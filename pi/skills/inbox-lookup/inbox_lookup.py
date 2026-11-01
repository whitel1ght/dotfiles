#!/usr/bin/env python3
"""Pull an ECFX inbox item's full record off the admin site.

Standard library only. The single thing this cannot do alone is mint a session cookie -- that needs
a real browser to get through Azure AD -- so it delegates to login.py, which runs in a virtualenv
this skill creates for itself on demand. Everything else (fetching, parsing, reporting) is stdlib,
so once a cookie is cached the whole tool is dependency free.

Run with --help for usage.
"""

from __future__ import annotations

import argparse
import base64
import hmac
import hashlib
import json
import os
import re
import shutil
import struct
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from collections import Counter
from html.parser import HTMLParser
from pathlib import Path

SKILL_DIR = Path(__file__).resolve().parent
LOGIN_SCRIPT = SKILL_DIR / "login.py"
# Deliberately outside the skill: SKILL_DIR is a plugin install path that changes on every
# version bump (or is a repo checkout that gets synced), and this venv is ~150 MB of installed
# packages a fresh version bump has no reason to lose and rebuild. Home-relative like
# SESSION_CACHE below, for the same reason: found wherever this runs.
VENV_DIR = Path.home() / ".cache" / "inbox-lookup" / "venv"

DEFAULT_ADMIN_URL = "https://admin.production.ecfxglobal.net/"
# Home-relative on every platform rather than a per-OS cache directory, so the same cached cookie is
# found wherever this runs. Delete the file (or pass --relogin) to force a fresh login.
SESSION_CACHE = Path.home() / ".cache" / "sadron" / "admin-session.json"
DEFAULT_MAX_JOB_PAGES = 5

BROWSER_MISSING_EXIT = 3   # must match login.py

APP_NAME = "ecfx"
CONFIG_FILENAME = "ecfx.env"
CREDENTIAL_KEYS = ("ECFX_ADMIN_URL", "O365_USERNAME", "O365_PASSWORD", "O365_TOTP_SECRET")
SECRET_KEYS = {"O365_PASSWORD", "O365_TOTP_SECRET"}


# --------------------------------------------------------------------------------------
# Credentials
# --------------------------------------------------------------------------------------

def config_dirs(os_name: str | None = None, platform: str | None = None,
                home: Path | None = None, environ: dict | None = None) -> list[Path]:
    """Where credentials may live, most preferred first.

    Deliberately none of these are inside the skill: the skill is a checkout that gets synced and
    shared, and credentials should outlive and stay out of it. Each OS gets its native location,
    plus ~/.ecfx as a fallback that behaves identically everywhere.

    The parameters exist so the per-OS choice can be tested from any machine; leave them unset.
    """
    os_name = os.name if os_name is None else os_name
    platform = sys.platform if platform is None else platform
    home = Path.home() if home is None else home
    environ = os.environ if environ is None else environ

    dirs: list[Path] = []
    if environ.get("XDG_CONFIG_HOME"):                    # honoured on any OS if the user set it
        dirs.append(Path(environ["XDG_CONFIG_HOME"]) / APP_NAME)
    if os_name == "nt":
        for variable in ("APPDATA", "LOCALAPPDATA"):
            if environ.get(variable):
                dirs.append(Path(environ[variable]) / APP_NAME)
    else:
        dirs.append(home / ".config" / APP_NAME)
        if platform == "darwin":
            dirs.append(home / "Library" / "Application Support" / APP_NAME)
    dirs.append(home / f".{APP_NAME}")
    return list(dict.fromkeys(dirs))                      # dedupe, keep order


def config_file_candidates() -> list[Path]:
    """Every credential file consulted, in order."""
    candidates: list[Path] = []
    if os.environ.get("ECFX_ENV_FILE"):
        candidates.append(Path(os.environ["ECFX_ENV_FILE"]))
    candidates.extend(directory / CONFIG_FILENAME for directory in config_dirs())
    # Last resort: a Sadron checkout that happens to carry the same O365_* values. Nothing here
    # depends on that project existing.
    candidates.append(Path(os.environ.get("SADRON_DIR", Path.home() / "gitlab" / "Sadron")) / ".env")
    return candidates


def parse_env_file(path: Path) -> dict[str, str]:
    """Reads KEY=value lines, ignoring comments and blanks, tolerating quotes."""
    values: dict[str, str] = {}
    try:
        # Explicit encoding: Windows would otherwise decode this with the ANSI code page.
        text = path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        return values
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
            value = value[1:-1]
        values[key.strip()] = value
    return values


def load_config() -> dict[str, str]:
    """Credentials, most explicit source first. The real environment always wins, so a one-off
    override works without touching any file."""
    config: dict[str, str] = {}
    for path in config_file_candidates():
        for key, value in parse_env_file(path).items():
            config.setdefault(key, value)

    for key in CREDENTIAL_KEYS:
        if os.environ.get(key):
            config[key] = os.environ[key]

    config.setdefault("ECFX_ADMIN_URL", DEFAULT_ADMIN_URL)
    if not config["ECFX_ADMIN_URL"].endswith("/"):
        config["ECFX_ADMIN_URL"] += "/"
    return config


