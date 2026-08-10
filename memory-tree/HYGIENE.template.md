<!-- gov:kit memory-tree@2.2 -->
# memory/ retention & hygiene

`memory/` is the project's AI-first memory: version-controlled, travelling to every node on clone.
It holds one append-only decision log, per-build folders, the gate's own waiver registries, and
long-lived guides.
The tree is FLAT: the discipline is a SIGNAL, not a directory. Which discipline a build served is
declared in each spec's status header as `streams <value>[+<value>]`, over the closed enum your
repo-root `.memory-tree.conf` declares as `DISCIPLINES`. A build spanning two disciplines is one
build, in one folder.
This file is the rule set; the single mechanical enforcement is `memory-tree/check-memory-hygiene.sh`
(run by CI, the pre-commit hook, and the local gate runner). Prose rules with no wiring rot — the
script is the law, this doc explains it. (Replace `memory/` throughout with your `MEMORY_ROOT` if you renamed it.)

## Structure

```
memory/
├── README.md              root index (one-liners)
├── LIVE.md                GENERATED — builds with a non-terminal unit (memory-tree/gen_build_index.py)
├── ledger/<YYYY-MM>.md    GENERATED — one row per build opened that month; freezes when the month passes
├── HYGIENE.md             this file
├── TEMPLATE-SPEC.md       the canonical spec/design-pass format (check 12; ships with the kit)
├── DECISIONS.md           append-only decision index, EVERY family, grouped for reading
├── backlog/<FAMILY>.md    mutable backlog, one shard per id family (status-vocabulary rows)
├── decisions/             decision detail (append-only area files)
├── guides/                long-lived reference guides
├── archive/               rotated indexes + legacy material a build can't claim
├── project/               the gate's own waiver registries (`*.txt`, five of them) and nothing else
└── builds/<slug>/
    ├── README.md · STATUS.md       (required only when >3 files / multi-item)
    └── prompts/ · spec/ · build/ · reviews/   (<date>-<kind>[-<FAMILY>]-<slug>-<seq>.md)
```

`<FAMILY>` is a stream's id family from `.memory-tree.conf` (`architecture:ARCH …`). A build folder is
named for its SLUG alone — no date, no family. A recording filename MAY carry the family as an
optional qualifier, which is how one slug shared by two families survives in a single folder.
Ceremony is conditional: subfolders exist only when non-empty; a single-file build is one spec file
plus its backlog row — no README/STATUS. Non-markdown artifacts (scripts, data) are legal only inside
`builds/*/build/`, `guides/`, and `archive/`.

## Rules

1. **Prompt placement (structural).** Prompt-kind files are sanctioned ONLY under `builds/*/prompts/`
   or `archive/`. A scratch planning-prompt committed elsewhere is a regression.
2. **No instance-specific / secret content** in core memory — scrub throwaway dev creds before mirroring a note.
3. **Archive-or-file on landing.** DECISIONS.md is the durable home. Delete cold scratch notes; file a
   feature's plan/review writeups into its `builds/` folder; a file's own "NOT merged" status prose rots.
4. **No broken relative links** outside the append-only log (`DECISIONS.md`, `decisions/`), `archive/`
   (dead pointers allowed by design), and migrated recording files listed in `legacy-files.txt`. The
   generated index files are NOT exempt: their rows link to build READMEs, and a link that stops
   resolving is exactly the drift they exist to prevent.
5. **A check never selects an empty population.** A path selector that matches nothing prints nothing,
   and nothing is what a passing check prints. Every selector over a population a real tree has
   asserts it is non-empty, so a mis-segmented path fails loudly instead of disarming its check.

## Index budgets, caps, rotation

- **Entry budget:** every entry in an index (`DECISIONS.md`, `backlog/<FAMILY>.md`, `STATUS.md`,
  `LIVE.md`, `ledger/<month>.md`, root `README.md` lists) is ONE physical line, ≤ 300 chars. Detail
  lives in the build folder or decision file the line points at. `guides/*.md` is exempt from the
  entry budget — a guide is prose, not index rows — and still carries the file caps below. That
  exemption is ONE expression with one base and one optional append for the codebase-map detail
  files; a second full spelling of it is how the `guides/` half went missing once.
