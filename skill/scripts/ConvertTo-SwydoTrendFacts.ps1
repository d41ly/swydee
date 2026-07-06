<#
.SYNOPSIS
  Turn a RAW trend extraction (Get-SwydoReport.ps1 -Trend, meta.trend=true) into a SCRUBBED, per-month
  trend-facts file that the ledger (Update-SwydoLedger.ps1) consumes.
.DESCRIPTION
  This is the trend analog of Analyze's scrub role: it is the ONLY script that opens the raw trend
  extraction (which carries the live share key/url in meta). It removes credentials, fails CLOSED if any
  credential-shaped text survives, and emits per-(providerId, metricId, YYYY-MM) cells:
    { providerId, metricId, month, value(raw), display, unit, currency, status }
  status = 'returned' (a real value came back) | 'null' (row present but value null). Months that were not
  returned at all simply have no cell -- the ledger's value-guard treats absence as KEEP.

  OUTPUT (trendFactsVersion 1):
    meta:  { tool, trendFactsVersion, computedFrom, reportName, client, extractedAt, coverage[], cellCount, warnings[] }
    cells: [ { providerId, metricId, month, value, display, unit, currency, status } ]
  Reuses Format-Metric / Scrub-Credential / Assert-NoCredential (Analyze) and Test-HasCredProps (Manage)
  via -DefineOnly dot-sourcing -- no divergent copies, no changes to those hardened scripts.
.PARAMETER DefineOnly
  Define functions and return WITHOUT running (for tests).
.EXAMPLE
  .\ConvertTo-SwydoTrendFacts.ps1 -InFile .\extractions\...-report.trend.json -OutDir .\extractions
#>
param(
  [string]$InFile,
  [string]$OutDir = "",
  [switch]$DefineOnly
)
$ErrorActionPreference = "Stop"
# Capture our own params BEFORE dot-sourcing: dot-sourcing shares scope, so the helper scripts' param
# binding clobbers $DefineOnly/$InFile/$OutDir. Use the $my* copies for our own logic.
$myInFile=$InFile; $myOutDir=$OutDir; $myDefineOnly=[bool]$DefineOnly
. "$PSScriptRoot\Manage-SwydoArchive.ps1" -DefineOnly     # Get-ClientSlug, Test-HasCredProps
. "$PSScriptRoot\Analyze-SwydoReport.ps1" -DefineOnly     # Format-Metric, Scrub-Credential, Assert-NoCredential, $script:KeyPattern (sourced last => authoritative)

# ---- pure: build the per-month cell list from a parsed raw trend doc ----
function ConvertTo-TrendFactCells($doc){
  $cells=[System.Collections.ArrayList]@()
  foreach($c in @($doc.trendCells)){
    if($null -eq $c){ continue }               # @($null) yields a [null] element; skip it
    $mid=[string]$c.metricId
    $prov=if($c.providerId){ [string]$c.providerId } else { ($mid -split ':')[0] }
    $val=$c.rawValue
    $unit=$c.unit; $cur=$c.currency
    $disp=$null; try { $disp=Format-Metric $mid $unit $val $cur } catch { $disp=$null }
    $status=if($null -ne $val){ 'returned' } else { 'null' }
    [void]$cells.Add([ordered]@{
      providerId=$prov; metricId=$mid; month=[string]$c.month
      value=$val; display=$disp; unit=$unit; currency=$cur; status=$status
    })
  }
  return $cells   # ArrayList; callers wrap with @() to normalize 1-vs-N
}
# ---- pure: copy the safe coverage fields (no credentials) ----
# Build with an explicit ArrayList (NOT a pipeline emitting [ordered] dicts, which PS can enumerate/unwrap).
function Select-CoverageFacts($coverage){
  $out=[System.Collections.ArrayList]@()
  foreach($c in @($coverage)){
    if($null -eq $c){ continue }               # @($null) yields a [null] element; skip it
    [void]$out.Add([ordered]@{
      providerId=$c.providerId; providerName=$c.providerName; hasMonthlyGrain=$c.hasMonthlyGrain
      ceilingMonths=$c.ceilingMonths; earliestMonth=$c.earliestMonth; latestMonth=$c.latestMonth; windowStatus=$c.windowStatus
    })
  }
  return $out   # ArrayList; callers wrap with @() to normalize 1-vs-N
}

if($myDefineOnly){ return }

# ================================ run ================================
if(-not $myInFile){ throw "InFile is required" }
if(-not $myOutDir){ $myOutDir = Split-Path -Parent $myInFile }
New-Item -ItemType Directory -Force -Path $myOutDir | Out-Null

$doc = [IO.File]::ReadAllText($myInFile) | ConvertFrom-Json    # .NET UTF-8 (BOM-safe in PS 5.1)
if($doc.meta.schemaVersion -ne 2 -or -not $doc.meta.trend){ throw "not a trend extraction (need meta.schemaVersion=2 + meta.trend=true) - run Get-SwydoReport.ps1 -Trend" }
$doc = Scrub-Credential $doc                                 # remove meta.shareKey/shareUrl in place

$cells = @(ConvertTo-TrendFactCells $doc)
$cov   = @(Select-CoverageFacts $doc.meta.coverage)
# NOTE: variable is $factsDoc, NOT $facts -- a dot-sourced script declares a [string]$Facts, and PS variable
# names are case-insensitive, so `$facts = [ordered]@{}` would coerce to its ToString(). (Same trap the closer
# avoided with $factsObj.)
$factsDoc = [ordered]@{
  meta = [ordered]@{
    tool='ConvertTo-SwydoTrendFacts.ps1'; trendFactsVersion=1; computedFrom=$doc.meta.tool
    reportName=$doc.report.name; client=$doc.report.client; extractedAt=$doc.meta.extractedAt
    coverage=$cov; cellCount=$cells.Count; warnings=@($doc.meta.warnings)
  }
  cells = $cells
}
$json = ConvertTo-Json -InputObject $factsDoc -Depth 40 -Compress   # -InputObject: never pipe an ordered dict (PS may enumerate it)
Assert-NoCredential $json                                    # regex gate (fail-closed)
if(Test-HasCredProps ($json | ConvertFrom-Json)){ throw "CREDENTIAL LEAK: credential-shaped property in trend facts" }  # structural gate

$stamp=(Get-Date).ToString('yyyy-MM-dd-HH-mm-ss')
$slug=($doc.report.name -replace '[^A-Za-z0-9]+','-').Trim('-').ToLower(); if(-not $slug){ $slug='report' }
$path=Join-Path $myOutDir "$stamp-$slug.trendfacts.json"
[IO.File]::WriteAllText($path,$json,(New-Object Text.UTF8Encoding($false)))
Write-Host ("trend facts -> {0}  ({1} cells, {2} providers)" -f $path,$cells.Count,@($factsDoc.meta.coverage).Count)
