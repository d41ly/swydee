# U8 - Extractor period resolution (RELATIVE -> concrete months) (spec v1)

## AMENDMENTS v1 (post adversarial review, 2026-07-12 — these OVERRIDE the body below)

Review verdict: **GO-WITH-CHANGES** (correctness GO-WITH-CHANGES - discipline GO-WITH-CHANGES - fatigue GO-WITH-CHANGES).

- **Correctness must-fix (count cast):** in `Resolve-ReportPeriod`, replace `$n=[int]$p.count` with `$n=[double]$p.count`. The `[int]` cast in PS 5.1 ROUNDS (banker's), it does not truncate: `count=-0.6` and `count=-1.4` both cast to `-1` and would RESOLVE to a complete-period span, violating D1's closed domain and EC-5's to-date guarantee — a hand-edited/wire fractional count would silently persist the one wrong artifact this unit must never produce (a plausible span that later feeds U7b's only major). `[double]` preserves every EC-9 case (`[long]-1`, `[double]-1.0`, `'-1'` pass; `'abc'` still throws into the catch) while making the `-1` test exact. Extend **U8-E12** with `-1.4` and `-0.6` -> null fixtures. (Verified empirically: `[int]-0.6` and `[int]-1.4` both yield `-1`.)
- **Correctness must-fix (D7 regex guard):** tighten `Get-PeriodMeta`'s guard from `^\d{4}-\d{2}$` to `^[0-9]{4}-(0[1-9]|1[0-2])$` on BOTH `startYm` and `endYm`. .NET `\d` matches Unicode digits (Arabic-Indic `٠١٢٣-٠٤` passes) and `\d{2}` admits months 13-99; a hand-edited `'2026-13'` would reach `facts.meta.period` with `calendarAligned=true` and later alias to a real month via `MonthKeyToOrdinal`'s identical `\d` pattern (G:241). D7's stated garbage-exclusion guarantee must actually hold. Extend **U8-A3** with `'2026-13'` and a Unicode-digit fixture. (Both leaks verified empirically.)
- **Fatigue must-fix (D1 month/year admission is evidence-free — probe or shrink):** before build, run the one-query live probe (`Fetch-Widget` with `New-RelDateRange -1 'month'`; inspect the server-labeled month(s) returned: last-complete vs current-partial) and cite the result in D1. If the probe cannot be run, D1's accepted domain SHRINKS to `quarter/-1` only, with `month/-1` and `year/-1` moved behind the same live-probe gate the body already imposes on `count<=-2` (Residuals). Rationale: the "no alternative reading" defense is prose the spec's own evidence undercuts — the EC-7 hypothesis (server window `[cur-N+1..cur]` including the current partial period, from G:405) applied at N=1 IS an alternative reading ("this month to date"), and D9 already demonstrates this API's date tokens are non-literal (`previousMonth` rendering the previous quarter, S:144). Only `quarter/-1` is live-verified. A wrong `month/-1` span would be systematic across every monthly report and pass every U7b gate. *Conflict resolution: the correctness lens accepted this as a residual (first-live-report pin noted for the U7b reviewer); the fatigue lens's stricter gate wins because meta.period's whole purpose is to authorize a future major, and the probe is one query.* If the probe confirms last-complete semantics, the correctness lens's residual note still applies to `year/-1` unless probed too.
- **Discipline must-fix (green-count arithmetic):** the Green-count contract total is **680**, not 690 (276+119+94+94+19+50+24+4 = 680; every per-suite figure re-verified correct on `main` @ `cccd0c9`). Read the body's "total 690" as 680; fix the line at build time.
- **Discipline must-fix (C6:5 supersession must be explicit):** U8 builds D-period standalone while U7b stays deferred, contradicting the AUTHORITATIVE C6 critic override ("When U7b is undeferred, D-period is built with it", `canonical-total-spec.md:5`). Silent contradiction of ratified canon is forbidden. The build MUST add `docs/specs/canonical-total-spec.md` to the blast-radius table (this overrides the body's table) with a one-line additive supersession note at the C6:5 override — "sequencing superseded by U8: D-period built ahead of U7b as its own unit, spec `extractor-period-resolution-spec.md`" — or place the equivalent explicit supersession in the units-index U8 row. The canon must not carry two contradictory authoritative statements after merge.
- **Discipline+fatigue must-fix (mandatory U7b cross-reference + R:274 rewording + the EC-2 decision, recorded NOW):** the body's "Optionally annotate U7b's row" becomes MANDATORY, and `docs/specs/cross-widget-reconciliation-spec.md` joins the blast-radius table (deferred design prose only; U7b's Status stays DEFERRED; the FORBIDDEN list covers scripts/tests, not spec docs — this overrides the body's table). Three bindings, all doc-only, in this same commit: (1) the U7b units-index row states "precondition met by U8". (2) R:274's gate-1 parenthetical "(Relative/`derived`/`custom`/non-aligned/absent -> `info`)" is amended as pre-U8 shorthand: a RESOLVED relative period (non-null `startYm/endYm`, `calendarAligned==true`) PASSES gate 1; only unresolved / derived-without-span / custom / non-aligned / absent degrade to info — otherwise the sole consumer would literally-read "Relative" and discard exactly the population U8 exists to enable, making U8 dead-on-arrival at undeferral. (3) The EC-2 boundary-skew decision (reviewer Q2, "decide before U7b is built") is DECIDED by the U7b re-review's **MF-4** (`cross-widget-reconciliation-spec.md`, "Re-review vs U8 spec" block) and this spec defers to it verbatim: gate 1b cross-checks the resolved span against the `-PeriodKpiFacts` file's OWN monthly timeSeries bucket labels (server-returned `YYYY-MM` labels emitted by `Get-TimeSeries`, `Analyze-SwydoReport.ps1:765-766`; verified present in the archived QCU live facts as `2026-04..2026-06`); disagreement -> coverage `info`; absence of such a series -> proceed (documented residual). *[Corrected 2026-07-12 by the cross-cutting critic: this bullet's earlier draft claimed KPI facts carry no server month labels and prescribed an `anchorDate`-proximity downgrade — the claim is factually false against the live fixture, and the downgrade is DROPPED (MF-4 declined it; `anchorDate` stays persisted for audit only).]* Severity wording aligned with U7b MF-1: `RECON_TREND_MISMATCH` ships as `info` in U7b v1, so gate 1b protects an info finding now and the future major only via the promotion unit. The corrected probability framing stands: extractions CLUSTER in the first days after a period end (the one live run was 02:23+03:00 local), so the skew window is an operational pattern, not "hours out of ~90 days".

**Residuals (documented, accepted):**
- EC-2 timezone/boundary skew beyond the mitigations above: `anchorDate` persisted for audit; labels skew together with months (same local-date semantics, A:217), keeping facts self-consistent.
- Type comparison is case-insensitive (`'relative'`/`'Relative'` accepted by `-ne 'RELATIVE'`): benign leniency, but pin the intent — either `-cne` or a one-line test asserting case-insensitive acceptance is deliberate.
- `resolverVersion` string `'1'` passes the `-eq 1` recognition (PS int-RHS coercion): benign leniency on hand-edited docs.
- `Get-PeriodMeta` does not check `startYm <= endYm` or recompute `calendarAligned` from dates: copy-with-shape-guard is the ratified point on the drift-vs-corruption line (reviewer Q8); U7b tiling degrades corrupted spans to info, never major. U8-E13 pins extractor-side recomputability.
- EC-11 label-vs-months anchor divergence (capture-time vs `extractedAt`): minutes-wide, both values persisted, capture-time is what fed the queries (reviewer Q3 confirmed). Do not unify anchors at the cost of touching `Derive-Periods`.
- D5 placement (`report.dateRangeResolved` vs the kickoff manifest's "new meta fields" letter): report-block adjacency to the verbatim `dateRange` accepted (U1 `report.clientId` precedent); record the deviation in the units-index U8 row so manifest letter and practice stop diverging silently.
- Trend mode (`-Trend`) executes the new capture line and computes an unused resolution before its early return: harmless (pure, nothing written to the trend doc); placing the capture line below the trend branch avoids the dead work at zero cost — builder's choice.
- U8-A6's "default `$null` keeps every existing fixture byte-identical" holds only if `MkDoc` adds the `dateRangeResolved` key ONLY when the param is non-null; an unconditional key would serialize `"dateRangeResolved": null` (functionally harmless, claim-breaking).
- `meta.period` ships with zero consumers until U7b undeferral: accepted — the extraction is the expensive online artifact (facts are regenerable), R:51 ratifies the Analyze allocation, and the U8-A6 exact-key-set test pins the contract while unconsumed.
- Closer haystack (`'2026-04'` tokens in facts meta): accepted on the `'Q2 2026'` precedent, pinned by U8-A9; re-opens if the closer's extraction scopes ever widen to meta.
- D8 measure passthrough (`'year'`/`'week'` verbatim): verified no present R18 gate branches on measure; U7b builder re-confirms at undeferral (as the body already requires).
- D4 silence-plus-null and D9 no-compare-resolution: CONFIRMED correct by all lenses (A:656 major-promotion; non-literal compare tokens). Zero-findings design stands.
- First live `month/-1` or `year/-1` report: pin KPI vs resolved months before trusting a non-quarter `RECON_TREND_MISMATCH` major (moot for whichever measures the pre-build probe covers).
- The 2026-07-06 archived facts predate U1/U2/U6 keys; still valid evidence for the "no `meta.period` exists today" claim (independently confirmed by A:784-793).

---

**Status:** SHIPPED (built 2026-07-14 per the AMENDMENTS v1; reviewed 2026-07-12, verdict GO-WITH-CHANGES). Unattended domain shipped as `quarter/-1` only (fatigue must-fix): `month/-1` and `year/-1` resolve to the null triple behind the documented live-probe gate; count cast is `[double]`; `Get-PeriodMeta` guard is `^[0-9]{4}-(0[1-9]|1[0-2])$`. Extends `docs/specs/context-and-canon-spec.md`; satisfies the named U7b precondition in `docs/specs/cross-widget-reconciliation-spec.md` (R:5) without undeferring U7b. Same discipline: PS 5.1/.NET, pure-ASCII script source, functions-first + `-DefineOnly`, hardened scripts reused via `-DefineOnly` dot-source (never mutated), default single-report output path byte-for-byte unchanged except additive fields, every credential path fail-closed, the model does no arithmetic (every number is computed in PS and persisted as data).

*Citation keys:* `G:` = `skill/scripts/Get-SwydoReport.ps1`, `A:` = `skill/scripts/Analyze-SwydoReport.ps1`, `S:` = `SWYDO_REPORT_EXTRACTION_SPEC.md`, `R:` = `docs/specs/cross-widget-reconciliation-spec.md`, `C6:` = `docs/specs/canonical-total-spec.md`, `TA:` = `Test-Analyze.ps1`, `TE:` = `Test-Extractor.ps1`. Line numbers are as of `main` @ `cccd0c9`.

---

## Why this unit exists

U7b's check #6 (monthly-series-sum vs period KPI) is deferred behind one named precondition: *"`Get-SwydoReport.ps1` must resolve RELATIVE date ranges to concrete `YYYY-MM` at extraction time (plus D-period persisted [...]). Until then #6's only `major` (`RECON_TREND_MISMATCH`) is inert for the common relative-quarter case (extractor discards concrete dates at G:165)"* (R:5). The D-period contract itself (R:59-74) demands a machine-readable `facts.meta.period` because *"fabricating a quarter from `"last quarter"` + the extraction date is exactly the kind of arithmetic/derivation the model-does-no-arithmetic discipline forbids doing implicitly; the period must be resolved once, in PS, at extraction time, and persisted as data"* (R:74).

**Correction of the standing assumption ("the shipped U6 D-period emission"):** D-period was **not** shipped with U6. The U6 v2 critic override deferred it explicitly: *"D-period is DEFERRED, not built in U6. [...] When U7b is undeferred, D-period is built with it (owned by U6/extractor at that time) with its own tests"* (C6:5). Verified against the code and live data:

- `Analyze-SwydoReport.ps1` emits **no** `meta.period` anywhere (grep for `startYm|calendarAligned|meta\.period` returns nothing in the emission path). Today's facts meta carries only the label fields `currentPeriod/previousPeriod/periodLabel/periodConfidence` (A:789) plus `canonical.period=$periods.current`, a display label like `"Q2 2026"` (A:645).
- The archived live facts (`skill/archive/quincy-credit-union/2026-07-06-19-45-59/QCU_Q2_2026_causal_report.facts.json`) confirm: `currentPeriod:"Q2 2026"`, `periodConfidence:"derived"`, and no `period` object at all.

So U8 is not "populate the null fields of an existing block" - it **creates** the block, end to end: a pure extractor-side resolver, additive persistence in the extraction document, and the additive Analyze read-through that emits `facts.meta.period` to the exact D-period contract.

## What the wire actually carries (evidence, not assumption)

The report's date range is a **relative token, never concrete dates**, on the one live-verified report:

- Wire shape (S:143, section 6, captured live 2026-07-05 against the QCU "Q2 2026 PPC" report):
  `"dateRange": {"parent":null,"primary":{"count":-1,"measure":"quarter","type":"RELATIVE"},"comparison":null,"baseDate":null,"timeZone":null}`
- Compare shape (S:144): `"compareDateRange": {"parentComparePeriod":null,"comparePeriod":{"period":"previousMonth","type":"PERIOD"}}`
- Input-type contract (S:212-218, section 7.4): `DateRange = {parent, primary:{count,measure,type}, comparison, baseDate, timeZone}` - validated structurally, nulls fine. There is no `from`/`to` field anywhere in the observed shape; `baseDate`/`timeZone` were null.
- The extractor treats both as opaque scalars: captured at G:352 (`$script:dr=$s.dateRange; $script:cp=$s.compareDateRange`), fed verbatim into every widget query (G:138-141, per S:173), and written verbatim into the output document at G:488 (`dateRange=$s.dateRange; compareDateRange=$s.compareDateRange`). The only client-side date-range constructor, `New-RelDateRange` (G:164-166), builds *relative* tokens for trend probes - concrete dates are never computed anywhere in the extractor (the "G:165 discards concrete dates" of R:5 and C6:5).

**Consequence:** this unit is genuinely a *resolution* problem, not a mapping/threading problem. The server resolves the relative token internally and never echoes the concrete span; the extractor must compute it client-side, at the moment the token is captured, and persist both the computation's inputs (anchor) and outputs (months) as data. A hypothetical fixed/custom-range report presumably populates other fields of the `DateRange` shape - **UNVERIFIED, never observed** - and is handled by honest non-resolution (D4), not by guessing.

## Design decisions

**D1. The resolver's accepted domain is exactly the live-verified relative family: `type=='RELATIVE'` AND `count==-1` AND `measure in {month, quarter, year}`. Everything else resolves to an honest null.**
*Rationale: the only (measure,count) pair verified end-to-end on live data is `quarter/-1`: the report extracted 2026-07-05/06 rendered last-complete-quarter data (title "Q2 2026 PPC", S:5), and `Derive-Periods`' "count=-1 => last COMPLETE quarter before anchor" rule (A:221-222) produced labels matching it (facts `currentPeriod:"Q2 2026"`). `month/-1` and `year/-1` are admitted because "last month"/"last year" have no alternative reading in a reporting product (a "last month" report rendering month-to-date would be visibly broken to every Swydo user), and both are calendar-month-safe (no week-start or day-inclusion convention to guess). `count<=-2` is EXCLUDED even for month: the trend path's own code is evidence against blind extrapolation - G:405 defensively drops "the partial current month" from `-N month` responses, implying the server's window for multi-count ranges may INCLUDE the current partial period, i.e. `[cur-N+1 .. cur]` rather than `[cur-N .. cur-1]`. Unverifiable offline; a wrongly-resolved span is the one artifact this unit could produce that later feeds U7b's only major (see EC-2), so the domain stays pinned to what evidence supports. Extending the domain is a follow-up gated on a live probe (see Residuals).*

**D2. Resolve once, extractor-side, anchored at the structure-fetch moment; the anchor is persisted so the resolution is reproducible data.**
*Rationale: the dateRange every widget query uses is the one captured at G:352; `meta.extractedAt` is stamped later, at document assembly (G:480), after minutes of fetching. Anchoring at capture time is the closest client-side approximation of the server's view when it resolved the token. The anchor (`anchorDate`, local calendar date) is persisted inside the resolved object, making `Resolve-ReportPeriod($dateRange,$anchorDate)` a pure, deterministic, re-runnable function of persisted inputs - the resolution is DATA, not implicit arithmetic (R:74). Local-date semantics follow the shipped precedent (`Derive-Periods` uses `[DateTimeOffset]::Parse($extractedAt).Date`, A:217); the account-timezone residual is EC-3.*

**D3. Semantics: `count=-1` resolves to the single complete calendar `<measure>` immediately before the anchor's current one; the span is emitted as concrete dates AND months.**
*Rationale: mirrors the shipped, live-verified `Derive-Periods` rule (A:219-225). month: previous calendar month (start==end month). quarter: previous calendar quarter (3 months). year: previous calendar year (12 months). Emitting `startDate/endDate` alongside `startYm/endYm` keeps `calendarAligned` computable (D6) and keeps the shape forward-compatible with a future custom-range resolution without a schema change.*

**D4. Unresolved is an honest null, never a warning.** For any shape outside D1's domain, the persisted object carries `primary=$null` plus a human-readable `note` naming why. **No entry is added to `meta.warnings`.**
*Rationale: Analyze promotes every `meta.warnings` entry to a `major GAP_WARNINGS` finding (A:656) which the closer force-surfaces - a custom-range or weekly report would then wedge a major into every delivery for a non-defect. Null resolution is the designed degrade path: U7b's gate 1 hard-degrades to `info RECON_TREND_COVERAGE` on null/non-aligned periods and "is never major" (R:72, R:274). U8 itself emits ZERO findings of any severity.*

**D5. Persistence shape: additive `report.dateRangeResolved` in the extraction document; the verbatim `dateRange`/`compareDateRange` are untouched.**

```jsonc
"report": {
  ...,
  "dateRange":        { ...verbatim wire object, unchanged... },   // G:488, stays byte-identical
  "compareDateRange": { ...verbatim, unchanged... },
  "dateRangeResolved": {                       // NEW (additive)
    "resolverVersion": 1,
    "rule": "relative-last-complete",          // names the semantic applied
    "anchorDate": "2026-07-06",                // local date at structure fetch (G:352)
    "primary": {                               // $null when unresolved
      "measure": "quarter", "count": -1,       // verbatim echo of the wire token
      "startDate": "2026-04-01", "endDate": "2026-06-30",
      "startYm": "2026-04",     "endYm":  "2026-06",
      "calendarAligned": true                  // COMPUTED from startDate/endDate (D6)
    }
    // "note": "unresolved: ..."               // present ONLY when primary is null
  }
}
```

*Rationale: provenance (verbatim label + raw range) must sit alongside the resolved span, never be overwritten - `dateRange` stays exactly what S:216 requires for replay (verbatim feed-back into widget queries). Additive-field precedent: U1 added `meta.clientId`/`report.clientId` and U2 added `meta.providerInventory`/`meta.providerFilter` to the default extraction output with no `schemaVersion` bump (context-and-canon-spec 1.1/U2; none of those appear in S section 9.1's meta listing either). `schemaVersion` stays `2`, so Analyze's hard gate `-ne 2` (A:570) is untouched. `Scrub-Credential` (A:232-235) and `Assert-NoCredential` (A:237) are unaffected - calendar dates cannot match `KeyPattern`.*

**D6. `calendarAligned` is computed, never asserted:** `($startDate.Day -eq 1) -and ($endDate.AddDays(1).Day -eq 1)`, matching the D-period definition *"start==first-day-of-startYm AND end==last-day-of-endYm"* (R:67).
*Rationale: for D1's domain it is true by construction, but computing it keeps the field honest if the resolver ever grows non-aligned cases (custom ranges, weeks), and makes the U7b gate's authority a property of the data rather than of this spec's prose.*

**D7. Analyze read-through is a pure copy - zero date arithmetic in Analyze.** New pure helper `Get-PeriodMeta($dateRange,$resolved)` emits `facts.meta.period` with **exactly** the four contracted keys, populated only from the persisted extractor resolution. The contract byte-matches what U7b consumes (R:62-68):

```
meta.period = [ordered]@{
  measure        = 'quarter' | 'month' | 'custom'      # from dateRange.primary.measure
  startYm        = 'YYYY-MM'  or $null                  # first calendar month, if resolvable
  endYm          = 'YYYY-MM'  or $null                  # last calendar month, if resolvable
  calendarAligned= $true|$false                         # start==first-day-of-startYm AND end==last-day-of-endYm
}
```

with U7b's null semantics: *"For a relative/derived label with no concrete span, `startYm/endYm=$null`, `calendarAligned=$false`"* (R:70) and its hard-degrade rule: *"If D-period is not present at U7b build time, #6 hard-degrades to `info RECON_TREND_COVERAGE` ('no machine-readable period') and is never `major`"* (R:72); gate 1 at U7b requires *"`meta.period.calendarAligned==true`, `startYm`/`endYm` non-null, and `startYm..endYm` equals exactly the set of months summed"* (R:116, R:274). `startYm`/`endYm` are copied only when `resolverVersion==1` is recognized AND both match `^\d{4}-\d{2}$`; anything else yields the null triple. `meta.period` is **always present** in facts from U8 on (nulls mark "unresolvable", presence marks capability).
*Rationale: resolve once, persist, copy - the analyzer never re-derives months from a label or an anchor (R:74). The regex guard keeps garbage out of facts if a hand-edited extraction carries a malformed resolution.*

**D8. `meta.period.measure` is the verbatim lowercased wire measure when present, `'custom'` when absent. [DELTA vs the D-period text]**
*Rationale: R:63 writes the enum as `'quarter' | 'month' | 'custom'`; U8 additionally lets `'year'` and `'week'` pass through verbatim rather than lossily coercing them to `'custom'`. Defense: no U7b gate branches on `measure` - gate 1 keys exclusively on `calendarAligned` + `startYm/endYm` + month tiling, and the v2 hardening explicitly states "a `measure=quarter` label alone never authorizes the equality" (R:31). Verbatim is strictly more informative and cannot flip any gate; a `week` report simply carries `measure='week'` with the null triple (D1). Called out so the U7b builder re-confirms at undeferral time.*

**D9. `compareDateRange` is NOT resolved (YAGNI, evidence-backed).**
*Rationale: (a) the sole contracted consumer, U7b #6, compares the monthly-series sum against the PRIMARY-period KPI; the D-period shape has no compare fields (R:62-68). (b) The verified compare token is `{period:'previousMonth', type:'PERIOD'}` on a QUARTERLY report (S:144) whose rendered comparison is the previous quarter (facts label "Q2 2026 vs Q1 2026") - i.e. the token demonstrably does not literally name the effective compare span. Resolving it would require guessing unverified token semantics and would persist a plausible-but-wrong span as fact - strictly worse than absence. (c) The shipped precedent already ignores it: "period derivation from extractedAt + dateRange.primary (ignore compareDateRange.period)" (A:213). The verbatim `compareDateRange` remains persisted for replay; if a consumer ever materializes, compare resolution is a new decision against live evidence, not a symmetry reflex.*

**D10. No version bumps: `schemaVersion` stays 2, `factsVersion` stays 1, `canonicalVersion` stays 1.** The only new version marker is `dateRangeResolved.resolverVersion=1`, scoped to the object it describes.
*Rationale: additive-fields-without-bump is the shipped precedent (U1/U2 extraction fields; U6's additive `canonical` kept `factsVersion=1` per C6 D10). A `schemaVersion` bump would brick Analyze's A:570 gate against every new extraction for zero consumer benefit.*

**D11. U8 changes no existing byte: no findings added or removed, no label changes, `Derive-Periods` untouched.** `currentPeriod/previousPeriod/periodLabel/periodConfidence` (A:789), `canonical.period` (A:645), and the seasonality caveat (A:779-782) are byte-identical before/after. `facts.meta` gains exactly one key (`period`), appended after `periodConfidence`; the extraction `report` block gains exactly one key (`dateRangeResolved`), appended after `compareDateRange`.
*Rationale: U8 is a pure data unit - its whole value is a new machine-readable field. Keeping the human-facing surface untouched keeps the 276-green Analyze board meaningful and the shipped QCU reports comparable.*

**D12. All date formatting uses `[Globalization.CultureInfo]::InvariantCulture`; all math is date-only.**
*Rationale: PS 5.1 `ToString('yyyy-MM')` under a non-Gregorian default culture (e.g. ar-SA) renders non-Gregorian years; the existing `Get-CurrentMonthKey` (G:275) does not pin culture (hardened, not modified), but new code does. No time-of-day or DST math exists anywhere in the resolver (pure `DateTime` date arithmetic on day 1 anchors).*

**D13. Cross-derivation agreement is pinned by shared literal fixtures, not cross-dot-sourcing.** `Derive-Periods` (labels, in Analyze) and `Resolve-ReportPeriod` (months, in the extractor) embody the same "last complete measure" semantic in two scripts. Their agreement is pinned by asserting both against the same anchor literals: TE asserts `quarter/-1 @ 2026-07-06 -> 2026-04..2026-06` and `@ 2026-02-15 -> 2025-10..2025-12`; TA already asserts the same anchors -> `"Q2 2026"` / `"Q4 2025"` (TA:50-55), and U8-A10 asserts the e2e pair on one fixture.
*Rationale: dot-sourcing both scripts into one test session risks silent function-name collisions (both define overlapping helper vocabularies); literal pins on identical anchors give the same drift protection without the hazard - the U7a-T0 pattern, adapted.*

## Reference implementation (PS 5.1-safe, pure ASCII)

Extractor - new pure helper in the function region (adjacent to the month helpers at G:233-275, define-safe, `-DefineOnly` testable):

```powershell
# U8: resolve the report's RELATIVE date range to a concrete calendar span at extraction time.
# Accepted domain (live-verified family ONLY): type RELATIVE, count -1, measure month|quarter|year
# => the single complete calendar <measure> immediately BEFORE the anchor's current one (the
# Derive-Periods rule, verified live on the QCU quarter report). Anything else => primary=$null
# plus a note: an honest non-answer, never a guessed span (a wrong span could later feed U7b's
# only major). Pure; $anchor is a [datetime]; date-only arithmetic; InvariantCulture formatting.
function Resolve-ReportPeriod($dateRange,$anchor){
  $inv=[Globalization.CultureInfo]::InvariantCulture
  $out=[ordered]@{ resolverVersion=1; rule='relative-last-complete'
                   anchorDate=(([datetime]$anchor).Date).ToString('yyyy-MM-dd',$inv); primary=$null }
  $p=$null; if($dateRange){ $p=$dateRange.primary }
  if($null -eq $p){ $out.note='unresolved: no primary date range'; return $out }
  if([string]$p.type -ne 'RELATIVE'){ $out.note=('unresolved: type ''' + [string]$p.type + ''''); return $out }
  $n=$null; try{ $n=[int]$p.count }catch{}
  if($n -ne -1){ $out.note=('unresolved: count ''' + [string]$p.count + ''' (only -1 verified)'); return $out }
  $meas=([string]$p.measure).ToLowerInvariant()
  if(@('month','quarter','year') -notcontains $meas){ $out.note=('unresolved: measure ''' + [string]$p.measure + ''''); return $out }
  $a=([datetime]$anchor).Date
  $curStart=New-Object DateTime($a.Year,$a.Month,1); $span=1
  if($meas -eq 'quarter'){ $qm=((([int][math]::Floor(($a.Month-1)/3))*3)+1); $curStart=New-Object DateTime($a.Year,$qm,1); $span=3 }
  elseif($meas -eq 'year'){ $curStart=New-Object DateTime($a.Year,1,1); $span=12 }
  $startDate=$curStart.AddMonths(-1*$span)
  $endDate=$curStart.AddDays(-1)
  $out.primary=[ordered]@{
    measure=$meas; count=-1
    startDate=$startDate.ToString('yyyy-MM-dd',$inv); endDate=$endDate.ToString('yyyy-MM-dd',$inv)
    startYm=$startDate.ToString('yyyy-MM',$inv);      endYm=$endDate.ToString('yyyy-MM',$inv)
    calendarAligned=(($startDate.Day -eq 1) -and ($endDate.AddDays(1).Day -eq 1))
  }
  return $out
}
```

Extractor run body - two additive lines. At G:352, immediately after the verbatim capture:

```powershell
$script:drResolved = Resolve-ReportPeriod $s.dateRange (Get-Date)   # U8: anchor = structure-fetch moment
```

(plus one additive `Write-Host` echoing `startYm..endYm` when resolved - operator visibility, no credential content). At G:488, in the report block after `compareDateRange`: `dateRangeResolved=$script:drResolved`. The trend document (G:434-443) is untouched - its month cells are already concrete `YYYY-MM` read from server-returned dimension labels; it has no `report.dateRange` to resolve.

Analyze - new pure helper in the function region (near `Derive-Periods`, A:213):

```powershell
# U8/D-period read-through: facts.meta.period, consumed by U7b #6 (cross-widget-reconciliation-spec
# R18 gate 1). A pure COPY of the extractor-persisted resolution -- NO date arithmetic here (resolve
# once, at extraction time, persist as data; the analyzer/model never derives months from a label).
# Null triple (startYm/endYm=$null, calendarAligned=$false) for legacy/unresolved/unrecognized input;
# U7b hard-degrades that to info RECON_TREND_COVERAGE, never major.
function Get-PeriodMeta($dateRange,$resolved){
  $meas='custom'
  if($dateRange -and $dateRange.primary -and $dateRange.primary.measure){ $meas=([string]$dateRange.primary.measure).ToLowerInvariant() }
  $out=[ordered]@{ measure=$meas; startYm=$null; endYm=$null; calendarAligned=$false }
  $rp=$null; if($resolved -and ($resolved.resolverVersion -eq 1)){ $rp=$resolved.primary }
  if($rp -and ([string]$rp.startYm -match '^\d{4}-\d{2}$') -and ([string]$rp.endYm -match '^\d{4}-\d{2}$')){
    $out.startYm=[string]$rp.startYm; $out.endYm=[string]$rp.endYm
    $out.calendarAligned=($rp.calendarAligned -eq $true)
  }
  return $out
}
```

Analyze run body: `$periodMeta = Get-PeriodMeta $doc.report.dateRange $doc.report.dateRangeResolved` next to the existing `$periods = Derive-Periods ...` (A:574), and one additive key in the meta block after `periodConfidence` (A:789): `period=$periodMeta`. (Property access on a legacy doc lacking `dateRangeResolved` returns `$null` silently - no strict mode in these scripts - and the helper null-guards anyway.)

New locals (`$periodMeta`, `$drResolved`, `$rp`, `$meas`, `$curStart`, `$span`, `$startDate`, `$endDate`, `$inv`, `$qm`) collide with no dot-source param of any hardened script (checked against `$Facts/$From/$Into/$Execute` and the U7b `$my*` guard convention, R:333, R:342). Both helpers are pure and define-safe for the future U7b `-DefineOnly` dot-source of Analyze.

## Blast radius

Files changed (one commit/review boundary):

| File | Change |
|---|---|
| `skill/scripts/Get-SwydoReport.ps1` | +`Resolve-ReportPeriod` (pure, function region); +1 capture line after G:352; +`dateRangeResolved` key in the report block (G:488); +1 operator `Write-Host`. No existing line modified. |
| `skill/scripts/Analyze-SwydoReport.ps1` | +`Get-PeriodMeta` (pure, function region); +1 line near A:574; +`period=` key in the meta block (A:789). No existing line modified. |
| `Test-Extractor.ps1` | additive `== U8: Resolve-ReportPeriod ==` section (cases below). |
| `Test-Analyze.ps1` | additive `== U8/D-period ==` sections, unit + e2e (cases below). |
| `docs/specs/context-and-canon-spec.md` | units-index row `U8` (per the ID+ledger protocol, row lands before build; Status -> shipped at merge). Optionally annotate U7b's row "precondition met by U8" at ship - U7b's Status stays DEFERRED. |
| `docs/specs/cross-widget-reconciliation-spec.md` | AMENDMENTS binding (2), doc-only, deferred design prose (U7b Status stays DEFERRED): gate-1 parenthetical (R18 gate 1 and the R18 gates-summary gate 1) amended off the pre-U8 "Relative -> info" shorthand to key on the persisted `meta.period` fields - a RESOLVED relative period passes. Aligns with the authoritative MF-7(a) re-review block. |
| `docs/specs/extractor-period-resolution-spec.md` | this spec (Status line updated at review/ship). |

**FORBIDDEN to change (violations are spec defects):** `skill/scripts/Test-ReportNumbers.ps1` (closer), `skill/scripts/Analyze-SwydoTrend.ps1` (U7b's file - check #6 stays deferred), `skill/scripts/ConvertTo-SwydoTrendFacts.ps1`, `skill/scripts/Update-SwydoLedger.ps1`, `skill/scripts/Manage-SwydoArchive.ps1`, `skill/scripts/Sync-SwydoTrend.ps1`, `skill/SKILL.md`, `skill/report-template.md`, `Test-Closer.ps1`, `Test-Archive.ps1`, `Test-TrendFacts.ps1`, `Test-Ledger.ps1`, `Test-TrendAnalyze.ps1`, `Test-Sync.ps1`, and `SWYDO_REPORT_EXTRACTION_SPEC.md` (its section 9.1 meta listing already omits the U1/U2 additive fields; syncing that doc is a pre-existing, separate concern - see Residuals). No ledger-DATA schema change of any kind (`Update-SwydoLedger` cells/state untouched); the "unit ledger" edit above is the units index table only.

## Edge cases and false-positive analysis

U8 emits **zero findings**, so it cannot false-positive directly. Its FP surface is indirect: a *wrongly resolved* span persisted as truth could later pass all of U7b's gates and feed its only major (`RECON_TREND_MISMATCH`). The cases below are named accordingly.

- **EC-1 Quarter-boundary straddle.** A run whose structure fetch lands 2026-06-30 23:55 and whose widget fetches cross midnight into Q3: the server may resolve `-1 quarter` differently for pre- vs post-midnight widget queries (a pre-existing hazard, independent of U8 - the extraction itself would mix periods). U8 anchors once, at capture time (D2), matching the majority interpretation, and persists `anchorDate` so the straddle is auditable post-hoc. Residual; window is minutes wide.
- **EC-2 Timezone skew -> potential U7b false major (the sharpest risk).** The resolver uses the extracting machine's local date; the server resolves in some account/server timezone (`timeZone:null` on the wire, S:143). Within hours of a period boundary these can disagree by one whole period, and an off-by-one-period resolution passes every U7b gate (months final, aligned, tiled) while comparing the wrong months' sum against the KPI -> false `RECON_TREND_MISMATCH`. Bounding: the skew window is hours around a boundary out of a ~90-day quarter; `anchorDate` is persisted for audit; and the same local-date semantics already govern the shipped labels (A:217), so months and labels skew *together*, keeping facts self-consistent. Flagged for the U7b builder (reviewer section): #6 can cheaply add an observed-months cross-check at its build time.
- **EC-3 Legacy extraction replay.** Analyze over a pre-U8 extraction (no `dateRangeResolved`): `meta.period` present with the null triple; no throw, no warning, no finding; U7b degrades to info per R:72. Test U8-A7.
- **EC-4 Custom/fixed-range report (unobserved shape).** `type != 'RELATIVE'` -> `primary=$null` + note; **no `meta.warnings` entry** (a warning would become a force-surfaced `major GAP_WARNINGS` via A:656 on every custom-range report - the named FP this unit refuses to ship). Test U8-E11/U8-A7.
- **EC-5 This-period-to-date / positive or zero count.** `count>=0` -> null. A to-date span is not calendar-complete; resolving it as complete months would be wrong by construction.
- **EC-6 Week / day measures.** Null. Week-start convention (Mon/Sun) is unverifiable offline and a complete week almost never tiles calendar months; day-count windows (`-30 day`) have unverified current-day inclusion. Both would emit `calendarAligned=$false` data with no consumer - surface without value. Tests U8-E8/E9.
- **EC-7 Multi-count relative ranges (`count<=-2`).** Null, with the G:405 evidence (server returns the current *partial* month inside `-N month` windows) documented as the reason blind "N complete periods" extrapolation is unsafe. Test U8-E10.
- **EC-8 Calendar arithmetic corners.** Leap February (`month/-1 @ 2024-03-10` -> `2024-02-01..2024-02-29`), December/January crossing (`month/-1 @ 2026-01-05` -> `2025-12`), quarter cross-year (`quarter/-1 @ 2026-02-15` -> `2025-10..2025-12`), boundary day itself (`quarter/-1 @ 2026-07-01` -> Q2, because July 1 belongs to the *new* quarter and Q2 is the last complete one). Tests U8-E2/E3/E6/E7.
- **EC-9 JSON-typed count tolerance.** `ConvertFrom-Json` may deliver `count` as `[long]`/`[double]`; `'-1'` as a string round-trips too; `[int]` cast handles all three; a non-numeric count is caught (`try/catch`) and yields null, not a crash. Test U8-E12.
- **EC-10 Non-Gregorian default culture.** All new `ToString` calls pin InvariantCulture (D12); a Thai/Umm-al-Qura default culture cannot corrupt `startYm`. Test U8-E13 asserts the exact string forms.
- **EC-11 Label-vs-months anchor divergence.** `meta.period` derives from `anchorDate` (structure fetch); the labels derive from `extractedAt` (assembly). A run crossing a boundary *between those two moments* could emit `currentPeriod:"Q3 2026"` beside `period: 2026-04..2026-06`. Cosmetic (labels are display; months are machine data), astronomically rare, self-documenting via the persisted `anchorDate`. Residual, named.
- **EC-12 `@($null).Count` traps.** The resolver takes and returns scalars/ordered dicts only - no collection counting. Test fixtures still `@()`-wrap any collection they index, per house rule.

## Green-count contract

Board measured 2026-07-11 on `main` @ `cccd0c9`, all green: **Analyze 276, Closer 119, Extractor 94, Archive 94, TrendFacts 19, Ledger 50, TrendAnalyze 24, Sync 4** (total 690). U8 is **additive on Extractor 94 and Analyze 276** (new cases on top; no existing case modified or deleted). All six other suites re-run green with counts **byte-unchanged** - in particular TrendAnalyze stays 24 (U7b remains deferred; U8 only satisfies its precondition) and Closer stays 119 (no closer edit; pinned by U8-A9). Every suite exits 0.

## Test plan

Harness style: `Test-Extractor.ps1` dot-sources the extractor `-DefineOnly` and asserts pure helpers (TE:9, TE:13 `Assert`); `Test-Analyze.ps1` adds `-DefineOnly` unit cases plus e2e cases that write a minimal `schemaVersion:2` doc via `MkDoc` and run the real script via `RunAnalyze` (TA:280-297). Anchors are constructed with `New-Object DateTime(y,m,d)` (no culture-sensitive string parsing).

**Test-Extractor - `== U8: Resolve-ReportPeriod ==`**
- **U8-E1** `quarter/-1 @ 2026-07-06` -> `startDate 2026-04-01, endDate 2026-06-30, startYm 2026-04, endYm 2026-06, calendarAligned $true`; wrapper carries `resolverVersion 1`, `rule 'relative-last-complete'`, `anchorDate '2026-07-06'`, no `note`. (The live-verified pair; shares its anchor with TA:51-52's label pin - D13.)
- **U8-E2** `quarter/-1 @ 2026-02-15` -> `2025-10..2025-12` (cross-year; mirrors TA:54-55).
- **U8-E3** boundary day `quarter/-1 @ 2026-07-01` -> still `2026-04..2026-06`.
- **U8-E4** `month/-1 @ 2026-07-06` -> `2026-06-01..2026-06-30`, `startYm==endYm=='2026-06'`.
- **U8-E5** `year/-1 @ 2026-07-06` -> `2025-01-01..2025-12-31`, `2025-01..2025-12`.
- **U8-E6** leap `month/-1 @ 2024-03-10` -> `2024-02-01..2024-02-29`.
- **U8-E7** year-crossing `month/-1 @ 2026-01-05` -> `2025-12-01..2025-12-31`.
- **U8-E8 (FP)** `week/-1` -> `primary $null`, `note` matches `measure`; **no throw**.
- **U8-E9 (FP)** `day/-30` -> null (measure and count both out of domain).
- **U8-E10 (FP)** `month/-3`, `quarter/-2`, `month/0`, `month/+1` -> all null with a count note (multi-count exclusion, EC-7).
- **U8-E11 (FP)** `type 'PERIOD'` and `type $null` -> null with a type note; `dateRange $null` and missing `primary` -> null, no throw.
- **U8-E12** count typed `[long]-1`, `[double]-1.0`, string `'-1'` -> all resolve; `'abc'` -> null (no crash).
- **U8-E13** every resolved output: `calendarAligned` is `$true` AND recomputable from the emitted `startDate/endDate`; `startYm/endYm` match `^\d{4}-\d{2}$`; `anchorDate` matches `^\d{4}-\d{2}-\d{2}$` (invariant-culture forms).
- **U8-E14** wrapper key contract: exactly `resolverVersion, rule, anchorDate, primary` when resolved; plus `note` only when `primary` is null.

**Test-Analyze - `== U8/D-period: Get-PeriodMeta (-DefineOnly) ==`**
- **U8-A1** resolved input (quarter fixture) -> `{measure 'quarter'; startYm '2026-04'; endYm '2026-06'; calendarAligned $true}`.
- **U8-A2** `resolved $null` (legacy doc) -> measure from the wire token, null triple.
- **U8-A3 (FP)** malformed `startYm` (`'2026-4'`, `'garbage'`, `$null`) -> null triple (regex guard; no partial copy).
- **U8-A4 (FP)** `resolverVersion 99` -> null triple (unrecognized resolution is not trusted).
- **U8-A5** `dateRange $null` -> `measure 'custom'`, null triple.

**Test-Analyze - `== U8/D-period: e2e (real script over a v2 doc) ==`** (extend `MkDoc` with an optional `dateRangeResolved` param; default `$null` keeps every existing fixture byte-identical)
- **U8-A6** doc with `dateRangeResolved` (quarter, anchor 2026-07-06) -> `facts.meta.period` == `{measure:'quarter', startYm:'2026-04', endYm:'2026-06', calendarAligned:true}` and its key set is exactly those four keys.
- **U8-A7 (FP)** legacy doc (no `dateRangeResolved`) -> `meta.period` present with null triple; **no `GAP_WARNINGS`**, and total finding count identical to the same fixture pre-U8 (zero-findings parity).
- **U8-A8 (byte-stability)** on both fixtures: `currentPeriod/previousPeriod/periodLabel/periodConfidence` and each headline's `canonical.period` are byte-identical to their pre-U8 values (`'Q2 2026'`, `'derived'`, etc.).
- **U8-A9 (closer pin)** dot-source the REAL closer (the existing U6/U7a closer-integration pattern in Test-Analyze) over facts carrying a populated `meta.period` -> closer suite behavior unchanged, Closer stays 119, no new number becomes traceable outside its scope ('2026-04' strings do not loosen the anti-haystack posture any more than the shipped `'Q2 2026'` labels already do).
- **U8-A10 (cross-derivation pin, D13)** one fixture, anchor/extractedAt both 2026-07-06: `meta.period` says `2026-04..2026-06` AND `meta.currentPeriod` says `'Q2 2026'` - the two derivations agree on the same anchor.

Extraction-side run-body coverage note: the two run-body lines (capture + doc key) execute only online, like U1's `clientId` assembly lines; they are reviewed, not offline-tested. All logic lives in the pure, fully-tested helper - the assembly is a single assignment each.

## Residuals (explicit non-goals)

- **U7b undeferral** - not this unit. U8 makes the precondition true for post-U8 extractions; flipping U7b's ledger row and building #6 is its own commit/review boundary with its own spec amendments.
- **`count<=-2` resolution** - deferred behind a live probe that pins whether a `-N month` window includes the current partial month (G:405 suggests it does). Extension = widen D1's domain + new tests; `resolverVersion` bumps only if the meaning of already-emitted fields changes.
- **Week/day/custom/fixed ranges** - unresolved by design (EC-5/6, D4). If a fixed-range wire shape is ever observed, resolution of concrete wire dates is a trivial additive rule (`rule:'fixed-verbatim'`).
- **Compare-range resolution** - D9. No consumer; token semantics demonstrably untrustworthy.
- **Account-timezone anchor** - EC-2 residual; `timeZone` was null on the wire, so there is nothing to read. If Swydo ever populates it, the resolver should prefer it over the local date (future rule, additive).
- **Per-widget date-range overrides** - schema v2 cannot see them (same residual U7a documented for #5, R:110); `dateRangeResolved` describes the REPORT range only, which is exactly what the widget queries were fed (G:140-141).
- **`SWYDO_REPORT_EXTRACTION_SPEC.md` section 9.1 doc drift** - the meta/report listing already omits U1/U2's additive fields; adding `dateRangeResolved` there is part of the same pre-existing doc-sync follow-up, not U8.
- **Trend document (`*.trend.json`)** - untouched; its months are server-labeled, concrete, and already ledgered.

## For the reviewer (adversarial)

1. **Is the count==-1 domain restriction right, or too timid?** The evidence split: `quarter/-1` verified live; `month/-1`/`year/-1` admitted on the "no alternative reading" argument; `count<=-2` refused because G:405 implies the server's multi-count window includes the current partial month. Attack both directions: (a) is "last month cannot mean month-to-date" actually airtight for Swydo, or should month/-1 also wait for a live pin? (b) does refusing `-N` leave a real report population (rolling-12-months reports) permanently null for no good reason?
2. **The EC-2 false-major chain.** An off-by-one-period resolution (timezone/boundary skew) passes every U7b gate and would produce a false `RECON_TREND_MISMATCH` - the exact failure class R7 exists to prevent. Is "hours-wide window + persisted anchorDate + labels skew consistently" an acceptable residual, or must U7b's gate 1 be amended NOW (in its deferred design text) to also require the summed ledger months to overlap the extraction's observed time-series months? Decide before U7b is built, not after.
3. **Anchor at structure-fetch vs `extractedAt`.** D2 argues capture-time is closest to the server's view, at the cost of EC-11 (labels and months can theoretically disagree in one facts file). The alternative - reuse `extractedAt` for both - makes them always agree but resolves with an anchor that may postdate the queries by minutes. Which consistency matters more?
4. **`measure` passthrough delta (D8).** U8 emits `'year'`/`'week'` where the D-period text enumerated `'quarter'|'month'|'custom'`. Confirm no U7b gate (present or planned) branches on `measure`, or force the lossy `'custom'` coercion.
5. **Placement of the resolved object** (`report.dateRangeResolved` vs `meta`). The kickoff manifest's letter says "new `meta` fields"; U1's precedent put `clientId` in both blocks. Is report-block adjacency to the verbatim `dateRange` worth the deviation from the manifest's letter?
6. **Should unresolved emit ANY signal?** D4 refuses a `meta.warnings` entry because A:656 promotes warnings to force-surfaced majors. Confirm that silence-plus-null is right, and that no info-grade channel is warranted for "this report's period could not be machine-resolved" (U7b will say it per-comparison anyway via `RECON_TREND_COVERAGE`).
7. **Closer haystack.** `meta.period` adds `'2026-04'`-style strings to facts. U8-A9 pins Closer 119 green, but confirm the closer's number-extraction scopes (global/byPlatform/byFid) genuinely ignore facts-meta strings, so `2026`/`04` tokens cannot become accidentally-traceable numbers that loosen `untraceable-number` enforcement.
8. **`Get-PeriodMeta` trust boundary.** It trusts `calendarAligned` as persisted (after `resolverVersion` + `YYYY-MM` regex checks) rather than recomputing from `startDate/endDate`. Recomputing in Analyze would double-implement the definition (drift risk) but catch a corrupted flag. Is copy-with-shape-guard the right point on that line?
