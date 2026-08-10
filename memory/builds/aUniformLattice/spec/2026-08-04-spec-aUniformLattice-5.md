# ANLZ-aUniformLattice-5 — P4: make the per-row second layer addressable

**Status:** SPECCED · rev-2 · 2026-08-05 · node a · Tier-2 · base 89877d4a · parent ANLZ-aUniformLattice-1 · review wf_dc495cd4-541

## 1. Goal

Give the per-row data already in facts a stable identity so it can be addressed by
`(platform, metricId, row)`. Today `breakdowns[].rows[].values` is keyed by metric DISPLAY NAME, the
block carries no metric ids at all, and a row has no unique key — so the "layered" half of the
owner's target is not referenceable. All three additions are additive.

## 2. Scope (IN)

- S1. `breakdowns[].rows[].valuesById`, the same cells keyed by metric id, alongside the untouched
  display-name-keyed `values`.
- S2. `breakdowns[].metricIds[]`, parallel and index-aligned to the untouched `metricNames[]`.
- S3. `breakdowns[].rows[].rowKey`, copied from P1's extractor key when present.
- S4. `breakdowns[].rowKeyBasis`, `extractor` or `absent`, so a consumer can tell "this row has no key"
  from "this document predates row keys".

## 3. Non-goals (OUT)

- `values`, `metricNames[]`, `label`, `rowCount`, `shown` and `note` are untouched. No re-keying.
- No change to which rows are selected, ordered, or capped. `Get-Breakdown`'s top-N cap, its ordering
  metric and its force-include of finding-referenced labels all stay exactly as they are.
- No matrix cell references the second layer yet. Rank 3 is WONTDO, so no cell has a
  `contributingRowKeys` to record; the master spec's S26 is therefore vacuous and is not built.
- No `timeSeries` change. That block is uncapped and separately shaped; addressing it is out of scope.
- No closer or template change.

## 4. Design

### Data model

`Get-Breakdown` already builds a per-row `$vals` map keyed by `$m.name`. P4 builds a second map in the
same loop keyed by `$m.id`, holding the SAME cell objects, and emits both. The two maps are built from
one iteration over `$mets`, so they cannot drift.

| Key | Shape | Note |
|---|---|---|
| `metricIds[]` | string array | index-aligned with `metricNames[]` |
| `rows[].valuesById` | map metricId to the same cell object as `values` | a metric with no usable cell is absent from BOTH maps |
| `rows[].rowKey` | string | from `rows[].rowKey` on the extraction |
| `rowKeyBasis` | `extractor` or `absent` | absent on a schemaVersion-2 document |

**D0 — key order is pinned.** Block: `widgetId, dimensions, metricNames, metricIds, rowCount, shown,
rowKeyBasis, rows`, with the conditional `note` last. Row: `label, values, valuesById`, then `rowKey`
only when present. `metricIds` sits adjacent to `metricNames` so the index alignment is legible.

**D1 — `rowKey` is copied, never recomputed.** P1 emits it at extraction where the row ordinal is free
and unambiguous. Recomputing it here would key off the ALREADY-FILTERED, ALREADY-SORTED, ALREADY-CAPPED
breakdown row set, so the ordinal would not match the extraction's and two documents describing the
same widget would disagree. On a schemaVersion-2 document the key is absent and `rowKeyBasis` says so.

**D2 — `valuesById` reads by `cellKey`, NOT by display name.** This is the correction that makes P4
worth building. `Get-Breakdown` fetches a row cell with `Row-Cur $r $m.name`, while the extractor keys
the row map with `Uniq-Key`, which renames a collider to `<name> [<id>]`. So on a widget with two
metrics sharing a display name, BOTH loop iterations resolve to the first metric's column. Writing
that into `valuesById[$m2.id]` would publish metric 1's number under metric 2's id, formatted with
metric 2's unit — a stable, machine-addressable, confidently WRONG attribution. That is strictly worse
than the collapse it was meant to fix.

`valuesById` therefore reads by `metrics[].cellKey`, the exact key P1 emits for this purpose. `values`
keeps the display-name read byte-for-byte, so the two maps DELIBERATELY diverge on a collided name:
`values` collapses to one entry, `valuesById` carries both, each with its own number. That divergence
is the point.

On a schemaVersion-2 document there is no `cellKey`. Where the display name is unique the name is a
safe key and is used; where it collides there is NO way to disambiguate, so the metric is OMITTED from
`valuesById` entirely. Fail-closed: an absent entry is honest, a guessed one is not.

**D3 — `rowKeyBasis` is derived from the EMITTED ROWS, not from `meta.schemaVersion`.**
`Get-Breakdown` never receives the document, and under `-DefineOnly` — which is how every existing
unit test calls it — no `$doc` exists to read. So the basis is `extractor` when a selected row carried
a non-empty `rowKey` and `absent` otherwise. This is observable in a unit test, which a schemaVersion
read would not be.

**D4 — the cost is duplicated cell content.** `valuesById` holds separately-formatted cells rather
than shared references, because a collided name resolves to a different source column. The emitted
JSON therefore carries each breakdown cell twice. That is a real cost, measured in AC6, not waved at.

### Inventory

`Get-Breakdown` in `skill/scripts/Analyze-SwydoReport.ps1`: the metric loop that writes
`$vals[[string]$m.name]`, the row assembly that writes `label` and `values`, and the block assembly
that writes `widgetId`, `dimensions`, `metricNames`, `rowCount`, `shown`, `rows` and the truncation
`note`. Nothing else is touched.

