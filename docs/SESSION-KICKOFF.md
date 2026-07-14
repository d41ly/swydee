# Session kickoff manifest — swydee

<!-- kickoff-manifest: v1.0 · instantiated from coding-governance skills/session-kickoff/MANIFEST-TEMPLATE.md -->

The project layer read by the generic `/session-kickoff` skill (the engine). Precedence on
conflicts: **`CLAUDE.md` > this file > the skill** — flag any conflict so it gets fixed. Keep
this file SHORT: it holds only what the engine can't derive from git or `CLAUDE.md`.

## §A — Task template (fill per kickoff)

> - **Title:** …
> - **Goal (1–2 sentences):** …
> - **IN scope:** …
> - **OUT / non-goals** (explicit cut-line): …
> - **Acceptance check** (the observation that proves THIS change — a test it adds, a gate it
>   moves, an observed behavior; *not* an unrelated green check): …
> - **Gates it must pass:** …
> - **Risk tier:** design-pass | direct

## §B — Orientation (project facts the engine reads)

- **Repo layout:** single checkout at `C:\projects\swydee` (no worktree fan-out).
- **Remote · default branch:** `origin` · `main`
- **Branch conventions:** feature work on `feat/<slug>` off `main`, merged back with a merge
  commit (`Merge feat/<slug>: <summary>`); docs/status-only commits may land directly on `main`.
- **Governing docs:** the **units index** in `docs/specs/context-and-canon-spec.md` is
  authoritative for what is shipped/deferred. Inside each spec, the v2 AMENDMENTS/review-override
  block at the top OVERRIDES the unit bodies below it. `SKILL_BUILD_SPEC.md` §13 (hardened
  design) supersedes its §1–12 on any conflict. `data_gaps.md` = candidate analyzer rules, not
  ratified spec.
- **Governance playbook:** not adopted.

### Pointer map (load the row(s) the task touches)

| Area / stream | Governing doc(s) | First code entrypoints |
|---|---|---|
| Swydo extraction (API/JWT/GraphQL/WS) | `SWYDO_REPORT_EXTRACTION_SPEC.md` | `skill/scripts/Get-SwydoReport.ps1` · `Test-Extractor.ps1` |
| Single-report analysis + facts | `SKILL_BUILD_SPEC.md` §13 · `docs/specs/canonical-total-spec.md` · `docs/specs/cross-widget-reconciliation-spec.md` | `skill/scripts/Analyze-SwydoReport.ps1` · `Test-Analyze.ps1` |
| Trend / ledger pipeline | `docs/specs/context-and-canon-spec.md` (U4) · `docs/specs/cross-widget-reconciliation-spec.md` (U7b) | `skill/scripts/Sync-SwydoTrend.ps1`, `ConvertTo-SwydoTrendFacts.ps1`, `Update-SwydoLedger.ps1`, `Analyze-SwydoTrend.ps1` · `Test-Sync.ps1`, `Test-TrendFacts.ps1`, `Test-Ledger.ps1`, `Test-TrendAnalyze.ps1` |
| Closer (report number verification) | `SKILL_BUILD_SPEC.md` §13.1 | `skill/scripts/Test-ReportNumbers.ps1` · `Test-Closer.ps1` |
| Archive / client registry | `docs/specs/context-and-canon-spec.md` (U1) | `skill/scripts/Manage-SwydoArchive.ps1` · `Test-Archive.ps1` |
| Skill orchestration + report voice | `skill/SKILL.md` · `skill/report-template.md` | `skill/SKILL.md` |

### Gate commands (the merge bar)

```powershell
# From the repo root; every suite must print "0 failed" and exit 0.
.\Test-Analyze.ps1
.\Test-Closer.ps1
.\Test-Extractor.ps1
.\Test-Archive.ps1
.\Test-Ledger.ps1
.\Test-Sync.ps1
.\Test-TrendAnalyze.ps1
.\Test-TrendFacts.ps1
```

ALL suites re-run green on every unit, not just the touched one (green-count contract: a unit
is additive on its suite's count; other suites' counts stay unchanged).

### Tier rule

Any change touching the extractor, a credential path, the closer contract, the facts schema, or
the default report surface is **design-pass**: a written spec (goal · scope · non-goals ·
acceptance) under `docs/specs/`, adversarially reviewed, with the review verdict folded in as an
AMENDMENTS block BEFORE building — one commit/review boundary per unit. Docs, additive tests,
and template wording are **direct**.

### ID + ledger protocol

Unit ids `U<seq>[a|b]` (e.g. `U7b`). The ledger is the **units index table** in
`docs/specs/context-and-canon-spec.md`: every new unit gets a row (Unit · Title · Spec link ·
Status) before build; Status moves `SPEC` → `shipped` (or `DEFERRED (<reason>)`). Collision
check: grep the units index for the next free `U<seq>`.

### Environment traps worth front-loading

- PowerShell **5.1** / .NET Framework only: no `&&`/`||`, no ternary, no `??` — parser errors.
- Source files are **pure ASCII**; non-ASCII glyphs are built via `[char]0x...` at runtime.
- Hardened scripts are reused via `-DefineOnly` dot-sourcing (functions-first pattern) and are
  **never behaviorally modified**; guard captured vars with the `$my*` prefix when dot-sourcing.
- `@($null).Count -eq 1`: always `@(...)`-wrap collections before `.Count`/indexing.
- The default single-report output path must stay **byte-for-byte unchanged** — every change is
  additive-in-facts (new `meta` fields / findings only). Sole exception: the reviewed, disclosed U9
  flip-set waiver (`headline-rank-precedence-spec.md` D1/D3) — a zero-dim KPI superseding a doc-earlier
  table total changes the flipped cells (always disclosed in-facts) and bumps `meta.canonicalVersion` 1->2.
- Every write path keeps its **fail-closed credential gate**; only `ConvertTo-SwydoTrendFacts`
  and `Analyze-SwydoReport` may open raw extractions.
- The model does no arithmetic: all numbers are computed in PS and must trace through the
  closer (`Test-ReportNumbers.ps1`); an untraceable number blocks publish.
- Suites exit 1 on any failure and print `RESULT: N passed, M failed` — assert exit 0, don't
  parse prose.
