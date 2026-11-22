import {
  affectsAccountBalance,
  computeAccountSummary,
  computeInventorySummary,
  formatAmount,
  inferExpenseCategory,
  normalizeExpenseCategory,
  parseArabicNumber,
} from "./accounting.ts";
import {
  EXPENSE_CATEGORIES,
  type AccountRecord,
  type CashboxRecord,
  type CurrencyCode,
  type ExpenseCategory,
  type InventoryItemRecord,
  type LedgerEntryRecord,
} from "./types.ts";

export type ErpModuleId =
  | "erp-hub"
  | "erp-finance"
  | "erp-hr"
  | "erp-crm"
  | "erp-procurement"
  | "erp-manufacturing";

export type ErpEmployeeProfile = {
  id: string;
  accountId?: string;
  name: string;
  roleTitle: string;
  department: string;
  basicSalary: number;
  allowances: number;
  deductions: number;
  status: "active" | "on-leave" | "inactive";
  hireDate: string;
  leaveBalanceDays: number;
  attendanceToday: "present" | "leave" | "absent";
};

export type ErpLeaveRequest = {
  id: string;
  employeeId: string;
  employeeName: string;
  leaveType: "سنوية" | "مرضية" | "اضطرارية";
  startDate: string;
  days: number;
  status: "pending" | "approved" | "rejected";
  note: string;
};

export type ErpDealStage = "lead" | "proposal" | "negotiation" | "won" | "lost";

export type ErpDealRecord = {
  id: string;
  title: string;
  clientAccountId: string;
  clientName: string;
  value: number;
  currency: CurrencyCode;
  stage: ErpDealStage;
  probability: number;
  expectedCloseDate: string;
  assignedTo: string;
  convertedInvoiceEntryId?: string;
};

export type ErpPurchaseOrderLine = {
  inventoryItemId?: string;
  itemName: string;
  unit: string;
  quantity: number;
  unitCost: number;
};

export type ErpPurchaseOrderStatus = "draft" | "approved" | "received";

export type ErpPurchaseOrder = {
  id: string;
  poNumber: string;
  supplierAccountId: string;
  supplierName: string;
  warehouseId: string;
  warehouseName: string;
  currency: CurrencyCode;
  orderDate: string;
  expectedDate: string;
  status: ErpPurchaseOrderStatus;
  lines: ErpPurchaseOrderLine[];
  notes: string;
  postedLedgerEntryId?: string;
};

export type ErpBomComponent = {
  inventoryItemId: string;
  itemName: string;
  unit: string;
  quantityPerUnit: number;
};

export type ErpBomRecipe = {
  id: string;
  name: string;
  finishedItemId: string;
  finishedItemName: string;
  finishedUnit: string;
  components: ErpBomComponent[];
};

export type ErpProductionOrder = {
  id: string;
  orderNumber: string;
  bomId: string;
  bomName: string;
  finishedItemId: string;
  finishedItemName: string;
  quantityToProduce: number;
  warehouseId: string;
  status: "planned" | "in-progress" | "completed";
  createdDate: string;
  completedDate?: string;
  costCenterId?: string;
};

export type ErpCostCenter = {
  id: string;
  code: string;
  name: string;
  managerName: string;
  budget: number;
  extraPostedSpend: number;
  linkedCategories: ExpenseCategory[];
  status: "active" | "closed";
};

export type ErpVatJurisdiction = "none" | "sa_15" | "ae_5" | "custom";

export type ErpVatConfig = {
  jurisdiction: ErpVatJurisdiction;
  ratePercent: number;
  basis: "recorded_only" | "estimated_gross";
};

export type ErpWorkspaceData = {
  employees: ErpEmployeeProfile[];
  leaveRequests: ErpLeaveRequest[];
  deals: ErpDealRecord[];
  purchaseOrders: ErpPurchaseOrder[];
  boms: ErpBomRecipe[];
  productionOrders: ErpProductionOrder[];
  costCenters: ErpCostCenter[];
  lastPayrollRunMonth?: string;
  vatConfig?: ErpVatConfig;
};

export type FinancialReportScopeOptions = {
  currency?: string;
  fromDate?: string;
  toDate?: string;
};

export type FinancialScopeMetadata = {
  effectiveCurrency: string;
  fromDate: string | null;
  toDate: string | null;
  matchedEntriesCount: number;
  excludedByCurrencyCount: number;
  excludedByDateCount: number;
  earliestEntryDate: string | null;
  latestEntryDate: string | null;
};

export type CashboxBreakdownItem = {
  id: number;
  name: string;
  currencyCode: string;
  isActive: boolean;
  totalIn: number;
  totalOut: number;
  netBalance: number;
  entryCount: number;
};

export type CashReconciliationSummary = {
  linkedCashboxes: CashboxBreakdownItem[];
  linkedCashboxesNet: number;
  unassignedCashIn: number;
  unassignedCashOut: number;
  unassignedCashNet: number;
  unassignedCashCount: number;
  totalCashFlowNet: number;
  ledgerCashAccountsNet: number;
  differenceVsLedgerAccounts: number;
  differenceVsCashboxesReport: number;
};

