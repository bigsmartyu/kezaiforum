const { chromium } = require("playwright");

const baseUrl = "http://10.10.24.116";

(async () => {
  const browser = await chromium.launch({
    headless: true,
    executablePath:
      process.env.KEZAI_BROWSER_PATH ||
      "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe",
  });

  try {
    const context = await browser.newContext({ viewport: { width: 390, height: 844 } });
    const page = await context.newPage();
    await page.goto(`${baseUrl}/signup`, { waitUntil: "networkidle" });

    const body = await page.locator("body").innerText();
    const visibleInputs = await page.locator("input:visible").count();
    const standardSignupVisible =
      (await page.locator('[data-action="show-create-account"]:visible').count()) > 0 ||
      (await page.getByRole("button", { name: /创建.*账号|注册|sign up|create account/i }).count()) > 0;

    const result = {
      requested: `${baseUrl}/signup`,
      finalUrl: page.url(),
      visibleInputs,
      standardSignupVisible,
      hasInviteOnlyMessage: /邀请|invite/i.test(body),
      guarded: !standardSignupVisible,
    };

    console.log(JSON.stringify(result, null, 2));
    if (!result.guarded) process.exitCode = 1;
  } finally {
    await browser.close();
  }
})().catch((error) => {
  console.error(error.stack || error.message);
  process.exitCode = 1;
});
