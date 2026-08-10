#!/usr/bin/env bash
# Fixture self-test for check-memory-hygiene.sh — checks 3, 4, 5, 7 and 12 plus the empty-population
# guard. Builds a scratch git repo with conforming + violating fixtures and asserts each class fires
# (red) or stays silent (green), plus the disabled-when-blank conf contracts. Only the asserted
# checks' lines are read — the scratch repo intentionally reds others and that noise is ignored.
# Four more scratch trees at the bottom: half-migrated and young (the empty-population guard's two
# states), one carrying a .codebase-map.conf (the only place check 7's MAP_SUB branch is reachable),
# and one built by adopt-memory-tree.sh --scaffold itself, so the scaffolder is asserted against the
# GATE rather than against a second description of the scaffolder.
#   bash memory-tree/check-memory-hygiene.test.sh    # "PASS (…assertions)" + exit 0 = good
#
# The tree is FLAT (kit 1.5): builds/<slug>/, backlog/<FAMILY>.md, one root DECISIONS.md. The
# discipline is a value in the spec status header, not a directory.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/check-memory-hygiene.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
# The resolver, INLINE. This kit is copy-installed as a standalone directory, so `../lib/` does not
# exist in an adopting repo. The block below is byte-identical to tools/lib/resolve-python.sh and
# tools/lib/resolve-python.test.sh reds if any copy drifts.
#
# This file invoked `python3` BARE — the shape a ban keyed on `command -v` cannot see, which is how
# it survived the V5 migration. On a python3-only host it happened to work; on a host where the
# MS-Store stub answers for python3 it renders nothing and the young-tree arm below reds for a
# reason that has nothing to do with hygiene.
# >>> resolve_python — canonical copy: tools/lib/resolve-python.sh (byte-identical; gated)
resolve_python() {
  # Candidates in order: the caller's own published override, then $GOV_PYTHON, then the three
  # launcher names. Every candidate is ONE WORD — `py -3` cannot work here, because the probe quotes
  # the candidate and every consumer uses "$PY" as a single word (measured: exit 127).
  _rp_tried=""
  for _rp_c in "${1:-}" "${GOV_PYTHON:-}" python3 python py; do
    [ -n "$_rp_c" ] || continue
    _rp_tried="$_rp_tried $_rp_c"
    if "$_rp_c" -c "import sys" >/dev/null 2>&1; then
      printf '%s\n' "$_rp_c"
      return 0
    fi
  done
  {
    echo "resolve_python: no usable python launcher. Each candidate was RUN with -c 'import sys' and"
    echo "resolve_python: none exited 0 — being on PATH is not evidence (the Microsoft Store python3"
    echo "resolve_python: stub answers \`command -v\` and exits 9009 without running anything)."
    echo "resolve_python: tried:$_rp_tried"
    if [ -n "${1:-}" ]; then
      echo "resolve_python: the caller's override '$1' was tried FIRST and did not run."
    fi
    if [ -n "${GOV_PYTHON:-}" ]; then
      echo "resolve_python: GOV_PYTHON is set to '$GOV_PYTHON' and did not run. An override that is"
      echo "resolve_python: set and unusable is THIS failure, never a silent fall-through — the"
      echo "resolve_python: operator believes they chose, and would not have."
    fi
  } >&2
  return 1
}
# <<< resolve_python
_PY=$(resolve_python) || { echo "check-memory-hygiene.test: no usable python"; exit 2; }
cd "$TMP" || exit 2
git init -q . && git config user.email t@t.test && git config user.name t && git config core.autocrlf false
# STREAMS_CUTOFF sits between the two fixture eras: the 2026-08-01 specs are grandfathered, the
# 2026-08-10 ones must carry `streams`. That is the arm the REAL corpus cannot exercise, because the
# cutoff is deliberately set ahead of every landed spec — so it is exercised here or nowhere.
printf 'MEMORY_ROOT=memory\nDISCIPLINES="architecture"\nFAMILIES="architecture:ARCH"\nSPEC_FORMAT_CUTOFF="2026-07-15"\nSTREAMS_CUTOFF="2026-08-05"\nTOMBSTONE_ROOTS="docs"\n' > .memory-tree.conf

D=memory/builds/tFixture
mkdir -p "$D/spec/subspecs" "$D/build" memory/backlog
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
# The ten-section canon plus a post-SPEC10_CUTOFF date — the era the streams arms live in.
good10() { good | sed 's/2026-08-01/2026-08-10/g'; printf '\n## 10. Reuse audit\n\nNo existing seam fits.\n'; }

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

