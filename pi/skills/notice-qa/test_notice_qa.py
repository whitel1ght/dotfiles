#!/usr/bin/env python3
"""Guards for notice-qa's verdict-setting logic.

Run directly — `python3 skills/notice-qa/test_notice_qa.py`. No pytest (stdlib only, like
lib/test_jira_metrics.py). Nothing here touches the network, Jira, Loki, SMTP or dev: every check
runs against temp directories and in-memory messages.

Each block pins one review finding on !52 whose failure mode is a WRONG VERDICT or an unsafe send,
because those are the ones a green suite must not be able to hide.
"""
import datetime
import email
import email.policy
import json
import os
import pathlib
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
os.environ.setdefault("HOME", tempfile.mkdtemp())

import qa_common as qc  # noqa: E402

FAILURES = []


def check(name, condition, detail=""):
    if condition:
        print(f"  ok   {name}")
    else:
        print(f"  FAIL {name} {detail}")
        FAILURES.append(name)


def utc(s):
    return datetime.datetime.fromisoformat(s).replace(tzinfo=datetime.timezone.utc)


def with_qa_home(fn):
    """Run fn with qc.QA_HOME pointed at a fresh temp dir."""
    old = qc.QA_HOME
    qc.QA_HOME = pathlib.Path(tempfile.mkdtemp())
    try:
        return fn(qc.QA_HOME)
    finally:
        qc.QA_HOME = old


def write_run(runs, run, batch, sent, children=(), parent=None, matched=True):
    runs.mkdir(parents=True, exist_ok=True)
    (runs / f"{run}.json").write_text(json.dumps({"run": run, "batch": batch, "sentAt": sent, "ticket": "ECFX-1",
                                                  "firm": "testfirm1", "notices": []}))
    (runs / f"{run}.result.json").write_text(json.dumps({"run": run, "matched": matched, "children": [{"id": c} for c in children],
                                                         "parent": {"id": parent} if parent else None}))


# ── B1: a duplicate of an EARLIER batch is not a pass ────────────────────────
print("B1 — same-ticket dedup is scoped to the batch")
import trace_run as tr  # noqa: E402


def b1(home):
    runs = home / "ECFX-1" / "runs"
    write_run(runs, "first-p1", "first", "2026-09-28T10:00:00+00:00", children=["inbox_old_child"])
    write_run(runs, "second-p1", "second", "2026-09-28T12:00:00+00:00", children=["inbox_sibling"])
    manifest = {"run": "second-p1", "batch": "second"}
    same = tr.same_batch_children({"children": [{"id": "inbox_new_child"}]}, manifest, runs)
    check("children of the earlier batch are not 'same batch'", "inbox_old_child" not in same, str(same))
    check("siblings in this batch are", {"inbox_sibling", "inbox_new_child"} <= same, str(same))
    check("original from an earlier QA pass → previouslyProcessed (NOT TESTED, requeue)",
          tr.classify_duplicate({"inbox_old_child"}, same) == "previouslyProcessed")
    check("original from this batch → sameTicket (valid dedup test)",
          tr.classify_duplicate({"inbox_sibling"}, same) == "sameTicket")
    check("no original found → unresolved", tr.classify_duplicate(set(), same) == "unresolved")


with_qa_home(b1)

# ── M7: parents are matched to their own chunk, never guessed ────────────────
print("M7 — parent attribution")


def m7(home):
    runs = home / "ECFX-1" / "runs"
    write_run(runs, "b-p1", "b", "2026-09-28T16:07:33+00:00")
    write_run(runs, "b-p2", "b", "2026-09-28T16:07:54+00:00")
    write_run(runs, "other-p1", "other", "2026-09-28T15:00:00+00:00", parent="inbox_claimed")
    p1 = json.loads((runs / "b-p1.json").read_text())
    end = tr.chunk_window_end(p1)
    check("p1's window ends when p2 was sent", end == utc("2026-09-28T16:07:54"), str(end))
    sent = utc("2026-09-28T16:07:33")
    parents = [("inbox_p1_parent", utc("2026-09-28T16:07:35")),     # p1's own, 2 s after send
               ("inbox_p2_parent", utc("2026-09-28T16:07:57")),     # arrived after p2 was sent
               ("inbox_claimed", utc("2026-09-28T16:07:40"))]       # already another run's parent
    got = tr.select_candidates(parents, sent, end, tr.claimed_parents(p1))
    check("only p1's own parent is a candidate", got == ["inbox_p1_parent"], str(got))
    # the held-chunk case: p1's email never arrived, p2's did
    held = tr.select_candidates([("inbox_p2_parent", utc("2026-09-28T16:07:57"))], sent, end, set())
    check("a held p1 does not adopt p2's parent", held == [], str(held))


