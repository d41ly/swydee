# ANLZ-aUniformLattice-8 — lean facts: stop duplicating every breakdown cell

**Status:** SPECCED · rev-2 · 2026-08-05 · node a · Tier-2 · base 19e907fe · parent ANLZ-aUniformLattice-1 · review wf_a087ecf9-cf5

## 1. Goal

Cut the facts document back to roughly its pre-P4 size by emitting `valuesById` only where it carries
information `values` cannot, and tell the analyst brief precisely what to read. The facts document is
the report model's entire context; 41% of it is currently a duplicate nothing reads.

## 2. Scope (IN)

- S1. `breakdowns[].rows[].valuesById` carries ONLY metrics whose display name COLLIDES within the
  widget. A metric with a unique display name is addressed through `metricIds[]`/`metricNames[]`.
- S2. `breakdowns[].valuesByIdScope`, one of `collisions-only` or `none`, so a consumer knows the rule
  rather than inferring it from an empty map.
- S3. `skill/SKILL.md` states what the analyst reads and what it skips, so the trim is a saving in the
  model's ATTENTION as well as its bytes.
- S4. `meta.factsVersion` 1 to 2. This is the first SUBTRACTIVE change to the facts shape, so the
  marker that names the shape has to move.
- S5. The measured before/after and the ENUMERATED flip set, recorded here and in the commit.
- S6. The `valuesById` read becomes INDEPENDENT of the display-name read. Review found the shared
  scalar guard silently dropped a collided metric's value; see D6.
- S7. Three shipped `Test-Analyze` pins are amended, not loosened: the `factsVersion` literal and the
  two P4 assertions that pinned `valuesById` as a TOTAL mirror. Each carries a superseded-by comment.
- S8. The manifest's waiver ledger gains this as the third disclosed change.

## 3. Non-goals (OUT)

- `values` is untouched, and stays keyed by display name.
- `metricNames[]`, `metricIds[]`, `rowKey`, `rowKeyBasis`, `label`, `rowCount`, `shown` and `note` are
  untouched. The id-addressing capability P4 shipped is PRESERVED, not withdrawn — see D1.
- `platforms[].metrics` is not trimmed. Its provenance is 12,912 bytes against `valuesById`'s 129,815;
  cutting it would be effort in the wrong place and would remove the coverage record the analyst was
  just told to read.
- No `headline` change, no finding change, no closer change, no template change.
- No change to which rows a breakdown selects, orders or caps.

## 4. Design

### Data model

**D1 — the capability survives; only the duplication goes.** P4 added `valuesById` so a consumer can
address a row cell by metric id instead of by display name. For a metric whose display name is UNIQUE
in its widget, that addressing already exists without any per-row payload: `metricIds[i]` and
`metricNames[i]` are index-aligned, so a consumer holding an INDEX has both the id and the name.

Two precisions the review forced, because this is the load-bearing sentence of the whole subtraction.
The lookup is stated index-keyed rather than id-keyed: `metricIds[]` is built from `$mets` with no
dedupe, so ids are not guaranteed unique within a widget. Index-keyed phrasing describes strictly MORE
capability than the map it replaces, since the block arrays expose both indices where `valuesById`
exposed one arbitrary entry. And `metricIds[i] -> metricNames[i]` is TOTAL while
`values[metricNames[i]]` is PARTIAL: a metric whose row cell is null or non-numeric is skipped by the
scalar guard, so it stays in both block arrays and is absent from `values`. Absence there means "no
usable cell for this metric in this row", not a producer error. The same guard skipped the id map too,
so dropping the duplicate loses nothing in that case.

The per-row map is load-bearing only for a COLLIDED display name, which is precisely the case `values`
cannot express because its second write overwrites the first.

So `valuesById` becomes collisions-only. The information content of the document is unchanged; the
duplication is gone.

**D2 — `valuesByIdScope` exists so an empty map is not ambiguous.** Without it, a consumer seeing
`valuesById: {}` cannot tell "no collisions in this widget" from "this document predates the id map"
from "the producer decided to omit it". The marker is `collisions-only` when the rule was applied and
`none` when the widget had no metrics at all. It sits beside `rowKeyBasis`, which exists for the same
reason and was ratified for the same reason in P4 D3.

**D3 — measured, not estimated.** On the live QCU report:

| Block | Bytes |
|---|---|
| `values` across all breakdown rows | 113,181 |
| `valuesById` across all breakdown rows | **129,815** |
| `platforms[].metrics` (both platforms) | 36,089 |
| matrix provenance inside those cells | 12,912 |
| whole document | 318,082 |

`valuesById` is LARGER than the `values` it duplicates, because its keys are full metric ids
(`google-adwords:cost_micros`) where `values` uses short display names (`Cost`). It is 41% of the
document. The same report has 161 metrics across its dimensioned widgets and **zero** display-name
collisions, so under S1 every `valuesById` on it is empty and the whole 129,815 bytes is reclaimed.

**D6 — the id read is now INDEPENDENT of the name read, and that is a correctness fix.** The P4 loop
shared one scalar guard: it read the DISPLAY-NAME cell first and `continue`d on null, before the id
path ever ran. So on a row where the FIRST colliding metric's column was null, the second metric's
value was dropped even though its own `cellKey` resolved — losing data in exactly the case the map
exists for. Reproduced by the review. The two reads are now separate, so `values` keeps its behaviour
byte-for-byte and `valuesById` recovers the collided metric regardless.

**D4 — why this is a subtractive change and needs its own marker.** P3 and P4 were additive: a
consumer that did not know a key simply ignored it. This REMOVES content a consumer could have read.
Nothing does read it — the closer indexes named keys and never sees it, the template forbids quoting
it, and P6's WONTDO means no matrix cell references a row — but "nobody reads it today" is not the
same as "the shape did not change". `meta.factsVersion` 1 to 2 is the honest marker, and it is the
right one rather than `canonicalVersion` (which names the headline algorithm, untouched here) or
`matrixVersion` (which names the matrix algorithm, also untouched).

**D5 — the analyst brief.** The trim is bytes; the brief is attention. `skill/SKILL.md` gains an
explicit read/skip list so the model is not left to infer which of a dozen keys matter. It reads
`headline` and `findings` for numbers, `platforms[].metrics` for coverage, and `breakdowns[].rows[]`
`label`+`values` for per-row narrative. It skips `valuesById`, `rowKey`, `metricIds`, `basis`,
`contributingWidgetIds`, `observedOnWidgetIds` and `coverageBasis` — all machine-addressing fields
with no narrative content.

### Inventory

`Get-Breakdown` in `skill/scripts/Analyze-SwydoReport.ps1` — the `$valsById` write and the block
assembly. The `$nameCount` map that decides collisions already exists there, added by P4.
`skill/SKILL.md` — the analyst brief. `meta.factsVersion` — one literal.

### Migration

Additive-key consumers are unaffected. A consumer that wanted id-addressing follows D1's two-step
lookup for a unique name and the per-row map for a collided one. `factsVersion` 2 self-describes.
Archived facts are not touched, per U9 D10/D11.

### Rollout

One phase, one commit. It changes default output, so it needs the measured flip set of S5 before it
lands — the third disclosed change under the manifest's waiver rule.

### Files touched (estimate)

| File | Nature |
|---|---|
| `skill/scripts/Analyze-SwydoReport.ps1` | `Get-Breakdown` valuesById gate, `factsVersion` |
| `skill/SKILL.md` | the analyst read/skip list |
| `Test-Analyze.ps1` | collision/non-collision assertions, size pin |

### Alternatives rejected

- **Dropping `valuesById` entirely.** Withdraws the one case where it is load-bearing, and re-opens
  the wrong-number path P4 exists to close.
- **Gating it behind a `-Lean` switch.** Two output shapes for one tool, and the default would still
  be the wasteful one.
- **Trimming `platforms[].metrics` instead.** 12,912 bytes against 129,815, and it is the block the
  analyst was just told to read.
- **Making the analyst brief the ONLY fix.** The single-pass path reads the whole facts document, not
  a slice, so a brief-only change saves nothing on a one-category report.
- **Emitting `valuesById` as id -> name pointers instead of cells.** Still per-row payload for
  information the block-level arrays already carry.

## 5. Production-readiness checklist

- security — N/A — removes content, adds no string source.
- perf / scale — strictly less work and less output.
- a11y — N/A — no UI.
- i18n — unchanged; the collided-name case still resolves by id, not by language.
- error / empty / loading states — `valuesByIdScope` makes the empty map unambiguous.
- observability — the scope marker states the rule in-band.
- risks — a consumer that assumed `valuesById` was total would break. None exists in-repo, verified by
  grep; the marker is what makes the assumption checkable for anything out-of-repo.
