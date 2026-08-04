# EXTR-aPatientHarvest-1 — extractor completeness under a slow Swydo backend

**Status:** SPECCED · rev-2 · 2026-08-04 · node a · Tier-2 · base ea721b4c

## 1. Goal

Make `skill/scripts/Get-SwydoReport.ps1` finish a report completely when Swydo is slow to compute
widget data. The extractor already opens a websocket on which Swydo reports each widget's outcome,
but its receive function loses every frame, so it blind-sleeps against a fixed attempt count and
guesses. Repair the receive, act on the verdict Swydo actually sends, and when a widget still cannot
be filled, mark the extraction incomplete in data so the closer refuses to publish a report built on
it, rather than emitting a warning a reader can miss.

## 2. Scope (IN)

- **S1.** Fix `Ws-Recv` so a timed-out slice no longer abandons its pending `ReceiveAsync`. This is
  the enabling fix: without it no other websocket behaviour in this spec is observable.
- **S2.** New `Wait-WidgetVerdict` replaces the blind `Start-Sleep`. It reads frames until Swydo's
  per-request verdict arrives, answers a `kind:4` frame with `kind:5`, and returns the verdict.
- **S3.** Act on the verdict: `RESOLVED` means re-query now, `REJECTED` means rows will never come
  for this window and waiting longer is pointless.
- **S4.** `Invoke-GQL` takes an explicit request timeout and retries transport faults with backoff.
  Exhaustion returns a structured failure marker; it no longer re-throws and kills the run.
- **S5.** `Fetch-Widget` moves from an attempt count to a wall-clock budget, driven by the pure
  helpers `Get-FetchPlan` and `Get-WidgetOutcome`, and returns a per-widget outcome record.
- **S6.** Two new parameters, `-MaxWaitSec` (per widget) and `-MaxTotalWaitSec` (whole run), both
  with defaults set in section 4 and both overridable per invocation.
- **S7.** Every data widget ends the run classified `filled`, `empty-resolved`, `rejected` or
  `incomplete`, per the classifier in section 4.
- **S8.** The extraction document gains additive `meta.extractionComplete`,
  `meta.incompleteWidgets` and `meta.fetchBudget`. The existing `meta.warnings` entry is kept
  byte-compatible so current `GAP_WARNINGS` behaviour does not regress.
- **S9.** `skill/scripts/Analyze-SwydoReport.ps1` copies the completeness verdict into `facts.meta`
  and emits a `GAP_EXTRACTION_INCOMPLETE` data gap at severity `critical`.
- **S10.** `skill/scripts/Test-ReportNumbers.ps1` gains an `incomplete-extraction` violation type, so
  a report whose facts declare an incomplete extraction cannot PASS and cannot be published.
- **S11.** The trend path reads the ceiling from `REJECTED` rather than inferring it from emptiness:
  `Probe-WidgetMonths` returns a four-state result and `Get-WidgetCeiling` treats only an explicit
  rejection as evidence of overshoot, aborting on an unsettled probe instead of guessing.
- **S12.** Additive offline cases in `Test-Extractor.ps1`, `Test-Analyze.ps1` and `Test-Closer.ps1`,
  driven through the dot-source seam verified in section 4.
- **S13.** `skill/SKILL.md` documents the completeness gate and both new flags.

## 3. Non-goals (OUT)

- No batched fetching. Firing every widget first and harvesting afterwards is faster but breaks the
  frame-to-widget attribution this design relies on; deferred to `EXTR-aPatientHarvest-2`.
- No change to `$script:TrendLadder`, `Select-CeilingBracket` or `Get-NextBisectN`. S11 changes what
  counts as evidence of a ceiling, never the search over ceilings.
- No `schemaVersion` bump. Every new field is additive and optional.
- No change to analyzer arithmetic, canonical-total precedence, reconciliation rules, or
  `skill/report-template.md`.
