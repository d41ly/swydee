# Offline unit tests for Test-ReportNumbers.ps1 (dot-source with -DefineOnly).
# PS 5.1. Run: powershell -File Test-Closer.ps1
. "$PSScriptRoot\Test-ReportNumbers.ps1" -DefineOnly

$script:pass = 0; $script:fail = 0
function Ok($cond,$name){ if($cond){ $script:pass++ } else { $script:fail++; Write-Host "FAIL: $name" } }
function Eqd($a,$b,$name){ if($null -eq $a){ Ok($false,"$name (got null)"); return }; Ok(([math]::Abs([double]$a-[double]$b) -lt 0.0001),"$name (got $a want $b)") }
function HasT($res,$t){ return (@($res.violations | Where-Object { $_.type -eq $t }).Count -gt 0) }
function CountT($res,$t){ return (@($res.violations | Where-Object { $_.type -eq $t }).Count) }
function NMeasures($text){ return (@(Get-MeasureTokens $text)).Count }

# ---------- Normalize-Num ----------
Eqd (Normalize-Num '$10,864.72') 10864.72 'norm currency decimal'
Eqd (Normalize-Num '+14.4%') 14.4 'norm signed percent'
Eqd (Normalize-Num '-2.2%') -2.2 'norm negative percent'
Eqd (Normalize-Num '15.6K') 15600 'norm K suffix'
Eqd (Normalize-Num '$1.2M') 1200000 'norm M suffix'
Eqd (Normalize-Num '3,473,132') 3473132 'norm thousands'
Eqd (Normalize-Num '~$500') 500 'norm tilde strip'
Eqd (Normalize-Num 'about 79%') 79 'norm about-word strip'
Eqd (Normalize-Num '-$2,500.00') -2500 'norm sign before currency symbol'
Eqd (Normalize-Num '$-2,500.00') -2500 'norm sign after currency symbol'
Ok ((Normalize-Num $null) -eq $null) 'norm null -> null'
Ok ((Normalize-Num 'n/a') -eq $null) 'norm non-numeric -> null'

# ---------- Type-FromDisplay / Map-CellType ----------
Ok ((Type-FromDisplay '$10.00') -eq 'currency') 'type currency'
Ok ((Type-FromDisplay '14.4%') -eq 'percent') 'type percent'
Ok ((Type-FromDisplay '1,234') -eq 'number') 'type number'
Ok ((Type-FromDisplay ([char]0x20AC + '9,500')) -eq 'currency') 'type EUR currency'
Ok ((Type-FromDisplay ([char]0xA3 + '9,500')) -eq 'currency') 'type GBP currency'
Ok ((Map-CellType 'currency') -eq 'currency') 'map currency'
Ok ((Map-CellType 'percent') -eq 'percent') 'map percent'
Ok ((Map-CellType 'count') -eq 'number') 'map count -> number'
Ok ((Map-CellType 'ratio') -eq 'number') 'map ratio -> number'
Ok ((Map-CellType 'number') -eq 'number') 'map number'

# ---------- Get-Ulp ----------
Eqd (Get-Ulp '8.0%') 0.1 'ulp 1-decimal'
Eqd (Get-Ulp '8%') 1 'ulp integer'
Eqd (Get-Ulp '$10,864.72') 0.01 'ulp cents'
Eqd (Get-Ulp '3,500,000') 1 'ulp large integer'
Eqd (Get-Ulp '3.5M') 100000 'ulp M with 1 decimal'
Eqd (Get-Ulp '15.6K') 100 'ulp K with 1 decimal'