with_qa_home(m7)

# ── M1: the only possible recipient is <bare subdomain>@dev.ecfxmail.com ────
print("M1 — recipient is always a dev firm inbox")
import send_bundle as sb  # noqa: E402

check("a bare subdomain is accepted", sb.dev_address("testfirm1") == "testfirm1@dev.ecfxmail.com")
for bad in ("x@ecfxmail.com>", "victim@gmail.com", "testfirm1@dev.ecfxmail.com", "Testfirm1", "a b", "", "-x", "x\r\nRCPT"):
    try:
        sb.dev_address(bad)
        check(f"--firm {bad!r} is refused", False, "accepted")
    except ValueError:
        check(f"--firm {bad!r} is refused", True)
try:
    sb.deliver(b"x", "someone@gmail.com", smtp_factory=lambda *a, **k: (_ for _ in ()).throw(AssertionError("connected")))
    check("deliver() refuses a non-dev address even if called directly", False, "no error")
except AssertionError as e:
    check("deliver() refuses a non-dev address even if called directly", "refusing" in str(e), str(e))

# ── M4: attached notices go out byte-for-byte (no re-folding / re-encoding) ─
print("M4 — attached notices are not re-folded")
RAW = (b"From: Clerk <efile@court.example>\r\n"
       b"Subject: =?utf-8?q?Order_=E2=80=94_Smith?=\r\n =?utf-8?b?4oCZcyBtb3Rpb24=?=\r\n"
       b"X-Long: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\r\n"
       b"  bbbbbbbbbbbbbb\r\n"
       b"Message-ID: <m1@court.example>\r\n"
       b"MIME-Version: 1.0\r\n"
       b"Content-Type: text/plain; charset=utf-8\r\n"
       b"Content-Transfer-Encoding: 8bit\r\n\r\n"
       b"Caf\xc3\xa9 \xe2\x80\x94 see https://court.example/doc?id=1\r\n")
notice = email.message_from_bytes(RAW, policy=email.policy.compat32)
wire, to = sb.build_bundle("t-run", "testfirm1", [("n.eml", notice)])
check("the attached notice appears verbatim in the sent bytes", RAW.rstrip(b"\r\n") in wire)
check("the wrapper goes to the dev address", b"To: testfirm1@dev.ecfxmail.com" in wire)


# ── M8: fall back to 2525 only before DATA; never send twice ────────────────
print("M8 — no second send after DATA started")


class FakeSMTP:
    log = []

    def __init__(self, host, port, timeout=None, fail=None):
        self.port, self.fail = port, fail
        FakeSMTP.log.append(("connect", port))
        if fail == ("connect", port):
            raise OSError("refused")

    def ehlo(self, *_):
        return 250, b"ok"

    def starttls(self, **_):
        return 220, b"ok"

    def mail(self, _):
        return 250, b"ok"

    def rcpt(self, _):
        return 250, b"ok"

    def data(self, _):
        FakeSMTP.log.append(("data", self.port))
        if self.fail == ("data", self.port):
            raise sb.smtplib.SMTPServerDisconnected("connection dropped after DATA")
        return 250, b"queued"

    def quit(self):
        pass


def factory(fail):
    return lambda host, port, timeout=None: FakeSMTP(host, port, timeout, fail)


FakeSMTP.log = []
try:
    sb.deliver(b"msg", "testfirm1@dev.ecfxmail.com", smtp_factory=factory(("data", 587)))
    check("a drop after DATA on 587 raises DeliveryUnknown", False, "returned normally")
