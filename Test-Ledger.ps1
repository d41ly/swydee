<#
.SYNOPSIS
  Offline tests for Update-SwydoLedger.ps1: pure basis/freeze/merge helpers (via -DefineOnly) + an
  integration run over a real trend-facts file with a deterministic injected clock. Run: .\Test-Ledger.ps1
#>
$ErrorActionPreference = "Stop"
$scripts = "$PSScriptRoot\skill\scripts"
. "$scripts\Update-SwydoLedger.ps1" -DefineOnly

$pass=0; $fail=0
function Assert($cond,$msg){ if($cond){ $script:pass++ } else { $script:fail++; Write-Host "  FAIL: $msg" -ForegroundColor Red } }
function K($p,$m,$u,$c,$mo){ return ($p + '|' + $m + '|' + (Get-BasisVersion $m $u $c) + '|' + $mo) }
function XCell($p,$m,$u,$c,$mo,$val,$state,$extra){
  $h=@{ providerId=$p; metricId=$m; basisVersion=(Get-BasisVersion $m $u $c); month=$mo; value=$val; display=("d"+$val); unit=$u; currency=$c; state=$state; firstSeen='OLD'; lastRefreshed='OLD'; lastAttempted='OLD'; sourceStamp='OLDSTAMP'; restatementCount=0; keptNullCount=0 }
  if($extra){ foreach($k in $extra.Keys){ $h[$k]=$extra[$k] } }
  return [pscustomobject]$h
}
$NOW='2026-07-06T00:00:00Z'; $STAMP='2026-07-06-00-00-00'; $MAX='2026-06'; $KK=6
# freeze boundary with MAX=2026-06, K=6: final iff month < 2025-12  (2025-12..2026-06 = 7 provisional buckets)

Write-Host "== Get-BasisVersion (deterministic; unit/currency change => new series) =="
Assert ((Get-BasisVersion 'g:cost' 'micros' 'USD') -eq (Get-BasisVersion 'g:cost' 'micros' 'USD')) "same inputs => same hash"
Assert ((Get-BasisVersion 'g:cost' 'micros' 'USD') -ne (Get-BasisVersion 'g:cost' $null 'USD')) "unit change => different"
Assert ((Get-BasisVersion 'g:cost' 'micros' 'USD') -ne (Get-BasisVersion 'g:cost' 'micros' 'EUR')) "currency change => different"
Assert ((Get-BasisVersion 'g:cost' 'micros' 'USD').Length -eq 12) "12 hex chars"
Assert ((Get-BasisVersion 'g:cost' 'micros' 'USD') -match '^[0-9a-f]{12}$') "lowercase hex"

Write-Host "== Test-IsFinal (K=6, max 2026-06) =="
Assert (Test-IsFinal '2025-11' $MAX $KK) "2025-11 => final"
Assert (-not (Test-IsFinal '2025-12' $MAX $KK)) "2025-12 => provisional (boundary)"
Assert (-not (Test-IsFinal '2026-06' $MAX $KK)) "2026-06 => provisional"
Assert (Test-IsFinal '2022-07' $MAX $KK) "old => final"

Write-Host "== Test-ValuesDiffer (0.5% tol) =="
Assert (-not (Test-ValuesDiffer 1000 1004)) "0.4% => same"
Assert (Test-ValuesDiffer 1000 1010) "1% => differ"
Assert (-not (Test-ValuesDiffer $null 5)) "null => not differ"

Write-Host "== Merge: create (final vs provisional) =="
$m1 = Merge-LedgerCells @{} @(
  [pscustomobject]@{ providerId='g'; metricId='g:clicks'; month='2025-01'; value=100; display='100'; unit=$null; currency=$null; status='returned' }
  [pscustomobject]@{ providerId='g'; metricId='g:clicks'; month='2026-03'; value=200; display='200'; unit=$null; currency=$null; status='returned' }
) $MAX $KK $NOW $STAMP
Assert ($m1.cells[(K 'g' 'g:clicks' $null $null '2025-01')].state -eq 'final') "2025-01 created final"
Assert ($m1.cells[(K 'g' 'g:clicks' $null $null '2026-03')].state -eq 'provisional') "2026-03 created provisional"
Assert ($m1.cells[(K 'g' 'g:clicks' $null $null '2025-01')].firstSeen -eq $NOW) "firstSeen stamped"

