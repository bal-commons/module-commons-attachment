# @bal-commons/attachment-ui

Web Components for the [commons attachment service](../README.md). They're built with Lit and work in any
framework or in plain HTML.

| Element | What it shows |
|---|---|
| [`<commons-upload-case>`](docs/commons-upload-case.md) | One upload case: slots and progress, drop zones and multiple-file upload, thumbnails, remove own files, Submit |
| [`<commons-case-list>`](docs/commons-case-list.md) | The caller's cases (or every case, for admin roles), with status, slot progress and "Needs your upload" |
| [`<commons-file-viewer>`](docs/commons-file-viewer.md) | A case's files as a gallery grouped by slot, with preview, download and delete |
| [`<commons-file-preview>`](docs/commons-file-preview.md) | A modal preview of one file: images, PDF, video, audio, text; download otherwise |

Every element stays live as files arrive and cases change, sharing one connection per service URL. Inside
[`<commons-conversation>`](https://github.com/bal-commons/module-commons-chat/tree/main/ui) an agent's upload
request renders as `<commons-upload-case>` automatically.

Installing, authentication, the live model, proxies, theming, events and framework notes are in the
[guide](https://github.com/bal-commons/module-commons-service-commons/blob/main/ui/docs/guide.md). For
notifications, chats and files on one page, see
[`<commons-hub>`](https://github.com/bal-commons/commons-hub-ui).

## Install

```sh
npm install @bal-commons/attachment-ui
```

```html
<script type="module" src="https://cdn.jsdelivr.net/npm/@bal-commons/attachment-ui@0.1/dist/attachment-ui.bundle.js"></script>
```

> The package is not yet published to npm, so the two lines above don't work yet. Until it is, build it locally:
> `npm install && npm run build` here (after building `@bal-commons/ui-core` in `service-commons/ui` and linking
> it), then either `npm link` this package into your app or copy `dist/attachment-ui.bundle.js` into your static
> files.

## Use

A user fills an upload case:

```html
<commons-upload-case base-url="/api/attachments" case-id="01M3..." me="u-123"></commons-upload-case>

<script type="module">
  import {bearer, configureAuth} from "@bal-commons/attachment-ui";
  configureAuth(bearer(() => sessionStorage.getItem("token")));
</script>
```

A reviewer browses cases and their files:

```html
<commons-case-list id="cases" base-url="/api/attachments" admin status="SUBMITTED"></commons-case-list>
<commons-file-viewer id="files" base-url="/api/attachments" layout="list"></commons-file-viewer>

<script type="module">
  cases.addEventListener("commons-case-select", (e) => { files.caseId = e.detail.case.id; });
</script>
```

The components show only the controls the caller can use, and the service enforces the rules: only a case's
subjects upload and submit; non-admins delete only their own files and only while the case is `OPEN`; admin roles
with `read` list every case through `/admin/cases`. Image thumbnails and previews use signed links that expire
after `linkTtlSeconds` (300 s by default).

## Reference

Each element has a full reference page: attributes, events and `detail` shapes, methods, CSS parts, slots, live
behaviour, permissions and recipes.

- [`<commons-upload-case>`](docs/commons-upload-case.md): `base-url`, `case-id`, `me`, `compact`; events
  `commons-file-uploaded`, `commons-file-deleted`, `commons-file-open` (cancelable), `commons-case-submitted`;
  method `reload()`; parts `slot`, `dropzone`, `submit`.
- [`<commons-case-list>`](docs/commons-case-list.md): `base-url`, `me`, `selected`, `status`, `correlation-id`,
  `admin`, `subject`, `page-size`; event `commons-case-select`; method `reload()`; parts `list`, `item`, `empty`;
  slot `empty`.
- [`<commons-file-viewer>`](docs/commons-file-viewer.md): `base-url`, `case-id`, `me`, `can-delete`, `layout`,
  `.groupBySlot`; events `commons-file-open` (cancelable), `commons-file-downloaded`, `commons-file-deleted`;
  method `reload()`; parts `group`, `file`, `empty`; slot `empty`.
- [`<commons-file-preview>`](docs/commons-file-preview.md): `base-url`, `.file`; events `commons-file-downloaded`,
  `commons-preview-close`; methods `show(file?)`, `close()`; parts `dialog`, `toolbar`, `body`.

Theme: the `--bc-*` custom properties; see
[theming](https://github.com/bal-commons/module-commons-service-commons/blob/main/ui/docs/guide.md#theming).

`AttachmentClient(baseUrl, auth?)` gives typed calls (`getCase`, `listCases`, `listAllCases`, `upload`,
`deleteFile`, `submit`, `download`, `link`) and `attachmentFeed(baseUrl, auth?)` the shared live feed, for custom
views. `previewKind` and `formatBytes` are exported too.

## What the service side needs

CORS for cross-origin pages (`corsAllowOrigins`), and a proxy that forwards the whole base path (signed links live
under `<base path>/links/`), doesn't buffer `/stream` (SSE) and allows request bodies up to `maxFileBytes`:
`proxy_buffering off; proxy_read_timeout 1h; proxy_http_version 1.1; proxy_set_header Connection "";
client_max_body_size 10m;`

## Integration prompt

```text
Let users upload the files my backend asks for, and let reviewers see them, using the npm package
@bal-commons/attachment-ui (Lit Web Components; API: node_modules/@bal-commons/attachment-ui/dist/custom-elements.json,
its README and docs/).

- The attachment service is at [base URL, e.g. /api/attachments]; proxy the whole base path (including /links/)
  without buffering /stream (SSE), and allow request bodies up to the service's maxFileBytes.
- Authentication: configureAuth(bearer(getToken, onUnauthorized)) once at startup, with [how my app gets the
  access token].
- Wherever [my app shows a pending upload request / a case], render <commons-upload-case base-url="..."
  case-id="[the case ID from my backend]"> and set its .me to [the signed-in user's ID]. On
  commons-case-submitted, [refresh / navigate].
- On [the files page], show <commons-case-list base-url="..."> next to a detail area. On commons-case-select,
  show <commons-upload-case> when the case is OPEN and the user is one of its subjects, otherwise
  <commons-file-viewer case-id="...">. Set .me on all of them. For [admin users], add the admin attribute to the
  case list (and can-delete on the viewer if their role has delete).
- On [detail pages of my business objects], show <commons-case-list correlation-id="[the object's ID]">.
- Match the design with the --bc-* CSS custom properties; keep dark mode.
- Do not re-implement uploading, polling or previews; the components do it.
```

## Develop

```sh
npm install && npm run build   # needs @bal-commons/ui-core (npm link ../../service-commons/ui until it is on npm)
```
