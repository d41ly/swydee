#!/usr/bin/env bash
# manifest-check.sh — kickoff-manifest ratchet gate (coding-governance session-kickoff kit).
# Verifies a project's SESSION-KICKOFF.md kickoff manifest against mechanical truth signals:
#   C1 no surviving {{PLACEHOLDER}}      C2 audit block present + parseable
#   C3 anchor sha real + ancestor        C4 verify-paths tracked
#   C5 no unaudited watch drift          C6 watch list alive
# Single source: CI, pre-commit, the manifest's gate fence, and the kickoff engine all invoke THIS
# script — never hand-copy the checks. Spec: the manifest-ratchet design record in coding-governance.
#
#   manifest-check.sh [<manifest-path>]   # full check (discovers the manifest when no path given;
#                                         # a relative path resolves from the repo root, then from
#                                         # the invoking directory)
#   manifest-check.sh --staged [<path>]   # pre-commit fast leg: C1 C2 C4 C6 + C5s (staged drift)
#
# Exit 0 + no FAILED lines = clean (WARN:/NOTE: lines permitted). Exit 1 = a check failed.
# Exit 2 = environment error (not a git repo / no manifest found / path outside the repo).
set -u
KIT_MANIFEST_VERSION="1.1"

CALLER_PWD=$PWD
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "MANIFEST env ERROR — not a git repository"; exit 2; }
ROOT=$(cd "$ROOT" 2>/dev/null && pwd) || { echo "MANIFEST env ERROR — cannot enter repo root"; exit 2; }   # normalize to the shell's path flavor (git-bash: C:/ vs /c/)
cd "$ROOT" || exit 2

STAGED=0; MF=""
for a in "$@"; do
  case "$a" in
    --staged) STAGED=1 ;;
    *) MF="$a" ;;
  esac
done

# Resolve a path argument: repo-root-relative first, then caller-cwd-relative; never outside the
# repo. Membership is decided by git identity (file's toplevel == this ROOT, both normalized the
# same way), never by path-string comparison — under MSYS one directory has two spellings
# (/tmp/x vs /c/.../Temp/x) and realpath can't unify them (mount points aren't symlinks).
if [ -n "$MF" ]; then
  case "$MF" in
    /*|[A-Za-z]:*) abs="$MF" ;;
    *) if [ -f "$ROOT/$MF" ]; then abs="$ROOT/$MF"; else abs="$CALLER_PWD/$MF"; fi ;;
  esac
  [ -f "$abs" ] || { echo "MANIFEST env ERROR — '$MF' not found (tried the repo root, then $CALLER_PWD)"; exit 2; }
  dir=$(cd "$(dirname -- "$abs")" 2>/dev/null && pwd) || dir=""
  froot=""
  if [ -n "$dir" ]; then
    froot=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || froot=""
    [ -n "$froot" ] && { froot=$(cd "$froot" 2>/dev/null && pwd) || froot=""; }
  fi
  if [ -z "$froot" ] || [ "$froot" != "$ROOT" ]; then
    echo "MANIFEST env ERROR — '$MF' resolves outside this repository"; exit 2
  fi
  MF="$(git -C "$dir" rev-parse --show-prefix 2>/dev/null)$(basename -- "$abs")"
else
  for p in docs/claude/SESSION-KICKOFF.md docs/SESSION-KICKOFF.md .claude/SESSION-KICKOFF.md SESSION-KICKOFF.md; do
    [ -f "$p" ] && { MF="$p"; break; }
  done
fi
[ -n "$MF" ] && [ -f "$MF" ] || { echo "MANIFEST env ERROR — no SESSION-KICKOFF.md at docs/claude/ docs/ .claude/ or the repo root (and no valid path argument)"; exit 2; }

# Unmanaged manifest (no kickoff-manifest marker, e.g. a prototype) — not ratchet-managed.
# An UNREADABLE manifest is an env error, never a green.
grep -q 'kickoff-manifest:' "$MF"
case $? in
  0) ;;
  1) echo "NOTE: $MF carries no kickoff-manifest marker — not ratchet-managed; skipping all checks."; exit 0 ;;
  *) echo "MANIFEST env ERROR — cannot read $MF"; exit 2 ;;
esac

# Forward-drift signal: manifest format older than this kit copy (no sort -V — BSD/busybox safe).
ver_older() { awk -v a="$1" -v b="$2" 'BEGIN{na=split(a,x,".");nb=split(b,y,".");n=(na>nb?na:nb);for(i=1;i<=n;i++){d=(x[i]+0)-(y[i]+0);if(d<0){print "y";exit}if(d>0)exit}}'; }
mver=$(sed -n 's/.*kickoff-manifest: v\([0-9][0-9.]*\).*/\1/p' "$MF" | head -1); mver=${mver%.}
if [ -n "$mver" ] && [ "$(ver_older "$mver" "$KIT_MANIFEST_VERSION")" = "y" ]; then
  echo "WARN: manifest format v$mver < kit v$KIT_MANIFEST_VERSION — see the upgrade recipe in coding-governance/WIRE-INTO-PROJECT.md §4."
