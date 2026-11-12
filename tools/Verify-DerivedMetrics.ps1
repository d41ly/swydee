<#
.SYNOPSIS
  Field check for Resolve-SwydoMetric.ps1 on REAL facts files: does it compute correctly, and does it
  ever state a figure it could not have derived from the data?

.DESCRIPTION
  For each facts file this script (1) generates derived-metric requests FROM the data, (2) runs the
  real tool as a child process on a scratch copy, and (3) audits every entry with an oracle that never
  loads the resolver, redoes the arithmetic in [decimal], and decides the expected outcome (resolve or
  refuse, previous period or not, comparison or not) BEFORE reading the tool's answer.

  What the oracle does NOT share with the tool:
    * its ground truth for a filtered subtotal is the IDENTITY  account = selected rows + other rows:
      the tool's figure must lie inside BOTH bounds (the selected rows' own sum, and the exact account
      figure minus the other rows); it does not copy the tool's choice of point value;
    * where the platform itself reports the same ratio (Cost / conversion, Avg. CPC, CTR at account
      level; Cost / conversion per breakdown row) the derived figure must agree - a difference FAILS;
    * the closer leg writes each line the way the template prescribes, then proves the closer still
      rejects it when the marker is removed, when "about" is removed from an approximate figure, and
      when the figure is altered.
  What it does share (stated so nobody mistakes it for proof): the reading of a display string
  (a count printed without decimals is an exact integer - Analyze-SwydoReport.ps1 Format-Metric; the
  unit suite pins that convention) and the rule that a row with no cell counts as zero.
  It does not model the widget cross-check: when the tool withholds a previous period that the oracle
  could resolve, that is accepted only with a stated route-disagreement reason.

  Checks: outcome, provenance of every cited input, arithmetic (figure inside the oracle bounds, range,
  approximate flag, previous period, delta), platform agreement, file integrity, closer.

  Reads only *.facts.json (credential-free by contract). Writes only under -WorkDir.
  EXIT 0 = no check failed; 1 = at least one failed; 2 = usage.

.PARAMETER FactsFile    One or more facts files.
.PARAMETER ArchiveRoot  Instead of -FactsFile: check every *.facts.json under this folder.
.PARAMETER WorkDir      Scratch folder (default: a new folder under the temp directory).
.PARAMETER MaxRows      Rows per breakdown to probe individually (default 6).
.PARAMETER ShowPassed   Also list the passing platform comparisons.
#>
param(
  [string[]]$FactsFile,
  [string]$ArchiveRoot,
  [string]$WorkDir,
  [int]$MaxRows = 6,
  [switch]$ShowPassed
)
$ErrorActionPreference = 'Stop'
$vFiles=$FactsFile; $vArchive=$ArchiveRoot; $vWork=$WorkDir; $vMaxRows=$MaxRows; $vShow=[bool]$ShowPassed
. "$PSScriptRoot\..\skill\scripts\Test-ReportNumbers.ps1" -DefineOnly      # the closer only
$script:Tool = (Resolve-Path "$PSScriptRoot\..\skill\scripts\Resolve-SwydoMetric.ps1").Path
$script:Inv  = [Globalization.CultureInfo]::InvariantCulture
$script:Enc  = New-Object Text.UTF8Encoding($false)
$script:Eps  = [decimal]0.000000001
$script:OkVersions = @(3,4)          # facts versions for which filtered terms are supported
$script:SeriesRx = '(?i)^(day|date|week|month|quarter|year)$'

