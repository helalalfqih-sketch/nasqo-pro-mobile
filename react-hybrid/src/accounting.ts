import {
  ACCOUNT_CATEGORIES,
  CURRENCIES,
  EXPENSE_CATEGORIES,
  LEDGER_KINDS,
  SCHEMA_LIMITS,
  type AccountCategory,
  type AccountGroupRecord,
  type AccountRecord,
  type CashboxRecord,
  type CurrencyCode,
  type ExpenseCategory,
  type InventoryItemRecord,
  type LedgerEntryRecord,
  type LedgerKind,
  type StatementRowWithBalance,
  type WarehouseRecord,
  type WorkspaceSettings,
} from "./types.ts";

const ARABIC_INDIC = "٠١٢٣٤٥٦٧٨٩";
const PERSIAN_INDIC = "۰۱۲۳۴۵۶۷۸۹";

export function parseArabicNumber(raw: string | number | null | undefined): number {
  if (typeof raw === "number") {
    return Number.isFinite(raw) ? raw : 0;
  }
  if (!raw) return 0;
  const ascii = String(raw)
    .replace(/[٠-٩]/g, (d) => String(ARABIC_INDIC.indexOf(d)))
    .replace(/[۰-۹]/g, (d) => String(PERSIAN_INDIC.indexOf(d)))
    .replace(/[,٬\s]/g, "")
    .replace(/٫/g, ".");
  const parsed = Number(ascii);
  return Number.isFinite(parsed) ? parsed : 0;
}

export function formatAmount(value: number): string {
  const safe = Number.isFinite(value) ? value : 0;
  const rounded = Math.round(safe * 100) / 100;
  return new Intl.NumberFormat("en-US", {
    maximumFractionDigits: 2,
  }).format(rounded);
}

export function normalizeArabicSearch(text: string): string {
  return String(text ?? "")
    .replace(/[\u064B-\u065F\u0670]/g, "")
    .replace(/[أإآٱ]/g, "ا")
    .replace(/ة/g, "ه")
    .replace(/ى/g, "ي")
    .replace(/ؤ/g, "و")
    .replace(/ئ/g, "ي")
    .replace(/[ـ,٬]/g, "")
    .replace(/[٠-٩]/g, (d) => String(ARABIC_INDIC.indexOf(d)))
    .replace(/[۰-۹]/g, (d) => String(PERSIAN_INDIC.indexOf(d)))
    .replace(/\s+/g, " ")
    .toLocaleLowerCase()
    .trim();
}

export function matchesArabicSearch(haystack: string, query: string): boolean {
  const normQuery = normalizeArabicSearch(query);
  if (!normQuery) return true;
  const normHaystack = normalizeArabicSearch(haystack);
  const tokens = normQuery.split(" ").filter(Boolean);
  return tokens.every((token) => {
    if (normHaystack.includes(token)) return true;
    if (token.startsWith("ال") && token.length > 2 && normHaystack.includes(token.slice(2))) return true;
    if (!token.startsWith("ال") && normHaystack.includes("ال" + token)) return true;
    return false;
  });
}

export function clampString(value: string, max: number): string {
  const trimmed = String(value ?? "").trim();
  return trimmed.length > max ? trimmed.slice(0, max) : trimmed;
}

export function isValidCurrency(val: string): val is CurrencyCode {
  const clean = String(val ?? "").trim();
  return clean.length >= 1 && clean.length <= 32 && !/[\r\n\t<>]/.test(clean);
}

export function isValidCategory(val: string): val is AccountCategory {
  return (ACCOUNT_CATEGORIES as readonly string[]).includes(val);
}

export function isValidLedgerKind(val: string): val is LedgerKind {
  return (LEDGER_KINDS as readonly string[]).includes(val);
}

export function sanitizeWorkspacePayload(input: Partial<WorkspaceSettings> & { ownerId: string }) {
  return {
    ownerId: clampString(input.ownerId, SCHEMA_LIMITS.ownerIdMax),
    companyName: clampString(input.companyName || "نسقو برو", SCHEMA_LIMITS.companyNameMax) || "نسقو برو",
    defaultCurrency: isValidCurrency(input.defaultCurrency ?? "") ? input.defaultCurrency! : ("ريال" as const),
    whatsappProvider: (input.whatsappProvider === "external" ? "external" : "nasqo") as "external" | "nasqo",
    whatsappInstantEnabled: Boolean(input.whatsappInstantEnabled),
    whatsappPhone: clampString(input.whatsappPhone ?? "", SCHEMA_LIMITS.phoneMax),
  };
}

export function sanitizeAccountPayload(input: Partial<AccountRecord> & { ownerId: string; name: string }) {
  const safeOpening = Math.max(0, parseArabicNumber(input.openingBalance));
  const safeLimit = Math.max(0, parseArabicNumber(input.creditLimit));
  return {
    ownerId: clampString(input.ownerId, SCHEMA_LIMITS.ownerIdMax),
    name: clampString(input.name, SCHEMA_LIMITS.accountNameMax),
    category: isValidCategory(input.category ?? "") ? input.category! : ("purchases" as const),
    phone: clampString(input.phone ?? "", SCHEMA_LIMITS.phoneMax),
    creditLimit: safeLimit,
    currency: isValidCurrency(input.currency ?? "") ? input.currency! : ("ريال" as const),
    isCashAccount: Boolean(input.isCashAccount),
    accountImage: (input.accountImage === "2" || input.accountImage === "3" ? input.accountImage : "1") as "1" | "2" | "3",
    sortOrder: Number.isFinite(input.sortOrder) ? Number(input.sortOrder) : 1,
    settlement: Boolean(input.settlement),
    documentNumberRequired: Boolean(input.documentNumberRequired),
    messageMethod: (input.messageMethod === "whatsapp" ? "whatsapp" : "sms") as "whatsapp" | "sms",
    sendMode: (input.sendMode === "auto" || input.sendMode === "confirm" ? input.sendMode : "never") as "auto" | "confirm" | "never",
    note: clampString(input.note ?? "", SCHEMA_LIMITS.accountNoteMax),
    openingBalance: safeOpening,
    openingDirection: (input.openingDirection === "credit" ? "credit" : "debit") as "credit" | "debit",
    codeNumber: Number.isFinite(input.codeNumber) ? Number(input.codeNumber) : 1,
    ...(input.legacyRef ? { legacyRef: clampString(input.legacyRef, 128) } : {}),
  };
}

export function sanitizeLedgerPayload(
  input: Partial<LedgerEntryRecord> & { ownerId: string; accountId: string; accountName: string },
) {
  const safeAmount = Math.max(0, parseArabicNumber(input.amount));
  const safeRate = Math.max(0.0001, parseArabicNumber(input.exchangeRate) || 1);
  const dueDate = clampString(input.dueDate ?? "", SCHEMA_LIMITS.entryDateMax);
  const expenseCategory = clampString(input.expenseCategory ?? "", SCHEMA_LIMITS.expenseCategoryMax);
  const rawDelivery =
    input.deliveryDays !== undefined && input.deliveryDays !== null
      ? parseArabicNumber(input.deliveryDays)
      : undefined;
  const deliveryDays =
    rawDelivery !== undefined && Number.isFinite(rawDelivery)
      ? Math.min(365, Math.max(0, Math.round(rawDelivery)))
      : undefined;
  return {
    ownerId: clampString(input.ownerId, SCHEMA_LIMITS.ownerIdMax),
    accountId: clampString(input.accountId, SCHEMA_LIMITS.ownerIdMax),
    accountName: clampString(input.accountName, SCHEMA_LIMITS.accountNameMax) || "حساب",
    counterpartAccountId: clampString(input.counterpartAccountId ?? "", SCHEMA_LIMITS.ownerIdMax),
    counterpartAccountName: clampString(input.counterpartAccountName ?? "", SCHEMA_LIMITS.accountNameMax),
    kind: isValidLedgerKind(input.kind ?? "") ? input.kind! : ("voucher" as const),
    typeLabel: clampString(input.typeLabel || "سند", SCHEMA_LIMITS.typeLabelMax) || "سند",
    payment: (input.payment === "cash" || input.payment === "credit" ? input.payment : "balance") as "cash" | "credit" | "balance",
    direction: (input.direction === "credit" ? "credit" : "debit") as "credit" | "debit",
    amount: safeAmount,
    currency: isValidCurrency(input.currency ?? "") ? input.currency! : ("ريال" as const),
    exchangeRate: safeRate,
    details: clampString(input.details ?? "", SCHEMA_LIMITS.ledgerDetailsMax),
    documentNumber: clampString(input.documentNumber ?? "", SCHEMA_LIMITS.documentNumberMax),
    warehouseId: clampString(input.warehouseId ?? "", SCHEMA_LIMITS.ownerIdMax),
    warehouseName: clampString(input.warehouseName ?? "", SCHEMA_LIMITS.warehouseNameMax),
    invoiceContent: (
      input.invoiceContent === "items" || input.invoiceContent === "free" ? input.invoiceContent : "none"
    ) as "items" | "free" | "none",
    entryNumber: Number.isFinite(input.entryNumber) ? Number(input.entryNumber) : 1,
    deleted: Boolean(input.deleted),
    entryDate:
      clampString(input.entryDate || new Date().toISOString().slice(0, 10), SCHEMA_LIMITS.entryDateMax) ||
      new Date().toISOString().slice(0, 10),
    ...(dueDate ? { dueDate } : {}),
    ...(expenseCategory ? { expenseCategory } : {}),
    ...(deliveryDays !== undefined ? { deliveryDays } : {}),
    ...(input.legacyRef ? { legacyRef: clampString(input.legacyRef, 128) } : {}),
  };
}

