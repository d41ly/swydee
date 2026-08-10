# ANLZ-aUniformLattice-4 — P3: the uniform matrix and its reduce, ranks 1 and 2

**Status:** SPECCED · rev-2 · 2026-08-05 · node a · Tier-2 · base 31a51a95 · parent ANLZ-aUniformLattice-1 · review wf_581747b9-2c7

## 1. Goal

Emit `platforms[].metrics{}`, a total map over every observed `(platform, metricId)` pair, as a
SIBLING of the untouched `headline{}`. Every pair gets exactly one cell carrying either a value with
full provenance or a reason token explaining its absence. Nothing reads it yet.

## 2. Scope (IN)

- S1. `platforms[].metrics{}` keyed by metric id, a sibling of `headline{}`.
- S2. `Test-MatrixEligible($w)` — the single definition of a value-contributing widget.
- S3. `Get-MatrixContributions($dataWidgets)` — every candidate contribution, ranked.
- S4. `Reduce-MatrixCell($contributions, $periods)` — the total reduce, one cell per key.
- S5. Every observed `(platform, metricId)` gets exactly one cell, value or reason, never neither and
  never two.
- S6. A same-rank or off-basis disagreement records a `conflict` naming losing widget ids and NO
  values.
- S7. Rank 3 is stubbed: a would-be summed cell carries `reason='incomplete-rows'`.
- S8. A facts-schema shape gate in `Test-Analyze`, since `tools/gate-legs.json` has no contract leg.

## 3. Non-goals (OUT)

- `headline{}` is byte-identical. No existing facts key changes name, order or value.
- No finding rule reads the matrix. `GAP_NO_ACCOUNT_TOTAL` keeps its current input until P5.
- No closer change and no template change. P5 owns those.
- No rank-3 summing, ever. P6 is WONTDO: the live probe proved no row-count field exists.
- No second layer. P4 owns `valuesById`, `metricIds[]` and `rowKey` on breakdowns.
- No trend matrix.

## 4. Design

### Data model

`platforms[<providerId>].metrics[<metricId>]`. A platform object is built at TWO sites, `:775` and
`:782`, and a PowerShell ordered dictionary appends, so `metrics=[ordered]@{}` is SEEDED at both
construction sites and populated in place. The resulting key sequence is
`id, name, category, headline, hasComparison, metrics`, with `breakdowns` and `timeSeries` as optional
trailing keys appended later for platforms that have them. Note `hasComparison` sits between
`headline` and `metrics`; rev-1 asserted the wrong order. A cell:

| Field | Present when | Meaning |
|---|---|---|
| `id`, `metric` | always | metric id and display name |
| `current`, `previous`, `deltaPct` | value cells | raw numerics, exactly as `headline` carries them |
| `displayCurrent`, `displayPrevious`, `displayDelta` | value cells | `Format-Metric` / `Format-Delta` output |
| `type`, `direction`, `unit`, `currency` | always | as on a headline cell |
| `hasComparison` | value cells | per cell, for the closer's comparison guard |
| `scope` | value cells | `account` or `table-total:<dim>` |
| `method` | value cells | `kpi-widget`, `total-row` |
| `aggClass` | always | the P2 class |
| `basis` | always | the P2 `{unit, currencyCode, basisVersion}` tuple |
| `contributingWidgetIds[]` | always | D2-eligible widgets that offered a usable cell, winner first |
| `observedOnWidgetIds[]` | always | every widget that DECLARED this key, blended and hidden included |
| `coverageBasis` | always | `{providerFiltered, hiddenSectionExcluded}` |
| `conflict` | on disagreement | `{losingWidgetIds[], reason}`, never a losing value |
| `reason` | reason cells | one token, instead of every value field |
| `period` | always | `meta.currentPeriod` |

**The reason ladder is ORDERED, exhaustive, and evaluated top-down.** Review found the rev-1 token set
was neither total nor disjoint: three tokens claimed the same configuration with no precedence, two
were unreachable by construction, and at least three real configurations had no token at all. The
ladder below is the ratified replacement. The first matching rung wins, and the last rung cannot fail.

| # | Token | Produced by |
|---|---|---|
| 1 | `blended-undecomposable` | every widget declaring this key is blended |
| 2 | `hidden-section` | every declaring widget is eligible except that its section is hidden |
| 3 | `no-usable-cell` | a ranked widget won, but its total-row cell is absent or non-numeric |
| 4 | `not-summable` | no ranked contribution, and `aggClass` is `dedup-nonsummable` or `account-asis` |
| 5 | `incomplete-rows` | no ranked contribution, the declaring widget is dimensioned with no total row, and the metric is otherwise summable — the permanent rank-3 stub |
| 6 | `no-total` | no ranked contribution and no earlier rung applies (includes a zero-dimension widget that returned no rows at all) |
| 7 | `unclassified` | the total fallback; unreachable by construction, present so the reduce is provably total rather than total by inspection |

