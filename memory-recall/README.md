# memory-recall — ask your decision corpus a question, get the records that answer it

<!-- gov:kit memory-recall@1.0 -->

A project-agnostic kit that turns a memory-tree corpus into two derived FTS5 indexes — one document
per anchored record, one per heading-bounded chunk — fuses them with reciprocal rank fusion, and
emits a byte-budgeted ranked list. Standard library only, offline, no model files, no network.

It declares **no config of its own**. It reads the memory-tree kit's `.memory-tree.conf` — two keys,
`MEMORY_ROOT` and `FAMILIES` — so the corpus root and the id grammar are declared once, in the file
another kit's gate already enforces. A second declaration would be the hand-kept-second-copy defect
this port exists to remove, which is why there is no `--memory-root` and no `--families` flag: the
conf is required, and its absence is a refusal that prints a two-key stub rather than scaffolding one.

Ported from the inCMS `scripts/recall/` implementation at `5318064`.

## What's here

| File | Role |
|---|---|
| `recall_conf.py` | the project layer — reads `.memory-tree.conf`, exposes `MEMORY_ROOT`, `FAMILIES`, the node-tag class, and `Conf.digest()`; carries `KIT_MEMORY_RECALL_VERSION`. Run it directly to print the resolved values (or the refusal). |
| `query.py` | the CLI. **Forked** from upstream — see Maintenance. |
| `extract.py` | record + chunk extraction and the alias join. **Forked**. |
| `bench.py` | the FTS5 index builder and the retrieval-substrate harness. **Verbatim** upstream. |
| `union.py` | the two-source ensemble scorer. **Verbatim** upstream. |
| `selftest.py` | the kit's contract gate — 18 checks, every arm inside a throwaway repo. |
| `adopt-memory-recall.sh` | renders the Skill from the conf (`--scaffold`), and reds when it drifts (`--check`). |
| `SKILL.template.md` | the agent-facing Skill, with the project values as placeholders. Rendered, never copied. |
| `recall-opened.js` | **optional** PostToolUse hook that infers which hit was read. **Forked**. |
| `recall-opened.fragment.json` | the settings block that wires that hook: event, matcher, dedup marker, hook path. |
| `recall-opened.test.sh` | the hook's own check — 8 cases, including a non-`memory` corpus root and a sibling worktree. |
| `verbatim.json` | LF-normalised digests of the two verbatim files, so a silent edit to one reds the selftest. |

## Configure

Nothing to configure. Adopt the **memory-tree** kit first; this kit reads its `.memory-tree.conf`:

| Key | Used for |
|---|---|
| `MEMORY_ROOT` | the corpus root passed to `git ls-files`, and folded into the durable-home regex |
| `FAMILIES` | the `discipline:FAMILY` pairs; the uppercase FAMILY tokens are the id allowlist |

The node-tag character class is **not** a conf key: it is `a-z`, matching the memory-tree gate's own
`node [a-z]`. Non-letter node tags are unsupported.

## Use

```bash
python3 tools/memory-recall/query.py "why did the gate start refusing my push" \
    --terms "pre-push dirty tree porcelain untracked submodule refusal predicate gatepost"
python3 tools/memory-recall/query.py --opened <rank> --qid <N>  # record which hit answered it
python3 tools/memory-recall/query.py "<question>" --rebuild     # force a cache rebuild
python3 tools/memory-recall/query.py --export --tag a           # aggregate the log, outside the tree
```

`--terms` is **required**. Rewriting is the measured half of the retrieval gain upstream (records
recall@20 0.71 → 0.84 on its hard slice) and the CLI cannot produce the terms itself — it is offline
and stdlib-only. The caller is a model, so supplying them costs nothing. `--no-terms` runs the
un-rewritten baseline deliberately and is logged as such.

## What it writes — nothing inside your worktree

The cache (`records.db`, `chunks.db`, `manifest.json`) and the append-only query log
(`queries.jsonl`) live under `<common-git-dir>/recall/`, keyed by a digest of the worktree path.
`--export`'s aggregate is written beside the log, not into the tree, so no free-text question ever
reaches a tracked file.

That property is asserted **by path**, not by a clean `git status`: a status is also clean when a
write was merely hidden by an ignore rule. `sys.dont_write_bytecode = True` sits above the
`sys.path` insert in `query.py`, `selftest.py` and `recall_conf.py` for exactly this reason — without
it, importing the sibling modules drops `__pycache__` next to the source, inside the adopter's tree.
An adopter therefore needs **no** `.gitignore` entry from this kit.

The cache is not small: upstream measures ~115 MiB per live worktree against a 40 MB corpus. A build
deletes sibling caches whose recorded worktree no longer exists; a cache with **no readable
manifest** is never evicted, because that is the shape of a sibling mid-first-build. v1.0 ships no
per-worktree size cap.

## Adopt (per project)

1. Copy this directory to your repo root as `memory-recall/` and make sure `.memory-tree.conf`
   exists (the memory-tree kit owns it — this one refuses rather than creating it).
