# ORCH-aFlattenedLedger-1 — flatten the memory tree to kit 2.2 and retire the in-flight ledger

**Status:** SPECCED · rev-4 · 2026-08-10 · node a · Tier-2 · base 57fe074d · streams orchestration · ratified 2026-08-09, all forks closed 2026-08-10

## 1. Goal

Bring this repo's `memory/` tree from memory-tree kit 1.4 to the current upstream kit, which collapses
the four discipline directories into one flat `memory/builds/<slug>/` tree and replaces the authored
per-node in-flight ledger with a generated work-state index. Upstream retired the sharded ledger as a
product feature, and this repo is the one adopter still carrying one.

**The external prereq is satisfied and overshot (2026-08-10).** rev-2 parked this build until kit 1.7
reached coding-governance `main`; `main` is now at **2.2** (`e7ec336`). The target is therefore **2.2,
not 1.7**, every rev-2 measurement has been re-taken against it, and Status returns BLOCKED → SPECCED.
Two rev-2 statements are superseded rather than merely refreshed, and §4 Rollout carries both:

1. **2.2 retires the ledger from the scaffolder.** `adopt-memory-tree.sh` at 2.2 contains zero
   `IN-FLIGHT`/`in-flight`/`journal` references. F1's ratified action is unchanged, but its rationale
   is: U3 now moves this repo **in step with** its kit, not one step ahead of it.
2. **The adopter runbook landed.** rev-1 derived the upgrade path from kit source because
   `WIRE-INTO-PROJECT.md` still documented the sharded ledger. It now carries §3a, "Migrating an
   existing repo off the sharded session ledger (BREAKING)", which names this repo by measurement as
   the one adopter on this node. Every step of §4 Migration was re-checked against it.

## 2. Scope (IN)

- **S1** Install the target memory-tree kit over the installed 1.4 at `memory-tree/`, adding the files
  1.4 does not ship and deleting `gen-memory-tree.sh`, which upstream retired. The target is kit
  **2.2**, and §4 Files touched now carries the measured 2.2 list rather than a placeholder.
- **S2** Flatten `memory/<discipline>/builds/<date>-<FAMILY>-<slug>/` to `memory/builds/<slug>/`,
  merging the six folders that share the slug `aUniformLattice` into one build.
- **S3** Disambiguate the recording filenames that collide or become ambiguous inside the merged
  folder, using the FAMILY qualifier the naming grammar already sanctions.
- **S4** Merge the four per-discipline `DECISIONS.md` into one append-only `memory/DECISIONS.md`, and
  the four `BACKLOG.md` into per-family shards at `memory/backlog/<FAMILY>.md`.
- **S5** Author README front matter (`slug node opened streams roster ids [status]`) plus the
  generated-region marker pair for all ten surviving builds, and generate `memory/LIVE.md` and
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

Re-measured at `57fe074d` on 2026-08-10 against kit **2.2**, end-to-end in a throwaway clone of this
repo (see Rollout). `git ls-files memory` → **58 tracked paths**, becoming **54** after the flatten.

The absolute counts moved by +2 from rev-2's `6a1c4dd2` figures because two commits later this build's
OWN folder exists: `orchestration/builds/2026-08-09-ORCH-aFlattenedLedger/` is a 15th folder and a
10th slug. The net delta is unchanged at −4, so rev-2's arithmetic stands; only its baseline moved.

| what | measured now | after |
|---|---|---|
| build folders | 15, named `<date>-<FAMILY>-<slug>` under four discipline dirs | 10, named for the slug alone |
| folders sharing the slug `aUniformLattice` | 6 | 1 |
| decision logs | 4 (`memory/<discipline>/DECISIONS.md`) | 1 (`memory/DECISIONS.md`) |
| backlogs | 4 (`memory/<discipline>/BACKLOG.md`) | 4 shards (`memory/backlog/<FAMILY>.md`) |
| generated tree listings | 5 `TREE.md` | 0 — replaced by `LIVE.md` + 2 `ledger/<month>.md` |
| build READMEs carrying front matter | 0 of 2 existing READMEs | 10 of 10 |
| live ledger rows | 3, all `merged:<sha>` | 0 — relocated to `archive/ledger/` |
| files admitted at `memory/project/` | 6 | 2 — see the 2.2 eviction below |

The merged `memory/DECISIONS.md` enters check 6's capped index set. At 7638 B / 44 L it sits well
under the 20480 B / 250 L cap, so no rotation is needed at the flatten.

Three facts that decide the plan, each measured rather than assumed:

1. **Kit 2.2 no longer ships the sharded ledger — retiring it is now REQUIRED, not permitted.** This
   inverts rev-1's fact 1 and is the single largest change at the retarget. `adopt-memory-tree.sh` at
   2.2 contains zero `IN-FLIGHT`/`in-flight`/`journal` references, and check 3's permitted set at
   `memory/project/` is *the gate's own waiver registries (`*.txt`) and nothing else*. Measured on the
   2.2 engine over the UNFLATTENED tree, check 3 names `project/in-flight`, `project/journal` and
   `project/IN-FLIGHT.md` as unexpected entries — so an untouched tree cannot go green on 2.2 while
   the ledger exists. U3 is no longer forward-compatibility work; it is part of the migration.
2. **Checks 13-19 are off, and 2.2 has 19 checks rather than 1.4's 12.** `corpus_ids.py` enables
   checks 13-16 only when one of `DEAD_PATH_PIN`, `ORPHAN_ID_PIN` or `READ_PATH_CEILING` is non-blank;
   this repo's `.memory-tree.conf` sets none of them, and `python memory-tree/corpus_ids.py` exits 0
   over the flattened tree. `gotchas.py` returns an empty record set when `memory/gotchas/` is absent,
   and both its check-17 guard and its check-18/19 loop are gated on that set being non-empty. So 12
   checks are active and 7 are gated off — which is why the leg's display name needs care in U4.
