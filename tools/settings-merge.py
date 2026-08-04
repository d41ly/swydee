#!/usr/bin/env python3
"""settings-merge.py — idempotently wire a hook into a target repo's .claude/settings.json.
Stdlib only (json, argparse, pathlib); py>=3.10 (write_text newline=).

# gov:kit settings-merge@1.0

The default hook, with no --fragment (shape mirrors WIRE-INTO-PROJECT.md and
tools/hooks/agent-cap.js verbatim):

    {"hooks": {"PreToolUse": [
      {"matcher": "Workflow",
       "hooks": [{"type": "command",
                  "command": "node \\"${CLAUDE_PROJECT_DIR}/.claude/hooks/agent-cap.js\\""}]}]}}

Idempotent by structure: a re-run finds the existing matcher group already carrying the fragment's
marker in a command and makes NO change (apply-twice-changed = 0). Existing keys and any other
groups under that event are preserved; a foreign command inside the matcher group is kept alongside.

A wired target is DETECTED by grepping the fragment's `marker` in .claude/settings.json — JSON
carries no comment marker, so that command substring IS the deployer's "is-it-wired?" signal, and
it is what tools/check-wiring.sh joins each arm on.

Usage:
    python tools/settings-merge.py [SETTINGS_FILE] [--fragment F] [--hook-path P] [--check]
    python tools/settings-merge.py --selftest
      SETTINGS_FILE  default .claude/settings.json (resolved from cwd = target repo root)
      --fragment     a JSON file declaring {name, event, matcher, marker, hook_path}; omitted =
                     the built-in agent-cap PreToolUse/Workflow fragment, byte-for-byte as before
      --hook-path    override the fragment's hook_path (the copied hook, repo-relative)
      --check        report drift without writing: exit 1 if a merge WOULD change the file
      --selftest     run the in-file assert suite in a tempdir; exit 0 on pass
Exit: 0 wired (already present OR merged this run) · 1 --check found drift · 2 error.

# ponytail: the fragment carries only what the three former hardcodes needed — event, matcher,
# marker, hook_path (+ a name for the messages). Everything else about the entry (type: command,
# the ${CLAUDE_PROJECT_DIR} spelling) stays fixed, because no consumer has asked to vary it. Dedup
# is a substring test on the marker and deliberately does NOT rewrite a stale hook path (a Phase-3
# upgrade concern, not Phase-0 wiring).
"""
from __future__ import annotations

import argparse
import json
import sys
import tempfile
from pathlib import Path

KIT_SETTINGS_MERGE_VERSION = "1.0"  # gov:kit settings-merge@1.0 — engine identity
HOOK_MARKER = "agent-cap.js"  # the loose join: dedup key AND the deployer's "is-it-wired?" grep target

# The built-in fragment. Identical to the three values this script hardcoded before --fragment
# existed, so a no-argument run is unchanged in behaviour AND in what it prints.
AGENT_CAP = {
    "name": "agent-cap",
    "event": "PreToolUse",
    "matcher": "Workflow",
    "marker": HOOK_MARKER,
    "hook_path": ".claude/hooks/agent-cap.js",
}
_FRAGMENT_KEYS = tuple(AGENT_CAP)


def load_fragment(path: Path) -> dict:
    """Read + validate a fragment file. Every key is required and must be a non-empty string.

    A fragment missing `marker` would leave the dedup test and check-wiring's arm nothing to join
    on, so this refuses rather than defaulting: a silently marker-less fragment re-appends its hook
    on every run and reports UNWIRED forever.
    """
    try:
        frag = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as e:
        raise ValueError(f"cannot read fragment {path}: {e}") from e
    if not isinstance(frag, dict):
        raise ValueError(f"fragment {path} is not a JSON object")
    bad = [k for k in _FRAGMENT_KEYS if not isinstance(frag.get(k), str) or not frag[k].strip()]
    if bad:
        raise ValueError(f"fragment {path} missing/empty: {', '.join(bad)}")
    return {k: frag[k] for k in _FRAGMENT_KEYS}


def _command(hook_path: str) -> str:
    # forward slashes on purpose: ${CLAUDE_PROJECT_DIR} + POSIX path is identical on every OS
    return f'node "${{CLAUDE_PROJECT_DIR}}/{hook_path}"'


