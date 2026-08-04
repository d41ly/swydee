#!/usr/bin/env python3
"""Score retrieval substrates over the extracted document sets against a query fixture.

Rebuilt instrument for ARCH-bSiftedArchive-1. Standard library only -- no sklearn, no model files,
no network -- so it runs on all six nodes offline and cannot rot into an uninstallable dependency.

Substrates -- the first four are stdlib and always available; the last five need the optional stack:
  grep    literal scan for the query's rarest content word, UNRANKED, corpus order. This is what the
          corpus's retrieval path actually is today, and it is the baseline everything else beats.
  fts5    SQLite FTS5 + bm25(), one column
  fts5w   FTS5 with the head column (path + heading) weighted HEAD_WEIGHT x
  rm3     pseudo-relevance feedback -- mine the top RM3_DOCS hits for rare terms, re-query once
  tfidf   TF-IDF + cosine                                    [scikit-learn]
  lsa     TF-IDF + TruncatedSVD(256) + cosine                [scikit-learn]
  embed   minishlab/potion-base-8M, a real 256-dim static embedding model   [model2vec]
  hybrid  reciprocal-rank fusion of fts5 + embed             [model2vec]
  hybrid2 reciprocal-rank fusion of fts5w + embed            [model2vec]

For the optional five:
  uv run --with scikit-learn --with numpy --with model2vec python scripts/recall/bench.py ...

Metrics:
  recall@k  share of queries with >=1 expected doc in the top k
  full@k    share of queries where every expected TARGET is covered by >=1 retrieved doc
  MRR       mean reciprocal rank of the first hit (0 when the query misses entirely)
  bytes@k   mean bytes an agent must read to consume the top k -- the token-cost axis
  ceiling   share of queries whose expected docs exist in that set AT ALL. Separates
            "retrieval missed it" from "the data was never there" -- different bugs, different
            fixes.

Usage:
  python bench.py <data-dir> <fixture.json> [--sets spine,records,chunks]
                  [--subs grep,fts5,fts5w,rm3]
                  [--ks 1,5,10,20,50,100] [--slice all|hard|easy] [--json OUT]
"""

from __future__ import annotations

import json
import pathlib
import re
import sqlite3
import sys
import time
from collections import Counter

HEAD_WEIGHT = 8.0
RM3_DOCS = 3
RM3_TERMS = 8

STOP = set(
    """a an and are as at be but by for from has have how in into is it its of on or that the
    this to was were what when where which who why will with does do did can could should would
    my our your their there here if then than so not no yes get got make made use used using i
    you we they he she them us me about after before between during over under again more most
    some any all each other same such only own too very just now new old also been being had"""
    .split()
)

TOKEN = re.compile(r"[A-Za-z][A-Za-z0-9_]{1,}")


def terms(text: str) -> list[str]:
    return [t.lower() for t in TOKEN.findall(text) if t.lower() not in STOP and len(t) > 2]


def load(data: pathlib.Path, name: str) -> list[dict]:
    rows = []
    with (data / f"{name}.jsonl").open(encoding="utf-8") as fh:
        for line in fh:
            if line.strip():
                rows.append(json.loads(line))
    return rows


# Swept on the 99-query hard slice with 262 records aliased. 1.0 costs r@10 a point against the
# un-aliased baseline; 0.25-0.5 recovers it and lifts r@20 to 0.74 against 0.71. Weights >=4 are
# actively harmful (16.0 drops r@10 to 0.55). The alias text is a bridge, not evidence -- it should
# break ties, not win them.
ALIAS_WEIGHT = 0.4


