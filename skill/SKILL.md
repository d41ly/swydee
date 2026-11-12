---
name: swydee
description: Generate a senior-performance-marketer client report from a Swydo shared report — either a swy.do share link or an already-parsed v2 extraction/facts JSON. Use ONLY when the user runs /swydee or explicitly asks to analyze / write a report on a Swydo report. Do NOT auto-invoke on unrelated marketing or data questions.
disable-model-invocation: true
argument-hint: "<swy.do link | path\\to\\extraction.json | trend <swy.do link|client:name> | list | cleanup older-than:<7d|1mo|3mo|1yr> (client:<name>|all)> [--password <pw>] [voice:<causal|correlational|executive|analytical|consultative>] [--platform <id>] [--fast|--thorough|--no-trend] [forecast:"<which metric/actions are incomplete, first-last day lost>"] [--out <dir>]"
allowed-tools: Bash, PowerShell, Read, Write
---

# /swydee — Swydo report → client report

Turns a Swydo report into a client-ready report: per-platform overviews with previous-period comparison, analytical insights (wins / needs-attention / anomalies), and recommendations — with **every number deterministically traced to the data**.

**Tools (bundled with this skill).** The PowerShell tools ship inside this skill at `${CLAUDE_SKILL_DIR}/scripts/`: `Get-SwydoReport.ps1` (extractor), `Analyze-SwydoReport.ps1` (analyzer), `Test-ReportNumbers.ps1` (closer), `Manage-SwydoArchive.ps1` (archive + retention), and for the cumulative-trend feature `ConvertTo-SwydoTrendFacts.ps1` + `Update-SwydoLedger.ps1` + `Analyze-SwydoTrend.ps1` + `Sync-SwydoTrend.ps1` (the fail-soft refresh wrapper; see "Trend mode" + Flow step 8). `${CLAUDE_SKILL_DIR}` is this skill's own install directory (the folder holding this SKILL.md), so the paths resolve wherever the skill is installed (personal, project, or plugin). Invoke each with the PowerShell tool as `powershell -NoProfile -File "${CLAUDE_SKILL_DIR}/scripts/<name>.ps1" <args>`. The report template sits beside this file at `${CLAUDE_SKILL_DIR}/report-template.md`.

**Forecast tool.** `Invoke-SwydoForecast.ps1` (also in `scripts/`) estimates what a metric that was DECLARED incomplete would have been (for example conversions lost to a tracking outage) and adds a separate `estimates` block to the facts. It is the only source of a modeled number; see Flow step 2b. Its closer rules live in `scripts/_EstimateCheck.ps1`, which `Test-ReportNumbers.ps1` loads by itself.

## Non-negotiables
- **The model narrates; the tools compute.** You may cite ONLY the pre-formatted display strings that appear in the facts JSON. Do NOT do arithmetic, re-round, sum, average, or derive any number. If a number you want isn't in the facts, you may not use it.
- **Credential safety.** After extraction, open ONLY the facts file. NEVER open, read, echo, or pass to a subagent the raw extraction file or its path — it contains the share key in cleartext. Never put a `swy.do/shares/...` URL or the share key in the report, a subagent prompt, or any written file.

## Flow

### 1. Parse the argument
- If the first token is `list` or `cleanup` → **Retention mode** (see "Retention commands" below); handle it and stop — do not produce a report.
- If the first token is `trend` → **Mode C (trend / cumulative QoQ-YoY history)** (see "Trend mode" below).
- If the first token matches `^(https?://)?(swy\.do/shares/|app\.swydo\.com/g/)` → **Mode A (link)**.
- Else if it ends in `.json` and the file exists → **Mode B (file)**.
- Else → stop with a usage message. Any token starting `--` is a flag; a share password must be given via `--password <pw>` (never positionally).
- A `forecast:"..."` token asks for a modeled estimate of a metric the user says is incomplete (e.g. `forecast:"web form conversions untracked Oct 10-28"`). It carries the declaration for Flow step 2b: which metric or conversion action(s), and the first and last day with lost tracking. It is a request to run the tool, never a number source.
- A `voice:<type>` token selects the report's attribution profile (`causal` (default) | `correlational` | `executive` | `analytical` | `consultative`; unknown → fall back to `causal`). See the voice section of `${CLAUDE_SKILL_DIR}/report-template.md`.