# ---------------- oracle helpers (independent of the resolver) ----------------
function O-Dec($s){
  if($null -eq $s){ return $null }
  $t=([string]$s).Trim()
  if($t -notmatch '^-?[^\d\s-]{0,3} ?-?\d[\d,]*(\.\d+)?%?$'){ return $null }
  $core=$t -replace '[^0-9\.]',''
  $d=[decimal]::Parse($core,[Globalization.NumberStyles]::Float,$script:Inv)
  if($t -match '^[^\d]*-'){ $d=-$d }
  return $d
}
function O-Places($s){ $m=[regex]::Match([string]$s,'\.(\d+)'); if($m.Success){ return $m.Groups[1].Value.Length }; return 0 }
function O-Half($s){ $h=[decimal]0.5; for($i=0;$i -lt (O-Places $s);$i++){ $h=$h/10 }; return $h }
function O-CellHalf($disp,$unit){
  # a count printed with no decimals is an exact integer; everything else is known to half a last digit
  if((([string]$disp).Trim() -match '^-?[\d,]+$') -and ([string]$unit -ne 'micros') -and ([string]$unit -ne 'fraction')){ return [decimal]0 }
  return (O-Half $disp)
}
function O-Abs($d){ if($d -lt 0){ return -$d }; return $d }
function O-Seg($id){ return (([string]$id -split ':')[-1]).ToLower() }
function O-Headlines($pl){
  $out=@()
  if($pl.headline){ foreach($k in $pl.headline.PSObject.Properties.Name){ $h=$pl.headline.$k; if($h -and -not ($h -is [bool]) -and ($h.PSObject.Properties.Name -contains 'metric')){ $out+=$h } } }
  return $out
}
function O-Summable($pl,$h){
  $id=[string]$h.id
  if($pl.metrics -and ($pl.metrics.PSObject.Properties.Name -contains $id) -and $pl.metrics.$id.aggClass){ return ([string]$pl.metrics.$id.aggClass -eq 'sum') }
  # no coverage record (old facts): a total by NAME, never by display type
  if([string]$h.unit -eq 'fraction'){ return $false }
  return ((O-Seg $id) -match '^(cost_micros|cost|spend|amount_spent|clicks|impressions|conversions)$')
}
function O-Raw($h,$which){
  if($which -eq 'previous' -and $h.hasComparison -ne $true){ return $null }
  $r = if($which -eq 'current'){ $h.current } else { $h.previous }
  if($null -eq $r){ return $null }
  $d=[decimal][double]$r
  if([string]$h.unit -eq 'micros'){ $d=$d/1000000 }
  return $d
}
function O-CellName($bd,$id){
  $ids=@($bd.metricIds); $nms=@($bd.metricNames)
  $i=[array]::IndexOf($ids,[string]$id)
  if($i -lt 0 -or $i -ge $nms.Count){ return $null }
  $n=[string]$nms[$i]
  if([string]::IsNullOrWhiteSpace($n) -or @($nms | Where-Object { [string]$_ -eq $n }).Count -ne 1){ return $null }
  return $n
}
function O-CellDisp($row,$name,$which){
  if(-not $row.values){ return $null }
  $p=$row.values.PSObject.Properties[$name]
  if(-not $p -or $null -eq $p.Value){ return $null }
  $k = if($which -eq 'current'){ 'display' } else { 'displayPrevious' }
  if(-not ($p.Value.PSObject.Properties.Name -contains $k)){ return $null }
  return $p.Value.$k
}
function O-SumRows($rows,$name,$which,$unit){
  $mid=[decimal]0; $half=[decimal]0; $n=0; $bad=0
  foreach($r in @($rows)){
    $d=O-CellDisp $r $name $which
    if([string]::IsNullOrWhiteSpace([string]$d)){ continue }
    $v=O-Dec $d
    if($null -eq $v){ $bad++; continue }
    $mid+=$v; $half+=(O-CellHalf $d $unit); $n++
  }
  return @{ mid=$mid; lo=($mid-$half); hi=($mid+$half); cells=$n; bad=$bad }
}
function O-Labels($xs){ $o=@(); foreach($x in @($xs)){ if($null -eq $x){ continue }; $s=([string]$x).Trim(); if($s -ne ''){ $o+=$s } }; return $o }
function O-Term($pl,$term,$which,$factsVersion,$pinWidget){
  # -> @{ ok; why; lo; hi; exact; h; routes=@(...) }  (lo..hi = where the TRUE value must lie)
  $hs=@(O-Headlines $pl | Where-Object { if($term.metricId){ [string]$_.id -eq [string]$term.metricId } else { [string]$_.metric -ieq [string]$term.metric } })
  if($hs.Count -ne 1){ return @{ ok=$false; why="metric matches $($hs.Count) headline metrics" } }
  $h=$hs[0]
  if(-not (O-Summable $pl $h)){ return @{ ok=$false; why='not summable'; h=$h } }
  $acct=O-Raw $h $which
  if($null -eq $acct){ return @{ ok=$false; why="no $which account value"; h=$h } }
  if(-not $term.filter){ return @{ ok=$true; lo=$acct; hi=$acct; h=$h; routes=@() } }
  if($script:OkVersions -notcontains [int]$factsVersion){ return @{ ok=$false; why='facts version not supported for filtered terms'; h=$h } }
  if($which -eq 'previous' -and ([string]$term.filter.dimension -match $script:SeriesRx)){ return @{ ok=$false; why='time-series rows have no previous period'; h=$h } }
  $inc=@(O-Labels $term.filter.include); $exc=@(O-Labels $term.filter.exclude)
  $isInc=($inc.Count -gt 0); $want=@(if($isInc){ $inc } else { $exc })
  if($want.Count -eq 0){ return @{ ok=$false; why='empty filter'; h=$h } }
  $routes=@(); $why='no single-dimension breakdown'
  foreach($bd in @($pl.breakdowns)){
    $dims=@($bd.dimensions)
    if($dims.Count -ne 1 -or ([string]$dims[0] -ine [string]$term.filter.dimension)){ continue }
    if($pinWidget -and ([string]$bd.widgetId -ne [string]$pinWidget)){ continue }
    $cn=O-CellName $bd $h.id
    if(-not $cn){ continue }
    $rows=@($bd.rows)
    if([int]$bd.shown -ne [int]$bd.rowCount -or $rows.Count -ne [int]$bd.rowCount){ $why='truncated'; continue }
    $bad=$false; $hit=@()
    foreach($l in $want){ $m=@($rows | Where-Object { ([string]$_.label).Trim() -ieq $l }); if($m.Count -ne 1 -or (@($hit | Where-Object { [object]::ReferenceEquals($_,$m[0]) }).Count -gt 0)){ $bad=$true; break }; $hit+=$m[0] }
    if($bad){ $why='label not matched exactly once'; continue }
    $all=O-SumRows $rows $cn $which $h.unit
    if($all.bad -gt 0){ $why='unreadable cell'; continue }
    if($all.cells -eq 0){ $why='no values'; continue }
    if(($acct -lt ($all.lo-$script:Eps)) -or ($acct -gt ($all.hi+$script:Eps))){ $why='rows do not reconcile with the account total'; continue }
    $isHit={ param($r) @($hit | Where-Object { [object]::ReferenceEquals($_,$r) }).Count -gt 0 }
    $sel=@($rows | Where-Object { (& $isHit $_) -eq $isInc }); $rest=@($rows | Where-Object { (& $isHit $_) -ne $isInc })
    $s=O-SumRows $sel $cn $which $h.unit; $o=O-SumRows $rest $cn $which $h.unit
    # the identity: selected = account - others. The true value lies in both intervals.
    $lo=[math]::Max($s.lo,($acct-$o.hi)); $hi=[math]::Min($s.hi,($acct-$o.lo))
    if($lo -gt ($hi+$script:Eps)){ $why='row bounds contradict the account figure'; continue }
    if($hi -lt $lo){ $hi=$lo }
    $routes+=@{ widgetId=[string]$bd.widgetId; labels=@($sel | ForEach-Object { [string]$_.label }); displays=@($sel | ForEach-Object { [string](O-CellDisp $_ $cn $which) }); cell=$cn; lo=$lo; hi=$hi }
  }
  if($routes.Count -eq 0){ return @{ ok=$false; why=$why; h=$h } }
  foreach($r in $routes){ if(($r.lo -gt ($routes[0].hi+$script:Eps)) -or ($routes[0].lo -gt ($r.hi+$script:Eps))){ return @{ ok=$false; why='breakdowns disagree'; h=$h } } }
  return @{ ok=$true; lo=$routes[0].lo; hi=$routes[0].hi; h=$h; routes=$routes }
}
function O-Combine($op,$ts){
  # -> @{ ok; lo; hi } : the interval the TRUE result lies in
  if($op -eq 'ratio'){
    if($ts[1].lo -le 0 -or $ts[0].lo -lt 0){ return @{ ok=$false } }
    return @{ ok=$true; lo=($ts[0].lo/$ts[1].hi); hi=($ts[0].hi/$ts[1].lo) }
  }
  $l=$ts[0].lo; $h=$ts[0].hi
  for($i=1;$i -lt $ts.Count;$i++){ if($op -eq 'sum'){ $l+=$ts[$i].lo; $h+=$ts[$i].hi } else { $l-=$ts[$i].hi; $h-=$ts[$i].lo } }
  return @{ ok=$true; lo=$l; hi=$h }
}
function O-Within($display,$lo,$hi,$scale){
  # the stated figure, read back, lies inside the oracle interval (to the display's own rounding)
  $d=O-Dec $display
  if($null -eq $d){ return $false }
  $h=(O-Half $display) + [decimal]0.0000001
  return (($d -ge (($lo*$scale)-$h)) -and ($d -le (($hi*$scale)+$h)))
}
function O-Near($display,$value,$scale){ return (O-Within $display $value $value $scale) }

