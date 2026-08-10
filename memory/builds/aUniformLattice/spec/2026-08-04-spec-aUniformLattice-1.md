# ANLZ-aUniformLattice-1 — layered uniform per-platform metric view

**Status:** INPROGRESS · rev-4 · 2026-08-05 · node a · Tier-2 · base 8e1e5294 · review wf_0925fd2f-2cd · ratified 2026-08-04

## 1. Goal

Replace the sparse per-platform headline with a computed, uniform `(platform, metric)` matrix that
covers every metric of every included widget, backed by an addressable per-row second layer, and
rewire the finding rules and the model-facing report surface onto it. The answer to "what would it
take" is a five-phase program, not one unit, because the matrix cannot be made sound until the
extractor emits identity and completeness keys it currently fetches and discards.

## 2. Scope (IN)

Five buildable phases, one unit each per F1 (a sixth was specified and is now WONTDO) — its own branch, spec, adversarial review and merge. Phase order is
a dependency order, not a priority order: P2 cannot be verified without P1, and P4 is unsound
without P3. P6 was gated on an external prereq that has now been measured and refused; see F2.

**P1 — extractor schema v3: identity and completeness keys (S1-S14).**

Every P1 key is strictly additive. No existing key changes name, shape or value. This constraint is
load-bearing and was violated by rev-1; see §4 "Migration".

- S1. Add `widget.dimensionRefs[]`, an array of `{name, id}` in the same order as the existing
  `widget.dimensions[]`. The ids are already collected at `Get-SwydoReport.ps1:513` and flattened
  away at `:515`. `widget.dimensions[]` stays a string array, byte-for-byte.
- S2. Add `widget.metrics[].cellKey`, the exact `Uniq-Key` string written into `rows[].metrics` at
  `Get-SwydoReport.ps1:525`. See §4 "Data model" for why this is a correctness fix.
- S3. Add `widget.metrics[].providerId`, the metric id prefix. Three analyzer passes re-derive it
  today at `Analyze-SwydoReport.ps1:187`, `:812` and `:852`.
- S4. Add `widget.providers[].dataSourceId` and `widget.providers[].partId`. Both are already
  requested at `Get-SwydoReport.ps1:378` and dropped by `Normalize-Widget` at `:500`.
- S5. Add `widget.pagesComplete` (bool) plus `widget.pageInfo{hasNextPage, endCursor, pagesFetched}`.
  Named for what it proves: every page the API offered was fetched. It is NOT a row-set completeness
  proof; see rank-3 precondition 1.
- S6. Add `widget.sectionHidden`. `sections{id name isHidden}` is already requested at
  `Get-SwydoReport.ps1:756` and `isHidden` is discarded at `:932`.
- S7. Add `widget.widgetTemplateId` and `widget.widgetTemplateLinked`, already fetched at `:378`.
- S8. Add `widget.hasTotalRow` and `widget.rowKindCounts{data, subtotal, total}`.
- S9. Add `widget.currencyBasis` (`row-meta` or `absent`) and `widget.currencyCodes[]`, the distinct
  set seen across rows, rather than only the first-row scavenge at `:510-511`.
- S10. Add `widget.documentIndex`, the widget's ordinal in `widgets[]`.
- S11. Add `rows[].rowKey`, built as the row's document ordinal joined with its full dimension tuple.
  The ordinal is free inside the edge loop at `Get-SwydoReport.ps1:519`, and including it guarantees
  within-widget uniqueness by construction. A label-only key would collide, because `Row-Label`'s
  fallback is shared across rows.
- S12. Bump `schemaVersion` 2 to 3 AND widen every consumer that gates on the literal. Three exist:
  `Analyze-SwydoReport.ps1:678` throws, `ConvertTo-SwydoTrendFacts.ps1:75` throws, and
  `skill/SKILL.md:31` tells the model to stop. All three accept `2` or `3` after this item, with the
  v2 degradation of §4 "Migration". Without S12, P1 dead-ends every analyze run while the suites stay
  green, because `Test-Analyze.ps1:324` pins its fixture at 2.
- S13. Extract the extraction-meta assembly into pure functions above the `-DefineOnly` return, and
  give `Normalize-Widget` an explicit `($wmeta, $obj, $outcome, $index)` signature. S5, S10 and the
  S14 probe otherwise land in top-level run-body code that no suite can execute, which would make
  AC1 unobservable by any gate in this repo.
- S14. Add `meta.fieldProbe`, the recorded result of one `Invoke-GQL -NoRetry` per c3 candidate field
  against a known widget id, capturing the error text. This replaces rev-1's JWT scope decode, which
  cannot answer the question: a scope claim enumerates authorization scopes, not GraphQL fields.
  **S14 is the F2 gate for the whole program.** It requires a live share link, which this checkout
  does not have because `skill/archive` is gitignored and absent, so it is an EXTERNAL prereq. Its
  recorded output decides whether P6 is ever built. S1-S13 do not depend on it and are not blocked by
  it; P1 may land with `meta.fieldProbe` absent and the probe run later against the same report.

**P2 — declared aggregation semantics (S15-S17).**

- S15. Add `Get-AggregationClass($metricId, $unit)` returning exactly one of `sum`,
  `ratio-recompute`, `dedup-nonsummable`, `account-asis`, `unknown`. It composes the existing pure
  helpers and adds no new regex table.
