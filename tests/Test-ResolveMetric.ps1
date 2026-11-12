# Offline unit tests for Resolve-SwydoMetric.ps1 (derived metrics) and the closer's derived-metric
# checks in Test-ReportNumbers.ps1. Dot-sources both with -DefineOnly. PS 5.1.
# Run: powershell -File tests\Test-ResolveMetric.ps1
# All figures below are synthetic - no client data.
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\..\skill\scripts\Resolve-SwydoMetric.ps1" -DefineOnly
. "$PSScriptRoot\..\skill\scripts\Test-ReportNumbers.ps1" -DefineOnly
$script:ResolveTool = "$PSScriptRoot\..\skill\scripts\Resolve-SwydoMetric.ps1"
$script:AnalyzeSrc  = "$PSScriptRoot\..\skill\scripts\Analyze-SwydoReport.ps1"

$script:pass = 0; $script:fail = 0
function Ok($cond,$name){ if($cond){ $script:pass++ } else { $script:fail++; Write-Host "FAIL: $name" } }
function Eqd($a,$b,$name){ if($null -eq $a){ Ok $false "$name (got null)"; return }; Ok ([math]::Abs([double]$a-[double]$b) -lt 0.0001) "$name (got $a want $b)" }
function Eqs($a,$b,$name){ Ok ([string]$a -ceq [string]$b) "$name (got '$a' want '$b')" }
function HasT($res,$t){ return (@($res.violations | Where-Object { $_.type -eq $t }).Count -gt 0) }
function Viol($res){ return (@($res.violations | ForEach-Object { $_.type + ':' + $_.detail }) -join ' | ') }

# ---------- synthetic facts ----------
# Cost $2,000.00 (prev $1,800.00); Conversions 400.43 (prev 500.19); Clicks 1,000 (prev 900).
# By 'Conversion action name': Directions 300/380 (whole numbers, so exact), Calls 80.0/90.0,
# Form 20.4/30.2 (rounded to one decimal) -> a partition of the account Conversions.
# A month-bucketed widget shows the non-Directions subset (100.4) with a row-aligned previous of 4.0.
$script:FactsJson = @'
{
  "meta": {
    "tool": "Analyze-SwydoReport.ps1", "factsVersion": 4,
    "client": "Synthetic Co", "currentPeriod": "2026-10-01..2026-10-31", "previousPeriod": "2026-08-31..2026-09-30",
    "compareBasis": "computed", "hasComparison": true,
    "periodResolved": { "current": { "start": "2026-10-01", "end": "2026-10-31" }, "previous": { "start": "2026-08-31", "end": "2026-09-30" } },
    "annotations": [ { "aid": "ANN#1", "text": "Exclude Directions from lead cost." } ],
    "comparisonCaveats": [], "providers": [ { "id": "google-adwords", "name": "Google Ads", "category": "ads" } ],
    "extractionComplete": true, "incompleteWidgets": []
  },
  "platforms": [ {
    "id": "google-adwords", "name": "Google Ads", "category": "ads", "hasComparison": true,
    "headline": {
      "hasComparison": true,
      "g:cost": { "metric": "Cost", "id": "g:cost", "unit": "micros", "type": "currency", "currency": "USD",
        "current": 2000000000, "previous": 1800000000, "deltaPct": 11.1, "hasComparison": true,
        "displayCurrent": "$2,000.00", "displayPrevious": "$1,800.00", "displayDelta": "+11.1%",
        "canonical": { "display": "$2,000.00", "sourceWidgetId": "wCost", "scope": "account", "period": "2026-10-01..2026-10-31" } },
      "g:conv": { "metric": "Conversions", "id": "g:conv", "unit": null, "type": "number", "currency": "USD",
        "current": 400.43, "previous": 500.19, "deltaPct": -19.9, "hasComparison": true,
        "displayCurrent": "400.4", "displayPrevious": "500.2", "displayDelta": "-19.9%",
        "canonical": { "display": "400.4", "sourceWidgetId": "wConv", "scope": "account", "period": "2026-10-01..2026-10-31" } },
      "g:cpa": { "metric": "Cost / conversion", "id": "g:cpa", "unit": "micros", "type": "currency", "currency": "USD",
        "current": 4994630, "previous": 3598630, "deltaPct": 38.8, "hasComparison": true,
        "displayCurrent": "$4.99", "displayPrevious": "$3.60", "displayDelta": "+38.8%",
        "canonical": { "display": "$4.99", "sourceWidgetId": "wCpa", "scope": "account", "period": "2026-10-01..2026-10-31" } },
      "g:clicks": { "metric": "Clicks", "id": "g:clicks", "unit": null, "type": "number", "currency": "USD",
        "current": 1000, "previous": 900, "deltaPct": 11.1, "hasComparison": true,
        "displayCurrent": "1,000", "displayPrevious": "900", "displayDelta": "+11.1%",
        "canonical": { "display": "1,000", "sourceWidgetId": "wClk", "scope": "account", "period": "2026-10-01..2026-10-31" } }
    },
    "metrics": {
      "g:cost": { "id": "g:cost", "aggClass": "sum" }, "g:conv": { "id": "g:conv", "aggClass": "sum" },
      "g:cpa": { "id": "g:cpa", "aggClass": "ratio-recompute" }, "g:clicks": { "id": "g:clicks", "aggClass": "sum" }
    },
    "breakdowns": [
      { "widgetId": "wAct", "dimensions": [ "Conversion action name" ], "metricNames": [ "Conversions" ], "metricIds": [ "g:conv" ],
        "rowCount": 3, "shown": 3, "rows": [
          { "label": "Directions", "values": { "Conversions": { "display": "300", "type": "number", "hasComparison": true, "displayPrevious": "380", "delta": "-21.1%" } } },
          { "label": "Calls", "values": { "Conversions": { "display": "80.0", "type": "number", "hasComparison": true, "displayPrevious": "90.0", "delta": "-11.1%" } } },
          { "label": "Form", "values": { "Conversions": { "display": "20.4", "type": "number", "hasComparison": true, "displayPrevious": "30.2", "delta": "-32.5%" } } } ] },
      { "widgetId": "wMonthAll", "dimensions": [ "Month", "Conversion action name" ], "metricNames": [ "Conversions" ], "metricIds": [ "g:conv" ],
        "rowCount": 1, "shown": 1, "rows": [
          { "label": "2026-10", "values": { "Conversions": { "display": "400.4", "type": "number", "hasComparison": true, "displayPrevious": "12.0", "delta": "+3236.7%" } } } ] },
      { "widgetId": "wMonthSub", "dimensions": [ "Month", "Conversion action name" ], "metricNames": [ "Conversions" ], "metricIds": [ "g:conv" ],
        "rowCount": 1, "shown": 1, "rows": [
          { "label": "2026-10", "values": { "Conversions": { "display": "100.4", "type": "number", "hasComparison": true, "displayPrevious": "4.0", "delta": "+2410.0%" } } } ] }
    ]
  } ],
  "findings": { "wins": [], "losses": [], "anomalies": [], "discrepancies": [], "dataGaps": [] }
}
'@
function NewFacts { return ($script:FactsJson | ConvertFrom-Json) }
function NewReq($json){ return ($json | ConvertFrom-Json) }
function Rows($f){ return $f.platforms[0].breakdowns[0].rows }
$script:ReqCpl = @'
{ "id": "cpl_ex_directions", "label": "Cost / conversion excluding Directions", "op": "ratio",
  "terms": [ { "metric": "Cost" },
             { "metric": "Conversions", "filter": { "dimension": "Conversion action name", "exclude": [ "Directions" ] } } ],
  "alongside": "Cost / conversion", "source": "annotation:ANN#1" }
'@
$script:ReqForm = @'
{ "id": "cpl_form", "label": "Cost per form lead", "op": "ratio",
  "terms": [ { "metric": "Cost" },
             { "metric": "Conversions", "filter": { "dimension": "Conversion action name", "include": [ "Form" ] } } ] }
'@

