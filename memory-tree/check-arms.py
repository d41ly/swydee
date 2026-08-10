#!/usr/bin/env python3
"""check-arms.py — the harness meta-gate: every `fail` BRANCH is armed, or explicitly pinned.

    python tools/memory-tree/check-arms.py --check      # the gate
    python tools/memory-tree/check-arms.py --report     # what is armed, what is pinned, per gate
    python tools/memory-tree/check-arms.py --emit-pin   # the pin file for the CURRENT unarmed set
    python tools/memory-tree/check-arms.py --selftest

THE POPULATION IS DISCOVERED, never named. A gate is a tracked `*.sh` that DEFINES the helper
(`fail() {`) and has `fail <n> "` call sites; its test is the sibling `<stem>.test.sh`. A named pair
went stale the day a second gate landed — `manifest-check.sh` carried 16 branches behind six numbers
with no arm requirement at all — and that is the row this file drains.

WHY THE HELPER DEFINITION IS PART OF THE PREDICATE. With a call-site test alone, any `*.test.sh` that
QUOTES a fail line becomes a "gate" demanding a `<stem>.test.test.sh` that will never exist, and the
whole suite goes permanently red. `*.test.sh` is excluded outright as well: the fixture shape is one
heredoc away, and this module's own selftest already writes one.

WHY THE KEY CARRIES THE GATE. Not because one gate's arm could silence another's — it could not, the
arm scan reads each gate's own sibling test. Because the PIN's keys are global: measured, seven keys
are claimed by both of this repo's gates — (1,1) (2,1) (3,1) (4,1) (5,1) (5,2) (6,1) — so a two-field
pin row raises false stale-signature reds against the other gate, or falsely EXEMPTS it.

WHY THE CAPTURE STOPS AT THE CLOSING QUOTE. `manifest-check.sh` writes five branches inline as
`{ fail 2 "…"; BLOCK_OK=0; }`. Capturing to end of line puts `"; BLOCK_OK=0; }` into the signature —
the gate's SOURCE, which no assertion can ever emit — so those rows would be permanently unarmable
inside a shrink-only pin, and `--check` would still pass because it compares the pin against a
signature from the same extractor. Measured: terminating at the first UNESCAPED closing quote changes
0 of 14 signatures in `check-memory-hygiene.sh` and exactly the 5 contaminated ones. A message with
no closing quote on its line is a run-on; it falls back to end-of-line.

WHAT COUNTS AS AN ARM. A POSITIVE assertion naming the branch's OWN failure text. A bare `check N`
mention, an ABSENCE assertion and a COMMENT all fail to arm: each is "something in the file mentions
it", which is not "something exercises it".

FLOORS ARE PER-GATE. An aggregate total lets one gate's DELETED guard be masked by another gate's
added one, and it goes slack by a whole gate's branch count the day a third gate lands — a guard that
gets quieter as the population grows.
"""
from __future__ import annotations

import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
PIN = "project/unarmed-branches.txt"

FAIL_RE = re.compile(r'\bfail (\d+) "(.*)$')
HELPER_RE = re.compile(r"^\s*fail\(\)\s*\{")
INTERP_RE = re.compile(r'\$\{?[A-Za-z_][A-Za-z0-9_]*\}?')
# A NEGATIVE assertion. `miss` is this kit's absence helper; the `&&` form is the inline one.
NEGATIVE_RE = re.compile(r"^\s*(miss\b|.*grep -qF .* <<<.*\s&&\s)")


class Problem(Exception):
    """A named, user-facing failure. Never a traceback."""


def run(*argv, cwd=None):
    return subprocess.run(argv, cwd=cwd, capture_output=True, text=True, check=True).stdout


def read(p):
    with open(p, "rb") as fh:
        return fh.read().decode("utf-8", "replace").replace("\r\n", "\n")


