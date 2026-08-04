<!-- gov:kit memory-tree@1.4 -->
# memory/ retention & hygiene

`memory/` is the project's AI-first memory: version-controlled, travelling to every node on clone.
It holds append-only decision logs, per-build folders, session machinery, and long-lived guides —
organised by development discipline (the disciplines your repo-root `.memory-tree.conf` declares).
This file is the rule set; the single mechanical enforcement is `memory-tree/check-memory-hygiene.sh`
(run by CI, the pre-commit hook, and the local gate runner). Prose rules with no wiring rot — the
script is the law, this doc explains it. (Replace `memory/` throughout with your `MEMORY_ROOT` if you renamed it.)

## Structure

```
memory/
├── README.md              root index (one-liners)
├── TREE.md                generated directory tree (memory-tree/gen-memory-tree.sh)
├── HYGIENE.md             this file
├── TEMPLATE-SPEC.md       the canonical spec/design-pass format (check 12; ships with the kit)
├── project/               session machinery: MEMORY.md, IN-FLIGHT.md (pointer) + in-flight/<tag>.md, journal/, notes, 2 ratchet manifests
└── <discipline>/          one per DISCIPLINES entry
    ├── README.md          structure explainer (+ an optional SWEBOK KA tag)
    ├── TREE.md            generated index
    ├── DECISIONS.md       append-only decision index
    ├── BACKLOG.md         mutable backlog (status-vocabulary rows)
    ├── decisions/         decision detail (append-only area files)
    ├── guides/            long-lived reference guides
    ├── archive/           rotated indexes + legacy material a build can't claim
    └── builds/YYYY-MM-DD-<FAMILY>-<slug>/
        ├── README.md · STATUS.md       (required only when >3 files / multi-item)
        ├── prompts/ · spec/ · build/ · reviews/   (YYYY-MM-DD-<kind>-<slug>-<seq>.md)
```

`<FAMILY>` is the discipline's id family from `.memory-tree.conf` (`architecture:ARCH …`). Ceremony is
conditional: subfolders exist only when non-empty; a single-file build is one spec file plus its backlog
row — no README/STATUS. Non-markdown artifacts (scripts, data) are legal only inside `builds/*/build/`,
`guides/`, and `archive/`.

## Rules

1. **Prompt placement (structural).** Prompt-kind files are sanctioned ONLY under `builds/*/prompts/`
   or `archive/`. A scratch planning-prompt committed elsewhere is a regression.
2. **No instance-specific / secret content** in core memory — scrub throwaway dev creds before mirroring a note.
3. **Archive-or-file on landing.** DECISIONS.md is the durable home. Delete cold journals; file a
   feature's plan/review writeups into its `builds/` folder; a file's own "NOT merged" status prose rots.
4. **No broken relative links** outside the append-only logs (`*/DECISIONS.md`, `decisions/`), `archive/`
   (dead pointers allowed by design), generated `TREE.md`, and migrated recording files listed in `legacy-files.txt`.

## Index budgets, caps, rotation

- **Entry budget:** every entry in an index (`DECISIONS.md`, `BACKLOG.md`, `MEMORY.md`, `STATUS.md`,
  root/discipline `README.md` lists) is ONE physical line, ≤ 300 chars. Detail lives in the build folder
  or decision file the line points at. `TREE.md` (generated), `IN-FLIGHT.md`, and the per-node ledger
  files `in-flight/*.md` (a ledger row is a session dossier) are exempt from the entry budget; the per-node
  files still carry the 20 KB file cap.
- **File caps:** index + tree files ≤ 20 KB AND ≤ 250 lines. `archive/` is wholly exempt.
- **Rotation** (on cap breach): `git mv <INDEX>.md archive/<INDEX>.<YYYY-MM-DD>.md`; create a fresh index
  whose line 1 notes the rotation + the id range archived. BACKLOG rotation carries forward every
  non-CLOSED/non-WONTDO row. Rotated archives stay inside `memory/` so the all-time id collision grep still
  covers them. Rotation moves whole files — it never rewrites or renumbers a ratified record.

## Status vocabulary (backlogs + STATUS.md)

