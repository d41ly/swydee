# memory-tree — structured, machine-linted project memory

A project-agnostic kit that turns the governance playbook's §5/§6 memory-and-decisions *principles*
into a concrete, gated folder structure: one `memory/` tree organised by development discipline, with
per-feature `builds/` folders, index budgets + rotation, a status vocabulary, a GENERATED work-state
index, and a 19-check hygiene gate that keeps it that way. The owner reads indexes, not files; sessions stop burning tokens
re-deriving what memory already records.

Opt-in. Everything project-specific lives in one repo-root `.memory-tree.conf`; the scripts and rules
below are identical across repos. (Reference implementation: the inCMS `docs/`→`memory/` reorg,
ARCH-bOrderlyAtlas-1.)

## What's here

| File | Role |
|---|---|
| `.memory-tree.conf.example` | the per-repo config — `MEMORY_ROOT`, `DISCIPLINES`, discipline→`FAMILIES`, optional `TOMBSTONE_ROOTS`. Copy to your repo root as `.memory-tree.conf`. |
| `check-memory-hygiene.sh` | the gate — 19 checks (1-12 in the shell, 13-16 delegated to `corpus_ids.py`, 17-19 to `gotchas.py`), grandfather-aware, with a `--staged` pre-commit fast leg. THE single source; CI/hook/gate-runner all call it. |
| `gen_build_index.py` | the generated build index (`--write` / `--check` / `--selftest`); check 9 calls it. Renders each build README's generated region, `LIVE.md`, and `ledger/<month>.md` shards from build front matter plus every spec's status header — a build's status is a pure function of its units', so nothing is authored and nothing rots. |
| `corpus_ids.py` | the id + path classifier behind checks 13-16 (`--report` / `--check` / `--measure` / `--selftest`): id collisions, orphan ids, dead repo-path citations with a four-rule registry, and read-path accounting. Declares NO grammar and NO set it does not own — the id grammar comes from the memory-recall kit and the append-only/index sets are asked of `check-memory-hygiene.sh` through its print modes. Every pin is measured per corpus; blank pins turn the unit off. |
| `gotchas.py` | the bug-class catalogue behind checks 17-19 (`--check` / `--write` / `--report` / `--for-diff <range>` / `--declares` / `--selftest`). Anchors are DERIVED from each record's body, not authored; `--for-diff`'s stdout IS the reviewer's checklist for that diff. |
| `check-arms.py` | the harness meta-gate: every `fail` BRANCH is armed by a positive assertion naming its own failure text, or pinned in a shrink-only list. Keyed on the call site, pinned in both directions, and excluded from its own scan. |
| `kit-dogfood-parity.test.sh` | the two docs this kit SHIPS must equal the two an adopting repo RUNS ON, modulo the tool-root install prefix (`--check` / `--render`). |
| `adopt-memory-tree.sh` | `--scaffold` an empty, passing tree from the config (new projects). |
| `HYGIENE.template.md` | the rule set, copied to `memory/HYGIENE.md` at scaffold time. |
| `SPEC-TEMPLATE.template.md` | the canonical spec/design-pass format, copied to `memory/TEMPLATE-SPEC.md` at scaffold time; check 12 enforces it once `SPEC_FORMAT_CUTOFF` is set. |
| `merge-rows.py` | the row-keyed three-way merge driver for the authored indexes (`DECISIONS.md`, `backlog/*.md`). TWO PLANES: one stateless predicate (`^\s*[-*]\s`) splits every line into ROW or STRUCTURE, structure is merged positionally by `git merge-file`, and only the row set is key-merged here. The two recombine through a SKELETON — each input projected to a line list where every row becomes a token (its id when the grammar keys it, else a digest of its text with the terminator and trailing whitespace dropped and LEADING whitespace kept, because indentation is nesting and nesting is content) and every other line passes through byte for byte — so placement comes from git's own diff rather than from a splice this driver computes. A conflict region that is entirely tokens on both sides resolves by concatenation, because both sides sit between the same context lines, so section membership is not in dispute and only sibling order is; ANY disputed structure line is always a conflict. Five postconditions run over the WRITTEN BYTES on every verdict: no row line or leading id written more often than any one input carried it, no row under a heading no input filed it under, per-key CONSERVATION (not uniqueness — a file may legitimately carry the same row line twice), and structure identity against the merged skeleton. The anchor grammar is IMPORTED from the sibling memory-recall kit (`grammar_for` / `anchor_at`), never vendored, and there is no degraded mode when it cannot be read: any failure becomes a conflict rather than a silent take-ours. Wiring is two facts in two places and the driver command carries the install prefix — see [Wire the row-keyed merge driver](#wire-the-row-keyed-merge-driver); do not hand-type it. NOT scaffolded by `adopt-memory-tree.sh`: a copy-installed kit lands at `<root>/memory-tree/` with no `lib/pyrun.sh` beside it, so packaging the driver for adopters is its own change. |
| `merge-rows.test.sh` | the driver's replay fixtures, built on ONE bar: **never worse than `git merge-file` on the identical three blobs**. Every case runs a live control and the comparison is arithmetic — losing a line git keeps, or writing a row more often than git does, fails the suite by name. Conflicting where git resolves correctly is acceptable and is COUNTED by name against a shrink-only constant, currently 2 — a row one side moved and the other deleted, in both directions, the one shape where the row plane and the skeleton disagree about intent. On top of that bar: id-set equality against a grammar-independent oracle, the audit line reconciled against the written file at BOTH exit codes, all seven newline sites, the three fail-closed grammar failures, an end-to-end two-branch `git merge` through the real attribute + config, and five sabotage arms that prove each postcondition is the sole net for a defect class. Every case runs a control — two of twenty-eight groups did before — but the arithmetic comparison can only bind where the control EXITS 0, which is 16 of 40 cases and is FLOORED so a fixture edit cannot quietly drop one. Stating that precisely is the point: a suite that reads stronger than it is, is how this driver twice signed off on rc-0 corruption. |
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
bash memory-tree/adopt-memory-tree.sh --scaffold             # creates memory/ + project/ + backlog shards + the generated index
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

