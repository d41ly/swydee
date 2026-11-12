# /swydee report template

Fill this from the facts JSON. **Every number must be copied verbatim from a facts display string** (`headline[].displayCurrent/displayPrevious/displayDelta`, `breakdowns[].rows[].values[].display/displayPrevious/delta`, `timeSeries[].buckets[].derived.*` and `pacing.*.display`, or a `findings[].evidence.*` string). No arithmetic, no re-rounding, no summing. `platforms[].metrics` is a COVERAGE record, not a number source: read it to know what a platform can and cannot be said to have measured, and NEVER quote its display strings. `breakdowns[].rows[].valuesById` is deliberately NOT quotable either: the closer does not index it, so a number taken from there cannot be traced and will block publish. Promoting it needs the closer and this file changed together (ANLZ-aCandidTally-1 S12). One further source exists only when the facts carry an `estimates` block: its display strings are quotable ONLY under hard rule 6, inside `## Estimates (modeled)`.

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
5. **Anchors** (machine-read verification scaffold; keep exactly in the draft). These are HTML comments the verifier uses to scope numbers and confirm surfacing — they are **stripped from the delivered client report** (the closer's `-PublishTo` writes the clean copy on PASS), so they never reach the client; include them in the draft anyway. Each platform gets its own `##` section header with `<!-- platform:<providerId> -->` immediately under it — **exactly one** platform anchor per section (two in one section is flagged, and an anchor whose id isn't in the facts is flagged). Put `<!-- finding:<fid> -->` on the **same line** as that finding's numbers (a finding's figures only trace on the line carrying its fid — don't split the comment onto its own line), and `<!-- caveat:<id> -->` on the caveat's line. The prose around them is free to paraphrase.
6. **Estimates are modeled, never measured.** A number from the facts `estimates` block (written by `Invoke-SwydoForecast.ps1`) appears ONLY under a heading that reads exactly `## Estimates (modeled)` (no sub-headings inside it), on a body line that carries its `<!-- estimate:EST#n -->` anchor AND a visible word saying what it is ("estimated", "modeled", "projected") - the anchor is stripped from the client copy, the word is what the client sees. EVERY line in that section that carries a number needs both. Each action / total estimate in the facts must be presented, with its base (`display`) and its range (`displayLow` to `displayHigh`); the cost-per-conversion and conversion-rate estimates are optional. Quote the display strings verbatim - never round one ("about 57" for an estimated 56.7 is rejected anywhere in the report). Set an estimate beside what was recorded THIS period (`measuredDisplay`), never beside a previous period. Never show the id `EST#n` in visible text, and keep every HTML comment on one line. Measured sections keep the measured figures; do not restate a headline, a delta or a finding using an estimate, and do not put an estimate in Recommendations. You still do no arithmetic: not a midpoint, not a rounded range, not a difference between an estimate and a measured figure.
7. **Derived metrics are calculated, not reported by the platform.** A number from the facts `derivedMetrics` block (written by `Resolve-SwydoMetric.ps1`) appears ONLY in its own platform's section, on a body line (not a heading) that carries its `<!-- derived:<id> -->` anchor and says so in words the client still sees once the anchor is stripped. Exactly three wordings are accepted, where `<P>` is the platform's name as in the facts, "the platform" or "the dashboard": **"derived — not a figure `<P>` reports"**, **"calculated, not reported by `<P>`"**, or **"computed: `<P>` does not report it"** ("derived", "calculated" and "computed" are interchangeable; "doesn't" is accepted). Quote the entry's `formula` verbatim on an anchored line, once per entry. When `approximate` is true, put "about" (or approximately / roughly / around) **directly before each such figure**, or give the range as "between `<displayLow>` and `<displayHigh>`"; quote every derived figure at the precision given, never rounder. Compare with the previous period only when `comparison.hasComparison` is true. A `refused` entry gets one line saying it could not be calculated, with the reason in plain words and **no number at all**. **No derived figure and no derived anchor in Recommendations** - refer to the metric there by name. Do not put figures in a request `label`: nothing typed into a request can be cited. See **Derived metrics** under Structure.

## Structure

*(intro: 1–2 warm sentences — the quarter in one breath.)*

