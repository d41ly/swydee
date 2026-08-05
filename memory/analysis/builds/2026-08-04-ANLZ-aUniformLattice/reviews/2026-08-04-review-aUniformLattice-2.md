## AMENDMENTS v1 (post adversarial design review, 2026-08-04 — these OVERRIDE the body below)

Review verdict: **GO-WITH-CHANGES**. Thirteen must-fix, nine should-fix, six sharpenings. No survivor
attacks the five-phase shape, the sibling-matrix placement, the deferral of the six UNKNOWN keys, the
trend non-goal or the taxonomy non-goal. Every code citation below was opened against the pinned tree
at `0e2bc0b`.

- **Correctness must-fix (S1 is a breaking shape change, not an additive key — make it additive):**
  keep `widget.dimensions[]` as the string name array byte-for-byte and add a sibling
  `widget.dimensionRefs[]` of `{name, id}` in the same order. Rank-3 precondition 4 and every new
  consumer read the sibling; no shipped consumer changes. Today `Get-SwydoReport.ps1:513` builds
  `{name, id}` and `:515` flattens it to names, and four shipped consumers treat each element as a
  string: the anchored time-series guard `'(?i)^(day|week|month|date)$'` at
  `Analyze-SwydoReport.ps1:412`, the `DISC_CROSS_WIDGET` grouping key `$dimSig` at `:929`, the headline
  scope `"table-total:$($dims[0])"` at `:735`, and `dimensions=$wdims` into the facts breakdown block
  at `:401`. Under PS 5.1 a `ConvertFrom-Json` object stringifies to `@{name=Day; id=...}`, so
  `Get-TimeSeries` returns `$null` for every widget and the entire `timeSeries` and `pacing` block
  silently disappears from facts. The suites would not catch it: the `DW` fixture builder at
  `Test-Analyze.ps1:314-318` constructs `dimensions=@($dims)` from plain strings and never runs
  `Normalize-Widget`, so AC11 stays green while every real extraction breaks. With the sibling, §4
  "Migration"'s "Every P1 key is additive", the Rollout's "P1 through P4 are additive and land dark"
  and S16's byte-identical `headline{}` all become true as written.

- **Correctness must-fix (§4 "Migration" rests on a false premise — three shipped consumers gate on
  `schemaVersion -eq 2` and two of them throw):** delete the sentence "nothing gates on a literal
  value, and the single writer is `Analyze-SwydoReport.ps1:996`". `:996` writes `canonicalVersion`;
  `schemaVersion` has two writers, both in the extractor, at `Get-SwydoReport.ps1:921` for the report
  path and `:867` for the trend path. The readers are `Analyze-SwydoReport.ps1:678`
  (`if($doc.meta.schemaVersion -ne 2){ throw ... }`), `ConvertTo-SwydoTrendFacts.ps1:75` (same shape,
  also a throw) and `skill/SKILL.md:31`, which tells the model to stop unless the value is 2. P1 gains
  an S-item widening both throws to an accepted set of 2 and 3, carrying the v2 degradation §4
  "Migration" already describes, updating `skill/SKILL.md:31` in P1 rather than P5, and stating
  explicitly whether the trend extraction's `schemaVersion` bumps too. Add
  `skill/scripts/ConvertTo-SwydoTrendFacts.ps1` to the Files-touched table for P1. Without this, P1 as
  scoped dead-ends every analyze run while `Test-Analyze.ps1:324` keeps its fixture at 2 and the suite
  stays green.

- **Correctness must-fix (S17 and §4 "The reduce function" — the group key is finer than the cell key
  and nothing resolves the collapse):** group contributions by `(providerId, metricId)` only. Rank
  across all contributions regardless of basis, as the shipped headline already does. The ranked
  winner supplies the value and its basis becomes the cell's `basis`. Every surviving contribution on a
  different `basisVersion` is recorded as a `conflict` entry carrying widget ids and `basisVersion`
  only and never a losing display string, per U9 D4/FP-3. Reserve the `basis-conflict` reason token for
  rank-3 precondition 6, which is the within-widget row case and the only rule in this spec that can
  produce it. As written, the three-part group key competes for the two-part cell slot at §4 "Data
  model" with no stated tiebreak, so the published value would depend on insertion order across a basis
  boundary — the non-determinism U9 FP-1 rejected value adjudication to avoid. The shape is live in the
  shipped suite, not hypothetical: fixture `u5c` at `Test-Analyze.ps1:538-541` is one report carrying a
  EUR dimensioned table total and a USD zero-dimension KPI card for `google-adwords:cost_micros`, and
  U6:242 records same-metric-two-currencies as a standing WONTFIX. Add an AC on the `u5c` shape
  asserting exactly one cell, a deterministic winner and a `conflict` naming both widgets. Add
  multi-basis to S30's enumerated drop classes, which today omit it.

