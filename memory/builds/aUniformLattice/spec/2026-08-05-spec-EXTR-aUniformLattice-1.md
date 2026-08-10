# EXTR-aUniformLattice-1 — prove the compare window instead of inheriting it

**Status:** CLOSED · rev-3 · 2026-08-05 · node a · Tier-2 · base 39def66f · review wf_cf501fc0-4e8 · ratified 2026-08-05

## 1. Goal

Stop taking the previous-period window from whatever the dashboard's compare selector happens to be
set to. Compute it, pass it explicitly, record it, and refuse to publish a comparison we cannot prove.
Every previous-period number and every delta in a delivered report currently depends on a volatile
setting nobody records.

## 2. Scope (IN)

- S1. Resolve the report's PRIMARY window to explicit `{start, end}` dates: `STATIC` trivially, and
  `RELATIVE count:-1 measure:month` by arithmetic now that a live probe has verified it.
  `resolverVersion` 1 to 2, because the accepted domain changed.
- S2. Compute the PREVIOUS window: same length, ending the day before the primary starts.
- S3. Build the compare as `{start: <prevStart>, type: 'FROM'}` into a NEW run-body variable and pass
  it EXPLICITLY at the report fetch site. `$script:cp` is NOT mutated.
- S4. `meta.periodResolved{ current{start,end}, previous{start,end}, lengthDays, basis, anchorDate }`.
- S5. `meta.compareBasis`: `computed` when S2/S3 produced the window, `untrusted` otherwise. Plus
  `meta.savedComparePeriod`, the report's own spec recorded verbatim and unused.
- S6. FAIL CLOSED IN THE ANALYZER, not the extractor. When `compareBasis` is `untrusted`, the analyzer
  emits NO `previous`, NO `deltaPct` and NO `displayDelta` on any cell, and `hasComparison` is false
  everywhere. See D5 — the extractor physically cannot decline to send a compare.
- S7. `Analyze-SwydoReport.ps1` accepts `resolverVersion` 1 or 2, and surfaces real dates:
  `meta.currentPeriod` / `previousPeriod` carry `<isoStart>..<isoEnd>` when resolved.
  `factsVersion` 2 to 3.
- S8. Every date parse and format pins `InvariantCulture` explicitly.

## 3. Non-goals (OUT)

- **No second fetch per widget.** D2 shows an explicit `FROM` compare returns the correct window in
  the same payload, so Swydo keeps doing the row alignment and the row shape does not change.
- **No `schemaVersion` bump.** S4/S5 are additive keys and the emitted shape is unchanged. A bump
  would force widening three literal gates and REWRITING a shipped assertion, which the previous unit
  already paid for once; the semantic change is disclosed by `periodResolved` and `compareBasis`
  instead. Review confirmed the bump as pure cost.
- **No trend-path change, guaranteed by construction.** `$script:cp` keeps the saved spec verbatim, so
  `Probe-WidgetMonths`, trend discovery and the trend pull are untouched. Rev-1 claimed this while
  mutating the shared variable, which would have changed all three.
- No widening of the resolver beyond `STATIC` and `month/-1`.
- No attempt to reimplement Swydo's compare ENUM semantics.
- No closer change.

## 4. Design

### Data model

**D1 — the defect, traced.** The extractor forwards `report.compareDateRange` verbatim as
`referenceCompareDate`; Swydo computes `compareCells` from it. That spec is the dashboard's saved
compare selector, and it moved between two runs hours apart:

| When | `report.dateRange` | `report.compareDateRange` |
|---|---|---|
| extraction 13:35 | `STATIC 2026-07-01..2026-07-31` | `{start: 2026-06-24, type: FROM}` |
| hours later | `RELATIVE count:-1 month` | `{period: previousMonth, type: PERIOD}` |

Nothing recorded which window the compare column covered, so the drift was invisible and every delta
was computed against an unknown baseline.

**D2 — the fix, measured before it was specified.** Primary `STATIC 2026-07-01..2026-07-31`:

