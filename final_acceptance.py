import json
import os
import re
import secrets
import sys
import time
from pathlib import Path

from playwright.sync_api import sync_playwright


BASE_URL = "http://10.10.24.116"
ROOT = Path(__file__).resolve().parent
EVIDENCE = ROOT / "evidence"
EVIDENCE.mkdir(parents=True, exist_ok=True)

run_id = str(int(time.time()))[-9:]
username = f"qa_final_{run_id}"
password = f"Kz!{secrets.token_urlsafe(12)}9a"
real_name = "最终验收用户"
office = "QA-A302"
avatar_file = ROOT / "brand" / "kezai-app-icon-v1.png"

result = {
    "username": username,
    "real_name": real_name,
    "office": office,
    "checks": {},
    "console_errors": [],
    "created_safe_post_title": None,
}


def check(condition, message):
    if not condition:
        raise AssertionError(message)


def record_console(page):
    def on_console(message):
        if message.type == "error":
            result["console_errors"].append(message.text)

    page.on("console", on_console)


def run():
    with sync_playwright() as playwright:
        browser_path = os.environ.get("KEZAI_BROWSER_PATH", playwright.chromium.executable_path)
        browser = playwright.chromium.launch(headless=True, executable_path=browser_path)
        try:
            anonymous = browser.new_context(viewport={"width": 1440, "height": 980})
            page = anonymous.new_page()
            record_console(page)

            response = page.goto(f"{BASE_URL}/mobile", wait_until="networkidle", timeout=30000)
            check(response and response.status == 200, "移动入口无法打开")
            check(page.title() == "科仔交流社区", "网页标题不正确")
            check(page.get_by_text("请共同维护社区纯净度").is_visible(), "社区纯净提示不可见")
            check(page.locator('input[name="login_password"]').is_visible(), "登录密码输入框不可见")
            background = page.locator(".wallpaper").get_attribute("src") or ""
            check("kezai-duo-v2" in background, "科仔背景板没有生效")
            page.screenshot(path=EVIDENCE / "final-desktop-login.png", full_page=True)
            result["checks"]["desktop_login"] = True

            page.set_viewport_size({"width": 390, "height": 844})
            page.goto(f"{BASE_URL}/mobile", wait_until="networkidle", timeout=30000)
            page.screenshot(path=EVIDENCE / "final-mobile-login.png", full_page=True)
            result["checks"]["mobile_web_entry"] = True

            latest = page.goto(f"{BASE_URL}/latest", wait_until="networkidle", timeout=30000)
            check("/latest" not in page.url, "未登录用户仍可直接访问论坛")
            result["checks"]["anonymous_forum_blocked"] = True

            page.goto(f"{BASE_URL}/mobile", wait_until="networkidle", timeout=30000)
            page.get_by_role("button", name="新成员实名登记").click()
            check(page.locator('input[name="username"]').is_visible(), "实名登记表没有打开")
            check(page.locator('input[name="password"]').is_visible(), "登记密码字段缺失")
            check(page.locator('input[name="real_name"]').is_visible(), "姓名字段缺失")
            check(page.locator('input[name="office"]').is_visible(), "办公室字段缺失")
            check(page.locator('input[name="avatar"]').is_visible(), "头像字段缺失")

            page.locator('input[name="username"]').fill(username)
            page.locator('input[name="password"]').fill(password)
            page.locator('input[name="real_name"]').fill(real_name)
            page.locator('input[name="office"]').fill(office)
            page.locator('input[name="avatar"]').set_input_files(str(avatar_file))
            preview_src = page.locator("#avatar-preview").get_attribute("src") or ""
            check(preview_src.startswith("blob:") or preview_src.startswith("data:"), "所选头像没有立即预览")
            page.locator('input[name="legal_agreement"]').check()
            page.screenshot(path=EVIDENCE / "final-mobile-register.png", full_page=True)

            page.get_by_role("button", name="完成登记并进入社区").click()
            page.wait_for_url(re.compile(r"^http://10\.10\.24\.116/(latest)?$"), timeout=30000)
            result["checks"]["registration_reached_forum"] = True

            auth_cookie = next((cookie for cookie in anonymous.cookies() if cookie["name"] == "_t"), None)
            check(auth_cookie is not None, "登记后没有登录凭据")
            expiry_days = round((auth_cookie["expires"] - time.time()) / 86400)
            result["checks"]["session_expires_in_days"] = expiry_days
            check(expiry_days > 300, "登录保存时间不足 300 天")

            page.goto(f"{BASE_URL}/join/account", wait_until="networkidle", timeout=30000)
            account_text = page.locator("body").inner_text()
            check(real_name in account_text, "成员页没有显示姓名")
            check(office in account_text, "成员页没有显示办公室")
            check("KZ-M-" in account_text, "成员编号格式不正确")
            check("已完成内部实名登记" in account_text, "实名登记状态缺失")
            page.screenshot(path=EVIDENCE / "final-member-page.png", full_page=True)
            result["checks"]["member_identity_page"] = True

            storage_state = anonymous.storage_state()
            reopened = browser.new_context(storage_state=storage_state, viewport={"width": 390, "height": 844})
            reopened_page = reopened.new_page()
            record_console(reopened_page)
            reopened_page.goto(f"{BASE_URL}/mobile", wait_until="domcontentloaded", timeout=30000)
            reopened_page.wait_for_timeout(2500)
            check("/mobile" not in reopened_page.url and "/join" not in reopened_page.url, "重新打开后仍要求登录")
            reopened_page.screenshot(path=EVIDENCE / "final-session-reopen.png", full_page=True)
            result["checks"]["remembered_after_reopen"] = True

            reopened_page.goto(f"{BASE_URL}/chat/c/-/3", wait_until="domcontentloaded", timeout=30000)
            reopened_page.wait_for_timeout(2500)
            chat_text = reopened_page.locator("body").inner_text()
            check("公屏聊天室" in chat_text, "公屏聊天室无法打开")
            result["checks"]["public_chat_accessible"] = True

            safe_title = f"最终安全验收主题 {run_id}"
            result["created_safe_post_title"] = safe_title
            post_script = """
                async ({title, raw}) => {
                  const csrfResponse = await fetch('/session/csrf.json', {credentials: 'same-origin'});
                  const {csrf} = await csrfResponse.json();
                  const response = await fetch('/posts.json', {
                    method: 'POST',
                    credentials: 'same-origin',
                    headers: {
                      'Content-Type': 'application/json',
                      'X-CSRF-Token': csrf,
                      'X-Requested-With': 'XMLHttpRequest'
                    },
                    body: JSON.stringify({title, raw, category: 4})
                  });
                  return {status: response.status, body: await response.text()};
                }
            """
            safe_post = reopened_page.evaluate(
                post_script,
                {"title": safe_title, "raw": "这是一次正常的内部工作交流验收，不包含敏感信息。内容长度满足论坛发帖要求。"},
            )
            check(200 <= safe_post["status"] < 300, f"正常内容提交失败：{safe_post['status']}")
            check(re.search(r"review|pending|queued|审核|success", safe_post["body"], re.I), "新成员首帖没有进入审核")
            result["checks"]["first_post_reviewed"] = True

            blocked_post = reopened_page.evaluate(
                post_script,
                {"title": f"违规拦截验收 {run_id}", "raw": "这里包含出售银行卡的违法招揽内容，用于验证自动拦截。"},
            )
            check(blocked_post["status"] >= 400, "违法招揽内容没有被拦截")
            result["checks"]["blocked_phrase_rejected"] = True
            reopened.close()

            remembered = browser.new_context(storage_state=storage_state, viewport={"width": 390, "height": 844})
            remembered.clear_cookies(name="_t")
            login_page = remembered.new_page()
            record_console(login_page)
            login_page.goto(f"{BASE_URL}/mobile", wait_until="networkidle", timeout=30000)
            remembered_username = login_page.locator('input[name="login_username"]').input_value()
            remembered_avatar = login_page.locator("#login-avatar-preview").get_attribute("src") or ""
            login_page.screenshot(path=EVIDENCE / "final-remembered-login.png", full_page=True)
            check(remembered_username == username, "登录页没有记住上次账号")
            check("user_avatar" in remembered_avatar or "/uploads/" in remembered_avatar, "登录页没有显示已选择头像")
            result["checks"]["remembered_profile_on_login"] = True

            login_page.locator('input[name="login_password"]').fill("WrongPassword2026!")
            login_page.get_by_role("button", name="登录并进入社区").click()
            login_page.wait_for_load_state("networkidle")
            check("用户名或密码不正确" in login_page.locator("body").inner_text(), "错误密码没有被拒绝")
            result["checks"]["wrong_password_rejected"] = True

            login_page.locator('input[name="login_password"]').fill(password)
            login_page.get_by_role("button", name="登录并进入社区").click()
            login_page.wait_for_url(re.compile(r"^http://10\.10\.24\.116/(latest)?$"), timeout=30000)
            result["checks"]["correct_password_accepted"] = True
            remembered.close()

            signup_context = browser.new_context(viewport={"width": 390, "height": 844})
            signup_page = signup_context.new_page()
            signup_page.goto(f"{BASE_URL}/signup", wait_until="networkidle", timeout=30000)
            body = signup_page.locator("body").inner_text()
            visible_standard_buttons = signup_page.get_by_role(
                "button", name=re.compile(r"创建.*账号|注册|sign up|create account", re.I)
            ).count()
            check(visible_standard_buttons == 0, "标准注册入口仍然可见")
            guarded_destination = signup_page.url.endswith("/login-required") or bool(re.search(r"邀请|invite", body, re.I))
            check(guarded_destination, "标准注册地址没有被登录或邀请限制保护")
            signup_page.screenshot(path=EVIDENCE / "final-signup-guard.png", full_page=True)
            result["checks"]["standard_signup_guarded"] = True
            result["checks"]["standard_signup_final_url"] = signup_page.url

            apk_response = signup_context.request.get(f"{BASE_URL}/Kezai-Community.apk")
            check(apk_response.ok, "安卓安装包无法下载")
            result["checks"]["apk_status"] = apk_response.status
            result["checks"]["apk_bytes"] = len(apk_response.body())

            manifest_response = signup_context.request.get(f"{BASE_URL}/manifest.webmanifest")
            check(manifest_response.ok, "网页应用入口清单无法读取")
            manifest = manifest_response.json()
            check(manifest.get("name") == "科仔交流社区", "网页应用名称不正确")
            result["checks"]["web_manifest"] = True
            signup_context.close()

            expected_console_fragments = ("Cross-Origin-Opener-Policy", "status of 422")
            unexpected_console_errors = [
                message
                for message in result["console_errors"]
                if not any(fragment in message for fragment in expected_console_fragments)
            ]
            result["checks"]["console_error_count"] = len(result["console_errors"])
            result["checks"]["unexpected_console_error_count"] = len(unexpected_console_errors)
            check(not unexpected_console_errors, "页面出现了意外错误")
        finally:
            browser.close()


if __name__ == "__main__":
    try:
        run()
        result["ok"] = True
    except Exception as exc:
        result["ok"] = False
        result["error"] = f"{type(exc).__name__}: {exc}"
    output = EVIDENCE / "final-acceptance-result.json"
    output.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(result, ensure_ascii=False, indent=2))
    sys.exit(0 if result["ok"] else 1)
