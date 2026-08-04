#!/usr/bin/env bash
# adopt-agent-instructions.sh — install ONE canonical agent-instruction file in a target repo and
# wire every AI coding tool's expected filename to it, so a single source drives them all.
#
# Canonical = AGENTS.md (the Linux-Foundation cross-tool standard: read natively by Codex/Copilot/
# Cursor/Windsurf/Amp/Devin/Zed/Aider/Jules and Gemini CLI via .gemini config). Claude Code reads
# ONLY CLAUDE.md — it does NOT read AGENTS.md natively (open request anthropics/claude-code#6235) —
# so CLAUDE.md is wired with a `@AGENTS.md` import (or symlink/copy).
#
#   adopt-agent-instructions.sh [--source <file>] [--aliases "claude gemini copilot cursor windsurf"]
#       [--mode symlink|pointer|copy] [--check] [--force]
#
# --source   file whose CONTENT becomes AGENTS.md (default: reuse an existing AGENTS.md; error if neither).
# --aliases  which tool files to wire (default: "claude gemini copilot"). Names: claude gemini copilot cursor windsurf.
# --mode     symlink: real symlinks → AGENTS.md (needs Developer Mode/elevation on Windows; auto-falls back);
#            pointer (DEFAULT): native indirection where one exists (CLAUDE.md = `@AGENTS.md` import;
#              Gemini = .gemini/settings.json context.fileName); others fall back to a synced copy;
#            copy: real duplicate files kept honest by --check (drift needs --force to re-sync).
# --check    verify wiring only (symlinks resolve / pointers intact / copies match AGENTS.md); exit 1 on drift.
# --force    overwrite an existing alias (file OR symlink) that isn't already correct wiring.
#
# Exit 0 clean · 1 a wiring/check failure · 2 environment/usage error. Idempotent: re-running converges
# (copy-mode drift is the one exception — it needs --force). No hard deps beyond git + coreutils.
set -u
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || ROOT=$PWD
cd "$ROOT" || { echo "AGENT-INSTR env ERROR — cannot enter repo root"; exit 2; }

CANON="AGENTS.md"
SOURCE=""; ALIASES="claude gemini copilot"; MODE="pointer"; CHECK=0; FORCE=0
need_val() { [ "$1" -ge 2 ] || { echo "AGENT-INSTR env ERROR — $2 needs a value"; exit 2; }; }
while [ $# -gt 0 ]; do
  case "$1" in
    --source)  need_val $# --source;  SOURCE=$2; shift 2;;
    --aliases) need_val $# --aliases; ALIASES=$2; shift 2;;
    --mode)    need_val $# --mode;    MODE=$2; shift 2;;
    --check)   CHECK=1; shift;;
    --force)   FORCE=1; shift;;
    *) echo "AGENT-INSTR env ERROR — unknown arg: $1"; exit 2;;
  esac
done
case "$MODE" in symlink|pointer|copy) ;; *) echo "AGENT-INSTR env ERROR — --mode must be symlink|pointer|copy (got '$MODE')"; exit 2;; esac

status=0
fail() { echo "AGENT-INSTR $1 FAILED — $2"; status=1; }

alias_path() {
  case "$1" in
    claude)   echo "CLAUDE.md";;
    gemini)   echo "GEMINI.md";;
    copilot)  echo ".github/copilot-instructions.md";;
    cursor)   echo ".cursorrules";;
    windsurf) echo ".windsurfrules";;
    *) echo "";;
  esac
}
# relative path from an alias file back to the repo-root CANON, in pure shell (no python).
rel_to_canon() { local p=$1 depth pref=""; depth=$(printf '%s' "$p" | tr -cd '/' | wc -c); while [ "$depth" -gt 0 ]; do pref="../$pref"; depth=$((depth-1)); done; printf '%s%s' "$pref" "$CANON"; }
gemini_configured() { [ -f .gemini/settings.json ] && grep -Eq '"fileName"[[:space:]]*:[[:space:]]*(\[[[:space:]]*)?"'"$CANON"'"' .gemini/settings.json; }
is_import() { grep -qE "^@\.*/?([^/]*/)*$CANON[[:space:]]*$" "$1" 2>/dev/null; }