- No new auth behaviour beyond the existing single 401 re-mint in `Invoke-GQL`.
- No fix for the 1 MiB `$script:buf` ceiling in `Ws-Recv`, and no handling of a frame split across
  websocket continuation fragments. Observed frames are about 120 bytes. Both stay known limits.
- No retry of the share-page fetch or the structure query. Those fail loudly at startup, which is
  correct for a bad link.

## 4. Design

### Data model

Three additive `meta` fields on the extraction document. Absence must be read as "complete", so
every extraction produced before this change keeps passing downstream unchanged.

```
meta.extractionComplete : bool          # false only when at least one widget ended 'incomplete'
meta.incompleteWidgets  : [ { id, visual, reason, waitedMs, lastVerdict, queries } ]
meta.fetchBudget        : { maxWaitSec, maxTotalWaitSec, totalWaitedMs, budgetExhausted }
```

`reason` is one of `budget-exhausted`, `run-budget-exhausted`, `transport-failed`, `socket-lost`,
`rejected`.

`facts.meta` gains `extractionComplete` and `incompleteWidgets` as widget ids only. The raw widget
payload never crosses into facts, so the existing credential scrub is untouched.

### Inventory

Every claim below was measured live against the QCU share on 2026-08-04, not inferred.

| Observation | Measured | Consequence |
|---|---|---|
| Warm widget, first query | 43 of 43 filled on attempt 1, 108-224 ms | the fast path must add no latency |
| Cold widget, first query | returns EMPTY in 128-252 ms, never blocks | the problem is an async compute, not a slow call |
| Cold widget, ready signal | `{"kind":3,"payload":{"id":"dataRows:view:...","status":"RESOLVED"}}` at 1220 ms and 3418 ms | the ready signal exists and is timely |
| Out-of-range window | same frame shape with `"status":"REJECTED"` at 44 ms and 260 ms | refusal is explicit, fast, and distinguishable from slow |
| Shipped receive vs fixed receive | 0 of 5 frames seen vs 5 of 5, same workload | the shipped receive loses every frame |
| Bare `Invoke-WebRequest` on a stalled socket | still waiting at 721 s, no exception | there is no default timeout to fall back on |

The root cause is `Ws-Recv` at `skill/scripts/Get-SwydoReport.ps1:79`. It calls `ReceiveAsync` and
then `$t.Wait($ms)`. When that wait times out the task is abandoned but stays pending, so the frame
that arrives next completes the orphaned task into `$script:buf` with nobody reading `Result`, and
the frame is consumed and lost. The next call then issues a second `ReceiveAsync`, which
`ClientWebSocket` refuses while one is outstanding; the surrounding `catch{}` swallows that too. A
controlled A/B against the same cold workload settles it: the shipped shape observed 0 `kind:3`
frames across five widgets, while a receiver that keeps the pending task across calls observed 5 of
5. The fix is to hold the task in a script-scope variable, re-await it on the next call, and clear
it only once its result has actually been read.

Everything downstream follows from that. `Ws-Pulse` at `:88-93` reads one frame and ignores it
unless `kind -eq 4`, so even when a frame did survive it was discarded. `Fetch-Widget` at `:145-150`
therefore has no evidence to act on and falls back to `Start-Sleep -Milliseconds 900` for at most 5
attempts, which is 4.5 seconds of deliberate waiting; the reconcile loop at `:501-506` adds three
rounds of 2 seconds plus four more attempts, about 21.3 seconds of total patience per cold widget
across the whole run. Against a measured 3418 ms resolve that is a coin flip, and against a slower
one it is a loss. Note also that a broken receive means the `kind:4` keepalive has never been
answered either, so the socket's liveness has been resting entirely on
`Options.KeepAliveInterval`.

