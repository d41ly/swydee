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