- S16. Move `Get-BasisVersion` into `Analyze-SwydoReport.ps1` and delete the copy in
  `Update-SwydoLedger.ps1`, which already dot-sources the analyzer at `:36`. Keep its shipped
  three-argument signature including the metric id. U6's deferred-work contract makes a single shared
  define-only helper a named precondition for bringing `basisVersion` into report facts, so a second
  copy is not acceptable.
- S17. Leave `Test-Additive` and `Test-Summable` untouched and still divergent. U7 R4 pins that
  divergence with a regression test; `Get-AggregationClass` consumes them, it does not unify them.

**P3 — the matrix and its reduce function, ranks 1 and 2 only (S18-S23).**

Per F2, rank-3 summing is NOT in P3. The matrix P3 ships is uniform in its KEY SPACE: every observed
`(platform, metricId)` gets a cell, and a cell that would need a sum carries
`reason='incomplete-rows'` instead of a value. That delivers the complete per-platform inventory and
an honest gap statement without publishing a number whose row set cannot be proven whole.

- S18. Add `platforms[].metrics{}` as a SIBLING of `platforms[].headline{}`. `headline{}` stays
  byte-identical, including its `hasComparison` scalar key.
- S19. Implement the reduce function of §4 "Data model" as a total function over the contribution
  set, ranked by structure only, grouped by `(providerId, metricId)`, with rank 3 stubbed to the
  `incomplete-rows` reason token. The rank ladder and every rank-3 precondition are specified now so
  P6 is a fill-in rather than a redesign, but P3 emits no summed value.
- S20. Every observed `(platform, metricId)` gets exactly one cell. A cell carries a value with its
  numerics and display strings, or a reason token, never nothing and never two cells.
- S21. Every cell carries its `method`, `aggClass`, `scope`, `basis`, `contributingWidgetIds[]` and
  `coverageBasis`.
- S22. A disagreement among surviving contributions produces the ranked winner AND a `conflict`
  record naming the losing widget ids, their `basisVersion`, and no values. The reduce never silently
  drops a contribution.
- S23. Compute the matrix from `$dataWidgets` only, never from the facts-level `breakdowns` block,
  which is capped at 20 rows at `Analyze-SwydoReport.ps1:386`. Add the facts-schema shape gate of §7.

**P4 — the addressable second layer (S24-S26).**

- S24. Add `breakdowns[].rows[].valuesById`, keyed by metric id, alongside the existing
  display-name-keyed `values`, and add `breakdowns[].metricIds[]` alongside `metricNames[]`. Both are
  additive; re-keying `values` in place would change default output and cost P4 its dark status.
- S25. Emit `breakdowns[].rows[].rowKey` from S11.
- S26. A matrix cell whose method is `summed-rows` records the `rowKey` set it summed, so the sum is
  retraceable without the reader performing arithmetic.

**P5 — rewire and disclose (S27-S33).**

- S27. Repoint the finding rules of §4 "Inventory" from `headline` to `metrics`, gated by method. The
  four value-reading rules read cells whose `method` is `kpi-widget`, `total-row` or
  `operator-entered`, and skip any cell carrying a `reason` token. They never republish a
  `summed-rows` or `ratio-recompute` value inside their statements.
- S28. Redefine `GAP_NO_ACCOUNT_TOTAL`'s input from observed-minus-headline to
  observed-minus-matrix-coverage, where a `reason`-bearing cell does NOT count as coverage. Keep U6
  D11's shape, severity and 20-item cap. Without the reason-cell exclusion the redefinition silently
  retires the rule for blended-only providers.
- S29. Extend `Build-FactIndex` in `Test-ReportNumbers.ps1` with a SPLIT index. Cells whose `method`
  is `kpi-widget`, `total-row` or `operator-entered` join the per-platform candidate bag as measured
  values. Cells whose `method` is `summed-rows` or `ratio-recompute` join `byFid` under their
  disclosure finding's fid ONLY, never the platform bag and never global. The existing line-scope rule
  then enforces AC11 for free.
- S30. Add a third forcing class to the closer's surfacing gate, `requiresProvenanceAnchor -eq $true`,
  with no clause obligation of its own. The closer today has exactly two levers and both are ruled
  out: severity at or above `major` is barred by U7 R7's downgrade discipline, and
  `requiresDownstreamData` is barred by U10 D8's ban on forcing a semantically wrong sentence.
  Without S30 the phrase "every rank-3 cell is force-surfaced" names no mechanism.
- S31. Add a disclosure-prose check alongside S30. The anchor S32 relies on is stripped from the
  delivered file, so an anchor-only contract lets a tool-computed sum reach the client unmarked.
- S32. Amend `skill/report-template.md` at every binding surface, not only hard rule 2: the opening
  verbatim whitelist must name `platforms[].metrics[].displayCurrent/displayPrevious/displayDelta`,
  hard rule 1's phrasing template must carry the scope-dependent wording, and hard rule 2 gains the
  `summed-rows` exception conditional on the disclosure fid being anchored on the same line.
- S33. Bump `meta.canonicalVersion` 2 to 3, disclose the enumerated flip set in facts, and produce
  the measured flip set of §4 "Rollout" before the waiver is approved.

**P6 — rank-3 summing. WONTDO, closed 2026-08-05 by S14's probe.**

