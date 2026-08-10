#!/usr/bin/env python3
"""corpus_ids.py — the corpus's id and path classifier: one grammar, one walk, every consumer.

    python tools/memory-tree/corpus_ids.py --report              # the derived numbers
    python tools/memory-tree/corpus_ids.py --check               # checks 13-16 as a gate
    python tools/memory-tree/corpus_ids.py --measure             # print the pins to set in the conf
    python tools/memory-tree/corpus_ids.py --selftest            # fixtures

Every number a gate here quotes is DERIVED from one walk rather than written into a document. A
classifier that lives in prose is a classifier nobody can check.

NOTHING HERE DECLARES A GRAMMAR OR A SET IT DOES NOT OWN.
  * the id grammar and the four anchor shapes come from the memory-recall kit's `extract.py`, which
    already derives them from `.memory-tree.conf`. A second grammar is the catalogue-drift class:
    upstream re-typed one alternation with its branches reordered and would never have noticed.
  * the append-only areas and the byte-capped index set come from `check-memory-hygiene.sh`, which
    already owns both — asked for through its print modes, never transcribed. Upstream transcribed
    the index set and had to guard the transcription in BOTH directions, because a shell-side
    addition the Python side still excludes leaves a file under no cap at all.

THE CROSS-KIT DEPENDENCY IS DECLARED, and its two states are kept apart: with every pin blank the
grammar module is never imported and checks 13-16 are simply off, while a pin SET with the module
absent is a NAMED error — you armed a check whose grammar is not installed. Never a traceback, and
never the silent pass a bare `try: import` would produce.

  13  id-definition collision   one id claimed by two different build folders
  14  orphan ids                cited but never defined; waiver + shrink-only pin + stale guard
  15  dead repo-path citations  registry + four rules, keyed on (file, path), NEVER on a line number
  16  read-path accounting      the charter's own read set: total under a ceiling, every member watched
"""
from __future__ import annotations

import os
import pathlib
import re
import subprocess
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
HYGIENE = HERE / "check-memory-hygiene.sh"
# The grammar lives in the sibling kit. Resolved relative to the TOOL ROOT, so an adopter who installs
# the kits somewhere other than `tools/` still finds it.
GRAMMAR_DIR = HERE.parent / "memory-recall"

REGISTRY = "project/corpus-path-unresolved.txt"
WAIVER = "project/id-orphan-waiver.txt"

# What counts as a repo PATH: rooted at a real top-level directory. That is the only class where
# "does it exist" is a well-posed question. A loose "backticked token with a slash" measures package
# specifiers, git refs and bare fragments as dead citations — upstream counted 13 085 of them.
BACKTICKED = re.compile(r"`([^`\s]+)`")
MD_LINK_TARGET = re.compile(r"\]\(([^)\s]+)\)")
ELISION = ("...", "…", "<", ">", "*", "{{")


class Problem(Exception):
    """A named, user-facing failure. Never a traceback."""


def run(*argv: str, cwd=None) -> str:
    return subprocess.run(argv, cwd=cwd, capture_output=True, text=True, check=True).stdout


def read(path) -> str:
    with open(path, "rb") as fh:
        return fh.read().decode("utf-8", "replace").replace("\r\n", "\n")


def load_conf(root: str) -> dict:
    conf = {
        "MEMORY_ROOT": "memory", "DISCIPLINES": "", "FAMILIES": "", "CHARTER": "AGENTS.md",
        "DEAD_PATH_PIN": "", "ORPHAN_ID_PIN": "", "READ_PATH_CEILING": "", "READ_PATH_WAIVER": "",
        "DEAD_PATH_EXCLUDE": ".claude/worktrees/",
    }
    p = os.path.join(root, ".memory-tree.conf")
    if os.path.isfile(p):
        for line in read(p).split("\n"):
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, _, v = line.partition("=")
            conf[k.strip()] = v.strip().strip('"').strip("'")
    return conf


def armed(conf: dict) -> bool:
    """Any pin set arms the unit. Blank everywhere = off, and the grammar is never imported."""
    return any(conf[k] for k in ("DEAD_PATH_PIN", "ORPHAN_ID_PIN", "READ_PATH_CEILING"))


def grammar(root: str):
    """The sibling kit's id + anchor grammar, BOUND TO THIS ROOT — or a named error naming the kit.

    `extract.repo_root()` anchors on the kit's own file, so the module-level constants describe the
    repo the kit is installed in and no chdir can move them. That is right for its CLI and wrong for
    a caller classifying a different tree: the alternation would come from the wrong repo and every
    id in the target would fail to match — silently, since a grammar that recognises nothing yields
    an empty classification and an empty classification is what a CLEAN corpus yields. Measured: the
    first selftest run here reported a clean scratch corpus while using this repo's family list.
    `grammar_for(root)` is the accessor added to the grammar module for exactly this, so there is
    still only ONE grammar.
    """
    if not (GRAMMAR_DIR / "extract.py").is_file():
        raise Problem(
            "corpus_ids: a pin is set in .memory-tree.conf, but the id grammar lives in the "
            "memory-recall kit and %s/extract.py is not installed. Either adopt that kit or blank "
            "DEAD_PATH_PIN / ORPHAN_ID_PIN / READ_PATH_CEILING to turn checks 13-16 off." % GRAMMAR_DIR
        )
    if str(GRAMMAR_DIR) not in sys.path:
        sys.path.insert(0, str(GRAMMAR_DIR))
    import extract  # noqa: E402  (deliberately late: see the module docstring)

    if not hasattr(extract, "grammar_for"):
        raise Problem("corpus_ids: the installed memory-recall kit predates grammar_for(root); "
                      "update it, or blank the pins to turn checks 13-16 off")
    return extract.grammar_for(root)


