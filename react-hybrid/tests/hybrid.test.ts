import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { afterEach, describe, it } from "node:test";
import {
  createIdempotencyKey,
  HYBRID_ALLOWED_COMMANDS,
  HYBRID_PROTOCOL_VERSION,
  validateHybridInboundMessage,
  validateHybridRequestEnvelope,
  validateHybridSnapshot,
  type HybridRequestEnvelope,
  type HybridWorkspaceSnapshot,
} from "../src/hybrid/contracts";
import { HybridBridgeError, hybridBridge, NasqoHybridBridge } from "../src/hybrid/bridge";
import { createHybridHomeFixtureSnapshot } from "../src/hybrid/homeFixture";
import {
  HYBRID_ROUTES,
  isValidHybridRoute,
  normalizeFlowScreenIdToHybridRoute,
} from "../src/hybrid/routes";
import {
  createLedgerEntry,
  createOrUpdateAccount,
  fetchCashboxesReport,
  fetchInventoryMovementsReport,
  LOCAL_WORKSPACE_UID,
  refreshWorkspaceFromServer,
} from "../src/hybrid/serviceAdapter";
import { computeAccountGroupsSummary } from "../src/accounting";
import {
  DEFAULT_HOME_TILE_LAYOUT,
  isDefaultHomeTileLayout,
  moveHomeTile,
  toggleHideHomeTile,
  togglePinHomeTile,
  toggleToneHomeTile,
} from "../src/utils/dashboardPrefs";

function createSampleSnapshot(): HybridWorkspaceSnapshot {
  return {
    workspaceId: LOCAL_WORKSPACE_UID,
    userEmail: "offline@nasqo.local",
    workspace: {
      id: LOCAL_WORKSPACE_UID,
      ownerId: LOCAL_WORKSPACE_UID,
      companyName: "مؤسسة نسقو للتجارة",
      defaultCurrency: "ريال",
      whatsappProvider: "nasqo",
      whatsappInstantEnabled: false,
      whatsappPhone: "777000111",
    },
    currencies: [
      { id: 1, code: "YER", name: "ريال", symbol: "ر.ي", ratePrimary: 1, rateSecondary: 1, nameSecondary: "فلس" },
      { id: 2, code: "USD", name: "دولار", symbol: "$", ratePrimary: 530, rateSecondary: 1, nameSecondary: "سنت" },
    ],
    accountGroups: [
      { id: 1, name: "الموردون", category: "purchases", currencyCode: "ريال", sortOrder: 1 },
      { id: 2, name: "العملاء", category: "clients", currencyCode: "ريال", sortOrder: 2 },
    ],
    accounts: [
      {
        id: "acc_sup_1",
        ownerId: LOCAL_WORKSPACE_UID,
        codeNumber: 101,
        name: "مؤسسة البراري للتوريد",
        category: "purchases",
        currency: "ريال",
        creditLimit: 0,
        isCashAccount: false,
        accountImage: "1",
        settlement: false,
        documentNumberRequired: false,
        messageMethod: "whatsapp",
        sendMode: "never",
        note: "",
        openingBalance: 0,
        openingDirection: "credit",
        sortOrder: 1,
        phone: "770123456",
        groupId: 1,
      },
      {
        id: "acc_cli_1",
        ownerId: LOCAL_WORKSPACE_UID,
        codeNumber: 201,
        name: "شركة الأفق للمبيعات",
        category: "clients",
        currency: "ريال",
        creditLimit: 0,
        isCashAccount: false,
        accountImage: "1",
        settlement: false,
        documentNumberRequired: false,
        messageMethod: "whatsapp",
        sendMode: "never",
        note: "",
        openingBalance: 15000,
        openingDirection: "debit",
        sortOrder: 2,
        phone: "771222333",
        groupId: 2,
      },
    ],
    cashboxes: [
      { id: 1, name: "الصندوق الرئيسي", details: "الصندوق النقدي العام", currencyCode: "ريال", isActive: true, state: 1 },
    ],
    ledger: [
      {
        id: "led_1",
        ownerId: LOCAL_WORKSPACE_UID,
        entryNumber: 1001,
        accountId: "acc_sup_1",
        accountName: "مؤسسة البراري للتوريد",
        counterpartAccountId: "",
        counterpartAccountName: "",
        kind: "invoice",
        typeLabel: "فاتورة مشتريات",
        direction: "credit",
        payment: "credit",
        amount: 25000,
        currency: "ريال",
        exchangeRate: 1,
        details: "فاتورة شراء بضاعة افتتاحية",
        documentNumber: "INV-1001",
        entryDate: "2026-11-20",
        deleted: false,
        createdAtMs: 1732100000000,
      },
    ],
    warehouses: [
      { id: "wh_main", ownerId: LOCAL_WORKSPACE_UID, codeNumber: 1, name: "المخزن الرئيسي", details: "", isDefault: true },
    ],
    inventory: [
      {
        id: "inv_1",
        ownerId: LOCAL_WORKSPACE_UID,
        sku: "SKU-001",
        name: "بطارية شمسية 200 أمبير",
        warehouseId: "wh_main",
        unit: "حبة",
        quantity: 12,
        avgCost: 42000,
        sellingPrice: 50000,
        minThreshold: 3,
      },
    ],
    snapshotVersion: 1,
  };
}

