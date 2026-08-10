#!/usr/bin/env bash
# Structured-memory-tree hygiene gate — the mechanized form of <MEMORY_ROOT>/HYGIENE.md.
# Config-driven (.memory-tree.conf: MEMORY_ROOT, DISCIPLINES, FAMILIES, TOMBSTONE_ROOTS,
# SPEC_FORMAT_CUTOFF). Single source
# of truth: HYGIENE.md's "Check" section, CI, the pre-commit hook, and the local gate runner all invoke
# THIS script — never hand-copy the checks. Part of the coding-governance memory-tree kit.
#
#   memory-tree/check-memory-hygiene.sh            # full check
#   memory-tree/check-memory-hygiene.sh --staged   # pre-commit fast leg (set-checks tree-wide, file-checks on staged paths)
#
# Exit 0 + no output = clean. Anything printed is a hygiene regression.
set -u
KIT_MEMORY_TREE_VERSION=2.2   # gov:kit memory-tree@2.2 — engine identity; set HERE, never from .memory-tree.conf (a project conf must not spoof it)
ROOT="$(git rev-parse --show-toplevel)" || exit 2
cd "$ROOT" || exit 2
MEMORY_ROOT=memory
# DISCIPLINES is a CLOSED ENUM of stream values, not a directory list. Since 1.5 the tree is FLAT:
# every build lives at <MEMORY_ROOT>/builds/<slug>/ and the discipline is declared in each spec's
# status header as `streams <value>[+<value>]`. FAMILIES maps an enum value to its id prefix, its
# backlog shard, and the optional FAMILY qualifier in a recording filename.
DISCIPLINES="architecture deployment blocks design performance"
FAMILIES="architecture:ARCH deployment:DEPLOY blocks:BLOCK design:DES performance:PERF"
TOMBSTONE_ROOTS=""     # old tree root(s) a migrated project must keep empty (e.g. "docs"); blank = skip check 11
SPEC_FORMAT_CUTOFF=""  # date; specs whose filename date >= this must follow TEMPLATE-SPEC.md (check 12); blank = skip
STREAMS_CUTOFF=""      # date; specs whose filename date >= this MUST carry `· streams <value>` (check 12); blank = never required
[ -f "$ROOT/.memory-tree.conf" ] && . "$ROOT/.memory-tree.conf"
M="$MEMORY_ROOT"
HERE="$(cd "$(dirname "$0")" && pwd)"
# codebase-map kit interop: when its MAP_ROOT is a DIRECT child of this tree (e.g. memory/map),
# carve that subtree into the structure lint + index caps below (prose files only; the map's
# coverage/freshness gates are its own test file, not this script).
MAP_SUB=""
if [ -f "$ROOT/.codebase-map.conf" ]; then
  _cbm_root=$(. "$ROOT/.codebase-map.conf" 2>/dev/null; printf '%s' "${MAP_ROOT:-}" | tr -d '\r')
  _cbm_root="${_cbm_root%/}"   # trailing slash would mis-read a direct child as nested
  case "$_cbm_root" in "$M"/*) _s="${_cbm_root#"$M"/}"; case "$_s" in */*) ;; *) MAP_SUB="$_s";; esac;; esac
fi
STAGED=0; [ "${1:-}" = "--staged" ] && STAGED=1

status=0
FILES=$(git ls-files "$M/")

# --- PRINT MODES: this script OWNS two sets that a sibling gate needs, and a transcription of
# --- either is the drift class the kit exists to remove. `corpus_ids.py` ASKS instead of copying.
# --- The dependency runs ONE WAY: these return before check 1, so nothing recurses back here.
# --- The append-only set is check 2's exemption; the index set is check 6's byte-capped population.
APPEND_ONLY_ERE="^$M/(DECISIONS\.md$|decisions/|archive/)"
case "${1:-}" in
  --print-append-only-ere) printf '%s\n' "$APPEND_ONLY_ERE"; exit 0 ;;
esac
LEGACY=$(grep -vE '^\s*(#|$)' "$M/project/legacy-files.txt" 2>/dev/null || true)
DEBT=$(grep -vE '^\s*(#|$)' "$M/project/curation-debt.txt" 2>/dev/null || true)
# Membership via associative arrays, NOT `grep -qxF <<<"$LIST"` — the here-string forks a grep per
# call, and these run once per scanned file (minutes on a large adopter tree; a fork is ~50-100ms
# under MSYS/Windows). Exact-key lookup is semantically identical (fixed string, whole line) and
# costs zero processes. (Upstream: inCMS ARCH-aFencedNamespace-3.)
declare -A LEGACY_SET DEBT_SET
while IFS= read -r _l; do [ -n "$_l" ] && LEGACY_SET["$_l"]=1; done <<<"$LEGACY"
while IFS= read -r _l; do [ -n "$_l" ] && DEBT_SET["$_l"]=1; done <<<"$DEBT"
in_legacy() { [ -n "${LEGACY_SET[$1]+x}" ]; }
in_debt()   { [ -n "${DEBT_SET[$1]+x}" ]; }
fail() { echo "HYGIENE check $1 FAILED — $2"; status=1; }

# The resolver, INLINE. This kit is copy-installed as a standalone directory, so `../lib/` does
# not exist in an adopting repo. The block below is byte-identical to tools/lib/resolve-python.sh
# and tools/lib/resolve-python.test.sh reds if any copy drifts.
# Resolved ONCE for all three delegating checks (9, 13-16, 17-19) — the retired idiom sat at
# three separate sites in this file, which is three chances to fix two of them.
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
_PY=$(resolve_python) || { echo "HYGIENE — no usable python; checks 9 and 13-19 delegate to sibling modules"; exit 2; }
FAMILY_of() { local p; for p in $FAMILIES; do case "$p" in "$1:"*) echo "${p#*:}"; return;; esac; done; }
FAM_ALT=$(for p in $FAMILIES; do echo "${p#*:}"; done | paste -sd'|' -)   # ARCH|DEPLOY|... for regexes
DISC_ALT=$(printf '%s\n' $DISCIPLINES | paste -sd'|' -)                   # the streams enum, for check 12
# THE recording-name tail, in ONE place. A multi-unit build names its sub-specs
# `<date>-spec-<slug>-<seq>-u6-indexed-join.md`, and both check 5's name grammar and check 12's
# selector have to admit that suffix. They were two hand-copied EREs for one grammar and they had
# already diverged — check 12 carried the tail, check 5 did not — so widening check 5's SELECTOR
# without this would have redded 14 conforming files. Interpolated by both; never retyped.
REC_TAIL='(-[a-z0-9][a-z0-9-]*)?'

