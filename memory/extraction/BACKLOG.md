# extraction backlog

> Mutable. Each row leads with one status token (OPEN…WONTDO).

- SPECCED - EXTR-aPatientHarvest-1 - extractor completeness under a slow Swydo backend: consume the discarded kind:3 RESOLVED signal, budget the fetch by wall clock, fail closed on an incomplete pull -> [spec](builds/2026-08-04-EXTR-aPatientHarvest/spec/2026-08-04-spec-aPatientHarvest-1.md)
- OPEN - EXTR-aPatientHarvest-2 - batched widget fetch (fire all, then harvest): faster because server computes pipeline, but needs frame-to-widget attribution the kind:3 payload does not carry. Deferred from EXTR-aPatientHarvest-1 section 3.
- OPEN - EXTR-aPatientHarvest-3 - AGENTS.md:167 prescribes a singular `review/` Tier-2 artifact folder, but memory hygiene check 4 sanctions only `reviews/`. Following the playbook literally reds the memory-hygiene gate leg.