Two further defects sit on the transport path, and they compound. No call in the file passes
`-TimeoutSec`, and Windows PowerShell 5.1 applies no effective default: measured against a loopback
listener that accepts the connection and never writes a byte, a bare `Invoke-WebRequest` was still
waiting after 721 seconds with no exception raised, at which point the probe was stopped. The
documented "0 means indefinite" behaviour is what actually happens, not the 100 second
`HttpWebRequest.Timeout` default the type exposes. And if a request does eventually fault,
`Invoke-GQL` at `:72` re-throws any exception whose `$_.Exception.Response` is null, which is
exactly the shape of a transport fault; nothing between that line and the top level catches it, and
`$ErrorActionPreference` is `Stop`, so the run aborts with no JSON written at all. An explicit
`-TimeoutSec` is therefore load-bearing rather than defensive: without it the budget in S5 cannot be
enforced, because one hung call outlives any budget the loop tries to keep.

### Migration

None. Every field is additive and optional, and the completeness check treats an absent flag as
complete. A facts file already on disk, or a Mode B run over an extraction produced before this
change, behaves exactly as it does today.

### Rollout

The closer check ships enabled and is inert by construction: it fires only on an explicit
`extractionComplete -eq $false`, a value only the post-change extractor can produce, so no existing
artifact can newly fail. This satisfies the land-risky-behaviour-dark rule in `AGENTS.md` section 1
through inert defaulted data rather than a feature flag, because a flag defaulting the fix OFF would
ship the bug.

Verification in place is a live re-run against the QCU share, diffing the new extraction against a
pre-change extraction of the same report. For a fully warm report the widget payloads must be
byte-identical apart from the three new `meta` fields and the timestamps.

The per-widget state machine, bounded by `min(MaxWaitSec, remaining run budget)`:

1. Drain the socket of backlog before firing, so a frame left from the previous widget is not
   mistaken for this one's. The drain is only safe once S1 lands; with the shipped receive it is
   what destroys the signal. Frames arriving between the query returning and the wait starting are
   not lost, because the OS socket buffer holds them until the next read.
2. Query once. Rows greater than zero ends it as `filled`, at today's cost and no more.
3. Otherwise wait for this request's verdict: `Ws-Recv` on a short slice; `kind:4` is answered with
   `kind:5` and continues; `kind:3` yields the verdict and ends the wait; an empty slice re-queries
   only once `pollEveryMs` has elapsed, so the fallback poll is bounded and the design still
   terminates correctly if Swydo ever stops sending frames.
4. Classify with the pure `Get-WidgetOutcome`:
   `RESOLVED` and the re-query returns rows gives `filled`;
   `RESOLVED` and the re-query returns none gives `empty-resolved`, which is a complete answer -
   the period genuinely holds no data;
   `REJECTED` gives `rejected` and stops the wait immediately, because more waiting cannot help;
   no verdict before the budget expires gives `incomplete`.
5. Only `incomplete` sets `meta.extractionComplete` to false. On the default report path a
   `rejected` verdict is also treated as incomplete, with reason `rejected`, because the report is
   asking for its own configured date range and a refusal there is a real fault rather than an
   expected answer. On the trend probe path `rejected` is the expected, wanted answer.
6. If the socket is not `Open` at any point, reconnect. A reconnect mints a new `socketId`, which
   orphans the pending compute, so the widget's query is re-fired against the new socket and its
   wait clock restarts. Restarts are capped at `maxReconnects` so a reconnect loop cannot consume
   the run budget.

Frames do not name the widget they belong to; the payload id is an opaque
`dataRows:view:<hash>-<epoch>`. Attribution is positional and is sound only because fetching is
sequential and step 1 drains first: exactly one request is outstanding when the wait begins. This is
precisely why batched fetching is out of scope.

The pure helpers carry every decision a test needs to assert, so no test has to sleep or reach the
network:

- `Get-FetchPlan($maxWaitSec)` returns `sliceMs`, `pollEveryMs`, `quietFallbackMs`,
  `minFallbackQueries` and `maxReconnects`.
- `Get-WidgetOutcome($verdict, $rows, $budgetLeftMs)` returns `filled`, `empty-resolved`,
  `rejected` or `incomplete`.