export function sanitizeWarehousePayload(input: Partial<WarehouseRecord> & { ownerId: string; name: string }) {
  return {
    ownerId: clampString(input.ownerId, SCHEMA_LIMITS.ownerIdMax),
    name: clampString(input.name, SCHEMA_LIMITS.warehouseNameMax),
    details: clampString(input.details ?? "", SCHEMA_LIMITS.warehouseDetailsMax),
    isDefault: Boolean(input.isDefault),
    codeNumber: Number.isFinite(input.codeNumber) ? Number(input.codeNumber) : 1,
    ...(input.legacyRef ? { legacyRef: clampString(input.legacyRef, 128) } : {}),
  };
}

export function sanitizeInventoryPayload(
  input: Partial<InventoryItemRecord> & { ownerId: string; name: string; warehouseId: string },
) {
  const minThreshold =
    input.minThreshold !== undefined ? Math.max(0, parseArabicNumber(input.minThreshold)) : 25;
  const sku = clampString(input.sku ?? "", SCHEMA_LIMITS.skuMax);
  return {
    ownerId: clampString(input.ownerId, SCHEMA_LIMITS.ownerIdMax),
    name: clampString(input.name, SCHEMA_LIMITS.inventoryNameMax),
    unit: clampString(input.unit || "حبة", SCHEMA_LIMITS.inventoryUnitMax) || "حبة",
    quantity: Math.max(0, parseArabicNumber(input.quantity)),
    avgCost: Math.max(0, parseArabicNumber(input.avgCost)),
    ...(input.sellingPrice !== undefined && Number.isFinite(Number(input.sellingPrice)) && Number(input.sellingPrice) > 0
      ? { sellingPrice: Number(input.sellingPrice) } : {}),
    minThreshold,
    ...(sku ? { sku } : {}),
    warehouseId: clampString(input.warehouseId, SCHEMA_LIMITS.ownerIdMax),
    ...(input.quantityUnverified ? { quantityUnverified: true } : {}),
    ...(input.legacyRef ? { legacyRef: clampString(input.legacyRef, 128) } : {}),
  };
}

export type AccountSummary = {
  debitTotal: number;
  creditTotal: number;
  netBalance: number;
  tone: "credit" | "debit" | "neutral";
  entryCount: number;
};

export function affectsAccountBalance(entry: Pick<LedgerEntryRecord, "deleted" | "kind">): boolean {
  if (entry.deleted) return false;
  return entry.kind !== "quote" && entry.kind !== "order";
}

export function maxNumericField<T>(
  items: readonly T[],
  selector: (item: T) => number,
  floor = 0,
): number {
  let maxVal = floor;
  for (let i = 0; i < items.length; i += 1) {
    const val = selector(items[i]);
    if (Number.isFinite(val) && val > maxVal) {
      maxVal = val;
    }
  }
  return maxVal;
}

export function limitSelectAccounts(
  accounts: readonly AccountRecord[],
  selectedId?: string,
  maxOptions = 150,
): { options: AccountRecord[]; truncatedCount: number } {
  if (accounts.length <= maxOptions) {
    return { options: accounts as AccountRecord[], truncatedCount: 0 };
  }
  const sliced = accounts.slice(0, maxOptions);
  if (selectedId && !sliced.some((a) => a.id === selectedId)) {
    const selected = accounts.find((a) => a.id === selectedId);
    if (selected) {
      return {
        options: [selected, ...sliced.slice(0, maxOptions - 1)],
        truncatedCount: accounts.length - maxOptions,
      };
    }
  }
  return {
    options: sliced,
    truncatedCount: accounts.length - sliced.length,
  };
}

type AccountEntriesIndex = {
  length: number;
  byAccount: Map<string, LedgerEntryRecord[]>;
};

const ledgerByAccountCache = new WeakMap<readonly LedgerEntryRecord[], AccountEntriesIndex>();

function getEntriesForAccount(
  entries: readonly LedgerEntryRecord[],
  accountId: string,
): readonly LedgerEntryRecord[] {
  let cached = ledgerByAccountCache.get(entries);
  if (!cached || cached.length !== entries.length) {
    const byAccount = new Map<string, LedgerEntryRecord[]>();
    for (let i = 0; i < entries.length; i += 1) {
      const entry = entries[i];
      const primaryId = entry.accountId;
      if (primaryId) {
        let list = byAccount.get(primaryId);
        if (!list) {
          list = [];
          byAccount.set(primaryId, list);
        }
        list.push(entry);
      }
      const counterId = entry.counterpartAccountId;
      if (counterId && counterId !== primaryId) {
        let list = byAccount.get(counterId);
        if (!list) {
          list = [];
          byAccount.set(counterId, list);
        }
        list.push(entry);
      }
    }
    cached = { length: entries.length, byAccount };
    ledgerByAccountCache.set(entries, cached);
  }
  return cached.byAccount.get(accountId) ?? [];
}

export function computeAccountSummary(
  account: AccountRecord,
  entries: readonly LedgerEntryRecord[],
  currencyFilter?: string,
): AccountSummary {
  let debitTotal = 0;
  let creditTotal = 0;
  let entryCount = 0;

  if (account.openingBalance > 0 && (!currencyFilter || currencyFilter === "الكل" || currencyFilter === account.currency)) {
    if (account.openingDirection === "credit") {
      creditTotal += account.openingBalance;
    } else {
      debitTotal += account.openingBalance;
    }
  }

  const accountEntries = getEntriesForAccount(entries, account.id);
  for (let i = 0; i < accountEntries.length; i += 1) {
    const entry = accountEntries[i];
    if (entry.deleted) continue;
    const isPrimary = entry.accountId === account.id;
    const isCounterpart = entry.counterpartAccountId === account.id && entry.counterpartAccountId !== "";
    if (!isPrimary && !isCounterpart) continue;

    if (
      currencyFilter &&
      currencyFilter !== "الكل" &&
      currencyFilter !== "جميع العملات بدون مصارفة" &&
      currencyFilter !== "مصارفة الكل بعملة ريال" &&
      entry.currency !== currencyFilter
    ) {
      continue;
    }

    entryCount += 1;
    if (!affectsAccountBalance(entry)) continue;

    const effectiveAmount =
      currencyFilter === "مصارفة الكل بعملة ريال" ? entry.amount * (entry.exchangeRate || 1) : entry.amount;
    const hasExplicitSides = entry.rawDain !== undefined || entry.rawMadin !== undefined;
    const shouldWashCash = hasExplicitSides
      ? Boolean(entry.settledOnReceipt)
      : Boolean((account.isCashAccount && entry.payment === "cash") || entry.settledOnReceipt);

    if (isPrimary) {
      if (shouldWashCash) {
        // Cash settlement washes both sides while preserving turnover totals.
        creditTotal += effectiveAmount;
        debitTotal += effectiveAmount;
      } else if (entry.direction === "credit") {
        creditTotal += effectiveAmount;
      } else {
        debitTotal += effectiveAmount;
      }
    } else if (isCounterpart) {
      // Counterpart in simple entry receives the opposite side.
      if (entry.direction === "credit") {
        debitTotal += effectiveAmount;
      } else {
        creditTotal += effectiveAmount;
      }
    }
  }

  const netSigned = creditTotal - debitTotal;
  const tone: "credit" | "debit" | "neutral" =
    Math.abs(netSigned) < 0.005 ? "neutral" : netSigned > 0 ? "credit" : "debit";

  return {
    debitTotal,
    creditTotal,
    netBalance: Math.abs(netSigned),
    tone,
    entryCount,
  };
}

