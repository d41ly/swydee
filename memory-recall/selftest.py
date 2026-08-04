#!/usr/bin/env python3
"""memory-recall kit self-test — the kit's own contract, stdlib only.

    python memory-recall/selftest.py        # exit 0 = the kit's contract holds

What this gates is the KIT CONTRACT, not a recall floor. No adopter has a graded fixture, and a
floor re-derived from the run it grades cannot fail, so there is no honest threshold to pin. What
IS pinned: the parser-versus-bash parity, the no-conf refusal and its stub, the empty-alias path,
the write-nothing-in-the-worktree property BY PATH, the conf-digest freshness in both directions,
the zero-record diagnosis, cache eviction including the never-evict branch, the interpreter
fallback, and that every invocation the CLI prints resolves to a file that exists.

Every arm runs inside a throwaway git repo built from scratch. Upstream's selftest appended a
synthetic `refused` row to the shared query log on every run — 471 of 489 refusals in the live log
came from the gate that was grading it — so a leg that writes to the instrument it measures is a
hard rule here, and the last arm re-hashes the live log to prove this run did not touch it.
"""

from __future__ import annotations

import hashlib
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

# ABOVE the sys.path insert: this file imports the same siblings query.py does, so without it the
# gate leg itself drops __pycache__ into the adopter's worktree (spec F5/S12).
sys.dont_write_bytecode = True
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

import recall_conf  # noqa: E402

KIT = pathlib.Path(__file__).resolve().parent
SHIPPED = ("recall_conf.py", "extract.py", "bench.py", "union.py", "query.py", "selftest.py")

CONF = 'MEMORY_ROOT=memory\nFAMILIES="tooling:TOOL"\n'
CORPUS = """# Tooling decisions

- TOOL-aFoo-1 · the frobnicator was chosen over the quibbler because it leaks less
- TOOL-aFoo-2 · snark counting is deferred until the boojum harness exists
"""
Q = ("why was the frobnicator chosen", "--terms", "frobnicator quibbler leaks snark boojum")

INDEX_RE = re.compile(r"index (\d+) records \+ (\d+) chunks \((rebuilt|cached)")
# `python3?` on purpose: every launcher this kit prints is resolved python3-first, so a pattern
# anchored on bare `python ` silently matched nothing on a python3 host — the arm below would then
# have folded an empty set and passed vacuously.
INVOKE_RE = re.compile(r"python3? ([A-Za-z0-9_./-]+\.py)")

_checks: list[tuple[str, str, str]] = []  # (state, name, detail)


def check(name):
    def deco(fn):
        try:
            detail = fn() or ""
            _checks.append(("ok", name, detail))
        except _Skip as exc:
            _checks.append(("skip", name, str(exc)))
        except Exception as exc:  # noqa: BLE001 — a crash is a failure, not a stack trace
            _checks.append(("FAIL", name, f"{type(exc).__name__}: {exc}"))
        return fn

    return deco


class _Skip(Exception):
    """This arm could not run here, and says why. Reported separately — never counted as passed."""


# ------------------------------------------------------------------ throwaway repo construction


def make_repo(kitname: str = "memory-recall", conf: str = CONF, gitignore: str | None = None):
    """A git repo with the kit copied in, a two-record corpus, and NO __pycache__ ignore rule.

    The ignore rule is deliberately absent: `git status --porcelain` is also clean when a write was
    merely HIDDEN, so a status-based check cannot tell "wrote nothing" from "wrote something we
    ignored". The AC4 arm enumerates paths instead, and it must do so in a tree with nothing hiding.
    """
    root = pathlib.Path(tempfile.mkdtemp(prefix="mrecall-")).resolve()
    subprocess.run(
        ["git", "-c", "init.defaultBranch=main", "init", "-q", str(root)],
        check=True, capture_output=True,
    )
    kitdir = root / kitname
    kitdir.mkdir(parents=True)
    for f in SHIPPED:
        shutil.copyfile(KIT / f, kitdir / f)
    (root / ".memory-tree.conf").write_text(conf, encoding="utf-8", newline="\n")
    disc = root / "memory" / "tooling"
    disc.mkdir(parents=True)
    (disc / "DECISIONS.md").write_text(CORPUS, encoding="utf-8", newline="\n")
    if gitignore is not None:
        (root / ".gitignore").write_text(gitignore, encoding="utf-8", newline="\n")
    # Staged, not committed: `git ls-files` reads the INDEX, and extract.py's corpus_files is
    # tracked-only on purpose (it is the measurement path). Without this it sees an empty corpus.
    subprocess.run(["git", "-C", str(root), "add", "-A"], check=True, capture_output=True)
    return root, kitdir


def run(root: pathlib.Path, kitdir: pathlib.Path, *args: str, script: str = "query.py"):
    return subprocess.run(
        [sys.executable, str(kitdir / script), *args],
        cwd=str(root), capture_output=True, text=True,
    )


def index_of(proc) -> tuple[int, int, str]:
    m = INDEX_RE.search(proc.stdout)
    assert m, f"no index header in output:\n{proc.stdout}\n{proc.stderr}"
    return int(m.group(1)), int(m.group(2)), m.group(3)


def git_common_dir(root: pathlib.Path) -> pathlib.Path:
    raw = subprocess.run(
        ["git", "-C", str(root), "rev-parse", "--git-common-dir"],
        capture_output=True, text=True, check=True,
    ).stdout.strip()
    p = pathlib.Path(raw)
    return p.resolve() if p.is_absolute() else (root / raw).resolve()


