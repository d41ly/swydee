#!/usr/bin/env python3
"""Ask the memory tree a question and get the records that answer it.

FORKED from inCMS ``scripts/recall/query.py`` at 5318064 (file last changed fd6274d). Six
constructs are edited and the rest is upstream's byte for byte, so a re-pull is a three-way merge:
(1) ``corpus_files()`` and the id grammar derive from ``.memory-tree.conf`` via ``recall_conf``;
(2) ``sys.dont_write_bytecode`` above the ``sys.path`` insert; (3) every printed invocation derives
from ``__file__`` and launches ``python3``, and the ``--terms`` refusal's worked example is a
generic one rather than the source project's domain vocabulary; (4) ``--export`` writes beside the
log under the common git dir and requires ``--tag``; (5) the cache manifest carries ``conf_digest``
and ``worktree``, which drive freshness and eviction; (6) an empty record arm, an empty corpus,
or an alias layer that joins to nothing is diagnosed out loud, and the manifest carries the join
counts the third one reads.

Standard library only. Two derived FTS5 indexes -- one per anchored record, one per 600-char
heading-bounded chunk -- cached under the COMMON git directory and rebuilt when the corpus moves.
The QUERY PATH writes nothing inside the worktree, and neither does ``--export``: both write only
under the common git dir.

Usage:
  {cli} "<question>" --terms "<8-14 coined words>" [--k 20] [--budget N]
  {cli} "<question>" --no-terms      # the un-rewritten baseline, logged
  {cli} "<question>" --rebuild       # force a cache rebuild, ignoring the freshness manifest
  {cli} --opened <rank> [--qid N]    # record which hit you actually read
  {cli} --export --tag <letter>      # aggregate the log beside itself, outside the worktree

``--terms`` is REQUIRED. Rewriting is the measured half of the retrieval gain (records recall@20
0.71 -> 0.84, MRR 0.389 -> 0.530, for zero committed bytes) and the CLI cannot generate the terms
itself: that needs a model, and this instrument is stdlib-only and offline on six nodes. The caller
IS a model, so supplying them costs nothing. Supplied terms BYPASS ``bench.terms()`` and are quoted
straight into the MATCH expression -- ``terms()`` would delete ``db``, ``ui``, ``422``, ``c++`` and
every id, which is most of what a rewriter produces.

Why the ranking looks the way it does, in one place so it cannot drift from the instrument:

  * ``--k`` is the depth PER SOURCE, not the length of the merged list. ``union.py`` ranks k from
    ``records`` and k from ``chunks``, so the published ensemble recall at "k=20" is a merged pool
    of up to 40 documents. A CLI whose k meant "20 hits total" would score a different, smaller
    configuration than the one that was measured.
  * The two rankings are fused with RECIPROCAL RANK FUSION at 60, reusing ``bench.RRF_K``. Their
    ``bm25()`` scores are not comparable -- different corpora, different IDF, different document
    lengths -- and a raw concatenation gives a merged top-20 that is ~80% chunks, because that set
    is 22x larger.
  * An id in the question is matched as a PHRASE. ``bench.terms()`` drops tokens of two characters
    or fewer and anything not starting with a letter, so ``ARCH-169`` reaches FTS5 as ``arch`` and
    the governing record ranks 523rd.
  * Output is sized by a BYTE BUDGET, not a document count, because the documents are not the same
    size -- a ``records`` hit averages ~1 020 chars and a chunk is capped at 600, so a fixed hit
    count costs anywhere between 12 KB and 70 KB. The consumer is a model with a context window, so
    bytes are the quantity to bound. Measured: the same recall costs 70 387 B printing whole
    documents and 19 606 B printing snippets.
"""

from __future__ import annotations

import collections
import hashlib
import json
import os
import pathlib
import shutil
import sqlite3
import statistics
import subprocess
import sys
import time
from datetime import UTC, datetime

# ABOVE the sys.path insert, not below it: importing the siblings makes CPython write their
# bytecode next to the SOURCE, which is inside the adopter's worktree -- so "a query writes nothing
# in your tree" was false by two .pyc files until this line existed (spec F5). Asserted by PATH in
# selftest.py, never by a clean `git status`: a status is also clean when the write was merely
# hidden by a .gitignore rule the adopter may not have.
sys.dont_write_bytecode = True
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

import recall_conf  # noqa: E402

try:
    CONF = recall_conf.resolve()
except recall_conf.ConfError as _e:
    # At QUERY time, not just at adopt time: a later FAMILIES edit would otherwise reintroduce the
    # silent-zero failure with nothing to say about it.
    print(_e, file=sys.stderr)
    raise SystemExit(2) from None

import bench as B  # noqa: E402
import extract as E  # noqa: E402


def _self_path() -> str:
    """This script's path as the adopter spells it -- repo-relative when it can be."""
    me = pathlib.Path(__file__).resolve()
    try:
        return me.relative_to(CONF.root).as_posix()
    except ValueError:
        return me.as_posix()


# ONE expression, reused by the docstring usage block, the REFUSAL and the qid hand-back. Ported
# unedited from upstream, all three named a path that does not exist in an adopter repo -- so the
# instruction printed after every successful query told the caller to run a missing file (spec F7).
# `python3`, not bare `python`: a stock Debian/Ubuntu host without python-is-python3 has no such
# binary, so every instruction this CLI prints would be an exit-127 dead end there. The rendered
# Skill says python3 for the same reason -- these two surfaces must agree or one of them lies.
CLI = "python3 " + _self_path()
# The usage block above is a plain literal so it stays a real docstring; the substitution happens
# once, here, after CLI exists.
__doc__ = (__doc__ or "").replace("{cli}", CLI)

