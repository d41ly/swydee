#!/usr/bin/env bash
# Scaffold an empty, hygiene-passing structured memory tree from .memory-tree.conf.
# For a NEW project. (A project MIGRATING an existing docs tree does that once as its own landing —
# see README.md "Adopting into an existing tree"; the tree shape below is the target either way.)
#
#   memory-tree/adopt-memory-tree.sh --scaffold
set -eu
ROOT="$(git rev-parse --show-toplevel)" || exit 2
cd "$ROOT" || exit 2
HERE="$(cd "$(dirname "$0")" && pwd)"
MEMORY_ROOT=memory
# DISCIPLINES is a CLOSED ENUM of stream values, not a directory list (kit 1.5). The tree is flat.
DISCIPLINES="architecture deployment blocks design performance"   # demo defaults; a real .memory-tree.conf overrides these
FAMILIES="architecture:ARCH deployment:DEPLOY blocks:BLOCK design:DES performance:PERF"
FAMILY_of() { local p; for p in $FAMILIES; do case "$p" in "$1:"*) echo "${p#*:}"; return;; esac; done; }

[ "${1:-}" = "--scaffold" ] || { echo "usage: $0 --scaffold"; exit 2; }

# .memory-tree.conf is REQUIRED — never silently scaffold the built-in DEMO disciplines into a real repo.
if [ ! -f "$ROOT/.memory-tree.conf" ]; then
  cp "$HERE/.memory-tree.conf.example" "$ROOT/.memory-tree.conf"
  echo "created .memory-tree.conf from the example — EDIT IT (MEMORY_ROOT, DISCIPLINES, FAMILIES), then re-run." >&2
  exit 1
fi
. "$ROOT/.memory-tree.conf"
M="$MEMORY_ROOT"

# Idempotent converge: a tree already scaffolded by this kit (marker present) is a clean no-op; a
# foreign/half-scaffolded memory/ is refused with a recovery hint; otherwise fall through and scaffold.
if [ -d "$M" ]; then
  if [ -f "$M/HYGIENE.md" ] && grep -q 'gov:kit memory-tree@' "$M/HYGIENE.md"; then
    echo "$M/ already scaffolded by memory-tree — nothing to do."; exit 0
  fi
  echo "$M/ exists without a memory-tree marker — refusing to overwrite. If a prior scaffold crashed, 'rm -rf $M' and re-run; otherwise migrate manually (README: Adopting into an existing tree)." >&2
  exit 1
fi

