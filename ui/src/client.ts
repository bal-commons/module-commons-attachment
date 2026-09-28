import {type AuthAdapter, defaultAuth, request, ServiceError} from "@bal-commons/ui-core";
import type {Attachment, Case} from "./types.js";

// Typed calls to the attachment service, as the signed-in user.
export class AttachmentClient {
  constructor(readonly baseUrl: string, private readonly auth?: AuthAdapter) {}

  getCase(id: string): Promise<Case> {
    return request(this.baseUrl, `/cases/${encodeURIComponent(id)}`, {auth: this.auth});
  }

  listCases(options: {status?: string; correlationId?: string} = {}): Promise<{items: Case[]}> {
    return request(this.baseUrl, "/cases", {auth: this.auth, query: {...options}});
  }

  async upload(caseId: string, slot: string, file: File): Promise<Attachment> {
    const auth = this.auth ?? defaultAuth();
    const url = `${this.baseUrl.replace(/\/+$/, "")}/cases/${encodeURIComponent(caseId)}/slots/${encodeURIComponent(slot)}`
        + `/files?fileName=${encodeURIComponent(file.name)}`;
    const response = await fetch(url, {method: "POST", body: file,
        headers: {...(await auth.headers()), "content-type": file.type || "application/octet-stream"}});
    if (!response.ok) {
      const body = await response.json().catch(() => ({})) as {code?: string; message?: string};
      throw new ServiceError(response.status, body.code ?? `HTTP_${response.status}`, body.message ?? response.statusText);
    }
    return response.json();
  }

  submit(caseId: string): Promise<Case> {
    return request(this.baseUrl, `/cases/${encodeURIComponent(caseId)}/submit`, {method: "POST", auth: this.auth});
  }

  // A short-lived URL that needs no credentials, e.g. for an <img>. The service returns a path under its base path.
  async link(caseId: string, fileId: string): Promise<string> {
    const {url} = await request<{url: string}>(this.baseUrl,
        `/cases/${encodeURIComponent(caseId)}/files/${encodeURIComponent(fileId)}/link`, {method: "POST", auth: this.auth});
    const base = new URL(this.baseUrl, globalThis.location?.href);
    const servicePath = base.pathname.replace(/\/+$/, "");
    const relative = url.startsWith(servicePath) ? url.slice(servicePath.length) : url.replace(/^\/[^/]+\/v\d+/, "");
    return this.baseUrl.replace(/\/+$/, "") + relative;
  }
}
