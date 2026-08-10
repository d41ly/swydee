# EXTR-aPatientHarvest-1 — extractor completeness under a slow Swydo backend

**Status:** CLOSED · rev-6 · 2026-08-04 · node a · Tier-2 · base ea721b4c · review 2026-08-04-review-aPatientHarvest-1 · ratified 2026-08-04 · landed 3e5bd93

## 1. Goal

Make `skill/scripts/Get-SwydoReport.ps1` finish a report completely when Swydo is slow to compute
widget data. The extractor already opens a websocket on which Swydo reports each widget's outcome,
but its receive function loses every frame, so it blind-sleeps against a fixed attempt count and
guesses. Repair the receive, act on the verdict Swydo actually sends, and when a widget still cannot
be filled, mark the extraction incomplete in data so the closer refuses to publish a report built on
it, rather than emitting a warning a reader can miss.

## 2. Scope (IN)

- **S1.** Fix `Ws-Recv` so a timed-out slice no longer abandons its pending `ReceiveAsync`. The
  pending task is held in `$script:pendingRecv` and the slot is cleared when the task completes and
  its `Result` has been read, when it ends `Faulted` or `Canceled`, or when the result's
  `MessageType` is `Close`. This is the enabling fix: without it no other websocket behaviour here
  is observable.
- **S2.** New `Reset-FetchState`, defined above the `-DefineOnly` return, clears `$script:pendingRecv`,
  the run-budget accumulator, the reconnect counter and `$script:outstandingComputes`. The run body
  calls it once at start; every suite case calls it in setup.
- **S3.** `Connect-Ws` nulls `$script:pendingRecv` as its first statement and `$script:socketId`
  before connecting, returns `$true` only when a `socketId` was obtained, and returns `$false` on a
  connect fault or on no `kind:2` within a bounded `handshakeMs`, instead of throwing into a bare
  `catch{}`.
- **S4.** New `Wait-WidgetVerdict` replaces the blind `Start-Sleep`. It reads frames until this
  request's verdict arrives, answers `kind:4` with `kind:5`, and returns the verdict.
- **S5.** Act on the verdict: `RESOLVED` means re-query now, `REJECTED` means rows will never come
  for this window.
- **S6.** Every network call reachable during a run is explicitly bounded. `Invoke-GQL` takes a
  request timeout and retries transport faults with backoff; `Mint-Jwt` and the share-page fetch take
  an explicit `-TimeoutSec`; `ConnectAsync` and `SendAsync` use bounded `.Wait($ms)`.
- **S7.** `Invoke-GQL` returns a structured failure marker on retry exhaustion instead of re-throwing.
  Every caller branches on it before `ConvertFrom-Json`. `-NoRetry` is passed by the share-page fetch
  and the structure query, which still throw at startup.
- **S8.** `Fetch-Widget` moves from an attempt count to a wall-clock budget. Its signature becomes
  `Fetch-Widget($w, $dr, $cp, $opt)`; the attempt-count positional slot is REMOVED, not repurposed.
- **S9.** Two new parameters, `-MaxWaitSec` (per widget) and `-MaxTotalWaitSec` (whole run), both
  overridable per invocation.
- **S10.** Every data widget ends classified `filled`, `empty-resolved`, `rejected` or `incomplete`,
  by the classifier in section 4. Any widget ending without a verdict forces a reconnect before the
  next widget, so no compute is ever left outstanding across a widget boundary.
- **S11.** The pagination loop distinguishes a faulted page from a last page and can end a widget
  `incomplete` with reason `partial-pages`. A widget is never `filled` when a page fetch faulted.
- **S12.** New pure `Get-ExtractionCompleteness`, defined above the `-DefineOnly` return, computes the
  three additive `meta` fields. The run body only splices its result into `$doc.meta` and `$tdoc.meta`.
- **S13.** The extraction document and the trend document both gain additive `meta.extractionComplete`,
  `meta.incompleteWidgets` and `meta.fetchBudget`. The existing `meta.warnings` entry stays
  byte-compatible so current `GAP_WARNINGS` behaviour does not regress.
- **S14.** `skill/scripts/Analyze-SwydoReport.ps1` copies the completeness verdict into `facts.meta`
  and emits a `GAP_EXTRACTION_INCOMPLETE` data gap at severity `critical`.
- **S15.** `skill/scripts/Test-ReportNumbers.ps1` gains an `incomplete-extraction` violation type, so
  a report whose facts declare an incomplete extraction cannot PASS and cannot be published.