# ---------------- request generation from the data ----------------
function New-Requests($facts,$maxRows){
  $reqs=New-Object System.Collections.ArrayList
  $single=(@($facts.platforms).Count -eq 1)
  $script:rn=0
  $add={ param($pl,$kind,$label,$op,$terms,$extra)
    $script:rn++; $id=('r{0:d4}' -f $script:rn)
    $r=[ordered]@{ id=$id; label=$label; op=$op; terms=@($terms) }
    # exercise both ways of naming the platform: omitted (when there is only one) and explicit
    if(-not ($single -and ($script:rn % 2 -eq 0))){ $r.platform=[string]$pl.id }
    if($extra){ foreach($k in $extra.Keys){ $r[$k]=$extra[$k] } }
    [void]$reqs.Add(@{ req=$r; kind=$kind; platformId=[string]$pl.id }) }
  foreach($pl in @($facts.platforms)){
    $hs=@(O-Headlines $pl)
    $pick={ param($rx) $m=@($hs | Where-Object { (O-Seg $_.id) -match $rx }); if($m.Count -ge 1){ return $m[0] }; return $null }
    $cost=& $pick '^(cost_micros|spend|amount_spent|cost)$'
    $conv=& $pick '^conversions$'
    $clk =& $pick '^clicks$'
    $imp =& $pick '^impressions$'
    $rCpa=& $pick '^cost_per_conversion$'; $rCpc=& $pick '^(average_cpc|cpc)$'; $rCtr=& $pick '^ctr$'
    # name a metric by its display name when that is unambiguous (odd request numbers), else by id
    $mkTerm={ param($h,$f)
      $byName=(($script:rn % 2 -eq 1) -and (@($hs | Where-Object { [string]$_.metric -ieq [string]$h.metric }).Count -eq 1))
      $t=[ordered]@{}; if($byName){ $t.metric=[string]$h.metric } else { $t.metricId=[string]$h.id }
      if($f){ $t.filter=$f }; return $t }
    # account-level ratios the platform also reports (definitional: they must match)
    if($cost -and $conv -and $rCpa){ & $add $pl 'platform-ratio' 'cost per conversion' 'ratio' @((& $mkTerm $cost),(& $mkTerm $conv)) @{ _reported=[string]$rCpa.id } }
    if($cost -and $clk  -and $rCpc){ & $add $pl 'platform-ratio' 'cost per click' 'ratio' @((& $mkTerm $cost),(& $mkTerm $clk)) @{ _reported=[string]$rCpc.id } }
    if($clk  -and $imp  -and $rCtr){ & $add $pl 'platform-ratio' 'click-through rate' 'ratio' @((& $mkTerm $clk),(& $mkTerm $imp)) @{ format='percent'; _reported=[string]$rCtr.id } }
    if($clk -and $conv){ & $add $pl 'plain' 'clicks minus conversions' 'difference' @((& $mkTerm $clk),(& $mkTerm $conv)) $null }
    if($clk -and $imp){ & $add $pl 'plain' 'clicks plus impressions' 'sum' @((& $mkTerm $clk),(& $mkTerm $imp)) $null }
    # every single-dimension breakdown: leave one row out / keep one row
    foreach($bd in @($pl.breakdowns)){
      $dims=@($bd.dimensions)
      if($dims.Count -ne 1){ continue }
      $dim=[string]$dims[0]
      $labels=@(@($bd.rows) | ForEach-Object { [string]$_.label } | Select-Object -First $maxRows)
      foreach($m in @($conv,$clk,$imp,$cost)){
        if(-not $m -or ([array]::IndexOf(@($bd.metricIds),[string]$m.id) -lt 0)){ continue }
        foreach($l in $labels){
          & $add $pl 'filter' "$($m.metric) without one row ($dim)" 'sum' @((& $mkTerm $m ([ordered]@{ dimension=$dim; exclude=@($l) }))) $null
          & $add $pl 'filter' "$($m.metric) for one row only ($dim)" 'sum' @((& $mkTerm $m ([ordered]@{ dimension=$dim; include=@($l) }))) $null
        }
        if($labels.Count -ge 2){ & $add $pl 'filter' "$($m.metric) without two rows ($dim)" 'sum' @((& $mkTerm $m ([ordered]@{ dimension=$dim; exclude=@($labels[0],$labels[1]) }))) $null }
      }
      if($cost -and $conv -and ([array]::IndexOf(@($bd.metricIds),[string]$conv.id) -ge 0)){
        foreach($l in $labels){ & $add $pl 'filter' "cost per conversion without one row ($dim)" 'ratio' @((& $mkTerm $cost),(& $mkTerm $conv ([ordered]@{ dimension=$dim; exclude=@($l) }))) $null }
        if([array]::IndexOf(@($bd.metricIds),[string]$cost.id) -ge 0){
          foreach($l in $labels){ & $add $pl 'row-ratio' "cost per conversion for one row ($dim)" 'ratio' @((& $mkTerm $cost ([ordered]@{ dimension=$dim; include=@($l) })),(& $mkTerm $conv ([ordered]@{ dimension=$dim; include=@($l) }))) @{ _row=$l; _widget=[string]$bd.widgetId; _reportedSeg='cost_per_conversion' } }
        }
      }
      # probes that MUST be refused
      $m0=@($conv,$clk,$imp,$cost | Where-Object { $_ -and ([array]::IndexOf(@($bd.metricIds),[string]$_.id) -ge 0) })
      if($m0.Count -gt 0){ & $add $pl 'probe' "row that does not exist ($dim)" 'sum' @((& $mkTerm $m0[0] ([ordered]@{ dimension=$dim; exclude=@('__no_such_row__') }))) $null }
    }
    # a multi-dimension widget must never stand in for a row breakdown, named or not
    $multi=@(@($pl.breakdowns) | Where-Object { @($_.dimensions).Count -gt 1 } | Select-Object -First 1)
    if($multi.Count -eq 1 -and $conv){ & $add $pl 'probe' 'invented filter riding on a named widget' 'sum' @((& $mkTerm $conv ([ordered]@{ dimension='__no_such_dimension__'; exclude=@('x') }))) $null; $reqs[$reqs.Count-1].req.terms[0].widget=[string]$multi[0].widgetId }
    if($cost){ & $add $pl 'probe' 'dimension that does not exist' 'sum' @((& $mkTerm $cost ([ordered]@{ dimension='__no_such_dimension__'; exclude=@('x') }))) $null }
    & $add $pl 'probe' 'metric that does not exist' 'sum' @([ordered]@{ metric='__no_such_metric__' }) $null
    $ratioMetric=@($hs | Where-Object { -not (O-Summable $pl $_) -and ((O-Seg $_.id) -match 'per_|average|rate|share|^ctr$|cpc|cpm') } | Select-Object -First 1)
    if($ratioMetric.Count -eq 1 -and $clk){ & $add $pl 'probe' 'a rate used as a component' 'ratio' @([ordered]@{ metricId=[string]$ratioMetric[0].id },[ordered]@{ metricId=[string]$clk.id }) $null }
  }
  return $reqs
}