# ---------- Get-MeasureTokens: exemptions ----------
Ok ((NMeasures 'reported in Q2 2026') -eq 0) 'exempt year+quarter'
Ok ((NMeasures 'ages 25-34 clicked') -eq 0) 'exempt range 25-34'
Ok ((NMeasures 'the 65+ segment') -eq 0) 'exempt bucket 65+'
Ok ((NMeasures '3x ROAS this quarter') -eq 0) 'exempt multiplier 3x'
Ok ((NMeasures 'see the top 5 keywords') -eq 0) 'exempt small bare (top 5)'
Ok ((NMeasures 'across 3 platforms') -eq 0) 'exempt small bare (3)'
Ok ((NMeasures 'in 2026 overall') -eq 0) 'exempt standalone year'
# exempt shapes are magnitude-bounded: large N+/N-M/Nx are measures (smuggling guard)
Ok ((NMeasures 'drove 40000+ conversions') -eq 1) 'large N+ is a measure (not exempt)'
Ok ((NMeasures '25000-30000 clicks') -eq 2) 'large range: BOTH bounds are measures'
Ok ((NMeasures 'in 2024-2025 overall') -eq 0) 'year range stays exempt'
Ok ((NMeasures '12500x return claimed') -eq 1) 'large multiplier is a measure'
# list-size / lookback context integers are not measures
Ok ((NMeasures 'the top 100 keywords') -eq 0) 'context: top 100 exempt'
Ok ((NMeasures 'first 200 clicks reviewed') -eq 0) 'context: first 200 exempt'
Ok ((NMeasures 'over the past 100 days') -eq 0) 'context: past 100 days exempt'
Ok ((NMeasures 'we saw 150 conversions') -eq 1) 'plain 150 is a measure'
# context exemption is word-anchored (\b) and magnitude-capped
Ok ((NMeasures 'Desktop 987654 conversions') -eq 1) 'Desktop suffix is NOT a context word (\b anchor)'
Ok ((NMeasures 'homepage 5000 views') -eq 1) 'homepage suffix is NOT a context word'
Ok ((NMeasures 'the last 45000 conversions') -eq 1) 'large context integer still traces (magnitude cap)'
# signed currency/count tokens capture their sign
$sc1 = @(Get-MeasureTokens 'gained +1,234 net leads'); Ok ($sc1.Count -eq 1 -and $sc1[0].signed) 'bare +1,234 captured as signed'; Eqd $sc1[0].value 1234 'signed +1,234 value'
$sc2 = @(Get-MeasureTokens 'a -$2,500.00 swing'); Ok ($sc2[0].signed) '-$2,500 captured as signed'; Eqd $sc2[0].value -2500 '-$2,500 value'
# a sign is captured ONLY at a sign position - never a joiner/range hyphen (round-4 regression fix)
Ok ((NMeasures '2026-04') -eq 0) 'ISO year-month date is exempt'
Ok ((NMeasures 'launched on 2024-01-15 exactly') -eq 0) 'ISO full date is exempt'
Ok ((NMeasures 'Ad Group-3.75 performed') -eq 0) 'number glued to a label word is not a measure'
Ok ((NMeasures 'Q3 was strong') -eq 0) 'Q3 identifier is not a measure'
Ok ((NMeasures 'campaign ID12345 ran') -eq 0) 'letter-glued digit run leaks no phantom tail (ID12345)'
Ok ((NMeasures 'we drove X5432 leads') -eq 0) 'letter-glued count is not truncated to a fact-matching tail'
Ok ((NMeasures 'leads:432 logged') -eq 1) 'colon-separated number is still a measure'
$rg1 = @(Get-MeasureTokens 'cost ranged $500-$600 total'); Ok ($rg1.Count -eq 2 -and -not $rg1[0].signed -and -not $rg1[1].signed) 'currency range $500-$600 -> two UNSIGNED tokens'
$rg2 = @(Get-MeasureTokens 'a 5%-10% band'); Ok ($rg2.Count -eq 2) 'percent range 5%-10% -> two tokens'
$es1 = @(Get-MeasureTokens 'net +1,234 change'); Ok ($es1[0].signed) 'space-preceded +1,234 is signed'
$es2 = @(Get-MeasureTokens 'delta (-2.2%) noted'); Ok ($es2[0].signed) 'paren-preceded -2.2% is signed'
# ---------- Get-MeasureTokens: measures ----------
Ok ((NMeasures 'spend was $10,864.72 total') -eq 1) 'measure currency'
Ok ((NMeasures 'CTR of 14.4% held') -eq 1) 'measure percent'
Ok ((NMeasures '3,473,132 impressions served') -eq 1) 'measure large count w/ comma'
Ok ((NMeasures 'rate held at 16.4%.') -eq 1) 'measure trailing punctuation'
$tk = @(Get-MeasureTokens 'ended at 16.4%.'); Eqd $tk[0].value 16.4 'trailing punct value'
$tk2 = @(Get-MeasureTokens 'cost $1.2M this year'); Ok ($tk2[0].type -eq 'currency') 'K/M currency type'; Eqd $tk2[0].value 1200000 'K/M currency value'

