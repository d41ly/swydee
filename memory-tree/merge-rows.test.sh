#!/usr/bin/env bash
# Fixtures for the row-keyed merge driver (aMendedLedger U9; upstream ARCH-dQuarriedLedger-1 U9 S4).
#
# THE CONTROL RUNS IN EVERY CASE; THE ARITHMETIC BAR BINDS WHERE GIT RESOLVES. Say it precisely,
# because the imprecise version is the failure this file exists to stop. Every `run` case executes
# `git merge-file` on the identical three blobs. The MECHANICAL never-worse comparison — the driver
# may not lose a line the control keeps, nor at rc 0 write a row the control does not — can only
# bind where the control EXITS 0, because only then is its output an ANSWER rather than a conflict
# to be resolved by hand. Measured: 12 of the 34 `run` cases, floored below at `NEVER_WORSE_FLOOR`
# so that a fixture edit flipping a control from rc 0 to rc 1 cannot quietly drop a case out of the
# bar while the group count stays the same. The other 22 are held by the id-set oracle, the
# duplicate-id oracle, and per-case assertions on bytes. Conflicting where git resolves CORRECTLY is
# acceptable and is counted by name against a shrink-only constant, never absorbed.
#
# That bar exists because a green suite has twice signed off on corruption here. Three adversarial
# rounds each closed the reported defect and opened a new one in the handling of unkeyed content, and
# two of those regressions passed a green 38-leg bar: `PASS — 28 fixture groups held` was printed on
# a tree that doubled a heading in `memory/DECISIONS.md` at rc 0 and on one that deleted a
# legitimately repeated note from an append-only record at rc 0. The fix is not more fixtures of the
# same kind — it is that every case now runs a LIVE control on the identical three blobs and the
# comparison is arithmetic rather than a hand-typed expectation. Two of twenty-eight groups did that
# before; all of them do now.
#
# The other structural lesson: an id-set oracle cannot see a duplicate, and a `sort -u` set
# comparison over two empty sets holds for the wrong reason. So every rc-0 arm also asserts no id
# occurs twice, the oracle is pointed at a row shape the driver's own grammar cannot key, and every
# half of the oracle is proved live in case 0d before anything leans on it.
#
#   bash tools/memory-tree/merge-rows.test.sh
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SELF="$HERE/$(basename "$0")"
ROOT="$(cd "$HERE/../.." && pwd)"
cd "$ROOT" || exit 2
st=0
TMP=$(mktemp -d); SCRATCH=""
cleanup() { cd "$ROOT" 2>/dev/null || true; rm -rf "$TMP" $SCRATCH; }
trap cleanup EXIT

# The interpreter comes from the ONE resolver, never from a launcher name typed here: a name that is
# on PATH and cannot run is the Microsoft-Store-stub defect the resolver exists for.
# shellcheck source=/dev/null
. "$ROOT/tools/lib/resolve-python.sh"
PY=$(resolve_python) || { echo "FAIL no usable python on this host — every arm below is unrunnable"; exit 2; }

DRV="bash tools/lib/pyrun.sh tools/memory-tree/merge-rows.py"
bad() { echo "FAIL $1"; st=1; }

# THE ORACLE — a family-agnostic id shape, deliberately NOT the driver's grammar. Keying the
# assertion on the same regex the driver keys the merge on would make every arm self-consistent and
# blind: a grammar that stopped recognising a row would remove it from BOTH sides of the comparison.
# THE `[a-z]*` TAIL IS THE POINT, not a tidy-up. Without it the oracle shared the driver grammar's
# trailing `\b`, so this corpus's ratified correction-id form (`…-1b`) fell out of BOTH sides of
# every comparison here — measured on the real memory/DECISIONS.md at 38 of 73 rows unkeyed then. The
# driver grammar has since caught up on that form (memory-recall kit 1.1 widened the session era, and
# the same file now keys 73 of 73), and the tail is STILL load-bearing for a different reason: the
# unkeyable population is now separator-shaped rather than era-shaped, and its ids carry the same
# suffixes. The remedy for a blind spot the oracle shares with the subject is to WIDEN the oracle,
# never to point it at the driver's regex.
ORACLE='\b[A-Z]+-[A-Za-z0-9]+-[0-9]+[a-z]*\b'
ids() { grep -ohE "$ORACLE" "$@" 2>/dev/null | LC_ALL=C sort -u | tr '\n' ' '; }
# ...and the same oracle asked the other question. `sort -u` above makes `ids` structurally unable to
# report a duplicate, which is exactly how a doubled row passed an id-SET comparison.
dups() { grep -ohE "$ORACLE" "$@" 2>/dev/null | LC_ALL=C sort | uniq -d | tr '\n' ' '; }
minus() {  # $1 = a space-separated set · rest = members the honoured deletes removed
  local all=$1 t d keep out=""; shift
  for t in $all; do
    keep=1; for d in "$@"; do [ "$t" = "$d" ] && keep=0; done
    [ "$keep" = 1 ] && out="$out$t "
  done
  printf '%s' "$out"
}
row() { printf -- '- %s · OPEN · %s\n' "$1" "$2"; }
pre() { printf '# Index\n\nRouting prose, unkeyable by design.\n\n'; }
# The line number of the FIRST match, or 0. Both halves matter: the placement arms below compare two
# line numbers, and the defect they were written for DUPLICATES a heading — so an un-headed
# `grep -n | cut` hands `[` two numbers on two lines and bash aborts the comparison with
# `integer expected` instead of the arm reporting anything. A missing match answers 0, and every
# caller tests for that EXPLICITLY — 0 wins a `-lt` against any real line number, so a vanished row
# would otherwise satisfy the placement it was supposed to prove.
at_line() { local n; n=$(grep -n -- "$1" "$2" 2>/dev/null | head -1 | cut -d: -f1); printf '%s' "${n:-0}"; }
# The two multisets the never-worse comparison is arithmetic over, as SORTED LINE LISTS rather than
# `uniq -c` tallies: `comm` on two sorted files already respects multiplicity, and reconstructing a
# line from a counted tally loses its leading whitespace to awk's field splitting — which is exactly
# the `  - notes` sub-bullet shape case 30 turns on.
#
# Trailing whitespace is stripped on BOTH sides, for `census()`'s reason: the question is content,
# not endings, and a CRLF file compared against itself must not read as a difference. Stripping
# rather than relying on grep to hide the CR is deliberate — this repo's other CR assertions need
# `grep -U` precisely because the default is platform-dependent, and a comparison whose correctness
# depends on which grep a node ships is not a bar.
allnorm() { LC_ALL=C sed 's/[[:space:]]*$//' "$1" 2>/dev/null | LC_ALL=C sort; }
rownorm() { LC_ALL=C grep -hE '^[[:space:]]*[-*][[:space:]]' "$1" 2>/dev/null | LC_ALL=C sed 's/[[:space:]]*$//' | LC_ALL=C sort; }

# THE CONSERVATIVE TALLY (AC3). A case where the driver CONFLICTS and the control RESOLVES CORRECTLY
# is noise rather than damage — but a redesign that trades one fix for one new conflict must be
# visible rather than absorbed, so the members are named and the count is a SHRINK-ONLY constant.
# Measured at 0 on this suite: every case where the driver refuses, the control refuses too, or the
# control resolves INCORRECTLY (it duplicates) and the case declares `ctl_wrong`. Lower it only by
# deleting a member; raising it needs the same justification any other ratchet raise does.
# ONE member, named: `a row ours MOVED and theirs DELETED` (group 40) and its mirror. Raised from 0
# to 1 by TOOL-aMendedLedger-9, and the raise is the ratchet WORKING rather than being defeated: it
# buys back an rc-0 CONTENT LOSS — a record silently dropped where `git merge-file` keeps it,
# confirmed auto-committed through a real `git merge` — at the price of a scoped conflict on the one
# shape where the row plane and the skeleton genuinely disagree about intent. Shrink-only from here:
# lower it by deleting a member, never by absorbing a new one.
CONSERVATIVE_CAP=2
CONSERVATIVE=""
# How many `run` cases the arithmetic comparison actually BINDS on. A GROW-ONLY floor: without
# it, a fixture edit that flips a control from rc 0 to rc 1 silently removes a case from the
# mechanical bar and the suite still prints PASS with the same group count. Measured at 12.
NEVER_WORSE_FLOOR=12
NEVER_WORSE_BOUND=0
# Cases where `git merge-file` exits 0 with a WRONG result — it duplicates a row-shaped line at rc 0,
# which is the single corruption class git commits and the whole justification for this driver. The
# never-worse comparison is meaningless against a corrupt reference, so these declare it and are
# exempt from the tally too: refusing where git silently duplicates is the unit working.
CTLWRONG=0
ctl_wrong() { CTLWRONG=1; }

# $1 label · $2 expected rc · $3 expected id set · rest: ids an honoured delete removed
#
# Runs the CONTROL first, on the identical three blobs, because the driver overwrites %A. Then the
# driver. Then: the declared id set, the observed rc, the no-duplicate-id oracle, and the mechanical
# never-worse comparison. Every case in this file goes through here — AC1.
run() {
  local label=$1 want_rc=$2 want_ids=$3 rc u expect got d wrong=$CTLWRONG; shift 3
  CTLWRONG=0
  u=$(ids "$TMP/o" "$TMP/a" "$TMP/b")            # BEFORE the driver overwrites %A
  expect=$(minus "$u" "$@")
  [ "$expect" = "$want_ids" ] \
    || bad "$label: the declared id set [$want_ids] is not the input union minus the declared deletes [$expect]"
  cp "$TMP/a" "$TMP/ctlin"
  git merge-file -p -L ours -L base -L theirs "$TMP/ctlin" "$TMP/o" "$TMP/b" > "$TMP/ctl" 2>/dev/null && crc=0 || crc=$?
  $DRV "$TMP/o" "$TMP/a" "$TMP/b" x >/dev/null 2>&1 && rc=0 || rc=$?
  [ "$rc" = "$want_rc" ] || bad "$label: rc=$rc, expected $want_rc (the control exited $crc)"
  got=$(ids "$TMP/a")
  [ "$got" = "$want_ids" ] || bad "$label: ids [$got], expected [$want_ids]"
  # THE SECOND ORACLE, and it runs on the OBSERVED rc, never the expected one. A conflict legitimately
  # writes one id twice (case 2 is built on exactly that), so a blanket no-duplicate rule would red
  # the arm that proves the driver conflicts instead of duplicating. But keying on `want_rc` would
  # exempt precisely the regression this exists to catch — a driver that was SUPPOSED to conflict and
  # exited 0 instead would have its duplicate skipped along with its rc. rc 0 is the regime where a
  # duplicate is invisible: no markers, nothing unmerged, the file quietly wrong.
  if [ "$rc" = 0 ]; then
    d=$(dups "$TMP/a")
    [ -z "$d" ] || bad "$label: rc 0 and the written file carries a DUPLICATE id [$d]"
  fi
  never_worse "$label" "$rc" "$crc" "$wrong"
}

# THE NEVER-WORSE COMPARISON — AC2, and it is arithmetic, not a judgement.
#
# It binds when the CONTROL exits 0, because only then is the control's output an ANSWER rather than
# a conflict to be resolved by hand. Two classes:
#   LOSS  — any line the control writes more often than the driver does. Unconditional on the
#           driver's rc: a conflict writes BOTH sides, so a refusal is never an excuse for losing a
#           line git kept.
#   DUP   — any ROW-SHAPED line the driver writes more often than the control does, when the driver
#           exits 0. Restricted to rc 0 because a conflict repeats content between its markers by
#           construction, and restricted to rows because a heading legitimately repeating in two
#           sections is the merge git itself performs.
# And when the driver refuses where the control resolved correctly, the case joins the tally.
never_worse() {  # $1 label · $2 driver rc · $3 control rc · $4 control-is-wrong
  local label=$1 rc=$2 crc=$3 wrong=$4 lost extra
  [ "$crc" = 0 ] || return 0
  [ "$wrong" = 1 ] && return 0
  NEVER_WORSE_BOUND=$((NEVER_WORSE_BOUND+1))
  allnorm "$TMP/ctl" > "$TMP/nw.ctl"; allnorm "$TMP/a" > "$TMP/nw.drv"
  lost=$(LC_ALL=C comm -23 "$TMP/nw.ctl" "$TMP/nw.drv" | head -3)
  [ -z "$lost" ] \
    || bad "$label: LOSS — git resolved this input at rc 0 and the driver's file does not carry: $(printf '%s' "$lost" | tr '\n' '|')"
  if [ "$rc" = 0 ]; then
    rownorm "$TMP/ctl" > "$TMP/nw.ctlr"; rownorm "$TMP/a" > "$TMP/nw.drvr"
    extra=$(LC_ALL=C comm -13 "$TMP/nw.ctlr" "$TMP/nw.drvr" | head -3)
    [ -z "$extra" ] \
      || bad "$label: DUP — at rc 0 the driver writes row line(s) the control does not: $(printf '%s' "$extra" | tr '\n' '|')"
  else
    CONSERVATIVE="$CONSERVATIVE
  $label"
  fi
}

# --- 0. the ORACLE is live, on a named population -------------------------------------------------
# `pop_guard` idiom: a set comparison whose two sides are both empty holds for the wrong reason, and
# two of this corpus's four backlog shards legitimately carry zero anchors.
{ pre; row TOOL-zFixture-1 base; row TOOL-zFixture-2 base; row TOOL-zFixture-3 base; } > "$TMP/oracle"
[ "$(ids "$TMP/oracle")" = "TOOL-zFixture-1 TOOL-zFixture-2 TOOL-zFixture-3 " ] \
  || bad "oracle: a 3-row fixture did not yield its three ids — every id-set arm below is vacuous"
[ -n "$(ids memory/DECISIONS.md)" ] \
  || bad "oracle: the real memory/DECISIONS.md yielded NO ids — the oracle does not see this corpus"
# ...and the never-worse comparison's own instruments, before any arm leans on them.
printf -- '- a row\n- a row  \n# not a row\n' > "$TMP/bagfix"
[ "$(rownorm "$TMP/bagfix" | grep -c '^- a row$')" = 2 ] \
  || bad "rownorm: a doubled row did not survive as TWO lines — comm respects multiplicity only if the bag does, and the DUP half is vacuous without it"
[ "$(rownorm "$TMP/bagfix" | grep -c 'not a row')" = 0 ] \
  || bad "rownorm: a non-row line is in the row bag, so the DUP half would fire on a legitimately repeated heading"
[ "$(allnorm "$TMP/bagfix" | grep -c 'not a row')" = 1 ] \
  || bad "allnorm: a non-row line is invisible to the LOSS half, which is not restricted to rows"
printf -- '- a row\r\n' > "$TMP/bagcrlf"; printf -- '- a row\n' > "$TMP/baglf"
[ "$(allnorm "$TMP/bagcrlf")" = "$(allnorm "$TMP/baglf")" ] \
  || bad "allnorm: a CRLF line does not normalise to its LF twin, so every never-worse comparison on a CRLF fixture reads as total LOSS"

# --- 0a. the driver PARSES under the interpreter the shim actually resolves -----------------------
"$PY" -c 'import py_compile,sys; py_compile.compile(sys.argv[1], cfile=sys.argv[2], doraise=True)' \
      tools/memory-tree/merge-rows.py "$TMP/mr.pyc" >/dev/null 2>&1 \
  || bad "merge-rows.py does not compile under the resolved interpreter ($PY)"

# ...and the version-INDEPENDENT half of the same concern, which py_compile on a modern node cannot
# see: `f"{"CONFLICT" if … else "clean"}"` is a nested SAME-quote f-string, PEP 701, valid only on
# 3.12+. `resolve_python` imposes NO version floor, so the interpreter a node hands this driver is
# whatever it has, and a driver that fails to START exits non-zero without writing %A — git then
# leaves OURS-only content with no markers. Upstream's arm needed `uv python find 3.11` and SKIPPED
# where uv was absent; this repo depends on uv nowhere, so a skippable arm would be a silent hole.
FSTR='f"[^"]*\{[^}"]*"'
nested=$(awk '!/^[[:space:]]*#/' tools/memory-tree/merge-rows.py | grep -nE "$FSTR" || true)
[ -z "$nested" ] || { echo "FAIL merge-rows.py carries a nested same-quote f-string (PEP 701, 3.12+):"; printf '%s\n' "$nested" | sed 's/^/    /'; st=1; }
# ...the ban FIRES on the shape it bans, or "clean" means "the predicate is broken".
printf 'v = f"{"X" if c else "y"}"\n' > "$TMP/pep701.py"
grep -qE "$FSTR" "$TMP/pep701.py" || bad "the PEP-701 predicate does not match the shape it bans"
# ...and does NOT fire on an ordinary f-string, or every interpolation in the driver reds.
printf 'v = f"{a} row(s) from {b}"\n' > "$TMP/plain.py"
grep -qE "$FSTR" "$TMP/plain.py" && bad "the PEP-701 predicate fires on an ordinary f-string"
# ...the comment exemption, with its own red half: the driver DOCUMENTS the banned shape in a comment,
# and a predicate that fires on the prose explaining a fix is this repo's catalogued self-inflicted red.
printf '# v = f"{"X" if c else "y"}"\n' > "$TMP/comment.py"
[ -z "$(awk '!/^[[:space:]]*#/' "$TMP/comment.py" | grep -E "$FSTR" || true)" ] \
  || bad "the PEP-701 ban fires on a COMMENT explaining the shape"