def merge(obj: dict, hook_path: str, frag: dict = AGENT_CAP) -> dict:
    """Ensure the fragment's hook is present in obj (mutates + returns obj)."""
    event, matcher, marker = frag["event"], frag["matcher"], frag["marker"]
    hooks = obj.setdefault("hooks", {})
    if not isinstance(hooks, dict):
        raise ValueError("settings 'hooks' is not an object")
    pre = hooks.setdefault(event, [])
    if not isinstance(pre, list):
        raise ValueError(f"settings 'hooks.{event}' is not an array")
    entry = {"type": "command", "command": _command(hook_path)}
    group = next((g for g in pre if isinstance(g, dict) and g.get("matcher") == matcher), None)
    if group is None:
        pre.append({"matcher": matcher, "hooks": [entry]})
        return obj
    inner = group.setdefault("hooks", [])
    if not isinstance(inner, list):
        raise ValueError(f"settings {matcher} group 'hooks' is not an array")
    if any(isinstance(h, dict) and marker in str(h.get("command", "")) for h in inner):
        return obj  # already wired — no change
    inner.append(entry)
    return obj


def _load(path: Path) -> dict:
    if not path.exists():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as e:  # ValueError covers json.JSONDecodeError
        raise ValueError(f"cannot read {path}: {e}") from e
    if not isinstance(data, dict):
        raise ValueError(f"{path} is not a JSON object")
    return data


def _dump(obj: dict) -> str:
    return json.dumps(obj, indent=2, ensure_ascii=False) + "\n"


def run(settings_file: str, hook_path: str, check: bool, frag: dict = AGENT_CAP) -> int:
    path = Path(settings_file)
    existed = path.exists()
    what = f"{frag['name']} {frag['matcher']} hook"
    try:
        before = _dump(_load(path))
        after = _dump(merge(json.loads(before), hook_path, frag))
    except ValueError as e:
        print(f"settings-merge: {e}", file=sys.stderr)
        return 2
    if before == after:
        print(f"settings-merge: {what} already wired in {settings_file}")
        return 0
    if check:
        print(f"settings-merge: DRIFT — {settings_file} is missing the {what}", file=sys.stderr)
        return 1
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        if existed:
            Path(str(path) + ".bak").write_bytes(path.read_bytes())  # byte-faithful, not the normalized parse
        path.write_text(after, encoding="utf-8", newline="\n")
    except OSError as e:
        print(f"settings-merge: write failed: {e}", file=sys.stderr)
        return 2
    print(f"settings-merge: wired {what} into {settings_file}"
          + (f" (backed up to {settings_file}.bak)" if existed else " (created)"))
    return 0