# ---------- Find-Candidates tolerance (ULP model) ----------
$cInt = [ordered]@{ value=432; type='number'; ulp=1 }
Ok ((@(Find-Candidates ([ordered]@{value=432;type='number';raw='432'}) @($cInt))).Count -eq 1) 'exact integer traces'
Ok ((@(Find-Candidates ([ordered]@{value=433;type='number';raw='433'}) @($cInt))).Count -eq 0) 'off-by-one integer (433 vs 432) does NOT trace'
$cPct = [ordered]@{ value=79.2; type='percent'; ulp=0.1 }
Ok ((@(Find-Candidates ([ordered]@{value=79;type='percent';raw='79%'}) @($cPct))).Count -eq 1) 'coarser prose 79% traces to 79.2%'
Ok ((@(Find-Candidates ([ordered]@{value=79.8;type='percent';raw='79.8%'}) @($cPct))).Count -eq 0) 'equal-precision 79.8% does NOT trace to 79.2%'
$cMoney = [ordered]@{ value=15627; type='number'; ulp=1 }
Ok ((@(Find-Candidates ([ordered]@{value=15600;type='number';raw='15.6K'}) @($cMoney))).Count -eq 1) 'K-rounded 15.6K traces to 15,627'
$cCur = [ordered]@{ value=1234; type='currency'; ulp=0.01 }
Ok ((@(Find-Candidates ([ordered]@{value=1234;type='number';raw='1,234'}) @($cCur))).Count -eq 0) 'count token does NOT match currency candidate (type guard)'
# coarse K/M/B fact must not validate a precise wrong report number (tolerance keyed to the token)
$cCoarse = [ordered]@{ value=1200000; type='number'; ulp=100000 }
Ok ((@(Find-Candidates ([ordered]@{value=1249000;type='number';raw='1,249,000'}) @($cCoarse))).Count -eq 0) 'precise 1,249,000 does NOT trace to coarse 1.2M'
Ok ((@(Find-Candidates ([ordered]@{value=1200000;type='number';raw='1.2M'}) @($cCoarse))).Count -eq 1) 'coarse 1.2M token traces to 1.2M fact'
# signed direction: an explicitly-signed token must match on sign; unsigned matches on magnitude
$cNeg = [ordered]@{ value=-12.5; type='percent'; ulp=0.1 }
Ok ((@(Find-Candidates ([ordered]@{value=12.5;type='percent';raw='+12.5%';signed=$true}) @($cNeg))).Count -eq 0) 'signed +12.5% does NOT trace to -12.5% fact (direction)'
Ok ((@(Find-Candidates ([ordered]@{value=12.5;type='percent';raw='12.5%';signed=$false}) @($cNeg))).Count -eq 1) 'unsigned 12.5% traces to -12.5% (prose drops the sign)'
$cNegN = [ordered]@{ value=-1234; type='number'; ulp=1 }
Ok ((@(Find-Candidates ([ordered]@{value=1234;type='number';raw='+1,234';signed=$true}) @($cNegN))).Count -eq 0) 'signed +1,234 does NOT trace a -1,234 count fact (direction)'

