# Tier-2 review — ORCH-aFlattenedLedger-1 rev-4

**Verdict: SAFE AFTER EDITS.** 28 raw findings, 7 refuted by the skeptic pass, 14 confirmed and
folded into rev-5. Reviewed at `df451d3` by node `a`, session `aWiredLineage`, 2026-08-10.

Shape: five primed finder lenses (measurements · migration-coverage · gate-reachability ·
internal-consistency · data-loss) run concurrently under a cap-5 bound, then batched skeptics
prompted to REFUTE, then one synthesis pass. 12 agents total.

The design needed no re-specification. The per-file migration map, the U1+U2+U3 atomicity envelope,
the FAMILY-qualifier rule and the four ratified forks all held under verification. What the spec
carried was one destructive instruction and a cluster of stale counts.

## The blocker

**`kit-dogfood-parity.test.sh --render` writes toward the KIT, not toward the tree.** rev-4 §4 said
to run it once in U1, placing the step before the template-replacement instruction. Its body is
`norm "$live" > "$ship"`: the live `memory/*` copy overwrites the shipped `memory-tree/*.template.md`.
Run in rev-4's order on a fresh install, it reinstates swydee's 1.4 templates over the 2.2 ones —
putting `## 10. Reuse audit` back OUTSIDE the fenced skeleton, which is the exact defect §4 spends
fifteen lines justifying the fix for — and then reports parity GREEN, because both sides now hold the
broken text. Nothing catches it: the leg is absent from `tools/gate-legs.json` and check 12's canon is
hardcoded in the engine.

This was not theoretical. **The session's own U1 rehearsal ran `--render` and corrupted its kit
copy**: `memory-tree/SPEC-TEMPLATE.template.md` went to md5 `a144b5e4…` against upstream's
`44e8c85d…`, in a clone where the live docs had already been replaced from 2.2 — so even the
supposedly safe ordering is not safe. The fix is a deletion, not a reordering: replace the two live
docs from the templates, run plain `kit-dogfood-parity.test.sh`, and never pass `--render` in this
repo, which does not author the kit.

## Confirmed findings

| # | sev | finding |
|---|---|---|
| 1 | blocker | `--render` clobbers the 2.2 templates with 1.4 copies, then reports green |
| 2 | major | `builds/aFlattenedLedger/README.md` already carries front matter AND a marker pair; authoring a second pair makes `gen_build_index.py` raise `expected exactly one marker pair, found 2` and render nothing |
| 3 | major | The ledger shard is named as the source for `streams:`/`ids:` on all ten builds but covers three; the six grandfathered builds own no FAMILY-shaped id at all |
| 4 | major | The U4 `.gitattributes` fix pins 3 of the 13 generated artifacts — the ten build READMEs churn on every fresh worktree, invisibly |
| 5 | major | AC2 requires `--staged` to exit 0 "after U1", a state the spec itself measured twice as exit 1 |
| 6 | major | Eight dead `memory/<discipline>/` routes survive in `AGENTS.md` and the manifest, including AGENTS.md:167's MANDATORY Tier-2 review-artifact path; AC11's grep cannot match any of them |
| 7 | major | The ledger's protocol obligations survive in `AGENTS.md` with no successor, and AC11's pattern does not contain the word `ledger` — it matches 8 of 14 lines, two of them false positives |
| 8 | minor | §5 promises to preserve an empty `journal/` that §4 deletes and check 3 rejects |
| 9 | minor | Post-flatten path count is 52 / −6, not 54 / −4: rev-4's F5 deletion never re-based it |
| 10 | minor | "15 files deleted" is off by one — the migration table enumerates 14 |
| 11 | minor | §4 claims every tracked path is named; `memory/README.md`, `HYGIENE.md` and `TEMPLATE-SPEC.md` have no row |
| 12 | minor | `memory/HYGIENE.md` is assigned to two units with contradictory treatments — replaced verbatim in U1, hand-patched in U4 |
| 13 | minor | The "17 files staged" breakdown adds to 18; `.memory-tree.conf.example` is byte-identical between 1.4 and 2.2, so it is 7 modified + 9 added + 1 deleted |
| 14 | minor | `skill/scripts/Analyze-SwydoReport.ps1:459` carries a provenance citation to a folder the flatten moves, and it is not in §4's repair list |

Findings 2, 9 and 14 each name something no gate would have caught. Finding 9 was independently
reproduced by the session's own rehearsal before the review returned.

## Recurring-bug-classes checklist (§10)

- **Auto-took merge class** — CHECKED, clean as specced with a documented exemption. The flatten
  creates exactly the two shapes that carry the class, and 2.2 ships the row-keyed driver for them;
  F6 ratifies leaving it inert with a backlog row rather than silently.
- **Silent truncation** — CHECKED, clean. The merged `DECISIONS.md` enters check 6's capped index set
  and sits far under the 20480 B / 250 L cap.
- **Green-by-absence** — CHECKED, TWO HITS. The `--render` parity green over a corrupted kit
  (finding 1), and AC11's grep, which returns few hits because its pattern misses the routes rather
  than because the routes are gone (findings 6 and 7).
- **Off-by-one in the counts** — CHECKED, FIVE HITS (findings 9, 10, 13 and their echoes). None reds
  a gate; all mislead a hand-verifier in a spec whose stated method is measurement.
- **Ordering hazard** — CHECKED, ONE HIT (finding 1) plus three verified clean.
- **Rename/similarity loss** — CHECKED, clean. AC3's `git log --follow --find-renames` R100 assertion
  is the right instrument and nothing edits the shard in the same commit.
- **Link rot across the restructure** — CHECKED, clean as specced, and additionally covered by a
  compensating verifier this session added for check 2's `DECISIONS.md` exemption: 31 links across
  the merged log, the backlog shards and the root index, 0 broken.

## What the skeptics killed

Seven findings were refuted, chiefly for reading historical rev-2 references in §9 as current claims,
for re-reporting the deliberate deferrals of F3/F4/F6 as oversights, and for asserting failures whose
premise did not survive opening the cited file.
