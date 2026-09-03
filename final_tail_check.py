import json
import os
import re
import sys
from pathlib import Path

from playwright.sync_api import sync_playwright


BASE_URL = "http://10.10.24.116"
ROOT = Path(__file__).resolve().parent
EVIDENCE = ROOT / "evidence"
result = {"checks": {}}


def check(value, message):
    if not value:
        raise AssertionError(message)


try:
    username = os.environ["KEZAI_QA_USERNAME"]
    password = os.environ["KEZAI_QA_PASSWORD"]
    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(headless=True, executable_path=playwright.chromium.executable_path)
        context = browser.new_context(viewport={"width": 390, "height": 844})
        page = context.new_page()
        page.goto(f"{BASE_URL}/mobile", wait_until="networkidle", timeout=30000)
        page.locator('input[name="login_username"]').fill(username)
        page.locator('input[name="login_password"]').fill(password)
        page.get_by_role("button", name="登录并进入社区").click()
        page.wait_for_url(re.compile(r"^http://10\.10\.24\.116/(latest)?$"), timeout=30000)
        page.wait_for_timeout(2500)

        logo = page.locator("#site-logo, img.logo-big, img.logo-small").first
        logo_src = logo.get_attribute("src") or ""
        check("discourse-logo" not in logo_src, "论坛内部仍显示默认 Discourse 标志")
        check("uploads/default" in logo_src, "论坛内部没有使用科仔标志")
        page.screenshot(path=EVIDENCE / "final-forum-branded.png", full_page=True)
        result["checks"]["forum_brand_logo"] = True
        result["checks"]["forum_logo_src"] = logo_src
        context.close()

        anonymous = browser.new_context(viewport={"width": 390, "height": 844})
        signup = anonymous.new_page()
        signup.goto(f"{BASE_URL}/signup", wait_until="networkidle", timeout=30000)
        standard_signup_buttons = signup.get_by_role(
            "button", name=re.compile(r"创建.*账号|注册|sign up|create account", re.I)
        ).count()
        check(standard_signup_buttons == 0, "普通注册入口仍可见")
        check(signup.url.endswith("/login-required"), "普通注册地址没有被保护")
        signup.screenshot(path=EVIDENCE / "final-signup-guard.png", full_page=True)
        result["checks"]["standard_signup_guarded"] = True
        result["checks"]["standard_signup_final_url"] = signup.url

        apk = anonymous.request.get(f"{BASE_URL}/Kezai-Community.apk")
        check(apk.ok and len(apk.body()) > 200000, "安卓安装包无法完整下载")
        result["checks"]["apk_status"] = apk.status
        result["checks"]["apk_bytes"] = len(apk.body())

        manifest_response = anonymous.request.get(f"{BASE_URL}/manifest.webmanifest")
        check(manifest_response.ok, "网页应用入口清单无法读取")
        manifest = manifest_response.json()
        check(manifest.get("name") == "科仔交流社区", "网页应用名称不正确")
        result["checks"]["web_manifest"] = True
        anonymous.close()
        browser.close()
    result["ok"] = True
except Exception as exc:
    result["ok"] = False
    result["error"] = f"{type(exc).__name__}: {exc}"

(EVIDENCE / "final-tail-check.json").write_text(
    json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8"
)
print(json.dumps(result, ensure_ascii=False, indent=2))
sys.exit(0 if result["ok"] else 1)