# ---------- synthetic facts (two ads platforms; comparison on Google, none on FB) ----------
$factsJson = @'
{ "meta": { "hasComparison": true,
    "comparisonCaveats": [ {"id":"seasonality","text":"Comparison is Q2 2026 vs Q1 2026, an adjacent quarter-over-quarter. Adjacent-period comparisons can reflect seasonality, not just performance - validate against the same period a year earlier."} ],
    "providers": [ {"id":"google_ads","name":"Google Ads","category":"ads"}, {"id":"facebook_ads","name":"Facebook / Meta","category":"ads"} ] },
  "platforms": [
    { "id":"google_ads", "name":"Google Ads", "hasComparison": true,
      "headline": {
        "cost": {"metric":"Cost","id":"google_ads:cost_micros","unit":"micros","type":"currency","hasComparison":true,"displayCurrent":"$10,864.72","displayPrevious":"$9,500.00","displayDelta":"+14.4%"},
        "leads": {"metric":"Leads","id":"google_ads:leads","type":"number","hasComparison":true,"displayCurrent":"432","displayPrevious":"400","displayDelta":"+8.0%"},
        "impr": {"metric":"Impressions","id":"google_ads:impressions","type":"number","hasComparison":true,"displayCurrent":"15,627","displayPrevious":"14,000","displayDelta":"+11.6%"},
        "rev": {"metric":"Revenue","id":"google_ads:revenue","unit":"micros","type":"currency","hasComparison":false,"displayCurrent":"1,234.00","displayPrevious":null,"displayDelta":null},
        "cpl": {"metric":"CPL","id":"google_ads:cpl","type":"currency","hasComparison":false,"displayCurrent":"$25.15","displayPrevious":null,"displayDelta":null}
      },
      "breakdowns": [ { "rows": [ { "label":"Brand", "values": {
        "Cost": {"display":"$1,234.00","type":"currency","hasComparison":true,"displayPrevious":"$1,000.00","delta":"+23.4%"},
        "CTR": {"display":"1.1%","type":"percent","hasComparison":false}
      } } ] } ],
      "timeSeries": [] },
    { "id":"facebook_ads", "name":"Facebook / Meta", "hasComparison": false,
      "headline": {
        "spend": {"metric":"Spend","id":"facebook_ads:spend","unit":"micros","type":"currency","hasComparison":false,"displayCurrent":"$555.00","displayPrevious":null,"displayDelta":null},
        "leads": {"metric":"Leads","id":"facebook_ads:leads","type":"number","hasComparison":false,"displayCurrent":"432","displayPrevious":null,"displayDelta":null}
      },
      "breakdowns": [], "timeSeries": [] }
  ],
  "findings": {
    "wins": [], "losses": [],
    "anomalies": [ {"ruleId":"ANOM_SHARE_MISMATCH","severity":"major","platform":"Google Ads","requiresDownstreamData":true,"statement":"Google Ads: 'Display' is 40% of cost but only 5% of leads","evidence":{"effortShare":"40%","resultShare":"5%"},"fid":"ANOM_SHARE_MISMATCH#1"} ],
    "discrepancies": [],
    "dataGaps": [ {"ruleId":"GAP_WARNINGS","severity":"major","statement":"widget Traffic returned no data","fid":"GAP_WARNINGS#1"} ]
  } }
'@
# $factsObj, not $facts: dot-sourcing the closer brings its [string]-typed $Facts param into scope,
# and $facts would collide (case-insensitive) and coerce the parsed object back to a string.
$factsObj = $factsJson | ConvertFrom-Json

$reportOk = @'
Here is how the quarter landed.

## Google Ads
<!-- platform:google_ads -->
Spend was $10,865 (+14.4%), up from $9,500.00. Leads grew to 432 (+8.0%) on 15.6K impressions. Brand cost $1,234.00 (+23.4%) at a 1.1% CTR.

## Facebook / Meta
<!-- platform:facebook_ads -->
Meta spend was $555.00 and leads were 432.

## Analytical insights
Display used 40% of spend for only 5% of leads. <!-- finding:ANOM_SHARE_MISMATCH#1 -->

The Traffic widget returned no data this quarter. <!-- finding:GAP_WARNINGS#1 -->

## Recommendations
Given seasonality, validate against the same period last year. <!-- caveat:seasonality -->
Confirm lead quality downstream before cutting the Display line.
'@

$rOk = Invoke-Closer $reportOk $factsObj
Ok ($rOk.violations.Count -eq 0) "clean report -> 0 violations (got $($rOk.violations.Count): $(( $rOk.violations | ForEach-Object { $_.type }) -join ','))"
Ok ($rOk.measuresChecked -ge 10) "clean report measures counted ($($rOk.measuresChecked))"

# fabricated number
$rFab = Invoke-Closer ($reportOk -replace '\$10,865','$99,999') $factsObj
Ok (HasT $rFab 'untraceable-number') 'fabricated $99,999 -> untraceable'

