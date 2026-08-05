# ANLZ-aCandidTally-1 — cell-key identity for metric lookups

**Status:** SPECCED · rev-5 · 2026-08-05 · node a · Tier-2 · base 39def66f · review wf_572b24b3-f3c · survey wf_0039abb6-748

> **REBASE NOTE (2026-08-05).** rev-1 through rev-4 were written and built against `6920f017`. The
> whole ANLZ-aUniformLattice program landed mid-unit, so the base moved to `39def66` and the body
> below is rewritten against it. The rev-3 AMENDMENTS block A1 through A14 is RETIRED, not deleted:
> its line anchors are all stale and three of its items are now wrong. A2, A3, A6 and A9 survive as
> design constraints and are folded into the body. A1 is superseded by S1. A5, A7, A10, A11 and A13
> are obsolete. The rev-3 review remains readable at `reviews/2026-08-05-review-aCandidTally-1.md`
> as the record of what it reviewed, which is the pre-rebase tree.

## 1. Goal

Make every rule that SELECTS a metric by its id also READ that metric's own cell. The defect is a
live wrong-number path that survived the ANLZ-aUniformLattice program, and the new matrix layer
replicates it while presenting the result as a fully provenanced measured value.

The invariant that explains the whole class, in one sentence: **every affected site selects a metric
by its ID and then reads its cell by display NAME, and the two agree only when the id-selected metric
happens to be the first holder of its display name.**

## 2. Scope (IN)

- **S1.** Single-source the key space. Move `Uniq-Key` and `Get-UniqKeySeq` out of
  `Get-SwydoReport.ps1` into `skill/scripts/_KeySpace.ps1`, holding nothing else, dot-sourced by
  `$PSScriptRoot` from both the extractor and the analyzer. This replaces rev-3's `Uniq-CellKey`
  replay, which was a hand-kept second copy of a single-source contract.
- **S2.** `Resolve-CellKeys($w)` stamps `cellKey` onto every record of `$w.metrics` that lacks one,
  by calling the shared sequence helper. Idempotent, and a no-op on a schemaVersion-3 document. It is
  load-bearing rather than legacy support: every end-to-end fixture in `Test-Analyze.ps1` hardcodes
  `schemaVersion=2`, so without it not one of them exercises a cell-key read.
- **S3.** `Metric-Key($m)` returns `cellKey` when present and non-empty, else the display name.
  `Metric-Label($m)` returns the display name unless it is null or whitespace, else the resolved key.
  Neither `Row-Cur` nor `Row-Cmp` changes signature; they already take a key.
- **S4.** Repoint every by-display-name cell read onto `Metric-Key`, resolved once per metric per
  function and never inside a per-row loop. The verification is mechanical rather than a list: after
  the change, a grep for a `.name`-shaped cell read returns hits only inside `Get-Breakdown`'s
  `values` block.
- **S5.** Repoint the matrix contribution read at `Analyze-SwydoReport.ps1:812`. Where `cellKey` is
  absent and the display name is collided, emit `reason='no-usable-cell'` rather than a value,
  matching the omit-rather-than-guess rule `Get-Breakdown` already applies.
- **S6.** Fix the matrix label. `Reduce-MatrixCell` writes `metric` from `$g[0]` at `:849`, before
  `:863` picks the winner, so a cell can carry one column's name with another column's number. Take
  the label from the winner, via `Metric-Label`. `aggClass` at `:841` has the same
  computed-before-the-winner shape and is resolved with it.
- **S7.** Make the breakdown `values` write first-wins. The read at `:404` always resolves the FIRST
  holder's cell while the format at `:406` uses the CURRENT metric's id and unit and the write at
  `:409` is last-wins, so a collided pair publishes metric 1's number formatted and typed as metric
  N. `type` is authoritative for the closer's same-type match, so that wrong string is a legitimate
  tracing candidate today. First-wins leaves every key count identical and makes one metric own the
  whole cell.
- **S8.** Close the blank-display-name hole in `Get-Breakdown`. Widen the `valuesById` gate from
  collided to collided-or-blank, and emit `metricNames[]` via `Metric-Label`. A lone blank-named
  metric currently has no `values` entry and no `valuesById` entry while `metricNames[]` and
  `metricIds[]` still advertise it, which breaks the index-aligned addressing contract.
