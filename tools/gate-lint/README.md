# gate-lint — drop-in source-hygiene scans

Project-agnostic checks for classes that make a script misbehave **silently**. This kit has no gate
legs of its own — the consuming project does — so wiring is a two-line adoption step, documented
here rather than left implicit.

## ps-hygiene.py

```bash
python3 tools/gate-lint/ps-hygiene.py [root]   # exit 0 clean, 1 findings, 2 usage
python3 tools/gate-lint/ps-hygiene.py --selftest
```

Scans **every** `.ps1` under `root` for two classes:

- **Case-only identifier collisions.** PowerShell variable names are case-INSENSITIVE, so `$LEGS`
  and `$legs` are ONE variable. Upstream this bit one file three times: `$LEGS = @($legs.legs)`
  overwrote a parsed manifest with its own sub-array, and `foreach ($sel in ...)` clobbered a `$SEL`
  selection map — which also disabled the backstop that read `$SEL`, because a guard sharing a
  variable with the thing it guards is not a guard.
- **BOM-less scripts containing non-ASCII.** PowerShell 5.1 decodes them as CP1252, so an em dash
  inside a double-quoted string becomes three chars ending in U+201D — which PowerShell accepts as a
  string delimiter. It closes the string early and desynchronises the parser. Every text-mode read
  hides this, so the check is byte-level.

## Wiring it into a host project

Add it as a gate leg wherever that project enumerates them, e.g. an entry in a leg manifest, a CI
step, or a pre-commit hook:

```bash
python3 tools/gate-lint/ps-hygiene.py . || exit 1
```

Run `--selftest` in the same place. Per `parallel-coding-governance.domain-rules.md` §14, a gate
whose failing case has never been observed is not a gate — `--selftest` is how this one proves it
can still fail after a refactor.

**Adoption is not automatic.** A repo with no `.ps1` files gets `0 files clean`, which is honest but
proves nothing; the scan only earns its place where PowerShell exists.