# A selector that matches NOTHING prints nothing, and nothing is what a passing check prints. The
# 1.5 flatten changed the segment count of several path selectors at once, so each one asserts its
# population is non-empty — but ONLY when the tree demonstrably holds files of that kind. A freshly
# scaffolded repo with no builds yet is a legitimate empty, not a disarmed gate, and a guard that
# cannot tell those apart makes `adopt --scaffold` produce a red tree.
#
# So the guard compares TWO granularities: the PRECONDITION asks "does a file of this kind exist
# anywhere under the memory root?" and the POPULATION asks "does one exist at the exact path this
# check expects?". Equal-and-zero is a young tree. Precondition non-zero with an empty population is
# a mis-segmented selector — the only shape that silently disarms a check — and that is what reds.
# `--staged` is exempt throughout: an empty staged set is the normal case.
POP_MISSING=""
pop_guard() { # check-number · label · population-count · precondition-count
  [ "$STAGED" = 1 ] && return 0
  [ "${3:-0}" -gt 0 ] && return 0
  [ "${4:-0}" -gt 0 ] || return 0
  POP_MISSING="${POP_MISSING}    check $1: $2 (but $4 file(s) of that kind exist elsewhere under $M/ — the selector is mis-segmented)"$'\n'
}
# Preconditions, deliberately un-segmented: they ask what KIND of file exists, never where.
PRE_ANYBUILD=$(printf '%s\n' "$FILES" | grep -cE "/builds/" || true)
PRE_RECORD=$(printf '%s\n' "$FILES" | grep -cE "/builds/.+/.+\.md$" || true)
PRE_SPEC=$(printf '%s\n' "$FILES" | grep -cE "/[0-9]{4}-[0-9]{2}-[0-9]{2}-spec-[^/]*\.md$" || true)
PRE_STATUSY=$(printf '%s\n' "$FILES" | grep -cE "(/STATUS\.md$|/BACKLOG\.md$|^$M/backlog/)" || true)
# CR-stripped + marker-matched fences: only the marker that OPENED a fence closes it (a ~~~ line
# inside a ``` fence is content, not a toggle), and \r is dropped so CRLF worktrees (autocrlf
# smudge read by WSL/Linux bash) compare equal to LF sources.
_unfenced() { awk '
  { sub(/\r$/, "") }
  /^[[:space:]]*(```|~~~)/ {
    m = ($0 ~ /^[[:space:]]*```/) ? "```" : "~~~"
    if (f == "") { f = m; next }
    if (m == f) { f = ""; next }
  }
  f == ""' "$1"; }

declare -A STAGED_SET
if [ "$STAGED" = 1 ]; then
  STAGED_MD=$(git diff --cached --name-only --diff-filter=ACMR -- "$M/**" | LC_ALL=C sort)
  while IFS= read -r _l; do [ -n "$_l" ] && STAGED_SET["$_l"]=1; done <<<"$STAGED_MD"
fi
in_scope() { [ "$STAGED" = 0 ] && return 0; [ -n "${STAGED_SET[$1]+x}" ]; }   # zero-fork (see LEGACY_SET)

# 1 — prompt placement: prompt-kind files only under builds/*/prompts/ or archive/.
c1=$(printf '%s\n' "$FILES" \
  | grep -E '(\.prompt\.md|\.build-prompt\.md|-prompt\.md|/[0-9]{4}-[0-9]{2}-[0-9]{2}-prompt-[A-Za-z0-9-]+-[0-9]+\.md)$' \
  | grep -vE '/(builds/[^/]+/prompts/|archive/)' || true)
[ -n "$c1" ] && fail 1 "prompt-kind files outside builds/*/prompts/ or archive/:
$c1"

# 2 — link integrity (exempt DECISIONS.md / decisions/ / archive/ and legacy-listed recording files).
# LIVE.md and the ledger shards are NOT exempt: their rows link to build READMEs, and a link that
# stops resolving is precisely the drift the generated index exists to prevent.
scan2=$(printf '%s\n' "$FILES" | grep -E '\.md$' | grep -vE '/(DECISIONS\.md$|decisions/|archive/)')
[ "$STAGED" = 1 ] && scan2=$(printf '%s\n' "$scan2" | { grep -xF -f <(printf '%s\n' "$STAGED_MD") || true; })
# Drop grandfathered files first (fork-free), then extract every candidate link in ONE awk pass over
# all remaining files — was `_unfenced | grep -oE | sed -E` PER FILE (3 forks × N files; the single
# biggest cost on a large adopter tree — upstream inCMS ARCH-aFencedNamespace-3). The awk inlines
# _unfenced's exact semantics (CR strip + marker-matched fences, state reset per file) and the
# grep+sed link shape INCLUDING the sed fall-through (an anchor-only `](#x.md)` stays as-is).
scan2f=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  in_legacy "$f" && continue
  scan2f+="$f"$'\n'
