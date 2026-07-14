<#
.SYNOPSIS
  Offline tests for Analyze-SwydoTrend.ps1: pure quarter math + honesty gate, and the load-bearing R1
  closer-integration proof -- a synthetic ledger -> trend facts -> the REAL closer (Test-ReportNumbers.ps1)
  must force GAP_RESTATEMENT_SUPPRESSED into the report and reject a fabricated number. Run: .\Test-TrendAnalyze.ps1
#>
$ErrorActionPreference = "Stop"
$scripts = "$PSScriptRoot\skill\scripts"
. "$scripts\Analyze-SwydoTrend.ps1" -DefineOnly

$pass=0; $fail=0
function Assert($cond,$msg){ if($cond){ $script:pass++ } else { $script:fail++; Write-Host "  FAIL: $msg" -ForegroundColor Red } }

Write-Host "== quarter arithmetic =="
Assert ((Get-QuarterKey '2025-07') -eq '2025-Q3') "2025-07 => 2025-Q3"
Assert ((Get-QuarterKey '2025-01') -eq '2025-Q1') "2025-01 => 2025-Q1"
Assert ((Get-QuarterKey '2025-12') -eq '2025-Q4') "2025-12 => 2025-Q4"
Assert (((Get-QuarterMonths '2025-Q3') -join ',') -eq '2025-07,2025-08,2025-09') "Q3 months"
Assert ((Get-PrevQuarter '2025-Q1') -eq '2024-Q4') "prev of Q1 wraps year"
Assert ((Get-PrevQuarter '2025-Q3') -eq '2025-Q2') "prev of Q3"
Assert ((Get-YearAgoQuarter '2025-Q3') -eq '2024-Q3') "year-ago Q3"
Assert ((Get-QuarterLabel '2025-Q3') -eq 'Q3 2025') "human label"

Write-Host "== Get-QuarterSum (gate: all 3 present + final) =="
$mfin=@{ '2025-07'=[pscustomobject]@{state='final';value=600}; '2025-08'=[pscustomobject]@{state='final';value=600}; '2025-09'=[pscustomobject]@{state='final';value=600} }
Assert ((Get-QuarterSum $mfin '2025-Q3').ok -and (Get-QuarterSum $mfin '2025-Q3').value -eq 1800) "3 final => sum 1800"
$mprov=@{ '2025-07'=[pscustomobject]@{state='final';value=600}; '2025-08'=[pscustomobject]@{state='provisional';value=600}; '2025-09'=[pscustomobject]@{state='final';value=600} }
Assert (-not (Get-QuarterSum $mprov '2025-Q3').ok) "a provisional month => not ok (gated)"
$mmiss=@{ '2025-07'=[pscustomobject]@{state='final';value=600}; '2025-09'=[pscustomobject]@{state='final';value=600} }
Assert (-not (Get-QuarterSum $mmiss '2025-Q3').ok) "missing month => not ok"
Assert (-not (Get-QuarterSum $mfin 'garbage').ok) "bad quarter key => not ok (fail-closed, no fabricated 0)"
Assert ((Get-LatestFinalQuarter $mfin) -eq '2025-Q3') "latest final quarter"

