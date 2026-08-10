# ANLZ-aUniformLattice-3 — P2: declared aggregation semantics and one shared basis hash

**Status:** SPECCED · rev-2 · 2026-08-05 · node a · Tier-2 · base 34b83967 · parent ANLZ-aUniformLattice-1 · review wf_3019ebea-7ed

## 1. Goal

Give every metric a single declared aggregation class and every cell a single declared basis, so P3's
reduce reads one answer instead of re-deriving it from three predicates that deliberately disagree.
Pure functions only; nothing calls them yet.

## 2. Scope (IN)

- S1. `Get-AggregationClass($metricId, $unit)` returning exactly one of `sum`, `ratio-recompute`,
  `dedup-nonsummable`, `account-asis`, `unknown`. It COMPOSES the shipped predicates and adds no new
  regex table.
- S2. `Get-BasisVersion` becomes single-source. It moves into `Analyze-SwydoReport.ps1` and the copy
  in `Update-SwydoLedger.ps1` is deleted, keeping its shipped three-argument signature and its exact
  output.
- S3. `Get-CellBasis($metricId, $unit, $currencyCode)` returning
  `[ordered]@{ unit; currencyCode; basisVersion }`, the shape a P3 cell carries.
- S4. `Test-Additive` and `Test-Summable` are NOT touched and NOT unified.
- S5. Four VETO terms, each lifted from a shipped predicate with its citation, run before the ladder.
  They exist because the shipped predicates match on substrings and disagree at their edges.

## 3. Non-goals (OUT)

- No caller. P2 defines the functions; P3 is the first consumer. Nothing in the emitted facts changes.
- No new metric-classification AUTHORITY. Every branch either delegates to a shipped predicate or
  applies a veto term copied verbatim from one, with the source cited inline. Review established that
  a pure-delegation ladder is not achievable: the shipped predicates match substrings and contradict
  each other at the edges, so the vetoes are the correction, not a new opinion.
- No change to `Update-SwydoLedger.ps1`'s ledger keys or output. Only the duplicate definition goes.
- No rank-3 semantics. P6 is WONTDO per the master spec rev-4.

## 4. Design

### Data model

**D1 — the class ladder, evaluated in this order.** Order matters because the shipped predicates
overlap; the first match wins and each branch names the predicate that decides it.

| Order | Class | Decided by | Meaning for the reduce |
|---|---|---|---|
| V1 | `account-asis` | metric part matches `(^|_)target` | a bid SETTING, not a measurement |
| R1 | `ratio-recompute` | `Get-RatioSpec $id` is non-null | derivable from two component cells |
| V2 | `account-asis` | metric part matches `per[_a-z]` | a per-X average R1 could not name |
| V3 | `account-asis` | metric part matches `return_on_ad_spend` | a ratio the recompute spec cannot name |
| R2 | `dedup-nonsummable` | metric part matches `reach|frequency|unique|users?$` | adding it double-counts people |
| R3 | `account-asis` | `Metric-Type $id $unit $null` is `percent` or `ratio` | a reported rate or ratio; take it as given |
| R4 | `sum` | `Test-Summable $id` | may be added across partition rows |
| R5 | `unknown` | nothing matched | no class; the reduce still ranks it normally |

Every term above is copied from a shipped predicate, and each one exists because review MEASURED the
naive ladder getting a real id wrong.

**V1** is the target guard. `google-adwords:target_roas` and `target_cpa` both satisfy
`Get-RatioSpec`, so a bare rule-1-first ladder would class a bid setting as a derivable measurement
and publish `conversions_value / cost` in a cell labelled Target ROAS. The codebase already ships the
opposite verdict: `Test-ValueMetricId` at `Analyze-SwydoReport.ps1:132-137` puts `(?i)(^|_)target`
FIRST under the comment that a `target_roas` is a bid SETTING, not measured value, and
`Test-Analyze.ps1:799-800` pins both FALSE. V1 reuses that guard's shape.

**V2** is `Test-Summable`'s OWN first guard, at `Analyze-SwydoReport.ps1:479`. It has to run here too,
because R2 copies four alternatives out of the middle of the same denylist and would otherwise class
`value_per_conversion` or `screenPageViewsPerSession` as a deduplicated count.

**V2 runs AFTER R1, not before.** `cost_per_conversion` and `cost_per_lead` both contain `per_` while
being exactly the ratios `Get-RatioSpec` can recompute, so a veto-first order demotes a derivable
ratio to as-reported. Measured during the build: the veto-first ladder classed `cost_per_conversion`
as `account-asis`, and the acceptance test caught it.

**V3** exists because `Test-Summable`'s allowlist matches on SUBSTRINGS.
`bing-ads:return_on_ad_spend` contains `spend`, so it returns `$true`; its denylist carries only the
bare token `roas`, and `Get-RatioSpec`'s roas branch tests bare `roas` too, so both miss the
spelled-out spelling. Measured under PowerShell 5.1: the naive ladder classes it `sum`. The id is
real and in the shipped corpus at `Test-ValueMetricId`'s regex (`:137`) and `Test-Analyze.ps1:798`.