| compare spec | Conv. | Conversion rate | Cost (micros) | Clicks | provenance |
|---|---|---|---|---|---|
| `{start: 2026-06-24, type: FROM}` | 238.4 | 7.1% | $3,320.72 | 5,277 | DELIVERED REPORT, rounded — not a raw probe |
| `{period: previousMonth, type: PERIOD}` | 231.214955 | 0.044593048 | 3221941719 | 5171 | raw probe |
| **`{start: 2026-05-31, type: FROM}`** | **237.214955** | **0.044774435** | **3308679082** | **5277** | raw probe |
| dashboard "Previous Period" | 237.21 | 4.48% | $3,308.68 | — | owner, from the UI |

Row 3 reproduces the dashboard exactly. Row 1 is included for the incident record and is explicitly
NOT a raw measurement — it is what the delivered report printed, so its values are display-rounded and
its `7.1%` is a two-significant-figure rendering. Nothing in this spec's conclusions rests on row 1;
D1 establishes the defect independently.

Three negative results, each of which cost time and each of which is load-bearing:

- `{period: 'previousPeriod'}` returns HTTP 200 with EMPTY compare cells. The endpoint validates the
  SHAPE of `ComparePeriod`, not the enum value, so acceptance proves nothing and only returned values
  do.
- A `{start, end, type: STATIC}` compare is rejected: `invalid_compare_period`.
- **`referenceCompareDate` is `ComparePeriod!` — required and non-null.** Measured three ways, all
  HTTP 400: a nullable `$cp:ComparePeriod` declaration fails validation against the non-null argument;
  omitting the argument fails `"required, but it was not provided"`; a null value fails
  `"Expected value of non-null type ComparePeriod! not to be null"`. **There is no way to fetch
  without a compare window.** Rev-1's S6 assumed there was.

**D3 — the previous-window arithmetic.** For a primary `[s, e]`:

```
lengthDays = (e - s).Days + 1
prevEnd    = s.AddDays(-1)
prevStart  = prevEnd.AddDays(-(lengthDays - 1))
```

`2026-07-01..2026-07-31` gives length 31, `prevEnd = 2026-06-30`, `prevStart = 2026-05-31` — the
dashboard's Previous Period, and D2's winning row. Pure `[datetime]` arithmetic on `.Date` values,
`InvariantCulture` on every parse and format per S8, unit-testable offline.

**D3b — the adjacency invariant, and what `FROM` is NOT proven to mean.** The single measured case
cannot distinguish "a window of the same length beginning at this date" from "a window running to the
day before the primary starts": for `prevStart = 2026-05-31` against a July primary, both readings
give the same window. Every window D3 emits satisfies `prevEnd + 1 day == primaryStart`, so the two
readings COINCIDE on the entire domain this unit can produce. The spec therefore says `FROM` is
CONSISTENT WITH same-length-from-this-date rather than asserting it, and `New-ComparePeriodFrom`
REFUSES a start that does not satisfy the adjacency invariant, so a future caller cannot silently
leave the proven region.

**D4 — resolving the primary, and the U8 residual this closes.** `Resolve-ReportPeriod` today handles
only `RELATIVE quarter/-1`, returning `unresolved` for `STATIC` and for `month/-1`, the latter under
an explicit note that the semantic "needs a credentialed live probe". That probe has now run:
querying the saved `RELATIVE count:-1 measure:month` and an explicit `STATIC 2026-07-01..2026-07-31`
returned IDENTICAL values (Clicks current 2591, compare 5277). Swydo's `month/-1` is the last COMPLETE
month and our arithmetic matches it.

`STATIC` was never a resolution failure — the dates are given. Treating it as unresolved is why a
static report sailed through with `periodConfidence: unconfirmed`.

Because the accepted domain changes, `resolverVersion` goes 1 to 2. `Get-PeriodMeta` whitelists
`resolverVersion -eq 1` at `Analyze-SwydoReport.ps1:332`; leaving the marker at 1 while changing what
it means is precisely the silent-algorithm-change U6 D10 forbids. S7 widens that gate to `-in @(1,2)`
in the SAME unit, and the two shipped assertions that pin the value move with it.

**D5 — fail closed in the ANALYZER, because the extractor cannot.** Since `ComparePeriod!` is
required, "send nothing" is not available. So when the primary cannot be resolved:

1. The extractor sends the report's saved spec, exactly as today — it has no choice.
2. It records `meta.compareBasis = 'untrusted'` and `meta.savedComparePeriod`, and warns.
3. The ANALYZER, seeing `untrusted`, emits no `previous`, no `deltaPct`, no `displayDelta`, and sets
   `hasComparison` false on every cell.