The probe proved `widget.serverRowTotal` does not exist, and neither does `data.totalCount` nor any
other row-count field. Rank-3 precondition 2 therefore has no signal that could ever satisfy it, and
U6 D5's bar — completeness affirmatively proven, never merely un-warned — cannot be met for a summed
cell. Rank 3 is not deferred; it is refused. `reason='incomplete-rows'` on a would-be summed cell is
the permanent, honest answer, and S30's forcing class plus S31's prose check ship in P5 with no
producer, ready if Swydo ever adds the field.

## 3. Non-goals (OUT)

- Trend facts get no matrix. `Analyze-SwydoTrend.ps1` builds its own independent
  `platforms[]`/`headline{}` of the same documented shape, and giving it a matrix is a second waiver
  with its own suite. The resulting asymmetry must be named in the template so the model does not
  look for a matrix that is not there. Follow-up: a TREND-family unit.
- No cross-platform metric taxonomy. Mapping `google-adwords:cost` and `facebook-ads:spend` onto one
  shared concept is a separate unit, and it inherits the direction inconsistency recorded in §5.
- No cross-scope reconciliation. U6's WONTFIX residual stands: a legitimate account KPI and a
  filtered table total are both surfaced with honest scope, and the matrix does not adjudicate
  between them by value.
- No remainder arithmetic anywhere, on either layer.
- No migration or backfill of archived facts. U9 D10/D11 stands.
- No renumbering of the frozen `U<seq>` id era. Cite verbatim.
- No new GraphQL round trip for a DATA field. S14 is a deliberate probe whose purpose is to record
  which fields exist; it fetches no report data.
- No repointing of `DISC_CROSS_WIDGET`. See §4 "Inventory".

## 4. Design

### Data model

The matrix is `platforms[<providerId>].metrics[<metricId>]`, a sibling of `headline`. The sibling
placement keeps `headline` byte-identical, which means `Analyze-SwydoTrend.ps1:276-282` gate 2c never
sees a computed cell, the existing closer index keeps working, and the U9 waiver surface shrinks to
the rewired finding rules plus additive keys. Nesting the matrix inside `headline` would put a
computed value where U7b MF-3 requires a measured account value.

| Field | Meaning |
|---|---|
| `id`, `metric` | metric id (the matrix key) and display name |
| `current`, `previous`, `deltaPct` | raw numerics; present only when the cell has a value |
| `displayCurrent`, `displayPrevious`, `displayDelta` | pre-formatted; named to match the shipped headline cell so a repointed rule reads the same field |
| `type`, `direction`, `unit`, `currency` | as on a headline cell |
| `hasComparison` | per cell, feeding the closer's comparison guard |
| `scope` | `account`, `table-total:<dim>`, `summed-rows:<dim>`, or `manual-entry` |
| `method` | `kpi-widget`, `total-row`, `summed-rows`, `ratio-recompute`, `operator-entered` |
| `aggClass` | the S15 class, so the template can key its wording on it |
| `basis` | `{unit, currencyCode, basisVersion}` |
| `contributingWidgetIds[]` | every widget that fed the cell, not only the winner |
| `contributingRowKeys[]` | present only when `method` is `summed-rows` |
| `coverageBasis` | what "included" meant for THIS cell: provider filter state and section visibility |
| `conflict` | losing widget ids and their `basisVersion`; never a losing display string |
| `reason` | present INSTEAD of every value and display field |

Reason tokens: `no-total`, `not-summable`, `basis-conflict`, `incomplete-rows`, `no-summable-rows`,
`blended-undecomposable`, `unit-unconfirmed`, `manual-entry`.

The raw numerics are required, not optional. The rules S27 repoints read `current`, `previous` and
`deltaPct`; a cell exposing only display strings would resolve those to `$null` silently under
PowerShell and kill two force-surfaced `major` rules without any error. U6 D8's ban on a raw `value`
key applied to the `canonical{}` PROVENANCE record, not to a headline-equivalent cell, and the
shipped headline carries all three at `Analyze-SwydoReport.ps1:760`.

**The reduce function.** Group contributions by `(providerId, metricId)` — the cell key exactly, so
no two groups can compete for one slot. Rank by structure only, never by value; U9 FP-1 rejected
value adjudication because it would make the winner depend on data that changes between periods.

- Rank 1: a zero-dimension KPI card, using U9 D1's FULL gate set. The gate set is not the bare
  `$isKpi` expression at `Analyze-SwydoReport.ps1:734`: the blended guard sits five lines above it at
  `:729`, so copying the predicate does not copy the guard.
- Rank 2: an explicit total row on a dimensioned widget.
- Rank 3: a sum over detail rows, under the preconditions below. DEFERRED to P6 per F2. P3 stubs it
  to `reason='incomplete-rows'`, so the ladder is complete in specification and inert in behaviour.
- Within a rank, document order wins, using S10's `documentIndex` so the winner is recordable rather
  than an implicit array position.

The ranked winner supplies the value and its basis becomes the cell's `basis`. Every surviving
contribution on a different `basisVersion` becomes a `conflict` entry. This case is live in the
shipped suite, not hypothetical: fixture `u5c` at `Test-Analyze.ps1:538-541` carries a EUR
dimensioned table total and a USD zero-dimension KPI for one metric in one report, and U6:242 records
same-metric-two-currencies as a standing WONTFIX.