except sb.DeliveryUnknown:
    check("a drop after DATA on 587 raises DeliveryUnknown", True)
check("…and 2525 is never tried (no second copy)", ("connect", 2525) not in FakeSMTP.log, str(FakeSMTP.log))
FakeSMTP.log = []
port = sb.deliver(b"msg", "testfirm1@dev.ecfxmail.com", smtp_factory=factory(("connect", 587)))
check("a connect failure on 587 falls back to 2525", port == 2525 and ("data", 2525) in FakeSMTP.log, str(FakeSMTP.log))


def m8_resume(home):
    runs = home / "ECFX-1" / "runs"
    runs.mkdir(parents=True)
    (runs / "old.json").write_text(json.dumps({"run": "old", "notices": [{"file": "inbox_item_inbox_a.eml"}]}))
    (runs / "old.result.json").write_text("{}")
    check("notices sent in an earlier run are recognised", sb.already_sent(runs) == {"inbox_item_inbox_a.eml": "old"})


with_qa_home(m8_resume)

# ── M9: real notices never land outside the private cache ───────────────────
print("M3 — make_variant changes only the edited text")
import make_variant as mv  # noqa: E402

EIGHTBIT = (b"From: a@court.example\r\nSubject: s\r\nMIME-Version: 1.0\r\n"
            b"Content-Type: text/plain; charset=utf-8\r\nContent-Transfer-Encoding: 8bit\r\n\r\n"
            b"Caf\xc3\xa9 \xe2\x80\x94 http://court.example/doc?nai=ABC\r\n")
try:
    msg, n = mv.edit_message(EIGHTBIT, [("nai=ABC", "nai=XYZ")])
    out = mv.flatten(msg)
    check("8bit UTF-8 part: no crash, edit applied", n["nai=ABC"] == 1 and b"nai=XYZ" in out)
    check("8bit UTF-8 part: the untouched bytes survive exactly", b"Caf\xc3\xa9 \xe2\x80\x94 http://court.example/doc?" in out)
except Exception as e:  # noqa: BLE001
    check("8bit UTF-8 part: no crash, edit applied", False, f"{type(e).__name__}: {e}")

MISLABELLED = (b"From: a@court.example\r\nSubject: s\r\nMIME-Version: 1.0\r\n"
               b"Content-Type: text/html; charset=us-ascii\r\nContent-Transfer-Encoding: quoted-printable\r\n\r\n"
               b"Smith=E2=80=99s motion =E2=80=94 see <a href=3D\"https://c.example/d?nai=3DABC\">doc</a>\r\n")
msg, n = mv.edit_message(MISLABELLED, [("nai=ABC", "nai=XYZ")])
body = next(p for p in msg.walk() if p.get_content_type() == "text/html").get_payload(decode=True)
check("mislabelled us-ascii QP: edit applied", n["nai=ABC"] == 1 and b"nai=XYZ" in body)
check("mislabelled us-ascii QP: the real UTF-8 punctuation survives (no ???)",
      "Smith’s motion — see".encode() in body and b"?" not in body.split(b"see")[0], body[:60])
try:
    mv.edit_message(MISLABELLED.replace(b"us-ascii", b"x-no-such-charset"), [("nai", "n")])
    check("an unknown charset stops with a clear error", False, "no error")
except SystemExit as e:
    check("an unknown charset stops with a clear error", "unknown charset" in str(e), str(e))

print("M2 — when check() says OK, every reader can actually read the files")
import subprocess  # noqa: E402

LIB = HERE.parents[1] / "lib"
INBOX = HERE.parent / "inbox-lookup"
AGREE = f"""
import sys; sys.path[:0] = [{str(LIB)!r}, {str(INBOX)!r}]
import ecfx_credentials as c, jira_metrics as jm, inbox_lookup as il
ok = c.check(("ecfx.env", "jira.env"), ())[0]
host = jm.load_credentials()[0]
cfg = il.load_config()
same = [str(p) for p in c.candidates("ecfx.env")] == [str(p) for p in il.config_file_candidates()[:-1]]
print(ok, host, cfg.get("O365_USERNAME"), same)
"""