export function computeCategoryTotals(
  accounts: readonly AccountRecord[],
  entries: readonly LedgerEntryRecord[],
  currencyFilter?: string,
): Record<AccountCategory, { netSigned: number; debitTotal: number; creditTotal: number; count: number }> {
  const result: Record<AccountCategory, { netSigned: number; debitTotal: number; creditTotal: number; count: number }> =
    {
      purchases: { netSigned: 0, debitTotal: 0, creditTotal: 0, count: 0 },
      sales: { netSigned: 0, debitTotal: 0, creditTotal: 0, count: 0 },
      clients: { netSigned: 0, debitTotal: 0, creditTotal: 0, count: 0 },
      employees: { netSigned: 0, debitTotal: 0, creditTotal: 0, count: 0 },
      transfers: { netSigned: 0, debitTotal: 0, creditTotal: 0, count: 0 },
      shop: { netSigned: 0, debitTotal: 0, creditTotal: 0, count: 0 },
    };

  const filterSpecific =
    Boolean(currencyFilter) &&
    currencyFilter !== "الكل" &&
    currencyFilter !== "جميع العملات بدون مصارفة" &&
    currencyFilter !== "مصارفة الكل بعملة ريال";
  const convertAllToRiyal = currencyFilter === "مصارفة الكل بعملة ريال";

  const accMap = new Map<string, AccountRecord>();
  for (const account of accounts) {
    accMap.set(account.id, account);
    const bucket = result[account.category];
    bucket.count += 1;
    if (account.openingBalance > 0 && (!filterSpecific || account.currency === currencyFilter)) {
      if (account.openingDirection === "credit") {
        bucket.creditTotal += account.openingBalance;
      } else {
        bucket.debitTotal += account.openingBalance;
      }
    }
  }

  for (const entry of entries) {
    if (entry.deleted || !affectsAccountBalance(entry)) continue;
    if (filterSpecific && entry.currency !== currencyFilter) continue;
    const effectiveAmount = convertAllToRiyal ? entry.amount * (entry.exchangeRate || 1) : entry.amount;

    const primary = accMap.get(entry.accountId);
    if (primary) {
      const bucket = result[primary.category];
      const hasExplicitSides = entry.rawDain !== undefined || entry.rawMadin !== undefined;
      const shouldWashCash = hasExplicitSides
        ? Boolean(entry.settledOnReceipt)
        : Boolean((primary.isCashAccount && entry.payment === "cash") || entry.settledOnReceipt);
      if (shouldWashCash) {
        bucket.creditTotal += effectiveAmount;
        bucket.debitTotal += effectiveAmount;
      } else if (entry.direction === "credit") {
        bucket.creditTotal += effectiveAmount;
      } else {
        bucket.debitTotal += effectiveAmount;
      }
    }
    if (entry.counterpartAccountId) {
      const counter = accMap.get(entry.counterpartAccountId);
      if (counter) {
        const bucket = result[counter.category];
        if (entry.direction === "credit") {
          bucket.debitTotal += effectiveAmount;
        } else {
          bucket.creditTotal += effectiveAmount;
        }
      }
    }
  }

  for (const key of ACCOUNT_CATEGORIES) {
    const b = result[key];
    b.netSigned = b.creditTotal - b.debitTotal;
  }

  return result;
}

export function computeStatementRows(
  account: AccountRecord,
  entries: readonly LedgerEntryRecord[],
  options: {
    currency?: string;
    searchQuery?: string;
    searchMode?: string;
    showPreviousBalance?: boolean;
    fromDate?: string;
    toDate?: string;
    docKind?: "all" | "invoice" | "voucher" | "return" | "quote" | "order";
    sortOrder?: "asc" | "desc";
  } = {},
): {
  rows: StatementRowWithBalance[];
  debitTotal: number;
  creditTotal: number;
  netBalance: number;
  netDirection: "credit" | "debit" | "neutral";
  previousBalance: number;
  previousDirection: "credit" | "debit" | "neutral";
} {
  const currency = options.currency ?? "الكل";
  const query = normalizeArabicSearch(options.searchQuery ?? "");
  const searchMode = options.searchMode ?? "الكل";
  const fromDate = options.fromDate?.trim() || "";
  const toDate = options.toDate?.trim() || "";
  const docKind = options.docKind ?? "all";

  const accountEntries = getEntriesForAccount(entries, account.id);
  const belongsAndCurrency = accountEntries
    .filter((entry) => {
      if (entry.deleted) return false;
      const belongs = entry.accountId === account.id || entry.counterpartAccountId === account.id;
      if (!belongs) return false;
      if (
        currency !== "الكل" &&
        currency !== "جميع العملات بدون مصارفة" &&
        currency !== "مصارفة الكل بعملة ريال" &&
        entry.currency !== currency
      ) {
        return false;
      }
      return true;
    })
    .sort((a, b) => a.createdAtMs - b.createdAtMs || a.entryNumber - b.entryNumber);

  const signedEffect = (entry: LedgerEntryRecord): { debit: number; credit: number; netDelta: number } => {
    const isPrimary = entry.accountId === account.id;
    const amount =
      currency === "مصارفة الكل بعملة ريال" ? entry.amount * (entry.exchangeRate || 1) : entry.amount;
    if (!affectsAccountBalance(entry)) {
      return { debit: 0, credit: 0, netDelta: 0 };
    }
    const hasExplicitSides = entry.rawDain !== undefined || entry.rawMadin !== undefined;
    const shouldWashCash = hasExplicitSides
      ? Boolean(entry.settledOnReceipt)
      : Boolean((account.isCashAccount && entry.payment === "cash") || (isPrimary && entry.settledOnReceipt));
    if (shouldWashCash) {
      return { debit: amount, credit: amount, netDelta: 0 };
    }
    if (isPrimary) {
      if (entry.direction === "credit") return { debit: 0, credit: amount, netDelta: amount };
      return { debit: amount, credit: 0, netDelta: -amount };
    }
    if (entry.direction === "credit") return { debit: amount, credit: 0, netDelta: -amount };
    return { debit: 0, credit: amount, netDelta: amount };
  };

  let prePeriodSigned = 0;
  const relevant: LedgerEntryRecord[] = [];
  for (const entry of belongsAndCurrency) {
    const dt = entry.entryDate || "";
    if (fromDate && dt && dt < fromDate) {
      prePeriodSigned += signedEffect(entry).netDelta;
      continue;
    }
    if (toDate && dt && dt > toDate) {
      continue;
    }
    if (docKind !== "all" && entry.kind !== docKind) {
      continue;
    }
    if (query && !ledgerEntryMatchesQuery(entry, query, searchMode)) {
      continue;
    }
    relevant.push(entry);
  }

  const openingSigned =
    account.openingDirection === "credit" ? account.openingBalance : -account.openingBalance;
  const previousBalanceSigned = openingSigned + prePeriodSigned;

  let running = options.showPreviousBalance ? previousBalanceSigned : 0;
  let debitTotal = 0;
  let creditTotal = 0;

  const chronological: StatementRowWithBalance[] = relevant.map((entry) => {
    const eff = signedEffect(entry);
    debitTotal += eff.debit;
    creditTotal += eff.credit;
    running += eff.netDelta;

    return {
      ...entry,
      runningBalance: account.isCashAccount ? 0 : Math.abs(running),
    };
  });

  // Newest entries appear at the top of statements cleanly
  const rows = options.sortOrder === "asc" ? chronological : [...chronological].reverse();
  const netSigned =
    creditTotal - debitTotal + (options.showPreviousBalance ? previousBalanceSigned : 0);

  return {
    rows,
    debitTotal,
    creditTotal,
    netBalance: Math.abs(netSigned),
    netDirection: Math.abs(netSigned) < 0.005 ? "neutral" : netSigned > 0 ? "credit" : "debit",
    previousBalance: Math.abs(previousBalanceSigned),
    previousDirection:
      Math.abs(previousBalanceSigned) < 0.005
        ? "neutral"
        : previousBalanceSigned > 0
          ? "credit"
          : "debit",
  };
}

export function ledgerEntryMatchesQuery(entry: LedgerEntryRecord, normalizedQuery: string, mode: string): boolean {
  if (!normalizedQuery) return true;
  const amountText = `${entry.amount} ${formatAmount(entry.amount)}`;
  const linesText = (entry.lines ?? []).map((l) => `${l.itemName}`).join(" ");
  const fields: Record<string, string> = {
    "الرقم": String(entry.entryNumber),
    "البيان": `${entry.details} ${linesText}`,
    "رقم المستند": entry.documentNumber,
    "اسم المرسل": entry.counterpartAccountName,
    "اسم المستلم": entry.accountName,
    "اسم الشركة": entry.warehouseName,
    "المبلغ عليه": entry.direction === "debit" ? amountText : "",
    "المبلغ له": entry.direction === "credit" ? amountText : "",
  };
  if (mode === "الكل") {
    return matchesArabicSearch(
      [...Object.values(fields), entry.typeLabel, entry.entryDate, entry.currency].join(" "),
      normalizedQuery,
    );
  }
  return matchesArabicSearch(fields[mode] ?? "", normalizedQuery);
}

export function accountMatchesQuery(account: AccountRecord, query: string): boolean {
  return matchesArabicSearch(
    `${account.name} ${account.phone} ${account.codeNumber} ${account.id} ${account.note ?? ""} ${account.legacyRef ?? ""} ${account.currency}`,
    query,
  );
}

export function getCategoryTitle(category: AccountCategory): string {
  const map: Record<AccountCategory, string> = {
    purchases: "مشتريات",
    sales: "مبيعات",
    clients: "عملاء",
    employees: "موظفين",
    transfers: "حوالات",
    shop: "محل",
  };
  return map[category] ?? category;
}