done <<<"$scan2"
broken=$(awk '
  { f = $0; if (f == "") next
    fence = ""
    while ((getline line < f) > 0) {
      sub(/\r$/, "", line)
      if (line ~ /^[[:space:]]*(```|~~~)/) {
        m = (line ~ /^[[:space:]]*```/) ? "```" : "~~~"
        if (fence == "") { fence = m; continue }
        if (m == fence) { fence = ""; continue }
      }
      if (fence != "") continue
      while (match(line, /\]\([^)]+\.md[^)]*\)/)) {
        mm   = substr(line, RSTART, RLENGTH)
        rest = substr(line, RSTART + RLENGTH)
        t = mm
        if (match(t, /^\]\([^)#]+/)) t = substr(t, 3, RLENGTH - 2)
        print f "\t" t
        line = rest
      }
    }
    close(f)
  }' <<<"$scan2f" | while IFS=$'\t' read -r f t; do
    case "$t" in http*|/*) continue;; esac
    d=${f%/*}                   # fork-free dirname — every path here starts "$M/", so it has a /
    [ -f "$d/$t" ] || echo "$f -> $t (MISSING)"
  done)
[ -n "$broken" ] && fail 2 "broken relative .md links:
$broken"

# 3 — structure lint (depth-2; decisions/ guides/ archive/ contents opaque).
# FLAT (1.5): the root holds the four index files, one append-only DECISIONS.md, and the fixed
# directory set. There is no discipline directory to descend into; `builds/` holds one folder per
# slug and `backlog/` holds one shard per FAMILY.
root1=$(printf '%s\n' "$FILES" | awk -F/ '{ if (NF==2) print "F:"$2; else print "D:"$2 }' | LC_ALL=C sort -u)
bad3=$(printf '%s\n' "$root1" | grep . | while IFS= read -r e; do case "$e" in
  F:README.md|F:HYGIENE.md|F:TEMPLATE-SPEC.md|F:DECISIONS.md|F:LIVE.md) ;;
  D:project|D:builds|D:backlog|D:decisions|D:guides|D:archive|D:ledger|D:gotchas) ;;
  D:*) d="${e#D:}"; [ "$d" = "$MAP_SUB" ] || echo "$M/$d";;
  *) echo "$M/${e#*:}";; esac; done)
# backlog/ holds ONLY <FAMILY>.md, one shard per declared family — a stray name there is a backlog
# nobody's status-vocabulary check will ever read.
b3b=$(printf '%s\n' "$FILES" | grep -E "^$M/backlog/" | awk -F/ -v m="$M" -v fam="$FAM_ALT" '
  { if (NF != 3) { print m "/backlog/" $3 " (nested)"; next }
    if ($3 !~ "^(" fam ")\\.md$") print m "/backlog/" $3 }' | LC_ALL=C sort -u)
# builds/ holds ONLY directories.
b3c=$(printf '%s\n' "$FILES" | grep -E "^$M/builds/" | awk -F/ -v m="$M" '
  NF == 3 { print m "/builds/" $3 " (file at the builds root — a build is a FOLDER)" }' | LC_ALL=C sort -u)
bad3=$(printf '%s\n%s\n%s\n' "$bad3" "$b3b" "$b3c")
# project/ holds the gate's OWN waiver registries and nothing else (aMendedLedger U3). The session
# machinery it used to also hold — MEMORY.md, IN-FLIGHT.md, in-flight/, journal/, project/README.md —
# is retired, and the `F:*.md` catch-all goes with it: a directory defined as five named files cannot
# also admit any `.md` anyone drops in. Nothing scaffolds those names any more either, so an
# admitted-but-never-written entry would be a third answer to a question this list is closing.
p1=$(printf '%s\n' "$FILES" | grep "^$M/project/" | awk -F/ '{ if (NF==3) print "F:"$3; else print "D:"$3 }' | LC_ALL=C sort -u)
# The precondition is deliberately UN-SEGMENTED (see pop_guard): `project/` is drained of session
# machinery, not emptied — the five registries stay — so the population is 5 on a real tree and 0
# only when the path expression is mis-segmented, which is the one shape that silently disarms this
# sub-lint. A tree with no `.txt` anywhere is a young tree and stays silent.
PRE_REGISTRY=$(printf '%s\n' "$FILES" | grep -cE '\.txt$')
pop_guard 3 "no registry under $M/project/" \
  "$(printf '%s\n' "$FILES" | grep -cE "^$M/project/[^/]+\.txt$")" "$PRE_REGISTRY"
bp=$(printf '%s\n' "$p1" | grep . | while IFS= read -r e; do case "$e" in
  F:legacy-files.txt|F:curation-debt.txt) ;;
  F:id-orphan-waiver.txt|F:corpus-path-unresolved.txt|F:unarmed-branches.txt) ;;
  *) echo "$M/project/${e#*:}";; esac; done)
bm=""
if [ -n "$MAP_SUB" ]; then
  m1=$(printf '%s\n' "$FILES" | grep "^$M/$MAP_SUB/" | awk -F/ '{ if (NF==3) print "F:"$3; else print "D:"$3 }' | LC_ALL=C sort -u)
  bm=$(printf '%s\n' "$m1" | grep . | while IFS= read -r e; do case "$e" in
    F:README.md|F:FOUNDATION.md|F:baseline.toml|F:affordance-exempt.toml|D:features|D:generated) ;;
    *) echo "$M/$MAP_SUB/${e#*:}";; esac; done)
fi
bad3=$(printf '%s\n%s\n%s\n' "$bad3" "$bp" "$bm" | grep . || true)
[ -n "$bad3" ] && fail 3 "unexpected entries (structure):
$bad3"

# 4 — build-folder naming + internal shape.
# FLAT (1.5): ONE population, `<M>/builds/<slug>/`. The date prefix and the FAMILY prefix are gone
# with the discipline directory — a folder is named for its slug and nothing else, so there is no
# FAMILY↔discipline pairing left to assert here. A recording filename MAY carry a FAMILY qualifier
# (`<date>-<kind>-<FAMILY>-<slug>-<seq>.md`), which is how one slug shared by two families survives
# the merge into a single folder; the alternation is the CLOSED one from FAMILIES, never `[A-Z]+`.
BUILD_N=$(printf '%s\n' "$FILES" | awk -F/ -v m="$M" '$0 ~ "^" m "/builds/" && NF > 3 { print $3 }' | LC_ALL=C sort -u | grep -c .)
pop_guard 4 "no build folder under $M/builds/" "$BUILD_N" "$PRE_ANYBUILD"
bad4=$(printf '%s\n' "$FILES" | grep -E "^$M/builds/[^/]+/" \
  | LC_ALL=C awk -F/ -v m="$M" -v famalt="$FAM_ALT" '
      BEGIN {
        n_m = split(m, _seg, "/"); fidx = n_m + 2    # <m>/builds/<folder>
        vre = "^[A-Za-z][A-Za-z0-9-]*$"              # the slug, alone
        rre = "^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-(prompt|spec|build|review)-((" famalt ")-)?[A-Za-z0-9]+-[0-9]+\\.md$"
      }
      function flush(   n,i,j,k,keys,tmp,type,name) {
        if (folder=="") return
        if (folder !~ vre) {
          print m "/builds/" folder " (bad folder name — expected the slug alone, no date and no FAMILY prefix)"
          folder=""; delete ent; return }
        n=0; for (k in ent) keys[++n]=k
        for (i=2;i<=n;i++){ tmp=keys[i]; j=i-1; while(j>=1 && keys[j]>tmp){keys[j+1]=keys[j];j--} keys[j+1]=tmp }
        for (i=1;i<=n;i++){ k=keys[i]; type=substr(k,1,1); name=substr(k,3)
          if (k=="F:README.md"||k=="F:STATUS.md"||k=="D:prompts"||k=="D:spec"||k=="D:build"||k=="D:reviews") continue
          if (type=="F"){ if (name !~ rre) print m "/builds/" folder "/" name }
          else print m "/builds/" folder "/" name }
        folder=""; delete ent
      }
      { if ($fidx!=folder){ flush(); folder=$fidx }
        if (NF==fidx+1) ent["F:" $(fidx+1)]=1; else ent["D:" $(fidx+1)]=1 }
      END { flush() }')
bad4=$(printf '%s\n' "$bad4" | grep . || true)
[ -n "$bad4" ] && fail 4 "build-folder naming/shape:
$bad4"


# 5 — recording-file naming (grandfather: legacy-files.txt).
# The optional `-<FAMILY>-` qualifier is the CLOSED alternation from FAMILIES. A generic `[A-Z]+`
# would admit a family that does not exist and make the rejection arm vacuous.
# ANY DEPTH under the four subfolders. A file one level deeper used to be governed by nothing: check
# 5 saw only direct children, and check 12's population is files that already match the dated name,
# so a free-named nested file was outside both by construction.
c5_sel=$(printf '%s\n' "$FILES" | grep -E "^$M/builds/[^/]+/(prompts|spec|build|reviews)/(.+/)?[^/]+\.md$" || true)
pop_guard 5 "no recording file under $M/builds/*/{prompts,spec,build,reviews}/" \
  "$(printf '%s\n' "$c5_sel" | grep -c . || true)" "$PRE_RECORD"
