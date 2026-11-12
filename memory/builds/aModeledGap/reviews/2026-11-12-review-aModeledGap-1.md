# ANLZ-aModeledGap-1 review - adversarial review of the modeled-estimates feature

**Status:** CLOSED - rev-1 - 2026-11-12 - node a - Tier-2 - base 02835529

## 1. What ran

Three independent finder subagents with distinct lenses, three independent verifier subagents that
reproduced each lens's findings with their own harnesses, and one adjudicator subagent that ruled
on every finding. The lenses were computation correctness of `Invoke-SwydoForecast.ps1`, an
adversarial pass on the closer rules in `_EstimateCheck.ps1`, and documentation, tests and repo
conventions. The test lens mutation-tested the suite on a scratch copy: 14 of 18 single-line
mutations survived the pre-review suite.

| Metric | Value |
|---|---|
| Agents | 3 finders, 3 verifiers, 1 adjudicator |
| Raw findings | 37 |
| Distinct after merging duplicates | 33 |
| Refuted by a verifier | 0 |
| Fixed in this unit, fully or in part | 30 |
| Follow-ups opened | 5 |
| Rejected in part | 1 |
| Process findings recorded | 3 |

## 2. Verdict

Ship after fold-in. No computation defect changed the Rentex result. The closer rules had real
gaps: a look-alike heading or a hidden comment could turn any section into the estimates section,
a heading could carry an estimate unlabelled, the base figure was not required, and the template's
own bullets produced a draft the closer rejected. All are fixed and tested. Two closer weaknesses
predate this unit and affect measured numbers equally; they are narrowed for estimates here and
backlogged in general.

## 3. Findings

