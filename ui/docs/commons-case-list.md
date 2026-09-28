# `<commons-case-list>`

A list of upload cases, kept live: the caller's own cases (those they are a subject of), or every case for an admin
role. Each row shows the title, the status, "Needs your upload" when the caller still has slots to fill, how many
slots are satisfied with a progress bar, and the time of the last change. In admin mode it also shows each case's
subjects. Use it as the left column of a files screen and open the chosen case in
[`<commons-upload-case>`](commons-upload-case.md) or [`<commons-file-viewer>`](commons-file-viewer.md).

```html
<script type="module" src="https://cdn.jsdelivr.net/npm/@bal-commons/attachment-ui@0.1/dist/attachment-ui.bundle.js"></script>

<commons-case-list base-url="/api/attachments" me="u-123"></commons-case-list>
```

Authentication, installing and theming are covered in the
[guide](https://github.com/bal-commons/module-commons-service-commons/blob/main/ui/docs/guide.md).

## Attributes and properties

| Property | Attribute | Type | Default | Meaning |
|---|---|---|---|---|
| `baseUrl` | `base-url` | `string` | `""` | Attachment service base URL. Required |
| `me` | `me` | `string` | unset | The caller's user ID. Used only for the "Needs your upload" marker |
| `selected` | `selected` (reflected) | `string` | unset | ID of the highlighted case. Set by a click; set it yourself to highlight one |
| `status` | `status` | `"OPEN" \| "SUBMITTED" \| "CLOSED"` | unset (all) | Lists only cases in this status |
| `correlationId` | `correlation-id` | `string` | unset | Lists only cases about this business object |
| `admin` | `admin` | `boolean` | `false` | Lists every case (`GET /admin/cases`) instead of the caller's own (`GET /cases`) |
| `subject` | `subject` | `string` | unset | With `admin`: only the cases this user is a subject of. Ignored without `admin` |
| `pageSize` | `page-size` | `number` | `20` | Cases per page (the service caps it at `maxPageSize`, 100 by default) |
| `auth` | property only | `AuthAdapter` | the `configureAuth` default | Auth adapter for this element's requests |

Changing `status`, `correlationId`, `admin` or `subject` refetches the first page.

## Events

| Event | When | `detail` | Bubbles / composed | Cancelable |
|---|---|---|---|---|
| `commons-case-select` | A row was clicked, or Enter was pressed on a focused row. `selected` is already set | `{case: Case}` | yes / yes | no |

`Case` is described on the [`<commons-upload-case>` page](commons-upload-case.md#events). The listed cases carry
their slots but not their files.

```js
list.addEventListener("commons-case-select", (e) => {
  viewer.caseId = e.detail.case.id;
});
```

## Methods

| Method | Returns | What it does |
|---|---|---|
| `reload()` | `Promise<void>` | Refetches the first page |

## CSS parts

| Part | Element |
|---|---|
| `list` | The `<ul role="listbox">` |
| `item` | One case row |
| `empty` | The empty state |

## Slots

| Slot | Replaces |
|---|---|
| `empty` | The "No cases." text |

## Behavior

### What it lists

- Without `admin`: `GET /cases`, the cases the caller is a **subject** of. Cases the caller only created are not
  listed.
- With `admin`: `GET /admin/cases`, every case in the service's namespace, optionally narrowed by `subject`. The
  service allows this only for holders of `attachment:admin` or an admin role with `read` (`adminRoles` in
  `Config.toml`); anyone else gets 403, shown as the error.
- The service orders cases by ID, newest created first. The row's time is `updatedAt`, so the order is creation
  order, not last activity.
- With `enforceScopes` on, the token needs `attachment:use`.

"Needs your upload" shows when the case is `OPEN`, `me` is one of its subjects, and at least one slot is not
satisfied. Optional slots (`minFiles: 0`) are always satisfied, so they never trigger it.

### Paging

When the service returns a `nextCursor`, a "Load more" button appends the next page (skipping cases already
shown).

### Live updates

The list subscribes to the shared attachment feed for its `base-url`. Any case or file event, and every reconnect,
refetches, debounced by 300 ms. The refetch asks for as many cases as are shown (up to 100), so pages loaded with
"Load more" stay. The service sends case events to each case's creator, subjects and admin roles with `read`.

### States

| State | What shows |
|---|---|
| Loading | "Loading…" (`role="status"`) until the first response arrives |
| Empty | The `empty` slot or "No cases." |
| Error | Only the error message in red (`role="alert"`); the list is hidden until a reload succeeds |

### Accessibility

- The list is `role="listbox"` with `aria-label="Upload cases"`; rows are `role="option"` with `aria-selected`.
- Rows are focusable (`tabindex="0"`); Enter selects. There is no arrow-key navigation.
- The full title is in a `title` attribute when it is truncated.

## Recipes

### Plain HTML: case list and file viewer side by side

```html
<div style="display:grid; grid-template-columns:320px 1fr; gap:12px">
  <commons-case-list id="cases" base-url="/api/attachments"></commons-case-list>
  <section>
    <commons-file-viewer id="files" base-url="/api/attachments">
      <p slot="empty">No files uploaded yet.</p>
    </commons-file-viewer>
  </section>
</div>

<script type="module">
  import {bearer, configureAuth} from "https://cdn.jsdelivr.net/npm/@bal-commons/attachment-ui@0.1/dist/attachment-ui.bundle.js";
  configureAuth(bearer(() => sessionStorage.getItem("token")));

  const me = currentUserId();
  const cases = document.getElementById("cases");
  const files = document.getElementById("files");
  cases.me = me;
  files.me = me;
  cases.addEventListener("commons-case-select", (e) => { files.caseId = e.detail.case.id; });
</script>
```

### Upload card for the caller's open cases, gallery for the rest

```js
cases.addEventListener("commons-case-select", (e) => {
  const c = e.detail.case;
  const tag = c.status === "OPEN" && c.subjects.includes(me) ? "commons-upload-case" : "commons-file-viewer";
  const el = document.createElement(tag);
  el.setAttribute("base-url", "/api/attachments");
  el.setAttribute("case-id", c.id);
  el.me = me;
  detail.replaceChildren(el);
});
```

### React 19: admin review screen

```tsx
import "@bal-commons/attachment-ui";
import type {Case} from "@bal-commons/attachment-ui";
import {useState} from "react";

export function CaseReview() {
  const [caseId, setCaseId] = useState<string>();
  return <div className="review">
    <commons-case-list base-url="/api/attachments" admin={true} status="SUBMITTED" selected={caseId}
        oncommons-case-select={(e: CustomEvent<{case: Case}>) => setCaseId(e.detail.case.id)} />
    {caseId && <commons-file-viewer base-url="/api/attachments" case-id={caseId} layout="list" />}
  </div>;
}
```

### Cases about one object

```html
<commons-case-list base-url="/api/attachments" correlation-id="order-4711"></commons-case-list>
```
