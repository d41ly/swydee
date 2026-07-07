<#
.SYNOPSIS
  Offline checks for Sync-SwydoTrend.ps1: it parses/loads (-DefineOnly), and it is FAIL-SOFT -- a bad
  invocation degrades to a clean non-zero exit + warning, never an uncaught throw (so it can never abort
  the primary /swydee report). Network success path is covered by the live smoke. Run: .\Test-Sync.ps1
#>
$ErrorActionPreference = "Stop"
$sync = "$PSScriptRoot\skill\scripts\Sync-SwydoTrend.ps1"
$pass=0; $fail=0
function Ok($c,$n){ if($c){ $script:pass++ } else { $script:fail++; Write-Host "  FAIL: $n" -ForegroundColor Red } }

# 1) parses + defines its helper under -DefineOnly (no run)
. $sync -DefineOnly
Ok ([bool](Get-Command Invoke-Child -EA SilentlyContinue)) "loads under -DefineOnly; Invoke-Child defined"

function RunSync([string[]]$a){
  $prev=$ErrorActionPreference; $ErrorActionPreference='Continue'; $ef=[IO.Path]::GetTempFileName()
  try { $o=& powershell -NoProfile -ExecutionPolicy Bypass -File $sync @a 2>$ef; return @{ code=$LASTEXITCODE; out=(($o -join "`n")+"`n"+[string](Get-Content -Raw $ef -EA SilentlyContinue)) } }
  finally { $ErrorActionPreference=$prev; Remove-Item $ef -EA SilentlyContinue }
}

# 2) missing -ShareUrl => clean non-zero (fail-soft), NOT an uncaught throw
$r = RunSync @('-OutDir', (Join-Path $env:TEMP ('synco-'+[guid]::NewGuid().ToString('N'))))
Ok ($r.code -ne 0) "missing -ShareUrl => non-zero exit (fail-soft)"
Ok ($r.out -match '(?i)ShareUrl required') "missing -ShareUrl => clear warning"
Ok ($r.out -notmatch '(?i)unhandled|ParentContainsErrorRecord|Exception was thrown') "no uncaught throw leaked"

Write-Host ""
Write-Host ("Test-Sync: {0} passed, {1} failed." -f $pass,$fail) -ForegroundColor $(if($fail){'Red'}else{'Green'})
if($fail){ exit 1 }
