# Swydo Shared Report — Data Extraction Spec

**Purpose.** Read all data out of a Swydo *shared report* link (`https://swy.do/shares/<KEY>`) programmatically, without a browser. Self-contained: follow it top-to-bottom, or run the reference script in §9. Another session should never need to re-derive any of this.

**Status.** Every claim below was reproduced live on 2026-07-05 against `https://swy.do/shares/jNqoFL4gPkgSNXMoT8neKrgxHKo3nFnoDvhFhdY2QimFTqTN` (Quincy Credit Union, Q2 2026 PPC) — first by deriving it, then by an independent clean-room verification pass. Items that could not be exercised on that report (password-protected shares; providers other than Google/Facebook Ads; genuine cache-miss push delivery) are explicitly marked **UNVERIFIED**.

---

## 1. When to use this

- You have a public Swydo share URL (`swy.do/shares/...`) and want the underlying numbers, not a screenshot.
- The browser route (scroll to lazy-load widgets) is unavailable or unreliable. This API route is *more* complete — it returns every widget's full row set.
- Read-only. Nothing here mutates the report. The share link is a bearer credential; treat it as a secret.

## 2. Architecture — the request chain

```
swy.do/shares/<KEY>            (static HTML, an <iframe>)
        │  iframe src
        ▼
app.swydo.com/g/<KEY>/reports/<REPORT_ID>   (React SPA)
        │
        ├── GET  vesting.swydo.com/jwt/share      → short-lived JWT (Basic auth = the share key)
        ├── POST graphql.swydo.com                → report structure + widget data (Bearer JWT)
        └── WS   wss://ws.swydo.com               → assigns a socketId; carries cache-miss result pushes
```

Three hosts, discoverable from the SPA bundle's config object (`app.swydo.com/main.<hash>.js`, search `graphqlUrl`/`vestingUrl`/`websocketUrl`) if any ever change:

| Role | URL |
|---|---|
| Auth (JWT mint) | `https://vesting.swydo.com` |
| GraphQL API | `https://graphql.swydo.com` |
| WebSocket | `wss://ws.swydo.com` |

## 3. Step 1 — Resolve the share link → REPORT_ID

`GET https://swy.do/shares/<KEY>` (use GET, not HEAD — HEAD returns 404) returns HTML whose body is a single iframe:

```html
<iframe src="https://app.swydo.com/g/<KEY>/reports/<REPORT_ID>"></iframe>
```

`<KEY>` in the iframe path equals the share key; `<REPORT_ID>` is what you pass to the GraphQL `report(id:)` argument. Isolate it (allow `-`/`_`, though observed ids are alphanumeric):

```bash
curl -s "https://swy.do/shares/<KEY>" \
  | grep -oE 'app\.swydo\.com/g/[^/]+/reports/[A-Za-z0-9_-]+' \
  | grep -oE 'reports/[A-Za-z0-9_-]+' | cut -d/ -f2
```

Cross-check the result against the JWT's `access.reports[0]` (§4) — a second, authoritative source of REPORT_ID.

## 4. Step 2 — Mint a JWT

```
GET https://vesting.swydo.com/jwt/share
Authorization: Basic base64("<KEY>:<SECRET>")
```

- `<SECRET>` is empty for a public (no-password) share → `base64("<KEY>:")` (trailing colon required). A wrong/extra secret on a *public* share is silently accepted.
- Password-protected shares pass the password as `<SECRET>` → `base64("<KEY>:<password>")`. **Verified** against a live protected share (35-widget report, password `123`): the JWT mints and all widgets extract normally; the password is not otherwise reflected in the token.
- Response `{"jwt":"<jwt>"}`. Lifetime is exactly **600 s** (`exp - iat = 600`). **Re-mint on 401** — long runs will cross the boundary (§9 handles this).
- Missing `Authorization` header → HTTP **500** (not 401). Only `/jwt/share` works for share links: `/jwt/guest` with the share key returns HTTP 200 but a *report-blind* token (`access:{}`, scope only `query.company query.countries`) — not an alternative.
- Portable base64 (do **not** use GNU-only `base64 -w0`): `printf '%s:' "$KEY" | base64 | tr -d '\n'` or `openssl base64 -A`.