# ---- --check: verify only ----------------------------------------------
if [ "$CHECK" = 1 ]; then
  [ -f "$CANON" ] || { echo "AGENT-INSTR CHECK FAILED — no canonical $CANON"; exit 1; }
  for a in $ALIASES; do
    p=$(alias_path "$a"); [ -n "$p" ] || { fail CHECK "unknown alias '$a'"; continue; }
    if [ "$a" = gemini ] && [ ! -e "$p" ] && [ ! -L "$p" ]; then
      gemini_configured && continue
      fail CHECK "gemini: neither GEMINI.md nor .gemini/settings.json context.fileName=$CANON"; continue
    fi
    if [ -L "$p" ]; then
      [ -e "$p" ] || { fail CHECK "$p is a DANGLING symlink → $(readlink "$p")"; continue; }
      [ "$(basename "$(readlink "$p")")" = "$CANON" ] || fail CHECK "$p symlinks '$(readlink "$p")', not $CANON"
    elif [ ! -e "$p" ]; then fail CHECK "$a alias '$p' missing"
    elif is_import "$p"; then :
    elif cmp -s "$CANON" "$p"; then :
    else fail CHECK "$p is a stale copy — re-run with --force to re-sync from $CANON (or it drifted)"
    fi
  done
  [ "$status" = 0 ] && echo "agent-instructions OK — $CANON + aliases [$ALIASES] correctly wired."
  exit "$status"
fi

# ---- install the canonical ---------------------------------------------
if [ -n "$SOURCE" ]; then
  [ -f "$SOURCE" ] || { echo "AGENT-INSTR env ERROR — --source not found: $SOURCE"; exit 2; }
  if [ -f "$CANON" ] && [ "$FORCE" != 1 ] && ! cmp -s "$SOURCE" "$CANON"; then
    echo "AGENT-INSTR env ERROR — $CANON exists and differs from --source; pass --force to overwrite."; exit 2
  fi
  cp "$SOURCE" "$CANON"
fi
[ -f "$CANON" ] || { echo "AGENT-INSTR env ERROR — no $CANON and no --source to create it from."; exit 2; }

wire() {
  local a=$1 p rel; p=$(alias_path "$a") || true
  [ -n "$p" ] || { fail wire "unknown alias '$a'"; return; }

  # already correctly wired? (idempotent no-op)
  if [ "$a" = gemini ] && [ ! -e "$p" ] && [ ! -L "$p" ] && gemini_configured; then echo "  = .gemini/settings.json (context.fileName, current)"; return; fi
  if [ -L "$p" ] && [ -e "$p" ] && [ "$(basename "$(readlink "$p")")" = "$CANON" ]; then echo "  = $p (symlink, current)"; return; fi
  if [ ! -L "$p" ] && [ -f "$p" ] && is_import "$p"; then echo "  = $p (pointer, current)"; return; fi
  if [ ! -L "$p" ] && [ -f "$p" ] && cmp -s "$CANON" "$p"; then echo "  = $p (copy, current)"; return; fi

  # exists but not correct wiring → protected unless --force (covers files AND symlinks, incl. dangling)
  if { [ -e "$p" ] || [ -L "$p" ]; } && [ "$FORCE" != 1 ]; then
    fail wire "$p exists and is not $CANON wiring — pass --force to replace it"; return
  fi

  local dir; dir=$(dirname "$p"); [ "$dir" = "." ] || mkdir -p "$dir"
  rel=$(rel_to_canon "$p")

  # gemini prefers config-driven indirection (pointer mode); symlink/copy modes wire GEMINI.md as a file
  if [ "$a" = gemini ] && [ "$MODE" = pointer ]; then
    mkdir -p .gemini
    if [ -f .gemini/settings.json ]; then
      fail wire "gemini: .gemini/settings.json exists without context.fileName=$CANON — merge \"context\":{\"fileName\":\"$CANON\"} in by hand (JSON can't be safely auto-merged)"
    else
      printf '{\n  "context": {\n    "fileName": "%s"\n  }\n}\n' "$CANON" > .gemini/settings.json
      echo "  + .gemini/settings.json (context.fileName=$CANON)"
    fi
    return
  fi

  case "$MODE" in
    symlink)
      rm -f "$p"
      if ln -s "$rel" "$p" 2>/dev/null && [ -e "$p" ]; then echo "  + $p → $rel (symlink)"
      else echo "  ! symlink unavailable/dangling (Windows Developer Mode?) — falling back"; rm -f "$p"; _wire_pointer_or_copy "$a" "$p" "$rel"; fi;;
    copy) rm -f "$p"; cp "$CANON" "$p"; echo "  + $p (copy — drift re-syncs with --force)";;
    pointer|*) _wire_pointer_or_copy "$a" "$p" "$rel";;
  esac
}
_wire_pointer_or_copy() {
  local a=$1 p=$2 rel=$3
  if [ "$a" = claude ]; then rm -f "$p"; printf '@%s\n' "$rel" > "$p"; printf '  + %s (@%s import)\n' "$p" "$rel"
  else rm -f "$p"; cp "$CANON" "$p"; echo "  + $p (copy — no native pointer; drift re-syncs with --force)"; fi
}

echo "canonical: $CANON ($(wc -c < "$CANON") bytes) · mode: $MODE · aliases: $ALIASES"
for a in $ALIASES; do wire "$a"; done
exit "$status"
