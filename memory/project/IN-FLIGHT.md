# In-flight ledger — sharded per node

One file per node under `in-flight/`. **Write ONLY your own node file** (`in-flight/<tag>.md`) so the ledger never conflicts on merge; **read all** of them for the who-is-touching-what / slug-collision scan. Row: node · slug · branch · streams · status; status in {in-flight | merged:<sha>}. Self-prune your own merged rows once the sha is an ancestor of `main`.