**Rank-3 preconditions.** These are the P6 contract, specified here so P6 is a fill-in rather than a
redesign. U6 D5 deferred synthesis in full and set a hard bar: synthesis may proceed only when
completeness is affirmatively proven, never merely because no warning said otherwise. F2 keeps that
bar rather than working around it. All of the following must hold; a failure emits the named reason
token and no value.

1. `widget.pagesComplete` is `$true`. This proves pagination was exhausted, nothing more.
2. An affirmative ROW-SET signal: `serverRowTotal` equal to the returned row count, or an equivalent
   no-row-limit flag recovered from the retained `raw` blob. A widget configured to show its top N
   rows returns N edges with `hasNextPage` false and reports pages-complete, so precondition 1 alone
   would publish an under-counted total whose disclosure would read "tool-computed" when the real
   defect is "rows are missing". `serverRowTotal` is UNKNOWN until S14 answers, and F2 resolved that
   rank 3 waits for that answer rather than shipping a shown-rows sum. Failure token:
   `incomplete-rows`.
3. `Test-Summable` on the metric id, and `aggClass` is `sum`.
4. Exactly one dimension AND its NAME satisfies `Test-PartitionDim` at
   `Analyze-SwydoReport.ps1:484-488`. The dimension id from S1 is provenance only. An id changes
   which string is matched, not what the match proves, and no id vocabulary has ever been observed
   because `:515` has always discarded ids. Failure token: `not-summable`.
5. Basis is homogeneous across the summed rows. Failure token: `basis-conflict`.
6. The row set is `kind -eq 'data'` AND NOT `Test-GroupRow`, with `kind -eq 'subtotal'` excluded
   EXPLICITLY. Subtotal rows are extracted at `Get-SwydoReport.ps1:521` and read by nothing today, so
   the exclusion is currently an accident of five filter shapes rather than a reviewable rule.
7. The FILTERED row set is non-empty, evaluated after precondition 6. A widget whose data rows are
   all group rows or all subtotals would otherwise sum to a fabricated zero. Failure token:
   `no-summable-rows`.
8. Every summed row carries a numeric compare cell, or the cell is emitted with `hasComparison` false
   and no `displayPrevious`/`displayDelta`. Without this a 10-row current sum divides against a 7-row
   previous sum and publishes a fabricated delta.

A `ratio-recompute` cell is NOT a rank-3 sum and carries its own preconditions: both components must
resolve to cells sharing the winner's `basisVersion`, `scope` and `method`; component selection uses
`Get-RatioSpec`'s numerator and denominator patterns with the role-qualifier rule; a zero or absent
denominator skips to `not-summable`. Rev-1 authorized ratio recomposition with no guards at all,
which would have permitted a numerator and denominator from different widgets, periods and scopes.

**Every rank-3 cell is force-surfaced** through S30's new forcing class plus S31's prose check. U6's
deferred-work contract states that a tool-computed total must never be presentable as if the platform
reported it, and an anchor alone does not achieve that because the closer strips anchors from the
delivered file.

**"Included" is defined once.** A widget contributes a VALUE at any rank when `kind -eq 'data'`, AND
`Test-Blended` is false, AND its section is not hidden (S6), AND either no `-Platform` filter was
applied or its provider is in the filter. The blended exclusion binds at every rank, per U6 D6, U7 R6
and U9 D1; rev-1 excluded blended widgets only from rank 3, which would have let a joined widget's
total become a platform's account cell. A blended widget still walks the `$observed` key space at
`Analyze-SwydoReport.ps1:809-828`, so it registers platforms and metric ids, and a `(platform,
metricId)` observed only on blended widgets gets a cell with `reason='blended-undecomposable'`.

A `manualKpi` widget does NOT contribute, because S23 computes from `$dataWidgets` and `manualKpi`
widgets are excluded before analysis at `Analyze-SwydoReport.ps1:684`. The affected `(platform,
metricId)` gets a cell with `reason='manual-entry'` and no value. This keeps operator-typed numbers
out of the closer's candidate bag, which they have never entered. F4 in §8 asks whether the owner
wants the stronger version.

`coverageBasis` stamps the filter and visibility answer on every cell, because a matrix computed
under a `-Platform` filtered pull is not account-level for the report's own claim, and `SKILL.md:81`
already forces a `PROVIDER_FILTERED` gap for exactly that reason.

**Why S2 is a correctness fix.** The analyzer fetches a total-row cell by metric DISPLAY NAME at
`Analyze-SwydoReport.ps1:738`, while the extractor uniquifies colliding names into `name [id]` at
`Get-SwydoReport.ps1:358-364`. When one widget carries two metrics with the same display name, the
second metric's lookup returns the FIRST metric's cell. This was verified by execution under
PowerShell 5.1 during review: both lookups returned `current=100`. The result is a headline cell
keyed by metric 2's id, carrying metric 1's value, formatted with metric 2's unit and type. It passes
the scalar guard. It is a wrong-number path in shipped code, not a dropped-metric path. `Uniq-Key`
also falls back to `col<idx>` on an empty metric name, giving a second silent path. Repairing the
lookups changes headline VALUES, so the repair is named in S27's phase and enters S33's flip set; it
is not free under S18's byte-identity claim.

