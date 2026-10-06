# EXTR-aStrictSchema-1 — Swydo schema drift fails fast instead of timing out

**Status:** INPROGRESS · rev-2 · 2026-10-06 · node a · Tier-2 · base b5f06bca · streams extraction · review 2026-10-06-review-aStrictSchema-1 · ratified 2026-10-06

## 1. Goal

On 2026-10-06 Swydo stopped accepting the `socketId` argument on `Widget.fields`, and every
extraction of a fully populated report came back with all data widgets `incomplete
(budget-exhausted)`. This unit restores extraction against the current schema, and makes the next
schema change fail in seconds with Swydo's own message instead of spending the whole wait budget.

## 2. Scope (IN)

- S1. Drop `socketId:$sid` from both `Widget.fields` selections in `$script:baseQ`
  (`skill/scripts/Get-SwydoReport.ps1`), keeping it on `data(...)`, which still requires it.
- S2. Apply the same change to the two `-ProbeFields` candidates in `Get-FieldProbeCandidates`, and
  set their `vars` to `none` so the probe no longer declares an unused `$sid`.
- S3. Add `Get-HttpErrorBody`: read a non-2xx body from the caught ErrorRecord's
  `ErrorDetails.Message`, falling back to the response stream. It returns `''` and never throws.
- S4. `Invoke-GQL`: read non-2xx bodies through `Get-HttpErrorBody`. A body carrying
  `GRAPHQL_VALIDATION_FAILED` throws a run-terminating error naming Swydo's `originalMessage`(s).
  A JSON body on a 4xx other than 429 is still returned as data. Everything else is a retryable
  fault that ends as `New-FetchFailure` (or a throw under `-NoRetry`): an empty body on a 200 or a
  non-2xx, a 5xx, a 429, and any non-JSON body such as a gateway's HTML page.
- S5. `Invoke-ProbeRequest` reads its non-2xx body through `Get-HttpErrorBody` too.
- S6. Regression tests in `tests/Test-Extractor.ps1` covering S1-S5 (AC1-AC8).
- S7. Docs: `SWYDO_REPORT_EXTRACTION_SPEC.md` (query text, the `fields` argument list and the
  PS 5.1 body note), `skill/SKILL.md` (what the new error means and what to do), the kickoff
  manifest trap list, a `memory/DECISIONS.md` line, and `memory/backlog/EXTR.md` rows.

## 3. Non-goals (OUT)

- No change to the facts schema, the analyzer, the closer, or any report-surface output.
- No automatic schema discovery or self-healing query rewrite. Introspection is disabled on
  Swydo's Apollo server (verified 2026-10-06), so there is nothing to discover from.
- No rewrite of the ratified `memory/builds/aUniformLattice/spec/2026-08-04-spec-aUniformLattice-2.md`,
  which quotes the old probe selections. It was correct when ratified and stays a frozen record.
- No change to the websocket verdict logic (EXTR-aPatientHarvest-1) or the period logic
  (EXTR-aUniformLattice-1).
- `Fetch-Widget` still does not inspect `errors` in a 4xx JSON body, so a non-validation error
  (for example a 403 `FORBIDDEN` scope rejection) still waits out the widget budget. Ending the run
  on it would be wrong if the error is per-widget, so it is follow-up EXTR-aStrictSchema-2.
- A `GRAPHQL_VALIDATION_FAILED` delivered with HTTP 200 is not detected. Swydo answered 400 when
  verified live on 2026-10-06.
- The 401 re-mint consuming a retry slot predates this unit; follow-up EXTR-aStrictSchema-3.

## 4. Design

### Root cause