For each platform in `meta.providers`:

```
## <client-facing platform name, e.g. Google Ads / Meta>
<!-- platform:<providerId> -->

- <Metric> was/were <displayCurrent> in <meta.currentPeriod> against <displayPrevious> in <meta.previousPeriod> (a <qualifier> <increase|decrease|improvement> of <displayDelta>).
- ...one bullet per headline metric worth featuring...

One-line takeaway.

<optional: intra-period pacing/CPL ONLY from timeSeries (pacing.series, derived.CPL), and a short
 prose call-out of a key breakdown row — again as prose, not a table.>
```
**Narrate EVERY comparison as prose — never a table, chart, or other structured format.** This applies to
the per-platform QoQ headline, breakdown/segment comparisons, pacing, and any period-over-period or
across-segment contrast. The client already sees the tabular/visual layer as Swydo widgets, so the report's
job is the narrative. Use bullets or sentences, one point per featured metric, e.g. *"Impressions were
95,302 in Q2 against 53,398 in Q1 (a whopping increase of 78.5%)."* The qualifier
("whopping/strong/healthy/concerning") carries the voice; the numbers are verbatim facts display strings
(`displayCurrent`, `displayPrevious`, `displayDelta` — drop the delta's sign in prose, the increase/decrease
word carries direction). Only include the against-last-period clause for metrics whose fact has
`hasComparison:true`. Do not emit markdown tables anywhere in the report.

**Derived metrics** [include ONLY if the facts have a `derivedMetrics` block; then every entry is required].
Put each entry in its platform's section (`platformId`), next to the reported metric it qualifies. One
bullet per entry, written on ONE physical line (the closer reads line by line - never wrap it):
```
- <label> was <current.display> in <current.period> (derived — not a figure <platformName> reports: <formula>, <numerator input display> over <denominator input display>), alongside the reported <reported.displayCurrent> <reported.metric>.  <!-- derived:<id> -->
```
- When `current.approximate` is true write "was about <current.display>", or "was between <displayLow> and
  <displayHigh>", and say in a few words that the dashboard rounds the inputs. When it is false, write the
  figure plainly - it is exact.
- The formula is quoted from `formula` exactly, on a line carrying the anchor, once per entry. A later
  mention of the figure needs the anchor and the "derived — not a figure <platform> reports" wording again,
  but not the formula.
- Input figures on that line come from `current.inputs[].display`. A filtered input's subtotal can show more
  decimals than the dashboard's own cells (for example 97.59): quote it as given.
- Previous period: only when `comparison.hasComparison` is true, e.g. "up 70.7% from $24.76" - with "about"
  directly before any figure whose block says `approximate`. When it is false, say there is no like-for-like
  comparison and give the reason from `comparison.reason` in plain words; do not reach for a previous figure
  from a widget yourself.
- `notes[]` are the tool's caveats (a cross-check that could not be used, a rounded input). Carry the ones that
  change how far the figure can be trusted, on the anchored line itself. A separate follow-on sentence may
  carry the anchor too; it needs the "derived — not reported" wording only if it quotes a number that appears
  nowhere else in that platform's data.
- A `refused` entry: one line saying the figure could not be calculated from this dashboard and why
  (`reasons[]`, in plain words), with the anchor and **no number of any kind** - not the reported figure, not
  a number from the reason. If the entry has a `platformId`, the line goes in that platform's section;
  otherwise in the intro, above the first platform section.
- A negative result is quoted with its minus sign, as given.
- A derived figure is still measured data rearranged: every caveat on its inputs (incomplete tracking, the
  seasonality caveat, a major discrepancy) applies to it too - say so where it matters.
- Recommendations: name the metric ("cost per lead without Directions"), never its figure, and no anchor.

Then:

```
## Analytical insights
**What's working** — wins, each citing the finding's numbers.  <!-- finding:WIN#n -->
**Needs attention** — losses.  <!-- finding:LOSS#n -->
**Anomalies worth knowing** — the anomalies (concentration, share-mismatch, segment-divergence,
  new/paused, budget-constrained, front-loading from timeSeries).  <!-- finding:ANOM_*#n -->
(Every major data-gap / discrepancy appears here too.)

## Context (unverified, client-supplied)   [include ONLY if meta.annotations is non-empty]
For each meta.annotations[] item, quote its `.text` verbatim and put its anchor `<!-- annotation:<aid> -->`
(e.g. `<!-- annotation:ANN#1 -->`) on that line. These are client-supplied notes (account changes, creative
refreshes, launches). Cite them ONLY as temporal co-occurrence — "coincided with", "was logged the same
period" — NEVER as cause, regardless of the voice profile. A number inside a note is being quoted, not
asserted, and traces only on its own anchored line.

## Estimates (modeled)   [include ONLY if the facts have an `estimates` block with items; then it is required]
Open with one or two sentences in plain words. Say, in these words, that the figures are "modeled, not
measured"; who declared the data incomplete (`estimates.declared.declaredBy`), which metric / action(s),
and the window (`outageStart` to `outageEnd`). Then the bullets below - each on ONE line, each ending with
its anchor, each containing the word "estimated" (or "estimate" / "modeled" / "projected"):
- <what>: an estimated <display> (range <displayLow> to <displayHigh>), against the <measuredDisplay> actually recorded.  <!-- estimate:EST#n -->
- How this estimate was built, in a sentence a client can follow: the tracked-day pace gives an estimated <methods[run-rate].display>, last period's level gives <the prior-level methods[].display values>, and the base blends them, leaning on the tracked-day pace in proportion to how much of the period was tracked.  <!-- estimate:EST#n -->
- The limit of this estimate: paraphrase `uncertainty` and keep its substance (a wide disagreement between the lines of evidence, a small sample, "indicative, not precise"); if `crossChecks[]` exists, say whether that check landed inside the estimated range.  <!-- estimate:EST#n -->
Give the first bullet for every action estimate and for the total (the closer requires both); the "how it
was built" and "limit" bullets at least once for the per-action estimate. Cost per conversion and
conversion rate are optional, same first-bullet shape. If `estimates.refused[]` is non-empty, add one plain
sentence (no numbers, no anchor) saying what could not be estimated and why.
A line without an estimate anchor cannot carry an estimate number. No sub-headings in this section. Do not
attribute the estimate to campaign performance, and do not set it beside a previous period ("last
period's level" as a description of a method is fine; "down from <n> last period" is not).

## Recommendations
Concrete next steps from the losses/anomalies. Any recommendation resting on a requiresDownstreamData
finding says to confirm downstream/lead-quality first. State the seasonality caveat once.
```

## Reminders
- Prefer quoting a finding's `statement` as the basis for a win/loss/anomaly point, then paraphrase around it — this keeps the number anchored and the role/period correct.
- Annotations (`meta.annotations`) are client-supplied CONTEXT, not measured facts: quote verbatim under "Context", anchor each with `<!-- annotation:<aid> -->`, and never let a note's presence become a causal claim ("the June 8 refresh drove the lift" is forbidden; "the lift coincided with a June 8 refresh" is fine).
- If `meta.periodConfidence` is `unconfirmed`, add "period labels approximate" once.
- Estimates (`estimates.items[]`) are the tool's model, not data: quote `display` / `displayLow` / `displayHigh` and method results verbatim, only under "Estimates (modeled)", each on its anchored line with the word "estimated" (or "modeled" / "projected"). When a client note asked for a projection, the "Context" section still quotes the note verbatim; the projection itself goes in "Estimates (modeled)".
- Derived metrics (`derivedMetrics.entries[]`) are the tool's arithmetic over reported components: quote `display` strings verbatim, in the platform's own section, on one line with `<!-- derived:<id> -->`; say "derived — not a figure <platform> reports"; state the `formula` once; put "about" directly before anything `approximate`; keep them out of Recommendations. If you want a figure the block does not hold, request it from the tool (SKILL.md step 2a); never work it out yourself.
- Headings are verified too: a number in a heading must be a facts display string in that section's scope, so keep figures in the body unless the heading quotes one verbatim. Keep every anchor comment on one line. Small whole numbers under 100 are not machine-checked, which makes them the one place a slip can pass: quote them from the facts exactly like any other figure.
- Keep the client copy free of internal ids, share links, and the facts filename.