def _selftest() -> int:
    hp = ".claude/hooks/agent-cap.js"
    cmd = _command(hp)
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)

        # 1) absent file -> creates the Workflow group + agent-cap command, exit 0
        sf = root / ".claude" / "settings.json"
        assert run(str(sf), hp, check=False) == 0
        wf = [g for g in json.loads(sf.read_text(encoding="utf-8"))["hooks"]["PreToolUse"]
              if g.get("matcher") == "Workflow"]
        assert len(wf) == 1 and any(h["command"] == cmd for h in wf[0]["hooks"])
        assert "\r" not in sf.read_text(encoding="utf-8")  # LF-only on every OS

        # 2) re-run -> byte-identical (no change); --check on a wired file -> 0
        first = sf.read_text(encoding="utf-8")
        assert run(str(sf), hp, check=False) == 0 and sf.read_text(encoding="utf-8") == first
        assert run(str(sf), hp, check=True) == 0

        # 3) pre-existing unrelated key is preserved through the merge
        sf2 = root / "s2.json"
        sf2.write_text('{"model": "x"}\n', encoding="utf-8")
        assert run(str(sf2), hp, check=False) == 0
        o2 = json.loads(sf2.read_text(encoding="utf-8"))
        assert o2["model"] == "x" and o2["hooks"]["PreToolUse"][0]["matcher"] == "Workflow"

        # 4) pre-existing Workflow group w/ a FOREIGN command -> agent-cap appended, foreign kept, ONE group
        sf3 = root / "s3.json"
        sf3.write_text(json.dumps({"hooks": {"PreToolUse": [
            {"matcher": "Workflow",
             "hooks": [{"type": "command", "command": "node other.js"}]}]}}) + "\n", encoding="utf-8")
        assert run(str(sf3), hp, check=False) == 0
        wf3 = [g for g in json.loads(sf3.read_text(encoding="utf-8"))["hooks"]["PreToolUse"]
               if g.get("matcher") == "Workflow"]
        cmds = [h["command"] for h in wf3[0]["hooks"]]
        assert len(wf3) == 1 and "node other.js" in cmds and cmd in cmds

        # 5) malformed JSON -> exit 2
        sf4 = root / "s4.json"
        sf4.write_text("{ not json", encoding="utf-8")
        assert run(str(sf4), hp, check=False) == 2

        # 6) --check on an absent file -> drift (1), and nothing written
        sf5 = root / "sub" / "s5.json"
        assert run(str(sf5), hp, check=True) == 1 and not sf5.exists()

        # --- --fragment: a SECOND hook, on a different event and matcher -----------------------
        recall = {"name": "recall-opened", "event": "PostToolUse", "matcher": "Read",
                  "marker": "recall-opened.js", "hook_path": ".claude/hooks/recall-opened.js"}
        rhp = recall["hook_path"]

        # 7) a fragment adds ITS block and leaves the agent-cap one alone; re-run is byte-identical
        sf6 = root / "s6.json"
        assert run(str(sf6), hp, check=False) == 0                 # agent-cap first
        cap_only = sf6.read_text(encoding="utf-8")
        assert run(str(sf6), rhp, check=False, frag=recall) == 0
        both = json.loads(sf6.read_text(encoding="utf-8"))["hooks"]
        assert [g["matcher"] for g in both["PreToolUse"]] == ["Workflow"]
        assert [g["matcher"] for g in both["PostToolUse"]] == ["Read"]
        assert recall["marker"] in both["PostToolUse"][0]["hooks"][0]["command"]
        assert cap_only != sf6.read_text(encoding="utf-8")          # it really did change something
        wired = sf6.read_text(encoding="utf-8")
        assert run(str(sf6), rhp, check=False, frag=recall) == 0
        assert sf6.read_text(encoding="utf-8") == wired             # AC10: re-run changes nothing
        assert run(str(sf6), rhp, check=True, frag=recall) == 0
        assert run(str(sf6), hp, check=True) == 0                   # ...and agent-cap still reads wired

        # 8) the fragment's OWN drift is detected independently of agent-cap's
        sf7 = root / "s7.json"
        assert run(str(sf7), hp, check=False) == 0
        assert run(str(sf7), rhp, check=True, frag=recall) == 1

        # 9) a fragment with no marker is REFUSED, not defaulted — a marker-less fragment
        #    re-appends its hook every run and reports UNWIRED forever.
        for broken in ({"name": "x", "event": "E", "matcher": "M", "hook_path": "h"},
                       {"name": "x", "event": "E", "matcher": "M", "marker": " ", "hook_path": "h"},
                       ["not", "an", "object"]):
            bf = root / "frag.json"
            bf.write_text(json.dumps(broken), encoding="utf-8")
            try:
                load_fragment(bf)
                raise AssertionError(f"accepted a bad fragment: {broken}")
            except ValueError:
                pass
        assert main([str(root / "s8.json"), "--fragment", str(root / "nope.json")]) == 2

        # 11) the MERGE is refused when the hook script it would dispatch does not exist. The
        #     wired-but-script-missing state is reachable from two separate WIRE commands run out of
        #     order, and it makes Claude Code run `node` against nothing on every matching call.
        sf9, gone, there = root / "s9.json", root / "gone.js", root / "here.js"
        assert main([str(sf9), "--hook-path", str(gone)]) == 2 and not sf9.exists()
        assert main([str(sf9), "--hook-path", str(gone), "--check"]) == 1, "--check is a report, not a merge"
        there.write_text("// stub\n", encoding="utf-8")
        assert main([str(sf9), "--hook-path", str(there)]) == 0 and sf9.exists()

        # 10) the SHIPPED fragment beside this script parses and declares the schema check-wiring
        #     joins on. Skipped, not failed, in a project that did not adopt memory-recall.
        shipped = Path(__file__).resolve().parent / "memory-recall" / "recall-opened.fragment.json"
        if shipped.is_file():
            got = load_fragment(shipped)
            assert got == recall, f"shipped fragment drifted from the pinned schema: {got}"

    print("settings-merge selftest: PASS")
    return 0


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(
        description="Idempotently wire a hook fragment into .claude/settings.json")
    p.add_argument("settings_file", nargs="?", default=".claude/settings.json")
    p.add_argument("--fragment", default=None)
    p.add_argument("--hook-path", default=None)
    p.add_argument("--check", action="store_true")
    p.add_argument("--selftest", action="store_true")
    a = p.parse_args(argv)
    if a.selftest:
        return _selftest()
    frag = AGENT_CAP
    if a.fragment:
        try:
            frag = load_fragment(Path(a.fragment))
        except ValueError as e:
            print(f"settings-merge: {e}", file=sys.stderr)
            return 2
    hook_path = a.hook_path or frag["hook_path"]
    # Refuse to wire a script that is not there: settings would dispatch `node <missing>` on every
    # matching tool call, and check-wiring can only NAME that state, not prevent it. Resolved from
    # the cwd, which the runbook fixes at the target repo root. --check is exempt — it writes
    # nothing, it reports drift, and the hook file is not what it is reporting on.
    if not a.check and not Path(hook_path).exists():
        print(f"settings-merge: refusing to wire {frag['name']} — {hook_path} does not exist "
              f"(from {Path.cwd()}). Copy the hook there first (or pass --hook-path); wiring a "
              "missing script makes every matching tool call run `node` against nothing.",
              file=sys.stderr)
        return 2
    return run(a.settings_file, hook_path, a.check, frag)


if __name__ == "__main__":
    sys.exit(main())
