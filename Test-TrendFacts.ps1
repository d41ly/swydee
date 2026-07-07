<#
.SYNOPSIS
  Offline tests for ConvertTo-SwydoTrendFacts.ps1: pure cell/coverage shaping (via -DefineOnly) plus a
  self-contained integration test that plants a credential to prove the fail-closed gate. Run: .\Test-TrendFacts.ps1
#>
$ErrorActionPreference = "Stop"
$scripts = "$PSScriptRoot\skill\scripts"
. "$scripts\ConvertTo-SwydoTrendFacts.ps1" -DefineOnly   # loads its funcs + (transitively) Format-Metric etc.

$pass=0; $fail=0
function Assert($cond,$msg){ if($cond){ $script:pass++ } else { $script:fail++; Write-Host "  FAIL: $msg" -ForegroundColor Red } }

Write-Host "== ConvertTo-TrendFactCells (display + status + provider fallback) =="
$doc = [pscustomobject]@{ trendCells = @(
  [pscustomobject]@{ providerId='google-adwords'; metricId='google-adwords:cost_micros';     month='2025-01'; rawValue=1000000;  currency='USD'; unit='micros' }
  [pscustomobject]@{ providerId='google-adwords'; metricId='google-adwords:conversion_rate'; month='2025-01'; rawValue=0.05;     currency='USD'; unit='fraction' }
  [pscustomobject]@{ providerId='google-adwords'; metricId='google-adwords:clicks';          month='2025-01'; rawValue=50;       currency='USD'; unit=$null }
  [pscustomobject]@{ providerId=$null;            metricId='facebook-ads:spend';              month='2025-02'; rawValue=$null;    currency='USD'; unit='micros' }
) }
$cells = @(ConvertTo-TrendFactCells $doc)
Assert (@($cells).Count -eq 4) "4 cells"
Assert ($cells[0].display -eq '$1.00') "cost_micros 1e6 => `$1.00 (got '$($cells[0].display)')"
Assert ($cells[0].status -eq 'returned') "non-null => returned"
Assert ($cells[0].value -eq 1000000) "raw value preserved"
Assert ($cells[1].display -eq '5.0%') "fraction 0.05 => 5.0% (got '$($cells[1].display)')"
Assert ($cells[2].display -eq '50') "count 50 => 50"
Assert ($cells[3].status -eq 'null' -and $null -eq $cells[3].display) "null rawValue => status null, display null"
Assert ($cells[3].providerId -eq 'facebook-ads') "provider fallback from metric id"

Write-Host "== Select-CoverageFacts (safe fields only) =="
$cov = @(Select-CoverageFacts @([pscustomobject]@{ providerId='g'; providerName='G'; hasMonthlyGrain=$true; ceilingMonths=48; earliestMonth='2022-07'; latestMonth='2026-06'; windowStatus='ok'; probedAt='x'; secret='LEAK' }))
Assert (@($cov).Count -eq 1) "1 coverage entry"
Assert (-not ($cov[0].PSObject.Properties.Name -contains 'secret')) "extra fields dropped"
Assert (-not ($cov[0].PSObject.Properties.Name -contains 'probedAt')) "probedAt not copied"
Assert ($cov[0].ceilingMonths -eq 48) "ceilingMonths kept"

Write-Host "== integration: scrub + fail-closed gate (child process) =="
$tmp = Join-Path $env:TEMP ("trendfacts-test-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$savedEAP = $ErrorActionPreference; $ErrorActionPreference = 'Continue'   # child stderr (the intentional fail-closed throw) must NOT escalate to a terminating NativeCommandError
try {
  # (a) clean doc with a credential ONLY in meta (scrubbed) -> should succeed and leak nothing
  $clean = [ordered]@{
    meta=[ordered]@{ tool='Get-SwydoReport.ps1'; schemaVersion=2; trend=$true; extractedAt='2026-07-06T00:00:00Z'
      shareUrl='https://swy.do/shares/SECRETKEY123'; shareKey='SECRETKEY123'; reportId='rid'
      coverage=@([ordered]@{ providerId='google-adwords'; providerName='Google Ads'; hasMonthlyGrain=$true; ceilingMonths=48; earliestMonth='2022-07'; latestMonth='2026-06'; windowStatus='ok' }); warnings=@(); providerFilter=@('google-adwords'); providerInventory=@('google-adwords','facebook-ads') }
    report=[ordered]@{ name='Test Client'; client='Test Client' }
    trendCells=@( [ordered]@{ providerId='google-adwords'; metricId='google-adwords:cost_micros'; month='2025-01'; rawValue=1000000; currency='USD'; unit='micros' } )
  }
  $cleanPath = Join-Path $tmp 'clean.trend.json'
  [IO.File]::WriteAllText($cleanPath, ($clean | ConvertTo-Json -Depth 40), (New-Object Text.UTF8Encoding($false)))
  & powershell -NoProfile -ExecutionPolicy Bypass -File "$scripts\ConvertTo-SwydoTrendFacts.ps1" -InFile $cleanPath -OutDir $tmp *> $null
  $okExit = ($LASTEXITCODE -eq 0)
  Assert $okExit "clean doc => exit 0"
  $outFile = Get-ChildItem (Join-Path $tmp '*.trendfacts.json') | Select-Object -First 1
  Assert ($null -ne $outFile) "trendfacts file produced"
  if($outFile){
    $txt = [IO.File]::ReadAllText($outFile.FullName)
    Assert ($txt -notmatch '(?i)swy\.do/shares/|SECRETKEY123') "output has NO share key/url (scrubbed)"
    $of = $txt | ConvertFrom-Json
    Assert (@($of.cells).Count -eq 1 -and $of.cells[0].display -eq '$1.00') "cell shaped + formatted"
    Assert ((@($of.meta.providerFilter) -contains 'google-adwords') -and (@($of.meta.providerInventory) -contains 'facebook-ads')) "providerFilter/inventory carried into trend facts (so the ledger can refuse a partial pull)"
  }

  # (b) credential planted in a NON-scrubbed field (report.client) -> gate must FAIL closed (non-zero exit)
  $leak = [ordered]@{
    meta=[ordered]@{ tool='Get-SwydoReport.ps1'; schemaVersion=2; trend=$true; extractedAt='2026-07-06T00:00:00Z'; shareUrl=$null; shareKey=$null; reportId='rid'; coverage=@(); warnings=@() }
    report=[ordered]@{ name='Leaky'; client='https://swy.do/shares/LEAKKEY999' }
    trendCells=@( [ordered]@{ providerId='g'; metricId='g:clicks'; month='2025-01'; rawValue=1; currency=$null; unit=$null } )
  }
  $leakPath = Join-Path $tmp 'leak.trend.json'
  [IO.File]::WriteAllText($leakPath, ($leak | ConvertTo-Json -Depth 40), (New-Object Text.UTF8Encoding($false)))
  & powershell -NoProfile -ExecutionPolicy Bypass -File "$scripts\ConvertTo-SwydoTrendFacts.ps1" -InFile $leakPath -OutDir $tmp *> $null
  Assert ($LASTEXITCODE -ne 0) "planted credential => fail-closed (non-zero exit)"
  Assert ($null -eq (Get-ChildItem (Join-Path $tmp '*leaky*.trendfacts.json') -ErrorAction SilentlyContinue)) "no facts file written on leak"
} finally { $ErrorActionPreference = $savedEAP; Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }

Write-Host ""
Write-Host ("RESULT: {0} passed, {1} failed" -f $pass, $fail) -ForegroundColor $(if($fail){'Red'}else{'Green'})
if($fail){ exit 1 }
