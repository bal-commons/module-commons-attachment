import ballerina/crypto;
import ballerina/log;
import ballerina/sql;
import ballerinax/java.jdbc;
import commons/attachment;
import commons/service_commons;
import commons/service_commons.db as sdb;
import commons/service_commons.webhook;

type NotFoundError distinct error;

type ConflictError distinct error;

type CaseRow record {|
    string id;
    string correlation_id;
    string title;
    string? description;
    string status;
    string watchers;
    int auto_submit;
    string created_by;
    int created_at;
    int updated_at;
    int? due_at;
    int? submitted_at;
    string? submitted_by;
    int? closed_at;
    string? closed_by;
    string? status_reason;
    string? metadata;
|};

type SubjectRow record {|
    string case_id;
    string user_id;
|};

type SlotRow record {|
    string case_id;
    string name;
    int slot_order;
    string label;
    string? description;
    string mime_types;
    int max_bytes;
    int min_files;
    int max_files;
    int file_count;
|};

type FileRow record {|
    string id;
    string case_id;
    string slot;
    string file_name;
    string mime_type;
    int size_bytes;
    string sha256;
    string uploaded_by;
    int uploaded_at;
|};

// The file to store, already validated against its slot.
type Upload record {|
    string slot;
    string fileName;
    string mimeType;
    byte[] content;
|};

