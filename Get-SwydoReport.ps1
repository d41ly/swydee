<#
.SYNOPSIS
  Extract all widget data from a Swydo shared report (swy.do/shares/<KEY>) with no browser.
.DESCRIPTION
  Resolves the share link -> mints a JWT -> opens a websocket for a socketId ->
  queries report structure -> pulls every widget's fields + data (paginated, with cache-warm
  retry) to one JSON file per widget. See SWYDO_REPORT_EXTRACTION_SPEC.md for the protocol.
  Windows PowerShell 5.1+ / .NET only (no jq/node/python needed).
.NOTES
  Verified 2026-07-05. Key facts the code depends on (see spec):
   - report-level widgets.source has NO 'name' in the share scope (only source.id / parts.*);
     source.name is available per-widget. Requesting it report-level => FORBIDDEN, whole query fails.
   - data/fields need a socketId (ID!), but the value is NOT validated for cache hits: any string
     returns cached rows. A live socket only matters to receive a cache-MISS computation push.
   - JWT lifetime is 600s; re-mint on 401.
   - referenceDateRange/referenceCompareDate must be the report's own dateRange/compareDateRange
     re-serialized with -Depth >= 10 (default depth 2 mangles them -> "date range object invalid").
.EXAMPLE
  .\Get-SwydoReport.ps1 -ShareUrl https://swy.do/shares/jNqoFL4gPkgSNXMoT8neKrgxHKo3nFnoDvhFhdY2QimFTqTN -OutDir .\out
#>
param(
  [Parameter(Mandatory)] [string]$ShareUrl,
  [string]$OutDir = ".\swydo_out",
  [string]$Secret = "",        # password for protected shares; empty for public
  [int]$PageSize = 500
)
$ErrorActionPreference = "Stop"
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

# ---- 1. resolve share key + report id from the iframe on the swy.do page ----
$html = Invoke-RestMethod -Uri $ShareUrl
if ($html -match 'app\.swydo\.com/g/([^/]+)/reports/([A-Za-z0-9_-]+)') { $key=$Matches[1]; $reportId=$Matches[2] }
else { throw "Could not find 'app.swydo.com/g/<key>/reports/<id>' iframe in $ShareUrl" }
Write-Host "key=$key  reportId=$reportId"

# ---- 2. JWT (re-mintable; Basic base64(UTF8 "<key>:<secret>"); 600s lifetime) ----
function Mint-Jwt {
  $basic = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("$key`:$Secret"))
  $j = (Invoke-RestMethod "https://vesting.swydo.com/jwt/share" -Headers @{authorization="Basic $basic"}).jwt
  if (-not $j) { throw "JWT mint failed (bad key or secret?)" }
  return $j
}
$script:jwt = Mint-Jwt
$script:jwtAt = Get-Date

# GraphQL helper: re-mints on 401, returns the JSON body even for 4xx (so errors are inspectable)
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
      if ($resp) { return (New-Object IO.StreamReader($resp.GetResponseStream())).ReadToEnd() }  # surface GraphQL error body
      throw
    }
  }
}

# ---- 3. websocket -> socketId. Required arg for data/fields; a LIVE socket only matters for
#         cache-MISS pushes (novel dateRange). Server sends no PINGs and drops idle sockets in
#         ~2s, so we self-heartbeat and reconnect defensively. ----
$ct=[Threading.CancellationToken]::None
$buf=[byte[]]::new(1048576)
function Ws-Send($o){ try{ $b=[Text.Encoding]::UTF8.GetBytes(($o|ConvertTo-Json -Compress -Depth 10)); $script:ws.SendAsync([ArraySegment[byte]]::new($b),'Text',$true,$ct).Wait() }catch{} }
function Ws-Recv($ms){ try{ $s=[ArraySegment[byte]]::new($buf); $t=$script:ws.ReceiveAsync($s,$ct); if($t.Wait($ms)){ return [Text.Encoding]::UTF8.GetString($buf,0,$t.Result.Count) } }catch{}; return $null }
function Connect-Ws {
  $script:ws=[System.Net.WebSockets.ClientWebSocket]::new()
  $script:ws.Options.KeepAliveInterval=[TimeSpan]::FromSeconds(15)
  $script:ws.ConnectAsync([Uri]"wss://ws.swydo.com",$ct).Wait()
  Ws-Send @{kind=1; payload=@{}}
  $script:socketId=$null
  for($i=0;$i -lt 8 -and -not $script:socketId;$i++){ $m=Ws-Recv 5000; if($m){ try{$o=$m|ConvertFrom-Json; if($o.kind -eq 2){$script:socketId=$o.payload.socketId}}catch{} } }
}
Connect-Ws
if(-not $script:socketId){ throw "no socketId from wss://ws.swydo.com" }
Write-Host "socketId=$script:socketId"
function Ws-Pulse {   # keep socket live between retries; reconnect (new socketId) if it dropped
  if($script:ws.State -ne 'Open'){ try{ Connect-Ws }catch{} ; return }
  Ws-Send @{kind=5; payload=@{socketId=$script:socketId}}
  $m=Ws-Recv 1000
  if($m){ try{$o=$m|ConvertFrom-Json; if($o.kind -eq 4){ Ws-Send @{kind=5;payload=@{socketId=$script:socketId}} }}catch{} }
}

