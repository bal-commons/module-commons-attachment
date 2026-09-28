import {type AuthAdapter, tokens} from "@bal-commons/ui-core";
import {css, html, LitElement, nothing} from "lit";
import {AttachmentClient} from "./client.js";
import {caseIdOf, feedFor} from "./feed.js";
import type {CommonsFilePreview} from "./file-preview.js";
import "./file-preview.js";
import {formatBytes, typeBadge} from "./files.js";
import type {Attachment, Case, Slot} from "./types.js";

/**
 * An upload case: its slots, uploaded files (image thumbnails through signed links), a drop zone per slot while
 * the case is open, and a Submit button once every slot is satisfied. Kept live.
 * @fires commons-file-uploaded - A file was uploaded; `detail.attachment`.
 * @fires commons-file-deleted - The caller removed one of their files; `detail.attachment`.
 * @fires commons-file-open - A file was clicked; `detail.attachment`. Cancelable: by default it opens a preview.
 * @fires commons-case-submitted - The caller submitted the case; `detail.case`.
 * @csspart slot - One slot.
 * @csspart dropzone - A slot's drop zone and file picker.
 * @csspart submit - The Submit button.
 */
export class CommonsUploadCase extends LitElement {
  static override properties = {
    baseUrl: {type: String, attribute: "base-url"},
    caseId: {type: String, attribute: "case-id"},
    me: {type: String},
    compact: {type: Boolean, reflect: true},
    auth: {attribute: false},
    case: {state: true, attribute: false},
    links: {state: true, attribute: false},
    uploading: {state: true, attribute: false},
    dragging: {state: true, attribute: false},
    error: {state: true, attribute: false}
  };

  declare baseUrl: string;
  declare caseId: string;
  /** The caller's user ID. When set, people who aren't the case's subjects see it read-only. */
  declare me?: string;
  /** Hides the case title and status, e.g. inside a chat bubble. */
  declare compact: boolean;
  declare auth?: AuthAdapter;
  /** @internal */
  declare case?: Case;
  /** @internal */
  declare links: Record<string, string>;
  /** @internal File names being uploaded, per slot. */
  declare uploading: Record<string, string[]>;
  /** @internal */
  declare dragging?: string;
  /** @internal */
  declare error?: string;
  private unsubscribe?: () => void;

  constructor() {
    super();
    this.baseUrl = "";
    this.caseId = "";
    this.compact = false;
    this.links = {};
    this.uploading = {};
  }