def resolve_bash() -> str:
    """The bash that shares THIS filesystem — not whatever the name `bash` resolves to.

    MEASURED on a Windows node: subprocess resolving the bare name `bash` goes through the Windows
    loader, which finds the System32 WSL launcher or the WindowsApps alias before git-bash. WSL then
    sees a DIFFERENT filesystem: the failure reads "/bin/bash: C:/a/b: No such file or directory"
    for a file that plainly exists, and a relative path resolves under /mnt/c/ instead. This is the
    documented trap — Python subprocess resolving a different bash on a Windows node — and the
    remedy is to name the EXECUTABLE rather than the command. GOV_BASH overrides.

    A candidate is accepted only if it RUNS. Existing on disk is not evidence — that is the same
    mistake one interpreter over that the python side made with the Microsoft Store `python3` stub,
    which answers `command -v` and exits 9009 without executing anything (see
    tools/lib/resolve-python.sh). An override that is SET and unusable is a named failure here too,
    never a silent fall-through to something else.
    """
    def runs(cand: str) -> bool:
        try:
            return subprocess.run([cand, "-c", ":"], capture_output=True).returncode == 0
        except OSError:
            return False

    override = os.environ.get("GOV_BASH")
    if override:
        if runs(override):
            return override
        raise Problem("corpus_ids: GOV_BASH is set to '%s' and does not run. An override that is set "
                      "and unusable is this failure, not a fall-through — you would believe you had "
                      "chosen." % override)
    skipped = []
    for d in os.environ.get("PATH", "").split(os.pathsep):
        for name in ("bash.exe", "bash"):
            cand = os.path.join(d, name)
            if not os.path.isfile(cand):
                continue
            low = cand.replace("\\", "/").lower()
            if "/system32/" in low or "/windowsapps/" in low:
                skipped.append(cand)          # a launcher for a different filesystem
                continue
            if not runs(cand):
                skipped.append(cand)          # on disk, cannot execute
                continue
            return cand
    raise Problem("corpus_ids: no usable bash on PATH — set GOV_BASH to one that shares this "
                  "filesystem" + (" (skipped %s)" % ", ".join(skipped) if skipped else ""))


def ask_shell(flag: str, root: str) -> str:
    """Ask check-memory-hygiene.sh for a set IT owns. One direction only — the print modes return
    before check 1, so there is no recursion back into this module."""
    if not HYGIENE.is_file():
        raise Problem("corpus_ids: %s is missing — it owns the sets this module asks for" % HYGIENE)
    sh = resolve_bash()
    try:
        out = subprocess.run([sh, HYGIENE.as_posix(), flag], cwd=root, capture_output=True, text=True)
    except OSError as exc:
        # A bash that cannot be LAUNCHED raises before any return code exists. Left unhandled this is
        # a traceback out of a hygiene gate — every failure here is named, including this one.
        raise Problem(f"corpus_ids: cannot run '{sh}' ({exc.strerror or exc}); set GOV_BASH to a bash "
                      f"that shares this filesystem") from None
    if out.returncode != 0:
        raise Problem("corpus_ids: `%s %s` failed: %s"
                      % (HYGIENE.name, flag, out.stderr.strip() or out.stdout.strip()))
    return out.stdout