export type InventoryReconciliationSummary = {
  verifiedCount: number;
  verifiedValue: number;
  unverifiedCount: number;
  unverifiedEstimatedValue: number;
  inventoryReportTotalValue: number;
  activeBasis: "verified_only" | "include_unverified_estimated";
  differenceVsInventoryReport: number;
};

export type TrialBalanceRow = {
  accountId: string;
  codeNumber: number;
  accountName: string;
  category: AccountRecord["category"];
  openingNet?: number;
  debitTurnover: number;
  creditTurnover: number;
  closingDebit: number;
  closingCredit: number;
};

export type TrialBalanceReport = {
  rows: TrialBalanceRow[];
  totalDebitTurnover: number;
  totalCreditTurnover: number;
  totalClosingDebit: number;
  totalClosingCredit: number;
  netDifference: number;
  scope?: FinancialScopeMetadata;
};

export type IncomeStatementReport = {
  salesRevenue: number;
  salesReturns: number;
  netSales: number;
  cogs: number;
  grossProfit: number;
  grossMarginPct: number;
  expensesByCategory: { category: ExpenseCategory; amount: number }[];
  totalOperatingExpenses: number;
  netProfit: number;
  includesOpeningSales?: boolean;
  scope?: FinancialScopeMetadata;
};

export type BalanceSheetReport = {
  cashAndBank: number;
  accountsReceivable: number;
  inventoryValue: number;
  totalAssets: number;
  accountsPayable: number;
  payrollPayable: number;
  totalLiabilities: number;
  ownerEquityBase: number;
  currentPeriodProfit: number;
  totalEquity: number;
  totalLiabilitiesAndEquity: number;
  cashReconciliation?: CashReconciliationSummary;
  inventoryReconciliation?: InventoryReconciliationSummary;
  scope?: FinancialScopeMetadata;
};

export type VatSummaryReport = {
  vatRate: number;
  vatMode?: "recorded_only" | "estimated_gross";
  jurisdictionCode?: ErpVatJurisdiction;
  jurisdictionLabel?: string;
  taxableSales: number;
  outputVat: number;
  taxablePurchases: number;
  inputVat: number;
  netVatPayable: number;
  recordedOutputVat?: number;
  recordedInputVat?: number;
  entriesWithRecordedTaxCount?: number;
  scope?: FinancialScopeMetadata;
};

function round2(n: number): number {
  return Math.round(n * 100) / 100;
}

function entryMatchesCurrency(entry: LedgerEntryRecord, currency?: string): boolean {
  if (!currency || currency === "الكل") return true;
  return entry.currency === currency;
}

function entryAmountInCurrency(entry: LedgerEntryRecord, currency?: string): number {
  if (!currency || currency === "الكل") {
    return entry.amount * (entry.exchangeRate || 1);
  }
  return entry.amount;
}

function collectEntryScope(
  entries: readonly LedgerEntryRecord[],
  options?: FinancialReportScopeOptions,
): {
  matched: LedgerEntryRecord[];
  scope: FinancialScopeMetadata;
} {
  const effectiveCurrency = options?.currency?.trim() || "الكل";
  const fromDate = options?.fromDate?.trim() || "";
  const toDate = options?.toDate?.trim() || "";

  let excludedByCurrencyCount = 0;
  let excludedByDateCount = 0;
  let earliestEntryDate: string | null = null;
  let latestEntryDate: string | null = null;
  const matched: LedgerEntryRecord[] = [];

  for (const e of entries) {
    if (e.deleted) continue;
    if (!entryMatchesCurrency(e, effectiveCurrency)) {
      excludedByCurrencyCount += 1;
      continue;
    }
    if ((fromDate && e.entryDate < fromDate) || (toDate && e.entryDate > toDate)) {
      excludedByDateCount += 1;
      continue;
    }
    matched.push(e);
    if (e.entryDate) {
      if (!earliestEntryDate || e.entryDate < earliestEntryDate) earliestEntryDate = e.entryDate;
      if (!latestEntryDate || e.entryDate > latestEntryDate) latestEntryDate = e.entryDate;
    }
  }

  return {
    matched,
    scope: {
      effectiveCurrency,
      fromDate: fromDate || null,
      toDate: toDate || null,
      matchedEntriesCount: matched.length,
      excludedByCurrencyCount,
      excludedByDateCount,
      earliestEntryDate,
      latestEntryDate,
    },
  };
}

function isCashInflowEvent(entry: LedgerEntryRecord): boolean {
  if (entry.kind === "voucher" || entry.kind === "transfer" || entry.kind === "simple-entry") {
    return entry.direction === "credit";
  }
  if (entry.docType === 2 || entry.docType === 7 || entry.docType === 5) return true;
  if (entry.docType === 3 || entry.docType === 9 || entry.docType === 4) return false;
  return entry.direction === "debit";
}

