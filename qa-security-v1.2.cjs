const { chromium } = require("playwright");
const fs = require("fs");
const path = require("path");

const baseUrl = "http://10.10.24.116";
const evidenceDir = path.join(__dirname, "evidence");
const password = process.env.KEZAI_QA_PASSWORD;
if (!password) throw new Error("KEZAI_QA_PASSWORD is required");

const username = `qa_${Date.now().toString().slice(-9)}`;
const realName = "安全验收用户";
const office = "A302验收办公室";
const result = { username, checks: {}, consoleErrors: [] };

const expect = (condition, message) => {
  if (!condition) throw new Error(message);
};

async function run() {
const browser = await chromium.launch({
  headless: true,
  executablePath: process.env.KEZAI_BROWSER_PATH || "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe",
});
try {
  fs.mkdirSync(evidenceDir, { recursive: true });

  const anonymous = await browser.newContext({ viewport: { width: 1440, height: 980 } });
  const page = await anonymous.newPage();
  page.on("console", (message) => {
    if (message.type() === "error") result.consoleErrors.push(message.text());
  });

  await page.goto(`${baseUrl}/mobile`, { waitUntil: "networkidle" });
  expect(await page.title() === "科仔交流社区", "页面标题没有更新");
  expect(await page.getByText("请共同维护社区纯净度").isVisible(), "社区纯净提示不可见");
  expect(await page.locator('input[name="login_password"]').isVisible(), "登录密码输入框不可见");
  expect(await page.locator('input[name="office"]').count() === 1, "办公室字段缺失");
  expect((await page.locator(".wallpaper").getAttribute("src")).includes("kezai-duo-v2"), "新科仔背景没有生效");
  result.checks.anonymousCannotSeeForum = !(await page.goto(`${baseUrl}/latest`, { waitUntil: "networkidle" })).url().includes("/latest");
  expect(result.checks.anonymousCannotSeeForum, "未登录用户仍能直接进入论坛");

  await page.goto(`${baseUrl}/mobile`, { waitUntil: "networkidle" });
  await page.screenshot({ path: path.join(evidenceDir, "kezai-security-v1.2-desktop.png"), fullPage: true });
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto(`${baseUrl}/mobile`, { waitUntil: "networkidle" });
  await page.screenshot({ path: path.join(evidenceDir, "kezai-security-v1.2-mobile-login.png"), fullPage: true });
  await page.getByRole("button", { name: "新成员实名登记" }).click();
  await page.screenshot({ path: path.join(evidenceDir, "kezai-security-v1.2-mobile-register.png"), fullPage: true });

  await page.locator('input[name="username"]').fill(username);
  await page.locator('input[name="password"]').fill(password);
  await page.locator('input[name="real_name"]').fill(realName);
  await page.locator('input[name="office"]').fill(office);
  await page.locator('input[name="legal_agreement"]').check();
  await Promise.all([
    page.waitForURL((url) => url.pathname === "/latest" || url.pathname === "/", { timeout: 30000 }),
    page.getByRole("button", { name: "完成登记并进入社区" }).click(),
  ]);
  result.checks.registrationReachedForum = page.url().includes("/latest") || new URL(page.url()).pathname === "/";

  const authCookie = (await anonymous.cookies()).find((cookie) => cookie.name === "_t");
  expect(authCookie, "注册后没有登录凭据");
  result.checks.sessionExpiresInDays = Math.round((authCookie.expires - Date.now() / 1000) / 86400);
  expect(result.checks.sessionExpiresInDays > 300, "登录保存时间不足 300 天");

  await page.goto(`${baseUrl}/join/account`, { waitUntil: "networkidle" });
  const accountText = await page.locator("body").innerText();
  expect(accountText.includes(realName), "成员页未显示真实姓名");
  expect(accountText.includes(office), "成员页未显示办公室");
  expect(accountText.includes("KZ-M-"), "成员编号格式错误");
  expect(accountText.includes("已完成内部实名登记"), "实名登记状态缺失");
  result.checks.memberPage = true;
  await page.screenshot({ path: path.join(evidenceDir, "kezai-security-v1.2-member.png"), fullPage: true });

  const storageState = await anonymous.storageState();
  await anonymous.close();
  const reopened = await browser.newContext({ storageState, viewport: { width: 390, height: 844 } });
  const reopenedPage = await reopened.newPage();
  await reopenedPage.goto(`${baseUrl}/mobile`, { waitUntil: "domcontentloaded", timeout: 30000 });
  await reopenedPage.waitForTimeout(2500);
  result.checks.rememberedAfterReopen = !reopenedPage.url().includes("/mobile") && !reopenedPage.url().includes("/join");
  expect(result.checks.rememberedAfterReopen, "重新打开后仍要求登录");

  const postAttempt = async (title, raw) => reopenedPage.evaluate(async ({ title, raw }) => {
    const csrfResponse = await fetch("/session/csrf.json", { credentials: "same-origin" });
    const { csrf } = await csrfResponse.json();
    const response = await fetch("/posts.json", {
      method: "POST",
      credentials: "same-origin",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": csrf, "X-Requested-With": "XMLHttpRequest" },
      body: JSON.stringify({ title, raw, category: 4 }),
    });
    return { status: response.status, body: await response.text() };
  }, { title, raw });

  const safePost = await postAttempt(`安全验收主题 ${Date.now()}`, "这是一次正常的内部工作交流验收，不包含敏感信息。内容长度满足论坛发帖要求。");
  result.safePost = safePost;
  expect(safePost.status >= 200 && safePost.status < 300, `正常内容提交失败：${safePost.status}`);
  expect(/review|pending|queued|审核|success/i.test(safePost.body), "新成员首帖没有显示审核结果");
  result.checks.firstPostReviewed = true;

  const blockedPost = await postAttempt(`违规拦截验收 ${Date.now()}`, "这里包含出售银行卡的违法招揽内容，用于验证自动拦截。");
  result.blockedPost = blockedPost;
  expect(blockedPost.status >= 400, `违规内容没有被拦截：${blockedPost.status}`);
  result.checks.blockedPhraseRejected = true;
  await reopened.close();

  const loginContext = await browser.newContext({ viewport: { width: 390, height: 844 } });
  const loginPage = await loginContext.newPage();
  await loginPage.goto(`${baseUrl}/mobile`, { waitUntil: "networkidle" });
  await loginPage.locator('input[name="login_username"]').fill(username);
  await loginPage.locator('input[name="login_password"]').fill("WrongPassword2026!");
  await loginPage.getByRole("button", { name: "登录并进入社区" }).click();
  await loginPage.waitForLoadState("networkidle");
  expect((await loginPage.locator("body").innerText()).includes("用户名或密码不正确"), "错误密码没有得到统一提示");
  result.checks.wrongPasswordRejected = true;

  await loginPage.locator('input[name="login_username"]').fill(username);
  await loginPage.locator('input[name="login_password"]').fill(password);
  await Promise.all([
    loginPage.waitForURL((url) => url.pathname === "/latest" || url.pathname === "/", { timeout: 30000 }),
    loginPage.getByRole("button", { name: "登录并进入社区" }).click(),
  ]);
  result.checks.correctPasswordAccepted = true;
  await loginContext.close();

  const apkResponse = await fetch(`${baseUrl}/Kezai-Community.apk`);
  result.checks.apkDownloadStatus = apkResponse.status;
  expect(apkResponse.ok, "安卓安装包下载失败");
} finally {
  await browser.close();
  fs.writeFileSync(path.join(evidenceDir, "kezai-security-v1.2-result.json"), JSON.stringify(result, null, 2));
}

console.log(JSON.stringify(result, null, 2));
}

run().catch((error) => {
  console.error(error.stack || error.message);
  process.exitCode = 1;
});
