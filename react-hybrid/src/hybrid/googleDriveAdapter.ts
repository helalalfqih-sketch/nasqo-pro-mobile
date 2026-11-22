import { hybridBridge } from "./bridge";
import {
  buildDriveFilesListUrl,
  classifyDriveMimeType,
  DRIVE_DOC_MIME,
  DRIVE_FOLDER_MIME,
  DRIVE_SHEET_MIME,
  DRIVE_SLIDES_MIME,
  filterDriveFiles,
  formatDriveFileSize,
  getDriveMimeLabelAr,
  type DriveCategoryFilter,
  type DriveFileKind,
  type DriveFileRecord,
} from "../services/googleDriveHelpers";

export {
  buildDriveFilesListUrl,
  classifyDriveMimeType,
  DRIVE_DOC_MIME,
  DRIVE_FOLDER_MIME,
  DRIVE_SHEET_MIME,
  DRIVE_SLIDES_MIME,
  filterDriveFiles,
  formatDriveFileSize,
  getDriveMimeLabelAr,
  type DriveCategoryFilter,
  type DriveFileKind,
  type DriveFileRecord,
};

export interface DriveAboutInfo {
  user?: {
    displayName?: string;
    emailAddress?: string;
    photoLink?: string;
  };
  storageQuota?: {
    limit?: string;
    usage?: string;
    usageInDrive?: string;
  };
}

export class DriveAuthExpiredError extends Error {
  constructor(message = "انتهت صلاحية جلسة Google Drive في تطبيق Flutter. يرجى إعادة الربط.") {
    super(message);
    this.name = "DriveAuthExpiredError";
  }
}

export class DriveApiError extends Error {
  readonly status: number;
  constructor(message: string, status = 503) {
    super(message);
    this.name = "DriveApiError";
    this.status = status;
  }
}

async function callFlutterDrive<T>(operation: string, args: Record<string, unknown> = {}): Promise<T> {
  return hybridBridge.invoke<"googleDriveAction", T>("googleDriveAction", { operation, args });
}

export async function getDriveAbout(_accessToken: string): Promise<DriveAboutInfo> {
  return callFlutterDrive<DriveAboutInfo>("getAbout");
}

export async function listDriveFiles(
  _accessToken: string,
  options: { folderId?: string | null; pageSize?: number; queryText?: string } = {},
): Promise<DriveFileRecord[]> {
  return callFlutterDrive<DriveFileRecord[]>("listFiles", options);
}

export async function findOrCreateDriveFolder(
  _accessToken: string,
  folderName: string,
  parentId?: string,
): Promise<DriveFileRecord> {
  return callFlutterDrive<DriveFileRecord>("findOrCreateFolder", { folderName, parentId });
}

export async function createDriveFolder(
  _accessToken: string,
  folderName: string,
  parentId?: string,
): Promise<DriveFileRecord> {
  return callFlutterDrive<DriveFileRecord>("createFolder", { folderName, parentId });
}

export async function uploadFileToDrive(
  _accessToken: string,
  options: { name: string; content: string | Uint8Array; mimeType: string; parentId?: string; description?: string },
): Promise<DriveFileRecord> {
  const payloadContent =
    typeof options.content === "string"
      ? options.content
      : btoa(Array.from(options.content, (b) => String.fromCharCode(b)).join(""));
  return callFlutterDrive<DriveFileRecord>("uploadFile", {
    name: options.name,
    mimeType: options.mimeType,
    parentId: options.parentId,
    description: options.description,
    isBase64: typeof options.content !== "string",
    content: payloadContent,
  });
}

export async function updateDriveFileContent(
  _accessToken: string,
  fileId: string,
  options: { name?: string; content: string | Uint8Array; mimeType: string; description?: string },
): Promise<DriveFileRecord> {
  const payloadContent =
    typeof options.content === "string"
      ? options.content
      : btoa(Array.from(options.content, (b) => String.fromCharCode(b)).join(""));
  return callFlutterDrive<DriveFileRecord>("updateFile", {
    fileId,
    name: options.name,
    mimeType: options.mimeType,
    description: options.description,
    isBase64: typeof options.content !== "string",
    content: payloadContent,
  });
}

export async function downloadDriveFileBytes(
  _accessToken: string,
  file: DriveFileRecord,
): Promise<{ bytes: Uint8Array; downloadName: string; mimeType: string }> {
  const res = await callFlutterDrive<{ base64Content: string; downloadName: string; mimeType: string }>(
    "downloadFile",
    { fileId: file.id, fileName: file.name, mimeType: file.mimeType },
  );
  const bin = atob(res.base64Content || "");
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i += 1) bytes[i] = bin.charCodeAt(i);
  return {
    bytes,
    downloadName: res.downloadName || file.name,
    mimeType: res.mimeType || file.mimeType || "application/octet-stream",
  };
}

export async function trashDriveFile(_accessToken: string, fileId: string): Promise<void> {
  await callFlutterDrive<void>("trashFile", { fileId });
}

export async function deleteDriveFilePermanently(_accessToken: string, fileId: string): Promise<void> {
  await callFlutterDrive<void>("deleteFilePermanently", { fileId });
}
