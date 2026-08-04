#!/usr/bin/env python3
"""Build the retrieval document sets from the tracked corpus under ``$MEMORY_ROOT``.

FORKED from inCMS ``scripts/recall/extract.py`` at 5318064 (file last changed 958bd35c3; fd6274d
is that revision's tip and never touched this file). The fork is SIX constructs wide, so a future
re-pull is a three-way merge rather than archaeology: (1) ``FAMILIES``; (2) the node-tag class
inside ``ERAS``; (3) ``DURABLE``; (4) ``corpus_files()``; (5) the zero-record diagnosis, now two
branches; (6) ``sys.dont_write_bytecode`` above the ``recall_conf`` import plus
``CONF = recall_conf.resolve()`` -- upstream's blob has zero occurrences of either name. Count the
sixth: two of its three lines are load-bearing (without ``CONF``, ``FAMILIES = CONF.families`` is a
NameError, so a re-pull that drops them fails loudly), but ``dont_write_bytecode`` is the whole of
the kit's "writes nothing inside your worktree" property on this file and a re-pull can drop it in
silence -- the .pyc lands next to the source, inside the adopter's tree, and ``git status`` is
clean anyway because ``__pycache__/`` is a near-universal ignore rule. Everything else is
upstream's, byte for byte.

Rebuilt instrument for the upstream recall measurement. The original harness lived in a session
scratchpad and was lost with the session, which made every number it produced unfalsifiable. This
version is committed, stdlib-only, and runs anywhere git does.

Three document sets, because they fail differently and the measurement uses all of them:

  spine    one anchored record, definition homes only (DECISIONS.md / decisions/ / BACKLOG.md)
  records  one anchored record, anywhere -- including builds/, journals and archives
  chunks   heading-bounded slices of the whole corpus, capped at CHUNK_MAX chars

Usage:  python extract.py <repo-root> <out-dir> [--rev REV] [--aliases <path|none>]

``<repo-root>`` is the repo whose corpus is read; the id grammar and the corpus root always come
from the conf beside THIS kit, so run it inside the repo you are extracting.

Writes ``spine.jsonl``, ``records.jsonl``, ``chunks.jsonl``, ``anchors.json`` and
``orphan-ids.txt``.
Reading at a git rev (rather than the worktree) keeps a measurement reproducible against a sha.
"""

from __future__ import annotations

import hashlib
import json
import pathlib
import re
import subprocess
import sys
from collections import defaultdict

# ABOVE the sibling import, not below it: CPython writes a module's bytecode next to its SOURCE,
# which is inside the adopter's worktree. The kit's whole "a query writes nothing in your tree"
# property is one line, and it has to be this line (spec F5).
sys.dont_write_bytecode = True

import recall_conf  # noqa: E402

CONF = recall_conf.resolve()

# The three id eras of the memory-tree kit's id grammar, in one pattern:
#   flat          ARCH-001              (family, "001",            None)
#   node-scoped   ABL-d119              (family, "d119",           None)
#   session       ABL-bSiftedArchive-3  (family, "bSiftedArchive", "3")
# The family list is an allowlist on purpose: a bare \b[A-Z]{2,8}- pattern also matches WU, AC, SS,
# JSON, PII and a dozen other non-id tokens that outnumber several real families. FORKED: the
# allowlist is the conf's FAMILIES rather than eleven baked-in inCMS tokens.
FAMILIES = CONF.families
_NODE = CONF.node_tag_class
# The three eras, spelled out rather than approximated. A loose `[A-Za-z0-9]+` tail also swallows
# `ARCH-codebase`, `DES-admin`, `BLOCK-arm`, a charter's own `BBL-NNN` placeholder, and bare
# session slugs like `ARCH-dLayeredKeystone` (which is a prefix of the record `-1`, not an id) --
# measured upstream at +348 phantom ids and a 27% orphan rate against a true 9-10%.
ERAS = (
    r"\d{3}",  # flat            ARCH-001
    rf"[{_NODE}]\d{{2,3}}",  # node-scoped     ABL-d119
    rf"[{_NODE}][A-Za-z]{{2,}}-\d+",  # session-scoped  ABL-bSiftedArchive-3
)
# Built by concatenation, not % or .format(): a regex is full of `{2,6}` quantifiers that .format()
# reads as replacement fields.
ID = r"(?:" + "|".join(FAMILIES) + r")-(?:" + "|".join(ERAS) + r")"
ID_RE = re.compile(r"\b" + ID + r"\b")

