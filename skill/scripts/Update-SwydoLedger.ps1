<#
.SYNOPSIS
  Merge a SCRUBBED trend-facts file (ConvertTo-SwydoTrendFacts.ps1) into a per-client cumulative MONTHLY
  ledger, applying freeze-old / refresh-recent with a value-guard. Never reads a raw extraction.
.DESCRIPTION
  The ledger is the union of every monthly window ever pulled, so history grows unbounded even though each
  live pull is trailing and ceiling-bound. Policy (restatement horizon K, default 6):
    * a month strictly older than K months before the newest complete month is FINAL / write-once -- a later
      pull that disagrees keeps the frozen value and increments restatementCount (surfaced by 2.4);
    * a month within K is PROVISIONAL and is overwritten ONLY by a real (non-null) value (value-guard): a
      null / not-returned pull keeps the prior value, bumps keptNullCount, and does NOT advance lastRefreshed;
    * a provisional month that has aged past K is frozen with its retained value (even if absent this pull).
  Cells are keyed providerId|metricId|basisVersion|YYYY-MM where basisVersion is a per-metric SHA256 over
  {metricId, unit, currency} -- a unit/currency change starts a NEW series (never coerced).

  LEDGER (ledgerVersion 1): { ledgerVersion, client, updatedAt, cells{ key -> {...} }, coverage{ provider -> {...} } }
  Reuses Get-ClientSlug / Test-HasCredProps (Manage) + Scrub-Credential / Assert-NoCredential (Analyze) via
  -DefineOnly dot-sourcing. Retention (Manage-SwydoArchive -Cleanup) is UNCHANGED: final cells are
  self-sufficient; sourceStamp is a provenance label, not a live dependency.
.PARAMETER DefineOnly
  Define functions and return WITHOUT running (for tests).
.EXAMPLE
  .\Update-SwydoLedger.ps1 -InFile .\extractions\...-report.trendfacts.json
#>
param(
  [string]$InFile,
  [string]$ArchiveRoot = "",
  [string]$Client = "",
  [string]$NowIso = "",
  [int]$K = 6,
  [switch]$DefineOnly
)
$ErrorActionPreference = "Stop"
$myInFile=$InFile; $myArchiveRoot=$ArchiveRoot; $myClient=$Client; $myNowIso=$NowIso; $myK=$K; $myDefineOnly=[bool]$DefineOnly
. "$PSScriptRoot\Manage-SwydoArchive.ps1" -DefineOnly     # Get-ClientSlug, Test-HasCredProps
. "$PSScriptRoot\Analyze-SwydoReport.ps1" -DefineOnly     # Scrub-Credential, Assert-NoCredential, $script:KeyPattern (last => authoritative)

# ---------- pure month arithmetic (local; trivial, kept identical to the extractor's) ----------
function MonthKeyToOrdinal($mk){ if([string]$mk -match '^(\d{4})-(\d{2})$'){ return ([int]$Matches[1])*12 + ([int]$Matches[2] - 1) } return $null }

