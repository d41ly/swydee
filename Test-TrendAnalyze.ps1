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

Write-Host ""
Write-Host ("RESULT: {0} passed, {1} failed" -f $pass, $fail) -ForegroundColor $(if($fail){'Red'}else{'Green'})
if($fail){ exit 1 }