Two rev-1 tokens are DELETED. `manual-entry` was unreachable twice over: a `manualKpi` widget is not
in `$dataWidgets` (`Analyze-SwydoReport.ps1:739`), and more fundamentally it has no `metrics[]` array
at all, because the whole metrics/rows construction sits inside the `kind -eq 'data'` branch of
`Normalize-Widget`. It can never contribute a key to any key space, so no token can describe it.
`basis-conflict` was deleted because a basis disagreement produces a VALUE cell plus a `conflict`
record, never a valueless cell — see D3.

**D1 — the key space is `$observed`, not a new walk.** `Analyze-SwydoReport.ps1:809-828` already
builds the exact key space this matrix needs: every metric id seen on any data widget, attributed by
metric-id PREFIX so a blended widget contributes each metric to its true owner. P3 reuses that pass
rather than adding a second discovery. A key whose prefix is not a discovered platform is skipped,
exactly as `GAP_NO_ACCOUNT_TOTAL` skips it today at `:817`.

**D2 — eligibility, defined once.** A widget CONTRIBUTES A VALUE when all hold:

1. `kind -eq 'data'`, which is already the `$dataWidgets` filter at `Analyze-SwydoReport.ps1:739`.
2. `Test-Blended` is false. This binds at EVERY rank, per U6 D6, U7 R6 and U9 D1. A blended widget
   still walks the key space, so its metrics still get cells.
3. `sectionHidden` is not `$true`. Absent on a schemaVersion-2 document, which reads as visible.

There is deliberately no `-Platform` condition. The filter is applied at EXTRACTION time
(`Get-SwydoReport.ps1:995` drops non-matching widgets from the document) and `Analyze-SwydoReport.ps1`
has no `-Platform` parameter at all, so every widget the analyzer sees has already passed it.
`meta.providerFilter` survives only as the input to the `PROVIDER_FILTERED` finding. Rev-1 carried an
inert fourth condition and a `$providerFilter` parameter that could never exclude anything; both are
removed.

A `manualKpi` widget never contributes and never appears in the key space, because it carries no
`metrics[]` array at all.

**D3 — the reduce.** Group contributions by `(providerId, metricId)` — the cell key exactly, so two
groups can never compete for one slot.

- Rank 1: a zero-dimension widget with a total row. The predicate is byte-for-byte the `$isKpi` test
  the headline uses, PLUS the blended guard that sits above it at `:784`.
- Rank 2: a dimensioned widget with an explicit total row.
- Rank 3: refused. A dimensioned widget with NO total row offers no value.
- Within a rank, `documentIndex` ascending wins; a v2 document with no `documentIndex` falls back to
  array position, which is the same order.

**`providerId` in the group key is the METRIC's provider, never the widget's.** It is
`metrics[].providerId` when present (schemaVersion 3) and `($m.id -split ':')[0]` otherwise, so the
group key is the same function of the same data as the key space at `:864-871`. It is deliberately
NOT `Get-WidgetProvider $w`, which the headline uses: that function falls back to the FIRST metric's
prefix for a widget with no declared providers, so on a mixed-prefix widget the headline files every
metric under one provider while the key space files each under its own. The matrix follows the key
space, and D4 records the resulting divergence from the headline as intended rather than accidental.

**A contribution is metric-level, not widget-level.** A widget that DECLARES a metric but whose total
row has no cell for it, or whose cell is a non-numeric echo object, is not a contribution: the same
two guards the headline applies at `:794` and `:795` are part of the contribution test. Without this a
structurally-ranked widget could win and then supply nothing, which is the rung-3 `no-usable-cell`
case.

**The total-row cell is fetched by `$m.name`, byte-identically to `:793`.** P1 shipped
`metrics[].cellKey`, which is the correct key and fixes the duplicate-display-name wrong-value path,
but switching to it changes VALUES and therefore belongs to the phase that owns a flip set. P3
deliberately reproduces the headline's lookup so matrix and headline agree cell-for-cell, and inherits
its known defect knowingly. Recorded here so the later switch is a decision, not a discovery.

The winner supplies the value and its basis. `observedOnWidgetIds[]` lists every widget that DECLARED
the key, blended and hidden included, so a valueless cell still points at its cause.
`contributingWidgetIds[]` lists only the D2-eligible offerers, winner first. If a surviving
contribution disagrees on `basisVersion`, the cell keeps the winner's VALUE and gains
`conflict{losingWidgetIds, reason='basis-mismatch'}`. A same-rank second contribution records
`same-rank-disagreement`. A basis disagreement never produces a valueless cell. No losing display
string is ever echoed, per U9 D4/FP-3.

