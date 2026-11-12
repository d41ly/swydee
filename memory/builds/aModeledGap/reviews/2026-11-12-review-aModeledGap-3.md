# ANLZ-aModeledGap-8 review - review of the follow-up build (headings, comments, splicer, money)

**Status:** CLOSED - rev-1 - 2026-11-12 - node a - Tier-2 - base 0946539c

## 1. What ran

Three independent finder subagents with distinct lenses over commits 9025729 and c1dbe13 as they
stand on `main`, three independent verifier subagents that reproduced each lens's findings with
their own harnesses, and one adjudicator subagent. The lenses were an adversarial pass on the
heading and comment rules, correctness of the splicer and the money path, and documentation, tests
and records. The verifiers classified each closer finding as new or as an unclosed part of the old
gap, by comparing with a baseline in which no heading is traced. The test lens and its verifier
mutation-tested the suites on scratch copies.

| Metric | Value |
|---|---|
| Agents | 3 finders, 3 verifiers, 1 adjudicator |
| Raw findings | 37 |
| Refuted by a verifier | 0 |
| Confirmed only in part | 3 |
| Rejected, in whole or in part | 4 |
| Follow-ups opened | 5 |

## 2. Verdict

Ship after fold-in. Nothing found changes a published number. The heading rule had left three
parts of the old gap open through the Recommendations exemption: any second level-1 heading, every
heading after a title containing "recommend", and estimate or derived figures in a Recommendations
heading. It also wrongly blocked a platform or client name with digits in a heading. The fix
replaces the scattered tests with one definition in `Split-Sections`. On the money path a metric
without a headline cell skipped the gate entirely. Several tests added by the follow-up build
could not fail; they are replaced.

## 3. Findings

| Id | Lens | Finding | Disposition |
|---|---|---|---|
| H1 | closer | Any second level-1 heading was untraced. | FIXED: only the first heading, when level 1, is the title. |
| H2 | closer | A title containing "recommend" exempted every later heading and left its intro body untraced. | FIXED: the title never opens a Recommendations section. |
| H3 | closer | A hidden `<!-- recommend -->` made a section Recommendations. | FIXED: comments are stripped before the test. |
| H4 | closer | Estimate and derived figures in a Recommendations heading or sub-heading escaped the misuse scans. | FIXED: the scans read heading text too. |
| H5 | closer | A sub-heading under Recommendations was exempt while its body was traced. | FIXED: sub-sections are Recommendations until the next heading of the same or a higher level. |
| H6 | closer | A heading borrows every finding anchored in its body, so a figure can sit beside the wrong metric. | REJECTED: the tracer is value-only on body lines too; recorded with ANLZ-aModeledGap-3. |
| H7 | closer | A derived-only comment loop still flagged a bare arrow and reported spanning comments again. | FIXED: loop removed. |
| H8 | closer | Sub-headings with digit labels were blocked, including a required platform heading "Search Ads 360". | FIXED for platform and client names. Other labels DEFERRED, ANLZ-aModeledGap-9. |
| H9 | closer | A heading cannot quote a finding anchored in a child section, nor an annotation. | DOCS: by design; the template now says so. |
| H10 | closer | A lone CR glued text onto the title; a `#` line in a code fence is a heading. | CR FIXED. Fences DEFERRED, ANLZ-aModeledGap-10. |
| H11 | closer | The comment regex is quadratic with one closer and thousands of openers; sections were re-walked. | REJECTED for the regex, self-inflicted input. The re-walk is gone with the new design. |
| H12 | closer | A literal `<!--` in a code span fails; a derived figure in a heading gets no hint; `-TraceRecommendations` left Recommendations headings untraced. | Flag FIXED. Code span DOCS. Hint REJECTED as cosmetic. |
| S1 | money | Per-action mode with no headline cell for the metric skipped the gate: money came out as a count, a rate was estimated. | FIXED: refused in every mode. |
| S2 | money | A money estimate without its cents, or rounded, passed in Recommendations. | FIXED: half-cent equality; rounded rule for money of 100 or more. |
| S3 | money | Money in a currency with no symbol the closer reads could never be published. | FIXED: refused up front. Closer support DEFERRED, ANLZ-aModeledGap-11. |
| S4 | money | A partial value had no scale check and no documented unit. | FIXED: refused above ten times every other method; unit documented. |
| S5 | money | Negative money is formatted in a way the closer cannot read. Confirmed in part: the analyzer formats it the same way. | FIXED: refused. Closer support DEFERRED, ANLZ-aModeledGap-12. |
| S6 | money | The small-sample sentence and the reconciliation tolerance were count-scaled. | FIXED. |
| S7 | money | The money flag was reset after three early throws. | FIXED: reset first. |
| S8 | money | Two empty ids matched in the coverage lookup. | FIXED. |
| S9 | splicer | "Every other byte is kept" was false for pretty-printed or BOM input. | DOCS: header states what is preserved. |
| S10 | splicer | A crafted value could inject a duplicate member; removal left one of two duplicates. | FIXED: one JSON value required; removal repeats. |
| S11 | splicer | About 3 s on 5 MB. Confirmed in part. | REJECTED: negligible at real sizes. |
| T1 | tests | Breaking the walk turned heading tracing off for any report ending in Recommendations, unnoticed. | FIXED: the walk is gone and the case is tested. |
| T2 | tests | One assertion indexed a string and could not fail; a dead call preceded it. | FIXED. |
| T3 | tests | Finding lending was untested because the fixture figure also traced as a headline value. | FIXED: fixture figure exists only in the finding. |
| T4 | docs | `skill/SKILL.md` listed a violation no code emits and placed `multiline-comment` under derived-only rules. | FIXED. |
| T5 | docs | The title and `-TraceRecommendations` statements did not match the code. | FIXED by H1 and H12; text updated. |
| T6 | docs, money | "Money that sums" needed conditions the docs omitted; a currency-typed metric outside micros was formatted as a count. | FIXED: refused with a stated reason; conditions documented. |
| T7 | tests | Five splicer mutations survived. | FIXED: tests added; the duplicate check in `Add-FcBlock` removed as untestable. |
| T8 | tests | Money was tested only whole-metric in USD. | FIXED: per-action and euro cases. |
| T9 | records | The spec claimed a test pins the regex guard; it only asserts a count. | FIXED in the spec; no timing test. |
| T10 | tests | Two comment-state mutations survived; two assertions could not fail; fixture carried leftovers. | FIXED. |
| T11 | docs | The template omitted the heading rules a writer needs. | FIXED. |
| T12 | docs | Two header comments were stale. | FIXED. |
| T13 | records | A gap was cited under the wrong id; "four hook lines" was three. | FIXED in spec rev-3. |
| T14 | docs | Suite-output counts were wrong in three files. Confirmed in part: one file was misattributed. | FIXED. A names gate DEFERRED, ANLZ-aModeledGap-13. |

## 4. Checks that came back clean

Alternating the two splicers five times in both orders on real facts kept the measured prefix
identical and both members intact. `-Metric Cost` on the real Rentex facts produced money-formatted
displays throughout with micros divided once. Dependent metrics and ledger methods stay off for
targets other than Conversions. Constructed comment tricks either fail or publish exactly what was
checked. No crash on odd input. All 13 archived draft and facts pairs pass before and after the
fold-in.
