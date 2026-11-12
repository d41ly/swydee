# ANLZ-aModeledGap-1 — modeled estimates for a metric declared incomplete

**Status:** INPROGRESS · rev-2 · 2026-11-12 · node a · Tier-2 · base 02835529 · streams analysis+orchestration · review 2026-11-12-review-aModeledGap-1

## 1. Goal

When a period's metric is known to be incomplete, a tool estimates what it would have been and
explains the estimate, so the report can present it as a labelled estimate and never as a
measurement. The trigger was the Rentex October 2026 report: a client note said web lead tracking
was cut off after Oct 9 and fixed on Oct 29, and asked for a full-month projection.

This spec is retroactive. The owner asked for the feature in conversation on 2026-11-12 and that
request was the approved scope. The feature was built before this file was written, on `main` in
the primary tree, which `AGENTS.md` section 3 forbids. Both deviations are recorded in section 9
and in the review.

## 2. Scope (IN)

- S1. `skill/scripts/Invoke-SwydoForecast.ps1`: all estimate arithmetic. Inputs are a facts file,
  a declaration (who, first and last day lost, which conversion actions) and an optional ledger.
- S2. Methods computed side by side, each recorded with its inputs, their display strings and
  their sources: last period's rate per click and per impression applied to this period's
  traffic, last period's value moved in step with the actions that kept tracking, the trailing
  ledger conversion rate, and the tracked-day pace extended to the full period.
- S3. Low is the smallest method and high is the largest. The base blends the prior-level family
  mean and the tracked-day family mean, weighting the tracked-day pace by the share of the period
  that was observed.
- S4. With per-action estimates and a breakdown that reconciles to the headline, the tool derives
  the account total, the conversion rate and the cost per conversion.
- S5. Fail-closed refusals with a stated reason: fewer than two methods, an untrusted comparison,
  an unstable ledger history, a breakdown that does not reconcile, an identity that does not hold,
  a non-count metric, an unmatched partial observation, unreadable input, a credential-bearing
  input.
- S6. Output is one top-level `estimates` member spliced into the facts text. The measured facts
  are byte-preserved.
- S7. `skill/scripts/_EstimateCheck.ps1`, hooked into `skill/scripts/Test-ReportNumbers.ps1`: an
  estimate number traces only on a body line carrying `<!-- estimate:EST#n -->` directly under a
  heading that reads exactly `Estimates (modeled)`.
- S8. `skill/SKILL.md` gains Flow step 2b, the `forecast:"..."` argument, a parameters table and
  a Notes entry. `skill/report-template.md` gains hard rule 6 and the `Estimates (modeled)` block.
- S9. `tests/Test-Forecast.ps1` as a gate leg, and `tests/Backtest-Forecast.ps1` as a manual
  hold-out harness.

## 3. Non-goals (OUT)

- Inferring an outage from the numbers. A declaration is always required.
- A daily pull by the extractor. The facts carry no daily split, so a partial-window figure must
  be supplied by the user through the spec file.
- Estimating a rate or a money metric directly. Follow-up ANLZ-aModeledGap-6.
- Trend facts. The tool accepts only facts written by `Analyze-SwydoReport.ps1`.
- Combining an estimate with a derived metric, for example cost per conversion excluding one
  action on estimated conversions.
- Fixing closer weaknesses that predate this unit and affect measured numbers equally. Follow-ups
  ANLZ-aModeledGap-2 and ANLZ-aModeledGap-3.

## 4. Design

### Data model

`estimates` holds `tool`, `estimatesVersion`, `generatedAt`, `label`, `disclosure`, `declared`,
`items[]` and `refused[]`. Each item carries `eid`, `kind` (`action`, `total` or `dependent`),
`display`, `displayLow`, `displayHigh`, `measuredDisplay`, `statement`, `method`, `methods[]`,
`skippedMethods[]`, `crossChecks[]` and `uncertainty`. Each method carries `id`, `family`,
`display`, `formula`, `inputs[]` with a `source` per input, and `assumption`.

Estimated counts always display one decimal. A whole number under 100 is not a measure token to
the closer, so a whole display could slip past the tracer.

### Base rule

The prior-level methods are correlated, so they count as one line of evidence through their
family mean. The base is `w x tracked-day mean + (1 - w) x prior-level mean`, where `w` is tracked
days over period days, or the supplied window's days over period days. The owner chose this
weighting on 2026-11-12 after the first hold-out run. With one family only, the base is that
family's mean and the uncertainty text says the range understates the uncertainty.

