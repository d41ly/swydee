#!/usr/bin/env bash
# Regression suite for adopt-agent-instructions.sh — one scenario per part-d review finding.
set -u
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
TOOL=/c/projects/coding-governance/tools/agent-instructions/adopt-agent-instructions.sh
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok(){ echo "PASS $1"; pass=$((pass+1)); }
bad(){ echo "FAIL $1"; echo "     $2"; fail=$((fail+1)); }
mkrepo(){ R="$TMP/$1"; mkdir -p "$R"; git -C "$R" init -q; git -C "$R" config user.email t@t; git -C "$R" config user.name t; git -C "$R" config core.autocrlf false; printf '# Rules\n\n- One.\n' > "$R/src.md"; }
run(){ ( cd "$R" && bash "$TOOL" "$@" ); }

# 1 — default install: AGENTS.md canonical, CLAUDE.md @import, gemini nested config, copilot copy
mkrepo t1
run --source src.md >/dev/null 2>&1
[ -f "$R/AGENTS.md" ] && ok "1 AGENTS.md created" || bad "1" "no AGENTS.md"
[ "$(cat "$R/CLAUDE.md")" = "@AGENTS.md" ] && ok "1 CLAUDE.md @import" || bad "1" "CLAUDE.md=$(cat "$R/CLAUDE.md")"
grep -q '"context"' "$R/.gemini/settings.json" && grep -q '"fileName": "AGENTS.md"' "$R/.gemini/settings.json" && ok "1 gemini nested context.fileName" || bad "1" "gemini schema: $(cat "$R/.gemini/settings.json")"
cmp -s "$R/AGENTS.md" "$R/.github/copilot-instructions.md" && ok "1 copilot copy" || bad "1" "copilot not a copy"

# 3 — gemini idempotency: re-run reports current, not 'add by hand'
out=$(cd "$R" && bash "$TOOL" 2>&1)
echo "$out" | grep -q 'context.fileName, current' && ok "3 gemini idempotent (=current)" || bad "3" "re-run gemini: $out"

# 1/10 — --check content-aware: passes correct, fails wrong gemini config
mkrepo t_gok; run --source src.md >/dev/null 2>&1
(cd "$R" && bash "$TOOL" --check) >/dev/null 2>&1 && ok "10 check passes correct wiring" || bad "10" "check failed on correct"
printf '{"theme":"dark"}\n' > "$R/.gemini/settings.json"; rm -f "$R/GEMINI.md"
(cd "$R" && bash "$TOOL" --check --aliases gemini) >/dev/null 2>&1 && bad "1/10" "check FALSE-PASSED unwired gemini" || ok "1/10 check fails unwired gemini config"

# 2 — symlink mode, subdir alias (copilot) must NOT dangle even without python3
mkrepo t2; run --source src.md --aliases copilot --mode symlink >/dev/null 2>&1
if [ -L "$R/.github/copilot-instructions.md" ]; then
  [ -e "$R/.github/copilot-instructions.md" ] && ok "2 copilot symlink resolves (no dangle)" || bad "2" "DANGLING symlink"
else
  cmp -s "$R/AGENTS.md" "$R/.github/copilot-instructions.md" && ok "2 copilot fell back to copy (symlink unavailable)" || bad "2" "copilot neither symlink nor copy"
fi
# and rel target is ../AGENTS.md if it is a symlink
if [ -L "$R/.github/copilot-instructions.md" ]; then [ "$(readlink "$R/.github/copilot-instructions.md")" = "../AGENTS.md" ] && ok "2 rel target ../AGENTS.md" || bad "2" "rel=$(readlink "$R/.github/copilot-instructions.md")"; else ok "2 (copy fallback, rel n/a)"; fi

# 4 — existing symlink to unrelated file: refused without --force
mkrepo t4; (cd "$R" && printf 'mine\n' > shared.md && ln -s shared.md .cursorrules 2>/dev/null)
if [ -L "$R/.cursorrules" ]; then
  out=$(run --source src.md --aliases cursor 2>&1); rc=$?
  [ "$rc" != 0 ] && [ "$(basename "$(readlink "$R/.cursorrules")")" = "shared.md" ] && ok "4 user symlink protected without --force" || bad "4" "user symlink clobbered (rc=$rc, now→$(readlink "$R/.cursorrules" 2>/dev/null))"
else ok "4 (symlink unavailable on host — scenario skipped)"; fi

# 5 — copy drift: --check flags it, --force re-syncs
mkrepo t5; run --source src.md --aliases cursor --mode copy >/dev/null 2>&1
printf '# Rules\n\n- One.\n- Two (new).\n' > "$R/AGENTS.md"    # canonical changes
(cd "$R" && bash "$TOOL" --check --aliases cursor) >/dev/null 2>&1 && bad "5" "check missed copy drift" || ok "5 check flags copy drift"
run --source AGENTS.md --aliases cursor --mode copy --force >/dev/null 2>&1
cmp -s "$R/AGENTS.md" "$R/.cursorrules" && ok "5 --force re-syncs drifted copy" || bad "5" "force did not re-sync"

# 6/11 — CLI validation: missing option value → clean env error exit 2; bad mode → exit 2
mkrepo t6
out=$(run --source 2>&1); rc=$?; { [ "$rc" = 2 ] && echo "$out" | grep -q 'AGENT-INSTR env ERROR'; } && ok "11 missing --source value → env error exit 2" || bad "11" "rc=$rc out=$out"
out=$(run --source src.md --mode symlnk 2>&1); rc=$?; [ "$rc" = 2 ] && echo "$out" | grep -q 'must be symlink' && ok "6 bad --mode → exit 2" || bad "6" "rc=$rc out=$out"

# 9 — eol-attribute copy must not read as drift (cmp -s, not git hash-object)
mkrepo t9; printf '*.md text eol=lf\n' > "$R/.gitattributes"; printf '# Rules\r\n\r\n- CRLF authored.\r\n' > "$R/src.md"
run --source src.md --aliases cursor --mode copy >/dev/null 2>&1
git -C "$R" add -A >/dev/null 2>&1
(cd "$R" && bash "$TOOL" --check --aliases cursor) >/dev/null 2>&1 && ok "9 eol-attr copy not false-drift (cmp -s)" || bad "9" "check false-flagged an identical copy under eol=lf"

echo "==== $pass passed, $fail failed ===="
[ "$fail" = 0 ]
