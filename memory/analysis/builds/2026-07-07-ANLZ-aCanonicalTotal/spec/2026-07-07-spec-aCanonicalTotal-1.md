# U6 - Canonical account total with provenance (spec v2)

> **Review provenance & critic overrides (authoritative).** This spec is the v2 output of a 3-lens adversarial review (correctness/fit, security/boundary, PS-5.1/compat), whose findings are folded into the body below, followed by a cross-cutting completeness critic over U6+U7 together. Where the critic overrides the body, the override wins:
>
> - **D-period is DEFERRED, not built in U6.** The U7 spec's "D-period folded into U6" note is superseded. U6's `meta` changes remain exactly section A2.5 (`canonicalVersion=1` only; nothing else in `meta`). Rationale: `meta.period`'s sole consumer is U7b/#6, which is itself deferred; and `Get-SwydoReport.ps1:165` discards concrete dates for RELATIVE date ranges, so `meta.period.startYm/endYm` would be `$null` and `calendarAligned=$false` for the dominant relative-quarter case regardless. When U7b is undeferred, D-period is built with it (owned by U6/extractor at that time) with its own tests. **[Sequencing superseded by U8, 2026-07-14]:** D-period was built ahead of U7b as its own unit (spec `extractor-period-resolution-spec.md`); U7b stays DEFERRED and consumes the now-shipped `facts.meta.period` at its own undeferral.
> - **Units index:** a one-line pointer to this spec is added to `docs/specs/context-and-canon-spec.md` so U6/U7 are discoverable alongside U1-U5.
>
> Build verdict: **GO.** Build order: U6 (this spec) -> U7a -> [U7b deferred].

