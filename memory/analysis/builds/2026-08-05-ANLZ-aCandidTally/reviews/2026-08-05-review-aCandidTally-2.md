# survey-aCandidTally-2 - defect-surface survey against the rebased base

**Run:** wf_0039abb6-748 - 2026-08-05 - node a - 5 agents, 4 survey lenses plus one
synthesis. Target: main at 39def66, after ANLZ-aUniformLattice landed. This is a SURVEY,
not an adversarial review: it re-derives the defect surface, it does not refute findings.

It reports 37 candidate sites. The synthesized scope proposal is folded into the spec at
rev-5; two of its claims were re-verified against source by hand before being written there,
and one recorded correction is below.

## Correction applied at fold-in

The synthesis lists five `Test-Analyze.ps1` version pins plus one `factsVersion` pin. Verified
by grep: `:459`, `:460`, `:728`, `:1300`, `:1301` and `:1409`. rev-3's A10 had claimed two.

## Candidate sites

| Site | Handled on main | Consequence |
|---|---|---|
| `skill/scripts/Analyze-SwydoReport.ps1:967` | no | The headline. Every per-platform top-line number the client reads. The cell is fetched by display name but FILED under $m.id, so platforms[].headline['google-adwords:all_conversions'] publishes conversions' 100 with unit/type/direction/currency taken from a... |
| `skill/scripts/Analyze-SwydoReport.ps1:812` | no | The matrix builder (Get-MatrixContributions), i.e. the whole platforms[].metrics lattice ANLZ-aUniformLattice-4 built to be addressable BY ID. The comment states the display-name read as a deliberate byte-identity choice with the headline, which means the m... |
| `skill/scripts/Analyze-SwydoReport.ps1:1211` | no | DISC_CROSS_WIDGET, severity=major, therefore FORCE-SURFACED by the closer's 3a gate - it must appear in the delivered client report. Two same-named metrics in one widget push the SAME cell value into TWO different metric-id buckets. When a second widget wit... |
| `skill/scripts/Analyze-SwydoReport.ps1:192` | no | The primitive under 14 of the sites below. Verified under PS 5.1 this session: property lookup is case-insensitive, so 'Conversions'/'conversions' resolve to the same first cell; and a $null or empty name returns $null SILENTLY (no throw), so every empty-di... |
| `skill/scripts/Analyze-SwydoReport.ps1:1133` | no | The value-provenance pass behind GAP_COST_RANKING_NO_VALUE - severity=major AND requiresDownstreamData=$true, so it trips BOTH the closer's 3a surfacing gate and its 3c downstream-clause gate; the published report is forced to carry it. $m is selected by id... |
| `skill/scripts/Analyze-SwydoReport.ps1:641` | no | Get-RatioReconFindings. $rm comes from Get-RatioSpec on the id, $num/$den from `Where-Object {(Get-MetricPart $_.id) -match $spec.numPat}` - all id-selected, then read by name. DISC_RATIO_UNIT is severity=major and force-surfaced, and its statement accuses ... |
| `skill/scripts/Analyze-SwydoReport.ps1:689` | no | Get-DetailSumFindings. The loop is `foreach($m in @($w.metrics))`, so two same-named metrics sum the SAME cells twice and emit the finding twice under two different metric labels. Worse, the micros base conversion at L693-694 keys on $m.unit - the SECOND me... |
| `skill/scripts/Analyze-SwydoReport.ps1:735` | no | Get-SliceAccountFindings, the cross-WIDGET case: L742 matches the ceiling candidate by id (correct) and L743 then reads the OTHER widget's total row by THAT widget's display name, so the ceiling can come from a different metric entirely. Two failure modes: ... |
| `skill/scripts/Analyze-SwydoReport.ps1:481` | no | Get-TimeSeries derived metrics. $dd.num/$dd.den come from Find-Metric on the id (L469-473), then read by name. The result is written to buckets[].derived.CPL / derived.'cost/conv' as a formatted money string, which report-template.md:3 explicitly whitelists... |
| `skill/scripts/Analyze-SwydoReport.ps1:498` | no | The time-series pacing pass. $primary is chosen by id predicates (L493-495) then read by name, so the ENTIRE published series - every bucket display, maxVsMinRatio, netChange and the trend verdict 'rising'/'declining'/'flat' - can be another metric's number... |
| `skill/scripts/Analyze-SwydoReport.ps1:219` | no | ANOM_CONCENTRATION. $primary is picked by scanning $w.metrics for higher-better+additive on the ID (L218) then read by name, so the share percentage and both absolute figures in the statement can come from a different metric while being labelled and unit-fo... |
| `skill/scripts/Analyze-SwydoReport.ps1:224` | no | ANOM_NEW / ANOM_PAUSED / ANOM_SEGMENT_DIVERGENCE. ANOM_PAUSED is severity=major and force-surfaced, so a mis-resolved pair (rv=0, rp>0 read off the wrong column) forces a fabricated "'Brand Search' stopped" claim into the client report - or suppresses a rea... |
| `skill/scripts/Analyze-SwydoReport.ps1:248` | no | The config-driven effort->result rules. $em/$rm come from Find-Metric (id regex, L246); the row read is by name. These agree ONLY when the id-selected metric happens to be the FIRST holder of its display name. Concrete repro: metrics[0] = 'Cost' / google-ad... |
| `skill/scripts/Analyze-SwydoReport.ps1:273` | no | ANOM_BRAND_BASELINE. $om=Find-Metric $w '(^\|:)conversions?$' (L271) matches google-adwords:conversions but NOT all_conversions. If all_conversions sits earlier in metrics[] under the same display name 'Conversions', the brand-share numerator, the outcome to... |
| `skill/scripts/Analyze-SwydoReport.ps1:388` | no | Get-Breakdown row ordering. $orderMet is picked by id (L385-386) and the sort key read by name, so the WRONG metric's column decides which 20 of N rows the client sees in the breakdown table - a silent selection bias no number check can catch. If $orderMet ... |
| `skill/scripts/Analyze-SwydoReport.ps1:404` | yes | Get-Breakdown's `values` map. MAIN HAS MITIGATED THE MISSING-NUMBER HALF: valuesById (L411-436) carries each collided id's own value read via cellKey, and Test-Analyze.ps1:1275-1277 pins it. But the mitigation is a SIBLING, not a fix - `values` itself is un... |
| `skill/scripts/Analyze-SwydoReport.ps1:396` | no | The empty-display-name hole that main's valuesById does NOT cover. A LONE metric with an empty name has nameCount=1, so it is not 'collided' and the L422 gate skips valuesById entirely; and Row-Cur $r '' returns null so no `values` entry is written either. ... |
| `skill/scripts/Analyze-SwydoReport.ps1:425` | no | Over-conservative, and the repair can lift it. A schemaVersion-2 row map IS disambiguable: the extractor ran Uniq-Key at extraction time (Get-SwydoReport.ps1:729), so the v2 document already contains BOTH 'Clicks' and 'Clicks [facebook-ads:clicks]' as row k... |
| `skill/scripts/Test-ReportNumbers.ps1:224` | no | The closer indexes `values` and NEVER reads `valuesById`, so main's own fix is inert at the verification boundary - and it fails in BOTH directions. (a) The correct disambiguated number for a collided metric is not a tracing candidate, so a report that quot... |
| `skill/SKILL.md:40` | no | The model that writes the report is explicitly instructed to ignore the ONLY field that carries the correct number for a collided metric, and to read `values` (the collapsed one) instead - and report-template.md:3's quotable-number whitelist matches, listin... |
| `skill/scripts/Test-ReportNumbers.ps1:206` | no | Adjacent but load-bearing for the repair: Build-FactIndex indexes headline, breakdowns, timeSeries, findings and meta.annotations - it never touches `p.metrics`, the uniform matrix. If the spec repoints any narrative surface at platforms[].metrics (the obvi... |
| `skill/scripts/Analyze-SwydoTrend.ps1:309` | no | The trend reconciliation's whole numeric input is the report analyzer's headline value, so it inherits Analyze-SwydoReport.ps1:967 wholesale. The ledger side is correctly id-keyed (Get-SwydoReport.ps1:854 keys trend cells by metric id, and Update-SwydoLedge... |
| `skill/scripts/Analyze-SwydoTrend.ps1:274` | no | The one metric-label site in the trend analyzer, and it has an independent empty-name bug: the guard tests `$null -ne`, which is TRUE for an empty string, so the Get-MetricPart fallback never runs for a blank display name. Once the headline repair makes emp... |
| `skill/scripts/Analyze-SwydoReport.ps1:988` | no | LABEL SITE, and the highest-traffic one. headline[].metric is the client-facing metric name for every WIN/LOSS statement (L1184-1185: "$($pf.name) $($h.metric) $($h.displayCurrent) vs ..."), GAP_UNIT_UNCONFIRMED (L1179, major), ANOM_BUDGET_CONSTRAINED (L119... |
| `skill/scripts/Analyze-SwydoReport.ps1:849` | no | LABEL SITE. Every platforms[].metrics cell's `metric` field. Blank for an empty-named metric, and duplicated across two cells for a collided pair - so the coverage record SKILL.md:44-50 tells the model to read presents two distinct metric ids under one indi... |
| `skill/scripts/Analyze-SwydoReport.ps1:221` | no | LABEL SITES in Get-BreakdownFindings. Four client-facing statements interpolate $primary.name directly. ANOM_PAUSED (L234) is severity=major and force-surfaced, so a blank label ships in a mandatory sentence: "Google Ads: 'Brand Search' stopped ( 0 this per... |
| `skill/scripts/Analyze-SwydoReport.ps1:256` | no | LABEL SITES. ANOM_EFFORT_NO_RESULT (L256) is severity=major and force-surfaced; ANOM_SHARE_MISMATCH (L260) carries requiresDownstreamData=$true and is therefore ALSO force-surfaced regardless of severity. Both statements name two metrics by display name. |
| `skill/scripts/Analyze-SwydoReport.ps1:295` | no | LABEL SITE. ANOM_BRAND_BASELINE's client-facing statement. |
| `skill/scripts/Analyze-SwydoReport.ps1:446` | no | LABEL SITE. metricNames[] is the breakdown table's column-header list that the model renders. It emits duplicate entries for a collided pair and an empty string for a blank-named metric, which is exactly what breaks the index-aligned name->values[name] addr... |
| `skill/scripts/Analyze-SwydoReport.ps1:409` | no | LABEL SITE (the map KEY is a display name). The breakdown row's `values` keys are what the model reads as column names when rendering a row. A blank key would be written if the guard ever let an empty-named metric through (today it cannot, because $cur is a... |
| `skill/scripts/Analyze-SwydoReport.ps1:483` | no | LABEL SITE. buckets[].derivedGaps is a client-readable explanation string. A blank denominator name renders 'CPL: 0 ' with a trailing space and no metric named. |
| `skill/scripts/Analyze-SwydoReport.ps1:500` | no | LABEL SITE. timeSeries[].pacing.metric names the series the client reads month by month. Blank for an empty-named primary. |
| `skill/scripts/Analyze-SwydoReport.ps1:660` | no | LABEL SITES. DISC_RATIO_UNIT (L660) is severity=major and force-surfaced, so a blank metric name ships inside a mandatory sentence accusing the ad platform of an arithmetic error: "Google Ads '' reported $4.20 but the cpa of the total-row components is ...". |
| `skill/scripts/Analyze-SwydoReport.ps1:701` | no | LABEL SITES in Get-DetailSumFindings, three statements. DISC_DETAIL_EXCEEDS_TOTAL (L701) is severity=major and force-surfaced. |
| `skill/scripts/Analyze-SwydoReport.ps1:757` | no | LABEL SITE. RECON_SLICE_OVER_ACCOUNT's client-facing statement. |
| `skill/scripts/Analyze-SwydoReport.ps1:1148` | no | LABEL SITE. The raw display names of cost-per-outcome metrics are collected here and printed verbatim inside GAP_COST_RANKING_NO_VALUE's parenthetical - severity=major AND requiresDownstreamData=$true, so it is force-surfaced twice over and its evidence.ran... |
| `skill/scripts/Analyze-SwydoReport.ps1:1179` | no | LABEL SITES, all reading $h.metric which is the headline label set at L988. GAP_UNIT_UNCONFIRMED and ANOM_BUDGET_CONSTRAINED are severity=major and force-surfaced; the WIN/LOSS statement at L1185 is the report's marquee sentence. Fixing L988 fixes all three... |

## Mechanism notes

MECHANISM, confirmed empirically under PS 5.1 this session (probe, not assumption): - `$row.metrics.$name` is CASE-INSENSITIVE, so 'Conversions'/'conversions' both return the first cell. - `$row.metrics.$name` with a $null or empty name returns $null SILENTLY (no throw). Every empty-display-name metric is therefore invisible to every rule today, not erroring - which is why the repair MAKES a new class of blank labels reachable. - PowerShell's `@{}` hashtable literal IS case-insensitive (so Get-Breakdown's $nameCount at L395-396 correctly counts a case-differing collision), but `Generic.HashSet[string]` is case-SENSITIVE (which is why the analyzer needs the $seenCi dance at L1063). - `[ordered]@{}` Contains is case-insensitive, matching the extractor's Uniq-Key comparer (Get-SwydoReport.ps1:403-409). Any replay of Uniq-Key MUST use [ordered]@{} or it produces a different key sequence. THE ONE-LINE SHAPE OF THE WHOLE CLASS: every affected site SELECTS a metric by its ID (Find-Metric, Get-RatioSpec, Test-ValueMetricId, a `Where-Object {$_.id -eq ...}`, or a Get-MetricPart regex) and then READS its cell by display NAME. They agree only when the id-selected metric happens to be the first holder of its display name. That is the invariant the spec should state, because it explains why several sites fail even when only ONE metric matches the id predicate. SEVERITY CONCENTRATION - five force-surfaced (severity=major or requiresDownstreamData) rules are fed by a display-name read, meaning the closer's 3a gate REQUIRES the wrong claim to appear in the delivered client report: DISC_CROSS_WIDGET (L1228), DISC_RATIO_UNIT (L660), DISC_DETAIL_EXCEEDS_TOTAL (L701), ANOM_EFFORT_NO_RESULT (L256), ANOM_PAUSED (L234), plus GAP_COST_RANKING_NO_VALUE (L1168) and ANOM_SHARE_MISMATCH (L260) via requiresDownstreamData. WHAT THE CLOSER CAN AND CANNOT CATCH: Test-ReportNumbers is a pure membership test of report tokens against facts display strings. A facts document that is internally consistent but wrong about which metric a number belongs to passes at 100% traced. No closer check reaches this class - the repair has to be in the analyzer, and the §7 left-shift for it is a fixture-based regression test in Test-Analyze.ps1 (a widget with two same-named metrics, asserting each id's cell carries its OWN value), not a closer gate. Worth saying explicitly in the spec so the unit is not scoped as 'add a closer check'. THE LANDED FIX IS CURRENTLY DEAD: valuesById is written by Get-Breakdown, excluded from report-template.md:3's quotable whitelist, listed under SKILL.md:40's SKIP list, and never read by Test-ReportNumbers.ps1's Build-FactIndex. Three readers, zero of them read it. Any spec revision that leans on valuesById must land the closer + docs half in the same unit. NOT A SITE, checked and clean: the trend extraction path is already id-keyed end to end (Get-SwydoReport.ps1:854 `$vals[[string]$mets[$j].id]`, ConvertTo-SwydoTrendFacts.ps1:40-49, and Analyze-SwydoTrend's series assembly at L127-135). Analyze-SwydoTrend derives every metric label from Get-MetricPart $mid (L152) rather than a display name - that is the pattern the report analyzer should adopt, and its only leak is the `$null -ne` guard at L274. One latent hazard there for a different unit: `$vals[[string]$mets[$j].id]` in an [ordered]@{} means two metrics with the SAME id (differing only in case) in one monthly widget silently last-write-wins; that is a duplicate-ID hazard, not a display-name one, and is out of this lens. ORDERING NOTE FOR THE REPAIR: Metric-Key must be resolved ONCE per metric per function, not inside per-row loops - Get-Breakdown's Sort-Object script block (L388) and Get-TimeSeries' series loop (L498-499) both evaluate per row, and Resolve-CellKeys is the more expensive half. TESTS THAT WILL MOVE: Test-Analyze.ps1:1264 pins `values` collapsing a duplicate name as an 'unchanged defect'; Test-Analyze.ps1:1290-1292 pins the schemaVersion-2 omit-rather-than-guess branch that Resolve-CellKeys would make unnecessary; Test-Analyze.ps1:1242/1246 pin the breakdown and row key ORDER, so any new emitted field has to be placed deliberately.

## Synthesized scope proposal

# Scope proposal - ANLZ-aCandidTally-1, rev-4 (rebased onto main @ 39def66)

Absolute anchors for the touched files:
`C:/projects/swydee/.claude/worktrees/gracious-pasteur-0e3377/skill/scripts/Analyze-SwydoReport.ps1`,
`.../skill/scripts/Get-SwydoReport.ps1`, `.../skill/scripts/Analyze-SwydoTrend.ps1`,
`.../skill/scripts/Test-ReportNumbers.ps1`, `.../Test-Analyze.ps1`, `.../Test-Extractor.ps1`,
`.../skill/SKILL.md`, `.../skill/report-template.md`.
Body prose below uses repo-root-relative `file:line` per AGENTS.md §6.

---

## 1. Now OUT of scope, because main already did it

**O1. Extractor `cellKey` emission.** `Get-SwydoReport.ps1:711-719` stamps `metrics[].cellKey` from
`Get-UniqKeySeq` (`:363-376`). The pre-rebase S1 is landed fact, not work. Its acceptance criteria are
already pinned at `Test-Extractor.ps1:94-97`.

**O2. The `schemaVersion` 2 -> 3 bump.** `Get-SwydoReport.ps1:1093` and `:1167` both write `3`; the
analyzer gate at `Analyze-SwydoReport.ps1:907` accepts `@(2,3)`. Non-goal section 3's "the bump from 2
to 3" is history. The marker does not move again in this unit.

**O3. The extractor-side wrong-value path.** `Test-Extractor.ps1:95` is the cell-key parity gate and
`:97` already pins that a `cellKey` read returns the SECOND metric's own value. A second such gate is
duplication.

**O4. The breakdown collision channel.** `valuesById` ships at `Analyze-SwydoReport.ps1:411-436`, gated
on `$nameCount` at `:396`, marked by `valuesByIdScope` at `:446`, pinned at `Test-Analyze.ps1:1274-1280`
and `:1384-1387`. The `values`-vs-`valuesById` independence fix (`:1395-1396`) is landed. S5 as written
in rev-3 is withdrawn; see D-1.

**O5. The matrix's existence, ranks, reason ladder, `aggClass`, `basis` and conflict machinery.** All of
`Analyze-SwydoReport.ps1:791-897` is landed. This unit changes exactly two lines inside it (`:812`,
`:849`) plus the F-1 identity fix, and inherits the rest.

**O6. `meta.factsVersion` 1 -> 2 and `meta.matrixVersion` mint at 1.** Both already at
`Analyze-SwydoReport.ps1:1276`. Rev-3's "canonicalVersion 2 to 3" arithmetic and its Migration line "if
P5 later lands it takes 3 to 4" are both stale and inverted; P5 landed first.

**Stale anchor map the rebase must apply throughout the spec:** `:738` -> `:967`; `:931` -> `:1211`;
`:996` -> `:1276`; `:765`/`:768` -> `:994`/`:997`; `:839-843` -> `:1109-1124`; `:397`/`:401` ->
`:404`/`:407`/`:409`/`:446`; extractor `:516`/`:525` -> `:711-719`/`:729`. A10's claim of two version
pins is wrong; there are five (`Test-Analyze.ps1:459`, `:460`, `:728`, `:1300`, `:1301`) plus
`:1409` for `factsVersion`.

---

## 2. The S-items that remain

**S1 - single-source the key space.** Move `Uniq-Key` (`Get-SwydoReport.ps1:403-409`) and
`Get-UniqKeySeq` (`:363-376`) into a new `skill/scripts/_KeySpace.ps1` containing nothing else, and
dot-source it by `$PSScriptRoot` from both `Get-SwydoReport.ps1` and `Analyze-SwydoReport.ps1`.
Verifiable: `Test-Extractor.ps1` stays at 288 passed without editing its dot-source line, because the
extractor loads the new file at define time. This replaces rev-3's `Uniq-CellKey` replay, which was a
second copy of a single-source contract and would have required a drift gate (AGENTS.md section 7,
section 12). See D-4 for the rejected alternatives.

**S2 - `Resolve-CellKeys($w)`.** Stamp `cellKey` onto every record in `$w.metrics` when absent, by
calling `Get-UniqKeySeq` over the metric list. Idempotent; a schemaVersion-3 document is left untouched.
Verifiable: on a schemaVersion-2 fixture the stamped sequence equals the extractor's own stamp on the
identical metric list, asserted in one test that dot-sources both scripts `-DefineOnly`.
This is load-bearing, not optional: `Test-Analyze.ps1:405` hardcodes `schemaVersion=2` in every e2e
fixture, so without the replay not one existing end-to-end test exercises a cell-key read.

**S3 - `Metric-Key($m)` and `Metric-Label($m)`.** `Metric-Key` returns `[string]$m.cellKey` when present
and non-empty, else `[string]$m.name`. `Metric-Label` returns `$m.name` when not null-or-whitespace,
else `Metric-Key $m` (which `Uniq-Key` sets to the metric id for a blank name, or `col<idx>` when the id
is also blank). Verifiable by unit assertions over three record shapes: named, blank-named, blank name
and blank id. Do NOT overload `Row-Cur`/`Row-Cmp` to accept a metric record: `Analyze-SwydoReport.ps1:428`
passes a raw key string and `:743` passes another widget's metric, so `(row, key)` is the one signature
serving all callers.

**S4 - repoint every by-display-name cell read onto `Metric-Key`.** Sites, resolved once per metric per
function and never inside a per-row loop: `:219`, `:220`, `:224`, `:228`, `:248`, `:252`, `:273`, `:281`,
`:388` (hoist out of the `Sort-Object` block), `:481`, `:498`, `:499`, `:502`, `:624`, `:641`, `:689`,
`:691`, `:735`, `:743` (resolve `$om[0]` against `$ow`, not `$w`), `:812`, `:967`, `:1133`, `:1211`.
Explicitly EXCLUDED: `:404`, `:407`, `:409` - see S6. Verifiable: after the change, a grep for
`metrics\.\$\(\$[a-z]+\.name\)` and for `Row-Cu?r? \$[a-z]+ \$[a-z]+\.name` over the file returns zero
hits outside `Get-Breakdown`'s `values` block. The site list is inherited from the sites lens; re-run
that grep mechanically at implementation time rather than trusting the enumeration.

**S5 - WITHDRAWN.** Rev-3's "repoint the breakdown output onto the resolved key" contradicts
ANLZ-aUniformLattice-8 D1/D6 and reds four shipped pins. Replaced by S6.

**S6 - `values` stays display-name-keyed; its write becomes first-wins.** At `Analyze-SwydoReport.ps1:409`,
skip the write when the key is already present. Today the loop is last-write-wins on the key while
`$cur` at `:404` always reads the FIRST holder's cell, so `values['Cost']` publishes metric 1's number
formatted and typed with metric 2's id and unit. `type` is authoritative for the closer's same-type
match (`Test-ReportNumbers.ps1:226`, `Find-Candidates` at `:279`), so a micros/count collided pair
publishes a wrong display string as a legitimate tracing candidate. Verifiable: `Test-Analyze.ps1:1274`,
`:1293`, `:1384` and `:1395` all stay green (each asserts a COUNT, which first-wins preserves), and a new
micros/count collided fixture yields a cell whose `display`, `unit` and `type` all describe the metric
that owns the number.

**S7 - close the blank-display-name hole in `Get-Breakdown`.** Widen the `valuesById` gate at `:422` from
`collided` to `collided OR blank display name`, and emit `metricNames[]` at `:446` via `Metric-Label`.
A lone blank-named metric today has `nameCount = 1`, so it gets no `valuesById` entry, and
`Row-Cur $r ''` returns `$null`, so it gets no `values` entry either - it vanishes from the table while
`metricNames[]`/`metricIds[]` still advertise it, breaking the index-aligned addressing contract the
`:412-417` comment depends on. Verifiable: a blank-named-metric fixture produces a non-blank
`metricNames[i]` and a `valuesById[<id>]` entry, and `Test-Analyze.ps1:1401` and `:1405-1407` stay green
(their fixtures have unique, non-blank names).

**S8 - matrix repair, two lines plus F-1.** Repoint `:812` onto `Metric-Key`. Fix F-1: `$out.metric` is
set at `:849` from `$g[0].metric` and is never re-set after `$m` is reassigned to `$win.metric` at `:863`,
so the cell publishes one column's name with another column's number - precisely what the `:860-862`
comment claims to prevent. Set the label from the winner, via `Metric-Label`. Verifiable: a fixture
with a rank-2 table declaring `google-adwords:clicks` as `Clicks` followed by a rank-1 KPI declaring it
as `Clicks (all)` yields matrix `metric` equal to headline `metric`; and `Test-Analyze.ps1:1145`
("matrix and headline agree cell-for-cell") re-asserted over both collision fixtures becomes the
mechanical prohibition on a one-sided repair.

**S9 - disclosure.** See section 5.

**S10 - version markers.** See section 4. One literal, `Analyze-SwydoReport.ps1:1276`.

**S11 - trend guard.** `Analyze-SwydoTrend.ps1:274` tests `$null -ne $cell.metric`, which is TRUE for an
empty string, so the `Get-MetricPart` fallback never runs. Change to
`[string]::IsNullOrWhiteSpace([string]$cell.metric)`. Verifiable: a hand-built `-PeriodKpiFacts` fixture
with `metric=''` renders `google-adwords 'clicks': ...` rather than `google-adwords '': ...` in all six
`RECON_TREND_COVERAGE` statements (`:279`, `:283`, `:288`, `:294`, `:299`, `:305`) and in
`RECON_TREND_MISMATCH` (`:320`). See D-2 - this is hardening, not the fix.

**S12 - docs.** `skill/SKILL.md:38-40`: keep `valuesById` in the SKIP list and state WHY it is safe to
skip after S6 (the surviving `values` cell is internally consistent), plus the collided-column rule -
when `metricNames[]` holds a duplicate, `values[name]` belongs to the FIRST holder and the second
metric's number is not quotable. `skill/SKILL.md:44-50`: no change to the coverage-record framing.
`skill/report-template.md:3`: no change to the quotable whitelist; add one sentence stating that
`breakdowns[].rows[].valuesById` is deliberately NOT quotable, so a later session does not "fix" the
omission without doing the closer half.

**S13 - tests.** See section 6.

**Non-goals, recorded so a later session does not re-open them:**
indexing `platforms[].metrics` in `Build-FactIndex` (rejected by
`memory/analysis/builds/2026-08-04-ANLZ-aUniformLattice/spec/2026-08-04-spec-aUniformLattice-6.md:143`,
and the matrix's non-indexing is a deliberate guard property); indexing `valuesById` in the closer
(deferred, D-3); widening the matrix conflict predicate to same-widget losers (accepted residual, D-5).

---

## 3. The flip set

| Surface | Site | Today on main | After |
|---|---|---|---|
| `headline[<id>]` value keys | `Analyze-SwydoReport.ps1:967` | cell fetched by `$m.name`; a collided pair publishes the FIRST holder's number under BOTH ids | fetched by resolved key; each id carries its own number |
| `headline[<id>]` presence, gained | `:967-968` | blank-named metric: `$tr.metrics.''` is `$null`, `continue`, no entry ever | entry present, keyed by the metric id |
| `headline[<id>]` presence, lost | `:967-969` | a metric whose own cell is a non-numeric echo publishes a same-named sibling's number | scalar guard drops it; entry absent |
| `headline[<id>].metric` label | `:988` | `$m.name`; blank for a blank-named metric | `Metric-Label`, falls back to the resolved key |
| `platforms[].metrics[<id>]` value | `:812` | same by-name read, byte-identical to the headline by spec-4 D3 | resolved-key read |
| `platforms[].metrics[<id>]` value <-> reason | `:812`, `:830`, `:850` | a borrowed cell ranks, so the cell publishes `current`/`method`/`basis` with NO reason | `reason='no-usable-cell'` and no value keys, and the inverse; `no-usable-cell` is the only reachable token either way |
| `platforms[].metrics[<id>].scope`/`.method`/`.contributingWidgetIds` | `:813-816`, `:873-877` | rank contest decided on a borrowed cell (a rank-1 KPI beats a rank-2 total on a number it does not own) | contest decided on own cells; `account`/`kpi-widget` can flip to `table-total:<dim>`/`total-row` |
| `platforms[].metrics[<id>].conflict` | `:885-894` | false `same-rank-disagreement` (both contributions share ONE borrowed cell object, so `$sameRankDiff` is empty or spurious); real disagreements masked | conflicts both appear and disappear; `reason` can move between `basis-mismatch` and `same-rank-disagreement` because `Get-BasisVersion` keys on the winner |
| `platforms[].metrics[<id>].metric` label | `:849`, `:863` | `$g[0].metric` name, never re-taken from the winner (F-1) | winner's `Metric-Label` |
| `breakdowns[].rows[].values[<name>].display`/`.type` | `:404-409` | last-write-wins: metric 1's NUMBER formatted and typed with metric N's id and unit | first-wins: number, unit and type all describe one metric |
| `breakdowns[].rows[].valuesById` | `:422-435` | emitted only for a collided name, and only when `cellKey` is present | also for a blank display name; the schemaVersion-2 omit branch at `:425-427` lifts once S2 lands |
| `breakdowns[].metricNames[]` | `:446` | raw `$_.name`; blank entry for a blank-named metric | `Metric-Label`; `metricIds[]` unchanged |
| breakdown row ORDER and top-N membership | `:388` | sort key read by `$orderMet.name`, so the wrong column can choose which 20 rows ship | resolved key; a different row set can be selected, changing closer-indexed `values` content |
| `timeSeries[].buckets[].derived.*` | `:481` | numerator/denominator read by name; publishes a wrong cost-per-lead that traces clean | resolved key |
| `timeSeries[].pacing.*` | `:498`, `:499`, `:500`, `:502` | the whole series, `netChange`, `maxVsMinRatio` and the trend verdict can be another metric's numbers under `$primary`'s unit | resolved key; `pacing.metric` via `Metric-Label` |
| findings, value-carrying | `:248`, `:252`, `:271-281`, `:624`, `:641`, `:689`, `:691`, `:735`, `:743`, `:1133`, `:1211` | fabricated or suppressed `DISC_CROSS_WIDGET`, `DISC_RATIO_UNIT`, `DISC_DETAIL_EXCEEDS_TOTAL`, `ANOM_EFFORT_NO_RESULT`, `ANOM_PAUSED`, `ANOM_BRAND_BASELINE`, `GAP_COST_RANKING_NO_VALUE`, `RECON_SLICE_OVER_ACCOUNT` | computed from each metric's own cell |
| findings, label-only | `:221`, `:232`, `:234`, `:239`, `:256`, `:260`, `:295`, `:483`, `:660`, `:701`, `:705`, `:714`, `:757`, `:1148`, `:1165-1171`, `:1179`, `:1184-1188`, `:1199` | blank or duplicated metric names inside force-surfaced client-facing sentences | `Metric-Label` at every interpolation; `:1148` dedupes on the resolved key, not the label |
| `GAP_NO_ACCOUNT_TOTAL` membership and `byReason` | `:1085`, `:1095-1097` | a metric absent from the headline counts as missing; a borrowed matrix VALUE takes the `attributed-to-other-platform` branch and emits a false reason string | membership moves both ways; the finding NEWLY fires for a metric that today publishes a borrowed number, with `byReason` gaining `no-usable-cell` counts |
| trend facts `RECON_TREND_*` | `Analyze-SwydoTrend.ps1:309`, `:318-321` | consumes the headline value wholesale; gate 3b at `:293` cannot catch it, because `unit` comes from the DECLARED metric while `current` came from the wrong cell, so a mismatch is guaranteed on every collided metric with ledger history | correct input; new iterations appear for metrics that had no headline cell |
| `meta` markers | `Analyze-SwydoReport.ps1:1276` | `factsVersion=2; canonicalVersion=3; matrixVersion=1` | `factsVersion=2; canonicalVersion=4; matrixVersion=2` |

Two flips deserve callouts in the spec body. First, the matrix today can publish a dimension echo's
neighbouring number as a measured account value; the repair DELETES that number rather than correcting
it, which is a coverage regression that is nonetheless the honest outcome. Second, a scope/method flip
is a first-class flip-set member, not merely a value flip - the rank contest itself moves.

---

## 4. Version decision

**`meta.canonicalVersion` 3 -> 4. Mandatory.** The marker names the headline algorithm
(`.claude/SESSION-KICKOFF.md:171-181`; `memory/analysis/DECISIONS.md:8`, ANLZ-aGovernedCanon-3;
`spec-aUniformLattice-8.md:96-98`), the rule is global and non-flip-conditional (U9 D6, echoed in the
comment above `Test-Analyze.ps1:459`), and `:967` changes what the headline publishes.

**`meta.matrixVersion` 1 -> 2. Mandatory, and rev-3 could not have known it.** The same two ratified
statements that fix `canonicalVersion` to the headline also fix `matrixVersion` to the matrix, both
phrased negatively - `spec-aUniformLattice-8.md:96-98` declines to move it only because the matrix
algorithm was "also untouched". `:812` is the matrix algorithm, and repointing it changes matrix cell
values, rankedness, scope, method and conflict entries. Declining the bump while bumping
`canonicalVersion` is not defensible: both markers would be moving, or not, for the identical reason -
a key-resolution change under an unchanged reduce. Ratify the positive rule explicitly in the rebased
spec, because today it exists only as an inference from two negative statements.

**`meta.factsVersion` stays 2.** It names the facts SHAPE and moves on a subtractive change
(`spec-aUniformLattice-8.md:19`, `:92-98`); additive keys explicitly do not move it
(`spec-aCanonicalTotal-1.md:73`, D10). Everything this unit adds is additive: the `canonical` disclosure
keys, and any new `valuesById` entry. Nothing is removed or renamed. This is the direct consequence of
withdrawing S5 - renaming published `values` keys WOULD have been a shape change by spec-8 D4's own
standard, and would additionally have made `valuesById` dead one commit after it shipped.

**Extraction `meta.schemaVersion` stays 3.** Unchanged per O2. Note the structural trap:
`Test-Extractor.ps1:154-158` regexes the extractor SOURCE for `schemaVersion=\d+`, asserts exactly two
matches and both `=3`. S1 moves functions out of that file; adding any line containing that literal
(including a comment) reds the leg.

**Trend `meta.factsVersion` stays 1, and it is a separate numbering line.** `Analyze-SwydoTrend.ps1:339`
writes `1` and emits no `canonicalVersion`/`matrixVersion`, so a trend-facts consumer cannot today
distinguish repaired from unrepaired numeric input - and `-PeriodKpiFacts` is a FILE PATH
(`Analyze-SwydoTrend.ps1:25`, `:208-209`), so the input can be a pre-repair archive. Recommendation
(OD-2): echo the source document's `canonicalVersion` into the trend `meta` as one additive key, and
state in the spec that the trend counter is independent of the report counter, or a future reader will
"align" them.

**Pins that go red on the bump and must move with it:** `Test-Analyze.ps1:459`, `:460`, `:728`, `:1300`,
`:1301`. Nothing outside those and the writer reads either marker - no product code, and the closer is
version-blind by construction (`grep` for all four markers over `skill/scripts/Test-ReportNumbers.ps1`
returns zero hits). `skill/SKILL.md` names no facts-side version literal, which resolves rev-3's open
"only if it names the current canonicalVersion" to no work on version grounds.

**OD-5, raised by this synthesis and by none of the four lenses.** S6 changes a published breakdown
display string, and the marker taxonomy has no name for the breakdown algorithm. The case is reachable
independently of the other two markers: a dimensioned widget with no total row feeds neither the
headline nor the matrix, so a breakdown-only flip would ship under an unchanged marker set.
Recommendation: mint `meta.breakdownVersion = 1` alongside the change, using the same
absence-is-the-old-version convention already ratified for `rowKey` (`Analyze-SwydoReport.ps1:439-441`,
"an absent key means this document predates row keys"). This is the weakest-supported item in the
proposal; the alternative is to record the unmarked breakdown flip as an accepted residual.

---

## 5. Where the disclosure lives, and why it cannot become a tracing candidate

**Home: `headline[<id>].canonical.<newKey>`, built at `Analyze-SwydoReport.ps1:994`, mirroring
`canonical.supersededWidgetId` at `:997`. Mirrored onto the matrix cell at `:849`ff.**

**Shape - two keys, no numbers.** `canonical.keyBasis`, one of `display-name` or `cell-key`, where
`cell-key` is emitted only when the metric's display name was ambiguous in its widget; and
`canonical.ambiguousWith`, an array of the OTHER metric ids sharing that display name. This is a
property of the INPUT, not of the version delta, so it is stable and idempotent across reruns. Rev-3's
framing ("disclose each flipped cell") is only computable by also evaluating the old display-name read;
the analyzer may compute it, but must never publish the superseded number.

**Evidence it cannot become a tracing candidate, read directly out of `Build-FactIndex`
(`skill/scripts/Test-ReportNumbers.ps1:195-266`):**

1. `:212-219` reads exactly three NAMED properties off `$p.headline.$hk` - `displayCurrent`,
   `displayPrevious`, `displayDelta`. It never enumerates the headline cell's property names, so
   `canonical` is never walked. `canonical.display` reaches the bag today only because `:994` sets it
   byte-equal to `displayCurrent`.
2. `platforms[].metrics` is not indexed at all. No loop between `:206` and `:243` touches `$p.metrics`;
   the substring `metrics` does not occur in the file.
3. `rows[].valuesById` is not indexed - `:224` walks `$row.values` only.
4. The indexed containers are exactly: headline's three named display properties (`:215-217`),
   `breakdowns[].rows[].values[].display`/`displayPrevious`/`delta` (`:226-228`),
   `timeSeries[].buckets[].derived.*` and `pacing.series[].display`/`netChange` (`:235-239`),
   findings `statement` plus every `evidence.*` into `byFid` (`:251-252`), and `meta.annotations[].text`
   into `byAnnotation` (`:262`). A disclosure that stays out of all five is closer-inert by
   construction.

**Existing pins the shape satisfies.** `Test-Analyze.ps1:451` checks `contains` for five canonical keys,
not an exact set, and `:452` bans only `value`, `basisVersion`, `synthesizedFrom` - so a new canonical
key passes as long as it is not named `value` and carries no number, and `:450`
(`canonical.display -eq displayCurrent`) still holds. `Test-Analyze.ps1:1192` -
`(($c6 | ConvertTo-Json -Depth 10) -notmatch '250')` - independently forbids a matrix cell from carrying
a superseded value, so the matrix mirror must also be ids-only.

**Correction to rev-3's A8.** "Neither a finding nor `meta.annotations`" is too strong. The real
constraint is NO METRIC VALUE IN AN INDEXED CONTAINER, not "no finding". `GAP_HEADLINE_SOURCE_CHANGED`
(`Analyze-SwydoReport.ps1:1109-1124`) is a shipped, ratified, findings-channel roll-up whose in-code
comment states the rule: ids plus count only, no metric values echoed; U9 D4 FP-3 argued its safety as
"structurally impossible - there is no metric value to trace" and pinned it (U9-T11).

**OD-1, recommended YES.** Copy that shape for one info-severity per-provider roll-up naming the metric
ids whose display names were ambiguous plus a count-as-string. A `canonical`-buried key gives the user
no visible signal that the repair fired; the roll-up does, at a cost of one `byFid` candidate per count
string, with ratified precedent. Left-shift gate, per `spec-aUniformLattice-6.md:175-176` (AC7):
dot-source `Test-ReportNumbers.ps1 -DefineOnly`, run `Build-FactIndex` over the collision fixtures and
assert (a) no candidate equals any superseded value and (b) the per-platform candidate count equals the
pre-change count plus exactly the intended delta.

**Breakdown-side flips, if any disclosure is wanted for them:** put the record on the breakdown BLOCK
object (`breakdowns[].<key>`), never inside `rows[].values`, because `:224` walks `values` property
names while `:221-231` never walks siblings of `rows`. Note this reds the block key-order pin at
`Test-Analyze.ps1:1242`, which must be updated deliberately.

---

## 6. Test plan

**Dropped from rev-3 as redundant against main:**

- Duplicate display names at the extractor and row-map layer - covered by `Test-Extractor.ps1:71-72`,
  `:87-88`, `:94-97`.
- The cell-key parity gate - `Test-Extractor.ps1:95` IS that gate, and `:97` already pins the
  wrong-value path.
- Breakdown block/row key order and `rowKeyBasis` - `Test-Analyze.ps1:1242`, `:1246`, `:1253-1255`.
- Byte-identity pins on `values` - `Test-Analyze.ps1:1250-1252`, `:1274`, `:1384`, `:1395`.
- The pre-cellKey fallback AT THE BREAKDOWN LAYER - `Test-Analyze.ps1:1290-1293`; the `col<idx>` half is
  `Test-Extractor.ps1:90`.
- Rev-3's `Uniq-CellKey` replay-parity suite, dropped with the replay itself under S1/D-4.

**Must survive the rebase, because nothing on main asserts them.** Note the load-bearing gap: `Hl` and
`Mx` are never called on any collided-display-name fixture (`$p4b`, `$p4c`, `$l8a`, `$l8b`), so the
headline and matrix defects have ZERO assertions today.

1. Headline on a collided display name - each id's cell carries its OWN value.
2. Matrix contribution on a collided display name, plus `Test-Analyze.ps1:1145`'s cell-for-cell
   agreement re-asserted over both collision fixtures, which is the mechanical prohibition on a
   one-sided repair.
3. Matrix value <-> reason in BOTH directions, asserting `reason='no-usable-cell'` and the absence of
   the value keys on the losing direction.
4. Matrix rank-contest flip: a rank-1 KPI whose own cell is an echo drops out of `$ranked`, the rank-2
   table wins, and `scope`/`method`/`contributingWidgetIds` all move.
5. Matrix conflict appearing AND disappearing; a false `same-rank-disagreement` is deleted, a genuine
   one is minted. These are the first cases that can manufacture a false conflict, so the existing
   "conflict honesty" block at `Test-Analyze.ps1:1340-1366` needs collision-fixture companions.
6. F-1: winner-sourced cell label, with a fixture where `$g[0] -ne $win` (the `:1365` pin's fixture has
   them equal, which is why it does not catch this).
7. Case-only-differing display names, untested anywhere today. The extractor's `[ordered]@{}`
   `Contains` is case-insensitive so `Conversions`/`conversions` IS a collision and the second gets
   suffixed, while the analyzer's `$tr.metrics.$name` is case-insensitive and returns the first.
8. Blank display name with a NON-NULL id, untested anywhere today (`Test-Extractor.ps1:90` covers only
   name AND id both null). Must exercise a blank-named metric reaching a WIN statement
   (`:1184-1188`) and at least one force-surfaced finding, since that is where a blank label ships.
9. The schemaVersion-2 fallback at the HEADLINE and MATRIX layer, which S2 turns from "omit" into
   "resolved".
10. The extractor -> analyzer seam: real `Normalize-Widget` output fed into `RunAnalyze`. Nothing does
    this today, and every e2e fixture hardcodes `schemaVersion=2` at `Test-Analyze.ps1:405`, so a repair
    gating on `meta.schemaVersion` would pass every existing test and still be wrong. Reuse the existing
    harness (`Test-Extractor.ps1:14-16`, `W`/`Node`/`FieldsConn`) rather than writing a second `NW`
    helper, which would be a section 12 duplicate. Mechanically safe: the two scripts share zero
    function names and zero `$script:` names. One caveat: `Normalize-Widget` reads `$script:secMap` and
    `$script:secHidden`, seeded at `Test-Extractor.ps1:10` and reset at `:138`/`:141`, so any reuse site
    must seed them. Preferred home is `Test-Extractor.ps1` beside the existing harness.
11. Finding SIDE-EFFECTS of the value change. On the `l8b` fixture (`Test-Analyze.ps1:1392`) a cell-key
    read makes the total 700 against a shown sum of 250, newly firing `RECON_ROW_REMAINDER`. No
    assertion pins the finding set of any collided-name fixture in either direction; add one per
    collision fixture.
12. `GAP_NO_ACCOUNT_TOTAL` newly FIRING for a metric that today publishes a borrowed number, with
    `byReason` reading `no-usable-cell=N`. The current inventory records only the opposite move.
13. Closer candidate arithmetic over the collision fixtures - the two-legged AC7-shaped gate described
    in section 5.
14. One trend `RECON_*` pass over repaired facts, exercising a metric that previously had no headline
    cell, so `Analyze-SwydoTrend.ps1:274` is proven. `Test-TrendAnalyze.ps1:146` builds its fixture by
    hand with `metric='Sessions'` hardcoded and asserts no version literal, so nothing in that suite
    reds on a bump - this new case is the only coverage the trend consumer gets.
15. S6: a micros/count collided pair, asserting the surviving `values` cell's `display`, `unit` and
    `type` all describe the metric that owns the number.

**Suite counts on main, measured at 39def66:** `Test-Analyze.ps1` 619 passed,
`Test-Extractor.ps1` 288 passed, `Test-Closer.ps1` 129 passed. A unit is additive on its own suite's
count and leaves every other count unchanged. Note that on a green run `$LASTEXITCODE` is empty - the
suites call `exit 1` only on failure - so assert the failure path, never a `0` that is never written.
While touching `Test-Analyze.ps1`, fix the stale header comment at `:649` claiming Test-Closer is 119.

---

## 7. Where the lenses genuinely conflict, and which wins

**D-1. The breakdown repoint (S5). `sites` versus `contracts`.**
`sites` wants `values` read via `Metric-Key` with a first-wins write; `contracts` wants S5 withdrawn
entirely as a contradiction of just-landed ANLZ-aUniformLattice-8 D1/D6.
**Contracts wins on the KEY, sites wins on the CELL CONTENT.** `values` stays display-name-keyed and its
read stays by display name, because keying by resolved key reds `Test-Analyze.ps1:1274`, `:1384`, `:1293`
and reading by resolved key reds `:1395`, renames published keys (a shape change, hence a `factsVersion`
bump), makes `valuesById` dead one commit after it shipped, and breaks the index-aligned
`index -> name -> values[name]` two-step that `spec-aUniformLattice-8.md:102-104` and `skill/SKILL.md:38-40`
depend on. But `sites` identified a real residual that `contracts` did not address: the surviving cell's
`type` and `unit` come from the LAST metric while its number comes from the FIRST, and `type` is
load-bearing for the closer's match. S6 is the reconciliation - first-wins keeps every key count
identical while making one metric own the whole cell. Neither lens proposed exactly this.

**D-2. `Metric-Label` placement for the trend path. `sites` versus `contracts`.**
`sites` proposes patching `Analyze-SwydoTrend.ps1:274`; `contracts` calls that "fixing the symptom in the
wrong file" and puts `Metric-Label` at `Analyze-SwydoReport.ps1:988`.
**Contracts wins on the primary fix; `sites`' patch is retained as one-line hardening.** `:988` is the
fix, and `contracts` is right that a same-version pipeline can never produce a blank
`headline[].metric` once it lands. The retention argument is one neither lens made: `-PeriodKpiFacts` is
a FILE PATH (`Analyze-SwydoTrend.ps1:25`, `:208-209`), so the trend analyzer can be handed a facts
document written by any analyzer version, and the guard is objectively wrong regardless
(`$null -ne ''` is `$true`). Record it as hardening, not as the repair, so a reader does not conclude
the trend file owns the defect.

**D-3. Indexing `valuesById` in the closer. `sites` versus `contracts`.**
`sites` calls the landed fix "currently dead" - written by `Get-Breakdown`, excluded from
`report-template.md:3`, on `SKILL.md:40`'s SKIP list, never read by `Build-FactIndex` - and wants
`Test-ReportNumbers.ps1:224` widened, arguing it is purely additive and can only turn a false block into
a pass. `contracts` cites `spec-aUniformLattice-6.md:143` rejecting closer indexing "for completeness"
as a measurable weakening of the guard.
**Deferred out of this unit; contracts' caution wins for now, on a narrower argument than either lens
made.** `sites`' failure mode (a) - the correct number is not a tracing candidate, so a report quoting
it is blocked - is UNREACHABLE today, because `SKILL.md:40` forbids the model from reading `valuesById`
and `report-template.md:3` excludes it from the quotable whitelist. Failure mode (b) - the wrong
`values` string traces clean - is what S6 fixes at the source. The coherent end state is: the collided
second metric's number exists in facts, is honest, and is deliberately not quotable at row level. S12
writes that down. Open a backlog row for the promote-`valuesById` unit (closer plus both docs, landed
together) rather than half-landing it here.

**D-4. How the analyzer gets a cell key for a schemaVersion-2 document.**
`sites` and `tests` both assume rev-3's `Uniq-CellKey` replay, and `tests` correctly notes it is a
second copy of a single-source contract needing a cross-file parity gate that does not exist.
**Neither variant of "replay" wins; S1's single-sourcing does.** Three options were evaluated.
(A) Replay plus parity gate - the rev-3 design, now dominated, because a drift gate is strictly more
machinery than not duplicating. (B1) `Analyze-SwydoReport.ps1` dot-sources `Get-SwydoReport.ps1 -DefineOnly`
- mechanically feasible (no mandatory params, `-DefineOnly` returns at `Get-SwydoReport.ps1:953` before
any run body, both scripts set `$ErrorActionPreference = "Stop"`, zero function-name and `$script:`-name
collisions), but it drags the websocket state block at `Get-SwydoReport.ps1:55-73` and the 1 MB buffer
allocation into the analyzer's load path for no reason. (B2) Extract the two functions into
`skill/scripts/_KeySpace.ps1` containing nothing else, dot-sourced by both - recommended, because it is
the section 12 shared-core shape, has no side effects, and keeps `Test-Extractor.ps1` green untouched.
Whichever is chosen, one AC guards it: a no-collision e2e fixture's facts must stay byte-identical
except for the version markers.

**D-5. F-2, the same-widget disagreement. Raised by `matrix` alone; no other lens covers it.**
`Analyze-SwydoReport.ps1:885` filters losers with `$_.widgetId -ne $win.widgetId`, and
`contributingWidgetIds` at `:877` is `Select-Object -Unique` on widget ids. One widget declaring the same
metric id twice under two display names today reads one cell twice, so nothing is lost; AFTER the repair
the two columns carry genuinely different numbers and the second is dropped with no `conflict`, no
distinct id in `contributingWidgetIds`, and no `valuesById` fallback (which is breakdown-scoped). The
headline drops it too, first-wins at `:970-972`.
**Recommendation: accept and record, do not widen the predicate in this unit.** Widening it to
same-widget losers would emit `losingWidgetIds` naming the winning widget, which reads as nonsense, and
it changes conflict semantics beyond the flip set. Per AGENTS.md section 7, an ungateable residual
becomes a DOCUMENTED check: add an AC pinning that the second column is dropped without a conflict, so
the residual is asserted rather than latent, and open a backlog row for the widening.

**Non-conflicts worth recording.** All four lenses agree the closer cannot catch this class at all -
`Test-ReportNumbers.ps1` is a pure membership test, and a facts document that is internally consistent
but wrong about which metric a number belongs to passes at 100% traced. The section 7 left-shift is
therefore a fixture-based regression test in `Test-Analyze.ps1`, NOT a closer gate; scope the unit
accordingly. All four also agree on the one-line shape of the whole defect class, which the spec should
state as its invariant: **every affected site SELECTS a metric by its ID and then READS its cell by
display NAME; the two agree only when the id-selected metric happens to be the first holder of its
display name.** That sentence explains why several sites fail even when only one metric matches the id
predicate.

## Lens reports

=== LENS matrix ===
## Bottom line

The matrix carries **the same defect, at one site**: `C:/projects/swydee/.claude/worktrees/gracious-pasteur-0e3377/skill/scripts/Analyze-SwydoReport.ps1:812`

```powershell
$c = $tr.metrics.$($m.name)   # by display NAME, byte-identically to the headline (see D3)
```

P3 shipped that knowingly and pre-authorised the switch. Spec `-4` D3 (`memory/analysis/builds/2026-08-04-ANLZ-aUniformLattice/spec/2026-08-04-spec-aUniformLattice-4.md:131-135`):

> **The total-row cell is fetched by `$m.name`, byte-identically to `:793`.** P1 shipped `metrics[].cellKey`, which is the correct key and fixes the duplicate-display-name wrong-value path, but switching to it changes VALUES and therefore belongs to the phase that owns a flip set. P3 deliberately reproduces the headline's lookup so matrix and headline agree cell-for-cell, and inherits its known defect knowingly. Recorded here so the later switch is a decision, not a discovery.

aCandidTally **is** that phase. Its S3 currently names only `:738` and `:931` (pre-rebase anchors; now `:967` headline and `:1211` `DISC_CROSS_WIDGET`). `:812` is a third direct `$tr.metrics.$name` site and is absent from the whole spec. Only **two** matrix lines move: `:812` (the lookup) and `:849` (the label — see F-1 below). `Reduce-MatrixCell` never reads a cell by name; it consumes `$rec.cell`. Per A1 the `Resolve-CellKeys` stamp must run inside `Get-MatrixContributions` (`:791`), the only place holding `$w` alongside `$m`.

---

## 1. Which matrix fields change

The repair changes exactly one thing per contribution: whether `$rec.cell` is populated and therefore whether `$rec.rank` is non-zero (`:811-817`). Group membership is built from *declarations*, not from the lookup, so it never changes.

**Cannot change** — `id`, `observedOnWidgetIds` (`:842`), `coverageBasis`, `period`, and `reason`'s *value* when a reason cell stays a reason cell (`Get-MatrixReason` reads only `blended`/`hidden`/`eligible`/`hasTotalRow`/`dimensioned` flags + `aggClass`; none is lookup-derived).

**Can change** — `current`, `previous`, `deltaPct`, `displayCurrent`, `displayPrevious`, `displayDelta`, `hasComparison`, `scope`, `method`, `contributingWidgetIds`, `conflict` (whole block), and — because the reason path reads `$g[0]` (`:851-853`) while the value path reads `$win` (`:870-876`) — also `type`, `unit`, `currency` and `basis.basisVersion` whenever a cell crosses the value/reason line with `$g[0] -ne $win`.

**`aggClass` never changes** (`:841`, computed from `$g[0].metric` before the winner is picked). That is worth noting because on a value cell `aggClass` is derived from `$g[0]`'s unit while `unit`/`basis`/`type` come from the winner's — a pre-existing split the repair makes reachable on more cells.

## 2. Value ↔ reason: yes, both directions, and the token is always `no-usable-cell`

`Get-MatrixReason` is only consulted when `$ranked.Count -eq 0` (`:850`). For a post-repair lookup to succeed the contribution must be `eligible` **and** have a total row, which is precisely rung 3's predicate at `:830`; rungs 1 and 2 require *no* eligible contribution, so they are skipped, and rungs 4–7 sit below rung 3. Symmetrically, a cell that loses its value had an eligible+total-row contribution, so it lands on rung 3 as well.

**`no-usable-cell` is the only token on either side of a lookup flip.** `blended-undecomposable`, `hidden-section`, `not-summable`, `incomplete-rows`, `no-total` and `unclassified` are unreachable by this repair. Reproduced under PS 5.1 against main, all four:

| Case | Fixture | Today | After repair |
|---|---|---|---|
| reason → value | one KPI widget, `Clicks`=50 + empty-named `google-adwords:impressions`=900 | `reason='no-usable-cell'`, no value, headline entry absent | value 900 |
| reason → value | two metrics both displayed `Campaign`; the *first* is an echo object, the second `clicks`=77 | `reason='no-usable-cell'` for `clicks` | value 77 |
| **value → reason** | same names, order swapped: `clicks`=77 first, `google-adwords:campaign` echo second | `google-adwords:campaign` publishes **`current=77`, `method=kpi-widget`, `aggClass=unknown`** | `reason='no-usable-cell'` |
| conflict deleted | `w-dup` (collided `Conversions` 100/250) + `w-solo` (`All conv`=250) | cell = 100, `conflict.reason='same-rank-disagreement'`, `losingWidgetIds=[w-solo]` | cell = 250, **no conflict** |

The third row is the one to put in the spec: the matrix today publishes a *dimension echo's* neighbouring number as a measured account value, and the repair deletes that number rather than correcting it.

## 3. The rank contest and conflict entries — both move

Rank is assigned **only when the lookup yields a numeric cell** (`:813-816`), so the repair changes rankedness, and rankedness is the contest.

Reproduced: a rank-1 KPI whose own cell is an echo (borrowing a same-named sibling's 5000) beats a rank-2 table total of 60 today — `current=5000, method='kpi-widget', scope='account', contributingWidgetIds=[w-kpi6,w-table6]`. After the repair the KPI drops out of `$ranked` and the table wins: `60`, `method='total-row'`, `scope='table-total:Campaign'`, `contributingWidgetIds=[w-table6]`. So a **scope/method flip is a first-class member of the flip set**, not just a value flip. The mirror case (an empty-named rank-1 KPI that is unranked today) promotes a rank-1 winner over a rank-2 incumbent.

Conflicts appear **and** disappear:
- `same-rank-disagreement` (`:888`) compares `[double]$_.cell.current -ne [double]$c.current`. Two widgets that today read one borrowed cell and one real one produce a **false** conflict that the repair deletes (row 4 above). The inverse — two widgets that agree today only because both borrowed, and disagree once each reads its own — mints a new one.
- `basis-mismatch` (`:887`) uses `Get-BasisVersion $m.id $m.unit $_.currencyCode` with **`$m` = the winner's** metric record, so a winner change swaps the baseline unit and can flip which losers count as off-basis. Since `basis-mismatch` outranks `same-rank-disagreement` (`:890-891`), `conflict.reason` can change token without any conflict appearing or disappearing.
- `conflict.losingWidgetIds` tracks `$ranked`, so it changes whenever rankedness does.

This directly reopens the two pinned cases at `Test-Analyze.ps1:1340-1366` ("matrix conflict honesty"), which exist to keep false conflicts out of facts. They stay green (no collisions in those fixtures) but the repair is the first thing that can manufacture one, so the collision fixtures need their own conflict assertions.

## 4. `matrixVersion` must move 1 → 2, and `canonicalVersion` is now 3 → 4

No landed spec states a *positive* rule for moving `matrixVersion` — it was minted at 1 by P5 (`spec-6:106`, `AC5:170`) and has never moved. The binding rule is stated negatively, twice, and both statements are one-marker-names-one-algorithm:

- `spec-8` D4 (`2026-08-05-spec-aUniformLattice-8.md:96-98`): "`meta.factsVersion` 1 to 2 is the honest marker, and it is the right one rather than `canonicalVersion` (which names the headline algorithm, untouched here) or **`matrixVersion` (which names the matrix algorithm, also untouched)**."
- `spec-4` Rollout (`:172-174`): "`facts.meta.canonicalVersion` does NOT move: the canonical algorithm producing `headline` is untouched, and moving the marker for an additive sibling would misdescribe it."

Repointing `:812` changes what the matrix algorithm emits, so `matrixVersion` 1 → 2. Declining it while bumping `canonicalVersion` is not defensible by symmetry: both markers would be moving (or not) for the identical reason — a key-resolution change under an unchanged reduce. Ratify the rule explicitly in the rebased spec; it is currently inferred.

`factsVersion` stays **2**: the additions (disclosure entries, the F5 breakdown `label`) are additive, and `spec-8` reserves `factsVersion` for shape subtraction; the precedent is aCanonicalTotal D10, "factsVersion stays 1 (all new fields additive)".

**Stale anchors the rebase must fix.** `Analyze-SwydoReport.ps1:1276` already reads `factsVersion=2; canonicalVersion=3; matrixVersion=1`, so S6's "2 to 3" is now **3 to 4**, and the Migration line "If ANLZ-aUniformLattice P5 later lands it takes `3` to `4`" is inverted — P5 landed first. A10 names two `Test-Analyze` pins at `:373` and `:641`; on main there are **five**, in `C:/projects/swydee/.claude/worktrees/gracious-pasteur-0e3377/Test-Analyze.ps1`: `:459` (`canonicalVersion -eq 3 -and factsVersion -eq 2`), `:460` (`matrixVersion -eq 1`), `:728` (`canonicalVersion -eq 3`), `:1300` (`canonicalVersion -eq 3`), `:1301` (`matrixVersion -eq 1`). Nothing outside those and the writer reads either marker (grep, whole tree, excluding `memory/`).

## 5. Where matrix and headline would disagree — one bug, two intended residuals, one new gap

**(i) BUG if the repair is partial.** Repairing `:967` and leaving `:812` leaves the matrix as a second, unrepaired copy of the defect, and it is worse than harmless: `GAP_NO_ACCOUNT_TOTAL` reads membership from the headline and the *reason* from the matrix (`:1085`, `:1095-1097`), and its `else` branch labels a matrix cell that carries a value `attributed-to-other-platform` (`:1097`). P5 justifies that token as the provider-attribution divergence only (`spec-6` D1, "the headline attributes by `Get-WidgetProvider` ... while the matrix attributes by metric-id prefix"). A borrowed-value matrix cell would fire the same branch and emit a **false reason string** into a published `dataGaps` finding. The shipped guard is already in place — `Test-Analyze.ps1:1145`, `A ($c1.displayCurrent -eq $hl1.displayCurrent) "P3 AC3 matrix and headline agree cell-for-cell"` — it just needs to be re-asserted over the two collision fixtures, where it becomes the mechanical prohibition on a one-sided repair.

**(ii) Intended layering, unchanged by the repair.** Hidden-section (headline publishes, matrix refuses) and provider attribution, both ratified as accepted residuals in `spec-6` §3 and D1. The repair touches neither predicate.

**(iii) A new, correct divergence the spec must list.** In the value→reason direction the headline *loses* an entry (`:969` scalar guard drops it) while the matrix keeps a cell carrying `reason='no-usable-cell'` — so `GAP_NO_ACCOUNT_TOTAL` **newly fires** for a metric that today silently publishes a borrowed number, with `byReason` reading `no-usable-cell=1`. Reproduced: `no account-level total available for 2 metric(s) of Google Ads: no-usable-cell=2`. The current inventory table records only the opposite move (the empty-name metric leaving `$missing`); a finding **appearing** is missing from it, and `severity='info'` keeps it out of forced surfacing.

The closer is unaffected either way: `Build-FactIndex` (`skill/scripts/Test-ReportNumbers.ps1:211-228`) indexes `headline` and `breakdowns` only, never `platforms[].metrics`. So AC6/AC7's candidate-bag arithmetic does not change because of the matrix — but the corollary is that a matrix-only wrong number has no gate at all, which is why `:812` cannot be left for a later phase.

---

## Two defects found in the landed matrix, in scope for the rebase

**F-1 — the "identity from the winner" fix at `:860-862` is not implemented.** `$out` is built at `:849` with `metric=[string]$m.name` where `$m = $g[0].metric`; `$m` is reassigned to `$win.metric` at `:863` and **`$out.metric` is never re-set**. Reproduced: a rank-2 table declaring `google-adwords:clicks` as `Clicks` followed by a rank-1 KPI declaring it as `Clicks (all)` yields matrix `metric='Clicks', current=999` while the headline yields `metric='Clicks (all)', current=999` — exactly the "one column's name and the other column's number" the comment says it prevents, plus a label disagreement with the headline. The pin at `Test-Analyze.ps1:1365` ("UL-2 the cell's NAME and VALUE come from the same contribution") does not catch it because its fixture has `$g[0] -eq $win`. Fix is one line; and A6's `Metric-Label` must cover `:849` too, or the empty-display-name case publishes `metric=""` into the coverage block P5 just told the analyst subagent to read.

**F-2 — the matrix cannot express a same-widget disagreement, and the repair is what creates one.** `:885` filters losers with `$_.widgetId -ne $win.widgetId`, and `contributingWidgetIds` (`:877`) is `Select-Object -Unique` on widget ids. One widget declaring the same metric id twice under two display names today reads one cell twice (equal values, nothing lost); after the repair the two columns carry genuinely different numbers and the second is dropped with **no `conflict`, no distinct id in `contributingWidgetIds`, and no rank-3/`valuesById` second layer to fall back on** (P6 is WONTDO, and `valuesById` is breakdown-scoped). The headline drops it too (keyed by `$m.id`, first-wins at `:970-972`). Decide explicitly: accept and record, or widen the conflict predicate to same-widget losers.

Probe scripts: `C:/Users/d41ly/AppData/Local/Temp/claude/C--projects-swydee--claude-worktrees-gracious-pasteur-0e3377/74a50f13-55b8-48a3-852c-9b0a62169aac/scratchpad/mx-probe.ps1` and `mx-probe2.ps1` (six fixtures, PS 5.1, run against main at 39def66).

=== LENS contracts ===
## 1. Which version literals must move, and to what

**Rule, as ratified — each literal names one algorithm/shape, not "the release":**

| Literal | What it names | Citation |
|---|---|---|
| `meta.canonicalVersion` | the **headline** algorithm; "names which algorithm produced an artifact" | `.claude/SESSION-KICKOFF.md:171-181`; `memory/analysis/DECISIONS.md:8` (ANLZ-aGovernedCanon-3); `spec-aUniformLattice-8.md:96-98` ("`canonicalVersion` … names the headline algorithm") |
| `meta.matrixVersion` | the **matrix** algorithm, separately | `spec-aUniformLattice-6.md:106`; `spec-aUniformLattice-8.md:98` |
| `meta.factsVersion` | the facts **shape**; bumped on a **subtractive** change | `spec-aUniformLattice-8.md:19` (S4), `:92-98` (D4). Additive keys explicitly do NOT bump it: `spec-aCanonicalTotal-1.md:73` (D10, "`factsVersion` stays `1` (all new fields additive)") |
| extraction `meta.schemaVersion` | the extraction document shape | `spec-aUniformLattice-1.md:347-353` |

**Verdict for a change that alters published headline VALUES:**

- **`canonicalVersion` 3 → 4.** Mandatory. `spec-aCandidTally-1.md:305-307` already wrote the rule and even predicted this arithmetic: "If ANLZ-aUniformLattice P5 later lands it takes `3` to `4`." P5 landed. The one literal is `Analyze-SwydoReport.ps1:1276` (the spec's `:996` is stale).
- **`matrixVersion` 1 → 2.** Also mandatory, and the pre-rebase revision had no way to know it. `Get-MatrixContributions` carries the *same* defect at `Analyze-SwydoReport.ps1:812` — `$c = $tr.metrics.$($m.name)   # by display NAME, byte-identically to the headline (see D3)`. Repairing the headline lookup without repairing `:812` splits the matrix from the headline and silently falsifies the comment; repairing it changes matrix cell values, which is precisely what `matrixVersion` names. Not bumping it would leave the matrix algorithm's output changed under an unchanged marker.
- **`factsVersion` 2 → 3: only if the unit ends up subtractive or renames a published key.** As scoped (additive disclosure key + repaired values) it stays `2` per aCanonicalTotal D10. It moves if S5 survives — see §5's S5 note, because renaming `breakdowns[].rows[].values` keys is a shape change by spec-8 D4's own standard ("'nobody reads it today' is not the same as 'the shape did not change'").
- **`schemaVersion`: does not move.** It is already `3`; S1 (`cellKey`) is *already in main* at `Get-SwydoReport.ps1:711-719`, so S1 and the S2 replay-fallback's justification both need rewriting rather than re-implementing. Non-goal §3's "the bump from `2` to `3`" is now historical fact, not a deferral.

## 2. Every reader of each version literal

**`meta.canonicalVersion` — writer `Analyze-SwydoReport.ps1:1276`.** No product reader anywhere. Confirmed by grep across `skill/`, `tools/`, `.githooks/`: zero hits outside that writer. `spec-aUniformLattice-1.md:349` states it directly: "a marker that nothing gates on". Test readers only:
- `Test-Analyze.ps1:459` (`-eq 3`, combined with `factsVersion -eq 2`)
- `Test-Analyze.ps1:728` (`-eq 3`, "even on non-flip (D6 global)")
- `Test-Analyze.ps1:1300` (`-eq 3`, P5 AC5)

The spec's A10 says the blast radius is exactly two pins at `:373` and `:641`. **It is now three**, at `:459`, `:728`, `:1300`, and A10's "a grep over the eight suites confirms these are the only two" must be re-run and rewritten.

**`meta.matrixVersion` — writer `Analyze-SwydoReport.ps1:1276`.** No product reader. Test readers: `Test-Analyze.ps1:460`, `Test-Analyze.ps1:1301`. These are new pins the pre-rebase revision never had to touch.

**`meta.factsVersion` — two independent counters sharing one key name.**
- Report analyzer writes `2` at `Analyze-SwydoReport.ps1:1276`; pinned at `Test-Analyze.ps1:459` and `Test-Analyze.ps1:1409`.
- Trend analyzer writes `1` at `Analyze-SwydoTrend.ps1:339`; documented at `:13`. **This is a separate numbering line, not a lag.** Fixtures echo `1`: `Test-Archive.ps1:221`, `Test-TrendAnalyze.ps1:146`.
- No product code reads either. `skill/SKILL.md:86` names the key without a value.

**Extraction `meta.schemaVersion` — two writers, `Get-SwydoReport.ps1:1093` (trend) and `:1167` (report), both `3`.** Readers:
- `Analyze-SwydoReport.ps1:907` — `-notin @(2,3)` → throws
- `ConvertTo-SwydoTrendFacts.ps1:75` — `-notin @(2,3)` → throws
- `skill/SKILL.md:31` — the Mode B prose gate the model itself runs (the third of the "three readers" in `spec-aUniformLattice-1.md:350-352`)
- `SKILL_BUILD_SPEC.md:32`, `:163`; `SWYDO_REPORT_EXTRACTION_SPEC.md:252`, `:275`, `:281`, `:313`
- **Structural pin worth flagging:** `Test-Extractor.ps1:154-158` regexes the extractor *source* for `schemaVersion=\d+`, asserts exactly **two** matches and both `=3`. Adding a comment or line containing `schemaVersion=` to `Get-SwydoReport.ps1` reds this leg. The unit touches that file.
- v2-path fixtures (inputs, not gates): `Test-Analyze.ps1:405`, `Test-TrendFacts.ps1:44`, `:70`, `:90`.

## 3. `Analyze-SwydoTrend.ps1` — yes, it consumes the repaired headline

A14 is right that it is a consumer, and its line cites survive the rebase. Confirmed on main:

Entry is `-PeriodKpiFacts` only, gated at `Analyze-SwydoTrend.ps1:208`. The per-metric pass iterates `$plat.headline.PSObject.Properties` at `:266`, skipping the literal key `hasComparison` at `:267`, then reads `$cell.id` (`:270`), `$cell.metric` (`:274`), `$cell.canonical.scope` (`:278`), `$cell.unit`/`$cell.currency` (`:293`), `$cell.current` (`:309`), and decides the mismatch at `:318`.

What actually changes, and what does not:

- **Headline KEY set does not change.** `Analyze-SwydoReport.ps1:970` is `$key = $m.id` — the store key was always the metric id; only the *cell fetched* at `:967` is wrong. So no trend loop iteration is lost or renamed by the repair.
- **New iterations appear.** An empty-display-name metric currently dies at `:967-968` (`$tr.metrics.''` → `$cell` null → `continue`) and has no headline cell at all. After the repair it gains one, so `:266` iterates a metric it never saw → a new `RECON_TREND_COVERAGE` or a new `RECON_TREND_MISMATCH`. This matches the spec's own inventory row ("headline presence … absent entirely → present with `current=900`").
- **Verdicts can flip.** A repaired `$cell.current` at `:309` moves `[math]::Abs($sumBase-$kpiBase)` against `$tol` at `:318`. That is a changed *published finding* in a second facts document.
- **Unaffected:** `$cell.unit`, `$cell.currency`, `$cell.canonical.scope` all derive from `$m.unit` / `$w.currencyCode` / widget dims (`Analyze-SwydoReport.ps1:964`, `:988`), never from the looked-up cell. Gate 1b at `:243-256` reads only `timeSeries` bucket *labels*, which come from `Row-Label`'s positional dimension read — no by-name metric lookup.
- **A blank label reaches trend prose, and `Metric-Label` must be applied upstream to stop it.** `Analyze-SwydoTrend.ps1:274` is `$pkName=if($null -ne $cell.metric){ [string]$cell.metric } else { Get-MetricPart $mid }` — a **`$null` check, not an emptiness check**. `$cell.metric` is `$m.name` (`Analyze-SwydoReport.ps1:988`), so for an empty-display-name metric it is `''`, not `$null`, and every `RECON_TREND_*` statement renders `google-adwords '': …`. Those statements are closer-indexed into `byFid` (`Test-ReportNumbers.ps1:245-255`). So `Metric-Label` belongs at `Analyze-SwydoReport.ps1:988`; patching `Analyze-SwydoTrend.ps1:274` would be fixing the symptom in the wrong file.
- **Trend facts carry no version echo.** `Analyze-SwydoTrend.ps1:339` emits `factsVersion=1` and no `canonicalVersion`/`matrixVersion`, so a trend-facts consumer cannot distinguish repaired from unrepaired input. If the spec wants that distinguishable, the choices are: echo the source facts' `canonicalVersion` into trend `meta`, or bump the trend `factsVersion` to `2` — and it must say explicitly that the trend counter is independent of the report counter, or a future reader will "align" them.
- **No trend gate catches any of this.** `Test-TrendAnalyze.ps1:146` builds its `-PeriodKpiFacts` fixture by hand with `metric='Sessions'` hardcoded and asserts no version literal. A version bump reds nothing in that suite. A14's "new AC covers one RECON pass over repaired facts" is therefore the only coverage this gets — keep it, and make it exercise the empty-name metric so `:274` is proven.

## 4. Pins in the closer, `SKILL.md`, `report-template.md`

**Closer: pins nothing.** `grep -n "metrics\|valuesById\|canonical\|matrix"` and `grep -n "factsVersion\|canonicalVersion\|matrixVersion\|schemaVersion"` over `skill/scripts/Test-ReportNumbers.ps1` both return **zero hits**. It is version-blind by construction and reads only the containers listed in §5.

**`skill/SKILL.md`:** one pin, and it is extraction-side — `:31` requires `meta.schemaVersion` of 2 or 3. No facts-side version literal appears anywhere in the file, which resolves the spec's open "`skill/SKILL.md` only if it names the current `canonicalVersion`" (files-touched row and section-5 user-docs bullet) to **no work on version grounds**. It does still need touching for the read/skip list at `:38-40` and the coverage paragraph at `:44` if the disclosure key is client-visible.

**`skill/report-template.md`:** no version literal at all. It pins the **quotable set** instead, at `:3`: headline `displayCurrent/displayPrevious/displayDelta`, `breakdowns[].rows[].values[].display/displayPrevious/delta`, `timeSeries[].buckets[].derived.*` and `pacing.*.display`, and `findings[].evidence.*` — plus the explicit prohibition "`platforms[].metrics` is a COVERAGE record, not a number source … NEVER quote its display strings."

**Root specs:** `SKILL_BUILD_SPEC.md:32`, `:163` and `SWYDO_REPORT_EXTRACTION_SPEC.md:252`, `:275`, `:281`, `:313` pin schemaVersion 2/3. Untouched, since schemaVersion does not move.

## 5. Where the flip disclosure should live

**Verified by reading `Build-FactIndex` (`skill/scripts/Test-ReportNumbers.ps1:195-266`). The containers that become tracing candidates are exactly:**

| Container | Lines | What is indexed |
|---|---|---|
| `platforms[].headline.<k>` | `:212-219` | three **named** properties only: `displayCurrent`, `displayPrevious`, `displayDelta` |
| `platforms[].breakdowns[].rows[].values.<name>` | `:221-231` | `display`, `displayPrevious`, `delta`; walks `$row.values.PSObject.Properties.Name` |
| `platforms[].timeSeries[]` | `:233-241` | `buckets[].derived.*`, `pacing.series[].display`, `pacing.netChange` |
| `findings.{wins,losses,anomalies,discrepancies,dataGaps}[]` | `:245-255` | `statement` + every `evidence.*` → `byFid` |
| `meta.annotations[]` | `:257-264` | `text` → `byAnnotation` |

**Explicitly: `platforms[].metrics` cells are NOT indexed.** No loop in `Build-FactIndex` touches `$p.metrics`; the string `metrics` does not occur in the file. Also not indexed: `rows[].valuesById` (only `$row.values` at `:224`), `headline[].canonical.*` beyond nothing — `canonical` is never enumerated, so `canonical.display` reaches the bag only because it is byte-equal to `displayCurrent` — and all of `meta` except `annotations`.

**So the matrix is closer-invisible, but it is still the wrong home for an `oldValue`,** for two independent reasons the pre-rebase revision could not have seen:

1. `Test-Analyze.ps1:1192` is a shipped pin: `A (($c6 | ConvertTo-Json -Depth 10) -notmatch '250') "P3 AC7 no losing VALUE is echoed anywhere in the cell (U9 D4/FP-3)"`. A matrix cell is contractually forbidden from carrying a superseded value.
2. `spec-aUniformLattice-6.md:143` rejected "Indexing the matrix in the closer 'for completeness'. Measurably weakens the guard for zero gain." The matrix's non-indexing is a deliberate guard property; a spec should not create a future reason to revisit it.

**Recommended placement, and the correction A8 needs:**

- **A8's container answer survives the rebase and is now provable, not assumed.** `headline[].canonical.<newKey>` adds **zero** candidates, because `:215-217` reads three named properties off `$p.headline.$hk` and never enumerates `canonical`. Build on `canonical` at `Analyze-SwydoReport.ps1:994`, mirroring `canonical.supersededWidgetId` at `:997` (A8's `:765`/`:768` are stale).
- **A8's blanket "neither a finding nor `meta.annotations`" is too strong and should be narrowed.** The real constraint is **no metric VALUE in an indexed container**, not "no finding". U9 D4 ratified exactly such a finding: `spec-aHeadlineRank-1.md:74` (ids, widget ids, count-as-string only) with the safety argument at `:194` (FP-3: "structurally impossible … there is no metric value to trace") and its test at `:225` (U9-T11). It ships today as `GAP_HEADLINE_SOURCE_CHANGED`, `Analyze-SwydoReport.ps1:1109-1124`, whose in-code comment states the rule: "ids + count only, NO metric values echoed". Copy that shape for a report-level roll-up if one is wanted — it gives the user a visible signal that a repair fired, which a `canonical`-buried key does not.
- **Breakdown flips, if any survive:** put the record on the **breakdown block object** (`breakdowns[].<key>`), never inside `rows[].values` — `:224` walks `values` property names, `:221-231` never walks siblings of `rows`.
- **Keep the left-shift gate A8 proposed and add the count leg**, matching `spec-aUniformLattice-6.md:175-176` (AC7): dot-source `Test-ReportNumbers.ps1 -DefineOnly`, run `Build-FactIndex` over the duplicate-name fixture, assert (a) no candidate equals a superseded value and (b) the per-platform candidate count equals the pre-change count plus exactly the intended delta.

**One scope collision the revision must resolve — S5 now contradicts a just-landed decision.**

S5 ("repoint the breakdown output onto the resolved key", now `Analyze-SwydoReport.ps1:404`/`:407`/`:409`) directly contradicts ANLZ-aUniformLattice-8 D1/D6, which ratified that `values` stays display-name-keyed **byte-for-byte** (`Get-Breakdown` comment at `:403`; `spec-aUniformLattice-8.md:85-90`) and that `valuesById` is the collision channel (`:411-436`, gated by `$nameCount` at `:396`, marked by `valuesByIdScope` at `:446`). On main the collided breakdown case is **already repaired**: for two `Conversions` metrics with row cells 60 and 150, `values` collapses to one key at 60 (unchanged) while `valuesById` carries both under their metric ids. So S5's stated justification at `spec-aCandidTally-1.md:266-271` — that the overwrite would otherwise survive and publish metric 2's value under metric 1's label — no longer holds as written, but a **new** version of that hazard does: if S4 repoints `Row-Cur $r $m.name` at `:404`/`:407` while the key expression at `:409` stays `$m.name`, the second metric overwrites the first with 150 under label `Conversions`. **The carve-out must be explicit**: S4 excludes `:404`, `:407`, `:409`, and S5 is withdrawn.

Two further consequences if S5 is retained anyway, both version-relevant: renaming published `values` keys is a shape change (→ `factsVersion` 2→3 by spec-8 D4's own standard) and it makes `valuesById` dead one commit after it shipped; and rewriting `metricNames[1]` to the uniquified key (spec inventory row "breakdown labels") breaks the index-aligned two-step lookup `spec-aUniformLattice-8.md:102-104` and `skill/SKILL.md:38-40` depend on (`index → name → values[name]`). If a cell-key list is wanted, it must be a **new** `metricCellKeys[]` beside `metricNames`/`metricIds` at `:446`, not a rewrite of either.

**Also unlisted in the spec's inventory and now in scope:**

- `Analyze-SwydoReport.ps1:812` — the matrix's own by-display-name read (drives `matrixVersion`).
- `Analyze-SwydoReport.ps1:388` — `Sort-Object { Row-Cur $_ $orderMet.name }`. Repointing this changes breakdown row **order**, hence top-N membership, hence closer-indexed `values` content. It is a genuine flip-set member and is not the `values` write, so the S4/S5 carve-out must decide it separately.
- `Analyze-SwydoReport.ps1:481`, `:483`, `:498`, `:499`, `:502` — `Get-TimeSeries` derived/pacing reads, whose outputs are closer-indexed at `Test-ReportNumbers.ps1:233-241`.
- `Analyze-SwydoReport.ps1:1133` — the `valueProv` probe feeding the cost-per-result rule.
- The spec's stale site map, for the rebase: `:738`→`:967`, `:931`→`:1211`, `:996`→`:1276`, `:765`/`:768`→`:994`/`:997`, `:839-843`→`:1109-1124`, `:397`/`:401`→`:404`/`:407`/`:409`/`:446`, extractor `:516`/`:525`→`:711-719`/`:729`.

=== LENS tests ===
## 1. What main already asserts (cellKey / valuesById / collided display names)

**`Test-Extractor.ps1`** — the only suite that runs the real `Normalize-Widget` (dot-sources `Get-SwydoReport.ps1 -DefineOnly` at line 9).

- `Test-Extractor.ps1:35-39` — the `Uniq-Key` contract itself: `"first Clicks => 'Clicks'"`, `"dup name diff id => id-suffixed"`, `"dup name+id => index-suffixed"`, `"null name => id"`, `"null name+id => col<idx>"`.
- `Test-Extractor.ps1:71` — `Assert ($mm.Keys.Count -eq 2) "blended Clicks => 2 distinct metric keys (got $($mm.Keys.Count))"`.
- `Test-Extractor.ps1:72` — `Assert ($mm['Clicks'].current -eq 100 -and $mm['Clicks [facebook-ads:clicks]'].current -eq 250) "both Clicks values survive (no overwrite)"`.
- `Test-Extractor.ps1:87-88` — `Get-UniqKeySeq` replay: `"P1 Get-UniqKeySeq returns one key per item"`, `"P1 dup display name => two DIFFERENT cellKeys"`.
- `Test-Extractor.ps1:90` — `"P1 empty name+id => Uniq-Key col<idx> fallback"` (name **and** id both null only).
- `Test-Extractor.ps1:94` — `"P1 AC1 cellKey emitted per metric"`.
- `Test-Extractor.ps1:95` — **this is the cell-key parity gate**: `Assert ($r.rows[0].metrics.Contains($r.metrics[0].cellKey) -and $r.rows[0].metrics.Contains($r.metrics[1].cellKey)) "P1 AC1 every cellKey addresses a real row-map key"`.
- `Test-Extractor.ps1:97` — `Assert ($r.rows[0].metrics[$r.metrics[1].cellKey].current -eq 250) "P1 cellKey reads the SECOND metric's own value (the wrong-value path)"`.
- `Test-Extractor.ps1:157-158` — `"P1 AC12 exactly two schemaVersion writers"`, `"P1 AC12 both writers emit schemaVersion=3"`.

Test-Extractor asserts nothing about `valuesById` (analyzer-side), nothing about case-only-differing names, nothing about an empty name with a non-null id.

**`Test-Analyze.ps1`** — dot-sources **only** `Analyze-SwydoReport.ps1 -DefineOnly` (line 7). `cellKey` enters exclusively by `Add-Member` on synthetic metric records (`1260-1261`, `1359-1360`, `1374-1375`).

- `1250-1255` no-collision block: `"L8 AC1 no colliding name => valuesById is EMPTY (the duplication is gone)"`, `"L8 AC1 valuesByIdScope states the rule…"`, `"L8 AC3 values still carries the cell, keyed by display name"`, `"L8 D1 index-aligned arrays are the addressing path for a unique name"`, `"P4 AC5 a fixture without extractor rowKeys reports rowKeyBasis=absent"`.
- `1274-1280` collided name **with** cellKey: `"P4 AC4 values still COLLAPSES a duplicate display name to one entry (unchanged defect)"`, `"P4 AC4 valuesById does NOT collapse: two ids, two entries"`, `"P4 AC4 each id carries its OWN number, not the first metric's"`, `"P4 AC4 the second metric's value is recoverable ONLY from valuesById"`, plus rowKey/rowKeyBasis.
- `1290-1293` collided name **without** cellKey (the schemaVersion-2 fallback): `"P4 AC4 v2 valuesById is EMITTED"`, `"…the metric is OMITTED from valuesById, never guessed"`, `"…neither colliding id is addressable, so no wrong number is published"`, `"…values still carries the collapsed single entry"`.
- `1384-1387` / `1395-1396` / `1401` / `1405-1407` — L8: collided ids kept, each with its own value; the `values`-read independence case; empty `valuesById` on unique names; the re-inflation guard `"L8 AC7 no-collision rows carry no id-keyed cell for '$mid'"`.
- `1364-1366` — one widget declaring the **same id twice under different names** (cellKey-stamped): one cell, `"UL-2 the cell's NAME and VALUE come from the same contribution"`, never its own loser.

**The load-bearing gap in Q1:** `Hl` and `Mx` are never called on any collided-display-name fixture (`$p4b`, `$p4c`, `$l8a`, `$l8b` — verified by grep). Every cellKey assertion in Test-Analyze lives inside `Get-Breakdown`'s `valuesById`. The reported defect — headline (`Analyze-SwydoReport.ps1:967`) and matrix (`:812`) reading `$tr.metrics.$($m.name)` — has **zero** assertions on main.

## 2. Prior-revision cases: redundant vs still uncovered

**Redundant against main (drop them):**
- Duplicate display names at the extractor/row-map layer → `Test-Extractor.ps1:71-72, 87-88, 94-97`.
- The cell-key parity gate → `Test-Extractor.ps1:95` **is** that gate; `:97` already pins the wrong-value path. A second one duplicates.
- Breakdown keys → `Test-Analyze.ps1:1242` (block key order), `:1246` (row key order), `:1253` (index-aligned arrays), `:1254-1255` (rowKeyBasis/rowKey omission).
- Byte-identity pins on `values` → `Test-Analyze.ps1:1250-1252, 1274, 1384, 1395`.
- Pre-cellKey fallback **at the breakdown layer** → `Test-Analyze.ps1:1290-1293`; the `col<idx>` half → `Test-Extractor.ps1:90`.

**Still uncovered (must survive the rebase):**
1. **The headline lookup on a collided name** — the defect itself. No fixture asserts `headline[<id>].current` where two metrics share a name.
2. **The matrix contribution cell** (`Analyze-SwydoReport.ps1:812`) on a collided name. All P3 fixtures use unique names.
3. **Case-only-differing names** — nothing in either suite. Real path: `Uniq-Key` (`Get-SwydoReport.ps1:403-406`) tests `$map.Contains($base)` against an `[ordered]@{}` row map (`:728`), so `Conversions`/`conversions` **is** a collision and the second gets suffixed; but the analyzer's `$tr.metrics.$($m.name)` is case-insensitive and returns the first. `Get-Breakdown`'s `$nameCount` (`:395-396`) is a plain `@{}`, also case-insensitive, so `valuesById` does engage — entirely untested.
4. **Empty display name with a non-null id** — `Uniq-Key` line 404 returns the id; `Test-Extractor.ps1:90` covers only name+id **both** null. Nothing anywhere covers the analyzer side: `$m.name` is interpolated straight into client-facing statements at `Analyze-SwydoReport.ps1:701-702, 705-706, 714-715, 757-758, 1184-1186, 1199`. The blank-label risk `Metric-Label` exists to fix is unpinned.
5. **Pre-cellKey fallback at the headline/matrix layer** — the breakdown omits; nothing states what the headline does with a v2 doc + collided name.
6. **The extractor→analyzer seam** — nothing feeds real `Normalize-Widget` output into `RunAnalyze`. `Test-Analyze.ps1:405` hardcodes `schemaVersion=2` in every e2e fixture, so no test exercises the analyzer over a schemaVersion-3 document at all. A repair that gates on `meta.schemaVersion` would pass every existing test and still be wrong.
7. **`Uniq-CellKey` replay parity** — `Test-Extractor.ps1:35-39` and `:87-90` pin the extractor's key algorithm; nothing pins an analyzer-side replay against it. A replay is a second copy of a single-source contract (§12/§7) and needs a cross-file parity gate that does not exist today.
8. **Closer scope of `valuesById`** — `Test-ReportNumbers.ps1:224` iterates `$row.values` only; `valuesById` and `canonical` are never indexed. So a number rendered from `valuesById` is untraceable, and a `canonical`-hosted disclosure is closer-inert (the prior revision's reasoning is confirmed by the code). Neither fact is pinned by a test.
9. **Finding side-effects of a value-changing repair** — `Get-DetailSumFindings` reads by name (`:689-691`). On fixture `l8b` (`Test-Analyze.ps1:1392`) a cellKey read makes total `700` against a shown sum of `250`, newly firing `RECON_ROW_REMAINDER`. No assertion pins the finding set of any collided-name fixture, either way.

## 3. Existing real-`Normalize-Widget` fixture helper

Yes. `Test-Extractor.ps1:9` loads the real functions; the harness is `Test-Extractor.ps1:14-16` — `W($widget)`, `Node($cells,$compare,$flags)`, `FieldsConn($items)` — driving real `Normalize-Widget` at lines 43, 51, 57, 62, 69, 79, 93, 100, 125, 126, 131, 133, 139, 147. A second `NW` helper in Test-Analyze is a §12 duplicate.

Reuse is mechanically safe: the two scripts share **zero** function names (49 vs 51, empty intersection) and **zero** `$script:` variable names, so one suite can dot-source both `-DefineOnly`. The one caveat: `Normalize-Widget` reads `$script:secMap` / `$script:secHidden`, seeded at `Test-Extractor.ps1:10` and reset at `:138`/`:141` — any reuse site must seed them. Preferred shape: put the seam test in Test-Extractor beside the existing harness, or extract the three builders into a shared dot-sourced fixture file consumed by both suites.

## 4. Existing assertions a value-changing repair turns red

**A. Red if `values` gains any cellKey-driven read** (these pin today's collapse as deliberate):
- `Test-Analyze.ps1:1395` — `A (@($rN.values.PSObject.Properties.Name | Where-Object { $_ }).Count -eq 0) "L8 D1-2 values drops the row (its display-name read is null) -- unchanged behaviour"`. Fixture `l8b` row A is `Clicks=null` / collider `250`; **any** cellKey-aware `values` read produces one entry. Sharpest tripwire in the suite.
- `Test-Analyze.ps1:1274` — `A (@($rd.values.PSObject.Properties.Name).Count -eq 1) "P4 AC4 values still COLLAPSES a duplicate display name to one entry (unchanged defect)"` (red if `values` becomes cellKey-**keyed**: 2 entries).
- `Test-Analyze.ps1:1384` — `A (@($rA.values.PSObject.Properties.Name).Count -eq 1) "L8 AC2 values still collapses the collided name to one entry"`.
- `Test-Analyze.ps1:1293` — `A (@($rd3.values.PSObject.Properties.Name).Count -eq 1) "P4 AC4 v2 values still carries the collapsed single entry"`.

**B. Red on the prior revision's `canonicalVersion` bump:**
- `Test-Analyze.ps1:459` — `A ($r9.facts.meta.canonicalVersion -eq 3 -and $r9.facts.meta.factsVersion -eq 2) "e2e14/U9: canonicalVersion=3 (P5 waiver), factsVersion=2 (the lean-facts subtraction)"`
- `Test-Analyze.ps1:1300` — `A ($p5a.facts.meta.canonicalVersion -eq 3) "P5 AC5 canonicalVersion is 3"`
- If `matrixVersion`/`factsVersion` also move: `:460`, `:1301`, `:1409`.

**C. Shape pins that constrain where a disclosure may live:**
- `Test-Analyze.ps1:1151` — `A (@($plA.PSObject.Properties.Name) -join ',' -eq 'id,name,category,headline,hasComparison,metrics,breakdowns')`. Any new **platform-level** key = red.
- `Test-Analyze.ps1:1246` — `A (@($r0.PSObject.Properties.Name) -join ',' -eq 'label,values,valuesById')`. Any new **row-level** key = red.
- `Test-Analyze.ps1:1242` — breakdown key order incl. `valuesByIdScope`.
- `Test-Analyze.ps1:1230-1231` — facts top-level `meta,platforms,findings` and the findings channel order.
- `Test-Analyze.ps1:452` — `foreach($bad in 'value','basisVersion','synthesizedFrom'){ A (-not ($h9.canonical.PSObject.Properties.Name -contains $bad)) }`. Only those three names are banned, and `:451` checks *contains*, not an exact set — so a **`canonical`-hosted flip disclosure passes the existing pins**, provided `:450` (`canonical.display -eq displayCurrent`) still holds.
- `Test-Extractor.ps1:157-158` — exactly two `schemaVersion` writers, both `3`.

**D. Value-echo precedent (trips if the disclosure carries the superseded number into a matrix cell):**
- `Test-Analyze.ps1:1192` — `A (($c6 | ConvertTo-Json -Depth 10) -notmatch '250') "P3 AC7 no losing VALUE is echoed anywhere in the cell (U9 D4/FP-3)"`.

**E. Closer pins that any facts-shape change must leave at zero violations:** `Test-Analyze.ps1:655`, `:661`, `:667`, `:699`.

Stale-comment note: `Test-Analyze.ps1:649` says `Test-Closer stays 119, untouched`; Test-Closer actually reports **129**. Fix the header while touching this file.

## 5. Per-suite counts on main (measured, 39def66)

- `C:/projects/swydee/.claude/worktrees/gracious-pasteur-0e3377/Test-Analyze.ps1` → `RESULT: 619 passed, 0 failed`
- `C:/projects/swydee/.claude/worktrees/gracious-pasteur-0e3377/Test-Extractor.ps1` → `RESULT: 288 passed, 0 failed`
- `C:/projects/swydee/.claude/worktrees/gracious-pasteur-0e3377/Test-Closer.ps1` → `Test-Closer: 129 passed, 0 failed.` (run because the repair's disclosure decision is closer-motivated)

On a green run `$LASTEXITCODE` was empty — the suites call `exit 1` only on failure, so a same-session invocation sets no code on success. Assert on the failure path, not on a `0` that is never written.

