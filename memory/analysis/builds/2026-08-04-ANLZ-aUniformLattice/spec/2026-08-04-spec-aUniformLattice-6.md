# ANLZ-aUniformLattice-6 — P5: rewire coverage onto the matrix, and disclose it

**Status:** SPECCED · rev-2 · 2026-08-05 · node a · Tier-2 · base 52ccae91 · parent ANLZ-aUniformLattice-1 · review wf_31f12c1f-2bc

## 1. Goal

Make the matrix the authority for what the report can and cannot say about each platform, and
disclose the change. P5 is the only phase that alters default output, so it is the only one carrying
the waiver.

## 2. Scope (IN)

- S1. `GAP_NO_ACCOUNT_TOTAL`'s MEMBERSHIP IS UNCHANGED — still observed-minus-headline. Only its
  statement and evidence gain the per-metric REASON, taken from the matrix cell. See D1.
- S1b. Fix the P1 miss: `skill/SKILL.md:31` still gated Mode B on `schemaVersion == 2`, so the model
  would REFUSE the v3 files P1 started writing. Also `SKILL_BUILD_SPEC.md` (two sites), the extractor
  header comment and `SWYDO_REPORT_EXTRACTION_SPEC.md`.
- S1c. `skill/report-template.md` states that `platforms[].metrics` is a COVERAGE record whose display
  strings are NEVER quotable.
- S2. `skill/SKILL.md` tells the analyst subagent to read `platforms[].metrics` for coverage — what a
  platform can and cannot be said to have measured — while numbers keep coming from where they come
  from today.
- S3. `meta.canonicalVersion` 2 to 3, with the flip set enumerated in-facts.
- S4. The measured flip set, produced on fixtures and on the live report, recorded in the spec.

## 3. Non-goals (OUT)

This section is longer than usual because P5's scope was CUT after the evidence changed. Each cut is
a decision, not an omission.

- **The value-reading rules are NOT repointed.** WIN, LOSS, `GAP_UNIT_UNCONFIRMED` and
  `ANOM_BUDGET_CONSTRAINED` keep reading `headline`, because it is the audited, closer-indexed source
  and D1 shows the two sources genuinely diverge. Moving a force-surfaced `major` onto a source the
  closer does not index, for no coverage gain, is the wrong trade.
- **`Build-FactIndex` is NOT extended.** See D2: the closer fails CLOSED on a matrix-only number, and
  indexing the matrix would add candidates that weaken the type-and-magnitude fabrication guard.
- **No `requiresProvenanceAnchor` forcing class and no disclosure-prose check.** The master spec's S30
  and S31 exist to force disclosure of a tool-COMPUTED number. P6 is WONTDO, so no such number can
  exist. Building an unused forcing class in the closer would be dead machinery in the one script
  where dead machinery is most dangerous. Review confirmed both cuts as correct.
- **`report-template.md`'s quotable whitelist is not WIDENED** — but it is NARROWED by S1c, which
  states the matrix is a coverage record and never a number source.
- **`DISC_CROSS_WIDGET` is not touched.** Its correctness argument is its dimension-signature key.
- **The hidden-section divergence is an ACCEPTED RESIDUAL, recorded not silent.** The headline
  publishes a hidden-section widget's value and the matrix refuses it. Aligning them would itself be a
  default-output change needing its own measurement, so it is deliberately out of P5. The matrix's
  `reason='hidden-section'` is the disclosure.
- **No trend change.**

## 4. Design

### Data model

**D1 — headline and matrix coverage are NOT equivalent, and rev-1 was wrong to claim they were.**
Rev-1 generalised from the live QCU report, where the two agree exactly (facebook-ads 14/14,
google-adwords 25/25, zero display disagreements). Review disproved the generalisation in BOTH
directions and reproduced each with a fixture:

- **Headline can exceed matrix.** `Test-MatrixEligible` refuses a hidden-section widget; the headline
  loop has no such test. A hidden-section KPI therefore yields a headline VALUE and a matrix
  `reason='hidden-section'`.
