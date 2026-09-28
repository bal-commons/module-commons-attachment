import {type AuthAdapter, LiveStream} from "@bal-commons/ui-core";
import type {Attachment, Case} from "./types.js";

export type AttachmentChange =
  | {type: "case"; event: string; case: Case}
  | {type: "file"; event: string; caseId: string; attachment: Attachment}
  | {type: "reconnected"};

// One live stream per attachment service URL, shared by every component on the page. The service does not replay
// missed events, so components refetch on `reconnected`.
class AttachmentFeed extends EventTarget {
  private stream?: LiveStream;
  private users = 0;

  constructor(private readonly baseUrl: string, private readonly auth?: AuthAdapter) {
    super();
  }

  subscribe(listener: (change: AttachmentChange) => void): () => void {
    const handler = (e: Event) => listener((e as CustomEvent<AttachmentChange>).detail);
    this.addEventListener("change", handler);
    if (this.users++ === 0) {
      const onCase = (event: string) => (c: Case) => this.emit({type: "case", event, case: c});
      const onFile = (event: string) => ({caseId, attachment}: {caseId: string; attachment: Attachment}) =>
        this.emit({type: "file", event, caseId, attachment});
      this.stream = new LiveStream(this.baseUrl, {
        "case.created": onCase("case.created"),
        "case.submitted": onCase("case.submitted"),
        "case.reopened": onCase("case.reopened"),
        "case.closed": onCase("case.closed"),
        "attachment.uploaded": onFile("attachment.uploaded"),
        "attachment.deleted": onFile("attachment.deleted")
      }, {auth: this.auth, onReconnect: () => this.emit({type: "reconnected"})});
      this.stream.start();
    }
    return () => {
      this.removeEventListener("change", handler);
      if (--this.users === 0) {
        this.stream?.stop();
        this.stream = undefined;
      }
    };
  }

  private emit(change: AttachmentChange): void {
    this.dispatchEvent(new CustomEvent("change", {detail: change}));
  }
}

const feeds = new Map<string, AttachmentFeed>();

export function feedFor(baseUrl: string, auth?: AuthAdapter): AttachmentFeed {
  let feed = feeds.get(baseUrl);
  if (!feed) {
    feed = new AttachmentFeed(baseUrl, auth);
    feeds.set(baseUrl, feed);
  }
  return feed;
}

// The case an event is about.
export function caseIdOf(change: AttachmentChange): string | undefined {
  return change.type === "case" ? change.case.id : change.type === "file" ? change.caseId : undefined;
}
