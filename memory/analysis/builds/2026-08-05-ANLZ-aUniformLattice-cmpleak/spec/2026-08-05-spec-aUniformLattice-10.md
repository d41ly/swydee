# ANLZ-aUniformLattice-10 — close the compare-suppression leak in the discrepancy layer

**Status:** SPECCED · rev-1 · 2026-08-05 · node a · Tier-2 · base 6213a239

Found by the adversarial review of ORCH-aUniformLattice-3, which tried to document the claim
"`compareBasis='untrusted'` suppresses every comparative field" and discovered it is false.

## 1. Goal

When the previous-period baseline is not proven, NO previous-period number reaches the facts —
including through the cross-widget reconciliation layer, which today bypasses the gate entirely.

## 2. Scope (IN)

`skill/scripts/Analyze-SwydoReport.ps1`, the cross-widget reconciliation pass. Line 1369 builds
`$byMetric[$key].rows += @{ wid=$w.id; cur=$cell.current; prev=$cell.compare }` with no
`$script:compareUntrusted` guard, and the loop at :1373 iterates `foreach($per in 'cur','prev')`
emitting a discrepancy finding per period. Under `untrusted`, the `prev` arm publishes previous-period
values that EXTR-aUniformLattice-1 D5 declared unpublishable.

The fix is the guard the other three sites already carry:

```
prev=$(if($script:compareUntrusted){ $null } else { $cell.compare })
```

`$vals` at :1375 already drops `$null` and the loop already `continue`s when fewer than two values
survive, so a null `prev` makes the `prev` arm self-skip with no other change.

## 3. Non-goals (OUT)

NOT touching the three already-gated sites (:197, :974, :1106) — they are correct. NOT changing the
extractor, the closer, the matrix, or any behavior when `compareBasis` is `computed` or `unknown`.
NOT changing what `unknown` means: the gate at :1025 is an exact `-eq 'untrusted'` and that stays,
because `unknown` marks a pre-contract extraction whose compare column was never claimed to be
proven-or-suppressed, and silently suppressing it would rewrite old artifacts' meaning.

## 4. Design

One guarded assignment at :1369, matching the house pattern of the other three sites including the
`# EXTR-aUniformLattice-1 D5` provenance comment style, extended with this unit's id.

Why the guard belongs at the COLLECTION site rather than the emit site: `$byMetric` is consumed by
one loop that treats `cur` and `prev` symmetrically, so gating at collection keeps the symmetry
intact and leaves exactly one place where a future period could be added without re-deriving the
rule. Gating at the emit site would need a second condition inside a loop whose whole shape is
period-agnostic.

**No version marker moves.** Under `computed` and `unknown` — every artifact anyone has — output is
byte-identical, because the guard only fires when `compareUntrusted` is true. This is a
BUG FIX inside an existing disclosed contract, not a new disclosed change, so it does not consume
the SIXTH slot in the kickoff manifest's waiver ledger. ANLZ-aUniformLattice-9 keeps that slot.

## 5. Production-readiness checklist

- **Security:** none — no I/O, no network, no credential surface.
- **Perf:** one boolean test per metric per widget; unmeasurable.
- **Error/empty states:** a null `prev` is already the normal shape for a no-comparison report and
  is already handled by the `$vals` filter and the `-lt 2` continue at :1375-1376.
- **Observability:** the existing `compareBasis=untrusted -> comparisons suppressed` line at :1026
  already announces the mode; with this fix that message becomes true rather than aspirational.
- **Testing:** see §6. The regression test is the point of the unit — the class is "a comparative
  value reaching facts under untrusted", and it was ungated for as long as nobody tested it.
- **Migration/rollback:** single-line revert, no persisted state, no schema change.
- **Docs:** none of its own. ORCH-aUniformLattice-3 documents the resulting contract and depends on
  this landing first, or its central claim is false.
- **a11y / i18n:** N/A — JSON producer, no UI.

## 6. Acceptance criteria

1. With `meta.compareBasis='untrusted'` and a fixture whose two widgets disagree on a metric's
   PREVIOUS value but agree on the current one, zero discrepancy findings are emitted.
2. The same fixture with `compareBasis='computed'` still emits the previous-period discrepancy —
   proving the fix suppresses rather than deletes the rule.
3. With `untrusted`, a fixture whose widgets disagree on the CURRENT value still emits its
   discrepancy — the `cur` arm is untouched.
4. `compareBasis='unknown'` behaves exactly as `computed` (no suppression), pinning the deliberate
   asymmetry in §3 so a later reader does not "fix" it.
5. No facts field changes under `computed`: `factsVersion` stays 3, `canonicalVersion` 4,
   `matrixVersion` 2.
6. A structural assertion that every read of `.compare` outside the three gated sites and this one
   is accounted for — a source scan pinning the count, so a fifth ungated read cannot appear
   silently. This is the left-shift: the defect existed because nothing counted these.

## 7. Gates

Full bar. `Test-Analyze.ps1` is the owning suite and grows by the AC1–AC6 assertions; the other
seven suite counts stay unchanged.

## 8. Open questions

- AC6's structural scan pins a count of `.compare` reads. A count-pin is brittle against innocent
  refactors and will red on a rename that changes nothing. The alternative — asserting each read
  site is within N lines of a `compareUntrusted` guard — is less brittle but also less honest,
  because proximity is not a guard. This spec takes the count-pin and accepts the false positives,
  on the grounds that a red gate asking "is this new read gated?" is the cheapest possible version
  of this bug not recurring. Worth challenging.

## 9. Revision log

- rev-1 · 2026-08-05 · initial spec. Cause traced during the ORCH-aUniformLattice-3 spec review:
  the doc claim "suppresses EVERY comparative field, at three sites" was verified against the code
  and found false, with the fourth read at :1369 ungated since the reconciliation pass was written.

## 10. Reuse audit

Nothing new is built. `$script:compareUntrusted` (:1025) is the existing gate variable and this adds
its fourth consumer, matching the exact expression shape used at :197, :974 and :1106. No new
function, no new parameter, no new config. AC6's scan reuses the source-reading idiom already used
by `Test-Extractor.ps1` and `Test-Analyze.ps1` to assert structural properties of the scripts
(`Get-Content ... -Raw` plus a regex count), rather than introducing a new lint tool.
