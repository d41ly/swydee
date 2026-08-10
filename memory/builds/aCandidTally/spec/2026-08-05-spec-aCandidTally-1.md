# ANLZ-aCandidTally-1 — cell-key identity for metric lookups

**Status:** INPROGRESS · rev-7 · 2026-08-05 · node a · Tier-2 · base 39def66f · ratified 2026-08-05 · review wf_26d054aa-792

> **REBASE NOTE (2026-08-05).** rev-1 through rev-4 were written and built against `6920f017`. The
> whole ANLZ-aUniformLattice program landed mid-unit, so the base moved to `39def66` and the body
> below is rewritten against it. The rev-3 AMENDMENTS block A1 through A14 is RETIRED, not deleted:
> its line anchors are all stale and three of its items are now wrong. A2, A3, A6 and A9 survive as
> design constraints and are folded into the body. A1 is superseded by S1. A5, A7, A10, A11 and A13
> are obsolete. The rev-3 review remains readable at `reviews/2026-08-05-review-aCandidTally-1.md`
> as the record of what it reviewed, which is the pre-rebase tree.

> **AMENDMENTS (review rev-6, 2026-08-05)** - these override the section bodies below on any conflict.
>
> **B1.** S2 names its invocation site: `Resolve-CellKeys` runs once over `$dataWidgets` after that
> array is built at `Analyze-SwydoReport.ps1:913`, before the headline loop at `:942`, the matrix
> pass at `:1049` and the breakdown pass at `:1249`. All three read the same stamped records,
> `Get-Breakdown` included. S2 therefore RETIRES the ANLZ-aUniformLattice-8 omit-rather-than-guess
> guard at `Analyze-SwydoReport.ps1:422-427`: on a schemaVersion-2 document `cellKey` is never
> absent, the `if($null -ne $ck)` branch is unreachable in the run path, and the comment at
> `:425-426` is rewritten to say so. The retirement publishes the extractor's own key rather than a
> guess, because the row map at `Get-SwydoReport.ps1:729` was built by the same `Uniq-Key` this unit
> single-sources. A collided schemaVersion-2 document GAINS `valuesById` entries it previously
> omitted; that is a deliberate facts-shape change and is disclosed in §4 Migration. The §3 non-goal
> covering the `valuesById` channel is narrowed: its gate is landed fact, its no-cellKey branch is
> not. §4 Migration's list of in-place test updates goes from five to seven. `Test-Analyze.ps1:1291`
> becomes two entries rather than zero. `Test-Analyze.ps1:1292` becomes both colliding ids
> addressable, each carrying its own number. The §4 Files-touched row for `Test-Analyze.ps1` names
> both lines. The §4 Rollout byte-identity claim is scoped to a no-collision report and does not
> extend to a collided one. **AC21.** When a schemaVersion-2 document carrying two metrics with one
> display name is analyzed end to end, both ids appear in `valuesById` and their `display` values
> differ.
>
> **B2.** S5's trigger condition is rewritten and its "where `cellKey` is absent" framing is dropped.
> B1 makes that state unreachable in the run path, and it also contradicts S3's stated fallback. The
> condition becomes: where the key returned by `Metric-Key` addresses no numeric cell on the widget's
> total row, the contribution stays rank 0 with a null cell and falls through to the shipped reason
> ladder at `Analyze-SwydoReport.ps1:830`, which already returns `no-usable-cell` for an eligible
> widget with a total row. No second emission path is written, so nothing double-classifies that
> cell. The §4 Inventory row for `matrix value` at `:812` reads `250` with no alternative branch.
> AC5 is re-pointed at a fixture whose row map does NOT contain the derived key, an archived
> key-space document, because a fixture that merely lacks `cellKey` no longer reaches the
> unresolvable state. Overrides S5, that Inventory row and AC5.
>
> **B3.** `_KeySpace.ps1` carries NO `param()` block, no `-DefineOnly` switch and no early return. It
> is a bare function library, dot-sourced as `. "$PSScriptRoot\_KeySpace.ps1"` with no arguments. A
> `param()` block on a dot-sourced file rebinds its declared names in the CALLER's scope, which would
> set `$DefineOnly=$false` and `$InFile=''` inside `Analyze-SwydoReport.ps1` and
> `Get-SwydoReport.ps1` and drop both through their guards at `:898` and `:953` into their run
> bodies. That reds six suites with a message naming neither `_KeySpace.ps1` nor the dot-source.
> Both dot-sources must sit ABOVE those guards, because the extractor consumes `Get-UniqKeySeq` at
> `Get-SwydoReport.ps1:711` and `Uniq-Key` at `:729`. This is the one file in `skill/scripts/` that
> deliberately breaks the functions-first `param()` convention recorded at
> `.claude/SESSION-KICKOFF.md:163-164`, and this sentence is the record of why. Overrides S1 and the
> §4 Files-touched row for `skill/scripts/_KeySpace.ps1`.
>
> **B4.** S1 removes a duplicate definition, so it also adds the guard against a re-added one.
> **AC22.** `(Get-Command Uniq-Key).ScriptBlock.File` and `(Get-Command Get-UniqKeySeq).ScriptBlock.File`
> both end in `_KeySpace.ps1`, asserted in `Test-Extractor.ps1`, the suite that loads the extractor
> and, per AC12, the analyzer. It mirrors the in-tree precedent at `Test-Ledger.ps1:185-186`. AC11
> cannot substitute for it: functions share one session namespace, so a re-added local copy shadows
> globally and both sides of a sequence-equality assertion would call the same surviving definition.
> AC22 is listed under §7 New gates. Overrides the §4 Alternatives-rejected entry "Replay `Uniq-Key`
> inside the analyzer" and §7 New gates.
>
> **B5.** S9 states its emission condition: `canonical.keyBasis` and `canonical.ambiguousWith` are
> emitted ONLY on a metric whose display name is ambiguous or blank within its own widget. An
> unambiguous cell's `canonical` block is byte-identical to today. Without that condition the keys
> land on every cell of every report, because the block is built unconditionally at
> `Analyze-SwydoReport.ps1:994`, which falsifies AC13 and the §4 Rollout claim that a no-collision
> report is unchanged except for the two version markers. Overrides S9.
>
> **B6.** S9 is the unit's only observability surface and gets its own criterion. **AC23.** When a
> report carries an ambiguous display name, each affected headline cell and its matrix mirror carry
> `canonical.keyBasis='cell-key'` and a `canonical.ambiguousWith` listing the other metric ids
> sharing that name, a `ConvertTo-Json` of each affected cell matches no superseded value, and a
> report with no ambiguous name carries neither key on any cell. The superseded-value half copies the
> shipped shape at `Test-Analyze.ps1:1192`. Overrides §6, which pins every other in-scope item and
> left S9 uncovered, and §7, whose fixture suite is driven by §6.
>
> **B7.** Ambiguity is a per-WIDGET property and S9 and S14 both say so. `Get-UniqKeySeq` allocates a
> fresh probe map per widget metric list at `Get-SwydoReport.ps1:364`, and the extractor's row maps
> are built the same way, so two single-metric widgets of one provider sharing a display name are not
> a collision and each headline cell already reads its own row correctly. S9 lists the other metric
> ids sharing the display name WITHIN `canonical.sourceWidgetId`'s own metric list. S14's roll-up is
> a per-provider PRESENTATION of a per-widget computation, and an id appears only when some single
> widget's metric list holds two comparer-equal display names covering it. AC19's report-wide trigger
> is read the same way. **AC24.** When one provider carries two single-metric widgets whose display
> names are identical, no cell carries `keyBasis` or `ambiguousWith` and no roll-up finding is
> emitted. Overrides S9, S14 and AC19.
>
> **B8.** The §4 Inventory row for `matrix rank contest` names the full flip set: `scope`, `method`,
> `unit`, `currency`, `type`, `aggClass` and `basis.basisVersion` all move with the winner, because
> `Analyze-SwydoReport.ps1:863` reassigns `$m` and `$cc` and `:870-876` derive all of them from those
> two. `observedOnWidgetIds` is invariant by construction, since `:842` computes it over the whole
> group and is rank-independent. AC6 asserts `unit`, `currency` and `basis.basisVersion` alongside
> `scope`, `method` and `contributingWidgetIds`. The §4 Inventory row for `matrix conflict` at
> `:885-894` gains the currency mode: `$offBasis` at `:887` compares each loser against the WINNER's
> basis and `$losers` at `:885` is derived from `$ranked`, so a winner flip across a currency
> boundary can make a `basis-mismatch` conflict appear or disappear, and `conflict.reason` can change
> token with no conflict appearing or disappearing. **AC25.** When the winner flips across a currency
> boundary, a `basis-mismatch` conflict both appears and disappears, over a two-currency fixture in
> the shape already shipped at `Test-Analyze.ps1:1195-1202`. Overrides those two Inventory rows, AC6
> and AC7.
>
> **B9.** AC4 is restated with a defined comparison, because the two layers do not share a key set
> and the only shipped assertion of the phrase, `Test-Analyze.ps1:1145`, compares `displayCurrent`
> alone. **AC4.** When the matrix and the headline are compared over the (platform, metricId) pairs
> present in BOTH layers, they agree on `id`, `current`, `previous`, `deltaPct`, `displayCurrent`,
> `displayPrevious`, `displayDelta`, `type`, `direction`, `unit`, `currency`, `hasComparison` and the
> resolved label; the matrix's provenance keys and the headline's `canonical` block are out of scope.
> Both collision fixtures are single-provider-prefix and visible-section by construction. The
> mixed-prefix and hidden-section divergences pinned at `Test-Analyze.ps1:1309-1332` remain
> legitimate and AC4 does not reverse them. Reusing `$dupMets` at `Test-Analyze.ps1:1259` would make
> AC4 unsatisfiable for reasons unrelated to this repair, because `facebook-ads:clicks` is never a
> discovered platform and its matrix cell is dropped at `Analyze-SwydoReport.ps1:1060`.
>
> **B10.** S8 moves the self-describing marker together with the gate: `valuesByIdScope` at
> `Analyze-SwydoReport.ps1:446` goes from `collisions-only` to `collisions-and-blank-names`, and
> `none` is unchanged. The token is a hardcoded rule descriptor, so widening the gate without moving
> it ships a marker stating a rule the code no longer follows. `Test-Analyze.ps1:1251` and `:1387`
> pin the token and are in-place updates, listed in §4 Migration beside the version pins and in the
> §4 Files-touched row for `Test-Analyze.ps1`. AC10 asserts the token beside the entry. Overrides S8,
> §4 Migration, §4 Files touched and AC10.
>
> **B11.** AC18 is restated, because S10's markers are unconditional literals at
> `Analyze-SwydoReport.ps1:1276` and move on EVERY document, so no fixture can flip a breakdown cell
> with them untouched. **AC18.** When a dimensioned no-total widget with a collided display name is
> analyzed, its breakdown cell changes owner while that fixture's `platforms[].headline` and
> `platforms[].metrics` blocks are byte-identical to the pre-change run, and no emitted marker names
> the breakdown layer. The §4 Migration sentence under OD-3 is corrected to match: the two markers
> move on every document and signal "new analyzer" rather than "the breakdown changed", so the
> accepted residual is that no marker NAMES the breakdown layer, not that the flip ships with the
> markers untouched.
>
> **B12.** AC14's first clause and AC19's second clause are restated in an assertable form.
> `Build-FactIndex` at `skill/scripts/Test-ReportNumbers.ps1:195` builds one flat per-platform
> candidate bag with no metric identity attached, so on the §4 reproduction the superseded value 100
> is still a candidate after the repair: it is `google-adwords:conversions`'s own correct number.
> **AC14.** `Build-FactIndex` over the collision fixtures yields a candidate multiset identical to
> the one derivable from headline `displayCurrent`, `displayPrevious` and `displayDelta`, breakdown
> cells and `timeSeries` alone, and the per-platform candidate count equals the pre-change count plus
> the intended delta. **AC19.** Its first clause is unchanged; its second becomes: the S14 roll-up
> contributes nothing to `byFid` beyond its own count. The justification is structural rather than
> measured: `Build-FactIndex` never reads `canonical` and never indexes `platforms[].metrics`, and
> findings route to `byFid` only at `:244-254`, so the S9 and S14 disclosure surfaces are
> candidate-free by construction.
>
> **B13.** S15 emits `meta.sourceCanonicalVersion` ONLY when `-PeriodKpiFacts` was supplied. The key
> is OMITTED, never null: an absent key means "no source document", which is different from "a source
> document with no marker", and the present-and-null form is itself the pre-repair signal. The trend
> meta block at `Analyze-SwydoTrend.ps1:337-349` sits OUTSIDE the `if($myPeriodKpiFacts)` branch that
> opens at `:208`, so an inline assignment in that `[ordered]@{}` literal adds a null key to every
> ledger-only run. That would break the byte-identity guarantee documented at `:206-207` under an
> unmoved trend `factsVersion`, and `Test-TrendAnalyze.ps1:251` counts `RECON_*` findings only and
> would not catch it. AC20 gains the negative case: a trend run with no `-PeriodKpiFacts` emits no
> `sourceCanonicalVersion` key at all and its facts are otherwise byte-identical to the pre-change
> output. Overrides S15, AC20 and the §4 Migration trend paragraph.
>
> **B14.** S6 RE-ASSIGNS `metric` and `aggClass` in place on the existing `[ordered]` entries created
> at `Analyze-SwydoReport.ps1:849` and `:875`, and the `$out` literal at `:849` keeps both keys.
> Dropping `metric` from that literal and appending it after the winner is picked would move it to
> last on every value cell and remove it from every reason cell, changing matrix-cell key order on
> every report under the §4 Rollout byte-identity claim. No shipped assertion observes matrix-cell
> key order: the pins at `Test-Analyze.ps1:1151`, `:1230`, `:1242` and `:1246` cover the platform
> object, the facts top level and the breakdown. **AC26.** Matrix-cell key order is pinned for both
> branches, one value cell and one reason cell, in the shape of `Test-Analyze.ps1:1242` and `:1246`,
> so S9's additions and any later reshuffle have a gate. Overrides S6 and §6.
>
> **B15.** S7's guarantee is restated: the surviving `values` key is the FIRST holder's spelling and
> the key count is unchanged. `$vals` at `Analyze-SwydoReport.ps1:400` is an `[ordered]@{}`, whose
> indexer REPLACES the stored key's casing, so on a comparer-equal pair today's last-wins publishes
> metric N's casing and first-wins publishes metric 1's. That is a user-visible published string
> change and joins the §5 i18n bullet beside the blank-label case. AC9 asserts the surviving key TEXT
> alongside `display`, `unit` and `type`. §4 Migration's justification for holding `meta.factsVersion`
> at 2 names this exception: the key TEXT of a comparer-equal duplicate changes while no key is added
> or removed, so the shape is unchanged and the marker still does not move. The membership test is
> `$vals.Contains(...)`, the idiom already used at `Analyze-SwydoReport.ps1:972`. `[ordered]@{}` is an
> `OrderedDictionary` and has no `ContainsKey` method, so that call throws under the
> `$ErrorActionPreference='Stop'` set at `:28`; the neighbouring `$nameCount` at `:396` is a plain
> Hashtable and the two idioms are not interchangeable. Overrides S7, §5 and AC9.
>
> **B16.** §4 Files touched gains a row for `.claude/SESSION-KICKOFF.md`: re-stamp `last-audit`,
> bundled into the SAME commit as each watched change, and update the per-suite green counts and the
> 1276 total at `:103-107` to the post-unit figures. The manifest's watch list at `:6` covers `skill`
> and `Test-*.ps1`, both of which this unit edits, and `.githooks/pre-commit` runs
> `scripts/manifest-check.sh --staged`, whose only green path is the bundled re-stamp, so an
> unbundled commit is BLOCKED at commit time rather than flagged at the push boundary. §7 states that
> the ratchet leg greens only with the re-stamp bundled in, and that the manifest's per-suite figures
> are part of the merge bar rather than documentation. This is the house pattern from the immediately
> preceding program at
> `memory/analysis/builds/2026-08-04-ANLZ-aUniformLattice/spec/2026-08-04-spec-aUniformLattice-2.md:230`.

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
- **S14.** One info-severity per-provider roll-up naming the metric ids whose display names were
  ambiguous, plus a count as a string. It copies the shape of the shipped
  `GAP_HEADLINE_SOURCE_CHANGED`: ids and a count, never a metric value, which is why that finding was
  ratified as closer-safe. S9 alone leaves the reader no visible signal that the repair fired.