Level→path map (from the SPA): `{SHARE:/jwt/share, TEAM:/jwt/team, USER:/jwt/user, GUEST:/jwt/guest, SUPPORT:/jwt/support}`.

**The JWT payload is your schema cheat-sheet.** It is base64**url** (chars `-` `_`, no `=` padding) — translate before decoding:

```bash
P=$(printf '%s' "$JWT" | cut -d. -f2); P="$P$(printf '%*s' $(( (4 - ${#P}%4)%4 )) '' | tr ' ' '=')"
printf '%s' "$P" | tr '_-' '/+' | base64 -d
```

Payload shape:

```json
{ "version":3, "guestId":"...", "shareId":"...",
  "access": { "teams":["..."], "clients":["..."], "reports":["<REPORT_ID>"] },
  "scope": "query.report.id query.report.name ... query.widget.data mutation.PdfReport.create.node.downloadUrl ...",
  "iat":1783279604, "exp":1783280204 }
```

- `access.reports[0]` = REPORT_ID.
- `scope` is a space-separated whitelist and **is** the effective schema (introspection is disabled, §5). Each token is `<query|mutation>.<Type>.<dotted.field.path>`. **Report-level and widget-level fields are namespaced separately** — this asymmetry is load-bearing (§6): `query.report.widgets.edges.node.source.name` is *absent* while `query.widget.source.name` is present. When a field errors `FORBIDDEN`, grep the scope for its exact path before assuming anything else.
- The scope also contains **mutations** (e.g. `mutation.PdfReport.create.node.downloadUrl` / `.publicUrl` — a server-side PDF export that may be an alternative extraction route worth investigating; `mutation.GuestThread.*` chat) and query fields this spec doesn't use (`query.report.apps/custom/language/coverOptions/cover/brandTemplate/share`, `query.widget.sort/style/visualOptions/manualKpiOptions/hash/target`). `widget.sort` governs row ordering (relevant to paging); `manualKpiOptions` matters for MANUAL KPI widgets that have no provider data source.

```bash
KEY="jNqoFL4gPkgSNXMoT8neKrgxHKo3nFnoDvhFhdY2QimFTqTN"
AUTH=$(printf '%s:' "$KEY" | base64 | tr -d '\n')
JWT=$(curl -s https://vesting.swydo.com/jwt/share -H "authorization: Basic $AUTH" | sed -E 's/.*"jwt":"([^"]+)".*/\1/')
```

## 5. Step 3 — GraphQL basics

```
POST https://graphql.swydo.com
Authorization: Bearer <JWT>
Content-Type: application/json
Body: {"query":"...","variables":{...}}
```

- **Introspection disabled.** `__schema`/`__type` → HTTP **400**, code `GRAPHQL_VALIDATION_FAILED`, message `"GraphQL introspection is not allowed by Apollo Server, but the query contained __schema or __type…"`. (There is no literal `INTROSPECTION_DISABLED` token.) Use the scope claim instead.
- **Error codes you will hit, and what they mean:**
  - `FORBIDDEN` (HTTP 403), `"Insufficient permissions for the given operation"` → you selected a field **outside the scope whitelist**. GraphQL fails the *entire* operation, returning **no data** — one bad leaf yields zero widgets. Bisect against the scope; do **not** re-mint.
  - `GRAPHQL_VALIDATION_FAILED` (400) → malformed query (missing required arg, wrong sub-selection). Verbose and useful — iterate against it.
  - `BAD_USER_INPUT` (200) → bad variable value (e.g. malformed DateRange, §7.4).
  - `UNAUTHENTICATED` / HTTP 401 → JWT expired (~10 min). Re-mint.
  - Note: for non-2xx responses the JSON error body is in the response stream — read it (curl shows it; in PowerShell catch the `WebException` and read `Response.GetResponseStream()`).
- **Scalar vs object fields** (learned by probing): `dateRange`, `compareDateRange`, `content`, `comparisonFormat`, and each `data`-connection `node` are JSON scalars (select bare); `visual`, `displayOptions`, `source`, `client`, `author`, `sections` need sub-selections.

