# Session kickoff manifest — swydee

<!-- kickoff-manifest: v1.1 · instantiated from coding-governance skills/session-kickoff/MANIFEST-TEMPLATE.md -->
<!-- manifest-audit
last-audit: 2026-08-05T10:42:27+03:00 @ e4a95a999b993a556219d6f7d6cb09b5c5d89e44
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
  is authoritative for what is shipped/deferred. Inside a GRANDFATHERED 2026-07 spec, the v2
  AMENDMENTS/review-override block at the top OVERRIDES the unit bodies below it; a post-cutoff spec
  has no such block and its body is already the folded text. `SKILL_BUILD_SPEC.md` §13 (hardened design)
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
1276 assertions across the 8 suites after ANLZ-aUniformLattice-8 -- the total is the SUM of the
per-suite figures, so an arithmetic slip is self-evident: Extractor 288, Analyze 619, Closer 129,
TrendAnalyze 68, TrendFacts 24, Archive 94, Ledger 50, Sync 4. Was 1064 at adoption.

### Tier rule

Any change touching the extractor, a credential path, the closer contract, the facts schema, or
the default report surface is **design-pass**: a written spec (goal · scope · non-goals ·
acceptance) under `memory/<discipline>/builds/<YYYY-MM-DD>-<FAMILY>-<slug>/spec/`, adversarially
reviewed, with the review verdict folded in BEFORE building — into the BODY with a `rev-N` bump for a
post-cutoff spec, as a top AMENDMENTS block only for the grandfathered 2026-07 ones — one
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

- *(none yet)*

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
- Swydo orders the lists inside grouped cells **non-deterministically**: three QCU widgets differ
  between ANY two extractions of the same report, including two runs of identical code. A
  byte-comparison of two extractions is therefore only meaningful per-widget and after excluding
  `raw` (which carries per-query node ids). Verified 2026-08-04 by running the pre-change extractor
  twice. Prune when a run-to-run diff of unchanged code comes back empty.
- The default single-report output path must stay **byte-for-byte unchanged** — every change is
  additive-in-facts (new `meta` fields / findings only). TWO reviewed, disclosed waivers now exist, and
  `meta.canonicalVersion` names which algorithm produced an artifact. **1->2** is the U9 flip-set
  waiver (D1/D3), where a zero-dim KPI superseding a doc-earlier table total changes the flipped cells.
  **2->3** is ANLZ-aUniformLattice-6, whose entire flip set is the `GAP_NO_ACCOUNT_TOTAL` statement
  wording plus its new `evidence.byReason`, with membership provably unchanged. Both disclose in-facts.
  A THIRD disclosed change is ANLZ-aUniformLattice-8, marked by **`meta.factsVersion` 1->2** rather
  than by `canonicalVersion` (the headline algorithm is untouched): it is the first SUBTRACTIVE change
  to the facts shape, making `breakdowns[].rows[].valuesById` collisions-only and reclaiming 37% of the
  document. Its flip set is exactly those rows, the new `valuesByIdScope`, and the version marker.
  A fourth disclosed change needs its own MEASURED flip set before it lands.
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
- PowerShell collapses a **returned empty array to `$null`** and a **returned one-element array to a
  scalar**. `ConvertTo-Json` then renders that `$null` as `{}` rather than `[]`, and a truthiness test
  counts the deserialized empty object as one real entry. Return `,@(...)` from any function whose
  result is a collection, and do NOT re-wrap such a result in `@()` at the call site - that nests it.
  This shipped as a false PROVIDER_FILTERED major (ANLZ-aUniformLattice-7).
- The facts document IS the report model's context budget. `platforms[].metrics` and the breakdown
  addressing keys are machine fields with no narrative content, and `skill/SKILL.md` carries an
  explicit read/skip list so the model does not spend attention on them. Before adding a per-row key,
  measure: `valuesById` reached 41% of the document (129,815 of 318,082 bytes) before being cut back.
- memory-recall indexes **tracked files only** — `git add` a new record before expecting a query to
  find it.
- Filing a new record costs three hygiene legs beyond writing it: a `DECISIONS.md` index line has a
  **300-char cap** (check 7), any new `builds/` folder makes `TREE.md` stale (check 9), and inside a
  build folder only `README.md STATUS.md prompts/ spec/ build/ reviews/` are allowed - `reviews/` is
  PLURAL and its files must be `<date>-review-<slug>-<seq>.md` (checks 4 and 5). Regenerate the tree
  with `memory-tree/gen-memory-tree.sh --write` before re-running the gate.
- A spec dated on/after the `SPEC_FORMAT_CUTOFF` may NOT carry a top-level `## AMENDMENTS` block:
  check 12 demands exactly the ten canonical `##` sections, so a review folds into the body with a
  `rev-N` bump logged in §9. The grandfathered 2026-07 specs use the older top-block convention.
- A fresh worktree can check out `.claude/skills/memory-recall/SKILL.md` with **CRLF despite the
  `eol=lf` pin**, which reds the recall skill-drift leg on an otherwise-clean tree. The committed
  blob is LF and `git check-attr` is correct, so this is a checkout artifact, not drift: fix with
  `git checkout -- .claude/skills/memory-recall/SKILL.md`. Do not "fix" it by re-scaffolding.
  Prune when a new worktree is observed to produce LF unaided.
- The agent harness's PowerShell tool is **PowerShell 7.x**, not the 5.1 this project targets. Ad-hoc
  checks run through it will silently accept `&&`, ternaries and `??` that the real runtime rejects.
  Always spell out `powershell.exe -NoProfile -File <script>` for anything whose 5.1 behaviour
  matters; the gate legs already do this via `tools/run-ps-suite.sh`.
