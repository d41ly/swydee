#!/usr/bin/env bash
# Runnable scenario suite for manifest-check.sh (spec: the manifest-ratchet design record, coding-governance §3).
# Run: bash skills/session-kickoff/manifest-check.test.sh    (exit 0 = all pass)
set -u
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null   # a runner's core.hooksPath/init.templateDir must not reach the throwaway repos
CHECK="$(cd "$(dirname "$0")" && pwd)/manifest-check.sh"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/mfcheck.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
echo 0 > "$TMP/.now"   # file-backed fake clock — stamp_line runs in subshells, so a plain
                       # variable would never advance and same-anchor re-stamps would no-op

# run <name> <repo> <want_exit> <want_grep|-> [args...]
run() {
  local name=$1 repo=$2 want=$3 pat=$4; shift 4
  local out got
  out=$(cd "$repo" && bash "$CHECK" "$@" 2>&1); got=$?
  if [ "$got" != "$want" ]; then
    echo "FAIL $name (exit $got, want $want)"; printf '%s\n' "$out" | sed 's/^/    /'; fail=$((fail+1)); return
  fi
  if printf '%s' "$out" | grep -q 'fatal:'; then   # the no-raw-fatal contract holds on EVERY path
    echo "FAIL $name (raw git fatal leaked)"; printf '%s\n' "$out" | sed 's/^/    /'; fail=$((fail+1)); return
  fi
  if [ "$pat" != "-" ] && ! printf '%s' "$out" | grep -q "$pat"; then
    echo "FAIL $name (output lacks '$pat')"; printf '%s\n' "$out" | sed 's/^/    /'; fail=$((fail+1)); return
  fi
  if [ "$pat" = "-" ] && printf '%s' "$out" | grep -vE '^(WARN:|NOTE:)' | grep -q .; then
    echo "FAIL $name (green run not silent-clean)"; printf '%s\n' "$out" | sed 's/^/    /'; fail=$((fail+1)); return
  fi
  echo "ok   $name"; pass=$((pass+1))
}

# Every mkrepo starts from a byte-identical base repo — so build it ONCE and copy per case,
# turning 36 `git init`+config+commit chains into 1. The suite's whole cost was repo
# construction (~3m of git process spawns on Windows); cp -r of a single-commit repo with no
# remotes/worktrees/alternates carries no absolute paths, so the copies are fully independent.
TEMPLATE="$TMP/.template"; mkdir -p "$TEMPLATE/docs"
git -C "$TEMPLATE" init -q -b main
git -C "$TEMPLATE" config user.email t@test; git -C "$TEMPLATE" config user.name t; git -C "$TEMPLATE" config commit.gpgsign false
git -C "$TEMPLATE" config core.autocrlf false
printf 'all:\n\ttrue\n' > "$TEMPLATE/Makefile"; echo gov > "$TEMPLATE/docs/GOV.md"
git -C "$TEMPLATE" add -A; git -C "$TEMPLATE" commit -qm base
mkrepo() { R="$TMP/$1"; cp -r "$TEMPLATE" "$R"; }   # $1=name → sets R; a copy of the base repo (Makefile watch + docs/GOV.md anchor)

stamp_line() {
  local n; n=$(( $(cat "$TMP/.now") + 1 )); echo "$n" > "$TMP/.now"
  printf 'last-audit: 2026-07-12T12:%02d:%02d+00:00 @ %s' $((n/60)) $((n%60)) "$1"
}

