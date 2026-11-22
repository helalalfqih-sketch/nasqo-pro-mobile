import { useCallback, useEffect, useState, type ChangeEvent, type MouseEvent } from "react";
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
import { pickNativeWebsiteBackup, restoreNativeWebsiteBackup, type NativeWebsiteBackupPreview } from "../hybrid/serviceAdapter";

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
      kind: "native";
      fileName: string;
      previewToken: string;
      restorable: boolean;
      counts: Record<string, number>;
      unsupportedRecords: Record<string, number>;
      reason?: string;
    }
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

  const [tablesMeta, setTablesMeta] = useState<UnifiedTableMeta[]>([]);
  const [summary, setSummary] = useState<ArchiveSummaryPayload | null>(null);
  const [selectedTable, setSelectedTable] = useState("accounts");
  const [tableSearch, setTableSearch] = useState("");
  const [tableOffset, setTableOffset] = useState(0);
  const [tableRows, setTableRows] = useState<Record<string, unknown>[]>([]);
  const [tableCols, setTableCols] = useState<string[]>([]);
  const [tableTotal, setTableTotal] = useState(0);

  const refreshMetadata = useCallback(async () => {
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
  }, [workspaceId]);

  useEffect(() => {
    if (!open) {
      setError("");
      setNotice("");
      return;
    }
    void refreshMetadata();
  }, [open, refreshMetadata]);

  useEffect(() => {
    if (!open || tab !== "tables") return;
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
  }, [open, tab, workspaceId, selectedTable, tableSearch, tableOffset]);

  if (!open) return null;

  // Retain the original React import screen; Android selects and reads the
  // bytes in Dart, then returns only preview counts and a one-time token.
  const handleNativeFileChoice = async (event: MouseEvent<HTMLLabelElement>) => {
    event.preventDefault();
    if (busy) return;
    setError("");
    setNotice("");
    setBusy(true);
    try {
      const preview: NativeWebsiteBackupPreview =
        await runWithBrandLoader("جارٍ فحص نسخة الويب المحلية...", () =>
          pickNativeWebsiteBackup(workspaceId));
      if (preview.cancelled) return;
      const counts = preview.counts ?? {};
      const unsupportedRecords = preview.unsupportedRecords ?? {};
      setUpload({
        kind: "native",
        fileName: preview.fileName ?? "نسخة الويب",
        previewToken: preview.previewToken ?? "",
        restorable: preview.restorable === true,
        counts, unsupportedRecords,
        reason: preview.reason,
      });
      const detail = [
        "الحسابات: " + (counts.accounts ?? 0),
        "المجموعات: " + (counts.groups ?? 0),
        "العملات: " + (counts.currencies ?? 0),
        "الفواتير: " + (counts.invoices ?? 0),
        "السندات: " + (counts.vouchers ?? 0),
        "المخازن: " + (counts.warehouses ?? 0),
        "الأصناف: " + (counts.items ?? 0),
      ].join(" • ");
      const unsupported = Object.entries(unsupportedRecords)
        .map(([name, number]) => name + ": " + number).join(" • ");
      setNotice("معاينة ملف " + (preview.fileName ?? "") + ": " + detail
        + (unsupported ? " • غير مدعوم: " + unsupported : ""));
      if (!preview.restorable) {
        setError(preview.reason ?? "فشلت مطابقة النسخة؛ الاستعادة محظورة.");
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : "تعذّر اختيار الملف.");
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
      if (upload.kind === "native") {
        if (!replaceAll || !upload.restorable) {
          throw new Error(upload.reason ?? "هذه النسخة لا تدعم الدمج؛ يلزم استعادة مؤكدة.");
        }
        const result = await restoreNativeWebsiteBackup(workspaceId, upload.previewToken);
        if (result.cancelled) {
          setNotice("أُلغيت الاستعادة؛ لم تتغير بيانات الهاتف.");
          return;
        }
        if (!result.restored) throw new Error("لم يكتمل تحقق SQLite.");
        setUpload(null);
        setNotice("اكتملت استعادة بيانات الويب والتحقق من SQLite.");
        onNotify("اكتملت استعادة بيانات الويب والتحقق من SQLite.");
        await refreshMetadata();
        return;
      }
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
      setNotice("تم حفظ النسخة الاحتياطية الكاملة بنجاح");
      onNotify("تم حفظ النسخة الاحتياطية الكاملة بنجاح");
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
            { id: "tables" as const, label: `عرض السجلات والجداول (${tablesMeta.length})` },
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
                <input
                  type="file"
                  id="legacy-center-sqlite-input"
                  accept=".sqlite,.db,.sqlite3,.back,.json,.gz,.sql"
                  onChange={handleFileChange}
                  style={{ display: "none" }}
                />
                <label
                  htmlFor="legacy-center-sqlite-input"
                  onClick={(event) => void handleNativeFileChoice(event)}
                  style={{ display: "inline-block", background: "#0284c7", color: "#fff", padding: "8px 16px", borderRadius: 8, fontSize: 13, fontWeight: 600, cursor: "pointer" }}
                >
                  اختر ملف النسخة الاحتياطية
                </label>
                <div style={{ marginTop: 8, fontSize: 12, color: "#475569" }}>
                  {upload
                    ? upload.kind === "sql"
                      ? `${upload.fileName} • ${(upload.byteLength / (1024 * 1024)).toFixed(2)} MiB`
                      : upload.kind === "native"
                        ? `${upload.fileName} • ${Object.values(upload.counts).reduce((a,b)=>a+b,0)} سجل • معاينة SQLite محلية`
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

              <div style={{ display: "flex", flexWrap: "wrap", gap: 8 }}>
                {upload ? (
                  <>
                    {upload.kind !== "native" ? <button
                      type="button"
                      data-testid="legacy-import-and-show"
                      disabled={busy}
                      onClick={() => void handleImportUpload(false)}
                      style={{ background: "#0f766e", color: "#fff", border: "none", padding: "8px 16px", borderRadius: 8, fontSize: 13, fontWeight: 700, cursor: "pointer" }}
                    >
                      {upload.kind === "sqlite"
                        ? "استيراد ودمج فوق الحالي (بدون مسح)"
                        : "استيراد وحفظ البيانات"}
                    </button> : null}
                    {upload.kind === "sqlite" || upload.kind === "native" ? (
                      <button
                        type="button"
                        data-testid="legacy-sqlite-restore-replace"
                        disabled={busy || (upload.kind === "native" && !upload.restorable)}
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
                  {tablesMeta.map((t) => (
                    <option key={t.name} value={t.name}>
                      {t.name} ({t.rowsCount.toLocaleString("en-US")})
                    </option>
                  ))}
                </select>
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
                            {row[c] === null || row[c] === undefined ? "—" : String(row[c])}
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
              {(summary?.stats.imports ?? []).length === 0 ? (
                <p style={{ color: "#64748b", fontSize: 13 }}>لم تُستورد ملفات مصادر بعد في سجل التدقيق.</p>
              ) : null}
            </div>
          ) : null}
        </div>
      </section>
    </div>
  );
}
