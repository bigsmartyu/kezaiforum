const { chromium } = require("playwright");
const fs = require("fs");
const path = require("path");

const baseUrl = process.env.KEZAI_QA_BASE_URL || "https://kezaiforum.xyz";
const aliceUsername = process.env.KEZAI_QA_USER_1;
const bobUsername = process.env.KEZAI_QA_USER_2;
const password = process.env.KEZAI_QA_PASSWORD;
if (!aliceUsername || !bobUsername || !password) {
  throw new Error("KEZAI_QA_USER_1, KEZAI_QA_USER_2 and KEZAI_QA_PASSWORD are required");
}

const evidenceDir = path.join(__dirname, "evidence", "anonymous-community");
const stamp = Date.now();
const anonymousTitle = `匿名审核网页验收 ${stamp}`;
const outsideTitle = `匿名越区网页验收 ${stamp}`;
const privateMessage = `实名私聊双向验收 ${stamp}`;
const result = { baseUrl, checks: {}, consoleErrors: [], anonymousTitle };

const expect = (condition, message) => {
  if (!condition) throw new Error(message);
};

async function login(context, username) {
  const page = await context.newPage();
  page.on("console", (message) => {
    if (message.type() === "error") result.consoleErrors.push(`${username}: ${message.text()}`);
  });
  await page.goto(`${baseUrl}/mobile`, { waitUntil: "domcontentloaded", timeout: 45000 });
  await page.locator('input[name="login_username"]').fill(username);
  await page.locator('input[name="login_password"]').fill(password);
  await Promise.all([
    page.waitForURL((url) => url.pathname.startsWith("/latest"), { timeout: 45000 }),
    page.getByRole("button", { name: "登录并进入社区" }).click(),
  ]);
  return page;
}

async function jsonRequest(page, url, options = {}) {
  return page.evaluate(
    async ({ url, options }) => {
      const csrf = document.querySelector('meta[name="csrf-token"]')?.content;
      const response = await fetch(url, {
        ...options,
        headers: {
          Accept: "application/json",
          "Content-Type": "application/json",
          "X-CSRF-Token": csrf || "",
          ...(options.headers || {}),
        },
      });
      const rawBody = await response.text();
      let body = {};
      try {
        body = rawBody ? JSON.parse(rawBody) : {};
      } catch {
        body = {};
      }
      return { status: response.status, body, rawBody: rawBody.slice(0, 500) };
    },
    { url, options },
  );
}

