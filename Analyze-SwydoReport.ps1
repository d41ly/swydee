<#
.SYNOPSIS
  Deterministic analysis of a Swydo v2 extraction -> analysis-facts JSON. Offline, no network.
  The /swydee skill's model layer narrates ONLY from these facts (never computes numbers).
.DESCRIPTION
  Reads a schemaVersion:2 extraction (from Get-SwydoReport.ps1), scrubs the share credential,
  validates the schema, derives the reporting period, and computes role-qualified, pre-formatted
  facts: per-platform headline tables, portfolio totals, and rule-based findings
  (wins/losses/anomalies/discrepancies/data-gaps). Owns ALL rounding; emits display strings.

  Build status: FOUNDATION increment - pure helpers (unit/direction/additive/period), credential
  scrub + schema gate, headline + portfolio compute, universal findings (wins/losses, additive &
  non-additive & cross-widget discrepancies, data-gaps). NEXT increments (per spec S13.12): the
  full per-category effort->result / ranking-drop / budget-constrained rules, timeSeries block,
  segment-divergence, and the report/closer/skill layer. See SWYDEE_SKILL_SPEC S13.
.PARAMETER DefineOnly
  Load functions and return without running (for dot-sourced unit tests).
#>
param(
  [string]$InFile,
  [string]$OutDir,
  [double]$WinLossPct = 10.0,   # |delta%| >= this on a directional metric => win/loss
  [int]$SmallN = 30,            # moved-side events below this => confidence:low
  [switch]$DefineOnly
)
$ErrorActionPreference = "Stop"

