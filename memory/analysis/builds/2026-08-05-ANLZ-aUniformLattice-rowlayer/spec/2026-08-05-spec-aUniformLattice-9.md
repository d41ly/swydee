# ANLZ-aUniformLattice-9 — the row layer answers to the computed platform total

**Status:** CLOSED · rev-3 · 2026-08-05 · node a · Tier-2 · base 6213a239

The uniform per-platform view shipped in `platforms[].metrics` (P1-P5). The headline-driven rules
read it. The ROW-level rules never got repointed and still reason inside one widget at a time, so a
share is a share of whatever that widget happened to total.

## 1. Goal

Every row-level finding is attributable to the canonical per-platform total, or explicitly discloses
that its denominator is not that total. Two same-labelled findings are distinguishable without
opening the extraction.

## 2. Scope (IN)

`Get-BreakdownFindings` in `skill/scripts/Analyze-SwydoReport.ps1`, which emits SEVEN rule ids, not
the four an earlier revision claimed. Applicability differs per rule and is pinned here:

| rule | D1 dimension | D2 scope | D3 full row label |
|---|---|---|---|
| `ANOM_CONCENTRATION` | yes | yes (`$primary`) | yes |
| `ANOM_NEW` | yes | yes (`$primary`) | yes |
| `ANOM_PAUSED` | yes | yes (`$primary`) | yes |
| `ANOM_SEGMENT_DIVERGENCE` | yes | yes (`$primary`) | yes |
| `ANOM_EFFORT_NO_RESULT` | yes | yes (`$em`, the EFFORT metric, since the disclosed share is the effort share) | yes |
| `ANOM_SHARE_MISMATCH` | yes | effort denominator only, stated as such | yes |
| `ANOM_BRAND_BASELINE` | yes | yes (`$primary`) | **no** — it aggregates `$bm`/`$bsum` across many rows (:346-367) and has no single row |

Three changes, D1 / D2 / D3. There is no D4 — see §3.

## 3. Non-goals (OUT)

**No dedup rung.** An earlier revision proposed collapsing exact collisions. Review killed it, and
the reasoning is worth keeping: the single measured "collision" (`Facebook Ads: 'audience_network'
used 6% of Impressions (3,668) with 0 Leads`, emitted twice) comes from a 1-dimension
`Publisher platform` widget and a 2-dimension `Publisher platform / Placement` widget. D1 and D3
make that pair non-identical, and this section's own rule against merging different cuts forbids
collapsing it anyway. Post-change the two read as two disclosed facts about two cuts, which is what
they are. The two `finding:` anchors on that bullet in the delivered report are therefore correct,
not a defect.

NOT recomputing any row VALUE — every number still traces; only labelling and denominator
disclosure change. NOT touching the headline layer, the matrix build, the closer, or the extractor.
NOT changing `Row-Label` (see D3). NOT changing `report-template.md`.

## 4. Design

**D1 — dimension-qualified identity.** Each finding gains `dimension` (the widget's dimension list
joined with ` / `) and `metricId` (the metric its share is computed on, resolved per the §2 table).
The statement becomes `<Platform> by <dimension>: '<row>' is N% of <metric> (<v> of <total>)`.

**D2 — scope disclosure against the matrix, THREE rungs, over-scope tested FIRST.** Look the
canonical cell up by the METRIC's provider, not the widget's — `Get-MetricProviderId` exists for
exactly this distinction and the two disagree on mixed-prefix widgets. Let
`r = widgetTotal / canonicalTotal`, `P = [math]::Round($r*100,0)`:

1. No canonical cell, a canonical total of zero, or a basis mismatch (`Test-SameBasis` on
   unit+currency, same argument order as :850) -> `scope.canonicalTotal = $null`, statement
   unchanged. An undisclosed denominator beats a fabricated one.
2. `r > $ScopeOverPct` (1.05) -> OVER-SCOPE: append
   ` - against a widget total [math]::Round($r,1)x the account <metric>`.
3. `r >= $ScopeFullPct` (0.95) -> full scope, statement unchanged by D2.
4. otherwise -> SUB-SCOPE: append ` - within a P% subset of <Platform> <metric>`.

`scope = [ordered]@{ widgetTotal; canonicalTotal; sharePct = P }` on every rung, and `sharePct`
carries the SAME integer the clause renders so field and prose can never disagree.

Rung 2 exists because the live data contains `r = 4.37`: widget `26KA5eR4tZNeGTLQW` reports a Conv.
total of 1,034.0 against a canonical 236.71, and a two-rung ladder stamps that FULL SCOPE — blessing
the largest denominator contradiction in the report with a rule that claims to have checked it.

