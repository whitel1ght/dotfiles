#!/usr/bin/env python3
"""Step 0 of a notice-QA run: verify everything the run needs BEFORE touching Jira, prod or dev.

    preflight.py [--local-emls]

Credentials are checked by the shared claude-components validator (lib/ecfx_credentials.py), the
same code `credentials/sync.sh --check` runs, so the two can never disagree. People put the files
there themselves — docs/CREDENTIALS.md:

    ~/.config/ecfx/jira.env    required   your own Jira API token
    ~/.config/ecfx/ecfx.env    required   1Password Document "ecfx.env" (prod admin login, to download notices)
                                          — optional with --local-emls (every notice already on disk)
    ~/.config/ecfx/duplo.env   optional   1Password Document "duplo.env"; without it, your duplo-jit login

Exit 0 ready · 3 needs a human (the output says exactly what to fix). Never prints a secret.
"""
import argparse
import shutil
import socket
import subprocess
import sys

import qa_common as qc


def smtp_port():
    for port in (587, 2525):
        try:
            with socket.create_connection(("inbound.postmarkapp.com", port), timeout=6):
                return port
        except OSError:
            continue
    return None


def kube_dev01():
    try:
        r = subprocess.run(["kubectl", "config", "get-contexts", "-o", "name"], capture_output=True, text=True, timeout=20)
        return "dev01" in r.stdout.split()
    except (OSError, subprocess.TimeoutExpired):
        return False


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--local-emls", action="store_true",
                    help="every notice is already on disk, so the prod admin login (ecfx.env) is optional")
    a = ap.parse_args()

    required = ("jira.env",) if a.local_emls else ("jira.env", "ecfx.env")
    optional = ("ecfx.env", "duplo.env") if a.local_emls else ("duplo.env",)
    ok, lines = qc.creds.check(required, optional)
    print("Credentials  (docs: claude-components/docs/CREDENTIALS.md)")
    print("\n".join("  " + l for l in lines))

    print("Tools")
    duplo = qc.creds.load("duplo", ("DUPLO_HOST", "DUPLO_TOKEN"))
    if not duplo.get("DUPLO_TOKEN") and not shutil.which("duplo-jit"):
        print('  ✗ dev Loki: no duplo.env and no duplo-jit — download the Document "duplo.env" '
              "from the shared 1Password vault, or install duplo-jit")
        ok = False
    else:
        # N9: make one real query — an expired token must stop us BEFORE prod notices are sent
        good, detail = qc.loki_ping()
        how = "shared DuploCloud token" if duplo.get("DUPLO_TOKEN") else "your duplo-jit login"
        if good:
            print(f"  ✓ dev Loki: {how}, query succeeded")
        else:
            print(f"  ✗ dev Loki: {how} could not query Loki ({detail}) — refresh duplo.env or re-run duplo-jit")
            ok = False

    port = smtp_port()
    if port:
        print(f"  ✓ SMTP to Postmark inbound MX: port {port} open")
    else:
        print("  ✗ SMTP to Postmark inbound MX: ports 587 and 2525 blocked on this network — "
              "try another network (the webhook fallback is not built yet)")
        ok = False

    if kube_dev01():
        print("  ✓ kubectl context dev01 (for the 'is the fix deployed' check)")
    else:
        print("  ! kubectl context dev01 missing — the report cannot prove the fix is in the dev image")

    print("Reminder (not checkable from here)")
    print("  · the target firm must accept notice-qa@dev.ecfxmail.com as a sender, or dev ignores the bundle")
    print(f"\n{'READY' if ok else 'NOT READY — fix the ✗ lines above'}")
    return 0 if ok else 3


if __name__ == "__main__":
    sys.exit(main())
