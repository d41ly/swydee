# `/swydee` Skill — Build Spec

**Goal.** A manually-invoked skill that turns a Swydo report (link or already-parsed v2 file) into a senior-media-buyer client report — per-platform overviews + previous-period comparison, analytical insights (wins/losses/anomalies/discrepancies/data-gaps), and recommendations — closing with an adversarial review that verifies every number against the data. **All-Swydo scope** (adapts voice to whatever providers are present, not just ad platforms). Numbers are **computed deterministically** by supporting tooling, never eyeballed by the model.

**Non-negotiable principle.** The model narrates; a deterministic tool computes. Every figure in the report must trace to the compute tool's output. This is what makes the adversarial closer meaningful (it re-checks prose against the same facts, not against more model arithmetic).

---

## 1. Skill mechanics

- **Files** (live in the `swydee` repo so tool + skill + compute ship and version together):
  - `Get-SwydoReport.ps1` — existing v2 extractor (Mode A).
  - `Analyze-SwydoReport.ps1` — **NEW** deterministic compute tool (§5). Spec now; build after review.
  - `skill/SKILL.md` — the skill definition (instructions the model follows).
  - `skill/report-template.md` — the report skeleton the model fills.
- **Registration:** symlink/copy `skill/` to `~/.claude/skills/swydee/` (or project `.claude/skills/swydee/`). Note the install step in the repo README.
- **Manual-only invocation:** `SKILL.md` frontmatter `description` must explicitly scope triggering to explicit invocation, e.g. *"Use ONLY when the user explicitly types /swydee or asks to run swydee. Do not auto-invoke."* No proactive-trigger verbs.
- **Runs in the main loop.** The skill may call `Workflow` for fan-out (allowed: skill instructions are a valid Workflow opt-in) — but only per the §6 threshold.

## 2. Inputs & mode detection

`/swydee <arg> [password] [--fast|--thorough] [--out <dir>]`

- **Mode A (link):** `<arg>` matches `swy.do/shares/…` or `app.swydo.com/g/…`. Optional 2nd token = share password. → run `Get-SwydoReport.ps1 -ShareUrl <arg> [-Secret <pw>]`, capture the produced JSON path.
- **Mode B (file):** `<arg>` is a filesystem path ending `.json`. → validate schema (§3), skip extraction.
- Detection order: if it looks like a URL → A; if a path/`.json` → B; else error with usage.
- `--fast` forces single-pass; `--thorough` forces fan-out; absent → auto (§6).

## 3. Mode B schema validation

A file is a valid input iff, after `ConvertFrom-Json`:
- `meta.schemaVersion == 2` (reject v1 with "re-extract with the current tool"; reject missing/other with a clear message).
- Required keys present: `meta{tool,extractedAt,reportId}`, `report{name,dateRange}`, `widgets[]` (array).
- At least one widget with `kind=="data"` and `rows` (else "no data to analyze — all text/empty").
Reject foreign JSON (no `meta.schemaVersion`) explicitly. Never attempt to analyze an unrecognized shape.

## 4. Credential hygiene

- The v2 file's `meta.shareKey` is a **live bearer credential** and `meta.shareUrl` contains it. The **client-facing report must never embed shareKey/shareUrl/password.** The compute tool's facts output and the report both **redact** them (report references the report *name*, not the link).
- The password (Mode A) is passed to the extractor only; never written to the facts, report, or logs.
- The skill may note in an internal/agency footer (not the client copy) the source report id — decision: keep report credential-free by default.

## 5. Deterministic compute tool — `Analyze-SwydoReport.ps1` (SPEC ONLY)

**Contract:** reads a v2 JSON, writes an **analysis-facts JSON** (`<slug>.facts.json`). Pure/offline (no network). The model reads ONLY this facts file to write prose.

### 5.1 Unit application (the contract)
For each metric value, produce raw + display using the v2 `unit`:
- `unit=="micros"` → base = raw/1e6. If the metric is money (see money-detection) → format as currency using widget `currencyCode` (e.g. `$12,620.50`); else base unit as-is (e.g. seconds).
- `unit=="fraction"` → `raw*100` formatted `xx.x%`.
- `unit` absent → render raw as-is; if the metric *looks* monetary but unit is absent (unverified provider) → mark `unitConfidence:"unconfirmed"` and DO NOT convert; flag as a data gap (§5.6 G2).
- **Money detection:** `unit=="micros"` AND `currencyCode` present ⇒ money; plus id-pattern fallback (`cost|spend|cpc|cpm|cpa|cpl|revenue|value|budget`) for display labeling only (never to force conversion).
- Counts (no unit) → integer/decimal formatting; conversions may be fractional.

