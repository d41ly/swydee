# TEMPLATE-SPEC — the canonical spec / design-pass format (memory-tree kit)

Every spec file under `<MEMORY_ROOT>/*/builds/*/spec/` (at any depth — sub-spec folders are scanned
too) whose filename date is on or after this repo's `SPEC_FORMAT_CUTOFF` (`.memory-tree.conf`)
follows this shape. Machine-enforced by check 12 of `check-memory-hygiene.sh`: the status header
must parse; a Tier-2 spec must carry exactly the nine canonical `##` sections in order, with no
empty section bodies, its header `rev-N` logged in §9, and a resolved §8 before a terminal status;
both tiers must be free of skeleton placeholders. Specs dated before the cutoff are grandfathered
by filename date — never retrofit them.

## The status header (required, within the first 5 unfenced lines)

```
**Status:** <TOKEN> · rev-<N> · <YYYY-MM-DD> · node <tag> · Tier-<1|2> · base <sha8>[ · <pointer tail>]
```

- `TOKEN` is the shared status vocabulary (HYGIENE.md check 8), with these meanings ON a spec:
  `OPEN` drafting · `SPECCED` complete, awaiting owner scope approval · `BLOCKED` waiting on an
  external prereq · `INPROGRESS` approved, build underway · `DEFERRED` approved but parked ·
  `CLOSED` built and landed · `WONTDO` abandoned or superseded — the tail MUST then carry the
  successor id or a reason pointer (machine-checked).
- Update the header **in place** on every state change; the date is the last-change date.
- `rev-<N>` bumps on ANY material content change (review fold-ins included) and every rev gets a
  §9 line — §9 is the rev high-water a resumed session reads; the header rev being absent from §9
  is machine-checked. A pure status flip moves the date, not the rev.
- `base` is the immutable default-branch sha (8+ hex chars) the design was grounded against.
- The tail holds POINTERS only — a review workflow id, `ratified <date>` — never prose.
- Fleet inventory (merged state only — unpushed specs on other nodes are invisible):
  `git grep -lE '^\*\*Status:\*\* (SPECCED|INPROGRESS)' -- '<MEMORY_ROOT>/*/builds/*/spec/'` lists
  every open spec; swap the token set to taste.

## Writing rules (LLM-optimized AND human-readable — both, always)

- One idea per sentence. Complete sentences, normal punctuation and spacing; hard-wrap ~100 cols.
- Brevity comes from **omitting** what doesn't change the build, never from compressing the
  survivors — no `·`-chains in prose, no parenthetical inventories (parens hold ≤3 items).
- Tables for enumerable facts (inventories, field maps, option menus); prose for reasoning;
  fenced blocks for commands, code, and schemas.
- Name things by repo identifier — a file path, flag key, decision id — never "the helper above".
- Number scope and acceptance items (`S1`, `S2`… / `AC1`, `AC2`…) so reviews and build summaries
  can cite them stably.
- No narration, no restating the heading as its first sentence, no marketing adjectives.
- Verify every claim about existing code against source at writing time; mark the rest `UNVERIFIED`.
- A section that genuinely doesn't apply keeps its heading with the single line `N/A — <why>`.
  Headings never disappear, and empty bodies are machine-rejected: an absent or hollow section is
  indistinguishable from a forgotten one.
- Sub-structure nests as `###` under the nine sections; no additional `##` headings, and no
  annotations on a `##` line (`## 4. Design (rev-2 …)` fails the gate — rev notes live in §9).

## Tier profiles, sub-specs, and where recurring content lives

- **Tier-2** uses the full nine-section skeleton below.
- **Tier-1** (light profile): the status header + placeholder rules are enforced; the nine-section
  canon is not — keep it anyway when it helps, or write the few sections that matter. This is
  HYGIENE.md's "ceremony is conditional" applied to specs.
- **Multi-spec builds:** each sub-spec is its own conforming file (dated recording name, any depth
  under `spec/`); the master overview and the owner decision menu live in the build-root
  `README.md` (hygiene check 5 bans free-named files inside `spec/`).
- **Recurring §4 sub-heads** — use these names, don't invent synonyms: `### Data model` ·
  `### Inventory` · `### Migration` · `### Rollout` · `### Files touched (estimate)` ·
  `### Alternatives rejected`.
- **Resolved owner forks:** mark each fork in §8 in place — `RESOLVED (owner, <date>): <pick>` —
  and add the `ratified <date>` pointer to the header tail. §8 must read `none` or be fully
  RESOLVED before the status may go CLOSED/WONTDO (machine-checked).

## The skeleton (copy everything below this line)

```markdown
# <FAMILY-slug-seq> — <title>

**Status:** OPEN · rev-1 · YYYY-MM-DD · node <tag> · Tier-<1|2> · base <sha8>

## 1. Goal

One or two sentences: the change and why it's worth building.

## 2. Scope (IN)

What this unit builds, as a bounded numbered list (S1, S2, …). Every item is verifiable at DoD.

## 3. Non-goals (OUT)

The explicit cut-line: what an eager builder might include but must not. Name follow-ups.

## 4. Design

The mechanism: data shapes, contracts, flows. Use the canonical ### sub-heads (Data model ·
Inventory · Migration · Rollout · Files touched (estimate) · Alternatives rejected) as needed.
Review corrections fold in here; bump the header rev and log it in §9.

## 5. Production-readiness checklist

The cross-cutting sweep, one line each (what's needed, or N/A — <why>):

- security
- perf / scale
- a11y
- i18n
- error / empty / loading states
- observability
- risks (concurrency, data-loss, rollback hazards)
- testing + left-shift gates
- migration / rollback
- user docs

For Tier-2, unresolved items become the owner scope menu.

## 6. Acceptance criteria

Numbered (AC1, AC2, …). Phrase each as "When <action>, <observable result>" — an observation that
proves THIS change works: a test it adds, a gate it moves, a browser observation. Never an
unrelated green gate.

## 7. Gates

The named gate legs this unit must keep green, plus any new gate it adds.

## 8. Open questions

One fork per bullet or ### sub-head; options and tradeoffs may span lines. Each fork carries a
recommendation. When resolved, mark it in place: RESOLVED (owner, <date>): <pick>. Write `none`
when clear.

## 9. Revision log

- rev-1 · YYYY-MM-DD · initial draft.
- rev-2 · YYYY-MM-DD · folded review wf_<id> corrections.   <!-- example shape -->
```

## 10. Reuse audit

The reuse-discovery result: the existing seam this unit wires through (from a
`tools/codebase-map/reuse_lookup.py` pass), or an explicit "no existing seam fits" with the
evidence. Date-gated by `SPEC10_CUTOFF` — specs dated before it keep the nine-section canon.