printf 'v = f"{"X" if c else "y"}"\n' > "$TMP/comment.py"
[ -n "$(awk '!/^[[:space:]]*#/' "$TMP/comment.py" | grep -E "$FSTR" || true)" ] \
  || bad "the SAME line uncommented is exempt too — the comment strip is doing nothing"

# --- 0b. the launcher shim's contract -------------------------------------------------------------
# (i) no arguments -> exit 2, and the usage text carries the four placeholders. Upstream prints
# `__doc__.split("\n\n")[0]` — the summary sentence alone — so its refusal never says how to wire the
# driver it is refusing to run.
out=$($DRV 2>&1 >/dev/null); rc=$?
[ "$rc" = 2 ] || bad "no-argument invocation exited $rc, expected 2"
for ph in '%O' '%A' '%B' '%P'; do
  printf '%s\n' "$out" | grep -qF -- "$ph" || bad "the usage text does not carry the $ph placeholder"
done
# (ii) the shim HALTS on the resolver's return value rather than falling through. The arm has to
# shadow ALL THREE launcher names first: `resolve_python` returns on the first candidate that RUNS,
# so an unusable GOV_PYTHON on a host with a working python3 resolves to python3 and exits 0 BY
# DESIGN — the named-failure block is unreachable until every candidate is dead.
mkfake() { mkdir -p "$1"; printf '#!/usr/bin/env bash\nexit %s\n' "$3" > "$1/$2"; chmod +x "$1/$2"; }
C="$TMP/allbad"; mkfake "$C" python3 9009; mkfake "$C" python 9009; mkfake "$C" py 9009
out=$(PATH="$C:$PATH" GOV_PYTHON="$C/python3" $DRV 2>&1); rc=$?
[ "$rc" = 2 ] || bad "the shim exited $rc with no usable launcher, expected 2"
printf '%s\n' "$out" | grep -qF "GOV_PYTHON is set to '$C/python3' and did not run" \
  || bad "the shim did not surface the resolver's named GOV_PYTHON failure"
# (iii) the shim SOURCES the resolver, so it must NOT carry the inline-copy marker block — that
# population is derived by grep, and enlisting the shim would put it in a parity gate it has no
# reason to be in.
copies=$(git grep -l '^# >>> resolve_python' -- '*.sh' || true)
[ -n "$copies" ] || bad "no inline resolver copy found — the marker-population assertion below is vacuous"
printf '%s\n' "$copies" | grep -qx 'tools/lib/pyrun.sh' \
  && bad "tools/lib/pyrun.sh carries the resolver marker block; it SOURCES the resolver instead"

# --- 0c. FAIL CLOSED: every deferred-resolution failure becomes a conflict, never a take-ours ------
# The driver reads its anchor grammar from the worktree at merge time. At module scope that import
# failing killed the process before %A was written — git then leaves OURS-only content with no
# markers, and the incoming rows are gone with nothing saying so. The import is deferred so all three
# failures land in main()'s fail-closed handler. Simulated on scratch trees rather than by breaking
# the real kit under a concurrently-running gate. This is corpus case C18, the worst class in it, and
# the redesign does not touch the property — so it is re-proven here rather than assumed (AC17).
failclosed() {  # $1 label · $2 scratch tree holding tools/memory-tree/merge-rows.py
  { pre; row TOOL-zFixture-1 base; } > "$TMP/o"
  { pre; row TOOL-zFixture-1 base; } > "$TMP/a"
  { pre; row TOOL-zFixture-1 base; row TOOL-zFixture-2 INCOMING; } > "$TMP/b"
  if "$PY" "$2/tools/memory-tree/merge-rows.py" "$TMP/o" "$TMP/a" "$TMP/b" x >/dev/null 2>&1; then
    bad "$1: the driver reported SUCCESS with no resolvable anchor grammar"
  fi
  grep -q 'INCOMING' "$TMP/a" || bad "$1: the incoming row vanished — this is the silent-take-ours shape"
  grep -q '^<<<<<<< ours$' "$TMP/a" || bad "$1: no conflict markers written"
}
mkscratch() { local d; d=$(mktemp -d); SCRATCH="$SCRATCH $d"
  mkdir -p "$d/tools/memory-tree" "$d/tools/memory-recall"
  cp tools/memory-tree/merge-rows.py "$d/tools/memory-tree/"
  printf '%s' "$d"; }
S=$(mkscratch); cp .memory-tree.conf "$S/"
printf 'this is not valid syntax(\n' > "$S/tools/memory-recall/extract.py"
failclosed "broken grammar" "$S"
S=$(mkscratch); cp .memory-tree.conf "$S/"          # kit dir present, extract.py absent
failclosed "missing grammar module" "$S"
S=$(mkscratch)                                       # no .memory-tree.conf above the driver
cp tools/memory-recall/extract.py tools/memory-recall/recall_conf.py "$S/tools/memory-recall/"
failclosed "missing .memory-tree.conf" "$S"

# --- 0d. the oracle sees a row the driver's grammar does NOT, and `dups` fires ---------------------
# The oracle earns its keep only if it can see something the subject cannot; otherwise "independent"
# is a comment, not a property. All of it is proved here, in both directions, before any arm below
# leans on it: the oracle KEYS the unkeyable row, the driver's own `key()` returns None for the
# identical line, a row with NO id is keyed by neither, `dups` REPORTS a repeat, and `dups` stays
# silent on a singleton.
#
# THE UNKEYABLE SHAPE MOVED, and this block is where that is caught rather than assumed. It used to
# be `- TOOL-zFixture-9b · …`: the shared session era was bounded by `\b`, so a trailing letter
# killed the match. memory-recall kit 1.1 widened that era to `\d+[a-z]*` — 35 of this corpus's 73
# rows keyed before, 73 of 73 after — and that line became an ordinary keyed row. The arm below is
# what SAID SO: on the widening it failed with the message it still carries, rather than passing
# while asserting nothing about a subject that had caught up with its oracle.
#
# The shape it moved TO is structural, not lexical. Every anchor pattern requires a separator after
# the id (`[-—:·]` or `[·|]`); `$ORACLE` requires nothing after it. So a row-shaped line carrying an
# id and no separator is unkeyable under ANY era the grammar may grow, which is the property the
# previous fixture lacked. Under the redesign such a line is not "content" any more — it is a ROW on
# a `raw:` key, hashed rather than keyed — and that is what case 24 exercises.
NOSEP='- TOOL-zFixture-9b carries an id and no anchor separator, so no anchor pattern matches it'
KEYED='- TOOL-zFixture-9b · the same id WITH a separator, which the widened grammar keys'
SUFFIXED="$NOSEP"     # every arm below that needs an unkeyable row uses this name
NOID='- a row with no id at all, which neither the oracle nor the driver can key'
printf '%s\n' "$NOSEP" > "$TMP/suffixed"
[ "$(ids "$TMP/suffixed")" = "TOOL-zFixture-9b " ] \
  || bad "oracle: the oracle does not see the id on an unkeyable row — case 12 would assert nothing"
keys() {  # $1=line -> 0 if the DRIVER keys it, 1 if not
  "$PY" - "$1" <<'PYEOF'
import importlib.util, sys
sys.dont_write_bytecode = True   # a test that leaves __pycache__ in tools/ dirties the tree it gates
spec = importlib.util.spec_from_file_location("mr", "tools/memory-tree/merge-rows.py")
mr = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mr)
sys.exit(0 if mr.key(sys.argv[1] + "\n") is not None else 1)
PYEOF
}
keys "$NOSEP" \
  && bad "oracle: the DRIVER keys the separator-less row, so the oracle is no wider than the subject — pick a shape the grammar really misses"
keys "$KEYED" \
  || bad "oracle: the driver does NOT key [$KEYED] — the unkeyable half of case 0d is unfalsifiable, because a grammar recognising nothing passes it too"
printf '%s\n' "$NOID" > "$TMP/noid"
[ -z "$(ids "$TMP/noid")" ] || bad "oracle: a row with NO id yielded an id — the oracle is matching text that is not one"
keys "$NOID" && bad "oracle: the driver keyed a row with no id at all"
{ printf '%s\n' "$NOSEP"; printf '%s\n' "$NOSEP"; } > "$TMP/twice"
[ "$(dups "$TMP/twice")" = "TOOL-zFixture-9b " ] \
  || bad "dups: a doubled id was not reported — every rc-0 arm's duplicate half is vacuous"
[ -z "$(dups "$TMP/suffixed")" ] || bad "dups: a singleton id was reported as a duplicate"

# --- 1. disjoint appends — the case the unit is FOR -----------------------------------------------
{ pre; row TOOL-zFixture-1 base; } > "$TMP/o"
{ pre; row TOOL-zFixture-1 base; row TOOL-zFixture-2 ours; } > "$TMP/a"
{ pre; row TOOL-zFixture-1 base; row TOOL-zFixture-3 theirs; } > "$TMP/b"
run "disjoint appends" 0 "TOOL-zFixture-1 TOOL-zFixture-2 TOOL-zFixture-3 "

# --- 2. the shape that broke union: same id, different text, both sides ---------------------------
{ pre; row TOOL-zFixture-1 base; } > "$TMP/o"
{ pre; row TOOL-zFixture-1 ours; } > "$TMP/a"
{ pre; row TOOL-zFixture-1 theirs; } > "$TMP/b"
run "same id both sides" 1 "TOOL-zFixture-1 "
n=$(grep -c '^- TOOL-zFixture-1 ' "$TMP/a")
[ "$n" = 2 ] || bad "union-shape: expected both texts inside markers, got $n TOOL-zFixture-1 lines"
grep -q '^<<<<<<< ours$' "$TMP/a" || bad "union-shape: no conflict marker written"

# --- 3. one side edits, the other does not — take the change, silently ----------------------------
{ pre; row TOOL-zFixture-1 base; } > "$TMP/o"
{ pre; row TOOL-zFixture-1 base; } > "$TMP/a"
{ pre; row TOOL-zFixture-1 theirs; } > "$TMP/b"
run "one-sided edit" 0 "TOOL-zFixture-1 "
grep -q 'theirs' "$TMP/a" || bad "one-sided edit: took ours, not the side that changed"

# --- 4. a row deleted on one side — honour the delete, do not resurrect ---------------------------
{ pre; row TOOL-zFixture-1 base; row TOOL-zFixture-2 base; } > "$TMP/o"
{ pre; row TOOL-zFixture-1 base; row TOOL-zFixture-2 base; } > "$TMP/a"
{ pre; row TOOL-zFixture-1 base; } > "$TMP/b"
run "delete honoured" 0 "TOOL-zFixture-1 " TOOL-zFixture-2

# --- 4b. DELETE/MODIFY, both directions — the interaction that lost data upstream -----------------
# Case 4 only ever deletes a row NEITHER side touched, so both mixed cases walk straight through: the
# driver honours the delete, discards the other side's EDIT, and exits 0 "clean". Git conflicts on
# delete/modify precisely because neither resolution is the tool's to choose.
{ pre; row TOOL-zFixture-1 base; row TOOL-zFixture-2 base; } > "$TMP/o"
{ pre; row TOOL-zFixture-1 base; } > "$TMP/a"
{ pre; row TOOL-zFixture-1 base; row TOOL-zFixture-2 EDITED; } > "$TMP/b"
run "ours deleted, theirs edited" 1 "TOOL-zFixture-1 TOOL-zFixture-2 "
grep -q 'EDITED' "$TMP/a" || bad "delete/modify: theirs' edit was DISCARDED"

{ pre; row TOOL-zFixture-1 base; row TOOL-zFixture-2 base; } > "$TMP/o"
{ pre; row TOOL-zFixture-1 base; row TOOL-zFixture-2 EDITED; } > "$TMP/a"
{ pre; row TOOL-zFixture-1 base; } > "$TMP/b"
run "ours edited, theirs deleted" 1 "TOOL-zFixture-1 TOOL-zFixture-2 "
grep -q 'EDITED' "$TMP/a" || bad "modify/delete: ours' edit was DISCARDED"

# --- 4c. conflict markers name ours/theirs, never a scratch path ----------------------------------
grep -q '^<<<<<<< ours$' "$TMP/a" || bad "markers: no ours marker"
if grep -qE '^(<<<<<<<|>>>>>>>|\|\|\|\|\|\|\|).*[A-Za-z]:[\\/]' "$TMP/a"; then
  bad "markers: a conflict marker carries an absolute path instead of ours/theirs"
fi

# --- 5. an unkeyable line INSIDE the row block keeps its position ---------------------------------
# Measured on this corpus: `## KICK — kickoff`, `## TOOL — tooling` and the `*(none yet)*` placeholder
# sit between anchored rows. A driver that hoisted them to the end would corrupt the file while
# exiting 0 — which is what the retired three-region model did on its first cut.
{ pre; row TOOL-zFixture-1 base; printf '\n## Section two\n\n'; row TOOL-zFixture-2 base; } > "$TMP/o"
{ pre; row TOOL-zFixture-1 base; printf '\n## Section two\n\n'; row TOOL-zFixture-2 base; row TOOL-zFixture-4 ours; } > "$TMP/a"
{ pre; row TOOL-zFixture-1 base; printf '\n## Section two\n\n'; row TOOL-zFixture-2 base; } > "$TMP/b"
run "interleaved heading" 0 "TOOL-zFixture-1 TOOL-zFixture-2 TOOL-zFixture-4 "
h=$(at_line '^## Section two$' "$TMP/a"); r=$(at_line '^- TOOL-zFixture-2 ' "$TMP/a")
{ [ "$h" -gt 0 ] && [ "$r" -gt 0 ] && [ "$h" -lt "$r" ]; } \
  || bad "interleaved heading: the section heading moved below its row"

# --- 6. empty %O — the file was ADDED on both sides; merge as a pure union of keys ----------------
: > "$TMP/o"
{ pre; row TOOL-zFixture-1 ours; } > "$TMP/a"
{ pre; row TOOL-zFixture-2 theirs; } > "$TMP/b"
run "empty base" 0 "TOOL-zFixture-1 TOOL-zFixture-2 "

# --- 7. IDENTITY: merging a file against itself must change NOTHING (AC18) -------------------------
# The cheapest proof that the two planes and the recombination do not mangle real files, and the one
# that caught upstream's first draft (it hoisted every unkeyed line to the end of the block).
# ENUMERATED BY GLOB, not listed, so a new backlog shard is covered the day it lands.
#
# AND THE GOVERNED FILES ARE NOT ENOUGH. Measured at HEAD they carry zero duplicate row lines and
# zero nested rows, so they satisfy this arm BY ACCIDENT and prove nothing about multiplicity. The
# authored fixture below carries the same row-shaped line twice, which is the shape that made a
# `key -> line` row plane fail its own identity merge — a permanent whole-file conflict no author
# can clear. It is authored rather than harvested because no governed file has one.
{ pre; row TOOL-zFixture-1 base; printf '  - notes\n'; row TOOL-zFixture-2 base; printf '  - notes\n'; } > "$TMP/rep.md"
[ "$(grep -c '^  - notes$' "$TMP/rep.md")" = 2 ] \
  || bad "identity: the repeated-row fixture does not carry its line twice — the multiplicity arm is vacuous"
