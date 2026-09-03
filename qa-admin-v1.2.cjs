const { chromium } = require("playwright");
const path = require("path");

const password = process.env.KEZAI_ADMIN_PASSWORD;
if (!password) throw new Error("KEZAI_ADMIN_PASSWORD is required");

(async () => {
  const browser = await chromium.launch({
    headless: true,
    executablePath: "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe",
  });
  try {
    const context = await browser.newContext({ viewport: { width: 1280, height: 900 } });
    const page = await context.newPage();
    await page.goto("http://10.10.24.116/mobile", { waitUntil: "domcontentloaded" });
    await page.locator('input[name="login_username"]').fill("Innoxsz管理者-7M4Q");
    await page.locator('input[name="login_password"]').fill("NoLegacyAccess2026!");
    await page.getByRole("button", { name: "登录并进入社区" }).click();
    await page.waitForLoadState("domcontentloaded");
    if (!(await page.locator("body").innerText()).includes("用户名或密码不正确")) {
      throw new Error("旧的特殊姓名入口仍可能有效");
    }

    await page.locator('input[name="login_username"]').fill("admin");
    await page.locator('input[name="login_password"]').fill(password);
    await Promise.all([
      page.waitForURL((url) => url.pathname.startsWith("/admin"), { timeout: 30000 }),
      page.getByRole("button", { name: "登录并进入社区" }).click(),
    ]);
    await page.screenshot({ path: path.join(__dirname, "evidence", "kezai-security-v1.2-admin.png"), fullPage: true });
    console.log(JSON.stringify({ legacyShortcutRejected: true, adminPasswordAccepted: true, finalUrl: page.url() }));
  } finally {
    await browser.close();
  }
})().catch((error) => {
  console.error(error.stack || error.message);
  process.exitCode = 1;
});
