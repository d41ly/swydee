#!/usr/bin/env bash
# kit-dogfood-parity.test.sh — the two documents this kit SHIPS must equal the two documents this
# repo RUNS ON, modulo one declared substitution. Exit 0 = in parity · 1 = drift · 2 = misconfigured.
#
#   bash tools/memory-tree/kit-dogfood-parity.test.sh            # assert parity
#   bash tools/memory-tree/kit-dogfood-parity.test.sh --render    # rewrite the shipped copies from the live ones
#
# WHY THIS EXISTS. `HYGIENE.template.md` and `SPEC-TEMPLATE.template.md` are copied into an adopting
# repo verbatim; `<MEMORY_ROOT>/HYGIENE.md` and `<MEMORY_ROOT>/TEMPLATE-SPEC.md` are this repo's own
# installed copies, and they are what a session reads while working here. Nothing connected them, so
# they drifted: measured 2026-08-08, the shipped spec template still described a NINE-section canon
# and carried no SPEC10_CUTOFF section, while the live copy — and the gate — had required TEN
# sections since 2026-08-04. An adopter would have installed a template the gate rejects. This is the
# kit-versus-dogfood divergence class, and prose alone never catches it.
#
# THE SUBSTITUTION. The kit ships TOOL-ROOT-RELATIVE (`memory-tree/…`, `codebase-map/…`) because an
# adopter chooses where the kits live. This repo installs them under `tools/`. So the only sanctioned
# difference is that leading `tools/`, and the comparison strips exactly that and nothing else. Any
# other difference is drift and is printed as a diff.
set -u
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "kit-parity: not a git repo"; exit 2; }
cd "$ROOT" || exit 2
MEMORY_ROOT=memory
[ -f "$ROOT/.memory-tree.conf" ] && . "$ROOT/.memory-tree.conf"
M="$MEMORY_ROOT"
HERE="$(cd "$(dirname "$0")" && pwd)"
# The tool root is derived from where THIS script lives, not hardcoded — an adopter who installs the
# kit somewhere else gets the right substitution without editing the test.
# BOTH sides go through the same `cd … && pwd` chain first. Under MSYS/git-bash one directory has two
# spellings (`C:/projects/x` from `git rev-parse` versus `/c/projects/x` from `pwd`), and a raw
# prefix strip across those flavors silently yields an ABSOLUTE path — which then substitutes
# nothing, reports the whole tree as drift, and prints a "fix" command containing a drive letter.
ROOT_N="$(cd "$ROOT" && pwd)"
KITREL=${HERE#"$ROOT_N"/}               # e.g. tools/memory-tree
[ "$KITREL" = "$HERE" ] && { echo "kit-parity: cannot locate this kit inside the repo ($HERE vs $ROOT_N)"; exit 2; }
TOOLROOT=${KITREL%/*}                   # e.g. tools   (empty when the kit sits at the repo root)
TOOLROOT=${TOOLROOT%/}
PREFIX=""; [ -n "$TOOLROOT" ] && [ "$TOOLROOT" != "$KITREL" ] && PREFIX="$TOOLROOT/"

MODE="${1:---check}"
PAIRS="$M/HYGIENE.md:$KITREL/HYGIENE.template.md $M/TEMPLATE-SPEC.md:$KITREL/SPEC-TEMPLATE.template.md"

norm() { # strip the install prefix from the live copy, and CR so a Windows checkout compares equal
  if [ -n "$PREFIX" ]; then sed -e 's/\r$//' -e "s|$PREFIX||g" "$1"
  else sed -e 's/\r$//' "$1"; fi
}

st=0
for pair in $PAIRS; do
  live=${pair%%:*}; ship=${pair##*:}
  if [ ! -f "$live" ]; then echo "kit-parity: missing live copy $live"; st=1; continue; fi
  if [ ! -f "$ship" ]; then echo "kit-parity: missing shipped copy $ship"; st=1; continue; fi
  case "$MODE" in
    --render) norm "$live" > "$ship"; echo "kit-parity: rendered $ship from $live" ;;
    --check)
      if ! diff -q <(norm "$live") <(sed 's/\r$//' "$ship") >/dev/null; then
        echo "kit-parity: DRIFT — $ship does not match $live (after stripping the '$PREFIX' install prefix)"
        diff <(norm "$live") <(sed 's/\r$//' "$ship") | head -30 | sed 's/^/    /'
        echo "    fix: bash $KITREL/kit-dogfood-parity.test.sh --render"
        st=1
      fi ;;
    *) echo "usage: $0 [--check|--render]"; exit 2 ;;
  esac
done

# The pair list is the population, and an empty one would pass silently — the same green-by-absence
# shape checked elsewhere in this kit.
[ -n "$PAIRS" ] || { echo "kit-parity: no document pairs configured — that is not a pass"; exit 1; }
[ "$MODE" = --render ] && exit 0
[ "$st" = 0 ] && echo "kit-parity: shipped and installed docs agree (2 pairs)"
exit "$st"
