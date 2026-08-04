#!/usr/bin/env bash
# Runnable check for the portable agent-cap.js Workflow fan-out guard.
# Run: bash hooks/agent-cap.test.sh   (exit 0 = all pass)
set -u
HOOK="$(cd "$(dirname "$0")" && pwd)/agent-cap.js"
pass=0; fail=0
check() { # name expected_exit json
  printf '%s' "$3" | node "$HOOK" >/dev/null 2>/tmp/acap.err; local got=$?
  if [ "$got" = "$2" ]; then echo "ok   $1 (exit $got)"; pass=$((pass+1))
  else echo "FAIL $1 (exit $got, want $2)"; cat /tmp/acap.err; fail=$((fail+1)); fi
}
check "raw parallel(items.map) → deny" 2 '{"tool_name":"Workflow","tool_input":{"script":"const r = await parallel(D.map(d => () => agent(d.p)))"}}'
check "raw pipeline(items,...) → deny" 2 '{"tool_name":"Workflow","tool_input":{"script":"const r = await pipeline(files, s1, s2)"}}'
check "boundedParallel + marker → allow" 0 '{"tool_name":"Workflow","tool_input":{"script":"async function boundedParallel(t,cap=6){const o=[];for(let i=0;i<t.length;i+=cap)o.push(...await parallel(t.slice(i,i+cap))); // gov:bounded-fanout\nreturn o}\nconst r = await boundedParallel(D.map(d=>()=>agent(d.p)),6)"}}'
check "non-Workflow tool → allow" 0 '{"tool_name":"Bash","tool_input":{"command":"parallel(x.map(y))"}}'
check "scriptPath run (no inline) → allow" 0 '{"tool_name":"Workflow","tool_input":{"scriptPath":"/x/tier2-review.js"}}'
check "member .parallel( → allow" 0 '{"tool_name":"Workflow","tool_input":{"script":"queue.parallel(2); log(1)"}}'
check "comment mentioning parallel() → allow" 0 '{"tool_name":"Workflow","tool_input":{"script":"// use boundedParallel(), never raw parallel()\nconst r = await boundedParallel(t,6)"}}'
check "parallel() only inside a string → allow" 0 '{"tool_name":"Workflow","tool_input":{"script":"const meta = { description: \"finders run, never raw parallel()\" }\nconst r = await boundedParallel(t, 6)"}}'
check "string mentions parallel() + a real raw parallel( → deny" 2 '{"tool_name":"Workflow","tool_input":{"script":"const note = \"we avoid parallel() normally\"\nconst r = await parallel(items.map(f))"}}'
echo "---- $pass passed, $fail failed ----"
[ "$fail" = 0 ]