- **Correctness must-fix (§4 "'Included' is defined once" — the blended exclusion binds at every rank,
  not only rank 3):** add "AND `Test-Blended` is false" to the inclusion rule for value contribution,
  and delete rank-3 precondition 5 as redundant. A blended widget stays in the `$observed` key-space
  walk at `Analyze-SwydoReport.ps1:809-828`, so it still registers platforms and metric ids, and a
  `(platform, metricId)` observed only on blended widgets gets a cell with
  `reason='blended-undecomposable'` and no value. Restate rank 1 as U9 D1's full gate set rather than
  as the bare `$isKpi` expression: `Analyze-SwydoReport.ps1:729` is `if(Test-Blended $w){ continue }`
  and sits five lines ABOVE the `:734` predicate the spec tells the builder to copy byte-for-byte, so
  copying the predicate demonstrably does not copy the guard. U6 D6 ratifies that blended
  multi-provider widgets are never a headline source, U7 R6 excludes them from every cross-widget
  check, and U9 D1 states they can never displace. State in S26 that a `reason`-bearing cell does NOT
  count as matrix coverage, so `GAP_NO_ACCOUNT_TOTAL` keeps firing for a blended-only provider instead
  of being silently retired by the redefinition. No shipped test would catch the reversal: U6 test 17
  and `Test-Analyze.ps1:678` assert on `canonical.sourceWidgetId` and on an empty `headline`, both of
  which stay true under a frozen `headline`. Add an AC pinning that a blended zero-dimension widget
  appears in no cell's contributing-widget list at any rank.

- **Correctness must-fix (rank-3 precondition 1 claims a completeness proof the spec elsewhere says it
  does not have):** rename precondition 1 to what the signal actually proves, which is that every page
  the API offered was fetched, and add a precondition requiring an affirmative row-set signal before
  any sum is published. `Get-SwydoReport.ps1:456-477` iterates `while($pi.hasNextPage)` and sets
  `outcome='incomplete'; reason='partial-pages'` only when a page faults or `hasNextPage` survives the
  loop, so a widget configured to show its top N rows returns N edges with `hasNextPage=$false` and
  reports complete. The spec's own (c3) table lists `widget.serverRowTotal` — "whether a row set is the
  whole set or a top-N prefix" — as UNKNOWN and blocking-for-soundness, and U6:244 records a top-N
  total row as undetectable without an extractor completeness signal. Absent `serverRowTotal` equal to
  the returned row count, or an equivalent no-row-limit flag recovered from the retained `raw` blob,
  the cell carries `reason='incomplete-rows'` and no value. If rank 3 ships before S12 answers, S28
  must state that a `summed-rows` cell is a sum of SHOWN rows and S26 must not count it as account
  coverage. Without this the U6 B1 blocker returns as an under-counted fabricated total that is
  disclosed as tool-computed and still wrong.

- **Correctness must-fix (rank-3 precondition 4 and §5 "i18n" — a dimension id is not a partition
  proof):** write precondition 4 as "exactly one dimension AND its NAME satisfies `Test-PartitionDim`",
  keep `Analyze-SwydoReport.ps1:484-488` as the authority until S12 resolves
  `dimensions[].isPartition`, and record S1's dimension id as provenance only. Correct the §5 i18n
  claim to "enables a future language-independent partition test". An id changes which string is
  matched, not what the match proves, and no id vocabulary has ever been observed because `:515` has
  always discarded ids. The spec contradicts itself as written: the (c3) table says
  `dimensions[].isPartition` is what would settle whether rows are disjoint buckets. The failure mode
  is a double count, not a gap: `Test-Analyze.ps1:436` pins `Test-PartitionDim` FALSE for
  `action_type`, fixture `u4b` at `:499-501` is a single-dimension `action_type` widget whose two rows
  sum to 160 against a total of 100, and `Get-DetailSumFindings` early-returns at
  `Analyze-SwydoReport.ps1:584` when there is no total row, so nothing cross-checks the sum. If the id
  is to become the authority, P3 must be preceded by the S12 probe output as an in-repo observed-id
  inventory plus a named add-only allowlist with a test asserting that an off-list dimension yields
  `reason='not-summable'` rather than a value. State plainly that rank 3 inherits U7 R16's accepted
  allowlist risk at a higher blast radius, because U7 spent that domain-known assumption on a finding
  while rank 3 spends it on a published number.