# ---------------- audit of one facts file ----------------
function Test-FactsFile($path,$workDir,$maxRows){
  $res=@{ file=$path; requests=0; resolved=0; refused=0; checks=0; fails=(New-Object System.Collections.ArrayList); platform=0; prevResolved=0; approx=0; exact=0; cmp=0; shown=(New-Object System.Collections.ArrayList) }
  $fail={ param($id,$what) [void]$res.fails.Add("[$id] $what") }
  $ok={ param($cond,$id,$what) $res.checks++; if(-not $cond){ & $fail $id $what } }
  $origText=[IO.File]::ReadAllText($path)
  $orig=$origText | ConvertFrom-Json
  if(-not $orig.platforms){ $res.skipped='no platforms'; return $res }
  if([string]$orig.meta.tool -ne 'Analyze-SwydoReport.ps1'){ $res.skipped='not single-period report facts'; return $res }
  $fv=$orig.meta.factsVersion
  $gen=@(New-Requests $orig $maxRows)
  $res.requests=$gen.Count
  if($gen.Count -eq 0){ $res.skipped='nothing to request'; return $res }
  $stem=[IO.Path]::GetFileNameWithoutExtension($path) + '-' + ([guid]::NewGuid().ToString('N').Substring(0,6))
  $reqPath=Join-Path $workDir "$stem.requests.json"; $outPath=Join-Path $workDir "$stem.out.facts.json"
  $clean=@($gen | ForEach-Object { $c=[ordered]@{}; foreach($k in $_.req.Keys){ if(-not $k.StartsWith('_')){ $c[$k]=$_.req[$k] } }; $c })
  [IO.File]::WriteAllText($reqPath,(ConvertTo-Json -InputObject @{ requests=$clean } -Depth 12),$script:Enc)
  $toolOut = & powershell -NoProfile -File $script:Tool -Facts $path -RequestFile $reqPath -OutFile $outPath -Replace 2>&1
  $code=$LASTEXITCODE
  & $ok ($code -in 0,1) 'run' "tool exit code $code (expected 0 or 1): $(@($toolOut | Select-Object -Last 2) -join ' ')"
  if(-not (Test-Path $outPath)){ & $fail 'run' 'tool wrote no output'; return $res }
  # integrity: the input is untouched, and the output is the input plus one appended member
  & $ok ([IO.File]::ReadAllText($path) -ceq $origText) 'integrity' 'the input facts file was modified'
  $outText=[IO.File]::ReadAllText($outPath)
  $origHead=$origText.TrimEnd(); $origHead=$origHead.Substring(0,$origHead.Length-1).TrimEnd()
  if(-not ($orig.PSObject.Properties.Name -contains 'derivedMetrics')){ & $ok ($outText.StartsWith($origHead + ",`n  `"derivedMetrics`": ")) 'integrity' 'output is not the original text plus an appended derivedMetrics member' }
  $out=$outText | ConvertFrom-Json
  $byId=@{}; foreach($e in @($out.derivedMetrics.entries)){ $byId[[string]$e.id]=$e }
  $wantPrev=(([string]$orig.meta.compareBasis -ne 'untrusted') -and ($orig.meta.hasComparison -ne $false))

  foreach($g in $gen){
    $r=$g.req; $id=[string]$r.id
    $pl=@($orig.platforms | Where-Object { [string]$_.id -eq $g.platformId })[0]
    $e=$byId[$id]
    if(-not $e){ & $fail $id 'no entry written for this request'; continue }
    $terms=@($r.terms | ForEach-Object { $t=[pscustomobject]$_; if($t.filter -and -not ($t.filter -is [pscustomobject])){ $t.filter=[pscustomobject]$t.filter }; $t })
    # --- the oracle decides first ---
    $tc=@($terms | ForEach-Object { O-Term $pl $_ 'current' $fv $null })
    $expect=(@($tc | Where-Object { -not $_.ok }).Count -eq 0)
    if($expect -and @($terms | Where-Object { $_.PSObject.Properties.Name -contains 'widget' }).Count -gt 0){ $expect=$false }   # generated only as probes
    $oc=$null
    if($expect){ $oc=O-Combine ([string]$r.op) $tc; if(-not $oc.ok){ $expect=$false } }
    $got=([string]$e.status -eq 'resolved')
    if($got){ $res.resolved++ } else { $res.refused++ }
    $whyNot=(@($tc | Where-Object { -not $_.ok } | ForEach-Object { $_.why }) -join '; ')
    & $ok ($got -eq $expect) $id ("outcome: tool " + $(if($got){'RESOLVED'}else{'REFUSED (' + (@($e.reasons) -join '; ') + ')'}) + " but the oracle expected " + $(if($expect){'a resolvable request'}else{"a refusal ($whyNot)"}) + " :: $($r.label)")
    & $ok ($e.derived -eq $true -and [string]$e.marker -match 'not reported') $id 'entry lacks the derived / not-reported marker'
    if($g.kind -eq 'probe'){ & $ok (-not $got) $id "a probe that must be refused was resolved :: $($r.label)" }
    if(-not $got){
      & $ok (-not ($e.PSObject.Properties.Name -contains 'current')) $id 'a refused entry carries a figure'
      & $ok (@($e.reasons).Count -ge 1 -and [string]@($e.reasons)[0]) $id 'a refused entry states no reason'
      continue
    }
    if(-not $expect){ continue }
    # --- previous period: the oracle's own expectation ---
    $pins=@($tc | ForEach-Object { if($_.routes -and @($_.routes).Count -gt 0){ $null } else { $null } })
    $tp=@(); $prevOk=$wantPrev -and ($pl.hasComparison -ne $false)
    if($prevOk){
      for($i=0;$i -lt $terms.Count;$i++){
        $pin=$null; $cin=@($e.current.inputs)[$i]; if($cin -and [string]$cin.source.kind -eq 'breakdown-rows'){ $pin=[string]$cin.source.widgetId }
        $tp+=(O-Term $pl $terms[$i] 'previous' $fv $pin)
      }
      if(@($tp | Where-Object { -not $_.ok }).Count -gt 0){ $prevOk=$false } else { $op2=O-Combine ([string]$r.op) $tp; if(-not $op2.ok){ $prevOk=$false } }
    }
    $prevGot=[bool]($e.previous -and ($e.previous.PSObject.Properties.Name -contains 'display'))
    if($prevGot -and -not $prevOk){ & $fail $id "previous period: the tool states a figure the oracle says cannot be resolved ($(@($tp | Where-Object { -not $_.ok } | ForEach-Object { $_.why }) -join '; '))" }
    if($prevOk -and -not $prevGot){ & $ok ([string]$e.previous.reason -match 'routes disagree|cross-check widget') $id "previous period withheld without a route-disagreement reason: $($e.previous.reason)" }
    # --- provenance + arithmetic, per period ---
    $scale = if([string]$e.type -eq 'percent'){ [decimal]100 } else { [decimal]1 }
    $per=@{}
    foreach($which in @('current','previous')){
      $blk=$e.$which
      if(-not $blk -or -not ($blk.PSObject.Properties.Name -contains 'display')){ continue }
      $ts = @(if($which -eq 'current'){ $tc } else { $tp })      # @(): an if-expression unrolls a one-element array
      if($which -eq 'previous'){ if(-not $prevOk){ continue }; $res.prevResolved++ }
      $ins=@($blk.inputs)
      & $ok ($ins.Count -eq $ts.Count) $id "${which}: $($ins.Count) inputs for $($ts.Count) terms"
      $tb=@()
      for($i=0;$i -lt [math]::Min($ins.Count,$ts.Count);$i++){
        $in=$ins[$i]; $t=$ts[$i]; $h=$t.h
        $hDisp = if($which -eq 'current'){ [string]$h.displayCurrent } else { [string]$h.displayPrevious }
        & $ok ([string]$in.source.metricId -eq [string]$h.id) $id "${which} input $($i+1): cites metric $($in.source.metricId), the request named $($h.id)"
        $b=@{ lo=$t.lo; hi=$t.hi }
        if([string]$in.source.kind -eq 'headline'){
          & $ok (-not $terms[$i].filter) $id "${which} input $($i+1): a filtered term was taken from the unfiltered headline"
          & $ok ([string]$in.display -ceq $hDisp) $id "${which} input $($i+1): cites '$($in.display)' but the headline shows '$hDisp'"
        } elseif([string]$in.source.kind -eq 'breakdown-rows'){
          $rt=@($t.routes | Where-Object { $_.widgetId -eq [string]$in.source.widgetId })
          & $ok ($rt.Count -eq 1) $id "${which} input $($i+1): rows taken from widget $($in.source.widgetId), which the oracle does not accept as a reconciling breakdown"
          if($rt.Count -eq 1){
            $used=@($in.source.rows)
            & $ok ((@($used | ForEach-Object { [string]$_.label }) -join '|') -ceq ($rt[0].labels -join '|')) $id "${which} input $($i+1): rows used [$(@($used | ForEach-Object { $_.label }) -join ', ')] are not the rows the filter selects [$($rt[0].labels -join ', ')]"
            for($k=0;$k -lt [math]::Min($used.Count,$rt[0].displays.Count);$k++){
              & $ok ([string]$used[$k].display -ceq [string]$rt[0].displays[$k]) $id "${which} input $($i+1): row '$($used[$k].label)' cited as '$($used[$k].display)' but the facts show '$($rt[0].displays[$k])'"
            }
            & $ok ([string]$in.source.reconciledWith.account -ceq $hDisp) $id "${which} input $($i+1): reconciliation cites account '$($in.source.reconciledWith.account)', headline shows '$hDisp'"
            & $ok (O-Within $in.display $rt[0].lo $rt[0].hi 1) $id "${which} input $($i+1): subtotal '$($in.display)' lies outside what the rows and the account allow ($($rt[0].lo) .. $($rt[0].hi))"
            $b=@{ lo=$rt[0].lo; hi=$rt[0].hi }
          }
        } else { & $fail $id "${which} input $($i+1): unexpected source kind '$($in.source.kind)'" }
        $tb+=$b
      }
      $o=O-Combine ([string]$r.op) $tb
      if(-not $o.ok){ & $fail $id "${which}: the tool states a figure for an undefined result (zero or negative denominator)"; continue }
      $per[$which]=$o
      & $ok (O-Within $blk.display $o.lo $o.hi $scale) $id "${which}: tool says '$($blk.display)', but the data only allow $($o.lo*$scale) .. $($o.hi*$scale)"
      if($blk.approximate -eq $true){
        $res.approx++
        & $ok ($o.lo -ne $o.hi) $id "${which}: flagged approximate although every input is exact"
        & $ok ((O-Near $blk.displayLow $o.lo $scale) -and (O-Near $blk.displayHigh $o.hi $scale)) $id "${which}: range '$($blk.displayLow)'..'$($blk.displayHigh)' but the oracle bounds are $($o.lo*$scale)..$($o.hi*$scale)"
      } else {
        $res.exact++
        # stated without a range: every value the data allow must round to the stated figure
        & $ok ((O-Near $blk.display $o.lo $scale) -and (O-Near $blk.display $o.hi $scale)) $id "${which}: stated as exact '$($blk.display)' but the inputs only bound it to $($o.lo*$scale)..$($o.hi*$scale)"
      }
    }
    # --- comparison: expected exactly when both periods stand and the values are positive ---
    $cmpGot=[bool]($e.comparison -and $e.comparison.hasComparison -eq $true)
    if($per.ContainsKey('current') -and $per.ContainsKey('previous')){
      $c=$per['current']; $p=$per['previous']
      $cmpWant=(($p.lo -gt 0) -and ($c.lo -ge 0))
      & $ok ($cmpGot -eq $cmpWant) $id ("comparison: tool " + $(if($cmpGot){'emits'}else{'withholds'}) + " a delta, the oracle expected " + $(if($cmpWant){'one'}else{'none'}))
      if($cmpGot -and $cmpWant){
        $res.cmp++
        $dlo=(($c.lo/$p.hi)-1)*100; $dhi=(($c.hi/$p.lo)-1)*100
        & $ok (O-Within $e.comparison.displayDelta $dlo $dhi 1) $id "delta: tool says '$($e.comparison.displayDelta)', but the data only allow $dlo .. $dhi"
        $dv=O-Dec $e.comparison.displayDelta
        & $ok ((([string]$e.comparison.displayDelta).StartsWith('-')) -eq ($dv -lt 0)) $id "delta: sign of '$($e.comparison.displayDelta)'"
      }
    } elseif($cmpGot){ & $fail $id 'a comparison is stated but one of the periods did not verify' }
    # --- against the platform's own figure (a difference is a FAILURE) ---
    if($per.ContainsKey('current')){
      $o=$per['current']
      if($g.kind -eq 'platform-ratio'){
        $rep=@(O-Headlines $pl | Where-Object { [string]$_.id -eq [string]$r._reported })[0]
        $res.platform++
        $same=([string]$e.current.display -ceq [string]$rep.displayCurrent)
        & $ok $same $id "PLATFORM DIFFERS: $($pl.name) $($rep.metric) derived $($e.current.display) vs reported $($rep.displayCurrent)"
        if($same){ [void]$res.shown.Add("[$id] $($pl.name) $($rep.metric): derived $($e.current.display) = reported $($rep.displayCurrent)") }
      } elseif($g.kind -eq 'row-ratio'){
        $bd=@($pl.breakdowns | Where-Object { [string]$_.widgetId -eq [string]$r._widget })[0]
        $ri=-1; $ids=@($bd.metricIds); for($k=0;$k -lt $ids.Count;$k++){ if((O-Seg $ids[$k]) -eq [string]$r._reportedSeg){ $ri=$k; break } }
        if($ri -ge 0){
          $cn=O-CellName $bd $ids[$ri]
          $row=@($bd.rows | Where-Object { [string]$_.label -ceq [string]$r._row })
          $rd = if($cn -and $row.Count -eq 1){ O-CellDisp $row[0] $cn 'current' } else { $null }
          $rv=O-Dec $rd
          if($null -ne $rv){
            $res.platform++
            $h=(O-Half $rd) + [decimal]0.0000001
            $same=(($rv+$h) -ge $o.lo) -and (($rv-$h) -le $o.hi)
            & $ok $same $id "PLATFORM DIFFERS: $($pl.name) Cost / conversion for row '$($r._row)': derived $($e.current.display) ($($o.lo) .. $($o.hi)) vs reported $rd"
            if($same){ [void]$res.shown.Add("[$id] $($pl.name) Cost / conversion, row '$($r._row)': derived $($e.current.display) ~ reported $rd") }
          }
        }
      }
    }
  }

  # --- closer: every entry written the way the template says; then the same lines, sabotaged ---
  $ours={ param($cr) @($cr.violations | Where-Object { $_.type -match '^derived|^unsurfaced-derived$|^unknown-derived|^multiline-comment$' -or $_.type -in @('untraceable-number','comparison-without-data') }) }
  $lines=New-Object System.Collections.ArrayList
  $sab=New-Object System.Collections.ArrayList
  [void]$lines.Add('Intro.')
  foreach($g in @($gen | Where-Object { $byId[[string]$_.req.id] -and -not $byId[[string]$_.req.id].platformId })){ [void]$lines.Add("- This figure could not be calculated from the dashboard. <!-- derived:$($g.req.id) -->") }
  foreach($pl in @($orig.platforms)){
    $head=@('',"## $($pl.name)","<!-- platform:$($pl.id) -->",'')
    foreach($x in $head){ [void]$lines.Add($x) }
    foreach($g in @($gen | Where-Object { $_.platformId -eq [string]$pl.id })){
      $e=$byId[[string]$g.req.id]; if(-not $e -or -not $e.platformId){ continue }
      if([string]$e.status -ne 'resolved'){ [void]$lines.Add("- This figure could not be calculated from the dashboard. <!-- derived:$($e.id) -->"); continue }
      $about = if($e.current.approximate -eq $true){ 'about ' } else { '' }
      $mk='derived - not a figure the platform reports: '
      $tpl="- The figure was {0}{1} ({2}$($e.formula)). <!-- derived:$($e.id) -->"
      [void]$lines.Add(($tpl -f $about,[string]$e.current.display,$mk))
      if($sab.Count -lt 60){
        $one={ param($a,$fig,$m) (($head -join "`n") + "`n" + ($tpl -f $a,$fig,$m) + "`n") }
        $v=O-Dec $e.current.display
        $alt=([string]::Format($script:Inv,'{0:N4}',(($v*3)+[decimal]1.2345)))
        if([string]$e.type -eq 'currency'){ $alt='$' + $alt } elseif([string]$e.type -eq 'percent'){ $alt=$alt + '%' }
        [void]$sab.Add(@{ id=[string]$e.id; text=(& $one $about $alt $mk); want='untraceable-number'; what="an altered figure ($alt)" })
        # the marker is owed when the figure traces ONLY through the entry - i.e. when the same line
        # without its anchor would not trace (a derived figure equal to a reported fact needs none)
        $bare=Invoke-Closer ((& $one $about ([string]$e.current.display) $mk) -replace '<!-- derived:[^>]*-->','') $out
        if(@($bare.violations | Where-Object { $_.type -eq 'untraceable-number' }).Count -gt 0){
          [void]$sab.Add(@{ id=[string]$e.id; text=(& $one $about ([string]$e.current.display) ''); want='derived-marker-missing'; what='the line without its marker' })
        }
        if($about){ [void]$sab.Add(@{ id=[string]$e.id; text=(& $one '' ([string]$e.current.display) $mk); want='derived-approximation-missing'; what='an approximate figure without "about"' }) }
      }
    }
  }
  $cv=@(& $ours (Invoke-Closer ($lines -join "`n") $out))
  & $ok ($cv.Count -eq 0) 'closer' ("a correctly worded report of every entry has $($cv.Count) violation(s): " + (@($cv | Select-Object -First 4 | ForEach-Object { $_.type + ' ' + $_.detail }) -join ' | '))
  foreach($m in $sab){
    $mr=Invoke-Closer $m.text $out
    & $ok (@($mr.violations | Where-Object { $_.type -eq $m.want }).Count -ge 1) $m.id "closer accepted $($m.what)"
  }
  return $res
}

