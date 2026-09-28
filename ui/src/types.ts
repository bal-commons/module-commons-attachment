export type CaseStatus = "OPEN" | "SUBMITTED" | "CLOSED";

export interface Slot {
  name: string;
  label: string;
  description?: string;
  mimeTypes: string[];
  maxBytes: number;
  minFiles: number;
  maxFiles: number;
  fileCount: number;
  satisfied: boolean;
}

export interface Attachment {
  id: string;
  caseId: string;
  slot: string;
  fileName: string;
  mimeType: string;
  sizeBytes: number;
  sha256: string;
  uploadedBy: string;
  uploadedAt: string;
}

export interface Case {
  id: string;
  correlationId: string;
  title: string;
  description?: string;
  status: CaseStatus;
  subjects: string[];
  watchers?: string[];
  createdBy: string;
  slots: Slot[];
  files?: Attachment[];
  autoSubmit: boolean;
  dueAt?: string;
  statusReason?: string;
  createdAt: string;
  updatedAt: string;
}

export interface CasePage {
  items: Case[];
  nextCursor?: string;
}

export interface CaseQuery {
  status?: CaseStatus;
  correlationId?: string;
  // Admin listing only.
  subject?: string;
  cursor?: string;
  limit?: number;
}