- **Correctness must-fix (rank-3 precondition 7 drops the row-count half of U6's contract — restore
  it):** add a precondition that the filtered row set is non-empty, evaluated AFTER the group-row and
  subtotal exclusions, failing to `reason='incomplete-rows'` or to a new `no-summable-rows` token.
  U6's deferred-work note prescribes both halves: reuse `Get-BreakdownFindings`' filter "and
  re-evaluate the `>=2 rows` gate against the filtered set". This spec adopts the filter and drops the
  gate, and precondition 6 is vacuously true over an empty set, so an empty or all-subtotal dimensioned
  table passes every stated precondition. `Test-GroupRow` at `Analyze-SwydoReport.ps1:127` also filters
  a `$null` label, so the empty case is reachable without any literal `All` row. Pin the summing idiom
  in the same sentence: an accumulator loop fabricates `$0.00`, while `Measure-Object -Sum` over an
  empty set returns `$null` in PS 5.1 and would leave a cell carrying neither a value nor a reason,
  violating S18's own totality claim. Add a fixture whose only data row is a group row, asserting a
  reason token and no value.

- **Correctness must-fix (the rank-3 preconditions constrain the current period only — add comparison
  coverage):** a previous-period sum is emitted only when every summed row carries a numeric compare
  cell. Otherwise the cell carries `display` with `hasComparison=$false`, no `displayPrevious` and no
  `displayDelta`, plus a field naming the covered and total row counts. Compare values are per row and
  independently absent: `Get-SwydoReport.ps1:525` sets `$cmp` per cell and yields `$null` for a row
  with no compare column, `Row-Cmp` at `Analyze-SwydoReport.ps1:193` returns `$null` for anything
  non-numeric, and `Get-DeltaPct` at `:112-116` cannot know its two arguments covered different row
  sets. The nearest shipped precedent points the wrong way and would be copied: `Get-DetailSumFindings`
  at `:595` sums only non-null cells. A ten-row current sum over a seven-row previous sum publishes a
  fabricated delta that S25 then turns into a WIN or LOSS verdict, and S28's disclosure covers the sum
  while saying nothing about the comparison basis. Extend AC4 to assert the full-coverage shape and add
  an AC pinning the partial-coverage shape.

- **Correctness must-fix (rank-3 precondition 3 and `method='ratio-recompute'` — give the derivation
  its own preconditions):** a `ratio-recompute` cell is emitted only when both component cells share
  `basisVersion`, `scope` and `method`, when component selection uses `Get-RatioSpec`'s numerator and
  denominator patterns with the role-qualifier rule and skips on ambiguity, when the denominator is
  non-zero, and when micros are normalised before dividing. Any failure emits a reason token; add one,
  for example `components-incomparable`, because none of the seven declared tokens covers a missing or
  zero denominator. The shipped recompute enforces all of this and the spec's one sentence enforces
  none of it: `Get-RatioReconFindings` requires one widget's total row at `Analyze-SwydoReport.ps1:517`,
  exactly one candidate per role at `:531-533`, numerator and denominator distinct from the reported
  metric at `:535`, link-versus-all role agreement at `:539-541`, confirmed units on money components
  at `:543-544`, a non-zero denominator at `:546` and `:549`, and micros normalisation at `:547-548`.
  The comment at `:502-505` records a false `major` that one missing role guard already produced in
  this codebase. Note the asymmetry that sets the severity: the shipped code with all six guards only
  emits a finding, while the spec with none publishes a number. Define the recomputed cell's `scope` as
  a function of its components' scopes, and route it through the same forced disclosure as
  `summed-rows`, because it is equally tool-computed. Correct §10's reuse claim while you are there:
  `:473-479` and `:491-511` are the classifier, and the pairing, unit, role and denominator guards live
  at `:531-549` in a different function the audit never mentions.

