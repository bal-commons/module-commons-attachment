import commons/service_commons.webhook;

# Lifecycle of a case. Only applications create, reopen and close cases; subjects submit them.
public enum CaseStatus {
    OPEN,
    SUBMITTED,
    CLOSED
}

# Where file content is stored.
public enum StorageType {
    DATABASE,
    FILESYSTEM
}

# What an admin role may do with every case in the namespace.
public enum AdminPermission {
    READ = "read",
    DELETE = "delete",
    REOPEN = "reopen",
    CLOSE = "close"
}

# A configurable admin role and the permissions it grants.
public type AdminRole record {|
    # Role name as it appears in the roles claim
    string role;
    # Granted permissions
    AdminPermission[] permissions;
|};

# A slot to create: one thing the subject is asked to upload.
public type NewSlot record {|
    # Key, e.g. `leak-photo` (letters, digits, `_`, `-`)
    string name;
    # Label shown in the UI; defaults to the name
    string label?;
    # Guidance shown in the UI
    string description?;
    # Accepted media types; `image/*` matches any image; empty accepts any
    string[] mimeTypes = [];
    # Largest file; defaults to the service's `maxFileBytes`
    int maxBytes?;
    # Files needed before the case can be submitted; 0 makes the slot optional
    int minFiles = 1;
    # Most files the slot holds
    int maxFiles = 1;
|};

# A slot of a case.
public type Slot record {|
    # Key
    string name;
    # Label shown in the UI
    string label;
    # Guidance shown in the UI
    string description?;
    # Accepted media types; empty accepts any
    string[] mimeTypes;
    # Largest file
    int maxBytes;
    # Files needed before submission
    int minFiles;
    # Most files
    int maxFiles;
    # Files uploaded
    int fileCount;
    # Whether `fileCount >= minFiles`
    boolean satisfied;
|};

# A case to create.
public type NewCase record {|
    # Ties the case to a workflow instance; not unique
    string correlationId?;
    # Makes retries safe: a second create with the same key returns the first case
    string idempotencyKey?;
    # Title shown to the subjects
    string title;
    # Longer instructions
    string description?;
    # Users allowed to upload
    string[] subjects;
    # What to upload
    NewSlot[] slots;
    # Participants whose webhooks receive the case's events; defaults to the creator
    string[] watchers?;
    # Submits the case as soon as every slot is satisfied
    boolean autoSubmit = false;
    # RFC 3339 deadline shown to the subjects
    string dueAt?;
    # Structured data for the UI
    json metadata?;
|};

# An uploaded file.
public type Attachment record {|
    # ULID
    string id;
    # Case ID
    string caseId;
    # Slot name
    string slot;
    # File name as uploaded, without any path
    string fileName;
    # Media type, sniffed from the content when recognised
    string mimeType;
    # Size in bytes
    int sizeBytes;
    # Hex SHA-256 of the content
    string sha256;
    # Uploader's user ID
    string uploadedBy;
    # RFC 3339 upload time
    string uploadedAt;
|};

# A case.
public type Case record {|
    # ULID
    string id;
    # Correlation ID; the case ID when none was given
    string correlationId;
    # Title
    string title;
    # Instructions
    string description?;
    # OPEN, SUBMITTED or CLOSED
    CaseStatus status;
    # Users allowed to upload
    string[] subjects;
    # Participants notified by webhook
    string[] watchers;
    # What to upload
    Slot[] slots;
    # Uploaded files; present when a single case is read
    Attachment[] files?;
    # Whether the case submits itself when complete
    boolean autoSubmit;
    # Who created it
    string createdBy;
    # RFC 3339 creation time
    string createdAt;
    # RFC 3339 time of the latest change
    string updatedAt;
    # RFC 3339 deadline
    string dueAt?;
    # RFC 3339 submission time
    string submittedAt?;
    # Who submitted it
    string submittedBy?;
    # RFC 3339 close time
    string closedAt?;
    # Who closed it
    string closedBy?;
    # Why it was last reopened or closed
    string statusReason?;
    # Structured data for the UI
    json metadata?;
|};

# One page of cases, newest first.
public type CasePage record {|
    # Cases on this page
    Case[] items;
    # Pass as `cursor` for the next page; absent on the last page
    string nextCursor?;
|};

# Filters for the caller's cases (as a subject).
public type CaseListOptions record {|
    # Only this status
    CaseStatus? status = ();
    # Only this correlation ID
    string? correlationId = ();
    # `nextCursor` of the previous page
    string? cursor = ();
    # Page size
    int? 'limit = ();
|};

# Filters for any case (admin).
public type AdminCaseListOptions record {|
    # Only cases of this subject
    string? subject = ();
    # Only this correlation ID
    string? correlationId = ();
    # Only this status
    CaseStatus? status = ();
    # `nextCursor` of the previous page
    string? cursor = ();
    # Page size
    int? 'limit = ();
|};

# Reopens or closes a case.
public type StatusChange record {|
    # Shown to the subjects, e.g. "The photo is blurry, please upload another"
    string reason?;
|};

# A short-lived download URL that needs no credentials, e.g. for an `<img>` tag.
public type AttachmentLink record {|
    # Absolute path under the service, including the signature
    string url;
    # RFC 3339 expiry time
    string expiresAt;
|};

# Single-use ticket that authenticates an SSE stream through its URL.
public type StreamTicket record {|
    # Pass as the `ticket` query parameter of `/stream`
    string ticket;
    # Seconds until the ticket expires
    int expiresIn;
|};

# A webhook to register.
public type NewWebhook webhook:NewSubscription;
# A registered webhook.
public type Webhook webhook:Subscription;
# A newly registered webhook with its secret.
public type CreatedWebhook webhook:CreatedSubscription;
# One webhook delivery.
public type WebhookDelivery webhook:Delivery;

# SSE: a case was created for the caller.
public const EVENT_CASE_CREATED = "case.created";
# SSE and webhook: a file was uploaded.
public const EVENT_FILE_UPLOADED = "attachment.uploaded";
# SSE and webhook: a file was deleted.
public const EVENT_FILE_DELETED = "attachment.deleted";
# SSE and webhook: the case was submitted.
public const EVENT_CASE_SUBMITTED = "case.submitted";
# SSE and webhook: the case was reopened for more uploads.
public const EVENT_CASE_REOPENED = "case.reopened";
# SSE and webhook: the case was closed.
public const EVENT_CASE_CLOSED = "case.closed";