fi

status=0
fail() { echo "MANIFEST check $1 FAILED — $2"; status=1; }

# The block's last-audit VALUE from a manifest body on stdin (block-scoped: body decoys don't count).
blockstamp() {
  awk '/<!-- manifest-audit/{f=1;next} f&&/-->/{exit} f' | tr -d '\r' \
    | sed -n 's/^[[:space:]]*last-audit:[[:space:]]*\(.*\)$/\1/p' | head -1 | sed 's/[[:space:]]*$//'
}

# C1 — no placeholder survives (placeholder SHAPE only: gate fences legitimately hold ${{ ... }},
# Go-template {{.Field}}, Helm {{ .Values }} — none of which match '{{' + uppercase).
c1=$(grep -nE '\{\{[A-Z]' "$MF" || true)
[ -n "$c1" ] && fail 1 "unfilled {{PLACEHOLDER}} survives in $MF (fill or delete each):
$(printf '%s\n' "$c1" | sed 's/^/  /')"

# C2 — exactly one manifest-audit block, three keys with non-empty, well-formed values.
RETROFIT="retrofit: (1) body deltas — rewrite the §B intro to 're-audited every kickoff; accretes', add the ratchet + dated-corrections (never delete the section) + traps-accrete text; (2) add the manifest-audit block: last-audit '<ISO datetime> @ <full sha>' (sha = HEAD on the default branch, else \$(git merge-base <remote>/<default> HEAD)), watch = gate-defining pathspecs, verify-paths = 2-3 anchors; (3) copy manifest-check.sh in, add the .gitattributes LF rule + the gate-fence line, git add everything; (4) run this check to 0; (5) pull the manifest DoD + reconcile lines into the project's playbook; (6) bump the marker to v1.1 LAST. Full recipe: coding-governance/WIRE-INTO-PROJECT.md §4."
nblocks=$(grep -c '<!-- manifest-audit' "$MF" || true)
BLOCK_OK=1
if [ "$nblocks" -eq 0 ]; then
  fail 2 "no manifest-audit block in $MF — $RETROFIT"
  BLOCK_OK=0
elif [ "$nblocks" -gt 1 ]; then
  fail 2 "$nblocks manifest-audit blocks in $MF — exactly one is allowed; merge them."
  BLOCK_OK=0
fi

LA=""; WATCH_RAW=""; VP_RAW=""
if [ "$BLOCK_OK" = 1 ]; then
  BLOCK=$(awk '/<!-- manifest-audit/{f=1;next} f&&/-->/{exit} f' "$MF" | tr -d '\r')
  getval() { printf '%s\n' "$BLOCK" | sed -n "s/^[[:space:]]*$1:[[:space:]]*\(.*\)$/\1/p" | head -1 | sed 's/[[:space:]]*$//'; }
  LA=$(getval 'last-audit'); WATCH_RAW=$(getval 'watch'); VP_RAW=$(getval 'verify-paths')
  [ -n "$LA" ] || { fail 2 "manifest-audit block lacks a last-audit value — stamp '<ISO datetime> @ <full sha>' after verifying §B."; BLOCK_OK=0; }
  [ -n "$WATCH_RAW" ] || { fail 2 "manifest-audit block lacks a watch value — list the gate-defining pathspecs (a missing watch silently disables the drift check)."; BLOCK_OK=0; }
  [ -n "$VP_RAW" ] || { fail 2 "manifest-audit block lacks a verify-paths value — list the 2-3 anchor paths."; BLOCK_OK=0; }