# ---------- number helpers ----------
Eqd (Get-DmDisplayNumber '$4,125.03') 4125.03 'display number: currency'
Eqd (Get-DmDisplayNumber '97.6') 97.6 'display number: decimal'
Eqd (Get-DmDisplayNumber '-12.5%') -12.5 'display number: negative percent'
Eqd (Get-DmDisplayNumber 'CA$1,234.50') 1234.5 'display number: prefixed currency symbol'
Eqd (Get-DmDisplayNumber '-$3.50') -3.5 'display number: negative currency'
Ok ($null -eq (Get-DmDisplayNumber 'n/a')) 'display number: non-numeric -> null'
Ok ($null -eq (Get-DmDisplayNumber '1.234,56')) 'display number: another culture''s format is NOT read (would be off by 1000x)'
Ok ($null -eq (Get-DmDisplayNumber '1.2K')) 'display number: abbreviated form is not read'
Ok ($null -eq (Get-DmDisplayNumber '(5)')) 'display number: accounting negative is not read'
Ok ($null -eq (Get-DmDisplayNumber '1e3')) 'display number: exponent form is not read'
Ok ((Get-DmDisplayDecimals '82.0') -eq 1) 'decimals: 82.0 -> 1'
Ok ((Get-DmDisplayDecimals '517') -eq 0) 'decimals: 517 -> 0'
Eqs (Format-DmValue 42.2677 'currency' 'USD' 2) '$42.27' 'format currency USD'
Eqs (Format-DmValue -3.5 'currency' 'USD' 2) '-$3.50' 'format negative currency'
Eqs (Format-DmValue 0.1234 'percent' $null 1) '12.3%' 'format percent'
Eqs (Format-DmValue 1234.56 'number' $null 1) '1,234.6' 'format number 1dp'
Ok ((Get-DmMonthsSpanned '2026-08-31' '2026-09-30') -eq 2) 'months spanned: Aug 31..Sep 30 = 2'
Ok ((Get-DmMonthsSpanned '2026-10-01' '2026-10-31') -eq 1) 'months spanned: October = 1'
Ok ((Get-DmMonthsSpanned '2025-12-01' '2026-02-28') -eq 3) 'months spanned across a year end'
$qa = New-DmQty 10 12 0 $false; $qb = New-DmQty 2 4 0 $false
$qd = Div-DmQty $qa $qb
Eqd $qd.lo 2.5 'interval division: low = lo/hi'; Eqd $qd.hi 6 'interval division: high = hi/lo'
Ok ($null -eq (Div-DmQty $qa (New-DmQty 0 1 0 $false))) 'division by an interval touching zero -> null'
Eqd $qd.mid (11/3) 'interval division: point value = mid/mid, not the midpoint of the bounds'
$qSmall = Div-DmQty (New-DmQty 15.19 15.19 2 $true) (New-DmQty 1.5 2.5 0 $false)
Eqd $qSmall.mid 7.595 'small rounded denominator: 15.19 / 2 = 7.595 (bounds midpoint would be 8.10)'
Ok (Test-DmOverlap (New-DmQty 1 2 0 $false) (New-DmQty 2 3 0 $false)) 'touching intervals overlap'
Ok (-not (Test-DmOverlap (New-DmQty 1 2 0 $false) (New-DmQty 2.1 3 0 $false))) 'disjoint intervals do not overlap'
# the delta is formatted in the invariant culture whatever the caller's culture is
$prevCulture = [Threading.Thread]::CurrentThread.CurrentCulture
try { [Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]'de-DE'; Eqs (Format-DmDelta 33.04) '+33.0%' 'delta: invariant under de-DE'; Eqs (Format-DmDelta -7.26) '-7.3%' 'delta: negative' }
finally { [Threading.Thread]::CurrentThread.CurrentCulture = $prevCulture }

# ---------- a cell without decimals is exact; the convention it relies on is pinned ----------
$cInt = Get-DmCellQty ([pscustomobject]@{ display='517' }) 'current' $null
Ok ($cInt.lo -eq 517 -and $cInt.hi -eq 517 -and $cInt.exact) 'cell: a count shown as 517 is exactly 517'
$cBig = Get-DmCellQty ([pscustomobject]@{ display='1,234' }) 'current' $null
Ok ($cBig.lo -eq 1234 -and $cBig.hi -eq 1234) 'cell: thousands separator, still exact'
$cDec = Get-DmCellQty ([pscustomobject]@{ display='82.0' }) 'current' $null
Eqd $cDec.lo 81.95 'cell: 82.0 is known to half its last digit (low)'; Eqd $cDec.hi 82.05 'cell: 82.0 (high)'
$cMic = Get-DmCellQty ([pscustomobject]@{ display='$5' }) 'current' 'micros'
Ok ($cMic.lo -lt 5 -and $cMic.hi -gt 5) 'cell: a currency display is never treated as exact'
Ok ($null -eq (Get-DmCellQty ([pscustomobject]@{ display='1.234,5' }) 'current' $null)) 'cell: an unreadable display is not a quantity'
$sumBad = Get-DmRowsSum @([pscustomobject]@{ values=[pscustomobject]@{ M=[pscustomobject]@{ display='12,5' } } }) 'M' 'current' $null
Ok ($sumBad.unreadable -eq 1 -and $sumBad.cells -eq 0) 'rows sum: an unreadable cell is counted, not silently zero'
Ok ($null -eq (Test-DmFormatConvention)) 'canary: the analyzer formats counts the way exactness assumes'
# drift guards: the analyzer's number format and facts version, against what this tool was verified for
Eqs (Format-Metric 'm' $null 2 $null) '2' 'drift: an integer count prints without decimals'
Eqs (Format-Metric 'm' $null 2.04 $null) '2.0' 'drift: a NON-integer count always prints a decimal point'
Ok ((Format-Metric 'm' 'micros' 2000000 'USD') -match '\.\d\d$') 'drift: micros always print two decimals'
Ok ((Format-Metric 'm' 'fraction' 0.5 $null) -match '\.\d%$') 'drift: fractions always print one decimal and a percent sign'
$fvm = [regex]::Match([IO.File]::ReadAllText($script:AnalyzeSrc),'factsVersion\s*=\s*(\d+)')
Ok ($fvm.Success -and ($script:DmFactsVersions -contains [int]$fvm.Groups[1].Value)) "drift: the analyzer's factsVersion ($($fvm.Groups[1].Value)) is in the resolver's verified set - re-verify exactness before adding a version"

# ---------- request validation ----------
function Problems($json){ return @(Test-DmRequest (NewReq $json)) }
Ok ((Problems $script:ReqCpl).Count -eq 0) 'well-formed request has no problems'
Ok ((Problems '{ "id": "Bad Id", "label": "x", "op": "ratio", "terms": [ {"metric":"a"}, {"metric":"b"} ] }').Count -ge 1) 'bad id rejected'
Ok ((Problems '{ "id": "CPL", "label": "x", "op": "sum", "terms": [ {"metric":"a"} ] }').Count -ge 1) 'upper-case id rejected (the anchor is case-sensitive text)'
Ok (@(Test-DmRequest ([pscustomobject]@{ id="cpl`n"; label='x'; op='sum'; terms=@([pscustomobject]@{ metric='a' }) })).Count -ge 1) 'id with a trailing newline rejected'
Ok ((Problems '{ "id": "a", "label": "x", "op": "ratio", "terms": [ {"metric":"a"} ] }').Count -ge 1) 'ratio with one term rejected'
Ok ((Problems '{ "id": "a", "label": "x", "op": "multiply", "terms": [ {"metric":"a"}, {"metric":"b"} ] }').Count -ge 1) 'unknown op rejected'
Ok ((Problems '{ "id": "a", "label": "x", "op": "sum", "terms": [ {"metric":"a", "filter": {"dimension":"d", "include":["x"], "exclude":["y"]}} ] }').Count -ge 1) 'include AND exclude rejected'
Ok ((Problems '{ "id": "a", "label": "x", "op": "sum", "terms": [ {"metric":"a", "filter": {"dimension":"d"}} ] }').Count -ge 1) 'filter with neither include nor exclude rejected'
Ok ((Problems '{ "id": "a", "op": "sum", "terms": [ {"metric":"a"} ] }').Count -ge 1) 'missing label rejected'
Ok ((Problems '{ "id": "a", "label": "x", "op": "sum", "terms": [ {"metric":"a", "filter": {"dimension":"d", "include":[0]}} ] }').Count -eq 0) 'a numeric label 0 is a valid label'
Ok ((Problems '{ "id": "a", "label": "x", "op": "sum", "terms": [ {"metric":"a", "filter": {"dimension":"d", "include":[true]}} ] }').Count -ge 1) 'a boolean label rejected'
Ok ((Problems '{ "id": "a", "label": "x", "op": "sum", "terms": [ {"metric":"a", "filter": {"dimension":"d", "include":["Calls","calls "]}} ] }').Count -ge 1) 'the same row named twice rejected'
Ok ((Problems '{ "id": "a", "label": "x --> y", "op": "sum", "terms": [ {"metric":"a"} ] }').Count -ge 1) 'a comment delimiter in request text rejected'
Ok ((Problems '{ "id": "a", "label": "x", "op": "sum", "decimals": 9, "terms": [ {"metric":"a"} ] }').Count -ge 1) 'decimals out of range rejected'
Ok (@(Get-DmRequests (NewReq ('{ "requests": [ ' + $script:ReqCpl + ' ] }'))).Count -eq 1) 'requests wrapper unwrapped'
Ok (@(Get-DmRequests (NewReq $script:ReqCpl)).Count -eq 1) 'single object accepted'
Ok (@(Get-DmRequests (NewReq ('[ ' + $script:ReqCpl + ', ' + $script:ReqCpl + ' ]'))).Count -eq 2) 'array accepted'
Eqs ((Get-DmLabels @(0,' Calls ',$null,'')) -join '|') '0|Calls' 'labels: 0 kept, blanks dropped, trimmed'