CHUNK_MAX = 600  # pinned by the parent spec: 2400 and 300 both measured worse
CACHE_VERSION = 3  # bump when extraction or schema changes, so an old cache is never queried
# 1 -> 2 on 2026-08-02 (ARCH-aGrittedFlagstone-3): records now carry the committed alias layer, so
# every cache built before the join must rebuild rather than keep serving an alias-free index.
# 2 -> 3 on 2026-08-03: the manifest carries the alias JOIN counts. A pre-bump manifest has no
# such key, and the dead-alias diagnosis reads the manifest -- without the bump a warm cache
# would keep the very silence this fix removes.
WINDOW = 400  # chars of the head fallback, matching union.py's SNIPPET accounting
SNIPPET_TOKENS = 64  # FTS5's documented maximum; a larger value is silently clamped
# The default is the MEASURED cost of the shipped configuration: union.py reports 19 606 B for
# records:fts5+chunks:fts5 at k=20 PER SOURCE, which is ~40 hits, not 20.
DEFAULT_BUDGET = 20_000
TERM_BAND = (8, 14)  # the instruction the SEALED rewriters were given -- not a measured optimum

# --- ARCH-aTemperedLoom-20 -----------------------------------------------------------------------
RESULT_CAP = 5  # entries kept in a record's `results`; `n_hits` still holds the true total
EXPORT_CAP = 20_480  # the index-file byte cap, self-imposed: nothing else bounds this file
# The highest qid a node's log carries from the build that BUILT the log -- traffic generated by
# agents probing the corpus, which counting as demand would measure the build. The MECHANISM ships
# and the DATA does not: a fresh adopter has no build era, so this map is empty and every record is
# live. Add `{"a": 163}`-style rows only from a value READ from that node's live log.
#
# PER NODE, because a qid is per node. Each node's log is independent and counts from its own max,
# so a single global integer is not a boundary -- it is an off-by-a-whole-log error on every node
# but the one it was measured on. An unknown node gets 0, so the default is "count everything" and
# a node can only ever lose records by an explicit, greppable pin.
#
# qids are NON-DECREASING but NOT unique: log_event allocates `max(qid) + 1` after re-reading the
# file, so concurrent writers collide -- measured upstream at 168 records under 155 distinct qids.
# Exclusion is still sound (no later record can carry a lower qid), but nothing here may JOIN on
# qid or count distinct qids in place of records.
BUILD_QID_CUTOFF: dict[str, int] = {}


def build_cutoff(tag: str) -> int:
    """The provenance cut-off for ONE node's log. Unknown node -> 0, i.e. nothing excluded."""
    return BUILD_QID_CUTOFF.get(tag, 0)

KNOWN_FLAGS = (
    "--k",
    "--budget",
    "--stats",
    "--opened",
    "--qid",
    "--rebuild",
    "--help",
    "--terms",
    "--no-terms",
    "--export",
    "--tag",
)

REFUSAL = """refused: this CLI requires rewrite terms alongside the question.

  --terms "<8-14 coined words this corpus would use for your symptom>"

Rewriting is the measured half of the retrieval gain, not a nicety: on the hard slice it
moves records recall@20 from 0.71 to 0.84 and MRR from 0.389 to 0.530, for zero committed
bytes. You are asking in plain English; the corpus answers in its own jargon. Supply the
jargon and the plain question together -- both go into one query.

  {cli} "why does the gate refuse this push" \\
      --terms "pre-push hook gate leg refusal exit-1 bypass no-verify merge bar \\
               single-head parity"

Terms are what THIS corpus calls your symptom -- one of its id families, a module name, an
error code, a flag key, a file name -- not synonyms of the words you just typed.

To run the un-rewritten baseline deliberately -- a measurement, or checking whether your own
record is findable without help -- pass --no-terms. It is logged as such.""".replace("{cli}", CLI)


def git(repo: pathlib.Path, *args: str) -> str:
    return subprocess.run(
        ["git", "-C", str(repo), *args], capture_output=True, text=True, check=True
    ).stdout


def repo_root() -> pathlib.Path:
    out = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True, check=True
    ).stdout.strip()
    return pathlib.Path(out).resolve()


def common_git_dir(repo: pathlib.Path) -> pathlib.Path:
    """The MAIN repository's git directory, shared by every worktree.

    ``--git-dir`` in a linked worktree is ``.git/worktrees/<name>``, which ``git worktree remove``
    deletes outright -- taking the query log with it. It is also RELATIVE (bare ``.git``) when run
    at the repo root and absolute elsewhere, so the raw value is not a usable path either way.
    """
    raw = git(repo, "rev-parse", "--git-common-dir").strip()
    p = pathlib.Path(raw)
    return p.resolve() if p.is_absolute() else (repo / raw).resolve()


def corpus_files(repo: pathlib.Path) -> list[str]:
    """Tracked AND untracked-not-ignored ``$MEMORY_ROOT/**/*.md``.

    A note written this session and not yet committed is exactly what a session needs to find, and
    ``extract.corpus_files`` is tracked-only on purpose -- it is the MEASUREMENT path and stays
    pinnable to a rev.
    """
    root = CONF.memory_root + "/"  # FORKED: conf, not a literal `memory/`
    tracked = git(repo, "ls-files", root).splitlines()
    untracked = git(repo, "ls-files", "--others", "--exclude-standard", root).splitlines()
    return sorted({p for p in tracked + untracked if p.endswith(".md")})


def corpus_digest(repo: pathlib.Path, files: list[str]) -> str:
    h = hashlib.sha1()
    for p in files:
        try:
            st = (repo / p).stat()
        except OSError:
            continue
        h.update(f"{p}\0{st.st_mtime_ns}\0{st.st_size}\0".encode())
    return h.hexdigest()


