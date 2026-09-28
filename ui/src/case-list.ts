import {type AuthAdapter, relativeTime, tokens} from "@bal-commons/ui-core";
import {css, html, LitElement, nothing} from "lit";
import {AttachmentClient} from "./client.js";
import {feedFor} from "./feed.js";
import type {Case, CaseQuery, CaseStatus} from "./types.js";

/**
 * Upload cases, newest first: the caller's own, or every case for an admin role. Each shows its status
 * and slot progress, and whether the caller still has to upload something. Kept live.
 * @fires commons-case-select - A case was chosen; `detail.case`.
 * @csspart list - The case list.
 * @csspart item - One case.
 * @csspart empty - The empty state.
 * @slot empty - Replaces the "No cases." text.
 */
export class CommonsCaseList extends LitElement {
  static override properties = {
    baseUrl: {type: String, attribute: "base-url"},
    auth: {attribute: false},
    me: {type: String},
    selected: {type: String, reflect: true},
    status: {type: String},
    correlationId: {type: String, attribute: "correlation-id"},
    admin: {type: Boolean},
    subject: {type: String},
    pageSize: {type: Number, attribute: "page-size"},
    items: {state: true, attribute: false},
    nextCursor: {state: true, attribute: false},
    error: {state: true, attribute: false},
    loaded: {state: true, attribute: false}
  };

  declare baseUrl: string;
  declare auth?: AuthAdapter;
  /** The caller's user ID, used for the "Needs your upload" marker. */
  declare me?: string;
  /** ID of the highlighted case. */
  declare selected?: string;
  /** Shows only `OPEN`, `SUBMITTED` or `CLOSED` cases; all when unset. */
  declare status?: CaseStatus;
  /** Shows only the cases about this business object. */
  declare correlationId?: string;
  /** Lists every case (`/admin/cases`); needs an admin role with `read`. */
  declare admin: boolean;
  /** With `admin`: only the cases this user is a subject of. */
  declare subject?: string;
  declare pageSize: number;
  /** @internal */
  declare items: Case[];
  /** @internal */
  declare nextCursor?: string;
  /** @internal */
  declare error?: string;
  /** @internal */
  declare loaded: boolean;
  private unsubscribe?: () => void;
  private pending?: ReturnType<typeof setTimeout>;

  constructor() {
    super();
    this.baseUrl = "";
    this.admin = false;
    this.pageSize = 20;
    this.items = [];
    this.loaded = false;
  }