## 6. Step 4 — Report structure

`report` requires `id: ID!`.

```graphql
query {
  report(id: "<REPORT_ID>") {
    id name subtitle orientation
    dateRange            # JSON scalar — capture verbatim; you feed it back in §7
    compareDateRange     # JSON scalar — capture verbatim
    client { id name }
    author { id name email }
    sections { id name isHidden }
    teamName
    widgets { edges { node {
      id
      section { id }
      visual { id }                 # KPI | TABLE | PIE_CHART | LINE_CHART | COLUMN_CHART | TEXT | PAGE_BREAK
      widgetTemplate { id linked }
      source { id parts { id provider { id name } dataSource { id } } }   # NO 'name' here — see below
    } } }
  }
}
```

⚠️ **Do not select `source { name }` under `report.widgets`.** `query.report.widgets.edges.node.source.name` is **not** in the share scope → the whole query returns `FORBIDDEN` with no data. Provider name (`source.parts.provider.name`) *is* available here. The source's own display name is only queryable per-widget (`query.widget.source.name`, §7) — fetch it there if you need it.

Returns the ordered widget list plus `dateRange`/`compareDateRange` as JSON objects you pass **verbatim** into each widget's data query. Example shapes:

```json
"dateRange": {"parent":null,"primary":{"count":-1,"measure":"quarter","type":"RELATIVE"},"comparison":null,"baseDate":null,"timeZone":null}
"compareDateRange": {"parentComparePeriod":null,"comparePeriod":{"period":"previousMonth","type":"PERIOD"}}
```

`source:null` widgets are TEXT/PAGE_BREAK (no data). Enumerate the report's providers via `source.parts.provider.id` (e.g. `google-adwords`, `facebook-ads`) — you need these to apply the right unit rules (§8.1).

## 7. Step 5 — Widget data

Each widget's data lives behind **Observable connections** requiring a `socketId`:

```graphql
query($sid: ID!, $dr: DateRange!, $cp: ComparePeriod!, $after: String) {
  widget(id: "<WIDGET_ID>") {
    id
    content                       # ProseMirror JSON doc for TEXT widgets, else null
    comparisonFormat              # e.g. PERCENTAGE
    visual { id }
    displayOptions { title }      # custom title, else null (falls back to metric name)
    source { id name parts { provider { id name } } }   # source.name IS in scope per-widget
    metrics: fields(socketId: $sid, type: METRIC)    { edges { node { id name } } }
    dims:    fields(socketId: $sid, type: DIMENSION) { edges { node { id name } } }
    data(first: 500, after: $after, socketId: $sid,
         referenceDateRange: $dr, referenceCompareDate: $cp) {
      edges { node cursor }
      pageInfo { hasNextPage endCursor }
    }
  }
}
```

Variables: `$sid` = a socketId (§7.1), `$dr` = `report.dateRange` verbatim, `$cp` = `report.compareDateRange` verbatim, `$after` = `null` for page 1.

Required args (from validation errors): `data`(`first:Int!`, `socketId:ID!`, `referenceDateRange:DateRange!`, `referenceCompareDate:ComparePeriod!`); `fields`(`socketId:ID!`, `type:FieldType!` = `METRIC`|`DIMENSION`). `fields.node` = `ProviderField{id name}`; `data.node` (`WidgetDataRow`) is a **JSON scalar** (select bare).

### 7.1 socketId & the websocket — what actually gates the data

`data`/`fields`/`sort` are typed `Observable…Connection`. The real rule (verified — this corrects a common misconception):

- **The gate is server-side CACHE STATE for the `(widget, dateRange)` pair — not the widget's visual type, and not socket liveness.**
- For a **cached** `(widget, dateRange)` — which includes a report's own stored `dateRange`/`compareDateRange` (§6) once it has been viewed — the HTTP response returns the full rows **synchronously to ANY `socketId` string**. `socketId` is a required arg but its value is *not validated* for cache hits: `"x"`, `""`, a random GUID — all return the data. KPI and TABLE/chart widgets behave identically. **So plain `curl` (§10) can extract the entire report** for its stored date range.
- For a **cache miss** — a `dateRange` the server hasn't computed (e.g. a custom range you supply, or a never-viewed report) — a fake/dead `socketId` returns **empty `edges` and stays empty on retry**. The server computes asynchronously and **pushes the result to a genuinely open websocket** identified by that `socketId`. So a cache miss needs (a) a live `wss://ws.swydo.com` connection and (b) its assigned `socketId` in the query.