def cache_dir(repo: pathlib.Path) -> pathlib.Path:
    """Per-worktree cache under the common git dir.

    Sub-keyed by the worktree path because two worktrees of one repo hold DIFFERENT corpus content;
    one shared cache would answer a question about one tree from the other.
    """
    key = hashlib.sha1(str(repo).encode()).hexdigest()[:12]
    return common_git_dir(repo) / "recall" / "cache" / key


def log_path(repo: pathlib.Path) -> pathlib.Path:
    return common_git_dir(repo) / "recall" / "queries.jsonl"


# ---------------------------------------------------------------------------------- index build


def alias_digest() -> str:
    """Content digest of the committed alias layer, for the cache manifest.

    The freshness manifest keys on `corpus_digest(repo, files)`, and `files` is `memory/` only, so
    an edit to `aliases.json` would otherwise leave a stale cache serving un-joined results with no
    signal at all.
    """
    return E.load_aliases()[2]


def dead_alias_diagnosis(man: dict) -> str | None:
    """An alias layer that loaded ids and joined to NOT ONE of them, named out loud.

    The zero-record class one layer in. The alias column is a down-weighted ranking aid, so an
    alias file authored against another id family is 100% dead with no symptom beyond slightly
    worse ranking -- `--stats` carried only `alias_digest`, which is a content hash and says
    nothing about coverage. Counts come from the MANIFEST, so this fires identically on a fresh
    build and on a cache hit. Silent on a partial join: some ids resolving is the normal state of
    an alias file written ahead of the records it names.
    """
    a = man.get("aliases") or {}
    if not a.get("ids") or a.get("joined"):
        return None
    return (
        f"DEAD ALIAS LAYER — {a['ids']} alias ids loaded and not one joined to a record.\n"
        f"  alias source: {a.get('src', '?')}\n"
        f"  FAMILIES in {CONF.path.as_posix()} resolved to: {' '.join(CONF.families)}\n"
        "  Not one of those ids names a record in this corpus, so the alias column is empty and\n"
        "  the only symptom is slightly worse ranking. Check the ids are this corpus's own."
    )


def _docs(repo: pathlib.Path, files: list[str]) -> tuple[list[dict], list[dict], dict]:
    records, chunks = [], []
    for path in files:
        try:
            text = (repo / path).read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        if not text:
            continue
        records.extend(E.extract_records(path, text))
        chunks.extend(E.extract_chunks(path, text, CHUNK_MAX))
    # The SECOND call site of the alias join, and the one the merge bar cannot see
    # (ARCH-aGrittedFlagstone-3). `check_recall.py` grades a SUBPROCESS of `extract.py`; this CLI
    # never runs that entry point and never reads its output dir -- it re-extracts here and indexes
    # the result. A join written only there ships a query index with an empty alias column while
    # every recall floor stays green, which is the dead-plumbing class arriving through the door
    # marked "the gate already covers it".
    #
    # The int return is CARRIED, not discarded (closing review F7): join_aliases documents it as
    # `how many were augmented`, extract.py's own path prints it, and the CLI -- the path every
    # session actually uses -- reported it nowhere. Same class again, one layer in.
    by_id, alias_src, _ = E.load_aliases()
    joined = E.join_aliases(records, by_id)
    return records, chunks, {"ids": len(by_id), "joined": joined, "src": alias_src}


def _write_set(dirp: pathlib.Path, name: str, docs: list[dict]) -> None:
    db_file = dirp / f"{name}.db"
    if db_file.exists():
        db_file.unlink()
    db = B.build_index(docs, db_path=str(db_file))
    db.execute("CREATE TABLE meta(rowid INTEGER PRIMARY KEY, id TEXT, path TEXT, line INTEGER)")
    db.executemany(
        "INSERT INTO meta(rowid, id, path, line) VALUES (?,?,?,?)",
        [(i, d.get("id") or d.get("rec") or "", d["path"], d["line"]) for i, d in enumerate(docs)],
    )
    db.commit()
    db.close()


def build_cache(repo: pathlib.Path, dirp: pathlib.Path, files: list[str]) -> dict:
    t0 = time.time()
    records, chunks, aliases = _docs(repo, files)
    dirp.mkdir(parents=True, exist_ok=True)
    _write_set(dirp, "records", records)
    _write_set(dirp, "chunks", chunks)
    man = {
        "version": CACHE_VERSION,
        "chunk_max": CHUNK_MAX,
        "n_files": len(files),
        "counts": {"records": len(records), "chunks": len(chunks)},
        "digest": corpus_digest(repo, files),
        "alias_digest": alias_digest(),
        # The join COUNTS beside the source digest: the digest keys freshness and cannot tell a
        # joined alias layer from a dead one. Here so the diagnosis fires on a cache hit too.
        "aliases": aliases,
        # FORKED. The port moves the id grammar and the corpus root OUT of source and into a
        # conf at the repo root -- which makes an adopter-editable value a COLD input to a HOT
        # cache. The corpus digest is mtime+size over the tree's .md files, so a FAMILIES edit
        # never enters it: without this field, fixing a mis-declared grammar is a silent no-op
        # against a warm cache, in BOTH directions (spec F1). Same reason alias_digest is here.
        "conf_digest": CONF.digest(),
        # The worktree this cache was built for, so a later build can evict a cache whose tree is
        # gone. Absolute: cache directories are keyed by a hash of this path, which is one-way.
        "worktree": str(repo),
        "built_s": round(time.time() - t0, 2),
        "built_at": datetime.now(UTC).isoformat(timespec="seconds"),
    }
    # Manifest LAST, and atomically: an interrupted build must leave a stale-or-absent manifest and
    # rebuild, never certify a half-written index.
    tmp = dirp / "manifest.json.tmp"
    tmp.write_text(json.dumps(man, indent=1), encoding="utf-8", newline="\n")
    os.replace(tmp, dirp / "manifest.json")
    return man