# ------------------------------------------------------------------------------------ the one walk
def walk(root: str, conf: dict) -> dict:
    E = grammar(root)
    m = conf["MEMORY_ROOT"]
    tracked = [p for p in run("git", "ls-files", cwd=root).split("\n") if p]
    tracked_set = set(tracked)
    corpus = [p for p in tracked if p.startswith(m + "/")]
    build_re = re.compile(r"^" + re.escape(m) + r"/builds/([^/]+)/")
    h1_re = re.compile(r"^#\s+[`*]*(" + E.ID + r")\b")

    append_only = re.compile(ask_shell("--print-append-only-ere", root).strip() or r"(?!)")
    excluded = tuple(x for x in conf.get("DEAD_PATH_EXCLUDE", "").split() if x)
    present = re.compile(
        r"^" + re.escape(m) + r"/(?:DECISIONS\.md|README\.md|HYGIENE\.md|TEMPLATE-SPEC\.md"
        r"|LIVE\.md|backlog/|ledger/|project/|guides/)"
    )

    defs: dict = {}          # id -> set(paths)
    def_builds: dict = {}    # id -> set(build slugs)
    cites: dict = {}         # id -> set(paths)
    dead: dict = {}          # (citing file, cited path) -> [count, first line]

    for p in corpus:
        text = read(os.path.join(root, p))
        b = build_re.match(p)
        for lineno, line in enumerate(text.split("\n"), 1):
            anchor = _anchor(E, line)
            if anchor is None:
                h = h1_re.match(line)
                anchor = h.group(1) if h else None
            if anchor:
                defs.setdefault(anchor, set()).add(p)
                if b:
                    def_builds.setdefault(anchor, set()).add(b.group(1))
            for mm in E.ID_RE.finditer(line):
                cites.setdefault(mm.group(0), set()).add(p)
            # A citation is a claim about NOW only in the present-tense corpus. `builds/` is a record
            # of a moment — a spec proposing to write a file is a plan, not a broken pointer — and an
            # append-only area cannot legally be repaired anyway.
            if not present.match(p) or append_only.match(p):
                continue
            for tok in list(BACKTICKED.findall(line)) + list(MD_LINK_TARGET.findall(line)):
                cited = tok.rstrip("/")
                if any(e in cited for e in ELISION) or "/" not in cited:
                    continue
                if cited.split("/", 1)[0] + "/" not in _roots(tracked_set):
                    continue
                # NOT repo CONTENT. A checkout location is not a claim about what this repo holds,
                # and no resolution rule can express that: resolution here never touches the
                # filesystem — it is membership in `git ls-files` plus a prefix scan over the same
                # index — so such a path classifies as dead identically on every node. The question
                # is about meaning, not existence, so the answer is DECLARED in the conf.
                if any(cited.startswith(x) for x in excluded):
                    continue
                if cited in tracked_set or any(t.startswith(cited + "/") for t in tracked_set):
                    continue
                # NO SHAPE TEST. Every rooted, non-elided, unresolved token is a finding, file-shaped
                # or not: a citation naming a DIRECTORY is exactly as broken as one naming a file when
                # neither resolves — the flatten left four in the live ledger and the pre-V8 harvest
                # could not see one. What stood here was
                #     is_file_shaped = <B or something>;  is_dir_shaped = <not B or something>
                #     if not is_file_shaped and not is_dir_shaped: continue
                # with B = `"." in basename`, i.e. ¬(B ∨ ¬B) — identically False, filtering nothing.
                # Measured: 0 of 1550 exhaustively-generated token shapes reached the `continue`.
                # Deleted rather than kept as documentation, because executable dead code is plumbing
                # a later edit will trust; the reachability arm in the selftest is what stops it
                # coming back.
                key = (p, cited)
                if key in dead:
                    dead[key][0] += 1
                else:
                    dead[key] = [1, lineno]

    return {
        "tracked": tracked_set, "corpus": corpus, "defs": defs, "def_builds": def_builds,
        "cites": cites, "dead": dead, "root": root, "conf": conf, "m": m,
    }


def _anchor(E, line):
    """The grammar bundle carries its own anchor patterns; `anchor_at` takes it as `g`."""
    import extract

    return extract.anchor_at(line, E)


def _roots(tracked_set) -> set:
    """Real top-level directories, derived — never a hardcoded list that an adopter has to edit."""
    return {p.split("/", 1)[0] + "/" for p in tracked_set if "/" in p}


# ------------------------------------------------------------------------------------- the read set
def read_set(w: dict) -> tuple:
    """Files the charter points a session at, DERIVED from the charter's own text through three
    independent token arms. Never enumerated: upstream hand-listed it five times and every revision
    missed something."""
    root, conf, tracked = w["root"], w["conf"], w["tracked"]
    charter = conf["CHARTER"]
    if charter not in tracked:
        raise Problem(f"corpus_ids: CHARTER '{charter}' is not a tracked file — check 16 has no source")
    text = read(os.path.join(root, charter))
    # READ_PATH_PREFIX: only charter citations INSIDE the memory root count. The charter also names
    # every gate script it runs, and those are code, not a read path — folding them in would make the
    # population 32 files of which 30 need waiving, and a rule whose whole population is waived is a
    # rule with no signal. The byte caps this check cross-references govern the memory tree, so the
    # memory tree is the population.
    prefix = conf["MEMORY_ROOT"].rstrip("/") + "/"
    bare = re.compile(r"(?<![`(\w./-])(" + re.escape(prefix) + r"[^\s`)\]]+)")
    members, absent = set(), set()
    for arm in (BACKTICKED, MD_LINK_TARGET, bare):
        for tok in arm.findall(text):
            cand = tok.rstrip("/").rstrip(".,;:")
            if not cand.startswith(prefix):
                continue
            if cand in tracked:
                if os.path.isfile(os.path.join(root, cand)):
                    members.add(cand)
                else:
                    absent.add(cand)          # tracked but missing: check 12's finding, not ours
    return sorted(members), sorted(absent)