# ---------- pure: per-metric basis version (unit/currency change => new series, never coerced) ----------
function Get-BasisVersion($metricId,$unit,$currency){
  $u = if($null -eq $unit){ '~' } else { [string]$unit }
  $c = if($null -eq $currency){ '~' } else { [string]$currency }
  $s = ([string]$metricId) + ([char]0x1F) + $u + ([char]0x1F) + $c
  $sha=[Security.Cryptography.SHA256]::Create()
  try { $bytes=$sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($s)) } finally { $sha.Dispose() }
  $sb=New-Object Text.StringBuilder
  foreach($b in $bytes){ [void]$sb.Append($b.ToString('x2')) }   # 'x2' = culture-invariant lowercase hex
  return $sb.ToString().Substring(0,12)
}
# ---------- pure: freeze classifier (month arithmetic on the newest complete month; K months provisional) ----------
function Test-IsFinal($monthKey,$maxLabel,$Horizon){    # $Horizon (not $K): $k is a common loop var and PS names are case-insensitive
  $m=MonthKeyToOrdinal $monthKey; $x=MonthKeyToOrdinal $maxLabel
  if($null -eq $m -or $null -eq $x){ return $false }
  return ($m -lt ($x - $Horizon))
}
# ---------- pure: do two numeric values differ beyond a 0.5% relative tolerance? ----------
function Test-ValuesDiffer($a,$b){
  if($null -eq $a -or $null -eq $b){ return $false }
  $da=[double]$a; $db=[double]$b
  $denom=[math]::Max([math]::Abs($da),1)
  return (([math]::Abs($da-$db))/$denom) -gt 0.005
}
# ---------- pure: copy a cell (PSCustomObject from JSON, or ordered dict) into a fresh ordered dict ----------
function Copy-Cell($c){
  $o=[ordered]@{}
  if($c -is [System.Collections.IDictionary]){ foreach($k in $c.Keys){ $o[$k]=$c[$k] } }   # ordered dict: iterate keys, not .PSObject members
  else { foreach($p in $c.PSObject.Properties){ $o[$p.Name]=$p.Value } }                     # PSCustomObject (from JSON)
  return $o
}
# ---------- pure: the merge (freeze-old / refresh-recent / value-guard). No IO. ----------
# $existing: hashtable key->cell (prior ledger). $newCells: array of {providerId,metricId,month,value,display,unit,currency,status}.
# Returns @{ cells=<ordered key->cell>; restated=@(events) }.
function Merge-LedgerCells($existing, $newCells, $maxLabel, $Horizon, $nowIso, $stamp){
  $out=[ordered]@{}
  foreach($ek in $existing.Keys){ $out[$ek]=Copy-Cell $existing[$ek] }
  $restated=@()
  foreach($nc in @($newCells)){
    $bv=Get-BasisVersion $nc.metricId $nc.unit $nc.currency
    $key=([string]$nc.providerId + '|' + [string]$nc.metricId + '|' + $bv + '|' + [string]$nc.month)
    $final=Test-IsFinal $nc.month $maxLabel $Horizon
    $hasVal=($nc.status -eq 'returned' -and $null -ne $nc.value)
    if(-not $out.Contains($key)){
      if(-not $hasVal){ continue }                      # never create a cell from a null-only sighting
      $st = if($final){ 'final' } else { 'provisional' }
      $out[$key]=[ordered]@{
        providerId=[string]$nc.providerId; metricId=[string]$nc.metricId; basisVersion=$bv; month=[string]$nc.month
        value=$nc.value; display=$nc.display; unit=$nc.unit; currency=$nc.currency; state=$st
        firstSeen=$nowIso; lastRefreshed=$nowIso; lastAttempted=$nowIso; sourceStamp=$stamp; restatementCount=0; keptNullCount=0
      }
      continue
    }
    $cell=$out[$key]
    $cell.lastAttempted=$nowIso
    if($cell.state -eq 'final'){
      if($hasVal -and (Test-ValuesDiffer $cell.value $nc.value)){
        $cell.restatementCount=[int]$cell.restatementCount + 1
        $cell.latestValue=$nc.value; $cell.latestDisplay=$nc.display
        $restated += [ordered]@{ key=$key; providerId=[string]$nc.providerId; metricId=[string]$nc.metricId; month=[string]$nc.month; frozen=$cell.display; latest=$nc.display }
      }
      # write-once: never overwrite a final value
    } else {
      if($hasVal){                                       # provisional + real value => refresh
        $cell.value=$nc.value; $cell.display=$nc.display; $cell.unit=$nc.unit; $cell.currency=$nc.currency
        $cell.sourceStamp=$stamp; $cell.lastRefreshed=$nowIso
      } else {                                           # value-guarded KEEP: hold prior value; do NOT advance lastRefreshed
        $cell.keptNullCount=[int]$cell.keptNullCount + 1
      }
      if($final){ $cell.state='final' }                  # freeze on aging (retains the value)
    }
  }
  # freeze-on-aging for cells not present in this pull (missing final kept; aged provisional frozen)
  foreach($ck in @($out.Keys)){
    $cell=$out[$ck]
    if($cell.state -eq 'provisional' -and (Test-IsFinal $cell.month $maxLabel $Horizon)){ $cell.state='final' }
  }
  return @{ cells=$out; restated=$restated }
}
# ---------- pure: newest month label across new + existing (freeze boundary anchor) ----------
function Get-MaxLabel($newCells,$existing){
  $best=$null
  foreach($nc in @($newCells)){ $o=MonthKeyToOrdinal $nc.month; if($null -ne $o -and ($null -eq $best -or $o -gt $best.o)){ $best=@{o=$o;k=[string]$nc.month} } }
  foreach($k in $existing.Keys){ $mk=$existing[$k].month; $o=MonthKeyToOrdinal $mk; if($null -ne $o -and ($null -eq $best -or $o -gt $best.o)){ $best=@{o=$o;k=[string]$mk} } }
  if($null -eq $best){ return $null }
  return $best.k
}
# ---------- pure: UNION two ledgers for the SAME client (for Manage -MergeClient). Distinct from
# Merge-LedgerCells: that gates on trend-facts $status; ledger cells carry $state, so this must fold cells
# directly. A key final-in-BOTH with differing values keeps the older-firstSeen value AND records the newer
# as a restatement (latestValue/Display -> Analyze-SwydoTrend surfaces GAP_RESTATEMENT_SUPPRESSED); never drops
# silently. Returns @{ ledger; conflicts }. ----------
function Merge-Ledgers($intoObj,$fromObj,$nowIso){
  $cells=[ordered]@{}; $conflicts=@()
  if($intoObj -and $intoObj.cells){ foreach($p in $intoObj.cells.PSObject.Properties){ $cells[$p.Name]=Copy-Cell $p.Value } }
  if($fromObj -and $fromObj.cells){
    foreach($p in $fromObj.cells.PSObject.Properties){
      $k=$p.Name; $fc=Copy-Cell $p.Value
      if(-not $cells.Contains($k)){ $cells[$k]=$fc; continue }
      $ic=$cells[$k]
      $mergedFirst = if(([string]$fc.firstSeen) -and (([string]$ic.firstSeen -eq '') -or ([string]$fc.firstSeen -lt [string]$ic.firstSeen))){ [string]$fc.firstSeen } else { [string]$ic.firstSeen }
      $mergedLast  = if(([string]$fc.lastRefreshed) -gt ([string]$ic.lastRefreshed)){ [string]$fc.lastRefreshed } else { [string]$ic.lastRefreshed }
      $sumKept = [int]$ic.keptNullCount + [int]$fc.keptNullCount
      $maxRestate = [Math]::Max([int]$ic.restatementCount,[int]$fc.restatementCount)
      $bothFinal = (([string]$ic.state -eq 'final') -and ([string]$fc.state -eq 'final'))
      if($bothFinal -and (Test-ValuesDiffer $ic.value $fc.value)){
        $keepInto = (([string]$ic.firstSeen) -le ([string]$fc.firstSeen))   # deterministic: older firstSeen wins
        $win = if($keepInto){ $ic } else { $fc }
        $lose = if($keepInto){ $fc } else { $ic }
        $win.restatementCount = $maxRestate + 1
        $win.latestValue = $lose.value; $win.latestDisplay = $lose.display
        $win.keptNullCount = $sumKept; $win.firstSeen = $mergedFirst; $win.lastRefreshed = $mergedLast
        $cells[$k]=$win
        $conflicts += [ordered]@{ key=$k; kept=[string]$win.display; dropped=[string]$lose.display }
      } else {
        $ic.restatementCount=$maxRestate; $ic.keptNullCount=$sumKept; $ic.firstSeen=$mergedFirst; $ic.lastRefreshed=$mergedLast
        if(([string]$ic.state -ne 'final') -and ([string]$fc.state -eq 'final')){ $ic.state='final'; $ic.value=$fc.value; $ic.display=$fc.display }
        $cells[$k]=$ic
      }
    }
  }
  # coverage recomputed from the unioned cells + carried metadata (providerName/ceiling/grain/windowStatus)
  $covOut=[ordered]@{}; $byProv=@{}
  foreach($ck in $cells.Keys){ $c=$cells[$ck]; $pr=[string]$c.providerId; if(-not $byProv.ContainsKey($pr)){ $byProv[$pr]=[System.Collections.ArrayList]@() }; [void]$byProv[$pr].Add([string]$c.month) }
  foreach($pr in $byProv.Keys){ $ms=@($byProv[$pr]|Sort-Object -Unique); $covOut[$pr]=[ordered]@{ providerId=$pr; earliestMonth=$ms[0]; latestMonth=$ms[-1]; monthCount=$ms.Count } }
  foreach($src in @($intoObj,$fromObj)){ if($src -and $src.coverage){ foreach($cp in $src.coverage.PSObject.Properties){ $pr=$cp.Name; if($covOut.Contains($pr)){ $v=$cp.Value; if($v.providerName){$covOut[$pr].providerName=$v.providerName}; if($null -ne $v.ceilingMonths){$covOut[$pr].ceilingMonths=$v.ceilingMonths}; if($null -ne $v.hasMonthlyGrain){$covOut[$pr].hasMonthlyGrain=$v.hasMonthlyGrain}; if($v.windowStatus){$covOut[$pr].windowStatus=$v.windowStatus} } } } }
  $client = if($intoObj -and $intoObj.client){ [string]$intoObj.client } elseif($fromObj -and $fromObj.client){ [string]$fromObj.client } else { 'client' }
  $ledger=[ordered]@{ ledgerVersion=1; client=$client; updatedAt=[string]$nowIso; cells=$cells; coverage=$covOut }
  return @{ ledger=$ledger; conflicts=$conflicts }
}

