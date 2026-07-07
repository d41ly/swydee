<#
.SYNOPSIS
  Refresh a client's cumulative monthly ledger from a Swydo share link: extract -Trend -> scrub/shape ->
  update ledger. A thin, FAIL-SOFT orchestrator so /swydee can keep trend history current on a normal pull
  without ever blocking the primary single-period report.
.DESCRIPTION
  Runs the three trend scripts as child processes and checks each exit code. ANY failure (e.g. a report with
  no monthly time-series widget, a network hiccup) is caught and reported as a clean non-zero exit with a
  warning -- it NEVER throws uncaught and never touches the primary report flow. On success, prints the
  ledger path. This is the reshaped idea (c): the ledger is the "prior-year + YTD, auto-updated" history,
  per-platform-probed so it can't blank a platform; the SEPARATE trend report (Analyze-SwydoTrend + closer,
  SKILL Mode C) is verified against its own trend facts -- trend numbers are NEVER woven into the
  single-period report (they wouldn't trace against the single-period facts).
.PARAMETER DefineOnly
  Load and return without running (parse check / tests).
.EXAMPLE
  .\Sync-SwydoTrend.ps1 -ShareUrl https://swy.do/shares/<KEY> -Secret 123 -OutDir .\tmp
#>
param(
  [string]$ShareUrl,
  [string]$Secret = "",
  [string]$OutDir = ".\trend-tmp",
  [string]$ArchiveRoot = "",
  [string]$CacheDir = "",
  [string[]]$Platform,
  [switch]$DefineOnly
)
$ErrorActionPreference = "Stop"
$script:here = $PSScriptRoot

# Run a bundled script as a child process; return @{ ok=$bool; out=<combined stdout+stderr> }. Child stderr
# is captured to a file (never 2>&1, which wraps+terminates under Stop in PS 5.1).
function Invoke-Child($scriptName,$scriptArgs){
  $ef=[IO.Path]::GetTempFileName()
  $prev=$ErrorActionPreference; $ErrorActionPreference='Continue'
  try {
    $full = @("-NoProfile","-ExecutionPolicy","Bypass","-File",(Join-Path $script:here $scriptName)) + $scriptArgs
    $o = & powershell @full 2>$ef
    $code=$LASTEXITCODE
    $err=Get-Content -Raw $ef -ErrorAction SilentlyContinue
    return @{ ok=($code -eq 0); out=(($o -join "`n") + "`n" + [string]$err) }
  } catch { return @{ ok=$false; out=[string]$_.Exception.Message } }
  finally { $ErrorActionPreference=$prev; Remove-Item $ef -ErrorAction SilentlyContinue }
}

if($DefineOnly){ return }

# ================================ run (fail-soft) ================================
try {
  if(-not $ShareUrl){ Write-Warning "Sync-SwydoTrend: -ShareUrl required"; exit 2 }
  New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

  # 1) extract -Trend
  $a1 = @("-Trend","-ShareUrl",$ShareUrl,"-OutDir",$OutDir)
  if($Secret){ $a1 += @("-Secret",$Secret) }
  if($CacheDir){ $a1 += @("-CacheDir",$CacheDir) }
  if($Platform){ $a1 += @("-Platform",($Platform -join ',')) }
  $r1 = Invoke-Child 'Get-SwydoReport.ps1' $a1
  if(-not $r1.ok){ Write-Warning ("trend extract failed (history not updated this run): " + ($r1.out -split "`n" | Select-Object -Last 3 | Out-String).Trim()); exit 1 }
  $rawT = Get-ChildItem (Join-Path $OutDir '*.trend.json') -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 1
  if(-not $rawT){ Write-Warning "trend extract produced no *.trend.json (no monthly time series?)"; exit 1 }

  # 2) scrub + shape (the ONLY reader of the raw trend extraction)
  $r2 = Invoke-Child 'ConvertTo-SwydoTrendFacts.ps1' @("-InFile",$rawT.FullName,"-OutDir",$OutDir)
  if(-not $r2.ok){ Write-Warning ("trend-facts step failed: " + ($r2.out -split "`n" | Select-Object -Last 3 | Out-String).Trim()); exit 1 }
  $tf = Get-ChildItem (Join-Path $OutDir '*.trendfacts.json') -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 1
  if(-not $tf){ Write-Warning "trend-facts step produced no *.trendfacts.json"; exit 1 }

  # 3) merge into the per-client ledger (canonical folder by clientId via the registry)
  $a3 = @("-InFile",$tf.FullName)
  if($ArchiveRoot){ $a3 += @("-ArchiveRoot",$ArchiveRoot) }
  $r3 = Invoke-Child 'Update-SwydoLedger.ps1' $a3
  if(-not $r3.ok){ Write-Warning ("ledger update failed: " + ($r3.out -split "`n" | Select-Object -Last 3 | Out-String).Trim()); exit 1 }

  $ledgerLine = @($r3.out -split "`n" | Where-Object { $_ -match 'ledger ->' }) | Select-Object -Last 1
  Write-Host ("trend synced. " + $(if($ledgerLine){ $ledgerLine.Trim() } else { "ledger updated." }))
  exit 0
} catch {
  # never let a trend failure surface as an uncaught error to the caller
  Write-Warning ("Sync-SwydoTrend degraded (primary report unaffected): " + $_.Exception.Message)
  exit 1
}
