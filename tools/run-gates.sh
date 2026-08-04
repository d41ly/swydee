#!/usr/bin/env bash
# run-gates.sh — the coding-governance merge bar: run every gate this repo dogfoods, report per leg.
# The full bar green at the push boundary; earlier runs scoped. Exit 0 = all passed · 1 = one or more failed · 2 = must run from the repo.
#   bash tools/run-gates.sh
# Legs live in tools/gate-legs.json (single source); this runner is a thin iterator over it.
set -u
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "run-gates: not a git repo"; exit 2; }
cd "$ROOT" || exit 2
PYBIN=python3; command -v python3 >/dev/null 2>&1 || PYBIN=python
command -v "$PYBIN" >/dev/null 2>&1 || { echo "run-gates: python ($PYBIN) not found — required to parse tools/gate-legs.json"; exit 2; }
fails=0; n=0; skips=0

# Baseline for conditional legs: the mainline tip we gate against. Override with GATE_BASE.
# Unresolvable (no remote / shallow / detached) → empty, and changed() fails safe to "run".
DEFBR=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null); DEFBR=${DEFBR#origin/}
BASE=$(git rev-parse --verify -q "${GATE_BASE:-origin/${DEFBR:-main}}" 2>/dev/null) || BASE=
changed() { [ -z "$BASE" ] && return 0; ! git diff --quiet "$BASE" -- "$@" 2>/dev/null; }

leg() { # name · command...
  local name=$1; shift; n=$((n+1))
  local out; out=$("$@" </dev/null 2>&1); local rc=$?   # legs never read stdin — deny it so a stray reader can't hang the bar
  if [ "$rc" = 0 ]; then printf 'GATE ok    %s\n' "$name"
  else fails=$((fails+1)); printf 'GATE FAIL  %s (exit %d)\n' "$name" "$rc"; printf '%s\n' "$out" | sed 's/^/    /'
       FAILED_LEGS="${FAILED_LEGS:-}GATE FAIL  $name (exit $rc)"$'\n'; fi   # TOOL-aLeasedGauntlet-1 S3: keep for the durable summary
}

leg_if_changed() { # guard-path[,guard-path...] · name · command...  (leg() counts n on run; skip counts here)
  local guard=$1 name=$2; shift 2
  local paths; IFS=, read -ra paths <<<"$guard"
  if changed "${paths[@]}"; then leg "$name" "$@"
  else n=$((n+1)); skips=$((skips+1)); printf 'GATE skip  %s (unchanged vs %s)\n' "$name" "${DEFBR:-baseline}"; fi
}

# Read the leg manifest as name<RS>guard(comma-joined)<RS>argv(joined by <US>) per line, where
# RS=\x1e and US=\x1f (non-whitespace, so an empty guard field survives `read`; a tab would collapse).
# Command-substitution surfaces a parse failure (a `< <()` process-sub would swallow it).
legs=$("$PYBIN" -c '
import json, sys
try:
    data = json.load(open("tools/gate-legs.json"))
except Exception as e:
    sys.stderr.write("parse error: %s\n" % e); sys.exit(3)
if not isinstance(data, list) or not data:
    sys.stderr.write("gate-legs.json empty or not a list\n"); sys.exit(3)
rows = [l["name"] + "\x1e" + ",".join(l.get("guard", [])) + "\x1e" + "\x1f".join(l["argv"]) for l in data]
sys.stdout.buffer.write(("\n".join(rows) + "\n").encode())   # LF bytes (Windows text stdout is CRLF); \x1e field sep is non-whitespace so an empty guard field is preserved (a tab would collapse)
') || { echo "run-gates: cannot parse tools/gate-legs.json"; exit 2; }

while IFS=$'\x1e' read -r name guard argvraw; do
  [ -z "$name" ] && continue
  IFS=$'\x1f' read -ra argv <<<"$argvraw"
  case "${argv[0]}" in python|python3) argv[0]=$PYBIN ;; esac   # the manifest stores the canonical python3; run under the resolved PYBIN
  if [ -n "$guard" ]; then leg_if_changed "$guard" "$name" "${argv[@]}"
  else leg "$name" "${argv[@]}"; fi
done <<<"$legs"

echo "----"
skipnote=""; [ "$skips" -gt 0 ] && skipnote=" ($skips skipped)"
# TOOL-aLeasedGauntlet-1 S3: write the verdict + failing-leg rows to a durable file (worktree-safe
# gitdir) so a `| tail`/`Select-Object -Last N` can't discard which leg failed.
gd="$(git rev-parse --git-dir 2>/dev/null)"; sfile=""; [ -n "$gd" ] && sfile="$gd/gate-last-summary.txt"
if [ "$fails" = 0 ]; then
  [ -n "$sfile" ] && printf 'gates GREEN — %s/%s legs passed%s\n' "$((n-skips))" "$((n-skips))" "$skipnote" >"$sfile" 2>/dev/null || true
  echo "gates GREEN — $((n-skips))/$((n-skips)) legs passed$skipnote"; exit 0
else
  [ -n "$sfile" ] && { printf '%s' "${FAILED_LEGS:-}" >"$sfile"; printf 'gates RED — %s/%s legs failed%s\n' "$fails" "$n" "$skipnote" >>"$sfile"; } 2>/dev/null || true
  echo "gates RED — $fails/$n legs failed$skipnote"
  [ -n "$sfile" ] && echo "gate summary saved to $sfile"
  exit 1
fi