def tree(base: pathlib.Path, skip=(".git",)) -> set[str]:
    out = set()
    for dirpath, dirnames, filenames in os.walk(base):
        dirnames[:] = [d for d in dirnames if d not in skip]
        for f in filenames:
            out.add(str(pathlib.Path(dirpath, f).relative_to(base)))
    return out


def cache_of(root: pathlib.Path) -> pathlib.Path:
    key = hashlib.sha1(str(root).encode()).hexdigest()[:12]
    return git_common_dir(root) / "recall" / "cache" / key


def cleanup(root: pathlib.Path) -> None:
    shutil.rmtree(root, ignore_errors=True)


# ------------------------------------------------------------------------------------ the arms


@check("conf parser == bash (the grammar's documented cases)")
def t_parser_vs_bash():
    """Asserted against BASH, never against a second Python parser.

    `recall_conf.load_conf` is a copy of codebase-map's twenty-line parser (kits are copied into
    adopters independently, so importing across kit directories is not available). Comparing it to
    another Python parser would be an assertion whose two operands share a generator; bash sourcing
    the same file is the only independent oracle.
    """
    bash = shutil.which("bash")
    if not bash:
        raise _Skip("no bash on PATH — the only independent oracle for the conf grammar")
    root = pathlib.Path(tempfile.mkdtemp(prefix="mrecall-conf-")).resolve()
    try:
        (root / ".memory-tree.conf").write_text(
            "# leading comment\n"
            "\n"
            "MEMORY_ROOT=memory   # trailing comment on an unquoted value\n"
            'export FAMILIES="tooling:TOOL playbook:PLAY"\n'
            'SPACED="a value with spaces"\n'
            "PLAIN=plain\n",
            encoding="utf-8", newline="\n",
        )
        keys = ["MEMORY_ROOT", "FAMILIES", "SPACED", "PLAIN"]
        script = ". '%s'; printf '%%s\\n' %s" % (
            (root / ".memory-tree.conf").as_posix(),
            " ".join(f'"${k}"' for k in keys),
        )
        proc = subprocess.run([bash, "-c", script], capture_output=True, text=True)
        assert proc.returncode == 0, f"bash could not source the conf: {proc.stderr.strip()!r}"
        from_bash = dict(zip(keys, proc.stdout.replace("\r\n", "\n").rstrip("\n").split("\n")))
        from_py = recall_conf.load_conf(root)
        for k in keys:
            assert from_py.get(k) == from_bash[k], (
                f"{k}: python {from_py.get(k)!r} != bash {from_bash[k]!r}"
            )
        return f"{len(keys)} keys agree with bash"
    finally:
        cleanup(root)


@check("no conf: query.py refuses, names memory-tree, prints a usable stub, creates nothing")
def t_no_conf_query():
    root, kitdir = make_repo()
    try:
        (root / ".memory-tree.conf").unlink()
        proc = run(root, kitdir, *Q)
        assert proc.returncode == 2, f"exit {proc.returncode}, want 2"
        err = proc.stderr
        assert "memory-tree" in err, "the refusal must name the prerequisite kit"
        assert "MEMORY_ROOT=memory" in err and "FAMILIES=" in err, "no copy-pasteable stub"
        assert not (root / ".memory-tree.conf").exists(), "the refusal scaffolded a conf"
        # AC3's second half: the stub, pasted verbatim and given real values, works.
        stub = [ln.strip() for ln in err.splitlines() if ln.strip().startswith(("MEMORY_ROOT", "FAMILIES"))]
        assert len(stub) == 2, f"stub is {stub}"
        pasted = (stub[0] + "\n" + stub[1].replace("<discipline>:<FAMILY> ...", "tooling:TOOL")) + "\n"
        (root / ".memory-tree.conf").write_text(pasted, encoding="utf-8", newline="\n")
        after = run(root, kitdir, *Q)
        assert after.returncode == 0, f"the pasted stub did not work: {after.stderr}"
        n_rec, _, _ = index_of(after)
        assert n_rec == 2, f"{n_rec} records after pasting the stub"
        # R1: the conf is the single source. A second way to declare the same values — a flag that
        # silently overrode it — is the hand-kept-second-copy defect this port exists to remove.
        for flag in ("--memory-root", "--families"):
            bad = run(root, kitdir, *Q, flag, "x")
            assert bad.returncode == 2 and "unknown flag" in bad.stderr, f"{flag} was accepted"
        return "exit 2, stub pasted -> 2 records, no --memory-root/--families"
    finally:
        cleanup(root)


@check("no conf: adopt-memory-recall.sh refuses and creates nothing")
def t_no_conf_adopt():
    bash = shutil.which("bash")
    if not bash:
        raise _Skip("no bash on PATH")
    root, kitdir = make_repo()
    try:
        shutil.copyfile(KIT / "adopt-memory-recall.sh", kitdir / "adopt-memory-recall.sh")
        (root / ".memory-tree.conf").unlink()
        proc = subprocess.run(
            [bash, str(kitdir / "adopt-memory-recall.sh"), "--check"],
            cwd=str(root), capture_output=True, text=True,
        )
        assert proc.returncode != 0, "the adopt script accepted a repo with no conf"
        assert "memory-tree" in proc.stderr + proc.stdout, "refusal must name the prerequisite kit"
        assert not (root / ".memory-tree.conf").exists(), "the adopt script scaffolded a conf"
        return f"exit {proc.returncode}, no conf written"
    finally:
        cleanup(root)


