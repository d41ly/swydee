---
name: swydee
description: Generate a senior-performance-marketer client report from a Swydo shared report — either a swy.do share link or an already-parsed v2 extraction/facts JSON. Use ONLY when the user runs /swydee or explicitly asks to analyze / write a report on a Swydo report. Do NOT auto-invoke on unrelated marketing or data questions.
disable-model-invocation: true
argument-hint: "<swy.do link | path\\to\\extraction.json | list | cleanup older-than:<7d|1mo|3mo|1yr> (client:<name>|all)> [--password <pw>] [voice:<causal|correlational|executive|analytical|consultative>] [--fast|--thorough] [--out <dir>]"
allowed-tools: Bash, PowerShell, Read, Write
---

# /swydee — Swydo report → client report

Turns a Swydo report into a client-ready report: per-platform overviews with previous-period comparison, analytical insights (wins / needs-attention / anomalies), and recommendations — with **every number deterministically traced to the data**.

**Tools (bundled with this skill).** The PowerShell tools ship inside this skill at `${CLAUDE_SKILL_DIR}/scripts/`: `Get-SwydoReport.ps1` (extractor), `Analyze-SwydoReport.ps1` (analyzer), `Test-ReportNumbers.ps1` (closer), `Manage-SwydoArchive.ps1` (archive + retention). `${CLAUDE_SKILL_DIR}` is this skill's own install directory (the folder holding this SKILL.md), so the paths resolve wherever the skill is installed (personal, project, or plugin). Invoke each with the PowerShell tool as `powershell -NoProfile -File "${CLAUDE_SKILL_DIR}/scripts/<name>.ps1" <args>`. The report template sits beside this file at `${CLAUDE_SKILL_DIR}/report-template.md`.

## Non-negotiables
- **The model narrates; the tools compute.** You may cite ONLY the pre-formatted display strings that appear in the facts JSON. Do NOT do arithmetic, re-round, sum, average, or derive any number. If a number you want isn't in the facts, you may not use it.
- **Credential safety.** After extraction, open ONLY the facts file. NEVER open, read, echo, or pass to a subagent the raw extraction file or its path — it contains the share key in cleartext. Never put a `swy.do/shares/...` URL or the share key in the report, a subagent prompt, or any written file.

## Flow

### 1. Parse the argument
- If the first token is `list` or `cleanup` → **Retention mode** (see "Retention commands" below); handle it and stop — do not produce a report.
- If the first token matches `^(https?://)?(swy\.do/shares/|app\.swydo\.com/g/)` → **Mode A (link)**.
- Else if it ends in `.json` and the file exists → **Mode B (file)**.
- Else → stop with a usage message. Any token starting `--` is a flag; a share password must be given via `--password <pw>` (never positionally).
- A `voice:<type>` token selects the report's attribution profile (`causal` (default) | `correlational` | `executive` | `analytical` | `consultative`; unknown → fall back to `causal`). See the voice section of `${CLAUDE_SKILL_DIR}/report-template.md`.

### 2. Produce the facts
- **Mode A:** run `${CLAUDE_SKILL_DIR}/scripts/Get-SwydoReport.ps1 -ShareUrl <link> [-Secret <pw>] -OutDir <tmp>` → note the extraction path (DO NOT open it). Then `${CLAUDE_SKILL_DIR}/scripts/Analyze-SwydoReport.ps1 -InFile <extraction> -OutDir <out>`.
- **Mode B:** validate the file has `meta.schemaVersion == 2` (else stop: "re-extract with the current Get-SwydoReport.ps1"). Then `${CLAUDE_SKILL_DIR}/scripts/Analyze-SwydoReport.ps1 -InFile <file> -OutDir <out>`.
- Read the resulting `*.facts.json` (BOM-less UTF-8) — **this is your only data source.**

