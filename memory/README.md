# memory/ — project memory index

Structured, machine-linted project memory. Shape + rules: [HYGIENE.md](HYGIENE.md). Spec format:
[TEMPLATE-SPEC.md](TEMPLATE-SPEC.md).

The tree is FLAT: a build is named for its SLUG alone, and the discipline it belongs to is a
`streams` value in that build's README front matter rather than a directory.

## Indexes

- [DECISIONS.md](DECISIONS.md) — one line per ratified decision, every family, append-only.
- [LIVE.md](LIVE.md) — GENERATED. Builds with at least one non-terminal unit. Never hand-edited.
- `ledger/<YYYY-MM>.md` — GENERATED. One row per build opened that month; freezes when the month
  passes. Both come from `memory-tree/gen_build_index.py --write`.
- `backlog/<FAMILY>.md` — mutable backlog, one shard per id family: `EXTR` extraction · `ANLZ`
  analysis · `TREND` trend/ledger · `ORCH` orchestration.

## Builds

`builds/<slug>/` holds a build's `spec/`, `build/`, `reviews/` and `prompts/`. Its `README.md`
carries the front matter the generated indexes are derived from. Recording filenames follow
`<date>-<kind>[-<FAMILY>]-<slug>-<seq>.md`; the optional FAMILY qualifier is how one slug shared by
two families survives in a single folder.

The authoritative record of what SHIPPED under the frozen `U1..U10` era remains the units index
inside [the U1-U5 master spec](builds/aCanonicalClient/spec/2026-07-07-spec-aCanonicalClient-1.md).

## Other roots

- `archive/` — rotated indexes and legacy material no build can claim. Holds
  [ledger/a.md](archive/ledger/a.md), the retired per-node session ledger: it is the sole carrier of
  this repo's worktree names, branch history and per-family seq high-water marks up to 2026-08-09.
  Work state is derived from `LIVE.md` now, so nothing is authored there again.
- `project/` — the gate's own waiver registries (`*.txt`) and nothing else.
