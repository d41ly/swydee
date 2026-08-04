#!/usr/bin/env python3
"""PowerShell source-hygiene scans — two classes that make a script misbehave SILENTLY.

Project-agnostic. Run over any repo: `python tools/gate-lint/ps-hygiene.py [root]`.
Exit 0 clean, 1 on findings, 2 on usage error. `--selftest` proves both scans can FAIL.

CLASS 1 — case-only identifier collisions. PowerShell variable names are case-INSENSITIVE, so
`$LEGS` and `$legs` are ONE variable. Upstream this bit the same file three times: `$LEGS =
@($legs.legs)` overwrote a parsed manifest with its own sub-array, and a `foreach ($sel in ...)`
clobbered a `$SEL` selection map — which also disabled the backstop that read `$SEL`, because a
guard sharing a variable with the thing it guards is not a guard.

CLASS 1 IS SCOPE-AWARE. PowerShell functions get their own scope: a parameter, and any name a
function body ASSIGNS, is function-local and cannot alias a script-level name. Comparing the two
in one flat namespace reported `function Recon($fa,$rid)` against a script-level `$FA` as a
collision — a name that PowerShell never merges, so the "finding" was unactionable and the only
remedy was to rename correct code. Collisions are therefore computed PER SCOPE: script level with
every function unit lifted out, then each function unit (its parameter list plus its body)
separately, recursively for nested functions. A name that a function only READS still resolves to
the script-level variable, but reading is not the clobber this class is about — the shape that bit
upstream was always an ASSIGNMENT, and an assignment inside a function is local by construction.
Brace matching runs on comment-stripped source; on unbalanced braces the scan falls back to
treating the remainder as one scope, preserving the pre-scope behaviour rather than losing text.

CLASS 2 — a BOM-less script containing non-ASCII. PowerShell 5.1 decodes it as CP1252, so an em
dash (E2 80 94) inside a double-quoted string becomes three chars ending in 0x94 = U+201D, which
PowerShell accepts as a STRING DELIMITER. It closes the string early and desynchronises the parser.
Every text-mode read hides this, so the check is byte-level.

Scans EVERY .ps1 in the tree, not one file: gating a single instance while claiming the class is
itself the could-not-fail shape these scans exist to catch.
"""
from __future__ import annotations

import collections
import pathlib
import re
import sys

SKIP_DIRS = {".git", "node_modules", ".venv", "dist", ".next", "__pycache__"}
_COMMENT = re.compile(r"^\s*#")
_BLOCK = re.compile(r"<#.*?#>", re.S)
_IDENT = re.compile(r"\$([A-Za-z_][A-Za-z0-9_]*)")
# `function Name` / `filter Name` — the scope-opening keywords. Hyphens are legal in PS verb-noun
# names (`Get-Thing`), and the lookbehind keeps `New-Function` from matching as a definition.
_FUNC_KW = re.compile(r"(?i)(?<![\w-])(?:function|filter)[ \t]+[A-Za-z_][\w-]*")


def _code(text: str) -> str:
    """Source with comments stripped — a collision in prose is not a collision.

    Strips block comments, whole-line comments AND trailing inline comments. The first cut kept
    trailing comments, so `$Foo = 1  # see $foo` reported a collision that does not exist. Naive on
    a `#` inside a string literal, which over-strips rather than over-reports — the safe direction
    for a gate: a missed collision surfaces on the next run, a false one blocks an innocent commit.
    """
    out = []
    for line in _BLOCK.sub("", text).splitlines():
        if _COMMENT.match(line):
            continue
        out.append(line.split("#", 1)[0] if "#" in line else line)
    return chr(10).join(out)


def _close_brace(code: str, open_at: int) -> int:
    """Index of the `}` matching the `{` at open_at, or -1 if the source is unbalanced."""
    depth = 0
    for i in range(open_at, len(code)):
        if code[i] == "{":
            depth += 1
        elif code[i] == "}":
            depth -= 1
            if depth == 0:
                return i
    return -1


def _scopes(code: str) -> list[str]:
    """Split comment-stripped source into [script level, *function scopes], recursively.

    Each function contributes ONE scope holding its parameter list and its body, and is removed
    from its parent's text — that is what stops a function parameter from being compared against a
    script-level name PowerShell would never merge with it. Unbalanced or unterminated definitions
    fall back to leaving the remaining text in the enclosing scope (over-group, never drop).
    """
    own: list[str] = []
    nested: list[str] = []
    i = 0
    while True:
        match = _FUNC_KW.search(code, i)
        if not match:
            own.append(code[i:])
            break
        body_open = code.find("{", match.end())
        if body_open < 0:
            own.append(code[i:])
            break
        body_close = _close_brace(code, body_open)
        if body_close < 0:
            own.append(code[i:])
            break
        own.append(code[i:match.start()])
        # The function's own scope: the parenthesised parameter list (if any) + the body. Dropping
        # the `function <Name>` keyword itself is what makes the recursion terminate.
        nested.extend(_scopes(code[match.end():body_open] + chr(10) + code[body_open + 1:body_close]))
        i = body_close + 1
    return ["".join(own)] + nested


