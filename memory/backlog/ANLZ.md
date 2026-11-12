# analysis backlog

> Mutable. Each row leads with one status token (OPEN…WONTDO).

- OPEN - ANLZ-aStrictSchema-1 - the ANOM_BUDGET_CONSTRAINED impression-share fix (11c15c1, merged 01a5e21) shipped with no spec, id or review, and changes a finding statement plus adds evidence.impressionShare: retro design-pass, incl. whether a facts marker must move.
- INPROGRESS - ANLZ-aModeledGap-1 - modeled estimates for a metric declared incomplete; reviewed, on `branch/forecast-estimates`, awaiting the merge to `main` -> [spec](../builds/aModeledGap/spec/2026-11-12-spec-aModeledGap-1.md)
- INPROGRESS - ANLZ-aModeledGap-2 - closer traces headings and rejects comments spanning lines; committed, awaiting merge. Left: a heading that merely contains "recommend" still untraces its section -> [spec](../builds/aModeledGap/spec/2026-11-12-spec-aModeledGap-2.md)
- OPEN - ANLZ-aModeledGap-3 - a bare whole number under 100 is never traced ("45 leads"). A phrase rule was built and withdrawn: it blocked prose and missed most cases. Needs candidates bound to their metric -> [review](../builds/aModeledGap/reviews/2026-11-12-review-aModeledGap-2.md)
- INPROGRESS - ANLZ-aModeledGap-4 - one shared facts-member splicer, `skill/scripts/_FactsBlock.ps1`, used by the forecast tool; committed, awaiting merge. Left: the unmerged derived-metrics tool adopts it when it lands.
- BLOCKED - ANLZ-aModeledGap-5 - a fair backtest of run-rate and the base weighting needs daily data: a Day-cut widget in the Swydo report or extractor work on the live API, plus a share link from the owner (review D3).
- INPROGRESS - ANLZ-aModeledGap-6 - a summable money metric can be estimated (coverage record `aggClass` sum); rates and per-unit prices stay refused; committed, awaiting merge.
