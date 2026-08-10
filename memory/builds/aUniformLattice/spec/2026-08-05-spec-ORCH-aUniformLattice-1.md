# ORCH-aUniformLattice-1 — the executables leave the repo root

**Status:** CLOSED · rev-1 · 2026-08-05 · node a · Tier-1 · base 3bf65010

Nine executables sat in the repo root: the eight `Test-*.ps1` suites (4,143 lines) and
`Run-Gates.ps1`. They moved to `tests/` and `tools/` respectively. Root now holds only governance
documents and dotfile config — zero executables, nine tracked files.

## What moved, and what deliberately did not

| from | to | why |
|---|---|---|
| eight root `Test-*.ps1` | `tests/` | the bulk of the clutter, and a directory the tooling can name as one pathspec |
| `Run-Gates.ps1` | `tools/Run-Gates.ps1` | it is a thin wrapper over `tools/run-gates.sh`; the twin belongs beside its twin |

`SKILL_BUILD_SPEC.md`, `SWYDO_REPORT_EXTRACTION_SPEC.md` and `data_gaps.md` STAYED in root, and the
reason is binding rather than aesthetic. All three are cited by name from ratified decision records
under `memory/` — `SWYDO_REPORT_EXTRACTION_SPEC.md` from eight of them, `data_gaps.md` from five
places in `2026-07-13-spec-aGappedRanking-1.md` alone. §6 makes the decision log append-only, so
moving the files would strand those citations with no sanctioned way to repair them: the choice is
a stale permanent record or a rewritten one, and both are worse than three documents in root. They
are governing documents anyway, which is where `AGENTS.md` already lives.

## The finding this move surfaced (the reason it needed a gate, not just a `git mv`)

`Test-Closer.ps1` was the ONLY one of the eight with no `$ErrorActionPreference`. Every other suite
sets `'Stop'` at the top. Measured on PS 5.1, dot-sourcing a missing path:

- without `EAP=Stop`: the error prints, **the body continues, and the script exits 0**
- with `EAP=Stop`: the script halts and exits 1

The suite ends `if($script:fail -gt 0){ exit 1 }`. So a `Test-Closer.ps1` whose dot-source no longer
resolved would have printed `Test-Closer: 0 passed, 0 failed.` and reported the leg GREEN having
executed nothing — precisely the green-by-absence class §7 names. The move would have created that
condition. `EAP=Stop` is now set, with the measurement recorded inline at the top of the file.

## Two properties of the gate runner worth knowing before the next layout change

1. **No glob discovery anywhere.** `tools/gate-legs.json` enumerates all eight suites as literal
   filenames, and `tools/run-ps-suite.sh` hard-checks `[ -f "$suite" ]` and exits 2. A stale suite
   path is therefore a loud per-leg failure, never a silent pass.
2. **No leg count is asserted.** `run-gates.sh` computes `n` dynamically and prints `X/X`, so a leg
   DELETED from the manifest yields a green bar with a smaller number and nothing objects. Verify a
   layout change by reading the leg NAMES in the run output, never the tally.

## Wiring updated in the same commit

- 16 `$PSScriptRoot` path expressions across the eight suites, in two syntactic forms (the
  `Join-Path $PSScriptRoot 'skill\scripts\…'` single-quoted form does not match a
  `"$PSScriptRoot\skill` grep — search the substring `skill\scripts` instead).
- `tools/gate-legs.json` — eight `argv[2]` values prefixed `tests/`.
- `tools/Run-Gates.ps1` — `Push-Location (Split-Path -Parent $PSScriptRoot)`, because every kit
  script it invokes assumes cwd is the repo root.
- `.claude/SESSION-KICKOFF.md` — the `watch:` pathspec `Test-*.ps1` matched zero files after the
  move and `manifest-check.sh` C6 fails a spec that matches nothing; it is now `tests`. Five
  pointer-map rows re-prefixed.
- `AGENTS.md` §6 — the layout map and the everyday-command catalog.

`skill/scripts/Test-ReportNumbers.ps1` is NOT one of the eight and did not move. It is the §4
verification harness, and every suite that references it keeps pointing at `skill/scripts/`.

## Known blind spot, accepted

`memory-recall` digests only `git ls-files memory/`, so a root-level relocation never invalidates
its cache and the corpus will keep answering with pre-move paths until a `memory/` file changes.
This record IS that change, which refreshes the digest as a side effect. Anyone doing a future
layout move outside `memory/` should land a decision line for the same reason.

## A pre-existing bug the move exposed: the bar depended on its parent shell

Documenting `.\tools\Run-Gates.ps1` in the AGENTS.md command catalog meant running it, which is how
this surfaced. It was RED on `Test-Archive` (6 assertions) while `bash tools/run-gates.sh` was green
on the identical tree. Confirmed pre-existing: `main`'s own `Run-Gates.ps1`, in the untouched primary
tree, failed the same way.

Cause: `PSModulePath` is inherited. Launched from PowerShell 7, the 5.1 children inherit pwsh's
module path, never search their own `v1.0\Modules`, and `Get-FileHash` stops resolving. The suite
result was therefore a property of the shell that started it, not of the code. `tools/run-ps-suite.sh`
now `unset PSModulePath` before launching, so 5.1 rebuilds its own default. Green under both parents.

This is the §11 "deterministic run modes" class, and it was invisible for as long as nobody ran the
bar from pwsh.

## Verification

All eight suites re-run from `tests/`: 1405 assertions, identical to the pre-move counts
(Analyze 701, Extractor 327, Closer 129, TrendAnalyze 76, TrendFacts 24, Archive 94, Ledger 50,
Sync 4). Full bar: 17/17 legs green, all eight suites present by name.