# tightened percent tolerance: 8.4% must NOT trace to 8.0%
$rTol = Invoke-Closer ($reportOk -replace '\(\+8\.0%\)','(+8.4%)') $factsObj
Ok (HasT $rTol 'untraceable-number') 'percent 8.4 does not trace to 8.0 (ULP tolerance)'

# platform scoping: FB-only $555.00 cited in the Google section
$rScope = Invoke-Closer ($reportOk -replace 'at a 1.1% CTR\.','at a 1.1% CTR. Also $555.00 spent here.') $factsObj
Ok (HasT $rScope 'untraceable-number') 'FB-only $555 in Google section -> untraceable (scoping)'

# type guard: $1.1 (currency) where facts only have 1.1% (percent)
$rType = Invoke-Closer ($reportOk -replace 'at a 1.1% CTR\.','at $1.1 cpc.') $factsObj
Ok (HasT $rType 'untraceable-number') 'currency $1.1 vs percent 1.1% -> untraceable (type guard)'

# M1: count token must NOT match a symbol-less currency fact (type comes from the cell field)
$rM1 = Invoke-Closer ($reportOk -replace 'at a 1.1% CTR\.','at a 1.1% CTR. We logged 1,234 signups.') $factsObj
Ok (HasT $rM1 'untraceable-number') 'count 1,234 does not match symbol-less currency 1,234.00 (cell-type guard)'

# C3: a finding-only number (40%) cited in a NON-fid paragraph must be untraceable (no haystack)
$rC3 = Invoke-Closer ($reportOk -replace 'at a 1.1% CTR\.','at a 1.1% CTR. Display took 40% of budget.') $factsObj
Ok (HasT $rC3 'untraceable-number') 'finding-only 40% in a non-fid paragraph -> untraceable (C3)'
# ...and the clean report cites 40%/5% WITH the fid, so it traces (baked into $rOk = 0 violations)

# comparison guard: "grew" on FB leads (no comparison data)
$rCmp = Invoke-Closer ($reportOk -replace 'leads were 432','leads grew to 432') $factsObj
Ok (HasT $rCmp 'comparison-without-data') 'comparison verb on no-comparison FB metric -> flagged'
Ok (-not (HasT $rOk 'comparison-without-data')) 'comparison on Google (has data) -> not flagged'

# C1: two platform anchors in one section
$rAmb = Invoke-Closer ($reportOk -replace '<!-- platform:facebook_ads -->','<!-- platform:facebook_ads --> <!-- platform:google_ads -->') $factsObj
Ok (HasT $rAmb 'ambiguous-platform-anchor') 'two platform anchors in one section -> flagged'

# C2: unknown/typo platform anchor -> empty scope + flag (not global fallback)
$rUnk = Invoke-Closer ($reportOk -replace '<!-- platform:facebook_ads -->','<!-- platform:tiktok_ads -->') $factsObj
Ok (HasT $rUnk 'unknown-platform-anchor') 'unknown platform anchor -> flagged'
Ok (HasT $rUnk 'untraceable-number') 'unknown anchor uses empty scope -> section numbers untraceable'

# surfacing gate: drop a major finding's fid echo
$rSurf = Invoke-Closer ($reportOk -replace '<!-- finding:GAP_WARNINGS#1 -->','') $factsObj
Ok (HasT $rSurf 'unsurfaced-finding') 'missing fid echo -> unsurfaced-finding'

# caveat gate: remove the caveat anchor
$rCav = Invoke-Closer ($reportOk -replace '<!-- caveat:seasonality -->','') $factsObj
Ok (HasT $rCav 'missing-caveat') 'missing caveat anchor -> flagged'

# downstream gate: surfaced requiresDownstreamData finding but no downstream clause
$rDown = Invoke-Closer ($reportOk -replace 'Confirm lead quality downstream before cutting the Display line\.','Cut the Display line.') $factsObj
Ok (HasT $rDown 'missing-downstream-caveat') 'no downstream clause for reqDownstream finding -> flagged'