Write-Host "== Merge: null-only sighting never creates a cell =="
$m2 = Merge-LedgerCells @{} @([pscustomobject]@{ providerId='g'; metricId='g:clicks'; month='2026-03'; value=$null; display=$null; unit=$null; currency=$null; status='overshoot-empty' }) $MAX $KK $NOW $STAMP
Assert ($m2.cells.Count -eq 0) "null-only new cell => not created"

Write-Host "== Merge: final is write-once (restatement kept + counted + surfaced) =="
$kf=K 'g' 'g:clicks' $null $null '2024-05'
$ex=@{ $kf = (XCell 'g' 'g:clicks' $null $null '2024-05' 1000 'final' $null) }
$m3 = Merge-LedgerCells $ex @([pscustomobject]@{ providerId='g'; metricId='g:clicks'; month='2024-05'; value=1200; display='1200'; unit=$null; currency=$null; status='returned' }) $MAX $KK $NOW $STAMP
Assert ($m3.cells[$kf].value -eq 1000) "final value NOT overwritten (kept 1000)"
Assert ([int]$m3.cells[$kf].restatementCount -eq 1) "restatementCount incremented"
Assert ($m3.cells[$kf].latestDisplay -eq '1200') "latest (rejected) value recorded"
Assert (@($m3.restated).Count -eq 1) "restatement event emitted"

Write-Host "== Merge: provisional refresh vs value-guarded KEEP =="
$kp=K 'g' 'g:clicks' $null $null '2026-05'
$exp=@{ $kp = (XCell 'g' 'g:clicks' $null $null '2026-05' 500 'provisional' $null) }
# real value => refresh
$m4 = Merge-LedgerCells $exp @([pscustomobject]@{ providerId='g'; metricId='g:clicks'; month='2026-05'; value=600; display='600'; unit=$null; currency=$null; status='returned' }) $MAX $KK $NOW $STAMP
Assert ($m4.cells[$kp].value -eq 600) "provisional refreshed to 600"
Assert ($m4.cells[$kp].lastRefreshed -eq $NOW) "lastRefreshed advanced on refresh"
# null/overshoot => KEEP prior, do NOT advance lastRefreshed, bump keptNullCount
$m5 = Merge-LedgerCells $exp @([pscustomobject]@{ providerId='g'; metricId='g:clicks'; month='2026-05'; value=$null; display=$null; unit=$null; currency=$null; status='overshoot-empty' }) $MAX $KK $NOW $STAMP
Assert ($m5.cells[$kp].value -eq 500) "value-guard: kept prior 500 on null pull"
Assert ($m5.cells[$kp].lastRefreshed -eq 'OLD') "value-guard: lastRefreshed NOT advanced"
Assert ([int]$m5.cells[$kp].keptNullCount -eq 1) "value-guard: keptNullCount bumped"

Write-Host "== Merge: freeze-on-aging (provisional month now past K, absent from pull) =="
$ka=K 'g' 'g:clicks' $null $null '2025-11'
$exa=@{ $ka = (XCell 'g' 'g:clicks' $null $null '2025-11' 900 'provisional' $null) }
$m6 = Merge-LedgerCells $exa @() $MAX $KK $NOW $STAMP     # not in pull; 2025-11 < 2025-12 => now final
Assert ($m6.cells[$ka].state -eq 'final') "aged provisional frozen to final"
Assert ($m6.cells[$ka].value -eq 900) "frozen value retained"

Write-Host "== Merge: basis change forks a new series (no coercion) =="
$kmicros=K 'g' 'g:cost' 'micros' 'USD' '2025-01'
$exb=@{ $kmicros = (XCell 'g' 'g:cost' 'micros' 'USD' '2025-01' 1000000 'final' $null) }
$m7 = Merge-LedgerCells $exb @([pscustomobject]@{ providerId='g'; metricId='g:cost'; month='2025-01'; value=1.0; display='$1.00'; unit=$null; currency='USD'; status='returned' }) $MAX $KK $NOW $STAMP
Assert ($m7.cells.Count -eq 2) "unit change => 2 distinct series (no merge)"
Assert ($m7.cells[$kmicros].value -eq 1000000) "original micros cell untouched"

