#!/usr/bin/env bash
# adopt-memory-recall.sh — render the memory-recall Skill from `.memory-tree.conf` and converge.
#
#   memory-recall/adopt-memory-recall.sh --scaffold [--with-hook]
#   memory-recall/adopt-memory-recall.sh --check                  # gate leg: has the skill drifted?
#
# The Skill's `description` is the whole trigger mechanism and it names project values (the id
# families, the query-script path, the corpus root), so the skill is GENERATED from the conf rather
# than shipped. `--check` re-renders and diffs, which is how a `FAMILIES` edit that nobody
# re-rendered turns into a red leg instead of a silently stale trigger.
#
# `--with-hook` is the ONLY way the `recall-opened` PostToolUse hook is installed. Skipping it is a
# supported end state: a hook file copied in but never merged into settings.json reads as UNWIRED
# forever, which is the fastest way to train every node to ignore the wiring verifier.
#
# The interpreter is resolved python3-first with a `python` fallback (the tools/check-wiring.sh:69
# form), overridable with RECALL_PY. `--check` is a merge-bar leg, and a stock Debian/Ubuntu adopter
# without `python-is-python3` would red the whole gate suite on a working kit if this defaulted to
# bare `python`. The gate runner's argv rewrite cannot rescue it — this leg's argv[0] is `bash`.
set -u

# HERE BEFORE the cd: `$0` may be relative, and resolving it after moving to the root resolves it
# against the wrong directory (measured — it found `C:/Program Files/Git/recall_conf.py`).
HERE="$(cd "$(dirname "$0")" && pwd)" || exit 2
ROOT="$(git rev-parse --show-toplevel)" || exit 2
cd "$ROOT" || exit 2
# Re-read it through `pwd`: git spells the root `C:/x` under MSYS while `pwd` spells it `/c/x`, and
# every path this script joins against ROOT should be in the shell's own spelling.
ROOT="$(pwd)"
# The kit dir as the adopting repo spells it, RELATIVE. git computes it, so the two operands
# cannot be two spellings of one directory: stripping a `pwd`-derived ROOT off a `pwd`-derived
# HERE still no-ops under an MSYS mount alias, and REL then comes out ABSOLUTE and machine-local
# — measured, the same tree at the same commit gave --check EXIT 0 from one spelling and a
# three-hunk DRIFTED diff from the other, and --scaffold writes that into a COMMITTED artifact
# silently. Works whether the kit sits at <root>/memory-recall/ or <root>/tools/memory-recall/.
REL="$(cd "$HERE" && git rev-parse --show-prefix)" || exit 2
REL="${REL%/}"

PY="${RECALL_PY:-}"
if [ -z "$PY" ]; then PY=python3; command -v python3 >/dev/null 2>&1 || PY=python; fi

mode=""; with_hook=0
for a in "$@"; do
  case "$a" in
    --scaffold|--check) mode="$a" ;;
    --with-hook) with_hook=1 ;;
    *) echo "usage: $0 --scaffold [--with-hook] | --check   (RECALL_PY overrides the launcher)"; exit 2 ;;
  esac
done
[ -n "$mode" ] || { echo "usage: $0 --scaffold [--with-hook] | --check"; exit 2; }

# The conf refusal lives in ONE place — recall_conf.py prints it, this script just forwards it.
conf="$("$PY" "$HERE/recall_conf.py")" || exit 1
# Belt-and-braces against a CR-bearing producer. recall_conf.py now pins LF on its KEY=VALUE
# protocol, but `read` would otherwise hand every value a trailing CR on Windows, and those CRs
# rendered straight into SKILL.md (`memory<CR>/`) and broke its YAML frontmatter. Stripping here
# keeps the consumer correct even against an older or third-party producer.
conf="${conf//$'\r'/}"
memory_root=""; families=""
while IFS='=' read -r k v; do
  case "$k" in MEMORY_ROOT) memory_root="$v" ;; FAMILIES) families="$v" ;; esac
done <<EOF
$conf
EOF

TEMPLATE="$HERE/SKILL.template.md"
SKILL_DIR="$ROOT/.claude/skills/memory-recall"
SKILL="$SKILL_DIR/SKILL.md"