Defaults are `-MaxWaitSec 90` and `-MaxTotalWaitSec 420`. Ninety seconds is roughly twenty-six times
the slowest measured resolve, which leaves wide headroom for a slow backend without letting a dead
one hang a session. The run figure bounds the worst case where every widget is cold: 43 widgets at
about 3.5 seconds each is roughly 150 seconds, so 420 leaves margin while still failing in minutes
rather than hours. Both are parameters precisely because these are judgement calls made on one
report's evidence.

S11 matters more than its size suggests. `Get-WidgetCeiling` currently treats an empty window as
proof that the window overshoots the provider's history and bisects on that signal, so a slow but
real window is indistinguishable from a genuine overshoot and the bisect converges on a ceiling that
is too low, silently truncating a client's history. The ledger's existing "a null or overshoot pull
never clobbers a good value" rule does not save the first pull for a new client, because there is no
prior good value to protect. After S11 the probe returns `has-months`, `rejected`, `empty-resolved`
or `unsettled`; only `rejected` and `empty-resolved` are admissible as ceiling evidence, and
`unsettled` aborts the probe with an error rather than guessing. The measured refusal latency of 44
to 260 ms also makes the ladder markedly faster than the current 4.5 seconds burned per overshoot
rung.

### Files touched (estimate)

| File | Change |
|---|---|
| `skill/scripts/Get-SwydoReport.ps1` | the receive fix, the verdict wait, the pure helpers, two parameters, the meta fields, the trend probe states |
| `skill/scripts/Analyze-SwydoReport.ps1` | propagate the verdict, emit `GAP_EXTRACTION_INCOMPLETE` |
| `skill/scripts/Test-ReportNumbers.ps1` | the `incomplete-extraction` violation in `Invoke-Closer` |
| `skill/SKILL.md` | document the gate and the two flags |
| `Test-Extractor.ps1` | pure-helper cases plus seam-driven state-machine cases |
| `Test-Analyze.ps1` | propagation and the new gap, including the absent-flag compat case |
| `Test-Closer.ps1` | the new violation, including the absent-flag compat case |

The offline seam is verified, not assumed. Dot-sourcing with `-DefineOnly` loads the functions into
the caller's scope, and a later redefinition of `Invoke-GQL` in that same scope is what
`Fetch-Widget` resolves at call time. A test-scope `function Start-Sleep` shadows the cmdlet, since
PowerShell resolves functions ahead of cmdlets. Both were confirmed against Windows PowerShell
5.1.22621.4249 before this spec was written: a stubbed `Fetch-Widget` run recorded exactly the
expected five 900 ms sleeps and completed in 102 ms of wall clock.

### Alternatives rejected

- **Raise the attempt count and the sleep.** The smallest diff and it fixes nothing structural. The
  receive is broken, so more attempts still observe nothing, still cannot separate slow from
  refused, and still die on a transport fault.
- **Keep polling only and ignore the websocket.** Workable, and it is retained as the fallback arm
  in step 3, but as the primary mechanism it throws away an exact answer Swydo is already sending
  and replaces it with a quiescence heuristic that cannot distinguish `REJECTED` from slow.
- **Fire every widget, then harvest.** Materially faster because the computes pipeline. Rejected
  here because the frame carries no widget identity, so with many computes in flight attribution
  collapses and the per-widget verdict, the strongest part of this design, is lost.
- **Correlate frames by recomputing the `dataRows:view` hash.** Rejected outright. The hash input is
  undocumented and unversioned, and a correlation that silently stopped matching would degrade to
  blind polling with nothing to signal that it had.
- **Hard-fail the run on any empty widget.** Rejected by the owner on 2026-08-04. A platform with
  genuinely zero activity in the period is a legitimate report, and `empty-resolved` is exactly how
  this design tells that apart from a failure.

## 5. Production-readiness checklist