- **S9.** Disclose ambiguity, never the superseded number. `canonical.keyBasis` is `display-name` or
  `cell-key`; `canonical.ambiguousWith` lists the other metric ids sharing that display name. Both
  describe the INPUT, so they are stable and idempotent across reruns. Mirrored onto the matrix cell.
- **S10.** `meta.canonicalVersion` 3 to 4 and `meta.matrixVersion` 1 to 2. `meta.factsVersion` stays
  2 and extraction `meta.schemaVersion` stays 3. Justified in §4 under `### Migration`.
- **S11.** Harden `Analyze-SwydoTrend.ps1:274`. Its `$null -ne $cell.metric` guard is true for an
  empty string, so the fallback never runs. This is hardening, not the repair: `-PeriodKpiFacts` is a
  file path, so the trend analyzer can be handed a facts document from any analyzer version.
- **S12.** Docs. Record in `skill/SKILL.md` why a collided `values` cell is safe to quote after S7,
  and state in `skill/report-template.md` that `valuesById` is deliberately not quotable, so a later
  session does not "fix" the omission without doing the closer half.
- **S13.** Tests, per §6 and §7.

## 3. Non-goals (OUT)

- Everything ANLZ-aUniformLattice already shipped. The extractor's `cellKey` emission, the
  `schemaVersion` 2 to 3 bump, the `valuesById` channel, and the matrix's ranks, reason ladder,
  `aggClass`, `basis` and conflict machinery are landed fact, not work.
- Re-keying the breakdown `values` map. Rev-3's S5 is WITHDRAWN. Keying by resolved key would red
  four shipped pins, rename published keys, make `valuesById` dead one commit after it shipped, and
  break the index-to-name-to-values two-step that `SKILL.md` depends on.
- Indexing `platforms[].metrics` or `rows[].valuesById` in the closer. The matrix's non-indexing is a
  deliberate guard property, ratified when the P5 spec rejected closer indexing for completeness.
  Promoting `valuesById` needs the closer and both docs to land together; it gets a backlog row.
- Widening the matrix conflict predicate to same-widget losers. Accepted residual, documented in §4.
- Any change to `Build-FactIndex`.

## 4. Design

### Data model

`Uniq-Key` derives a row-map key from the display name, falling back to the metric id when the name
is empty and to `col<idx>` when both are empty, and appending `[<id>]` then `[<id> #<idx>]` on a
collision. Its collision test runs against an `[ordered]@{}`, whose key comparer is
case-insensitive, so `Clicks` and `clicks` ARE a collision. PowerShell member access is
case-insensitive too, so the analyzer's by-name read resolves both to the first holder's cell.

There are therefore THREE divergence classes, not two: an exact duplicate display name, a
comparer-equal duplicate display name, and an empty display name. Byte-identity holds for a widget
whose display names are non-empty and pairwise distinct UNDER THAT COMPARER.

Any accumulator used to derive keys must be `[ordered]@{}` or a plain `@{}`. A
`Generic.HashSet[string]`, the idiom already used elsewhere in the analyzer, compares ordinally and
would derive a bare key where the extractor wrote a suffixed one, which the case-insensitive member
lookup would then resolve to the wrong metric's cell. That is the defect restored through its own
repair, and no existing test would catch it.

### Inventory

Verified against `39def66` by execution and by reading source on 2026-08-05, node a. The
reproduction is one Google Ads KPI widget carrying `google-adwords:conversions` and
`google-adwords:all_conversions`, both displayed `Conversions`, with cells 100 and 250.