# ---- STREAMS (kit 1.5). The discipline moved from the PATH into the header, so these four arms are
# ---- the only place the enum is exercised: on the real corpus the cutoff is set ahead of every
# ---- landed spec, which is what keeps the migration from retroactively redding history — and what
# ---- leaves the REQUIRED arm with no data. Upstream shipped exactly this arm vacuous once.
good10 | sed 's/base 0123abcd/base 0123abcd · streams architecture/' > "$D/spec/2026-08-10-spec-tFixture-18.md"  # post-cutoff WITH streams -> silent
good10 > "$D/spec/2026-08-10-spec-tFixture-19.md"                                # post-cutoff WITHOUT streams -> red
good | sed 's/base 0123abcd/base 0123abcd · streams bogus/' > "$D/spec/2026-08-01-spec-tFixture-20.md"   # illegal value, any date -> red
good | sed 's/base 0123abcd/base 0123abcd · streams architecture/' > "$D/spec/2026-08-01-spec-tFixture-21.md"  # pre-cutoff WITH streams -> silent
printf '# t22\n\n**Status:** OPEN · rev-1 · 2026-08-10 · node a · Tier-1 · base 0123abcd\n\n## Whatever\n\nbody\n' \
  > "$D/spec/2026-08-10-spec-tFixture-22.md"                                     # TIER-1 post-cutoff, no streams -> red

# ---- CHECK 5: the optional FAMILY qualifier. It exists so one slug shared by two families survives
# ---- the merge into a single folder. The alternation is the CLOSED one from FAMILIES — a generic
# ---- [A-Z]+ would admit a family that does not exist and make the rejection arm vacuous.
printf 'x\n' > "$D/build/2026-08-01-build-ARCH-tFixture-1.md"                    # legal qualifier -> silent
printf 'x\n' > "$D/build/2026-08-01-build-XXXX-tFixture-2.md"                    # unknown family -> red

# ---- THE §9 REV RANGE, both sub-paths. The high-water scan used to run from `## 9.` to the end of
# ---- the body, so a rev-N in §10 satisfied the header rev. The branch has TWO conditions and the
# ---- range change makes BOTH newly reachable, so each gets its own fixture: one where §9 logs a
# ---- SMALLER rev, and one where §9 logs NONE at all. With only the first, an implementation that
# ---- closes the range for the maximum but leaves `seen` set below §9 passes while the masking
# ---- survives — which is the case the unit exists to fix.
good10 | sed 's/base 0123abcd/base 0123abcd · streams architecture/; s/^\*\*Status:\*\* SPECCED · rev-1/**Status:** SPECCED · rev-2/; s/^## 10\. Reuse audit$/## 10. Reuse audit\n\n- rev-99 · 2026-08-10 · a later section carrying a bigger number./' \
  > "$D/spec/2026-08-10-spec-tFixture-40.md"          # §9 logs rev-1, header rev-2, §10 has rev-99 -> RED
good10 | sed 's/base 0123abcd/base 0123abcd · streams architecture/; s/^- rev-1 · 2026-08-10 · initial draft\.$/- initial draft, with no rev token at all./; s/^## 10\. Reuse audit$/## 10. Reuse audit\n\n- rev-99 · 2026-08-10 · a later section carrying a bigger number./' \
  > "$D/spec/2026-08-10-spec-tFixture-41.md"          # §9 has NO rev token, §10 has rev-99 -> RED
good10 | sed 's/base 0123abcd/base 0123abcd · streams architecture/; s/^## 10\. Reuse audit$/## 10. Reuse audit\n\n- rev-99 · 2026-08-10 · a later section carrying a bigger number./' \
  > "$D/spec/2026-08-10-spec-tFixture-42.md"          # §9 logs rev-1, header rev-1 -> silent

# ---- CHECK 5 AT DEPTH. A recording one level deeper used to be governed by NOTHING: check 5 saw
# ---- only direct children, and check 12's population is files that already match the dated name, so
# ---- a free-named nested file was outside both by construction.
mkdir -p "$D/spec/units"
good > "$D/spec/units/2026-08-01-spec-tFixture-30-u1-nested-ok.md"   # conforming nested -> silent
printf 'x\n' > "$D/spec/units/scratch-notes.md"                      # free-named nested   -> RED
# A nested name carrying the unit tail — the shape that made the drafted grammar a red merge bar on
# 14 real files. Silent only because check 5's name ERE and check 12's selector now share one tail.
printf 'x\n' > "$D/spec/units/2026-08-01-spec-tFixture-31-u2-tail-ok.md"
mkdir -p memory/project memory/guides
# ---- CHECK 3: `project/` holds the five waiver registries and NOTHING else — no catch-all. The
# ---- `.md` on the stray is load-bearing rather than decoration: a stray `.txt`, an extensionless
# ---- file or a subdirectory already fell through to the reporting `*)` arm on the PRE-tightening
# ---- engine, so only a `.md` tells the two engines apart. These five are also the population the
# ---- selector-integrity guard measures — the half-migrated tree below is the same guard's red half.
printf '# legacy\n' > memory/project/legacy-files.txt
printf '# debt\n' > memory/project/curation-debt.txt
printf '# orphan waiver\n' > memory/project/id-orphan-waiver.txt
printf '# unresolved repo-path citations\n' > memory/project/corpus-path-unresolved.txt
printf '# unarmed branches\n' > memory/project/unarmed-branches.txt
printf '# stray\n' > memory/project/tstray.md          # a .md under project/ -> RED

# ---- CHECK 4: the folder is named for its SLUG alone. A date or FAMILY prefix is the pre-flatten
# ---- shape and must be rejected, or a half-migrated tree passes.
mkdir -p memory/builds/2026-08-01-ARCH-tBadFolder/spec
printf 'x\n' > memory/builds/2026-08-01-ARCH-tBadFolder/spec/2026-08-01-spec-tBadFolder-1.md