### 5.2 Comparison-window derivation (don't trust Swydo's label)
- `hasComparison` = any data row has non-null `compare`.
- Derive **current** and **previous** period labels from `report.dateRange.primary` (`count`,`measure`,`type`) relative to `meta.extractedAt`, NOT from `compareDateRange.period` (which mislabels — e.g. says `previousMonth` for a quarter-over-quarter). Rule for `RELATIVE`,`count=-1`,`measure=quarter`: current = last complete quarter before extractedAt; previous = the quarter before that. Generalize per measure (day/week/month/quarter/year). Cross-validate against any date-dimension rows present (e.g. `2026-04-01`…`2026-06-30` confirms Q2).
- Emit `currentPeriod`/`previousPeriod` as human labels + ISO date ranges when derivable; if not derivable, emit `"current"`/`"previous"` and say so.

### 5.3 Metric direction (for win/loss classification)
Map metric-id patterns → `higher-better` | `lower-better` | `neutral`:
- lower-better: `cost|cpc|cpm|cpa|cost_per|cost_per_conversion|cost_per_lead|costPerActionType|spend?`(spend is neutral—more spend isn't inherently good/bad), `bounce_rate`, `unsubscribe`, `frequency`(context), `search_lost_is*`.
- higher-better: `conversion|conversions|clicks|impressions|reach|leads|ctr|roas|revenue|sessions|opens|open_rate|engagement|impression_share|quality_score|ranking`(lower position number = better → special-case).
- neutral/no-direction: `spend|amount_spent|budget`, ids with no known direction → report value/Δ but DON'T label win/loss.
Unknown metric → neutral (report, don't judge). This map is provider-agnostic via id substrings + a small per-category override table.

### 5.4 Provider → category (all-Swydo)
| category | provider ids (examples) | report framing |
|---|---|---|
| ads | google-adwords, facebook-ads, bing-ads/microsoft, linkedin-ads, tiktok-ads, pinterest, snapchat, twitter-ads, reddit-ads, adroll | spend / CPA / CPL / leads / ROAS — media-buyer voice |
| web-analytics | google-analytics-4, (ua) | sessions / users / engagement / conversions |
| seo | semrush, se-ranking, accuranker, trueranker | rankings / visibility / traffic |
| email-crm | mailchimp, klaviyo, activecampaign, hubspot | sends / opens / clicks / list growth |
| ecommerce | shopify | revenue / orders / AOV |
| calls | callrail, ctm | calls / call outcomes |
| perf/util/custom | pagespeed, pingdom, toggl, google-sheets, microsoft-excel, openai | as-is, minimal judgment |
Unknown provider → category `other`, report values with no ad-specific framing and no win/loss on unknown metrics. The report's persona stays "senior performance marketer," but section framing + which anomaly rules apply are category-driven.

### 5.5 Derived rule-based checks (the ruleset — provider-aware)
Each emits a `finding {ruleId, type(win|loss|anomaly|discrepancy|dataGap), severity, platform, widgetId, metric?, statement, evidence{numbers}}`. Thresholds are constants (tunable), listed.

**Discrepancies (data integrity):**
- `DISC_NONADDITIVE` — reach/frequency/unique_* summed across rows ≠ total. Mark as *expected* (dedup) not an error; emit an informational note so the report never sums reach. (severity: info)
- `DISC_CROSS_WIDGET` — same metric id + period reported by ≥2 widgets differs > 1% → flag (e.g. link-clicks KPI 2363 vs table 2346). (major)
- `DISC_TOTAL_VS_ROWS` — for additive metrics, |Σ detail − total| / total > 1% → flag. (major)

**Data gaps:**
- `GAP_WARNINGS` — surface each `meta.warnings[]` (empty widgets, unverified providers).
- `GAP_UNIT_UNCONFIRMED` — money-looking metric with absent `unit` (unverified provider) → "units unconfirmed; figures raw." (major)
- `GAP_NO_COMPARE` — some widgets have `compare`, others null → partial comparison; name which lack it.
- `GAP_UNKNOWN_KIND` — `kind=="unknown"` widget → couldn't classify; raw preserved.
- `GAP_MANUAL` — `manualKpi` present → value is hand-entered, not measured.
- `GAP_ALL_ZERO` — metric all-zero/all-null across rows.

**Anomalies (require comparison unless noted):**
- `ANOM_NEW` — metric/campaign non-zero now, 0/absent in previous. (info→win)
- `ANOM_PAUSED` — 0 now, non-zero previous. (loss)
- `ANOM_SWING` — |Δ%| ≥ 50% on a headline metric. (win or loss by direction)
- `ANOM_EFFICIENCY_DIVERGENCE` — volume (clicks/impressions/spend) up ≥ X% while outcome (conversions/leads) flat/down, OR cost-per-outcome worsening ≥ X% while volume grows. (loss) — the conversion-rate-drop pattern.
- `ANOM_SHARE_MISMATCH` (no comparison needed) — a row's share of cost/impressions ≫ its share of conversions/leads (ratio ≥ 3×) → inefficient concentration (the Hanover case). (loss)
- `ANOM_ZERO_RESULT_SPEND` — row with spend ≥ threshold and 0 conversions/leads. (loss)
- `ANOM_EFFICIENCY_SPREAD` — best vs worst cost-per-result across a breakdown ≥ 3× → reallocation opportunity (Audience Network case). (win/opportunity)
- `ANOM_CONCENTRATION` — one dimension bucket ≥ 50% of a metric (audience 65+ skew). (info)

**Wins / losses:** any metric with a comparison and a known direction whose Δ is favorable/unfavorable and |Δ%| ≥ 10% (headline) becomes a win/loss finding; smaller moves listed in the overview table but not called out.

### 5.6 Facts output schema (`*.facts.json`)
```jsonc
{
  "meta": { "reportName","extractedAt","currentPeriod","previousPeriod","hasComparison",
            "providers":[{id,name,category}], "widgetCount","dataWidgets",
            "fanout":{ "recommended":bool,"reason","platforms","rows" },
            /* NO shareKey/shareUrl */ },
  "platforms": [ { "id","name","category",
      "headline":[{ "metric","id","unit","current","previous","deltaPct","direction",
                    "displayCurrent","displayPrevious","displayDelta","currency" }],
      "breakdowns":[{ "widgetId","title","dimensions","topRows":[…capped…],"note" }] } ],
  "findings": { "wins":[…],"losses":[…],"anomalies":[…],"discrepancies":[…],"dataGaps":[…] },
  "computedAt":"<stamp>"
}
```
All display strings pre-formatted so the report copies them verbatim. Long tables capped (e.g. top 15 rows) with a "N of M shown" note (never silent truncation).

## 6. Fan-out decision (dynamic thresholds)

The compute tool emits `meta.fanout.recommended` + reason; the skill obeys it (unless `--fast`/`--thorough` overrides). Rule:
- **Single-pass** if: `platforms == 1` AND `dataWidgets ≤ 25` AND `total rows ≤ 200`.
- **Fan-out** if: `platforms ≥ 2` OR `dataWidgets > 25` OR `total rows > 200`.
- Fan-out shape: **one analyst agent per platform** (parallel, each gets that platform's facts slice → returns narrative + finding confirmations) + **one cross-cutting agent** (discrepancies across platforms, data gaps, portfolio-level recommendations) → **synthesis** into the report. Single-pass = the model writes directly from the full facts.
- Cap: ≤ 8 platform agents. Thresholds are constants at the top of SKILL.md, tunable.
- **Failure-mode guard:** agents receive the pre-computed facts (not raw JSON) and are told to return prose + which finding ids they confirm/dispute — they never invent numbers, which also sidesteps the "structured-output returns placeholder" failure by using plain-text agents, not schema-forced ones.

## 7. Report generation

- **Persona:** senior performance marketer / media buyer writing to a client; warm, direct, honest about bad news (the tone from the accepted QCU report). Framing per §5.4 category.
- **Structure (`report-template.md`):**
  a. **Per-platform overviews** — one section per platform: a headline KPI table (current | previous | Δ, using facts display strings) with a one-liner takeaway; comparison columns only if `hasComparison`.
  b. **Analytical insights** — wins / needs-attention / anomalies-&-weird, sourced from `findings`. Each point cites the finding's numbers.
  c. **Recommendations** — derived from losses/anomalies/opportunities; concrete next steps. Caveat where units unconfirmed or data gapped.
- **Numbers:** copied verbatim from facts display strings. The model must not compute or reformat numbers.
- **Output:** `<out>/<stamp>-<reportslug>-report.md`, credential-free. Default `<out>` = alongside the extraction. Also keep the `*.facts.json` for auditability.

## 8. Adversarial review closer

After the report is drafted:
- **Deterministic pass (primary):** extract every numeric token from the report prose and confirm each appears in the facts display strings (or is a stated % derivable from two facts). Any number not traceable → flag. This is a script/regex check over report vs facts, not model judgment.
- **Model pass (secondary):** a short review that checks framing honesty — every win/loss has the right direction, caveats present where facts say `unitConfidence:unconfirmed` or a data gap exists, no claim beyond the data (e.g. lead-quality). Mirrors the manual review that caught the seasonality/AN caveats.
- Output: a short "review notes" block appended (agency copy) listing any corrections applied; if a number failed tracing, fix or remove it before finalizing.

## 9. Degradation & edge cases

- Extraction fails / dead link (404) → report the failure, don't fabricate.
- Report with **no comparison** → skip the comparison columns and comparison-dependent anomalies; say so.
- **Unverified-provider units** → figures shown raw, explicitly caveated; no fabricated conversions.
- **Non-ad / mixed reports** → category framing (§5.4); drop ad-specific anomaly rules that don't apply.
- **Cold/empty widgets** → surfaced as data gaps, report continues.
- **Manual KPIs** → labeled hand-entered.
- **`unknown`-kind widgets** → listed as "uninterpreted (raw preserved)."
- **Single-widget or tiny report** → still works (single-pass), no fan-out.

## 10. Dependencies & compatibility

- Depends on `Get-SwydoReport.ps1` v2 (schemaVersion 2). Windows PowerShell 5.1 / .NET. No jq/node/python.
- `Analyze-SwydoReport.ps1` is pure/offline and independently testable (functions-first + `-DefineOnly`, mirroring the extractor, so its rules get unit tests).

## 11. Build plan & test plan (after review)

Build order: (1) `Analyze-SwydoReport.ps1` + its unit tests (synthetic reports exercising every rule + unit/comparison logic); (2) `SKILL.md` + `report-template.md`; (3) wire Mode A/B, fan-out decision, review closer; (4) end-to-end on the live report B + a synthetic multi-platform/non-ad fixture; (5) commit.
Tests: rule unit tests (each ruleId fires on a crafted fixture, doesn't false-fire); unit/comparison/direction correctness; facts-schema validity; report number-tracing (closer) on the real output; degradation fixtures (no-comparison, unverified-provider, non-ad, dead-link).

## 12. Open decisions flagged for the adversarial review
- Fan-out thresholds (§6 numbers) — are they right, or should fan-out key off distinct *categories* not raw widget counts?
- Skill file location / registration (repo vs `~/.claude/skills`), bundling vs referencing the extractor.
- How much of the anomaly ruleset is truly provider-agnostic vs needs per-category rules (esp. non-ad: what are the SEO/email/analytics analogues of "zero-result spend"?).
- Comparison-window derivation for irregular ranges (SINCE, custom, parent ranges).
- Whether the model pass in §8 needs a separate agent or can be inline.

---

# §13. HARDENED DESIGN (post-review, authoritative — supersedes any conflict above)

Three adversarial reviews (architecture/ruleset, feasibility/PS-5.1, "wrong-report" auditor), all validated against the real extraction. Core lesson: **tracing numbers to facts guarantees arithmetic, not truth or safety.** Guarantees must move from the soft model-pass into deterministic fail-closed gates, and facts must be role-qualified and fully pre-computed. This section is what the build follows.

## 13.0 Scope decision (v1) — FULL non-ad ruleset (user-chosen)
"All-Swydo" = every report produces a sound report AND fires category-appropriate anomaly/win-loss rules for **every** category (ads, web-analytics, seo, email-crm, ecommerce, calls; `other` = descriptive-only). Rules are **category-gated** via `appliesToCategories[]` and a per-category **rule config** (§13.12) that generalizes "effort-with-no-result" and names each category's money/effort/result/quality metrics. Universal rules (direction-based win/loss, swing+small-N, trend, segment-divergence, concentration, cross-widget/additive discrepancies, data-gaps) run for all. `other`/unknown providers still get overviews + data-gaps + direction-safe win/loss only (no fabricated category semantics).

## 13.1 Fact identity & the closer (the soundness core)
- **Every numeric fact is role-qualified**, not a free scalar. Key = `platform.metricId.period.rowRole` (period ∈ current|previous|deltaPct; rowRole ∈ total|<dimlabel>). All values pre-formatted to a canonical `display` string; the tool owns **all** rounding (currency 2dp, percent 1dp, counts 0dp, ratios as spec'd). The model never computes or reformats.
- **Read the `total` row for every widget headline; never sum rows.** KPI widgets emit 3 identical rows (total/subtotal/data) — read `total`. **Never surface `subtotal` rows** to the report layer.
- **Scalar-guard**: drop non-scalar (object-valued echo) metric columns before any compute (`$v -is [double]/[int]/[long]/[decimal]`).
- **name→id join** per widget (row maps are keyed by display name; recover metric id via `metrics[]`).
- **The §8 deterministic closer** (rewritten):
  1. Normalize both sides numerically (strip `$ , % +`, trim trailing punctuation) and compare within display precision (tolerance = the metric's rounding unit). No string/substring matching.
  2. **No model arithmetic.** Remove the "% derivable from two facts" clause entirely — every %, delta, ratio, share must appear verbatim as a `display` in facts.
  3. **Typed allowlist for non-metric numbers**: period labels (Q2, 2026), age/segment buckets ("55+","25–34"), multipliers ("3×"), ordinals, list markers, and recommendation thresholds are exempt; only *measure tokens* (currency/percent/count adjacent to a metric claim) are traced.
  4. **Role/period/platform check**: a traced number must match a fact whose role/period/platform is consistent with the surrounding prose (current↔"this period", total↔that platform's or portfolio total; a Google number cannot appear in the Facebook section).
  5. **Comparison guard**: reject any comparative word (grew/fell/up/down/increased/decreased/±/%Δ) attached to a number whose source row has `hasComparison:false`.

## 13.2 Facts schema — required additions (so the model never computes)
- `timeSeries` block per time-dimension (Day/Week/Month) widget: per-bucket **derived** metrics (CPC/CPL/CTR computed by the tool) + a `trend` summary (first-vs-last, min/max, pacing e.g. "Apr 3× Jun") with display strings. Enables intra-period claims.
- Every finding carries an `evidence` object with **pre-formatted display strings** for every number it references (shares, ratios, spreads, deltas) — the report copies them.
- `deltaPct`/`direction` are **nullable per metric**; `hasComparison` recorded at **widget/row granularity**, not just report-level.
- `meta.portfolioTotals` computed once by the tool (same-currency only); synthesis/report must not compute its own.
- **Dimension-label rule** (in facts): prefer `*name`/`*text`; skip `^[\w-]+/\d+$` resource paths and all-digit ids; render `(group)`/null aggregate rows as `"All"`; **exclude `(group)`/aggregate sub-rows from share/spread/additivity math**.
- Per-figure `currency`; cross-widget aggregation only within same currency; currency-symbol map with **code-prefix fallback** (`EUR 12,620.50`).

## 13.3 Ruleset — final
- **DISC_CROSS_WIDGET**: compare current↔current and previous↔previous **separately**, skip null-period cells; for exact-count metrics flag **any** nonzero integer mismatch (not a 1% threshold). (The 2363-vs-2346 case is a sub-1% *previous*-period curiosity → informational, not major; reconciled.)
- **DISC_TOTAL_VS_ROWS**: runs only on an **additive whitelist** (impressions, clicks, conversions, leads, spend/cost, sessions, sends…); ratios/averages validated by recomputation from components; reach/frequency/unique/`average_*`/ctr never summed.
- **ANOM_ZERO_RESULT_SPEND**: threshold **relative** (row spend ≥ 2% of total AND 0 conv/leads), not absolute currency.
- **ANOM_SHARE_MISMATCH**: emit as **observation** (not auto-"loss"); `campaignNameHint` (`awareness|brand|video|launch|opening`) downgrades severity; model contextualizes.
- **ADD**: `ANOM_TREND` (time-series pacing from the timeSeries block), `ANOM_SEGMENT_DIVERGENCE` (one dimension bucket's Δ diverges sharply from siblings, e.g. desktop +219% vs mobile −2%), `ANOM_BUDGET_CONSTRAINED` (`search_lost_is_budget`/`impression_share` past threshold).
- **Small-N guard**: volume-swing rules require an absolute floor (current or previous ≥ N events, N≈30); low-N findings tagged `confidence:low` → model hedges.
- **requiresDownstreamData:true** on cost-per-outcome / efficiency-spread findings and any reallocation recommendation → forces a "confirm downstream/lead-quality first" clause; review **fails** if a reallocation rec lacks it.
- **comparisonCaveats[]** auto-emitted when comparison is adjacent-period QoQ/MoM (e.g. previous window overlaps a seasonal peak) → model **must** surface the caveat in any section using that comparison. (Tool flags the *possibility*; can't detect seasonality from one period.)
- **Ban causal verbs** (funded/drove/caused/because) unless a finding explicitly encodes causation → correlational language only.
- Optional/nice: `GOAL_DELTA` (vs `target.value`); stale-text-widget discrepancy (numeric claims in TEXT vs facts).

## 13.4 Deterministic surfacing gates (not model-judged)
- **Every `dataGap`/`discrepancy` of severity ≥ major MUST appear in the client report** — verified mechanically (finding-id → presence check), fail-closed.
- `unitConfidence:unconfirmed` caveats and table-truncation notes are **required tokens** the closer greps for and **fails** if absent.
- The §8 model pass becomes a **fail-closed checklist** (caveats present, directions correct, no over-claim, no causal verb without encoded causation), not advisory prose.

## 13.5 Credential hygiene (escalated — fail-closed)
- The compute tool **strips `shareKey`/`shareUrl` from the input on load**; the facts file is validated to contain **no** substring matching `swy\.do/shares/\w+` or the bare key **before** anything downstream runs (fail-closed gate).
- Fan-out agents receive **only the facts slice file (absolute path) — never the raw JSON, never the `raw` node**. Guardrail: no agent prompt contains the share-key pattern.
- Password (Mode A) never written to facts/report/review-notes/logs; prefer an explicit `--password <pw>` flag over positional.
- **Build test**: grep every written file (facts, slices, report, review-notes, temp) and every agent prompt for the share-key regex; fail the build if it appears.

## 13.6 Comparison-window derivation
- Anchor on `meta.extractedAt` parsed as **`[DateTimeOffset]`**, never the current clock (determinism).
- **Ignore `compareDateRange.period` entirely**; derive `hasComparison` from presence of non-null `compare` cells.
- Specify per `measure`×`type`; **incomplete current period** (extracted mid-interval) → label "…-to-date" and **disable strict QoQ deltas**; `SINCE`/custom/`baseDate`/`parent` → fall back to the ISO range from date-dimension rows (reliably present) rather than a computed label.
- **Mandatory** date-dimension cross-validation when a Day/Week/Month dimension exists → `periodConfidence: confirmed|derived|unconfirmed`; `unconfirmed` forces a "period labels approximate" caveat.

## 13.7 Fan-out
- Trigger on **distinct categories ≥ 2** (not platform/widget/row counts) OR total data rows > 400; else single-pass. (Two same-category ad platforms → single-pass handles it — it produced the accepted report.) `--fast`/`--thorough` override.
- Shape: one analyst agent per **category** (parallel) + one cross-cutting agent (portfolio, cross-widget discrepancies, blended/multi-provider widgets) → synthesis. Slices passed as **absolute path to a written facts-slice file**.
- **Synthesis completeness gate**: platforms in report == `meta.providers`, each once. Trace each section's numbers against **that platform's slice only**.

## 13.8 Direction / persona / category
- **Per-category direction table** (not substring guessing), full-segment-anchored regex (`(^|:)(cost_micros|spend)$`, not `spend?`); `additive` is a **separate boolean** from `direction`. SEO `position|rank` = **lower-better (core, not edge case)**; email `bounce_rate|unsubscribe|spam` lower-better; GA4 `bounce_rate` lower / `engagement_rate` higher.
- Every rule gated by `appliesToCategories[]` (fail-closed: category not listed → rule doesn't run).
- Closer **forbids evaluative words** (good/bad/win/loss/strong/underperforming) on `direction:neutral` metrics.
- **Persona is category-derived** (dominant category → "senior media buyer" | "senior SEO strategist" | "senior lifecycle/email marketer" | "senior performance marketer" for mixed).

## 13.9 Skill mechanics
- Frontmatter: **`disable-model-invocation: true`** (hard manual-only) + `argument-hint`, `allowed-tools` (pre-authorize the PS calls). Description wording is belt-and-suspenders.
- **Mode A anchored to Swydo hosts**: `^(https?://)?(swy\.do/shares/|app\.swydo\.com/g/)`; other URL-shaped input → error, not blind extraction. Path/`.json` → Mode B. Explicit `--password` flag for edge passwords.
- **Install on Windows: copy** `skill/` into the skills dir (symlink needs admin/Developer Mode); document it; overwrite-on-rerun.

## 13.10 Test matrix (synthetic fixtures — the real file can't exercise these)
manualKpi; unverified-provider units (no `unit`); non-money micros (`engagement_time_micros`→seconds); `meta.warnings` populated; multi-currency; each non-ad category + a mixed report; no-comparison + partial-comparison; incomplete current period; the credential-leak grep over all outputs; low-N swing; blended multi-provider widget; `(group)` aggregate rows. Plus the closer's false-positive cases (trailing punctuation, thousands-separator drift, `+`-prefixed %, bare integers).

## 13.11 Build order
1. `Analyze-SwydoReport.ps1` (functions-first + `-DefineOnly`): load+scrub → validate schema → derive periods → compute headline/timeSeries/breakdowns/portfolioTotals (unit+role-qualified) → run category-gated rules → emit facts + facts slices. 2. Its unit tests (fixtures above). 3. Closer script `Test-ReportNumbers.ps1` (numeric-normalized tracing + surfacing/comparison gates). 4. `SKILL.md` + `report-template.md` (per-category personas; fail-closed checklist). 5. Wire Mode A/B, category-based fan-out, review closer. 6. E2E on report B + a synthetic multi-category fixture; credential-grep. 7. Commit.

## 13.12 Per-category rule config (data-driven — the non-ad ruleset)
A table drives category-specific rules so the engine stays one code path. Metric matching is by id-suffix patterns (anchored, full-segment). `effort→result` generalizes "zero-result spend": fire `ANOM_EFFORT_NO_RESULT` when an effort value ≥ (relative) threshold and its paired result == 0; comparison-based drop fires `ANOM_LOST_<result>` when result was non-zero previous, 0 now.

| category | money | effort→result pairs | quality/guard metrics (fire if adverse & significant) | category-special |
|---|---|---|---|---|
| ads | cost/spend | spend→(conversions\|leads); clicks→conversions | ctr(low), frequency(high), quality_score(low) | ANOM_BUDGET_CONSTRAINED (impression_share / search_lost_is_budget) |
| web-analytics | (none) | sessions→conversions; users→conversions | bounce_rate(high), engagement_rate(low) | goal/conversion-rate divergence by channel |
| seo | (none) | impressions→clicks | position/rank(worsened), bounce_rate(high) | ANOM_RANKING_DROP (position previous→now worse past N), visibility→0 |
| email-crm | (none) | sends→opens; opens→clicks | unsubscribe_rate(high), spam/bounce_rate(high) | list-growth trend; ANOM_ZERO_ENGAGEMENT_SEND (sends≥N, opens 0) |
| ecommerce | revenue | sessions→orders; add_to_cart→orders | conversion_rate(low), refund/return(high) | AOV swing; revenue trend |
| calls | (none) | calls→(qualified\|converted) | missed_call_rate(high), duration(too-short) | first-time-caller / after-hours share |
| other | (none) | — | — | descriptive + direction-safe win/loss only |

Direction table (per-category, full-segment-anchored): lower-better = `cost*`, `cpc`, `cpm`, `cpa`, `cpl`, `cost_per*`, `bounce_rate`, `unsubscribe*`, `spam*`, `refund*`, `position`/`rank*` (SEO core), `missed*`, `search_lost_is*`; higher-better = `conversions`, `clicks`, `impressions`, `reach`, `leads`, `ctr`, `roas`, `revenue`, `orders`, `sessions`, `users`, `opens`, `open_rate`, `engagement*`, `impression_share`, `quality_score`, `sends?`(neutral); neutral = `spend`, `amount_spent`, `budget`, `frequency`, `calls`(volume), unknown. `additive` is a separate boolean (additive: impressions/clicks/conversions/leads/spend/sessions/orders/sends/opens/revenue; NON-additive: reach/frequency/ctr/rate/position/average_*/roas/aov). Every rule/finding records `appliesToCategories` and `confidence`; low-N (< ~30 events on the moved side) → `confidence:low`. Synthetic fixtures (§13.10) must cover one report per category + a mixed report.
