# ANLZ-aDerivedMetric-1 review - adversarial review of the derived-metric feature

**Status:** CLOSED - rev-1 - 2026-11-12 - node a - Tier-2 - base c1dbe13e

## 1. What ran

Three independent finder subagents with distinct lenses, three independent verifier subagents that
reproduced each lens's findings with their own scripts, and one adjudicator subagent that ruled on
every finding and on the author's proposed dispositions. The lenses were: computation and
resolution logic of `Resolve-SwydoMetric.ps1`; the trust boundary of the closer's derived rules
and the facts splice; documentation, operator usability and test quality. The third lens
mutation-tested the unit suite on a scratch copy: 14 of 14 sampled single-line mutations survived
the pre-review suite.

## 2. Findings ruled must-fix, and what changed

- **A numeric row label 0 emptied the filter**, so the account total was published as a filtered
  figure (reproduced on real facts: weekday rows "0".."6"). One label normaliser now serves
  validation, routing and phrasing; duplicates are malformed; an empty filter is refused inside
  the rows route.
- **Integer cells were treated as plus or minus one half.** Rows that missed the account total by
  up to n/2 passed reconciliation, exact figures were hedged, and Rentex showed about $42.26 where
  the data pin $42.27. Integer displays are now exact, the subtotal is bounded twice and
  intersected, and the convention is guarded (start-up canary, pinned facts versions, drift test).
- **Request text became citable.** The closer indexed entry label, notes and refusal reasons, so a
  number typed into a request traced on the anchored line, even for a refused entry. Only
  tool-computed displays, facts values, tool-authored notes and the facts-built formula are indexed.
- **A request-named widget resolved an invented filter**, with a comparison. The widget-only route
  is removed; entries from the older tool version are rejected by the closer.
- **The marker and "about" checks were satisfied by text the client never sees or by sentences
  meaning the opposite** (a comment spanning lines; unrelated "not ... reported"; "about" far from
  the figure; a range end quoted as the figure). The marker is a closed three-form grammar on the
  visible line, "about" must sit directly before each approximate figure or the range must be
  written out, a rounder form of a figure is rejected, and a comment spanning lines is a violation.
- **An anchor anywhere counted as surfacing.** It now counts only on a traced body line in the
  entry's own platform section; a refused entry's line must state the refusal and carry no number;
  Recommendations rejects derived anchors and derived figures.
- **Ratio metrics passed as summable on facts without a coverage record**; the analyzer's own
  classifier now decides. **Trend facts were accepted**; `meta.tool` is checked.
- **Two reconciling breakdowns that disagree** were resolved by taking the first; now refused, and
  the previous period must use the breakdown the current period used.
- **Any error exited 1**, the same code as "refused, block written"; errors now exit 2 with
  nothing written, through a temporary file.
- **Docs told the operator to do things the closer rejected** (a wrapped example line, a marker-less
  follow-on line). Rewritten against the enforced rules; the example line is tested on real facts.

## 3. Ruled should-fix and done

Time-series check on every dimension and on the rows route; separate refusal reason for a negative
numerator; `decimals` restricted to plain number results; invariant delta formatting; strict
display parser; case-sensitive id check; `-Replace` with a guard for client-note entries; fan-out,
anchor and violation-type documentation; a negative derived value quoted with its sign.

## 4. Not done

- A whole-number derived result under 100 is not tokenised by the closer (ruled should-fix;
  tracked with ANLZ-aModeledGap-3).
- The post-splice integrity check in the resolver's run block has no test that can reach it
  without fault injection.
- The field verifier still shares two readings with the tool (ANLZ-aDerivedMetric-4).

## 5. Evidence after the fixes

`tests/Test-ResolveMetric.ps1` 264 passed. `tools/Verify-DerivedMetrics.ps1` over the 12 archived
facts files: 2,514 requests, 2,289 resolved, 225 refused, 60,433 checks, 0 failed, including 195
comparisons with the platform's own figures. Rentex October 2026 cost per conversion excluding
'Local actions - Directions': $42.27, exact, cross-check agreed; previous period $24.76; +70.7%.