# ---- CHECK 3: backlog/ holds ONLY <FAMILY>.md. A stray name there is a backlog no status-vocabulary
# ---- check will ever read.
printf '# stray\n' > memory/backlog/notes.md

# ---- CHECK 7 fixture. The check had NO coverage here, and its per-file `_unfenced | awk` pair is
# ---- now one batched awk, so the exemptions and — above all — the line NUMBERING are what a
# ---- regression silently moves. The offending row sits at UNFENCED line 5 and RAW line 8; only a
# ---- counter over the unfenced stream reports 5. The 300/301 pair pins the threshold from both
# ---- sides, ASCII on purpose so bytes and characters agree on any awk build.
# ---- CHECK 1: a prompt-kind file belongs under builds/<slug>/prompts/ or archive/. The green
# ---- half is not decoration — the selector is a grep PAIR, and deleting the second grep is silent
# ---- unless something asserts that a correctly-placed prompt stays OUT of the report.
mkdir -p "$D/prompts"
printf 'x\n' > "$D/prompts/2026-08-01-prompt-tFixture-1.md"      # correctly placed -> silent
printf 'x\n' > memory/guides/kickoff-prompt.md                   # loose in the tree -> RED
# `guides/` because check 3 no longer admits a stray `.md` under `project/` — parking it there would
# make this fixture satisfy check 3 as well, and check 1's arm would no longer be its own evidence.
# `guides/` contents are unconstrained by check 3, and check 1 exempts only builds/*/prompts/ and
# archive/, so the arm still fires.

# ---- CHECK 2: link integrity, both states in ONE file. A resolver that stopped resolving anything
# ---- would still satisfy a red-only arm, so the live link is asserted absent from check 2's slice.
# ---- It moves WITH its live target: the resolving half is relative, so splitting the pair across
# ---- two directories would break the green arm for a reason that has nothing to do with check 2.
printf '# links\n\n[alive](kickoff-prompt.md)\n[dead](no-such-file.md)\n' > memory/guides/links.md

# ---- CHECK 10: a rotated archive is announced in lines 1-3 of the index it was cut from. Two
# ---- archives, one index, one mention — the referenced one is the control.
mkdir -p memory/archive
printf '# Decisions\n\nRotated: DECISIONS.2026-08-02.md\n\n- ARCH-tFixture-1 · a decision\n' > memory/DECISIONS.md
printf '# rotated\n' > memory/archive/DECISIONS.2026-08-01.md    # unreferenced   -> RED
printf '# rotated\n' > memory/archive/DECISIONS.2026-08-02.md    # named in the head -> silent

# ---- CHECK 6: the index byte/line cap. `guides/*.md` is in INDEX_SET — a guide is mandatory reading
# ---- the charter points a session at, and check 16 refuses a charter-cited file nothing caps — and
# ---- this file carries no other assertion, so growing it past 250 lines trips exactly one branch and
# ---- nothing else. It is entry-budget exempt (check 7), which the codebase-map tree below pins from
# ---- the other side: that exemption is the alternative the MAP_SUB branch used to overwrite.
{ printf '# tfixture guide\n'; i=1; while [ "$i" -le 260 ]; do printf -- '- row %d\n' "$i"; i=$((i+1)); done; } \
  > memory/guides/tfixture.md

# ---- CHECK 11: the tombstone root, set in the conf above and BLANK in the two disabled-when-blank
# ---- runs further down — which is this branch's green half.
mkdir -p docs
printf '# resurrected\n' > docs/legacy-note.md

C7L=$(printf 'x%.0s' $(seq 1 340))
{ printf '# Backlog\n'
  printf '\n```text\n%s\n```\n' "$C7L"                             # >300 inside a fence  -> silent
  printf '# %s\n' "$C7L"                                           # >300 comment line    -> silent
  printf '|%s|\n' "$(printf -- '-%.0s' $(seq 1 340))"              # >300 table separator -> silent
  printf -- '- ARCH-tFixture-1 · OPEN · %s\n' "$C7L"               # >300 entry row       -> RED at :5
  printf '%s\n' "$(printf 'z%.0s' $(seq 1 300))"                   # exactly 300          -> silent
  printf '%s\n' "$(printf 'w%.0s' $(seq 1 301))"                   # exactly 301          -> RED at :7
  # CHECK 8 rides the same file, BELOW every line the check-7 arms number by hand. Two status
  # tokens in one row -> RED at :8; the one-token row at :5 above is the green control.
  printf -- '- ARCH-tFixture-9 · OPEN · CLOSED · two status tokens in one row\n'
} > memory/backlog/ARCH.md

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

# ---- the §9 range, both sub-paths. tFixture-42 is the silent control; the other two are the two
# ---- conditions of the branch. Each names the branch's OWN message.
hit  'tFixture-40.md (header rev-2 not logged in the §9 Revision log)'
hit  'tFixture-41.md (header rev-1 not logged in the §9 Revision log)'
miss 'tFixture-42.md ('