def evict_dead_siblings(keep: pathlib.Path) -> list[str]:
    """Delete sibling caches whose recorded ``worktree`` no longer exists. Returns what went.

    ONE predicate, read in two directions: an unreadable manifest means REBUILD MINE, NEVER DELETE
    THEIRS. The builder writes both .db files BEFORE the manifest, deliberately and atomically, so
    a directory with no readable manifest is exactly the shape of a sibling mid-first-build --
    evicting it destroys a live cache while its builder is still writing. A pre-fork manifest with
    no ``worktree`` key is kept for the same reason: absence of evidence.
    """
    gone: list[str] = []
    parent = keep.parent
    try:
        siblings = sorted(p for p in parent.iterdir() if p.is_dir())
    except OSError:
        return gone
    for d in siblings:
        if d == keep:
            continue
        man = read_manifest(d)
        if man is None:                      # never-evict: no readable manifest
            continue
        wt = man.get("worktree")
        if not wt or pathlib.Path(wt).exists():
            continue
        shutil.rmtree(d, ignore_errors=True)
        gone.append(wt)
    return gone


def read_manifest(dirp: pathlib.Path) -> dict | None:
    try:
        return json.loads((dirp / "manifest.json").read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None


def ensure_cache(repo: pathlib.Path, force: bool = False) -> tuple[pathlib.Path, dict, bool]:
    dirp = cache_dir(repo)
    files = corpus_files(repo)
    man = read_manifest(dirp)
    fresh = (
        not force
        and man is not None
        and man.get("version") == CACHE_VERSION
        and man.get("chunk_max") == CHUNK_MAX
        and man.get("digest") == corpus_digest(repo, files)
        and man.get("alias_digest") == alias_digest()
        and man.get("conf_digest") == CONF.digest()
        and (dirp / "records.db").exists()
        and (dirp / "chunks.db").exists()
    )
    if fresh:
        return dirp, man, False
    built = build_cache(repo, dirp, files)
    for wt in evict_dead_siblings(dirp):
        print(f"evicted the cache of a worktree that no longer exists: {wt}", file=sys.stderr)
    return dirp, built, True


# ---------------------------------------------------------------------------------- querying


def query_expr(question: str, extra_terms: list[str] | None = None) -> str | None:
    """The FTS5 MATCH expression, or None when nothing searchable survives.

    ``bench.match_expr`` falls back to ``'"the"'`` on an empty term set, which turns "how do I do
    this?" into five arbitrary records presented as answers. The caller refuses instead.

    Ids are added as quoted PHRASES: the ``unicode61`` tokenizer splits ``ARCH-169`` into ``arch``
    and ``169``, so ``"arch 169"`` is how the pair is matched adjacently.
    """
    extra_terms = extra_terms or []
    parts: list[str] = []
    base_terms = B.terms(question)
    if base_terms:
        parts.append(B.match_expr(question))
    for t in extra_terms:
        cleaned = t.replace('"', " ").strip()
        if cleaned:
            parts.append(f'"{cleaned}"')
    for found in dict.fromkeys(E.ID_RE.findall(question + " " + " ".join(extra_terms))):
        parts.append('"' + found.replace("-", " ").lower() + '"')
    if not parts:
        return None
    return " OR ".join(parts)


def search(dirp: pathlib.Path, name: str, expr: str, k: int) -> list[dict]:
    db = sqlite3.connect(f"file:{dirp / f'{name}.db'}?mode=ro", uri=True)
    try:
        rows = db.execute(
            "SELECT d.rowid, m.id, m.path, m.line, "
            f"snippet(d, 1, '', '', '…', {SNIPPET_TOKENS}), d.body "
            "FROM d JOIN meta m ON m.rowid = d.rowid "
            f"WHERE d MATCH ? ORDER BY bm25(d, 1.0, 1.0, {B.ALIAS_WEIGHT}) LIMIT ?",
            (expr, k),
        ).fetchall()
    except sqlite3.OperationalError:
        return []
    finally:
        db.close()
    return [
        {
            "set": name,
            "rowid": r[0],
            "id": r[1],
            "path": r[2],
            "line": r[3],
            "snippet": r[4],
            "text": r[5],
        }
        for r in rows
    ]


def rrf(rankings: list[list[dict]]) -> list[dict]:
    """Reciprocal rank fusion at ``bench.RRF_K``, the instrument's own constant.

    Keyed on (path, line) rather than rowid: the same passage can surface from both sets, and two
    sets' rowids are unrelated integers.
    """
    scored: dict[tuple, list] = {}
    for ranked in rankings:
        for rank, hit in enumerate(ranked, 1):
            key = (hit["path"], hit["line"], (hit.get("text") or "")[:60])
            slot = scored.setdefault(key, [0.0, hit])
            slot[0] += 1.0 / (B.RRF_K + rank)
            # Prefer the record-level view of the same passage: it carries the id.
            if hit["set"] == "records":
                slot[1] = hit
    return [h for _, (_, h) in sorted(scored.items(), key=lambda kv: -kv[1][0])]


# ---------------------------------------------------------------------------------- emission


def render(hit: dict, question: str, extra_terms: list[str] | None = None) -> tuple[str, bool]:
    """One hit as text, plus whether it fell back to a head window.

    ``snippet(d, 1, …)`` returns the BODY's leading tokens rather than a query-biased window when
    the match landed only in the ``head`` or ``alias`` column -- measured, 5 of 3 680 fixture hits.
    Those are labelled rather than passed off as match windows.

    The header is ``id · path:line`` and carries NO heading. ``union.py`` charges 100 B per hit for
    "id + path + heading"; measured on this corpus, id + path:line is 61 B mean / 102 B p90 and
    fits, while adding the heading takes the mean to 646 B -- six times the accounting every byte
    figure in the parent spec rests on.
    """
    wanted = set(B.terms(question)) | {t.lower() for t in (extra_terms or [])}
    body = " ".join((hit["snippet"] or "").split())
    is_head = bool(wanted) and not any(w in body.lower() for w in wanted)
    if not body:
        body = " ".join(hit["text"].split())[:WINDOW]
        is_head = True
    head = f"{hit['id']} · " if hit["id"] else ""
    tag = "  [head window — matched on the title, not the body]" if is_head else ""
    return f"{head}{hit['path']}:{hit['line']}{tag}\n    {body}", is_head


def emit(
    hits: list[dict], question: str, budget: int, full: bool = False
) -> tuple[str, int, int, int]:
    """Render hits in rank order until the NEXT one would exceed ``budget``.

    Returns ``(text, shown, bytes_spent, overflow)``. The one exception to the bound is a budget too
    small for even the first hit: that hit is emitted alone and ``overflow`` says by how much,
    rather than printing an empty list that reads as "no such record".

    ``full=True`` renders whole documents instead of snippets. It is not a CLI flag -- restoring
    whole-document output is the cost this item exists to remove -- it exists so the saving can be
    MEASURED against the same ranked pool rather than against a number written in a document.
    """
    parts: list[str] = []
    spent = shown = overflow = 0
    for n, h in enumerate(hits, 1):
        if full:
            text = f"{h['id'] + ' · ' if h['id'] else ''}{h['path']}:{h['line']}\n    {h['text']}"
        else:
            text, _ = render(h, question)
        chunk = f"[{n}] {text}\n"
        cost = len(chunk.encode())
        if spent + cost > budget:
            if shown == 0:
                parts.append(chunk)
                shown, spent, overflow = 1, cost, cost - budget
            break
        parts.append(chunk)
        spent += cost
        shown += 1
    return "\n".join(parts), shown, spent, overflow


# ---------------------------------------------------------------------------------- the log


def log_event(repo: pathlib.Path, event: dict) -> int | None:
    """Append one JSONL record. Never fatal: a query that answered is worth more than its log."""
    p = log_path(repo)
    try:
        p.parent.mkdir(parents=True, exist_ok=True)
        qid = 0
        if p.exists():
            with p.open(encoding="utf-8") as fh:
                for line in fh:
                    try:
                        qid = max(qid, json.loads(line).get("qid", 0))
                    except ValueError:
                        continue
        qid += 1
        event = {"qid": qid, "at": datetime.now(UTC).isoformat(timespec="seconds"), **event}
        with p.open("a", encoding="utf-8", newline="\n") as fh:
            fh.write(json.dumps(event, ensure_ascii=False) + "\n")
        return qid
    except OSError as e:
        print(f"warning: query log not written ({e})", file=sys.stderr)
        return None


def last_qid(repo: pathlib.Path) -> int | None:
    p = log_path(repo)
    if not p.exists():
        return None
    qid = None
    with p.open(encoding="utf-8") as fh:
        for line in fh:
            try:
                row = json.loads(line)
            except ValueError:
                continue
            if row.get("type") != "opened":
                qid = row.get("qid", qid)
    return qid


def qid_exists(repo: pathlib.Path, qid: int) -> bool:
    """Is there a non-``opened`` row carrying this qid?

    A typo'd ``--qid`` would otherwise write a dangling outcome record into the one
    instrument this feature has, and nothing downstream could tell it from a real one.
    """
    p = log_path(repo)
    if not p.exists():
        return False
    with p.open(encoding="utf-8") as fh:
        for line in fh:
            try:
                row = json.loads(line)
            except ValueError:
                continue
            if row.get("qid") == qid and row.get("type") != "opened":
                return True
    return False


# ------------------------------------------------------- the export (ARCH-aTemperedLoom-20)


# FORKED: upstream resolved the node tag by parsing its own CLAUDE.md node registry, a document no
# adopter has. `--tag` is required for `--export` instead; a project-specific lookup is exactly the
# hand-kept second copy this port exists to remove.


def read_log(repo: pathlib.Path) -> list[dict]:
    p = log_path(repo)
    if not p.exists():
        return []
    rows = []
    with p.open(encoding="utf-8") as fh:
        for line in fh:
            try:
                rows.append(json.loads(line))
            except ValueError:
                continue
    return rows


def _table(header: list[str], body: list[list[str]]) -> list[str]:
    return [
        "| " + " | ".join(header) + " |",
        "|" + "|".join("---" for _ in header) + "|",
        *["| " + " | ".join(r) + " |" for r in body],
    ]


def export_text(rows: list[dict], tag: str, cutoff: int | None = None) -> str:
    """The aggregate, as markdown. Pure: same rows in, byte-identical text out.

    NO wall clock and NO unordered iteration anywhere -- a ``generated <now>`` line is the natural
    thing to write and it would churn a tracked file on every session close, which is the one thing
    ``--export`` promises not to do. Every table sorts on a stated key.

    NO raw query text. Not for secrecy -- a dev question is not sensitive -- but because raw text
    is what makes the artifact big, churn-prone and unmergeable, and no question the log exists to
    answer needs it.
    """
    # Resolved from the TAG, so the boundary is the one belonging to the log being read. A caller
    # may override for a test, but never inherits another node's number by default.
    if cutoff is None:
        cutoff = build_cutoff(tag)
    # LABEL, do not EXCLUDE (owner 2026-07-28). The perishable asset is the BOUNDARY, not the
    # exclusion: node `a`'s build-era records are separable by qid and only approximately by date,
    # because a genuine query landed the same day. So both segments are REPORTED and neither is
    # hidden -- a mechanism that can silently drop a record is a poor guardian for a risk that
    # shrinks on its own, and this one had already misfired once by eating a foreign node's log.
    build_era = [r for r in rows if r.get("qid", 0) <= cutoff]
    kept = [r for r in rows if r.get("qid", 0) > cutoff]
    queries = [r for r in kept if r.get("type") == "query"]

    def _seg(rs: list[dict]) -> list[str]:
        qs = [r for r in rs if r.get("type") == "query"]
        return [
            str(len(rs)),
            str(len(qs)),
            str(sum(1 for r in rs if r.get("type") == "refused")),
            str(sum(1 for r in qs if not r.get("rewritten"))),
        ]

    out = [
        f"# Recall traffic — node `{tag}`",
        "",
        f"Generated by `{CLI} --export --tag {tag}`. One file per node so it never conflicts, and",
        "it is written beside the raw JSONL under the common git dir -- OUTSIDE the worktree, so no",
        "free-text question ever reaches a tracked file. Aggregate only — no raw query text.",
        "Re-running `--export` on an unchanged log rewrites this file byte-identically.",
        "",
        "## Provenance",
        "",
        *(
            [
                f"`build-era` is every record at or below the pinned boundary `qid <= {cutoff}` —",
                "traffic generated by the build that built this log, probing the corpus. It is",
                "LABELLED, never hidden: counting it as demand would measure that build, but",
                "dropping it would destroy a boundary nothing can reconstruct later (these",
                "records are separable by `qid` and only approximately by date, because a genuine",
                "query landed the same day). Every table after this section covers `live` only,",
                "and this one shows you exactly what that leaves out.",
            ]
            if cutoff
            else [
                "No boundary is pinned for this node, so everything is `live`. The boundary is PER",
                "NODE — a `qid` is per node — and only a node whose log opens with known build",
                "traffic carries one. See `BUILD_QID_CUTOFF` in `query.py`.",
            ]
        ),
        "",
        *_table(
            ["segment", "records", "queries", "refused", "--no-terms"],
            [["build-era", *_seg(build_era)], ["live", *_seg(kept)]],
        ),
        "",
        "## Per day",
        "",
        "`live` records only — see Provenance above for what sits below the boundary.",
        "",
    ]

    by_day: dict[str, list[dict]] = collections.defaultdict(list)
    for r in kept:
        by_day[r.get("at", "")[:10] or "(undated)"].append(r)
    body = []
    for day in sorted(by_day):
        rs = by_day[day]
        qs = [r for r in rs if r.get("type") == "query"]
        terms = [len(r.get("terms") or []) for r in qs]
        hits = [r.get("n_hits", 0) for r in qs]
        emitted = [r.get("bytes_emitted", 0) for r in qs]
        body.append([
            day,
            str(len(qs)),
            str(sum(1 for r in qs if r.get("rewritten"))),
            str(sum(1 for r in qs if not r.get("rewritten"))),
            str(sum(1 for r in rs if r.get("type") == "refused")),
            str(sum(1 for r in rs if r.get("type") == "opened")),
            f"{statistics.fmean(hits):.1f}" if hits else "—",
            f"{statistics.fmean(emitted):,.0f}" if emitted else "—",
            f"{statistics.median(terms):.0f}" if terms else "—",
        ])
    out += _table(
        ["day", "queries", "rewritten", "--no-terms", "refused", "opened",
         "mean hits", "mean B out", "median terms"],
        body or [["(none)"] + ["—"] * 8],
    )

    out += ["", "## Supplied-term count", "", "`0` is `--no-terms`, the deliberate baseline.", ""]
    hist = collections.Counter(len(r.get("terms") or []) for r in queries)
    out += _table(
        ["terms", "queries"], [[str(n), str(hist[n])] for n in sorted(hist)] or [["—", "—"]]
    )

    out += [
        "",
        "## Opened rank",
        "",
        "The rank the caller said they actually read. This is the only signal answering *what was",
        "right* rather than *what was asked*; everything else here measures demand.",
        "",
    ]
    oh = collections.Counter(r.get("rank") for r in kept if r.get("type") == "opened")
    out += _table(
        ["rank", "times"],
        [[str(n), str(oh[n])] for n in sorted(oh, key=lambda x: (x is None, x))] or [["—", "—"]],
    )

    out += [
        "",
        "## Top target paths",
        "",
        f"By hit count across retained queries. Records written after `RESULT_CAP={RESULT_CAP}`",
        "carry only their top few hits, so this ranks what callers were SHOWN, not the full pool.",
        "",
    ]
    paths = collections.Counter(
        h.get("path", "") for r in queries for h in (r.get("results") or []) if h.get("path")
    )
    # Count DESC then path ASC, so ties never reorder between runs.
    top = sorted(paths.items(), key=lambda kv: (-kv[1], kv[0]))[:20]
    out += _table(["hits", "path"], [[str(n), f"`{p}`"] for p, n in top] or [["—", "—"]])

    out += [
        "",
        "## By worktree",
        "",
        "A burst from one tree is the shape the cut-off above excluded once already; averaged",
        "into a total it is invisible. `(unrecorded)` is counted rather than dropped — the field",
        "is absent from older query records and from every `refused`/`opened` row, so a table",
        "without it would silently under-report.",
        "",
    ]
    wt = collections.Counter(r.get("worktree") or "(unrecorded)" for r in queries)
    out += _table(
        ["queries", "worktree"],
        [[str(n), w if w == "(unrecorded)" else f"`{w}`"]
         for w, n in sorted(wt.items(), key=lambda kv: (-kv[1], kv[0]))] or [["—", "—"]],
    )
    return "\n".join(out) + "\n"


def export(repo: pathlib.Path, tag: str) -> int:
    rows = read_log(repo)
    if not rows:
        print(f"no query log at {log_path(repo)} — nothing to export", file=sys.stderr)
        return 1
    text = export_text(rows, tag)
    size = len(text.encode())
    # FORKED: beside the log under the common git dir, not `<root>/memory/project/` inside the
    # worktree. That was the kit's ONE tracked write and the only path that could carry a
    # free-text question into version control; moving it keeps the reader and closes the path.
    dest = common_git_dir(repo) / "recall" / f"recall-traffic-{tag}.md"
    if size > EXPORT_CAP:
        # A bound nobody can trip is not a bound. Refuse BEFORE writing, so the oversized file
        # never exists.
        print(
            f"refused: the export is {size:,} B, over the {EXPORT_CAP:,} B cap.\n"
            f"  mv {dest.as_posix()} {dest.as_posix()}.<date>\n"
            "  then re-run --export to start a fresh file.",
            file=sys.stderr,
        )
        return 1
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(text, encoding="utf-8", newline="\n")
    print(f"wrote {dest.as_posix()} ({size:,} B of {EXPORT_CAP:,} B)")
    return 0


# ---------------------------------------------------------------------------------- main


VALUE_FLAGS = ("--k", "--budget", "--opened", "--qid", "--terms", "--tag")
BARE_FLAGS = ("--stats", "--rebuild", "--help", "--no-terms", "--export")


def parse(argv: list[str]) -> tuple[dict[str, str], list[str], str | None]:
    """One left-to-right scan. Returns ``(flags, positionals, error)``.

    The scan replaces a first-non-dash guess plus a repair loop, which got the question wrong for
    any ordering the repair did not anticipate: ``query.py --terms "a b" --budget 400 "question"``
    picked up ``400`` and queried it, printing "33 hits for: 400". A parser that has to be repaired
    per flag ordering is a parser that is wrong for the next ordering.
    """
    flags: dict[str, str] = {}
    pos: list[str] = []
    i = 0
    while i < len(argv):
        a = argv[i]
        if a.startswith("--"):
            name, _, inline = a.partition("=")
            if name in VALUE_FLAGS:
                if inline:
                    flags[name] = inline
                elif i + 1 < len(argv) and not argv[i + 1].startswith("--"):
                    flags[name] = argv[i + 1]
                    i += 1
                else:
                    return flags, pos, f"{name} needs a value"
            elif name in BARE_FLAGS:
                flags[name] = ""
            else:
                return flags, pos, f"unknown flag {name!r}; known: {' '.join(sorted(KNOWN_FLAGS))}"
        else:
            pos.append(a)
        i += 1
    return flags, pos, None


def main(argv: list[str] | None = None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    flags, pos, err = parse(argv)
    if err:
        print(err, file=sys.stderr)
        return 2
    if "--help" in flags or not argv:
        print(__doc__)  # the usage block already carries the resolved CLI path
        return 0 if "--help" in flags else 2

    def num(flag: str, default: int) -> int | None:
        raw = flags.get(flag)
        if raw is None:
            return default
        try:
            v = int(raw)
        except ValueError:
            print(f"{flag} takes an integer, got {raw!r}", file=sys.stderr)
            return None
        if v <= 0:
            print(f"{flag} must be positive, got {v}", file=sys.stderr)
            return None
        return v

    repo = repo_root()

    if "--export" in flags:
        tag = (flags.get("--tag") or "").strip().lower()
        if not tag:
            print("refused: --export needs --tag <letter>; the log is per node and so is its "
                  "aggregate.", file=sys.stderr)
            return 2
        if len(tag) != 1 or not tag.isalpha():
            print(f"--tag takes one letter from the node registry, got {tag!r}", file=sys.stderr)
            return 2
        return export(repo, tag)

    if "--opened" in flags:
        rank = num("--opened", 0)
        if rank is None:
            return 2
        # WITHOUT --qid this attaches to the repo-wide LAST logged query: the log lives in
        # the COMMON git dir and `last_qid` carries no session or worktree predicate. The
        # fix is a KEY, not a filter -- measured over the live log, the race that actually
        # happens is INTRA-worktree (49 of 54 consecutive gaps from this checkout under
        # 60 s, concurrent agents in ONE tree), which no worktree predicate can see, while
        # the cross-worktree race a filter would close has 0 observed instances in 120
        # worktree-bearing rows (closing review F17). So the query path prints its qid and
        # the caller hands it back.
        if "--qid" in flags:
            qid = num("--qid", 0)
            if qid is None:
                return 2
            if not qid_exists(repo, qid):
                print(f"no query with qid {qid} in the log; the query path prints the qid "
                      "it logged", file=sys.stderr)
                return 2
        else:
            qid = last_qid(repo)
            if qid is None:
                print("no query to attach an --opened record to", file=sys.stderr)
                return 1
        log_event(repo, {"type": "opened", "of_qid": qid, "rank": rank})
        print(f"recorded: opened rank {rank} of query {qid}")
        return 0

    question = pos[0] if pos else ""
    if not question:
        print('no question given; usage: query.py "<question>"', file=sys.stderr)
        return 2

    k = num("--k", 20)
    budget = num("--budget", DEFAULT_BUDGET)
    if k is None or budget is None:
        return 2

    # An EMPTY --terms is not rewriting. It bypassed the refusal and logged identically to
    # --no-terms, which would have made the whole item opt-out by accident.
    terms = [t for t in (flags.get("--terms") or "").split() if t]
    has_terms = bool(terms)
    no_terms = "--no-terms" in flags
    if "--terms" in flags and not terms:
        print("--terms was given with no terms; pass real terms or --no-terms", file=sys.stderr)
        return 2
    if has_terms and no_terms:
        print("--terms and --no-terms contradict; pass one", file=sys.stderr)
        return 2
    if not has_terms and not no_terms:
        log_event(repo, {"type": "refused", "reason": "no-rewrite-terms", "query": question})
        print(REFUSAL, file=sys.stderr)
        return 2
    if has_terms and len(terms) < TERM_BAND[0]:
        # Warn, never refuse: a caller who supplied six real terms should get an answer. The band
        # describes the population the 0.84 was measured on; it is not a tuned threshold.
        print(
            f"note: {len(terms)} rewrite terms; the measured arm used "
            f"{TERM_BAND[0]}-{TERM_BAND[1]}",
            file=sys.stderr,
        )

    dirp, man, rebuilt = ensure_cache(repo, force="--rebuild" in flags)

    expr = query_expr(question, terms)
    if expr is None:
        log_event(repo, {"type": "refused", "reason": "no-searchable-term", "query": question})
        print(
            "refused: that question carries no distinctive term (every word is a stop word or "
            "shorter than three characters). Add the coined vocabulary you are looking for.",
            file=sys.stderr,
        )
        return 2

    try:
        hits = rrf([search(dirp, "records", expr, k), search(dirp, "chunks", expr, k)])
    except sqlite3.DatabaseError:
        shutil.rmtree(dirp, ignore_errors=True)
        dirp, man, rebuilt = ensure_cache(repo, force=True)
        hits = rrf([search(dirp, "records", expr, k), search(dirp, "chunks", expr, k)])

    live_files = len(corpus_files(repo))
    notices = []
    if man.get("n_files") != live_files:
        notices.append(f"index covers {man.get('n_files')} files, corpus now has {live_files}")
    for name in ("records", "chunks"):
        if not (dirp / f"{name}.db").exists():
            notices.append(f"document set {name!r} is MISSING from the cache")
    if notices:
        print("PARTIAL RECALL — " + "; ".join(notices))

    if "--stats" in flags:
        print(json.dumps(man, indent=1))
    print(
        f"index {man['counts']['records']} records + {man['counts']['chunks']} chunks "
        f"({'rebuilt ' + str(man['built_s']) + 's' if rebuilt else 'cached ' + man['built_at']})"
    )
    # AFTER the index line and on EVERY path that can produce it -- the counts come from the
    # manifest, so this fires identically on a fresh build and on a cache hit. Upstream printed the
    # line above and stopped, so a corpus whose ids the grammar does not describe returned chunks,
    # zero records, and exit 0 (spec S7).
    diag = E.zero_record_diagnosis(
        man["counts"]["records"], man["counts"]["chunks"], rebuild_hint=f"`{CLI} --rebuild`"
    )
    if diag:
        print(diag, file=sys.stderr)
    dead = dead_alias_diagnosis(man)
    if dead:
        print(dead, file=sys.stderr)
    print(f"{len(hits)} hits for: {question}\n")

    out, shown, spent, overflow = emit(hits, question + " " + " ".join(terms), budget)
    print(out)
    if shown < len(hits):
        print(
            f"shown {shown} of {len(hits)} within {budget:,} B "
            f"(used {spent:,} B) — raise --budget"
        )
    if overflow:
        print(f"note: the first hit alone exceeded the budget by {overflow:,} B")
    qid = log_event(
        repo,
        {
            "type": "query",
            "query": question,
            "terms": terms,
            "rewritten": bool(terms),
            "k": k,
            "budget": budget,
            "bytes_emitted": spent,
            "worktree": str(repo),
            "n_hits": len(hits),
            "n_shown": shown,
            # Top RESULT_CAP only. Embedding every fused hit cost 12 987 B per record (mean 131.8
            # results) -- a month of six-node traffic in hundreds of MB. `n_hits` above keeps the
            # TRUE total, so the cap shrinks the log without clamping the count. What is lost: the
            # log can no longer answer "was the right record at rank 40". `opened` records the rank
            # the caller actually read, the byte budget truncates the emitted list anyway, and a
            # deep-rank question re-runs the fixture -- which is what the fixture is for.
            "results": [
                {"set": h["set"], "id": h["id"], "path": h["path"], "line": h["line"]}
                for h in hits[:RESULT_CAP]
            ],
            # The ordered paths the caller was actually SHOWN, one per emitted hit, duplicates and
            # order preserved -- `shown_paths.index(p) + 1` IS the rank. This exists for the opened
            # -rank INFERENCE hook (spec-20 §8 Q1 pick (c), owner 2026-07-27): the hook cannot map a
            # path to a rank the log never recorded, and RESULT_CAP=5 alone would silently cap every
            # inferred rank at 5 -- reporting "the answer is always in the top 5" by construction.
            # Paths only: strings cost a fraction of the {set,id,path,line} objects the cap removed.
            "shown_paths": [h["path"] for h in hits[:shown]],
        },
    )
    # The qid, printed WITH the hits. Without it the caller cannot name the query they
    # meant, and `--opened` can only guess at the last row in a repo-wide log.
    if qid is not None:
        print(f"\nlogged as qid {qid} — record which hit answered it:\n"
              f"  {CLI} --opened <rank> --qid {qid}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
