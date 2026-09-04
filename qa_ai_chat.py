import json
import os
import re
import sys
import time
from pathlib import Path

from playwright.sync_api import sync_playwright


BASE_URL = os.environ.get("KEZAI_QA_BASE_URL", "https://kezaiforum.xyz")
USERNAME = os.environ.get("KEZAI_QA_USERNAME")
PASSWORD = os.environ.get("KEZAI_QA_PASSWORD")
CHANNEL_ID = os.environ.get("KEZAI_QA_CHAT_CHANNEL_ID", "3")
EVIDENCE = Path(__file__).resolve().parent / "evidence" / "ai-chat"
EVIDENCE.mkdir(parents=True, exist_ok=True)


def check(condition, message):
    if not condition:
        raise AssertionError(message)


def json_request(page, route, method="GET", body=None):
    return page.evaluate(
        """
        async ({url, method, body}) => {
          const options = {
            method,
            credentials: 'same-origin',
            headers: {'Content-Type': 'application/json', 'X-Requested-With': 'XMLHttpRequest'}
          };
          if (method !== 'GET') {
            const csrfResponse = await fetch('/session/csrf.json', {credentials: 'same-origin'});
            const csrfPayload = await csrfResponse.json();
            options.headers['X-CSRF-Token'] = csrfPayload.csrf;
          }
          if (body !== null) options.body = JSON.stringify(body);
          const response = await fetch(url, options);
          const text = await response.text();
          let parsed;
          try { parsed = JSON.parse(text); } catch (_) { parsed = {text}; }
          return {status: response.status, body: parsed};
        }
        """,
        {"url": f"{BASE_URL}{route}", "method": method, "body": body},
    )


def run():
    check(USERNAME and PASSWORD, "缺少网页验收账号")
    result = {"base_url": BASE_URL, "checks": {}, "console_errors": []}
    with sync_playwright() as playwright:
        browser_path = os.environ.get("KEZAI_BROWSER_PATH", playwright.chromium.executable_path)
        browser = playwright.chromium.launch(headless=True, executable_path=browser_path)
        try:
            context = browser.new_context(viewport={"width": 390, "height": 844})
            page = context.new_page()
            page.on(
                "console",
                lambda message: result["console_errors"].append(message.text)
                if message.type == "error"
                else None,
            )

            page.goto(f"{BASE_URL}/mobile", wait_until="domcontentloaded", timeout=90000)
            page.locator('input[name="login_username"]').fill(USERNAME)
            page.locator('input[name="login_password"]').fill(PASSWORD)
            page.locator('form[action$="/join/login"] button[type="submit"]').click()
            page.wait_for_url(re.compile(r"^https?://[^/]+/latest"), timeout=90000)
            result["checks"]["login"] = True

            stamp = int(time.time() * 1000)
            question = f"科仔AI，2加3等于多少？只回答结果。验收编号{stamp}"
            sent = json_request(
                page,
                f"/chat/{CHANNEL_ID}",
                method="POST",
                body={"chat_channel_id": CHANNEL_ID, "message": question},
            )
            check(sent["status"] == 200 and sent["body"].get("message_id"), f"公开群聊提问失败：{sent}")
            source_id = sent["body"]["message_id"]
            result["source_message_id"] = source_id
            result["checks"]["question_sent"] = True

            reply = None
            last_messages = []
            deadline = time.time() + 60
            while time.time() < deadline:
                response = json_request(
                    page,
                    f"/chat/api/channels/{CHANNEL_ID}/messages?target_message_id={source_id}",
                )
                last_messages = response["body"].get("messages", [])
                for message in last_messages:
                    user = message.get("user") or {}
                    parent = message.get("in_reply_to") or {}
                    parent_id = parent.get("id") or message.get("in_reply_to_id")
                    if user.get("username") == "kezai_ai" and str(parent_id) == str(source_id):
                        reply = message
                        break
                    if str(message.get("id")) == str(source_id):
                        preview = ((message.get("thread") or {}).get("preview") or {})
                        last_reply_user = preview.get("last_reply_user") or {}
                        if last_reply_user.get("username") == "kezai_ai":
                            reply = {
                                "id": preview.get("last_reply_id"),
                                "message": preview.get("last_reply_excerpt", ""),
                                "user": last_reply_user,
                            }
                            break
                if reply:
                    break
                page.wait_for_timeout(2000)

            check(reply, f"60秒内没有识别到科仔 AI 的公开回复：{json.dumps(last_messages[-4:], ensure_ascii=False)}")
            check("5" in str(reply.get("message", "")), f"科仔 AI 回答不正确：{reply.get('message')}")
            result["reply_message_id"] = reply["id"]
            result["reply"] = reply["message"]
            result["checks"]["bot_identity_visible"] = True
            result["checks"]["public_reply_received"] = True
            result["checks"]["answer_correct"] = True

            page.goto(f"{BASE_URL}/chat/c/-/{CHANNEL_ID}", wait_until="commit", timeout=90000)
            page.wait_for_timeout(3000)
            scope = "public" if BASE_URL.startswith("https://") else "lan"
            page.screenshot(path=EVIDENCE / f"{scope}-ai-reply-mobile.png", full_page=True)
            result["checks"]["chat_page_visible"] = "科仔" in page.locator("body").inner_text()

            expected = (
                "Failed to load resource",
                "Content Security Policy",
                "Cross-Origin-Opener-Policy",
                "Mixed Content",
            )
            unexpected = [
                message for message in result["console_errors"] if not any(item in message for item in expected)
            ]
            result["unexpected_console_errors"] = unexpected
            check(not unexpected, f"页面出现异常：{' | '.join(unexpected)}")
            return result
        finally:
            browser.close()


if __name__ == "__main__":
    try:
        output = run()
        output["ok"] = True
        print(json.dumps(output, ensure_ascii=False, indent=2))
    except Exception as error:
        print(json.dumps({"ok": False, "error": f"{type(error).__name__}: {error}"}, ensure_ascii=False, indent=2))
        sys.exit(1)