- **Correctness must-fix (§4 cell table and S25 — the cell omits every numeric the repointed rules
  read, and renames the display field):** add `current`, `previous` and `deltaPct` to the cell table,
  present only when the cell has a value and absent alongside `reason`. Name the display field
  `displayCurrent` to match the headline, or add an S-item enumerating every rule site whose field read
  changes. Add an explicit rule that every value-reading rule skips a cell carrying `reason`. S25 is
  unbuildable as written: `Analyze-SwydoReport.ps1:900` gates WIN and LOSS on `$null -ne $h.deltaPct`,
  `:902` computes the confidence flag from `$h.current` and `$h.previous`, `:917` gates
  `ANOM_BUDGET_CONSTRAINED` on `[double]$h.current -ge 0.10`, and `:899`, `:905` and `:919` interpolate
  `$h.displayCurrent`. Against the specified cell shape PS 5.1 resolves each of those to `$null`
  silently, so the repointed verdict set becomes EMPTY and a force-surfaced `major` rule stops firing
  entirely — the exact inverse of the Inventory table's "verdict set grows; this is the point of the
  change". A reason-bearing cell would also render `GAP_UNIT_UNCONFIRMED` as "figure shown raw ()".
  U6 D8's ban on a raw `value` governed a provenance record, and the shipped headline cell at `:760`
  carries all three numerics; the spec never draws that distinction and an implementer would read the
  omission as deliberate. Add an AC that on a fixture where headline and matrix agree, the repointed
  rules produce a strict superset of today's WIN, LOSS and ANOM set, asserted rather than assumed.

- **Correctness must-fix (S27, AC9 and AC10 — name the closer index bucket per method, and close the
  finding-statement bypass):** cells whose `method` is `kpi-widget`, `total-row` or `operator-entered`
  are indexed into `byPlatform` as measured values. Cells whose `method` is `summed-rows` or
  `ratio-recompute` are NOT added to the per-platform bag; their display strings reach the closer only
  through the disclosure finding's `statement`, which `Add-StringNumbers` at
  `Test-ReportNumbers.ps1:251` already routes to `byFid`. No new violation type is needed for this
  half: `$base` is resolved once per section at `:367-369`, `$cands` is built additively at `:373-376`,
  and a fid bag joins it only on a line carrying that fid, so `byFid` IS the line-restriction mechanism
  and the closer says so in its own header at `:197-200`. Under the plain reading of S27 every matrix
  cell lands in `byPlatform`, which makes a tool-computed sum traceable on every line of that
  platform's section and leaves AC10 unobservable. S25 must close the second door in the same breath:
  state whether `summed-rows` and `ratio-recompute` cells feed the value-reading rules at all, and if
  they do, the derived finding inherits the disclosure obligation and its statement must name the
  method. Otherwise `GAP_UNIT_UNCONFIRMED` at `:899` or a WIN or LOSS at `:905` puts the identical
  computed string into a second `byFid` bag reachable through a fid that discloses nothing, and
  `report-template.md:75` actively instructs the model to quote a finding's statement. Add an AC that a
  rank-3 cell which also produces a WIN or LOSS finding does not make its value traceable on a line
  carrying only that fid. State AC10's residual limit: matching is on value and collapsed type only at
  `:268-285`, so a summed value coinciding within tolerance with an unrestricted candidate still
  traces.

- **Correctness must-fix (§4 "Every rank-3 cell is force-surfaced" and S28 — name the forcing lever,
  its channel and its budget):** name the disclosure finding now. Per U9's ratified fatigue ruling a
  provenance or sourcing note belongs in `$gaps` under a `GAP_` prefix, so give it a `GAP_` ruleId and
  route it there. Name the forcing mechanism as a third class on closer gate 3a with no clause
  obligation attached, for example `requiresProvenanceAnchor -eq $true` beside the existing predicate
  at `Test-ReportNumbers.ps1:420`, and add `Test-ReportNumbers.ps1` to Files-touched for that change as
  well as for the `Build-FactIndex` extension. Both shipped levers are ruled out: severity escalation
  is refused by the spec's own sentence and by U7 R7, and reusing `requiresDownstreamData` drags gate
  3c at `:459-461` along, which would force a downstream or lead-quality clause onto a row-summing
  disclosure — the wrong-clause failure U10 D8 rejected verbatim. U10's "adding a new closer token
  class is out of scope" was scoped to U10 and is not a standing prohibition, so this spec may add the
  class; it must simply budget it. Add a `Test-Closer.ps1` case pinning that an unsurfaced summed-rows
  disclosure blocks publish while a surfaced one needs no downstream clause. Note in S28 that the
  anchor is a verification scaffold rather than the client-visible disclosure: `Strip-Anchors` at
  `:483-491` deletes every HTML comment and `:511-513` writes the stripped text to `-PublishTo`. U6:255
  sanctioned the anchor route, so a prose-disclosure requirement is optional; if it is wanted, mirror
  `$script:DownRx` with a `$script:SummedRx` clause check.

