import { strict as assert } from "node:assert";
import { readFileSync } from "node:fs";
import { test } from "node:test";

const source = readFileSync("src/Prototype.tsx", "utf8");
const css = readFileSync("src/prototype.css", "utf8");

test("ERP browser layout activates only on the HTTPS NASQO mobile route", () => {
  assert.match(source, /window\.location\.protocol === "https:"/);
  assert.match(source, /window\.location\.hostname === "erp\.indexesstore\.com"/);
  assert.match(source, /window\.location\.pathname\.startsWith\("\/nasqo-mobile"\)/);
  assert.match(source, /document\.body\.classList\.add\("nasqo-browser-mode"\)/);
  assert.match(source, /document\.body\.classList\.remove\("nasqo-browser-mode"\)/);
});

test("ERP browser layout removes phone chrome and keeps full-width app", () => {
  assert.match(css, /body\.nasqo-browser-mode \.phone-bezel,/);
  assert.match(css, /body\.nasqo-browser-mode \.device-menu-bar,/);
  assert.match(css, /body\.nasqo-browser-mode \.status-bar,/);
  assert.match(css, /body\.nasqo-browser-mode \.home-indicator-svg,/);
  assert.match(css, /body\.nasqo-browser-mode \.device-screen\s*\{[^}]*width: 100% !important;[^}]*height: 100% !important;[^}]*border-radius: 0 !important;/s);
  assert.match(css, /body\.nasqo-browser-mode \.phone-device\s*\{[^}]*transform: none !important;/s);
});

test("Browser mode is scoped and does not override protected simulator globally", () => {
  assert.equal((css.match(/NASQO ERP browser mode/g) ?? []).length, 1);
  assert.match(css, /body\.nasqo-browser-mode \.dashboard-page/);
  assert.match(css, /body\.nasqo-browser-mode \.keyboard-dock,/);
  assert.match(css, /body\.nasqo-browser-mode \.flow-stack/);
});