- **S15.** The trend facts document echoes the source `canonicalVersion` as one additive `meta` key.
  `-PeriodKpiFacts` is a file path, so a trend run can consume a pre-repair archive and today has no
  way to tell. The trend counter stays independent of the report counter, stated in `### Migration`
  so a future reader does not "align" them.

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

No `meta.breakdownVersion` is minted (OD-3, owner). S7 changes a published breakdown display string,
and a dimensioned widget with no total row feeds neither the headline nor the matrix, so that flip is
reachable with both moved markers untouched. That is an ACCEPTED, UNMARKED residual: a consumer
diffing two facts documents cannot attribute a breakdown-only change to this unit from the markers
alone. It is pinned by AC18 rather than left latent, and the marker taxonomy keeps three names rather
than four.

The trend facts document gains `meta.sourceCanonicalVersion` (S15), echoing the report document it
was handed. Trend `meta.factsVersion` stays 1 and is a SEPARATE numbering line from the report's:
the two counters have never been aligned and must not be.

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
- **AC18.** When a dimensioned no-total widget with a collided display name is analyzed, its
  breakdown cell changes owner while `canonicalVersion`, `matrixVersion` and `factsVersion` all stay
  put. This pins the unmarked breakdown flip that OD-3 accepted as a residual.
- **AC19.** When a report carries an ambiguous display name, one info-severity roll-up names the
  affected metric ids, and `Build-FactIndex` over that document yields no candidate equal to any
  superseded value.
