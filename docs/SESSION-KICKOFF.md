# Session kickoff manifest — swydee

<!-- kickoff-manifest: v1.1 · instantiated from coding-governance skills/session-kickoff/MANIFEST-TEMPLATE.md -->
<!-- manifest-audit
last-audit: 2026-08-04T13:25:56+03:00 @ b20d4e9357a806001dce521402ee66f3ebfe3d29
watch: AGENTS.md; skill; tools; scripts; memory-tree; memory-recall; .memory-tree.conf; Test-*.ps1
verify-paths: AGENTS.md; memory/trend/builds/2026-07-07-TREND-aCanonicalClient/spec/2026-07-07-spec-aCanonicalClient-1.md; tools/gate-legs.json
check-script: scripts/manifest-check.sh
-->

The project layer read by the generic `/session-kickoff` skill (the engine). Precedence on
conflicts: **`CLAUDE.md` > this file > the skill** — flag any conflict so it gets fixed. Keep
this file SHORT: it holds only what the engine can't derive from git or `CLAUDE.md`; the full
ruleset lives in `AGENTS.md`, referenced — not duplicated — here.

> Note on that precedence line: `CLAUDE.md` is a one-line `@AGENTS.md` import, and `AGENTS.md` is
> the project-agnostic playbook instantiated. So that it cannot outrank swydee's own project layer,
> `AGENTS.md` carries an explicit project-layer deferral right after its version marker: on any
> swydee-specific fact, **this file wins and `AGENTS.md` is the thing to fix.**

## The ratchet — how this file stays true

- Every kickoff audits this file (engine Step 2b runs `manifest-check.sh`) and repairs drift on the
  spot — fix or delete stale rows; a deep restructure becomes a flagged task instead.
- Every work-unit that changed what this file front-loads writes the delta back before wrap-up — a
  gate command, entrypoint, governing doc, layout/branch convention, a trap hit, a doc/memory claim
  found stale, or **a fact the session had to re-derive that this file should have front-loaded**
  (the accretion trigger); no delta → no touch.
- `last-audit` is an assertion of verification, re-stamped ONLY after actually re-verifying §B, with
  a delta line (`manifest-audit: delta <none|summary incl. deletions> · watch-commits-since-stamp:
  <n>`, n counted from the OLD stamp before re-stamping) in the commit message; the gate goes red
  whenever `watch` files move past the stamp.
- Stamp rule: sha = `HEAD` on the default branch, else `git merge-base origin/main HEAD`. Note the
  consequence on a long-lived branch: that merge-base does NOT advance, so a re-stamp legitimately
  changes only the datetime. That still counts — the check compares the block's value against its
  parent, and any change satisfies it. A re-stamp that changes nothing is silently not a re-stamp.
- Dated entries (corrections, traps) carry a prune-when condition and are DELETED once it holds.
- A claim whose truth lives in another repo is tagged `(cross-repo — verify at use)` and sits
  outside the `last-audit` assertion — watch pathspecs are single-repo.

## §A — Task (the agent DERIVES this per kickoff — the user does NOT fill it)

The agent fills §A from the `/session-kickoff` message plus the adjacent memory (the decision logs,
backlog, ledger) and the code — to the fullest extent possible. It uses **`AskUserQuestion`** ONLY
for a field it genuinely cannot derive to any extent (a real fork between approaches, or a non-code
prereq only the user knows). The template below is the *shape the agent fills*, not a form the user
completes.

> - **Title:** …
> - **Goal (1–2 sentences):** …
> - **IN scope:** …
> - **OUT / non-goals** (explicit cut-line): …
> - **Acceptance check** (the observation that proves THIS change — a test it adds, a gate it
>   moves, an observed behavior; *not* an unrelated green check): …
> - **Gates it must pass:** …
> - **Risk tier:** design-pass | direct

## §B — Orientation (derived at instantiation; re-audited every kickoff per the ratchet above; accretes)

- **Repo layout:** primary checkout at `C:/projects/swydee`, which stays on `main`. Feature work
  happens in linked worktrees under `.claude/worktrees/<slug>/` — that path is excluded from
  tracking, so a worktree never appears as untracked noise. One node, one machine (tag `a`).
- **Remote · default branch:** `origin` (github `d41ly/swydee`) · `main`
- **Branch conventions:** feature work on `feat/<slug>` or `branch/<slug>` off `main`, merged back
  with a merge commit (`Merge <branch>: <summary>`); docs/status-only commits may land directly on
  `main`. **Nothing mechanically enforces this** — the branch-guard hook was declined at adoption.
