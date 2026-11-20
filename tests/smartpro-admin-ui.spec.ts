import { expect, test } from "@playwright/test";

test("SmartPro central management opens from ERP hub without requiring schema access in public mode",async ({page})=>{
  test.setTimeout(45000);
  await page.goto("/?autostart=1");
  await expect(page.getByTestId("dashboard-screen")).toBeVisible({timeout:20000});
  await page.getByTestId("open-erp-hub-btn").click();
  await expect(page.getByTestId("erp-hub-screen")).toBeVisible({timeout:15000});
  await page.getByTestId("open-smartpro-control").click();
  await expect(page.getByTestId("smartpro-center")).toBeVisible({timeout:15000});
  await expect(page.getByText(/ربط SmartPro المركزي غير مُفعّل/)).toBeVisible({timeout:15000});
  await expect(page.getByTestId("smartpro-role")).toHaveCount(0);
  await expect(page.getByTestId("smartpro-new")).toHaveCount(0);
});

test("primary SmartPro mode requires verified sign-in and cannot silently enter local ERP", async ({page}) => {
  test.setTimeout(45000);
  await page.route("**/api/smartpro/status", route =>
    route.fulfill({status:200,contentType:"application/json",body:JSON.stringify({available:true,writeEnabled:true,primary:true})})
  );
  await page.goto("/?autostart=1");
  await expect(page.getByTestId("google-signin-button")).toBeVisible({timeout:20000});
  await expect(page.getByTestId("local-erp-signin-button")).toHaveCount(0);
  await expect(page.getByTestId("dashboard-screen")).toHaveCount(0);
});

test("after central cutover, network failure fails closed without writing legacy workspace", async ({page}) => {
  test.setTimeout(45000);
  const workspaceWrites: string[] = [];
  page.on("request", request => {
    if (new URL(request.url()).pathname.startsWith("/api/db/workspace/") &&
        ["POST", "PUT", "PATCH", "DELETE"].includes(request.method())) {
      workspaceWrites.push(request.method() + " " + request.url());
    }
  });
  await page.addInitScript(() => localStorage.setItem("nasqo-smartpro-primary-active","1"));
  await page.route("**/api/smartpro/status", route => route.abort());
  await page.goto("/?autostart=1");
  await expect(page.getByRole("heading", { name: "تعذر الاتصال بالإدارة المركزية" })).toBeVisible({timeout:20000});
  await expect(page.getByTestId("local-erp-signin-button")).toHaveCount(0);
  await expect(page.getByTestId("dashboard-screen")).toHaveCount(0);
  expect(workspaceWrites).toEqual([]);
});