| Surface | Site | Today on main | After |
|---|---|---|---|
| headline value | `:967` | `all_conversions` publishes 100 | 250 |
| headline presence | `:967` | a blank-named metric never gets an entry | present, keyed by id |
| headline label | `:988` | `$m.name`, blank for a blank-named metric | `Metric-Label` |
| matrix value | `:812` | 100, `method=kpi-widget`, no reason token | 250, or `reason='no-usable-cell'` |
| matrix rank contest | `:813-816`, `:873-877` | decided on a borrowed cell | decided on own cells; `scope` and `method` can flip |
| matrix conflict | `:885-894` | false or missing `same-rank-disagreement` | conflicts both appear and disappear |
| matrix label | `:849` | `$g[0]`'s name with the winner's number | winner's `Metric-Label` |
| breakdown cell | `:404-409` | metric 1's number formatted and typed as metric N | one metric owns the whole cell |
| breakdown blank name | `:422`, `:446` | vanishes from the table while `metricNames[]` advertises it | present in `valuesById`, labelled |
| breakdown row order | `:388` | the wrong column chooses which rows ship | resolved key |
| time-series derived and pacing | `:481`, `:498-502` | another metric's numbers under `$primary`'s unit | resolved key |
| value-carrying findings | `:248`, `:252`, `:271-281`, `:624`, `:641`, `:689`, `:691`, `:735`, `:743`, `:1133`, `:1211` | fabricated or suppressed majors | each metric's own cell |
| label-only findings | `:221`, `:232`, `:234`, `:239`, `:256`, `:260`, `:295`, `:483`, `:660`, `:701`, `:757`, `:1148`, `:1179`, `:1184-1188` | blank or duplicated names in client-facing sentences | `Metric-Label` |
| `GAP_NO_ACCOUNT_TOTAL` | `:1085`, `:1095-1097` | a borrowed value suppresses the gap | membership moves both ways |
| trend `RECON_*` | `Analyze-SwydoTrend.ps1:309`, `:318-321` | consumes the wrong headline value wholesale | correct input |

Two flips deserve their own sentence. The matrix today can publish a borrowed number as a measured
account value, and the repair DELETES that number rather than correcting it, which is a coverage
regression and the honest outcome. A scope or method flip is a first-class flip-set member, because
the rank contest itself moves, not only the value it selects.

`DISC_CROSS_WIDGET` at `:1211` is the sharpest consequence. It is severity major and therefore
force-surfaced into the delivered client report, and a collision makes it accuse the platform of a
cross-widget disagreement that does not exist, quoting a metric id so it reads as authoritative.

### Migration

`meta.canonicalVersion` 3 to 4 is mandatory: the marker names the headline algorithm, the rule is
global rather than flip-conditional, and `:967` changes what the headline publishes.

`meta.matrixVersion` 1 to 2 is mandatory for the identical reason applied to the matrix. Today that
rule exists only as an inference from two negative statements, both of which declined to move a
marker because the corresponding algorithm was untouched. This spec ratifies the positive form:
a key-resolution change under an unchanged reduce moves the marker of every layer it changes.

`meta.factsVersion` stays 2. It names the facts SHAPE and moves on a subtractive change; everything
here is additive. This is a direct consequence of withdrawing rev-3's S5, since renaming published
`values` keys would have been a shape change.

Extraction `meta.schemaVersion` stays 3. Note a structural trap: `Test-Extractor.ps1:154-158` regexes
the extractor SOURCE for `schemaVersion=\d+` and asserts exactly two matches. S1 moves functions out
of that file, so the leg must be re-checked rather than assumed.

Five assertions pin the two markers this unit moves, at `Test-Analyze.ps1:459`, `:460`, `:728`,
`:1300` and `:1301`. They are in-place updates, not additions. No product code outside the writer
reads either marker, and the closer is version-blind by construction.

### Rollout

This unit does not land dark. A default-OFF flag would leave the wrong number shipping by default,
which is the thing being repaired, and would double the surface every rule reads.

What replaces darkness is a byte-identity claim provable from `Uniq-Key` rather than measured: it
returns the bare display name on its first call, so the resolved key equals the display name for
every metric whose name is non-empty and comparer-unique within its widget. Such a report is
unchanged except for the two version markers. The guard is one acceptance criterion pinning a
no-collision fixture, not a full-facts golden, which this repo already ruled against.

### Files touched (estimate)

