# analysis backlog

> Mutable. Each row leads with one status token (OPEN…WONTDO).

- OPEN - ANLZ-aStrictSchema-1 - the ANOM_BUDGET_CONSTRAINED impression-share fix (11c15c1, merged 01a5e21) shipped with no spec, id or review, and changes a finding statement plus adds evidence.impressionShare: retro design-pass, incl. whether a facts marker must move.
- INPROGRESS - ANLZ-aModeledGap-1 - modeled estimates for a metric declared incomplete; reviewed, on `branch/forecast-estimates`, awaiting the merge to `main` -> [spec](../builds/aModeledGap/spec/2026-11-12-spec-aModeledGap-1.md)
- OPEN - ANLZ-aModeledGap-2 - the closer never traces heading lines and checks comments per line while the client copy strips them across lines, so a fabricated MEASURED number can pass there. Predates aModeledGap (review C1, C2).
- OPEN - ANLZ-aModeledGap-3 - `Get-MeasureTokens` exempts bare whole numbers under 100, so a small rounded figure is never traced; only a rounded ESTIMATE is caught (review C4).
- OPEN - ANLZ-aModeledGap-4 - the top-level facts-member splicer exists here and again in the unmerged derived-metrics tool; extract one shared helper when the second lands (review D9).
- OPEN - ANLZ-aModeledGap-5 - the hold-out backtest cannot test run-rate or the base weighting without daily data; the weighting rests on one month of evidence (review D3).
- OPEN - ANLZ-aModeledGap-6 - estimating a summable money metric is refused together with rates; allow it once a gate can tell summable money from a ratio (review M3).
