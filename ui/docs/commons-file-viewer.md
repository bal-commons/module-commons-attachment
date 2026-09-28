# `<commons-file-viewer>`

A case's files as a gallery, kept live. Files are grouped under their slot's label, with a thumbnail for images and
a type badge (such as `PDF`) for everything else, plus the size, uploader and time. Each file has Download and,
where allowed, Delete; clicking a file opens a preview. Unlike [`<commons-upload-case>`](commons-upload-case.md) it
has no upload controls. Use it to review what was uploaded: for reviewers and admins, for the uploader after
submitting, or next to a [`<commons-case-list>`](commons-case-list.md).

```html
<script type="module" src="https://cdn.jsdelivr.net/npm/@bal-commons/attachment-ui@0.1/dist/attachment-ui.bundle.js"></script>

<commons-file-viewer base-url="/api/attachments" case-id="01J9..."></commons-file-viewer>
```

Authentication, installing and theming are covered in the
[guide](https://github.com/bal-commons/module-commons-service-commons/blob/main/ui/docs/guide.md).

## Attributes and properties

| Property | Attribute | Type | Default | Meaning |
|---|---|---|---|---|
| `baseUrl` | `base-url` | `string` | `""` | Attachment service base URL. Required |
| `caseId` | `case-id` | `string` | `""` | The case whose files to show. Required |
| `me` | `me` | `string` | unset | The caller's user ID. Their own files get Delete while the case is `OPEN` |
| `canDelete` | `can-delete` | `boolean` | `false` | Shows Delete on every file in any status, for admin roles with `delete`. The service still decides |
| `layout` | `layout` (reflected) | `"grid" \| "list"` | `"grid"` | `grid`: thumbnail tiles; `list`: rows with a small thumbnail |
| `flat` | `flat` | `boolean` | `false` | Lists all files in one section instead of under their slot's label |
| `auth` | property only | `AuthAdapter` | the `configureAuth` default | Auth adapter for this element's requests (also used by its preview) |

## Events

All events bubble and are composed.

| Event | When | `detail` | Cancelable | Default action |
|---|---|---|---|---|
| `commons-file-open` | A file tile was clicked, or Enter was pressed on it | `{attachment: Attachment}` | yes | Opens the built-in preview dialog |
| `commons-file-downloaded` | A download finished (from a tile's Download, or the preview's) | `{attachment: Attachment}` | no | |
| `commons-file-deleted` | The caller confirmed Delete and the service deleted the file | `{attachment: Attachment}` | no | |
| `commons-preview-close` | The preview dialog closed | none | no | |

`Attachment` is described on the [`<commons-upload-case>` page](commons-upload-case.md#events).

```js
viewer.addEventListener("commons-file-deleted", (e) => {
  audit.log("file deleted", e.detail.attachment.id);
});
```

## Methods

| Method | Returns | What it does |
|---|---|---|
| `reload()` | `Promise<void>` | Refetches the case and its files, and fetches signed links for image thumbnails |

## CSS parts

| Part | Element |
|---|---|
| `group` | One slot's `<section>` of files (or the single section with `flat`) |
| `file` | One file tile or row |
| `empty` | The empty state |

## Slots

| Slot | Replaces |
|---|---|
| `empty` | The "No files yet." text |

## Behavior

### Actions

- **Preview**: clicking a tile fires `commons-file-open`; unless cancelled, the built-in
  [`<commons-file-preview>`](commons-file-preview.md) dialog opens.
- **Download**: fetches the bytes with the caller's credentials (`GET /cases/{id}/files/{fileId}/content`) and saves
  them under the original file name.
- **Delete**: asks with the browser's `confirm()` dialog, then calls `DELETE /cases/{id}/files/{fileId}` and
  reloads.

Delete shows when `can-delete` is set, or when the case is `OPEN`, `me` is set, and `attachment.uploadedBy === me`.

### What the service decides

| Action | Allowed by the service |
|---|---|
| See the case, its files, thumbnails and downloads | The case's subjects, its creator, `attachment:admin`, and admin roles with `read`. Anyone else gets 404 |
| Delete a file | Its uploader, only while the case is `OPEN`; or `attachment:admin` / an admin role with `delete`, in any status |

`can-delete` only shows the buttons. A caller without the permission gets 403 or 409 from the service, shown as the
error.

### Grouping

By default, files appear under their slot's label in slot order, and slots without files are
left out. With `flat`, all files
are shown in one section in upload order.

### Live updates and links

As for `<commons-upload-case>`: the element subscribes to the shared attachment feed, refetches on any event about
this case and on reconnect, and loads image thumbnails through signed links that expire after `linkTtlSeconds`
(300 seconds by default). The proxy must forward the whole base path, including `/links/`.

### States

| State | What shows |
|---|---|
| Loading (no case yet) | "Loading…" |
| Load error (no case yet) | The error in red (`role="alert"`) |
| No files | The `empty` slot or "No files yet." |
| Download or delete error | The error in red under the files |

### Accessibility

- Each tile holds a native preview button (the thumbnail and name, `aria-label="Preview <name>"`) and, beside it,
  the Download and Delete buttons (`aria-label="Download <name>"` / `"Delete <name>"`). No control is nested in
  another.
- Thumbnails are decorative (`alt=""`); the file name is always shown as text.
- The preview is a modal `<dialog>`; Escape closes it.

## Recipes

### Plain HTML: reviewer view

```html
<commons-file-viewer id="files" base-url="/api/attachments" layout="list" can-delete></commons-file-viewer>

<script type="module">
  import {bearer, configureAuth} from "https://cdn.jsdelivr.net/npm/@bal-commons/attachment-ui@0.1/dist/attachment-ui.bundle.js";
  configureAuth(bearer(() => sessionStorage.getItem("token")));
  document.getElementById("files").caseId = new URLSearchParams(location.search).get("case");
</script>
```

### Case list and file viewer side by side

See [`<commons-case-list>` recipes](commons-case-list.md#recipes).

### React 19: your own preview

```tsx
import "@bal-commons/attachment-ui";
import type {Attachment} from "@bal-commons/attachment-ui";
import {useState} from "react";

export function Files({caseId}: {caseId: string}) {
  const [open, setOpen] = useState<Attachment>();
  return <>
    <commons-file-viewer base-url="/api/attachments" case-id={caseId} flat
        oncommons-file-open={(e: CustomEvent<{attachment: Attachment}>) => {
          e.preventDefault();          // skip the built-in dialog
          setOpen(e.detail.attachment);
        }} />
    {open && <MyPreview file={open} onClose={() => setOpen(undefined)} />}
  </>;
}
```

In `MyPreview`, get a URL with `new AttachmentClient("/api/attachments").link(file.caseId, file.id)` or the bytes
with `.download(file.caseId, file.id)`.
