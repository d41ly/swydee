# ANLZ-aModeledGap-2 — closer traces headings and rejects comments that span lines

**Status:** INPROGRESS · rev-2 · 2026-11-12 · node a · Tier-2 · base d7f015b1 · streams analysis+orchestration · review 2026-11-12-review-aModeledGap-2

## 1. Goal

Close the follow-ups the ANLZ-aModeledGap-1 review opened, so a fabricated measured number can no
longer pass in a heading or behind a multi-line comment, the facts-member splicer has one shared
copy, and a summable money metric can be estimated. The owner asked for the follow-ups to be fixed
on 2026-11-12 while the first unit waited to merge.

## 2. Scope (IN)

- S1. ANLZ-aModeledGap-2: `skill/scripts/_CloserGaps.ps1`, hooked into
  `skill/scripts/Test-ReportNumbers.ps1`. Heading text is traced in the heading's own section
  scope. An HTML comment that does not open and close on one line is `multiline-comment`.
- S2. ANLZ-aModeledGap-4: `skill/scripts/_FactsBlock.ps1` holds `Find-FactsMember`,
  `Remove-FactsMember` and `Set-FactsMember`. `Invoke-SwydoForecast.ps1` uses it and keeps no
  private scanner.
- S3. ANLZ-aModeledGap-6: `-Metric` accepts money that sums. The facts coverage record decides:
  `aggClass` `sum` is accepted, anything else is refused. Estimates of a money metric display and
  type as currency.
- S4. `skill/SKILL.md` and `skill/report-template.md` state the heading and comment rules, the
  additive-metric rule, and the small-number gap that remains.

## 3. Non-goals (OUT)

- ANLZ-aModeledGap-3, tracing a bare whole number under 100. A phrase-pattern rule was built and
  withdrawn after review; see section 4 and the review. It stays open.
- ANLZ-aModeledGap-5, a daily-data backtest. It needs a daily widget in the Swydo report or
  extractor work against the live API, and a share link from the owner.
- Moving the unmerged derived-metrics tool onto `_FactsBlock.ps1`. That tool is another unit.
- Changing how a section is classified as Recommendations. A heading that merely contains
  "recommend" still switches its section's tracing off; recorded under ANLZ-aModeledGap-2.

## 4. Design

### Headings

`Split-Sections` keeps heading text out of the section body. `Get-HeadingTraceLine` returns the
heading as one extra line for the per-line tracer, so it is traced in the section's own scope with
no change to `Split-Sections`. The finding anchors found in the section body are appended to that
line, so a heading may quote the figures of a finding its section echoes. Two headings are not
traced: the level-1 title, because client and report names carry digits, and any heading at or
under a Recommendations heading, because targets are not facts.

### Comments

`Strip-Anchors` removes comments across lines and every check reads line by line.
`Test-MultilineComments` keeps one bit of state, whether a comment is open, and reports the line
that leaves a comment open and the line that closes it. A bare `-->` with no comment open is an
arrow in prose and is ignored. The lazy comment regex runs only on a line holding both markers.

### Small whole numbers, withdrawn

The first draft traced a whole number under 100 when an outcome noun followed it. The review found
six classes of ordinary prose it blocked and five classes of fabrication it missed. The decisive
miss is structural: in the archived facts, 33 to 75 of the integers 0 to 99 match some unrelated
fact in scope, so a pattern rule passes most fabricated small counts anyway. The rule was removed
before commit. A real fix binds each candidate to its metric.

### Files touched (estimate)

New: `skill/scripts/_CloserGaps.ps1`, `skill/scripts/_FactsBlock.ps1`. Edited:
`skill/scripts/Test-ReportNumbers.ps1` (four hook lines), `skill/scripts/Invoke-SwydoForecast.ps1`,
`skill/scripts/_EstimateCheck.ps1`, `tests/Test-Closer.ps1`, `tests/Test-Forecast.ps1`,
`skill/SKILL.md`, `skill/report-template.md`.

### Alternatives rejected

- Shipping the small-count rule as a warning. The closer has no warning channel, and a rule known
  to miss most cases would read as coverage it does not give.
- Tracing every heading including the title. A client named with digits would block every report.

## 5. Production-readiness checklist

- security: N/A — no new input or output surface; the splicer verifies its result by re-parsing.
- perf / scale: a 140 KB line of unclosed comment openers is judged without the lazy regex; a test
  pins it.
- a11y: N/A — no UI.
- i18n: N/A — no locale-dependent text.
- error / empty / loading states: `Set-FactsMember` throws on a non-object; the closer rules add
  violations and never throw.
- observability: `multiline-comment` names the line number; a heading violation names the heading
  as its section.
- risks: the closer is stricter for every report. All 12 archived draft and facts pairs were
  re-verified and still pass.
- testing + left-shift gates: `tests/Test-Closer.ps1` gains the heading and comment cases;
  `tests/Test-Forecast.ps1` gains the splicer and money cases.
- migration / rollback: none — revert the commit; facts and archived reports are unaffected.
- user docs: `skill/SKILL.md` Notes and step 2b; `skill/report-template.md` Reminders.

## 6. Acceptance criteria

- AC1. When a heading carries a number that is not a fact in its section's scope, the closer
  reports `untraceable-number`.
- AC2. When a comment opens on one line and closes on another, the closer reports
  `multiline-comment` for both lines.
- AC3. When the 12 archived drafts are verified against their own facts, all pass.
- AC4. When `-Metric Cost` is given on facts whose coverage record marks it `sum`, the estimate
  displays as money; when `-Metric "Cost / conversion"` is given, the tool exits 2.
- AC5. When `Invoke-SwydoForecast.ps1` is searched for a private member scanner, none is found.

## 7. Gates

`bash tools/run-gates.sh`. `Test-Closer` rises from 129 to 145 and `Test-Forecast` from 194 to
213. The other suites keep their counts.

## 8. Open questions

none

## 9. Revision log

- rev-1 · 2026-11-12 · follow-ups 2, 3, 4 and 6 designed and built, including a small-count rule.
- rev-2 · 2026-11-12 · folded review 2026-11-12-review-aModeledGap-2: small-count rule withdrawn,
  title and Recommendations sub-headings exempt, a heading borrows its section's finding anchors,
  a bare `-->` is no longer a comment, the comment check avoids a quadratic regex.

## 10. Reuse audit

none — codebase-map not adopted. This unit creates the shared seam: `_FactsBlock.ps1` is the one
facts-member splicer, extracted from `Invoke-SwydoForecast.ps1`. The heading rule reuses the
closer's existing per-line tracer rather than adding a second one.
