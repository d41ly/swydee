#!/usr/bin/env bash
# Self-test for check-verdict-epoch.sh. Every arm runs in a throwaway repo with a synthetic engine,
# because the arm that matters — "the engine moved and the version did not" — cannot be staged in
# this tree without leaving the merge bar red.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
GATE="$HERE/check-verdict-epoch.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fails=0
# THE EXIT CODE IS PART OF THE ASSERTION. The first cut captured `rc` and only printed it, so the
# message and the verdict were never checked together: mutating the gate's FAILED branch from
# `exit 1` to `exit 0` left all ten arms green and printed PASS, while run-gates.sh judges a leg
# purely by its exit status. A gate that has been turned into a printer is exactly the shape this
# repo exists to catch, and this harness could not see it happen to its own gate.
arm() { # label · want-rc · expected-substring · dir · [base]
  local label=$1 wantrc=$2 want=$3 dir=$4 base=${5:-}
  local out rc bad=0
  out=$(cd "$dir" && bash "$GATE" $base 2>&1); rc=$?
  [ "$rc" = "$wantrc" ] || bad=1
  case "$out" in *"$want"*) ;; *) bad=1 ;; esac
  if [ "$bad" = 0 ]; then printf 'arm ok    %s\n' "$label"; return; fi
  fails=$((fails+1))
  printf 'arm FAIL  %s — wanted rc=%s + %s, got rc=%s\n' "$label" "$wantrc" "$want" "$rc"
  printf '%s\n' "$out" | sed 's/^/      /'
}

engine() { # $1=dir $2=version $3=extra-body-line
  mkdir -p "$1/tools/memory-tree"
  { printf '#!/usr/bin/env bash\n'
    printf 'KIT_MEMORY_TREE_VERSION=%s   # gov:kit memory-tree@%s — engine identity\n' "$2" "$2"
    printf '# a comment line that never changes behaviour\n'
    printf 'echo hygiene\n'
    [ -n "$3" ] && printf '%s\n' "$3"
  } > "$1/tools/memory-tree/check-memory-hygiene.sh"
}

commit_engine() { # $1=dir $2=version $3=extra-body-line $4=message
  engine "$1" "$2" "$3"
  ( cd "$1" && git add -A && git commit -qm "$4" --no-verify ) >/dev/null
}

newrepo() { # $1=name -> echoes the dir
  local d="$TMP/$1"
  mkdir -p "$d"
  ( cd "$d" && git init -q -b main . && git config user.email t@t.test && git config user.name t \
    && git config commit.gpgsign false ) >/dev/null 2>&1
  printf '%s' "$d"
}

# ---- 1. the defect, reproduced: the engine's behaviour moves, the constant does not ----------------
A=$(newrepo moved); engine "$A" 1.5 ""
( cd "$A" && git add -A && git commit -qm base --no-verify ) >/dev/null
BASE_A=$(cd "$A" && git rev-parse HEAD)
engine "$A" 1.5 "echo an extra behaviour-bearing line"
( cd "$A" && git add -A && git commit -qm change --no-verify ) >/dev/null
arm 'an engine change with no bump FAILS' 1 'changes KIT_MEMORY_TREE_VERSION (still 1.5)' "$A" "$BASE_A"
arm '...and the remedy names all three files' 1 'kit-dogfood-parity.test.sh --render' "$A" "$BASE_A"

# ---- 1b. THE ENDPOINT HOLE. A bump ANYWHERE in the range used to satisfy this gate, so one early
# ---- bump excused every verdict change after it. These four arms are the whole of
# ---- TOOL-aBatchedTribunal-7 and none of them could exist under the endpoint rule.
H=$(newrepo topo)
commit_engine "$H" 1.5 "" base
BASE_H=$(cd "$H" && git rev-parse HEAD)
commit_engine "$H" 1.6 "echo one" "bump BUNDLED with the change"
arm 'a bump bundled with the change is clean (W == S)' 0 'the version moved 1.5 -> 1.6' "$H" "$BASE_H"
commit_engine "$H" 1.6 "echo one
echo two" "a LATER change with no bump"
arm 'a change AFTER the bump is caught' 1 'the bump is OLDER than the change it claims to date' "$H" "$BASE_H"
arm '...and the failure names both commits' 1 'last KIT_MEMORY_TREE_VERSION change' "$H" "$BASE_H"
commit_engine "$H" 1.7 "echo one
echo two" "bump placed AFTER the last change"
arm '...and re-bumping after it clears' 0 'the version moved 1.5 -> 1.7' "$H" "$BASE_H"

# A range that changes the engine and carries NO bump at all is a different message from a
# mis-ordered one — "you never dated this" and "you dated it too early" are different mistakes.
N=$(newrepo nobump)
commit_engine "$N" 1.5 "" base
BASE_N=$(cd "$N" && git rev-parse HEAD)
commit_engine "$N" 1.5 "echo one" "change, no bump anywhere"
arm 'a range with no bump at all says so' 1 'NO' "$N" "$BASE_N"

# A DECOY: the constant's LINE moves, its VALUE does not. `-G` finds the commit; the parent
# comparison must reject it, or a comment reflow on that line would launder every later change.
K=$(newrepo decoy)
commit_engine "$K" 1.5 "" base
BASE_K=$(cd "$K" && git rev-parse HEAD)
commit_engine "$K" 1.5 "echo one" "change, no bump"
( cd "$K" && sed -i 's/# gov:kit memory-tree@1.5/# gov:kit memory-tree@1.5 — engine identity, reworded/' \
    tools/memory-tree/check-memory-hygiene.sh && git add -A && git commit -qm "reword the comment ON the constant line" --no-verify ) >/dev/null