**R1 before R4** is deliberate. `Get-RatioSpec` is role-qualified and component-aware, and U7 R20
records that a blanket mapping produced false findings; where the two could disagree, the specific
one wins.

**R3 delegates rather than inventing a family.** `Metric-Type` is the shipped, unit-aware classifier,
and it is the only reason `$unit` is in the signature: a `fraction` unit resolves to `percent` at
`Analyze-SwydoReport.ps1:78`. Measured: `search_lost_is_budget` with unit `fraction` yields `percent`,
and `search_impression_share` likewise, so both land in `account-asis` without a new regex.

**R5 `unknown` is metadata, not a veto.** `aggClass` never decides whether a cell has a value; RANK
does, per the parent's structure-only reduce. An `unknown` cell still ranks and can still carry a
measured KPI value. The class only tells the template how to word it.

**D2 — `Get-BasisVersion` moves, it is not copied.** `Update-SwydoLedger.ps1:36` already dot-sources
`Analyze-SwydoReport.ps1`, so moving the definition upstream gives the ledger the same function for
free and leaves exactly one copy. U6's deferred-work contract names a single shared define-only
helper as a precondition for bringing `basisVersion` into report facts, so a second copy would fail
that precondition before P3 even starts.

The output must not change: `Test-Ledger.ps1:12` builds its ledger keys with it, so any drift in the
hash silently re-keys every ledger cell. The function moves verbatim, including its `[char]0x1F`
separator and its 12-character truncation.

**D3 — `Get-CellBasis` is a shape, not a decision.** It returns the tuple a cell carries and delegates
the hash to `Get-BasisVersion`. It exists so P3 has one place to construct a basis and one place to
compare two.

### Inventory

Composed predicates, all shipped and all unchanged:

| Predicate | Site | Role in P2 |
|---|---|---|
| `Get-RatioSpec` | `Analyze-SwydoReport.ps1:495-515` | decides `ratio-recompute` (R1) |
| `Test-Summable` | `:477-483` | decides `sum` (R4) |
| `Test-Summable`'s per-X guard | `:479` | source of V2 |
| `Test-Summable`'s denylist | `:480` | source of R2's four terms |
| `Test-ValueMetricId` | `:132-137` | source of V1 and V3 |
| `Metric-Type` | `:76-82` | decides R3, and the only reader of `$unit` |
| `Get-MetricPart` | `:51` | normalizes the id for every veto |
| `Get-BasisVersion` | `Update-SwydoLedger.ps1:42-51` | moves to the analyzer |

All three new functions are defined in the pure-helpers region ABOVE
`Analyze-SwydoReport.ps1:673` (`if($DefineOnly){ return }`). A definition below that line is invisible
to every `-DefineOnly` dot-source, which is how the ledger and four suites load the file.

### Migration

None. No emitted key changes and no consumer exists yet. `Update-SwydoLedger.ps1` keeps working
because it already dot-sources the analyzer.

### Rollout

Dark, and provably so: the only observable change is that a function is defined in a different file.

### Files touched (estimate)

| File | Nature |
|---|---|
| `skill/scripts/Analyze-SwydoReport.ps1` | three pure functions added, one of them moved in |
| `skill/scripts/Update-SwydoLedger.ps1` | duplicate definition deleted |
| `Test-Analyze.ps1` | class-ladder and basis assertions |
| `Test-Ledger.ps1` | proof the ledger still gets the same hash |

### Alternatives rejected

- **Unifying `Test-Additive` and `Test-Summable`.** U7 R4 pins their divergence with a regression
  test precisely so a tidy-up cannot silently flip calibration.
- **Copying `Get-BasisVersion` into the analyzer.** Two copies of a hash that keys ledger cells is
  exactly the drift U6's contract forbids.
- **A single new regex table for the class.** It would become a third authority disagreeing with the
  two that already exist. The vetoes are not that: each is a term copied from a shipped predicate to
  correct a measured misclassification, cited at its use site.
- **U6:257's standalone param-only helper file for the basis hash.** Superseded here. The analyzer is
  a better home because no new file is needed, `Update-SwydoLedger.ps1:36` already dot-sources it, and
  the ledger already absorbs the analyzer's param block. The single-definition requirement U6 was
  protecting is met more directly, and AC5 now enforces it mechanically.
- **Deciding `sum` before `ratio-recompute`.** The narrower, role-qualified predicate must win.

## 5. Production-readiness checklist

- security — N/A — pure string classification, no I/O, no credential path.
- perf / scale — O(1) per metric, regex only.
- a11y — N/A — no UI.
- i18n — the classes key on provider metric IDs, never on display labels.
- error / empty / loading states — a null or unmatched id yields `unknown`, never a throw.
- observability — the class lands on every P3 cell, so a mis-class is visible in facts.
- risks — the only real risk is `Get-BasisVersion` drifting during the move; AC5 pins its output
  against literal expected hashes rather than against itself.
- testing + left-shift gates — see §6, additive on `Test-Analyze` and `Test-Ledger`.
- migration / rollback — a revert restores the duplicate; nothing persists.
- user docs — none; no user-facing surface changes.

## 6. Acceptance criteria

