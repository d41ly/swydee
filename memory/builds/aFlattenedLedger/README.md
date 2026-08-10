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

**CLOSED at rev-5, built 2026-08-10.** Landed as three commits: `974545c` (U1+U2+U3 — kit 2.2, the
flatten, the ledger retired), `13a7dc4` (U4 — governing docs, gate leg, CRLF pins) and `3bc9b27`
(U5 — decision and backlog rows). Full bar green at each boundary.

The unit was retargeted twice and reviewed once before it built. rev-2 parked it on kit 1.7; rev-3
found `main` had reached 2.2 and re-measured everything against it; rev-4 closed the forks; rev-5
folded a Tier-2 review whose blocker was this spec's own instruction to run
`kit-dogfood-parity.test.sh --render` — a command that writes toward the kit and would have
silently reinstated the 1.4 templates over the 2.2 ones. See
[the review](reviews/2026-08-10-review-aFlattenedLedger-1.md).

Follow-ups live in `memory/backlog/ORCH.md` as `ORCH-aFlattenedLedger-4` (memory-recall re-pull →
`DURABLE` fix → arm checks 13-16) and `-5` (wire the row-keyed merge driver).

<!-- gen:build-index -->
**Build status:** CLOSED · 1 unit(s) · node a · opened 2026-08-09 · streams orchestration · ids ORCH-aFlattenedLedger-1

| Unit | Status | Rev | Last change |
|---|---|---|---|
| [ORCH-aFlattenedLedger-1 — flatten the memory tree to kit 2.2 and retire the in-flight ledger](spec/2026-08-09-spec-aFlattenedLedger-1.md) | CLOSED | rev-5 | 2026-08-10 |
<!-- /gen:build-index -->