export function computeCashReconciliation(
  accounts: readonly AccountRecord[],
  entries: readonly LedgerEntryRecord[],
  cashboxes: readonly CashboxRecord[],
  options?: FinancialReportScopeOptions,
): CashReconciliationSummary {
  const effectiveCurrency = options?.currency?.trim() || "الكل";
  const fromDate = options?.fromDate?.trim() || "";
  const toDate = options?.toDate?.trim() || "";

  const boxBuckets = new Map<number, CashboxBreakdownItem>();
  for (const cb of cashboxes) {
    boxBuckets.set(cb.id, {
      id: cb.id,
      name: cb.name,
      currencyCode: cb.currencyCode,
      isActive: cb.isActive ?? (cb.state ?? 1) === 1,
      totalIn: 0,
      totalOut: 0,
      netBalance: 0,
      entryCount: 0,
    });
  }

  let unassignedCashIn = 0;
  let unassignedCashOut = 0;
  let unassignedCashCount = 0;

  for (const e of entries) {
    if (e.deleted || !affectsAccountBalance(e)) continue;
    if (!entryMatchesCurrency(e, effectiveCurrency)) continue;
    if (fromDate && e.entryDate < fromDate) continue;
    if (toDate && e.entryDate > toDate) continue;

    const isCashSettlement = Boolean(e.settledOnReceipt || e.payment === "cash");
    if (!isCashSettlement) continue;

    const amt = entryAmountInCurrency(e, effectiveCurrency);
    const inflow = isCashInflowEvent(e);

    if (typeof e.cashboxId === "number") {
      const bucket = boxBuckets.get(e.cashboxId) ?? {
        id: e.cashboxId,
        name: `صندوق #${e.cashboxId}`,
        currencyCode: e.currency,
        isActive: false,
        totalIn: 0,
        totalOut: 0,
        netBalance: 0,
        entryCount: 0,
      };
      if (inflow) bucket.totalIn += amt;
      else bucket.totalOut += amt;
      bucket.entryCount += 1;
      bucket.netBalance = round2(bucket.totalIn - bucket.totalOut);
      boxBuckets.set(e.cashboxId, bucket);
    } else {
      if (inflow) unassignedCashIn += amt;
      else unassignedCashOut += amt;
      unassignedCashCount += 1;
    }
  }

  const linkedCashboxes = [...boxBuckets.values()].map((b) => ({
    ...b,
    totalIn: round2(b.totalIn),
    totalOut: round2(b.totalOut),
    netBalance: round2(b.totalIn - b.totalOut),
  }));
  const linkedCashboxesNet = round2(linkedCashboxes.reduce((sum, b) => sum + b.netBalance, 0));
  const unassignedCashNet = round2(unassignedCashIn - unassignedCashOut);
  const totalCashFlowNet = round2(linkedCashboxesNet + unassignedCashNet);

  // Legacy cash balance derived purely from chart-of-accounts flags (`isCashAccount` / `transfers`)
  const pointEntries = entries.filter((e) => {
    if (e.deleted) return false;
    if (!entryMatchesCurrency(e, effectiveCurrency)) return false;
    if (toDate && e.entryDate > toDate) return false;
    return true;
  });
  const summaryCurrency = effectiveCurrency === "الكل" ? undefined : effectiveCurrency;
  let ledgerCashAccountsNet = 0;
  for (const acc of accounts) {
    if (!acc.isCashAccount && acc.category !== "transfers") continue;
    const summary = computeAccountSummary(acc, pointEntries, summaryCurrency);
    const netSigned = summary.creditTotal - summary.debitTotal;
    ledgerCashAccountsNet += Math.abs(netSigned) > 0 ? Math.abs(netSigned) : summary.creditTotal;
  }
  ledgerCashAccountsNet = round2(ledgerCashAccountsNet);

  return {
    linkedCashboxes,
    linkedCashboxesNet,
    unassignedCashIn: round2(unassignedCashIn),
    unassignedCashOut: round2(unassignedCashOut),
    unassignedCashNet,
    unassignedCashCount,
    totalCashFlowNet,
    ledgerCashAccountsNet,
    differenceVsLedgerAccounts: round2(totalCashFlowNet - ledgerCashAccountsNet),
    differenceVsCashboxesReport: unassignedCashNet,
  };
}