# ---------- the headline case: ratio with an excluded whole-number row -> exact ----------
$e = Resolve-DmRequest (NewFacts) (NewReq $script:ReqCpl)
Eqs $e.status 'resolved' 'cpl: resolved'
Ok ($e.v -eq 2) 'cpl: entry carries the tool version'
Ok ($e.derived -eq $true) 'cpl: derived flag'
Eqs $e.marker 'derived - not reported by the platform' 'cpl: marker text'
Eqs $e.formula "Cost divided by Conversions excluding 'Directions'" 'cpl: formula in plain words'
Eqs $e.type 'currency' 'cpl: currency result'
Eqs $e.current.display '$19.91' 'cpl: current = 2000 / (400.43 - 300)'
Ok ($e.current.approximate -eq $false -and -not $e.current.Contains('displayLow')) 'cpl: exact - the excluded row is a whole number, so the subtotal is pinned'
Eqs $e.current.crossCheck 'agreed' 'cpl: current cross-checked against the month widget'
Eqs $e.current.inputs[0].display '$2,000.00' 'cpl: numerator input display'
Eqs $e.current.inputs[0].source.kind 'headline' 'cpl: numerator source kind'
Eqs $e.current.inputs[1].display '100.43' 'cpl: denominator subtotal = account minus the other row'
Eqs $e.current.inputs[1].source.kind 'breakdown-rows' 'cpl: denominator source kind'
Eqs $e.current.inputs[1].source.method 'account-minus-other-rows' 'cpl: method recorded'
Eqs $e.current.inputs[1].source.otherRows[0].label 'Directions' 'cpl: the other row is recorded'
Ok (@($e.current.inputs[1].source.rows).Count -eq 2) 'cpl: two rows selected'
Ok (@($e.current.inputs[1].source.rows | Where-Object { $_.label -eq 'Directions' }).Count -eq 0) 'cpl: excluded row not among the selected rows'
Eqs $e.current.inputs[1].source.corroboratedBy[0].widgetId 'wMonthSub' 'cpl: corroborating widget recorded'
Eqs $e.current.inputs[1].source.reconciledWith.account '400.4' 'cpl: rows reconciled with the account total'
# previous: the month widget's row-aligned previous (4.0) is NOT the previous period (2 month buckets)
Eqs $e.previous.display '$14.98' 'cpl: previous = 1800 / (500.19 - 380)'
Eqs $e.previous.crossCheck 'single-route' 'cpl: previous has no usable cross-check'
Ok (@($e.notes | Where-Object { $_ -match 'spans 2 month bucket' -and $_ -match '4\.0' }).Count -eq 1) 'cpl: note explains why the widget previous column was not used, and shows it'
Ok ($e.comparison.hasComparison -eq $true) 'cpl: comparison emitted (both periods resolved, no usable route disagrees)'
Eqs $e.comparison.displayDelta '+33.0%' 'cpl: delta'
Ok ($e.comparison.approximate -eq $false) 'cpl: an exact pair gives an exact delta'
Eqs $e.reported.displayCurrent '$4.99' 'cpl: reported counterpart carried alongside'
Ok ($e.reported.hasComparison -eq $true -and $e.reported.displayPrevious -eq '$3.60') 'cpl: reported counterpart carries the headline''s own comparison'
Eqs $e.requestSource 'annotation:ANN#1' 'cpl: provenance kept'
# the formula quotes the FACTS label, never the request's spelling
$eSp = Resolve-DmRequest (NewFacts) (NewReq ($script:ReqCpl -replace '"Directions"','"directions "'))
Eqs $eSp.formula "Cost divided by Conversions excluding 'Directions'" 'formula uses the row label as the facts spell it'

# ---------- a rounded row stays approximate, bounded from both sides ----------
$eF = Resolve-DmRequest (NewFacts) (NewReq $script:ReqForm)
Eqs $eF.status 'resolved' 'form: resolved'
Eqs $eF.formula "Cost divided by Conversions from 'Form' only" 'form: include wording'
Eqs $eF.current.display '$98.04' 'form: 2000 / 20.4'
Ok ($eF.current.approximate -eq $true) 'form: approximate (the row is rounded to one decimal)'
Eqs $eF.current.displayLow '$97.80' 'form: low = 2000 / 20.45'
Eqs $eF.current.displayHigh '$98.14' 'form: high = 2000 / 20.38 (the account-minus-other-rows bound, tighter than 20.35)'
Eqs $eF.current.crossCheck 'single-route' 'form: no widget corroborates'
Eqs $eF.previous.display '$59.60' 'form: previous = 1800 / 30.2'
Eqs $eF.previous.displayLow '$59.52' 'form: previous low = 1800 / 30.24 (account minus the other rows caps the subtotal at 30.24)'; Eqs $eF.previous.displayHigh '$59.70' 'form: previous high'
Eqs $eF.comparison.displayDelta '+64.5%' 'form: delta'
Ok ($eF.comparison.approximate -eq $true) 'form: approximate delta'
Eqs $eF.comparison.displayDeltaLow '+63.8%' 'form: delta low'; Eqs $eF.comparison.displayDeltaHigh '+64.9%' 'form: delta high'
Ok (@($eF.notes | Where-Object { $_ -match 'between \$97\.80 and \$98\.14' }).Count -eq 1) 'form: note states the range'
# raw cells (a future facts version) are used exactly
$fRaw = NewFacts; (Rows $fRaw)[2].values.Conversions | Add-Member -NotePropertyName raw -NotePropertyValue 20.43
$eRaw = Resolve-DmRequest $fRaw (NewReq $script:ReqForm)
Eqs $eRaw.current.display '$97.90' 'raw cell: exact 2000 / 20.43'
Ok ($eRaw.current.approximate -eq $false) 'raw cell: not approximate'

# ---------- a numeric row label is a label, not "false" ----------
$fHour = NewFacts; $fHour.platforms[0].breakdowns[0].dimensions = @('Hour of day')
(Rows $fHour)[0].label = '0'; (Rows $fHour)[1].label = '1'; (Rows $fHour)[2].label = '2'
$eZeroLbl = Resolve-DmRequest $fHour (NewReq '{ "id": "h0", "label": "Hour 0", "op": "sum", "terms": [ { "metric": "Conversions", "filter": { "dimension": "Hour of day", "include": [ 0 ] } } ] }')
Eqs $eZeroLbl.current.display '300' 'numeric label 0: resolves to ROW 0, not the account total'
Eqs $eZeroLbl.formula "Conversions from '0' only" 'numeric label 0: named in the formula'
$rEmpty = Resolve-DmRowsRoute $fHour.platforms[0] $fHour.platforms[0].headline.'g:conv' ([pscustomobject]@{ dimension='Hour of day'; include=@() }) 'current' (Get-DmAccountQty $fHour.platforms[0].headline.'g:conv' 'current') $null
Ok (-not $rEmpty.ok -and $rEmpty.reason -match 'names no row') 'an empty filter is refused inside the rows route itself'

# ---------- include filter, sum, difference, percent, negative ----------
$eInc = Resolve-DmRequest (NewFacts) (NewReq '{ "id": "calls_forms", "label": "Calls and forms", "op": "sum", "terms": [ { "metric": "Conversions", "filter": { "dimension": "Conversion action name", "include": [ "Calls", "Form" ] } } ] }')
Eqs $eInc.current.display '100.43' 'include: Calls + Form, pinned by the account minus Directions'
Eqs $eInc.formula "Conversions from 'Calls' and 'Form' only" 'include: formula wording'
$eDiff = Resolve-DmRequest (NewFacts) (NewReq '{ "id": "non_converting", "label": "Clicks that did not convert", "op": "difference", "terms": [ { "metric": "Clicks" }, { "metric": "Conversions" } ] }')
Eqs $eDiff.current.display '599.6' 'difference: 1000 - 400.43 at one decimal'
Ok ($eDiff.current.approximate -eq $false) 'difference of raw headline values is exact'
Eqs $eDiff.formula 'Clicks minus Conversions' 'difference: formula wording'
$eSum2 = Resolve-DmRequest (NewFacts) (NewReq '{ "id": "touches", "label": "Clicks plus conversions", "op": "sum", "terms": [ { "metric": "Clicks" }, { "metric": "Conversions" } ] }')
Eqs $eSum2.current.display '1,400.4' 'sum of two terms: 1000 + 400.43'
Eqs $eSum2.formula 'Clicks plus Conversions' 'sum: formula wording'
$ePct = Resolve-DmRequest (NewFacts) (NewReq '{ "id": "lead_rate", "label": "Lead rate", "op": "ratio", "format": "percent", "terms": [ { "metric": "Conversions", "filter": { "dimension": "Conversion action name", "exclude": [ "Directions" ] } }, { "metric": "Clicks" } ] }')
Eqs $ePct.current.display '10.0%' 'percent ratio: 100.43 / 1000'
$eDec = Resolve-DmRequest (NewFacts) (NewReq '{ "id": "conv_per_click", "label": "Conversions per click", "op": "ratio", "decimals": 3, "terms": [ { "metric": "Conversions" }, { "metric": "Clicks" } ] }')
Eqs $eDec.current.display '0.400' 'decimals honoured for a plain number result'
$eNeg = Resolve-DmRequest (NewFacts) (NewReq '{ "id": "neg", "label": "Conversions minus clicks", "op": "difference", "terms": [ { "metric": "Conversions" }, { "metric": "Clicks" } ] }')
Eqs $eNeg.current.display '-599.6' 'negative result keeps its sign'
Ok ($eNeg.comparison.hasComparison -eq $false -and [string]$eNeg.comparison.reason) 'negative values: no percentage change, with a reason'