arm 'touching the constant LINE without its VALUE is not a bump' 1 'NO' "$K" "$BASE_K"

# A COMMENT-ONLY commit after a correct bump must not re-open the range: W is the newest
# BEHAVIOUR-bearing commit, not the newest touching one.
M=$(newrepo trailing)
commit_engine "$M" 1.5 "" base
BASE_M=$(cd "$M" && git rev-parse HEAD)
commit_engine "$M" 1.6 "echo one" "bump + change"
( cd "$M" && printf '# a trailing comment\n' >> tools/memory-tree/check-memory-hygiene.sh \
    && git add -A && git commit -qm "comment only, after the bump" --no-verify ) >/dev/null
arm 'a comment-only commit after the bump does not re-open it' 0 'the version moved 1.5 -> 1.6' "$M" "$BASE_M"

# A DELEGATE change after the bump is caught too — 8 of the 19 verdicts live in those modules, and
# the population is only real if a change there behaves like a change to the shell engine.
P=$(newrepo delegate)
commit_engine "$P" 1.5 "" base
BASE_P=$(cd "$P" && git rev-parse HEAD)
commit_engine "$P" 1.6 "echo one" "bump + change"
( cd "$P" && printf 'print("classify")\n' > tools/memory-tree/gotchas.py \
    && git add -A && git commit -qm "a delegate moves after the bump" --no-verify ) >/dev/null
arm 'a DELEGATE change after the bump is caught' 1 'the bump is OLDER than the change' "$P" "$BASE_P"

# ---- 2. the same range with the version bumped is clean ------------------------------------------
B=$(newrepo bumped); engine "$B" 1.5 ""
( cd "$B" && git add -A && git commit -qm base --no-verify ) >/dev/null
BASE_B=$(cd "$B" && git rev-parse HEAD)
engine "$B" 1.6 "echo an extra behaviour-bearing line"
( cd "$B" && git add -A && git commit -qm bump --no-verify ) >/dev/null
arm 'the same change WITH a bump is clean' 0 'the version moved 1.5 -> 1.6' "$B" "$BASE_B"

# ---- 3. a COMMENT-only change does not demand a bump ----------------------------------------------
# Without this the gate would demand a version bump for editing prose, and the next person would
# start bumping reflexively — which makes the constant meaningless in the other direction.
C=$(newrepo comment); engine "$C" 1.5 ""
( cd "$C" && git add -A && git commit -qm base --no-verify ) >/dev/null
BASE_C=$(cd "$C" && git rev-parse HEAD)
printf '# one more comment, and a blank line follows\n\n' >> "$C/tools/memory-tree/check-memory-hygiene.sh"
( cd "$C" && git add -A && git commit -qm prose --no-verify ) >/dev/null
arm 'a comment-only change needs no bump' 0 'no behaviour-bearing engine line moved' "$C" "$BASE_C"

# ---- 4. an INDENTED comment counts as a comment; an indented statement does not -------------------
D=$(newrepo indent); engine "$D" 1.5 ""
( cd "$D" && git add -A && git commit -qm base --no-verify ) >/dev/null
BASE_D=$(cd "$D" && git rev-parse HEAD)
printf '    # an indented comment\n' >> "$D/tools/memory-tree/check-memory-hygiene.sh"
( cd "$D" && git add -A && git commit -qm indented --no-verify ) >/dev/null
arm 'an indented comment is still a comment' 0 'no behaviour-bearing engine line moved' "$D" "$BASE_D"
printf '    echo indented statement\n' >> "$D/tools/memory-tree/check-memory-hygiene.sh"
( cd "$D" && git add -A && git commit -qm stmt --no-verify ) >/dev/null
arm '...and an indented STATEMENT is not' 1 'changes KIT_MEMORY_TREE_VERSION (still 1.5)' "$D" "$BASE_D"

# ---- 5. the misconfigured cases are NAMED, never silently green ----------------------------------
E=$(newrepo noengine)
( cd "$E" && printf 'x\n' > README.md && git add -A && git commit -qm base --no-verify ) >/dev/null
arm 'a missing engine is a named failure' 2 'is missing' "$E"
# A repo with no `main` at all — a fresh clone of a differently-named default, or a detached probe.
# The skip must SAY it skipped: silence here is indistinguishable from "the constant is fine", which
# is the exact failure this gate exists for.
F="$TMP/nomain"; mkdir -p "$F"
( cd "$F" && git init -q -b work . && git config user.email t@t.test && git config user.name t   && git config commit.gpgsign false ) >/dev/null 2>&1
engine "$F" 1.5 ""
( cd "$F" && git add -A && git commit -qm base --no-verify ) >/dev/null
arm 'an unresolvable base is a REFUSAL, not a pass' 1 'no mainline base' "$F"
arm 'a bogus base is a named failure' 2 'is not a commit in this repo' "$A" deadbeefdeadbeef

# ---- 6. this repo, right now --------------------------------------------------------------------
# The live tree must be clean, and it must be clean because the constant MOVED — not because nothing
# changed. Asserting the message discriminates the two.
# `verdict-epoch:` prefixes EVERY message this gate emits, failures included — an early cut asserted
# that and could not fail while its own comment claimed it discriminated. `clean —` appears on the
# two passing messages and on NEITHER failure, so it separates the verdicts.
#
# It cannot demand a specific clean REASON: which of the two holds depends on whether this branch
# currently carries an engine change, and both are correct answers. The arms above pin each reason to
# a fixture where only one of them can be right.
arm 'the live tree passes, and says so as a clean verdict' 0 'clean —' "$HERE/../.."

if [ "$fails" = 0 ]; then echo "PASS — check-verdict-epoch: all arms held"; exit 0; fi
echo "FAIL — $fails arm(s) failed"
exit 1
