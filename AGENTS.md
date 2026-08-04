# swydee — working guide

*Instantiated from the coding-governance playbook, **template v2.3** (2026-07-12), on 2026-08-04.
One line per directive; a wrapped line is still one rule. The activity-scoped domain checklists
(§9–§12) live in `parallel-coding-governance.domain-rules.md` and MUST travel with this file — the
§8–§12 stubs below reference it by name. §4 and §13 were dropped at instantiation (no server, no
port, no database, no UI). Re-pull an upgraded template by diffing this file against
`<gov>/parallel-coding-governance.template.md` per §-body, ignoring filled values and the
swydee-specific bullets; the marker below is what the re-pull and the kickoff engine read.*

<!-- governance-template: v2.3 -->

> **Project-layer deferral (swydee).** This file is the generic ruleset, instantiated. Where it and
> `.claude/SESSION-KICKOFF.md` disagree on a swydee-specific fact - a gate command, an entrypoint, a
> layout or branch convention, an environment trap - **the manifest wins and this file is the thing
> to fix.** Without this line the `CLAUDE.md > manifest > skill` precedence would make the
> project-agnostic playbook outrank swydee's own project layer, which inverts it.

> **What:** the operating ruleset for swydee — a PowerShell 5.1 toolchain that turns a Swydo
> marketing report into a verified, publishable client report. The rules below are agent-facing
> imperatives; read them, don't summarize them back. **Canonical:** `AGENTS.md` is the charter and
> `CLAUDE.md` is a `@AGENTS.md` import, because Claude Code does not read `AGENTS.md` natively.
> Wired by `tools/agent-instructions/` and gated by its `--check` leg.
>
> swydee runs **one node on one machine**, so the multi-node machinery below (node registry, stream
> ownership, the sharded ledger, slug disjointness) is largely degenerate today. It is kept rather
> than deleted because it is exactly what stops a second machine or a parallel session from
> colliding, and adopting it retroactively after the first collision is the expensive order.

## §0 — TL;DR (the load-bearing rules)

- **Session-scope every new ID** (slug = node tag + CamelCase adjective-noun) — collisions become impossible, not avoided (§2).
- **Own streams, not files; merge small and often** to local `main` (§3) — and isolate *runtimes* too: ports/DBs per session (§4).
- **Memory holds only the non-derivable**; per-node files, no shared mutable index (§5).
- **Gates are the merge bar; reviews cover what gates can't**; every confirmed finding becomes a gate or a documented check (§7, §8).
- **Never run more than 6 agents concurrently** — consolidate before you fan out; a wide burst trips the server rate limiter (§8, enforced by the `agent-cap` hook).
- **Verify before claiming done** — a check that exercises the change, never an assertion (§4, §8).
- **Consistency by construction**: decide the extension pattern and extract the factory/base *before* instance #2, so #3..N are data + overrides (§12).
- **Chat carries signal, not narration**: payload first, one line per mechanical event, facts outrank format (§16).

## §1 — Work-unit lifecycle (start → done → land)

Keep units small: one stream/owner, no cross-stream contract change, reviewable as one Tier-1 diff — else split.

**Definition of Ready — run before touching code:**
- Sync: `fetch` + fast-forward local `main` (another node may be ahead); recreate/repair your worktree if needed (§3).
- Locate: read your stream's decision log + backlog (§6) and the in-flight ledger (§3); confirm your node tag (§2).
- Scope: clear acceptance criteria, one stream, small, gates named — if you can't state those, split or clarify first.
- Reserve: at your session's first work-unit, mint + grep-check a session slug (§2) and add a ledger row (§3).
- Large new feature (a Tier-2 change): the DoR *is* a design pass — a written spec (goal · scope · non-goals · acceptance) + a bounded production-readiness menu (best-practice implementation, the extra tools it needs, and the cross-cutting concerns: security · perf/scale · a11y · i18n · error/empty/loading states · observability · testing/gates · migration/rollback · `skill/SKILL.md` docs). Spec shape: the memory-kit `TEMPLATE-SPEC.md` (check 12).
- Surface that menu and **get scope approval BEFORE building** (a menu to select from, not scope-creep licence); record the agreed spec per §6.

