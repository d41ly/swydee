# ANLZ-aDerivedMetric-1 — derived metrics computed by a tool from reported components

**Status:** CLOSED · rev-1 · 2026-11-12 · node a · Tier-2 · base c1dbe13e · streams analysis+orchestration · review 2026-11-12-review-aDerivedMetric-1 · ratified 2026-11-12 · landed 0c2360f

## 1. Goal

A report sometimes needs a figure the dashboard does not report directly, built from figures it
does: the trigger was the Rentex October 2026 report, where the client asked for cost per
conversion with and without the 'Local actions - Directions' conversion action. The model may not
do that arithmetic. A tool resolves the components, checks that they belong together, computes,
and writes the result into the facts so the closer can trace it; the report then presents it as
derived, never as a platform figure.

This spec is retroactive. The owner asked for the feature in conversation on 2026-11-12 and that
request was the approved scope; it was built before this file was written, in the primary tree,
alongside ANLZ-aModeledGap-1. Both deviations from `AGENTS.md` sections 1 and 3 are recorded in
section 5.

## 2. Scope (IN)

- `skill/scripts/Resolve-SwydoMetric.ps1`: request format (ratio, sum, difference over account
  metrics, with include / exclude filters on the rows of one breakdown), resolution, refusal
  reasons, and the `derivedMetrics` block spliced into the facts text.
- `skill/scripts/Test-ReportNumbers.ps1`: the derived-metric block (index, per-line checks,
  Recommendations guard, surfacing) and its hooks in `Invoke-Closer`.
- `skill/SKILL.md` Flow step 2a, the `derive:"..."` argument, the parameters table, the Notes
  entry; `skill/report-template.md` hard rule 7 and the "Derived metrics" block.
- `tests/Test-ResolveMetric.ps1` (a gate leg) and `tools/Verify-DerivedMetrics.ps1` (a field
  verifier run by hand against real facts; not a gate leg, because the archive is not tracked).

## 3. Non-goals (OUT)

- No change to `Analyze-SwydoReport.ps1` or `Get-SwydoReport.ps1`.
- No value taken from a widget total alone. The facts do not record widget filters, so a widget
  can only confirm or contradict a figure resolved from breakdown rows (section 4).
- No blending across platforms, no trend facts (Mode C), no modeled values (that is
  ANLZ-aModeledGap-1).

## 4. Design

- **Rows are the only source of a filtered value.** A request-named widget is a must-agree
  cross-check. A widget-only ("asserted") route was built, found by review to let the model attach
  an invented meaning to an unverifiable number, and removed. Reintroduce it only when the
  extractor records widget filters in the facts.
- **A count shown without decimals is exact.** `Format-Metric` prints a unit-null value as N0 only
  when it is an integer to 1e-9. The resolver relies on that, re-checks the convention at start-up,
  pins the facts versions it was verified for (3 and 4), and the unit suite carries a drift test.
  Treating integers as plus or minus one half let non-partitioning rows pass reconciliation.
- **Two bounds, one intersection.** A filtered subtotal is bounded by its own rows and by the
  account figure minus the other rows; an empty intersection is a refusal.
- **Request text is untrusted.** The model writes the request and the report. The formula is
  built from the facts' own names, notes never echo request text, and the closer does not index
  label, source or refusal reasons.
- **Closed wording.** The marker accepts three forms only, and "about" must sit directly before
  an approximate figure; both were loose regexes before review and accepted sentences meaning the
  opposite.

## 5. Production-readiness checklist

- security: the model writes the request, so request text is untrusted - it never reaches the
  formula, a note, or the closer's candidate pool; the credential guard runs on the spliced facts.
- perf / scale: one pass over the facts; the string-aware splice scanner is linear in file size.
- a11y: N/A — no UI.
- i18n: figures are parsed and formatted in the invariant culture; a cell in another number format
  is refused, not misread.
- error / empty / loading states: any error exits 2 with nothing written (temporary file, then
  swap); a refusal exits 1 with the reason recorded in the block.
- observability: every entry records its inputs, their source widget and rows, the cross-check
  status and the tool's own notes; refusals name the available metrics or rows.
- risks: the closer is stricter for any report whose facts carry a `derivedMetrics` block, and
  inert otherwise. Deviations and open items:
  - Built before the spec and in the primary tree (see section 1). Landed from
    `branch/derived-metrics`, stacked on `branch/forecast-estimates`.
  - ANLZ-aDerivedMetric-2: breakdown rows carry display strings only. Emitting raw cell values
    (`raw` / `rawPrevious`) from `Get-Breakdown` would make every filtered figure exact; the
    resolver already reads those keys.
  - ANLZ-aDerivedMetric-3: adopt the shared splicer `skill/scripts/_FactsBlock.ps1`
    (ANLZ-aModeledGap-4) in place of the resolver's own.
  - ANLZ-aDerivedMetric-4: the field verifier shares two readings with the tool (integer displays
    are exact; a row with no cell counts as zero) and does not model the widget cross-check.
  - A whole-number derived result under 100 is not a measure token, so the closer cannot police it
    (ANLZ-aModeledGap-3 covers the general case).

## 6. Acceptance criteria

- Every derived number in a report traces to a `derivedMetrics` display string on a line carrying
  `<!-- derived:<id> -->`, in the entry's own platform section, with a visible statement that the
  platform does not report it; the closer rejects it otherwise.
- The tool refuses, with a stated reason, when a component is missing, not summable, on another
  platform or currency, when rows do not reconcile with the account figure, or when two routes or
  two breakdowns disagree. A comparison is emitted only when both periods resolve from the same
  breakdown.
- Rentex October 2026: cost per conversion excluding 'Local actions - Directions' resolves to
  $42.27 (exact) beside the reported $6.71.
- `tools/Verify-DerivedMetrics.ps1` passes on every archived facts file and on a fresh extraction.

## 7. Gates

`bash tools/run-gates.sh`. A tenth suite, `Test-ResolveMetric`, joins the bar with 264 assertions;
the other nine keep their counts. Evidence beyond the gate bar:
- `tests/Test-ResolveMetric.ps1`: 264 assertions.
- `tools/Verify-DerivedMetrics.ps1 -ArchiveRoot skill/archive` on 2026-11-12, after the review
  fixes: 12 files, 2,514 requests, 60,433 checks, 0 failed, including 195 comparisons with the
  platform's own Cost / conversion, Avg. CPC and CTR.
- A fresh extraction of the Rentex report was verified before the review fixes (209 requests,
  5,406 checks, 0 failed); it was not re-pulled afterwards.

## 8. Open questions

none

## 9. Revision log

- rev-1 · 2026-11-12 · retroactive spec, written after the build and after folding review
  2026-11-12-review-aDerivedMetric-1 (widget-only route removed, integer cells exact, closed marker
  grammar, request text untrusted).

## 10. Reuse audit

none — codebase-map not adopted. The resolver dot-sources `Analyze-SwydoReport.ps1` for the
currency symbols, the credential guard, `Format-Metric` and `Get-AggregationClass` rather than
copying them, and the closer's derived rules reuse its per-line tracer. Not yet reused: the shared
facts splicer `_FactsBlock.ps1` (ANLZ-aDerivedMetric-3).