def build_index(
    docs: list[dict], crumb: bool = False, db_path: str = ":memory:"
) -> sqlite3.Connection:
    """FTS5 index over three columns: ``head``, ``body`` and ``alias``.

    ``crumb=True`` folds each chunk's heading ancestry into the searchable head. The breadcrumb is a
    structural variant, not the default: a slice deep in a document loses every heading above it, so
    `Rules` under `Sanitization` under `Security` indexes as `Rules`.

    ``alias`` is its OWN column rather than text concatenated onto the body, because BM25 divides by
    document length: appending ~484 chars of alias text to a ~1 000-char record costs that record
    roughly a third of the weight of the terms it already had. Aliasing a record made it worse at
    matching its own vocabulary, and when rivals were aliased and the target was not, the penalty
    landed entirely on the target. A separate column keeps the bridge searchable without diluting
    the record, and lets ``bm25()`` weight the two independently.

    ``db_path`` defaults to ``":memory:"`` -- every benchmark caller keeps that and no measured
    number moves. ``query.py`` passes a file so the CLI's cache is built by the SAME builder the
    measurement uses; a second ``CREATE VIRTUAL TABLE`` elsewhere would be a second place for the
    column order and the alias weight to drift.
    """
    db = sqlite3.connect(db_path)
    db.execute("CREATE VIRTUAL TABLE d USING fts5(head, body, alias, tokenize='unicode61')")
    db.executemany(
        "INSERT INTO d(rowid, head, body, alias) VALUES (?,?,?,?)",
        [
            (
                i,
                " ".join(
                    x
                    for x in (
                        r.get("id", ""),
                        r["path"],
                        r["text"].split("\n", 1)[0],
                        r.get("crumb", "") if crumb else "",
                    )
                    if x
                ),
                r["text"],
                r.get("alias", ""),
            )
            for i, r in enumerate(docs)
        ],
    )
    return db


def parent_of(r: dict) -> str:
    """The coarse unit a fine-grained hit rolls up to."""
    return r.get("rec") or r.get("id") or r["path"]


def run_rollup(db, docs: list[dict], query: str, k: int, weighted: bool = False) -> list[int]:
    """Small-to-big: rank fine chunks, then keep only the best-ranked chunk per parent.

    The measured motivation: `chunks` reach everything (ceiling 1.00) and rank badly, `records` rank
    well and top out at 0.90. A top-20 of chunks can be twenty slices of three documents; deduping
    to the best chunk per parent buys back the diversity a record-level list has, without giving up
    the chunk set's reach.

    Measured worth: +0.04 to +0.05 recall on CHUNK-ONLY retrieval, and exactly +0.000 once the
    `records` set is in the ensemble -- that set already supplies the parent diversity this
    manufactures. Use it when querying chunks alone; do not expect it to move a two-set ensemble.
    """
    deep = run_fts(db, query, k * 8, weighted)
    seen, out = set(), []
    for i in deep:
        p = parent_of(docs[i])
        if p in seen:
            continue
        seen.add(p)
        out.append(i)
        if len(out) >= k:
            break
    return out


def match_expr(query: str) -> str:
    ts = terms(query)
    if not ts:
        return '"the"'
    # OR the terms. FTS5's query language treats most punctuation as syntax, so every term is
    # double-quoted -- an unquoted `use client` or `c++` is a syntax error, not a miss.
    return " OR ".join('"' + t.replace('"', "") + '"' for t in dict.fromkeys(ts))


def run_fts(db: sqlite3.Connection, query: str, k: int, weighted: bool) -> list[int]:
    expr = match_expr(query)
    hw = HEAD_WEIGHT if weighted else 1.0
    rank = f"bm25(d, {hw}, 1.0, {ALIAS_WEIGHT})"
    try:
        cur = db.execute(
            f"SELECT rowid FROM d WHERE d MATCH ? ORDER BY {rank} LIMIT ?", (expr, k)
        )
    except sqlite3.OperationalError:
        return []
    return [r[0] for r in cur.fetchall()]


def run_rm3(db: sqlite3.Connection, docs: list[dict], query: str, k: int) -> list[int]:
    seed = run_fts(db, query, RM3_DOCS, False)
    if not seed:
        return []
    df: Counter = Counter()
    for i in seed:
        df.update(set(terms(docs[i]["text"])[:400]))
    extra = [t for t, _ in df.most_common(RM3_TERMS * 3) if t not in set(terms(query))][:RM3_TERMS]
    return run_fts(db, query + " " + " ".join(extra), k, False)