Rung 4 is the motivating case: `Google Ads: 'CONTENT' is 100% of Impressions (617 of 617)` against a
canonical 18,321 (r = 0.034) reads as "Google is all Display" today, and will read
`... - within a 3% subset of Google Ads Impressions`.

**D3 — full row labels, WITHOUT touching `Row-Label`.** `Row-Label` has 21 call sites across six
passes, including the group-row filter, `Get-Breakdown`'s published `rows[].label`, both time-series
sort keys, and `Get-DetailSumFindings`. Changing it in place would flip published breakdown labels
and silently alter which rows survive filtering — an unmarked flip far outside this unit.

Add `Row-LabelFull($row)` used ONLY for statement text. It takes the ordered dimension values, drops
any that is `$null`, whitespace-empty, or satisfies the shipped `Test-GroupRow` sentinel test
(`(group)` / `All`, :130), joins survivors with ` / `, and falls back to `Row-Label`'s own output
when nothing survives — so a label is never empty and the internal sentinels never reach a client.
Filter AFTER `@()`-wrapping the property walk, because `@($null).Count` is 1.

**The force-include coupling, which a naive emitter-only helper breaks.** `:1401-1402` harvests
quoted labels out of finding statements with `[regex]::Matches($fnd.statement, "'([^']+)'")` and
`:475` compares them against `$mustLabels -contains $lbl` where `$lbl = Row-Label $r`. Joined labels
on one side and first-dimension labels on the other silently stops force-including the very rows the
findings name. So `Get-Breakdown`'s comparison must match on EITHER form: `:475` tests
`$mustLabels -contains (Row-Label $r) -or $mustLabels -contains (Row-LabelFull $r)`. AC7 pins it.

**Statement text is pure ASCII.** No `x` glyph, no em dash: the joiner is ` / ` and the clause
separator is ` - `, matching the shipped style at :366-368. `skill/scripts/*.ps1` are BOM-less and
contain zero bytes above 127; `ps-hygiene.py` fires on BOM-less non-ASCII, and adding a BOM is not
an option because PS 5.1 reads UTF-8-no-BOM as CP1252 and the toolchain depends on the current shape.

**Config.** `[double]$ScopeFullPct = 0.95` and `[double]$ScopeOverPct = 1.05` join the `param()`
block at :19-27 beside `$WinLossPct`, `$SmallN` and `$BrandSharePct` — that is where the analyzer's
tunable thresholds actually live. An earlier revision said `$script:RuleCfg`, which is a
category-keyed map and holds none of them.

**Version markers.** `factsVersion` 3 -> 4 (additive `dimension`, `metricId`, `scope`).
`canonicalVersion` stays 4, `matrixVersion` stays 2 — no canonical value and no matrix cell moves.
This is the SIXTH disclosed change and needs its MEASURED flip set in the kickoff manifest in the
landing commit, which must also re-arm the trailing placeholder for a seventh so the ratchet does
not stall.

## 5. Production-readiness checklist

- **Security:** none — no new I/O, network, or credential path.
- **Perf:** one hashtable lookup per row finding against an already-built structure. Negligible.
- **Error/empty states:** the four handled cases are no canonical cell, a zero canonical total, a
  basis mismatch, and an all-sentinel row label — each with a named fallback in D2/D3.
- **Observability:** the disclosure IS the observability; a denominator mismatch that was invisible
  becomes a clause in the delivered artifact.
- **Testing:** §6, one fixture per rung.
- **Migration/rollback:** additive fields plus a statement-text flip; clean single-commit revert.
- **Docs:** `skill/SKILL.md` gains (a) `dimension`, `metricId` and `scope` classified against its
  existing read/skip list, and (b) a hard rule that a row finding's scope clause must not be
  stripped when the statement moves into prose. AC10 pins it.
- **a11y / i18n:** N/A — JSON producer, English-only report surface.

## 6. Acceptance criteria

1. A 2-dimension fixture's finding statement carries both dimension values joined with ` / `, and
   `Get-Breakdown`'s published `rows[].label` for that same row is UNCHANGED.
2. A row whose second dimension is `(group)`, `All`, null or blank yields a label with no dangling
   separator and no sentinel text.
3. `r = 0.034` fixture: the sub-scope clause fires, `scope.sharePct = 3`, and the clause renders the
   same 3.
4. `r = 4.37` fixture: the over-scope clause fires with `4.4x`, and does NOT take the full-scope path.
5. `r = 0.97` fixture: no clause.
6. No canonical cell, canonical total zero, and a unit/currency basis mismatch each yield
   `scope.canonicalTotal = $null` with an unmodified statement, and no divide-by-zero.
7. A 2-dimension finding still force-includes its row into the published breakdown — the `:475`
   either-form match.
8. Every finding from the seven §2 rules carries a non-empty `dimension`; `ANOM_BRAND_BASELINE`
   carries `dimension` but no `Row-LabelFull`-derived label.