Every backlog / STATUS row leads with exactly one token of
`OPEN · SPECCED · INPROGRESS · BLOCKED · DEFERRED · CLOSED · WONTDO`, in its `·`/`|`/leading-dash slot
(a prose mention of one of these words elsewhere on the line does not count). Distinct from the
session-ledger vocabulary (`in-flight | merged:<sha>`, IN-FLIGHT.md). New-entry dash form:
`- <id> · <STATUS> · <one-liner>[ → <pointer>]`.
Spec status headers (check 12) reuse the same seven tokens with spec-lifecycle meanings — see
`TEMPLATE-SPEC.md`.

## The grandfather ratchet

Two plain sorted path lists in `memory/project/`, read with exact-match `grep -qxF`:
- **`legacy-files.txt`** — recording files kept under historical names (e.g. from a migration), permanently
  exempt from the recording-file naming check. Should not grow after the initial adoption.
- **`curation-debt.txt`** — index files pending slimming, exempt from the cap / entry-budget / status-vocabulary
  checks while listed. Every curation sweep deletes lines; empty = fully strict. CI fails if a listed path is gone.

## The check catalog (all in `memory-tree/check-memory-hygiene.sh`; this file is the prose home)

1. **prompt placement** — prompt-kind files only under `builds/*/prompts/` or `archive/`.
2. **link integrity** — every relative md link resolves (exempt: DECISIONS.md, `decisions/`, `archive/`,
   `TREE.md`, and `legacy-files.txt`-listed recordings).
3. **structure lint** — the `memory/` root and each discipline root hold only the sanctioned set;
   `decisions/ guides/ archive/ journal/ in-flight/` contents are unconstrained; `builds/` shape is check 4.
4. **build-folder naming** — `builds/*` matches `YYYY-MM-DD-<FAMILY>-<slug>` with FAMILY paired to its
   discipline; inside a build folder only `README.md STATUS.md prompts/ spec/ build/ reviews/` plus loose
   recording-named `.md`; non-md only in `build/`.
5. **recording-file naming** — files under the four subfolders match `YYYY-MM-DD-<kind>-<slug>-<seq>.md`,
   kind matching subfolder (grandfather: `legacy-files.txt`).
6. **index size caps** — the index set ≤ 20 KB / ≤ 250 lines (grandfather: `curation-debt.txt`).
7. **entry budget** — index entry lines ≤ 300 chars (grandfather: `curation-debt.txt`).
8. **status vocabulary** — BACKLOG/STATUS rows carry exactly one slot status token (grandfather: `curation-debt.txt`).
9. **tree drift** — `memory-tree/gen-memory-tree.sh --check` must be clean.
10. **rotation note** — every rotated `archive/<INDEX>.<date>.md` is referenced from lines 1–3 of its live index.
11. **old-tree tombstone** — if `.memory-tree.conf` sets `TOMBSTONE_ROOTS` (the tree you migrated FROM),
    the gate fails if that tree ever regains a tracked file. Blank = skipped (fresh-scaffold projects).
12. **spec format** — when `.memory-tree.conf` sets `SPEC_FORMAT_CUTOFF`, spec files dated ≥ it
    (any depth under `spec/`) carry the `**Status:**` header (token · rev · date · node · tier ·
    base sha); Tier-2 adds exactly the nine canonical `##` sections, non-empty bodies,
    header-rev-in-§9 parity, and a resolved §8 before CLOSED/WONTDO; both tiers reject skeleton
    placeholders and a bare WONTDO tail (`TEMPLATE-SPEC.md`). Older specs grandfathered by filename date.

## Codebase-map interop

If the codebase-map kit is adopted with its `MAP_ROOT` a DIRECT child of this tree (e.g.
`<MEMORY_ROOT>/map`), that subtree is sanctioned automatically (the scripts read
`.codebase-map.conf`): allowed entries are `README.md`, `FOUNDATION.md`, `baseline.toml`,
`features/`, `generated/`; the map dir appears in the root TREE.md render; `README.md`,
`FOUNDATION.md` and `features/*.md` carry the size caps (check 6: 20 KB / 250 lines) but are
entry-budget exempt (check 7) — dossiers are detail files. A dossier over cap is SPLIT into two
dossiers (never rotated; the map gate requires `FOUNDATION.md` in place). The map's
coverage/freshness enforcement is its own test file, not this script.
