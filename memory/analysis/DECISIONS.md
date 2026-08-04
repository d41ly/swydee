# analysis decisions — index

> One line per decision, append-only. Detail in decisions/.

- ANLZ-aGovernedCanon-1 · analysis owns four ratified specs, moved into this tree at the 2026-08-04 readopt → [U6 canonical total](builds/2026-07-07-ANLZ-aCanonicalTotal/spec/2026-07-07-spec-aCanonicalTotal-1.md)
- ANLZ-aGovernedCanon-2 · the rest → [U7a+U7b reconciliation](builds/2026-07-07-ANLZ-aCrossWidget/spec/2026-07-07-spec-aCrossWidget-1.md)
- ANLZ-aGovernedCanon-4 · and the later pair → [U9 headline rank](builds/2026-07-13-ANLZ-aHeadlineRank/spec/2026-07-13-spec-aHeadlineRank-1.md) · [U10 data-gap rules](builds/2026-07-13-ANLZ-aGappedRanking/spec/2026-07-13-spec-aGappedRanking-1.md)
- ANLZ-aGovernedCanon-3 · the default single-report output stays byte-for-byte unchanged and every change is additive-in-facts. Sole exception: the reviewed, disclosed U9 flip-set waiver, which bumps `meta.canonicalVersion` 1->2 and discloses each flipped cell in-facts.
- ANLZ-aUniformLattice-1 · a uniform per-platform metric matrix is a five-phase program: it needs extractor identity and completeness keys that are fetched today then discarded → [layered uniform view](builds/2026-08-04-ANLZ-aUniformLattice/spec/2026-08-04-spec-aUniformLattice-1.md)
- ANLZ-aUniformLattice-2 - P1 emits the identity and completeness keys the extractor already fetched and discarded; strictly additive, schemaVersion 3 -> [P1 spec](builds/2026-08-04-ANLZ-aUniformLattice/spec/2026-08-04-spec-aUniformLattice-2.md)
- ANLZ-aUniformLattice-7 - an UNFILTERED report emitted a false force-surfaced PROVIDER_FILTERED major; a returned-empty-array collapses to $null, serializes as {} and reads as one filter entry -> [P1 spec](builds/2026-08-04-ANLZ-aUniformLattice/spec/2026-08-04-spec-aUniformLattice-2.md)
- ANLZ-aUniformLattice-3 - P2 declares one aggregation class per metric and makes the basis hash single-source; four cited vetoes correct measured misclassifications -> [P2 spec](builds/2026-08-04-ANLZ-aUniformLattice/spec/2026-08-04-spec-aUniformLattice-3.md)
- ANLZ-aUniformLattice-4 - P3 emits platforms[].metrics, a TOTAL map over every observed (platform, metric) pair, as a dark sibling of an untouched headline -> [P3 spec](builds/2026-08-04-ANLZ-aUniformLattice/spec/2026-08-04-spec-aUniformLattice-4.md)
