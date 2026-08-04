# extraction decisions — index

> One line per decision, append-only. Detail in decisions/.

- EXTR-aGovernedCanon-1 · extraction's ratified spec corpus moved out of `docs/specs/` into this tree at the 2026-08-04 governance readopt; the record itself is unchanged → [U8 period resolution](builds/2026-07-13-EXTR-aRelativePeriod/spec/2026-07-13-spec-aRelativePeriod-1.md)
- EXTR-aGovernedCanon-2 · unit ids `U<seq>[a|b]` are a FROZEN legacy era: cite them verbatim, never renumber them, and never mint a new one. New extraction decisions take `EXTR-<slug>-<seq>`. The two id spaces cannot collide, so both stay readable.
