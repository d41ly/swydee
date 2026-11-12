# /swydee analysis playbook

How to turn a facts file into advice. Read this before writing a word of the report (Flow step 3b).
The tools decide what the numbers ARE. This file is about what they MEAN and what the client should
DO, which no tool decides for you.

## The standard

The client already has the dashboard. A report that restates it is worth nothing to them, however
accurate. The report is an analyst advising a client on how to run their account or channel:

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
  **request it from the tool** (SKILL.md step 2a, which holds the mechanics) and wait for the
  result. Asking because the analysis needs it is expected. Request only what an insight will use:
  every entry the tool writes must then appear in the report.
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
- **Objective and target.** What the client is trying to achieve and any target they have stated (a
  cost per lead, a return, a budget), taken from the notes or from what the user said. If none is
  known, write "no target known": the report then says that performance is judged only against the
  previous period, and the target is the first item under "What we need from you".
- **What the client told us.** Notes, declared outages, decisions, requests.
- **What the data cannot support this period.** The comparison basis, major gaps and discrepancies,
  metrics with no account total, missing conversion value.
- **The one-sentence account model.** For example: "A brand-defence search account whose conversion
  count is led by a soft action, so reported cost per conversion says little about lead cost."

## Step B. Establish what happened: decompose, locate, and read the levels

Do not walk the headline metrics in dashboard order. Follow the chain the channel runs on:

- ads: `spend -> impressions -> clicks -> conversions -> cost per result (-> value, when recorded)`
- SEO: `visibility (impressions, position) -> clicks -> sessions -> outcomes`
- email and CRM: `sends -> delivered -> opens -> clicks -> outcomes`

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
4. **Read the levels, not only the changes.** A segment that did not move can still be the problem.
   Where does spend sit against results? What constrains the account? Which like-for-like segments
   (two campaigns on the same kind of term, two devices, two regions) pay very different prices or
   convert at very different rates? A standing gap is an insight even in a month when nothing moved.

**When there is no usable comparison** (`meta.compareBasis` is `untrusted`, a metric has
`hasComparison:false`, or this is the first period on record), items 1 and 2 do not apply to it.
Item 3 and item 4 are the whole of Step B, and no sentence in the worksheet or the report says
anything rose, fell, held or changed, with or without a figure. **When little moved**, say so: one
or two insights and "no change recommended" is a valid, short report. Do not manufacture a story.

Locate before you explain. Most wrong explanations come from explaining an account-level average
that is really one segment's movement.

## Step C. Explain why: hypotheses, tested against the data

For each movement or gap that matters, write the candidate explanation and then try to break it.

- **Supporting evidence**: at least two independent data points where the data has them (a headline
  figure plus the breakdown row that carries it; two breakdowns that agree).
- **Its own predictions**: state what else must be true if the explanation holds (the click-through
  rate of the segment, the price of its sibling, spend against budget) and check each in the facts.
  An explanation whose predictions fail is demoted, however neat it is.
- **Contradicting evidence**: look for it on purpose. If a breakdown disagrees with the story, the
  report must deal with it, not skip it.
- **Rival explanations**: seasonality and the comparison window; a tracking or measurement change;
  a mix shift (a cheap segment shrank, an expensive one grew); small numbers; a budget or bid change
  by us; competition (impression share, lost share, price per click moving together); a change in
  what counts as a conversion. For each one the data raises, say which way the facts lean. Rule out
  the ones the facts already speak against. At most two open rivals reach the report, and only
  those that would change the action; the rest stay in the worksheet.
- **Confidence**: high (several independent data points, no credible rival), medium (consistent
  with the data, a rival remains), low (a single data point, or small numbers). Low-confidence
  explanations are offered as questions to check, not as findings.
- **What would settle it**: the extra data or the test that would confirm or kill the explanation.
  If only the client can supply it, it becomes a request to the client. If the account team can
  look it up itself (search terms, change history, bid strategy, budgets), it is NOT a client
  recommendation: list it under "Questions for the account team" in the worksheet.

