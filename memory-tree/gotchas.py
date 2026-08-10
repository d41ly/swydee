#!/usr/bin/env python3
"""gotchas.py — the bug-class catalogue's index and its per-diff checklist (memory-tree kit 1.5).

    python tools/memory-tree/gotchas.py --check                 # checks 17-19 + INDEX freshness
    python tools/memory-tree/gotchas.py --write                 # render INDEX.md
    python tools/memory-tree/gotchas.py --report                # the counts the budget is measured on
    python tools/memory-tree/gotchas.py --for-diff <base>..<head>   # STDOUT IS THE CHECKLIST
    python tools/memory-tree/gotchas.py --declares < record.md   # rc 0 declares, 1 does not
    python tools/memory-tree/gotchas.py --selftest

`--for-diff`'s STDOUT IS THE CHECKLIST. That is the point: a reviewer is handed the classes their
diff can actually hit instead of being pointed at a catalogue and trusted to remember which entries
apply. A checklist nobody can finish is not a checklist.

ANCHORS ARE DERIVED, NOT DECLARED. A record's anchors are the backtick-quoted path-like tokens in its
body. An authored `anchors:` list is a second copy of what the body already says, and this catalogue
has an entry for exactly that. The trade is stated rather than discovered: derivation is
recall-biased, so `--for-diff` OVER-selects, and a record naming no path at all matches nothing and
is REPORTED as unanchored rather than silently never firing.

THREE UPSTREAM HARVEST DEFECTS ARE CARRIED, each with its own arm in --selftest — TWO as behaviour
this implementation shares, ONE as a difference:
  1. SHARED   — a token containing `::` inside backticks harvests to nothing.
  2. NOT HERE — upstream required a non-empty tail after the slash, so a directory anchor written
                `tools/memory-tree/` harvested to nothing and its record was silently unanchored.
                Here the tail may be empty, the directory token IS harvested, and it selects
                everything beneath it. The arm pins the DIFFERENCE, so a future tightening of the
                pattern reintroduces the upstream defect loudly instead of quietly.
  3. SHARED   — an anchor's BASENAME matches tree-wide, however much path precedes it. Kept: it is
                what makes short-form anchors usable at all.
Documented behaviour that no test pins is indistinguishable from a bug nobody has noticed. A future
change that "fixes" one of these must fail loudly and be made deliberately.
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
BEGIN, END = "<!-- BEGIN GENERATED -->", "<!-- END GENERATED -->"
FM_RE = re.compile(r"\A---\n(.*?)\n---\n", re.S)
# A path-ish token inside backticks: at least one `/`, or a known source extension.
ANCHOR_RE = re.compile(r"`([^`\s]+(?:/[^`\s]*|\.(?:md|py|sh|js|json|ts|toml|yml|yaml|conf|txt)))`")
# A record DECLARES its resolution by naming a gate, or by saying in as many words that it has none.
# Both are acceptable; silence is not, because "no gate named" and "gate not yet written" are
# indistinguishable from outside and the second one quietly never happens.
#
# THE ONE COPY OF THIS PREDICATE. Upstream shipped it typed twice — this alternation and a hand-copied
# grep in the shell gate — and the two did not agree: the shell grepped the WHOLE file while the
# module searched only the post-front-matter body, so a `description` carrying the word "gated"
# satisfied one and not the other. Every consumer calls `declares()`; nobody re-types the alternation.
DECLARES_RE = re.compile(r"gated by|gated in|gated at|documented[ -]check|no machine gate", re.I)
KINDS = ("class", "note", "superseded")


class Problem(Exception):
    """A named, user-facing failure. Never a traceback."""


def run(*argv, cwd=None):
    return subprocess.run(argv, cwd=cwd, capture_output=True, text=True, check=True).stdout


def read(path) -> str:
    with open(path, "rb") as fh:
        return fh.read().decode("utf-8", "replace").replace("\r\n", "\n")


def write(path, text):
    d = os.path.dirname(path)
    if d:
        os.makedirs(d, exist_ok=True)
    with open(path, "wb") as fh:
        fh.write(text.encode("utf-8"))


def load_conf(root: str) -> dict:
    conf = {"MEMORY_ROOT": "memory", "UNIVERSAL_BUDGET": ""}
    p = os.path.join(root, ".memory-tree.conf")
    if os.path.isfile(p):
        for line in read(p).split("\n"):
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, _, v = line.partition("=")
            conf[k.strip()] = v.strip().strip('"').strip("'")
    return conf


def append_only_re(root: str) -> re.Pattern:
    """The append-only classification, ASKED of the script that owns it — never retyped here.

    The sibling raises ITS OWN `Problem` class, which this module's `except Problem` cannot catch —
    two classes with one name are two classes. Every failure crossing this boundary is re-raised as
    ours, so a hygiene gate never emits a traceback.
    """
    import importlib.util

    src = HERE / "corpus_ids.py"
    if not src.is_file():
        raise Problem(f"gotchas: {src} is missing — it owns the append-only classification "
                      f"checks 17-19 read")
    try:
        spec = importlib.util.spec_from_file_location("corpus_ids", src)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        return re.compile(mod.ask_shell("--print-append-only-ere", root).strip() or r"(?!)")
    except Problem:
        raise
    except Exception as exc:  # noqa: BLE001 — including the sibling's own Problem, a different class
        raise Problem(f"gotchas: could not ask corpus_ids for the append-only classification: "
                      f"{type(exc).__name__}: {exc}") from None


# ------------------------------------------------------------------------------------------ records
def parse_front_matter(path: str, text: str) -> dict:
    m = FM_RE.match(text)
    if not m:
        raise Problem(f"{path}: no front matter — a record opens with a '---' block at line 1")
    fm = {}
    for i, line in enumerate(m.group(1).split("\n"), 2):
        if not line.strip():
            continue
        if line[:1].isspace():
            # A key indented under a parent (`metadata:` / `nested:`) is SILENTLY DROPPED by every
            # simple parser, and a dropped `kind` or `universal` changes what the checklist emits.
            raise Problem(f"{path}:{i}: front-matter key is indented — keys live at COLUMN 0, and an "
                          f"indented key is dropped without a word")
        if ":" not in line:
            raise Problem(f"{path}:{i}: front-matter line is not 'key: value'")
        k, _, v = line.partition(":")
        fm[k.strip()] = v.strip()
    for key in ("name", "description"):
        if key not in fm:
            raise Problem(f"{path}: front matter is missing required key '{key}'")
    kind = fm.get("kind", "class")
    if kind not in KINDS:
        raise Problem(f"{path}: kind '{kind}' is not one of {' '.join(KINDS)}")
    fm["kind"] = kind
    fm["universal"] = fm.get("universal", "").lower() in ("true", "yes", "1")
    return fm


def declares(text: str) -> bool:
    """Does this record name a gate, or say in as many words that it has none?

    The BODY only, never the front matter — a `description` carrying the word "gated" is prose about
    the class, not a declaration about its resolution.
    """
    m = FM_RE.match(text)
    return bool(DECLARES_RE.search(text[m.end():] if m else text))


def records(root: str, m: str) -> list:
    d = os.path.join(root, m, "gotchas")
    out = []
    if not os.path.isdir(d):
        return out
    for name in sorted(os.listdir(d)):
        if not name.endswith(".md") or name == "INDEX.md":
            continue
        rel = f"{m}/gotchas/{name}"
        text = read(os.path.join(d, name))
        fm = parse_front_matter(rel, text)
        body = text[FM_RE.match(text).end():]
        out.append({
            "path": rel, "name": fm["name"], "description": fm["description"],
            "kind": fm["kind"], "universal": fm["universal"],
            "declares": declares(text),
            "anchors": sorted(set(ANCHOR_RE.findall(body))),
        })
    return out


def selectable(anchor: str, paths, m: str) -> set:
    """The paths an anchor can select. THE ONE COPY of the selection predicate.

    Substring both ways plus a BASENAME equality — the basename arm is harvest defect 3, kept
    deliberately: `check-memory-hygiene.sh` in a record selects that file wherever it lives, which is
    what makes short forms usable at all.

    The catalogue EXCLUDES ITSELF. Every record cites paths under `gotchas/` while describing its own
    class, and with basename matching a record naming `INDEX.md` would select every `INDEX.md` in the
    tree — so a diff that touches the catalogue would emit most of the catalogue. Noise on a
    checklist is how reviewers learn to skip it.
    """
    skip = f"{m}/gotchas/"
    return {p for p in paths
            if not p.startswith(skip)
            and (anchor in p or p in anchor or os.path.basename(p) == os.path.basename(anchor))}


def inert_only(rec: dict, paths, m: str, append_only: re.Pattern) -> bool:
    """True when every tracked path this record's anchors can REACH is append-only.

    Resolve THEN classify, never string-match the anchor token: an anchor is judged by what it
    selects. Upstream matched the append-only pattern against the raw token and the arm went green
    for every short-form anchor in the corpus.
    """
    hits = set()
    for a in rec["anchors"]:
        hits |= selectable(a, paths, m)
    return bool(hits) and all(append_only.match(p) for p in hits)


# ---------------------------------------------------------------------------------------- rendering
def render(recs: list, m: str) -> str:
    head = [
        f"# {m}/gotchas/ — the recurring bug-class catalogue",
        "",
        "One authored record per class. The table below is GENERATED from each record's front matter",
        "and its DERIVED anchors — do not hand-edit between the markers.",
        "",
        "Hand a reviewer the classes their diff can hit:",
        "",
        "```bash",
        "python tools/memory-tree/gotchas.py --for-diff <base>..<head>",
        "```",
        "",
        BEGIN,
        "",
        "| Class | Kind | Anchors | Universal | Description |",
        "|---|---|---:|---|---|",
    ]
    for r in recs:
        head.append(f"| [{r['name']}]({os.path.basename(r['path'])}) | {r['kind']} | "
                    f"{len(r['anchors'])} | {'yes' if r['universal'] else ''} | {_cell(r['description'])} |")
    classes = [r for r in recs if r["kind"] == "class"]
    head += [
        "",
        f"{len(recs)} record(s): {len(classes)} class, "
        f"{sum(1 for r in recs if r['kind'] == 'note')} note, "
        f"{sum(1 for r in recs if r['kind'] == 'superseded')} superseded · "
        f"{sum(1 for r in classes if r['universal'])} universal · "
        f"{sum(1 for r in classes if not r['anchors'] and not r['universal'])} unanchored",
        "",
        END,
        "",
    ]
    return "\n".join(head)


def _cell(s: str) -> str:
    """A pipe inside a cell ends the cell — GFM drops the rest of the row silently."""
    return s.replace("|", "\\|").strip()


def apply_region(existing: str, body: str, path: str) -> str:
    if BEGIN not in existing or END not in existing:
        return body
    lines = existing.split("\n")
    o = [i for i, l in enumerate(lines) if l.strip() == BEGIN]
    c = [i for i, l in enumerate(lines) if l.strip() == END]
    if len(o) != 1 or len(c) != 1 or c[0] < o[0]:
        raise Problem(f"{path}: expected exactly one marker pair, found {len(o)} open / {len(c)} close")
    return body


# ------------------------------------------------------------------------------------------- checks
def do_check(root: str, conf: dict) -> int:
    m = conf["MEMORY_ROOT"]
    recs = records(root, m)
    bad = []
    # 17 — INDEX freshness.
    idx = os.path.join(root, m, "gotchas", "INDEX.md")
    want = render(recs, m)
    if recs or os.path.exists(idx):
        if not os.path.exists(idx):
            bad.append(f"check 17: {m}/gotchas/INDEX.md is missing — run gotchas.py --write")
        elif read(idx) != want:
            bad.append(f"check 17: {m}/gotchas/INDEX.md is stale — run gotchas.py --write")
    if recs:
        paths = [p for p in run("git", "ls-files", cwd=root).split("\n") if p]
        ao = append_only_re(root)
        for r in recs:
            if r["kind"] != "class":
                continue
            # 18 — declares a gate, or says it has none.
            if not r["declares"]:
                bad.append(f"check 18: {r['path']} names no gate and does not say it has none — "
                           f"'no gate named' and 'gate not yet written' are indistinguishable from outside")
            # 19 — the INERT-ANCHOR arm.
            if not r["anchors"] and not r["universal"]:
                bad.append(f"check 19: {r['path']} derives no anchor and is not marked universal — "
                           f"it can never appear on a checklist")
            elif r["anchors"] and inert_only(r, paths, m, ao):
                bad.append(f"check 19: {r['path']} has INERT anchors — every path they reach is "
                           f"append-only, so the record is reachable on paper and dead in practice")
        budget = conf.get("UNIVERSAL_BUDGET", "")
        if budget:
            n = sum(1 for r in recs if r["kind"] == "class" and r["universal"])
            if n > int(budget):
                bad.append(f"check 19: {n} universal record(s) against a budget of {budget} — every one "
                           f"is emitted on EVERY checklist, so raise the budget in a commit that says why")
    for line in bad:
        print("HYGIENE " + line)
    return 1 if bad else 0


def do_write(root: str, conf: dict) -> int:
    m = conf["MEMORY_ROOT"]
    recs = records(root, m)
    idx = os.path.join(root, m, "gotchas", "INDEX.md")
    if not recs and not os.path.isdir(os.path.dirname(idx)):
        print("gotchas: no catalogue to render")
        return 0
    write(idx, render(recs, m))
    print(f"gotchas: wrote {m}/gotchas/INDEX.md ({len(recs)} record(s))")
    return 0


def do_report(root: str, conf: dict) -> int:
    m = conf["MEMORY_ROOT"]
    recs = records(root, m)
    classes = [r for r in recs if r["kind"] == "class"]
    print(f"records          : {len(recs)}")
    print(f"classes          : {len(classes)}")
    print(f"universal        : {sum(1 for r in classes if r['universal'])}  "
          f"(budget {conf.get('UNIVERSAL_BUDGET') or 'unset'})")
    print(f"unanchored       : {sum(1 for r in classes if not r['anchors'] and not r['universal'])}")
    for r in recs:
        print(f"    {r['kind']:<10} {len(r['anchors']):>2} anchor(s)  {r['name']}")
    return 0


def do_for_diff(root: str, conf: dict, rng: str) -> int:
    """STDOUT IS THE CHECKLIST."""
    m = conf["MEMORY_ROOT"]
    recs = records(root, m)
    changed = [p for p in run("git", "diff", "--name-only", rng, cwd=root).split("\n") if p]
    if not changed:
        print(f"gotchas: {rng} touches no file — nothing to check")
        return 0
    hit, uni = [], []
    for r in recs:
        if r["kind"] != "class":
            continue
        if r["universal"]:
            uni.append(r)
            continue
        for a in r["anchors"]:
            if selectable(a, changed, m):
                hit.append(r)
                break
    print(f"# recurring-bug-class checklist for {rng} ({len(changed)} changed file(s))")
    print(f"# {len(hit)} class(es) selected by an anchor + {len(uni)} universal")
    for r in uni + hit:
        print(f"\n- [ ] {r['name']}{' (universal)' if r['universal'] else ''}\n      {r['description']}\n      {r['path']}")
    return 0


# ----------------------------------------------------------------------------------------- selftest
def _rec(name, desc, body, kind=None, universal=None, indent=False):
    fm = [f"name: {name}", f"description: {desc}"]
    if kind:
        fm.append(f"kind: {kind}")
    if universal is not None:
        fm.append(f"universal: {'true' if universal else 'false'}")
    if indent:
        fm.append("  nested: dropped-without-a-word")
    return "---\n" + "\n".join(fm) + "\n---\n\n" + body


def _scratch(tmp: str, recs: dict, extra=None):
    run("git", "init", "-q", ".", cwd=tmp)
    run("git", "config", "user.email", "t@t.test", cwd=tmp)
    run("git", "config", "user.name", "t", cwd=tmp)
    write(os.path.join(tmp, ".memory-tree.conf"),
          'MEMORY_ROOT=memory\nDISCIPLINES="arch"\nFAMILIES="arch:ARCH"\nUNIVERSAL_BUDGET="1"\n')
    write(os.path.join(tmp, "memory", "HYGIENE.md"), "sentinel\n")
    write(os.path.join(tmp, "memory", "README.md"), "# r\n")
    # A POPULATED append-only area: check 19's inert arm can only fire when an anchor is able to
    # reach one, so on a tree with an empty append-only area the rule ships green forever.
    write(os.path.join(tmp, "memory", "DECISIONS.md"), "# d\n\n- ARCH-tOne-1 · a decision\n")
    write(os.path.join(tmp, "memory", "archive", "OLD.2026-01-01.md"), "frozen\n")
    write(os.path.join(tmp, "tools", "some-gate.sh"), "#!/usr/bin/env bash\n")
    write(os.path.join(tmp, "deep", "nested", "some-gate.sh"), "#!/usr/bin/env bash\n")
    for name, text in recs.items():
        write(os.path.join(tmp, "memory", "gotchas", name), text)
    for rel, text in (extra or {}).items():
        write(os.path.join(tmp, rel), text)
    run("git", "add", "-A", cwd=tmp)
    run("git", "commit", "-q", "-m", "f", "--no-verify", cwd=tmp)
    return load_conf(tmp)


def do_selftest() -> int:
    import io
    import contextlib

    fails = []

    def arm(label, want, fn):
        buf = io.StringIO()
        try:
            with contextlib.redirect_stdout(buf):
                rc = fn()
            got = buf.getvalue() + f"[rc={rc}]"
        except Problem as exc:
            got = str(exc)
        except Exception as exc:  # noqa: BLE001 — a traceback here IS the finding
            got = f"UNEXPECTED {type(exc).__name__}: {exc}"
        ok = (want in got) if want else ("[rc=0]" in got)
        print(("arm ok    " if ok else "arm FAIL  ") + label + ("" if ok else f" — expected {want!r}, got: {got.strip()}"))
        if not ok:
            fails.append(label)

    GOOD = _rec("good-class", "a real class", "Fires on `tools/some-gate.sh`. Gated by the hygiene gate.\n")
    with tempfile.TemporaryDirectory() as base:
        t = os.path.join(base, "clean"); os.makedirs(t)
        c = _scratch(t, {"good-class.md": GOOD})
        do_write(t, c)
        run("git", "add", "-A", cwd=t); run("git", "commit", "-q", "-m", "idx", "--no-verify", cwd=t)
        arm("a rendered catalogue is clean", None, lambda: do_check(t, c))

        # 17 — freshness.
        write(os.path.join(t, "memory", "gotchas", "INDEX.md"), "hand-edited\n")
        arm("check 17 catches a stale INDEX", "INDEX.md is stale", lambda: do_check(t, c))

        # 18 — declares.
        t2 = os.path.join(base, "nogate"); os.makedirs(t2)
        c2 = _scratch(t2, {"x.md": _rec("x", "d", "Fires on `tools/some-gate.sh`. Nothing said about a gate.\n")})
        do_write(t2, c2); run("git", "add", "-A", cwd=t2); run("git", "commit", "-q", "-m", "i", "--no-verify", cwd=t2)
        arm("check 18 catches a record that names no gate", "names no gate and does not say it has none",
            lambda: do_check(t2, c2))
        arm("--declares is the one predicate: 'no machine gate' declares", "[rc=0]",
            lambda: 0 if declares(_rec("x", "d", "There is no machine gate for this.\n")) else 1)
        arm("--declares reads the BODY, not the front matter", "[rc=0]",
            lambda: 0 if not declares(_rec("x", "gated by nothing", "plain body\n")) else 1)

        # 19 — inert anchors, and the unanchored case.
        t3 = os.path.join(base, "inert"); os.makedirs(t3)
        c3 = _scratch(t3, {"i.md": _rec("i", "d", "Only ever touches `memory/archive/OLD.2026-01-01.md`. Gated by nothing.\n")})
        do_write(t3, c3); run("git", "add", "-A", cwd=t3); run("git", "commit", "-q", "-m", "i", "--no-verify", cwd=t3)
        arm("check 19 catches INERT anchors", "has INERT anchors", lambda: do_check(t3, c3))
        t4 = os.path.join(base, "unanch"); os.makedirs(t4)
        c4 = _scratch(t4, {"u.md": _rec("u", "d", "Applies everywhere. No machine gate.\n")})
        do_write(t4, c4); run("git", "add", "-A", cwd=t4); run("git", "commit", "-q", "-m", "i", "--no-verify", cwd=t4)
        arm("check 19 catches an unanchored non-universal record", "derives no anchor",
            lambda: do_check(t4, c4))
        t5 = os.path.join(base, "uni"); os.makedirs(t5)
        c5 = _scratch(t5, {"u.md": _rec("u", "d", "Applies everywhere. No machine gate.\n", universal=True)})
        do_write(t5, c5); run("git", "add", "-A", cwd=t5); run("git", "commit", "-q", "-m", "i", "--no-verify", cwd=t5)
        arm("a universal record needs no anchor", None, lambda: do_check(t5, c5))

        # the universal BUDGET.
        t6 = os.path.join(base, "budget"); os.makedirs(t6)
        c6 = _scratch(t6, {
            "u1.md": _rec("u1", "d", "Everywhere. No machine gate.\n", universal=True),
            "u2.md": _rec("u2", "d", "Everywhere too. No machine gate.\n", universal=True)})
        do_write(t6, c6); run("git", "add", "-A", cwd=t6); run("git", "commit", "-q", "-m", "i", "--no-verify", cwd=t6)
        arm("the universal budget is enforced", "against a budget of 1", lambda: do_check(t6, c6))

        # front matter: an indented key is NAMED, not dropped.
        t7 = os.path.join(base, "indent"); os.makedirs(t7)
        c7 = _scratch(t7, {"n.md": _rec("n", "d", "Body cites `tools/some-gate.sh`. No machine gate.\n", indent=True)})
        arm("an indented front-matter key is named", "keys live at COLUMN 0", lambda: do_check(t7, c7))

        # ---- the THREE CARRIED HARVEST DEFECTS. Each is asserted as OBSERVED behaviour so that a
        # ---- future "fix" fails loudly and has to be made deliberately.
        d1 = ANCHOR_RE.findall("a `Class::method` reference\n")
        arm("harvest defect 1: `::` inside backticks harvests to nothing", "[rc=0]",
            lambda: 0 if d1 == [] else 1)
        # Defect 2 is the one this implementation does NOT share, and the arm says so rather than
        # asserting upstream's behaviour out of deference. Upstream's token pattern required a
        # non-empty tail after the slash, so `tools/memory-tree/` harvested to nothing and a record
        # written that way was silently unanchored. Here the tail may be empty, the directory token
        # IS harvested, and it selects everything beneath it. The arm pins the DIFFERENCE, so a
        # future tightening of the pattern reintroduces the upstream defect loudly.
        d2 = ANCHOR_RE.findall("a directory `tools/memory-tree/` reference\n")
        arm("harvest defect 2 does NOT apply here: a trailing slash harvests the directory", "[rc=0]",
            lambda: 0 if d2 == ["tools/memory-tree/"] else 1)
        arm("...and that directory anchor selects everything beneath it", "[rc=0]",
            lambda: 0 if selectable("tools/memory-tree/", ["tools/memory-tree/gotchas.py"], "memory")
            == {"tools/memory-tree/gotchas.py"} else 1)
        paths = ["tools/some-gate.sh", "deep/nested/some-gate.sh", "memory/README.md"]
        sel = selectable("some-gate.sh", paths, "memory")
        arm("harvest defect 3: a basename selects tree-wide", "[rc=0]",
            lambda: 0 if sel == {"tools/some-gate.sh", "deep/nested/some-gate.sh"} else 1)
        arm("the catalogue never selects itself", "[rc=0]",
            lambda: 0 if selectable("INDEX.md", ["memory/gotchas/INDEX.md"], "memory") == set() else 1)

        # A failure crossing the corpus_ids boundary is NAMED, not a traceback. The sibling raises
        # its OWN Problem class, which this module's `except Problem` cannot catch — two classes
        # with one name are two classes, and the first run of this arm printed a WinError stack out
        # of a hygiene gate.
        t9 = os.path.join(base, "boundary"); os.makedirs(t9)
        c9 = _scratch(t9, {"g.md": GOOD})
        do_write(t9, c9); run("git", "add", "-A", cwd=t9); run("git", "commit", "-q", "-m", "i", "--no-verify", cwd=t9)
        old_bash = os.environ.get("GOV_BASH")
        os.environ["GOV_BASH"] = os.path.join(base, "no-such-bash")
        try:
            arm("a failure crossing the corpus_ids boundary is named, not a traceback",
                "could not ask corpus_ids", lambda: do_check(t9, c9))
        finally:
            if old_bash is None:
                del os.environ["GOV_BASH"]
            else:
                os.environ["GOV_BASH"] = old_bash

        # --for-diff: anchors that intersect, plus universal, and nothing else.
        t8 = os.path.join(base, "diff"); os.makedirs(t8)
        c8 = _scratch(t8, {
            "hit.md": _rec("hit", "d", "Fires on `tools/some-gate.sh`. Gated by the hygiene gate.\n"),
            "miss.md": _rec("miss", "d", "Fires on `memory/README.md`. Gated by the hygiene gate.\n"),
            "uni.md": _rec("uni", "d", "Everywhere. No machine gate.\n", universal=True),
            "note.md": _rec("note", "d", "A policy, not a class. Touches `tools/some-gate.sh`. No machine gate.\n", kind="note")})
        do_write(t8, c8); run("git", "add", "-A", cwd=t8); run("git", "commit", "-q", "-m", "i", "--no-verify", cwd=t8)
        write(os.path.join(t8, "tools", "some-gate.sh"), "#!/usr/bin/env bash\n# edited\n")
        run("git", "add", "-A", cwd=t8); run("git", "commit", "-q", "-m", "edit", "--no-verify", cwd=t8)
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            do_for_diff(t8, c8, "HEAD~1..HEAD")
        text = out.getvalue()
        arm("--for-diff emits the anchored hit", "[rc=0]", lambda: 0 if "- [ ] hit" in text else 1)
        arm("--for-diff emits every universal record", "[rc=0]", lambda: 0 if "- [ ] uni (universal)" in text else 1)
        arm("--for-diff omits a record whose anchors miss", "[rc=0]", lambda: 0 if "- [ ] miss" not in text else 1)
        arm("--for-diff omits a non-class record", "[rc=0]", lambda: 0 if "- [ ] note" not in text else 1)

    if fails:
        print(f"FAIL — {len(fails)} arm(s) failed")
        return 1
    print("PASS — gotchas: all arms held")
    return 0


def main(argv: list) -> int:
    mode = argv[1] if len(argv) > 1 else "--check"
    if mode == "--selftest":
        return do_selftest()
    if mode == "--declares":
        return 0 if declares(sys.stdin.read()) else 1
    try:
        root = run("git", "rev-parse", "--show-toplevel").strip()
    except Exception:  # noqa: BLE001
        print("gotchas: not a git repo")
        return 2
    conf = load_conf(root)
    try:
        if mode == "--check":
            return do_check(root, conf)
        if mode == "--write":
            return do_write(root, conf)
        if mode == "--report":
            return do_report(root, conf)
        if mode == "--for-diff":
            if len(argv) < 3:
                print("usage: gotchas.py --for-diff <base>..<head>")
                return 2
            return do_for_diff(root, conf, argv[2])
        print("usage: gotchas.py [--check|--write|--report|--for-diff <range>|--declares|--selftest]")
        return 2
    except Problem as exc:
        print(f"HYGIENE {exc}")
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