Write-Host "== Get-MaxLabel =="
Assert ((Get-MaxLabel @([pscustomobject]@{month='2025-03'},[pscustomobject]@{month='2026-01'}) @{}) -eq '2026-01') "max from new cells"
Assert ((Get-MaxLabel @() @{ x=[pscustomobject]@{month='2024-12'} }) -eq '2024-12') "max from existing"

Write-Host "== Merge-Ledgers (union for -MergeClient) =="
# Fixtures authored as JSON (the exact shape Manage -MergeClient reads via ConvertFrom-Json).
function LJ($mo,$v,$fs,$kn){ '"g:clicks|bv|' + $mo + '":{"providerId":"g","metricId":"g:clicks","basisVersion":"bv","month":"' + $mo + '","value":' + $v + ',"display":"' + $v + '","unit":null,"currency":null,"state":"final","firstSeen":"' + $fs + '","lastRefreshed":"' + $fs + '","lastAttempted":"' + $fs + '","sourceStamp":"s","restatementCount":0,"keptNullCount":' + $kn + '}' }
# NB: variables are $intoL/$fromL, NOT $into/$from -- Manage's -MergeClient params [string]$Into/[string]$From
# leak into this dot-source scope and would coerce $into/$from to strings (same class as $facts/$Facts).
$intoL = ('{"ledgerVersion":1,"client":"Acme","cells":{' + (LJ '2025-01' 100 '2026-01-01T00:00:00Z' 1) + ',' + (LJ '2025-02' 200 '2026-01-01T00:00:00Z' 0) + '},"coverage":{"g":{"providerId":"g","providerName":"Google","ceilingMonths":48}}}') | ConvertFrom-Json
$fromL = ('{"ledgerVersion":1,"client":"Acme","cells":{' + (LJ '2025-02' 250 '2026-02-01T00:00:00Z' 2) + ',' + (LJ '2025-03' 300 '2026-02-01T00:00:00Z' 0) + '},"coverage":{}}') | ConvertFrom-Json
Assert (@($intoL.cells.PSObject.Properties).Count -eq 2) "fixture sanity: into has 2 cells"
$mr = Merge-Ledgers $intoL $fromL '2026-07-07T00:00:00Z'
$mc = $mr.ledger.cells
Assert (@($mc.Keys).Count -eq 3) "union yields 3 distinct month cells"
Assert ($mc['g:clicks|bv|2025-03'].value -eq 300) "non-overlapping from-cell imported"
Assert ($mc['g:clicks|bv|2025-02'].value -eq 200) "conflict (both final, differ): older-firstSeen value (200) kept"
Assert ([int]$mc['g:clicks|bv|2025-02'].restatementCount -eq 1) "conflict: restatementCount incremented"
Assert ($mc['g:clicks|bv|2025-02'].latestDisplay -eq '250') "conflict: newer value recorded (surfaces GAP_RESTATEMENT_SUPPRESSED)"
Assert ([int]$mc['g:clicks|bv|2025-02'].keptNullCount -eq 2) "conflict: keptNullCount summed (0+2)"
Assert (@($mr.conflicts).Count -eq 1) "one conflict reported for the dry-run preview"
Assert ($mr.ledger.coverage['g'].earliestMonth -eq '2025-01' -and $mr.ledger.coverage['g'].latestMonth -eq '2025-03') "coverage recomputed from union"
Assert ($mr.ledger.coverage['g'].providerName -eq 'Google') "coverage metadata carried"
# union with an absent into-ledger (Into folder had no ledger yet)
$mr2 = Merge-Ledgers $null $fromL '2026-07-07T00:00:00Z'
Assert (@($mr2.ledger.cells.Keys).Count -eq 2 -and @($mr2.conflicts).Count -eq 0) "union with null into = from's cells, no conflict"