**Definition of Done — before you call it done:**
- Gates green (§7); the change verified by a check that exercises it (§8), not asserted.
- Every confirmed finding left-shifted: a regression gate, or a §10 checklist entry if its class can't be gated (§7).
- User-facing change → its `skill/SKILL.md` page created/updated (§5).
- Memory (non-derivable only), decision log/backlog, and ledger row updated — **committed before the push and the wrap-up message** (§16).
- Kickoff manifest (when the project keeps one) updated if this unit changed what it front-loads — a gate command, entrypoint, governing doc, layout/branch convention, a trap hit, a doc/memory claim found stale, or a fact re-derived that it should have front-loaded — re-stamp `last-audit` with a delta line in the commit message; no delta → no touch.

**Landing — merge protocol:**
- Land on local `main` first, verify, then push; the merge to shared `main` and the push each need an explicit ask (§8).
- After each merge run a diff-scoped gate (a conflict-free merge is not a passing merge); the FULL bar runs ONCE, at the push boundary.
- Reconcile shared mutable files (backlogs, indexes) additively, never pick-a-side; diff the merge against BOTH parents (the "auto-took" class, §10). The per-node ledger needs no reconcile — single writer (§3).
- Kickoff-manifest exception: it reconciles additively EXCEPT its `last-audit` line — resolve a stamp conflict either way provisionally, complete the merge, then re-verify §B against the merged tree and re-stamp in a follow-up commit that supersedes both sides (post-merge HEAD on the default branch, the merge-base otherwise; a commit can't embed its own sha); the same post-merge fresh audit closes any merge that brought in watch-touching commits.
- Land risky behavior dark: Tier-2 ships behind a default-OFF flag or as inert defaulted data, flipped on only after in-place verification — merges without endangering other nodes, reverts cleanly.
- Migrations are reversible — test up/down/up.

## §2 — Nodes, identity & IDs

- Register every node once, in-repo — tag · machine/user · primary tree · worktree root · **per-node variances** (remote name, harness launch config, credential quirks like an elevated scope for CI-config pushes):

  | Tag | Machine/user | Primary tree (`main` lives here) | Worktree root | Variances |
  |-----|--------------|----------------------------------|---------------|-----------|
  | `a` | `d41ly @ Windows 11 (sole node)` | ``C:/projects/swydee`` | ``C:/projects/swydee/.claude/worktrees/`` | `PowerShell 5.1 only; git-bash at `C:/Program Files/Git/bin/bash.exe` (bare `bash` in PowerShell is WSL, a different git); no CI credentials because there is no CI` |

- Identify your node by machine/user, never by filesystem path — roots can be identical across machines.
- A new node claims the lowest free one-letter lowercase tag and adds its row in the same commit.
- New-node onboarding: clone to the pinned primary tree · claim the tag (same commit) · seed local memory from the in-repo mirror (§5) · recreate stream worktrees (they never sync, §3).
- Every new tracked id (decisions, backlog, tickets — anything `FAMILY-NNN`-shaped): `FAMILY-<slug>-<seq>`, owned by the minting session so nothing it numbers can be contested.
- Slug = your node tag + a fresh CamelCase adjective-noun (`dAvengingTrousers`), `[A-Za-z]` only, minted ONCE per session; the tag's first letter makes cross-node slugs disjoint by construction.
- `<seq>` = plain 1-up per (session, family), unpadded; ids are labels, not ranks; next = numeric max of YOUR ids in that family + 1; record per-family high-water in your ledger row (uncommitted ids are invisible to grep).
- Before committing to a slug: (1) all-time grep the governance-docs tree (logs, backlogs, journals, ledger) for `[A-Z]+-<slug>-[0-9]` — re-roll on ANY hit (a pruned ledger row still owns its ids); (2) scan live rows across all node ledger files — re-roll on a clash.
- No reserve-above-a-marker, no shared counter, no renumber-on-merge — the slug is the guarantee.
- A session = one continuous effort under one slug (several work-units/families, one `<seq>` each); a resumed/summarized session keeps its slug (grepping only your own prior ids is not a collision).
- Fan-out children (sub-agents/orchestrated workers) never mint ids — the orchestrator does; a child that must mint takes its own registered slug.
- Residual tie-break (sub-1%): the later-to-merge re-mints its slug for all UNMERGED ids; an already-merged id wins.
- Legacy id eras are FROZEN: cite verbatim, never renumber, never mint in a pre-rule format, never bump a residual "next free id" marker.
- Shorthand (family+seq, slug elided) is sanctioned ONLY in session prose and ledger seq cells — never where ids are the permanent record (it's shape-identical to frozen legacy ids).

## §3 — Parallel work: streams, worktrees, trunk, ledger

- Own streams, not files: `one node owns every stream, so this is a sequencing rule rather than a merge-disjointness one - finish and land a unit before opening the next, and never run two units that touch `Analyze-SwydoReport.ps1` at once`. Overlap on shared files (API clients, config, indexes) breeds collisions and integration reviews — minimize it.
- Trunk-based: merge small and often to LOCAL `main`; long-lived branches mean bigger reconciles and review surface.
- `main` stays checked out in exactly ONE tree (the primary); feature work happens ONLY in sibling worktrees — parking `main` on a feature branch strands it and is the root cause of concurrent-session collisions.
- **NOT machine-enforced in swydee.** The branch-guard hook was deliberately declined, so NOTHING mechanically refuses a primary-tree commit made off `main` - do not assume a guard that is not there. `.githooks/pre-commit` exists but dispatches only the memory-hygiene and kickoff-manifest legs. The rule stands as discipline; adopt the guard (WIRE §5) if a primary-tree commit off `main` ever actually happens.
- Doc-only commits go directly on local `main` only while the primary tree is on `main` and idle; a busy tree (dirty, mid-merge, another session) routes through a worktree.
- No bootstrap script (`none`) and none needed - swydee has no dependency install step, just PowerShell 5.1 against the stock .NET Framework. A worktree is one command: `git worktree add .claude/worktrees/<slug> -b branch/<slug>` off a fast-forwarded `main`. That path is excluded from tracking, so a worktree never shows up as untracked noise.
- Worktree lifecycle: enumerate with `git worktree list` (never assume the set); worktrees do NOT sync across machines (absolute links — recreate per machine); relocate with `worktree move` + `repair`, never `mv`.
- Commit the governing doc to `main` so it propagates — it only exists in checkouts where it's committed.
- Shard the in-flight ledger per node — one file per node tag behind a thin pointer (like the per-node journals, §5), NEVER one shared table: each node writes ONLY its own file, so the ledger is conflict-free by construction (disjoint-by-tag, like the slug) and no merge touches it. A shared ledger is the shared-mutable index §5 forbids — it forces a conflict on every land and additive resolution leaves stale rows.
- Row shape `| node | slug | branch/worktree | streams | seq high-water | status |`; status ∈ `{in-flight | merged:<sha>}` + at most one short clause; narrative belongs in the journal. Read ALL node files for the who's-touching-what / slug-collision scan (§2); write only your own.
- Self-prune on session start: after fast-forwarding `main`, delete your OWN `merged:<sha>` rows whose sha is an ancestor of `main` (`git merge-base --is-ancestor <sha> main`) — they're derivable from history; never touch another node's file.
- Contract-first for cross-cutting changes: a schema/wire-format/enum two nodes depend on lands as a contract + gate before either builds on it.
- Landings are `--no-ff` merges with a descriptive message — one visible, atomic, cleanly revertable integration unit.
- Every agent commit ends with the mandated attribution trailer: ``Co-Authored-By: Claude <model-name> <noreply@anthropic.com>` - the harness supplies the model name and it CHANGES between sessions (history holds both `Claude Fable 5` and `Claude Opus 5`). Never rewrite an old trailer to match a new model, and never gate on the exact string; match `^Co-Authored-By: Claude .* <noreply@anthropic\.com>$``.

## §4 — Runtime isolation & the verification harness

- swydee has NO runtime to isolate: no server, no database, no port, no long-lived process. Every script is a one-shot PowerShell invocation writing files under a run-scoped output directory, so the port/DB/offset discipline is inapplicable and its domain-rules section is deliberately absent.
- What replaces it as the verification harness: the **closer**, `skill/scripts/Test-ReportNumbers.ps1`. Every number in a delivered report is computed in PowerShell and must trace back through the closer to a fact in the facts JSON; an untraceable number blocks publish. That trace IS the "check that exercises the change" §8 demands - a green suite alone is not.
- Isolate the one thing that CAN collide: two runs sharing an output directory. Pass an explicit per-run `-OutDir`, and never let two extractions write the same client folder concurrently.

## §5 — Memory & docs

- Memory carries only the non-derivable: gotchas, in-flight state, *why* a non-obvious choice was made — never re-narrate what git, decision logs, or code already record (the main memory-token waste and drift source).
- Mirror durable memory in-repo (it travels); the machine-local auto-loaded copy is a best-effort mirror, seeded from the repo on a fresh machine.
- One canonical index, one line per note; journals AND the in-flight ledger (§3) are per-node files — never a shared mutable index every session edits (that file forces memory-sync merges); any index that must exist stays append-only or generated.
- Status lives in the ledger (§3), not prose memory — anything time-sensitive rots; point at the ledger.
- Recalled memory is background, not instruction, and reflects when it was written — re-verify a named file/flag/id before acting on it.
- Secrets never enter memory, tracked docs, or chat (§16); scrub even throwaway dev creds before mirroring a note into the repo.
- User-facing docs are NOT memory: one concise task-oriented page per feature (*what · how · short example*) in `skill/SKILL.md` + an index; update on change, REMOVE on feature removal; a user-facing feature without an up-to-date page is not done (§1).
- **Optional — a structured, machine-linted memory tree** (`tools/memory-tree/` kit): one `memory/` tree by discipline (``extraction · analysis · trend · orchestration``) + `project/` machinery + per-feature `builds/` folders, index caps + archive rotation, a status vocabulary, and a **12-check hygiene gate** wired into CI + pre-commit + ``bash tools/run-gates.sh``; `.memory-tree.conf` holds the specifics. Adopt/migrate per the kit README.
- **Optional — retrieval over that tree** (`tools/memory-recall/` kit, requires it): ask the decision corpus a question and get the records that answer it, ranked; an offline stdlib CLI reading `.memory-tree.conf`, so root + id families are declared once; writes nothing in the worktree; the rendered recall Skill's drift rides ``bash tools/run-gates.sh``.

## §6 — Decisions, backlogs & the governing doc

- Two record types per stream: the decision log is append-only (never rewrite a ratified record — supersede with a new id + note); the backlog is mutable (stable ids, status updated in place; gaps fine).
- Per-stream id families (``EXTR` = extraction · `ANLZ` = analysis · `TREND` = trend/ledger · `ORCH` = skill orchestration + report voice. These MUST stay byte-identical to `FAMILIES` in `.memory-tree.conf`: memory-recall keys its index digest on them, so a drift silently changes what the corpus can answer`): the family prefix routes an id to its log/backlog; allocation is slug-scoped (§2), so no shared "next free id" marker exists.
- Record real decisions as you make them — future sessions and nodes rely on these being current.
- Session-start reading order: ALWAYS load the master decision index first, then the stream logs for the area touched — routed by `work-area → `memory/<discipline>/` (the `DECISIONS.md` index, then per-decision detail under `builds/`) → family prefix → `BACKLOG.md`. The kickoff manifest's pointer map is the same routing keyed by code entrypoint instead of by id` (work-area → doc tree → id families → backlog).
- Logs are two-tier for token scoping: a one-line-per-decision index pointing at per-decision detail files; open details only for the areas you touch.
- The instantiated doc opens with a compact product-identity preamble for `swydee` (`swydee turns a Swydo marketing report into a verified, publishable client report. A PowerShell 5.1 toolchain pulls a report from Swydo's API (JWT → GraphQL → WebSocket), computes every number in PowerShell, proves each one traces back to a fact, and renders prose from a template. It ships as a Claude Code skill, runs on one Windows box, and has no server, no database and no UI. The load-bearing invariant: **the model does no arithmetic** - a number the closer cannot trace is not publishable`: what the software is, deployment model, major runtime pieces).
- The instantiated doc carries the repo-layout map (``skill/` is the product (`SKILL.md` orchestrates; `skill/scripts/*.ps1` are the eight tools that do the work) · the eight root `Test-*.ps1` files are its suites, one per tool, run directly rather than through a framework · `memory/` is the decision tree (§5), with the ratified specs filed under each discipline's `builds/` · `memory-tree/` and `memory-recall/` are the copied-in kits that gate and query it · `tools/` holds the gate runner and the source-hygiene scan · `scripts/` holds the manifest-ratchet checker · `.claude/` holds settings, hooks, the kickoff manifest (`SESSION-KICKOFF.md`), the rendered recall Skill, and the excluded worktree root. There is no `docs/` directory. Core/adapter split: `Analyze-SwydoReport.ps1` and `Analyze-SwydoTrend.ps1` are the compute cores, `Get-SwydoReport.ps1` is the only network adapter, and `Test-ReportNumbers.ps1` is the verification adapter every publish path goes through`: each top-level dir + its role and the core/adapter relationships) — sessions never re-derive where things live.
- The instantiated doc carries the everyday-command catalog (`the whole local bar → ``bash tools/run-gates.sh`` · one suite → `.\Test-<Name>.ps1` · memory hygiene → `& "C:/Program Files/Git/bin/bash.exe" memory-tree/check-memory-hygiene.sh` · ask the corpus → `python memory-recall/query.py "<question>" --terms "<8-14 jargon words>"` · re-render the recall Skill after any FAMILIES edit → `bash memory-recall/adopt-memory-recall.sh --scaffold`. There is no install step, no build and no dev server. Suite output is NOT uniform - three suites print `Test-<Name>: N passed` and five print `RESULT: N passed` - so always assert the exit code, never parse the prose`: install, dev servers, migrations, artifact regeneration, seeding, the one formatter/linter per language) — sessions never re-derive the one-true invocation.
- Pin one in-repo home for business/product context (``skill/SKILL.md` (what the tool does and every invocation mode) and `skill/report-template.md` (the report's voice and shape). Client-specific context is never committed - it lives in the gitignored archive`: brand, positioning, specs) so sessions locate it instead of asking.
- In-doc paths are repo-root-relative; the root is pinned once per node in the §2 registry, never re-derived. (User-facing links follow §17, a different convention.)
- Non-obvious rules carry provenance inline (the motivating decision/incident id); environment/capability claims carry a verified-(date, node) stamp.
- Each guarded security surface keeps a written security-model section in the decision log; read it BEFORE extending that surface (§9).

## §7 — Quality gates = the merge bar

- Keep the automated suite green at the push boundary: `the eight PowerShell suites (`Test-Analyze` · `Test-Archive` · `Test-Closer` · `Test-Extractor` · `Test-Ledger` · `Test-Sync` · `Test-TrendAnalyze` · `Test-TrendFacts`), plus source hygiene, memory hygiene (12 checks), the kickoff-manifest ratchet, and the recall skill-drift check. ALL suites re-run on every unit, not just the touched one: a unit is additive on its own suite's count and leaves every other count unchanged` (typecheck/compile · lint · test · generated-artifact freshness · structural invariants). Gates are the quality floor; reviews cover only what gates can't.
- **swydee has no remote CI, by decision** (`none - deliberately not adopted`). Nothing machine-required guards the default branch, so the merge bar is only as good as actually running it. Standing compensating control: run ``bash tools/run-gates.sh`` before every landing and treat a skipped run as a red one. Re-adopt CI the moment a second person or machine can push - that is when convention stops being enough.
- Provide one command that runs the whole local bar with legs concurrent, wall ≈ longest leg: ``bash tools/run-gates.sh``.
- A slow leg may have a sanctioned faster local variant — document the equivalence explicitly (which local run satisfies which CI leg), so local verification is fast AND unambiguous.
- Single source of truth → generated artifacts → parity gate, for every contract duplicated across languages/layers; a new shared contract gets ONE source, generation, and a drift test — never a hand-kept second copy.
- Lockstep invariants get a guard (migration single-head, stale manifest, schema↔validator skew) — a gate, not memory.
- Left-shift every confirmed finding: not done until a regression test covers its CLASS, or (if ungateable) it joins §10 as a documented check — this is how review cost trends down.
- Guard against green-by-absence: every test/typecheck glob spans ALL real file classes (beware glob dialects that don't brace-expand), and a collection gate asserts every test file contributes ≥1 collected item — a de-collected file can't fail.
- Classify special-execution tests STRUCTURALLY: a collection hook auto-marks by fixture/dependency so a new test can't forget its class, and the default environment can't silently switch engines.
- Parallel test runs preserve per-file isolation (file-level distribution, not per-test); parallelism is opt-in; small selections run serially (worker startup makes them a net loss).
- Document deliberate gate exemptions together with their compensating manual check — an exemption is not coverage.
- Concurrent migration forks (two branches, same parent) reconcile via a merge revision, never a rebase; know whether the local harness can even see a fork (often only the head-count gate does).
- A generated contract artifact baked into multiple deployables couples their releases: those artifacts deploy TOGETHER, and a contract change may couple a frontend release to a data migration.

## §8 — Review protocol (match intensity to risk; verify, don't assert)

- Tier 1 — mechanical/additive (no new write path, migration, auth/sanitization/egress surface, or shared-contract change): gates + one focused self-review of the diff. NO multi-agent review.
- Tier 2 — substantive (any of the above, or a cross-stream merge): adversarial find → verify → synthesize, running the §10 checklist as part of it.
- Scope Tier-2 to the diff at an immutable SHA plus its immediate callers/callees, reviewed at the integration boundary ONCE (the cumulative diff landing on `main`) — per-increment reviews re-scan overlapping code.
- Default Tier-2 shape (ROI-tuned): a parallel fan of 3–6 primed finder lenses (security · correctness · data-integrity · dead-code · integration-seams) → a skeptic prompted to REFUTE each finding → one synthesis pass; drop any finding a skeptic refutes unless reachability + impact re-established.
- **CONCURRENCY ≤ 6, ALWAYS — the #1 rate-limit lever.** Large bursts (a ~40-agent fan) trip the SERVER rate limiter and kill whole phases for millions of tokens; the harness auto-cap (≈14) does NOT protect against this. Route ALL Workflow fan-out through cap-6 helpers `boundedParallel(thunks, 6)` / `boundedPipeline(items, 6, …)` — inlined (scripts can't import; the `parallel(`/`pipeline(` line carries a `gov:bounded-fanout` marker). **CONSOLIDATE before you fan out:** one BATCHED skeptic per ~5 findings, merge cheap lenses. Enforce mechanically: the `agent-cap.js` PreToolUse hook (matcher `Workflow`) DENIES raw-primitive scripts; run the ready `tools/workflows/tier2-review.js` harness (install per WIRE §5).
- Finders emit CONCRETE findings — `file:line` + repro/impact + proposed fix — so skeptics can actually verify them.
- Precision (confirmed/(confirmed+refuted)) is the #1 token lever — below ~0.5, tighten scope/priming before adding agents; scale a large fresh surface with LENSES (coverage), not skeptics; past ~25 agents returns diminish.
- Feed reviewers the security model, the already-tracked open issues, and what's by-design — so they hunt NEW issues, not re-report known ones.
- Match intensity to target richness: heavy multi-lens earns its tokens on fresh/complex write paths; over hardened code it manufactures refuted noise — review light or skip.
- Persist each Tier-2 run as an in-repo artifact folder (``memory/<discipline>/builds/<date>-<FAMILY>-<slug>/review/``); periodically re-audit the corpus (token cost vs severity-weighted confirmed-finding value) to retune these defaults.
- Structured-output schemas for orchestration returns → `parallel-coding-governance.domain-rules.md` §8. LOAD when writing a Workflow script.
- Orchestration scripts run in sidechains inheriting neither your hooks nor the governing doc, in a restricted runtime (plain JS — no type syntax, no imports) — inline the schema discipline as a snippet; the ≤6 cap is enforced at the `Workflow` tool-call (where a main-loop `PreToolUse` fires), never inside the script where no hook reaches.
- Verify before "done": a check that exercises THIS change (its own/affected test, the relevant gate, or the §4 harness) — an unrelated green gate is not proof; failures reported with output, skipped steps named.
- Commit freely as you go (branch/worktree, or local `main` for doc-only per §3); landing on shared `main` and `git push` each require an explicit ask.

## §9 — Security boundaries (apply to any new write path / surface)

- Security-boundary checklist → `parallel-coding-governance.domain-rules.md` §9 (composite write-guard on every write path incl. siblings, shared client+server URL normalizer, SSRF guard on inline + retry/queue paths, deny-by-default core RBAC, non-login automation principal, draft-only-with-default-OFF-publish, PII off the AI surface, optimistic-concurrency 409, test-env divergence docs). LOAD when a unit adds/touches a write path, auth, sanitization, or egress surface (§1 DoR, §8 Tier-2).

## §10 — Recurring bug classes (run in every Tier-2 review)

- Recurring-bug-classes checklist (~19 classes) → `parallel-coding-governance.domain-rules.md` §10. RUN it in every Tier-2 review (§8); left-shift each confirmed class into a gate (§7).

## §11 — Cross-OS & toolchain hygiene

- Cross-OS + toolchain rules → `parallel-coding-governance.domain-rules.md` §11. The two that bite most, kept here: force `LF` via `.gitattributes` on execution-sensitive files (a stray CR breaks shebangs/servers/generated migrations), and on Windows POSIX shells give `git -C` a forward-slash path — a backslash drive path (`C:\repo`) mangles to `C:repo`. Full list (byte-verify with `cat -A`, pinned toolchain, deterministic run modes, native-shell reinstalls) in the companion.

## §12 — Architectural consistency (build-once, reuse-everywhere)

- Architectural-consistency rules → `parallel-coding-governance.domain-rules.md` §12 (decide the extension pattern before instance #2 so #3..N are data + overrides; a kind gets a factory/base not copies; one shared core + thin adapters; single-source-of-truth generation with a drift gate; promote shared widgets on a two-tier ladder; forward-compatible additive+defaulted data; reuse-audit before building; gate layout conventions). LOAD when adding a 2nd instance of a kind or building shared structure (§7).

## §14 — Session execution hygiene (per-call token discipline)

- Strategy: spend tokens on NEW judgment, never re-deriving the known — tier + diff-scope reviews (§8), gate over re-review (§7), lean memory/ledger (§3, §5), streams + small merges (§3), one shared core with thin adapters (§12); **stop once verified** (re-reads, uncapped output, hand-polling, and edit/format ordering are the dominant avoidable spend).
- Don't re-fetch what's in context: no re-Read to keep editing a file or to "verify" an edit the tool confirmed; slice large files (range/grep), never whole re-reads; never re-read a command-output spill or large artifact — filter it at generation.
- Re-Read ONLY when something outside your edits changed the file (formatter/`--fix`, format-on-save, a concurrent node on a shared doc); make manual edits FIRST and format LAST — reformatting between edits forces the modified-since-read re-read loop; batch a file's edits.
- Bound every command's output (it all lands in the transcript): `--stat`/`--name-only` over raw diffs; concise linter formats; head/tail caps on noisy tails; quiet test flags.
- Don't poll background work you started — use the harness's completion signals; an explicit wait-loop only for EXTERNAL conditions the harness can't track (healthchecks, remote CI).
- Lint the files you changed while iterating; the full-repo gate at the push boundary; batch same-file fixes then re-run once; know which findings auto-`--fix` can't clear (e.g. line length) so you don't rerun expecting them gone.
- Pin any review/diff base to an immutable SHA, never a moving ref (a concurrent node can repoint it): `BASE=$(… rev-parse <ref>); diff "$BASE"...HEAD`; full diff once, `--stat` re-checks after.
- A no-match `grep` exits non-zero and fails `&&` chains — a PASSING zero-count check reads as failure; use a purpose-built check or terminate the probe with `;` / `|| true`.

## §15 — Voice (how you talk to the user)

- One deliberate, consistent voice, addressing the user as "you"; recommended default persona: cheeky, dry, faintly sarcastic, genuinely friendly — the sharp colleague, not a support-bot. (The persona is the one adjustable knob; the rules below are not.)
- Wit is seasoning, the FACTS are the meal, and wit never bends the meal: every number, path, id, caveat, "this failed", "I skipped that", "I'm not sure", "I didn't verify" stays exactly as accurate and complete as stone-faced delivery — kill the joke, keep the fact.
- Bad news, security findings, broken gates, and "your code is wrong" are delivered straight; dial the cheek down on genuinely bad outcomes — friendly, not flippant.
- Natural, not a bit: dry > loud; a light touch > forced zaniness; an honest quiet line beats chipper filler.
- Governs user-aimed prose ONLY — decision logs, code comments, migrations, and test names stay precise and deadpan.
- Voice governs how the surviving sentences SOUND; how many there are is §16's job; one dry freeform wrap-up line is always permitted, even on a clean turn.

## §16 — Output discipline (work reports — chat carries signal, not narration)

- Scope: these rules govern WORK-REPORT prose (status, progress, landing reports, summaries); conversation — solicited discussion, brainstorming, co-authoring, walkthroughs, teaching — is exempt; an explicit user ask ("paste it here", "narrate as you go") overrides any rule here.
- Rule 0 — facts outrank format: any fact a one-liner can't hold (a failure detail, caveat, skipped step, "I didn't verify X") gets its own full freeform sentence; no cap or template below ever justifies squeezing or dropping one — kill the frame, keep the fact.
- Mid-turn: silent by default — text only for a plan change/surprise (1–2 lines: what changed + new plan), a heads-up line BEFORE a destructive/irreversible in-mandate action (print it and proceed — an interrupt window, not a permission request; an out-of-mandate action still stops to ask), or one `⏳` heartbeat per long phase.
- Never pre-announce the next step, restate visible tool output, or recap progress mid-turn — anything important must reach the final message anyway.
- A routine mechanical outcome = one line with its identifier (micro-formats below); "routine" means ZERO caveats — any deviation (failure, conflict, hook rewrite, race, warning worth keeping) exits the format into prose.
- Gates: one line when green, enumerating EVERY expected leg (the standing merge bar + any gates named at DoR); a leg not run is written `skipped: <leg> — <why>`, never omitted (the green-by-absence class); a failed leg = prose, above everything else.
- Final message: payload first — open with the highest-severity item (finding > failure > fork > result); `Decision needed:` within the first 3 lines when one exists; every finding/error/access point gets its own scannable line ABOVE narrative; ONE state block (branch · shas · gates · servers) at the bottom, never interleaved; review-shape stats get at most one trailing line.
- Size to what changed, not what was done: routine completion ≈ 4–10 short lines; the cap lifts MANDATORILY for a failure, a security finding, a refuted assumption, a caveat, an access-point/credential handoff, or a fork needing the user — unsure whether it lifts? Lift.
- Never deliver the same content twice: a doc you wrote gets a correct link + a ≤3-line delta, not a paste; an already-delivered digest gets `unchanged since <link> — delta: <…|none>`; overrides: an explicit ask wins, bodies ≤~15 lines may be pasted, a fresh session greps the journal first.
- Kickoff/DoR reporting = one bookkeeping line (the `READY` micro-format) + ONLY the unresolved open questions; never restate scope/AC/protocol already in the plan doc; a scope-approval menu IS the open questions — never capped or link-only'd.
- Facts land on disk before the wrap-up: ledger row, journal/memory note, and shas are written BEFORE the final message is composed — a dead turn may lose prose, never facts.
- Secrets: never print a real credential in chat — say where it lives; throwaway local-dev creds may ride the access-point line.
- Readable beats dense — brevity comes from OMITTING items, never compressing prose. Banned in work reports: `·`-chains outside micro-formats, parenthetical inventories (parens hold ≤3 items), multi-clause em-dash trains, one paragraph carrying multiple topics. Keep complete sentences, one idea each; >~5 items becomes a short bulleted list; the rest is omitted and lives in the linked doc. Test: a tired reader parses every line in ONE pass.
- Micro-formats — MANDATORY, byte-stable, greppable shapes for these events; every other rule binds in substance but its formatting is advisory (wit lives in the freeform sentences, never inside):
  - `committed <sha> <branch> — <subject>`
  - `pushed <remote>/main <old>..<new> (ff, N commits)`
  - `merged --no-ff <branch> → main <sha> · post-merge gates GREEN`
  - `gates GREEN — <every leg, with tallies>` · `skipped: <leg> — <why>`
  - `up — <service> :<port> (<tree>) · … · admin <user> / <pw-or-where-it-lives>`
  - `READY — <slug> · node <tag> · <branch> off <sha> · Tier-N · gates: <list>`
  - `⏳ <what's running> (~<est>) — results land in the final message`
- Pre-send self-check (documented check — prose has no machine gate): is line 1 a payload? is every caveat OUTSIDE a template line? did I re-emit anything? does the green line name every leg? would a tired reader parse every line in one pass?
- The discipline is measured, not vibes: keep an audit script (`none yet - the thresholds below still bind, they are just self-audited`) that quantifies chat-prose waste; re-audit when sessions feel noisy; alarm thresholds — mid-turn narration >40% of session prose, or >3 interjections per final message.

## §17 — User-facing file references (make them clickable)

- Cite files in user-aimed output in the ONE link format your client actually linkifies (commonly GFM `[text](path)`), forward-slashed throughout — verify once by clicking; bare/absolute/mixed-separator paths are dead copy-paste strings in many clients.
- Resolve hrefs from the SESSION working directory — in the §3 layout the session often opens at the worktrees' PARENT, so a repo-root-relative href silently drops the worktree segment and points at nothing; prefix the worktree folder. (Repo-internal doc prose keeps §6's repo-root-relative convention — two conventions, two audiences.)