export function computeTrialBalance(
  accounts: readonly AccountRecord[],
  entries: readonly LedgerEntryRecord[],
  options?: FinancialReportScopeOptions,
): TrialBalanceReport {
  const effectiveCurrency = options?.currency?.trim() || "الكل";
  const fromDate = options?.fromDate?.trim() || "";
  const toDate = options?.toDate?.trim() || "";
  const summaryCurrency = effectiveCurrency === "الكل" ? undefined : effectiveCurrency;
  const hasScope = Boolean(options && (options.currency || options.fromDate || options.toDate));

  const { matched: rangeEntries, scope } = collectEntryScope(entries, options);
  const priorEntries = fromDate
    ? entries.filter(
        (e) => !e.deleted && entryMatchesCurrency(e, effectiveCurrency) && e.entryDate < fromDate,
      )
    : [];
  const upToEntries = toDate
    ? entries.filter(
        (e) => !e.deleted && entryMatchesCurrency(e, effectiveCurrency) && e.entryDate <= toDate,
      )
    : entries.filter((e) => !e.deleted && entryMatchesCurrency(e, effectiveCurrency));

  const rows: TrialBalanceRow[] = [];
  let totalDebitTurnover = 0;
  let totalCreditTurnover = 0;
  let totalClosingDebit = 0;
  let totalClosingCredit = 0;

  for (const account of accounts) {
    const closingSummary = hasScope
      ? computeAccountSummary(account, upToEntries, summaryCurrency)
      : computeAccountSummary(account, entries);
    const turnoverSummary = hasScope && fromDate
      ? computeAccountSummary({ ...account, openingBalance: 0 }, rangeEntries, summaryCurrency)
      : closingSummary;
    const priorSummary = fromDate
      ? computeAccountSummary(account, priorEntries, summaryCurrency)
      : null;

    const netSigned = closingSummary.creditTotal - closingSummary.debitTotal;
    const closingDebit = netSigned < 0 ? Math.abs(netSigned) : 0;
    const closingCredit = netSigned > 0 ? netSigned : 0;

    rows.push({
      accountId: account.id,
      codeNumber: account.codeNumber,
      accountName: account.name,
      category: account.category,
      ...(priorSummary ? { openingNet: priorSummary.creditTotal - priorSummary.debitTotal } : {}),
      debitTurnover: turnoverSummary.debitTotal,
      creditTurnover: turnoverSummary.creditTotal,
      closingDebit,
      closingCredit,
    });

    totalDebitTurnover += turnoverSummary.debitTotal;
    totalCreditTurnover += turnoverSummary.creditTotal;
    totalClosingDebit += closingDebit;
    totalClosingCredit += closingCredit;
  }

  return {
    rows,
    totalDebitTurnover,
    totalCreditTurnover,
    totalClosingDebit,
    totalClosingCredit,
    netDifference: Math.abs(totalClosingDebit - totalClosingCredit),
    scope,
  };
}

export function computeIncomeStatement(
  accounts: readonly AccountRecord[],
  entries: readonly LedgerEntryRecord[],
  options?: FinancialReportScopeOptions,
): IncomeStatementReport {
  const effectiveCurrency = options?.currency?.trim() || "الكل";
  const fromDate = options?.fromDate?.trim() || "";
  const { matched: scopedEntries, scope } = collectEntryScope(entries, options);
  const accountMap = new Map(accounts.map((a) => [a.id, a]));
  const salesIds = new Set(accounts.filter((a) => a.category === "sales").map((a) => a.id));

  let salesRevenue = 0;
  let salesReturns = 0;
  let cogs = 0;
  const expenseBuckets = new Map<ExpenseCategory, number>();
  for (const cat of EXPENSE_CATEGORIES) {
    expenseBuckets.set(cat, 0);
  }

  let includesOpeningSales = false;
  if (!fromDate) {
    for (const acc of accounts) {
      if (
        acc.category === "sales" &&
        acc.openingBalance > 0 &&
        (effectiveCurrency === "الكل" || acc.currency === effectiveCurrency)
      ) {
        salesRevenue += acc.openingBalance;
        includesOpeningSales = true;
      }
    }
  }

  for (const entry of scopedEntries) {
    if (entry.deleted) continue;
    if (entry.kind === "quote" || entry.kind === "order") continue;

    const amount = entryAmountInCurrency(entry, effectiveCurrency);
    if (amount <= 0) continue;

    const acc = accountMap.get(entry.accountId);
    const isSale =
      salesIds.has(entry.accountId) ||
      (entry.kind === "invoice" && entry.direction === "debit");

    if (isSale) {
      if (entry.kind === "return") {
        salesReturns += amount;
      } else {
        salesRevenue += amount;
      }
      continue;
    }

    const explicitCategory = normalizeExpenseCategory(entry.expenseCategory);
    const inferred =
      explicitCategory ?? inferExpenseCategory(entry.details, entry.accountName, acc?.category);

    const isPurchaseCogs =
      inferred === "مشتريات بضائع" &&
      (acc?.category === "purchases" || (entry.kind === "invoice" && entry.direction === "credit"));

    if (isPurchaseCogs) {
      if (entry.kind === "return") {
        cogs = Math.max(0, cogs - amount);
      } else {
        cogs += amount;
      }
      continue;
    }

    const isOperatingExpense =
      acc?.category === "shop" ||
      acc?.category === "employees" ||
      Boolean(explicitCategory) ||
      (entry.kind === "voucher" && entry.direction === "debit");

    if (isOperatingExpense && inferred !== "مشتريات بضائع") {
      expenseBuckets.set(inferred, (expenseBuckets.get(inferred) ?? 0) + amount);
    }
  }

  const netSales = Math.max(0, salesRevenue - salesReturns);
  const grossProfit = netSales - cogs;
  const grossMarginPct = netSales > 0 ? Math.round((grossProfit / netSales) * 1000) / 10 : 0;

  const expensesByCategory = Array.from(expenseBuckets.entries())
    .filter(([, amount]) => amount > 0)
    .map(([category, amount]) => ({ category, amount }))
    .sort((a, b) => b.amount - a.amount);

  const totalOperatingExpenses = expensesByCategory.reduce((sum, item) => sum + item.amount, 0);
  const netProfit = grossProfit - totalOperatingExpenses;

  return {
    salesRevenue,
    salesReturns,
    netSales,
    cogs,
    grossProfit,
    grossMarginPct,
    expensesByCategory,
    totalOperatingExpenses,
    netProfit,
    includesOpeningSales,
    scope,
  };
}