# credential leak (lowercase and uppercase both caught)
$rCred = Invoke-Closer ($reportOk + "`nsee swy.do/shares/ABC123def456") $factsObj
Ok (HasT $rCred 'credential-leak') 'share-key in report -> credential-leak'
$rCredU = Invoke-Closer ($reportOk + "`nSWY.DO/SHARES/ABC123DEF456") $factsObj
Ok (HasT $rCredU 'credential-leak') 'UPPERCASE share-key -> credential-leak (case-insensitive)'

# CRITICAL leak fixed: a finding number on a SIBLING line (no fid) must not borrow the fid's numbers
$leakReport = @'
## Analytical insights
Spend efficiency was 40% overall this quarter.
Display had a share anomaly worth noting. <!-- finding:ANOM_SHARE_MISMATCH#1 -->
'@
$rLeak = Invoke-Closer $leakReport $factsObj
Ok (HasT $rLeak 'untraceable-number') 'finding number on a sibling line (no fid) -> untraceable (line scope, not paragraph)'
$rNoLeak = Invoke-Closer "## Analytical insights`nDisplay ran at 40% of spend for only 5% of leads. <!-- finding:ANOM_SHARE_MISMATCH#1 -->`n" $factsObj
Ok (-not (HasT $rNoLeak 'untraceable-number')) 'finding numbers on the fid line -> trace'

# platform scope must not be laundered to global when the anchor is on the heading line, in a
# subsection, or in a "## Platform - subtopic" sibling (a FB-only $555 must stay untraceable there)
$vHdr = @'
## Google Ads <!-- platform:google_ads -->
We also spent $555.00 here.
'@
Ok (HasT (Invoke-Closer $vHdr $factsObj) 'untraceable-number') 'heading-line anchor scopes: FB-only $555 untraceable under Google'
$vSub = @'
## Google Ads
<!-- platform:google_ads -->
Cost was $10,864.72.

### Deeper cut
We also spent $555.00 here.
'@
Ok (HasT (Invoke-Closer $vSub $factsObj) 'untraceable-number') 'subsection inherits Google scope: FB-only $555 untraceable'
$vSib = @'
## Google Ads
<!-- platform:google_ads -->
Cost was $10,864.72.

## Google Ads - Keywords
We also spent $555.00 here.
'@
Ok (HasT (Invoke-Closer $vSib $factsObj) 'untraceable-number') 'sibling "Google Ads - Keywords" name-resolves to Google: FB-only $555 untraceable'
$vGen = @'
## Summary
Across accounts, Meta spend was $555.00 while Google cost $10,864.72.
'@
Ok (-not (HasT (Invoke-Closer $vGen $factsObj) 'untraceable-number')) 'general (non-platform) section uses global scope: cross-platform numbers trace'
# comparison header stays global (does not narrow to the one platform it names)
$vCmp = @'
## How Google Ads compares to the rest
Google cost $10,864.72 but Meta only spent $555.00.
'@
Ok (-not (HasT (Invoke-Closer $vCmp $factsObj) 'untraceable-number')) 'comparison header stays global (cross-platform numbers trace)'
# ISO date labels in a platform section are not flagged
$vDate = @'
## Google Ads
<!-- platform:google_ads -->
Data covers 2026-04 through 2026-06.
'@
Ok (-not (HasT (Invoke-Closer $vDate $factsObj) 'untraceable-number')) 'ISO date labels are not flagged untraceable'
# nested platform names (Google / Google Ads): anchorless "## Google Ads" scopes to Ads, not global
$fNest = '{ "meta":{}, "platforms":[ {"id":"ga4","name":"Google","hasComparison":false,"headline":{"u":{"type":"number","hasComparison":false,"displayCurrent":"9,001"}},"breakdowns":[],"timeSeries":[]}, {"id":"gads","name":"Google Ads","hasComparison":false,"headline":{"c":{"type":"currency","hasComparison":false,"displayCurrent":"$10,864.72"}},"breakdowns":[],"timeSeries":[]} ], "findings":{"wins":[],"losses":[],"anomalies":[],"discrepancies":[],"dataGaps":[]} }' | ConvertFrom-Json
$vNest = @'
## Google Ads
We drove 9,001 conversions.
'@
Ok (HasT (Invoke-Closer $vNest $fNest) 'untraceable-number') 'nested names: "## Google Ads" scopes to Ads (GA4-only 9,001 untraceable), not global'
# short platform name ("Meta") must not match inside "Metadata" -> section stays global, Google traces
$fMeta = '{ "meta":{}, "platforms":[ {"id":"meta_ads","name":"Meta","hasComparison":false,"headline":{"s":{"type":"currency","hasComparison":false,"displayCurrent":"$555.00"}},"breakdowns":[],"timeSeries":[]}, {"id":"gads","name":"Google Ads","hasComparison":false,"headline":{"c":{"type":"currency","hasComparison":false,"displayCurrent":"$10,864.72"}},"breakdowns":[],"timeSeries":[]} ], "findings":{"wins":[],"losses":[],"anomalies":[],"discrepancies":[],"dataGaps":[]} }' | ConvertFrom-Json
$vMeta = @'
## Metadata quality review
Google cost was $10,864.72 in this review.
'@
Ok (-not (HasT (Invoke-Closer $vMeta $fMeta) 'untraceable-number')) 'short name "Meta" does not match inside "Metadata" (Google number traces)'