def case_collisions(text: str) -> dict[str, list[str]]:
    collisions: dict[str, list[str]] = {}
    for scope in _scopes(_code(text)):
        seen: dict[str, set[str]] = collections.defaultdict(set)
        for ident in _IDENT.findall(scope):
            seen[ident.lower()].add(ident)
        for key, names in seen.items():
            if len(names) > 1:
                collisions.setdefault(key, sorted(names))
    return collisions


def missing_bom(raw: bytes) -> bool:
    return any(b > 127 for b in raw) and not raw.startswith(b"\xef\xbb\xbf")


def scan(root: pathlib.Path) -> list[str]:
    findings: list[str] = []
    for path in sorted(root.rglob("*.ps1")):
        if any(part in SKIP_DIRS for part in path.parts):
            continue
        raw = path.read_bytes()
        rel = path.relative_to(root).as_posix()
        if missing_bom(raw):
            findings.append(f"{rel}: non-ASCII with no UTF-8 BOM — PS 5.1 will read it as CP1252")
        for _, names in sorted(case_collisions(raw.decode("utf-8-sig", "replace")).items()):
            findings.append(f"{rel}: identifiers differ only by case, PowerShell sees ONE: {names}")
    return findings


def _selftest() -> int:
    """Stage the break, confirm RED. A gate whose failing case has never been observed is not a gate."""
    ok = True
    bad_case = '$Foo = 1\n$foo = 2\n'
    if not case_collisions(bad_case):
        print("SELFTEST FAIL: collision scan missed $Foo/$foo"); ok = False
    if case_collisions('$Foo = 1\n$Bar = 2\n'):
        print("SELFTEST FAIL: collision scan fired on clean source"); ok = False
    if case_collisions('# $Foo and $foo in a comment\n$Bar = 1\n'):
        print("SELFTEST FAIL: collision scan fired on comment prose"); ok = False
    # --- scope model: both directions, or the split is not a gate -------------------------------
    if case_collisions('$FA = 1\nfunction Recon($fa, $rid) { $fa.x }\n'):
        print("SELFTEST FAIL: collision scan fired on a function PARAM shadowing a script name"); ok = False
    if not case_collisions('function F($foo) { $Foo = 2 }\n'):
        print("SELFTEST FAIL: collision scan missed a collision INSIDE one function scope"); ok = False
    if not case_collisions('$Bar = 1\nfunction F($x) { $x }\n$bar = 2\n'):
        print("SELFTEST FAIL: lifting a function out lost script-level text"); ok = False
    if not case_collisions('function Outer($a) { function Inner($b) { $B = 1 } }\n'):
        print("SELFTEST FAIL: collision scan missed a collision in a NESTED function"); ok = False
    if case_collisions('function Outer($q) { function Inner($r) { $r } }\n'):
        print("SELFTEST FAIL: collision scan fired across two sibling nested scopes"); ok = False
    # Unbalanced braces must degrade to the flat pre-scope behaviour, never drop text.
    if not case_collisions('$Zed = 1\nfunction Broken($x) { if ($x) {\n$zed = 2\n'):
        print("SELFTEST FAIL: unbalanced braces dropped text instead of falling back"); ok = False
    if not missing_bom("Write-Host 'em dash —'".encode("utf-8")):
        print("SELFTEST FAIL: BOM scan missed a BOM-less non-ASCII file"); ok = False
    if missing_bom(b"\xef\xbb\xbf" + "Write-Host '—'".encode("utf-8")):
        print("SELFTEST FAIL: BOM scan fired on a file that has a BOM"); ok = False
    if missing_bom(b"Write-Host 'plain ascii'"):
        print("SELFTEST FAIL: BOM scan fired on pure ASCII"); ok = False
    print("selftest: both scans observed failing and passing" if ok else "selftest: RED")
    return 0 if ok else 1


def main(argv: list[str]) -> int:
    if "--selftest" in argv:
        return _selftest()
    root = pathlib.Path(argv[1] if len(argv) > 1 else ".").resolve()
    if not root.is_dir():
        print(f"ps-hygiene: not a directory: {root}", file=sys.stderr)
        return 2
    findings = scan(root)
    scanned = sum(1 for p in root.rglob("*.ps1") if not any(x in SKIP_DIRS for x in p.parts))
    if not findings:
        print(f"ps-hygiene: OK — {scanned} .ps1 file(s) clean under {root}")
        return 0
    print(f"ps-hygiene: {len(findings)} finding(s) across {scanned} .ps1 file(s) under {root}")
    for f in findings:
        print(f"  {f}")
    return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