GOVERNED=$(printf '%s\n' memory/DECISIONS.md memory/backlog/*.md "$TMP/rep.md")
# COUNT THE FILES THAT EXIST, not the strings the glob yielded. An unmatched glob stays LITERAL in
# sh, so `memory/backlog/*.md` counts as one "file", the `[ -f ]` guard below silently skips it,
# and a floor of 3 is met by a TOTAL glob failure — the `vacuous-selector-empty-population` shape
# exactly. Measured: renaming memory/backlog aside left this arm PASSing with every shard out of
# it. So existence is counted, and the shards are counted on their own against their own floor.
ngov=$(printf '%s
' "$GOVERNED" | while IFS= read -r f; do [ -f "$f" ] && echo x; done | grep -c .)
nshard=$(printf '%s
' memory/backlog/*.md | while IFS= read -r f; do [ -f "$f" ] && echo x; done | grep -c .)
[ "$ngov" -ge 4 ] || bad "identity: only $ngov of the governed indexes EXIST — the arm collapsed to a glob that matched nothing"
[ "$nshard" -ge 2 ] || bad "identity: the backlog glob resolved $nshard real shard(s); the arm claims to cover a new shard the day it lands, and does not"
while IFS= read -r f; do
  [ -n "$f" ] && [ -f "$f" ] || continue
  cp "$f" "$TMP/o"; cp "$f" "$TMP/a"; cp "$f" "$TMP/b"
  $DRV "$TMP/o" "$TMP/a" "$TMP/b" x >/dev/null 2>&1 \
    || bad "identity $f: the driver reported a conflict merging a file with itself"
  cmp -s "$f" "$TMP/a" || bad "identity $f: output differs from input"
done <<EOF
$GOVERNED
EOF
# ...and both line-ending flavours EXPLICITLY, so all seven newline sites are under a `cmp` regardless
# of how this node happens to have checked the tree out. This repo's nodes run core.autocrlf=true and
# the governed indexes are CRLF in the worktree, which is the format git hands a merge driver; a node
# that checked out LF must still not be told the CRLF sites are green.
LC_ALL=C tr -d '\r' < memory/DECISIONS.md > "$TMP/lf.md"
awk '{ printf "%s\r\n", $0 }' "$TMP/lf.md" > "$TMP/crlf.md"
LC_ALL=C grep -qU $'\r' "$TMP/crlf.md" || bad "the CRLF fixture carries no CR — the newline arm is vacuous"
for f in "$TMP/lf.md" "$TMP/crlf.md"; do
  cp "$f" "$TMP/o"; cp "$f" "$TMP/a"; cp "$f" "$TMP/b"
  $DRV "$TMP/o" "$TMP/a" "$TMP/b" x >/dev/null 2>&1 \
    || bad "identity $(basename "$f"): the driver reported a conflict merging a file with itself"
  cmp -s "$f" "$TMP/a" || bad "identity $(basename "$f"): line endings were rewritten"
done
# ...a file with NO anchors at all is entirely structure and round-trips unchanged.
{ pre; printf 'No id anywhere in this document.\n'; } > "$TMP/none.md"
cp "$TMP/none.md" "$TMP/o"; cp "$TMP/none.md" "$TMP/a"; cp "$TMP/none.md" "$TMP/b"
$DRV "$TMP/o" "$TMP/a" "$TMP/b" x >/dev/null 2>&1 || bad "identity no-anchor: reported a conflict"
cmp -s "$TMP/none.md" "$TMP/a" || bad "identity no-anchor: output differs from input"
# ...and a file that is ENTIRELY rows, which is the other end of the same partition.
{ row TOOL-zFixture-1 base; row TOOL-zFixture-2 base; } > "$TMP/allrows.md"
cp "$TMP/allrows.md" "$TMP/o"; cp "$TMP/allrows.md" "$TMP/a"; cp "$TMP/allrows.md" "$TMP/b"
$DRV "$TMP/o" "$TMP/a" "$TMP/b" x >/dev/null 2>&1 || bad "identity all-rows: reported a conflict"
cmp -s "$TMP/allrows.md" "$TMP/a" || bad "identity all-rows: output differs from input"

# --- 7b. a STRUCTURE region that genuinely three-way merges, in both line-ending flavours -----------
# THE IDENTITY ARMS ABOVE CANNOT REACH `git merge-file` AT ALL: `text_merge` short-circuits on
# `a == b`, `o == a` and `o == b`, and an identity merge satisfies all three. So sites 2 and 3 of the
# newline contract — the temp writes and the captured stdout — are under test HERE and nowhere else.
# Measured: with upstream's `capture_output=True, text=True` on that capture (universal-newline mode)
# every identity arm still passes and this one reds, which is the whole reason the divergence is
# written down rather than inherited. Counting bytes rather than parsing lines is deliberate — awk on
# a Cygwin/MSYS node strips CR before it sees a byte, so a CR guard must be built out of `tr`/`wc`.
# The two edited lines are held APART by four unchanged ones on purpose: a diff folds adjacent hunks
# into one conflicting region, so a fixture with them side by side asserts a conflict rather than the
# clean prose merge this arm is about.
prose()  { printf '# Index\n\n%s\n\nrouting prose\nmore routing prose\n\n%s\n\n' "$1" "$2"; }
cprose() { printf '# Index\r\n\r\n%s\r\n\r\nrouting prose\r\nmore routing prose\r\n\r\n%s\r\n\r\n' "$1" "$2"; }
crow() { printf -- '- %s · OPEN · %s\r\n' "$1" "$2"; }
endings() {  # "<CR count>:<LF count>" of a file
  printf '%s:%s' "$(LC_ALL=C tr -dc '\r' < "$1" | wc -c | tr -d ' ')" \
                 "$(LC_ALL=C tr -dc '\n' < "$1" | wc -c | tr -d ' ')"
}
{ cprose alpha beta;  crow TOOL-zFixture-1 base; } > "$TMP/o"
{ cprose ALPHA beta;  crow TOOL-zFixture-1 base; } > "$TMP/a"
{ cprose alpha BETA;  crow TOOL-zFixture-1 base; } > "$TMP/b"
run "crlf structure three-way" 0 "TOOL-zFixture-1 "
grep -q 'ALPHA' "$TMP/a" || bad "crlf structure: ours' prose edit was lost"
grep -q 'BETA' "$TMP/a" || bad "crlf structure: theirs' prose edit was lost"
cr=$(endings "$TMP/a")
[ "${cr%%:*}" = "${cr##*:}" ] \
  || bad "crlf structure: CR:LF byte counts are $cr — a newline site translated the merged region"
{ prose alpha beta; row TOOL-zFixture-1 base; } > "$TMP/o"
{ prose ALPHA beta; row TOOL-zFixture-1 base; } > "$TMP/a"
{ prose alpha BETA; row TOOL-zFixture-1 base; } > "$TMP/b"
run "lf structure three-way" 0 "TOOL-zFixture-1 "
cr=$(endings "$TMP/a")
[ "${cr%%:*}" = 0 ] || bad "lf structure: CR:LF byte counts are $cr — a CR was introduced into an LF file"

# --- 8. THE AUDIT LINE RECONCILES WITH THE FILE, AT BOTH EXIT CODES (AC15, corpus C21) -------------
# That line is the only output this module produces and it is what an operator audits an auto-resolved
# merge with. The retired line was unable to see a loss — `kept` was a tautology over the input, and
# it printed `38 row(s) from ours … clean` on a merge that had just deleted a line. Every number is
# now derived from the WRITTEN BYTES after the fact, and this arm re-derives each of them
# independently and compares.
#
# BOTH EXIT CODES, and that is the half the old group could not reach: all three of its call sites
# passed `want_rc 0`, so the only regime where the equality can break was never exercised. `written`
# counts rows OUTSIDE conflict regions, which is what makes the rc-1 arm meaningful.
audit() {   # $1 label · $2 want_rc · $3 want_deletes · $4 want_row_conflicts · $5 want_structure_conflicts
  local label=$1 want_rc=$2 rc err line got_w got_k got_h got_d got_x got_s w k h
  err=$($DRV "$TMP/o" "$TMP/a" "$TMP/b" x 2>&1 >/dev/null) && rc=0 || rc=$?
  [ "$rc" = "$want_rc" ] || bad "audit $label: rc=$rc, expected $want_rc"
  line=$(printf '%s\n' "$err" | grep '^merge-rows: rows ' | tail -1)
  if [ -z "$line" ]; then
    bad "audit $label: the driver printed no audit line — nothing to reconcile"; return
  fi
  got_w=$(printf '%s\n' "$line" | sed -n 's/.*-> \([0-9]*\) written.*/\1/p')
  got_k=$(printf '%s\n' "$line" | sed -n 's/.*written (\([0-9]*\) keyed.*/\1/p')
  got_h=$(printf '%s\n' "$line" | sed -n 's/.*keyed, \([0-9]*\) hashed.*/\1/p')
  got_d=$(printf '%s\n' "$line" | sed -n 's/.*), \([0-9]*\) deletes honoured.*/\1/p')
  got_x=$(printf '%s\n' "$line" | sed -n 's/.*honoured, \([0-9]*\) row conflicts.*/\1/p')
  got_s=$(printf '%s\n' "$line" | sed -n 's/.*conflicts, \([0-9]*\) structure conflicts.*/\1/p')
  # Re-derive `written` from the file: row-shaped lines OUTSIDE every conflict region.
  w=$(awk '/^<<<<<<</ { skip=1 } /^>>>>>>>/ { skip=0; next } !skip && /^[[:space:]]*[-*][[:space:]]/ { n++ } END { print n+0 }' "$TMP/a")
  [ "$got_w" = "$w" ] \
    || bad "audit $label: the line says $got_w row(s) written and the settled file holds $w"
  [ $((got_k + got_h)) = "$got_w" ] \
    || bad "audit $label: keyed $got_k + hashed $got_h does not equal written $got_w"
  [ "$got_d" = "$3" ] || bad "audit $label: deletes honoured $got_d, expected $3"
  [ "$got_x" = "$4" ] || bad "audit $label: row conflicts $got_x, expected $4"
  [ "$got_s" = "$5" ] || bad "audit $label: structure conflicts $got_s, expected $5"
  # ...and the verdict the line prints agrees with whether the file carries markers, which is the
  # equality the retired line could not hold: a `clean` verdict over a file with markers in it.
  if grep -q '^<<<<<<<' "$TMP/a"; then
    printf '%s\n' "$line" | grep -q 'CONFLICT$' || bad "audit $label: the file carries markers and the line says clean"
  else
    printf '%s\n' "$line" | grep -q 'clean$' || bad "audit $label: the file carries no markers and the line says CONFLICT"
  fi
}
# (a) disjoint appends — the ordinary shape
{ pre; row TOOL-zFixture-1 base; } > "$TMP/o"
{ pre; row TOOL-zFixture-1 base; row TOOL-zFixture-2 ours; } > "$TMP/a"
{ pre; row TOOL-zFixture-1 base; row TOOL-zFixture-3 theirs; } > "$TMP/b"
audit "disjoint appends" 0 0 0 0
# (b) two theirs-side deletes honoured — the shape the tautological counter could not see
{ pre; row TOOL-zFixture-1 base; row TOOL-zFixture-2 base; row TOOL-zFixture-3 base; } > "$TMP/o"
{ pre; row TOOL-zFixture-1 base; row TOOL-zFixture-2 base; row TOOL-zFixture-3 base; } > "$TMP/a"
{ pre; row TOOL-zFixture-1 base; } > "$TMP/b"
audit "two deletes honoured" 0 2 0 0
# (c) AT rc 1 — a row conflict. `written` must count the settled rows only, so it is 0 here while the
# file holds two row lines between the markers.
{ pre; row TOOL-zFixture-1 base; } > "$TMP/o"
{ pre; row TOOL-zFixture-1 OURS; } > "$TMP/a"
{ pre; row TOOL-zFixture-1 THEIRS; } > "$TMP/b"
audit "a row conflict at rc 1" 1 0 1 0
[ "$(grep -c '^- TOOL-zFixture-1 ' "$TMP/a")" = 2 ] \
  || bad "audit rc 1: the file does not hold both texts, so `written`=0 means something else"
# (d) AT rc 1 — a STRUCTURE conflict, which is the other term and a different code path.
{ pre; printf '## OLD\n\n'; row TOOL-zFixture-1 base; } > "$TMP/o"
{ pre; printf '## OURS-RENAME\n\n'; row TOOL-zFixture-1 base; } > "$TMP/a"
{ pre; printf '## THEIRS-RENAME\n\n'; row TOOL-zFixture-1 base; } > "$TMP/b"
audit "a structure conflict at rc 1" 1 0 0 1

# --- 9. END TO END: a real two-branch `git merge` through the real wiring --------------------------
# Everything above drives the driver by hand. This drives GIT, through the `.gitattributes` line and
# the `merge.rows.driver` config a node actually carries, which is the only arm that can catch a
# wiring string that does not start the driver at all. THREE directories are copied, not two: the
# configured command is `bash tools/lib/pyrun.sh tools/memory-tree/merge-rows.py …` and its paths are
# RELATIVE, so a fixture carrying only the two kits cannot launch anything.
E=$(mktemp -d); SCRATCH="$SCRATCH $E"
mkdir -p "$E/tools/memory-tree" "$E/tools/memory-recall" "$E/tools/lib" "$E/memory/backlog"
cp .memory-tree.conf "$E/"
cp tools/memory-tree/merge-rows.py "$E/tools/memory-tree/"
cp tools/memory-recall/extract.py tools/memory-recall/recall_conf.py "$E/tools/memory-recall/"
cp tools/lib/pyrun.sh tools/lib/resolve-python.sh "$E/tools/lib/"
(
  cd "$E" || exit 2
  git init -q -b main
  git config user.email t@e; git config user.name t; git config core.autocrlf false
  printf 'memory/DECISIONS.md merge=rows\nmemory/backlog/*.md merge=rows\n' > .gitattributes
  git config merge.rows.driver 'bash tools/lib/pyrun.sh tools/memory-tree/merge-rows.py %O %A %B %P'
  { printf '# tooling backlog\n\n> Mutable. Each row leads with one status token.\n'
    row TOOL-zFixture-1 base; } > memory/backlog/TOOL.md
  git add -A; git commit -q -m base
  git checkout -q -b side
  row TOOL-zFixture-3 theirs >> memory/backlog/TOOL.md
  git commit -q -am theirs
  git checkout -q main
  row TOOL-zFixture-2 ours >> memory/backlog/TOOL.md
  git commit -q -am ours
  # the attribute must be what GIT judges, not what a grep of .gitattributes says
  git check-attr merge -- memory/backlog/TOOL.md | grep -q 'merge: rows' \
    || { echo "FAIL end-to-end: git does not resolve memory/backlog/TOOL.md to merge=rows"; exit 1; }
  git merge -q --no-edit side >/dev/null 2>&1 || { echo "FAIL end-to-end: git merge did not auto-resolve"; exit 1; }
  for want in TOOL-zFixture-1 TOOL-zFixture-2 TOOL-zFixture-3; do
    c=$(grep -c "^- $want " memory/backlog/TOOL.md)
    [ "$c" = 1 ] || { echo "FAIL end-to-end: $want appears $c time(s), expected exactly 1"; exit 1; }
  done
  grep -q '<<<<<<<' memory/backlog/TOOL.md && { echo "FAIL end-to-end: conflict markers in an auto-resolved file"; exit 1; }
  exit 0
) || st=1

# --- 10. BOTH NODES OPEN THE SAME EMPTY SECTION (corpus C1, AC5 first half) ------------------------
# The headline auto-resolve, and the one the retired lead-in model corrupted: each side's new row
# carried the same base furniture — the `## FAMILY` heading and the `*(none yet)*` placeholder — and
# both copies were emitted, rc 0, zero markers, in an append-only file. The CONTROL is what makes it
# decisive: `git merge-file` REFUSES this input at rc 1, so pure delegation would lose the case the
# unit exists for. Reconciliation rule 3 buys it back — the region is token-only on both sides, so
# section membership is not in dispute and only sibling order is, which is not semantic.
{ pre; row TOOL-zFixture-1 base; printf '\n## Section two\n\n*(none yet)*\n'; } > "$TMP/o"
{ pre; row TOOL-zFixture-1 base; printf '\n## Section two\n\n'; row TOOL-zFixture-2 ours; } > "$TMP/a"
{ pre; row TOOL-zFixture-1 base; printf '\n## Section two\n\n'; row TOOL-zFixture-3 theirs; } > "$TMP/b"
cp "$TMP/a" "$TMP/ctlin"
git merge-file -p -L ours -L base -L theirs "$TMP/ctlin" "$TMP/o" "$TMP/b" >/dev/null 2>&1; c10=$?
[ "$c10" = 1 ] || bad "shared furniture: the CONTROL exits $c10 where this arm's whole point is that git REFUSES it at rc 1 — the headline better-than-git claim is stale, re-measure before trusting it"
want_h=$(grep -h '^## ' "$TMP/o" "$TMP/a" "$TMP/b" | LC_ALL=C sort -u | grep -c .)   # BEFORE %A moves
[ "$want_h" = 1 ] || bad "shared furniture: the fixture declares $want_h distinct headings, expected 1"
run "both nodes open the same empty section" 0 "TOOL-zFixture-1 TOOL-zFixture-2 TOOL-zFixture-3 "
got_h=$(grep -c '^## ' "$TMP/a")
[ "$got_h" = "$want_h" ] \
  || bad "shared furniture: the result carries $got_h '## ' heading line(s) against $want_h distinct across the three inputs"