- **File caps:** index + generated files ≤ 20 KB AND ≤ 250 lines. `archive/` is wholly exempt.
- **Rotation** (on cap breach): `git mv <INDEX>.md archive/<INDEX>.<YYYY-MM-DD>.md`; create a fresh index
  whose line 1 notes the rotation + the id range archived. BACKLOG rotation carries forward every
  non-CLOSED/non-WONTDO row. Rotated archives stay inside `memory/` so the all-time id collision grep still
  covers them. Rotation moves whole files — it never rewrites or renumbers a ratified record.

## Status vocabulary (backlogs + STATUS.md)

Every backlog / STATUS row leads with exactly one token of
`OPEN · SPECCED · INPROGRESS · BLOCKED · DEFERRED · CLOSED · WONTDO`, in its `·`/`|`/leading-dash slot
(a prose mention of one of these words elsewhere on the line does not count). New-entry dash form:
`- <id> · <STATUS> · <one-liner>[ → <pointer>]`.
Spec status headers (check 12) reuse the same seven tokens with spec-lifecycle meanings — see
`TEMPLATE-SPEC.md`.

## The grandfather ratchet

Five plain lists in `memory/project/` — the whole of what that directory holds — read as exact-key
set membership rather than a `grep -qxF` per call, because that fork ran once per scanned file:
- **`legacy-files.txt`** — recording files kept under historical names (e.g. from a migration), permanently
  exempt from the recording-file naming check. Should not grow after the initial adoption.
- **`curation-debt.txt`** — index files pending slimming, exempt from the cap / entry-budget / status-vocabulary
  checks while listed. Every curation sweep deletes lines; empty = fully strict. CI fails if a listed path is gone.
- **`id-orphan-waiver.txt`** — ids cited but never defined, deliberately (check 14). Shrink-only
  against `ORPHAN_ID_PIN`, with a stale-entry guard: a waived id that now resolves reds.
- **`corpus-path-unresolved.txt`** — rooted repo-path citations that resolve to nothing (check 15),
  one TAB-separated row per `(citing-file, cited-path)`. Shrink-only against `DEAD_PATH_PIN`.
- **`unarmed-branches.txt`** — `fail` branches no assertion reaches (the harness meta-gate below).
  Shrink-only, and EMPTY is its working state rather than its retirement.

All five are scaffolded by `adopt-memory-tree.sh`. "Absent" and "present and empty" read identically
to every consumer, so a registry a gate names and nothing creates is invisible until the first row.

## The check catalog (all in `memory-tree/check-memory-hygiene.sh`; this file is the prose home)

1. **prompt placement** — prompt-kind files only under `builds/*/prompts/` or `archive/`.
2. **link integrity** — every relative md link resolves (exempt: DECISIONS.md, `decisions/`, `archive/`,
   and `legacy-files.txt`-listed recordings). The generated index files are NOT exempt.
3. **structure lint** — the `memory/` root holds only the sanctioned set; `backlog/` holds only
   `<FAMILY>.md`; `builds/` holds only folders; `decisions/ guides/ archive/` contents are
   unconstrained; `project/` holds ONLY the five waiver registries — no catch-all — and its selector
   carries rule 5's guard, so a mis-segmented `project/` path reds instead of admitting everything;
   `builds/` shape is check 4.
4. **build-folder naming** — `builds/*` is the SLUG alone, no date and no family prefix; inside a
   build folder only `README.md STATUS.md prompts/ spec/ build/ reviews/` plus loose recording-named
   `.md`; non-md only in `build/`.
5. **recording-file naming** — files under the four subfolders, AT ANY DEPTH, match
   `<date>-<kind>[-<FAMILY>]-<slug>-<seq>[-<unit-tail>].md`. The kind comes from the SUBFOLDER, not
   from the file's immediate parent — `spec/units/x.md` is a spec. The family is the closed
   `FAMILIES` alternation and the optional unit tail is shared with check 12's selector, in one
   variable, because two hand-copied EREs for one grammar had already diverged (grandfather:
   `legacy-files.txt`).
6. **index size caps** — the index set ≤ 20 KB / ≤ 250 lines (grandfather: `curation-debt.txt`).
   `guides/*.md` is in that set: a guide is MANDATORY reading the charter points a session at, and
   check 16 refuses a charter-cited file that nothing caps. Entry-budget exempt (check 7's `ex7`) —
   a guide is prose, not index rows.
7. **entry budget** — index entry lines ≤ 300 chars (grandfather: `curation-debt.txt`).
8. **status vocabulary** — `backlog/<FAMILY>.md` and STATUS rows carry exactly one slot status token (grandfather: `curation-debt.txt`).
9. **build-index drift** — `memory-tree/gen_build_index.py --check` must be clean. The index is
   DERIVED from each build's README front matter (`slug node opened streams roster ids [status]`, at
   column 0, opening at line 1) plus every `**Status:**` header under its `spec/`. A build with no
   README, an unpaired generated-region marker, or two answers to its own status is a NAMED error.
   Pin the generated files `eol=lf` in `.gitattributes` — the gate byte-compares them.
