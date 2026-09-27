# commons/attachment

A small file-upload service built around cases. An application (the workflow) creates a case and names who must
upload what. Its subjects upload into typed slots and submit. Admin roles manage the files.

| Module | Contents |
|---|---|
| `attachment` | Types and `Client`. Safe to import anywhere. |
| `attachment.server` | The HTTP service. Importing it starts the listener. |

## Run it inside an application

```ballerina
import ballerinax/postgresql.driver as _;
import commons/attachment.server as _;
```

```toml
[commons.attachment.server]
port = 9102                    # default
basePath = "/attachments/v1"   # default; signed links live under <basePath>/links
ns = "my-app"
storage = "DATABASE"           # or "FILESYSTEM" with storageDir
maxFileBytes = 10485760        # default 10 MB
linkSecret = "change-me"       # signs download links; random per process when empty
adminRoles = [
    {role = "PropertyManager", permissions = ["read", "delete"]},
    {role = "Auditor", permissions = ["read"]}
]

[commons.attachment.server.auth]
enableJwtAuth = true
jwksUrl = "https://idp.example.com/oauth2/jwks"
enforceScopes = true

[commons.attachment.server.db]
dbType = "POSTGRESQL"
url = "jdbc:postgresql://localhost:5432/myapp"

[[commons.attachment.server.webhooks]]
participantId = "agent:maintenance-triage"
url = "http://localhost:9090/agent/attachment-events"
secret = "change-me"
```

Other settings (see `modules/server/config.bal`): `tablePrefix` (`attachment_`), scope names, `linkTtlSeconds` (300),
`webhookDelivery`, `maxPageSize`, `ticketTtlSeconds`, `corsAllowOrigins`.

## Who may do what

| Action | Allowed for |
|---|---|
| Create a case | `attachment:case:create`, held explicitly: **users cannot create cases** |
| List own cases, read, download, create links | Subjects and the case's creator (`attachment:use`) |
| Upload, submit | Subjects |
| Delete a file | Its uploader while the case is OPEN; admin roles with `delete` at any time |
| Reopen / close | The creator, `attachment:case:manage`, or admin roles with `reopen` / `close` |
| Read every case, `GET /admin/cases` | Admin roles with `read`, or `attachment:admin` |
| Manage webhooks | `attachment:webhook:manage` |

Anyone else asking for a case gets `404`.

## Cases and slots

A slot is one thing to upload: `{name, label, description, mimeTypes, maxBytes, minFiles, maxFiles}`.
`mimeTypes` accepts patterns like `image/*`. `minFiles: 0` makes a slot optional. A case can be submitted once every
slot has `minFiles` files. With `autoSubmit`, the upload that completes the last slot submits the case.

Status goes `OPEN → SUBMITTED → OPEN` (reopen, e.g. "the photo is blurry") and then `CLOSED`, which is final. Uploads
are accepted only while the case is OPEN. `statusReason` carries the latest reopen or close reason to the subjects.

The content of each upload is checked:
- Its media type is sniffed for PNG, JPEG, GIF, WebP and PDF. Content that contradicts its declared type is rejected.
- The type must match the slot.
- Its size must be at most the slot's `maxBytes`, otherwise the response is `413`.
- Paths and control characters are stripped from file names.
- A SHA-256 is recorded for every file.

## API

| Method | Path | |
|---|---|---|
| `POST` | `/cases` | Create. `201`, or `200` with the original when `idempotencyKey` repeats |
| `GET` | `/cases` | Caller's cases as a subject: `status`, `correlationId`, `cursor`, `limit` |
| `GET` | `/admin/cases` | Any case: `subject`, `correlationId`, `status`, paging |
| `GET` | `/cases/{id}` | The case with slots and files |
| `POST` | `/cases/{id}/slots/{slot}/files` | Upload: a raw body with `?fileName=`, or `multipart/form-data` (first file part) |
| `GET` | `/cases/{id}/files` | Files |
| `GET` | `/cases/{id}/files/{fileId}` | File metadata |
| `GET` | `/cases/{id}/files/{fileId}/content` | Download; `?inline=true` for display |
| `POST` | `/cases/{id}/files/{fileId}/link` | `{url, expiresAt}`: a signed URL that needs no credentials |
| `DELETE` | `/cases/{id}/files/{fileId}` | Delete |
| `POST` | `/cases/{id}/submit` \| `/reopen` \| `/close` | Status changes; reopen/close take `{reason?}` |
| `POST` / `GET` / `DELETE` | `/webhooks`, `/webhooks/{id}`, `/webhooks/{id}/deliveries` | Webhook registry |
| `POST` | `/stream-ticket` | `{ticket, expiresIn}` for a browser `EventSource` |
| `GET` | `/stream` | SSE |

## Events

| Event | SSE (subjects, creator, admin roles with `read`) | Webhook (watchers other than the actor) |
|---|---|---|
| `case.created` | ✓ the case | — |
| `attachment.uploaded` | ✓ `{caseId, attachment}` | ✓ `{caseId, correlationId, attachment}` |
| `attachment.deleted` | ✓ | ✓ |
| `case.submitted` | ✓ | ✓ `{case}`, with its files |
| `case.reopened`, `case.closed` | ✓ | ✓ `{case}` |

`watchers` defaults to the case's creator. A workflow sets it to its agent's participant ID so that the agent's
webhook receives the events. Verify deliveries with `service_commons.webhook:verify` (see the chat README).

## From a workflow

```ballerina
attachment:Case photos = check attachments->createCase({
    idempotencyKey: string `${caseId}/photos`,
    correlationId: caseId,
    title: "Photos of the leak",
    subjects: [tenantId],
    watchers: ["agent:maintenance-triage"],
    autoSubmit: true,
    slots: [{name: "leak-photo", label: "Photo of the leak", mimeTypes: ["image/*"], maxFiles: 3}]
});
// then wait durably for the case.submitted webhook
```

## Storage

Tables `attachment_case`, `attachment_subject`, `attachment_slot`, `attachment_file`, `attachment_blob`, plus
`attachment_webhook_subscription` and `attachment_webhook_outbox`. The blob column is `BLOB`, `LONGBLOB` or `BYTEA`
depending on the database.
- **DATABASE storage** writes the content in the same transaction as the file row.
- **FILESYSTEM storage** writes `<storageDir>/<ns>/<fileId>` before that transaction and removes the file if the
  transaction fails.

Tested on H2, with both storage types. MySQL and PostgreSQL haven't been run yet.