| File | Change |
|---|---|
| `skill/scripts/_KeySpace.ps1` | new; the two key functions and nothing else |
| `skill/scripts/Get-SwydoReport.ps1` | dot-source the new file; remove the moved functions |
| `skill/scripts/Analyze-SwydoReport.ps1` | dot-source; the four helpers; the S4 repoints; S5 to S9; the two version literals |
| `skill/scripts/Analyze-SwydoTrend.ps1` | the S11 guard |
| `Test-Analyze.ps1` | the §6 cases; five in-place version-pin updates; the stale header comment at `:649` |
| `Test-Extractor.ps1` | the extractor-to-analyzer seam fixture; re-check the source-regex leg |
| `Test-TrendAnalyze.ps1` | one RECON pass over repaired facts |
| `skill/SKILL.md`, `skill/report-template.md` | S12 |

### Alternatives rejected

**Replay `Uniq-Key` inside the analyzer.** This was the rev-3 design. Dominated by S1: a drift gate
is strictly more machinery than not duplicating.

**Dot-source `Get-SwydoReport.ps1 -DefineOnly` from the analyzer.** Mechanically feasible, but it
drags the websocket state block and a 1 MB buffer allocation into the analyzer's load path.

**Re-key the breakdown `values` map.** Rejected under §3.

**Widen the matrix conflict predicate to same-widget losers.** It would emit `losingWidgetIds` naming
the winning widget, which reads as nonsense. Accepted as a residual with a pinned acceptance
criterion instead, so the drop is asserted rather than latent.

## 5. Production-readiness checklist

- security — N/A. No write path, credential path or egress surface is touched.
- perf / scale — one key resolution per metric per function, hoisted out of every per-row loop.
- a11y — N/A. No UI.
- i18n — this unit DOES change user-visible strings: a blank metric label becomes a resolved key.
- error / empty / loading states — the blank-display-name case is a first-class fixture, not an edge.
- observability — S9 is the observability surface, and it names ids only.
- risks — the matrix loses coverage where it currently publishes a borrowed number. `type` and `unit`
  on a collided breakdown cell change owner under S7. Rollback is a revert; no persisted artifact
  changes shape.
- testing + left-shift gates — §6 and §7. The closer cannot catch this class at all: it is a
  membership test, and a facts document that is internally consistent but wrong about which metric
  owns a number passes at 100% traced. The left-shift is therefore a fixture regression suite.
- migration / rollback — `### Migration`.
- user docs — S12.

## 6. Acceptance criteria

- **AC1.** When a widget carries two metrics with the same display name, each headline id carries its
  own value.
- **AC2.** When a metric's display name is empty, it reaches the headline with a non-empty label and
  `GAP_NO_ACCOUNT_TOTAL` no longer names it.
- **AC3.** When two display names differ only in case, they are treated as a collision at both ends.
- **AC4.** When the matrix and the headline are compared cell-for-cell over both collision fixtures,
  they agree. This is the mechanical prohibition on a one-sided repair.
- **AC5.** When a matrix contribution cannot resolve its own cell, the cell carries
  `reason='no-usable-cell'` and no value keys.
- **AC6.** When a rank-1 KPI's own cell is an echo, the rank-2 table wins and `scope`, `method` and
  `contributingWidgetIds` all move.
- **AC7.** When a collision is present, a false `same-rank-disagreement` conflict disappears and a
  genuine one appears.
- **AC8.** When the winner is not `$g[0]`, the matrix cell's label is the winner's.
- **AC9.** When a micros metric and a count metric share a display name, the surviving breakdown
  cell's `display`, `unit` and `type` all describe the metric that owns the number.
- **AC10.** When a metric's display name is blank, it appears in `valuesById` and its `metricNames[]`
  entry is non-blank.
- **AC11.** When a schemaVersion-2 document is analyzed, the headline and matrix resolve cell keys
  through S2, and the stamped sequence equals the extractor's own on the identical metric list.
- **AC12.** When a real `Normalize-Widget` output is fed to the analyzer, the seam holds end to end.
  Nothing does this today.
- **AC13.** When a no-collision fixture is analyzed, its facts are unchanged except for the two
  version markers.
- **AC14.** When `Build-FactIndex` runs over the collision fixtures, no candidate equals a superseded
  value, and the per-platform candidate count equals the pre-change count plus the intended delta.
- **AC15.** When one widget declares the same metric id twice under two display names, the second
  column is dropped without a conflict entry. This pins the accepted residual.
- **AC16.** When a trend RECON pass runs over repaired facts, a metric that previously had no
  headline cell is reconciled and no statement carries a blank label.
