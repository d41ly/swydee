# Offline unit tests for Invoke-SwydoForecast.ps1 + the closer's estimate rules (_EstimateCheck.ps1).
# PS 5.1. Run: powershell -File tests\Test-Forecast.ps1
# EAP=Stop is load-bearing: a dot-source that silently fails must not leave "0 passed, 0 failed" + exit 0.
$ErrorActionPreference = 'Stop'
$script:ToolPath = "$PSScriptRoot\..\skill\scripts\Invoke-SwydoForecast.ps1"
. $script:ToolPath -DefineOnly
. "$PSScriptRoot\..\skill\scripts\Test-ReportNumbers.ps1" -DefineOnly

$script:pass = 0; $script:fail = 0
function Ok($cond,$name){ if($cond){ $script:pass++ } else { $script:fail++; Write-Host "FAIL: $name" } }
function Eqd($a,$b,$name){ if($null -eq $a){ Ok $false "$name (got null)"; return }; Ok ([math]::Abs([double]$a-[double]$b) -lt 0.001) "$name (got $a want $b)" }
function HasT($res,$t){ return (@($res.violations | Where-Object { $_.type -eq $t }).Count -gt 0) }
function Throws($sb,$pattern,$name){ $msg = $null; try { & $sb | Out-Null } catch { $msg = [string]$_.Exception.Message }; Ok ($msg -and $msg -match $pattern) "$name (got '$msg')" }
function Method($item,$id){ return @($item.methods | Where-Object { $_.id -eq $id })[0] }
function Skipped($item,$id){ return @($item.skippedMethods | Where-Object { $_.id -eq $id })[0] }

# ---------- fixture: a synthetic account, June 2026, form tracking lost 06-11..06-25 ----------
$script:FactsJson = @'
{"meta":{"tool":"Analyze-SwydoReport.ps1","factsVersion":4,"client":"Acme","currentPeriod":"2026-06-01..2026-06-30","previousPeriod":"2026-05-02..2026-05-31",
"period":{"measure":"month","startYm":"2026-06","endYm":"2026-06","calendarAligned":true},"compareBasis":"computed","hasComparison":true,
"periodResolved":{"current":{"start":"2026-06-01","end":"2026-06-30"},"previous":{"start":"2026-05-02","end":"2026-05-31"},"lengthDays":30},
"comparisonCaveats":[],"providers":[{"id":"gads","name":"Google Ads","category":"ads"}],"extractionComplete":true},
"platforms":[{"id":"gads","name":"Google Ads","category":"ads","hasComparison":true,
"headline":{"hasComparison":true,
"gads:a:clicks":{"metric":"Clicks","id":"gads:a:clicks","unit":null,"type":"number","current":1000,"previous":800,"hasComparison":true,"displayCurrent":"1,000","displayPrevious":"800","displayDelta":"+25.0%"},
"gads:a:impressions":{"metric":"Impressions","id":"gads:a:impressions","unit":null,"type":"number","current":5000,"previous":4000,"hasComparison":true,"displayCurrent":"5,000","displayPrevious":"4,000","displayDelta":"+25.0%"},
"gads:a:conversions":{"metric":"Conversions","id":"gads:a:conversions","unit":null,"type":"number","current":130,"previous":200,"hasComparison":true,"displayCurrent":"130","displayPrevious":"200","displayDelta":"-35.0%"},
"gads:a:conversion_rate":{"metric":"Conversion rate","id":"gads:a:conversion_rate","unit":"fraction","type":"percent","current":0.13,"previous":0.25,"hasComparison":true,"displayCurrent":"13.0%","displayPrevious":"25.0%","displayDelta":"-48.0%"},
"gads:a:cost_per_conversion":{"metric":"Cost / conversion","id":"gads:a:cost_per_conversion","unit":"micros","type":"currency","currency":"USD","current":5000000,"previous":3000000,"hasComparison":true,"displayCurrent":"$5.00","displayPrevious":"$3.00","displayDelta":"+66.7%"},
"gads:a:cost_micros":{"metric":"Cost","id":"gads:a:cost_micros","unit":"micros","type":"currency","currency":"USD","current":650000000,"previous":600000000,"hasComparison":true,"displayCurrent":"$650.00","displayPrevious":"$600.00","displayDelta":"+8.3%"}},
"breakdowns":[
{"widgetId":"wMonth","dimensions":["Month","Conversion action name"],"rowCount":1,"shown":1,"rows":[{"label":"2026-06","values":{"Conversions":{"display":"130","type":"number","hasComparison":false}}}]},
{"widgetId":"wAct","dimensions":["Conversion action name"],"rowCount":2,"shown":2,"rows":[
{"label":"Calls","values":{"Conversions":{"display":"120","type":"number","hasComparison":true,"displayPrevious":"120","delta":"0.0%"}}},
{"label":"Web form","values":{"Conversions":{"display":"10.0","type":"number","hasComparison":true,"displayPrevious":"80.0","delta":"-87.5%"}}}]}]}],
"findings":{"wins":[],"losses":[],"anomalies":[],"discrepancies":[],"dataGaps":[]}}
'@
function NewFacts(){ return ($script:FactsJson | ConvertFrom-Json) }
function NewSpec($over){
  $s = Resolve-FcSpec $null @{ declaredBy='client note ANN#1'; platform=''; metric=''; action='Web form'; outageStart='2026-06-11'; outageEnd='2026-06-25' }
  if($over){ foreach($k in $over.Keys){ $s[$k] = $over[$k] } }
  return $s
}
function NewLedger($client,$rates,$cpas){
  # months 2026-03.. in order
  $cells = New-Object PSObject; $i = 0
  foreach($r in $rates){ $mk = '2026-{0:D2}' -f (3+$i); $cells | Add-Member -NotePropertyName ("gads|gads:a:conversion_rate|b|" + $mk) -NotePropertyValue ([pscustomobject]@{ providerId='gads'; metricId='gads:a:conversion_rate'; month=$mk; value=$r; unit='fraction' }); $i++ }
  $i = 0
  foreach($c in $cpas){ $mk = '2026-{0:D2}' -f (3+$i); $cells | Add-Member -NotePropertyName ("gads|gads:a:cost_per_conversion|b|" + $mk) -NotePropertyValue ([pscustomobject]@{ providerId='gads'; metricId='gads:a:cost_per_conversion'; month=$mk; value=$c; unit='micros' }); $i++ }
  return [pscustomobject]@{ ledgerVersion=1; client=$client; cells=$cells }
}

Write-Host '== helpers =='
Ok ((Format-FcCount 40.26) -eq '40.3') 'count is one decimal'
Ok ((Format-FcCount 61) -eq '61.0') 'a whole estimate still shows a decimal (stays a measure token for the closer)'
Ok ((Format-FcCount 1587.66) -eq '1,587.7') 'count thousands separator'
Ok ((Format-FcPercent 0.3276) -eq '32.8%') 'percent from fraction'
Ok ((Format-FcMoney 6.251 'USD') -eq '$6.25') 'money USD'
Ok ((Format-FcMoney 6.251 'EUR') -eq ([string][char]0x20AC + '6.25')) 'money EUR symbol'
Eqd (ConvertFrom-FcDisplay '1,234.5') 1234.5 'parse display thousands'
Eqd (ConvertFrom-FcDisplay '$12.30') 12.3 'parse display currency'
Ok ($null -eq (ConvertFrom-FcDisplay 'None')) 'parse non-number -> null'
Ok ((Get-FcDays (ConvertTo-FcDate '2026-06-01') (ConvertTo-FcDate '2026-06-30')) -eq 30) 'inclusive day count'
Ok ($null -eq (ConvertTo-FcDate '06/01/2026')) 'non-ISO date rejected'
Ok ((@(Get-FcPrevMonths '2026-02' 3) -join ',') -eq '2025-11,2025-12,2026-01') 'trailing months cross a year boundary'

Write-Host '== spec: an outage is declared, never inferred =='
Throws { Resolve-FcSpec $null @{ declaredBy=''; action='Web form'; outageStart='2026-06-11'; outageEnd='2026-06-25' } } 'no declaration source' 'missing -DeclaredBy refuses'
Throws { Resolve-FcSpec $null @{ declaredBy='user'; action='Web form'; outageStart=''; outageEnd='' } } 'window is not declared' 'missing outage dates refuses'
Throws { Resolve-FcSpec $null @{ declaredBy='user'; outageStart='2026-06-25'; outageEnd='2026-06-11' } } 'before' 'reversed outage dates refuse'
Throws { Resolve-FcSpec $null @{ declaredBy='user'; outageStart='June 11'; outageEnd='2026-06-25' } } 'yyyy-MM-dd' 'non-ISO outage date refuses'
$sp = Resolve-FcSpec $null @{ declaredBy='user'; action='A one; B two ;'; outageStart='2026-06-11'; outageEnd='2026-06-25' }
Ok ($sp.actions.Count -eq 2 -and $sp.actions[1] -eq 'B two') 'flag -Action splits on ; and trims'
Ok ($sp.metric -eq 'Conversions') 'metric defaults to Conversions'
$specObj = '{"declaredBy":"client note ANN#2","actions":["X"],"outage":{"start":"2026-06-02","end":"2026-06-03"},"metricNames":{"clicks":"Link clicks"}}' | ConvertFrom-Json
$sp2 = Resolve-FcSpec $specObj @{ declaredBy='user'; action='Y'; outageStart='2026-06-11'; outageEnd='2026-06-25' }
Ok ($sp2.declaredBy -eq 'client note ANN#2' -and $sp2.actions[0] -eq 'X' -and $sp2.outageStart -eq '2026-06-02') 'spec file wins over flags'
Ok ($sp2.names.clicks -eq 'Link clicks' -and $sp2.names.cost -eq 'Cost') 'spec overrides one metric name, keeps the other defaults'