afterEach(() => {
  hybridBridge.resetForTesting();
});

describe("Hybrid Bridge Contracts & Security Validation", () => {
  it("accepts all 12 core commands plus domain commands in strict allowlist", () => {
    const core12 = [
      "navigate",
      "goBack",
      "getSnapshot",
      "changeCurrency",
      "saveUiPreferences",
      "openInvoice",
      "openVoucher",
      "openAccountStatement",
      "printDocument",
      "exportPdf",
      "pickFile",
      "showMessage",
    ];
    for (const cmd of core12) {
      assert.ok(
        (HYBRID_ALLOWED_COMMANDS as readonly string[]).includes(cmd),
        `Missing core command: ${cmd}`,
      );
    }
  });

  it("rejects unauthorized actions and raw SQL/shell injection keys", () => {
    const badAction = validateHybridRequestEnvelope({
      protocolVersion: HYBRID_PROTOCOL_VERSION,
      kind: "request",
      requestId: "req_bad_1",
      action: "execRawSql",
      payload: { sql: "DROP TABLE accounts" },
      timestampMs: Date.now(),
    });
    assert.equal(badAction.valid, false);

    const sqlPayload = validateHybridRequestEnvelope({
      protocolVersion: HYBRID_PROTOCOL_VERSION,
      kind: "request",
      requestId: "req_sql_1",
      action: "getSnapshot",
      payload: { workspaceId: "local", nested: { rawSql: "SELECT * FROM users" } },
      timestampMs: Date.now(),
    });
    assert.equal(sqlPayload.valid, false);
    if (!sqlPayload.valid) {
      assert.match(sqlPayload.reason, /rawSql/);
    }
  });

  it("enforces mandatory idempotencyKey on financial mutations", () => {
    const missingIdem = validateHybridRequestEnvelope({
      protocolVersion: HYBRID_PROTOCOL_VERSION,
      kind: "request",
      requestId: "req_fin_1",
      action: "createLedgerEntry",
      payload: { workspaceId: LOCAL_WORKSPACE_UID, payload: { accountId: "a1", accountName: "test" } },
      timestampMs: Date.now(),
    });
    assert.equal(missingIdem.valid, false);

    const withIdem = validateHybridRequestEnvelope({
      protocolVersion: HYBRID_PROTOCOL_VERSION,
      kind: "request",
      requestId: "req_fin_2",
      action: "createLedgerEntry",
      idempotencyKey: createIdempotencyKey("createLedgerEntry", "a1"),
      payload: { workspaceId: LOCAL_WORKSPACE_UID, payload: { accountId: "a1", accountName: "test" } },
      timestampMs: Date.now(),
    });
    assert.equal(withIdem.valid, true);
  });

  it("validates inbound responses and rejects malformed or unknown host events", () => {
    assert.equal(
      validateHybridInboundMessage({
        protocolVersion: HYBRID_PROTOCOL_VERSION,
        kind: "event",
        event: "backPressed",
        payload: {},
      }).valid,
      true,
    );
    assert.equal(
      validateHybridInboundMessage({
        protocolVersion: HYBRID_PROTOCOL_VERSION,
        kind: "event",
        event: "evalScript",
        payload: {},
      }).valid,
      false,
    );
    assert.equal(validateHybridInboundMessage("{invalid json").valid, false);
  });
});