[ "$(grep -c 'none yet' "$TMP/a")" = 0 ] \
  || bad "shared furniture: the placeholder BOTH sides replaced is back in the merged file"
h=$(at_line '^## Section two$' "$TMP/a"); r=$(at_line '^- TOOL-zFixture-2 ' "$TMP/a")
{ [ "$h" -gt 0 ] && [ "$r" -gt 0 ] && [ "$h" -lt "$r" ]; } \
  || bad "shared furniture: heading at line $h, ours' row at line $r (0 = absent) — the heading must open its section"
[ "$(grep -c '<<<<<<<' "$TMP/a")" = 0 ] || bad "shared furniture: markers written on an arm that must auto-resolve"

# --- 11. a %B-only row in a NON-FINAL section stays inside its section -----------------------------
# The mirror of case 5, which only ever covers a heading whose position must be PRESERVED. Emitting
# every theirs-only row after ALL of ours' rows filed an incoming decision under whatever `## FAMILY`
# happened to be last. Under the redesign placement comes from git's own diff of the skeleton rather
# than from a splice this driver computes, and the CONTROL decides it: git resolves this input rc 0
# with the row correctly filed, so anything else is a regression against the merge being replaced.
{ pre; row TOOL-zFixture-1 base; printf '\n## Section two\n\n'; row TOOL-zFixture-2 base; } > "$TMP/o"
{ pre; row TOOL-zFixture-1 base; printf '\n## Section two\n\n'; row TOOL-zFixture-2 base; row TOOL-zFixture-4 ours; } > "$TMP/a"
{ pre; row TOOL-zFixture-1 base; row TOOL-zFixture-5 theirs; printf '\n## Section two\n\n'; row TOOL-zFixture-2 base; } > "$TMP/b"
run "b-only row in a non-final section" 0 "TOOL-zFixture-1 TOOL-zFixture-2 TOOL-zFixture-4 TOOL-zFixture-5 "
h=$(at_line '^## Section two$' "$TMP/a")
r=$(at_line '^- TOOL-zFixture-5 ' "$TMP/a"); m=$(at_line '^- TOOL-zFixture-4 ' "$TMP/a")
{ [ "$h" -gt 0 ] && [ "$r" -gt 0 ] && [ "$r" -lt "$h" ]; } \
  || bad "b-only placement: the incoming row is at line $r against the next heading at line $h (0 = absent) — it was filed into the wrong section"
{ [ "$m" -gt 0 ] && [ "$m" -gt "$h" ]; } \
  || bad "b-only placement: ours' own row is at line $m against the heading at line $h (0 = absent) — it left the section it was added to"

# --- 12. AN UNKEYABLE ROW MINTED ON BOTH NODES, IN DIFFERENT REGIONS (corpus C10, AC10) ------------
# THE CASE THAT JUSTIFIES THE UNIT. `git merge-file` resolves this input at rc 0 having written the
# row TWICE — measured, twice, once on the real memory/DECISIONS.md — and that is the single
# corruption class git commits. The driver must refuse. Under the redesign both copies hash to the
# SAME `raw:` key, so the row plane resolves the key to one line while the merged skeleton carries
# its token twice, and CONSERVATION refuses by name. The refusal quotes the row text, not just the
# digest: `raw:ad3a…` in front of an author resolving a merge by hand is not attribution.
mk12() {
  { pre; row TOOL-zFixture-1 base; row TOOL-zFixture-2 base; } > "$TMP/o"
  { pre; row TOOL-zFixture-1 base; printf '%s\n' "$SUFFIXED"; row TOOL-zFixture-2 base; } > "$TMP/a"
  { pre; row TOOL-zFixture-1 base; row TOOL-zFixture-2 base; printf '%s\n' "$SUFFIXED"; } > "$TMP/b"
}
mk12
cp "$TMP/a" "$TMP/ctlin"
git merge-file -p -L ours -L base -L theirs "$TMP/ctlin" "$TMP/o" "$TMP/b" > "$TMP/ctl12" 2>/dev/null && c12=0 || c12=$?
[ "$c12" = 0 ] && [ "$(grep -cF -- "$SUFFIXED" "$TMP/ctl12")" = 2 ] \
  || bad "unkeyable duplicate: the CONTROL no longer duplicates at rc 0 (rc=$c12, copies=$(grep -cF -- "$SUFFIXED" "$TMP/ctl12")) — this arm's premise is that git gets it WRONG here"
mk12
err=$($DRV "$TMP/o" "$TMP/a" "$TMP/b" x 2>&1 >/dev/null)
printf '%s\n' "$err" | grep -q 'RowLoss' \
  || bad "unkeyable duplicate: the refusal does not name the conservation postcondition — stderr was [$err]"
printf '%s\n' "$err" | grep -qF 'TOOL-zFixture-9b' \
  || bad "unkeyable duplicate: the refusal does not quote the line it refused over — a digest is not attribution"
mk12
ctl_wrong
run "unkeyable row minted on both nodes" 1 "TOOL-zFixture-1 TOOL-zFixture-2 TOOL-zFixture-9b "
grep -q '^<<<<<<< ours$' "$TMP/a" \
  || bad "unkeyable duplicate: rc 1 with NO markers is the marker-free-UU trap — write the conflict"
# ...and the postcondition does NOT fire on the same row arriving from one side only, or every clean
# append below it is one refusal away from unusable.
{ pre; row TOOL-zFixture-1 base; row TOOL-zFixture-2 base; } > "$TMP/o"
{ pre; row TOOL-zFixture-1 base; printf '%s\n' "$SUFFIXED"; row TOOL-zFixture-2 base; } > "$TMP/a"
{ pre; row TOOL-zFixture-1 base; row TOOL-zFixture-2 base; } > "$TMP/b"
run "unkeyable row from one side only" 0 "TOOL-zFixture-1 TOOL-zFixture-2 TOOL-zFixture-9b "

# --- 13. AN HONOURED DELETE MUST NOT SWALLOW WHAT THE OTHER SIDE FILED NEXT TO IT (C9, AC7) --------
# THE EXPECTATION HERE IS DELIBERATELY CHANGED FROM rc 1 TO rc 0, and the change is the unit's. The
# retired driver narrowed both delete comparisons to the anchor line, so a side that left the row
# alone but filed something immediately ABOVE it read as "untouched" and the `continue` discarded
# what it filed — rc 0, incoming row GONE. The repair made the whole shape a conflict, matching git,
# which refuses it too. Under the redesign there is no lead-in at all: the adjacent row is a separate
# key with its own decision, the region is ours-side-empty and theirs-side two tokens, so rule 3
# applies and rule 2 DROPS the deleted key. The delete is honoured AND the incoming row is kept.
#
# SO THIS ARM ASSERTS BYTES ON BOTH HALVES, NEVER AN EXIT CODE. This is one of only two places the
# driver resolves where git refuses, and an rc-only assertion reads identically whether the row
# survived or was swallowed — which is the exact failure the case exists for.
ADJ='- TOOL-zFixture-7b OPEN an unkeyable correction row filed against the deleted row, no separator'
{ pre; row TOOL-zFixture-1 base; row TOOL-zFixture-2 base; row TOOL-zFixture-3 base; } > "$TMP/o"
{ pre; row TOOL-zFixture-1 base; row TOOL-zFixture-3 base; } > "$TMP/a"
{ pre; row TOOL-zFixture-1 base; printf '%s\n' "$ADJ"; row TOOL-zFixture-2 base; row TOOL-zFixture-3 base; } > "$TMP/b"
cp "$TMP/a" "$TMP/ctlin"
git merge-file -p -L ours -L base -L theirs "$TMP/ctlin" "$TMP/o" "$TMP/b" >/dev/null 2>&1; c13=$?
[ "$c13" = 1 ] || bad "delete/adjacent: the CONTROL exits $c13 where this arm claims to be one of only TWO places the driver resolves what git refuses — the claim is stale"
run "ours deleted, theirs filed above it" 0 "TOOL-zFixture-1 TOOL-zFixture-3 TOOL-zFixture-7b " TOOL-zFixture-2
[ "$(grep -cF -- "$ADJ" "$TMP/a")" = 1 ] \
  || bad "delete/adjacent: theirs' correction row is not present exactly once — an honoured delete swallowed it"
[ "$(grep -c '^- TOOL-zFixture-2 ' "$TMP/a")" = 0 ] \
  || bad "delete/adjacent: the deleted row came back, so the delete was NOT honoured and the rc 0 means something else"

{ pre; row TOOL-zFixture-1 base; row TOOL-zFixture-2 base; row TOOL-zFixture-3 base; } > "$TMP/o"
{ pre; row TOOL-zFixture-1 base; printf '%s\n' "$ADJ"; row TOOL-zFixture-2 base; row TOOL-zFixture-3 base; } > "$TMP/a"
{ pre; row TOOL-zFixture-1 base; row TOOL-zFixture-3 base; } > "$TMP/b"
run "theirs deleted, ours filed above it" 0 "TOOL-zFixture-1 TOOL-zFixture-3 TOOL-zFixture-7b " TOOL-zFixture-2
[ "$(grep -cF -- "$ADJ" "$TMP/a")" = 1 ] \
  || bad "delete/adjacent mirror: ours' correction row is not present exactly once"
[ "$(grep -c '^- TOOL-zFixture-2 ' "$TMP/a")" = 0 ] \
  || bad "delete/adjacent mirror: the deleted row came back"

# ...and the same neighbourhood with a KEYED adjacent row, which travels the ordinary keyed path.
ADJK='- TOOL-zFixture-8b · OPEN · a KEYED correction row filed against the deleted row'
{ pre; row TOOL-zFixture-1 base; row TOOL-zFixture-2 base; row TOOL-zFixture-3 base; } > "$TMP/o"
{ pre; row TOOL-zFixture-1 base; row TOOL-zFixture-3 base; } > "$TMP/a"
{ pre; row TOOL-zFixture-1 base; printf '%s\n' "$ADJK"; row TOOL-zFixture-2 base; row TOOL-zFixture-3 base; } > "$TMP/b"
keys "$ADJK" || bad "delete/adjacent keyed: [$ADJK] is NOT keyed by the driver — this arm is a duplicate of the one above and proves nothing new"
run "ours deleted, theirs filed a KEYED row above it" 0 "TOOL-zFixture-1 TOOL-zFixture-3 TOOL-zFixture-8b " TOOL-zFixture-2
[ "$(grep -cF -- "$ADJK" "$TMP/a")" = 1 ] \
  || bad "delete/adjacent keyed: theirs' keyed correction row is not present exactly once"
[ "$(grep -c '^- TOOL-zFixture-2 ' "$TMP/a")" = 0 ] \
  || bad "delete/adjacent keyed: the deleted row came back, so the delete was not honoured"

# --- 14. A %B-ONLY ROW THAT OPENS THE NEXT SECTION MUST NOT SWALLOW OURS' OWN NEW ROW (C6) ---------
# `git merge-file` resolves this input rc 0 and CORRECTLY, so the driver is compared to git's answer
# BYTE FOR BYTE rather than to a hand-typed expectation. The retired splice put ours' new row UNDER
# the heading theirs' new row carried as its lead-in — reproduced through a real `git merge` on the
# real index, a PLAY decision auto-committed under `## KICK`, rc 0, zero markers.
{ pre; row TOOL-zFixture-1 base; printf '\n## Section two\n\n'; row TOOL-zFixture-2 base; } > "$TMP/o"
{ pre; row TOOL-zFixture-1 base; row TOOL-zFixture-3 ours; printf '\n## Section two\n\n'; row TOOL-zFixture-2 base; } > "$TMP/a"
{ pre; row TOOL-zFixture-1 base; printf '\n## Section two\n\n'; row TOOL-zFixture-9 theirs; row TOOL-zFixture-2 base; } > "$TMP/b"
cp "$TMP/a" "$TMP/keep14"
run "b-only row opening the next section" 0 "TOOL-zFixture-1 TOOL-zFixture-2 TOOL-zFixture-3 TOOL-zFixture-9 "
h=$(at_line '^## Section two$' "$TMP/a")
m=$(at_line '^- TOOL-zFixture-3 ' "$TMP/a"); r=$(at_line '^- TOOL-zFixture-9 ' "$TMP/a")
{ [ "$h" -gt 0 ] && [ "$m" -gt 0 ] && [ "$m" -lt "$h" ]; } \
  || bad "b-only opens next section: OURS' new row is at line $m against the heading at $h (0 = absent) — it was pushed under theirs' new heading"
{ [ "$r" -gt 0 ] && [ "$r" -gt "$h" ]; } \
  || bad "b-only opens next section: theirs' row is at line $r against the heading at $h (0 = absent)"
cmp -s "$TMP/a" "$TMP/ctl" \
  || bad "b-only opens next section: the driver's file differs from git merge-file's, which is CORRECT here — the driver is worse than no driver"

# --- 15. PLACEMENT THE DRIVER CANNOT DECIDE IS A CONFLICT, NEVER A GUESS (corpus C7, AC9) ----------
# Ours RELOCATES a row across a `## ` boundary and theirs files a new row behind that row's old
# position. `git merge-file` REFUSES the same input. The retired driver dragged theirs' row into the
# section ours moved to, at rc 0, through a real `git merge`. Under the redesign the moved key's
# token appears TWICE in the merged skeleton, so CONSERVATION refuses — and the refusal names the key
# that would have been written twice, which is attribution the heading-mismatch message never had.
{ pre; printf '## open\n\n'; row TOOL-zFixture-1 base; row TOOL-zFixture-2 base; printf '\n## closed\n\n'; row TOOL-zFixture-3 base; } > "$TMP/o"
{ pre; printf '## open\n\n'; row TOOL-zFixture-1 base; printf '\n## closed\n\n'; row TOOL-zFixture-3 base; row TOOL-zFixture-2 base; } > "$TMP/a"
{ pre; printf '## open\n\n'; row TOOL-zFixture-1 base; row TOOL-zFixture-2 base; row TOOL-zFixture-9 theirs; printf '\n## closed\n\n'; row TOOL-zFixture-3 base; } > "$TMP/b"
cp "$TMP/a" "$TMP/ctlin"
git merge-file -p -L ours -L base -L theirs "$TMP/ctlin" "$TMP/o" "$TMP/b" >/dev/null 2>&1 && c15=0 || c15=$?
[ "$c15" -ge 1 ] && [ "$c15" -lt 128 ] || bad "unplaceable row: the CONTROL answered $c15 — 0 means it now RESOLVES this input and >=128 means it could not run at all, and neither is the refusal this arm rests on — the arm's premise is that git refuses it too"
err=$($DRV "$TMP/o" "$TMP/a" "$TMP/b" x 2>&1 >/dev/null); rc=$?
[ "$rc" = 1 ] || bad "unplaceable row: rc=$rc, expected 1 — a row would have been written twice and the driver did not say so"
printf '%s\n' "$err" | grep -q 'RowLoss' \
  || bad "unplaceable row: the refusal does not name the conservation postcondition — stderr was [$err]"
printf '%s\n' "$err" | grep -qF 'TOOL-zFixture-2' || bad "unplaceable row: the refusal does not name the key it refused over"
grep -q '^<<<<<<< ours$' "$TMP/a" || bad "unplaceable row: rc 1 with NO markers is the marker-free-UU trap"

# --- 16. THE SAME UNKEYABLE ID MINTED ON BOTH NODES, WITH DIFFERENT WORDING (corpus C11) ----------
# The line-level census compares EXACT text, so two nodes each minting the same correction id with
# their own prose produce two DIFFERENT lines and the id lands TWICE at rc 0 — measured. Under the
# redesign they are also two different `raw:` keys, so conservation cannot see them either: this is
# the population the ID HALF of `no_new_duplicates` exists for, and it is the arm that proves it live.
# C11's control was never measured in any round; it is measured here and recorded.
mk16() {
  { pre; row TOOL-zFixture-1 base; row TOOL-zFixture-2 base; } > "$TMP/o"
  { pre; row TOOL-zFixture-1 base; printf -- '- TOOL-zFixture-9b CORRECTS TOOL-zFixture-1, the ours-side wording\n'; row TOOL-zFixture-2 base; } > "$TMP/a"
  { pre; row TOOL-zFixture-1 base; row TOOL-zFixture-2 base; printf -- '- TOOL-zFixture-9b CORRECTS TOOL-zFixture-1, the theirs-side wording\n'; } > "$TMP/b"
}
mk16
cp "$TMP/a" "$TMP/ctlin"
git merge-file -p -L ours -L base -L theirs "$TMP/ctlin" "$TMP/o" "$TMP/b" > "$TMP/ctl16" 2>/dev/null && c16=0 || c16=$?
c16n=$(grep -c 'TOOL-zFixture-9b' "$TMP/ctl16")
[ "$c16" = 0 ] && [ "$c16n" = 2 ] \
  || bad "divergent-text duplicate id: the CONTROL's measured behaviour changed (rc=$c16, id x$c16n) — it wrote the id twice at rc 0 when this arm was authored"
