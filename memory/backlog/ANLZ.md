# analysis backlog

> Mutable. Each row leads with one status token (OPEN…WONTDO).

- OPEN - ANLZ-aStrictSchema-1 - the ANOM_BUDGET_CONSTRAINED impression-share fix (11c15c1, merged 01a5e21) shipped with no spec, id or review, and changes a finding statement plus adds evidence.impressionShare: retro design-pass, incl. whether a facts marker must move.
- CLOSED - ANLZ-aModeledGap-1 - modeled estimates for a metric declared incomplete: forecast tool, closer rules, docs, tests; merged dddfe20 -> [spec](../builds/aModeledGap/spec/2026-11-12-spec-aModeledGap-1.md)
- CLOSED - ANLZ-aModeledGap-2 - the closer traces headings and rejects comments spanning lines; merged dddfe20 -> [spec](../builds/aModeledGap/spec/2026-11-12-spec-aModeledGap-2.md)
- OPEN - ANLZ-aModeledGap-3 - a bare whole number under 100 is never traced ("45 leads"). A phrase rule was built and withdrawn: it blocked prose and missed most cases. Needs candidates bound to their metric -> [review](../builds/aModeledGap/reviews/2026-11-12-review-aModeledGap-2.md)
- CLOSED - ANLZ-aModeledGap-4 - one shared facts-member splicer, `skill/scripts/_FactsBlock.ps1`, used by the forecast tool; merged dddfe20. The derived-metrics tool adopts it under its own id.
- BLOCKED - ANLZ-aModeledGap-5 - a fair backtest of run-rate and the base weighting needs daily data: a Day-cut widget in the Swydo report or extractor work on the live API, plus a share link from the owner (review D3).
- CLOSED - ANLZ-aModeledGap-6 - a summable money metric can be estimated (coverage record `aggClass` sum); rates and per-unit prices stay refused; merged dddfe20.
- OPEN - ANLZ-aModeledGap-7 - `Split-Sections` treats any heading containing "recommend" as Recommendations, so that whole section goes untraced; classify on the heading's leading word instead (review aModeledGap-2 R10).