# ---------- refusals, each with a stated reason ----------
function Refused($facts,$reqJson,$pattern,$name){
  $r = Resolve-DmRequest $facts (NewReq $reqJson)
  Ok (([string]$r.status -eq 'refused') -and ((@($r.reasons) -join ' ') -match $pattern) -and -not $r.Contains('current')) "$name (status=$($r.status); reasons=$(@($r.reasons) -join ' | '))"
}
Refused (NewFacts) ($script:ReqCpl -replace '"Directions"','"Driving directions"') "matched 0 rows.*available: 'Directions', 'Calls', 'Form'" 'refuse: unknown row label lists the available ones'
Refused (NewFacts) ($script:ReqCpl -replace 'Conversion action name','Campaign') "no breakdown by 'Campaign' alone" 'refuse: no breakdown by that dimension'
Refused (NewFacts) ($script:ReqCpl -replace '"metric": "Cost"','"metric": "Spend"') "no account-level figure.*available: .*Cost" 'refuse: unknown metric lists the available ones'
Refused (NewFacts) '{ "id": "a", "label": "x", "op": "ratio", "terms": [ { "metric": "Cost / conversion" }, { "metric": "Clicks" } ] }' 'not a summable metric' 'refuse: a ratio metric cannot be a component'
Refused (NewFacts) '{ "id": "a", "label": "x", "op": "sum", "terms": [ { "metric": "Cost" }, { "metric": "Clicks" } ] }' 'cannot sum a currency amount and a count' 'refuse: adding money to a count'
Refused (NewFacts) ($script:ReqCpl -replace '"op": "ratio"','"op": "ratio", "platform": "facebook-ads"') "platform 'facebook-ads' is not in the facts" 'refuse: platform not present'
Refused (NewFacts) ($script:ReqCpl -replace 'annotation:ANN#1','annotation:ANN#9') 'annotation that is not in the facts' 'refuse: provenance names a missing annotation'
Refused (NewFacts) '{ "id": "a", "label": "x", "op": "ratio", "format": "currency", "terms": [ { "metric": "Conversions" }, { "metric": "Clicks" } ] }' 'not a currency amount' 'refuse: format currency on a count ratio'
Refused (NewFacts) '{ "id": "a", "label": "x", "op": "ratio", "format": "percent", "terms": [ { "metric": "Cost" }, { "metric": "Clicks" } ] }' 'needs a ratio of two like quantities' 'refuse: format percent on money per click'
Refused (NewFacts) '{ "id": "a", "label": "x", "op": "ratio", "format": "number", "terms": [ { "metric": "Cost" }, { "metric": "Clicks" } ] }' 'would mislabel' 'refuse: format number on a currency result'
Refused (NewFacts) '{ "id": "a", "label": "x", "op": "ratio", "decimals": 0, "terms": [ { "metric": "Cost" }, { "metric": "Clicks" } ] }' 'decimals applies only' 'refuse: decimals on a currency result'
$fTrunc = NewFacts; $fTrunc.platforms[0].breakdowns[0].rowCount = 5
Refused $fTrunc $script:ReqCpl 'truncated' 'refuse: truncated breakdown cannot be summed'
$fNoPart = NewFacts; (Rows $fNoPart)[0].values.Conversions.display = '250'
Refused $fNoPart $script:ReqCpl 'do not reconcile with the account Conversions for the current period' 'refuse: rows that do not partition the account figure'
# whole-number rows are exact: one unit off is NOT within tolerance any more
$fOff = NewFacts; (Rows $fOff)[0].values.Conversions.display = '301'
Refused $fOff $script:ReqCpl 'do not reconcile' 'refuse: a whole-number row off by one no longer slips through rounding slack'
$fBadCell = NewFacts; (Rows $fBadCell)[1].values.Conversions.display = '80,0'
Refused $fBadCell $script:ReqCpl 'cannot be read as a number' 'refuse: a cell in another number format'
$fInc = NewFacts; $fInc.meta.extractionComplete = $false
Refused $fInc $script:ReqCpl 'extractionComplete=false' 'refuse: partial extraction'
$fVer = NewFacts; $fVer.meta.factsVersion = 2
Refused $fVer $script:ReqCpl 'facts version' 'refuse: filtered term on an unverified facts version'
$eVerPlain = Resolve-DmRequest $fVer (NewReq '{ "id": "a", "label": "x", "op": "ratio", "terms": [ { "metric": "Cost" }, { "metric": "Clicks" } ] }')
Eqs $eVerPlain.current.display '$2.00' 'an unfiltered ratio does not depend on the facts version'
$fZero = NewFacts
$fZero.platforms[0].headline.'g:conv'.current = 300; $fZero.platforms[0].headline.'g:conv'.displayCurrent = '300'
(Rows $fZero)[1].values.Conversions.display = '0'; (Rows $fZero)[2].values.Conversions.display = '0'
Refused $fZero $script:ReqCpl "the denominator \(Conversions excluding 'Directions'\) is zero" 'refuse: zero denominator, and the reason names the denominator'
$eZeroNum = Resolve-DmRequest $fZero (NewReq '{ "id": "form_rate", "label": "Form rate", "op": "ratio", "format": "percent", "terms": [ { "metric": "Conversions", "filter": { "dimension": "Conversion action name", "include": [ "Form" ] } }, { "metric": "Clicks" } ] }')
Eqs $eZeroNum.current.display '0.0%' 'a zero numerator is a zero result, not a refusal'
$fTwo = NewFacts; $p2 = ($script:FactsJson | ConvertFrom-Json).platforms[0]; $p2.id = 'facebook-ads'; $p2.name = 'Meta'; $fTwo.platforms = @($fTwo.platforms[0], $p2)
Refused $fTwo $script:ReqCpl 'never blends platforms' 'refuse: two platforms and none named'
$eTwo = Resolve-DmRequest $fTwo (NewReq ($script:ReqCpl -replace '"op": "ratio"','"op": "ratio", "platform": "Meta"'))
Eqs $eTwo.platformId 'facebook-ads' 'platform may be named by display name'
$fAmb = NewFacts; $fAmb.platforms[0].headline.'g:clicks'.metric = 'Cost'
Refused $fAmb $script:ReqCpl 'ambiguous.*metricId' 'refuse: ambiguous metric name asks for metricId'
$eById = Resolve-DmRequest $fAmb (NewReq ($script:ReqCpl -replace '"metric": "Cost"','"metricId": "g:cost"'))
Eqs $eById.current.display '$19.91' 'metricId disambiguates'
$fCur = NewFacts
$fCur.platforms[0].headline | Add-Member -NotePropertyName 'g:rev' -NotePropertyValue ([pscustomobject]@{ metric='Revenue'; id='g:rev'; unit='micros'; type='currency'; currency='EUR'; current=5000000000; previous=4000000000; hasComparison=$true; displayCurrent='5,000.00'; displayPrevious='4,000.00'; canonical=[pscustomobject]@{ scope='account'; period='2026-10-01..2026-10-31' } })
$fCur.platforms[0].metrics | Add-Member -NotePropertyName 'g:rev' -NotePropertyValue ([pscustomobject]@{ id='g:rev'; aggClass='sum' })
Refused $fCur '{ "id": "a", "label": "x", "op": "sum", "terms": [ { "metric": "Cost" }, { "metric": "Revenue" } ] }' 'different currencies' 'refuse: two currencies'
$fPer = NewFacts; $fPer.platforms[0].headline.'g:cost'.canonical.period = '2026-09-01..2026-09-30'
Refused $fPer $script:ReqCpl 'covers 2026-09-01..2026-09-30, not the report period' 'refuse: a component measured over another period'
$fScope = NewFacts; $fScope.platforms[0].headline.'g:cost'.canonical.scope = 'campaign:Brand'
Refused $fScope $script:ReqCpl "scoped 'campaign:Brand'" 'refuse: a component that is not an account-level total'
# facts older than the coverage record: the analyzer's own classifier decides, not the display type
$plOld = [pscustomobject]@{ name='Google Ads' }
Ok ($null -eq (Test-DmSummable $plOld ([pscustomobject]@{ id='google-adwords:x:cost_micros'; metric='Cost'; unit='micros'; type='currency' }))) 'no coverage record: Cost is still summable'
Ok ([string](Test-DmSummable $plOld ([pscustomobject]@{ id='google-adwords:x:cost_per_conversion'; metric='Cost / conv.'; unit='micros'; type='currency' })) -match 'not a summable') 'no coverage record: Cost / conversion (typed currency) is NOT summable'
Ok ([string](Test-DmSummable $plOld ([pscustomobject]@{ id='google-adwords:x:average_cpc'; metric='Avg. CPC'; unit='micros'; type='currency' })) -match 'not a summable') 'no coverage record: Avg. CPC is NOT summable'

