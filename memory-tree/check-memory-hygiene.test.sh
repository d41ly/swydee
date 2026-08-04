#!/usr/bin/env bash
# Fixture self-test for check-memory-hygiene.sh CHECK 12 (spec-format ratchet).
# Builds a scratch git repo with conforming + violating spec fixtures and asserts each check-12
# class fires (red) or stays silent (green), plus the disabled-when-blank conf contract. Only
# check-12 lines are asserted — the scratch repo intentionally reds other checks and that noise
# is ignored.
#   bash memory-tree/check-memory-hygiene.test.sh    # "PASS (37 assertions)" + exit 0 = good
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/check-memory-hygiene.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cd "$TMP" || exit 2
git init -q . && git config user.email t@t.test && git config user.name t && git config core.autocrlf false
printf 'MEMORY_ROOT=memory\nDISCIPLINES="architecture"\nFAMILIES="architecture:ARCH"\nSPEC_FORMAT_CUTOFF="2026-07-15"\n' > .memory-tree.conf

D=memory/architecture/builds/2026-08-01-ARCH-tFixture
mkdir -p "$D/spec/subspecs"
printf 'sentinel\n' > memory/HYGIENE.md

good() { cat <<'EOF'
# ARCH-tFixture-1 — fixture

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

good > "$D/spec/2026-08-01-spec-tFixture-1.md"                                   # conforming -> silent
good | sed 's/$/\r/' > "$D/spec/2026-08-01-spec-tFixture-2.md"                   # CRLF twin -> silent
printf '# nested\nno header here\n## Wrong\nbody\n' > "$D/spec/subspecs/2026-08-01-spec-tFixture-3.md"  # nested+headerless -> red
good | sed 's/^## 4\. Design$/## 4. Blueprint/' > "$D/spec/2026-08-01-spec-tFixture-4.md"               # wrong canon -> red
printf '# t1\n\n**Status:** OPEN · rev-1 · 2026-08-01 · node a · Tier-1 · base 0123abcd\n\n## Whatever\n\nfree-form body\n' \
  > "$D/spec/2026-08-01-spec-tFixture-5.md"                                      # Tier-1 light profile -> silent
good | sed 's/^A goal\.$/Ship on YYYY-MM-DD./' > "$D/spec/2026-08-01-spec-tFixture-6.md"                # placeholder -> red
good | sed '/^The design\.$/d' > "$D/spec/2026-08-01-spec-tFixture-7.md"          # empty section body -> red
good | sed 's/rev-1 · 2026-08-01 · node/rev-2 · 2026-08-01 · node/' > "$D/spec/2026-08-01-spec-tFixture-8.md"  # header rev not in §9 -> red
good | sed 's/^\*\*Status:\*\* SPECCED/**Status:** WONTDO/' > "$D/spec/2026-08-01-spec-tFixture-9.md"   # bare WONTDO tail -> red
good | sed 's/^\*\*Status:\*\* SPECCED/**Status:** CLOSED/; s/^none$/- still deciding something/' \
  > "$D/spec/2026-08-01-spec-tFixture-10.md"                                     # terminal + open §8 -> red
printf '# old era\nfreeform, no header\n## Anything\n' > "$D/spec/2026-07-10-spec-tFixture-11.md"       # pre-cutoff -> silent
{ good; printf '\n```text\n~~~\n## bogus heading inside fence\n```\n'; } > "$D/spec/2026-08-01-spec-tFixture-12.md"  # fence torture -> silent
good > "$D/spec/2026-08-01-spec-tFixture-13.md"                                  # deleted after commit -> red
good | sed 's/^A goal\.$/Ship on YYYY-MM-DD./; /^The design\.$/d' \
  > "$D/spec/2026-08-01-spec-tFixture-14.md"                                     # TWO findings in ONE file -> red
good | sed 's/SPECCED/CLOSED/' > "$D/spec/2026-08-01-spec-tFixture-15.md"        # terminal + RESOLVED §8 -> silent
# TRAILING BLANK LINES with §8 as the last section (TOOL-aBatchedLintel-1). Check 12 reproduces
# `sed "1d;\$d"`, whose deletes act on the CONCATENATED range output — so the range's last line, and
# therefore which line `\$d` removes, depends on whether the body still carries its trailing blanks.
# The pre-batch body lived in a command substitution, which DROPS them, so this file is SILENT on the
# terminal-§8 arm. A body array that retains them makes `- unresolved` the survivor and reds it.
printf '# t\n\n**Status:** CLOSED · rev-1 · 2026-08-01 · node a · Tier-2 · base 0123abcd\n\n## 8. Open questions\n\n- unresolved\n\n\n' \
  > "$D/spec/2026-08-01-spec-tFixture-16.md"
good | sed 's/^## /## X/' > "$D/spec/2026-08-01-spec-tFixture-17.md"             # every heading wrong -> long diff

# ---- CHECK 7 fixture. The check had NO coverage here, and its per-file `_unfenced | awk` pair is
# ---- now one batched awk, so the exemptions and — above all — the line NUMBERING are what a
# ---- regression silently moves. The offending row sits at UNFENCED line 5 and RAW line 8; only a
# ---- counter over the unfenced stream reports 5. The 300/301 pair pins the threshold from both
# ---- sides, ASCII on purpose so bytes and characters agree on any awk build.
mkdir -p memory/architecture
C7L=$(printf 'x%.0s' $(seq 1 340))
{ printf '# Backlog\n'
  printf '\n```text\n%s\n```\n' "$C7L"                             # >300 inside a fence  -> silent
  printf '# %s\n' "$C7L"                                           # >300 comment line    -> silent
  printf '|%s|\n' "$(printf -- '-%.0s' $(seq 1 340))"              # >300 table separator -> silent
  printf -- '- ARCH-tFixture-1 · OPEN · %s\n' "$C7L"               # >300 entry row       -> RED at :5
  printf '%s\n' "$(printf 'z%.0s' $(seq 1 300))"                   # exactly 300          -> silent
  printf '%s\n' "$(printf 'w%.0s' $(seq 1 301))"                   # exactly 301          -> RED at :7
} > memory/architecture/BACKLOG.md

git add -A && git commit -q -m fixtures --no-verify
rm -f "$D/spec/2026-08-01-spec-tFixture-13.md"   # tracked-but-absent only exists after the commit

out=$(bash "$SCRIPT" 2>/dev/null)
st=0
hit()  { grep -qF "$1" <<<"$out" || { echo "FAIL missing: $1"; st=1; }; }
miss() { if grep -qF "$1" <<<"$out"; then echo "FAIL unexpected: $1"; st=1; fi; }
hitl() { grep -qxF "$1" <<<"$out" || { echo "FAIL missing exact line: $1"; st=1; }; }
lineno()  { grep -nF "$1" <<<"$out" | head -1 | cut -d: -f1; }
before()  { local a b; a=$(lineno "$1"); b=$(lineno "$2")
            { [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ]; } \
              || { echo "FAIL expected [$1] before [$2] (got '$a' vs '$b')"; st=1; }; }

hit  'tFixture-3.md (missing/invalid'
hit  'tFixture-4.md (## sections differ'
hit  'tFixture-6.md (unfilled skeleton placeholder'
hit  'tFixture-7.md (section with an empty body'
hit  'tFixture-8.md (header rev-2 not logged'
hit  'tFixture-9.md (WONTDO needs'
hit  'tFixture-10.md (terminal Status'
miss 'tFixture-1.md ('
miss 'tFixture-2.md ('
miss 'tFixture-5.md ('
miss 'tFixture-11.md ('
miss 'tFixture-12.md ('
hit  'tFixture-13.md (tracked but missing from worktree'
hit  'tFixture-14.md (unfilled skeleton placeholder'
miss 'tFixture-15.md ('
hit  'tFixture-16.md (## sections differ'
miss 'tFixture-16.md (terminal Status'
# Emission ORDER inside one file: a per-file loop got it for free, one awk over a driver does not.
before 'tFixture-14.md (unfilled skeleton placeholder' 'tFixture-14.md (section with an empty body'

# ---- the section-canon DIFF EXCERPT. The batched check 12 emits a sentinel record and rebuilds the
# ---- excerpt afterwards with the original `diff | head -6 | sed`, so BOTH halves need pinning: it
# ---- is a real diff, indented four spaces, capped at six lines, and the sentinel byte itself never
# ---- reaches the output. Without these, deleting the sentinel or shrinking the cap is invisible.
hit  'tFixture-17.md (## sections differ'
hitl '    < ## 4. Design'
hitl '    > ## 4. Blueprint'
hitl '    ---'
case "$out" in *$'\001'*) echo "FAIL the check-12 diff sentinel leaked into the output"; st=1;; esac
n17=$(awk '/tFixture-17\.md \(## sections differ/{g=1; next} g && /^    /{c++; next} g{exit} END{print c+0}' <<<"$out")
[ "$n17" = 6 ] || { echo "FAIL the diff excerpt for a wholly-renamed spec is $n17 lines, expected the head -6 cap"; st=1; }

