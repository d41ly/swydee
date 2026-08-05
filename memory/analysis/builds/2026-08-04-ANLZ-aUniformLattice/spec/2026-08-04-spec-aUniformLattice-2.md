# ANLZ-aUniformLattice-2 — P1: extractor schema v3, identity and completeness keys

**Status:** SPECCED · rev-2 · 2026-08-04 · node a · Tier-2 · base d1848f7b · parent ANLZ-aUniformLattice-1 · review wf_b63e8c70-87e

## 1. Goal

Emit the identity and completeness keys the uniform matrix needs, every one of which the extractor
already fetches and discards, and bump `schemaVersion` to 3 with every literal-gating consumer
widened. Strictly additive: no existing key changes name, shape, value or ordering.

## 2. Scope (IN)

- S1. `widget.dimensionRefs[]` of `{name, id}`, parallel to the untouched `widget.dimensions[]`.
- S2. `widget.metrics[].cellKey`, the exact `Uniq-Key` string used for that metric in `rows[].metrics`.
- S3. `widget.metrics[].providerId`, the metric id prefix.
- S4. `widget.providers[].dataSourceId` and `widget.providers[].partId`.
- S5. `widget.pagesComplete` (bool), `widget.pageInfo{pagesFetched, endCursor, truncated, hasNextPage}`,
  and `widget.fetchOutcome` / `widget.fetchReason`.
- S6. `widget.sectionHidden` (bool).
- S7. `widget.widgetTemplateId` and `widget.widgetTemplateLinked`.
- S8. `widget.hasTotalRow` (bool) and `widget.rowKindCounts{data, subtotal, total}`.
- S9. `widget.currencyBasis` (`row-meta` or `absent`) and `widget.currencyCodes[]`.
- S10. `widget.documentIndex`, 0-based ordinal within the pulled widget set.
- S11. `rows[].rowKey`, the row ordinal joined with its dimension values.
- S12. `schemaVersion` 3 on BOTH writers, with all FIVE documented gates widened.
- S13. Pure functions `Build-WidgetInputs` and `Get-UniqKeySeq` above the `-DefineOnly` return, so the
  per-widget pairing and the key derivation are assertable offline.
- S14. `meta.fieldProbe`, behind a default-OFF `-ProbeFields` switch.

## 3. Non-goals (OUT)

- No analyzer behaviour change. `Analyze-SwydoReport.ps1` is touched ONLY to widen its gate.
- No matrix, no aggregation class, no new finding.
- No consumption of any new key. Nothing reads them in this phase; that is what makes P1 dark.
- No change to `widget.dimensions[]`, to the construction of `rows[].metrics` or `rows[].dimensions`,
  or to any existing value or key order.
- No probe on the default path. `-ProbeFields` is opt-in.

## 4. Design

### Data model

**D1 — the per-widget outcome carrier.** `Normalize-Widget` becomes
`Normalize-Widget($wmeta, $obj, $outcome, $index)`. Parameters are APPENDED, never repurposed, per
the convention documented in-source at `Get-SwydoReport.ps1:382-383`.

The carrier matters more than the signature. `$script:lastFetchOutcome` is a SINGLE slot reassigned
on every `Fetch-Widget` return path at `:406`, `:412` and `:485`. Normalization is a separate later
pass at `:911`, by which point that slot holds only the LAST widget's record. Reading it there would
stamp every widget with the final widget's completeness — a fabricated completeness proof, which is
precisely the class the parent spec exists to prevent. Indexing `$script:outcomes[$i]` is no better:
it aligns with `$wids` only by accident, and breaks the moment a `continue` enters the loop.

So P1 adds a pure pairing function above the `-DefineOnly` return:

```
Build-WidgetInputs($wids, $fetched, $outcomes)
  -> @( [ordered]@{ wmeta; obj; outcome; index } ) in $wids order
```

It pairs outcomes to widgets by `$o.id` (the record already carries `id` at `:398`), assigns `index`
as the ordinal within `$wids`, and leaves `outcome` `$null` for a widget with no record rather than
guessing. The run body at `:911` becomes a loop over its result. Both `index` and `outcome` are
guarded with `if($null -ne ...)`, never truthiness, because `0` is a valid `documentIndex`.

There is exactly ONE production call site, at `:911`. The other six `Normalize-Widget` calls are
fixtures in `Test-Extractor.ps1` at `:43`, `:51`, `:57`, `:62`, `:69` and `:79`; a two-argument call
binds `$null` to the new slots and omits the derived keys, which keeps those fixtures valid.