# ---------- routes: rows are the only source; widgets confirm or contradict ----------
$reqNamedAll = $script:ReqCpl -replace '"exclude": \[ "Directions" \] \}','"exclude": [ "Directions" ] }, "widget": "wMonthAll"'
Refused (NewFacts) $reqNamedAll "routes disagree for the current period.*100\.43.*400\.4" 'refuse: a named cross-check widget that disagrees with the rows'
Refused (NewFacts) ($reqNamedAll -replace 'wMonthAll','wNope') 'cross-check widget that is not a breakdown' 'refuse: named widget not in the facts'
Refused (NewFacts) '{ "id": "a", "label": "x", "op": "sum", "terms": [ { "metric": "Conversions", "widget": "wMonthSub" } ] }' 'has no filter' 'refuse: a cross-check widget on an unfiltered term'
# a named widget that agrees now but cannot be aligned for the previous period: no comparison
$eNamedSub = Resolve-DmRequest (NewFacts) (NewReq ($reqNamedAll -replace 'wMonthAll','wMonthSub'))
Ok ($eNamedSub.status -eq 'resolved' -and $eNamedSub.current.crossCheck -eq 'agreed') 'named widget: agrees in the current period'
Ok ($eNamedSub.comparison.hasComparison -eq $false -and [string]$eNamedSub.previous.reason -match 'cannot be used for the previous period') 'named widget: unusable for the previous period -> no comparison'
# NO widget-only route: without a row breakdown nothing resolves, whatever the request names
$fNoRows = NewFacts; $fNoRows.platforms[0].breakdowns = @($fNoRows.platforms[0].breakdowns[1], $fNoRows.platforms[0].breakdowns[2])
Refused $fNoRows $script:ReqCpl "no breakdown by 'Conversion action name' alone.*'Month / Conversion action name'.*cannot say which rows" 'refuse: no rows - and the refusal names the widget that exists but cannot be used alone'
Refused $fNoRows ($reqNamedAll -replace 'wMonthAll','wMonthSub') "no breakdown by 'Conversion action name' alone" 'refuse: naming a widget does not create a route'
# an invented filter cannot ride on a named widget
Refused (NewFacts) ($script:ReqCpl -replace 'Conversion action name','Campaign' -replace '"exclude": \[ "Directions" \] \}','"exclude": [ "Brand search" ] }, "widget": "wAct"') "no breakdown by 'Campaign' alone" 'refuse: invented dimension with a named widget'
Refused (NewFacts) ($reqNamedAll -replace 'wMonthAll','wMonthSub' -replace '"Directions"','"Directionz"') 'matched 0 rows' 'refuse: a label typo is not rescued by a named widget'
# when the previous window IS one month bucket, the widget's previous column is usable - and here it
# contradicts the rows, so the comparison is withheld while the current figure stands
$fOne = NewFacts
$fOne.meta.periodResolved.previous.start = '2026-09-01'; $fOne.meta.previousPeriod = '2026-09-01..2026-09-30'
$eOne = Resolve-DmRequest $fOne (NewReq $script:ReqCpl)
Eqs $eOne.status 'resolved' 'prev disagreement: current still resolved'
Eqs $eOne.current.display '$19.91' 'prev disagreement: current figure unchanged'
Ok ($eOne.comparison.hasComparison -eq $false) 'prev disagreement: comparison withheld'
Eqs $eOne.previous.status 'unresolved' 'prev disagreement: previous marked unresolved'
Ok ([string]$eOne.previous.reason -match 'routes disagree for the previous period.*120\.19.*4\.0') 'prev disagreement: reason names both values'
Ok (-not $eOne.previous.Contains('display')) 'prev disagreement: no previous figure emitted'
$fAgree = NewFacts
$fAgree.meta.periodResolved.previous.start = '2026-09-01'; $fAgree.meta.previousPeriod = '2026-09-01..2026-09-30'
$fAgree.platforms[0].breakdowns[2].rows[0].values.Conversions.displayPrevious = '120.2'
$eAgree = Resolve-DmRequest $fAgree (NewReq $script:ReqCpl)
Eqs $eAgree.previous.crossCheck 'agreed' 'prev agreement: cross-check agreed'
Ok ($eAgree.comparison.hasComparison -eq $true) 'prev agreement: comparison emitted'
# a time-series dimension anywhere in a widget blocks its previous column, not only when it leads
$fTail = NewFacts
$fTail.meta.periodResolved.previous.start = '2026-09-01'; $fTail.meta.previousPeriod = '2026-09-01..2026-09-30'
$fTail.platforms[0].breakdowns[2].dimensions = @('Conversion action name','Week')
$eTail = Resolve-DmRequest $fTail (NewReq $script:ReqCpl)
Ok ($eTail.comparison.hasComparison -eq $true -and @($eTail.notes | Where-Object { $_ -match 'bucketed by Week' }).Count -eq 1) 'a trailing time-series dimension: previous column not used (noted), no false disagreement'
# rows of a time-series breakdown: current only
$fSeries = NewFacts; $fSeries.platforms[0].breakdowns[0].dimensions = @('Month')
$eSeries = Resolve-DmRequest $fSeries (NewReq '{ "id": "m", "label": "x", "op": "sum", "terms": [ { "metric": "Conversions", "filter": { "dimension": "Month", "include": [ "Calls" ] } } ] }')
Ok ($eSeries.status -eq 'resolved' -and $eSeries.comparison.hasComparison -eq $false -and [string]$eSeries.previous.reason -match 'time series') 'a row of a time-series breakdown resolves for the current period only'
# two breakdowns by the same dimension that both reconcile but split differently: ambiguous
$fDup = NewFacts
$dupBd = ($script:FactsJson | ConvertFrom-Json).platforms[0].breakdowns[0]; $dupBd.widgetId = 'wAct2'
$dupBd.rows[1].values.Conversions.display = '20.4'; $dupBd.rows[2].values.Conversions.display = '80.0'
$fDup.platforms[0].breakdowns = @($fDup.platforms[0].breakdowns) + @($dupBd)
Refused $fDup $script:ReqForm 'both reconcile.*different subtotals' 'refuse: two reconciling breakdowns that disagree'
# the previous period must come from the breakdown the current period used
$accP = Get-DmAccountQty (NewFacts).platforms[0].headline.'g:conv' 'previous'
$rPin = Resolve-DmRowsRoute (NewFacts).platforms[0] (NewFacts).platforms[0].headline.'g:conv' ([pscustomobject]@{ dimension='Conversion action name'; include=@('Form') }) 'previous' $accP 'wOther'
Ok (-not $rPin.ok) 'rows route: pinned to a widget id, no other breakdown is used'

# ---------- comparison gates ----------
$fUntr = NewFacts; $fUntr.meta.compareBasis = 'untrusted'
$eUntr = Resolve-DmRequest $fUntr (NewReq $script:ReqCpl)
Ok ($eUntr.status -eq 'resolved' -and $eUntr.comparison.hasComparison -eq $false -and -not $eUntr.previous.Contains('display')) 'untrusted basis: current resolves, no previous figure, no comparison'
$fPlNo = NewFacts; $fPlNo.platforms[0].hasComparison = $false
$ePlNo = Resolve-DmRequest $fPlNo (NewReq $script:ReqCpl)
Ok ($ePlNo.comparison.hasComparison -eq $false -and -not $ePlNo.previous.Contains('display')) 'platform without a comparison: none emitted'
$fMetaNo = NewFacts; $fMetaNo.meta.hasComparison = $false
$eMetaNo = Resolve-DmRequest $fMetaNo (NewReq $script:ReqCpl)
Ok ($eMetaNo.comparison.hasComparison -eq $false -and -not $eMetaNo.previous.Contains('display')) 'report without a comparison: none emitted'
$fNoPrev = NewFacts; $fNoPrev.platforms[0].headline.'g:cost'.hasComparison = $false
$eNoPrev = Resolve-DmRequest $fNoPrev (NewReq $script:ReqCpl)
Ok ($eNoPrev.status -eq 'resolved' -and $eNoPrev.comparison.hasComparison -eq $false) 'a component without a previous value: no comparison'
Ok ([string]$eNoPrev.comparison.reason -match 'previous period did not resolve') 'the reason for no comparison is stated'
# a zero previous value: the figure is shown, a percentage change is not
$fZeroPrev = NewFacts
$fZeroPrev.platforms[0].headline.'g:conv'.previous = 470; $fZeroPrev.platforms[0].headline.'g:conv'.displayPrevious = '470'
(Rows $fZeroPrev)[2].values.Conversions.displayPrevious = '0'
$eZeroPrev = Resolve-DmRequest $fZeroPrev (NewReq '{ "id": "forms", "label": "Form leads", "op": "sum", "terms": [ { "metric": "Conversions", "filter": { "dimension": "Conversion action name", "include": [ "Form" ] } } ] }')
Ok ($eZeroPrev.previous.display -eq '0' -and $eZeroPrev.comparison.hasComparison -eq $false -and -not $eZeroPrev.comparison.Contains('displayDelta')) 'zero previous: no delta'
Ok ([string]$eZeroPrev.comparison.reason -match 'zero or negative') 'zero previous: the reason is stated'
# reported counterpart without a comparison of its own
$fRepNo = NewFacts; $fRepNo.platforms[0].headline.'g:cpa'.hasComparison = $false
$eRepNo = Resolve-DmRequest $fRepNo (NewReq $script:ReqCpl)
Ok ($eRepNo.reported.hasComparison -eq $false -and -not $eRepNo.reported.Contains('displayPrevious') -and -not $eRepNo.reported.Contains('displayDelta')) 'reported counterpart: no previous or delta when the headline has no comparison'
# request text never reaches a note
$eAlong = Resolve-DmRequest (NewFacts) (NewReq ($script:ReqCpl -replace '"alongside": "Cost / conversion"','"alongside": "industry average $31.40"'))
Ok ($eAlong.status -eq 'resolved' -and -not $eAlong.Contains('reported') -and (@($eAlong.notes) -join ' ') -notmatch '31\.40|industry') 'a missing alongside metric is noted WITHOUT echoing the request text'