# ----------------------------------------------------------------------------------------- registry
def parse_registry(root: str, m: str) -> list:
    """Rows are `<citing-file>\\t<cited-path>\\t<count>\\t<absent|moved:DEST>`."""
    p = os.path.join(root, m, REGISTRY)
    rows = []
    if not os.path.isfile(p):
        return rows
    for i, line in enumerate(read(p).split("\n"), 1):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) != 4:
            raise Problem(f"{m}/{REGISTRY}:{i}: expected 4 tab-separated fields, got {len(parts)}")
        rows.append((parts[0], parts[1], parts[2], parts[3], i))
    return rows


def parse_waiver(root: str, m: str) -> list:
    p = os.path.join(root, m, WAIVER)
    if not os.path.isfile(p):
        return []
    return [l.strip() for l in read(p).split("\n") if l.strip() and not l.lstrip().startswith("#")]


# ------------------------------------------------------------------------------------------- checks
def checks(w: dict) -> list:
    conf, m, root, tracked = w["conf"], w["m"], w["root"], w["tracked"]
    bad = []

    # 13 — one id claimed by two different BUILD FOLDERS. Deliberately NOT "defined twice": a
    # decision-log row and its spec's H1 both anchor the same id by design (the index points at the
    # record), and treating that as a collision would red 10 of this corpus's ids on day one.
    for i, slugs in sorted(w["def_builds"].items()):
        if len(slugs) > 1:
            bad.append(f"check 13: id {i} is claimed by {len(slugs)} build folders: {', '.join(sorted(slugs))}")

    # 14 — orphan ids, with a waiver, a shrink-only pin, and a stale-entry guard.
    if conf["ORPHAN_ID_PIN"]:
        waived = parse_waiver(root, m)
        orphans = sorted(set(w["cites"]) - set(w["defs"]))
        for i in orphans:
            if i not in waived:
                bad.append(f"check 14: id {i} is cited but never defined, and is not in {m}/{WAIVER}")
        for i in waived:
            if i not in orphans:
                bad.append(f"check 14: {m}/{WAIVER} waives {i}, which now resolves — stale row")
        pin = int(conf["ORPHAN_ID_PIN"])
        if len(waived) > pin:
            bad.append(f"check 14: the orphan waiver holds {len(waived)} rows, pinned at {pin} (shrink-only)")

    # 15 — dead repo-path citations. FOUR rules. The key is (citing file, cited path) with a COUNT,
    # never a line number: a line number moves whenever anything above the citation is edited, so a
    # line-keyed registry reds on edits that have nothing to do with it, and a gate whose steady
    # state is red gets bypassed.
    if conf["DEAD_PATH_PIN"]:
        rows = parse_registry(root, m)
        measured = {k: v for k, v in w["dead"].items()}
        seen = {}
        for f, cited, count, state, ln in rows:
            key = (f, cited)
            if key in seen:                                                    # rule 3
                bad.append(f"check 15 rule 3: {m}/{REGISTRY}:{ln}: duplicate row for {f} -> {cited} (first at line {seen[key]})")
                continue
            seen[key] = ln
            if key not in measured:                                            # rule 1, stale side
                bad.append(f"check 15 rule 1: {m}/{REGISTRY}:{ln}: {f} -> {cited} no longer resolves to nothing — the citation was repaired; delete the row")
            elif str(measured[key][0]) != count:
                bad.append(f"check 15 rule 1: {m}/{REGISTRY}:{ln}: {f} -> {cited} occurs {measured[key][0]} time(s), row says {count}")
            if state.startswith("moved:"):                                     # rule 4
                dest = state.split(":", 1)[1]
                if dest not in tracked:
                    bad.append(f"check 15 rule 4: {m}/{REGISTRY}:{ln}: destination {dest} is not a tracked file")
                elif os.path.isdir(os.path.join(root, dest)):
                    bad.append(f"check 15 rule 4: {m}/{REGISTRY}:{ln}: destination {dest} is a directory, not a file")
            elif state != "absent":
                bad.append(f"check 15: {m}/{REGISTRY}:{ln}: state '{state}' is neither 'absent' nor 'moved:<dest>'")
        for key, (count, ln) in sorted(measured.items()):                      # rule 1, new side
            if key not in seen:
                bad.append(f"check 15 rule 1: {key[0]}:{ln} cites {key[1]}, which resolves to nothing and has no row in {m}/{REGISTRY}")
        pin = int(conf["DEAD_PATH_PIN"])
        if len(rows) > pin:                                                    # rule 2
            bad.append(f"check 15 rule 2: the dead-path registry holds {len(rows)} rows, pinned at {pin} (shrink-only)")

    # 16 — read-path accounting.
    if conf["READ_PATH_CEILING"]:
        members, absent = read_set(w)
        capped = {l for l in ask_shell("--print-index-set", root).split("\n") if l.strip()}
        waived = set(conf["READ_PATH_WAIVER"].split())
        total = sum(os.path.getsize(os.path.join(root, p)) for p in members)
        ceiling = int(conf["READ_PATH_CEILING"])
        if total > ceiling:
            bad.append(f"check 16: the charter's read path is {total} B, ceiling {ceiling} B "
                       f"({len(members)} files) — trim it or raise the ceiling in a commit that says why")
        for p in members:
            if p not in capped and p not in waived:
                bad.append(f"check 16 rule 3: {conf['CHARTER']} points a session at {p}, which is under "
                           f"no byte cap and not in READ_PATH_WAIVER — nothing watches it")
        for p in absent:
            bad.append(f"check 16: NOTE {p} is tracked but absent from the worktree; check 12 owns that finding")
    return bad