### 2. Produce the facts
- **Mode A:** run `${CLAUDE_SKILL_DIR}/scripts/Get-SwydoReport.ps1 -ShareUrl <link> [-Secret <pw>] -OutDir <tmp>` → note the extraction path (DO NOT open it). Then `${CLAUDE_SKILL_DIR}/scripts/Analyze-SwydoReport.ps1 -InFile <extraction> -OutDir <out>`.
- **Mode B:** validate the file has `meta.schemaVersion` of 2 or 3 (else stop: "re-extract with the current Get-SwydoReport.ps1"). Then `${CLAUDE_SKILL_DIR}/scripts/Analyze-SwydoReport.ps1 -InFile <file> -OutDir <out>`.
- Read the resulting `*.facts.json` (BOM-less UTF-8) — **this is your only data source.**
- Check `meta.compareBasis` before writing any comparison: `untrusted` forbids comparative language outright. See **Comparison basis** in Notes.
- Every flag either tool accepts, with its default, is in **## Parameters** below. Reach for it before
  guessing a flag or re-deriving a default from a script.

### 2b. Forecast an incomplete metric — ONLY when it is declared incomplete
Run this step when, and only when, someone has STATED that a metric is incomplete: the user (a `forecast:"..."` token or a plain request), or a client note in `meta.annotations` (e.g. "tracking was cut off after Oct 9 and fixed on Oct 29"). **Never infer an outage from the numbers** - a metric that merely fell is a loss, not a gap. Skip the step otherwise, and for Mode C (trend facts are not supported).
- **What you must have before running:** (1) who declared it (`-DeclaredBy "client note ANN#1"` or `"user"`, in words - never a link or key); (2) the window as the FIRST and LAST day with lost tracking, inclusive ("cut off after Oct 9, fixed on Oct 29" → `2026-10-10` to `2026-10-28`); (3) which conversion action(s) lost tracking, by their exact row label in the facts' "Conversion action name" breakdown. If the statement does not name the actions or the dates, **ask the user** (show the action rows with their current and previous display strings); do not pick the affected actions yourself from how far each one dropped. Omit `-Action` only when the whole metric was untracked. The metric must be a plain count (conversions, calls, leads); a rate or a money figure is refused.
- **Run:** `${CLAUDE_SKILL_DIR}/scripts/Invoke-SwydoForecast.ps1 -Facts <facts.json> -DeclaredBy "<who>" -OutageStart <yyyy-MM-dd> -OutageEnd <yyyy-MM-dd> [-Action "<label>[;<label>]"] [-Ledger ${CLAUDE_SKILL_DIR}/archive/<client-slug>/ledger.json] [-HistoryMonths <n>]`. Pass `-Ledger` when the client has one (it is read for the trailing conversion-rate history; it is credential-free). For anything the flags cannot say, write a small spec file and pass `-Spec <path>`: `{ "declaredBy": "...", "platform": "<providerId>", "metric": "Conversions", "actions": ["<label>"], "outage": {"start": "yyyy-MM-dd", "end": "yyyy-MM-dd"}, "partials": [ {"action": "<label>", "value": <number recorded in a tracked window>, "start": "...", "end": "...", "source": "<where that number came from>"} ], "excludeMonths": ["yyyy-MM"], "metricNames": {"clicks": "...", "impressions": "...", "cost": "...", "conversionRate": "...", "costPerConversion": "..."} }`. A spec value wins over the matching flag. A `partials` entry names one of the declared actions exactly; for the whole metric leave its `action` out; an entry that matches no target is an input error (exit 2). A `partials` value must itself come from a tool or the user (e.g. "the client says 12 forms were recorded Oct 1-9") - never from your own arithmetic. If the platform's action breakdown is cut by a dimension with another name, add `"actionDimension": "<dimension name>"`.
- **What it does:** computes several simple methods side by side - last period's rate per click and per impression applied to this period's traffic, last period's value moved in step with the actions that kept tracking, and the tracked-day pace extended to the full period - then reports low (smallest), high (largest) and a base (a blend of the prior-level evidence and the tracked-day evidence, with the tracked-day pace weighted by the share of the period that was tracked). With per-action estimates it also derives the account total, the conversion rate and the cost per conversion. The ledger's trailing conversion rate is a cross-check on the total (a method only when the whole metric is incomplete), and is refused when that history is unstable.
- **Exit codes:** `0` = the facts file now carries a top-level `estimates` block (re-read the facts); `1` = every estimate was refused - nothing is written, an `estimates` block left by an earlier run is REMOVED, so tell the user the printed reasons and write the report WITHOUT estimates; `2` = bad input (unreadable JSON, wrong arguments, a non-count metric, an unmatched partial; it also refuses a raw extraction) - the facts are untouched, so fix the arguments and run again. Partial refusals are listed under `estimates.refused[]` with their reasons - say so in the report rather than filling the gap yourself.
- **Using the result:** each `estimates.items[]` entry has an `eid` (`EST#n`), `display` / `displayLow` / `displayHigh`, the `measuredDisplay` it sits beside, a ready `statement`, the `methods[]` (each with `display`, a plain-words `formula`, `inputs[]` with their sources, and its `assumption`), `skippedMethods[]`, `crossChecks[]` and an `uncertainty` statement. Cite them ONLY in the report's `## Estimates (modeled)` section, following `report-template.md`. Everywhere else the report keeps the measured figures, and the measured-data caveat stays in force.
- Run it after any other tool that adds to the facts and before writing the draft; re-running replaces the block. To drop an estimate that was produced, re-run `Analyze-SwydoReport.ps1` for clean facts.
- **Fan-out (step 3):** the per-category slices do not carry the `estimates` block. The synthesizing (orchestrating) pass writes `## Estimates (modeled)` itself from the full facts; analyst subagents never cite an estimate.