### 3. Decide single-pass vs fan-out
- Count distinct `meta.providers[].category`. **Single-pass** if 1 category (and not `--thorough`). **Fan-out** if ≥ 2 distinct categories (or `--thorough`); `--fast` forces single-pass.
- Fan-out: write one facts-slice file per category (the facts subset for that category's platforms) to the out dir, spawn one analyst subagent per category **passing only the slice file path** (never the extraction), plus one cross-cutting agent for portfolio/cross-platform notes; then synthesize. Completeness gate: every `meta.providers` platform appears exactly once in the report.

### 4. Write the report DRAFT — follow `${CLAUDE_SKILL_DIR}/report-template.md` exactly
Write the **draft** (with anchors) to a working path `<out>\<stamp>-<slug>-report.draft.md`. Fill the template from the facts in the selected voice profile (default `causal`). Obey every hard rule in it: verbatim numbers; ALL comparisons narrated as prose (no tables/charts); mandatory caveats; the `<!-- platform:id -->` / `<!-- finding:fid -->` / `<!-- caveat:id -->` anchors (these are the verifier's scaffold and get stripped from the delivered file). The voice changes only tone and attribution confidence — never the numbers or caveats.

### 5. Verify + publish — run the closer, fail-closed
Run `${CLAUDE_SKILL_DIR}/scripts/Test-ReportNumbers.ps1 -Report <draft.md> -Facts <facts.json> -PublishTo <out>\<stamp>-<slug>-report.md`. On PASS the closer writes the client copy with all anchors stripped to `-PublishTo` (deterministic strip → the delivered file is the verified text minus comments). If it exits non-zero, it publishes NOTHING — read the violations, **fix the draft** (untraceable numbers, missing caveats/gaps, comparison claims, leaked credentials), and re-run. Never hand-strip anchors or deliver a report the closer rejects.

### 6. Deliver
Deliver the published `<out>\<stamp>-<slug>-report.md` (anchor-free, credential-free). Keep the `.draft.md` as the audit/re-verify source. Tell the user the report path and the facts path; summarize the headline in one or two sentences.

### 7. Retain — file the run into the archive
Store the run into the client/date archive:
`${CLAUDE_SKILL_DIR}/scripts/Manage-SwydoArchive.ps1 -Store -Facts <facts.json> -Report <report.md> -Draft <draft.md> -Client "<client>" -ArchiveRoot <archive-root>`
It creates `<archive-root>/<client-slug>/<YYYY-MM-DD-HH-MM-SS>/` with a `manifest.json` (client, period, scrape + archive dates, per-file sha256) and writes a `.swydee-archive` sentinel. Its fail-closed gate **refuses to store anything still carrying a share credential** (`meta.shareKey`/`shareUrl` or a `swy.do/shares/...` string). The facts snapshot is the record of provenance — it keeps the report re-verifiable and feeds later QoQ/YoY trend work (ad data is mutable, so re-scraping won't reproduce today's numbers). Do NOT pass the raw extraction unless it has been scrubbed to REMOVE `meta.shareKey`/`meta.shareUrl`; otherwise delete the raw — never archive a credential.

## Retention commands (user-invoked)
When the user asks to review or clean up archived data (first token `list` or `cleanup`), run `Manage-SwydoArchive.ps1`:
- **list** → `-List [-Client "<name>"] -ArchiveRoot <root>`  (read-only inventory by client → entries/dates/sizes).
- **cleanup** `older-than:<7d|1mo|3mo|1yr>` `(client:"<name>" | all)` → `-Cleanup -OlderThan <t> (-Client "<name>" | -All) -ArchiveRoot <root>`.
  **DESTRUCTIVE.** ALWAYS run the dry-run first (NO `-Execute`), show the user the exact entries it lists as removable, and only re-run adding `-Execute` after the user explicitly confirms. `-All` (whole archive) requires a stronger, explicit confirmation. The tool keeps undated/unparseable entries, refuses to delete outside the archive root, and skips entries containing a junction/symlink — but the confirmation is still yours to get.

## Notes
- Coverage: surface every finding with `confidence` normal and every anomaly in the insights section; every `dataGaps`/`discrepancies` finding of severity ≥ major and every `meta.comparisonCaveats` MUST appear (the closer enforces the major ones).
- If Mode A extraction returns warnings (`meta.warnings`) or empty widgets, surface them as data gaps — never present a clean report over incomplete data.