# ---------- facts text splice, merge, replace ----------
$blockA = ConvertTo-DmBlockJson @($e)
$spliced = Set-DmFactsBlock $script:FactsJson $blockA
$head = $script:FactsJson.TrimEnd(); $head = $head.Substring(0,$head.Length-1).TrimEnd()
Ok ($spliced.StartsWith($head)) 'splice: everything before the new member is byte-preserved'
$sp = $spliced | ConvertFrom-Json
Ok (@($sp.derivedMetrics.entries).Count -eq 1 -and $sp.derivedMetrics.entries[0].id -eq 'cpl_ex_directions') 'splice: block parses back'
Ok ($sp.derivedMetrics.version -eq 2) 'splice: block version'
Eqs $sp.derivedMetrics.marker 'derived - not reported by the platform' 'splice: block-level marker'
Ok (@($sp.platforms).Count -eq 1 -and $sp.findings) 'splice: rest of the document intact'
$again = Set-DmFactsBlock $spliced $blockA
Ok ($again -ceq $spliced) 'splice: re-running is idempotent'
Ok (([regex]::Matches($again,'"derivedMetrics"')).Count -eq 1) 'splice: never two blocks'
$middle = '{ "meta": { "a": "x, } \" {" }, "derivedMetrics": { "entries": [ { "id": "old" } ] }, "platforms": [ 1 ] }'
$mid2 = Set-DmFactsBlock $middle '{ "entries": [] }'
$m2 = $mid2 | ConvertFrom-Json
Ok ($m2.meta.a -eq 'x, } " {' -and @($m2.platforms).Count -eq 1 -and ([regex]::Matches($mid2,'"derivedMetrics"')).Count -eq 1) 'splice: an existing member mid-document is replaced, strings with braces survive'
$nested = '{ "meta": { "derivedMetrics": 1 }, "platforms": [] }'
Ok ($null -eq (Find-DmTopLevelMember $nested 'derivedMetrics')) 'splice: a nested key of the same name is not the top-level member'
$merged = @(Merge-DmEntries @([pscustomobject]@{ id='keep' }, [pscustomobject]@{ id='cpl_ex_directions'; stale=$true }) @($e))
Ok ($merged.Count -eq 2 -and $merged[0].id -eq 'keep' -and -not $merged[1].stale) 'merge: other ids kept, same id replaced'
$exist = @([pscustomobject]@{ id='from_note'; requestSource='annotation:ANN#1' }, [pscustomobject]@{ id='mine'; requestSource='user' })
Eqs ((Test-DmReplaceSafe $exist @([pscustomobject]@{ id='x'; source='user' })) -join ',') 'from_note' 'replace: an entry a client note asked for may not be dropped silently'
Ok (@(Test-DmReplaceSafe $exist @([pscustomobject]@{ id='x'; source='annotation:ANN#1' })).Count -eq 0) 'replace: fine when the note is re-requested'

# ---------- closer: derived metrics ----------
function FactsOn($factsObj,$entries){ return ((Set-DmFactsBlock (ConvertTo-Json -InputObject $factsObj -Depth 30) (ConvertTo-DmBlockJson @($entries))) | ConvertFrom-Json) }
function FactsWith($entries){ return ((Set-DmFactsBlock $script:FactsJson (ConvertTo-DmBlockJson @($entries))) | ConvertFrom-Json) }
$secHead = "## Google Ads`n<!-- platform:google-adwords -->`n`n- Cost was `$2,000.00 and conversions were 400.4.`n"
function Rep($lines){ return ($secHead + (@($lines) -join "`n") + "`n") }
$markX = "derived - not a figure Google Ads reports: Cost divided by Conversions excluding 'Directions', `$2,000.00 over 100.43"
$lineX = "- Cost per lead without Directions was `$19.91 ($markX), alongside the reported `$4.99. <!-- derived:cpl_ex_directions -->"
$markF = "derived - not a figure Google Ads reports: Cost divided by Conversions from 'Form' only, `$2,000.00 over 20.4"
$lineF = "- Cost per form lead was about `$98.04 ($markF). <!-- derived:cpl_form -->"
$fX = FactsWith @($e); $fF = FactsWith @($eF)

