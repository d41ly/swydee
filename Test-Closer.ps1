# Offline unit tests for Test-ReportNumbers.ps1 (dot-source with -DefineOnly).
# PS 5.1. Run: powershell -File Test-Closer.ps1
. "$PSScriptRoot\Test-ReportNumbers.ps1" -DefineOnly

$script:pass = 0; $script:fail = 0
function Ok($cond,$name){ if($cond){ $script:pass++ } else { $script:fail++; Write-Host "FAIL: $name" } }
function Eqd($a,$b,$name){ if($null -eq $a){ Ok($false,"$name (got null)"); return }; Ok(([math]::Abs([double]$a-[double]$b) -lt 0.001),"$name (got $a want $b)") }
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

# ---------- Type-FromDisplay ----------
Ok ((Type-FromDisplay '$10.00') -eq 'currency') 'type currency'
Ok ((Type-FromDisplay '14.4%') -eq 'percent') 'type percent'
Ok ((Type-FromDisplay '1,234') -eq 'number') 'type number'
Ok ((Type-FromDisplay '3.5') -eq 'number') 'type ratio-as-number'
Ok ((Type-FromDisplay ([char]0x20AC + '9,500')) -eq 'currency') 'type EUR currency'
Ok ((Type-FromDisplay ([char]0xA3 + '9,500')) -eq 'currency') 'type GBP currency'

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

# ---------- synthetic facts (two ads platforms; comparison on Google, none on FB) ----------
$factsJson = @'
{ "meta": { "hasComparison": true,
    "comparisonCaveats": ["Comparison is Q2 2026 vs Q1 2026, an adjacent quarter-over-quarter. Adjacent-period comparisons can reflect seasonality, not just performance - validate against the same period a year earlier."],
    "providers": [ {"id":"google_ads","name":"Google Ads","category":"ads"}, {"id":"facebook_ads","name":"Facebook / Meta","category":"ads"} ] },
  "platforms": [
    { "id":"google_ads", "name":"Google Ads", "hasComparison": true,
      "headline": {
        "cost": {"metric":"Cost","id":"google_ads:cost_micros","unit":"micros","hasComparison":true,"displayCurrent":"$10,864.72","displayPrevious":"$9,500.00","displayDelta":"+14.4%"},
        "leads": {"metric":"Leads","id":"google_ads:leads","hasComparison":true,"displayCurrent":"432","displayPrevious":"400","displayDelta":"+8.0%"},
        "impr": {"metric":"Impressions","id":"google_ads:impressions","hasComparison":true,"displayCurrent":"15,627","displayPrevious":"14,000","displayDelta":"+11.6%"}
      },
      "breakdowns": [ { "rows": [ { "label":"Brand", "values": {
        "Cost": {"display":"$1,234.00","type":"currency","hasComparison":true,"displayPrevious":"$1,000.00","delta":"+23.4%"},
        "CTR": {"display":"1.1%","type":"percent","hasComparison":false}
      } } ] } ],
      "timeSeries": [] },
    { "id":"facebook_ads", "name":"Facebook / Meta", "hasComparison": false,
      "headline": {
        "spend": {"metric":"Spend","id":"facebook_ads:spend","unit":"micros","hasComparison":false,"displayCurrent":"$555.00","displayPrevious":null,"displayDelta":null},
        "leads": {"metric":"Leads","id":"facebook_ads:leads","hasComparison":false,"displayCurrent":"432","displayPrevious":null,"displayDelta":null}
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
One campaign is eating budget without returning leads. <!-- finding:ANOM_SHARE_MISMATCH#1 -->
The Traffic widget returned no data this quarter. <!-- finding:GAP_WARNINGS#1 -->

## Recommendations
Validate against the same period a year earlier given seasonality. Confirm lead quality downstream before cutting the Display line.
'@

$rOk = Invoke-Closer $reportOk $factsObj
Ok ($rOk.violations.Count -eq 0) "clean report -> 0 violations (got $($rOk.violations.Count): $(( $rOk.violations | ForEach-Object { $_.type }) -join ','))"
Ok ($rOk.measuresChecked -ge 8) "clean report measures counted ($($rOk.measuresChecked))"

# fabricated number
$rFab = Invoke-Closer ($reportOk -replace '\$10,865','$99,999') $factsObj
Ok (HasT $rFab 'untraceable-number') 'fabricated $99,999 -> untraceable'

# platform scoping: FB-only $555.00 cited in the Google section
$rScope = Invoke-Closer ($reportOk -replace 'at a 1.1% CTR\.','at a 1.1% CTR. Also $555.00 spent here.') $factsObj
Ok (HasT $rScope 'untraceable-number') 'FB-only $555 in Google section -> untraceable (scoping)'

# type guard: $1.1 (currency) where facts only have 1.1% (percent)
$rType = Invoke-Closer ($reportOk -replace 'at a 1.1% CTR\.','at $1.1 cpc.') $factsObj
Ok (HasT $rType 'untraceable-number') 'currency $1.1 vs percent 1.1% -> untraceable (type guard)'

# comparison guard: "grew" on FB leads (no comparison data)
$rCmp = Invoke-Closer ($reportOk -replace 'leads were 432','leads grew to 432') $factsObj
Ok (HasT $rCmp 'comparison-without-data') 'comparison verb on no-comparison FB metric -> flagged'
# ...and the same phrase on Google (has comparison) does NOT flag
Ok (-not (HasT $rOk 'comparison-without-data')) 'comparison on Google (has data) -> not flagged'

# surfacing gate: drop a major finding's fid echo
$rSurf = Invoke-Closer ($reportOk -replace '<!-- finding:GAP_WARNINGS#1 -->','') $factsObj
Ok (HasT $rSurf 'unsurfaced-finding') 'missing fid echo -> unsurfaced-finding'

# caveat gate: remove seasonality
$rCav = Invoke-Closer ($reportOk -replace 'seasonality','') $factsObj
Ok (HasT $rCav 'missing-caveat') 'missing seasonality caveat -> flagged'

# downstream gate: surfaced requiresDownstreamData finding but no downstream clause
$rDown = Invoke-Closer ($reportOk -replace 'Confirm lead quality downstream before cutting the Display line\.','Cut the Display line.') $factsObj
Ok (HasT $rDown 'missing-downstream-caveat') 'no downstream clause for reqDownstream finding -> flagged'

# credential leak
$rCred = Invoke-Closer ($reportOk + "`nsee swy.do/shares/ABC123def456") $factsObj
Ok (HasT $rCred 'credential-leak') 'share-key in report -> credential-leak'

# rounding/K tolerance already exercised by clean report (15.6K vs 15,627; $10,865 vs $10,864.72)

Write-Host ''
Write-Host ("Test-Closer: {0} passed, {1} failed." -f $script:pass,$script:fail)
if($script:fail -gt 0){ exit 1 }
