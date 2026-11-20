import initSqlJs, { type Database, type SqlJsStatic } from "sql.js";
import type { LegacyPayload, LegacyTable } from "./legacyFinancialStaging";

let sqlPromise: Promise<SqlJsStatic> | null = null;

export async function getSqlJs(): Promise<SqlJsStatic> {
  if (!sqlPromise) {
    if (typeof window !== "undefined") {
      try {
        const wasmModule = await import("sql.js/dist/sql-wasm.wasm?url");
        sqlPromise = initSqlJs({
          locateFile: () => wasmModule.default,
        });
      } catch {
        sqlPromise = initSqlJs();
      }
    } else {
      sqlPromise = initSqlJs();
    }
  }
  return sqlPromise;
}

export const SQLITE_HEADER = "SQLite format 3\0";

export function isSqliteBinary(bytes: Uint8Array): boolean {
  if (bytes.length < 16) return false;
  const header = String.fromCharCode(...bytes.slice(0, 16));
  return header === SQLITE_HEADER || header.startsWith("SQLite format 3");
}

export async function computeSha256(bytes: Uint8Array): Promise<string> {
  if (typeof crypto !== "undefined" && crypto.subtle) {
    const copy = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer;
    const hashBuffer = await crypto.subtle.digest("SHA-256", copy);
    const hashArray = Array.from(new Uint8Array(hashBuffer));
    return hashArray.map((b) => b.toString(16).padStart(2, "0")).join("");
  }
  const g = globalThis as unknown as {
    require?: (mod: string) => {
      createHash: (algo: string) => {
        update: (buf: Uint8Array) => { digest: (enc: string) => string };
      };
    };
  };
  if (typeof g.require === "function") {
    return g.require("crypto").createHash("sha256").update(bytes).digest("hex");
  }
  throw new Error("بيئة التشفير غير مدعومة لحساب بصمة SHA-256.");
}

export type SqliteColumnInfo = {
  cid: number;
  name: string;
  type: string;
  notnull: number;
  dflt_value: unknown;
  pk: number;
};

export type SqliteForeignKey = {
  id: number;
  seq: number;
  table: string;
  from: string;
  to: string;
  on_update?: string;
  on_delete?: string;
};

export type SqliteIndexInfo = {
  seq: number;
  name: string;
  unique: number;
  origin: string;
  partial: number;
};

export type SqliteTableInspection = {
  name: string;
  rowCount: number;
  columns: SqliteColumnInfo[];
  foreignKeys: SqliteForeignKey[];
  indexes: SqliteIndexInfo[];
  sampleRows: Record<string, unknown>[];
  sql?: string;
};

export type SqliteMismatchReport = {
  missingCustomerRefs: number;
  missingProductRefs: number;
  missingInvoiceRefs: number;
  unregisteredCurrencyRefs: number;
  bothAmountsPositive: number;
  bothAmountsZero: number;
  warnings: string[];
  mappedModules: {
    customers: number;
    inventory: number;
    warehouses: number;
    cashBoxes: number;
    currencies: number;
    invoicesAndMoves: number;
    invoiceDetails: number;
    storeTransfers: number;
    archivedBin: number;
  };
};

export type SqliteInspectionResult = {
  sourceSha256: string;
  fileName: string;
  fileSize: number;
  integrity: string;
  userVersion: number;
  tables: SqliteTableInspection[];
  totalRows: number;
  tableCounts: Record<string, number>;
  mismatches: SqliteMismatchReport;
};