Two defects compounded. The query sent `fields(socketId:$sid,...)`, which Swydo now rejects with
HTTP 400 `GRAPHQL_VALIDATION_FAILED: Unknown argument "socketId" on field "Widget.fields"`. A
validation error fails the whole operation, so even TEXT widgets came back null. Then `Invoke-GQL`
read the 4xx body from `Response.GetResponseStream()`, which Windows PowerShell 5.1 has already
drained, and returned `''`. `ConvertFrom-Json` turned that into `$null`, `Count-Edges` read zero
rows, and `Fetch-Widget` kept waiting for a websocket verdict that could never arrive. The comment
above `Invoke-ProbeRequest` already stated that this read comes back empty, undated. The probe read
the same drained stream (with a seek to 0), so it was affected too: every absent field it probed
came back `unknown` rather than absent.

### Inventory

| Site | Before | After |
|---|---|---|
| `$script:baseQ` metrics/dims | `fields(socketId:$sid,type:...)` | `fields(type:...)` |
| `Get-FieldProbeCandidates` rows 1 and 5 | `vars='sid'`, `fields(socketId:$sid,...)` | `vars='none'`, `fields(type:...)` |
| `Invoke-GQL` non-2xx path | stream read, `''` on PS 5.1 | `Get-HttpErrorBody`; validation throws; JSON 4xx is data; rest is a fault |
| `Invoke-GQL` 200 path | `.Content` returned as-is, `''` included | empty `.Content` is a retryable fault |
| `Invoke-ProbeRequest` non-2xx path | stream read | `Get-HttpErrorBody` |

### Why throw rather than return a failure

A validation failure is a contract break between this code and Swydo. Retrying cannot change the
answer, and recording it per widget would emit 40-odd identical `incomplete` rows plus a critical
gap. One terminating error with Swydo's message is the most diagnosable outcome. No production
caller wraps `Invoke-GQL` or `Fetch-Widget` in a catch (verified by grep; the catch around
`Invoke-FieldProbe` covers `Invoke-ProbeRequest`, which does not throw on validation). The throw
therefore ends the run. `Sync-SwydoTrend.ps1` maps the failed child to exit 1, which SKILL.md step 8
already treats as "trend history not updated", and the ceilings cache is written only after a
complete trend pass, so it survives intact. Trend ceiling probes cannot trip the throw: an
out-of-range window is signalled by the websocket `REJECTED` verdict, not by a GraphQL error.

### Why only a JSON 4xx is data

Before this unit, every non-2xx body reached callers as `''` under PS 5.1, so a transient 502 or
429 cost a wait and nothing more. Returning such a body as data would hand an HTML page to
`Fetch-Widget`, whose `ConvertFrom-Json` would throw "Invalid JSON primitive" and end the run (review
finding F1). So a 5xx, a 429 and any non-JSON body now take the retry path, and the failure text
names the status without echoing the upstream page. A 4xx JSON body parses to an `errors`-only
document. `Count-Edges` reads zero rows from it, which is the same outcome the old empty read
produced, so callers see no new shape.

### Files touched (estimate)

`skill/scripts/Get-SwydoReport.ps1`, `tests/Test-Extractor.ps1`, `SWYDO_REPORT_EXTRACTION_SPEC.md`,
`skill/SKILL.md`, `.claude/SESSION-KICKOFF.md`, `memory/DECISIONS.md`, `memory/backlog/EXTR.md`,
this build folder.

### Alternatives rejected

- Switch the request to `HttpClient`, which exposes status and body on every response. Rejected:
  it touches the auth and timeout plumbing that AC22 pins, for no gain over reading ErrorDetails.
- Classify a validation failure as a per-widget `incomplete` with a new reason. Rejected: the
  report fails closed either way, but the user would still have to dig the message out of the facts.
- Also end the run on a 403 `FORBIDDEN`. Rejected for this unit: unverified whether Swydo ever
  sends it for one widget's data source rather than for the query, and a whole-run abort over one
  widget would be a regression. Deferred to EXTR-aStrictSchema-2.

## 5. Production-readiness checklist

- security: the thrown message carries Swydo's `originalMessage` text, or at most 300 characters of
  a validation body that would not parse. Neither holds the share key or JWT: the JWT travels in a
  header and the share key goes to a different host. A non-JSON upstream page is never echoed.
