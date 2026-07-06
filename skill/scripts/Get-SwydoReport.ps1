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
function Fetch-Widget($w, $attempts){
  $q = $script:baseQ -replace '__ID__',$w.id -replace '__N__',"$PageSize"
  $needData = $w.visual -notin @('TEXT','PAGE_BREAK')
  $obj=$null
  for($a=1;$a -le $attempts;$a++){
    if($script:ws.State -ne 'Open'){ try{ Connect-Ws }catch{} }
    $obj = (Invoke-GQL $q @{sid=$script:socketId;dr=$script:dr;cp=$script:cp;after=$null}) | ConvertFrom-Json
    if(-not $needData -or ($obj.data.widget.data.edges.Count -gt 0)){ break }
    Ws-Pulse; Start-Sleep -Milliseconds 900
  }
  if($needData -and $obj.data.widget -and $obj.data.widget.data.edges.Count -gt 0){
    $wd=$obj.data.widget.data
    $all=[System.Collections.ArrayList]@(); $wd.edges | ForEach-Object {[void]$all.Add($_)}
    $pi=$wd.pageInfo
    while($pi.hasNextPage){
      $pg=((Invoke-GQL $q @{sid=$script:socketId;dr=$script:dr;cp=$script:cp;after=$pi.endCursor}) | ConvertFrom-Json).data.widget.data
      if(-not $pg -or $pg.edges.Count -eq 0){ break }
      $pg.edges | ForEach-Object {[void]$all.Add($_)}; $pi=$pg.pageInfo
    }
    $obj.data.widget.data.edges=$all.ToArray(); $obj.data.widget.data.pageInfo=$pi
  }
  return $obj
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

if($DefineOnly){ return }   # dot-source stops here (functions loaded, nothing run)

# ================================ run ================================
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
if(-not $ShareUrl){ throw "ShareUrl is required" }

# 1. resolve share key + report id
$html = Invoke-RestMethod -Uri $ShareUrl
if ($html -match 'app\.swydo\.com/g/([^/]+)/reports/([A-Za-z0-9_-]+)') { $script:key=$Matches[1]; $reportId=$Matches[2] }
else { throw "Could not find 'app.swydo.com/g/<key>/reports/<id>' iframe in $ShareUrl" }
Write-Host "key=$script:key  reportId=$reportId"

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