export async function inspectSqliteBinary(
  bytes: Uint8Array,
  fileName: string = "nasqo_exact_original.sqlite",
): Promise<{ inspection: SqliteInspectionResult; db: Database }> {
  if (!isSqliteBinary(bytes)) {
    throw new Error("الملف المحدد ليس قاعدة بيانات SQLite صالحة (توقيع الملف غير مطابق لـ SQLite format 3).");
  }

  const sha256 = await computeSha256(bytes);
  const SQL = await getSqlJs();
  const db = new SQL.Database(bytes);

  // 1. Integrity check
  let integrity = "ok";
  try {
    const res = db.exec("PRAGMA integrity_check;");
    if (res.length > 0 && res[0].values.length > 0) {
      integrity = String(res[0].values[0][0]);
    }
  } catch (err) {
    integrity = err instanceof Error ? err.message : "فشل فحص سلامة الملف";
  }

  // 2. User version
  let userVersion = 0;
  try {
    const uvRes = db.exec("PRAGMA user_version;");
    if (uvRes.length > 0 && uvRes[0].values.length > 0) {
      userVersion = Number(uvRes[0].values[0][0]) || 0;
    }
  } catch {
    // ignore
  }

  // 3. Extract user tables
  const tablesRes = db.exec(
    "SELECT name, sql FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name;",
  );

  const rawTables = tablesRes.length > 0 ? tablesRes[0].values : [];
  const tables: SqliteTableInspection[] = [];
  const tableCounts: Record<string, number> = {};
  let totalRows = 0;

  for (const [nameVal, sqlVal] of rawTables) {
    const tableName = String(nameVal);
    const sql = typeof sqlVal === "string" ? sqlVal : "";

    // Count rows
    let rowCount = 0;
    try {
      const cntRes = db.exec(`SELECT COUNT(*) FROM [${tableName}];`);
      rowCount = Number(cntRes[0].values[0][0]) || 0;
    } catch {
      rowCount = 0;
    }
    tableCounts[tableName] = rowCount;
    totalRows += rowCount;

    // Table columns
    const columns: SqliteColumnInfo[] = [];
    try {
      const colRes = db.exec(`PRAGMA table_info([${tableName}]);`);
      if (colRes.length > 0) {
        for (const row of colRes[0].values) {
          columns.push({
            cid: Number(row[0]),
            name: String(row[1]),
            type: String(row[2]),
            notnull: Number(row[3]),
            dflt_value: row[4],
            pk: Number(row[5]),
          });
        }
      }
    } catch {
      // ignore
    }

    // Foreign keys
    const foreignKeys: SqliteForeignKey[] = [];
    try {
      const fkRes = db.exec(`PRAGMA foreign_key_list([${tableName}]);`);
      if (fkRes.length > 0) {
        for (const row of fkRes[0].values) {
          foreignKeys.push({
            id: Number(row[0]),
            seq: Number(row[1]),
            table: String(row[2]),
            from: String(row[3]),
            to: String(row[4]),
            on_update: row[5] ? String(row[5]) : undefined,
            on_delete: row[6] ? String(row[6]) : undefined,
          });
        }
      }
    } catch {
      // ignore
    }

    // Indexes
    const indexes: SqliteIndexInfo[] = [];
    try {
      const idxRes = db.exec(`PRAGMA index_list([${tableName}]);`);
      if (idxRes.length > 0) {
        for (const row of idxRes[0].values) {
          indexes.push({
            seq: Number(row[0]),
            name: String(row[1]),
            unique: Number(row[2]),
            origin: String(row[3]),
            partial: Number(row[4]),
          });
        }
      }
    } catch {
      // ignore
    }

    // Sample rows (first 10)
    const sampleRows: Record<string, unknown>[] = [];
    try {
      const smpRes = db.exec(`SELECT * FROM [${tableName}] LIMIT 10;`);
      if (smpRes.length > 0) {
        const colNames = smpRes[0].columns;
        for (const r of smpRes[0].values) {
          const item: Record<string, unknown> = {};
          colNames.forEach((c, i) => {
            item[c] = r[i];
          });
          sampleRows.push(item);
        }
      }
    } catch {
      // ignore
    }

    tables.push({
      name: tableName,
      rowCount,
      columns,
      foreignKeys,
      indexes,
      sampleRows,
      sql,
    });
  }

  // 4. Mismatch & Relation Audit
  const mismatches = auditSqliteRelations(db, tableCounts);

  const inspection: SqliteInspectionResult = {
    sourceSha256: sha256,
    fileName,
    fileSize: bytes.length,
    integrity,
    userVersion,
    tables,
    totalRows,
    tableCounts,
    mismatches,
  };

  return { inspection, db };
}