When the data cannot distinguish between two explanations, say exactly that, give your best reading
at its stated confidence, and say what would settle it. Hedge once, in one place, then advise.

## Step D. Cross-reference: account for every data point

Before writing, go through the facts once more and give every item a disposition. Nothing is left
unconsidered and nothing is included by default.

For every finding (`wins`, `losses`, `anomalies`, `discrepancies`, `dataGaps`), every headline
metric and every breakdown, decide one of:

| Disposition | Meaning | Where it goes |
|---|---|---|
| `evidence` | It supports, qualifies or contradicts an insight | In the narrative, inside that insight |
| `required` | The closer demands it (severity major or above, `requiresDownstreamData`, a comparison caveat, `GAP_UNIT_UNCONFIRMED`) | In the narrative if it bears on an insight, otherwise in Data notes |
| `noted` | True, but it carries no argument | The worksheet only. One exception: a `dataGaps` or `discrepancies` item below major that limits a conclusion the report draws gets one line in Data notes |
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

- **Action**: specific and executable ("cap the regional campaign's daily budget until its form
  leads are confirmed", not "review the regional campaign"). Prefer a change to the account over
  another audit; "we will look into it" is not advice.
- **Why**: the insight it follows from, by name. Recommendations carry no measured figures.
- **Expected effect**: the direction and the metric that should move. Do not invent a forecast
  figure. The only number allowed is a proposed target or threshold, labelled as a proposal and not
  computed from the facts.
- **How we will know**: the metric and the period to check.
- **Precondition or risk**: what must be confirmed first (always for a `requiresDownstreamData`
  finding: confirm downstream lead quality before acting), and what could go wrong.
- **Owner**: us (the account team) or the client.
- **Priority**: order by impact on the client's business first, then by confidence, then by effort.
  Three to six recommendations that matter beat ten that do not; a quiet period may have fewer.

Also collect: **decisions and information we need from the client**, and **what we will watch next
period**. No recommendation without an insight behind it. No insight without a consequence.

## Step F. The analysis worksheet

Write the result of Steps A to E to `<out>\<stamp>-<slug>-analysis.md` before drafting. It is an
internal working file: it is never delivered, it stays in the out dir and is not archived, and it
follows every credential rule (no share link, no key, no extraction path). The report is written
FROM it. An analyst subagent in a fan-out writes no file: it returns these sections as its reply
(SKILL.md step 3b). Shape:

```
# Analysis worksheet: <client>, <period>

## Account model
<Step A, 4-8 lines, including objective and target, ending with the one-sentence account model>

## Insights (in order of importance to the client)
### I1. <the claim, as one sentence a client would understand>
- Evidence: <fact, exact display strings, and where it comes from: headline | breakdown row | finding fid>
- Predictions checked: <what else must be true, and what the facts say>
- Against / rivals: <contradicting data; each rival and which way the facts lean>
- Confidence: high | medium | low, and why
- So what: <what it means for the client's business>
- Leads to: R<n> | a question for the client | no action because ...
### I2. ...

## Recommendations
### R1. <action>  (owner, priority)
- From: I<n>   - Expected effect: ...   - Check: ...   - Precondition / risk: ...

## Needed from the client
- <decision or information, and what it unblocks>

## Questions for the account team
- <what we can look up ourselves, and which insight it would settle>

## Disposition ledger
- <fid>: evidence I<n> | required -> <where> | noted | dropped (<reason>)        (one line per finding)
- <breakdown>: <what its rows say about the metric that moved and about the constraint> -> I<n> | nothing
  (one line per breakdown, every metric column read; headline metrics may be grouped)

## Derived figures requested
- <id>: why the analysis needs it

## Review log
- <reviewer finding, in a few words>: fixed | rejected because <reason from the facts>
```

Every display string in the worksheet is copied from the facts. The worksheet is where you catch a
weak argument cheaply, before it is dressed up as prose. Every insight in it appears in the report;
delete the ones that do not survive.

## Lenses by category

Questions that a senior practitioner asks. Use the ones the data can answer. A question the facts
cannot answer but that would change the budget or the strategy is not dropped: it becomes a
question for the client or the account team, or a proposed test. A category with no lens below
(web analytics, e-commerce, calls, other) uses Steps A to E as they stand, and what you would
expect from the domain is raised as a question, never asserted.

**Paid search and other ads (`ads`, which includes paid social)**
- Demand and coverage: are impressions moving with demand or with our budget? What do impression
  share, the share budget ran out for and the share missed on rank say together? Read impression
  share by every cut the facts carry (device, campaign, network) before calling the account
  budget-constrained: the constraint usually sits somewhere specific.
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
- Paid social: is spend finding new people or repeating to the same ones (reach against
  frequency)? Which placements or formats carry results, and which only carry impressions? Is each
  campaign judged on the right outcome for its role (awareness against conversion)?

**SEO (`seo`)**
- Visibility against clicks: did impressions, position and click-through move together?
- Which pages or queries carry the change, and are they brand or non-brand?
- Is a change in sessions matched by a change in outcomes?

**Email and CRM (`email-crm`)**
- List health against engagement: sends, delivery, opens, clicks and unsubscribes as one chain.
- Which campaigns or flows carry the results, and what distinguishes them?

## Reasoning errors to check for

Each of these has appeared in a real draft or was raised in review of one.

- **Direction slips on derived consequences.** Under-counted leads UNDERSTATE the lead count and
  OVERSTATE cost per lead. Whenever a sentence says "understated", "inflated" or "flattered", check
  the direction for each metric it covers separately.
- **A claim wider than its data.** An account-level figure (impression share, share lost to budget)
  cannot be pinned on one campaign, device or keyword unless the facts carry that split. Say where
  the data stops, and make finding out a recommendation.
- **Absolutes.** "Every", "all", "nothing", "no loss" are almost never supported. A report that
  hypothesises one thing in one section must not assume the opposite in the next.
- **Words that hide arithmetic.** Quantity words ("most of", "nearly all", "half", "doubled", "for
  much of the month", "a few", "almost the same"), ranking words ("the largest", "the cheapest",
  "the main driver") and totality words ("the whole increase", "entirely") each encode a share, a
  ratio, a subtraction or a sort you have not been given. Use one only when a facts display string
  or a finding says it; otherwise quote the two figures and let them speak, or give the dates. A
  ranking over a breakdown the facts mark as truncated ("top N of M rows") is never safe.
- **Cuts are not causes.** The campaign, keyword and device views of one movement are the same
  money seen three ways. Do not present them as three things that each added to it.
- **Reallocation described as a rise.** When one row rises by more than the total, another row fell.
  Quote both; the story is the shift between them.
- **Judging on a metric the report itself distrusts.** If conversions are declared incomplete or are
  mostly a soft signal, a verdict that rests on conversions carries that reservation in the same
  sentence.
- **The calendar.** Two windows of equal length can hold a different mix of weekdays. When the
  day-of-week rows move in a block, raise the day mix as a rival in words only: never count days,
  never state a number of weekdays, and never name a weekday the facts do not name (numbered day
  buckets carry no mapping).
- **Percent against percentage points.** A rate's delta in the facts is a relative change. Give both
  levels and call the delta a relative change; never present it as a gap in points, and never work
  the gap out.
- **Big percentages on small bases.** A large change on a handful of conversions is noise until
  shown otherwise. Say the base is small.
- **Platform-reported conversions are not incremental and not comparable.** A platform claims the
  conversions it touched. Never add or blend them across platforms, and do not rank platforms or
  campaigns on cost per result when what they count as a result differs.
- **Open rivals left out, or carried when the facts speak.** Routing between keywords, new or paused
  entities (rows with no previous value), a bidding change, budget exhaustion and seasonality are
  rivals for most price and volume stories. Name the ones the data raises, say which way the facts
  lean, and what would settle the ones still open.
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
3. Have I looked for the data that contradicts my main explanation, and checked its predictions?
4. Is every recommendation specific, owned, and tied to an insight, and is none of them a question
   we could answer ourselves?
5. Is there any figure in the worksheet that I computed myself? If so, remove it and request it.