**D2 — section visibility.** `$script:secMap` maps section id to NAME and is read at `:503`; its
value type is not changed. A parallel `$script:secHidden` map is added and initialized to `@{}` beside
it at `:763`. The read is defensive, because `Test-Extractor.ps1` seeds `$script:secMap` by hand and
an unseeded map would otherwise throw under `$ErrorActionPreference='Stop'`:

```
sectionHidden = [bool]$(if($script:secHidden){ $script:secHidden[$wmeta.section] } else { $false })
```

**D3 — `documentIndex` is the ordinal within the PULLED set (`$wids`).** Under a `-Platform` filter
that is a subset, and that is correct rather than a compromise: U9 D2's tiebreak is document order
among the widgets the ANALYZER sees, which is exactly the pulled set.

**D4 — `rowKey` shape.** `"<ordinal>|<dimValue1>|<dimValue2>..."`, ordinal first, dimension values in
declared order. The ordinal makes uniqueness structural; `Row-Label`'s fallback returns the shared
string `(group)`, so a label-only key would collide.

Two mechanics are pinned here because both were measured wrong in review. The separator escape is a
literal string operation, NOT a regex — `-replace '|','/'` treats `|` as alternation, leaves the pipe
intact and injects `/` between every character:

```
$esc = ([string]$v).Replace('|','/')
```

And a zero-dimension widget yields exactly `"0"`, not `"0|"`, so the join is conditional on there
being at least one dimension.

**D5 — one key derivation, no loop rewrite.** `Get-UniqKeySeq($items)` returns the `Uniq-Key`
sequence for a metric or dimension list, and is used ONLY to populate `metrics[].cellKey`. The row
loops at `:523` and `:525` are left byte-for-byte alone. Rewiring them would touch `rows[].metrics`
and `rows[].dimensions`, which §3 forbids. AC1 is the anti-drift gate: it asserts the emitted
`cellKey` equals the key the untouched loop actually produced.

**D6 — completeness is keyed off FETCH INTENT, not normalized kind.** The three `Fetch-Widget` paths
that return `$null` (`:407`, `:413`, and a transport failure) degrade a real data widget to
`kind='unknown'` at `:499` — exactly the widgets whose completeness matters most. So the block is
emitted for every widget whose `visual` is not `TEXT`/`PAGE_BREAK`, the same `$needData` predicate as
`:397`, whatever the resulting `kind`. `fetchOutcome` and `fetchReason` ride alongside so
`kind='unknown'` is distinguishable from "not a data widget".

`Get-WidgetOutcome` at `:268-280` returns `filled`, `empty-resolved`, `rejected` or `incomplete`.
`pagesComplete` answers the PAGINATION question only:

```
pagesComplete = ($outcome.outcome -in @('filled','empty-resolved')) -and ($outcome.reason -ne 'partial-pages')
```

`empty-resolved` is the one honest zero-row answer the state machine produces, and a
`pagesComplete=$true` widget with zero rows is a valid, expected combination. `pagesComplete` proves
pagination was exhausted and NOTHING about whether the row set is the whole set — that distinction is
the parent's rank-3 precondition 1 versus 2.

`truncated` and the final `hasNextPage` have no source on the record today, so `Fetch-Widget` records
them: `$st.truncated` and `$st.hasNextPage` are added to the record at `:398-399` and assigned at
`:473` beside `outcome`/`reason`, and `$st.endCursor` is assigned unconditionally after the
pagination loop rather than only in the truncation branch.

**D7 — currency.** The existing first-wins `break` loop at `:510-511` is left completely untouched.
`currencyCodes[]` is built by a SEPARATE encounter-order pass with an explicit `-notcontains` dedupe,
never `Sort-Object -Unique`, so the array cannot reorder into something that looks like a different
first-wins answer. `currencyBasis='row-meta'` when at least one row carried a code, else `'absent'`.

**D8 — both writers bump, five gates widen.** `schemaVersion` becomes 3 at `:921` (report) and `:867`
(trend), so the tool has ONE schema version. The gates:

| Site | Change |
|---|---|
| `Analyze-SwydoReport.ps1:678` | `-ne 2` becomes `-notin @(2,3)` |
| `ConvertTo-SwydoTrendFacts.ps1:75` | same |
| `skill/SKILL.md:31` | Mode B accepts 2 or 3 |
| `SKILL_BUILD_SPEC.md:32` | contract statement |
| `SKILL_BUILD_SPEC.md:163` | dependency statement |

