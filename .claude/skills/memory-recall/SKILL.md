---
name: memory-recall
description: >-
  Answer a question about WHY this repo is the way it is, from its in-repo decision logs,
  by querying the retrieval index instead of guessing or reading a whole stream. Use whenever
  the ask is recall-shaped: "why does X work this way", "what decided Y", "is there a record
  for Z", "what binds this change", "was this considered before", "what's the rationale for
  this constraint", "which decision covers <area>", "did we already try this" — any question
  whose answer is a rationale, a trade-off, a prior id in one of this repo's families
  (EXTR ANLZ TREND ORCH), or a backlog row. Also use before touching an unfamiliar area, to find the
  records that bind the change. Routes through the shipped CLI, python3 memory-recall/query.py, which needs the
  question in plain English AND 8-14 --terms in this corpus's own jargon (you write the terms;
  the CLI is offline and stdlib-only, so it cannot).
  Do NOT use for ordinary code search — finding a symbol, a caller, a definition, a config key,
  a filename, or a string in code. Grep and Glob own those, they are correct, and this skill
  neither replaces nor intercepts them: it ADDS retrieval as one more way to find a record.
  While /session-kickoff is running, run the probes that skill itself asks for rather than
  pre-empting them.
---

# Ask memory why

You ask in English, the corpus answers in jargon, so `--terms` is REQUIRED and **you** supply
them.

```bash
python3 memory-recall/query.py "<the question, in plain English>" --terms "<8-14 coined words>"
```

Run it from the root of the tree you are **working in** — your worktree, not the primary tree.
The corpus is the tracked `memory/` of `git rev-parse --show-toplevel` from the cwd, so
it includes notes you have staged but not committed, and the cache is keyed per worktree. It
writes nothing inside the worktree: the index, the query log and every aggregate live under the
common git dir.

## Writing the terms — the half that does the work

Terms are the words **this corpus would use for your symptom**, not synonyms of your question:
ids, module names, error codes, flag keys, file names, and the noun a decision record would
title itself with. Supplied terms bypass the tokenizer, so `db`, `ui`, `422`, `c++` and every id
survive — which is most of what a good rewrite produces. Fewer than 8 warns but still answers;
no terms at all is refused. Upstream measured the rewrite at records recall@20 0.71 → 0.84 for
zero committed bytes; that figure is the source project's and has not been re-derived here.

## Reading the answer

Open the records it names, not the streams they live in. Output is sized by a byte budget
(default 20 000 B) and prints snippets, so a hit is a pointer, not the document.

**A miss is ordinary.** On a small corpus retrieval buys precision, not speed — a full-corpus
`grep` is faster and returns half the tree. So when the hits are thin or wrong, fall straight
back to `Grep` over `memory/`. That is not a failure mode, it is the other tool.

## Record which hit you opened — one flag, and it is the point

```bash
python3 memory-recall/query.py --opened <rank> --qid <qid>
```

The query prints the qid it logged — pass that back. Without `--qid` the record attaches to the
**repo-wide last logged query**: the log lives in the common git dir and carries no session or
worktree predicate, so the bare form is only reliable immediately after your own query.

Run it right after you read one of the hits. The query log already records what was asked; what
nobody records is which hit answered it, and that gap is why the source project's own
retrieval-versus-grep study came back underpowered.

If this project took the optional `recall-opened` PostToolUse hook, run it anyway — the hook
returns early when a record already exists for that qid, and stamps `inferred: true` on what it
does write, so a hand record is never lost or double-counted.

## Other flags

- `--k <n>` — depth PER SOURCE (default 20); the merged pool is up to 2×.
- `--budget <bytes>` — the output size cap.
- `--no-terms` — the un-rewritten baseline, logged as such.
- `--rebuild` — force a cold index, ignoring the freshness manifest. This is the escape hatch the
  zero-records diagnosis names.
- `--stats` — print the **cache manifest** (version, chunk max, file count, record and chunk
  counts, corpus digest, alias digest, build seconds, build timestamp). It does not read the
  query log.
- `--export --tag <letter>` — aggregate the query log into a readable table **beside the log,
  under the common git dir**, never into the worktree. `--tag` is required: the log is per node
  and so is its aggregate.

## When the CLI cannot run

Fall back to reading the stream's `DECISIONS.md` / `BACKLOG.md` index under `memory/`
directly. That is the exception, not the norm.