**D3b — key-space dedupe is case-insensitive.** `$observed` stores ids in a
`HashSet[string]`, which is case-SENSITIVE, while the emitted `metrics` map is a PowerShell ordered
dictionary, which is case-INsensitive. Two ids differing only in case would be two hashset entries and
one dictionary key. The matrix therefore dedupes the id list case-insensitively before building the
map, so the cell count and the key count cannot disagree.

**D4 — why the matrix is not just a fuller headline.** The headline stores at most one cell per
`(provider, metric)` and only from a total row; a metric observed only on a no-total table has no
entry at all. The matrix is TOTAL: it has an entry for every observed pair, and the absence of a
value is itself data with a stated reason. That is the property the rewire in P5 depends on.

### Inventory

Citations re-anchored against base 31a51a95; rev-1's were roughly 55 lines stale because P2 landed
above them. Reused unchanged: the `$observed` pass (`:864-871`) and its consumer (`:872-883`),
`$dataWidgets` (`:739`), the headline loop (`:768-825`), the no-total skip (`:786`), the cell lookup
(`:793`), the scalar guard (`:795`), `canonical{}` (`:820`), the platform construction sites (`:775`
and `:782`), `Test-Blended`, `Total-Row`, `Format-Metric`, `Format-Delta`, `Get-DeltaPct`,
`Metric-Type`, `Get-Direction`, and P2's `Get-AggregationClass` and `Get-CellBasis`.

### Migration

A schemaVersion-2 document produces a matrix: `sectionHidden` and `documentIndex` are absent and
degrade to visible and array-position. No key that exists today changes.

### Rollout

Dark. `platforms[].metrics` is additive and nothing reads it. `facts.meta.canonicalVersion` does NOT
move: the canonical algorithm producing `headline` is untouched, and moving the marker for an
additive sibling would misdescribe it.

### Files touched (estimate)

| File | Nature |
|---|---|
| `skill/scripts/Analyze-SwydoReport.ps1` | three pure functions, one emit site |
| `Test-Analyze.ps1` | matrix assertions plus the facts-schema shape gate |

### Alternatives rejected

- **Nesting the matrix inside `headline`.** Breaks `Analyze-SwydoTrend.ps1` gate 2c, which requires a
  MEASURED account value at `canonical.scope`.
- **A second discovery walk.** `$observed` already computes this key space.
- **Emitting only non-empty cells.** A sparse matrix is a fuller headline, not a uniform view, and
  P5's rewire would inherit the same blind spots.
- **Bumping `canonicalVersion`.** Additive sibling; the canonical algorithm did not change.

## 5. Production-readiness checklist

- security — no new I/O; the emitted cell carries no free text beyond ids already in facts.
- perf / scale — one pass over `$dataWidgets` per platform; the matrix is at most metrics x platforms.
- a11y — N/A — no UI.
- i18n — cells key on provider metric ids, never on display labels.
- error / empty / loading states — the reason vocabulary IS the empty state, and it is total.
- observability — `contributingWidgetIds` and `conflict` make every cell retraceable.
- risks — facts size growth; measured in AC10. A wrong `aggClass` is visible in-facts rather than
  silently changing a number, because nothing reads the matrix yet.
- testing + left-shift gates — S8's shape gate is the left-shift: nothing today stops a facts key
  being renamed out from under the closer.
- migration / rollback — additive; revert is a revert.
- user docs — none in P3; `skill/SKILL.md` gains the matrix in P5 when the model is told to read it.

## 6. Acceptance criteria

- AC1. `headline{}` is byte-identical before and after P3 on the same input, including key order and
  the `hasComparison` scalar.
- AC2. Every id in `$observed` for a discovered platform has exactly one cell; no cell exists for an
  unobserved id; no platform has two cells for one id.
- AC3. A zero-dimension KPI widget yields `method='kpi-widget'`, `scope='account'`, and the same
  `displayCurrent` the headline carries for that metric.
- AC4. A dimensioned widget with a total row yields `method='total-row'` and
  `scope='table-total:<dim>'`.
- AC5. A dimensioned SUMMABLE widget with NO total row yields `reason='incomplete-rows'`, no
  `current`, no `displayCurrent`, and no `method`.
- AC5b. Every rung of the reason ladder has a test naming the widget shape that produces it, and a
  cell can never carry both a value and a `reason`.
- AC5c. A widget that DECLARES a metric whose total-row cell is absent, and one whose cell is a
  non-numeric echo object, both yield `reason='no-usable-cell'` rather than a value or a crash.