def agree_env(home):
    xdg = home / "xdg"
    (xdg / "ecfx").mkdir(parents=True, mode=0o700)
    (xdg / "ecfx" / "ecfx.env").write_text("ECFX_ADMIN_URL=https://a/\nO365_USERNAME=qa-user\nO365_PASSWORD=p\nO365_TOTP_SECRET=s\n")
    (xdg / "ecfx" / "jira.env").write_text('JIRA_HOST="example.atlassian.net"\nJIRA_USER=u\nJIRA_TOKEN=t\n')
    for f in (xdg / "ecfx").iterdir():
        os.chmod(f, 0o600)
    clean = {k: v for k, v in os.environ.items() if not k.startswith(("JIRA", "O365", "ECFX", "XDG"))}
    return {**clean, "HOME": str(home), "XDG_CONFIG_HOME": str(xdg)}


home = pathlib.Path(tempfile.mkdtemp())
r = subprocess.run([sys.executable, "-c", AGREE], capture_output=True, text=True, env=agree_env(home))
out = r.stdout.split()
check("with a non-default config location, check() passes", out[:1] == ["True"], r.stdout + r.stderr[-300:])
check("…and jira_metrics finds jira.env there", out[1:2] == ["example.atlassian.net"], r.stdout + r.stderr[-300:])
check("…and inbox-lookup finds ecfx.env there", out[2:3] == ["qa-user"], r.stdout + r.stderr[-300:])
check("ecfx.env search order is identical to inbox-lookup's", out[3:4] == ["True"], r.stdout)
export_line = pathlib.Path(tempfile.mkdtemp()) / "x.env"
export_line.write_text("export JIRA_TOKEN=t\n")
sys.path.insert(0, str(LIB))
import ecfx_credentials as ec  # noqa: E402
check("an `export KEY=` line is not accepted (no other reader accepts it)", "JIRA_TOKEN" not in ec.parse_env_file(export_line))

print("Q1/Q2/N1 — reading the ticket")
import ecfx_tickets as et  # noqa: E402
import fetch_ticket as ft  # noqa: E402


def adf(t):
    return {"type": "doc", "content": [{"type": "paragraph", "content": [{"type": "text", "text": t}]}]}


class FakeJira:
    """150 comments; the issue embeds only the first 50 (Jira's page size), like a long ticket."""
    def __init__(self):
        self.comments = [{"id": str(i), "created": "2026-09-28T00:00:00.000+0000",
                          "author": {"displayName": "Bot", "accountType": "atlassian"},
                          "body": adf(f"inbox_{'a' * 20}{i:06d} - ECF")} for i in range(150)]
        self.comments[149]["author"] = {"displayName": "Outside Person", "accountType": "customer"}
        self.comments[149]["body"] = adf("please test inbox_zzzzzzzzzzzzzzzzzzzzzzzzzz")

    def get_issue(self, key, fields=None):
        return {"key": key, "fields": {"summary": "s", "status": {"name": "In QA"}, "description": adf("d"),
                                       "reporter": {"displayName": "Dev", "accountType": "atlassian"},
                                       "comment": {"comments": self.comments[:50], "total": 150, "maxResults": 50}}}

    def get(self, path):
        start = int(re.search(r"startAt=(\d+)", path).group(1))
        return {"comments": self.comments[start:start + 100], "total": 150}


import re  # noqa: E402

_, texts = et.read_ticket(FakeJira(), "ECFX-1")
check("Q1: all 150 comments are read, not just the 50 embedded", sum(t["where"] == "comment" for t in texts) == 150,
      str(sum(t["where"] == "comment" for t in texts)))
items = {i["id"]: i for i in ft.collect(texts)}
check("Q1: an id only in comment #149 is collected", "inbox_zzzzzzzzzzzzzzzzzzzzzzzzzz" in items)
check("Q2: an id only a portal customer mentioned is flagged externalOnly",
      items.get("inbox_zzzzzzzzzzzzzzzzzzzzzzzzzz", {}).get("externalOnly") is True)