- **AC20.** When the trend analyzer is handed a facts document, the trend facts carry
  `meta.sourceCanonicalVersion` equal to the source document's `canonicalVersion`, and the trend's
  own `factsVersion` is unchanged at 1.

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
  RESOLVED (owner, 2026-08-05): yes. Built as S14.
- **OD-2 — does the trend facts document echo the source `canonicalVersion`?** `-PeriodKpiFacts` is a
  file path, so a trend run can consume a pre-repair archive and cannot tell. Recommendation: yes,
  one additive key, plus a spec sentence that the trend counter is independent of the report counter
  so a future reader does not "align" them.
  RESOLVED (owner, 2026-08-05): yes. Built as S15.
- **OD-3 — is a breakdown-only flip allowed to ship under an unchanged marker set?** S7 changes a
  published breakdown display string, and a dimensioned widget with no total row feeds neither the
  headline nor the matrix, so that flip is reachable with both moved markers untouched. Options are
  to mint `meta.breakdownVersion` or to record it as an accepted residual. This is the
  weakest-supported item in the spec and I have no strong recommendation.
  RESOLVED (owner, 2026-08-05): NO. No marker is minted; the unmarked breakdown flip is an accepted
  residual, pinned by AC18 so it is asserted rather than latent.
- **OD-4 — does this unit fix S6 and S7 at all?** Both are defects in code that landed hours ago from
  a different unit, not in the lookup path this unit was scoped to. They are in scope only because
  repairing the lookups without them leaves the breakdown cell internally inconsistent.
  Recommendation: keep them here, because splitting them out means two units touching
  `Analyze-SwydoReport.ps1` in sequence for one coherent repair.
  RESOLVED (owner, 2026-08-05): fix them here. S6 and S7 stay in scope.

