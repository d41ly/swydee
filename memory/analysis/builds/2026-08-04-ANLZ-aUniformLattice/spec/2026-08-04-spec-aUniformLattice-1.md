# ANLZ-aUniformLattice-1 — layered uniform per-platform metric view

**Status:** OPEN · rev-1 · 2026-08-04 · node a · Tier-2 · base 8e1e5294

## 1. Goal

Replace the sparse per-platform headline with a computed, uniform `(platform, metric)` matrix that
covers every metric of every included widget, backed by an addressable per-row second layer, and
rewire the finding rules and the model-facing report surface onto it. The answer to "what would it
take" is a five-phase program, not one unit, because the matrix cannot be made sound until the
extractor emits identity and completeness keys it currently fetches and discards.

## 2. Scope (IN)

Five phases. Each is its own commit and review boundary. Phase order is a dependency order, not a
priority order: P2 cannot be verified without P1, and P4 is unsound without P3.

**P1 — extractor schema v3: identity and completeness keys (S1-S12).**

- S1. Emit `widget.dimensions[]` as `{name, id}` instead of names only. The ids are already
  collected at `Get-SwydoReport.ps1:513` and flattened away at `:515`.
- S2. Emit `widget.metrics[].cellKey`, the exact `Uniq-Key` string written into `rows[].metrics`
  at `Get-SwydoReport.ps1:525`. See §4 "Data model" for why this is a correctness fix, not an
  ergonomic one.
- S3. Emit `widget.metrics[].providerId`, the metric id prefix. Four separate analyzer passes
  re-derive it today at `Analyze-SwydoReport.ps1:187`, `:812` and `:852`.
- S4. Emit `widget.providers[].dataSourceId` and `widget.providers[].partId`. Both are already
  requested at `Get-SwydoReport.ps1:378` and dropped by `Normalize-Widget` at `:500`.
- S5. Emit `widget.rowsComplete` (bool) plus `widget.pageInfo{hasNextPage, endCursor,
  pagesFetched}`. This is the positive completeness signal U6 D5 requires; see §4.
- S6. Emit `widget.sectionHidden`. `sections{id name isHidden}` is already requested at
  `Get-SwydoReport.ps1:756` and `isHidden` is discarded at `:932`.
- S7. Emit `widget.widgetTemplateId` and `widget.widgetTemplateLinked`, already fetched at `:378`.
- S8. Emit `widget.hasTotalRow` and `widget.rowKindCounts{data, subtotal, total}`.
- S9. Emit `widget.currencyBasis` (`row-meta` or `absent`) and `widget.currencyCodes[]`, the
  distinct set seen across rows, rather than only the first-row scavenge at `:510-511`.
- S10. Emit `widget.documentIndex`, the widget's ordinal in `widgets[]`.
- S11. Emit `rows[].rowKey`, a stable identity over ALL dimensions. `Get-SwydoReport.ps1:523`
  already builds the full multi-dimension map that nothing downstream reads past position 0.
- S12. Emit `meta.scopeTokens`, the decoded `scope` claim of the JWT minted at
  `Get-SwydoReport.ps1:84-89`. Costs one base64url decode of a token already in hand. It is the
  only way to enumerate the API surface, because introspection is disabled.

**P2 — declared aggregation semantics (S13-S15).**

- S13. Add `Get-AggregationClass($metricId, $unit)` returning exactly one of `sum`,
  `ratio-recompute`, `dedup-nonsummable`, `account-asis`, `unknown`. It composes the existing pure
  helpers and adds no new regex table.
- S14. Add `Get-CellBasis($unit, $currencyCode)` returning a basis tuple plus a `basisVersion`
  hash. The hash algorithm already ships at `Update-SwydoLedger.ps1:41-51`.
- S15. Leave `Test-Additive` and `Test-Summable` untouched and still divergent. U7 R4 pins that
  divergence with a regression test; `Get-AggregationClass` consumes them, it does not unify them.

**P3 — the matrix and its reduce function (S16-S21).**

- S16. Add `platforms[].metrics{}` as a SIBLING of `platforms[].headline{}`. `headline{}` stays
  byte-identical, including its `hasComparison` scalar key.
- S17. Implement the reduce function of §4 "Data model" as a total function over the contribution
  set, ranked by structure only.