check("Q2: ids staff mentioned are not", items[f"inbox_{'a' * 20}000001"]["externalOnly"] is False)
check("Q2: each id records who mentioned it", items["inbox_zzzzzzzzzzzzzzzzzzzzzzzzzz"]["sourceAuthors"][0]["author"] == "Outside Person")
lookup = et.find_inbox_lookup()
check("N1: inbox-lookup is found repo-relative first", lookup == HERE.parent / "inbox-lookup" / "inbox_lookup.py", str(lookup))

print("M9 — purge removes client data, keeps only the report, never leaves the cache")
import purge as pg  # noqa: E402


def m9_purge(home):
    d = qc.ticket_dir("ECFX-9")
    for rel in ("emls/inbox_item_inbox_x.eml", "runs/r.json", "runs/r-bundle.eml", "ticket.json",
                "report-summary.json", "verdicts.json", "notice-qa-report-ECFX-9-2026-09-28-1200Z.md"):
        (d / rel).write_text("x")
    pg.purge("ECFX-9", keep_report=True)
    left = sorted(p.name for p in d.iterdir())
    check("--keep-report leaves only the report, summary and verdicts",
          left == ["notice-qa-report-ECFX-9-2026-09-28-1200Z.md", "report-summary.json", "verdicts.json"], str(left))
    pg.purge("ECFX-9")
    check("a full purge removes the ticket folder", not d.exists())
    for bad in ("../x", "ECFX-9/../../etc", "", "notakey"):
        try:
            pg.purge(bad)
            check(f"purge({bad!r}) is refused", False)
        except SystemExit:
            check(f"purge({bad!r}) is refused", True)


with_qa_home(m9_purge)

print("N9 — a Loki failure is never reported as OK")
real_get, real_token = qc.nl.loki_get, qc._token
qc._token = "expired"
qc.nl.loki_get = lambda *a, **k: (_ for _ in ()).throw(ValueError("401 Unauthorized"))
try:
    good, detail = qc.loki_ping()
    check("loki_ping() is False when the query fails", good is False and "401" in detail, detail)
finally:
    qc.nl.loki_get, qc._token = real_get, real_token

print("M5 — unknowns never become confident claims")
import report as rp  # noqa: E402

check("fix check: all yes → yes", rp.combine_deployed([True, True]) is True)
check("fix check: one unknown → unverified, not NO", rp.combine_deployed([True, None]) is None)
check("fix check: a known no wins", rp.combine_deployed([None, False]) is False)
check("fix check: no images → unverified", rp.combine_deployed([]) is None)
bad = {"Undefined Exception": {"kind": "forbid", "count": 1, "ok": False}}
check("a failed forbid-log turns PASS into FAIL", rp.apply_log_checks("PASS", "n", bad, None)[0] == "FAIL")
check("…unless an explicit logCheckOverride reason is given",
      rp.apply_log_checks("PASS", "n", bad, "line belongs to the CaseNotFound attempt")[0] == "PASS")
check("passing log checks leave the verdict alone",
      rp.apply_log_checks("PASS", "n", {"x": {"kind": "expect", "count": 1, "ok": True}}, None)[0] == "PASS")


def mf(run, files, sent="2026-09-28T10:00:00+00:00"):
    return {"run": run, "sentAt": sent, "notices": [{"file": f, "sourceInboxId": f.split(".")[0]} for f in files]}


held = (mf("b-p1", ["a.eml", "b.eml"]), {"run": "b-p1", "firm": "t", "parent": None, "children": []})
ok = (mf("b-p2", ["c.eml"]), {"run": "b-p2", "firm": "t", "parent": {"id": "P"}, "children": [{"id": "C", "file": "c.eml"}]})
rows = rp.missing_rows([held, ok])
check("an undelivered run's notices each get a NOT TESTED row",
      sorted(r["child"]["file"] for r in rows) == ["a.eml", "b.eml"] and {r["verdict"] for r in rows} == {"NOT TESTED"}, str(rows))
resent = (mf("c-p1", ["a.eml", "b.eml"]), {"run": "c-p1", "firm": "t", "parent": {"id": "Q"},
                                           "children": [{"id": "X", "file": "a.eml"}, {"id": "Y", "file": "b.eml"}]})
