# extraction backlog

> Mutable. Each row leads with one status token (OPEN…WONTDO).

- CLOSED - EXTR-aPatientHarvest-1 - extractor completeness under a slow Swydo backend: consume the discarded kind:3 RESOLVED signal, budget the fetch by wall clock, fail closed on an incomplete pull -> [spec](../builds/aPatientHarvest/spec/2026-08-04-spec-aPatientHarvest-1.md)
- OPEN - EXTR-aPatientHarvest-2 - batched widget fetch (fire all, then harvest): faster because server computes pipeline, but needs frame-to-widget attribution the kind:3 payload does not carry. Deferred from EXTR-aPatientHarvest-1 section 3.
- OPEN - EXTR-aPatientHarvest-3 - AGENTS.md:167 prescribes a singular `review/` Tier-2 artifact folder, but memory hygiene check 4 sanctions only `reviews/`. Following the playbook literally reds the memory-hygiene gate leg.
- CLOSED - EXTR-aStrictSchema-1 - Swydo schema drift fails fast instead of timing out: socketId off Widget.fields, 4xx bodies read from ErrorDetails, a validation error ends the run -> [spec](../builds/aStrictSchema/spec/2026-10-06-spec-aStrictSchema-1.md)
- OPEN - EXTR-aStrictSchema-2 - Fetch-Widget never inspects `errors` in a 4xx JSON body, so a non-validation error (e.g. 403 FORBIDDEN after a scope change) still waits out the widget budget. Needs a per-widget vs whole-query call before failing fast. Deferred from EXTR-aStrictSchema-1 section 3.
- OPEN - EXTR-aStrictSchema-3 - Invoke-GQL's 401 re-mint `continue` consumes a retry slot, so under -NoRetry (the structure query) a 401 re-mints and then fails without retrying. Predates EXTR-aStrictSchema-1 (review finding F4).
- OPEN - EXTR-aPatientHarvest-4 - memory/TEMPLATE-SPEC.md says a terminal spec needs section 8 "none or fully RESOLVED", but hygiene check 12 only accepts a first line starting none/N-A. Prose and checker disagree; same class as -3.
