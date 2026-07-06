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
        "rev": {"metric":"Revenue","id":"google_ads:revenue","unit":"micros","type":"currency","hasComparison":false,"displayCurrent":"1,234.00","displayPrevious":null,"displayDelta":null}
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

Write-Host ''
Write-Host ("Test-Closer: {0} passed, {1} failed." -f $script:pass,$script:fail)
if($script:fail -gt 0){ exit 1 }