# An anchor is a line that DEFINES a record, as opposed to one that merely cites it. Four shapes
# exist in this corpus and all four are load-bearing -- U4 of the unified build spec counts 759
# pipe-table rows against 407 charter-form dash rows across 7 table schemas.
# H1 is deliberately NOT an anchor. A build spec titles itself `# ARCH-aBoundGazetteer-1 — ...`, and
# an H1 anchor then owns the whole file down to the next H1 -- one 40 KB "record". Measured: records
# went 3 164 394 -> 8 507 443 indexed chars (mean 1 041 -> 2 572) against the published mean of
# 1 086. The H2-H6 rule reproduces the published byte profile; H1 destroys it.
A_HEADING = re.compile(r"^#{2,6}\s+[`*]*(" + ID + r")\b")
A_BOLD_LI = re.compile(r"^\s*[-*]\s+[`*]*(" + ID + r")\b[`*]*\s*[-—:·]")
# The first cell may carry trailing text -- `| **ABL-a085** (AC2 sweep) | ... |` is one of the 7
# table schemas U4 counts. Anchoring on cell 1 rather than on an exact cell match picks those up.
A_TABLE = re.compile(r"^\|\s*[`*]*(" + ID + r")\b[^|]*\|")
A_DASH = re.compile(r"^\s*[-*]\s+[`*]*(" + ID + r")\b[`*]*\s*[·|]")

# A record's DURABLE home. `archive/<INDEX>.<date>.md` is included: rotation MOVES an index, it does
# not retire its records, so a decision that lived in `DECISIONS.md` is still a decision after the
# file rotates (ARCH-aSmirkingBallast-4, owner 2026-07-28). Before this, the 2026-07-27 rotation
# dropped ids-with-a-durable-anchor 1778 -> 940 and left three fully-written PERF/ARCH records with
# no durable home at all.
#
# Blast radius, measured rather than assumed: DURABLE selects ONLY the `spine` document set
# (below). `anchors.json` is built from `records`, and `check_recall.py` grades `records`+`chunks`,
# so no gate and no merge-bar floor reads this. `bench.py --sets spine` moves; nothing else does.
_ROOT = re.escape(CONF.memory_root)  # FORKED: the corpus root is a conf value, not a literal
DURABLE = re.compile(
    rf"{_ROOT}/[^/]+/(DECISIONS|BACKLOG)\.md$"
    rf"|{_ROOT}/[^/]+/decisions/[^/]+\.md$"
    rf"|{_ROOT}/[^/]+/archive/(DECISIONS|BACKLOG)\.[^/]+\.md$"
)

CHUNK_MAX = 2400

# --- the alias layer ------------------------------------------------------------------------------
# The alias MECHANISM ships; no alias DATA does. Upstream's aliases.json is 915 515 bytes of
# questions authored against the inCMS corpus and joined by id, and no id in it exists anywhere
# else. An absent default is a legal alias-free corpus (see load_aliases), so an adopter runs with
# every alias cell empty until they author their own; drop an `aliases.json` in THIS directory and
# it is picked up with no config edit, and the cache rebuilds on the digest change.
#
# The join is by id, newline-joining each record's `questions` -- `bench.build_index` gives the
# `alias` key a separate, down-weighted FTS5 column, so bridge text is searchable without diluting
# the record's own vocabulary.
#
# Resolved beside THIS SCRIPT rather than under the repo root: script and data ship together, and
# both call sites (`main()` here and `query._docs`) hold a repo path that need not contain the kit
# directory at all -- a throwaway test repo does not.
ALIASES_DEFAULT = pathlib.Path(__file__).resolve().parent / "aliases.json"


class AliasError(RuntimeError):
    """An EXPLICITLY REQUESTED alias source that could not be read. An absent DEFAULT is not one."""


def git(repo: pathlib.Path, *args: str) -> str:
    return subprocess.run(
        ["git", "-C", str(repo), *args], capture_output=True, text=True, check=True
    ).stdout


def corpus_files(repo: pathlib.Path, rev: str | None) -> list[str]:
    root = CONF.memory_root + "/"  # FORKED: conf, not a literal `memory/`
    if rev:
        out = git(repo, "ls-tree", "-r", "--name-only", rev, root)
    else:
        out = git(repo, "ls-files", root)
    return sorted(p for p in out.splitlines() if p.endswith(".md"))


def read(repo: pathlib.Path, path: str, rev: str | None) -> str:
    if rev:
        try:
            return git(repo, "show", f"{rev}:{path}")
        except subprocess.CalledProcessError:
            return ""
    try:
        return (repo / path).read_text(encoding="utf-8", errors="replace")
    except OSError:
        return ""