export function computeBalanceSheet(
  accounts: readonly AccountRecord[],
  entries: readonly LedgerEntryRecord[],
  inventory: readonly InventoryItemRecord[],
  options?: FinancialReportScopeOptions & {
    cashboxes?: readonly CashboxRecord[];
    useUnifiedCash?: boolean;
    includeUnverifiedInventory?: boolean;
    estimatedInventoryReportValue?: number;
  },
): BalanceSheetReport {
  const effectiveCurrency = options?.currency?.trim() || "الكل";
  const toDate = options?.toDate?.trim() || "";
  const summaryCurrency = effectiveCurrency === "الكل" ? undefined : effectiveCurrency;
  const hasExplicitScope = Boolean(
    options && (options.currency || options.fromDate || options.toDate || options.cashboxes || options.useUnifiedCash),
  );

  // Balance sheet balances are always point-in-time up to `toDate`
  const pointEntries = hasExplicitScope
    ? entries.filter((e) => !e.deleted && entryMatchesCurrency(e, effectiveCurrency) && (!toDate || e.entryDate <= toDate))
    : entries;

  const invSummary = computeInventorySummary(inventory);
  let fallbackUnverifiedEstimated = 0;
  for (const item of inventory) {
    if (!item.quantityUnverified) continue;
    const qty = item.computedQuantity ?? 0;
    if (qty > 0 && item.avgCost > 0) {
      fallbackUnverifiedEstimated += qty * item.avgCost;
    }
  }
  const unverifiedEstimatedValue =
    typeof options?.estimatedInventoryReportValue === "number" && Number.isFinite(options.estimatedInventoryReportValue)
      ? round2(options.estimatedInventoryReportValue)
      : round2(fallbackUnverifiedEstimated);

  const income = computeIncomeStatement(accounts, entries, options);
  const cashReconciliation = computeCashReconciliation(accounts, entries, options?.cashboxes ?? [], {
    currency: options?.currency,
    toDate: options?.toDate,
  });

  let cashAndBank = 0;
  let accountsReceivable = 0;
  let accountsPayable = 0;
  let payrollPayable = 0;

  for (const acc of accounts) {
    const summary = hasExplicitScope
      ? computeAccountSummary(acc, pointEntries, summaryCurrency)
      : computeAccountSummary(acc, entries);
    const netSigned = summary.creditTotal - summary.debitTotal;

    if (acc.isCashAccount || acc.category === "transfers") {
      cashAndBank += Math.abs(netSigned) > 0 ? Math.abs(netSigned) : summary.creditTotal;
    } else if (acc.category === "clients") {
      if (netSigned < 0) {
        accountsReceivable += Math.abs(netSigned);
      } else if (netSigned > 0) {
        accountsPayable += netSigned;
      }
    } else if (acc.category === "purchases") {
      if (netSigned > 0) {
        accountsPayable += netSigned;
      } else if (netSigned < 0) {
        accountsReceivable += Math.abs(netSigned);
      }
    } else if (acc.category === "employees") {
      if (netSigned > 0) {
        payrollPayable += netSigned;
      }
    }
  }

  if (options?.useUnifiedCash) {
    cashAndBank = cashReconciliation.totalCashFlowNet;
  }

  const activeInventoryBasis = options?.includeUnverifiedInventory
    ? "include_unverified_estimated"
    : "verified_only";
  const inventoryValue =
    activeInventoryBasis === "include_unverified_estimated"
      ? round2(invSummary.totalValue + unverifiedEstimatedValue)
      : round2(invSummary.totalValue);

  const inventoryReportTotalValue = round2(invSummary.totalValue + unverifiedEstimatedValue);
  const inventoryReconciliation: InventoryReconciliationSummary = {
    verifiedCount: invSummary.verifiedCount,
    verifiedValue: round2(invSummary.totalValue),
    unverifiedCount: invSummary.unverifiedCount,
    unverifiedEstimatedValue,
    inventoryReportTotalValue,
    activeBasis: activeInventoryBasis,
    differenceVsInventoryReport: round2(inventoryReportTotalValue - inventoryValue),
  };

  const totalAssets = round2(cashAndBank + accountsReceivable + inventoryValue);
  const totalLiabilities = round2(accountsPayable + payrollPayable);
  const currentPeriodProfit = income.netProfit;
  const ownerEquityBase = round2(totalAssets - totalLiabilities - currentPeriodProfit);
  const totalEquity = round2(ownerEquityBase + currentPeriodProfit);

  const { scope } = collectEntryScope(entries, {
    currency: options?.currency,
    toDate: options?.toDate,
  });

  return {
    cashAndBank: round2(cashAndBank),
    accountsReceivable: round2(accountsReceivable),
    inventoryValue,
    totalAssets,
    accountsPayable: round2(accountsPayable),
    payrollPayable: round2(payrollPayable),
    totalLiabilities,
    ownerEquityBase,
    currentPeriodProfit,
    totalEquity,
    totalLiabilitiesAndEquity: round2(totalLiabilities + totalEquity),
    cashReconciliation,
    inventoryReconciliation,
    scope,
  };
}