Write-Host '== per-action estimate =='
$b = Get-FcEstimates (NewFacts) $null (NewSpec $null) 6 3 '2026-07-01T00:00:00Z'
Ok ($b.label -eq 'Estimates (modeled)' -and $b.tool -eq 'Invoke-SwydoForecast.ps1') 'block identifies itself'
Ok ($b.declared.declaredBy -eq 'client note ANN#1' -and $b.declared.trackedDays -eq 15 -and $b.declared.outageDays -eq 15 -and $b.declared.periodDays -eq 30) 'declaration + day counts recorded'
Ok (@($b.items).Count -eq 4 -and @($b.refused).Count -eq 0) 'action + total + rate + cost-per-conversion, nothing refused'
$e1 = $b.items[0]
Ok ($e1.eid -eq 'EST#1' -and $e1.kind -eq 'action' -and $e1.action -eq 'Web form') 'EST#1 is the action'
Eqd (Method $e1 'prior-rate-clicks').value 100 'prior-rate-clicks = 80/800*1000'
Eqd (Method $e1 'prior-rate-impressions').value 100 'prior-rate-impressions = 80/4000*5000'
Eqd (Method $e1 'unaffected-ratio').value 80 'unaffected-ratio = 80*120/120'
Eqd (Method $e1 'run-rate').value 20 'run-rate = 10/15*30'
Eqd $e1.low 20 'low = smallest method'
Eqd $e1.high 100 'high = largest method'
Eqd $e1.value 56.6667 'base = 15/30 x run-rate 20 + 15/30 x prior-level mean (100+100+80)/3'
Ok ($e1.uncertainty -match 'weight of 50\.0%') 'uncertainty states the tracked-share weight'
$rw = Get-FcEstimates (NewFacts) $null (NewSpec @{ outageStart='2026-06-11'; outageEnd='2026-06-30' }) 6 3
Eqd (Method $rw.items[0] 'run-rate').value 30 'longer outage: run-rate = 10/10*30'
Eqd $rw.items[0].value 72.2222 'longer outage: base = 10/30 x 30 + 20/30 x 93.33 (less tracked => leans on prior level)'
$rw = Get-FcEstimates (NewFacts) $null (NewSpec @{ outageStart='2026-06-11'; outageEnd='2026-06-13' }) 6 3
Eqd $rw.items[0].value 19.3333 'short outage: base = 27/30 x 11.11 + 3/30 x 93.33 (mostly tracked => leans on the observed pace)'
Eqd (Resolve-FcRange @(@{ value=10; family='prior-level' },@{ value=30; family='prior-level' }) 0.9).base 20 'one family only: base is its mean, the weight is ignored'
Ok ($e1.display -eq '56.7' -and $e1.displayLow -eq '20.0' -and $e1.displayHigh -eq '100.0') 'display strings'
Ok ($e1.measuredDisplay -eq '10.0') 'the recorded figure is carried beside the estimate'
Ok ($e1.statement -match '^Modeled estimate' -and $e1.statement -match '56\.7' -and $e1.statement -match '10\.0 were actually recorded') 'statement labels itself and names the recorded value'
Ok ($e1.uncertainty -match 'disagree widely' -and $e1.uncertainty -match 'small sample' -and $e1.uncertainty -match 'not a measurement') 'uncertainty: divergence + small sample + not-a-measurement'
$m = Method $e1 'prior-rate-clicks'
Ok (@($m.inputs).Count -eq 3 -and @($m.inputs | Where-Object { -not $_.source -or -not $_.display }).Count -eq 0) 'every method input has a display and a source'
Ok ($m.inputs[1].source -match "headline 'Clicks' displayPrevious" -and $m.inputs[1].display -eq '800') 'input source names the facts cell'
Ok ($m.formula -match '80\.0' -and $m.formula -match '1,000' -and $m.assumption) 'formula in plain words + stated assumption'

Write-Host '== account total + dependent metrics =='
$e2 = $b.items[1]; $e3 = $b.items[2]; $e4 = $b.items[3]
Ok ($e2.kind -eq 'total' -and $e2.display -eq '176.7' -and $e2.displayLow -eq '140.0' -and $e2.displayHigh -eq '220.0') 'total = measured - recorded affected + estimated'
Ok ($e2.measuredDisplay -eq '130') 'total carries the measured headline'
Ok ($e3.metric -eq 'Conversion rate' -and $e3.type -eq 'percent' -and $e3.display -eq '17.7%' -and $e3.displayLow -eq '14.0%' -and $e3.displayHigh -eq '22.0%') 'conversion rate from the estimated total'
Ok ($e4.metric -eq 'Cost / conversion' -and $e4.type -eq 'currency' -and $e4.display -eq '$3.68') 'cost per conversion base'
Ok ($e4.displayLow -eq '$2.95' -and $e4.displayHigh -eq '$4.64') 'cost per conversion range is inverted (most conversions -> lowest cost)'
Ok (@($e2.skippedMethods | Where-Object { $_.id -match 'ledger' -and $_.reason -match 'no ledger' }).Count -eq 1) 'no ledger -> the cross-check is listed as skipped with the reason'

Write-Host '== refusals (fail closed, with a stated reason) =='
$f = NewFacts; $f.meta.compareBasis = 'untrusted'
$r = Get-FcEstimates $f $null (NewSpec $null)
Ok (@($r.items).Count -eq 0) 'untrusted comparison: only the run-rate is computable -> no estimate'
Ok (@($r.refused | Where-Object { $_.reason -match 'needs at least two' -and $_.reason -match 'not trusted' }).Count -eq 1) 'refusal says a range needs two methods and why the others dropped'
$r = Get-FcEstimates (NewFacts) $null (NewSpec @{ outageStart='2026-06-02'; outageEnd='2026-06-30' }) 6 3
Ok ($null -eq (Method $r.items[0] 'run-rate') -and (Skipped $r.items[0] 'run-rate').reason -match 'only 1 tracked day') 'too few tracked days: run-rate skipped, prior-level methods still give a range'
Ok ($r.items[0].uncertainty -match 'understates') 'prior-level-only estimate says its range understates the uncertainty'
Throws { Get-FcEstimates (NewFacts) $null (NewSpec @{ outageStart='2026-07-02'; outageEnd='2026-07-09' }) } 'does not touch the report period' 'outage outside the period refuses'
Throws { Get-FcEstimates (NewFacts) $null (NewSpec @{ actions=@('Nope') }) } 'every declared action' 'unknown action refuses and lists the rows'
$f = NewFacts; $f.meta.extractionComplete = $false
Throws { Get-FcEstimates $f $null (NewSpec $null) } 'extractionComplete=false' 'incomplete extraction refuses'
$f = NewFacts; $f.platforms[0].breakdowns[1].rowCount = 5
$r = Get-FcEstimates $f $null (NewSpec $null)
Ok ((Skipped $r.items[0] 'unaffected-ratio').reason -match 'shows 2 of 5 rows') 'truncated breakdown: unaffected-ratio skipped'
Ok (@($r.refused | Where-Object { $_.target -match 'account total' -and $_.reason -match '2 of 5' }).Count -eq 1 -and @($r.items).Count -eq 1) 'truncated breakdown: total (and its dependents) refused'
$f = NewFacts; $f.platforms[0].headline.'gads:a:conversions'.current = 300; $f.platforms[0].headline.'gads:a:conversions'.displayCurrent = '300'
$r = Get-FcEstimates $f $null (NewSpec $null)
Ok (@($r.refused | Where-Object { $_.reason -match 'rows sum to 130\.0 but the headline is 300' }).Count -eq 1) 'rows that do not reconcile to the headline: total refused'
$f = NewFacts; $f.platforms[0].headline.'gads:a:conversion_rate'.current = 0.5
$r = Get-FcEstimates $f $null (NewSpec $null)
Ok (@($r.refused | Where-Object { $_.target -match 'Conversion rate' -and $_.reason -match 'not conversions / clicks' }).Count -eq 1) 'conversion-rate identity fails -> that metric refused'
Ok (@($r.items | Where-Object { $_.metric -eq 'Cost / conversion' }).Count -eq 1) '...while cost per conversion is still estimated'
$f = NewFacts; $f.platforms[0].headline.'gads:a:cost_per_conversion'.current = 9000000
$r = Get-FcEstimates $f $null (NewSpec $null)
Ok (@($r.refused | Where-Object { $_.target -match 'Cost / conversion' -and $_.reason -match 'not cost / conversions' }).Count -eq 1) 'cost-per-conversion identity fails -> refused'
$f = NewFacts; $f.platforms += $f.platforms[0]
Throws { Get-FcEstimates $f $null (NewSpec $null) } 'say which one with -Platform' 'two platforms and no -Platform refuses'

Write-Host '== floor + supplied partial window =='
$f = NewFacts; $f.platforms[0].breakdowns[1].rows[1].values.Conversions.display = '90.0'
$r = Get-FcEstimates $f $null (NewSpec $null)
Ok ((Method $r.items[0] 'unaffected-ratio').value -eq 90 -and (Method $r.items[0] 'unaffected-ratio').note -match 'held at the recorded value') 'a method below the recorded value is floored to it, and says so'
$pspec = NewSpec @{ partials=@(@{ action='Web form'; value=9; start='2026-06-01'; end='2026-06-09'; source='daily pull of the first nine days' }) }
$r = Get-FcEstimates (NewFacts) $null $pspec
Eqd (Method $r.items[0] 'run-rate').value 30 'partial window run-rate = 9/9*30'
Ok ((Method $r.items[0] 'run-rate').inputs[0].source -match 'daily pull of the first nine days') 'partial observation source is recorded'
$pspec = NewSpec @{ partials=@(@{ action='Web form'; value=9; start='2026-06-05'; end='2026-06-12'; source='x' }) }
$r = Get-FcEstimates (NewFacts) $null $pspec
Ok ((Skipped $r.items[0] 'run-rate').reason -match 'overlaps the declared outage') 'a partial window overlapping the outage is rejected, not silently replaced'
$pspec = NewSpec @{ partials=@(@{ action='Web form'; value=9; start='2026-06-01'; end='2026-06-09' }) }
$r = Get-FcEstimates (NewFacts) $null $pspec
Ok ((Skipped $r.items[0] 'run-rate').reason -match 'names no source') 'a partial observation without a source is rejected'