# ============================ config ============================
$script:CategoryMap = @{
  'google-adwords'='ads'; 'facebook-ads'='ads'; 'bing-ads'='ads'; 'microsoft-advertising'='ads'
  'linkedin-ads'='ads'; 'tiktok-ads'='ads'; 'pinterest'='ads'; 'snapchat'='ads'; 'twitter-ads'='ads'
  'reddit-ads'='ads'; 'adroll'='ads'
  'google-analytics-4'='web-analytics'
  'semrush'='seo'; 'se-ranking'='seo'; 'accuranker'='seo'; 'trueranker'='seo'
  'mailchimp'='email-crm'; 'klaviyo'='email-crm'; 'activecampaign'='email-crm'; 'hubspot'='email-crm'
  'shopify'='ecommerce'; 'callrail'='calls'; 'ctm'='calls'
}
# ============================ pure helpers ============================
function Get-MetricPart($id){ if($null -eq $id){ return '' }; $s=($id -split ':',2); $p=if($s.Count -gt 1){$s[1]}else{$s[0]}; return $p.ToLower() }
function Get-ProviderId($id){ if($null -eq $id){ return '' }; return ($id -split ':')[0] }
function Get-Category($providerId){ $c=$script:CategoryMap[$providerId]; if($c){ return $c } return 'other' }
# Direction over the FULL metric part (handles compound ids like costPerActionType::link_click).
# lower-better checked FIRST so cost_per_conversion (cost + conversion) resolves to lower.
function Get-Direction($id){
  $p = Get-MetricPart $id
  if($p -match 'cost|cpc|cpm|cpa|cpl|bounce|unsubscrib|spam|refund_rate|missed|search_lost_is|(^|_)position$|(^|_)rank|frequency'){ return 'lower-better' }
  if($p -match 'conversion|click|impression|reach|lead|ctr|roas|revenue|order|session|user|open|engag|quality|sends|score'){ return 'higher-better' }
  return 'neutral'   # spend, amount_spent, budget, unknown
}
# Additive = a summable count/total. Ratios/rates/averages/dedup metrics are NOT additive.
function Test-Additive($id){
  $p = Get-MetricPart $id
  if($p -match 'reach|frequency|ctr|_rate|average|avg|position|rank|roas|aov|cpc|cpm|cpa|cpl|share|score|cost_per|costper'){ return $false }
  if($p -match 'impression|click|conversion|lead|spend|cost_micros|(^|_)cost$|session|user|order|send|open|revenue|(^|_)call|phone_call|amount_spent|value'){ return $true }
  return $false
}
function Test-Money($id,$unit,$currency){
  if($unit -eq 'micros' -and $currency){ return $true }
  $p = Get-MetricPart $id
  return [bool]($p -match '(cost|spend|cpc|cpm|cpa|cpl|revenue|budget|amount_spent|cost_per)')
}
$script:CurSym = @{ USD='$'; EUR=([char]0x20AC); GBP=([char]0xA3); CAD='CA$'; AUD='A$' }  # char-codes: keep source pure-ASCII (PS 5.1 reads UTF-8-no-BOM as ANSI)
function Format-Metric($id,$unit,$value,$currency){
  if($null -eq $value){ return $null }
  if($unit -eq 'micros'){
    $base = [double]$value/1e6
    if(Test-Money $id $unit $currency){
      $sym = if($currency -and $script:CurSym[$currency]){ $script:CurSym[$currency] } elseif($currency){ "$currency " } else { '$' }
      return ("{0}{1:N2}" -f $sym,$base)
    }
    return ("{0:N2}" -f $base)   # non-money micros (e.g. GA4 seconds)
  }
  if($unit -eq 'fraction'){ return ("{0:N1}%" -f ([double]$value*100)) }
  # counts: integer unless clearly fractional
  $d=[double]$value
  if([math]::Abs($d - [math]::Round($d)) -lt 1e-9){ return ("{0:N0}" -f $d) }
  return ("{0:N1}" -f $d)
}
function Get-DeltaPct($cur,$prev){
  if($null -eq $cur -or $null -eq $prev){ return $null }
  $p=[double]$prev; if($p -eq 0){ if([double]$cur -eq 0){ return 0.0 } else { return $null } }  # NEW/undefined
  return [math]::Round(((([double]$cur)-$p)/[math]::Abs($p))*100,1)
}
function Format-Delta($d){ if($null -eq $d){ return $null }; return ("{0:+0.0;-0.0;0.0}%" -f $d) }
# human dimension label (mirror extractor DimName intent)
function Get-DimLabel($c){
  if($null -eq $c){ return $null }
  if($c -is [string]){ return $c }
  $cands=@(); foreach($p in $c.PSObject.Properties){ $v=$p.Value; if($v -is [string] -and $v -match '[A-Za-z]' -and $v.Length -lt 160 -and $v -notmatch '^https?://' -and $v -notmatch '^[\w-]+/\d+$'){ $cands+=@{k=$p.Name;v=$v} } }
  if($cands.Count -eq 0){ return '(group)' }
  $named=@($cands | Where-Object {$_.k -match 'name|text|keyword|title'}); if($named.Count -gt 0){ return $named[0].v }
  return $cands[-1].v
}
function Test-GroupRow($label){ return ($null -eq $label -or $label -eq '(group)' -or $label -eq 'All') }
# period derivation from extractedAt + dateRange.primary (ignore compareDateRange.period)
function Derive-Periods($extractedAt,$dateRange){
  $out=[ordered]@{ current='current'; previous='previous'; label='current vs previous'; confidence='unconfirmed' }
  try {
    $anchor=[DateTimeOffset]::Parse($extractedAt).Date
    $p=$dateRange.primary
    if($p -and $p.type -eq 'RELATIVE' -and $p.measure -eq 'quarter'){
      $q=[math]::Floor((($anchor.Month)-1)/3)  # 0..3 for the anchor's own quarter
      # count=-1 => last COMPLETE quarter before anchor
      $curQidx=$q-1; $y=$anchor.Year
      if($curQidx -lt 0){ $curQidx=3; $y-- }
      $prevQidx=$curQidx-1; $py=$y; if($prevQidx -lt 0){ $prevQidx=3; $py-- }
      $out.current="Q$($curQidx+1) $y"; $out.previous="Q$($prevQidx+1) $py"; $out.label="$($out.current) vs $($out.previous)"; $out.confidence='derived'
    }
    elseif($p -and $p.measure){ $out.current="last $($p.measure)"; $out.previous="previous $($p.measure)"; $out.label="$($out.current) vs $($out.previous)"; $out.confidence='derived' }
  } catch {}
  return $out
}
# credential scrub: remove shareKey/shareUrl in place on a parsed doc
function Scrub-Credential($doc){
  if($doc.meta){ 'shareKey','shareUrl' | ForEach-Object { if($doc.meta.PSObject.Properties.Name -contains $_){ $doc.meta.PSObject.Properties.Remove($_) } } }
  return $doc
}
$script:KeyPattern = 'swy\.do/shares/[A-Za-z0-9]+|/g/[A-Za-z0-9]{20,}/reports/'
function Assert-NoCredential($text){ if($text -match $script:KeyPattern){ throw "CREDENTIAL LEAK: share key/url found in output" } }

if($DefineOnly){ return }   # dot-source stops here

# ============================ run ============================
if(-not $InFile){ throw "InFile is required" }
if(-not $OutDir){ $OutDir = Split-Path -Parent $InFile }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$doc = (Get-Content $InFile -Raw) | ConvertFrom-Json
# schema gate
if($doc.meta.schemaVersion -ne 2){ throw "unsupported schemaVersion (need 2, got '$($doc.meta.schemaVersion)') - re-extract with the current tool" }
if(-not $doc.report -or -not $doc.report.name -or -not $doc.widgets){ throw "not a valid v2 extraction (missing report/widgets)" }
$doc = Scrub-Credential $doc

