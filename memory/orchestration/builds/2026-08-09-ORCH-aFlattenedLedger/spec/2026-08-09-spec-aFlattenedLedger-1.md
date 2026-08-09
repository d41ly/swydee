# ORCH-aFlattenedLedger-1 — flatten the memory tree to kit 1.6 and retire the in-flight ledger

**Status:** SPECCED · rev-1 · 2026-08-09 · node a · Tier-2 · base 6a1c4dd2 · streams orchestration

## 1. Goal

Bring this repo's `memory/` tree from memory-tree kit 1.4 to the current upstream kit, which collapses
the four discipline directories into one flat `memory/builds/<slug>/` tree and replaces the authored
per-node in-flight ledger with a generated work-state index. Upstream is retiring the sharded ledger
as a product feature, and this repo is the one adopter still carrying one.

## 2. Scope (IN)

- **S1** Install memory-tree kit 1.6 over the installed 1.4 at `memory-tree/`, adding the six files
  1.4 does not ship and deleting `gen-memory-tree.sh`, which upstream retired.
- **S2** Flatten `memory/<discipline>/builds/<date>-<FAMILY>-<slug>/` to `memory/builds/<slug>/`,
  merging the six folders that share the slug `aUniformLattice` into one build.
- **S3** Disambiguate the recording filenames that collide or become ambiguous inside the merged
  folder, using the FAMILY qualifier the naming grammar already sanctions.
- **S4** Merge the four per-discipline `DECISIONS.md` into one append-only `memory/DECISIONS.md`, and
  the four `BACKLOG.md` into per-family shards at `memory/backlog/<FAMILY>.md`.
- **S5** Author README front matter (`slug node opened streams roster ids [status]`) plus the
  generated-region marker pair for all nine surviving builds, and generate `memory/LIVE.md` and
  `memory/ledger/<month>.md`.
- **S6** Relocate `memory/project/in-flight/a.md` to `memory/archive/ledger/a.md` byte-identically,
  and delete the pointer stub and the two empty `.gitkeep` directories in the same commit.
- **S7** Re-true every governing doc and gate wiring the restructure falsifies: `AGENTS.md`,
  `.claude/SESSION-KICKOFF.md` (including its `manifest-audit` block), `memory/README.md`,
  `memory/HYGIENE.md`, `.gitattributes`, and the `tools/gate-legs.json` leg name.
- **S8** Record the decisions in the merged `memory/DECISIONS.md`, including a row that supersedes
  `TREND-aGovernedCanon-2` — whose subject is the retired ledger — rather than editing an
  append-only record.

## 3. Non-goals (OUT)

- **Enabling hygiene checks 13-19.** `corpus_ids.py` reads three pins that must be MEASURED against
  the post-flatten corpus, so they cannot be set before the flatten lands. `gotchas.py` needs a
  `memory/gotchas/` catalogue this repo has never had. Both are off by construction while their pins
  are blank and the directory is absent (verified in §4 Inventory). Their adoption is its own unit.
- **Adopting codebase-map.** It is a separate kit with its own adopter blast radius, and nothing in
  the kit bump requires it.
- **Retrofitting the six grandfathered specs.** They are ratified records dated before
  `SPEC_FORMAT_CUTOFF` and are grandfathered by filename date. `HYGIENE.md` says never retrofit them.
- **Deleting the ledger shard.** See §4 Migration; it is the sole carrier of worktree names, branch
  histories and per-family seq high-water marks.
- **Repairing the `DURABLE` retrieval regex in `memory-recall/`.** The flatten takes its population
  from 8 files to 0. It is a real regression, it is measured in §4 Inventory, and it reds no gate —
  see §8 F3, which routes it to a backlog row rather than widening this unit into a second kit.
- **Closing `EXTR-aPatientHarvest-3` and `-4`.** Both are pre-existing prose-versus-checker
  disagreements on the same surface this unit touches. Kit 1.6 resolves neither, so neither may be
  reported as fixed by this unit.
- **Editing any ratified id, any spec body, or any append-only record.** Files move and are renamed;
  their content changes only where a relative link must be repointed.

## 4. Design

### Inventory