Write-Host '== ledger history =='
$led = NewLedger 'Acme' @(0.18,0.20,0.22) @(4000000,5000000,6000000)
$r = Get-FcEstimates (NewFacts) $led (NewSpec $null) 3 3
$cc = @($r.items[1].crossChecks)[0]
Ok ($cc.id -eq 'ledger-rate' -and $cc.display -eq '200.0' -and $cc.withinRange -eq $true) 'ledger cross-check on the total: 20.0% x 1,000 clicks, inside the range'
Ok ($cc.explanation -match '20\.0%' -and $cc.explanation -match '2026-03 to 2026-05' -and $cc.explanation -match 'a check, not part of the estimate') 'cross-check explains itself'
Ok ($r.items[1].display -eq '176.7') 'the cross-check does not move the estimate'
Ok (@($r.items[3].crossChecks)[0].display -eq '$5.00') 'ledger cost-per-conversion context'
$r = Get-FcEstimates (NewFacts) (NewLedger 'Other Client' @(0.18,0.20,0.22) @()) (NewSpec $null) 3 3
Ok (@($r.items[1].crossChecks).Count -eq 0 -and @($r.items[1].skippedMethods | Where-Object { $_.reason -match 'different client' }).Count -eq 1) 'a ledger for another client is refused'
$r = Get-FcEstimates (NewFacts) (NewLedger 'Acme' @(0.02,0.20,0.22) @()) (NewSpec $null) 3 3
Ok (@($r.items[1].skippedMethods | Where-Object { $_.reason -match 'too unstable to average' -and $_.reason -match '2\.0% to 22\.0%' }).Count -eq 1) 'an unstable history (setup change) is refused, with its range'
$r = Get-FcEstimates (NewFacts) (NewLedger 'Acme' @(0.18,0.20) @()) (NewSpec $null) 6 3
Ok (@($r.items[1].skippedMethods | Where-Object { $_.reason -match 'only 2 of the trailing 6 months' }).Count -eq 1) 'fewer than 3 history months is refused'
$r = Get-FcEstimates (NewFacts) $led (NewSpec @{ excludeMonths=@('2026-05') }) 3 3
Ok (@($r.items[1].skippedMethods | Where-Object { $_.reason -match 'only 2 of the trailing 3' }).Count -eq 1) 'excludeMonths removes a month from the history'
# whole-metric mode: the ledger rate is a METHOD
$whole = NewSpec @{ actions=@() }
$r = Get-FcEstimates (NewFacts) $led $whole 3 3
$w = $r.items[0]
Ok ($w.kind -eq 'total' -and $null -eq $w.action) 'no -Action => the whole metric is the target'
Eqd (Method $w 'prior-rate-clicks').value 250 'whole metric prior-rate-clicks = 200/800*1000'
Eqd (Method $w 'ledger-rate').value 200 'whole metric ledger-rate = 20.0% x 1,000'
Eqd (Method $w 'run-rate').value 260 'whole metric run-rate = 130/15*30'
Ok ($null -eq (Method $w 'unaffected-ratio')) 'whole metric has no unaffected-ratio method'
Eqd $w.value 246.6667 'whole metric base = mean(mean(250,250,200), 260)'

Write-Host '== splice =='
$txt = $script:FactsJson
$out = Add-FcBlock $txt $b
$o = $out | ConvertFrom-Json
Ok ($out.StartsWith($txt.TrimEnd().Substring(0,$txt.TrimEnd().Length-1))) 'measured facts are byte-preserved ahead of the block'
Ok (@($o.estimates.items).Count -eq 4 -and $o.meta.client -eq 'Acme') 'spliced text parses with the block'
$out2 = Add-FcBlock $out $b
Ok ($out2 -eq $out) 're-running replaces the block (idempotent)'
$withOther = $out.TrimEnd().Substring(0,$out.TrimEnd().Length-1) + ',"derivedMetrics":{"note":"has \"estimates\": inside a string"}}'
$out3 = Add-FcBlock $withOther $b
$o3 = $out3 | ConvertFrom-Json
Ok (([regex]::Matches($out3,'"estimates":\{"tool"')).Count -eq 1 -and $null -ne $o3.derivedMetrics -and $null -ne $o3.estimates) 'coexists with another tool''s block, wherever ours sat'
Ok ((@($o3.PSObject.Properties | ForEach-Object { $_.Name }) -join ',') -eq 'meta,platforms,findings,derivedMetrics,estimates') 'ours is re-appended last; the other block is untouched'
Ok ($null -eq (Find-FcTopLevelMember '{"a":{"estimates":1},"b":"estimates"}' 'estimates')) 'a nested key / string value is not mistaken for the top-level member'

Write-Host '== closer: estimates stay labelled and in their own section =='
$factsEst = $out | ConvertFrom-Json
$head = "## Google Ads`n<!-- platform:gads -->`n`n- Clicks were 1,000 against 800.`n- Conversions were 130.`n`n"
$sec  = "## Estimates (modeled)`n`nThese figures are modeled, not measured.`n`n" +
        "- Web form: an estimated 56.7 conversions (range 20.0 to 100.0) against the 10.0 recorded. <!-- estimate:EST#1 -->`n" +
        "- Total conversions: an estimated 176.7 (range 140.0 to 220.0). <!-- estimate:EST#2 -->`n" +
        "- Cost per conversion: an estimated `$3.68 (range `$2.95 to `$4.64) against the `$5.00 measured. <!-- estimate:EST#4 -->`n`n"
$recs = "## Recommendations`n`n- Fix the form tracking.`n"
$good = Invoke-Closer ($head + $sec + $recs) $factsEst
Ok ($good.violations.Count -eq 0) ("a correct estimates section passes (" + (@($good.violations | ForEach-Object { $_.type + ':' + $_.snippet }) -join ' ; ') + ")")
Ok ((Strip-Anchors ($head + $sec + $recs)) -match 'an estimated 56\.7') 'the label survives anchor stripping'
$r1 = Invoke-Closer ($head + "Conversions would have been 176.7.`n`n" + $sec + $recs) $factsEst
Ok ((HasT $r1 'untraceable-number') -and (HasT $r1 'estimate-misuse')) 'an estimate number in a platform section is rejected as misuse'
$r2 = Invoke-Closer ($head + "- An estimated 176.7 conversions (range 140.0 to 220.0). <!-- estimate:EST#2 -->`n`n" + $sec + $recs) $factsEst
Ok (HasT $r2 'estimate-outside-section') 'an anchored estimate outside the section is rejected'
Ok (HasT $r2 'untraceable-number') '...and its numbers do not trace there even with the anchor'
$r3 = Invoke-Closer ($head + ($sec -replace 'an estimated 176\.7','176.7') + $recs) $factsEst
Ok (HasT $r3 'estimate-label-missing') 'an anchored line without a visible estimate word is rejected'
$r4 = Invoke-Closer ($head + ($sec -replace ' \(range 140\.0 to 220\.0\)','') + $recs) $factsEst
Ok ((@($r4.violations | Where-Object { $_.type -eq 'estimate-range-missing' })).Count -eq 2) 'an estimate cited without its range is rejected (low and high)'
$r5 = Invoke-Closer ($head + $sec + $recs + "- Plan for 176.7 conversions next month.`n") $factsEst
Ok (HasT $r5 'estimate-misuse') 'an estimate number inside Recommendations is rejected even though that section is not traced'
$r5b = Invoke-Closer ($head + $sec + $recs + "- Hold cost per conversion under `$4.00 and aim for 1,000 clicks.`n") $factsEst
Ok ($r5b.violations.Count -eq 0) 'ordinary recommendation targets and measured figures are still allowed'
$r6 = Invoke-Closer ($head + $recs) $factsEst
Ok (HasT $r6 'estimates-not-surfaced') 'a produced estimate that the report drops is rejected'
$r7 = Invoke-Closer ($head + ($sec -replace 'These figures are modeled, not measured\.','These are projections.') + $recs) $factsEst
Ok (HasT $r7 'estimate-disclosure-missing') 'the section must say the figures are not measured'
$r8 = Invoke-Closer ($head + ($sec -replace 'EST#4','EST#9') + $recs) $factsEst
Ok (HasT $r8 'unknown-estimate-anchor') 'an unknown estimate anchor is rejected'
$r9 = Invoke-Closer ($head + "## Estimates (modeled)`n`nNot measured.`n`n- An estimated 999.9 conversions (range 20.0 to 100.0). <!-- estimate:EST#1 -->`n`n" + $recs) $factsEst
Ok (HasT $r9 'untraceable-number') 'a fabricated number on an estimate line still fails to trace'
$plain = Invoke-Closer ($head + $recs) (NewFacts)
Ok ($plain.violations.Count -eq 0) 'facts without an estimates block verify exactly as before (rules inert)'
$stray = Invoke-Closer ($head + "- An estimated 56.7. <!-- estimate:EST#1 -->`n" + $recs) (NewFacts)
Ok (HasT $stray 'unknown-estimate-anchor') 'an estimate anchor with no estimates block is rejected'

