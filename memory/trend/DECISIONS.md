# trend decisions — index

> One line per decision, append-only. Detail in decisions/.

- TREND-aGovernedCanon-1 · the U1..U5 master spec, which also carries the authoritative UNITS INDEX, moved into this tree at the 2026-08-04 readopt → [master spec + units index](builds/2026-07-07-TREND-aCanonicalClient/spec/2026-07-07-spec-aCanonicalClient-1.md)
- TREND-aGovernedCanon-2 · the units index stays the ledger for SHIPPED UNITS (`U<seq>` rows, Status SPEC -> shipped/DEFERRED). It is NOT the session ledger — that is `memory/project/in-flight/<tag>.md`. Two ledgers, two questions: what shipped, versus who is touching what right now.
- TREND-aGovernedCanon-3 · U7b is specced with U7a under analysis (the reconciliation rule family is analysis-side) even though it builds in `Analyze-SwydoTrend.ps1` → [U7a+U7b](../analysis/builds/2026-07-07-ANLZ-aCrossWidget/spec/2026-07-07-spec-aCrossWidget-1.md)