Measured at `6a1c4dd2` on 2026-08-09, and re-measured end-to-end in a throwaway clone of this repo
(see Rollout). `git ls-files memory` → **56 tracked paths**, becoming **52** after the flatten.

| what | measured now | after |
|---|---|---|
| build folders | 14, named `<date>-<FAMILY>-<slug>` under four discipline dirs | 9, named for the slug alone |
| folders sharing the slug `aUniformLattice` | 6 | 1 |
| decision logs | 4 (`memory/<discipline>/DECISIONS.md`) | 1 (`memory/DECISIONS.md`), 7638 B / 44 L |
| backlogs | 4 (`memory/<discipline>/BACKLOG.md`) | 4 shards (`memory/backlog/<FAMILY>.md`) |
| generated tree listings | 5 `TREE.md` | 0 — replaced by `LIVE.md` + 2 `ledger/<month>.md` |
| build READMEs carrying front matter | 0 of 1 existing README | 9 of 9 |
| live ledger rows | 3, all `merged:<sha>` | 0 — relocated to `archive/ledger/` |

The merged `memory/DECISIONS.md` enters check 6's capped index set. At 7638 B / 44 L it sits well
under the 20480 B / 250 L cap, so no rotation is needed at the flatten.

Three facts that decide the plan, each measured rather than assumed:

1. **Kit 1.6 still ships the sharded ledger.** `adopt-memory-tree.sh` scaffolds `IN-FLIGHT.md`,
   `in-flight/` and `journal/`, and check 3 admits all three. Retiring the ledger here is therefore
   *permitted, not required* — nothing at 1.6 reds when those paths are absent, because every index
   entry that names them is filtered through a `[ -f ]` test and check 3's entries are permits. Doing
   it now makes this repo forward-compatible with the kit version that removes them.
2. **Checks 13-19 are off.** `corpus_ids.py` enables checks 13-16 only when one of `DEAD_PATH_PIN`,
   `ORPHAN_ID_PIN` or `READ_PATH_CEILING` is non-blank; this repo's `.memory-tree.conf` sets none of
   them. `gotchas.py` returns an empty record set when `memory/gotchas/` is absent, and both its
   check-17 guard and its check-18/19 loop are gated on that set being non-empty.
3. **The cross-kit dependency resolves in this repo's layout.** `corpus_ids.py` looks for the id
   grammar at `<kit-parent>/memory-recall/`. The kit is root-installed at `memory-tree/`, so the
   parent is the repo root and `memory-recall/` is exactly where it looks. The kit self-test passes
   here unmodified: **101 assertions, exit 0.**

The retrieval regression, stated with its number. `memory-recall/extract.py`'s `DURABLE` pattern
requires a `memory/<segment>/(DECISIONS|BACKLOG).md` shape. It selects **8 files today and 0 after
the flatten**, because `memory/DECISIONS.md` has no intervening segment and `memory/backlog/ANLZ.md`
does not end in `DECISIONS.md` or `BACKLOG.md`. `DURABLE` feeds only the `spine` document set, which
no gate and no merge-bar floor reads, so this reds nothing — `memory-recall/selftest.py` and
`adopt-memory-recall.sh --check` both pass over the flattened tree (exit 0 each). It is a silent loss
of retrieval quality, not a broken build, which is why §8 F3 routes it rather than hiding it.

### Data model

A build's identity becomes its **slug alone**. The discipline stops being a directory and becomes a
`streams` value, and a build may carry several — which is what lets six folders become one build.

Front matter opens at line 1 of each build README and carries six required keys plus one conditional:

| key | value | source |
|---|---|---|
| `slug` | must equal the folder name | the folder |
| `node` | `a` | the ledger shard |
| `opened` | the earliest date among the folders that merge into it | the old folder name's date prefix |
| `streams` | `+`-joined, every value inside the `DISCIPLINES` enum | the ledger's `streams` column |
| `roster` | `+`-joined, every value inside the `FAMILIES` set | the ids the build's specs define |
| `ids` | the id range the build owns | the ledger's `seq high-water` column |
| `status` | REQUIRED when no spec carries a parseable header; an ERROR when one does | the specs |

