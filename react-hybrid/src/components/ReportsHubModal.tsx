import { useEffect, useMemo, useState } from "react";
import { ArrowRightIcon, Cross2Icon } from "@radix-ui/react-icons";
import { NasqoBrandLoader } from "./NasqoBrandLoader";
import {
  computeCategoryTotals,
  computeCategoryTotalsByCurrency,
  computeTrialBalanceByCurrency,
  computeTrialBalanceReport,
  formatAmount,
  formatSignedSmartBalance,
  getCategoryTitle,
  matchesArabicSearch,
  normalizeArabicSearch,
} from "../accounting";
import { fetchInventoryMovementsReport } from "../firebase";
import {
  ACCOUNT_CATEGORIES,
  type AccountRecord,
  type CashboxRecord,
  type InventoryItemRecord,
  type LedgerEntryRecord,
  type WarehouseRecord,
} from "../types";

type ReportId =
  | "closing"
  | "by-category"
  | "stock-remaining"
  | "stock-expiry"
  | "invoice-profit"
  | "services"
  | "tax";

type MovementReport = Awaited<ReturnType<typeof fetchInventoryMovementsReport>>;

interface ReportsHubModalProps {
  open: boolean;
  onClose: () => void;
  uid: string;
  accounts: readonly AccountRecord[];
  ledger: readonly LedgerEntryRecord[];
  inventory: readonly InventoryItemRecord[];
  warehouses: readonly WarehouseRecord[];
  cashboxes: readonly CashboxRecord[];
  currencyCodes: readonly string[];
  defaultCurrency: string;
  onOpenCashboxes: () => void;
  onOpenTrialBalance: () => void;
  onOpenInventoryMovements: () => void;
}

const REPORT_TITLES: Record<ReportId, string> = {
  closing: "تقرير الحسابات الختامية",
  "by-category": "تقرير إجمالي حسب التصنيف",
  "stock-remaining": "المخزون المتبقي",
  "stock-expiry": "المخزون المتبقي وتاريخ الانتهاء",
  "invoice-profit": "أرباح الفواتير",
  services: "تقارير الخدمات",
  tax: "التقارير الضريبية",
};

const round2 = (n: number) => Math.round((Number.isFinite(n) ? n : 0) * 100) / 100;

function matchesCurrency(entryCurrency: string, filter: string): boolean {
  return filter === "الكل" || entryCurrency === filter;
}

