# /swydee report template

Write the report FROM the analysis worksheet (`analysis-playbook.md`, SKILL.md step 3b), citing numbers from the facts JSON. **Every number must be copied verbatim from a facts display string** (`headline[].displayCurrent/displayPrevious/displayDelta`, `breakdowns[].rows[].values[].display/displayPrevious/delta`, `timeSeries[].buckets[].derived.*` and `pacing.*.display`, or a `findings[].evidence.*` string). No arithmetic, no re-rounding, no summing. `platforms[].metrics` is a COVERAGE record, not a number source: read it to know what a platform can and cannot be said to have measured, and NEVER quote its display strings. `breakdowns[].rows[].valuesById` is deliberately NOT quotable either: the closer does not index it, so a number taken from there cannot be traced and will block publish. Promoting it needs the closer and this file changed together (ANLZ-aCandidTally-1 S12). One further source exists only when the facts carry an `estimates` block: its display strings are quotable ONLY under hard rule 6, inside `## Estimates (modeled)`.

## Voice
**Persona (constant):** a senior practitioner writing to a client you have a good relationship with — warm, direct, honest about bad news. Role is category-derived from the dominant `meta.providers[].category`: `ads` → senior media buyer; `seo` → senior SEO strategist; `email-crm` → senior lifecycle/email marketer; mixed / `other` → senior performance marketer.

**Attribution profile — selected by the `voice:<type>` argument (default `causal`).** A profile changes ONLY tone and how confidently results are attributed; it NEVER changes the numbers, the structure, the depth of the analysis, or the mandatory caveats/anchors below. Every profile delivers the full argument: what happened, why, what it means, what to do.
- **causal** (default): confident, takes credit — "drove", "funded", "generated", "delivered", "because". Attribute the movements to the work.
- **correlational**: cautious about causation — "alongside", "while", "as", "coincided with"; state what moved without claiming the campaign caused it.
- **executive**: top-line first, terse, decision-oriented; short paragraphs; lead each insight with the decision it supports and keep only the figures that decision needs. Attribution as in causal.
- **analytical**: precise and methodology-aware; foreground confidence, what the data does and doesn't support, and every caveat; neutral attribution.
- **consultative**: teaching tone; explain the *why* and the levers behind each move and orient every point toward a next step; moderate attribution.

If `voice:<type>` names an unknown profile, fall back to `causal` and say so in one line. Regardless of profile: do not attach evaluative words (good/bad/strong/weak) to a metric whose `direction` is `neutral`; and remember confident attribution frames *why* numbers moved — it never licenses changing a number or dropping a caveat (the closer verifies the figures, not the attribution).