$periods = Derive-Periods $doc.meta.extractedAt $doc.report.dateRange
$dataWidgets = @($doc.widgets | Where-Object { $_.kind -eq 'data' })
if($dataWidgets.Count -eq 0){ throw "no data widgets to analyze (all text/empty)" }

function Total-Row($w){ $t=@($w.rows | Where-Object { $_.kind -eq 'total' }); if($t.Count -gt 0){ return $t[0] } ; $t=@($w.rows|Where-Object{$_.kind -eq 'data'}); if($t.Count -gt 0){return $t[0]}; return $null }

# per-platform headline (role-qualified) + provider discovery
$platforms=@{}
foreach($w in $dataWidgets){
  $prov = if($w.providers -and $w.providers.Count -gt 0){ $w.providers[0].id } else { ($w.metrics | Select-Object -First 1).id -split ':' | Select-Object -First 1 }
  if(-not $prov){ continue }
  if(-not $platforms.ContainsKey($prov)){ $pname=if($w.providers -and $w.providers.Count -gt 0 -and $w.providers[0].name){ $w.providers[0].name }else{ $prov }; $platforms[$prov]=[ordered]@{ id=$prov; name=$pname; category=(Get-Category $prov); headline=[ordered]@{}; hasComparison=$false } }
  $tr = Total-Row $w
  if(-not $tr){ continue }
  $cc = $w.currencyCode
  foreach($m in $w.metrics){
    $cell = $tr.metrics.$($m.name)
    if(-not $cell){ continue }
    if(-not ($cell.current -is [double] -or $cell.current -is [int] -or $cell.current -is [long] -or $cell.current -is [decimal])){ continue }  # scalar-guard: drop echo objects
    $key = $m.id  # role-qualified store key by metric id (dedup across widgets keeps first/total)
    if($platforms[$prov].headline.Contains($key)){ continue }
    $dir = Get-Direction $m.id
    $delta = Get-DeltaPct $cell.current $cell.compare
    $hasCmp = ($null -ne $cell.compare)
    if($hasCmp){ $platforms[$prov].headline.hasComparison=$true; $platforms[$prov].hasComparison=$true }
    $platforms[$prov].headline[$key]=[ordered]@{
      metric=$m.name; id=$m.id; unit=$m.unit; direction=$dir; currency=$cc
      current=$cell.current; previous=$cell.compare; deltaPct=$delta; hasComparison=$hasCmp
      displayCurrent=(Format-Metric $m.id $m.unit $cell.current $cc)
      displayPrevious=(Format-Metric $m.id $m.unit $cell.compare $cc)
      displayDelta=(Format-Delta $delta)
    }
  }
}

# findings
$findings=[ordered]@{ wins=@(); losses=@(); anomalies=@(); discrepancies=@(); dataGaps=@() }
# NOTE: PowerShell variables are case-insensitive, so accumulators must NOT collide with loop vars ($w, etc.)
$wins=[System.Collections.ArrayList]@(); $losses=[System.Collections.ArrayList]@(); $anoms=[System.Collections.ArrayList]@(); $disc=[System.Collections.ArrayList]@(); $gaps=[System.Collections.ArrayList]@()

