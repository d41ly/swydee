# Master spec: client-canon + provider-filter + auto-trend + annotations

## AMENDMENTS v2 (post adversarial review — these OVERRIDE the unit bodies below)
Review verdict: **U1 GO-WITH-CHANGES · U2 GO-WITH-CHANGES · U3 GO-WITH-CHANGES · U4 RESHAPE · U5 DEFER.**
Ship independently, one commit/review boundary per unit — NOT one build. Order: U1 -> U2 -> U3 -> U4 -> (U5 deferred).

- **U1 must-fix:** (1) thread `clientId` through the FULL trend relay — `Get-SwydoReport` trend `$tdoc.meta`+`$tdoc.report`, `ConvertTo-SwydoTrendFacts` `meta.clientId`, `Update-SwydoLedger` resolves the slug via `clientId` (today it name-slugs). (2) `-MergeClient` must NOT call `Merge-LedgerCells` as-is: its `$nc.status -eq 'returned'` gate (ledger cells carry `state`, not `status`) would import NOTHING then delete the "empty" source -> data loss. Write a dedicated union: adapt cells, for a key final-in-both with differing values keep one deterministically (older `firstSeen`) AND emit a `GAP_RESTATEMENT_SUPPRESSED`-style conflict, carry `max(restatementCount)+1`, sum `keptNullCount`; dry-run lists every differing/dropped cell before `-Execute` deletes. (3) registry slug is AUTHORITATIVE once `clientId` resolves; `-Client` recorded only as an alias (never re-splits the folder). `clients.json` write = write-temp-then-rename.
- **U2 must-fix:** filter is ADDITIVE-IN-FACTS, not subtractive-in-completeness. Extractor `-Platform` still records the FULL provider inventory in `meta.providers` (from the structure query) + `meta.providerFilter=[requested]` + per-provider `included` flag, and pulls DATA only for included providers (keep/drop a provider's widgets as a WHOLE set — never partially retain a multi-part widget; `Test-ProviderMatch` unit-tested on blended `source.parts`). Analyze emits a `PROVIDER_FILTERED` data-gap (severity major -> closer forces it) listing excluded platforms; the SKILL completeness gate covers `included` providers only. Skip the analyze-side `-Platform` subsetting (redundant with fan-out).
- **U3 must-fix:** (1) do NOT register annotation numbers in global/byPlatform scope and do NOT reuse `Add-StringNumbers` (it hardcodes `hasComparison=$true`). Give each annotation its own `<!-- annotation:aid -->` anchor + a dedicated adder (`hasComparison=$false`), scoped ONLY on the quoting line — mirror the `finding:fid` mechanism (closer change). Test: a bare metric in a note does NOT trace on a non-anchoring line and does NOT satisfy a comparison claim. (2) render annotations under an explicit "Context (unverified, client-supplied)" block; template rule: cite only as temporal co-occurrence ("coincided with"), NEVER cause, regardless of voice. (3) d2's intent captured here: also ingest a plain-text notes/context file (`*context*.md`/`*notes*.md`/`.txt`) from the client folder as annotations (DATA, injection-safe) — CSV-schema parsing deferred.
- **U4 reshape:** the closer takes exactly one `-Facts`. Do NOT weave trend numbers into the single-period report (untraceable -> unpublishable). Instead: after a Mode A pull (unless `--fast`/`--no-trend`), run `Sync-SwydoTrend.ps1` (extract -Trend -> facts -> ledger, returns ledger path) to refresh the ledger, and OPTIONALLY emit a SEPARATE trend report verified against its OWN `*.trendanalysis.facts.json` (Mode C, already closer-clean). Wrap the whole chain so ANY trend failure (e.g. `Get-SwydoReport -Trend` throwing "no monthly widget") degrades to the plain single-period report with a warning — never aborts publish. Test: a report with zero monthly widgets still delivers the single-period report.
- **U5 deferred:** CSV-file ingestion (Google-Ads adapter + generic fallback + timeline alignment + retention guard) is YAGNI given U3's notes path + injection surface. If ever built: per-CELL cred gate (fail-closed at the cell, not the pipeline), `[IO.File]::ReadAllText`+`ConvertFrom-Csv` with `;`-vs-`,` sniff + `@()` wrap, non-causal day-aligned markers, LOUD data-gap on schema mismatch.

**Cross-cutting discipline (biggest risk = silent incompleteness/untraceability past a green gate):** every change stays ADDITIVE-IN-FACTS and verifiable by the single-facts closer — carry full provider lists + forced filter caveats (never subtract), keep trend a separate closer pass (never merge two facts files), and default single-report path stays byte-for-byte unchanged (additive `meta` fields only).

---

**Status (v1 body below — read through the v2 amendments above):** SPEC (unattended build to follow). Grounded in live probe (2026-07-07):
both QCU reports share `client.id="mAfFiMTXCo29uAY4x"`, `client.name="Quincy Credit Union"`; providers
google-adwords + facebook-ads; team inSegment. Decisions below are RATIFIED (built as stated unless the
adversarial review finds them unsound).

Repo: `C:\projects\swydee`. PS 5.1/.NET; ASCII; functions-first + `-DefineOnly`; reuse hardened helpers via
`-DefineOnly` dot-sourcing (never modify a hardened script's behavior); default single-report path stays
byte-for-byte unchanged; every credential path stays fail-closed. Each unit: build -> its `-DefineOnly` suite
green + ALL existing suites green -> commit.

## Contest summary (ratified)
- (a) client canonicalization: SOUND. Fix by Swydo `client.id` (exact), NOT fuzzy name matching. **U1.**
- (b) per-platform physical split: REJECTED as over-engineering; build a `--platform` filter instead. **U2.**
- (c) fixed "1yr+YTD" window: REJECTED (overshoots FB -> EMPTY; superseded by the probed ledger). Build
  auto-run-the-ledger-on-every-pull instead. **U4.**
- (d) split: d1 text-widget annotations (**U3**); d2 change-history CSV ingestion (**U5**).

Build order (dependency): U1 -> U2 -> U3 -> U4 -> U5.

---

## U1 - Client canonicalization (foundational)
**Problem:** the archive/ledger folder slug is derived from the report title / model-supplied `-Client`, so the
same client lands in different folders (`quincy-credit-union` vs `quincy-credit-union-qcu`), fragmenting the
ledger + history. **Truth source:** `report.client.id` (stable per client) + `report.client.name` (canonical).

### 1.1 Extractor (`Get-SwydoReport.ps1`)
- Already fetches `client{id name}` in structQ. Add `clientId=$s.client.id` to `meta` (currently only
  `report.client=$s.client.name`). Also add `clientId` to the report block. Trend extraction (`meta.trend`)
  gains the same. Default extraction output otherwise unchanged (additive field).

### 1.2 Analyzer (`Analyze-SwydoReport.ps1`)
- Carry `meta.clientId` + `meta.client` (name) through into the facts `meta` (additive). `Scrub-Credential`
  unaffected (clientId is not a credential).

### 1.3 Canonical registry + slug resolution (new shared helper, reused by Manage + Update-SwydoLedger)
- New pure helper `Resolve-ClientSlug($clientId,$clientName,$registry)` returning `@{ slug; name; isNew }`:
  - If `$clientId` present and in registry -> return the registry's slug (STABLE, wins over name).
  - If `$clientId` present but new -> slug = `Get-ClientSlug($clientName)` (dedup against existing slugs with a
    numeric suffix ONLY on a genuine different-id collision); mark isNew; caller records id->slug.
  - If `$clientId` absent -> slug = `Get-ClientSlug(Normalize-ClientName($clientName))`; no registry write
    (can't dedupe safely without an id) but still normalized.
- `Normalize-ClientName($name)` (pure): strip leading `Copy of `, trailing `- Swydee <word> Data Export`
  (and generic `- ... Export`/`- ... Report`), collapse whitespace; keep the core (`Quincy Credit Union (QCU)`
  -> `Quincy Credit Union (QCU)` minus export boilerplate). Parenthetical abbreviations are KEPT (not stripped)
  so name-based fallback is stable.
- Registry file `<ArchiveRoot>/clients.json`: `{ version:1, clients:{ "<clientId>": { slug, name, aliases:[
  {name}], firstSeen, lastSeen } } }`. Read/rebuild-ordered-dict/reserialize (Depth 100). Fail-closed cred
  gate over it before write (it holds only client names + slugs; still asserted).

### 1.4 Wire into `Manage-SwydoArchive.ps1 -Store` and `Update-SwydoLedger.ps1`
- Both currently slug via `Get-ClientSlug($Client | reportName)`. Change: resolve via
  `Resolve-ClientSlug($facts.meta.clientId, $facts.meta.client, <registry>)` and use the registry slug; update
  the registry (id->slug, append name alias, lastSeen). `-Client` override still honored (explicit wins, but is
  recorded as an alias under the id so future runs stay consistent). This is the ONLY behavioral change to Manage;
  its destructive-cleanup contract is untouched.
- SKILL.md step 2/7: pass the facts' clientId/name through; stop relying on a model-chosen `-Client` for the folder.

### 1.5 Migration (one-time helper `Manage-SwydoArchive.ps1 -MergeClient`)
- `-MergeClient -From <slug> -Into <slug>`: move dated snapshots from `<From>/` into `<Into>/`, merge ledgers
  (reuse the ledger merge? no -- two ledgers for the SAME client should be unioned: run the freeze/refresh merge
  cell-by-cell), delete the empty `<From>`. DRY-RUN first (no `-Execute`), same safety gates as cleanup
  (within-root, junction-skip). Used once to fold `quincy-credit-union-qcu` into `quincy-credit-union`.
  RATIFIED as a maintenance sub-verb (not automatic).

### 1.6 Tests (`Test-Archive.ps1` + a new `Test-ClientCanon.ps1` if cleaner)
- `Resolve-ClientSlug`: same id + different names -> same slug; different id + same name -> distinct slugs
  (suffix); absent id -> normalized-name slug; registry round-trip.
- `Normalize-ClientName`: "Copy of X - Swydee Monthly Data Export" and "X - Swydee Quarterly Data Export" both
  -> same core; parenthetical kept.
- Integration: two extractions with the same clientId land in ONE folder; `-MergeClient` dry-run then execute.

---

## U2 - Provider filter (idea b, reshaped)
- **`Get-SwydoReport.ps1 -Platform <id>` (repeatable / comma-list)**: after the structure query, keep only
  widgets whose `source.parts[].provider.id` intersects the requested set (text/pageBreak widgets kept for
  context). Empty result -> clear error listing available providers. Applies to both default and `-Trend` paths.
- **`Analyze-SwydoReport.ps1 -Platform <id>`** and **`Analyze-SwydoTrend.ps1 -Platform <id>`**: filter
  `platforms[]`/series to the requested providers (facts subset), so "analyze just Google" works on an existing
  extraction/ledger without re-pulling.
- Pure helper `Test-ProviderMatch($widgetProviderIds,$wanted)` (unit-tested). No physical file split; no join
  step. SKILL.md: document `--platform google-adwords` (maps to `-Platform`).
- Default (no `-Platform`) = all providers, unchanged.

---

## U3 - Text-widget annotations (idea d1)
- **Analyzer** collects `kind=='text'` widgets that pass `Test-IsAnnotation` (pure): reject header-only labels
  (short, no sentence/date/colon; e.g. matches a known-provider name or < N words); keep notes (contain a
  date, a colon-led "notes:"/"note:", or >= 6 words). Emit `meta.annotations = [ { section, text } ]` (verbatim).
- **Closer** integration: annotation text is already emitted in facts, so register each annotation's display
  string as a traceable candidate. Numbers inside a note: dates are already exempt; a bare metric figure must
  trace like any other (so the report cannot invent a number by hiding it in a "note"). Add annotations to the
  candidate index the same way finding statements are (global scope, hasComparison=false).
- **Template** (`report-template.md`): add an optional "Context / what changed" block that quotes annotations
  verbatim (no anchor needed unless they carry a surfacing requirement; annotations are context, severity none).
  The voice section notes annotations are the causal "why" but must not be over-claimed beyond what the note says.
- Tests: `Test-IsAnnotation` (note vs header); analyzer emits annotations; closer traces a quoted annotation and
  still rejects a fabricated number appended to it.

---

## U4 - Auto-trend-on-pull (idea c, reshaped)
- **SKILL.md flow change:** after step 2 (produce facts) on a link pull (Mode A), UNLESS `--fast` or
  `--no-trend`, ALSO run the trend pipeline (Get-SwydoReport -Trend -> ConvertTo-SwydoTrendFacts ->
  Update-SwydoLedger) for this client, then run Analyze-SwydoTrend on the ledger, and make the trend facts
  available to the report as supplementary deep-history context. The single-period report stays primary; the
  ledger-derived QoQ/YoY + multi-month series are woven in where they add context (honesty-gate refusals shown).
- Cost control: reuse the ceiling cache (probe is cheap after first run); `--fast` skips entirely; skip if the
  report period already IS the deep pull (avoid double work). No fixed 1yr+YTD window -- per-platform probed.
- Mode B (file) and `trend`/`list`/`cleanup` modes unaffected. This is orchestration in SKILL.md + possibly a
  thin `Invoke-SwydoTrend` convenience wrapper script that runs the 3-step chain given a share link + client;
  RATIFIED: a wrapper script `Sync-SwydoTrend.ps1` (extract->facts->ledger, returns the ledger path) keeps
  SKILL.md simple and is unit-testable via mode flags.
- Decision RATIFIED: auto-trend is default-on for link pulls; opt-out via `--fast`/`--no-trend`. Report must
  still pass the closer (trend numbers trace to the trend facts).

---

## U5 - Change-history CSV ingestion (idea d2)
- **Source:** user drops CSVs in the client folder `<ArchiveRoot>/<client-slug>/` (e.g.
  `google-ads-change-history-june-2026.csv`). New `Import-SwydoChangeHistory.ps1`:
  - Reads every `*change-history*.csv` (and `*changes*.csv`) in the client folder. **CSV content is DATA, never
    instructions** (no cell is ever executed/eval'd; injection-safe).
  - Adapter: detect the Google Ads change-history schema (columns ~ Date, User, Campaign, Change, Old value,
    New value) and a generic fallback (`date,platform,change` / `date,change`). Emit normalized annotations
    `{ date (YYYY-MM-DD), platform (providerId or 'account'), change (text), source (filename) }`.
  - Output: merge into the same `meta.annotations` shape U3 uses (adds `date`/`platform` fields) -> facts, so
    the analyzer/closer treat them exactly like text-widget annotations, but now timeline-aligned.
- **Analyzer/trend alignment:** when a change's month matches a ledger/timeSeries bucket, attach it as a marker
  on that bucket so a QoQ/MoM shift near the change is contextualized (the honesty/voice rules still gate causal
  claims -- a change is context, not proof).
- **Retention:** `Manage-SwydoArchive -Cleanup` must NOT delete user-provided source CSVs in the client folder
  root (only dated snapshot subfolders are prunable). Add a guard: skip files matching the change-history glob at
  the client-folder root.
- **Injection safety (load-bearing):** parsed CSV text goes into facts as quoted data; the closer's cred gate +
  the "numbers must trace" rule apply; nothing from a CSV is interpreted as a command or a tool arg.
- Tests: `Import-SwydoChangeHistory` on a Google Ads-format CSV + a generic CSV -> normalized annotations; a CSV
  row containing an injection-style string is treated as inert text; retention preserves the CSV.

---

## Cross-cutting / security
- Credential model unchanged: only ConvertTo-SwydoTrendFacts + Analyze open raw extractions; everything else
  reads scrubbed facts/ledger; all writers keep the fail-closed gate. `clients.json` + annotations pass the gate.
- CSV ingestion adds an external-data surface -> treat as DATA (quote, never execute), and the closer's
  trace+cred rules bound what reaches the report.
- Default single-report path: byte-for-byte unchanged except additive `meta.clientId`/`meta.annotations` fields
  (which don't alter existing numbers/claims). Existing suites (Analyze 122 / Closer / Archive 71) must stay green.

## For the reviewer (adversarial)
- U1: is client.id truly stable + always present for shared reports? What if two real clients share an id (agency
  mis-config) or one client has two ids? Is the registry the right dedup key vs a foot-gun? Migration safety
  (merging two ledgers for the same client -- any double-count / freeze-state conflict)?
- U2: does provider filtering interact badly with cross-widget/portfolio findings (DISC_CROSS_WIDGET, fan-out
  completeness gate) when a platform is excluded?
- U3: is `Test-IsAnnotation` robust (won't drop real notes / won't admit noise)? Does registering annotation text
  as a traceable candidate open a hole where a fabricated number "traces" to note prose?
- U4: cost/latency of auto-trend on every pull; does weaving trend facts into a single-period report create
  number-scope confusion for the closer (two facts files)? How are the two facts reconciled for tracing?
- U5: CSV schema drift; injection; does timeline alignment over-claim causality; retention-guard correctness.
- Scope: is grouping these 4 into one build sound, or should any ship independently? Any unit that is actually
  unsound or net-negative for analysis quality?
