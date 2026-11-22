import { useCallback, useEffect, useState, type ChangeEvent } from "react";
import {
  downloadUnifiedSqliteFile,
  fetchArchiveSummary,
  fetchUnifiedJsonExport,
  importSmartProSqlIntoServer,
  importSqliteBytesIntoServer,
  listUnifiedSqliteTables,
  queryUnifiedSqliteTable,
  type ArchiveSummaryPayload,
  type UnifiedTableMeta,
} from "../firebase";
import type {
  AccountRecord,
  InventoryItemRecord,
  LedgerEntryRecord,
  WarehouseRecord,
  WorkspaceSettings,
} from "../types";
import { runWithBrandLoader } from "../utils/brandLoaderBus";
import { useHybridPresentation } from "../hybrid/presentationAdapter";
import { hybridBridge } from "../hybrid/bridge";
import { awaitBackupInspection } from "../hybrid/backupInspectionPolling";
import { createIdempotencyKey, type NativeWebImportPreview, type HybridPickFileResult, type HybridWorkspaceSnapshot, type SmartProArchiveInfo } from "../hybrid/contracts";
import { applyHybridSnapshot, refreshWorkspaceFromServer } from "../hybrid/serviceAdapter";

type Props = {
  open: boolean;
  onClose: () => void;
  workspaceId: string;
  liveWorkspace: WorkspaceSettings | null;
  liveAccounts: readonly AccountRecord[];
  liveWarehouses: readonly WarehouseRecord[];
  liveInventory: readonly InventoryItemRecord[];
  liveLedger: readonly LedgerEntryRecord[];
  onNotify: (message: string) => void;
};

type InspectedUpload =
  | {
      kind: "sqlite";
      fileName: string;
      bytes: Uint8Array;
      sha256: string;
      integrity: string;
      tablesCount: number;
      totalRows: number;
      tableCounts: Record<string, number>;
    }
  | {
      kind: "sql";
      fileName: string;
      sqlText: string;
      byteLength: number;
    };