# ---- 4. structure (note: NO source.name at report.widgets level -> would 403) ----
$structQ='query($id:ID!){report(id:$id){id name subtitle client{id name} author{id name email} dateRange compareDateRange sections{id name isHidden} teamName widgets{edges{node{id visual{id} section{id} source{id parts{provider{id name} dataSource{id}}}}}}}}'
$structRaw = Invoke-GQL $structQ @{id=$reportId}
$structRaw | Set-Content "$OutDir\_structure.json" -Encoding utf8
$s = ($structRaw | ConvertFrom-Json).data.report
if(-not $s){ throw "structure query returned no report (check for a `"errors`" body in _structure.json): $structRaw" }
$dr=$s.dateRange; $cp=$s.compareDateRange
$wids = @($s.widgets.edges | ForEach-Object { @{ id=$_.node.id; visual=$_.node.visual.id } })
Write-Host ("report: {0} | widgets: {1}" -f $s.name, $wids.Count)

# ---- 5. per-widget pull: cache-warm retry (a cold widget needs a live socket + time to
#         compute), then paginate via `after`. Returns the parsed object; writes nothing. ----
$baseQ='query($sid:ID!,$dr:DateRange!,$cp:ComparePeriod!,$after:String){widget(id:"__ID__"){id content comparisonFormat visual{id} displayOptions{title} source{id name parts{provider{id name}}} metrics:fields(socketId:$sid,type:METRIC){edges{node{id name}}} dims:fields(socketId:$sid,type:DIMENSION){edges{node{id name}}} data(first:__N__,after:$after,socketId:$sid,referenceDateRange:$dr,referenceCompareDate:$cp){edges{node}pageInfo{hasNextPage endCursor}}}}'
function Fetch-Widget($w, $attempts){
  $q = $baseQ -replace '__ID__',$w.id -replace '__N__',"$PageSize"
  $needData = $w.visual -notin @('TEXT','PAGE_BREAK')
  $obj=$null
  for($a=1;$a -le $attempts;$a++){
    if($script:ws.State -ne 'Open'){ try{ Connect-Ws }catch{} }   # ensure a live socket for cache-miss pushes
    $obj = (Invoke-GQL $q @{sid=$script:socketId;dr=$dr;cp=$cp;after=$null}) | ConvertFrom-Json
    if(-not $needData -or ($obj.data.widget.data.edges.Count -gt 0)){ break }
    Ws-Pulse; Start-Sleep -Milliseconds 900                       # give the async computation time to land
  }
  if($needData -and $obj.data.widget -and $obj.data.widget.data.edges.Count -gt 0){  # paginate
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
function Save-Widget($w,$obj){
  ($obj | ConvertTo-Json -Depth 64) | Set-Content "$OutDir\$($w.id).json" -Encoding utf8
  $n = $obj.data.widget.data.edges.Count
  $tag = if($n -gt 0){"DATA"} elseif($obj.data.widget.content){"TEXT"} else {"none"}
  Write-Host ("  {0,-4} {1} [{2}] rows={3}" -f $tag,$w.id,$w.visual,$n)
  return $n
}
try {
  $empty=@()
  foreach($w in $wids){                                # pass 1
    $obj = Fetch-Widget $w 5
    if((Save-Widget $w $obj) -eq 0 -and $w.visual -notin @('TEXT','PAGE_BREAK')){ $empty += $w }
  }
  for($round=1; $round -le 3 -and $empty.Count -gt 0; $round++){   # reconciliation: cold widgets triggered
    Write-Host ("reconcile round {0}: {1} still empty" -f $round,$empty.Count)   # in pass 1 have had time to compute
    Start-Sleep -Seconds 2
    $still=@()
    foreach($w in $empty){ $obj = Fetch-Widget $w 4; if((Save-Widget $w $obj) -eq 0){ $still += $w } }
    $empty=$still
  }
  if($empty.Count -gt 0){ Write-Host ("WARN: {0} widget(s) never returned rows: {1}" -f $empty.Count, (($empty | ForEach-Object { $_.id }) -join ', ')) }
} finally { try{ $script:ws.Dispose() }catch{} }
Write-Host "done -> $OutDir"
