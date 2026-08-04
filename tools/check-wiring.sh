#!/usr/bin/env bash
# check-wiring.sh — detect coding-governance tools installed-but-unwired in THIS repo, and
# (with --fix/--session) wire the zero-risk ones. Spec: memory/tooling/builds/2026-07-15-TOOL-aWireWarden/.
#
#   check-wiring.sh            # --check (default): report; exit 1 if any installed tool is unwired
#   check-wiring.sh --fix      # wire the safe cases (core.hooksPath when unset); exit reflects remainder
#   check-wiring.sh --session  # like --fix but ALWAYS exit 0 — the SessionStart hook mode
#
# Wiring the git hooks opts into running this repo's committed hooks (a git trust boundary). Auto-fix
# sets core.hooksPath ONLY when unset and NEVER overwrites an already-set value (e.g. a deliberate
# out-of-tree copy per WIRE-INTO-PROJECT.md §5). Agent-cap wiring is never auto-applied — it would mean
# rewriting settings.json, the file the SessionStart hook lives in.
KIT_CHECK_WIRING_VERSION=1.0
set -u

MODE=check
case "${1:-}" in
  ""|--check) MODE=check ;;
  --fix)      MODE=fix ;;
  --session)  MODE=session ;;
  *) echo "usage: $(basename "$0") [--check|--fix|--session]" >&2; exit 2 ;;
esac

# Not a git repo → nothing to wire; never an error (and never break session start).
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "skip     — not a git repo"; exit 0; }
cd "$ROOT" || { [ "$MODE" = session ] && exit 0; exit 0; }

DO_FIX=0; case "$MODE" in fix|session) DO_FIX=1 ;; esac
unwired=0

# Absolute path of an existing directory ("" if it does not resolve).
abspath() { ( cd "$1" 2>/dev/null && pwd ); }

# First of the candidates that is a file ("" if none).
first_of() { for c in "$@"; do [ -f "$c" ] && { echo "$c"; return; }; done; }

# THE wired signal, for every arm: the hook's marker substring present in .claude/settings.json.
# settings-merge.py documents that same substring as the deployer's is-it-wired test (its module
# docstring), so this is the one predicate stated once — not a second spelling of it. Grepping it
# directly also removes the "settings-merge.py absent, cannot verify" skip, which was a false
# all-clear in every adopter (the tool is copied in per WIRE §3c step 4 / §5, so an arm that
# REQUIRED it to answer reported `skip … exit 0` on the state the runbook calls the one bad state).
wired() { [ -f .claude/settings.json ] && grep -qF "$1" .claude/settings.json; }

# The launcher named in a remedy string — printed, never run, so a python3-only host gets a
# copy-pasteable line (the python3-first resolution this file already used per-arm).
PY=python3; command -v python3 >/dev/null 2>&1 || PY=python

# --- Check H: git hooks (core.hooksPath) ---------------------------------------------------------
check_hooks() {
  if ! { [ -f .githooks/pre-commit ] && git ls-files --error-unmatch .githooks/pre-commit >/dev/null 2>&1; }; then
    echo "skip     hooks     — no tracked .githooks/pre-commit"
    return
  fi
  local cur curdir
  cur=$(git config core.hooksPath 2>/dev/null || true)
  if [ -n "$cur" ]; then
    curdir=$(abspath "$cur")
    if [ -n "$curdir" ] && [ -f "$curdir/pre-commit" ]; then
      echo "ok       hooks     — core.hooksPath -> $cur"
    else
      echo "UNWIRED  hooks     — core.hooksPath='$cur' resolves to no pre-commit; NOT overwriting (deliberate?). Fix: git config core.hooksPath .githooks"
      unwired=$((unwired+1))
    fi
    return
  fi
  # unset — the fresh-clone case
  if [ "$DO_FIX" = 1 ]; then
    git config core.hooksPath .githooks && echo "FIXED    hooks     — set core.hooksPath -> .githooks"
  else
    echo "UNWIRED  hooks     — core.hooksPath unset; .githooks gates (incl. branch guard) dormant. Fix: git config core.hooksPath .githooks"
    unwired=$((unwired+1))
  fi
}