- perf / scale: N/A — removes waiting; adds no calls.
- a11y: N/A — no UI.
- i18n: N/A — the matched token `GRAPHQL_VALIDATION_FAILED` is an Apollo error code, not prose.
- error / empty / loading states: the subject of this unit (S4).
- observability: the terminating error names the HTTP status and Swydo's message; a retryable
  fault's `lastError` names the status and whether the body was empty or non-JSON.
- risks: a non-validation 4xx JSON body still waits out the widget budget (section 3, follow-up
  EXTR-aStrictSchema-2). A transient 5xx or 429 now retries three times inside `Invoke-GQL`, as an
  empty-bodied one did before.
- testing + left-shift gates: AC1-AC8 in `Test-Extractor.ps1`; AC1 pins the query text so the
  same drift cannot return silently. Each assertion was checked to fail against the base code or a
  targeted mutation (review section 1).
- migration / rollback: none — revert the merge commit.
- user docs: `skill/SKILL.md` Notes gains the error and its meaning (S7).

## 6. Acceptance criteria

- AC1. When the extractor source is scanned, no `fields(socketId` remains, both field lists are
  still requested, and every probe candidate declares `$sid` exactly when its selection uses it.
- AC2. When `Invoke-GQL` receives a 400 whose body carries `GRAPHQL_VALIDATION_FAILED`, it throws
  on the first call with Swydo's `originalMessage` in preference to the prefixed `message`, with or
  without `-NoRetry`. An unparseable validation body still reaches the message.
- AC3. When it receives a 4xx JSON body with any other error, it returns that body without retrying.
- AC4. When the body is empty, on a 4xx or a 200, it retries and then returns a fetch failure
  naming the status (or throws under `-NoRetry`), and a later good response still recovers. A body
  present only in the response stream is still read.
- AC5. `Get-HttpErrorBody` prefers ErrorDetails, falls back to the stream, and returns `''` for
  null inputs without throwing.
- AC6. `Invoke-ProbeRequest` reads the 400 body, and `Get-FieldProbeVerdict` then classifies the
  field as absent rather than unknown.
- AC7. When `Fetch-Widget` hits a validation failure, it throws in under 5 s against a 30 s
  widget budget.
- AC8. When the response is a 5xx, a 429 or a non-JSON page, `Invoke-GQL` retries it as a
  transport fault, never returns it as data, and does not echo the page in the failure text.
- AC9. A live extraction of the QCU report fills every data widget and passes the period probe.
  Verified 2026-10-06: 43 data widgets filled, `period probe OK`.

## 7. Gates

The full bar via `bash tools/run-gates.sh`. `Test-Extractor` moves from 327 to 365 (+38); every
other suite's count is unchanged. The manifest ratchet needs a re-stamp, because `skill` and
`tests` are watched paths.

## 8. Open questions

none

## 9. Revision log

- rev-1 · 2026-10-06 · initial draft. The S1 and S4 code was prototyped live during the incident
  diagnosis, before this spec existed; the review covers the spec and that diff together.
- rev-2 · 2026-10-06 · folded review 2026-10-06-review-aStrictSchema-1: only a JSON 4xx is data
  (F1, new AC8); originalMessage pinned and empty messages filtered (F2, T1); stream-only body and
  empty-4xx recovery tested (T3, T5); the section 5 risk claim corrected and FORBIDDEN deferred
  (T4, I2); root-cause wording corrected (I5); stale `fields` argument docs fixed (I3); probe
  comment corrected (I4); owner approval recorded (fix requested in chat, 2026-10-06).

## 10. Reuse audit

none — codebase-map not adopted; seam identified by reading
`skill/scripts/Get-SwydoReport.ps1:121` (`Invoke-GQL`) and `skill/scripts/Get-SwydoReport.ps1`
`Invoke-ProbeRequest`. `Get-HttpErrorBody` is the shared seam both now go through.