isolated class Store {
    private final jdbc:Client db;
    private final string ns;
    private final string caseTable;
    private final string subjectTable;
    private final string slotTable;
    private final string fileTable;
    private final BlobStore blobs;
    private final webhook:Webhooks webhooks;

    isolated function init(jdbc:Client db, string ns, string prefix, BlobStore blobs, webhook:Webhooks webhooks) {
        self.db = db;
        self.ns = ns;
        self.caseTable = prefix + "case";
        self.subjectTable = prefix + "subject";
        self.slotTable = prefix + "slot";
        self.fileTable = prefix + "file";
        self.blobs = blobs;
        self.webhooks = webhooks;
    }

    // A repeated idempotency key returns the stored case with `false`.
    isolated function createCase(attachment:NewCase input, string createdBy, int defaultMaxBytes)
            returns [attachment:Case, boolean]|error {
        final string? key = input?.idempotencyKey;
        if key is string {
            attachment:Case? existing = check self.caseByKey(key);
            if existing is attachment:Case {
                return [existing, false];
            }
        }
        final string id = service_commons:newId();
        final int now = service_commons:nowMillis();
        string? dueAt = input?.dueAt;
        final int? dueMillis = dueAt is string ? check service_commons:fromIso(dueAt) : ();
        json metadata = input?.metadata;
        final string? metadataText = metadata is () ? () : metadata.toJsonString();
        final string watchers = string:'join(",", ...(input?.watchers ?: [createdBy]));
        final attachment:NewCase & readonly request = input.cloneReadOnly();
        anydata|error stored = sdb:atomic(isolated function () returns anydata|error {
                _ = check self.db->execute(sql:queryConcat(`INSERT INTO `, sdb:ident(self.caseTable),
                    ` (id, ns, idempotency_key, correlation_id, title, description, status, watchers, auto_submit,
                    created_by, created_at, updated_at, due_at, metadata) VALUES (${id}, ${self.ns}, ${key},
                    ${request?.correlationId ?: id}, ${request.title}, ${request?.description}, ${attachment:OPEN},
                    ${watchers}, ${request.autoSubmit ? 1 : 0}, ${createdBy}, ${now}, ${now}, ${dueMillis},
                    ${metadataText})`));
                foreach string subject in request.subjects {
                    _ = check self.db->execute(sql:queryConcat(`INSERT INTO `, sdb:ident(self.subjectTable),
                        ` (case_id, user_id) VALUES (${id}, ${subject})`));
                }
                foreach [int, attachment:NewSlot] [i, slot] in request.slots.enumerate() {
                    _ = check self.db->execute(sql:queryConcat(`INSERT INTO `, sdb:ident(self.slotTable),
                        ` (case_id, name, slot_order, label, description, mime_types, max_bytes, min_files, max_files,
                        file_count) VALUES (${id}, ${slot.name}, ${i}, ${slot?.label ?: slot.name}, ${slot?.description},
                        ${string:'join(",", ...slot.mimeTypes)}, ${slot?.maxBytes ?: defaultMaxBytes}, ${slot.minFiles},
                        ${slot.maxFiles}, 0)`));
                }
                return ();
        });
        if stored is error {
            error e = stored;
            string? repeatedKey = key;
            if repeatedKey is string && sdb:isDuplicateKey(e) {
                attachment:Case? raced = check self.caseByKey(repeatedKey);
                if raced is attachment:Case {
                    return [raced, false];
                }
            }
            return e;
        }
        return [check (check self.getCase(id, false)).ensureType(), true];
    }

    isolated function getCase(string id, boolean withFiles) returns attachment:Case?|error {
        attachment:Case[] found = check self.cases(sql:queryConcat(self.selectCases(()), ` AND c.id = ${id}`));
        if found.length() == 0 {
            return ();
        }
        attachment:Case result = found[0];
        if withFiles {
            result.files = check self.files(id);
        }
        return result;
    }

    isolated function caseByKey(string key) returns attachment:Case?|error {
        attachment:Case[] found = check self.cases(sql:queryConcat(self.selectCases(()),
            ` AND c.idempotency_key = ${key}`));
        return found.length() == 0 ? () : found[0];
    }

    isolated function listCases(string? subject, string? status, string? correlationId, string? cursor, int 'limit)
            returns attachment:CasePage|error {
        sql:ParameterizedQuery query = self.selectCases(subject);
        if status is string {
            query = sql:queryConcat(query, ` AND c.status = ${status}`);
        }
        if correlationId is string {
            query = sql:queryConcat(query, ` AND c.correlation_id = ${correlationId}`);
        }
        if cursor is string {
            query = sql:queryConcat(query, ` AND c.id < ${cursor}`);
        }
        attachment:Case[] found = check self.cases(sql:queryConcat(query, ` ORDER BY c.id DESC LIMIT ${'limit + 1}`));
        attachment:CasePage page = {items: found.length() > 'limit ? found.slice(0, 'limit) : found};
        if found.length() > 'limit {
            page.nextCursor = page.items[page.items.length() - 1].id;
        }
        return page;
    }

    isolated function files(string caseId) returns attachment:Attachment[]|error {
        stream<FileRow, sql:Error?> rows = self.db->query(sql:queryConcat(self.selectFiles(),
            ` WHERE case_id = ${caseId} ORDER BY id`));
        return from FileRow row in rows select toAttachment(row);
    }

    isolated function getFile(string caseId, string fileId) returns attachment:Attachment?|error {
        stream<FileRow, sql:Error?> rows = self.db->query(sql:queryConcat(self.selectFiles(),
            ` WHERE case_id = ${caseId} AND id = ${fileId}`));
        attachment:Attachment[] found = check from FileRow row in rows select toAttachment(row);
        return found.length() == 0 ? () : found[0];
    }

    // File name and media type of a file in this namespace, for signed links.
    isolated function fileInfo(string fileId) returns [string, string]?|error {
        stream<record {|string file_name; string mime_type;|}, sql:Error?> rows = self.db->query(sql:queryConcat(
            `SELECT f.file_name, f.mime_type FROM `, sdb:ident(self.fileTable), ` f JOIN `, sdb:ident(self.caseTable),
            ` c ON c.id = f.case_id WHERE c.ns = ${self.ns} AND f.id = ${fileId}`));
        [string, string][] found = check from var row in rows select [row.file_name, row.mime_type];
        return found.length() == 0 ? () : found[0];
    }

    isolated function content(string fileId) returns byte[]|error => self.blobs.get(fileId);

    isolated function upload(attachment:Case target, Upload file, string uploader) returns attachment:Attachment|error {
        final string id = service_commons:newId();
        final int now = service_commons:nowMillis();
        final boolean inTransaction = self.blobs.isTransactional();
        if !inTransaction {
            check self.blobs.put(id, file.content);
        }
        FileRow row = {
            id,
            case_id: target.id,
            slot: file.slot,
            file_name: file.fileName,
            mime_type: file.mimeType,
            size_bytes: file.content.length(),
            sha256: crypto:hashSha256(file.content).toBase16(),
            uploaded_by: uploader,
            uploaded_at: now
        };
        final attachment:Attachment & readonly stored = toAttachment(row).cloneReadOnly();
        final FileRow & readonly file_ = row.cloneReadOnly();
        final attachment:Case & readonly owner = target.cloneReadOnly();
        final byte[] & readonly content = file.content.cloneReadOnly();
        anydata|error saved = sdb:atomic(isolated function () returns anydata|error {
                check self.touchOpen(owner.id, now);
                sql:ExecutionResult claimed = check self.db->execute(sql:queryConcat(`UPDATE `,
                    sdb:ident(self.slotTable), ` SET file_count = file_count + 1 WHERE case_id = ${owner.id}
                    AND name = ${file_.slot} AND file_count < max_files`));
                if claimed.affectedRowCount != 1 {
                    return error ConflictError(string `Slot ${file_.slot} is full`);
                }
                _ = check self.db->execute(sql:queryConcat(`INSERT INTO `, sdb:ident(self.fileTable),
                    ` (id, case_id, slot, file_name, mime_type, size_bytes, sha256, uploaded_by, uploaded_at)
                    VALUES (${id}, ${owner.id}, ${file_.slot}, ${file_.file_name}, ${file_.mime_type},
                    ${file_.size_bytes}, ${file_.sha256}, ${uploader}, ${now})`));
                if inTransaction {
                    check self.blobs.put(id, content);
                }
                _ = check self.webhooks.enqueue(attachment:EVENT_FILE_UPLOADED, recipients(owner, uploader),
                    fileEvent(owner, stored), owner.correlationId);
                return ();
        });
        if saved is error {
            error e = saved;
            if !inTransaction {
                error? cleanup = self.blobs.remove(id);
                if cleanup is error {
                    log:printWarn(string `Could not remove the content of failed upload ${id}`, 'error = cleanup);
                }
            }
            return e;
        }
        return stored;
    }

    // Uploaders delete while the case is open; admins at any time.
    isolated function deleteFile(attachment:Case target, attachment:Attachment file, string actor, boolean asAdmin)
            returns error? {
        final int now = service_commons:nowMillis();
        final attachment:Case & readonly owner = target.cloneReadOnly();
        final attachment:Attachment & readonly removedFile = file.cloneReadOnly();
        _ = check sdb:atomic(isolated function () returns anydata|error {
            if asAdmin {
                _ = check self.db->execute(sql:queryConcat(`UPDATE `, sdb:ident(self.caseTable),
                    ` SET updated_at = ${now} WHERE id = ${owner.id}`));
            } else {
                check self.touchOpen(owner.id, now);
            }
            sql:ExecutionResult removed = check self.db->execute(sql:queryConcat(`DELETE FROM `,
                sdb:ident(self.fileTable), ` WHERE case_id = ${owner.id} AND id = ${removedFile.id}`));
            if removed.affectedRowCount != 1 {
                return error NotFoundError(string `File ${removedFile.id} not found`);
            }
            _ = check self.db->execute(sql:queryConcat(`UPDATE `, sdb:ident(self.slotTable),
                ` SET file_count = file_count - 1 WHERE case_id = ${owner.id} AND name = ${removedFile.slot}`));
            if self.blobs.isTransactional() {
                check self.blobs.remove(removedFile.id);
            }
            _ = check self.webhooks.enqueue(attachment:EVENT_FILE_DELETED, recipients(owner, actor),
                fileEvent(owner, removedFile), owner.correlationId);
            return ();
        });
        if !self.blobs.isTransactional() {
            check self.blobs.remove(file.id);
        }
    }

    isolated function submit(attachment:Case target, string actor) returns attachment:Case|error {
        final int now = service_commons:nowMillis();
        final attachment:Case & readonly owner = target.cloneReadOnly();
        _ = check sdb:atomic(isolated function () returns anydata|error {
            int missing = check self.db->queryRow(sql:queryConcat(`SELECT COUNT(*) FROM `, sdb:ident(self.slotTable),
                ` WHERE case_id = ${owner.id} AND file_count < min_files`));
            if missing > 0 {
                return error ConflictError(string `${missing} slot(s) still need files`);
            }
            sql:ExecutionResult result = check self.db->execute(sql:queryConcat(`UPDATE `, sdb:ident(self.caseTable),
                ` SET status = ${attachment:SUBMITTED}, submitted_at = ${now}, submitted_by = ${actor},
                updated_at = ${now} WHERE id = ${owner.id} AND status = ${attachment:OPEN}`));
            if result.affectedRowCount != 1 {
                return error ConflictError("Case is not open");
            }
            attachment:Case submitted = check (check self.getCase(owner.id, true)).ensureType();
            _ = check self.webhooks.enqueue(attachment:EVENT_CASE_SUBMITTED, recipients(owner, actor),
                {'case: submitted.toJson()}, owner.correlationId);
            return ();
        });
        return check (check self.getCase(target.id, true)).ensureType();
    }

    isolated function reopen(attachment:Case target, string actor, string? reason) returns attachment:Case|error {
        return self.changeStatus(target, actor, reason, attachment:OPEN, [attachment:SUBMITTED],
            attachment:EVENT_CASE_REOPENED);
    }

    isolated function close(attachment:Case target, string actor, string? reason) returns attachment:Case|error {
        return self.changeStatus(target, actor, reason, attachment:CLOSED, [attachment:OPEN, attachment:SUBMITTED],
            attachment:EVENT_CASE_CLOSED);
    }

    isolated function changeStatus(attachment:Case target, string actor, string? reason, attachment:CaseStatus next,
            attachment:CaseStatus[] allowed, string event) returns attachment:Case|error {
        final int now = service_commons:nowMillis();
        final attachment:Case & readonly owner = target.cloneReadOnly();
        final attachment:CaseStatus[] & readonly previous = allowed.cloneReadOnly();
        _ = check sdb:atomic(isolated function () returns anydata|error {
            sql:ParameterizedQuery closing = next == attachment:CLOSED ? `, closed_at = ${now}, closed_by = ${actor}`
                : ``;
            sql:ExecutionResult result = check self.db->execute(sql:queryConcat(`UPDATE `, sdb:ident(self.caseTable),
                ` SET status = ${next}, status_reason = ${reason}, updated_at = ${now}`, closing,
                ` WHERE id = ${owner.id} AND status IN (`, sql:arrayFlattenQuery(previous), `)`));
            if result.affectedRowCount != 1 {
                return error ConflictError(string `Case is ${owner.status}`);
            }
            attachment:Case changed = check (check self.getCase(owner.id, false)).ensureType();
            _ = check self.webhooks.enqueue(event, recipients(owner, actor), {'case: changed.toJson()},
                owner.correlationId);
            return ();
        });
        return check (check self.getCase(target.id, true)).ensureType();
    }

    // Locks the case row, so uploads, deletes and submission are serialised, and checks it is open.
    isolated function touchOpen(string caseId, int now) returns error? {
        sql:ExecutionResult result = check self.db->execute(sql:queryConcat(`UPDATE `, sdb:ident(self.caseTable),
            ` SET updated_at = ${now} WHERE id = ${caseId} AND status = ${attachment:OPEN}`));
        if result.affectedRowCount != 1 {
            return error ConflictError("Case is not open for uploads");
        }
    }

    isolated function selectCases(string? subject) returns sql:ParameterizedQuery {
        sql:ParameterizedQuery columns = `SELECT c.id, c.correlation_id, c.title, c.description, c.status, c.watchers,
            c.auto_submit, c.created_by, c.created_at, c.updated_at, c.due_at, c.submitted_at, c.submitted_by,
            c.closed_at, c.closed_by, c.status_reason, c.metadata FROM `;
        if subject is () {
            return sql:queryConcat(columns, sdb:ident(self.caseTable), ` c WHERE c.ns = ${self.ns}`);
        }
        return sql:queryConcat(columns, sdb:ident(self.caseTable), ` c JOIN `, sdb:ident(self.subjectTable),
            ` s ON s.case_id = c.id AND s.user_id = ${subject} WHERE c.ns = ${self.ns}`);
    }

    isolated function cases(sql:ParameterizedQuery query) returns attachment:Case[]|error {
        stream<CaseRow, sql:Error?> result = self.db->query(query);
        CaseRow[] rows = check from CaseRow row in result select row;
        if rows.length() == 0 {
            return [];
        }
        sql:ParameterizedQuery ids = sql:arrayFlattenQuery(rows.map(row => row.id));
        stream<SubjectRow, sql:Error?> subjectRows = self.db->query(sql:queryConcat(`SELECT case_id, user_id FROM `,
            sdb:ident(self.subjectTable), ` WHERE case_id IN (`, ids, `) ORDER BY case_id, user_id`));
        map<string[]> subjects = {};
        check from SubjectRow row in subjectRows
            do {
                string[] list = subjects[row.case_id] ?: [];
                list.push(row.user_id);
                subjects[row.case_id] = list;
            };
        stream<SlotRow, sql:Error?> slotRows = self.db->query(sql:queryConcat(`SELECT case_id, name, slot_order, label,
            description, mime_types, max_bytes, min_files, max_files, file_count FROM `, sdb:ident(self.slotTable),
            ` WHERE case_id IN (`, ids, `) ORDER BY case_id, slot_order`));
        map<attachment:Slot[]> slots = {};
        check from SlotRow row in slotRows
            do {
                attachment:Slot[] list = slots[row.case_id] ?: [];
                list.push(toSlot(row));
                slots[row.case_id] = list;
            };
        return from CaseRow row in rows
            select check toCase(row, subjects[row.id] ?: [], slots[row.id] ?: []);
    }

    isolated function selectFiles() returns sql:ParameterizedQuery =>
        sql:queryConcat(`SELECT id, case_id, slot, file_name, mime_type, size_bytes, sha256, uploaded_by, uploaded_at
            FROM `, sdb:ident(self.fileTable));
}

// Watchers other than the actor receive webhooks.
isolated function recipients(attachment:Case target, string actor) returns string[] =>
    from string watcher in target.watchers where watcher != actor select watcher;

isolated function fileEvent(attachment:Case target, attachment:Attachment file) returns json => {
    caseId: target.id,
    correlationId: target.correlationId,
    attachment: file.toJson()
};

isolated function splitList(string value) returns string[] =>
    from string item in re `,`.split(value) where item != "" select item;

isolated function toCase(CaseRow row, string[] subjects, attachment:Slot[] slots) returns attachment:Case|error {
    attachment:Case result = {
        id: row.id,
        correlationId: row.correlation_id,
        title: row.title,
        status: check row.status.ensureType(),
        subjects,
        watchers: splitList(row.watchers),
        slots,
        autoSubmit: row.auto_submit == 1,
        createdBy: row.created_by,
        createdAt: service_commons:toIso(row.created_at),
        updatedAt: service_commons:toIso(row.updated_at)
    };
    string? description = row.description;
    if description is string {
        result.description = description;
    }
    int? dueAt = row.due_at;
    if dueAt is int {
        result.dueAt = service_commons:toIso(dueAt);
    }
    int? submittedAt = row.submitted_at;
    if submittedAt is int {
        result.submittedAt = service_commons:toIso(submittedAt);
    }
    string? submittedBy = row.submitted_by;
    if submittedBy is string {
        result.submittedBy = submittedBy;
    }
    int? closedAt = row.closed_at;
    if closedAt is int {
        result.closedAt = service_commons:toIso(closedAt);
    }
    string? closedBy = row.closed_by;
    if closedBy is string {
        result.closedBy = closedBy;
    }
    string? reason = row.status_reason;
    if reason is string {
        result.statusReason = reason;
    }
    string? metadata = row.metadata;
    if metadata is string {
        result.metadata = check metadata.fromJsonString();
    }
    return result;
}

isolated function toSlot(SlotRow row) returns attachment:Slot {
    attachment:Slot slot = {
        name: row.name,
        label: row.label,
        mimeTypes: splitList(row.mime_types),
        maxBytes: row.max_bytes,
        minFiles: row.min_files,
        maxFiles: row.max_files,
        fileCount: row.file_count,
        satisfied: row.file_count >= row.min_files
    };
    string? description = row.description;
    if description is string {
        slot.description = description;
    }
    return slot;
}

isolated function toAttachment(FileRow row) returns attachment:Attachment => {
    id: row.id,
    caseId: row.case_id,
    slot: row.slot,
    fileName: row.file_name,
    mimeType: row.mime_type,
    sizeBytes: row.size_bytes,
    sha256: row.sha256,
    uploadedBy: row.uploaded_by,
    uploadedAt: service_commons:toIso(row.uploaded_at)
};