function auditSqliteRelations(db: Database, tableCounts: Record<string, number>): SqliteMismatchReport {
  let missingCustomerRefs = 0;
  let missingProductRefs = 0;
  let missingInvoiceRefs = 0;
  let unregisteredCurrencyRefs = 0;
  let bothAmountsPositive = 0;
  let bothAmountsZero = 0;
  const warnings: string[] = [];

  // 1. Audit input_move foreign references and amount semantics
  if (tableCounts.input_move) {
    try {
      const amtRes = db.exec(`
        SELECT 
          SUM(CASE WHEN CAST(dain AS REAL) > 0 AND CAST(madin AS REAL) > 0 THEN 1 ELSE 0 END) AS both_pos,
          SUM(CASE WHEN CAST(dain AS REAL) = 0 AND CAST(madin AS REAL) = 0 THEN 1 ELSE 0 END) AS both_zero
        FROM [input_move];
      `);
      if (amtRes.length > 0 && amtRes[0].values.length > 0) {
        bothAmountsPositive = Number(amtRes[0].values[0][0]) || 0;
        bothAmountsZero = Number(amtRes[0].values[0][1]) || 0;
      }
    } catch {
      // ignore
    }

    // Check missing customer references in input_move
    if (tableCounts.customers) {
      try {
        const mcRes = db.exec(`
          SELECT COUNT(*) FROM [input_move] m
          WHERE m.per_id IS NOT NULL AND m.per_id != '' AND m.per_id != 0
            AND NOT EXISTS (SELECT 1 FROM [customers] c WHERE c.id = m.per_id);
        `);
        missingCustomerRefs = Number(mcRes[0].values[0][0]) || 0;
      } catch {
        // ignore
      }
    }

    // Check unregistered currency references in input_move
    if (tableCounts.currencies) {
      try {
        const curRes = db.exec(`
          SELECT COUNT(*) FROM [input_move] m
          WHERE m.cur IS NOT NULL AND m.cur != '' AND m.cur != 0
            AND NOT EXISTS (SELECT 1 FROM [currencies] c WHERE c.id = m.cur);
        `);
        unregisteredCurrencyRefs = Number(curRes[0].values[0][0]) || 0;
      } catch {
        // ignore
      }
    }
  }

  // 2. Audit bill_details references
  if (tableCounts.bill_details) {
    if (tableCounts.products) {
      try {
        const mpRes = db.exec(`
          SELECT COUNT(*) FROM [bill_details] b
          WHERE b.prod_id IS NOT NULL AND b.prod_id != '' AND b.prod_id != 0
            AND NOT EXISTS (SELECT 1 FROM [products] p WHERE p.id = b.prod_id);
        `);
        missingProductRefs += Number(mpRes[0].values[0][0]) || 0;
      } catch {
        // ignore
      }
    }

    if (tableCounts.input_move) {
      try {
        const miRes = db.exec(`
          SELECT COUNT(*) FROM [bill_details] b
          WHERE b.bill_id IS NOT NULL AND b.bill_id != ''
            AND NOT EXISTS (SELECT 1 FROM [input_move] m WHERE m.id = b.bill_id);
        `);
        missingInvoiceRefs += Number(miRes[0].values[0][0]) || 0;
      } catch {
        // ignore
      }
    }
  }

  // 3. Audit bill_details2 references
  if (tableCounts.bill_details2 && tableCounts.input_move) {
    try {
      const mi2Res = db.exec(`
        SELECT COUNT(*) FROM [bill_details2] b
        WHERE b.bill_id IS NOT NULL AND b.bill_id != ''
          AND NOT EXISTS (SELECT 1 FROM [input_move] m WHERE m.id = b.bill_id);
      `);
      missingInvoiceRefs += Number(mi2Res[0].values[0][0]) || 0;
    } catch {
      // ignore
    }
  }

  if (bothAmountsPositive > 0) {
    warnings.push(`${bothAmountsPositive} حركة مالية فيها قيمتان موجبتان في دائن ومدين: تتطلب مراجعة دلالات العملية.`);
  }
  if (bothAmountsZero > 0) {
    warnings.push(`${bothAmountsZero} حركات مالية قيمتها صفر في كلا الحقلين.`);
  }
  if (unregisteredCurrencyRefs > 0) {
    warnings.push(`${unregisteredCurrencyRefs} حركة تستخدم معرّف عملة غير مسجل بجدول العملات.`);
  }
  if (missingCustomerRefs > 0) {
    warnings.push(`${missingCustomerRefs} حركة مالية ترتبط بمعرف عميل غير موجود.`);
  }
  if (missingProductRefs > 0) {
    warnings.push(`${missingProductRefs} بند فاتورة يرتبط بصنف غير موجود.`);
  }
  if (missingInvoiceRefs > 0) {
    warnings.push(`${missingInvoiceRefs} بند فاتورة يرتبط برقم حركة غير موجود.`);
  }

  warnings.push("يتم استيراد وحفظ الأرشيف في وضع المعاينة والمراجعة المحاسبية دون التأثير على القيود المالية الحية.");

  return {
    missingCustomerRefs,
    missingProductRefs,
    missingInvoiceRefs,
    unregisteredCurrencyRefs,
    bothAmountsPositive,
    bothAmountsZero,
    warnings,
    mappedModules: {
      customers: tableCounts.customers ?? 0,
      inventory: tableCounts.products ?? 0,
      warehouses: tableCounts.stores ?? 0,
      cashBoxes: tableCounts.boxes ?? 0,
      currencies: tableCounts.currencies ?? 0,
      invoicesAndMoves: tableCounts.input_move ?? 0,
      invoiceDetails: (tableCounts.bill_details ?? 0) + (tableCounts.bill_details2 ?? 0),
      storeTransfers: tableCounts.store_trans ?? 0,
      archivedBin: tableCounts.bin ?? 0,
    },
  };
}