The published output is then current-period only, which is honest. The gate moved from the fetch to
the artifact, which is where it can actually be enforced.

**D6 — a detected skew fails closed too.** When the primary is RELATIVE, the extractor probes one
widget with the saved relative range and with its own resolved static range. A mismatch means our
anchor disagrees with Swydo's (timezone, month boundary), so `compareBasis` becomes `untrusted` and
D5's path fires. Rev-1 only warned here, which was the one place the spec detected a wrong window and
shipped it anyway — directly contradicting its own fail-closed principle.

**D7 — the divergence disclosure.** `meta.savedComparePeriod` is recorded verbatim and a warning fires
when it is not equivalent to the computed window. On the QCU report that warning fires, making the
incident visible in the artifact. Extractor warnings become `GAP_WARNINGS` at severity `major`, which
the closer force-surfaces, so the divergence reaches the report.

### Inventory

| Site | Change |
|---|---|
| `Resolve-ReportPeriod` (`:923-951`) | handle `STATIC`; admit `month/-1`; `resolverVersion` 2 |
| new `Get-PreviousWindow($start,$end)` | D3 arithmetic, pure |
| new `New-ComparePeriodFrom($startDate,$primaryStart)` | builds `{start,type:'FROM'}`, enforces D3b adjacency |
| run body `$script:cp` (`:983`) | UNCHANGED — keeps the saved spec for trend and the field probe |
| run body, new `$reportCp` | the computed compare, passed explicitly at the report fetch site `:1116` |
| report `meta` block | `periodResolved`, `compareBasis`, `savedComparePeriod` |
| `Analyze-SwydoReport.ps1:332` | `resolverVersion -in @(1,2)` |
| `Analyze-SwydoReport.ps1` cell builders | suppress previous/delta when `compareBasis` is `untrusted` |
| `Analyze-SwydoReport.ps1` meta | real date strings, `factsVersion` 3 |
| `Test-Analyze.ps1:86-87`, `Test-Extractor.ps1:291` | the `resolverVersion` pins move to 2 |

### Migration

A schemaVersion-3 document without `compareBasis` reads as `computed` is ABSENT, which the analyzer
treats as today's behaviour: it keeps emitting deltas, because that is what those artifacts meant.
Only a document that explicitly says `untrusted` suppresses them. Archived facts are untouched.

### Rollout

One unit. It changes extraction VALUES (a different, correct compare window) and facts period strings,
so it is the fourth disclosed change and carries a measured flip set.

### Files touched (estimate)

`skill/scripts/Get-SwydoReport.ps1`, `skill/scripts/Analyze-SwydoReport.ps1`, `Test-Extractor.ps1`,
`Test-Analyze.ps1`, `SWYDO_REPORT_EXTRACTION_SPEC.md`, `.claude/SESSION-KICKOFF.md`.

### Alternatives rejected

- **Two fetches per widget, one per period.** The owner's proposal; it would work, but D2 shows it is
  unnecessary, and it would double the fetch budget and force us to re-implement the row alignment
  Swydo already does — matching rows by dimension tuple where a campaign present in one period and
  absent in the other has no defined behaviour.