- S18. Every observed `(platform, metricId)` gets a cell. A cell carries a value with its display
  strings, or a reason token, never nothing.
- S19. Every cell carries its `method`, `aggClass`, `scope`, `basis`, `contributingWidgetIds[]` and
  `coverageBasis`.
- S20. A same-rank disagreement produces the document-order winner AND a `conflict` record on the
  cell. The reduce never silently drops a disagreeing contribution.
- S21. Compute the matrix from `$dataWidgets` only, never from the facts-level `breakdowns` block,
  which is capped at 20 rows at `Analyze-SwydoReport.ps1:386`.

**P4 — the addressable second layer (S22-S24).**

- S22. Key `breakdowns[].rows[].values` by metric id, and add `breakdowns[].metricIds[]` alongside
  the existing `metricNames[]`.
- S23. Emit `breakdowns[].rows[].rowKey` from S11, so a row in a two-dimension widget has a unique
  identity.
- S24. A matrix cell whose method is `summed-rows` records the `rowKey` set it summed, so the sum
  is retraceable without the reader performing arithmetic.

**P5 — rewire and disclose (S25-S30).**

- S25. Repoint the finding rules of §4 "Inventory" from `headline` to `metrics`.
- S26. Redefine `GAP_NO_ACCOUNT_TOTAL`'s input from observed-minus-headline to
  observed-minus-matrix-coverage. Keep U6 D11's shape, severity and 20-item cap.
- S27. Extend `Build-FactIndex` in `Test-ReportNumbers.ps1` to index `platforms[].metrics` and the
  metric-id-keyed breakdown rows. A number the closer cannot index is not publishable, so P5
  without this ships an unusable matrix.
- S28. Amend `skill/report-template.md` hard rule 2 to admit a verbatim `uniformCell.display` whose
  `scope` starts `summed-rows:` only when the forced disclosure fid is anchored on the same line.
- S29. Bump `meta.canonicalVersion` 2 to 3 and disclose the enumerated flip set in facts.
- S30. Produce the measured flip set on fixtures before the waiver is approved. See §4 "Rollout".

## 3. Non-goals (OUT)

- Trend facts get no matrix. `Analyze-SwydoTrend.ps1` builds its own independent
  `platforms[]`/`headline{}` of the same documented shape, and giving it a matrix is a second
  waiver with its own suite. The resulting asymmetry must be named in the template so the model
  does not look for a matrix that is not there. Follow-up: a TREND-family unit.
- No cross-platform metric taxonomy. Mapping `google-adwords:cost` and `facebook-ads:spend` onto
  one shared concept is a separate unit, and it inherits the direction inconsistency recorded in
  §5. This spec keeps metric ids provider-namespaced.
- No cross-scope reconciliation. U6's WONTFIX residual stands: a legitimate account KPI and a
  filtered table total are both surfaced with honest scope, and the matrix does not adjudicate
  between them by value.
- No remainder arithmetic anywhere, on either layer. U6's ban is absolute and P4 makes violating it
  easier, not harder.
- No migration or backfill of archived facts. U9 D10/D11 stands: archived artifacts stay truthful
  and self-describe via `canonicalVersion`.
- No renumbering of the frozen `U<seq>` id era. Cite verbatim.
- No new GraphQL round trip. Every P1 key is already fetched, already derivable from the retained
  `raw` blob, or is a local decode. Keys that would need a new query field are listed as UNKNOWN in
  §4 "Inventory" and are explicitly out until S12 resolves them.

## 4. Design

### Data model

The matrix is `platforms[<providerId>].metrics[<metricId>]`, a sibling of `headline`. The sibling
placement is the load-bearing choice. It keeps `headline` byte-identical, which means
`Analyze-SwydoTrend.ps1:276-282` gate 2c never sees a computed cell, the existing closer index
keeps working unchanged, and the U9 waiver surface shrinks to the rewired finding rules plus
additive keys. Nesting the matrix inside `headline` would put a computed value where U7b MF-3
requires a measured account value, and would silently corrupt the trend path.

A cell has this shape. Fields marked NEW have no precedent; the rest extend the shipped
`canonical{}` block at `Analyze-SwydoReport.ps1:765` from one source widget to N.

