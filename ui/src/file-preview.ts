import {type AuthAdapter, relativeTime, tokens} from "@bal-commons/ui-core";
import {css, html, LitElement, nothing} from "lit";
import {AttachmentClient} from "./client.js";
import {formatBytes, previewKind, saveBlob} from "./files.js";
import type {Attachment} from "./types.js";

/**
 * A modal preview of one file: images, PDFs, video, audio and small text files inline; anything else offers a
 * download. `<commons-file-viewer>` and `<commons-upload-case>` open one when a file is clicked.
 * @fires commons-file-downloaded - The caller downloaded the file; `detail.attachment`.
 * @fires commons-preview-close - The preview was closed.
 * @csspart dialog - The dialog.
 * @csspart body - The preview area.
 * @csspart toolbar - File name, details and the Download and Close buttons.
 */
export class CommonsFilePreview extends LitElement {
  static override properties = {
    baseUrl: {type: String, attribute: "base-url"},
    auth: {attribute: false},
    file: {attribute: false},
    url: {state: true, attribute: false},
    text: {state: true, attribute: false},
    error: {state: true, attribute: false}
  };

  declare baseUrl: string;
  declare auth?: AuthAdapter;
  /** The file to show; set it, then call `show()`. */
  declare file?: Attachment;
  /** @internal */
  declare url?: string;
  /** @internal */
  declare text?: string;
  /** @internal */
  declare error?: string;

  constructor() {
    super();
    this.baseUrl = "";
  }

  static override styles = [tokens, css`
    dialog { width: min(960px, 94vw); height: min(720px, 90vh); padding: 0; border: 1px solid var(--_border);
      border-radius: var(--_radius); background: var(--_bg); color: var(--_fg); overflow: hidden; }
    dialog[open] { display: flex; flex-direction: column; }
    dialog::backdrop { background: rgb(0 0 0 / .55); }
    .bar { display: flex; gap: 8px; align-items: center; padding: 8px 12px; border-bottom: 1px solid var(--_border); }
    .name { flex: 1; min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; font-weight: 600; }
    .meta { font-size: 12px; color: var(--_muted); white-space: nowrap; }
    button { font: inherit; font-size: 13px; padding: 5px 10px; border-radius: 6px; cursor: pointer;
      border: 1px solid var(--_border); background: var(--_surface); color: var(--_fg); }
    button:focus-visible { outline: 2px solid var(--_accent); }
    .open { font-size: 13px; color: var(--_accent); white-space: nowrap; }
    .body { flex: 1; min-height: 0; display: grid; place-items: center; background: var(--_surface); overflow: auto; }
    img, video { max-width: 100%; max-height: 100%; object-fit: contain; }
    iframe { width: 100%; height: 100%; border: 0; background: #fff; }
    pre { align-self: start; justify-self: stretch; margin: 0; padding: 12px; font-size: 12px; white-space: pre-wrap;
      word-break: break-word; }
    .none { text-align: center; color: var(--_muted); display: grid; gap: 10px; justify-items: center; }
    .error { color: var(--_error); }
  `];

  // Opens the preview for `file` (or the file already set).
  async show(file?: Attachment): Promise<void> {
    if (file) {
      this.file = file;
    }
    if (!this.file) {
      return;
    }
    this.url = undefined;
    this.text = undefined;
    this.error = undefined;
    await this.updateComplete;
    this.renderRoot.querySelector("dialog")?.showModal();
    const current = this.file;
    // Another show() may have switched the file while this one waited.
    const stale = () => this.file !== current;
    try {
      const client = new AttachmentClient(this.baseUrl, this.auth);
      const kind = previewKind(current);
      if (kind === "text") {
        const text = await (await client.download(current.caseId, current.id)).text();
        if (!stale()) this.text = text;
      } else if (kind !== "none") {
        const url = await client.link(current.caseId, current.id);
        if (!stale()) this.url = url;
      }
    } catch (e) {
      if (!stale()) this.error = (e as Error).message;
    }
  }

  close(): void {
    this.renderRoot.querySelector("dialog")?.close();
  }

  private async download(): Promise<void> {
    const file = this.file;
    if (!file) {
      return;
    }
    try {
      saveBlob(await new AttachmentClient(this.baseUrl, this.auth).download(file.caseId, file.id), file.fileName);
      this.dispatchEvent(new CustomEvent("commons-file-downloaded", {detail: {attachment: file}, bubbles: true, composed: true}));
    } catch (e) {
      this.error = (e as Error).message;
    }
  }

  private body() {
    const file = this.file!;
    if (this.error) {
      return html`<div class="error" role="alert">${this.error}</div>`;
    }
    const kind = previewKind(file);
    if (kind === "none") {
      return html`<div class="none">No preview for ${file.mimeType}.
        <button @click=${this.download}>Download ${file.fileName}</button></div>`;
    }
    if (kind === "text") {
      return this.text === undefined ? html`<span class="meta">Loading…</span>` : html`<pre>${this.text}</pre>`;
    }
    if (!this.url) {
      return html`<span class="meta">Loading…</span>`;
    }
    switch (kind) {
      case "image": return html`<img src=${this.url} alt=${file.fileName}>`;
      case "pdf": return html`<iframe src=${this.url} title=${file.fileName}></iframe>`;
      case "video": return html`<video src=${this.url} controls></video>`;
      default: return html`<audio src=${this.url} controls></audio>`;
    }
  }

  override render() {
    const file = this.file;
    return html`<dialog part="dialog" aria-label=${file?.fileName ?? "File preview"}
        @close=${() => this.dispatchEvent(new CustomEvent("commons-preview-close", {bubbles: true, composed: true}))}>
      ${file ? html`
        <div class="bar" part="toolbar">
          <span class="name" title=${file.fileName}>${file.fileName}</span>
          <span class="meta">${formatBytes(file.sizeBytes)} · ${file.uploadedBy} ·
            <span title=${file.uploadedAt}>${relativeTime(file.uploadedAt)}</span></span>
          ${this.url ? html`<a class="open" href=${this.url} target="_blank" rel="noopener">Open in new tab</a>` : nothing}
          <button @click=${this.download}>Download</button>
          <button @click=${this.close} aria-label="Close preview">Close</button>
        </div>
        <div class="body" part="body">${this.body()}</div>` : nothing}
    </dialog>`;
  }
}

if (!customElements.get("commons-file-preview")) {
  customElements.define("commons-file-preview", CommonsFilePreview);
}