def load_aliases(
    source: str | None = None, repo: pathlib.Path | None = None, rev: str | None = None
) -> tuple[dict[str, str], str, str]:
    """``(id -> alias block, resolved source, content digest)`` for one alias source.

    ``source`` is a path, the literal ``none``, or ``None`` for the committed default.

    The refusal fires ONLY on an explicitly requested but unreadable source. An absent DEFAULT is a
    legal alias-free corpus -- the selftest's throwaway repo is one -- while a caller that NAMED a
    file and got nothing would otherwise be handed a silent empty join, which is indistinguishable
    from a working one until a recall floor reds minutes later. Malformed JSON always refuses: a
    parse failure is never a legal alias-free corpus.

    Under ``--rev`` the blob is read AT THAT REV, so a measurement pinned to a sha is pinned on both
    halves rather than mixing that rev's corpus with the working tree's alias text. A file OUTSIDE
    that repo has no blob at any rev, so it is read from the worktree and the source string says
    so -- see the branch below.
    """
    if source == "none":
        return {}, "none", ""
    explicit = source is not None
    path = pathlib.Path(source).resolve() if explicit else ALIASES_DEFAULT
    raw: str | None = None
    off_rev = False
    if rev and repo is not None:
        rel = None
        try:
            rel = path.relative_to(repo).as_posix()
        except ValueError:
            rel = None
        if rel:
            try:
                raw = git(repo, "show", f"{rev}:{rel}")
            except subprocess.CalledProcessError:
                raw = None
        else:
            # The file is OUTSIDE the repo under measurement, so it HAS no blob at that
            # rev -- and the DEFAULT resolves beside this script, so every cross-tree
            # `--rev` run lands here. Read the worktree copy and SAY SO. Leaving `raw`
            # unset dropped through to the `(absent)` return below, which is the legal
            # alias-free corpus: a `--rev` run, the one path whose whole purpose is a
            # reproducible measurement, then scored an alias-free corpus behind a
            # success-looking summary line (ARCH-aGrittedFlagstone-4, closing review F7).
            try:
                raw = path.read_text(encoding="utf-8")
                off_rev = True
            except OSError:
                raw = None
    else:
        try:
            raw = path.read_text(encoding="utf-8")
        except OSError:
            raw = None
    if raw is None:
        if explicit:
            raise AliasError(
                f"aliases: cannot read {path}" + (f" at rev {rev}" if rev else "")
                + " — it was requested explicitly, so this is a refusal, not an empty join."
            )
        return {}, f"{path} (absent)", ""
    try:
        payload = json.loads(raw)
    except ValueError as e:
        raise AliasError(f"aliases: {path} is not valid JSON: {e}") from e
    rows = payload["aliases"] if isinstance(payload, dict) else payload
    by_id: dict[str, str] = {}
    for a in rows:
        rid = (a.get("id") or "").strip()
        block = "\n".join(str(q) for q in (a.get("questions") or []) if str(q).strip())
        if rid and block:
            by_id[rid] = block
    src_label = f"{path} (worktree, not at rev)" if off_rev else str(path)
    return by_id, src_label, hashlib.sha1(raw.encode("utf-8")).hexdigest()[:12]


def join_aliases(records: list[dict], by_id: dict[str, str]) -> int:
    """Set ``alias`` on every record whose id carries one. Returns how many were augmented.

    Records only. `chunks` stay alias-free (the handed measurement holds them constant) and so does
    `spine` -- its rows are copied off `records` BEFORE this runs, because `main()` derives spine as
    a filter over the SAME dict objects and `dump()` writes every key.
    """
    n = 0
    for r in records:
        block = by_id.get(r.get("id", ""))
        if block:
            r["alias"] = block
            n += 1
    return n