- **S16.** The trend chain carries the verdict end to end: `ConvertTo-SwydoTrendFacts.ps1` copies the
  fields into its meta, `Analyze-SwydoTrend.ps1` copies them into its facts meta, and
  `Update-SwydoLedger.ps1` refuses to merge trend facts whose `extractionComplete` is `$false`.
- **S17.** The trend ceiling probe reads overshoot from `REJECTED` rather than inferring it from
  emptiness. `Probe-WidgetMonths` returns a state plus months; the accept/reject decision moves into
  a pure `Test-CeilingStillValid`; the ceiling cache is versioned so pre-change entries are ignored
  once.
- **S18.** Additive offline cases in `Test-Extractor.ps1`, `Test-Analyze.ps1`, `Test-Closer.ps1`,
  `Test-TrendFacts.ps1`, `Test-Ledger.ps1` and `Test-TrendAnalyze.ps1`.
- **S19.** `skill/SKILL.md` documents the completeness gate and both new flags.

## 3. Non-goals (OUT)

- No batched fetching. Firing every widget first and harvesting afterwards is faster but breaks the
  frame-to-widget attribution this design relies on; deferred to `EXTR-aPatientHarvest-2`.
- No change to `$script:TrendLadder`, `Select-CeilingBracket` or `Get-NextBisectN`. S17 changes what
  counts as evidence of a ceiling, never the search over ceilings.
- No `schemaVersion` bump. Every new field is additive and optional.
- No change to analyzer arithmetic, canonical-total precedence, reconciliation rules, or
  `skill/report-template.md`.
- No new auth behaviour beyond the existing single 401 re-mint in `Invoke-GQL`. `Mint-Jwt` still gains
  a timeout, which is a bound rather than a behaviour.
- No RETRY of the share-page fetch or the structure query. Both still take an explicit `-TimeoutSec`,
  and both still throw on a transport fault, which is correct for a bad link.
- No fix for the 1 MiB `$script:buf` ceiling in `Ws-Recv`, and no handling of a frame split across
  websocket continuation fragments. Observed frames are about 120 bytes. Both stay known limits.
- No fix for `AGENTS.md:167`, which prescribes a singular `review/` artifact folder while hygiene
  check 4 sanctions only `reviews/`. Filed as a backlog row; the edit is outside this unit.

## 4. Design

### Data model

Three additive `meta` fields, on both the extraction document and the trend document. Absence must be
read as "complete", so every artifact produced before this change keeps passing downstream unchanged.

```
meta.extractionComplete : bool          # false when any widget ended 'incomplete'
meta.incompleteWidgets  : [ { id, visual, reason, waitedMs, lastVerdict, queries,
                              pagesFetched, endCursor } ]
meta.fetchBudget        : { maxWaitSec, maxTotalWaitSec, totalWaitedMs, budgetExhausted }
```

`reason` is one of `budget-exhausted`, `run-budget-exhausted`, `transport-failed`, `socket-lost`,
`rejected`, `partial-pages`, `stale-verdict-risk`.

`facts.meta` gains `extractionComplete` and `incompleteWidgets` as widget ids only. The raw widget
payload never crosses into facts, so the existing credential scrub is untouched.

The whole block is produced by a pure `Get-ExtractionCompleteness $outcomes $plan $budgetState`
defined ABOVE the `-DefineOnly` return at `:365`, returning exactly the three keys. The run body does
nothing but splice that block in, which is what makes S13 observable from the suites at all.
`incompleteWidgets` is always `@()`-wrapped, so a single null can never masquerade as one entry.

### Inventory

Every claim below was measured live against the QCU share on 2026-08-04, not inferred.

| Observation | Measured | Consequence |
|---|---|---|
| Warm widget, first query | 43 of 43 filled on attempt 1, 108-224 ms | the fast path must add no latency |
| Cold widget, first query | returns EMPTY in 128-252 ms, never blocks | an async compute, not a slow call |
| Ready signal | `{"kind":3,"payload":{"id":"dataRows:view:...","status":"RESOLVED"}}` at 1220 ms and 3418 ms | the signal exists and is timely |
| Out-of-range window | same shape with `"status":"REJECTED"` at 44-260 ms | refusal is explicit, fast, distinguishable from slow |
| Shipped receive vs fixed receive | 0 of 5 frames seen vs 5 of 5, same workload | the shipped receive loses every frame |
| Silent band | 37 and 39 months returned neither rows nor a verdict for 30 s | a third outcome exists: no answer at all |
| Silent band, retried | 37 months returned `REJECTED` in 49 ms on the next attempt; 39 months stayed silent through 30 s and 90 s | silence is often transient, so it must be retried before it is believed |
| Bare `Invoke-WebRequest` on a stalled socket | still waiting at 721 s, no exception | there is no default timeout to fall back on |
| Whole-report run, current code | 5 widgets empty on the first pass, 1 m 38 s wall for about 6 s of work | today's cost is nearly all blind sleeping |

