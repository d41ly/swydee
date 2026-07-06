<#
.SYNOPSIS
  Extract every data piece from a Swydo shared report (swy.do/shares/<KEY>) into ONE
  timestamped, self-describing JSON file. No browser required.
.DESCRIPTION
  Resolves the share link -> mints a JWT -> opens a websocket for a socketId ->
  queries report structure -> pulls every widget's fields + data (paginated, with
  cache-warm retry + reconciliation) -> normalizes everything into a single document
  and writes it as  <OutDir>\YYYY-MM-DD-HH-MM-SS-<report-slug>.json.
  Handles password-protected shares. Windows PowerShell 5.1+ / .NET only.

  OUTPUT SCHEMA (schemaVersion 2):
    {
      "meta":   { tool, schemaVersion:2, extractedAt, shareUrl, shareKey, reportId,
                  widgetCount, dataWidgets, unitBasis:[providers units were inferred for], warnings[] },
      "report": { name, subtitle, orientation, client, author{name,email}, team,
                  dateRange, compareDateRange, sections[{id,name}], custom },
      "widgets":[ {
          id, visual, kind ("data"|"text"|"pageBreak"|"manualKpi"|"unknown"),
          section, title, provider, providers[{id,name}],
          // kind=="text":      text
          // manualKpiOptions present (any kind): manualKpi{value,compareValue}
          // kind=="data":      comparisonFormat, currencyCode, target{value}(if a goal is set),
          //                    dimensions[names], metrics[{name,id,unit?}],
          //                    rows[{ kind, dimensions{name->label}, metrics{name->{current,compare}} }]
          raw   // ALWAYS: the untouched GraphQL widget node (lossless for everything queried)
      } ]
    }
  UNITS: values are RAW. metric.unit is a SCALE hint, present only for providers whose
  convention is verified (google-adwords, facebook-ads): "micros" => divide by 1e6 to reach
  the base unit (currency OR e.g. seconds -- use currencyCode to know if it is money);
  "fraction" => multiply by 100 for a percentage. unit ABSENT => render raw (never convert).
.PARAMETER DefineOnly
  Define functions and return WITHOUT running (for dot-sourcing in tests).
.EXAMPLE
  .\Get-SwydoReport.ps1 -ShareUrl https://swy.do/shares/<KEY> -OutDir .\extractions -Secret 123
#>
param(
  [string]$ShareUrl,
  [string]$OutDir = ".\extractions",
  [string]$Secret = "",
  [int]$PageSize = 500,
  [switch]$Trend,            # opt-in: pull a wide per-provider monthly history (cumulative-trend feature)
  [string]$CacheDir = "",    # ceiling-probe cache location; default %LOCALAPPDATA%\swydee\ceilings (NOT OutDir)
  [switch]$DefineOnly
)
$ErrorActionPreference = "Stop"

# ============================ function definitions ============================
$script:ct  = [Threading.CancellationToken]::None
$script:buf = [byte[]]::new(1048576)