def zero_record_diagnosis(
    n_records: int, n_chunks: int, rebuild_hint: str = "--rebuild"
) -> str | None:
    """The mis-declared-FAMILIES failure, named. ``None`` when there is nothing to say.

    THE defect this port exists to close. The chunk arm is family-blind and works with zero
    configuration; the record arm is the only consumer of the id grammar. Point the conf at a
    corpus whose ids it does not describe and upstream returns "index 0 records + N chunks" and
    reports success -- a healthy-looking run that silently answers from half the index. Zero
    records is ALSO the honest state of a tree that has not written a decision yet, so this is a
    loud printed diagnosis rather than a refusal: it names the key, the conf, the families it
    resolved, and the escape hatch for a cache built before the conf was repaired.

    TWO branches, because 0 records + 0 chunks has a DIFFERENT cause and a single guard reading
    ``n_records or not n_chunks`` excluded it from every diagnosis. The chunk arm needs no id
    grammar, so an empty chunk arm cannot be FAMILIES -- it is MEMORY_ROOT, which is one of the
    three keys the adopter hand-edits and where a one-character typo produces exactly this.
    """
    if n_records:
        return None
    resolved = (
        f"  FAMILIES in {CONF.path.as_posix()} resolved to: {' '.join(CONF.families)}\n"
        f"  MEMORY_ROOT resolved to: {CONF.memory_root}\n"
    )
    if not n_chunks:
        return (
            "EMPTY CORPUS — no records AND no chunks: nothing reached the index at all.\n"
            + resolved
            + "  MEMORY_ROOT is the prime suspect: the chunk arm needs no id grammar, so FAMILIES\n"
              "  cannot cause this. Check it names a directory that exists, and that the files in\n"
              "  it are TRACKED — the corpus is read from the git index, so anything nobody\n"
              "  `git add`ed reads as absent.\n"
            + f"  After fixing the conf, re-run with {rebuild_hint} if the cache predates the fix."
        )
    return (
        f"ZERO RECORDS — the corpus produced {n_chunks} chunks and not one anchored record.\n"
        + resolved
        + "  Either no decision has been written yet, or FAMILIES does not describe this corpus's\n"
          "  ids. The chunk arm works without the grammar, so this is the only signal you get.\n"
        + f"  After fixing the conf, re-run with {rebuild_hint} if the cache predates the fix."
    )


def anchor_at(line: str) -> str | None:
    """Return the record id this line DEFINES, or None if it merely cites one."""
    for pat in (A_HEADING, A_BOLD_LI, A_TABLE, A_DASH):
        m = pat.match(line)
        if m:
            found = ID_RE.search(m.group(0))
            if found:
                return found.group(0)
    return None


def heading_level(line: str) -> int | None:
    m = re.match(r"^(#{1,6})\s", line)
    return len(m.group(1)) if m else None


def extract_records(path: str, text: str) -> list[dict]:
    """One document per anchored record.

    A heading anchor owns its section, down to the next heading of the same or higher level. A row
    anchor (list entry or table row) owns its own line plus indented continuations -- those rows run
    to 1-2 KB in this corpus, so the row IS the record.
    """
    lines = text.splitlines()
    docs, i = [], 0
    while i < len(lines):
        rid = anchor_at(lines[i])
        if not rid:
            i += 1
            continue
        lvl = heading_level(lines[i])
        start, j = i, i + 1
        if lvl is not None:
            while j < len(lines):
                nl = heading_level(lines[j])
                if nl is not None and nl <= lvl:
                    break
                j += 1
        else:
            while j < len(lines) and lines[j].strip() and not anchor_at(lines[j]):
                j += 1
        body = "\n".join(lines[start:j]).strip()
        if body:
            docs.append({"id": rid, "path": path, "line": start + 1, "text": body})
        i = max(j, i + 1)
    return docs