KNOWN_FLAGS = ("--sets", "--subs", "--ks", "--slice", "--json", "--crumb")

LEXICAL = ("grep", "fts5", "fts5w", "rm3")
ROLLUP = ("roll", "rollw")
DENSE = ("tfidf", "lsa", "embed")
HYBRID = {"hybrid": "fts5", "hybrid2": "fts5w"}
RRF_K = 60
EMBED_MODEL = "minishlab/potion-base-8M"

_dense_cache: dict[tuple[int, str], object] = {}


def build_dense(docs: list[dict], kind: str):
    """Build a normalised dense matrix + a query encoder for one document set.

    Optional: needs scikit-learn (tfidf/lsa) or model2vec (embed). These are NOT stdlib, which is
    why the four lexical substrates stay importable without them -- the harness must still run
    offline on a node that has nothing installed. A missing dependency raises here with the install
    line rather than silently dropping the arm, because a silently-dropped arm is how the +0.000
    result went a month without being re-run.
    """
    key = (id(docs), kind)
    if key in _dense_cache:
        return _dense_cache[key]
    try:
        import numpy as np
    except ImportError as e:  # pragma: no cover - environment guard
        raise SystemExit(
            f"substrate {kind!r} needs numpy. Run under:\n"
            "  uv run --with scikit-learn --with numpy --with model2vec \\\n"
            "     python scripts/recall/bench.py ..."
        ) from e

    texts = [r["text"] for r in docs]
    if kind in ("tfidf", "lsa"):
        try:
            from sklearn.decomposition import TruncatedSVD
            from sklearn.feature_extraction.text import TfidfVectorizer
        except ImportError as e:  # pragma: no cover
            raise SystemExit(f"substrate {kind!r} needs scikit-learn (see --help)") from e
        vec = TfidfVectorizer(stop_words=sorted(STOP), min_df=2, max_features=200_000)
        X = vec.fit_transform(texts)
        if kind == "tfidf":

            def enc(q: str):
                return vec.transform([q])

            M = X
        else:
            svd = TruncatedSVD(n_components=256, random_state=0)
            M = svd.fit_transform(X)
            M = M / (np.linalg.norm(M, axis=1, keepdims=True) + 1e-9)

            def enc(q: str):
                v = svd.transform(vec.transform([q]))
                return v / (np.linalg.norm(v) + 1e-9)

    else:
        try:
            from model2vec import StaticModel
        except ImportError as e:  # pragma: no cover
            raise SystemExit(f"substrate {kind!r} needs model2vec (see --help)") from e
        model = StaticModel.from_pretrained(EMBED_MODEL)
        M = model.encode(texts)
        M = M / (np.linalg.norm(M, axis=1, keepdims=True) + 1e-9)

        def enc(q: str):
            v = model.encode([q])
            return v / (np.linalg.norm(v) + 1e-9)

    _dense_cache[key] = (M, enc, kind)
    return _dense_cache[key]


def run_dense(docs: list[dict], kind: str, query: str, k: int) -> list[int]:
    # build_dense FIRST: it owns the dependency guard and raises with the install line. Importing
    # numpy here first would surface a bare ModuleNotFoundError instead.
    M, enc, _ = build_dense(docs, kind)
    import numpy as np

    q = enc(query)
    if kind == "tfidf":
        sims = (M @ q.T).toarray().ravel()
    else:
        sims = (M @ np.asarray(q).ravel())
    if not sims.size:
        return []
    top = np.argpartition(-sims, min(k, sims.size - 1))[:k]
    return [int(i) for i in top[np.argsort(-sims[top])]]


def rrf(*rankings: list[int], k: int) -> list[int]:
    """Reciprocal-rank fusion -- the published harness's hybrid combiner."""
    score: dict[int, float] = {}
    for r in rankings:
        for rank, doc in enumerate(r, 1):
            score[doc] = score.get(doc, 0.0) + 1.0 / (RRF_K + rank)
    return [d for d, _ in sorted(score.items(), key=lambda kv: -kv[1])][:k]