@check("index builds and ranks with NO alias data (the empty-alias path is first class)")
def t_empty_alias():
    root, kitdir = make_repo()
    try:
        proc = run(root, kitdir, *Q)
        assert proc.returncode == 0, proc.stderr
        n_rec, n_chunk, state = index_of(proc)
        assert (n_rec, state) == (2, "rebuilt"), f"{n_rec} records, {state}"
        assert n_chunk >= 1, f"{n_chunk} chunks"
        assert " hits for: " in proc.stdout and "[1] " in proc.stdout, "empty ranked list"
        man = json.loads((cache_of(root) / "manifest.json").read_text(encoding="utf-8"))
        assert man["alias_digest"] == "", f"alias digest {man['alias_digest']!r} with no alias file"
        assert "ZERO RECORDS" not in proc.stderr, "false diagnosis on a healthy corpus"
        assert "DEAD ALIAS LAYER" not in proc.stderr, "dead-alias fired with NO alias file"
        return f"{n_rec} records + {n_chunk} chunks, alias digest empty, ranked list non-empty"
    finally:
        cleanup(root)


@check("mis-declared FAMILIES is LOUD: zero records diagnosed, not reported as success")
def t_zero_records_is_loud():
    root, kitdir = make_repo(conf='MEMORY_ROOT=memory\nFAMILIES="tooling:ZZZZ"\n')
    try:
        proc = run(root, kitdir, *Q)
        n_rec, n_chunk, _ = index_of(proc)
        assert n_rec == 0 and n_chunk > 0, f"{n_rec} records / {n_chunk} chunks — wrong fixture"
        err = proc.stderr
        assert "ZERO RECORDS" in err, f"the silent zero stayed silent:\n{err}"
        assert "FAMILIES" in err and "ZZZZ" in err, "the diagnosis does not name the resolved key"
        assert ".memory-tree.conf" in err, "the diagnosis does not name the conf path"
        assert "--rebuild" in err, "the diagnosis does not name the escape hatch"
        # ...and the same diagnosis on extract.py's own path, which can produce the same state.
        out = pathlib.Path(tempfile.mkdtemp(prefix="mrecall-x-"))
        try:
            ex = run(root, kitdir, str(root), str(out), script="extract.py")
            assert "ZERO RECORDS" in ex.stderr, "extract.py reports the silent zero as success"
            # extract.py is the one entry point the query path does not go through, so its own
            # `sys.dont_write_bytecode` is the whole of "writes nothing in your worktree" here —
            # and deleting that line SURVIVED the entire suite until this assertion existed. Not
            # a `git status` check: `__pycache__/` is a near-universal ignore rule, so a status
            # is clean whether nothing was written or the write was merely hidden.
            pyc = sorted(p for p in tree(root) if "__pycache__" in p)
            assert not pyc, f"extract.py wrote bytecode into the worktree: {pyc}"
        finally:
            cleanup(out)
        return "diagnosed on both paths, and extract.py wrote no bytecode"
    finally:
        cleanup(root)


@check("an EMPTY corpus is diagnosed too, and names MEMORY_ROOT — FAMILIES cannot cause it")
def t_empty_corpus_names_memory_root():
    """A one-character MEMORY_ROOT typo produced 0 records + 0 chunks, 0 hits and exit 0.

    The old guard read `if n_records or not n_chunks: return None`, so the one state the record
    diagnosis could NOT describe was the one where the chunk arm is empty too — and the chunk arm
    is the family-blind half, so its emptiness is never a FAMILIES problem. MEMORY_ROOT is one of
    the three keys the adopter hand-edits.
    """
    root, kitdir = make_repo(conf='MEMORY_ROOT=no-such-corpus\nFAMILIES="tooling:TOOL"\n')
    try:
        proc = run(root, kitdir, *Q)
        n_rec, n_chunk, _ = index_of(proc)
        assert (n_rec, n_chunk) == (0, 0), f"{n_rec} records / {n_chunk} chunks — wrong fixture"
        err = proc.stderr
        assert "EMPTY CORPUS" in err, f"0 records + 0 chunks was reported as success:\n{err}"
        assert "MEMORY_ROOT" in err, "the diagnosis does not name the suspect key"
        assert "no-such-corpus" in err, "the diagnosis does not name the resolved value"
        return "0 records + 0 chunks -> EMPTY CORPUS naming MEMORY_ROOT"
    finally:
        cleanup(root)


@check("conf_digest joins freshness: a FAMILIES edit rebuilds, and the repair rebuilds back")
def t_conf_digest_both_directions():
    """The blocker. The corpus digest is mtime+size over the tree's .md files, so a conf edit never
    enters it; without conf_digest in the manifest the S7 remediation is a silent no-op in BOTH
    directions — the diagnosis fires, the adopter fixes the conf, and the cache keeps answering.
    Asserting the message alone is insufficient: both directions must MOVE the count.
    """
    root, kitdir = make_repo()
    conf = root / ".memory-tree.conf"
    try:
        first = index_of(run(root, kitdir, *Q))
        assert first == (2, first[1], "rebuilt"), first
        warm = index_of(run(root, kitdir, *Q))
        assert warm[2] == "cached", f"second run did not hit the cache: {warm}"
        conf.write_text('MEMORY_ROOT=memory\nFAMILIES="tooling:ZZZZ"\n', encoding="utf-8", newline="\n")
        broken = index_of(run(root, kitdir, *Q))
        assert broken[2] == "rebuilt", f"a FAMILIES edit did not invalidate the cache: {broken}"
        assert broken[0] == 0, f"records did not move to zero: {broken}"
        conf.write_text(CONF, encoding="utf-8", newline="\n")
        fixed = index_of(run(root, kitdir, *Q))
        assert fixed[2] == "rebuilt", f"the repair did not invalidate the cache: {fixed}"
        assert fixed[0] == 2, f"records did not come back: {fixed}"
        return f"{first[0]} -> cached -> {broken[0]} (rebuilt) -> {fixed[0]} (rebuilt)"
    finally:
        cleanup(root)