def extract_chunks(
    path: str, text: str, chunk_max: int = CHUNK_MAX, overlap: float = 0.0
) -> list[dict]:
    """Heading-bounded slices of the whole file, hard-capped at ``chunk_max`` chars.

    Each chunk also carries two structural fields, so alternative index shapes can be measured
    without re-extracting:

      ``crumb``  the heading ancestry above it (``H1 > H2 > H3``) -- context a bare slice loses
      ``rec``    the anchored record it sits inside, if any -- lets a hit roll up to its parent

    ``overlap`` (0..0.9) slides the window instead of tiling it, so an answer straddling a boundary
    is not split across two documents that each carry half of it.
    """
    lines = text.splitlines()
    bounds = [k for k, ln in enumerate(lines) if heading_level(ln) is not None] or [0]
    if bounds[0] != 0:
        bounds.insert(0, 0)
    bounds.append(len(lines))
    step = max(1, int(chunk_max * (1.0 - min(0.9, max(0.0, overlap)))))
    out: list[dict] = []
    stack: list[tuple[int, str]] = []
    cur_rec: str | None = None
    for a, b in zip(bounds, bounds[1:], strict=False):
        head_line = lines[a] if heading_level(lines[a]) is not None else ""
        lvl = heading_level(head_line) if head_line else None
        if lvl is not None:
            while stack and stack[-1][0] >= lvl:
                stack.pop()
            stack.append((lvl, re.sub(r"^#+\s*", "", head_line).strip()))
            found = anchor_at(head_line)
            if found:
                cur_rec = found
        crumb = " > ".join(t for _, t in stack)
        seg = "\n".join(lines[a:b]).strip()
        if not seg:
            continue
        base = {"path": path, "line": a + 1, "crumb": crumb}
        if cur_rec:
            base["rec"] = cur_rec
        # Long sections split into windows; each window re-carries the heading so a hit deep in a
        # section still names what it belongs to.
        if len(seg) <= chunk_max:
            out.append({**base, "text": seg})
        else:
            for off in range(0, len(seg), step):
                piece = seg[off : off + chunk_max]
                if not piece.strip():
                    continue
                out.append(
                    {
                        **base,
                        "text": piece if off == 0 or not head_line else head_line + "\n" + piece,
                    }
                )
                if off + chunk_max >= len(seg):
                    break
    return out


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    repo = pathlib.Path(sys.argv[1]).resolve()
    outdir = pathlib.Path(sys.argv[2])
    outdir.mkdir(parents=True, exist_ok=True)
    rev = None
    if "--rev" in sys.argv:
        rev = sys.argv[sys.argv.index("--rev") + 1]
    chunk_max = CHUNK_MAX
    if "--chunk-max" in sys.argv:
        chunk_max = int(sys.argv[sys.argv.index("--chunk-max") + 1])
    overlap = 0.0
    if "--overlap" in sys.argv:
        overlap = float(sys.argv[sys.argv.index("--overlap") + 1])
    asrc = None
    if "--aliases" in sys.argv:
        asrc = sys.argv[sys.argv.index("--aliases") + 1]

    # BEFORE the corpus scan: a refusal a caller waits 4.5 s for is one they will route around.
    try:
        by_id, alias_src, alias_digest = load_aliases(asrc, repo, rev)
    except AliasError as e:
        print(e, file=sys.stderr)
        return 1

    files = corpus_files(repo, rev)
    records, chunks = [], []
    anchors: dict[str, list[str]] = defaultdict(list)
    cited: set[str] = set()

    for path in files:
        text = read(repo, path, rev)
        if not text:
            continue
        cited.update(ID_RE.findall(text))
        for d in extract_records(path, text):
            records.append(d)
            anchors[d["id"]].append(path)
        chunks.extend(extract_chunks(path, text, chunk_max, overlap))

    # COPIES, and BEFORE the join: spine is a filter over the same dict objects and `dump()` writes
    # every key, so a join applied first would silently alias 2 505 of spine's 2 959 documents --
    # a document set no published figure was ever measured on (`alias_bench.py` copies spine
    # byte-for-byte from the un-augmented dir, so every figure came from an alias-FREE spine).
    spine = [dict(d) for d in records if DURABLE.search(d["path"])]
    n_aliased = join_aliases(records, by_id)
    unresolved = sorted(i for i in by_id if i not in anchors)

    def dump(name: str, rows: list[dict]) -> int:
        p = outdir / f"{name}.jsonl"
        with p.open("w", encoding="utf-8", newline="\n") as fh:
            for k, r in enumerate(rows):
                fh.write(json.dumps({"doc": k, **r}, ensure_ascii=False) + "\n")
        return sum(len(r["text"]) for r in rows)

    sizes = {n: dump(n, r) for n, r in (("spine", spine), ("records", records), ("chunks", chunks))}

    (outdir / "anchors.json").write_text(
        json.dumps({k: sorted(set(v)) for k, v in anchors.items()}, indent=0, sort_keys=True),
        encoding="utf-8",
        newline="\n",
    )
    orphans = sorted(cited - set(anchors))
    (outdir / "orphan-ids.txt").write_text(
        "\n".join(orphans) + "\n", encoding="utf-8", newline="\n"
    )

    durable_ids = {d["id"] for d in spine}
    print(f"corpus      {len(files):>7} files, rev={rev or 'worktree'}")
    diag = zero_record_diagnosis(len(records), len(chunks))
    if diag:
        print(diag, file=sys.stderr)
    for n, rows in (("spine", spine), ("records", records), ("chunks", chunks)):
        print(f"{n:<11} {len(rows):>7} docs, {sizes[n]:>10} indexed chars")
    print(f"ids cited   {len(cited):>7}")
    print(f"ids anchored{len(anchors):>7}  (durable home: {len(durable_ids)})")
    pct = 100 * len(orphans) / max(1, len(cited))
    print(f"orphan ids  {len(orphans):>7}  ({pct:.1f}% of cited)")
    # The source and its digest, so a recorded measurement names the blob it used. The two counts
    # are REPORTED here and pinned in `check_recall.py`: both move with corpus growth.
    print(f"aliases     {n_aliased:>7} records aliased  (ids {len(by_id)}, unresolved "
          f"{len(unresolved)}, digest {alias_digest or '-'}, source {alias_src})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