3. **The cross-kit dependency resolves in this repo's layout.** `corpus_ids.py` looks for the id
   grammar at `<kit-parent>/memory-recall/`. The kit is root-installed at `memory-tree/`, so the
   parent is the repo root and `memory-recall/` is exactly where it looks. The kit self-test passes
   here unmodified: **120 assertions, exit 0** (was 101 at 1.6).
4. **`.memory-tree.conf` needs no edit.** Diffing this repo's key set against 2.2's
   `.memory-tree.conf.example`: every key 2.2 reads is present, and the one key this repo has that the
   example omits is `TOMBSTONE_ROOTS`, which 2.2 still reads. `DISCIPLINES` became a closed enum of
   header values rather than a directory list at 1.5, but its value here is already the four stream
   names, so the same literal is correct under both readings.

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
splits this repo's ten builds cleanly — six take an authored `status: CLOSED`, and four derive theirs
and must NOT carry the key.

**Why the six are underivable is not what rev-1 assumed, and the difference is worth pinning.** rev-1
said the grandfathered builds "carry no status header at all". Measured: five of the six DO carry a
`**Status:**` line — `SHIPPED (built, reviewed, merged to main)` and similar — and only
`aCanonicalClient` has none. They are underivable because `SHIPPED` **is not in the status vocabulary**.
`gen_build_index.py` anchors on `^\*\*Status:\*\* (?P<token>…)` over the closed set
`OPEN · SPECCED · INPROGRESS · BLOCKED · DEFERRED · CLOSED · WONTDO`, so the free-prose header does not
match and the build reports "no spec under this build carries a parseable header". rev-1's *action*
was right for the wrong reason; the authored value stays `CLOSED`, which is the vocabulary's terminal
token for work that shipped. A builder who "fixes" the six prose headers into tokens instead would be
rewriting frozen grandfathered records, which §3 forbids.

The four that derive are `aPatientHarvest` (CLOSED), `aCandidTally` (INPROGRESS), `aUniformLattice`
(INPROGRESS) and `aFlattenedLedger` (BLOCKED at rev-2, SPECCED at rev-3 — this build indexes itself).

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
| `orchestration/builds/2026-08-09-ORCH-aFlattenedLedger/` | U2 | `builds/aFlattenedLedger/` | this build's own folder; did not exist at rev-1's `6a1c4dd2` baseline |
| `project/in-flight/a.md` | U3 | `archive/ledger/a.md`, byte-identical `git mv` | **sole carrier** of worktree names, the four-branch history of `aUniformLattice`, and the per-family seq high-water marks |
| `project/IN-FLIGHT.md` | U3 | delete; its protocol prose has no successor | its only content is the vocabulary, which retires with the ledger |
| `project/in-flight/.gitkeep`, `project/journal/.gitkeep` | U3 | delete with their directories | 0 B; `journal/` never held a journal |
| `project/README.md`, `project/MEMORY.md` | U3 | **delete** — F5, ratified 2026-08-10 | **REVERSED at 2.2.** rev-1 had these staying. Both are empty scaffolding: `MEMORY.md` is 48 B holding zero notes, and two of `README.md`'s three bullets describe machinery THIS unit deletes |
| `project/legacy-files.txt`, `project/curation-debt.txt` | — | **stay** | still admitted; both are empty and remain the grandfather hooks |

**Check 3 evicts two files at 2.2 that 1.6 admitted, and this is the one migration row the retarget
reverses.** 2.2's `HYGIENE.template.md` states the rule directly: `project/` holds "the gate's own
waiver registries (`*.txt`, five of them) and nothing else". Measured on the flattened tree with the
2.2 engine, check 3 fails naming exactly `memory/project/MEMORY.md` and `memory/project/README.md`;
the two `.txt` registries are not named. Draining both takes the gate to **exit 0, no output** — the
dry run proved that by relocating them, and a deletion satisfies check 3 identically, because the
check tests what REMAINS rather than where anything went.

**F5 ratified them as DELETIONS on 2026-08-10**, after the files were read rather than counted.
`MEMORY.md` is 48 bytes — an `# Memory Index` heading and a `> One line per durable note.`
blockquote, holding zero notes. `README.md` is 241 bytes describing three things: `MEMORY.md`, the
in-flight ledger, and `journal/` — and this unit deletes the latter two, so two of its three bullets
are false the moment it lands. Nothing in the repo links to either file. `archive/`'s charter is
"legacy material a build can't claim", and an empty index and a description of removed machinery are
neither. Git keeps both recoverable, which is exactly why a deletion is cheap here and a relocation
would have bought nothing but two files nobody will read.

The same passage names five registries where this repo has two (`corpus-path-unresolved.txt`,
`id-orphan-waiver.txt` and `unarmed-branches.txt` are the absentees). Their absence is NOT a failure:
the gate is green without them, because each is a waiver file consulted only by a check this repo has
gated off. They arrive with checks 13-19, which F4 keeps out of scope.

**The ledger is read before it is moved, and that ordering is load-bearing.** Its `streams` column is
the source for every `streams:` front-matter value and its `seq high-water` column is the source for
every `ids:` value, so U2 cannot author front matter without it. Relocation, not deletion, also keeps
`git log --follow` working across the move: the dry run records the rename at **R100**.

