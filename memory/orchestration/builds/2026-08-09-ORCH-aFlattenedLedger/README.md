---
slug: aFlattenedLedger
node: a
opened: 2026-08-09
streams: orchestration
roster: ORCH
ids: ORCH-aFlattenedLedger-1
---

# ORCH-aFlattenedLedger — flatten the memory tree, retire the in-flight ledger

Master spec: [ORCH-aFlattenedLedger-1](spec/2026-08-09-spec-aFlattenedLedger-1.md). It carries the
measured inventory, the per-file migration map, and the ratified forks. Read it before touching
`memory/`.

The unit takes this repo's `memory/` tree from memory-tree kit 1.4 to the flat kit: the four
discipline directories collapse into one `memory/builds/<slug>/`, the discipline becomes a `streams`
field in each build's README front matter, and the authored per-node in-flight ledger is replaced by a
generated `LIVE.md` + `ledger/<month>.md` index. Upstream is retiring the sharded ledger as a product
feature and this repo is the one adopter still carrying one.

## Why this is not a drop-in

| the problem | the answer |
|---|---|
| The in-flight ledger is this repo's ONLY work-state index today. | Its replacement is derived from build README front matter, which zero builds carry — so the front matter is authored before the ledger moves, from the ledger's own `streams` and `seq high-water` columns. |
| Six build folders share the slug `aUniformLattice`. | They are one build spanning three streams. They merge into one folder; the folder suffixes `-cmpleak`, `-rowlayer` and `-docs` were 1.4-era disambiguators, not part of the slug. |
| Two of those specs collide on one filename. | Check 5's grammar already admits an optional FAMILY qualifier: `<date>-<kind>-<FAMILY>-<slug>-<seq>.md`. |
| The kit bump and the flatten are each red on their own. | They land as ONE commit. Both orders were probed; each reds checks 3 and 9. |

## The naming rule inside `builds/aUniformLattice/`

Minimum churn, deliberately (spec §4 Alternatives rejected). `ANLZ` opened the build and owns 10 of
its 14 ids, so its seven specs keep unqualified names; the six recordings merged in from other folders
carry the FAMILY qualifier. The mixed naming is a decision, not an accident.

## Status

**BLOCKED — parked by the owner on 2026-08-09 until memory-tree kit 1.7 lands on coding-governance
`main`.** The target is 1.7, not 1.6. Measured 2026-08-09: gov `main` is at 1.6 and 1.7 exists on one
unmerged branch. Migrating to 1.6 now would pay the flatten's link-repair and front-matter cost twice.

F1 is **RESOLVED (owner, 2026-08-09): retire the ledger now, in U3** — and that decision survives the
retarget on measurement, because 1.7 still scaffolds the ledger too; upstream removes it at 1.8.
F2, F3 and F4 stand at the spec's recommendations and are not blocking.

Nothing under `memory/` has been edited beyond this build folder, per the measure-then-spec-then-move
discipline. The whole migration was first executed end-to-end in a throwaway clone, so the spec's gate
results, broken-link list and rename-similarity figure are observations rather than predictions —
taken at **1.6**. §4 Rollout carries the table splitting the findings that stand from the ones that
must be re-taken against 1.7 before the build starts.

<!-- gen:build-index -->
<!-- /gen:build-index -->