fi

# ;-split, trimming, EMPTY ELEMENTS DROPPED (a stray ';' must never reach git as '' — fatal 128).
splitspecs() { printf '%s\n' "$1" | tr ';' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v '^$' || true; }

WATCH=(); VPATHS=(); LA_SHA=""
if [ "$BLOCK_OK" = 1 ]; then
  while IFS= read -r _s; do WATCH+=("$_s"); done < <(splitspecs "$WATCH_RAW")
  while IFS= read -r _s; do VPATHS+=("$_s"); done < <(splitspecs "$VP_RAW")
  [ "${#WATCH[@]}" -gt 0 ] || { fail 2 "watch: holds no usable pathspec after splitting — list the gate-defining pathspecs (a missing watch silently disables the drift check)."; BLOCK_OK=0; }
  [ "${#VPATHS[@]}" -gt 0 ] || { fail 2 "verify-paths: holds no usable path after splitting — list the 2-3 anchor paths."; BLOCK_OK=0; }
  if [ "$BLOCK_OK" = 1 ]; then
    if ! printf '%s' "$LA" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?([+-][0-9]{2}:?[0-9]{2}|Z)[[:space:]]*@[[:space:]]*[0-9a-fA-F]{40}$'; then
      fail 2 "last-audit value malformed ('$LA') — want '<ISO-8601 datetime with offset> @ <full 40-hex sha>'."
      BLOCK_OK=0
    else
      LA_SHA=$(printf '%s' "$LA" | sed -n 's/.*@[[:space:]]*\([0-9a-fA-F]\{40\}\)[[:space:]]*$/\1/p')
    fi
  fi
fi