if($myDefineOnly){ return }

# ================================ run ================================
if(-not $myInFile){ throw "InFile is required" }
if(-not $myArchiveRoot){ $myArchiveRoot = if($PSScriptRoot){ Join-Path (Split-Path $PSScriptRoot -Parent) 'archive' } else { Join-Path $HOME 'swydee-archive' } }
$nowIso = if($myNowIso){ $myNowIso } else { ([datetimeoffset](Get-Date)).ToString('o') }
$stamp  = ([datetimeoffset]$nowIso).ToString('yyyy-MM-dd-HH-mm-ss')

$txt = [IO.File]::ReadAllText($myInFile)
Assert-NoCredential $txt                                    # input must be already-scrubbed trend facts (fail-closed)
$tf = $txt | ConvertFrom-Json
if($tf.meta.trendFactsVersion -ne 1){ throw "not a trend-facts file (need meta.trendFactsVersion=1) - run ConvertTo-SwydoTrendFacts.ps1" }

# Canonical client folder by stable clientId via the registry (same resolution as Manage -Store, so a report
# pull and a trend pull for the same client land in ONE folder). Reused via -DefineOnly dot-source of Manage.
$rootN = Normalize-Root $myArchiveRoot
New-Item -ItemType Directory -Force -Path $rootN | Out-Null
$clientId = [string]$tf.meta.clientId
$canonName = if($myClient){ [string]$myClient } elseif($tf.meta.client){ [string]$tf.meta.client } elseif($tf.meta.reportName){ [string]$tf.meta.reportName } else { 'client' }
$reg = Read-ClientRegistry $rootN
$res = Resolve-ClientSlug $clientId $canonName $reg.clients
$slug = $res.slug; $clientName = $res.name
if($clientId){
  if($reg.clients.ContainsKey($clientId)){
    $e = $reg.clients[$clientId]; $e.slug = $slug; $e.lastSeen = $nowIso
    foreach($al in @($canonName,$myClient)){ if($al -and ($e.name -ne $al) -and (@($e.aliases) -notcontains $al)){ $e.aliases = @(@($e.aliases) + $al) } }
  } else {
    $al=@(); if($myClient -and ($myClient -ne $canonName)){ $al=@($myClient) }
    $reg.clients[$clientId] = [ordered]@{ slug=$slug; name=$canonName; aliases=$al; firstSeen=$nowIso; lastSeen=$nowIso }
  }
  Write-ClientRegistry $rootN $reg
}
$ledgerDir = Join-Path $rootN $slug
New-Item -ItemType Directory -Force -Path $ledgerDir | Out-Null
$ledgerPath = Join-Path $ledgerDir 'ledger.json'