describe("NasqoHybridBridge Runtime & Duplicate Prevention", () => {
  it("blocks duplicate concurrent financial mutations with DUPLICATE_REQUEST", async () => {
    const bridge = new NasqoHybridBridge();
    const sent: HybridRequestEnvelope[] = [];
    bridge.setTransportForTesting({
      postMessage: (json) => {
        sent.push(JSON.parse(json) as HybridRequestEnvelope);
      },
    });

    const p1 = bridge.invoke(
      "createLedgerEntry",
      {
        workspaceId: LOCAL_WORKSPACE_UID,
        payload: { accountId: "acc_1", accountName: "حساب اختبار", amount: 500 },
      },
      { dedupeKey: "invoice-submit-1" },
    );

    await assert.rejects(
      () =>
        bridge.invoke(
          "createLedgerEntry",
          {
            workspaceId: LOCAL_WORKSPACE_UID,
            payload: { accountId: "acc_1", accountName: "حساب اختبار", amount: 500 },
          },
          { dedupeKey: "invoice-submit-1" },
        ),
      (err: unknown) => err instanceof HybridBridgeError && err.code === "DUPLICATE_REQUEST",
    );

    assert.equal(sent.length, 1);
    assert.ok(sent[0].idempotencyKey && sent[0].idempotencyKey.startsWith("idem_createLedgerEntry_"));

    bridge.handleInbound({
      protocolVersion: HYBRID_PROTOCOL_VERSION,
      kind: "response",
      requestId: sent[0].requestId,
      ok: true,
      data: { entry: { id: "led_new" } },
    });

    const result = await p1;
    assert.deepEqual(result, { entry: { id: "led_new" } });
    assert.equal(bridge.isFinancialOperationInFlight("invoice-submit-1"), false);
  });

  it("propagates Flutter service errors and timeouts without faking success", async () => {
    const bridge = new NasqoHybridBridge();
    bridge.setTransportForTesting({
      postMessage: (json) => {
        const req = JSON.parse(json) as HybridRequestEnvelope;
        if (req.action === "saveAccount") {
          queueMicrotask(() => {
            bridge.handleInbound({
              protocolVersion: HYBRID_PROTOCOL_VERSION,
              kind: "response",
              requestId: req.requestId,
              ok: false,
              error: { code: "VALIDATION_ERROR", message: "اسم الحساب مكرر بالفعل في SQLite" },
            });
          });
        }
      },
    });

    await assert.rejects(
      () =>
        bridge.invoke("saveAccount", {
          workspaceId: LOCAL_WORKSPACE_UID,
          payload: { name: "حساب مكرر", category: "clients", currency: "ريال" },
        }),
      (err: unknown) =>
        err instanceof HybridBridgeError &&
        err.code === "VALIDATION_ERROR" &&
        err.message.includes("SQLite"),
    );

    await assert.rejects(
      () => bridge.invoke("getSnapshot", { workspaceId: LOCAL_WORKSPACE_UID }, { timeoutMs: 35 }),
      (err: unknown) => err instanceof HybridBridgeError && err.code === "TIMEOUT",
    );
  });

  it("rejects with SERVICE_UNAVAILABLE when no Flutter transport is attached", async () => {
    const bridge = new NasqoHybridBridge();
    await assert.rejects(
      () => bridge.invoke("getSnapshot", { workspaceId: LOCAL_WORKSPACE_UID }),
      (err: unknown) => err instanceof HybridBridgeError && err.code === "SERVICE_UNAVAILABLE",
    );
  });
});