**Atomicity rule, measured in both directions.** The kit bump and the flatten MUST be one commit.
Neither half is green alone:

| probe | result at 2.2 (re-taken 2026-08-10, two separate clones) |
|---|---|
| kit 2.2 installed, tree not yet flattened | exit 1. Check 3 reports the four discipline dirs, `TREE.md`, **and `project/in-flight`, `project/journal`, `project/IN-FLIGHT.md`, `project/MEMORY.md`, `project/README.md`**; check 9 reports `LIVE.md` missing (never rendered); the empty-population guard fires for checks 4, 5, 8 and 12 |
| tree flattened, kit still 1.4 | exit 1. Check 2 reports the 8 broken links; check 3 reports `archive/ backlog/ builds/ DECISIONS.md`; check 9 reports all five `TREE.md` stale |

The first probe's five extra `project/` entries are the 2.2 tightening; everything else reproduces
rev-1's 1.6 table unchanged, including the four-way empty-population guard. That guard firing is the
1.5 flatten's own alarm working as designed.

The two tree shapes are mutually exclusive to the gate, so there is no green intermediate state to
land on.

**Two checks need hand repair at 2.2, not one.** The dry run's first full gate run over the flattened
tree failed check 2 and check 3 and nothing else. Check 3 is the `project/` eviction above. Check 2 is
exactly eight broken links, unchanged from rev-1:

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

**The precondition is DISCHARGED.** rev-2 held U1 until kit 1.7 reached coding-governance `main`.
Measured 2026-08-10: `main` is at `e7ec336` carrying kit **2.2**, so the hold is satisfied and
overshot by four minor versions. The whole dry run was replayed against 2.2 in a fresh clone of
`57fe074d`, and the rev-2 re-measure table is now a results table rather than a to-do list.

| finding | rev-2 said | re-taken at 2.2 |
|---|---|---|
| the 8 broken links (§4 Migration) | no re-measure | **unchanged** — the same 8, verbatim, in the same 3 files |
| the per-file migration map, the slug collision | no re-measure | **unchanged**, plus one row for this build's own folder |
| R100 on the relocated shard | no re-measure | **unchanged** — `similarity index 100%` |
| the gate is green over the flattened tree (AC1) | re-measure | **green, exit 0, no output** — but only after the F5 relocation below |
| the self-test's assertion count (AC2) | re-measure | **101 → 120** |
| the both-directions atomicity probe | re-measure | **reproduced**, plus five extra `project/` entries in probe A |
| generated artifacts (AC5) | re-measure | **12 → 13**, and the cause is the 10th build, not the engine |
| checks 13-19 off; the `memory-recall` sibling lookup | re-measure | **still off** (no pins set, `corpus_ids.py` exits 0); recall selftest **21/21**, `--check` exit 0 |
| the kit file list (§4 Files touched) | re-measure | **+2 files** — `merge-rows.py`, `merge-rows.test.sh` |
| the `.gitattributes` CRLF churn, the two `manifest-check.sh` failures | no re-measure | **unchanged** — both reproduced exactly |
| the `DURABLE` retrieval population | no re-measure | **unchanged** — measured 8 → 0 |

