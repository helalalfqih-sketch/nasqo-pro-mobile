import { HybridBridgeError, hybridBridge } from "./bridge";
import type { HybridPickFileResult } from "./contracts";

export interface BackupInspectionStatus {
  phase: string;
  result?: HybridPickFileResult | null;
  error?: string;
}

export interface BackupInspectionPollOptions {
  /** Injected for deterministic tests. Never reopens Android's file picker. */
  requestStatus?: (jobId: string) => Promise<BackupInspectionStatus>;
  wait?: (ms: number) => Promise<void>;
  clock?: () => number;
  deadlineMs?: number;
  onPhase?: (phase: string) => void;
}

const statusFromDart = (jobId: string) =>
  hybridBridge.invoke<"getBackupInspectionStatus", BackupInspectionStatus>(
    "getBackupInspectionStatus",
    { jobId },
    { timeoutMs: 15_000 },
  );

/** Poll a single native job, never retry beginBackupInspection/pickFile.
 * Transient response timeouts cannot cancel Dart's ongoing SQLite inspection.
 * An explicit native failure, invalid reply, or overall deadline fails closed.
 */
export async function awaitBackupInspection(
  jobId: string,
  options: BackupInspectionPollOptions = {},
): Promise<HybridPickFileResult> {
  if (!jobId || !/^[0-9a-f]{48}$/i.test(jobId)) {
    throw new Error("معرّف فحص النسخة غير صالح.");
  }
  const requestStatus = options.requestStatus ?? statusFromDart;
  const wait = options.wait ??
    ((ms: number) => new Promise<void>((resolve) => window.setTimeout(resolve, ms)));
  const clock = options.clock ?? Date.now;
  const deadline = clock() + (options.deadlineMs ?? 7 * 60_000);
  while (clock() < deadline) {
    await wait(850);
    let status: BackupInspectionStatus;
    try {
      status = await requestStatus(jobId);
    } catch (error) {
      if (error instanceof HybridBridgeError && error.code === "TIMEOUT") {
        options.onPhase?.("waiting");
        // React may be paused under the Android picker while native SQLite
        // continues. Keep checking this SAME job; do not duplicate an import.
        continue;
      }
      throw error;
    }
    if (!status || typeof status.phase !== "string") {
      throw new Error("رد فحص النسخة غير صالح؛ لم تتغير قاعدة البيانات.");
    }
    if (status.phase === "failed") {
      throw new Error(status.error || "فشل فحص النسخة المحلية؛ لم تتغير قاعدة الهاتف.");
    }
    if (status.phase === "complete") {
      if (!status.result) {
        throw new Error("لم تصل نتيجة فحص SQLite؛ لم تتغير قاعدة الهاتف.");
      }
      return status.result;
    }
    if (!["picking", "reading", "auditing", "verifying"].includes(status.phase)) {
      throw new Error("حالة فحص SQLite غير معروفة؛ لم تتغير قاعدة الهاتف.");
    }
    options.onPhase?.(status.phase);
  }
  throw new Error(
    "لم يصل تأكيد فحص SQLite ضمن الحد الآمن. لا تبدأ استيرادًا ثانيًا؛ البيانات الحالية لم تتغير.",
  );
}