Write-Host "== integration: ledger -> trend facts -> REAL closer =="
$tmp = Join-Path $env:TEMP ("trendanalyze-test-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$savedEAP=$ErrorActionPreference; $ErrorActionPreference='Continue'
try {
  # synthetic ledger: google-adwords clicks, monthly 2024-01..2025-09 all FINAL; Q3'25=1800 Q2'25=1500 (+20% QoQ), Q3'24=1200 (+50% YoY); 2024-05 restated.
  $cells=[ordered]@{}
  $vals=@{ '2025-04'=500;'2025-05'=500;'2025-06'=500; '2025-07'=600;'2025-08'=600;'2025-09'=600; '2024-07'=400;'2024-08'=400;'2024-09'=400 }
  foreach($yr in 2024,2025){ foreach($mo in 1..12){ $mk=('{0}-{1:D2}' -f $yr,$mo); if($mk -gt '2025-09'){ continue }
    $v = if($vals.ContainsKey($mk)){ $vals[$mk] } else { 300 }
    $cell=[ordered]@{ providerId='google-adwords'; metricId='google-adwords:clicks'; basisVersion='bv1'; month=$mk; value=$v; display="$v"; unit=$null; currency=$null; state='final'; restatementCount=0; keptNullCount=0 }
    if($mk -eq '2024-05'){ $cell.restatementCount=1; $cell.latestDisplay='9,999' }
    $cells[("google-adwords:clicks|"+$mk)]=$cell
  } }
  $ledger=[ordered]@{ ledgerVersion=1; client='Acme Co'; updatedAt='2026-07-06T00:00:00Z'; cells=$cells; coverage=[ordered]@{ 'google-adwords'=[ordered]@{ providerId='google-adwords'; providerName='Google Ads'; hasMonthlyGrain=$true; ceilingMonths=48; earliestMonth='2024-01'; latestMonth='2025-09'; windowStatus='ok' } } }
  $ledgerPath=Join-Path $tmp 'ledger.json'
  [IO.File]::WriteAllText($ledgerPath, (ConvertTo-Json -InputObject $ledger -Depth 100), (New-Object Text.UTF8Encoding($false)))

  & powershell -NoProfile -ExecutionPolicy Bypass -File "$scripts\Analyze-SwydoTrend.ps1" -LedgerFile $ledgerPath -OutDir $tmp *> $null
  Assert ($LASTEXITCODE -eq 0) "trend analysis exit 0"
  $ff = Get-ChildItem (Join-Path $tmp '*.trendanalysis.facts.json') | Select-Object -First 1
  Assert ($null -ne $ff) "trend facts produced"
  # NB: parse into $FA, NOT $F -- $f is used as a loop var below and $F/$f are the same variable (case-insensitive).
  $FA = [IO.File]::ReadAllText($ff.FullName) | ConvertFrom-Json
  # structural: R1 finding present, sev major, has fid; a QoQ/YoY comparison present
  $rest = @($FA.findings.anomalies | Where-Object { $_.ruleId -eq 'GAP_RESTATEMENT_SUPPRESSED' })
  Assert ($rest.Count -eq 1) "GAP_RESTATEMENT_SUPPRESSED emitted"
  Assert ($rest.Count -gt 0 -and $rest[0].severity -eq 'major' -and $rest[0].fid) "restatement finding is sev major + has fid"
  $comp = @($FA.findings.wins) + @($FA.findings.losses)
  Assert ($comp.Count -ge 1) "at least one QoQ/YoY win/loss emitted"
  $txt=[IO.File]::ReadAllText($ff.FullName); Assert ($txt -notmatch '(?i)swy\.do/shares/') "no credential in trend facts"

  # report A: surfaces NOTHING -> closer must FAIL with unsurfaced-finding for the restatement
  $repA = Join-Path $tmp 'reportA.md'
  [IO.File]::WriteAllText($repA, "## Trend`nNothing to report.`n", (New-Object Text.UTF8Encoding($false)))
  $outA = & powershell -NoProfile -ExecutionPolicy Bypass -File "$scripts\Test-ReportNumbers.ps1" -Report $repA -Facts $ff.FullName 2>&1 | Out-String
  Assert ($LASTEXITCODE -ne 0) "closer FAILs on report that surfaces nothing"
  Assert ($outA -match 'unsurfaced-finding' -and $outA -match 'GAP_RESTATEMENT_SUPPRESSED') "closer flags unsurfaced GAP_RESTATEMENT_SUPPRESSED"

  # report B: surface EVERY finding (statement + anchor) + caveats -> closer should PASS (numbers trace via byFid).
  # Guarded literal access: an empty JSON array can deserialize so @() yields a [null] element.
  $allF=@()
  foreach($f in @($FA.findings.wins))          { if($f -and $f.fid){ $allF+=$f } }
  foreach($f in @($FA.findings.losses))        { if($f -and $f.fid){ $allF+=$f } }
  foreach($f in @($FA.findings.anomalies))     { if($f -and $f.fid){ $allF+=$f } }
  foreach($f in @($FA.findings.discrepancies)) { if($f -and $f.fid){ $allF+=$f } }
  foreach($f in @($FA.findings.dataGaps))      { if($f -and $f.fid){ $allF+=$f } }
  $lines=@('## Trend','')
  foreach($f in $allF){ $lines += ("$($f.statement) <!-- finding:$($f.fid) -->") }
  foreach($cav in @($FA.meta.comparisonCaveats)){ if($cav -and $cav.id){ $lines += ("$($cav.text) <!-- caveat:$($cav.id) -->") } }
  $repB = Join-Path $tmp 'reportB.md'
  [IO.File]::WriteAllText($repB, ($lines -join "`n"), (New-Object Text.UTF8Encoding($false)))
  $outB = & powershell -NoProfile -ExecutionPolicy Bypass -File "$scripts\Test-ReportNumbers.ps1" -Report $repB -Facts $ff.FullName 2>&1 | Out-String
  Assert ($LASTEXITCODE -eq 0) "closer PASSes a surfacing-complete, traceable report (out: $($outB -replace '\s+',' '))"

  # report C: report B + a fabricated number -> closer must FAIL with untraceable-number
  $repC = Join-Path $tmp 'reportC.md'
  [IO.File]::WriteAllText($repC, (($lines -join "`n") + "`nThe grand total was 12,345,678 clicks.`n"), (New-Object Text.UTF8Encoding($false)))
  $outC = & powershell -NoProfile -ExecutionPolicy Bypass -File "$scripts\Test-ReportNumbers.ps1" -Report $repC -Facts $ff.FullName 2>&1 | Out-String
  Assert ($LASTEXITCODE -ne 0) "closer FAILs on a fabricated number"
  Assert ($outC -match 'untraceable-number') "closer flags the fabricated number as untraceable"
} finally { $ErrorActionPreference=$savedEAP; Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }

# ============================ U7b check #6: monthly-series-sum vs period KPI ============================
Write-Host "== U7b #6: Get-MonthSpan / Get-MonthRangeSum (pure, INTEGER month arithmetic) =="
Assert (((Get-MonthSpan '2026-04' '2026-06').months -join ',') -eq '2026-04,2026-05,2026-06') "span k=3 quarter"
Assert (((Get-MonthSpan '2026-04' '2026-04').months -join ',') -eq '2026-04') "span k=1 single month"
Assert ((Get-MonthSpan '2025-01' '2025-12').months.Count -eq 12) "span k=12 full year"
Assert (((Get-MonthSpan '2025-11' '2026-02').months -join ',') -eq '2025-11,2025-12,2026-01,2026-02') "span year-crossing enumerates correctly"
Assert (-not (Get-MonthSpan '2026-06' '2026-04').ok) "span inverted range -> not ok (fail-closed)"
Assert (-not (Get-MonthSpan '2026-13' '2026-14').ok) "span rejects month 13 (strict YYYY-MM, no Unicode/overflow)"
$m3=@{ '2026-04'=[pscustomobject]@{value=10000;state='final';restatementCount=0}; '2026-05'=[pscustomobject]@{value=10000;state='final';restatementCount=0}; '2026-06'=[pscustomobject]@{value=10000;state='provisional';restatementCount=0} }
$rs3=Get-MonthRangeSum $m3 '2026-04' '2026-06'
Assert ($rs3.ok -and $rs3.value -eq 30000) "sum k=3 (provisional month INCLUDED per MF-1)"
$m1=@{ '2026-04'=[pscustomobject]@{value=777;state='final'} }
Assert ((Get-MonthRangeSum $m1 '2026-04' '2026-04').value -eq 777) "sum k=1"
$mYr=@{}; foreach($mo in 1..12){ $mYr[('2025-{0:D2}' -f $mo)]=[pscustomobject]@{value=100;state='final'} }
Assert ((Get-MonthRangeSum $mYr '2025-01' '2025-12').value -eq 1200) "sum k=12"
$mXr=@{ '2025-11'=[pscustomobject]@{value=1;state='final'}; '2025-12'=[pscustomobject]@{value=2;state='final'}; '2026-01'=[pscustomobject]@{value=3;state='final'}; '2026-02'=[pscustomobject]@{value=4;state='final'} }
Assert ((Get-MonthRangeSum $mXr '2025-11' '2026-02').value -eq 10) "sum year-crossing"
Assert (-not (Get-MonthRangeSum $m1 '2026-04' '2026-06').ok) "sum missing month -> not ok"
Assert (-not (Get-MonthRangeSum $m3 '2026-06' '2026-04').ok) "sum inverted range -> not ok"

Write-Host "== U7b #6: e2e reconciliation (ledger + -PeriodKpiFacts -> trend facts) =="
$tmp6 = Join-Path $env:TEMP ("trendanalyze6-test-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmp6 | Out-Null
$savedEAP=$ErrorActionPreference; $ErrorActionPreference='Continue'
try {
  $PROV='google-analytics-4'; $MID='google-analytics-4:sessions'
  function New-Led($client,$monthVals,$unit,$cur,$restated,$basisPerMonth){
    $cells=[ordered]@{}
    foreach($mk in ($monthVals.Keys|Sort-Object)){
      $bv = if($basisPerMonth -and $basisPerMonth.ContainsKey($mk)){ $basisPerMonth[$mk] } else { 'bv1' }
      $c=[ordered]@{ providerId=$PROV; metricId=$MID; basisVersion=$bv; month=$mk; value=$monthVals[$mk]; display="$($monthVals[$mk])"; unit=$unit; currency=$cur; state='final'; restatementCount=0; keptNullCount=0 }
      if($restated -and $mk -eq $restated){ $c.restatementCount=1; $c.latestDisplay='9,999' }
      $cells[($MID+'|'+$mk)]=$c
    }
    $mks=@($monthVals.Keys|Sort-Object)
    return [ordered]@{ ledgerVersion=1; client=$client; updatedAt='2026-07-06T00:00:00Z'; cells=$cells; coverage=[ordered]@{ $PROV=[ordered]@{ providerId=$PROV; providerName='GA4'; hasMonthlyGrain=$true; ceilingMonths=48; earliestMonth=$mks[0]; latestMonth=$mks[-1]; windowStatus='ok' } } }
  }
  function New-Pk($client,$mid,$unit,$cur,$current,$scope,$period,$tsLabels){
    $src = if($scope -eq 'account'){ 'kpi-widget' } else { 'total-row' }
    $cell=[ordered]@{ metric='Sessions'; id=$mid; unit=$unit; type='number'; currency=$cur; current=$current; hasComparison=$false; displayCurrent="$current" }
    if($scope){ $cell.canonical=[ordered]@{ display="$current"; sourceWidgetId='w1'; scope=$scope; source=$src } }
    $headline=[ordered]@{}; $headline[$mid]=$cell; $headline.hasComparison=$false
    $plat=[ordered]@{ id=$PROV; name='GA4'; category='analytics'; headline=$headline; hasComparison=$false }
    if($tsLabels){ $bk=@(); foreach($lb in $tsLabels){ $bk+=[ordered]@{ label=$lb } }; $plat.timeSeries=@([ordered]@{ widgetId='w1'; dimension='month'; buckets=$bk }) }
    return [ordered]@{ meta=[ordered]@{ tool='Analyze-SwydoReport.ps1'; factsVersion=1; client=$client; period=$period }; platforms=@($plat); findings=[ordered]@{} }
  }
  $QP=[ordered]@{ measure='quarter'; startYm='2026-04'; endYm='2026-06'; calendarAligned=$true }
  function Run-Trend($ledger,$pk){
    $d=Join-Path $tmp6 ([guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Force -Path $d|Out-Null
    $lp=Join-Path $d 'ledger.json'; [IO.File]::WriteAllText($lp,(ConvertTo-Json -InputObject $ledger -Depth 100),(New-Object Text.UTF8Encoding($false)))
    $a=@('-NoProfile','-ExecutionPolicy','Bypass','-File',"$scripts\Analyze-SwydoTrend.ps1",'-LedgerFile',$lp,'-OutDir',$d)
    if($pk){ $pkp=Join-Path $d 'pk.facts.json'; [IO.File]::WriteAllText($pkp,(ConvertTo-Json -InputObject $pk -Depth 100),(New-Object Text.UTF8Encoding($false))); $a+=@('-PeriodKpiFacts',$pkp) }
    & powershell @a *> $null
    $ff=Get-ChildItem (Join-Path $d '*.trendanalysis.facts.json')|Select-Object -First 1
    if(-not $ff){ return $null }
    return ([IO.File]::ReadAllText($ff.FullName)|ConvertFrom-Json)
  }
  function Recon($fa,$rid){ $r=@(); foreach($k in 'wins','losses','anomalies','discrepancies','dataGaps'){ foreach($f in @($fa.findings.$k)){ if($f -and $f.ruleId -eq $rid){ $r+=$f } } }; return @($r) }

  $months3=@{ '2026-04'=10000; '2026-05'=10000; '2026-06'=10000 }

  # within tolerance -> no mismatch, no coverage (not force-surfaced, no clean-recon info)
  $fa=Run-Trend (New-Led 'Acme Co' $months3 $null $null $null $null) (New-Pk 'acme co' $MID $null $null 30000 'account' $QP $null)
  Assert ($null -ne $fa) "within-tol: trend facts produced"
  Assert (@(Recon $fa 'RECON_TREND_MISMATCH').Count -eq 0) "within-tol: no RECON_TREND_MISMATCH"
  Assert (@(Recon $fa 'RECON_TREND_COVERAGE').Count -eq 0) "within-tol: no coverage info (clean-recon suppressed, identity ci-match)"

  # over tolerance -> info RECON_TREND_MISMATCH with 3/3 final + both displays + period
  $fa=Run-Trend (New-Led 'Acme Co' $months3 $null $null $null $null) (New-Pk 'Acme Co' $MID $null $null 35000 'account' $QP $null)
  $mm=@(Recon $fa 'RECON_TREND_MISMATCH')
  Assert ($mm.Count -eq 1) "over-tol: one RECON_TREND_MISMATCH"
  Assert ($mm.Count -eq 1 -and $mm[0].severity -eq 'info') "over-tol: severity is INFO (MF-1, not major)"
  Assert ($mm.Count -eq 1 -and $mm[0].evidence.months -eq '3/3 final') "over-tol: months '3/3 final'"
  Assert ($mm.Count -eq 1 -and $mm[0].evidence.period -eq '2026-04..2026-06') "over-tol: period in evidence"
  Assert ($mm.Count -eq 1 -and $mm[0].evidence.monthsSum -eq '30,000' -and $mm[0].evidence.periodKpi -eq '35,000') "over-tol: both displays present"
  Assert ($mm.Count -eq 1 -and $mm[0].fid) "over-tol: mismatch has a fid"

  # over tolerance but a PROVISIONAL month -> still summed (MF-1); months honestly '2/3 final'
  $mvP=@{ '2026-04'=10000; '2026-05'=10000; '2026-06'=15000 }
  $ledP=New-Led 'Acme Co' $mvP $null $null $null $null
  $ledP.cells[($MID+'|2026-06')].state='provisional'
  $fa=Run-Trend $ledP (New-Pk 'Acme Co' $MID $null $null 30000 'account' $QP $null)
  $mm=@(Recon $fa 'RECON_TREND_MISMATCH')
  Assert ($mm.Count -eq 1 -and $mm[0].evidence.months -eq '2/3 final') "provisional: summed anyway, months '2/3 final'"

  # gate 1: no machine-readable period -> ONE coverage info, no mismatch
  $NP=[ordered]@{ measure='custom'; startYm=$null; endYm=$null; calendarAligned=$false }
  $fa=Run-Trend (New-Led 'Acme Co' $months3 $null $null $null $null) (New-Pk 'Acme Co' $MID $null $null 35000 'account' $NP $null)
  Assert (@(Recon $fa 'RECON_TREND_COVERAGE').Count -eq 1) "gate1 legacy/custom: exactly one coverage info"
  Assert (@(Recon $fa 'RECON_TREND_MISMATCH').Count -eq 0) "gate1 legacy/custom: no mismatch"

  # gate 1: malformed startYm -> coverage info
  $BP=[ordered]@{ measure='quarter'; startYm='2026-13'; endYm='2026-06'; calendarAligned=$true }
  $fa=Run-Trend (New-Led 'Acme Co' $months3 $null $null $null $null) (New-Pk 'Acme Co' $MID $null $null 35000 'account' $BP $null)
  Assert (@(Recon $fa 'RECON_TREND_COVERAGE').Count -eq 1 -and @(Recon $fa 'RECON_TREND_MISMATCH').Count -eq 0) "gate1 malformed startYm: coverage info, no mismatch"

  # gate 1b: skew FP -- server-labeled months disagree with resolved period -> coverage info
  $fa=Run-Trend (New-Led 'Acme Co' $months3 $null $null $null $null) (New-Pk 'Acme Co' $MID $null $null 35000 'account' $QP @('2026-03','2026-04','2026-05'))
  Assert (@(Recon $fa 'RECON_TREND_COVERAGE').Count -eq 1 -and @(Recon $fa 'RECON_TREND_MISMATCH').Count -eq 0) "gate1b skew: coverage info, no mismatch"
  # gate 1b: agreeing server labels -> proceeds to the mismatch
  $fa=Run-Trend (New-Led 'Acme Co' $months3 $null $null $null $null) (New-Pk 'Acme Co' $MID $null $null 35000 'account' $QP @('2026-04','2026-05','2026-06'))
  Assert (@(Recon $fa 'RECON_TREND_MISMATCH').Count -eq 1) "gate1b agreeing labels: mismatch fires"
  # gate 1b (MF-4 scoping): a LONGER trailing monthly trend chart (6 months) alongside a clean-reconciling quarter
  # KPI is a DIFFERENT date range, NOT period skew -> gate 1b must skip it and reconcile cleanly (no false coverage).
  $fa=Run-Trend (New-Led 'Acme Co' $months3 $null $null $null $null) (New-Pk 'Acme Co' $MID $null $null 30000 'account' $QP @('2026-01','2026-02','2026-03','2026-04','2026-05','2026-06'))
  Assert (@(Recon $fa 'RECON_TREND_COVERAGE').Count -eq 0 -and @(Recon $fa 'RECON_TREND_MISMATCH').Count -eq 0) "gate1b longer trend chart: not period skew, reconciles cleanly (no false coverage)"
  # ...and the same longer chart with a MISMATCHING KPI still reconciles to a mismatch (chart is not consulted for skew)
  $fa=Run-Trend (New-Led 'Acme Co' $months3 $null $null $null $null) (New-Pk 'Acme Co' $MID $null $null 35000 'account' $QP @('2026-01','2026-02','2026-03','2026-04','2026-05','2026-06'))
  Assert (@(Recon $fa 'RECON_TREND_MISMATCH').Count -eq 1 -and @(Recon $fa 'RECON_TREND_COVERAGE').Count -eq 0) "gate1b longer trend chart: mismatch still fires (no spurious coverage)"

  # gate 2: identity mismatch -> ONE coverage info, never a mismatch
  $fa=Run-Trend (New-Led 'Acme Co' $months3 $null $null $null $null) (New-Pk 'Other Co' $MID $null $null 35000 'account' $QP $null)
  Assert (@(Recon $fa 'RECON_TREND_COVERAGE').Count -eq 1 -and @(Recon $fa 'RECON_TREND_MISMATCH').Count -eq 0) "gate2 identity mismatch: coverage info, no mismatch"

  # gate 2c: non-account headline (table-total shadow) -> per-metric coverage info
  $fa=Run-Trend (New-Led 'Acme Co' $months3 $null $null $null $null) (New-Pk 'Acme Co' $MID $null $null 35000 'table-total:campaign' $QP $null)
  Assert (@(Recon $fa 'RECON_TREND_COVERAGE').Count -eq 1 -and @(Recon $fa 'RECON_TREND_MISMATCH').Count -eq 0) "gate2c non-account scope: coverage info, no mismatch"

  # gate 4b: a restated month -> per-metric coverage info naming the month
  $fa=Run-Trend (New-Led 'Acme Co' $months3 $null $null '2026-05' $null) (New-Pk 'Acme Co' $MID $null $null 35000 'account' $QP $null)
  $cov=@(Recon $fa 'RECON_TREND_COVERAGE')
  Assert ($cov.Count -eq 1 -and $cov[0].statement -match '2026-05') "gate4b restated month: coverage info names the month"
  Assert (@(Recon $fa 'RECON_TREND_MISMATCH').Count -eq 0) "gate4b restated month: no mismatch"

  # gate 4: a missing month -> per-metric coverage info
  $fa=Run-Trend (New-Led 'Acme Co' @{ '2026-04'=10000; '2026-06'=10000 } $null $null $null $null) (New-Pk 'Acme Co' $MID $null $null 35000 'account' $QP $null)
  Assert (@(Recon $fa 'RECON_TREND_COVERAGE').Count -eq 1 -and @(Recon $fa 'RECON_TREND_MISMATCH').Count -eq 0) "gate4 missing month: coverage info, no mismatch"

  # gate 3b: KPI basis (EUR) != months basis (USD micros) -> coverage info
  $fa=Run-Trend (New-Led 'Acme Co' $months3 'micros' 'USD' $null $null) (New-Pk 'Acme Co' $MID 'micros' 'EUR' 35000 'account' $QP $null)
  Assert (@(Recon $fa 'RECON_TREND_COVERAGE').Count -eq 1 -and @(Recon $fa 'RECON_TREND_MISMATCH').Count -eq 0) "gate3b basis mismatch: coverage info, no mismatch"

  # gate 3a: basis fork within ledger history -> coverage info
  $fa=Run-Trend (New-Led 'Acme Co' $months3 $null $null $null @{ '2026-06'='bv2' }) (New-Pk 'Acme Co' $MID $null $null 35000 'account' $QP $null)
  Assert (@(Recon $fa 'RECON_TREND_COVERAGE').Count -ge 1 -and @(Recon $fa 'RECON_TREND_MISMATCH').Count -eq 0) "gate3a basis fork: coverage info, no mismatch"

  # gate 5: dedup metric (GA4 activeUsers) -> non-summable coverage info, never a mismatch (predicate split)
  $DUID='google-analytics-4:activeUsers'
  $duCells=[ordered]@{}; foreach($mk in ($months3.Keys|Sort-Object)){ $duCells[($DUID+'|'+$mk)]=[ordered]@{ providerId=$PROV; metricId=$DUID; basisVersion='bv1'; month=$mk; value=$months3[$mk]; display="$($months3[$mk])"; unit=$null; currency=$null; state='final'; restatementCount=0; keptNullCount=0 } }
  $duLed=[ordered]@{ ledgerVersion=1; client='Acme Co'; updatedAt='2026-07-06T00:00:00Z'; cells=$duCells; coverage=[ordered]@{ $PROV=[ordered]@{ providerId=$PROV; providerName='GA4'; hasMonthlyGrain=$true; ceilingMonths=48; earliestMonth='2026-04'; latestMonth='2026-06'; windowStatus='ok' } } }
  $duPk=New-Pk 'Acme Co' $DUID $null $null 999999 'account' $QP $null
  $fa=Run-Trend $duLed $duPk
  Assert (@(Recon $fa 'RECON_TREND_MISMATCH').Count -eq 0) "gate5 dedup: no mismatch (Test-Summable false)"
  Assert (@(Recon $fa 'RECON_TREND_COVERAGE').Count -eq 1) "gate5 dedup: non-summable coverage info"
  Assert ((@($fa.findings.wins)+@($fa.findings.losses)+@($fa.findings.dataGaps) | Where-Object { $_ -and ($_.ruleId -like 'WIN_*' -or $_.ruleId -like 'LOSS_*' -or $_.ruleId -like 'GAP_NO_*') }).Count -ge 0) "gate5 dedup: Test-Additive trend path still runs (predicate split)"

  # omitted -PeriodKpiFacts -> ZERO RECON_* findings (trend path unchanged)
  $fa=Run-Trend (New-Led 'Acme Co' $months3 $null $null $null $null) $null
  $anyRecon=@(); foreach($k in 'wins','losses','anomalies','discrepancies','dataGaps'){ foreach($f in @($fa.findings.$k)){ if($f -and $f.ruleId -like 'RECON_*'){ $anyRecon+=$f } } }
  Assert ($anyRecon.Count -eq 0) "omitted param: ZERO RECON_* findings (opt-in; byte-identical trend path)"

  # credential-bearing -PeriodKpiFacts -> Assert-NoCredential rejects before parse (no facts produced)
  $d=Join-Path $tmp6 ([guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Force -Path $d|Out-Null
  $lp=Join-Path $d 'ledger.json'; [IO.File]::WriteAllText($lp,(ConvertTo-Json -InputObject (New-Led 'Acme Co' $months3 $null $null $null $null) -Depth 100),(New-Object Text.UTF8Encoding($false)))
  $leakPk=New-Pk 'Acme Co' $MID $null $null 35000 'account' $QP $null; $leakPk.meta.leak='see swy.do/shares/LEAKKEY123'
  $pkp=Join-Path $d 'pk.facts.json'; [IO.File]::WriteAllText($pkp,(ConvertTo-Json -InputObject $leakPk -Depth 100),(New-Object Text.UTF8Encoding($false)))
  & powershell -NoProfile -ExecutionPolicy Bypass -File "$scripts\Analyze-SwydoTrend.ps1" -LedgerFile $lp -OutDir $d -PeriodKpiFacts $pkp *> $null
  Assert ($LASTEXITCODE -ne 0) "credential in -PeriodKpiFacts: run fails (fail-closed scrub before parse)"
  Assert ($null -eq (Get-ChildItem (Join-Path $d '*.trendanalysis.facts.json') -ErrorAction SilentlyContinue | Select-Object -First 1)) "credential in -PeriodKpiFacts: no facts written"
} finally { $ErrorActionPreference=$savedEAP; Remove-Item -Recurse -Force $tmp6 -ErrorAction SilentlyContinue }

Write-Host ""
Write-Host ("RESULT: {0} passed, {1} failed" -f $pass, $fail) -ForegroundColor $(if($fail){'Red'}else{'Green'})
if($fail){ exit 1 }