(async () => {
  fs.mkdirSync(evidenceDir, { recursive: true });
  const browser = await chromium.launch({
    headless: true,
    executablePath:
      process.env.KEZAI_BROWSER_PATH || "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe",
  });

  try {
    const aliceContext = await browser.newContext({ viewport: { width: 1365, height: 900 } });
    const alicePage = await login(aliceContext, aliceUsername);

    await alicePage.goto(`${baseUrl}/u/${bobUsername}/summary`, {
      waitUntil: "domcontentloaded",
      timeout: 45000,
    });
    await alicePage.waitForTimeout(2500);
    const profileText = await alicePage.locator("body").innerText();
    expect(profileText.includes("匿名验收乙"), "成员资料页没有显示实名姓名");
    expect(profileText.includes("B202测试办公室"), "成员资料页没有显示办公室");
    result.checks.memberPublicProfile = true;
    await alicePage.screenshot({
      path: path.join(evidenceDir, "member-profile.png"),
      fullPage: true,
    });

    const profileJson = await jsonRequest(alicePage, `/u/${bobUsername}.json`, { method: "GET" });
    expect(profileJson.status === 200, "成员资料接口不可访问");
    const publicFields = profileJson.body.user?.user_fields || profileJson.body.user?.custom_fields || {};
    const serializedProfile = JSON.stringify(profileJson.body.user || {});
    expect(serializedProfile.includes("KZ-M-"), "成员资料没有公开成员编号");
    expect(serializedProfile.includes("B202测试办公室"), "成员资料没有公开办公室信息");
    result.checks.memberIdVisible = true;
    result.checks.profileFieldCount = Object.keys(publicFields).length;

    await alicePage.goto(`${baseUrl}/c/anonymous-community/5`, {
      waitUntil: "domcontentloaded",
      timeout: 45000,
    });
    await alicePage.waitForTimeout(2500);
    expect((await alicePage.locator("body").innerText()).includes("匿名社区"), "匿名社区页面不存在");
    await alicePage.locator(".header-dropdown-toggle.current-user").click();
    await alicePage.locator("#user-menu-button-profile").click();
    const enableAnonymous = alicePage.locator("li.enable-anonymous button");
    await enableAnonymous.waitFor({ state: "visible", timeout: 15000 });
    expect((await enableAnonymous.innerText()).includes("匿名"), "匿名切换入口没有清晰标识");
    await Promise.all([
      alicePage.waitForNavigation({ waitUntil: "domcontentloaded", timeout: 45000 }),
      enableAnonymous.click(),
    ]);

    const currentAnonymous = await jsonRequest(alicePage, "/session/current.json", { method: "GET" });
    const anonymousSessionUser = currentAnonymous.body.current_user || currentAnonymous.body;
    expect(anonymousSessionUser?.is_anonymous === true, "没有成功切换到匿名身份");
    result.checks.anonymousSwitch = true;

    await alicePage.goto(`${baseUrl}/c/anonymous-community/5`, {
      waitUntil: "domcontentloaded",
      timeout: 45000,
    });
    await alicePage.waitForTimeout(2500);
    await alicePage.screenshot({
      path: path.join(evidenceDir, "anonymous-category.png"),
      fullPage: true,
    });

    const anonymousPost = await jsonRequest(alicePage, "/posts.json", {
      method: "POST",
      body: JSON.stringify({
        title: anonymousTitle,
        raw: "这是通过公网网页提交的匿名内容，用于确认所有匿名发布都会先进入审核。",
        category: 5,
      }),
    });
    expect(anonymousPost.status === 200, `匿名内容提交失败，状态 ${anonymousPost.status}`);
    expect(Boolean(anonymousPost.body.id), "安全匿名内容没有被 AI 批准公开");
    result.checks.anonymousSafeAutoApproved = true;

    const rejectedAnonymousPost = await jsonRequest(alicePage, "/posts.json", {
      method: "POST",
      body: JSON.stringify({
        title: `匿名违规网页验收 ${stamp}`,
        raw: "你这个蠢货，滚开。",
        category: 5,
      }),
    });
    expect(rejectedAnonymousPost.status >= 400, "违规匿名内容没有被 AI 退回");
    expect(
      JSON.stringify(rejectedAnonymousPost.body).includes("未通过 AI 审核"),
      "AI 退回提示不清晰",
    );
    result.checks.anonymousUnsafeRejected = true;

    const outsidePost = await jsonRequest(alicePage, "/posts.json", {
      method: "POST",
      body: JSON.stringify({
        title: outsideTitle,
        raw: "匿名身份不应当能在其他分类发布这条测试内容。",
        category: 4,
      }),
    });
    expect(outsidePost.status >= 400, "匿名身份可以越过匿名社区发布");
    expect(JSON.stringify(outsidePost.body).includes("匿名身份只能"), "越区阻止提示不清楚");
    result.checks.anonymousRestrictedToCategory = true;

    await alicePage.locator(".header-dropdown-toggle.current-user").click();
    await alicePage.locator("#user-menu-button-profile").click();
    const disableAnonymous = alicePage.locator("li.disable-anonymous button");
    await disableAnonymous.waitFor({ state: "visible", timeout: 15000 });
    await Promise.all([
      alicePage.waitForNavigation({ waitUntil: "domcontentloaded", timeout: 45000 }),
      disableAnonymous.click(),
    ]);
    const currentReal = await jsonRequest(alicePage, "/session/current.json", { method: "GET" });
    const realSessionUser = currentReal.body.current_user || currentReal.body;
    expect(realSessionUser?.is_anonymous !== true, "没有成功切回实名身份");
    result.checks.realIdentityRestored = true;

    const directChannel = await jsonRequest(alicePage, "/chat/api/direct-message-channels", {
      method: "POST",
      body: JSON.stringify({ target_usernames: [bobUsername], upsert: true }),
    });
    expect(directChannel.status === 200, `无法创建私聊，状态 ${directChannel.status}`);
    const channelId = directChannel.body.channel?.id;
    expect(channelId, "私聊创建成功但没有返回会话编号");

    const sentMessage = await jsonRequest(alicePage, `/chat/${channelId}`, {
      method: "POST",
      body: JSON.stringify({ chat_channel_id: String(channelId), message: privateMessage }),
    });
    expect(
      sentMessage.status === 200 && sentMessage.body.message_id,
      `私聊消息发送失败：${sentMessage.status} ${JSON.stringify(sentMessage.body)} ${sentMessage.rawBody}`,
    );
    result.checks.privateChatSent = true;

    const bobContext = await browser.newContext({ viewport: { width: 390, height: 844 } });
    const bobPage = await login(bobContext, bobUsername);
    const messages = await jsonRequest(bobPage, `/chat/api/channels/${channelId}/messages`, {
      method: "GET",
    });
    expect(messages.status === 200, "私聊接收方无法打开会话");
    expect(JSON.stringify(messages.body).includes(privateMessage), "私聊接收方没有收到消息");
    result.checks.privateChatReceived = true;
    await bobPage.goto(`${baseUrl}/chat/c/-/${channelId}`, {
      waitUntil: "domcontentloaded",
      timeout: 45000,
    });
    await bobPage.waitForTimeout(2500);
    await bobPage.screenshot({
      path: path.join(evidenceDir, "private-chat-mobile.png"),
      fullPage: true,
    });

    result.knownConsoleWarnings = result.consoleErrors.filter(
      (message) =>
        message.includes("static.cloudflareinsights.com") ||
        message.includes("Mixed Content") ||
        message.includes("Cross-Origin-Opener-Policy") ||
        message.includes("Failed to load resource"),
    );
    result.unexpectedConsoleErrors = result.consoleErrors.filter(
      (message) => !result.knownConsoleWarnings.includes(message),
    );
    expect(
      result.unexpectedConsoleErrors.length === 0,
      `页面出现新的脚本错误：${result.unexpectedConsoleErrors.join(" | ")}`,
    );
    await bobContext.close();
    await aliceContext.close();
    console.log(JSON.stringify(result, null, 2));
  } finally {
    await browser.close();
  }
})().catch((error) => {
  console.error(error.stack || error.message);
  process.exitCode = 1;
});