# comparison guard does not taint an unrelated no-comparison metric across a clause break
$clauseReport = @'
## Google Ads
<!-- platform:google_ads -->
Spend rose to $10,864.72, giving a $25.15 CPL.
'@
$rClause = Invoke-Closer $clauseReport $factsObj
Ok (-not (HasT $rClause 'comparison-without-data')) 'comparison verb does not taint a later no-comparison metric across a comma'

# surfacing gate: delimited anchor - ANOM_X#1 is NOT masked by an echoed ANOM_X#10
$fCollide = '{ "meta":{}, "platforms":[], "findings":{ "wins":[],"losses":[],"discrepancies":[],"dataGaps":[], "anomalies":[ {"ruleId":"ANOM_X","severity":"major","fid":"ANOM_X#1","statement":"first"},{"ruleId":"ANOM_X","severity":"major","fid":"ANOM_X#10","statement":"tenth"} ] } }' | ConvertFrom-Json
$rCollide = Invoke-Closer "## Insights`nThe tenth issue only. <!-- finding:ANOM_X#10 -->`n" $fCollide
Ok (HasT $rCollide 'unsurfaced-finding') 'ANOM_X#1 not masked by echoed ANOM_X#10 (delimited anchor)'

# caveat gate: delimited anchor - s1 is NOT masked by an echoed s10
$fCav2 = '{ "meta":{ "comparisonCaveats":[ {"id":"s1","text":"a"},{"id":"s10","text":"b"} ] }, "platforms":[], "findings":{"wins":[],"losses":[],"anomalies":[],"discrepancies":[],"dataGaps":[]} }' | ConvertFrom-Json
$rCav2 = Invoke-Closer "## Notes`nSee note. <!-- caveat:s10 -->`n" $fCav2
Ok (HasT $rCav2 'missing-caveat') 's1 caveat not masked by echoed s10 (delimited anchor)'

# Strip-Anchors: the published client copy has no machine anchors but keeps prose + numbers verbatim
$anchoredRep = @'
## Google Ads
<!-- platform:google-adwords -->

Impressions were 95,302 in Q2 against 53,398 in Q1 (a whopping increase of 78.5%). <!-- finding:WIN#10 -->

Given seasonality, validate against last year. <!-- caveat:seasonality -->
'@
$clean = Strip-Anchors $anchoredRep
Ok (-not ($clean -match '<!--')) 'Strip-Anchors removes every HTML anchor comment'
Ok ($clean -match 'Impressions were 95,302 in Q2 against 53,398 in Q1 \(a whopping increase of 78\.5%\)\.') 'Strip-Anchors keeps prose + numbers verbatim'
Ok (-not ($clean -match '\n{3,}')) 'Strip-Anchors collapses the blank runs left by anchor-only lines'
Ok (-not ($clean -match '[ \t]+\n')) 'Strip-Anchors trims trailing whitespace left by inline anchors'

Write-Host ''
Write-Host ("Test-Closer: {0} passed, {1} failed." -f $script:pass,$script:fail)
if($script:fail -gt 0){ exit 1 }
