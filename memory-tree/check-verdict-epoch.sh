#!/usr/bin/env bash
# check-verdict-epoch.sh — the kit version DATES the engine's verdicts, so it must move when they do.
#
#   bash tools/memory-tree/check-verdict-epoch.sh [<base>]     # default base: the mainline merge-base
#
# Exit 0 = the constant is honest for this range · 1 = the engine moved and the constant did not ·
# 2 = misconfigured.
#
# WHY. `hygiene-parity.test.sh` derives its baseline floor from the first commit introducing the
# CURRENT `KIT_MEMORY_TREE_VERSION`, on the stated ground that the constant marks when the verdicts
# last changed. Measured, that ground gave way: this repo changed check 5's selector, the §9 rev
# range and the index set across three commits while the constant sat at 1.5, so the floor pointed at
# a commit from before those changes and the parity harness accepted a baseline it could not legally
# compare against. The floor was not wrong about WHERE to look; the constant was wrong about WHEN.
#
# THE RULE IS TOPOLOGICAL, not an endpoint comparison. Let W be the NEWEST commit in `<base>..HEAD`
# that moves a behaviour-bearing line of the engine, and S the NEWEST commit in that range that
# actually CHANGES the value of `KIT_MEMORY_TREE_VERSION`. Then W must be an ancestor of, or equal
# to, S: the bump has to come at or after the last change it claims to date.
#
# WHY NOT THE ENDPOINTS. The first cut compared the constant at the two ends of the range, and that
# is satisfied by a bump ANYWHERE in it — so a bump in commit 2 excused every verdict change in
# commits 3..n. Reproduced: base(1.5) -> "bump + change"(1.6) -> "later change, no bump" read clean.
#
# WHY NOT PER-COMMIT. Measured on this repo's own history: 129 commits, 22 of which move a
# behaviour-bearing line of the engine or its delegates, against 7 bumps that actually happened. A
# per-commit rule would demand 22 — three times the churn — and a constant that increments on a fifth
# of all commits stops meaning "the verdict epoch" and starts meaning "someone edited the file".
# The topological rule asks for ONE bump per range, correctly placed. That is the same shape
# `skills/session-kickoff/manifest-check.sh` check 5 already uses for its `last-audit` re-stamp, and
# it is here because that rule is proven rather than because it is new.
#
# S IS VALIDATED, NOT MATCHED. A commit that touches the constant's LINE without changing its VALUE —
# a comment reflow, a marker edit — is not a bump. Each candidate is confirmed by parsing the value
# at the commit and at its parent, which is the same structural check manifest-check applies to its
# own stamp, and for the same reason: a decoy edit must not be able to launder a change.
#
# IT OVER-COUNTS, DELIBERATELY. A rename or a whitespace-only refactor changes no verdict and still
# demands a bump. That is the safe direction: the cost is three lines and a `--render`, and the
# alternative — deciding from a diff whether a verdict moved — is the judgement call that produced
# the stale constant in the first place. A line whose first non-space character is `#` cannot change
# what `sh` or `awk` does, so the exemption cannot hide a behaviour change.
set -u
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "verdict-epoch: not a git repo"; exit 2; }
cd "$ROOT" || exit 2

# THE ENGINE IS NOT ONE FILE. Checks 9 and 13-19 delegate to sibling Python modules, so 8 of the 19
# verdicts live outside the shell script — a change to `gotchas.py`'s classifier moves what the gate
# SAYS exactly as surely as a change to check 5's selector. The first cut diffed only the shell file
# and would have let all of them drift under a still constant.
#
# AND THE CHAIN IS TWO HOPS, not one. `corpus_ids.py` is listed, but it deliberately declares no
# grammar of its own (`corpus_ids.py:12`): `grammar()` returns `extract.grammar_for(root)`, so the
# regex that decides checks 13-16's verdicts lives one file further out, in the memory-recall kit.
# Measured on the commit that widened it: the session era went `\d+` to `\d+[a-z]*`, check 14's
# answer went 5 orphans to 9, and this gate printed `clean` with the constant untouched — the same
# defect TOOL-aBatchedTribunal-6o closed for the three modules below, one hop short. A kit an adopter
# has not installed is skipped by the `[ -f ]` guard, so listing it costs a non-adopter nothing.
#
# AND `merge-rows.py` IS IN THE SET, which is the same one-hop-short shape found a third time. The
# merge driver ships in this kit and the constant DATES the kit's verdicts; a redesign of what the
# driver does with three blobs moves a kit verdict exactly as surely as a change to check 5's
# selector, and nothing forced a bump. Measured before it was added: the driver's whole merge
# algorithm was replaced and this gate printed `clean` with the constant untouched. The driver is
# not a check — its "verdict" is the file it writes — and that is the reason it belongs here rather
# than an argument against it: an adopter reading `memory-tree@2.0` is being told which merge
# semantics their indexes were merged under.
ENGINE=tools/memory-tree/check-memory-hygiene.sh
DELEGATES="tools/memory-tree/gen_build_index.py tools/memory-tree/corpus_ids.py tools/memory-tree/gotchas.py tools/memory-recall/extract.py tools/memory-tree/merge-rows.py"
[ -f "$ENGINE" ] || { echo "verdict-epoch: $ENGINE is missing — this gate reads the engine's own source"; exit 2; }
SCAN="$ENGINE"
for _d in $DELEGATES; do [ -f "$_d" ] && SCAN="$SCAN $_d"; done