- testing + left-shift gates — a size pin so a future change cannot silently re-inflate the document.
- migration / rollback — revert is a revert; `factsVersion` self-describes.
- user docs — `skill/SKILL.md`.

## 6. Acceptance criteria

- AC1. On a widget with NO colliding display names, every row's `valuesById` is empty and
  `valuesByIdScope` is `collisions-only`.
- AC2. On a widget WITH a colliding display name, `valuesById` carries exactly the colliding metric
  ids — each with its OWN value — and nothing else.
- AC3. `values`, `metricNames[]`, `metricIds[]`, `rowKey`, `rowKeyBasis`, `label`, `rowCount`, `shown`
  and `note` are byte-identical before and after.
- AC4. `headline`, `platforms[].metrics` and every finding are byte-identical before and after.
- AC5. `meta.factsVersion` is 2.
- AC6. MEASURED against a baseline generated from `main` on the SAME extraction, not against an older
  artifact. Result: **317,025 -> 198,336 bytes, 37.4% smaller, 118,689 reclaimed**, with the
  `valuesById` payload going 129,815 -> 286 (the residue is one empty map per row). The document
  remains 12,678 bytes above the pre-P4 185,658, which is the addressing capability P4 added and this
  unit deliberately keeps: `metricIds[]`, `rowKey`, `rowKeyBasis` and `valuesByIdScope`.
- AC6b. THE ENUMERATED FLIP SET, asserted by diff rather than inspected. Exactly three things move:
  every dimensioned-widget breakdown row loses its `valuesById` body; every breakdown block gains
  `valuesByIdScope`; `meta.factsVersion` goes 1 to 2. `meta` otherwise, `findings`, `headline`,
  `platforms[].metrics`, `timeSeries` and every other breakdown key are byte-identical. Verified True.
- AC7. A re-inflation guard in `Test-Analyze`: on a no-collision fixture, no metric id appears as a
  ROW-level key in the serialized rows, so a future change cannot silently restore the duplication.
- AC8. `bash tools/run-gates.sh` green. `Test-Analyze` is net-additive EXCEPT three named amended
  pins: the `factsVersion` literal at its e2e14 block, and the two P4 assertions that pinned
  `valuesById` as a total mirror of `values`. Each is amended with a superseded-by comment, not
  deleted. Every other suite unchanged.
- AC9. On a collided display name whose FIRST column is null in a row, `valuesById` still carries the
  SECOND metric's own value — the D6 correctness fix.

## 7. Gates

`bash tools/run-gates.sh` — the whole standing bar.

## 8. Open questions

none — D1 establishes that the capability is preserved, and the measurement in D3 establishes that
the duplication is where the bytes are.

## 9. Revision log

- rev-1 · 2026-08-05 · initial spec, from the measured facts composition recorded in D3.
- rev-2 · 2026-08-05 · folded adversarial review wf_a087ecf9-cf5 (2 lenses, 4 batched skeptics, 6
  agents; 17 raw findings, 6 survived, 1 must-fix). The must-fix: the `factsVersion` bump and the trim
  break three SHIPPED assertions the spec never listed, so AC8's "additive" claim was false and the
  gate would have gone red on landing; they are now named and amended. The most valuable finding was
  not the must-fix: the P4 loop shared one scalar guard between the name read and the id read, so a
  collided metric whose first column was null lost its value entirely. Since this unit makes
  `valuesById` the ONLY carrier for the collided case, that latent defect is fixed here rather than
  documented (D6). D1's "total lookup" was imprecise in two ways and is now stated index-keyed with
  the partial-`values` caveat spelled out. AC6 became a measurement against a baseline built from
  `main` on the same extraction, after the first comparison used a stale artifact predating the
  closing-review conflict fix and showed a false difference.

## 10. Reuse audit

None — codebase-map is not adopted; audit by reading source. The change reuses the `$nameCount`
collision map P4 already builds in `Get-Breakdown`, and the block-level `metricIds[]`/`metricNames[]`
alignment P4 already emits, as the addressing path for non-collided metrics. `valuesByIdScope`
mirrors `rowKeyBasis`, the marker P4 introduced for exactly this ambiguity. No new function, no new
file, no new predicate.