| Field | Meaning |
|---|---|
| `id` | the metric id; the matrix key |
| `metric` | display name |
| `display`, `displayPrevious`, `displayDelta` | pre-formatted by `Format-Metric` / `Format-Delta`; the only thing the closer can match |
| `type` | `currency`, `percent`, `count`, `ratio` or `number`, from `Metric-Type` |
| `direction`, `unit`, `currency` | as on a headline cell |
| `hasComparison` | per cell, feeding the closer's comparison guard |
| `scope` | `account`, `table-total:<dimId>`, `summed-rows:<dimId>`, or `manual-entry` |
| `method` NEW | `kpi-widget`, `total-row`, `summed-rows`, `ratio-recompute`, `operator-entered` |
| `aggClass` NEW | the S13 class, so the template can key its wording on it |
| `basis` NEW | `{unit, currencyCode, basisVersion}` |
| `contributingWidgetIds[]` NEW | every widget that fed the cell, not just the winner |
| `contributingRowKeys[]` NEW | present only when `method` is `summed-rows` |
| `coverageBasis` NEW | what "included" meant for THIS cell: provider filter state and section visibility |
| `conflict` NEW | present when a same-rank disagreement was reduced away; carries the losing widget ids and no values |
| `reason` NEW | present instead of a value; one of the reason tokens below |
| `period` | stamped from `meta.currentPeriod` |

Reason tokens, for a cell that exists but has no value: `no-total`, `not-summable`,
`basis-conflict`, `incomplete-rows`, `blended-undecomposable`, `unit-unconfirmed`, `manual-entry`.
These replace `GAP_NO_ACCOUNT_TOTAL`'s metric list rather than duplicating it.

`conflict` carries ids and counts only, never a losing display string. U9 D4/FP-3 ratified that
echoing a superseded value mints a traceable-number surface for a figure the tool deliberately
demoted.

**The reduce function.** Group contributions by `(providerId, metricId, basisVersion)`. Rank by
structure only, never by value. U9 FP-1 rejected value adjudication because it would have the tool
decide which number is right by arithmetic and would make the winner depend on data that changes
between periods.

- Rank 1: a zero-dimension KPI card. The predicate is byte-for-byte the `$isKpi` test at
  `Analyze-SwydoReport.ps1:734`, per U9 D1.
- Rank 2: an explicit total row on a dimensioned widget.
- Rank 3: a sum over detail rows, permitted only under the preconditions below.
- Within a rank, document order wins, using the S10 `documentIndex` so the winner is recordable
  rather than an implicit array position.

**Rank-3 preconditions.** U6 D5 deferred synthesis in full and set a hard bar: synthesis may
proceed only when completeness is affirmatively proven, never merely because no warning said
otherwise. All of the following must hold, and a failure emits a reason token instead of a value:

1. `widget.rowsComplete` is `$true` (S5). Absence is not proof.
2. `Test-Summable` on the metric id.
3. `aggClass` is `sum`. A `ratio-recompute` cell is derived from its component cells instead; a
   `dedup-nonsummable` or `account-asis` cell is never summed.
4. The widget has exactly one dimension, and that dimension is a partition. S1's dimension id
   replaces today's regex over an English display label at `Analyze-SwydoReport.ps1:484-488`.
5. The widget is not blended.
6. Basis is homogeneous across the summed rows.
7. The summed row set is `kind -eq 'data'` AND NOT `Test-GroupRow`, with `kind -eq 'subtotal'`
   excluded EXPLICITLY. Subtotal rows are extracted at `Get-SwydoReport.ps1:521` and read by
   nothing today; every analyzer filter happens to be `data` or `total`. A row-summing matrix
   depends on that exclusion to avoid double counting, so it must become a stated rule with its own
   test rather than an accident of five filter shapes.

Every rank-3 cell is force-surfaced. U6's deferred-work contract states that a tool-computed total
must never be presentable as if the platform reported it. The mechanism is the template contract of
S28 plus a finding the closer honours, not a severity escalation.

**"Included" is defined once.** A widget is included when `kind -eq 'data'`, AND its section is not
hidden (S6), AND either no `-Platform` filter was applied or its provider is in the filter. A
`manualKpi` widget is admitted as a cell with `method='operator-entered'` and is never a measured
contribution, which closes the residual U7's critic override left open when it dropped the
goal-card exclusion for want of a concrete flag. `coverageBasis` stamps the answer on every cell,
because a matrix computed under a `-Platform` filtered pull is not account-level for the report's
own claim, and `SKILL.md:81` already forces a `PROVIDER_FILTERED` gap for exactly that reason.