@check("a query writes NOTHING in the worktree — asserted by path, with no ignore rule present")
def t_writes_nothing_in_worktree():
    root, kitdir = make_repo()
    try:
        assert not (root / ".gitignore").exists(), "fixture must carry no ignore rule"
        before = tree(root)
        proc = run(root, kitdir, *Q)
        assert proc.returncode == 0, proc.stderr
        after = tree(root)
        new = sorted(after - before)
        assert not new, f"the query wrote {len(new)} file(s) inside the worktree: {new}"
        kit_new = sorted(p for p in new if p.startswith(kitdir.name))
        assert not kit_new, f"files landed in the kit directory: {kit_new}"
        assert not any("__pycache__" in p for p in after), "bytecode landed in the worktree"
        created = tree(git_common_dir(root) / "recall")
        assert created, "the query created nothing under the common git dir either"
        status = subprocess.run(
            ["git", "-C", str(root), "status", "--porcelain"], capture_output=True, text=True,
        ).stdout
        return f"{len(created)} files, all under <gitdir>/recall; worktree unchanged; status {len(status.splitlines())} rows"
    finally:
        cleanup(root)


@check("an alias file dropped in the kit dir rebuilds the cache and lands in the manifest")
def t_alias_rebuild():
    root, kitdir = make_repo()
    try:
        run(root, kitdir, *Q)
        before = json.loads((cache_of(root) / "manifest.json").read_text(encoding="utf-8"))
        assert before["alias_digest"] == ""
        (kitdir / "aliases.json").write_text(
            json.dumps([{"id": "TOOL-aFoo-1", "questions": ["how do I pick a frobnicator"]}]),
            encoding="utf-8", newline="\n",
        )
        proc = run(root, kitdir, *Q)
        n_rec, _, state = index_of(proc)
        assert state == "rebuilt", "an alias edit did not invalidate the cache"
        after = json.loads((cache_of(root) / "manifest.json").read_text(encoding="utf-8"))
        assert after["alias_digest"], "the manifest did not record the new alias digest"
        assert n_rec == 2, n_rec
        # The join that WORKS: counted in the manifest, and silent. A diagnosis that also
        # fires here would be a gate that reds the terminal success state.
        assert after["aliases"]["joined"] == 1, after["aliases"]
        assert "DEAD ALIAS LAYER" not in proc.stderr, "dead-alias fired on a LIVE alias layer"
        return (
            f"alias digest '' -> {after['alias_digest']}, "
            f"{after['aliases']['joined']}/{after['aliases']['ids']} joined, silent"
        )
    finally:
        cleanup(root)


@check("an alias layer that joins to ZERO records is diagnosed, not silently dead")
def t_dead_alias_is_loud():
    """`query.py` discarded `join_aliases`' return, so a 100%-dead alias column was reported
    NOWHERE — the dead-plumbing class one layer inside the tool built to close it. An adopter
    authoring aliases against the wrong id family gets a silently empty third FTS5 column whose
    only symptom is slightly worse ranking, and `--stats` carried a content hash that says nothing
    about coverage. The record and chunk arms are unaffected, which is why nothing else can see it.
    """
    root, kitdir = make_repo()
    try:
        (kitdir / "aliases.json").write_text(
            json.dumps([{"id": "ZZZZ-aFoo-1", "questions": ["how do I pick a frobnicator"]}]),
            encoding="utf-8", newline="\n",
        )
        proc = run(root, kitdir, *Q)
        assert proc.returncode == 0, proc.stderr
        n_rec, n_chunk, _ = index_of(proc)
        assert (n_rec, n_chunk > 0) == (2, True), f"{n_rec} records / {n_chunk} chunks — wrong fixture"
        err = proc.stderr
        assert "DEAD ALIAS LAYER" in err, f"a 100%-dead alias column stayed silent:\n{err}"
        assert "aliases.json" in err, "the diagnosis does not name the alias source"
        assert "TOOL" in err, "the diagnosis does not name the resolved families"
        man = json.loads((cache_of(root) / "manifest.json").read_text(encoding="utf-8"))
        assert (man["aliases"]["ids"], man["aliases"]["joined"]) == (1, 0), man["aliases"]
        # ...and on a CACHE HIT, which is the state a session is actually in: the counts come from
        # the manifest for exactly this reason, and a re-run must not go quiet.
        again = run(root, kitdir, *Q)
        assert index_of(again)[2] == "cached", "fixture did not reach the cached path"
        assert "DEAD ALIAS LAYER" in again.stderr, "the diagnosis is fresh-build-only"
        # ...and a cache built BEFORE this fix carries no alias counts at all, so the manifest the
        # diagnosis reads is empty of them. The CACHE_VERSION bump is the whole of what stops such
        # a cache from keeping the very silence this fix removes: doctor a manifest into that shape
        # and the next query must REBUILD and diagnose, not serve the pre-fix index.
        mf = cache_of(root) / "manifest.json"
        stale = json.loads(mf.read_text(encoding="utf-8"))
        stale.pop("aliases")
        stale["version"] = 2
        mf.write_text(json.dumps(stale, indent=1), encoding="utf-8", newline="\n")
        third = run(root, kitdir, *Q)
        assert index_of(third)[2] == "rebuilt", "a pre-fix manifest was served from cache"
        assert "DEAD ALIAS LAYER" in third.stderr, "a pre-fix cache kept the silence"
        return "1 alias id, 0 joined -> diagnosed on rebuild, on cache hit, and past a pre-fix cache"
    finally:
        cleanup(root)