describe("Hybrid Service Adapter Simulated Flutter Host Round-Trip", () => {
  it("hydrates workspace, creates accounts/ledger entries, and queries reports exclusively via bridge", async () => {
    const snapshot = createSampleSnapshot();
    const receivedActions: string[] = [];

    hybridBridge.setTransportForTesting({
      postMessage: (raw) => {
        const req = JSON.parse(raw) as HybridRequestEnvelope;
        receivedActions.push(req.action);
        queueMicrotask(() => {
          if (req.action === "getSnapshot") {
            hybridBridge.handleInbound({
              protocolVersion: HYBRID_PROTOCOL_VERSION,
              kind: "response",
              requestId: req.requestId,
              ok: true,
              data: snapshot,
            });
          } else if (req.action === "saveAccount") {
            const accPayload = (req.payload as { payload: Record<string, unknown> }).payload;
            const created = {
              id: "acc_new_99",
              ownerId: LOCAL_WORKSPACE_UID,
              codeNumber: 301,
              name: String(accPayload.name),
              category: "clients",
              currency: "ريال",
              phone: "",
              creditLimit: 0,
              isCashAccount: false,
              accountImage: "1",
              settlement: false,
              documentNumberRequired: false,
              messageMethod: "whatsapp",
              sendMode: "never",
              note: "",
              openingBalance: 0,
              openingDirection: "debit",
              sortOrder: 3,
            };
            hybridBridge.handleInbound({
              protocolVersion: HYBRID_PROTOCOL_VERSION,
              kind: "response",
              requestId: req.requestId,
              ok: true,
              data: { account: created },
            });
          } else if (req.action === "createLedgerEntry") {
            const entryPayload = (req.payload as { payload: Record<string, unknown> }).payload;
            hybridBridge.handleInbound({
              protocolVersion: HYBRID_PROTOCOL_VERSION,
              kind: "response",
              requestId: req.requestId,
              ok: true,
              data: {
                entry: {
                  id: "led_999",
                  ownerId: LOCAL_WORKSPACE_UID,
                  entryNumber: 1002,
                  accountId: entryPayload.accountId,
                  accountName: entryPayload.accountName,
                  counterpartAccountId: "",
                  counterpartAccountName: "",
                  kind: "voucher",
                  typeLabel: "سند قبض",
                  direction: "credit",
                  payment: "cash",
                  amount: entryPayload.amount ?? 1000,
                  currency: "ريال",
                  exchangeRate: 1,
                  details: "سند قبض عبر الجسر",
                  documentNumber: "V-1002",
                  entryDate: "2026-11-21",
                  deleted: false,
                  createdAtMs: 1732200000000,
                },
              },
            });
          } else if (req.action === "getInventoryMovementsReport") {
            hybridBridge.handleInbound({
              protocolVersion: HYBRID_PROTOCOL_VERSION,
              kind: "response",
              requestId: req.requestId,
              ok: true,
              data: {
                warehouses: [{ id: "wh_main", name: "المخزن الرئيسي" }],
                warehouseStocks: [],
                itemRows: [],
                totals: {
                  totalSales: 0,
                  totalPurchases: 0,
                  totalProfit: 0,
                  totalRemainingValue: 504000,
                  activeItemsCount: 1,
                  profitBasis: "avg",
                },
                movements: [],
                anomalies: {
                  unverifiedItemsCount: 0,
                  unresolvedTransfersCount: 0,
                  unresolvedTransfers: [],
                  negativeComputedItems: [],
                },
              },
            });
          } else if (req.action === "getCashboxesReport") {
            hybridBridge.handleInbound({
              protocolVersion: HYBRID_PROTOCOL_VERSION,
              kind: "response",
              requestId: req.requestId,
              ok: true,
              data: {
                cashboxes: [
                  {
                    id: 1,
                    name: "الصندوق الرئيسي",
                    currencyCode: "ريال",
                    totalIn: 10000,
                    totalOut: 2500,
                    netBalance: 7500,
                    entryCount: 4,
                  },
                ],
              },
            });
          }
        });
      },
    });

    const bundle = await refreshWorkspaceFromServer(LOCAL_WORKSPACE_UID);
    assert.equal(bundle.accounts.length, 2);
    assert.equal(bundle.inventory.length, 1);

    const newAccId = await createOrUpdateAccount(LOCAL_WORKSPACE_UID, {
      name: "عميل الجسر الهجين",
      category: "clients",
      currency: "ريال",
    });
    assert.equal(newAccId, "acc_new_99");

    const newEntryId = await createLedgerEntry(LOCAL_WORKSPACE_UID, {
      accountId: newAccId,
      accountName: "عميل الجسر الهجين",
      amount: 1500,
      currency: "ريال",
      kind: "voucher",
      direction: "credit",
      payment: "cash",
    });
    assert.equal(newEntryId, "led_999");

    const invReport = await fetchInventoryMovementsReport(LOCAL_WORKSPACE_UID, {
      warehouseId: "wh_main",
    });
    assert.equal(invReport.totals.totalRemainingValue, 504000);

    const cbReport = await fetchCashboxesReport(LOCAL_WORKSPACE_UID, { currency: "ريال" });
    assert.equal(cbReport.cashboxes[0].netBalance, 7500);

    assert.deepEqual(receivedActions, [
      "getSnapshot",
      "saveAccount",
      "createLedgerEntry",
      "getInventoryMovementsReport",
      "getCashboxesReport",
    ]);
  });
});