  static override styles = [tokens, css`
    :host { display: grid; gap: 8px; }
    .head { display: flex; gap: 8px; align-items: baseline; }
    .head strong { flex: 1; }
    .status { font-size: 11px; padding: 1px 8px; border-radius: 8px; background: var(--_surface); }
    .status.SUBMITTED { background: var(--_accent-soft); } .status.CLOSED { color: var(--_muted); }
    .reason { font-size: 13px; color: var(--_warning); }
    .slot { display: grid; gap: 6px; padding: 8px; border: 1px dashed var(--_border); border-radius: var(--_radius); }
    .slot.done { border-style: solid; border-color: var(--_success); }
    .meta { font-size: 12px; color: var(--_muted); }
    .thumbs { display: flex; gap: 6px; flex-wrap: wrap; }
    .file { position: relative; }
    .thumb { position: relative; width: 72px; height: 72px; border-radius: 6px; border: 1px solid var(--_border);
      display: grid; place-items: center; background: var(--_surface); cursor: pointer; overflow: hidden; padding: 0;
      font: inherit; color: var(--_fg); }
    .thumb:focus-visible, .remove:focus-visible { outline: 2px solid var(--_accent); }
    .thumb img { width: 100%; height: 100%; object-fit: cover; }
    .thumb .badge { font-size: 11px; font-weight: 700; color: var(--_muted); }
    .thumb .name { position: absolute; bottom: 0; left: 0; right: 0; font-size: 9px; padding: 1px 3px;
      background: rgb(0 0 0 / .55); color: #fff; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
    .remove { position: absolute; top: 2px; right: 2px; width: 18px; height: 18px; border-radius: 50%; border: none;
      background: rgb(0 0 0 / .6); color: #fff; font-size: 12px; line-height: 18px; cursor: pointer; padding: 0; }
    .drop { display: grid; place-items: center; gap: 4px; padding: 12px; border: 1px dashed var(--_border);
      border-radius: 6px; font-size: 13px; color: var(--_muted); text-align: center; cursor: pointer; }
    .drop.over { border-color: var(--_accent); background: var(--_accent-soft); color: var(--_fg); }
    .drop:focus-within { outline: 2px solid var(--_accent); }
    .drop input { position: absolute; width: 1px; height: 1px; opacity: 0; }
    .drop u { color: var(--_accent); text-decoration: none; font-weight: 600; }
    .busy { font-size: 12px; color: var(--_accent); }
    button.submit { font: inherit; padding: 6px 12px; border-radius: 6px; border: 1px solid var(--_accent);
      background: var(--_accent); color: #fff; cursor: pointer; justify-self: start; }
    button.submit:disabled { opacity: .5; cursor: default; }
    .error { color: var(--_error); font-size: 13px; }
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
    if (changed.has("caseId") || changed.has("baseUrl")) {
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

  private canUpload(): boolean {
    return this.case?.status === "OPEN" && (!this.me || this.case.subjects.includes(this.me));
  }

  // Uploads up to the slot's remaining room, one at a time; a rejected file doesn't stop the rest.
  private async upload(slot: Slot, files: File[]): Promise<void> {
    if (!this.case || !files.length) {
      return;
    }
    const room = slot.maxFiles - slot.fileCount - (this.uploading[slot.name]?.length ?? 0);
    const accepted = files.filter((f) => accepts(slot, f));
    const errors: string[] = [];
    if (accepted.length < files.length) {
      errors.push(`${slot.label} takes ${slot.mimeTypes.join(", ")}`);
    }
    if (accepted.length > room) {
      errors.push(`${slot.label} has room for ${Math.max(room, 0)} more`);
    }
    const queue = accepted.slice(0, Math.max(room, 0));
    this.uploading = {...this.uploading, [slot.name]: [...(this.uploading[slot.name] ?? []), ...queue.map((f) => f.name)]};
    const client = new AttachmentClient(this.baseUrl, this.auth);
    for (const file of queue) {
      try {
        if (file.size > slot.maxBytes) {
          throw new Error(`${file.name} is larger than ${formatBytes(slot.maxBytes)}`);
        }
        const attachment = await client.upload(this.case.id, slot.name, file);
        this.dispatchEvent(new CustomEvent("commons-file-uploaded", {detail: {attachment}, bubbles: true, composed: true}));
      } catch (e) {
        errors.push((e as Error).message);
      } finally {
        const remaining = [...(this.uploading[slot.name] ?? [])];
        remaining.splice(remaining.indexOf(file.name), 1);
        this.uploading = {...this.uploading, [slot.name]: remaining};
      }
    }
    this.error = errors.length ? errors.join(". ") : undefined;
    await this.reload();
    if (errors.length) {
      this.error = errors.join(". ");
    }
  }

  private async removeFile(file: Attachment): Promise<void> {
    try {
      await new AttachmentClient(this.baseUrl, this.auth).deleteFile(file.caseId, file.id);
      this.dispatchEvent(new CustomEvent("commons-file-deleted", {detail: {attachment: file}, bubbles: true, composed: true}));
      await this.reload();
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

  private async submit(): Promise<void> {
    try {
      const submitted = await new AttachmentClient(this.baseUrl, this.auth).submit(this.caseId);
      this.case = submitted;
      this.dispatchEvent(new CustomEvent("commons-case-submitted", {detail: {case: submitted}, bubbles: true, composed: true}));
    } catch (e) {
      this.error = (e as Error).message;
    }
  }

  private dropzone(slot: Slot) {
    const room = slot.maxFiles - slot.fileCount;
    const drop = (e: DragEvent) => {
      e.preventDefault();
      this.dragging = undefined;
      void this.upload(slot, [...(e.dataTransfer?.files ?? [])]);
    };
    return html`<label class="drop ${this.dragging === slot.name ? "over" : ""}" part="dropzone"
        @dragover=${(e: DragEvent) => { e.preventDefault(); this.dragging = slot.name; }}
        @dragleave=${() => { this.dragging = undefined; }} @drop=${drop}>
      <span>Drop ${room > 1 ? "files" : "a file"} here or <u>choose</u></span>
      <input type="file" aria-label="Upload ${slot.label}" accept=${slot.mimeTypes.join(",")} ?multiple=${room > 1}
          @change=${(e: Event) => {
            const input = e.target as HTMLInputElement;
            void this.upload(slot, [...(input.files ?? [])]).finally(() => { input.value = ""; });
          }}>
    </label>`;
  }

  override render() {
    const c = this.case;
    if (!c) {
      return this.error ? html`<div class="error" role="alert">${this.error}</div>` : html`<div class="meta">Loading…</div>`;
    }
    const writable = this.canUpload();
    return html`
      ${this.compact ? nothing : html`<div class="head"><strong>${c.title}</strong>
        <span class="status ${c.status}">${c.status}</span></div>`}
      ${c.statusReason ? html`<div class="reason">${c.statusReason}</div>` : nothing}
      ${c.slots.map((slot) => {
        const files = (c.files ?? []).filter((f) => f.slot === slot.name);
        const busy = this.uploading[slot.name] ?? [];
        return html`<div class="slot ${slot.satisfied ? "done" : ""}" part="slot">
          <div><strong>${slot.label}</strong> <span class="meta">${slot.fileCount}/${slot.maxFiles}
            · ${slot.mimeTypes.join(", ") || "any type"}${slot.minFiles === 0 ? " · optional" : ""}</span></div>
          ${slot.description ? html`<div class="meta">${slot.description}</div>` : nothing}
          ${files.length ? html`<div class="thumbs">${files.map((f) => html`<span class="file">
            <button class="thumb" @click=${() => this.open(f)} title=${f.fileName} aria-label="Preview ${f.fileName}">
              ${this.links[f.id] ? html`<img src=${this.links[f.id]} alt="">`
                : html`<span class="badge">${typeBadge(f)}</span><span class="name">${f.fileName}</span>`}
            </button>
            ${writable && this.me && f.uploadedBy === this.me ? html`<button class="remove"
                aria-label="Remove ${f.fileName}" @click=${() => void this.removeFile(f)}>×</button>` : nothing}
          </span>`)}</div>` : nothing}
          ${busy.length ? html`<div class="busy" role="status">Uploading ${busy.join(", ")}…</div>` : nothing}
          ${writable && slot.fileCount + busy.length < slot.maxFiles ? this.dropzone(slot) : nothing}
        </div>`;
      })}
      ${writable && !c.autoSubmit ? html`<button class="submit" part="submit"
          ?disabled=${!c.slots.every((s) => s.satisfied)} @click=${this.submit}>Submit</button>` : nothing}
      ${this.error ? html`<div class="error" role="alert">${this.error}</div>` : nothing}
      <commons-file-preview .baseUrl=${this.baseUrl} .auth=${this.auth}></commons-file-preview>
    `;
  }
}

// The slot's MIME patterns, e.g. "image/*" or "application/pdf"; no patterns take anything.
function accepts(slot: Slot, file: File): boolean {
  if (!slot.mimeTypes.length) {
    return true;
  }
  const type = (file.type || "application/octet-stream").toLowerCase();
  return slot.mimeTypes.some((pattern) => pattern.endsWith("/*")
    ? type.startsWith(pattern.slice(0, -1).toLowerCase()) : type === pattern.toLowerCase());
}

if (!customElements.get("commons-upload-case")) {
  customElements.define("commons-upload-case", CommonsUploadCase);
}