write_manifest() { # $1=repo $2=sha $3=watch $4=vpaths [$5=marker] [$6=extra-body]
  local marker="${5:-kickoff-manifest: v1.1}"
  cat > "$1/SESSION-KICKOFF.md" <<EOF
# Kickoff manifest — test
<!-- $marker · test instance -->
<!-- manifest-audit
$(stamp_line "$2")
watch: $3
verify-paths: $4
-->
## §B
gate fence:
\`\`\`bash
make all
\`\`\`
${6:-}
EOF
}

restamp() { # $1=repo $2=sha — rewrite the last-audit line (datetime always advances)
  local nl; nl=$(stamp_line "$2")
  sed -i "s|^last-audit: .*|$nl|" "$1/SESSION-KICKOFF.md"
}

commit_all() { git -C "$1" add -A; git -C "$1" commit -qm "$2"; }
head_sha() { git -C "$1" rev-parse HEAD; }

# ---- 1 clean pass -------------------------------------------------------
mkrepo clean
write_manifest "$R" "$(head_sha "$R")" "Makefile" "docs/GOV.md"
commit_all "$R" manifest
run "clean pass → 0, silent" "$R" 0 -

# ---- 2 surviving placeholder → C1 --------------------------------------
mkrepo c1
write_manifest "$R" "$(head_sha "$R")" "Makefile" "docs/GOV.md" "" "{{GATE_COMMANDS}}"
commit_all "$R" manifest
run "surviving {{PLACEHOLDER}} → C1" "$R" 1 "check 1 FAILED"

# ---- 3 Actions/Go-template braces are NOT placeholders ------------------
mkrepo c1ok
write_manifest "$R" "$(head_sha "$R")" "Makefile" "docs/GOV.md" "" 'echo ${{ secrets.X }} && docker inspect --format {{.State.Status}} c'
commit_all "$R" manifest
run "\${{ secrets }} / {{.Go}} in fence → 0" "$R" 0 -

# ---- 4 missing block (v1.1 marker) → C2 ---------------------------------
mkrepo noblock
cat > "$R/SESSION-KICKOFF.md" <<'EOF'
# manifest
<!-- kickoff-manifest: v1.1 · test -->
body only
EOF
commit_all "$R" manifest
run "missing audit block → C2" "$R" 1 "check 2 FAILED"

# ---- 5 empty watch value → C2 -------------------------------------------
mkrepo emptywatch
write_manifest "$R" "$(head_sha "$R")" " ; " "docs/GOV.md"
commit_all "$R" manifest
run "empty watch value → C2" "$R" 1 "check 2 FAILED"

# ---- 6 bogus sha → C3 unknown -------------------------------------------
mkrepo bogus
write_manifest "$R" "0123456789abcdef0123456789abcdef01234567" "Makefile" "docs/GOV.md"
commit_all "$R" manifest
run "bogus sha → C3 unknown" "$R" 1 "unknown to this repo"

# ---- 7 valid-but-non-ancestor sha → C3 second remedy --------------------
mkrepo nonanc
git -C "$R" checkout -qb side; echo s > "$R/side.txt"; commit_all "$R" side; SIDE=$(head_sha "$R")
git -C "$R" checkout -q main
write_manifest "$R" "$SIDE" "Makefile" "docs/GOV.md"
commit_all "$R" manifest
run "non-ancestor sha → C3 rewrite remedy" "$R" 1 "not an ancestor"

# ---- 8 dead verify-path → C4 --------------------------------------------
mkrepo deadvp
write_manifest "$R" "$(head_sha "$R")" "Makefile" "docs/GONE.md"
commit_all "$R" manifest
run "dead verify-path → C4" "$R" 1 "check 4 FAILED"

# ---- 9 untracked file at verify-path → C4 -------------------------------
mkrepo untrackvp
write_manifest "$R" "$(head_sha "$R")" "Makefile" "docs/LOCAL.md"
commit_all "$R" manifest
echo local > "$R/docs/LOCAL.md"   # exists on disk, never tracked
run "untracked verify-path → C4" "$R" 1 "check 4 FAILED"

# ---- 10 watch commit without re-stamp → C5 ------------------------------
mkrepo drift
write_manifest "$R" "$(head_sha "$R")" "Makefile" "docs/GOV.md"
commit_all "$R" manifest
printf 'all:\n\ttrue\nx:\n\ttrue\n' > "$R/Makefile"; commit_all "$R" "watch drift"
run "watch commit, no re-stamp → C5" "$R" 1 "check 5 FAILED"

# ---- 11 bundled watch+re-stamp commit → 0 (W==S reflexive) --------------
mkrepo bundle
write_manifest "$R" "$(head_sha "$R")" "Makefile" "docs/GOV.md"
commit_all "$R" manifest
printf 'all:\n\ttrue\ny:\n\ttrue\n' > "$R/Makefile"
restamp "$R" "$(head_sha "$R")"          # stamps the PARENT sha — the one-commit remedy
commit_all "$R" "bundle: drift + re-stamp"
run "bundled drift+re-stamp → 0" "$R" 0 -

# ---- 12 follow-up re-stamp (frozen anchor, datetime moves) → 0 ----------
mkrepo followup
ANCHOR=$(head_sha "$R")
write_manifest "$R" "$ANCHOR" "Makefile" "docs/GOV.md"
commit_all "$R" manifest
printf 'all:\n\ttrue\nz:\n\ttrue\n' > "$R/Makefile"; commit_all "$R" "watch drift"
restamp "$R" "$ANCHOR"                    # same anchor sha, new datetime — must still commit
commit_all "$R" "follow-up re-stamp"
run "follow-up re-stamp, frozen anchor → 0" "$R" 0 -

# ---- 13 cross-mode pair: staged bundle → C5s green, then full C5 green --
mkrepo xmode
write_manifest "$R" "$(head_sha "$R")" "Makefile" "docs/GOV.md"
commit_all "$R" manifest
printf 'all:\n\ttrue\nw:\n\ttrue\n' > "$R/Makefile"
restamp "$R" "$(head_sha "$R")"
git -C "$R" add -A
run "cross-mode: staged bundle → C5s green" "$R" 0 - --staged
commit_all "$R" "bundle"
run "cross-mode: same commit → full C5 green" "$R" 0 -

# ---- 14 true-merge laundering probe → RED, then post-merge re-stamp → 0 -
mkrepo laundering
ANCHOR=$(head_sha "$R")
write_manifest "$R" "$ANCHOR" "Makefile" "docs/GOV.md"
commit_all "$R" manifest
git -C "$R" checkout -qb feat
printf 'all:\n\ttrue\nfeat:\n\ttrue\n' > "$R/Makefile"; commit_all "$R" "unaudited drift on feat"
git -C "$R" checkout -q main
restamp "$R" "$ANCHOR"; commit_all "$R" "independent mainline re-stamp"   # pre-merge stamp
git -C "$R" merge -q --no-ff --no-edit feat
run "true-merge laundering → C5 RED" "$R" 1 "check 5 FAILED"
restamp "$R" "$(head_sha "$R")"; commit_all "$R" "post-merge fresh audit"
run "post-merge re-stamp → 0" "$R" 0 -

# ---- 15 no-remote squash-merge with merge-base stamp → 0 ----------------
mkrepo squash
MAIN0=$(head_sha "$R")
write_manifest "$R" "$MAIN0" "Makefile" "docs/GOV.md"
commit_all "$R" manifest
MB=$(head_sha "$R")                       # branch point = merge-base vs main
git -C "$R" checkout -qb work
printf 'all:\n\ttrue\nsq:\n\ttrue\n' > "$R/Makefile"
restamp "$R" "$MB"                        # §2 stamp rule: merge-base, not branch HEAD
commit_all "$R" "bundle on branch"
git -C "$R" checkout -q main
git -C "$R" merge -q --squash work >/dev/null
git -C "$R" commit -qm "squashed landing"
run "no-remote squash landing → 0 (C3+C5 hold)" "$R" 0 -

# ---- 16 merged orphan-root watch history → clean fail, no raw fatal -----
mkrepo orphan
write_manifest "$R" "$(head_sha "$R")" "Makefile; tools/" "docs/GOV.md"
mkdir -p "$R/tools"; echo t > "$R/tools/seed.txt"   # keeps the tools/ watch pathspec alive (C6)
commit_all "$R" manifest
git -C "$R" checkout -q --orphan lonely
git -C "$R" rm -qrf . >/dev/null 2>&1
mkdir -p "$R/tools"; echo o > "$R/tools/orphan.txt"   # watched path, no overlap with main
git -C "$R" add -A; git -C "$R" commit -qm "orphan root touching watch"
git -C "$R" checkout -q main
git -C "$R" merge -q --no-edit --allow-unrelated-histories lonely
run "merged orphan watch root → clean C5 red (no fatal)" "$R" 1 "check 5 FAILED"

# ---- 17 staged watch without staged stamp → C5s -------------------------
mkrepo stagedbad
write_manifest "$R" "$(head_sha "$R")" "Makefile" "docs/GOV.md"
commit_all "$R" manifest
printf 'all:\n\ttrue\nsb:\n\ttrue\n' > "$R/Makefile"; git -C "$R" add Makefile
run "staged watch, no staged stamp → C5s" "$R" 1 "THIS commit" --staged

# ---- 18 staged watch + unrelated manifest edit → C5s --------------------
mkrepo stagedside
write_manifest "$R" "$(head_sha "$R")" "Makefile" "docs/GOV.md"
commit_all "$R" manifest
printf 'all:\n\ttrue\nss:\n\ttrue\n' > "$R/Makefile"
printf '\nunrelated trap note\n' >> "$R/SESSION-KICKOFF.md"     # manifest edit, stamp untouched
git -C "$R" add -A
run "staged watch + unrelated manifest edit → C5s" "$R" 1 "check 5 FAILED" --staged

# ---- 19 trailing semicolon in watch → parsed clean → 0 ------------------
mkrepo trailsemi
write_manifest "$R" "$(head_sha "$R")" "Makefile;" "docs/GOV.md;"
commit_all "$R" manifest
run "trailing ';' → parsed clean, 0" "$R" 0 -

# ---- 20 dead watch pathspec → C6 ----------------------------------------
mkrepo deadwatch
write_manifest "$R" "$(head_sha "$R")" "gone-dir/" "docs/GOV.md"
commit_all "$R" manifest
run "dead watch pathspec → C6" "$R" 1 "check 6 FAILED"

# ---- 21 broad watch pathspec → breadth WARN, still 0 --------------------
mkrepo broad
mkdir -p "$R/bulk"; for i in $(seq 1 101); do echo x > "$R/bulk/f$i.txt"; done
commit_all "$R" bulk
write_manifest "$R" "$(head_sha "$R")" "bulk/; Makefile" "docs/GOV.md"
commit_all "$R" manifest
run "watch matches 101 files → WARN + 0" "$R" 0 "WARN: watch pathspec"

# ---- 22 unmanaged manifest (no marker) → NOTE + 0 -----------------------
mkrepo unmanaged
cat > "$R/SESSION-KICKOFF.md" <<'EOF'
# Session kickoff template (prototype — deliberately unmanaged)
No marker here; stable preamble; stream map.
EOF
commit_all "$R" manifest
run "unmanaged manifest → NOTE + 0" "$R" 0 "NOTE:"

# ---- 23 v1.0 marker, no block → C2 with retrofit ------------------------
mkrepo v10
cat > "$R/SESSION-KICKOFF.md" <<'EOF'
# manifest
<!-- kickoff-manifest: v1.0 · instantiated from coding-governance -->
old body
EOF
commit_all "$R" manifest
run "v1.0 marker, no block → C2 retrofit" "$R" 1 "marker to v1.1 LAST"

# ---- 24 v1.0 marker WITH valid block → version WARN, 0 ------------------
mkrepo v10block
write_manifest "$R" "$(head_sha "$R")" "Makefile" "docs/GOV.md" "kickoff-manifest: v1.0"
commit_all "$R" manifest
run "v1.0 + valid block → WARN + 0" "$R" 0 "WARN: manifest format v1.0"

# ---- 25 shallow clone → WARN + skip C3/C5 → 0 ---------------------------
mkrepo shallowsrc
ANCHOR=$(head_sha "$R")
write_manifest "$R" "$ANCHOR" "Makefile" "docs/GOV.md"
commit_all "$R" manifest
printf 'all:\n\ttrue\nmore:\n\ttrue\n' > "$R/Makefile"; commit_all "$R" more   # depth-1 clone misses ANCHOR
git clone -q --depth 1 "file://$R" "$TMP/shallow" 2>/dev/null
run "shallow clone → WARN, C3+C5 skipped, 0" "$TMP/shallow" 0 "WARN: shallow clone"

# ---- 26 exit 2 contract --------------------------------------------------
mkdir -p "$TMP/nogit"
run "non-repo → exit 2" "$TMP/nogit" 2 "env ERROR"
mkrepo nomanifest
run "no manifest → exit 2" "$R" 2 "env ERROR"

# ---- 27 manifest rename after unaudited drift → still C5 RED -------------
mkrepo rename
write_manifest "$R" "$(head_sha "$R")" "Makefile" "docs/GOV.md"
commit_all "$R" manifest
printf 'all:\n\ttrue\nrn:\n\ttrue\n' > "$R/Makefile"; commit_all "$R" "unaudited drift"
mkdir -p "$R/docs/claude"; git -C "$R" mv SESSION-KICKOFF.md docs/claude/SESSION-KICKOFF.md
commit_all "$R" "pure rename of the manifest"
run "manifest renamed after drift → C5 RED (no laundering)" "$R" 1 "check 5 FAILED"

# ---- 28 body decoy last-audit line does not count as a re-stamp ----------
mkrepo decoy
write_manifest "$R" "$(head_sha "$R")" "Makefile" "docs/GOV.md" "" 'last-audit: decoy @ 0000000000000000000000000000000000000000'
commit_all "$R" manifest
printf 'all:\n\ttrue\ndc:\n\ttrue\n' > "$R/Makefile"; commit_all "$R" "unaudited drift"
sed -i 's/^last-audit: decoy @ 0\{40\}/last-audit: decoy2 @ 0000000000000000000000000000000000000000/' "$R/SESSION-KICKOFF.md"
commit_all "$R" "edit only the body decoy line"
run "body decoy edit after drift → C5 RED" "$R" 1 "check 5 FAILED"

# ---- 29 block reorder without value change does not count ----------------
mkrepo reorder
write_manifest "$R" "$(head_sha "$R")" "Makefile" "docs/GOV.md"
commit_all "$R" manifest
printf 'all:\n\ttrue\nro:\n\ttrue\n' > "$R/Makefile"; commit_all "$R" "unaudited drift"
PYBIN=python3; command -v python3 >/dev/null 2>&1 || PYBIN=python
"$PYBIN" - "$R/SESSION-KICKOFF.md" <<'PY'
import sys
p = sys.argv[1]; lines = open(p, encoding='utf-8').read().split('\n')
la = next(i for i,l in enumerate(lines) if l.startswith('last-audit:'))
w  = next(i for i,l in enumerate(lines) if l.startswith('watch:'))
lines[la], lines[w] = lines[w], lines[la]      # swap the two lines, values untouched
open(p, 'w', encoding='utf-8', newline='\n').write('\n'.join(lines))
PY
if git -C "$R" diff --quiet -- SESSION-KICKOFF.md; then
  echo "FAIL block reorder after drift → C5 RED (mutation never landed — python missing?)"; fail=$((fail+1))
else
  commit_all "$R" "reorder block lines only"
  run "block reorder after drift → C5 RED" "$R" 1 "check 5 FAILED"
fi

# ---- 30 staged decoy line does not satisfy C5s ---------------------------
mkrepo stageddecoy
write_manifest "$R" "$(head_sha "$R")" "Makefile" "docs/GOV.md"
commit_all "$R" manifest
printf 'all:\n\ttrue\nsd:\n\ttrue\n' > "$R/Makefile"
printf 'last-audit: fake @ 0000000000000000000000000000000000000000\n' >> "$R/SESSION-KICKOFF.md"
git -C "$R" add -A
run "staged body decoy → C5s RED" "$R" 1 "check 5 FAILED" --staged

# ---- 31 repo-escaping watch pathspec → C6 red, no fatal ------------------
mkrepo escape
write_manifest "$R" "$(head_sha "$R")" "../outside; Makefile" "docs/GOV.md"
commit_all "$R" manifest
run "repo-escaping watch pathspec → C6, no fatal" "$R" 1 "check 6 FAILED"

# ---- 32 unborn HEAD (orphan checkout) → guided C3, no fatal --------------
mkrepo unborn
write_manifest "$R" "$(head_sha "$R")" "Makefile" "docs/GOV.md"
commit_all "$R" manifest
git -C "$R" checkout -q --orphan void
run "unborn HEAD → C3 'no commits', no fatal" "$R" 1 "no commits on this branch"

# ---- 33 malformed datetime → C2 ------------------------------------------
mkrepo baddate
write_manifest "$R" "$(head_sha "$R")" "Makefile" "docs/GOV.md"
sed -i 's/^last-audit: [^@]*@/last-audit: banana breakfast @/' "$R/SESSION-KICKOFF.md"
commit_all "$R" manifest
run "malformed datetime → C2" "$R" 1 "malformed"

# ---- 34 relative path arg from a subdirectory ----------------------------
mkrepo subdir
mkdir -p "$R/docs"
write_manifest "$R" "$(head_sha "$R")" "Makefile" "docs/GOV.md"
mv "$R/SESSION-KICKOFF.md" "$R/docs/SESSION-KICKOFF.md"
commit_all "$R" manifest
run "relative arg from subdir resolves" "$R/docs" 0 - "SESSION-KICKOFF.md"

# ---- 34b outside-repo path argument → env error 2 (relative ../ and absolute)
mkrepo escapearg
echo x > "$TMP/SESSION-KICKOFF.md"          # sibling of the repo, outside it
run "relative ../ arg escaping repo → 2" "$R" 2 "resolves outside" "../SESSION-KICKOFF.md"
run "absolute arg outside repo → 2" "$R" 2 "resolves outside" "$TMP/SESSION-KICKOFF.md"
rm -f "$TMP/SESSION-KICKOFF.md"

# ---- 35 unit-branch: bundle at merge-base anchor, then same-anchor re-stamp
mkrepo branchunit
write_manifest "$R" "$(head_sha "$R")" "Makefile" "docs/GOV.md"
commit_all "$R" manifest
MB=$(head_sha "$R")                       # branch point = merge-base vs main
git -C "$R" checkout -qb unit
printf 'all:\n\ttrue\nbu:\n\ttrue\n' > "$R/Makefile"
restamp "$R" "$MB"; commit_all "$R" "bundle on unit branch"
restamp "$R" "$MB"; commit_all "$R" "second same-anchor re-stamp (datetime only)"
n=$(git -C "$R" rev-list --count HEAD)
if [ "$n" -ne 4 ]; then echo "FAIL branch same-anchor re-stamps (want 4 commits, got $n — a re-stamp no-oped)"; fail=$((fail+1)); else
  run "unit branch: merge-base bundle + same-anchor re-stamp → 0" "$R" 0 -
fi

echo "---- $pass passed, $fail failed ----"
[ "$fail" = 0 ]