bad5=$(printf '%s\n' "$c5_sel" | grep . | while IFS= read -r f; do
  in_legacy "$f" && continue
  # Fork-free basename + SUBFOLDER extraction (was basename + awk + grep = 3 forks per recording file).
  # The kind comes from the subfolder — the first segment after the build slug — NOT from the file's
  # immediate parent: `spec/units/x.md` is a spec, and `units` is not a kind.
  base=${f##*/}; rest=${f#"$M"/builds/}; rest=${rest#*/}; sub=${rest%%/*}
  case "$sub" in prompts) kind=prompt;; spec) kind=spec;; build) kind=build;; reviews) kind=review;; esac
  [[ $base =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}-$kind-(($FAM_ALT)-)?[A-Za-z0-9]+-[0-9]+$REC_TAIL\.md$ ]] || echo "$f"
done)
# The DEPTH is not the problem, and the message says so on a CONTINUATION line — the first line is
# this branch's check-arms signature and its arm sits exactly at the armed floor with no slack.
[ -n "$bad5" ] && fail 5 "recording-file names not matching YYYY-MM-DD-<kind>[-<FAMILY>]-<slug>-<seq>.md (and not grandfathered):
  (nesting is fine — a sub-folder under spec/ groups a multi-unit build; the NAME is what is wrong)
$bad5"

# index set for checks 6/7
index_set() {
  { echo "$M/README.md"; echo "$M/LIVE.md"; echo "$M/DECISIONS.md"
    printf '%s
' "$FILES" | grep -E "^$M/ledger/[^/]+\.md$"
    if [ -n "$MAP_SUB" ]; then
      echo "$M/$MAP_SUB/README.md"; echo "$M/$MAP_SUB/FOUNDATION.md"
      printf '%s\n' "$FILES" | grep -E "^$M/$MAP_SUB/features/[^/]+\.md$"   # dossiers: size caps, entry-budget exempt
    fi
    printf '%s\n' "$FILES" | grep -E "^$M/backlog/[^/]+\.md$"
    printf '%s\n' "$FILES" | grep -E "^$M/builds/[^/]+/STATUS\.md$"
    # A GUIDE is mandatory reading — the charter points a session at it — so it carries the same
    # byte/line cap as an index. Check 16 says the same thing from the other side: a charter-cited
    # file under no cap is a read budget nobody watches. Entry-budget exempt: a guide is prose.
    printf '%s\n' "$FILES" | grep -E "^$M/guides/[^/]+\.md$"
  } | while IFS= read -r f; do [ -f "$f" ] && echo "$f"; done
}
INDEX_SET=$(index_set)   # compute ONCE; checks 6 and 7 both read it (was recomputed per check)
case "${1:-}" in --print-index-set) printf '%s\n' "$INDEX_SET"; exit 0 ;; esac   # see the PRINT MODES note above

