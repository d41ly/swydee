---
name: swydee
description: Generate a senior-performance-marketer client report from a Swydo shared report — either a swy.do share link or an already-parsed v2 extraction/facts JSON. Use ONLY when the user runs /swydee or explicitly asks to analyze / write a report on a Swydo report. Do NOT auto-invoke on unrelated marketing or data questions.
disable-model-invocation: true
argument-hint: "<swy.do link | path\\to\\extraction.json> [--password <pw>] [--fast|--thorough] [--out <dir>]"
allowed-tools: Bash, PowerShell, Read, Write
---

# /swydee — Swydo report → client report

Turns a Swydo report into a client-ready report: per-platform overviews with previous-period comparison, analytical insights (wins / needs-attention / anomalies), and recommendations — with **every number deterministically traced to the data**. Scripts live in the `swydee` repo (`Get-SwydoReport.ps1`, `Analyze-SwydoReport.ps1`, `Test-ReportNumbers.ps1`); run them from there.

## Non-negotiables
- **The model narrates; the tools compute.** You may cite ONLY the pre-formatted display strings that appear in the facts JSON. Do NOT do arithmetic, re-round, sum, average, or derive any number. If a number you want isn't in the facts, you may not use it.
- **Credential safety.** After extraction, open ONLY the facts file. NEVER open, read, echo, or pass to a subagent the raw extraction file or its path — it contains the share key in cleartext. Never put a `swy.do/shares/...` URL or the share key in the report, a subagent prompt, or any written file.

## Flow

### 1. Parse the argument
- If the first token matches `^(https?://)?(swy\.do/shares/|app\.swydo\.com/g/)` → **Mode A (link)**.
- Else if it ends in `.json` and the file exists → **Mode B (file)**.
- Else → stop with a usage message. Any token starting `--` is a flag; a share password must be given via `--password <pw>` (never positionally).

### 2. Produce the facts
- **Mode A:** run `Get-SwydoReport.ps1 -ShareUrl <link> [-Secret <pw>] -OutDir <tmp>` → note the extraction path (DO NOT open it). Then `Analyze-SwydoReport.ps1 -InFile <extraction> -OutDir <out>`.
- **Mode B:** validate the file has `meta.schemaVersion == 2` (else stop: "re-extract with the current Get-SwydoReport.ps1"). Then `Analyze-SwydoReport.ps1 -InFile <file> -OutDir <out>`.
- Read the resulting `*.facts.json` (BOM-less UTF-8) — **this is your only data source.**

### 3. Decide single-pass vs fan-out
- Count distinct `meta.providers[].category`. **Single-pass** if 1 category (and not `--thorough`). **Fan-out** if ≥ 2 distinct categories (or `--thorough`); `--fast` forces single-pass.
- Fan-out: write one facts-slice file per category (the facts subset for that category's platforms) to the out dir, spawn one analyst subagent per category **passing only the slice file path** (never the extraction), plus one cross-cutting agent for portfolio/cross-platform notes; then synthesize. Completeness gate: every `meta.providers` platform appears exactly once in the report.

### 4. Write the report — follow `report-template.md` exactly
Fill the template from the facts. Obey every hard rule in it (verbatim numbers, mandatory caveats, `<!-- platform:id -->` and `<!-- finding:fid -->` anchors, no arithmetic, correlational-not-causal voice).

### 5. Verify — run the closer, fail-closed
Run `Test-ReportNumbers.ps1 -Report <report.md> -Facts <facts.json>`. If it exits non-zero, read the violations and **fix the report** (remove/correct untraceable numbers, add missing caveats/gaps, fix comparison claims, remove leaked credentials), then re-run. Do NOT deliver a report the closer rejects.

### 6. Deliver
Save `<out>\<stamp>-<report-slug>-report.md` (credential-free). Tell the user the report path and the facts path (for audit). Summarize the headline in one or two sentences.

## Notes
- Coverage: surface every finding with `confidence` normal and every anomaly in the insights section; every `dataGaps`/`discrepancies` finding of severity ≥ major and every `meta.comparisonCaveats` MUST appear (the closer enforces the major ones).
- If Mode A extraction returns warnings (`meta.warnings`) or empty widgets, surface them as data gaps — never present a clean report over incomplete data.