export function ReportsHubModal({
  open,
  onClose,
  uid,
  accounts,
  ledger,
  inventory,
  warehouses,
  cashboxes,
  currencyCodes,
  defaultCurrency,
  onOpenCashboxes,
  onOpenTrialBalance,
  onOpenInventoryMovements,
}: ReportsHubModalProps) {
  const [report, setReport] = useState<ReportId | null>(null);
  const [currency, setCurrency] = useState(defaultCurrency || "ريال");
  const [warehouseId, setWarehouseId] = useState("");
  const [fromDate, setFromDate] = useState("");
  const [toDate, setToDate] = useState("");
  const [stockSearch, setStockSearch] = useState("");
  const [includeZeroStock, setIncludeZeroStock] = useState(false);

  const [profitData, setProfitData] = useState<MovementReport | null>(null);
  const [profitError, setProfitError] = useState("");
  const [stockReportData, setStockReportData] = useState<MovementReport | null>(null);
  const [stockReportLoading, setStockReportLoading] = useState(false);
  const [stockReportError, setStockReportError] = useState("");

  const [visibleLimit, setVisibleLimit] = useState(80);

  useEffect(() => {
    if (!open) {
      setReport(null);
      setStockSearch("");
      setIncludeZeroStock(false);
    }
    setVisibleLimit(80);
  }, [open]);

  useEffect(() => {
    setVisibleLimit(80);
  }, [report, currency, warehouseId, fromDate, toDate, stockSearch, includeZeroStock]);

  // Fetch accurate per-warehouse stock directly from SQLite for stock-remaining & stock-expiry
  useEffect(() => {
    if (!open || (report !== "stock-remaining" && report !== "stock-expiry")) return;
    let active = true;
    setStockReportLoading(true);
    setStockReportError("");
    void fetchInventoryMovementsReport(uid, {
      warehouseId: warehouseId || undefined,
    })
      .then((res) => {
        if (active) setStockReportData(res);
      })
      .catch(() => {
        if (active) {
          setStockReportData(null);
          setStockReportError("تعذر تحميل رصيد المخزون الفعلي من قاعدة البيانات.");
        }
      })
      .finally(() => {
        if (active) setStockReportLoading(false);
      });
    return () => {
      active = false;
    };
  }, [open, report, uid, warehouseId, inventory.length, ledger.length]);

  useEffect(() => {
    if (!open || report !== "invoice-profit") return;
    let active = true;
    setProfitData(null);
    setProfitError("");
    void fetchInventoryMovementsReport(uid, {
      fromDate: fromDate || undefined,
      toDate: toDate || undefined,
      currency: currency !== "الكل" ? currency : undefined,
      warehouseId: warehouseId || undefined,
    })
      .then((res) => {
        if (active) setProfitData(res);
      })
      .catch(() => {
        if (active) setProfitError("تعذر تحميل تقرير الأرباح من قاعدة البيانات.");
      });
    return () => {
      active = false;
    };
  }, [open, report, uid, fromDate, toDate, currency, warehouseId]);

  const activeLedger = useMemo(
    () => (open && (report === "services" || report === "tax") ? ledger.filter((e) => !e.deleted) : []),
    [ledger, open, report],
  );

  // Closing report: single currency OR separate blocks per currency when "الكل" is chosen
  const closingReports = useMemo(() => {
    if (!open || report !== "closing") return [];
    if (currency === "الكل") {
      return computeTrialBalanceByCurrency(accounts, ledger, inventory, cashboxes, {
        currencies: currencyCodes,
      });
    }
    return [computeTrialBalanceReport(accounts, ledger, inventory, cashboxes, { currency })];
  }, [accounts, ledger, inventory, cashboxes, currency, currencyCodes, open, report]);

  // By-category report: single currency OR separate tables per currency when "الكل" is chosen
  const categoryReportBlocks = useMemo(() => {
    if (!open || report !== "by-category") return [];
    if (currency === "الكل") {
      return computeCategoryTotalsByCurrency(accounts, ledger, currencyCodes);
    }
    return [{ currency, totals: computeCategoryTotals(accounts, ledger, currency) }];
  }, [accounts, ledger, currency, currencyCodes, open, report]);

  const inventoryMetaById = useMemo(() => new Map(inventory.map((i) => [i.id, i])), [inventory]);

  const stockRows = useMemo(() => {
    if (!open || (report !== "stock-remaining" && report !== "stock-expiry")) return [];
    const sourceRows = stockReportData?.itemRows ?? [];
    const q = normalizeArabicSearch(stockSearch);
    return sourceRows
      .map((r) => {
        const meta = inventoryMetaById.get(r.id);
        const qty = round2(Number(r.availableQty ?? 0));
        const unitCost = round2(Number(r.unitCost ?? r.avgCost ?? 0));
        const value = round2(Number(r.remainingValue ?? qty * unitCost));
        return {
          id: r.id,
          code: r.code,
          name: r.name,
          sku: r.sku || meta?.sku || "",
          unit: r.unit || "حبة",
          qty,
          unitCost,
          value,
          currencyCode: r.currencyCode || meta?.currencyCode || "ريال",
          expiryDate: r.expiryDate || meta?.expiryDate || "",
          hasMovement: r.hasMovement,
        };
      })
      .filter((r) => (includeZeroStock ? true : Math.abs(r.qty) > 0.0001))
      .filter((r) =>
        q ? matchesArabicSearch(`${r.code ?? ""} ${r.name} ${r.sku} ${r.unit}`, q) : true,
      )
      .sort((a, b) => a.name.localeCompare(b.name, "ar"));
  }, [open, report, stockReportData, inventoryMetaById, includeZeroStock, stockSearch]);

  const stockTotalsByCurrency = useMemo(() => {
    const map = new Map<string, { currency: string; qty: number; value: number; count: number }>();
    for (const r of stockRows) {
      const curr = r.currencyCode || "ريال";
      const cur = map.get(curr) ?? { currency: curr, qty: 0, value: 0, count: 0 };
      cur.qty = round2(cur.qty + r.qty);
      cur.value = round2(cur.value + r.value);
      cur.count += 1;
      map.set(curr, cur);
    }
    return [...map.values()];
  }, [stockRows]);

  const totalStockQty = useMemo(
    () => round2(stockRows.reduce((s, r) => s + r.qty, 0)),
    [stockRows],
  );

  const todayMs = useMemo(() => {
    const t = new Date();
    return Date.UTC(t.getFullYear(), t.getMonth(), t.getDate());
  }, []);

  const expiryRows = useMemo(
    () =>
      open && report === "stock-expiry"
        ? stockRows
            .filter((r) => Boolean(r.expiryDate))
            .map((r) => {
              const ms = Date.parse(`${r.expiryDate}T00:00:00Z`);
              const days = Number.isFinite(ms) ? Math.round((ms - todayMs) / 86_400_000) : null;
              return { ...r, days };
            })
            .sort((a, b) => (a.days ?? 1e9) - (b.days ?? 1e9))
        : [],
    [open, report, stockRows, todayMs],
  );

  const profitRows = useMemo(
    () =>
      open && report === "invoice-profit"
        ? (profitData?.itemRows ?? [])
            .filter((r) => Math.abs(r.sellQty) > 0.0001 || Math.abs(r.sellTotal) > 0.0001)
            .sort((a, b) => b.profit - a.profit)
        : [],
    [open, profitData, report],
  );

  const serviceRows = useMemo(
    () =>
      open && report === "services"
        ? activeLedger
            .filter(
              (e) =>
                e.kind === "invoice" && e.invoiceContent === "free" && matchesCurrency(e.currency, currency),
            )
            .sort((a, b) => b.entryDate.localeCompare(a.entryDate) || b.entryNumber - a.entryNumber)
        : [],
    [activeLedger, currency, open, report],
  );

  const serviceTotalsByCurrency = useMemo(() => {
    const map = new Map<string, { currency: string; sales: number; purchases: number }>();
    for (const e of serviceRows) {
      const curr = e.currency || "ريال";
      const cur = map.get(curr) ?? { currency: curr, sales: 0, purchases: 0 };
      const dt = e.docType !== undefined && e.docType !== null ? Number(e.docType) : null;
      const isSale = dt !== null ? dt === 2 || dt === 7 : e.direction === "debit";
      if (isSale) cur.sales = round2(cur.sales + e.amount);
      else cur.purchases = round2(cur.purchases + e.amount);
      map.set(curr, cur);
    }
    if (map.size === 0 && currency !== "الكل") {
      map.set(currency, { currency, sales: 0, purchases: 0 });
    }
    return [...map.values()];
  }, [serviceRows, currency]);

  const taxByCurrency = useMemo(() => {
    if (!open || report !== "tax") return [];
    const map = new Map<string, { currency: string; output: number; input: number; net: number; taxedDocs: number }>();
    for (const e of activeLedger) {
      if ((e.kind !== "invoice" && e.kind !== "return") || !matchesCurrency(e.currency, currency)) continue;
      const t = Number(e.taxAmount ?? 0);
      if (!(t > 0)) continue;
      const curr = e.currency || "ريال";
      const cur = map.get(curr) ?? { currency: curr, output: 0, input: 0, net: 0, taxedDocs: 0 };
      cur.taxedDocs += 1;
      const dt = e.docType !== undefined && e.docType !== null ? Number(e.docType) : null;
      const isSaleSide =
        dt !== null
          ? dt === 2 || dt === 7 || dt === 4
          : e.kind === "invoice"
            ? e.direction === "debit"
            : e.direction === "credit";
      const sign = e.kind === "return" ? -1 : 1;
      if (isSaleSide) cur.output = round2(cur.output + sign * t);
      else cur.input = round2(cur.input + sign * t);
      cur.net = round2(cur.output - cur.input);
      map.set(curr, cur);
    }
    if (map.size === 0) {
      return [
        {
          currency: currency === "الكل" ? defaultCurrency || "ريال" : currency,
          output: 0,
          input: 0,
          net: 0,
          taxedDocs: 0,
        },
      ];
    }
    return [...map.values()];
  }, [activeLedger, currency, defaultCurrency, open, report]);

  if (!open) return null;

  const openExternal = (fn: () => void) => {
    onClose();
    fn();
  };

  const menu: { label: string; tone: "orange" | "blue"; run: () => void }[][] = [
    [
      { label: "حركة الصندوق", tone: "orange", run: () => openExternal(onOpenCashboxes) },
      { label: "تقرير الحسابات الختامية", tone: "blue", run: () => setReport("closing") },
      { label: "تقرير إجمالي حسب التصنيف", tone: "orange", run: () => setReport("by-category") },
      { label: "ميزان المراجعة", tone: "blue", run: () => openExternal(onOpenTrialBalance) },
    ],
    [
      { label: "تقرير حركة المخزون والأرباح", tone: "orange", run: () => openExternal(onOpenInventoryMovements) },
      { label: "تقرير المخزون المتبقي وتاريخ الانتهاء", tone: "blue", run: () => setReport("stock-expiry") },
      { label: "المخزون المتبقي", tone: "orange", run: () => setReport("stock-remaining") },
      { label: "أرباح الفواتير", tone: "blue", run: () => setReport("invoice-profit") },
      { label: "تقارير الخدمات", tone: "orange", run: () => setReport("services") },
      { label: "تقارير ضريبية", tone: "blue", run: () => setReport("tax") },
    ],
  ];
  const sectionTitles = ["التقارير المالية", "التقارير المخزنية"];

  const usesCurrency =
    report === "closing" ||
    report === "by-category" ||
    report === "services" ||
    report === "tax" ||
    report === "invoice-profit";
  const usesWarehouse = report === "stock-remaining" || report === "stock-expiry" || report === "invoice-profit";
  const usesDates = report === "invoice-profit";
  const usesStockControls = report === "stock-remaining" || report === "stock-expiry";

  const row = (key: string, label: string, value: string, tone?: "pos" | "neg") => (
    <div className="trial-balance-row" key={key}>
      <span className="trial-row-label">{label}</span>
      <strong className={`trial-row-val ${tone ?? ""}`}>
        <bdi>{value}</bdi>
      </strong>
    </div>
  );

  return (
    <div className="center-modal-layer" data-testid="reports-hub-modal">
      <button className="center-modal-backdrop" onClick={onClose} aria-label="إغلاق التقارير" />
      <section
        className="account-groups-modal reports-hub-modal"
        role="dialog"
        aria-modal="true"
        aria-labelledby="reports-hub-title"
      >
        <header className="smart-modal-header">
          <button type="button" className="smart-modal-close" onClick={onClose} aria-label="إغلاق">
            <Cross2Icon />
          </button>
          <h2 id="reports-hub-title">{report ? REPORT_TITLES[report] : "التقارير"}</h2>
          {report ? (
            <button
              type="button"
              className="smart-modal-close"
              onClick={() => setReport(null)}
              aria-label="رجوع إلى قائمة التقارير"
              data-testid="reports-back-btn"
            >
              <ArrowRightIcon />
            </button>
          ) : (
            <span className="smart-modal-spacer" aria-hidden="true" />
          )}
        </header>

        {!report ? (
          <div className="reports-hub-menu" data-testid="reports-hub-menu">
            {menu.map((group, gi) => (
              <div key={sectionTitles[gi]}>
                <div className="reports-hub-section">{sectionTitles[gi]}</div>
                {group.map((item) => (
                  <button
                    key={item.label}
                    type="button"
                    className={`reports-hub-btn ${item.tone}`}
                    onClick={item.run}
                  >
                    {item.label}
                  </button>
                ))}
              </div>
            ))}
          </div>
        ) : (
          <div className="reports-hub-detail">
            {usesCurrency || usesWarehouse || usesDates || usesStockControls ? (
              <div className="reports-hub-filters">
                {usesCurrency ? (
                  <label>
                    <span>العملة</span>
                    <select aria-label="عملة التقرير" value={currency} onChange={(e) => setCurrency(e.target.value)}>
                      {currencyCodes.map((c) => (
                        <option key={c} value={c}>
                          {c}
                        </option>
                      ))}
                      <option value="الكل">الكل (منفصل لكل عملة)</option>
                    </select>
                  </label>
                ) : null}
                {usesWarehouse ? (
                  <label>
                    <span>المخزن</span>
                    <select
                      aria-label="مخزن التقرير"
                      value={warehouseId}
                      onChange={(e) => setWarehouseId(e.target.value)}
                    >
                      <option value="">جميع المخازن</option>
                      {warehouses.map((w) => (
                        <option key={w.id} value={w.id}>
                          {w.name}
                        </option>
                      ))}
                    </select>
                  </label>
                ) : null}
                {usesDates ? (
                  <>
                    <label>
                      <span>من تاريخ</span>
                      <input
                        type="date"
                        dir="ltr"
                        aria-label="من تاريخ"
                        value={fromDate}
                        onChange={(e) => setFromDate(e.target.value)}
                      />
                    </label>
                    <label>
                      <span>إلى تاريخ</span>
                      <input
                        type="date"
                        dir="ltr"
                        aria-label="إلى تاريخ"
                        value={toDate}
                        onChange={(e) => setToDate(e.target.value)}
                      />
                    </label>
                  </>
                ) : null}
                {usesStockControls ? (
                  <>
                    <label className="reports-hub-search-field">
                      <span>بحث في الأصناف</span>
                      <input
                        type="search"
                        aria-label="بحث في أصناف المخزون المتبقي"
                        placeholder="ابحث بالاسم أو الرمز..."
                        value={stockSearch}
                        onChange={(e) => setStockSearch(e.target.value)}
                      />
                    </label>
                    <label className="reports-hub-checkbox">
                      <input
                        type="checkbox"
                        checked={includeZeroStock}
                        onChange={(e) => setIncludeZeroStock(e.target.checked)}
                        data-testid="stock-include-zero-toggle"
                      />
                      <span>إظهار الأصناف ذات الرصيد الصفري</span>
                    </label>
                  </>
                ) : null}
              </div>
            ) : null}

            {report === "closing" ? (
              <div data-testid="report-closing" className="reports-currency-stack">
                {closingReports.map((closing) => (
                  <div key={closing.currency} className="reports-currency-block">
                    <div className="smart-section-band">الأرصدة — {closing.currency}</div>
                    <div className="trial-balance-rows">
                      {row(`${closing.currency}-dr`, "إجمالي المدين (عليهم)", `${formatAmount(closing.totalDebitAccounts)} ${closing.currency}`, "pos")}
                      {row(`${closing.currency}-cr`, "إجمالي الدائن (لهم)", `${formatAmount(closing.totalCreditAccounts)} ${closing.currency}`, "neg")}
                      {row(`${closing.currency}-cash`, "إجمالي النقدية", `${formatSignedSmartBalance(closing.cashTotal)} ${closing.currency}`, closing.cashTotal < 0 ? "neg" : "pos")}
                      {row(`${closing.currency}-net`, "صافي الرصيد", `${formatSignedSmartBalance(closing.netBalance)} ${closing.currency}`, closing.netBalance < 0 ? "neg" : "pos")}
                    </div>
                    <div className="smart-section-band">نتيجة النشاط — {closing.currency}</div>
                    <div className="trial-balance-rows">
                      {row(`${closing.currency}-sales`, "المبيعات", `${formatAmount(closing.salesTotal)} ${closing.currency}`, "pos")}
                      {row(`${closing.currency}-purch`, "المشتريات", `${formatAmount(closing.purchasesTotal)} ${closing.currency}`, "neg")}
                      {row(`${closing.currency}-inv`, "قيمة المخزون", `${formatAmount(closing.inventoryValue)} ${closing.currency}`, "pos")}
                      {row(`${closing.currency}-prof`, "صافي الربح التقديري", `${formatSignedSmartBalance(closing.netProfit)} ${closing.currency}`, closing.netProfit < 0 ? "neg" : "pos")}
                    </div>
                  </div>
                ))}
              </div>
            ) : null}

            {report === "by-category" ? (
              <div data-testid="report-by-category" className="reports-currency-stack">
                {categoryReportBlocks.map((block) => (
                  <div key={block.currency} className="reports-currency-block">
                    {categoryReportBlocks.length > 1 ? (
                      <div className="smart-section-band">تصنيفات الحسابات — {block.currency}</div>
                    ) : null}
                    <div className="account-groups-table-wrap">
                      <table className="account-groups-table">
                        <thead>
                          <tr>
                            <th>التصنيف</th>
                            <th>الحسابات</th>
                            <th>عليه</th>
                            <th>له</th>
                            <th>الرصيد ({block.currency})</th>
                          </tr>
                        </thead>
                        <tbody>
                          {ACCOUNT_CATEGORIES.map((cat) => {
                            const b = block.totals[cat];
                            return (
                              <tr key={cat}>
                                <td className="ag-name-cell">{getCategoryTitle(cat)}</td>
                                <td>{b.count}</td>
                                <td className="coa-debit-cell">{formatAmount(b.debitTotal)}</td>
                                <td className="coa-credit-cell">{formatAmount(b.creditTotal)}</td>
                                <td className={b.netSigned < 0 ? "coa-debit-cell" : "coa-credit-cell"}>
                                  {formatAmount(Math.abs(b.netSigned))}{" "}
                                  {b.netSigned < 0 ? "عليه" : b.netSigned > 0 ? "له" : "متزن"}
                                </td>
                              </tr>
                            );
                          })}
                        </tbody>
                      </table>
                    </div>
                  </div>
                ))}
              </div>
            ) : null}

            {report === "stock-remaining" ? (
              <div data-testid="report-stock-remaining">
                {stockReportError ? <p className="cash-empty">{stockReportError}</p> : null}
                {stockReportLoading ? (
                  <NasqoBrandLoader size="sm" label="جاري احتساب الرصيد الفعلي للمخزون..." />
                ) : (
                  <>
                    <div className="account-groups-table-wrap">
                      <table className="account-groups-table">
                        <thead>
                          <tr>
                            <th>الرقم</th>
                            <th>اسم الصنف</th>
                            <th>الوحدة</th>
                            <th>الكمية</th>
                            <th>القيمة</th>
                          </tr>
                        </thead>
                        <tbody>
                          {stockRows.slice(0, visibleLimit).map((r, idx) => (
                            <tr key={r.id}>
                              <td>{r.code ?? idx + 1}</td>
                              <td className="ag-name-cell">{r.name}</td>
                              <td>{r.unit}</td>
                              <td className={r.qty < 0 ? "coa-debit-cell" : ""}>
                                <bdi>{formatAmount(r.qty)}</bdi>
                              </td>
                              <td>
                                <bdi>
                                  {formatAmount(r.value)} {r.currencyCode}
                                </bdi>
                              </td>
                            </tr>
                          ))}
                          {stockRows.length > visibleLimit ? (
                            <tr>
                              <td colSpan={5} style={{ textAlign: "center", padding: 8 }}>
                                <button
                                  type="button"
                                  className="load-more-list-btn"
                                  onClick={() => setVisibleLimit((v) => v + 100)}
                                >
                                  عرض المزيد (المعروض {visibleLimit} من {stockRows.length})
                                </button>
                              </td>
                            </tr>
                          ) : null}
                          {stockRows.length === 0 ? (
                            <tr>
                              <td colSpan={5} className="coa-empty-cell">
                                {includeZeroStock
                                  ? "لا توجد أصناف مسجلة تطابق البحث."
                                  : "لا توجد أصناف بكميات متبقية في هذا النطاق. فعّل خيار إظهار الأصناف الصفرية لعرض كامل الدليل."}
                              </td>
                            </tr>
                          ) : null}
                        </tbody>
                      </table>
                    </div>
                    <div className="trial-balance-rows">
                      {row("stock-count", "عدد الأصناف الظاهرة", String(stockRows.length))}
                      {row("stock-qty", "إجمالي الكمية المتبقية", formatAmount(totalStockQty), totalStockQty < 0 ? "neg" : "pos")}
                      {stockTotalsByCurrency.map((ct) =>
                        row(
                          `stock-val-${ct.currency}`,
                          `قيمة المخزون (${ct.currency})`,
                          `${formatAmount(ct.value)} ${ct.currency}`,
                          ct.value < 0 ? "neg" : "pos",
                        ),
                      )}
                    </div>
                  </>
                )}
              </div>
            ) : null}

            {report === "stock-expiry" ? (
              <div data-testid="report-stock-expiry">
                {stockReportError ? <p className="cash-empty">{stockReportError}</p> : null}
                {stockReportLoading ? (
                  <NasqoBrandLoader size="sm" label="جاري تحميل تواريخ الانتهاء..." />
                ) : (
                  <div className="account-groups-table-wrap">
                    <table className="account-groups-table">
                      <thead>
                        <tr>
                          <th>اسم الصنف</th>
                          <th>الكمية</th>
                          <th>تاريخ الانتهاء</th>
                          <th>الحالة</th>
                        </tr>
                      </thead>
                      <tbody>
                        {expiryRows.slice(0, visibleLimit).map((r) => (
                          <tr key={r.id}>
                            <td className="ag-name-cell">{r.name}</td>
                            <td>
                              <bdi>
                                {formatAmount(r.qty)} {r.unit}
                              </bdi>
                            </td>
                            <td>
                              <bdi>{r.expiryDate}</bdi>
                            </td>
                            <td
                              className={
                                r.days !== null && r.days < 0
                                  ? "coa-debit-cell"
                                  : r.days !== null && r.days <= 30
                                    ? "coa-cash-tag"
                                    : "coa-credit-cell"
                              }
                            >
                              {r.days === null
                                ? "—"
                                : r.days < 0
                                  ? `منتهي منذ ${Math.abs(r.days)} يوم`
                                  : r.days === 0
                                    ? "ينتهي اليوم"
                                    : `متبقي ${r.days} يوم`}
                            </td>
                          </tr>
                        ))}
                        {expiryRows.length > visibleLimit ? (
                          <tr>
                            <td colSpan={4} style={{ textAlign: "center", padding: 8 }}>
                              <button
                                type="button"
                                className="load-more-list-btn"
                                onClick={() => setVisibleLimit((v) => v + 100)}
                              >
                                عرض المزيد (المعروض {visibleLimit} من {expiryRows.length})
                              </button>
                            </td>
                          </tr>
                        ) : null}
                        {expiryRows.length === 0 ? (
                          <tr>
                            <td colSpan={4} className="coa-empty-cell">
                              لا توجد أصناف بتاريخ انتهاء مسجل في هذا النطاق.
                            </td>
                          </tr>
                        ) : null}
                      </tbody>
                    </table>
                  </div>
                )}
              </div>
            ) : null}

            {report === "invoice-profit" ? (
              <div data-testid="report-invoice-profit">
                {profitError ? <p className="cash-empty">{profitError}</p> : null}
                {!profitData && !profitError ? <NasqoBrandLoader size="sm" label="جاري حساب الأرباح..." /> : null}
                {profitData ? (
                  <>
                    <div className="account-groups-table-wrap">
                      <table className="account-groups-table">
                        <thead>
                          <tr>
                            <th>اسم الصنف</th>
                            <th>كمية البيع</th>
                            <th>إجمالي البيع</th>
                            <th>الربح</th>
                          </tr>
                        </thead>
                        <tbody>
                          {profitRows.slice(0, visibleLimit).map((r) => (
                            <tr key={r.id}>
                              <td className="ag-name-cell">{r.name}</td>
                              <td>{formatAmount(r.sellQty)}</td>
                              <td>
                                {formatAmount(r.sellTotal)} {r.currencyCode || ""}
                              </td>
                              <td className={r.profit < 0 ? "coa-debit-cell" : "coa-credit-cell"}>
                                {formatSignedSmartBalance(r.profit)}
                              </td>
                            </tr>
                          ))}
                          {profitRows.length > visibleLimit ? (
                            <tr>
                              <td colSpan={4} style={{ textAlign: "center", padding: 8 }}>
                                <button
                                  type="button"
                                  className="load-more-list-btn"
                                  onClick={() => setVisibleLimit((v) => v + 100)}
                                >
                                  عرض المزيد (المعروض {visibleLimit} من {profitRows.length})
                                </button>
                              </td>
                            </tr>
                          ) : null}
                          {profitRows.length === 0 ? (
                            <tr>
                              <td colSpan={4} className="coa-empty-cell">
                                لا توجد مبيعات أصناف في النطاق المحدد.
                              </td>
                            </tr>
                          ) : null}
                        </tbody>
                      </table>
                    </div>
                    <div className="trial-balance-rows">
                      {currency === "الكل" && (profitData.totalsByCurrency?.length ?? 0) > 0 ? (
                        profitData.totalsByCurrency!.map((ct) => (
                          <div key={ct.currency} className="reports-currency-subblock">
                            {row(
                              `prof-sales-${ct.currency}`,
                              `إجمالي المبيعات (${ct.currency})`,
                              `${formatAmount(ct.totalSales)} ${ct.currency}`,
                              "pos",
                            )}
                            {row(
                              `prof-net-${ct.currency}`,
                              `إجمالي الأرباح (${ct.currency})`,
                              `${formatSignedSmartBalance(ct.totalProfit)} ${ct.currency}`,
                              ct.totalProfit < 0 ? "neg" : "pos",
                            )}
                          </div>
                        ))
                      ) : (
                        <>
                          {row("prof-sales", "إجمالي المبيعات", formatAmount(profitData.totals.totalSales), "pos")}
                          {row(
                            "prof-net",
                            "إجمالي الأرباح",
                            formatSignedSmartBalance(profitData.totals.totalProfit),
                            profitData.totals.totalProfit < 0 ? "neg" : "pos",
                          )}
                        </>
                      )}
                    </div>
                  </>
                ) : null}
              </div>
            ) : null}

            {report === "services" ? (
              <div data-testid="report-services">
                <div className="account-groups-table-wrap">
                  <table className="account-groups-table">
                    <thead>
                      <tr>
                        <th>الرقم</th>
                        <th>التاريخ</th>
                        <th>الحساب</th>
                        <th>النوع</th>
                        <th>المبلغ</th>
                      </tr>
                    </thead>
                    <tbody>
                      {serviceRows.slice(0, visibleLimit).map((e) => (
                        <tr key={e.id}>
                          <td>{e.entryNumber}</td>
                          <td>
                            <bdi>{e.entryDate}</bdi>
                          </td>
                          <td className="ag-name-cell">{e.accountName}</td>
                          <td>{e.typeLabel}</td>
                          <td className={e.direction === "debit" ? "coa-credit-cell" : "coa-debit-cell"}>
                            {formatAmount(e.amount)} {e.currency}
                          </td>
                        </tr>
                      ))}
                      {serviceRows.length > visibleLimit ? (
                        <tr>
                          <td colSpan={5} style={{ textAlign: "center", padding: 8 }}>
                            <button
                              type="button"
                              className="load-more-list-btn"
                              onClick={() => setVisibleLimit((v) => v + 100)}
                            >
                              عرض المزيد (المعروض {visibleLimit} من {serviceRows.length})
                            </button>
                          </td>
                        </tr>
                      ) : null}
                      {serviceRows.length === 0 ? (
                        <tr>
                          <td colSpan={5} className="coa-empty-cell">
                            لا توجد فواتير خدمات (فواتير حرة بدون أصناف).
                          </td>
                        </tr>
                      ) : null}
                    </tbody>
                  </table>
                </div>
                <div className="trial-balance-rows">
                  {serviceTotalsByCurrency.map((st) => (
                    <div key={st.currency} className="reports-currency-subblock">
                      {row(`srv-s-${st.currency}`, `إيرادات الخدمات (${st.currency})`, `${formatAmount(st.sales)} ${st.currency}`, "pos")}
                      {row(`srv-p-${st.currency}`, `مصروفات الخدمات (${st.currency})`, `${formatAmount(st.purchases)} ${st.currency}`, "neg")}
                      {row(
                        `srv-n-${st.currency}`,
                        `صافي الخدمات (${st.currency})`,
                        `${formatSignedSmartBalance(st.sales - st.purchases)} ${st.currency}`,
                        st.sales - st.purchases < 0 ? "neg" : "pos",
                      )}
                    </div>
                  ))}
                </div>
              </div>
            ) : null}

            {report === "tax" ? (
              <div data-testid="report-tax" className="reports-currency-stack">
                {taxByCurrency.map((t) => (
                  <div key={t.currency} className="reports-currency-block">
                    <div className="smart-section-band">ملخص ضريبة القيمة المضافة — {t.currency}</div>
                    <div className="trial-balance-rows">
                      {row(`${t.currency}-out`, "ضريبة المبيعات (مخرجات)", `${formatAmount(t.output)} ${t.currency}`, "pos")}
                      {row(`${t.currency}-in`, "ضريبة المشتريات (مدخلات)", `${formatAmount(t.input)} ${t.currency}`, "neg")}
                      {row(
                        `${t.currency}-net`,
                        t.net >= 0 ? "الضريبة المستحقة للسداد" : "ضريبة مستردة",
                        `${formatAmount(Math.abs(t.net))} ${t.currency}`,
                        t.net >= 0 ? "neg" : "pos",
                      )}
                      {row(`${t.currency}-docs`, "عدد المستندات الخاضعة للضريبة", String(t.taxedDocs))}
                    </div>
                  </div>
                ))}
                {taxByCurrency.every((t) => t.taxedDocs === 0) ? (
                  <p className="cash-empty">لا توجد مستندات بضريبة مسجلة في هذا النطاق حتى الآن.</p>
                ) : null}
              </div>
            ) : null}
          </div>
        )}

        <footer className="account-groups-footer">
          <span>{report ? REPORT_TITLES[report] : "اختر تقريرًا"}</span>
          <button type="button" className="ag-btn close" onClick={onClose}>
            إغلاق
          </button>
        </footer>
      </section>
    </div>
  );
}
