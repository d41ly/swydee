# ANLZ-aModeledGap-8 — review fold-in: one Recommendations definition, heading rules, money and splicer hardening

**Status:** INPROGRESS · rev-1 · 2026-11-12 · node a · Tier-2 · base 0946539c · streams analysis+orchestration · review 2026-11-12-review-aModeledGap-3

## 1. Goal

Fold in the review the owner ordered of the follow-up build (ANLZ-aModeledGap-2, -4 and -6). The
review found that the heading rule left parts of the old gap open through the Recommendations
exemption, wrongly blocked headings that carry a platform or client name with digits, and that the
money path and the splicer had untested and unguarded edges.

## 2. Scope (IN)

- S1. `Split-Sections` in `skill/scripts/Test-ReportNumbers.ps1` owns one definition. The title is
  the first heading when it is level 1. A Recommendations section is opened by a heading other
  than the title whose visible text starts with "Recommendation(s)", runs to the next heading of
  the same or a higher level, and includes its sub-sections. This closes ANLZ-aModeledGap-7.
- S2. Inside a Recommendations section neither headings nor bodies are traced, and the estimate
  and derived misuse scans read the headings as well as the bodies. With `-TraceRecommendations`
  the headings are traced too.
- S3. `Get-HeadingTraceLine` reads the section flags, lends only finding anchors of the heading
  and its direct body, and masks platform and client names that carry digits.
- S4. Line endings are normalised once in `Invoke-Closer` and in `Strip-Anchors`, so a lone CR is
  a line break.
- S5. The derived-only comment loop in `Test-DerivedSurfacing` is removed;
  `Test-MultilineComments` is the only emitter of `multiline-comment`.
- S6. `skill/scripts/_EstimateCheck.ps1`: a currency token within half a cent of a money
  estimate's base, low or high states that estimate whatever its written precision, and the
  rounded-estimate rule covers money estimates of 100 or more after an approximation word.
- S7. `skill/scripts/Invoke-SwydoForecast.ps1`: the metric needs its own headline cell in every
  mode; money needs unit micros, a coverage record with `aggClass` sum and a currency symbol the
  closer reads; negative money is refused; a partial whose run-rate exceeds ten times every other
  method is refused; the small-sample sentence and the reconciliation tolerance are money-aware;
  the money flag is reset before anything can throw.
- S8. `skill/scripts/_FactsBlock.ps1`: the value must be one JSON value, and removal repeats until
  no member of that name is left.
- S9. Tests for every fix, replacing assertions that could not fail. Docs and records corrected.

## 3. Non-goals (OUT)

- Masking facts row labels and generic digit labels in body and heading text. Follow-up
  ANLZ-aModeledGap-9.
- Fenced code blocks: a `#` line inside a fence is still read as a heading. Follow-up
  ANLZ-aModeledGap-10.
- Teaching the closer code-prefixed currencies and negative money. Follow-ups ANLZ-aModeledGap-11
  and ANLZ-aModeledGap-12; until then the forecast tool refuses those targets.
- A gate that checks violation names quoted in `skill/SKILL.md` against the code. Follow-up
  ANLZ-aModeledGap-13.
- Binding a heading's borrowed figure to its metric. The tracer is value-only on body lines too;
  this belongs to ANLZ-aModeledGap-3.
- The quadratic comment regex on a line with one closer and thousands of openers. Self-inflicted
  input only.

## 4. Design

### Sections

`Split-Sections` adds `isTitle` and sets `kind` to `recommendations` in one pass over the finished
section list, so no caller walks the list again. A platform anchor inside a Recommendations
sub-section no longer makes it a platform section. A heading such as "Next steps and
recommendations" is now an ordinary traced section; the template tells the writer to title the
section "Recommendations".

### Heading line

The traced line is the heading's visible text with digit-bearing platform and client names
removed, followed by the finding anchors found on the heading and in its direct body. Whole-name
matching cannot be chosen by the writer, so it opens no laundering path. Other digit labels fail
in body text as well and are left for one masking rule that covers both.

### Money estimates in untraced text