- **Governing docs:** `AGENTS.md` is the ruleset. The **units index** (inside
  `memory/trend/builds/2026-07-07-TREND-aCanonicalClient/spec/2026-07-07-spec-aCanonicalClient-1.md`)
  is authoritative for what is shipped/deferred. Inside each spec, the v2 AMENDMENTS/review-override
  block at the top OVERRIDES the unit bodies below it. `SKILL_BUILD_SPEC.md` §13 (hardened design)
  supersedes its §1–12 on any conflict. `data_gaps.md` = candidate analyzer rules, not ratified spec.
- **Governance playbook:** `AGENTS.md` (template v2.3), with its activity-scoped companion
  `parallel-coding-governance.domain-rules.md`. `CLAUDE.md` is a `@AGENTS.md` import.

### Pointer map (load the row(s) the task touches)

| Area / stream | Governing doc(s) | First code entrypoints |
|---|---|---|
| Swydo extraction (API/JWT/GraphQL/WS) | `SWYDO_REPORT_EXTRACTION_SPEC.md` · `memory/extraction/` | `skill/scripts/Get-SwydoReport.ps1` · `Test-Extractor.ps1` |
| Single-report analysis + facts | `SKILL_BUILD_SPEC.md` §13 · `memory/analysis/` (U6 canonical total, U7a/U7b reconciliation, U9 rank precedence, U10 data-gap rules) | `skill/scripts/Analyze-SwydoReport.ps1` · `Test-Analyze.ps1` |
| Trend / ledger pipeline | `memory/trend/` (U1–U5 master spec + units index) · `memory/analysis/` (U7b) | `skill/scripts/Sync-SwydoTrend.ps1`, `ConvertTo-SwydoTrendFacts.ps1`, `Update-SwydoLedger.ps1`, `Analyze-SwydoTrend.ps1` · `Test-Sync.ps1`, `Test-TrendFacts.ps1`, `Test-Ledger.ps1`, `Test-TrendAnalyze.ps1` |
| Closer (report number verification) | `SKILL_BUILD_SPEC.md` §13.1 | `skill/scripts/Test-ReportNumbers.ps1` · `Test-Closer.ps1` |
| Archive / client registry | `memory/trend/` (U1) | `skill/scripts/Manage-SwydoArchive.ps1` · `Test-Archive.ps1` |
| Skill orchestration + report voice | `skill/SKILL.md` · `skill/report-template.md` · `memory/orchestration/` | `skill/SKILL.md` |
| Governance chain itself | `AGENTS.md` · `memory/HYGIENE.md` | `tools/run-gates.sh` · `tools/gate-legs.json` |

### Gate commands (the merge bar)

```bash
bash tools/run-gates.sh                # every leg below, per-leg pass/fail; this IS the bar
bash scripts/manifest-check.sh         # manifest ratchet — standing line; path = check-script: above
```

Legs: the 8 PowerShell suites · ps source hygiene (+ its self-test) · memory hygiene, 12 checks
(+ self-test) · the manifest ratchet (+ self-test) · memory-recall kit selftest + skill-drift ·
agent-instructions wiring (+ self-test) · agent-cap self-test · check-wiring self-test · the
run-gates canary.

**From PowerShell, `bash` is WSL, not git-bash** — a different git against a `/mnt/c` mount. Always
spell it out: `& "C:/Program Files/Git/bin/bash.exe" tools/run-gates.sh`.

ALL suites re-run green on every unit, not just the touched one (green-count contract: a unit is
additive on its suite's count; other suites' counts stay unchanged). Baseline at adoption:
933 assertions across the 8 suites.

### Tier rule

Any change touching the extractor, a credential path, the closer contract, the facts schema, or
the default report surface is **design-pass**: a written spec (goal · scope · non-goals ·
acceptance) under `memory/<discipline>/builds/<YYYY-MM-DD>-<FAMILY>-<slug>/spec/`, adversarially
reviewed, with the review verdict folded in as an AMENDMENTS block BEFORE building — one
commit/review boundary per unit. Docs, additive tests, and template wording are **direct**.

Specs dated on/after **2026-08-04** must follow `memory/TEMPLATE-SPEC.md` (hygiene check 12); the
six migrated specs predate that and are grandfathered by filename date — never retrofit them.
Two gotchas the check will not explain: the status header wants an **8-char** base sha
(`git rev-parse --short=8 HEAD`, not the 7-char default), and a Tier-2 spec dated on/after
2026-08-04 needs a tenth `## 10. Reuse audit` section whose intended source is the codebase-map kit
— **not adopted here**, so write it by hand as `none — codebase-map not adopted; seam identified by
reading <file>:<line>`.

### ID + ledger protocol

