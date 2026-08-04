#!/usr/bin/env python3
"""Score ENSEMBLES of (document-set, substrate) pairs -- the shape a real query path would have.

A single substrate understates any real design, because an agent would hit more than one index and
read the merged shortlist. This is where the headline cost number comes from: recall of the union,
against the bytes an agent must actually read to consume it.

Two byte accountings are reported. Their difference is review-2 candidate 2's whole argument:

  bytes_full     every hit returned in full -- what the published 78.7 KB figure charged
  bytes_snippet  a query-biased window per hit plus its id/path/heading

recall@k is a property of the ranked list, not of how much of each hit you print, so both columns
describe the SAME recall. Whether an agent can still pick the right record off snippets alone is a
separate question this script does not answer -- it is the pick-accuracy arm review-2 asks for.

Usage:
  python union.py <data-dir> <fixture.json> [--k 20] [--slice all|hard|easy]
                  [--ens "records:fts5+chunks:fts5" ...] [--json OUT]
"""

from __future__ import annotations

import json
import pathlib
import sys

import bench as B

SNIPPET = 400  # chars of query-biased window per hit
OVERHEAD = 100  # id + path + heading printed beside each snippet

DEFAULT_ENS = [
    "records:fts5",
    "records:fts5+chunks:fts5",
    "records:fts5+records:fts5w+chunks:fts5",
    "records:fts5+records:fts5w+records:rm3+chunks:fts5+chunks:fts5w+chunks:rm3",
]


SETS = ("spine", "records", "chunks")
SUBS = tuple(B.LEXICAL) + tuple(B.ROLLUP) + tuple(B.DENSE) + tuple(B.HYBRID)


def is_ensemble(arg: str) -> bool:
    """`records:fts5+chunks:fts5` is an ensemble; `C:/tmp/out.json` is a Windows path."""
    if arg.startswith("-"):
        return False
    parts = arg.split("+")
    return all(
        p.count(":") == 1 and p.split(":")[0] in SETS and p.split(":")[1] in SUBS for p in parts
    )


def snippet_bytes(text: str, query: str) -> int:
    """Bytes of a query-biased window: the region around the first query term, capped."""
    ts = B.terms(query)
    low = text.lower()
    at = min((low.find(t) for t in ts if low.find(t) >= 0), default=0)
    start = max(0, at - SNIPPET // 3)
    return min(len(text) - start, SNIPPET) + OVERHEAD


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    data = pathlib.Path(sys.argv[1])
    fixture = json.loads(pathlib.Path(sys.argv[2]).read_text(encoding="utf-8"))
    argv = sys.argv

    def opt(flag, default):
        return argv[argv.index(flag) + 1] if flag in argv else default

    k = int(opt("--k", "20"))
    sl = opt("--slice", "all")
    out_json = opt("--json", "")
    # Validate against a real grammar rather than "contains a colon" -- on Windows the drive letter
    # in an --json path parses as a document set named "C".
    ens = [a for a in argv[3:] if is_ensemble(a)] or DEFAULT_ENS

    queries = fixture["queries"] if isinstance(fixture, dict) else fixture
    if sl == "hard":
        queries = [q for q in queries if q.get("shares_vocab") is False]
    elif sl == "easy":
        queries = [q for q in queries if q.get("shares_vocab") is True]

    anchors = json.loads((data / "anchors.json").read_text(encoding="utf-8"))
    names = sorted({p.split(":")[0] for e in ens for p in e.split("+")})
    sets, dbs, dfs, wants = {}, {}, {}, {}
    for n in names:
        sets[n] = B.load(data, n)
        dfs[n] = B.Counter()
        for r in sets[n]:
            dfs[n].update(set(B.terms(r["text"])[:600]))
        dbs[n] = B.build_index(sets[n])
        wants[n] = [B.expected_by_target(sets[n], q, anchors) for q in queries]

    def ranked(setname: str, sub: str, query: str) -> list[int]:
        r = B.rank_with(sub, sets[setname], dbs[setname], dfs[setname], query, k)
        return r or []

    print(f"fixture {len(queries)} queries (slice={sl}), per-source depth k={k}\n")
    print(f"{'ensemble':<62} {'recall':>7} {'full':>6} {'bytes_full':>11} {'bytes_snip':>11}")
    report = {"slice": sl, "k": k, "n_queries": len(queries), "ensembles": {}}

    for e in ens:
        pairs = [p.split(":") for p in e.split("+")]
        hit = full = 0
        bf = bs = 0
        for qi, q in enumerate(queries):
            per_set_hits: dict[str, set[int]] = {}
            for sn, sub in pairs:
                per_set_hits.setdefault(sn, set()).update(ranked(sn, sub, q["query"]))
            # A target counts as covered if ANY set in the ensemble retrieved a doc satisfying it.
            all_targets, covered = set(), set()
            for sn, ids in per_set_hits.items():
                for tgt, hs in wants[sn][qi].items():
                    all_targets.add(tgt)
                    if hs & ids:
                        covered.add(tgt)
                for d in ids:
                    t = sets[sn][d]["text"]
                    bf += len(t)
                    bs += snippet_bytes(t, q["query"])
            hit += 1 if covered else 0
            full += 1 if all_targets and covered >= all_targets else 0
        n = max(1, len(queries))
        rec, fl = hit / n, full / n
        print(f"{e:<62} {rec:>7.3f} {fl:>6.3f} {bf/n:>11,.0f} {bs/n:>11,.0f}")
        report["ensembles"][e] = {
            "recall": round(rec, 4),
            "full": round(fl, 4),
            "bytes_full": round(bf / n),
            "bytes_snippet": round(bs / n),
        }

    if out_json:
        pathlib.Path(out_json).write_text(
            json.dumps(report, indent=2), encoding="utf-8", newline="\n"
        )
        print(f"\nwrote {out_json}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
