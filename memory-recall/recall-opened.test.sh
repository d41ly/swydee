#!/usr/bin/env bash
# Runnable check for the recall-opened PostToolUse hook.
# Run: bash memory-recall/recall-opened.test.sh   (exit 0 = all pass · 1 = a failure · 3 = skipped)
#
# Every case drives the hook the way the harness does — a JSON payload on stdin — against a
# THROWAWAY repo carrying a fabricated query log. Nothing here touches the live log; a gate that
# writes to the instrument it measures is how the upstream log came to be 96% self-inflicted rows.
#
# The corpus root is the point. Upstream matched a literal `memory/`, so a project whose
# MEMORY_ROOT is anything else recorded NOTHING and looked identical to "no read matched" — the
# silent-nothing class. AC12 runs the same case with the root renamed and demands the same row.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/recall-opened.js"
pass=0; fail=0

command -v node >/dev/null 2>&1 || { echo "skip recall-opened — no node on PATH"; exit 3; }
command -v cygpath >/dev/null 2>&1 && WIN=1 || WIN=0
# node is a native binary: it cannot resolve an MSYS `/tmp/...` path, so every path that crosses
# into the payload or into argv is spelled the way the OS spells it. `-l` (LONG form) is not
# cosmetic: bare `-m` hands back the 8.3 name (`DAILY-~1`) while git writes the long one into a
# linked worktree's `gitdir:` pointer, and path.resolve does not unify the two — the sibling-
# worktree case below then recorded nothing, for a fixture reason that looks exactly like the
# hook defect it is there to catch (measured).
winp() { if [ "$WIN" = 1 ]; then cygpath -ml "$1"; else printf '%s' "$1"; fi; }

ck() { if [ "$2" = 1 ]; then echo "ok   $1"; pass=$((pass+1)); else echo "FAIL $1"; fail=$((fail+1)); fi; }

D=""
WT=""
newrepo() { # $1 = corpus root name
  D=$(mktemp -d)
  git init -q -b main "$D"
  mkdir -p "$D/.claude/hooks" "$D/.git/recall" "$D/$1/tooling"
  cp "$HOOK" "$D/.claude/hooks/recall-opened.js"
  : > "$D/$1/tooling/DECISIONS.md"
  : > "$D/$1/tooling/BACKLOG.md"
  # Tracked, not just present: a linked worktree checks out the INDEX, so an uncommitted corpus
  # gives `git worktree add` an empty tree and the sibling case below never materialises.
  git -C "$D" add -A >/dev/null 2>&1
  git -C "$D" -c user.email=t@e -c user.name=t commit -q -m init >/dev/null 2>&1
  LOG="$D/.git/recall/queries.jsonl"
}
cleanup() { [ -n "$D" ] && rm -rf "$D"; [ -n "$WT" ] && rm -rf "$WT"; D=""; WT=""; }

# A `query` row exactly as query.py logs one: qid, ISO `at`, and the ordered shown_paths.
logquery() { # $1 qid · $2 at · $3.. shown paths
  local qid=$1 at=$2; shift 2
  local paths="" p
  for p in "$@"; do paths="$paths${paths:+,}\"$p\""; done
  printf '{"qid":%s,"at":"%s","type":"query","query":"q","shown_paths":[%s]}\n' "$qid" "$at" "$paths" >> "$LOG"
}
# The COPY inside the throwaway repo, never the kit file: the hook derives its repo from __dirname
# (`<checkout>/.claude/hooks/` -> `<checkout>`), so running the kit copy would resolve this repo.
fire() { printf '{"tool_name":"Read","tool_input":{"file_path":"%s"}}' "$(winp "$1")" | node "$(winp "$D/.claude/hooks/recall-opened.js")"; }
opened() { grep -c '"type":"opened"' "$LOG" 2>/dev/null || true; }
NOW=$(date -u +%Y-%m-%dT%H:%M:%S+00:00)
OLD=$(date -u -d '-2 hours' +%Y-%m-%dT%H:%M:%S+00:00 2>/dev/null || date -u -v-2H +%Y-%m-%dT%H:%M:%S+00:00)

# AC11 — a Read of a SHOWN corpus file inside the window appends exactly one inferred row at its rank
newrepo memory
logquery 7 "$NOW" memory/tooling/DECISIONS.md memory/tooling/BACKLOG.md
fire "$D/memory/tooling/BACKLOG.md"
row=$(grep '"type":"opened"' "$LOG" || true)
{ [ "$(opened)" = 1 ] \
  && printf '%s' "$row" | grep -q '"of_qid":7' \
  && printf '%s' "$row" | grep -q '"rank":2' \
  && printf '%s' "$row" | grep -q '"in_shown":true' \
  && printf '%s' "$row" | grep -q '"inferred":true' \
  && printf '%s' "$row" | grep -q '"path":"memory/tooling/BACKLOG.md"'; } \
  && ck "AC11 shown corpus read -> one inferred row at rank 2" 1 \
  || ck "AC11 shown corpus read -> one inferred row at rank 2 [$row]" 0