def run_grep(docs: list[dict], dfreq: Counter, query: str, k: int) -> list[int]:
    """The corpus's real retrieval path: pick the rarest content word, scan, return corpus order."""
    ts = [t for t in dict.fromkeys(terms(query))]
    if not ts:
        return []
    needle = min(ts, key=lambda t: (dfreq.get(t, 0) == 0, dfreq.get(t, 10**9)))
    out = []
    for i, r in enumerate(docs):
        if needle in r["text"].lower():
            out.append(i)
            if len(out) >= k:
                break
    return out


def rank_with(sub, docs, db, dfreq, query: str, k: int):
    """One dispatcher for every substrate, shared by bench.py and union.py.

    Returns None for an unknown name so a typo shows as a missing row rather than as a zero score.
    """
    if sub == "grep":
        return run_grep(docs, dfreq, query, k)
    if sub == "fts5":
        return run_fts(db, query, k, False)
    if sub == "fts5w":
        return run_fts(db, query, k, True)
    if sub == "rm3":
        return run_rm3(db, docs, query, k)
    if sub == "roll":
        return run_rollup(db, docs, query, k, False)
    if sub == "rollw":
        return run_rollup(db, docs, query, k, True)
    if sub in DENSE:
        return run_dense(docs, sub, query, k)
    if sub in HYBRID:
        lex = run_fts(db, query, k, HYBRID[sub] == "fts5w")
        return rrf(lex, run_dense(docs, "embed", query, k), k=k)
    return None


def expected_by_target(
    docs: list[dict], q: dict, anchors: dict[str, list[str]]
) -> dict[str, set[int]]:
    """Map each expected TARGET to the documents in this set that satisfy it.

    Keyed by target rather than flattened to a document set, because `full@k` means "every target
    the query asked for is covered", not "every document that happens to match was retrieved". A
    query whose one id anchors across five chunks would otherwise need all five in the top k --
    measured at full@20 0.03 against a published 0.66, which is a metric bug, not a finding.

    Record-level docs carry an ``id``, so an expected id matches directly. Chunk-level docs do not,
    so the id resolves through the anchor map: a chunk counts only when it comes from a file where
    the id is anchored AND the chunk text carries the id. Path-only matching would credit all ~40
    chunks of a long file for one hit and quietly inflate chunk recall.
    """
    ids = [i.strip() for i in q.get("expected_ids", []) if i.strip()]
    paths = [p.strip().replace("\\", "/") for p in q.get("expected_paths", []) if p.strip()]
    out: dict[str, set[int]] = {}
    for tid in ids:
        anchor_paths = set(anchors.get(tid, []))
        hits = set()
        for i, r in enumerate(docs):
            if "id" in r:
                if r["id"] == tid:
                    hits.add(i)
            elif r["path"] in anchor_paths and tid in r["text"]:
                hits.add(i)
        if hits:
            out[tid] = hits
    for tp in paths:
        hits = {i for i, r in enumerate(docs) if r["path"] == tp}
        if hits:
            out["path:" + tp] = hits
    return out


def expected_hits(docs: list[dict], q: dict, anchors: dict[str, list[str]]) -> set[int]:
    """Flattened form of :func:`expected_by_target` -- every document that satisfies any target."""
    return {d for hs in expected_by_target(docs, q, anchors).values() for d in hs}


