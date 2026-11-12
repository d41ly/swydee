# analysis backlog

> Mutable. Each row leads with one status token (OPEN…WONTDO).

- OPEN - ANLZ-aStrictSchema-1 - the ANOM_BUDGET_CONSTRAINED impression-share fix (11c15c1, merged 01a5e21) shipped with no spec, id or review, and changes a finding statement plus adds evidence.impressionShare: retro design-pass, incl. whether a facts marker must move.
- INPROGRESS - ANLZ-aModeledGap-1 - modeled estimates for a metric declared incomplete; reviewed, on `branch/forecast-estimates`, awaiting the merge to `main` -> [spec](../builds/aModeledGap/spec/2026-11-12-spec-aModeledGap-1.md)
- INPROGRESS - ANLZ-aModeledGap-2 - closer traces headings and rejects comments spanning lines; committed, awaiting merge. Left: a heading that merely contains "recommend" still untraces its section -> [spec](../builds/aModeledGap/spec/2026-11-12-spec-aModeledGap-2.md)
- OPEN - ANLZ-aModeledGap-3 - a bare whole number under 100 is never traced ("45 leads"). A phrase rule was built and withdrawn: it blocked prose and missed most cases. Needs candidates bound to their metric -> [review](../builds/aModeledGap/reviews/2026-11-12-review-aModeledGap-2.md)
- INPROGRESS - ANLZ-aModeledGap-4 - one shared facts-member splicer, `skill/scripts/_FactsBlock.ps1`, used by the forecast tool; committed, awaiting merge. Left: the unmerged derived-metrics tool adopts it when it lands.
- BLOCKED - ANLZ-aModeledGap-5 - a fair backtest of run-rate and the base weighting needs daily data: a Day-cut widget in the Swydo report or extractor work on the live API, plus a share link from the owner (review D3).
- INPROGRESS - ANLZ-aModeledGap-6 - a summable money metric can be estimated (coverage record `aggClass` sum); rates and per-unit prices stay refused; committed, awaiting merge.
- INPROGRESS - ANLZ-aDerivedMetric-1 - derived metrics computed by `Resolve-SwydoMetric.ps1` and policed by the closer; reviewed, on `branch/derived-metrics`, awaiting the merge to `main` -> [spec](../builds/aDerivedMetric/spec/2026-11-12-spec-aDerivedMetric-1.md)
- OPEN - ANLZ-aDerivedMetric-2 - breakdown rows carry display strings only; emitting raw cell values (`raw` / `rawPrevious`) from `Get-Breakdown` would make every filtered derived figure exact. The resolver already reads those keys.
- OPEN - ANLZ-aDerivedMetric-3 - the resolver still has its own facts splicer; adopt `skill/scripts/_FactsBlock.ps1` (ANLZ-aModeledGap-4).
- OPEN - ANLZ-aDerivedMetric-4 - `tools/Verify-DerivedMetrics.ps1` shares two readings with the tool (integer displays are exact; a row with no cell counts as zero) and does not model the widget cross-check -> [review](../builds/aDerivedMetric/reviews/2026-11-12-review-aDerivedMetric-1.md)