# ------------------------------------------------------------------------------------------- report
def do_report(root: str, conf: dict) -> int:
    w = walk(root, conf)
    orphans = sorted(set(w["cites"]) - set(w["defs"]))
    coll = {i: s for i, s in w["def_builds"].items() if len(s) > 1}
    print(f"ids defined      : {len(w['defs'])}")
    print(f"ids cited        : {len(w['cites'])}")
    print(f"orphan ids       : {len(orphans)}  {orphans}")
    print(f"build collisions : {len(coll)}  {coll}")
    print(f"dead path cites  : {len(w['dead'])}")
    for k, v in sorted(w["dead"].items()):
        print(f"    {k[0]}:{v[1]} -> {k[1]} (x{v[0]})")
    try:
        members, absent = read_set(w)
        total = sum(os.path.getsize(os.path.join(root, p)) for p in members)
        print(f"read path        : {len(members)} files, {total} B (tracked-but-absent: {len(absent)})")
        for p in members:
            print(f"    {os.path.getsize(os.path.join(root, p)):>7} B  {p}")
    except Problem as exc:
        print(f"read path        : {exc}")
    return 0


def do_measure(root: str, conf: dict) -> int:
    """Print the pins to WRITE INTO .memory-tree.conf. Measured against THIS corpus — a pin copied
    from a larger tree is either vacuous or permanently red."""
    w = walk(root, conf)
    orphans = sorted(set(w["cites"]) - set(w["defs"]))
    members, _ = read_set(w)
    total = sum(os.path.getsize(os.path.join(root, p)) for p in members)
    headroom = 20480
    print(f'ORPHAN_ID_PIN="{len(orphans)}"')
    print(f'DEAD_PATH_PIN="{len(w["dead"])}"')
    print(f'READ_PATH_CEILING="{total + headroom}"   # measured {total} B + {headroom} B headroom')
    return 0


# ----------------------------------------------------------------------------------------- selftest
def _scratch(tmp: str, *, pins=True, extra=None):
    run("git", "init", "-q", ".", cwd=tmp)
    run("git", "config", "user.email", "t@t.test", cwd=tmp)
    run("git", "config", "user.name", "t", cwd=tmp)
    conf = ['MEMORY_ROOT=memory', 'DISCIPLINES="arch"', 'FAMILIES="arch:ARCH"', 'CHARTER="AGENTS.md"']
    if pins:
        conf += ['ORPHAN_ID_PIN="0"', 'DEAD_PATH_PIN="0"', 'READ_PATH_CEILING="100000"']
    _w(tmp, ".memory-tree.conf", "\n".join(conf) + "\n")
    _w(tmp, "AGENTS.md", "# charter\n\nRead `memory/README.md` before touching code.\n")
    # A tracked `.claude/` path, so `.claude/` is a REAL top-level directory in the fixture. Without
    # it `_roots()` yields only {memory/} and a `.claude/worktrees/x` citation is never a candidate —
    # the exclusion arms below would pass while exercising nothing.
    _w(tmp, ".claude/settings.json", "{}\n")
    _w(tmp, "memory/README.md", "# r\n")
    _w(tmp, "memory/HYGIENE.md", "sentinel\n")
    _w(tmp, "memory/DECISIONS.md", "# d\n\n- ARCH-tOne-1 · a decision\n")
    _w(tmp, "memory/builds/tOne/README.md",
       "---\nslug: tOne\nnode: a\nopened: 2026-08-01\nstreams: arch\nroster: ARCH\nids: ARCH-tOne-1\nstatus: OPEN\n---\n\n# tOne\n")
    _w(tmp, "memory/builds/tOne/spec/2026-08-01-spec-tOne-1.md", "# ARCH-tOne-1 — a unit\n\nbody\n")
    for rel, body in (extra or {}).items():
        _w(tmp, rel, body)
    run("git", "add", "-A", cwd=tmp)
    run("git", "commit", "-q", "-m", "f", "--no-verify", cwd=tmp)
    return load_conf(tmp)


def _w(root, rel, text):
    p = os.path.join(root, rel)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "wb") as fh:
        fh.write(text.encode("utf-8"))