- **security** — no new egress and no new credential path. `meta.incompleteWidgets` carries widget
  ids the document already contains. The share key is still never printed and `Assert-NoCredential`
  is untouched.
- **perf / scale** — the warm path keeps its single query per widget at 108-224 ms. The cold path
  gets faster, not slower, because a 1220-3418 ms verdict replaces a 4.5 second sleep ladder and a
  44-260 ms refusal replaces it entirely on the trend ladder.
- **a11y** — N/A. A command-line tool with no interface.
- **i18n** — N/A. Output is ASCII console text and machine-read JSON.
- **error / empty / loading states** — this unit is that work. The four-state outcome is the
  deliverable, and `empty-resolved` is the state the current code cannot express.
- **observability** — the existing per-widget console line gains its outcome and verdict;
  `meta.fetchBudget` records what the run actually spent, so a slow client is diagnosable from the
  artifact alone.
- **risks** — the largest is attribution: a verdict frame is matched to the outstanding request
  positionally, so any future concurrency would silently mis-attribute it; step 1's drain and the
  sequential-fetch non-goal are what hold that closed, and a test pins it. A reconnect loop is
  bounded by `maxReconnects`. Treating `rejected` as incomplete on the default path could newly
  block a report that previously published with a silently empty widget, which is the intended
  direction but is a behaviour change worth watching on the first live runs.
- **testing + left-shift gates** — additive cases in three suites. Every confirmed defect in this
  spec gets a regression case: the orphaned receive, the discarded verdict, the fatal transport
  fault, the false ceiling, and absent-flag compatibility.
- **migration / rollback** — no migration. Rollback is a single clean revert; the additive fields are
  ignored by any consumer that does not know them.
- **user docs** — `skill/SKILL.md` gains the completeness gate and the two flags.

## 6. Acceptance criteria

- **AC1.** When a stubbed socket delivers a frame only after an earlier receive slice has already
  timed out, `Ws-Recv` still returns that frame, proving the orphaned-receive defect is closed.
- **AC2.** When the wait receives `kind:3` with `status` `RESOLVED`, `Fetch-Widget` re-queries
  immediately rather than waiting out the poll interval.
- **AC3.** When the wait receives `kind:3` with `status` `REJECTED`, the wait ends at once and no
  further query is issued for that window.
- **AC4.** When the wait receives `kind:4`, it replies `kind:5` and keeps waiting, and the frame is
  not treated as a verdict.
- **AC5.** When a widget returns rows on the first query, the number of `Invoke-GQL` calls and the
  emitted widget object are identical to pre-change behaviour.
- **AC6.** When `Invoke-GQL` hits a transport fault with no HTTP response, the run continues and the
  widget is retried, instead of the process aborting with no JSON written.
- **AC7.** When a widget never returns a verdict within the budget, it ends `incomplete`,
  `meta.extractionComplete` is `$false`, and `meta.incompleteWidgets` names it with reason
  `budget-exhausted`.
- **AC8.** When a widget resolves and the re-query still returns zero rows, it ends `empty-resolved`
  and `meta.extractionComplete` stays `$true`, so a zero-activity platform does not block a report.
- **AC9.** When facts carry `extractionComplete: false`, `Invoke-Closer` returns an
  `incomplete-extraction` violation and the script exits non-zero without publishing.
- **AC10.** When facts carry no `extractionComplete` key at all, `Invoke-Closer` returns no such
  violation, proving pre-change artifacts still pass.
- **AC11.** When a trend probe window is refused, `Get-WidgetCeiling` records it as overshoot
  evidence; when a probe window returns neither rows nor a verdict, it raises an error instead of
  recording that window as the ceiling.
- **AC12.** When the whole run budget is exhausted, remaining widgets end `incomplete` with reason
  `run-budget-exhausted` and the document is still written, so the failure is inspectable.
- **AC13.** When the extractor is run live against the QCU share, every data widget ends `filled`,
  `meta.extractionComplete` is `$true`, and the widget payloads are byte-identical to a pre-change
  extraction of the same report apart from the new `meta` fields and timestamps.