BASE="${1:-}"
if [ -z "$BASE" ]; then
  DEF="${GOV_DEFAULT_BRANCH:-main}"
  BASE=$(git merge-base "origin/$DEF" HEAD 2>/dev/null || git merge-base "$DEF" HEAD 2>/dev/null || true)
fi
# No resolvable base — a shallow clone, a fresh init, a detached probe. SKIP LOUDLY: silence here
# would be indistinguishable from "the constant is fine", which is the failure this gate exists for.
if [ -z "$BASE" ]; then
  echo "verdict-epoch: FAILED — no mainline base to compare against, so this gate cannot judge"
  echo "verdict-epoch: anything. A shallow clone or a differently-named default branch does that."
  echo "verdict-epoch: Fetch full history (CI: fetch-depth: 0), or set GOV_DEFAULT_BRANCH."
  echo "verdict-epoch: This exits 1 on purpose: run-gates judges a leg by its exit code, so a"
  echo "verdict-epoch: zero-status skip would be indistinguishable from a pass, forever."
  exit 1
fi
git cat-file -e "$BASE^{commit}" 2>/dev/null || { echo "verdict-epoch: base '$BASE' is not a commit in this repo"; exit 2; }

# Behaviour-bearing added/removed lines in ONE commit. `-U0` so context lines cannot be mistaken for
# changes; the `+++`/`---` headers are dropped. A merge commit prints nothing here, which is right:
# a merge introduces no line its parents did not already carry.
behav_in() {  # $1=commit · $2=pathspec (default: the whole scan set) -> count
  git diff-tree -U0 --no-commit-id -r -p "$1" -- ${2:-$SCAN} 2>/dev/null \
    | grep -E '^[+-]' | grep -vE '^(\+\+\+|---)' | sed 's/^.//' \
    | grep -vE '^[[:space:]]*(#|$)' | grep -c . || true
}
# WHICH of the scanned files moved. The failure used to name only a sha, and the scan set is now four
# files across TWO kits: "$W moved 3 lines" leaves the reader to diff the commit themselves to learn
# whether the engine, a delegate or the shared grammar was what moved. One `behav_in` per scanned
# file, and only on the failure path, so the clean path costs nothing.
moved_files() {  # $1=commit -> space-separated paths
  local f out=""
  for f in $SCAN; do [ "$(behav_in "$1" "$f")" -gt 0 ] && out="$out $f"; done
  printf '%s' "${out# }"
}
verat() {  # $1=rev -> the constant's value at that rev ("" if absent/unparseable)
  git show "$1:$ENGINE" 2>/dev/null | sed -n 's/^KIT_MEMORY_TREE_VERSION=\([0-9.]*\).*/\1/p' | head -1
}

now=$(verat HEAD)
was=$(verat "$BASE")
[ -n "$now" ] || { echo "verdict-epoch: cannot read KIT_MEMORY_TREE_VERSION from $ENGINE at HEAD"; exit 2; }
# An UNREADABLE old constant is not "it changed". The comparison below only fires when `was` is
# non-empty, so a reader that stopped matching would silently excuse every future change — the
# fail-open direction, in the gate whose whole job is to notice a constant that stopped being true.
# `was` is legitimately empty only when the base PREDATES the constant, and git can be asked which.
if [ -z "$was" ] && git show "$BASE:$ENGINE" 2>/dev/null | grep -q 'KIT_MEMORY_TREE_VERSION'; then
  echo "verdict-epoch: FAILED — $ENGINE at $BASE carries KIT_MEMORY_TREE_VERSION but this gate could"
  echo "verdict-epoch: not parse it, so the comparison below would pass without comparing anything."
  echo "verdict-epoch: Fix the constant's format (want 'KIT_MEMORY_TREE_VERSION=<X.Y>') or the reader."
  exit 2
