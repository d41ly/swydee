<#
.SYNOPSIS
  Compute QoQ / YoY trend comparisons from a per-client cumulative ledger (Update-SwydoLedger.ps1) and emit a
  CLOSER-SHAPED facts file, with an honesty gate and R1 restatement surfacing.
.DESCRIPTION
  Comparisons are computed by us from the ledger's monthly series -- never from Swydo's compare column:
    * QoQ / YoY on ADDITIVE metrics use QUARTER SUMS (all 3 constituent months required on BOTH sides).
    * The honesty gate emits a comparison ONLY if both endpoints are FINAL and SAME-BASIS; otherwise it emits an
      explicit dataGap ("no comparison available - <provider> history begins <month>"), never a fabricated number.
    * Providers with different coverage are NEVER blended.
    * A final cell that a later pull restated (restatementCount>0) is surfaced as GAP_RESTATEMENT_SUPPRESSED
      (severity major) so the closer FORCES it into the report (R1: surface, don't correct).
  Output matches the schema Test-ReportNumbers.ps1 consumes: meta{factsVersion, providers[], comparisonCaveats},
  platforms[{id,name,category,headline{},hasComparison,timeSeries[]}], findings{wins,losses,anomalies,discrepancies,dataGaps}
  with ruleId#ordinal fids -- so every sev>=major finding must echo <!-- finding:$fid --> and its numbers trace.
.PARAMETER DefineOnly
  Define functions and return WITHOUT running (for tests).
.EXAMPLE
  .\Analyze-SwydoTrend.ps1 -LedgerFile ..\archive\<slug>\ledger.json -OutDir .\out
#>
param(
  [string]$LedgerFile,
  [string]$OutDir = "",
  [double]$WinLossPct = 10,
  [switch]$DefineOnly
)
$ErrorActionPreference = "Stop"
$myLedgerFile=$LedgerFile; $myOutDir=$OutDir; $myWinLossPct=$WinLossPct; $myDefineOnly=[bool]$DefineOnly
. "$PSScriptRoot\Manage-SwydoArchive.ps1" -DefineOnly     # Test-HasCredProps
. "$PSScriptRoot\Analyze-SwydoReport.ps1" -DefineOnly     # Format-Metric, Get-DeltaPct, Format-Delta, Get-Direction, Test-Additive, Metric-Type, Get-Category, Get-MetricPart, Get-ProviderId, Scrub-Credential, Assert-NoCredential, $script:KeyPattern

# ---------- pure quarter arithmetic ----------
function Get-QuarterKey($monthKey){
  if([string]$monthKey -notmatch '^(\d{4})-(\d{2})$'){ return $null }
  $y=[int]$Matches[1]; $mo=[int]$Matches[2]; $q=[math]::Floor(($mo-1)/3)+1
  return ('{0:D4}-Q{1}' -f $y,$q)
}
function Get-QuarterMonths($quarterKey){
  if([string]$quarterKey -notmatch '^(\d{4})-Q([1-4])$'){ return @() }
  $y=[int]$Matches[1]; $q=[int]$Matches[2]; $start=($q-1)*3+1
  return @(0,1,2 | ForEach-Object { '{0:D4}-{1:D2}' -f $y,($start+$_) })
}
function Get-PrevQuarter($quarterKey){
  if([string]$quarterKey -notmatch '^(\d{4})-Q([1-4])$'){ return $null }
  $y=[int]$Matches[1]; $q=[int]$Matches[2]; $q--; if($q -lt 1){ $q=4; $y-- }
  return ('{0:D4}-Q{1}' -f $y,$q)
}
function Get-YearAgoQuarter($quarterKey){
  if([string]$quarterKey -notmatch '^(\d{4})-Q([1-4])$'){ return $null }
  return ('{0:D4}-Q{1}' -f ([int]$Matches[1]-1),[int]$Matches[2])
}
# ---------- pure: sum a quarter's 3 months from a series (months = hashtable mk -> cell) ----------
# Returns @{ ok=$bool; value=<num|null>; reason=<why not ok> }. ok requires all 3 months present, state=final, numeric.
function Get-QuarterSum($months,$quarterKey){
  $qm=Get-QuarterMonths $quarterKey
  if(@($qm).Count -ne 3){ return @{ ok=$false; value=$null; reason="bad quarter key $quarterKey" } }   # fail-closed, not a fabricated $0
  $sum=0.0
  foreach($mk in $qm){
    if(-not $months.ContainsKey($mk)){ return @{ ok=$false; value=$null; reason="missing $mk" } }
    $c=$months[$mk]
    if($c.state -ne 'final'){ return @{ ok=$false; value=$null; reason="$mk not final" } }
    if($null -eq $c.value){ return @{ ok=$false; value=$null; reason="$mk null" } }
    $sum += [double]$c.value
  }
  return @{ ok=$true; value=$sum; reason=$null }
}
# ---------- pure: latest quarter whose 3 months are ALL present + final in a series ----------
function Get-LatestFinalQuarter($months){
  $qs=@{}
  foreach($mk in $months.Keys){ $qk=Get-QuarterKey $mk; if($qk){ $qs[$qk]=$true } }
  $ordered=@($qs.Keys | Sort-Object -Descending)
  foreach($qk in $ordered){ if((Get-QuarterSum $months $qk).ok){ return $qk } }
  return $null
}
# ---------- pure: quarter key -> human label "Q3 2025" ----------
function Get-QuarterLabel($quarterKey){
  if([string]$quarterKey -notmatch '^(\d{4})-Q([1-4])$'){ return [string]$quarterKey }
  return ('Q{0} {1}' -f [int]$Matches[2],[int]$Matches[1])
}

if($myDefineOnly){ return }

# ================================ run ================================
if(-not $myLedgerFile){ throw "LedgerFile is required" }
if(-not $myOutDir){ $myOutDir = Split-Path -Parent $myLedgerFile }
New-Item -ItemType Directory -Force -Path $myOutDir | Out-Null

$txt=[IO.File]::ReadAllText($myLedgerFile)
Assert-NoCredential $txt
$L = $txt | ConvertFrom-Json
if($L.ledgerVersion -ne 1){ throw "unsupported ledgerVersion (need 1) - rebuild with Update-SwydoLedger.ps1" }

# assemble series: providerId -> metricId -> @{ activeBasis; unit; currency; months{ mk -> cell }; basisChanged }
$series=@{}
foreach($p in $L.cells.PSObject.Properties){
  $cell=$p.Value; $prov=[string]$cell.providerId; $mid=[string]$cell.metricId
  if(-not $series.ContainsKey($prov)){ $series[$prov]=@{} }
  if(-not $series[$prov].ContainsKey($mid)){ $series[$prov][$mid]=@{ byBasis=@{}; latestMonth=$null; latestBasis=$null } }
  $s=$series[$prov][$mid]
  if(-not $s.byBasis.ContainsKey($cell.basisVersion)){ $s.byBasis[$cell.basisVersion]=@{} }
  $s.byBasis[$cell.basisVersion][[string]$cell.month]=$cell
  if($null -eq $s.latestMonth -or [string]$cell.month -gt $s.latestMonth){ $s.latestMonth=[string]$cell.month; $s.latestBasis=$cell.basisVersion }
}

$platforms=@{}
$wins=[Collections.ArrayList]@(); $losses=[Collections.ArrayList]@(); $anoms=[Collections.ArrayList]@(); $disc=[Collections.ArrayList]@(); $gaps=[Collections.ArrayList]@()

# coverage lookup for gate messaging
$covByProv=@{}; if($L.coverage){ foreach($c in $L.coverage.PSObject.Properties){ $covByProv[$c.Name]=$c.Value } }   # no @() wrapper: it would make a [null] element from an absent coverage key

foreach($prov in ($series.Keys | Sort-Object)){
  $cv=$covByProv[$prov]
  $pname=if($cv -and $cv.providerName){ $cv.providerName } else { $prov }
  $platforms[$prov]=[ordered]@{ id=$prov; name=$pname; category=(Get-Category $prov); headline=[ordered]@{}; hasComparison=$false; timeSeries=[Collections.ArrayList]@() }
  foreach($mid in ($series[$prov].Keys | Sort-Object)){
    $s=$series[$prov][$mid]
    $months=$s.byBasis[$s.latestBasis]        # active-basis series only (older-basis months are a separate series)
    if($s.byBasis.Keys.Count -gt 1){ [void]$gaps.Add([ordered]@{ ruleId='GAP_BASIS_CHANGED'; severity='major'; platform=$pname; metric=$mid; statement="$pname '$mid' changed unit/currency basis; trend uses the current basis only (older data kept as a separate series)" }) }
    $unit=$null; $cur=$null; foreach($mk in $months.Keys){ $unit=$months[$mk].unit; $cur=$months[$mk].currency; break }
    $mname=Get-MetricPart $mid
    # monthly series (traceable display) - sorted
    $sorted=@($months.Keys | Sort-Object)
    $seq=@(); foreach($mk in $sorted){ $c=$months[$mk]; $seq+=[ordered]@{ label=$mk; display=(Format-Metric $mid $unit $c.value $cur); state=$c.state } }
    [void]$platforms[$prov].timeSeries.Add([ordered]@{ metricId=$mid; dimension='month'; pacing=[ordered]@{ metric=$mname; series=$seq } })
    # R1: surface any restated final cells for this metric
    foreach($mk in $sorted){ $c=$months[$mk]; if([int]$c.restatementCount -gt 0){
      $ld=if($c.PSObject.Properties.Name -contains 'latestDisplay'){ $c.latestDisplay } else { '(unknown)' }
      [void]$anoms.Add([ordered]@{ ruleId='GAP_RESTATEMENT_SUPPRESSED'; severity='major'; platform=$pname; metric=$mid
        statement="$pname '$mname' $mk was restated after freezing: ledger holds $($c.display), latest pull reported $ld (kept frozen; K-month horizon exceeded)"
        evidence=[ordered]@{ frozen=$c.display; latest=$ld; month=$mk } })
    } }
    # QoQ / YoY on ADDITIVE metrics only (sums are meaningless for rates/ratios)
    if(-not (Test-Additive $mid)){ continue }
    $curQ=Get-LatestFinalQuarter $months
    if(-not $curQ){ if($cv){ [void]$gaps.Add([ordered]@{ ruleId='GAP_NO_FINAL_QUARTER'; severity='major'; platform=$pname; metric=$mid; statement="$pname '$mname': no fully-settled quarter yet (history begins $($cv.earliestMonth))" }) }; continue }
    $dir=Get-Direction $mid
    $curSum=Get-QuarterSum $months $curQ
    foreach($cmp in @(@{ kind='QoQ'; q=(Get-PrevQuarter $curQ) }, @{ kind='YoY'; q=(Get-YearAgoQuarter $curQ) })){
      $prevSum=Get-QuarterSum $months $cmp.q
      if(-not $prevSum.ok){
        [void]$gaps.Add([ordered]@{ ruleId=('GAP_NO_'+$cmp.kind); severity='major'; platform=$pname; metric=$mid; statement="$pname '$mname' $($cmp.kind): no comparison available - needs a fully-settled $($cmp.q) (history begins $(if($cv){$cv.earliestMonth}else{'?'}))" })
        continue
      }
      $platforms[$prov].hasComparison=$true
      $dCur=Format-Metric $mid $unit $curSum.value $cur
      $dPrev=Format-Metric $mid $unit $prevSum.value $cur
      $delta=Get-DeltaPct $curSum.value $prevSum.value
      $dDelta=Format-Delta $delta
      $hk="$mid|$($cmp.kind)"
      $platforms[$prov].headline[$hk]=[ordered]@{ metric=$mname; id=$mid; unit=$unit; type=(Metric-Type $mid $unit $cur); direction=$dir; currency=$cur
        current=$curSum.value; previous=$prevSum.value; deltaPct=$delta; hasComparison=$true
        displayCurrent=$dCur; displayPrevious=$dPrev; displayDelta=$dDelta; label="$($cmp.kind) $(Get-QuarterLabel $curQ) vs $(Get-QuarterLabel $cmp.q)" }
      if($null -ne $delta -and $dir -ne 'neutral' -and [math]::Abs($delta) -ge $myWinLossPct){
        $favorable=(($dir -eq 'higher-better' -and $delta -gt 0) -or ($dir -eq 'lower-better' -and $delta -lt 0))
        $rid=if($favorable){"WIN_$($cmp.kind)"}else{"LOSS_$($cmp.kind)"}
        $f=[ordered]@{ ruleId=$rid; platform=$pname; metric=$mname; direction=$dir
          statement="$pname $mname $($cmp.kind) ($(Get-QuarterLabel $curQ) vs $(Get-QuarterLabel $cmp.q)): $dCur vs $dPrev ($dDelta)"
          evidence=[ordered]@{ current=$dCur; previous=$dPrev; delta=$dDelta } }
        if($favorable){ [void]$wins.Add($f) } else { [void]$losses.Add($f) }
      }
    }
  }
  # freeze the ArrayList timeSeries into a plain array for clean JSON
  $platforms[$prov].timeSeries=@($platforms[$prov].timeSeries)
}

# stable ruleId#ordinal fids (same scheme as Analyze so the closer surfaces sev>=major findings)
$fidCounts=@{}
foreach($arr in @($wins,$losses,$anoms,$disc,$gaps)){ foreach($fnd in $arr){ $rid=if($fnd.ruleId){$fnd.ruleId}else{'F'}; if(-not $fidCounts.ContainsKey($rid)){ $fidCounts[$rid]=0 }; $fidCounts[$rid]++; $fnd.fid="$rid#$($fidCounts[$rid])" } }

$hasCmp=[bool](@($platforms.Values | Where-Object { $_.hasComparison }).Count)
$caveats=@()
if($hasCmp){ $caveats += [ordered]@{ id='seasonality'; text="Quarter-over-quarter comparisons can reflect seasonality (e.g. Q1 tax season, Q4 holidays), not just performance - validate against the same quarter a year earlier (the YoY figures) before attributing changes to the campaigns." } }

$factsDoc=[ordered]@{
  meta=[ordered]@{
    tool='Analyze-SwydoTrend.ps1'; factsVersion=1; computedFrom=$L.client; reportName=$L.client; client=$L.client
    horizonMonths=$null; ledgerUpdatedAt=$L.updatedAt; hasComparison=$hasCmp; comparisonCaveats=$caveats
    providers=@($platforms.Values | ForEach-Object { [ordered]@{ id=$_.id; name=$_.name; category=$_.category } })
    coverage=@($covByProv.Values)
  }
  platforms=@($platforms.Values)
  findings=[ordered]@{ wins=@($wins); losses=@($losses); anomalies=@($anoms); discrepancies=@($disc); dataGaps=@($gaps) }
}
$json = ConvertTo-Json -InputObject $factsDoc -Depth 40 -Compress
Assert-NoCredential $json
if(Test-HasCredProps ($json | ConvertFrom-Json)){ throw "CREDENTIAL LEAK: credential-shaped property in trend facts" }
$stamp=(Get-Date).ToString('yyyy-MM-dd-HH-mm-ss')
$slug=([string]$L.client -replace '[^A-Za-z0-9]+','-').Trim('-').ToLower(); if(-not $slug){ $slug='client' }
$path=Join-Path $myOutDir "$stamp-$slug.trendanalysis.facts.json"
[IO.File]::WriteAllText($path,$json,(New-Object Text.UTF8Encoding($false)))
Write-Host ("trend analysis -> {0}  (platforms {1}, wins {2}, losses {3}, restated {4}, gaps {5})" -f $path,$platforms.Count,$wins.Count,$losses.Count,@($anoms|Where-Object{$_.ruleId -eq 'GAP_RESTATEMENT_SUPPRESSED'}).Count,$gaps.Count)