# `project/` still needs creating even though it now holds only files: the registry printf
# redirects below cannot create their own directory.
mkdir -p "$M/project" "$M/builds" "$M/backlog"
# root index + rules
if [ -f "$HERE/HYGIENE.template.md" ]; then cp "$HERE/HYGIENE.template.md" "$M/HYGIENE.md"; else echo "# ${M}/ retention & hygiene" > "$M/HYGIENE.md"; fi
if [ -f "$HERE/SPEC-TEMPLATE.template.md" ]; then cp "$HERE/SPEC-TEMPLATE.template.md" "$M/TEMPLATE-SPEC.md"; fi
{ echo "# $M/ — project memory index"; echo
  echo "Structured, machine-linted project memory. Shape + rules: [HYGIENE.md](HYGIENE.md)."
  echo "Generated index: [LIVE.md](LIVE.md) + \`ledger/<month>.md\` shards (memory-tree/gen_build_index.py)."; echo
  echo "The discipline is a SIGNAL, not a directory. A build folder is named for its slug alone; which"
  echo "discipline it served is declared in each spec's status header as \`streams <value>[+<value>]\`,"
  echo "over the closed enum \`.memory-tree.conf\` declares."; echo
  echo "## Root files"; echo
  echo "- [DECISIONS.md](DECISIONS.md) — append-only decision index, every family, grouped for reading."
  echo "- [TEMPLATE-SPEC.md](TEMPLATE-SPEC.md) — the canonical spec / design-pass format (hygiene check 12)."
  echo "- [HYGIENE.md](HYGIENE.md) — the rule set; the check script is its enforcement."; echo
  echo "## Directories"; echo
  echo "- [builds/](builds/) — one folder per slug: \`README.md\` · \`STATUS.md\` · \`prompts/\` \`spec/\` \`build/\` \`reviews/\`."
  echo "- [backlog/](backlog/) — one mutable shard per id family."
  echo "- [project/](project/) — the gate's own waiver registries (\`*.txt\`) and nothing else: legacy-files, curation-debt, id-orphan-waiver, corpus-path-unresolved, unarmed-branches."; echo
  echo "## Streams (the closed enum)"; echo
  echo "| Value | Family |"; echo "|---|---|"
  for d in $DISCIPLINES; do echo "| \`$d\` | \`$(FAMILY_of "$d")\` |"; done
} > "$M/README.md"
# ONE append-only decision log, every family, grouped for reading.
{ printf '# decisions — index

'
  printf '> One line per decision, APPEND-ONLY, every family in one file. Detail in `decisions/`.
'
  printf '> Grouped by family for reading; the file is never re-sorted and a landed row is never edited.
'
  for d in $DISCIPLINES; do printf '
## %s — %s

*(none yet)*
' "$(FAMILY_of "$d")" "$d"; done
} > "$M/DECISIONS.md"
# project/ — the gate's OWN waiver registries and nothing else. ALL FIVE are written here, not two:
# three of them are NAMED by gates (corpus_ids.py's checks 14 and 15, check-arms.py) and were created
# by nothing, so an adopter met them as a missing file rather than as an empty ratchet. The gate reads
# "absent" and "present and empty" identically, which is exactly what makes the omission invisible.
printf '# legacy-files.txt — recording files kept under historical names (permanent C5 exemption). Empty = strict.
' > "$M/project/legacy-files.txt"
printf '# curation-debt.txt — index files pending slimming (exempt from checks 6/7/8 while listed). Empty = fully strict.
' > "$M/project/curation-debt.txt"
printf '# id-orphan-waiver.txt — ids cited but never defined, deliberately (check 14). One id per line.
# Shrink-only against ORPHAN_ID_PIN; a waived id that now resolves is a stale row and reds.
' > "$M/project/id-orphan-waiver.txt"
printf '# corpus-path-unresolved.txt — rooted repo-path citations in the present-tense corpus that
# resolve to nothing (check 15). One row per (citing-file, cited-path), TAB-separated:
#   <citing-file>\t<cited-path>\t<occurrences>\t<absent|moved:DEST>
# Shrink-only against DEAD_PATH_PIN. Empty = every citation resolves.
' > "$M/project/corpus-path-unresolved.txt"
printf '# unarmed-branches.txt — `fail` branches with no positive assertion naming their own failure
# text (check-arms.py). Fields: gate<TAB>check<TAB>ordinal<TAB>signature.
# SHRINK-ONLY, and EMPTY is the working state: a row appears only when a new branch lands that no
# fixture can reach, and it carries the REASON — "not yet written" and "cannot be written from here"
# are indistinguishable in a bare pin and only one of them is acceptable.
' > "$M/project/unarmed-branches.txt"
# one mutable backlog shard per FAMILY
for d in $DISCIPLINES; do
  fam=$(FAMILY_of "$d")
  printf '# %s backlog (%s)

> Mutable. Each row leads with one status token (OPEN…WONTDO).
' "$fam" "$d" > "$M/backlog/$fam.md"
done
# builds/ starts empty; a .gitkeep would be an unsanctioned entry under check 3, so the first build
# is what makes the directory tracked. The empty-population guard says so out loud on the first run.
# Stage the tree FIRST so the generator (git ls-files) sees the files, then render + re-stage.
git add "$M" >/dev/null 2>&1 || true
# The resolver, INLINE. This kit is copy-installed as a standalone directory, so `../lib/` does
# not exist in an adopting repo. The block below is byte-identical to tools/lib/resolve-python.sh
# and tools/lib/resolve-python.test.sh reds if any copy drifts.
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
_PY=$(resolve_python) || exit 2
"$_PY" "$HERE/gen_build_index.py" --write
git add "$M" >/dev/null 2>&1 || true

echo "Scaffolded $M/ ($(echo $DISCIPLINES | wc -w) disciplines) — staged."
echo "Next:"
echo "  1. git add $M/ .memory-tree.conf && commit."
echo "  2. Wire the gate: add 'bash memory-tree/check-memory-hygiene.sh' to CI + your local gate runner;"
echo "     add a pre-commit fast leg calling it with --staged on staged $M/** paths."
echo "  3. Verify: bash memory-tree/check-memory-hygiene.sh ; echo \$?   (expect 0)"
echo "  4. Arm the spec-format ratchet: set SPEC_FORMAT_CUTOFF=<today> in .memory-tree.conf"
echo "     (every spec dated >= it must follow $M/TEMPLATE-SPEC.md — hygiene check 12)."
echo "  5. Arm the streams ratchet: set STREAMS_CUTOFF in .memory-tree.conf STRICTLY AHEAD of every"
echo "     committed spec's filename date, so no landed spec is retroactively red. Every spec written"
echo "     from that date on must carry '· streams <value>' in its status header."
echo "  6. MEASURE any pin/floor this kit gains against YOUR corpus — never inherit another repo's"
echo "     numbers. A pin copied from a larger tree is either vacuous or permanently red here."