fi

# W — the NEWEST commit in the range that moves a behaviour-bearing line. Walked newest-first rather
# than taken from `rev-list -1`, because the newest commit TOUCHING the engine may have moved only
# comments, and a comment is not a verdict.
W=""; moved=0
while IFS= read -r c; do
  [ -n "$c" ] || continue
  n=$(behav_in "$c")
  if [ "$n" -gt 0 ]; then W="$c"; moved=$n; break; fi
done <<EOF
$(git rev-list "$BASE"..HEAD -- $SCAN 2>/dev/null)
EOF

if [ -z "$W" ]; then
  echo "verdict-epoch: clean — no behaviour-bearing engine line moved since ${BASE} (version $now; scanned $SCAN)"
  exit 0
fi

# S — the NEWEST commit in the range that actually CHANGES the constant's value. Candidates come from
# a `-G` search: `-S` counts OCCURRENCES of a string, and `KIT_MEMORY_TREE_VERSION=` occurs exactly
# once before and once after a bump, so the count never moves and the bump is never reported —
# measured, the first cut found no bump at all. `-G` matches changed LINES, which is what a bump is;
# manifest-check.sh uses -G on its own stamp for exactly this reason. Each candidate is then
# VALIDATED against its parent: a commit that reflows the
# comment on that line, or re-types the same number, touches it without dating anything.
S=""
while IFS= read -r cand; do
  [ -n "$cand" ] || continue
  cur=$(verat "$cand")
  prev=$(verat "$cand^")
  if [ -n "$cur" ] && [ "$cur" != "$prev" ]; then S="$cand"; break; fi
done <<EOF
$(git log --format=%H -G'^KIT_MEMORY_TREE_VERSION=' "$BASE"..HEAD -- "$ENGINE" 2>/dev/null)
EOF

remedy() {
  echo "verdict-epoch: Bump it in ALL THREE places, which must move together, in a commit at or after"
  echo "verdict-epoch: ${W}:"
  echo "verdict-epoch:   $ENGINE (the constant AND the gov:kit marker on that same line)"
  echo "verdict-epoch:   tools/memory-tree/HYGIENE.template.md (line 1)"
  echo "verdict-epoch:   memory/HYGIENE.md (line 1) — then: bash tools/memory-tree/kit-dogfood-parity.test.sh --render"
}

if [ -z "$S" ]; then
  echo "verdict-epoch: FAILED — $moved behaviour-bearing line(s) of the engine moved in $W, and NO"
  echo "verdict-epoch: commit in ${BASE}..HEAD changes KIT_MEMORY_TREE_VERSION (still $now)."
  echo "verdict-epoch:   moved: $(moved_files "$W")"
  echo "verdict-epoch: The constant is what dates the engine's verdicts — hygiene-parity.test.sh"
  echo "verdict-epoch: derives its baseline floor from it — so leaving it makes that floor point at a"
  echo "verdict-epoch: commit from before this change."
  remedy
  exit 1
fi

if ! git merge-base --is-ancestor "$W" "$S" 2>/dev/null; then
  echo "verdict-epoch: FAILED — the bump is OLDER than the change it claims to date."
  echo "verdict-epoch:   last behaviour-bearing engine change: $W ($moved line(s))"
  echo "verdict-epoch:   moved: $(moved_files "$W")"
  echo "verdict-epoch:   last KIT_MEMORY_TREE_VERSION change:  $S"
  echo "verdict-epoch: A bump anywhere in the range used to satisfy this gate, so one early bump"
  echo "verdict-epoch: excused every verdict change after it. The bump has to come at or after the"
  echo "verdict-epoch: last change, or the floor it feeds still points before that change."
  remedy
  exit 1
fi
echo "verdict-epoch: clean — $moved line(s) moved in $W and the version moved ${was:-<absent>} -> $now in $S"
