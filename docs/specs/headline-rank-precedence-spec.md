# U9 - Headline rank precedence (promote deferred D4) (spec v1)

## AMENDMENTS v1 (post adversarial review, 2026-07-12 — these OVERRIDE the body below)

Review verdict: **GO-WITH-CHANGES** (correctness GO-WITH-CHANGES - discipline GO-WITH-CHANGES - fatigue GO-WITH-CHANGES).

- **Correctness must-fix (the D4/FP-1(b)/E9 "#5 fires independently" safety-net claim is FALSE in general — rewrite it, and rule reviewer Q2/Q6 explicitly):** `RECON_SLICE_OVER_ACCOUNT` is gated on `Test-Summable` (A:530), `Test-SameBasis` (A:546), non-null values, and the ambiguous-ceiling skip (A:543-544). Four shipped fixture shapes refute the body's claim that #5 fires "when the displaced total actually exceeds the KPI": **u5c** (T:493-497, EUR table 120 vs USD KPI 100 — SameBasis false), **u5d** (T:498-502, null-unit KPI), **u5e** (T:503-507, CTR ratio — not summable), **u5h** (T:510-515, two differing KPIs — ambiguous ceiling). In all four, U9 displaces the doc-earlier table total AND the displaced VALUE appears nowhere in the emitted facts (`Get-Breakdown` emits only `kind=='data'` rows, A:269-270 — never the total row). The D4 rationale, FP-1(b), and E9 must be rewritten to enumerate these gate-failure shapes and state plainly that in them the displaced number is unrecoverable from facts. **Rulings folded in:** (Q6) id-only disclosure STANDS — all three lenses concur that echoing the displaced display string would mint a new traceable-number surface for a figure the unit deliberately unheadlines, and the exceeds direction where the reader wants both numbers is carried by #5 whenever its gates pass; the four silent shapes are an **accepted, now-honestly-documented residual**. (Q2) the ambiguity gate is DECLINED — for the u5h shape (a rank-1 candidate #5 itself refuses as ambiguous still deterministically wins the headline), `DISC_CROSS_WIDGET` fires major on the disagreeing KPI pair (U9-T15), which is the correct disclosure; the spec text must note that this argument does NOT extend to the u5c cross-basis shape (table dimSig `'campaign'` vs KPI dimSig `''` never share a dimSig, so `DISC_CROSS_WIDGET` cannot fire either — a EUR-120 vs USD-100 disagreement is disclosed by nothing numeric, only the id-only precedence finding). Say so in FP-1.
- **Correctness must-fix (QCU evidence prose is factually wrong in two places — re-verified against the archived facts during this fold):** (a) the claim that `search_impression_share` appears "in no early breakdown widget" is false — "Search impression share" is a column of Google breakdowns #2 (Device) and #7 (Network); the scorecards-first conclusion holds only via `search_lost_is_budget` (headline position 3, present in NO breakdown widget) plus the contiguity argument (a winning widget's metrics land contiguously in headline key order, so Device cannot have supplied positions 1-2 with position 3 absent from it). (b) The claim that `frequency` and `pageEngagementActions` are "both present on the Campaign table" is false — Frequency is on the Campaign and Platform tables; "Actions" (`pageEngagementActions`) is on the Month, Age/Gender, and Day-of-week tables, NOT Campaign. Correct both sentences; all conclusions survive unchanged.
- **Correctness must-fix (the "Audited non-flips" list omits three flip-layout fixtures):** the complete cross-rank flip-layout set in the shipped suite is SEVEN fixtures: e2e11 (T:318-321), u5a (T:481-484), **u5b (T:488-491)**, u5c (T:493-496), u5d (T:498-501), **u5e (T:503-506)**, **u5h (T:510-514)** — the body lists only u5a/u5c/u5d. The bottom-line claim is independently confirmed TRUE (u5b/u5e/u5h assert only negative `HasFind` checks on U7a rule ids and stay green under the new rule), but the audit list must be corrected so the green-count contract's audit is trustworthy. Also name in the audit two flip-behavior changes on existing fixtures: post-U9, u5d additionally emits `GAP_UNIT_UNCONFIRMED` (the null-unit KPI becomes the winner) and u5c's headline currency flips EUR -> USD; neither breaks an assertion, both are D8-intended winner-follows-facts behavior.
- **Discipline must-fix (cross-spec `canonicalVersion` pin conflict with U8):** the sibling U8 spec's D10 (`docs/specs/extractor-period-resolution-spec.md:122`, same-session, also post-review) ratifies "`canonicalVersion` stays 1", which U9/D6 contradicts; neither spec references the other and no build order is declared. Before build: U9 hereby amends U8/D10 to read "`canonicalVersion` unchanged BY U8" (U8 makes no claim about other units' bumps), and whichever unit ships SECOND must declare the U8/U9 build order in its units-index row. Note the mechanical consequence either way: if U8 builds first, U9's "exactly two in-place assertion updates" contract is unaffected (T:328 still asserts 1 until U9 lands); U8's builder must NOT derive any `canonicalVersion -eq 1` assertion from D10.
- **Discipline must-fix (U9-T2's full-file golden is not sustainable — replace it):** `Test-Analyze.ps1` has no golden-file infrastructure (the only precedent is one hardcoded display string, e2e20 T:371-372); a full-facts golden captured from pre-U9 `main` cannot be regenerated from the shipped tree and breaks on EVERY future additive unit (U8's meta/period fields, U10 findings). Replace U9-T2's "differs from a pre-U9 golden only in `canonicalVersion:2`" with targeted byte guards in house style: winner-cell assertions, `$r.text -notmatch 'supersededWidgetId'`, no precedence finding, `meta.canonicalVersion -eq 2`, plus e2e20-style pins on specific legacy substrings (e.g. `'"current":<n>,'` and the `displayCurrent` string) proving non-flip cells unchanged.
- **Discipline must-fix (null-check `$existing.canonical` in the displacement guard):** the headline `OrderedDictionary` also holds the boolean `hasComparison` key (A:636), and `[ordered]` is case-insensitive; pre-U9 a metric id colliding with that key was benign (bare `continue`), but sketch snippet 1 would evaluate `($true).canonical.source` -> `$null -ne 'kpi-widget'` -> `$true` and let an `$isKpi` candidate DISPLACE the boolean, corrupting `headline.hasComparison` and the D7 recompute. The guard becomes: `if(-not ($isKpi -and $existing.canonical -and ($existing.canonical.source -ne 'kpi-widget'))){ continue }` — any non-cell collision degrades to exact pre-U9 behavior. Pin with a small unit/e2e case.
- **Fatigue must-fix (D4 is mis-channeled and mis-prefixed — this RULES the spec's own open Q3):** a precedence flip is not a numbers-disagree event; everything in the discrepancies channel today asserts that numbers disagree (`DISC_CROSS_WIDGET` major A:738, value-vs-value RECON routing A:746-750), while the finding's true class is a sourcing/provenance note — exactly `GAP_NO_ACCOUNT_TOTAL`'s class (A:678-683, `$gaps`). Route the finding into **`$gaps`** and rename it **`GAP_HEADLINE_SOURCE_CHANGED`** (no `DISC_` prefix); keep `severity='info'`, the per-provider rollup, the 20-id cap, and the no-values rule exactly as specced. Fix the statement wording: drop "now comes from" (on a first-ever pull there is no "now" vs anything the reader saw) in favor of "comes from the account KPI card rather than the document-earlier table total <ids>". Update U9-T1/T8/T11's rule-id and channel assertions, the D4/blast-radius text, and sketch snippet 3 accordingly (mechanics identical: the pinned insertion point after A:683 has `$gaps` in scope and the fid pass A:769-771 covers it). *Conflict resolution: the discipline lens accepted the `DISC_` routing as a residual (info in `$disc` provably never force-surfaces, Test-ReportNumbers.ps1:420); the fatigue lens's channel-hygiene ruling wins — inflating the discrepancy count with our own algorithm choice on clean data is the mechanism by which readers learn to discount that channel, and discipline's own analysis confirms the reroute is mechanically free.*
- **Cross-cutting critic addition (canon byte-for-byte lines must carry the waiver note; apply in the U9 build commit):** the byte-for-byte rule is stated unconditionally in two still-authoritative canon lines U9's blast radius never touches — `docs/SESSION-KICKOFF.md` ("must stay byte-for-byte unchanged — every change is additive-in-facts") and `docs/specs/context-and-canon-spec.md:27` ("default single-report path stays byte-for-byte unchanged (additive meta fields only)"). The U9 build commit MUST add a one-line explicit-waiver note at both lines (e.g. "except the reviewed, disclosed U9 flip-set waiver — `headline-rank-precedence-spec.md` D1/D3"), and both docs join the blast-radius table (doc-only). The canon must not carry two contradictory authoritative statements after merge — the same standard U8's C6:5 supersession was held to.

**Residuals (documented, accepted):**
- **FP-1 stands as the load-bearing residual, with its sharpest instance named:** a single-campaign "spotlight" KPI card (a plausible agency layout) placed after an all-campaigns table displaces the genuinely account-wide total, and WIN/LOSS/ANOM_BUDGET_CONSTRAINED recompute from the spotlight figure (D8). Schema v2 cannot distinguish it (U6:243); the value-comparison gate stays rejected; the Q2 ambiguity gate would not catch a SINGLE spotlight candidate anyway (declined, YAGNI). Disclosed via D4/D5; the #5 value backstop covers only the exceeds-direction, summable, same-basis, unambiguous shapes (see must-fix 1).
- **Q1/D6 ruled IN as specced (all three lenses):** the global `canonicalVersion` 1 -> 2 is the version marker doing its one U6-D10 job; grep confirms nothing gates on `-eq 1` (writer A:786, assertion T:328 only). The freeze-at-1 fallback would make v1- and v2-winner facts indistinguishable across the dominant no-flip population — worse. See the U8 coordination must-fix.
- **Q4/D7 confirmed as specced:** the value-only `hasComparison` recompute is airtight (any true state implies a comparison-bearing write already created the key at A:636; `OrderedDictionary` indexer assignment is position-stable) and can only REMOVE the seasonality caveat on flip platforms — it strictly reduces caveat noise.
- **Q5 ruled: no live-extraction gate on the build.** The QCU bound is inference from key order, not observation (and a dimensioned widget with a total row but zero data rows is invisible in breakdowns, A:270); "no expected flip, any actual flip disclosed via D4/D5 + the D6 token" is an acceptable evidentiary standard. A non-gating fresh-pull smoke check after merge is recommended, not required; do NOT exercise the credentialed extraction path solely for review.
- **Measured live demand is zero:** every attributable QCU metric is already KPI-won, so U9's value is prospective (table-first layouts; plus shrinking U7b #6's future false-major surface per D12). Acceptable — the unit was explicitly invited by the U6 review (U6:330) and the blast is flip-gated.
- **u5d's new post-flip `GAP_UNIT_UNCONFIRMED` is a fixture-only shape:** `Unit-Of` (Get-SwydoReport.ps1:107-116) is a pure function of the metric id, so a same-`(provider,metricId)` unit differential between two widgets cannot occur in a live extraction. Keep U9-T10 as a robustness pin; the spec may note the shape is synthetic.
- **D1's `manualKpi` claim verified in code** (`kind='manualKpi'` only for source-less widgets, G:171-175); a `kind=='data'` widget carrying `manualKpiOptions` stays a candidate with measured rows — same residual U7:7 already accepted.
- **D3 blast enumeration, one sentence to add at build time:** a replacement cell write with a compare column can ADD the `headline.hasComparison` key at a position where pre-U9 it would have been added later or never, and the D7 recompute can leave it holding `$false` (a value never produced pre-U9) — both reachable only via displacement, inside the declared waiver.
- **Sketch idiom nits, non-blocking:** prefer `$null -ne $existing` over `if($existing)` (house-safe; the must-fix guard above already de-fangs the collision case); `Sort-Object -Unique` is case/culture-insensitive in PS 5.1 but ids are ASCII and the store is already case-insensitive — matches the `GAP_NO_ACCOUNT_TOTAL` precedent byte-for-byte.
- **Scope verified clean (Q7):** rank-3 synthesis stays deferred, ledger/closer untouched, D12 is a text-only design note for the still-deferred U7b; the test plan is heavy (15 cases for ~20 lines) but house-consistent and every case pins a named edge.

