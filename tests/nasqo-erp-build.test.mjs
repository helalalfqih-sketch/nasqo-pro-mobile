import { strict as assert } from "node:assert";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";

const output = "dist/erp-client";
const html = readFileSync(join(output, "index.html"), "utf8");

test("ERP bundle resolves JS/CSS under /nasqo-mobile only", () => {
  const urls = [...html.matchAll(/(?:src|href)="([^"]+\.(?:js|css))"/g)].map((m) => m[1]);
  assert.ok(urls.length >= 2);
  for (const url of urls) {
    assert.ok(url.startsWith("/nasqo-mobile/assets/"), url);
    assert.ok(existsSync(join(output, url.slice("/nasqo-mobile/".length))), url);
  }
});

test("original preview build stays independent", () => {
  const source = readFileSync("dist/client/index.html", "utf8");
  assert.match(source, /\/assets\/index-/);
  assert.doesNotMatch(source, /\/nasqo-mobile\/assets\//);
});

test("ERP entrypoint never refers to root-scoped /assets paths", () => {
  assert.doesNotMatch(html, /(?:src|href)="\/assets\//);
});
