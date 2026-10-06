# Decision index — swydee

One line per ratified decision, append-only across every family. Supersede with a new id and
a note; never rewrite a row. Detail lives under `builds/<slug>/`.

## extraction

- EXTR-aGovernedCanon-1 · extraction's ratified spec corpus moved out of `docs/specs/` into this tree at the 2026-08-04 governance readopt; the record itself is unchanged → [U8 period resolution](builds/aRelativePeriod/spec/2026-07-13-spec-aRelativePeriod-1.md)
- EXTR-aGovernedCanon-2 · unit ids `U<seq>[a|b]` are a FROZEN legacy era: cite them verbatim, never renumber them, and never mint a new one. New extraction decisions take `EXTR-<slug>-<seq>`. The two id spaces cannot collide, so both stay readable.
- EXTR-aPatientHarvest-1 · Ws-Recv abandoned its pending ReceiveAsync on a timed-out slice, so the extractor never saw Swydo's kind:3 RESOLVED/REJECTED verdict and blind-slept instead → [spec](builds/aPatientHarvest/spec/2026-08-04-spec-aPatientHarvest-1.md)
- EXTR-aStrictSchema-1 - Swydo dropped socketId from Widget.fields; PS 5.1 hid the 400 so every widget timed out. Query fixed; a validation error now ends the run with Swydo's message -> [spec](builds/aStrictSchema/spec/2026-10-06-spec-aStrictSchema-1.md)
- EXTR-aUniformLattice-1 - the previous-period column came from the dashboard's saved compare selector, unrecorded and volatile; the extractor now computes, passes and records the window -> [proven periods](builds/aUniformLattice/spec/2026-08-05-spec-EXTR-aUniformLattice-1.md)

## analysis

- ANLZ-aGovernedCanon-1 · analysis owns four ratified specs, moved into this tree at the 2026-08-04 readopt → [U6 canonical total](builds/aCanonicalTotal/spec/2026-07-07-spec-aCanonicalTotal-1.md)
- ANLZ-aGovernedCanon-2 · the rest → [U7a+U7b reconciliation](builds/aCrossWidget/spec/2026-07-07-spec-aCrossWidget-1.md)
- ANLZ-aGovernedCanon-4 · and the later pair → [U9 headline rank](builds/aHeadlineRank/spec/2026-07-13-spec-aHeadlineRank-1.md) · [U10 data-gap rules](builds/aGappedRanking/spec/2026-07-13-spec-aGappedRanking-1.md)
- ANLZ-aGovernedCanon-3 · the default single-report output stays byte-for-byte unchanged and every change is additive-in-facts. Sole exception: the reviewed, disclosed U9 flip-set waiver, which bumps `meta.canonicalVersion` 1->2 and discloses each flipped cell in-facts.
- ANLZ-aUniformLattice-1 · a uniform per-platform metric matrix is a five-phase program: it needs extractor identity and completeness keys that are fetched today then discarded → [layered uniform view](builds/aUniformLattice/spec/2026-08-04-spec-aUniformLattice-1.md)
- ANLZ-aUniformLattice-2 - P1 emits the identity and completeness keys the extractor already fetched and discarded; strictly additive, schemaVersion 3 -> [P1 spec](builds/aUniformLattice/spec/2026-08-04-spec-aUniformLattice-2.md)
- ANLZ-aUniformLattice-7 - an UNFILTERED report emitted a false force-surfaced PROVIDER_FILTERED major; a returned-empty-array collapses to $null, serializes as {} and reads as one filter entry -> [P1 spec](builds/aUniformLattice/spec/2026-08-04-spec-aUniformLattice-2.md)
- ANLZ-aUniformLattice-3 - P2 declares one aggregation class per metric and makes the basis hash single-source; four cited vetoes correct measured misclassifications -> [P2 spec](builds/aUniformLattice/spec/2026-08-04-spec-aUniformLattice-3.md)
- ANLZ-aUniformLattice-4 - P3 emits platforms[].metrics, a TOTAL map over every observed (platform, metric) pair, as a dark sibling of an untouched headline -> [P3 spec](builds/aUniformLattice/spec/2026-08-04-spec-aUniformLattice-4.md)
- ANLZ-aUniformLattice-5 - P4 makes the per-row layer addressable via P1's cellKey; reading by display name would have published a wrong number under the right id -> [P4 spec](builds/aUniformLattice/spec/2026-08-04-spec-aUniformLattice-5.md)
- ANLZ-aUniformLattice-6 - P5 gives GAP_NO_ACCOUNT_TOTAL the matrix's real per-metric reason while keeping membership headline-keyed; repointing membership was disproved in both directions -> [P5 spec](builds/aUniformLattice/spec/2026-08-04-spec-aUniformLattice-6.md)
- ANLZ-aUniformLattice-8 - valuesById duplicated every breakdown cell for 41% of the facts document and was read by nothing; it is now collisions-only -> [lean facts](builds/aUniformLattice/spec/2026-08-05-spec-aUniformLattice-8.md)
- ANLZ-aCandidTally-1 - every rule SELECTS a metric by id then READS its cell by display name; the two agree only when the id-selected metric is the first holder of that name -> [cell-key identity](builds/aCandidTally/spec/2026-08-05-spec-aCandidTally-1.md)
- ANLZ-aCandidTally-2 - a key-resolution change under an unchanged reduce moves the version marker of EVERY layer whose published values it changes; today that rule exists only as an inference from two negative statements
- ANLZ-aUniformLattice-9 · row findings name their cut and disclose their denominator against the computed platform total; no dedup rung → [detail](builds/aUniformLattice/spec/2026-08-05-spec-ANLZ-aUniformLattice-9.md)
- ANLZ-aUniformLattice-10 · the cross-widget discrepancy layer obeys the compare-suppression gate; it was the fourth `.compare` read and the only ungated one → [detail](builds/aUniformLattice/spec/2026-08-05-spec-ANLZ-aUniformLattice-10.md)