export function querySqliteTable(
  db: Database,
  table: string,
  limit: number = 50,
  offset: number = 0,
): { columns: string[]; rows: Record<string, unknown>[]; total: number } {
  if (!/^[a-z_][a-z0-9_]*$/i.test(table)) {
    throw new Error("اسم الجدول غير مسموح به.");
  }
  const cntRes = db.exec(`SELECT COUNT(*) FROM [${table}];`);
  const total = cntRes.length > 0 ? Number(cntRes[0].values[0][0]) || 0 : 0;

  const dataRes = db.exec(`SELECT * FROM [${table}] LIMIT ${Math.max(1, limit)} OFFSET ${Math.max(0, offset)};`);
  if (dataRes.length === 0) {
    return { columns: [], rows: [], total };
  }
  const columns = dataRes[0].columns;
  const rows: Record<string, unknown>[] = [];
  for (const valRow of dataRes[0].values) {
    const item: Record<string, unknown> = {};
    columns.forEach((c, i) => {
      item[c] = valRow[i];
    });
    rows.push(item);
  }
  return { columns, rows, total };
}

export function convertSqliteToLegacyPayload(
  db: Database,
  sourceSha256: string,
  fileName: string = "nasqo_exact_original.sqlite",
  userVersion: number = 0,
): LegacyPayload {
  const tablesRes = db.exec(
    "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name;",
  );
  const tableNames = tablesRes.length > 0 ? tablesRes[0].values.map((v) => String(v[0])) : [];

  const tables: Record<string, LegacyTable> = {};

  for (const name of tableNames) {
    const colRes = db.exec(`PRAGMA table_info([${name}]);`);
    const columns = colRes.length > 0 ? colRes[0].values.map((c) => String(c[1])) : [];

    const dataRes = db.exec(`SELECT * FROM [${name}];`);
    const rows: Record<string, unknown>[] = [];
    if (dataRes.length > 0) {
      const colNames = dataRes[0].columns;
      for (const valRow of dataRes[0].values) {
        const item: Record<string, unknown> = {};
        colNames.forEach((c, i) => {
          item[c] = valRow[i];
        });
        rows.push(item);
      }
    }
    tables[name] = { columns, rows };
  }

  return {
    format: "nasqo-legacy-financial-staging-v1",
    version: 1,
    sourceSha256,
    sourceName: fileName,
    sourceUserVersion: userVersion,
    tables,
  };
}
