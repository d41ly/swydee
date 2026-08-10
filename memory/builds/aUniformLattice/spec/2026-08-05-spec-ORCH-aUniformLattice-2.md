# ORCH-aUniformLattice-2 — SKILL.md gets a parameters reference

**Status:** CLOSED · rev-2 · 2026-08-05 · node a · Tier-1 · base 6213a239

## Goal

An agent reading `SKILL.md` can discover every flag the eight tools accept, at the point where it
decides what to run, without opening a `.ps1` — and every flag `SKILL.md` names is one that script
actually has.

## The gap, measured

`SKILL.md` has no parameters section. `Get-SwydoReport.ps1` has **eleven** parameters
(`ShareUrl OutDir Secret PageSize Trend CacheDir Platform MaxWaitSec MaxTotalWaitSec ProbeFields
DefineOnly`, :38-51). Coverage today, counted as lines of `SKILL.md` mentioning the flag / of which
on an invocation of THIS script:

| flag | lines | on this script | where |
|---|---|---|---|
| `-OutDir` | 8 | 2 | inline in the Flow commands |
| `-ShareUrl`, `-Secret` | 3 | 2 | inline |
| `-MaxWaitSec` | 2 | 2 | `## Notes` "Patience flags" + a completeness-gate aside |
| `-Trend` | 2 | 2 | `:89` trend flow, `:104` Notes |
| `-MaxTotalWaitSec`, `-Platform` | 1 | 1 | `## Notes` |
| `-PageSize`, `-CacheDir`, `-ProbeFields`, `-DefineOnly` | **0** | 0 | nowhere |

(`-ArchiveRoot`, 3 lines, belongs to `Manage-SwydoArchive.ps1` / `Update-SwydoLedger.ps1` /
`Sync-SwydoTrend.ps1` — an earlier revision wrongly filed it under the extractor.)

Flow step 2 shows `Get-SwydoReport.ps1 -ShareUrl <link> [-Secret <pw>] -OutDir <tmp>` and stops.
Every tuning knob is absent or 70 lines below the command it modifies.

**And one documented flag does not exist.** `SKILL.md:74` says to run `Sync-SwydoTrend.ps1 … (add
`-Platform <id>` to match a filtered pull)`. That script's `param()` is `ShareUrl Secret OutDir
ArchiveRoot` — there is no `-Platform`, and `SKILL.md:54` states the opposite in terms: "there is NO
`-Platform` here — even after a filtered report pull, trend sync always covers the FULL account so
the ledger never accumulates a partial history." The file contradicts itself, and the instruction at
:74 would fail at the prompt. This is why the unit needs a REVERSE check, not just a forward one.

## Scope

IN: a `## Parameters` reference in `skill/SKILL.md` covering every parameter of all eight tool
scripts. A pointer from Flow step 2. The self-contradiction at `:74` deleted and replaced with the
`:54` truth. The `## Notes` "Patience flags" numbers collapsed into a cross-reference. The ledger
freeze horizon at `:91`, currently a bare literal `6`, stated as the `-K` default by reference.

OUT: no script changes, no default changes, no new parameters. Nothing outside `skill/SKILL.md`.

## Design

One table per script in Flow order. `_KeySpace.ps1` is excluded and cannot ever qualify: it has no
`param()` block by ratified decision (ANLZ-aCandidTally-1 B3 — a `param()` on a dot-sourced file
rebinds its names in the CALLER's scope and would set `$DefineOnly=$false` inside both callers), so
the mechanical glob and "all eight scripts" produce the identical set.

`-DefineOnly` IS documented, on all eight. It is a real parameter, the kickoff manifest front-loads
it at :166-167 as the reuse pattern every dot-sourcing caller must follow, and excluding it would
need a hand-maintained exclusion list that AC1's mechanical check would then have to encode.

## Acceptance criteria

- **AC0 (reverse).** Every `-Flag` token on a command line anywhere in `SKILL.md` is a parameter of
  the script named on that line, verified by the same mechanical `param()` extraction as AC1. The
  `:74` `-Platform` defect is the one existing violation and is fixed.
- **AC1.** Every parameter in every `param()` block across `skill/scripts/*.ps1` appears in the
  section — mechanical extract-and-diff, not eyeballed.
- **AC2a.** Parameters whose `param()` default is a LITERAL: the documented default is diffed
  mechanically against the source.
- **AC2b.** Parameters whose default is empty-string, a `$(...)`/`if(...)` expression, or absent are
  derived mechanically as that set, and each is documented as
  `default: <effective value>, resolved at <file>:<line>` — verified by reading that line. Publishing
  a literal `""` for a sentinel default would be actively misleading.
- **AC3.** `-PageSize`, `-CacheDir`, `-ProbeFields`, `-DefineOnly` — today at zero — are present.
- **AC4.** Flow step 2 links to the section.
- **AC5.** `## Notes` "Patience flags" no longer restates the numbers.
- **AC6.** No default appears both as a table value and as a bare literal in prose; specifically
  `:91` reads the freeze horizon as `-K` rather than `6`.

## Gates

Full bar. No suite asserts `SKILL.md` content, so the gates prove only that nothing else broke.
AC0-AC2 are the real check, are mechanical, and their output is pasted into the landing report
rather than asserted.

## Risk

Doc-only, and the dominant failure mode is a documented default drifting from the code — which is
why AC1/AC2 are mechanical. AC0 exists because a forward-only check cannot see a flag that is
documented but does not exist, which is precisely the live defect.