> Why the confusion: on a *cold* report the first table query with a placeholder socketId returns empty, so it looks like "tables need a live socket." Opening a live socket and re-querying computes-and-warms them; thereafter *any* socketId returns them from cache. The distinction is cache state, not widget type.

**Practical guidance:** always open a live socket first and reuse the report's stored `dateRange` (a near-certain cache hit) — this is correct for both cached and cold data and costs nothing. Only if you query a *custom* dateRange must you rely on the live-socket push path.

### 7.2 WebSocket protocol

Connect to `wss://ws.swydo.com` (no token in the URL). Messages are JSON `{kind, payload}` (`JSON.stringify`). Enum:

| kind | name | notes |
|---|---|---|
| 1 | CONNECTED | client→server on open: `{kind:1, payload:{}}` (or with current socketId) |
| 2 | SOCKET_ID | server→client: `{kind:2, payload:{socketId:"..."}}` — **store this** (a ~17-char token) |
| 3 | PROMISE_UPDATE | server→client async result push |
| 4 | PING | server→client |
| 5 | PONG | client→server |
| 6 | UPDATE | server→client data update |

Handshake: open → send `{"kind":1,"payload":{}}` → read until `{"kind":2,...}` → keep `payload.socketId`.

⚠️ **Keepalive reality (verified):** the server does **not** reliably send PINGs (kind 4), and an idle socket is **aborted in ~1.5–3.5 s**. Do not wait for a PING to PONG — set `KeepAliveInterval` (~15 s) and/or send a **proactive** PONG (`{kind:5, payload:{socketId}}`) on every idle cycle, and reconnect if the socket state leaves `Open` (a reconnect yields a **new** socketId). During active back-to-back querying the socket stays busy enough; the danger is idle gaps.

⚠️ **Push path (kind 3/6) is documented but UNVERIFIED in practice:** in testing, data always arrived in the HTTP body — zero socket frames were observed even after heavy queries. The `node` payload shape inside a kind:3/6 frame was never captured. If you ever hit a widget whose HTTP `edges` stay empty *with a confirmed-live socket*, you may need to parse rows out of the socket frames (keyed by a promise/query id) — treat that as new territory, not covered here.

### 7.3 Cache-warm retry

Even with a live socket, a cold `(widget, dateRange)` may return empty `edges` on the first hit; the query triggers computation and a later hit returns it. **Loop the data query until `edges` is non-empty** (cap ~8 attempts, keeping the socket alive between tries). Gate the retry on `visual.id` — TEXT/PAGE_BREAK legitimately have no rows. Caveat: this only converges if a **live** socket is held; with a dead socket a cache miss stays empty forever, so the loop just wastes attempts.

### 7.4 Input types (`DateRange!`, `ComparePeriod!`)

Both are validated by a custom **structural** check (shape, not value). Malformed shape → `BAD_USER_INPUT`, `"The structure of the date range object is invalid"` (also `invalid_parent_daterange`).

- **Don't hand-build them.** Pass the exact `report.dateRange` / `report.compareDateRange` objects from §6. This always yields a valid shape. (A structurally-complete hand-built object with *different values* is also accepted and returns data for that range — "verbatim" is sufficient, not strictly required — but partial/minimal objects like `{primary:{…}}` fail.)
- **PowerShell:** re-serialize with `ConvertTo-Json -Depth 10+`. The default depth (2) stringifies the nested `primary`/`comparePeriod` into `"@{count=-1;…}"` and triggers the "invalid" error.
- Shapes: `DateRange` = `{parent, primary:{count,measure,type}, comparison, baseDate, timeZone}` (nulls fine); `ComparePeriod` = `{parentComparePeriod, comparePeriod:{period,type}}`.

