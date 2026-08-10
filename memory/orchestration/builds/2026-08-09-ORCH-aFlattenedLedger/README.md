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

The unit takes this repo's `memory/` tree from memory-tree kit 1.4 to kit **2.2**: the four
discipline directories collapse into one `memory/builds/<slug>/`, the discipline becomes a `streams`
field in each build's README front matter, and the authored per-node in-flight ledger is replaced by a
generated `LIVE.md` + `ledger/<month>.md` index. Upstream retired the sharded ledger as a product
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

**SPECCED at rev-4 (2026-08-10) — unparked, forks closed, ready to build.** The rev-2 hold was "wait
for kit 1.7 on coding-governance `main`". `main` is now at `e7ec336` carrying kit **2.2**, four minor
versions past the hold, so the prereq is discharged and overshot. Every rev-2 measurement was re-taken
against 2.2 in fresh clones of `57fe074d`, and §4 Rollout's re-measure table is now a results table.

Forks: F1 ratified at rev-2 (retire the ledger now — the action stands, its rationale moved, since
2.2's scaffolder has no ledger and check 3 rejects one, so U3 is in step with the kit rather than one
step ahead, and no longer optional). F3, F4, F5 and F6 ratified 2026-08-10, each at its
recommendation: the F3+F4 follow-up merges into ONE unit behind a memory-recall 1.0 → 1.1 re-pull;
F5 **deletes** `project/README.md` and `project/MEMORY.md` rather than archiving them; F6 takes
`merge-rows.py` inert with a backlog row. **F2 is not formally ratified** — it stands at minimum
churn, unchallenged, which §8 records as acceptance by default rather than a decision.

Three things rev-2 did not predict, worth knowing before opening the spec:

- **The rollout is three commits, not four.** 2.2's check 3 rejects the ledger paths outright, so a
  commit that flattens but leaves them reds. U1, U2 and U3 are now one commit.
- **`project/MEMORY.md` and `project/README.md` lose their home** — check 3 admits only `*.txt`
  waiver registries under `project/` now. That reverses a §4 Migration row. F5 deletes both: one is
  an empty index, the other describes machinery this unit removes, and nothing links to either.
- **`merge-rows.py` arrives with the kit**, a row-keyed merge driver for exactly the `DECISIONS.md`
  and `backlog/*.md` shapes this flatten creates, but wiring it needs files this repo lacks. F6 takes
  it inert with a backlog row.

Two more found by an adversarial read of the kit source rather than the dry run, both verified:
`memory/TEMPLATE-SPEC.md` puts `## 10. Reuse audit` OUTSIDE its fenced skeleton where 2.2's template
puts it inside, so copying the skeleton omits a section check 12 requires — U1 replaces the file. And
arming checks 13-16 needs `extract.grammar_for(root)`, which the installed memory-recall does not
export, so that follow-up is a second kit upgrade rather than a config edit.

Changed by measurement: the self-test is **120 assertions** (was 101), the generator writes **13
artifacts** (was 12), and the tree is **58 → 54 paths** (was 56 → 52 — the same −4 delta, re-based
onto a commit where this build's own folder exists as a 10th slug).

Nothing under `memory/` has been edited beyond this build folder, per the measure-then-spec-then-move
discipline.

<!-- gen:build-index -->
<!-- /gen:build-index -->