# ---- CHECK 7: unfenced line NUMBERING and the three exemptions.
hit  'HYGIENE check 7 FAILED'
n7=$(grep -cE '^memory/architecture/BACKLOG\.md:[0-9]+ \([0-9]+ chars\)$' <<<"$out")
[ "$n7" = 2 ] || { echo "FAIL check 7 emitted $n7 findings, expected exactly 2 (fence, comment and separator are exempt; the 300-byte row is under the cap)"; st=1; }
hitl 'memory/architecture/BACKLOG.md:7 (301 chars)'
miss 'memory/architecture/BACKLOG.md:6 ('
c7line=$(grep -E '^memory/architecture/BACKLOG\.md:[0-9]+ \([0-9]+ chars\)$' <<<"$out" | head -1)
case "$c7line" in 'memory/architecture/BACKLOG.md:5 ('*) ;;
  *) echo "FAIL check 7 reported '$c7line'; expected the offending row at UNFENCED line 5 (raw line 8)"; st=1;; esac

# ---- --staged: `in_scope` is the ONLY thing deciding selection there, so no full-mode arm above can
# ---- see a scoping regression. A red must be the committer's own file, never another stream's debt.
git reset -q
printf 'x\n' >> "$D/spec/2026-08-01-spec-tFixture-4.md"
git add "$D/spec/2026-08-01-spec-tFixture-4.md"
outs=$(bash "$SCRIPT" --staged 2>/dev/null)
grep -qF 'tFixture-4.md (## sections differ' <<<"$outs" \
  || { echo "FAIL --staged missed the staged file's own finding"; st=1; }