@check("cache eviction: dead worktree evicted, live worktree kept, no-manifest NEVER evicted")
def t_eviction():
    """One predicate read in two directions: rebuild MINE, never delete THEIRS.

    The builder writes both .db files BEFORE the manifest, deliberately and atomically, so a
    directory with no readable manifest is exactly the shape of a sibling mid-first-build. Evicting
    it deletes a live cache while its builder is still writing.
    """
    root, kitdir = make_repo()
    try:
        run(root, kitdir, *Q)
        caches = cache_of(root).parent
        dead, live, mid = caches / "deadcache", caches / "livecache", caches / "midbuild"
        for d in (dead, live, mid):
            d.mkdir(parents=True)
            (d / "records.db").write_bytes(b"")
            (d / "chunks.db").write_bytes(b"")
        (dead / "manifest.json").write_text(
            json.dumps({"worktree": str(root / "no" / "such" / "tree")}), encoding="utf-8"
        )
        (live / "manifest.json").write_text(json.dumps({"worktree": str(root)}), encoding="utf-8")
        # `mid` gets NO manifest at all — the reachable third case.
        proc = run(root, kitdir, *Q, "--rebuild")
        assert proc.returncode == 0, proc.stderr
        assert not dead.exists(), "a cache for a vanished worktree survived"
        assert live.exists(), "a cache for a LIVE worktree was evicted"
        assert mid.exists(), "a mid-first-build cache (no readable manifest) was evicted"
        assert "evicted" in proc.stderr, "the eviction was silent"
        return "dead evicted, live kept, no-manifest kept"
    finally:
        cleanup(root)


def copy_extra(kitdir: pathlib.Path, *names: str) -> None:
    """The Skill/hook surface, which make_repo leaves out because the query arms do not need it."""
    for n in names:
        shutil.copyfile(KIT / n, kitdir / n)


def adopt(root: pathlib.Path, kitdir: pathlib.Path, *args: str):
    bash = shutil.which("bash")
    if not bash:
        raise _Skip("no bash on PATH")
    return subprocess.run(
        [bash, str(kitdir / "adopt-memory-recall.sh"), *args],
        cwd=str(root), capture_output=True, text=True,
    )


SKILL_REL = pathlib.Path(".claude/skills/memory-recall/SKILL.md")
SURFACE = ("adopt-memory-recall.sh", "SKILL.template.md", "recall-opened.js",
           "recall-opened.fragment.json")


def settings_merge_src() -> pathlib.Path | None:
    """The wiring tool, wherever THIS repo keeps it: beside the kit here, under tools/ in an adopter."""
    for c in (KIT.parent / "settings-merge.py", recall_conf.repo_root() / "tools" / "settings-merge.py"):
        if c.is_file():
            return c
    return None


@check("every invocation the CLI and the --with-hook remedy print resolves to a real file")
def t_printed_invocations_resolve():
    """The fixture kit dir is spelled like NEITHER layout, so a baked-in path cannot pass by luck.

    Not `memory-recall`: WIRE §3c step 1 mandates exactly that name in an adopter, so a fixture
    spelled that way made the `here != kitdir.name` guard below trip in every conformant adopter —
    the kit's own mandated gate leg, red on arrival. The guard still holds against both spellings.
    """
    smerge = settings_merge_src()
    if smerge is None:
        raise _Skip("settings-merge.py not found beside the kit — cannot build the post-WIRE state")
    root, kitdir = make_repo(kitname="mrecall-fixture-kit")
    try:
        here = KIT.relative_to(recall_conf.repo_root()).as_posix()
        assert here != kitdir.name, f"fixture kit dir must not spell like this repo's ({here})"
        assert kitdir.name != "memory-recall", "fixture kit dir spells the ADOPTER's mandated name"
        seen: set[str] = set()
        helped = run(root, kitdir, "--help")
        refused = run(root, kitdir, "why was the frobnicator chosen")
        answered = run(root, kitdir, *Q)
        assert refused.returncode == 2 and "--terms" in refused.stderr
        # The hook opt-in's remedy is the kit's OTHER printed invocation, and it was the one naming
        # a path no runbook step created (errno 2 when run verbatim). The fixture is built to the
        # post-WIRE state — §3c step 4 copies the wiring tool into <project>/tools/ — so the remedy
        # is checked against the tree the runbook actually produces.
        copy_extra(kitdir, *SURFACE)
        (root / "tools").mkdir()
        shutil.copyfile(smerge, root / "tools" / "settings-merge.py")
        hooked = adopt(root, kitdir, "--scaffold", "--with-hook")
        assert hooked.returncode == 0, f"{hooked.stdout}{hooked.stderr}"
        for proc in (helped, refused, answered, hooked):
            seen |= set(INVOKE_RE.findall(proc.stdout + proc.stderr))
        assert seen, "the CLI printed no invocation at all"
        # RELATIVE first, because it is the specific diagnosis: `root / p` DISCARDS root when p is
        # absolute, so an absolute REL — what a no-op prefix strip produces when two spellings of
        # one directory disagree — resolves happily against the check below on a POSIX node and
        # then ships a machine-local path in a COMMITTED artifact. Asserted directly because the
        # fixture cannot make the two spellings disagree.
        absolute = sorted(p for p in seen if p.startswith("/") or re.match(r"^[A-Za-z]:", p))
        assert not absolute, f"printed invocations carry an absolute path: {absolute}"
        missing = sorted(p for p in seen if not (root / p).is_file())
        assert not missing, f"printed invocations naming files that do not exist: {missing}"
        # The CLI's OWN launcher, which is a literal and must be `python3` — a stock Debian/Ubuntu
        # adopter has no `python`. The adopt script's lines are deliberately NOT scanned: those carry
        # the RESOLVED $PY, and on a node with no python3 `python` is the correct answer there.
        cli_lines = [ln.strip() for p in (helped, refused, answered)
                     for ln in (p.stdout + p.stderr).splitlines() if ".py" in ln]
        bare = [ln for ln in cli_lines if re.search(r"\bpython(?!3)\s+\S*\.py", ln)]
        assert not bare, f"the CLI prints a bare-`python` launcher: {bare}"
        py3 = [ln for ln in cli_lines if re.search(r"\bpython3\s+\S*\.py", ln)]
        assert py3, "the CLI printed no python3 launcher at all — the scan above is vacuous"
        assert any("query.py" in p for p in seen)
        # Non-vacuity: the fold above is worthless if the remedy line never reaches `seen`.
        assert any("settings-merge.py" in p for p in seen), "the --with-hook remedy printed no invocation"
        return f"{len(seen)} distinct printed path(s), all resolve: {sorted(seen)}"
    finally:
        cleanup(root)


