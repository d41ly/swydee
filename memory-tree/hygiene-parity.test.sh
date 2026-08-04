#!/usr/bin/env bash
# Differential byte-identity harness for check-memory-hygiene.sh (TOOL-aBatchedLintel-1).
#
# A fork-collapse rewrite of a gate has exactly one hard bar: the gate must keep saying the same
# thing. This runs a BEFORE and an AFTER copy of the engine over the same scratch corpora and asserts
# their stdout and exit codes are byte-identical, in FULL and in --staged mode.
#
#   bash tools/memory-tree/hygiene-parity.test.sh <before-rev>    # e.g. a pre-change sha
#
# NOT a gate leg, deliberately: it needs a before-revision to compare against, and that reference
# rots the moment anything else edits the engine. The standing protection is
# check-memory-hygiene.test.sh, which needs no baseline. Keep this committed so the NEXT collapse
# pass can re-point it at its own base.
#
# Two corpora, because either alone is blind:
#   arm 1  the REAL tracked memory tree with violations injected — real ordering, real population
#   arm 2  pathological SHAPES no committed file has — where the subtle divergences actually live
set -u
ROOT=$(git rev-parse --show-toplevel) || exit 2
cd "$ROOT" || exit 2
BEFORE_REV=${1:-}
[ -n "$BEFORE_REV" ] || { echo "usage: bash tools/memory-tree/hygiene-parity.test.sh <before-rev>"; exit 2; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
BEFORE="$TMP/before.sh"; AFTER="$TMP/after.sh"
git show "$BEFORE_REV:tools/memory-tree/check-memory-hygiene.sh" > "$BEFORE" 2>/dev/null \
  || { echo "FAIL cannot read the engine at $BEFORE_REV"; exit 2; }
cp tools/memory-tree/check-memory-hygiene.sh "$AFTER" || exit 2
# Without this, passing the CURRENT revision (or running after the change is committed) compares a
# deterministic program against itself and prints PASS over every arm. That is the exact defect this
# harness exists to catch, in the harness itself.
if cmp -s "$BEFORE" "$AFTER"; then
  echo "FAIL before($BEFORE_REV) and after are the SAME BYTES — nothing is being compared."
  exit 2
fi

st=0
say() { printf '%s\n' "$*"; }
run() { ( bash "$1" ${2:-} 2>&1; printf 'rc=%s\n' "$?" ); }
# The floor is anchored on the message texts checks 12 and 7 actually emit. A path-shaped prefix also
# matches check 2's broken-link findings, which a corpus produces for free, so a floor built on one
# is padded by a check this rewrite never touches.
FINDINGS_RE='\((tracked but missing from worktree|missing/invalid \*\*Status|unfilled skeleton placeholder|WONTDO needs|## sections differ|section with an empty body|header rev-[0-9]+ not logged|terminal Status with unresolved)'
count12() { printf '%s\n' "$1" | grep -cE "$FINDINGS_RE" || true; }
count7()  { printf '%s\n' "$1" | grep -cE '^[^ ]+:[0-9]+ \([0-9]+ chars\)$' || true; }

CONF="$ROOT/.memory-tree.conf"
[ -f "$CONF" ] || { echo "FAIL no .memory-tree.conf at the repo root"; exit 2; }

nine() { cat <<'EOF'
# TOOL-tFixture-1 — fixture

**Status:** SPECCED · rev-1 · 2026-08-01 · node a · Tier-2 · base 0123abcd

## 1. Goal

A goal.

## 2. Scope (IN)

- S1 something.

## 3. Non-goals (OUT)

- Nothing else.

## 4. Design

The design.

## 5. Production-readiness checklist

- security: N/A — fixture.

## 6. Acceptance criteria

- AC1 When run, it passes.

## 7. Gates

- memory hygiene.

## 8. Open questions

none

## 9. Revision log

- rev-1 · 2026-08-01 · initial draft.
EOF
}

# =====================================================================================================
# ARM 1 — the REAL tracked memory tree, with a violation of each check-12 class injected.
# =====================================================================================================
say "-- arm 1: real corpus"
R1="$TMP/real"; mkdir -p "$R1"
git archive HEAD memory | tar -x -C "$R1" || exit 2
cp "$CONF" "$R1/.memory-tree.conf"
cd "$R1" || exit 2
git init -q -b main . && git config user.email t@t.test && git config user.name t && git config core.autocrlf false

# The check-12 population, derived the way the engine derives it.
specs=()
while IFS= read -r f; do
  b=${f##*/}
  [[ $b =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}-spec-[A-Za-z0-9]+-[0-9]+(-[a-z0-9][a-z0-9-]*)?\.md$ ]] || continue
  [ "${b:0:10}" \< "2026-07-15" ] && continue
  specs+=("$f")
done < <(find memory -path '*/builds/*/spec/*' -name '*.md' | tr '\\' '/' | LC_ALL=C sort)
[ "${#specs[@]}" -ge 5 ] || { say "FAIL only ${#specs[@]} in-scope specs — too few to prove anything"; exit 1; }
say "   population: ${#specs[@]} specs"

mut() {   # mut <file> <sed|awk> <program>   — asserts the mutation APPLIED
  local f=$1 tool=$2 prog=$3
  cp "$f" "$f.pre" || { say "FAIL cannot stage $f"; st=1; return; }
  "$tool" "$prog" "$f.pre" > "$f"
  cmp -s "$f.pre" "$f" && { say "FAIL mutation did not apply to $f"; st=1; }
  rm -f "$f.pre"
}
np=${#specs[@]}
mut "${specs[0]}"            sed 's/^\*\*Status:\*\* .*/**Status:** not a real header/'
mut "${specs[$((np/4))]}"    sed '$a\
Ship it on YYYY-MM-DD.'
mut "${specs[$((np/2))]}"    sed 's/^## 4\. Design$/## 4. Blueprint/'
mut "${specs[$((np-1))]}"    sed 's/^\(\*\*Status:\*\* [A-Z]*\) · rev-[0-9]* · /\1 · rev-97 · /'
git add -A && git commit -q -m corpus --no-verify
rm -f "${specs[$((np/4))]}"     # tracked but missing from the worktree — only exists post-commit

b1=$(run "$BEFORE"); a1=$(run "$AFTER")
n1=$(count12 "$b1")
say "   before: $n1 check-12 findings"
[ "$n1" -ge 4 ] || { say "FAIL only $n1 findings — the mutation battery is not landing"; st=1; }
if [ "$b1" != "$a1" ]; then
  say "FAIL arm 1 diverges (before < , after > ):"; diff <(printf '%s\n' "$b1") <(printf '%s\n' "$a1") | head -40; st=1
fi

say "-- arm 1: --staged"
printf '\n' >> "${specs[0]}"; git add "${specs[0]}"
b1s=$(run "$BEFORE" --staged); a1s=$(run "$AFTER" --staged)
# Without this the staged comparison can pass by both sides emitting nothing at all.
[ "$(count12 "$b1s")" -ge 1 ] || { say "FAIL the --staged run produced no check-12 finding to compare"; st=1; }
if [ "$b1s" != "$a1s" ]; then
  say "FAIL --staged diverges:"; diff <(printf '%s\n' "$b1s") <(printf '%s\n' "$a1s") | head -40; st=1
fi

# =====================================================================================================
# ARM 2 — pathological SHAPES. Arm 1 can only expose a divergence some committed file already
# triggers; the subtle ones live here. Shapes 08, A and B are the §8 sed-range semantics: the deletes
# act on the CONCATENATED range output, the range RESTARTS on a later opener, and it runs to EOF when
# §9 never follows. Shape 08 is the divergence upstream actually shipped a bug for.
# =====================================================================================================
say "-- arm 2: pathological shapes"
R2="$TMP/shapes"; D=memory/tooling/builds/2026-08-01-TOOL-tShape/spec
mkdir -p "$R2/$D/subspecs" "$R2/memory/project"
cp "$CONF" "$R2/.memory-tree.conf"
cd "$R2" || exit 2
printf 'sentinel\n' > memory/HYGIENE.md
S() { printf '%s' "$D/2026-08-01-spec-tShape-$1.md"; }
printf '%s' "$(nine)"                      > "$(S 01)"   # no trailing newline
: > "$(S 02)"                                            # empty file
printf '\n\n\n\n'                          > "$(S 03)"   # blank lines only
printf 'a\nb\nc\nd\n**Status:** SPECCED · rev-1 · 2026-08-01 · node a · Tier-1 · base 0123abcd\n' > "$(S 04)"
printf 'a\nb\nc\nd\ne\n**Status:** SPECCED · rev-1 · 2026-08-01 · node a · Tier-1 · base 0123abcd\n' > "$(S 05)"
printf 'a\n```x\nq\nw\ne\n```\nb\nc\nd\n**Status:** SPECCED · rev-1 · 2026-08-01 · node a · Tier-1 · base 0123abcd\n' > "$(S 06)"
# 08 — §8 LAST, unresolved, TRAILING BLANKS. The pre-batch body lived in a command substitution,
# which drops them, so `$d` removed `- unresolved` and this was SILENT. A body array that keeps them
# surfaces it. This shape is why the strip exists.
printf '# t\n\n**Status:** CLOSED · rev-1 · 2026-08-01 · node a · Tier-2 · base 0123abcd\n\n## 8. Open questions\n\n- unresolved\n\n\n\n' > "$(S 08)"
printf '# t\n\n**Status:** CLOSED · rev-1 · 2026-08-01 · node a · Tier-2 · base 0123abcd\n\n## 8. Open questions\n\n- unresolved\n' > "$(S 09)"
# A — the §8 heading TWICE, first body empty. Real sed yields the HEADING as the survivor, which
# matches neither none* nor N/A*, so it FINDS. A per-range implementation that drops both headings
# yields `none` and stays silent.
printf '# t\n\n**Status:** CLOSED · rev-1 · 2026-08-01 · node a · Tier-2 · base 0123abcd\n\n## 8. Open questions\n\n## 8. Open questions\n\nnone\n\n## 9. Revision log\n\n- rev-1 · 2026-08-01 · d.\n' > "$(S 10)"
# B — no §9 after §8, so the range runs to EOF and `$d` removes the `## 10.` line, leaving
# `- unresolved` as the survivor. An implementation that stops at the next heading goes silent.
printf '# t\n\n**Status:** CLOSED · rev-1 · 2026-08-01 · node a · Tier-2 · base 0123abcd\n\n## 8. Open questions\n\n- unresolved\n\n## 10. Appendix\n\ntail\n' > "$(S 11)"
nine | sed 's/^\*\*Status:\*\* SPECCED · rev-1/**Status:** SPECCED · rev-10/; s/^- rev-1 · 2026-08-01 · initial draft\.$/- rev-007 · 2026-08-01 · a.\n- rev-9 · 2026-08-01 · b./' > "$(S 12)"
nine | sed 's/^\*\*Status:\*\* SPECCED · rev-1/**Status:** SPECCED · rev-9/; s/^- rev-1 · 2026-08-01 · initial draft\.$/- rev-10 · 2026-08-01 · later./' > "$(S 13)"
nine | sed 's/^## 4\. Design$/## 4. Design  /'                    > "$(S 14)"
{ nine; printf '\n```text\nnever closed\n'; }                     > "$(S 15)"
nine | sed 's|^The design\.$|```\n~~~\n## 99. Bogus\n```|'        > "$(S 16)"
nine | sed 's/^The design\.$/   /'                                > "$(S 17)"
nine | sed 's/^The design\.$/\t/'                                 > "$(S 18)"
nine | sed 's/^\*\*Status:\*\* SPECCED\(.*\)base 0123abcd$/**Status:** WONTDO\1base 0123abcd/'            > "$(S 19)"
nine | sed 's/^\*\*Status:\*\* SPECCED\(.*\)base 0123abcd$/**Status:** WONTDO\1base 0123abcde · why/'     > "$(S 20)"
nine | sed 's/^\*\*Status:\*\* SPECCED/**Status:** CLOSED/; s/^none$/N\/A — nothing/'                     > "$(S 21)"
nine | sed 's/^\*\*Status:\*\* SPECCED/**Status:** CLOSED/; s/^none$/  none/'                             > "$(S 22)"
nine | sed "s/^The design\.\$/\x01 sentinel byte/"                > "$(S 23)"
nine | sed 's/^## 4\. Design$/## 4.\tDesign/'                     > "$(S 24)"
printf '# t\n\n**Status:** WONTDO · rev-1 · 2026-08-01 · node a · Tier-1 · base 0123abcd\n\n## Whatever\n\nbody\n' > "$(S 25)"
printf '# t\r\n\r\n**Status:** CLOSED · rev-1 · 2026-08-01 · node a · Tier-2 · base 0123abcd\r\n\r\n## 8. Open questions\r\n\r\n- unresolved\r\n\r\n\r\n' > "$(S 26)"
printf '# t\n\n**Status:** WONTDO · rev-1 · 2026-08-01 · node a · Tier-2 · base 0123abcd\n\n## 8. Open questions\n\n- unresolved\n\n' > "$D/subspecs/2026-08-01-spec-tShape-27.md"
printf 'grandfathered\n' > "$D/2026-07-01-spec-tShape-28.md"

# check 7 rows, in a real index_set member.
L=$(printf 'y%.0s' $(seq 1 320))
{ printf '# Backlog\n'
  printf -- '- TOOL-tShape-1 · OPEN · %s\n' "$L"                     # plain long row        -> RED
  printf '```\n'; printf -- '- TOOL-tShape-2 · OPEN · %s\n' "$L"     # inside a fence        -> silent
  printf '~~~\n'; printf -- '- TOOL-tShape-3 · OPEN · %s\n' "$L"     # ~~~ is not the closer -> silent
  printf '```\n'
  printf '   |%s|   \n' "$(printf -- '-%.0s' $(seq 1 320))"          # padded separator      -> silent
  printf '  # %s\n' "$L"                                             # INDENTED comment      -> RED
  printf '%s\n' "$(printf 'z%.0s' $(seq 1 300))"                     # exactly 300 ASCII     -> silent
  printf '%s\n' "$(printf 'w%.0s' $(seq 1 301))"                     # exactly 301 ASCII     -> RED
  # BYTE-vs-CHARACTER: 160 middots are 320 bytes and 160 characters, so this row lands on opposite
  # sides of the cap under the two readings of length(). Both engines must agree either way — this is
  # the only shape that catches an LC_ALL= prefix being added to the check-7 awk.
  printf -- '- TOOL-tShape-4 · OPEN · %s\n' "$(printf '·%.0s' $(seq 1 160))"
} > memory/tooling/BACKLOG.md
git init -q -b main . && git config user.email t@t.test && git config user.name t && git config core.autocrlf false
git add -A && git commit -q -m shapes --no-verify

b2=$(run "$BEFORE"); a2=$(run "$AFTER")
s12=$(count12 "$b2"); s7=$(count7 "$b2")
say "   before: $s12 check-12 findings · $s7 check-7 findings"
[ "$s12" -ge 10 ] || { say "FAIL only $s12 shape findings — the shape corpus is not exercising check 12"; st=1; }
[ "$s7"  -ge 3 ]  || { say "FAIL only $s7 check-7 findings — the shape corpus is not exercising check 7"; st=1; }
if [ "$b2" != "$a2" ]; then
  say "FAIL arm 2 diverges (before < , after > ):"; diff <(printf '%s\n' "$b2") <(printf '%s\n' "$a2") | head -40; st=1
fi

# =====================================================================================================
# The harness's own honesty check: it must be able to SEE a difference.
# =====================================================================================================
say "-- self-check (a planted difference must be caught)"
SPOILED="$TMP/spoiled.sh"
sed 's/^exit "\$status"$/echo "planted"; exit "$status"/' "$BEFORE" > "$SPOILED"
cmp -s "$BEFORE" "$SPOILED" && { say "FAIL the planted difference did not apply"; st=1; }
[ "$(run "$SPOILED")" = "$b2" ] && { say "FAIL the harness cannot see a planted difference — every PASS above is meaningless"; st=1; }

cd "$ROOT" || exit 2
[ "$st" = 0 ] && say "PASS — before($BEFORE_REV) and after are byte-identical over the real corpus and 28 shapes, full and --staged"
exit "$st"