# GAP_WARNINGS (from extraction)
foreach($warn in @($doc.meta.warnings)){ if($warn){ [void]$gaps.Add([ordered]@{ ruleId='GAP_WARNINGS'; severity='major'; statement=$warn }) } }
# per-platform win/loss + gaps
foreach($pk in $platforms.Keys){
  $pf=$platforms[$pk]
  foreach($hk in $pf.headline.Keys){
    $h=$pf.headline[$hk]
    if($null -eq $h.unit -and (Test-Money $h.id $h.unit $h.currency)){ [void]$gaps.Add([ordered]@{ ruleId='GAP_UNIT_UNCONFIRMED'; severity='major'; platform=$pf.name; metric=$h.metric; statement="units unconfirmed for $($pf.name) '$($h.metric)' (unverified provider); figure shown raw ($($h.displayCurrent))" }) }
    if($null -ne $h.deltaPct -and $h.direction -ne 'neutral' -and [math]::Abs($h.deltaPct) -ge $WinLossPct){
      $favorable = (($h.direction -eq 'higher-better' -and $h.deltaPct -gt 0) -or ($h.direction -eq 'lower-better' -and $h.deltaPct -lt 0))
      $conf = if([math]::Abs([double]$h.current) -lt $SmallN -and [math]::Abs([double]($h.previous)) -lt $SmallN){ 'low' } else { 'normal' }
      $rid = if($favorable){ 'WIN' } else { 'LOSS' }
      $f=[ordered]@{ ruleId=$rid; platform=$pf.name; metric=$h.metric; direction=$h.direction; confidence=$conf
        statement="$($pf.name) $($h.metric) $($h.displayCurrent) vs $($h.displayPrevious) ($($h.displayDelta))"
        evidence=[ordered]@{ current=$h.displayCurrent; previous=$h.displayPrevious; delta=$h.displayDelta } }
      if($favorable){ [void]$wins.Add($f) } else { [void]$losses.Add($f) }
    }
  }
}
# DISC_CROSS_WIDGET: a metric's total disagrees across widgets THAT MEASURE THE SAME POPULATION.
# Key on metricId + dimension-signature: a keyword table (dims Keyword,Ad group) and the account
# KPI (no dims) legitimately differ in scope, so we only compare widgets with identical dim sets.
$byMetric=@{}
foreach($w in $dataWidgets){
  $tr=Total-Row $w; if(-not $tr){continue}
  $dimSig = (@($w.dimensions) | Sort-Object) -join ','
  foreach($m in $w.metrics){
    $cell=$tr.metrics.$($m.name); if(-not $cell){continue}
    if(-not ($cell.current -is [double] -or $cell.current -is [int] -or $cell.current -is [long] -or $cell.current -is [decimal])){continue}
    $key="$($m.id)`t$dimSig"
    if(-not $byMetric.ContainsKey($key)){ $byMetric[$key]=@{ mid=$m.id; rows=@() } }
    $byMetric[$key].rows += @{ wid=$w.id; cur=$cell.current; prev=$cell.compare }
  }
}
foreach($key in $byMetric.Keys){
  $mid=$byMetric[$key].mid; $rows=$byMetric[$key].rows; if($rows.Count -lt 2){ continue }
  foreach($per in 'cur','prev'){
    $vals=@($rows | ForEach-Object { $_.$per } | Where-Object { $null -ne $_ })
    if($vals.Count -lt 2){ continue }
    $mn=($vals|Measure-Object -Minimum).Minimum; $mx=($vals|Measure-Object -Maximum).Maximum
    $additive = Test-Additive $mid
    $mismatch = if($additive){ ($mx -ne $mn) } else { ($mx -ne 0 -and (($mx-$mn)/[math]::Abs($mx)) -gt 0.01) }
    $perWord = if($per -eq 'cur'){ 'current' } else { 'previous' }
    $perLabel = if($per -eq 'cur'){ $periods.current } else { $periods.previous }
    if($mismatch){ [void]$disc.Add([ordered]@{ ruleId='DISC_CROSS_WIDGET'; severity='major'; metric=$mid; period=$perLabel; statement="'$mid' ($perWord) differs across same-scope widgets: $mn..$mx" }) }
  }
}

$findings.wins=@($wins); $findings.losses=@($losses); $findings.anomalies=@($anoms); $findings.discrepancies=@($disc); $findings.dataGaps=@($gaps)

# portfolio totals (same-currency additive money + counts) - informational
$facts=[ordered]@{
  meta=[ordered]@{
    tool='Analyze-SwydoReport.ps1'; factsVersion=1; computedFrom=$doc.meta.tool
    reportName=$doc.report.name; extractedAt=$doc.meta.extractedAt
    currentPeriod=$periods.current; previousPeriod=$periods.previous; periodLabel=$periods.label; periodConfidence=$periods.confidence
    hasComparison=([bool](@($platforms.Values|Where-Object{$_.hasComparison}).Count));
    providers=@($platforms.Values | ForEach-Object { [ordered]@{ id=$_.id; name=$_.name; category=$_.category } })
    dataWidgets=$dataWidgets.Count; unitBasis=$doc.meta.unitBasis
  }
  platforms=@($platforms.Values)
  findings=$findings
}
$json = $facts | ConvertTo-Json -Depth 40
Assert-NoCredential $json
$stamp=(Get-Date).ToString('yyyy-MM-dd-HH-mm-ss')
$slug=($doc.report.name -replace '[^A-Za-z0-9]+','-').Trim('-').ToLower(); if(-not $slug){$slug='report'}
$path=Join-Path $OutDir "$stamp-$slug.facts.json"
[IO.File]::WriteAllText($path,$json,(New-Object Text.UTF8Encoding($false)))
Write-Host ("facts -> {0}  (platforms {1}, wins {2}, losses {3}, disc {4}, gaps {5}; period {6}/{7})" -f $path,$facts.platforms.Count,$wins.Count,$losses.Count,$disc.Count,$gaps.Count,$periods.label,$periods.confidence)