# ---- CHECK 5 AT DEPTH, three arms. Two of them would be satisfied by ABSENCE if the selector were
# ---- left unwidened — a file that is never selected is also silent — so the legacy arm is TWO-STATE
# ---- and the red arm is attributed inside check 5's OWN output slice. Check 5 prints a bare path and
# ---- checks 2, 9 and 12 all print paths from under spec/ too, so an unattributed `hit '<path>'`
# ---- would be satisfied by the wrong check.
c5block() { awk '/^HYGIENE check 5 FAILED/{g=1} g&&/^HYGIENE check [0-9]+ FAILED/&&!/check 5 FAILED/{g=0} g' <<<"$1"; }
# ...and the same slice for any check number. Attribution is not optional: checks 1, 2, 5, 9 and 12
# all print bare paths, so an unattributed `hit '<path>'` is satisfied by the wrong check's finding.
cblock() { awk -v n="$2" '
    index($0, "HYGIENE check " n " FAILED") == 1 { g = 1 }
    g && index($0, "HYGIENE check") == 1 && index($0, "HYGIENE check " n " FAILED") != 1 { g = 0 }
    g' <<<"$1"; }
chit()  { cblock "$out" "$1" | grep -qF "$2" || { echo "FAIL check $1 did not report: $2"; st=1; }; }
cnot()  { cblock "$out" "$1" | grep -qF "$2" && { echo "FAIL check $1 reported: $2"; st=1; }; }
c5hit()  { c5block "$out" | grep -qF "$1" || { echo "FAIL check 5 did not report: $1"; st=1; }; }
c5miss() { c5block "$out" | grep -qF "$1" && { echo "FAIL check 5 reported: $1"; st=1; }; }

c5hit  "$D/spec/units/scratch-notes.md"
c5miss "$D/spec/units/2026-08-01-spec-tFixture-30-u1-nested-ok.md"
c5miss "$D/spec/units/2026-08-01-spec-tFixture-31-u2-tail-ok.md"
# the conforming-nested arm is load-bearing for the KIND derivation: the kind comes from the
# SUBFOLDER (`spec`), not from the file's immediate parent (`units`). Do not delete it as redundant.
grep -qF 'nesting is fine' <<<"$out" || { echo "FAIL the check-5 message does not say depth is allowed"; st=1; }

# ---- streams arms. Each asserts the branch's OWN text, not merely "check 12 fired": a bare
# ---- `check 12` mention is satisfied by any other finding in the same file.
miss 'tFixture-18.md ('
hit  'tFixture-19.md (filename date 2026-08-10 is on/after STREAMS_CUTOFF 2026-08-05'
hit  'tFixture-20.md (streams value(s) outside the enum: bogus'
miss 'tFixture-21.md ('
hit  'tFixture-22.md (filename date 2026-08-10 is on/after STREAMS_CUTOFF 2026-08-05'
# the legal set rides the message — a rejection that does not say what IS legal is a riddle
grep -qF 'legal values: architecture' <<<"$out" || { echo "FAIL the streams rejection does not name the legal set"; st=1; }

# ---- FAMILY qualifier + flat folder naming + backlog shard naming
hit  'HYGIENE check 5 FAILED'
hit  '2026-08-01-build-XXXX-tFixture-2.md'
miss '2026-08-01-build-ARCH-tFixture-1.md'
hit  'memory/builds/2026-08-01-ARCH-tBadFolder (bad folder name'
hit  'memory/backlog/notes.md'

# ---- BRANCH ARMS. Each of these names its branch's OWN failure text, which is what
# ---- `check-arms.py` reads to decide a branch is armed. A bare `check N` mention is not an arm:
# ---- a substring test is satisfied by any other finding that happens to carry the same number, and
# ---- an ABSENCE assertion satisfies it too. Every unarmed branch is listed in
# ---- memory/project/unarmed-branches.txt and that pin is shrink-only.
hit  'unexpected entries (structure)'
# `project/` is defined as five named registries, so a stray `.md` there is check 3's finding and
# nobody else's — attributed through the slice, because checks 1, 2, 5, 9 and 12 also print bare paths.
chit 3 'memory/project/tstray.md'
# ...and the selector-integrity guard's GREEN half, on this tree: the five registries sit at exactly
# the depth the path expression expects, so check 3's population is non-empty and the
# empty-population report must NOT name it. Silence from check 3 itself would prove nothing — a
# mis-segmented selector is silent for the same reason a clean one is.
grep -qE '^    check 3: ' <<<"$out" \
  && { echo "FAIL check 3 tripped the empty-population guard on a tree whose registries sit at the expected depth"; st=1; }
hit  'build-folder naming/shape'
hit  'prompt-kind files outside builds/*/prompts/ or archive/'
chit 1 'memory/guides/kickoff-prompt.md'
cnot 1 "$D/prompts/2026-08-01-prompt-tFixture-1.md"
hit  'broken relative .md links'
chit 2 'memory/guides/links.md -> no-such-file.md (MISSING)'
cnot 2 'links.md -> kickoff-prompt.md'
hit  'index files over cap (rotate to archive/<INDEX>.<YYYY-MM-DD>.md; a codebase-map dossier over cap is SPLIT into two dossiers instead — never rotate FOUNDATION.md, the map gate requires it)'
chit 6 'memory/guides/tfixture.md'
cnot 6 'memory/backlog/ARCH.md'
hit  'backlog/STATUS rows without exactly one status token (OPEN SPECCED INPROGRESS BLOCKED DEFERRED CLOSED WONTDO)'
chit 8 'memory/backlog/ARCH.md:8'
cnot 8 'memory/backlog/ARCH.md:5'
# check 9's green half is the freshly-scaffolded tree at the bottom of this file, which renders the
# index and then asserts the WHOLE gate exits 0. This tree never renders it, so it drifts.
hit  'generated build index differs from a fresh render'
hit  'rotated archives not referenced from their live index (lines 1-3)'
chit 10 'memory/archive/DECISIONS.2026-08-01.md'
cnot 10 'DECISIONS.2026-08-02.md'
hit  '/ is the only sanctioned memory root'
chit 11 'docs/legacy-note.md'
hit  'recording-file names not matching YYYY-MM-DD-<kind>[-<FAMILY>]-<slug>-<seq>.md (and not grandfathered)'
hit  'index entry lines over 300 chars'
hit  'spec files dated >='

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
n7=$(grep -cE '^memory/backlog/ARCH\.md:[0-9]+ \([0-9]+ chars\)$' <<<"$out")
[ "$n7" = 2 ] || { echo "FAIL check 7 emitted $n7 findings, expected exactly 2 (fence, comment and separator are exempt; the 300-byte row is under the cap)"; st=1; }
hitl 'memory/backlog/ARCH.md:7 (301 chars)'
miss 'memory/backlog/ARCH.md:6 ('
c7line=$(grep -E '^memory/backlog/ARCH\.md:[0-9]+ \([0-9]+ chars\)$' <<<"$out" | head -1)
case "$c7line" in 'memory/backlog/ARCH.md:5 ('*) ;;
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
# the empty-population guard must NOT fire in --staged mode: an empty staged set is the normal case.
grep -qF 'selected an EMPTY population' <<<"$outs" \
  && { echo "FAIL --staged tripped the empty-population guard, which is the normal staged case"; st=1; }