## Hard rules
1. Numbers verbatim from facts only. State comparisons as "`<displayCurrent>` against `<displayPrevious>` (an increase / a decrease of `<displayDelta>`, sign dropped)", as `<displayCurrent> (<displayDelta>)`, or as "from `<displayPrevious>` to `<displayCurrent>`" — **both ends must be facts display strings**. The delta of a rate is a relative change: say so, and never present it as a gap in points. If a metric's fact has `hasComparison:false`, do NOT use any comparative word/number for it.
2. **No blended/portfolio numbers** (there is no portfolio total in the facts) — report each platform separately. **No hand-summed segment figures** (cite the single-bucket concentration the facts give, e.g. "65+ = 53% of clicks", not a summed "55+ = 73%").
3. Reproduce **every** `meta.comparisonCaveats[]` at least once (in Data notes unless the narrative already made it) — write its `.text` and put its anchor `<!-- caveat:<id> -->` (e.g. `<!-- caveat:seasonality -->`) on that line so the verifier can confirm it. For every surfaced finding with `requiresDownstreamData:true`, its point/recommendation carries a "confirm downstream / lead-quality before acting" clause.
4. Surface every finding of severity ≥ major (anomalies, `dataGaps`, `discrepancies`), every `requiresDownstreamData` finding and every `GAP_UNIT_UNCONFIRMED`, each with its anchor: in the narrative where it bears on an insight, otherwise in Data notes. Findings below major are surfaced only as evidence for an insight.
5. **Anchors** (machine-read verification scaffold; keep exactly in the draft). These are HTML comments the verifier uses to scope numbers and confirm surfacing — they are **stripped from the delivered client report** (the closer's `-PublishTo` writes the clean copy on PASS), so they never reach the client; include them in the draft anyway. Each platform gets its own `##` section header with `<!-- platform:<providerId> -->` immediately under it — **exactly one** platform anchor per section (two in one section is flagged, and an anchor whose id isn't in the facts is flagged). Put `<!-- finding:<fid> -->` on the **same line** as that finding's numbers (a finding's figures only trace on the line carrying its fid — don't split the comment onto its own line), and `<!-- caveat:<id> -->` on the caveat's line. Every comment opens and closes on ONE line - a comment that spans lines is rejected, and so is a literal `<!--` shown in the text, even in backticks. The prose around them is free to paraphrase.
6. **Estimates are modeled, never measured.** A number from the facts `estimates` block (written by `Invoke-SwydoForecast.ps1`) appears ONLY under a heading that reads exactly `## Estimates (modeled)` (no sub-headings inside it), on a body line that carries its `<!-- estimate:EST#n -->` anchor AND a visible word saying what it is ("estimated", "modeled", "projected") - the anchor is stripped from the client copy, the word is what the client sees. EVERY line in that section that carries a number needs both. Each action / total estimate in the facts must be presented, with its base (`display`) and its range (`displayLow` to `displayHigh`); the cost-per-conversion and conversion-rate estimates are optional. Quote the display strings verbatim - never round one ("about 57" for an estimated 56.7 is rejected anywhere in the report). Set an estimate beside what was recorded THIS period (`measuredDisplay`), never beside a previous period. Never show the id `EST#n` in visible text, and keep every HTML comment on one line. Measured sections keep the measured figures; do not restate a headline, a delta or a finding using an estimate, and do not put an estimate in Recommendations. You still do no arithmetic: not a midpoint, not a rounded range, not a difference between an estimate and a measured figure.
7. **Derived metrics are calculated, not reported by the platform.** A number from the facts `derivedMetrics` block (written by `Resolve-SwydoMetric.ps1`) appears ONLY in its own platform's section, on a body line (not a heading) that carries its `<!-- derived:<id> -->` anchor and says so in words the client still sees once the anchor is stripped. Exactly three wordings are accepted, where `<P>` is the platform's name as in the facts, "the platform" or "the dashboard": **"derived — not a figure `<P>` reports"**, **"calculated, not reported by `<P>`"**, or **"computed: `<P>` does not report it"** ("derived", "calculated" and "computed" are interchangeable; "doesn't" is accepted). Quote the entry's `formula` verbatim on an anchored line, once per entry. When `approximate` is true, put "about" (or approximately / roughly / around) **directly before each such figure**, or give the range as "between `<displayLow>` and `<displayHigh>`"; quote every derived figure at the precision given, never rounder. Compare with the previous period only when `comparison.hasComparison` is true. A `refused` entry gets one line saying it could not be calculated, with the reason in plain words and **no number at all**. **No derived figure and no derived anchor in Recommendations** - refer to the metric there by name. Do not put figures in a request `label`: nothing typed into a request can be cited. See **Derived metrics** under Structure.

## What the report is for

The client already has the dashboard. The report is an analyst advising them on how to run their
account or channel: what happened, why, what it means for their business, and what to do next. It is read
top to bottom as one argument in one voice.

- **One summary of the main numbers, then the argument.** Each platform section opens with a short
  "Key numbers" list of its main metrics (below). It orients the reader and is the only list of
  metrics in the report.
- **Outside that summary, every number earns its place.** A figure appears only as evidence for a
  point, and the sentence or the one after it says what the figure means.
