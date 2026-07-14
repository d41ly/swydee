# U7 - Cross-widget reconciliation checks (spec **v2**)

> **Review provenance & critic overrides (authoritative).** This spec is the v2 output of a 3-lens adversarial review (alert-fatigue/severity, formula/taxonomy, closer-integration), folded into the body below, followed by a cross-cutting completeness critic over U6+U7. Where the critic overrides the body, the override wins:
>
> - **Build scope: U7a (#3/#4/#5) is GO; U7b (#6 monthly-series-sum vs period KPI) is DEFERRED** (YAGNI, matching the U5 deferral). **Precondition to undefer U7b:** `Get-SwydoReport.ps1` must resolve RELATIVE date ranges to concrete `YYYY-MM` at extraction time (plus D-period persisted, owned by U6 at that time). Until then #6's only `major` (`RECON_TREND_MISMATCH`) is inert for the common relative-quarter case (extractor discards concrete dates at G:165), so shipping it buys an inert major and a large gate surface. All #6 / D-period text below is retained as the *deferred design*.
> - **#5 account-ceiling lookup RE-DERIVES scope from `$dataWidgets`** (zero-dim + non-null `Total-Row` + non-blended), NOT from `canonical.scope`. U6 attaches `canonical{}` only to the first-wins headline winner (A:380 `continue`), so a non-winning zero-dim KPI has no persisted `canonical` to scan. U7a's real U6 dependency is A1 (`Total-Row -> $null`) + `Test-Blended`/`Get-WidgetProvider` -- not `canonical`.
> - **#5 drops the `manualKpi` exclusion clause** (kind=='manualKpi' widgets are already excluded by the `kind -eq 'data'` filter at A:344, so they can never be a #5 candidate). Goal-card exclusion is dropped unless U6 stamps a concrete `hasTarget`/`isManual` flag; a normal data widget's measured `current` is a legitimate ceiling. Documented as residual.
> - **Predicate divergence (`Test-Additive` vs `Test-Summable`)** stays intentional, but both are colocated in the metric-helper region with one loud comment enumerating the divergence set (`{user, value}`) and why, plus a shared divergence test asserting the split on the literal ids. `Test-Synthesizable`'s regex lives only in U6's deferred note, not as live code.
> - **ULP authorities:** the closer's string-based `Get-Ulp` and U7a's value-aware `Get-MetricUlp` stay separate (different layers), but the U7a-T0 drift test adds a cross-file assertion feeding `Get-MetricUlp`'s step through `Format-Metric` -> the closer's `Get-Ulp`, asserting equality (structural pin, not prose).
>
> Build verdict: **U7a GO; U7b DEFER.** Build order: U6 -> U7a (this spec, #3/#4/#5) -> [U7b #6 deferred].

### Re-review vs U8 spec (undeferral)

> **Provenance.** Second 3-lens adversarial re-review of the deferred U7b (#6) against the new U8 spec (`docs/specs/extractor-period-resolution-spec.md`) on main `cccd0c9`, 2026-07-12. Lens verdicts: **correctness GO-WITH-CHANGES; discipline GO-WITH-CHANGES; fatigue GO-WITH-CHANGES.** **Final verdict: GO-WITH-CHANGES -- the DEFER LIFTS once U8 ships as specced**, conditional on the must-fix deltas below being folded into the U7b sections before the U7b build commit. Build order: U8-ship -> U7b, each its own commit/review boundary. This block is authoritative over any conflicting U7b text below it.

**Precondition finding (all three lenses concur):** U8's `Get-PeriodMeta` (U8 D7) satisfies the D-period field contract EXACTLY -- the four contracted keys `{measure, startYm, endYm, calendarAligned}`, `YYYY-MM` regex enforcement, `calendarAligned` computed per this spec's start-day-1/end-plus-1-day-1 definition, the null triple for legacy/unresolved input, `meta.period` always present -- and U7b's gate-1 hard-degrade to `info RECON_TREND_COVERAGE` works unchanged for both the null triple and pre-U8 facts lacking the key. The named DEFER precondition is therefore met by U8 (once built), and the common relative-quarter case becomes live exactly as the deferral demanded.

**Must-fix deltas (prescriptive; apply to the R18 / #6 / D-period text before the U7b build):**

1. **MF-1 -- Demote `RECON_TREND_MISMATCH` to `severity=info` for the initial U7b build.** Three chains break the "provably impossible" claim R7 requires for major: (a) filtered/date-overridden zero-dim KPI cards are undetectable from schema v2 -- the exact rationale this spec used to demote #5 (R17), and #6 uses those same KPI cards as one side of its equality; (b) the freshness freeze (`Test-IsFinal`, `Update-SwydoLedger.ps1:53-57`, Horizon K=6, strictly-older-than test) makes gate 4's all-`final` requirement unreachable in the primary last-complete-quarter flow, so months are always provisional there and a major would be inert for the live report family -- silently re-creating the inert major that motivated the original DEFER; (c) legitimate provider restatement beyond the freeze horizon is routine data evolution, not a report defect. Resolution (merges correctness MF-1 option (b) with the fatigue prescription): ship #6 with `RECON_TREND_MISMATCH` as `info`; relax gate 4 so provisional months may be summed (present + numeric `.value` + single `byBasis` series), with `evidence.months` stating `"<final>/<k> final"` honestly -- the check is then LIVE in the primary flow. The finding keeps its fid and anchored-line traceability but is never force-surfaced in v1. Promotion back to major is a cheap follow-up unit gated on live true-positive evidence with zero FPs, and must restore the all-`final` gate. Consequential text edits: drop #6 from R7's major list and the "Net severity effect" line; update the #6 decision block, the gates-summary Severity row, the closer-integration majors list, and test cases asserting `major RECON_TREND_MISMATCH` (assert `info` instead, not force-surfaced).
2. **MF-2 -- Respec gate 2 (identity): the ledger has NO `clientId`.** Ledger schema is `{ ledgerVersion, client, updatedAt, cells, coverage }` (`Update-SwydoLedger.ps1:16`; clientId is resolved only for archive/registry placement and never persisted into the ledger document), so "`meta.clientId` == ledger `clientId`" (R18 gate 2 / R18b / changelog item 8) is unimplementable -- a literal build compares a real id against `$null` and fails on every run. Respec: compare `-PeriodKpiFacts` `meta.client` (name, emitted at the Analyze meta block) `-eq` ledger `.client`, case-insensitive, trimmed; null/empty on either side -> coverage info (fail-closed). Pin the ":usage-error exit 2 OR info" ambiguity to **info** (the trend script has no exit-2 convention). Drop the clientId wording everywhere, including test case "FP - identity mismatch (R18b)". Do NOT extend the ledger schema (forbidden file); a registry-backed stronger identity check is optional future work, its own unit.
3. **MF-3 -- Add gate 2c (account scope), which the #6 prose assumes but the gates never state.** The shipped U6 headline store is FIRST-WINS per `(prov, metricId)` (`Analyze-SwydoReport.ps1:632` `continue`), and a dimensioned total-row widget winning the slot carries `canonical.scope=='table-total:<dim>'` (A:625). Gate 2c: the headline entry for `(providerId, metricId)` must exist, carry a `canonical{}` object (pre-U6 facts lack it entirely), and have `canonical.scope -eq 'account'` (equivalently `canonical.source -eq 'kpi-widget'`); anything else -> per-metric coverage info ("no measured account-scope KPI for this metric"), never a comparison. Unlike #5 (which re-derives from `$dataWidgets` per the critic override), #6 reads facts only and cannot recover a shadowed account KPI -- document the first-wins shadowing case as a residual (degrades honestly, unrecoverable from facts).
4. **MF-4 -- Add gate 1b (the EC-2 timezone decision U8 explicitly deferred to this review; decided here: cross-check, not accept).** The U8 resolver anchors on the extracting machine's local date; the server resolves in an unknown account timezone (`timeZone:null` on the wire). Near a period boundary an off-by-one-period resolution passes every R18 gate and compares the wrong period -- the exact false-positive class R7 exists to prevent. Gate 1b: when `-PeriodKpiFacts` carries a monthly timeSeries for the compared provider whose bucket labels ALL match `^\d{4}-\d{2}$` (server-returned month labels of the same report period, `Get-TimeSeries`; verified present in the archived QCU live facts as `2026-04..2026-06`), that label set must equal `startYm..endYm`; disagreement -> coverage info ("resolved period disagrees with server-labeled report months"); absence of such a series -> proceed (documented residual). Add a skewed-anchor FP fixture to the #6 test plan. No `anchorDate` addition to the D-period contract is needed.
5. **MF-5 -- Add gate 4b (restatement).** Every summed month must have `restatementCount==0` (`[int]` cast, per the L:126 precedent); any restated month -> per-metric coverage info naming the month. Without it, a frozen-then-restated month passes all gates and #6 relabels a known freeze-policy artifact -- already force-surfaced as `GAP_RESTATEMENT_SUPPRESSED` (`Analyze-SwydoTrend.ps1:126-131`) -- as a provider mismatch (double finding, wrong causal claim). Residual: a provider restatement occurring after the LAST trend pull is invisible to `restatementCount`; accept and note.
6. **MF-6 -- Replace "`Get-QuarterSum`'s ok-logic" with a specced generalized month-range sum.** U8 resolves `month/-1` (k=1) and `year/-1` (k=12) in addition to `quarter/-1` (U8 D1), and gate 1 keys only on `startYm..endYm` tiling, so #6 legitimately receives 1- and 12-month spans that `Get-QuarterSum` (quarter-key-only) cannot sum. Spec a new pure helper `Get-MonthRangeSum($months,$startYm,$endYm)` returning the same `@{ok; value; reason}` shape with the same ok-logic (per-month presence + numeric `.value` + single `byBasis` series; `.state` handling per MF-1), month enumeration by INTEGER arithmetic in the existing `'{0:D4}-{1:D2}'` string style -- explicitly NO `[datetime]` parsing of `YYYY-MM` strings (culture hazard) -- and `endYm < startYm -> ok=$false` (fail-closed). Tolerance `k` = month count per R15. Tests at k=1, k=3, k=12, a year-crossing range (e.g. `2025-11..2026-02` enumerated correctly), and the inverted range.
7. **MF-7 -- Reconcile the D-period section, ownership text, and test plan with what U8 actually ships.** (a) The resolvability rule is INVERTED: the D-period text says "Resolvable only when `dateRange.primary` has concrete dates. For a relative/derived label ... `startYm/endYm=$null`", but U8 resolves exactly the RELATIVE `count==-1` `month|quarter|year` family and nulls everything else, including custom/fixed ranges (the wire never carries concrete dates). Rewrite that bullet and gate 1's parenthetical to key EXCLUSIVELY on the persisted fields (unresolved -> null triple -> info); a builder adding a "relative -> info" branch would re-inertify #6 and defeat U8 entirely. (b) Re-point ownership: the "D-period (folded into U6)" / "when U6 stamps canonicalVersion, it also persists `meta.period`" text is stale -- U6 shipped WITHOUT `meta.period` (verified: no `meta.period` in `Analyze-SwydoReport.ps1`; archived QCU facts lack it); U8 (extractor `Resolve-ReportPeriod` + Analyze `Get-PeriodMeta` read-through) owns it. Update the Status/changelog-item-7 wording and blast-radius line accordingly. (c) Restate the test case "FP - no machine-readable period: ... relative 'last quarter'": post-U8 a relative last-quarter RESOLVES (`calendarAligned=$true`) and is the HAPPY PATH; the info cases become: legacy facts (no `meta.period`), custom/fixed range, week/day measure, `count<=-2`, malformed `startYm`. (d) Record the U8 D8 delta: `meta.period.measure` passes `'year'`/`'week'` through verbatim instead of coercing to `'custom'` (enum wider than the `quarter|month|custom` shown below); verified benign -- no R18 gate branches on `measure` (gate 1 keys on `calendarAligned` + `startYm/endYm` + tiling only) -- but the contract text must match what ships; U7b builder re-confirms at build.
8. **MF-8 -- Pin coverage-emission cardinality and delete the no-param availability note.** Report-global gate failures (gate 1 period, gate 1b observed-months, gate 2 identity) emit exactly ONE `RECON_TREND_COVERAGE` per run; per-metric gates (2c, 3, 4, 4b, 5) emit per metric. When `-PeriodKpiFacts` is OMITTED, emit ZERO findings -- the param is opt-in and absence is not a data gap; delete the "FP - no `-PeriodKpiFacts`: ... info availability note" test case (replace with: omitted -> zero `RECON_*` findings, trend path byte-identical). The optional clean-recon info in the #6 decision block is explicitly NOT emitted (inverse fatigue).
9. **MF-9 -- Mirror the fail-closed read for the new input.** `Assert-NoCredential` over the raw `-PeriodKpiFacts` text before `ConvertFrom-Json`, exactly as the trend script already does for the ledger (L:89); add a credential-bearing-input test case. One line; preserves the fail-closed posture the "#6 placement" text asserts but never requires.

**Residuals (consolidated from the three lenses; document, do not build):**

- **U8 is itself spec v1, unbuilt** at re-review time (no `meta.period` emitted anywhere today). GO-WITH-CHANGES means: U7b is buildable once U8 ships as specced; if U8 slips, #6 self-degrades to a single coverage info and still cannot ship a false finding.
- **Filtered account-scope KPI card** passes gate 2c and can legitimately differ from the ledger sum (schema-v2 blindness, same residual R17 documents for #5). MF-1's info severity is the mitigation; a promotion-to-major follow-up must re-argue this chain.
- **Provider restatement after the last trend pull** is invisible to `restatementCount` (MF-5 residual); bounded by the same freshness that makes gate 4 conservative.
- **First-wins headline shadowing** (MF-3 residual): when a table-total wins the slot, the real account KPI is unrecoverable from facts; #6 degrades honestly to coverage info.
- **U8 EC-11** (labels from `extractedAt` vs months from `anchorDate` diverging inside one facts file) and sub-day timezone alignment remain U8 residuals; gate 1b reduces their blast radius on #6 to info-grade.
- **`Derive-Periods` label looseness** (applies the last-complete-quarter label for ANY relative quarter regardless of count, vs U8's `count==-1` domain): for a hypothetical `quarter/-2` report the label is plausible-but-wrong while `meta.period` is honestly null. Pre-existing label-side issue, not a U7b defect; the months side is fail-closed.
- **Legacy/pre-U8 artifacts** permanently degrade #6 to coverage info (or silence per MF-8); the check earns value only on post-U8 extractions. Accepted.
- **No defect found in #6's core arithmetic:** raw-unit summation, micros/1e6 both sides, `max(2,k)*ulp` with the shipped value-aware `Get-MetricUlp`, and the intentional `Test-Additive` (L:133) vs `Test-Summable` split all verified against live code; TrendAnalyze 24/24 and Analyze 276/276 green this review.
- **Editorial, refresh at build:** all `A:` anchors in the U7b text are stale post-U6/U7a (file now 803 lines: DISC block ~A:713-738, meta block A:786-789, canonical A:645, first-wins A:631-632); ledger read is L:88-91; the guarded `-DefineOnly` dot-source is L:28-30; L:133 is still byte-exact. Replace the `<U6-total>` green-count placeholder with the measured Analyze 276 (board at `cccd0c9`: Analyze 276, Closer 119, Extractor 94, Archive 94, TrendFacts 19, Ledger 50, TrendAnalyze 24, Sync 4); U8 lands first and grows Extractor/Analyze, so re-measure U7b's green-count row against the post-U8 board at build time.
- **Cross-cutting critic additions (2026-07-12; fold in the same MF build-time edit):** (a) the ratio-fixture-sweep test item's "protects the 135 green" is a pre-U6 Analyze count the bullet above does not cover — read it as the measured Analyze count at U7b build time and fix it in the MF-fold. (b) Align MF-4/MF-6's loose `^\d{4}-\d{2}$` idiom to U8's strict `^[0-9]{4}-(0[1-9]|1[0-2])$` (fail-closed either way — .NET `\d` admits Unicode digits and months 13-99 — but the two specs must teach one idiom). (c) MF-3's first-wins citation (`Analyze-SwydoReport.ps1` A:631-632 `continue`) goes stale once U9 ships: U9 replaces exactly that line with rank precedence, which mostly eliminates the shadowed-account-KPI case; gate 2c stays correct either way, but re-read MF-3's residual against post-U9 code rather than treating the shadowing text as current.

**Verdict restated:** GO-WITH-CHANGES. The DEFER lifts when (and only when) U8 ships as specced; U7b then builds with MF-1..MF-9 folded into its sections, on its own branch/commit/review boundary, additive on the post-U8 TrendAnalyze green count.

*Spec file to write on build:* `C:/projects/swydee/docs/specs/cross-widget-reconciliation-spec.md`

---

## Changelog vs draft (v1 -> v2)

Every blocker/major from the three-lens adversarial review is resolved below; each is tagged `[FIXED]` or `[WONTFIX]` with rationale.

1. **`[FIXED]` #4 over-sum is no longer an unconditional major.** Detail-sum > total is `info RECON_ROW_OVERSUM` by default. A `major DISC_DETAIL_EXCEEDS_TOTAL` fires **only** for a single-dimension widget whose dimension is on a hardcoded **partition allowlist** (campaign/ad_group/keyword/date/...), with **row-count-scaled tolerance** and single-currency. Overlap/multi-attribution dimensions (Facebook `action_type`, named rollups) never reach major. (Reviewers L1-blocker, L2-major.)
2. **`[FIXED]` #5 major removed entirely.** Slice-vs-account is `info RECON_SLICE_OVER_ACCOUNT` only. Filtered KPI cards and per-widget/overridden date ranges are undetectable from schema v2, so "subset exceeds whole" is not provably impossible. (Reviewers L1-blocker, L3-major.)
3. **`[FIXED]` #5 account-KPI lookup no longer defeated by document order.** #5 scans **all** non-blended zero-dim account-scope widgets for `(prov, metricId)`, not the first-wins headline winner; and **excludes `manualKpi`/goal cards** as the account ceiling. (Reviewer L3-major + missing item.)
4. **`[FIXED]` #3 requires the REPORTED ratio's own unit to be confirmed.** New gate R13: skip #3 unless `rm.unit` is non-null AND consistent with `resultKind`. Kills both the false-major (micros not divided on null-unit providers) and the per-report false-info (percent-scaled CTR on non-AdWords/FB). (All three lenses.)
5. **`[FIXED]` Get-MetricUlp is value-aware** (R14). It now mirrors `Format-Metric`'s runtime integer-vs-fractional N0/N1 branch; fractional counts/ratios (conversions 12.7, ROAS 4.2) get step `0.1`, not `1.0`. Drift test extended to cover them. (All three lenses.)
6. **`[FIXED]` #4 tolerance scales with row count** (R15): `tol = max(2, rowCount) * ulp` on the exceeds direction. (Reviewer L1-major.)
7. **`[FIXED]` #6 blocker: no machine-readable period in facts.** New cross-unit dependency **D-period** on U6 to persist `meta.period = { measure, startYm, endYm, calendarAligned }`. #6 consumes that; if absent or relative/unparseable -> `info RECON_TREND_COVERAGE`, never major. `dateRange.primary.measure` is **not** referenced from facts (it is never persisted). (Reviewer L3-blocker.)
8. **`[FIXED]` #6 identity guard** (R18b): assert `meta.clientId` + per-metric `providerId` match between `-PeriodKpiFacts` and the ledger; mismatch -> info/usage-error, never major. (Reviewer L3-major.)
9. **`[FIXED]` #6 coverage gate rewritten against real ledger fields.** Uses `Get-QuarterSum`'s ok-logic (`.state=='final'`, all constituent months present, numeric `.value`, single `byBasis` series). No `.status` field, no `G:405` reference. (Reviewer L3-major.)
10. **`[FIXED]` #6 KPI-vs-months basis gate** (gate 3 extended): `Test-SameBasis` between the period-KPI cell basis and the single summed `basisVersion`. (Reviewer L1-major.)
11. **`[FIXED]` #6 calendar-alignment gate** (gate 1 hardened): requires `meta.period.calendarAligned==true` AND start/end months tile the summed months exactly; a `measure=quarter` label alone never authorizes the equality. (Reviewer L1-major.)
12. **`[FIXED]` #3 display is resultKind-driven** (R19): `ratio`->plain numeric (no currency symbol), `currency`->`Format-Money`, `percent`->`Format-Metric` fraction. ROAS no longer rendered `$4.20`; ctr/cvr no longer hand-rolled. (Reviewers L2/L3 minors.)
13. **`[FIXED]` #3 component disambiguation** (R20): explicit cost-only numerators for cpc/cpm/cpl/cpa; role-qualifier agreement (link vs all); skip when a widget carries multiple ambiguous candidates for the same role. (All lenses, minor.)
14. **`[FIXED]` Test-Summable regex tightened**: `value`->`conversions?_value|conversion_value|(^|_)revenue`; bare `event` dropped; added per-X ratio guard `per[_a-z]`; removed redundant `rate$`. New unit cases. (Reviewers, minor/nit.)
15. **`[FIXED]` negative-remainder handling** (#4): suppress `RECON_ROW_REMAINDER` when `remainderRaw < 0`. (Reviewer nit.)
16. **`[WONTFIX]` per-row currency divergence inside one widget** - documented residual (extractor resolves widget currency first-row-only; per-row currency not exposed in schema v2). Defensive `Test-SameBasis` assert retained. (Reviewer nit.)
17. **`[WONTFIX]` Test-Additive GA4 `user` defect** - unchanged (as v1 R4); follow-up unit. **`[WONTFIX]` DISC cross-basis false positive** - unchanged (R10).
18. **`[FIXED]` divergent predicates in trend pass** (Test-Additive @ L:133 vs Test-Summable @ #6) - documented loudly + regression test pins the intentional split.
19. **Missing tests added** - every reviewer-named FP-guard and traceability case is now in the test plan (sec Test plan), including the alert-fatigue positive-refusal cases each major demanded.

Net severity effect: v2 ships **one** single-report force-surfaced major (#4, tightly gated) and **one** trend force-surfaced major (#6, behind full coverage+identity+basis+alignment gates). #3-unit-signature remains major but is now nearly unreachable (only a genuine ~1e6 provider error with a *confirmed* reported unit). #5 is info-only. This is the calibration the standing invariant demands: *only provably-impossible directions are major.*

---

**Status:** U7a SHIPPED (built, reviewed, merged to main); U7b SHIPPED (built 2026-07-14 with MF-1..MF-9 folded, on branch feat/u8-u9-u10-u7b-build). Check #6 lives in `Analyze-SwydoTrend.ps1` behind the new optional `-PeriodKpiFacts <path>` param (single-report facts with `meta.period` + account headline); `RECON_TREND_MISMATCH` and `RECON_TREND_COVERAGE` are both `severity=info` in v1 (never force-surfaced per MF-1); new pure helpers `Get-MonthSpan`/`Get-MonthRangeSum` (INTEGER month arithmetic, no `[datetime]`); omitted param -> zero `RECON_*` findings + byte-identical trend path. Tests added to `Test-TrendAnalyze.ps1` (24 -> 66). Extends `docs/specs/context-and-canon-spec.md`; **depends on U6** (`docs/specs/canonical-total-spec.md`) including new dependency **D-period** (below). Same discipline: PS 5.1/.NET, pure-ASCII source, functions-first + `-DefineOnly`, hardened scripts reused via `-DefineOnly` dot-source (never mutated), default single-report path byte-for-byte unchanged except additive findings, every credential path fail-closed.

**Blast radius (two sub-units, two commit/review boundaries):**
- **U7a** - checks #3, #4, #5 in `skill/scripts/Analyze-SwydoReport.ps1` ONLY. New tests in `Test-Analyze.ps1`.
- **U7b** - check #6 in `skill/scripts/Analyze-SwydoTrend.ps1` ONLY (+ new optional params). New tests in `Test-TrendAnalyze.ps1`.
- No edit to `Test-ReportNumbers.ps1` (closer), `Get-SwydoReport.ps1`, `ConvertTo-SwydoTrendFacts.ps1`, `Update-SwydoLedger.ps1`, `Manage-SwydoArchive.ps1`, `Sync-SwydoTrend.ps1`.
- **D-period edits `Analyze-SwydoReport.ps1`'s fact-emission (meta block) as part of U6, not U7** (see below).

**Green-count contract:** Analyze `<U6-total>`, Closer 119, Extractor 94, Archive 94, TrendFacts 19, Ledger 50, TrendAnalyze 24, Sync 4. U7a additive on the U6 Analyze total; U7b additive on TrendAnalyze 24. **All other suites re-run green untouched.**

---

## Cross-unit dependency added by v2: **D-period** (folded into U6)

#6 cannot resolve a KPI period to calendar months from the current facts file: `facts.meta` (A:496-504) carries only `currentPeriod` (a **label**, e.g. `"last quarter"` when `periodConfidence=='derived'`, A:197), `previousPeriod`, `periodLabel`, `periodConfidence`. `dateRange.primary.measure` lives on the raw `$doc` only and is **never persisted**.

**D-period (U6 requirement):** when U6 stamps `canonicalVersion`, it also persists a machine-readable period into `facts.meta.period`:
```
meta.period = [ordered]@{
  measure        = 'quarter' | 'month' | 'custom'      # from dateRange.primary.measure
  startYm        = 'YYYY-MM'  or $null                  # first calendar month, if resolvable
  endYm          = 'YYYY-MM'  or $null                  # last calendar month, if resolvable
  calendarAligned= $true|$false                         # start==first-day-of-startYm AND end==last-day-of-endYm
}
```
- Resolvable only when `dateRange.primary` has concrete dates. For a relative/`derived` label with no concrete span, `startYm/endYm=$null`, `calendarAligned=$false`.
- No credential exposure (period dates are not credentials; the existing scrub is unaffected).
- **If D-period is not present at U7b build time, #6 hard-degrades to `info RECON_TREND_COVERAGE` ("no machine-readable period")** and is never `major`. U7b therefore cannot ship a false major even if D-period slips.

*(Rationale: fabricating a quarter from `"last quarter"` + the extraction date is exactly the kind of arithmetic/derivation the model-does-no-arithmetic discipline forbids doing implicitly; the period must be resolved once, in PS, at extraction time, and persisted as data.)*

---

## Why this unit exists

The model does no arithmetic and the closer traces every number, so a *fabricated* total is structurally impossible. What is **not** caught is an *internally inconsistent* set of provider/extraction numbers: a CTR that is not `clicks/impressions`, a campaign table whose rows sum past its own total, a per-campaign slice that exceeds an account KPI, or a quarter KPI that disagrees with the sum of its months. `DISC_CROSS_WIDGET` (A:435-462) compares only identical dimension signatures (A:436-437); every intra-widget-consistency and cross-scope/cross-artifact relation is unchecked. U7 fills those gaps under the standing invariant: **only a provably-impossible-direction violation may be `major` (force-surfaced); every relation schema v2 cannot prove impossible is `info`.**

U7 depends on U6 because #5 reads U6's `canonical.scope`, and U6's A1 `Total-Row` fix guarantees a dimensioned no-total table returns `$null` (never a promoted top slice), without which #4/#5 would operate on garbage.

Build order: **U6 (incl. D-period) -> U7a (#3/#4/#5) -> U7b (#6).**

---

## Ratified decisions (v2)

Unchanged from v1 and still in force: **R1** (flag, never rewrite), **R2** (every introduced number -> `Format-Metric`/`Format-Money` display string, `byFid` only), **R3** (`Format-Metric`/`Format-Money` sole display authority), **R4** (`Test-Summable` is the additivity predicate; `Test-Additive` untouched), **R5** (`Test-SameBasis` gate), **R6** (blended excluded), **R8** (firing tolerance `N=2` as the *base* multiplier; see R15 for N-term scaling), **R9** (`Get-MetricUlp` colocated with `Format-Metric`; superseded in signature by R14), **R10** (no `DISC_CROSS_WIDGET` edit), **R11** (routing into `$disc`/`$gaps`; #6 in trend structure), **R12** (#6 in the trend pass via `-PeriodKpiFacts`).

**New / revised in v2:**

- **R7 (revised - severity calibration, the dominant risk).** The complete set of `major` (force-surfaced) findings is now:
  - **#3 `DISC_RATIO_UNIT`** - only when the reported ratio's **own unit is confirmed** (R13) AND `r  in  [1e5,1e7]`. With a confirmed unit the pipeline divides correctly, so a firing is a genuine ~1e6 provider arithmetic error. Practically rare by design.
  - **#4 `DISC_DETAIL_EXCEEDS_TOTAL`** - only for a **single-dimension, partition-allowlisted** widget (R16), single-currency, with **row-count-scaled tolerance** (R15).
  - **#6 `RECON_TREND_MISMATCH`** - only with D-period present, calendar-aligned, identity-matched, single-basis, KPI-basis==months-basis, all months `final`, metric summable (R18).
  
  Every other U7 relation is `info`, never force-surfaced: #3 same-basis mismatch (`DISC_RATIO_RECOMPUTE`), #4 non-allowlisted over-sum (`RECON_ROW_OVERSUM`) and under-sum remainder (`RECON_ROW_REMAINDER`), **#5 all cases (`RECON_SLICE_OVER_ACCOUNT`)**, #6 any gate failure (`RECON_TREND_COVERAGE`). **When any gate is uncertain, downgrade to `info`.**

- **R13 (new - #3 reported-unit gate).** Skip #3 entirely (defer to `GAP_UNIT_UNCONFIRMED`) unless the **reported ratio metric's `unit` is non-null AND consistent with `resultKind`**: `percent`->`unit=='fraction'`; `currency`->`unit in {'micros', confirmed base money}`; `ratio`->reported cell present and numeric with a confirmed basis for its components. A null/unconfirmed reported unit is an *inference gap*, not a data defect, and must never produce a #3 finding of any severity. (This single gate closes both the micros false-major and the percent-scaled false-info for all non-AdWords/FB providers, since `Unit-Of` infers ratio units only for google-adwords/facebook-ads at G:107-116.)

- **R14 (new - value-aware `Get-MetricUlp`).** Signature becomes `Get-MetricUlp($id,$unit,$currency,$value)`. It mirrors `Format-Metric`'s runtime branch: micros/money -> `0.01`; fraction -> `0.001`; count -> `1` when `abs($value-[math]::Round($value)) -lt 1e-9` else `0.1` (matching `Format-Metric`'s N0/N1 choice at A:96-97); ratio-typed (`Metric-Type` A:78, unit null) -> `0.1` (N1). Per-operand: tolerance uses each operand's own value. `tol = N * max(Get-MetricUlp(A-basis,valA), Get-MetricUlp(B-basis,valB))` with base `N=2` (R8), scaled per R15 for N-term sums. Colocation comment + drift test **U7a-T0 extended** to fractional-count (`12.7`) and ratio (`roas 4.2`) so the value-dependent branch is guarded. The closer's string-based `Get-Ulp` (C:109) is untouched; both now agree on integer *and* fractional counts.

- **R15 (new - N-term tolerance scaling).** For any sum of `k` detail rows/months (#4 exceeds-direction, #4 remainder, #6), `tol = max(2, k) * max-ulp`. A two-operand compare (#3, #5) keeps `2 * max-ulp`. This absorbs up to `k/2` steps of provider per-row rounding accumulated into the sum, preventing a false major on large tables. (Reviewer L1-major.)

- **R16 (new - #4 partition allowlist for major).** `DISC_DETAIL_EXCEEDS_TOTAL` (major) is emitted only when the widget is **single-dimension** (`@($w.dimensions|?{$_}).Count -eq 1`) AND `Test-PartitionDim $w.dimensions[0]` is `$true` (allowlist: `campaign|ad_?group|adset|keyword|search_?term|(^|_)date$|day|week|month|landing_?page|page_?path|country|region|device|channel|source_?medium`). Every other over-sum (multi-dimension, or a non-allowlisted single dimension such as `action_type`, `conversion_action`, hierarchical group rows) -> `info RECON_ROW_OVERSUM`. Partition-ness of these dimensions is domain-known (each row is disjoint) and independent of the metric, so summing across them is legitimately additive; overlap-prone dimensions are excluded by omission. Schema v2 cannot prove partition-ness for anything off the list, so those stay info.

- **R17 (new - #5 is info-only + robust lookup + goal exclusion).**
  - #5 emits only `info RECON_SLICE_OVER_ACCOUNT`; no major (per R7, filtered KPI cards and per-widget/overridden date ranges are undetectable from schema v2).
  - The account KPI is found by scanning **all** non-blended **zero-dimension** data widgets for `(prov, metricId)` with `canonical.scope=='account'` (not the document-order first-wins headline winner), so a table-total-before-KPI-card layout still finds the real account total.
  - **Exclude `manualKpi`/goal/target cards** from the account-ceiling candidate set (`$w.kind`/source flag indicating a manual/goal card - reuse whatever U6 records; if U6 does not distinguish, skip a candidate whose widget has `isGoal`/`manualKpi` marker and document the residual). A target is not a measured ceiling.
  - If more than one zero-dim account candidate exists for the same `(prov,metricId)` with differing values, #5 skips (ambiguous ceiling) rather than picking one.

- **R18 (new - #6 hardened gates).** In addition to v1 gates, #6 requires **all** of:
  1. **Machine-readable, calendar-aligned period** (D-period): `meta.period.calendarAligned==true`, `startYm`/`endYm` non-null, and `startYm..endYm` equals exactly the set of months summed. Amended per U8: a RESOLVED relative period (non-null `startYm`/`endYm`, `calendarAligned==true`) PASSES; only unresolved / `derived`-without-span / `custom` / unparseable / non-aligned / absent -> `info` (key on the persisted fields, not the literal `RELATIVE` token).
  2. **Identity match:** `-PeriodKpiFacts` `meta.clientId` == ledger `clientId`, and the compared metric's `providerId`/`metricId` match. Mismatch -> `info` (or usage-error exit 2 if clientId differs), never major.
  3. **KPI-basis == months-basis:** `Test-SameBasis(periodKpi.unit,periodKpi.currency, monthsBasis.unit,monthsBasis.currency)`. Mismatch -> `info`.
  4. **Ledger completeness via existing `Get-QuarterSum` ok-logic:** all constituent months present, `.state=='final'`, numeric `.value`, one `byBasis` series (the ledger forks on basis change; `GAP_BASIS_CHANGED` already flags multi-basis). **No `.status`/`G:405` reference.**
  5. **Metric `Test-Summable`.**
  Any gate fails -> `info RECON_TREND_COVERAGE` stating why; the equality is **not** computed.

- **R19 (new - #3 resultKind-driven display).** `resultKind=='ratio'` (roas) -> plain numeric `('{0:N2}' -f $recomputedBase)` **no currency symbol**, matching how the reported roas cell (unit null -> `Format-Metric` count branch) renders, so it traces same-typed in `byFid`. `resultKind=='currency'` (cpc/cpm/cpl/cpa/aov) -> `Format-Money`. `resultKind=='percent'` (ctr/cvr) -> `Format-Metric $rm.id 'fraction' $recomputedFraction $cc` (**not** hand-rolled `{0:N1}%`, so it stays inside the R3/R9 display+drift authority). Never route a ratio through `Format-Money` (would prepend a spurious `$` and mistype the `byFid` token).

- **R20 (new - #3 component disambiguation).** `Get-RatioSpec` numerators are **role-pinned**: cpc/cpm/cpl/cpa/cpc numerator = cost-only (`cost_micros|(^|_)cost$|spend|amount_spent`), **never** revenue/value; roas/aov numerator = `conversions_value|conversion_value|revenue|(^|_)value$`. Role-qualifier agreement: a `link`-qualified ratio (`ctrLink`) must pair with a `link`-qualified numerator (`link_click`); an all/unqualified ratio pairs with the unqualified component. If the widget carries **multiple candidate metrics matching the same role pattern** (e.g. both `clicks` and `link_clicks` for an unqualified ctr, or both `cost` and `revenue` where a `(money)` regex would match both), **#3 skips** that ratio (ambiguous components -> no finding). For roas/aov the value component's unit must be confirmed non-null before any unit-signature evaluation.

---

## Shared helpers (define-safe, pure, `-DefineOnly` friendly)

Added to the function region of `Analyze-SwydoReport.ps1` (U7a runs them directly; U7b gets them via the existing guarded `-DefineOnly` dot-source at T:29-32 with the `$my*` capture guard). New helpers: `Test-Summable`, `Test-SameBasis`, `Test-PartitionDim`, `Get-RatioSpec` near the metric helpers; `Get-MetricUlp` directly under `Format-Metric`.

### `Test-Summable($id)` (R4, tightened per v2)
```powershell
function Test-Summable($id){
  $p = Get-MetricPart $id                     # substring after ':', lowercased
  # per-X ratio guard FIRST (screenPageViewsPerSession, eventsPerUser, ...)
  if($p -match 'per[_a-z]'){ return $false }
  # dedup / ratio / average / rank / share denylist
  if($p -match 'reach|frequency|unique|users?$|ctr|_rate$|rate$|average|avg|position|rank|roas|aov|cpc|cpm|cpa|cpl|share|score|cost_per|costper|(^|_)ratio$'){ return $false }
  #   ^ note: 'rate$' subsumes '_rate$'; keep 'rate$' only (redundancy removed)
  # summable allowlist (value tightened; bare 'event' removed)
  if($p -match 'impression|click|conversion|lead|spend|cost_micros|(^|_)cost$|session|order|send|open|revenue|(^|_)call|phone_call|amount_spent|conversions?_value|conversion_value|purchase|bounce'){ return $true }
  return $false
}
```
- `activeUsers`/`totalUsers`/`newUsers`/`uniqueUsers` -> `$false` (GA4 defect fix). `screenPageViewsPerSession`/`eventsPerSession` -> `$false` (per-X guard). `sessions`/`bounces` -> `$true`. `value_per_conversion` -> `$false` (`cost_per` no; but `per[_a-z]` catches it). `ctr`/`average_cpc`/`impression_share`/`average_position`/`roas` -> `$false`.

### `Test-SameBasis($ua,$ca,$ub,$cb)` (R5) - unchanged from v1.

### `Test-PartitionDim($dim)` (R16, new)
```powershell
function Test-PartitionDim($dim){
  if($null -eq $dim){ return $false }
  $d = ([string]$dim).ToLowerInvariant() -replace '[^a-z0-9]',''
  return ($d -match 'campaign|adgroup|adset|keyword|searchterm|date|day|week|month|landingpage|pagepath|country|region|device|channel|sourcemedium')
}
```
Only these known-disjoint dimensions authorize the #4 major. Everything else (notably `actiontype`, `conversionaction`, hierarchical rollups) -> info.

### `Get-MetricUlp($id,$unit,$currency,$value)` (R14, value-aware)
```powershell
# MUST mirror Format-Metric's format specifiers AND its runtime integer-vs-fractional branch
# (kept adjacent so drift is caught by test U7a-T0).
function Get-MetricUlp($id,$unit,$currency,$value){
  if($unit -eq 'micros'){ return 0.01 }               # N2
  if($unit -eq 'fraction'){ return 0.001 }             # {value*100:N1}% -> 0.1% == 0.001 fraction
  if(Test-Money $id $unit $currency){ return 0.01 }    # N2
  # count / ratio-typed (unit null): mirror Format-Metric A:96-97 N0 vs N1
  if($null -ne $value -and ([math]::Abs([double]$value - [math]::Round([double]$value)) -lt 1e-9)){ return 1.0 }
  return 0.1                                            # fractional count / ratio-typed (roas 4.2, conversions 12.7)
}
```
`tolerance = (two-operand: 2 | N-term: max(2,k)) * max(Get-MetricUlp(A,valA), Get-MetricUlp(B,valB))`.

### `Get-RatioSpec($id)` (R20-pinned) - drives #3
Returns `$null` for a non-ratio id, else `[ordered]@{ kind; numPat; numRole; denPat; scale; resultKind }`.

| kind | ratio id-part | numerator part (`numPat`) | numRole | denominator part (`denPat`) | scale | resultKind | formula |
|---|---|---|---|---|---|---|---|
| ctr | `(^\|_)ctr$` | `(^\|_)clicks?$` | all | `impression` | 1 | percent | clicks/impr |
| ctr-link | `ctrlink` | `link_click` | link | `impression` | 1 | percent | link_clicks/impr |
| cpc | `average_cpc\|(^\|_)cpc$` | `cost_micros\|(^\|_)cost$\|spend\|amount_spent` | cost | `(^\|_)clicks?$` | 1 | currency | cost/clicks |
| cpm | `average_cpm\|(^\|_)cpm$` | `cost_micros\|(^\|_)cost$\|spend\|amount_spent` | cost | `impression` | 1000 | currency | cost/impr*1000 |
| cpl | `cost_per.*lead\|(^\|_)cpl$` | `cost_micros\|(^\|_)cost$\|spend\|amount_spent` | cost | `(^\|_)lead` | 1 | currency | cost/leads |
| cpa | `cost_per_conversion\|(^\|_)cpa$` | `cost_micros\|(^\|_)cost$\|spend\|amount_spent` | cost | `(^\|:)conversions?$` | 1 | currency | cost/conv |
| cvr | `conversion_rate\|conv_rate\|(^\|_)cvr$` | `(^\|:)conversions?$` | conv | `(^\|_)clicks?$\|session` | 1 | percent | conv/clicks |
| roas | `roas` | `conversions_value\|conversion_value\|revenue\|(^\|_)value$` | value | `cost_micros\|(^\|_)cost$\|spend` | 1 | ratio | value/cost |
| aov | `aov\|average_order_value` | `conversions_value\|conversion_value\|revenue\|(^\|_)value$` | value | `order` | 1 | currency | revenue/orders |

Numerators are cost-only for cost-ratios (never revenue), value-only for roas/aov (never cost) - closes the ambiguous-`(money)` mis-pair. `numRole`/qualifier drives R20 role agreement and skip-on-ambiguity.

**Post-build amendment:** `costperactiontype` is REMOVED from the cpa row. A Facebook `costPerActionType::<action>` metric's denominator is the `<action>` count (link_click, video_view, landing_page_view, ...), NOT conversions; blanket-mapping it to a conversions denominator recomputed an unrelated ratio and produced false findings - a routine false `DISC_RATIO_RECOMPUTE` and, when link_clicks >> conversions, a false `DISC_RATIO_UNIT` **major**. Only the unambiguous google `cost_per_conversion`/`cpa` is reconciled; compound `costPerActionType::<action>` ratios are skipped (`Get-RatioSpec` returns `$null`). Deriving a per-action denominator is possible future work but risks self-matching the reported metric, so it is deferred. Also note R20 role-agreement is enforced in `Get-RatioReconFindings` (an `all` ratio pairs only with an unqualified numerator, a `link` ratio only with a link-qualified one), and link-basis CTR ids (`inline_link_click_ctr`, ...) are matched to the `ctr-link` row BEFORE the plain `ctr` row.

---

## Check #3 - Ratio recompute (ratio-of-totals), reported-unit gated

**Purpose:** validate a natively-reported ratio against its own total-row components as **ratio-of-totals** (never average-of-ratios), catching Simpson's-paradox provider ratios and confirmed-unit ~1e6 arithmetic errors.

**Scope / inputs:** one non-blended data widget; `$tr = Total-Row $w` (post-U6; `$null`->skip - this also skips a time-dimensioned native-ratio widget, which has no total row, so #3 never collides with the `Get-TimeSeries` derive path A:289). For each ratio metric `$rm` with `Get-RatioSpec $rm.id` non-null:
1. **R13 reported-unit gate:** `$rm.unit` non-null AND consistent with `resultKind`; else skip.
2. Locate components via `Find-Metric` with **R20** role agreement; if ambiguous (multiple same-role candidates) skip.
3. All three present as scalars on `$tr`; money/value component unit confirmed non-null (else skip - defers to `GAP_UNIT_UNCONFIRMED`).

**Formula (Get-TimeSeries precedent A:297-303; convert micros; zero/null denom -> skip, no division):**
```
numBase = (num.unit=='micros') ? Row-Cur(tr,num)/1e6 : Row-Cur(tr,num)
denBase = (den.unit=='micros') ? Row-Cur(tr,den)/1e6 : Row-Cur(tr,den)
if(denBase == null || denBase == 0){ skip }
recomputedBase = (numBase / denBase) * spec.scale
reportedBase   = (rm.unit=='micros') ? Row-Cur(tr,rm)/1e6 : Row-Cur(tr,rm)   # fraction stays as-is (now guaranteed confirmed)
```

**Decision & severity (R7):** `r = reportedBase / recomputedBase` (skip if `recomputedBase==0`).
- **`major DISC_RATIO_UNIT`** - reported unit confirmed (R13, already true here) AND `r  in  [1e5,1e7]` OR `1/r  in  [1e5,1e7]`. Cause: `"micros-not-divided (reported ratio ~1e6x its components)"`. With a confirmed unit this is a genuine provider arithmetic defect. (Band `[1e5,1e7]` retained; a `[1e3,1e9]` widening is a documented follow-up if milli-confusions surface - see Residuals.)
- **`info DISC_RATIO_RECOMPUTE`** - not the unit signature AND `abs(reportedBase-recomputedBase) > 2*max(Get-MetricUlp(reported), Get-MetricUlp(recomputed))`. Cause: `"provider ratio basis differs from components (filtered denominator or average-of-ratios)"`.
- else no finding.

**Fact emission (R2, R19):** reported via `Format-Metric $rm.id $rm.unit <cell> $cc`; recomputed via the resultKind branch (R19). Statement: `"$pname '$($rm.metric)' reported $dispReported but $($spec.kind) of the total-row components is $dispRecomputed ($cause)"`; `evidence=[ordered]@{ reported; recomputed; components="$dispNum / $dispDen" }`. Routed to `$disc`->byFid. Major echoes `<!-- finding:DISC_RATIO_UNIT#n -->`; the info variant's fid anchor is required on any line citing `$dispRecomputed`.

---

## Check #4 - Detail-rows-sum vs widget total (summable, full rows)

**Purpose:** within one dimensioned widget with an explicit total row, verify `Sum(detail) ~= total`; over-sum on a true partition is a duplicate/double-count defect; under-sum is truncation -> honest "(other)" remainder.

**Scope / inputs:** non-blended data widget, `@($w.dimensions|?{$_}).Count > 0`, `$tr = Total-Row $w` non-null (post-U6 => explicit total). Detail set = `Get-BreakdownFindings`'s filter (A:131): `@($w.rows|?{ $_.kind -eq 'data' -and -not (Test-GroupRow (Row-Label $_)) })` (Test-GroupRow drops literal `All`/`(group)` only). For each metric `$m` with `Test-Summable $m.id`.

**Basis:** widget currency is widget-wide (G:186); assert `Test-SameBasis` defensively. **Per-row currency divergence is a documented residual (WONTFIX)** - schema v2 exposes only widget currency (first-row-resolved). Sum in raw units, format once:
```
sumRaw   = Sum over detail rows of Row-Cur(row,$m.name)   # nulls skipped
totalRaw = Row-Cur($tr,$m.name)
k        = detail row count
# compare in base units (divide micros by 1e6 both sides)
ulp = max(Get-MetricUlp($m.id,$m.unit,$cc,sumBase), Get-MetricUlp($m.id,$m.unit,$cc,totalBase))
```

**Decision & severity (R7, R15, R16):**
- `sumBase - totalBase > max(2,k)*ulp`:
  - **partition-allowlisted single-dim (R16) & single-currency -> `major DISC_DETAIL_EXCEEDS_TOTAL`** (force-surfaced; echo `<!-- finding:DISC_DETAIL_EXCEEDS_TOTAL#n -->`); cause `"detail rows exceed the widget total on a partition dimension - possible duplicated/double-counted rows"`.
  - **otherwise -> `info RECON_ROW_OVERSUM`** (pushed to `$gaps`); cause `"listed rows sum above the widget total; dimension may double-count (overlapping/multi-attribution values)"`. Never blocks delivery.
- `totalBase - sumBase > max(2,k)*ulp` AND `remainderRaw = totalRaw - sumRaw >= 0` -> **`info RECON_ROW_REMAINDER`** (`$gaps`); `evidence=[ordered]@{ total; shownSum; other }`. If `remainderRaw < 0` (negative-tail rows: refunds/credits) -> **suppress** (no finding). The report MAY render an "(other)" bucket citing `$other`, echoing the fid.
- within tolerance -> no finding.

Sum is over **all** detail rows (not the top-20 cap), so the remainder captures server-side truncation.

---

## Check #5 - Slice-total vs account KPI (info-only; robust lookup)

**Purpose:** surface (never block) a dimensioned slice total exceeding a measured account KPI. Because filtered KPI cards and per-widget/overridden date ranges make this legitimately possible and are undetectable from schema v2, **#5 is `info` only** (R17).

**Scope / inputs:** for each non-blended dimensioned data widget with an explicit total row `$tr`, `$prov = Get-WidgetProvider $w`. For each metric `$m` with `Test-Summable $m.id`:
- Account KPI = scan **all** non-blended **zero-dim** data widgets for `(prov, $m.id)` with `canonical.scope=='account'`, **excluding `manualKpi`/goal cards**. If none -> skip (no authoritative measured ceiling). If multiple with differing values -> skip (ambiguous).
- `Test-SameBasis($m.unit,$cc, $kpi.unit,$kpi.currency)` - mismatch (incl. null-unit) -> skip.
```
sliceBase = (m.unit=='micros') ? Row-Cur(tr,m)/1e6 : Row-Cur(tr,m)
kpiBase   = (kpi.unit=='micros') ? kpi.current/1e6 : kpi.current
ulp = max(Get-MetricUlp($m.id,$m.unit,$cc,sliceBase), Get-MetricUlp($m.id,$kpi.unit,$kpi.currency,kpiBase))
```
- `sliceBase - kpiBase > 2*ulp` -> **`info RECON_SLICE_OVER_ACCOUNT`** (`$disc`). `evidence=[ordered]@{ slice; account; dimension; note="slice exceeds measured account KPI; if the KPI card is filtered or the table spans a different period this is expected" }`. Statement names both scopes.
- `sliceBase <= kpiBase` -> no finding.

Restricted to `Test-Summable`. Ratio/dedup metrics excluded (a slice CTR can exceed account CTR; reach/users forgone conservatively).

---

## Check #6 - Monthly-series-sum vs period KPI (U7b; fully gated)

**Placement (R12):** `Analyze-SwydoTrend.ps1`, which reads the ledger (`providerId|metricId|basisVersion|YYYY-MM`, cells expose `.state`/`.value`/`.byBasis`, L:80-81) and emits `*.trendanalysis.facts.json` verified by its own Mode-C closer. New optional params: `-PeriodKpiFacts <path>` (single-report facts with U6 `meta.period` + account headline). Both inputs are scrubbed facts; **no raw extraction opened**.

**Gates (R18 - all must hold before the two-sided equality):**
1. **D-period present & calendar-aligned:** `-PeriodKpiFacts` provided; `meta.period.calendarAligned==true`; `startYm`/`endYm` non-null; the summed month set == `startYm..endYm` inclusive. (Amended per U8, keying EXCLUSIVELY on the persisted `meta.period` fields, NOT the wire `type=='RELATIVE'` token: a RESOLVED relative period -- non-null `startYm`/`endYm`, `calendarAligned==true` -- PASSES this gate; only unresolved / `derived`-without-span / `custom` / non-aligned / absent degrade to `info`. The prior "Relative -> info" shorthand was pre-U8; a builder re-adding a literal-`Relative` branch would re-inertify #6 and defeat U8 entirely.)
2. **Identity:** `meta.clientId` matches the ledger's; the metric's `providerId`/`metricId` match. clientId mismatch -> usage-error (exit 2) or `info`; provider/metric mismatch -> skip that comparison. Never major.
3. **Basis (two parts):** (a) all summed months share one `basisVersion` (via `byBasis`, single series); (b) `Test-SameBasis(periodKpi.unit,periodKpi.currency, monthsBasis.unit,monthsBasis.currency)`. Either fails -> `info`.
4. **Completeness (real ledger fields):** `Get-QuarterSum` ok-logic - every constituent month present, `.state=='final'`, numeric `.value`. (No `.status`; no `G:405`.)
5. **`Test-Summable $metricId`** (GA4 `activeUsers` etc. -> gate fails -> `info`).

**Decision & severity (R7):**
```
sumBase = Sum over the period's months of the cell base value (micros/1e6 where unit=='micros')
kpiBase = period KPI base (canonical account headline)
k       = month count
ulp     = max(Get-MetricUlp(metricId,unit,currency,sumBase), Get-MetricUlp(metricId,unit,currency,kpiBase))
```
- **All gates pass** AND `abs(sumBase-kpiBase) > max(2,k)*ulp` -> **`major RECON_TREND_MISMATCH`**. `evidence=[ordered]@{ monthsSum; periodKpi; months="<n>/<n> final"; basis="<unit>/<currency>"; period="<startYm>..<endYm>" }`. Echo `<!-- finding:RECON_TREND_MISMATCH#n -->`.
- **Any gate fails** -> **`info RECON_TREND_COVERAGE`** stating the reason (no machine-readable period / not calendar-aligned / identity mismatch / basis fork / KPI-basis differs / missing or non-final months / non-summable). Equality not computed.
- Gates pass & within tolerance -> no finding (optionally an `info` clean-recon citing both display strings).

**Predicate-split note (R4 residual, now documented in-code):** the existing QoQ/YoY comparison (Analyze-SwydoTrend L:133) still gates on `Test-Additive` (unchanged); #6 gates on `Test-Summable`. For GA4 `activeUsers` the trend pass therefore still emits a QoQ comparison (pre-existing behavior) but #6 correctly emits **no** `RECON_TREND_MISMATCH`. A loud comment at L:133 and a regression test pin this intentional divergence so a future "unification" cannot silently flip #6's calibration.

---

## Gates summary

| Gate | Helper | Rule | Applies |
|---|---|---|---|
| Summable/dedup | `Test-Summable` (R4) | per-X/dedup/ratio/avg/rank/share -> not summable | #4,#5,#6 |
| Partition (major only) | `Test-PartitionDim` (R16) | single known-disjoint dim authorizes #4 major | #4 |
| Reported-unit | R13 | ratio metric's own unit confirmed & resultKind-consistent | #3 |
| Component role | `Get-RatioSpec`+`Find-Metric` (R20) | role-pinned; skip on ambiguity | #3 |
| Tolerance | `Get-MetricUlp`(value-aware R14)+N (R8/R15) | `max(2,k)*max-ulp` (N-term) / `2*max-ulp` (2-op) | all |
| Display authority | `Format-Metric`/`Format-Money` (R3,R19) | resultKind-driven; no hand-rolled numbers | all |
| Basis-match | `Test-SameBasis` (R5) | unit AND currency identical else skip | #4(assert),#5,#6 |
| Blended exclusion | `Test-Blended` (U6, R6) | providers>1 -> skip | all |
| Period/identity (#6) | R18 | D-period + calendar-aligned + clientId/provider + KPI-basis | #6 |
| Severity | R7 | provably-impossible -> major; else info | all |

---

## Closer integration (no closer edit)

- All U7 single-report findings enter `$disc`/`$gaps`, get a fid from the A:482 pass, index into **`byFid` only** (C:245-255), `hasComparison=$true` via `Add-StringNumbers` over `statement`+`evidence.*`. Numbers are in scope for exactly one report line (the fid-anchored one, C:371-376) and never enter `global`/`byPlatform` (anti-haystack, C:198-200).
- Majors (#3-unit, #4-exceeds, #6-mismatch) are force-surfaced by gate 3a (C:414-434), matched by delimited regex (`#1` not masked by `#10`). A false major blocks delivery - hence R7's conservative gates.
- Info findings trace only if the report cites them on the fid-anchored line (else `untraceable-number`).
- **#3 ROAS traceability (R19):** the recomputed ratio is formatted the same way as the reported roas cell (plain numeric, no `$`, no `x` suffix), so it is a same-typed `byFid` candidate and traces; it is not routed through `Format-Money` (currency mistype) nor emitted with an `x` suffix (which the closer's `<mult>` token C:52 would silently exempt from verification).
- **#3 percent (R19):** ctr/cvr recompute is `Format-Metric` fraction output (byte-equal to the reported cell's formatter), so R3/R9/U7a-T0 cover it.
- No closer code changes; 119 stays green (pinned by U7a-T-closer). U7b rides the identical mechanism in the trend closer.

---

## Interaction with existing `DISC_CROSS_WIDGET` (A:435-462)

Disjoint from all U7 checks: #3 intra-widget ratio-vs-components (DISC never recomputes ratios); #4 intra-widget detail-vs-total (DISC never sums details); #5 cross-scope (DISC refuses differing dimSig, A:436-437); #6 cross-artifact (DISC is single-artifact). No pair can double-fire. DISC's code and its pre-existing cross-basis false-positive are untouched (R10); U7's `Test-SameBasis` protects only the new checks.

---

## Build / test ordering

1. **U6 + D-period** land (canonical + A1 Total-Row fix + `meta.period`). Hard prerequisite.
2. **U7a** (`Analyze-SwydoReport.ps1`: helpers + #3/#4/#5): insertion **immediately after the `DISC_CROSS_WIDGET` block (A:462), before the row-level breakdown block (A:464)**; `$platforms` (with U6 `canonical`), `$dataWidgets`, `$disc`, `$gaps` in scope; fid pass (A:482) assigns fids. Commit after new `Test-Analyze` cases green + ALL suites green.
3. **U7b** (`Analyze-SwydoTrend.ps1`: `-PeriodKpiFacts` + #6 + guarded `-DefineOnly` dot-source of Analyze via `$my*` capture, no new helper param named `$Facts`/`$From`/`$Into`/`$Execute`): commit after new `Test-TrendAnalyze` cases green + ALL suites green.

Both additive-in-facts; default numeric surface unchanged except new findings.

---

## PS 5.1 hazards specific to this change

- `@($null).Count==1`: dimension counts via `@($w.dimensions|?{$_}).Count`; detail/candidate collections always `@(...)`-wrapped before `.Count`/indexing; single-element function returns `@(...)`-wrapped.
- Case-insensitive collisions: new locals (`$spec`,`$numBase`,`$denBase`,`$recomputedBase`,`$reportedBase`,`$sumRaw`,`$totalRaw`,`$remainderRaw`,`$sliceBase`,`$kpiBase`,`$ulp`,`$k`,`$cause`,`$kpiCandidates`) do not match any dot-sourced param. **No closer dot-source into Analyze** (would collide `$facts`/`$Facts`). U7b's Analyze dot-source is `-DefineOnly` + `$my*` guard. **Do NOT dot-source `Update-SwydoLedger.ps1`** (param block clobbers caller vars) - `Test-SameBasis` replaces the basis concept locally.
- Sum in raw units, format once. `[double]` casts only inside `Row-Cur`.
- Zero/null denominator in #3/any ratio -> skip.
- `ConvertTo-Json -Depth 40 -Compress` (A:508) covers the shallow nesting.

---

## Test plan (every reviewer-named case included)

All e2e cases write a minimal `schemaVersion:2` extraction to a temp file and run `Analyze-SwydoReport.ps1 -InFile <tmp> -OutDir <tmp>` (U7a) or the trend pass (U7b), then inspect the emitted facts.

**U7a-T0 - helper units (`-DefineOnly`)**
- `Test-Summable` TRUE: `...:impressions`/`clicks`/`conversions`/`sessions`/`spend`/`cost_micros`/`conversions_value`/`bounces`.
- `Test-Summable` FALSE: `google-analytics-4:activeUsers`/`totalUsers`/`newUsers`/`...:uniqueUsers` (GA4 regression), `...:ctr`/`average_cpc`/`impression_share`/`average_position`/`roas`, **`...:screenPageViewsPerSession`/`eventsPerSession` (per-X guard)**, **`...:value_per_conversion`**.
- `Test-SameBasis`: `(micros,USD)==(micros,USD)` T; `(micros,USD)vs(micros,EUR)` F; `(null,null)==(null,null)` T; `(micros,USD)vs(null,USD)` F.
- `Test-PartitionDim`: `campaign`/`ad_group`/`keyword`/`date` T; `action_type`/`conversion_action`/`audience` F.
- **`Get-MetricUlp` vs `Format-Metric` drift (extended R14):** money/micros -> 0.01; fraction -> 0.001; **integer count (value 9) -> 1.0; fractional count (value 12.7) -> 0.1; ratio-typed (roas value 4.2) -> 0.1** - each asserted equal to the step implied by `Format-Metric`'s output for that value.
- `Get-RatioSpec`: returns ctr/ctr-link/cpc/cpm/cpl/cpa/cvr/roas/aov specs for representative ids; `$null` for `impressions`; roas/aov numerator is value-only, cpc/cpm/cpl/cpa numerator is cost-only.

**Check #3**
- CTR `clicks=500,impr=10000,ctr(fraction)=0.05` -> recomputed 5.0%, reported 5.0% -> **no finding**.
- CTR `ctr(fraction)=0.08` (avg-of-ratios) -> **info `DISC_RATIO_RECOMPUTE`**, `evidence.recomputed=='5.0%'`.
- CPC reported `average_cpc` **confirmed micros** but ~1e6x components -> **major `DISC_RATIO_UNIT`**, cause contains `micros`, fid present.
- **FP - reported ratio unit null (R13):** non-AdWords/FB widget, native CTR (unit null) + clicks + impressions, CTR stored as `5.0` (percent-scaled) -> **no finding** (defers to `GAP_UNIT_UNCONFIRMED`); assert neither major nor info.
- **FP - null-unit micros ratio (the escalation case):** Microsoft-style `cost_micros`(confirmed) + `average_cpc`(unit null, micros-scale) -> **no finding** (R13 skip), *not* a `DISC_RATIO_UNIT` major.
- **FP - zero denominator:** `clicks=0` -> skip, no division.
- **FP - money component unit null:** value/cost `unit=null` -> skip.
- **FP - no native ratio:** clicks+impr, no ctr -> nothing (Get-TimeSeries derive path).
- **FP - ambiguous components (R20):** widget has both `clicks` and `link_clicks` with an unqualified `ctr` -> skip (no finding).
- **FP - time-dimensioned native ratio (no total row post-U6):** `Total-Row` null -> #3 skips; no collision with derive path.
- **Display/trace - ROAS (R19):** roas reported cell `4.2` (unit null), components mismatch -> info recompute rendered plain `5.5` (no `$`, no `x`); assert it traces on the fid-anchored line and is NOT currency-typed / NOT `<mult>`-exempt.
- **R3 drift - ctr/cvr recompute string == `Format-Metric` fraction output** (byte-equal).

**Check #4**
- Partition dim (`campaign`) detail rows summing above total (duplicate) -> **major `DISC_DETAIL_EXCEEDS_TOTAL`**, fid echoed, sum/total displays in evidence.
- **FP - overlap dimension NOT major:** `action_type` widget where a purchase is counted under multiple action rows so `Sum(rows) >> total` -> **info `RECON_ROW_OVERSUM`**, `severity=='info'`, NOT `DISC_DETAIL_EXCEEDS_TOTAL`.
- **FP - multi-dimension NOT major:** two-dim widget over-summing -> info, not major.
- Under-sum (top-N truncation) -> **info `RECON_ROW_REMAINDER`** in `dataGaps`; `evidence.other`=total-shownSum; no major.
- **FP - negative remainder suppressed:** a negative refund tail row makes `remainderRaw<0` -> **no `RECON_ROW_REMAINDER`**.
- **FP - dedup metric not summed:** `users` rows summing past total -> no #4 finding.
- **FP - row-count tolerance (R15):** 300 integer-count rows each provider-rounded, netting `sum-total ~= +120` (< `max(2,300)*1`=300) -> **no major**; a case at `+320` -> major (asserts scaling both directions).
- **FP - fractional-count tolerance (R14):** conversions rows `4.5+5.5` total `9.0` vs a `12.0` total -> over/under behaves at step 0.1, not 1.0 (assert a 0.5-conv gap is detected, not swallowed).
- **FP - 1-cent rounding:** sum vs total differ < `2*ULP` -> no finding.
- **FP - no explicit total (post-U6):** dimensioned no-total widget -> `Total-Row` null -> skip.

**Check #5**
- Slice `spend=$120` vs account KPI `spend=$100`, same basis -> **info `RECON_SLICE_OVER_ACCOUNT`** (assert `severity=='info'`, NOT major), both scope displays + `note` in evidence.
- **FP - filtered slice:** slice `$80` vs KPI `$100` -> no finding.
- **FP - mixed currency:** slice `(micros,EUR)` vs KPI `(micros,USD)` -> `Test-SameBasis` false -> skip.
- **FP - KPI unit null:** `Test-SameBasis(micros,USD, null,USD)` false -> skip.
- **FP - ratio metric:** slice CTR 6% vs account CTR 4% -> not summable -> skip.
- **Lookup - document-order loss (R17):** fixture where the dimensioned total-row widget PRECEDES the zero-dim account KPI for the same `(prov,metric)` -> #5 still finds the account total (scan-all, not first-wins) and emits the info.
- **FP - goal/manualKpi ceiling excluded (R17):** the only zero-dim cell is a `manualKpi`/goal card -> #5 skips (no measured ceiling); assert no finding.
- **FP - ambiguous ceiling:** two differing zero-dim account cells -> skip.
- **FP - no account KPI at all:** only the dimensioned table exists -> skip.

**Check #6 (U7b, trend pass)**
- Quarter KPI `sessions=30000`, D-period calendar-aligned `2026-04..2026-06`, 3 months `10000x3`, one basis, all `final`, clientId matches -> within tolerance -> no major (optional clean-recon info).
- Same but months sum `35000` -> **major `RECON_TREND_MISMATCH`**, `months=='3/3 final'`, both displays + `period` in evidence.
- **FP - no machine-readable period:** `meta.period.calendarAligned==false` / relative `"last quarter"` (`periodConfidence=='derived'`) -> **info `RECON_TREND_COVERAGE`** ("no machine-readable period"), no crash, no major.
- **FP - non-calendar-aligned (rolling Feb15-May14 labeled quarter):** `calendarAligned==false` -> info, equality not run.
- **FP - partial/missing month:** 2 of 3 months `final` (or 3rd is partial/absent) -> info, no major.
- **FP - identity mismatch (R18b):** `-PeriodKpiFacts` clientId != ledger clientId -> **no major** (info or usage-error exit 2); provider/metric mismatch -> skipped.
- **FP - KPI-basis vs months-basis (R18/gate3b):** ledger months USD, period KPI EUR -> info, never major.
- **FP - basis fork mid-quarter:** currency change forks `basisVersion` -> gate 3a fails -> info.
- **FP - dedup metric:** GA4 `activeUsers`, 3 months summing above the quarter KPI -> `Test-Summable` false -> info, never major.
- **FP - no `-PeriodKpiFacts`:** omitted -> info availability note; trend path still delivers.
- **Predicate-split (R4 residual):** GA4 `activeUsers` receives a QoQ comparison (Test-Additive path unchanged) BUT no `RECON_TREND_MISMATCH` (Test-Summable path) - pins the intentional divergence.
- **Happy-path resolution:** explicit `-PeriodKpiFacts` whose `meta.period` resolves to `2026-04..2026-06` with all 3 months `final` - asserts the quarter is resolved from `meta.period` (not from a fuzzy label).

**Cross-suite / regression**
- **U7a-T-closer:** closer against facts carrying #3/#4/#5 findings -> **119 green**; each major's number traces only on its anchored line; a #4-remainder number is `untraceable-number` on a non-anchoring line but traces on the fid-anchored line; **ROAS recompute traces** (R19) and is not `<mult>`-exempt.
- **U7b-T-closer:** trend closer against `*.trendanalysis.facts.json` carrying `RECON_TREND_*` -> green; mismatch major force-surfaced.
- **fid uniqueness/stability:** one widget producing `DISC_RATIO_RECOMPUTE` + `DISC_CROSS_WIDGET` + a second recompute -> per-ruleId ordinals `#1,#2` unaffected by interleaving with other ruleIds.
- **Ratio-fixture sweep:** audit every existing `Test-Analyze` fixture with a native ratio whose `ctr != clicks/impressions`; expectation: none trips #3 (all have confirmed units and consistent numbers) - explicitly update any that encode a documented behavior change; protects the 135 green.
- Analyze `<U6-total>`+U7a, Closer 119, Extractor 94, Archive 94, TrendFacts 19, Ledger 50, TrendAnalyze 24+U7b, Sync 4 re-run green.

---

## Residuals (explicit non-goals)

- **`Test-Additive` GA4 `user` defect** - WONTFIX in U7 (R4). Still mis-classes `user` for `DISC_CROSS_WIDGET`/ANOM_CONCENTRATION/pacing; consolidating to `Test-Summable` is a follow-up with its own green-count audit. The trend-pass predicate split is now documented in-code (L:133 comment + regression test).
- **`DISC_CROSS_WIDGET` cross-basis false positive** - pre-existing, untouched (R10). U7's `Test-SameBasis` protects only new checks. WONTFIX.
- **Per-row currency divergence inside one widget** - WONTFIX. Schema v2 exposes widget currency only (first-row-resolved, G:186); a defensive `Test-SameBasis` assert remains. Documented gap for #4/#5.
- **#3 unit-signature band `[1e5,1e7]`** - retained. A `[1e3,1e9]` widening (milli/centi confusions) is a documented follow-up; not shipped absent evidence.
- **#5 dedup/monotonic metrics** (reach/users) - deliberately forgone (excluded by `Test-Summable`) to avoid any false finding.
- **#6 non-month-aligned / relative periods** - never run the equality (gate 1). **Timezone/period-boundary micro-alignment** across the KPI period and ledger calendar months is not modeled (a month straddling a timezone-defined boundary) - documented minor; the `calendarAligned` gate operates on the persisted `startYm/endYm` and does not resolve sub-day timezone offsets.
- **#4 metric-side overlap on a partition dimension** - not modeled; partition-allowlisted dimensions are domain-known disjoint, so the metric cannot multi-count across rows. If a future provider emits an overlapping metric on a partition dim, it would false-major; considered acceptable and monitored via the allowlist (add-only).

## For the reviewer (adversarial, v2)

- **Only three majors remain**, each behind a gate schema v2 can actually evaluate: #3-unit needs a *confirmed* reported unit (so it fires only on genuine provider arithmetic error, not our inference gaps); #4-exceeds needs a known-disjoint single partition dimension + row-count tolerance; #6-mismatch needs D-period calendar alignment + identity + basis + completeness. Confirm each gate is airtight and that no `info`-worthy asymmetry was re-promoted to major.
- **#5 is now info-only** - confirm this acceptable degradation (a real subset-exceeds-whole error surfaces as info with a fid, tracing on its anchored line, but never wedges delivery).
- **D-period is a hard U6 dependency** - confirm U6 will persist `meta.period`; if it cannot, #6 self-degrades to info and the unit still ships correctly.
- **Get-MetricUlp is now value-aware** - confirm the drift test's fractional-count/ratio cases pin it to `Format-Metric`'s runtime branch, closing the R9 "cannot drift" gap the reviewers falsified.