git reset -q && git checkout -q -- "$D/spec/2026-08-01-spec-tFixture-4.md"
# ...and the other direction: staging the index file DOES surface its own over-cap row.
printf '\n' >> memory/backlog/ARCH.md
git add memory/backlog/ARCH.md
outs7=$(bash "$SCRIPT" --staged 2>/dev/null)
grep -qF 'HYGIENE check 7' <<<"$outs7" \
  || { echo "FAIL --staged missed check 7 on the staged index file"; st=1; }
git reset -q && git checkout -q -- memory/backlog/ARCH.md

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
# 3. The §9 range CLOSES. `check-arms` cannot help here: check 12's per-spec findings are awk `print`
#    statements funnelled into one `fail 12` that is already armed, so deleting the reset moves no
#    branch, no floor and — measured — no corpus verdict. The fixtures above and this line are the
#    whole of the protection.
r9=$(awk '/in9 = 1/{f=1} f&&/else if \(in9 && L ~ \/\^## \/\) in9 = 0/{ok=1} END{print ok+0}' "$SCRIPT")
[ "$r9" = 1 ] || { echo "FAIL the §9 rev-scan range no longer closes on the next ## heading"; st=1; }
# 4. Check 7 takes NO locale prefix. `length()` decides its verdict and its character-versus-byte
#    meaning belongs to the awk build and the ambient locale; check 8's `LC_ALL=C xargs` seventeen
#    lines below sorts, it does not measure, and is not the pattern to copy here.
#    Comment lines are stripped first: the region carries prose explaining exactly this ban, and a
#    predicate that fires on the comment documenting the fix is the classic self-inflicted red.
lc7=$(awk '/^# 7 — /{f=1} /^# 8 — /{f=0} f && $0 !~ /^[[:space:]]*#/ && /LC_ALL/{print NR ": " $0}' "$SCRIPT")
[ -z "$lc7" ] || { echo "FAIL check 7 carries a locale prefix — length() must stay locale-dependent: $lc7"; st=1; }
# 5. Check 7's exemption expression keeps ONE spelling of the guides/ alternative. The MAP_SUB branch
#    used to REBUILD the whole expression, and the rebuild silently omitted `guides/` — so on any repo
#    carrying a .codebase-map.conf every guide entered the entry-budget population and no assertion
#    moved. The fixture below catches today's shape; this catches the RESHAPE that would lose it
#    again, which no fixture can, because the second spelling would still be a valid expression.
ex7asg=$(grep -nE 'ex7=' "$SCRIPT")
ex7g=$(printf '%s\n' "$ex7asg" | grep -cF '/guides/')
[ "$ex7g" = 1 ] || { echo "FAIL the ex7 exemption carries $ex7g spellings of the guides/ alternative, expected exactly 1"; st=1; }
ex7bad=$(printf '%s\n' "$ex7asg" | tail -n +2 | grep -vF '$ex7' || true)
[ -z "$ex7bad" ] || { echo "FAIL an ex7 re-assignment rebuilds the expression instead of appending to \$ex7: $ex7bad"; st=1; }

