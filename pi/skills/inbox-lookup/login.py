#!/usr/bin/env python3
"""Mints an ECFX admin session cookie by driving the Azure AD login in headless Chromium.

Runs inside the virtualenv that inbox_lookup.py creates -- it is the one part of this skill that
needs a real browser, because the O365 flow is interactive OIDC and cannot be replayed over plain
HTTP once MFA is enforced.

Reads O365_USERNAME / O365_PASSWORD / O365_TOTP_CODE / ECFX_ADMIN_URL from the environment and
prints {"cookie": ..., "expires": ...} as JSON on stdout. Progress goes to stderr.
"""

import json
import os
import sys
from urllib.parse import urlsplit

from playwright.sync_api import sync_playwright

TIMEOUT_MS = 45_000
# Distinct exit code so the caller can reinstall the browser and retry instead of just failing.
BROWSER_MISSING_EXIT = 3


def log(message: str) -> None:
    print(message, file=sys.stderr)


def domain_matches(cookie_domain: str, host: str) -> bool:
    domain = cookie_domain.lstrip(".")
    return host.lower() == domain.lower() or host.lower().endswith("." + domain.lower())


def settle(page) -> None:
    """networkidle never settles in the container (blocked telemetry hosts); give the SPA a moment instead."""
    try:
        page.wait_for_load_state("domcontentloaded", timeout=15000)
    except Exception:
        pass
    page.wait_for_timeout(4000)


def main() -> int:
    admin_url = os.environ.get("ECFX_ADMIN_URL", "https://admin.production.ecfxglobal.net/")
    username = os.environ["O365_USERNAME"]
    password = os.environ["O365_PASSWORD"]
    otp_code = os.environ["O365_TOTP_CODE"]

    split = urlsplit(admin_url)
    origin = f"{split.scheme}://{split.netloc}"
    host = split.hostname

    with sync_playwright() as playwright:
        try:
            browser = playwright.chromium.launch(headless=True, args=[
                "--disable-dev-shm-usage", "--disable-gpu", "--no-sandbox", "--disable-setuid-sandbox",
            ])
        except Exception as error:
            # Playwright keeps browsers in a HOME-relative cache, separate from the virtualenv, so
            # they can go missing on their own -- cleared cache, upgraded Playwright, another user.
            text = str(error)
            if "Executable doesn't exist" in text or "playwright install" in text:
                log("chromium is missing from the Playwright cache")
                sys.exit(BROWSER_MISSING_EXIT)
            raise
        context = browser.new_context()
        page = context.new_page()
        page.set_default_timeout(TIMEOUT_MS)

        page.goto(admin_url, wait_until="commit")
        # networkidle never settles in the container (blocked telemetry hosts); wait for the first screen instead.
        try:
            page.wait_for_selector("input[name='loginfmt'], input[type='email'], input[type='password']", timeout=TIMEOUT_MS)
        except Exception:
            pass

        # The Azure screens appear one at a time; each is optional because an existing browser
        # session can skip straight past it.
        user_field = page.locator("input[name='loginfmt'], input[type='email']")
        if user_field.is_visible():
            log("entering username")
            user_field.fill(username)
            page.locator("input[type='submit'], button[type='submit'], #idSIButton9").first.click()
            settle(page)

        password_field = page.locator("input[name='passwd'], input[type='password']")
        if password_field.is_visible():
            log("entering password")
            password_field.fill(password)
            page.locator("#idSIButton9, input[type='submit']").first.click()
            settle(page)

        otp_field = page.locator("#idTxtBx_SAOTCC_OTC, input[name='otc']")
        if otp_field.is_visible():
            log("entering TOTP code")
            otp_field.fill(otp_code)
            page.locator("#idSubmit_SAOTCC_Continue, #idSIButton9, input[type='submit']").first.click()
            settle(page)

        stay_signed_in = page.locator("#idSIButton9")
        if stay_signed_in.is_visible():
            log("answering 'stay signed in'")
            stay_signed_in.click()
            settle(page)

        # Any URL back on the admin origin means the callback has run and set the cookie.
        page.wait_for_url(lambda url: url.startswith(origin), timeout=TIMEOUT_MS)

        cookies = [c for c in context.cookies()
                   if c["name"] == "session" and domain_matches(c["domain"], host)]
        if not cookies:
            log(f"current URL: {page.url}")
            raise SystemExit(f"Login finished but no 'session' cookie was set for {host}")

        cookie = cookies[0]
        context.close()
        browser.close()

    expires = cookie.get("expires")
    print(json.dumps({
        "cookie": cookie["value"],
        "expires": expires if isinstance(expires, (int, float)) and expires > 0 else None,
    }))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as error:  # surfaced by the caller, which prints stderr on failure
        log(f"login failed: {type(error).__name__}: {error}")
        sys.exit(1)
