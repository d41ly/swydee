# memory-tree — structured, machine-linted project memory

A project-agnostic kit that turns the governance playbook's §5/§6 memory-and-decisions *principles*
into a concrete, gated folder structure: one `memory/` tree organised by development discipline, with
per-feature `builds/` folders, index budgets + rotation, a status vocabulary, and a 12-check hygiene
gate that keeps it that way. The owner reads indexes, not files; sessions stop burning tokens
re-deriving what memory already records.

Opt-in. Everything project-specific lives in one repo-root `.memory-tree.conf`; the scripts and rules
below are identical across repos. (Reference implementation: the inCMS `docs/`→`memory/` reorg,
ARCH-bOrderlyAtlas-1.)

## What's here

| File | Role |
|---|---|
| `.memory-tree.conf.example` | the per-repo config — `MEMORY_ROOT`, `DISCIPLINES`, discipline→`FAMILIES`, optional `TOMBSTONE_ROOTS`. Copy to your repo root as `.memory-tree.conf`. |
| `check-memory-hygiene.sh` | the gate — 12 checks, grandfather-aware, with a `--staged` pre-commit fast leg. THE single source; CI/hook/gate-runner all call it. |
| `gen-memory-tree.sh` | deterministic `TREE.md` generator (`--write` / `--check`); check 9 calls it. |
| `adopt-memory-tree.sh` | `--scaffold` an empty, passing tree from the config (new projects). |
| `HYGIENE.template.md` | the rule set, copied to `memory/HYGIENE.md` at scaffold time. |
| `SPEC-TEMPLATE.template.md` | the canonical spec/design-pass format, copied to `memory/TEMPLATE-SPEC.md` at scaffold time; check 12 enforces it once `SPEC_FORMAT_CUTOFF` is set. |
| `check-memory-hygiene.test.sh` | fixture self-test for check 12 (red + green classes in a scratch repo). |

## Configure

Copy `.memory-tree.conf.example` to your repo root as `.memory-tree.conf` and edit:
- `MEMORY_ROOT` — the tree's root folder (default `memory`).
- `DISCIPLINES` — your development streams (add one only when content exists — no empty folders).
- `FAMILIES` — `discipline:FAMILY` pairs; FAMILY is the id-family prefix and the required build-folder FAMILY.
- `TOMBSTONE_ROOTS` — set to the old tree you migrated FROM (e.g. `docs`) so it can't resurrect; blank otherwise.
- `SPEC_FORMAT_CUTOFF` — the date you adopt the kit; specs dated ≥ it must follow `TEMPLATE-SPEC.md` (check 12). Blank disables the check; older specs are grandfathered by filename date either way.

Disciplines are yours to name. A SWEBOK v4 mapping is a reasonable default lens (Software Architecture,
Construction, Testing, Security, Operations, …), but product streams (as inCMS uses) work equally well —
put the KA tag in each discipline's `README.md`, not in the folder name.

## Adopt — new project (scaffold)

```bash
cp memory-tree/.memory-tree.conf.example .memory-tree.conf   # then edit
bash memory-tree/adopt-memory-tree.sh --scaffold             # creates memory/ + project/ + disciplines + TREE.md
bash memory-tree/check-memory-hygiene.sh ; echo $?           # expect 0
git add memory/ .memory-tree.conf && git commit
```

## Adopt — existing tree (migrate)

Migrating an existing docs/notes tree is a ONE-TIME landing, done in your repo (the re-file map is
project-specific data, so it is not a generic script). The inCMS reorg is the worked reference; the
pattern:
1. Write a table-driven mover that `git mv`s the whole tree to `MEMORY_ROOT`, then re-files per-feature
   material into `builds/YYYY-MM-DD-<FAMILY>-<slug>/`, with a census-drift guard that hard-fails any
   unmapped path.
2. Rewrite every in-tree + out-of-tree reference (masking false-positives like URLs and unrelated paths).
3. Emit `legacy-files.txt` (migrated recordings keep historical names) + `curation-debt.txt` (the fat
   legacy indexes) so the caps/naming checks pass on day one and tighten later (Phase-3 curation).
4. Set `TOMBSTONE_ROOTS` to the old root; run this gate; land atomically.
   During the transition you can keep the old gate green by running the kit only after the flip — or make
   the gate dual-mode (old checks until the flip, `memory/` checks after).

## Wire the gate (all three)

- **CI:** a job running `bash memory-tree/check-memory-hygiene.sh` (no args = full check, includes TREE drift).
- **Local gate runner:** add it as a concurrent leg (cheap, parallel with your test/typecheck legs).
- **pre-commit hook:** BEFORE any linked-worktree early-exit, guarded so a hook-proof in a scripts-less repo
  stays green:
  ```sh
  top=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
  if [ -f "$top/memory-tree/check-memory-hygiene.sh" ] &&
     git diff --cached --name-only --diff-filter=ACMR -- 'memory/**' | grep -q .; then
    bash "$top/memory-tree/check-memory-hygiene.sh" --staged || exit 1
  fi
  ```

## Notes

- Determinism: the scripts export `LC_ALL=C`, emit LF, and `--strip-trailing-cr` on the drift diff — stable
  across Windows/Linux. Add `memory/**/TREE.md text eol=lf` (+ the two manifests) to `.gitattributes` so a
  Windows autocrlf checkout can't spuriously fail check 9.
- The gate is Bash (git-bash on Windows works). The `--staged` leg scopes the file-checks to staged paths.
- No brand gate, no product-specific migration lives here — those stay in the adopting repo.

## Codebase-map interop

Adopting the sibling `codebase-map/` kit with `MAP_ROOT` under this tree (e.g. `memory/map`)?
The hygiene + TREE scripts read `.codebase-map.conf` and carve that subtree in automatically —
see the "Codebase-map interop" section the HYGIENE template ships. No conf keys here change.