| Id | Lens | Finding | Disposition |
|---|---|---|---|
| C1 | closer | Comments are stripped across lines but checked per line, so a header, label or disclosure can hide in a multi-line comment. | FIXED for reports with estimates (`estimate-multiline-comment`). General case DEFERRED, ANLZ-aModeledGap-2. |
| C2 | closer | Heading lines are never traced; an anchored heading satisfied surfacing and range alone. | FIXED: `estimate-anchor-on-heading`, headings never count as citing. Tracing headings in general DEFERRED, ANLZ-aModeledGap-2. |
| C3 | closer | The section test was an unanchored match on the raw header, comments included. | FIXED: comments stripped, exact heading required. |
| C4 | closer | Whole numbers under 100 are not measure tokens, so "about 57" for 56.7 passed anywhere. | FIXED narrowly: a whole number after an approximation word that equals a count estimate rounded either way is `estimate-misuse`. The exemption itself DEFERRED, ANLZ-aModeledGap-3. |
| C5 | closer | Round targets in Recommendations (100, $4, 18%) were flagged as estimates. | FIXED: a token must be at least as precise as the estimate to count as stating it. |
| C6 | closer | The base figure was not required; a method value could stand as the estimate. | FIXED: `estimate-base-missing`. |
| C7 | closer | An estimate could be compared with the previous period. | FIXED: `estimate-compared-to-previous`; "last period's level" as a method description stays legal. |
| C8 | closer, docs | The template's "how it was built" and "limit" bullets led to a rejected draft. | FIXED: every template bullet carries the anchor and an estimate word; a test reads the template. |
| C9 | closer | Disclosure wording "aren't measured" and similar was rejected; sub-headings were rejected without saying why. | FIXED: wording widened; sub-headings stay unsupported and the message and template say so. |
| C10 | closer | An unrelated "not ..., ... measured" sentence satisfied the disclosure; a negated label word satisfied the label. | Disclosure FIXED. Negated label REJECTED: not machine-checkable, and anchor, section, base, range and disclosure still apply. |
| C11 | closer | One cited estimate satisfied surfacing; an item without an eid was skipped silently. | FIXED: every action and total estimate must be cited; `estimate-item-without-eid`. |
| C12 | closer | The spec file had no credential gate; a bare key in `-DeclaredBy` was written through. | FIXED: gate on the spec text; a key-shaped `-DeclaredBy` is refused. |
| M1 | computation | Repeated declared actions were estimated twice and double-counted in the total. | FIXED: case-insensitive de-duplication. |
| M2 | computation | Clicks without a previous value disabled ledger-rate and the derived rate, which need current clicks only. | FIXED. |
| M3 | computation | `-Metric` accepted rates and money and emitted count-formatted nonsense. | FIXED: non-count metrics are refused. Summable money DEFERRED, ANLZ-aModeledGap-6. |
| M4 | computation | A partial observation naming no declared target was silently ignored. | FIXED: input error, exit 2. |
| M5 | computation | `-MinTrackedDays` was not applied to a supplied partial window. | FIXED. |
| M6 | computation | The rate identity used an absolute tolerance, so a different rate definition passed on low-rate accounts. | FIXED: relative 2 percent. The first fix kept an absolute floor and its own test caught it. |
| M7 | computation | Unparseable JSON exited 1, which the docs read as "all refused". | FIXED: exit 2. |
| M8 | computation | `-MinTrackedDays 0` with no tracked days wrote NaN and Infinity. | FIXED: rejected flag, zero tracked days skips run-rate, non-finite values never written. |
| M9 | computation | Relative paths were checked against the PowerShell location and read against the process directory; in-place mode deleted before moving. | FIXED: paths resolved once; write is temp then copy. |
| M10 | computation | With a partial window the weight was described as the tracked share. | FIXED: wording names the supplied window and its days. |
| M11 | computation | The ledger rate was multiplied by clicks without checking that this report's rate is conversions over clicks. | FIXED: one identity predicate gates the derived rate, the ledger method and the ledger cross-check. |
| D3 | tests | The backtest called itself blind, but run-rate recovers the hidden figure by construction. | FIXED: renamed hold-out, caveat printed and recorded. A daily-data backtest is ANLZ-aModeledGap-5. |
| D4 | tests | Eight fail-closed guards had no effective test; one test passed for the wrong reason. | FIXED: one test per guard. |
| D6 | docs, computation | A refused re-run left the earlier run's block, so a report without estimates then failed the closer. | FIXED: exit 1 removes a stale block. |
| D7 | docs | Stale counts and lists in `skill/SKILL.md`, `skill/report-template.md`, `AGENTS.md` and the kickoff manifest. | FIXED. |
| D8 | docs | Tool-written sentences contained internal ids that could reach the client copy. | FIXED: no `EST#` in quotable strings; `estimate-internal-id-visible`. |
| D9 | docs | Dependent items used `derived`, another feature's term; the member splicer exists twice. | Rename FIXED. Shared splicer DEFERRED, ANLZ-aModeledGap-4. |
| D10 | docs | `actionDimension` undocumented; required flags misstated; fan-out silent on who writes the section. | FIXED. |
| P1 | process | Built on `main` in the primary tree, not in a worktree. | RECORDED. Ported to `branch/forecast-estimates` before the first commit. |
| P2 | process | No spec or scope menu before building. | RECORDED. Retroactive spec written; the owner's request was the scope. |
| P3 | process | A second unit's uncommitted work shares four files in the primary tree. | RECORDED. This branch carries only this unit's hunks; the merge needs those files set aside. |

## 4. Checks that came back clean

The method arithmetic, day counting and outage clipping, the floor rule, the base weighting, the
account total, the inverted cost range, ledger selection and the stability gate all matched hand
checks. A de-DE culture run produced identical output. The splice preserved every other byte and
coexisted with a second tool's block in either order. Facts without an `estimates` member, with
empty `items`, or with `estimates` as a string verified exactly as before. `tests/Test-Closer.ps1`
stayed at 129 of 129. The weekday mapping in the backtest matches .NET `DayOfWeek`.