export function FullSqliteImportModal({
  open,
  onClose,
  workspaceId,
  liveAccounts,
  liveWarehouses,
  liveInventory,
  liveLedger,
  onNotify,
}: Props) {
  const [tab, setTab] = useState<"overview" | "tables" | "audit">("overview");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const [upload, setUpload] = useState<InspectedUpload | null>(null);
  const [replaceExistingSql, setReplaceExistingSql] = useState(true);
  const hybrid = useHybridPresentation();
  const [nativePreview, setNativePreview] = useState<NativeWebImportPreview | null>(null);
  const [nativeConfirm, setNativeConfirm] = useState(false);
  const [archiveSha, setArchiveSha] = useState<string | null>(null);
  const [legacyTables, setLegacyTables] = useState<SmartProArchiveInfo["tables"]>([]);
  const [legacyAudit, setLegacyAudit] = useState<SmartProArchiveInfo | null>(null);
  const [savedArchives, setSavedArchives] = useState<Array<{ sourceSha256: string; sizeBytes: number }>>([]);
  const [tablesMeta, setTablesMeta] = useState<UnifiedTableMeta[]>([]);
  const tableOptions = hybrid.isHybrid
    ? legacyTables.map(t => ({ name: t.name, rowsCount: t.rows }))
    : tablesMeta;
  const [summary, setSummary] = useState<ArchiveSummaryPayload | null>(null);
  const [selectedTable, setSelectedTable] = useState("accounts");
  const [tableSearch, setTableSearch] = useState("");
  const [tableOffset, setTableOffset] = useState(0);
  const [tableRows, setTableRows] = useState<Record<string, unknown>[]>([]);
  const [tableCols, setTableCols] = useState<string[]>([]);
  const [tableTotal, setTableTotal] = useState(0);

  const refreshMetadata = useCallback(async () => {
    if (hybrid.isHybrid) return; // Web-only table inspector; Android uses native SQLite.
    try {
      const [meta, sum] = await Promise.all([
        listUnifiedSqliteTables(workspaceId),
        fetchArchiveSummary(workspaceId),
      ]);
      setTablesMeta(meta.tables);
      setSummary(sum);
    } catch (err) {
      setError(err instanceof Error ? err.message : "تعذر قراءة بيانات النظام.");
    }
  }, [workspaceId, hybrid.isHybrid]);

  useEffect(() => {
    if (!open) {
      setError("");
      setNotice("");
      return;
    }
    void refreshMetadata();
  }, [open, refreshMetadata]);

  useEffect(() => {
    if (!open || tab !== "tables" || hybrid.isHybrid) return;
    let active = true;
    void queryUnifiedSqliteTable(workspaceId, selectedTable, tableSearch, 30, tableOffset)
      .then((res) => {
        if (!active) return;
        setTableCols(res.columns);
        setTableRows(res.rows);
        setTableTotal(res.total);
      })
      .catch((err) => {
        if (active) setError(err instanceof Error ? err.message : "تعذر قراءة الجدول.");
      });
    return () => {
      active = false;
    };
  }, [open, tab, workspaceId, selectedTable, tableSearch, tableOffset, hybrid.isHybrid]);

  useEffect(() => {
    if (!open || !hybrid.isHybrid) return;
    let active = true;
    void hybridBridge.invoke<"listLegacyArchives", Array<{ sourceSha256: string; sizeBytes: number }>>(
      "listLegacyArchives", {},
    ).then(rows => { if (active) setSavedArchives(rows); })
      .catch(err => { if (active) setError(err instanceof Error ? err.message : "تعذر عرض قائمة الأرشيفات."); });
    return () => { active = false; };
  }, [open, hybrid.isHybrid]);

  useEffect(() => {
    if (!open || tab !== "tables" || !hybrid.isHybrid || !archiveSha || !selectedTable) return;
    let active = true;
    void hybridBridge.invoke<"queryLegacyArchive", {
      columns: string[]; rows: Record<string, unknown>[]; total: number;
    }>("queryLegacyArchive", {
      sourceSha256: archiveSha, table: selectedTable, offset: tableOffset, limit: 30,
    }).then(result => {
      if (!active) return;
      setTableCols(result.columns);
      setTableRows(result.rows);
      setTableTotal(result.total);
    }).catch(err => {
      if (active) setError(err instanceof Error ? err.message : "تعذر قراءة صفحة الأرشيف.");
    });
    return () => { active = false; };
  }, [open, tab, hybrid.isHybrid, archiveSha, selectedTable, tableOffset]);

  if (!open) return null;

  // Same existing React import modal; Android uses the system file picker
  // and receives only an opaque token + preflight counts, never SQLite bytes.
  const chooseNativeBackup = async () => {
    setError("");
    setNotice("");
    setNativePreview(null);
    setNativeConfirm(false);
    setBusy(true);
    try {
      // The Android system picker and SQLite integrity scan can outlast a
      // single WebMessage reply. Start a native job and poll status only;
      // no file contents ever cross the React bridge.
      const started = await hybridBridge.invoke<"beginBackupInspection", { jobId: string }>(
        "beginBackupInspection",
        { purpose: "restore-backup", accept: [".json", ".sqlite", ".sqlite3", ".db", ".back", ".backup", ".gz"] },
        { timeoutMs: 15000 },
      );
      const stageText: Record<string, string> = {
        picking: "اختر ملف النسخة من ملفات Android…",
        reading: "جارٍ قراءة الملف محليًا دون تغيير قاعدة الهاتف…",
        auditing: "جارٍ فحص جداول SQLite والعلاقات التاريخية…",
        verifying: "جارٍ اختبار الاستعادة في قاعدة معزولة…",
      };
      let lastPhase = "";
      const selected = await awaitBackupInspection(started.jobId, {
        onPhase: (phase) => {
          if (phase !== lastPhase) {
            lastPhase = phase;
            setNotice(
              phase === "waiting"
                ? "فحص SQLite مستمر في Android؛ أُعيد التحقق من المهمة نفسها دون إعادة اختيار الملف…"
                : stageText[phase] || "جارٍ فحص النسخة على الجهاز…",
            );
          }
        },
      });
      if (selected.cancelled) return;
      if (!selected.preview) throw Error("لم تصل معاينة النسخة المختبرة من SQLite.");
      setNativePreview(selected.preview);
      if (selected.preview.historicalArchive) {
        setLegacyAudit(selected.preview.historicalArchive);
        setLegacyTables(selected.preview.historicalArchive.tables);
        setNotice("تم فتح SmartPro v28 للمعاينة التاريخية فقط؛ لم تُرحّل أي قيود مالية.");
      } else {
        setNotice(selected.preview.canRestore
          ? "اكتمل فحص الملف والاستعادة التجريبية المعزولة؛ راجع الأعداد قبل الموافقة."
          : "الملف يحتوي بيانات غير مدعومة أو لم يجتز اختبار الاستعادة؛ لن تُمس بيانات الهاتف.");
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : "تعذر فحص النسخة في Android.");
    } finally {
      setBusy(false);
    }
  };

  const confirmNativeRestore = async () => {
    const preview = nativePreview;
    if (!preview?.canRestore || !nativeConfirm || busy) return;
    setBusy(true);
    setError("");
    setNotice("");
    try {
      const result = await hybridBridge.invoke<"restoreWorkspace", {
        verified?: boolean;
        rollbackBackupId?: string;
        snapshot?: HybridWorkspaceSnapshot;
      }>("restoreWorkspace", {
        workspaceId,
        previewToken: preview.previewToken,
        sourceSha256: preview.sourceSha256,
        confirmation: "REPLACE_AFTER_VERIFIED_PREVIEW",
      }, {
        idempotencyKey: createIdempotencyKey("restoreWorkspace", preview.sourceSha256.slice(0, 12)),
        timeoutMs: 120000,
      });
      if (!result.verified) throw Error("لم تؤكد خدمة SQLite نجاح الاستعادة.");
      if (result.snapshot) applyHybridSnapshot(result.snapshot);
      await refreshWorkspaceFromServer(workspaceId);
      setNativeConfirm(false);
      setNativePreview(null);
      const message = "اكتملت الاستعادة والتحقق من قاعدة SQLite؛ نسخة التراجع: " + (result.rollbackBackupId ?? "محفوظة");
      setNotice(message);
      onNotify(message);
    } catch (err) {
      setError(err instanceof Error ? err.message : "فشلت الاستعادة. لم يُعلن نجاح.");
    } finally {
      setBusy(false);
    }
  };

  const saveHistoricalOnly = async () => {
    const preview = nativePreview;
    if (!preview?.historicalArchive || busy) return;
    setBusy(true);
    setError("");
    try {
      const result = await hybridBridge.invoke<"saveLegacyArchive", {
        saved: boolean; alreadySaved: boolean;
        sourceSha256: string; tables: SmartProArchiveInfo["tables"];
      }>("saveLegacyArchive", {
        previewToken: preview.previewToken,
        sourceSha256: preview.sourceSha256,
      }, { timeoutMs: 120000 });
      if (!result.saved) throw Error("لم يؤكد Dart حفظ الأرشيف الخاص.");
      setArchiveSha(result.sourceSha256);
      setLegacyTables(result.tables);
      setSelectedTable(result.tables.some(t => t.name === "customers")
        ? "customers" : result.tables[0]?.name || "");
      setTableOffset(0);
      setSavedArchives(previous => previous.some(x => x.sourceSha256 === result.sourceSha256)
        ? previous : [...previous, { sourceSha256: result.sourceSha256, sizeBytes: preview.sizeBytes }]);
      setNotice(result.alreadySaved
        ? "الأرشيف موجود مسبقًا بالبصمة نفسها؛ لم تُكرر أي سجلات مالية."
        : "حُفظت نسخة SmartPro الأصلية بلا تعديل في مساحة Android الخاصة، للقراءة فقط.");
      setTab("tables");
    } catch (err) {
      setError(err instanceof Error ? err.message : "تعذر حفظ الأرشيف التاريخي.");
    } finally {
      setBusy(false);
    }
  };

  const viewSavedArchive = async (sha: string) => {
    setBusy(true);
    setError("");
    try {
      const result = await hybridBridge.invoke<"describeLegacyArchive", {
        sourceSha256: string; tables: SmartProArchiveInfo["tables"];
        issues: Record<string, number>; tableCount: number; totalRows: number;
        postingEligible: number; documentTypes: SmartProArchiveInfo["documentTypes"];
        currencyReferences: SmartProArchiveInfo["currencyReferences"];
      }>("describeLegacyArchive", { sourceSha256: sha }, { timeoutMs: 120000 });
      setArchiveSha(sha);
      setLegacyTables(result.tables);
      setLegacyAudit({ ...result, readOnly: true });
      setSelectedTable(result.tables.some(t => t.name === "customers")
        ? "customers" : result.tables[0]?.name || "");
      setTableOffset(0);
      setTab("tables");
      setNotice("أرشيف تاريخي للقراءة فقط. الحسابات التشغيلية وSQLite الأصلية لم تتغير.");
    } catch (err) {
      setError(err instanceof Error ? err.message : "تعذر فتح الأرشيف المحفوظ.");
    } finally {
      setBusy(false);
    }
  };

  const handleFileChange = async (event: ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0];
    event.target.value = "";
    if (!file) return;
    setError("");
    setNotice("");
    setBusy(true);
    try {
      await runWithBrandLoader(`جاري فحص الملف ${file.name}...`, async () => {
        const lower = file.name.toLowerCase();
        if (lower.endsWith(".sql")) {
          const sqlText = await file.text();
          setUpload({ kind: "sql", fileName: file.name, sqlText, byteLength: file.size });
          setNotice(`تم تحميل الملف (${file.name}) — جاهز للاستيراد.`);
        } else {
          const buf = new Uint8Array(await file.arrayBuffer());
          const inspected = await importSqliteBytesIntoServer(workspaceId, buf, file.name, "inspect");
          const tables = Array.isArray(inspected.tables) ? inspected.tables.length : Object.keys(inspected.tableCounts ?? {}).length;
          const totalRows = Number(inspected.totalRows ?? 0);
          const integrity = String(inspected.integrity ?? "ok");
          setUpload({
            kind: "sqlite",
            fileName: file.name,
            bytes: buf,
            sha256: String(inspected.sha256 ?? ""),
            integrity,
            tablesCount: tables,
            totalRows,
            tableCounts: (inspected.tableCounts as Record<string, number>) ?? {},
          });
          setNotice(`تم فحص النسخة الاحتياطية بنجاح: ${tables} قسم و ${totalRows.toLocaleString("en-US")} سجل`);
        }
      });
    } catch (err) {
      setError(err instanceof Error ? err.message : "تعذر فحص الملف المختار.");
    } finally {
      setBusy(false);
    }
  };

  const handleImportUpload = async (replaceAll = false) => {
    if (!upload) return;
    setError("");
    setNotice("");
    setBusy(true);
    try {
      if (upload.kind === "sql") {
        const report = await importSmartProSqlIntoServer(
          workspaceId,
          upload.sqlText,
          upload.fileName,
          replaceAll || replaceExistingSql,
        );
        const imported = (report.imported as Record<string, number>) ?? {};
        const msg = `تم استيراد ${Number(report.totalSourceRows ?? 0).toLocaleString("en-US")} سجلًا من ${upload.fileName} بنجاح (الحسابات: ${imported.accounts ?? 0} • القيود: ${imported.ledgerEntries ?? 0} • البنود: ${imported.invoiceLines ?? 0} • الأصناف: ${imported.inventoryItems ?? 0}).`;
        setNotice(msg);
        onNotify(msg);
      } else {
        const mode = replaceAll ? "restore" : "import";
        const res = await importSqliteBytesIntoServer(
          workspaceId,
          upload.bytes,
          upload.fileName,
          mode,
          undefined,
          replaceAll,
        );
        const inner = (res.result as { added?: Record<string, number> } | undefined) ?? (res as { added?: Record<string, number> });
        const added = inner.added ?? {};
        const msg = replaceAll
          ? `تم استبدال البيانات باستعادة ${upload.fileName} (الحسابات: ${added.accounts ?? 0} • القيود: ${added.ledger ?? 0} • البنود: ${added.invoiceLines ?? 0}).`
          : `تم استيراد ودمج البيانات بنجاح (حسابات مضافة: ${added.accounts ?? 0} • قيود: ${added.ledger ?? 0} • بنود: ${added.invoiceLines ?? 0}).`;
        setNotice(msg);
        onNotify(msg);
      }
      await refreshMetadata();
    } catch (err) {
      setError(err instanceof Error ? err.message : "تعذر إتمام الاستيراد.");
    } finally {
      setBusy(false);
    }
  };

  const handleDownloadJson = async () => {
    setError("");
    setNotice("");
    setBusy(true);
    try {
      const payload = await fetchUnifiedJsonExport(workspaceId);
      const blob = new Blob([JSON.stringify(payload, null, 2)], { type: "application/json;charset=utf-8" });
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = `nasqo-unified-export-${new Date().toISOString().slice(0, 10)}.json`;
      a.click();
      window.setTimeout(() => URL.revokeObjectURL(url), 1000);
      setNotice("تم تصدير النسخة الشاملة بنجاح");
      onNotify("تم تصدير النسخة الشاملة بنجاح");
    } catch (err) {
      setError(err instanceof Error ? err.message : "تعذر تصدير النسخة الشاملة.");
    } finally {
      setBusy(false);
    }
  };

  const handleDownloadSqlite = async () => {
    setError("");
    setNotice("");
    setBusy(true);
    try {
      await downloadUnifiedSqliteFile(workspaceId);
      setNotice(hybrid.isHybrid
        ? "تم إنشاء نسخة محلية محمية والتحقق منها داخل التطبيق."
        : "تم حفظ النسخة الاحتياطية الكاملة بنجاح");
      onNotify(hybrid.isHybrid
        ? "تم إنشاء نسخة محلية محمية والتحقق منها داخل التطبيق."
        : "تم حفظ النسخة الاحتياطية الكاملة بنجاح");
    } catch (err) {
      setError(err instanceof Error ? err.message : "تعذر حفظ النسخة الاحتياطية.");
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="center-modal-layer" dir="rtl" style={{ zIndex: 70 }}>
      <button type="button" className="center-modal-backdrop" aria-label="إغلاق مركز قاعدة البيانات" onClick={onClose} />
      <section
        className="full-sqlite-import-modal"
        role="dialog"
        aria-modal="true"
        style={{
          position: "absolute",
          top: "50%",
          left: "50%",
          transform: "translate(-50%, -50%)",
          zIndex: 71,
          width: "min(calc(100% - 16px), 920px)",
          maxHeight: "min(88%, 760px)",
          display: "flex",
          flexDirection: "column",
          background: "var(--nasqo-surface, #ffffff)",
          color: "var(--nasqo-ink, #0f172a)",
          borderRadius: 20,
          boxShadow: "0 25px 60px rgba(0,0,0,0.35)",
          overflow: "hidden",
        }}
      >
        <header style={{ padding: "14px 20px", borderBottom: "1px solid #e2e8f0", display: "flex", justifyContent: "space-between", alignItems: "center", background: "#f8fafc" }}>
          <div>
            <h2 style={{ margin: 0, fontSize: 17, fontWeight: 700, color: "#0f172a" }}>
              إدارة النسخ الاحتياطية والاستيراد
            </h2>
            <div style={{ fontSize: 11, color: "#475569", marginTop: 2 }}>
              بيانات النظام الموحدة • {summary?.stats.tablesCount ?? 29} قسم بيانات
            </div>
          </div>
          <button type="button" onClick={onClose} style={{ background: "#e2e8f0", border: "none", borderRadius: 8, width: 32, height: 32, cursor: "pointer", fontWeight: 700 }}>
            ✕
          </button>
        </header>

        <div style={{ display: "flex", gap: 6, padding: "8px 16px", background: "#f1f5f9", borderBottom: "1px solid #e2e8f0", flexWrap: "wrap" }}>
          {[
            { id: "overview" as const, label: "الاستيراد والتصدير" },
            { id: "tables" as const, label: `عرض السجلات والجداول (${tableOptions.length})` },
            { id: "audit" as const, label: "سجل المطابقة" },
          ].map((item) => (
            <button
              key={item.id}
              type="button"
              onClick={() => setTab(item.id)}
              style={{
                padding: "6px 12px",
                borderRadius: 8,
                border: "none",
                background: tab === item.id ? "#0284c7" : "#ffffff",
                color: tab === item.id ? "#ffffff" : "#334155",
                fontWeight: 600,
                fontSize: 12,
                cursor: "pointer",
              }}
            >
              {item.label}
            </button>
          ))}
        </div>

        <div style={{ padding: 16, overflowY: "auto", flex: 1 }}>
          {error ? (
            <div style={{ padding: "8px 12px", borderRadius: 8, background: "#fef2f2", color: "#991b1b", fontSize: 13, marginBottom: 10, border: "1px solid #fecaca" }}>
              ⚠️ {error}
            </div>
          ) : null}
          {notice ? (
            <div style={{ padding: "8px 12px", borderRadius: 8, background: "#f0fdf4", color: "#166534", fontSize: 13, marginBottom: 10, border: "1px solid #bbf7d0" }}>
              ✅ {notice}
            </div>
          ) : null}

          {tab === "overview" ? (
            <>
              <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(140px, 1fr))", gap: 8, marginBottom: 12 }}>
                <div style={{ padding: 10, borderRadius: 10, background: "#f8fafc", border: "1px solid #e2e8f0" }}>
                  <div style={{ fontSize: 11, color: "#64748b" }}>إجمالي الحسابات</div>
                  <strong style={{ fontSize: 16 }}>{(summary?.stats.accountsCount ?? liveAccounts.length).toLocaleString("en-US")}</strong>
                </div>
                <div style={{ padding: 10, borderRadius: 10, background: "#f8fafc", border: "1px solid #e2e8f0" }}>
                  <div style={{ fontSize: 11, color: "#64748b" }}>الفواتير والقيود</div>
                  <strong style={{ fontSize: 16 }}>{(summary?.stats.ledgerCount ?? liveLedger.length).toLocaleString("en-US")}</strong>
                </div>
                <div style={{ padding: 10, borderRadius: 10, background: "#f8fafc", border: "1px solid #e2e8f0" }}>
                  <div style={{ fontSize: 11, color: "#64748b" }}>بنود الفواتير</div>
                  <strong style={{ fontSize: 16 }}>{(summary?.stats.invoiceLinesCount ?? 0).toLocaleString("en-US")}</strong>
                </div>
                <div style={{ padding: 10, borderRadius: 10, background: "#f8fafc", border: "1px solid #e2e8f0" }}>
                  <div style={{ fontSize: 11, color: "#64748b" }}>الأصناف والمخازن</div>
                  <strong style={{ fontSize: 16 }}>
                    {(summary?.stats.inventoryCount ?? liveInventory.length).toLocaleString("en-US")} / {summary?.stats.warehousesCount ?? liveWarehouses.length}
                  </strong>
                </div>
              </div>

              <div style={{ border: "2px dashed #cbd5e1", borderRadius: 14, padding: 14, textAlign: "center", background: upload ? "#f0fdf4" : "#f8fafc", marginBottom: 12 }}>
                {hybrid.isHybrid ? (
                  <button
                    type="button"
                    data-testid="native-web-backup-pick"
                    disabled={busy}
                    onClick={() => void chooseNativeBackup()}
                    style={{ display: "inline-block", background: "#0284c7", color: "#fff", padding: "8px 16px", borderRadius: 8, fontSize: 13, fontWeight: 600, cursor: "pointer", border: "none" }}
                  >
                    اختر ملف النسخة الاحتياطية
                  </button>
                ) : (
                  <>
                    <input
                      type="file"
                      id="legacy-center-sqlite-input"
                      accept=".sqlite,.db,.back,.sql"
                      onChange={handleFileChange}
                      style={{ display: "none" }}
                    />
                    <label
                      htmlFor="legacy-center-sqlite-input"
                      style={{ display: "inline-block", background: "#0284c7", color: "#fff", padding: "8px 16px", borderRadius: 8, fontSize: 13, fontWeight: 600, cursor: "pointer" }}
                    >
                      اختر ملف النسخة الاحتياطية
                    </label>
                  </>
                )}
                <div style={{ marginTop: 8, fontSize: 12, color: "#475569" }}>
                  {nativePreview
                    ? nativePreview.fileName + " • " + nativePreview.format + " • " + (nativePreview.sizeBytes / 1048576).toFixed(2) + " MiB"
                    : upload
                    ? upload.kind === "sql"
                      ? `${upload.fileName} • ${(upload.byteLength / (1024 * 1024)).toFixed(2)} MiB`
                      : `${upload.fileName} • ${upload.tablesCount} قسم • ${upload.totalRows.toLocaleString("en-US")} سجل`
                    : "يتم فحص ملف النسخة الاحتياطية واستيراده مباشرة إلى النظام."}
                </div>
                {upload?.kind === "sql" ? (
                  <label style={{ display: "inline-flex", alignItems: "center", gap: 6, marginTop: 8, fontSize: 12 }}>
                    <input type="checkbox" checked={replaceExistingSql} onChange={(e) => setReplaceExistingSql(e.target.checked)} />
                    <span>استبدال البيانات الحالية بالكامل ببيانات الملف</span>
                  </label>
                ) : null}
              </div>

              {nativePreview ? (
                <section data-testid="native-web-backup-preview" style={{ border: "1px solid #cbd5e1", borderRadius: 10, padding: 12, marginBottom: 12 }}>
                  <strong>{nativePreview.historicalArchive
                    ? "معاينة الأرشيف التاريخي — لا توجد قيود مالية مرحّلة"
                    : "معاينة النسخة قبل استبدال بيانات الهاتف"}</strong>
                  <div style={{ fontSize: 12, marginTop: 6 }}>
                    الصيغة: {nativePreview.format} v{String(nativePreview.version)} •
                    سلامة SQLite المعزولة: {nativePreview.trialIntegrity} •
                    السجلات المطابقة: {nativePreview.trialMatchedRecords}
                  </div>
                  <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(125px, 1fr))", gap: 8, marginTop: 10 }}>
                    {([
                      ["accounts", "الحسابات"], ["groups", "المجموعات"], ["currencies", "العملات"],
                      ["invoices", "الفواتير"], ["vouchers", "السندات"], ["movements", "القيود"],
                      ["warehouses", "المخازن"], ["items", "الأصناف"], ["invoiceLines", "بنود الفواتير"],
                    ] as const).map(([key, label]) => (
                      <div key={key} style={{ padding: 7, background: "#f8fafc", borderRadius: 8 }}>
                        <div style={{ fontSize: 11 }}>{label}</div>
                        <strong>{nativePreview.counts[key].toLocaleString("en-US")}</strong>
                      </div>
                    ))}
                  </div>
                  {nativePreview.historicalArchive ? (
                    <div data-testid="smartpro-v28-historical-preview" style={{ marginTop: 12 }}>
                      <p><strong>SmartPro v28</strong> • {nativePreview.historicalArchive.tableCount} جدول
                        • {nativePreview.historicalArchive.totalRows.toLocaleString("en-US")} سجل في الأرشيف الأصلي</p>
                      <p style={{ fontSize: 12, overflowWrap: "anywhere" }}>
                        SHA-256: <bdi>{nativePreview.sourceSha256}</bdi>
                      </p>
                      <p style={{ color: "#991b1b", fontSize: 12 }}>
                        الحركات والعملات والمخازن والأرصدة ذات المعنى غير المثبت تبقى تاريخية؛
                        الترحيل المالي الآلي موقوف حتى المطابقة.
                      </p>
                      <button type="button" data-testid="smartpro-save-archive" disabled={busy}
                        onClick={() => void saveHistoricalOnly()}
                        style={{ padding: 10, background: "#0f766e", color: "#fff", border: 0, borderRadius: 8 }}>
                        حفظ الأرشيف الأصلي للقراءة فقط
                      </button>
                    </div>
                  ) : null}
                  {nativePreview.unsupported.length ? (
                    <p data-testid="native-unsupported-records" style={{ color: "#991b1b", fontSize: 12 }}>
                      سجلات غير مدعومة (محظورة من الاستيراد):
                      {nativePreview.unsupported.map(x => " " + x.section + ": " + x.count).join(" •")}
                    </p>
                  ) : null}
                  {nativePreview.trialError ? <p style={{ color: "#991b1b", fontSize: 12 }}>{nativePreview.trialError}</p> : null}
                  {nativePreview.canRestore ? (
                    <>
                      {!nativeConfirm ? (
                        <button type="button" data-testid="native-web-backup-review-consent" disabled={busy}
                          onClick={() => setNativeConfirm(true)}
                          style={{ marginTop: 10, padding: 10, borderRadius: 8, color: "#fff", background: "#b45309", border: 0 }}>
                          مراجعة استبدال البيانات بعد إنشاء نسخة تراجع
                        </button>
                      ) : (
                        <div style={{ marginTop: 10 }}>
                          <p style={{ fontSize: 12, color: "#991b1b" }}>ستُستبدل بيانات SQLite الحالية بالملف الذي اجتاز الاختبار. ستُحفظ نسخة تراجع محلية أولًا. هل تؤكد؟</p>
                          <button type="button" data-testid="native-web-backup-confirm" disabled={busy}
                            onClick={() => void confirmNativeRestore()}
                            style={{ padding: 10, background: "#b45309", color: "#fff", border: 0, borderRadius: 8 }}>
                            أوافق على الاستبدال بعد الحفظ والتحقق
                          </button>
                          <button type="button" disabled={busy} onClick={() => setNativeConfirm(false)}
                            style={{ marginRight: 10, padding: 10 }}>إلغاء</button>
                        </div>
                      )}
                    </>
                  ) : <p>{nativePreview.historicalArchive
                    ? "يمكن حفظ واستعراض كل الجداول؛ لا ترحيل مالي قبل استكمال المطابقة."
                    : "الاستعادة غير مسموحة لهذا الملف قبل تصحيح المشاكل المذكورة."}</p>}
                </section>
              ) : null}

              {hybrid.isHybrid && savedArchives.length > 0 ? (
                <div style={{ padding: 10, border: "1px solid #e2e8f0", borderRadius: 10, marginBottom: 10 }}>
                  <strong>الأرشيفات التاريخية المحفوظة</strong>
                  {savedArchives.map(a => (
                    <button key={a.sourceSha256} type="button" disabled={busy}
                      onClick={() => void viewSavedArchive(a.sourceSha256)}
                      style={{ display: "block", padding: 8, marginTop: 5 }}>
                      فتح أرشيف <bdi>{a.sourceSha256.slice(0, 18)}…</bdi> • {(a.sizeBytes / 1048576).toFixed(2)} MiB
                    </button>
                  ))}
                </div>
              ) : null}
              <div style={{ display: "flex", flexWrap: "wrap", gap: 8 }}>
                {!hybrid.isHybrid && upload ? (
                  <>
                    <button
                      type="button"
                      data-testid="legacy-import-and-show"
                      disabled={busy}
                      onClick={() => void handleImportUpload(false)}
                      style={{ background: "#0f766e", color: "#fff", border: "none", padding: "8px 16px", borderRadius: 8, fontSize: 13, fontWeight: 700, cursor: "pointer" }}
                    >
                      {upload.kind === "sqlite"
                        ? "استيراد ودمج فوق الحالي (بدون مسح)"
                        : "استيراد وحفظ البيانات"}
                    </button>
                    {upload.kind === "sqlite" ? (
                      <button
                        type="button"
                        data-testid="legacy-sqlite-restore-replace"
                        disabled={busy}
                        onClick={() => void handleImportUpload(true)}
                        style={{ background: "#b45309", color: "#fff", border: "none", padding: "8px 14px", borderRadius: 8, fontSize: 12, fontWeight: 700, cursor: "pointer" }}
                      >
                        استبدال كامل ومسح الحالي (استعادة)
                      </button>
                    ) : null}
                  </>
                ) : null}
                <button
                  type="button"
                  disabled={busy}
                  onClick={() => void handleDownloadSqlite()}
                  style={{ background: "#059669", color: "#fff", border: "none", padding: "8px 14px", borderRadius: 8, fontSize: 12, fontWeight: 600, cursor: "pointer" }}
                >
                  حفظ نسخة احتياطية كاملة
                </button>
                <button
                  type="button"
                  data-testid="legacy-export-json-btn"
                  disabled={busy}
                  onClick={() => void handleDownloadJson()}
                  style={{ background: "#334155", color: "#fff", border: "none", padding: "8px 14px", borderRadius: 8, fontSize: 12, fontWeight: 600, cursor: "pointer" }}
                >
                  تصدير نسخة شاملة
                </button>
              </div>
            </>
          ) : null}

          {tab === "tables" ? (
            <>
              <div style={{ display: "flex", gap: 8, marginBottom: 10, flexWrap: "wrap" }}>
                <select
                  value={selectedTable}
                  onChange={(e) => {
                    setSelectedTable(e.target.value);
                    setTableOffset(0);
                  }}
                  style={{ padding: "8px 10px", borderRadius: 8, border: "1px solid #cbd5e1", fontSize: 12, background: "#fff" }}
                >
                  {tableOptions.map((t) => (
                    <option key={t.name} value={t.name}>
                      {t.name} ({t.rowsCount.toLocaleString("en-US")})
                    </option>
                  ))}
                </select>
                {!hybrid.isHybrid ? (
                <input
                  type="search"
                  value={tableSearch}
                  onChange={(e) => {
                    setTableSearch(e.target.value);
                    setTableOffset(0);
                  }}
                  placeholder="بحث داخل الجدول..."
                  style={{ flex: 1, minWidth: 180, padding: "8px 10px", borderRadius: 8, border: "1px solid #cbd5e1", fontSize: 12 }}
                />
                ) : (
                  <span style={{ fontSize: 12 }}>صفحات أرشيف تاريخي غير مرحّل محاسبيًا</span>
                )}
              </div>

              <div style={{ overflowX: "auto", border: "1px solid #e2e8f0", borderRadius: 10 }}>
                <table style={{ width: "100%", borderCollapse: "collapse", fontSize: 11, textAlign: "right" }}>
                  <thead>
                    <tr style={{ background: "#f8fafc", borderBottom: "1px solid #cbd5e1" }}>
                      {tableCols.map((c) => (
                        <th key={c} style={{ padding: "6px 8px", whiteSpace: "nowrap" }}>{c}</th>
                      ))}
                    </tr>
                  </thead>
                  <tbody>
                    {tableRows.map((row, idx) => (
                      <tr key={idx} style={{ borderBottom: "1px solid #f1f5f9" }}>
                        {tableCols.map((c) => (
                          <td key={c} style={{ padding: "6px 8px", maxWidth: 180, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>
                            {row[c] === null || row[c] === undefined
  ? "—"
  : typeof row[c] === "object" ? JSON.stringify(row[c]) : String(row[c])}
                          </td>
                        ))}
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>

              <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginTop: 10, fontSize: 12 }}>
                <button type="button" disabled={tableOffset === 0} onClick={() => setTableOffset((o) => Math.max(0, o - 30))}>
                  السابق
                </button>
                <span>إجمالي السجلات: {tableTotal.toLocaleString("en-US")}</span>
                <button type="button" disabled={tableOffset + tableRows.length >= tableTotal} onClick={() => setTableOffset((o) => o + 30)}>
                  التالي
                </button>
              </div>
            </>
          ) : null}

          {tab === "audit" ? (
            <div style={{ display: "grid", gap: 10 }} data-testid="sqlite-audit-report">
              <div
                style={{
                  display: "grid",
                  gridTemplateColumns: "repeat(auto-fit, minmax(150px, 1fr))",
                  gap: 8,
                  padding: 10,
                  borderRadius: 10,
                  background: "#f8fafc",
                  border: "1px solid #cbd5e1",
                  fontSize: 12,
                }}
              >
                <div>
                  <div style={{ color: "#64748b" }}>الحسابات والصناديق</div>
                  <strong>
                    {liveAccounts.length} حساب ({liveAccounts.filter((a) => a.groupId != null).length} مصنّف)
                  </strong>
                </div>
                <div>
                  <div style={{ color: "#64748b" }}>الأصناف والمخازن</div>
                  <strong>
                    {liveWarehouses.length} مخزن • {liveInventory.length} صنف
                  </strong>
                  <div style={{ color: "#b45309", fontSize: 11 }}>
                    بحاجة جرد: {liveInventory.filter((i) => i.quantityUnverified).length}
                  </div>
                </div>
                <div>
                  <div style={{ color: "#64748b" }}>القيود والفواتير</div>
                  <strong>{liveLedger.length.toLocaleString("en-US")} سجل</strong>
                  <div style={{ color: "#0369a1", fontSize: 11 }}>
                    بنود الأصناف: {(summary?.stats.invoiceLinesCount ?? 0).toLocaleString("en-US")}
                  </div>
                </div>
                <div>
                  <div style={{ color: "#64748b" }}>التحويلات والأرشيف</div>
                  <strong>
                    {summary?.transfers?.length ?? 0} تحويل • {summary?.archivedDocs?.length ?? 0} أرشيف
                  </strong>
                </div>
              </div>
              {(summary?.stats.imports ?? []).map((imp) => (
                <div key={imp.id} style={{ padding: 12, borderRadius: 10, background: "#f8fafc", border: "1px solid #e2e8f0", fontSize: 12 }}>
                  <div><strong>{imp.sourceName}</strong> ({imp.sourceFormat})</div>
                  <div style={{ color: "#475569", marginTop: 4 }}>
                    الجداول: {imp.tablesCount} • إجمالي السجلات المصدرية: {imp.totalRows.toLocaleString("en-US")} • البصمة: <bdi>{imp.sourceSha256.slice(0, 16)}…</bdi>
                  </div>
                </div>
              ))}
              {hybrid.isHybrid && legacyAudit ? (
                <section data-testid="smartpro-archive-audit" style={{ padding: 12, border: "1px solid #e2e8f0", borderRadius: 10 }}>
                  <strong>مطابقة SmartPro v28 — قراءة تاريخية فقط</strong>
                  <p>الجداول: {legacyAudit.tableCount} • السجلات: {legacyAudit.totalRows} • القيود المرحلة: 0</p>
                  {Object.entries(legacyAudit.issues)
                    .filter(([, count]) => count > 0)
                    .map(([name, count]) => <div key={name}>{name}: {count.toLocaleString("en-US")}</div>)}
                  <p>أنواع مستندات تحتاج إلى مطابقة:</p>
                  {legacyAudit.documentTypes.map(t => <span key={t.id} style={{ margin: 4, display: "inline-block" }}>
                    نوع {t.id}: {t.count.toLocaleString("en-US")}
                  </span>)}
                </section>
              ) : null}
              {(summary?.stats.imports ?? []).length === 0 && !hybrid.isHybrid ? (
                <p style={{ color: "#64748b", fontSize: 13 }}>لم تُستورد ملفات مصادر بعد في سجل التدقيق.</p>
              ) : null}
            </div>
          ) : null}
        </div>
      </section>
    </div>
  );
}