describe("Hybrid Routes Canonical Mapping", () => {
  it("normalizes FlowStack screen IDs to canonical hybrid routes across all 5 batches", () => {
    assert.equal(isValidHybridRoute("dashboard"), true);
    assert.equal(isValidHybridRoute("unknown-route"), false);
    assert.equal(normalizeFlowScreenIdToHybridRoute("dashboard"), "dashboard");
    assert.equal(normalizeFlowScreenIdToHybridRoute("supplier:acc_123"), "supplier");
    assert.equal(normalizeFlowScreenIdToHybridRoute("cash-invoice-preview:1140"), "cash-invoice-preview");
    assert.equal(normalizeFlowScreenIdToHybridRoute("category-purchases"), "purchases");
    assert.equal(normalizeFlowScreenIdToHybridRoute("accounts-purchases-1"), "purchases");
    assert.equal(normalizeFlowScreenIdToHybridRoute("accounts-clients-3"), "clients");
    assert.equal(normalizeFlowScreenIdToHybridRoute("accounts-transfers-4"), "transfers");
    assert.equal(normalizeFlowScreenIdToHybridRoute("settings"), "settings");
    assert.equal(normalizeFlowScreenIdToHybridRoute("inventory-report"), "inventory-report");
    assert.ok(HYBRID_ROUTES.length >= 25);
  });
});