# --- Check A: agent-cap PreToolUse hook in .claude/settings.json ----------------------------------
# Advisory: no mode mutates settings.json (the SessionStart hook must not rewrite its own file).
check_agentcap() {
  local smerge; smerge=$(first_of tools/settings-merge.py settings-merge.py)
  # Left as a plain skip on purpose: agent-cap's hook path is not declared anywhere this script can
  # read (settings-merge.py hardcodes it), so "settings wired, script missing" cannot be told from a
  # deliberate out-of-tree copy. The recall arm below CAN — its fragment declares `hook_path`.
  if [ ! -f .claude/hooks/agent-cap.js ]; then
    echo "skip     agent-cap — not adopted (.claude/hooks/agent-cap.js absent)"
    return
  fi
  if wired "agent-cap.js"; then
    echo "ok       agent-cap — PreToolUse hook wired in .claude/settings.json"
  else
    echo "UNWIRED  agent-cap — agent-cap.js present but hook not in settings.json. Fix: $PY ${smerge:-tools/settings-merge.py}"
    unwired=$((unwired+1))
  fi
}

# --- Check R: recall-opened PostToolUse hook (memory-recall kit — an OPT-IN) ----------------------
# FIVE states, not two. `adopt-memory-recall.sh` copies the hook only under `--with-hook`, so an
# absent hook file with nothing in settings.json is a TRUE signal ("opt-in not taken"), never
# UNWIRED. Mirroring the agent-cap arm literally would print a permanent false alarm in the repo
# that runs THIS script as its own SessionStart hook, which is the fastest way to train every node
# to ignore the wiring verifier. Both halves — the marker and the script path — are read from the
# fragment, so this arm asserts nothing the shipped kit does not itself declare.
# Advisory like every other arm: no mode rewrites settings.json.
json_str() {  # value of a top-level "key": "..." in a small flat JSON file
  sed -n 's|.*"'"$2"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*|\1|p' "$1" | head -1
}
check_recall_opened() {
  local frag smerge marker hookjs
  # Resolved by path because the kit is COPIED: <root>/memory-recall/ in an adopter,
  # <root>/tools/memory-recall/ in this repo.
  frag=$(first_of memory-recall/recall-opened.fragment.json tools/memory-recall/recall-opened.fragment.json)
  if [ -z "$frag" ]; then
    echo "skip     recall    — memory-recall kit not adopted (no recall-opened.fragment.json)"
    return
  fi
  smerge=$(first_of tools/settings-merge.py settings-merge.py)
  marker=$(json_str "$frag" marker)
  hookjs=$(json_str "$frag" hook_path)
  if [ -z "$marker" ] || [ -z "$hookjs" ]; then
    echo "UNWIRED  recall    — $frag declares no marker/hook_path; settings-merge.py refuses it too. Fix: restore the shipped fragment"
    unwired=$((unwired+1))
    return
  fi
  if [ ! -f "$hookjs" ]; then
    if wired "$marker"; then
      echo "UNWIRED  recall    — settings.json dispatches the hook but $hookjs is missing; every Read runs node against nothing. Fix: bash $(dirname "$frag")/adopt-memory-recall.sh --scaffold --with-hook"
      unwired=$((unwired+1))
    else
      echo "skip     recall    — recall-opened hook opt-in not taken (adopt-memory-recall.sh --with-hook)"
    fi
    return
  fi
  if wired "$marker"; then
    echo "ok       recall    — recall-opened PostToolUse hook wired in .claude/settings.json"
  else
    echo "UNWIRED  recall    — $hookjs present but hook not in settings.json. Fix: $PY ${smerge:-tools/settings-merge.py} --fragment $frag"
    unwired=$((unwired+1))
  fi
}

check_hooks
check_agentcap
check_recall_opened

[ "$MODE" = session ] && exit 0
[ "$unwired" = 0 ] && exit 0 || exit 1
