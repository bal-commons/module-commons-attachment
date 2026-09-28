import type {Attachment} from "./types.js";

export type PreviewKind = "image" | "pdf" | "video" | "audio" | "text" | "none";

// How a file can be shown in the browser. Text previews are capped, so large logs don't freeze the page.
export function previewKind(file: Attachment): PreviewKind {
  const type = file.mimeType.toLowerCase();
  if (type.startsWith("image/")) return "image";
  if (type === "application/pdf") return "pdf";
  if (type.startsWith("video/")) return "video";
  if (type.startsWith("audio/")) return "audio";
  if ((type.startsWith("text/") || type === "application/json" || type.endsWith("+json") || type.endsWith("+xml")
      || type === "application/xml") && file.sizeBytes <= 256 * 1024) return "text";
  return "none";
}

export function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  const units = ["KB", "MB", "GB"];
  let value = bytes / 1024;
  let unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return `${value < 10 ? value.toFixed(1) : Math.round(value)} ${units[unit]}`;
}

// A short badge for a file with no thumbnail, e.g. "PDF".
export function typeBadge(file: Attachment): string {
  const extension = file.fileName.includes(".") ? file.fileName.split(".").pop()! : "";
  return (extension || file.mimeType.split("/").pop() || "file").slice(0, 4).toUpperCase();
}

// Saves a Blob under a file name, through a temporary object URL.
export function saveBlob(blob: Blob, fileName: string): void {
  const url = URL.createObjectURL(blob);
  const anchor = Object.assign(document.createElement("a"), {href: url, download: fileName});
  document.body.append(anchor);
  anchor.click();
  anchor.remove();
  setTimeout(() => URL.revokeObjectURL(url), 10_000);
}