describe("Offline Hybrid Build Output Integrity (dist/hybrid)", () => {
  it("produces self-contained dist/hybrid bundle with CSP, manifest, zero external URLs, and zero mock/fixture code", () => {
    const outDir = path.resolve(process.cwd(), "dist", "hybrid");
    const indexPath = path.join(outDir, "index.html");
    const manifestPath = path.join(outDir, "hybrid-manifest.json");

    assert.ok(fs.existsSync(indexPath), "dist/hybrid/index.html must exist (run npm run build:hybrid)");
    assert.ok(fs.existsSync(manifestPath), "dist/hybrid/hybrid-manifest.json must exist");

    const html = fs.readFileSync(indexPath, "utf8");
    assert.match(html, /Content-Security-Policy/);
    assert.match(html, /connect-src 'none'/);
    assert.doesNotMatch(html, /fonts\.googleapis\.com/i);
    assert.doesNotMatch(html, /src="\/assets\//);

    const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8")) as {
      protocolVersion: string;
      bridgeChannel: string;
      supportedBridgeChannels?: string[];
      offlineReady: boolean;
      mockHostStripped?: boolean;
      files: Array<{ path: string; bytes: number; sha256: string }>;
    };
    assert.equal(manifest.protocolVersion, HYBRID_PROTOCOL_VERSION);
    assert.equal(manifest.bridgeChannel, "NasqoHome");
    assert.ok(Array.isArray(manifest.supportedBridgeChannels) && manifest.supportedBridgeChannels.includes("NasqoFlutterBridge"));
    assert.equal(manifest.offlineReady, true);
    assert.equal(manifest.mockHostStripped, true);
    assert.ok(manifest.files.some((f) => f.path.endsWith(".woff2")), "Local Arabic fonts must be bundled");
    assert.ok(manifest.files.some((f) => f.path.endsWith(".js")), "Hybrid JS bundle must exist");
    assert.ok(manifest.files.some((f) => f.path.endsWith(".css")), "Hybrid CSS bundle must exist");

    // Hard guarantee: production bundle MUST NOT contain mockFlutter or fixture data
    const forbiddenProdStrings = [
      "mockFlutter",
      "installMockFlutterHost",
      "__nasqoMockBridgeLog",
      "مؤسسة البراري للتوريد",
      "شركة الخليج للطاقة (دولار)",
      "حوالات الصرافة الدولية",
      "BAT-200",
    ];
    for (const file of manifest.files) {
      if (!/\.(html|js|css)$/i.test(file.path)) continue;
      const content = fs.readFileSync(path.join(outDir, file.path), "utf8");
      for (const forbidden of forbiddenProdStrings) {
        assert.ok(
          !content.includes(forbidden),
          `Production bundle file ${file.path} must NOT contain "${forbidden}"`,
        );
      }
    }
  });

  it("prioritizes existing Android WebViewCompat window.NasqoHome channel over NasqoFlutterBridge", async () => {
    const prevWindow = (globalThis as { window?: unknown }).window;
    const messageListeners: Array<(evt: { data?: unknown }) => void> = [];
    const nasqoHomeSent: string[] = [];
    const fallbackSent: string[] = [];

    const mockWindow = {
      NasqoHome: {
        addEventListener: (type: string, fn: (evt: { data?: unknown }) => void) => {
          if (type === "message") messageListeners.push(fn);
        },
        postMessage: (msg: string) => {
          nasqoHomeSent.push(msg);
          const req = JSON.parse(msg) as HybridRequestEnvelope;
          queueMicrotask(() => {
            const resp = JSON.stringify({
              protocolVersion: HYBRID_PROTOCOL_VERSION,
              kind: "response",
              requestId: req.requestId,
              action: req.action,
              ok: true,
              data: { source: "NasqoHome" },
            });
            for (const fn of messageListeners) fn({ data: resp });
          });
        },
      },
      NasqoFlutterBridge: {
        postMessage: (msg: string) => {
          fallbackSent.push(msg);
        },
      },
    };

    (globalThis as { window?: unknown }).window = mockWindow;
    try {
      const bridge = new NasqoHybridBridge();
      assert.equal(bridge.getActiveTransportName(), "NasqoHome");

      const hostEvents: unknown[] = [];
      bridge.onHostEvent("themeChanged", (payload) => hostEvents.push(payload));

      const res = await bridge.invoke<"getSnapshot", { source: string }>("getSnapshot", {
        workspaceId: LOCAL_WORKSPACE_UID,
      });
      assert.deepEqual(res, { source: "NasqoHome" });
      assert.equal(nasqoHomeSent.length, 1);
      assert.equal(fallbackSent.length, 0);

      // Verify WebViewCompat postMessage event delivery into React
      for (const fn of messageListeners) {
        fn({
          data: JSON.stringify({
            protocolVersion: HYBRID_PROTOCOL_VERSION,
            kind: "event",
            event: "themeChanged",
            payload: { mode: "dark" },
          }),
        });
      }
      assert.deepEqual(hostEvents, [{ mode: "dark" }]);
    } finally {
      if (prevWindow === undefined) {
        delete (globalThis as { window?: unknown }).window;
      } else {
        (globalThis as { window?: unknown }).window = prevWindow;
      }
    }
  });
});