### Migration

A schemaVersion-2 document yields `rowKeyBasis='absent'` and no `rowKey` on any row; `valuesById` and
`metricIds[]` are still emitted, because they derive from the metric list rather than from any new
extractor key.

### Rollout

Dark. Every addition is a new key; nothing reads them. The facts document grows by roughly the size of
the breakdown block, which AC6 measures.

### Files touched (estimate)

| File | Nature |
|---|---|
| `skill/scripts/Analyze-SwydoReport.ps1` | `Get-Breakdown` only |
| `Test-Analyze.ps1` | additive assertions |

### Alternatives rejected

- **Re-keying `values` to metric ids.** Changes default output and costs P4 its dark status; it would
  have to ride P5's waiver instead, for no benefit that a sibling map does not give.
- **Recomputing `rowKey` from the breakdown row set.** The ordinal would disagree with the extraction's.
- **Emitting only `valuesById` and dropping `values`.** Same waiver problem, and the template and
  closer both read the display-name map today.

## 5. Production-readiness checklist

- security — N/A — no new I/O and no new string source.
- perf / scale — one extra dictionary write per cell; the real cost is serialized size, in AC6.
- a11y — N/A — no UI.
- i18n — this is the change that REMOVES a display-language dependency from row addressing.
- error / empty / loading states — a widget with no dimensions still returns `$null` from
  `Get-Breakdown` exactly as today.
- observability — a row can finally be named in a finding or an anchor.
- risks — facts size. Measured, not asserted.
- testing + left-shift gates — the duplicate-display-name case gets an explicit test proving
  `values` still collapses and `valuesById` does not.
- migration / rollback — additive; revert is a revert.
- user docs — none; nothing user-facing reads it yet.

## 6. Acceptance criteria

- AC1. `values`, `metricNames[]`, `label`, `rowCount`, `shown` and `note` are byte-identical before
  and after P4 for the same input.
- AC2. `metricIds[]` is index-aligned with `metricNames[]`, same length, same order.
- AC3. Stated per METRIC, not as a count identity, because the two maps legitimately differ in count
  on a collided name: for every metric whose cell is non-null AND whose display name is unique in the
  widget, `values` holds it under its name and `valuesById` holds an equal cell under its id.
- AC4. On a widget with two metrics sharing a display name, `values` has ONE entry (the existing,
  unchanged collapse) while `valuesById` has TWO, and each id carries its OWN number — the second
  metric's value is recoverable only from `valuesById`.
- AC4b. With NO `cellKey` (schemaVersion 2) and a collided display name, BOTH colliding ids are
  OMITTED from `valuesById`. Neither is addressable, so no wrong number is published.
- AC5. `rowKey` is present and equals the extraction's `rows[].rowKey` when the rows carry one, and
  `rowKeyBasis='extractor'`. Otherwise `rowKey` is OMITTED from every row — never emitted as `null` —
  and `rowKeyBasis='absent'`.
- AC6. The facts document still serializes without hitting the `ConvertTo-Json -Depth` ceiling, and
  the measured size delta on the live QCU extraction is recorded here and in the commit message.
  MEASURED 2026-08-05: 185,658 -> 318,104 bytes, a 71% increase, all of it duplicated breakdown cell
  content. This is the largest single cost in the program and it lands in the model's context budget.
  P5 must decide what the analyst brief actually reads; it is NOT obliged to feed `valuesById` to the
  model just because it exists in facts.
- AC7b. Block and row key order match D0 exactly.
- AC7. A time-dimension widget still produces BOTH a breakdown and a `timeSeries` block, and
  `timeSeries` is unchanged.
- AC8. `bash tools/run-gates.sh` green; `Test-Analyze` additive, every other suite unchanged.

## 7. Gates

`bash tools/run-gates.sh` — the whole standing bar.

## 8. Open questions

none — the master spec's F5 (reference versus copy for the second layer) is answered by
construction: P4 makes the existing block addressable rather than adding a second copy of the rows, so
no reference-versus-copy decision remains.

## 9. Revision log

- rev-1 · 2026-08-05 · initial sub-spec derived from ANLZ-aUniformLattice-1 P4 (S24-S26), with S26
  dropped as vacuous because rank 3 is WONTDO.
- rev-2 · 2026-08-05 · folded adversarial review wf_dc495cd4-541 (2 lenses, 3 batched skeptics, 5
  agents; 15 raw findings, 14 survived, 3 must-fix). The load-bearing correction: rev-1 had
  `valuesById` reading cells by DISPLAY NAME, which on a collided name would have published metric 1's
  number under metric 2's id — a machine-addressable wrong attribution, strictly worse than the
  collapse it was meant to fix. It now reads P1's `cellKey`, with a name fallback only where the name
  is unique and an explicit OMISSION where it is not. AC3 was restated per-metric because the two maps
  legitimately differ in count. `rowKeyBasis` is derived from the emitted rows rather than from
  `meta.schemaVersion`, which `Get-Breakdown` cannot see under `-DefineOnly`. `rowKey` is omitted
  rather than null. Key order is pinned in D0. AC6 was retargeted from an unfailable depth check to
  the measured byte delta.

## 10. Reuse audit

None — codebase-map is not adopted; audit by reading source. P4 wires entirely through the existing
`Get-Breakdown`, reusing its metric loop, its already-selected row set and the cell objects it already
formats. `rowKey` is reused from P1's extractor output rather than recomputed. No new function, no new
file, and no second row payload.