- **Discipline must-fix (S5, S10, S12 and AC1 — the three keys land in code no suite can execute):**
  add an S-item to P1 extracting the assembly into pure functions above the `-DefineOnly` return, for
  example a `Build-ExtractionMeta` helper plus an explicit
  `Normalize-Widget($wmeta,$obj,$outcome,$index)` signature, and restate AC1 at that function boundary
  against a synthetic outcome record and a synthetic JWT. `Normalize-Widget` at
  `Get-SwydoReport.ps1:493` receives only the widget meta and the GraphQL object, `rowsComplete` and
  `pageInfo` live in the per-widget outcome record collected at `:893`, the widget ordinal exists only
  in the run-body loop at `:911`, and `meta.scopeTokens` belongs to the meta block at `:919-927`. All
  of that sits below `if($DefineOnly){ return }` at `:730`, which is how `Test-Extractor.ps1:9` loads
  the script. The repo already ratified the pattern: the comment at `:281-283` says
  `Get-ExtractionCompleteness` is defined above the return "so the completeness contract is assertable
  offline instead of living in run-body code no suite can reach". Say plainly in AC1 that the live
  three-feature report is a manual check and not a gate, because `skill/archive` is gitignored and
  absent from this checkout.

- **Discipline should-fix (S22 changes existing output inside a phase the Rollout calls additive):**
  keep `breakdowns[].rows[].values` keyed by metric display name and add a sibling `valuesById` keyed
  by metric id, mirroring the S16 move this spec already justifies for `headline`.
  `Analyze-SwydoReport.ps1:397` is `$vals[[string]$m.name]=$cell`, so the re-key changes shipped
  output, while the Rollout says P5 is the only phase that changes default output and the only one that
  needs the waiver. `Test-Analyze.ps1:230` reads `$bd.rows[0].values.Clicks` and feeds three
  assertions, so the re-key also breaks AC11 in a phase with no enumerated flip set to charge them to.
  Nothing fails loudly at runtime, because `Test-ReportNumbers.ps1:224` iterates
  `$row.values.PSObject.Properties.Name` blindly. If the re-key is kept instead, move S22 to P5, add it
  to S30's enumerated flip set, and name `Test-Analyze.ps1:230-232` as a rewrite site.

- **Discipline should-fix (S14 and §10 reuse audit — name the single-implementation mechanism and
  budget it):** P2 extracts `Get-BasisVersion` into one param-only define-only helper file dot-sourced
  by both `Analyze-SwydoReport.ps1` and `Update-SwydoLedger.ps1`, deleting the ledger's copy, exactly
  as U6's deferred-work note prescribes. Add that helper, `skill/scripts/Update-SwydoLedger.ps1` and
  `Test-Ledger.ps1` to the Files-touched table, and add a cross-call-site test asserting both produce
  the same hash for the same inputs. The dependency direction matters and the spec never states it:
  `Update-SwydoLedger.ps1:36` dot-sources `Analyze-SwydoReport.ps1 -DefineOnly` and the analyzer
  dot-sources nothing, so a naive reverse dot-source re-enters the ledger's param block, which is the
  clobber hazard `Manage-SwydoArchive.ps1:461-464` already warns about in code. Reconcile the signature
  too: the shipped function is `Get-BasisVersion($metricId,$unit,$currency)` at
  `Update-SwydoLedger.ps1:42-51`, so S14's two-argument `Get-CellBasis($unit, $currencyCode)` cannot
  produce a ledger-comparable digest — either pass the metric id through or rename the cell field so it
  does not read as comparable. U6 M4 rated two drifting copies **major**, which is why the mechanism
  must be named rather than left to the builder.