# disabled-when-blank contracts: same tree, each cutoff removed in turn.
printf 'MEMORY_ROOT=memory\nDISCIPLINES="architecture"\nFAMILIES="architecture:ARCH"\nSTREAMS_CUTOFF="2026-08-05"\n' > .memory-tree.conf
out2=$(bash "$SCRIPT" 2>/dev/null)
if grep -qF 'HYGIENE check 12' <<<"$out2"; then echo "FAIL: check 12 ran with blank SPEC_FORMAT_CUTOFF"; st=1; fi
if ! grep -qF 'HYGIENE check 12' <<<"$out"; then echo "FAIL: check 12 never fired with cutoff armed"; st=1; fi
printf 'MEMORY_ROOT=memory\nDISCIPLINES="architecture"\nFAMILIES="architecture:ARCH"\nSPEC_FORMAT_CUTOFF="2026-07-15"\n' > .memory-tree.conf
out3=$(bash "$SCRIPT" 2>/dev/null)
if grep -qF 'on/after STREAMS_CUTOFF' <<<"$out3"; then echo "FAIL: the streams requirement fired with a blank STREAMS_CUTOFF"; st=1; fi
# docs/legacy-note.md is still tracked in this run — only the conf key went away.
if grep -qF 'is the only sanctioned memory root' <<<"$out3"; then echo "FAIL: check 11 ran with a blank TOMBSTONE_ROOTS"; st=1; fi
# an ILLEGAL value is still illegal with the cutoff blank — validation and the ratchet are separate
grep -qF 'tFixture-20.md (streams value(s) outside the enum' <<<"$out3" \
  || { echo "FAIL: an illegal streams value went unchecked with a blank STREAMS_CUTOFF"; st=1; }
printf 'MEMORY_ROOT=memory\nDISCIPLINES="architecture"\nFAMILIES="architecture:ARCH"\nSPEC_FORMAT_CUTOFF="2026-07-15"\nSTREAMS_CUTOFF="2026-08-05"\n' > .memory-tree.conf

# ---- the legacy grandfather, BOTH STATES. Silence alone proves nothing here: an unwidened selector
# ---- is silent for exactly the same file. Listed -> silent; the line removed -> the same file reds.
printf '# legacy\n%s\n' "$D/spec/units/scratch-notes.md" > memory/project/legacy-files.txt
git add -A >/dev/null 2>&1; git commit -q -m legacy --no-verify
outl=$(bash "$SCRIPT" 2>/dev/null)
awk '/^HYGIENE check 5 FAILED/{g=1} g&&/^HYGIENE check [0-9]+ FAILED/&&!/check 5 FAILED/{g=0} g' <<<"$outl" \
  | grep -qF "$D/spec/units/scratch-notes.md" \
  && { echo "FAIL a legacy-listed nested file still reds check 5"; st=1; }
printf '# legacy\n' > memory/project/legacy-files.txt
git add -A >/dev/null 2>&1; git commit -q -m unlegacy --no-verify
outu=$(bash "$SCRIPT" 2>/dev/null)
awk '/^HYGIENE check 5 FAILED/{g=1} g&&/^HYGIENE check [0-9]+ FAILED/&&!/check 5 FAILED/{g=0} g' <<<"$outu" \
  | grep -qF "$D/spec/units/scratch-notes.md" \
  || { echo "FAIL removing the legacy line did not make the nested file red again"; st=1; }

# ---- the GRANDFATHER lists' stale-line guards, both of them. A list naming a path git no longer
# ---- tracks is a permanent silent exemption — the exempted file is gone, so nothing ever reds and
# ---- nothing ever says why. Each list gets a dead line AND a live one in the same run: the live one
# ---- must stay unreported, or the guard is merely "the list is non-empty".
printf '# legacy\n%s\nmemory/project/gone-forever.md\n' "$D/spec/units/scratch-notes.md" > memory/project/legacy-files.txt
printf '# debt\nmemory/backlog/ARCH.md\nmemory/project/also-gone.md\n' > memory/project/curation-debt.txt
git add -A >/dev/null 2>&1; git commit -q -m stale --no-verify
outst=$(bash "$SCRIPT" 2>/dev/null)
grep -qF 'legacy-files.txt lists paths that no longer exist (stale-line guard)' <<<"$outst" \
  || { echo "FAIL the legacy-files stale-line guard did not fire on a dead entry"; st=1; }
grep -qF 'memory/project/gone-forever.md' <<<"$outst" \
  || { echo "FAIL the legacy-files stale-line guard did not name the dead entry"; st=1; }
grep -qF 'curation-debt.txt lists paths that no longer exist (stale-line guard)' <<<"$outst" \
  || { echo "FAIL the curation-debt stale-line guard did not fire on a dead entry"; st=1; }
grep -qF 'memory/project/also-gone.md' <<<"$outst" \
  || { echo "FAIL the curation-debt stale-line guard did not name the dead entry"; st=1; }