The `status` rule is a hard either/or, not a default: with a derivable status an authored `status:`
key is rejected as "two answers to one question", and with none the absent key is a named error. That
splits this repo's nine builds cleanly — the six grandfathered builds carry no status header at all
and take an authored `status: CLOSED`; the three post-adoption builds derive theirs and must NOT
carry the key.

The derived status is not the same fact the ledger recorded, and the difference is worth stating
because it looks like a contradiction. All three ledger rows read `merged:<sha>`, yet the generated
`LIVE.md` lists `aCandidTally` and `aUniformLattice` as INPROGRESS. Both are correct: the ledger row
described whether a *branch* had merged, and the index describes whether every *unit* has reached a
terminal status. `aPatientHarvest` is CLOSED on both readings and correctly leaves `LIVE.md`.

**The naming grammar and the collision.** Merging six folders into one `spec/` directory produces one
hard filename collision — `EXTR-aUniformLattice-1` and `ORCH-aUniformLattice-1` are both
`2026-08-05-spec-aUniformLattice-1.md` — and a broader ambiguity, because the seq space is per
FAMILY, so a bare `-2` names two different ids. Check 5's grammar already sanctions the fix:

```
<date>-<kind>[-<FAMILY>]-<slug>-<seq>.md
```

The FAMILY slot is the closed alternation from `FAMILIES`, and check 4's comment states this is
precisely "how one slug shared by two families survives the merge into a single folder". The rule
adopted here is **minimum churn**: the originating family for the slug (`ANLZ`, which opened the
build and owns 10 of its 14 ids) keeps unqualified names for the seven specs already in that folder,
and every recording merged in from another folder takes the qualifier. That leaves no two files with
the same name and no bare seq ambiguous, at the cost of six renames instead of thirteen. The
alternative — qualifying all thirteen — is rejected in Alternatives rejected.

### Migration

Per-file destinations, and the unit that performs each. A count cannot derive a destination, so every
path is named.

| path (from `memory/`) | unit | destination | why |
|---|---|---|---|
| `analysis/builds/2026-07-07-ANLZ-aCanonicalTotal/` | U2 | `builds/aCanonicalTotal/` | one folder, one slug |
| `analysis/builds/2026-07-07-ANLZ-aCrossWidget/` | U2 | `builds/aCrossWidget/` | one folder, one slug |
| `analysis/builds/2026-07-13-ANLZ-aGappedRanking/` | U2 | `builds/aGappedRanking/` | one folder, one slug |
| `analysis/builds/2026-07-13-ANLZ-aHeadlineRank/` | U2 | `builds/aHeadlineRank/` | one folder, one slug |
| `analysis/builds/2026-08-05-ANLZ-aCandidTally/` | U2 | `builds/aCandidTally/` | one folder, one slug |
| `extraction/builds/2026-07-13-EXTR-aRelativePeriod/` | U2 | `builds/aRelativePeriod/` | one folder, one slug |
| `extraction/builds/2026-08-04-EXTR-aPatientHarvest/` | U2 | `builds/aPatientHarvest/` | one folder, one slug |
| `trend/builds/2026-07-07-TREND-aCanonicalClient/` | U2 | `builds/aCanonicalClient/` | one folder, one slug |
| `analysis/builds/2026-08-04-ANLZ-aUniformLattice/` | U2 | `builds/aUniformLattice/` | the originating folder; its seven specs and two reviews keep their names |
| `analysis/builds/2026-08-05-ANLZ-aUniformLattice-rowlayer/` | U2 | `builds/aUniformLattice/spec/2026-08-05-spec-ANLZ-aUniformLattice-9.md` | folder suffix was a 1.4-era disambiguator, not part of the slug |
| `analysis/builds/2026-08-05-ANLZ-aUniformLattice-cmpleak/` | U2 | `builds/aUniformLattice/spec/2026-08-05-spec-ANLZ-aUniformLattice-10.md` | same |
| `extraction/builds/2026-08-05-EXTR-aUniformLattice/` | U2 | `builds/aUniformLattice/spec/2026-08-05-spec-EXTR-aUniformLattice-1.md` | resolves the hard collision |
| `orchestration/builds/2026-08-05-ORCH-aUniformLattice/` | U2 | `builds/aUniformLattice/spec/2026-08-05-spec-ORCH-aUniformLattice-1.md` | resolves the hard collision |
| `orchestration/builds/2026-08-05-ORCH-aUniformLattice-docs/` | U2 | `builds/aUniformLattice/spec/2026-08-05-spec-ORCH-aUniformLattice-{2,3}.md` | same slug, different family |
| `<discipline>/DECISIONS.md` ×4 | U2 | merged into `DECISIONS.md`, one `###`-free section per discipline, links repointed | one append-only log per tree at 1.6 |
| `<discipline>/BACKLOG.md` ×4 | U2 | `backlog/{ANLZ,EXTR,ORCH,TREND}.md`, links repointed one level deeper | check 3 admits only `<FAMILY>.md` under `backlog/` |
| `<discipline>/README.md` ×4 | U2 | delete | they describe only the directory that is going away |
| `<discipline>/TREE.md` ×4, `TREE.md` | U2 | delete | the generator that wrote them is retired; `LIVE.md` replaces them |
| `project/in-flight/a.md` | U3 | `archive/ledger/a.md`, byte-identical `git mv` | **sole carrier** of worktree names, the four-branch history of `aUniformLattice`, and the per-family seq high-water marks |
| `project/IN-FLIGHT.md` | U3 | delete; its protocol prose has no successor | its only content is the vocabulary, which retires with the ledger |
| `project/in-flight/.gitkeep`, `project/journal/.gitkeep` | U3 | delete with their directories | 0 B; `journal/` never held a journal |
| `project/README.md`, `project/MEMORY.md`, the two `*.txt` | — | **stay** | check 3 admits all four at `project/`; both registries are empty and remain the grandfather hooks |