def score(docs, ranked: list[int], targets: dict[str, set[int]], ks: list[int]) -> dict:
    res = {}
    want = {d for hs in targets.values() for d in hs}
    first = next((n for n, d in enumerate(ranked, 1) if d in want), None)
    res["rr"] = 1.0 / first if first else 0.0
    for k in ks:
        top = set(ranked[:k])
        res[f"r@{k}"] = 1.0 if want & top else 0.0
        # every target covered by at least one retrieved doc
        res[f"f@{k}"] = 1.0 if targets and all(hs & top for hs in targets.values()) else 0.0
        res[f"b@{k}"] = sum(len(docs[d]["text"]) for d in ranked[:k])
    return res


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    data = pathlib.Path(sys.argv[1])
    fixture = json.loads(pathlib.Path(sys.argv[2]).read_text(encoding="utf-8"))
    argv = sys.argv

    def opt(flag, default):
        """Accept both `--flag value` and `--flag=value`.

        Supporting only the spaced form made `--slice=hard` fall through to the default and silently
        score the WRONG population -- a run that looks like a hard-slice result and is not. Measured
        the full 184 while labelled 99.
        """
        if flag in argv:
            return argv[argv.index(flag) + 1]
        for a in argv:
            if a.startswith(flag + "="):
                return a.split("=", 1)[1]
        return default

    for a in argv[1:]:
        if a.startswith("--") and a.split("=")[0] not in KNOWN_FLAGS:
            bad = a.split("=")[0]
            raise SystemExit(f"unknown flag {bad!r}; known: {' '.join(sorted(KNOWN_FLAGS))}")

    sets = opt("--sets", "spine,records,chunks").split(",")
    subs = opt("--subs", "grep,fts5,fts5w,rm3").split(",")
    ks = [int(x) for x in opt("--ks", "1,5,10,20,50,100").split(",")]
    sl = opt("--slice", "all")
    out_json = opt("--json", "")

    queries = fixture["queries"] if isinstance(fixture, dict) else fixture
    if sl == "hard":
        queries = [q for q in queries if q.get("shares_vocab") is False]
    elif sl == "easy":
        queries = [q for q in queries if q.get("shares_vocab") is True]

    anchors = json.loads((data / "anchors.json").read_text(encoding="utf-8"))
    print(f"fixture {len(queries)} queries (slice={sl})   ks={ks}")
    report = {"slice": sl, "n_queries": len(queries), "sets": {}}

    for sname in sets:
        docs = load(data, sname)
        dfreq: Counter = Counter()
        for r in docs:
            dfreq.update(set(terms(r["text"])[:600]))
        t0 = time.time()
        db = build_index(docs, crumb="--crumb" in argv)
        build_s = time.time() - t0
        wants = [expected_by_target(docs, q, anchors) for q in queries]
        ceiling = sum(1 for w in wants if w) / max(1, len(queries))
        print(
            f"\n=== {sname}: {len(docs)} docs, {sum(len(r['text']) for r in docs)} chars, "
            f"index {build_s:.2f}s, ceiling {ceiling:.2f}"
        )
        kf = ks[len(ks) // 2]
        kb = ks[min(2, len(ks) - 1)]
        print(
            "substrate  "
            + "".join(f"  r@{k:<4}" for k in ks)
            + f"  f@{kf:<5} MRR    b@{kb}"
        )
        report["sets"][sname] = {
            "docs": len(docs),
            "chars": sum(len(r["text"]) for r in docs),
            "index_s": round(build_s, 3),
            "ceiling": round(ceiling, 4),
            "substrates": {},
        }
        for sub in subs:
            acc = []
            t0 = time.time()
            for q, want in zip(queries, wants, strict=False):
                kmax = max(ks)
                ranked = rank_with(sub, docs, db, dfreq, q["query"], kmax)
                if ranked is None:
                    continue
                acc.append(score(docs, ranked, want, ks))
            if not acc:
                continue
            qs = time.time() - t0
            agg = {m: sum(a[m] for a in acc) / len(acc) for m in acc[0]}
            row = f"{sub:<10}" + "".join(f"  {agg[f'r@{k}']:<6.2f}" for k in ks)
            row += f"  {agg[f'f@{kf}']:<6.2f} {agg['rr']:.3f}  {agg[f'b@{kb}']:,.0f}"
            print(row + f"   ({qs * 1000 / max(1, len(acc)):.0f} ms/q)")
            report["sets"][sname]["substrates"][sub] = {
                m: round(v, 4) for m, v in agg.items()
            }
    if out_json:
        pathlib.Path(out_json).write_text(
            json.dumps(report, indent=2), encoding="utf-8", newline="\n"
        )
        print(f"\nwrote {out_json}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
