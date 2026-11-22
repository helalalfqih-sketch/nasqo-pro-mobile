import { useMemo } from "react";
import {
  ArrowLeftIcon,
  BackpackIcon,
  BarChartIcon,
  CardStackIcon,
  CubeIcon,
  ExclamationTriangleIcon,
  FileTextIcon,
  LayersIcon,
  PersonIcon,
  RocketIcon,
} from "@radix-ui/react-icons";
import { computeInventorySummary, formatAmount } from "../../accounting";
import {
  computeIncomeStatement,
  computePayrollTotals,
  computeVatSummary,
  type ErpModuleId,
  type ErpWorkspaceData,
} from "../../erp";
import { MobileScroll } from "../../mobile";
import type {
  AccountRecord,
  InventoryItemRecord,
  LedgerEntryRecord,
  WarehouseRecord,
} from "../../types";
import { triggerHaptic } from "../../utils/haptics";

export function ErpHubScreen({
  companyName,
  currency,
  accounts,
  ledger,
  warehouses,
  inventory,
  erpData,
  onOpenModule,
  onOpenInventory,
}: {
  companyName: string;
  currency: string;
  accounts: readonly AccountRecord[];
  ledger: readonly LedgerEntryRecord[];
  warehouses: readonly WarehouseRecord[];
  inventory: readonly InventoryItemRecord[];
  erpData: ErpWorkspaceData;
  onOpenModule: (moduleId: ErpModuleId) => void;
  onOpenInventory: () => void;
}) {
  const income = useMemo(() => computeIncomeStatement(accounts, ledger), [accounts, ledger]);
  const invSummary = useMemo(() => computeInventorySummary(inventory), [inventory]);
  const payroll = useMemo(() => computePayrollTotals(erpData.employees), [erpData.employees]);
  const vatConfig = erpData.vatConfig ?? {
    jurisdiction: "none" as const,
    ratePercent: 0,
    basis: "recorded_only" as const,
  };
  const vat = useMemo(
    () =>
      computeVatSummary(accounts, ledger, vatConfig.ratePercent / 100, {
        vatMode: vatConfig.basis,
        jurisdictionCode: vatConfig.jurisdiction,
      }),
    [accounts, ledger, vatConfig.basis, vatConfig.jurisdiction, vatConfig.ratePercent],
  );

  const pendingPos = useMemo(
    () => erpData.purchaseOrders.filter((po) => po.status !== "received"),
    [erpData.purchaseOrders],
  );
  const pendingLeaves = useMemo(
    () => erpData.leaveRequests.filter((lv) => lv.status === "pending"),
    [erpData.leaveRequests],
  );
  const openDeals = useMemo(
    () => erpData.deals.filter((d) => d.stage !== "won" && d.stage !== "lost"),
    [erpData.deals],
  );
  const activeProduction = useMemo(
    () => erpData.productionOrders.filter((o) => o.status !== "completed"),
    [erpData.productionOrders],
  );
  const lowStockCount = useMemo(
    () => inventory.filter((item) => item.quantity <= (item.minThreshold ?? 25)).length,
    [inventory],
  );

  const formatArCount = (count: number, singular: string, plural: string) =>
    count === 1 ? `1 ${singular}` : count <= 10 ? `${count} ${plural}` : `${count} ${singular}`;

  const modules: {
    id: ErpModuleId | "inventory";
    title: string;
    subtitle: string;
    stat: string;
    icon: typeof CardStackIcon;
    tone: "blue" | "green" | "orange" | "purple" | "teal" | "slate";
  }[] = [
    {
      id: "erp-finance",
      title: "القوائم المالية والأستاذ العام",
      subtitle: "ميزان المراجعة · الدخل · الميزانية · VAT",
      stat: `${formatAmount(income.netSales)} مبيعات`,
      icon: BarChartIcon,
      tone: "blue",
    },
    {
      id: "erp-crm",
      title: "المبيعات ونقطة البيع",
      subtitle: "نقطة بيع فورية · صفقات · تحويل لفاتورة",
      stat: formatArCount(openDeals.length, "صفقة نشطة", "صفقات نشطة"),
      icon: RocketIcon,
      tone: "green",
    },
    {
      id: "erp-procurement",
      title: "المشتريات وسلسلة التوريد",
      subtitle: "أوامر الشراء · الاستلام المخزني · التكلفة",
      stat: formatArCount(pendingPos.length, "أمر مفتوح", "أوامر مفتوحة"),
      icon: BackpackIcon,
      tone: "orange",
    },
    {
      id: "erp-hr",
      title: "الموارد البشرية والرواتب",
      subtitle: "الموظفون · الحضور والإجازات · ترحيل الرواتب",
      stat: formatArCount(payroll.activeCount, "موظف", "موظفين"),
      icon: PersonIcon,
      tone: "purple",
    },
    {
      id: "erp-manufacturing",
      title: "التصنيع ومراكز التكلفة",
      subtitle: "قوائم المواد · أوامر الإنتاج · الموازنات",
      stat: `${formatArCount(activeProduction.length, "أمر إنتاج", "أوامر إنتاج")} · ${formatArCount(erpData.costCenters.length, "مركز", "مراكز")}`,
      icon: LayersIcon,
      tone: "teal",
    },
    {
      id: "inventory",
      title: "المخازن وحركة الأصناف",
      subtitle: `${formatArCount(warehouses.length, "مستودع", "مستودعات")} · ${formatArCount(invSummary.items.length, "صنف", "أصناف")}`,
      stat: lowStockCount > 0 ? `${formatArCount(lowStockCount, "ناقص", "نواقص")}` : "المخزون مستقر",
      icon: CubeIcon,
      tone: "slate",
    },
  ];

  const hasPendingActions =
    pendingPos.length > 0 ||
    pendingLeaves.length > 0 ||
    activeProduction.length > 0 ||
    lowStockCount > 0;

  return (
    <MobileScroll className="app-screen erp-scroll">
      <main className="erp-page" data-testid="erp-hub-screen">
        <section className="erp-hero-card">
          <div className="erp-hero-top">
            <div>
              <small>مركز الإدارة المتكامل</small>
              <h2>{companyName || "نسقو برو"}</h2>
            </div>
            <span className="erp-hero-badge">نظام مترابط</span>
          </div>
          <p className="erp-hero-sub">
            كل عملية في المبيعات أو المشتريات أو الرواتب أو التصنيع تُحدّث المخزون والحسابات لحظيًا.
          </p>
        </section>

        <section className="erp-kpi-grid" aria-label="المؤشرات التنفيذية">
          <article className="erp-kpi-card">
            <small>صافي الربح التشغيلي</small>
            <strong className={income.netProfit >= 0 ? "pos" : "neg"}>
              <bdi>
                {income.netProfit < 0 ? "−" : ""}
                {formatAmount(Math.abs(income.netProfit))}
              </bdi>
            </strong>
            <span>{currency}</span>
          </article>
          <article className="erp-kpi-card">
            <small>قيمة المخزون الحالية</small>
            <strong>
              <bdi>{formatAmount(invSummary.totalValue)}</bdi>
            </strong>
            <span>{formatArCount(invSummary.items.length, "صنف", "أصناف")}</span>
          </article>
          <article className="erp-kpi-card">
            <small>مسير الرواتب الشهري</small>
            <strong>
              <bdi>{formatAmount(payroll.totalNetPayroll)}</bdi>
            </strong>
            <span>{formatArCount(payroll.activeCount, "موظف نشط", "موظفين نشطين")}</span>
          </article>
          <article className="erp-kpi-card">
            <small>صافي ضريبة القيمة المضافة</small>
            <strong className={vat.netVatPayable >= 0 ? "warn" : "pos"}>
              <bdi>
                {vat.netVatPayable < 0 ? "−" : ""}
                {formatAmount(Math.abs(vat.netVatPayable))}
              </bdi>
            </strong>
            <span>
              {vatConfig.jurisdiction === "none"
                ? "غير مفعّل · 0% مسجلة"
                : vatConfig.basis === "recorded_only"
                  ? "مسجل بالفواتير"
                  : `${vatConfig.ratePercent}% تقديري`}
            </span>
          </article>
        </section>

        <section className="erp-section">
          <div className="erp-section-head">
            <h3>أقسام النظام</h3>
            <span>{modules.length} أنظمة</span>
          </div>
          <div className="erp-module-grid">
            {modules.map((mod) => (
              <button
                key={mod.id}
                type="button"
                className={`erp-module-card tone-${mod.tone}`}
                data-testid={`erp-mod-btn-${mod.id}`}
                onClick={() => {
                  triggerHaptic("light");
                  if (mod.id === "inventory") {
                    onOpenInventory();
                  } else {
                    onOpenModule(mod.id);
                  }
                }}
              >
                <div className="erp-module-icon">
                  <mod.icon />
                </div>
                <div className="erp-module-body">
                  <strong>{mod.title}</strong>
                  <small>{mod.subtitle}</small>
                  <div className="erp-module-foot">
                    <span>{mod.stat}</span>
                    <ArrowLeftIcon />
                  </div>
                </div>
              </button>
            ))}
          </div>
        </section>

        {hasPendingActions ? (
          <section className="erp-section">
            <div className="erp-section-head">
              <h3>مهام واعتمادات عبر الأقسام</h3>
              <span>متابعة فورية</span>
            </div>
            <div className="erp-action-list">
              {pendingPos.length > 0 ? (
                <button
                  type="button"
                  className="erp-action-row"
                  onClick={() => {
                    triggerHaptic("light");
                    onOpenModule("erp-procurement");
                  }}
                >
                  <span className="erp-action-dot orange" />
                  <div className="erp-action-copy">
                    <strong>{pendingPos.length} أمر شراء بانتظار الاستلام بالمخزن</strong>
                    <small>استلام البضاعة يحدّث متوسط التكلفة ويُرحّل فاتورة المورد</small>
                  </div>
                  <FileTextIcon />
                </button>
              ) : null}

              {pendingLeaves.length > 0 ? (
                <button
                  type="button"
                  className="erp-action-row"
                  onClick={() => {
                    triggerHaptic("light");
                    onOpenModule("erp-hr");
                  }}
                >
                  <span className="erp-action-dot purple" />
                  <div className="erp-action-copy">
                    <strong>{pendingLeaves.length} طلب إجازة بانتظار الاعتماد</strong>
                    <small>مراجعة طلبات الفريق وترحيل مسير الرواتب الشهري</small>
                  </div>
                  <PersonIcon />
                </button>
              ) : null}

              {activeProduction.length > 0 ? (
                <button
                  type="button"
                  className="erp-action-row"
                  onClick={() => {
                    triggerHaptic("light");
                    onOpenModule("erp-manufacturing");
                  }}
                >
                  <span className="erp-action-dot teal" />
                  <div className="erp-action-copy">
                    <strong>{activeProduction.length} أمر تصنيع جاهز للتنفيذ</strong>
                    <small>فحص توفر الخامات وإضافة المنتج التام للمستودع</small>
                  </div>
                  <LayersIcon />
                </button>
              ) : null}

              {lowStockCount > 0 ? (
                <button
                  type="button"
                  className="erp-action-row"
                  onClick={() => {
                    triggerHaptic("light");
                    onOpenInventory();
                  }}
                >
                  <span className="erp-action-dot red" />
                  <div className="erp-action-copy">
                    <strong>تنبيه مخزون: {lowStockCount} أصناف عند الحد الأدنى</strong>
                    <small>يمكنك إنشاء أمر شراء فوري من وحدة المشتريات</small>
                  </div>
                  <ExclamationTriangleIcon />
                </button>
              ) : null}
            </div>
          </section>
        ) : null}
      </main>
    </MobileScroll>
  );
}