## 7. Gates

`bash tools/run-gates.sh` must be green on every leg. `Test-Extractor.ps1`, `Test-Analyze.ps1` and
`Test-Closer.ps1` are additive on their own assertion counts and every other suite's count is
unchanged. `bash scripts/manifest-check.sh` stays green, and the manifest is re-stamped if this unit
changes what it front-loads. `python tools/gate-lint/ps-hygiene.py .` must stay green, which for
this unit means pure-ASCII sources and no case-only variable collision among the new names.

## 8. Open questions

- **Fork 1, behaviour when a widget is still empty at the end of the budget.** RESOLVED (owner,
  2026-08-04): write the document, flag it in facts, and let the closer refuse to publish. Not a
  hard run failure, because a genuinely zero-activity platform is a legitimate report.
- **Fork 2, how much wall clock an extraction may spend.** RESOLVED (owner, 2026-08-04):
  configurable with a sane default. Realised as `-MaxWaitSec` and `-MaxTotalWaitSec`.
- **Fork 3, whether `REJECTED` on the default report path should block publish.** Recommendation:
  yes, treat it as `incomplete` with reason `rejected`. The default path asks for the report's own
  configured date range, so a refusal is a genuine fault rather than an expected answer, and the
  alternative is publishing over a silently missing widget. Only two statuses were observed, so this
  is the conservative reading of an incompletely mapped enum.
- **Fork 4, whether `GAP_EXTRACTION_INCOMPLETE` should be `critical` or `major`.** Recommendation:
  `critical`, because unlike every existing gap it means the input itself is untrustworthy rather
  than one number being unavailable. The closer violation in S10 is what actually blocks publish
  either way.
- **Fork 5, the fallback-poll constants.** `quietFallbackMs` and `minFallbackQueries` only matter if
  Swydo stops sending frames entirely, which was never observed once S1's fix was in place.
  Recommendation: `quietFallbackMs` 6000 and `minFallbackQueries` 3, exposed on `Get-FetchPlan` so
  they can be retuned without touching the state machine.

## 9. Revision log

- rev-1 · 2026-08-04 · initial draft, grounded on three live probes of the QCU share: warm-path
  timing, cold-path retry curve, and a frame capture that identified the `kind:3` signal.
- rev-2 · 2026-08-04 · two further probes overturned the rev-1 premise. A controlled A/B proved the
  shipped `Ws-Recv` loses every frame by abandoning its pending `ReceiveAsync`, promoting that from
  an unstated assumption to S1, the enabling fix. Re-running the overshoot case with a correct
  receiver revealed a second status, `REJECTED`, which replaces rev-1's quiescence heuristic with an
  exact discriminator and rewrites S11 from mitigation to a precise signal. A black-hole listener
  showed `Invoke-WebRequest` has no default timeout at all, making the explicit `-TimeoutSec`
  load-bearing rather than defensive.

## 10. Reuse audit

No existing seam fits, and there is no automated reuse pass to cite: the codebase-map kit is not
adopted in this repo, so `tools/codebase-map/reuse_lookup.py` does not exist here. The seams were
identified by reading source. `Ws-Recv` at `skill/scripts/Get-SwydoReport.ps1:79` is the single
receive path for every websocket consumer in the file, so the S1 fix lands once and repairs
`Connect-Ws`, `Ws-Pulse` and the new wait together. `Fetch-Widget` at `:139-163` is the single choke
point every data pull already passes through, including the trend probe path via
`Probe-WidgetMonths` at `:306-309`, so the retry rework is not duplicated per caller.
`Invoke-Closer` at `skill/scripts/Test-ReportNumbers.ps1:316-468` is the single place every
violation is raised and is already dot-source testable, so the completeness check reuses the
existing violation contract rather than adding a parallel gate. The offline test seam reuses the
established `-DefineOnly` dot-source pattern that all eight suites already use.
