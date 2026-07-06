# /swydee report template

Fill this from the facts JSON. **Every number must be copied verbatim from a facts display string** (`headline[].displayCurrent/displayPrevious/displayDelta`, `breakdowns[].rows[].values[].display/displayPrevious/delta`, `timeSeries[].buckets[].derived.*` and `pacing.*.display`, or a `findings[].evidence.*` string). No arithmetic, no re-rounding, no summing.

## Voice
**Persona (constant):** a senior practitioner writing to a client you have a good relationship with — warm, direct, honest about bad news. Role is category-derived from the dominant `meta.providers[].category`: `ads` → senior media buyer; `seo` → senior SEO strategist; `email-crm` → senior lifecycle/email marketer; mixed / `other` → senior performance marketer.

**Attribution profile — selected by the `voice:<type>` argument (default `causal`).** A profile changes ONLY tone and how confidently results are attributed; it NEVER changes the numbers, the structure, or the mandatory caveats/anchors below.
- **causal** (default): confident, takes credit — "drove", "funded", "generated", "delivered", "because". Attribute the movements to the work.
- **correlational**: cautious about causation — "alongside", "while", "as", "coincided with"; state what moved without claiming the campaign caused it.
- **executive**: top-line first, terse, decision-oriented; short paragraphs / tight bullets; lead each platform with the single number that matters. Attribution as in causal.
- **analytical**: precise and methodology-aware; foreground confidence, what the data does and doesn't support, and every caveat; neutral attribution.
- **consultative**: teaching tone; explain the *why* and the levers behind each move and orient every point toward a next step; moderate attribution.

If `voice:<type>` names an unknown profile, fall back to `causal` and say so in one line. Regardless of profile: do not attach evaluative words (good/bad/strong/weak) to a metric whose `direction` is `neutral`; and remember confident attribution frames *why* numbers moved — it never licenses changing a number or dropping a caveat (the closer verifies the figures, not the attribution).

## Hard rules
1. Numbers verbatim from facts only. State comparisons as `<displayCurrent> (<displayDelta>)` or "from `<displayPrevious>` to `<displayCurrent>`" — **both ends must be facts display strings**. If a metric's fact has `hasComparison:false`, do NOT use any comparative word/number for it.
2. **No blended/portfolio numbers** (there is no portfolio total in the facts) — report each platform separately. **No hand-summed segment figures** (cite the single-bucket concentration the facts give, e.g. "65+ = 53% of clicks", not a summed "55+ = 73%").
3. Reproduce **every** `meta.comparisonCaveats[]` at least once — write its `.text` and put its anchor `<!-- caveat:<id> -->` (e.g. `<!-- caveat:seasonality -->`) on that line so the verifier can confirm it. For every surfaced finding with `requiresDownstreamData:true`, its point/recommendation carries a "confirm downstream / lead-quality before acting" clause.
4. Surface every `dataGaps`/`discrepancies` finding (sev ≥ major) and every `GAP_UNIT_UNCONFIRMED`.
5. **Anchors** (machine-read; keep exactly): each platform gets its own `##` section header with `<!-- platform:<providerId> -->` immediately under it — **exactly one** platform anchor per section (two in one section is flagged, and an anchor whose id isn't in the facts is flagged). Put `<!-- finding:<fid> -->` on the **same line** as that finding's numbers (a finding's figures only trace on the line carrying its fid — don't split the comment onto its own line), and `<!-- caveat:<id> -->` on the caveat's line. These let the verifier scope numbers and confirm surfacing; the prose around them is free to paraphrase.

## Structure

*(intro: 1–2 warm sentences — the quarter in one breath.)*

For each platform in `meta.providers`:

```
## <client-facing platform name, e.g. Google Ads / Meta>
<!-- platform:<providerId> -->

| Metric | <meta.currentPeriod> | <meta.previousPeriod> | Δ |
|---|---|---|---|
| <headline metric> | <displayCurrent> | <displayPrevious> | <displayDelta> |
...   (previous/Δ columns only if hasComparison)

One-line takeaway.

<optional: a key breakdown table from breakdowns[] — top rows + the "top N of M" note;
 intra-period pacing/CPL ONLY from timeSeries (pacing.series, derived.CPL).>
```

Then:

```
## Analytical insights
**What's working** — wins, each citing the finding's numbers.  <!-- finding:WIN#n -->
**Needs attention** — losses.  <!-- finding:LOSS#n -->
**Anomalies worth knowing** — the anomalies (concentration, share-mismatch, segment-divergence,
  new/paused, budget-constrained, front-loading from timeSeries).  <!-- finding:ANOM_*#n -->
(Every major data-gap / discrepancy appears here too.)

## Recommendations
Concrete next steps from the losses/anomalies. Any recommendation resting on a requiresDownstreamData
finding says to confirm downstream/lead-quality first. State the seasonality caveat once.
```

## Reminders
- Prefer quoting a finding's `statement` as the basis for a win/loss/anomaly point, then paraphrase around it — this keeps the number anchored and the role/period correct.
- If `meta.periodConfidence` is `unconfirmed`, add "period labels approximate" once.
- Keep the client copy free of internal ids, share links, and the facts filename.