### Closer rules

`_EstimateCheck.ps1` adds thirteen violation types. They are listed in `skill/SKILL.md` Notes.
All are inert when the facts carry no `estimates` member and the report no estimate anchor. The
closer file itself gains one dot-source line and five hook lines.

### Files touched (estimate)

New: `skill/scripts/Invoke-SwydoForecast.ps1`, `skill/scripts/_EstimateCheck.ps1`,
`tests/Test-Forecast.ps1`, `tests/Backtest-Forecast.ps1`. Edited: `skill/SKILL.md`,
`skill/report-template.md`, `skill/scripts/Test-ReportNumbers.ps1`, `tools/gate-legs.json`,
`AGENTS.md`, `.claude/SESSION-KICKOFF.md`.

### Alternatives rejected

- Re-serializing the facts through `ConvertTo-Json`. It can alter measured values, so the block is
  spliced into the text instead.
- A separate estimates file. The archive stores one facts file per run, so a sidecar would not be
  kept with the report it explains.
- A plain midpoint between the two families. It gave the tracked-day pace half the weight even
  when most of the period was tracked.
- Blending the ledger rate into the per-action total. It ignores what the unaffected actions
  measured, so it is a cross-check there and a method only when the whole metric is incomplete.

## 5. Production-readiness checklist

- security: the tool gates the facts, ledger and spec text for a share credential before parsing,
  gates its own output, refuses a key-shaped `-DeclaredBy`, and accepts only analyzer facts.
- perf / scale: N/A — one pass over a facts file; the splice scans the text once.
- a11y: N/A — no UI.
- i18n: formatting and parsing use the invariant culture; a de-DE run was checked in review.
- error / empty / loading states: exit 2 for bad input with the facts untouched, exit 1 when all
  estimates are refused with any earlier block removed, exit 0 otherwise.
- observability: every skipped method and refused target carries its reason in the block and on
  the console.
- risks: the facts file is rewritten in place by default; the write goes to a temp file and is
  copied over, and every path is resolved once against the PowerShell location.
- testing + left-shift gates: `tests/Test-Forecast.ps1` is a gate leg; every confirmed review
  finding has a test named with its finding id.
- migration / rollback: none — revert the merge commit; facts without the block are unaffected.
- user docs: `skill/SKILL.md` step 2b, parameters and Notes; `skill/report-template.md` rule 6.

## 6. Acceptance criteria

- AC1. When the tool runs on the archived Rentex October 2026 facts with the web form action
  declared untracked from 2026-10-10 to 2026-10-28, it writes four estimates and refuses none.
- AC2. When a draft cites those estimates as the template shows, the closer passes and publishes.
- AC3. When an estimate number appears in a platform section, in Recommendations, unlabelled, or
  without its range, the closer fails with the matching estimate violation.
- AC4. When the facts carry no `estimates` member, `tests/Test-Closer.ps1` still passes 129 of
  129.
- AC5. When no declaration source or no outage window is given, the tool exits 2 and writes
  nothing.
- AC6. When every estimate is refused after an earlier successful run, the facts no longer carry
  an `estimates` member.

## 7. Gates

`bash tools/run-gates.sh` with the new leg `Test-Forecast (modeled estimates)`. The other eight
suites keep their counts. ps source hygiene and memory hygiene stay green.

## 8. Open questions

none

## 9. Revision log

- rev-1 · 2026-11-12 · retroactive record of the feature as built from the owner's request,
  including the tracked-share base weighting the owner chose after the first hold-out run.
- rev-2 · 2026-11-12 · folded review 2026-11-12-review-aModeledGap-1: 30 fixes in the tool, the
  closer rules, the docs and the tests; dependent items renamed from `derived`; refusal semantics
  for exit 1 changed to remove a stale block.

## 10. Reuse audit

none — codebase-map not adopted. Seams reused by reading the source: the closer's
`Normalize-Num`, `Get-Ulp`, `Get-MeasureTokens` and `Find-Candidates` in
`skill/scripts/Test-ReportNumbers.ps1`, and the format specifiers of `Format-Metric` in
`skill/scripts/Analyze-SwydoReport.ps1`. The top-level member splicer is new here; a second copy
exists in unmerged work, and extracting one shared helper is follow-up ANLZ-aModeledGap-4.