grep -qF 'tFixture-10.md (' <<<"$outs" \
  && { echo "FAIL --staged reported an UNSTAGED file's finding"; st=1; }
# check 7 carries its own `in_scope` filter, and the arm above stages only a SPEC — so an unstaged
# over-cap index file must stay silent. Without this, dropping check 7's in_scope is invisible.
grep -qF 'HYGIENE check 7' <<<"$outs" \
  && { echo "FAIL --staged reported check 7 for an UNSTAGED index file"; st=1; }
git reset -q && git checkout -q -- "$D/spec/2026-08-01-spec-tFixture-4.md"
# ...and the other direction: staging the index file DOES surface its own over-cap row.
printf '\n' >> memory/architecture/BACKLOG.md
git add memory/architecture/BACKLOG.md
outs7=$(bash "$SCRIPT" --staged 2>/dev/null)
grep -qF 'HYGIENE check 7' <<<"$outs7" \
  || { echo "FAIL --staged missed check 7 on the staged index file"; st=1; }
git reset -q && git checkout -q -- memory/architecture/BACKLOG.md

# ---- SOURCE-level assertions. These three hazards cannot be reached by any fixture on this
# ---- platform, so they are asserted against the engine's text instead.
#
# 1. Every getline loop strips a trailing CR. On Linux a CRLF worktree delivers the \r into awk and
#    the fence toggle and every compare break. On a Cygwin node the C runtime strips CR BEFORE awk
#    sees a byte — measured through a filename argument, through `getline line < f` AND through a
#    pipe — so the CRLF fixture above passes identically with and without the guard.
ncr=$(awk '
  index($0, "while ((getline line < f) > 0)") { open[++n] = NR; guarded[n] = 0 }
  n > 0 && NR > open[n] && NR <= open[n] + 2 && index($0, "sub(/\\r$/, \"\", line)") { guarded[n] = 1 }
  END { for (i = 1; i <= n; i++) if (!guarded[i]) print "line " open[i]
        if (n < 3) print "only " n " getline loop(s) — expected at least 3" }
' "$SCRIPT")
[ -z "$ncr" ] || { echo "FAIL a getline loop with no trailing-CR strip within 2 lines: $ncr"; st=1; }
# 2. Interval expressions stay spelled out inside the batched awk. On a build that does not honour
#    `{8}` the header regex demands those literal bytes and never matches, so every post-cutoff spec
#    reds with "missing/invalid **Status:** header" — a loud break of a check that works today.
#    The predicate matches `{` followed by a DIGIT, not a bare `{` — every one of these lines ends in
#    the `) {` that opens its own if-block, so a bare-brace ban flags the innocent and passes nothing.
ivl=$(grep -nE 'hdr [!=]~ /' "$SCRIPT" | grep -E '\{[0-9]' || true)
[ -z "$ivl" ] || { echo "FAIL an interval expression survives in a batched-awk regex: $ivl"; st=1; }
# 3. Check 7 takes NO locale prefix. `length()` decides its verdict and its character-versus-byte
#    meaning belongs to the awk build and the ambient locale; check 8's `LC_ALL=C xargs` seventeen
#    lines below sorts, it does not measure, and is not the pattern to copy here.
#    Comment lines are stripped first: the region carries prose explaining exactly this ban, and a
#    predicate that fires on the comment documenting the fix is the classic self-inflicted red.
lc7=$(awk '/^# 7 — /{f=1} /^# 8 — /{f=0} f && $0 !~ /^[[:space:]]*#/ && /LC_ALL/{print NR ": " $0}' "$SCRIPT")
[ -z "$lc7" ] || { echo "FAIL check 7 carries a locale prefix — length() must stay locale-dependent: $lc7"; st=1; }

# disabled-when-blank contract: same tree, cutoff removed -> check 12 fully silent.
printf 'MEMORY_ROOT=memory\nDISCIPLINES="architecture"\nFAMILIES="architecture:ARCH"\n' > .memory-tree.conf
out2=$(bash "$SCRIPT" 2>/dev/null)
if grep -qF 'HYGIENE check 12' <<<"$out2"; then echo "FAIL: check 12 ran with blank SPEC_FORMAT_CUTOFF"; st=1; fi
if ! grep -qF 'HYGIENE check 12' <<<"$out"; then echo "FAIL: check 12 never fired with cutoff armed"; st=1; fi

[ "$st" = 0 ] && echo "PASS (37 assertions)"
exit "$st"