# ---------------- run ----------------
$files=@()
if($vFiles){ $files+=@($vFiles | ForEach-Object { (Resolve-Path -LiteralPath $_).Path }) }
if($vArchive){ $files+=@(Get-ChildItem -LiteralPath $vArchive -Recurse -File -Filter *.facts.json | Sort-Object FullName | ForEach-Object { $_.FullName }) }
if($files.Count -eq 0){ Write-Host 'usage: Verify-DerivedMetrics.ps1 (-FactsFile <facts.json>[,...] | -ArchiveRoot <dir>) [-WorkDir <dir>] [-MaxRows <n>] [-ShowPassed]'; exit 2 }
if(-not $vWork){ $vWork=Join-Path ([IO.Path]::GetTempPath()) ('swydee-verify-' + [guid]::NewGuid().ToString('N').Substring(0,8)) }
if(-not (Test-Path -LiteralPath $vWork)){ New-Item -ItemType Directory -Path $vWork | Out-Null }
$vWork=(Resolve-Path -LiteralPath $vWork).Path

$tot=@{ files=0; requests=0; resolved=0; refused=0; checks=0; fails=0; plat=0; prev=0; approx=0; exact=0; cmp=0 }
foreach($f in $files){
  $r=Test-FactsFile $f $vWork $vMaxRows
  $name=Split-Path (Split-Path $f -Parent) -Leaf
  $client=Split-Path (Split-Path (Split-Path $f -Parent) -Parent) -Leaf
  if($r.skipped){ Write-Host ("{0}/{1}: skipped ({2})" -f $client,$name,$r.skipped); continue }
  $tot.files++; $tot.requests+=$r.requests; $tot.resolved+=$r.resolved; $tot.refused+=$r.refused; $tot.checks+=$r.checks; $tot.fails+=$r.fails.Count; $tot.plat+=$r.platform; $tot.prev+=$r.prevResolved; $tot.approx+=$r.approx; $tot.exact+=$r.exact; $tot.cmp+=$r.cmp
  Write-Host ("{0}/{1}: {2} requests -> {3} resolved, {4} refused | {5} checks, {6} FAILED | compared with the platform: {7}" -f $client,$name,$r.requests,$r.resolved,$r.refused,$r.checks,$r.fails.Count,$r.platform)
  foreach($x in @($r.fails | Select-Object -First 15)){ Write-Host "    FAIL $x" }
  if($r.fails.Count -gt 15){ Write-Host "    ... and $($r.fails.Count-15) more" }
  if($vShow){ foreach($x in $r.shown){ Write-Host "    agrees $x" } }
}
Write-Host ''
Write-Host ("Verify-DerivedMetrics: {0} file(s), {1} requests ({2} resolved, {3} refused)." -f $tot.files,$tot.requests,$tot.resolved,$tot.refused)
Write-Host ("  figures: {0} exact, {1} approximate; {2} previous-period figures; {3} comparisons" -f $tot.exact,$tot.approx,$tot.prev,$tot.cmp)
Write-Host ("  checks: {0}, failed: {1} (includes {2} comparisons with the platform's own figure)" -f $tot.checks,$tot.fails,$tot.plat)
if($tot.fails -gt 0){ exit 1 }
exit 0