# 6 — index size caps (grandfather: curation-debt.txt).
# Batched wc: one `wc -c` + one `wc -l` over the whole selected set (was 2 forks PER index file).
# Findings emit in index_set order (the -l stream's arg order); multi-file wc `total` lines are
# skipped by name; `+0` coerces the counts.
sel6=$(printf '%s\n' "$INDEX_SET" | while IFS= read -r f; do in_debt "$f" && continue; in_scope "$f" || continue; printf '%s\n' "$f"; done)
bad6=""
if [ -n "$sel6" ]; then
  cbytes=$(printf '%s\n' "$sel6" | xargs -r wc -c)
  clines=$(printf '%s\n' "$sel6" | xargs -r wc -l)
  bad6=$(awk '
    FNR==NR { if ($NF!="total") b[$NF]=$1; next }
    $NF=="total" { next }
    { l[$NF]=$1; ord[++n]=$NF }
    END { for(i=1;i<=n;i++){ f=ord[i]; if (b[f]+0>20480 || l[f]+0>250) printf "%s (%dB %dL > 20480B/250L)\n", f, b[f]+0, l[f]+0 } }
  ' <(printf '%s\n' "$cbytes") <(printf '%s\n' "$clines"))
fi
[ -n "$bad6" ] && fail 6 "index files over cap (rotate to archive/<INDEX>.<YYYY-MM-DD>.md; a codebase-map dossier over cap is SPLIT into two dossiers instead — never rotate FOUNDATION.md, the map gate requires it):
$bad6"

# 7 — entry budget ≤300 chars (grandfather: curation-debt.txt; exempt guides/*.md — a guide is prose,
#     not index rows — and, when the codebase-map kit is adopted under this tree, its
#     dossiers/FOUNDATION (detail files).
# ONE base plus an APPEND, never a second full spelling (aMendedLedger U3). The MAP_SUB branch used to
# rebuild the whole expression, which silently dropped the guides/ alternative on any repo carrying a
# .codebase-map.conf — every guide entered this check's population and nothing said so. Two spellings
# of one expression is the two-answers-to-one-question class, and this is how it fired.
ex7='/guides/[^/]+\.md$'
[ -n "$MAP_SUB" ] && ex7="$ex7|/$MAP_SUB/FOUNDATION\.md\$|/$MAP_SUB/features/[^/]+\.md\$"
# ONE awk over the whole selected set (was `_unfenced | awk` = 2 forks per file; measured 7.86s here,
# TOOL-aBatchedLintel-1). `uln` counts the UNFENCED stream, which is what the old `FNR` counted — the
# piped `_unfenced` output WAS the record source, so the reported line number was never the file line
# number and must not become one.
#
# NO `LC_ALL=` prefix and no `xargs` wrapper that sets one, deliberately. `length()` decides this
# verdict and its character-versus-byte meaning is a property of the awk build and the ambient
# locale; pinning it would silently re-decide the cap on any adopter whose awk counts characters
# today. Check 8 at the batched `LC_ALL=C xargs -r awk` seventeen lines below is NOT the pattern to
# copy here — it sorts, it does not measure.
sel7=$(printf '%s\n' "$INDEX_SET" | grep -vE "$ex7" | while IFS= read -r f; do
  in_debt "$f" && continue; in_scope "$f" || continue; printf '%s\n' "$f"
done)
bad7=""
if [ -n "$sel7" ]; then
  bad7=$(awk '
    { f = $0; if (f == "") next
      fence = ""; uln = 0
      while ((getline line < f) > 0) {
        sub(/\r$/, "", line)
        if (line ~ /^[[:space:]]*(```|~~~)/) {
          mk = (line ~ /^[[:space:]]*```/) ? "```" : "~~~"
          if (fence == "") { fence = mk; continue }
          if (mk == fence) { fence = ""; continue }
        }
        if (fence != "") continue
        uln++
        if (length(line) > 300 && line !~ /^#/ && line !~ /^[[:space:]]*\|[-: |]+\|[[:space:]]*$/)
          print f ":" uln " (" length(line) " chars)"
      }
      close(f)
    }' <<<"$sel7")
fi
[ -n "$bad7" ] && fail 7 "index entry lines over 300 chars:
$bad7"

# 8 — status vocabulary on BACKLOG.md / STATUS.md (grandfather: curation-debt.txt).
# One awk over the whole filtered file set (was _unfenced + grep -n PER file and a 3-fork
# printf|grep -oE|wc -l PER row). nmatch() reproduces `grep -oE '…\b' | wc -l` EXACTLY: the
# `^[[:space:]]*-` slot can only anchor once (caret pattern on the first match, no-caret thereafter),
# and the trailing `\b` is checked ZERO-WIDTH (next char is end/non-word) so it never consumes a
# following delimiter. uln counts the UNFENCED stream (== the old grep -n numbering). The two `·` in
# the patterns are the LITERAL middot byte. Validated per-row against grep over the upstream inCMS
# tree's 589 real rows — 0 mismatches (PERF-eThriftyBellows-1).
pop8=$( { printf '%s\n' "$FILES" | grep -E "^$M/backlog/[^/]+\.md$"; printf '%s\n' "$FILES" | grep -E "^$M/builds/[^/]+/STATUS\.md$"; } | grep -c . || true)
pop_guard 8 "no backlog shard under $M/backlog/ and no STATUS.md under $M/builds/" "$pop8" "$PRE_STATUSY"
files8=$( { printf '%s\n' "$FILES" | grep -E "^$M/backlog/[^/]+\.md$"; printf '%s\n' "$FILES" | grep -E "^$M/builds/[^/]+/STATUS\.md$"; } | while IFS= read -r f; do
  [ -f "$f" ] || continue; in_debt "$f" && continue; in_scope "$f" || continue; printf '%s\n' "$f"; done)
bad8=""
if [ -n "$files8" ]; then
  bad8=$(printf '%s\n' "$files8" | LC_ALL=C xargs -r awk '
    function nmatch(s,   c,first,nc,ok) { c=0; first=1
      while (length(s)>0) {
        if (first) ok=match(s,/([·|]|^[[:space:]]*-)[[:space:]]*(OPEN|SPECCED|INPROGRESS|BLOCKED|DEFERRED|CLOSED|WONTDO)/)
        else       ok=match(s,/[·|][[:space:]]*(OPEN|SPECCED|INPROGRESS|BLOCKED|DEFERRED|CLOSED|WONTDO)/)
        if (!ok) break
        nc=substr(s,RSTART+RLENGTH,1)
        if (nc=="" || nc !~ /[A-Za-z0-9_]/) { c++; s=substr(s,RSTART+RLENGTH); first=0 }
        else { s=substr(s,RSTART+1); first=0 }
      } return c }
    FNR==1 { uln=0; fence="" }
    { line=$0; sub(/\r$/,"",line)
      if (line ~ /^[[:space:]]*(```|~~~)/) { m=(line ~ /^[[:space:]]*```/)?"```":"~~~"
        if (fence=="") { fence=m; next }
        if (m==fence) { fence=""; next } }
      if (fence!="") next
      uln++
      if (line ~ /^[[:space:]]*[|-].*[A-Z]+-[A-Za-z0-9]*-?[0-9]/ && nmatch(line)!=1) print FILENAME ":" uln
    }')
fi
[ -n "$bad8" ] && fail 8 "backlog/STATUS rows without exactly one status token (OPEN SPECCED INPROGRESS BLOCKED DEFERRED CLOSED WONTDO):
$bad8"

# 9 — build-index drift (delegates to the sibling generator). The retired directory listing carried
# PATHS, which git already prints better; this carries STATUS, which git does not — and the status is
# DERIVED from each build's front matter plus its specs' status headers, so nothing is authored here
# and nothing rots.
if [ "$STAGED" = 0 ] || printf '%s\n' "$STAGED_MD" | grep -q .; then
  if ! drift=$("$_PY" "$HERE/gen_build_index.py" --check 2>&1); then fail 9 "generated build index differs from a fresh render:
$drift"; fi
fi

# 10 — rotation note (always; cheap). FLAT (1.5): one archive at the memory root.
bad10=$(printf '%s\n' "$FILES" | grep -E "^$M/archive/[^/]+\.[0-9]{4}-[0-9]{2}-[0-9]{2}\.md$" | while IFS= read -r a; do
    base=${a##*/}; idx="$M/${base%%.*}.md"
    [ -f "$idx" ] || continue
    head -3 "$idx" | grep -qF "$base" || echo "$a (not referenced in lines 1-3 of $idx)"
  done)
[ -n "$bad10" ] && fail 10 "rotated archives not referenced from their live index (lines 1-3):
$bad10"

# 11 — old-tree tombstone (only if TOMBSTONE_ROOTS is configured; never grandfathered).
for old in $TOMBSTONE_ROOTS; do
  if git ls-files "$old/" | grep -q .; then
    fail 11 "migrated-from tree '$old/' resurrected — $M/ is the only sanctioned memory root:
$(git ls-files "$old/" | head)"
  fi
done

# 12 — spec format ($M/TEMPLATE-SPEC.md; runs only when SPEC_FORMAT_CUTOFF is set in the conf).
# Status header (first 5 unfenced lines) for every spec incl. nested spec/<sub>/ files. Tier-2 adds:
# the canonical nine ## sections (exact, in order) · no empty section bodies (write "N/A — <why>") ·
# header rev logged in §9 · terminal Status (CLOSED/WONTDO) needs a resolved §8. Both tiers: no
# skeleton placeholders; WONTDO needs a successor/reason in the header tail. Tier-1 skips the
# section canon ("ceremony is conditional"). Pre-cutoff specs are grandfathered by FILENAME date;
# legacy-named files never match the glob. NOTE (shared idiom with checks 6/7/8): reads WORKTREE
# content in --staged mode, not the staged blob — CI's full run is the tree-wide truth.
if [ -n "$SPEC_FORMAT_CUTOFF" ]; then
SPEC_CANON='## 1. Goal
## 2. Scope (IN)
## 3. Non-goals (OUT)
## 4. Design
## 5. Production-readiness checklist
## 6. Acceptance criteria
## 7. Gates
## 8. Open questions
## 9. Revision log'
# §10 is date-gated exactly as the section canon itself is: a spec dated before SPEC10_CUTOFF keeps
# the nine-section shape, so adopting reuse-audit never retroactively reds a landed spec. The kit
# already ships tools/codebase-map/reuse_lookup.py; this is the check that makes anyone use it.
SPEC10_CUTOFF="${SPEC10_CUTOFF:-2026-08-04}"
SPEC_CANON10="$SPEC_CANON
## 10. Reuse audit"
# ONE awk over the whole population, replacing ~13 forks PER SPEC (measured 42.88s of an 81.77s run
# here; upstream inCMS measured the same shape at 257.8s of 311s over 356 specs —
# TOOL-aBatchedLintel-1 ports PERF-aSlothfulCapstan-1). The driver is a tagged path stream built in
# the SHELL rather than an `ARGIND` switch: ARGIND is gawk-only, and upstream had a byte cap silently
# not exist under mawk because of it. `M` = tracked and in scope but absent from the worktree,
# `P` = analyse. `[ -f ]` stays a bash builtin so the absent-file finding keeps its position in the
# stream. The canon rides in on `-v canon=`: this kit has ONE nine-line canon and one equality, so it
# needs no canon records in the driver and therefore has no TAB-truncation hazard to guard against.
c12_all=$(printf '%s\n' "$FILES" | grep -E "^$M/builds/[^/]+/spec/(.+/)?[0-9]{4}-[0-9]{2}-[0-9]{2}-spec-(($FAM_ALT)-)?[A-Za-z0-9]+-[0-9]+$REC_TAIL\.md$" || true)
pop_guard 12 "no spec file under $M/builds/*/spec/" "$(printf '%s\n' "$c12_all" | grep -c . || true)" "$PRE_SPEC"
c12_sel=$(printf '%s\n' "$c12_all" | grep . | while IFS= read -r f; do
  base=${f##*/}; d=${base:0:10}      # spawn-free date extract — this loop sees every spec file
  [ "$d" \< "$SPEC_FORMAT_CUTOFF" ] && continue
  in_scope "$f" || continue          # no-op in full mode; decides the WHOLE selection under --staged
  if [ -f "$f" ]; then printf 'P\t%s\n' "$f"; else printf 'M\t%s\n' "$f"; fi
done)
bad12_raw=""
if [ -n "$c12_sel" ]; then
# Every array below is read only up to its own counter (n, ng, q), so entries left from a previous
# file are unreachable and no `delete array` is needed — which also keeps this off a construct whose
# portability would have to be argued rather than read. Interval expressions are spelled out
# character by character for the same reason: on a build that does not honour `{8}` the header regex
# would demand those literal bytes and never match, redding every post-cutoff spec.
bad12_raw=$(printf '%s\n' "$c12_sel" | awk -F'\t' -v canon="$SPEC_CANON" -v canon10="$SPEC_CANON10" -v cut10="$SPEC10_CUTOFF" -v mroot="$M" -v discalt="$DISC_ALT" -v scut="$STREAMS_CUTOFF" '
  $1 == "M" { print $2 " (tracked but missing from worktree)"; next }
  $1 != "P" { next }
  {
    f = $2
    # ---- the _unfenced fence machine, verbatim: CR strip, marker-matched fences ----
    n = 0; fence = ""
    while ((getline line < f) > 0) {
      sub(/\r$/, "", line)
      if (line ~ /^[[:space:]]*(```|~~~)/) {
        mk = (line ~ /^[[:space:]]*```/) ? "```" : "~~~"
        if (fence == "") { fence = mk; continue }
        if (mk == fence) { fence = ""; continue }
      }
      if (fence != "") continue
      body[++n] = line
    }
    close(f)
    # `body=$(_unfenced "$f")` held this text, and command substitution DROPS trailing newlines, so
    # the old body ended at its last non-empty line. That is load-bearing: the §8 extraction below
    # reproduces `sed "1d;$d"`, whose two deletes act on the CONCATENATED range output, and a body
    # that keeps its trailing blanks moves which line the last delete removes — inventing a finding
    # on a terminal spec whose §8 is the last section.
    while (n > 0 && body[n] == "") n--
    # ---- hdr: head -5 | grep -E "^\*\*Status:\*\* " | head -1, over the UNFENCED body ----
    hdr = ""; lim = (n < 5) ? n : 5
    for (i = 1; i <= lim; i++) if (body[i] ~ /^\*\*Status:\*\* /) { hdr = body[i]; break }
    if (hdr !~ /^\*\*Status:\*\* (OPEN|SPECCED|INPROGRESS|BLOCKED|DEFERRED|CLOSED|WONTDO) · rev-[0-9]+ · [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] · node [a-z] · Tier-[12] · base [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]/) {
      print f " (missing/invalid **Status:** header in lines 1-5)"
      next      # header unparseable — the per-field assertions below have no anchor
    }
    for (i = 1; i <= n; i++) if (body[i] ~ /<FAMILY-slug-seq>|YYYY-MM-DD/) { print f " (unfilled skeleton placeholder)"; break }
    if (hdr ~ /^\*\*Status:\*\* WONTDO/ && hdr !~ /base [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]* · ./)
      print f " (WONTDO needs a successor id or reason pointer in the header tail)"
    # ---- the FILENAME date, computed once. Not the first date in the PATH: a build folder used to
    # ---- be date-named itself, and matching the whole path grandfathered by the wrong date. Both
    # ---- the streams ratchet and the section canon read this, and BOTH tiers need the streams one,
    # ---- so it is computed above the Tier-1 exit rather than inside the Tier-2 block.
    fbase = f; sub(/^.*\//, "", fbase)
    fdate = ""
    if (match(fbase, /[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/)) fdate = substr(fbase, RSTART, RLENGTH)
    # ---- streams: the discipline is a SIGNAL, not a directory (1.5). Validated whenever present, on
    # ---- either tier; REQUIRED once the filename date reaches STREAMS_CUTOFF. `streams ` is matched
    # ---- as 8 ASCII bytes rather than by offsetting past the middot separator, whose length in
    # ---- characters-versus-bytes is a property of the awk build and the ambient locale.
    strv = ""
    if (match(hdr, /streams [A-Za-z0-9]+(\+[A-Za-z0-9]+)*/)) strv = substr(hdr, RSTART + 8, RLENGTH - 8)
    if (strv == "") {
      if (scut != "" && fdate != "" && fdate >= scut)
        print f " (filename date " fdate " is on/after STREAMS_CUTOFF " scut " but the header carries no `· streams <value>` segment; legal values: " discalt ")"
    } else {
      nsb = 0; sbad = ""
      ns = split(strv, sv, "+")
      for (si = 1; si <= ns; si++) if (sv[si] !~ "^(" discalt ")$") { nsb++; sbad = (nsb == 1) ? sv[si] : sbad ", " sv[si] }
      if (nsb > 0) print f " (streams value(s) outside the enum: " sbad "; legal values: " discalt ")"
    }
    if (hdr ~ /Tier-1/) next
    # ---- Tier-2 body assertions ----
    ng = 0; got = ""
    for (i = 1; i <= n; i++) if (body[i] ~ /^## /) { got = (++ng == 1) ? body[i] : got "\n" body[i] }
    # pick the canon by FILENAME date (computed above), mirroring how the whole check is grandfathered
    want = (fdate != "" && fdate >= cut10) ? canon10 : canon
    wantn = (want == canon10) ? "ten" : "nine"
    if (got != want) {
      print f " (## sections differ from the canonical " wantn " of " mroot "/TEMPLATE-SPEC.md):"
      print "\001\t" f      # the excerpt is a real diff — rebuilt by the post-pass below
    }
    # ---- empty section bodies. The old test was `NF > 0` on a split record; the line is read into a
    # ---- variable here, so NF does not exist and /[^ \t]/ stands in. The two agree on every
    # ---- plain-text line; they part only on an invalid multibyte byte under gawk in a UTF-8 locale.
    ne = 0; emp = ""; s = ""; cnt = 0
    for (i = 1; i <= n; i++) {
      L = body[i]
      if (L ~ /^## /) {
        if (s != "" && cnt == 0) { ne++; emp = (ne == 1) ? "    " s : emp "\n    " s }
        s = L; cnt = 0; continue
      }
      if (s != "" && L ~ /[^ \t]/) cnt++
    }
    if (s != "" && cnt == 0) { ne++; emp = (ne == 1) ? "    " s : emp "\n    " s }
    if (ne > 0) print f " (section with an empty body — write N/A — <why>):" "\n" emp
    # ---- header rev vs the §9 high-water. The range CLOSES on the next `## ` heading. Without that
    # ---- close it ran to the end of the body, so any rev-N below §9 -- in §10, or in later prose --
    # ---- raised the high-water and a header rev counted as logged whenever a larger number appeared
    # ---- anywhere further down. Reproduced at 99 against a true 1.
    # ---- A VERDICT change, measured before it landed: closing the range can only produce MORE
    # ---- findings, and over the real corpus it changes 0 of 22 in-scope specs. Nobody paid, so the
    # ---- two fixtures in the self-test are the only evidence this works -- one per sub-path, since
    # ---- the branch fires both when §9 logs a SMALLER rev and when it logs NONE.
    # ---- (No apostrophe below this line: the whole awk program is one single-quoted shell string.)
    k = "· rev-"; p = index(hdr, k); hrev = ""
    if (p > 0) { t = substr(hdr, p + length(k)); sp = index(t, " "); hrev = (sp > 0) ? substr(t, 1, sp - 1) : t }
    in9 = 0; seen = 0; mx = 0
    for (i = 1; i <= n; i++) {
      L = body[i]
      if (L ~ /^## 9\. Revision log/) in9 = 1
      else if (in9 && L ~ /^## /) in9 = 0
      if (in9) while (match(L, /rev-[0-9]+/)) {
        v = substr(L, RSTART + 4, RLENGTH - 4) + 0
        if (!seen || v > mx) mx = v
        seen = 1; L = substr(L, RSTART + RLENGTH)
      }
    }
    if (!seen || hrev + 0 > mx) print f " (header rev-" hrev " not logged in the §9 Revision log)"
    # ---- terminal status needs a resolved §8. Reproduces `sed -n "/A/,/B/p" | sed "1d;$d"`: the
    # ---- range RESTARTS on a later opener, runs to EOF when §9 never follows, and yields nothing
    # ---- when shorter than three lines because both deletes land inside it.
    if (hdr ~ /^\*\*Status:\*\* CLOSED/ || hdr ~ /^\*\*Status:\*\* WONTDO/) {
      q = 0; inr = 0
      for (i = 1; i <= n; i++) {
        L = body[i]
        if (!inr) { if (L ~ /^## 8\. Open questions/) { inr = 1; rng[++q] = L } }
        else { rng[++q] = L; if (L ~ /^## 9\. /) inr = 0 }
      }
      q8 = ""
      for (i = 2; i <= q - 1; i++) if (rng[i] !~ /^[[:space:]]*$/) { q8 = rng[i]; break }
      if (q8 != "" && q8 !~ /^none/ && q8 !~ /^N\/A/) print f " (terminal Status with unresolved §8 Open questions)"
    }
  }')
fi
# The section-canon excerpt keeps a REAL `diff`: reproducing its normal-format output inside awk
# would need a longest-common-subsequence implementation, and the mismatch path fires zero times on a
# clean tree. awk emits a sentinel record and the excerpt is rebuilt here by the ORIGINAL commands
# over the ORIGINAL inputs, so the bytes cannot drift from a second implementation. The `case` guard
# means a clean run never enters the loop.
case "$bad12_raw" in
  *$'\001'*)
    bad12=$(printf '%s\n' "$bad12_raw" | while IFS= read -r _ln; do
      case "$_ln" in
        $'\001'*)
          _f=${_ln#$'\001'$'\t'}
          _g=$(_unfenced "$_f" | grep -E '^## ' || true)
          # Diff the canon AWK CHOSE, by the same basename-date rule. Diffing the nine-canon
          # when awk wanted ten printed a BLANK excerpt for the primary new failure mode — a
          # diagnostic that cannot describe its own finding.
          _b=${_f##*/}
          _d=$(printf %s "$_b" | grep -oE "[0-9]{4}-[0-9]{2}-[0-9]{2}" | head -1)
          if [ -n "$_d" ] && ! [ "$_d" \< "$SPEC10_CUTOFF" ]; then _want=$SPEC_CANON10; else _want=$SPEC_CANON; fi
          diff <(printf '%s\n' "$_want") <(printf '%s\n' "$_g") | head -6 | sed 's/^/    /' ;;
        *) printf '%s\n' "$_ln" ;;
      esac
    done) ;;
  *) bad12=$bad12_raw ;;
esac
[ -n "$bad12" ] && fail 12 "spec files dated >= $SPEC_FORMAT_CUTOFF not conforming to $M/TEMPLATE-SPEC.md:
$bad12"
fi

# 13-16 — id + path corpus classification (delegates to the sibling classifier). ONE grammar and ONE
# walk: this script owns the append-only and index sets and PRINTS them on demand; the classifier
# owns the id grammar it imports from the recall kit. Neither transcribes the other. Every pin the
# classifier reads is measured per corpus, and blank pins turn the whole unit off.
if [ "$STAGED" = 0 ]; then
  if ! ids=$("$_PY" "$HERE/corpus_ids.py" --check 2>&1); then
    printf '%s
' "$ids"; status=1
  fi
fi

# 17-19 — the bug-class catalogue (delegates to the sibling module). The catalogue's INDEX is
# generated, every class record declares a gate or says it has none, and a record whose anchors reach
# only the append-only tree is reachable on paper and dead in practice.
if [ "$STAGED" = 0 ]; then
  if ! got=$("$_PY" "$HERE/gotchas.py" --check 2>&1); then
    printf '%s
' "$got"; status=1
  fi
fi

# grandfather stale-line guards (a listed path that no longer exists fails).
# One `git ls-files` + set lookups, NOT `git ls-files --error-unmatch` per path — git is a heavyweight
# fork, so a long grandfather list was one spawn per line (~80s at inCMS's 522 lines). Entries are
# literal paths, never globs, so exact membership in the tracked set is equivalent.
if [ -n "$LEGACY$DEBT" ]; then
  declare -A TRACKED_SET
  while IFS= read -r _l; do [ -n "$_l" ] && TRACKED_SET["$_l"]=1; done < <(git ls-files)
  badL=$(printf '%s\n' "$LEGACY" | grep . | while IFS= read -r p; do [ -n "${TRACKED_SET[$p]+x}" ] || echo "$p"; done)
  [ -n "$badL" ] && fail 5 "legacy-files.txt lists paths that no longer exist (stale-line guard):
$badL"
  badD=$(printf '%s\n' "$DEBT" | grep . | while IFS= read -r p; do [ -n "${TRACKED_SET[$p]+x}" ] || echo "$p"; done)
  [ -n "$badD" ] && fail 6 "curation-debt.txt lists paths that no longer exist (stale-line guard):
$badD"
fi

# --- empty-population report (see pop_guard). Reported ONCE, after every check has run, so the
# --- message names every disarmed selector instead of the first one. A tree that genuinely has no
# --- builds yet is a real case: scaffold it, or set MEMORY_ROOT to the tree that has one.
if [ -n "$POP_MISSING" ]; then
  echo "HYGIENE FAILED — a check selected an EMPTY population. An empty selection prints nothing,"
  echo "HYGIENE which is exactly what a passing check prints, so the gate would be green over an"
  echo "HYGIENE unlinted tree. Either the tree is unscaffolded or a path selector is mis-segmented."
  printf '%s' "$POP_MISSING"
  status=1
fi

exit "$status"