export function computeVatSummary(
  accounts: readonly AccountRecord[],
  entries: readonly LedgerEntryRecord[],
  vatRate: number = 0.15,
  options?: FinancialReportScopeOptions & {
    vatMode?: "recorded_only" | "estimated_gross";
    jurisdictionCode?: ErpVatJurisdiction;
    jurisdictionLabel?: string;
  },
): VatSummaryReport {
  const effectiveCurrency = options?.currency?.trim() || "الكل";
  const { matched: scopedEntries, scope } = collectEntryScope(entries, options);
  const accountMap = new Map(accounts.map((a) => [a.id, a]));
  let taxableSales = 0;
  let taxablePurchases = 0;
  let recordedOutputVat = 0;
  let recordedInputVat = 0;
  let entriesWithRecordedTaxCount = 0;

  for (const entry of scopedEntries) {
    if (entry.deleted) continue;
    if (entry.kind !== "invoice" && entry.kind !== "return") continue;
    const amount = entryAmountInCurrency(entry, effectiveCurrency);
    const acc = accountMap.get(entry.accountId);
    const isSale = acc?.category === "sales" || entry.direction === "debit";
    const recordedTax = Number(entry.taxAmount ?? 0) * (!options?.currency || options.currency === "الكل" ? (entry.exchangeRate || 1) : 1);
    if (recordedTax > 0) entriesWithRecordedTaxCount += 1;

    if (isSale) {
      taxableSales += entry.kind === "return" ? -amount : amount;
      recordedOutputVat += entry.kind === "return" ? -recordedTax : recordedTax;
    } else {
      taxablePurchases += entry.kind === "return" ? -amount : amount;
      recordedInputVat += entry.kind === "return" ? -recordedTax : recordedTax;
    }
  }

  taxableSales = Math.max(0, taxableSales);
  taxablePurchases = Math.max(0, taxablePurchases);
  recordedOutputVat = Math.max(0, round2(recordedOutputVat));
  recordedInputVat = Math.max(0, round2(recordedInputVat));

  const vatMode = options?.vatMode ?? "estimated_gross";
  const outputVat = vatMode === "recorded_only" ? recordedOutputVat : round2(taxableSales * vatRate);
  const inputVat = vatMode === "recorded_only" ? recordedInputVat : round2(taxablePurchases * vatRate);

  return {
    vatRate,
    vatMode,
    jurisdictionCode: options?.jurisdictionCode ?? (vatRate === 0 ? "none" : "custom"),
    jurisdictionLabel: options?.jurisdictionLabel,
    taxableSales,
    outputVat,
    taxablePurchases,
    inputVat,
    netVatPayable: round2(outputVat - inputVat),
    recordedOutputVat,
    recordedInputVat,
    entriesWithRecordedTaxCount,
    scope,
  };
}

export function computeEmployeeNetSalary(emp: Pick<ErpEmployeeProfile, "basicSalary" | "allowances" | "deductions">): number {
  return Math.max(0, (emp.basicSalary || 0) + (emp.allowances || 0) - (emp.deductions || 0));
}

export function computePayrollTotals(employees: readonly ErpEmployeeProfile[]): {
  activeCount: number;
  totalBasic: number;
  totalAllowances: number;
  totalDeductions: number;
  totalNetPayroll: number;
} {
  let activeCount = 0;
  let totalBasic = 0;
  let totalAllowances = 0;
  let totalDeductions = 0;
  let totalNetPayroll = 0;

  for (const emp of employees) {
    if (emp.status === "inactive") continue;
    activeCount += 1;
    totalBasic += Math.max(0, emp.basicSalary);
    totalAllowances += Math.max(0, emp.allowances);
    totalDeductions += Math.max(0, emp.deductions);
    totalNetPayroll += computeEmployeeNetSalary(emp);
  }

  return {
    activeCount,
    totalBasic,
    totalAllowances,
    totalDeductions,
    totalNetPayroll,
  };
}

export function computePurchaseOrderTotal(po: Pick<ErpPurchaseOrder, "lines">): number {
  return po.lines.reduce(
    (sum, line) => sum + Math.max(0, line.quantity) * Math.max(0, line.unitCost),
    0,
  );
}

export function computeWeightedAvgCost(
  currentQty: number,
  currentAvgCost: number,
  receivedQty: number,
  unitCost: number,
): { newQty: number; newAvgCost: number } {
  const safeCurQty = Math.max(0, currentQty);
  const safeRecQty = Math.max(0, receivedQty);
  const newQty = safeCurQty + safeRecQty;
  if (newQty <= 0) {
    return { newQty: 0, newAvgCost: Math.max(0, unitCost || currentAvgCost) };
  }
  const totalCost = safeCurQty * Math.max(0, currentAvgCost) + safeRecQty * Math.max(0, unitCost);
  return {
    newQty,
    newAvgCost: Math.round((totalCost / newQty) * 100) / 100,
  };
}