check("…but not when they were re-sent and matched in another included run", rp.missing_rows([held, resent]) == [])

print("M6 — Loki results are paged, never silently truncated")
LINES = [(1_000_000_000 + i, f"2026-09-28 10:00:0{i}.000 [t] INFO x - line {i}") for i in range(7)]


def fake_loki_get(base, token, path, params, attempts=4):
    start, lim = int(params["start"]), int(params["limit"])
    page = [(ts, l) for ts, l in LINES if ts >= start][:lim]
    return {"data": {"result": [{"stream": {}, "values": [[str(ts), l] for ts, l in page]}]}}


real_get, real_limit, real_token = qc.nl.loki_get, qc.nl.PAGE_LIMIT, qc._token
qc.nl.loki_get, qc.nl.PAGE_LIMIT, qc._token = fake_loki_get, 3, "test-token"
try:
    got = qc.loki_query("{x}", datetime.datetime.fromtimestamp(0, datetime.timezone.utc),
                        datetime.datetime.fromtimestamp(10, datetime.timezone.utc))
    check("all 7 lines come back across 3 pages of 3", len(got) == 7, f"got {len(got)}")
    check("…in order, newest last (a child's final attempt is not dropped)", got[-1].endswith("line 6"), got[-1:])
finally:
    qc.nl.loki_get, qc.nl.PAGE_LIMIT, qc._token = real_get, real_limit, real_token

print("M8 — the Jira comment id survives re-rendering")
prev = {"batches": ["b1"], "posted": {"commentId": "123", "report": "r1.md"}}
check("same batches → keep the comment id (update in place)", (rp.carry_posted(prev, ["b1"]) or {}).get("commentId") == "123")
check("different batches → new QA pass, new comment", rp.carry_posted(prev, ["b2"]) is None)
check("nothing posted yet → nothing carried", rp.carry_posted({}, ["b1"]) is None)

print("M9 — client data stays in ~/.cache/notice-qa, private")


def no_network(*_a, **_k):
    raise RuntimeError("TEST BUG: deliver() reached — a test must never send")


def run_main(argv):
    """send_bundle.main() in-process with delivery stubbed out: even a broken guard cannot send."""
    real_deliver, real_argv = sb.deliver, sys.argv
    sb.deliver, sys.argv = no_network, ["send_bundle.py"] + argv
    try:
        return sb.main()
    except SystemExit as e:
        return e.code
    except RuntimeError as e:
        return str(e)
    finally:
        sb.deliver, sys.argv = real_deliver, real_argv


def m9_out(home):
    tmp = pathlib.Path(tempfile.mkdtemp())
    eml = tmp / "inbox_item_inbox_x.eml"
    eml.write_bytes(RAW)
    code = run_main(["--firm", "testfirm1", "--out", str(tmp / "repo"), str(eml)])
    check("--out outside the cache is refused for real notices, before any send", code == 2, repr(code))


with_qa_home(m9_out)


def m9_perms(home):
    loose = home / "ECFX-3" / "emls"
    loose.mkdir(parents=True)
    os.chmod(home, 0o755); os.chmod(home / "ECFX-3", 0o755); os.chmod(loose, 0o755)   # made before the rule
    qc.ticket_dir("ECFX-3")
    modes = {str(p.relative_to(home.parent)): oct(p.stat().st_mode & 0o777) for p in (home, home / "ECFX-3", loose)}
    check("pre-existing loose cache dirs are tightened to 0700", set(modes.values()) == {"0o700"}, str(modes))
    d = qc.ticket_dir("ECFX-2")
    check("new cache dirs are 0700", {oct(x.stat().st_mode & 0o777) for x in (d, d / "emls", d / "runs")} == {"0o700"})
    try:
        qc.ticket_dir("../../etc")
        check("a non-Jira-key ticket is refused", False)
    except ValueError:
        check("a non-Jira-key ticket is refused", True)


with_qa_home(m9_perms)

print()
if FAILURES:
    print(f"{len(FAILURES)} FAILED: {', '.join(FAILURES)}")
    sys.exit(1)
print("all passed")