- **Discipline should-fix (S28 amends one rule while the binding constraint sits elsewhere — widen
  it):** extend S28 to amend `skill/report-template.md:3`, a closed enumeration of permitted fact
  sources that does not contain `platforms[].metrics`, and the Structure block at `:34-35`, which
  templates the per-platform body as one bullet per HEADLINE metric. Add
  `platforms[].metrics[].display/displayPrevious/displayDelta` to the enumeration with the
  scope-dependent conditions attached, and say which `scope` values may be narrated as account figures.
  Change the Files-touched row for `skill/report-template.md` from "hard rule 2 amendment" to name the
  permitted-source enumeration, hard rule 2 and the per-platform structure. As scoped the template
  would simultaneously forbid and permit citing a matrix cell, and the closer enforces neither
  direction, because `Test-ReportNumbers.ps1:373-386` matches any indexed candidate regardless of which
  block it came from. S28 as written also admits only cells whose scope starts `summed-rows:`, leaving
  `account` and `table-total:` cells unadmitted after the amendment. Add an AC that greps the shipped
  template for the matrix path, so the prose contract cannot drift from what S27 indexes.

- **Correctness should-fix (AC3 has no implementing S-item, and the frozen headline keeps a wrong value
  the matrix gets right):** state in AC3 which surface it binds, and name the S-item and phase that
  repoints the display-name lookups at `Analyze-SwydoReport.ps1:738`, `:192-193`, `:392`, `:395`,
  `:528` and `:931` to S2's `cellKey`. The wrong-value path is shipped and was confirmed by execution:
  `:738` is `$cell = $tr.metrics.$($m.name)` while `Get-SwydoReport.ps1:358-364` stores the second
  colliding metric under `"$base [$id]"`. If the headline is repaired, its value changes belong in
  S30's enumerated flip set and under the P5 waiver. If S16's freeze stands instead, say so in S16 and
  add a P5 rule emitting a finding whenever `headline[m].displayCurrent` differs from
  `metrics[m].display` for the same metric id, with an AC pinning it. Shipping both surfaces silently
  is the one option that is not acceptable, because `Test-ReportNumbers.ps1:206-218` builds one flat
  per-platform candidate list with no metric-id association, so both contradictory strings are
  certifiable and the model may cite either. The repair-versus-freeze choice is a scope call for the
  owner and should be recorded as a new F-item in §8.

- **Correctness should-fix (S25 — a repointed `major` rule would call a tool-computed sum a raw
  reported figure):** gate the repointed rules by `method`, or give `GAP_UNIT_UNCONFIRMED` a per-method
  statement variant that names the cell as tool-computed and drops the "figure shown raw" and
  "unverified provider" framing. `Analyze-SwydoReport.ps1:899` emits that statement at
  `severity='major'`, its predicate is a null unit plus `Test-Money`, and nothing in the rank-3
  preconditions requires a confirmed unit, so a summable money metric with a null unit reaches rank 3
  and gets summed. The rule is force-surfaced by closer gate 3a and named explicitly in
  `report-template.md` hard rule 4, so the misattributing sentence would be mandatory in the report.
  U6:255 forbids exactly this presentation: a synthesized total must never read as if the platform
  reported it. Fold the answer into F3, which today asks only about fire counts and not about input
  provenance. Two prongs of the original finding do not apply and must not be carried in:
  `ANOM_BUDGET_CONSTRAINED` reads `search_lost_is`, which `Test-Summable` at `:476-477` rejects, so it
  can only ever read a measured cell; and AC10 still blocks an undisclosed summed NUMBER, so what
  survives is a false provenance claim in the prose rather than a wrong figure.

- **Discipline should-fix (§4 "'Included' is defined once", S21 and F4 — resolve the `manualKpi`
  contradiction once and correct two false citations):** the section defines inclusion as
  `kind -eq 'data'`, admits a `manualKpi` widget two sentences later, and S21 computes from
  `$dataWidgets`, which `Analyze-SwydoReport.ps1:684` defines as `kind -eq 'data'`. Pick one and state
  it in a single place. If `manualKpi` is admitted, S21 and the inclusion rule must both say so, and P1
  must first supply the keys that would give such a widget a `providerId` and a `metricId`:
  `Normalize-Widget` emits `metrics[]`, `rows[]` and `currencyCode` only inside the `kind -eq 'data'`
  branch, and `providers` comes from `$w.source.parts`, which a `manualKpi` widget lacks by the same
  test that gave it the kind at `Get-SwydoReport.ps1:498`. U9's amendments already ruled the ratified
  position: `kind -eq 'data'` structurally excludes non-data kinds, documented and not coded. Delete
  the clause claiming this closes a residual U7's critic override left open — U7:56 lists the goal-card
  exclusion as `[FIXED]`, R17 at U7:145 mandates it, and the concrete flag ships as `kind='manualKpi'`.
  Delete or restate F4's citation of U10 line 29, which flags a hand-entered value SUPPRESSING a
  `major` rule rather than a silent exclusion, and is therefore evidence against admitting
  operator-entered numbers into a measured set.