# --- auth / GraphQL (reference $key/$Secret/$script:jwt at call time) ---
function Mint-Jwt {
  $basic = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("$script:key`:$Secret"))
  $j = (Invoke-RestMethod "https://vesting.swydo.com/jwt/share" -Headers @{authorization="Basic $basic"}).jwt
  if (-not $j) { throw "JWT mint failed (bad key or secret?)" }
  return $j
}
function Invoke-GQL($q,$vars){
  if ((((Get-Date) - $script:jwtAt).TotalSeconds) -gt 500) { $script:jwt = Mint-Jwt; $script:jwtAt = Get-Date }
  for($try=0; $try -lt 2; $try++){
    try {
      $body = @{query=$q; variables=$vars} | ConvertTo-Json -Compress -Depth 40
      return (Invoke-WebRequest "https://graphql.swydo.com" -Method Post -UseBasicParsing `
              -Headers @{authorization="Bearer $script:jwt"; "content-type"="application/json"} -Body $body).Content
    } catch {
      $resp = $_.Exception.Response
      if ($resp -and [int]$resp.StatusCode -eq 401) { $script:jwt = Mint-Jwt; $script:jwtAt = Get-Date; continue }
      if ($resp) { return (New-Object IO.StreamReader($resp.GetResponseStream())).ReadToEnd() }
      throw
    }
  }
}

# --- websocket (live socketId for cache-miss pushes) ---
function Ws-Send($o){ try{ $b=[Text.Encoding]::UTF8.GetBytes(($o|ConvertTo-Json -Compress -Depth 10)); $script:ws.SendAsync([ArraySegment[byte]]::new($b),'Text',$true,$script:ct).Wait() }catch{} }
function Ws-Recv($ms){ try{ $s=[ArraySegment[byte]]::new($script:buf); $t=$script:ws.ReceiveAsync($s,$script:ct); if($t.Wait($ms)){ return [Text.Encoding]::UTF8.GetString($script:buf,0,$t.Result.Count) } }catch{}; return $null }
function Connect-Ws {
  $script:ws=[System.Net.WebSockets.ClientWebSocket]::new()
  $script:ws.Options.KeepAliveInterval=[TimeSpan]::FromSeconds(15)
  $script:ws.ConnectAsync([Uri]"wss://ws.swydo.com",$script:ct).Wait()
  Ws-Send @{kind=1; payload=@{}}
  $script:socketId=$null
  for($i=0;$i -lt 8 -and -not $script:socketId;$i++){ $m=Ws-Recv 5000; if($m){ try{$o=$m|ConvertFrom-Json; if($o.kind -eq 2){$script:socketId=$o.payload.socketId}}catch{} } }
}
function Ws-Pulse {
  if($script:ws.State -ne 'Open'){ try{ Connect-Ws }catch{} ; return }
  Ws-Send @{kind=5; payload=@{socketId=$script:socketId}}
  $m=Ws-Recv 1000
  if($m){ try{$o=$m|ConvertFrom-Json; if($o.kind -eq 4){ Ws-Send @{kind=5;payload=@{socketId=$script:socketId}} }}catch{} }
}

# --- pure helpers ---
function DimName($c){
  if($null -eq $c){ return $null }
  if($c -is [string]){ return $c }
  $cands=@()
  foreach($p in $c.PSObject.Properties){ $v=$p.Value; if($v -is [string] -and $v -match '[A-Za-z]' -and $v.Length -lt 160 -and $v -notmatch '^https?://' -and $v -notmatch '^[\w-]+/\d+$'){ $cands+=@{k=$p.Name;v=$v} } }
  if($cands.Count -eq 0){ return "(group)" }
  $named=@($cands | Where-Object {$_.k -match 'name|text|keyword|title'}); if($named.Count -gt 0){ return $named[0].v }
  return $cands[-1].v
}
# Unit is a SCALE hint. micros = /1e6 to base unit (money OR e.g. seconds); fraction = *100.
# Only inferred for verified providers; _micros$ is a universal scale marker. Never guesses for others.
function Unit-Of($id){
  if($null -eq $id){ return $null }
  if($id -match '(_|:)micros$'){ return 'micros' }
  $prov = ($id -split ':')[0]
  if($prov -eq 'google-adwords' -or $prov -eq 'facebook-ads'){
    if($id -match 'cost_micros|average_cpc|average_cpm|cost_per_conversion|costPerActionType|(^|:)cost_per|(:)(spend|cpc|cpm)$'){ return 'micros' }
    if($id -match '(:|_)ctr$|ctrLink|_rate$|impression_share|lost_is'){ return 'fraction' }
  }
  return $null
}
# collision-proof, null-safe key for an OrderedDictionary map
function Uniq-Key($map,$name,$id,$idx){
  $base = if([string]::IsNullOrEmpty($name)){ if([string]::IsNullOrEmpty($id)){ "col$idx" } else { [string]$id } } else { [string]$name }
  if(-not $map.Contains($base)){ return $base }
  $k = "$base [$id]"
  if(-not $map.Contains($k)){ return $k }
  return "$base [$id #$idx]"
}
function Flatten-Text($node){
  if($null -eq $node){ return "" }
  if($node.type -eq 'text'){ return [string]$node.text }
  $inner=""; if($node.content){ foreach($c in $node.content){ $inner += (Flatten-Text $c) } }
  switch($node.type){
    'heading'   { return "`n$inner`n" }
    'paragraph' { return "$inner`n" }
    'listItem'  { return "- $inner" }
    default     { return $inner }
  }
}

# --- data fetch: cache-warm retry on page 1, then paginate ---
$script:baseQ='query($sid:ID!,$dr:DateRange!,$cp:ComparePeriod!,$after:String){widget(id:"__ID__"){id content comparisonFormat visual{id} displayOptions{title} widgetTemplate{id linked} target{value} manualKpiOptions{value compareValue} source{id name parts{id provider{id name} dataSource{id}}} metrics:fields(socketId:$sid,type:METRIC){edges{node{id name}}} dims:fields(socketId:$sid,type:DIMENSION){edges{node{id name}}} data(first:__N__,after:$after,socketId:$sid,referenceDateRange:$dr,referenceCompareDate:$cp){edges{node}pageInfo{hasNextPage endCursor}}}}'
function Fetch-Widget($w, $attempts, $dr, $cp){
  if($null -eq $dr){ $dr = $script:dr }   # default = report range (default extraction path unchanged)
  if($null -eq $cp){ $cp = $script:cp }
  $q = $script:baseQ -replace '__ID__',$w.id -replace '__N__',"$PageSize"
  $needData = $w.visual -notin @('TEXT','PAGE_BREAK')
  $obj=$null
  for($a=1;$a -le $attempts;$a++){
    if($script:ws.State -ne 'Open'){ try{ Connect-Ws }catch{} }
    $obj = (Invoke-GQL $q @{sid=$script:socketId;dr=$dr;cp=$cp;after=$null}) | ConvertFrom-Json
    if(-not $needData -or ($obj.data.widget.data.edges.Count -gt 0)){ break }
    Ws-Pulse; Start-Sleep -Milliseconds 900
  }
  if($needData -and $obj.data.widget -and $obj.data.widget.data.edges.Count -gt 0){
    $wd=$obj.data.widget.data
    $all=[System.Collections.ArrayList]@(); $wd.edges | ForEach-Object {[void]$all.Add($_)}
    $pi=$wd.pageInfo
    while($pi.hasNextPage){
      $pg=((Invoke-GQL $q @{sid=$script:socketId;dr=$dr;cp=$cp;after=$pi.endCursor}) | ConvertFrom-Json).data.widget.data
      if(-not $pg -or $pg.edges.Count -eq 0){ break }
      $pg.edges | ForEach-Object {[void]$all.Add($_)}; $pi=$pg.pageInfo
    }
    $obj.data.widget.data.edges=$all.ToArray(); $obj.data.widget.data.pageInfo=$pi
  }
  return $obj
}
function New-RelDateRange($count,$measure){
  return [pscustomobject]@{ parent=$null; primary=[pscustomobject]@{ count=$count; measure=$measure; type='RELATIVE' }; comparison=$null; baseDate=$null; timeZone=$null }
}

# --- normalize one widget into schema v2 ---
function Normalize-Widget($wmeta,$obj){
  $w = $obj.data.widget
  $kind = if($wmeta.visual -eq 'TEXT'){'text'}
          elseif($wmeta.visual -eq 'PAGE_BREAK'){'pageBreak'}
          elseif($w.source){'data'}
          elseif($w.manualKpiOptions){'manualKpi'}
          else{'unknown'}
  $providers=@(); if($w.source -and $w.source.parts){ $providers=@($w.source.parts | ForEach-Object { [ordered]@{ id=$_.provider.id; name=$_.provider.name } }) }
  $out = [ordered]@{
    id=$wmeta.id; visual=$wmeta.visual; kind=$kind
    section=$script:secMap[$wmeta.section]; title=$w.displayOptions.title
    provider=$(if($providers.Count -gt 0){$providers[0].name}else{$null}); providers=$providers
  }
  if($w.manualKpiOptions){ $out.manualKpi=[ordered]@{ value=$w.manualKpiOptions.value; compareValue=$w.manualKpiOptions.compareValue } }
  if($kind -eq 'text'){ $out.text=(Flatten-Text $w.content).Trim() }
  elseif($kind -eq 'data'){
    $out.comparisonFormat=$w.comparisonFormat
    $cc=$null; foreach($e in $w.data.edges){ if($e.node.meta -and $e.node.meta.currencyCode){ $cc=$e.node.meta.currencyCode; break } }
    if($cc){ $out.currencyCode=$cc }
    if($w.target -and $null -ne $w.target.value){ $out.target=[ordered]@{ value=$w.target.value } }
    $dims=@(); if($w.dims -and $w.dims.edges){ $dims=@($w.dims.edges|ForEach-Object{ [ordered]@{name=$_.node.name; id=$_.node.id} }) }
    $mets=@(); if($w.metrics -and $w.metrics.edges){ $mets=@($w.metrics.edges|ForEach-Object{ $_.node }) }
    $out.dimensions=@($dims|ForEach-Object{ $_.name })
    $out.metrics=@($mets|ForEach-Object{ $m=[ordered]@{name=$_.name; id=$_.id}; $u=Unit-Of $_.id; if($u){$m.unit=$u}; $m })
    $nd=$dims.Count
    $rows=[System.Collections.ArrayList]@()
    foreach($e in $w.data.edges){
      $node=$e.node
      $rk=if($node.isTotals){'total'}elseif($node.isSubtotals){'subtotal'}else{'data'}
      $dmap=[ordered]@{}
      for($i=0;$i -lt $nd;$i++){ $k=Uniq-Key $dmap $dims[$i].name $dims[$i].id $i; $dmap[$k]=(DimName $node.cells[$i]) }
      $mmap=[ordered]@{}
      for($j=0;$j -lt $mets.Count;$j++){ $k=Uniq-Key $mmap $mets[$j].name $mets[$j].id $j; $cur=$node.cells[$nd+$j]; $cmp=if($node.compareCells){$node.compareCells[$nd+$j]}else{$null}; $mmap[$k]=[ordered]@{current=$cur;compare=$cmp} }
      [void]$rows.Add([ordered]@{ kind=$rk; dimensions=$dmap; metrics=$mmap })
    }
    $out.rows=$rows
  }
  $out.raw = $w    # null-safe: $w may be null on an error response
  return $out
}

# ===================== trend (opt-in wide monthly pull) pure helpers =====================
# The ladder is a COARSE bracket, bisected to the true ceiling so months between rungs are not lost (C1).
$script:TrendLadder = @(48,36,24,18,12)   # months, descending

# Own month-dimension detector for the trend path (decoupled from Analyze's two detectors, per review).
function Test-TrendTimeWidget($dimNames){
  foreach($d in @($dimNames)){ if([string]$d -match '(?i)(^|[^a-z])(month|week|date|day)([^a-z]|$)'){ return $true } }
  return $false
}
# Normalize a dimension label to a YYYY-MM key, or $null if it is not a month bucket (real-row gate).
function ConvertTo-MonthKey($label){
  $s=[string]$label
  if($s -match '^(\d{4})-(\d{2})$'){ return $s }
  if($s -match '^(\d{4})-(\d{2})-\d{2}$'){ return ($Matches[1]+'-'+$Matches[2]) }
  if($s -match '^(\d{4})(\d{2})$'){ return ($Matches[1]+'-'+$Matches[2]) }
  return $null
}
# Month arithmetic on YYYY-MM as an ordinal (year*12 + monthIndex) so comparisons/diffs are exact.
function MonthKeyToOrdinal($mk){ if([string]$mk -match '^(\d{4})-(\d{2})$'){ return ([int]$Matches[1])*12 + ([int]$Matches[2] - 1) } return $null }
function OrdinalToMonthKey($o){ $y=[math]::Floor($o/12); $m=($o % 12)+1; return ('{0:D4}-{1:D2}' -f [int]$y,[int]$m) }
# The most-recent $minRun month keys must be strictly consecutive (rejects sparse/gapped false ceilings, M3).
function Test-TrailingContiguous($monthKeys,$minRun){
  $ords=@($monthKeys | ForEach-Object { MonthKeyToOrdinal $_ } | Where-Object { $null -ne $_ } | Sort-Object -Descending)
  if($ords.Count -lt $minRun){ return $false }
  for($i=0;$i -lt ($minRun-1);$i++){ if(($ords[$i]-$ords[$i+1]) -ne 1){ return $false } }
  return $true
}
# Choose the bracket: R = widest ladder rung with >=2 real months, F = narrowest empty rung above R.
# $probeMap: N(int) -> realRowCount. Returns @{ R=<int|null>; F=<int|null> }. Assumes monotonic (rows for
# N<=ceiling, empty above) which matches the observed overshoot-empties.
function Select-CeilingBracket($probeMap){
  $R=$null; $F=$null
  foreach($n in $script:TrendLadder){          # descending 48..12
    if(-not $probeMap.Contains($n)){ continue }
    if([int]$probeMap[$n] -ge 2){ $R=$n; break }   # first non-empty while descending = widest with rows
    else { $F=$n }                                 # narrowest empty seen above R
  }
  return @{ R=$R; F=$F }
}
# Next probe N strictly inside (R,F); $null once converged (F-R<=1) -> the true ceiling is R.
function Get-NextBisectN($R,$F){
  if($null -eq $R -or $null -eq $F){ return $null }
  if(($F - $R) -le 1){ return $null }
  return [int][math]::Floor(($R + $F)/2)
}
# TTL freshness for the ceiling cache (pure; injected $now).
function Test-CeilingFresh($discoveredAt,$now,$ttlDays){
  if(-not $discoveredAt){ return $false }
  try { $d=[datetimeoffset]::Parse([string]$discoveredAt).UtcDateTime } catch { return $false }
  return ((([datetimeoffset]$now).UtcDateTime - $d).TotalDays -lt $ttlDays)
}
# Current calendar month (the partial month to drop), from $now.
function Get-CurrentMonthKey($now){ return ([datetimeoffset]$now).ToString('yyyy-MM') }
# Extract per-month raw cells from a fetched single-time-dimension widget object.
# Returns @{ windowStatus = ok|overshoot-empty|error; metricIds[]; months[ @{ month; currency; values{metricId->raw} } ] }.
function Get-TrendMonthCells($obj){
  $out=[ordered]@{ windowStatus='ok'; metricIds=@(); months=@() }
  $w=$null; try { $w=$obj.data.widget } catch {}
  if(-not $w){ $out.windowStatus='error'; return $out }
  $mets=@(); if($w.metrics -and $w.metrics.edges){ $mets=@($w.metrics.edges | ForEach-Object { $_.node }) }
  $dims=@(); if($w.dims -and $w.dims.edges){ $dims=@($w.dims.edges | ForEach-Object { $_.node }) }
  $out.metricIds=@($mets | ForEach-Object { [string]$_.id })
  $nd=$dims.Count
  $edges=@(); if($w.data -and $w.data.edges){ $edges=@($w.data.edges) }
  if($edges.Count -eq 0){ $out.windowStatus='overshoot-empty'; return $out }
  # Resolve currency WIDGET-WIDE (like Normalize-Widget): low/zero-activity months can omit meta.currencyCode,
  # and a per-row currency would fork one real series into two basisVersions downstream (currency is in the hash).
  $wCur=$null; foreach($e in $edges){ if($e.node.meta -and $e.node.meta.currencyCode){ $wCur=[string]$e.node.meta.currencyCode; break } }
  $months=[System.Collections.ArrayList]@()
  foreach($e in $edges){
    $node=$e.node
    if($node.isTotals -or $node.isSubtotals){ continue }        # exclude total/subtotal rows
    if($nd -lt 1){ continue }
    $mk=ConvertTo-MonthKey $node.cells[0]
    if(-not $mk){ continue }                                    # not a month bucket -> skip
    $vals=[ordered]@{}
    for($j=0;$j -lt $mets.Count;$j++){ $vals[[string]$mets[$j].id]=$node.cells[$nd+$j] }
    [void]$months.Add([ordered]@{ month=$mk; currency=$wCur; values=$vals })
  }
  $out.months=@($months)
  return $out
}
# --- impure probe orchestration (hits the network; the pure bracket/bisect it calls are unit-tested) ---
function Probe-WidgetMonths($w,$n){
  $o = Fetch-Widget $w 5 (New-RelDateRange (-1*$n) 'month')
  return @((Get-TrendMonthCells $o).months | ForEach-Object { $_.month })
}
# Per-widget ceiling: lazily probe the ladder descending (stop at first rung with >=2 trailing-contiguous
# months = R, prior empty = F), then bisect (R,F) to the true max N. Returns months (0 = no monthly history).
function Get-WidgetCeiling($w){
  $R=$null; $F=$null
  foreach($n in $script:TrendLadder){
    $km = Probe-WidgetMonths $w $n
    if(Test-TrailingContiguous $km 2){ $R=$n; break } else { $F=$n }
  }
  if($null -eq $R){ return 0 }
  while($true){
    $mid = Get-NextBisectN $R $F
    if($null -eq $mid){ break }
    if(Test-TrailingContiguous (Probe-WidgetMonths $w $mid) 2){ $R=$mid } else { $F=$mid }
  }
  return $R
}

if($DefineOnly){ return }   # dot-source stops here (functions loaded, nothing run)

# ================================ run ================================
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
if(-not $ShareUrl){ throw "ShareUrl is required" }

# 1. resolve share key + report id
$html = Invoke-RestMethod -Uri $ShareUrl
if ($html -match 'app\.swydo\.com/g/([^/]+)/reports/([A-Za-z0-9_-]+)') { $script:key=$Matches[1]; $reportId=$Matches[2] }
else { throw "Could not find 'app.swydo.com/g/<key>/reports/<id>' iframe in $ShareUrl" }
Write-Host ("key=***  reportId={0}" -f $reportId)   # never echo the raw share key (it is the Basic-auth credential)

# 2. JWT
$script:jwt = Mint-Jwt; $script:jwtAt = Get-Date

# 3. websocket
Connect-Ws
if(-not $script:socketId){ throw "no socketId from wss://ws.swydo.com" }
Write-Host "socketId=$script:socketId"

# 4. structure
$structQ='query($id:ID!){report(id:$id){id name subtitle orientation custom client{id name} author{id name email} dateRange compareDateRange sections{id name isHidden} widgets{edges{node{id visual{id} section{id} source{id parts{provider{id name}}}}}} teamName}}'
$structRaw = Invoke-GQL $structQ @{id=$reportId}
$s = ($structRaw | ConvertFrom-Json).data.report
if(-not $s){ throw "structure query returned no report: $structRaw" }
$script:dr=$s.dateRange; $script:cp=$s.compareDateRange
$script:secMap=@{}; if($s.sections){ $s.sections | ForEach-Object { $script:secMap[$_.id]=$_.name } }
$wids = @($s.widgets.edges | ForEach-Object { @{ id=$_.node.id; visual=$_.node.visual.id; section=$_.node.section.id } })
Write-Host ("report: {0} | widgets: {1}" -f $s.name, $wids.Count)

# ============================ TREND: opt-in wide monthly pull ============================
if($Trend){
  $now = Get-Date
  if(-not $CacheDir){ $cbase = if($env:LOCALAPPDATA){ $env:LOCALAPPDATA } else { $HOME }; $CacheDir = Join-Path $cbase 'swydee\ceilings' }
  New-Item -ItemType Directory -Force -Path $CacheDir | Out-Null
  $cachePath = Join-Path $CacheDir ("$reportId.json")
  $cache=@{}; if(Test-Path $cachePath){ try{ $cj=[IO.File]::ReadAllText($cachePath)|ConvertFrom-Json; foreach($p in $cj.PSObject.Properties){ $cache[$p.Name]=$p.Value } }catch{} }

  # data widgets with declared provider
  $twids=@()
  foreach($e in $s.widgets.edges){
    $n=$e.node; if($n.visual.id -in @('TEXT','PAGE_BREAK')){ continue }
    $prov=$null; $pname=$null
    if($n.source -and $n.source.parts){ $pp=@($n.source.parts | ForEach-Object { $_.provider }); if($pp.Count -gt 0){ $prov=$pp[0].id; $pname=$pp[0].name } }
    $twids += @{ id=$n.id; visual=$n.visual.id; prov=$prov; pname=$pname }
  }
  # discovery: one fetch each at month/-12 (safe, dims return regardless of data rows) -> classify time widgets
  Write-Host ("trend: discovering monthly time-series widgets among {0} data widgets..." -f $twids.Count)
  $trendW=@()
  foreach($w in $twids){
    $o=Fetch-Widget $w 5 (New-RelDateRange -12 'month')
    $dims=@(); try{ $dims=@($o.data.widget.dims.edges.node.name) }catch{}
    if((@($dims).Count -eq 1) -and (Test-TrendTimeWidget $dims)){ $trendW += $w; Write-Host ("  TIME {0} [{1}] prov={2} dim='{3}'" -f $w.id,$w.visual,$w.prov,($dims -join ',')) }
  }
  if($trendW.Count -eq 0){ throw "no single-month-dimension widget found; this report has no monthly time series to accumulate" }

  $curMonth = Get-CurrentMonthKey $now
  $cells=[System.Collections.ArrayList]@()
  $cov=[ordered]@{}
  $newCache=@{}
  foreach($w in $trendW){
    $ceiling=$null
    $ce=$cache[$w.id]
    if($ce -and (Test-CeilingFresh $ce.discoveredAt $now 30)){
      if(Test-TrailingContiguous (Probe-WidgetMonths $w ([int]$ce.ceilingMonths)) 2){ $ceiling=[int]$ce.ceilingMonths }
    }
    if($null -eq $ceiling){ $ceiling = Get-WidgetCeiling $w }
    if($ceiling -le 0){ Write-Host ("  {0}: no monthly history (ceiling 0)" -f $w.id); continue }
    $newCache[$w.id]=@{ ceilingMonths=$ceiling; discoveredAt=([datetimeoffset]$now).ToString('o') }
    $mc = Get-TrendMonthCells (Fetch-Widget $w 6 (New-RelDateRange (-1*$ceiling) 'month'))
    $wMonths=@()
    foreach($mo in $mc.months){
      if($mo.month -eq $curMonth){ continue }   # drop the partial current month
      $wMonths += $mo.month
      foreach($mid in @($mo.values.Keys)){
        $prov = if($w.prov){ $w.prov } else { ($mid -split ':')[0] }
        [void]$cells.Add([ordered]@{ providerId=$prov; metricId=[string]$mid; month=$mo.month; rawValue=$mo.values[$mid]; currency=$mo.currency; unit=(Unit-Of $mid) })
      }
    }
    $pk = if($w.prov){ $w.prov } else { 'unknown' }
    if(-not $cov.Contains($pk)){ $cov[$pk]=[ordered]@{ providerId=$pk; providerName=$w.pname; hasMonthlyGrain=$true; ceilingMonths=$ceiling; probeLadderHit=$false; earliestMonth=$null; latestMonth=$null; windowStatus=$mc.windowStatus; probedAt=([datetimeoffset]$now).ToString('o') } }
    else { if($ceiling -gt $cov[$pk].ceilingMonths){ $cov[$pk].ceilingMonths=$ceiling } }
    if($wMonths.Count -gt 0){
      $mn=($wMonths|Sort-Object|Select-Object -First 1); $mx=($wMonths|Sort-Object|Select-Object -Last 1)
      if(-not $cov[$pk].earliestMonth -or $mn -lt $cov[$pk].earliestMonth){ $cov[$pk].earliestMonth=$mn }
      if(-not $cov[$pk].latestMonth   -or $mx -gt $cov[$pk].latestMonth){ $cov[$pk].latestMonth=$mx }
    }
    if($script:TrendLadder -contains $ceiling){ $cov[$pk].probeLadderHit=$true }
    Write-Host ("  {0}: ceiling {1}mo, {2} months pulled" -f $w.id,$ceiling,$wMonths.Count)
  }
  # providers present as data widgets but with no monthly grain
  foreach($p in (@($twids | ForEach-Object { $_.prov }) | Where-Object { $_ } | Sort-Object -Unique)){
    if(-not $cov.Contains($p)){ $pn=(@($twids|Where-Object{$_.prov -eq $p})[0]).pname; $cov[$p]=[ordered]@{ providerId=$p; providerName=$pn; hasMonthlyGrain=$false; ceilingMonths=0; probeLadderHit=$false; earliestMonth=$null; latestMonth=$null; windowStatus='no-monthly-widget'; probedAt=([datetimeoffset]$now).ToString('o') } }
  }

  try { [IO.File]::WriteAllText($cachePath, (($newCache | ConvertTo-Json -Depth 10)), (New-Object Text.UTF8Encoding($false))) } catch {}

  $tstamp=(Get-Date).ToString('yyyy-MM-dd-HH-mm-ss')
  $tslug=($s.name -replace '[^A-Za-z0-9]+','-').Trim('-').ToLower(); if(-not $tslug){ $tslug='report' }
  $twarn=@(); $noGrain=@($cov.Values | Where-Object { -not $_.hasMonthlyGrain } | ForEach-Object { $_.providerId })
  if($noGrain.Count -gt 0){ $twarn += ("no monthly time-series widget for provider(s): " + ($noGrain -join ', ') + " -- add a by-month widget to include them in trend history") }
  $tdoc=[ordered]@{
    meta=[ordered]@{
      tool='Get-SwydoReport.ps1'; schemaVersion=2; trend=$true; extractedAt=(Get-Date).ToString('o')
      shareUrl=$ShareUrl; shareKey=$script:key; reportId=$reportId
      trendWidgets=$trendW.Count; cellCount=$cells.Count; coverage=@($cov.Values); warnings=$twarn
    }
    report=[ordered]@{ name=$s.name; client=$s.client.name; author=[ordered]@{name=$s.author.name;email=$s.author.email}; team=$s.teamName }
    trendCells=@($cells)
  }
  $tpath=Join-Path $OutDir "$tstamp-$tslug.trend.json"
  [IO.File]::WriteAllText($tpath, ($tdoc | ConvertTo-Json -Depth 100), (New-Object Text.UTF8Encoding($false)))
  try{ $script:ws.Dispose() }catch{}
  Write-Host ("trend done -> {0}  ({1} cells across {2} providers{3})" -f $tpath, $cells.Count, @($cov.Values|Where-Object{$_.hasMonthlyGrain}).Count, $(if($twarn){", "+$twarn.Count+" warning(s)"}else{""}))
  return
}

# 5. fetch all, reconcile cold widgets
$fetched=@{}; $empty=@()
try {
  foreach($w in $wids){
    $o = Fetch-Widget $w 5; $fetched[$w.id]=$o
    $n = $o.data.widget.data.edges.Count
    $tag = if($n -gt 0){"DATA"} elseif($o.data.widget.content){"TEXT"} else {"none"}
    Write-Host ("  {0,-4} {1} [{2}] rows={3}" -f $tag,$w.id,$w.visual,$n)
    if($n -eq 0 -and $w.visual -notin @('TEXT','PAGE_BREAK')){ $empty += $w }
  }
  for($round=1; $round -le 3 -and $empty.Count -gt 0; $round++){
    Write-Host ("reconcile round {0}: {1} still empty" -f $round,$empty.Count); Start-Sleep -Seconds 2
    $still=@()
    foreach($w in $empty){ $o=Fetch-Widget $w 4; $fetched[$w.id]=$o; if($o.data.widget.data.edges.Count -eq 0){ $still+=$w } }
    $empty=$still
  }
} finally { try{ $script:ws.Dispose() }catch{} }

# 6. normalize + assemble
$widgetsOut = @(foreach($w in $wids){ Normalize-Widget $w $fetched[$w.id] })
$warnings=@(); if($empty.Count -gt 0){ $warnings += ("no rows returned for: " + (($empty|ForEach-Object{$_.id}) -join ', ')) }
$unitBasis = @('google-adwords','facebook-ads')
$provIds = @(); foreach($wd in $widgetsOut){ if($wd.kind -eq 'data' -and $wd.metrics){ foreach($m in $wd.metrics){ $provIds += (($m.id -split ':')[0]) } } }
$provIds = @($provIds | Sort-Object -Unique)
$unverified = @($provIds | Where-Object { $_ -notin $unitBasis })
if($unverified.Count -gt 0){ $warnings += ("units not inferred for unverified provider(s): " + ($unverified -join ', ') + " -- values are raw; confirm scale/currency downstream") }

$doc = [ordered]@{
  meta = [ordered]@{
    tool='Get-SwydoReport.ps1'; schemaVersion=2; extractedAt=(Get-Date).ToString('o')
    shareUrl=$ShareUrl; shareKey=$script:key; reportId=$reportId
    widgetCount=$wids.Count; dataWidgets=@($widgetsOut|Where-Object{$_.kind -eq 'data'}).Count
    unitBasis=$unitBasis; warnings=$warnings
  }
  report = [ordered]@{
    name=$s.name; subtitle=$s.subtitle; orientation=$s.orientation
    client=$s.client.name; author=[ordered]@{name=$s.author.name;email=$s.author.email}; team=$s.teamName
    dateRange=$s.dateRange; compareDateRange=$s.compareDateRange
    sections=@($s.sections|ForEach-Object{ [ordered]@{id=$_.id;name=$_.name} }); custom=$s.custom
  }
  widgets = $widgetsOut
}

$stamp = (Get-Date).ToString('yyyy-MM-dd-HH-mm-ss')
$slug  = ($s.name -replace '[^A-Za-z0-9]+','-').Trim('-').ToLower(); if(-not $slug){ $slug='report' }
$path  = Join-Path $OutDir "$stamp-$slug.json"
[IO.File]::WriteAllText($path, ($doc | ConvertTo-Json -Depth 100), (New-Object Text.UTF8Encoding($false)))
Write-Host ("done -> {0}  ({1} widgets, {2} with data{3})" -f $path, $wids.Count, $doc.meta.dataWidgets, $(if($warnings){", "+$warnings.Count+" warning(s)"}else{""}))
