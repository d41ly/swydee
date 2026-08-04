#!/usr/bin/env bash
# run-ps-suite.sh <Suite.ps1> — bash launcher for one PowerShell 5.1 test suite.
#
# Why this exists rather than putting powershell.exe straight into gate-legs.json: the runner's
# canary (tools/run-gates.test.sh) hard-rejects any leg whose argv[0] is not bash/python/python3,
# and that canary is the only thing standing between swydee and a silently malformed leg manifest.
# Widening the canary would fork an upstream file; wrapping the suite does not.
#
# Contract: propagate the suite's EXIT CODE untouched. swydee's suites are not uniform in what they
# print — three end with `Test-<Name>: N passed, M failed.` and five with `RESULT: N passed, M failed`
# — so exit status is the only trustworthy signal. Never parse the prose.
set -u
top=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "run-ps-suite: not a git repo"; exit 2; }
cd "$top" || exit 2

suite=${1:-}
[ -n "$suite" ] || { echo "usage: run-ps-suite.sh <Suite.ps1>"; exit 2; }
[ -f "$suite" ] || { echo "run-ps-suite: no such suite: $suite"; exit 2; }

# Windows PowerShell 5.1. Override with SWYDEE_PS if the launcher ever differs.
PS=${SWYDEE_PS:-powershell.exe}
command -v "$PS" >/dev/null 2>&1 || { echo "run-ps-suite: launcher '$PS' not found on PATH"; exit 2; }

"$PS" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$suite"
