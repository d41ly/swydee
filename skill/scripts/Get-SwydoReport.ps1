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

  OUTPUT SCHEMA (schemaVersion 3; v2 differs only by the absence of the additive keys below):
    {
      "meta":   { tool, schemaVersion:3, extractedAt, shareUrl, shareKey, reportId,
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
  [string[]]$Platform,       # optional provider-id filter (repeatable or comma-list); pull ONLY these providers
  [int]$MaxWaitSec = 90,     # per-widget wall-clock budget for Swydo to answer (EXTR-aPatientHarvest-1 S9)
  [int]$MaxTotalWaitSec = 420, # whole-run waiting budget; the run stops fetching when it is spent
  [switch]$ProbeFields,      # opt-in (ANLZ-aUniformLattice-2 D9): record meta.fieldProbe. OFF by default so
                             # the default extraction path gains no network call and no wall clock.
  [switch]$DefineOnly
)
$ErrorActionPreference = "Stop"

# ============================ function definitions ============================
$script:ct  = [Threading.CancellationToken]::None
$script:buf = [byte[]]::new(1048576)
# EXTR-aPatientHarvest-1 S1: the pending ReceiveAsync lives HERE, across calls. Abandoning it on a
# timed-out slice is what made the shipped extractor blind: the next frame completed the orphaned
# task into $script:buf with nobody reading .Result, so it was consumed and lost, and the following
# ReceiveAsync was refused by ClientWebSocket (one outstanding receive only) into a bare catch{}.
# Measured: shipped shape saw 0 of 5 kind:3 frames, this shape saw 5 of 5, same cold workload.
$script:pendingRecv        = $null
$script:outstandingComputes = 0    # widgets that ended with no verdict; their compute may still land
$script:reconnects          = 0
$script:totalWaitedMs       = 0
$script:budgetExhausted     = $false
$script:httpTimeoutSec      = 30   # PS 5.1 applies NO default (measured 721 s against a black hole)
$script:sendWaitMs          = 10000
$script:fetchPlan           = $null
# NOT named $script:maxTotalWaitSec: PS variable names are case-insensitive at one scope, so that
# name IS the [int]$MaxTotalWaitSec param, and initialising it to $null coerced the param to 0 -
# which made every widget start with an already-exhausted run budget.
$script:runWaitCapSec       = $null

# Clear every piece of cross-widget fetch state. The run body calls this once at start; suites call
# it in setup so no case inherits another's pending receive or budget.
function Reset-FetchState {
  $script:pendingRecv         = $null
  $script:outstandingComputes = 0
  $script:reconnects          = 0
  $script:totalWaitedMs       = 0
  $script:budgetExhausted     = $false
}

# --- auth / GraphQL (reference $key/$Secret/$script:jwt at call time) ---
function Mint-Jwt {
  $basic = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("$script:key`:$Secret"))
  $j = (Invoke-RestMethod "https://vesting.swydo.com/jwt/share" -TimeoutSec $script:httpTimeoutSec -Headers @{authorization="Basic $basic"}).jwt
  if (-not $j) { throw "JWT mint failed (bad key or secret?)" }
  return $j
}
# An OBJECT, never a JSON string: a caller that forgets to branch faults loudly at ConvertFrom-Json
# instead of quietly parsing to nulls and looking like an empty widget.
function New-FetchFailure($reason,$attempts,$lastError){
  return [pscustomobject]@{ __fetchFailed=$true; reason=[string]$reason; attempts=[int]$attempts; lastError=[string]$lastError }
}
function Test-FetchFailed($r){
  if($null -eq $r){ return $false }
  if($r -is [string]){ return $false }
  if($null -eq $r.PSObject){ return $false }
  return ($null -ne $r.PSObject.Properties['__fetchFailed'])
}
function Invoke-GQL($q,$vars,[switch]$NoRetry){
  if ((((Get-Date) - $script:jwtAt).TotalSeconds) -gt 500) { $script:jwt = Mint-Jwt; $script:jwtAt = Get-Date }
  $maxTries = 3; if($NoRetry){ $maxTries = 1 }
  $body = @{query=$q; variables=$vars} | ConvertTo-Json -Compress -Depth 40
  $lastErr = ''
  $reminted = $false    # hoisted: one 401 re-mint per call, never a re-mint loop
  for($try=1; $try -le $maxTries; $try++){
    try {
      return (Invoke-WebRequest "https://graphql.swydo.com" -Method Post -UseBasicParsing -TimeoutSec $script:httpTimeoutSec `
              -Headers @{authorization="Bearer $script:jwt"; "content-type"="application/json"} -Body $body).Content
    } catch {
      $lastErr = [string]$_.Exception.Message
      $resp = $null; try { $resp = $_.Exception.Response } catch {}
      if ($resp) {
        $code = 0; try { $code = [int]$resp.StatusCode } catch {}
        if ($code -eq 401 -and -not $reminted) {
          $reminted = $true
          try { $script:jwt = Mint-Jwt; $script:jwtAt = Get-Date; continue } catch { $lastErr = [string]$_.Exception.Message }
        }
        # a real HTTP response (GraphQL errors, 4xx bodies) is DATA, not a transport fault
        try { return (New-Object IO.StreamReader($resp.GetResponseStream())).ReadToEnd() } catch { }
      }
    }
    if($try -lt $maxTries){ Start-Sleep -Milliseconds ([int]([math]::Pow(2,$try) * 250)) }
  }
  # Startup calls (share page, structure query) opt out of retry AND keep failing loudly: a bad link
  # must not degrade into a half-empty document.
  if($NoRetry){ throw ("transport fault after " + $maxTries + " attempt(s): " + $lastErr) }
  return (New-FetchFailure 'transport' $maxTries $lastErr)
}

# --- websocket (live socketId for cache-miss pushes) ---
function Ws-Send($o){
  try{
    if($null -eq $script:ws){ return $false }
    $b=[Text.Encoding]::UTF8.GetBytes(($o|ConvertTo-Json -Compress -Depth 10))
    $t=$script:ws.SendAsync([ArraySegment[byte]]::new($b),'Text',$true,$script:ct)
    return [bool]$t.Wait($script:sendWaitMs)
  }catch{ return $false }
}
# S1. The slot is cleared ONLY when the task's Result has been read, or the task ended
# Faulted/Canceled, or the peer sent Close. A timed-out slice keeps it pending so the frame that
# arrives next is still delivered to the NEXT call rather than vanishing.
function Ws-Recv($ms){
  try {
    if($null -eq $script:pendingRecv){
      if($null -eq $script:ws){ return $null }
      $seg=[ArraySegment[byte]]::new($script:buf)
      $script:pendingRecv = $script:ws.ReceiveAsync($seg,$script:ct)
    }
    $t = $script:pendingRecv
    if($t.Wait($ms)){
      $r = $t.Result
      $script:pendingRecv = $null
      if($r.MessageType -eq 'Close'){ return $null }
      return [Text.Encoding]::UTF8.GetString($script:buf,0,$r.Count)
    }
    if($t.IsFaulted -or $t.IsCanceled){ $script:pendingRecv = $null }
  } catch {
    $script:pendingRecv = $null
  }
  return $null
}
# Returns $true only with a socketId in hand. Never throws into a bare catch{}: the caller decides
# whether a dead socket ends the widget or the run.
function Connect-Ws {
  $script:pendingRecv = $null      # FIRST: a task from the dead socket must never be re-awaited
  $script:socketId    = $null
  $plan = $script:fetchPlan
  if($null -eq $plan){ $plan = Get-FetchPlan $null }
  try { if($script:ws){ $script:ws.Dispose() } } catch {}
  $script:ws = $null
  try {
    $w=[System.Net.WebSockets.ClientWebSocket]::new()
    $w.Options.KeepAliveInterval=[TimeSpan]::FromSeconds(15)
    $t=$w.ConnectAsync([Uri]"wss://ws.swydo.com",$script:ct)
    if(-not $t.Wait([int]$plan.handshakeMs)){ return $false }
    $script:ws=$w
  } catch { return $false }
  if(-not (Ws-Send @{kind=1; payload=@{}})){ return $false }
  $sw=[Diagnostics.Stopwatch]::StartNew()
  while($sw.ElapsedMilliseconds -lt [int]$plan.handshakeMs){
    $m=Ws-Recv ([int]$plan.sliceMs)
    if($m){ try{ $o=$m|ConvertFrom-Json; if($o.kind -eq 2){ $script:socketId=$o.payload.socketId; break } }catch{} }
  }
  $sw.Stop()
  $script:totalWaitedMs = $script:totalWaitedMs + [int]$sw.ElapsedMilliseconds
  return ($null -ne $script:socketId)
}
# Reconnect and account for it. A new socketId ORPHANS any compute still running for the old one,
# which is exactly what makes positional frame attribution safe across a widget boundary.
function Reset-Socket {
  $plan = $script:fetchPlan
  if($null -eq $plan){ $plan = Get-FetchPlan $null }
  if($script:reconnects -ge [int]$plan.maxReconnects){ return $false }
  $script:reconnects = $script:reconnects + 1
  if(Connect-Ws){ $script:outstandingComputes = 0; return $true }
  return $false
}
# Drain frames already buffered so a leftover verdict is not read as the next widget's answer.
# drainSliceMs must be NON-ZERO: Task.Wait(0) returns false on a frame already sitting in the OS
# buffer, which would silently turn the drain into a no-op.
function Drain-Ws($plan){
  if($null -eq $plan){ $plan = Get-FetchPlan $null }
  $n=0
  while($n -lt 200){
    $m = Ws-Recv ([int]$plan.drainSliceMs)
    if(-not $m){ break }
    $n++
    try{ $o=$m|ConvertFrom-Json; if($o.kind -eq 4){ [void](Ws-Send @{kind=5;payload=@{socketId=$script:socketId}}) } }catch{}
  }
  return $n
}
# Read until THIS request's verdict lands or the slice budget runs out. kind:3 carries the verdict
# (RESOLVED = data ready, REJECTED = out of range and never coming); kind:4 is a keepalive.
function Wait-WidgetVerdict($budgetMs,$plan){
  if($null -eq $plan){ $plan = Get-FetchPlan $null }
  $sw=[Diagnostics.Stopwatch]::StartNew()
  $verdict=$null
  while($sw.ElapsedMilliseconds -lt [int]$budgetMs){
    $m = Ws-Recv ([int]$plan.sliceMs)
    if($m){
      $o=$null; try{ $o=$m|ConvertFrom-Json }catch{}
      if($o){
        if($o.kind -eq 3){ $verdict = [string]$o.payload.status; break }
        if($o.kind -eq 4){ [void](Ws-Send @{kind=5;payload=@{socketId=$script:socketId}}) }
      }
    }
  }
  $sw.Stop()
  $script:totalWaitedMs = $script:totalWaitedMs + [int]$sw.ElapsedMilliseconds
  return @{ verdict=$verdict; waitedMs=[int]$sw.ElapsedMilliseconds }
}

# --- pure helpers ---
# Every knob the fetch state machine turns, in ONE place, so a suite can assert the schedule without
# sleeping and a future retune never has to touch the state machine.
function Get-FetchPlan($maxWaitSec){
  $m = 90
  if($null -ne $maxWaitSec){ try { $m = [int]$maxWaitSec } catch { $m = 90 } }
  if($m -lt 1){ $m = 1 }
  return [ordered]@{
    maxWaitSec         = $m
    sliceMs            = 500     # one websocket read slice
    pollEveryMs        = 3000    # fallback re-query cadence when no frame arrives
    drainSliceMs       = 50      # non-zero on purpose; Wait(0) would no-op the drain
    handshakeMs        = 15000   # bound on connect + kind:2 discovery
    quietFallbackMs    = 6000
    minFallbackQueries = 3
    retryUnsettledOnce = $true   # the silent band is transient: 37mo went silent 30 s, then REJECTED in 49 ms
    maxReconnects      = 3
    transportRetries   = 3
    # A verdict is attributed positionally, so a LATE verdict from the previous widget can be read as
    # this one's. Observed live: widgets with data were being marked empty-resolved off a stale frame.
    # Before believing "resolved but empty", wait one more window: this widget's OWN verdict will
    # arrive if its compute is still running. Costs one extra wait+query on genuinely empty widgets.
    emptyConfirms      = 1
    # Ceiling probes are cheap and are EXPECTED to be refused: a refusal measured 44-260 ms and a
    # resolve 1.2-3.4 s, so a probe never needs the full per-widget budget. Without this the
    # unsettled band (measured at 37 and 39 months) burns 90 s twice per rung, and a trend run spends
    # most of its whole-run budget re-deciding a ceiling it already knows.
    probeMaxWaitSec    = 10
  }
}
# The four-state classifier. $outstandingComputes guards the one window positional attribution cannot
# cover: a verdict from a widget that already timed out can arrive during the NEXT widget's wait, and
# reading it as "resolved, no rows" would turn a real gap into a silent "genuinely empty".
function Get-WidgetOutcome($verdict,$rows,$budgetLeftMs,$outstandingComputes){
  $n = 0;   if($null -ne $rows){ try { $n = [int]$rows } catch { $n = 0 } }
  $out = 0; if($null -ne $outstandingComputes){ try { $out = [int]$outstandingComputes } catch { $out = 0 } }
  $v = ''
  if($null -ne $verdict){ $v = ([string]$verdict).ToUpperInvariant() }
  if($n -gt 0){ return 'filled' }
  if($v -eq 'REJECTED'){ return 'rejected' }
  if($v -eq 'RESOLVED'){
    if($out -gt 0){ return 'incomplete' }
    return 'empty-resolved'
  }
  return 'incomplete'
}
# Build the whole additive meta block from the per-widget outcome records. Pure, and defined above the
# -DefineOnly return, so the completeness contract is assertable offline instead of living in run-body
# code no suite can reach.
function Get-ExtractionCompleteness($outcomes,$plan,$budgetState){
  $inc=[System.Collections.ArrayList]@()
  foreach($o in @($outcomes)){
    if($null -eq $o){ continue }
    $st = [string]$o.outcome
    # 'rejected' on the report path is a refusal of the report's OWN configured range: a real fault,
    # not an expected answer (owner fork 3, 2026-08-04).
    if($st -ne 'incomplete' -and $st -ne 'rejected'){ continue }
    $reason = [string]$o.reason
    if(-not $reason){ $reason = 'budget-exhausted' }
    if($st -eq 'rejected'){ $reason = 'rejected' }
    $row=[ordered]@{ id=$o.id; visual=$o.visual; reason=$reason
                     waitedMs=[int]$o.waitedMs; lastVerdict=$o.lastVerdict; queries=[int]$o.queries }
    if([int]$o.pagesFetched -gt 0){ $row.pagesFetched=[int]$o.pagesFetched }
    if($o.endCursor){ $row.endCursor=[string]$o.endCursor }
    [void]$inc.Add($row)
  }
  $mw = 90; $mt = 420
  if($plan -and $null -ne $plan.maxWaitSec){ $mw = [int]$plan.maxWaitSec }
  $tw = 0; $bx = $false
  if($budgetState){
    if($null -ne $budgetState.maxTotalWaitSec){ $mt = [int]$budgetState.maxTotalWaitSec }
    if($null -ne $budgetState.totalWaitedMs){ $tw = [int]$budgetState.totalWaitedMs }
    if($null -ne $budgetState.budgetExhausted){ $bx = [bool]$budgetState.budgetExhausted }
  }
  return [ordered]@{
    extractionComplete = (@($inc).Count -eq 0)
    incompleteWidgets  = @($inc)     # @()-wrapped: a lone null must never read as one entry
    fetchBudget        = [ordered]@{ maxWaitSec=$mw; maxTotalWaitSec=$mt; totalWaitedMs=$tw; budgetExhausted=$bx }
  }
}
# Whether a trend probe result is admissible evidence about the history ceiling.
function Test-CeilingStillValid($probeResult,$minRun){
  if($null -eq $probeResult){ return $false }
  if([string]$probeResult.state -ne 'has-months'){ return $false }
  return (Test-TrailingContiguous $probeResult.months $minRun)
}
# @($null).Count is 1, so a null edge list would read as ONE row and classify an empty widget as
# 'filled'. Every rowcount in this file goes through here.
function Count-Edges($obj){
  if($null -eq $obj){ return 0 }
  $e = $null
  try { $e = $obj.data.widget.data.edges } catch { return 0 }
  if($null -eq $e){ return 0 }
  return @($e).Count
}
function Get-RunBudgetLeftMs {
  if($null -eq $script:runWaitCapSec){ return 2147483647 }
  $left = ([int]$script:runWaitCapSec * 1000) - [int]$script:totalWaitedMs
  if($left -lt 0){ $left = 0 }
  return [int]$left
}
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
# ANLZ-aUniformLattice-2 S13/D5: the Uniq-Key SEQUENCE a metric or dimension list produces, derived once.
# The per-row loops build the same sequence against a fresh map each row, so this reproduces it exactly
# without touching them. Used ONLY to publish metrics[].cellKey, so a consumer can address rows[].metrics
# by metric id instead of by display name (the duplicate-name wrong-value path). Pure; -DefineOnly testable.
function Get-UniqKeySeq($items){
  $probe=[ordered]@{}; $out=@()
  $arr=@($items)
  for($i=0;$i -lt $arr.Count;$i++){
    $k = Uniq-Key $probe $arr[$i].name $arr[$i].id $i
    $probe[$k]=1
    $out += $k
  }
  # unary comma: `return @(x)` collapses a ONE-element array to a scalar, and the caller then
  # indexes into a string. Same PowerShell trap as ANLZ-aUniformLattice-7.
  return ,@($out)
}
# ANLZ-aUniformLattice-2 D1: pair every pulled widget with ITS OWN fetch outcome and its document
# ordinal. $script:lastFetchOutcome is a single slot holding the LAST widget's record by the time the
# normalize pass runs, and indexing $script:outcomes positionally aligns with $wids only by accident.
# Pairing on the record's own id is the only form that survives a `continue` in the fetch loop.
# A widget with no record gets $null rather than a guess. Pure; -DefineOnly testable.
function Build-WidgetInputs($wids,$fetched,$outcomes){
  $byId=@{}
  foreach($o in @($outcomes)){ if($null -ne $o -and $o.id){ if(-not $byId.ContainsKey([string]$o.id)){ $byId[[string]$o.id]=$o } } }
  $out=@(); $arr=@($wids)
  for($i=0;$i -lt $arr.Count;$i++){
    $w=$arr[$i]; $wid=[string]$w.id
    $obj=$null; if($fetched -and $fetched.ContainsKey($wid)){ $obj=$fetched[$wid] }
    $oc=$null;  if($byId.ContainsKey($wid)){ $oc=$byId[$wid] }
    $out += ,([ordered]@{ wmeta=$w; obj=$obj; outcome=$oc; index=$i })
  }
  return ,@($out)
}
# ANLZ-aUniformLattice-2 D4: a row identity unique WITHIN a widget by construction. Ordinal first,
# because Row-Label's fallback is the shared string '(group)' and a label-only key would collide.
# The separator escape is a literal .Replace, NOT -replace: `-replace '|','/'` reads | as regex
# alternation and injects / between every character (measured).
function Get-RowKey($ordinal,$dimValues){
  $vals=@($dimValues)
  if($vals.Count -eq 0){ return [string]$ordinal }
  $esc=@($vals | ForEach-Object { ([string]$_).Replace('|','/') })
  return ([string]$ordinal + '|' + ($esc -join '|'))
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
$script:baseQ='query($sid:ID!,$dr:DateRange!,$cp:ComparePeriod!,$after:String){widget(id:"__ID__"){id content comparisonFormat visual{id} displayOptions{title} widgetTemplate{id linked} target{value} dateRange manualKpiOptions{value compareValue} source{id name parts{id provider{id name} dataSource{id}}} metrics:fields(socketId:$sid,type:METRIC){edges{node{id name}}} dims:fields(socketId:$sid,type:DIMENSION){edges{node{id name}}} data(first:__N__,after:$after,socketId:$sid,referenceDateRange:$dr,referenceCompareDate:$cp){edges{node}pageInfo{hasNextPage endCursor}}}}'
# Budgeted, verdict-driven fetch. Returns the GraphQL object exactly as before; the per-widget
# outcome record is left in $script:lastFetchOutcome for the caller to collect (probe and discovery
# callers deliberately do NOT collect it - a REJECTED probe is the answer they wanted).
# NOTE the signature: the old attempt-count positional slot is REMOVED, not repurposed, so a
# leftover `Fetch-Widget $w 5` would bind 5 to $dr and fail loudly rather than mean a 5 s budget.
function Fetch-Widget($w, $dr, $cp, $opt){
  if($null -eq $dr){ $dr = $script:dr }   # default = report range (default extraction path unchanged)
  if($null -eq $cp){ $cp = $script:cp }
  $plan = $null; $myMaxWait = $null
  if($opt){
    if($opt.plan){ $plan = $opt.plan }
    if($null -ne $opt.maxWaitSec){ $myMaxWait = $opt.maxWaitSec }
  }
  if($null -eq $plan){ $plan = $script:fetchPlan }
  if($null -eq $plan){ $plan = Get-FetchPlan $myMaxWait }
  if($null -eq $myMaxWait){ $myMaxWait = $plan.maxWaitSec }

  $q = $script:baseQ -replace '__ID__',$w.id -replace '__N__',"$PageSize"
  $needData = $w.visual -notin @('TEXT','PAGE_BREAK')
  $st = [ordered]@{ id=$w.id; visual=$w.visual; outcome='filled'; reason=$null
                    waitedMs=0; lastVerdict=$null; queries=0; pagesFetched=0; endCursor=$null
                    truncated=$false; hasNextPage=$false }

  $runLeft = Get-RunBudgetLeftMs
  if($needData -and $runLeft -le 0){
    $script:budgetExhausted = $true
    $st.outcome='incomplete'; $st.reason='run-budget-exhausted'
    $script:outstandingComputes = $script:outstandingComputes + 1
    $script:lastFetchOutcome = $st
    return $null
  }
  if($needData -and $null -eq $script:socketId){
    if(-not (Reset-Socket)){
      $st.outcome='incomplete'; $st.reason='socket-lost'
      $script:lastFetchOutcome = $st
      return $null
    }
  }
  if($needData){ [void](Drain-Ws $plan) }

  $budgetMs = [int][math]::Min([double]([int]$myMaxWait * 1000), [double]$runLeft)
  $sw=[Diagnostics.Stopwatch]::StartNew()
  $obj=$null; $rows=0; $verdict=$null; $failed=$false; $confirms=0
  $maxConfirms = 1; if($null -ne $plan.emptyConfirms){ $maxConfirms = [int]$plan.emptyConfirms }
  while($true){
    $raw = Invoke-GQL $q @{sid=$script:socketId;dr=$dr;cp=$cp;after=$null}
    $st.queries = $st.queries + 1
    if(Test-FetchFailed $raw){ $failed=$true; $st.reason='transport-failed'; break }
    $obj = $raw | ConvertFrom-Json
    $rows = Count-Edges $obj
    if(-not $needData){ break }
    if($rows -gt 0){ break }
    if($verdict -and $verdict.ToUpperInvariant() -eq 'REJECTED'){ break }
    # "Resolved but empty" is believed only after a further quiet window produces no NEW verdict.
    # Otherwise the frame we acted on may have belonged to the PREVIOUS widget, and this one's own
    # compute is still running - observed live, marking widgets with data as empty.
    if($verdict -and $confirms -ge $maxConfirms){ break }
    $left = $budgetMs - [int]$sw.ElapsedMilliseconds
    if($left -le 0){ break }
    $slice = [int][math]::Min([double]$plan.pollEveryMs,[double]$left)
    $wv = Wait-WidgetVerdict $slice $plan
    $st.waitedMs = $st.waitedMs + [int]$wv.waitedMs
    if($wv.verdict){ $verdict = [string]$wv.verdict; $st.lastVerdict = $verdict }
    elseif($verdict){ $confirms = $confirms + 1 }   # quiet confirm window: nothing new arrived
    if($verdict -and $verdict.ToUpperInvariant() -eq 'REJECTED'){ break }   # never coming; do not re-query
  }
  $sw.Stop()

  if(-not $needData){ $st.outcome='filled'; $st.reason=$null }
  elseif($failed){ $st.outcome='incomplete' }
  else {
    $st.outcome = Get-WidgetOutcome $verdict $rows ($budgetMs - [int]$sw.ElapsedMilliseconds) $script:outstandingComputes
    if($st.outcome -eq 'incomplete' -and -not $st.reason){
      if($verdict -and $script:outstandingComputes -gt 0){ $st.reason='stale-verdict-risk' }
      else { $st.reason='budget-exhausted' }
    }
  }

  # Pagination. A faulted page is NOT a last page: breaking out as if it were would emit 500 of 2000
  # rows as a complete widget, which the closer would certify and the analyzer would total.
  if($needData -and $st.outcome -eq 'filled' -and $obj -and $obj.data.widget -and $rows -gt 0){
    $wd=$obj.data.widget.data
    $all=[System.Collections.ArrayList]@(); $wd.edges | ForEach-Object {[void]$all.Add($_)}
    $pi=$wd.pageInfo; $st.pagesFetched=1; $truncated=$false
    while($pi.hasNextPage){
      $praw = Invoke-GQL $q @{sid=$script:socketId;dr=$dr;cp=$cp;after=$pi.endCursor}
      $st.queries = $st.queries + 1
      if(Test-FetchFailed $praw){ $truncated=$true; break }
      $pg=$null; try { $pg=($praw|ConvertFrom-Json).data.widget.data } catch { $pg=$null }
      if(-not $pg){ $truncated=$true; break }
      $pgEdges = $pg.edges
      if($null -eq $pgEdges -or @($pgEdges).Count -eq 0){ $pi=$pg.pageInfo; break }
      $pg.edges | ForEach-Object {[void]$all.Add($_)}
      $pi=$pg.pageInfo; $st.pagesFetched = $st.pagesFetched + 1
    }
    # ANLZ-aUniformLattice-2 D6: record what the loop OBSERVED, not only what it concluded. `truncated`
    # and the final `hasNextPage` had no carrier before, so widget.pageInfo had to be reconstructed from
    # `reason` -- which cannot distinguish "drained cleanly" from "never paginated".
    $st.truncated=[bool]$truncated; $st.hasNextPage=[bool]$pi.hasNextPage
    if($truncated -or $pi.hasNextPage){
      $st.outcome='incomplete'; $st.reason='partial-pages'; $st.endCursor=[string]$pi.endCursor
    }
    $obj.data.widget.data.edges=$all.ToArray(); $obj.data.widget.data.pageInfo=$pi
  }

  # A widget that ended with NO verdict may still have a compute running server-side. Reconnecting
  # mints a new socketId, which orphans it, so it can never be mis-read as the next widget's answer.
  if($st.outcome -eq 'incomplete'){
    $script:outstandingComputes = $script:outstandingComputes + 1
    [void](Reset-Socket)
  }
  $script:lastFetchOutcome = $st
  return $obj
}
function New-RelDateRange($count,$measure){
  return [pscustomobject]@{ parent=$null; primary=[pscustomobject]@{ count=$count; measure=$measure; type='RELATIVE' }; comparison=$null; baseDate=$null; timeZone=$null }
}

# ===================== field probe (ANLZ-aUniformLattice-2 S14/D9) =====================
# GraphQL introspection is disabled on this endpoint, so the only way to learn whether a field exists
# is to name it and read the error. Each candidate declares EXACTLY the variables its selection uses:
# GraphQL's "all variables used" rule rejects a document that declares an unused one, so a single
# template would fail every probe for the wrong reason.
function Get-FieldProbeCandidates(){
  return @(
    [ordered]@{ field='metrics[].aggregation';   leaf='aggregation';       vars='sid';       sel='metrics:fields(socketId:$sid,type:METRIC){edges{node{aggregation}}}' }
    [ordered]@{ field='widget.dateRange';        leaf='dateRange';         vars='none';      sel='dateRange' }
    [ordered]@{ field='widget.filters';          leaf='filters';           vars='none';      sel='filters' }
    [ordered]@{ field='widget.segments';         leaf='segments';          vars='none';      sel='segments' }
    [ordered]@{ field='dims[].isPartition';      leaf='isPartition';       vars='sid';       sel='dims:fields(socketId:$sid,type:DIMENSION){edges{node{isPartition}}}' }
    [ordered]@{ field='widget.serverRowTotal';   leaf='serverRowTotal';    vars='none';      sel='serverRowTotal' }
    [ordered]@{ field='data.totalCount';         leaf='totalCount';        vars='sid-dr-cp'; sel='data(first:1,socketId:$sid,referenceDateRange:$dr,referenceCompareDate:$cp){totalCount}' }
  )
}
# Trim a backend string to something safe to persist: the extraction document has no scrubber of its
# own, and the probe records a server message verbatim.
function Limit-ProbeDetail($text){
  $t = [string]$text
  if(-not $t){ return $null }
  $t = $t -replace '(?i)swy\.do/shares/[A-Za-z0-9_-]+','[redacted-share-link]'
  $t = $t -replace '(?i)/g/[A-Za-z0-9_-]+/reports/','/g/[redacted]/reports/'
  $t = $t -replace '\s+',' '
  if($t.Length -gt 300){ $t = $t.Substring(0,300) }
  return $t
}
# The probe issues its OWN request rather than going through Invoke-GQL, because Invoke-GQL surfaces no
# status code and its error-body read at the WebException path comes back EMPTY (the stream is already
# drained by the time it is read). Verified live 2026-08-05: every absent field answers 400 with
# GRAPHQL_VALIDATION_FAILED, every present field answers 200 -- so status is the reliable signal and the
# body is the corroborating detail.
function Invoke-ProbeRequest($q,$vars){
  $payload = @{query=$q; variables=$vars} | ConvertTo-Json -Compress -Depth 40
  $out=[ordered]@{ status=0; body='' }
  try {
    $r = Invoke-WebRequest "https://graphql.swydo.com" -Method Post -UseBasicParsing -TimeoutSec $script:httpTimeoutSec `
           -Headers @{authorization="Bearer $script:jwt"; "content-type"="application/json"} -Body $payload
    $out.status=[int]$r.StatusCode; $out.body=[string]$r.Content
  } catch {
    $resp=$null; try { $resp=$_.Exception.Response } catch {}
    if($resp){
      try { $out.status=[int]$resp.StatusCode } catch { $out.status=-1 }
      try {
        $st=$resp.GetResponseStream()
        try { if($st.CanSeek){ $st.Position=0 } } catch {}
        $out.body=(New-Object IO.StreamReader($st)).ReadToEnd()
      } catch { $out.body='' }
    } else { $out.status=-1; $out.body=[string]$_.Exception.Message }
  }
  return $out
}
# Three-state, positive-evidence classification. Inferring "field exists" from the absence of a match
# would record present=$true for every 401, 5xx and rate limit, so both verdicts need their own evidence
# and everything else stays unknown -- the discipline Probe-WidgetMonths applies to an unsettled probe.
function Get-FieldProbeVerdict($status,$body,$leaf){
  $out=[ordered]@{ present='unknown'; detail=$null }
  $st=0; try { $st=[int]$status } catch { $st=0 }
  $o=$null
  try { $o = $body | ConvertFrom-Json } catch { $o=$null }
  $errs=@(); if($o){ try { if($o.errors){ $errs=@($o.errors) } } catch { $errs=@() } }
  if($errs.Count -gt 0){
    $msgs=@($errs | ForEach-Object { [string]$_.message })
    $out.detail=(Limit-ProbeDetail ($msgs -join ' | '))
    $validation=$false
    foreach($e in $errs){ try { if([string]$e.extensions.code -eq 'GRAPHQL_VALIDATION_FAILED'){ $validation=$true } } catch {} }
    $names=$false
    foreach($m in $msgs){ if($m -and $m -match [regex]::Escape([string]$leaf)){ $names=$true; break } }
    # Both signals required: a validation failure that names some OTHER field is not evidence about this one.
    if($validation -and $names){ $out.present=$false }
    return $out
  }
  if($st -eq 200){
    $hasData=$false; try { $hasData = ($null -ne $o -and $null -ne $o.data) } catch { $hasData=$false }
    if($hasData){ $out.present=$true; return $out }
  }
  $out.detail=(Limit-ProbeDetail ('http ' + $st + ' ' + $body))
  return $out
}
# `node` is a LEAF in $script:baseQ (data(...){edges{node}} has no sub-selection), so a row-level field
# can never be probed by GraphQL here -- the error would name `node`, not the candidate. Enumerate the
# deserialized blob's own keys instead. Pure.
function Get-BlobKeyProbe($obj){
  $node=$null
  try {
    $edges=@($obj.data.widget.data.edges)
    foreach($e in $edges){ if($e -and $e.node){ if($e.node.isTotals){ $node=$e.node; break } } }
    if($null -eq $node -and $edges.Count -gt 0){ $node=$edges[0].node }
  } catch { $node=$null }
  if($null -eq $node){ return $null }
  $keys=@(); try { $keys=@($node.PSObject.Properties.Name | Sort-Object) } catch { $keys=@() }
  return [ordered]@{ field='rows[].isTotalOfShownRows'; kind='blob-keys'
                     present=$(if($keys -contains 'isTotalOfShownRows'){$true}else{$false}); observedKeys=@($keys) }
}
# Runs only under -ProbeFields. Each candidate is wrapped individually so one failure cannot void the
# whole probe, and no candidate is retried.
function Invoke-FieldProbe($widgetId,$dr,$cp){
  $out=@()
  foreach($c in @(Get-FieldProbeCandidates)){
    $decl=''; $vars=@{}
    if($c.vars -eq 'sid'){ $decl='($sid:ID!)'; $vars=@{sid=$script:socketId} }
    elseif($c.vars -eq 'sid-dr-cp'){ $decl='($sid:ID!,$dr:DateRange!,$cp:ComparePeriod!)'; $vars=@{sid=$script:socketId;dr=$dr;cp=$cp} }
    $q = 'query' + $decl + '{widget(id:"' + $widgetId + '"){' + $c.sel + '}}'
    $r=$null
    try { $r = Invoke-ProbeRequest $q $vars } catch { $r=[ordered]@{ status=-1; body=[string]$_.Exception.Message } }
    $v = Get-FieldProbeVerdict $r.status $r.body $c.leaf
    $out += ,([ordered]@{ field=[string]$c.field; kind='gql'; present=$v.present; detail=$v.detail })
  }
  return ,@($out)
}

# --- normalize one widget into schema v3 ---
function Normalize-Widget($wmeta,$obj,$outcome,$index){
  $w = $obj.data.widget
  $kind = if($wmeta.visual -eq 'TEXT'){'text'}
          elseif($wmeta.visual -eq 'PAGE_BREAK'){'pageBreak'}
          elseif($w.source){'data'}
          elseif($w.manualKpiOptions){'manualKpi'}
          else{'unknown'}
  # S4: dataSourceId/partId are already fetched at the source.parts selection and were dropped here.
  $providers=@(); if($w.source -and $w.source.parts){ $providers=@($w.source.parts | ForEach-Object { [ordered]@{ id=$_.provider.id; name=$_.provider.name; partId=$_.id; dataSourceId=$(if($_.dataSource){$_.dataSource.id}else{$null}) } }) }
  $out = [ordered]@{
    id=$wmeta.id; visual=$wmeta.visual; kind=$kind
    section=$script:secMap[$wmeta.section]; title=$w.displayOptions.title
    provider=$(if($providers.Count -gt 0){$providers[0].name}else{$null}); providers=$providers
  }
  # S6/D2: defensive -- Test-Extractor seeds $script:secMap by hand, so an unseeded parallel map must
  # not throw under $ErrorActionPreference='Stop'.
  $out.sectionHidden = [bool]$(if($script:secHidden){ $script:secHidden[$wmeta.section] } else { $false })
  # S10/D1: 0 is a valid ordinal, so this is a null test and never a truthiness test.
  if($null -ne $index){ $out.documentIndex = [int]$index }
  # S7: template identity, for detecting the same widget cloned across sections.
  if($w.widgetTemplate){ $out.widgetTemplateId=$w.widgetTemplate.id; $out.widgetTemplateLinked=[bool]$w.widgetTemplate.linked }
  # S15: the per-widget date range. The field probe proved this EXISTS (verified live 2026-08-05), which
  # settles the residual U6:243 / U7 R17 / U9 FP-1 all cite as undetectable-from-schema-v2. `inherited`
  # is the common case: primary.type=='PARENT' means the widget uses the report's own range, so any other
  # value is a genuine per-widget override and a cell built from that widget is NOT period-homogeneous.
  if($w -and $w.PSObject -and $w.PSObject.Properties['dateRange']){
    $wdr=$w.dateRange
    $ptype=$null; try { if($wdr -and $wdr.primary){ $ptype=[string]$wdr.primary.type } } catch { $ptype=$null }
    $out.dateRangeRef=$wdr
    $out.dateRangeInherited=[bool]($ptype -eq 'PARENT')
  }
  # S5/D6: completeness is keyed off FETCH INTENT, not the normalized kind -- a data widget whose fetch
  # returned $null degrades to kind='unknown', and that is exactly the widget whose completeness matters.
  if(($wmeta.visual -ne 'TEXT') -and ($wmeta.visual -ne 'PAGE_BREAK') -and ($null -ne $outcome)){
    $oc=[string]$outcome.outcome
    $out.fetchOutcome=$oc
    $out.fetchReason=$(if($outcome.reason){[string]$outcome.reason}else{$null})
    $out.pagesComplete=[bool](($oc -eq 'filled' -or $oc -eq 'empty-resolved') -and ([string]$outcome.reason -ne 'partial-pages'))
    $out.pageInfo=[ordered]@{ pagesFetched=[int]$outcome.pagesFetched; endCursor=$(if($outcome.endCursor){[string]$outcome.endCursor}else{$null})
                              truncated=[bool]$outcome.truncated; hasNextPage=[bool]$outcome.hasNextPage }
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
    # S1: dimensions[] stays the STRING array, byte-for-byte. Re-keying it to objects would break the
    # anchored day/week/month guard in Get-TimeSeries, the DISC_CROSS_WIDGET dimension signature and the
    # headline's table-total scope string -- none of which the suites would catch.
    $out.dimensions=@($dims|ForEach-Object{ $_.name })
    $out.dimensionRefs=@($dims|ForEach-Object{ [ordered]@{ name=$_.name; id=$_.id } })
    # S2/S3: cellKey is the key the UNTOUCHED row loop below actually writes; providerId is the prefix
    # three analyzer passes re-derive today.
    $mKeys=Get-UniqKeySeq $mets   # already array-wrapped by the callee; re-wrapping would NEST it
    $out.metrics=@(for($mi=0;$mi -lt @($mets).Count;$mi++){
      $src=@($mets)[$mi]
      $m=[ordered]@{name=$src.name; id=$src.id}
      $u=Unit-Of $src.id; if($u){$m.unit=$u}
      $m.cellKey=$mKeys[$mi]
      $m.providerId=(($src.id -split ':')[0])
      $m
    })
    $nd=$dims.Count
    $rows=[System.Collections.ArrayList]@()
    $rowOrd=0
    foreach($e in $w.data.edges){
      $node=$e.node
      $rk=if($node.isTotals){'total'}elseif($node.isSubtotals){'subtotal'}else{'data'}
      $dmap=[ordered]@{}
      for($i=0;$i -lt $nd;$i++){ $k=Uniq-Key $dmap $dims[$i].name $dims[$i].id $i; $dmap[$k]=(DimName $node.cells[$i]) }
      $mmap=[ordered]@{}
      for($j=0;$j -lt $mets.Count;$j++){ $k=Uniq-Key $mmap $mets[$j].name $mets[$j].id $j; $cur=$node.cells[$nd+$j]; $cmp=if($node.compareCells){$node.compareCells[$nd+$j]}else{$null}; $mmap[$k]=[ordered]@{current=$cur;compare=$cmp} }
      # S11: rowKey is APPENDED; kind/dimensions/metrics keep their construction and their order.
      [void]$rows.Add([ordered]@{ kind=$rk; dimensions=$dmap; metrics=$mmap; rowKey=(Get-RowKey $rowOrd @($dmap.Values)) })
      $rowOrd=$rowOrd+1
    }
    $out.rows=$rows
    # S8: what an aggregation may legally take from this widget, declared instead of re-derived.
    $kc=[ordered]@{ data=0; subtotal=0; total=0 }
    foreach($r in $rows){ $kk=[string]$r.kind; if($kc.Contains($kk)){ $kc[$kk]=[int]$kc[$kk]+1 } }
    $out.hasTotalRow=[bool]([int]$kc['total'] -gt 0)
    $out.rowKindCounts=$kc
    # S9/D7: the first-wins $cc loop above is untouched. This is a SEPARATE encounter-order pass, with a
    # -notcontains dedupe rather than Sort-Object -Unique, so the array cannot reorder into something
    # that looks like a different first-wins answer.
    $ccAll=@()
    foreach($e in $w.data.edges){ if($e.node.meta -and $e.node.meta.currencyCode){ $c1=[string]$e.node.meta.currencyCode; if($ccAll -notcontains $c1){ $ccAll += $c1 } } }
    $out.currencyCodes=@($ccAll)
    $out.currencyBasis=$(if(@($ccAll).Count -gt 0){'row-meta'}else{'absent'})
  }
  $out.raw = $w    # null-safe: $w may be null on an error response
  return $out
}

# ===================== provider filter (--platform) pure helpers =====================
# Normalize a -Platform value (repeated and/or comma-lists) to a lowercased provider-id set.
function Parse-PlatformFilter($platform){
  $out=@(); foreach($x in @($platform)){ foreach($t in ([string]$x -split ',')){ $t=$t.Trim().ToLower(); if($t){ $out += $t } } }
  # ANLZ-aUniformLattice-7: the unary comma is load-bearing. `return @()` collapses to $null at the call
  # site, ConvertTo-Json then renders that $null as `{}` rather than `[]`, ConvertFrom-Json turns it back
  # into an empty PSCustomObject, and a truthiness test counts that object as ONE filter entry -- which
  # made every UNFILTERED report emit a false, force-surfaced PROVIDER_FILTERED major claiming the report
  # excluded every platform. Verified live 2026-08-05.
  return ,@(@($out) | Sort-Object -Unique)
}
# Keep-if-ANY: a widget is kept when any of its provider ids is wanted (whole widget; never split a blended widget).
function Test-ProviderMatch($widgetProviderIds,$wanted){
  if(@($wanted).Count -eq 0){ return $true }   # no filter => keep everything
  foreach($p in @($widgetProviderIds)){ if(([string]$p).ToLower() -in $wanted){ return $true } }
  return $false
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
function Get-TrendMonthCells($obj,$outcome){
  $out=[ordered]@{ windowStatus='ok'; metricIds=@(); months=@() }
  $w=$null; try { $w=$obj.data.widget } catch {}
  if(-not $w){
    # An unanswered window is NOT an overshoot. Recording it as one is how a slow response became a
    # false history ceiling and silently truncated a client's trend.
    if($outcome -and [string]$outcome.outcome -eq 'incomplete'){ $out.windowStatus='unsettled'; return $out }
    $out.windowStatus='error'; return $out
  }
  $mets=@(); if($w.metrics -and $w.metrics.edges){ $mets=@($w.metrics.edges | ForEach-Object { $_.node }) }
  $dims=@(); if($w.dims -and $w.dims.edges){ $dims=@($w.dims.edges | ForEach-Object { $_.node }) }
  $out.metricIds=@($mets | ForEach-Object { [string]$_.id })
  $nd=$dims.Count
  $edges=@(); if($w.data -and $w.data.edges){ $edges=@($w.data.edges) }
  if($edges.Count -eq 0){
    if($outcome -and [string]$outcome.outcome -eq 'incomplete'){ $out.windowStatus='unsettled'; return $out }
    $out.windowStatus='overshoot-empty'; return $out
  }
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
# Four-state probe result. 'rejected' is Swydo explicitly refusing the window (measured 44-260 ms) and
# is the ONLY definitive overshoot signal; 'unsettled' means no answer at all and must never be read
# as one.
function Probe-WidgetMonths($w,$n){
  $popt = $script:probeOpt
  if($null -eq $popt){ $popt = $script:fetchOpt }
  $o = Fetch-Widget $w (New-RelDateRange (-1*$n) 'month') $null $popt
  $rec = $script:lastFetchOutcome
  $months = @()
  if($o){ $months = @((Get-TrendMonthCells $o $rec).months | ForEach-Object { $_.month }) }
  $state = 'unsettled'
  if(@($months).Count -gt 0){ $state = 'has-months' }
  elseif($rec -and [string]$rec.outcome -eq 'rejected'){ $state = 'rejected' }
  elseif($rec -and [string]$rec.outcome -eq 'empty-resolved'){ $state = 'empty-resolved' }
  return [ordered]@{ state=$state; months=@($months) }
}
# Retry an unsettled window ONCE before believing it: the silent band is transient. Measured on the
# QCU Facebook widget, a 37-month window stayed silent for 30 s and then returned REJECTED in 49 ms
# on the very next attempt. A window still unsettled after the retry is treated as overshoot - the
# conservative direction, since claiming history you cannot prove is the worse error - and marks the
# resulting ceiling as a lower bound rather than a measurement.
function Get-CeilingProbe($w,$n){
  $r = Probe-WidgetMonths $w $n
  $unc = $false
  if([string]$r.state -eq 'unsettled'){
    $plan = $script:fetchPlan
    if($null -eq $plan){ $plan = Get-FetchPlan $null }
    if($plan.retryUnsettledOnce){ $r = Probe-WidgetMonths $w $n }
    if([string]$r.state -eq 'unsettled'){ $unc = $true }
  }
  return @{ result=$r; uncertain=$unc }
}
# Per-widget ceiling: lazily probe the ladder descending (stop at first rung with >=2 trailing-contiguous
# months = R, prior empty = F), then bisect (R,F) to the true max N. Returns months (0 = no monthly history).
# Sets $script:lastCeilingUncertain when any rung stayed unanswered, so coverage can say so.
function Get-WidgetCeiling($w){
  $R=$null; $F=$null; $unc=$false
  foreach($n in $script:TrendLadder){
    $pr = Get-CeilingProbe $w $n
    if($pr.uncertain){ $unc=$true }
    if(Test-CeilingStillValid $pr.result 2){ $R=$n; break } else { $F=$n }
  }
  if($null -eq $R){ $script:lastCeilingUncertain=$unc; return 0 }
  while($true){
    $mid = Get-NextBisectN $R $F
    if($null -eq $mid){ break }
    $pr = Get-CeilingProbe $w $mid
    if($pr.uncertain){ $unc=$true }
    if(Test-CeilingStillValid $pr.result 2){ $R=$mid } else { $F=$mid }
  }
  $script:lastCeilingUncertain=$unc
  return $R
}

# U8: resolve the report's RELATIVE date range to a concrete calendar span at extraction time.
# Accepted domain (live-verified family ONLY): type RELATIVE, count -1, measure month|quarter|year
# => the single complete calendar <measure> immediately BEFORE the anchor's current one (the
# Derive-Periods rule, verified live on the QCU quarter report). Anything else => primary=$null
# plus a note: an honest non-answer, never a guessed span (a wrong span could later feed U7b's
# only major). Pure; $anchor is a [datetime]; date-only arithmetic; InvariantCulture formatting.
# count cast is [double] NOT [int]: PS 5.1 [int] banker's-rounds -0.6/-1.4 to -1, which would
# resolve a fractional hand-edited count to a complete span (violates D1). [double] keeps -1 exact.
# EXTR-aUniformLattice-1 (D3): the window immediately preceding a primary, same length. Pure date
# arithmetic on .Date values, InvariantCulture on every boundary -- PS 5.1 parsing and formatting are
# culture-sensitive, so a de-DE host must produce byte-identical strings.
function Get-PreviousWindow($start,$end){
  $inv=[Globalization.CultureInfo]::InvariantCulture
  $s=$null; $e=$null
  try { $s=[datetime]::ParseExact([string]$start,'yyyy-MM-dd',$inv).Date } catch { return $null }
  try { $e=[datetime]::ParseExact([string]$end,'yyyy-MM-dd',$inv).Date } catch { return $null }
  if($e -lt $s){ return $null }
  $len = ($e - $s).Days + 1
  $prevEnd = $s.AddDays(-1)
  $prevStart = $prevEnd.AddDays(-1*($len-1))
  return [ordered]@{ start=$prevStart.ToString('yyyy-MM-dd',$inv); end=$prevEnd.ToString('yyyy-MM-dd',$inv); lengthDays=$len }
}
# EXTR-aUniformLattice-1 (D3b): FROM is only PROVEN to mean what we need when the compare window is
# ADJACENT to the primary (prevEnd + 1 day == primaryStart). On that domain "same length from this
# date" and "runs to the primary start" coincide, so both readings are safe. Refuse anything else
# rather than silently leaving the measured region.
function New-ComparePeriodFrom($startDate,$primaryStart){
  $inv=[Globalization.CultureInfo]::InvariantCulture
  $ps=$null; $st=$null
  try { $st=[datetime]::ParseExact([string]$startDate,'yyyy-MM-dd',$inv).Date } catch { throw "New-ComparePeriodFrom: unparseable start '$startDate'" }
  try { $ps=[datetime]::ParseExact([string]$primaryStart,'yyyy-MM-dd',$inv).Date } catch { throw "New-ComparePeriodFrom: unparseable primaryStart '$primaryStart'" }
  if($st -ge $ps){ throw "New-ComparePeriodFrom: compare start '$startDate' is not before primary start '$primaryStart'" }
  return [pscustomobject]@{ parentComparePeriod=$null; comparePeriod=[pscustomobject]@{ start=$st.ToString('yyyy-MM-dd',$inv); type='FROM' } }
}
# Are two compare specs the same window? Only a FROM-with-the-same-start is provably equivalent to
# ours; every other shape (a PERIOD enum, a different FROM) is a divergence worth disclosing.
function Test-SameComparePeriod($saved,$computed){
  if($null -eq $saved -or $null -eq $computed){ return $false }
  $a=$null; $b=$null
  try { $a=$saved.comparePeriod } catch { $a=$null }
  try { $b=$computed.comparePeriod } catch { $b=$null }
  if($null -eq $a -or $null -eq $b){ return $false }
  if([string]$a.type -ne 'FROM' -or [string]$b.type -ne 'FROM'){ return $false }
  return ([string]$a.start -eq [string]$b.start)
}
# First numeric cell of a widget's total row -- the smallest stable signal for "did these two date
# specs return the same data". Pure; null when the widget gave nothing usable.
function Get-ProbeCurrentValue($obj){
  if($null -eq $obj){ return $null }
  $edges=@()
  try { $edges=@($obj.data.widget.data.edges) } catch { return $null }
  if($edges.Count -eq 0){ return $null }
  $node=$null
  foreach($e in $edges){ if($e -and $e.node -and $e.node.isTotals){ $node=$e.node; break } }
  if($null -eq $node){ $node=$edges[0].node }
  if($null -eq $node){ return $null }
  $cells=@($node.cells)
  foreach($c in $cells){ if($c -is [double] -or $c -is [int] -or $c -is [long] -or $c -is [decimal]){ return [string]$c } }
  return $null
}
function Resolve-ReportPeriod($dateRange,$anchor){
  $inv=[Globalization.CultureInfo]::InvariantCulture
  # resolverVersion 2 (EXTR-aUniformLattice-1 D4): the accepted domain CHANGED -- STATIC is now
  # resolved (its dates were always given; calling that "unresolved" is what let a static report ship
  # with periodConfidence unconfirmed) and month/-1 is admitted after a live probe proved Swydo's
  # month/-1 is the last COMPLETE month. Leaving the marker at 1 would be a silent algorithm change.
  $out=[ordered]@{ resolverVersion=2; rule='relative-last-complete'
                   anchorDate=(([datetime]$anchor).Date).ToString('yyyy-MM-dd',$inv); primary=$null }
  $p=$null; if($dateRange){ $p=$dateRange.primary }
  if($null -eq $p){ $out.note='unresolved: no primary date range'; return $out }
  if([string]$p.type -eq 'STATIC'){
    $sd=$null; $ed=$null
    try { $sd=[datetime]::ParseExact([string]$p.start,'yyyy-MM-dd',$inv).Date } catch { $sd=$null }
    try { $ed=[datetime]::ParseExact([string]$p.end,'yyyy-MM-dd',$inv).Date } catch { $ed=$null }
    if($null -eq $sd -or $null -eq $ed -or $ed -lt $sd){ $out.note='unresolved: STATIC range unparseable'; return $out }
    $out.rule='static'
    $out.primary=[ordered]@{
      measure='static'; count=0
      startDate=$sd.ToString('yyyy-MM-dd',$inv); endDate=$ed.ToString('yyyy-MM-dd',$inv)
      startYm=$sd.ToString('yyyy-MM',$inv);      endYm=$ed.ToString('yyyy-MM',$inv)
      calendarAligned=(($sd.Day -eq 1) -and ($ed.AddDays(1).Day -eq 1))
    }
    return $out
  }
  if([string]$p.type -ne 'RELATIVE'){ $out.note=('unresolved: type ''' + [string]$p.type + ''''); return $out }
  $n=$null; try{ $n=[double]$p.count }catch{}
  if($n -ne -1){ $out.note=('unresolved: count ''' + [string]$p.count + ''' (only -1 verified)'); return $out }
  $meas=([string]$p.measure).ToLowerInvariant()
  # UNATTENDED DOMAIN (amendment, fatigue must-fix): accepted measure SHRINKS to 'quarter' only.
  # quarter/-1 is the sole live-verified pair; month/-1 and year/-1 cannot be resolved unattended
  # (the last-complete-vs-current-partial semantic needs a credentialed live probe) so they resolve
  # to the null triple. The arithmetic below stays measure-general for the post-probe widening.
  # 'month' admitted by EXTR-aUniformLattice-1 D4: the credentialed live probe U8 asked for has now
  # run. RELATIVE {count:-1, measure:month} and STATIC 2026-07-01..2026-07-31 returned identical
  # values (Clicks current 2591, compare 5277), so Swydo's month/-1 IS the last complete month.
  if(@('quarter','month') -notcontains $meas){ $out.note=('unresolved: measure ''' + [string]$p.measure + ''' (verified domain: quarter/-1, month/-1)'); return $out }
  $a=([datetime]$anchor).Date
  $curStart=New-Object DateTime($a.Year,$a.Month,1); $span=1
  if($meas -eq 'quarter'){ $qm=((([int][math]::Floor(($a.Month-1)/3))*3)+1); $curStart=New-Object DateTime($a.Year,$qm,1); $span=3 }
  elseif($meas -eq 'year'){ $curStart=New-Object DateTime($a.Year,1,1); $span=12 }
  $startDate=$curStart.AddMonths(-1*$span)
  $endDate=$curStart.AddDays(-1)
  $out.primary=[ordered]@{
    measure=$meas; count=-1
    startDate=$startDate.ToString('yyyy-MM-dd',$inv); endDate=$endDate.ToString('yyyy-MM-dd',$inv)
    startYm=$startDate.ToString('yyyy-MM',$inv);      endYm=$endDate.ToString('yyyy-MM',$inv)
    calendarAligned=(($startDate.Day -eq 1) -and ($endDate.AddDays(1).Day -eq 1))
  }
  return $out
}

if($DefineOnly){ return }   # dot-source stops here (functions loaded, nothing run)

# ================================ run ================================
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
if(-not $ShareUrl){ throw "ShareUrl is required" }
Reset-FetchState
$script:fetchPlan       = Get-FetchPlan $MaxWaitSec
$script:runWaitCapSec = $MaxTotalWaitSec
$script:fetchOpt        = @{ plan=$script:fetchPlan; maxWaitSec=$MaxWaitSec }
$script:probeOpt        = @{ plan=$script:fetchPlan; maxWaitSec=$script:fetchPlan.probeMaxWaitSec }
$script:outcomes        = [System.Collections.ArrayList]@()

# 1. resolve share key + report id
$html = Invoke-RestMethod -Uri $ShareUrl -TimeoutSec $script:httpTimeoutSec
if ($html -match 'app\.swydo\.com/g/([^/]+)/reports/([A-Za-z0-9_-]+)') { $script:key=$Matches[1]; $reportId=$Matches[2] }
else { throw "Could not find the 'app.swydo.com/g/<key>/reports/<id>' iframe in the share page (bad/expired link, or password required?)" }   # never interpolate $ShareUrl - it carries the share key
Write-Host ("key=***  reportId={0}" -f $reportId)   # never echo the raw share key (it is the Basic-auth credential)

# 2. JWT
$script:jwt = Mint-Jwt; $script:jwtAt = Get-Date

# 3. websocket
if(-not (Connect-Ws)){ throw "no socketId from wss://ws.swydo.com" }
Write-Host "socketId=$script:socketId"

# 4. structure
$structQ='query($id:ID!){report(id:$id){id name subtitle orientation custom client{id name} author{id name email} dateRange compareDateRange sections{id name isHidden} widgets{edges{node{id visual{id} section{id} source{id parts{provider{id name}}}}}} teamName}}'
$structRaw = Invoke-GQL $structQ @{id=$reportId} -NoRetry
$s = ($structRaw | ConvertFrom-Json).data.report
if(-not $s){ throw "structure query returned no report: $structRaw" }
$script:dr=$s.dateRange; $script:cp=$s.compareDateRange
$script:drResolved = Resolve-ReportPeriod $s.dateRange (Get-Date)   # U8: anchor = structure-fetch moment
# EXTR-aUniformLattice-1: compute OUR OWN compare window and pass it explicitly at the report fetch
# site. $script:cp deliberately KEEPS the report's saved spec, because Probe-WidgetMonths, trend
# discovery, the trend pull and the field probe all pass $null and INHERIT it -- mutating it here
# would silently change every trend fetch, and the trend path reads a rejected fetch as proof that
# history does not exist.
$script:reportCp   = $null                       # the computed compare, or $null if we could not build one
$script:compareBasis = 'untrusted'               # fail closed by default; earned, not assumed
$script:periodResolved = $null
$rp = $script:drResolved.primary
if($rp -and $rp.startDate -and $rp.endDate){
  $prevWin = Get-PreviousWindow $rp.startDate $rp.endDate
  if($prevWin){
    try {
      $script:reportCp = New-ComparePeriodFrom $prevWin.start $rp.startDate
      $script:compareBasis = 'computed'
      $script:periodResolved = [ordered]@{
        current  = [ordered]@{ start=[string]$rp.startDate; end=[string]$rp.endDate }
        previous = [ordered]@{ start=[string]$prevWin.start; end=[string]$prevWin.end }
        lengthDays = [int]$prevWin.lengthDays
        basis = 'previous-period'
        anchorDate = [string]$script:drResolved.anchorDate
      }
    } catch { $script:reportCp = $null; $script:compareBasis = 'untrusted' }
  }
}
if($script:compareBasis -eq 'untrusted'){
  $note = 'unresolved'
  if($script:drResolved.note){ $note = [string]$script:drResolved.note }
  $warnCompare = "period NOT proven ($note): the previous-period column comes from the report's own saved compare setting, which this tool cannot verify. Comparisons are suppressed downstream."
} else {
  $warnCompare = $null
}
if($script:drResolved.primary){ Write-Host ("period resolved: {0}..{1}" -f $script:drResolved.primary.startYm, $script:drResolved.primary.endYm) }
$script:secMap=@{}; if($s.sections){ $s.sections | ForEach-Object { $script:secMap[$_.id]=$_.name } }
# S6: isHidden was already requested by the structure query and discarded here. Parallel map rather than
# a richer secMap value, because secMap's value is read as a NAME at the normalize site.
$script:secHidden=@{}; if($s.sections){ $s.sections | ForEach-Object { $script:secHidden[$_.id]=[bool]$_.isHidden } }
# full provider inventory (from the UNFILTERED structure) so downstream always knows what exists,
# even when --platform pulls a subset (additive-in-facts; a filtered report can't look complete).
$providerInventory = @($s.widgets.edges | ForEach-Object { @($_.node.source.parts | ForEach-Object { $_.provider.id }) } | Where-Object { $_ } | Sort-Object -Unique)
$platFilter = Parse-PlatformFilter $Platform
$widsAll = @($s.widgets.edges | ForEach-Object { $n=$_.node; @{ id=$n.id; visual=$n.visual.id; section=$n.section.id; provs=@($n.source.parts | ForEach-Object { $_.provider.id } | Where-Object { $_ }) } })
if($platFilter.Count -gt 0){ $wids = @($widsAll | Where-Object { ($_.visual -in @('TEXT','PAGE_BREAK')) -or (Test-ProviderMatch $_.provs $platFilter) }) } else { $wids = $widsAll }
Write-Host ("report: {0} | widgets: {1}{2}" -f $s.name, $wids.Count, $(if($platFilter.Count -gt 0){ " (filtered to: " + ($platFilter -join ',') + ")" }else{""}))

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
    if($platFilter.Count -gt 0 -and -not (Test-ProviderMatch @($prov) $platFilter)){ continue }   # --platform filter
    $twids += @{ id=$n.id; visual=$n.visual.id; prov=$prov; pname=$pname }
  }
  # discovery: one fetch each at month/-12 (safe, dims return regardless of data rows) -> classify time widgets
  Write-Host ("trend: discovering monthly time-series widgets among {0} data widgets..." -f $twids.Count)
  $trendW=@()
  foreach($w in $twids){
    $o=Fetch-Widget $w (New-RelDateRange -12 'month') $null $script:probeOpt
    $dims=@(); try{ $dims=@($o.data.widget.dims.edges.node.name) }catch{}
    if((@($dims).Count -eq 1) -and (Test-TrendTimeWidget $dims)){ $trendW += $w; Write-Host ("  TIME {0} [{1}] prov={2} dim='{3}'" -f $w.id,$w.visual,$w.prov,($dims -join ',')) }
  }
  if($trendW.Count -eq 0){ throw "no single-month-dimension widget found; this report has no monthly time series to accumulate" }

  $curMonth = Get-CurrentMonthKey $now
  $cells=[System.Collections.ArrayList]@()
  $cov=[ordered]@{}
  $newCache=@{}
  foreach($w in $trendW){
    $ceiling=$null; $script:lastCeilingUncertain=$false; $keptStamp=$null
    $ce=$cache[$w.id]
    # probeVersion gate: a ceiling discovered by the pre-EXTR-aPatientHarvest-1 prober inferred
    # overshoot from emptiness, so it may be false. Ignore those exactly once and re-derive.
    $ceUsable = $false
    if($ce -and $null -ne $ce.probeVersion){ try { $ceUsable = ([int]$ce.probeVersion -ge 2) } catch { $ceUsable = $false } }
    if($ceUsable -and (Test-CeilingFresh $ce.discoveredAt $now 30)){
      # The revalidation caller has a safe fallback the bisect does not: an unsettled probe simply
      # means "cache not validated", so it falls through to a full probe instead of erroring.
      if(Test-CeilingStillValid (Probe-WidgetMonths $w ([int]$ce.ceilingMonths)) 2){
        $ceiling=[int]$ce.ceilingMonths
        $keptStamp=[string]$ce.discoveredAt   # a HIT must not re-stamp, or the 30-day TTL never expires
      }
    }
    if($null -eq $ceiling){ $ceiling = Get-WidgetCeiling $w }
    if($ceiling -le 0){ Write-Host ("  {0}: no monthly history (ceiling 0)" -f $w.id); continue }
    $stamp = $keptStamp
    if(-not $stamp){ $stamp = ([datetimeoffset]$now).ToString('o') }
    $newCache[$w.id]=@{ ceilingMonths=$ceiling; discoveredAt=$stamp; probeVersion=2 }
    $tfo = Fetch-Widget $w (New-RelDateRange (-1*$ceiling) 'month') $null $script:fetchOpt
    $trec = $script:lastFetchOutcome
    if($trec){ [void]$script:outcomes.Add($trec) }
    $mc = Get-TrendMonthCells $tfo $trec
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
    if(-not $cov.Contains($pk)){ $cov[$pk]=[ordered]@{ providerId=$pk; providerName=$w.pname; hasMonthlyGrain=$true; ceilingMonths=$ceiling; ceilingUncertain=[bool]$script:lastCeilingUncertain; probeLadderHit=$false; earliestMonth=$null; latestMonth=$null; windowStatus=$mc.windowStatus; probedAt=([datetimeoffset]$now).ToString('o') } }
    else {
      if($ceiling -gt $cov[$pk].ceilingMonths){ $cov[$pk].ceilingMonths=$ceiling }
      if($script:lastCeilingUncertain){ $cov[$pk].ceilingUncertain=$true }
    }
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
  $uncertain=@($cov.Values | Where-Object { $_.ceilingUncertain } | ForEach-Object { $_.providerId })
  if($uncertain.Count -gt 0){ $twarn += ("history ceiling is a LOWER BOUND for provider(s): " + ($uncertain -join ', ') + " -- a probe window went unanswered twice, so more history may exist than was pulled") }
  $tcompleteness = Get-ExtractionCompleteness $script:outcomes $script:fetchPlan `
                     @{ maxTotalWaitSec=$MaxTotalWaitSec; totalWaitedMs=$script:totalWaitedMs; budgetExhausted=$script:budgetExhausted }
  $tdoc=[ordered]@{
    meta=[ordered]@{
      tool='Get-SwydoReport.ps1'; schemaVersion=3; trend=$true; extractedAt=(Get-Date).ToString('o')
      shareUrl=$ShareUrl; shareKey=$script:key; reportId=$reportId; clientId=$s.client.id
      trendWidgets=$trendW.Count; cellCount=$cells.Count; coverage=@($cov.Values); warnings=$twarn
      providerInventory=$providerInventory; providerFilter=$platFilter
      extractionComplete=$tcompleteness.extractionComplete; incompleteWidgets=@($tcompleteness.incompleteWidgets)
      fetchBudget=$tcompleteness.fetchBudget
    }
    report=[ordered]@{ name=$s.name; client=$s.client.name; clientId=$s.client.id; author=[ordered]@{name=$s.author.name;email=$s.author.email}; team=$s.teamName }
    trendCells=@($cells)
  }
  $tpath=Join-Path $OutDir "$tstamp-$tslug.trend.json"
  [IO.File]::WriteAllText($tpath, ($tdoc | ConvertTo-Json -Depth 100), (New-Object Text.UTF8Encoding($false)))
  try{ $script:ws.Dispose() }catch{}
  Write-Host ("trend done -> {0}  ({1} cells across {2} providers{3})" -f $tpath, $cells.Count, @($cov.Values|Where-Object{$_.hasMonthlyGrain}).Count, $(if($twarn){", "+$twarn.Count+" warning(s)"}else{""}))
  return
}

# EXTR-aUniformLattice-1 D6: when the primary is RELATIVE, our resolved STATIC window is an ASSERTION
# about Swydo's anchor and timezone. Prove it before trusting it: fetch one data widget both ways and
# compare the current value. A mismatch means our anchor disagrees with theirs, so the compare window
# we computed is wrong -- fail closed rather than ship a delta against it.
if($script:compareBasis -eq 'computed' -and ([string]$s.dateRange.primary.type -eq 'RELATIVE')){
  $pw = @($wids | Where-Object { $_.visual -notin @('TEXT','PAGE_BREAK') })
  if(@($pw).Count -gt 0){
    $pw0 = @($pw)[0]
    $drStatic = [pscustomobject]@{ parent=$null
      primary=[pscustomobject]@{ start=[string]$script:periodResolved.current.start; end=[string]$script:periodResolved.current.end; type='STATIC' }
      comparison=$null; baseDate=$null; timeZone=$null }
    $vSaved  = Get-ProbeCurrentValue (Fetch-Widget $pw0 $script:dr $script:reportCp $script:probeOpt)
    $vStatic = Get-ProbeCurrentValue (Fetch-Widget $pw0 $drStatic $script:reportCp $script:probeOpt)
    if($null -eq $vSaved -or $null -eq $vStatic -or ([string]$vSaved -ne [string]$vStatic)){
      $script:compareBasis = 'untrusted'
      $warnCompare = "period NOT proven: the report's relative range and our resolved window " + [string]$script:periodResolved.current.start + ".." + [string]$script:periodResolved.current.end + " returned different values (probe widget " + [string]$pw0.id + ": '" + [string]$vSaved + "' vs '" + [string]$vStatic + "'), so our anchor disagrees with Swydo's. Comparisons are suppressed downstream."
      Write-Host ("period probe MISMATCH -> compareBasis=untrusted")
    } else {
      Write-Host ("period probe OK: relative and resolved static agree (" + [string]$vStatic + ")")
    }
  }
}

# 5. fetch all. The old reconcile loop is GONE: its job (wait, then ask again) now lives inside
# Fetch-Widget's verdict wait, where it is bounded and where the outcome is recorded exactly once.
# A second pass could otherwise overwrite a settled outcome and make publish depend on round timing.
$fetched=@{}; $empty=@()
try {
  foreach($w in $wids){
    # EXTR-aUniformLattice-1: explicit compare. $null would INHERIT $script:cp (the saved spec), which
    # is the defect this unit exists to remove. When we could not build one, we fall back to the saved
    # spec because ComparePeriod! is required -- and compareBasis='untrusted' makes the analyzer
    # suppress every comparative field.
    $cpForFetch = $script:reportCp
    if($null -eq $cpForFetch){ $cpForFetch = $script:cp }
    $o = Fetch-Widget $w $null $cpForFetch $script:fetchOpt
    $fetched[$w.id]=$o
    $rec = $script:lastFetchOutcome
    if($rec){ [void]$script:outcomes.Add($rec) }
    $n = Count-Edges $o
    $tag = if($n -gt 0){"DATA"} elseif($o -and $o.data.widget.content){"TEXT"} else {"none"}
    $oc = 'filled'; if($rec){ $oc = [string]$rec.outcome }
    $extra = ''
    if($oc -ne 'filled'){
      $extra = (" {0}" -f $oc)
      if($rec -and $rec.reason){ $extra = $extra + (" ({0})" -f $rec.reason) }
      if($rec -and $rec.lastVerdict){ $extra = $extra + (" verdict={0}" -f $rec.lastVerdict) }
    }
    Write-Host ("  {0,-4} {1} [{2}] rows={3}{4}" -f $tag,$w.id,$w.visual,$n,$extra)
    if($n -eq 0 -and $w.visual -notin @('TEXT','PAGE_BREAK')){ $empty += $w }
  }
} finally { try{ $script:ws.Dispose() }catch{} }
$completeness = Get-ExtractionCompleteness $script:outcomes $script:fetchPlan `
                  @{ maxTotalWaitSec=$MaxTotalWaitSec; totalWaitedMs=$script:totalWaitedMs; budgetExhausted=$script:budgetExhausted }

# 6. normalize + assemble
# D1: pair each widget with ITS OWN outcome by id. Reading $script:lastFetchOutcome here would stamp
# every widget with the LAST widget's completeness -- a fabricated completeness proof.
$widgetInputs = Build-WidgetInputs $wids $fetched $script:outcomes
$widgetsOut = @(foreach($wi in $widgetInputs){ Normalize-Widget $wi.wmeta $wi.obj $wi.outcome $wi.index })

# S14/D9: opt-in only. Runs after the fetch loop, so a probe error cannot disturb a live data socket.
$fieldProbe = $null
if($ProbeFields){
  try {
    $probeW = @($widgetsOut | Where-Object { $_.kind -eq 'data' })
    if(@($probeW).Count -gt 0){
      $pid0 = [string]@($probeW)[0].id
      Write-Host ("field probe: {0} candidate(s) against widget {1}" -f @(Get-FieldProbeCandidates).Count, $pid0)
      $fp = Invoke-FieldProbe $pid0 $script:dr $script:cp
      $bk = Get-BlobKeyProbe $fetched[$pid0]
      if($bk){ $fp += ,$bk }
      $fieldProbe = @($fp)
      foreach($r in $fieldProbe){ Write-Host ("  {0,-28} present={1}" -f $r.field, $r.present) }
    }
  } catch { Write-Host ("field probe skipped: " + $_.Exception.Message) }
}
$warnings=@(); if($empty.Count -gt 0){ $warnings += ("no rows returned for: " + (($empty|ForEach-Object{$_.id}) -join ', ')) }
$unitBasis = @('google-adwords','facebook-ads')
$provIds = @(); foreach($wd in $widgetsOut){ if($wd.kind -eq 'data' -and $wd.metrics){ foreach($m in $wd.metrics){ $provIds += (($m.id -split ':')[0]) } } }
$provIds = @($provIds | Sort-Object -Unique)
# EXTR-aUniformLattice-1 D7: disclose when the report's own compare setting is not the window we used.
if($warnCompare){ $warnings += $warnCompare }
elseif(-not (Test-SameComparePeriod $s.compareDateRange $script:reportCp)){
  # Client-READABLE: this becomes a force-surfaced GAP_WARNINGS finding, so it must name the windows
  # in plain language rather than dumping the raw spec. The saved shape is still in
  # meta.savedComparePeriod for an operator who needs it.
  $savedDesc = 'a different setting'
  try {
    $scp = $s.compareDateRange.comparePeriod
    if([string]$scp.type -eq 'DISABLED'){ $savedDesc = 'comparison turned off' }
    elseif([string]$scp.type -eq 'PERIOD' -and $scp.period){ $savedDesc = ("'" + [string]$scp.period + "'") }
    elseif([string]$scp.type -eq 'FROM' -and $scp.start){ $savedDesc = ('a window starting ' + [string]$scp.start) }
  } catch {}
  $warnings += ("comparison basis: this report compares " + [string]$script:periodResolved.current.start + " to " + [string]$script:periodResolved.current.end + " against the preceding " + [string]$script:periodResolved.previous.start + " to " + [string]$script:periodResolved.previous.end + ". The dashboard itself is set to " + $savedDesc + ", so figures here may not match a like-for-like view on screen.")
}
$unverified = @($provIds | Where-Object { $_ -notin $unitBasis })
if($unverified.Count -gt 0){ $warnings += ("units not inferred for unverified provider(s): " + ($unverified -join ', ') + " -- values are raw; confirm scale/currency downstream") }

$doc = [ordered]@{
  meta = [ordered]@{
    tool='Get-SwydoReport.ps1'; schemaVersion=3; extractedAt=(Get-Date).ToString('o')
    shareUrl=$ShareUrl; shareKey=$script:key; reportId=$reportId; clientId=$s.client.id
    widgetCount=$wids.Count; dataWidgets=@($widgetsOut|Where-Object{$_.kind -eq 'data'}).Count
    unitBasis=$unitBasis; warnings=$warnings; providerInventory=$providerInventory; providerFilter=$platFilter
    periodResolved=$script:periodResolved; compareBasis=$script:compareBasis; savedComparePeriod=$s.compareDateRange
    extractionComplete=$completeness.extractionComplete; incompleteWidgets=@($completeness.incompleteWidgets)
    fetchBudget=$completeness.fetchBudget
  }
  report = [ordered]@{
    name=$s.name; subtitle=$s.subtitle; orientation=$s.orientation
    client=$s.client.name; clientId=$s.client.id; author=[ordered]@{name=$s.author.name;email=$s.author.email}; team=$s.teamName
    dateRange=$s.dateRange; compareDateRange=$s.compareDateRange; dateRangeResolved=$script:drResolved
    sections=@($s.sections|ForEach-Object{ [ordered]@{id=$_.id;name=$_.name} }); custom=$s.custom
  }
  widgets = $widgetsOut
}
# S14: additive and last, so meta's existing key order is byte-stable when the probe is off.
if($null -ne $fieldProbe){ $doc.meta.fieldProbe=@($fieldProbe) }

$stamp = (Get-Date).ToString('yyyy-MM-dd-HH-mm-ss')
$slug  = ($s.name -replace '[^A-Za-z0-9]+','-').Trim('-').ToLower(); if(-not $slug){ $slug='report' }
$path  = Join-Path $OutDir "$stamp-$slug.json"
[IO.File]::WriteAllText($path, ($doc | ConvertTo-Json -Depth 100), (New-Object Text.UTF8Encoding($false)))
Write-Host ("done -> {0}  ({1} widgets, {2} with data{3})" -f $path, $wids.Count, $doc.meta.dataWidgets, $(if($warnings){", "+$warnings.Count+" warning(s)"}else{""}))