# Three states, not two. The Skill surface is a separate artifact in this kit directory; when it is
# not installed there is nothing to render and nothing that can drift, so `--check` SKIPS rather
# than reds (a red an adopter cannot fix by editing their own repo trains them to ignore the leg).
# A rendered SKILL.md with no template is the one genuinely unverifiable state, and it reds.
if [ ! -f "$TEMPLATE" ]; then
  if [ -f "$SKILL" ]; then
    echo "memory-recall: $SKILL exists but $REL/SKILL.template.md does not — cannot verify drift"; exit 1
  fi
  echo "skip     memory-recall skill — $REL/SKILL.template.md not installed, nothing to render"
  [ "$mode" = "--check" ] && exit 0
  exit 1
fi

# `python3` LITERAL, not the resolved $PY: this render is a COMMITTED artifact shared across a
# fleet, so baking one node's answer reds --check on every node that resolves differently. Bare
# `python` is not an option either — a stock Debian/Ubuntu adopter without python-is-python3 has
# only python3, and every command in the kit's primary agent-facing surface would exit 127.
render() { # -> stdout
  sed -e "s|{{FAMILIES}}|$families|g" \
      -e "s|{{MEMORY_ROOT}}|$memory_root|g" \
      -e "s|{{QUERY_CLI}}|python3 $REL/query.py|g" "$TEMPLATE"
}

# An unsubstituted placeholder is a template that grew a value this script does not know how to
# fill — silently shipping `{{...}}` into a Skill description would break the trigger, so it reds.
leftover="$(render | grep -o '{{[A-Z_]*}}' | sort -u | tr '\n' ' ')"
if [ -n "$leftover" ]; then
  echo "memory-recall: unsubstituted placeholder(s) in SKILL.template.md: $leftover"; exit 1
fi

if [ "$mode" = "--check" ]; then
  [ -f "$SKILL" ] || { echo "memory-recall: $SKILL not rendered — run $REL/adopt-memory-recall.sh --scaffold"; exit 1; }
  if render | diff -q - "$SKILL" >/dev/null 2>&1; then
    echo "ok       memory-recall skill — SKILL.md matches the conf (FAMILIES: $families)"
    exit 0
  fi
  echo "memory-recall: .claude/skills/memory-recall/SKILL.md has DRIFTED from .memory-tree.conf."
  render | diff -u "$SKILL" - | head -40
  echo "Fix: $REL/adopt-memory-recall.sh --scaffold"
  exit 1
fi

mkdir -p "$SKILL_DIR"
render > "$SKILL.tmp" && mv "$SKILL.tmp" "$SKILL" || exit 1
echo "rendered $SKILL (FAMILIES: $families, corpus: $memory_root)"

if [ "$with_hook" = 1 ]; then
  if [ ! -f "$HERE/recall-opened.js" ]; then
    echo "memory-recall: --with-hook asked for, but $REL/recall-opened.js is not installed"; exit 1
  fi
  mkdir -p "$ROOT/.claude/hooks"
  cp "$HERE/recall-opened.js" "$ROOT/.claude/hooks/recall-opened.js"
  echo "installed .claude/hooks/recall-opened.js — now merge it into settings.json:"
  # RESOLVED, not hardcoded — this is the last instruction an adopter sees at the moment they take
  # the opt-in, and the step whose omission leaves the hook inert. A hardcoded tools/ path printed
  # here died with errno 2 in an adopter, because no runbook step delivered the tool. WIRE §3c
  # step 4 now copies it to tools/; when it still is not there, say so instead of pretending.
  smerge=""
  for c in tools/settings-merge.py settings-merge.py; do [ -f "$ROOT/$c" ] && { smerge="$c"; break; }; done
  if [ -z "$smerge" ]; then
    echo "  cp <gov>/tools/settings-merge.py tools/     # not installed here yet (WIRE §3c step 4)"
    smerge=tools/settings-merge.py
  fi
  echo "  $PY $smerge --fragment $REL/recall-opened.fragment.json"
fi

echo "Adopted. Next:"
echo "  1. Add both legs to your gate runner AND your CI config (see WIRE-INTO-PROJECT.md):"
echo "       $PY $REL/selftest.py"
echo "       bash $REL/adopt-memory-recall.sh --check"
echo "     Without this the skill-drift check silently never runs."
echo "  2. Re-run --scaffold after any FAMILIES/MEMORY_ROOT edit; --check reds until you do."