`SWYDO_REPORT_EXTRACTION_SPEC.md` §8.1, §9.1 and its forward-compat contract at `:313` are prose and
update with them.

**D9 — the field probe, opt-in and bounded.** Behind a default-OFF `-ProbeFields` switch. That is
what makes P1 genuinely dark and satisfies the land-dark rule in `AGENTS.md` §1; the parent's S14
already contemplates P1 landing with `meta.fieldProbe` absent.

Three mechanics are pinned because review measured the naive versions wrong.

*Presence needs POSITIVE evidence, and there are three states.* `Invoke-GQL` returns a body string on
success and throws on HTTP failure, handing the caller no status code, so inferring presence from the
absence of a match records "field exists" for every 401, 5xx or rate limit. The rule:

- `present=$true` only when the parsed body has a non-null `.data` AND no `.errors`.
- `present=$false` only when an `.errors[].message` NAMES the candidate field.
- `present='unknown'` otherwise, with the message in `detail`.

This mirrors the extractor's existing `Probe-WidgetMonths` discipline, where an unsettled probe is
deliberately not read as an answer. Each candidate is wrapped individually, so one failure does not
void the whole probe.

*`node` is a GraphQL LEAF here.* `$script:baseQ` at `:378` selects `data(...){edges{node}...}` with no
sub-selection, so `node` is a JSON scalar and `edges{node{isTotalOfShownRows}}` can never be answered
— it fails on the selection set and the error names `node`, not the candidate. Row-level candidates
are therefore answered from data already in hand: enumerate `$node.PSObject.Properties.Name` on the
first total row and record the observed key set as a `blob-keys` probe.

*The candidate set is the parent's (c3) list, not a substitute for it.* `widget.serverRowTotal` is the
field the parent's F2 resolution and the whole P6 go/no-go depend on, and it must be probed by that
name.

| # | Candidate | Probe form |
|---|---|---|
| 1 | `metrics[].aggregation` | `metrics:fields(socketId:$sid,type:METRIC){edges{node{aggregation}}}` |
| 2 | `widget.dateRange` | `widget(id:"<W>"){dateRange}` |
| 3 | `widget.filters` | `widget(id:"<W>"){filters}` |
| 4 | `widget.segments` | `widget(id:"<W>"){segments}` |
| 5 | `dims[].isPartition` | `dims:fields(socketId:$sid,type:DIMENSION){edges{node{isPartition}}}` |
| 6 | `widget.serverRowTotal` | `widget(id:"<W>"){serverRowTotal}` |
| 7 | `data.totalCount` | `data(...){totalCount}` — ADDED as a seventh, because Relay connections conventionally expose `totalCount` rather than a widget-level field |
| 8 | `rows[].isTotalOfShownRows` | `blob-keys`, not GraphQL |

*Detail is bounded and scrubbed.* `detail` is truncated to 300 characters and has the share-key
pattern stripped, because the extraction document has no scrubber of its own and the probe records a
backend string verbatim.

**D10 — `providers[]` element keys.** `dataSourceId` and `partId` are ADDED to each element object.
No consumer reads the element by shape; `Analyze-SwydoReport.ps1` reads `.id`, `.name` and `.Count`.

### Inventory

| Key | Source already in hand | Line |
|---|---|---|
| `dimensionRefs[]` | `$dims` built as `{name,id}` | `:513` |
| `metrics[].cellKey` | `Get-UniqKeySeq` over `Uniq-Key` | `:358-364` |
| `metrics[].providerId` | metric id prefix | `:516` |
| `providers[].dataSourceId`, `partId` | `source.parts{id ... dataSource{id}}` | `:378`, `:500` |
| `pagesComplete`, `pageInfo`, `fetchOutcome` | the record paired by `Build-WidgetInputs` | `:398-399`, `:473-475` |
| `sectionHidden` | `sections{... isHidden}` | `:756` |
| `widgetTemplateId`, `Linked` | `widgetTemplate{id linked}` | `:378` |
| `hasTotalRow`, `rowKindCounts` | `node.isTotals` / `isSubtotals` | `:521` |
| `currencyBasis`, `currencyCodes[]` | `node.meta.currencyCode` | `:510` |
| `documentIndex` | `$wids` ordinal via `Build-WidgetInputs` | `:911` |
| `rows[].rowKey` | `$dmap` values plus loop ordinal | `:519-523` |