@check("adopt --check runs with `python` off PATH and only `python3` available")
def t_python3_only():
    """A node with both binaries can never see this defect, so PATH is cut down to prove it."""
    bash = shutil.which("bash")
    git = shutil.which("git")
    if not (bash and git):
        raise _Skip("needs bash and git on PATH")
    keep = []
    for exe in (bash, git):
        d = pathlib.Path(exe).parent
        if any((d / n).exists() for n in ("python", "python.exe", "python3", "python3.exe")):
            continue
        if str(d) not in keep:
            keep.append(str(d))
    if not keep:
        raise _Skip("cannot isolate a PATH without python next to bash/git")
    shimdir = pathlib.Path(tempfile.mkdtemp(prefix="mrecall-py3-"))
    root, kitdir = make_repo()
    try:
        shim = shimdir / "python3"
        shim.write_text(f'#!/bin/sh\nexec "{sys.executable}" "$@"\n', encoding="utf-8", newline="\n")
        shim.chmod(0o755)
        shutil.copyfile(KIT / "adopt-memory-recall.sh", kitdir / "adopt-memory-recall.sh")
        env = dict(os.environ, PATH=os.pathsep.join([str(shimdir), *keep]))
        # Exact LINES, not `in`: "HAVE_PYTHON3" contains "HAVE_PYTHON", so a substring test reports
        # a correctly-isolated PATH as "python is still there" and skips the arm for the wrong
        # reason — which is exactly how this arm would have shipped never running (measured).
        probe = subprocess.run(
            [bash, "-c",
             "command -v python >/dev/null && echo HAVE_PY2; command -v python3 >/dev/null && echo HAVE_PY3"],
            env=env, capture_output=True, text=True,
        ).stdout.split()
        if "HAVE_PY3" not in probe:
            raise _Skip("the python3 shim is not visible to bash on the cut-down PATH")
        if "HAVE_PY2" in probe:
            raise _Skip("could not remove `python` from PATH on this node")
        proc = subprocess.run(
            [bash, str(kitdir / "adopt-memory-recall.sh"), "--check"],
            cwd=str(root), env=env, capture_output=True, text=True,
        )
        assert proc.returncode == 0, (
            f"exit {proc.returncode} with python3 only:\n{proc.stdout}{proc.stderr}"
        )
        return "exit 0 with only python3 on PATH"
    finally:
        cleanup(root)
        cleanup(shimdir)


@check("adopt --scaffold converges byte-identically, and copies NO hook without --with-hook")
def t_scaffold_converges():
    """AC8 and the opt-in half of AC13.

    A hook file copied in but never merged into settings.json reads as UNWIRED forever, in the repo
    that runs the wiring verifier as its own SessionStart hook. So absence has to be a TRUE signal:
    no `--with-hook`, no file, nothing to report.
    """
    root, kitdir = make_repo()
    try:
        copy_extra(kitdir, *SURFACE)
        first = adopt(root, kitdir, "--scaffold")
        assert first.returncode == 0, f"{first.stdout}{first.stderr}"
        skill = root / SKILL_REL
        assert skill.is_file(), "--scaffold rendered no SKILL.md"
        b1 = skill.read_bytes()
        again = adopt(root, kitdir, "--scaffold")
        assert again.returncode == 0, f"{again.stdout}{again.stderr}"
        assert skill.read_bytes() == b1, "a second --scaffold changed the rendered skill"
        chk = adopt(root, kitdir, "--check")
        assert chk.returncode == 0, f"--check reds on a freshly rendered skill: {chk.stdout}"
        assert not (root / ".claude" / "hooks").exists(), "a hook was installed without --with-hook"
        with_hook = adopt(root, kitdir, "--scaffold", "--with-hook")
        assert with_hook.returncode == 0, f"{with_hook.stdout}{with_hook.stderr}"
        hook = root / ".claude" / "hooks" / "recall-opened.js"
        assert hook.read_bytes() == (KIT / "recall-opened.js").read_bytes(), "hook copy differs"
        assert "settings-merge.py --fragment" in with_hook.stdout, "no wiring instruction printed"
        return f"{len(b1)} B skill, idempotent; hook absent until --with-hook"
    finally:
        cleanup(root)


