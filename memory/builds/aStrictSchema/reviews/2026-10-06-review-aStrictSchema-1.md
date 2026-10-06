# EXTR-aStrictSchema-1 review - adversarial review of the schema-drift fail-fast spec and diff

**Status:** CLOSED - rev-1 - 2026-10-06 - node a - Tier-2 - base b5f06bca

## 1. What ran

Three primed finder lenses over the rev-1 spec and the diff against `b5f06bca`, run as
independent subagents: correctness and error paths, test validity, and integration seams with doc
accuracy. The orchestrator acted as the skeptic, re-checking each finding against the source before
accepting it. The test lens mutation-tested the new section by breaking the fix eight ways on a
scratch copy.

| Metric | Value |
|---|---|
| Agents | 3 finders; the orchestrator was the skeptic and synthesis pass |
| Raw findings | 14 |
| Confirmed | 11 |
| Refuted or deferred | 3 |
| Precision | 0.79 |

A small, hardened diff justified three lenses rather than six (`AGENTS.md` section 8, match
intensity to target richness).

## 2. Verdict

Ship after fold-in. The fix is correct for the incident. One regression was introduced by the
rev-1 design and is fixed in rev-2: any non-2xx body was returned as data, so an HTML 502 would
have ended the run through `Fetch-Widget`'s unguarded `ConvertFrom-Json`.

## 3. Findings

| Id | Lens | Finding | Disposition |
|---|---|---|---|
| F1 | correctness, integration | A non-JSON or 5xx/429 body returned as data makes `Fetch-Widget` throw "Invalid JSON primitive" and ends the run; before, it read `''` and only waited. | CONFIRMED. Fixed: only a JSON 4xx other than 429 is data. AC8 added. |
| F2 | correctness | A validation body whose `errors` is null yields `@('')`, defeating the fallback message. | CONFIRMED. Empty messages filtered; fallback is up to 300 chars of the body. Tested. |
| F3 | correctness | `GRAPHQL_VALIDATION_FAILED` on HTTP 200 is not detected. | DEFERRED. Verified live as 400; recorded as a spec non-goal. |
| F4 | correctness | The 401 re-mint consumes a retry slot, so `-NoRetry` never retries after it. | DEFERRED. Predates this unit; backlog EXTR-aStrictSchema-3. |
| T1 | tests | The AC2 fixture's `message` contained the `originalMessage` text, so a mutation using `message` survived. | CONFIRMED. The fixtures now differ, plus an assertion that the prefixed message is not used. |
| T2 | tests | The child-scope block isolates functions only; `$script:` state leaks out. | CONFIRMED. Comment corrected; harmless while it is the last section. |
| T3 | tests | No `Invoke-GQL` case for a body present only in the stream. | CONFIRMED. Added. |
| T4 | tests, integration | The spec claimed a non-validation 4xx no longer waits; `Fetch-Widget` still waits out the budget. | CONFIRMED. Claim corrected; backlog EXTR-aStrictSchema-2. |
| T5 | tests | Empty 4xx then data, and multi-message de-duplication, untested. | CONFIRMED for empty-4xx recovery (added). De-duplication left untested as cosmetic. |
| I3 | integration | `SWYDO_REPORT_EXTRACTION_SPEC.md` still listed `socketId:ID!` as a `fields` argument. | CONFIRMED. Fixed, with the type claim marked UNVERIFIED. |
| I4 | integration | The probe comment said status is the reliable signal; the verdict needs the body. | CONFIRMED. Comment rewritten. |
| I5 | integration | The spec overstated a 2026-08-05 observation and a probe workaround. | CONFIRMED. Root-cause text corrected. |
| I6 | integration | The S7 manifest and DECISIONS items were not yet in the diff. | CONFIRMED. Delivered in this unit. |
| T6 | tests | The fake error models only the ErrorDetails-populated shape. | REFUTED as a defect: the stream fallback is now exercised through `Invoke-GQL` (T3). |

## 4. Checks that came back clean

ps-hygiene over all `.ps1` files is clean. AC22 and the V5 query pins are unaffected. AC7 is not
flaky; with the throw removed it took 30 s and failed. The thrown message cannot carry the share
key or JWT. No other doc outside frozen specs and reviews quotes the old query.