---

**Status:** SPEC (reviewed 2026-07-12, verdict GO-WITH-CHANGES). Extends `docs/specs/canonical-total-spec.md` (U6); same discipline (PS 5.1/.NET, pure-ASCII script source, functions-first + `-DefineOnly`, hardened scripts reused via dot-source and never behaviorally modified, every credential write path fail-closed, the model does no arithmetic) - **except** the default single-report byte-for-byte rule, which this unit deliberately and explicitly waives for the bounded flip set defined in D1/D3 below. The waiver is never silent: every changed winner is disclosed in the emitted facts (D4/D5).

**Mandate.** U6 shipped with winner selection deliberately unchanged: canonical-total-spec D4 (U6:67) declined the draft's rank rule ("prefer a true KPI over a doc-earlier table total") to keep the common path byte-identical, and the U6 reviewer section explicitly invited promoting it: *"Confirm this deferral is acceptable, or promote it to its own follow-up unit"* (U6:330). This unit is that follow-up. Scope is CLOSED per the ratified unit description: the winner-selection change in `Analyze-SwydoReport.ps1`, an explicit flip disclosure, new `Test-Analyze` cases, and a migration/restatement argument. **OUT:** rank-3 synthesis and its completeness-signal precondition (stays deferred per U6 D5, U6:68/248-257); ledger schema untouched; closer untouched.