export function computeBomAvailability(
  bom: ErpBomRecipe,
  quantityToProduce: number,
  inventory: readonly InventoryItemRecord[],
): {
  canProduce: boolean;
  estimatedUnitCost: number;
  totalEstimatedCost: number;
  shortages: { itemName: string; required: number; available: number; unit: string }[];
} {
  const invMap = new Map(inventory.map((i) => [i.id, i]));
  const qty = Math.max(1, quantityToProduce);
  const shortages: { itemName: string; required: number; available: number; unit: string }[] = [];
  let estimatedUnitCost = 0;

  for (const comp of bom.components) {
    const item = invMap.get(comp.inventoryItemId);
    const available = item?.quantity ?? 0;
    const required = comp.quantityPerUnit * qty;
    estimatedUnitCost += comp.quantityPerUnit * (item?.avgCost ?? 0);
    if (available < required) {
      shortages.push({
        itemName: comp.itemName,
        required,
        available,
        unit: comp.unit,
      });
    }
  }

  return {
    canProduce: shortages.length === 0,
    estimatedUnitCost: Math.round(estimatedUnitCost * 100) / 100,
    totalEstimatedCost: Math.round(estimatedUnitCost * qty * 100) / 100,
    shortages,
  };
}

export function computeCostCenterMetrics(
  costCenters: readonly ErpCostCenter[],
  accounts: readonly AccountRecord[],
  entries: readonly LedgerEntryRecord[],
): (ErpCostCenter & { actualSpend: number; remaining: number; utilizationPct: number })[] {
  const accountMap = new Map(accounts.map((a) => [a.id, a]));
  const categorySpend = new Map<ExpenseCategory, number>();
  for (const entry of entries) {
    if (entry.deleted || entry.kind === "quote" || entry.kind === "order" || entry.kind === "return") continue;
    const acc = accountMap.get(entry.accountId);
    const cat =
      normalizeExpenseCategory(entry.expenseCategory) ??
      inferExpenseCategory(entry.details, entry.accountName, acc?.category);
    categorySpend.set(cat, (categorySpend.get(cat) ?? 0) + entry.amount * (entry.exchangeRate || 1));
  }

  return costCenters.map((cc) => {
    const ledgerSpend = cc.linkedCategories.reduce((s, c) => s + (categorySpend.get(c) ?? 0), 0);
    const actualSpend = ledgerSpend + Math.max(0, cc.extraPostedSpend || 0);
    const remaining = cc.budget - actualSpend;
    const utilizationPct = cc.budget > 0 ? Math.min(200, Math.round((actualSpend / cc.budget) * 100)) : 0;
    return {
      ...cc,
      actualSpend,
      remaining,
      utilizationPct,
    };
  });
}

export function createDefaultErpData(todayIso: string = new Date().toISOString().slice(0, 10)): ErpWorkspaceData {
  return {
    employees: [
      {
        id: "emp_1",
        accountId: "acc_emp_1",
        name: "أحمد السالم",
        roleTitle: "مدير مبيعات وفروع",
        department: "المبيعات",
        basicSalary: 6500,
        allowances: 1200,
        deductions: 0,
        status: "active",
        hireDate: "2024-03-01",
        leaveBalanceDays: 18,
        attendanceToday: "present",
      },
      {
        id: "emp_2",
        name: "سارة القحطاني",
        roleTitle: "محاسبة مالية رئيسية",
        department: "المالية",
        basicSalary: 5800,
        allowances: 900,
        deductions: 200,
        status: "active",
        hireDate: "2024-07-15",
        leaveBalanceDays: 21,
        attendanceToday: "present",
      },
      {
        id: "emp_3",
        name: "خالد الحربي",
        roleTitle: "أمين مستودع ومشتريات",
        department: "المخازن وسلسلة التوريد",
        basicSalary: 4500,
        allowances: 750,
        deductions: 0,
        status: "active",
        hireDate: "2025-01-10",
        leaveBalanceDays: 14,
        attendanceToday: "present",
      },
    ],
    leaveRequests: [
      {
        id: "lv_1",
        employeeId: "emp_3",
        employeeName: "خالد الحربي",
        leaveType: "سنوية",
        startDate: todayIso,
        days: 3,
        status: "pending",
        note: "إجازة عائلية قصيرة",
      },
    ],
    deals: [
      {
        id: "deal_1",
        title: "توريد تجهيزات إنارة ذكية — معرض الشمال",
        clientAccountId: "acc_sales_1",
        clientName: "المبيعات العامة",
        value: 42000,
        currency: "ريال",
        stage: "negotiation",
        probability: 75,
        expectedCloseDate: todayIso,
        assignedTo: "أحمد السالم",
      },
      {
        id: "deal_2",
        title: "عقد صيانة وتوريد مستلزمات مكتبية سنوي",
        clientAccountId: "acc_sales_1",
        clientName: "المبيعات العامة",
        value: 28500,
        currency: "ريال",
        stage: "proposal",
        probability: 50,
        expectedCloseDate: todayIso,
        assignedTo: "أحمد السالم",
      },
    ],
    purchaseOrders: [
      {
        id: "po_101",
        poNumber: "PO-2026-101",
        supplierAccountId: "acc_barari",
        supplierName: "البراري للتوريد",
        warehouseId: "wh_1",
        warehouseName: "المخزن الرئيسي",
        currency: "ريال",
        orderDate: todayIso,
        expectedDate: todayIso,
        status: "approved",
        lines: [
          {
            inventoryItemId: "inv_2",
            itemName: "توصيلة تايب سي 2 متر",
            unit: "حبة",
            quantity: 20,
            unitCost: 1450,
          },
          {
            inventoryItemId: "inv_3",
            itemName: "بطارية جهاز كشف الذهب",
            unit: "حبة",
            quantity: 10,
            unitCost: 1500,
          },
        ],
        notes: "توريد لتعويض المخزون المنخفض",
      },
    ],
    boms: [
      {
        id: "bom_1",
        name: "طقم تجهيز إضاءة وطاقة محمول",
        finishedItemId: "inv_1",
        finishedItemName: "ابجورة شكل قمر",
        finishedUnit: "حبة",
        components: [
          {
            inventoryItemId: "inv_2",
            itemName: "توصيلة تايب سي 2 متر",
            unit: "حبة",
            quantityPerUnit: 1,
          },
          {
            inventoryItemId: "inv_3",
            itemName: "بطارية جهاز كشف الذهب",
            unit: "حبة",
            quantityPerUnit: 1,
          },
        ],
      },
    ],
    productionOrders: [
      {
        id: "mfg_1",
        orderNumber: "MFG-01",
        bomId: "bom_1",
        bomName: "طقم تجهيز إضاءة وطاقة محمول",
        finishedItemId: "inv_1",
        finishedItemName: "ابجورة شكل قمر",
        quantityToProduce: 5,
        warehouseId: "wh_1",
        status: "planned",
        createdDate: todayIso,
        costCenterId: "cc_ops",
      },
    ],
    costCenters: [
      {
        id: "cc_ops",
        code: "CC-100",
        name: "مركز تشغيل الفروع والمخازن",
        managerName: "خالد الحربي",
        budget: 95000,
        extraPostedSpend: 0,
        linkedCategories: ["مصروفات تشغيلية", "صيانة ومرافق", "شحن ونقل"],
        status: "active",
      },
      {
        id: "cc_hr",
        code: "CC-200",
        name: "مركز الرواتب والموارد البشرية",
        managerName: "سارة القحطاني",
        budget: 60000,
        extraPostedSpend: 0,
        linkedCategories: ["رواتب وأجور"],
        status: "active",
      },
      {
        id: "cc_sales",
        code: "CC-300",
        name: "مركز المبيعات والتسويق",
        managerName: "أحمد السالم",
        budget: 45000,
        extraPostedSpend: 0,
        linkedCategories: ["تسويق ومبيعات"],
        status: "active",
      },
    ],
  };
}