def load_conf(root):
    conf = {"MEMORY_ROOT": "memory", "ARMS_FLOORS": ""}
    p = os.path.join(root, ".memory-tree.conf")
    if os.path.isfile(p):
        for line in read(p).split("\n"):
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, _, v = line.partition("=")
            conf[k.strip()] = v.strip().strip('"').strip("'")
    return conf


def message_of(tail: str) -> str:
    """The message text, ending at the first UNESCAPED closing quote.

    Everything after that quote is shell, not output. A line with no closing quote is a run-on
    message that continues on the next line; the whole tail is the best available approximation and
    the signature is taken from it.
    """
    i = 0
    while i < len(tail):
        if tail[i] == "\\":
            i += 2
            continue
        if tail[i] == '"':
            return tail[:i]
        i += 1
    return tail


def signature(message: str) -> str:
    """A literal slice of the branch's own message that a test can assert on.

    Interpolations are dropped rather than guessed at, and the longest surviving literal run is the
    signature — short runs like ':' or ' — ' appear in every message and would arm every branch.
    """
    parts = [p.strip() for p in INTERP_RE.split(message)]
    parts = [p.rstrip(':" ').strip() for p in parts]
    best = max(parts, key=len) if parts else ""
    return best


def discover(root: str) -> list:
    """Every (gate, test) pair in the tree. Derived, never listed."""
    tracked = [p for p in run("git", "ls-files", cwd=root).split("\n") if p.endswith(".sh")]
    pairs = []
    for rel in tracked:
        if rel.endswith(".test.sh"):
            continue                          # a fixture that quotes a fail line is not a gate
        try:
            text = read(os.path.join(root, rel))
        except OSError:
            continue
        if not any(HELPER_RE.match(l) for l in text.split("\n")):
            continue                          # quotes a fail line but does not own the protocol
        if not any(FAIL_RE.search(l) for l in text.split("\n")
                   if not l.lstrip().startswith("#") and "fail() {" not in l):
            continue
        pairs.append((rel, rel[:-3] + ".test.sh"))
    return sorted(pairs)


def branches(root: str, gate_rel: str) -> list:
    """Every `fail` call site in one gate, keyed on (number, ordinal-within-that-number)."""
    path = os.path.join(root, gate_rel)
    if not os.path.isfile(path):
        raise Problem(f"check-arms: {gate_rel} is missing — this meta-gate reads the gate's source, "
                      f"so a renamed or moved gate must be repointed here, not silently uncovered")
    seen = {}
    out = []
    for lineno, line in enumerate(read(path).split("\n"), 1):
        if line.lstrip().startswith("#") or "fail() {" in line:
            continue                          # a comment about a branch, and the helper's definition
        m = FAIL_RE.search(line)
        if not m:
            continue
        num = int(m.group(1))
        seen[num] = seen.get(num, 0) + 1
        sig = signature(message_of(m.group(2)))
        if len(sig) < 12:
            raise Problem(f"{gate_rel}:{lineno}: check {num} branch {seen[num]} has no literal run "
                          f"long enough to assert on ({sig!r}) — reword the message or the arm cannot "
                          f"name it")
        out.append({"gate": gate_rel, "num": num, "ord": seen[num], "line": lineno, "sig": sig})
    return out


def armed_signatures(root: str, test_rel: str) -> set:
    """Lines of the test file that could carry a POSITIVE assertion.

    A COMMENT is not an arm. The test file's prose explains what each arm covers and naturally quotes
    the messages, so a comment-blind scan would let a branch read as armed on the strength of a
    sentence describing it — the same shape as the bare-`check N` mention and the absence assertion
    this function already refuses. All three are "something mentions it", not "something exercises
    it".
    """
    path = os.path.join(root, test_rel)
    if not os.path.isfile(path):
        raise Problem(f"check-arms: {test_rel} is missing, but its gate has `fail` branches — with no "
                      f"test file EVERY branch is unarmed and there is nothing to arm them with")
    out = set()
    for line in read(path).split("\n"):
        if line.lstrip().startswith("#"):
            continue
        if NEGATIVE_RE.match(line):
            continue
        out.add(line)
    return out