**Line-citation shorthand used below:** `A:` = `skill/scripts/Analyze-SwydoReport.ps1`, `T:` = `Test-Analyze.ps1`, `L:` = `skill/scripts/Update-SwydoLedger.ps1`, `TF:` = `skill/scripts/ConvertTo-SwydoTrendFacts.ps1`, `AT:` = `skill/scripts/Analyze-SwydoTrend.ps1`, `U6:` = `docs/specs/canonical-total-spec.md`, `U7:` = `docs/specs/cross-widget-reconciliation-spec.md`. All line numbers verified against `main` at commit `cccd0c9` (2026-07-11).

---

## Measured baseline (evidence, not assumption)

- **Green board, measured 2026-07-11 on `main` (all exit 0):** Analyze **276**, Closer **119**, Extractor **94**, Archive **94**, TrendFacts **19**, Ledger **50**, TrendAnalyze **24**, Sync **4**. (The U6 spec's "Analyze 135" (U6:12) is the pre-U6 count; U6+U7a grew it to 276. This spec pins against the measured 276.)
- **Winner selection as shipped:** headline population walks `$dataWidgets` (`kind -eq 'data'`, A:575) in document order; blended widgets are skipped as a source (A:619); `Total-Row` returns a row only for an explicit total row or a zero-dim widget's first data row (A:141-150); the store key is `$m.id` and **first-wins** is the bare `continue` at A:632. Scope stamping already distinguishes the two ranks: `$isKpi` at A:624 yields `scope='account'` / `source='kpi-widget'`, otherwise `scope='table-total:<dim>'` / `source='total-row'` (A:625-626, A:645).
- **Assertions that pin today's winner:** exactly two Analyze assertions encode cross-rank doc-order or the algorithm version:
  - **e2e11** (T:317-322): a doc-earlier dimensioned total-row widget (`w-first`) beats a later zero-dim KPI (`w-second`) for the same `(prov,metricId)`. **This is THE assertion U9 flips**; it is updated in place (documented, not silent) and becomes the new-rank pin.
  - **e2e14** (T:327-328): `meta.canonicalVersion -eq 1` - updated to `2` per D6.
  - Audited non-flips: e2e10 (T:313-316, single table-total widget, no rank-1 rival), r18a (T:357-362, two KPIs = same rank, doc order unchanged), u5a/u5c/u5d (T:481-502, table-before-KPI fixtures whose assertions read only U7a's re-derived findings, never the headline winner), e2e16/e2e17 (gap/discovery paths, winner-independent), closer cases r22/u4a/u3j (single-widget fixtures). No other assertion among the 276 encodes the old cross-rank winner.
- **Archived QCU facts** (`skill/archive/quincy-credit-union/2026-07-06-19-45-59/QCU_Q2_2026_causal_report.facts.json`): **pre-U6** - `meta.canonicalVersion` is absent and no headline cell carries `canonical` (verified by parsing the file). The manifest lists only facts/report/draft (no raw extraction is ever archived - raw extractions carry the live share key), so the flip question cannot be settled by re-running Analyze on archived inputs. What the facts DO show (see "QCU empirical bound" below) is that both providers' first headline winners came from zero-dim scorecards, so **no flip is expected for any metric the archive can resolve**.

### QCU empirical bound (how far the archive answers the flip question)

A flip requires, for some `(provider, metricId)`: a document-earlier dimensioned total-row widget AND a later zero-dim KPI. The archived facts reveal document order two ways: `platforms[].headline` is an `[ordered]` dict populated in doc order of winning widgets, and `platforms[].breakdowns` lists every dimensioned widget in doc order with its metric names.

- **Facebook:** headline key order is `reach, impressions, cpm, actions::link_click, costPerActionType::link_click, ctrLink, actions::lead, costPerActionType::lead, spend, clicks, ctr, cpc, pageEngagementActions, frequency`. The first FB dimensioned widget (Month, `vAzpM9Ad87ZMGhPS8`) orders its metrics `Reach, Impressions, CPM, Clicks, CTR, CPC, Link Clicks, ...` - if its total row had supplied the first winners, `clicks/ctr/cpc` would precede the link-click ids in the headline. They do not. The first winners therefore came from zero-dim scorecards that precede the tables.
- **Google:** headline positions 2-3 are `search_impression_share` and `search_lost_is_budget`, which appear in **no** early breakdown widget - again scorecards first.
- **Conclusion:** for every metric the archive can attribute, the doc-order winner is ALREADY the zero-dim KPI; the rank rule is a no-op there. For late-ordered metrics whose source the archive cannot resolve (e.g. FB `frequency`, `pageEngagementActions`, both present on the Campaign table), a flip on the next pull is possible but not provable from the archive; **if it happens it is disclosed by D4/D5, never silent**. Note also that a current-`main` re-pull already differs from this pre-U6 archive by U6's documented behavior changes 1-5 (U6:265-271), so U9's delta must be assessed against current `main`, not against the archived bytes.

---

## Decisions

- **D1. Rank definition and candidate predicate (pinned).** Two ranks exist, exactly the two canonical sources U6 D5 left standing (U6:68):
  - **Rank 1 - true zero-dim KPI:** a widget that passes every gate the headline loop already applies - `kind -eq 'data'` (A:575), non-blended (`Test-Blended` false, A:619), `Total-Row` non-null (A:620-621), `@($w.dimensions | Where-Object {$_}).Count -eq 0` (A:623-624), and a numeric scalar cell for the metric (A:628-630). Equivalently: **exactly the cells that today earn `canonical.scope='account'` / `source='kpi-widget'`**.
  - **Rank 2 - explicit dimensioned total row:** everything else that reaches the cell write, i.e. today's `scope='table-total:<dim>'` / `source='total-row'`.
  - Rank derives from the **dimension count**, not the row kind: a zero-dim widget whose row is `kind='total'` is still rank 1 (A:141-150 already returns it; A:624 already stamps `account`).
  - **`manualKpi` needs no exclusion clause** - the repo contradicts the concern raised in the unit brief: `kind -eq 'data'` at A:575 structurally excludes non-data widget kinds from `$dataWidgets`, so a `manualKpi` widget can never be a candidate NOR an incumbent (same finding as the U7 critic override, U7:7). Documented, not coded.
  - **Blended widgets can never displace** (A:619 `continue` precedes the candidate evaluation; U6 D6 invariant intact).
  *Rationale: the predicate must be byte-for-byte the predicate that already earns `scope='account'`, or the scope label and the rank rule could disagree. No new classification logic is introduced; rank 1 IS `$isKpi`.*

- **D2. Precedence rule.** Within one `(provider, metricId)` key: **rank 1 beats rank 2 regardless of document order; document order remains the tiebreak within the same rank.** Concretely, the bare first-wins `continue` at A:632 becomes: keep the incumbent unless the incoming candidate is rank 1 AND the incumbent is rank 2 (`$existing.canonical.source -ne 'kpi-widget'`); in that one case, **replace the cell in place**. After a replacement the incumbent is rank 1, so at most one displacement can occur per key (a second, later KPI hits a rank-1 incumbent and keeps doc-order first-wins).
  *Rationale: this is U6's declined draft-D4 verbatim - a platform's own zero-dimension KPI card is the account total by construction of the widget type; a dimensioned table's total row is only ever a table total, possibly a filtered subset (U6 m1, U6:28). Preferring the honest `account` scope over the accidental doc-order of report layout is the whole point of the unit.*

- **D3. The waiver is bounded and provable.** The replacement branch is reachable ONLY when a provider carries both a doc-earlier rank-2 winner and a later rank-1 candidate for the same metric id. On every other report the loop takes exactly today's code path and the emitted facts are byte-identical **except** the D6 version token. All flip-conditional additions (D4 finding, D5 field, D7 recompute) are gated on an actual displacement having occurred.
  *Rationale: the house rule ("default single-report output path stays byte-for-byte unchanged") is waived, not abandoned - the waiver's blast surface must be enumerable, and it is: {flipped headline cells and everything computed from them (D8)} + {one meta token (D6)} + {flip-only additive disclosures}.*

- **D4. Disclosure finding `DISC_HEADLINE_PRECEDENCE` (additive, info, flip-only).** One finding **per provider** with at least one displacement, D11-style rollup (U6 D11, U6:74): `evidence.metrics` = displaced metric ids, deduped/sorted, capped at 20 with a `+N more` sentinel; `evidence.count` = full count as a display string (precedent: `GAP_NO_ACCOUNT_TOTAL`'s `count`, A:681); `evidence.supersededWidgets` = deduped displaced widget ids. Routed into `$disc` (it documents a cross-widget scope relationship, the discrepancies channel's job - `DISC_CROSS_WIDGET` A:738, `RECON_SLICE_OVER_ACCOUNT` routing A:746-750); the fid pass (A:769-771) assigns `DISC_HEADLINE_PRECEDENCE#n`. `severity='info'` - never force-surfaced, never blocks delivery.
  **The statement and evidence carry NO metric values** - only ids and a count. *Rationale: the finding's job is visibility of the flip, not re-litigating the numbers; the displaced table-total value is deliberately NOT echoed (it would be a new untraceable-number surface for a figure we just decided not to headline). When the displaced total actually exceeds the KPI - the case where the reader most wants both numbers - U7a's `RECON_SLICE_OVER_ACCOUNT` (A:550-555) already fires independently and carries both display strings with full traceability.*

- **D5. Per-cell provenance `canonical.supersededWidgetId` (additive, flip-only).** A flipped cell's `canonical` record gains one key, `supersededWidgetId` = the displaced rank-2 widget's id. Absent on every non-flipped cell (so non-flip reports gain zero bytes from it). The U6 record shape `{display, sourceWidgetId, scope, period, source}` (U6:179-187) is otherwise untouched; the e2e13 forbidden-key list (`value`, `basisVersion`, `synthesizedFrom`, T:326) stays as-is.
  *Rationale: the reader question U6 canonical answers is "which widget did this number come from?"; after a flip the natural follow-up is "and which widget did it USED to come from?". One id answers it; the closer ignores unknown keys (pinned by U6 case 22, T:519-523).*

- **D6. `meta.canonicalVersion` bumps 1 -> 2 (on every report).** A:786 changes `canonicalVersion=1` to `canonicalVersion=2`. This is the one deliberate NON-flip-gated byte delta, and it is exactly the field doing the job U6 created it for (U6 D10, U6:73): marking which canonical algorithm produced the facts. Grep-verified: the only consumers of `canonicalVersion` are A:786 and the e2e14 assertion (T:328); nothing gates on `-eq 1`.
  *Rationale: a silent algorithm change under an unchanged version marker would be worse than the flip itself - any future cross-artifact comparison (including U7b) must be able to tell a v1-winner facts file from a v2-winner one. The alternative (keep 1, disclose only per-flip) leaves the dominant no-flip population indistinguishable from pre-U9 output while the selection algorithm differs; rejected.*

- **D7. `hasComparison` recompute, flip-platforms only, value-only.** The comparison flags are set-only during the loop (A:636), so a displaced comparison-bearing cell could leave a stale `true` behind if its replacement KPI lacks a compare column. After the headline loop (pinned: immediately after A:648, before the findings init at A:651), every provider with >= 1 displacement recomputes `platform.hasComparison` and the value of the `headline.hasComparison` key (if present) as the OR of the **surviving** cells' `hasComparison`. No key is ever added or removed - a `true` case always has the key already (any comparison-bearing write sets it, A:636), so value-only recompute is complete. `meta.hasComparison` (A:777) and the seasonality caveat (A:779-783) then follow automatically.
  *Rationale: precedent is U6 behavior change #5 (U6:270): a caveat about a comparison we no longer surface is not needed. Non-flip platforms never enter the branch, so their key positions AND values are byte-identical; on flip platforms the value may change - already inside the waiver.*

- **D8. Downstream headline consumers recompute from the winner - intended, disclosed, not patched.** `WIN/LOSS` (A:690-698), `GAP_UNIT_UNCONFIRMED` (A:689), and `ANOM_BUDGET_CONSTRAINED` (A:701-712) all read the final headline cells; on a flip report they now reflect the truer number (deltas, units, currency of the KPI cell). No special-casing.
  *Rationale: patching them to remember the displaced cell would re-introduce the wrong number through a side door. The whole unit's claim is that the KPI cell IS the account figure; every derived fact should follow it.*

- **D9. Winner-independent machinery is untouched - proven, not asserted.**
  - **U7a #5 account-ceiling** (`Get-SliceAccountFindings`, A:522-559) re-derives its KPI candidates by scanning `$dataWidgets` for non-blended zero-dim widgets with a non-null `Total-Row` and matching provider/metric (A:532-541), with its own ambiguity skip (A:543-544). It never reads `platforms[].headline` or `canonical`. (The U7 spec's R17 body text at U7:111 says "with `canonical.scope=='account'`", but the authoritative critic override at U7:6 corrected this to re-derivation, and the code follows the override - **follow the repo**.) A winner flip cannot perturb #5; after a flip, #5's ceiling and the headline now cite the same widget - strictly more coherent.
  - **DISC_CROSS_WIDGET** (A:713-740) builds its own index from `$dataWidgets` + `Total-Row` + dimSig (A:716-727); headline-independent. Unchanged.
  - **#3/#4** (`Get-RatioReconFindings` A:407-469, `Get-DetailSumFindings` A:473-517) are per-widget over `Total-Row`; headline-independent. Unchanged.
  - **GAP_NO_ACCOUNT_TOTAL** (A:664-683) tests `-not $pf.headline.Contains($_)` (A:675) - the key exists whether won by rank 1 or rank 2, so gap membership is flip-invariant.
  - **Trend ledger:** the ledger pipeline never touches single-report headline facts at all. Ledger cells are built from `$doc.trendCells` of a raw `-Trend` extraction (TF:36-52), keyed `providerId|metricId|basisVersion|month` (L:87-91); `Analyze-SwydoTrend.ps1` reads only the ledger (`-LedgerFile`, AT:21-23). A headline flip cannot change any ledger key or value. `Update-SwydoLedger.ps1` is on the forbidden list.

- **D10. `restatementCount` is NOT reused - the ledger is left alone.** The ledger's restatement machinery (L:90, L:96-101; surfaced as `GAP_RESTATEMENT_SUPPRESSED` at AT:126-130) tracks a frozen **monthly trend cell** whose value a later pull contradicts - same artifact, same key, new number. A U9 flip is a different event class: same raw data, new **selection algorithm**, report-scoped, and the report facts are never frozen (each pull writes a new timestamped facts file; archived snapshots are immutable with sha256 manifests). Wiring headline history into the ledger would require persisting per-report winners there - a ledger schema change, which is an explicit OUT for this unit.
  *Rationale: the restatement concept answers "the platform changed a shipped number"; U9 answers "we changed which of the platform's numbers we headline". Conflating them would make `GAP_RESTATEMENT_SUPPRESSED` (a major) fire on an algorithm upgrade - a false alarm by construction. The correct restatement-style note for a re-pulled client is exactly D4's finding in the new facts, plus D6's version token distinguishing the algorithm generations.*

- **D11. Migration: none. Archived artifacts are immutable and stay truthful.** Already-shipped reports/facts are never rewritten (the archive stores dated snapshot dirs with sha256s; nothing in this unit touches `Manage-SwydoArchive.ps1`). An archived facts file remains a correct record of what algorithm v1 computed, self-describing via its `canonicalVersion` (absent = pre-U6, `1` = U6, `2` = U9). A re-pull of a previously-archived client that now produces a different headline discloses it forward (D4/D5/D6) in the new artifact. No backfill pass, no ledger edit, no archive edit.

- **D12. U7b `-PeriodKpiFacts` interaction: U9 strictly reduces #6's false-mismatch surface.** U7b is still deferred and `-PeriodKpiFacts` does not exist in code (grep-verified against `Analyze-SwydoTrend.ps1`; AT param block is `-LedgerFile/-OutDir/...` only). Check #6's deferred design consumes "the canonical account headline" of the period-KPI facts (U7:271, U7:285) and compares it against monthly ledger sums, which are account-scoped by construction (per-provider-metric-month trend cells, TF:8-9). Pre-U9, a table-before-scorecard layout would hand #6 a `table-total:*` cell as the "period KPI" - a subset total vs account-months comparison that can only manufacture a false `RECON_TREND_MISMATCH` (major). Post-U9 the headline for any metric with a true KPI anywhere in the document is the account cell - like-for-like. The interaction is one-directional: a flip replaces a table total with a true KPI, never the reverse.
  *Recorded for the U7b build (design note, not built now): #6 should additionally gate on `canonical.scope -eq 'account'` of the period-KPI cell, which post-U9 is both meaningful and cheap; a `table-total:*` period KPI degrades to `info RECON_TREND_COVERAGE`.*

---

## Implementation sketch (pinned insertion points; PS 5.1-safe, pure ASCII)

**1. Displacement tracking + replacement (replaces the bare `continue` at A:632).** `$displaced = @{}` is initialized next to `$platforms=@{}` (A:602).

```powershell
$existing = $null
if($platforms[$prov].headline.Contains($key)){ $existing = $platforms[$prov].headline[$key] }
if($existing){
  # U9/D2: a TRUE zero-dim KPI supersedes a document-earlier table total for the same metric id;
  # same-rank candidates keep document-order first-wins (identical to pre-U9 for every other pair).
  if(-not ($isKpi -and ($existing.canonical.source -ne 'kpi-widget'))){ continue }
  if(-not $displaced.ContainsKey($prov)){ $displaced[$prov]=[System.Collections.ArrayList]@() }
  [void]$displaced[$prov].Add([ordered]@{ metricId=$key; supersededWidgetId=$existing.canonical.sourceWidgetId })
}
```

The cell write (A:638-646) is unchanged except: when `$existing` was displaced, the `canonical` ordered dict gains `supersededWidgetId=$existing.canonical.sourceWidgetId` as its last key (D5). Assigning `$platforms[$prov].headline[$key] = <new cell>` on an `OrderedDictionary` **replaces the value in place, preserving the key's position** - the flipped metric keeps its original position in the emitted JSON, so headline key order is stable across the flip (pinned by test U9-T7).

**2. `hasComparison` recompute (D7).** Immediately after the headline loop closes (A:648), before the findings init (A:651):

```powershell
# U9/D7: platforms that had a displacement recompute comparison flags from SURVIVING cells.
# Value-only: no key is added or removed. Non-flip reports never enter this branch.
foreach($dpk in @($displaced.Keys)){
  if(-not $platforms.ContainsKey($dpk)){ continue }
  $pfD=$platforms[$dpk]; $anyCmp=$false
  foreach($hk in @($pfD.headline.Keys)){
    if($hk -eq 'hasComparison'){ continue }
    if($pfD.headline[$hk].hasComparison){ $anyCmp=$true; break }
  }
  if($pfD.headline.Contains('hasComparison')){ $pfD.headline['hasComparison']=$anyCmp }
  $pfD.hasComparison=$anyCmp
}
```

**3. Disclosure finding pass (D4).** Pinned: immediately after the `GAP_NO_ACCOUNT_TOTAL` pass (A:683), before the win/loss pass (A:684) - `$disc` and `$platforms` are in scope; the fid pass (A:769-771) covers it.

```powershell
# U9/D4: disclose rank displacements - one info finding per provider (D11-style rollup; ids and count only,
# NO metric values: the displaced total is deliberately not echoed - see RECON_SLICE_OVER_ACCOUNT for values).
foreach($dpk in @($displaced.Keys)){
  $items=@($displaced[$dpk]); if($items.Count -eq 0){ continue }
  $dmet=@($items | ForEach-Object { $_.metricId } | Sort-Object -Unique)
  $dwid=@($items | ForEach-Object { $_.supersededWidgetId } | Where-Object { $_ } | Sort-Object -Unique)
  $dshown = if($dmet.Count -gt 20){ (@($dmet[0..19]) + @("+$($dmet.Count-20) more")) } else { $dmet }
  $pnameD = if($platforms.ContainsKey($dpk)){ $platforms[$dpk].name } else { $dpk }
  [void]$disc.Add([ordered]@{
    ruleId='DISC_HEADLINE_PRECEDENCE'; severity='info'; platform=$pnameD
    statement="headline for $($dmet.Count) metric(s) of ${pnameD} now comes from the account KPI card instead of a document-earlier table total: $($dshown -join ', '); superseded widget(s): $($dwid -join ', ')"
    evidence=[ordered]@{ metrics=@($dshown); count="$($dmet.Count)"; supersededWidgets=@($dwid) }
  })
}
```

**4. Version token (D6).** A:786: `canonicalVersion=1` -> `canonicalVersion=2`.

---

## Blast radius

**Files that change (build commit, one review boundary):**
- `skill/scripts/Analyze-SwydoReport.ps1` - the four edits above; nothing else in the file.
- `Test-Analyze.ps1` - new cases (test plan below) + two documented in-place assertion updates (e2e11 -> new-rank pin, e2e14 -> `canonicalVersion 2`).
- `docs/specs/headline-rank-precedence-spec.md` - this file (Status line updated on ship).
- `docs/specs/context-and-canon-spec.md` - one row added to the units index (U9), per the U6 precedent (U6:6). No other content in that file changes.

**Files FORBIDDEN to change:** `skill/scripts/Test-ReportNumbers.ps1` (closer), `skill/scripts/Get-SwydoReport.ps1`, `skill/scripts/ConvertTo-SwydoTrendFacts.ps1`, `skill/scripts/Update-SwydoLedger.ps1`, `skill/scripts/Analyze-SwydoTrend.ps1`, `skill/scripts/Manage-SwydoArchive.ps1`, `skill/scripts/Sync-SwydoTrend.ps1`, `skill/SKILL.md`, all other `Test-*.ps1` suites, everything under `skill/archive/` (immutable snapshots).

**Facts-surface delta, enumerated (the waiver's full extent):**
1. Flip reports only: the flipped headline cells' values/displays/deltas/unit/currency and their `canonical` (now `account`-scoped, + `supersededWidgetId`); findings derived from those cells (WIN/LOSS, GAP_UNIT_UNCONFIRMED, ANOM_BUDGET_CONSTRAINED); possibly `hasComparison`/seasonality caveat (D7); + one `DISC_HEADLINE_PRECEDENCE` info per affected provider.
2. All reports: `meta.canonicalVersion` `1` -> `2` (D6). Nothing else.

---

## Edge cases and false-positive analysis (named)

- **E1 kpi-after-table (the core flip):** table total wins at first encounter, later KPI displaces it; `supersededWidgetId` + finding emitted. (Test U9-T1.)
- **E2 kpi-first (the dominant layout, QCU-verified):** KPI wins at first encounter; the later table-total candidate hits a rank-1 incumbent and `continue`s - byte-identical output except D6. (U9-T2.)
- **E3 same-rank stability:** two KPIs -> doc-first wins (r18a layout unchanged); two table totals -> doc-first wins. No finding. (U9-T3.)
- **E4 blended zero-dim never displaces:** `Test-Blended` skip at A:619 precedes candidate evaluation; a blended KPI-shaped widget after a table total changes nothing. (U9-T5.)
- **E5 `dimensions=$null` KPI:** `@($null | Where-Object {$_}).Count -eq 0` - treated as zero-dim (the `@($null).Count==1` trap is already guarded, A:146, U6:95); it displaces like any rank-1 candidate. (U9-T13.)
- **E6 non-numeric KPI cell (echo object):** fails the scalar guard at A:630 before rank evaluation - not a candidate; the table total stays, no finding. (U9-T14.)
- **E7 at-most-one displacement per key:** after a flip the incumbent is rank 1; a second later KPI cannot displace again, so `supersededWidgetId` always names a rank-2 widget and the finding never chains. (U9-T4.)
- **E8 table-total-only metric:** no rank-1 rival exists -> no flip, no finding; `GAP_NO_ACCOUNT_TOTAL` semantics untouched (the metric HAS a headline; D9). (Covered by e2e10 unchanged.)
- **E9 cross-basis flip:** table EUR/micros displaced by KPI USD/null-unit - the winner's unit/currency go with it; `GAP_UNIT_UNCONFIRMED` recomputes from the final cell (D8), and a same-metric basis mismatch surfaces there, not in the D4 finding (which carries no values). (U9-T10.)
- **E10 comparison loss on flip:** displaced cell was the only comparison-bearing cell and the KPI has none -> D7 recompute flips `hasComparison` false, seasonality caveat drops (U6 behavior-#5 precedent). (U9-T9.)
- **FP-1 "filtered KPI card displaces an honest account-wide table total" - the unit's real residual risk.** Schema v2 cannot detect widget-level filters or per-widget date ranges (U6 residual, U6:243; U7 R17 rationale, U7:110). A zero-dim card that is secretly campaign-filtered would displace a genuinely account-wide table total. **Accepted residual, disclosed:** (a) the flip itself is visible (D4/D5); (b) when the displaced total exceeds the KPI, `RECON_SLICE_OVER_ACCOUNT` fires with both values (A:550-555); (c) a value-based gate ("only displace if KPI >= table total") was considered and REJECTED - it would have the tool adjudicate which number is right by arithmetic comparison, exactly the class of inference U6/U7 reserve for provably-impossible directions, and it would make the winner depend on data values (non-deterministic across periods) instead of structure. This is the same risk U6 already accepted when it stamped `scope='account'` on these cards; U9 re-weights it but does not create it.
- **FP-2 "finding fatigue on breakdown-heavy reports":** bounded by the D11-style per-provider rollup + 20-id cap; info severity never force-surfaces (U6 D11 precedent). (U9-T8.)
- **FP-3 "disclosure numbers entering the untraceable haystack":** structurally impossible - statement/evidence carry only metric ids, widget ids, and a count-as-string (D4); there is no metric value to trace. (U9-T11.)
- **FP-4 "flip perturbs U7a/DISC/ledger":** disproven at D9 with line evidence; pinned by U9-T6/T12 and the untouched-suite green re-runs.

---

## Green-count contract

Measured board on `main` @ `cccd0c9` (2026-07-11), all suites exit 0: **Analyze 276, Closer 119, Extractor 94, Archive 94, TrendFacts 19, Ledger 50, TrendAnalyze 24, Sync 4.**

- U9 is **additive on Analyze (276)** with exactly **two documented in-place assertion updates** (e2e11 at T:317-322, e2e14 at T:328) - both encode the pre-U9 algorithm and are updated as part of this unit, never silently. Every other existing Analyze assertion re-runs green unmodified (audit result above).
- **All seven other suites re-run green untouched** - no file they exercise is modified (blast radius). Closer 119 specifically re-verifies that facts carrying `supersededWidgetId` and `DISC_HEADLINE_PRECEDENCE` remain ignorable extra data (the U6 case-22 mechanism, T:519-523, extended by U9-T11).

---

## Test plan (`Test-Analyze.ps1`, house harness style: `-DefineOnly` units + `RunAnalyze` e2e fixtures)

**Updated in place (documented):**
- **e2e11 (T:317-322) ->** same two-widget fixture (`w-first` table total before `w-second` KPI, same `(prov,metricId)`): assert `canonical.sourceWidgetId -eq 'w-second'`, `canonical.scope -eq 'account'`, `canonical.source -eq 'kpi-widget'`, `canonical.supersededWidgetId -eq 'w-first'`.
- **e2e14 (T:328) ->** `meta.canonicalVersion -eq 2` (factsVersion still 1).

**New e2e cases:**
1. **U9-T1 flip core (E1):** table-then-KPI -> headline `current`/`displayCurrent` are the KPI's; `DISC_HEADLINE_PRECEDENCE` present with `severity='info'`, a fid, `evidence.metrics` containing the metric id, `evidence.supersededWidgets` containing the table widget id, `evidence.count -eq '1'`.
2. **U9-T2 no-flip byte guard (E2):** KPI-then-table -> winner is the KPI; `$r.text -notmatch 'supersededWidgetId'` and no `DISC_HEADLINE_PRECEDENCE`; assert the emitted facts differ from a pre-U9 golden only in `"canonicalVersion":2`.
3. **U9-T3 same-rank doc-order pins (E3):** (a) two KPIs same metric -> first wins, no finding; (b) two dimensioned total-row widgets same metric -> first wins, no finding.
4. **U9-T4 single displacement (E7):** table, then KPI-1, then KPI-2 -> winner KPI-1; `supersededWidgetId` names the table; exactly one metric entry in the finding.
5. **U9-T5 blended never displaces (E4):** table total, then a blended zero-dim widget carrying the same metric -> winner stays the table; no finding; blended widget still absent from any `canonical.sourceWidgetId` (e2e17 invariant).
6. **U9-T6 #5 independence (D9):** the u5a layout (table `$120` total before KPI `$100`) -> headline flips to the `$100` KPI AND `RECON_SLICE_OVER_ACCOUNT` still fires info with both displays; the headline and #5's `evidence.account` now cite the same figure.
7. **U9-T7 key-order stability:** flip fixture with three metrics where only the middle one flips -> headline JSON key order unchanged (regex over `$r.text` for the three ids' relative positions).
8. **U9-T8 rollup + cap (FP-2):** one provider, 25 metrics all table-won then displaced by a later 25-metric KPI widget -> exactly ONE `DISC_HEADLINE_PRECEDENCE`; `evidence.count -eq '25'`; `@(evidence.metrics).Count -eq 21` with `'+5 more'` sentinel (mirrors e2e16, T:332-337).
9. **U9-T9 comparison recompute (E10):** table cell WITH compare displaced by KPI without -> `meta.hasComparison -eq $false`, zero `comparisonCaveats`; control variant where a second, undisplaced cell carries compare -> stays `$true`.
10. **U9-T10 winner-follows facts (D8/E9):** table (delta would be a WIN) displaced by KPI whose delta crosses the loss threshold -> LOSS emitted from the KPI figures, no WIN from the displaced figures; variant with null-unit money KPI -> `GAP_UNIT_UNCONFIRMED` names the KPI's raw display.
11. **U9-T11 closer graceful-ignore + no-value evidence (FP-3):** run the closer over flip-report facts with a report that does NOT cite the finding -> 0 violations (info, not force-surfaced); assert `DISC_HEADLINE_PRECEDENCE`'s statement matches `-notmatch '[\$%]'` and contains no formatted metric value; the flipped `displayCurrent` traces on a platform line as usual.
12. **U9-T12 gap invariance (D9):** flip fixture -> no `GAP_NO_ACCOUNT_TOTAL` for the flipped metric (headline key exists); a genuinely uncovered metric on the same provider still gets its gap.
13. **U9-T13 null-dimensions KPI displaces (E5).**
14. **U9-T14 non-numeric KPI cell does not displace (E6):** echo-object cell in the later KPI -> table stays, no finding.
15. **U9-T15 DISC unchanged (D9):** two disagreeing KPIs after a table total -> flip to doc-first KPI + `DISC_CROSS_WIDGET` still fires major on the KPI pair (r18a mechanism intact).

**Cross-suite:** full Analyze suite green (276 baseline with the two documented updates + the cases above); Closer 119, Extractor 94, Archive 94, TrendFacts 19, Ledger 50, TrendAnalyze 24, Sync 4 re-run green untouched.

---

## PS 5.1 hazards specific to this change

- **`@($null).Count == 1`:** `$displaced` values are `ArrayList`s wrapped `@(...)` before `.Count`; `$dmet`/`$dwid`/`$dshown` always `@(...)`-wrapped; the zero-dim guard stays `@($w.dimensions | Where-Object {$_})` (A:623).
- **OrderedDictionary semantics:** indexer assignment replaces in place (position-stable) - this is load-bearing for U9-T7; `.Contains($key)` is the key test already used at A:632. Iterating `headline.Keys` in D7 snapshot-copies via `@(...)` before any value write (no enumerate-while-modify).
- **Case-insensitive collisions:** new locals `$existing`, `$displaced`, `$dpk`, `$items`, `$dmet`, `$dwid`, `$dshown`, `$pnameD`, `$pfD`, `$anyCmp` collide with no Analyze param (`$InFile/$OutDir/$WinLossPct/$SmallN/$NotesFile/$DefineOnly`) and no dot-sourcing consumer's param (`ConvertTo-SwydoTrendFacts` captures `$my*` before sourcing, TF:29-31; nothing named `$Facts/$From/$Into/$Execute` is introduced).
- **No new arithmetic on metric values:** the only computed quantity is a count (`$dmet.Count`), emitted as a display string (D11/A:681 precedent). No `Format-Metric` call is added.
- **Byte-identity guards:** legacy cell fields keep the raw-cell population (A:640, U6:278); the D7 recompute and D4/D5 emissions are reachable only via a displacement; `ConvertTo-Json -Depth 40 -Compress` (A:797) already covers the one extra `canonical` key.
- **Pure ASCII, no `&&`/`||`/ternary/`??`** in all snippets above.

---

## For the reviewer (adversarial)

1. **Is D6's global `canonicalVersion` 1 -> 2 inside or outside the sanctioned waiver?** It is the only NON-flip-gated byte change, on every report including the dominant no-flip population. The spec's position: the version marker changing when the algorithm changes is the marker doing its job, and keeping `1` would make v1- and v2-winner facts indistinguishable. If the reviewer rules it out, the fallback is flip-only disclosure (D4/D5) with `canonicalVersion` frozen at 1 - state explicitly which shipped invariant that fallback breaks (a facts file no longer names its selection algorithm).
2. **FP-1 (filtered KPI card) is the load-bearing residual.** U9 trusts widget STRUCTURE (zero-dim = account) over document order, knowing schema v2 cannot see widget-level filters. The rejected alternative was a value-comparison gate. Is structure-over-order the right trust hierarchy, or should displacement additionally require agreement with U7a #5's re-derived ceiling scan (skip the flip when multiple differing zero-dim candidates exist - #5's A:543-544 ambiguity rule)? Note the current design already inherits DISC_CROSS_WIDGET (major) on disagreeing same-scope KPIs; an ambiguity gate would be additive, not corrective.
3. **D4 routing and naming:** `DISC_HEADLINE_PRECEDENCE` into `$disc` (cross-widget scope channel) vs a `GAP_`/gaps-channel note. Mechanically identical (fid pass covers both; info never force-surfaces). Is the `DISC_` prefix misleading for a non-discrepancy provenance note?
4. **D7's value-only recompute** can flip an existing `hasComparison` key to `$false` on flip reports. The alternative (leave set-only, accept a stale-true flag and a possibly unwarranted seasonality caveat) is smaller but dishonest. Confirm the recompute, and confirm the "no key added/removed" argument (any true case implies the key exists) is airtight.
5. **The QCU empirical bound is inference, not observation:** headline-key-order vs breakdown-metric-order proves scorecards precede tables for the attributable metrics, but late-ordered metrics (`frequency`, `pageEngagementActions`) are unresolvable from a pre-U6 archive, and a dimensioned widget with a total row but zero data rows would be invisible in `breakdowns` (Get-Breakdown returns `$null` on empty detail, A:270). Is "no expected flip, any actual flip is disclosed" an acceptable evidentiary standard, or should the build gate on re-running Analyze against one fresh live extraction before merge?
6. **Sharpest self-criticism of the disclosure design:** D4 deliberately omits the displaced value. A reader of a flip report sees WHICH widget was superseded but not WHAT it said; recovering the number requires the (unheadlined) widget's breakdown rows or a #5 finding, which only fires in the exceeds direction. Is id-only disclosure enough, or does the finding need the displaced display string (accepting the new traceable-number surface and its closer obligations)?
7. **Scope discipline check:** rank-3 synthesis stays deferred (U6:248-257), the ledger and closer are untouched, and no report-template change is required (`scope`/`supersededWidgetId` are labels, U6 m1 precedent). Verify no decision above quietly widens that cut-line.
