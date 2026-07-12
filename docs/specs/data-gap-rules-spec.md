# U10 - Data-gap anomaly rules: cost-ranking-without-value + branded-baseline-suspect (spec v1)

## AMENDMENTS v1 (post adversarial review, 2026-07-12 — these OVERRIDE the body below)

Review verdict: **GO-WITH-CHANGES** (correctness GO-WITH-CHANGES - discipline GO-WITH-CHANGES - fatigue GO-WITH-CHANGES).

- **Correctness + fatigue must-fix (rule (a) statement template is factually wrong in two of its own firing branches — rewrite it; both lenses hit the same sentence, resolved as ONE template change):** (1) *Correctness:* when a widget is rankable only via the cost+outcome PAIR, the D5 fallback (body lines 104-106) pushes raw SPEND display names (`Cost`, `Amount spent`) into `rankingMetrics`, and the statement then calls them "Cost-per-result comparisons" — factually wrong on the live QCU extraction (the Google keyword widget contributes `Cost`, the FB ad-preview widget contributes `Amount spent`). (2) *Fatigue:* in the E4 branch (value column present but all cells 0/null — a branch D3 deliberately fires on) the clause "no conversion-value, revenue, or ROAS metric measured" is untrue: the metric IS measured, it is just zero. Both errors land verbatim on the force-surfaced line — statement accuracy is this unit's whole point. Prescribed fix: `rankingMetrics`/the parenthetical list ONLY explicit cost-per-outcome display names (D2(iii) explicit-pattern hits); pair-only surfaces are covered by a generic digit-free phrase (e.g. "and tables pairing cost with conversions/leads") — never label a spend column as a cost-per-result metric; and reword the value clause to be true in both branches: "with no positive conversion-value, revenue, or ROAS recorded". The rewritten statement must keep the literal word `downstream` (closer 3c, C:67-69) and stay digit-free in the <=6-name case. Update tests 20/22's statement assertions accordingly.
- **Correctness must-fix (D3: `target_`-prefixed ids silently suppress rule (a)):** the unanchored `roas` in `Test-ValueMetricId` matches a `target_roas` metric-part, and Google Ads exposes a "Target ROAS" column (the live campaign widget already carries the adjacent `Bidding strategy status` dim). A target is a bid SETTING (> 0 by construction, e.g. 3.5), not measured downstream value — if surfaced, the D3 `> 0` scan marks value "measured" and `GAP_COST_RANKING_NO_VALUE` disappears while the report stays value-blind, the exact failure direction D3 claims to err against. Fix: guard `if($p -match '(?i)(^|_)target'){ return $false }` before the value-pattern test (no legitimate value id contains `target`). Add FALSE unit cases `google-adwords:target_roas`, `google-adwords:target_cpa` to test group 2.
- **Fatigue must-fix (D3: `value_per_conversion` token misses `value_per_all_conversions` — false forced caveat despite measured value):** the real Google column `value_per_all_conversions` ("All conv. value / conv.") matches NO token in the D3 pattern (`value_per_conversion` is not a substring; `(^|_)value$` fails; `conversions?_value` fails), so a widget carrying only that per-conversion value column fires the major forced caveat with a false claim. Fix: widen the token `value_per_conversion` -> `value_per_` (unambiguously a value signal in ads taxonomies) and add a TRUE case `google-adwords:value_per_all_conversions` to test group 1. Cheap hardening folded in from the correctness residuals: also add `return_on_ad_spend` to the pattern (spelled-out ROAS, Bing/Microsoft convention). Resulting predicate: target-guard first, then `'conversions?_value|conversion_value|action_?values?|value_per_|(^|_)value$|revenue|roas|return_on_ad_spend'`.
- **Correctness must-fix (S3 phrase check lacks the token boundary its own sibling helper uses):** `$norm.Contains($tokens.phrase)` (body lines 148-151) is a raw substring — client "Metro Bank" fires on campaign "Metro Bankers Golf Promo" (`metro bankers golf promo` contains `metro bank`), contradicting D6's "near-zero FP by construction" claim, while `Get-MatchedBrandToken` right next to it deliberately pads `' $t '`. Fix: `(' '+$norm+' ').Contains(' '+$tokens.phrase+' ')`. Add a FALSE case ("Metro Bankers Golf Promo" vs client "Metro Bank") to test group 9.
- **Correctness must-fix (S2 lookahead misses hyphenated "Brand-New"):** `(?!\s+new\b)` requires whitespace, but `\bbrand\b` matches in `Brand-New Auto Loans Sale` (hyphen is a word boundary) and the lookahead sees `-New`, not `\s+new` — the exact idiom F1 exists to exclude fires. Fix the lookahead to `(?![\s_-]+new\b)` (supported identically in PS 5.1 .NET regex) in both D6/S2 and `Test-BrandLabel`, and add `Brand-New Auto Loans Sale` to tests 9 and 14.
- **Discipline must-fix (compat audit's "No existing field changes" claim is false on >20-campaign accounts — disclose, don't redesign):** rule (b)'s quoted campaign labels ride the shipped `$plLabels` force-include pass (A:757-763), which appends finding-referenced rows to an existing platform breakdown past the top-20 cap and changes that breakdown's `shown` count and `note` string ("showing top N of M"). On the live 8-row QCU widget nothing changes, but the body line 236 claim "identical facts except ... No existing field changes" is false in general. The mechanism is precedented (every anomaly rule's quoted labels do this), so amend the compat audit to state that rule (b) may enlarge an existing breakdown's rows/`shown`/`note` via the shipped force-include; keep test 25 as the pin.
- **Discipline must-fix (test 30's byFid-scoping pin is unassertable as written — rewrite it):** the widget total (`860.9`) becomes a table-total headline cell and a breakdown-row display, both registered in the closer's byPlatform candidates (C:206-243), so it TRACES on a non-anchored line and produces no violation. Only the tool-derived numbers — the `47%` share and the `404.3` matched-set sum — are byFid-only (C:244-252). Rewrite the pin to assert `untraceable-number` on `47%` and `404.3` specifically (never on the widget total); as written the case fails on build and invites assertion-weakening under time pressure.
- **Discipline must-fix (D9 call-site audit count is wrong: 10, not 40):** `Test-Analyze.ps1` has **10** direct `Get-BreakdownFindings` calls (lines 114, 122, 130, 138, 144, 151, 158, 165, 173, 264 — re-verified by grep during this fold). The substantive conclusion survives (all pass one argument; optional `$clientName` binds `$null`; S1/S2 stay live), but this audit protects the 276-green contract, so the count must be correct and its measurement method stated. Read every "40 existing direct calls" in the body as 10.

**Residuals (documented, accepted):**
- **Taxonomy is one account deep.** LinkedIn-style camelCase ids (`costperlead`, `costinlocalcurrency`, `oneclickleads`) match neither the D2 cost nor outcome patterns — rule (a) is silent on a LinkedIn campaign table. Failure direction is silence; widen only with a green-count audit in a later unit. (`return_on_ad_spend` is folded into the must-fix above.)
- **"Day of the week" dims are invisible to both rule (a) and time series:** D2(i)'s unanchored `day` excludes them from rankability while `Get-TimeSeries`' anchored pattern also rejects them — a weekday CPL ranking (two such widgets exist in the live facts) is disclosed by nothing. Silent direction; live reports carry campaign tables; consistent with `Get-Breakdown`'s `$isTime`.
- **The live invariants `404.3`/`860.9` are display-string sums** (the archive carries no raws; the headline conversions raw is 860.879162, so a raw-sum display could read 404.2/404.4). Test 26 defines its own fixture and is deterministic — do not treat `404.3` as a live-raw regression pin. Related: "`PMax Quincy General` alone is 25.0%" is a rounding artifact (214.9/860.879 = 24.96%, strictly BELOW the 25.0 gate); only the combined-set 47% clears the D7 gate, which is the specced semantics.
- **The "statement contains no digits" claim is conditional:** >6 ranking-metric names injects `+N more` (a digit). Harmless (small bare integers are not measures per `Get-MeasureTokens`; byFid self-traces the statement anyway) — soften the D4 claim and scope test 20's `-notmatch '\d'` assertion to its <=6-name fixture.
- **D8 prose says `requiresDownstreamData=$false` but the build shape omits the key** — align the prose to the code (omit it, like `ANOM_CONCENTRATION`; closer 3a tests `-eq $true`, semantics identical) so the builder does not "fix" the divergence in the wrong direction.
- **Rule (a) fires on effectively every value-less lead-gen ads report forever — by ratified design** (G:6/G:36), capped at one forced line, self-healing when value tracking appears; same posture as the seasonality caveat. Severity stays `major`: forcing comes from `requiresDownstreamData` either way (C:420), so major-vs-info changes nothing about the forced line count, and `major` is taxonomy-honest (S:214). Do not "fix" the permanence in a future session.
- **Reviewer questions ruled with the fatigue lens:** E5 (KPI-only cross-platform cost-per comparison) stays a residual — do NOT add the zero-dim trigger floated in the body (it would fire on virtually every ads KPI strip). E4 (tracked-but-zero value quarter still fires) stands — defensible, and the reworded statement is now true in that branch. D8 non-forcing stands — no >=50% escalation ("PMax harvests brand demand" is a domain prior, not a measured fact, and the 3c downstream clause is semantically wrong for brand-split caveats). D2's pair trigger stands as specced.
- **Rule (a)'s outcome regex misses `google-adwords:all_conversions`** (the `_` before `conversions` defeats `(^|:)conversions?$`) — a Cost + All conv. table does not trigger. Under-trigger on a house-precedent pattern (A:318-320); accept.
- **Blended widgets:** never rankable for rule (a) (R6 convention), and rule (b) attributes a blended campaign table to `providers[0]` (pre-existing `Get-Breakdown` behavior) — silent FN/mis-attribution directions. A `Campaign, Bidding strategy status` widget can list the same campaign twice in rule (b)'s evidence (both rows are real slices; sums stay honest) — cosmetic.
- **`brandToken='quincy'` on "the live QCU data" (body line 201) overstates:** the archived facts have `meta.client=''` (verified), so S3/annotation need a fresh U1-era extraction populating `report.client`. Test 26 must pass `$clientName` explicitly rather than relying on the archive; F7 already covers the mechanics.
- **Margin FN/FP accepted at info severity (F12 posture):** `Test-PMaxLabel` misses "Perf Max" and en-dash-inside-token "P–Max"; S2 fires on possessives ("Brand's Best") and off-target names ("Co-Branded Visa", a dominant "Brand Awareness" prospecting campaign) where "harvest existing brand demand" is imprecise. Optional polish: soften to "brand-related campaigns whose conversions may reflect existing brand demand".
- **`$BrandSharePct=25.0` is single-account calibration** — acceptable for an info-severity advisory rule. The largest-single-contributor evidence field is YAGNI (the force-included breakdown rows already show the split) — skip it. The annotation-only token tier (`Get-BrandTokens` abbr/lead + `Get-MatchedBrandToken`) structurally cannot cause firings; keep-or-cut at builder discretion (if cut, tests 7/10/16's brandToken assertions go with it).
- **Two harmless mechanics, named so nobody "fixes" them:** the `+N more` cap suffix inside rule (b)'s statement is swept by the A:758 `$plLabels` regex as a quoted label — it matches no row and is a no-op; a platform with two campaign-dim widgets (e.g. `Campaign` and `Campaign, Month`) can emit two near-duplicate info findings — bounded, per-widget, unforced. A hand-entered `manualKpi` value metric with `current > 0` would suppress rule (a) for its provider — document if manual KPIs ever appear in ads sections.

---

**Status:** SPEC (reviewed 2026-07-12, verdict GO-WITH-CHANGES). Extends `docs/specs/context-and-canon-spec.md`; same discipline (PS 5.1/.NET Framework, pure-ASCII script source, functions-first + `-DefineOnly` dot-sourcing, hardened scripts never behaviorally modified, default single-report output path byte-for-byte unchanged - every change additive-in-facts, every credential path fail-closed, the model does no arithmetic and every number traces through `skill/scripts/Test-ReportNumbers.ps1`).

**Blast radius (one commit/review boundary):** `skill/scripts/Analyze-SwydoReport.ps1` ONLY (additive pure helpers + two additive findings + one additive param + one additive argument at an existing call site). New tests in `Test-Analyze.ps1`. The unit commit also adds the U10 row to the units index in `docs/specs/context-and-canon-spec.md` and flips this spec's Status line. **FORBIDDEN to change:** `skill/scripts/Test-ReportNumbers.ps1` (closer), `skill/scripts/Get-SwydoReport.ps1`, `skill/report-template.md`, `skill/SKILL.md`, `skill/scripts/ConvertTo-SwydoTrendFacts.ps1`, `Update-SwydoLedger.ps1`, `Manage-SwydoArchive.ps1`, `Sync-SwydoTrend.ps1`, `Analyze-SwydoTrend.ps1`, and every Test-*.ps1 suite other than `Test-Analyze.ps1`.

**Green-count contract (board measured 2026-07-11 on `main` @ `cccd0c9`, all suites `0 failed`):** Analyze **276**, Closer **119**, Extractor **94**, Archive **94**, Ledger **50**, Sync **4**, TrendAnalyze **24**, TrendFacts **19**. U10 is **additive on Analyze 276 only**; every other suite re-runs green with its count untouched (no file outside Analyze/Test-Analyze is edited).

---

## Problem (what these two rules protect against)

`data_gaps.md` Tier 1 names the two gaps that "undermine every conclusion" and closes by proposing exactly these rules (G:36: *"flag cost-per-lead rankings when no funded-value field is present"*, *"flag branded-PMax conversions as baseline-suspect"*):

1. **Cost rankings without downstream value** (G:5-8): the QCU report ranks HELOC's `$9.83` CPL "efficient" and Auto Loans' `$21.06` "least efficient", but *"a $21 lead that funds a $30k auto loan destroys a $9 lead that never applies. Without funded-value, cheap-CPL is a vanity ranking."* The closer guarantees the numbers are real; nothing guarantees the *ranking framing* is disclosed as value-blind.
2. **Branded/PMax baseline** (G:10-13): *"Google's cheapest, highest-volume campaign, 'PMax Quincy General' ($2.48 cost/conv, 7,394 clicks), is almost certainly harvesting branded/existing-member demand - people who'd convert anyway. Counting it as 'driven' over-credits the campaign."*

Evidence from the live data (`skill/archive/quincy-credit-union/2026-07-06-19-45-59/QCU_Q2_2026_causal_report.facts.json`):

- **No value metric exists anywhere in the extraction.** All 25 Google headline ids (`impressions`, `conversions`, `cost_per_conversion`, `cost_micros`, `view_through_conversions`, ...) and all 14 Facebook ids (`spend`, `actions::lead`, `costPerActionType::lead`, ...) lack any `conversions_value` / `revenue` / `roas` / `actionValues` id. Rule (a) fires on this report - correctly.
- **Campaign-name grounding for rule (b):** the Google campaign widget (`jgr4gfKAGeGfZT9Xd`, dims `Campaign, Bidding strategy status`) carries `inS - PMax - Quincy General` (conv 214.9), `inS - PMax - Mortgages` (111.6), `inS - PMax - Visa Traditional Card` (40.5), `inS - PMax - HELOC` (34.3), `inS - PMax - Hanover` (3), against a 860.9 conversions total. The PMax set is **404.3 / 860.9 = 47%** of conversions; `PMax Quincy General` alone is **25.0%**. (Threshold calibration in D7 rests on these numbers.)
- The FB campaign widget's `General QCU - Awareness Video` carries the client abbreviation but no PMax/brand word - it is deliberately NOT a rule (b) firing case (F-cases below); its cheap-CPL skepticism is already carried by `ANOM_SHARE_MISMATCH`'s awareness-hint downgrade (A:205).

**The forced-caveat machinery already exists and is reused unchanged:**
- Closer check 3a (C:414-427): a finding with `severity in (major|critical|high)` **or** `requiresDownstreamData -eq $true` (C:420) MUST echo its fid as `<!-- finding:<fid> -->` or the report fails, fail-closed.
- Closer check 3c (C:458-460): a surfaced `requiresDownstreamData` finding must be accompanied by a downstream/lead-quality clause matching `$DownRx` (C:67-69, includes the word `downstream`).
- byFid candidate index (C:244-252): `Add-StringNumbers` registers every number in a finding's `statement` **and** every `evidence.*` string, scoped to lines echoing that fid - so a finding's numbers trace iff they are pre-formatted display strings inside the finding itself.
- Template hard rules 3/4 (T:20-21) already instruct the model to surface every sev>=major gap and attach the confirm-downstream clause to every `requiresDownstreamData` finding. **No template change is needed.**

## Ratified decisions

- **D1. Two additive rules, existing carriers only.** Rule (a) = `GAP_COST_RANKING_NO_VALUE`, a `dataGaps` finding; rule (b) = `ANOM_BRAND_BASELINE`, an `anomalies` finding. No closer edit, no template edit, no facts-schema/meta change (`factsVersion` stays 1, no new meta marker - the findings are self-describing and no downstream consumer gates on a version). *The unit scope is CLOSED to "two rules in Analyze, additive findings only"; every guarantee needed (forced surfacing, downstream clause, number tracing) is already mechanized in the closer and template.*

- **D2. Rule (a) trigger = a "rankable cost surface" exists (pure predicate `Test-RankableCostWidget`).** A widget is rankable iff ALL of: (i) it has >= 1 dimension (`@($w.dimensions | Where-Object {$_})`, the A1/U6 null-safe form) whose first dimension does NOT match the time pattern `'(?i)day|week|month|date'` (same pattern as `Get-Breakdown`'s `$isTime`, A:271); (ii) >= 2 detail rows after the standard group-row filter (A:161 form); (iii) it carries EITHER an explicit cost-per-outcome metric - metric-part regex `'cost_per_conversion|cost_per.*lead|costperactiontype::lead|(^|_)cpa$|(^|_)cpl$'` - OR both a cost metric (`'cost_micros|(^|_)cost$|spend|amount_spent'`, superset of the ads RuleCfg effort pattern A:42) and an outcome metric (`'(^|:)conversions?$|(^|_)lead|actions::lead'`, the union of the patterns already used at A:318-320). *A breakdown with cost and outcomes lets the report rank campaigns by implied cost-per-result even without an explicit CPL column; a time-only breakdown is a trend, not a ranking (E6); a lone KPI card ranks nothing (E5). `costPerActionType::link_click` is deliberately NOT cost-per-outcome - its denominator is a click, not a lead/conversion (same reasoning that excluded it from ratio reconciliation, A:394-397).*

- **D3. Rule (a) suppression = "value measured" is decided per platform, presence AND signal (pure predicate `Test-ValueMetricId` + a `> 0` cell scan).** `Test-ValueMetricId($id)`: metric-part matches `'conversions?_value|conversion_value|action_?values?|value_per_conversion|(^|_)value$|revenue|roas'`. Grounded in the taxonomy: catches `google-adwords:conversions_value`, `all_conversions_value`, `value_per_conversion`, `facebook-ads:actionValues::<action>` (part `actionvalues::...`), `purchase_roas`/`websitePurchaseRoas` (contain `roas`), `shopify:revenue`; rejects every id present in the live QCU extraction (verified: none of the 39 observed ids match) and the near-misses `active_view_non_viewable_impression_rate`, `costPerActionType::lead`, `search_lost_is_budget`. Value counts as **measured** for provider P iff some data widget carries a `Test-ValueMetricId` metric whose id-prefix is P (prefix attribution, same convention as the U6 `$observed` map A:664-671, so a blended widget contributes value metrics to their true owner) AND at least one row cell for it has numeric `current > 0` (via `Row-Cur`, scalar-guarded). *Presence alone is not enough: a configured-but-broken value column (all zero/null) still leaves CPL rankings value-blind, so it must NOT suppress (E4). The `> 0` rule is deterministic and errs toward disclosure; a legitimately zero-value period genuinely has no value signal to rank by.*

- **D4. Rule (a) severity/cardinality: `severity='major'`, `requiresDownstreamData=$true`, emitted AT MOST ONCE PER REPORT.** One rolled-up finding listing the affected platforms (an ads platform is affected iff it has >= 1 rankable non-blended widget AND value is not measured for it, per D3). Zero affected platforms => no finding. The statement is a fixed template containing **no digits** (asserted by test) so it can never fail tracing; it contains the literal word `downstream` so quoting it satisfies `$DownRx` (C:67-69) on the anchored line. *Every value-less ads report will fire this forever, by ratified design ("the report cannot present CPL rankings as decision-grade") - exactly like the seasonality caveat fires on every adjacent-period comparison (A:775-783). Cardinality one-per-report caps the fatigue at a single forced line; per-platform or per-widget emission would multiply forced lines with no added information. `requiresDownstreamData` is the semantically exact flag (S13.3 already mandates it "on cost-per-outcome / efficiency-spread findings", S:214); `major` additionally routes it through template rule 4 (T:21). The finding disappears the day the client's value tracking appears in the report - it is a self-healing nag, not a permanent one.*

- **D5. Rule (a) placement + evidence.** Runs in the body immediately after the `GAP_NO_ACCOUNT_TOTAL` pass (insertion point: after A:683, before the per-platform win/loss loop A:684-700), where `$dataWidgets`, `$platforms`, and `$gaps` are all in scope; appended to `$gaps` so the existing fid pass (A:769-771) assigns `GAP_COST_RANKING_NO_VALUE#1`. Evidence fields are **flat strings only** (the closer stringifies each `evidence.*` value, C:252; arrays/objects would stringify to garbage): `platforms` = display names joined `', '`; `rankingMetrics` = distinct ranking-metric display names (e.g. `Cost per Lead, Cost / conv.`), deduped, capped at 6 with a `+N more` suffix (D11 precedent, A:677). No numbers in evidence. Finding shape mirrors S5.5 (`ruleId/severity/statement/evidence`, S:80-81); `platform` key omitted (multi-platform finding, like `GAP_WARNINGS`/`PROVIDER_FILTERED`).

- **D6. Rule (b) firing signals are three deterministic, name/type-level tests - fuzzy client-name tokens NEVER gate firing.** A campaign row is brand-demand-suspect iff its label matches:
  - **S1 (PMax type-marker):** `Test-PMaxLabel` - regex `'(?i)((^|[^a-z])p[\s._-]?max([^a-z]|$))|performance[\s._-]*max'`. Performance Max serves on branded queries by default and its conversions cannot be split brand/non-brand in this data - the campaign TYPE is the signal, no name token required. The `(^|[^a-z])` boundary kills `TopMax`/`CompMax` (F2).
  - **S2 (self-declared brand):** label matches `'(?i)\bbrand(ed)?\b(?!\s+new\b)'`. A campaign that names itself "Brand" is brand-targeted by its own declaration; the lookahead kills the "Brand New ..." idiom (F1). Word-boundary anchored, so `Rebranding` does not match (F10) - strictly tighter than the shipped `campaignNameHint` substring at A:205.
  - **S3 (full client name):** the label, punctuation-normalized and lowercased, contains the full multi-token client name phrase from `meta.client` (parentheticals stripped) - near-zero FP by construction.
  Derived brand tokens (parenthetical abbreviations like `QCU`, and the lead token like `Quincy`) are **annotation-only**: `Get-MatchedBrandToken` enriches `evidence.brandToken` on a row that already fired via S1-S3, and can never cause a firing. **Delta vs the task brief (repo wins):** brand tokens are NOT derived via `Manage-SwydoArchive.ps1`'s `Normalize-ClientName` (M:70). Dot-sourcing Manage into Analyze would execute Manage's param block (`$From/$Into/$Execute/$Client`) in Analyze's scope - the exact clobber hazard the U6 spec banned for `Update-SwydoLedger.ps1` - and it is unnecessary anyway: `meta.client` is the Swydo client ENTITY name (`report.client`, G-extractor:441; live value `"Quincy Credit Union"`, probed in context-and-canon-spec:32), which carries none of the report-title boilerplate Normalize-ClientName exists to strip. A tiny pure `Get-BrandTokens` local to Analyze is the correct shape. *This resolves the generic-English-word problem head-on: for a client named "First National Bank", the tokens `First/National/Bank` can annotate but never fire; firing requires PMax, a literal "brand" self-declaration, or the full phrase "first national bank" in the label (F4).*

- **D7. Rule (b) dominance gate: the MATCHED SET's combined share of the widget's outcome total must be >= `$BrandSharePct` (default 25.0), computed on raw values against the widget's `Total-Row`.** Outcome metric = first match of `'(^|:)conversions?$'`, else `'(^|_)lead|actions::lead'`. Matched rows contribute only when their outcome value is `> 0`. One rolled-up finding per widget (not per row), labels capped at 5 with `+N more`. If the matched set's raw outcome sum `< $SmallN` (30, the existing param A:23) the finding is tagged `confidence='low'` (S13.3 small-N convention). *Calibration is grounded, not guessed: in the live data the named target (`PMax Quincy General`) is 25.0% of conversions and the PMax set is 47% - a single-row 30% gate would MISS the exact case `data_gaps.md` names, while the combined-set-at-25% gate catches it and also matches the ratified wording ("totals DOMINATED BY campaignS", plural). Below the gate, brand harvesting cannot materially distort the total and silence is correct.*

- **D8. Rule (b) severity/routing: `severity='info'`, `requiresDownstreamData=$false`, appended to `$anoms` - NOT force-surfaced.** *The ratified scope says baseline-suspect CONTEXT, "not proof of driven demand" - info is the calibrated severity for observations (`ANOM_CONCENTRATION`, `ANOM_SEGMENT_DIVERGENCE`, downgraded `ANOM_SHARE_MISMATCH` are all info). Reusing `requiresDownstreamData` to force it would also force the WRONG clause: the closer's 3c clause is downstream/lead-quality (C:67-69), but the honest caveat here is brand/non-brand split - forcing a semantically wrong sentence is worse than advisory context. The statement text itself carries the baseline-suspect framing, and the causal-verb rules (S:217, T:15) independently stop "drove" claims. Escalation is a named reviewer question.*

- **D9. Rule (b) placement: inside `Get-BreakdownFindings`, after the share-mismatch block (insert between A:209 and the `return` at A:211), gated `if($wcat -eq 'ads' -and $dimName -match '(?i)campaign')`.** `Get-BreakdownFindings` gains an optional second parameter: `function Get-BreakdownFindings($w,$clientName)`; the single call site (A:754) becomes `Get-BreakdownFindings $w $doc.report.client`. All 40 existing direct calls in `Test-Analyze.ps1` pass one argument and keep working (`$clientName` binds `$null` => S3/annotation tiers disabled, S1/S2 still live). *Row-level, per-widget, category-gated, pure over `($w,$clientName)` - the same machinery and testability every other breakdown rule uses. The campaign-dim gate keeps device/keyword/location tables out (F8); the ads gate is the S13.8 fail-closed `appliesToCategories` convention (E7). The widget-with-no-total case already early-returns at A:156 (U6/A1), so the share denominator is always an honest total row (F9).*

- **D10. Both rules quote numbers ONLY as pre-formatted display strings produced by the existing formatters.** Rule (b)'s three numbers: `share` = `"$([math]::Round($share*100,0))%"` (the A:166/A:202 house pattern), `matchedTotal` = `Format-Metric $om.id $om.unit $msum $cc`, `total` = `Format-Metric $om.id $om.unit $tot $cc`. The identical strings appear in the statement and in `evidence`, so byFid registration (C:244-252) makes them trace on the fid-anchored line; the labels quoted in single quotes inside the statement are automatically force-included into the platform's breakdown table by the existing `$plLabels` pass (A:757-758), so a reader can see the flagged rows. Rule (a) quotes no numbers at all. *Tool-computed sums in findings are established practice (`RECON_ROW_REMAINDER`'s `other`, DISC sums); template rule 2's no-hand-summing ban binds the model, not the tool.*

- **D11. One additive param: `[double]$BrandSharePct = 25.0`** appended to the param block after `$SmallN` (A:23). *Thresholds-as-tunable-params is the shipped convention (`$WinLossPct`, `$SmallN`); the default preserves behavior for every existing caller (all tests and SKILL.md invoke without it).*

---

## Rule (a) - `GAP_COST_RANKING_NO_VALUE` (exact build shape)

New pure helpers (define-safe, in the helper region near `Find-Metric` A:128):

```powershell
# U10/D3: does this metric id measure downstream value (conversion value / revenue / ROAS)?
function Test-ValueMetricId($id){
  $p = Get-MetricPart $id
  return [bool]($p -match 'conversions?_value|conversion_value|action_?values?|value_per_conversion|(^|_)value$|revenue|roas')
}
# U10/D2: does this widget expose a cross-row cost-efficiency ranking surface?
function Test-RankableCostWidget($w){
  $wdims=@($w.dimensions | Where-Object {$_}); if($wdims.Count -eq 0){ return $false }
  if($wdims[0] -match '(?i)day|week|month|date'){ return $false }
  $detail=@($w.rows | Where-Object { $_.kind -eq 'data' -and -not (Test-GroupRow (Row-Label $_)) })
  if($detail.Count -lt 2){ return $false }
  if(Find-Metric $w 'cost_per_conversion|cost_per.*lead|costperactiontype::lead|(^|_)cpa$|(^|_)cpl$'){ return $true }
  $costM=Find-Metric $w 'cost_micros|(^|_)cost$|spend|amount_spent'
  $outM =Find-Metric $w '(^|:)conversions?$|(^|_)lead|actions::lead'
  return [bool]($costM -and $outM)
}
```

Body pass (insert after A:683):

```powershell
# U10 rule (a): cost-per-result rankings with no measured downstream value (data_gaps.md Tier 1.1).
# ONE finding per report, listing every affected ads platform. Value attribution is by metric-id
# prefix (blended widgets contribute value metrics to their true owner, like the $observed map).
$valueProv=@{}
foreach($w in $dataWidgets){
  foreach($m in @($w.metrics)){
    if(-not (Test-ValueMetricId $m.id)){ continue }
    $mp=($m.id -split ':')[0]; if(-not $mp -or $valueProv[$mp]){ continue }
    foreach($r in @($w.rows)){ $v=Row-Cur $r $m.name; if($null -ne $v -and $v -gt 0){ $valueProv[$mp]=$true; break } }
  }
}
$rankProv=@{}   # providerId -> ArrayList of ranking-metric display names
foreach($w in $dataWidgets){
  if(Test-Blended $w){ continue }
  $prov=Get-WidgetProvider $w; if(-not $prov){ continue }
  if((Get-Category $prov) -ne 'ads'){ continue }
  if(-not (Test-RankableCostWidget $w)){ continue }
  if(-not $rankProv.ContainsKey($prov)){ $rankProv[$prov]=[System.Collections.ArrayList]@() }
  $rmet=Find-Metric $w 'cost_per_conversion|cost_per.*lead|costperactiontype::lead|(^|_)cpa$|(^|_)cpl$'
  if(-not $rmet){ $rmet=Find-Metric $w 'cost_micros|(^|_)cost$|spend|amount_spent' }
  if($rmet -and ($rankProv[$prov] -notcontains [string]$rmet.name)){ [void]$rankProv[$prov].Add([string]$rmet.name) }
}
$affected=@($rankProv.Keys | Where-Object { -not $valueProv[$_] } | Sort-Object)
if($affected.Count -gt 0){
  $affNames=@($affected | ForEach-Object { if($platforms.ContainsKey($_)){ $platforms[$_].name } else { $_ } })
  $rmNames=@(); foreach($p in $affected){ foreach($n in @($rankProv[$p])){ if($rmNames -notcontains $n){ $rmNames+=$n } } }
  $rmShown = if(@($rmNames).Count -gt 6){ (@($rmNames[0..5]) + @("+$(@($rmNames).Count-6) more")) } else { @($rmNames) }
  [void]$gaps.Add([ordered]@{
    ruleId='GAP_COST_RANKING_NO_VALUE'; severity='major'; requiresDownstreamData=$true
    statement=("Cost-per-result comparisons (" + ($rmShown -join ', ') + ") are reported for " + ($affNames -join ', ') + " with no conversion-value, revenue, or ROAS metric measured; cost-based rankings order campaigns by acquisition cost alone - confirm downstream (funded/closed) value before treating a cheaper cost-per-result as better.")
    evidence=[ordered]@{ platforms=($affNames -join ', '); rankingMetrics=($rmShown -join ', ') }
  })
}
```

Interlocks (all pre-existing, cited): forced fid echo C:414-427; downstream clause C:458-460 satisfied by the statement's literal `downstream`; template rules T:20-21 route it into "Analytical insights"; fid assigned by A:769-771; statement/evidence registered byFid by C:244-252. The statement template contains **no digit characters** (test-asserted; metric display names in the live taxonomy are digit-free, and a hypothetical digit-bearing name would still self-trace because byFid indexes the statement itself).

## Rule (b) - `ANOM_BRAND_BASELINE` (exact build shape)

New pure helpers:

```powershell
# U10/D6: deterministic brand-token derivation from the Swydo client entity name (meta.client).
# phrase (>=2 tokens, parentheticals stripped) may FIRE via Test-BrandLabel; abbr/lead ANNOTATE only.
function Get-BrandTokens($clientName){
  $out=[ordered]@{ phrase=$null; abbr=@(); lead=$null }
  $s=[string]$clientName; if([string]::IsNullOrWhiteSpace($s)){ return $out }
  foreach($m in [regex]::Matches($s,'\(([^)]+)\)')){
    foreach($t in ($m.Groups[1].Value -split '[^A-Za-z]+')){ if($t.Length -ge 3){ $out.abbr+=$t.ToLower() } }
  }
  $core=(($s -replace '\([^)]*\)',' ') -replace '\s+',' ').Trim()
  $toks=@($core -split '[^A-Za-z0-9]+' | Where-Object { $_ })
  if($toks.Count -ge 2){ $out.phrase=(($toks -join ' ').ToLower()) }
  if($toks.Count -gt 0 -and $toks[0].Length -ge 4){ $out.lead=$toks[0].ToLower() }
  return $out
}
function Test-PMaxLabel($label){
  return [bool](([string]$label) -match '(?i)((^|[^a-z])p[\s._-]?max([^a-z]|$))|performance[\s._-]*max')
}
function Test-BrandLabel($label,$tokens){
  $l=[string]$label
  if($l -match '(?i)\bbrand(ed)?\b(?!\s+new\b)'){ return $true }
  if($tokens -and $tokens.phrase){
    $norm=((($l -replace '[^A-Za-z0-9]+',' ') -replace '\s+',' ').Trim().ToLower())
    if($norm.Contains($tokens.phrase)){ return $true }
  }
  return $false
}
function Get-MatchedBrandToken($label,$tokens){
  if(-not $tokens){ return $null }
  $norm=' ' + ((([string]$label -replace '[^A-Za-z0-9]+',' ') -replace '\s+',' ').Trim().ToLower()) + ' '
  foreach($t in @($tokens.abbr)){ if($t -and $norm.Contains(" $t ")){ return $t } }
  if($tokens.lead -and $norm.Contains(" $($tokens.lead) ")){ return $tokens.lead }
  return $null
}
```

Block inside `Get-BreakdownFindings` (after the effort/share-mismatch section, before `return @($out)` at A:211; `$wcat`, `$pname`, `$dimName`, `$tr`, `$detail`, `$cc` already in scope):

```powershell
# U10 rule (b): brand-demand-harvest suspects dominating the outcome total (data_gaps.md Tier 1.2).
if($wcat -eq 'ads' -and $dimName -match '(?i)campaign'){
  $btok=Get-BrandTokens $clientName
  $om=Find-Metric $w '(^|:)conversions?$'; if(-not $om){ $om=Find-Metric $w '(^|_)lead|actions::lead' }
  if($om){
    $btot=Row-Cur $tr $om.name
    if($btot -and $btot -gt 0){
      $bm=[System.Collections.ArrayList]@(); $bsum=0.0; $btk=$null
      foreach($r in $detail){
        $lbl=[string](Row-Label $r)
        $sig=$null
        if(Test-PMaxLabel $lbl){ $sig='pmax' } elseif(Test-BrandLabel $lbl $btok){ $sig='brand-name' }
        if(-not $sig){ continue }
        $v=Row-Cur $r $om.name
        if($null -ne $v -and $v -gt 0){
          $bsum+=[double]$v; [void]$bm.Add($lbl)
          if(-not $btk){ $btk=Get-MatchedBrandToken $lbl $btok }
        }
      }
      if(@($bm).Count -gt 0 -and ($bsum/$btot) -ge ($BrandSharePct/100)){
        $bshare="$([math]::Round(($bsum/$btot)*100,0))%"
        $bLbls = if(@($bm).Count -gt 5){ @($bm[0..4]) + @("+$(@($bm).Count-5) more") } else { @($bm) }
        $bconf = if($bsum -lt $SmallN){ 'low' } else { 'normal' }
        $bev=[ordered]@{ campaigns=($bLbls -join '; '); share=$bshare
          matchedTotal=(Format-Metric $om.id $om.unit $bsum $cc); total=(Format-Metric $om.id $om.unit $btot $cc) }
        if($btk){ $bev.brandToken=$btk }
        [void]$out.Add([ordered]@{ ruleId='ANOM_BRAND_BASELINE'; severity='info'; platform=$pname; widget=$dimName; confidence=$bconf
          statement="${pname}: brand-demand-suspect campaigns ($(($bLbls | ForEach-Object { "'$_'" }) -join ', ')) account for $bshare of $($om.name) ($(Format-Metric $om.id $om.unit $bsum $cc) of $(Format-Metric $om.id $om.unit $btot $cc)) - Performance Max / brand-named campaigns harvest existing brand demand, so treat this share as baseline-suspect context, not proof of driven demand"
          evidence=$bev })
      }
    }
  }
}
```

On the live QCU data this emits exactly one finding: the 5 PMax campaigns (4 with outcome > 0 contributions plus `Hanover` at 3), combined `47%` of `Conv.` (`404.3` of `860.9`), `brandToken='quincy'` (from `inS - PMax - Quincy General`), severity info. The FB campaign widget emits nothing (no S1-S3 signal).

---

## Edge cases and false-positive analysis (named)

**Rule (a):**
- **E1 - partial value coverage:** Google measures `conversions_value > 0`, Facebook does not; both rankable. Finding fires naming Facebook only. The statement's platform list is derived, never "everywhere".
- **E2 - value on a different widget:** value metric lives on a separate KPI card (or a blended widget) of the same provider - prefix attribution suppresses correctly.
- **E3 - all platforms measured:** no finding. Self-healing (D4).
- **E4 - zero-value column:** `conversions_value` present but all cells 0/null - fires anyway (D3, `> 0` scan). A configured-but-empty value column is still a value-blind ranking.
- **E5 - KPI-only report (documented residual):** two zero-dim cards (Google `Cost / conv.` vs FB `Cost per Lead`) allow a cross-PLATFORM efficiency comparison the rule does not see (no dimensioned surface). Not covered in U10 - real ads reports carry campaign tables (the live one does), and a zero-dim trigger would fire on virtually any ads KPI strip, tanking precision. Named for the reviewer.
- **E6 - time-only cost breakdown (documented residual):** a Month widget with `Cost / conv.` is pacing, not a ranking; excluded by D2(i). A report whose ONLY cost-per-X surface is temporal does not fire.
- **E7 - non-ads / unknown providers:** shopify (`revenue` native), GA4, `other` - gated out by `(Get-Category $prov) -ne 'ads'` (S13.8 fail-closed convention).
- **E8 - cost-only or outcome-only tables:** a campaign table with spend but no outcomes (or vice versa) cannot rank efficiency - D2(iii) requires the pair or an explicit cost-per-outcome column.

**Rule (b):**
- **F1 - "Brand New Auto Loans":** S2 lookahead `(?!\s+new\b)` rejects the idiom. Named regression test.
- **F2 - "TopMax Deals" / "CompMax":** S1's `(^|[^a-z])` boundary rejects embedded `pmax`. Named regression test.
- **F3 - agency naming convention ("QCU | Auto Loans", "QCU | Mortgages", ...):** abbreviation tokens are annotation-only (D6), so a client prefix on every campaign fires NOTHING. This is the single largest FP class in the wild and it is structurally excluded, not threshold-excluded.
- **F4 - generic client name ("First National Bank"):** lead token `first` is annotation-only; a "First Time Buyer Promo" campaign cannot fire via tokens. Firing requires PMax / literal "brand" / the full phrase `first national bank`.
- **F5 - product PMax campaigns ("inS - PMax - Mortgages"):** counted in the matched set by design - PMax's brand-harvest property is a function of the campaign TYPE, not its name; the statement says "Performance Max / brand-named", not "branded". Named reviewer question (scope-down alternative: require S1 AND a brand token).
- **F6 - below threshold:** matched share < 25% => silent (e.g. the DefineOnly `adsAware` fixture's 'Brand Awareness' row at 2% of conversions - guarantees the existing fixture cannot start firing).
- **F7 - no client name (legacy/Mode B extraction, live archived facts have `client=''`):** S3 and annotations disabled; S1/S2 still live. Never throws (`Get-BrandTokens` returns the empty shape).
- **F8 - non-campaign breakdowns:** device/keyword/location/age tables gated out by `$dimName -match '(?i)campaign'` (the `Location,Campaign name` widget's dims[0] is `Location` - correctly out, its rows are locations).
- **F9 - dimensioned no-total widget:** `Get-BreakdownFindings` already early-returns (A:156, U6/A1) - no fabricated denominator.
- **F10 - "Rebranding Campaign":** `\bbrand\b` word boundary rejects `rebranding` (tighter than the shipped A:205 substring hint).
- **F11 - small totals:** matched sum < 30 => `confidence='low'`, model hedges (S13.3).
- **F12 - "Branded Merchandise" (accepted residual FP):** a campaign selling branded merch would match S2 and, if dominant, draw an info observation whose wording ("brand-named campaigns harvest existing brand demand") is mildly off-target. Accepted: info severity, never forced, and the model contextualizes - same posture as `ANOM_SHARE_MISMATCH`'s hint-based downgrade.

## Backward-compat / behavior audit (existing 276 must stay green)

- Every existing e2e fixture in `Test-Analyze.ps1` was audited against the new triggers: no fixture widget passes `Test-RankableCostWidget` with an ads category (u4a/u4c/u4g/r18: clicks-only; u5a-u5h/r10/r11: cost-only, no outcome; u4b/u4e: outcome-only; u4k: provider `someads` => category `other`; u3*/r9/r22: zero-dim), and no fixture campaign label matches S1/S2/S3 (labels `A/B/c1..c25/purchase/lead/Big/Small`). The DefineOnly `adsAware` fixture's 'Brand Awareness' row matches S2 but sits at 2% share => silent (F6). **Expectation: zero existing assertions change.** The build re-runs the full suite and treats any flip as a defect in this analysis (documented, never silently absorbed).
- Existing assertion style (`HasFind`/`GetFind`/`HasRule`) targets specific ruleIds, never total finding counts, so even an unexpected additive finding cannot break them - but the audit above says none appears.
- `Get-BreakdownFindings` gains an optional `$clientName` parameter - all existing one-argument calls bind `$null` (S1/S2 unaffected). The run body's call site change (A:754) is the only behavioral wiring.
- The default single-report output path is additive-only: identical facts except (possibly) one new `dataGaps` entry, one new `anomalies` entry, and their fids. No existing field changes; `factsVersion` stays 1; the closer ignores unknown finding keys (`confidence` already exists on WIN/LOSS; `requiresDownstreamData` already exists on `ANOM_SHARE_MISMATCH` A:206).
- Credential surface: untouched (no new file reads/writes; `Assert-NoCredential` still gates the single facts write A:798).

## PS 5.1 hazards specific to this change

- All new collections are `@(...)`-wrapped before `.Count`/indexing (`@($bm)`, `@($rmNames)`, `@($w.dimensions | Where-Object {$_})` - never the raw `@($null).Count -eq 1` trap).
- No `&&`/`||`/ternary/`??`; branching via `if/else`; `return [bool](...)` for predicates.
- Pure-ASCII source: statements/regexes contain no unicode; the live labels' en-dashes arrive via data and never touch a regex character class (S1's boundary is `[^a-z]`, which an en-dash satisfies). Test fixtures use ASCII hyphens.
- Case-insensitive variable collisions: new locals are `$valueProv/$rankProv/$affected/$affNames/$rmNames/$rmShown/$btok/$om/$btot/$bm/$bsum/$btk/$bshare/$bLbls/$bconf/$bev` - none collide with dot-source params (`$Facts/$From/$Into/$Execute/$Report`) or existing loop vars (`$w/$m/$r/$prov` reuse follows the body's existing pattern inside fresh `foreach` scopes; `$bm`/`$btot` chosen to avoid `Get-BreakdownFindings`' existing `$tr/$tot/$detail`).
- `[System.Collections.ArrayList]` + `[void]$x.Add(...)` for accumulators (house pattern, avoids O(n^2) `+=` and pipeline-unwrap surprises).
- New helpers take everything as parameters except the documented reads of script-scope `$BrandSharePct`/`$SmallN` inside `Get-BreakdownFindings` - both are bound by the param block even under `-DefineOnly` dot-source (defaults 25.0/30), so unit tests exercise them without the body.
- Negative lookahead `(?!\s+new\b)` is .NET regex - supported in PS 5.1.

## Test plan (`Test-Analyze.ps1`, additive on 276)

**`-DefineOnly` units - rule (a) predicates**
1. `Test-ValueMetricId` TRUE: `google-adwords:conversions_value`, `google-adwords:all_conversions_value`, `google-adwords:value_per_conversion`, `facebook-ads:actionValues::purchase`, `x:purchase_roas`, `shopify:revenue`, `x:websitePurchaseRoas`.
2. `Test-ValueMetricId` FALSE: `google-adwords:cost_micros`, `google-adwords:conversions`, `facebook-ads:actions::lead`, `facebook-ads:costPerActionType::lead`, `google-adwords:active_view_non_viewable_impression_rate`, `google-adwords:search_lost_is_budget`, `google-analytics-4:eventValue` (letter-glued `value` tail must not match).
3. `Test-RankableCostWidget` TRUE: campaign dim + cost_micros + conversions (implicit pair); campaign dim + explicit `cost_per_conversion`; campaign dim + spend + `actions::lead` (FB shape).
4. `Test-RankableCostWidget` FALSE: zero-dim KPI; `Month` dim with cost/conv (time exclusion); campaign dim with cost only; campaign dim with conversions only; campaign dim with a single detail row; campaign dim with only `costPerActionType::link_click` (click denominator is not an outcome).

**`-DefineOnly` units - rule (b) predicates**
5. `Test-PMaxLabel` TRUE: `inS - PMax - Quincy General`, `Performance Max - Brand`, `pmax_general`, `P Max Launch`, `P.Max 2026`.
6. `Test-PMaxLabel` FALSE: `TopMax Deals`, `CompMax`, `Search - Auto Loans`, `''`/`$null`.
7. `Get-BrandTokens`: `'Quincy Credit Union (QCU)'` => phrase `quincy credit union`, abbr `qcu`, lead `quincy`; `'First National Bank'` => lead `first`, no abbr; `$null`/`''` => empty shape (no throw); single-token `'Acme'` => no phrase, lead `acme`.
8. `Test-BrandLabel` TRUE: `Quincy Credit Union - Search` (phrase), `Brand - Exact` (S2), `Branded Search` (S2).
9. `Test-BrandLabel` FALSE: `Brand New Auto Loans` (F1), `Rebranding Campaign` (F10), `QCU | Mortgages` with QCU tokens (abbr never fires, F3), `First Time Buyer Promo` with 'First National Bank' tokens (F4).
10. `Get-MatchedBrandToken`: `inS - PMax - Quincy General` + QCU tokens => `quincy`; `General QCU - Awareness Video` => `qcu`; `Auto Loans` => `$null`.

**`-DefineOnly` units - `Get-BreakdownFindings` rule (b) fixtures (harness `Wgt`/`Rw`/`Met` style, passing `$clientName` as the new 2nd arg)**
11. PMax row at 40% of conversions => ONE `ANOM_BRAND_BASELINE`, severity `info`, evidence `share`/`matchedTotal`/`total` present and byte-equal to `Format-Metric` output.
12. Two PMax rows individually 15%+13% (combined 28%) => fires ONCE, rolled up, both labels quoted (combined-set semantics, D7).
13. PMax row at 10% => silent (F6).
14. `Brand New Auto Loans` dominant => silent (F1).
15. Convention-prefix widget (every label `QCU | ...`, no PMax/brand word) with QCU client => silent (F3).
16. `Quincy Credit Union - Brand` row dominant, client `'Quincy Credit Union (QCU)'` => fires with `evidence.brandToken`.
17. Matched sum 12 of total 20 (60% share, sum < 30) => fires with `confidence='low'` (F11).
18. Non-campaign dim (`Device`) with a PMax-named row => silent (F8); non-ads category (shopify `Channel`) => silent (E7); dimensioned no-total campaign widget => silent (F9).
19. Existing `adsAware` fixture re-asserted: still emits info `ANOM_SHARE_MISMATCH` and NO `ANOM_BRAND_BASELINE` (F6 pin).

**e2e body (RunAnalyze harness, `schemaVersion:2` temp extraction per U6 M5 pattern)**
20. Two ads platforms, each with a rankable campaign widget, no value metric anywhere => exactly ONE `GAP_COST_RANKING_NO_VALUE`; `severity='major'`; `requiresDownstreamData=$true`; fid assigned (`GAP_COST_RANKING_NO_VALUE#1`); `evidence.platforms` names both; statement matches `'downstream'` and contains NO digit (`-notmatch '\d'`).
21. Same + a Google zero-dim KPI carrying `conversions_value` with current > 0 => finding names Facebook only (E1/E2).
22. Value metric present but all cells 0 => still fires (E4).
23. All rankable platforms carry value > 0 => absent (E3).
24. KPI-only report (zero-dim `cost_per_conversion` card) => absent (E5); time-dim-only cost breakdown => absent (E6); shopify sessions/orders/revenue table => absent (E7).
25. Rule (b) e2e: campaign widget with a dominant PMax row => `ANOM_BRAND_BASELINE` in `findings.anomalies` with fid; the flagged label is force-included in the platform's breakdown rows even past a small cap (the A:757-758 `$plLabels` synergy, mirroring the F2 force-include test).
26. Live-shape regression: a fixture mirroring the QCU google campaign widget (5 PMax + 3 non-PMax rows, conv values as archived) => share evidence `'47%'`, `matchedTotal '404.3'`, `total '860.9'`.

**Closer integration (dot-source the REAL `Test-ReportNumbers.ps1 -DefineOnly`, per the shipped closer22 pattern)**
27. A draft echoing rule (a)'s statement + `<!-- finding:GAP_COST_RANKING_NO_VALUE#1 -->` => `Invoke-Closer` 0 violations.
28. The same draft with the fid comment stripped => `unsurfaced-finding` violation (proves the forced-caveat path).
29. A draft surfacing the fid but paraphrasing WITHOUT any `$DownRx` clause => `missing-downstream-caveat` violation (proves 3c engages).
30. A draft omitting rule (b) entirely => 0 surfacing violations (info is advisory, D8); a draft quoting rule (b)'s `47%`/`404.3`/`860.9` on its fid-anchored line => numbers trace; the same numbers on a NON-anchored line => `untraceable-number` (byFid scoping pin).

**Cross-suite**
31. Full `Test-Analyze.ps1` green (276 + new cases, 0 failed).
32. Closer 119, Extractor 94, Archive 94, Ledger 50, Sync 4, TrendAnalyze 24, TrendFacts 19 re-run green, counts unchanged (no file outside Analyze/Test-Analyze touched).

## For the reviewer (adversarial)

- **Rule (a)'s severity is the load-bearing call.** `major` + `requiresDownstreamData` means every value-less ads report carries one forced caveat line forever. The defense: that is the ratified intent (data_gaps G:6 - CPL without value is a vanity ranking), the cost is one line, and it self-heals when value tracking appears. The alternative (`info` + `requiresDownstreamData=$true`) would STILL force surfacing via C:420 while softening template rule 4's placement - is the extra weight of `major` earning anything, or is it pure fatigue? Conversely: is once-per-report too coarse when platforms differ (a single line must name both platforms honestly)?
- **Rule (a)'s trigger breadth:** D2 counts a cost+outcome PAIR as a ranking surface even without an explicit cost-per column. Too aggressive (a table the report never ranks still triggers the caveat) or correctly conservative (the model CAN rank from that table, so the disclosure must exist)? The scoped-down alternative is explicit-cost-per-outcome-column-only.
- **E5 residual:** a KPI-only cross-platform comparison (Google cost/conv card vs FB CPL card) escapes the rule. Accept as residual, or is a `>= 2 ads platforms each carrying a zero-dim cost-per-outcome KPI` trigger worth its precision cost?
- **Rule (b) plain-PMax firing (F5):** the matched set includes product-named PMax campaigns (`PMax - Mortgages`) because the TYPE, not the name, is the harvest signal. Scope-down alternative: require S1 AND a brand token/S2/S3 - but that reduces the live QCU finding from the honest 47% to just `PMax Quincy General`'s 25% and makes firing dependent on the fuzzy token tier the design deliberately demoted. Which side of that trade is right?
- **Rule (b) is never force-surfaced (D8).** A 47%-of-conversions baseline-suspect observation can legally be omitted from the report while the causal voice says "drove 860.9 conversions" (the causal-verb ban is prompt-level, not closer-mechanized). Should dominance >= 50% escalate to a forced path - and if so, which one, given the downstream clause (3c) is semantically wrong for brand-split caveats and adding a new closer token class is out of scope for this unit?
- **Threshold constants:** `$BrandSharePct=25.0` is calibrated on exactly one live account (47% fires, and the named single campaign sits at 25.0%). Is single-account calibration acceptable for an info-severity rule, and should the combined-set share ALSO report the largest single contributor (extra evidence field) so the reader can distinguish "one harvester" from "five small PMax campaigns"?
- **Suppression via `> 0` (D3/E4):** a report with a genuine zero-value quarter (tracked, truly zero revenue) fires the gap. Defensible ("no value signal to rank by") or misleading ("value IS measured, it is just zero")? The presence-only alternative is one predicate simpler.
- **`Test-ValueMetricId` breadth:** unanchored `revenue`/`roas` and `(^|_)value$` - hunt for an ads-taxonomy id this wrongly matches (suppressing the gap) or wrongly misses (firing despite value present). The live taxonomy shows neither, but the taxonomy is one account deep.