- **Correctness should-fix (S11 and S23 — `rowKey` is built from display labels and can collide):**
  define `rowKey` as the row's document ordinal joined with the dimension tuple, which guarantees
  within-widget uniqueness by construction and is free inside the existing
  `foreach($e in $w.data.edges)` loop at `Get-SwydoReport.ps1:519`. `:523` fills the map with `DimName`
  output, and `DimName` at `:336-344` returns the literal `(group)` whenever no cell property passes
  its string filter, so a numeric dimension column yields the same value for every row while the map's
  keys are the dimension column names and identical on every row. S23's stated property, that a row in
  a two-dimension widget has a unique identity, is not delivered by the cited construction, and AC4's
  "populated `contributingRowKeys[]`" would be satisfiable by N copies of one string. Add a test
  asserting the contributing key count equals the unique key count on a fixture with two
  identically-labelled rows.

- **Discipline should-fix (S12 and F2 — a scope claim cannot answer the (c3) questions; use a
  field-existence probe):** every (c3) candidate is a field-existence question, and a token scope claim
  carries permissions rather than a type system, so change the instrument. `Invoke-GQL` at
  `Get-SwydoReport.ps1:101-110` returns `.Content` verbatim and takes `-NoRetry`, and `:120-121`
  returns an HTTP error body as data by design, so one speculative-field request per (c3) candidate
  answers it from the GraphQL `Cannot query field` error with introspection still disabled. Delete "It
  is the only way to enumerate the API surface" from S12 and keep the scope decode as the
  token-surface inventory it actually is. Add to AC1 an observable for at least one (c3) row being
  resolved, because AC1 today asserts only the shape and safety of `meta.scopeTokens`. The §5 security
  sentence needs no change: `Scrub-Credential` and `Assert-NoCredential` do run over the facts document
  they describe, and the extraction JSON is a known credential-bearing artifact by design.

- **Discipline should-fix (S30 and AC12 measure bag size but not comparison reachability — add the
  second measurement):** add to the P5 gating measurements, per platform, the count of distinct value
  and type pairs whose hit set mixes `hasComparison` true and false, before and after. The closer's
  comparison guard at `Test-ReportNumbers.ps1:405` is satisfied by ANY hit in the bag carrying
  `hasComparison`, `Find-Candidates` at `:268-285` matches on collapsed type and value only, and
  `Map-CellType` at `:103-107` collapses counts and ratios into one type space, so a growth claim can
  publish for a metric that has no previous-period data at all. §5 "risks" names only the fabrication
  half of the dilution and the Rollout measures only bag size. The stronger option, carrying the cell's
  metric id into the candidate record so that a comparison-satisfying hit must belong to the same
  metric, is a real fix and would need its own Files-touched budget.

- **Sharpening, not an override (§4 Inventory table line ranges):** change `ANOM_BUDGET_CONSTRAINED`'s
  site to `Analyze-SwydoReport.ps1:911-922` and `GAP_UNIT_UNCONFIRMED`'s to its rule line `:899`. The
  cited `:912-930` ends eight lines inside `DISC_CROSS_WIDGET`, which the same table cites as
  `:923-950` and says must NOT be repointed, and `:895-910` likewise encloses the WIN and LOSS rows at
  `:904-907`. Every severity claim in the table is correct as written.

- **Sharpening, not an override (§4 "Why S2 is a correctness fix", the `col<idx>` sentence):** restate
  it as follows. When a metric name is empty the row-map key becomes the metric ID, and `col<idx>` is
  used only when the name and the id are BOTH empty, per `Get-SwydoReport.ps1:359`. The conclusion is
  unchanged: the analyzer's display-name lookup at `:738` then evaluates on the empty string and the
  cell is silently dropped. Ids come from the GraphQL node at `:516`, so the empty-name-live-id shape
  is the reachable one and is what an AC3 companion fixture should cover.

