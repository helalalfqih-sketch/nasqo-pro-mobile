import { useCallback, useEffect, useMemo, useState } from "react";
import { KeyboardInput, MobileScroll } from "../mobile";
import { hybridBridge } from "./bridge";
import { validateHybridSnapshot, type HybridWorkspaceSnapshot } from "./contracts";
import { LOCAL_WORKSPACE_UID } from "./serviceAdapter";
import "../components/erp/SmartProControlScreen.css";

type OfflineTab = "accounts" | "ledger" | "inventory" | "reports";

function formatLocalNumber(value: unknown): string {
  const num = typeof value === "number" ? value : Number(value ?? 0);
  if (!Number.isFinite(num)) return "0";
  return num.toLocaleString("en-US", { maximumFractionDigits: 2 });
}

/**
 * Pure-offline local SQLite control screen replacing the web-server
 * SmartProControlScreen inside the Flutter Android Hybrid bundle.
 *
 * Guarantees:
 * - Zero HTTP/fetch requests (100% Airplane Mode compatible).
 * - Reads live records directly from Dart SQLite via `window.NasqoHome`.
 * - Preserves per-currency separation in financial summaries.
 */
export function SmartProControlScreen() {
  const [snapshot, setSnapshot] = useState<HybridWorkspaceSnapshot | null>(null);
  const [tab, setTab] = useState<OfflineTab>("accounts");
  const [search, setSearch] = useState("");
  const [busy, setBusy] = useState(true);
  const [error, setError] = useState("");

  const loadLocalSnapshot = useCallback(async () => {
    setBusy(true);
    setError("");
    try {
      const raw = await hybridBridge.invoke<"getSnapshot", unknown>(
        "getSnapshot",
        { workspaceId: LOCAL_WORKSPACE_UID, forceRefresh: true },
        { timeoutMs: 10_000 },
      );
      const checked = validateHybridSnapshot(raw);
      if (!checked.valid) {
        throw new Error(checked.reason);
      }
      setSnapshot(checked.value);
    } catch (err) {
      setError(
        err instanceof Error
          ? err.message
          : "تعذر قراءة البيانات المحلية من SQLite.",
      );
    } finally {
      setBusy(false);
    }
  }, []);

  useEffect(() => {
    void loadLocalSnapshot();
    const unsub = hybridBridge.onHostEvent<unknown>("snapshotUpdated", (raw) => {
      const checked = validateHybridSnapshot(raw);
      if (checked.valid) {
        setSnapshot(checked.value);
      }
    });
    return unsub;
  }, [loadLocalSnapshot]);

  const query = search.trim().toLowerCase();

  const filteredAccounts = useMemo(() => {
    const items = snapshot?.accounts ?? [];
    if (!query) return items;
    return items.filter(
      (a) =>
        a.name.toLowerCase().includes(query) ||
        (a.phone ?? "").toLowerCase().includes(query) ||
        (a.currency ?? "").toLowerCase().includes(query),
    );
  }, [snapshot?.accounts, query]);

  const filteredLedger = useMemo(() => {
    const items = (snapshot?.ledger ?? []).filter((e) => !e.deleted);
    if (!query) return items;
    return items.filter(
      (e) =>
        e.accountName.toLowerCase().includes(query) ||
        e.typeLabel.toLowerCase().includes(query) ||
        (e.details ?? "").toLowerCase().includes(query) ||
        String(e.entryNumber ?? "").includes(query),
    );
  }, [snapshot?.ledger, query]);

  const filteredInventory = useMemo(() => {
    const items = snapshot?.inventory ?? [];
    if (!query) return items;
    return items.filter(
      (item) =>
        item.name.toLowerCase().includes(query) ||
        (item.sku ?? "").toLowerCase().includes(query) ||
        (item.unit ?? "").toLowerCase().includes(query),
    );
  }, [snapshot?.inventory, query]);

  const currencyTotals = useMemo(() => {
    const map = new Map<string, { debit: number; credit: number; count: number }>();
    for (const entry of snapshot?.ledger ?? []) {
      if (entry.deleted) continue;
      const curr = entry.currency || "ريال";
      const bucket = map.get(curr) ?? { debit: 0, credit: 0, count: 0 };
      if (entry.direction === "debit") {
        bucket.debit += Number(entry.amount) || 0;
      } else {
        bucket.credit += Number(entry.amount) || 0;
      }
      bucket.count += 1;
      map.set(curr, bucket);
    }
    return Array.from(map.entries());
  }, [snapshot?.ledger]);

  return (
    <div className="sp-shell" dir="rtl" data-testid="smartpro-offline-panel">
      <header className="sp-header">
        <div>
          <h1 className="sp-title">إدارة البيانات المحلية (SQLite دون إنترنت)</h1>
          <p className="sp-sub">
            {snapshot?.workspace?.companyName ?? "نسقو برو"} • مصدر البيانات: قاعدة SQLite المحلية على الجهاز
          </p>
        </div>
        <button
          type="button"
          className="sp-btn"
          onClick={() => void loadLocalSnapshot()}
          disabled={busy}
        >
          {busy ? "جاري التحديث..." : "تحديث محلي"}
        </button>
      </header>

      <nav className="sp-tabs" aria-label="أقسام البيانات المحلية">
        {(
          [
            ["accounts", `الحسابات (${snapshot?.accounts.length ?? 0})`],
            ["ledger", `الفواتير والسندات (${filteredLedger.length})`],
            ["inventory", `المخزون (${snapshot?.inventory.length ?? 0})`],
            ["reports", "ملخص العملات"],
          ] as const
        ).map(([id, label]) => (
          <button
            key={id}
            type="button"
            className={`sp-tab ${tab === id ? "is-active" : ""}`}
            onClick={() => setTab(id)}
          >
            {label}
          </button>
        ))}
      </nav>

      <div className="sp-toolbar">
        <KeyboardInput
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          placeholder="ابحث محليًا في الحسابات أو الفواتير أو الأصناف..."
          aria-label="بحث محلي"
        />
      </div>

      {error ? (
        <div className="sp-alert is-error" role="alert">
          {error}
        </div>
      ) : null}

      <MobileScroll className="sp-scroll">
        <div className="sp-list">
          {tab === "accounts" ? (
            filteredAccounts.length === 0 ? (
              <div className="sp-empty">لا توجد حسابات مسجلة بعد في قاعدة SQLite المحلية.</div>
            ) : (
              filteredAccounts.map((acc) => (
                <article key={acc.id} className="sp-card">
                  <div className="sp-card-top">
                    <strong>{acc.name}</strong>
                    <span>{acc.currency}</span>
                  </div>
                  <div className="sp-card-meta">
                    <span>التصنيف: {acc.category}</span>
                    {acc.phone ? <span>الهاتف: {acc.phone}</span> : null}
                  </div>
                </article>
              ))
            )
          ) : null}

          {tab === "ledger" ? (
            filteredLedger.length === 0 ? (
              <div className="sp-empty">لا توجد قيود أو فواتير مسجلة بعد في قاعدة SQLite المحلية.</div>
            ) : (
              filteredLedger.map((entry) => (
                <article key={entry.id} className="sp-card">
                  <div className="sp-card-top">
                    <strong>
                      #{entry.entryNumber} — {entry.typeLabel}
                    </strong>
                    <span>
                      {formatLocalNumber(entry.amount)} {entry.currency}
                    </span>
                  </div>
                  <div className="sp-card-meta">
                    <span>{entry.accountName}</span>
                    <span>{entry.entryDate}</span>
                  </div>
                  {entry.details ? <p className="sp-card-note">{entry.details}</p> : null}
                </article>
              ))
            )
          ) : null}

          {tab === "inventory" ? (
            filteredInventory.length === 0 ? (
              <div className="sp-empty">لا توجد أصناف مخزون مسجلة بعد.</div>
            ) : (
              filteredInventory.map((item) => (
                <article key={item.id} className="sp-card">
                  <div className="sp-card-top">
                    <strong>{item.name}</strong>
                    <span>
                      {formatLocalNumber(item.quantity)} {item.unit}
                    </span>
                  </div>
                  <div className="sp-card-meta">
                    <span>متوسط التكلفة: {formatLocalNumber(item.avgCost)}</span>
                    {item.sku ? <span>SKU: {item.sku}</span> : null}
                  </div>
                </article>
              ))
            )
          ) : null}

          {tab === "reports" ? (
            currencyTotals.length === 0 ? (
              <div className="sp-empty">لا توجد عمليات مالية ملخصة بعد — القاعدة نظيفة وفارغة.</div>
            ) : (
              currencyTotals.map(([curr, totals]) => (
                <article key={curr} className="sp-card">
                  <div className="sp-card-top">
                    <strong>عملة: {curr}</strong>
                    <span>{totals.count} قيد</span>
                  </div>
                  <div className="sp-card-meta">
                    <span>مدين: {formatLocalNumber(totals.debit)}</span>
                    <span>دائن: {formatLocalNumber(totals.credit)}</span>
                    <span>الصافي: {formatLocalNumber(totals.credit - totals.debit)}</span>
                  </div>
                </article>
              ))
            )
          ) : null}
        </div>
      </MobileScroll>
    </div>
  );
}