Counts keep the precision rule, so a round "100" in a recommendation is a target and not the
estimate 100.0. Money differs: "$1,025" is the estimate $1,025.00 without its cents, so equality
within half a cent is enough. The rounded rule applies to money only from 100 upward, which keeps
"about $4" beside a $3.68 estimate legal.

### Partial scale

A partial above the recorded value is legitimate and is what the floor is for. The bound compares
the partial's run-rate with the other methods before the floor is applied, and refuses above ten
times the largest. The message names the unit.

### Files touched (estimate)

`skill/scripts/Test-ReportNumbers.ps1`, `skill/scripts/_CloserGaps.ps1`,
`skill/scripts/_EstimateCheck.ps1`, `skill/scripts/_FactsBlock.ps1`,
`skill/scripts/Invoke-SwydoForecast.ps1`, `tests/Test-Closer.ps1`, `tests/Test-Forecast.ps1`,
`tests/Test-ResolveMetric.ps1`, `skill/SKILL.md`, `skill/report-template.md`,
`tools/run-ps-suite.sh`, `AGENTS.md`, `.claude/SESSION-KICKOFF.md`.

### Alternatives rejected

- Lending a heading only the findings anchored on the heading itself. It blocks the natural
  "heading above its finding line" layout and does not bind the figure to a metric anyway.
- Lending from child sections. A level-2 heading could then borrow every finding in the report.
- Refusing a partial larger than the recorded value. Client-supplied partials are often larger.
- A timing assertion for the comment check. It would be flaky; the spec no longer claims one.

## 5. Production-readiness checklist

- security: N/A — no new input or output surface; the splicer now rejects a value that is not one
  JSON value.
- perf / scale: the per-section walk is gone; heading work is linear in the number of sections.
- a11y: N/A — no UI.
- i18n: only currencies with a symbol the closer reads are accepted as money targets.
- error / empty / loading states: each new refusal is an `INPUT:` error, exit 2, facts untouched.
- observability: every refusal names the metric, the reason and, for a partial, the unit.
- risks: the Recommendations definition is narrower, so a report whose final section is titled
  differently now has that section traced. All 13 archived drafts were re-verified and pass.
- testing + left-shift gates: `tests/Test-Closer.ps1`, `tests/Test-Forecast.ps1` and
  `tests/Test-ResolveMetric.ps1` gain one case per fix and per surviving mutation worth killing.
- migration / rollback: none — revert the merge commit.
- user docs: `skill/SKILL.md` Notes, step 2b and parameters; `skill/report-template.md` rule 5
  and Reminders.

## 6. Acceptance criteria

- AC1. When a report ends in a Recommendations section, a fabricated number in an earlier heading
  fails.
- AC2. When a heading merely contains "recommend", or carries it in a hidden comment, its section
  is traced.
- AC3. When a sub-heading under Recommendations states a target and its body states others, the
  report passes.
- AC4. When "## Search Ads 360" is a platform heading, it passes; "## Google Ads: 360 clicks" with
  no such fact fails.
- AC5. When a money estimate is written without its cents in Recommendations, the closer reports
  `estimate-misuse`.
- AC6. When `-Metric` names a metric with no headline cell, money in an unreadable currency, or a
  partial in the wrong unit, the tool exits 2 with the reason.
- AC7. When the 13 archived drafts are verified against their own facts, all pass.

## 7. Gates

`bash tools/run-gates.sh`. `Test-Closer` rises from 145 to 166, `Test-Forecast` from 213 to 256
and `Test-ResolveMetric` from 264 to 268. The other suites keep their counts.

## 8. Open questions

none

## 9. Revision log

- rev-1 · 2026-11-12 · written with the fold-in of review 2026-11-12-review-aModeledGap-3.

## 10. Reuse audit

none — codebase-map not adopted. The fold-in moves the Recommendations decision into the existing
`Split-Sections`, removes a duplicate comment check in favour of `Test-MultilineComments`, and
removes a duplicate verification in `Add-FcBlock` in favour of `Set-FactsMember`.