### Migration

A v2 document keeps working: the widened gates accept it and every consumer treats an absent new key
as unknown. No facts output changes, because no analyzer code reads any new key in this phase.

### Rollout

Dark. The only observable difference is the extraction JSON, which gains keys and a version number.
With `-ProbeFields` off by default there is no extra network call and no extra wall clock.

### Files touched (estimate)

| File | Nature |
|---|---|
| `skill/scripts/Get-SwydoReport.ps1` | additive keys, two pure helpers, the probe, signature, version |
| `skill/scripts/Analyze-SwydoReport.ps1` | gate widened, one line |
| `skill/scripts/ConvertTo-SwydoTrendFacts.ps1` | gate widened, one line |
| `skill/SKILL.md` | Mode B accepts 2 or 3 |
| `SKILL_BUILD_SPEC.md` | two contract statements |
| `SWYDO_REPORT_EXTRACTION_SPEC.md` | schemaVersion 3 contract |
| `Test-Extractor.ps1` | additive assertions |
| `.claude/SESSION-KICKOFF.md` | re-stamp plus the assertion baseline |

### Alternatives rejected

- **Re-keying `dimensions[]` to objects.** Breaks the anchored time-dimension guard, the
  `DISC_CROSS_WIDGET` signature and the headline scope string, none of which the suites would catch.
- **Reading `$script:lastFetchOutcome` inside the normalize pass.** Stamps every widget with the last
  widget's completeness.
- **Indexing `$script:outcomes[$i]`.** Aligns with `$wids` only by accident.
- **Rewiring the row loops to consume `Get-UniqKeySeq`.** Touches structures §3 forbids.
- **A default-ON probe.** Up to six unbudgeted 30-second HTTP calls on the production path.
- **`-replace '|','/'` for the rowKey escape.** Regex alternation; measured wrong.
- **`Sort-Object -Unique` for `currencyCodes[]`.** Reorders away from encounter order.

## 5. Production-readiness checklist

- security — the probe records field names and a 300-character scrubbed error excerpt, never a token,
  a header or request variables. Existing `shareKey`/`shareUrl` handling is unchanged.
- perf / scale — zero extra calls by default; with `-ProbeFields` on, seven bounded `-NoRetry` calls.
- a11y — N/A — no UI.
- i18n — N/A — no user-facing strings added.
- error / empty / loading states — a failed candidate records `present='unknown'` rather than voiding
  the probe; a widget with no data still carries `pagesComplete=$false` and its `fetchReason`.
- observability — `pageInfo` and `fetchOutcome` surface per widget what only the run-level
  `meta.incompleteWidgets` roll-up carried.
- risks — the signature change is the only breaking-by-construction edit, mitigated by appended
  parameters and a single production call site updated in the same commit.
- testing + left-shift gates — see §6. Source-text assertions pin both `schemaVersion` literals and
  their writer count, so a third writer cannot appear unnoticed.
- migration / rollback — additive; revert is a revert.
- user docs — `SWYDO_REPORT_EXTRACTION_SPEC.md`, `skill/SKILL.md`, `SKILL_BUILD_SPEC.md`.

## 6. Acceptance criteria

Pre-P1 suite baseline, for the additive contract: Extractor 231, Analyze 467, Closer 129,
TrendAnalyze 68, TrendFacts 24, Archive and Ledger and Sync unchanged.

- AC1. On a widget whose two metrics share a display name, `metrics[].cellKey` holds two DIFFERENT
  keys and each equals the key actually present in that widget's `rows[].metrics`.
- AC2. On a widget with an empty metric name, `cellKey` is the `Uniq-Key` fallback and matches the row
  map key.
- AC3. `rowKey` is exact: a two-dimension widget whose row at ordinal 2 has labels `Alpha` and
  `Brand | Search` yields exactly `2|Alpha|Brand / Search`. A zero-dimension widget yields exactly
  `0`. Uniqueness across rows is asserted as a secondary check.
- AC4. `Build-WidgetInputs` pairs by id: given two widgets whose outcomes differ, each carries its OWN
  `pagesComplete`. Given a `$wids` entry with no matching outcome, that entry's `outcome` is `$null`
  and its `pagesComplete` key is absent.
- AC5. A widget whose fetch returned `$null` and normalized to `kind='unknown'` still carries
  `pagesComplete`, `fetchOutcome` and `fetchReason`.
