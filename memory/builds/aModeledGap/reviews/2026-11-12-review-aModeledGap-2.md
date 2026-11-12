# ANLZ-aModeledGap-2 review - adversarial review of the closer gap rules

**Status:** CLOSED - rev-1 - 2026-11-12 - node a - Tier-2 - base d7f015b1

## 1. What ran

One adversarial finder subagent over the uncommitted gap rules, with three priorities: wrongful
blocks, misses, and crashes or performance. It mined the 12 archived drafts for phrasings and
varied them, and ran every candidate through the closer. The orchestrator re-checked the findings
against the source and acted as the skeptic. One lens was enough for a diff of one helper file and
four hook lines; the first unit's review had already covered the rest of the closer.

| Metric | Value |
|---|---|
| Agents | 1 finder; the orchestrator was the skeptic and synthesis pass |
| Raw findings | 12 |
| Confirmed | 12 |
| Fixed by withdrawing the small-count rule | 7 |
| Fixed in the heading and comment rules | 3 |
| Deferred to backlog | 2 |

## 2. Verdict

Ship the heading and comment rules after fold-in. Do not ship the small-count rule. It blocked
ordinary prose in six ways and missed most fabricated small counts, because most small integers
match some unrelated fact in scope. The rule was removed before commit and ANLZ-aModeledGap-3 stays
open with a sharper statement of what a real fix needs.

## 3. Findings

| Id | Kind | Finding | Disposition |
|---|---|---|---|
| R1 | wrongful block | A number that labels or counts something else, with one word before the noun: "week 3 conversions", "only 2 generated leads". | FIXED by withdrawal. |
| R2 | wrongful block | Day-month dates, en-dash ranges and durations: "28 October leads", "55–64 group's conversions", "20 days leads". | FIXED by withdrawal. |
| R3 | wrongful block | Thresholds and ratios: "fewer than 20 conversions", "1 in 4 clicks". | FIXED by withdrawal. |
| R4 | miss | Noun-first phrasing, two words between, spelled-out numbers, singular nouns, nouns outside the list. | FIXED by withdrawal; the gap is ANLZ-aModeledGap-3. |
| R5 | miss | 33 to 75 of the integers 0 to 99 trace in global scope on the archived facts, so most fabricated small counts pass any phrase rule. | DEFERRED, ANLZ-aModeledGap-3: bind candidates to their metric. |
| R6 | wrongful block | List nouns used in another sense and the derived noun "actions": "13 conversion actions", "2 sales reps". | FIXED by withdrawal. |
| R7 | miss | Any annotation anchor, even an unknown id, switched the rule off for the line. | FIXED by withdrawal. |
| R8 | wrongful block | A sub-heading under Recommendations was traced; a heading quoting its section's finding failed. | FIXED: headings at or under Recommendations are not traced; a heading borrows the finding anchors of its own section. |
| R9 | miss | Month and lookback exemptions matched "decline" and "market" and exempted "last 45 leads". | FIXED by withdrawal. |
| R10 | miss | A heading that merely contains "recommend" makes its whole section untraced. | DEFERRED: predates this unit, lives in `Split-Sections`; recorded under ANLZ-aModeledGap-2. |
| R11 | wrongful block | A bare `-->` arrow in prose was called a comment; a title "Studio 360" failed to trace. | FIXED: the comment check tracks whether a comment is open; the level-1 title is not traced. |
| R12 | performance | A 140 KB line of unclosed comment openers took 63 s through the lazy regex; a string-typed finding evidence lent its length as a count. | FIXED: the regex runs only on a line holding both markers, pinned by a test; the evidence quirk left with the withdrawn rule. |

## 4. Checks that came back clean

No crash with null or empty facts, missing platforms, headline or findings, non-object headline
cells, regex metacharacters in metric names, an empty report, or 200,000-character lines. Setext
headings, trailing hashes, seven hashes and a number at the start of a heading are all handled.
All 12 archived draft and facts pairs pass before and after the fold-in.