function RunTool([string[]]$toolArgs){
  # PS 5.1 turns a native command's stderr into a terminating error under EAP=Stop + 2>&1, so relax it
  # for the call only. -> @{ code; out }
  $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  try { $o = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $script:ToolPath @toolArgs 2>&1 | Out-String; $c = $LASTEXITCODE }
  finally { $ErrorActionPreference = $old }
  return @{ code=$c; out=$o }
}
Write-Host '== CLI: fail-closed exits, BOM-less output =='
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('swydee-fc-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
  $enc = New-Object Text.UTF8Encoding($false)
  $fp = Join-Path $tmp 'a.facts.json'
  [IO.File]::WriteAllText($fp,$script:FactsJson,$enc)
  $run = RunTool @('-Facts',$fp,'-DeclaredBy','user','-Action','Web form','-OutageStart','2026-06-11','-OutageEnd','2026-06-25')
  Ok ($run.code -eq 0) ("CLI success exits 0: " + $run.out)
  $bytes = [IO.File]::ReadAllBytes($fp)
  Ok (-not ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB)) 'output is BOM-less UTF-8'
  Ok (@(([IO.File]::ReadAllText($fp) | ConvertFrom-Json).estimates.items).Count -eq 4) 'facts updated in place with the estimates block'
  Ok (-not (Test-Path ($fp + '.fc-tmp'))) 'no temp file left behind'
  $fp2 = Join-Path $tmp 'b.facts.json'
  [IO.File]::WriteAllText($fp2,$script:FactsJson,$enc)
  $before = [IO.File]::ReadAllText($fp2)
  $run = RunTool @('-Facts',$fp2,'-Action','Web form','-OutageStart','2026-06-11','-OutageEnd','2026-06-25')
  Ok ($run.code -eq 2 -and [IO.File]::ReadAllText($fp2) -eq $before) 'no -DeclaredBy => exit 2, nothing written'
  $run = RunTool @('-Facts',$fp2,'-DeclaredBy','user','-Action','Web form','-OutageStart','2026-06-01','-OutageEnd','2026-06-30','-Metric','Phone calls')
  Ok ($run.code -eq 2 -and [IO.File]::ReadAllText($fp2) -eq $before) 'a metric with no action breakdown => exit 2, nothing written'
  $fp3 = Join-Path $tmp 'c.facts.json'
  [IO.File]::WriteAllText($fp3,($script:FactsJson -replace '"compareBasis":"computed"','"compareBasis":"untrusted"'),$enc)
  $before3 = [IO.File]::ReadAllText($fp3)
  $run = RunTool @('-Facts',$fp3,'-DeclaredBy','user','-Action','Web form','-OutageStart','2026-06-11','-OutageEnd','2026-06-25')
  Ok ($run.code -eq 1 -and [IO.File]::ReadAllText($fp3) -eq $before3) 'everything refused => exit 1, nothing written'
  Ok (($run.out -match 'REFUSED')) 'the refusal reason is printed'
  $fp4 = Join-Path $tmp 'raw.json'
  [IO.File]::WriteAllText($fp4,('{"meta":{"shareKey":"k","tool":"Analyze-SwydoReport.ps1"},"platforms":[]}'),$enc)
  $run = RunTool @('-Facts',$fp4,'-DeclaredBy','user','-OutageStart','2026-06-11','-OutageEnd','2026-06-25')
  Ok ($run.code -eq 2 -and ($run.out -match 'share credential')) 'a credential-bearing input is refused before it is parsed'
  $fp5 = Join-Path $tmp 'trend.json'
  [IO.File]::WriteAllText($fp5,('{"meta":{"tool":"Analyze-SwydoTrend.ps1"},"platforms":[]}'),$enc)
  $run = RunTool @('-Facts',$fp5,'-DeclaredBy','user','-OutageStart','2026-06-11','-OutageEnd','2026-06-25')
  Ok ($run.code -eq 2) 'a non-Analyze facts file is refused'
} finally { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }

# =====================================================================================================
# Review round 1 (memory/builds/aModeledGap/reviews): every confirmed finding gets a test that fails
# without its fix. Ids in the names (C = closer, M = computation, D = docs/tests) match the review file.
# =====================================================================================================
function CloneEst(){ return ($out | ConvertFrom-Json) }

Write-Host '== review: closer rules =='
$rv = Invoke-Closer ($head + "<!-- note`n-->`n" + $sec + $recs) $factsEst
Ok (HasT $rv 'multiline-comment') 'C1 a comment spanning lines is rejected when the facts carry estimates'
$hidden = $head + "<!-- x`n## Estimates (modeled) <!-- y -->`n- Conversions: 176.7 (140.0 to 220.0). <!-- estimate:EST#2 --> <!-- estimated, not measured`n-->`n`n" + $recs
Ok (HasT (Invoke-Closer $hidden $factsEst) 'multiline-comment') 'C1 a section header / label / disclosure hidden in a multi-line comment cannot pass'
$rv = Invoke-Closer ($head + "## Estimates (modeled)`n`nNot measured.`n`n### An estimated 176.7 (range 140.0 to 220.0) <!-- estimate:EST#2 -->`n`n" + $recs) $factsEst
Ok (HasT $rv 'estimate-anchor-on-heading') 'C2 an estimate anchor on a heading is rejected'
Ok (@($rv.violations | Where-Object { $_.type -eq 'estimates-not-surfaced' -and $_.snippet -eq 'EST#2' }).Count -eq 1) 'C2 ...and a heading does not count as presenting the estimate'
Ok (Test-EstimateSection 'Estimates (modeled)') 'C3 the exact heading is the estimates section'
Ok (Test-EstimateSection 'Estimates (modelled) <!-- x -->') 'C3 spelling variant + trailing comment still match'
Ok (-not (Test-EstimateSection 'Google Ads <!-- platform:gads --> <!-- estimates modeled -->')) 'C3 a hidden comment cannot make another section the estimates section'
Ok (-not (Test-EstimateSection 'Key insights: our estimate and how we modeled it')) 'C3 a heading that merely mentions the words does not qualify'
Ok (-not (Test-EstimateSection 'Recommendations from our estimates (modeled)')) 'C3 extra words before the phrase do not qualify'
$rv = Invoke-Closer ($head + "## Key insights: our estimate and how we modeled it`n`nNot measured.`n`n- An estimated 176.7 (range 140.0 to 220.0). <!-- estimate:EST#2 -->`n`n" + $recs) $factsEst
Ok (HasT $rv 'estimate-outside-section') 'C3 an anchored estimate under a look-alike heading is outside the section'
$rv = Invoke-Closer ($head + $sec + $recs + "- Plan for about 57 web form conversions a month.`n") $factsEst
Ok (HasT $rv 'estimate-misuse') 'C4 a rounded estimate ("about 57" for 56.7) is rejected in Recommendations'
$rv = Invoke-Closer ($head + "- Without the gap, forms would have been roughly 57.`n`n" + $sec + $recs) $factsEst
Ok (HasT $rv 'estimate-misuse') 'C4 ...and in a platform section'
$rv = Invoke-Closer ($head + $sec + $recs + "- Review the top 5 campaigns over about 30 days, then about 20 ad groups.`n") $factsEst
Ok ($rv.violations.Count -eq 0) ('C4 ordinary small numbers still pass (' + (@($rv.violations | ForEach-Object { $_.type + ':' + $_.snippet }) -join ' ; ') + ')')
$rv = Invoke-Closer ($head + $sec + $recs + "- Aim for 100 web form conversions, hold cost per conversion under `$4 and move 18% of budget.`n") $factsEst
Ok ($rv.violations.Count -eq 0) ('C5 round targets (100, $4, 18%) are not mistaken for estimates (' + (@($rv.violations | ForEach-Object { $_.type + ':' + $_.snippet }) -join ' ; ') + ')')
$rv = Invoke-Closer ($head + ($sec -replace 'an estimated 56\.7 conversions \(range 20\.0 to 100\.0\)','an estimated 100.0 conversions (other methods gave 20.0)') + $recs) $factsEst
Ok (HasT $rv 'estimate-base-missing') 'C6 a method value presented as the estimate, without the base, is rejected'
$rv = Invoke-Closer ($head + ($sec -replace 'an estimated 176\.7 \(range 140\.0 to 220\.0\)\.','an estimated 176.7 (range 140.0 to 220.0), down from 200 last period.') + $recs) $factsEst
Ok (HasT $rv 'estimate-compared-to-previous') 'C7 an estimate compared with the previous period is rejected'
$rv = Invoke-Closer ($head + ($sec -replace 'an estimated 176\.7 \(range 140\.0 to 220\.0\)\.','an estimated 176.7 (range 140.0 to 220.0) versus prior results.') + $recs) $factsEst
Ok (HasT $rv 'estimate-compared-to-previous') 'C7 ...also phrased as versus prior'
foreach($phrase in @("These figures are modeled; they aren't measured.",'These are modeled rather than measured.','They were never measured by the platform.','These figures are modeled, not a measurement.')){
  $rv = Invoke-Closer ($head + ($sec -replace 'These figures are modeled, not measured\.',$phrase) + $recs) $factsEst
  Ok (-not (HasT $rv 'estimate-disclosure-missing')) "C9 disclosure wording accepted: $phrase"
}
$rv = Invoke-Closer ($head + ($sec -replace 'These figures are modeled, not measured\.','Form tracking was not working, so we measured only calls.') + $recs) $factsEst
Ok (HasT $rv 'estimate-disclosure-missing') 'C10 an unrelated "not ..., ... measured" sentence does not count as the disclosure'
$rv = Invoke-Closer ($head + "## Estimates (modeled)`n`nNot measured.`n`n### Web form`n`n- An estimated 56.7 (range 20.0 to 100.0). <!-- estimate:EST#1 -->`n`n" + $recs) $factsEst
Ok ((HasT $rv 'estimate-outside-section') -and (@($rv.violations | Where-Object { $_.detail -match 'no sub-headings' }).Count -gt 0)) 'C9 a sub-heading inside the section is rejected and the message says why'
$only1 = "## Estimates (modeled)`n`nThese figures are modeled, not measured.`n`n- Web form: an estimated 56.7 conversions (range 20.0 to 100.0). <!-- estimate:EST#1 -->`n`n"
$rv = Invoke-Closer ($head + $only1 + $recs) $factsEst
Ok (@($rv.violations | Where-Object { $_.type -eq 'estimates-not-surfaced' }).Count -eq 1 -and @($rv.violations | Where-Object { $_.type -eq 'estimates-not-surfaced' })[0].snippet -eq 'EST#2') 'C11 the total estimate must be presented too; the dependent ones (rate, cost per conversion) are optional'
$fe = CloneEst; $fe.estimates.items[3].eid = ''
Ok (HasT (Invoke-Closer ($head + $sec + $recs) $fe) 'estimate-item-without-eid') 'C11 an estimates item without an eid is flagged, not skipped'
$rv = Invoke-Closer ($head + ($sec -replace 'an estimated 176\.7 \(range 140\.0 to 220\.0\)\.','an estimated 176.7 (range 140.0 to 220.0), built on EST#1.') + $recs) $factsEst
Ok (HasT $rv 'estimate-internal-id-visible') 'D8 a visible internal id (EST#1) is rejected'
$allText = New-Object System.Text.StringBuilder
foreach($it in $b.items){ [void]$allText.AppendLine(($it.statement + ' ' + $it.uncertainty + ' ' + $it.method)); foreach($mm in $it.methods){ [void]$allText.AppendLine(($mm.formula + ' ' + $mm.name + ' ' + $mm.assumption)) }; foreach($cx in @($it.crossChecks)){ [void]$allText.AppendLine($cx.explanation) } }
Ok ($allText.ToString() -notmatch 'EST#') 'D8 no tool-written sentence a report may quote contains an internal id'
Ok (@($b.items | Where-Object { $_.kind -eq 'dependent' }).Count -eq 2 -and @($b.items | Where-Object { $_.kind -eq 'derived' }).Count -eq 0) 'D9 rate / cost-per-conversion items are kind=dependent ("derived" is another feature''s word)'
Ok ($b.items[2].methods[0].id -eq 'from-estimated-total' -and $b.items[2].methods[0].family -eq 'dependent') 'D9 their method id / family are renamed too'