**Why S2 is a correctness fix.** The analyzer fetches a total-row cell by metric DISPLAY NAME at
`Analyze-SwydoReport.ps1:738`, while the extractor uniquifies colliding names into `name [id]` at
`Get-SwydoReport.ps1:358-364`. When one widget carries two metrics with the same display name, the
second metric's lookup returns the FIRST metric's cell. This was verified by execution under
PowerShell 5.1 during the review pass: both lookups returned `current=100`. The result is a
headline cell keyed by metric 2's id, carrying metric 1's value, formatted with metric 2's unit and
type. It passes the scalar guard. It is a wrong-number path, not a dropped-metric path, and it
exists in shipped code today. `Uniq-Key` also falls back to `col<idx>` when a metric name is empty,
producing a second silent path where the analyzer evaluates a lookup on the empty string.

### Inventory

Finding rules that read `platforms[].headline` and must be repointed in P5. Two are `major` and
therefore force-surfaced by the closer, so their verdicts changing is user-visible.

| Rule | Site | Severity | Effect of the rewire |
|---|---|---|---|
| `GAP_UNIT_UNCONFIRMED` | `Analyze-SwydoReport.ps1:895-910` | major | fires on more metrics; forced into the report |
| `ANOM_BUDGET_CONSTRAINED` | `:912-930` | major | fires on more metrics; forced into the report |
| WIN / LOSS | `:904-907` | none | verdict set grows; this is the point of the change |
| `GAP_NO_ACCOUNT_TOTAL` | `:806-828` | info | input redefined per S26 |
| `GAP_HEADLINE_SOURCE_CHANGED` | `:829-844` | info | unchanged; keyed on `headline`, which is frozen |
| `DISC_CROSS_WIDGET` | `:923-950` | major | NOT repointed; see below |

`DISC_CROSS_WIDGET` keeps reading widgets directly. Its correctness argument is its dimension
signature key: it compares only widgets with identical sorted dimension sets. Repointing it at a
matrix that has already reduced those widgets to one cell would destroy the comparison it exists to
make.

Recommendations are NOT rules in code. They are model-authored from the facts document, per
`skill/SKILL.md`. Rewiring recommendations therefore means changing what the model reads, which is
the matrix plus S28's template amendment, not a PowerShell change. The spec's deliverable (b) is
half PowerShell and half prompt contract, and the two halves land in the same phase.

Widget data keys, answering the owner's second question. It splits in two, because an extractor key
bumps `schemaVersion` and touches a second script while an analyzer key rides the waiver.

**(c1) extractor keys — all already fetched, derivable from `raw`, or a local decode.** S1-S12
above. Nothing here needs a new GraphQL field.

**(c2) analyzer cell fields.** The cell table above. Prefer c2 wherever the data is already in the
extraction, because the retained `raw` blob makes most of it derivable locally.

**(c3) UNKNOWN — cannot be classified until S12 lands.** GraphQL introspection is disabled, so the
JWT scope claim is the effective schema. Each of these is rated blocking-for-soundness by at least
one research lens, and each is currently assumed rather than known:

| Candidate key | What it would settle |
|---|---|
| `metrics[].aggregation` | whether collapsing rows into an account cell is arithmetic or fiction |
| `widget.dateRange` override | whether two widgets can be proven to describe the same period |
| `widget.filters` / `segments` | whether a KPI card is an account ceiling or a filtered subset |
| `dimensions[].isPartition` | whether rows are disjoint buckets, replacing a regex allowlist |
| `rows[].isTotalOfShownRows` | whether a total row totals the account or the shown slice |
| `widget.serverRowTotal` | whether a row set is the whole set or a top-N prefix |

The filtered-KPI-card ambiguity is the shared root cause of three ratified residuals: U6:243,
U7 R17 and U9 FP-1. It gets structurally larger as more rules read the account layer, which is
exactly what this program does. S12 is the cheapest probe that could close it.

### Migration

`schemaVersion` 2 to 3 at P1, and `meta.canonicalVersion` 2 to 3 at P5. Both are markers naming
which algorithm produced the artifact; nothing gates on a literal value, and the single writer is
`Analyze-SwydoReport.ps1:996`. Per U6 D10 and U9 D6, a silent algorithm change under an unchanged
marker would be worse than the change itself.

