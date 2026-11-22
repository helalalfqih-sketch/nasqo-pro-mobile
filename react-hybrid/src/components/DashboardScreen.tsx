import { useMemo, useState } from "react";
import {
  ActivityLogIcon,
  ArrowLeftIcon,
  BackpackIcon,
  CheckCircledIcon,
  ExclamationTriangleIcon,
  FileTextIcon,
  Pencil1Icon,
  PlusIcon,
} from "@radix-ui/react-icons";
import { MobileScroll } from "../mobile";
import {
  computeDashboardSummary,
  computeSalesTrend7Days,
  computeSupplierPerformance,
  formatAmount,
  parseArabicNumber,
  type LowStockAlertItem,
} from "../accounting";
import { triggerHaptic } from "../utils/haptics";
import type {
  AccountRecord,
  CurrencyCode,
  InventoryItemRecord,
  LedgerEntryRecord,
  WarehouseRecord,
} from "../types";
import { ExpenseTrendsChart } from "./ExpenseTrendsChart";
import { PdfReportButton } from "./PdfReportButton";
import { SalesTrendChart } from "./SalesTrendChart";
import { SupplierPerformanceChart } from "./SupplierPerformanceChart";

export type DashboardPeriod = "all" | "month" | "week";

export interface DashboardProps {
  companyName: string;
  defaultCurrency: CurrencyCode;
  accounts: readonly AccountRecord[];
  ledger: readonly LedgerEntryRecord[];
  warehouses: readonly WarehouseRecord[];
  inventory: readonly InventoryItemRecord[];
  loading?: boolean;
  onOpenSales: () => void;
  onOpenSupplier: (accountId: string) => void;
  onPreviewInvoice: (entryId: string) => void;
  onAddInventoryItem: () => void;
  onUpdateItemThreshold: (item: InventoryItemRecord, newThreshold: number) => Promise<void>;
  onOpenInventoryReport: () => void;
  onOpenDailyJournal: () => void;
  onNotify: (message: string) => void;
}

const PERIOD_OPTIONS: readonly { id: DashboardPeriod; label: string }[] = [
  { id: "all", label: "الكل" },
  { id: "month", label: "30 يوم" },
  { id: "week", label: "7 أيام" },
];

const THRESHOLD_MODE_OPTIONS = [
  { id: "item", label: "حد كل صنف", value: 25, useItem: true },
  { id: "15", label: "≤ 15", value: 15, useItem: false },
  { id: "25", label: "≤ 25", value: 25, useItem: false },
  { id: "50", label: "≤ 50", value: 50, useItem: false },
] as const;