$rGood = Invoke-Closer (Rep $lineX) $fX
Ok ($rGood.violations.Count -eq 0) ("closer: a correctly cited exact derived metric passes (" + (Viol $rGood) + ")")
Ok ($rGood.traced -eq $rGood.measuresChecked -and $rGood.measuresChecked -ge 6) 'closer: every number on the derived line traced'
$clean = Strip-Anchors (Rep $lineX)
Ok ($clean -notmatch 'derived:' -and $clean -match 'derived - not a figure Google Ads reports') 'closer: anchor stripped, visible marker survives publication'
$rApprox = Invoke-Closer (Rep $lineF) $fF
Ok ($rApprox.violations.Count -eq 0) ("closer: an approximate figure with 'about' directly before it passes (" + (Viol $rApprox) + ")")
# --- approximate wording ---
$rFlat = Invoke-Closer (Rep ($lineF -replace 'about \$98\.04','$98.04')) $fF
Ok (HasT $rFlat 'derived-approximation-missing') 'closer: an approximate figure stated flatly is flagged'
$rFar = Invoke-Closer (Rep (($lineF -replace 'about \$98\.04','exactly $98.04') -replace ' <!--','; ask us about it. <!--')) $fF
Ok (HasT $rFar 'derived-approximation-missing') 'closer: "about" somewhere else on the line does not count'
$rOther = Invoke-Closer (Rep ($lineF -replace 'was about \$98\.04','on about 20.4 leads was $98.04')) $fF
Ok (HasT $rOther 'derived-approximation-missing') 'closer: "about" before ANOTHER number does not cover the figure'
$rRange = Invoke-Closer (Rep ($lineF -replace 'about \$98\.04','between $97.80 and $98.14')) $fF
Ok ($rRange.violations.Count -eq 0) ("closer: the range, written as between low and high, passes (" + (Viol $rRange) + ")")
$rBound = Invoke-Closer (Rep ($lineF -replace 'about \$98\.04','$97.80')) $fF
Ok (HasT $rBound 'derived-approximation-missing') 'closer: one end of the range stated as the figure is flagged'
$rRound = Invoke-Closer (Rep ($lineF -replace 'about \$98\.04','about $98')) $fF
Ok (HasT $rRound 'derived-rounded') 'closer: a rounder form of the figure is flagged'
$rCmp = Invoke-Closer (Rep ($lineF -replace '\)\. <!--',"), up about 64.5% from about `$59.60. <!--")) $fF
Ok ($rCmp.violations.Count -eq 0) ("closer: a derived comparison, each approximate figure worded so, passes (" + (Viol $rCmp) + ")")
# the same-value trap: an approximate filtered SUM equals its own subtotal input
$eFS = Resolve-DmRequest (NewFacts) (NewReq '{ "id": "forms", "label": "Form leads", "op": "sum", "terms": [ { "metric": "Conversions", "filter": { "dimension": "Conversion action name", "include": [ "Form" ] } } ] }')
Ok ($eFS.current.approximate -eq $true) 'a filtered sum of a rounded row is approximate'
$lineFS = "- Form leads were {0} (derived - not a figure Google Ads reports: Conversions from 'Form' only). <!-- derived:forms -->"
Ok (HasT (Invoke-Closer (Rep ($lineFS -f '20.4')) (FactsWith @($eFS))) 'derived-approximation-missing') 'closer: flat wording is flagged even when the figure equals another candidate'
Ok ((Invoke-Closer (Rep ($lineFS -f 'about 20.4')) (FactsWith @($eFS))).violations.Count -eq 0) 'closer: ... and passes with "about"'
# --- the marker: one closed family of wording ---
function MarkTest($phrase){ return (Invoke-Closer (Rep ("- Cost per lead without Directions was `$19.91 ($phrase Cost divided by Conversions excluding 'Directions'). <!-- derived:cpl_ex_directions -->")) $fX) }
Ok ((MarkTest 'derived - not a figure Google Ads reports:').violations.Count -eq 0) 'marker: "derived - not a figure <platform> reports"'
Ok ((MarkTest 'calculated, not reported by Google Ads:').violations.Count -eq 0) 'marker: "calculated, not reported by <platform>"'
Ok ((MarkTest "computed: Google Ads doesn't report it;").violations.Count -eq 0) 'marker: "computed: <platform> doesn''t report it"'
Ok ((MarkTest 'derived - not a figure the platform reports:').violations.Count -eq 0) 'marker: "the platform" stands for the platform name'
Ok (HasT (MarkTest 'our figure:') 'derived-marker-missing') 'marker: missing'
Ok (HasT (MarkTest 'derived:') 'derived-marker-missing') 'marker: "derived" alone is not enough'
Ok (HasT (MarkTest 'derived - not a figure Meta reports:') 'derived-marker-missing') 'marker: naming a different platform does not count'
Ok (HasT (MarkTest 'not derived - not a figure Google Ads reports:') 'derived-marker-missing') 'marker: a negated derived word does not count'
$rOpp = Invoke-Closer (Rep "- This is not in doubt: Google Ads reported a cost per lead of `$19.91, calculated as Cost divided by Conversions excluding 'Directions'. <!-- derived:cpl_ex_directions -->") $fX
Ok (HasT $rOpp 'derived-marker-missing') 'marker: a sentence attributing the figure to the platform is flagged'
$rHidden = Invoke-Closer (Rep "- Cost per lead without Directions was `$19.91 (Cost divided by Conversions excluding 'Directions'). <!-- derived - not a figure Google Ads reports --> <!-- derived:cpl_ex_directions -->") $fX
Ok (HasT $rHidden 'derived-marker-missing') 'marker: hidden in a comment does not count (it would be stripped)'
$rMulti = Invoke-Closer (Rep @("- Cost per lead without Directions was `$19.91 (Cost divided by Conversions excluding 'Directions'). <!-- derived:cpl_ex_directions --> <!-- derived - not a figure Google Ads reports",'-->')) $fX
Ok (HasT $rMulti 'multiline-comment') 'closer: a comment left open across lines is refused'
Ok (HasT (Invoke-Closer (Rep ($lineX -replace 'alongside','<span hidden>x</span> alongside')) $fX) 'derived-line-html') 'closer: an HTML tag on a derived line is refused'
# --- tracing ---
$rNoAnchor = Invoke-Closer (Rep ($lineX -replace ' <!-- derived:cpl_ex_directions -->','')) $fX
Ok (HasT $rNoAnchor 'untraceable-number') 'closer: a derived figure without its anchor is untraceable'
Ok (HasT $rNoAnchor 'unsurfaced-derived') 'closer: ... and the requested metric counts as unsurfaced'
Ok (HasT (Invoke-Closer (Rep ($lineX -replace '\$19\.91','$19.95')) $fX) 'untraceable-number') 'closer: a different number on the anchored line is still untraceable'
# nothing the REQUEST spelled is citable: label, refusal reasons, alongside text
$eLbl = Resolve-DmRequest (NewFacts) (NewReq ($script:ReqCpl -replace '"label": "Cost / conversion excluding Directions"','"label": "Cost per lead (target $12.50, benchmark 512%, 48,750 leads)"'))
$rLbl = Invoke-Closer (Rep ($lineX -replace ', alongside the reported \$4\.99',' against a target of $12.50, a benchmark of 512% and 48,750 leads')) (FactsWith @($eLbl))
Ok (@($rLbl.violations | Where-Object { $_.type -eq 'untraceable-number' }).Count -eq 3) ("closer: numbers typed into a request label are NOT citable (" + (Viol $rLbl) + ")")
Ok (@((Build-DerivedIndex (FactsWith @($eLbl)))['cpl_ex_directions'].cands | Where-Object { $_.value -in 12.5,512,48750 }).Count -eq 0) 'closer: request text adds no candidates'
# digits inside a real row label (part of the facts-built formula) do trace
$fPromo = NewFacts; (Rows $fPromo)[0].label = 'Promo 2500'
$ePromo = Resolve-DmRequest $fPromo (NewReq ($script:ReqCpl -replace '"Directions"','"Promo 2500"'))
$rPromo = Invoke-Closer (Rep "- Cost per lead was `$19.91 (derived - not a figure Google Ads reports: Cost divided by Conversions excluding 'Promo 2500'). <!-- derived:cpl_ex_directions -->") (FactsOn $fPromo @($ePromo))
Ok ($rPromo.violations.Count -eq 0) ("closer: digits inside a facts row label trace on the derived line (" + (Viol $rPromo) + ")")
# --- formula ---
Ok (HasT (Invoke-Closer (Rep ($lineX -replace "Cost divided by Conversions excluding 'Directions', ",'')) $fX) 'derived-formula-missing') 'closer: a cited derived metric must state its formula'
$rFormElse = Invoke-Closer (Rep @(($lineX -replace "Cost divided by Conversions excluding 'Directions', ",''),"- The formula is Cost divided by Conversions excluding 'Directions'.")) $fX
Ok (HasT $rFormElse 'derived-formula-missing') 'closer: the formula must sit on a line carrying the anchor'
Ok (-not (HasT (Invoke-Closer (Rep ($lineX -replace "'Directions'",([char]0x2018 + 'Directions' + [char]0x2019))) $fX) 'derived-formula-missing')) 'closer: curly quotes in the formula still match'
# --- where an entry may be cited ---
$rHeading = Invoke-Closer ("## Google Ads`n<!-- platform:google-adwords -->`n`n### Cost per lead `$19.91 ($markX) <!-- derived:cpl_ex_directions -->`n`n- Cost was `$2,000.00.`n") $fX
Ok (HasT $rHeading 'unsurfaced-derived') 'closer: an anchor in a heading is not surfacing'
$recs = "`n## Recommendations`n- Keep cost per lead without Directions near `$19.91 ($markX). <!-- derived:cpl_ex_directions -->`n"
$rRecs = Invoke-Closer ($secHead + $recs) $fX
Ok ((HasT $rRecs 'derived-in-recommendations') -and (HasT $rRecs 'unsurfaced-derived')) 'closer: an anchor in Recommendations is refused and is not surfacing'
$rRecsT = Invoke-Closer ($secHead + $recs) $fX -TraceRecs
Ok ((HasT $rRecsT 'derived-in-recommendations') -and (HasT $rRecsT 'unsurfaced-derived')) 'closer: ... also when Recommendations is traced'
$rRecFig = Invoke-Closer ((Rep $lineX) + "`n## Recommendations`n- Hold cost per lead near `$19.91 next month.`n") $fX
Ok (HasT $rRecFig 'derived-misuse') 'closer: a derived figure in Recommendations with no anchor is refused'
$rRecName = Invoke-Closer ((Rep $lineX) + "`n## Recommendations`n- Keep an eye on cost per lead without Directions; total cost was `$2,000.00.`n") $fX
Ok ($rRecName.violations.Count -eq 0) ("closer: Recommendations may name the metric and cite measured facts (" + (Viol $rRecName) + ")")
$rWrongSec = Invoke-Closer ($secHead + "`n## Analytical insights`n$lineX`n") $fX
Ok ((HasT $rWrongSec 'derived-wrong-platform') -and (HasT $rWrongSec 'unsurfaced-derived')) 'closer: a derived metric cited outside its platform section is refused'
Ok (HasT (Invoke-Closer (Rep @($lineX,'- Another figure. <!-- derived:nope -->')) $fX) 'unknown-derived-anchor') 'closer: an anchor naming no entry is flagged'
# a follow-on line that only quotes a caveat number already in the platform's own data needs no marker
$rNote = Invoke-Closer (Rep @($lineX,'- The dashboard''s monthly widget shows 4.0 for the prior period, which covers only part of it. <!-- derived:cpl_ex_directions -->')) $fX
Ok ($rNote.violations.Count -eq 0) ("closer: a caveat line under the same anchor passes without the marker (" + (Viol $rNote) + ")")
# --- comparison guard ---
$fNoCmp = FactsOn $fOne @($eOne)
Ok (HasT (Invoke-Closer (Rep ($lineX -replace 'was \$19\.91','rose to $19.91')) $fNoCmp) 'comparison-without-data') 'closer: comparative wording on a derived figure with no comparison is flagged'
$rRep = Invoke-Closer (Rep ($lineX -replace 'alongside the reported \$4\.99','while reported cost per conversion rose to $4.99')) (FactsOn $fRepNo @($eRepNo))
Ok (HasT $rRep 'comparison-without-data') 'closer: the derived anchor does not launder a comparison claim on a reported metric that has none'
$rNeg = Invoke-Closer (Rep "- Conversions minus clicks was -599.6 (derived - not a figure Google Ads reports: Conversions minus Clicks). <!-- derived:neg -->") (FactsWith @($eNeg))
Ok ($rNeg.violations.Count -eq 0) ("closer: a negative derived value quoted with its sign is not a comparison claim (" + (Viol $rNeg) + ")")
# --- refused entries ---
$eRef = Resolve-DmRequest (NewFacts) (NewReq (($script:ReqCpl -replace 'Conversion action name','Campaign') -replace '"label": "Cost / conversion excluding Directions"','"label": "Blended ROAS 512% on $48,750.00"'))
$fRef = FactsWith @($eRef)
Ok (HasT (Invoke-Closer $secHead $fRef) 'unsurfaced-derived') 'closer: a refused request the report is silent about is flagged'
$rRefOk = Invoke-Closer (Rep '- Cost per lead by campaign could not be calculated from this dashboard, which has no campaign breakdown of conversions. <!-- derived:cpl_ex_directions -->') $fRef
Ok ($rRefOk.violations.Count -eq 0) ("closer: stating the refusal passes (" + (Viol $rRefOk) + ")")
Ok (HasT (Invoke-Closer (Rep '- Lead cost held steady this month. <!-- derived:cpl_ex_directions -->') $fRef) 'derived-refusal-unstated') 'closer: a refused entry''s line must say it could not be calculated'
Ok (HasT (Invoke-Closer (Rep '- <!-- derived:cpl_ex_directions -->') $fRef) 'derived-refusal-unstated') 'closer: a bare anchor does not state a refusal'
$rRefFig = Invoke-Closer (Rep '- Cost per lead could not be calculated; the reported figure was $4.99. <!-- derived:cpl_ex_directions -->') $fRef
Ok (HasT $rRefFig 'derived-refused-figure') 'closer: a refused entry''s line carries no figure, not even a real one'
$rRefLbl = Invoke-Closer (Rep '- Blended ROAS of 512% on $48,750.00 could not be calculated. <!-- derived:cpl_ex_directions -->') $fRef
Ok ((HasT $rRefLbl 'untraceable-number') -and (HasT $rRefLbl 'derived-refused-figure')) 'closer: a refused entry lends no number from its label'
# --- stale / inert ---
$eOld = Resolve-DmRequest (NewFacts) (NewReq $script:ReqCpl); $eOld.Remove('v')
$rOld = Invoke-Closer (Rep $lineX) (FactsWith @($eOld))
Ok ((HasT $rOld 'derived-stale-entry') -and (HasT $rOld 'untraceable-number')) 'closer: an entry from an older tool version is rejected and lends nothing'
$eAsserted = Resolve-DmRequest (NewFacts) (NewReq $script:ReqCpl); $eAsserted.current.inputs[1].source.basis = 'request-asserted'
Ok (HasT (Invoke-Closer (Rep $lineX) (FactsWith @($eAsserted))) 'derived-stale-entry') 'closer: an entry resting on a request-asserted widget is rejected'
$rInert = Invoke-Closer $secHead (NewFacts)
Ok ($rInert.violations.Count -eq 0) 'closer: facts without a derivedMetrics block verify exactly as before'
Ok ((Build-DerivedIndex (NewFacts)).Count -eq 0) 'closer: no block -> empty derived index'