mk16
err=$($DRV "$TMP/o" "$TMP/a" "$TMP/b" x 2>&1 >/dev/null); rc=$?
[ "$rc" = 1 ] || bad "divergent-text duplicate id: rc=$rc, expected 1 — the id was written twice at exit $rc"
printf '%s\n' "$err" | grep -q 'DuplicatedContent' \
  || bad "divergent-text duplicate id: the refusal does not name the id postcondition — stderr was [$err]"
printf '%s\n' "$err" | grep -qF 'TOOL-zFixture-9b' || bad "divergent-text duplicate id: the refusal does not name the id"
# ...and the id half must NOT fire on a row that merely CITES an id two nodes both cite. Counting
# every id on a line rather than the LEADING one reds this, and it is the ordinary shape of this
# corpus: 73 of 73 rows carry a leading id and rows cite each other constantly.
{ pre; row TOOL-zFixture-1 base; } > "$TMP/o"
{ pre; row TOOL-zFixture-1 base; printf -- '- TOOL-zFixture-4 · OPEN · supersedes TOOL-zFixture-1 (ours)\n'; } > "$TMP/a"
{ pre; row TOOL-zFixture-1 base; printf -- '- TOOL-zFixture-5 · OPEN · supersedes TOOL-zFixture-1 (theirs)\n'; } > "$TMP/b"
err=$($DRV "$TMP/o" "$TMP/a" "$TMP/b" x 2>&1 >/dev/null) && rc=0 || rc=$?
[ "$rc" = 0 ] \
  || bad "citing rows: rc=$rc, expected 0 — two nodes each citing one base row is not a duplicate [$err]"
for want in TOOL-zFixture-1 TOOL-zFixture-4 TOOL-zFixture-5; do
  [ "$(grep -c "^- $want " "$TMP/a")" = 1 ] || bad "citing rows: $want is not present exactly once"
done

# --- 17. A STRUCTURE LINE THAT LEGITIMATELY REPEATS IN TWO SECTIONS SURVIVES TWICE (C3) ------------
# THE CONTROL IS RIGHT HERE TOO. The retired file-wide lead-in dedup dropped every later copy of a
# repeated lead-in — correct for case 10 and wrong the moment the same text is two different pieces
# of furniture. Under the redesign nothing decides this at all: a `### ` sub-heading is STRUCTURE and
# git merges it positionally, which is the class git is measured correct on.
{ pre; printf '## Section one\n\n'; row TOOL-zFixture-1 base; printf '\n## Section two\n\n'; row TOOL-zFixture-2 base; } > "$TMP/o"
{ pre; printf '## Section one\n\n'; row TOOL-zFixture-1 base; printf '\n### 2026-08\n\n'; row TOOL-zFixture-3 ours; printf '\n## Section two\n\n'; row TOOL-zFixture-2 base; } > "$TMP/a"
{ pre; printf '## Section one\n\n'; row TOOL-zFixture-1 base; printf '\n## Section two\n\n'; row TOOL-zFixture-2 base; printf '\n### 2026-08\n\n'; row TOOL-zFixture-4 theirs; } > "$TMP/b"
run "the same sub-heading in two sections" 0 "TOOL-zFixture-1 TOOL-zFixture-2 TOOL-zFixture-3 TOOL-zFixture-4 "
[ "$(grep -c '^### 2026-08$' "$TMP/a")" = 2 ] \
  || bad "repeated sub-heading: the result carries $(grep -c '^### 2026-08$' "$TMP/a") copies of a heading that legitimately belongs in two places, expected 2"
cmp -s "$TMP/a" "$TMP/ctl" \
  || bad "repeated sub-heading: the driver's file differs from git merge-file's, which is CORRECT here"

# --- 18. AN UNRELATED CONFLICT MUST NOT SWITCH THE DUPLICATE DETECTORS OFF (corpus C12) ------------
# Scoped to clean verdicts, the postcondition was disabled for the WHOLE FILE by one unrelated
# both-sides row edit — and the duplicate was then written OUTSIDE the markers, in text the author
# reads as already settled. rc 1 hides a duplicate exactly as well as rc 0 does. So every check runs
# on every verdict, over the merged lines with the conflict REGIONS excised. C12's control was never
# measured in any round; it is measured here.
DUP18='- TOOL-zFixture-77b an unkeyable correction row minted on BOTH nodes, no anchor separator'
{ pre; row TOOL-zFixture-1 base; row TOOL-zFixture-3 base; } > "$TMP/o"
{ pre; row TOOL-zFixture-1 base; printf '%s\n' "$DUP18"; row TOOL-zFixture-3 OURSEDIT; } > "$TMP/a"
{ pre; row TOOL-zFixture-1 base; row TOOL-zFixture-3 THEIRSEDIT; printf '%s\n' "$DUP18"; } > "$TMP/b"
cp "$TMP/a" "$TMP/ctlin"
git merge-file -p -L ours -L base -L theirs "$TMP/ctlin" "$TMP/o" "$TMP/b" > "$TMP/ctl18" 2>/dev/null && c18=0 || c18=$?
printf 'the C12 control, measured here for the first time: rc %s, the duplicated row x%s\n' \
  "$c18" "$(grep -cF -- "$DUP18" "$TMP/ctl18")" > "$TMP/c12.note"
err=$($DRV "$TMP/o" "$TMP/a" "$TMP/b" x 2>&1 >/dev/null); rc=$?
[ "$rc" = 1 ] || bad "duplicate beside a conflict: rc=$rc, expected 1"
printf '%s\n' "$err" | grep -qE 'RowLoss|DuplicatedContent' \
  || bad "duplicate beside a conflict: an unrelated conflict switched the detectors off — stderr was [$err]"
printf '%s\n' "$err" | grep -qF 'TOOL-zFixture-77b' \
  || bad "duplicate beside a conflict: the refusal does not name the duplicated row"
# ...and the excision is what makes that possible: case 2's conflict repeats one id inside the
# markers by construction, and the census must NOT read that as a duplicate. Without the excision
# this arm reds instead of case 2's.
{ pre; row TOOL-zFixture-1 base; } > "$TMP/o"
{ pre; row TOOL-zFixture-1 ours; } > "$TMP/a"
{ pre; row TOOL-zFixture-1 theirs; } > "$TMP/b"
err=$($DRV "$TMP/o" "$TMP/a" "$TMP/b" x 2>&1 >/dev/null)
printf '%s\n' "$err" | grep -q 'DuplicatedContent' \
  && bad "conflict excision: a row repeated INSIDE its own conflict markers was counted as a duplicate"

# --- 19. A HEADING RENAMED ON %B SURVIVES A ROW EDITED ON %A (corpus C14) --------------------------
# `git merge-file` REFUSES this input at rc 1 (measured), and the driver resolves it — because a
# keyed row tokenizes to its ID, so ours' skeleton is byte-identical to base's and `text_merge`'s
# `o == a` short-circuit takes theirs wholesale while the row plane independently takes ours' edit.
# That is the mechanism, and it is the reason a row's token is its id and not its text.
#
# THE ROW SITS IMMEDIATELY UNDER THE HEADING, and the spacing is load-bearing rather than incidental.
# Measured on this host: with a blank line between them git's own diff separates the two hunks and
# resolves the input at rc 0, so the BETTER-than-git claim is simply false at that spacing and the
# arm would assert nothing. Adjacent, the two edits fall in one hunk and git refuses. The premise is
# asserted below rather than trusted.
{ pre; row TOOL-zFixture-1 base; printf '\n## OLD HEADING\n'; row TOOL-zFixture-2 base; } > "$TMP/o"
{ pre; row TOOL-zFixture-1 base; printf '\n## OLD HEADING\n'; row TOOL-zFixture-2 OURS-EDIT; } > "$TMP/a"
{ pre; row TOOL-zFixture-1 base; printf '\n## RENAMED HEADING\n'; row TOOL-zFixture-2 base; } > "$TMP/b"
cp "$TMP/a" "$TMP/ctlin"
git merge-file -p -L ours -L base -L theirs "$TMP/ctlin" "$TMP/o" "$TMP/b" >/dev/null 2>&1 && c19=0 || c19=$?
{ [ "$c19" -ge 1 ] && [ "$c19" -lt 128 ]; } || bad "heading rename vs row edit: the CONTROL now resolves this input, so the BETTER-than-git claim is stale — re-measure it (it answered $c19; >=128 means it could not run at all)"
run "heading renamed on theirs, row edited on ours" 0 "TOOL-zFixture-1 TOOL-zFixture-2 "
grep -q '^## RENAMED HEADING$' "$TMP/a" || bad "heading rename: theirs' rename was DISCARDED"
grep -q '^- TOOL-zFixture-2 · OPEN · OURS-EDIT$' "$TMP/a" || bad "heading rename: ours' row edit was DISCARDED"
grep -q '^## OLD HEADING$' "$TMP/a" && bad "heading rename: the pre-rename heading is still in the file"

# --- 20. THE TOKEN HASHES THE STRIPPED LINE, SO LINE FORM CANNOT SMUGGLE A DUPLICATE IN (C13) ------
# The reachable channel is LINE FORM, not encoding — git hands the driver uniformly-terminated
# %O/%A/%B under either `core.autocrlf`, but a side whose copy of the row is the file's FINAL line
# carries no terminator at all. The `raw:` token hashes the STRIPPED text, so the two forms produce
# the SAME key and conservation sees them as one record. The fixture row is deliberately ID-LESS: the
# id half ignores terminators by construction, so a row it can key would keep this arm green under
# the sabotage it exists to catch.
BARE='- a bare correction note with no id at all, minted on both nodes'
{ pre; row TOOL-zFixture-1 base; row TOOL-zFixture-2 base; } > "$TMP/o"
{ pre; row TOOL-zFixture-1 base; printf '%s\n' "$BARE"; row TOOL-zFixture-2 base; } > "$TMP/a"
{ pre; row TOOL-zFixture-1 base; row TOOL-zFixture-2 base; printf '%s' "$BARE"; } > "$TMP/b"
err=$($DRV "$TMP/o" "$TMP/a" "$TMP/b" x 2>&1 >/dev/null); rc=$?
[ "$rc" = 1 ] || bad "line-form duplicate: rc=$rc, expected 1 — the same row in two line forms was written twice"
printf '%s\n' "$err" | grep -qE 'RowLoss|DuplicatedContent' \
  || bad "line-form duplicate: neither detector saw it — stderr was [$err]"
# ...and the fixture really is id-less, or the arm proves the id half rather than the hash.
printf '%s\n' "$BARE" > "$TMP/bare"
[ -z "$(ids "$TMP/bare")" ] \
  || bad "line-form duplicate: the fixture row carries an id, so the id half can catch it and the hash is still untested"
# ...and the two line forms really do hash to ONE key, asserted directly rather than inferred.
"$PY" - "$BARE" <<'PYEOF'
import importlib.util, sys
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("mr", "tools/memory-tree/merge-rows.py")
mr = importlib.util.module_from_spec(spec); spec.loader.exec_module(mr)
a, b = mr._row_key(sys.argv[1] + "\n"), mr._row_key(sys.argv[1])
sys.exit(0 if a == b and a.startswith("raw:") else 1)
PYEOF
[ $? = 0 ] || bad "line-form duplicate: the terminated and unterminated forms do not produce ONE raw: key"

# --- 21. DOUBLED HEADING VIA THE MIDDLE ROW (corpus C2, AC5 second half) ---------------------------
# LIVE AT HEAD BEFORE THIS UNIT, and the regression that a green 28-group bar auto-committed through
# a real `git merge`. Ours replaces the placeholder with THREE lines including an unkeyable note row;
# theirs replaces it with one. The retired adjacency dedup saw a different lead-in on the middle row,
# overwrote its signature, and emitted the `## FAMILY` heading a second time — rc 0, zero markers,
# `clean`. Group 10 could not see it: it uses exactly one row per side.
{ pre; row TOOL-zFixture-1 base; printf '\n## KICK — kickoff\n\n*(none yet)*\n'; } > "$TMP/o"
{ pre; row TOOL-zFixture-1 base; printf '\n## KICK — kickoff\n\n'; row KICK-zFixture-2 ours
  printf -- '- an unkeyable ours-side note row\n'; row KICK-zFixture-4 ours; } > "$TMP/a"
{ pre; row TOOL-zFixture-1 base; printf '\n## KICK — kickoff\n\n'; row KICK-zFixture-3 theirs; } > "$TMP/b"
run "doubled heading via the middle row" 0 "KICK-zFixture-2 KICK-zFixture-3 KICK-zFixture-4 TOOL-zFixture-1 "
[ "$(grep -c '^## KICK' "$TMP/a")" = 1 ] \
  || bad "middle-row heading: the result carries $(grep -c '^## KICK' "$TMP/a") copies of a heading the base carries once"
[ "$(grep -c 'none yet' "$TMP/a")" = 0 ] || bad "middle-row heading: the replaced placeholder is back"
[ "$(grep -cF -- '- an unkeyable ours-side note row' "$TMP/a")" = 1 ] \
  || bad "middle-row heading: ours' unkeyable note row is not present exactly once"
[ "$(grep -c '<<<<<<<' "$TMP/a")" = 0 ] || bad "middle-row heading: markers written on an arm that must auto-resolve"
h=$(at_line '^## KICK' "$TMP/a")
for r in KICK-zFixture-2 KICK-zFixture-3 KICK-zFixture-4; do
  n=$(at_line "^- $r " "$TMP/a")
  { [ "$n" -gt 0 ] && [ "$n" -gt "$h" ]; } || bad "middle-row heading: $r is at line $n against the heading at $h (0 = absent)"
done

# --- 22. A LEAD-IN NOTE THAT LEGITIMATELY REPEATS (corpus C4) --------------------------------------
# ALSO LIVE AT HEAD BEFORE THIS UNIT, and the one that falsified round three's headline claim: an
# incoming change that touched only preamble prose DELETED one of ours' two copies of a repeated
# note, at rc 0, through a real `git merge` with a `1 insertion(+), 2 deletions(-)` diffstat. The
# blank-lead-in exemption returned before the adjacency chain was reset, so the suppression reached
# across a furniture-less row. The control resolves this input at rc 0 with BOTH copies, so the
# never-worse comparison in `run` catches it on its own; the explicit count is here because a
# byte-comparison failure names bytes and this names the property.
N22='> a note that legitimately repeats'
{ pre; printf '## TOOL — tooling\n\n'; row TOOL-zFixture-1 base; printf '\n> routing\n'; } > "$TMP/o"
{ pre; printf '## TOOL — tooling\n\n'; row TOOL-zFixture-1 base; printf '%s\n' "$N22"; row TOOL-zFixture-2 ours
  row TOOL-zFixture-3 ours; printf '%s\n' "$N22"; row TOOL-zFixture-4 ours; printf '\n> routing\n'; } > "$TMP/a"
{ printf '# Index\n\nROUTING PROSE, unkeyable by design.\n\n'; printf '## TOOL — tooling\n\n'
  row TOOL-zFixture-1 base; printf '\n> routing\n'; } > "$TMP/b"
run "a repeated lead-in note against a preamble-only change" 0 "TOOL-zFixture-1 TOOL-zFixture-2 TOOL-zFixture-3 TOOL-zFixture-4 "
[ "$(grep -cF -- "$N22" "$TMP/a")" = 2 ] \
  || bad "repeated note: ours carried the note twice and the result carries $(grep -cF -- "$N22" "$TMP/a") — an incoming preamble-only change deleted one"
grep -q 'ROUTING PROSE' "$TMP/a" || bad "repeated note: theirs' preamble edit was lost"
cmp -s "$TMP/a" "$TMP/ctl" || bad "repeated note: the driver's file differs from git merge-file's, which is CORRECT here"