def _walk_continues() -> set:
    """Every `continue` statement inside walk(), by line, DERIVED from its own source.

    A written-down line list would rot at the first edit and then vouch for the wrong lines. The AST
    is asked instead, so adding a branch to walk() automatically adds an obligation to reach it.
    """
    import ast
    import inspect

    src, first = inspect.getsourcelines(walk)
    tree = ast.parse("".join(src).lstrip() if src[0][:1].isspace() else "".join(src))
    off = first - 1
    return {n.lineno + off for n in ast.walk(tree) if isinstance(n, ast.Continue)}


def do_selftest() -> int:
    fails = []
    # EVERY `continue` IN walk() MUST BE REACHED BY A FIXTURE. This is the one arm that could catch
    # the tautological shape filter deleted in TOOL-aBatchedTribunal-4: that branch was
    # `not (B or not B)`, identically False, so no INPUT/OUTPUT arm could ever discriminate — a
    # behavioural fixture is green against the dead code and against its removal alike. A branch no
    # fixture reaches is a branch no arm covers, and the next person to edit around it will trust it.
    _hit = set()
    _walk_file = walk.__code__.co_filename

    def _tracer(frame, event, _arg):
        if frame.f_code is walk.__code__:
            return _liner
        return None

    def _liner(frame, event, _arg):
        if event == "line" and frame.f_code.co_filename == _walk_file:
            _hit.add(frame.f_lineno)
        return _liner

    def arm(label, want, fn):
        try:
            got = fn()
        except Problem as exc:
            got = str(exc)
        except Exception as exc:  # noqa: BLE001 — a traceback here IS the finding
            got = f"UNEXPECTED {type(exc).__name__}: {exc}"
        ok = (want in str(got)) if want else (str(got) in ("[]", ""))
        print(("arm ok    " if ok else "arm FAIL  ") + label + ("" if ok else f" — expected {want!r}, got: {got}"))
        if not ok:
            fails.append(label)

    sys.settrace(_tracer)
    with tempfile.TemporaryDirectory() as base:
        t = os.path.join(base, "clean"); os.makedirs(t)
        c = _scratch(t)
        arm("a clean corpus produces no finding", None, lambda: checks(walk(t, c)))

        # 13 — two build folders claiming one id.
        t2 = os.path.join(base, "coll"); os.makedirs(t2)
        c2 = _scratch(t2, extra={
            "memory/builds/tTwo/README.md":
                "---\nslug: tTwo\nnode: a\nopened: 2026-08-01\nstreams: arch\nroster: ARCH\nids: ARCH-tOne-1\nstatus: OPEN\n---\n\n# tTwo\n",
            "memory/builds/tTwo/spec/2026-08-01-spec-tTwo-1.md": "# ARCH-tOne-1 — the same id\n\nbody\n"})
        arm("check 13 catches one id in two build folders", "claimed by 2 build folders",
            lambda: "\n".join(checks(walk(t2, c2))))

        # 14 — orphan, waiver, stale waiver, pin.
        t3 = os.path.join(base, "orph"); os.makedirs(t3)
        # PROSE, not a list row: `- <id> ·` IS an anchor, so a backlog row DEFINES its id rather than
        # orphaning it. The first cut of this fixture used a backlog row, produced no orphan at all,
        # and the arm would have passed by finding nothing on a rule it never exercised.
        c3 = _scratch(t3, extra={"memory/README.md": "# r\n\nContext lives in ARCH-tGhost-9 upstream.\n"})
        arm("check 14 catches a cited-never-defined id", "ARCH-tGhost-9 is cited but never defined",
            lambda: "\n".join(checks(walk(t3, c3))))
        _w(t3, "memory/project/id-orphan-waiver.txt", "# waived\nARCH-tGhost-9\n")
        run("git", "add", "-A", cwd=t3); run("git", "commit", "-q", "-m", "w", "--no-verify", cwd=t3)
        c3b = dict(c3); c3b["ORPHAN_ID_PIN"] = "1"
        arm("a waived orphan passes", None, lambda: checks(walk(t3, c3b)))
        c3c = dict(c3b); c3c["ORPHAN_ID_PIN"] = "0"
        arm("the waiver pin is shrink-only", "pinned at 0 (shrink-only)",
            lambda: "\n".join(checks(walk(t3, c3c))))
        t4 = os.path.join(base, "stale"); os.makedirs(t4)
        c4 = _scratch(t4, extra={"memory/project/id-orphan-waiver.txt": "ARCH-tOne-1\n"})
        c4["ORPHAN_ID_PIN"] = "1"
        arm("a waiver row that now resolves is stale", "which now resolves — stale row",
            lambda: "\n".join(checks(walk(t4, c4))))

        # 15 — the four rules.
        DEAD = "# r\n\nSee `memory/gone/never-existed.md` for detail.\n"
        t5 = os.path.join(base, "dead"); os.makedirs(t5)
        c5 = _scratch(t5, extra={"memory/README.md": DEAD})
        arm("check 15 rule 1 catches an unregistered dead citation", "has no row in",
            lambda: "\n".join(checks(walk(t5, c5))))
        reg = "memory/README.md\tmemory/gone/never-existed.md\t1\tabsent\n"
        _w(t5, "memory/project/corpus-path-unresolved.txt", reg)
        run("git", "add", "-A", cwd=t5); run("git", "commit", "-q", "-m", "r", "--no-verify", cwd=t5)
        c5b = dict(c5); c5b["DEAD_PATH_PIN"] = "1"
        arm("a registered dead citation passes", None, lambda: checks(walk(t5, c5b)))
        c5c = dict(c5b); c5c["DEAD_PATH_PIN"] = "0"
        arm("check 15 rule 2 is shrink-only", "pinned at 0 (shrink-only)",
            lambda: "\n".join(checks(walk(t5, c5c))))
        _w(t5, "memory/project/corpus-path-unresolved.txt", reg + reg)
        run("git", "add", "-A", cwd=t5); run("git", "commit", "-q", "-m", "r2", "--no-verify", cwd=t5)
        c5d = dict(c5b); c5d["DEAD_PATH_PIN"] = "2"
        arm("check 15 rule 3 catches a duplicate row", "duplicate row for",
            lambda: "\n".join(checks(walk(t5, c5d))))
        _w(t5, "memory/project/corpus-path-unresolved.txt",
           "memory/README.md\tmemory/gone/never-existed.md\t1\tmoved:memory/builds\n")
        run("git", "add", "-A", cwd=t5); run("git", "commit", "-q", "-m", "r3", "--no-verify", cwd=t5)
        arm("check 15 rule 4 rejects a directory destination", "is not a tracked file",
            lambda: "\n".join(checks(walk(t5, c5b))))
        # rule 1's OTHER direction: the source is repaired, the row survives.
        t6 = os.path.join(base, "repaired"); os.makedirs(t6)
        c6 = _scratch(t6, extra={
            "memory/project/corpus-path-unresolved.txt": "memory/README.md\tmemory/gone/x.md\t1\tabsent\n"})
        c6["DEAD_PATH_PIN"] = "1"
        arm("check 15 rule 1 catches a row whose citation was repaired", "the citation was repaired",
            lambda: "\n".join(checks(walk(t6, c6))))

        # 15, DIRECTORY citations. The flatten moved every build folder and left four dead directory
        # citations in the live ledger, and the harvest could not see one of them because it required
        # a file extension. The RED and GREEN arms run over the SAME fixture, because the green half
        # alone passes on the un-widened code too: an unharvested token is silent for the wrong
        # reason.
        tD = os.path.join(base, "dirs"); os.makedirs(tD)
        cD = _scratch(tD, extra={
            # The four EXCLUSION branches of the harvest, each with a token that takes it. The
            # reachability arm at the end of this file is what demanded them: before it, three of
            # walk()'s `continue`s had never been executed by any fixture, so a change to the
            # append-only skip, the elision list or the top-level-root test could not have redded
            # anything. A branch no fixture reaches is a branch no arm covers.
            #   * `memory/DECISIONS.md` is APPEND-ONLY: a dead citation there is a historical
            #     record, not a repair, so the harvest must skip the file entirely.
            #   * `memory/builds/tOne/spec/…` is not in the PRESENT-tense corpus regex — same skip,
            #     the other half of the same `if`.
            #   * an ELIDED token (`<slug>`) and a slashless one (`README.md`) are not repo paths.
            #   * `nosuchroot/x.md` is rooted at no real top-level directory, so "does it exist" is
            #     not a well-posed question about this repo.
            "memory/DECISIONS.md": "# d\n\n- a decision citing `memory/gone/appendonly/`\n",
            "memory/builds/tOne/spec/2026-08-01-spec-tOne-9.md":
                "x\n\nnot present-tense: `memory/gone/notpresent/`\n",
            "memory/README.md": (
                "# r\n\nSee `memory/builds/tOne/` and `memory/gone/never/`.\n"
                "Elided: `memory/builds/<slug>/spec/`. Slashless: `README.md`.\n"
                "Unrooted: `nosuchroot/x.md`.\n"),
        })
        cD["DEAD_PATH_PIN"] = "0"
        arm("check 15 catches a dead DIRECTORY citation", "memory/gone/never",
            lambda: "\n".join(checks(walk(tD, cD))))
        arm("...and is silent about a directory that resolves", "[nope]" if False else "",
            lambda: "" if not [l for l in checks(walk(tD, cD)) if "memory/builds/tOne" in l] else "FOUND")

        # the DECLARED exclusion. A checkout location is not repo CONTENT, and resolution here never
        # touches the filesystem, so it would otherwise classify as dead identically on every node.
        tX = os.path.join(base, "excl"); os.makedirs(tX)
        cX = _scratch(tX, extra={
            "memory/README.md": "# r\n\nThe worktree lives at `.claude/worktrees/whatever/`.\n"})
        cX["DEAD_PATH_PIN"] = "0"
        arm("an excluded prefix is not classified", None, lambda: checks(walk(tX, cX)))
        cX2 = dict(cX); cX2["DEAD_PATH_EXCLUDE"] = ""
        arm("...and removing the prefix from the conf makes it classified again",
            ".claude/worktrees/whatever",
            lambda: "\n".join(checks(walk(tX, cX2))))

        # 16 — the charter's read path.
        t7 = os.path.join(base, "readpath"); os.makedirs(t7)
        c7 = _scratch(t7, extra={
            "AGENTS.md": "# charter\n\nRead `memory/builds/tOne/spec/2026-08-01-spec-tOne-1.md` first.\n"})
        arm("check 16 rule 3 catches an unwatched charter citation", "which is under\nno byte cap",
            lambda: "\n".join(checks(walk(t7, c7))).replace("under ", "under\n"))
        c7b = dict(c7); c7b["READ_PATH_CEILING"] = "1"
        arm("check 16 catches a read path over its ceiling", "ceiling 1 B",
            lambda: "\n".join(checks(walk(t7, c7b))))
        c7c = dict(c7); c7c["CHARTER"] = "NOPE.md"
        arm("a missing charter is a named error", "is not a tracked file",
            lambda: "\n".join(checks(walk(t7, c7c))))

        # the off switch, and the armed-without-grammar error.
        t8 = os.path.join(base, "off"); os.makedirs(t8)
        c8 = _scratch(t8, pins=False)
        arm("blank pins turn every check off", None, lambda: str(armed(c8)).replace("False", ""))

        # resolve_bash accepts a candidate only if it RUNS. A launcher that exists on disk and cannot
        # execute is the same defect one interpreter over as the Microsoft Store `python3` stub, and
        # an override that is SET and unusable has to be a named failure rather than a fall-through
        # to whatever is next on PATH — otherwise the operator believes they chose, and did not.
        tB = os.path.join(base, "bashprobe"); os.makedirs(tB)
        dead = os.path.join(tB, "not-a-bash")
        with open(dead, "w", encoding="utf-8") as fh:
            fh.write("this file exists and is not an executable\n")

        def _with_gov_bash(value):
            old = os.environ.get("GOV_BASH")
            os.environ["GOV_BASH"] = value
            try:
                return resolve_bash()
            finally:
                if old is None:
                    os.environ.pop("GOV_BASH", None)
                else:
                    os.environ["GOV_BASH"] = old

        arm("an unusable GOV_BASH is a NAMED failure, not a fall-through",
            "is set to", lambda: _with_gov_bash(dead))
        # ...and the green half over the SAME mechanism: a real bash still comes back untouched, so
        # the arm above is not passing because resolve_bash rejects everything.
        arm("a working GOV_BASH is returned unchanged", "OK",
            lambda: "OK" if _with_gov_bash(resolve_bash()) else "")

    sys.settrace(None)
    want = _walk_continues()
    missed = sorted(want - _hit)
    arm("every `continue` in walk() is reached by a fixture", None,
        lambda: "" if not missed else
        "; ".join(f"corpus_ids.py:{n} is a `continue` no fixture reaches" for n in missed))
    # ...and the checker's own red half. The first cut re-typed the message over `want | {-1}` and so
    # held by construction — it asserted a formatting expression, not the checker. This runs the SAME
    # expression the arm above runs, against a population with one line the fixtures provably never
    # executed (line 0 does not exist), so a tracer that recorded nothing and a tracer that recorded
    # everything give different answers.
    def _missed(pop):
        return "; ".join(f"corpus_ids.py:{n} is a `continue` no fixture reaches"
                         for n in sorted(pop - _hit))
    arm("...and the reachability checker can name an unreached branch",
        "corpus_ids.py:0 is a `continue` no fixture reaches", lambda: _missed(want | {0}))
    arm("...and it is silent when every member was reached", None, lambda: _missed(want))
    arm("...and the population is derived, not listed", "True", lambda: str(len(want) >= 4))

    if fails:
        print(f"FAIL — {len(fails)} arm(s) failed")
        return 1
    print("PASS — corpus_ids: all arms held")
    return 0


def main(argv: list) -> int:
    mode = argv[1] if len(argv) > 1 else "--check"
    if mode == "--selftest":
        return do_selftest()
    try:
        root = run("git", "rev-parse", "--show-toplevel").strip()
    except Exception:  # noqa: BLE001
        print("corpus_ids: not a git repo")
        return 2
    conf = load_conf(root)
    try:
        if mode == "--report":
            return do_report(root, conf)
        if mode == "--measure":
            return do_measure(root, conf)
        if mode != "--check":
            print("usage: corpus_ids.py [--check|--report|--measure|--selftest]")
            return 2
        if not armed(conf):
            return 0                       # every pin blank: checks 13-16 are off, grammar unloaded
        bad = checks(walk(root, conf))
        for line in bad:
            print("HYGIENE " + line)
        return 1 if bad else 0
    except Problem as exc:
        print(f"HYGIENE {exc}")
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