def show_config() -> None:
    """Prints where credentials are looked for and what resolved -- the answer to 'where do I put
    these?' on whatever machine you happen to be on."""
    config = load_config()
    print(f"Platform: {sys.platform} ({os.name})")
    print(f"\nCredential files, in order (* = exists):")
    for path in config_file_candidates():
        print(f"  {'*' if path.is_file() else ' '} {path}")
    print(f"\nPreferred location for new setups:\n    {config_dirs()[0] / CONFIG_FILENAME}")
    print(f"    create it with: {Path(__file__).name} --init-config\n")
    print("Resolved values:")
    for key in CREDENTIAL_KEYS:
        value = config.get(key, "")
        if not value:
            shown = "(not set)"
        elif key in SECRET_KEYS:
            shown = f"(set, {len(value)} chars)"
        else:
            shown = value
        print(f"  {key:<18} {shown}")
    print(f"\nSession cache: {SESSION_CACHE}"
          f"{' (present)' if SESSION_CACHE.is_file() else ' (none yet)'}")
    print(f"Login virtualenv: {VENV_DIR}"
          f"{' (built)' if (VENV_DIR / '.bootstrapped').exists() else ' (not built yet)'}")


def init_config() -> None:
    """Writes an empty credential template to the platform's config location."""
    path = config_dirs()[0] / CONFIG_FILENAME
    if path.exists():
        print(f"Already exists: {path}")
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        "# inbox-lookup credentials. Fill in and keep private.\n"
        "# Only needed to mint a session cookie; once one is cached this file is not read.\n\n"
        f"ECFX_ADMIN_URL={DEFAULT_ADMIN_URL}\n"
        "O365_USERNAME=\n"
        "O365_PASSWORD=\n"
        "O365_TOTP_SECRET=\n",
        encoding="utf-8")
    restrict_permissions(path)
    print(f"Created {path}\nEdit it and fill in the O365_* values.")


def restrict_permissions(path: Path) -> None:
    """Owner-only where the filesystem supports it. On Windows this only clears the read-only bit,
    so it is best effort rather than a guarantee."""
    try:
        os.chmod(path, 0o600)
    except (OSError, NotImplementedError):
        pass


# --------------------------------------------------------------------------------------
# TOTP (RFC 6238) -- verified against the RFC test vectors
# --------------------------------------------------------------------------------------