The analyzer must keep reading schemaVersion-2 extractions. Every P1 key is additive and every
consumer treats absence as "unknown", not as a default value. A v2 extraction therefore yields a
matrix whose rank-3 cells are all `reason='incomplete-rows'`, because S5's positive completeness
signal is absent and absence is not proof. That degradation is correct and is the visible reason to
re-extract.

### Rollout

P1 through P4 are additive and land dark. P5 is the only phase that changes default output, and it
is the only one that needs the waiver.

The waiver cannot be approved on a promise. U9 D3 ratified that a waiver's blast surface must be
enumerable and provable, and no research lens could measure one because `skill/archive` is
gitignored and absent from this checkout. S30 therefore requires a measured before-and-after on
synthetic fixtures covering each drop class — dimensioned-no-total, blended, duplicate-display-name,
unit-unconfirmed, partial-pages — enumerating cells added, findings added, findings removed and
severities crossed. If no real extraction can be obtained, the fixture set IS the enumeration and
the spec says so rather than implying broader proof.

Two measurements gate P5 alongside it. First, the closer's candidate-bag size per platform before
and after, because every candidate added makes a hallucinated number likelier to trace by type and
magnitude, and "the guard gets weaker" is not a reviewable claim while "the bag goes from N to M"
is. Second, the facts document's serialized size and nesting depth against `ConvertTo-Json -Depth
40`, because the facts document is the model's entire context and a silent depth truncation would
be invisible.

`skill/SKILL.md:36` has the model write one facts-slice file per CATEGORY and spawn one analyst
subagent per slice, with a completeness gate that every `meta.providers` platform appears exactly
once. The matrix is per-platform and therefore slices cleanly. Any document-level block would not,
and would be invisible to the analyst that owns a platform — silently reproducing the
insights-from-a-subset problem this program exists to fix. This spec adds no document-level block
for that reason.

### Files touched (estimate)

| File | Phases | Nature |
|---|---|---|
| `skill/scripts/Get-SwydoReport.ps1` | P1 | additive keys in `Normalize-Widget` and the report block |
| `skill/scripts/Analyze-SwydoReport.ps1` | P2-P5 | two new pure helpers, the matrix pass, rule repointing |
| `skill/scripts/Test-ReportNumbers.ps1` | P5 | `Build-FactIndex` extension |
| `skill/report-template.md` | P5 | hard rule 2 amendment |
| `skill/SKILL.md` | P5 | matrix in the analyst brief; trend asymmetry note |
| `Test-Extractor.ps1` | P1 | additive |
| `Test-Analyze.ps1` | P2-P5 | additive, plus the enumerated flip set rewrites |
| `Test-Closer.ps1` | P5 | additive |
| `SWYDO_REPORT_EXTRACTION_SPEC.md` | P1 | schemaVersion 3 contract |

### Alternatives rejected

- **Nesting the matrix inside `headline`.** Breaks `Analyze-SwydoTrend.ps1` gate 2c, which requires
  `canonical.scope -eq 'account'` on a MEASURED value, and widens the waiver to the trend path.
- **Analysis-only, never persisted.** The closer cannot trace what it cannot see, so nothing derived
  from the matrix would be publishable. It fails the product's load-bearing invariant.
- **Unifying `Test-Additive` and `Test-Summable`.** U7 R4 pins their divergence with a regression
  test precisely so a future tidy-up cannot silently flip calibration.
- **Deriving the matrix from the facts-level `breakdowns` block.** It is capped at 20 rows plus
  force-included anomaly labels, so a sum over it is a certifiable wrong number.
- **Retiring `GAP_NO_ACCOUNT_TOTAL`.** It is simultaneously the disclosure of today's loss and the
  natural regression detector for the new feature. Keep the rule, redefine its input.
- **A value-comparison tiebreak in the reduce.** Rejected verbatim by U9 FP-1.

## 5. Production-readiness checklist

- **security** — no new egress, no new credential path, no new write path. `Scrub-Credential` and
  `Assert-NoCredential` already run over the emitted document and the matrix adds no free text. The
  only new surface is S12's decoded JWT scope claim, which must record the `scope` claim ONLY and
  never the token, the signature or any other claim.
- **perf / scale** — the matrix is O(widgets x metrics); the reduce is one pass over contributions.
  The real cost is facts size, sized in §4 "Rollout".
- **a11y** — N/A — swydee has no UI.
- **i18n** — the program REMOVES a language dependency: S1's dimension id replaces `Test-PartitionDim`'s
  English word list as the authority for whether rows may be summed.
- **error / empty / loading states** — the reason-token vocabulary IS the empty state, and it is
  total: every observed `(platform, metric)` gets a cell, so a missing value is always explained.
- **observability** — `contributingWidgetIds[]`, `contributingRowKeys[]`, `conflict` and
  `coverageBasis` make every cell retraceable to its inputs without arithmetic by the reader.
- **risks** — the dominant risk is closer dilution: a larger candidate bag makes a fabricated number
  likelier to trace. Gated by the P5 measurement. Second risk is a rank-3 cell presented as reported
  data, gated by S28 and the forced disclosure. Third is double counting from subtotal rows, gated
  by precondition 7 and its own test. No concurrency risk: single-writer, one-shot scripts.
- **testing + left-shift gates** — see §7. Precondition 7 and the S2 duplicate-name path each get a
  named regression test, because both are currently correct only by accident.
- **migration / rollback** — additive through P4, so rollback is a revert. P5 is revertable as one
  `--no-ff` merge; `canonicalVersion` makes any artifact produced under it self-describing.
- **user docs** — `skill/SKILL.md` gains the matrix in the analyst brief and the trend asymmetry
  note. `SWYDO_REPORT_EXTRACTION_SPEC.md` gains the schemaVersion-3 contract. A user-facing change
  without its page updated is not done.

## 6. Acceptance criteria

- AC1. When an extraction runs against a report with a hidden section, a multi-account provider and
  a paginated table, the emitted widget objects carry all of S1-S11 and `meta.scopeTokens` is a
  string array containing no token, signature or other claim.
- AC2. When the analyzer runs on a schemaVersion-2 extraction, it still produces valid facts, and
  every rank-3 candidate cell carries `reason='incomplete-rows'` rather than a synthesized value.
- AC3. When a widget carries two metrics with the same display name, each metric's cell carries its
  OWN value. A regression test pins this against the executed repro in §4 "Data model".
- AC4. When a dimensioned widget has no total row, is single-dimension on a partition dimension, is
  non-blended, has `rowsComplete=$true` and a summable metric, its cell carries a value with
  `method='summed-rows'`, `scope='summed-rows:<dimId>'`, a populated `contributingRowKeys[]`, and a
  force-surfaced disclosure finding.
- AC5. When any one rank-3 precondition fails, the cell carries the matching reason token and NO
  value, and no finding claims a computed total.
- AC6. When a widget's rows include a `subtotal` row, that row is excluded from the sum, proven by a
  test whose fixture would double-count without the exclusion.
- AC7. When two zero-dimension KPI cards for one `(platform, metric)` disagree, the matrix carries
  the document-order winner plus a `conflict` record naming the losing widget ids and no values, and
  `DISC_CROSS_WIDGET` still fires unchanged.
- AC8. When a `-Platform` filtered extraction is analyzed, every matrix cell's `coverageBasis`
  records the filter, and `PROVIDER_FILTERED` still fires.
- AC9. When the report cites a number that exists only in `platforms[].metrics`, the closer traces
  it. Before S27 the same citation must FAIL, proven by a test that pins the fail-closed direction.
- AC10. When the report cites a `summed-rows` number without the disclosure fid anchored on the same
  line, the closer blocks publish.
- AC11. `bash tools/run-gates.sh` is green, with each of the eight suites additive on its own count
  and unchanged on the others, except for the flip-set assertions enumerated by S30.
- AC12. S30's measured flip set exists as an in-repo artifact enumerating cells added, findings
  added, findings removed and severities crossed, plus the closer candidate-bag delta and the facts
  size and depth measurements. The P5 waiver is not approvable without it.

## 7. Gates

- `bash tools/run-gates.sh` — the whole standing bar, and the merge bar for every phase.
- The eight PowerShell suites, all re-run on every phase. Baseline at spec time: 1064 assertions.
  Measured during research on 2026-08-04: `Test-Analyze` 467 passed, `Test-Closer` 129 passed,
  `Test-TrendAnalyze` 68 passed.
- `memory-tree/check-memory-hygiene.sh` — 12 checks, including check 12 on this file.
- `bash scripts/manifest-check.sh` — the kickoff-manifest ratchet.
- ps source hygiene, memory-recall selftest and skill-drift, agent-instructions wiring, agent-cap
  selftest, check-wiring selftest, the run-gates canary.
- NEW gate proposed by this spec: a facts-schema shape assertion. `tools/gate-legs.json:2-9` lists
  the eight suites and contains no facts-schema or contract-drift leg, so today nothing mechanically
  stops a facts key from being renamed out from under the closer and the template. P3 adds one.

## 8. Open questions

- **F1. Phase split.** Land as five sequenced units, or fewer? RECOMMENDATION: five. P1 alone is a
  schemaVersion bump touching the extractor, which the tier rule already makes a design-pass unit;
  bundling it with the rewire would put a two-script change under a one-script waiver.
- **F2. Can S12 actually run before P1 is built?** The scope-token decode needs a live share link,
  and `skill/archive` is gitignored and absent here. If the owner can supply one report pull, the
  six UNKNOWN keys in §4 "Inventory" become measured facts and several rank-3 preconditions may
  become gateable rather than disclose-only. RECOMMENDATION: run the probe before P3 is designed in
  detail. This is the single highest-value unblocking action in the program.
- **F3. Do the two `major` rules stay `major` once they fire on more metrics?**
  `GAP_UNIT_UNCONFIRMED` and `ANOM_BUDGET_CONSTRAINED` are force-surfaced. A matrix that covers
  every metric will fire them on many more, and U7 R7's discipline is that uncertainty downgrades to
  info. RECOMMENDATION: keep the severity, add a per-provider rollup with U6 D11's 20-item cap, so
  the report is forced to disclose once rather than twenty times.
- **F4. Does `manualKpi` enter the matrix at all?** Admitting it makes "every included widget" true;
  excluding it keeps operator-entered numbers out of a computed set. RECOMMENDATION: admit with
  `method='operator-entered'` and a distinct scope, because silent exclusion is the failure U10
  already flags at its line 29.
- **F5. Is the second layer a reference into `breakdowns`, or its own copy?** A copy triples the row
  payload on a breakdown-heavy report; a reference needs S22 and S23 first. RECOMMENDATION: a
  reference, decided after the P5 size measurement.
- **F6. Does the closer gain a scope check?** Once cells carry `period` and `scope`, the closer
  could refuse a number whose scope contradicts the sentence. It does no period or scope
  discrimination today. RECOMMENDATION: out of scope here, tracked as a follow-up, because it would
  change publish outcomes on reports this program does not otherwise touch.

## 9. Revision log

- rev-1 · 2026-08-04 · initial draft from workflow wf_34e0982e-f78 (six research lenses plus a
  completeness critic, 222 tool calls). Two premises stated at kickoff were falsified during
  research and are corrected in this draft: a blended widget is NOT skipped entirely, and a
  duplicate metric display name is a wrong-value path rather than a dropped-metric path.

## 10. Reuse audit

None — the codebase-map kit is not adopted in swydee, so `tools/codebase-map/reuse_lookup.py` does
not exist here and the audit was done by reading source. The seams this program wires through were
identified by reading:

- `Analyze-SwydoReport.ps1:711-782`, the headline loop, which the matrix parallels rather than
  replaces.
- `Analyze-SwydoReport.ps1:765`, the shipped `canonical{}` provenance block, which the cell's
  provenance fields extend from one source widget to N.
- `Analyze-SwydoReport.ps1:809-828`, the `$observed` inventory pass. The matrix's key space already
  exists and is already computed here, by metric-id prefix across ALL data widgets including
  blended ones. `GAP_NO_ACCOUNT_TOTAL` is already exactly observed-minus-coverage. The matrix reuses
  this pass rather than adding a second discovery walk.
- `Analyze-SwydoReport.ps1:473-479` and `:491-511`, `Test-Summable` and `Get-RatioSpec`, which
  `Get-AggregationClass` composes rather than replaces.
- `Update-SwydoLedger.ps1:41-51`, the shipped basis-hash algorithm, reused verbatim for
  `basisVersion` instead of writing a second one.
- `Get-SwydoReport.ps1:492-531`, `Normalize-Widget`, where every P1 key is a retention rather than a
  new fetch.
