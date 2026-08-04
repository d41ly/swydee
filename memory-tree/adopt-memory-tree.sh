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

mkdir -p "$M/project/journal"
# root index + rules
if [ -f "$HERE/HYGIENE.template.md" ]; then cp "$HERE/HYGIENE.template.md" "$M/HYGIENE.md"; else echo "# ${M}/ retention & hygiene" > "$M/HYGIENE.md"; fi
if [ -f "$HERE/SPEC-TEMPLATE.template.md" ]; then cp "$HERE/SPEC-TEMPLATE.template.md" "$M/TEMPLATE-SPEC.md"; fi
{ echo "# $M/ — project memory index"; echo
  echo "Structured, machine-linted project memory. Shape + rules: [HYGIENE.md](HYGIENE.md). Generated tree: [TREE.md](TREE.md)."; echo
  echo "## Disciplines"; echo
  for d in $DISCIPLINES; do echo "- [$d/]($d/) — decisions \`$(FAMILY_of "$d")-<slug>-<seq>\`, per-feature builds/."; done
  echo; echo "## Cross-discipline"; echo; echo "- [project/](project/) — session machinery: MEMORY.md, IN-FLIGHT.md (pointer) + in-flight/<tag>.md, journal/, notes."
} > "$M/README.md"
# project/
printf '# %s/project/ — session machinery\n\n- MEMORY.md — memory-note index (one line per note).\n- IN-FLIGHT.md — ledger pointer; in-flight/<tag>.md — per-node ledger files (write only your own).\n- journal/ — per-session journals.\n' "$M" > "$M/project/README.md"
printf '# Memory Index\n\n> One line per durable note.\n' > "$M/project/MEMORY.md"
printf '# In-flight ledger — sharded per node\n\nOne file per node under `in-flight/`. **Write ONLY your own node file** (`in-flight/<tag>.md`) so the ledger never conflicts on merge; **read all** of them for the who-is-touching-what / slug-collision scan. Row: node · slug · branch · streams · status; status in {in-flight | merged:<sha>}. Self-prune your own merged rows once the sha is an ancestor of `main`.\n' > "$M/project/IN-FLIGHT.md"
printf '# legacy-files.txt — recording files kept under historical names (permanent C5 exemption). Empty = strict.\n' > "$M/project/legacy-files.txt"
printf '# curation-debt.txt — index files pending slimming (exempt from checks 6/7/8 while listed). Empty = fully strict.\n' > "$M/project/curation-debt.txt"
touch "$M/project/journal/.gitkeep"
mkdir -p "$M/project/in-flight"; touch "$M/project/in-flight/.gitkeep"
# disciplines
for d in $DISCIPLINES; do
  fam=$(FAMILY_of "$d")
  mkdir -p "$M/$d"
  { echo "# $M/$d/"; echo; echo "Decision log \`$fam-<slug>-<seq>\`, backlog, per-feature builds/. Shape: [../HYGIENE.md](../HYGIENE.md)."; } > "$M/$d/README.md"
  printf '# %s decisions — index\n\n> One line per decision, append-only. Detail in decisions/.\n' "$d" > "$M/$d/DECISIONS.md"
  printf '# %s backlog\n\n> Mutable. Each row leads with one status token (OPEN…WONTDO).\n' "$d" > "$M/$d/BACKLOG.md"
done
# Stage the tree FIRST so the generator (git ls-files) sees the files, then generate + re-stage TREE.md.
git add "$M" >/dev/null 2>&1 || true
bash "$HERE/gen-memory-tree.sh" --write
git add "$M" >/dev/null 2>&1 || true

echo "Scaffolded $M/ ($(echo $DISCIPLINES | wc -w) disciplines) — staged."
echo "Next:"
echo "  1. git add $M/ .memory-tree.conf && commit."
echo "  2. Wire the gate: add 'bash memory-tree/check-memory-hygiene.sh' to CI + your local gate runner;"
echo "     add a pre-commit fast leg calling it with --staged on staged $M/** paths."
echo "  3. Verify: bash memory-tree/check-memory-hygiene.sh ; echo \$?   (expect 0)"
echo "  4. Arm the spec-format ratchet: set SPEC_FORMAT_CUTOFF=<today> in .memory-tree.conf"
echo "     (every spec dated >= it must follow $M/TEMPLATE-SPEC.md — hygiene check 12)."