**Status:** SHIPPED (built, reviewed, merged to main). Extends `docs/specs/context-and-canon-spec.md`; same discipline (PS 5.1/.NET, ASCII, functions-first + `-DefineOnly`, default single-report path additive-only, every credential path fail-closed). **Blast radius: `skill/scripts/Analyze-SwydoReport.ps1` ONLY** (v2 keeps the draft's Analyze-only scope by *deferring* the two things that would have touched the ledger). New tests in `Test-Analyze.ps1`. Decisions below are RATIFIED unless marked **[USER-FACING]**.

Green-count contract to preserve: **Analyze 135, Closer 119, Extractor 94, Archive 94, TrendFacts 19, Ledger 50, TrendAnalyze 24, Sync 4.** New Analyze cases are additive on top of 135.

---

## Changelog vs draft

The three adversarial lenses converged on one root cause: **rank-3 synthesis was unsafe against the current extractor** and dragged in most of the other findings. v2 removes that whole class rather than patching each symptom.

| # | Finding (sev) | Resolution in v2 |
|---|---|---|
| B1 | Rank-3 truncation guard is dead code -> tool ships an under-counted fabricated total (both lenses; **blocker/major**) | **RANK-3 SYNTHESIS DEFERRED ENTIRELY.** Precedence collapses to (1) zero-dim KPI -> (2) explicit total row -> GAP. No tool-invented total is ever emitted. The completeness signal the guard needed does not exist in `Get-SwydoReport.ps1` (confirmed: only warnings are `no rows returned for:` and `units not inferred...`); synthesis is gated behind a *positive* completeness signal in a future unit. |
| M1 | `Test-Synthesizable` dedup regex misses GA4 `activeUsers`/`totalUsers` (defeats D5, fails test 9) (**major** x2) | **MOOT** - no synthesis path exists; `Test-Synthesizable` is not shipped. (Regex fix recorded in the deferred-work note so it lands correctly if synthesis is ever built.) |
| M2 | Synthesized sum double-counts `(group)`/`All` data rows (**major**) | **MOOT** - no synthesis. (Deferred note: must reuse `Test-GroupRow` filter, confirmed at A:131.) |
| M3 | Blended-only provider never emits `GAP_NO_ACCOUNT_TOTAL` (breaks D6, fails test 17) (**major** x2) | **FIXED.** Gaps are now emitted from a **providerxmetric coverage** pass keyed off *observed metric-id prefixes*, not off canonical keys. A discovered provider with no headline cell for a metric gets the gap regardless of why (blended-only, dimensioned-no-total-only). |
| M4 | Basis-pin test (#16) silently self-compares -> false green; two `Get-BasisVersion` copies drift (**major**) | **MOOT** - `basisVersion` dropped from the canonical record (deferred with synthesis, its only real consumer). No second copy of `Get-BasisVersion` is introduced; the ledger is untouched. |
| M5 | Rewritten run-body has zero test coverage; body-level asserts (#14/#15/#17) need execution, harness only does `-DefineOnly` (**major**) | **FIXED.** New end-to-end fixture cases run `Analyze-SwydoReport.ps1 -InFile <tmp> -OutDir <tmp>` and inspect the emitted `*.facts.json` (cases 14-22). |
| m1 | Rank-2 total row trusted as `scope='account'` with no disclosure (**minor**) | **FIXED.** A dimensioned widget's total row is now stamped `scope='table-total:<dim>'`, never bare `account`. Only a zero-dim KPI earns `scope='account'`. |
| m2 | `canonical.value` (raw scalar) enlarges the untraceable-number haystack (**minor**) | **FIXED.** `canonical.value` dropped; record carries `display` + provenance only. |
| m3 | `@($null).Count==1` trap on `$w.dimensions[0]` (**nit/minor**) | **FIXED.** `$dims=@($w.dimensions | Where-Object {$_})`; use `$dims[0]`/`$dims.Count`. |
| m4 | Build-Canonical impure (reads caller `$doc`) (**minor**) | **MOOT** - the truncation read is gone (no synthesis). The headline augmentation needs nothing but `$w` + `$periods` and is inline (no separate impure helper). |
| m5 | Provider-derivation expression diverges between discovery and canonical -> silent winner drop (**nit**) | **FIXED.** Factored into one `Get-WidgetProvider($w)` used by discovery, headline, and the gap pass. |
| m6 | Gap-emission insertion point unpinned; `$gaps` undefined at A:367 (**nit**) | **FIXED.** Exact insertion point pinned: the gap pass runs **after `$gaps` init (A:398) and the GAP_WARNINGS/PROVIDER_FILTERED adds (A:401-405)**, **before** the fid pass (A:482). |
| - | Cross-scope disagreement (KPI vs table-total) not reconciled (**missing**) | **WONTFIX, documented residual.** Canonical does not attempt cross-scope reconciliation; DISC only compares identical dimSig. See sec Residuals. |
| - | Seasonality caveat can flip false when A1 drops the only comparison-bearing widget (**missing**) | **DOCUMENTED** as behavior-change #5 + regression test (case 21). |
| - | Cross-basis DISC false-positive (same metric, two currencies, same dimSig) (**missing**) | **WONTFIX, documented residual** (pre-existing; U6 does not touch DISC). |
| - | Closer must gracefully ignore the new `canonical` key (**missing**) | Pinned by case 22 (closer 119 green on facts carrying `canonical`). |
| - | `GAP_NO_ACCOUNT_TOTAL` cardinality bloat (**missing**) | **FIXED.** Deduped to **one finding per provider**, rolling up the affected metric ids into `evidence.metrics` (capped list). |

Net effect: v2 is a **strictly smaller** change than the draft (fixes the live bug + adds honest provenance + a gap; no synthesis, no new pure helpers beyond a tiny provider-derivation factor, no ledger edit). Everything the reviewers flagged as unsafe is deferred behind a named precondition rather than shipped behind an inert guard.

---

## Problem (the ratified live bug)

`Total-Row($w)` (A:120) falls back to the **first data row** when a widget has no explicit total row:

```powershell
function Total-Row($w){ $t=@($w.rows | Where-Object { $_.kind -eq 'total' }); if($t.Count -gt 0){ return $t[0] }; $t=@($w.rows|Where-Object{$_.kind -eq 'data'}); if($t.Count -gt 0){return $t[0]}; return $null }
```

A dimensioned table (e.g. per-campaign cost) with no total row therefore silently promotes its **top slice** to the provider account headline -> order-dependent scope misattribution. The same fallback feeds the headline loop (A:372), `Get-BreakdownFindings` (A:126), and `DISC_CROSS_WIDGET` (A:440), so the wrong comparand propagates everywhere.

U6 v2:
- **A1** - `Total-Row` returns an account total ONLY when the widget is a true KPI widget (zero dimensions); a dimensioned no-total table returns `$null` (never a data row).
- **A2** - attach a **scope-aware canonical provenance record** to every headline cell (which widget the number came from, and whether it is an account total or merely a table total), and emit `GAP_NO_ACCOUNT_TOTAL` (info) for every discovered `(provider, metricId)` that ends up with no headline cell.

Winner selection is otherwise **unchanged from today** (document-order first-wins per `metricId`); v2 does not reorder winners. This keeps the common path byte-identical while eliminating the slice-promotion bug.

---

## Ratified decisions (v2)

- **D1.** `Total-Row`'s first-data-row fallback is gated on `@($w.dimensions).Count -eq 0`. *A KPI card is the only widget whose sole row legitimately IS the account total.*
- **D2.** A dimensioned no-total table returns `$null` from `Total-Row`. *A slice must never masquerade as the account.*
- **D3.** Headline dict stays keyed by `metricId`, populated by **document-order first-wins** over non-blended widgets whose `Total-Row` is non-null (identical selection to today). *No winner reordering; byte-identical common path; the live bug is fixed by A1 alone.*
- **D4. (CHANGED from draft)** **Rank precedence is dropped.** There are only two canonical sources - zero-dim KPI total and explicit dimensioned total row - and the winner among them is document order, exactly as today. *The draft's rank-1-beats-doc-earlier-rank-2 rule was a separate correctness improvement that silently changes shipped headline winners; deferred (YAGNI) to avoid perturbing the 135 green and shipped reports.*
- **D5. (CHANGED)** **Rank-3 synthesis is deferred in full**, together with `Test-Synthesizable` and `GAP_SYNTHESIZED_TOTAL`. Precedence is (1) zero-dim KPI -> (2) explicit total row -> `GAP_NO_ACCOUNT_TOTAL`. *The synthesis safety gate depended on a truncation warning the extractor never emits; a tool-invented account total behind an inert guard is worse than a disclosed gap.* See sec Deferred work for the exact preconditions and the corrected regex/group-row filter to use when it is built.
- **D6.** Blended multi-provider widgets (`@($w.providers).Count -gt 1`) are **never a headline source**. Provider **discovery** still walks all widgets and creates the platform entry (unchanged), so a blended-only provider keeps its platform entry, gets an empty headline, and surfaces `GAP_NO_ACCOUNT_TOTAL`. *Honors the standing "never anchor a blended widget" invariant.*
- **D7. (CHANGED)** No `Get-BasisVersion` is added to Analyze and the ledger is not touched. *`basisVersion` was provenance for the deferred synthesis series-keying; with synthesis deferred it has no consumer, so it is dropped (see D8). This keeps blast radius Analyze-only and dissolves the duplication/pin-test hazard entirely.*
- **D8. (CHANGED)** The canonical record drops `value`, `basisVersion`, and `synthesizedFrom`. It carries `{ display, sourceWidgetId, scope, period, source }`. *`display` + `sourceWidgetId` + `source` + `scope` fully answer the task's reader goal ("which widget did this number come from, and is it an account total?"). `value` (raw) was a redundant untraceable-number surface; `basisVersion`/`synthesizedFrom` belong to the deferred synthesis.*
- **D9.** DISC_CROSS_WIDGET is **not** modified. It keys on `Total-Row + sorted dimSig`; the A1 fix beneficially drops dimensioned no-total widgets from its index. *No new major-severity false-positive surface.*
- **D10.** `factsVersion` stays `1` (all new fields additive); add `meta.canonicalVersion=1` as a marker. *No downstream consumer gates on exact factsVersion.*
- **D11. (NEW)** `GAP_NO_ACCOUNT_TOTAL` is **one finding per provider**, `severity=info`, rolling the affected metric ids into `evidence.metrics` (deduped, sorted, capped at 20 with an "+N more" suffix). *Caps fid/facts bloat on breakdown-heavy reports; info -> never force-surfaced -> never blocks delivery.*

---

## A1 - Fix `Total-Row` (A:120)

Replace the one-liner with:

```powershell
function Total-Row($w){
  $t=@($w.rows | Where-Object { $_.kind -eq 'total' }); if($t.Count -gt 0){ return $t[0] }
  # KPI-only fallback: the first data row IS the account total ONLY when the widget carries no dimensions.
  # A dimensioned table with no total row has NO account total here (never promote a slice).
  if(@($w.dimensions | Where-Object {$_}).Count -eq 0){
    $t=@($w.rows | Where-Object { $_.kind -eq 'data' }); if($t.Count -gt 0){ return $t[0] }
  }
  return $null
}
```

- `subtotal` rows remain never-selected (unchanged).
- The zero-dim guard uses `@($w.dimensions | Where-Object {$_}).Count` (not `@($w.dimensions).Count`) so a null/scalar `dimensions` property cannot slip through the `@($null).Count==1` trap.
- **Exact return for a dimensioned no-total table:** `$null`. Consumers already guard (`if(-not $tr){ continue|return @() }` at A:373, A:440, A:126), so they degrade to "no account total" instead of a wrong number.
- **Consumer consequences (all intended, all safer):**
  - **Headline** (A:372): a no-total dimensioned widget contributes nothing (was: its top slice). A2's gap pass surfaces this.
  - **`Get-BreakdownFindings`** (A:126): a no-total dimensioned widget now early-returns `@()`; the pre-existing `ANOM_CONCENTRATION` false positive (first data row scored 100% against itself as denominator) disappears.
  - **DISC_CROSS_WIDGET** (A:440): no-total dimensioned widgets drop out of the index (sec DISC).

---

## A2 - Headline provenance + account-total gap

### A2.1 Factor provider derivation (one source of truth)

Add once in the function region (~A:116, define-safe, pure):

```powershell
# The provider a widget's headline is attributed to. Prefer the declared provider; else the id-prefix of the
# first metric. Single source of truth for discovery, headline population, and the gap pass so they cannot drift.
function Get-WidgetProvider($w){
  if($w.providers -and @($w.providers).Count -gt 0){ return $w.providers[0].id }
  $m0=@($w.metrics); if($m0.Count -gt 0){ return ($m0[0].id -split ':')[0] }
  return $null
}
function Test-Blended($w){ return ($w.providers -and @($w.providers).Count -gt 1) }
```

### A2.2 Rewire the headline loop (replace A:367-393)

Discovery walks all data widgets and registers **every provider present on each widget** (both sides of a blended widget). **Post-build amendment:** the draft said "create `$platforms[$prov]`" from the primary provider only; that silently dropped a provider appearing ONLY as a non-primary side of a blended widget (no platform, no headline, no gap) - contradicting M3/D6 and the test-17 guarantee. Discovery therefore registers each `providers[]` entry, so such a provider still earns a platform entry (empty headline) + `GAP_NO_ACCOUNT_TOTAL`. Single-provider widgets are unaffected. Headline **population** still attributes to the primary provider (`Get-WidgetProvider`) only, skips blended widgets as a headline source (D6), and attaches `canonical{}` additively. Every pre-existing legacy field is populated **from the raw total-row cell**, byte-for-byte as today (NOT via `Row-Cur`'s `[double]` cast - so an int KPI's `current` stays an int in JSON).

```powershell
$platforms=@{}
foreach($w in $dataWidgets){
  # discovery: register EVERY provider present on the widget (each side of a blended widget), so a provider that
  # appears ONLY as a non-primary side of a blended widget still earns a platform entry + GAP (post-build fix).
  foreach($pe in @($w.providers)){
    if($pe.id -and -not $platforms.ContainsKey($pe.id)){
      $pn = if($pe.name){ $pe.name } else { $pe.id }
      $platforms[$pe.id]=[ordered]@{ id=$pe.id; name=$pn; category=(Get-Category $pe.id); headline=[ordered]@{}; hasComparison=$false }
    }
  }
  $prov = Get-WidgetProvider $w
  if(-not $prov){ continue }
  if(-not $platforms.ContainsKey($prov)){   # metric-prefix-only widget (no providers[]) discovered here
    $pname = if($w.providers -and @($w.providers).Count -gt 0 -and $w.providers[0].name){ $w.providers[0].name } else { $prov }
    $platforms[$prov]=[ordered]@{ id=$prov; name=$pname; category=(Get-Category $prov); headline=[ordered]@{}; hasComparison=$false }
  }
  if(Test-Blended $w){ continue }            # D6: never a headline source (discovery above still counted it)
  $tr = Total-Row $w
  if(-not $tr){ continue }                    # A1: dimensioned no-total -> $null -> no headline value
  $cc   = $w.currencyCode
  $dims = @($w.dimensions | Where-Object {$_})
  $isKpi= ($dims.Count -eq 0)
  $scope= if($isKpi){ 'account' } else { "table-total:$($dims[0])" }   # m1: honest scope, never bare 'account' for a table total
  $src  = if($isKpi){ 'kpi-widget' } else { 'total-row' }
  foreach($m in $w.metrics){
    $cell = $tr.metrics.$($m.name)
    if(-not $cell){ continue }
    if(-not ($cell.current -is [double] -or $cell.current -is [int] -or $cell.current -is [long] -or $cell.current -is [decimal])){ continue }
    $key = $m.id
    if($platforms[$prov].headline.Contains($key)){ continue }   # doc-order first-wins (unchanged)
    $dir   = Get-Direction $m.id
    $delta = Get-DeltaPct $cell.current $cell.compare
    $hasCmp= ($null -ne $cell.compare)
    if($hasCmp){ $platforms[$prov].headline.hasComparison=$true; $platforms[$prov].hasComparison=$true }
    $dispCur = (Format-Metric $m.id $m.unit $cell.current $cc)
    $platforms[$prov].headline[$key]=[ordered]@{
      metric=$m.name; id=$m.id; unit=$m.unit; type=(Metric-Type $m.id $m.unit $cc); direction=$dir; currency=$cc
      current=$cell.current; previous=$cell.compare; deltaPct=$delta; hasComparison=$hasCmp
      displayCurrent=$dispCur
      displayPrevious=(Format-Metric $m.id $m.unit $cell.compare $cc)
      displayDelta=(Format-Delta $delta)
      # ---- U6 provenance (additive) ----
      canonical=[ordered]@{ display=$dispCur; sourceWidgetId=$w.id; scope=$scope; period=$periods.current; source=$src }
    }
  }
}
```

- **Every pre-existing headline field is retained byte-for-byte** (`metric,id,unit,type,direction,currency,current,previous,deltaPct,hasComparison,displayCurrent,displayPrevious,displayDelta`). Only `canonical` is added. `canonical.display` reuses the same `$dispCur` string the closer already indexes, so **synthesized/derived numbers cannot appear here** and the closer needs no change.
- The closer indexes `displayCurrent/displayPrevious/displayDelta` exactly as before (C:215-217); `canonical` is ignored extra data -> **119 green** (pinned by case 22).

### A2.3 Canonical record struct

```
canonical = {
  display        # the headline display string (identical to displayCurrent)
  sourceWidgetId # the widget whose total row supplied the value
  scope          # 'account'  (zero-dim KPI widget)  |  'table-total:<dimName>'  (dimensioned total row)
  period         # meta.currentPeriod label
  source         # 'kpi-widget' | 'total-row'
}
```

A reader answers "which widget did this number come from, and is it an account total or a table total?" from `sourceWidgetId` + `scope` + `source` alone. The report template MAY render "(account total)" vs "(campaign-table total)" from `scope`; no anchor is needed because the value lives in platform scope and traces via `displayCurrent` exactly as today.

### A2.4 Observed-metrics map + `GAP_NO_ACCOUNT_TOTAL` gap pass

**Insertion point (pinned):** immediately after the GAP_WARNINGS / PROVIDER_FILTERED adds (A:405) and before the fid pass (A:482). `$platforms` and `$gaps` are both in scope here.

```powershell
# (built alongside the headline loop, before the gap pass) provider -> distinct observed metric ids,
# attributed by metric-id prefix so BLENDED widgets contribute each metric to its true owner.
$observed=@{}
foreach($w in $dataWidgets){
  foreach($m in @($w.metrics)){
    $mp=($m.id -split ':')[0]; if(-not $mp){ continue }
    if(-not $observed.ContainsKey($mp)){ $observed[$mp]=[System.Collections.Generic.HashSet[string]]::new() }
    [void]$observed[$mp].Add($m.id)
  }
}

# GAP_NO_ACCOUNT_TOTAL: one info finding per provider listing metric ids that were observed but got NO
# headline cell (all their widgets were dimensioned-no-total and/or blended). Covers M3 (blended-only provider).
foreach($prov in $observed.Keys){
  if(-not $platforms.ContainsKey($prov)){ continue }   # only discovered platforms
  $pf=$platforms[$prov]
  $missing=@($observed[$prov] | Where-Object { -not $pf.headline.Contains($_) } | Sort-Object)
  if($missing.Count -eq 0){ continue }
  $shown = if($missing.Count -gt 20){ (@($missing[0..19]) + @("+$($missing.Count-20) more")) } else { $missing }
  [void]$gaps.Add([ordered]@{
    ruleId='GAP_NO_ACCOUNT_TOTAL'; severity='info'; platform=$pf.name
    statement="no account-level total available for $($missing.Count) metric(s) of $($pf.name): only dimensioned rows with no total row (or blended widgets); metrics: $($shown -join ', ')"
    evidence=[ordered]@{ metrics=@($shown); count="$($missing.Count)" }
  })
}
```

- **Info** -> not force-surfaced -> never blocks delivery. It records the *absence* of a number, so it introduces no traceable number (the `count` is a display string in `byFid` scope, reachable only on a line echoing the fid - acceptable for an info finding).
- Both `GAP_WARNINGS` (major) and `GAP_NO_ACCOUNT_TOTAL` (info) coexist in `$gaps`; the fid pass (A:482) assigns fids to both.

### A2.5 `facts.meta`

Add exactly one field to the `meta` block (A:496-504): `canonicalVersion=1`. `factsVersion` stays `1` (D10). Nothing else in `meta` changes.

---

## DISC_CROSS_WIDGET interaction (A:435-462)

- **No code change.** DISC keeps keying on `Total-Row + sorted dimSig` and comparing raw min..max per dimSig.
- The A1 fix changes DISC's **inputs only**: dimensioned no-total widgets now yield `$null` from `Total-Row` and drop out of the index (A:440 `if(-not $tr){continue}`). Net effect: DISC compares only true totals of identical scope (zero-dim KPI cards against each other; explicit total rows against each other), **removing** the prior false positive where two no-total tables had their top slices compared.

---

## Residuals (explicit non-goals, documented per reviewer "missing" notes)

- **Cross-scope disagreement is not reconciled.** A legitimate account KPI (`$100`) and a filtered/subset table total (`$120`) for the same metric are both surfaced with honest `scope` (`account` vs `table-total:<dim>`); canonical does not flag their difference and DISC only compares identical dimSig. Adding cross-scope reconciliation would manufacture major-severity false positives across legitimately-different scopes and is out of scope. The `table-total:<dim>` scope label is the disclosure. **WONTFIX (documented).**
- **Cross-basis DISC false positive** (same metric reported in two currencies over the same dimSig -> raw min..max differ -> spurious `major`) is **pre-existing** and untouched by U6. U6's provenance does not quiet it. **WONTFIX (documented); flagged for a future DISC unit.**
- **Per-widget dateRange override.** `canonical.period` is stamped from `$periods.current`. When a winning widget carries its own dateRange, this is unchanged from today's implicit behavior (that widget already supplied the headline value). **WONTFIX (pre-existing, out of scope).**
- **Server-side silent truncation** of an explicit total row (a table total that is itself a top-N subset) cannot be detected without a completeness signal from the extractor. The `scope='table-total:<dim>'` label is the honest disclosure that it is a table total, not a proven account total. Full detection is deferred with synthesis (sec Deferred work).

---

## Deferred work (rank-3 synthesis - do NOT build in U6)

Recorded so a future unit builds it correctly. **Precondition (hard):** `Get-SwydoReport.ps1` must first emit a **positive completeness signal** per widget - e.g. server-reported total row-count vs returned row-count, or an explicit page-limit-hit flag carrying the widget id. Synthesis may proceed only when completeness is **affirmatively proven**, never merely "no warning said otherwise." When built:

- **`Test-Synthesizable`** dedup denylist must match GA4 camelCase (`google-analytics-4:activeUsers` -> `activeusers`). Use an unanchored tail: `reach|frequency|unique|impression_share|users?$` (NOT `(^|_)users?$`, which misses `activeusers`/`totalusers`/`newusers`). Add positive-refusal unit cases on those literal ids.
- **Summed rows** must reuse `Get-BreakdownFindings`' filter (A:131): `@($w.rows | Where-Object { $_.kind -eq 'data' -and -not (Test-GroupRow (Row-Label $_)) })`, and re-evaluate the `>=2 rows` gate against the *filtered* set, so an `All`/`(group)` aggregate data row cannot double-count.
- **Currency:** refuse synthesis if rows span currencies within the widget (widget currency is resolved from the first row carrying `meta.currencyCode` at G:186); sum in raw units, format once.
- **Disclosure:** a synthesized (tool-computed) total must be **force-surfaced** - either a finding with a downstream-data / requires-surfacing flag the closer honors without severity escalation, or a template contract mandating an anchor whenever `canonical.source=='synthesized-sum'`. It must never be presentable as if the platform reported it.
- **Report contract:** forbid total-minus-shown-rows remainder arithmetic (a synthesized total juxtaposed with the same widget's breakdown rows invites it; the closer would fail-close on the untraceable remainder, but the prompt should forbid it up front).
- **`basisVersion`** returns to the canonical record then, sourced from a **single define-only helper** dot-sourced by both `Analyze-SwydoReport.ps1` and `Update-SwydoLedger.ps1` (a param-only helper carries no `$From/$Into/$Execute` clobber risk), replacing the ledger's copy at L:42-51 so there is exactly one implementation.

---

## Backward-compat / migration

- **Fields that MUST remain (all retained byte-for-byte):** every existing headline field (sec A2.2), the finding record shape, all existing `facts.meta` fields, `factsVersion=1`.
- **Consumers:** closer (unchanged - reads named display fields; `canonical` is ignored extra data, pinned by case 22), ledger/trend (read `meta`/facts by name; `canonicalVersion` is additive; **ledger not touched**). No migration.
- **Documented behavior changes (audit `Test-Analyze.ps1` before claiming 135 green):**
  1. A dimensioned no-total widget no longer yields a headline value (surfaces as `GAP_NO_ACCOUNT_TOTAL`).
  2. Blended widgets no longer contribute headline values (D6); their providers surface `GAP_NO_ACCOUNT_TOTAL`.
  3. `ANOM_CONCENTRATION` no longer fires on no-total dimensioned widgets (removes the first-row-is-100% false positive).
  4. DISC no longer compares no-total dimensioned widgets.
  5. If the *only* comparison-bearing widget for a provider was a dimensioned no-total table (previously supplying a wrong top-slice comparison), `hasComparison` may flip false and the seasonality caveat may disappear for that report. Intended: a caveat about a number we no longer surface is not needed.
  - **Action:** grep existing cases that assert (1)-(5). Hypothesis: the buggy paths are untested (headline tests use KPI/total-bearing widgets), so 135 stay green after the audit; any case encoding old buggy output is updated as part of this unit (documented, not silent).

---

## PS 5.1 hazards specific to this change

- **`@($null).Count == 1` trap:** the zero-dim guard and the dim-label read both use `@($w.dimensions | Where-Object {$_})`, never raw `$w.dimensions[0]` / `@($w.dimensions).Count`.
- **`[double]` cast changing JSON:** legacy `current`/`previous` are populated from the **raw** total-row cell (`$cell.current`), NOT from `Row-Cur` (which casts to `[double]`), so an int KPI's `current` stays an int in JSON - byte-identical to today (pinned by case 20).
- **Case-insensitive name collisions:** new locals `$dims`,`$isKpi`,`$scope`,`$src`,`$observed`,`$missing`,`$shown`,`$mp` are function/script-scoped in the execution body; none share a name with a dot-sourced script's param. No new helper param is named `$Facts`/`$From`/`$Into`/`$Execute`.
- **Single-element unwrap:** `$missing` is always `@(...)`-wrapped before `.Count`/indexing; `evidence.metrics` is `@($shown)`.
- **`Get-WidgetProvider`/`Test-Blended`** take everything as params -> define-safe for `-DefineOnly` dot-source (they run in unit tests without executing the body).
- **`ConvertTo-Json -Depth 40 -Compress`** (A:508) already covers the shallow `canonical` nesting; no depth change.
- **No dot-source of `Update-SwydoLedger.ps1`** (its param block would clobber caller vars); U6 does not need it (no `Get-BasisVersion`).

---

## Test plan (`Test-Analyze.ps1`, additive on 135)

**Total-Row / A1 (`-DefineOnly` unit)**
1. Dimensioned table, no total row -> `Total-Row` returns `$null` (regression guard for the live bug).
2. Zero-dim KPI widget, one data row -> returns that row.
3. Dimensioned table WITH an explicit total row -> returns the total row (unchanged).
4. Dimensioned widget with only subtotal + data rows -> returns `$null` (subtotal never selected; no KPI fallback).
5. Widget with `dimensions=$null` and one data row -> treated as zero-dim, returns the data row (the `@($null)` trap does not promote a phantom dimension).

**Helpers (`-DefineOnly` unit)**
6. `Get-WidgetProvider`: declared provider wins; else first-metric prefix; `$null` when neither.
7. `Test-Blended`: `$true` for `providers.Count -gt 1`, `$false` for single/zero.

**End-to-end body (write minimal `schemaVersion:2` extraction to a temp file, run `Analyze-SwydoReport.ps1 -InFile <tmp> -OutDir <tmp>`, read back `*.facts.json`)** - this is the coverage the draft lacked (M5).
8. **Slice-promotion regression:** a dimensioned no-total widget whose top slice value is large (>= 1000) -> that value appears in **no** traced scope: no headline cell for the metric, and `GAP_NO_ACCOUNT_TOTAL` is emitted. (Guards the bug at the emitted-facts layer, not just `Total-Row`'s return.)
9. Zero-dim KPI widget -> headline cell present; `canonical.scope='account'`, `canonical.source='kpi-widget'`, `canonical.sourceWidgetId` = the widget id.
10. Dimensioned widget WITH a total row -> headline cell present; `canonical.scope='table-total:<dim>'`, `canonical.source='total-row'` (m1: never bare `account`).
11. Two widgets for the same `(prov,metricId)` (a KPI card and a dimensioned total-row widget) -> **document-order first-wins** decides `sourceWidgetId` (D3/D4: no rank reordering); assert the first-in-order widget supplied the value.
12. Every headline cell carries `canonical{ display, sourceWidgetId, scope, period, source }` and `canonical.display == displayCurrent`.
13. `canonical` contains **no** `value`, `basisVersion`, or `synthesizedFrom` keys (m2/M4/D8).
14. `facts.meta.canonicalVersion == 1` and `facts.meta.factsVersion == 1` (unchanged).
15. `GAP_NO_ACCOUNT_TOTAL` is emitted with `severity='info'`, carries a `fid` (assigned by the A:482 pass), and `evidence.metrics` lists the affected metric id(s).
16. **Cardinality/dedup:** a provider with many no-total-only metrics -> exactly **one** `GAP_NO_ACCOUNT_TOTAL` for that provider, `evidence.count` = full count, `evidence.metrics` capped at 20 with a `+N more` sentinel (D11).
17. **Blended-only provider (M3/D6):** a two-provider blended widget where provider B appears only there -> B is discovered as a platform, its headline is empty, and a `GAP_NO_ACCOUNT_TOTAL` names B's metric(s); B's widget never appears as any `canonical.sourceWidgetId`.
18. **DISC unchanged:** two zero-dim KPI widgets that disagree still fire `DISC_CROSS_WIDGET` (major); two dimensioned no-total widgets whose top slices differ do **not** fire (they drop out via A1).
19. `Get-BreakdownFindings` no longer emits `ANOM_CONCENTRATION` for a dimensioned no-total widget (behavior change #3).

**Byte-identical / regression (body)**
20. An int-valued KPI metric -> emitted `current` is still an integer in JSON (not `1000.0`) and `displayCurrent` is byte-identical to a pre-U6 golden string (proves legacy fields come from the raw cell, not `Row-Cur`'s `[double]`).
21. Seasonality caveat (behavior change #5): a report whose only comparison-bearing widget is a dimensioned no-total table -> after A1, `hasComparison` is false and no seasonality caveat is emitted; assert this is the intended output (documented, not a bug).

**Cross-suite**
22. **Closer graceful-ignore pin:** run the closer against a `facts.json` carrying `canonical` on every headline cell; assert 119 green and that `displayCurrent` still traces (the closer ignores the `canonical` key).
23. Full existing `Test-Analyze` suite (135) re-run green after the sec Backward-compat audit (update any case encoding a documented behavior change; expectation: none must change).
24. Closer (119), Extractor (94), Archive (94), TrendFacts (19), Ledger (50), TrendAnalyze (24), Sync (4) re-run green (no code touched outside Analyze; guards against accidental shared-helper edits).

---

## For the reviewer (adversarial, v2)

- **D5/D4 deferral is the load-bearing call.** v2 ships the *bug fix* (A1) + *honest provenance* (A2) and defers *synthesis*. The claim is that a disclosed `GAP_NO_ACCOUNT_TOTAL` is strictly safer than a tool-invented total behind a guard that is provably inert against the current extractor. If a reviewer believes rank-3 synthesis is required for U6 to be useful, the counter is sec Deferred work's hard precondition: it cannot be built safely until `Get-SwydoReport.ps1` emits a positive completeness signal, which is itself a separate unit.
- **`scope='table-total:<dim>'` (m1)** is the only disclosure that a dimensioned total row may be a filtered subset. It is provenance, not a finding - no force-surface. Is a passive label sufficient, or should a dimensioned total-row headline also carry an info finding? v2 says label-only (a platform's own reported total row is far less suspect than a tool-computed sum, and an extra finding per table-total metric would bloat facts).
- **D11 cap at 20 metrics per provider [USER-FACING]:** is one rolled-up info finding per provider the right granularity, or should each `(provider, metric)` gap be individually anchorable? v2 chose the roll-up to bound fid/facts growth on breakdown-heavy reports.
- **Winner selection is deliberately unchanged (D3/D4).** The draft's rank precedence (prefer a true KPI over a doc-earlier table total) is a real correctness improvement that v2 declines in order to keep the common path byte-identical and the 135 green undisturbed. Confirm this deferral is acceptable, or promote it to its own follow-up unit.

The single largest risk remains **severity calibration**: `GAP_NO_ACCOUNT_TOTAL` is `info` by design so a mis-tuned gate can never emit a false `major` and block delivery; and because v2 ships no synthesis, there is no tool-computed number that could be mis-disclosed at all.

---

*Spec file to write on build:* `C:/projects/swydee/docs/specs/canonical-total-spec.md`. *All code edits land in* `C:/projects/swydee/skill/scripts/Analyze-SwydoReport.ps1`; *new tests in* `C:/projects/swydee/Test-Analyze.ps1`. *No other shipped script is modified.*