The root cause is `Ws-Recv` at `skill/scripts/Get-SwydoReport.ps1:79`. It calls `ReceiveAsync` and
then `$t.Wait($ms)`. When that wait times out the task is abandoned but stays pending, so the frame
that arrives next completes the orphaned task into `$script:buf` with nobody reading `Result`, and
the frame is consumed and lost. The next call then issues a second `ReceiveAsync`, which
`ClientWebSocket` refuses while one is outstanding; the surrounding `catch{}` swallows that too. A
controlled A/B against the same cold workload settles it: the shipped shape observed 0 `kind:3`
frames across five widgets, a receiver holding the pending task observed 5 of 5.

Everything downstream follows. `Ws-Pulse` at `:88-93` reads one frame and ignores it unless
`kind -eq 4`, so even a surviving frame was discarded. `Fetch-Widget` at `:145-150` therefore has no
evidence and falls back to `Start-Sleep -Milliseconds 900` for at most 5 attempts, 4.5 seconds of
deliberate waiting; the reconcile loop at `:501-506` adds three rounds of 2 seconds plus four more
attempts, about 21.3 seconds of total patience per cold widget. Against a measured 3418 ms resolve
that is a coin flip. Note also that a broken receive means the `kind:4` keepalive has never been
answered, so socket liveness has rested entirely on `Options.KeepAliveInterval`.

Two further defects sit on the transport path and compound. No call in the file passes `-TimeoutSec`,
and Windows PowerShell 5.1 applies no effective default: against a loopback listener that accepts and
never writes, a bare `Invoke-WebRequest` was still waiting at 721 seconds. The documented "0 means
indefinite" behaviour is what happens, not the 100 second `HttpWebRequest.Timeout` the type exposes.
And if a request does fault, `Invoke-GQL` at `:72` re-throws any exception whose
`$_.Exception.Response` is null; nothing catches it and `$ErrorActionPreference` is `Stop`, so the
run aborts with no JSON at all. Bounding `Invoke-GQL` alone is not enough: the 500-second JWT re-mint
fires from inside a widget's own re-query, so an unbounded `Mint-Jwt` would hang the run past both
budgets through the auth door instead of the GraphQL door.

### Migration

None for extraction and facts documents; every field is additive and optional, and an absent flag
reads as complete. The ceiling cache IS versioned: entries gain `probeVersion=2` and any entry lacking
`probeVersion -ge 2` is ignored exactly once, so the first post-change trend run re-derives every
ceiling rather than inheriting a false one from the emptiness-based prober. On a cache hit the entry
is written back with its ORIGINAL `discoveredAt`; `:441` must not re-stamp it with `$now`, or the
30-day TTL never expires for a client whose trend runs monthly.

### Rollout

The closer check ships enabled and is inert by construction: it fires only on an explicit
`extractionComplete -eq $false`, a value only the post-change extractor can produce, so no existing
artifact can newly fail. This satisfies the land-risky-behaviour-dark rule in `AGENTS.md` section 1
through inert defaulted data rather than a feature flag, because a flag defaulting the fix OFF would
ship the bug.

Verification in place is a live re-run against the QCU share, diffed against the pre-change baseline
already captured for this unit (43 of 43 data widgets, 294 rows, no warnings). For a fully warm
report the widget payloads must be byte-identical apart from the new `meta` fields and timestamps.

The per-widget state machine, bounded by `min(MaxWaitSec, remaining run budget)`:

1. Drain the socket of backlog before firing, using a non-zero `plan.drainSliceMs` (default 50 ms)
   and looping until a slice returns empty. `Ws-Recv 0` is forbidden: `Task.Wait(0)` returns false on
   a frame already sitting in the OS buffer and would silently no-op the drain. A `kind:4` seen
   during the drain is still answered with `kind:5`. The drain is only safe once S1 lands; with the
   shipped receive it is what destroys the signal.
2. Query once. Rows greater than zero ends it as `filled`, at today's cost and no more.
3. Otherwise wait for this request's verdict: `Ws-Recv` on a short slice; `kind:4` is answered with
   `kind:5` and continues; `kind:3` yields the verdict and ends the wait; an empty slice re-queries
   only once `pollEveryMs` has elapsed, so the design still terminates if Swydo stops sending frames.
