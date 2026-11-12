# ORCH-aLucidCounsel-1 review 2 - adversarial review of the build before landing

**Status:** CLOSED - rev-1 - 2026-11-12 - node a - Tier-2 - base 243c00b8

## 1. What ran

At the owner's instruction, on commit 24af2d4: three independent reviewers with distinct lenses,
one verifier per reviewer, one adjudicator. All were read-only subagents with fresh context.

| Role | Lens | Findings |
|---|---|---|
| Reviewer A | Instruction coherence and executability against the closer | 12 should-fix, 5 nits |
| Reviewer B | Analytical method and the specimen, as a senior paid-media analyst | 2 blockers, 12 should-fix, 1 nit |
| Reviewer C | Invariants (no arithmetic, credentials), failure modes, governance | 7 should-fix, 7 nits; gates run GREEN 19/19 |
| Verifiers | Tried to refute each finding against the files; reproduced closer claims with synthetic facts | None fully refuted; 18 confirmed, the rest held in part |
| Adjudicator | Ruled fix now / follow-up / reject, resolved conflicts | Land after the fixes, on four conditions |

## 2. What the verifiers corrected

- B1 (no path without a comparison) is a missing branch, not a missing rule: should-fix, not blocker.
- B2 (no cross-platform reasoning) is confirmed but untested by any specimen.
- The short version is not always global scope: with a single-platform title it is in platform scope.
- `-Replace` on the derived-metric tool replaces the whole block and refuses an empty request file.
- The untraced Recommendations region predates this unit and is test-pinned; the unit enlarged it.
- Missed by the reviewers: AGENTS.md section 1, "Tier-2 ships behind a default-OFF flag".

## 3. Fixed in this round (spec rev-2, S5)

| Group | Fix | Home |
|---|---|---|
| Derived requests (A3, B7, C3) | Step 2a opens to analysis-driven requests, `source: analysis`, drop unused entries, not for trend facts | `skill/SKILL.md` 2a |
| `noted` disposition (A5, C7) | Worksheet only, one exception for a gap that limits a conclusion | playbook Step D |
| No comparison, quiet month (A8, B1, C6) | "Read the levels" pass; a no-comparison branch; short report when little moved; review check 1 covers figure-free comparisons | playbook Step B, template, SKILL 4b |
| Scope traps (A1, A2, A4) | No platform name in an insight heading; no derived or estimate figure in the short version; derived sentence inside the insight; refused no-platform entry to Data notes | template |
| Reviewer hand-off (A9, C4, C5) | Five paths and the voice; a subagent contract quoted in every prompt; fallback to a declared self-review; delivery states which review ran | SKILL 4b, 6 |
| Review quality (B9) | Reviewer writes its top three from the facts first; changed sentences are re-checked; best reading at stated confidence | SKILL 4b |
| Hypotheses (B8) | Test an explanation against its own predictions; say which way the facts lean; at most two open rivals in the report | playbook Step C |
| Advice (B5, C1) | A question the account team can answer is not a client recommendation; no measured figures in Recommendations | playbook Steps C and E, template |
| Coverage (B10) | One ledger line per breakdown; read impression share by every cut | playbook Step F, lens |
| Reasoning errors (B6, B12, C2) | Words that hide arithmetic (quantity, ranking, totality); cuts are not causes; percent against points; small bases; platform conversions; calendar in words only | playbook error list |
| Account model (B3, B11, B14) | Objective and target; chain per category; unanswerable lens questions become questions | playbook |
| Fan-out and trend (A6, A7, C10) | Analysts return text, orchestrator merges and owns step 2a; Mode C worksheet and step 8 | SKILL 3b, 8 |
| Shipped text (A10, A11, A13, A14, A15, C11, C12, C14) | Examples without banned words; true heading legend; placeholders for client figures; one comparison rule; `AGENTS.md` names the playbook | template, playbook, AGENTS.md |

The Estimates block of the template is byte-identical to base (checked by script), so Test-Forecast
C8 is unaffected.

## 4. Deferred and rejected

Deferred to the backlog as ORCH-aLucidCounsel-4 to -11: cross-platform step and section (B2);
continuity with the previous report and worksheet archiving (B4, A16); an interactive question
step (B5); contribution figures from the analyzer (B6); lenses beyond search (B11, A17); closer
hardening for the reproduced scope and comparison gaps (A1, A2, C6); derived metrics for trend
facts; the flag question. A whole-shape closer fixture (C13) joins -3 because it moves pinned
suite counts. Rejected: editing `SKILL_BUILD_SPEC.md`, a historical record; promoting the
Recommendations sub-sections to `##`, which would fail proposed thresholds and change pinned
closer behaviour.

## 5. Specimen regenerated under the fixed instructions

The Rentex October 2026 report was rewritten from an updated worksheet. Closer: 141 of 141 numbers
traced, 0 violations. A fresh reviewer, run exactly as the new step 4b prescribes (five files, the
contract, top three written first), matched every figure it checked and returned 23 problems: 2
blockers, 17 should-fix, 4 nits.

| Class | Example | Disposition |
|---|---|---|
| Period scope | calls "rose in the weeks when tracking was lost", from full-window totals | Fixed |
| A guess about our own account | the price rise put down to "a change inside the account" | Fixed in part: evidence added, the lookup is named as under way |
| Rival dismissed on one row | competition ruled out against account-level signals | Fixed: carried open, recommendation made conditional |
| Template order | outage not stated first in the short version | Fixed |
| Overlapping cuts | keyword and campaign views counted as separate savings | Fixed |
| Inference hardening | forms-on-desktop became a recommendation to protect desktop | Fixed: recast as no change yet |
| Sections disagreeing | narrative and Estimates on whether form leads really fell | Fixed |
| Rejected | a threshold for "material"; a form-only estimated total; keyword-level location of the fall | Reasons in the worksheet's Review log |

Changed sentences were re-checked by the author, which removed one more hidden-arithmetic word.

Not met: the insight narrative is about 1,500 words against the template's guide of 800 to 1,200.
The review's additions put it there. The old specimen ran to about 1,650.

## 6. What it shows about the unit

- The independent review earns its place again: a draft that traced 128 of 128 numbers still
  claimed a period the data does not split.
- The reviewer's sharpest finding is a limit of the tool, not of the text: the agent cannot see
  the account, so "what changed" stays a question. The fix in scope sends those questions to the
  user in the delivery message; the real fix is the interactive step in ORCH-aLucidCounsel-6.
- Review pushes length up. The length guide and the cap on open rivals pull against it; one
  specimen is not enough to say the balance is right.
- Still untested: multi-platform, SEO, email, an untrusted comparison, a quiet month, trend mode.

## 7. Left-shift

No gate can cover these classes. The confirmed ones are lines in `skill/analysis-playbook.md`
under "Reasoning errors to check for" and checks in `skill/SKILL.md` step 4b. The three closer
gaps the verifiers reproduced are gateable and are logged as ORCH-aLucidCounsel-9.