## trend

- TREND-aGovernedCanon-1 · the U1..U5 master spec, which also carries the authoritative UNITS INDEX, moved into this tree at the 2026-08-04 readopt → [master spec + units index](builds/aCanonicalClient/spec/2026-07-07-spec-aCanonicalClient-1.md)
- TREND-aGovernedCanon-2 · the units index stays the ledger for SHIPPED UNITS (`U<seq>` rows, Status SPEC -> shipped/DEFERRED). It is NOT the session ledger — that is `memory/project/in-flight/<tag>.md`. Two ledgers, two questions: what shipped, versus who is touching what right now.
- TREND-aGovernedCanon-3 · U7b is specced with U7a under analysis (the reconciliation rule family is analysis-side) even though it builds in `Analyze-SwydoTrend.ps1` → [U7a+U7b](builds/aCrossWidget/spec/2026-07-07-spec-aCrossWidget-1.md)

## orchestration

- ORCH-aGovernedCanon-1 · the report surface and its voice live in `skill/SKILL.md` + `skill/report-template.md`, which are also swydee's user-facing help. A user-facing change is not done until both reflect it.
- ORCH-aGovernedCanon-2 · client annotations render under an explicit "Context (unverified, client-supplied)" block and are cited ONLY as temporal co-occurrence, never as cause → [U3](builds/aCanonicalClient/spec/2026-07-07-spec-aCanonicalClient-1.md)
- ORCH-aUniformLattice-1 · the eight `Test-*.ps1` suites moved to `tests/`, `Run-Gates.ps1` to `tools/`; the three root spec docs stayed — ratified records cite them and the log is append-only → [detail](builds/aUniformLattice/spec/2026-08-05-spec-ORCH-aUniformLattice-1.md)
- ORCH-aUniformLattice-2 · SKILL.md documents all 59 parameters of the eight tools; a reverse check caught `-Platform` documented on a script that refuses one → [detail](builds/aUniformLattice/spec/2026-08-05-spec-ORCH-aUniformLattice-2.md)
- ORCH-aUniformLattice-3 · SKILL.md states the comparison contract: computed/untrusted/unknown, one payload, never inherited from the dashboard → [detail](builds/aUniformLattice/spec/2026-08-05-spec-ORCH-aUniformLattice-3.md)
- ORCH-aFlattenedLedger-1 · the memory tree flattened to memory-tree kit 2.2 and the authored in-flight ledger retired; work state is GENERATED now, never authored → [detail](builds/aFlattenedLedger/spec/2026-08-09-spec-aFlattenedLedger-1.md)
- ORCH-aFlattenedLedger-2 · supersedes TREND-aGovernedCanon-2's session-ledger half ONLY; its units-index half stands. Who-is-touching-what is the generated `LIVE.md`; the retired shard is preserved at [archive/ledger/a.md](archive/ledger/a.md).
- ORCH-aFlattenedLedger-3 · `kit-dogfood-parity.test.sh --render` is NEVER run here: it writes live → shipped, overwriting installed kit templates then reporting green → [review](builds/aFlattenedLedger/reviews/2026-08-10-review-aFlattenedLedger-1.md)