- AC6. A hidden section's widgets carry `sectionHidden=$true`; an unseeded `$script:secHidden` yields
  `$false` and does not throw.
- AC7. `hasTotalRow` is `$true` when a total row is present and `rowKindCounts` sums to the row count.
- AC8. Rows carrying `USD` then `EUR` yield `currencyCodes=@('USD','EUR')` in that order while
  `currencyCode` stays `USD`.
- AC9. `dimensions[]` is pinned, not diffed: the duplicate-`Campaign` fixture yields exactly
  `@('Campaign','Campaign')` with `[string]` elements, and `dimensionRefs[]` carries both ids.
- AC10. The widget at position 0 carries `documentIndex=0` as a PRESENT key.
- AC11. The analyzer and the trend converter accept `schemaVersion` 2 and 3, and still throw on 1
  and 4.
- AC12. A source-text assertion proves both `schemaVersion=` literals in `Get-SwydoReport.ps1` read 3
  and that there are exactly two such writers.
- AC13. With `Invoke-GQL` stubbed, `Invoke-FieldProbe` records one entry per candidate: a body naming
  the field yields `present=$false`; a clean `.data` body with no `.errors` yields `present=$true`; a
  thrown call yields `present='unknown'` with a `detail` of at most 300 characters and no share key.
  The recorded `field` set is a superset of the parent's (c3) list.
- AC14. `-ProbeFields` is absent by default: a run without the switch emits no `meta.fieldProbe`.
- AC15. `bash tools/run-gates.sh` green, `Test-Extractor` additive on its own count, every other
  suite's count unchanged.

## 7. Gates

`bash tools/run-gates.sh` — the whole standing bar. The commit also re-stamps
`.claude/SESSION-KICKOFF.md` with a `manifest-audit:` delta line and updates its assertion baseline,
because every file P1 touches is on the manifest's watch list.

## 8. Open questions

- The LIVE half of the probe (the parent's AC16) is not observable in this checkout, because
  `skill/archive` is gitignored and absent and no share link is available. P1 lands with
  `meta.fieldProbe` absent and AC13 covering the classification logic offline. This is a documented
  gate exemption, and its compensating manual check is: run `Get-SwydoReport.ps1 -ProbeFields` once
  against any live report and read `meta.fieldProbe` before P6 is specced.

## 9. Revision log

- rev-1 · 2026-08-04 · initial sub-spec derived from ANLZ-aUniformLattice-1 P1 (S1-S14).
- rev-2 · 2026-08-04 · folded adversarial review wf_b63e8c70-87e (3 lenses, 8 batched skeptics, 11
  agents; 37 raw findings, 27 survived, 6 must-fix). Corrections: the outcome carrier was unnamed and
  a literal reading stamped every widget with the last widget's completeness, now a pure
  `Build-WidgetInputs` pairing by id; `serverRowTotal` had been dropped from the probe set and
  `data.totalCount` substituted for it; probe presence inferred existence from a non-match, now
  three-state with positive evidence; `node` is a GraphQL leaf so the row-level probe was
  unanswerable and becomes a `blob-keys` enumeration; D5 rewired the row loops that §3 forbids
  touching; completeness keyed off `kind` missed the `kind='unknown'` degradation. Also: the probe is
  now opt-in behind `-ProbeFields`, the rowKey escape is a literal `.Replace` because `-replace` reads
  `|` as alternation, `pagesComplete` admits `empty-resolved`, `truncated`/`hasNextPage` are now
  recorded on the outcome record, two more `schemaVersion` sites were found in `SKILL_BUILD_SPEC.md`,
  and AC9 became a pin rather than an unobservable byte-diff.

## 10. Reuse audit

None — codebase-map is not adopted; the audit was done by reading source. Wired through: `Uniq-Key`
at `Get-SwydoReport.ps1:358-364` (wrapped in a sequence helper, not reimplemented); the fetch outcome
record at `:398-399` and `:473-475` (extended with two fields it already observed); `$script:secMap`
at `:763` (paralleled, not modified); `Invoke-GQL` at `:101` (reused with its existing `-NoRetry`);
`Get-ExtractionCompleteness` at `:282` (unchanged, still the run-level roll-up, and the precedent for
putting a pure contract function above the `-DefineOnly` return); `Probe-WidgetMonths` at `:641-652`
(the precedent for treating an unsettled probe as not-an-answer).