9. `meta.factsVersion` is 4; `canonicalVersion` 4, `matrixVersion` 2.
10. `skill/SKILL.md` classifies the three new fields and states the scope-clause rule.
11. Live QCU re-run: the CONTENT finding carries ` - within a 3% subset`, the Campaign/Network Conv.
    finding carries the over-scope clause, and the two `audience_network` findings are
    distinguishable by their `dimension`.

## 7. Gates

Full bar. `Test-Analyze.ps1` is the owning suite and is additive; the other seven counts stay
unchanged. Note that `Test-Analyze.ps1:960` (`bb12.statement -match "PMax - One"`) reads
`ANOM_BRAND_BASELINE` statement text and is an EDIT under D1 rather than a deletion — the
green-count contract survives because no assertion is removed.

## 8. Open questions

none - both were resolved by building and measuring. Recorded because the reasoning still binds:

- `$ScopeFullPct = 0.95` is a judgement, and the live run CONFIRMED the noise it predicted: The live distribution is NOT the clean gap an earlier
  revision asserted: measured r values are 0.034, 0.68, 0.80, 0.91, ~1.0 and 4.37, so three real
  findings sit between the rungs and WILL gain a sub-scope clause. That is arguably correct — a
  keyword widget covering 68% of account impressions genuinely is a subset — but it means the change
  is noisier than "fix the 617 case". Measured on the live report: 4 sub-scope and 1 over-scope
  disclosure across 34 changed statements, which is proportionate. RESOLVED: keep 0.95, revisit only
  if a real widget lands mid-range and the clause reads as noise rather than as information.
- Placement of the clause in the statement rather than in `evidence` is a PROSE call, not an
  enforcement one. The closer treats statement and evidence identically (`Test-ReportNumbers.ps1:251`
  buckets both by fid) and its surfacing gate (:425) matches only the fid anchor, never statement
  text. So putting it in the statement buys visibility to a human report writer and nothing
  mechanical. An earlier revision claimed the closer made it hard to drop; that was wrong. RESOLVED:
  the clause stays in the statement, because a human report writer is the reader who needs it and the
  statement is what they copy from.

## 9. Revision log

- rev-1 · 2026-08-05 · initial spec, with a D4 dedup rung and a two-rung D2.
- rev-3 · 2026-08-05 · BUILT and landed. Measured flip set on the live QCU report: 34 of 78
  finding statements changed (ANOM_NEW 13, ANOM_CONCENTRATION 11, ANOM_SEGMENT_DIVERGENCE 8,
  ANOM_EFFORT_NO_RESULT 2), 4 sub-scope and 1 over-scope disclosure added, finding count unchanged
  at 78, and 0 headline cells changed. AC6 moved to resolver unit tests: with only the breakdown
  widget in a document the matrix correctly derives the account total FROM that widget, so an e2e
  fixture cannot manufacture a missing cell. Test-Analyze 709 -> 731.
- rev-2 · 2026-08-05 · adversarial review, 46 standing findings. D4 DELETED (its only measured
  collision is a cross-cut pair the spec's own non-goal protects). D2 gained the over-scope rung
  (live `r = 4.37` was being certified full-scope), a basis check, and a pinned rounding rule. D3
  stopped mutating `Row-Label` (21 call sites) in favour of `Row-LabelFull`, plus sentinel filtering
  and the `:475` force-include either-form match. Scope corrected from four rules to seven with
  per-rule applicability. Threshold home corrected from `$script:RuleCfg` to the `param()` block.
  Canonical lookup corrected to `Get-MetricProviderId`. Statement glyphs forced to ASCII. Grounding
  line corrected: 35 anomalies from 17 distinct widgets collapsed into 11 dimension-name labels, not
  "12 widgets".

## 10. Reuse audit

No new file, no new module, no second implementation. `Get-MatrixContributions` / `Reduce-MatrixCell`
already populate `platforms[].metrics` and D2 only READS it — the point of the unit, since the matrix
is today read at exactly one site (:1233) for a coverage-warning string. `Get-MetricProviderId`
(existing) resolves the canonical lookup. `Test-SameBasis` (existing, used at :850) supplies D2's
rung 1 guard. `Test-GroupRow` (:130) supplies D3's sentinel test. `Row-Label` is WRAPPED, not
modified. The `param()` block at :19-27 is the existing home for tunable thresholds.

Correction to rev-1's reuse claim: `Get-RowKey` is NOT reusable here. It is defined only in
`skill/scripts/Get-SwydoReport.ps1:383`, which the analyzer neither dot-sources nor is allowed to
touch (§3), and it embeds the row ordinal, making it position-dependent. With D4 deleted no
cross-widget row identity is needed at all, so nothing replaces it.