def parse_pin(root: str, m: str) -> list:
    p = os.path.join(root, m, PIN)
    rows = []
    if not os.path.isfile(p):
        return rows
    for i, line in enumerate(read(p).split("\n"), 1):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) != 4:
            raise Problem(f"{m}/{PIN}:{i}: expected 4 tab-separated fields "
                          f"(gate<TAB>check<TAB>ordinal<TAB>signature), got {len(parts)}")
        rows.append((parts[0].strip(), parts[1].strip(), parts[2].strip(), parts[3].strip(), i))
    return rows


def parse_floors(conf: dict) -> dict:
    """`ARMS_FLOORS="<gate>:<branches>:<armed> …"` — per gate, both one-sided upward."""
    out = {}
    for tok in conf.get("ARMS_FLOORS", "").split():
        parts = tok.rsplit(":", 2)
        if len(parts) != 3 or not parts[1].isdigit() or not parts[2].isdigit():
            raise Problem(f"check-arms: ARMS_FLOORS entry {tok!r} is not <gate>:<branches>:<armed>")
        out[parts[0]] = (int(parts[1]), int(parts[2]))
    return out


def classify(root: str, conf: dict, pairs=None) -> dict:
    m = conf["MEMORY_ROOT"]
    pairs = discover(root) if pairs is None else pairs
    brs, errors = [], []
    for gate_rel, test_rel in pairs:
        # A gate that raises does NOT abort the walk: for the duration of that red the gate would
        # otherwise enforce nothing else — every other gate's unarmed branches, every stale pin row
        # and both floors would go unchecked, and a second regression could land under cover.
        try:
            gb = branches(root, gate_rel)
            lines = armed_signatures(root, test_rel)
        except Problem as exc:
            errors.append(str(exc))
            continue
        for b in gb:
            b["armed"] = any(b["sig"] in l for l in lines)
        brs.extend(gb)
    return {"branches": brs, "pinned": parse_pin(root, m), "errors": errors,
            "pairs": pairs, "m": m}


