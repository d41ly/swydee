# Governance domain rules — runtime, cross-OS, architecture, security, recurring bugs & design system

Companion to `parallel-coding-governance.template.md`, holding five activity-scoped domain sections the
template references by section number rather than inlining (they apply only when a unit touches a
risky surface or runs a Tier-2 review). Deploy this file alongside the playbook; the template's §8, §9, §10, §11 and §12 stubs point here. §4 (runtime isolation) and §13 (design system) were dropped at instantiation - swydee has no server, no port, no database and no UI.

## §8 — Structured returns from orchestration scripts

- Structured-output schemas so a malformed return can't force full regeneration (top output-token waste): write a large body to a file and return `{path, summary}`, forward-slash paths (never hand-serialize JSON — unescaped backslashes are the top breaker); restate the required keys in EVERY loop iteration; accept-and-ignore stray keys unless a stray key is actually harmful; on a validation failure feed back only the offending field, never "regenerate everything".

## §9 — Security boundaries (apply to any new write path / surface)

- Sanitize untrusted input at the WRITE boundary, once; trust storage at render; re-check size/shape caps AFTER any transform that can grow content (sanitizers add attributes).
- ONE composite write-guard (scrub + capability gate + sanitize) on EVERY path that stores renderable/dangerous content — sibling write paths (templates, imports, saved/shared components) included; a bare or partial sanitizer on a sibling path is the recurring hole.
- Gate the most dangerous sanctioned content class behind an explicit per-principal permission at write time — a capability check distinct from, and additional to, sanitization.
- One canonical URL/href normalizer shared by client AND server: strip control/whitespace, fold `\`→`/`, reject protocol-relative (`//host`, `/\host`), deny dangerous schemes (`javascript:`/`data:`/`vbscript:`); divergence is a stored open-redirect; pin the evasions (`/\evil`, `\\evil`, control chars) in tests on both sides.
- SSRF-guard every outbound request: https-only, resolve to public IPs only, no redirect-following, signed payloads; the SAME guard on retry/queue paths, not just inline; blocking DNS/network resolution runs OFF the event loop (a hung nameserver must not freeze a worker).
- Authorization lives in the shared core (deny-by-default RBAC, defined as code) so every adapter — HTTP, RPC, CLI, AI tool — inherits it; a service fn reachable by a future adapter re-checks authz itself.
- AI/automation runs as a dedicated non-login service principal with a deliberately narrow grant — never a human/admin role; authority bounded by construction.
- Automation writes are draft-only by default; autonomous publish/irreversible action sits behind an explicit default-OFF gate — a standing blast-radius bound distinct from per-feature launch flags.
- Keep PII/secrets off the AI/automation surface structurally: payload/return types that CANNOT carry sensitive values (ids/counts/field-names only); audit value-bearing fields flowing to automated readers.
- Optimistic concurrency on full-document writes: a version/`updated_at` precondition → 409 on stale — else concurrent editors/nodes silently clobber each other.
- Document which production protections are deliberately OFF in the test env (CSRF, rate limits, …), confirm they default ON in production, and exercise each directly in a dedicated test.

## §10 — Recurring bug classes (run in every Tier-2 review)

