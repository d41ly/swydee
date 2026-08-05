---
name: swydee
description: Generate a senior-performance-marketer client report from a Swydo shared report — either a swy.do share link or an already-parsed v2 extraction/facts JSON. Use ONLY when the user runs /swydee or explicitly asks to analyze / write a report on a Swydo report. Do NOT auto-invoke on unrelated marketing or data questions.
disable-model-invocation: true
argument-hint: "<swy.do link | path\\to\\extraction.json | trend <swy.do link|client:name> | list | cleanup older-than:<7d|1mo|3mo|1yr> (client:<name>|all)> [--password <pw>] [voice:<causal|correlational|executive|analytical|consultative>] [--platform <id>] [--fast|--thorough|--no-trend] [--out <dir>]"
allowed-tools: Bash, PowerShell, Read, Write
---

# /swydee — Swydo report → client report

Turns a Swydo report into a client-ready report: per-platform overviews with previous-period comparison, analytical insights (wins / needs-attention / anomalies), and recommendations — with **every number deterministically traced to the data**.

**Tools (bundled with this skill).** The PowerShell tools ship inside this skill at `${CLAUDE_SKILL_DIR}/scripts/`: `Get-SwydoReport.ps1` (extractor), `Analyze-SwydoReport.ps1` (analyzer), `Test-ReportNumbers.ps1` (closer), `Manage-SwydoArchive.ps1` (archive + retention), and for the cumulative-trend feature `ConvertTo-SwydoTrendFacts.ps1` + `Update-SwydoLedger.ps1` + `Analyze-SwydoTrend.ps1` + `Sync-SwydoTrend.ps1` (the fail-soft refresh wrapper; see "Trend mode" + Flow step 8). `${CLAUDE_SKILL_DIR}` is this skill's own install directory (the folder holding this SKILL.md), so the paths resolve wherever the skill is installed (personal, project, or plugin). Invoke each with the PowerShell tool as `powershell -NoProfile -File "${CLAUDE_SKILL_DIR}/scripts/<name>.ps1" <args>`. The report template sits beside this file at `${CLAUDE_SKILL_DIR}/report-template.md`.

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
- A `voice:<type>` token selects the report's attribution profile (`causal` (default) | `correlational` | `executive` | `analytical` | `consultative`; unknown → fall back to `causal`). See the voice section of `${CLAUDE_SKILL_DIR}/report-template.md`.

### 2. Produce the facts
- **Mode A:** run `${CLAUDE_SKILL_DIR}/scripts/Get-SwydoReport.ps1 -ShareUrl <link> [-Secret <pw>] -OutDir <tmp>` → note the extraction path (DO NOT open it). Then `${CLAUDE_SKILL_DIR}/scripts/Analyze-SwydoReport.ps1 -InFile <extraction> -OutDir <out>`.
- **Mode B:** validate the file has `meta.schemaVersion` of 2 or 3 (else stop: "re-extract with the current Get-SwydoReport.ps1"). Then `${CLAUDE_SKILL_DIR}/scripts/Analyze-SwydoReport.ps1 -InFile <file> -OutDir <out>`.
- Read the resulting `*.facts.json` (BOM-less UTF-8) — **this is your only data source.**
- Check `meta.compareBasis` before writing any comparison: `untrusted` forbids comparative language outright. See **Comparison basis** in Notes.
- Every flag either tool accepts, with its default, is in **## Parameters** below. Reach for it before
  guessing a flag or re-deriving a default from a script.

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
  SKIP `valuesById`, `rowKey`, `rowKeyBasis`, `valuesByIdScope`, `metricIds`,
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
Write the **draft** (with anchors) to a working path `<out>\<stamp>-<slug>-report.draft.md`. Fill the template from the facts in the selected voice profile (default `causal`). Obey every hard rule in it: verbatim numbers; ALL comparisons narrated as prose (no tables/charts); mandatory caveats; the `<!-- platform:id -->` / `<!-- finding:fid -->` / `<!-- caveat:id -->` anchors (these are the verifier's scaffold and get stripped from the delivered file). The voice changes only tone and attribution confidence — never the numbers or caveats.

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

Every flag the eight tools accept. Defaults are the `param()` defaults; where a default is an empty
sentinel or an expression, the **effective** value and where it resolves are given instead, because
publishing a literal `""` would be misleading. `-DefineOnly` is on all eight: it dot-sources the
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