**One finding is new at 2.2 and appears in no rev-2 row: check 3 evicts `project/MEMORY.md` and
`project/README.md`.** It sits inside the surface rev-2 predicted ("check 3's permitted root set is
the engine's"), so the table caught it, but its consequence is a reversed migration row rather than a
changed number. That is F5.

**Two kit self-tests cannot run in this repo's layout, and neither is wanted.** `merge-rows.test.sh`
and `check-verdict-epoch.test.sh` both resolve the repo root as `$HERE/../..`, which assumes the kit
sits at `<root>/tools/memory-tree/`; this repo root-installs at `memory-tree/`, so that path lands
outside the repo. `check-verdict-epoch.sh` itself hardcodes `tools/memory-tree/check-memory-hygiene.sh`
and exits 2 here. §7's third coupling already declined that leg on its own merits, so this measurement
confirms a decision rather than forcing one. The hygiene ENGINE is layout-independent (it resolves via
`git rev-parse --show-toplevel`), which is why AC1 is green regardless.

**Three commits at 2.2, not four — U3 has been absorbed.** rev-1 made U3 separable on the measured
fact that kit 1.6 still ADMITTED the ledger paths, so a commit that flattened but left them alone was
green. At 2.2 it is not. Probed directly (kit 2.2 installed, flatten and front matter complete, U3's
work deliberately skipped): check 3 fails naming `project/in-flight`, `project/journal`,
`project/IN-FLIGHT.md`, `project/MEMORY.md` and `project/README.md`, exit 1. The ledger retirement is
now inside the same atomicity envelope as the kit bump and the flatten.

This is the mechanical consequence of F1 being overtaken by upstream: the owner ratified retiring the
ledger as a choice, and 2.2 turned it into a requirement. The ratification still governs — it is why
the shard is relocated rather than deleted — but "which commit" is no longer a free variable.

**The intermediate commit could not be MADE even if a red gate were tolerable.** Check 3 selects
tree-wide — `FILES=$(git ls-files "$M/")` — and, unlike checks 6, 7 and 12, it never calls the
`in_scope` filter, so `--staged` does not narrow it. The pre-commit hook runs
`check-memory-hygiene.sh --staged` whenever anything under `memory/**` is staged. A commit that
stages the flatten while `project/in-flight/` still exists is therefore refused by the hook, not
merely red afterwards. That closes the "land it red and fix it next commit" escape.

| unit | work | reds a watched path? |
|---|---|---|
| U1+U2+U3 | kit 2.2 in, `gen-memory-tree.sh` out; the whole flatten; record merges; front matter; the eight link repairs; `LIVE.md` + `ledger/` generated; `memory/HYGIENE.md` and `memory/TEMPLATE-SPEC.md` replaced from the 2.2 templates; ledger to `archive/ledger/`; stub, both `.gitkeep` directories and the two F5 files deleted | **yes** — `memory-tree`, and U2 kills a `verify-paths` anchor |
| U4 | `.gitattributes` pins; the `tools/gate-legs.json` leg name; `AGENTS.md` and `.claude/SESSION-KICKOFF.md` re-trued; `memory/README.md` and `memory/HYGIENE.md` re-trued | **yes** — `tools`, `scripts`, `AGENTS.md`, `memory-recall` |
| U5 | `memory/DECISIONS.md` rows, including the `TREND-aGovernedCanon-2` superseding row; **two** backlog rows — one for the merged F3+F4 follow-up (memory-recall 1.0 → 1.1, then `DURABLE`, then arm 13-16), one for F6's inert merge driver | no |

Two ratchets bite on U1+U2+U3 and U4, both re-measured on the 2.2 dry run and both unchanged:

- `scripts/manifest-check.sh` **check 4** reds because `verify-paths` anchors
  `memory/trend/builds/2026-07-07-TREND-aCanonicalClient/spec/2026-07-07-spec-aCanonicalClient-1.md`,
  which U2 moves. The same path is cited in §B as the units-index location. Both must be repointed to
  `memory/builds/aCanonicalClient/spec/2026-07-07-spec-aCanonicalClient-1.md` in that same commit,
  because the pre-commit hook runs `manifest-check.sh --staged` on every commit.
- `manifest-check.sh` **check 5** reds because watched pathspecs moved with no re-stamp. `watch` is
  `AGENTS.md; skill; tests; tools; scripts; memory-tree; memory-recall; .memory-tree.conf`. Measured at
  2.2 the first commit stages **17** files under `memory-tree` (the 8 replaced, the 9 new — one more
  pair than at 1.6 — and the deleted `gen-memory-tree.sh`), and U4 stages four more watch entries.
  Each of those two commits carries its own `last-audit` re-stamp bundled in, since the `--staged` leg
  accepts only a re-stamp in that same commit. `memory/` itself is not watched, so U5 needs no
  re-stamp.

### Files touched (estimate)

Measured against kit 2.2 at `e7ec336`, not estimated. Kit, replaced wholesale from upstream
`tools/memory-tree/`: `check-memory-hygiene.sh`, `check-memory-hygiene.test.sh`,
`hygiene-parity.test.sh`, `adopt-memory-tree.sh`, `HYGIENE.template.md`, `README.md`,
`SPEC-TEMPLATE.template.md`, `.memory-tree.conf.example`.
**New in the kit (9, two more than at 1.6):** `gen_build_index.py`, `corpus_ids.py`, `gotchas.py`,
`check-arms.py`, `check-verdict-epoch.sh`, `check-verdict-epoch.test.sh`,
`kit-dogfood-parity.test.sh`, and — new at 2.2 — **`merge-rows.py`, `merge-rows.test.sh`**.
**Deleted:** `gen-memory-tree.sh`. Copy the directory but NOT `__pycache__`.

`merge-rows.py` is the row-keyed three-way merge driver for `DECISIONS.md` and `backlog/*.md` — the
two file shapes this flatten CREATES. It arrives with the kit but is inert until wired, and wiring it
needs `lib/pyrun.sh` plus a `check-wiring.sh` newer than the one installed here. That is F6.

`kit-dogfood-parity.test.sh` fails on a fresh install and is expected to: it byte-compares the kit's
shipped `SPEC-TEMPLATE.template.md` against a render. `bash memory-tree/kit-dogfood-parity.test.sh
--render` then exits 0, and it does not modify `memory/TEMPLATE-SPEC.md`. Run it once in U1.

Tree: 15 folder moves, 6 file renames, 10 READMEs authored, 4 decision logs merged to 1, 4 backlogs
resharded, **15** files deleted (13 plus the two F5 files), 1 shard relocated, 13 artifacts generated.

Repo: `.gitattributes`, `tools/gate-legs.json` (the leg's display name says "12 checks"; 2.2 has
**19**, of which 12 are active here and 7 gated off by F4 — so the honest rename is not simply "19"),
`AGENTS.md` (8 ledger/journal references, including the §3 shard rule the product is retiring),
`.claude/SESSION-KICKOFF.md` (the ledger pointer at `:143`, the stale `TREE.md`/check-9 sentence at
`:260`, the units-index path at `:68`, and the `manifest-audit` block).

`memory/HYGIENE.md` carries 11 references to the retiring machinery and is the copy of the kit's
`HYGIENE.template.md`; replace it from the 2.2 template rather than hand-patching it, so the two do
not drift.

**`memory/TEMPLATE-SPEC.md` must be replaced too, and rev-1 missed it — the installed copy is
structurally wrong in a way nothing here gates.** Measured: swydee's copy closes its fenced skeleton
at line 128 and places `## 10. Reuse audit` at line 130, OUTSIDE the fence; 2.2's
`SPEC-TEMPLATE.template.md` closes at 159 with §10 inside at 153. So an author who copies the
skeleton — which is what the file is FOR — silently omits §10. Check 12 then reds that spec, because
`SPEC10_CUTOFF` defaults to `2026-08-04`, byte-identical to this repo's `SPEC_FORMAT_CUTOFF`: there
is zero grandfathering margin. Nothing catches the template itself, since check 12's canon is
hardcoded in the shell and `kit-dogfood-parity.test.sh` is not a leg here. This is the mechanical fix
for a trap the kickoff manifest currently carries as prose ("a Tier-2 spec dated on/after 2026-08-04
needs a tenth `## 10. Reuse audit` section"); U4 can drop that half of the entry once the template is
correct.

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
- perf / scale — the tree is 58 tracked paths. Kit 2.2 is strictly faster on it than 1.4: it batches
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
  was executed end-to-end in a throwaway clone before this spec was written, and again at rev-3
  against kit 2.2 in a fresh clone of `57fe074d`; the gate result quoted in AC1 is the rev-3 run's.
  Three probe clones back the atomicity and separability claims rather than one.
- migration / rollback — this unit IS the migration; §4 Migration carries the per-file map.
- user docs — S7. `AGENTS.md` and `.claude/SESSION-KICKOFF.md` are the agent-facing surface; there is
  no end-user documentation of the memory tree.

## 6. Acceptance criteria

- **AC1** When `bash memory-tree/check-memory-hygiene.sh` is run after each of U1+U2+U3, U4 and U5,
  it exits 0 and prints nothing. Measured on the rev-3 dry run at the end of U1+U2+U3: exit 0, no
  output. The negative case is pinned too: probe C skipped only U3's work and the same command exits
  1 on check 3, which is why the three units are one commit.
- **AC2** When `bash memory-tree/check-memory-hygiene.test.sh` is run after U1, it passes with at
  least the **120** assertions the rev-3 dry run reported (101 was the 1.6 figure), and `bash
  memory-tree/check-memory-hygiene.sh --staged` exits 0. Additionally `bash
  memory-tree/kit-dogfood-parity.test.sh` exits 0 — it fails on a fresh install until `--render` is
  run once.
- **AC3** When `git log --follow --find-renames` is run over `memory/archive/ledger/a.md`, it shows
  the rename from `memory/project/in-flight/a.md` with a 100% similarity index and no content change.
- **AC4** When `git ls-files memory/project` is run after U3, it lists exactly `legacy-files.txt` and
  `curation-debt.txt`, and nothing else. **Changed at rev-3, settled at rev-4:** `README.md` and
  `MEMORY.md` are no longer admitted by check 3 and are DELETED per F5; an AC4 that still expected
  them would have contradicted AC1. `git ls-files memory/archive` lists exactly `ledger/a.md` —
  the relocation is the shard's alone.
- **AC5** When `python memory-tree/gen_build_index.py --check` is run after U1+U2, it exits 0 and
  reports **13** artifacts (10 build READMEs + `LIVE.md` + 2 month shards; 12 was the nine-build
  figure); `memory/LIVE.md` lists `aCandidTally` and `aUniformLattice` as INPROGRESS and
  `aFlattenedLedger` as its then-current status, and does NOT list `aPatientHarvest`; and
  `memory/ledger/` holds exactly `2026-07.md` and `2026-08.md`.
- **AC6** When `git ls-files memory/builds` is read after U2, every path's third segment is one of the
  **ten** slugs, no folder name carries a date or a FAMILY prefix, and
  `memory/builds/aUniformLattice/spec/` holds 13 specs whose names are pairwise distinct.
- **AC7** When each of the **ten** build READMEs is read after U2, front matter opens at line 1 with
  the six required keys; the six grandfathered builds carry `status: CLOSED`; and `aPatientHarvest`,
  `aCandidTally`, `aUniformLattice` and `aFlattenedLedger` carry NO `status:` key. A build that
  wrongly carries both is a named hard error, not a silent precedence.
- **AC8** When `bash scripts/manifest-check.sh` is run after U1+U2+U3 and again after U4, it exits 0 —
  proving the moved `verify-paths` anchor was repointed and each watched-path commit carried its own
  `last-audit` re-stamp. Both failures were reproduced at 2.2 before the repair: check 4 on the dead
  anchor, check 5 naming 17 `memory-tree/` files.
- **AC9** When `python memory-recall/selftest.py` and `bash memory-recall/adopt-memory-recall.sh
  --check` are run after U4, each exits 0. Re-measured at 2.2 over the flattened tree: selftest
  **21/21 checks passed**, `--check` reports the SKILL matches the conf. This holds despite the
  `DURABLE` population going 8 → 0, which is precisely why F3 exists — nothing reds.
- **AC10** When `memory/LIVE.md` and `memory/ledger/2026-08.md` are deleted, restored with `git
  checkout --`, and `python memory-tree/gen_build_index.py --write` is then run, `git status` reports
  no modification to either — the `.gitattributes` fix from U4 verified by the exact procedure that
  reproduced the defect.
- **AC11** When `grep -rniE "in-?flight|journal|TREE\.md" AGENTS.md .claude/SESSION-KICKOFF.md
  memory/README.md memory/HYGIENE.md` is run after U4, every surviving hit is listed in the commit
  message with its reason. Baseline **re-measured at `57fe074d`: 8 · 2 · 2 · 11 — identical to
  rev-1's first four**, so the two intervening commits touched none of them. rev-1's fifth path was
  `memory/project/README.md` at baseline 2; F5 deletes that file, so its two hits are discharged by
  the deletion and it leaves the grep list rather than being re-pointed. A zero-hit result on a file
  whose baseline is 0 proves nothing and is not evidence of work.
- **AC14** When `bash memory-tree/check-verdict-epoch.sh` is NOT present in `tools/gate-legs.json`
  after U4, that absence is deliberate per §7's third coupling. Pinned as an AC because the leg
  arrives with the kit and a later reader will otherwise assume it was forgotten: measured here it
  exits 2 (`tools/memory-tree/check-memory-hygiene.sh is missing`), since it hardcodes the `tools/`
  prefix this repo does not use.
- **AC12** When `memory/DECISIONS.md` is read after U5, `TREND-aGovernedCanon-2` is unedited and a
  later row supersedes it by id, naming `memory/archive/ledger/` as the retired ledger's home.
- **AC13** When `bash tools/run-gates.sh` is run at the end of U5, every leg is green, and the
  memory-hygiene leg's display name no longer claims a check count that misdescribes 2.2. The engine
  has 19 checks and 12 are active here, so "12 checks" is now wrong on the total and right on the
  effect; the rename must not simply read "19 checks", which would claim seven checks that are gated
  off. The PowerShell suite tallies are untouched by this unit — 1435 assertions before and after.

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
   copy-installs it. Wiring it would red on the next upstream re-pull for no benefit. rev-3 adds a
   second, independent reason measured rather than argued: it hardcodes
   `tools/memory-tree/check-memory-hygiene.sh` and exits 2 in this repo's root-level kit layout. AC14
   pins the absence so it reads as a decision.
4. **`merge-rows.test.sh` is new at 2.2 and is likewise not a leg.** It resolves the repo root as
   `$HERE/../..`, which lands outside this repo, and it sources `tools/lib/resolve-python.sh`, which
   this repo does not carry. The DRIVER it tests (`merge-rows.py`) does run here — that is F6.

## 8. Open questions

- **F1 — does the ledger retirement land in this unit or wait for the kit version that removes it?**
  Kit 1.6 still scaffolds and admits the sharded ledger; upstream retires it at a later version whose
  spec is written but unlanded. Retiring it here is verified green (§4 Inventory fact 1) and makes
  this repo forward-compatible, but it puts the tree one step ahead of its own kit, so a re-run of
  `adopt-memory-tree.sh --scaffold` would try to recreate what U3 removed. **Recommendation: retire
  it now, in U3**, because the migration is already reading the shard for its front-matter values and
  a second pass over the same file later is the more expensive order. The adopter re-scaffold hazard
  is theoretical: the scaffolder refuses to touch an already-scaffolded tree.
  **RESOLVED (owner, 2026-08-09): retire it now, in U3.** Taken with the target version's own
  behaviour measured rather than assumed: kit 1.7 still scaffolds the ledger, so the decision is
  knowingly one step ahead of the kit until upstream's 1.8 bump removes it, and the U3 work is
  unchanged by the version hold.
  *rev-3 note, appended without altering the ratification above:* the retarget to 2.2 carried the
  build past upstream's 1.8 bump, so the "one step ahead" framing no longer describes reality — 2.2's
  scaffolder has no ledger and check 3 rejects one. The ratified ACTION is unchanged and its main
  reason (the migration already reads the shard for front-matter values) still holds. What changed is
  that it stopped being optional: see §4 Rollout's separability probe, which is why U3 folds into the
  first commit.
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
  **RESOLVED (owner, 2026-08-10): backlog row in U5, and the follow-up is ONE unit shared with F4.**
  rev-3 established that F4's follow-up needs the same memory-recall 1.0 → 1.1 re-pull, so the two
  forks share a prerequisite and land together: upgrade the kit, fix `DURABLE` against the flat shape,
  then measure and arm. One review boundary, and the pin measurements are taken against a corpus that
  by then exists. The row must still record the measured 8 → 0, so the regression is not rediscovered
  later as a mystery.
- **F4 — should this unit enable hygiene checks 13-19?** §3 puts them out of scope because
  `corpus_ids.py`'s three pins must be measured against the post-flatten corpus, which does not exist
  until U2 lands, and `gotchas.py` needs a catalogue this repo has never had. `corpus_ids.py
  --measure` prints the pins, so the follow-up is mechanical. **Recommendation: out of scope**, with
  a backlog row in U5 so seven silently-off checks are not mistaken for seven passing ones.
  *rev-3 note:* the count is now exact — 2.2 has 19 checks, 12 active here. The three absent waiver
  registries (`corpus-path-unresolved.txt`, `id-orphan-waiver.txt`, `unarmed-branches.txt`) belong to
  those seven and arrive with them, so they stay out of scope too.
  **rev-1's "the follow-up is mechanical" is WRONG and the correction raises the follow-up's cost.**
  Arming checks 13-16 needs more than setting a pin: `corpus_ids.py` reaches into the memory-recall
  kit for the id grammar via `extract.grammar_for(root)` and raises a named error when the installed
  kit predates that accessor. Measured — swydee's `memory-recall/extract.py` has **0** occurrences of
  `grammar_for`; upstream's 1.1 has 4. So F4's follow-up is gated on a memory-recall 1.0 → 1.1
  re-pull, i.e. a second kit upgrade, not a config edit. This does not affect THIS unit (the pins stay
  blank and the gate is green), but the backlog row U5 files must say so.
  Separately and reassuringly: the frozen `U1..U10` era is safe under checks 13-16 by construction.
  They are disarmed with all three pins blank, and the id grammar requires a `<FAMILY>-` prefix on
  every era, so a bare `U6` matches no branch and can never be read as a definition, a citation or an
  orphan. The second half of that is read from the regex rather than executed, since arming it is
  blocked by the `grammar_for` gap above.
  **RESOLVED (owner, 2026-08-10): out of scope here, and the follow-up merges with F3's into ONE
  unit.** The raised cost strengthens rather than weakens the original recommendation — a fork whose
  follow-up needs a second kit upgrade is plainly not something to bundle into a restructure. The
  shared unit's order is fixed by the dependency: memory-recall 1.0 → 1.1 first, then `DURABLE`, then
  `corpus_ids.py --measure` against the flattened corpus, then arm. U5's backlog row names the
  `grammar_for` prerequisite explicitly, so a later session does not re-derive why a pin edit alone
  fails.
- **F5 — NEW at rev-3. Where do `project/README.md` and `project/MEMORY.md` go?** Kit 2.2's check 3
  admits only `*.txt` waiver registries under `project/`, so rev-1's "they stay" is no longer
  available and doing nothing means a red gate. Three exits: delete both; relocate both under
  `archive/`; or relocate `MEMORY.md` and delete `README.md`. `README.md` describes a directory whose
  contents this unit removes, so most of its text is about to be false. `MEMORY.md` is the durable
  memory-note index and is content, not machinery. **Recommendation: relocate BOTH to
  `archive/project-README.md` and `archive/project-MEMORY.md`** — `archive/`'s charter is "legacy
  material a build can't claim", the relocation is what the rev-3 dry run measured to exit 0, and
  deleting a stale README is a judgement better made when someone reads it than mid-restructure.
  Deleting instead is defensible and costs one line of U3; it is the owner's call, not the gate's.
  **That recommendation was WITHDRAWN before it reached the owner, and the reason is worth keeping.**
  It rested on `MEMORY.md` being "the durable memory-note index … content, not machinery" — asserted
  from the filename, never opened. Measured: `MEMORY.md` is **48 bytes**, an `# Memory Index` heading
  and a `> One line per durable note.` blockquote, holding **zero** notes. `README.md` is 241 bytes
  whose three bullets are `MEMORY.md`, the in-flight ledger and `journal/` — this unit deletes the
  latter two. `grep -rn` across every tracked `.md` finds **no inbound link** to either. So the
  premise was wrong: there is no content to preserve, and `archive/` would gain an empty index plus a
  description of things that no longer exist.
  **RESOLVED (owner, 2026-08-10): DELETE both.** Check 3 is satisfied identically either way — it
  tests what remains, not where anything went — so the gate does not choose here and the owner did.
  Git keeps both blobs reachable, which is why the reversible option is the deletion rather than the
  relocation.
- **F6 — NEW at rev-3. Wire the row-keyed merge driver, or take the kit file inert?** 2.2 ships
  `merge-rows.py`, a three-way merge driver keyed on id rows, whose declared targets are
  `memory/DECISIONS.md` and `memory/backlog/*.md` — both created BY this flatten. Wiring it needs
  three things this repo lacks: `lib/pyrun.sh`, a `tools/check-wiring.sh` new enough to know the
  driver (the installed copy has zero references to it; upstream's has eight), and two
  `.gitattributes` lines plus a per-node `git config` set by `check-wiring.sh --fix`. The value is
  real but not urgent: one node, one session at a time, so the append-only log rarely takes a true
  three-way merge — though when it does, an un-wired driver is exactly the silent "auto-took" class
  `AGENTS.md` §1 warns about, and upstream measured that failure as marker-free. **Recommendation:
  out of scope for this unit, backlog row in U5**, wired alongside the `check-wiring.sh` upgrade in
  the same follow-up that handles the other drifted engine files. Bundling it here adds a second
  kit's wiring to a restructure whose main risk is already a mis-repointed link.
  **RESOLVED (owner, 2026-08-10): copy the file in with the kit, leave it inert, backlog row in U5.**
  The row must record two things a later session cannot re-derive cheaply: that the inertness is a
  decision rather than an oversight, and the two prerequisites above. It must also carry the
  marker-free failure mode, because that is the reason the row exists at all rather than the driver
  simply being dropped.

**Fork state, stated exactly rather than rounded up.** F1 was owner-ratified at rev-2. F3, F4, F5 and
F6 were owner-ratified on 2026-08-10, each at its stated recommendation. **F2 has never been
explicitly ratified** — it was walked through on 2026-08-10 and left standing at its recommendation
(minimum churn) without challenge, which is acceptance by default rather than a decision on the
record. Nothing turns on the difference today, because the recommendation is what U2 builds either
way; it is written down so that a later reader does not cite F2 as ratified when it is not.

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
- rev-2 · 2026-08-09 · owner ratified F1 as **retire the ledger now, in U3**, marked RESOLVED in place,
  and the header tail stamped `ratified 2026-08-09`. Owner also parked the build on an external
  prereq: kit **1.7**, not 1.6, is the target, and it must land on coding-governance `main` first.
  Status moved SPECCED → BLOCKED, which is this repo's token for exactly that. Measured while
  re-targeting: `main` is at 1.6 and 1.7 exists on one unmerged branch, and 1.7 does **not** retire the
  ledger from the scaffolder — so F1's "one step ahead of the kit" reading survives the retarget
  instead of being quietly invalidated by it. §4 Rollout gained the precondition and a
  version-sensitivity table splitting the tree-shape findings, which stand, from the engine findings,
  which must be re-taken. To re-measure: clone this repo to a scratch dir, copy the 1.7
  `tools/memory-tree/` over `memory-tree/`, replay §4 Migration's map, then run the hygiene gate, its
  self-test, `gen_build_index.py --check` and both atomicity probes.
- rev-3 · 2026-08-10 · **retargeted 1.7 → 2.2 and unparked.** The rev-2 precondition is discharged:
  coding-governance `main` is at `e7ec336` carrying kit 2.2, four minor versions past the hold.
  Status BLOCKED → SPECCED. The rev-2 re-measure procedure was executed against `57fe074d` in three
  fresh clones (one migration, two atomicity probes, plus a third separability probe), and §4 Rollout's
  to-do table is now a results table. Baseline moved `6a1c4dd2` → `57fe074d`, which adds this build's
  own folder as a 15th folder and 10th slug; the tree is 58 → 54 paths, so rev-2's −4 delta stands and
  only its absolute figures moved.

  Changed by measurement: self-test **101 → 120** assertions; generated artifacts **12 → 13**; the kit
  file list gains **`merge-rows.py` and `merge-rows.test.sh`**; check 3 now has **19 checks** behind it
  with 12 active here. Unchanged and re-verified: the 8 broken links verbatim, R100 on the shard, the
  `DURABLE` 8 → 0, the CRLF churn, both `manifest-check.sh` failures, and AC11's 8 · 2 · 2 · 11 · 2
  baseline.

  Three findings rev-2 did not predict, in descending order of consequence. **(a) U3 is no longer
  separable** — 2.2's check 3 rejects `project/in-flight`, `project/journal` and `project/IN-FLIGHT.md`
  outright, so a commit that flattens but leaves them reds; the rollout goes from four commits to
  three and U1+U2+U3 become one. This is F1 being overtaken: the owner ratified the retirement as a
  choice and the kit turned it into a requirement. **(b) check 3 evicts `project/MEMORY.md` and
  `project/README.md`**, reversing a §4 Migration row that said they stay — now F5. **(c)
  `merge-rows.py` arrives wireable but unwired** — now F6.

  One rev-1 rationale is corrected without changing its action: the six grandfathered builds are
  underivable because `SHIPPED` is not in the status vocabulary, not because they lack a header. Five
  of the six do carry one. The authored `status: CLOSED` was and remains right.

  Two further gaps found by an adversarial read of the kit source rather than by the dry run, both
  verified by measurement before being written here. **`memory/TEMPLATE-SPEC.md` is structurally
  wrong** — it puts `## 10. Reuse audit` outside the fenced skeleton where 2.2's template puts it
  inside, so copying the skeleton omits a section check 12 requires for every spec dated on or after
  2026-08-04; §4 Files touched now adds the replacement. **F4's follow-up is not mechanical** — it
  needs `extract.grammar_for(root)`, which the installed memory-recall kit does not have, so arming
  checks 13-16 is gated on a memory-recall re-pull.

  Method note for a later reader: rev-3's measurements come from four throwaway clones of `57fe074d`
  (migration, two atomicity probes, one separability probe) and a source read of the 2.2 kit run as a
  bounded five-lens fan-out plus synthesis. Where the two disagreed the clone won, and every claim
  imported from the read was re-verified against the files before it was written down.
- rev-4 · 2026-08-10 · **forks closed, no new measurement.** The owner ratified F3, F4, F5 and F6 in
  one pass, each at its stated recommendation. Nothing measured changed; this revision is decisions
  and their consequences only.

  **F5 → delete both, not relocate.** rev-3 recommended relocating `project/README.md` and
  `project/MEMORY.md` to `archive/`. Reading them reversed that recommendation before it was put to
  the owner: `MEMORY.md` is 48 B holding zero notes, `README.md` is 241 B of which two of three
  bullets describe machinery this unit removes, and nothing links to either. Check 3 is satisfied
  identically by a deletion, since it tests what remains. Consequences threaded through: the §4
  Migration row, the U1+U2+U3 work list, AC4 (which now also pins `archive/` to the shard alone), and
  AC11 — whose fifth grep target was that README, so the path leaves the list and its baseline drops
  from `8 · 2 · 2 · 11 · 2` to `8 · 2 · 2 · 11`. Files deleted goes 13 → 15.

  **F3 + F4 → one shared follow-up unit.** rev-3 found both need the memory-recall 1.0 → 1.1 re-pull
  for `grammar_for`, so they land together in a fixed order: re-pull, fix `DURABLE`, measure pins
  against the by-then-existing flat corpus, arm 13-16. U5 files one row for the pair.

  **F6 → inert, with a row.** `merge-rows.py` is copied in with the kit and wired by nobody; the row
  records that this is a decision, names the two missing prerequisites, and carries the marker-free
  failure mode so the row's purpose survives its author. U5 now files two backlog rows, not one.

  **F2 is NOT ratified** and §8 now says so. It was walked through and left standing at minimum churn
  without challenge. That is acceptance by default, and rounding it up to a ratification would put a
  decision on the record the owner never made.

## 10. Reuse audit

No `tools/codebase-map/reuse_lookup.py` pass is possible: this repo has not adopted codebase-map and
has no `.codebase-map.conf`, so there is no seam index to query. The reuse decision is therefore
argued from the kit surface directly, which is the whole of what this unit builds against.

**Nothing new is written.** Every mechanism this unit needs already ships in the kit it installs, and
the unit's discipline is to wire through them rather than reimplement:
`gen_build_index.py --write` renders the work-state index and `--check` gates it; check 5's existing
FAMILY-qualifier slot resolves the slug collision; `git mv` carries the rename similarity that AC3
asserts; `corpus_ids.py --measure` is the follow-up's pin source in F4. The one hand-authored
artifact is the ten READMEs' front matter, which is data, not a mechanism, and its values are
transcribed from the ledger shard rather than invented.

The seam deliberately NOT wired through is `memory-recall/extract.py`'s `DURABLE` pattern: F3 records
that the flatten leaves it selecting nothing and routes the repair to its own unit, so this unit
neither vendors a second copy of that grammar nor edits a declared fork mid-restructure.