4. Classify with the pure `Get-WidgetOutcome $verdict $rows $budgetLeftMs $outstandingComputes`:
   `RESOLVED` with rows gives `filled`;
   `RESOLVED` with no rows gives `empty-resolved`, a complete answer meaning the period genuinely
   holds no data — but ONLY while `$outstandingComputes` is zero; while it is greater than zero the
   same input gives `incomplete` with reason `stale-verdict-risk`;
   `REJECTED` gives `rejected` and stops the wait immediately;
   no verdict before the budget expires gives `incomplete`.
5. Any widget ending WITHOUT a verdict (`incomplete`, `transport-failed`, `socket-lost`,
   `run-budget-exhausted`, `partial-pages`) increments `$script:outstandingComputes` and forces
   `Connect-Ws` before the next widget is fetched; a successful reconnect mints a new `socketId`,
   orphaning the abandoned compute so it can never deliver on the live socket, and resets the counter
   to zero. On the default report path a `rejected` verdict is also treated as incomplete, with reason
   `rejected`, because the report is asking for its own configured date range and a refusal there is
   a real fault. On the trend probe path `rejected` is the expected, wanted answer.
6. No query is ever fired while `$script:socketId` is `$null`: the widget ends immediately with reason
   `socket-lost`. After `maxReconnects` consecutive failed reconnects the run stops fetching and
   writes the document with the remaining widgets `incomplete`. Handshake wall clock is charged to
   `totalWaitedMs`.
7. The reconcile loop at `:501-506` is REMOVED; its function now lives inside the verdict wait.
   Leaving it would let a later round overwrite a settled outcome, making publish or no-publish
   depend on round timing.

Attribution is positional, because the frame's payload id is an opaque `dataRows:view:<hash>-<epoch>`
that cannot be mapped back to a widget. It is sound only because fetching is sequential, step 1
drains first, AND step 5 forces a reconnect after every unverdicted widget, so no compute is ever
left outstanding across a widget boundary. The `$outstandingComputes` guard in step 4 is the second
line of defence for the window between a widget timing out and the reconnect completing. This is
precisely why batched fetching is out of scope.

The pure helpers carry every decision a test needs, so no test sleeps or reaches the network:

- `Get-FetchPlan($maxWaitSec)` returns `sliceMs`, `pollEveryMs`, `drainSliceMs`, `handshakeMs`,
  `quietFallbackMs`, `minFallbackQueries`, `retryUnsettledOnce`, `maxReconnects`, `emptyConfirms`
  and `probeMaxWaitSec`.
- `Count-Edges($obj)` is the ONLY rowcount path in the file, because `@($null).Count` is 1 and a null
  edge list would otherwise read as one row and classify an empty widget `filled`.
- `Get-WidgetOutcome($verdict, $rows, $budgetLeftMs, $outstandingComputes)` returns the four states.
- `Get-ExtractionCompleteness($outcomes, $plan, $budgetState)` returns the whole `meta` block.
- `Test-CeilingStillValid($probeResult, $minRun)` decides whether a probe result is admissible
  ceiling evidence.

Defaults are `-MaxWaitSec 90` and `-MaxTotalWaitSec 420`. Ninety seconds is about twenty-six times
the slowest measured resolve. The run figure bounds the worst case where every widget is cold: 43
widgets at about 3.5 seconds each is roughly 150 seconds, so 420 leaves margin while still failing in
minutes rather than hours. Both are parameters because these are judgement calls on one report's
evidence.