# C8: the template's own block must lead to an accepted draft
$tplText = [IO.File]::ReadAllText("$PSScriptRoot\..\skill\report-template.md") -replace "`r`n","`n"
$tb = [regex]::Match($tplText,'(?ms)^## Estimates \(modeled\)   \[include.*?^## Recommendations').Value
Ok ($tb.Length -gt 200) 'C8 the template has an Estimates (modeled) block'
$tplBullets = @(($tb -split "`n- ") | Select-Object -Skip 1)
Ok ($tplBullets.Count -ge 3) 'C8 the template block models at least three bullets'
Ok (@($tplBullets | Where-Object { $_ -notmatch '<!-- estimate:EST#n -->' }).Count -eq 0) 'C8 every template bullet carries the estimate anchor'
Ok (@($tplBullets | Where-Object { (($_ -replace '<!--.*?-->','') -replace '`[^`]*`','') -notmatch $script:EstWordRx }).Count -eq 0) 'C8 every template bullet models a visible estimate word'
Ok (($tb -replace '\s+',' ') -match 'modeled, not measured') 'C8 the template gives the exact disclosure phrase'
$asTemplate = "## Estimates (modeled)`n`nThese figures are modeled, not measured. The client note states web form tracking was lost from 2026-06-11 to 2026-06-25.`n`n" +
  "- Web form: an estimated 56.7 conversions (range 20.0 to 100.0), against the 10.0 actually recorded. <!-- estimate:EST#1 -->`n" +
  "- How the web form estimate was built: the tracked-day pace gives an estimated 20.0, last period's level gives 80.0 to 100.0 depending on the method, and the base blends them. <!-- estimate:EST#1 -->`n" +
  "- The limit of this estimate: the tracked-day pace is only 21.4% of the prior-level figure and rests on 10.0 recorded, so treat it as indicative. <!-- estimate:EST#1 -->`n" +
  "- Total conversions: an estimated 176.7 (range 140.0 to 220.0), against the 130 actually recorded. <!-- estimate:EST#2 -->`n`n"
$rv = Invoke-Closer ($head + $asTemplate + $recs) $factsEst
Ok ($rv.violations.Count -eq 0) ('C8 a draft written the way the template shows passes (' + (@($rv.violations | ForEach-Object { $_.type + ':' + $_.snippet }) -join ' ; ') + ')')

Write-Host '== review: forecast tool =='
$sd = Resolve-FcSpec $null @{ declaredBy='user'; action='Web form; web form ;WEB FORM'; outageStart='2026-06-11'; outageEnd='2026-06-25' }
Ok ($sd.actions.Count -eq 1 -and $sd.actions[0] -eq 'Web form') 'M1 repeated actions are de-duplicated case-insensitively'
$rd = Get-FcEstimates (NewFacts) $null $sd 6 3
Ok (@($rd.items | Where-Object { $_.kind -eq 'action' }).Count -eq 1 -and $rd.items[1].display -eq '176.7') 'M1 ...so the total is not double-counted'
Throws { Resolve-FcSpec $null @{ declaredBy='user 0123456789abcdefghijKLMN'; outageStart='2026-06-11'; outageEnd='2026-06-25' } } 'key or token' 'C12 a key-shaped -DeclaredBy is refused'
$led3 = NewLedger 'Acme' @(0.18,0.20,0.22) @(4000000,5000000,6000000)
$f = NewFacts; $f.platforms[0].headline.'gads:a:clicks'.previous = $null
$r = Get-FcEstimates $f $led3 (NewSpec @{ actions=@() }) 3 3
Ok ($null -ne (Method $r.items[0] 'ledger-rate')) 'M2 clicks without a previous value: ledger-rate (needs current clicks only) still runs'
Ok ((Skipped $r.items[0] 'prior-rate-clicks').reason -match 'no previous-period clicks') 'M2 ...prior-rate-clicks is skipped with the true reason'
Ok (@($r.items | Where-Object { $_.metric -eq 'Conversion rate' }).Count -eq 1) 'M2 ...and the conversion rate is still derived'
$f = NewFacts; $f.platforms[0].headline.'gads:a:clicks'.current = $null
$r = Get-FcEstimates $f $led3 (NewSpec @{ actions=@() }) 3 3
Ok ($null -eq (Method $r.items[0] 'ledger-rate') -and @($r.items | Where-Object { $_.metric -eq 'Conversion rate' }).Count -eq 0) 'M2 no current clicks: ledger-rate and the derived rate are both off'
Throws { Get-FcEstimates (NewFacts) $null (NewSpec @{ actions=@(); metric='Conversion rate' }) } 'Only additive quantities' 'M3 a rate is refused as the incomplete metric'
Throws { Get-FcEstimates (NewFacts) $null (NewSpec @{ actions=@(); metric='Cost' }) } 'no coverage record' 'M3 a money figure the facts do not mark as summable is refused'
Throws { Get-FcEstimates (NewFacts) $null (NewSpec @{ partials=@(@{ action='Web forms'; value=9; start='2026-06-01'; end='2026-06-09'; source='x' }) }) } 'not a declared action' 'M4 a partial naming an undeclared action is an input error, not a silent fallback'
Throws { Get-FcEstimates (NewFacts) $null (NewSpec @{ actions=@(); partials=@(@{ action='Conversions'; value=60; start='2026-06-01'; end='2026-06-09'; source='x' }) }) } 'omit "action"' 'M4 whole-metric mode: a partial that names an action is an input error'
$r = Get-FcEstimates (NewFacts) $null (NewSpec @{ actions=@(); partials=@(@{ value=60; start='2026-06-01'; end='2026-06-10'; source='client count' }) }) 6 3
Eqd (Method $r.items[0] 'run-rate').value 180 'M4 whole-metric mode: a partial without an action is used (60/10*30)'
Ok ($r.items[0].uncertainty -match 'supplied tracked window, 10 of 30 days') 'M10 the weight is described as the supplied window''s share, with its days'
$r = Get-FcEstimates (NewFacts) $null (NewSpec @{ partials=@(@{ action='Web form'; value=4; start='2026-06-01'; end='2026-06-01'; source='x' }) }) 6 3
Ok ((Skipped $r.items[0] 'run-rate').reason -match 'only 1 day') 'M5 a one-day partial window is not extrapolated'
$r = Get-FcEstimates (NewFacts) $null (NewSpec @{ partials=@(@{ action='Web form'; value=4; start='2026-06-01'; end='2026-06-02'; source='x' },@{ action='Web form'; value=5; start='2026-06-03'; end='2026-06-05'; source='y' }) }) 6 3
Ok ((Skipped $r.items[0] 'run-rate').reason -match 'more than one partial') 'D4 two partials for one target are rejected'
$r = Get-FcEstimates (NewFacts) $null (NewSpec @{ partials=@(@{ action='Web form'; value=4; start='2026-05-25'; end='2026-05-30'; source='x' }) }) 6 3
Ok ((Skipped $r.items[0] 'run-rate').reason -match 'not inside the report period') 'D4 a partial window outside the period is rejected'
Ok (-not (Test-FcRateIdentity 0.00143 130 100000)) 'M6 low-rate account: a rate 10% off conversions/clicks fails the identity'
Ok (Test-FcRateIdentity 0.0013 130 100000) 'M6 low-rate account: the true rate passes'
Ok (Test-FcRateIdentity 0.13 130.4 1000) 'M6 a rounding-sized difference passes'
Ok (-not (Test-FcRateIdentity 0.13 130 0)) 'M6 zero clicks is unverified'
Ok (-not (Test-FcRateIdentity $null 130 1000)) 'M6 a missing rate is unverified'
$r = Get-FcEstimates (NewFacts) $null (NewSpec @{ outageStart='2026-06-01'; outageEnd='2026-06-30' }) 6 0
Ok ((Skipped $r.items[0] 'run-rate').reason -match 'only 0 tracked day') 'M8 zero tracked days: run-rate is skipped even with a minimum of 0'
Ok (@($r.items | Where-Object { [double]::IsNaN([double]$_.value) -or [double]::IsInfinity([double]$_.high) -or [double]::IsNaN([double]$_.low) }).Count -eq 0) 'M8 ...and no NaN / Infinity is produced'
$f = NewFacts; $f.platforms[0].headline.'gads:a:conversion_rate'.current = 0.5
$r = Get-FcEstimates $f $led3 (NewSpec @{ actions=@() }) 3 3
Ok ((Skipped $r.items[0] 'ledger-rate').reason -match 'not conversions / clicks') 'M11 whole-metric: ledger-rate is skipped when this report''s rate is not conversions/clicks'
$r = Get-FcEstimates $f $led3 (NewSpec $null) 3 3
Ok (@($r.items[1].crossChecks).Count -eq 0 -and @($r.items[1].skippedMethods | Where-Object { $_.reason -match 'not conversions / clicks' }).Count -eq 1) 'M11 per-action: the ledger cross-check is skipped for the same reason'
$f = NewFacts; $f.meta.hasComparison = $false
$r = Get-FcEstimates $f $null (NewSpec $null)
Ok (@($r.items).Count -eq 0 -and @($r.refused | Where-Object { $_.reason -match 'not trusted' }).Count -eq 1) 'D4 meta.hasComparison=false disables the prior-level methods'
$ledDup = NewLedger 'Acme' @(0.18,0.20,0.22) @()
$ledDup.cells | Add-Member -NotePropertyName 'gads|gads:a:conversion_rate|OTHERBASIS|2026-04' -NotePropertyValue ([pscustomobject]@{ providerId='gads'; metricId='gads:a:conversion_rate'; month='2026-04'; value=0.21; unit='fraction' })
$r = Get-FcEstimates (NewFacts) $ledDup (NewSpec $null) 3 3
Ok (@($r.items[1].skippedMethods | Where-Object { $_.reason -match 'more than one series' }).Count -eq 1) 'D4 two ledger series for one month are refused as ambiguous'
$f = NewFacts; $f.meta.period.calendarAligned = $false
$r = Get-FcEstimates $f $led3 (NewSpec $null) 3 3
Ok (@($r.items[1].skippedMethods | Where-Object { $_.reason -match 'not one calendar month' }).Count -eq 1) 'D4 a non-calendar period does not use monthly ledger history'
$r = Get-FcEstimates (NewFacts) $null (NewSpec @{ outageStart='2026-05-20'; outageEnd='2026-06-10' }) 6 3
Ok ($r.declared.outageDays -eq 10 -and $r.declared.trackedDays -eq 20) 'D4 an outage starting before the period is clipped to it'
$r = Get-FcEstimates (NewFacts) $null (NewSpec @{ outageStart='2026-06-21'; outageEnd='2026-07-15' }) 6 3
Ok ($r.declared.outageDays -eq 10 -and $r.declared.trackedDays -eq 20) 'D4 an outage ending after the period is clipped to it'