def do_check(root: str, conf: dict) -> int:
    st = classify(root, conf)
    brs, pinned, m = st["branches"], st["pinned"], st["m"]
    bad = list(st["errors"])
    pin_keys = {(r[0], r[1], r[2]): r for r in pinned}
    for b in brs:
        key = (b["gate"], str(b["num"]), str(b["ord"]))
        if b["armed"]:
            if key in pin_keys:
                bad.append(f"check-arms: {m}/{PIN}:{pin_keys[key][4]} pins {b['gate']} check "
                           f"{b['num']} branch {b['ord']}, which IS armed now — delete the row "
                           f"(the pin is shrink-only)")
            continue
        if key not in pin_keys:
            bad.append(f"check-arms: {b['gate']}:{b['line']} check {b['num']} branch {b['ord']} has "
                       f"no POSITIVE assertion naming its own failure text ({b['sig']!r}) and is not "
                       f"pinned in {m}/{PIN}")
        elif pin_keys[key][3] != b["sig"]:
            bad.append(f"check-arms: {m}/{PIN}:{pin_keys[key][4]} pins {b['gate']} check {b['num']} "
                       f"branch {b['ord']} with a stale signature — the message was reworded")
    live = {(b["gate"], str(b["num"]), str(b["ord"])) for b in brs}
    scanned = {g for g, _ in st["pairs"]}
    for r in pinned:
        if (r[0], r[1], r[2]) not in live:
            why = ("the gate is no longer in the population" if r[0] not in scanned
                   else "the guard was deleted or renumbered")
            bad.append(f"check-arms: {m}/{PIN}:{r[4]} pins {r[0]} check {r[1]} branch {r[2]}, which "
                       f"no longer exists — {why}")
    # PER-GATE floors. An aggregate would let one gate's deletion be masked by another's addition.
    floors = parse_floors(conf)
    # A FLOOR NAMING A GATE THAT IS NOT IN THE POPULATION IS A FAILURE, not a skip. The loop below
    # walks the DISCOVERED gates and looks each floor up by key, so a floor whose gate vanished was
    # simply never consulted: `do_check` returned 0 with no output. Measured — reformatting one gate's
    # helper from `fail() {` to `fail () {` drops it out of discovery entirely, taking 14 branches and
    # 14 arms with it, and every floor stayed green. The pin has this guard already (above); the
    # floors did not, and with the pin empty by design the floors are the only backstop left.
    for gate_rel in sorted(floors):
        if gate_rel not in scanned:
            bad.append(f"check-arms: ARMS_FLOORS names {gate_rel}, which is NOT in the discovered "
                       f"population — the gate was renamed, moved, or stopped matching the "
                       f"`fail() {{` + call-site predicate. Its branches and arms are no longer "
                       f"counted by anything; fix the gate or remove the floor in a commit that "
                       f"says why")
    for gate_rel in sorted({b["gate"] for b in brs}):
        gb = [b for b in brs if b["gate"] == gate_rel]
        want = floors.get(gate_rel)
        if not want:
            continue
        got = (len(gb), sum(1 for b in gb if b["armed"]))
        for i, label in ((0, "fail branch(es)"), (1, "armed branch(es)")):
            if got[i] < want[i]:
                bad.append(f"check-arms: {gate_rel} has {got[i]} {label} against a floor of "
                           f"{want[i]} (ARMS_FLOORS) — a guard or an assertion was removed; lower "
                           f"the floor in a commit that says why")
    for line in bad:
        print("HYGIENE " + line)
    return 1 if bad else 0


def do_report(root: str, conf: dict) -> int:
    st = classify(root, conf)
    floors = parse_floors(conf)
    for gate_rel, test_rel in st["pairs"]:
        gb = [b for b in st["branches"] if b["gate"] == gate_rel]
        want = floors.get(gate_rel, ("unset", "unset"))
        print(f"{gate_rel}  ->  {test_rel}")
        print(f"    branches {len(gb):>3} (floor {want[0]})   armed "
              f"{sum(1 for b in gb if b['armed']):>3} (floor {want[1]})")
        for b in gb:
            print(f"      check {b['num']:>2} branch {b['ord']}  line {b['line']:>4}  "
                  f"{'ARMED ' if b['armed'] else '      '} {b['sig'][:72]}")
    print(f"pinned rows   : {len(st['pinned'])}")
    for e in st["errors"]:
        print("ERROR " + e)
    return 0


def do_emit_pin(root: str, conf: dict) -> int:
    """Print the pin file for the CURRENT unarmed set — the measurement, not a guess."""
    st = classify(root, conf)
    print("# unarmed-branches.txt — `fail` branches with no positive assertion naming their own")
    print("# failure text. SHRINK-ONLY: a row leaves when its branch gains an arm, and check-arms")
    print("# reds if a pinned branch is armed, if a pinned branch or its gate disappears, or if a")
    print("# message is reworded out from under its signature.")
    print("# Fields: gate<TAB>check<TAB>ordinal<TAB>signature.")
    for b in st["branches"]:
        if not b["armed"]:
            print(f"{b['gate']}\t{b['num']}\t{b['ord']}\t{b['sig']}")
    return 0


# ----------------------------------------------------------------------------------------- selftest
def _w(path, text):
    d = os.path.dirname(path)
    if d:
        os.makedirs(d, exist_ok=True)
    with open(path, "wb") as fh:
        fh.write(text.encode("utf-8"))