export function rankAccountSearchMatches(
  accounts: readonly AccountRecord[],
  query: string,
  preferredCategories?: AccountCategory | AccountCategory[],
  limit?: number,
): AccountRecord[] {
  const normQuery = normalizeArabicSearch(query);
  const prefs = Array.isArray(preferredCategories)
    ? preferredCategories
    : preferredCategories
      ? [preferredCategories]
      : [];
  const prefSet = prefs.length > 0 ? new Set(prefs) : null;

  if (!normQuery) {
    const ordered = [...accounts];
    ordered.sort((a, b) => {
      if (prefSet) {
        const aPref = prefSet.has(a.category) ? 0 : 1;
        const bPref = prefSet.has(b.category) ? 0 : 1;
        if (aPref !== bPref) return aPref - bPref;
      }
      return a.codeNumber - b.codeNumber || a.name.localeCompare(b.name, "ar");
    });
    return typeof limit === "number" ? ordered.slice(0, limit) : ordered;
  }

  const tokens = normQuery.split(" ").filter(Boolean);
  const scored: { acc: AccountRecord; pref: number; score: number }[] = [];
  for (let i = 0; i < accounts.length; i += 1) {
    const acc = accounts[i];
    const haystack = normalizeArabicSearch(
      `${acc.name} ${acc.phone} ${acc.codeNumber} ${acc.id} ${acc.note ?? ""} ${acc.legacyRef ?? ""} ${acc.currency}`,
    );
    let matches = true;
    for (let t = 0; t < tokens.length; t += 1) {
      if (!haystack.includes(tokens[t])) {
        matches = false;
        break;
      }
    }
    if (!matches) continue;
    const normName = normalizeArabicSearch(acc.name);
    const score =
      normName === normQuery
        ? 0
        : normName.startsWith(normQuery)
          ? 1
          : String(acc.codeNumber) === normQuery || normalizeArabicSearch(acc.phone) === normQuery
            ? 2
            : normName.includes(normQuery)
              ? 3
              : 4;
    scored.push({
      acc,
      pref: prefSet ? (prefSet.has(acc.category) ? 0 : 1) : 0,
      score,
    });
  }

  scored.sort((a, b) => {
    if (a.pref !== b.pref) return a.pref - b.pref;
    if (a.score !== b.score) return a.score - b.score;
    return a.acc.name.localeCompare(b.acc.name, "ar");
  });

  const end = typeof limit === "number" ? Math.min(limit, scored.length) : scored.length;
  const result = new Array<AccountRecord>(end);
  for (let i = 0; i < end; i += 1) {
    result[i] = scored[i].acc;
  }
  return result;
}