**The ledger is read before it is moved, and that ordering is load-bearing.** Its `streams` column is
the source for every `streams:` front-matter value and its `seq high-water` column is the source for
every `ids:` value, so U2 cannot author front matter without it. Relocation, not deletion, also keeps
`git log --follow` working across the move: the dry run records the rename at **R100**.

**Atomicity rule, measured in both directions.** The kit bump and the flatten MUST be one commit.
Neither half is green alone:

| probe | result |
|---|---|
| kit 1.6 installed, tree not yet flattened | check 3 reports the four discipline dirs and `TREE.md`; check 9 reports `LIVE.md` missing; the empty-population guard fires for checks 4, 5, 8 and 12 |
| tree flattened, kit still 1.4 | check 3 reports `archive/ backlog/ builds/ ledger/ DECISIONS.md LIVE.md`; check 9 reports all five `TREE.md` stale |

The empty-population guard firing four ways in the first probe is the 1.5 flatten's own alarm working
as designed: the two tree shapes are mutually exclusive to the gate, so there is no green intermediate
state to land on.

**Link integrity is the only check that needs hand repair.** The dry run's first full gate run over
the flattened tree failed check 2 and nothing else, with exactly eight broken links:

| broken link | repair |
|---|---|
| `memory/README.md → TREE.md` | rewrite `README.md` for the flat shape; `TREE.md` is gone |
| `memory/backlog/EXTR.md → builds/aPatientHarvest/spec/…` | shard sits one level deeper than the old backlog: `../builds/…` |
| six links in `builds/aCanonicalClient/spec/2026-07-07-spec-aCanonicalClient-1.md` | `../../../../<discipline>/builds/<old-folder>/` becomes `../../<slug>/` |

Links inside `DECISIONS.md` are exempt from check 2, so the merged log's repointing is not gate-caught
and must be done deliberately — it is what keeps the log readable and keeps `memory-recall` resolving.