def do_selftest() -> int:
    fails = []

    def arm(label, want, fn):
        import contextlib
        import io

        buf = io.StringIO()
        try:
            with contextlib.redirect_stdout(buf):
                rc = fn()
            got = buf.getvalue() + f"[rc={rc}]"
        except Problem as exc:
            got = str(exc)
        except Exception as exc:  # noqa: BLE001
            got = f"UNEXPECTED {type(exc).__name__}: {exc}"
        ok = (want in got) if want else ("[rc=0]" in got)
        print(("arm ok    " if ok else "arm FAIL  ") + label
              + ("" if ok else f" — expected {want!r}, got: {got.strip()}"))
        if not ok:
            fails.append(label)

    HELPER = 'fail() { echo "HYGIENE check $1 FAILED — $2"; status=1; }\n'
    GATE_A = HELPER + \
        '[ -n "$a" ] && fail 1 "alpha branch message here:\n"\n' \
        '[ -n "$b" ] && fail 1 "beta branch message here:\n"\n' \
        '[ -n "$c" ] && fail 2 "gamma branch message here:\n"\n'
    # The INLINE form: a message followed by more shell on the same line. Capturing to end of line
    # would put `"; BLOCK_OK=0; }` into the signature, which no assertion can ever emit.
    GATE_B = HELPER + '[ -n "$d" ] && { fail 1 "delta branch message here"; BLOCK_OK=0; }\n'

    with tempfile.TemporaryDirectory() as base:
        root = os.path.join(base, "repo")
        os.makedirs(root)
        run("git", "init", "-q", ".", cwd=root)
        run("git", "config", "user.email", "t@t.test", cwd=root)
        run("git", "config", "user.name", "t", cwd=root)
        _w(os.path.join(root, ".memory-tree.conf"),
           'MEMORY_ROOT=memory\nARMS_FLOORS="tools/gate-a.sh:3:1"\n')
        _w(os.path.join(root, "tools", "gate-a.sh"), GATE_A)
        _w(os.path.join(root, "tools", "gate-a.test.sh"), "hit 'alpha branch message here'\n")
        _w(os.path.join(root, "tools", "gate-b.sh"), GATE_B)
        _w(os.path.join(root, "tools", "gate-b.test.sh"), "hit 'delta branch message here'\n")
        # A *.test.sh that QUOTES a fail line AND defines the helper — the shape that would make the
        # whole suite permanently red by demanding a <stem>.test.test.sh.
        _w(os.path.join(root, "tools", "decoy.test.sh"), HELPER + 'fail 1 "decoy message here"\n')
        _w(os.path.join(root, "memory", "project", ".keep"), "")
        run("git", "add", "-A", cwd=root)
        run("git", "commit", "-q", "-m", "f", "--no-verify", cwd=root)
        conf = load_conf(root)
        pin = os.path.join(root, "memory", "project", "unarmed-branches.txt")

        arm("two gates are discovered, the decoy test is not",
            "[rc=0]",
            lambda: 0 if [g for g, _ in discover(root)] == ["tools/gate-a.sh", "tools/gate-b.sh"] else 1)
        arm("branches are keyed on the call site, not the check number", "[rc=0]",
            lambda: 0 if [(b["num"], b["ord"]) for b in branches(root, "tools/gate-a.sh")]
            == [(1, 1), (1, 2), (2, 1)] else 1)
        arm("the capture stops at the closing quote, not end of line", "[rc=0]",
            lambda: 0 if branches(root, "tools/gate-b.sh")[0]["sig"] == "delta branch message here" else 1)

        # the PIN key carries the gate: both gates have a (1,1)
        _w(pin, "tools/gate-a.sh\t1\t2\tbeta branch message here\n"
                "tools/gate-a.sh\t2\t1\tgamma branch message here\n")
        run("git", "add", "-A", cwd=root); run("git", "commit", "-q", "-m", "p", "--no-verify", cwd=root)
        arm("a fully pinned + armed population passes", None, lambda: do_check(root, conf))
        # gate A's (1,1) pinned must NOT exempt gate B's (1,1)
        _w(os.path.join(root, "tools", "gate-b.test.sh"), "# no arm here\n")
        _w(pin, "tools/gate-a.sh\t1\t1\talpha branch message here\n"
                "tools/gate-a.sh\t1\t2\tbeta branch message here\n"
                "tools/gate-a.sh\t2\t1\tgamma branch message here\n")
        run("git", "add", "-A", cwd=root); run("git", "commit", "-q", "-m", "p2", "--no-verify", cwd=root)
        out = []
        arm("a pin for gate A does not exempt gate B's same key",
            "tools/gate-b.sh:2 check 1 branch 1 has no POSITIVE",
            lambda: _capture(do_check, root, conf, out))
        arm("...and raises no stale-signature line against gate B", "[rc=0]",
            lambda: 0 if not any("gate-b" in l and "stale signature" in l for l in out) else 1)
        arm("...and gate A's own armed branch is reported as wrongly pinned",
            "pins tools/gate-a.sh check 1 branch 1, which IS armed now",
            lambda: _capture(do_check, root, conf, []))

        # a missing sibling test is a NAMED failure, and it does not abort the other gate
        _w(pin, "tools/gate-a.sh\t1\t2\tbeta branch message here\n"
                "tools/gate-a.sh\t2\t1\tgamma branch message here\n")
        os.remove(os.path.join(root, "tools", "gate-b.test.sh"))
        run("git", "add", "-A", cwd=root); run("git", "commit", "-q", "-m", "rm", "--no-verify", cwd=root)
        arm("a gate with no sibling test is named", "gate-b.test.sh is missing, but its gate has",
            lambda: do_check(root, conf))
        out2 = []
        _w(pin, "")
        run("git", "add", "-A", cwd=root); run("git", "commit", "-q", "-m", "e", "--no-verify", cwd=root)
        # line-agnostic on purpose: the assertion is about WHICH gate still gets scanned, not about
        # where in that gate the branch happens to sit.
        arm("one gate's error does not hide the other gate's branches",
            "tools/gate-a.sh:4 check 1 branch 2 has no POSITIVE",
            lambda: _capture(do_check, root, conf, out2))

        # restore gate B, then the per-gate floors
        _w(os.path.join(root, "tools", "gate-b.test.sh"), "hit 'delta branch message here'\n")
        _w(pin, "tools/gate-a.sh\t1\t2\tbeta branch message here\n"
                "tools/gate-a.sh\t2\t1\tgamma branch message here\n")
        run("git", "add", "-A", cwd=root); run("git", "commit", "-q", "-m", "r", "--no-verify", cwd=root)
        arm("restored population passes", None, lambda: do_check(root, conf))
        confh = dict(conf, ARMS_FLOORS="tools/gate-a.sh:4:1")
        arm("a per-gate branch floor catches a deleted guard",
            "tools/gate-a.sh has 3 fail branch(es) against a floor of 4",
            lambda: do_check(root, confh))
        confa = dict(conf, ARMS_FLOORS="tools/gate-a.sh:3:2")
        arm("a per-gate armed floor catches a dropped assertion",
            "tools/gate-a.sh has 1 armed branch(es) against a floor of 2",
            lambda: do_check(root, confa))
        # CROSS-GATE COMPENSATION: an aggregate floor would be satisfied here; a per-gate one is not.
        confc = dict(conf, ARMS_FLOORS="tools/gate-a.sh:4:1 tools/gate-b.sh:0:0")
        arm("a per-gate floor is not satisfied by another gate's growth",
            "tools/gate-a.sh has 3 fail branch(es)",
            lambda: do_check(root, confc))

        # A FLOOR whose gate is gone. The floors loop walks the DISCOVERED gates and looks each floor
        # up by key, so before this guard a floor for a vanished gate was never consulted at all:
        # rc=0, no output, and a whole gate's branches and arms silently uncounted. The escape is not
        # hypothetical — reformatting `fail() {` to `fail () {` drops a gate out of discovery.
        confz = dict(conf, ARMS_FLOORS="tools/gate-a.sh:3:1 tools/gate-gone.sh:9:9")
        arm("a floor naming a gate outside the population is a failure",
            "which is NOT in the discovered population", lambda: do_check(root, confz))
        # ...and the same floor set with the gate PRESENT is silent, so the arm above is not passing
        # because do_check reds on everything.
        arm("...and a floor whose gate IS discovered stays silent", "[rc=0]",
            lambda: do_check(root, dict(conf, ARMS_FLOORS="tools/gate-a.sh:3:1")))

        # a pin whose GATE is gone names that, not "the guard was deleted"
        _w(pin, "tools/gate-z.sh\t1\t1\tvanished gate message here\n"
                "tools/gate-a.sh\t1\t2\tbeta branch message here\n"
                "tools/gate-a.sh\t2\t1\tgamma branch message here\n")
        run("git", "add", "-A", cwd=root); run("git", "commit", "-q", "-m", "z", "--no-verify", cwd=root)
        arm("a pin for a gate outside the population says so",
            "the gate is no longer in the population", lambda: do_check(root, conf))

        # a signature present only in the PIN arms nothing
        arm("a signature present only in the PIN arms nothing", "[rc=0]",
            lambda: 0 if not [b for b in classify(root, conf)["branches"]
                              if (b["num"], b["ord"]) == (1, 2) and b["armed"]] else 1)

        # a comment and an absence assertion do not arm
        _w(os.path.join(root, "tools", "gate-a.test.sh"),
           "hit 'alpha branch message here'\n"
           "# this arm would cover: gamma branch message here\n"
           "miss 'beta branch message here'\n")
        _w(pin, "")
        run("git", "add", "-A", cwd=root); run("git", "commit", "-q", "-m", "c", "--no-verify", cwd=root)
        outc = []
        _capture(do_check, root, conf, outc)
        arm("a comment naming the message does not arm", "[rc=0]",
            lambda: 0 if any("check 2 branch 1 has no POSITIVE" in l for l in outc) else 1)
        arm("an absence assertion does not arm", "[rc=0]",
            lambda: 0 if any("check 1 branch 2 has no POSITIVE" in l for l in outc) else 1)

        # a message with no assertable literal run is a named error, not a silent skip
        _w(os.path.join(root, "tools", "gate-a.sh"), HELPER + '[ -n "$a" ] && fail 1 "$X:\n"\n')
        run("git", "add", "-A", cwd=root); run("git", "commit", "-q", "-m", "x", "--no-verify", cwd=root)
        arm("a message with no literal run is named", "no literal run long enough",
            lambda: do_check(root, conf))

    if fails:
        print(f"FAIL — {len(fails)} arm(s) failed")
        return 1
    print("PASS — check-arms: all arms held")
    return 0


def _capture(fn, root, conf, sink):
    """Run a check, echo its output (so `arm` can match), and keep the lines for a second assertion."""
    import contextlib
    import io

    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        rc = fn(root, conf)
    text = buf.getvalue()
    sink.extend(text.split("\n"))
    print(text, end="")
    return rc


def main(argv):
    mode = argv[1] if len(argv) > 1 else "--check"
    if mode == "--selftest":
        return do_selftest()
    try:
        root = run("git", "rev-parse", "--show-toplevel").strip()
    except Exception:  # noqa: BLE001
        print("check-arms: not a git repo")
        return 2
    conf = load_conf(root)
    try:
        if mode == "--check":
            return do_check(root, conf)
        if mode == "--report":
            return do_report(root, conf)
        if mode == "--emit-pin":
            return do_emit_pin(root, conf)
        print("usage: check-arms.py [--check|--report|--emit-pin|--selftest]")
        return 2
    except Problem as exc:
        print(f"HYGIENE {exc}")
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