$existing=@{}
if(Test-Path $ledgerPath){
  $prev=[IO.File]::ReadAllText($ledgerPath) | ConvertFrom-Json
  if($prev.cells){ foreach($p in $prev.cells.PSObject.Properties){ $existing[$p.Name]=$p.Value } }
}
$newCells=@($tf.cells)
$maxLabel=Get-MaxLabel $newCells $existing
if(-not $maxLabel){ throw "no month labels in trend facts or ledger - nothing to merge" }

$merged = Merge-LedgerCells $existing $newCells $maxLabel $myK $nowIso $stamp

# coverage recomputed from the merged cells (union), overlaid with the latest probe facts
$covOut=[ordered]@{}
$byProv=@{}
foreach($ck in $merged.cells.Keys){ $cell=$merged.cells[$ck]; $p=[string]$cell.providerId; if(-not $byProv.ContainsKey($p)){ $byProv[$p]=[System.Collections.ArrayList]@() }; [void]$byProv[$p].Add([string]$cell.month) }
foreach($p in $byProv.Keys){
  $ms=@($byProv[$p] | Sort-Object -Unique)
  $covOut[$p]=[ordered]@{ providerId=$p; earliestMonth=$ms[0]; latestMonth=$ms[-1]; monthCount=$ms.Count }
}
foreach($fc in @($tf.meta.coverage)){
  $p=[string]$fc.providerId; if(-not $covOut.Contains($p)){ $covOut[$p]=[ordered]@{ providerId=$p } }
  $covOut[$p].providerName=$fc.providerName; $covOut[$p].hasMonthlyGrain=$fc.hasMonthlyGrain
  $covOut[$p].ceilingMonths=$fc.ceilingMonths; $covOut[$p].windowStatus=$fc.windowStatus
}

$ledger=[ordered]@{ ledgerVersion=1; client=$clientName; updatedAt=$nowIso; cells=$merged.cells; coverage=$covOut }
$json = ConvertTo-Json -InputObject $ledger -Depth 100 -Compress   # Depth 100: default depth 2 would truncate the cell map to its type name
Assert-NoCredential $json
if(Test-HasCredProps ($json | ConvertFrom-Json)){ throw "CREDENTIAL LEAK: credential-shaped property in ledger" }
[IO.File]::WriteAllText($ledgerPath, $json, (New-Object Text.UTF8Encoding($false)))

$finals=@($merged.cells.Keys | Where-Object { $merged.cells[$_].state -eq 'final' }).Count
$prov=@($merged.cells.Keys | Where-Object { [int]$merged.cells[$_].restatementCount -gt 0 }).Count
Write-Host ("ledger -> {0}  ({1} cells: {2} final / {3} provisional; {4} restated; maxMonth {5})" -f $ledgerPath, $merged.cells.Count, $finals, ($merged.cells.Count-$finals), $prov, $maxLabel)
if($merged.restated.Count -gt 0){ Write-Host ("  {0} final cell(s) restated (kept frozen; surfaced by Analyze-SwydoTrend)" -f $merged.restated.Count) }