**The `.gitattributes` gap, and what it actually costs.** The only memory-tree line pinning a `.md`
file is `memory/**/TREE.md text eol=lf`, which becomes dead when `TREE.md` goes. The new generated
artifacts are unpinned, and the consequence was measured rather than reasoned: after commit and fresh
checkout, `memory/LIVE.md` and `memory/ledger/2026-08.md` are CRLF; `gen_build_index.py --check`
stays **green**, because its reader normalises CRLF; but `--write` re-emits LF and `git status` then
shows both files permanently modified. So the defect is not a red gate — it is invisible churn that
trains a reader to ignore `git status`. U4 replaces the dead pin with `memory/LIVE.md`,
`memory/ledger/*.md` and `memory/DECISIONS.md`.

### Rollout

Four commits. U1 and U2 are one commit by the atomicity rule above; the rest are separable because
each leaves the gate green.

| unit | work | reds a watched path? |
|---|---|---|
| U1+U2 | kit 1.6 in, `gen-memory-tree.sh` out; the whole flatten; record merges; front matter; the eight link repairs; `LIVE.md` + `ledger/` generated | **yes** — `memory-tree`, and U2 kills a `verify-paths` anchor |
| U3 | ledger to `archive/ledger/`; stub and both `.gitkeep` directories deleted | no |
| U4 | `.gitattributes` pins; the `tools/gate-legs.json` leg name; `AGENTS.md` and `.claude/SESSION-KICKOFF.md` re-trued; `memory/README.md` and `memory/HYGIENE.md` re-trued | **yes** — `tools`, `scripts`, `AGENTS.md`, `memory-recall` |
| U5 | `memory/DECISIONS.md` rows, including the `TREND-aGovernedCanon-2` superseding row; the §8 F3 backlog row | no |

Two ratchets bite on U1+U2 and U4, both measured on the dry run:

- `scripts/manifest-check.sh` **check 4** reds because `verify-paths` anchors
  `memory/trend/builds/2026-07-07-TREND-aCanonicalClient/spec/2026-07-07-spec-aCanonicalClient-1.md`,
  which U2 moves. The same path is cited in §B as the units-index location. Both must be repointed to
  `memory/builds/aCanonicalClient/spec/2026-07-07-spec-aCanonicalClient-1.md` in U1+U2's own commit,
  because the pre-commit hook runs `manifest-check.sh --staged` on every commit.
- `manifest-check.sh` **check 5** reds because watched pathspecs moved with no re-stamp. `watch` is
  `AGENTS.md; skill; tests; tools; scripts; memory-tree; memory-recall; .memory-tree.conf`; U1+U2
  stages `memory-tree` and U4 stages four of them. Each of those two commits carries its own
  `last-audit` re-stamp bundled in, since the `--staged` leg accepts only a re-stamp in that same
  commit. `memory/` itself is not watched, so U3 and U5 need no re-stamp.

### Files touched (estimate)

Kit, replaced wholesale from upstream `tools/memory-tree/`: `check-memory-hygiene.sh`,
`check-memory-hygiene.test.sh`, `hygiene-parity.test.sh`, `adopt-memory-tree.sh`,
`HYGIENE.template.md`, `README.md`, `SPEC-TEMPLATE.template.md`, `.memory-tree.conf.example`.
**New in the kit:** `gen_build_index.py`, `corpus_ids.py`, `gotchas.py`, `check-arms.py`,
`check-verdict-epoch.sh`, `check-verdict-epoch.test.sh`, `kit-dogfood-parity.test.sh`.
**Deleted:** `gen-memory-tree.sh`.

Tree: 14 folder moves, 6 file renames, 9 READMEs authored, 4 decision logs merged to 1, 4 backlogs
resharded, 13 files deleted, 1 shard relocated, 3 artifacts generated.