describe("Stage 2 Home Screen Batch 1 Requirements", () => {
  it("validates Flutter Home snapshot and rejects malformed or unsafe snapshot payloads", () => {
    const validSnap = createHybridHomeFixtureSnapshot();
    const ok = validateHybridSnapshot(validSnap);
    assert.equal(ok.valid, true);

    assert.equal(validateHybridSnapshot(null).valid, false);
    assert.equal(validateHybridSnapshot({ workspaceId: "" }).valid, false);
    assert.equal(
      validateHybridSnapshot({
        ...validSnap,
        accounts: "not-an-array",
      }).valid,
      false,
    );
    assert.equal(
      validateHybridSnapshot({
        ...validSnap,
        extra: { execSql: "DELETE FROM ledger" },
      }).valid,
      false,
    );
  });

  it("computes signed multi-currency group balances accurately without mixing currencies", () => {
    const snap = createHybridHomeFixtureSnapshot();
    const rows = computeAccountGroupsSummary(
      snap.accountGroups,
      snap.accounts,
      snap.ledger,
      {},
      snap.workspace?.defaultCurrency ?? "ريال",
    );

    const purchasesRow = rows.find((r) => r.id === 1);
    const salesRow = rows.find((r) => r.id === 2);
    const clientsRow = rows.find((r) => r.id === 3);
    const transfersRow = rows.find((r) => r.id === 4);
    const shopRow = rows.find((r) => r.id === 5);

    // Group 1 (Purchases, default ريال): opening 120,000 credit + 45,000 credit = -165,000 (USD account excluded!)
    assert.equal(purchasesRow?.currency, "ريال");
    assert.equal(purchasesRow?.netDebitMinusCredit, -165000);
    // Group 2 (Sales, default ريال): 0
    assert.equal(salesRow?.netDebitMinusCredit, 0);
    // Group 3 (Clients, default ريال): opening 85,000 debit - 30,000 credit = +55,000
    assert.equal(clientsRow?.netDebitMinusCredit, 55000);
    // Group 4 (Transfers, configured دولار): +1,250 USD (honors group currencyCode!)
    assert.equal(transfersRow?.currency, "دولار");
    assert.equal(transfersRow?.netDebitMinusCredit, 1250);
    // Group 5 (Shop, ريال): -45,000
    assert.equal(shopRow?.netDebitMinusCredit, -45000);

    // Switching Group 1 currency to دولار shows ONLY USD balance (-2400 opening - 600 invoice = -3000)
    const usdRows = computeAccountGroupsSummary(
      snap.accountGroups,
      snap.accounts,
      snap.ledger,
      { 1: "دولار" },
      snap.workspace?.defaultCurrency ?? "ريال",
    );
    const purchasesUsd = usdRows.find((r) => r.id === 1);
    assert.equal(purchasesUsd?.currency, "دولار");
    assert.equal(purchasesUsd?.netDebitMinusCredit, -3000);
  });

  it("blocks JS financial writes in Batch 1 read-only mode while allowing navigation, currency, and UI preferences", async () => {
    const bridge = new NasqoHybridBridge();
    const sent: HybridRequestEnvelope[] = [];
    bridge.setTransportForTesting({
      postMessage: (json) => {
        const req = JSON.parse(json) as HybridRequestEnvelope;
        sent.push(req);
        queueMicrotask(() => {
          bridge.handleInbound({
            protocolVersion: HYBRID_PROTOCOL_VERSION,
            kind: "response",
            requestId: req.requestId,
            ok: true,
            data: { ok: true },
          });
        });
      },
    });
    bridge.setReadOnlyFinancialMode(true);

    // Financial posting must be rejected immediately before reaching transport
    await assert.rejects(
      () =>
        bridge.invoke("createLedgerEntry", {
          workspaceId: LOCAL_WORKSPACE_UID,
          payload: { accountId: "acc_sup_1", accountName: "مورد", amount: 1000 },
        }),
      (err: unknown) => err instanceof HybridBridgeError && err.code === "UNAUTHORIZED_ACTION",
    );
    assert.equal(sent.length, 0);

    // Read/display/navigation/currency/preferences commands still succeed
    await bridge.invoke("navigate", { route: "purchases" });
    await bridge.invoke("changeCurrency", { scope: "dashboard", targetId: "1", currency: "دولار" });
    await bridge.invoke("saveUiPreferences", { preferences: { themeMode: "dark" } });
    await bridge.invoke("goBack", { currentRoute: "dashboard", stackDepth: 1 });
    assert.deepEqual(
      sent.map((e) => e.action),
      ["navigate", "changeCurrency", "saveUiPreferences", "goBack"],
    );
  });

  it("supports Home tile drag reorder, pin, color toggle, hide/show, and reset to default layout", () => {
    let layout = DEFAULT_HOME_TILE_LAYOUT;
    assert.equal(isDefaultHomeTileLayout(layout), true);

    layout = togglePinHomeTile(layout, "new-invoice");
    assert.ok(layout.pinned.includes("new-invoice"));
    assert.equal(isDefaultHomeTileLayout(layout), false);

    layout = moveHomeTile(layout, "new-voucher", "new-invoice");
    assert.equal(layout.order[0], "new-voucher");

    layout = toggleToneHomeTile(layout, "new-invoice", "blue");
    assert.equal(layout.toneOverrides["new-invoice"], "amber");

    layout = toggleHideHomeTile(layout, "quote");
    assert.ok(layout.hidden.includes("quote"));

    // Restore hidden tile
    layout = toggleHideHomeTile(layout, "quote");
    assert.ok(!layout.hidden.includes("quote"));

    // Reset to default
    layout = DEFAULT_HOME_TILE_LAYOUT;
    assert.equal(isDefaultHomeTileLayout(layout), true);
  });
});

