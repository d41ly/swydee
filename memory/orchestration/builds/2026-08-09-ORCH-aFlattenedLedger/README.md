---
slug: aFlattenedLedger
node: a
opened: 2026-08-09
streams: orchestration
roster: ORCH
ids: ORCH-aFlattenedLedger-1
---

# ORCH-aFlattenedLedger — flatten the memory tree to kit 1.6, retire the in-flight ledger

Master spec: [ORCH-aFlattenedLedger-1](spec/2026-08-09-spec-aFlattenedLedger-1.md). It carries the
measured inventory, the per-file migration map, and the four forks awaiting an owner decision. Read it
before touching `memory/`.

The unit takes this repo's `memory/` tree from memory-tree kit 1.4 to 1.6. Kit 1.6 is FLAT: the four
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

Written before any edit to `memory/`, per the measure-then-spec-then-move discipline. The whole
migration was first executed end-to-end in a throwaway clone, so the spec's gate results, broken-link
list and rename-similarity figure are observations rather than predictions. Awaiting owner
ratification of forks F1-F4.

<!-- gen:build-index -->
<!-- /gen:build-index -->
