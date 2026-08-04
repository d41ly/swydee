#!/usr/bin/env bash
# run-gates.test.sh — canary: gate-legs.json is well-formed AND run-gates.sh sources every leg from it
# (no inlined leg command). Exit 0 = clean. Runs as a leg of run-gates.sh itself.
set -u
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "canary: not a git repo"; exit 2; }
cd "$ROOT" || exit 2
PYBIN=python3; command -v python3 >/dev/null 2>&1 || PYBIN=python
command -v "$PYBIN" >/dev/null 2>&1 || { echo "canary: python ($PYBIN) not found"; exit 2; }
fail=0

# 1. manifest well-formed: non-empty list; every leg has a non-empty name, an argv with a launcher
#    AND a script (len >= 2), and argv[0] in the allowed set. An empty name is the runner's
#    drop-sentinel (run-gates.sh skips it), and a launcher-only argv runs `bash </dev/null` = a silent
#    no-op GATE ok — both are green-by-absence shapes this canary exists to forbid.
"$PYBIN" -c '
import json, sys
try:
    legs = json.load(open("tools/gate-legs.json"))
except Exception as e:
    print("canary: gate-legs.json does not parse: %s" % e); sys.exit(1)
if not isinstance(legs, list) or not legs:
    print("canary: gate-legs.json is empty or not a list"); sys.exit(1)
ok = {"bash", "python", "python3"}
bad = [l.get("name", "?") for l in legs
       if not str(l.get("name", "")).strip() or not l.get("argv") or len(l["argv"]) < 2 or l["argv"][0] not in ok]
if bad:
    print("canary: malformed leg(s) (empty name, argv len < 2, or argv[0] not in {bash,python,python3}): " + ", ".join(bad)); sys.exit(1)
' || fail=1

# 2. no leg SCRIPT-PATH arg (argv[1..] that looks like a path) is hardcoded in run-gates.sh —
#    launcher tokens (bash/python/python3) and flags are excluded; the parse path is the manifest
#    filename, not a leg path, so it never matches.
paths=$("$PYBIN" -c '
import json, sys
rows = [a for l in json.load(open("tools/gate-legs.json")) for a in l["argv"][1:] if "/" in a or a.endswith(".sh") or a.endswith(".py")]
sys.stdout.buffer.write(("\n".join(rows) + ("\n" if rows else "")).encode())   # LF bytes (Windows text stdout is CRLF)
')
while IFS= read -r p; do
  [ -z "$p" ] && continue
  if grep -qF -- "$p" tools/run-gates.sh; then
    echo "canary: leg script path '$p' is hardcoded in run-gates.sh — source it from gate-legs.json"; fail=1
  fi
done <<<"$paths"

[ "$fail" = 0 ] && exit 0 || exit 1