export function createEmptyErpData(): ErpWorkspaceData {
  return {
    employees: [],
    leaveRequests: [],
    deals: [],
    purchaseOrders: [],
    boms: [],
    productionOrders: [],
    costCenters: [],
  };
}

const erpMemoryCache = new Map<string, ErpWorkspaceData>();
const erpListeners = new Set<(data: ErpWorkspaceData) => void>();

export function hydrateErpWorkspaceCache(uid: string, data: ErpWorkspaceData): void {
  const key = uid || "local-erp-workspace";
  erpMemoryCache.set(key, data);
  for (const listener of erpListeners) {
    listener(data);
  }
}

export function subscribeErpCache(listener: (data: ErpWorkspaceData) => void): () => void {
  erpListeners.add(listener);
  return () => {
    erpListeners.delete(listener);
  };
}

export function loadErpWorkspaceData(uid: string): ErpWorkspaceData {
  const key = uid || "local-erp-workspace";
  return erpMemoryCache.get(key) ?? erpMemoryCache.get("local-erp-workspace") ?? createEmptyErpData();
}

export function saveErpWorkspaceData(uid: string, data: ErpWorkspaceData): void {
  const key = uid || "local-erp-workspace";
  erpMemoryCache.set(key, data);
  for (const listener of erpListeners) {
    listener(data);
  }
  if (typeof window === "undefined") return;
  const win = window as unknown as {
    __nasqoHybridReady?: boolean;
    __nasqoHybridSaveErp?: (workspaceId: string, erpData: ErpWorkspaceData) => void;
  };
  if (import.meta.env.VITE_NASQO_HYBRID === "1" || win.__nasqoHybridReady) {
    win.__nasqoHybridSaveErp?.(key, data);
    return;
  }
  if (import.meta.env.VITE_NASQO_HYBRID !== "1") {
    try {
      const viteBase = (import.meta as { env?: { BASE_URL?: string } }).env?.BASE_URL || "/";
      const base = new URL("api/db/workspace/", new URL(viteBase, window.location.origin)).pathname;
      const ctrl = new AbortController();
      const timer = globalThis.setTimeout(() => ctrl.abort(), 12_000);
      void fetch(`${base}local-erp-workspace/erp`, {
        method: "PUT",
        signal: ctrl.signal,
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(data),
      })
        .catch(() => {})
        .finally(() => globalThis.clearTimeout(timer));
    } catch {
      // Ignore non-browser test environments
    }
  }
}

export function formatErpCurrency(amount: number, currency: CurrencyCode | string = "ريال"): string {
  return `${formatAmount(amount)} ${currency}`;
}

export function parsePositiveNumber(raw: string | number): number {
  return Math.max(0, parseArabicNumber(raw));
}