- **Sending no compare spec at all** (rev-1's S6). Measured impossible: `ComparePeriod!` is required.
- **Bumping `schemaVersion` to 4.** Three literal gates and a shipped assertion would have to change
  for a shape that did not change.
- **Mutating `$script:cp`** (rev-1's S3). It is shared with three trend call sites and the field probe,
  all of which pass `$null` and inherit it, so the "no trend-path change" non-goal would have been
  false. The trend path reads a fetch rejection as proof that history does not exist, so a compare
  Swydo dislikes would have silently shrunk the measured monthly ceiling.
- **Keeping `resolverVersion` at 1.** A changed accepted domain under an unchanged marker.

## 5. Production-readiness checklist

- security — no new I/O beyond the existing widget fetch and one probe; no credential surface.
- perf / scale — one extra probe fetch when the primary is RELATIVE; otherwise unchanged.
- a11y — N/A — no UI.
- i18n — NOT N/A, contrary to rev-1. PS 5.1 date parsing and formatting are culture-sensitive, so S8
  pins `[datetime]::ParseExact(..., 'yyyy-MM-dd', InvariantCulture)` and
  `.ToString('yyyy-MM-dd', InvariantCulture)` on every boundary, matching the existing `$inv` idiom at
  `Resolve-ReportPeriod:924`.
- error / empty / loading states — D5 is the empty state and it is total: unresolved or skewed both
  land on `untrusted`, and the analyzer suppresses every comparative field.
- observability — `periodResolved` puts both windows and the anchor in the artifact; `compareBasis`
  states whether they can be trusted; the warning becomes a force-surfaced `major` finding.
- risks — the residual risk is `FROM`'s exact semantics outside the adjacency invariant, closed by
  D3b's refusal rather than by hope. Second is our `month/-1` arithmetic disagreeing with Swydo on an
  unprobed boundary, closed by D6's run-time equivalence check now that it fails closed.
- testing + left-shift gates — the date arithmetic is pure with exhaustive offline cases; D6 is the
  left-shift for the live half; AC13 pins that the trend path's compare spec is unchanged.
- migration / rollback — additive keys, no schema bump; revert is a revert.
- user docs — `SWYDO_REPORT_EXTRACTION_SPEC.md`.

## 6. Acceptance criteria

- AC1. `Get-PreviousWindow '2026-07-01' '2026-07-31'` returns `2026-05-31`..`2026-06-30`, length 31.
- AC2. Boundaries are exact: a 1-day primary (`2026-07-15..2026-07-15` -> `2026-07-14..2026-07-14`);
  a year boundary (`2026-01-01..2026-01-31` -> `2025-12-01..2025-12-31`); a leap February
  (`2028-02-01..2028-02-29` -> `2028-01-03..2028-01-31`, length 29); a non-calendar-aligned primary
  (`2026-07-15..2026-08-14` -> `2026-06-14..2026-07-14`).
- AC3. Every window `Get-PreviousWindow` emits satisfies `prevEnd + 1 day == primaryStart` (D3b).
- AC4. `New-ComparePeriodFrom` produces exactly
  `{parentComparePeriod:null, comparePeriod:{start:<isoDate>, type:'FROM'}}`, and THROWS when the
  start does not satisfy the adjacency invariant.
- AC5. `Resolve-ReportPeriod` resolves a `STATIC` range to its own dates with `rule='static'`, resolves
  `RELATIVE count:-1 measure:month` to the last complete month, keeps `quarter/-1` behaviour, and
  reports `resolverVersion` 2.
- AC6. Date handling is culture-proof: with `CurrentCulture` temporarily set to `de-DE`, AC1 and AC5
  return identical strings.
- AC7. `meta.periodResolved` carries both windows, `lengthDays` and `anchorDate`;
  `meta.compareBasis` is `computed`; `meta.savedComparePeriod` carries the report's spec verbatim.
- AC8. When the saved compare spec is not equivalent to the computed window, a warning naming both
  appears in `meta.warnings`.
- AC9. When the primary cannot be resolved, `compareBasis` is `untrusted`, a warning says so, and the
  ANALYZER emits no `previous`, no `deltaPct`, no `displayDelta`, and `hasComparison` false on every
  headline and matrix cell.
- AC10. When the RELATIVE equivalence probe mismatches, `compareBasis` is `untrusted` and AC9's
  suppression applies. A detected skew never ships a delta.
- AC11. `$script:cp` still equals the report's saved compare spec after the run-body assignment, and a
  source-text assertion proves the three trend fetch sites and the field probe still pass `$null`.
- AC12. `Analyze-SwydoReport.ps1` accepts `resolverVersion` 1 and 2 and still ignores 3.
- AC13. LIVE: re-extracting QCU yields previous-period Conv. `237.21`, Conversion rate `4.48%`, Cost
  `$3,308.68`, Cost / conv. `$13.95`, and the corrected Conversion rate delta is `+99.0%`, not the
  `+26.4%` that shipped.
- AC14. LIVE: `meta.currentPeriod` reads `2026-07-01..2026-07-31`, `periodConfidence` is `resolved`.
- AC15. `bash tools/run-gates.sh` green; `Test-Extractor` and `Test-Analyze` additive except the two
  named `resolverVersion` pins, which are MODIFIED; the other six suites unchanged.

## 7. Gates

`bash tools/run-gates.sh` — the whole standing bar, plus the live re-extraction of AC13 and AC14.

## 8. Open questions

none — F1 was resolved before the build. It asked whether the computed window should always be the
"previous period" or whether a switch should offer calendar-previous-month; the answer is
previous-period only, because it is the dashboard default, it is what D2 verified, and a second mode
doubles the surface with no measured demand. The live run reinforced it: the report's saved compare
had become `{type:'DISABLED'}`, so there was no configured alternative to honour. Recorded here rather
than as an in-place RESOLVED marker because hygiene check 12 requires a terminal spec's §8 to OPEN
with `none`.

## 9. Revision log

- rev-1 · 2026-08-05 · initial spec, after the live trace that reproduced the defect and verified the
  fix.
- rev-2 · 2026-08-05 · folded adversarial review wf_cf501fc0-4e8 (3 lenses, 6 batched skeptics, 9
  agents; 27 raw findings, 24 survived, 8 must-fix). The central correction: rev-1's fail-closed path
  was IMPOSSIBLE. `referenceCompareDate` is `ComparePeriod!`, measured three ways at HTTP 400, so the
  extractor can never decline to send a compare; the gate moved to the analyzer, which suppresses every
  comparative field when `compareBasis` is `untrusted`. Second: rev-1 mutated `$script:cp`, which is
  shared with three trend call sites and the field probe that all inherit it, so its own "no trend-path
  change" non-goal was false and a rejected compare would have silently shrunk the trend ceiling; the
  computed spec now goes in a new variable passed explicitly at one site. Third: the `schemaVersion`
  bump repeated a defect a prior review already caught — three literal gates and a shipped assertion —
  and is dropped, since the shape is unchanged. Fourth: `resolverVersion` is whitelisted at `-eq 1` by
  the analyzer, so changing the resolver's domain without bumping it and widening the gate would have
  been a silent algorithm change. Fifth: a detected anchor skew now fails closed instead of warning.
  Also: D2 row 1 is labelled as delivered-report values rather than presented as a probe; the `FROM`
  semantics claim is softened to "consistent with" with the adjacency invariant enforced in code; and
  i18n is no longer N/A because PS 5.1 date handling is culture-sensitive.
- rev-3 · 2026-08-05 · built and verified live. AC13/AC14 measured on the QCU report: previous-period
  Conv. raw 237.214955, Conversion rate 0.04477443469233673, Cost 3308679082 micros, Cost / conv.
  13948020.6 micros -- all four equal to the dashboard's own Previous Period. The corrected Conversion
  rate delta is +99.0%, against the +26.4% that shipped. `meta.currentPeriod` reads
  `2026-07-01..2026-07-31` and `periodConfidence` is `resolved`.
  Two things the live run taught that the spec did not anticipate. First, the saved compare spec had
  become `{type: 'DISABLED'}` -- the dashboard's comparison was switched OFF entirely, a shape D2 never
  saw, which makes the case for computing our own window rather than inheriting one even stronger.
  Second, D7's disclosure becomes a force-surfaced `major` finding and therefore reaches the CLIENT,
  so dumping the raw spec JSON into it was wrong; it now names both windows in plain language and
  leaves the raw shape in `meta.savedComparePeriod` for an operator.
  The build also hit two traps worth recording: the `ps-hygiene` gate caught case-only identifier
  collisions introduced by the new test block (`$w1` against the existing `$W`), and it cannot tell a
  dollar-token inside a quoted regex from an identifier, so source-scanning assertions must avoid the
  literal.

## 10. Reuse audit

None — codebase-map is not adopted; audit by reading source. The unit extends `Resolve-ReportPeriod`
at `Get-SwydoReport.ps1:923-951` rather than adding a second resolver, and reuses its
`resolverVersion`/`note`/`$inv` shape. `Fetch-Widget` already takes a per-call `$cp` argument, so the
computed spec needs no new plumbing — only an explicit value at the one report fetch site instead of
the `$null` that inherits `$script:cp`. Note the correction to rev-1's audit: the trend path does NOT
pass its own compare; `Probe-WidgetMonths` (`:867`), trend discovery (`:1019`) and the trend pull
(`:1049`) all pass `$null` and inherit, which is exactly why `$script:cp` must stay untouched. The
warnings array and `Get-ExtractionCompleteness` are the existing carriers for D7's disclosure.