Write-Host '== review: CLI =='
$tmp2 = Join-Path ([IO.Path]::GetTempPath()) ('swydee-fc2-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp2 | Out-Null
try {
  $enc = New-Object Text.UTF8Encoding($false)
  $std = @('-DeclaredBy','user','-Action','Web form','-OutageStart','2026-06-11','-OutageEnd','2026-06-25')
  $good = Join-Path $tmp2 'good.facts.json'; [IO.File]::WriteAllText($good,$script:FactsJson,$enc)
  $bad = Join-Path $tmp2 'bad.json'; [IO.File]::WriteAllText($bad,'{"meta": oops',$enc)
  $run = RunTool (@('-Facts',$bad) + $std)
  Ok ($run.code -eq 2 -and $run.out -match 'not valid JSON') 'M7 unparseable facts => exit 2 (exit 1 means "refused")'
  $run = RunTool (@('-Facts',$good,'-Ledger',$bad,'-OutFile',(Join-Path $tmp2 'o1.json')) + $std)
  Ok ($run.code -eq 2 -and $run.out -match 'ledger file is not valid JSON') 'M7 unparseable ledger => exit 2'
  $run = RunTool (@('-Facts',$good,'-Spec',$bad,'-OutFile',(Join-Path $tmp2 'o2.json')) + $std)
  Ok ($run.code -eq 2 -and $run.out -match 'spec file is not valid JSON') 'M7 unparseable spec => exit 2'
  $credSpec = Join-Path $tmp2 'cred.spec.json'; [IO.File]::WriteAllText($credSpec,'{"declaredBy":"user","note":"https://swy.do/shares/FAKEFAKE"}',$enc)
  $run = RunTool (@('-Facts',$good,'-Spec',$credSpec,'-OutFile',(Join-Path $tmp2 'o3.json')) + $std)
  Ok ($run.code -eq 2 -and $run.out -match 'spec file carries a share credential') 'C12 a credential-bearing spec file is refused before it is parsed'
  $credLed = Join-Path $tmp2 'cred.ledger.json'; [IO.File]::WriteAllText($credLed,'{"client":"Acme","shareKey":"x","cells":{}}',$enc)
  $run = RunTool (@('-Facts',$good,'-Ledger',$credLed,'-OutFile',(Join-Path $tmp2 'o4.json')) + $std)
  Ok ($run.code -eq 2 -and $run.out -match 'ledger file carries a share credential') 'D4 a credential-bearing ledger is refused'
  $o5 = Join-Path $tmp2 'o5.json'
  $run = RunTool @('-Facts',$good,'-OutFile',$o5,'-DeclaredBy','see swy.do/shares/abc','-Action','Web form','-OutageStart','2026-06-11','-OutageEnd','2026-06-25')
  Ok ($run.code -eq 2 -and $run.out -match 'output would carry a share credential' -and -not (Test-Path $o5)) 'D4 the output credential gate stops a share link from being written'
  $trend = Join-Path $tmp2 'trend.facts.json'; [IO.File]::WriteAllText($trend,($script:FactsJson -replace '"tool":"Analyze-SwydoReport.ps1"','"tool":"Analyze-SwydoTrend.ps1"'),$enc)
  $run = RunTool (@('-Facts',$trend) + $std)
  Ok ($run.code -eq 2 -and $run.out -match 'not a facts file written by Analyze-SwydoReport') 'D4 trend facts (with real platforms) are refused for the stated reason'
  $run = RunTool (@('-Facts',$good,'-OutFile',(Join-Path $tmp2 'o6.json'),'-MinTrackedDays','0') + $std)
  Ok ($run.code -eq 2 -and $run.out -match 'at least 1') 'M8 -MinTrackedDays 0 is rejected'
  $run = RunTool @('-Facts',$good,'-OutFile',(Join-Path $tmp2 'o7.json'),'-DeclaredBy','user','-Metric','Conversion rate','-OutageStart','2026-06-11','-OutageEnd','2026-06-25')
  Ok ($run.code -eq 2 -and $run.out -match 'Only additive quantities') 'M3 CLI: a rate metric => exit 2'
  # D6: a refused re-run must not leave the earlier run's block behind
  $re = Join-Path $tmp2 're.facts.json'; [IO.File]::WriteAllText($re,$script:FactsJson,$enc)
  $run = RunTool (@('-Facts',$re) + $std)
  $afterFirst = [IO.File]::ReadAllText($re)
  Ok ($run.code -eq 0 -and $afterFirst -match '"estimates":') 'D6 setup: first run wrote the block'
  [IO.File]::WriteAllText($re,($afterFirst -replace '"compareBasis":"computed"','"compareBasis":"untrusted"'),$enc)
  $run = RunTool (@('-Facts',$re) + $std)
  $afterSecond = [IO.File]::ReadAllText($re)
  Ok ($run.code -eq 1 -and $run.out -match 'earlier run was removed') 'D6 a fully refused re-run exits 1 and says the old block was removed'
  Ok ($null -eq ($afterSecond | ConvertFrom-Json).PSObject.Properties['estimates'] -and ($afterSecond | ConvertFrom-Json).meta.client -eq 'Acme') 'D6 ...the facts no longer carry an estimates block, the rest is intact'
  Ok ((Invoke-Closer ($head + $recs) ($afterSecond | ConvertFrom-Json)).violations.Count -eq 0) 'D6 ...so a report without estimates passes the closer again'
  # M9: a relative path resolves against the PowerShell location, never the process directory
  $sub = Join-Path $tmp2 'sub'; New-Item -ItemType Directory -Path $sub | Out-Null
  [IO.File]::WriteAllText((Join-Path $sub 'f.facts.json'),$script:FactsJson,$enc)
  [IO.File]::WriteAllText((Join-Path $tmp2 'f.facts.json'),($script:FactsJson -replace '"client":"Acme"','"client":"Decoy"'),$enc)
  $decoyBefore = [IO.File]::ReadAllText((Join-Path $tmp2 'f.facts.json'))
  $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  $cmd = "Set-Location -LiteralPath '$sub'; & '$script:ToolPath' -Facts f.facts.json -DeclaredBy user -Action 'Web form' -OutageStart 2026-06-11 -OutageEnd 2026-06-25; exit `$LASTEXITCODE"
  Push-Location $tmp2
  try { $o = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command $cmd 2>&1 | Out-String; $c = $LASTEXITCODE } finally { Pop-Location; $ErrorActionPreference = $old }
  Ok ($c -eq 0) "M9 relative path after Set-Location runs ($o)"
  Ok (([IO.File]::ReadAllText((Join-Path $sub 'f.facts.json')) | ConvertFrom-Json).estimates.declared.declaredBy -eq 'user') 'M9 ...the file in the PowerShell location was updated'
  Ok ([IO.File]::ReadAllText((Join-Path $tmp2 'f.facts.json')) -eq $decoyBefore -and -not (Test-Path (Join-Path $tmp2 'f.facts.json.fc-tmp'))) 'M9 ...and the same-named file in the process directory was not touched'
} finally { Remove-Item -LiteralPath $tmp2 -Recurse -Force -ErrorAction SilentlyContinue }

Write-Host '== follow-ups: shared splicer (ANLZ-aModeledGap-4), summable money (ANLZ-aModeledGap-6) =='
$fb = Set-FactsMember '{"a":1,"b":{"x":"} , \"q\""}}' 'zz' '{"k":[1,2]}'
Ok ($fb -eq '{"a":1,"b":{"x":"} , \"q\""},"zz":{"k":[1,2]}}') 'Set-FactsMember appends a member and leaves the rest byte-identical'
Ok ((Set-FactsMember $fb 'zz' '{"k":[1,2]}') -eq $fb) 'Set-FactsMember is idempotent'
$fb2 = Set-FactsMember ($fb.Substring(0,$fb.Length-1) + ',"other":true}') 'zz' '3'
Ok ((@(($fb2 | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $_.Name }) -join ',') -eq 'a,b,other,zz') 'an existing member is replaced and re-appended last; other members keep their order'
Ok ((Remove-FactsMember $fb2 'zz') -eq '{"a":1,"b":{"x":"} , \"q\""},"other":true}') 'Remove-FactsMember drops only that member'
Ok ((Remove-FactsMember '{"a":{"zz":1},"s":"zz"}' 'zz') -eq '{"a":{"zz":1},"s":"zz"}') 'a nested key or a string value named like the member is left alone'
Throws { Set-FactsMember '[1,2]' 'zz' '1' } 'not a JSON object' 'Set-FactsMember refuses a non-object'
Ok ((Get-Command Find-FactsMember).ScriptBlock.File -like '*_FactsBlock.ps1') 'the splicer is defined in _FactsBlock.ps1, the one shared copy'
Ok ((Get-Content "$PSScriptRoot\..\skill\scripts\Invoke-SwydoForecast.ps1" -Raw) -notmatch '\$inStr') 'the forecast tool keeps no private scanner'

function NewFactsCov(){
  # the fixture plus the analyzer's coverage record (aggClass decides what can be summed)
  $f = NewFacts
  $cov = New-Object PSObject
  foreach($pair in @(@('gads:a:clicks','Clicks','number',$null,'sum'),@('gads:a:impressions','Impressions','number',$null,'sum'),@('gads:a:conversions','Conversions','number',$null,'sum'),
                     @('gads:a:conversion_rate','Conversion rate','percent','fraction','ratio-recompute'),@('gads:a:cost_per_conversion','Cost / conversion','currency','micros','ratio-recompute'),
                     @('gads:a:cost_micros','Cost','currency','micros','sum'))){
    $cov | Add-Member -NotePropertyName $pair[0] -NotePropertyValue ([pscustomobject]@{ id=$pair[0]; metric=$pair[1]; type=$pair[2]; unit=$pair[3]; aggClass=$pair[4] })
  }
  $f.platforms[0] | Add-Member -NotePropertyName metrics -NotePropertyValue $cov
  return $f
}
$r = Get-FcEstimates (NewFactsCov) $null (NewSpec @{ actions=@(); metric='Cost' }) 6 3
$mi = $r.items[0]
Ok ($mi.type -eq 'currency' -and $mi.metric -eq 'Cost') 'a summable money metric is accepted and typed currency'
Eqd (Method $mi 'prior-rate-clicks').value 750 'money: prior-rate-clicks = 600/800*1000'
Eqd (Method $mi 'run-rate').value 1300 'money: run-rate = 650/15*30'
Ok ($mi.display -eq '$1,025.00' -and $mi.displayLow -eq '$750.00' -and $mi.displayHigh -eq '$1,300.00') 'money estimates display as money, never as a bare count'
Ok ((Method $mi 'run-rate').display -eq '$1,300.00' -and $mi.statement -match '\$1,025\.00' -and $mi.uncertainty -match '\$750\.00') 'method displays and tool sentences use the money format too'
Ok (@($r.items).Count -eq 1) 'no conversion-rate / cost-per-conversion is derived from a money target'
Throws { Get-FcEstimates (NewFactsCov) $null (NewSpec @{ actions=@(); metric='Cost / conversion' }) } 'not summable' 'a per-unit price (ratio-recompute) is refused even though it is money'
Throws { Get-FcEstimates (NewFactsCov) $null (NewSpec @{ actions=@(); metric='Conversion rate' }) } 'Only additive quantities' 'a rate is refused with a coverage record too'
$r2 = Get-FcEstimates (NewFactsCov) $null (NewSpec $null) 6 3
Ok ($r2.items[0].display -eq '56.7' -and $r2.items[0].type -eq 'number') 'a count target right after a money run is formatted as a count again (no state leaks between runs)'
$moneyFacts = (Add-FcBlock $script:FactsJson $r) | ConvertFrom-Json
$mSec = "## Estimates (modeled)`n`nThese figures are modeled, not measured.`n`n- Cost: an estimated `$1,025.00 (range `$750.00 to `$1,300.00), against the `$650.00 actually recorded. <!-- estimate:EST#1 -->`n`n"
Ok ((Invoke-Closer ($head + $mSec + $recs) $moneyFacts).violations.Count -eq 0) 'the closer accepts a money estimate cited as the template shows'
Ok (HasT (Invoke-Closer ($head + ($mSec -replace '\$1,025\.00','1,025.0') + $recs) $moneyFacts) 'untraceable-number') 'the same value written as a bare count does not trace (type must match)'

Write-Host '== review round 3 (2026-11-12-review-aModeledGap-3) =='
# --- S1: the gate needs the metric's headline cell, in every mode ---
$f = NewFacts; $f.platforms[0].headline.PSObject.Properties.Remove('gads:a:conversions')
Throws { Get-FcEstimates $f $null (NewSpec $null) } 'without its headline cell' 'S1 per-action mode without a headline cell for the metric is refused (the gate cannot run)'
Throws { Get-FcEstimates $f $null (NewSpec @{ actions=@() }) } 'without its headline cell' 'S1 ...and so is whole-metric mode'
# --- T6 / S8: what counts as money that sums ---
Throws { Get-FcEstimates (NewFacts) $null (NewSpec @{ actions=@(); metric='Cost' }) } 'no coverage record' 'T6 micros money without a coverage record is refused, and the message says why'
$f = NewFactsCov; $f.platforms[0].headline.'gads:a:cost_micros'.unit = $null
Throws { Get-FcEstimates $f $null (NewSpec @{ actions=@(); metric='Cost' }) } 'unknown unit' 'T6 currency-typed money that is not in micros is refused, never formatted as a count'
$f = NewFactsCov; $f.platforms[0].headline.'gads:a:cost_per_conversion'.id = ''
foreach($cp in $f.platforms[0].metrics.PSObject.Properties){ $cp.Value.id = '' }
Throws { Get-FcEstimates $f $null (NewSpec @{ actions=@(); metric='Cost / conversion' }) } 'no coverage record' 'S8 a headline cell and coverage entries that both lack an id do not match each other'
Ok ((Get-Content "$PSScriptRoot\..\skill\scripts\Invoke-SwydoForecast.ps1" -Raw) -notmatch 'non-count metric') 'T6 the tool header no longer says "non-count metric"'
# --- S3 / S5: money the closer could never read is refused up front ---
$f = NewFactsCov; $f.platforms[0].headline.'gads:a:cost_micros'.currency = 'SEK'
Throws { Get-FcEstimates $f $null (NewSpec @{ actions=@(); metric='Cost' }) } 'closer cannot read' 'S3 a currency with no symbol the closer knows is refused'
$f = NewFactsCov; $f.platforms[0].headline.'gads:a:cost_micros'.currency = 'EUR'
$rEur = Get-FcEstimates $f $null (NewSpec @{ actions=@(); metric='Cost' }) 6 3
$eur = [string][char]0x20AC
Ok ($rEur.items[0].display -eq ($eur + '1,025.00') -and $rEur.items[0].displayLow -eq ($eur + '750.00')) 'T8 a euro target is formatted with the euro sign (the currency is carried, not assumed)'
$eurFacts = (Add-FcBlock $script:FactsJson $rEur) | ConvertFrom-Json
$eurSec = "## Estimates (modeled)`n`nThese figures are modeled, not measured.`n`n- Cost: an estimated " + $eur + "1,025.00 (range " + $eur + "750.00 to " + $eur + "1,300.00). <!-- estimate:EST#1 -->`n`n"
Ok ((Invoke-Closer ($head + $eurSec + $recs) $eurFacts).violations.Count -eq 0) 'T8 ...and the closer accepts it'
$f = NewFactsCov; $f.platforms[0].headline.'gads:a:cost_micros'.current = -50000000
Throws { Get-FcEstimates $f $null (NewSpec @{ actions=@(); metric='Cost' }) } 'negative' 'S5 a negative money target is refused'
# --- S6: count-scaled constants do not apply to money ---
$f = NewFactsCov; $f.platforms[0].headline.'gads:a:cost_micros'.current = 25000000; $f.platforms[0].headline.'gads:a:cost_micros'.displayCurrent = '$25.00'
$rSmall = Get-FcEstimates $f $null (NewSpec @{ actions=@(); metric='Cost' }) 6 3
Ok ($rSmall.items[0].uncertainty -notmatch 'small sample') 'S6 money under 30 is not called a small sample'
Ok ($e1.uncertainty -match 'small sample') 'S6 ...a count under 30 still is'
function NewFactsMoneyRows($formRow){
  # per-action money: the action breakdown also carries Cost rows
  $f = NewFactsCov
  $rows = $f.platforms[0].breakdowns[1].rows
  $rows[0].values | Add-Member -NotePropertyName Cost -NotePropertyValue ([pscustomobject]@{ display='$400.00'; type='currency'; hasComparison=$true; displayPrevious='$350.00' })
  $rows[1].values | Add-Member -NotePropertyName Cost -NotePropertyValue ([pscustomobject]@{ display=$formRow; type='currency'; hasComparison=$true; displayPrevious='$250.00' })
  return $f
}
$rRows = Get-FcEstimates (NewFactsMoneyRows '$250.00') $null (NewSpec @{ metric='Cost' }) 6 3
Ok (@($rRows.items).Count -eq 2 -and $rRows.items[0].kind -eq 'action' -and $rRows.items[1].kind -eq 'total') 'T8 per-action money: action + total, no dependents'
Ok ($rRows.items[0].type -eq 'currency' -and $rRows.items[1].type -eq 'currency') 'T8 both the action and the TOTAL are typed currency'
Ok (@(@($rRows.items[0].display,$rRows.items[0].displayLow,$rRows.items[0].displayHigh,$rRows.items[1].display,$rRows.items[1].displayLow,$rRows.items[1].displayHigh) | Where-Object { $_ -notmatch '^\$[\d,]+\.\d\d$' }).Count -eq 0) 'T8 every per-action money display is money-formatted'
$rOff = Get-FcEstimates (NewFactsMoneyRows '$249.85') $null (NewSpec @{ metric='Cost' }) 6 3
Ok (@($rOff.refused | Where-Object { $_.target -match 'account total' -and $_.reason -match 'rows sum' }).Count -eq 1) 'S6 money rows 15 cents off the headline do not reconcile (cent-scaled tolerance)'
# --- S4: a partial far out of scale is refused, in the unit's own words ---
Throws { Get-FcEstimates (NewFactsCov) $null (NewSpec @{ actions=@(); metric='Cost'; partials=@(@{ value=200000000; start='2026-06-01'; end='2026-06-10'; source='x' }) }) } 'dollars, not micros' 'S4 a money partial given in micros by mistake is refused and the message names the unit'
Throws { Get-FcEstimates (NewFacts) $null (NewSpec @{ actions=@(); partials=@(@{ value=5000; start='2026-06-01'; end='2026-06-10'; source='x' }) }) } 'ten times' 'S4 a count partial wildly above every other method is refused too'
$rAbove = Get-FcEstimates (NewFacts) $null (NewSpec @{ partials=@(@{ action='Web form'; value=14; start='2026-06-01'; end='2026-06-09'; source='client count' }) }) 6 3
Ok ($null -ne (Method $rAbove.items[0] 'run-rate') -and @($rAbove.items | Where-Object { $_.kind -eq 'action' }).Count -eq 1) 'S4 a partial moderately above the recorded value is still accepted'
Ok (@($rAbove.items[0].methods | Where-Object { $_.note -and $null -eq $_.valueBeforeFloor }).Count -eq 0) 'S4 a floored method records its value before the floor'
# --- S7: no stale money flag ---
try { Get-FcEstimates (NewFactsCov) $null (NewSpec @{ actions=@(); metric='Cost' }) 6 3 | Out-Null; Get-FcEstimates $null $null (NewSpec $null) | Out-Null } catch { }
Ok ((Format-FcTarget 5) -eq '5.0') 'S7 a throw at the very start of a run does not leave the money flag set'

# --- S2: money estimates written without their cents, or rounded ---
$rm = Invoke-Closer ($head + $mSec + $recs + "- Plan for `$1,025 of spend next month.`n") $moneyFacts
Ok (HasT $rm 'estimate-misuse') 'S2 a money estimate without its cents ("$1,025" for $1,025.00) is still the estimate'
$rm = Invoke-Closer ($head + $mSec + $recs + "- Plan for about `$1,025 of spend next month.`n") $moneyFacts
Ok (HasT $rm 'estimate-misuse') 'S2 ...also after an approximation word'
$rm = Invoke-Closer ($head + $mSec + $recs + "- Spend was `$650.00; hold it under `$700 next month.`n") $moneyFacts
Ok ($rm.violations.Count -eq 0) ('S2 a measured figure and an ordinary target stay legal in Recommendations (' + (@($rm.violations | ForEach-Object { $_.type + ':' + $_.snippet }) -join ' ; ') + ')')
$rm = Invoke-Closer ($head + $sec + $recs + "- Hold cost per conversion at about `$4.`n") $factsEst
Ok ($rm.violations.Count -eq 0) 'S2 "about $4" beside a $3.68 estimate is a target, not a rounded estimate'
$handIdx = @{ 'EST#9' = @{ item=$null; cands=@([ordered]@{ value=1025.4; type='currency'; role='base'; ulp=0.01 }, [ordered]@{ value=3.68; type='currency'; role='low'; ulp=0.01 }) } }
Ok ((@(Test-EstimateRounded 'Plan for about $1,025 of spend.' $handIdx 'x')).Count -eq 1) 'S2 "about $1,025" for an estimated $1,025.40 is a rounded estimate'
Ok ((@(Test-EstimateRounded 'Plan for about $1,026 of spend.' $handIdx 'x')).Count -eq 1) 'S2 ...rounded up as well'
Ok ((@(Test-EstimateRounded 'Hold it at about $4 or about $3.' $handIdx 'x')).Count -eq 0) 'S2 ...but only for estimates of 100 or more'
Ok ((@(Test-EstimateRounded 'About 1,025 clicks.' $handIdx 'x')).Count -eq 0) 'S2 a count never matches a money estimate'

# --- H4: estimates in a Recommendations heading or sub-heading ---
$rh = Invoke-Closer ($head + $sec + "## Recommendations: plan on 176.7 conversions`n`n- Fix the form tracking.`n") $factsEst
Ok (HasT $rh 'estimate-misuse') 'H4 an estimate in the Recommendations heading is misuse (the heading is not traced, but it is scanned)'
$rh = Invoke-Closer ($head + $sec + $recs + "`n### Plan on 176.7 conversions`n`n- Do it.`n") $factsEst
Ok (HasT $rh 'estimate-misuse') 'H4 ...and in a sub-heading under Recommendations'
$rh = Invoke-Closer ($head + $sec + $recs + "`n### Aim for 1,000 clicks and 200 conversions`n`n- Do it.`n") $factsEst
Ok ($rh.violations.Count -eq 0) ('H4 ordinary targets and measured facts in such a heading stay legal (' + (@($rh.violations | ForEach-Object { $_.type + ':' + $_.snippet }) -join ' ; ') + ')')

# --- S10 / T7: the splicer ---
Throws { Set-FactsMember '{"meta":{"m":1},"a":1}' 'estimates' '1,"meta":{"evil":true}' } 'not valid JSON' 'S10 a value carrying a second member cannot be smuggled in'
Throws { Set-FactsMember '{"a":1}' 'zz' '1,2' } 'single JSON value' 'S10 a value that is two JSON values is refused'
Throws { Set-FactsMember '{"a":1}' 'zz' '{oops' } 'not valid JSON' 'S10 a value that is not JSON is refused'
Throws { Set-FactsMember '{"Estimates":1,"a":2}' 'estimates' '3' } '.' 'T7 a splice that would leave two members differing only by case is refused'
Ok ((Remove-FactsMember '{"zz":1,"a":2,"b":3}' 'zz') -eq '{"a":2,"b":3}') 'T7 Remove: a FIRST member'
Ok ((Remove-FactsMember '{"a":2,"zz":1,"b":3}' 'zz') -eq '{"a":2,"b":3}') 'T7 Remove: a MIDDLE member'
Ok ((Remove-FactsMember '{"a":2,"b":3,"zz":1}' 'zz') -eq '{"a":2,"b":3}') 'T7 Remove: the LAST member'
Ok ((Remove-FactsMember '{"zz":1,"a":2,"zz":{"k":[1,2]}}' 'zz') -eq '{"a":2}') 'S10 Remove: both of two duplicate members'
Ok ((Set-FactsMember '{}' 'zz' '1') -eq '{"zz":1}') 'T7 Set into an empty object needs no separator'
Ok ((Remove-FactsMember '{"zz":1}' 'zz') -eq '{}') 'T7 Remove down to an empty object'
Ok ((Set-FactsMember '{"zz":1,"a":2}' 'zz' '9') -eq '{"a":2,"zz":9}') 'T7 Set replaces a first member and re-appends it last'

Write-Host ''
Write-Host ("Test-Forecast: {0} passed, {1} failed." -f $script:pass,$script:fail)
if($script:fail -gt 0){ exit 1 }