### 7.5 Pagination

`data(first:N, after:$after)` — `after` accepts `pageInfo.endCursor` and pages correctly (verified). **`first` does not auto-return everything**: loop `after: endCursor` while `pageInfo.hasNextPage`, accumulating `edges`, or a table with >`first` rows is silently truncated. Use a page size like 500 and page to completion. (Apply the §7.3 warm-retry per page for cold data.)

## 8. Data model & interpretation

A `data.edges[].node` (WidgetDataRow) JSON scalar:

```json
{"id":"...","cells":[<dim…>, <metric…>], "compareCells":[…same shape…],
 "meta":{"currencyCode":"USD","location":null}, "rows":[], "isTotals":false, "isSubtotals":false}
```

- **`cells` order:** first *D* entries = **dimension** values (D = count of `dims` edges), in `dims` order; the rest = **metric** values in `metrics` order. Verified on 1-dim (1+8=9 cells) and 2-dim (2+8=10) tables.
- **`compareCells`** = same layout for the comparison period; `null`/absent when there's no comparison (e.g. device pie, phone-calls-by-day).
- **Dimension cell** = a plain string (`"MOBILE"`, `"2026-04-01"`, ISO week `"202614"`) or an object: `{campaign_id, campaign_name}`, `{campaign_location_id:"geoTargetConstants/1018372", location_resource_name:"Quincy"}`, keyword `{criterion_id, keyword_text}`, FB ad `{id, name, <asset_feed object>}`. Pick the human-readable property (prefer a key containing `name`/`text`; skip resource-path strings matching `^[\w-]+/\d+$` and all-digit ids).
- **Object-valued "metrics":** some `type:METRIC` fields are provider fields that echo a dimension (e.g. a keyword table's `Campaign`/`Ad group` metrics return objects). Drop metric columns whose values are non-scalar.
- **Totals/subtotals:** every data widget returns exactly one `isTotals:true` and one `isSubtotals:true` row plus detail rows. ⚠️ **They appear at the HEAD of the stream** (`isTotals` first, then `isSubtotals`, then details) — filter by the **flags**, not by position (do not assume the total is last). On the totals row, `cells[0]` (first dimension) is JSON `null`; on multi-dim tables the other dimension/echo cells may be an aggregate object like `{"value":[…],"Count":3}`.

### 8.1 Units — CONVERT THESE

Money is stored in **micros** (÷1,000,000 → currency, from `meta.currencyCode`). CTR is a **fraction** (×100 → %). Field ids are `<provider>:<metric>`.

| Provider | Micros (money) field ids | Fraction | As-is |
|---|---|---|---|
| `google-adwords` | `cost_micros`, `average_cpc`, `average_cpm`, `cost_per_conversion` | `ctr` | `impressions`, `clicks`, `conversions` (may be fractional), `phone_calls` |
| `facebook-ads` | `spend`, `cpc`, `costPerActionType::lead`, `costPerActionType::link_click` | `ctr`, `ctrLink` | `impressions`, `reach`, `frequency`, `clicks`, `link_clicks`, leads |

Verified by internal consistency (e.g. `cost_micros/1e6 ÷ clicks == average_cpc/1e6` to zero delta; `ctr == clicks/impressions`). Note the Facebook ids are `spend`/`cpc`/`costPerActionType::…`/`ctrLink` — **not** `amount_spent`/`cost_per_lead`/`cost_per_link_click` (those are display labels, not field ids).

**Other providers (GA4, LinkedIn, Microsoft/Bing, TikTok, Pinterest, Snapchat, … ~30 total) — UNVERIFIED.** The test report used only the two above. Do **not** assume micros for a provider not in this table — Microsoft/Bing, LinkedIn, TikTok, Pinterest, Snapchat and GA4 report spend/cost in **actual account currency**, so a blind ÷1e6 turns $152.34 into $0.00015. To infer units for a new provider: enumerate it via `source.parts.provider.id`, then cross-check a rendered KPI tile's value (from the browser, if available) against the raw `cell`, or reason from the metric's nature.

**Unit contract emitted by the extractor (schemaVersion 2).** `metric.unit` is a **scale hint, not a money flag**:
- `"micros"` → divide by 1e6 to reach the **base unit** (currency **or** e.g. GA4 `engagement_time_micros` → seconds). Use `currencyCode` (surfaced per data widget) to know whether the base unit is money.
- `"fraction"` → multiply by 100 for a percentage.
- **absent** → render raw, never convert.

The extractor only *infers* a unit for the **verified providers** `google-adwords` and `facebook-ads` (listed in `meta.unitBasis`); for any other provider it emits **no** `unit` and adds a `meta.warnings[]` note. The one universal rule is the self-documenting `_micros$` suffix (any provider). This deliberately trades false-positive corruption (v1 tagged every `:spend`/`:cpc`/`:cpm` and `_rate` as convertible, provider-blind) for honest silence on the unverified.

### 8.2 Visual types (`visual.id`)

Seen live: `KPI`, `TABLE`, `PIE_CHART`, `LINE_CHART`, `COLUMN_CHART`, `TEXT` (ProseMirror `content`), `PAGE_BREAK`. Confirmed in the bundle but **not** in the test report: `BAR_CHART`, `AREA_CHART`, `IMAGE`, `HEATMAP`, `MAP` (and likely more in lazy chunks). Because the set is open, the extractor classifies by **shape, not by a visual-name allowlist** (§9.1 `kind`): `visual` is always preserved verbatim, but any data-backed viz (has a `source`) normalizes as `data` regardless of type, and an unrecognized non-data widget becomes `kind:"unknown"` with its raw node preserved — so a new Swydo chart type is never silently dropped or mis-coerced.

### 8.3 TEXT widgets

`content` is a ProseMirror doc: `{type:"doc", content:[{type:"heading"|"paragraph"|"bulletList"|"listItem"|"text", …}]}`. Flatten `text` nodes recursively; `heading.attrs.level` = depth; `bulletList`/`listItem` for bullets. Note author-written text can be **stale** relative to the live tiles (a copied-forward summary describing a previous period) — report values from the data widgets, and flag mismatches.

## 9. Reference implementation

`Get-SwydoReport.ps1` (alongside this spec) runs the whole flow: resolve → JWT (re-mints on 401) → live websocket (self-heartbeat + reconnect) → structure → per-widget pull with cache-warm retry (query + ~900 ms wait so a cold widget's async computation can land), `after` pagination, and a final **reconciliation sweep** (up to 3 rounds) that re-fetches any data widget still empty. It then **normalizes everything into one self-describing document** and writes a single file. Uses only .NET (`System.Net.WebSockets.ClientWebSocket`); no jq/node/python. Verified end-to-end (35-widget report: 32 data / 2 text / 1 page-break, no crash).

```
.\Get-SwydoReport.ps1 -ShareUrl https://swy.do/shares/<KEY> -OutDir .\extractions [-Secret <password>] [-PageSize 500]
```

### 9.1 Output — one timestamped file per run (schemaVersion 2)

Discipline: **one extraction = one file**, never a pile of per-widget fragments. Filename is `<OutDir>\YYYY-MM-DD-HH-MM-SS-<report-name-slug>.json` (local time; slug = report name lowercased, non-alphanumerics → `-`). BOM-less UTF-8. Fixed top-level keys `meta` / `report` / `widgets`; every widget has the same shape:

```jsonc
{
  "meta":   { "tool","schemaVersion":2,"extractedAt"(ISO-8601),"shareUrl","shareKey",
              "reportId","widgetCount","dataWidgets",
              "unitBasis":["google-adwords","facebook-ads"],  // providers whose units were inferred
              "warnings":[] },
  "report": { "name","subtitle","orientation","client","author":{name,email},"team",
              "dateRange","compareDateRange","sections":[{id,name}],"custom" },  // ranges verbatim (§7.4)
  "widgets":[{
      "id","visual","kind":"data|text|pageBreak|manualKpi|unknown","section","title",
      "provider",                       // first part's name (readable)
      "providers":[{ "id","name" }],     // every source.part (blended/multi-source safe)
      // manualKpiOptions present (any kind): "manualKpi":{ "value","compareValue" }
      // kind=="text":  "text" (flattened ProseMirror)
      // kind=="data":  "comparisonFormat","currencyCode",
      //                "target":{ "value" },        // KPI goal, present only when set
      //                "dimensions":[names],
      //                "metrics":[{ "name","id","unit"? }],   // unit: "micros"|"fraction"; absent = render raw
      //                "rows":[{ "kind":"total|subtotal|data",
      //                          "dimensions":{ DimName -> label },
      //                          "metrics":{ MetricName -> { "current","compare" } } }]
      "raw": { ...untouched GraphQL widget node... }   // ALWAYS: lossless escape hatch
  }]
}
```

Design rules that keep it consistent and flexible to the unseen:
- **Faithful, not interpreted.** Values are raw API numbers; the per-metric `unit` is a **scale hint** (§8.1) applied only for verified providers — never a guess that could corrupt an unseen platform's numbers.
- **`raw` escape hatch.** Every widget carries its untouched GraphQL node, so nothing *queried* is ever silently dropped — including the nested `node.rows` (a grouped/drill-down container the normalized view flattens) and object-valued cells. `raw` is post-pagination (holds all merged rows). Still **not** queried (documented boundary): `visualOptions`, `sort`, `style`, `hash`, `edges.cursor`.
- **Shape-based `kind`, open to new visuals.** `TEXT`→text, `PAGE_BREAK`→pageBreak, `source!=null`→data (any viz type), `manualKpiOptions!=null`→manualKpi, else `unknown`. `visual` is preserved verbatim; an unrecognized widget is `unknown` + `raw`, never coerced. `manualKpi` is emitted whenever `manualKpiOptions` is present, independent of `kind`.
- **Collision-safe rows.** Row maps are keyed by display name; on a duplicate (blended table with Google + Facebook "Clicks", or two same-named dims) the key is disambiguated (`"Clicks [facebook-ads:clicks]"`, then `[id #idx]`) so no column is silently overwritten. `raw` remains the ordered-cells source of truth.
- **Object-valued echo metrics** preserved as-is under `current`; a formatter drops non-scalar metric values.
- `warnings[]` lists widgets that never returned rows (cold cache) and any provider outside `unitBasis` (units not inferred).

**Forward-compat contract.** Additive minor changes bump `schemaVersion` additively; only a breaking rename bumps major. Consumers **must ignore** unknown `widget.kind` values and unknown keys, and treat `kind:"unknown"` as "read `raw`."

**Environment caveats (Windows PowerShell 5.1):** functions are defined first with a `-DefineOnly` switch (dot-source for unit tests without running); the script forces arrays, uses UTF-8 for the secret, writes BOM-less UTF-8 via `[IO.File]::WriteAllText`, and serializes at `-Depth 100`. Turning this normalized file into a formatted report (applying `unit` hints + `currencyCode`, dropping echo columns, rendering totals) is a downstream concern.

## 10. curl / bash quickstart

For a report on its **stored** date range (a cache hit), curl alone extracts **everything** — KPIs, tables, and charts — because socketId is unvalidated for cache hits (§7.1). You only need the websocket for a custom/uncached date range.

```bash
KEY="<KEY>"; RID="<REPORT_ID>"
AUTH=$(printf '%s:' "$KEY" | base64 | tr -d '\n')
JWT=$(curl -s https://vesting.swydo.com/jwt/share -H "authorization: Basic $AUTH" | sed -E 's/.*"jwt":"([^"]+)".*/\1/')
# structure (note: source has NO 'name' at report.widgets level)
curl -s https://graphql.swydo.com -H "authorization: Bearer $JWT" -H 'content-type: application/json' \
  -d "{\"query\":\"query{report(id:\\\"$RID\\\"){name dateRange compareDateRange widgets{edges{node{id visual{id}}}}}}\"}"
# any widget (cache path; any socketId string works). Paste report.dateRange/compareDateRange verbatim:
curl -s https://graphql.swydo.com -H "authorization: Bearer $JWT" -H 'content-type: application/json' -d '{
 "query":"query($sid:ID!,$dr:DateRange!,$cp:ComparePeriod!){widget(id:\"<WIDGET_ID>\"){metrics:fields(socketId:$sid,type:METRIC){edges{node{name}}} data(first:500,socketId:$sid,referenceDateRange:$dr,referenceCompareDate:$cp){edges{node}pageInfo{hasNextPage endCursor}}}}",
 "variables":{"sid":"x","dr":<PASTE report.dateRange>,"cp":<PASTE report.compareDateRange>}}'
# paginate: repeat with an extra $after:String var and after:"<endCursor>" while hasNextPage.
```

## 11. Gotchas & troubleshooting

- **`FORBIDDEN` / "Insufficient permissions"** → a selected field is outside the JWT scope; the whole query returns no data. Most common: `source{name}` under `report.widgets` (§6). Bisect against the scope claim; don't re-mint.
- **Table/KPI returns empty `edges`** → cache miss for that `(widget, dateRange)`. Open a real websocket and query with its socketId so the server can push the computed result; then it warms and any socketId works (§7.1). Not caused by widget type.
- **Empty `edges` even with a live socket, persistently** → possible push-only delivery (§7.2, UNVERIFIED) or the socket dropped (idle ~2 s; self-heartbeat).
- **`"structure of the date range object is invalid"` / `invalid_parent_daterange`** → hand-built or under-serialized date range. Pass `report.dateRange`/`compareDateRange` verbatim; in PowerShell use `ConvertTo-Json -Depth 10+` (§7.4).
- **`must have a selection of subfields`** → object field (`visual`, `displayOptions`, `source`, `client`, `author`, `sections`); add a sub-selection (`visual{id}`).
- **`must not have a selection since type WidgetDataRow has no subfields`** → select `data{edges{node}}` bare.
- **HTTP 400 + "introspection is not allowed"** → introspection disabled; use the scope claim.
- **HTTP 401 / UNAUTHENTICATED** → JWT expired (600 s). Re-mint (the script auto re-mints).
- **HTTP 500 on `/jwt/share`** → missing `Authorization` header.
- **`/jwt/guest` "works" but returns nothing** → guest token is report-blind (`access:{}`); use `/jwt/share`.
- **Numbers ~1e6 too big** → micros; ÷1,000,000 (§8.1). Unknown provider → verify the divisor, don't assume.
- **Table truncated at N rows** → you didn't paginate; loop `after` until `hasNextPage:false` (§7.5).
- **WebSocket call throws `AggregateException`/`Task.Wait`** → the socket aborted; wrap receives in try/catch and reconnect (§7.2).
- **`base64 -w0: invalid option`** → BSD/macOS; use `base64 | tr -d '\n'` or `openssl base64 -A`.

## 12. Quick reference

- Hosts: `vesting.swydo.com/jwt/share` · `graphql.swydo.com` · `wss://ws.swydo.com`
- Auth: `Basic base64("<KEY>:<secret>")`; JWT 600 s; scope claim = field whitelist (`<query|mutation>.<Type>.<path>`; report vs widget namespaced separately).
- WS kinds: 1 CONNECTED · 2 SOCKET_ID · 3 PROMISE_UPDATE · 4 PING · 5 PONG · 6 UPDATE. Server sends no PINGs; self-heartbeat.
- Visuals: KPI · TABLE · PIE_CHART · LINE_CHART · COLUMN_CHART · TEXT · PAGE_BREAK. FieldType: METRIC · DIMENSION.
- `data` args: `first`, `after`, `socketId`, `referenceDateRange`, `referenceCompareDate`. socketId unvalidated for cache hits.
- `cells` = D dims (in `dims` order) then metrics (in `metrics` order); totals/subtotals rows at the HEAD, filter by `isTotals`/`isSubtotals`.
- Micros ÷1e6: Google `cost_micros`/`average_cpc`/`average_cpm`/`cost_per_conversion`; Facebook `spend`/`cpc`/`costPerActionType::lead`/`costPerActionType::link_click`. CTR (`ctr`/`ctrLink`) ×100. Other providers: verify before dividing.
- Structure query: `source{id parts{provider{id name}}}` (NO `name` at report.widgets). Per-widget: `source{id name …}` OK.