# the LIVE debt entry is exempted, not reported: it is the over-cap arm's own file, and check 6
# branch 1 must now stay silent about it. That is the grandfather working and the guard not
# over-firing, in one assertion.
awk -v n=6 'index($0,"HYGIENE check " n " FAILED")==1{g=1} g&&index($0,"HYGIENE check")==1&&index($0,"HYGIENE check " n " FAILED")!=1{g=0} g' <<<"$outst" \
  | grep -qF 'memory/backlog/ARCH.md (' \
  && { echo "FAIL a curation-debt-listed file was still capped by check 6"; st=1; }
printf '# legacy\n' > memory/project/legacy-files.txt
printf '# debt\n' > memory/project/curation-debt.txt
git add -A >/dev/null 2>&1; git commit -q -m unstale --no-verify

# ---- the EMPTY-POPULATION guard, in two scratch trees, because it has to tell two states apart.
#
# (a) A HALF-MIGRATED tree: the files exist, at the PRE-flatten paths. Every flat selector matches
#     nothing, prints nothing, and is indistinguishable from a passing check. This is the state the
#     guard exists for, and the state a mis-segmented selector would produce on a correct tree.
H=$TMP/halfmigrated
mkdir -p "$H/memory/project" "$H/memory/architecture/project" "$H/memory/architecture/builds/2026-08-01-ARCH-tOld/spec"
( cd "$H" && git init -q . && git config user.email t@t.test && git config user.name t
  printf 'MEMORY_ROOT=memory\nDISCIPLINES="architecture"\nFAMILIES="architecture:ARCH"\nSPEC_FORMAT_CUTOFF="2026-07-15"\n' > .memory-tree.conf
  printf '# r\n' > memory/README.md
  printf '# old\n' > memory/architecture/builds/2026-08-01-ARCH-tOld/spec/2026-08-01-spec-tOld-1.md
  printf '# b\n' > memory/architecture/BACKLOG.md
  # A registry at the PRE-flatten path. It is the PRECONDITION for check 3's guard and nothing else:
  # the un-segmented count asks "does a registry exist anywhere under the memory root?" and answers
  # yes, while the flat selector `memory/project/*.txt` matches none — which is exactly the
  # mis-segmented shape the guard exists to catch, and is silent without it.
  printf '# legacy\n' > memory/architecture/project/legacy-files.txt
  git add -A && git commit -q -m half --no-verify )
outh=$(cd "$H" && bash "$SCRIPT" 2>/dev/null); rch=$?
[ "$rch" = 0 ] && { echo "FAIL a half-migrated tree exited 0 — every flat selector matched nothing and the gate was green"; st=1; }
grep -qF 'selected an EMPTY population' <<<"$outh" || { echo "FAIL no empty-population report on a half-migrated tree"; st=1; }
for c in 3 4 5 8 12; do
  grep -qE "^    check $c: " <<<"$outh" || { echo "FAIL check $c did not report its empty population on a half-migrated tree"; st=1; }
done
grep -qF 'the selector is mis-segmented' <<<"$outh" || { echo "FAIL the empty-population report does not name the cause"; st=1; }
#
# (b) A FRESHLY SCAFFOLDED tree: no builds at all, nothing mis-segmented. The guard MUST stay quiet,
#     or `adopt --scaffold` hands every new adopter a red tree on its first run. The precondition is
#     what separates this case from (a), and without this arm the guard's first draft did exactly
#     that — measured, not imagined.
Y=$TMP/young
mkdir -p "$Y/memory/project" "$Y/memory/backlog"
( cd "$Y" && git init -q . && git config user.email t@t.test && git config user.name t
  printf 'MEMORY_ROOT=memory\nDISCIPLINES="architecture"\nFAMILIES="architecture:ARCH"\nSPEC_FORMAT_CUTOFF="2026-07-15"\n' > .memory-tree.conf
  printf '# r\n' > memory/README.md
  printf '# ARCH backlog\n' > memory/backlog/ARCH.md
  # the generator reads `git ls-files`, so stage first, render, then stage the render — the same
  # order `adopt-memory-tree.sh --scaffold` uses, because this arm is standing in for its output
  git add -A && "$_PY" "$HERE/gen_build_index.py" --write >/dev/null && git add -A
  git commit -q -m young --no-verify )
outy=$(cd "$Y" && bash "$SCRIPT" 2>/dev/null); rcy=$?
grep -qF 'selected an EMPTY population' <<<"$outy" \
  && { echo "FAIL a freshly scaffolded tree tripped the empty-population guard"; st=1; }
[ "$rcy" = 0 ] || { echo "FAIL a freshly scaffolded tree is not clean (rc=$rcy):"; printf '%s\n' "$outy" | sed 's/^/      /'; st=1; }

