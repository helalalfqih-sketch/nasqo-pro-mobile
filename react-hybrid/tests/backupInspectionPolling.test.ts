import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { HybridBridgeError } from "../src/hybrid/bridge";
import { awaitBackupInspection } from "../src/hybrid/backupInspectionPolling";

const jobId = "a".repeat(48);

describe("Android SmartPro inspection status polling", () => {
  it("retries transient TIMEOUT against the same job and receives a read-only preview", async () => {
    const calls: string[] = [];
    const phases: string[] = [];
    let clock = 0;
    let attempt = 0;
    const result = await awaitBackupInspection(jobId, {
      clock: () => clock,
      wait: async (ms) => { clock += ms; },
      onPhase: phase => phases.push(phase),
      requestStatus: async (requestedJob) => {
        calls.push(requestedJob);
        attempt += 1;
        if (attempt === 1) return { phase: "auditing" };
        if (attempt === 2) throw new HybridBridgeError("TIMEOUT", "temporary pause", true);
        return {
          phase: "complete",
          result: {
            fileName: "smartpro.back",
            previewToken: "opaque-preview-token",
            preview: {
              fileName: "smartpro.back",
              format: "SQLite",
              version: 28,
              sizeBytes: 512,
              sourceSha256: "c".repeat(64),
              counts: {
                accounts: 0, groups: 0, currencies: 0, invoices: 0,
                vouchers: 0, movements: 0, invoiceLines: 0, warehouses: 0, items: 0,
              },
              unsupported: [],
              trialIntegrity: "ok",
              trialMatchedRecords: 0,
              canRestore: false,
              previewToken: "opaque-preview-token",
            },
          },
        };
      },
    });
    assert.deepEqual(calls, [jobId, jobId, jobId]);
    assert.deepEqual(phases, ["auditing", "waiting"]);
    assert.equal(result.preview?.version, 28);
    assert.equal(result.preview?.canRestore, false);
  });

  it("fails closed on native inspection error without a fresh file selection", async () => {
    let calls = 0;
    await assert.rejects(
      awaitBackupInspection(jobId, {
        clock: () => 0,
        wait: async () => {},
        requestStatus: async () => {
          calls += 1;
          return { phase: "failed", error: "Invalid SQLite schema" };
        },
      }),
      /Invalid SQLite schema/,
    );
    assert.equal(calls, 1);
  });

  it("does not turn an expired job or an empty complete reply into success", async () => {
    await assert.rejects(
      awaitBackupInspection(jobId, {
        clock: (() => {
          let n = 0;
          return () => n++;
        })(),
        deadlineMs: 0,
        wait: async () => {},
        requestStatus: async () => ({ phase: "verifying" }),
      }),
      /لم يصل تأكيد/,
    );
    await assert.rejects(
      awaitBackupInspection(jobId, {
        clock: () => 0,
        wait: async () => {},
        requestStatus: async () => ({ phase: "complete", result: null }),
      }),
      /لم تصل نتيجة/,
    );
  });

  it("rejects unknown states and never silently claims import completion", async () => {
    await assert.rejects(
      awaitBackupInspection(jobId, {
        clock: () => 0,
        wait: async () => {},
        requestStatus: async () => ({ phase: "unknown" }),
      }),
      /غير معروفة/,
    );
  });
});
