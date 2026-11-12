# analysis backlog

> Mutable. Each row leads with one status token (OPEN…WONTDO).

- OPEN - ANLZ-aStrictSchema-1 - the ANOM_BUDGET_CONSTRAINED impression-share fix (11c15c1, merged 01a5e21) shipped with no spec, id or review, and changes a finding statement plus adds evidence.impressionShare: retro design-pass, incl. whether a facts marker must move.
- CLOSED - ANLZ-aModeledGap-1 - modeled estimates for a metric declared incomplete: forecast tool, closer rules, docs, tests; merged dddfe20 -> [spec](../builds/aModeledGap/spec/2026-11-12-spec-aModeledGap-1.md)
- CLOSED - ANLZ-aModeledGap-2 - the closer traces headings and rejects comments spanning lines; merged dddfe20 -> [spec](../builds/aModeledGap/spec/2026-11-12-spec-aModeledGap-2.md)
- OPEN - ANLZ-aModeledGap-3 - a bare whole number under 100 is never traced ("45 leads"). A phrase rule was built and withdrawn: it blocked prose and missed most cases. Needs candidates bound to their metric -> [review](../builds/aModeledGap/reviews/2026-11-12-review-aModeledGap-2.md)
- CLOSED - ANLZ-aModeledGap-4 - one shared facts-member splicer, `skill/scripts/_FactsBlock.ps1`, used by the forecast tool; merged dddfe20. The derived-metrics tool adopts it under its own id.
- BLOCKED - ANLZ-aModeledGap-5 - a fair backtest of run-rate and the base weighting needs daily data: a Day-cut widget in the Swydo report or extractor work on the live API, plus a share link from the owner (review D3).
- CLOSED - ANLZ-aModeledGap-6 - a summable money metric can be estimated (coverage record `aggClass` sum); rates and per-unit prices stay refused; merged dddfe20.
- CLOSED - ANLZ-aModeledGap-7 - a heading merely containing "recommend" untraced its section; one Recommendations definition in `Split-Sections` fixes it, under ANLZ-aModeledGap-8; merged 145eb44.
- CLOSED - ANLZ-aModeledGap-8 - fold-in of the follow-up build's review: Recommendations and title rules, name masking in headings, money and splicer hardening; merged 145eb44 -> [spec](../builds/aModeledGap/spec/2026-11-12-spec-aModeledGap-3.md)
- OPEN - ANLZ-aModeledGap-9 - digit labels ("Promo 2500", "401(k)", "365-day") are read as numbers in body and heading text; needs one label-masking rule for both, designed with ANLZ-aModeledGap-3.
- OPEN - ANLZ-aModeledGap-10 - a line starting with `#` inside a fenced code block is treated as a heading by `Split-Sections`; ignore or refuse fences.
- OPEN - ANLZ-aModeledGap-11 - the closer cannot read code-prefixed money ("SEK 1,025.00"); the forecast tool refuses such targets until it can, and a cost-per-conversion estimate there is unpublishable.
- OPEN - ANLZ-aModeledGap-12 - negative money ("$-50.00") is not tokenised as currency by the closer; the forecast tool refuses negative money targets until it is.
- OPEN - ANLZ-aModeledGap-13 - no gate checks that the violation names quoted in `skill/SKILL.md` exist as `type=` values in the scripts; a stale name passed a green bar once.
- CLOSED - ANLZ-aDerivedMetric-1 - derived metrics computed by `Resolve-SwydoMetric.ps1` and policed by the closer; reviewed and merged to `main` (0c2360f) -> [spec](../builds/aDerivedMetric/spec/2026-11-12-spec-aDerivedMetric-1.md)
- OPEN - ANLZ-aDerivedMetric-2 - breakdown rows carry display strings only; emitting raw cell values (`raw` / `rawPrevious`) from `Get-Breakdown` would make every filtered derived figure exact. The resolver already reads those keys.
- OPEN - ANLZ-aDerivedMetric-3 - the resolver still has its own facts splicer; adopt `skill/scripts/_FactsBlock.ps1` (ANLZ-aModeledGap-4).
- OPEN - ANLZ-aDerivedMetric-4 - `tools/Verify-DerivedMetrics.ps1` shares two readings with the tool (integer displays are exact; a row with no cell counts as zero) and does not model the widget cross-check -> [review](../builds/aDerivedMetric/reviews/2026-11-12-review-aDerivedMetric-1.md)
