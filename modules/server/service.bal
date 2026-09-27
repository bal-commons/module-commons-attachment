import ballerina/http;
import ballerina/mime;
import commons/attachment;
import commons/service_commons;
import commons/service_commons.auth as sauth;

const NAME_PATTERN = "[A-Za-z0-9_-]{1,64}";

final http:InterceptableService attachmentService = @http:ServiceConfig {
    cors: {
        allowOrigins: corsAllowOrigins,
        allowHeaders: ["Authorization", "Content-Type", sauth:HEADER_USER_ID, sauth:HEADER_USER_ROLES,
            sauth:HEADER_USER_SCOPES, auth.apiKeyHeader],
        allowMethods: ["GET", "POST", "DELETE", "OPTIONS"]
    }
} isolated service object {

    public isolated function createInterceptors() returns [sauth:AuthInterceptor, service_commons:ErrorInterceptor] =>
        [new (authenticator, tickets), new];

    isolated resource function post cases(http:RequestContext ctx, @http:Payload attachment:NewCase body)
            returns http:Created|http:Ok|http:BadRequest|http:Forbidden|error {
        sauth:CallerIdentity caller = check sauth:callerOf(ctx);
        if !sauth:holdsScope(caller, scopeCreate) {
            return service_commons:forbidden(string `Creating cases requires scope '${scopeCreate}'`);
        }
        string? invalid = validateCase(body);
        if invalid is string {
            return service_commons:badRequest(invalid);
        }
        [attachment:Case, boolean] [created, isNew] = check store.createCase(body, caller.userId, maxFileBytes);
        if !isNew {
            return <http:Ok>{body: created};
        }
        publish(created, attachment:EVENT_CASE_CREATED, created.toJson());
        return <http:Created>{body: created, headers: {"Location": string `${basePath}/cases/${created.id}`}};
    }

    isolated resource function get cases(http:RequestContext ctx, string? status = (), string? correlationId = (),
            string? cursor = (), int 'limit = 20) returns attachment:CasePage|http:BadRequest|http:Forbidden|error {
        sauth:CallerIdentity|http:Forbidden caller = check authorize(ctx, scopeUse);
        if caller is http:Forbidden {
            return caller;
        }
        string? invalid = validateStatus(status) ?: validateLimit('limit);
        if invalid is string {
            return service_commons:badRequest(invalid);
        }
        return store.listCases(caller.userId, status, correlationId, cursor, 'limit);
    }

    isolated resource function get admin/cases(http:RequestContext ctx, string? subject = (),
            string? correlationId = (), string? status = (), string? cursor = (), int 'limit = 20)
            returns attachment:CasePage|http:BadRequest|http:Forbidden|error {
        sauth:CallerIdentity caller = check sauth:callerOf(ctx);
        if !sauth:holdsScope(caller, scopeAdmin) && !hasPermission(caller, attachment:READ) {
            return service_commons:forbidden("Requires an admin role with 'read'");
        }
        string? invalid = validateStatus(status) ?: validateLimit('limit);
        if invalid is string {
            return service_commons:badRequest(invalid);
        }
        return store.listCases(subject, status, correlationId, cursor, 'limit);
    }

    isolated resource function get cases/[string id](http:RequestContext ctx)
            returns attachment:Case|http:NotFound|http:Forbidden|error {
        sauth:CallerIdentity|http:Forbidden caller = check authorize(ctx, scopeUse);
        if caller is http:Forbidden {
            return caller;
        }
        return readable(caller, id, true);
    }

    isolated resource function post cases/[string id]/slots/[string slotName]/files(http:RequestContext ctx,
            http:Request req, string? fileName = ())
            returns http:Created|http:BadRequest|http:Forbidden|http:NotFound|http:Conflict|http:PayloadTooLarge|error {
        sauth:CallerIdentity|http:Forbidden caller = check authorize(ctx, scopeUse);
        if caller is http:Forbidden {
            return caller;
        }
        attachment:Case|http:NotFound target = check readable(caller, id, false);
        if target is http:NotFound {
            return target;
        }
        if target.subjects.indexOf(caller.userId) is () {
            return service_commons:forbidden("Only the case's subjects upload");
        }
        attachment:Slot? slot = slotOf(target, slotName);
        if slot is () {
            return service_commons:notFound(string `Slot ${slotName} not found`);
        }
        Upload|http:BadRequest|http:PayloadTooLarge upload = check readUpload(req, slot, fileName);
        if upload !is Upload {
            return upload;
        }
        attachment:Attachment|error stored = store.upload(target, upload, caller.userId);
        if stored is error {
            return mapError(stored);
        }
        publish(target, attachment:EVENT_FILE_UPLOADED, {caseId: id, attachment: stored.toJson()});
        if target.autoSubmit {
            attachment:Case|error submitted = store.submit(target, caller.userId);
            if submitted is attachment:Case {
                publish(submitted, attachment:EVENT_CASE_SUBMITTED, submitted.toJson());
            }
        }
        dispatcher.dispatch();
        return <http:Created>{body: stored, headers: {"Location": string `${basePath}/cases/${id}/files/${stored.id}`}};
    }

    isolated resource function get cases/[string id]/files(http:RequestContext ctx)
            returns attachment:Attachment[]|http:NotFound|http:Forbidden|error {
        sauth:CallerIdentity|http:Forbidden caller = check authorize(ctx, scopeUse);
        if caller is http:Forbidden {
            return caller;
        }
        attachment:Case|http:NotFound target = check readable(caller, id, false);
        return target is http:NotFound ? target : store.files(id);
    }

    isolated resource function get cases/[string id]/files/[string fileId](http:RequestContext ctx)
            returns attachment:Attachment|http:NotFound|http:Forbidden|error {
        sauth:CallerIdentity|http:Forbidden caller = check authorize(ctx, scopeUse);
        if caller is http:Forbidden {
            return caller;
        }
        attachment:Attachment|http:NotFound file = check readableFile(caller, id, fileId);
        return file;
    }

    isolated resource function get cases/[string id]/files/[string fileId]/content(http:RequestContext ctx,
            boolean inline = false) returns http:Response|http:NotFound|http:Forbidden|error {
        sauth:CallerIdentity|http:Forbidden caller = check authorize(ctx, scopeUse);
        if caller is http:Forbidden {
            return caller;
        }
        attachment:Attachment|http:NotFound file = check readableFile(caller, id, fileId);
        if file is http:NotFound {
            return file;
        }
        return contentResponse(check store.content(fileId), file.fileName, file.mimeType, inline);
    }

    isolated resource function post cases/[string id]/files/[string fileId]/link(http:RequestContext ctx)
            returns attachment:AttachmentLink|http:NotFound|http:Forbidden|error {
        sauth:CallerIdentity|http:Forbidden caller = check authorize(ctx, scopeUse);
        if caller is http:Forbidden {
            return caller;
        }
        attachment:Attachment|http:NotFound file = check readableFile(caller, id, fileId);
        if file is http:NotFound {
            return file;
        }
        [string, int] [url, expires] = check linkFor(fileId);
        return {url, expiresAt: service_commons:toIso(expires * 1000)};
    }

    isolated resource function delete cases/[string id]/files/[string fileId](http:RequestContext ctx)
            returns http:NoContent|http:NotFound|http:Forbidden|http:Conflict|http:BadRequest|error {
        sauth:CallerIdentity|http:Forbidden caller = check authorize(ctx, scopeUse);
        if caller is http:Forbidden {
            return caller;
        }
        attachment:Case|http:NotFound target = check readable(caller, id, false);
        if target is http:NotFound {
            return target;
        }
        attachment:Attachment? file = check store.getFile(id, fileId);
        if file is () {
            return service_commons:notFound(string `File ${fileId} not found`);
        }
        boolean asAdmin = sauth:holdsScope(caller, scopeAdmin) || hasPermission(caller, attachment:DELETE);
        if !asAdmin && file.uploadedBy != caller.userId {
            return service_commons:forbidden("Only the uploader or an admin role with 'delete' deletes a file");
        }
        error? deleted = store.deleteFile(target, file, caller.userId, asAdmin);
        if deleted is error {
            return mapError(deleted);
        }
        publish(target, attachment:EVENT_FILE_DELETED, {caseId: id, attachment: file.toJson()});
        dispatcher.dispatch();
        return http:NO_CONTENT;
    }

    isolated resource function post cases/[string id]/submit(http:RequestContext ctx)
            returns attachment:Case|http:NotFound|http:Forbidden|http:Conflict|http:BadRequest|error {
        sauth:CallerIdentity|http:Forbidden caller = check authorize(ctx, scopeUse);
        if caller is http:Forbidden {
            return caller;
        }
        attachment:Case|http:NotFound target = check readable(caller, id, false);
        if target is http:NotFound {
            return target;
        }
        if target.subjects.indexOf(caller.userId) is () {
            return service_commons:forbidden("Only the case's subjects submit");
        }
        attachment:Case|error submitted = store.submit(target, caller.userId);
        if submitted is error {
            return mapError(submitted);
        }
        publish(submitted, attachment:EVENT_CASE_SUBMITTED, submitted.toJson());
        dispatcher.dispatch();
        return submitted;
    }

    isolated resource function post cases/[string id]/reopen(http:RequestContext ctx,
            @http:Payload attachment:StatusChange? body)
            returns attachment:Case|http:NotFound|http:Forbidden|http:Conflict|http:BadRequest|error {
        return changeStatus(ctx, id, body, attachment:REOPEN);
    }

    isolated resource function post cases/[string id]/close(http:RequestContext ctx,
            @http:Payload attachment:StatusChange? body)
            returns attachment:Case|http:NotFound|http:Forbidden|http:Conflict|http:BadRequest|error {
        return changeStatus(ctx, id, body, attachment:CLOSE);
    }

    isolated resource function post webhooks(http:RequestContext ctx, @http:Payload attachment:NewWebhook body)
            returns http:Created|http:BadRequest|http:Forbidden|error {
        http:Forbidden? denied = check requireWebhookScope(ctx);
        if denied is http:Forbidden {
            return denied;
        }
        if body.participantId.trim() == "" || !(body.url.startsWith("http://") || body.url.startsWith("https://")) {
            return service_commons:badRequest("participantId and an http(s) url are required");
        }
        return <http:Created>{body: check dispatcher.register(body)};
    }

    isolated resource function get webhooks(http:RequestContext ctx, string? participantId = ())
            returns attachment:Webhook[]|http:Forbidden|error {
        http:Forbidden? denied = check requireWebhookScope(ctx);
        return denied ?: dispatcher.list(participantId);
    }

    isolated resource function get webhooks/[string id]/deliveries(http:RequestContext ctx)
            returns attachment:WebhookDelivery[]|http:Forbidden|http:NotFound|error {
        http:Forbidden? denied = check requireWebhookScope(ctx);
        if denied is http:Forbidden {
            return denied;
        }
        if check dispatcher.get(id) is () {
            return service_commons:notFound(string `Webhook ${id} not found`);
        }
        return dispatcher.deliveries(id);
    }

    isolated resource function delete webhooks/[string id](http:RequestContext ctx)
            returns http:NoContent|http:Forbidden|http:NotFound|error {
        http:Forbidden? denied = check requireWebhookScope(ctx);
        if denied is http:Forbidden {
            return denied;
        }
        return check dispatcher.remove(id) ? http:NO_CONTENT : service_commons:notFound(string `Webhook ${id} not found`);
    }

    isolated resource function post stream\-ticket(http:RequestContext ctx)
            returns attachment:StreamTicket|http:Forbidden|error {
        sauth:CallerIdentity|http:Forbidden caller = check authorize(ctx, scopeUse);
        if caller is http:Forbidden {
            return caller;
        }
        return {ticket: tickets.issue(caller), expiresIn: tickets.ttlSeconds()};
    }

    // Events of the cases the caller is a subject or creator of, and of every case for admin roles with 'read'.
    isolated resource function get 'stream(http:RequestContext ctx)
            returns stream<http:SseEvent, error?>|http:Forbidden|error {
        sauth:CallerIdentity|http:Forbidden caller = check authorize(ctx, scopeUse);
        if caller is http:Forbidden {
            return caller;
        }
        return hub.open(["user:" + caller.userId, ...from string role in caller.roles select "role:" + role]);
    }
};

isolated function authorize(http:RequestContext ctx, string scope) returns sauth:CallerIdentity|http:Forbidden|error {
    sauth:CallerIdentity caller = check sauth:callerOf(ctx);
    return authenticator.hasScope(caller, scope) ? caller : service_commons:forbidden(string `Requires scope '${scope}'`);
}

isolated function requireWebhookScope(http:RequestContext ctx) returns http:Forbidden?|error {
    sauth:CallerIdentity caller = check sauth:callerOf(ctx);
    return sauth:holdsScope(caller, scopeWebhooks) ? () :
        service_commons:forbidden(string `Requires scope '${scopeWebhooks}'`);
}

isolated function hasPermission(sauth:CallerIdentity caller, attachment:AdminPermission permission) returns boolean {
    foreach attachment:AdminRole adminRole in adminRoles {
        if caller.roles.indexOf(adminRole.role) != () && adminRole.permissions.indexOf(permission) != () {
            return true;
        }
    }
    return false;
}

// Subjects, the creator, the admin scope and admin roles with 'read' see a case; others get 404.
isolated function readable(sauth:CallerIdentity caller, string id, boolean withFiles)
        returns attachment:Case|http:NotFound|error {
    attachment:Case? found = check store.getCase(id, withFiles);
    if found is attachment:Case && (found.subjects.indexOf(caller.userId) != () || found.createdBy == caller.userId
            || sauth:holdsScope(caller, scopeAdmin) || hasPermission(caller, attachment:READ)) {
        return found;
    }
    return service_commons:notFound(string `Case ${id} not found`);
}

isolated function readableFile(sauth:CallerIdentity caller, string caseId, string fileId)
        returns attachment:Attachment|http:NotFound|error {
    attachment:Case|http:NotFound target = check readable(caller, caseId, false);
    if target is http:NotFound {
        return target;
    }
    attachment:Attachment? file = check store.getFile(caseId, fileId);
    return file ?: service_commons:notFound(string `File ${fileId} not found`);
}

// The creator, a service with the manage scope, or an admin role with the permission reopens and closes.
isolated function changeStatus(http:RequestContext ctx, string id, attachment:StatusChange? body,
        attachment:AdminPermission permission)
        returns attachment:Case|http:NotFound|http:Forbidden|http:Conflict|http:BadRequest|error {
    sauth:CallerIdentity caller = check sauth:callerOf(ctx);
    attachment:Case? found = check store.getCase(id, false);
    if found is () {
        return service_commons:notFound(string `Case ${id} not found`);
    }
    boolean allowed = found.createdBy == caller.userId || sauth:holdsScope(caller, scopeManage)
        || sauth:holdsScope(caller, scopeAdmin) || hasPermission(caller, permission);
    if !allowed {
        return found.subjects.indexOf(caller.userId) != () || hasPermission(caller, attachment:READ)
            ? service_commons:forbidden(string `Requires an admin role with '${permission}'`)
            : service_commons:notFound(string `Case ${id} not found`);
    }
    string? reason = body?.reason;
    attachment:Case|error changed = permission == attachment:REOPEN ? store.reopen(found, caller.userId, reason)
        : store.close(found, caller.userId, reason);
    if changed is error {
        return mapError(changed);
    }
    publish(changed, permission == attachment:REOPEN ? attachment:EVENT_CASE_REOPENED : attachment:EVENT_CASE_CLOSED,
        changed.toJson());
    dispatcher.dispatch();
    return changed;
}

// Reads a raw body (`?fileName=`) or the first file part of a multipart form, and checks it against the slot.
isolated function readUpload(http:Request req, attachment:Slot slot, string? fileName)
        returns Upload|http:BadRequest|http:PayloadTooLarge|error {
    string contentType = req.getContentType();
    byte[] content;
    string name;
    string declared;
    if contentType.toLowerAscii().startsWith(mime:MULTIPART_FORM_DATA) {
        mime:Entity? part = ();
        foreach mime:Entity candidate in check req.getBodyParts() {
            if candidate.getContentDisposition().fileName != "" {
                part = candidate;
                break;
            }
        }
        if part is () {
            return service_commons:badRequest("The form has no file part");
        }
        content = check part.getByteArray();
        name = part.getContentDisposition().fileName;
        declared = part.getContentType();
    } else {
        content = check req.getBinaryPayload();
        name = fileName ?: "file";
        declared = contentType;
    }
    if content.length() == 0 {
        return service_commons:badRequest("The file is empty");
    }
    if content.length() > slot.maxBytes {
        return <http:PayloadTooLarge>{body: <service_commons:ErrorBody>{code: "PAYLOAD_TOO_LARGE",
            message: string `Slot ${slot.name} accepts files up to ${slot.maxBytes} bytes`}};
    }
    string claimed = normalizeMime(declared == "" ? "application/octet-stream" : declared);
    string? sniffed = sniff(content);
    if sniffed is string && claimed != "application/octet-stream" && claimed != sniffed {
        return service_commons:badRequest(string `The content is ${sniffed}, not ${claimed}`);
    }
    string effective = sniffed ?: claimed;
    if !accepts(slot.mimeTypes, effective) {
        return service_commons:badRequest(string `Slot ${slot.name} accepts ${string:'join(", ", ...slot.mimeTypes)}`);
    }
    return {slot: slot.name, fileName: sanitizeFileName(name), mimeType: effective, content};
}

isolated function slotOf(attachment:Case target, string name) returns attachment:Slot? {
    foreach attachment:Slot slot in target.slots {
        if slot.name == name {
            return slot;
        }
    }
    return ();
}

// Subjects, the creator and admin roles with 'read' watch a case over SSE.
isolated function publish(attachment:Case target, string event, json data) {
    string[] targets = ["user:" + target.createdBy, ...from string subject in target.subjects select "user:" + subject];
    foreach attachment:AdminRole adminRole in adminRoles {
        attachment:AdminPermission read = attachment:READ;
        if adminRole.permissions.indexOf(read) != () {
            targets.push("role:" + adminRole.role);
        }
    }
    hub.publish({id: service_commons:newId(), event, data}, targets);
}

isolated function mapError(error err) returns http:BadRequest|http:NotFound|http:Conflict|error {
    if err is NotFoundError {
        return service_commons:notFound(err.message());
    }
    if err is ConflictError {
        return service_commons:alreadyExists(err.message());
    }
    return err;
}

isolated function validateCase(attachment:NewCase input) returns string? {
    if input.title.trim() == "" || input.title.length() > 500 {
        return "title must be 1-500 characters";
    }
    if input.subjects.length() == 0 || input.subjects.length() > 20 {
        return "A case has 1-20 subjects";
    }
    foreach int i in 0 ..< input.subjects.length() {
        string subject = input.subjects[i];
        if subject.trim() == "" || subject.length() > 255 || input.subjects.indexOf(subject) != i {
            return "subjects must be distinct user IDs of 1-255 characters";
        }
    }
    if input.slots.length() == 0 || input.slots.length() > 20 {
        return "A case has 1-20 slots";
    }
    string[] names = input.slots.map(s => s.name);
    foreach int i in 0 ..< input.slots.length() {
        attachment:NewSlot slot = input.slots[i];
        if !re `${NAME_PATTERN}`.isFullMatch(slot.name) || names.indexOf(slot.name) != i {
            return "slot names must be distinct: 1-64 letters, digits, '_' or '-'";
        }
        if slot.minFiles < 0 || slot.maxFiles < 1 || slot.minFiles > slot.maxFiles {
            return string `Slot ${slot.name} needs 0 <= minFiles <= maxFiles and maxFiles >= 1`;
        }
        int maxBytes = slot?.maxBytes ?: maxFileBytes;
        if maxBytes < 1 || maxBytes > maxFileBytes {
            return string `Slot ${slot.name} maxBytes must be 1-${maxFileBytes}`;
        }
    }
    if (input?.watchers ?: []).length() > 20 {
        return "A case has at most 20 watchers";
    }
    if (input?.correlationId ?: "x").length() > 255 || input?.correlationId == "" {
        return "correlationId must be 1-255 characters";
    }
    if (input?.idempotencyKey ?: "").length() > 255 {
        return "idempotencyKey must be at most 255 characters";
    }
    string? dueAt = input?.dueAt;
    if dueAt is string && service_commons:fromIso(dueAt) is error {
        return "dueAt must be an RFC 3339 timestamp";
    }
    return ();
}

isolated function validateStatus(string? status) returns string? =>
    status is () || status is attachment:CaseStatus ? () : "status must be OPEN, SUBMITTED or CLOSED";

isolated function validateLimit(int 'limit) returns string? =>
    'limit >= 1 && 'limit <= maxPageSize ? () : string `limit must be between 1 and ${maxPageSize}`;
