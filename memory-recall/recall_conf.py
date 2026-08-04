#!/usr/bin/env python3
"""The memory-recall kit's project layer: read `.memory-tree.conf`, declare nothing of its own.

gov:kit memory-recall@1.0

The kit indexes the memory tree the memory-tree kit already declares. Two of that conf's keys are
read and no third declaration is invented:

  MEMORY_ROOT   the corpus root passed to `git ls-files` and folded into extract.DURABLE
  FAMILIES      discipline:FAMILY pairs; the uppercase FAMILY tokens are the id allowlist

The conf is REQUIRED and its absence is a refusal, not a default -- matching adopt-memory-tree.sh
and adopt-codebase-map.sh, which refuse for the same reason. This kit does not OWN the conf, so it
must not create one: the refusal names the memory-tree kit and prints a two-key stub instead. There
is deliberately no --memory-root and no --families flag anywhere in the kit; a second way to declare
the same values is the hand-kept-second-copy defect the port exists to remove.

The node-tag character class is NOT a conf key. Upstream pins `[a-f]`; the memory-tree kit's own
hygiene gate admits `node [a-z]`, so the kit takes `a-z` and adds no key.

The conf PARSER below is a copy of the twenty lines in codebase-map's map_lib.load_conf, not an
import of it: kits are copied into adopters independently, and importing across kit directories
would make memory-recall un-adoptable without codebase-map. The drift is gated by asserting this
parser against BASH sourcing the same file (selftest `conf parser == bash`), never against a second
Python parser -- two operands from one generator assert nothing.
"""

from __future__ import annotations

import hashlib
import pathlib
import re
import subprocess
import sys

# The kit never leaves bytecode in the adopter's worktree — see query.py's note.
sys.dont_write_bytecode = True

KIT_MEMORY_RECALL_VERSION = "1.0"

CONF_NAME = ".memory-tree.conf"
# a-z, per tools/memory-tree/check-memory-hygiene.sh's own `node [a-z]` (spec Q1 option (b)).
NODE_TAG_CLASS = "a-z"


class ConfError(RuntimeError):
    """The project layer is missing or unusable. Always a refusal, never a default."""


def repo_root() -> pathlib.Path:
    """The adopting repo's root, anchored on THIS FILE rather than on the cwd.

    The kit directory lives inside the adopting repo (`memory-recall/` at the root in an adopter,
    `tools/memory-recall/` in this one), so the anchor is exact from any cwd, and a throwaway-repo
    test that copies the kit in resolves to that repo rather than to wherever the runner stood.
    """
    here = pathlib.Path(__file__).resolve().parent
    try:
        out = subprocess.run(
            ["git", "-C", str(here), "rev-parse", "--show-toplevel"],
            capture_output=True,
            text=True,
            check=True,
        ).stdout.strip()
    except (OSError, subprocess.CalledProcessError) as e:
        raise ConfError(f"memory-recall: {here} is not inside a git repository") from e
    return pathlib.Path(out).resolve()


def load_conf(root: pathlib.Path) -> dict[str, str]:
    """Parse the restricted shell grammar `.memory-tree.conf` documents.

    Quoted values keep everything inside the quotes; an unquoted value ends at the first
    whitespace, so a trailing ` # comment` cannot leak in and diverge from bash.
    """
    path = root / CONF_NAME
    conf: dict[str, str] = {}
    if not path.is_file():
        return conf
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip().removeprefix("export ").strip()
        value = value.strip()
        if value[:1] in {'"', "'"} and value[-1:] == value[:1] and len(value) >= 2:
            value = value[1:-1]
        else:
            value = value.split()[0] if value.split() else ""
        conf[key] = value
    return conf


def refusal(root: pathlib.Path, why: str) -> str:
    return (
        f"refused: {why}\n\n"
        "memory-recall reads the memory-tree kit's project layer and declares no config of its\n"
        "own, so it will not create one. Adopt the memory-tree kit (adopt-memory-tree.sh), or\n"
        f"paste this into {(root / CONF_NAME).as_posix()} and fill in real values:\n\n"
        "  MEMORY_ROOT=memory\n"
        '  FAMILIES="<discipline>:<FAMILY> ..."\n\n'
        "There is no --memory-root and no --families: the conf is the single source."
    )


