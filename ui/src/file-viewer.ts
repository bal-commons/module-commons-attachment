import {type AuthAdapter, relativeTime, tokens} from "@bal-commons/ui-core";
import {css, html, LitElement, nothing} from "lit";
import {AttachmentClient} from "./client.js";
import {caseIdOf, feedFor} from "./feed.js";
import type {CommonsFilePreview} from "./file-preview.js";
import "./file-preview.js";
import {formatBytes, saveBlob, typeBadge} from "./files.js";
import type {Attachment, Case} from "./types.js";

/**
 * A case's files as a gallery grouped by slot: thumbnails for images, a type badge for the rest, and preview,
 * download and delete actions. Kept live.
 * @fires commons-file-open - A file was clicked; `detail.attachment`. Cancelable: by default it opens a preview.
 * @fires commons-file-deleted - The caller deleted a file; `detail.attachment`.
 * @fires commons-file-downloaded - The caller downloaded a file; `detail.attachment`.
 * @csspart group - One slot's files.
 * @csspart file - One file tile.
 * @csspart empty - The empty state.
 * @slot empty - Replaces the "No files yet." text.
 */
export class CommonsFileViewer extends LitElement {
  static override properties = {
    baseUrl: {type: String, attribute: "base-url"},
    caseId: {type: String, attribute: "case-id"},
    me: {type: String},
    canDelete: {type: Boolean, attribute: "can-delete"},
    layout: {type: String, reflect: true},
    flat: {type: Boolean},
    auth: {attribute: false},
    case: {state: true, attribute: false},
    links: {state: true, attribute: false},
    error: {state: true, attribute: false}
  };

  declare baseUrl: string;
  declare caseId: string;
  /** The caller's user ID: their own files get a Delete action while the case is open. */
  declare me?: string;
  /** Shows Delete on every file, for admin roles with `delete`. The service still decides. */
  declare canDelete: boolean;
  /** `grid` (thumbnails) or `list` (rows with details). */
  declare layout: "grid" | "list";
  /** Lists all files together instead of under their slot's label. */
  declare flat: boolean;
  declare auth?: AuthAdapter;
  /** @internal */
  declare case?: Case;
  /** @internal */
  declare links: Record<string, string>;
  /** @internal */
  declare error?: string;
  private unsubscribe?: () => void;

  constructor() {
    super();
    this.baseUrl = "";
    this.caseId = "";
    this.canDelete = false;
    this.layout = "grid";
    this.flat = false;
    this.links = {};
  }

  static override styles = [tokens, css`
    :host { display: grid; gap: 12px; }
    h3 { margin: 0 0 6px; font-size: 12px; font-weight: 600; color: var(--_muted); text-transform: uppercase;
      letter-spacing: .04em; }
    .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(128px, 1fr)); gap: 8px; }
    .list { display: grid; gap: 4px; }
    .file { position: relative; border: 1px solid var(--_border); border-radius: var(--_radius); background: var(--_bg);
      overflow: hidden; }
    .open { display: block; width: 100%; padding: 0; border: 0; background: none; font: inherit; color: inherit;
      text-align: left; cursor: pointer; }
    .open:focus-visible { outline: 2px solid var(--_accent); outline-offset: -2px; }
    .open > span { display: block; }
    .grid .thumb { aspect-ratio: 4 / 3; display: grid; place-items: center; background: var(--_surface); }
    .thumb img { width: 100%; height: 100%; object-fit: cover; }
    .badge { font-size: 12px; font-weight: 700; color: var(--_muted); border: 1px solid var(--_border);
      border-radius: 4px; padding: 2px 6px; background: var(--_bg); }
    .info { padding: 6px 8px; display: grid; gap: 2px; min-width: 0; }
    .name { font-size: 13px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
    .meta { font-size: 11px; color: var(--_muted); }
    .list .file { display: flex; align-items: center; }
    .list .open { display: grid; grid-template-columns: 48px 1fr; align-items: center; flex: 1; min-width: 0; }
    .list .thumb { width: 48px; height: 48px; display: grid; place-items: center; background: var(--_surface); }
    .actions { display: flex; gap: 4px; padding: 0 8px 6px; }
    .list .actions { padding: 0 8px; }
    .actions button { font: inherit; font-size: 11px; padding: 2px 8px; border-radius: 5px; cursor: pointer;
      border: 1px solid var(--_border); background: var(--_bg); color: var(--_fg); }
    .actions button.danger { color: var(--_error); }
    .empty, .error { font-size: 13px; color: var(--_muted); }
    .error { color: var(--_error); }
  `];

  override connectedCallback(): void {
    super.connectedCallback();
    this.start();
  }

  override disconnectedCallback(): void {
    super.disconnectedCallback();
    this.unsubscribe?.();
    this.unsubscribe = undefined;
  }

