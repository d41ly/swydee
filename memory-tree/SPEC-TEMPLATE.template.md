# TEMPLATE-SPEC — the canonical spec / design-pass format (memory-tree kit)

Every spec file under `<MEMORY_ROOT>/builds/*/spec/` (at any depth — sub-spec folders are scanned
too) whose filename date is on or after this repo's `SPEC_FORMAT_CUTOFF` (`.memory-tree.conf`)
follows this shape. Machine-enforced by check 12 of `check-memory-hygiene.sh`: the status header
must parse; a Tier-2 spec must carry exactly the ten canonical `##` sections in order (§10 is
date-gated by `SPEC10_CUTOFF` — specs dated before it keep the ten-section canon), with no
empty section bodies, its header `rev-N` logged in §9, and a resolved §8 before a terminal status;
both tiers must be free of skeleton placeholders. Specs dated before the cutoff are grandfathered
by filename date — never retrofit them.

## SPEC10_CUTOFF — how §10 is phased in

`§10 Reuse audit` is required only for specs whose FILENAME date is on or after `SPEC10_CUTOFF`
(default `2026-08-04`, set in `memory-tree/check-memory-hygiene.sh`). Specs dated before it
keep the nine-section canon, so adopting the reuse audit never retroactively reds landed work. It is
env-overridable for adoption in a repo with a different history — raising it grandfathers more, and
lowering it is how you'd ratchet an existing corpus forward. It is a merge-bar knob: changing it
changes what the gate demands, so change it in a commit that says why.

## STREAMS_CUTOFF — the discipline is a header field, not a directory

The tree is flat: a build folder is `<MEMORY_ROOT>/builds/<slug>/` and carries no discipline segment.
Which discipline(s) a spec served is declared in its status header as `· streams <value>[+<value>]`,
over the CLOSED enum `.memory-tree.conf` declares as `DISCIPLINES`. The segment is validated whenever
present, on either tier. It is REQUIRED for specs whose FILENAME date is on or after
`STREAMS_CUTOFF`, which is set strictly ahead of the corpus at adoption so no landed spec is
retroactively red — and which means every spec written from that date onward must carry it.

## The status header (required, within the first 5 unfenced lines)

```
**Status:** <TOKEN> · rev-<N> · <YYYY-MM-DD> · node <tag> · Tier-<1|2> · base <sha8>[ · streams <v>[+<v>]][ · <pointer tail>]
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
- `streams` names the discipline(s) this spec served, `+`-joined, each one a legal `DISCIPLINES`
  value. See the cutoff section above for when it becomes mandatory.
- The tail holds POINTERS only — a review workflow id, `ratified <date>` — never prose.
- Fleet inventory (merged state only — unpushed specs on other nodes are invisible):
  `git grep -lE '^\*\*Status:\*\* (SPECCED|INPROGRESS)' -- '<MEMORY_ROOT>/builds/*/spec/'` lists
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
- Sub-structure nests as `###` under the ten sections; no additional `##` headings, and no
  annotations on a `##` line (`## 4. Design (rev-2 …)` fails the gate — rev notes live in §9).

## Tier profiles, sub-specs, and where recurring content lives

- **Tier-2** uses the full ten-section skeleton below (§10 date-gated by `SPEC10_CUTOFF`).
- **Tier-1** (light profile): the status header + placeholder rules are enforced; the nine-section
  canon is not — keep it anyway when it helps, or write the few sections that matter. This is
  HYGIENE.md's "ceremony is conditional" applied to specs.
- **Multi-spec builds:** each sub-spec is its own conforming file (dated recording name, any depth
  under `spec/`); the master overview and the owner decision menu live in the build-root
  `README.md` (hygiene check 5 bans free-named files inside `spec/`).
- **One slug, two families:** a build that served two disciplines is ONE folder. Where two families'
  recordings would collide on a filename, the optional `-<FAMILY>-` qualifier separates them:
  `<date>-spec-<FAMILY>-<slug>-<seq>.md`.
- **Recurring §4 sub-heads** — use these names, don't invent synonyms: `### Data model` ·
  `### Inventory` · `### Migration` · `### Rollout` · `### Files touched (estimate)` ·
  `### Alternatives rejected`.
- **Resolved owner forks:** mark each fork in §8 in place — `RESOLVED (owner, <date>): <pick>` —
  and add the `ratified <date>` pointer to the header tail. §8 must read `none` or be fully
  RESOLVED before the status may go CLOSED/WONTDO (machine-checked).

## The skeleton (copy everything below this line)

```markdown
# <FAMILY-slug-seq> — <title>

**Status:** OPEN · rev-1 · YYYY-MM-DD · node <tag> · Tier-<1|2> · base <sha8> · streams <value>

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

## 10. Reuse audit

The reuse-discovery result: the existing seam this unit wires through (from a
`codebase-map/reuse_lookup.py` pass), or an explicit "no existing seam fits" with the evidence.
Records the reuse decision so an author cannot silently skip it — the machinery already ships in
this kit, and a checklist item nobody is asked to answer is not a checklist item.
```