- **AC17.** When the full bar runs, every leg is green and no untouched suite's count moves.

## 7. Gates

The standing merge bar, `bash tools/run-gates.sh`, with all eight PowerShell suites, ps source
hygiene, memory hygiene, the manifest ratchet, the memory-recall selftest and skill-drift leg, the
agent-instructions wiring leg, the agent-cap selftest, the check-wiring selftest and the run-gates
canary. Plus `bash scripts/manifest-check.sh`.

Baseline on `39def66`: `Test-Analyze.ps1` 619, `Test-Extractor.ps1` 288, `Test-Closer.ps1` 129.

New gates: the §6 fixture suite, and the AC14 closer-arithmetic check. On a green run
`$LASTEXITCODE` is empty because the suites call `exit 1` only on failure, so assert the failure
path rather than a zero that is never written.

## 8. Open questions

- **OD-1 — does the ambiguity disclosure also get a visible finding?** A `canonical`-buried key gives
  the reader no signal that the repair fired. Recommendation: yes, one info-severity per-provider
  roll-up naming the ambiguous metric ids plus a count, copying the shape of the shipped
  `GAP_HEADLINE_SOURCE_CHANGED`, which is ids-and-count only and was ratified as safe precisely
  because it carries no metric value to trace.
- **OD-2 — does the trend facts document echo the source `canonicalVersion`?** `-PeriodKpiFacts` is a
  file path, so a trend run can consume a pre-repair archive and cannot tell. Recommendation: yes,
  one additive key, plus a spec sentence that the trend counter is independent of the report counter
  so a future reader does not "align" them.
- **OD-3 — is a breakdown-only flip allowed to ship under an unchanged marker set?** S7 changes a
  published breakdown display string, and a dimensioned widget with no total row feeds neither the
  headline nor the matrix, so that flip is reachable with both moved markers untouched. Options are
  to mint `meta.breakdownVersion` or to record it as an accepted residual. This is the
  weakest-supported item in the spec and I have no strong recommendation.
- **OD-4 — does this unit fix S6 and S7 at all?** Both are defects in code that landed hours ago from
  a different unit, not in the lookup path this unit was scoped to. They are in scope only because
  repairing the lookups without them leaves the breakdown cell internally inconsistent.
  Recommendation: keep them here, because splitting them out means two units touching
  `Analyze-SwydoReport.ps1` in sequence for one coherent repair.

## 9. Revision log

- rev-1 · 2026-08-05 · initial draft, grounded on a PowerShell 5.1 reproduction against `6920f017`.
- rev-2 · 2026-08-05 · owner resolved F1 through F4 on the recommendations.
- rev-3 · 2026-08-05 · folded review `wf_572b24b3-f3c` as an AMENDMENTS block, A1 through A14, from
  28 confirmed findings against 16 refuted. F5 opened and resolved.
- rev-4 · 2026-08-05 · built and landed on the branch against `6920f017`. Gates green there.
- rev-5 · 2026-08-05 · rebased onto `39def66f` after ANLZ-aUniformLattice landed mid-unit. Body
  rewritten against the new base from survey `wf_0039abb6-748`. rev-3's AMENDMENTS retired per the
  rebase note. S1 dropped as landed upstream; rev-3's S5 withdrawn; the matrix, the breakdown cell
  and the blank-name hole added. Status returned to SPECCED because the scope now includes two
  defects in freshly-landed code and needs owner approval before building.

## 10. Reuse audit

none — codebase-map not adopted; seams identified by reading `skill/scripts/Get-SwydoReport.ps1:363`
and `:403`, and `skill/scripts/Analyze-SwydoReport.ps1:192`, `:404`, `:812`, `:849` and `:967`. S1
wires through the extractor's existing `Uniq-Key` and `Get-UniqKeySeq` by extracting them to a shared
file rather than copying them, which is the §12 shared-core shape. S2 reuses that same sequence
helper. AC12 reuses the `W`, `Node` and `FieldsConn` fixture harness already in `Test-Extractor.ps1`
rather than adding a second normalizer-driving helper, which would be a §12 duplicate; that harness
seeds `$script:secMap` and `$script:secHidden`, so any reuse site must seed them too.