### 3. Decide single-pass vs fan-out
- Count distinct `meta.providers[].category`. **Single-pass** if 1 category (and not `--thorough`). **Fan-out** if ≥ 2 distinct categories (or `--thorough`); `--fast` forces single-pass.
- Fan-out: write one facts-slice file per category (the facts subset for that category's platforms) to the out dir, spawn one analyst subagent per category **passing only the slice file path** (never the extraction), plus one cross-cutting agent for portfolio/cross-platform notes; then synthesize. Completeness gate: every `meta.providers` platform appears exactly once in the report.
- **What to read, and what to skip (ANLZ-aUniformLattice-8).** The facts document carries machine
  addressing fields alongside the narrative ones. Read `platforms[].headline` and `findings` for
  numbers, `platforms[].metrics` for coverage, and `breakdowns[].rows[]` `label` + `values` for
  per-row detail. When two metrics on one widget share a display name, `values[<name>]` belongs to
  the FIRST holder and carries that metric's own number, unit and type together
  (ANLZ-aCandidTally-1 S7), so it is internally consistent and safe to quote; the second metric's
  number is NOT quotable at row level. A cell whose display name was ambiguous carries
  `canonical.keyBasis` and is named in the info finding `GAP_METRIC_NAME_AMBIGUOUS`, which lists ids
  and a count and no values.
  **Row findings (ANLZ-aUniformLattice-9).** Every row-level anomaly carries `dimension` (the cut it
  measures, e.g. `Publisher platform / Placement`) and `metricId`. Its statement names that cut, so
  two findings with the same row label are distinguishable rather than contradictory. When the
  widget's total for that metric is not the account total, the statement carries a scope clause —
  `within a N% subset of <Platform> <metric>` or `against a widget total N.Nx the account <metric>`
  — and `scope` holds the same numbers. **That clause is load-bearing: never strip it when moving
  the statement into prose.** Without it, `'CONTENT' is 100% of Impressions (617 of 617)` reads as
  "this platform is all Display" when 617 is 3% of the account.
  SKIP `valuesById`, `rowKey`, `rowKeyBasis`, `valuesByIdScope`, `metricIds`, `scope`,
  `basis`, `contributingWidgetIds`, `observedOnWidgetIds` and `coverageBasis` - they exist so a
  future tool can address a cell by id, and carry no narrative content. Spending attention on
  them costs context and buys nothing.
- **Coverage (ANLZ-aUniformLattice-6):** each platform carries `platforms[].metrics`, one entry per metric the
  dashboard declares for it. An entry with a `reason` is a metric the tool could NOT give an account-level
  value, and the reason says why (`no-usable-cell`, `incomplete-rows`, `blended-undecomposable`,
  `hidden-section`, `not-summable`, `no-total`). Read this to know what a platform can and cannot be said to
  have measured, and to avoid recommending action on a metric the report has no account figure for. It is a
  COVERAGE record only: never quote a number from it. Every quotable number still comes from the sources
  `report-template.md` whitelists.

### 4. Write the report DRAFT — follow `${CLAUDE_SKILL_DIR}/report-template.md` exactly
Write the **draft** (with anchors) to a working path `<out>\<stamp>-<slug>-report.draft.md`. Fill the template from the facts in the selected voice profile (default `causal`). Obey every hard rule in it: verbatim numbers; ALL comparisons narrated as prose (no tables/charts); mandatory caveats; the `<!-- platform:id -->` / `<!-- finding:fid -->` / `<!-- caveat:id -->` anchors, plus `<!-- estimate:EST#n -->` on every estimate line when the facts carry an `estimates` block (these are the verifier's scaffold and get stripped from the delivered file). The voice changes only tone and attribution confidence — never the numbers or caveats.

### 5. Verify + publish — run the closer, fail-closed
Run `${CLAUDE_SKILL_DIR}/scripts/Test-ReportNumbers.ps1 -Report <draft.md> -Facts <facts.json> -PublishTo <out>\<stamp>-<slug>-report.md`. On PASS the closer writes the client copy with all anchors stripped to `-PublishTo` (deterministic strip → the delivered file is the verified text minus comments). If it exits non-zero, it publishes NOTHING — read the violations, **fix the draft** (untraceable numbers, missing caveats/gaps, comparison claims, leaked credentials), and re-run. Never hand-strip anchors or deliver a report the closer rejects. If `meta.compareBasis` is `untrusted`, the closer's comparison-without-data check is what catches comparative language that slipped in — see **Comparison basis** in Notes.

### 6. Deliver
Deliver the published `<out>\<stamp>-<slug>-report.md` (anchor-free, credential-free). Keep the `.draft.md` as the audit/re-verify source. Tell the user the report path and the facts path; summarize the headline in one or two sentences.

### 7. Retain — file the run into the archive
Store the run into the client/date archive:
`${CLAUDE_SKILL_DIR}/scripts/Manage-SwydoArchive.ps1 -Store -Facts <facts.json> -Report <report.md> -Draft <draft.md> -Client "<client>"`
The archive lives **inside the skill** at `${CLAUDE_SKILL_DIR}/archive/` by default (so it travels with the installed skill) — pass `-ArchiveRoot <dir>` only to override. It creates `<archive>/<client-slug>/<YYYY-MM-DD-HH-MM-SS>/` with a `manifest.json` (client, period, scrape + archive dates, per-file sha256) and writes a `.swydee-archive` sentinel. Its fail-closed gate **refuses to store anything still carrying a share credential** (`meta.shareKey`/`shareUrl` or a `swy.do/shares/...` string). The facts snapshot is the record of provenance — it keeps the report re-verifiable and feeds later QoQ/YoY trend work (ad data is mutable, so re-scraping won't reproduce today's numbers). Do NOT pass the raw extraction unless it has been scrubbed to REMOVE `meta.shareKey`/`meta.shareUrl`; otherwise delete the raw — never archive a credential.

### 8. Refresh trend history — Mode A, default-on (opt out with `--fast` or `--no-trend`)
After delivering the primary single-period report, keep the client's cumulative monthly ledger current so QoQ/YoY history survives across pulls. Run **FAIL-SOFT** (a trend failure must NEVER affect the delivered report):
`${CLAUDE_SKILL_DIR}/scripts/Sync-SwydoTrend.ps1 -ShareUrl <link> [-Secret <pw>] -OutDir <tmp>` (there is NO `-Platform` here, by design - see Parameters). It extracts a wide per-platform monthly pull, scrubs it, and merges into `${CLAUDE_SKILL_DIR}/archive/<client-slug>/ledger.json`. If it exits non-zero (e.g. the report has no monthly time-series widget), say "trend history not updated this run" in one line and STOP there — do not retry, do not touch the primary report.
On success, you MAY produce a SEPARATE trend report (never merge trend numbers into the single-period report — they won't trace): run `Analyze-SwydoTrend.ps1 -LedgerFile <archive>/<client-slug>/ledger.json -OutDir <out>` → write a trend draft from the template → verify with `Test-ReportNumbers.ps1` against the **`*.trendanalysis.facts.json`** (its own facts) → deliver as a distinct `-trend-report.md`. Skip this whole step entirely under `--fast`/`--no-trend`, and for Mode B (file) input.

## Retention commands (user-invoked)
When the user asks to review or clean up archived data (first token `list` or `cleanup`), run `Manage-SwydoArchive.ps1`:
- **list** → `-List [-Client "<name>"]`  (read-only inventory by client → entries/dates/sizes).
- **cleanup** `older-than:<7d|1mo|3mo|1yr>` `(client:"<name>" | all)` → `-Cleanup -OlderThan <t> (-Client "<name>" | -All)`.
- **merge** (fold a client accidentally split across two folders into one — e.g. a pre-canonicalization archive) → `-MergeClient -From <slug> -Into <slug>`. Moves `<From>`'s dated snapshots into `<Into>`, unions their ledgers (older-firstSeen value wins; the other is recorded as a restatement, never dropped), moves any notes/context files, then removes the empty `<From>`.
(all default to the skill's `${CLAUDE_SKILL_DIR}/archive/`; add `-ArchiveRoot <dir>` only to target a different archive.)
  **DESTRUCTIVE (cleanup + merge).** ALWAYS run the dry-run first (NO `-Execute`), show the user the exact entries/conflicts it lists, and only re-run adding `-Execute` after the user explicitly confirms. `-All` (whole archive) requires a stronger, explicit confirmation. The tools keep undated/unparseable entries, refuse to act outside the archive root, and skip entries reached through a junction/symlink — but the confirmation is still yours to get.

## Trend mode (cumulative QoQ/YoY history)
`trend <swy.do link> [--password <pw>]` maintains a per-client, gap-free MONTHLY history so quarter-over-quarter / year-over-year comparisons survive across boundaries — history a single report can't hold (ad data is mutable and each platform only serves so far back). Opt-in; the default report flow is untouched. The raw wide extraction is credential-bearing — treat it exactly like Mode A's extraction: **note the path, DO NOT open it.**

Run the pipeline (each step feeds the next):
1. **Extract wide** — `Get-SwydoReport.ps1 -Trend -ShareUrl <link> [-Secret <pw>] -OutDir <tmp>`. Probes each platform's true history ceiling (bracket + bisection; e.g. Google ~48mo, Facebook ~18mo) and pulls monthly. It NEVER uses one uniform window — an overshoot is REFUSED, which would silently blank the shorter platform. The ceiling is read from Swydo's explicit `REJECTED` verdict, never inferred from a window merely coming back empty, so a slow response can no longer masquerade as the end of a client's history. A window that goes unanswered twice yields `coverage[].ceilingUncertain: true` — the ceiling is then a lower bound, and a later run can extend it. Output: `*.trend.json` (raw, has the share key).
2. **Scrub + shape** — `ConvertTo-SwydoTrendFacts.ps1 -InFile <*.trend.json> -OutDir <out>`. The ONLY tool that opens the raw trend extraction; fail-closed credential scrub → `*.trendfacts.json` (safe).
3. **Update the ledger** — `Update-SwydoLedger.ps1 -InFile <*.trendfacts.json>`. Merges into `${CLAUDE_SKILL_DIR}/archive/<client-slug>/ledger.json`: months older than `-K` (default 6) are frozen write-once; recent months refresh, but a null/overshoot pull never clobbers a good value; a unit/currency change forks a new series (never coerced). The ledger is the accumulating union of every window ever pulled (`-ArchiveRoot <dir>` to override its location).
4. **Analyze** — `Analyze-SwydoTrend.ps1 -LedgerFile <archive>/<client-slug>/ledger.json -OutDir <out>`. QoQ/YoY over the settled months, gated by an **honesty gate**: a comparison is emitted only when both endpoints are fully settled + same-basis — otherwise an explicit "no comparison available — <provider> history begins <month>", never a fabricated number; providers with different coverage are never blended. Output: `*.trendanalysis.facts.json` (closer-shaped, `meta.factsVersion`).

Then **continue at step 3 of the Flow** using `*.trendanalysis.facts.json` as the facts source: single-pass vs fan-out, write the report DRAFT from the template in the chosen voice (all comparisons as PROSE), verify + publish with the closer, deliver, and retain (step 7). The trend facts carry QoQ/YoY findings, a monthly `timeSeries`, and honesty-gate `dataGaps` — surface the gaps (the closer forces the major ones). A figure restated after freezing surfaces as a `GAP_RESTATEMENT_SUPPRESSED` anomaly you MUST narrate: the ledger keeps the frozen value and notes the platform's newer number rather than substituting it (the numbers still trace).

**Re-analyze an existing ledger without re-pulling** (e.g. to regenerate a report, or after a new platform accrues history): `trend client:<name>` → run only step 4 on `${CLAUDE_SKILL_DIR}/archive/<client-slug>/ledger.json`, then continue at step 3 of the Flow.

## Parameters

Every flag the tools accept. Defaults are the `param()` defaults; where a default is an empty
sentinel or an expression, the **effective** value and where it resolves are given instead, because
publishing a literal `""` would be misleading. `-DefineOnly` is on every script tabled here: it dot-sources the
script's functions and runs nothing, and is how the suites and any reusing caller load them.

**`Get-SwydoReport.ps1`** — the only network adapter (11)

| flag | default | reach for it when |
|---|---|---|
| `-ShareUrl <url>` | required | always, in Mode A |
| `-OutDir <dir>` | `.\extractions` | always — give each run its own directory (§4 isolation) |
| `-Secret <pw>` | none (unprotected share) | the share link asks for a password |
| `-Platform <id>` | all providers | pulling only some platforms; forces `PROVIDER_FILTERED` |
| `-MaxWaitSec <n>` | `90` | the same widgets keep coming back `incomplete` |
| `-MaxTotalWaitSec <n>` | `420` | bounding a whole run against a dead backend |
| `-PageSize <n>` | `500` | a breakdown truncates; raises rows fetched per widget |
| `-CacheDir <dir>` | `%LOCALAPPDATA%\swydee\ceilings` (:1085) | isolating or inspecting the trend ceiling-probe cache |
| `-Trend` | off | pulling the wide monthly history instead of the report window |
| `-ProbeFields` | off | diagnosing field coverage; records `meta.fieldProbe` |
| `-DefineOnly` | off | loading the functions without running |

**`Analyze-SwydoReport.ps1`** — the compute core (7)

| flag | default | reach for it when |
|---|---|---|
| `-InFile <path>` | required | always |
| `-OutDir <dir>` | the input's directory (:1013) | writing facts somewhere else |
| `-WinLossPct <n>` | `10.0` | tuning the win/loss delta threshold |
| `-SmallN <n>` | `30` | tuning when a finding is tagged `confidence='low'` |
| `-BrandSharePct <n>` | `25.0` | tuning the brand-baseline dominance gate |
| `-ScopeFullPct <n>` | `0.95` | tuning when a row finding's widget total counts as the full account total |
| `-ScopeOverPct <n>` | `1.05` | tuning when a widget total is treated as EXCEEDING the account total (a cross-tab) |
| `-NotesFile <path>` | none | supplying client context notes from a file |
| `-DefineOnly` | off | loading the functions without running |

**`Test-ReportNumbers.ps1`** — the closer (5)

| flag | default | reach for it when |
|---|---|---|
| `-Report <path>` | required | always |
| `-Facts <path>` | required | always |
| `-PublishTo <path>` | no publish | writing the anchor-stripped client copy on PASS |
| `-TraceRecommendations` | off | also tracing numbers inside the recommendations section |
| `-DefineOnly` | off | loading the functions without running |

**`Invoke-SwydoForecast.ps1`** — modeled estimates for a declared-incomplete metric (13)

| flag | default | reach for it when |
|---|---|---|
| `-Facts <path>` | required | always; updated in place unless `-OutFile` |
| `-DeclaredBy <text>` | required (flag or `-Spec`; the spec wins) | always - who states the data is incomplete (`"client note ANN#1"`, `"user"`) |
| `-OutageStart <yyyy-MM-dd>` | required (flag or `-Spec`; the spec wins) | first day with lost tracking |
| `-OutageEnd <yyyy-MM-dd>` | required (flag or `-Spec`; the spec wins) | last day with lost tracking (inclusive) |
| `-Action "<label>[;<label>]"` | none (the whole metric) | only some conversion actions lost tracking |
| `-Metric <name>` | `Conversions` | the incomplete metric has another display name |
| `-Ledger <path>` | none | the client has a ledger - adds the trailing-rate history |
| `-HistoryMonths <n>` | `6` | the recent history has a setup change; a shorter stable stretch (minimum 3 months) |
| `-MinTrackedDays <n>` | `3` | tuning how few tracked days the run-rate method accepts |
| `-Platform <id>` | the only platform | the facts hold more than one platform |
| `-Spec <path>` | none | passing partial-window observations, excluded months or other metric names |
| `-OutFile <path>` | `-Facts` (in place) | keeping the original facts file untouched |
| `-DefineOnly` | off | loading the functions without running |

**`Manage-SwydoArchive.ps1`** — archive + registry (16). Modes: `-Store`, `-List`, `-Cleanup`,
`-MergeClient`. `-ArchiveRoot` defaults to the installed skill's own `archive/` (:35) — the client
history lives there, so override it rather than moving it. `-Store` takes `-Facts`, `-Report`,
`-Draft`, `-Extraction`, `-Client`. `-Cleanup` takes `-OlderThan`, `-All` and is a dry run until
`-Execute`. `-MergeClient` takes `-From` and `-Into`. Plus `-DefineOnly`.

**Trend tools**

| script | flags |
|---|---|
| `Sync-SwydoTrend.ps1` (6) | `-ShareUrl` (required), `-Secret`, `-OutDir` (`.\trend-tmp`), `-ArchiveRoot`, `-CacheDir`, `-DefineOnly`. **There is no `-Platform`** — trend sync always covers the FULL account so the ledger never accumulates a partial history. |
| `ConvertTo-SwydoTrendFacts.ps1` (3) | `-InFile` (required), `-OutDir` (the input's directory, :71), `-DefineOnly` |
| `Update-SwydoLedger.ps1` (6) | `-InFile` (required), `-ArchiveRoot` (the skill's `archive/`, :170), `-Client` (from the facts, :195), `-NowIso` (now, :171), `-K <n>` (`6`, the freeze horizon in months), `-DefineOnly` |
| `Analyze-SwydoTrend.ps1` (5) | `-LedgerFile` (required), `-OutDir` (the ledger's directory, :117), `-WinLossPct` (`10`), `-PeriodKpiFacts`, `-DefineOnly` |

## Notes
- Coverage: surface every finding with `confidence` normal and every anomaly in the insights section; every `dataGaps`/`discrepancies` finding of severity ≥ major and every `meta.comparisonCaveats` MUST appear (the closer enforces the major ones).
- **Estimates are not facts.** Numbers from `estimates` (Flow step 2b) are modeled. The closer traces them only on a body line carrying `<!-- estimate:EST#n -->` directly under a heading that reads exactly `## Estimates (modeled)`, and on such a line requires a visible estimate word and no comparison with a previous period. Report-wide it requires every action / total estimate to be presented with its base, low and high, a plain "not measured" statement in the section, no visible `EST#n`, and no HTML comment spanning lines. A stated estimate number anywhere else (including Recommendations), or a rounded one ("about 57"), fails as `estimate-misuse`; the one case it cannot tell apart is an estimate that happens to equal a measured figure already in scope. Violation types: `unknown-estimate-anchor`, `estimate-outside-section`, `estimate-label-missing`, `estimate-compared-to-previous`, `estimate-misuse`, `estimates-not-surfaced`, `estimate-base-missing`, `estimate-range-missing`, `estimate-disclosure-missing`, `estimate-internal-id-visible`, `estimate-anchor-on-heading`, `estimate-multiline-comment`, `estimate-item-without-eid`. Never move an estimate into a platform section, a headline bullet, the insights, or a comparison against a previous period.
- **Context annotations.** Analyze collects real client notes from the report's TEXT widgets (layout headers like "Google Ads" are filtered out) into `meta.annotations`. To add external context (e.g. an account-change log the user placed in the client folder), pass `Analyze-SwydoReport.ps1 -NotesFile <path>` (repeatable; plain text). Surface annotations verbatim in the report's "Context (unverified, client-supplied)" section with each `<!-- annotation:<aid> -->` anchor, and cite them ONLY as temporal co-occurrence — never as cause (the closer scopes a note's numbers to its anchored line and treats them as non-comparison, so a note can't launder a fabricated or comparative figure).
- **--platform filter.** `--platform <providerId>` (repeatable) pulls/analyzes only those platforms; the report MUST then surface the forced `PROVIDER_FILTERED` data-gap naming the excluded platforms (it is a partial view).
- If Mode A extraction returns warnings (`meta.warnings`) or empty widgets, surface them as data gaps — never present a clean report over incomplete data.
- **Comparison basis.** The previous-period column is not inherited from the dashboard. The extractor
  COMPUTES the preceding window and passes it explicitly as `{start, type:'FROM'}`, so `cells` and
  `compareCells` come from ONE payload per widget — there is no second pull for the previous period.
  (A RELATIVE primary window additionally costs one extra fetch of a single probe widget, which
  fails the run closed when our resolved window and Swydo's relative range disagree.)
  `meta.periodResolved` records the two windows and `meta.compareBasis` records how much to trust
  them. Three values reach the facts:
  - `computed` — the window was proven. Comparisons are real; narrate them normally.
  - `untrusted` — the window could NOT be proven. Every comparison is suppressed: no `previous`, no
    `deltaPct`, no `displayDelta`, `hasComparison` false, and no cross-widget previous-period
    discrepancy. The report must then carry **no comparative language at all** — not "up", not
    "down", not "flat". There is nothing to compare against.
  - `unknown` — the facts came from an extraction predating this contract. It behaves like
    `computed` (the gate matches the literal `untrusted` only), so older artifacts keep comparing.
  Because the window is ours rather than the dashboard's, a report can legitimately disagree with a
  like-for-like view on screen — especially when the dashboard has comparison switched off. That is
  what the forced `GAP_WARNINGS` disclosure exists to say, and it must reach the delivered report.
- **Completeness gate.** Swydo computes widget data asynchronously and pushes a per-widget verdict on its websocket: `RESOLVED` (data ready) or `REJECTED` (window out of range). The extractor waits for that verdict instead of guessing, and classifies every data widget `filled`, `empty-resolved` (genuinely no data in the period — fine), `rejected`, or `incomplete`. Any `incomplete` widget sets `meta.extractionComplete: false` and lists the widget under `meta.incompleteWidgets`. Analyze turns that into a **critical** `GAP_EXTRACTION_INCOMPLETE`, and the closer **refuses to publish** — a report whose numbers all trace can still be totals over partial data. If you hit it, re-extract; raise `-MaxWaitSec` only if the same widgets keep failing. `Update-SwydoLedger.ps1` refuses an incomplete trend pull for the same reason: partial months must never freeze into the cumulative ledger.
- **Patience flags.** `-MaxWaitSec` and `-MaxTotalWaitSec` (see Parameters for defaults) bound per-widget and whole-run waiting on `Get-SwydoReport.ps1`, and apply to the default and `-Trend` paths. `meta.fetchBudget` records what the run actually spent, so a slow client is diagnosable from the artifact alone. An extraction produced before this gate existed carries no `extractionComplete` key and is read as complete, so old files keep working unchanged.
- **"Swydo rejected the GraphQL query".** If extraction stops with `Swydo rejected the GraphQL query (HTTP 400, GRAPHQL_VALIDATION_FAILED): <Swydo's message>`, Swydo has changed its API and the extractor's query no longer matches it. Do NOT re-run or raise the wait flags; no amount of waiting fixes a rejected query. Report Swydo's message to the user: `Get-SwydoReport.ps1` needs a code fix. (Before EXTR-aStrictSchema-1 this failure was invisible, and showed up instead as every data widget `incomplete (budget-exhausted)`.)