- **Interpret, then advise.** Each part of the narrative ends in a consequence: a recommendation, a
  decision for the client, or a stated reason for leaving things alone.
- **No inventory of findings.** There is no list of findings, and no second list of metrics after
  "Key numbers". A finding that carries no argument is not in the narrative (see Data notes for the
  few that must be on record).
- **Honest about limits.** Say what the data shows, what it suggests, and what it cannot tell us.
  Confidence words follow the worksheet's confidence levels and the voice profile.
- **Plain, fluent prose.** Short paragraphs that connect ("because", "which means", "so"). Bullets
  only for genuinely parallel items such as the recommendations. A reader who skips to any section
  should still follow it.

## Structure

The order below is fixed. Two headings are read by the closer by their text and must be exact:
`## Estimates (modeled)` and `## Recommendations`. A platform section is identified by its anchor,
not its title. Keep `## Data notes` and `## Context (unverified, client-supplied)` as written.

```
# <Client>: <platform(s)> review, <period in words>

<"The short version": no heading needed. One paragraph, or three to five short bullets, that a busy
 client can stop after: the verdict on the period, the two or three things that drove it, and the
 main thing we recommend or need from them. A handful of headline or breakdown figures at most; a
 finding's figure needs its anchor on the same line. NO derived and NO estimate figure here: name
 the metric and give the number in its own section. In a report with several platforms, name the
 platform beside every figure. If the data for the period is compromised (a declared outage, an
 untrusted comparison), say so here, first. If no client target is known, say that the period is
 judged only against the previous one.>

## <client-facing platform name, e.g. Google Ads / Meta>
<!-- platform:<providerId> -->

<One short orienting paragraph: what this account is and what it is for (the worksheet's account
 model), and the period. Name the comparison period (meta.previousPeriod, in words) only when
 meta.compareBasis is not `untrusted`; otherwise say there is no trusted comparison this period.>

### Key numbers
- <Metric> was/were <displayCurrent> in <period in words> against <displayPrevious> in <previous period in words> (an increase / a decrease of <displayDelta>, sign dropped).
- ...one bullet per main headline metric, each on ONE physical line...
<REQUIRED for every platform, in every voice. The main points of the account at a glance, from
 `platforms[].headline` only: what the account reached (impressions, and impression share where the
 platform has it), the response (clicks, click-through rate), what it cost (cost, cost per click)
 and what it produced (conversions, conversion rate, cost per conversion, and revenue or return
 where reported), in that order. For SEO or email use that channel's equivalents. Normally six to
 ten bullets; leave out metrics that are zero, do not apply to the account, or repeat another
 bullet. Rules:
 * the against-last-period clause only when the metric has `hasComparison:true` and
   meta.compareBasis is not `untrusted`; otherwise state the level alone;
 * plain statements, no interpretation: the insights below carry the meaning. A qualifier word
   ("strong", "concerning") is allowed where the voice calls for it, never on a `neutral` metric;
 * when a figure is known to be compromised (a declared outage, a major gap or discrepancy on that
   metric), say so in a short clause on the same bullet, so the list cannot be read without it;
 * NO derived and NO estimate figure here, and no finding figure: headline display strings only;
 * the delta of a rate is a relative change: write "a relative decrease of <displayDelta>".
 The insights may quote the same figures again where they are evidence; they do not walk the list.>

### <Insight 1, as a plain-sentence heading with NO figures, e.g. "Clicks cost more, and the rise sits in one keyword">
<The argument, in prose: what moved or what stands out (with the figures that prove it), where it
 sits (the breakdown rows that carry it), why we think it happened and how sure we are, and what it
 means. End on the consequence, pointing to the recommendation it leads to by name.>

### <Insight 2 ...>
### <Insight 3 ...>
<Up to five insights, in order of importance to the client, not in dashboard order; fewer, and a
 short report, when little moved. Include what is working when it is real - a client needs to know
 what to protect - and say plainly when nothing improved. Length guide: the insight narrative for
 one platform runs to roughly 800 to 1,200 words, not counting "Key numbers". Past that, cut the hedges and the rivals that do
 not change the action before cutting evidence.>
```