- AC6. A metric observed ONLY on a blended widget yields `reason='blended-undecomposable'`, no blended
  widget appears in `contributingWidgetIds`, AND the blended widget IS listed in
  `observedOnWidgetIds`.
- AC7. Two zero-dimension widgets offering the same metric yield ONE cell, the document-order winner,
  plus `conflict.losingWidgetIds` naming the other and no losing value anywhere in the cell.
- AC8. Two contributions differing only in currency yield ONE cell that KEEPS the winner's value and
  carries `conflict.reason='basis-mismatch'`. It is never a valueless cell.
- AC9. A widget in a hidden section contributes no value; if it was the only offerer the cell carries
  `reason='hidden-section'`.
- AC9b. Two metric ids differing only in case yield exactly as many cells as dictionary keys.
- AC10. On the live QCU extraction the matrix has 42 cells across 2 platforms, of which 39 carry
  values and 3 carry `reason='no-usable-cell'`, equal to the measured headline coverage because that
  report has no blended widgets and no hidden sections; and the facts document serializes without
  hitting the `ConvertTo-Json -Depth` ceiling.

  MEASURED 2026-08-05, and the token is not the one rev-1 predicted. The three valueless cells are
  `google-adwords:ad_group`, `ad_network_type` and `campaign` — dimension-like ids DECLARED as metrics
  on widgets that do have a total row, whose total-row cell is a non-numeric echo object. They are
  rung 3, not rung 5. Rev-1 had no rung for them at all; the review's must-fix P3-02 added it, and
  the live run is what confirms the rung was necessary rather than theoretical. Headline and findings
  were verified byte-identical against the pre-P3 facts for the same input, and the facts document
  grew from 151,983 to 185,658 bytes.
- AC11. A schemaVersion-2 document still produces a matrix, with hidden-section and document-index
  degradation as specified.
- AC12. The facts-schema shape gate asserts the presence and order of `meta`, `platforms`, `findings`
  and of each platform's `id`, `name`, `category`, `headline`, `hasComparison`, `metrics`, for a
  platform discovered by EACH of the two construction sites, so a rename cannot land silently.
- AC13. `bash tools/run-gates.sh` green; `Test-Analyze` additive, every other suite unchanged.

## 7. Gates

`bash tools/run-gates.sh` — the whole standing bar, plus S8's new shape assertions inside
`Test-Analyze`.

## 8. Open questions

none — the parent's F1 and F2 resolutions and P2's ratified class ladder cover this phase.

## 9. Revision log

- rev-1 · 2026-08-05 · initial sub-spec derived from ANLZ-aUniformLattice-1 P3 (S18-S23), with rank 3
  stubbed per the master spec rev-4 WONTDO.
- rev-2 · 2026-08-05 · folded adversarial review wf_581747b9-2c7 (3 lenses, 7 batched skeptics, 10
  agents; 32 raw findings, 24 survived, 3 must-fix). The reason vocabulary was neither total nor
  disjoint and is replaced by an ordered seven-rung ladder with a provable fallback; `manual-entry`
  and `basis-conflict` are deleted as unreachable, the first because a manualKpi widget has no
  `metrics[]` array at all. A basis disagreement now unambiguously yields a VALUE cell plus a
  `conflict`, resolving a flat contradiction between the old token table and AC8. A contribution
  became metric-level, so a widget that ranks structurally but supplies no usable cell can no longer
  win with nothing. The group key's `providerId` is pinned to the METRIC's provider, and the
  divergence from the headline's widget-level attribution is now deliberate and recorded. The
  total-row lookup is pinned to `$m.name` so matrix and headline agree, with the switch to P1's
  `cellKey` explicitly deferred to the phase that owns a flip set. D2's `-Platform` condition was
  inert (the filter runs at extraction) and is removed with its parameter. Key order corrected:
  `hasComparison` sits between `headline` and `metrics`, and `metrics` is seeded at BOTH platform
  construction sites. Key-space dedupe is case-insensitive to match the ordered dictionary. All
  citations re-anchored.

## 10. Reuse audit

None — codebase-map is not adopted; audit by reading source. The matrix's key space is the `$observed`
pass at `Analyze-SwydoReport.ps1:864-871`, reused rather than re-walked; its provenance block extends
the shipped `canonical{}` at `:820` from one widget to N; ranking reuses the headline's own `$isKpi`
predicate and `Total-Row`; the contribution guards are the headline's own at `:794-795`; formatting
reuses `Format-Metric` and `Format-Delta`; class and basis come from P2's `Get-AggregationClass` and
`Get-CellBasis`. No predicate is duplicated and no new file is created.
