import { test } from "node:test";
import { strict as assert } from "node:assert";
import { ContactSaveError, saveOdooContact } from "../src/odooContacts.ts";
import { NATIVE_ODOO_ACTIONS, nativeOdooPath } from "../src/odooNavigation.ts";

const originalWindow = globalThis.window;
const originalFetch = globalThis.fetch;
const validLocation = { protocol: "https:", hostname: "erp.indexesstore.com", pathname: "/nasqo-mobile/" };
const response = (result) => ({ ok: true, json: async () => ({ jsonrpc: "2.0", id: 1, result }) });

test("Odoo actions map only to numerical installed action IDs", () => {
  for (const [key, id] of Object.entries(NATIVE_ODOO_ACTIONS)) {
    assert.ok(Number.isSafeInteger(id) && id > 0, key);
    assert.equal(nativeOdooPath(key), "/odoo/action-" + id);
  }
  assert.equal(nativeOdooPath("partnerLedger"), "/odoo/action-256");
  assert.equal(nativeOdooPath("vendorBills"), "/odoo/action-264");
  assert.equal(nativeOdooPath("warehouses"), "/odoo/action-469");
});

test("a real contact create requires a live HTTPS origin and Odoo login", async () => {
  try {
    globalThis.window = { location: { ...validLocation, protocol: "http:" } };
    globalThis.fetch = async () => { throw Error("network must not be used"); };
    await assert.rejects(saveOdooContact({ name: "Test" }), (err) => err instanceof ContactSaveError && err.reason === "permission");

    globalThis.window = { location: validLocation };
    let calls = 0;
    globalThis.fetch = async () => {
      calls += 1;
      return response({ uid: false });
    };
    await assert.rejects(saveOdooContact({ name: "Test" }), (err) => err instanceof ContactSaveError && err.reason === "login");
    assert.equal(calls, 1, "must never call write without login");
  } finally {
    globalThis.window = originalWindow;
    globalThis.fetch = originalFetch;
  }
});

test("create sends only whitelisted contact fields through same-origin session", async () => {
  const calls = [];
  try {
    globalThis.window = { location: validLocation };
    globalThis.fetch = async (url, opts) => {
      calls.push({ url, opts });
      return response(calls.length === 1 ? { uid: 42 } : [154]);
    };
    assert.equal(await saveOdooContact({ name: "  Example  ", phone: "1234", note: "  memo  " }), 154);
    assert.equal(calls.length, 2);
    assert.equal(calls[1].url, "/web/dataset/call_kw/res.partner/create");
    assert.equal(calls[1].opts.credentials, "same-origin");
    assert.deepEqual(JSON.parse(calls[1].opts.body).params.args, [[{ name: "Example", phone: "1234", comment: "memo" }]]);
  } finally {
    globalThis.window = originalWindow;
    globalThis.fetch = originalFetch;
  }
});

test("editing does not erase contact notes or phone when unspecified", async () => {
  const calls = [];
  try {
    globalThis.window = { location: validLocation };
    globalThis.fetch = async (url, opts) => {
      calls.push({ url, opts });
      return response(calls.length === 1 ? { uid: 42 } : true);
    };
    assert.equal(await saveOdooContact({ id: 5, name: "Edited" }), 5);
    assert.equal(calls[1].url, "/web/dataset/call_kw/res.partner/write");
    assert.deepEqual(JSON.parse(calls[1].opts.body).params.args, [[5], { name: "Edited" }]);
  } finally {
    globalThis.window = originalWindow;
    globalThis.fetch = originalFetch;
  }
});

test("Odoo permission errors do not trigger retries or extra writes", async () => {
  let calls = 0;
  try {
    globalThis.window = { location: validLocation };
    globalThis.fetch = async () => {
      calls += 1;
      return calls === 1 ? response({ uid: 42 }) : {
        ok: true, json: async () => ({ error: { code: 200, data: { name: "odoo.exceptions.AccessError" } } }),
      };
    };
    await assert.rejects(saveOdooContact({ name: "Denied" }), (err) => err instanceof ContactSaveError && err.reason === "permission");
    assert.equal(calls, 2);
  } finally {
    globalThis.window = originalWindow;
    globalThis.fetch = originalFetch;
  }
});