### Inventory

Finding rules that read `platforms[].headline` and their disposition in P5.

| Rule | Site | Severity | Disposition |
|---|---|---|---|
| `GAP_UNIT_UNCONFIRMED` | `Analyze-SwydoReport.ps1:895-910` | major | repointed, method-gated, skips reason cells |
| `ANOM_BUDGET_CONSTRAINED` | `:912-930` | major | repointed, method-gated, skips reason cells |
| WIN / LOSS | `:904-907` | none | repointed, method-gated; the verdict set grows |
| `GAP_NO_ACCOUNT_TOTAL` | `:806-828` | info | input redefined per S28 |
| `GAP_HEADLINE_SOURCE_CHANGED` | `:829-844` | info | unchanged; keyed on the frozen `headline` |
| `DISC_CROSS_WIDGET` | `:923-950` | major | NOT repointed |

`DISC_CROSS_WIDGET` keeps reading widgets directly. Its correctness argument is its dimension
signature key: it compares only widgets with identical sorted dimension sets. Repointing it at a
matrix that has already reduced those widgets to one cell would destroy the comparison it exists to
make.

Recommendations are NOT rules in code. They are model-authored from the facts document per
`skill/SKILL.md`. Rewiring recommendations means changing what the model reads, which is the matrix
plus S32's template amendment, so the deliverable is half PowerShell and half prompt contract.

Widget data keys, answering the owner's second question. It splits in two, because an extractor key
bumps `schemaVersion` and touches three consumers while an analyzer key rides the waiver.

**(c1) extractor keys — all already fetched or derivable from the retained `raw` blob.** S1-S14. No
new data field is requested.

**(c2) analyzer cell fields.** The cell table above.

**(c3) MEASURED — S14's probe ran against a live report on 2026-08-05 and settled every candidate.**
GraphQL introspection is disabled, so each field was probed by name; an absent field answers HTTP 400
`GRAPHQL_VALIDATION_FAILED` naming it, a present field answers 200.

| Candidate key | Verdict | Consequence |
|---|---|---|
| `widget.dateRange` | **EXISTS** | period homogeneity becomes provable; extracted by P1 S15 |
| `metrics[].aggregation` | absent | `Get-AggregationClass` stays a derivation, permanently |
| `widget.filters` | absent | the filtered-KPI ambiguity is PERMANENT, not a gap to close |
| `widget.segments` | absent | same |
| `dims[].isPartition` | absent | `Test-PartitionDim`'s English word list stays the authority |
| `widget.serverRowTotal` | absent | **no row-set completeness signal exists; P6 is WONTDO** |
| `data.totalCount` | absent | the Relay connection exposes no count either |
| `rows[].isTotalOfShownRows` | absent | node keys are `cells, compareCells, id, isTotals, meta, rows` |

Two results are load-bearing. `serverRowTotal` does not exist and neither does any equivalent, so
rank-3 precondition 2 can never be satisfied and F2's WONTDO branch is the one that fires: the
`incomplete-rows` stub is the permanent answer, not a temporary one.

`widget.dateRange` DOES exist, which partially closes the residual U6:243, U7 R17 and U9 FP-1 all
cite. The period half is now provable. The filter half is not: `filters` and `segments` are both
absent, so a filtered KPI card stays indistinguishable from an account-wide one for good. That
residual should stop being described as undetectable-from-schema-v2 and start being described as
undetectable, full stop.

### Migration

`schemaVersion` 2 to 3 at P1, and `meta.canonicalVersion` 2 to 3 at P5.

`canonicalVersion` is a marker that nothing gates on; its single writer is
`Analyze-SwydoReport.ps1:996`. `schemaVersion` is NOT such a marker. It has two writers,
`Get-SwydoReport.ps1:921` for the report path and `:867` for the trend path, and three readers that
gate on the literal `2`, two of which throw. S12 widens all three; rev-1 asserted the opposite and
would have dead-ended every analyze run at the phase it called dark.

The analyzer must keep reading schemaVersion-2 extractions. Every P1 key is additive and every
consumer treats absence as unknown rather than as a default. A v2 extraction therefore yields a
matrix whose rank-3 candidates all carry `reason='incomplete-rows'`, because preconditions 1 and 2
have no affirmative signal. That degradation is correct and is the visible reason to re-extract.

### Rollout

P1 through P4 are additive and land dark, which is true only because S1 and S24 were made additive.
P5 changes default output and needs the waiver. P6, if it is ever built, needs a second and much
smaller one, because F2 confined the summed values to their own phase.

The waiver cannot be approved on a promise. U9 D3 ratified that a waiver's blast surface must be
enumerable and provable, and no research or review agent could measure one because `skill/archive` is
gitignored and absent from this checkout. S33 therefore requires a measured before-and-after on
synthetic fixtures covering each drop class: dimensioned-no-total, blended, duplicate-display-name,
unit-unconfirmed, partial-pages, and multi-basis. It enumerates cells added, findings added, findings
removed and severities crossed.

