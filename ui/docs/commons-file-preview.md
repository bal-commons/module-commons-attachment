# `<commons-file-preview>`

A modal dialog that previews one uploaded file: images, PDFs, video and audio inline through a signed link, and
small text files (up to 256 KB) as text. Anything else shows "No preview for <type>" with a Download button. The
toolbar shows the file name, size, uploader and time, "Open in new tab" when there is a link, Download and Close.
[`<commons-upload-case>`](commons-upload-case.md) and [`<commons-file-viewer>`](commons-file-viewer.md) contain
one and open it when a file is clicked. Use it directly when you list files yourself (for example from
`AttachmentClient`) and want the same preview.

```html
<script type="module" src="https://cdn.jsdelivr.net/npm/@bal-commons/attachment-ui@0.1/dist/attachment-ui.bundle.js"></script>

<commons-file-preview id="preview" base-url="/api/attachments"></commons-file-preview>
<script type="module">
  document.getElementById("preview").show(attachment);   // an Attachment from the service
</script>
```

The element renders nothing visible until `show()` is called.

Authentication, installing and theming are covered in the
[guide](https://github.com/bal-commons/module-commons-service-commons/blob/main/ui/docs/guide.md).

## Attributes and properties

| Property | Attribute | Type | Default | Meaning |
|---|---|---|---|---|
| `baseUrl` | `base-url` | `string` | `""` | Attachment service base URL. Required |
| `file` | property only | `Attachment` | unset | The file to show. Set it and call `show()`, or pass it to `show(file)` |
| `auth` | property only | `AuthAdapter` | the `configureAuth` default | Auth adapter for this element's requests |

## Events

All events bubble and are composed.

| Event | When | `detail` | Cancelable |
|---|---|---|---|
| `commons-file-downloaded` | A download from the toolbar or the "No preview" button finished | `{attachment: Attachment}` | no |
| `commons-preview-close` | The dialog closed (Close button or Escape) | none | no |

```js
preview.addEventListener("commons-preview-close", () => {
  history.replaceState(null, "", location.pathname);   // e.g. drop a ?file= parameter
});
```

## Methods

| Method | Returns | What it does |
|---|---|---|
| `show(file?: Attachment)` | `Promise<void>` | Opens the dialog for `file` (or for the `file` already set) and loads the preview. Does nothing when there is no file |
| `close()` | `void` | Closes the dialog |

## CSS parts

| Part | Element |
|---|---|
| `dialog` | The `<dialog>` (at most 960×720 px, 94vw × 90vh) |
| `toolbar` | The top bar with name, details and buttons |
| `body` | The preview area |

## Slots

None.

## Behavior

### What previews

| MIME type | Preview |
|---|---|
| `image/*` | `<img>` |
| `application/pdf` | `<iframe>` (the browser's PDF viewer) |
| `video/*` | `<video controls>` |
| `audio/*` | `<audio controls>` |
| `text/*`, `application/json`, `*+json`, `application/xml`, `*+xml`, up to 256 KB | `<pre>` with the text |
| anything else, or text over 256 KB | "No preview for <type>." and a Download button |

The same rules are exported as `previewKind(attachment)`.

- Images, PDFs, video and audio load through a signed link (`POST /cases/{id}/files/{fileId}/link`), which needs no
  credentials and expires after `linkTtlSeconds` (300 seconds by default). "Open in new tab" uses the same link, so
  it stops working after that time.
- Text is downloaded with the caller's credentials and shown as plain text.
- Download fetches the bytes with the caller's credentials and saves them under the original file name.

The service serves signed links with `Content-Disposition: inline`, `X-Content-Type-Options: nosniff` and
`Cache-Control: private, no-store`.

### What the service decides

The caller must be able to read the case: its subjects, its creator, `attachment:admin`, or an admin role with
`read`. Anyone else gets 404, shown in the preview area.

### States

| State | What shows |
|---|---|
| Loading | "Loading…" in the preview area |
| Error | The error in red (`role="alert"`) in the preview area |

### Accessibility

- A native modal `<dialog>` opened with `showModal()`: focus moves into it, the page behind is inert, and Escape
  closes it.
- The dialog's `aria-label` is the file name. Images use the file name as `alt`; PDFs use it as the iframe `title`.
- Close has `aria-label="Close preview"`.

## Recipes

### Plain HTML: preview files from your own list

```html
<ul id="files"></ul>
<commons-file-preview id="preview" base-url="/api/attachments"></commons-file-preview>

<script type="module">
  import {AttachmentClient, bearer, configureAuth} from "https://cdn.jsdelivr.net/npm/@bal-commons/attachment-ui@0.1/dist/attachment-ui.bundle.js";
  configureAuth(bearer(() => sessionStorage.getItem("token")));

  const c = await new AttachmentClient("/api/attachments").getCase(caseId);
  const preview = document.getElementById("preview");
  for (const file of c.files ?? []) {
    const button = Object.assign(document.createElement("button"), {textContent: file.fileName});
    button.onclick = () => preview.show(file);
    const item = document.createElement("li");
    item.append(button);
    document.getElementById("files").append(item);
  }
</script>
```

### React 19

```tsx
import "@bal-commons/attachment-ui";
import type {Attachment, CommonsFilePreview} from "@bal-commons/attachment-ui";
import {useEffect, useRef} from "react";

export function Preview({file, onClose}: {file?: Attachment; onClose: () => void}) {
  const ref = useRef<CommonsFilePreview>(null);
  useEffect(() => { if (file) void ref.current?.show(file); }, [file]);
  return <commons-file-preview ref={ref} base-url="/api/attachments" oncommons-preview-close={onClose} />;
}
```