10. **rotation note** — every rotated `archive/<INDEX>.<date>.md` is referenced from lines 1–3 of its live index.
11. **old-tree tombstone** — if `.memory-tree.conf` sets `TOMBSTONE_ROOTS` (the tree you migrated FROM),
    the gate fails if that tree ever regains a tracked file. Blank = skipped (fresh-scaffold projects).
12. **spec format** — when `.memory-tree.conf` sets `SPEC_FORMAT_CUTOFF`, spec files dated ≥ it
    (any depth under `spec/`) carry the `**Status:**` header (token · rev · date · node · tier ·
    base sha); Tier-2 adds exactly the canonical `##` sections, non-empty bodies,
    header-rev-in-§9 parity — the §9 range CLOSES at the next `##`, so a bigger `rev-N` in §10 no
    longer satisfies the header — and a resolved §8 before CLOSED/WONTDO; both tiers reject skeleton
    placeholders and a bare WONTDO tail (`TEMPLATE-SPEC.md`). Older specs grandfathered by filename date.
    A `streams` segment is validated against the `DISCIPLINES` enum whenever present, on either tier,
    and is REQUIRED once the filename date reaches `STREAMS_CUTOFF`.

13. **id-definition collision** — one id claimed by two different build folders. A decision-log row
    and its spec's H1 both anchor the same id BY DESIGN (the index points at the record), so
    "defined twice" is not the test; "claimed by two builds" is.
14. **orphan ids** — an id cited but never defined fails unless listed in
    `project/id-orphan-waiver.txt`, which carries a shrink-only pin (`ORPHAN_ID_PIN`) and a
    stale-entry guard: a waived id that now resolves is a stale row and reds.
15. **dead repo-path citations** — a rooted repo-path citation in the PRESENT-tense corpus that
    resolves to nothing must be registered in `project/corpus-path-unresolved.txt`. A DIRECTORY
    citation counts: it is exactly as broken when it does not resolve, and the flatten left four of
    them in the live ledger. `DEAD_PATH_EXCLUDE` names prefixes that are not repo CONTENT — a
    checkout location, say — because resolution never touches the filesystem and cannot tell meaning
    from existence. Four rules:
    (1) set equality between the registry and the measured set, keyed on `(citing-file, cited-path)`
    with an occurrence count and NEVER on a line number — a line number moves on unrelated edits and
    a gate whose steady state is red gets bypassed; (2) a shrink-only pin (`DEAD_PATH_PIN`);
    (3) no duplicate rows; (4) a `moved:<dest>` row needs `<dest>` to be a tracked FILE.
16. **read-path accounting** — the files `CHARTER` points a session at, under `MEMORY_ROOT`, derived
    from the charter's own text through three token arms. The total stays under `READ_PATH_CEILING`
    (one-sided — shrinking never reds) and every member is either byte-capped by check 6 or listed in
    `READ_PATH_WAIVER`; a charter citation nothing watches is the rule-3 case.

Checks 13-16 live in `memory-tree/corpus_ids.py` and are DISABLED when their pins are blank.
Every pin is MEASURED against the adopting corpus (`corpus_ids.py --measure`), never inherited: a pin
copied from a larger tree is either vacuous or permanently red. The id grammar comes from the
memory-recall kit, so arming these checks requires that kit — with the pins blank it is never
imported, and with a pin set and the kit absent the failure is NAMED, not a traceback.

17. **catalogue index freshness** — `gotchas/INDEX.md` byte-matches a fresh render.
18. **a class declares its resolution** — every `kind: class` record names a gate or says in as many
    words that it has none. Silence is not acceptable: "no gate named" and "gate not yet written" are
    indistinguishable from outside, and the second one quietly never happens.
19. **the record can actually fire** — a class record derives at least one anchor or is marked
    `universal`, and a record whose anchors reach ONLY the append-only tree is reported as INERT:
    reachable on paper, dead in practice. The `universal` set is budgeted (`UNIVERSAL_BUDGET`)
    because every universal record is emitted on EVERY reviewer's checklist.

## The harness meta-gate