`Invoke-GQL`'s failure marker is `[pscustomobject]@{ __fetchFailed=$true; reason; attempts;
lastError }` — an object, never a JSON string, so a caller that forgets to branch faults loudly at
`ConvertFrom-Json` rather than parsing to nulls. Callers branch before `ConvertFrom-Json`: the widget
fetch ends `incomplete` reason `transport-failed`; the pagination loop applies S11; the trend probe
returns `unsettled`; the structure query throws a transport-shaped message.

The pagination loop at `:155-159` distinguishes a faulted page from a last page. On a marker, or on
any page whose `.data.widget.data` is absent while the previous page's `pageInfo.hasNextPage` was
`$true`, the widget ends `incomplete` with reason `partial-pages`, recording `pagesFetched` and
`endCursor`; rows already collected are still emitted. A failed page is retried under the same budget
as page 1. Without this, a fault on page 2 of 4 turns a loud abort into a silent 500-of-2000-row
truncation that the closer would certify as complete and the analyzer would total.

### Trend ceiling evidence

`Get-WidgetCeiling` currently treats an empty window as proof of overshoot and bisects on that signal,
so a slow but real window is indistinguishable from a genuine overshoot and the bisect converges too
low, silently truncating a client's history. The ledger's "a null or overshoot pull never clobbers a
good value" rule does not save the first pull for a new client.

`Probe-WidgetMonths` returns `[ordered]@{ state=<has-months|rejected|empty-resolved|unsettled>;
months=@(...) }`. It has three callers: `:315` and `:322` inside `Get-WidgetCeiling`'s ladder and
bisect, and `:437`, the cached-ceiling revalidation. `:437` reads `.months`, and treats `unsettled` as
"cache not validated", falling through to `Get-WidgetCeiling` rather than erroring — it has a safe
fallback the bisect does not.

Inside the ladder and bisect, `unsettled` is retried ONCE (`plan.retryUnsettledOnce`) before it is
believed, because the silent band was measured to be transient: a 37-month window that stayed silent
for 30 seconds returned `REJECTED` in 49 ms on the very next attempt. A window still `unsettled` after
that retry is treated as overshoot — the conservative direction, since claiming history you cannot
prove is the worse error — and the provider's coverage entry records `ceilingUncertain=$true` so the
artifact is honest that the ceiling is a lower bound rather than a measurement. A later run that does
get an answer extends it, because the ledger is the accumulating union of every window ever pulled.

This deliberately diverges from the review's must-fix 9, which asked for abort-on-`unsettled` inside
the ladder. Probes run after the review was launched showed 39 months staying silent across both a 30
second and a 90 second wait on a widget whose true ceiling is 36; aborting would have converted a
correct, working trend pull into a hard error. The retry-then-conservative rule keeps the pull working
while removing the false-ceiling risk the must-fix targeted.

`Get-TrendMonthCells` gains a distinct `windowStatus='unsettled'`, fed from the per-widget verdict, so
a budget-exhausted window is never recorded as `overshoot-empty` and contributes no cells.

### Files touched (estimate)

| File | Change |
|---|---|
| `skill/scripts/Get-SwydoReport.ps1` | the receive fix, reset seam, bounded connect, verdict wait, pure helpers, two parameters, meta block, pagination states, trend probe states, cache version |
| `skill/scripts/Analyze-SwydoReport.ps1` | propagate the verdict, emit `GAP_EXTRACTION_INCOMPLETE` |
| `skill/scripts/Test-ReportNumbers.ps1` | the `incomplete-extraction` violation in `Invoke-Closer` |
| `skill/scripts/ConvertTo-SwydoTrendFacts.ps1` | carry the three fields into its meta |
| `skill/scripts/Analyze-SwydoTrend.ps1` | copy them into its facts meta |
| `skill/scripts/Update-SwydoLedger.ps1` | refuse a merge when `extractionComplete` is `$false` |
| `skill/SKILL.md` | document the gate and the two flags |
| `Test-Extractor.ps1` | pure-helper cases, seam-driven state-machine cases, the timeout text scan |
| `Test-Analyze.ps1`, `Test-Closer.ps1` | propagation, the new gap, the new violation, absent-flag compat |
| `Test-TrendFacts.ps1`, `Test-Ledger.ps1`, `Test-TrendAnalyze.ps1` | the trend chain's carry and refusal |

`Fetch-Widget`'s call sites in their post-change form, given verbatim because the attempt-count slot
is removed and a leftover integer would silently bind to `$dr`:

```
:307   Fetch-Widget $w (New-RelDateRange (-1*$n) 'month') $null $script:fetchOpt
:423   Fetch-Widget $w (New-RelDateRange -12 'month')     $null $script:fetchOpt
:442   Fetch-Widget $w (New-RelDateRange (-1*$ceiling) 'month') $null $script:fetchOpt
:495   Fetch-Widget $w $null $null $script:fetchOpt
:504   (removed with the reconcile loop, per step 7)
```

The offline seam is verified, not assumed. Dot-sourcing with `-DefineOnly` loads the functions into
the caller's scope, and a later redefinition of `Invoke-GQL` in that scope is what `Fetch-Widget`
resolves at call time. A test-scope `function Start-Sleep` shadows the cmdlet, since PowerShell
resolves functions ahead of cmdlets. Both were confirmed on Windows PowerShell 5.1.22621.4249: a
stubbed run recorded exactly the expected five 900 ms sleeps in 102 ms of wall clock. Every helper
this spec adds is defined ABOVE the `-DefineOnly` return at `:365`, without which the completeness
and ceiling assertions would sit in unreachable run-body code and be green by absence.

### Alternatives rejected

- **Raise the attempt count and the sleep.** The smallest diff and it fixes nothing structural. The
  receive is broken, so more attempts still observe nothing, still cannot separate slow from refused,
  and still die on a transport fault.
- **Keep polling only and ignore the websocket.** Retained as the fallback arm in step 3, but as the
  primary mechanism it discards an exact answer Swydo already sends and replaces it with a heuristic
  that cannot tell `REJECTED` from slow.
- **Fire every widget, then harvest.** Materially faster because the computes pipeline. Rejected
  because the frame carries no widget identity, so with many in flight attribution collapses and the
  per-widget verdict, the strongest part of this design, is lost.
- **Correlate frames by recomputing the `dataRows:view` hash.** Rejected outright. The hash input is
  undocumented and unversioned, and a correlation that silently stopped matching would degrade to
  blind polling with nothing to signal it had.
- **Hard-fail the run on any empty widget.** Rejected by the owner on 2026-08-04. A zero-activity
  platform is a legitimate report, and `empty-resolved` is how this design tells that from a failure.

## 5. Production-readiness checklist

- **security** — no new egress and no new credential path. `meta.incompleteWidgets` carries widget ids
  the document already contains. The share key is still never printed and `Assert-NoCredential` is
  untouched.
- **perf / scale** — the warm path keeps its single query per widget at 108-224 ms. The cold path gets
  faster: a 1220-3418 ms verdict replaces a 4.5 second sleep ladder, a 44-260 ms refusal replaces it
  entirely on the trend ladder, and removing the reconcile loop stops ten genuinely empty widgets each
  burning three extra full budgets. The measured 1 m 38 s whole-report run should fall sharply.
- **a11y** — N/A. A command-line tool with no interface.
- **i18n** — N/A. Output is ASCII console text and machine-read JSON.
- **error / empty / loading states** — this unit is that work. The four-state outcome is the
  deliverable, and `empty-resolved` is the state the current code cannot express.
- **observability** — the per-widget console line gains its outcome and verdict; `meta.fetchBudget`
  records what the run spent, so a slow client is diagnosable from the artifact alone.
- **risks** — attribution is the largest: a verdict is matched to the outstanding request positionally,
  held closed by sequential fetching, the pre-fire drain, the forced reconnect after every unverdicted
  widget, and the `$outstandingComputes` guard, with AC16 pinning it. A reconnect loop is bounded by
  `maxReconnects`. Treating `rejected` as incomplete on the default path could newly block a report
  that previously published over a silently empty widget: the intended direction, but a behaviour
  change to watch on the first live runs.
- **testing + left-shift gates** — additive cases in six suites. Every confirmed defect gets a
  regression case: the orphaned receive, the deafened receiver after a fault, the stale verdict, the
  discarded verdict, the fatal transport fault, the pagination truncation, the false ceiling, the
  unbounded call sites, and absent-flag compatibility.
- **migration / rollback** — no document migration; the ceiling cache is versioned and re-derives once.
  Rollback is a single clean revert.
- **user docs** — `skill/SKILL.md` gains the completeness gate and the two flags.
- **accepted residual risks** — six, carried from the review rather than closed: AC13's byte-identical
  guarantee stays a manual live check; the run-body splice of the meta block is covered only by that
  live run plus a documented check; forcing a reconnect after every unverdicted widget costs one
  handshake each; the `kind:3` status enum is only partially mapped, so any unknown status is treated
  as no-verdict and blocks conservatively; the 1 MiB buffer and continuation fragments stay known
  limits; and no remote CI guards any of this, so the self-run bar is the only gate.

## 6. Acceptance criteria

- **AC1.** When a stubbed socket delivers a frame only after an earlier receive slice has timed out,
  `Ws-Recv` still returns that frame.
- **AC2.** When the wait receives `kind:3` `RESOLVED`, `Fetch-Widget` re-queries immediately rather
  than waiting out the poll interval.
- **AC3.** When the wait receives `kind:3` `REJECTED`, the wait ends at once and no further query is
  issued for that window.
- **AC4.** When the wait receives `kind:4`, it replies `kind:5` and keeps waiting, and the frame is
  not treated as a verdict.
- **AC5.** When a widget returns rows on the first query, the number of `Invoke-GQL` calls and the
  emitted widget object are identical to pre-change behaviour.
- **AC6.** When `Invoke-GQL` hits a transport fault with no HTTP response, the run continues and the
  widget is retried, instead of the process aborting with no JSON written.
- **AC7.** `Get-ExtractionCompleteness` over an outcome set containing an unverdicted widget returns
  `extractionComplete=$false` with that widget named and reason `budget-exhausted`.
- **AC8.** `Get-ExtractionCompleteness` over an outcome set of only `filled` and `empty-resolved`
  returns `$true`, with `incompleteWidgets` an `@()`-wrapped EMPTY array.
- **AC9.** When facts carry `extractionComplete: false`, `Invoke-Closer` returns an
  `incomplete-extraction` violation and the script exits non-zero without publishing.
- **AC10.** When facts carry no `extractionComplete` key, `Invoke-Closer` returns no such violation,
  proving pre-change artifacts still pass.
- **AC11.** When a trend probe window is refused, `Get-WidgetCeiling` records it as overshoot evidence;
  when a window is `unsettled` it is retried once, and a still-`unsettled` window yields a ceiling
  with `ceilingUncertain=$true` rather than an error. The cached-ceiling revalidation caller treats
  `unsettled` as "not validated" and falls through to a full probe.
- **AC12.** When the run budget is exhausted, remaining widgets end `incomplete` with reason
  `run-budget-exhausted` and the document is still written.
- **AC13.** When run live against the QCU share, every data widget ends `filled`,
  `meta.extractionComplete` is `$true`, and the widget payloads are byte-identical to the captured
  pre-change baseline apart from the new `meta` fields and timestamps.
- **AC14.** When a stubbed pending receive faults and a reconnect follows, the next `Ws-Recv` returns
  a live frame and `Connect-Ws` obtains a `socketId`.
- **AC15.** A reconnect mid-wait does not resurrect a pre-reconnect frame.
- **AC16.** When a stubbed socket delivers widget A's `RESOLVED` during widget B's wait, B ends
  `incomplete`, not `empty-resolved`, and `meta.extractionComplete` is `$false`.
- **AC17.** When `Invoke-GQL` succeeds on page 1 and returns the marker on page 2, the widget lands in
  `meta.incompleteWidgets` with reason `partial-pages` and `extractionComplete` is `$false`.
- **AC18.** With a stub that never emits `kind:2`, the widget ends `socket-lost` within the handshake
  bound rather than `budget-exhausted` at `MaxWaitSec`, and reconnect attempts equal `maxReconnects`.
- **AC19.** With `Invoke-GQL` stubbed to record `$vars`, `Fetch-Widget` invoked as the run body invokes
  it sends `sid`, `dr` and `cp` byte-identical to pre-change, and the effective budget at each call
  site equals the value `Get-FetchPlan` derived from `-MaxWaitSec`.
- **AC20.** A transport fault on the structure query still throws at startup with a transport-shaped
  message.
- **AC21.** A trend document with `extractionComplete:false` is refused by `Update-SwydoLedger.ps1`
  and, if analyzed, yields an `incomplete-extraction` violation from `Invoke-Closer`.
- **AC22.** A text scan of `Get-SwydoReport.ps1` finds no `Invoke-WebRequest` or `Invoke-RestMethod`
  call site lacking `-TimeoutSec`, and no `.Wait()` called with no argument.
- **AC23.** A leftover `kind:3` sitting in a stubbed receive queue is consumed by the pre-fire drain
  and is not accepted as the next widget's verdict.

## 7. Gates

`bash tools/run-gates.sh` must be green on every leg. `Test-Extractor.ps1`, `Test-Analyze.ps1`,
`Test-Closer.ps1`, `Test-TrendFacts.ps1`, `Test-Ledger.ps1` and `Test-TrendAnalyze.ps1` are additive
on their own assertion counts; every other suite's count is unchanged. `bash scripts/manifest-check.sh`
stays green and the manifest is re-stamped if this unit changes what it front-loads.
`python tools/gate-lint/ps-hygiene.py .` must stay green, which here means pure-ASCII sources and no
case-only variable collision among the new names. AC22 is a new gate leg inside `Test-Extractor.ps1`.
One documented check rather than a gate: the two run-body lines that splice the completeness block
into `$doc.meta` and `$tdoc.meta` are covered only by the live run.

## 8. Open questions

none - all five forks below were resolved by the owner, three of them before the build started and
two at the scope-approval gate. They are kept in place as the record of what was decided and why.

- **Fork 1, behaviour when a widget is still empty at the end of the budget.** RESOLVED (owner,
  2026-08-04): write the document, flag it in facts, and let the closer refuse to publish.
- **Fork 2, how much wall clock an extraction may spend.** RESOLVED (owner, 2026-08-04): configurable
  with a sane default. Realised as `-MaxWaitSec` and `-MaxTotalWaitSec`.
- **Fork 3, whether `REJECTED` on the default report path should block publish.** RESOLVED (owner,
  2026-08-04): block, treating it as `incomplete` with reason `rejected`. The default path asks for the report's own
  configured date range, so a refusal is a genuine fault, and the alternative is publishing over a
  silently missing widget.
- **Fork 4, whether `GAP_EXTRACTION_INCOMPLETE` should be `critical` or `major`.** RESOLVED (owner,
  2026-08-04): `critical`, because it means the input itself is untrustworthy rather than one number being
  unavailable. The closer violation in S15 blocks publish either way.
- **Fork 5, whether a persistently `unsettled` trend window should be conservative-overshoot or a hard
  error.** RESOLVED (owner, 2026-08-04, via the scope approval): conservative overshoot plus
  `ceilingUncertain`, per the measured silent band. A hard error would have failed a trend pull that today produces the right answer.

## 9. Revision log

- rev-1 · 2026-08-04 · initial draft, grounded on three live probes: warm-path timing, cold-path retry
  curve, and a frame capture that identified the `kind:3` signal.
- rev-2 · 2026-08-04 · two further probes overturned the rev-1 premise. A controlled A/B proved the
  shipped `Ws-Recv` loses every frame by abandoning its pending `ReceiveAsync`, promoting that to the
  enabling fix. Re-running the overshoot case with a correct receiver revealed `REJECTED`, replacing
  rev-1's quiescence heuristic with an exact discriminator. A black-hole listener showed
  `Invoke-WebRequest` has no default timeout, making the explicit `-TimeoutSec` load-bearing.
- rev-3 · 2026-08-04 · folded review `2026-08-04-review-aPatientHarvest-1` (51 findings, 27 confirmed,
  precision 0.53, verdict GO-WITH-CHANGES). All eleven must-fixes and should-fixes 1 and 2 are
  incorporated; should-fix 3 became a backlog row. Four closed silent-failure classes: stale-verdict
  mis-attribution, pagination truncation certified complete, a permanently deafened receiver after one
  socket fault, and the trend chain exempting itself from the gate via the absent-key rule. Also
  folded two probes run after the review launched, which measured a transient silent band and led to
  a deliberate divergence from must-fix 9, recorded in section 4.
- rev-4 · 2026-08-04 · owner ratified the full 19-item scope; forks 3, 4 and 5 resolved in place as
  block-on-REJECTED, `critical`, and conservative-overshoot. Status to INPROGRESS; build started.
- rev-5 · 2026-08-04 · built, plus three corrections that only LIVE verification could find. (a) The
  case-insensitivity trap in this repo's own manifest fired: `$script:maxTotalWaitSec` IS the
  `[int]$MaxTotalWaitSec` param at one scope, so initialising it to `$null` coerced the param to 0 and
  every widget started with an exhausted run budget. Renamed to `$script:runWaitCapSec`. (b) The
  `@($null).Count -eq 1` trap fired too: a null response reported one row, which would have classified
  an empty widget `filled`. All rowcounts now go through `Count-Edges`. (c) The stale-verdict class
  recurred live in a shape `$outstandingComputes` does not cover - a widget that ends WITH a verdict
  still leaves a compute from its own successful re-query, so the NEXT widget was reading that late
  frame and being marked `empty-resolved` despite having data. Closed by `emptyConfirms`: a
  resolved-but-empty result is believed only after one further quiet window yields no new verdict.
  Also added `probeMaxWaitSec` (10 s) after a live trend run spent 349 s of its 420 s budget waiting
  out the unsettled band at full per-widget budget; probes are cheap and expected to be refused.
- rev-6 · 2026-08-04 · landed on `main` as merge 3e5bd93; full bar green post-merge (17 of 17
  legs, 1064 assertions across the 8 suites). Status to CLOSED.

## 10. Reuse audit

No existing seam fits, and there is no automated reuse pass to cite: the codebase-map kit is not
adopted in this repo, so `tools/codebase-map/reuse_lookup.py` does not exist here. The seams were
identified by reading source. `Ws-Recv` at `skill/scripts/Get-SwydoReport.ps1:79` is the single
receive path for every websocket consumer in the file, so the S1 fix lands once and repairs
`Connect-Ws`, `Ws-Pulse` and the new wait together. `Fetch-Widget` at `:139-163` is the single choke
point every data pull passes through, with call sites at `:307`, `:423`, `:442`, `:495` and `:504`,
so the retry rework is not duplicated per caller. `Probe-WidgetMonths` at `:306-309` has three
callers — `:315` and `:322` inside `Get-WidgetCeiling`, and `:437`, the cached-ceiling revalidation —
and the two groups need different failure handling, which is why the accept decision is extracted
into `Test-CeilingStillValid` rather than inlined. `Invoke-Closer` at
`skill/scripts/Test-ReportNumbers.ps1:316-468` is the single place every violation is raised and is
already dot-source testable, so the completeness check reuses the existing violation contract.
`Update-SwydoLedger.ps1:186-187` already refuses a merge on `providerFilter`, so S16's refusal reuses
that shape rather than inventing a second one. The offline test seam reuses the established
`-DefineOnly` dot-source pattern all eight suites already use.
