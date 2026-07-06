Good question to ask *before* trusting the report — including the one I just wrote. The honest adversarial read is that the current data measures the **top of the funnel and compares only to last quarter**, so almost every "we drove X" is an attribution claim the data can't actually defend. Here's where the blind spots are, ranked by how much they distort objectivity, each tied to a specific claim in the QCU report.

## Tier 1 — the two gaps that undermine every conclusion

**1. Downstream outcomes + dollar value (the missing funnel bottom).** The report stops at "leads" (432) and "conversions" (860.9) — proxies, not outcomes. It has no visibility into application → approved → **funded loan / opened account → balance / revenue**. This isn't a nice-to-have; it silently inverts conclusions:
- The report calls HELOC's `$9.83` and awareness video's `$9.00` cost-per-lead "efficient" and Auto Loans' `$21.06` "least efficient" — but a $21 lead that funds a $30k auto loan destroys a $9 lead that never applies. **Without funded-value, cheap-CPL is a vanity ranking.**
- The whole HELOC and Hanover **share-mismatch** anomalies I flagged literally cannot be resolved without it — I had to hedge them with "confirm downstream" precisely because the data ends at the click.
- **Add:** connect the CRM / loan-origination / core-banking system (Swydo ingests via a data-source connector, Google Sheets import, or manual KPIs): applications started/completed, approved, funded, loan/deposit **$ amount**, and member-vs-nonmember — keyed back to campaign/channel. Then every CPL/CPA becomes cost-per-funded-dollar.

**2. A counterfactual — brand/non-brand split, organic baseline, YoY, holdout.** There is *no control* in this data, which is exactly why the seasonality caveat exists. The causal voice you chose is the riskiest framing here:
- Google's cheapest, highest-volume campaign, "PMax Quincy General" (`$2.48` cost/conv, 7,394 clicks), is almost certainly harvesting **branded/existing-member demand** — people who'd convert anyway. Counting it as "driven" over-credits the campaign.
- `View-through conv. 102 (+1033.3%)` is a weak, easily-inflated signal presented next to click conversions.
- **Add:** brand vs non-brand segmentation on search; a GA4 organic/direct baseline widget; a **same-period-last-year** comparison range (Swydo supports it — this directly answers the seasonality caveat); and ideally a geo/PSA holdout for true incrementality lift. This is the single best defense against the over-attribution the causal voice invites.

## Tier 2 — comparability and honesty of the numbers

| Gap | Claim it undermines | Add to Swydo |
|---|---|---|
| **Conversion definitions + attribution model + dedup** | Meta "Leads 432" and Google "Conv. 860.9" are treated as comparable but are defined, modeled, and windowed differently; a member touching both channels is double-counted | Document per-platform conversion definition, attribution window/model (last-click vs data-driven, 7d-click/1d-view), and a de-duplicated GA4/cross-channel conversion view |
| **Estimated vs observed flags** | Google's fractional/modeled conversions (`34.3`, `3`) and view-through are shown identically to observed leads | Tag modeled/estimated metrics distinctly (the tool already caught one unconfirmed field: `202,867`) |
| **Denominators on every rate + small-n flags** | "Hanover 0.2% of leads," "Leads=1," "Unknown" rows, `+1033.3%` deltas on tiny bases read as trustworthy as big ones | Show absolute counts beside each rate; flag statistically thin cells |
| **Targets / benchmarks** | Everything is "vs Q1" only — there's no objective "good" | Add agreed KPI targets (target CPL/CPA/tROAS, lead-volume goal) and vertical benchmarks as goal lines |

## Tier 3 — diagnostic completeness

- **Budget-to-plan + bid targets.** I flagged Google as "budget-constrained (26.1% lost to budget)," but there's no planned budget or target CPA — was Meta's `+40.9%` spend intentional or overspend? Add planned vs actual budget and campaign target settings.
- **Landing-page / funnel metrics (GA4).** Google's conversion rate fell `-29.6%` while clicks doubled — I attributed that to traffic quality, but it could equally be a **landing-page** problem. Ad data alone can't tell. Add form-start→complete, bounce/engaged-session, page speed.
- **Tracking / signal health.** The `unknown`/`undetermined` age and publisher rows hint at consent-mode/iOS signal loss that's never quantified. Add conversion-tracking coverage, tag/pixel health, and invalid-traffic filtering.
- **Competitive / auction insights.** Impression-share vs competitors, overlap/outranking share, and category search-demand trend separate "we improved" from "the market got easier" — again, the real answer to seasonality.
- **Creative fatigue diagnostics.** I called June's Meta CPL spike (`$23.13`) "fatigue," but that's a hypothesis without creative age, first-served date, or frequency distribution.

## If you add only three things
1. **Funded-loan / account value from the CRM**, keyed to channel — turns every cost metric into cost-per-dollar.
2. **A same-period-last-year comparison + brand/non-brand split** — the minimum counterfactual that lets causal language ("drove/funded") be *defensible* rather than assumed.
3. **A conversion-definitions/attribution note + de-duplicated cross-channel conversions** — so Meta "leads" and Google "conversions" can honestly sit in the same report.

Notably, the deterministic closer already enforces that whatever numbers *are* present trace to the source — but it can't verify a number that was never collected. These additions are how you make the *inputs* objective, not just the arithmetic. Want me to encode any of these as new anomaly rules in the analyzer (e.g., "flag cost-per-lead rankings when no funded-value field is present," or "flag branded-PMax conversions as baseline-suspect")?