Three measurements gate P5 alongside it. First, the closer's candidate-bag size per platform before
and after. Second, per platform, the count of distinct `(value, type)` pairs whose hit set mixes
`hasComparison` true and false — the comparison guard is satisfied by ANY hit carrying
`hasComparison`, regardless of which metric it belongs to, so bag growth weakens it independently of
the tracer. Third, the facts document's serialized size and nesting depth against `ConvertTo-Json
-Depth 40`, because a silent depth truncation would be invisible.

`skill/SKILL.md:36` has the model write one facts-slice file per CATEGORY and spawn one analyst
subagent per slice, with a completeness gate that every `meta.providers` platform appears exactly
once. The matrix is per-platform and therefore slices cleanly. This spec adds no document-level
block, because such a block would be invisible to the analyst that owns a platform.

### Files touched (estimate)

| File | Phases | Nature |
|---|---|---|
| `skill/scripts/Get-SwydoReport.ps1` | P1 | additive keys, pure-function extraction, the field probe |
| `skill/scripts/ConvertTo-SwydoTrendFacts.ps1` | P1 | schemaVersion gate widening |
| `skill/scripts/Analyze-SwydoReport.ps1` | P1-P5 | gate widening, two new helpers, the matrix pass, rule repointing |
| `skill/scripts/Update-SwydoLedger.ps1` | P2 | delete the duplicated basis hash |
| `skill/scripts/Test-ReportNumbers.ps1` | P5 | split fact index, the new forcing class, the prose check |
| `skill/report-template.md` | P5 | whitelist, hard rule 1 and hard rule 2 |
| `skill/SKILL.md` | P1, P5 | schemaVersion 3 in Mode B; matrix in the analyst brief; trend asymmetry |
| `Test-Extractor.ps1` | P1 | additive |
| `Test-Analyze.ps1` | P1-P6 | additive, plus the enumerated flip set rewrites |
| `Test-Closer.ps1` | P5, P6 | additive |
| `SWYDO_REPORT_EXTRACTION_SPEC.md` | P1 | schemaVersion 3 contract |

### Alternatives rejected

- **Nesting the matrix inside `headline`.** Breaks `Analyze-SwydoTrend.ps1` gate 2c, which requires
  `canonical.scope -eq 'account'` on a MEASURED value.
- **Analysis-only, never persisted.** The closer cannot trace what it cannot see.
- **Unifying `Test-Additive` and `Test-Summable`.** U7 R4 pins their divergence with a regression test.
- **Deriving the matrix from the facts-level `breakdowns` block.** Capped at 20 rows.
- **Retiring `GAP_NO_ACCOUNT_TOTAL`.** It is the natural regression detector for the new feature.
- **A value-comparison tiebreak in the reduce.** Rejected verbatim by U9 FP-1.
- **Re-keying `dimensions[]` or `breakdowns[].rows[].values` in place** (rev-1's S1 and S22). Both are
  breaking shape changes that silently corrupt shipped consumers while the suites stay green, because
  the fixture builders construct those structures directly instead of running `Normalize-Widget`.
- **Decoding the JWT scope claim to enumerate fields** (rev-1's S12). A scope claim enumerates
  authorization scopes, not GraphQL fields.
- **Indexing summed cells into the per-platform candidate bag.** That bag is section-scoped, so a
  tool-computed value would trace on any line of the platform's section and the anchor requirement
  would be unenforceable.

## 5. Production-readiness checklist

- **security** — no new egress on the data path and no new credential path. S14's field probe issues
  requests against an already-authenticated session and must record error text only, never a token or
  a signature. `Scrub-Credential` and `Assert-NoCredential` run over the emitted document; note that
  they cover the ANALYZER output, so any new extractor-side string must be checked at its own seam.
- **perf / scale** — the matrix is O(widgets x metrics) with a single reduce pass. The real cost is
  facts size, sized in §4 "Rollout".
- **a11y** — N/A — swydee has no UI.
- **i18n** — no improvement is claimed. Precondition 4 still matches an English word list.
  `dimensionRefs[]` records ids that ENABLE a future language-independent partition test once S14
  establishes an id vocabulary; until then the id proves nothing.
- **error / empty / loading states** — the reason-token vocabulary IS the empty state, and it is
  total: every observed `(platform, metric)` gets a cell, so a missing value is always explained.
- **observability** — `contributingWidgetIds[]`, `contributingRowKeys[]`, `conflict` and
  `coverageBasis` make every cell retraceable without arithmetic by the reader.
- **risks** — the dominant risk is closer dilution, gated by the P5 measurements and bounded by S29's
  split index. Second is a rank-3 cell presented as reported data, gated by S30 and S31. Third is
  double counting from subtotal rows or a non-partition dimension; precondition 4 inherits U7 R16's
  accepted allowlist risk at a higher blast radius, because U7 spent that assumption on a finding
  while rank 3 spends it on a published number. Fourth is a top-N widget summing to an under-count,
  gated by precondition 2. No concurrency risk: single-writer, one-shot scripts.
- **testing + left-shift gates** — see §7. Precondition 6, precondition 7 and the S2 duplicate-name
  path each get a named regression test. Fixture builders must exercise `Normalize-Widget` rather
  than constructing widget objects directly, or a breaking extractor change stays invisible.
- **migration / rollback** — additive through P4, so rollback is a revert. P5 is revertable as one
  `--no-ff` merge; `canonicalVersion` makes any artifact produced under it self-describing.
- **user docs** — `skill/SKILL.md` gains schemaVersion 3, the matrix in the analyst brief, and the
  trend asymmetry note. `SWYDO_REPORT_EXTRACTION_SPEC.md` gains the schemaVersion-3 contract.

## 6. Acceptance criteria

- AC1. When an extraction runs against a report with a hidden section, a multi-account provider and a
  paginated table, the emitted widget objects carry S1-S11, and `meta.fieldProbe` records one result
  per c3 candidate with no token or signature in it. Observable because S13 makes the assembly
  callable under `-DefineOnly`.
- AC2. When `widget.dimensions[]` is compared before and after P1 on the same extraction, it is
  byte-identical, and `Get-TimeSeries` still returns a non-null block for a Day-dimensioned widget.
- AC3. When the analyzer or the trend converter is handed a schemaVersion-2 document, it does not
  throw, and every rank-3 candidate cell carries `reason='incomplete-rows'`.
- AC4. When a widget carries two metrics with the same display name, each metric's cell carries its
  OWN value, and the resulting headline value change appears in S33's flip set.
- AC5. **(P6)** When a dimensioned widget satisfies every rank-3 precondition, its cell carries a
  value with `method='summed-rows'`, a populated `contributingRowKeys[]` whose count equals the
  filtered row count, and a force-surfaced disclosure finding.
- AC6. **(P6)** When any one rank-3 precondition fails, the cell carries the matching reason token
  and NO value, and no finding claims a computed total. Covered per token, including
  `no-summable-rows` on an all-group-row widget and `incomplete-rows` on a top-N widget.
- AC7. When a widget's rows include a `subtotal` row, that row is excluded from the sum, proven by a
  fixture that would double-count without the exclusion.
- AC8. When the `u5c` fixture shape is analyzed (one metric, EUR table total and USD KPI card),
  exactly one cell exists, its winner is deterministic across two runs, and its `conflict` names both
  widgets and carries no display string.
- AC9. When a blended zero-dimension widget is present, it appears in no cell's
  `contributingWidgetIds[]` at any rank, and a provider observed only on blended widgets has a cell
  with `reason='blended-undecomposable'` and still triggers `GAP_NO_ACCOUNT_TOTAL`.
- AC10. When every cell of a platform carries a reason token, no WIN, LOSS, `GAP_UNIT_UNCONFIRMED` or
  `ANOM_BUDGET_CONSTRAINED` is emitted for that platform.
- AC11. When the report cites a `summed-rows` number without the disclosure fid anchored on the same
  line, the closer blocks publish. When it cites a measured matrix number, the closer traces it.
  Before S29 the same measured citation must FAIL, proven by a test pinning the fail-closed direction.
- AC12. When a rank-3 disclosure finding is surfaced but the report body contains no disclosure prose,
  the closer blocks publish.
- AC13. `bash tools/run-gates.sh` is green, with each of the eight suites additive on its own count
  and unchanged on the others, except for the flip-set assertions enumerated by S33.
- AC14. S33's measured flip set exists as an in-repo artifact enumerating cells added, findings added,
  findings removed and severities crossed, plus the three P5 measurements of §4 "Rollout". The waiver
  is not approvable without it.
- AC15. **(P3)** When a widget satisfies every rank-3 precondition EXCEPT the deferral, its cell still
  carries `reason='incomplete-rows'` and no value, and no `summed-rows` cell exists anywhere in the
  facts document. This pins the F2 stub so P6 cannot leak into P3 unnoticed.
- AC16. **(P1, conditional)** When a live share link is available, `meta.fieldProbe` records one
  result per c3 candidate and the six UNKNOWN rows of §4 "Inventory" are each resolved to present or
  absent. Without a share link this criterion is not observable, and P1 lands without it.

## 7. Gates

- `bash tools/run-gates.sh` — the whole standing bar, and the merge bar for every phase.
- The eight PowerShell suites, all re-run on every phase. Baseline at spec time: 1064 assertions.
  Measured 2026-08-04: `Test-Analyze` 467, `Test-Closer` 129, `Test-TrendAnalyze` 68.
- `memory-tree/check-memory-hygiene.sh` — 12 checks, including check 12 on this file.
- `bash scripts/manifest-check.sh` — the kickoff-manifest ratchet.
- ps source hygiene, memory-recall selftest and skill-drift, agent-instructions wiring, agent-cap
  selftest, check-wiring selftest, the run-gates canary.
- NEW gate added by S23: a facts-schema shape assertion. `tools/gate-legs.json:2-9` lists the eight
  suites and contains no facts-schema or contract-drift leg, so nothing today stops a facts key from
  being renamed out from under the closer and the template.

## 8. Open questions

- **F1. Phase split.** Land as sequenced units, or grouped by waiver boundary?
  **RESOLVED (owner, 2026-08-04): one unit per phase.** Each phase takes its own branch, spec,
  adversarial review and merge. The rule is one-per-phase rather than a fixed count, so F2's
  resolution raising the phase count to six raises the unit count to six with it. The rejected
  alternative was three units grouped by waiver boundary (P1 · P2+P3+P4 · P5).
- **F2. Does rank 3 ship before `serverRowTotal` is settled?**
  **RESOLVED (owner, 2026-08-04): probe first — Option A with a trigger.** Rank 3 moves to a
  conditional P6 that does not start until S14 reports. P3 ships ranks 1 and 2 with rank 3 stubbed to
  `reason='incomplete-rows'`, so the matrix is uniform in its key space immediately and uniform in its
  values only once completeness can be affirmatively proven. If the probe finds no row-set signal, P6
  closes WONTDO and the stub is the permanent answer. This keeps U6 D5's bar rather than working
  around it. Prereq on the owner: one live share link, since `skill/archive` is gitignored and absent
  from this checkout.
  **OUTCOME (2026-08-05):** the owner supplied a live share link and the probe ran. `serverRowTotal`
  does not exist, so the WONTDO branch fired and P6 is closed. The probe also proved
  `widget.dateRange` DOES exist, which P1 S15 now extracts.
- **F3. Do the two `major` rules stay `major` once they fire on more metrics?** RECOMMENDATION: keep
  the severity, add a per-provider rollup with U6 D11's 20-item cap, so the report discloses once
  rather than twenty times.
- **F4. Does `manualKpi` ever become a value-bearing cell?** The body currently says no, and gives it
  `reason='manual-entry'`. Admitting it would make "every included widget" literally true but would
  put operator-typed numbers into the closer's candidate bag for the first time. RECOMMENDATION: keep
  the body's answer; revisit only if a client report is found to depend on a manual KPI.
- **F5. Is the second layer a reference into `breakdowns`, or its own copy?** RECOMMENDATION: a
  reference, decided after the P5 size measurement.
- **F6. Does the closer gain a scope or period check?** RECOMMENDATION: out of scope here, tracked as
  a follow-up, because it would change publish outcomes on reports this program does not touch.

## 9. Revision log

- rev-1 · 2026-08-04 · initial draft from workflow wf_34e0982e-f78 (six research lenses plus a
  completeness critic, 222 tool calls). Two kickoff premises were falsified during research and
  corrected in the draft: a blended widget is NOT skipped entirely, and a duplicate metric display
  name is a wrong-value path rather than a dropped-metric path.
- rev-2 · 2026-08-04 · folded the Tier-2 adversarial review wf_0925fd2f-2cd (five finder lenses,
  eleven batched skeptics, 17 agents, 324 tool calls; 54 raw findings, 50 survived refutation,
  deduplicating to 13 must-fix and 9 should-fix). Full artifact under `../reviews/`. Load-bearing
  corrections: S1 and S24 were breaking shape changes and are now additive; `schemaVersion` has three
  literal-gating consumers and rev-1 claimed it had none; the reduce grouped on a key finer than the
  cell key with no collapse rule; the blended exclusion bound only rank 3; pagination completeness is
  not row-set completeness; a dimension id does not prove partition-hood; the cell lacked the raw
  numerics its repointed rules read; ratio recomposition had no guards; the closer's per-platform bag
  made the anchor requirement unenforceable; the force-surfacing mechanism did not exist; and the JWT
  scope claim cannot enumerate GraphQL fields.
- rev-4 · 2026-08-05 · S14's field probe ran against a live report. Seven of eight candidates do not
  exist. P6 (rank-3 summing) is closed WONTDO because no row-set completeness signal exists at all,
  which makes the `incomplete-rows` stub permanent rather than temporary. `widget.dateRange` DOES
  exist and P1 extracts it, partially closing a residual three ratified specs cite. The filtered-KPI
  ambiguity is now known to be permanent. Status moved to INPROGRESS as P1 landed.
- rev-3 · 2026-08-04 · owner resolved F1 and F2 in place; header tail carries `ratified 2026-08-04`.
  F2 splits rank-3 summing out of P3 into a conditional P6 (S34-S36) gated on S14's field probe, so
  P3 now ships ranks 1 and 2 with rank 3 stubbed to `incomplete-rows`. AC5 and AC6 are re-scoped to
  P6; AC15 pins the P3 stub so P6 cannot leak into P3 unnoticed; AC16 covers the probe and states
  plainly that it is unobservable without a share link. F1 makes each phase its own unit, which now
  means six units rather than five.

## 10. Reuse audit

None — the codebase-map kit is not adopted in swydee, so `tools/codebase-map/reuse_lookup.py` does
not exist here and the audit was done by reading source. The seams this program wires through:

- `Analyze-SwydoReport.ps1:711-782`, the headline loop, which the matrix parallels rather than
  replaces.
- `Analyze-SwydoReport.ps1:765`, the shipped `canonical{}` provenance block, which the cell's
  provenance fields extend from one source widget to N.
- `Analyze-SwydoReport.ps1:809-828`, the `$observed` inventory pass. The matrix's key space already
  exists and is already computed here, by metric-id prefix across ALL data widgets including blended
  ones, and `GAP_NO_ACCOUNT_TOTAL` is already exactly observed-minus-coverage. The matrix reuses this
  pass rather than adding a second discovery walk.
- `Analyze-SwydoReport.ps1:473-479` and `:491-511`, `Test-Summable` and `Get-RatioSpec`, which
  `Get-AggregationClass` composes rather than replaces.
- `Update-SwydoLedger.ps1:41-51`, the shipped basis hash. S16 MOVES it into the analyzer rather than
  copying it, because `Update-SwydoLedger.ps1:36` already dot-sources the analyzer and U6's
  deferred-work contract names a single shared helper as a precondition.
- `Get-SwydoReport.ps1:492-531`, `Normalize-Widget`, where every P1 key is a retention rather than a
  new fetch.