  override updated(changed: Map<string, unknown>): void {
    if (changed.has("baseUrl") || changed.has("caseId")) {
      this.start();
    }
  }

  private start(): void {
    this.unsubscribe?.();
    this.unsubscribe = undefined;
    if (!this.baseUrl || !this.caseId || !this.isConnected) {
      return;
    }
    this.unsubscribe = feedFor(this.baseUrl, this.auth).subscribe((change) => {
      if (change.type === "reconnected" || caseIdOf(change) === this.caseId) {
        void this.reload();
      }
    });
    void this.reload();
  }

  async reload(): Promise<void> {
    try {
      const client = new AttachmentClient(this.baseUrl, this.auth);
      const loaded = await client.getCase(this.caseId);
      const links: Record<string, string> = {};
      await Promise.all((loaded.files ?? []).filter((f) => f.mimeType.startsWith("image/")).map(async (f) => {
        links[f.id] = await client.link(loaded.id, f.id).catch(() => "");
      }));
      this.case = loaded;
      this.links = links;
      this.error = undefined;
    } catch (e) {
      this.error = (e as Error).message;
    }
  }

  private open(file: Attachment): void {
    const event = new CustomEvent("commons-file-open",
        {detail: {attachment: file}, bubbles: true, composed: true, cancelable: true});
    if (this.dispatchEvent(event)) {
      void (this.renderRoot.querySelector("commons-file-preview") as CommonsFilePreview | null)?.show(file);
    }
  }

  private async download(file: Attachment): Promise<void> {
    try {
      saveBlob(await new AttachmentClient(this.baseUrl, this.auth).download(file.caseId, file.id), file.fileName);
      this.dispatchEvent(new CustomEvent("commons-file-downloaded", {detail: {attachment: file}, bubbles: true, composed: true}));
    } catch (e) {
      this.error = (e as Error).message;
    }
  }

  private async removeFile(file: Attachment): Promise<void> {
    if (!confirm(`Delete ${file.fileName}?`)) {
      return;
    }
    try {
      await new AttachmentClient(this.baseUrl, this.auth).deleteFile(file.caseId, file.id);
      this.dispatchEvent(new CustomEvent("commons-file-deleted", {detail: {attachment: file}, bubbles: true, composed: true}));
      await this.reload();
    } catch (e) {
      this.error = (e as Error).message;
    }
  }

  private deletable(file: Attachment): boolean {
    return this.canDelete || (this.case?.status === "OPEN" && !!this.me && file.uploadedBy === this.me);
  }

  private tile(file: Attachment) {
    const stop = (action: () => void) => (e: Event) => { e.stopPropagation(); action(); };
    return html`<div class="file" part="file">
      <button class="open" aria-label="Preview ${file.fileName}" @click=${() => this.open(file)}>
        <span class="thumb">${this.links[file.id]
          ? html`<img src=${this.links[file.id]} alt="" loading="lazy">`
          : html`<span class="badge">${typeBadge(file)}</span>`}</span>
        <span class="info">
          <span class="name" title=${file.fileName}>${file.fileName}</span>
          <span class="meta">${formatBytes(file.sizeBytes)} · ${file.uploadedBy} ·
            <span title=${file.uploadedAt}>${relativeTime(file.uploadedAt)}</span></span>
        </span>
      </button>
      <div class="actions">
        <button @click=${stop(() => void this.download(file))} aria-label="Download ${file.fileName}">Download</button>
        ${this.deletable(file) ? html`<button class="danger" @click=${stop(() => void this.removeFile(file))}
            aria-label="Delete ${file.fileName}">Delete</button>` : nothing}
      </div>
    </div>`;
  }

  override render() {
    const c = this.case;
    const preview = html`<commons-file-preview .baseUrl=${this.baseUrl} .auth=${this.auth}></commons-file-preview>`;
    if (!c) {
      return this.error ? html`<div class="error" role="alert">${this.error}</div>` : html`<div class="empty">Loading…</div>`;
    }
    const files = c.files ?? [];
    if (!files.length) {
      return html`<div class="empty" part="empty"><slot name="empty">No files yet.</slot></div>${preview}`;
    }
    const groups = !this.flat
      ? c.slots.map((s) => ({label: s.label, files: files.filter((f) => f.slot === s.name)})).filter((g) => g.files.length)
      : [{label: "", files}];
    return html`
      ${groups.map((g) => html`<section part="group">
        ${g.label ? html`<h3>${g.label}</h3>` : nothing}
        <div class=${this.layout === "list" ? "list" : "grid"}>${g.files.map((f) => this.tile(f))}</div>
      </section>`)}
      ${this.error ? html`<div class="error" role="alert">${this.error}</div>` : nothing}
      ${preview}`;
  }
}

if (!customElements.get("commons-file-viewer")) {
  customElements.define("commons-file-viewer", CommonsFileViewer);
}