Repo: `.gitattributes`, `tools/gate-legs.json` (the leg's display name says "12 checks"),
`AGENTS.md` (8 ledger/journal references, including the §3 shard rule the product is retiring),
`.claude/SESSION-KICKOFF.md` (the ledger pointer at `:143`, the stale `TREE.md`/check-9 sentence at
`:260`, the units-index path at `:68`, and the `manifest-audit` block).

`memory/HYGIENE.md` carries 11 references to the retiring machinery and is the copy of the kit's
`HYGIENE.template.md`; replace it from the 1.6 template rather than hand-patching it, so the two do
not drift.

### Alternatives rejected

**Qualifying all thirteen `aUniformLattice` recordings with their FAMILY** — rejected. It is the more
uniform rule and it would make every filename self-describing, but it renames seven files that
already have unambiguous names and, because the build's own `README.md` and several specs
cross-reference them, it multiplies the link repairs check 2 must catch. Minimum churn is preferred
on a restructure whose main risk is a mis-repointed link. The rule is stated in §4 Data model so a
later reader does not read the mixed naming as an accident.

**Adding a fifth discipline for governance work** — rejected. `DISCIPLINES` is a closed enum read by
check 12 and by the front-matter validator, so adding a value is cheap mechanically, but this repo
already files repo-surface work under `orchestration`: `ORCH-aUniformLattice-1` moved the eight test
suites and the gate runner out of the repo root. That precedent makes `orchestration` the established
home, and inventing a stream for one unit would leave two answers to one question.

**Deleting the ledger shard rather than relocating it** — rejected, and upstream reversed its own
spec at build time on the same ground. The status content is redundant and, where it differs from the
generated index, wrong; but the worktree names, the four-branch history behind `aUniformLattice`, and
the per-family seq high-water marks exist nowhere else in the repo.

**Keeping the discipline directories and taking only the non-flatten parts of 1.6** — rejected as not
available. The flatten is not a separable feature of the kit: check 3's permitted root set, check 4's
folder grammar and check 9's generator all encode the flat shape, and the probe above shows the 1.6
gate reporting five findings against the current tree.

## 5. Production-readiness checklist

- security — N/A. No auth, egress or sanitization surface; the change moves markdown and runs
  stdlib-only local scripts.
- perf / scale — the tree is 56 tracked paths. Kit 1.6 is strictly faster on it than 1.4: it batches
  the per-file forks 1.4 spawned. Measured gate runtime stays under a second either way.
- a11y — N/A. No user interface.
- i18n — N/A. No user-facing strings; `skill/SKILL.md` is untouched.
- error / empty / loading states — the empty cases are the ones that bite: an empty `journal/`, two
  empty grandfather registries, and two empty backlogs. Each is preserved as empty rather than
  removed, so a later first row does not look like a new feature.
- observability — the generated `LIVE.md` and `ledger/<month>.md` ARE the instrument, and AC5
  requires them to distinguish live from terminal builds rather than merely render.
- risks (concurrency, data-loss, rollback hazards) — **data-loss is the live risk**, in one place: a
  `git mv` that is not byte-identical, which AC3 pins at 100% similarity. Concurrency: three linked
  worktrees are checked out at detached HEADs and each carries its own pre-flatten `memory/`; they are
  untouched by this unit and will see the flat tree only when they rebase. Rollback is `git revert`;
  no external state.
- testing + left-shift gates — no new gate leg; one leg's display name changes. The whole migration
  was executed end-to-end in a throwaway clone before this spec was written, and the gate result
  quoted in AC1 is that run's.
- migration / rollback — this unit IS the migration; §4 Migration carries the per-file map.
- user docs — S7. `AGENTS.md` and `.claude/SESSION-KICKOFF.md` are the agent-facing surface; there is
  no end-user documentation of the memory tree.

## 6. Acceptance criteria

- **AC1** When `bash memory-tree/check-memory-hygiene.sh` is run after each of U1+U2, U3, U4 and U5,
  it exits 0 and prints nothing. Measured on the dry run at the end of U1+U2 plus U3: exit 0, no
  output.
- **AC2** When `bash memory-tree/check-memory-hygiene.test.sh` is run after U1, it passes with at
  least the 101 assertions the dry run reported, and `bash memory-tree/check-memory-hygiene.sh
  --staged` exits 0.
- **AC3** When `git log --follow --find-renames` is run over `memory/archive/ledger/a.md`, it shows
  the rename from `memory/project/in-flight/a.md` with a 100% similarity index and no content change.
- **AC4** When `git ls-files memory/project` is run after U3, it lists exactly `README.md`,
  `MEMORY.md`, `legacy-files.txt` and `curation-debt.txt`, and nothing else.
- **AC5** When `python memory-tree/gen_build_index.py --check` is run after U1+U2, it exits 0 and
  reports 12 artifacts; `memory/LIVE.md` lists `aCandidTally` and `aUniformLattice` as INPROGRESS and
  does NOT list `aPatientHarvest`; and `memory/ledger/` holds exactly `2026-07.md` and `2026-08.md`.
- **AC6** When `git ls-files memory/builds` is read after U2, every path's third segment is one of the
  nine slugs, no folder name carries a date or a FAMILY prefix, and
  `memory/builds/aUniformLattice/spec/` holds 13 specs whose names are pairwise distinct.
- **AC7** When each of the nine build READMEs is read after U2, front matter opens at line 1 with the
  six required keys; the six grandfathered builds carry `status: CLOSED`; and `aPatientHarvest`,
  `aCandidTally` and `aUniformLattice` carry NO `status:` key.
- **AC8** When `bash scripts/manifest-check.sh` is run after U1+U2 and again after U4, it exits 0 —
  proving the moved `verify-paths` anchor was repointed and each watched-path commit carried its own
  `last-audit` re-stamp.
- **AC9** When `python memory-recall/selftest.py` and `bash memory-recall/adopt-memory-recall.sh
  --check` are run after U4, each exits 0.
- **AC10** When `memory/LIVE.md` and `memory/ledger/2026-08.md` are deleted, restored with `git
  checkout --`, and `python memory-tree/gen_build_index.py --write` is then run, `git status` reports
  no modification to either — the `.gitattributes` fix from U4 verified by the exact procedure that
  reproduced the defect.
- **AC11** When `grep -rniE "in-?flight|journal|TREE\.md" AGENTS.md .claude/SESSION-KICKOFF.md
  memory/README.md memory/HYGIENE.md memory/project/README.md` is run after U4, every surviving hit
  is listed in the commit message with its reason. Measured baseline at `6a1c4dd2`: 8 · 2 · 2 · 11 ·
  2. A zero-hit result on a file whose baseline is 0 proves nothing and is not evidence of work.
- **AC12** When `memory/DECISIONS.md` is read after U5, `TREND-aGovernedCanon-2` is unedited and a
  later row supersedes it by id, naming `memory/archive/ledger/` as the retired ledger's home.
- **AC13** When `bash tools/run-gates.sh` is run at the end of U5, it is green, and the memory-hygiene
  leg's display name no longer claims 12 checks.

## 7. Gates

Existing legs that must stay green, from `tools/gate-legs.json`: the eight `Test-*.ps1` suites, `ps
source hygiene` + its self-test, `memory hygiene` + `memory-hygiene self-test`, `kickoff-manifest
ratchet` + `manifest-check self-test`, `memory-recall kit selftest`, `memory-recall skill wiring`,
`agent-instructions wiring` + self-test, `agent-cap self-test`, `check-wiring self-test`, and
`run-gates canary`.

Load-bearing here: `memory hygiene`, `memory-hygiene self-test`, `kickoff-manifest ratchet`,
`memory-recall kit selftest`, `memory-recall skill wiring`, and `run-gates canary` — the canary
forbids a hardcoded leg command, so the leg rename in U4 must happen in `tools/gate-legs.json` and
nowhere else.

No new leg. Three couplings a builder will otherwise discover the hard way:

1. **The pre-commit runs two legs on every commit.** `check-memory-hygiene.sh --staged` fires
   whenever `memory/**` or `.memory-tree.conf` is staged, and `manifest-check.sh --staged` fires
   unconditionally. A commit that stages a watched path without its `last-audit` re-stamp cannot be
   made.
2. **`hygiene-parity.test.sh` is deliberately not a gate leg** and must not be added as one. It needs
   a before-revision to compare against, and that reference rots the moment anything else edits the
   engine.
3. **`check-verdict-epoch.sh` arrives with the kit but has nothing to gate here.** It exists to force
   `KIT_MEMORY_TREE_VERSION` to move when the engine changes; this repo does not author the engine, it
   copy-installs it. Wiring it would red on the next upstream re-pull for no benefit.

## 8. Open questions

- **F1 — does the ledger retirement land in this unit or wait for the kit version that removes it?**
  Kit 1.6 still scaffolds and admits the sharded ledger; upstream retires it at a later version whose
  spec is written but unlanded. Retiring it here is verified green (§4 Inventory fact 1) and makes
  this repo forward-compatible, but it puts the tree one step ahead of its own kit, so a re-run of
  `adopt-memory-tree.sh --scaffold` would try to recreate what U3 removed. **Recommendation: retire
  it now, in U3**, because the migration is already reading the shard for its front-matter values and
  a second pass over the same file later is the more expensive order. The adopter re-scaffold hazard
  is theoretical: the scaffolder refuses to touch an already-scaffolded tree.
- **F2 — the FAMILY-qualifier rule: minimum churn, or qualify everything?** §4 Alternatives rejected
  argues minimum churn and §4 Data model states the resulting rule. The cost of being wrong is
  asymmetric: qualifying more files later is a rename plus a link sweep, while un-qualifying is the
  same work in reverse. **Recommendation: minimum churn**, with the rule written into the build
  README so the mixed naming reads as a decision.
- **F3 — the `DURABLE` regex, whose retrieval population this flatten takes from 8 to 0.** Three
  exits: fix the regex in this unit; leave it and record a backlog row; or leave it silently. The
  third is not acceptable — it is a measured regression. Fixing it here means forking a second kit
  mid-restructure, and `extract.py` is already a declared fork carrying an upstream sha, so an
  unrelated edit complicates the next three-way merge. **Recommendation: record it as an OPEN
  `ORCH-aFlattenedLedger-2` backlog row in U5**, naming the measured 8 → 0 and the one consumer
  (`bench.py --sets spine`), and fix it in its own unit alongside the upstream re-pull.
- **F4 — should this unit enable hygiene checks 13-19?** §3 puts them out of scope because
  `corpus_ids.py`'s three pins must be measured against the post-flatten corpus, which does not exist
  until U2 lands, and `gotchas.py` needs a catalogue this repo has never had. `corpus_ids.py
  --measure` prints the pins, so the follow-up is mechanical. **Recommendation: out of scope**, with
  a backlog row in U5 so seven silently-off checks are not mistaken for seven passing ones.

## 9. Revision log

- rev-1 · 2026-08-09 · initial draft. Grounded on upstream `TOOL-aMendedLedger-1` rev-3 (read at
  `dae7500` on branch `branch/cd-memory-rework-alignment-005661` in `C:/projects/coding-governance`,
  where its S6b adopter upgrade note is specced but NOT yet landed — `WIRE-INTO-PROJECT.md` still
  documents the sharded ledger as current, so this repo's upgrade path was derived from the kit
  source rather than from a runbook). Every number in §4 is measured against `6a1c4dd2`, and the
  whole migration was executed end-to-end in a throwaway clone first: the kit-1.6 gate is green over
  the flattened tree, the eight broken links in §4 Migration are that run's actual check-2 output,
  the both-directions atomicity table is two separate probe clones, and the CRLF churn and the two
  `manifest-check.sh` failures were reproduced rather than predicted.

## 10. Reuse audit

No `tools/codebase-map/reuse_lookup.py` pass is possible: this repo has not adopted codebase-map and
has no `.codebase-map.conf`, so there is no seam index to query. The reuse decision is therefore
argued from the kit surface directly, which is the whole of what this unit builds against.

**Nothing new is written.** Every mechanism this unit needs already ships in the kit it installs, and
the unit's discipline is to wire through them rather than reimplement:
`gen_build_index.py --write` renders the work-state index and `--check` gates it; check 5's existing
FAMILY-qualifier slot resolves the slug collision; `git mv` carries the rename similarity that AC3
asserts; `corpus_ids.py --measure` is the follow-up's pin source in F4. The one hand-authored
artifact is the nine READMEs' front matter, which is data, not a mechanism, and its values are
transcribed from the ledger shard rather than invented.

The seam deliberately NOT wired through is `memory-recall/extract.py`'s `DURABLE` pattern: F3 records
that the flatten leaves it selecting nothing and routes the repair to its own unit, so this unit
neither vendors a second copy of that grammar nor edits a declared fork mid-restructure.