@check("a FAMILIES edit nobody re-rendered reds --check and shows the stale description")
def t_skill_drift_reds():
    root, kitdir = make_repo()
    try:
        copy_extra(kitdir, *SURFACE)
        assert adopt(root, kitdir, "--scaffold").returncode == 0
        (root / ".memory-tree.conf").write_text(
            'MEMORY_ROOT=memory\nFAMILIES="tooling:TOOL playbook:PLAY"\n',
            encoding="utf-8", newline="\n",
        )
        proc = adopt(root, kitdir, "--check")
        out = proc.stdout + proc.stderr
        assert proc.returncode != 0, f"--check stayed green on a stale skill:\n{out}"
        assert "DRIFTED" in out, out
        # The value the conf now carries and the rendered file does not — derived from the edit.
        assert "PLAY" in out, f"the diff does not show what drifted:\n{out}"
        assert adopt(root, kitdir, "--scaffold").returncode == 0
        assert adopt(root, kitdir, "--check").returncode == 0, "re-rendering did not clear the drift"
        return "stale -> exit 1 naming PLAY, re-render -> exit 0"
    finally:
        cleanup(root)


@check("the rendered Skill augments grep, prints only real flags, and claims no kickoff step")
def t_skill_description_invariants():
    """AC18's three invariants, all of one class: the description is the whole trigger mechanism.

    The flag set is imported from query.py rather than restated here — a second copy of that tuple
    would be an assertion whose two operands share a generator.
    """
    try:
        import query  # noqa: PLC0415 — a no-conf repo makes this a SystemExit, hence the guard
    except SystemExit as exc:
        raise _Skip(f"query.py refused to import here (exit {exc.code})") from None
    root, kitdir = make_repo()
    try:
        copy_extra(kitdir, *SURFACE)
        assert adopt(root, kitdir, "--scaffold").returncode == 0
        text = (root / SKILL_REL).read_text(encoding="utf-8")
        parts = text.split("---")
        assert len(parts) >= 3, "no YAML frontmatter in the rendered skill"
        desc = parts[1]

        # 1. AUGMENTS grep, never replaces it. Not editorial: this is what keeps the skill from
        #    intercepting ordinary code search, which Grep and Glob already do correctly.
        for token in ("Grep", "Glob", "ordinary code search", "ADDS retrieval"):
            assert token in desc, f"the description dropped {token!r}"

        # 2. Every flag printed beside an invocation is one query.py parses.
        bad = sorted({
            f
            for line in text.splitlines() if "query.py" in line
            for f in re.findall(r"--[a-z][a-z-]*", line)
            if f not in query.KNOWN_FLAGS
        })
        assert not bad, f"the skill prints flags query.py does not parse: {bad}"

        # 3. No claim about a numbered kickoff step. The kit ships to projects whose kickoff engine
        #    this file cannot read, and upstream's "that skill's Step 3 issues this query itself"
        #    was true there and false here — it suppressed the tool at the one moment it is for.
        # Split on the SENTENCE terminator only. Splitting on `;` too would cut upstream's exact
        # clause ("...is running; that skill's Step 3 issues this query itself.") in half and let
        # the numbered half through with no /session-kickoff token to catch it on — measured.
        sentences = [s for s in re.split(r"(?<=\.)\s+", desc) if "/session-kickoff" in s]
        assert sentences, "the description says nothing about /session-kickoff at all"
        numbered = [s for s in sentences if re.search(r"\bStep\b|\d", s)]
        assert not numbered, f"the description names a kickoff step it cannot verify: {numbered}"

        # 4. No BARE `python` launcher. A stock Debian/Ubuntu adopter without python-is-python3
        #    has python3 and no `python`, so such a line exits 127 — quietly, because this
        #    skill's own guidance says a miss is ordinary and to fall back to Grep. The whole
        #    trigger surface is this file, so one launcher is enough to make the kit look dead.
        bare = [ln.strip() for ln in text.splitlines()
                if re.search(r"\bpython(?!3)\s+\S*query\.py", ln)]
        assert not bare, f"the rendered skill launches query.py with a bare `python`: {bare}"
        launchers = len([ln for ln in text.splitlines() if "query.py" in ln])
        assert launchers >= 2, f"only {launchers} query.py line(s) — the scan is near-vacuous"
        return (f"{len(desc)} B description, {len(sentences)} kickoff clause(s), 0 unknown flags, "
                f"{launchers} python3 launcher(s)")
    finally:
        cleanup(root)


@check("recall-opened.test.sh: the hook records a rank on ANY corpus root")
def t_hook_test():
    bash = shutil.which("bash")
    if not bash:
        raise _Skip("no bash on PATH")
    proc = subprocess.run(
        [bash, str(KIT / "recall-opened.test.sh")], capture_output=True, text=True,
    )
    if proc.returncode == 3:
        raise _Skip(proc.stdout.strip() or "recall-opened.test.sh skipped itself")
    assert proc.returncode == 0, f"{proc.stdout}{proc.stderr}"
    tally = [ln for ln in proc.stdout.splitlines() if ln.startswith("----")]
    return (tally[-1].strip("- ") if tally else "passed")