function escapeCsvCell(cell: string | number | boolean): string {
  const str = String(cell ?? "");
  if (/[",\r\n]/.test(str)) {
    return `"${str.replace(/"/g, '""')}"`;
  }
  return str;
}

export function buildCsvContent(headers: readonly string[], rows: readonly (readonly (string | number | boolean)[])[]): string {
  const headerLine = headers.map(escapeCsvCell).join(",");
  const dataLines = rows.map((row) => row.map(escapeCsvCell).join(","));
  return `\uFEFF${[headerLine, ...dataLines].join("\r\n")}`;
}

export function computeInventorySummary(items: readonly InventoryItemRecord[], warehouseId?: string) {
  const filtered = warehouseId ? items.filter((item) => item.warehouseId === warehouseId) : items;
  let totalQuantity = 0;
  let totalValue = 0;
  let verifiedCount = 0;
  let unverifiedCount = 0;
  for (const item of filtered) {
    if (item.quantityUnverified) {
      unverifiedCount += 1;
      continue;
    }
    verifiedCount += 1;
    totalQuantity += item.quantity;
    totalValue += item.quantity * item.avgCost;
  }
  return {
    items: filtered,
    totalQuantity,
    totalValue,
    verifiedCount,
    unverifiedCount,
  };
}

export type LowStockAlertItem = InventoryItemRecord & {
  warehouseName: string;
  effectiveThreshold: number;
  shortage: number;
  severity: "critical" | "warning";
  stockValue: number;
};

export type DashboardSummary = {
  totalSales: number;
  salesInvoiceCount: number;
  salesAccountCount: number;
  recentInvoices: LedgerEntryRecord[];
  totalInvoicesCount: number;
  totalInvoicesVolume: number;
  lowStockItems: LowStockAlertItem[];
  totalInventoryItems: number;
  lowStockThreshold: number;
};

export type SalesTrendPoint = {
  dateIso: string;
  shortLabel: string;
  weekdayLabel: string;
  salesTotal: number;
  invoiceCount: number;
};

export type NotificationCategory = "due-invoice" | "low-stock" | "system";

export type WorkspaceNotification = {
  id: string;
  category: NotificationCategory;
  severity: "critical" | "warning" | "info";
  title: string;
  message: string;
  dateLabel: string;
  targetType?: "invoice" | "inventory" | "account" | "settings";
  targetId?: string;
};

export type ParsedQrStockPayload = {
  raw: string;
  lookupKey: string;
  sku?: string;
  name?: string;
  quantity?: number;
  unit?: string;
  avgCost?: number;
  minThreshold?: number;
};

function isSaleLedgerEntry(entry: LedgerEntryRecord, salesAccountIds: ReadonlySet<string>): boolean {
  return (
    salesAccountIds.has(entry.accountId) ||
    (entry.kind === "invoice" && entry.direction === "debit") ||
    (entry.kind === "return" && entry.direction === "credit" && salesAccountIds.has(entry.accountId))
  );
}

export function computeDashboardSummary(
  accounts: readonly AccountRecord[],
  entries: readonly LedgerEntryRecord[],
  warehouses: readonly WarehouseRecord[],
  inventory: readonly InventoryItemRecord[],
  options: {
    lowStockThreshold?: number;
    useItemThresholds?: boolean;
    recentInvoicesLimit?: number;
    period?: "all" | "month" | "week";
    referenceDate?: Date;
  } = {},
): DashboardSummary {
  const defaultThreshold = options.lowStockThreshold ?? 25;
  const useItemThresholds = options.useItemThresholds ?? true;
  const recentInvoicesLimit = options.recentInvoicesLimit ?? 6;
  const period = options.period ?? "all";
  const refDate = options.referenceDate ?? new Date();

  const cutoffIso =
    period === "week"
      ? new Date(refDate.getTime() - 7 * 86_400_000).toISOString().slice(0, 10)
      : period === "month"
        ? new Date(refDate.getTime() - 30 * 86_400_000).toISOString().slice(0, 10)
        : "";

  const salesAccountIds = new Set(accounts.filter((a) => a.category === "sales").map((a) => a.id));
  const warehouseMap = new Map(warehouses.map((w) => [w.id, w.name]));

  let totalSales = 0;
  if (period === "all") {
    for (const acc of accounts) {
      if (acc.category === "sales" && acc.openingBalance > 0) {
        totalSales += acc.openingBalance;
      }
    }
  }

  let salesInvoiceCount = 0;
  let totalInvoicesVolume = 0;
  const activeInvoices: LedgerEntryRecord[] = [];

  for (const entry of entries) {
    if (entry.deleted) continue;
    if (cutoffIso && entry.entryDate < cutoffIso) continue;

    const isInvoiceDoc = entry.kind === "invoice" || entry.kind === "return";
    if (isInvoiceDoc) {
      activeInvoices.push(entry);
      if (entry.kind === "invoice") {
        totalInvoicesVolume += entry.amount;
      }
    }

    if (isSaleLedgerEntry(entry, salesAccountIds)) {
      if (entry.kind === "return") {
        totalSales = Math.max(0, totalSales - entry.amount);
      } else if (entry.kind === "invoice" || entry.kind === "voucher") {
        totalSales += entry.amount;
        if (entry.kind === "invoice") {
          salesInvoiceCount += 1;
        }
      }
    }
  }

  activeInvoices.sort(
    (a, b) =>
      b.entryDate.localeCompare(a.entryDate) ||
      b.createdAtMs - a.createdAtMs ||
      b.entryNumber - a.entryNumber,
  );

  const lowStockItems: LowStockAlertItem[] = inventory
    .filter((item) => !item.quantityUnverified)
    .map((item) => {
      const effectiveThreshold = useItemThresholds
        ? typeof item.minThreshold === "number"
          ? item.minThreshold
          : defaultThreshold
        : defaultThreshold;
      const shortage = Math.max(0, effectiveThreshold - item.quantity);
      const isBelow = effectiveThreshold > 0 && item.quantity < effectiveThreshold;
      return {
        ...item,
        warehouseName: warehouseMap.get(item.warehouseId) ?? "مخزن عام",
        effectiveThreshold,
        shortage,
        severity:
          item.quantity <= Math.max(5, Math.floor(effectiveThreshold * 0.5))
            ? ("critical" as const)
            : ("warning" as const),
        stockValue: item.quantity * item.avgCost,
        isBelow,
      };
    })
    .filter((item) => item.isBelow)
    .map(({ isBelow: _discard, ...rest }) => rest)
    .sort((a, b) => b.shortage - a.shortage || a.quantity - b.quantity || a.name.localeCompare(b.name, "ar"));

  return {
    totalSales,
    salesInvoiceCount,
    salesAccountCount: salesAccountIds.size,
    recentInvoices: activeInvoices.slice(0, recentInvoicesLimit),
    totalInvoicesCount: activeInvoices.length,
    totalInvoicesVolume,
    lowStockItems,
    totalInventoryItems: inventory.length,
    lowStockThreshold: defaultThreshold,
  };
}

export function computeSalesTrend7Days(
  accounts: readonly AccountRecord[],
  entries: readonly LedgerEntryRecord[],
  referenceDate: Date = new Date(),
): SalesTrendPoint[] {
  const salesAccountIds = new Set(accounts.filter((a) => a.category === "sales").map((a) => a.id));
  const endUtc = Date.UTC(referenceDate.getUTCFullYear(), referenceDate.getUTCMonth(), referenceDate.getUTCDate());
  const dayBuckets = new Map<string, { salesTotal: number; invoiceCount: number }>();

  const orderedDates: string[] = [];
  for (let offset = 6; offset >= 0; offset -= 1) {
    const dayDate = new Date(endUtc - offset * 86_400_000);
    const iso = dayDate.toISOString().slice(0, 10);
    orderedDates.push(iso);
    dayBuckets.set(iso, { salesTotal: 0, invoiceCount: 0 });
  }

  for (const entry of entries) {
    if (entry.deleted) continue;
    const bucket = dayBuckets.get(entry.entryDate);
    if (!bucket) continue;
    if (!isSaleLedgerEntry(entry, salesAccountIds)) continue;

    if (entry.kind === "return") {
      bucket.salesTotal = Math.max(0, bucket.salesTotal - entry.amount);
    } else if (entry.kind === "invoice" || entry.kind === "voucher") {
      bucket.salesTotal += entry.amount;
      if (entry.kind === "invoice") {
        bucket.invoiceCount += 1;
      }
    }
  }

  const weekdayFormatter = new Intl.DateTimeFormat("ar", { weekday: "short", timeZone: "UTC" });

  return orderedDates.map((iso) => {
    const dateObj = new Date(`${iso}T00:00:00Z`);
    const bucket = dayBuckets.get(iso)!;
    return {
      dateIso: iso,
      shortLabel: iso.slice(5).replace("-", "/"),
      weekdayLabel: weekdayFormatter.format(dateObj),
      salesTotal: bucket.salesTotal,
      invoiceCount: bucket.invoiceCount,
    };
  });
}

function addDaysIso(isoDate: string, days: number): string {
  const parsed = Date.parse(`${isoDate}T00:00:00Z`);
  if (!Number.isFinite(parsed)) return isoDate;
  return new Date(parsed + days * 86_400_000).toISOString().slice(0, 10);
}

export function isBackupOverdue(
  lastBackupIso: string | null | undefined,
  referenceDate: Date = new Date(),
  maxDays: number = 7,
): { lastBackupIso: string | null; daysSince: number | null; overdue: boolean } {
  if (!lastBackupIso) {
    return { lastBackupIso: null, daysSince: null, overdue: true };
  }
  const parsed = Date.parse(lastBackupIso);
  if (!Number.isFinite(parsed)) {
    return { lastBackupIso: null, daysSince: null, overdue: true };
  }
  const diffDays = Math.max(0, Math.floor((referenceDate.getTime() - parsed) / 86_400_000));
  return {
    lastBackupIso,
    daysSince: diffDays,
    overdue: diffDays > maxDays,
  };
}

export function computeWorkspaceNotifications(
  accounts: readonly AccountRecord[],
  entries: readonly LedgerEntryRecord[],
  warehouses: readonly WarehouseRecord[],
  inventory: readonly InventoryItemRecord[],
  workspace: WorkspaceSettings | null,
  referenceDate: Date = new Date(),
  options: { lastBackupIso?: string | null } = {},
): WorkspaceNotification[] {
  const notifications: WorkspaceNotification[] = [];
  const todayIso = referenceDate.toISOString().slice(0, 10);
  const todayMs = Date.parse(`${todayIso}T00:00:00Z`);
  const warehouseMap = new Map(warehouses.map((w) => [w.id, w.name]));

  // 1. Upcoming / overdue credit invoice due dates & over-credit-limit accounts
  for (const entry of entries) {
    if (entry.deleted) continue;
    if (entry.kind !== "invoice" || entry.payment !== "credit") continue;
    const dueIso = entry.dueDate?.trim() || addDaysIso(entry.entryDate, 30);
    const dueMs = Date.parse(`${dueIso}T00:00:00Z`);
    if (!Number.isFinite(dueMs)) continue;
    const daysLeft = Math.round((dueMs - todayMs) / 86_400_000);
    if (daysLeft <= 10) {
      const overdue = daysLeft < 0;
      notifications.push({
        id: `due_${entry.id}`,
        category: "due-invoice",
        severity: overdue || daysLeft <= 2 ? "critical" : "warning",
        title: overdue
          ? `فاتورة آجلة متأخرة السداد (#${entry.entryNumber})`
          : `موعد استحقاق فاتورة قريب (#${entry.entryNumber})`,
        message: `${entry.accountName} · ${formatAmount(entry.amount)} ${entry.currency} · ${
          overdue ? `متأخرة منذ ${Math.abs(daysLeft)} يوم` : daysLeft === 0 ? "تستحق اليوم" : `بعد ${daysLeft} يوم`
        }`,
        dateLabel: dueIso,
        targetType: "invoice",
        targetId: entry.id,
      });
    }
  }

  for (const acc of accounts) {
    if (acc.creditLimit <= 0) continue;
    const s = computeAccountSummary(acc, entries);
    if (s.netBalance > acc.creditLimit) {
      notifications.push({
        id: `limit_${acc.id}`,
        category: "due-invoice",
        severity: "critical",
        title: `تجاوز سقف المديونية: ${acc.name}`,
        message: `الرصيد الحالي ${formatAmount(s.netBalance)} يتجاوز السقف ${formatAmount(acc.creditLimit)} ${acc.currency}`,
        dateLabel: todayIso,
        targetType: "account",
        targetId: acc.id,
      });
    }
  }

  // 2. Low-stock updates for items below their defined minimum threshold
  for (const item of inventory) {
    if (item.quantityUnverified) continue;
    const threshold = typeof item.minThreshold === "number" ? item.minThreshold : 25;
    if (threshold > 0 && item.quantity < threshold) {
      const whName = warehouseMap.get(item.warehouseId) ?? "مخزن عام";
      notifications.push({
        id: `stock_${item.id}`,
        category: "low-stock",
        severity: item.quantity <= Math.max(5, Math.floor(threshold * 0.5)) ? "critical" : "warning",
        title: `انخفاض مخزون: ${item.name}`,
        message: `المتوفر ${formatAmount(item.quantity)} من الحد الأدنى ${formatAmount(threshold)} ${item.unit} · ${whName}`,
        dateLabel: todayIso,
        targetType: "inventory",
        targetId: item.id,
      });
    }
  }

  // 3. Important system messages & backup freshness check
  const backupStatus = isBackupOverdue(options.lastBackupIso, referenceDate, 7);
  if (backupStatus.overdue) {
    notifications.push({
      id: "sys_backup_overdue",
      category: "system",
      severity: "warning",
      title: "النسخة الاحتياطية بحاجة للتحديث",
      message:
        backupStatus.daysSince === null
          ? "لم يتم إنشاء نسخة احتياطية JSON بعد. يُنصح بتنزيل نسخة احتياطية لحماية بياناتك."
          : `مضى ${backupStatus.daysSince} يومًا على آخر نسخة احتياطية (أكثر من 7 أيام).`,
      dateLabel: todayIso,
      targetType: "settings",
    });
  }

  if (workspace && !workspace.whatsappInstantEnabled) {
    notifications.push({
      id: "sys_whatsapp_disabled",
      category: "system",
      severity: "info",
      title: "تنبيهات واتساب التلقائية غير مفعلة",
      message: "فعّل إشعارات واتساب الفورية من الإعدادات لإرسال إشعارات الفواتير تلقائيًا.",
      dateLabel: todayIso,
      targetType: "settings",
    });
  }

  notifications.push({
    id: "sys_cloud_sync",
    category: "system",
    severity: "info",
    title: "المزامنة السحابية نشطة ومؤمنة",
    message: `يتم حفظ ${accounts.length} حساب و${entries.filter((e) => !e.deleted).length} قيد في Firestore تلقائيًا.`,
    dateLabel: todayIso,
    targetType: "settings",
  });

  const severityRank: Record<WorkspaceNotification["severity"], number> = {
    critical: 0,
    warning: 1,
    info: 2,
  };
  return notifications.sort((a, b) => severityRank[a.severity] - severityRank[b.severity]);
}

export function parseQrStockPayload(rawInput: string): ParsedQrStockPayload {
  const raw = String(rawInput ?? "").trim();
  if (!raw) {
    return { raw: "", lookupKey: "" };
  }

  if (raw.startsWith("{") && raw.endsWith("}")) {
    try {
      const parsed = JSON.parse(raw) as Record<string, unknown>;
      const sku = typeof parsed.sku === "string" ? parsed.sku.trim() : typeof parsed.code === "string" ? parsed.code.trim() : undefined;
      const name = typeof parsed.name === "string" ? parsed.name.trim() : undefined;
      const unit = typeof parsed.unit === "string" ? parsed.unit.trim() : undefined;
      const qtyRaw = parsed.quantity ?? parsed.qty;
      const costRaw = parsed.avgCost ?? parsed.cost ?? parsed.price;
      const threshRaw = parsed.minThreshold ?? parsed.min;
      return {
        raw,
        lookupKey: sku || name || (typeof parsed.id === "string" ? parsed.id.trim() : "") || raw,
        ...(sku ? { sku } : {}),
        ...(name ? { name } : {}),
        ...(qtyRaw !== undefined ? { quantity: Math.max(0, parseArabicNumber(String(qtyRaw))) } : {}),
        ...(unit ? { unit } : {}),
        ...(costRaw !== undefined ? { avgCost: Math.max(0, parseArabicNumber(String(costRaw))) } : {}),
        ...(threshRaw !== undefined ? { minThreshold: Math.max(0, parseArabicNumber(String(threshRaw))) } : {}),
      };
    } catch {
      // Fall through to structured key=value or plain lookup parsing
    }
  }

  if (raw.includes("=") && (raw.includes(";") || raw.includes("\n"))) {
    const map = new Map<string, string>();
    for (const part of raw.split(/[;\n]+/)) {
      const idx = part.indexOf("=");
      if (idx > 0) {
        map.set(part.slice(0, idx).trim().toLowerCase(), part.slice(idx + 1).trim());
      }
    }
    const sku = map.get("sku") || map.get("code");
    const name = map.get("name");
    const unit = map.get("unit");
    const qty = map.get("qty") ?? map.get("quantity");
    const cost = map.get("cost") ?? map.get("avgcost");
    const min = map.get("min") ?? map.get("minthreshold");
    return {
      raw,
      lookupKey: sku || name || raw,
      ...(sku ? { sku } : {}),
      ...(name ? { name } : {}),
      ...(qty !== undefined ? { quantity: Math.max(0, parseArabicNumber(qty)) } : {}),
      ...(unit ? { unit } : {}),
      ...(cost !== undefined ? { avgCost: Math.max(0, parseArabicNumber(cost)) } : {}),
      ...(min !== undefined ? { minThreshold: Math.max(0, parseArabicNumber(min)) } : {}),
    };
  }

  const cleaned = raw.replace(/^(sku:|item:|product:)/i, "").trim();
  return {
    raw,
    lookupKey: cleaned,
    sku: /^[a-zA-Z0-9_-]{3,32}$/.test(cleaned) ? cleaned : undefined,
    name: /^[a-zA-Z0-9_-]{3,32}$/.test(cleaned) ? undefined : cleaned,
  };
}

export function inferExpenseCategory(
  description: string,
  accountName: string = "",
  accountCategory?: AccountCategory,
): ExpenseCategory {
  const haystack = normalizeArabicSearch(`${description} ${accountName}`);
  if (/راتب|رواتب|اجور|مكاف|حوافز|موظف/.test(haystack) || accountCategory === "employees") {
    return "رواتب وأجور";
  }
  if (/شحن|توصيل|نقل|بوليصة|جمرك|تخليص|لوجست|سيارة|سائق/.test(haystack)) {
    return "شحن ونقل";
  }
  if (/صيانة|كهرباء|ماء|مياه|انترنت|نت|اتصال|طاقة|وقود|ديزل|بنزين/.test(haystack)) {
    return "صيانة ومرافق";
  }
  if (/ايجار|إيجار|مستودع|مكتب|معرض|عقد/.test(haystack)) {
    return "إيجار ومقر";
  }
  if (/اعلان|تسويق|حملة|تصميم|مطبوع|دعاية|سوشيال/.test(haystack)) {
    return "تسويق ومبيعات";
  }
  if (/محل|تشغيل|قرطاسية|تغليف|اكواب|مستلزمات|ضيافة|نظافة/.test(haystack) || accountCategory === "shop") {
    return "مصروفات تشغيلية";
  }
  if (
    /فاتورة|توريد|بضاعة|صنف|حبة|كيلو|كرتون|ابجورة|توصيلة|بطارية|فواحة|مكينة|عازل|فرامة|شراء|مشتريات/.test(
      haystack,
    ) ||
    accountCategory === "purchases"
  ) {
    return "مشتريات بضائع";
  }
  return "أخرى";
}

export function normalizeExpenseCategory(raw?: string): ExpenseCategory | null {
  if (!raw) return null;
  const trimmed = raw.trim();
  if ((EXPENSE_CATEGORIES as readonly string[]).includes(trimmed)) {
    return trimmed as ExpenseCategory;
  }
  return null;
}

export type SupplierPerformanceMetric = {
  accountId: string;
  name: string;
  totalSpend: number;
  orderCount: number;
  avgOrderCost: number;
  avgDeliveryDays: number;
  onTimeScore: number;
};

export function computeSupplierPerformance(
  accounts: readonly AccountRecord[],
  entries: readonly LedgerEntryRecord[],
): SupplierPerformanceMetric[] {
  const supplierAccounts = accounts.filter((a) => a.category === "purchases");
  const results: SupplierPerformanceMetric[] = [];

  for (const supplier of supplierAccounts) {
    const supplierEntries = getEntriesForAccount(entries, supplier.id)
      .filter((e) => !e.deleted && (e.accountId === supplier.id || e.counterpartAccountId === supplier.id))
      .sort((a, b) => a.entryDate.localeCompare(b.entryDate));

    const purchaseDocs = supplierEntries.filter(
      (e) => e.kind === "invoice" || e.kind === "order" || (e.kind === "voucher" && e.direction === "credit"),
    );

    const totalSpendFromDocs = purchaseDocs.reduce((sum, e) => sum + e.amount * (e.exchangeRate || 1), 0);
    const totalSpend =
      totalSpendFromDocs > 0 ? totalSpendFromDocs : supplier.openingDirection === "credit" ? supplier.openingBalance : 0;
    const orderCount = Math.max(purchaseDocs.length, totalSpend > 0 ? 1 : 0);
    if (totalSpend <= 0 && orderCount === 0) continue;

    const avgOrderCost = orderCount > 0 ? Math.round((totalSpend / orderCount) * 100) / 100 : 0;

    const explicitDelivery = purchaseDocs
      .map((e) => e.deliveryDays)
      .filter((d): d is number => typeof d === "number" && Number.isFinite(d) && d >= 0);

    let avgDeliveryDays = 3;
    if (explicitDelivery.length > 0) {
      avgDeliveryDays =
        Math.round((explicitDelivery.reduce((s, d) => s + d, 0) / explicitDelivery.length) * 10) / 10;
    } else if (purchaseDocs.length >= 2) {
      const gaps: number[] = [];
      for (let i = 1; i < purchaseDocs.length; i += 1) {
        const prev = Date.parse(`${purchaseDocs[i - 1].entryDate}T00:00:00Z`);
        const cur = Date.parse(`${purchaseDocs[i].entryDate}T00:00:00Z`);
        if (Number.isFinite(prev) && Number.isFinite(cur)) {
          gaps.push(Math.min(14, Math.max(1, Math.round(Math.abs(cur - prev) / 86_400_000))));
        }
      }
      if (gaps.length > 0) {
        avgDeliveryDays = Math.round((gaps.reduce((s, g) => s + g, 0) / gaps.length) * 10) / 10;
      }
    } else {
      // Deterministic baseline when only opening balance / single cash supplier record exists
      avgDeliveryDays = supplier.isCashAccount ? 1.5 : 3 + (supplier.codeNumber % 4);
    }

    const onTimeScore = Math.max(35, Math.min(99, Math.round(100 - avgDeliveryDays * 6)));

    results.push({
      accountId: supplier.id,
      name: supplier.name,
      totalSpend,
      orderCount,
      avgOrderCost,
      avgDeliveryDays,
      onTimeScore,
    });
  }

  return results.sort((a, b) => b.totalSpend - a.totalSpend).slice(0, 6);
}

export type ExpenseTrendRange = "month" | "quarter" | "all";

export type ExpenseCategorySlice = {
  category: ExpenseCategory;
  total: number;
  count: number;
  percentage: number;
  color: string;
};

const EXPENSE_PALETTE: Record<ExpenseCategory, string> = {
  "مشتريات بضائع": "#0b5ca8",
  "مصروفات تشغيلية": "#f39a16",
  "شحن ونقل": "#0d9488",
  "رواتب وأجور": "#6366f1",
  "صيانة ومرافق": "#e11d48",
  "تسويق ومبيعات": "#0284c7",
  "إيجار ومقر": "#7c3aed",
  "أخرى": "#64748b",
};

export function computeExpenseTrendsByCategory(
  accounts: readonly AccountRecord[],
  entries: readonly LedgerEntryRecord[],
  range: ExpenseTrendRange = "month",
  referenceDate: Date = new Date(),
): {
  totalSpend: number;
  entryCount: number;
  slices: ExpenseCategorySlice[];
} {
  const accountMap = new Map(accounts.map((a) => [a.id, a]));
  const cutoffMs =
    range === "month"
      ? referenceDate.getTime() - 30 * 86_400_000
      : range === "quarter"
        ? referenceDate.getTime() - 90 * 86_400_000
        : 0;
  const cutoffIso = cutoffMs > 0 ? new Date(cutoffMs).toISOString().slice(0, 10) : "";

  const bucketMap = new Map<ExpenseCategory, { total: number; count: number }>();
  let totalSpend = 0;
  let entryCount = 0;

  for (const entry of entries) {
    if (entry.deleted) continue;
    if (entry.kind === "quote" || entry.kind === "order" || entry.kind === "return") continue;
    if (cutoffIso && entry.entryDate < cutoffIso) continue;

    const account = accountMap.get(entry.accountId);
    const isExpenseOrPurchase =
      account?.category === "purchases" ||
      account?.category === "shop" ||
      account?.category === "employees" ||
      (entry.kind === "invoice" && entry.direction === "credit") ||
      Boolean(entry.expenseCategory);

    if (!isExpenseOrPurchase) continue;

    const category =
      normalizeExpenseCategory(entry.expenseCategory) ??
      inferExpenseCategory(entry.details, entry.accountName, account?.category);
    const amount = entry.amount * (entry.exchangeRate || 1);
    if (amount <= 0) continue;

    const current = bucketMap.get(category) ?? { total: 0, count: 0 };
    current.total += amount;
    current.count += 1;
    bucketMap.set(category, current);
    totalSpend += amount;
    entryCount += 1;
  }

  const slices: ExpenseCategorySlice[] = Array.from(bucketMap.entries())
    .map(([category, data]) => ({
      category,
      total: data.total,
      count: data.count,
      percentage: totalSpend > 0 ? Math.round((data.total / totalSpend) * 1000) / 10 : 0,
      color: EXPENSE_PALETTE[category] ?? "#0b5ca8",
    }))
    .sort((a, b) => b.total - a.total);

  return {
    totalSpend,
    entryCount,
    slices,
  };
}

export function normalizeWhatsAppPhone(raw: string | undefined | null): string {
  if (!raw) return "";
  const asciiDigits = String(raw)
    .replace(/[٠-٩]/g, (ch) => String(ch.charCodeAt(0) - 0x0660))
    .replace(/[۰-۹]/g, (ch) => String(ch.charCodeAt(0) - 0x06f0))
    .replace(/[^0-9]/g, "");
  if (asciiDigits.startsWith("00")) {
    return asciiDigits.slice(2);
  }
  return asciiDigits;
}

export function buildWhatsAppMessageUrl(
  phone: string | undefined | null,
  message: string,
): string {
  const digits = normalizeWhatsAppPhone(phone);
  const encodedText = encodeURIComponent(message);
  if (digits.length >= 7) {
    return `https://wa.me/${digits}?text=${encodedText}`;
  }
  return `https://wa.me/?text=${encodedText}`;
}

const AR_ONES = [
  "",
  "واحد",
  "اثنان",
  "ثلاثة",
  "أربعة",
  "خمسة",
  "ستة",
  "سبعة",
  "ثمانية",
  "تسعة",
  "عشرة",
  "أحد عشر",
  "اثنا عشر",
  "ثلاثة عشر",
  "أربعة عشر",
  "خمسة عشر",
  "ستة عشر",
  "سبعة عشر",
  "ثمانية عشر",
  "تسعة عشر",
];

const AR_TENS = ["", "", "عشرون", "ثلاثون", "أربعون", "خمسون", "ستون", "سبعون", "ثمانون", "تسعون"];
const AR_HUNDREDS = [
  "",
  "مائة",
  "مائتان",
  "ثلاثمائة",
  "أربعمائة",
  "خمسمائة",
  "ستمائة",
  "سبعمائة",
  "ثمانمائة",
  "تسعمائة",
];

function arabicThreeDigits(n: number): string {
  const clean = Math.trunc(n) % 1000;
  if (clean === 0) return "";
  const hundreds = Math.floor(clean / 100);
  const rest = clean % 100;
  const parts: string[] = [];
  if (hundreds > 0) parts.push(AR_HUNDREDS[hundreds]);
  if (rest > 0) {
    if (rest < 20) {
      parts.push(AR_ONES[rest]);
    } else {
      const ones = rest % 10;
      const tens = Math.floor(rest / 10);
      if (ones > 0) {
        parts.push(`${AR_ONES[ones]} و${AR_TENS[tens]}`);
      } else {
        parts.push(AR_TENS[tens]);
      }
    }
  }
  return parts.join(" و");
}

function integerToArabicWords(n: number): string {
  const num = Math.trunc(Math.abs(n));
  if (num === 0) return "صفر";

  const scales: { divisor: number; singular: string; dual: string; plural: string; accSingular: string }[] = [
    { divisor: 1_000_000_000, singular: "مليار", dual: "ملياران", plural: "مليارات", accSingular: "مليارًا" },
    { divisor: 1_000_000, singular: "مليون", dual: "مليونان", plural: "ملايين", accSingular: "مليونًا" },
    { divisor: 1_000, singular: "ألف", dual: "ألفان", plural: "آلاف", accSingular: "ألفًا" },
  ];

  let rem = num;
  const parts: string[] = [];

  for (const scale of scales) {
    const group = Math.floor(rem / scale.divisor);
    rem %= scale.divisor;
    if (group === 0) continue;
    if (group === 1) parts.push(scale.singular);
    else if (group === 2) parts.push(scale.dual);
    else if (group >= 3 && group <= 10) parts.push(`${arabicThreeDigits(group)} ${scale.plural}`);
    else parts.push(`${arabicThreeDigits(group)} ${scale.accSingular}`);
  }

  if (rem > 0) {
    parts.push(arabicThreeDigits(rem));
  }
  return parts.join(" و");
}

export function amountToArabicWords(amount: number, currency = "ريال"): string {
  const safe = Number.isFinite(amount) ? Math.abs(amount) : 0;
  const rounded = Math.round(safe * 100) / 100;
  const intPart = Math.trunc(rounded);
  const fracPart = Math.round((rounded - intPart) * 100);
  const currencyLabel = currency?.trim() || "ريال";
  const mainText = `${integerToArabicWords(intPart)} ${currencyLabel}`;
  if (fracPart > 0) {
    const subUnit = currencyLabel === "دولار" || currencyLabel === "يورو" ? "سنت" : "فلس";
    return `${mainText} و${integerToArabicWords(fracPart)} ${subUnit} فقط لا غير`;
  }
  return `${mainText} فقط لا غير`;
}

export function formatSignedSmartBalance(debitMinusCredit: number): string {
  const safe = Number.isFinite(debitMinusCredit) ? debitMinusCredit : 0;
  if (Math.abs(safe) < 0.005) return "0";
  const formatted = formatAmount(Math.abs(safe));
  return safe < 0 ? `${formatted}-` : formatted;
}

export type AccountGroupSummaryRow = {
  id: number;
  legacyId: number;
  name: string;
  category: AccountCategory;
  currency: string;
  debitTotal: number;
  creditTotal: number;
  /** debitTotal - creditTotal: positive = عليه (receivable), negative = له (payable) */
  netDebitMinusCredit: number;
  accountCount: number;
};

export function computeAccountGroupsSummary(
  groups: readonly AccountGroupRecord[],
  accounts: readonly AccountRecord[],
  entries: readonly LedgerEntryRecord[],
  currencyByGroupId: Record<number, string> = {},
  defaultCurrency: string = "ريال",
): AccountGroupSummaryRow[] {
  const byGroupId = new Map<
    number,
    {
      group: AccountGroupRecord;
      currency: string;
      debitTotal: number;
      creditTotal: number;
      accountIds: Set<string>;
    }
  >();

  for (const g of groups) {
    const chosenCurrency = currencyByGroupId[g.id] ?? (g.currencyCode || defaultCurrency || "ريال");
    byGroupId.set(g.id, {
      group: g,
      currency: chosenCurrency,
      debitTotal: 0,
      creditTotal: 0,
      accountIds: new Set(),
    });
  }

  const accToGroup = new Map<string, number>();
  for (const acc of accounts) {
    if (!acc.groupId) continue;
    const target = byGroupId.get(acc.groupId);
    if (!target) continue;
    accToGroup.set(acc.id, acc.groupId);
    target.accountIds.add(acc.id);
    if (acc.openingBalance > 0 && (target.currency === "الكل" || acc.currency === target.currency)) {
      if (acc.openingDirection === "credit") target.creditTotal += acc.openingBalance;
      else target.debitTotal += acc.openingBalance;
    }
  }

  for (const entry of entries) {
    if (entry.deleted || !affectsAccountBalance(entry)) continue;
    const gId = accToGroup.get(entry.accountId);
    if (!gId) continue;
    const bucket = byGroupId.get(gId);
    if (!bucket) continue;
    if (bucket.currency !== "الكل" && entry.currency !== bucket.currency) continue;
    const hasExplicitSides = entry.rawDain !== undefined || entry.rawMadin !== undefined;
    if (hasExplicitSides && entry.settledOnReceipt) {
      bucket.debitTotal += entry.amount;
      bucket.creditTotal += entry.amount;
    } else if (hasExplicitSides) {
      bucket.debitTotal += entry.rawDain ?? (entry.direction === "debit" ? entry.amount : 0);
      bucket.creditTotal += entry.rawMadin ?? (entry.direction === "credit" ? entry.amount : 0);
    } else if (entry.direction === "credit") {
      bucket.creditTotal += entry.amount;
    } else {
      bucket.debitTotal += entry.amount;
    }
  }

  return Array.from(byGroupId.values())
    .sort((a, b) => (a.group.legacyId ?? a.group.sortOrder ?? a.group.id) - (b.group.legacyId ?? b.group.sortOrder ?? b.group.id))
    .map((item) => ({
      id: item.group.id,
      legacyId: item.group.legacyId ?? item.group.id,
      name: item.group.name,
      category: item.group.category,
      currency: item.currency,
      debitTotal: item.debitTotal,
      creditTotal: item.creditTotal,
      netDebitMinusCredit: item.debitTotal - item.creditTotal,
      accountCount: item.accountIds.size,
    }));
}

export type TrialBalanceReport = {
  currency: string;
  totalDebitAccounts: number;
  totalCreditAccounts: number;
  cashTotal: number;
  netBalance: number;
  resultLabel: "فائض" | "عجز" | "متزن";
  liquidityRatioPercent: number;
  salesTotal: number;
  purchasesTotal: number;
  inventoryValue: number;
  netProfit: number;
};

export function computeTrialBalanceReport(
  accounts: readonly AccountRecord[],
  entries: readonly LedgerEntryRecord[],
  inventory: readonly InventoryItemRecord[],
  _cashboxes: readonly CashboxRecord[] = [],
  options: { currency?: string; fromDate?: string; toDate?: string } = {},
): TrialBalanceReport {
  const round2 = (v: number) => Math.round((Number.isFinite(v) ? v : 0) * 100) / 100;
  const currency = options.currency || "ريال";
  const fromDate = options.fromDate || "";
  const toDate = options.toDate || "";

  const accNets = new Map<string, number>();
  for (const acc of accounts) {
    let init = 0;
    if (acc.openingBalance > 0 && (currency === "الكل" || acc.currency === currency)) {
      init = acc.openingDirection === "credit" ? -acc.openingBalance : acc.openingBalance;
    }
    accNets.set(acc.id, init);
  }

  let cashIn = 0;
  let cashOut = 0;
  let salesTotal = 0;
  let purchasesTotal = 0;

  for (const e of entries) {
    if (e.deleted || !affectsAccountBalance(e)) continue;
    if (currency !== "الكل" && e.currency !== currency) continue;
    if (toDate && e.entryDate > toDate) continue;

    const isBeforePeriod = Boolean(fromDate && e.entryDate < fromDate);

    const hasExplicitSides = e.rawDain !== undefined || e.rawMadin !== undefined;
    const dVal = hasExplicitSides
      ? e.settledOnReceipt
        ? 0
        : (e.rawDain ?? (e.direction === "debit" ? e.amount : 0))
      : e.settledOnReceipt
        ? 0
        : e.direction === "debit"
          ? e.amount
          : 0;
    const cVal = hasExplicitSides
      ? e.settledOnReceipt
        ? 0
        : (e.rawMadin ?? (e.direction === "credit" ? e.amount : 0))
      : e.settledOnReceipt
        ? 0
        : e.direction === "credit"
          ? e.amount
          : 0;

    // Account balances & cumulative cash include prior periods up to toDate
    accNets.set(e.accountId, (accNets.get(e.accountId) ?? 0) + (dVal - cVal));

    // Cashbox inflows/outflows: only genuine cash vouchers, cash-settled invoices/returns, or entries linked to a cashbox
    const affectsCashbox =
      (e.payment === "cash" || e.settledOnReceipt) &&
      (e.kind === "voucher" || e.kind === "invoice" || e.kind === "return" || e.cashboxId !== undefined);
    if (affectsCashbox) {
      if (e.kind === "voucher" || e.kind === "transfer" || e.kind === "simple-entry") {
        if (e.direction === "credit") cashIn += e.amount;
        else cashOut += e.amount;
      } else {
        const isInflow =
          e.docType !== undefined && e.docType !== null
            ? [2, 7, 5].includes(Number(e.docType))
            : e.direction === "debit";
        if (isInflow) cashIn += e.amount;
        else cashOut += e.amount;
      }
    }

    // Period P&L activity (sales & purchases strictly within [fromDate, toDate])
    if (isBeforePeriod) continue;
    if (e.kind === "invoice") {
      const dt = e.docType !== undefined && e.docType !== null ? Number(e.docType) : null;
      const lbl = e.typeLabel || "";
      const isSale =
        dt !== null
          ? dt === 2 || dt === 7
          : lbl.includes("بيع") || (!lbl.includes("شراء") && !lbl.includes("مشتريات") && e.direction === "debit");
      if (isSale) salesTotal += e.amount;
      else purchasesTotal += e.amount;
    } else if (e.kind === "return") {
      const dt = e.docType !== undefined && e.docType !== null ? Number(e.docType) : null;
      const lbl = e.typeLabel || "";
      const isSaleReturn =
        dt !== null
          ? dt === 4
          : lbl.includes("مبيعات") || (!lbl.includes("مشتريات") && e.direction === "credit");
      if (isSaleReturn) salesTotal -= e.amount;
      else purchasesTotal -= e.amount;
    }
  }

  let totalDebitAccounts = 0;
  let totalCreditAccounts = 0;
  for (const net of accNets.values()) {
    if (net > 0.005) totalDebitAccounts += net;
    else if (net < -0.005) totalCreditAccounts += Math.abs(net);
  }

  let inventoryValue = 0;
  for (const item of inventory) {
    const itemCurr = (item.currencyCode || "ريال").trim();
    if (currency !== "الكل" && itemCurr !== currency) continue;
    const qty = item.quantityUnverified ? (item.computedQuantity ?? 0) : item.quantity;
    if (qty > 0 && item.avgCost > 0) {
      inventoryValue += qty * item.avgCost;
    } else if (qty !== 0 && item.avgCost > 0 && !item.quantityUnverified) {
      inventoryValue += qty * item.avgCost;
    }
  }

  const cashTotal = round2(cashIn - cashOut);
  const netBalance = round2(totalDebitAccounts - totalCreditAccounts);
  const liquidityRatioPercent =
    totalCreditAccounts > 0 ? Math.round((Math.max(0, cashTotal) / totalCreditAccounts) * 1000) / 10 : 0;
  const netProfit = round2(salesTotal + inventoryValue - purchasesTotal);

  return {
    currency,
    totalDebitAccounts: round2(totalDebitAccounts),
    totalCreditAccounts: round2(totalCreditAccounts),
    cashTotal,
    netBalance,
    resultLabel: Math.abs(netBalance) < 0.005 ? "متزن" : netBalance >= 0 ? "فائض" : "عجز",
    liquidityRatioPercent,
    salesTotal: round2(salesTotal),
    purchasesTotal: round2(purchasesTotal),
    inventoryValue: round2(inventoryValue),
    netProfit,
  };
}

export function collectActiveCurrencies(
  accounts: readonly AccountRecord[],
  entries: readonly LedgerEntryRecord[],
  inventory: readonly InventoryItemRecord[],
  preferredCurrencies: readonly string[] = [],
): string[] {
  const set = new Set<string>();
  for (const c of preferredCurrencies) {
    const clean = c.trim();
    if (clean && clean !== "الكل") set.add(clean);
  }
  for (const acc of accounts) {
    if (acc.openingBalance > 0 && acc.currency) set.add(acc.currency);
  }
  for (const e of entries) {
    if (!e.deleted && e.currency) set.add(e.currency);
  }
  for (const i of inventory) {
    const qty = i.quantityUnverified ? (i.computedQuantity ?? 0) : i.quantity;
    if (Math.abs(qty) > 0.0001 && i.currencyCode) set.add(i.currencyCode);
  }
  if (set.size === 0) set.add("ريال");
  return [...set];
}

export function computeTrialBalanceByCurrency(
  accounts: readonly AccountRecord[],
  entries: readonly LedgerEntryRecord[],
  inventory: readonly InventoryItemRecord[],
  cashboxes: readonly CashboxRecord[] = [],
  options: { currencies?: readonly string[]; fromDate?: string; toDate?: string } = {},
): TrialBalanceReport[] {
  const currencies = collectActiveCurrencies(accounts, entries, inventory, options.currencies);
  return currencies
    .map((curr) =>
      computeTrialBalanceReport(accounts, entries, inventory, cashboxes, {
        currency: curr,
        fromDate: options.fromDate,
        toDate: options.toDate,
      }),
    )
    .filter(
      (r, idx) =>
        idx === 0 ||
        r.totalDebitAccounts !== 0 ||
        r.totalCreditAccounts !== 0 ||
        r.cashTotal !== 0 ||
        r.salesTotal !== 0 ||
        r.purchasesTotal !== 0 ||
        r.inventoryValue !== 0,
    );
}

export function computeCategoryTotalsByCurrency(
  accounts: readonly AccountRecord[],
  entries: readonly LedgerEntryRecord[],
  preferredCurrencies: readonly string[] = [],
): Array<{ currency: string; totals: ReturnType<typeof computeCategoryTotals> }> {
  const currencies = collectActiveCurrencies(accounts, entries, [], preferredCurrencies);
  return currencies
    .map((curr) => ({
      currency: curr,
      totals: computeCategoryTotals(accounts, entries, curr),
    }))
    .filter(
      (row, idx) =>
        idx === 0 ||
        Object.values(row.totals).some((b) => b.debitTotal !== 0 || b.creditTotal !== 0),
    );
}

