# ORCH-aUniformLattice-3 — SKILL.md states the comparison contract

**Status:** CLOSED · rev-2 · 2026-08-05 · node a · Tier-1 · base 6213a239 · depends on ANLZ-aUniformLattice-10

## Goal

An agent driving the skill knows where the previous-period column comes from, what guarantees it
carries, and what the report must say when those guarantees are absent — from `SKILL.md` alone.

## The gap, measured

`SKILL.md` mentions `compareBasis`, `periodResolved`, the compare window, and the suppression gate
**zero times**. Its only statement is line 11: the report has "previous-period comparison".

The machinery it does not mention is load-bearing. `Get-SwydoReport.ps1` COMPUTES the preceding
window and passes it as `{start, type:'FROM'}`; `cells` and `compareCells` come from ONE payload per
widget. `meta.compareBasis` and `meta.periodResolved` record the outcome. `compareBasis='untrusted'`
suppresses the comparative fields on every CELL at three sites (`Analyze-SwydoReport.ps1:197`,
`:974`, `:1106`).

This replaced a real defect: the baseline used to come from an unrecorded dashboard compare selector,
so deltas were computed against an unknown reference (EXTR-aUniformLattice-1 D1).

**Writing this spec found a hole in the invariant it wanted to document.** A fourth read of the
compare column at `:1369` was NOT gated, and the reconciliation loop at `:1373` iterates
`'cur','prev'` — so under `untrusted` a discrepancy finding published previous-period numbers the
gate exists to suppress. That is `ANLZ-aUniformLattice-10`, and this spec DEPENDS on it: if
ANLZ-10 does not land first, the central claim here is false and must be weakened to name the gap.

## Scope

IN: a `### Comparison basis` subsection under `## Notes` in `skill/SKILL.md` stating (a) the window
is computed and passed explicitly, one payload per widget, never inherited from the dashboard;
(b) `meta.compareBasis` and `meta.periodResolved` are the record; (c) what each of the THREE values a
reader can encounter means; (d) that `untrusted` suppresses every comparison and the report must then
carry no comparative language; (e) why a `GAP_WARNINGS` disclosure appears when the dashboard's own
compare setting diverges from the report's. A pointer from Flow step 2 and from the closer step.

OUT: no script changes here — the code fix is ANLZ-aUniformLattice-10's, deliberately separated
because it is analyzer behaviour with its own regression test, not documentation. Not documenting
`referenceDateRange` internals or the GraphQL shape; `SWYDO_REPORT_EXTRACTION_SPEC.md` owns those.

## Design notes

**Three values, not two.** `Get-SwydoReport.ps1` only ever writes `computed` or `untrusted`, but the
facts meta is written as `compareBasis=$(if($doc.meta.compareBasis){...}else{'unknown'})`
(`Analyze-SwydoReport.ps1:1434`), so `unknown` is a value a reader WILL encounter — it marks facts
analyzed from a pre-contract extraction. The gate at `:1025` is an exact `-eq 'untrusted'`, so
`unknown` does NOT suppress and behaves like `computed`. The doc must say this plainly; an earlier
revision claimed two values and would have documented an invariant that does not hold.

**"No second pull" needs one qualifier.** Per widget, current and previous come from one payload.
A RELATIVE primary window additionally costs one extra fetch of a single PROBE widget
(`Get-SwydoReport.ps1:1198-1215`), which fails the run closed to `untrusted` when the resolved window
and Swydo's relative range disagree. The unqualified claim is wrong on that path.

**What this documents, and what it does not.** The originally suggested approach — pulling the two
timeframes separately by moving the dashboard date — was NOT built. It was used to VERIFY the shipped
design: querying `2026-05-31..2026-06-30` as its own primary window reproduced all ten checked
headline previous values, three after the documented unit normalisation. The doc states the shipped
mechanism and cites that verification so nobody mistakes the check for the design.

## Acceptance criteria

1. `SKILL.md` names `meta.periodResolved` and `meta.compareBasis` with all THREE values —
   `computed`, `untrusted`, `unknown` — stating that only the literal `untrusted` suppresses and
   that `unknown` therefore compares normally, with its provenance (a pre-contract extraction).
2. It states that `untrusted` suppresses all comparisons and forbids comparative language.
3. It states the one-payload explicit-compare mechanism, that the dashboard selector is not
   inherited, and the RELATIVE-path probe-fetch qualifier.
4. Flow step 2 and the closer step each carry a pointer.
5. Every claim is verified against the code at write time. Specifically: the three cell-layer
   suppression sites are re-grepped and confirmed present, AND `:1369` is confirmed GATED by
   ANLZ-aUniformLattice-10 before the "every comparison" wording is used. If ANLZ-10 has not landed,
   the wording narrows to "every comparative field on every cell" and names the discrepancy-layer gap.
6. The claim about the corrected numbers cites something verifiable rather than an unsourced count:
   the corrected Conversion-rate delta is +99.0%, and four previous-period values (Conv. 237.21,
   Conversion rate 4.48%, Cost $3,308.68, Cost/conv. $13.95) equal the dashboard's own Previous
   Period column.

## Gates

Full bar. As with ORCH-aUniformLattice-2 no suite asserts `SKILL.md` prose; AC5 is the real check.
Both ORCH units edit `SKILL.md`, so whichever lands second rebases on the first — they are sequenced
deliberately, not concurrent.

## Risk

Doc-only, but a WRONG statement here is worse than silence: it would assert an invariant a future
session relies on. That is exactly what happened to rev-1, which asserted "suppresses EVERY
comparative field" without checking the fourth read. Hence AC5's explicit dependency check.