- **Matrix can exceed headline.** The headline attributes by `Get-WidgetProvider` (the widget's first
  declared provider) while the matrix attributes by metric-id prefix. On a single-provider widget
  carrying a foreign-prefix metric, the headline files it under the widget's platform and the matrix
  under the metric's true platform.

Both are why S1 keeps membership on the HEADLINE. Repointing it would have listed a metric the report
still publishes (self-contradicting facts) and silently DELETED a correct warning (fail-open). The
matrix supplies the per-metric REASON only, which is the honest half and carries no membership risk.

The same divergence is why the force-surfaced value rules stay on `headline`: it is the audited,
closer-indexed source, and moving them would change which source a `major` finding reads without any
coverage benefit.

**D2 — why the closer is untouched, corrected.** Rev-1 justified this with the same false premise as
D1. The true reason is fail-CLOSED behaviour: `Build-FactIndex` reads named keys, never a generic
walk, so a matrix-only display string is simply not a candidate and a report quoting one is BLOCKED,
not fabricated. Indexing the matrix would add candidates and weaken the type-and-magnitude guard,
which is the wrong direction.

Because a matrix-only display string CAN exist (D1's second direction), S1c makes the rule explicit
where the model reads it: `report-template.md` now states that `platforms[].metrics` is a coverage
record and its display strings are never quotable. Belt and braces — the closer would refuse it
anyway, and now the model is told not to try.

**D3 — the new `GAP_NO_ACCOUNT_TOTAL`.** Same rule id, same `info` severity, same per-provider
cardinality, same 20-item cap, per U6 D11. Two things change.

Its INPUT does not change. It stays `-not $pf.headline.Contains($_)`, so membership is invariant by
construction on EVERY report rather than on the one that was measured.

Its STATEMENT gains the reason breakdown. Today every missing metric is described with one
undifferentiated clause, "only dimensioned rows with no total row (or blended widgets)", which is a
guess about the cause. The matrix knows the actual cause per metric, so the statement now reports
counts by reason token. On the live report that turns a wrong explanation into a right one: the three
Google Ads metrics are not no-total-row at all, they are `no-usable-cell`.

The evidence block gains `byReason`, a flat string per U10 D5 — the closer stringifies evidence values
and an object would render as garbage.

**D4 — the flip set, and why it is small.** The waiver covers exactly:

1. `GAP_NO_ACCOUNT_TOTAL.statement` wording, on reports that emit it.
2. `GAP_NO_ACCOUNT_TOTAL.evidence.byReason`, a new key.
3. `meta.canonicalVersion` 2 to 3.
4. `meta.matrixVersion` 1, a new key naming the matrix algorithm.

Membership is provably invariant, so no finding appears or disappears on any report. The two
counterexample fixtures from the review are pinned as tests precisely so a future edit cannot re-open
this.

No metric value, no headline cell, no other finding and no closer verdict moves. That is enumerable
and provable, which is what U9 D3 demands of a waiver.

### Inventory

`Analyze-SwydoReport.ps1`: the `GAP_NO_ACCOUNT_TOTAL` emitter and the `meta` block.
`skill/SKILL.md`: the analyst brief.

### Migration

A schemaVersion-2 extraction still analyzes. `canonicalVersion` 3 self-describes the artifact per U6
D10 and U9 D6; no archived facts are touched, per U9 D10/D11.

### Rollout

P5 is the waiver phase. It lands after the measured flip set exists, not before.

### Files touched (estimate)

| File | Nature |
|---|---|
| `skill/scripts/Analyze-SwydoReport.ps1` | the gap emitter, `meta`, header comment |
| `skill/SKILL.md` | Mode B schemaVersion gate (P1 miss) + analyst brief |
| `skill/report-template.md` | the matrix is never quotable |
| `SKILL_BUILD_SPEC.md`, `SWYDO_REPORT_EXTRACTION_SPEC.md` | schemaVersion contract (P1 miss) |
| `Test-Analyze.ps1` | flip-set assertions + the two counterexample fixtures |

### Alternatives rejected

- **Repointing the value rules anyway, for symmetry.** Symmetry is not a reason to change a
  force-surfaced rule.
- **Indexing the matrix in the closer "for completeness".** Measurably weakens the guard for zero gain.
- **Shipping S30/S31's forcing machinery unused.** Dead code in the publish gate.
- **Retiring `GAP_NO_ACCOUNT_TOTAL` and letting the matrix speak for itself.** It is the regression
  detector for this feature and it is what forces the disclosure into the report at all.

## 5. Production-readiness checklist

- security — no new I/O, no new string source beyond reason tokens the tool itself mints.
- perf / scale — one extra pass over the matrix per provider.
- a11y — N/A — no UI.
- i18n — reason tokens are fixed ASCII identifiers, not prose.
- error / empty / loading states — a platform whose every metric has a value emits no gap, as today.
- observability — the report can finally say WHY a number is absent instead of guessing.
- risks — the only default-output change in the program. Bounded by D4 and proven by the flip set.
- testing + left-shift gates — flip-set assertions plus a pin that the closer's candidate count is
  UNCHANGED, so a future "index the matrix" edit cannot land silently.
- migration / rollback — one `--no-ff` merge to revert; `canonicalVersion` self-describes.
- user docs — `skill/SKILL.md`.

## 6. Acceptance criteria

- AC1. `GAP_NO_ACCOUNT_TOTAL` lists exactly the metrics whose matrix cell carries a `reason`, and on
  the live report that is the same three metrics it listed before.
- AC2. Its statement reports counts by reason token, and on the live report says `no-usable-cell`
  rather than the old no-total-row guess.
- AC3. `evidence.byReason` is a FLAT STRING, per U10 D5.
- AC4. Its severity is still `info`, its cardinality still one per provider, its cap still 20.
- AC5. `meta.canonicalVersion` is 3 and `meta.matrixVersion` is 1.
- AC6. The FLIP SET: on the live report, the ONLY differences between P4 facts and P5 facts are the
  gap statement, the new `byReason` key, `canonicalVersion` and `matrixVersion`. Every headline cell,
  every matrix cell, every other finding and every breakdown is byte-identical. Asserted by a
  diff-count test, not by inspection.
- AC7. The closer's per-platform candidate count is UNCHANGED from P4, proving the fabrication guard
  was not diluted.
- AC8. `Test-Closer` stays green with its count unchanged, proving no publish verdict moved.
- AC9. `bash tools/run-gates.sh` green.

## 7. Gates

`bash tools/run-gates.sh` — the whole standing bar.

## 8. Open questions

none — the scope cuts in §3 are ratified in D1 and D2 against a measurement, not a preference.

## 9. Revision log

- rev-1 · 2026-08-05 · initial sub-spec derived from ANLZ-aUniformLattice-1 P5 (S27-S33), with S29,
  S30, S31 and S32 CUT after P6 closed WONTDO.
- rev-2 · 2026-08-05 · folded adversarial review wf_31f12c1f-2bc (2 lenses, 4 batched skeptics, 6
  agents; 16 raw findings, 11 survived, 6 must-fix). The review DISPROVED rev-1's D1 in both
  directions with reproduced fixtures, so S1 no longer repoints the gap's membership: the matrix
  refuses hidden-section widgets the headline accepts, and the two attribute providers differently, so
  repointing would both invent a gap for a published metric and delete a correct warning. Membership
  stays headline-keyed and the matrix supplies only the reason. D2's justification was replaced (the
  closer is dark because it fails CLOSED, not because the matrix is redundant), and since a
  matrix-only display string CAN exist, the template now says the matrix is never quotable. The cuts
  of S30 and S31 stand and were confirmed correct. Review also caught a landed P1 miss: `SKILL.md:31`
  still gated on `schemaVersion == 2`, which would have made the model refuse the v3 files P1 writes.

## 10. Reuse audit

None — codebase-map is not adopted; audit by reading source. P5 wires through the existing
`GAP_NO_ACCOUNT_TOTAL` emitter rather than adding a finding, keeps U6 D11's shape, severity and cap,
and reuses the matrix P3 already emits as its input. No new function, no closer change, no template
change.