## Wire the row-keyed merge driver

TWO facts, wired in two different places. The attribute is COMMITTED, so it lands once for every node:

```gitattributes
memory/DECISIONS.md merge=rows
memory/backlog/*.md merge=rows
```

The driver COMMAND is git config, so it is per node — and both of its path arguments carry the
install prefix, so there is no single literal that starts in both layouts. Do not hand-type it; this
one spelling is correct in both, because the runbook installs `check-wiring.sh` at `<root>/tools/`
either way:

```bash
bash tools/check-wiring.sh --fix     # resolves both prefixes, then sets ONE string
```

`check-wiring.sh` probes for `pyrun.sh` and `merge-rows.py` at each prefix and sets exactly one of
the two commands below. They are quoted here so you can VERIFY what it set — not so you can retype
one of them:

- kit under a `tools/` prefix (what this repo dogfoods):
  `bash tools/lib/pyrun.sh tools/memory-tree/merge-rows.py %O %A %B %P`
- kit copy-installed at the repo root:
  `bash lib/pyrun.sh memory-tree/merge-rows.py %O %A %B %P`

A command that MIXES the two prefixes names a driver that exists in neither layout, and that failure
is not loud. Git prints `CONFLICT (content)`, but a driver that never starts never writes `%A`, so
the path is left holding OURS-ONLY content with ZERO conflict markers and status `UU`: an author who
sees "conflict", opens a marker-free file and `git add`s it has silently dropped every incoming row.
Measured — that is what the previously published mixed-prefix literal did. Two guards keep this
section honest rather than merely correct today: `check-wiring.sh` RUNS the configured command on a
scratch three-way before it reports `ok`, and `check-wiring.test.sh` DERIVES both spellings above by
running `--fix` in a fixture of each layout, so a stray third spelling in this file reds the bar.

## Notes

- Determinism: the scripts export `LC_ALL=C` and emit LF, and the build index normalises CR before it
  compares — stable across Windows/Linux. Add `memory/LIVE.md text eol=lf` and
  `memory/ledger/*.md text eol=lf` (+ the two manifests) to `.gitattributes` anyway: check 9
  BYTE-COMPARES the generated index against an LF render, so an unpinned generated file on a Windows
  checkout is CRLF in the tracked copy — the normalisation keeps the gate honest, the pin keeps the
  committed bytes right, and you want both.
- The gate is Bash (git-bash on Windows works). The `--staged` leg scopes the file-checks to staged paths.
- No brand gate, no product-specific migration lives here — those stay in the adopting repo.

## Codebase-map interop

Adopting the sibling `codebase-map/` kit with `MAP_ROOT` under this tree (e.g. `memory/map`)?
The hygiene + TREE scripts read `.codebase-map.conf` and carve that subtree in automatically —
see the "Codebase-map interop" section the HYGIENE template ships. No conf keys here change.