# ---- (c) A tree carrying a .codebase-map.conf. This is the ONLY place check 7's MAP_SUB branch is
# ----     reachable: every tree above writes no such conf, so `MAP_SUB` is empty throughout and the
# ----     branch that rebuilt the exemption expression was dormant in this whole file. It went live
# ----     the day this repo adopted codebase-map, and the rebuild had dropped the `guides/`
# ----     alternative — a LOOSENING, which nothing here could have seen: every guide silently
# ----     entered the entry-budget population and the gate stayed green. Three over-cap rows, one
# ----     per exemption state, so the arm cannot be satisfied by a check 7 that reports nothing.
G=$TMP/mapped
mkdir -p "$G/memory/project" "$G/memory/guides" "$G/memory/map/features" "$G/memory/backlog"
( cd "$G" && git init -q . && git config user.email t@t.test && git config user.name t && git config core.autocrlf false
  printf 'MEMORY_ROOT=memory\nDISCIPLINES="architecture"\nFAMILIES="architecture:ARCH"\n' > .memory-tree.conf
  printf 'MAP_ROOT=memory/map\n' > .codebase-map.conf
  printf '# r\n' > memory/README.md
  printf '# ARCH backlog\n' > memory/backlog/ARCH.md
  printf '# legacy\n' > memory/project/legacy-files.txt
  L=$(printf 'x%.0s' $(seq 1 340))
  printf '# map index\n\n- %s\n' "$L" > memory/map/README.md          # NOT exempt      -> RED
  printf '# a guide\n\n- %s\n' "$L"  > memory/guides/tguide.md        # exempt (guides) -> silent
  printf '# a dossier\n\n- %s\n' "$L" > memory/map/features/tdoss.md  # exempt (map)    -> silent
  git add -A && "$_PY" "$HERE/gen_build_index.py" --write >/dev/null && git add -A
  git commit -q -m mapped --no-verify )
outm=$(cd "$G" && bash "$SCRIPT" 2>/dev/null)
cblock "$outm" 7 | grep -qF 'memory/map/README.md:' \
  || { echo "FAIL check 7 did not report the over-cap row in the map index, which carries no exemption"; st=1; }
cblock "$outm" 7 | grep -qF 'memory/guides/tguide.md' \
  && { echo "FAIL check 7 reported a guide's over-cap row — the MAP_SUB branch dropped the guides/ exemption again"; st=1; }
cblock "$outm" 7 | grep -qF 'memory/map/features/tdoss.md' \
  && { echo "FAIL check 7 reported a codebase-map dossier's over-cap row — dossiers are detail files"; st=1; }

# ---- THE SCAFFOLDER, asserted against the GATE rather than against a second description of itself.
# ---- A hand-built imitation asserts what this file BELIEVES adopt-memory-tree.sh emits, and that
# ---- belief is the copy that drifts; the young-tree arm above is exactly that, and stays as the
# ---- control. Here the real script builds the fixture. Scaffolding a shape the gate rejects and
# ---- rejecting a shape the scaffolder writes are both red bars, and only running both catches either.
# ---- Three preconditions, because the scaffolder refuses three ways before it writes anything: a
# ---- git repo, a .memory-tree.conf (absent -> it copies the example and exits 1), and NO existing
# ---- memory/ (present -> exit 0 "already scaffolded" over an unwritten tree, which would be a green
# ---- rc proving nothing).
A=$TMP/scaffolded
mkdir -p "$A"
( cd "$A" && git init -q . && git config user.email t@t.test && git config user.name t && git config core.autocrlf false
  printf 'MEMORY_ROOT=memory\nDISCIPLINES="architecture"\nFAMILIES="architecture:ARCH"\n' > .memory-tree.conf
  bash "$HERE/adopt-memory-tree.sh" --scaffold >/dev/null 2>&1
  git add -A && git commit -q -m scaffolded --no-verify ) || { echo "FAIL adopt-memory-tree.sh --scaffold did not complete"; st=1; }
# The retired session machinery: five names under project/ the gate no longer admits, so writing any
# of them would hand every new adopter a red tree on their first run. The prefix is interpolated
# rather than spelled into each entry, so this arm cannot itself be mistaken for a surviving fixture
# by a sweep looking for the old paths.
for p in MEMORY.md IN-FLIGHT.md README.md in-flight journal; do
  [ -e "$A/memory/project/$p" ] && { echo "FAIL adopt-memory-tree.sh still scaffolds memory/project/$p, which check 3 now rejects"; st=1; }
done
# ...and all FIVE registries, not two. Three of them are NAMED by gates and were created by nothing;
# "absent" and "present and empty" read identically to every consumer, which is what hid it.
for r in legacy-files.txt curation-debt.txt id-orphan-waiver.txt corpus-path-unresolved.txt unarmed-branches.txt; do
  [ -f "$A/memory/project/$r" ] || { echo "FAIL adopt-memory-tree.sh did not scaffold memory/project/$r"; st=1; }
done
outa=$(cd "$A" && bash "$SCRIPT" 2>/dev/null); rca=$?
[ "$rca" = 0 ] || { echo "FAIL a tree built by adopt-memory-tree.sh --scaffold is not hygiene-clean (rc=$rca):"; printf '%s\n' "$outa" | sed 's/^/      /'; st=1; }

# ---- the verdict, printed AFTER the last arm. Upstream printed PASS ~150 lines early and landed a
# ---- red merge bar because the head of the output said success.
[ "$st" = 0 ] && echo "PASS (120 assertions)"
exit "$st"