export function Dashboard({
  companyName,
  defaultCurrency,
  accounts,
  ledger,
  warehouses,
  inventory,
  loading = false,
  onOpenSales,
  onOpenSupplier,
  onPreviewInvoice,
  onAddInventoryItem,
  onUpdateItemThreshold,
  onOpenInventoryReport,
  onOpenDailyJournal,
  onNotify,
}: DashboardProps) {
  const [period, setPeriod] = useState<DashboardPeriod>("all");
  const [thresholdMode, setThresholdMode] = useState<"item" | "15" | "25" | "50">("item");
  const [editingThresholdItemId, setEditingThresholdItemId] = useState<string | null>(null);
  const [thresholdDraft, setThresholdDraft] = useState("");
  const [savingThreshold, setSavingThreshold] = useState(false);
  const [visibleLowStockLimit, setVisibleLowStockLimit] = useState(40);

  const selectedThresholdConfig =
    THRESHOLD_MODE_OPTIONS.find((opt) => opt.id === thresholdMode) ?? THRESHOLD_MODE_OPTIONS[0];

  const summary = useMemo(
    () =>
      computeDashboardSummary(accounts, ledger, warehouses, inventory, {
        period,
        lowStockThreshold: selectedThresholdConfig.value,
        useItemThresholds: selectedThresholdConfig.useItem,
        recentInvoicesLimit: 6,
      }),
    [accounts, inventory, ledger, period, selectedThresholdConfig, warehouses],
  );

  const salesTrend = useMemo(
    () => computeSalesTrend7Days(accounts, ledger),
    [accounts, ledger],
  );

  const supplierPerf = useMemo(
    () => computeSupplierPerformance(accounts, ledger),
    [accounts, ledger],
  );

  const criticalCount = useMemo(
    () => summary.lowStockItems.filter((item) => item.severity === "critical").length,
    [summary.lowStockItems],
  );

  const periodSubtitle =
    period === "all"
      ? "جميع الفترات المسجلة"
      : period === "month"
        ? "خلال آخر 30 يومًا"
        : "خلال آخر 7 أيام";

  const handleStartEditThreshold = (item: LowStockAlertItem) => {
    triggerHaptic("light");
    setEditingThresholdItemId(item.id);
    setThresholdDraft(String(item.effectiveThreshold));
  };

  const handleSaveThreshold = async (item: LowStockAlertItem) => {
    const nextThreshold = Math.max(0, parseArabicNumber(thresholdDraft));
    setSavingThreshold(true);
    try {
      await onUpdateItemThreshold(item, nextThreshold);
      setEditingThresholdItemId(null);
      triggerHaptic("success");
      onNotify(`تم تحديث الحد الأدنى لصنف "${item.name}" إلى ${formatAmount(nextThreshold)}`);
    } finally {
      setSavingThreshold(false);
    }
  };

  return (
    <MobileScroll className="app-screen exec-dashboard-scroll">
      <main className="exec-dashboard-page" data-testid="analytics-dashboard-screen">
        <header className="exec-toolbar">
          <div className="exec-toolbar-copy">
            <h1>{companyName || "نسقو برو"}</h1>
            <p>ملخص المبيعات والفواتير والمخزون · {periodSubtitle}</p>
          </div>
          <div className="exec-toolbar-controls">
            <div className="exec-segmented" role="group" aria-label="تصفية الفترة الزمنية">
              {PERIOD_OPTIONS.map((option) => (
                <button
                  key={option.id}
                  type="button"
                  className={period === option.id ? "active" : ""}
                  aria-pressed={period === option.id}
                  onClick={() => {
                    triggerHaptic("light");
                    setPeriod(option.id);
                  }}
                >
                  {option.label}
                </button>
              ))}
            </div>

            <PdfReportButton
              companyName={companyName}
              defaultCurrency={defaultCurrency}
              periodLabel={periodSubtitle}
              summary={summary}
              onNotify={onNotify}
            />
          </div>
        </header>

        <div className="exec-widgets-stack" data-testid="dashboard-widgets-stack">
          <section className="exec-kpi-grid" aria-label="ملخص المؤشرات الرئيسية">
            <button
              type="button"
              className="exec-kpi-card"
              onClick={() => {
                triggerHaptic("light");
                onOpenSales();
              }}
              data-testid="kpi-total-sales"
            >
              <div className="exec-kpi-top">
                <span className="exec-kpi-label">إجمالي المبيعات</span>
                <span className="exec-kpi-icon sales" aria-hidden="true">
                  <ActivityLogIcon />
                </span>
              </div>
              <strong className="exec-kpi-value">
                {loading ? "..." : `${formatAmount(summary.totalSales)} ${defaultCurrency}`}
              </strong>
              <span className="exec-kpi-meta">
                {summary.salesInvoiceCount} فاتورة مبيعات · {summary.salesAccountCount} حساب مبيعات
              </span>
            </button>

            <button
              type="button"
              className="exec-kpi-card"
              onClick={() => {
                triggerHaptic("light");
                onOpenDailyJournal();
              }}
              data-testid="kpi-recent-invoices"
            >
              <div className="exec-kpi-top">
                <span className="exec-kpi-label">الفواتير المسجلة</span>
                <span className="exec-kpi-icon invoices" aria-hidden="true">
                  <FileTextIcon />
                </span>
              </div>
              <strong className="exec-kpi-value">
                {loading ? "..." : `${summary.totalInvoicesCount} فاتورة`}
              </strong>
              <span className="exec-kpi-meta">
                إجمالي القيمة: {formatAmount(summary.totalInvoicesVolume)} {defaultCurrency}
              </span>
            </button>

            <button
              type="button"
              className="exec-kpi-card"
              onClick={() => {
                triggerHaptic("light");
                onOpenInventoryReport();
              }}
              data-testid="kpi-low-stock"
            >
              <div className="exec-kpi-top">
                <span className="exec-kpi-label">تنبيهات المخزون</span>
                <span
                  className={`exec-kpi-icon ${summary.lowStockItems.length > 0 ? "alerts" : "healthy"}`}
                  aria-hidden="true"
                >
                  {summary.lowStockItems.length > 0 ? <ExclamationTriangleIcon /> : <CheckCircledIcon />}
                </span>
              </div>
              <strong
                className={`exec-kpi-value ${
                  criticalCount > 0 ? "critical" : summary.lowStockItems.length > 0 ? "warning" : "healthy"
                }`}
              >
                {loading ? "..." : `${summary.lowStockItems.length} أصناف`}
              </strong>
              <span className="exec-kpi-meta">
                من أصل {summary.totalInventoryItems} صنف ·{" "}
                {criticalCount > 0
                  ? `${criticalCount} نفاد وشيك`
                  : summary.lowStockItems.length > 0
                    ? "دون الحد الأدنى المحدد"
                    : "المخزون ضمن الحد الآمن"}
              </span>
            </button>
          </section>

          <SalesTrendChart points={salesTrend} currency={defaultCurrency} loading={loading} />

          <SupplierPerformanceChart
            suppliers={supplierPerf}
            currency={defaultCurrency}
            loading={loading}
            onSelectSupplier={onOpenSupplier}
          />

          <ExpenseTrendsChart
            accounts={accounts}
            ledger={ledger}
            currency={defaultCurrency}
            loading={loading}
            onNotify={onNotify}
          />

          <section className="exec-panel" aria-labelledby="recent-invoices-heading">
            <div className="exec-panel-head">
              <div>
                <h2 id="recent-invoices-heading">أحدث الفواتير</h2>
                <p>عرض آخر {summary.recentInvoices.length} مستندات فواتير ومردودات</p>
              </div>
              <div className="exec-panel-actions">
                <button type="button" className="exec-action-link" onClick={onOpenDailyJournal}>
                  <span>الكل</span>
                  <ArrowLeftIcon />
                </button>
              </div>
            </div>

            {loading ? (
              <div className="exec-empty">جاري تحميل الفواتير...</div>
            ) : summary.recentInvoices.length === 0 ? (
              <div className="exec-empty">
                <p>لا توجد فواتير مسجلة ضمن الفترة المحددة.</p>
              </div>
            ) : (
              <ul className="exec-list" data-testid="recent-invoices-list">
                {summary.recentInvoices.map((entry) => {
                  const paymentLabel =
                    entry.payment === "cash" ? "نقدي" : entry.payment === "credit" ? "آجل" : "رصيد";
                  return (
                    <li key={entry.id}>
                      <button
                        type="button"
                        className="exec-row"
                        onClick={() => {
                          triggerHaptic("light");
                          onPreviewInvoice(entry.id);
                        }}
                      >
                        <div className="exec-row-main">
                          <strong>{entry.accountName}</strong>
                          <span className="exec-row-meta">
                            #{entry.entryNumber} · {entry.typeLabel} · {paymentLabel} · {entry.entryDate}
                            {entry.expenseCategory ? ` · ${entry.expenseCategory}` : ""}
                          </span>
                          {entry.details ? (
                            <span className="exec-row-detail">{entry.details.split("\n")[0]}</span>
                          ) : null}
                        </div>
                        <div className="exec-row-side">
                          <strong className={`exec-amount ${entry.kind === "return" ? "debit" : ""}`}>
                            {formatAmount(entry.amount)} {entry.currency}
                          </strong>
                          <span className="exec-row-link">
                            معاينة <ArrowLeftIcon />
                          </span>
                        </div>
                      </button>
                    </li>
                  );
                })}
              </ul>
            )}
          </section>

          <section className="exec-panel" aria-labelledby="low-stock-heading">
            <div className="exec-panel-head">
              <div>
                <h2 id="low-stock-heading">الأصناف دون الحد الأدنى</h2>
                <p>
                  {selectedThresholdConfig.useItem
                    ? "الأصناف التي انخفضت كميتها عن الحد الأدنى المحدد لكل صنف"
                    : `الأصناف الأقل من ${selectedThresholdConfig.value} وحدة`}
                </p>
              </div>
              <div className="exec-panel-actions">
                <div className="exec-threshold-group" role="group" aria-label="حد تنبيه المخزون">
                  {THRESHOLD_MODE_OPTIONS.map((opt) => (
                    <button
                      key={opt.id}
                      type="button"
                      className={thresholdMode === opt.id ? "active" : ""}
                      aria-pressed={thresholdMode === opt.id}
                      onClick={() => {
                        triggerHaptic("light");
                        setThresholdMode(opt.id);
                      }}
                    >
                      {opt.label}
                    </button>
                  ))}
                </div>
                <button
                  type="button"
                  className="exec-action-secondary"
                  onClick={() => {
                    triggerHaptic("light");
                    onAddInventoryItem();
                  }}
                  aria-label="إضافة صنف للمخزن"
                >
                  <PlusIcon />
                  <span>صنف</span>
                </button>
              </div>
            </div>

            {loading ? (
              <div className="exec-empty">جاري فحص أرصدة المخازن...</div>
            ) : summary.lowStockItems.length === 0 ? (
              <div className="exec-empty">
                <p>جميع الأصناف المسجلة تفي بالحد الأدنى المطلوب.</p>
              </div>
            ) : (
              <ul className="exec-list" data-testid="low-stock-list">
                {summary.lowStockItems.slice(0, visibleLowStockLimit).map((item) => {
                  const isEditing = editingThresholdItemId === item.id;
                  return (
                    <li key={item.id} className="exec-stock-li">
                      <div className="exec-stock-row">
                        <button
                          type="button"
                          className="exec-stock-main-btn"
                          onClick={onOpenInventoryReport}
                        >
                          <div className="exec-row-main">
                            <strong>{item.name}</strong>
                            <span className="exec-row-meta">
                              {item.warehouseName}
                              {item.sku ? ` · ${item.sku}` : ""} · الحد الأدنى:{" "}
                              {formatAmount(item.effectiveThreshold)} {item.unit} · نقص{" "}
                              {formatAmount(item.shortage)}
                            </span>
                          </div>
                          <div className="exec-row-side">
                            <strong className="exec-qty">
                              {formatAmount(item.quantity)} / {formatAmount(item.effectiveThreshold)}{" "}
                              {item.unit}
                            </strong>
                            <span className={`exec-severity ${item.severity}`}>
                              {item.severity === "critical" ? "نفاد وشيك" : "دون الحد الأدنى"}
                            </span>
                          </div>
                        </button>
                        <button
                          type="button"
                          className="exec-threshold-edit-btn"
                          aria-label={`تعديل الحد الأدنى لصنف ${item.name}`}
                          onClick={() =>
                            isEditing ? setEditingThresholdItemId(null) : handleStartEditThreshold(item)
                          }
                        >
                          <Pencil1Icon />
                        </button>
                      </div>

                      {isEditing ? (
                        <div className="exec-threshold-inline">
                          <label>
                            <span>الحد الأدنى:</span>
                            <input
                              type="number"
                              min={0}
                              value={thresholdDraft}
                              aria-label={`الحد الأدنى الجديد لصنف ${item.name}`}
                              onChange={(e) => setThresholdDraft(e.target.value)}
                            />
                          </label>
                          <button
                            type="button"
                            className="exec-action-primary"
                            disabled={savingThreshold}
                            onClick={() => handleSaveThreshold(item)}
                          >
                            {savingThreshold ? "حفظ..." : "حفظ الحد"}
                          </button>
                          <button
                            type="button"
                            className="exec-action-link"
                            onClick={() => setEditingThresholdItemId(null)}
                          >
                            إلغاء
                          </button>
                        </div>
                      ) : null}
                    </li>
                  );
                })}
                {summary.lowStockItems.length > visibleLowStockLimit ? (
                  <li style={{ listStyle: "none", textAlign: "center", padding: "8px 0" }}>
                    <button
                      type="button"
                      className="load-more-list-btn"
                      onClick={() => setVisibleLowStockLimit((v) => v + 60)}
                    >
                      عرض المزيد (المعروض {visibleLowStockLimit} من {summary.lowStockItems.length} صنف)
                    </button>
                  </li>
                ) : null}
              </ul>
            )}

            <footer className="exec-panel-foot">
              <button type="button" className="exec-action-link" onClick={onOpenInventoryReport}>
                <BackpackIcon />
                <span>فتح تقرير حركة المخزون الكامل</span>
                <ArrowLeftIcon />
              </button>
            </footer>
          </section>
        </div>
      </main>
    </MobileScroll>
  );
}

export const DashboardScreen = Dashboard;
export default Dashboard;
