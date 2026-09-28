import {type AuthAdapter, LiveStream, tokens} from "@bal-commons/ui-core";
import {css, html, LitElement, nothing} from "lit";
import {AttachmentClient} from "./client.js";
import type {Case, Slot} from "./types.js";

/**
 * An upload case: its slots, uploaded files (image thumbnails through signed links), an upload control per slot
 * while the case is open, and a Submit button once every slot is satisfied. Kept live.
 * @fires commons-file-uploaded - A file was uploaded; `detail.attachment`.
 * @fires commons-case-submitted - The caller submitted the case; `detail.case`.
 * @csspart slot - One slot.
 * @csspart submit - The Submit button.
 */
export class CommonsUploadCase extends LitElement {
  static override properties = {
    baseUrl: {type: String, attribute: "base-url"},
    caseId: {type: String, attribute: "case-id"},
    auth: {attribute: false},
    case: {state: true, attribute: false},
    links: {state: true, attribute: false},
    busy: {state: true, attribute: false},
    error: {state: true, attribute: false}
  };

  declare baseUrl: string;
  declare caseId: string;
  declare auth?: AuthAdapter;
  /** @internal */
  declare case?: Case;
  /** @internal */
  declare links: Record<string, string>;
  /** @internal */
  declare busy: boolean;
  /** @internal */
  declare error?: string;
  private stream?: LiveStream;

  constructor() {
    super();
    this.baseUrl = "";
    this.caseId = "";
    this.links = {};
    this.busy = false;
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
    .thumbs img { width: 72px; height: 72px; object-fit: cover; border-radius: 6px; border: 1px solid var(--_border); }
    .thumbs a { font-size: 13px; color: var(--_accent); }
    button { font: inherit; padding: 6px 12px; border-radius: 6px; border: 1px solid var(--_accent);
      background: var(--_accent); color: #fff; cursor: pointer; justify-self: start; }
    button:disabled { opacity: .5; cursor: default; }
    .error { color: var(--_error); font-size: 13px; }
  `];

  override disconnectedCallback(): void {
    super.disconnectedCallback();
    this.stream?.stop();
  }

  override updated(changed: Map<string, unknown>): void {
    if ((changed.has("caseId") || changed.has("baseUrl")) && this.baseUrl && this.caseId) {
      this.stream?.stop();
      const refresh = (e: {caseId?: string; id?: string}) => (e.caseId ?? e.id) === this.caseId && void this.reload();
      this.stream = new LiveStream(this.baseUrl, {
        "attachment.uploaded": refresh, "attachment.deleted": refresh, "case.submitted": refresh,
        "case.reopened": refresh, "case.closed": refresh
      }, {auth: this.auth, onReconnect: () => void this.reload()});
      this.stream.start();
      void this.reload();
    }
  }

  async reload(): Promise<void> {
    try {
      const client = new AttachmentClient(this.baseUrl, this.auth);
      const loaded = await client.getCase(this.caseId);
      const links: Record<string, string> = {};
      for (const file of loaded.files ?? []) {
        links[file.id] = this.links[file.id] ?? await client.link(loaded.id, file.id).catch(() => "");
      }
      this.case = loaded;
      this.links = links;
      this.error = undefined;
    } catch (e) {
      this.error = (e as Error).message;
    }
  }

  private async upload(slot: Slot, input: HTMLInputElement): Promise<void> {
    const file = input.files?.[0];
    if (!file || !this.case) {
      return;
    }
    this.busy = true;
    try {
      const attachment = await new AttachmentClient(this.baseUrl, this.auth).upload(this.case.id, slot.name, file);
      this.dispatchEvent(new CustomEvent("commons-file-uploaded", {detail: {attachment}, bubbles: true, composed: true}));
      await this.reload();
    } catch (e) {
      this.error = (e as Error).message;
    } finally {
      this.busy = false;
      input.value = "";
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

  override render() {
    const c = this.case;
    if (!c) {
      return this.error ? html`<div class="error" role="alert">${this.error}</div>` : html`<div class="meta">Loading…</div>`;
    }
    const open = c.status === "OPEN";
    return html`
      <div class="head"><strong>${c.title}</strong><span class="status ${c.status}">${c.status}</span></div>
      ${c.statusReason ? html`<div class="reason">${c.statusReason}</div>` : nothing}
      ${c.slots.map((slot) => {
        const files = (c.files ?? []).filter((f) => f.slot === slot.name);
        return html`<div class="slot ${slot.satisfied ? "done" : ""}" part="slot">
          <div><strong>${slot.label}</strong> <span class="meta">${slot.fileCount}/${slot.maxFiles}
            · ${slot.mimeTypes.join(", ") || "any type"}${slot.minFiles === 0 ? " · optional" : ""}</span></div>
          ${slot.description ? html`<div class="meta">${slot.description}</div>` : nothing}
          <div class="thumbs">${files.map((f) => f.mimeType.startsWith("image/") && this.links[f.id]
            ? html`<img src=${this.links[f.id]} alt=${f.fileName} title=${f.fileName}>`
            : html`<a href=${this.links[f.id] ?? "#"} target="_blank" rel="noopener">${f.fileName}</a>`)}</div>
          ${open && slot.fileCount < slot.maxFiles ? html`<input type="file" aria-label="Upload ${slot.label}"
              accept=${slot.mimeTypes.join(",")} ?disabled=${this.busy}
              @change=${(e: Event) => this.upload(slot, e.target as HTMLInputElement)}>` : nothing}
        </div>`;
      })}
      ${open && !c.autoSubmit ? html`<button part="submit" ?disabled=${!c.slots.every((s) => s.satisfied)}
          @click=${this.submit}>Submit</button>` : nothing}
      ${this.error ? html`<div class="error" role="alert">${this.error}</div>` : nothing}
    `;
  }
}

if (!customElements.get("commons-upload-case")) {
  customElements.define("commons-upload-case", CommonsUploadCase);
}

declare global {
  interface HTMLElementTagNameMap {
    "commons-upload-case": CommonsUploadCase;
  }
}