**Two id eras, deliberately coexisting — they cannot collide, so both stay readable.**

- `U<seq>[a|b]` (U1..U10) is a **FROZEN legacy era**: cite verbatim, never renumber, never mint a
  new one. Its ledger is the **units index** table inside the U1–U5 master spec: every shipped unit
  has a row (Unit · Title · Spec link · Status), Status `SPEC` → `shipped` / `DEFERRED (<reason>)`.
  That table remains authoritative for *what shipped*.
- New records take `FAMILY-<slug>-<seq>` where FAMILY ∈ `EXTR` (extraction) · `ANLZ` (analysis) ·
  `TREND` (trend/ledger) · `ORCH` (orchestration), and slug = node tag + CamelCase adjective-noun,
  minted ONCE per session. Collision check: grep the whole `memory/` tree for
  `[A-Z]+-<slug>-[0-9]` and re-roll on any hit.
- **Session** ledger — who is touching what right now — is `memory/project/in-flight/<tag>.md`.
  Write only your own file; read all of them. Distinct from the units index, which answers a
  different question (what shipped, not who is working).
- `FAMILIES` in `.memory-tree.conf` and the id families in `AGENTS.md` §6 MUST stay byte-identical;
  memory-recall keys its index digest on them, and `adopt-memory-recall.sh --check` is the leg
  that catches a drift.

### Current posture — dated corrections

*A correction OVERRIDES a stale doc/memory claim until the underlying staleness is fixed. Entry
shape: `<date> · <what is stale where> · <the correction> · prune when <condition>`. This section
starts empty and is prunable per-ENTRY — never delete the section itself.*

- 2026-08-04 · `coding-governance` carries three fixes on branch
  `fix/gate-lint-scope-and-recall-crlf` that are NOT yet on its `main` (ps-hygiene function-scope
  model; the memory-recall CRLF protocol fix; the rendered-Skill LF pin). swydee's copied kits
  already include them, so re-copying a kit from gov `main` would REGRESS them ·
  prune when that branch is merged and pushed (cross-repo — verify at use).

### Environment traps worth front-loading

*This list ACCRETES — append the trap that cost this session time, prune the one that stopped being
true. Keep each to one line; link out for detail.*

- PowerShell **5.1** / .NET Framework only: no `&&`/`||`, no ternary, no `??` — parser errors.
- Source files are **pure ASCII**; non-ASCII glyphs are built via `[char]0x...` at runtime. Enforced
  by `tools/gate-lint/ps-hygiene.py`, which also catches case-only identifier collisions.
- PowerShell variable names are **case-insensitive**: `$Foo` and `$foo` are ONE variable. Function
  parameters are function-scoped and safe; two names at the SAME scope are not.
- Hardened scripts are reused via `-DefineOnly` dot-sourcing (functions-first pattern) and are
  **never behaviorally modified**; guard captured vars with the `$my*` prefix when dot-sourcing.
- `@($null).Count -eq 1`: always `@(...)`-wrap collections before `.Count`/indexing.
- The default single-report output path must stay **byte-for-byte unchanged** — every change is
  additive-in-facts (new `meta` fields / findings only). Sole exception: the reviewed, disclosed U9
  flip-set waiver (D1/D3) — a zero-dim KPI superseding a doc-earlier table total changes the flipped
  cells (always disclosed in-facts) and bumps `meta.canonicalVersion` 1->2.
- Every write path keeps its **fail-closed credential gate**; only `ConvertTo-SwydoTrendFacts`
  and `Analyze-SwydoReport` may open raw extractions.
- The model does no arithmetic: all numbers are computed in PS and must trace through the
  closer (`Test-ReportNumbers.ps1`); an untraceable number blocks publish.
- Suite output is **not uniform** — three suites print `Test-<Name>: N passed, M failed.` and five
  print `RESULT: N passed, M failed`. Assert the **exit code**, never parse the prose.
- In PowerShell, bare `bash` resolves to **WSL**, not git-bash. Every kit script here is git-bash;
  use `& "C:/Program Files/Git/bin/bash.exe" <script>` from a PS wrapper.
- `core.autocrlf=true` (system + global) with a deliberately **additive** `.gitattributes` that pins
  only the paths this chain introduced. Do not add `* text=auto` or a `*.ps1` rule — the 28
  pre-existing blobs are already LF in the index and a repo-wide rule risks renormalizing them.
- The gate runner's canary rejects any leg whose `argv[0]` is not `bash`/`python`/`python3`, so the
  PowerShell suites run through `tools/run-ps-suite.sh` rather than invoking `powershell.exe` direct.
- memory-recall indexes **tracked files only** — `git add` a new record before expecting a query to
  find it.
