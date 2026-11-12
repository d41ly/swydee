<#
.SYNOPSIS
  Hold-out backtest for Invoke-SwydoForecast.ps1: take a COMPLETE facts file, stage a tracking outage on
  one metric (hide part of what was really recorded), forecast it, and score the forecast against the
  real figure. Only the prior-level methods are tested blind - see STAGING.

.DESCRIPTION
  Not a gate suite (it needs real client facts); run it by hand:
    powershell -File tests\Backtest-Forecast.ps1 -Facts <complete.facts.json> -Target "action:<label>" `
      -OutageStart 2026-09-10 -OutageEnd 2026-09-28 -OutDir <dir> [-Ledger <ledger.json>]
  -Target is "action:<row label of the 'Conversion action name' breakdown>" or "metric:<headline name>".

  STAGING. The facts hold no daily split, so the share of the month recorded on the tracked days is
  taken from the report's own 'Day of the week' breakdown of Conversions: every date in the period
  gets its weekday's average, and the tracked dates' share of the total is what stays "recorded".
  (Row labels 0..6 are read as Sunday..Saturday.) That is more realistic than a flat days/days share,
  but it still assumes one weekday looks like the next. The staged "recorded" figure is the real figure
  times that share, and the run-rate method divides by nearly the same share again - so run-rate
  recovers the real figure BY CONSTRUCTION (it differs only by weekday mix). Its error, and therefore
  the base error and the "actual in range" result that include it, are NOT evidence of skill. The
  prior-level methods never see the hidden figure at all; their per-method errors are the blind result.
  A fair test of run-rate needs real daily data.

  The staged facts keep the hidden figure out of everything the forecast tool reads (the target cell,
  the Conversions headline, conversion rate, cost per conversion). The answer key is held in memory
  and written only to the result file.
#>
param(
  [string]$Facts,
  [string]$Target,
  [string]$OutageStart,
  [string]$OutageEnd,
  [string]$Ledger = "",
  [string]$OutDir = "",
  [int]$HistoryMonths = 6,
  [string]$Tag = ""
)
$ErrorActionPreference = 'Stop'
$toolPath = "$PSScriptRoot\..\skill\scripts\Invoke-SwydoForecast.ps1"
# capture our arguments BEFORE dot-sourcing: the tool's own param block (same names) would blank them
$btFacts=$Facts; $btTarget=$Target; $btStart=$OutageStart; $btEnd=$OutageEnd; $btLedger=$Ledger; $btOutDir=$OutDir; $btHist=$HistoryMonths; $btTag=$Tag
. $toolPath -DefineOnly

if(-not $btFacts -or -not $btTarget -or -not $btStart -or -not $btEnd -or -not $btOutDir){ Write-Host 'usage: Backtest-Forecast.ps1 -Facts <facts.json> -Target "action:<label>|metric:<name>" -OutageStart <d> -OutageEnd <d> -OutDir <dir>'; exit 2 }
$srcText = [IO.File]::ReadAllText($btFacts)
if($srcText -match $script:FcCredRx){ Write-Host 'refusing: input carries a share credential'; exit 2 }
$doc = $srcText | ConvertFrom-Json
if($doc.PSObject.Properties['estimates']){ $doc.PSObject.Properties.Remove('estimates') }
$plat = @($doc.platforms)[0]
$kind,$name = $btTarget -split ':',2
$ps = ConvertTo-FcDate $doc.meta.periodResolved.current.start; $pe = ConvertTo-FcDate $doc.meta.periodResolved.current.end
$os = ConvertTo-FcDate $btStart; $oe = ConvertTo-FcDate $btEnd

# ---- tracked share from the weekday profile ----
$dow = @($plat.breakdowns | Where-Object { @($_.dimensions) -contains 'Day of the week' -and @($_.rows).Count -eq 7 })[0]
if($null -eq $dow){ Write-Host "no 7-row 'Day of the week' breakdown to stage from"; exit 2 }
$dowVal = @{}; foreach($r in $dow.rows){ $dowVal[[int]$r.label] = ConvertFrom-FcDisplay $r.values.Conversions.display }
$cnt = @{}; $trk = @{}; for($i=0;$i -lt 7;$i++){ $cnt[$i]=0; $trk[$i]=0 }
for($d=$ps; $d -le $pe; $d=$d.AddDays(1)){ $w=[int]$d.DayOfWeek; $cnt[$w]++; if($d -lt $os -or $d -gt $oe){ $trk[$w]++ } }
$tot=0.0; $kept=0.0
for($i=0;$i -lt 7;$i++){ $tot += $dowVal[$i]; $kept += $dowVal[$i] * $trk[$i] / $cnt[$i] }
$share = $kept/$tot
$perDays = Get-FcDays $ps $pe; $outDays = Get-FcDays $os $oe

# ---- answer key + staging ----
$hConv = (Get-FcHeadline $plat 'Conversions').cell
$hRate = (Get-FcHeadline $plat 'Conversion rate').cell
$hCpa  = (Get-FcHeadline $plat 'Cost / conversion').cell
$hCost = (Get-FcHeadline $plat 'Cost').cell
$hClk  = (Get-FcHeadline $plat 'Clicks').cell
$key = [ordered]@{ target=$null; totalConversions=[double]$hConv.current; conversionRate=[double]$hRate.current; costPerConversion=([double]$hCpa.current/1e6) }
$fcArgs = @('-DeclaredBy','backtest (staged outage)','-OutageStart',$btStart,'-OutageEnd',$btEnd,'-HistoryMonths',[string]$btHist)
$lost = 0.0; $touchConv = $false
if($kind -eq 'action'){
  $bd = (Get-FcActionBreakdown $plat 'Conversions' 'Conversion action name' @($name)).breakdown
  $cell = @($bd.rows | Where-Object { [string]$_.label -eq $name })[0].values.Conversions
  $actual = ConvertFrom-FcDisplay $cell.display
  $staged = $actual * $share
  $cell.display = Format-FcCount $staged
  $lost = $actual - $staged; $touchConv = $true
  $fcArgs += @('-Action',$name)
} else {
  $h = (Get-FcHeadline $plat $name).cell
  $actual = [double]$h.current
  $staged = $actual * $share
  if($name -eq 'Conversions'){ $lost = $actual - $staged; $touchConv = $true }
  else { $h.current = [math]::Round($staged,4); $h.displayCurrent = Format-FcCount $staged }
  $fcArgs += @('-Metric',$name)
}
$key.target = $actual
if($touchConv){
  $newConv = [double]$hConv.current - $lost
  $hConv.current = $newConv; $hConv.displayCurrent = Format-FcCount $newConv
  $hRate.current = $newConv / [double]$hClk.current; $hRate.displayCurrent = Format-FcPercent $hRate.current
  $hCpa.current = [double]$hCost.current / $newConv; $hCpa.displayCurrent = Format-FcMoney ($hCpa.current/1e6) $hCpa.currency
}
if(-not (Test-Path $btOutDir)){ New-Item -ItemType Directory -Path $btOutDir | Out-Null }
if(-not $btTag){ $btTag = (($btTarget -replace '[^A-Za-z0-9]+','-').Trim('-') + '_' + $btStart + '_' + $btEnd) }
$stagedPath = Join-Path $btOutDir ($btTag + '.staged.facts.json')
[IO.File]::WriteAllText($stagedPath,(ConvertTo-Json -InputObject $doc -Depth 40 -Compress),(New-Object Text.UTF8Encoding($false)))

# ---- forecast (separate process: it sees only the staged file) ----
$fcArgs = @('-Facts',$stagedPath) + $fcArgs
if($btLedger){ $fcArgs += @('-Ledger',$btLedger) }
$old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
$fcOut = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $toolPath @fcArgs 2>&1 | Out-String; $code = $LASTEXITCODE
$ErrorActionPreference = $old

# ---- score ----
function Score($label,$actualV,$fmt,$it){
  $f = { param($v) if($fmt -eq 'pct'){ Format-FcPercent $v } elseif($fmt -eq 'money'){ Format-FcMoney $v 'USD' } else { Format-FcCount $v } }
  $err = ([double]$it.value - $actualV)/$actualV
  $row = [ordered]@{ metric=$label; eid=$it.eid; actual=(& $f $actualV); staged=$it.measuredDisplay; base=$it.display; low=$it.displayLow; high=$it.displayHigh
                     baseError=(('{0:+0.0;-0.0;0.0}%' -f ($err*100))); actualInRange=($actualV -ge ([double]$it.low - 1e-9) -and $actualV -le ([double]$it.high + 1e-9)); methods=@() }
  foreach($m in @($it.methods)){
    if($m.family -in @('bottom-up','dependent')){ continue }
    $me = ([double]$m.value - $actualV)/$actualV
    $row.methods += [ordered]@{ id=$m.id; result=$m.display; error=('{0:+0.0;-0.0;0.0}%' -f ($me*100)) }
  }
  return $row
}
$result = [ordered]@{ target=$btTarget; period=[string]$doc.meta.currentPeriod; outage=("{0}..{1}" -f $btStart,$btEnd); periodDays=$perDays; outageDays=$outDays
                      caveat='run-rate is not blind (staged = actual x weekday share); only prior-level method errors are'
                      stagedShareKept=(Format-FcPercent $share); flatShareKept=(Format-FcPercent (($perDays-$outDays)/$perDays)); forecastExit=$code; rows=@(); refused=@(); skipped=@() }
if($code -eq 0){
  $est = ([IO.File]::ReadAllText($stagedPath) | ConvertFrom-Json).estimates
  foreach($it in @($est.items)){
    if($it.kind -eq 'action'){ $result.rows += (Score ("'" + $it.action + "' conversions") $key.target 'n' $it) }
    elseif($it.kind -eq 'total' -and $kind -eq 'metric'){ $result.rows += (Score $name $key.target 'n' $it) }
    elseif($it.kind -eq 'total'){ $result.rows += (Score 'Total conversions' $key.totalConversions 'n' $it) }
    elseif($it.metric -eq 'Conversion rate'){ $result.rows += (Score 'Conversion rate' $key.conversionRate 'pct' $it) }
    elseif($it.metric -eq 'Cost / conversion'){ $result.rows += (Score 'Cost / conversion' $key.costPerConversion 'money' $it) }
    foreach($s in @($it.skippedMethods)){ $result.skipped += ("{0} {1}: {2}" -f $it.eid,$s.id,$s.reason) }
  }
  $result.refused = @($est.refused | ForEach-Object { "{0}: {1}" -f $_.target,$_.reason })
} else { $result.refused = @($fcOut.Trim()) }
$resPath = Join-Path $btOutDir ($btTag + '.backtest.json')
[IO.File]::WriteAllText($resPath,(ConvertTo-Json -InputObject $result -Depth 10),(New-Object Text.UTF8Encoding($false)))

Write-Host ("BACKTEST {0} | outage {1} ({2} of {3} days) | kept {4} of the real figure (flat share would be {5})" -f $btTarget,$result.outage,$outDays,$perDays,$result.stagedShareKept,$result.flatShareKept)
Write-Host '  NOTE: run-rate recovers the hidden figure by construction (weekday mix only). Read the prior-level method errors as the blind result; base error and in-range are flattered by run-rate.'
foreach($r in $result.rows){
  Write-Host ("  {0}: actual {1} | staged {2} | forecast {3} (range {4} to {5}) | base error {6} | actual in range: {7}" -f $r.metric,$r.actual,$r.staged,$r.base,$r.low,$r.high,$r.baseError,$r.actualInRange)
  foreach($m in $r.methods){ Write-Host ("      {0}: {1} ({2})" -f $m.id,$m.result,$m.error) }
}
foreach($x in $result.refused){ Write-Host ("  REFUSED {0}" -f $x) }
foreach($x in $result.skipped){ Write-Host ("  skipped {0}" -f $x) }
exit 0