- Client/server validation divergence: client validates only visible/active fields but submits the whole payload → strip inactive values before send, or validate identically.
- Dead plumbing: a value computed → serialized → passed → never read; wire the consumer or delete end-to-end + guard test.
- Index that doesn't serve its query: a composite led by an inequality, or column order mismatching predicate + `ORDER BY`, can't seek/sort — verify against the real query shape.
- Stale caches: invalidated on create but not rename/delete/restore — reset on ALL mutation paths.
- Cross-language catalog drift in "zero-drift" modules, and coercion/format divergence at ANY cross-language boundary (e.g. numeric stringification differing per runtime) — normalize on one side, guard with a parity test (§7).
- Half-applied merges: one branch's fix silently dropped when the other's version auto-took; duplicate/conflicting symbol definitions — diff the merge against both parents.
- Guard on the primary write path but a bare/partial sanitizer on a SIBLING path to the same stored data (templates, imports, saved/shared components) — verify every such path routes through the §9 composite guard.
- Check-then-insert racing a concurrent bulk-UPDATE (read-committed: the bulk statement's snapshot never sees the in-flight child) — lock the parent row on BOTH the insert and bulk-mutate paths (the lock may be a no-op on the dev DB engine — verify serialization on the production engine).
- Never cache a degraded/failed response (rate-limit, 5xx, flag-off blip) as the permanent answer — mark degraded ≠ genuinely empty and skip caching it, or one transient failure suppresses the feature all session.
- Stale async response race: guard success-path state writes with a request-identity check and abort superseded in-flight requests, or a late response clobbers fresher results.
- Blocking/synchronous work on a hot path or event loop (I/O, DNS, heavy transforms) — find it and off-load it.
- A parallel test runner can deadlock in its OWN distribution/IPC layer after a worker crash — a mode no per-test timeout can reach (it only arms while a test executes). Any `-n auto` suite needs a per-test timeout AND fail-fast on worker death (`--max-worker-restart=0`) AND a pre-kill stack dump (`faulthandler_timeout` below the per-test bound); on Windows a "worker crashed" is your own timeout's `os._exit` until proven otherwise, and a session budget only reds a slow-but-COMPLETING run — it bounds no hang.
- A helper THREAD posting a result to a per-test event loop that already closed must not die trying (the aiosqlite class: a double `call_soon_threadsafe` raise escapes the worker loop, the thread dies, every later op on that connection hangs forever) — loop-side drains cannot win the race, so guard the post at the seam (drop the undeliverable delivery, keep the thread alive) and gate it with a test that FORCES the race deterministically.
- Verify the COMPUTED value, never the declaration: styling/config declarations can silently resolve to nothing (conflicting caps, percentage sizes against indefinite bases, no-op utility values) — measure the rendered result.
- Scale-to-fit frames measure their container SYNCHRONOUSLY at first commit (layout-effect/callback ref), never defaulting until a resize observer fires (unreliable in throttled/preview contexts); a CSS max-width cap fights the scale model (double-shrinks) — rely on the container's overflow clip, verify rendered width ≤ container at a narrow viewport.
- A component defined inside another's render body mints a new type per parent render → full remount per keystroke (focus loss, un-typeable forms) — hoist to module scope.
- Window-scrollbar toggling between short/tall pages shifts centered, window-scrolled layouts (horizontal recenter + header reflow) — stabilize the scrollbar gutter; never let a page depend on scrollbar presence (a no-op on overlay-scrollbar platforms — can't be eyeballed there, so don't drop the gutter rule on that evidence).
- Transient overlays (autocomplete, popups) dismiss on focus-out via a related-target-scoped blur check, per platform a11y authoring practices.
- ID-scheme drift (documented check): new ids are `FAMILY-<slug>-<seq>` (§2); no reused slugs, no pre-rule formats, no renumbering append-only records.
- Where the needed runner/harness doesn't exist, push ALL logic into pure, machine-gated helpers and keep the un-testable wiring deliberately thin — only that residue ships as a documented check.
- Documented checks (no machine gate fits) are labeled so, record WHY no gate fits + the concrete manual recipe (grep pattern, measurement), and graduate to a gate when the missing harness lands.
- Diff-scoping which gate legs run is legitimate economy but ONLY fail-closed and coarse: an unclassified/unrecognized path runs the FULL bar, and never guard a leg on a path set NARROWER than the complete input whose change flips its verdict — a test reads its inputs INDIRECTLY (through a shared module), so a too-narrow guard skips the leg the diff needed and the scoped run passes green-by-absence (§7/§16). Guarding a self-test on its OWN source is safe (guard = full input); a per-file "this file → these tests" map that omits the indirect readers is the trap. The full bar runs once, at the push boundary — enforced by a `pre-push` hook where the project has one, else run by the lander before pushing.
- A ratchet/parity gate that never exercises its target is vacuous and reads as coverage: a coverage check that greps for a literal (a path, a symbol) the real code never spells because it builds it segment-by-segment matches the empty set and passes checking nothing; a `--check` freshness gate whose correct output is "unchanged" on every machine that runs it asserts nothing. Prove the gate CATCHES an injected regression (feed it a synthetic violation → it must red), and gate a non-empty selection — never trust a green.
- A gate's OWN vocabulary hardcoded as a mirror of the codebase's real exports drifts silently: a check keyed on a hand-typed list of the code's own identifiers (component / symbol / path names) diverges the moment that code is renamed, moved, or extended — it is a hand-kept second copy (§12) that the gate can't detect going stale, and it fails LOUD (a false offender → pressure to loosen the check) or SILENT (a new pattern the check doesn't know). Derive that set from source instead (glob, or a co-located marker for a curated semantic role that isn't structurally inferable — prove the structural rule wrong against source before trusting it), guarded by a non-vacuity self-check: a hand-frozen SENTINEL membership + a non-empty assertion, so an empty/wrong derivation reds by name rather than false-flagging en masse, and a kit rename/addition auto-updates the gate or reds it specifically.
- The pre-push full gate must never run on a STALE tree: land the default branch via a lander (`push-main`) that fetch-reconciles origin BEFORE the gate, so a green gate is not thrown away by an immediate non-fast-forward rejection; a during-gate remote race is bounded by a retry cap (not an unbounded loop), and a raw push that bypasses the lander is refused by the hook (a local marker gate; `--no-verify` bypasses). The pre-push hook stays the SOLE mandated full run — DoR/post-merge runs are optional developer-choice fail-fast. Never pipe the gate through `tail`/`head` (it discards the failing-leg row) — read the durable `$(git rev-parse --git-dir)/gate-last-summary.txt`.

## §11 — Cross-OS & toolchain hygiene

- Force `LF` via `.gitattributes` on execution-sensitive filetypes (shell scripts, Dockerfiles, configs, env files, migration templates, runtime-read JSON) — a stray CR breaks shebangs, `sh -c`, servers, generated migrations.
- Verify the staged BYTES, not a pretty-printer: `git diff | cat -A` / `git cat-file -p <blob>`; `git show` and MSYS `grep` mislead on CRLF.
- Pin toolchain versions + the one-true way to run gates on each OS: `PowerShell **5.1** / .NET Framework only - no `&&`, no `||`, no ternary, no `??`; those are parser errors, not runtime ones. Python 3.12 (`python`) and 3.14 (`python3`) both present. In PowerShell, bare `bash` resolves to **WSL**, not git-bash - always spell it `& "C:/Program Files/Git/bin/bash.exe"` in a PowerShell gate wrapper, or the kit scripts run under a different git against a `/mnt/c` mount` — no per-session re-derivation.
- Prefer deterministic run modes (no auto-reload) where a watcher can leave stale processes/ports squatting.
- POSIX-emulation shells on Windows (MSYS/Git-Bash/Cygwin) mangle backslash working-dir paths (`git -C C:\repo` → `fatal: cannot change to 'C:repo'`) — use forward-slash there; a zero-false-positive hook can block the broken form.
- Package installs run from a POSIX-emulation shell can create broken links in the dependency tree — if it looks wrong, reinstall from the native shell.
- Absence of crash evidence is only evidence where the reporter is on: parallel-test workers get fd 0/1 (Windows: fd 2 too) redirected to devnull, so banners and native tracebacks vanish; Windows Event Viewer records nothing when WER is disabled (`Disabled=1`), and an `os._exit` is not a fault so WER never records it anywhere — instrument the process itself (a probe log) before concluding "no crash".

## §12 — Architectural consistency (build-once, reuse-everywhere)

- Decide the extension pattern before the SECOND instance — so #3..#N are data + a few overrides, never new plumbing.
- A "kind" gets a factory/base, not copies: at instance #2, extract the shared contract into a definition helper/base — per-kind map: `an analyzer *rule* is the kind that recurs (reconciliation checks, data-gap rules): each is a pure function appended to the shared findings collection at one seam in `Analyze-SwydoReport.ps1`, so rules #3..N are data plus a predicate, never a new pipeline. A *report surface* is the other: one template, voice profiles as data`.
- One shared core, thin adapters: business logic + authorization in a single service core; HTTP/RPC/CLI/AI surfaces are thin adapters that cannot diverge (also how authz stays consistent, §9).
- Single source of truth → generated artifacts (§7): the catalog of a kind's instances generates the schema/validator/manifest/docs; adding an instance = one edit + a drift gate. When the ONLY consumer is same-language, prefer runtime-derivation over a committed artifact: derive the set live in the check (glob/scan or a co-located marker) and commit NOTHING — there is nothing to keep fresh and drift is structurally impossible; commit + parity-gate an artifact ONLY when a cross-language/cross-layer consumer must read it (that boundary is the artifact's whole justification), and make that parity gate compare the committed artifact against a LIVE re-derivation, never generated-vs-generated (§10).
- Promote shared widgets the instant two features need them, on a two-tier ladder: product-generic presentational primitives → the shared kit (``skill/scripts/` - hardened scripts are reused by dot-sourcing with `-DefineOnly` (the functions-first pattern) and are NEVER behaviorally modified by a caller; guard captured variables with the `$my*` prefix so a caller's name cannot alias a script parameter`); app-scoped shared widgets → that app's own kit; a feature re-implementing or re-styling a primitive locally is a smell.
- Forward-compatible data: new fields additive + defaulted (old content renders identically, new capability inert until used); shape changes ship an auto-upgrade step; prefer riding an existing shape over a migration.
- Reuse audit before building: grep for an existing component/util/endpoint to extend before adding one.
- Gate the layout conventions you can (naming, layer boundaries); the "where things live" map lives in the always-loaded doc (§6) so every feature has an obvious home.

## §14 — Gate discipline: a check that cannot fail is not a check

Ported from a session where six of seventeen review findings were the same defect: a gate satisfied
by its own comment prose, an arm reporting `ok` on a path it never took, a predicate that never
matched its target population.

- **A new gate is not landed until its failing case has been observed.** Stage the break, confirm
  RED, unstage. A gate you have only ever seen pass is an assertion about nothing.
- **A guard that shares a variable with the thing it guards is not a guard.** A backstop that reads
  the same state the bug corrupts is disabled by the bug it exists to catch.
- **Run a candidate gate predicate over the real tree before wiring it**, and print hits AND
  near-misses. Doing so routinely surfaces live instances the original symptom never reached — and
  catches a predicate that would red innocent files.
- **A skip must announce itself.** A skip that looks like a pass is indistinguishable from coverage.
  State which arm went unexercised and why, so a green row is never misread as a verified one.
- **Gate the CLASS, not the instance.** Fixing one file and scanning only that file certifies
  coverage you do not have — the same could-not-fail shape, one level up.
