import {type AuthAdapter, defaultAuth, joinUrl, request, ServiceError} from "@bal-commons/ui-core";
import type {Attachment, Case, CasePage, CaseQuery} from "./types.js";

// Signed links are short-lived: reuse one until shortly before it expires.
const links = new Map<string, {url: string; expires: number}>();

// Typed calls to the attachment service, as the signed-in user.
export class AttachmentClient {
  constructor(readonly baseUrl: string, private readonly auth?: AuthAdapter) {}

  getCase(id: string): Promise<Case> {
    return request(this.baseUrl, `/cases/${encodeURIComponent(id)}`, {auth: this.auth});
  }

  // The cases the caller is a subject of.
  listCases(options: CaseQuery = {}): Promise<CasePage> {
    return request(this.baseUrl, "/cases", {auth: this.auth, query: {...options, subject: undefined}});
  }

  // Every case, for admin roles with `read`; `subject` narrows it to one user's.
  listAllCases(options: CaseQuery = {}): Promise<CasePage> {
    return request(this.baseUrl, "/admin/cases", {auth: this.auth, query: {...options}});
  }

  async upload(caseId: string, slot: string, file: File): Promise<Attachment> {
    const auth = this.auth ?? defaultAuth();
    const url = joinUrl(this.baseUrl, `/cases/${encodeURIComponent(caseId)}/slots/${encodeURIComponent(slot)}/files`,
        {fileName: file.name});
    const response = await fetch(url, {method: "POST", body: file,
        headers: {...(await auth.headers()), "content-type": file.type || "application/octet-stream"}});
    if (!response.ok) {
      if (response.status === 401) {
        auth.onUnauthorized?.();
      }
      const body = await response.json().catch(() => ({})) as {code?: string; message?: string};
      throw new ServiceError(response.status, body.code ?? `HTTP_${response.status}`, body.message ?? response.statusText);
    }
    return response.json();
  }

  deleteFile(caseId: string, fileId: string): Promise<void> {
    return request(this.baseUrl, `/cases/${encodeURIComponent(caseId)}/files/${encodeURIComponent(fileId)}`,
        {method: "DELETE", auth: this.auth});
  }

  submit(caseId: string): Promise<Case> {
    return request(this.baseUrl, `/cases/${encodeURIComponent(caseId)}/submit`, {method: "POST", auth: this.auth});
  }

  // The file's bytes, with the caller's credentials; for a download or a preview that can't use a link.
  async download(caseId: string, fileId: string): Promise<Blob> {
    const auth = this.auth ?? defaultAuth();
    const response = await fetch(joinUrl(this.baseUrl,
        `/cases/${encodeURIComponent(caseId)}/files/${encodeURIComponent(fileId)}/content`), {headers: await auth.headers()});
    if (!response.ok) {
      if (response.status === 401) {
        auth.onUnauthorized?.();
      }
      const body = await response.json().catch(() => ({})) as {code?: string; message?: string};
      throw new ServiceError(response.status, body.code ?? `HTTP_${response.status}`, body.message ?? response.statusText);
    }
    return response.blob();
  }

  // A short-lived URL that needs no credentials, e.g. for an <img>. The service returns a path under its base path.
  async link(caseId: string, fileId: string): Promise<string> {
    const cached = links.get(fileId);
    if (cached && cached.expires - Date.now() > 30_000) {
      return cached.url;
    }
    const {url, expiresAt} = await request<{url: string; expiresAt: string}>(this.baseUrl,
        `/cases/${encodeURIComponent(caseId)}/files/${encodeURIComponent(fileId)}/link`, {method: "POST", auth: this.auth});
    const base = new URL(this.baseUrl, globalThis.location?.href);
    const servicePath = base.pathname.replace(/\/+$/, "");
    const relative = url.startsWith(servicePath) ? url.slice(servicePath.length) : url.replace(/^\/[^/]+\/v\d+/, "");
    const resolved = this.baseUrl.replace(/\/+$/, "") + relative;
    links.set(fileId, {url: resolved, expires: new Date(expiresAt).getTime()});
    return resolved;
  }
}