# ---------- end to end: the script itself ----------
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('swydee-dm-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
  $enc = New-Object Text.UTF8Encoding($false)
  $factsPath = Join-Path $tmp 'x.facts.json'; $rf = Join-Path $tmp 'req.json'
  function RunTool([string[]]$more){ $o = & powershell -NoProfile -File $script:ResolveTool -Facts $factsPath @more 2>&1; return @{ code=$LASTEXITCODE; out=(@($o) -join "`n") } }
  function WriteReq($name,$json){ $p = Join-Path $tmp $name; [IO.File]::WriteAllText($p,$json,$enc); return $p }
  [IO.File]::WriteAllText($factsPath,$script:FactsJson,$enc); [IO.File]::WriteAllText($rf,$script:ReqCpl,$enc)
  $r1 = RunTool @('-RequestFile',$rf)
  Ok ($r1.code -eq 0) "e2e: exit 0 when every request resolves (got $($r1.code): $($r1.out))"
  Ok ($r1.out -match 'RESOLVED cpl_ex_directions') 'e2e: prints the resolution'
  $bytes = [IO.File]::ReadAllBytes($factsPath)
  Ok (-not ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB)) 'e2e: output is BOM-less'
  Ok (@(Get-ChildItem $tmp -Filter *.tmp).Count -eq 0) 'e2e: no temporary file left behind'
  $w = [IO.File]::ReadAllText($factsPath) | ConvertFrom-Json
  Eqs $w.derivedMetrics.entries[0].current.display '$19.91' 'e2e: facts gained the derived block'
  Eqd $w.platforms[0].headline.'g:conv'.current 400.43 'e2e: existing facts untouched'
  # a refusal: exit 1, block written with both entries
  $r2 = RunTool @('-RequestFile',(WriteReq 'req2.json' ($script:ReqCpl -replace 'cpl_ex_directions','cpl_bad' -replace '"Directions"','"Nope"')))
  Ok ($r2.code -eq 1) "e2e: exit 1 when a request is refused (got $($r2.code))"
  $w2 = [IO.File]::ReadAllText($factsPath) | ConvertFrom-Json
  Ok (@($w2.derivedMetrics.entries).Count -eq 2 -and $w2.derivedMetrics.entries[1].status -eq 'refused') 'e2e: the refusal is recorded and the earlier entry kept'
  # everything below must exit 2 and write NOTHING
  $before = [IO.File]::ReadAllText($factsPath)
  function Nothing($res,$name){ Ok ($res.code -eq 2 -and ([IO.File]::ReadAllText($factsPath) -ceq $before)) "$name (exit $($res.code): $($res.out))" }
  Nothing (RunTool @('-RequestFile',(WriteReq 'r3.json' '{ "id": "x", "label": "x", "op": "ratio", "terms": [] }'))) 'e2e: malformed request -> exit 2, nothing written'
  Nothing (RunTool @('-RequestFile',(WriteReq 'r4.json' ('[ ' + $script:ReqCpl + ', ' + $script:ReqCpl + ' ]')))) 'e2e: the same id twice -> exit 2, nothing written'
  Nothing (RunTool @('-RequestFile',(WriteReq 'r5.json' ($script:ReqCpl -replace '"label": "Cost / conversion excluding Directions"','"label": "see swy.do/shares/AbCdEf123456"')))) 'e2e: a share link in request text trips the credential guard -> exit 2, nothing written'
  Nothing (RunTool @('-RequestFile',$rf,'-OutFile',(Join-Path $tmp 'no\such\dir\out.json'))) 'e2e: an unwritable -OutFile -> exit 2, nothing written'
  # -Replace would silently drop the entry a client note asked for
  Nothing (RunTool @('-RequestFile',(WriteReq 'r6.json' $script:ReqForm),'-Replace')) 'e2e: -Replace refuses to drop a client-note entry'
  # -Replace with the note re-requested: the stray refused entry goes
  $r7 = RunTool @('-RequestFile',$rf,'-Replace')
  $w7 = [IO.File]::ReadAllText($factsPath) | ConvertFrom-Json
  Ok ($r7.code -eq 0 -and @($w7.derivedMetrics.entries).Count -eq 1 -and $w7.derivedMetrics.entries[0].id -eq 'cpl_ex_directions') 'e2e: -Replace keeps only what this request file asks for'
  # -OutFile leaves the input alone
  $before = [IO.File]::ReadAllText($factsPath); $of = Join-Path $tmp 'out.facts.json'
  $r8 = RunTool @('-RequestFile',$rf,'-OutFile',$of)
  Ok ($r8.code -eq 0 -and (Test-Path $of) -and ([IO.File]::ReadAllText($factsPath) -ceq $before)) 'e2e: -OutFile writes elsewhere and leaves -Facts untouched'
  # an entry written by an older version is not carried forward silently
  $oldText = $before -replace '"v":\s*2','"v":  1'
  [IO.File]::WriteAllText($factsPath,$oldText,$enc); $before = $oldText
  Nothing (RunTool @('-RequestFile',(WriteReq 'r9.json' $script:ReqForm))) 'e2e: an older-version entry in the facts -> exit 2 until re-requested or replaced'
  # wrong kind of facts
  $trend = $script:FactsJson -replace '"tool": "Analyze-SwydoReport.ps1"','"tool": "Analyze-SwydoTrend.ps1"'
  [IO.File]::WriteAllText($factsPath,$trend,$enc); $before = $trend
  Nothing (RunTool @('-RequestFile',$rf)) 'e2e: trend facts are refused -> exit 2, nothing written'
} finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }

Write-Host ''
Write-Host ("Test-ResolveMetric: {0} passed, {1} failed." -f $script:pass,$script:fail)
if($script:fail -gt 0){ exit 1 }
