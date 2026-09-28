# `<commons-upload-case>`

One upload case, kept live: its title and status, the reason when it was reopened, and one box per slot with the
slot's progress, accepted types and uploaded files. While the case is open and the caller may upload, each slot
with room has a drop zone and file picker, the caller can remove their own files, and a Submit button appears for
cases that do not submit themselves. Clicking a file opens a preview. Use it wherever your app asks a user for
files: a task page, a request detail page, or inside a chat (`<commons-conversation>` renders it for
`ATTACHMENT_REF` messages).

```html
<script type="module" src="https://cdn.jsdelivr.net/npm/@bal-commons/attachment-ui@0.1/dist/attachment-ui.bundle.js"></script>

<commons-upload-case base-url="/api/attachments" case-id="01J9..." me="u-123"></commons-upload-case>
```

Authentication, installing and theming are covered in the
[guide](https://github.com/bal-commons/module-commons-service-commons/blob/main/ui/docs/guide.md).

## Attributes and properties

| Property | Attribute | Type | Default | Meaning |
|---|---|---|---|---|
| `baseUrl` | `base-url` | `string` | `""` | Attachment service base URL, e.g. `/api/attachments` or `http://localhost:9102/attachments/v1`. Required |
| `caseId` | `case-id` | `string` | `""` | The case to show. Required |
| `me` | `me` | `string` | unset | The caller's user ID. When set, a caller who is not one of the case's subjects sees the case read-only, and the caller gets a remove (×) button on files they uploaded. When unset, upload controls show for everyone while the case is open, and no remove buttons show |
| `compact` | `compact` (reflected) | `boolean` | `false` | Hides the title and status line, e.g. inside a chat bubble |
| `auth` | property only | `AuthAdapter` | the `configureAuth` default | Auth adapter for this element's requests (also used by its preview) |

## Events

All events bubble and are composed.

| Event | When | `detail` | Cancelable | Default action |
|---|---|---|---|---|
| `commons-file-uploaded` | One file was stored. Fires once per file | `{attachment: Attachment}` | no | |
| `commons-file-deleted` | The caller removed one of their files | `{attachment: Attachment}` | no | |
| `commons-file-open` | A file thumbnail was clicked (or activated with Enter or Space) | `{attachment: Attachment}` | yes | Opens the built-in preview dialog |
| `commons-case-submitted` | The caller pressed Submit and the service accepted it | `{case: Case}` | no | |
| `commons-file-downloaded` | The caller pressed Download in the preview | `{attachment: Attachment}` | no | |
| `commons-preview-close` | The preview dialog closed | none | no | |

`commons-case-submitted` does not fire for cases with `autoSubmit`: the service submits those itself after the
upload that satisfies the last slot, and the element shows the new status from the live stream.

```ts
interface Attachment {
  id: string;
  caseId: string;
  slot: string;
  fileName: string;
  mimeType: string;
  sizeBytes: number;
  sha256: string;
  uploadedBy: string;
  uploadedAt: string;
}

interface Case {
  id: string;
  correlationId: string;
  title: string;
  description?: string;
  status: "OPEN" | "SUBMITTED" | "CLOSED";
  subjects: string[];        // the users who upload and submit
  watchers?: string[];
  createdBy: string;
  slots: Slot[];
  files?: Attachment[];
  autoSubmit: boolean;
  dueAt?: string;
  statusReason?: string;     // e.g. why it was reopened
  createdAt: string;
  updatedAt: string;
}

interface Slot {
  name: string;
  label: string;
  description?: string;
  mimeTypes: string[];       // e.g. ["image/*", "application/pdf"]; empty takes any type
  maxBytes: number;
  minFiles: number;          // 0 means optional
  maxFiles: number;
  fileCount: number;
  satisfied: boolean;        // fileCount >= minFiles
}
```

```js
card.addEventListener("commons-case-submitted", (e) => {
  showToast(`Submitted ${e.detail.case.title}`);
  router.navigate("/tasks");
});

// Open files in your own viewer instead of the built-in dialog.
card.addEventListener("commons-file-open", (e) => {
  e.preventDefault();
  openInSidePanel(e.detail.attachment);
});
```

## Methods

| Method | Returns | What it does |
|---|---|---|
| `reload()` | `Promise<void>` | Refetches the case and its files, and fetches signed links for image thumbnails |

## CSS parts

| Part | Element |
|---|---|
| `slot` | One slot's box. Solid green border when satisfied, dashed otherwise |
| `dropzone` | A slot's drop zone and file picker |
| `submit` | The Submit button |

## Slots

None. (The `slot` part is a styling hook for a case slot, not a DOM `<slot>`.)

## Behavior

### Uploading

- Drop files on a slot's zone, or click it to choose. The picker allows several files when the slot has room for
  more than one, and its `accept` is the slot's `mimeTypes`.
- The element filters before sending: files whose type does not match the slot's patterns (`image/*` style or
  exact) are skipped, and only as many files as the slot has room for are sent. It reports both ("Photos takes
  image/*", "Photos has room for 1 more").
- Files upload one at a time as the raw request body (`POST /cases/{id}/slots/{slot}/files?fileName=...`, with the
  file's `Content-Type`). A file larger than the slot's `maxBytes` is rejected before sending. One failed file does
  not stop the rest; all errors are listed together afterwards.
- While files upload, the slot shows "Uploading a.jpg, b.pdf…" (`role="status"`).
- The drop zone disappears when the slot is full, when the case is not `OPEN`, or when `me` is set and is not a
  subject.

### Removing files

The × button appears on a file when the case is `OPEN`, `me` is set and is one of the subjects, and
`attachment.uploadedBy === me`. It removes the file without a confirmation.

### Submitting

For cases without `autoSubmit`, a Submit button shows while the caller may upload. It is disabled until every slot
is satisfied. After a successful submit, the case is `SUBMITTED` and read-only.

### What the service decides

The element hides controls the caller cannot use, but the service enforces the rules:

| Action | Allowed by the service |
|---|---|
| See the case and its files | The case's subjects, its creator, holders of `attachment:admin`, and admin roles with `read` (`adminRoles` in `Config.toml`). Anyone else gets 404 |
| Upload | Only the case's subjects, only while the case is `OPEN`, only up to `maxFiles` per slot and `maxBytes` per file. The service also sniffs the content: a file whose bytes do not match its declared type is rejected |
| Delete a file | Its uploader, only while the case is `OPEN`; or `attachment:admin` / an admin role with `delete`, in any status |
| Submit | Only the case's subjects, only while `OPEN`, only when every slot has at least `minFiles` files |

With `enforceScopes` on, the token needs `attachment:use`.

Without `me`, a user who is not a subject still sees upload controls; the service answers 403 ("Only the case's
subjects upload") and the element shows it. Set `me` to avoid that.

### Live updates

The element subscribes to the shared attachment feed for its `base-url`. Any event about this case (created,
submitted, reopened, closed, file uploaded or deleted) and every reconnect refetches the case. The service sends
case events to the case's creator, its subjects and admin roles with `read`.

### Thumbnails and signed links

Image files get a thumbnail through a signed link (`POST /cases/{id}/files/{fileId}/link`). A link needs no
credentials and expires after `linkTtlSeconds` (300 seconds by default). The client caches each link and reuses it
until 30 seconds before it expires; each reload fetches fresh ones as needed. Other files show a type badge such as
`PDF` with the file name.

The service returns links as a path under its own base path (`/attachments/v1/links/...`). The client maps it onto
your `base-url`, so a proxy must forward the whole base path, including `/links/`.

### States

| State | What shows |
|---|---|
| Loading (no case yet) | "Loading…" |
| Load error (no case yet) | The error message in red (`role="alert"`) |
| Upload, remove or submit error | The message in red under the slots, until the next successful action |
| `SUBMITTED` / `CLOSED` | Status badge; slots and files without controls |
| Reopened | `statusReason` in amber under the title |

### Accessibility

- Each file is a native button with `aria-label="Preview <name>"`.
- The drop zone is a `<label>` wrapping a visually hidden file input with `aria-label="Upload <slot label>"`, so it
  is reachable with Tab and opens the picker from the keyboard. The focus ring is on the zone.
- The remove control is a native button with `aria-label="Remove <name>"`, beside the file's preview button (not
  inside it).
- The preview is a modal `<dialog>`; Escape closes it.

## Recipes

### Plain HTML: a task page that asks for files

```html
<h1>Upload your documents</h1>
<commons-upload-case id="docs" base-url="/api/attachments"></commons-upload-case>

<script type="module">
  import {bearer, configureAuth} from "https://cdn.jsdelivr.net/npm/@bal-commons/attachment-ui@0.1/dist/attachment-ui.bundle.js";
  configureAuth(bearer(() => sessionStorage.getItem("token")));

  const docs = document.getElementById("docs");
  docs.me = currentUserId();
  docs.caseId = new URLSearchParams(location.search).get("case");
  docs.addEventListener("commons-case-submitted", () => location.assign("/tasks?done=1"));
</script>
```

### React 19

```tsx
import "@bal-commons/attachment-ui";
import type {Case} from "@bal-commons/attachment-ui";

export function EvidenceUpload({caseId, me, onDone}: {caseId: string; me: string; onDone: (c: Case) => void}) {
  return <commons-upload-case base-url="/api/attachments" case-id={caseId} me={me}
      oncommons-case-submitted={(e: CustomEvent<{case: Case}>) => onDone(e.detail.case)} />;
}
```

### Inside a chat

`<commons-conversation>` renders this element for `ATTACHMENT_REF` messages whose content has a `caseId`. Load
`attachment-ui` on the page and set `attachments-url` on the conversation:

```html
<commons-conversation base-url="/api/chat" attachments-url="/api/attachments" conversation-id="..."></commons-conversation>
```

### Upload card for the subject, gallery for everyone else

```js
const c = await new AttachmentClient("/api/attachments").getCase(caseId);
const el = c.status === "OPEN" && c.subjects.includes(me)
    ? document.createElement("commons-upload-case")
    : document.createElement("commons-file-viewer");
el.setAttribute("base-url", "/api/attachments");
el.setAttribute("case-id", caseId);
el.me = me;
container.replaceChildren(el);
```

This is what `<commons-hub>` does in its Files pane. See [`<commons-file-viewer>`](commons-file-viewer.md).