- AC1. `Get-AggregationClass 'google-adwords:clicks' $null` is `sum`; `'google-adwords:cost_micros'
  'micros'` is `sum`.
- AC2. `Get-AggregationClass 'google-adwords:ctr' 'fraction'` is `ratio-recompute`, and so is
  `'google-adwords:average_cpc' 'micros'`.
- AC3. `Get-AggregationClass 'facebook-ads:reach' $null` and `'ga4:activeUsers' $null` are
  `dedup-nonsummable`, NOT `unknown`.
- AC4. `'google-adwords:search_impression_share' 'fraction'` and
  `'google-adwords:search_lost_is_budget' 'fraction'` are `account-asis`;
  `'x:some_unknown_metric' $null` is `unknown`; `$null $null` is `unknown` and does not throw.
- AC4b. THE VETOES, each pinned against the misclassification review measured:
  `'google-adwords:target_roas' $null` and `'google-adwords:target_cpa' $null` are `account-asis`,
  NOT `ratio-recompute`. `'bing-ads:return_on_ad_spend' $null` is `account-asis`, NOT `sum`.
  `'x:value_per_conversion' $null` and `'ga4:screenPageViewsPerSession' $null` are `account-asis`,
  NOT `dedup-nonsummable` and NOT `sum`.
- AC4c. Every id in the shipped `Test-Summable` corpus at `Test-Analyze.ps1` and every id in the
  `Unit-Of` table at `Test-Extractor.ps1` resolves to a class without throwing, and R2's four terms
  are a strict subset of `Test-Summable`'s denylist, so an edit to that denylist cannot desync the
  copy silently.
- AC5. `Get-BasisVersion` returns these exact hashes, captured from the PRE-MOVE definition and
  committed as literals so the test cannot compare the function against itself:
  `('g:cost','micros','USD')` is `840fe173e2ff`; `('g:clicks',$null,$null)` is `38651fdc0b49`;
  `('g:cost','micros','EUR')` is `d26f76203c7f`; `('x:y',$null,'USD')` is `9aa1c4d052bd`.
- AC5b. The single-definition rule is MECHANICAL, asserted in `Test-Ledger` because that suite loads
  both files: `(Get-Command Get-BasisVersion).ScriptBlock.File` ends in `Analyze-SwydoReport.ps1`.
  This also fails loudly if the definition is placed below the `-DefineOnly` return.
- AC6. `Update-SwydoLedger.ps1` still produces identical ledger keys, proven by `Test-Ledger`
  staying green with its existing `K()` helper unchanged.
- AC7. `Get-CellBasis 'google-adwords:cost_micros' 'micros' 'USD'` carries `unit`, `currencyCode` and
  a `basisVersion` equal to `Get-BasisVersion` on the same inputs; a null unit and null currency
  still produce a stable hash.
- AC8. Two metrics differing ONLY in currency produce different `basisVersion` values.
- AC9. `bash tools/run-gates.sh` green; `Test-Analyze` and `Test-Ledger` additive on their own
  counts, the other six suites unchanged.

## 7. Gates

`bash tools/run-gates.sh` — the whole standing bar.

## 8. Open questions

none — the veto set and the ladder ordering are ratified in §4 D1, each term against a measured
misclassification.

## 9. Revision log

- rev-1 · 2026-08-05 · initial sub-spec derived from ANLZ-aUniformLattice-1 P2 (S15-S17), renumbered
  locally as S1-S4.
- rev-2 · 2026-08-05 · folded adversarial review wf_3019ebea-7ed (2 lenses, 4 batched skeptics, 6
  agents; 16 raw findings, 14 survived, 2 must-fix). The naive ladder was measured misclassifying four
  real ids, so four cited vetoes now run first: `target_*` are bid settings that `Get-RatioSpec`
  wrongly claims; `return_on_ad_spend` passes `Test-Summable` on the `spend` substring; the per-X
  family had no class at all and R2 would have called it a dedup count. Rule 4's undefined
  rate/share/position family now delegates to `Metric-Type`, which is also what makes `$unit`
  load-bearing instead of dead. `unknown` is metadata only — rank decides whether a cell has a value,
  not the class. AC5 gained literal pre-move hash pins so it cannot compare the function against
  itself, and AC5b makes the single-definition rule mechanical. All citations re-derived against
  34b8396 (they were four lines stale).

## 10. Reuse audit

None — codebase-map is not adopted; the audit was done by reading source. Every branch of the class
ladder delegates to a shipped predicate rather than restating it: `Get-RatioSpec`
(`Analyze-SwydoReport.ps1:495-515`), `Test-Summable` (`:477-483`), `Metric-Type` (`:76-82`),
`Get-MetricPart` (`:51`). R2's dedup terms are lifted verbatim from `Test-Summable`'s own denylist at
`:480`, V2 from its per-X guard at `:479`, and V1 and V3 from `Test-ValueMetricId` at `:132-137`.
`Get-BasisVersion` is MOVED from `Update-SwydoLedger.ps1:42-51` rather than reimplemented, and the
ledger reaches it through the dot-source it already performs at `:36`. No new file is created and no
predicate is duplicated.