if [ "$BLOCK_OK" = 1 ]; then
  # C6 — watch list is alive (a dead pathspec is a silent permanent false-green on the drift check).
  for w in "${WATCH[@]}"; do
    n=$(git ls-files -- "$w" 2>/dev/null | wc -l | tr -d '[:space:]')
    if [ "$n" -eq 0 ]; then
      fail 6 "watch pathspec '$w' matches no tracked file — update the watch list to the restructured paths."
    elif [ "$n" -gt 100 ]; then
      echo "WARN: watch pathspec '$w' matches $n tracked files — overly broad; narrow it to the gate-defining slice."
    fi
  done

  # C4 — every verify-path anchors TRACKED content (an untracked leftover must not green the local
  # leg while fresh-clone CI reds).
  for vp in "${VPATHS[@]}"; do
    vp="${vp%/}"
    if git ls-files --error-unmatch -- "$vp" >/dev/null 2>&1; then :
    elif git ls-files -- "$vp/" 2>/dev/null | grep -q .; then :
    else
      fail 4 "verify-path '$vp' is not tracked content — the tree restructured or the anchor is dead; fix the path (or the §B pointer it anchors)."
    fi
  done

  STAMP_SHA_RULE="sha = HEAD on the default branch, else \$(git merge-base <remote>/<default> HEAD)"
  if [ "$STAGED" = 0 ]; then
    SKIP_RANGE=0
    # C3 — anchor sha is real and ours.
    if ! git rev-parse -q --verify 'HEAD^{commit}' >/dev/null 2>&1; then
      fail 3 "HEAD has no commits on this branch — make the first commit, then re-verify §B and re-stamp last-audit at it."
      SKIP_RANGE=1
    elif ! git cat-file -e "$LA_SHA^{commit}" 2>/dev/null; then
      if [ "$(git rev-parse --is-shallow-repository 2>/dev/null)" = "true" ]; then
        echo "WARN: shallow clone and the last-audit sha is absent — skipping C3+C5; set 'fetch-depth: 0' on the CI checkout step so the drift check actually enforces."
        SKIP_RANGE=1
      else
        fail 3 "last-audit sha $LA_SHA is unknown to this repo — the stamp is foreign or predates a history rewrite; re-verify §B, then re-stamp last-audit '<ISO datetime> @ <sha>' with $STAMP_SHA_RULE."
        SKIP_RANGE=1
      fi
    elif ! git merge-base --is-ancestor "$LA_SHA" HEAD 2>/dev/null; then
      fail 3 "last-audit sha $LA_SHA is not an ancestor of HEAD — history was rewritten or the stamp was squash-merged; re-verify §B, then re-stamp last-audit '<ISO datetime> @ <sha>' with $STAMP_SHA_RULE."
      SKIP_RANGE=1
    fi

    # C5 — no unaudited drift (TOPOLOGICAL + STRUCTURAL): the newest watch-touching commit W must be
    # an ancestor of (or equal to) the newest commit S that actually CHANGED the audit block's
    # last-audit VALUE. Candidates come from a pathspec-FREE -G search (with the rename source in the
    # diff, git's rename detection collapses a pure `git mv` of the manifest, which a pathspec-scoped
    # search would mistake for a stamp); each candidate is then validated by comparing the block's
    # stamp value at the commit vs its parent, so body decoy lines and block reorders never count.
    # Residual (documented): a decoy edit in a commit predating the manifest's current path is
    # accepted unvalidated — narrow, and it fails toward green only when combined with a later rename.
    if [ "$SKIP_RANGE" = 0 ]; then
      W=$(git rev-list -1 "$LA_SHA..HEAD" -- "${WATCH[@]}" 2>/dev/null)
      if [ -n "$W" ]; then
        S=""
        while IFS= read -r cand; do
          [ -n "$cand" ] || continue
          cur=$(git show "$cand:$MF" 2>/dev/null | blockstamp)
          prev=$(git show "$cand^:$MF" 2>/dev/null | blockstamp)
          if [ -z "$cur" ] || [ -z "$prev" ] || [ "$cur" != "$prev" ]; then S="$cand"; break; fi
        done < <(git log --format=%H -G'^last-audit:' "$LA_SHA..HEAD" 2>/dev/null)
        if [ -z "$S" ] || ! git merge-base --is-ancestor "$W" "$S" 2>/dev/null; then
          files=$(git diff --name-only "$LA_SHA..HEAD" -- "${WATCH[@]}" 2>/dev/null | sed 's/^/  /')
          fail 5 "watched files changed since last-audit with no re-stamp at/after the change:
$files
  For each file, re-check the §B claims derived from it, update the manifest where stale, then
  re-stamp last-audit ($STAMP_SHA_RULE) — bundled with the watched change or as a follow-up in the
  same PR. After a merge that brought in watch-touching commits, the fresh post-merge audit +
  re-stamp is the close."
        fi
      fi
    fi
  else
    # C5s — staged leg (deliberately narrowed: a blocking pre-commit cannot see a future follow-up
    # commit, so the bundle form is the only green path here). STRUCTURAL: the staged blob's block
    # stamp must differ from HEAD's — co-staging an unrelated manifest edit, or a body decoy line,
    # does not count.
    sw=$(git diff --cached --name-only -- "${WATCH[@]}" 2>/dev/null)
    if [ -n "$sw" ]; then
      staged_stamp=$(git show ":$MF" 2>/dev/null | blockstamp)
      head_stamp=$(git show "HEAD:$MF" 2>/dev/null | blockstamp)
      if [ -z "$staged_stamp" ] || [ "$staged_stamp" = "$head_stamp" ]; then
        fail 5 "staged changes touch watched files:
$(printf '%s\n' "$sw" | sed 's/^/  /')
  but the staged manifest's audit block does not update last-audit. Re-verify the §B claims these
  files feed, update the manifest where stale, and bundle the re-stamp into THIS commit
  ($STAMP_SHA_RULE)."
      fi
    fi
  fi
fi

exit "$status"