2. `bash memory-recall/adopt-memory-recall.sh --scaffold` renders the Skill from the conf into
   `.claude/skills/memory-recall/SKILL.md`. Add `--with-hook` only if you want the `recall-opened`
   PostToolUse hook; skipping it is a supported end state, not a gap. With `--with-hook`, finish
   the wiring:
   `python3 settings-merge.py --fragment memory-recall/recall-opened.fragment.json`.
3. **Wire both legs into your local gate runner AND your CI config**, grep-guarded so a re-run does
   not duplicate them. Without this the skill-drift check silently never runs:
   `python3 memory-recall/selftest.py` and `bash memory-recall/adopt-memory-recall.sh --check`.
   The `--check` leg resolves its own interpreter (`python3` first, `python` fallback, `RECALL_PY`
   override), so a `python3`-only adopter needs no extra step — a gate runner's argv rewrite cannot
   reach a `bash` leg.
4. Re-run `--scaffold` after any `FAMILIES` or `MEMORY_ROOT` edit. `--check` reds until you do.

## The Skill, and the optional hook

The Skill is **rendered from the conf, not copied**. Its `description` is the entire trigger
mechanism and it names project values — the id families, the query-script path, the corpus root —
and a description is matched *before* the skill runs, so those values have to be in the file. That
is also why it is project-local rather than a per-machine junction: one machine working on two
projects needs two descriptions. `--check` re-renders and diffs, so a `FAMILIES` edit nobody
re-rendered is a red leg instead of a silently stale trigger.

Three things about that description are pinned by `selftest.py`, because breaking any of them is
silent. It **augments** Grep and Glob rather than replacing them, so ordinary code search still
goes where it already worked. Every flag it prints is one `query.py` actually parses (the flag set
is imported from `query.py`, not restated). And it claims nothing about a numbered `/session-kickoff`
step — upstream's clause named a step that issues this query in *its* repo, which ported verbatim
would suppress the tool at the exact moment it exists for.

The `recall-opened` hook is **opt-in**. It appends one `opened` row per query saying which rank the
caller actually read, stamped `inferred: true`, and it is the only instrument that can answer
"did the answer get shown". It ships dark: no `--with-hook`, no file — so `check-wiring.sh` reports
three honest states (kit not adopted · opt-in not taken · present but unmerged = UNWIRED) instead of
a permanent false alarm. Membership is decided by the log's `shown_paths` array rather than a
`memory/` literal, so it works on any `MEMORY_ROOT`.

## Maintenance — three categories, three different stories

- **Verbatim** — `bench.py`, `union.py`. Zero coupling on the query path, so they are re-pulled
  **wholesale** from upstream on any fix and never merged. Two caveats, stated rather than patched
  out, because patching them would end the wholesale re-pull: their usage strings name the *upstream*
  script path (`scripts/recall/bench.py`), and `bench.main()` / `union.main()` are the upstream
  benchmark harnesses, which are **inert here** — they need a graded `fixture.json` that this kit
  deliberately does not ship. `selftest.py` pins both files' digests, so an edit reds.
- **Forked** — `extract.py`, `query.py`, `recall-opened.js`. Each carries a header naming the
  upstream path and the sha it was taken from, and enumerates its edits, so a re-pull is a
  three-way merge rather than archaeology.
- **New** — `recall_conf.py`, `selftest.py`, `adopt-memory-recall.sh`, `SKILL.template.md`,
  `recall-opened.fragment.json`, `recall-opened.test.sh`, this README.

## Notes

- **No alias data ships.** The alias *mechanism* does: `extract.load_aliases` treats an absent
  default as a legal alias-free corpus, and `bench.build_index` writes an empty third FTS5 column.
  Upstream's `aliases.json` is 915,515 bytes of questions authored against *its* corpus and joined by
  id, so none of it transfers. Drop your own `aliases.json` in this directory and it is picked up
  with no config edit — the cache rebuilds on the digest change.
- **Zero records is diagnosed, never reported as success.** The chunk arm is family-blind and works
  with no configuration; the record arm is the only consumer of the id grammar. Point `FAMILIES` at a
  corpus it does not describe and the un-forked upstream prints `index 0 records + N chunks` and
  exits 0. This kit prints a `ZERO RECORDS` diagnosis naming the resolved families, the conf path and
  `--rebuild`, on the query path and on `extract.py`'s own.
- **On a small corpus, retrieval buys precision, not speed.** Measured on this repo — 66 tracked
  corpus files, 496,153 bytes, 9 anchored records, 1,033 chunks — a full-corpus
  `grep -rIl "adopt" memory/` takes 0.077 s / 0.092 s / 0.447 s across three warm runs and returns
  31 of 66 files. The kit's index build is 0.18 s and a warm query is 1.58–2.27 s wall, dominated by
  interpreter start-up and `git` calls, so it is **slower** than the grep at this size. What it
  returns is a ranked handful instead of half the tree. Adopt it for the ranking, not the clock;
  upstream's 40 MB corpus is where the 6 s cold build starts paying for itself.
