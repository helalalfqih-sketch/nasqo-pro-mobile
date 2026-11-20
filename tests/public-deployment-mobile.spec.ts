import { test, expect } from "@playwright/test";

test("NASQO SQLite page shows mobile login without clipped grid", async ({ browser }) => {
  test.setTimeout(65000);
  const ctx = await browser.newContext({
    viewport: { width: 390, height: 844 },
    deviceScaleFactor: 1,
    isMobile: true,
    hasTouch: true,
  });
  const page = await ctx.newPage();
  const errors: string[] = [];
  page.on("pageerror", err => errors.push("PAGE: " + err.message));
  page.on("console", msg => { if (msg.type() === "error") errors.push("CONSOLE: " + msg.text()); });
  page.on("response", response => { if (response.status() >= 400) errors.push("HTTP: " + response.status() + " " + response.url()); });
  try {
    await page.route("**/api/db/auth/status", route => route.fulfill({
      status: 200, contentType: "application/json",
      body: JSON.stringify({ mode: "password", authenticated: false }),
    }));
    await page.goto("/?autostart=1", {waitUntil:"domcontentloaded",timeout:30000});
    await page.waitForTimeout(5500);
    console.log("PUBLIC_MOBILE_TEXT", JSON.stringify((await page.locator("body").innerText()).slice(0,1400)));
    console.log("PUBLIC_MOBILE_ERRORS", JSON.stringify(errors.slice(0,30)));
    console.log("PUBLIC_MOBILE_ELEMENTS", JSON.stringify(await page.evaluate(() =>
      [...document.querySelectorAll("body *")].filter(e=> {
        const b=e.getBoundingClientRect();return b.width>300 && b.height>400;
      }).slice(-12).map(e=>({tag:e.tagName,className:e.className,rect:[Math.round(e.getBoundingClientRect().top),Math.round(e.getBoundingClientRect().height)],background:getComputedStyle(e).backgroundColor,z:getComputedStyle(e).zIndex})))));
    await page.screenshot({path:"test-results/public-mobile.png",fullPage:true});
    expect(errors.filter(e=>e.startsWith("PAGE:"))).toEqual([]);
    await expect(page.getByRole("heading", { name: "نسقو برو — تسجيل الدخول" })).toBeVisible();
    await expect(page.getByTestId("sqlite-admin-login")).toBeVisible();
    const card = await page.locator(".auth-gate-single-panel .auth-card").boundingBox();
    const field = await page.getByLabel("كلمة مرور المدير").boundingBox();
    const login = await page.getByTestId("sqlite-admin-login").boundingBox();
    expect(card).not.toBeNull();
    expect(field).not.toBeNull();
    expect(login).not.toBeNull();
    expect(card!.y).toBeGreaterThanOrEqual(0);
    expect(card!.y + card!.height).toBeLessThanOrEqual(844);
    expect(field!.y).toBeGreaterThanOrEqual(card!.y);
    expect(login!.y + login!.height).toBeLessThanOrEqual(844);

  } finally { await ctx.close(); }
});
