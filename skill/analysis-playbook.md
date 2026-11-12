# /swydee analysis playbook

How to turn a facts file into advice. Read this before writing a word of the report (Flow step 3b).
The tools decide what the numbers ARE. This file is about what they MEAN and what the client should
DO, which no tool decides for you.

## The standard

The client already has the dashboard. A report that restates it is worth nothing to them, however
accurate. The report is an analyst advising a client on how to run their paid account:

- It answers four questions, in this order: **what happened, why, what it means for the business,
  and what we do about it.**
- **Every number earns its place.** A figure appears only as evidence for a point. If you cannot
  finish the sentence "this matters because ...", the figure does not go in the report.
- **Every point lands somewhere.** An observation leads to a recommendation, a decision the client
  must make, or an explicit "no action, and here is why".
- It is one argument in one voice, read top to bottom. It is not a list of findings.

A useful test for any paragraph: could the client have written it themselves from the dashboard?
If yes, it is description. Add the interpretation or cut it.

## Ground rules that still bind the analysis

- **No arithmetic, ever.** You reason about relationships ("cost rose while clicks held, so the
  price of a click rose"); you never compute a figure. If the argument needs a number the facts do
  not carry (a cost per lead for a subset of conversion actions, a difference, a combined count),
  **request it from the tool** (SKILL.md step 2a) and wait for the result. Asking for a derived
  metric because the analysis needs it is expected, not exceptional.
- Shares and "N of M" figures exist only inside findings. Quote them from the finding; never work
  out a share from two cells.
- Never infer a tracking outage or a data problem from a number that merely moved. A gap exists only
  when the facts or a client note declare it.
- Respect `meta.compareBasis`, `hasComparison`, `confidence: low`, neutral `direction`, and every
  scope clause on a row finding. A caveat on an input is a caveat on every conclusion built on it.
- Client notes (`meta.annotations`) are context. They may shape which questions you ask; they are
  never cited as the cause of a movement.
- Certainty follows the voice profile and the evidence. Say what the data shows, what it suggests,
  and what it cannot tell us, and keep those three apart.

## Step A. Understand the account before the period

Write this down first, in a few lines. It frames everything else.

- **What the money buys.** Which platforms, which campaign types, and what the campaign, ad group
  and keyword names reveal about intent (brand or non-brand, prospecting or retargeting, which
  regions or products).
- **What counts as a result.** List the conversion actions and sort them into hard business outcomes
  (a purchase, a submitted form, a qualified call) and soft signals (a directions request, a page
  view, an engagement). If soft signals dominate the conversion count, every cost-per-conversion and
  conversion-rate figure is mostly measuring the soft signal. Say so, and judge efficiency on the
  hard outcomes (request the derived metric).
- **What the client told us.** Notes, declared outages, decisions, requests.
- **What the data cannot support this period.** The comparison basis, major gaps and discrepancies,
  metrics with no account total, missing conversion value.
- **The one-sentence account model.** For example: "A brand-defence search account in which most
  recorded conversions are map directions, so reported cost per conversion says little about lead
  cost."

## Step B. Establish what happened: decompose, then locate

Do not walk the headline metrics in dashboard order. Follow the chain the money takes:

`spend -> impressions -> clicks -> conversions -> cost per result (-> value, when recorded)`

1. **Find the link that moved.** Compare each link with the previous period. A change in an outcome
   is a change in volume, in price, in rate, or in mix. Name which. Examples of the reasoning:
   - cost up, clicks flat: the price per click rose; it is not a volume story;
   - clicks flat, conversions down: the rate fell, or tracking did, or the mix of conversion
     actions changed;
   - impressions up, impression share down: demand grew faster than our coverage of it.
2. **Locate it.** For the link that moved, use every breakdown (campaign, keyword, device,
   geography, network, audience, time, conversion action) to find WHERE the change sits. A movement
   that lives in one campaign or one keyword is a different problem from one spread evenly. Rows that
   moved against the total are leads, not trivia.
3. **Check the composition.** Does one row dominate a metric? Then the account figure is really that
   row's figure, and the story is about that row.

Locate before you explain. Most wrong explanations come from explaining an account-level average
that is really one segment's movement.

## Step C. Explain why: hypotheses, tested against the data

For each movement that matters, write the candidate explanation and then try to break it.

- **Supporting evidence**: at least two independent data points where the data has them (a headline
  figure plus the breakdown row that carries it; two breakdowns that agree).
- **Contradicting evidence**: look for it on purpose. If a breakdown disagrees with the story, the
  report must deal with it, not skip it.
- **Rival explanations** to rule out or carry as open: seasonality and the comparison window; a
  tracking or measurement change; a mix shift (a cheap segment shrank, an expensive one grew);
  small numbers; a budget or bid change by us; competition (impression share, lost share, price per
  click moving together); a change in what counts as a conversion.
- **Confidence**: high (several independent data points, no credible rival), medium (consistent
  with the data, a rival remains), low (a single data point, or small numbers). Low-confidence
  explanations are offered as questions to check, not as findings.
- **What would settle it**: the extra data or the test that would confirm or kill the explanation.
  This often becomes a recommendation or a request to the client.

When the data cannot distinguish between two explanations, say exactly that and say what would.
That is more useful to a client than a confident guess.

## Step D. Cross-reference: account for every data point

Before writing, go through the facts once more and give every item a disposition. Nothing is left
unconsidered and nothing is included by default.

For every finding (`wins`, `losses`, `anomalies`, `discrepancies`, `dataGaps`), every headline
metric and every breakdown, decide one of:

| Disposition | Meaning | Where it goes |
|---|---|---|
| `evidence` | It supports, qualifies or contradicts an insight | In the narrative, inside that insight |
| `required` | The closer demands it (severity major or above, `requiresDownstreamData`, a comparison caveat, `GAP_UNIT_UNCONFIRMED`) | In the narrative if it bears on an insight, otherwise in Data notes |
| `noted` | True and worth one line of record, but it carries no argument | Data notes, briefly |
| `dropped` | An artifact, a duplicate of another item, or trivial | Not in the report; reason recorded in the worksheet |

Checks to run while doing it:

- **Duplicates**: several findings are often one fact seen from different cuts (a campaign and its
  region; a network that is all of the account). Merge them into one point.
- **Artifacts**: a row finding that only reflects how a widget is bucketed or filtered (a month row
  compared across windows, a filtered widget's total) is not performance. Drop it, or explain it in
  one line of Data notes when it is `required`.
- **Contradictions**: two data points that cannot both mean what they seem to. Resolve it or
  surface it; never quote both as if they agreed.
- **Orphans**: after the pass, any insight without evidence is deleted, and any important data point
  without an insight means the analysis missed something. Go back to Step B.

## Step E. Decide what to do

Every recommendation is a piece of advice a client could act on or approve today.

- **Action**: specific and executable ("cap the Georgia campaign's daily budget until its form leads
  are confirmed", not "review Georgia").
- **Why**: the insight it follows from, with its evidence.
- **Expected effect**: the direction and the metric that should move. Do not invent a forecast
  figure; a target or threshold is fine when it is clearly a proposal.
- **How we will know**: the metric and the period to check.
- **Precondition or risk**: what must be confirmed first (always for a `requiresDownstreamData`
  finding: confirm downstream lead quality before acting), and what could go wrong.
- **Owner**: us (the account team) or the client.
- **Priority**: order by impact on the client's business first, then by confidence, then by effort.
  Three to six recommendations that matter beat ten that do not.

Also collect: **decisions and information we need from the client**, and **what we will watch next
period**. No recommendation without an insight behind it. No insight without a consequence.

## Step F. The analysis worksheet

Write the result of Steps A to E to `<out>\<stamp>-<slug>-analysis.md` before drafting. It is an
internal working file: it is never delivered and never archived as the report, and it follows every
credential rule. The report is written FROM it. Shape:

```
# Analysis worksheet: <client>, <period>

## Account model
<Step A, 4-8 lines, ending with the one-sentence account model>

## Insights (in order of importance to the client)
### I1. <the claim, as one sentence a client would understand>
- Evidence: <fact, exact display strings, and where it comes from: headline | breakdown row | finding fid>
- Against / rivals: <contradicting data, rival explanations, why they are ruled out or still open>
- Confidence: high | medium | low, and why
- So what: <what it means for the client's business>
- Leads to: R<n> | a question for the client | no action because ...
### I2. ...

## Recommendations
### R1. <action>  (owner, priority)
- From: I<n>   - Expected effect: ...   - Check: ...   - Precondition / risk: ...

## Needed from the client
- <decision or information, and what it unblocks>

## Disposition ledger
- <fid or metric or breakdown>: evidence I<n> | required -> <where> | noted | dropped (<reason>)
  (one line per finding; headline metrics and breakdowns may be grouped)

## Derived figures requested
- <id>: why the analysis needs it
```

Every display string in the worksheet is copied from the facts. The worksheet is where you catch a
weak argument cheaply, before it is dressed up as prose.

## Lenses by category

Questions that a senior practitioner asks. Use the ones the data can answer; do not report on the
ones it cannot.

**Paid search and other ads (`ads`)**
- Demand and coverage: are impressions moving with demand or with our budget? What do impression
  share, share lost to budget and share lost to rank say together?
- Price: is cost per click moving because of competition, because of a shift toward dearer keywords,
  campaigns or regions, or because of a bidding change? Which rows carry the change?
- Brand versus non-brand: what share of the account is brand defence, and is that spend buying
  results the brand would have received anyway?
- Efficiency by segment: which campaign, keyword, device, region, audience or daypart takes a share
  of cost out of line with its share of results? Is that a real inefficiency or a conversion-mix
  effect?
- Conversion quality: which actions are counted, which dominate, and does cost per result change
  meaning when soft actions are set aside?
- Budget: is the account constrained? If more budget were available, which segment has earned it,
  and which should give budget up?
- Quality signals: quality score, click-through rate and exact-match share, read together, as early
  warnings on relevance.

**Paid social**
- Reach against frequency: is spend finding new people or repeating to the same ones?
- Creative and placement: which placements or formats carry results, and which only carry
  impressions?
- Funnel role: is a campaign judged on the right outcome for its role (awareness against
  conversion)?

**SEO (`seo`)**
- Visibility against clicks: did impressions, position and click-through move together?
- Which pages or queries carry the change, and are they brand or non-brand?
- Is a change in sessions matched by a change in outcomes?

**Email and CRM (`email-crm`)**
- List health against engagement: sends, delivery, opens, clicks and unsubscribes as one chain.
- Which campaigns or flows carry the results, and what distinguishes them?

## Reasoning errors to check for

Each of these has appeared in a real draft and was caught only by the reasoning review.

- **Direction slips on derived consequences.** Under-counted leads UNDERSTATE the lead count and
  OVERSTATE cost per lead. Whenever a sentence says "understated", "inflated" or "flattered", check
  the direction for each metric it covers separately.
- **A claim wider than its data.** An account-level figure (impression share, share lost to budget)
  cannot be pinned on one campaign, device or keyword unless the facts carry that split. Say where
  the data stops, and make finding out a recommendation.
- **Absolutes.** "Every", "all", "nothing", "no loss" are almost never supported. A report that
  hypothesises one thing in one section must not assume the opposite in the next.
- **Quantity words that hide arithmetic.** "Most of the increase", "nearly all", "half", "doubled",
  "for much of the month" each encode a share or a ratio. Use one only when a facts display string
  says it; otherwise quote the two figures and let them speak, or give the dates.
- **Reallocation described as a rise.** When one row rises by more than the total, another row fell.
  Quote both; the story is the shift between them.
- **Judging on a metric the report itself distrusts.** If conversions are declared incomplete or are
  mostly a soft signal, a verdict that rests on conversions carries that reservation in the same
  sentence.
- **The calendar.** Two windows of equal length can hold a different mix of weekdays. When the
  day-of-week rows move in a block, check the calendar before reading it as behaviour, and remember
  that a different day mix can move average prices too.
- **Open rivals left out.** Routing between keywords, new or paused entities (rows with no previous
  value), a bidding change, budget exhaustion and seasonality are rivals for most price and volume
  stories. Name the ones the data raises and say what would settle them.
- **Two sections telling different stories.** The narrative, the Estimates section and the
  Recommendations must agree. If the narrative doubts an input, every estimate built on that input
  says so on its own line.
- **Promises in recommendations.** State the expected direction and the risk; never "no loss" or a
  level the data has never shown. Prefer a reversible first step, and say that it is one.
- **Tool language in client prose.** A finding's statement is the source of its figures, not a
  sentence to paste. Write "desktop", "search partner sites", "the two dashboard views" and the
  period in words; keep internal labels, ids and widget names out.

## Before you write: the five-line check

1. Can I state the period in two sentences a client would repeat to their boss?
2. Does every insight have evidence, a confidence level and a consequence?
3. Have I looked for the data that contradicts my main explanation?
4. Is every recommendation specific, owned, and tied to an insight?
5. Is there any figure in the worksheet that I computed myself? If so, remove it and request it.