_FAMILY_RE = re.compile(r"^[A-Z][A-Z0-9]*$")


class Conf:
    """The three RESOLVED values every other module in the kit reads."""

    __slots__ = ("root", "path", "memory_root", "families", "node_tag_class")

    def __init__(self, root: pathlib.Path, memory_root: str, families: tuple[str, ...]):
        self.root = root
        self.path = root / CONF_NAME
        self.memory_root = memory_root
        self.families = families
        self.node_tag_class = NODE_TAG_CLASS

    def digest(self) -> str:
        """A hash of the RESOLVED values, not of the conf file's bytes.

        The manifest keys freshness on this (query.ensure_cache), so an id-grammar or corpus-root
        edit invalidates a warm cache the way an alias edit already does. Hashing the file's bytes
        instead would force a full rebuild for a comment edit, for no semantic change.
        """
        blob = "\0".join((self.memory_root, ",".join(sorted(self.families)), self.node_tag_class))
        return hashlib.sha1(blob.encode("utf-8")).hexdigest()[:12]


_cached: Conf | None = None


def resolve(root: pathlib.Path | None = None) -> Conf:
    """The kit's project layer, or a ConfError carrying the printable refusal.

    Cached per process: every module in the kit calls this at import, and the resolution costs a
    `git rev-parse`.
    """
    global _cached
    if root is None and _cached is not None:
        return _cached
    base = root if root is not None else repo_root()
    path = base / CONF_NAME
    if not path.is_file():
        raise ConfError(refusal(base, f"no {CONF_NAME} at {path.as_posix()}"))
    conf = load_conf(base)
    memory_root = conf.get("MEMORY_ROOT", "").strip().strip("/")
    if not memory_root:
        raise ConfError(refusal(base, f"{CONF_NAME} declares no MEMORY_ROOT"))
    families = tuple(
        dict.fromkeys(
            fam
            for pair in conf.get("FAMILIES", "").split()
            if _FAMILY_RE.match(fam := pair.rpartition(":")[2].strip())
        )
    )
    if not families:
        raise ConfError(
            refusal(base, f"{CONF_NAME} declares no usable FAMILIES (want `discipline:FAMILY ...`)")
        )
    out = Conf(base, memory_root, families)
    if root is None:
        _cached = out
    return out


def main() -> int:
    """Print the resolved project layer as KEY=VALUE, or the refusal on stderr.

    ONE home for the refusal text: adopt-memory-recall.sh shells out to this rather than restating
    it, so the CLI and the adopt script cannot drift on what a missing conf says (AC3).

    The KEY=VALUE lines are a MACHINE-READABLE protocol (adopt-memory-recall.sh parses them with
    `read`), so the newline is part of the contract. On Windows, text-mode stdout translated every
    \\n to \\r\\n and each value reached the shell carrying a trailing CR — which rendered into
    SKILL.md as `memory\\r/` and `(PLAY KICK TOOL DEPL\\r)`, breaking its YAML frontmatter outright.
    Pin LF so the protocol is byte-identical on every OS.
    """
    try:
        sys.stdout.reconfigure(newline="\n")
    except (AttributeError, ValueError):  # a replaced or non-TextIOWrapper stdout
        pass
    try:
        c = resolve()
    except ConfError as e:
        print(e, file=sys.stderr)
        return 2
    print(f"ROOT={c.root.as_posix()}")
    print(f"MEMORY_ROOT={c.memory_root}")
    print(f"FAMILIES={' '.join(c.families)}")
    print(f"NODE_TAG_CLASS={c.node_tag_class}")
    print(f"CONF_DIGEST={c.digest()}")
    print(f"KIT_VERSION={KIT_MEMORY_RECALL_VERSION}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
