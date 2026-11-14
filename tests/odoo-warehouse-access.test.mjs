import { test } from "node:test";
import { strict as assert } from "node:assert";
import { readFileSync } from "node:fs";
import { classifyOdooFailure } from "../src/odooErrors.ts";

test("Odoo session expiration is not mistaken for missing stock permissions", () => {
  assert.equal(classifyOdooFailure({ code: 100 }), "login");
});

test("warehouse AccessError is classified as a permission problem", () => {
  assert.equal(classifyOdooFailure({
    code: 200, data: { name: "odoo.exceptions.AccessError" },
  }), "permission");
  assert.equal(classifyOdooFailure({
    code: 200, data: { name: "odoo.exceptions.AccessDenied" },
  }), "permission");
});

test("other Odoo errors never masquerade as authorization errors", () => {
  assert.equal(classifyOdooFailure({ code: 200, data: { name: "odoo.exceptions.ValidationError" } }), "other");
  assert.equal(classifyOdooFailure({ code: 200 }), "other");
});

test("live warehouse failures are shown as permissions, never demo records", () => {
  const provider = readFileSync("src/liveOdoo.tsx", "utf8");
  const ui = readFileSync("src/Prototype.tsx", "utf8");
  assert.match(provider, /deniedSections/);
  assert.match(provider, /ODOO_ACCESS_DENIED/);
  assert.match(ui, /المخازن: لا يملك هذا الحساب صلاحية القراءة في Odoo/);
  assert.match(ui, /لا تملك صلاحية القراءة في Odoo/);
});