# --- 23. A SHARED ROW MOVED ACROSS A SECTION BOUNDARY (corpus C8, AC8, fork F9) --------------------
# THE CORPUS RECORDED THIS CONTROL AS rc 1 AND IT IS rc 0. Re-measured: with ours leaving the file
# alone, %O and %A are byte-identical, so `git merge-file` cannot conflict — it returns theirs with
# the move correctly honoured. So the corpus fixture is SAME as git, not better, and the arm records
# it that way rather than claiming otherwise. The BETTER claim holds for the keyed-edit variant
# below, by the case-19 mechanism.
{ pre; printf '## open\n\n'; row TOOL-zFixture-1 base; row TOOL-zFixture-2 base; printf '\n## closed\n\n'; row TOOL-zFixture-3 base; } > "$TMP/o"
cp "$TMP/o" "$TMP/a"                                                    # ours leaves it alone
{ pre; printf '## open\n\n'; row TOOL-zFixture-1 base; printf '\n## closed\n\n'; row TOOL-zFixture-3 base; row TOOL-zFixture-2 base; } > "$TMP/b"
cp "$TMP/a" "$TMP/ctlin"
git merge-file -p -L ours -L base -L theirs "$TMP/ctlin" "$TMP/o" "$TMP/b" >/dev/null 2>&1 && c23=0 || c23=$?
[ "$c23" = 0 ] || bad "cross-section move: the CONTROL exits $c23 where it was MEASURED at 0 — the corpus's rc 1 was the error this arm corrects, so re-measure before changing it"
run "a shared row moved across a section boundary, ours untouched" 0 "TOOL-zFixture-1 TOOL-zFixture-2 TOOL-zFixture-3 "
cl=$(at_line '^## closed$' "$TMP/a"); mv=$(at_line '^- TOOL-zFixture-2 ' "$TMP/a")
{ [ "$cl" -gt 0 ] && [ "$mv" -gt "$cl" ]; } \
  || bad "cross-section move: the moved row is at line $mv against '## closed' at $cl (0 = absent) — theirs' move was silently discarded"
cmp -s "$TMP/a" "$TMP/ctl" || bad "cross-section move: the driver's file differs from git merge-file's, which is CORRECT here"

# ...and the variant that genuinely beats git: ours edits a DIFFERENT keyed row while theirs moves.
{ pre; printf '## open\n\n'; row TOOL-zFixture-1 OURS-EDIT; row TOOL-zFixture-2 base; printf '\n## closed\n\n'; row TOOL-zFixture-3 base; } > "$TMP/a"
cp "$TMP/a" "$TMP/ctlin"
git merge-file -p -L ours -L base -L theirs "$TMP/ctlin" "$TMP/o" "$TMP/b" >/dev/null 2>&1 && c23b=0 || c23b=$?
{ [ "$c23b" -ge 1 ] && [ "$c23b" -lt 128 ]; } || bad "cross-section move + keyed edit: the CONTROL now RESOLVES this input, so the BETTER-than-git claim is stale (it answered $c23b; >=128 means it could not run at all)"
run "a shared row moved while ours edits a different keyed row" 0 "TOOL-zFixture-1 TOOL-zFixture-2 TOOL-zFixture-3 "
cl=$(at_line '^## closed$' "$TMP/a"); mv=$(at_line '^- TOOL-zFixture-2 ' "$TMP/a")
{ [ "$cl" -gt 0 ] && [ "$mv" -gt "$cl" ]; } \
  || bad "cross-section move + keyed edit: the moved row is at line $mv against '## closed' at $cl (0 = absent)"
grep -q 'OURS-EDIT' "$TMP/a" || bad "cross-section move + keyed edit: ours' edit was DISCARDED"

# --- 24. TWO DIFFERENT SEPARATOR-LESS ROWS AT THE SAME INSERTION POINT (corpus C15, AC11) ----------
# The conservatism this closes: the retired driver treated every row the grammar cannot key as
# CONTENT, so two nodes each appending one conflicted forever — for 38 of 73 rows of the real index
# when the population was measured. `git merge-file` refuses it too, so this was not "worse than
# git"; it was the auto-resolve being unavailable for the majority of the file. Rule 3 keys on the
# row SHAPE and not on the grammar, so it resolves.
{ pre; row TOOL-zFixture-1 base; } > "$TMP/o"
{ pre; row TOOL-zFixture-1 base; printf -- '- TOOL-zFixture-5b carries an id and no anchor separator (ours)\n'; } > "$TMP/a"
{ pre; row TOOL-zFixture-1 base; printf -- '- TOOL-zFixture-6b carries an id and no anchor separator (theirs)\n'; } > "$TMP/b"
keys '- TOOL-zFixture-5b carries an id and no anchor separator (ours)' \
  && bad "separator-less appends: the fixture row IS keyed by the driver — this arm proves the ordinary keyed path, not the hashed one"
cp "$TMP/a" "$TMP/ctlin"
git merge-file -p -L ours -L base -L theirs "$TMP/ctlin" "$TMP/o" "$TMP/b" >/dev/null 2>&1 && c24=0 || c24=$?
{ [ "$c24" -ge 1 ] && [ "$c24" -lt 128 ]; } || bad "separator-less appends: the CONTROL now resolves this input, so the BETTER-than-git claim is stale (it answered $c24; >=128 means it could not run at all)"
run "two different separator-less rows at one insertion point" 0 "TOOL-zFixture-1 TOOL-zFixture-5b TOOL-zFixture-6b "
for w in 5b 6b; do
  [ "$(grep -c "^- TOOL-zFixture-$w " "$TMP/a")" = 1 ] \
    || bad "separator-less appends: TOOL-zFixture-$w is not present exactly once"
done
# ...and the audit line SAYS they were hashed, which is what makes an inert grammar visible.
err=$($DRV "$TMP/o" "$TMP/a" "$TMP/b" x 2>&1 >/dev/null)
printf '%s\n' "$err" | grep -qE '\(1 keyed, 2 hashed\)' \
  || bad "separator-less appends: the audit line does not report 2 hashed rows — stderr was [$err]"

# --- 25. TWO DIFFERENT EMPTY SECTIONS OPENED (corpus C16) -----------------------------------------
# `git merge-file` resolves this CORRECTLY at rc 0 and the retired driver returned rc 1 with each
# heading doubled inside a whole-file refusal — conservative, nothing lost, and still worse than the
# merge it replaces. Each side's furniture was a different overlapping slice of the same base, so the
# adjacency dedup suppressed neither. On the structure plane there is nothing to suppress.
{ pre; row TOOL-zFixture-1 base; printf '\n## KICK — kickoff\n\n*(none yet)*\n'
  printf '\n## DEPL — deployer\n\n*(none yet)*\n'; printf '\n## end\n\n'; row TOOL-zFixture-9 base; } > "$TMP/o"
{ pre; row TOOL-zFixture-1 base; printf '\n## KICK — kickoff\n\n'; row KICK-zFixture-2 ours
  printf '\n## DEPL — deployer\n\n*(none yet)*\n'; printf '\n## end\n\n'; row TOOL-zFixture-9 base; } > "$TMP/a"
{ pre; row TOOL-zFixture-1 base; printf '\n## KICK — kickoff\n\n*(none yet)*\n'
  printf '\n## DEPL — deployer\n\n'; row DEPL-zFixture-3 theirs; printf '\n## end\n\n'; row TOOL-zFixture-9 base; } > "$TMP/b"
run "two DIFFERENT empty sections opened" 0 "DEPL-zFixture-3 KICK-zFixture-2 TOOL-zFixture-1 TOOL-zFixture-9 "
for hd in '## KICK' '## DEPL' '## end'; do
  [ "$(grep -c "^$hd" "$TMP/a")" = 1 ] \
    || bad "two empty sections: '$hd' appears $(grep -c "^$hd" "$TMP/a") time(s), expected 1"
done
k=$(at_line '^## KICK' "$TMP/a"); d=$(at_line '^## DEPL' "$TMP/a")
r1=$(at_line '^- KICK-zFixture-2 ' "$TMP/a"); r2=$(at_line '^- DEPL-zFixture-3 ' "$TMP/a")
{ [ "$r1" -gt "$k" ] && [ "$r1" -lt "$d" ] && [ "$r2" -gt "$d" ]; } \
  || bad "two empty sections: rows landed at $r1/$r2 against headings at $k/$d — each row must sit under its own family"
cmp -s "$TMP/a" "$TMP/ctl" || bad "two empty sections: the driver's file differs from git merge-file's, which is CORRECT here"

# --- 26. A STRUCTURE LINE DISPUTED ON BOTH SIDES IS ALWAYS A CONFLICT (AC12) -----------------------
# The converse of rule 3, and the refusal the whole design rests on: two nodes renaming the same
# heading differently is a decision no merge driver should make. Both versions are written between
# ONE marker pair and no row is lost — a nested pair would close the outer region early and leak
# unresolved lines into the view all the postconditions read.
{ pre; printf '## OLD HEADING\n\n'; row TOOL-zFixture-1 base; } > "$TMP/o"
{ pre; printf '## OURS HEADING\n\n'; row TOOL-zFixture-1 base; } > "$TMP/a"
{ pre; printf '## THEIRS HEADING\n\n'; row TOOL-zFixture-1 base; } > "$TMP/b"
run "a heading renamed differently on both sides" 1 "TOOL-zFixture-1 "
grep -q '^## OURS HEADING$' "$TMP/a" || bad "structure conflict: ours' rename is not in the file"
grep -q '^## THEIRS HEADING$' "$TMP/a" || bad "structure conflict: theirs' rename is not in the file"
[ "$(grep -c '^<<<<<<<' "$TMP/a")" = 1 ] && [ "$(grep -c '^>>>>>>>' "$TMP/a")" = 1 ] \
  || bad "structure conflict: expected exactly one marker pair, got $(grep -c '^<<<<<<<' "$TMP/a")/$(grep -c '^>>>>>>>' "$TMP/a")"
[ "$(grep -c '^- TOOL-zFixture-1 ' "$TMP/a")" = 1 ] \
  || bad "structure conflict: the undisputed row is not present exactly once — a structure conflict must not disturb the row plane"
# ...and the conflict is SCOPED: it is git's own hunk, not the whole file (corpus C17's ergonomics).
[ "$(wc -l < "$TMP/a")" -lt "$(( $(wc -l < "$TMP/o") * 2 ))" ] \
  || bad "structure conflict: the refusal is a whole-file sandwich, not the scoped hunk git produced"

# --- 27. EVERY SYNTHESIZED MARKER CARRIES THE FILE'S TERMINATOR, AT rc 1 (corpus C22, AC13) --------
# The retired driver wrote `<<<<<<< ours`, `=======` and `>>>>>>> theirs` with LF into an all-CRLF
# file — measured `lines: 13 | without CR: 3`. The clean-merge arm in 7b could not see it because a
# clean merge synthesizes no markers. Site 6 of the newline contract closes it, and this is the arm.
{ cprose alpha beta; crow TOOL-zFixture-1 base; } > "$TMP/o"
{ cprose alpha beta; crow TOOL-zFixture-1 OURS; } > "$TMP/a"
{ cprose alpha beta; crow TOOL-zFixture-1 THEIRS; } > "$TMP/b"
run "crlf file, row conflict at rc 1" 1 "TOOL-zFixture-1 "
grep -q '^<<<<<<<' "$TMP/a" || bad "crlf markers: no conflict written, so the marker terminator is untested"
nocr=$(LC_ALL=C grep -cv $'\r$' "$TMP/a" || true)
[ "$nocr" = 0 ] \
  || bad "crlf markers: $nocr line(s) of an all-CRLF file end without CR — a synthesized marker used the wrong terminator"
# ...and the mirror, so the fix is not "always write CRLF".
{ prose alpha beta; row TOOL-zFixture-1 base; } > "$TMP/o"
{ prose alpha beta; row TOOL-zFixture-1 OURS; } > "$TMP/a"
{ prose alpha beta; row TOOL-zFixture-1 THEIRS; } > "$TMP/b"
run "lf file, row conflict at rc 1" 1 "TOOL-zFixture-1 "
cr=$(endings "$TMP/a")
[ "${cr%%:*}" = 0 ] || bad "lf markers: CR:LF byte counts are $cr — a CR was introduced into an LF file at rc 1"
# ...and the fail-closed path, which is a THIRD synthesis site and the one an author hits when the
# grammar cannot be read at all.
S=$(mkscratch); cp .memory-tree.conf "$S/"
printf 'this is not valid syntax(\n' > "$S/tools/memory-recall/extract.py"
{ cprose alpha beta; crow TOOL-zFixture-1 base; } > "$TMP/o"
{ cprose alpha beta; crow TOOL-zFixture-1 OURS; } > "$TMP/a"
{ cprose alpha beta; crow TOOL-zFixture-1 THEIRS; } > "$TMP/b"
"$PY" "$S/tools/memory-tree/merge-rows.py" "$TMP/o" "$TMP/a" "$TMP/b" x >/dev/null 2>&1
nocr=$(LC_ALL=C grep -cv $'\r$' "$TMP/a" || true)
[ "$nocr" = 0 ] \
  || bad "crlf markers (fail-closed): $nocr line(s) end without CR — the fail-closed body is the third synthesis site"

# --- 28. A NOTE REPEATED WITHIN ONE SIDE SURVIVES TWICE (AC22) -------------------------------------
# A NEVER-REGRESS BAR, not an improvement claim: the driver this replaces is CORRECT on this shape.
# It exists because a spec-faithful prototype of the redesign's first revision was not — stating
# rule 3 as "each distinct key emitted once" rebuilt the deleted file-wide-uniqueness assumption on
# the row plane, and it DELETED one of ours' own two copies at rc 0 with a `clean` audit line. No
# postcondition saw it: the duplicate caps are maxima, so under-writing is invisible to them. Hence
# positional concatenation with dedup ACROSS sides only, and hence this arm.
{ printf '# t\n\n'; row TOOL-zFixture-1 base; } > "$TMP/o"
{ printf '# t\n\n'; row TOOL-zFixture-1 base; printf -- '- repeated bullet\n'; row TOOL-zFixture-2 ours
  printf -- '- repeated bullet\n'; } > "$TMP/a"
{ printf '# t\n\n'; row TOOL-zFixture-1 base; row TOOL-zFixture-3 theirs; } > "$TMP/b"
cp "$TMP/a" "$TMP/ctlin"
git merge-file -p -L ours -L base -L theirs "$TMP/ctlin" "$TMP/o" "$TMP/b" >/dev/null 2>&1 && c28=0 || c28=$?
{ [ "$c28" -ge 1 ] && [ "$c28" -lt 128 ]; } || bad "within-side repeat: the CONTROL now resolves this input — re-measure before treating rc 0 as better than git (it answered $c28; >=128 means it could not run at all)"
run "a note repeated WITHIN ours' own side" 0 "TOOL-zFixture-1 TOOL-zFixture-2 TOOL-zFixture-3 "
[ "$(grep -cF -- '- repeated bullet' "$TMP/a")" = 2 ] \
  || bad "within-side repeat: ours carried the note twice and the result carries $(grep -cF -- '- repeated bullet' "$TMP/a") — rule 3 deduped WITHIN a side"

# --- 29. AN UNTERMINATED FINAL ROW RELOCATED AWAY FROM END OF FILE (AC24) --------------------------
# Newline site 7, and the corruption a spec-faithful prototype shipped: ours appends an unterminated
# final row while theirs appends a terminated one, rule 3 emits ours' token first, the EMPTY
# terminator rides along, and the join FUSES TWO RECORDS ONTO ONE LINE — rc 0, no markers, audit line
# `clean`, where the control refuses at rc 1 with both rows intact. Asserted on the file ON DISK,
# because in a list of lines two glued records are still two elements and every postcondition passes.
{ printf '# t\n\n'; row TOOL-zFixture-1 base; } > "$TMP/o"
{ printf '# t\n\n'; row TOOL-zFixture-1 base; printf -- '- TOOL-zFixture-2 · OPEN · ours'; } > "$TMP/a"   # NO terminator
{ printf '# t\n\n'; row TOOL-zFixture-1 base; row TOOL-zFixture-3 theirs; } > "$TMP/b"
cp "$TMP/a" "$TMP/ctlin"
git merge-file -p -L ours -L base -L theirs "$TMP/ctlin" "$TMP/o" "$TMP/b" >/dev/null 2>&1; c29=$?
[ "$c29" = 1 ] || bad "unterminated final row: the CONTROL exits $c29 where the arm's prose says it refuses at rc 1 with both rows intact"
run "ours' final row carries no terminator (rule 3)" 0 "TOOL-zFixture-1 TOOL-zFixture-2 TOOL-zFixture-3 "
[ "$(grep -c '^- TOOL-zFixture-2 · OPEN · ours$' "$TMP/a")" = 1 ] \
  || bad "unterminated final row: ours' record is not a line of its own — it fused with its neighbour"
[ "$(grep -c '^- TOOL-zFixture-3 ' "$TMP/a")" = 1 ] \
  || bad "unterminated final row: theirs' record is not a line of its own"