# AC11b — the qid already has a record: a second fire appends nothing (hand records are never doubled)
fire "$D/memory/tooling/DECISIONS.md"
[ "$(opened)" = 1 ] && ck "AC11b second fire on a recorded qid appends nothing" 1 \
                    || ck "AC11b second fire on a recorded qid appends nothing" 0
cleanup

# AC12 — the SAME case with the corpus root renamed. Upstream's literal recorded nothing here.
newrepo docs
logquery 7 "$NOW" docs/tooling/DECISIONS.md docs/tooling/BACKLOG.md
fire "$D/docs/tooling/BACKLOG.md"
row=$(grep '"type":"opened"' "$LOG" || true)
{ [ "$(opened)" = 1 ] \
  && printf '%s' "$row" | grep -q '"rank":2' \
  && printf '%s' "$row" | grep -q '"in_shown":true' \
  && printf '%s' "$row" | grep -q '"path":"docs/tooling/BACKLOG.md"'; } \
  && ck "AC12 non-'memory' corpus root -> the same row" 1 \
  || ck "AC12 non-'memory' corpus root -> the same row [$row]" 0
cleanup

# The SIBLING WORKTREE arm, on a non-'memory' root. This is the only case the fast own-tree path
# cannot serve: feature work happens in sibling worktrees while the hook is wired out of the
# primary tree, so a boundary scan keyed on a literal root leaves the inferred stream permanently
# empty for the majority session shape. It is also what isolates that scan — for a read inside the
# hook's OWN checkout the two arms are redundant, so mutating either alone changes nothing.
newrepo docs
WT=$(mktemp -d)/wt
git -C "$D" worktree add -q -b side "$WT" >/dev/null 2>&1
if [ -d "$WT/docs/tooling" ]; then
  logquery 11 "$NOW" docs/tooling/DECISIONS.md
  fire "$WT/docs/tooling/DECISIONS.md"
  row=$(grep '"type":"opened"' "$LOG" || true)
  { [ "$(opened)" = 1 ] && printf '%s' "$row" | grep -q '"rank":1' \
    && printf '%s' "$row" | grep -q '"path":"docs/tooling/DECISIONS.md"'; } \
    && ck "sibling worktree, non-'memory' root -> rank 1 in the shared log" 1 \
    || ck "sibling worktree, non-'memory' root -> rank 1 in the shared log [$row]" 0
else
  echo "FAIL sibling worktree fixture did not materialise"; fail=$((fail+1))
fi
cleanup

# A corpus file that was NOT shown: recorded with rank null / in_shown false. That is the evidence
# the answer was not emitted, and it is the most valuable signal the log carries.
newrepo memory
logquery 9 "$NOW" memory/tooling/DECISIONS.md
fire "$D/memory/tooling/BACKLOG.md"
row=$(grep '"type":"opened"' "$LOG" || true)
{ [ "$(opened)" = 1 ] && printf '%s' "$row" | grep -q '"rank":null' \
  && printf '%s' "$row" | grep -q '"in_shown":false'; } \
  && ck "unshown corpus read -> rank null, in_shown false" 1 \
  || ck "unshown corpus read -> rank null, in_shown false [$row]" 0

# A read OUTSIDE the corpus root records nothing — the hook observes recall traffic, not every Read.
fire "$D/.claude/hooks/recall-opened.js"
[ "$(opened)" = 1 ] && ck "read outside the corpus root -> nothing appended" 1 \
                    || ck "read outside the corpus root -> nothing appended" 0
cleanup

# Outside the window: a two-hour-old query is not what you are reading.
newrepo memory
logquery 3 "$OLD" memory/tooling/DECISIONS.md
fire "$D/memory/tooling/DECISIONS.md"
[ "$(opened)" = 0 ] && ck "query older than the window -> nothing appended" 1 \
                    || ck "query older than the window -> nothing appended" 0

# Never fail a Read for a telemetry record: garbage on stdin, and a payload with no file_path.
printf 'not json at all' | node "$(winp "$D/.claude/hooks/recall-opened.js")"; rc1=$?
printf '{"tool_name":"Read","tool_input":{}}' | node "$(winp "$D/.claude/hooks/recall-opened.js")"; rc2=$?
{ [ "$rc1" = 0 ] && [ "$rc2" = 0 ] && [ "$(opened)" = 0 ]; } \
  && ck "malformed payload -> exit 0, nothing appended" 1 \
  || ck "malformed payload -> exit 0, nothing appended (rc $rc1/$rc2)" 0
cleanup

echo "---- $pass passed, $fail failed ----"
[ "$fail" = 0 ]