Write-Host "== integration: real trend-facts -> ledger (deterministic clock) + fail-closed =="
$tmp = Join-Path $env:TEMP ("ledger-test-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$savedEAP=$ErrorActionPreference; $ErrorActionPreference='Continue'
try {
  # a real scrubbed trend-facts (produced earlier by the 2.2 smoke); skip integration if absent
  $sc = 'C:\Temp\claude\C--projects-qcu\74dba70e-b0c4-447c-8580-819c926878d2\scratchpad\trend_facts_out'
  $tf = Get-ChildItem (Join-Path $sc '*.trendfacts.json') -ErrorAction SilentlyContinue | Select-Object -First 1
  if($tf){
    & powershell -NoProfile -ExecutionPolicy Bypass -File "$scripts\Update-SwydoLedger.ps1" -InFile $tf.FullName -ArchiveRoot $tmp -NowIso '2026-07-06T00:00:00Z' -K 6 *> $null
    Assert ($LASTEXITCODE -eq 0) "ledger run exit 0"
    $lp = Get-ChildItem (Join-Path $tmp '*\ledger.json') -ErrorAction SilentlyContinue | Select-Object -First 1
    Assert ($null -ne $lp) "ledger.json written under <slug>/"
    if($lp){
      $L = [IO.File]::ReadAllText($lp.FullName) | ConvertFrom-Json
      $ncells = @($L.cells.PSObject.Properties).Count
      Assert ($ncells -eq 372) "372 cells in ledger (got $ncells)"
      # Google 2022-07..2025-11 final; 2025-12..2026-06 provisional
      $gJan24 = @($L.cells.PSObject.Properties | Where-Object { $_.Value.providerId -eq 'google-adwords' -and $_.Value.month -eq '2024-01' })
      $gJun26 = @($L.cells.PSObject.Properties | Where-Object { $_.Value.providerId -eq 'google-adwords' -and $_.Value.month -eq '2026-06' })
      Assert ($gJan24.Count -gt 0 -and $gJan24[0].Value.state -eq 'final') "old Google month is final"
      Assert ($gJun26.Count -gt 0 -and $gJun26[0].Value.state -eq 'provisional') "recent Google month is provisional"
      $txt=[IO.File]::ReadAllText($lp.FullName); Assert ($txt -notmatch '(?i)swy\.do/shares/') "no credential in ledger"
    }
  } else { Write-Host "  (skipped live-facts integration: no trendfacts fixture present)" }

  # fail-closed: planted credential in facts input
  $leak = [ordered]@{ meta=[ordered]@{ trendFactsVersion=1; reportName='Leaky'; client='https://swy.do/shares/LEAKKEY'; coverage=@() }; cells=@([ordered]@{ providerId='g'; metricId='g:clicks'; month='2025-01'; value=1; display='1'; unit=$null; currency=$null; status='returned' }) }
  $leakPath = Join-Path $tmp 'leak.trendfacts.json'
  [IO.File]::WriteAllText($leakPath, ($leak | ConvertTo-Json -Depth 40), (New-Object Text.UTF8Encoding($false)))
  & powershell -NoProfile -ExecutionPolicy Bypass -File "$scripts\Update-SwydoLedger.ps1" -InFile $leakPath -ArchiveRoot $tmp -NowIso '2026-07-06T00:00:00Z' *> $null
  Assert ($LASTEXITCODE -ne 0) "planted credential in facts => fail-closed (non-zero exit)"
  # refuse a --platform-filtered (partial) trend pull into the whole-account ledger
  $filt = [ordered]@{ meta=[ordered]@{ trendFactsVersion=1; reportName='Acme'; client='Acme'; providerFilter=@('google-adwords'); coverage=@() }; cells=@([ordered]@{ providerId='google-adwords'; metricId='google-adwords:clicks'; month='2025-01'; value=1; display='1'; unit=$null; currency=$null; status='returned' }) }
  $filtPath = Join-Path $tmp 'filtered.trendfacts.json'
  [IO.File]::WriteAllText($filtPath, ($filt | ConvertTo-Json -Depth 40), (New-Object Text.UTF8Encoding($false)))
  & powershell -NoProfile -ExecutionPolicy Bypass -File "$scripts\Update-SwydoLedger.ps1" -InFile $filtPath -ArchiveRoot $tmp -NowIso '2026-07-06T00:00:00Z' *> $null
  Assert ($LASTEXITCODE -ne 0) "--platform-filtered trend facts => refused (whole-account ledger only)"
} finally { $ErrorActionPreference=$savedEAP; Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }

Write-Host ""
Write-Host ("RESULT: {0} passed, {1} failed" -f $pass, $fail) -ForegroundColor $(if($fail){'Red'}else{'Green'})
if($fail){ exit 1 }