def totp(secret_b32: str, when: float | None = None, digits: int = 6, step: int = 30) -> str:
    secret = secret_b32.replace(" ", "").upper()
    key = base64.b32decode(secret + "=" * (-len(secret) % 8))
    counter = int((time.time() if when is None else when) // step)
    digest = hmac.new(key, struct.pack(">Q", counter), hashlib.sha1).digest()
    offset = digest[-1] & 0x0F
    code = struct.unpack(">I", digest[offset:offset + 4])[0] & 0x7FFFFFFF
    return str(code % 10 ** digits).zfill(digits)


# --------------------------------------------------------------------------------------
# Session cookie
# --------------------------------------------------------------------------------------

class NotAuthenticated(Exception):
    """The cookie is no longer good and the caller should mint a new one."""


class Session:
    def __init__(self, config: dict[str, str], explicit_cookie: str | None = None, quiet: bool = False):
        self.config = config
        self.admin_url = config["ECFX_ADMIN_URL"]
        self.quiet = quiet
        self._cookie = explicit_cookie
        self._explicit = explicit_cookie is not None

    def log(self, message: str) -> None:
        if not self.quiet:
            print(f"[admin] {message}", file=sys.stderr)

    def cookie(self) -> str:
        if self._cookie is None:
            self._cookie = self._from_cache() or self.refresh()
        return self._cookie

    def _from_cache(self) -> str | None:
        try:
            cached = json.loads(SESSION_CACHE.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return None
        if cached.get("adminUrl") != self.admin_url:
            return None
        expires = cached.get("expires")
        if isinstance(expires, (int, float)) and expires > 0 and expires <= time.time():
            self.log("cached session has expired")
            return None
        return cached.get("cookie") or None

    def refresh(self) -> str:
        """Mints a new cookie through the browser login."""
        if self._explicit:
            raise NotAuthenticated("the cookie passed with --cookie is not valid")
        cookie, expires = browser_login(self.config, self.log)
        self._cookie = cookie
        self._write_cache(cookie, expires)
        return cookie

    def _write_cache(self, cookie: str, expires: float | None) -> None:
        try:
            SESSION_CACHE.parent.mkdir(parents=True, exist_ok=True)
            # adminUrl + cookie are the keys Sadron's Java reader expects; extras are ignored there.
            payload = {
                "adminUrl": self.admin_url,
                "cookie": cookie,
                "acquiredAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            }
            if expires:
                payload["expires"] = expires
            SESSION_CACHE.write_text(json.dumps(payload, indent=2), encoding="utf-8")
            restrict_permissions(SESSION_CACHE)
            self.log(f"session cached at {SESSION_CACHE}")
        except OSError as error:
            self.log(f"could not cache session: {error}")


def install_browsers(python: Path, log) -> None:
    """Downloads the Chromium build this Playwright expects, into the user's browser cache."""
    log("downloading chromium (~275 MB, one time)...")
    subprocess.run([str(python), "-m", "playwright", "install", "chromium"],
                   stdout=sys.stderr, check=True)


def venv_python(os_name: str | None = None) -> Path:
    """Windows puts the interpreter in Scripts\\python.exe, everything else in bin/python."""
    if (os.name if os_name is None else os_name) == "nt":
        return VENV_DIR / "Scripts" / "python.exe"
    return VENV_DIR / "bin" / "python"


def ensure_venv(log) -> Path:
    """Creates the skill's own virtualenv with Playwright in it, the first time a login is needed.

    A marker file records that the install actually finished, so a half-built venv from an
    interrupted or failed bootstrap gets rebuilt rather than silently reused.
    """
    python = venv_python()
    marker = VENV_DIR / ".bootstrapped"
    if python.exists() and marker.exists():
        return python

    # Pip on a work machine is often pointed at a private index that these public packages are not
    # in, and whose credentials expire. Bootstrap against PyPI explicitly and ignore any pip.conf.
    pip_env = {k: v for k, v in os.environ.items() if not k.startswith("PIP_")}
    pip_env["PIP_INDEX_URL"] = os.environ.get("INBOX_LOOKUP_PIP_INDEX", "https://pypi.org/simple")
    pip_env["PIP_CONFIG_FILE"] = os.devnull

    log("first login on this machine -- creating the skill's virtualenv (one time)")
    if VENV_DIR.exists():
        shutil.rmtree(VENV_DIR)
    # pip and the Playwright installer both chatter on stdout; send that to stderr so it can never
    # end up inside the report -- it would corrupt --json outright.
    noise = {"stdout": sys.stderr, "check": True}
    try:
        subprocess.run([sys.executable, "-m", "venv", str(VENV_DIR)], **noise)
        log("installing playwright...")
        subprocess.run([str(python), "-m", "pip", "install", "--quiet", "playwright"],
                       env=pip_env, **noise)
        install_browsers(python, log)
    except subprocess.CalledProcessError as error:
        raise SystemExit(
            f"Could not build the skill's virtualenv (step failed: {error.cmd[1:3]}).\n"
            f"Install it by hand with:\n"
            f"  python3 -m venv {VENV_DIR}\n"
            f"  {python} -m pip install --index-url https://pypi.org/simple playwright\n"
            f"  {python} -m playwright install chromium\n"
            f"  touch {marker}\n"
            f"Or skip the browser entirely by passing --cookie (see SKILL.md)."
        ) from None
    marker.touch()
    return python


def browser_login(config: dict[str, str], log) -> tuple[str, float | None]:
    missing = [k for k in ("O365_USERNAME", "O365_PASSWORD", "O365_TOTP_SECRET") if not config.get(k)]
    if missing:
        raise SystemExit(
            f"Cannot log in: {', '.join(missing)} not set.\n"
            f"Put them in ~/.config/ecfx/ecfx.env (see the skill's SKILL.md), export them, or pass\n"
            f"an existing cookie with --cookie."
        )

    python = ensure_venv(log)
    log(f"logging in to {config['ECFX_ADMIN_URL']} as {config['O365_USERNAME']} (O365 + TOTP, ~1 min)...")

    def attempt():
        # Build the environment fresh each time: a TOTP code is only valid for 30 seconds, so one
        # generated before a browser download would be long expired by the retry.
        env = {**os.environ, **{k: v for k, v in config.items() if v}}
        env["O365_TOTP_CODE"] = totp(config["O365_TOTP_SECRET"])
        return subprocess.run([str(python), str(LOGIN_SCRIPT)], env=env, capture_output=True,
                              text=True, encoding="utf-8")

    result = attempt()
    if result.returncode == BROWSER_MISSING_EXIT:
        log("chromium is missing from the Playwright cache; reinstalling it...")
        install_browsers(python, log)
        result = attempt()
    if result.returncode != 0:
        sys.stderr.write(result.stderr)
        raise SystemExit(f"Login failed (exit {result.returncode}). See the output above.")
    for line in result.stderr.splitlines():
        log(f"login: {line}")
    try:
        payload = json.loads(result.stdout.strip().splitlines()[-1])
    except (ValueError, IndexError):
        sys.stderr.write(result.stdout)
        raise SystemExit("Login produced no usable result.")
    return payload["cookie"], payload.get("expires")


# --------------------------------------------------------------------------------------
# HTTP
# --------------------------------------------------------------------------------------

class NoRedirects(urllib.request.HTTPRedirectHandler):
    """Keeps redirects visible: a bounce to the identity provider means the cookie is dead, and
    following it would return a login page with a perfectly successful 200."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise Redirected(newurl)


class Redirected(Exception):
    def __init__(self, location: str):
        super().__init__(location)
        self.location = location


LOGIN_HINTS = ("microsoftonline.com", "/login", "/authorize", "/oidc")

_opener = urllib.request.build_opener(NoRedirects)


def http_fetch(url: str, cookie: str, timeout: int = 60) -> tuple[bytes, object]:
    """GET a URL, following same-origin redirects but treating an IdP bounce as unauthenticated.

    Returns the undecoded body and the response headers, so callers that need exact bytes -- saving
    a .eml, say -- are not at the mercy of a charset guess.
    """
    current = url
    for _ in range(5):
        request = urllib.request.Request(current, headers={
            "Cookie": f"session={cookie}",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "User-Agent": "sadron-inbox-lookup/1.0",
        })
        try:
            with _opener.open(request, timeout=timeout) as response:
                return response.read(), response.headers
        except Redirected as redirect:
            target = urllib.parse.urljoin(current, redirect.location)
            if any(hint in target.lower() for hint in LOGIN_HINTS):
                raise NotAuthenticated(target)
            current = target
        except urllib.error.HTTPError as error:
            if error.code in (401, 403):
                raise NotAuthenticated(f"HTTP {error.code}") from None
            raise SystemExit(f"GET {current} failed: HTTP {error.code} {error.reason}")
        except urllib.error.URLError as error:
            raise SystemExit(f"GET {current} failed: {error.reason}")
    raise SystemExit(f"Too many redirects fetching {url}")


def http_get(url: str, cookie: str, timeout: int = 60) -> str:
    body, headers = http_fetch(url, cookie, timeout)
    return body.decode(headers.get_content_charset() or "utf-8", errors="replace")


class Fetcher:
    """Fetches admin pages, re-logging in once if the session has expired."""

    def __init__(self, session: Session, keep_raw: bool = False):
        self.session = session
        self.admin_url = session.admin_url
        self.pages: dict[str, str] = {}
        self.keep_raw = keep_raw

    def get(self, url: str) -> str:
        try:
            html = http_get(url, self.session.cookie())
        except NotAuthenticated:
            self.session.log("session expired, re-authenticating...")
            html = http_get(url, self.session.refresh())
        if self.keep_raw:
            self.pages[url] = html
        return html

    def get_bytes(self, url: str) -> tuple[bytes, object]:
        """Undecoded body, for downloads that must be preserved byte for byte."""
        try:
            return http_fetch(url, self.session.cookie())
        except NotAuthenticated:
            self.session.log("session expired, re-authenticating...")
            return http_fetch(url, self.session.refresh())

    def absolute(self, href: str) -> str:
        if href.startswith(("http://", "https://")):
            return href
        return self.admin_url + href.lstrip("/")


# --------------------------------------------------------------------------------------
# Minimal HTML DOM -- enough to query the admin's Flask-Admin tables
# --------------------------------------------------------------------------------------

VOID_TAGS = {"area", "base", "br", "col", "embed", "hr", "img", "input",
             "link", "meta", "param", "source", "track", "wbr"}
# Tags that should start a new line when rendering prose.
BLOCK_TAGS = {"p", "div", "tr", "li", "ul", "ol", "table", "blockquote", "pre", "hr",
              "h1", "h2", "h3", "h4", "h5", "h6", "section", "article", "header", "footer"}
# Tags the admin templates leave unclosed; a new one of these implicitly closes the open one.
AUTO_CLOSE = {
    "td": {"td", "th", "tr"}, "th": {"td", "th", "tr"}, "tr": {"tr"},
    "li": {"li"}, "p": {"p"}, "option": {"option"},
    "thead": {"tbody", "tfoot"}, "tbody": {"tbody", "tfoot"},
}


class Node:
    __slots__ = ("tag", "attrs", "children", "parent")

    def __init__(self, tag: str, attrs: dict[str, str] | None = None, parent: "Node|None" = None):
        self.tag = tag
        self.attrs = attrs or {}
        self.children: list = []
        self.parent = parent

    @property
    def classes(self) -> set[str]:
        return set(self.attrs.get("class", "").split())

    def elements(self) -> list["Node"]:
        return [c for c in self.children if isinstance(c, Node)]

    def walk(self):
        for child in self.children:
            if isinstance(child, Node):
                yield child
                yield from child.walk()

    def find_all(self, tag: str | None = None, cls: str | None = None) -> list["Node"]:
        return [n for n in self.walk()
                if (tag is None or n.tag == tag) and (cls is None or cls in n.classes)]

    def find(self, tag: str | None = None, cls: str | None = None) -> "Node|None":
        for node in self.walk():
            if (tag is None or node.tag == tag) and (cls is None or cls in node.classes):
                return node
        return None

    def raw_text(self) -> str:
        """Concatenated text with whitespace intact -- what <pre> content needs."""
        parts: list[str] = []
        stack: list = [self]
        while stack:
            node = stack.pop()
            if isinstance(node, str):
                parts.append(node)
            else:
                stack.extend(reversed(node.children))
        return "".join(parts)

    def text(self) -> str:
        """Whitespace-collapsed text, with element boundaries kept as spaces so words don't fuse.

        Used for field values, which are single-line by nature; see block_text for prose.
        """
        parts: list[str] = []
        stack: list = [self]
        while stack:
            node = stack.pop()
            if isinstance(node, str):
                parts.append(node)
            else:
                if node.tag in ("script", "style"):
                    continue
                stack.append(" ")
                stack.extend(reversed(node.children))
                parts.append(" ")
        return re.sub(r"\s+", " ", "".join(parts)).strip()

    def block_text(self) -> str:
        """Readable text that keeps paragraph structure -- an email rendered as one 3000-character
        line is technically the same content and useless to read."""
        parts: list[str] = []

        def visit(node) -> None:
            if isinstance(node, str):
                parts.append(node)
                return
            if node.tag in ("script", "style"):
                return
            if node.tag == "br":
                parts.append("\n")
                return
            block = node.tag in BLOCK_TAGS
            if block:
                parts.append("\n")
            for child in node.children:
                visit(child)
            if block:
                parts.append("\n")

        visit(self)
        text = "".join(parts)
        text = re.sub(r"[^\S\n]+", " ", text)      # collapse spaces but keep newlines
        text = re.sub(r" *\n *", "\n", text)
        text = re.sub(r"\n{3,}", "\n\n", text)
        return text.strip()


class DomBuilder(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.root = Node("#document")
        self.current = self.root

    def handle_starttag(self, tag, attrs):
        while (self.current.tag in AUTO_CLOSE and tag in AUTO_CLOSE[self.current.tag]
               and self.current.parent is not None):
            self.current = self.current.parent
        node = Node(tag, {k: (v or "") for k, v in attrs}, self.current)
        self.current.children.append(node)
        if tag not in VOID_TAGS:
            self.current = node

    def handle_startendtag(self, tag, attrs):
        node = Node(tag, {k: (v or "") for k, v in attrs}, self.current)
        self.current.children.append(node)

    def handle_endtag(self, tag):
        node = self.current
        while node is not None and node.tag != tag:
            node = node.parent
        if node is not None and node.parent is not None:
            self.current = node.parent

    def handle_data(self, data):
        self.current.children.append(data)


def parse_html(html: str) -> Node:
    builder = DomBuilder()
    builder.feed(html)
    builder.close()
    return builder.root


def table_rows(table: Node) -> list[Node]:
    """Direct data <tr> children, descending into tbody but never into a nested table, and never
    returning <thead> rows -- the jobs tables carry a header row that is not an attempt."""
    rows = []
    for child in table.elements():
        if child.tag == "tr":
            rows.append(child)
        elif child.tag in ("tbody", "tfoot"):
            rows.extend(c for c in child.elements() if c.tag == "tr")
    return rows


def cell_value(cell: Node) -> str:
    pre = cell.find("pre")
    return pre.raw_text().strip() if pre else cell.text()


def label_value_table(doc: Node) -> dict[str, str]:
    """The admin's detail table: <td><b>Label</b></td><td>value</td>."""
    fields: dict[str, str] = {}
    table = doc.find("table", cls="searchable")
    if table is None:
        return fields
    for row in table_rows(table):
        cells = row.elements()
        if len(cells) < 2:
            continue
        label = cells[0].find("b")
        if label is None:
            continue
        fields[label.text().strip()] = cell_value(cells[1])
    return fields


# --------------------------------------------------------------------------------------
# Inbox item parsing
# --------------------------------------------------------------------------------------

STACK_MARKERS = ("Traceback (most recent call last)", '\n  File "', "\n\tat ", "\n    at ")


def looks_like_stack_trace(text: str) -> bool:
    return any(marker in text for marker in STACK_MARKERS)


def extract_stack_trace(doc: Node, fields: dict[str, str]) -> str:
    for label, value in fields.items():
        lowered = label.lower()
        if ("trace" in lowered or "stack" in lowered) and value and value != "None":
            return value
    best = ""
    for pre in doc.find_all("pre"):
        text = pre.raw_text().strip()
        if looks_like_stack_trace(text) and len(text) > len(best):
            best = text
    return best


def job_id_from(href: str | None) -> str | None:
    if not href:
        return None
    parts = href.split("/")
    for index, part in enumerate(parts[:-1]):
        if part in ("job", "dms_job"):
            return parts[index + 1]
    return None


def is_present(value: str | None) -> bool:
    return bool(value) and value.strip() != "" and value != "None"


# Classes the admin has used for the nested per-item jobs table. `jobs-inline` was the original;
# `grid-inline` is what it renders today. Both are matched so a rollback does not re-break this.
JOB_TABLE_CLASSES = ("grid-inline", "jobs-inline")
# Header cells that identify a jobs table whatever its class, and name its columns.
JOB_TABLE_HEADERS = ("created", "status", "error exception", "error message")


def find_job_table(cell: Node) -> "Node|None":
    """The jobs table inside one label/value cell, located by class or by its header row.

    The class lookup is the precise path and stays first. The header fallback exists only so that a
    third rename does not cost another silent run, and it has to be careful: `find_all` is a
    pre-order walk over every descendant and `find_all("th")` descends too, so an enclosing wrapper
    table inherits its child's headers and would be returned instead of the jobs table itself. The
    jobs table is a leaf, so candidates containing another table are skipped (review M2).
    """
    for css_class in JOB_TABLE_CLASSES:
        table = cell.find("table", cls=css_class)
        if table is not None:
            return table
    for table in cell.find_all("table"):
        if table.find("table") is not None:
            continue
        headers = [h.text().strip().lower() for h in table.find_all("th")]
        if all(column in headers for column in JOB_TABLE_HEADERS):
            return table
    return None


def links_to_jobs(node: Node) -> bool:
    """Does anything under here link to a job page?

    Uses `job_id_from` rather than a substring: DMS job links are `/dms_job/<id>/`, in which `/job/`
    does not appear, so a literal test is dead code on half the call sites (review M1).
    """
    return any(job_id_from(a.attrs.get("href")) for a in node.find_all("a"))


def header_columns(table: Node) -> dict:
    """Lower-cased header text -> column index, for the table's own header row."""
    header = table.find("thead") or table
    return {h.text().strip().lower(): i for i, h in enumerate(header.find_all("th"))}


def parse_job_rows(cell: Node, kind: str, fetcher: Fetcher) -> list[dict]:
    """Reads the inline jobs table. Every row already carries status and error, so no requests yet."""
    jobs: list[dict] = []
    table = find_job_table(cell)
    if table is None:
        return jobs
    # Columns by header name, not by position. Positional indices are only correct for one column
    # order: insert a column and status/exception/message all shift by one, and because the row still
    # has five-or-more cells nothing notices -- the run reports confidently wrong values, which is
    # worse than reporting none (review M2). An unrecognised header layout yields no rows, which the
    # caller then reports as unreadable.
    columns = header_columns(table)
    if not all(key in columns for key in ("created", "status", "error exception", "error message")):
        return jobs
    for row in table_rows(table):
        cells = row.elements()
        if len(cells) <= max(columns.values()):
            continue
        link = cells[0].find("a")
        href = link.attrs.get("href") if link else None
        jobs.append({
            "jobId": job_id_from(href),
            "kind": kind,
            "created": cells[columns["created"]].text().strip(),
            "status": cells[columns["status"]].text().strip(),
            "errorException": cells[columns["error exception"]].text().strip(),
            "errorMessage": cells[columns["error message"]].text().strip(),
            "url": fetcher.absolute(href) if href else None,
            "fields": {},
            "stackTrace": "",
        })
    # The admin already lists newest first; sort anyway so index 0 is reliably the latest attempt.
    jobs.sort(key=lambda job: job["created"], reverse=True)
    return jobs


def load_job_pages(job_lists: list[list[dict]], max_job_pages: int, fetcher: Fetcher) -> None:
    """Opens the job pages worth reading. A notice that retried ninety times repeats one trace, so
    prefer failures over successes and recent attempts over old ones."""
    for jobs in job_lists:
        if not jobs:
            continue
        candidates = [i for i, job in enumerate(jobs)
                      if is_present(job["errorException"]) or is_present(job["errorMessage"])]
        if not candidates:
            candidates = [0]
        limit = len(candidates) if max_job_pages < 0 else min(max_job_pages, len(candidates))
        if limit < len(candidates):
            fetcher.session.log(f"{len(candidates)} {jobs[0]['kind']} jobs to inspect; opening the "
                                f"{limit} most recent (use --all-jobs for every one)")
        for index in candidates[:limit]:
            job = jobs[index]
            if not job["url"]:
                continue
            page = parse_html(fetcher.get(job["url"]))
            job["fields"] = label_value_table(page)
            job["stackTrace"] = extract_stack_trace(page, job["fields"])


def fetch_notice(inbox_id: str, fetcher: Fetcher, include_email: bool, max_job_pages: int) -> dict:
    details_url = (fetcher.admin_url + "inbox_item/details/?id="
                   + urllib.parse.quote(inbox_id, safe=""))
    doc = parse_html(fetcher.get(details_url))

    table = doc.find("table", cls="searchable")
    if table is None:
        raise SystemExit(
            f"No inbox item detail table at {details_url}\n"
            f"Check that the inbox id exists in this environment."
        )

    fields: dict[str, str] = {}
    process_jobs: list[dict] = []
    dms_jobs: list[dict] = []
    raw_email = ""

    for row in table_rows(table):
        cells = row.elements()
        if len(cells) < 2:
            continue
        label = cells[0].find("b")
        if label is None:
            continue
        name = label.text().strip()
        value = cells[1]
        if name == "Process Jobs":
            process_jobs = parse_job_rows(value, "process", fetcher)
        elif name == "DMS Jobs":
            dms_jobs = parse_job_rows(value, "dms", fetcher)
        elif name == "Raw Content":
            raw_email = cell_value(value)
        else:
            fields[name] = cell_value(value)

    load_job_pages([process_jobs, dms_jobs], max_job_pages, fetcher)

    email_html = email_text = None
    if include_email:
        try:
            email_html = fetcher.get(fetcher.admin_url + f"inbox_item/get/{inbox_id}/email/")
            email_text = parse_html(email_html).block_text()
        except SystemExit as error:
            # The rendered email is a convenience; the raw MIME above is the source of truth.
            fetcher.session.log(f"could not fetch rendered email: {error}")

    all_jobs = process_jobs + dms_jobs
    failures = [j for j in all_jobs
                if is_present(j["errorException"]) or is_present(j["errorMessage"]) or j["stackTrace"]]

    # Watch "no rows parsed", not "no table found" (review M2). Asking inside parse_job_rows only
    # covered one of the ways the jobs go missing: a wrapper table matching the header fallback, a
    # column count that shifts, or a renamed detail-row label all yield zero rows without ever
    # reaching that branch -- and the label rename bypasses parse_job_rows entirely, so no guard
    # inside it could fire. Asked here, one site covers every path, process and DMS alike.
    jobs_unreadable = not all_jobs and links_to_jobs(table)
    if jobs_unreadable:
        # stderr rather than session.log(), which quiet=True silences. This is still only half the
        # story -- see the jobsUnreadable field below, which is what survives into --out.
        print(f"WARNING: {inbox_id} links to job pages but no job rows could be read. The admin "
              f"markup has changed -- check JOB_TABLE_CLASSES / JOB_TABLE_HEADERS and the column "
              f"order in inbox_lookup.py. Statuses and stack traces are MISSING for this item.",
              file=sys.stderr)

    return {
        "inboxId": inbox_id,
        "detailsUrl": details_url,
        "fields": fields,
        "processJobs": process_jobs,
        "dmsJobs": dms_jobs,
        "rawEmail": raw_email,
        "emailHtml": email_html,
        "emailText": email_text,
        "lastFailure": failures[0] if failures else None,
        # Carried in the payload because the warning above does not survive --out (review M3): the
        # durable artifact is what fix-jira-bug and --skip-lookup read, and a bare attemptCount of 0
        # there is indistinguishable from a notice that genuinely never ran. Absent means "read
        # fine"; consumers should treat True as "attempt data unknown", not "no attempts".
        "jobsUnreadable": jobs_unreadable,
    }


# --------------------------------------------------------------------------------------
# Reporting
# --------------------------------------------------------------------------------------

def all_jobs(report: dict) -> list[dict]:
    return report["processJobs"] + report["dmsJobs"]


def truncate(text: str, limit: int) -> str:
    if len(text) <= limit:
        return text
    return text[:limit] + f"\n... [truncated {len(text) - limit} chars]"


def render_traces(report: dict) -> str:
    out: list[str] = []
    for job in all_jobs(report):
        if not (is_present(job["errorException"]) or is_present(job["errorMessage"]) or job["stackTrace"]):
            continue
        out.append(f"=== {report['inboxId']} / {job['kind']} job {job['jobId']} ({job['status']}) ===")
        if is_present(job["errorException"]):
            out.append(f"Exception: {job['errorException']}")
        if is_present(job["errorMessage"]):
            out.append(f"Message: {job['errorMessage']}")
        if job["stackTrace"]:
            out.append(job["stackTrace"])
        out.append("")
    return "\n".join(out)


def render_full(report: dict, email_limit: int = 8000) -> str:
    out = ["=" * 64, f"Inbox item: {report['inboxId']}", report["detailsUrl"], "=" * 64, ""]
    for key, value in report["fields"].items():
        if value:
            out.append(f"{key + ':':<18} {value}")

    jobs = all_jobs(report)
    out.append("")
    out.append(f"--- Jobs ({len(jobs)} attempts) ---")
    if not jobs:
        out.append("(none)")
    histogram = Counter(job["errorException"] for job in jobs if is_present(job["errorException"]))
    for exception, count in sorted(histogram.items()):
        out.append(f"  {count:4d} x {exception}")

    for job in jobs:
        out.append("")
        out.append(f"[{job['kind']}] {job['created']}  {job['status']}  {job['jobId']}")
        if is_present(job["errorException"]):
            out.append(f"  Exception: {job['errorException']}")
        if is_present(job["errorMessage"]):
            out.append(f"  Message: {job['errorMessage']}")
        for key, value in job["fields"].items():
            if key in ("ID", "Created", "Status") or not is_present(value):
                continue
            if value in (job["stackTrace"], job["errorException"], job["errorMessage"]):
                continue
            out.append(f"  {key}: {value}")
        if job["stackTrace"]:
            out.append("  Stack trace:")
            out.extend(f"    {line}" for line in job["stackTrace"].splitlines())

    if report["emailText"]:
        out += ["", "--- Email (rendered) ---", truncate(report["emailText"], email_limit)]
    if report["rawEmail"]:
        out += ["", "--- Email (raw MIME, truncated) ---", truncate(report["rawEmail"], email_limit)]
    out.append("")
    return "\n".join(out)


# --------------------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------------------

def normalize_inbox_id(raw: str) -> str:
    """Accepts a bare id, an id without the prefix, or a pasted admin URL."""
    value = raw.strip()
    if "id=" in value:
        value = value.split("id=", 1)[1].split("&", 1)[0]
        value = urllib.parse.unquote(value)
    elif "/inbox_item/get/" in value:
        value = value.split("/inbox_item/get/", 1)[1].split("/")[0]
    return value if value.startswith("inbox_") else "inbox_" + value


def write_eml(report: dict, directory: Path, fetcher: "Fetcher", log) -> Path | None:
    """Saves the notice's original message as a .eml.

    Prefers the admin's own download_raw endpoint, which returns the stored bytes untouched --
    that matters for attachments and for any charset other than the UTF-8 the HTML page is served
    in. Falls back to the scraped Raw Content block, which is equivalent for a plain ASCII notice
    but is a re-encoding, not the original bytes.
    """
    directory.mkdir(parents=True, exist_ok=True)
    inbox_id = report["inboxId"]
    url = fetcher.admin_url + f"inbox_item/get/{inbox_id}/download_raw/"

    try:
        body, headers = fetcher.get_bytes(url)
        name = None
        disposition = headers.get("Content-Disposition", "")
        match = re.search(r'filename="?([^";]+)', disposition)
        if match:
            name = Path(match.group(1)).name          # never let the server pick a path
        path = directory / (name or f"{inbox_id}.eml")
        path.write_bytes(body)
        log(f"wrote {path} ({path.stat().st_size} bytes, original bytes)")
        return path
    except SystemExit as error:
        log(f"download_raw unavailable ({error}); falling back to the scraped raw content")

    raw = report["rawEmail"]
    if not raw:
        log(f"{inbox_id} has no raw content to save")
        return None
    # Mail expects CRLF; the HTML page carries bare newlines.
    text = raw.replace("\r\n", "\n").replace("\r", "\n").replace("\n", "\r\n")
    path = directory / f"{inbox_id}.eml"
    path.write_bytes((text if text.endswith("\r\n") else text + "\r\n").encode("utf-8"))
    log(f"wrote {path} ({path.stat().st_size} bytes, reconstructed)")
    return path


def dump_raw(directory: Path, pages: dict[str, str], log) -> None:
    directory.mkdir(parents=True, exist_ok=True)
    for index, (url, html) in enumerate(pages.items()):
        slug = re.sub(r"[^A-Za-z0-9._-]", "_", re.sub(r"^https?://", "", url))
        # Keep the tail, where the ids differ, but never drop the counter or long job URLs collide.
        (directory / f"{index:03d}-{slug[-110:]}.html").write_text(html, encoding="utf-8")
    log(f"dumped {len(pages)} raw pages to {directory}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="inbox_lookup",
        description="Pull an ECFX inbox item's status, processing errors, stack traces and email "
                    "off the admin site.")
    parser.add_argument("inbox_ids", nargs="*", metavar="INBOX_ID",
                        help="inbox id, bare id, or a pasted admin URL")
    parser.add_argument("--show-config", action="store_true",
                        help="print where credentials are looked for and what resolved, then exit")
    parser.add_argument("--init-config", action="store_true",
                        help="create an empty credential file in this OS's config location, then exit")
    parser.add_argument("--json", action="store_true", help="emit JSON instead of the text report")
    parser.add_argument("--out", type=Path, help="write output to a file instead of stdout")
    parser.add_argument("--raw", type=Path, metavar="DIR", help="also dump the raw HTML fetched")
    parser.add_argument("--eml", type=Path, metavar="DIR", nargs="?", const=Path.home() / "Downloads",
                        help="save each notice's raw MIME as <inboxId>.eml (default ~/Downloads)")
    parser.add_argument("--no-email", action="store_true", help="skip the rendered email fetch")
    parser.add_argument("--trace-only", action="store_true", help="print only the failing jobs")
    parser.add_argument("--max-job-pages", type=int, default=DEFAULT_MAX_JOB_PAGES, metavar="N",
                        help=f"job pages to open per table (default {DEFAULT_MAX_JOB_PAGES})")
    parser.add_argument("--all-jobs", action="store_true", help="open every attempt's page")
    parser.add_argument("--relogin", action="store_true", help="force a fresh login")
    parser.add_argument("--cookie", help="use this session cookie instead of the cached one")
    parser.add_argument("--quiet", action="store_true", help="suppress progress messages")
    args = parser.parse_args(argv)

    if args.init_config:
        init_config()
        return 0
    if args.show_config:
        show_config()
        return 0
    if not args.inbox_ids:
        parser.error("give at least one inbox id (or use --show-config / --init-config)")

    config = load_config()
    session = Session(config, explicit_cookie=args.cookie or os.environ.get("ECFX_SESSION_COOKIE"),
                      quiet=args.quiet)
    if args.relogin:
        session._explicit = False
        session.refresh()

    fetcher = Fetcher(session, keep_raw=args.raw is not None)
    max_job_pages = -1 if args.all_jobs else args.max_job_pages

    reports = [fetch_notice(normalize_inbox_id(raw), fetcher, not args.no_email, max_job_pages)
               for raw in args.inbox_ids]

    if args.raw:
        dump_raw(args.raw, fetcher.pages, session.log)

    if args.eml:
        for report in reports:
            write_eml(report, args.eml, fetcher, session.log)

    if args.json:
        output = json.dumps(reports[0] if len(reports) == 1 else reports, indent=2)
    elif args.trace_only:
        output = "".join(render_traces(report) for report in reports)
    else:
        output = "".join(render_full(report) for report in reports)

    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(output, encoding="utf-8")
        session.log(f"wrote {args.out}")
    else:
        print(output)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except NotAuthenticated as error:
        # Only reaches here when a cookie was supplied explicitly, so there is nothing to refresh.
        sys.exit(f"Session cookie rejected ({error}).\n"
                 f"Drop --cookie/$ECFX_SESSION_COOKIE to let the skill log in for you.")
    except KeyboardInterrupt:
        sys.exit(130)