## 9. Revision log

- rev-1 · 2026-08-05 · initial draft, grounded on a PowerShell 5.1 reproduction against `6920f017`.
- rev-2 · 2026-08-05 · owner resolved F1 through F4 on the recommendations.
- rev-3 · 2026-08-05 · folded review `wf_572b24b3-f3c` as an AMENDMENTS block, A1 through A14, from
  28 confirmed findings against 16 refuted. F5 opened and resolved.
- rev-4 · 2026-08-05 · built and landed on the branch against `6920f017`. Gates green there.
- rev-7 · 2026-08-05 · folded review `wf_26d054aa-792` as the B-series AMENDMENTS block, B1
  through B16, from 20 confirmed findings against 16 refuted across five finder lenses and four
  batched skeptics. Three blockers share one root cause: S2's stamping makes the shipped
  omit-rather-than-guess branch unreachable, which reds two undeclared assertions and voids S5's
  stated precondition. AC21 through AC25 added. Status INPROGRESS.
- rev-6 · 2026-08-05 · owner resolved OD-1 through OD-4. OD-1 and OD-2 become S14 and S15; OD-3 is
  declined, so the unmarked breakdown flip is an accepted residual pinned by AC18; OD-4 keeps the two
  freshly-landed defects in scope. AC18 through AC20 added.
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