grep -q 'ours- TOOL-' "$TMP/a" && bad "unterminated final row: two records are on one line"
# ...and the rule-2 path, where a formerly-final row is relocated mid-file by an incoming insert.
{ printf '# t\n\n'; row TOOL-zFixture-1 base; } > "$TMP/o"
{ printf '# t\n\n'; row TOOL-zFixture-1 base; printf -- '- TOOL-zFixture-2 · OPEN · ours'; } > "$TMP/a"
{ printf '# t\n\n'; row TOOL-zFixture-1 base; row TOOL-zFixture-3 theirs; row TOOL-zFixture-4 theirs; } > "$TMP/b"
run "a formerly-final row relocated mid-file (rule 2)" 0 "TOOL-zFixture-1 TOOL-zFixture-2 TOOL-zFixture-3 TOOL-zFixture-4 "
for w in 1 2 3 4; do
  [ "$(grep -c "^- TOOL-zFixture-$w · " "$TMP/a")" = 1 ] \
    || bad "relocated final row: TOOL-zFixture-$w is not on a line of its own"
done

# --- 30. A FILE CARRYING THE SAME ROW LINE TWICE, MERGED AND APPENDED TO (AC21) --------------------
# The identity half is in case 7; this is the both-sides-append half. A `key -> line` row plane
# resolved the repeated key to ONE line while the skeleton carried its token TWICE, so the file
# failed its own identity merge with a 15-line whole-file marker sandwich — a permanent conflict no
# author action clears. `key -> LIST` with the branch's own multiplicity is what makes it ordinary.
cp "$TMP/rep.md" "$TMP/o"
{ cat "$TMP/rep.md"; row TOOL-zFixture-8 ours; } > "$TMP/a"
{ cat "$TMP/rep.md"; row TOOL-zFixture-9 theirs; } > "$TMP/b"
run "both sides append to a file with a repeated row line" 0 "TOOL-zFixture-1 TOOL-zFixture-2 TOOL-zFixture-8 TOOL-zFixture-9 "
[ "$(grep -c '^  - notes$' "$TMP/a")" = 2 ] \
  || bad "repeated row line: the result carries $(grep -c '^  - notes$' "$TMP/a") copies of a line the input carries twice"
for w in 8 9; do
  [ "$(grep -c "^- TOOL-zFixture-$w " "$TMP/a")" = 1 ] || bad "repeated row line: the append TOOL-zFixture-$w is missing"
done

# --- 31. A ROW CONFLICT INSIDE A STRUCTURE CONFLICT IS NOT NESTED (AC25) ---------------------------
# Rule 4 substitutes each token by the row from the SIDE OF THE REGION IT APPEARS ON, never by the
# row plane's verdict — because that verdict can itself be a marker block, and read across, rule 4
# would nest a conflict inside a conflict. `settled()` tracks ONE boolean, so the inner `>>>>>>>`
# closes the outer region early and the remainder leaks into the view all the postconditions read.
# Reachable through the delete/modify branch: ours edits a row and appends another, theirs deletes
# that row and renames its heading.
{ pre; printf '## H\n\n'; row TOOL-zFixture-1 base; } > "$TMP/o"
{ pre; printf '## H\n\n'; row TOOL-zFixture-1 OURS-EDIT; row TOOL-zFixture-2 ours; } > "$TMP/a"
{ pre; printf '## H RENAMED\n\n'; } > "$TMP/b"
run "a delete/modify row inside a heading rename" 1 "TOOL-zFixture-1 TOOL-zFixture-2 "
[ "$(grep -c '^<<<<<<<' "$TMP/a")" = "$(grep -c '^>>>>>>>' "$TMP/a")" ] \
  || bad "nested markers: $(grep -c '^<<<<<<<' "$TMP/a") open markers against $(grep -c '^>>>>>>>' "$TMP/a") close markers"
# ...the decisive assertion: `settled()` over the OUTPUT must return only settled lines, which is
# false the moment a region closes early. Asserted against the driver's own function, because that
# view is what every postcondition reads.
"$PY" - "$TMP/a" <<'PYEOF'
import importlib.util, sys
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("mr", "tools/memory-tree/merge-rows.py")
mr = importlib.util.module_from_spec(spec); spec.loader.exec_module(mr)
lines = mr.read(sys.argv[1])
leaked = [ln for ln in mr.settled(lines) if ln.lstrip().startswith(("<<<<<<<", "=======", ">>>>>>>"))]
sys.exit(1 if leaked else 0)
PYEOF
[ $? = 0 ] || bad "nested markers: settled() over the written file still returns marker lines — a region closed early and unresolved content leaked into the postconditions' view"

# --- 32. THE CONFLICT STYLE IS PINNED AT THE CALL SITE (AC23, fork F8) -----------------------------
# `git merge-file` honours the invoking repo's `merge.conflictStyle`, and git runs a merge driver
# from the top of the worktree, so a node-local `diff3`/`zdiff3` reaches the driver. Under three
# sections a token-only region stops being token-only, rule 3 evaporates, and every BETTER-than-git
# case vanishes ON THAT NODE ONLY — the same driver answering two ways on identical blobs. This
# repo's config sets no style, so a fixture that relies on the ambient value is blind to the shape.
# THE PREMISE IS ASSERTED FIRST: the control must actually change shape under diff3, or the arm is
# proving that a setting nobody honours changes nothing.
G=$(mktemp -d); SCRATCH="$SCRATCH $G"
( cd "$G" && git init -q -b main && git config user.email t@e && git config user.name t )
{ pre; row TOOL-zFixture-1 base; printf '\n## Section two\n\n*(none yet)*\n'; } > "$G/o"
{ pre; row TOOL-zFixture-1 base; printf '\n## Section two\n\n'; row TOOL-zFixture-2 ours; } > "$G/a0"
{ pre; row TOOL-zFixture-1 base; printf '\n## Section two\n\n'; row TOOL-zFixture-3 theirs; } > "$G/b"
cp "$G/a0" "$G/actl"
( cd "$G" && git -c merge.conflictStyle=diff3 merge-file -p -L ours -L base -L theirs actl o b > ctl3 2>/dev/null )
grep -q '^|||||||' "$G/ctl3" \
  || bad "conflict style: git merge-file under diff3 emitted no '|||||||' section on this host — the arm's premise is unmet and it proves nothing"
for style in diff3 zdiff3; do
  ( cd "$G" && git config merge.conflictStyle "$style" )
  cp "$G/a0" "$G/a"
  ( cd "$G" && bash "$ROOT/tools/lib/pyrun.sh" "$ROOT/tools/memory-tree/merge-rows.py" o a b x >/dev/null 2>&1 ) && rc=0 || rc=$?
  [ "$rc" = 0 ] \
    || bad "conflict style=$style: the driver exited $rc where the same three blobs resolve at rc 0 with the style unset — a node's config changed the verdict"
  [ "$(grep -c '^## Section two$' "$G/a")" = 1 ] \
    || bad "conflict style=$style: the heading appears $(grep -c '^## Section two$' "$G/a") time(s), expected 1"
  for w in 2 3; do
    [ "$(grep -c "^- TOOL-zFixture-$w " "$G/a")" = 1 ] \
      || bad "conflict style=$style: TOOL-zFixture-$w is not filed exactly once"
  done
  [ "$(grep -c '<<<<<<<' "$G/a")" = 0 ] || bad "conflict style=$style: markers written on an arm that must auto-resolve"
done

# --- 33. THE FIVE POSTCONDITIONS ARE ARMED (AC14) --------------------------------------------------
# A postcondition no fixture can reach is a comment. `check-arms.py` cannot help here — it discovers
# gates as tracked `*.sh` files defining `fail() {`, so a Python driver is structurally outside its
# population — which is exactly why these are hand-written.
#
# AND TWO OF THE FIVE CANNOT BE REACHED BY ANY INPUT, which is a measured property of the redesign
# rather than a gap. Identical stripped text produces the identical `raw:` key, so every duplicate an
# INPUT can express is one key with one entry and two tokens — and the CONSTRUCTION-level
# conservation inside `take()` refuses it before a single postcondition runs. Measured across the
# duplicate shapes in this file: case 12, case 15 and case 20 all refuse with `RowLoss` no matter
# which postcondition is disabled. So `no_row_loss`, `structure_identity` and the LINE half of
# `no_new_duplicates` are BACKSTOPS behind that construction, and the honest way to arm a backstop is
# to inject the defect it backs onto: a reconstruction that drops a row, drops a structure line, or
# writes a row twice. Each arm below then shows the named check is the SOLE net — it refuses, and
# disabling only it makes the same injection pass.
#
# The harness is a MONKEYPATCH rather than an edited copy, so a red proves the named check is what
# refuses rather than that some edit broke the driver. `census` and `row_ids` are patched instead of
# `no_new_duplicates` because that function carries two independent halves and AC14 wants each armed
# separately. Mutations compose, comma-separated.
cat > "$TMP/sabotage.py" <<'PYEOF'
import importlib.util, sys
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("mr", "tools/memory-tree/merge-rows.py")
mr = importlib.util.module_from_spec(spec); spec.loader.exec_module(mr)
_real = mr.reconcile


def _inject(what):
    def patched(skel, *a, **k):
        out, facts = _real(skel, *a, **k)
        rows = [i for i, ln in enumerate(out) if mr._ROW_RE.match(ln)]
        struct = [i for i, ln in enumerate(out)
                  if not mr._ROW_RE.match(ln) and ln.strip() and not mr._MARKER_RE.match(ln.lstrip())]
        if what == "row_drop" and rows:
            del out[rows[-1]]
        elif what == "row_dup" and rows:
            out.insert(rows[-1], out[rows[-1]])
        elif what == "structure_drop" and struct:
            del out[struct[-1]]
        else:
            raise SystemExit("the injection found nothing to mutate — the arm would be vacuous")
        return out, facts
    return patched


for w in sys.argv[1].split(","):
    if w == "none":
        pass
    elif w == "row_loss":
        mr.no_row_loss = lambda *a, **k: None
    elif w == "structure":
        mr.structure_identity = lambda *a, **k: None
    elif w == "dup_line":
        mr.census = lambda lines: {}
    elif w == "dup_id":
        mr.row_ids = lambda lines: {}
    elif w == "misfiled":
        mr.no_misfiled_rows = lambda *a, **k: None
    elif w in ("row_drop", "row_dup", "structure_drop"):
        mr.reconcile = _inject(w)
    else:
        raise SystemExit("unknown sabotage " + w)
raise SystemExit(mr.main([sys.argv[0]] + sys.argv[2:]))
PYEOF
sab() {  # $1 mutations · echoes "<rc> <first exception class or ->"
  local rc err
  cp "$TMP/sab.a" "$TMP/a"
  err=$("$PY" "$TMP/sabotage.py" "$1" "$TMP/o" "$TMP/a" "$TMP/b" x 2>&1 >/dev/null) && rc=0 || rc=$?
  printf '%s %s' "$rc" "$(printf '%s' "$err" | sed -n 's/.*FAILED (\([A-Za-z]*\):.*/\1/p' | head -1)"
}
# ...the harness is proved live in BOTH directions first, or every verdict below is the wrapper's.
mk16; cp "$TMP/a" "$TMP/sab.a"
[ "$(sab none)" = "1 DuplicatedContent" ] \
  || bad "sabotage harness: un-sabotaged it answers [$(sab none)] where the driver itself refuses case 16 with DuplicatedContent — the wrapper is not running the driver"
# THE INJECTION FIXTURE'S LAST ROW IS DELIBERATELY ID-LESS. The injections below mutate the last row
# line of the reconstruction, and an id-carrying one is ALSO caught by the id half — which would make
# arm (c) unable to tell the two halves apart. Theirs' rows follow ours' in the reconstruction, so a
# trailing bare note on theirs is the line that gets mutated.
{ pre; row TOOL-zFixture-1 base; } > "$TMP/o"
{ pre; row TOOL-zFixture-1 base; row TOOL-zFixture-2 ours; } > "$TMP/a"
{ pre; row TOOL-zFixture-1 base; row TOOL-zFixture-3 theirs; printf -- '- a bare trailing note with no id\n'; } > "$TMP/b"
cp "$TMP/a" "$TMP/sab.a"; cp "$TMP/a" "$TMP/ok.a"; cp "$TMP/o" "$TMP/ok.o"; cp "$TMP/b" "$TMP/ok.b"
[ "$(sab none)" = "0 " ] \
  || bad "sabotage harness: un-sabotaged it answers [$(sab none)] on an ordinary clean merge — every injection below would red for the wrong reason"
printf -- '- a bare trailing note with no id\n' > "$TMP/injrow"
[ -z "$(ids "$TMP/injrow")" ] \
  || bad "sabotage harness: the injected row carries an id, so arm (c) cannot separate the line half from the id half"

# (a) the ID half — one id, two wordings, two different `raw:` keys, so conservation cannot see it.
mk16; cp "$TMP/a" "$TMP/sab.a"
[ "$(sab dup_id)" = "0 " ] \
  || bad "postcondition arm: with the id half disabled, case 16 still refuses [$(sab dup_id)] — the id half is not what catches it"

# (b) MISFILED — a heading DELETED on one side refiles the rows under it, and no row is duplicated,
# so conservation is silent and placement is the only check that can speak.
{ pre; printf '## A\n\n'; row TOOL-zFixture-1 base; printf '\n## B\n\n'; row TOOL-zFixture-2 base; } > "$TMP/o"
{ pre; printf '## A\n\n'; row TOOL-zFixture-1 base; printf '\n'; row TOOL-zFixture-2 base; } > "$TMP/a"
{ pre; printf '## A\n\n'; row TOOL-zFixture-1 base; printf '\n## B\n\n'; row TOOL-zFixture-2 base; row TOOL-zFixture-3 theirs; } > "$TMP/b"
cp "$TMP/a" "$TMP/sab.a"
[ "$(sab none)" = "1 Misfiled" ] \
  || bad "postcondition arm: a heading deletion that refiles a row answers [$(sab none)], expected a Misfiled refusal"
[ "$(sab misfiled)" = "0 " ] \
  || bad "postcondition arm: with no_misfiled_rows disabled that shape still refuses [$(sab misfiled)] — the placement check is not what catches it"

# (c) the LINE half — injected: the reconstruction writes one row twice.
cp "$TMP/ok.o" "$TMP/o"; cp "$TMP/ok.b" "$TMP/b"; cp "$TMP/ok.a" "$TMP/sab.a"
[ "$(sab row_dup)" = "1 DuplicatedContent" ] \
  || bad "postcondition arm: a reconstruction writing a row twice answers [$(sab row_dup)], expected the LINE half of no_new_duplicates to refuse"
[ "$(sab row_dup,dup_line)" = "1 RowLoss" ] \
  || bad "postcondition arm: with the line half disabled the same injection answers [$(sab row_dup,dup_line)] — conservation should be the next net, and if it is not, the line half is the ONLY net and must not be removed"
[ "$(sab row_dup,dup_line,row_loss)" = "0 " ] \
  || bad "postcondition arm: with both duplicate nets disabled the injection still refuses [$(sab row_dup,dup_line,row_loss)] — some third check is doing the work and these two arms attribute it wrongly"

# (d) `no_row_loss` — injected: the reconstruction drops a row after the construction check passed.
[ "$(sab row_drop)" = "1 RowLoss" ] \
  || bad "postcondition arm: a reconstruction dropping a row answers [$(sab row_drop)], expected no_row_loss to refuse"
[ "$(sab row_drop,row_loss)" = "0 " ] \
  || bad "postcondition arm: with no_row_loss disabled a dropped row still refuses [$(sab row_drop,row_loss)] — the conservation arm attributes it wrongly"

# (e) `structure_identity` — injected: the reconstruction drops a structure line.
[ "$(sab structure_drop)" = "1 StructureDrift" ] \
  || bad "postcondition arm: a reconstruction dropping a structure line answers [$(sab structure_drop)], expected structure_identity to refuse"
[ "$(sab structure_drop,structure)" = "0 " ] \
  || bad "postcondition arm: with structure_identity disabled a dropped structure line still refuses [$(sab structure_drop,structure)] — nothing else was watching the structure plane, so this arm attributes it wrongly"

# ...and the measured fact the block above rests on, asserted rather than described: every
# INPUT-reachable duplicate is refused by the construction, not by a postcondition.
mk12; cp "$TMP/a" "$TMP/sab.a"
[ "$(sab dup_line,dup_id,row_loss,structure,misfiled)" = "1 RowLoss" ] \
  || bad "construction conservation: with ALL FIVE postconditions disabled, case 12's duplicate answers [$(sab dup_line,dup_id,row_loss,structure,misfiled)] — take()'s conservation is what refuses an input-reachable duplicate, and the arms above are written on that measurement"