Every `fail` BRANCH in every gate is either ARMED — a POSITIVE assertion in that gate's own sibling
test naming a literal slice of the branch's OWN failure text — or listed in
`project/unarmed-branches.txt`. The POPULATION IS DISCOVERED: a tracked `*.sh` that DEFINES `fail()`
and has `fail <n> "` call sites is a gate, and `<stem>.test.sh` beside it is its test; a missing
sibling test is a named failure. `*.test.sh` is excluded, because a fixture that QUOTES a fail line
would otherwise demand a `<stem>.test.test.sh` that will never exist.

The key is `(gate, check number, ordinal)`. The gate is in the key because the PIN's keys are global
and two gates both number their checks from 1 — measured, seven keys are claimed by both of this
repo's gates. The ordinal is in the key because one number can carry several branches and a
number-keyed pin lets the cheapest arm hide the valuable one.

A branch's signature ends at the first UNESCAPED closing quote of its message. Capturing to end of
line puts shell source into the signature for any branch written inline as `{ fail 2 "…"; ok=0; }`,
and no assertion can ever emit that — the row becomes permanently unarmable inside a shrink-only
pin.

Three things do NOT arm a branch: a bare `check N` mention, an ABSENCE assertion, and a COMMENT. All
three are "something in the file mentions it", which is not "something exercises it".

The pin is shrink-only and reds three ways: a pinned branch that is now armed, a pinned branch that
no longer exists, and a signature the message was reworded out from under. It is EXCLUDED from its
own scan — it holds each signature verbatim in order to name it.

BOTH directions are pinned, PER GATE — `ARMS_FLOORS="<gate>:<branches>:<armed> …"`. The branch floor
catches a deleted guard; the armed floor catches an assertion dropped by WIDENING the pin, which a
branch count alone cannot see because the count falls and the pin still holds. Per-gate rather than
aggregate: a total lets one gate's deletion be masked by another gate's addition, and goes slack by a
whole gate's branch count the day a third gate lands. A gate that raises a named error does not abort
the walk, so one bad gate cannot hide every other gate's findings.

`memory-tree/check-arms.py --report` shows every branch, its line, its signature and its state.

The pin is EMPTY today — 30 of 30 branches across both gates are armed — and an empty pin is the
file's working state, not its retirement. A row appears when a new branch lands that no fixture can
reach, and it carries the REASON in a comment above it: "not yet written" and "cannot be written
from here" look identical in a bare pin and only one of them is acceptable. Where an arm goes is a
property of the harness, not a preference: the hygiene gate's `fail` never aborts, so one scratch
tree trips many branches in one ~9 s invocation and the fixtures batch; the manifest gate's CALLERS
short-circuit — `BLOCK_OK` skips four whole checks after any check-2 branch fires, and check 3 is a
mutually-exclusive `if`/`elif` chain — so its branches need separate small repos and must not be
helpfully merged back together.

## The bug-class catalogue

One authored record per class under `gotchas/`, front matter `name` + `description` (+ optional
`kind` and `universal`) at COLUMN 0 — an indented key is dropped without a word by any simple parser,
so it is a named error here. ANCHORS ARE DERIVED, not declared: a record's anchors are the
backtick-quoted path-like tokens in its body, because an authored list is a second copy of what the
body already says. Derivation over-selects rather than under-selects, and a record naming no path is
REPORTED as unanchored rather than silently never firing.

Hand a reviewer the classes their diff can hit:

```bash
python memory-tree/gotchas.py --for-diff <base>..<head>
```

Its stdout IS the checklist. A checklist nobody can finish is not a checklist.

## Codebase-map interop

If the codebase-map kit is adopted with its `MAP_ROOT` a DIRECT child of this tree (e.g.
`<MEMORY_ROOT>/map`), that subtree is sanctioned automatically (the scripts read
`.codebase-map.conf`): allowed entries are `README.md`, `FOUNDATION.md`, `baseline.toml`,
`affordance-exempt.toml` (the codebase-map kit renders it; a gate that did not sanction it reds a
freshly-adopted map),
`features/`, `generated/`; `README.md`,
`FOUNDATION.md` and `features/*.md` carry the size caps (check 6: 20 KB / 250 lines) but are
entry-budget exempt (check 7) — dossiers are detail files. A dossier over cap is SPLIT into two
dossiers (never rotated; the map gate requires `FOUNDATION.md` in place). The map's
coverage/freshness enforcement is its own test file, not this script.