**Writing an insight.**
- Open with the point, not with a metric. *"The month paid more for the same traffic"* comes before
  *"Cost was `<displayCurrent>` against `<displayPrevious>` (an increase of `<displayDelta>`) while
  clicks held at ..."*. With no trusted comparison the point is about levels, never about movement.
- State a comparison in one of hard rule 1's forms, only for facts with `hasComparison:true`.
- Bring in a breakdown row to LOCATE a movement, and a finding to show a pattern. Keep each
  finding's figures on the same physical line as its `<!-- finding:<fid> -->` anchor. A paragraph is
  one physical line, so an anchor at the end of the paragraph covers it; never hard-wrap a paragraph
  that quotes a finding.
- When two data points pull in different directions, say so and say which you believe and why.
- Use the client's own campaign and conversion-action names the first time, then a short plain name.
- Platform section sub-headings (`###`) inherit the platform's scope. Keep figures out of headings,
  and **never put any platform's name in an insight heading**: the closer reads a heading that
  names a platform as the start of a new scope, and the insights after it lose theirs.
- Give your best reading at its stated confidence, once. Do not repeat a hedge in every sentence.
- Do not say "lost ... to budget" for a metric with no comparison (the closer reads "lost" as a
  comparison): write "budget ran out for `<N>` of eligible impressions".

**Narrate every comparison as prose - never a table, chart, or other structured format.** The client
already sees the tabular layer as Swydo widgets. Do not emit markdown tables anywhere in the report;
"Key numbers" is a bullet list of sentences, not a table.

**Derived metrics** [include ONLY if the facts have a `derivedMetrics` block; then every entry is required].
Put each entry in its platform's section (`platformId`), inside the insight paragraph it supports. That
paragraph is ONE physical line (the closer reads line by line - never wrap it) and carries the anchor, the
marker wording and the formula. The sentence has this shape:
```
<label> was <current.display> in <current.period> (derived — not a figure <platformName> reports: <formula>, <numerator input display> over <denominator input display>), alongside the reported <reported.displayCurrent> <reported.metric>.  <!-- derived:<id> -->
```
An entry that supports no insight goes on a line of its own under the platform's orienting paragraph.
- When `current.approximate` is true write "was about <current.display>", or "was between <displayLow> and
  <displayHigh>", and say in a few words that the dashboard rounds the inputs. When it is false, write the
  figure plainly - it is exact.
- The formula is quoted from `formula` exactly, on a line carrying the anchor, once per entry. A later
  mention of the figure needs the anchor and the "derived — not a figure <platform> reports" wording again,
  but not the formula.
- Input figures on that line come from `current.inputs[].display`. A filtered input's subtotal can show more
  decimals than the dashboard's own cells (two decimals where the dashboard shows one): quote it as given.
- Previous period: only when `comparison.hasComparison` is true, e.g. "up `<comparison delta>` from `<previous.display>`" - with "about"
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
  otherwise under `## Data notes` (never in the short version).
- A negative result is quoted with its minus sign, as given.
- A derived figure is still measured data rearranged: every caveat on its inputs (incomplete tracking, the
  seasonality caveat, a major discrepancy) applies to it too - say so where it matters.
- Recommendations: name the metric ("cost per lead without Directions"), never its figure, and no anchor.

Then, after the last platform section:

```
## Data notes
<Short and plain: what a careful reader needs to know about the data behind this report. Prose or a
 few bullets, one physical line each. Required here unless already made in the narrative, each with
 its anchor on the same line:
 * every `dataGaps` / `discrepancies` finding of severity major or above, and every
   `GAP_UNIT_UNCONFIRMED`, in plain words and with what it means for the conclusions;  <!-- finding:<fid> -->
 * every major anomaly or `requiresDownstreamData` finding that the narrative did not use, with one
   clause on why it does not change the advice;  <!-- finding:<fid> -->
 * every `meta.comparisonCaveats[]` text;  <!-- caveat:<id> -->
 * "period labels approximate" when `meta.periodConfidence` is `unconfirmed`.
 Required items that change nothing in the advice may share ONE line, each anchor on that line.
 Do NOT list info-level findings here to be complete. An info-level finding appears in the report
 only where it is evidence for an insight; the one exception is a gap or discrepancy that limits a
 conclusion the report draws (playbook Step D).>

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
<Three to six, fewer in a quiet period, numbered in priority order: impact on the client's business
 first, then confidence, then effort. Each is one short paragraph that a client could approve as
 written:
 **<the action, specific and executable>.** Why: the insight it follows from, by name. What we
 expect: the direction and the metric that should move. How we will check, and when. What must be
 confirmed first, or the risk. Who does it (us or the client).
 The closer does not trace this section or its sub-sections, so they carry NO measured figure: not a
 headline, not a delta, not a restated finding. The only number allowed is a proposed target or
 watch threshold, labelled as a proposal and not computed from the facts.
 Any recommendation resting on a `requiresDownstreamData` finding says to confirm downstream / lead
 quality before acting. No recommendation without an insight behind it. A question the account team
 can answer itself is not a recommendation to the client (playbook Step C).>

### What we need from you
<Decisions and information only the client can give, each with what it unblocks; the client's target
 first when none is known. Omit if none.>

### What we will watch next period
<The two or three measures that will show whether the advice worked. Omit if it repeats the above.>
```

## Reminders
- When a finding is evidence for an insight, take its figures from its `statement` / `evidence` and keep them on the line with its anchor - this keeps the number, role and period correct - then say what it means in your own words. Never strip a scope clause ("within a N% subset of ...").
- Before the closer runs, the draft is reviewed for reasoning (SKILL.md step 4b holds the checks). The closer checks numbers; it cannot check an argument.
- Annotations (`meta.annotations`) are client-supplied CONTEXT, not measured facts: quote verbatim under "Context", anchor each with `<!-- annotation:<aid> -->`, and never let a note's presence become a causal claim ("the June 8 refresh drove the lift" is forbidden; "the lift coincided with a June 8 refresh" is fine).
- If `meta.periodConfidence` is `unconfirmed`, add "period labels approximate" once.
- Estimates (`estimates.items[]`) are the tool's model, not data: quote `display` / `displayLow` / `displayHigh` and method results verbatim, only under "Estimates (modeled)", each on its anchored line with the word "estimated" (or "modeled" / "projected"). When a client note asked for a projection, the "Context" section still quotes the note verbatim; the projection itself goes in "Estimates (modeled)".
- Derived metrics (`derivedMetrics.entries[]`) are the tool's arithmetic over reported components: follow hard rule 7 and **Derived metrics** under Structure. If you want a figure the block does not hold, request it from the tool (SKILL.md step 2a); never work it out yourself.
- Headings are verified too. A number in a heading must be a facts display string in that section's scope; a heading may quote a finding only when its own body (not a sub-section) echoes that finding with its anchor, and a heading never carries annotation, estimate or derived figures or their anchors - those go on body lines. Simplest: keep figures in the body. Not checked: the report title (the first heading, `#` level) and anything under Recommendations. A platform or client name with digits ("Search Ads 360") is fine in a heading; any other digits in a heading are read as a number. Title the last section exactly `## Recommendations` (leading numbering is fine): a heading that merely contains the word, such as `## Next steps and recommendations`, is treated as an ordinary section and its targets will fail. Small whole numbers under 100 are not machine-checked, which makes them the one place a slip can pass: quote them from the facts exactly like any other figure.
- Keep the client copy free of internal ids, share links, and the facts filename.