# --- 35. A KEY PRESENT ON BOTH SIDES OF A rule-4 REGION -------------------------------------------
# The most ordinary rule-4 shape there is: two nodes rename the same heading AND each append a row,
# so the shared row's token lands on BOTH sides of git's hunk. One cursor shared across the region's
# ours/base/theirs sections consumed ours' only body on the ours side and then ran off the end on
# the theirs side — a `StructureDrift` refusal and a whole-file marker sandwich where git returns a
# scoped hunk. Per side the driver's output is byte-identical to git's, and THAT is the assertion:
# an rc-only arm reads identically whether the region was reproduced or the file was sandwiched.
{ printf '# t\n\n## H\n\n'; row TOOL-zFixture-1 base; } > "$TMP/o"
{ printf '# t\n\n## Hours\n\n'; row TOOL-zFixture-1 base; row TOOL-zFixture-2 ours; } > "$TMP/a"
{ printf '# t\n\n## Hthem\n\n'; row TOOL-zFixture-1 base; row TOOL-zFixture-3 theirs; } > "$TMP/b"
run "a shared row on both sides of a heading-rename hunk" 1 "TOOL-zFixture-1 TOOL-zFixture-2 TOOL-zFixture-3 "
cmp -s "$TMP/a" "$TMP/ctl" \
  || bad "rule-4 both sides: the driver's file differs from git merge-file's — a cursor shared across the region's sections refuses where git emits a scoped hunk"
[ "$(grep -c '^<<<<<<<' "$TMP/a")" = 1 ] \
  || bad "rule-4 both sides: $(grep -c '^<<<<<<<' "$TMP/a") marker pair(s) — a whole-file sandwich is not a scoped hunk"

# --- 36. A LINE ENDS IN CRLF, LF OR CR — AND IN NOTHING ELSE ---------------------------------------
# `str.splitlines()` also breaks on VT, FF, FS, GS, RS, NEL, U+2028 and U+2029, none of which git or
# `_split_term` treat as terminators. Splitting with one rule and terminating with another made a
# file carrying a U+2028 soft break — the ordinary Word/macOS paste — FAIL ITS OWN IDENTITY MERGE,
# and the fail-closed body then wrote the line back split in two by a newline that was never in the
# input. The control returns it byte for byte at rc 0.
for esc in '\013' '\014' '\034' '\035' '\036' '\302\205' '\342\200\250' '\342\200\251'; do
  { printf "# t\n\nA${esc}B\n\n"; row TOOL-zFixture-1 base; } > "$TMP/brk"
  cp "$TMP/brk" "$TMP/o"; cp "$TMP/brk" "$TMP/a"; cp "$TMP/brk" "$TMP/b"
  $DRV "$TMP/o" "$TMP/a" "$TMP/b" x >/dev/null 2>&1 \
    || bad "line breaks: an identity merge of a file containing byte(s) [$esc] reported a conflict"
  cmp -s "$TMP/brk" "$TMP/a" \
    || bad "line breaks: an identity merge of a file containing byte(s) [$esc] REWROTE it — the splitter and the terminator disagree about what a line is"
done
# ...and the fixture is not vacuous: the character really is one `str.splitlines` breaks on, so the
# arm would have failed before the fix rather than passing over a shape nothing produces.
"$PY" -c 'import sys; sys.exit(0 if len("A B\n".splitlines()) == 2 else 1)' \
  || bad "line breaks: U+2028 does not split under str.splitlines on this interpreter — the arm asserts nothing"

# --- 37. A BYTE THAT IS NOT VALID UTF-8 SURVIVES THE MERGE -----------------------------------------
# `errors="replace"` turned every such byte into U+FFFD and `write_bytes` committed the replacement:
# a CP-1252 apostrophe pasted into a record was DESTROYED at rc 0 with a `clean` audit line, and two
# sides carrying DIFFERENT invalid bytes at one spot decoded EQUAL and auto-resolved to a third
# value neither author wrote. `git merge-file` preserves those bytes exactly, so this is squarely
# the never-worse bar. Asserted on BYTES — the corruption is invisible in any decoded view, which is
# why every postcondition was silent over it.
{ printf '# t\n\n## TOOL\n\n'; printf -- '- TOOL-zFixture-1 \302\267 the node\222s ledger \227 kept\n'; } > "$TMP/o"
cp "$TMP/o" "$TMP/a"; cp "$TMP/o" "$TMP/b"
row TOOL-zFixture-2 ours >> "$TMP/a"; row TOOL-zFixture-3 theirs >> "$TMP/b"
run "a CP-1252 byte in a record neither side touched" 0 "TOOL-zFixture-1 TOOL-zFixture-2 TOOL-zFixture-3 "
LC_ALL=C grep -q "$(printf 'node\222s')" "$TMP/a" \
  || bad "invalid bytes: the 0x92 in a record NEITHER side touched was rewritten — U+FFFD is not the byte the author typed"
LC_ALL=C grep -q "$(printf '\357\277\275')" "$TMP/a" \
  && bad "invalid bytes: a U+FFFD replacement character reached the written file"
# ...and two sides carrying DIFFERENT invalid bytes are two different records, never one.
printf '# t\n\n## TOOL\n\n- TOOL-zFixture-1 \302\267 v0\n'    > "$TMP/o"
printf '# t\n\n## TOOL\n\n- TOOL-zFixture-1 \302\267 v\267\n' > "$TMP/a"
printf '# t\n\n## TOOL\n\n- TOOL-zFixture-1 \302\267 v\240\n' > "$TMP/b"
$DRV "$TMP/o" "$TMP/a" "$TMP/b" x >/dev/null 2>&1 \
  && bad "invalid bytes: two sides with DIFFERENT invalid bytes at one spot merged CLEAN — they decoded equal and a third value neither author wrote was committed"
LC_ALL=C grep -q "$(printf 'v\267')" "$TMP/a" || bad "invalid bytes: ours' byte is not in the conflict"
LC_ALL=C grep -q "$(printf 'v\240')" "$TMP/a" || bad "invalid bytes: theirs' byte is not in the conflict"

# --- 38. INDENTATION IS NESTING, AND NESTING IS CONTENT --------------------------------------------
# The `raw:` digest hashed `line.strip()`, so `- notes` and `  - notes` — two different records in
# markdown — collapsed to ONE key. The row plane then resolved two distinct lines as one and rule 4
# substituted one side's body for the other's: measured, a line carried identically by all three
# inputs and touched by nobody was DESTROYED while another was written twice, at rc 1, with the loss
# OUTSIDE the marked hunk where the author resolving it has no signal. The control is rc 0 and
# correct, so this is the never-worse bar again.
printf -- '- notes\n* TOOL-zFixture-4 | star\n- TOOL-zFixture-2 | beta\n' > "$TMP/o"
printf -- '  - notes\n- notes\n* TOOL-zFixture-4 | star\n- TOOL-zFixture-2 | beta\n' > "$TMP/a"
printf -- '- notes\n### sub\n- TOOL-zFixture-2 | beta\n' > "$TMP/b"
run "a nested twin of an unkeyable row" 0 "TOOL-zFixture-2 " TOOL-zFixture-4
[ "$(grep -cx -- '- notes' "$TMP/a")" = 1 ] \
  || bad "nesting: the un-indented note, carried by all three inputs and edited by nobody, appears $(grep -cx -- '- notes' "$TMP/a") time(s) — expected exactly 1"
[ "$(grep -cx -- '  - notes' "$TMP/a")" = 1 ] \
  || bad "nesting: ours' indented note appears $(grep -cx -- '  - notes' "$TMP/a") time(s) — expected exactly 1"
cmp -s "$TMP/a" "$TMP/ctl" || bad "nesting: the driver's file differs from git merge-file's, which is CORRECT here"

# --- 39. A CONFLICTED KEY IN TWO SECTIONS REFUSES RATHER THAN RELOCATING ---------------------------
# A marker block that "speaks for every occurrence of its key" reads as a tidy way to avoid a
# refusal. Measured, it RELOCATES: one key carried in two `## FAMILY` sections and edited on both
# sides collapsed into a single block under the FIRST heading and left the second section empty, at
# rc 1, where git emits two scoped conflicts in place. Whichever side the author then picks, the
# record has permanently left the section it was filed under — the exact class `no_misfiled_rows`
# exists to refuse and cannot see, because `sections()` records only a key's FIRST heading.
{ pre; printf '## PLAY\n\n'; row PLAY-zFixture-1 a; printf '  - shared note \n'; row PLAY-zFixture-2 b
  printf '\n## TOOL\n\n'; row TOOL-zFixture-3 c; printf '  - shared note \n'; } > "$TMP/o"
sed 's/  - shared note $/  - shared note/'  "$TMP/o" > "$TMP/a"
sed 's/  - shared note $/   - shared note/' "$TMP/o" > "$TMP/b"
err=$($DRV "$TMP/o" "$TMP/a" "$TMP/b" x 2>&1 >/dev/null); rc=$?
[ "$rc" = 1 ] || bad "two-section key: rc=$rc, expected 1 — a key carried in two sections must never be collapsed into one block"
printf '%s\n' "$err" | grep -q 'RowLoss' \
  || bad "two-section key: the refusal does not name conservation — stderr was [$err]"
[ "$(awk '/## TOOL/,0' "$TMP/a" | grep -c 'shared note')" -gt 0 ] \
  || bad "two-section key: the '## TOOL' section lost its note entirely — the record was relocated across a heading"

# --- 40. A ROW ONE SIDE MOVED AND THE OTHER DELETED (TOOL-aMendedLedger-9) -------------------------
# THE ONE CASE IN THIS FILE WHERE THE DRIVER CONFLICTS AND GIT RESOLVES, and it is the reason
# `CONSERVATIVE_CAP` is 1 rather than 0. Before the fix this was rc 0 CONTENT LOSS: the row plane's
# delete branch compares the key's row BODIES, which a relocation does not change, so a side that
# deliberately MOVED a record read as having left it alone and the other side's delete was honoured.
# Measured on the flat backlog shape with no headings involved, and confirmed through a real
# `git merge`: auto-committed, `1 deletion(-)`, no markers, while `git merge-file` keeps the row.
#
# The row plane is position-blind by design — ordering is the skeleton's job — so it cannot see the
# move. The SKELETON can, and git has already ruled there: a surviving token for a key the row plane
# deleted can only mean the side that kept it MOVED it, because a side that left a row alone
# contributes no token git would place anywhere new. The two planes disagree, and neither answer is
# the driver's to pick silently: honouring the delete discards a deliberate relocation, honouring the
# move discards a deliberate delete. That is delete/modify by another name, and it takes the same
# answer — a scoped conflict naming both. Asserted on BYTES, because an rc-only arm reads the same
# whether the row survived or was swallowed, which is the exact failure this case exists for.
{ printf '# tooling backlog\n\n'; row TOOL-zFixture-1 one; row TOOL-zFixture-2 two; row TOOL-zFixture-3 three; } > "$TMP/o"
{ printf '# tooling backlog\n\n'; row TOOL-zFixture-1 one; row TOOL-zFixture-3 three; row TOOL-zFixture-2 two; } > "$TMP/a"
{ printf '# tooling backlog\n\n'; row TOOL-zFixture-1 one; row TOOL-zFixture-3 three; } > "$TMP/b"
cp "$TMP/a" "$TMP/ctlin"
git merge-file -p -L ours -L base -L theirs "$TMP/ctlin" "$TMP/o" "$TMP/b" > "$TMP/ctl40" 2>/dev/null; c40=$?
{ [ "$c40" = 0 ] && [ "$(grep -c '^- TOOL-zFixture-2 ' "$TMP/ctl40")" = 1 ]; } \
  || bad "move-vs-delete: the CONTROL answered $c40 with $(grep -c '^- TOOL-zFixture-2 ' "$TMP/ctl40") copies of the moved row — this arm is the tally's only member BECAUSE git resolves it correctly, so re-measure before changing the cap"
run "a row ours MOVED and theirs DELETED" 1 "TOOL-zFixture-1 TOOL-zFixture-2 TOOL-zFixture-3 "
[ "$(grep -c '^- TOOL-zFixture-2 ' "$TMP/a")" = 1 ] \
  || bad "move-vs-delete: the moved row appears $(grep -c '^- TOOL-zFixture-2 ' "$TMP/a") time(s) — it must survive the refusal exactly once, or the conflict is hiding the loss it exists to prevent"
grep -q '^<<<<<<< ours$' "$TMP/a" || bad "move-vs-delete: rc 1 with no markers is the marker-free-UU trap"
grep -q '^>>>>>>> theirs (deleted)$' "$TMP/a" \
  || bad "move-vs-delete: the conflict does not name the DELETE, so the author cannot see what the other side intended"
[ "$(grep -c '^<<<<<<<' "$TMP/a")" = 1 ] \
  || bad "move-vs-delete: $(grep -c '^<<<<<<<' "$TMP/a") marker pair(s) — the refusal must be SCOPED to the disputed key, not a whole-file sandwich"
# ...and the MIRROR, because the delete branch has two arms and only one of them was measured.
{ printf '# tooling backlog\n\n'; row TOOL-zFixture-1 one; row TOOL-zFixture-3 three; } > "$TMP/a"
{ printf '# tooling backlog\n\n'; row TOOL-zFixture-1 one; row TOOL-zFixture-3 three; row TOOL-zFixture-2 two; } > "$TMP/b"
run "a row theirs MOVED and ours DELETED" 1 "TOOL-zFixture-1 TOOL-zFixture-2 TOOL-zFixture-3 "
[ "$(grep -c '^- TOOL-zFixture-2 ' "$TMP/a")" = 1 ] \
  || bad "move-vs-delete mirror: the moved row is not present exactly once"
grep -q '^<<<<<<< ours (deleted)$' "$TMP/a" \
  || bad "move-vs-delete mirror: the conflict does not name OURS' delete"
# ...and an ORDINARY honoured delete is untouched by all of this: no token survives, no conflict.
{ printf '# tooling backlog\n\n'; row TOOL-zFixture-1 one; row TOOL-zFixture-2 two; } > "$TMP/o"
{ printf '# tooling backlog\n\n'; row TOOL-zFixture-1 one; row TOOL-zFixture-2 two; } > "$TMP/a"
{ printf '# tooling backlog\n\n'; row TOOL-zFixture-1 one; } > "$TMP/b"
run "an ordinary delete is still honoured silently" 0 "TOOL-zFixture-1 " TOOL-zFixture-2

# --- 34. THE CONSERVATIVE TALLY — a redesign that trades a fix for a conflict must SHOW it (AC3) ---
ncons=$(printf '%s' "$CONSERVATIVE" | grep -c . || true)
if [ "$ncons" -gt "$CONSERVATIVE_CAP" ]; then
  echo "FAIL the driver conflicts where git resolves correctly in $ncons case(s), against a shrink-only cap of $CONSERVATIVE_CAP:"
  printf '%s\n' "$CONSERVATIVE" | grep . | sed 's/^/    /'
  st=1
elif [ "$ncons" -lt "$CONSERVATIVE_CAP" ]; then
  echo "FAIL the conservative tally is $ncons against a cap of $CONSERVATIVE_CAP — the cap is SHRINK-ONLY; lower it in this file"
  st=1
fi

# The count is DERIVED from the file, not typed: a hand-maintained tally reads as a claim about
# coverage and goes stale the first time a group is added without touching it. The floor is a
# RATCHET — raised with the groups, never left behind, or a deleted group passes as a green run.
# TWO floors, because one of them counts COMMENT BANNERS. `grep -c '^# --- '` is a ratchet on the
# number of headers, not on the number of executed assertions: measured, commenting out every line
# of a group's body while keeping its banner leaves this count unchanged and the suite still prints
# PASS. So the executable population is floored too — the `run` invocations that actually drive the
# driver, and the count of cases the arithmetic bar binds on.
ngroups=$(grep -c '^# --- ' "$SELF")
nruns=$(grep -c '^run "' "$SELF")
[ "$ngroups" -ge 46 ] || bad "the fixture-group scan found $ngroups banner(s), expected at least 46 — a group was deleted"
[ "$nruns" -ge 36 ] || bad "only $nruns 'run' case(s) remain, expected at least 36 — a group was emptied while its banner stayed, which the banner count cannot see"
[ "$NEVER_WORSE_BOUND" -ge "$NEVER_WORSE_FLOOR" ]   || bad "the arithmetic never-worse comparison bound on $NEVER_WORSE_BOUND case(s) against a grow-only floor of $NEVER_WORSE_FLOOR — a control flipped from rc 0 to rc 1 and silently left the bar"
[ "$st" = 0 ] && echo "PASS — merge-rows: $ngroups groups / $nruns run cases held, $NEVER_WORSE_BOUND under the arithmetic never-worse bar, $ncons conservative (cap $CONSERVATIVE_CAP)"
exit "$st"
