# @bal-commons/attachment-ui

Web Components for the [commons attachment service](../README.md). `<commons-upload-case>` shows an upload
case:
- its status, and the reason when it was reopened;
- each slot's progress and accepted types;
- the uploaded files, with image thumbnails through short-lived signed links;
- an upload control per slot while the case is open and the slot has room;
- a Submit button once every slot is satisfied (for cases that don't submit themselves).

It stays live as files arrive and the case changes. It's built with Lit and works in any framework or in plain HTML.
Inside [`<commons-conversation>`](https://github.com/bal-commons/module-commons-chat/tree/main/ui) it renders an
agent's upload request automatically.

## Install

```sh
npm install @bal-commons/attachment-ui
```

```html
<script type="module" src="https://cdn.jsdelivr.net/npm/@bal-commons/attachment-ui@0.1/dist/attachment-ui.bundle.js"></script>
```

## Use

```html
<commons-upload-case base-url="/api/attachments" case-id="01M3..."></commons-upload-case>

<script type="module">
  import {bearer, configureAuth} from "@bal-commons/attachment-ui";
  configureAuth(bearer(() => sessionStorage.getItem("token")));
</script>
```

| Attribute | |
|---|---|
| `base-url` | Attachment service base URL (required) |
| `case-id` | The case to show (required) |

Events: `commons-file-uploaded` (`detail.attachment`), `commons-case-submitted` (`detail.case`). Method:
`reload()`. CSS parts: `slot`, `submit`. Theme: the `--bc-*` custom properties.

Only the case's subjects see upload controls. Admin roles with `read` see the files. The service decides both,
and the component shows what it's allowed.

`AttachmentClient` gives typed calls (`getCase`, `listCases`, `upload`, `submit`, `link`) for custom views.

## Integration prompt

```text
Let users upload the files my backend asks for, using the npm package @bal-commons/attachment-ui (Lit Web
Component; API: node_modules/@bal-commons/attachment-ui/dist/custom-elements.json and its README).

- The attachment service is at [base URL, e.g. /api/attachments]; proxy it without buffering /stream (SSE) and
  allow request bodies up to the service's maxFileBytes.
- Authentication: configureAuth(bearer(getToken, onUnauthorized)) once at startup, with [how my app gets the
  access token].
- Wherever [my app shows a pending upload request / a case], render <commons-upload-case base-url="..."
  case-id="[the case ID from my backend]">. On commons-case-submitted, [refresh / navigate].
- Match the design with the --bc-* CSS custom properties; keep dark mode.
```
