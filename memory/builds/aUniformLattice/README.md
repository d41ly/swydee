---
slug: aUniformLattice
node: a
opened: 2026-08-04
streams: analysis+extraction+orchestration
roster: ANLZ+EXTR+ORCH
ids: ANLZ-aUniformLattice-1/-10 + EXTR-aUniformLattice-1 + ORCH-aUniformLattice-1/-3
---
# ANLZ-aUniformLattice — layered uniform per-platform metric view

Master spec: [ANLZ-aUniformLattice-1](spec/2026-08-04-spec-aUniformLattice-1.md). It answers the two
owner questions, ratifies the design, and records the resolved forks F1 and F2. Read it before any
sub-spec.

The program replaces the sparse `platforms[].headline{}` — which is populated only from widgets that
happen to carry a total row — with a computed `platforms[].metrics{}` matrix covering every metric of
every included widget, plus an addressable per-row second layer, and rewires the finding rules onto
it.

## Phases and sub-specs

One unit per phase, per F1. Each sub-spec is adversarially reviewed before its code is written.

| Phase | Sub-spec | What it does | Waiver? |
|---|---|---|---|
| P1 | [-2](spec/2026-08-04-spec-aUniformLattice-2.md) | extractor schema v3: identity and completeness keys | no, dark |
| P2 | [-3](spec/2026-08-04-spec-aUniformLattice-3.md) | declared aggregation semantics and the basis hash | no, dark |
| P3 | [-4](spec/2026-08-04-spec-aUniformLattice-4.md) | the matrix and its reduce function, ranks 1 and 2 | no, dark |
| P4 | [-5](spec/2026-08-04-spec-aUniformLattice-5.md) | the addressable second layer | no, dark |
| P5 | [-6](spec/2026-08-04-spec-aUniformLattice-6.md) | rewire, closer split index, forced disclosure | YES |
| P6 | WONTDO | rank-3 summing | refused |
| — | [-8](spec/2026-08-05-spec-aUniformLattice-8.md) | lean facts: valuesById collisions-only, -37% | YES |

P6 is CLOSED. The S14 field probe ran against a live report on 2026-08-05 and proved Swydo exposes no
row-set completeness signal: `serverRowTotal`, `data.totalCount` and `rows[].isTotalOfShownRows` are
all absent. A summed cell can therefore never satisfy U6 D5's affirmatively-proven bar, so rank-3
summing is refused rather than deferred, and `reason='incomplete-rows'` is the permanent answer.

The same probe proved `widget.dateRange` DOES exist. P1 extracts it, which makes per-cell period
homogeneity provable for the first time.

## Reviews

Every adversarial pass lands in [reviews/](reviews/) under the recording naming the hygiene gate
requires. The master spec's own review is
[-1](reviews/2026-08-04-review-aUniformLattice-1.md) with its synthesis in
[-2](reviews/2026-08-04-review-aUniformLattice-2.md).

## The rule that shapes every phase

`platforms[].headline{}` stays byte-identical throughout. The matrix is a SIBLING. That keeps
`Analyze-SwydoTrend.ps1` gate 2c and the existing closer index working untouched, and confines the
waiver to P5.

<!-- gen:build-index -->
**Build status:** INPROGRESS · 13 unit(s) · node a · opened 2026-08-04 · streams analysis+extraction+orchestration · ids ANLZ-aUniformLattice-1/-10 + EXTR-aUniformLattice-1 + ORCH-aUniformLattice-1/-3

| Unit | Status | Rev | Last change |
|---|---|---|---|
| [ANLZ-aUniformLattice-1 — layered uniform per-platform metric view](spec/2026-08-04-spec-aUniformLattice-1.md) | INPROGRESS | rev-4 | 2026-08-05 |
| [ANLZ-aUniformLattice-2 — P1: extractor schema v3, identity and completeness keys](spec/2026-08-04-spec-aUniformLattice-2.md) | SPECCED | rev-2 | 2026-08-04 |
| [ANLZ-aUniformLattice-3 — P2: declared aggregation semantics and one shared basis hash](spec/2026-08-04-spec-aUniformLattice-3.md) | SPECCED | rev-2 | 2026-08-05 |
| [ANLZ-aUniformLattice-4 — P3: the uniform matrix and its reduce, ranks 1 and 2](spec/2026-08-04-spec-aUniformLattice-4.md) | SPECCED | rev-2 | 2026-08-05 |
| [ANLZ-aUniformLattice-5 — P4: make the per-row second layer addressable](spec/2026-08-04-spec-aUniformLattice-5.md) | SPECCED | rev-2 | 2026-08-05 |
| [ANLZ-aUniformLattice-6 — P5: rewire coverage onto the matrix, and disclose it](spec/2026-08-04-spec-aUniformLattice-6.md) | SPECCED | rev-2 | 2026-08-05 |
| [ANLZ-aUniformLattice-10 — close the compare-suppression leak in the discrepancy layer](spec/2026-08-05-spec-ANLZ-aUniformLattice-10.md) | CLOSED | rev-1 | 2026-08-05 |
| [ANLZ-aUniformLattice-9 — the row layer answers to the computed platform total](spec/2026-08-05-spec-ANLZ-aUniformLattice-9.md) | CLOSED | rev-3 | 2026-08-05 |
| [EXTR-aUniformLattice-1 — prove the compare window instead of inheriting it](spec/2026-08-05-spec-EXTR-aUniformLattice-1.md) | CLOSED | rev-3 | 2026-08-05 |
| [ORCH-aUniformLattice-1 — the executables leave the repo root](spec/2026-08-05-spec-ORCH-aUniformLattice-1.md) | CLOSED | rev-1 | 2026-08-05 |
| [ORCH-aUniformLattice-2 — SKILL.md gets a parameters reference](spec/2026-08-05-spec-ORCH-aUniformLattice-2.md) | CLOSED | rev-2 | 2026-08-05 |
| [ORCH-aUniformLattice-3 — SKILL.md states the comparison contract](spec/2026-08-05-spec-ORCH-aUniformLattice-3.md) | CLOSED | rev-2 | 2026-08-05 |
| [ANLZ-aUniformLattice-8 — lean facts: stop duplicating every breakdown cell](spec/2026-08-05-spec-aUniformLattice-8.md) | SPECCED | rev-2 | 2026-08-05 |
<!-- /gen:build-index -->