  static override styles = [tokens, css`
    :host { display: block; }
    ul { list-style: none; margin: 0; padding: 0; display: grid; grid-template-columns: minmax(0, 1fr); gap: 4px; }
    li { padding: 8px 10px; border-radius: 6px; border: 1px solid transparent; cursor: pointer; }
    li:hover { background: var(--_surface); }
    li[aria-selected="true"] { border-color: var(--_accent); background: var(--_accent-soft); }
    li:focus-visible { outline: 2px solid var(--_accent); }
    .top { display: flex; gap: 6px; align-items: center; }
    .title { flex: 1; font-weight: 600; font-size: 14px; min-width: 0; overflow: hidden; text-overflow: ellipsis;
      white-space: nowrap; }
    .status { font-size: 11px; padding: 1px 8px; border-radius: 8px; background: var(--_surface); white-space: nowrap; }
    .status.SUBMITTED { background: var(--_accent-soft); } .status.CLOSED { color: var(--_muted); }
    .todo { font-size: 11px; color: var(--_warning); white-space: nowrap; }
    .meta { font-size: 12px; color: var(--_muted); }
    .bar { height: 3px; background: var(--_surface); border-radius: 2px; margin-top: 4px; overflow: hidden; }
    .bar span { display: block; height: 100%; background: var(--_success); }
    .more { display: block; margin: 6px auto; font: inherit; font-size: 12px; padding: 4px 10px; cursor: pointer;
      border: 1px solid var(--_border); border-radius: 6px; background: none; color: var(--_fg); }
    .empty, .error { padding: 12px; font-size: 13px; color: var(--_muted); }
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
    if (changed.has("baseUrl")) {
      this.start();
    } else if (["status", "correlationId", "admin", "subject"].some((name) => changed.has(name))) {
      void this.reload();
    }
  }

  private start(): void {
    this.unsubscribe?.();
    this.unsubscribe = undefined;
    if (!this.baseUrl || !this.isConnected) {
      return;
    }
    // Any case or file change can reorder the list or move a progress bar: refetch, debounced.
    this.unsubscribe = feedFor(this.baseUrl, this.auth).subscribe(() => {
      clearTimeout(this.pending);
      this.pending = setTimeout(() => void this.reload(), 300);
    });
    void this.reload();
  }

  private query(cursor?: string, limit = this.pageSize): CaseQuery {
    return {status: this.status || undefined, correlationId: this.correlationId || undefined,
      subject: this.admin ? this.subject || undefined : undefined, limit, cursor};
  }

  private fetchPage(cursor?: string, limit?: number) {
    const client = new AttachmentClient(this.baseUrl, this.auth);
    return this.admin ? client.listAllCases(this.query(cursor, limit)) : client.listCases(this.query(cursor, limit));
  }

  // Refetches as many cases as are shown (up to 100), so a live refresh keeps pages loaded with "Load more".
  async reload(): Promise<void> {
    try {
      const page = await this.fetchPage(undefined, Math.min(100, Math.max(this.pageSize, this.items.length)));
      this.loaded = true;
      this.items = page.items;
      this.nextCursor = page.nextCursor;
      this.error = undefined;
    } catch (e) {
      this.error = (e as Error).message;
    }
  }

  private async loadMore(): Promise<void> {
    if (!this.nextCursor) {
      return;
    }
    try {
      const page = await this.fetchPage(this.nextCursor);
      this.items = [...this.items, ...page.items.filter((c) => !this.items.some((i) => i.id === c.id))];
      this.nextCursor = page.nextCursor;
    } catch (e) {
      this.error = (e as Error).message;
    }
  }

  private select(c: Case): void {
    this.selected = c.id;
    this.dispatchEvent(new CustomEvent("commons-case-select", {detail: {case: c}, bubbles: true, composed: true}));
  }

  override render() {
    if (this.error) {
      return html`<div class="error" role="alert">${this.error}</div>`;
    }
    if (!this.loaded) {
      return html`<div class="empty" role="status">Loading…</div>`;
    }
    if (!this.items.length) {
      return html`<div class="empty" part="empty"><slot name="empty">No cases.</slot></div>`;
    }
    return html`<ul part="list" role="listbox" aria-label="Upload cases">
      ${this.items.map((c) => {
        const done = c.slots.filter((s) => s.satisfied).length;
        const todo = c.status === "OPEN" && !!this.me && c.subjects.includes(this.me) && done < c.slots.length;
        return html`<li part="item" role="option" tabindex="0" aria-selected=${this.selected === c.id}
            @click=${() => this.select(c)} @keydown=${(e: KeyboardEvent) => e.key === "Enter" && this.select(c)}>
          <div class="top">
            <span class="title" title=${c.title}>${c.title}</span>
            ${todo ? html`<span class="todo">Needs your upload</span>` : nothing}
            <span class="status ${c.status}">${c.status.toLowerCase()}</span>
          </div>
          <div class="meta">${done}/${c.slots.length} slots ·
            ${this.admin ? html`${c.subjects.join(", ")} · ` : nothing}
            <span title=${c.updatedAt}>${relativeTime(c.updatedAt)}</span></div>
          <div class="bar"><span style="width:${c.slots.length ? Math.round(done / c.slots.length * 100) : 100}%"></span></div>
        </li>`;
      })}
    </ul>
    ${this.nextCursor ? html`<button class="more" @click=${() => this.loadMore()}>Load more</button>` : nothing}`;
  }
}

if (!customElements.get("commons-case-list")) {
  customElements.define("commons-case-list", CommonsCaseList);
}