- **Sharpening, not an override (§4 Inventory (c3), the three-residual sentence):** split the citation.
  U6:243 is the per-widget `dateRange` override WONTFIX, which the (c3) table already tracks on its own
  row; cite U7 R17 and U9 FP-1 for the filtered-KPI-card ambiguity. The error is inherited from U9
  FP-1, which cites U6:243 correctly for both gaps at once.

- **Sharpening (§4 cell table, `contributingWidgetIds[]`):** rename it `candidateWidgetIds[]` and add a
  singular `sourceWidgetId` mirroring the shipped `canonical.sourceWidgetId` at
  `Analyze-SwydoReport.ps1:765`, reserving a plural summand list for `method='summed-rows'`, where
  `contributingRowKeys[]` already carries the real summands. The reduce sources a cell's value from
  exactly one winner, so "every widget that fed the cell" reads as an aggregation label on what is
  really a candidate list, and §5's retraceability claim is overstated for a single-winner cell. State
  in S28 that candidate ids are provenance and never license an aggregation claim in prose, which the
  closer cannot check because it verifies numbers and not the claims wrapped around them.

- **Sharpening, not an override (AC9's fail-closed half):** add the fixture constraint. AC9's cited
  value must live in a rank-2 or rank-3 cell and must not coincide within half-ULP tolerance with any
  headline, breakdown or timeSeries candidate for that platform, or the test proves nothing. A rank-1
  cell is the same measurement as its headline cell and is formatted by the same `Format-Metric` call
  at `Analyze-SwydoReport.ps1:757-763`, so its display string is already in `byPlatform` via
  `Test-ReportNumbers.ps1:213-218` and traces with or without S27. The before-and-after half is
  observable across the phase commits and needs no golden infrastructure.

- **Sharpening (§3 non-goal 4, remainder arithmetic):** cite U6:256 inline and say plainly whether its
  report-contract deliverable is being declined. U6's deferred-work list requires the unit that builds
  rank-3 synthesis to forbid total-minus-shown-rows remainder arithmetic in the prompt, and this spec
  discharges the neighbouring bullet by name while converting this one into a non-goal. The existing
  "No arithmetic, no re-rounding, no summing" clause at `report-template.md:3` predates U6 by a day and
  is the rule U6 asked to be strengthened, not a discharge of it. The failure direction is fail-closed
  rewrite cost rather than a wrong number, so promoting it to a hard-rule-2 clause is optional and the
  citation is not.

---

%%% END OF AMENDMENTS BLOCK — the notes below are for the owner, not for pasting %%%

**Survivors I would move to §8 as open questions instead of amendments**

1. **The AC3 headline repair-versus-freeze fork** (written above as the AC3 should-fix). The amendment
   correctly forbids shipping two contradictory certifiable values in silence, but the choice between
   repairing `Analyze-SwydoReport.ps1:738` and freezing the headline plus disclosing the divergence is
   a blast-radius call, not a correctness verdict — repair moves headline values into P1 or P2 and
   widens the waiver the spec deliberately confined to P5. Both options are sound; the owner picks.

2. **F4's `manualKpi` admit-or-exclude decision.** Everything factual in that amendment must land, and
   the two false citations must go regardless. But the decision itself already lives in F4, and the
   review adds a fact that changes its price rather than its answer: a `manualKpi` widget carries
   neither a `providerId` nor a `metricId` today, so admitting it needs extractor keys nobody scoped.
   Restate F4 with that price attached and let the owner rule.

3. **Whether P3 hard-gates on the S12 probe.** The precondition 1 and precondition 4 amendments are
   both written fail-closed, so they are safe on their own. What they cannot decide is the program
   question underneath: rank 3 currently rests on two properties the spec's own (c3) table calls
   unknown and blocking, so either P3 waits for the probe or the program ships P1, P2 and P4 and defers
   rank 3 where U6 D5 left it. F2 recommends the probe; it should be sharpened into a gate question
   with a named fallback.

4. **Borderline, and I did not move it.** The reduce-collapse policy could be "winner plus `conflict`"
   or "no value plus `basis-conflict`". I wrote the amendment decisively as winner-plus-conflict,
   because it matches shipped U9 behaviour on `u5c` and because the value-suppressing branch would have
   the matrix blank a metric that the frozen `headline` still reports. If the owner prefers fail-closed
   over headline consistency, that is the one line in the block worth reopening.