@check("kit version constant and the gov:kit marker agree")
def t_version_marker():
    v = recall_conf.KIT_MEMORY_RECALL_VERSION
    assert re.fullmatch(r"\d+\.\d+", v), f"version {v!r} is not the house two-part X.Y"
    hits = []
    for name in ("README.md", "recall_conf.py"):
        text = (KIT / name).read_text(encoding="utf-8")
        found = re.findall(r"gov:kit memory-recall@(\d+\.\d+)", text)
        assert found, f"no gov:kit marker in {name}"
        hits += [(name, f) for f in found]
    bad = [(n, f) for n, f in hits if f != v]
    assert not bad, f"marker(s) disagree with the constant {v}: {bad}"
    return f"{len(hits)} marker(s) == {v}"


@check("bench.py and union.py are byte-identical to the upstream copies they were taken from")
def t_verbatim_files():
    """Not a diff against upstream (no adopter has that repo) — a diff against the recorded digest.

    These two carry no coupling on the query path, so they are re-pulled WHOLESALE on an upstream
    fix rather than merged. An edit here means somebody forked them without saying so.
    """
    pins = json.loads((KIT / "verbatim.json").read_text(encoding="utf-8"))
    bad = []
    for name, want in sorted(pins.items()):
        raw = (KIT / name).read_bytes().replace(b"\r\n", b"\n")
        got = hashlib.sha256(raw).hexdigest()[:16]
        if got != want:
            bad.append(f"{name}: {got} != {want}")
    assert not bad, "; ".join(bad)
    return f"{len(pins)} file(s) unmodified: {', '.join(sorted(pins))}"


@check("the whole selftest passes from the ADOPTER layout (kit at <root>/memory-recall/)")
def t_adopter_layout():
    """The layout the runbook ships, on the merge bar — because a gate green only in the repo that
    authored it is the third-shape defect this kit exists to prevent.

    WIRE §3c step 1 fixes the adopter's kit dir at `memory-recall/` and §3c step 3 makes this file a
    standing gate leg there, so every arm has to hold in that spelling; one fixture named for it was
    enough to red the adopter's merge bar on arrival. Nested exactly one level: the child sees
    MRECALL_NESTED and skips this arm, so the recursion terminates.
    """
    if os.environ.get("MRECALL_NESTED"):
        raise _Skip("nested run — the outer selftest owns this arm")
    root, kitdir = make_repo(kitname="memory-recall")
    try:
        # The WHOLE kit, not just SHIPPED: the surface arms read README.md, verbatim.json, the
        # template and the hook test from their own kit dir.
        shutil.copytree(KIT, kitdir, ignore=shutil.ignore_patterns("__pycache__"), dirs_exist_ok=True)
        (root / "tools").mkdir(exist_ok=True)
        smerge = settings_merge_src()
        if smerge is not None:
            shutil.copyfile(smerge, root / "tools" / "settings-merge.py")
        proc = subprocess.run(
            [sys.executable, str(kitdir / "selftest.py")], cwd=str(root),
            env=dict(os.environ, MRECALL_NESTED="1"), capture_output=True, text=True,
        )
        tally = [ln for ln in proc.stdout.splitlines() if ln.startswith("----")]
        bad = [ln for ln in proc.stdout.splitlines() if ln.startswith("FAIL")]
        assert proc.returncode == 0, (
            f"exit {proc.returncode} from {kitdir.name}/selftest.py:\n"
            + "\n".join(bad or proc.stdout.splitlines()[-5:]) + proc.stderr[-500:]
        )
        return (tally[-1].split(":", 1)[-1].strip() if tally else "exit 0") + " in the adopter layout"
    finally:
        cleanup(root)


# ------------------------------------------------------------------------------------ the runner


def main() -> int:
    # The live log of the repo this kit sits in, hashed before and after: a gate that writes to the
    # instrument it measures is how upstream's log came to be 96% self-inflicted refusals.
    try:
        live = git_common_dir(recall_conf.repo_root()) / "recall" / "queries.jsonl"
        before = hashlib.sha256(live.read_bytes()).hexdigest() if live.exists() else "(absent)"
    except Exception:  # noqa: BLE001 — no repo, no log to protect
        live, before = None, "(absent)"

    order = [
        t_parser_vs_bash, t_no_conf_query, t_no_conf_adopt, t_empty_alias,
        t_zero_records_is_loud, t_empty_corpus_names_memory_root,
        t_conf_digest_both_directions, t_writes_nothing_in_worktree,
        t_alias_rebuild, t_dead_alias_is_loud, t_eviction, t_printed_invocations_resolve,
        t_python3_only,
        t_scaffold_converges, t_skill_drift_reds, t_skill_description_invariants, t_hook_test,
        t_version_marker, t_verbatim_files, t_adopter_layout,
    ]
    assert len(order) == len(_checks), f"{len(order)} arms declared, {len(_checks)} ran"

    if live is not None:
        after = hashlib.sha256(live.read_bytes()).hexdigest() if live.exists() else "(absent)"
        _checks.append(
            ("ok", "the live query log is byte-identical after this run", f"{before[:12]}")
            if after == before
            else ("FAIL", "the live query log is byte-identical after this run", "the gate wrote to it")
        )

    for state, name, detail in _checks:
        print(f"{state:<5}{name}" + (f" — {detail}" if detail else ""))
    fails = sum(1 for s, _, _ in _checks if s == "FAIL")
    skips = sum(1 for s, _, _ in _checks if s == "skip")
    note = f", {skips} skipped" if skips else ""
    print(f"---- memory-recall selftest: {len(_checks) - fails - skips}/{len(_checks)} checks passed{note}")
    return 1 if fails else 0


if __name__ == "__main__":
    raise SystemExit(main())
