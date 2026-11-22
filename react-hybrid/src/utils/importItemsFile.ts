import * as XLSX from "xlsx";
import { parseArabicNumber } from "../accounting";
import type { CurrencyCode, InventoryItemRecord } from "../types";

export type ImportedInventoryItemInput = Partial<InventoryItemRecord> & {
  name: string;
  warehouseId?: string;
};

export type ParsedItemsImportResult = {
  items: ImportedInventoryItemInput[];
  skippedRows: number;
  sheetName: string;
};

function normalizeHeaderCell(raw: unknown): string {
  return String(raw ?? "")
    .replace(/^\uFEFF/, "")
    .replace(/[أإآ]/g, "ا")
    .replace(/ة/g, "ه")
    .replace(/ى/g, "ي")
    .replace(/[\u064B-\u065F\u0670\u0640]/g, "")
    .replace(/[_-]+/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .toLowerCase();
}

function cleanTextCell(raw: unknown): string {
  if (raw === null || raw === undefined) return "";
  if (typeof raw === "number" && Number.isFinite(raw)) {
    return Number.isInteger(raw) ? String(raw) : String(raw);
  }
  return String(raw).trim();
}

function parseOptionalNumber(raw: unknown): number | undefined {
  if (raw === null || raw === undefined) return undefined;
  if (typeof raw === "number") {
    return Number.isFinite(raw) ? raw : undefined;
  }
  const s = String(raw).trim();
  if (!s) return undefined;
  const n = parseArabicNumber(s);
  return Number.isFinite(n) ? n : undefined;
}

function defaultUnitConversion(unitName: string): number {
  const norm = normalizeHeaderCell(unitName);
  if (norm.includes("درزن") || norm.includes("دسته")) return 12;
  return 1;
}

type ColumnMap = {
  legacyId?: number;
  sku?: number;
  name?: number;
  unit?: number;
  avgCost?: number;
  sellingPrice?: number;
  unit2?: number;
  count2?: number;
  sprice2?: number;
  unit3?: number;
  count3?: number;
  sprice3?: number;
  currencyCode?: number;
  isActive?: number;
  defaultUnit?: number;
  quantity?: number;
  minThreshold?: number;
  expiryDate?: number;
};

function detectColumnMap(headerRow: unknown[]): ColumnMap {
  const map: ColumnMap = {};
  const headers = headerRow.map(normalizeHeaderCell);

  headers.forEach((h, idx) => {
    if (!h) return;

    if (
      map.name === undefined &&
      (h === "اسم الصنف" ||
        h === "الصنف" ||
        h === "الاسم" ||
        h === "اسم الماده" ||
        h === "اسم المنتج" ||
        h === "name" ||
        h === "item" ||
        h === "item name" ||
        h === "product" ||
        h === "product name")
    ) {
      map.name = idx;
      return;
    }

    if (
      map.sku === undefined &&
      (h === "الباركود" ||
        h === "باركود" ||
        h === "الرمز" ||
        h === "رمز الصنف" ||
        h === "الكود" ||
        h === "كود الصنف" ||
        h === "sku" ||
        h === "barcode" ||
        h === "code")
    ) {
      map.sku = idx;
      return;
    }

    if (
      map.legacyId === undefined &&
      (h === "الرقم" || h === "رقم الصنف" || h === "م" || h === "id" || h === "no" || h === "#")
    ) {
      map.legacyId = idx;
      return;
    }

    if (
      map.unit === undefined &&
      (h === "الوحده" ||
        h === "الوحده1" ||
        h === "الوحده 1" ||
        h === "وحده" ||
        h === "وحده1" ||
        h === "الوحده الاساسيه" ||
        h === "unit" ||
        h === "unit1" ||
        h === "unit 1")
    ) {
      map.unit = idx;
      return;
    }

    if (
      map.unit2 === undefined &&
      (h === "الوحده2" || h === "الوحده 2" || h === "وحده2" || h === "وحده 2" || h === "unit2" || h === "unit 2")
    ) {
      map.unit2 = idx;
      return;
    }

    if (
      map.unit3 === undefined &&
      (h === "الوحده3" || h === "الوحده 3" || h === "وحده3" || h === "وحده 3" || h === "unit3" || h === "unit 3")
    ) {
      map.unit3 = idx;
      return;
    }

    if (
      map.count2 === undefined &&
      (h === "العبوه 2" || h === "العبوه2" || h === "عبوه 2" || h === "عدد 2" || h === "عدد2" || h === "count2")
    ) {
      map.count2 = idx;
      return;
    }

    if (
      map.count3 === undefined &&
      (h === "العبوه 3" || h === "العبوه3" || h === "عبوه 3" || h === "عدد 3" || h === "عدد3" || h === "count3")
    ) {
      map.count3 = idx;
      return;
    }

    if (
      map.avgCost === undefined &&
      (h.includes("التكلفه") ||
        h.includes("تكلفه") ||
        h.includes("سعر الشراء") ||
        h === "الشراء" ||
        h === "cost" ||
        h === "avg cost" ||
        h === "buy price" ||
        h === "purchase price")
    ) {
      map.avgCost = idx;
      return;
    }

    if (h === "سعر 2" || h === "سعر2" || h === "سعر البيع 2" || h === "سعر البيع2" || h === "sprice2" || h === "price2") {
      if (map.sprice2 === undefined) map.sprice2 = idx;
      return;
    }

    if (h === "سعر 3" || h === "سعر3" || h === "سعر البيع 3" || h === "سعر البيع3" || h === "sprice3" || h === "price3") {
      if (map.sprice3 === undefined) map.sprice3 = idx;
      return;
    }

    if (
      h === "سعر البيع" ||
      h === "سعر البيع 1" ||
      h === "سعر البيع1" ||
      h === "سعر بيع" ||
      h === "البيع" ||
      h === "price" ||
      h === "sell price" ||
      h === "selling price"
    ) {
      // Handle repeated "سعر البيع" columns in exports like الاصناف.xls:
      // 1st -> sellingPrice, after unit2 -> sprice2, after unit3 -> sprice3
      if (map.unit3 !== undefined && idx > map.unit3 && map.sprice3 === undefined) {
        map.sprice3 = idx;
      } else if (map.unit2 !== undefined && idx > map.unit2 && map.sprice2 === undefined) {
        map.sprice2 = idx;
      } else if (map.sellingPrice === undefined) {
        map.sellingPrice = idx;
      } else if (map.sprice2 === undefined) {
        map.sprice2 = idx;
      } else if (map.sprice3 === undefined) {
        map.sprice3 = idx;
      }
      return;
    }

    if (map.currencyCode === undefined && (h === "العمله" || h === "عمله" || h === "currency")) {
      map.currencyCode = idx;
      return;
    }

    if (map.isActive === undefined && (h === "الحاله" || h === "حاله" || h === "status" || h === "active")) {
      map.isActive = idx;
      return;
    }

    if (
      map.defaultUnit === undefined &&
      (h === "الوحده الافتراضيه" || h === "وحده افتراضيه" || h === "default unit")
    ) {
      map.defaultUnit = idx;
      return;
    }

    if (
      map.quantity === undefined &&
      (h === "الكميه" || h === "كميه" || h === "الرصيد" || h === "رصيد" || h === "المتوفر" || h === "qty" || h === "quantity")
    ) {
      map.quantity = idx;
      return;
    }

    if (
      map.minThreshold === undefined &&
      (h === "الحد الادني" || h === "حد الطلب" || h === "حد ادني" || h === "min threshold" || h === "min qty")
    ) {
      map.minThreshold = idx;
      return;
    }

    if (
      map.expiryDate === undefined &&
      (h.includes("الانتهاء") || h.includes("الصلاحيه") || h === "expiry" || h === "expiry date")
    ) {
      map.expiryDate = idx;
    }
  });

  return map;
}

function findHeaderRowIndex(rows: unknown[][]): { headerIndex: number; map: ColumnMap } {
  const maxScan = Math.min(rows.length, 15);
  for (let i = 0; i < maxScan; i += 1) {
    const row = rows[i];
    if (!Array.isArray(row) || row.length === 0) continue;
    const map = detectColumnMap(row);
    if (map.name !== undefined) {
      return { headerIndex: i, map };
    }
  }
  return { headerIndex: -1, map: {} };
}

function isBinarySpreadsheet(bytes: Uint8Array): boolean {
  if (bytes.length < 4) return false;
  // ZIP (.xlsx / .xlsm / .ods): PK\x03\x04
  if (bytes[0] === 0x50 && bytes[1] === 0x4b && bytes[2] === 0x03 && bytes[3] === 0x04) {
    return true;
  }
  // OLE2 Compound Document (.xls BIFF8): D0 CF 11 E0
  if (bytes[0] === 0xd0 && bytes[1] === 0xcf && bytes[2] === 0x11 && bytes[3] === 0xe0) {
    return true;
  }
  // Legacy BIFF2-5 BOF record: 09 00 / 09 02 / 09 04 / 09 08
  if (bytes[0] === 0x09 && (bytes[1] === 0x00 || bytes[1] === 0x02 || bytes[1] === 0x04 || bytes[1] === 0x08)) {
    return true;
  }
  return false;
}

export function parseItemsSpreadsheetBytes(
  bytes: Uint8Array,
  defaultCurrency: CurrencyCode = "ريال",
): ParsedItemsImportResult {
  let workbook: XLSX.WorkBook;
  if (!isBinarySpreadsheet(bytes)) {
    try {
      const text = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
      workbook = XLSX.read(text, { type: "string", raw: false });
    } catch {
      workbook = XLSX.read(bytes, { type: "array", raw: false });
    }
  } else {
    workbook = XLSX.read(bytes, { type: "array", raw: false });
  }
  const sheetName = workbook.SheetNames[0];
  if (!sheetName) {
    throw new Error("الملف لا يحتوي على أي ورقة بيانات صالحة.");
  }
  const sheet = workbook.Sheets[sheetName];
  const rows = XLSX.utils.sheet_to_json<unknown[]>(sheet, {
    header: 1,
    defval: "",
    blankrows: false,
  });

  if (!rows.length) {
    throw new Error("الملف فارغ ولا يحتوي على صفوف أصناف.");
  }

  let { headerIndex, map } = findHeaderRowIndex(rows);
  if (headerIndex === -1) {
    // Fallback for headerless simple CSV/Excel: [name, sku, unit, avgCost, sellingPrice]
    headerIndex = -1;
    map = { name: 0, sku: 1, unit: 2, avgCost: 3, sellingPrice: 4 };
  }

  const items: ImportedInventoryItemInput[] = [];
  let skippedRows = 0;

  for (let r = headerIndex + 1; r < rows.length; r += 1) {
    const row = rows[r];
    if (!Array.isArray(row)) {
      skippedRows += 1;
      continue;
    }
    const name = cleanTextCell(map.name !== undefined ? row[map.name] : "");
    if (!name || normalizeHeaderCell(name) === "اسم الصنف" || normalizeHeaderCell(name) === "الاسم") {
      skippedRows += 1;
      continue;
    }

    const sku = map.sku !== undefined ? cleanTextCell(row[map.sku]) : "";
    const unit = (map.unit !== undefined ? cleanTextCell(row[map.unit]) : "") || "حبة";
    const avgCostRaw = map.avgCost !== undefined ? parseOptionalNumber(row[map.avgCost]) : undefined;
    const avgCost = avgCostRaw !== undefined && avgCostRaw >= 0 ? avgCostRaw : 0;

    const sellingPriceRaw = map.sellingPrice !== undefined ? parseOptionalNumber(row[map.sellingPrice]) : undefined;
    const sellingPrice = sellingPriceRaw !== undefined && sellingPriceRaw >= 0 ? sellingPriceRaw : undefined;

    let unit2 = map.unit2 !== undefined ? cleanTextCell(row[map.unit2]) : "";
    let count2 = map.count2 !== undefined ? parseOptionalNumber(row[map.count2]) : undefined;
    let sprice2 = map.sprice2 !== undefined ? parseOptionalNumber(row[map.sprice2]) : undefined;

    let unit3 = map.unit3 !== undefined ? cleanTextCell(row[map.unit3]) : "";
    let count3 = map.count3 !== undefined ? parseOptionalNumber(row[map.count3]) : undefined;
    let sprice3 = map.sprice3 !== undefined ? parseOptionalNumber(row[map.sprice3]) : undefined;

    if (unit3 && !unit2) {
      unit2 = unit3;
      count2 = count3;
      sprice2 = sprice3;
      unit3 = "";
      count3 = undefined;
      sprice3 = undefined;
    }
    if (unit2 && !(count2 && count2 > 0)) {
      count2 = defaultUnitConversion(unit2);
    }
    if (unit3 && !(count3 && count3 > 0)) {
      count3 = defaultUnitConversion(unit3);
    }

    const currencyRaw = map.currencyCode !== undefined ? cleanTextCell(row[map.currencyCode]) : "";
    const currencyCode = (currencyRaw || defaultCurrency || "ريال") as CurrencyCode;

    const statusRaw = map.isActive !== undefined ? normalizeHeaderCell(row[map.isActive]) : "";
    const isActive =
      statusRaw === "موقف" ||
      statusRaw === "غير نشط" ||
      statusRaw === "معطل" ||
      statusRaw === "0" ||
      statusRaw === "false" ||
      statusRaw === "inactive"
        ? false
        : true;

    let defaultUnit: 1 | 2 | 3 = 1;
    if (map.defaultUnit !== undefined) {
      const defRaw = cleanTextCell(row[map.defaultUnit]);
      const defNorm = normalizeHeaderCell(defRaw);
      if (defRaw === "2" || (unit2 && defNorm === normalizeHeaderCell(unit2))) {
        defaultUnit = 2;
      } else if (defRaw === "3" || (unit3 && defNorm === normalizeHeaderCell(unit3))) {
        defaultUnit = 3;
      }
    }

    const legacyIdRaw = map.legacyId !== undefined ? parseOptionalNumber(row[map.legacyId]) : undefined;
    const legacyId = legacyIdRaw !== undefined && Number.isInteger(legacyIdRaw) && legacyIdRaw > 0 ? legacyIdRaw : undefined;

    const minThresholdRaw = map.minThreshold !== undefined ? parseOptionalNumber(row[map.minThreshold]) : undefined;
    const expiryDate = map.expiryDate !== undefined ? cleanTextCell(row[map.expiryDate]) : "";

    items.push({
      name: name.slice(0, 120),
      sku: sku.slice(0, 64),
      unit: unit.slice(0, 32),
      quantity: 0,
      avgCost,
      ...(sellingPrice !== undefined ? { sellingPrice } : {}),
      ...(unit2 ? { unit2: unit2.slice(0, 32), count2, ...(sprice2 !== undefined && sprice2 >= 0 ? { sprice2 } : {}) } : {}),
      ...(unit3 ? { unit3: unit3.slice(0, 32), count3, ...(sprice3 !== undefined && sprice3 >= 0 ? { sprice3 } : {}) } : {}),
      defaultUnit,
      currencyCode,
      isActive,
      ...(legacyId !== undefined ? { legacyId } : {}),
      ...(minThresholdRaw !== undefined && minThresholdRaw >= 0 ? { minThreshold: minThresholdRaw } : {}),
      ...(expiryDate ? { expiryDate: expiryDate.slice(0, 32) } : {}),
      quantityUnverified: false,
    });
  }

  return { items, skippedRows, sheetName };
}
