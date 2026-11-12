<#
.SYNOPSIS
  Resolve DERIVED metrics - figures the dashboard does not report directly - from a /swydee facts file,
  deterministically, and add them to the facts as a closer-traceable `derivedMetrics` block.

.DESCRIPTION
  "The model narrates; the tools compute." A request names a ratio / sum / difference over account
  metrics, optionally filtered by include/exclude on the rows of a breakdown (e.g. Cost divided by
  Conversions excluding 'Local actions - Directions'). The model may TRANSLATE a plain-language ask
  (a `derive:"..."` argument or a client note) into the request format below; this tool finds the
  components, checks they are compatible, computes, and refuses with a stated reason otherwise.

  Reads ONLY the facts file (credential-free by contract) - never the raw extraction.

  REQUEST FORMAT (JSON file; one object, an array, or { "requests": [ ... ] }):
    {
      "id":       "cpl_ex_directions",          required  ^[a-z0-9][a-z0-9_-]{0,63}$ - the report anchor id
      "label":    "Cost / conversion excluding 'Local actions - Directions'",   required, client-facing name
      "platform": "google-adwords",             optional when the facts hold exactly one platform
      "op":       "ratio" | "sum" | "difference",
      "terms": [                                ratio: exactly 2 (numerator, denominator);
        { "metric": "Cost" },                   difference: first minus the rest; sum: 1 or more
        { "metric": "Conversions",              metric = headline display name, or "metricId": "<id>"
          "filter": { "dimension": "Conversion action name",
                      "exclude": [ "Local actions - Directions" ] },     exactly one of include / exclude
          "widget": "<widgetId>" }              optional: a widget whose total MUST AGREE with the rows (cross-check only)
      ],
      "format":    "currency" | "number" | "percent",   optional (inferred from the terms)
      "decimals":  2,                            optional, plain number results only
      "alongside": "Cost / conversion",          optional: a REPORTED headline metric to present next to it
      "source":    "annotation:ANN#1"            optional provenance; an annotation id must exist in the facts
    }
  Filter labels are strings or numbers (a row called 0 is a row); naming a row twice is malformed.
  Nothing typed into a request is ever quotable as a number in the report: the formula is built from
  the facts' own metric and row names, and the closer does not index label / source / refusal reasons.

  HOW A TERM RESOLVES
    * unfiltered term  -> the platform's account-level headline figure (raw value, unit-normalised).
    * filtered term    -> ONLY from the rows of a breakdown whose single dimension is filter.dimension,
                          complete (shown == rowCount), whose rows RECONCILE with the account figure for
                          the same period (proof they partition the account metric). The subtotal is
                          bounded twice - the selected rows added up, and the account figure minus the
                          other rows - and the intersection is kept (an empty one is a refusal). Two
                          such breakdowns that give different subtotals are a refusal. The previous
                          period uses the SAME breakdown; rows of a time-series breakdown have none.
    * cross-check      -> other widgets carrying the metric whose dimensions include filter.dimension,
                          and the widget the request names. The facts do not record widget filters, so
                          a widget total never SUPPLIES a value: an auto-discovered one corroborates
                          when it matches; the named one must match or the request is refused. A widget
                          with a time-series dimension has a usable previous column only when it is one
                          row per month and both windows span exactly that many months.
    * every term must be a summable metric (coverage record aggClass 'sum', or the analyzer's own
      classifier for older facts), all on ONE platform, the report's own periods, account-level scope,
      compatible types and one currency. Filtered terms need a facts version this tool was verified
      against ($script:DmFactsVersions).

  PRECISION. A count shown without decimals is an exact integer (Analyze-SwydoReport.ps1 Format-Metric
  prints N0 only for integers; the run block re-checks that convention before computing). Any other
  cell is known to half its last displayed digit, and that doubt is carried as an interval. When the
  low and high ends format differently the entry is `approximate` with displayLow/displayHigh, and the
  closer makes the report say "about". Cells carrying `raw`/`rawPrevious` are used exactly.

  A comparison (delta) is emitted ONLY when both periods resolve and no usable route disagrees.

  OUTPUT. The facts file gains (or has replaced) a top-level member:
    "derivedMetrics": { tool, version, marker, entries: [ { id, v, label, status: resolved|refused,
       derived: true, marker, platformId, op, formula, type, current{display, approximate, displayLow,
       displayHigh, crossCheck, inputs[{role, term, display, source{...}}]}, previous{...},
       comparison{...}, reported{...}, notes[], reasons[] } ] }
  It is spliced into the facts TEXT (the rest of the document is byte-preserved, never re-serialised),
  written to a temporary file and swapped in, BOM-less UTF-8. Entries with other ids from an earlier
  run are kept unless -Replace is given.

  EXIT: 0 every request resolved | 1 at least one request refused (block still written, so the report
  can say so) | 2 NOTHING written: usage, malformed request, facts that are not single-period report
  facts, an older-version entry still present, a broken format convention, or any unexpected error.
.PARAMETER Facts        Path to the *.facts.json produced by Analyze-SwydoReport.ps1
.PARAMETER RequestFile  Path to the JSON request file (see above)
.PARAMETER OutFile      Write the updated facts here instead of updating -Facts in place
.PARAMETER Replace      Keep only the entries this request file asks for (refuses to drop one a client note requested)
.PARAMETER DefineOnly   Define functions and return WITHOUT running (for tests)
.EXAMPLE
  .\Resolve-SwydoMetric.ps1 -Facts .\out\x.facts.json -RequestFile .\out\derive-requests.json
#>
param(
  [string]$Facts,
  [string]$RequestFile,
  [string]$OutFile = "",
  [switch]$Replace,
  [switch]$DefineOnly
)
$ErrorActionPreference = 'Stop'
# Saved before the dot-source below: Analyze-SwydoReport.ps1 has its own param() block (same trick as
# Analyze-SwydoTrend.ps1).
$myFacts=$Facts; $myRequestFile=$RequestFile; $myOutFile=$OutFile; $myReplace=[bool]$Replace; $myDefineOnly=[bool]$DefineOnly
. "$PSScriptRoot\Analyze-SwydoReport.ps1" -DefineOnly     # $script:CurSym, Format-Delta, Assert-NoCredential

$script:DmVersion = 2            # v1 entries could come from a request-asserted widget; the closer rejects them
# Facts versions for which "a count shown without decimals is an exact integer" has been verified against
# Analyze-SwydoReport.ps1 Format-Metric and real data. Filtered terms are refused for any other version.
$script:DmFactsVersions = @(3,4)
$script:DmMarker  = 'derived - not reported by the platform'
$script:DmInv     = [Globalization.CultureInfo]::InvariantCulture
$script:DmIdRx    = '\A[a-z0-9][a-z0-9_-]{0,63}\z'
$script:DmTimeDimRx = '(?i)^(day|date|week|month|quarter|year)$'

# NB (PS 5.1): an `if`/`switch` used as an expression UNROLLS a one-element array to a scalar, and
# indexing a scalar string or an ordered dictionary then silently returns the wrong thing. Every
# collection below is therefore built as @( if/switch ... ), and every caller wraps a function's
# collection result in @().

# ===================== pure number helpers =====================
function Get-DmLabels($list){
  # Filter labels as trimmed, non-blank STRINGS. Never a truthiness test: a JSON number 0 (an hour or
  # weekday row) is falsy and would silently empty the filter (review finding, reproduced on real facts).
  $out=@()
  foreach($x in @($list)){ if($null -eq $x){ continue }; $s=([string]$x).Trim(); if($s -ne ''){ $out+=$s } }
  return $out
}
function Get-DmDisplayNumber($s){
  # display string -> [double] or $null. Facts displays are invariant-formatted ("$4,125.03", "97.6").
  # STRICT: anything else ("1.234,56" from another culture, "1.2K", "(5)", "1e3") is not a number here -
  # a misread cell must fail reconciliation, not be off by a factor of a thousand.
  if($null -eq $s){ return $null }
  $t=([string]$s).Trim()
  if($t -notmatch ('^-?(?:[A-Z]{3} |[A-Z]{0,2}[\$' + [char]0x20AC + [char]0xA3 + '])?-?\d{1,3}(?:,\d{3})*(?:\.\d+)?%?$') -and $t -notmatch ('^-?(?:[A-Z]{3} |[A-Z]{0,2}[\$' + [char]0x20AC + [char]0xA3 + '])?-?\d+(?:\.\d+)?%?$')){ return $null }
  $neg=($t -match '^[^\d]*-')
  $core=$t -replace '[^0-9\.]',''
  if($core -eq '' -or $core -eq '.'){ return $null }
  $d=0.0
  if(-not [double]::TryParse($core,[Globalization.NumberStyles]::Float,$script:DmInv,[ref]$d)){ return $null }
  if($neg){ $d=-$d }
  return [double]$d
}
function Get-DmDisplayDecimals($s){
  if($null -eq $s){ return 0 }
  $m=[regex]::Match([string]$s,'\.(\d+)')
  if($m.Success){ return $m.Groups[1].Value.Length }
  return 0
}
function New-DmQty($lo,$hi,$decimals,$exact){
  return @{ lo=[double]$lo; hi=[double]$hi; mid=(([double]$lo+[double]$hi)/2.0); decimals=[int]$decimals; exact=[bool]$exact }
}
function Test-DmOverlap($a,$b){
  # two intervals describe the same quantity when they overlap (tiny epsilon for float noise)
  $eps=1e-9*[math]::Max(1.0,[math]::Max([math]::Abs($a.mid),[math]::Abs($b.mid)))
  return (($a.lo -le ($b.hi+$eps)) -and ($b.lo -le ($a.hi+$eps)))
}
function Add-DmQty($a,$b){ return (New-DmQty ($a.lo+$b.lo) ($a.hi+$b.hi) ([math]::Max($a.decimals,$b.decimals)) ($a.exact -and $b.exact)) }
function Sub-DmQty($a,$b){ return (New-DmQty ($a.lo-$b.hi) ($a.hi-$b.lo) ([math]::Max($a.decimals,$b.decimals)) ($a.exact -and $b.exact)) }
function Div-DmQty($a,$b){
  # $null when the denominator interval touches zero or below, or the numerator is negative (the
  # simple positive-interval rule below would be wrong there; refuse rather than guess).
  # (callers report WHICH side was the problem - see Join-DmQty)
  if($b.lo -le 0 -or $a.lo -lt 0){ return $null }
  # The POINT value is numerator over denominator - what anyone dividing the two stated inputs gets.
  # It is NOT the midpoint of the bounds: 1/x is convex, so that midpoint sits above the quotient and
  # drifts badly for a small rounded denominator (found by tools/Verify-DerivedMetrics.ps1 on real data).
  $q=New-DmQty ($a.lo/$b.hi) ($a.hi/$b.lo) 2 ($a.exact -and $b.exact)
  $q.mid=($a.mid/$b.mid)
  return $q
}
function Format-DmValue($v,$type,$currency,$decimals){
  if($null -eq $v){ return $null }
  $d=[double]$v
  switch([string]$type){
    'currency' {
      $sym = if($currency -and $script:CurSym[$currency]){ [string]$script:CurSym[$currency] } elseif($currency){ "$currency " } else { '$' }
      $body=[string]::Format($script:DmInv,'{0:N2}',[math]::Abs($d))
      if($d -lt 0 -and $body -ne '0.00'){ return ('-' + $sym + $body) }
      return ($sym + $body)
    }
    'percent' { return ([string]::Format($script:DmInv,'{0:N1}',($d*100)) + '%') }
    default   { return [string]::Format($script:DmInv,('{0:N' + [int]$decimals + '}'),$d) }
  }
}
function Format-DmQty($q,$type,$currency,$decimals){
  # -> @{ display; approximate; displayLow; displayHigh }
  $disp=Format-DmValue $q.mid $type $currency $decimals
  $lo=Format-DmValue $q.lo $type $currency $decimals
  $hi=Format-DmValue $q.hi $type $currency $decimals
  $o=[ordered]@{ display=$disp; approximate=[bool]($lo -ne $hi) }
  if($o.approximate){ $o.displayLow=$lo; $o.displayHigh=$hi }
  return $o
}
function Get-DmMonthsSpanned($start,$end){
  # inclusive month buckets touched by a yyyy-MM-dd window; $null when unparseable
  $a=[regex]::Match([string]$start,'^(\d{4})-(\d{2})'); $b=[regex]::Match([string]$end,'^(\d{4})-(\d{2})')
  if(-not $a.Success -or -not $b.Success){ return $null }
  return (([int]$b.Groups[1].Value-[int]$a.Groups[1].Value)*12 + ([int]$b.Groups[2].Value-[int]$a.Groups[2].Value) + 1)
}
function Get-DmWindow($meta,$which){
  # -> @{ start; end; label } for 'current'|'previous', from meta.periodResolved, else meta.<which>Period
  $label = if($which -eq 'current'){ [string]$meta.currentPeriod } else { [string]$meta.previousPeriod }
  $w=@{ start=$null; end=$null; label=$label }
  if($meta.periodResolved -and $meta.periodResolved.$which){ $w.start=[string]$meta.periodResolved.$which.start; $w.end=[string]$meta.periodResolved.$which.end }
  elseif($label -match '^(\d{4}-\d{2}-\d{2})\.\.(\d{4}-\d{2}-\d{2})$'){ $w.start=$Matches[1]; $w.end=$Matches[2] }
  return $w
}

function Test-DmFormatConvention {
  # Canary for the convention Get-DmCellQty relies on. -> $null when it holds, else what broke.
  # Catches both a changed Format-Metric and a non-English culture (which would print "1.234").
  $probe=@( @(2,'2'), @(1234,'1,234'), @(2.5,'2.5'), @(2.04,'2.0') )
  foreach($pr in $probe){ $got=[string](Format-Metric 'm' $null $pr[0] $null); if($got -cne $pr[1]){ return "Format-Metric prints $($pr[0]) as '$got' (expected '$($pr[1])')" } }
  return $null
}

# ===================== request validation (pure) =====================
function Get-DmRequests($obj){
  # normalise the three accepted shapes to the request objects (callers wrap in @())
  if($null -eq $obj){ return @() }
  if($obj -is [array]){ return @($obj) }
  if($obj.PSObject.Properties.Name -contains 'requests'){ return @($obj.requests) }
  return @($obj)
}
function Test-DmRequest($req){
  # -> problems (none = well-formed; callers wrap in @()). Malformed requests are a USAGE error
  # (exit 2): the translation from plain language is the model's job and a broken one must not half-run.
  $p=@()
  if($null -eq $req){ return @('request is null') }
  $names=@($req.PSObject.Properties.Name)
  $id=[string]$req.id
  # case-SENSITIVE and \z-anchored: the id becomes a report anchor, and "$" would admit a trailing newline
  if($id -cnotmatch $script:DmIdRx){ $p+="id '$($id.Trim())' must match $($script:DmIdRx)" }
  if([string]::IsNullOrWhiteSpace([string]$req.label)){ $p+="[$id] label is required" }
  $op=[string]$req.op
  if($op -notin @('ratio','sum','difference')){ $p+="[$id] op '$op' must be ratio, sum or difference" }
  $terms=@($req.terms | Where-Object { $null -ne $_ })
  if($op -eq 'ratio' -and $terms.Count -ne 2){ $p+="[$id] ratio needs exactly 2 terms (numerator, denominator); got $($terms.Count)" }
  if($op -eq 'difference' -and $terms.Count -lt 2){ $p+="[$id] difference needs at least 2 terms; got $($terms.Count)" }
  if($op -eq 'sum' -and $terms.Count -lt 1){ $p+="[$id] sum needs at least 1 term" }
  $i=0
  foreach($t in $terms){
    $i++
    $tn=@($t.PSObject.Properties.Name)
    if([string]::IsNullOrWhiteSpace([string]$t.metric) -and [string]::IsNullOrWhiteSpace([string]$t.metricId)){ $p+="[$id] term $i needs metric or metricId" }
    if($tn -contains 'filter' -and $null -ne $t.filter){
      $f=$t.filter
      if([string]::IsNullOrWhiteSpace([string]$f.dimension)){ $p+="[$id] term $i filter needs a dimension" }
      foreach($lv in (@($f.include) + @($f.exclude))){
        if($null -eq $lv){ continue }
        if(-not (($lv -is [string]) -or ($lv -is [int]) -or ($lv -is [long]) -or ($lv -is [double]) -or ($lv -is [decimal]))){ $p+="[$id] term $i filter labels must be strings or numbers"; break }
        if([string]::IsNullOrWhiteSpace([string]$lv)){ $p+="[$id] term $i filter has a blank label"; break }
      }
      $inc=@(Get-DmLabels $f.include)
      $exc=@(Get-DmLabels $f.exclude)
      if(($inc.Count -gt 0) -eq ($exc.Count -gt 0)){ $p+="[$id] term $i filter needs exactly one of include / exclude (non-empty)" }
      $lab=@($inc + $exc | ForEach-Object { $_.ToLowerInvariant() })
      if(@($lab | Select-Object -Unique).Count -ne $lab.Count){ $p+="[$id] term $i filter names the same row more than once" }
    }
  }
  if($names -contains 'format' -and $req.format -and ([string]$req.format -notin @('currency','number','percent'))){ $p+="[$id] format '$($req.format)' must be currency, number or percent" }
  if($names -contains 'decimals' -and $null -ne $req.decimals){ $dd=0; if(-not [int]::TryParse([string]$req.decimals,[ref]$dd) -or $dd -lt 0 -or $dd -gt 4){ $p+="[$id] decimals must be 0..4" } }
  # request strings are echoed into the facts; none may carry an HTML comment delimiter or a line break
  foreach($sv in @([string]$req.label,[string]$req.alongside,[string]$req.source,[string]$req.platform)){ if($sv -match '<!--|-->|[\r\n]'){ $p+="[$id] request text must not contain an HTML comment delimiter or a line break"; break } }
  return $p
}

# ===================== component lookup =====================
function Find-DmPlatform($facts,$req){
  # -> @{ platform; reason }
  $pls=@($facts.platforms)
  $want=[string]$req.platform
  if($want){
    $hit=@($pls | Where-Object { ([string]$_.id -ieq $want) -or ([string]$_.name -ieq $want) })
    if($hit.Count -eq 1){ return @{ platform=$hit[0]; reason=$null } }
    return @{ platform=$null; reason=("platform '$want' is not in the facts (available: " + (@($pls | ForEach-Object { [string]$_.id }) -join ', ') + ")") }
  }
  if($pls.Count -eq 1){ return @{ platform=$pls[0]; reason=$null } }
  return @{ platform=$null; reason=("the facts hold $($pls.Count) platforms and the request names none - a derived metric never blends platforms (available: " + (@($pls | ForEach-Object { [string]$_.id }) -join ', ') + ")") }
}
function Find-DmHeadline($platform,$term){
  # -> @{ headline; reason }. Exactly one account-level headline metric must match.
  $hits=@()
  if($platform.headline){
    foreach($k in $platform.headline.PSObject.Properties.Name){
      $h=$platform.headline.$k
      if($null -eq $h -or $h -is [bool] -or -not ($h.PSObject.Properties.Name -contains 'metric')){ continue }
      if($term.metricId){ if([string]$h.id -eq [string]$term.metricId){ $hits+=$h } }
      elseif([string]$h.metric -ieq ([string]$term.metric).Trim()){ $hits+=$h }
    }
  }
  $what = if($term.metricId){ [string]$term.metricId } else { [string]$term.metric }
  if($hits.Count -eq 1){ return @{ headline=$hits[0]; reason=$null } }
  if($hits.Count -gt 1){ return @{ headline=$null; reason=("metric '$what' is ambiguous on $($platform.name): " + $hits.Count + " headline metrics share that name - request it by metricId (" + (@($hits | ForEach-Object { [string]$_.id }) -join ', ') + ")") } }
  $avail=@(); if($platform.headline){ foreach($k in $platform.headline.PSObject.Properties.Name){ $h=$platform.headline.$k; if($h -and -not ($h -is [bool]) -and $h.metric){ $avail+=[string]$h.metric } } }
  return @{ headline=$null; reason=("metric '$what' has no account-level figure on $($platform.name) (available: " + ($avail -join ', ') + ")") }
}
function Test-DmSummable($platform,$h){
  # -> $null when summable, else the reason. The coverage record's aggClass is the analyzer's own
  # verdict; a ratio/percent/average is never summed, filtered or used as a ratio component here.
  $id=[string]$h.id
  $rec=$null
  if($platform.metrics -and ($platform.metrics.PSObject.Properties.Name -contains $id)){ $rec=$platform.metrics.$id }
  if($rec -and $rec.aggClass){
    if([string]$rec.aggClass -eq 'sum'){ return $null }
    return "'$($h.metric)' is not a summable metric (aggregation class '$($rec.aggClass)') - only summable totals can be components"
  }
  # Facts older than the coverage record: ask the analyzer's own classifier. Falling back to the
  # display TYPE would accept Cost / conversion or Avg. CPC (typed currency) as a summable amount.
  $cls=Get-AggregationClass $id $h.unit
  if($cls -eq 'sum'){ return $null }
  return "'$($h.metric)' is not a summable metric (aggregation class '$cls') - only summable totals can be components"
}
function Get-DmAccountQty($h,$which){
  # raw headline value, unit-normalised (micros -> currency units). $null when absent.
  $raw = if($which -eq 'current'){ $h.current } else { $h.previous }
  if($which -eq 'previous' -and $h.hasComparison -ne $true){ return $null }
  if($null -eq $raw){ return $null }
  $v=[double]$raw
  if([string]$h.unit -eq 'micros'){ $v=$v/1e6 }
  $disp = if($which -eq 'current'){ [string]$h.displayCurrent } else { [string]$h.displayPrevious }
  $q=New-DmQty $v $v (Get-DmDisplayDecimals $disp) $true
  $q.display=$disp
  return $q
}
function Get-DmCellQty($cell,$which,$unit){
  # a breakdown cell -> quantity. raw/rawPrevious (when a facts version carries them) are exact.
  # Otherwise the display string is known to +/- half its last displayed digit - EXCEPT a count shown
  # with no decimals: Analyze-SwydoReport.ps1 Format-Metric prints a unit-null value as N0 only when
  # it IS an integer (to 1e-9) and as N1 otherwise, so "517" is exactly 517. (Micros always print N2
  # and fractions N1%, so they never reach that branch.) Treating integers as +/-0.5 let rows that do
  # not add up to the account pass reconciliation, and hedged exact figures.
  if($null -eq $cell){ return $null }
  $names=@($cell.PSObject.Properties.Name)
  if($which -eq 'current'){ $rawN='raw'; $dispN='display' } else { $rawN='rawPrevious'; $dispN='displayPrevious' }
  if(-not ($names -contains $dispN) -or $null -eq $cell.$dispN){ return $null }
  $disp=[string]$cell.$dispN
  $dec=Get-DmDisplayDecimals $disp
  if(($names -contains $rawN) -and $null -ne $cell.$rawN){ $v=[double]$cell.$rawN; $q=New-DmQty $v $v $dec $true; $q.display=$disp; return $q }
  $d=Get-DmDisplayNumber $disp
  if($null -eq $d){ return $null }
  if(($disp.Trim() -match '^-?(\d{1,3}(,\d{3})*|\d+)$') -and [string]$unit -ne 'micros' -and [string]$unit -ne 'fraction'){ $q=New-DmQty $d $d 0 $true; $q.display=$disp; return $q }
  $half=[math]::Pow(10,-$dec)/2.0
  $q=New-DmQty ($d-$half) ($d+$half) $dec $false
  $q.display=$disp
  return $q
}
function Get-DmCellName($bd,$metricId){
  # the `values` key that holds this metric on this widget, or $null. metricIds[]/metricNames[] are
  # index-aligned; a display name shared by two metrics on the widget is NOT addressable by name.
  $ids=@($bd.metricIds); $nms=@($bd.metricNames)
  $idx=[array]::IndexOf($ids,[string]$metricId)
  if($idx -lt 0 -or $idx -ge $nms.Count){ return $null }
  $name=[string]$nms[$idx]
  if([string]::IsNullOrWhiteSpace($name)){ return $null }
  if(@($nms | Where-Object { [string]$_ -eq $name }).Count -ne 1){ return $null }
  return $name
}
function Get-DmRowCell($row,$name){
  if(-not $row.values){ return $null }
  $p=$row.values.PSObject.Properties[$name]
  if($p){ return $p.Value }
  return $null
}
function Get-DmRowsSum($rows,$cellName,$which,$unit){
  # sum the metric over rows; a row with no cell for the period counts as zero (the caller's
  # reconciliation against the account total is what makes that safe).
  # A cell that HAS a display for the period but cannot be read strictly is counted as unreadable, and
  # the caller refuses - it is never silently zero.
  $acc=New-DmQty 0 0 0 $true
  $n=0; $bad=0
  $dispN = if($which -eq 'current'){ 'display' } else { 'displayPrevious' }
  foreach($r in @($rows)){
    $cell=Get-DmRowCell $r $cellName
    $q=Get-DmCellQty $cell $which $unit
    if($null -eq $q){
      if($cell -and ($cell.PSObject.Properties.Name -contains $dispN) -and -not [string]::IsNullOrWhiteSpace([string]$cell.$dispN)){ $bad++ }
      continue
    }
    $acc=Add-DmQty $acc $q; $n++
  }
  $acc.cells=$n; $acc.unreadable=$bad
  return $acc
}

# ---- ROWS route: a complete single-dimension breakdown that reconciles with the account figure ----
function Resolve-DmRowsRoute($platform,$h,$filter,$which,$acct,$onlyWidgetId){
  # $onlyWidgetId: the breakdown chosen for the CURRENT period. The previous period must come from the
  # same widget, or a delta would compare two different breakdowns.
  $dim=[string]$filter.dimension; $unit=$h.unit
  $cands=@()
  foreach($bd in @($platform.breakdowns)){
    $dims=@($bd.dimensions)
    if($dims.Count -ne 1 -or ([string]$dims[0] -ine $dim)){ continue }
    if($onlyWidgetId -and ([string]$bd.widgetId -ne [string]$onlyWidgetId)){ continue }
    $cn=Get-DmCellName $bd $h.id
    if($cn){ $cands+=@{ bd=$bd; cell=$cn } }
  }
  if($cands.Count -eq 0){
    $why="no breakdown by '$dim' alone carries $($h.metric) on $($platform.name)"
    # name what IS there, so the user knows a widget sliced that way exists but cannot be used on its own
    $multi=@(@($platform.breakdowns) | Where-Object { $d=@($_.dimensions | ForEach-Object { [string]$_ }); $d.Count -gt 1 -and (@($d | Where-Object { $_ -ieq $dim }).Count -gt 0) -and (Get-DmCellName $_ $h.id) } | ForEach-Object { "'" + (@($_.dimensions) -join ' / ') + "'" } | Select-Object -Unique)
    if($multi.Count -gt 0){ $why+=("; widget(s) sliced as " + ($multi -join ', ') + " carry it, but a widget total cannot say which rows it covers, so it is not used on its own") }
    return @{ ok=$false; reason=$why }
  }
  $inc=@(Get-DmLabels $filter.include); $exc=@(Get-DmLabels $filter.exclude)
  $isInclude=($inc.Count -gt 0)
  $wanted=@(if($isInclude){ $inc } else { $exc })
  # invariant, whatever validation did: an empty filter must never fall through to the account total
  if($wanted.Count -eq 0){ return @{ ok=$false; reason="the filter on '$dim' names no row" } }
  $firstFail=$null; $oks=@()
  foreach($c in $cands){
    $bd=$c.bd; $rows=@($bd.rows)
    $fail=$null
    if([int]$bd.shown -ne [int]$bd.rowCount -or $rows.Count -ne [int]$bd.rowCount){ $fail="the '$dim' breakdown is truncated in the facts ($($rows.Count) of $($bd.rowCount) rows) - rows cannot be summed" }
    $matched=@()
    if(-not $fail){
      foreach($lbl in $wanted){
        $m=@($rows | Where-Object { ([string]$_.label).Trim() -ieq $lbl })
        if($m.Count -ne 1){ $fail=("a requested row matched $($m.Count) rows of the '$dim' breakdown (available: " + (@($rows | ForEach-Object { "'" + [string]$_.label + "'" }) -join ', ') + ")"); break }
        if(@($matched | Where-Object { [object]::ReferenceEquals($_,$m[0]) }).Count -gt 0){ $fail="the filter on '$dim' names the same row more than once"; break }
        $matched+=$m[0]
      }
    }
    $all=$null
    if(-not $fail){
      $all=Get-DmRowsSum $rows $c.cell $which $unit
      if($all.unreadable -gt 0){ $fail="the '$dim' breakdown has $($all.unreadable) $which-period cell(s) that cannot be read as a number" }
      elseif($all.cells -eq 0){ $fail="the '$dim' breakdown has no $which-period values for $($h.metric)" }
      elseif(-not (Test-DmOverlap $all $acct)){
        $fail=("the '$dim' rows do not reconcile with the account $($h.metric) for the $which period (rows sum to " + (Format-DmValue $all.mid 'number' $null $all.decimals) + " against " + $acct.display + ") - the breakdown does not partition the account figure")
      }
    }
    $qty=$null; $method='rows-sum'; $sel=@(); $rest=@()
    if(-not $fail){
      $isSel={ param($r) (@($matched | Where-Object { [object]::ReferenceEquals($_,$r) }).Count -gt 0) -eq $isInclude }
      $sel=@($rows | Where-Object { & $isSel $_ })
      $rest=@($rows | Where-Object { -not (& $isSel $_) })
      $qty=Get-DmRowsSum $sel $c.cell $which $unit
      # Second, equally valid bound on the same quantity: the (exact) account figure minus the OTHER
      # rows. The rows were just shown to partition the account, so the true value lies in BOTH
      # intervals: keep the intersection. When the other rows are whole numbers this pins the subtotal
      # exactly. An empty intersection means the two bounds contradict each other - refuse, never clamp.
      $comp=Sub-DmQty $acct (Get-DmRowsSum $rest $c.cell $which $unit)
      if(-not (Test-DmOverlap $comp $qty)){
        $fail=("the '$dim' rows are inconsistent for the $which period: the requested rows sum to between " + (Format-DmValue $qty.lo 'number' $null ($qty.decimals+2)) + " and " + (Format-DmValue $qty.hi 'number' $null ($qty.decimals+2)) + ", but the account figure minus the other rows is between " + (Format-DmValue $comp.lo 'number' $null ($qty.decimals+2)) + " and " + (Format-DmValue $comp.hi 'number' $null ($qty.decimals+2)))
      } else {
        $lo=[math]::Max($comp.lo,$qty.lo); $hi=[math]::Min($comp.hi,$qty.hi); if($hi -lt $lo){ $hi=$lo }
        $tiny=1e-9*[math]::Max(1.0,[math]::Abs($qty.mid))
        if(($lo -gt ($qty.lo+$tiny)) -or ($hi -lt ($qty.hi-$tiny))){
          $mid=[math]::Min([math]::Max($qty.mid,$lo),$hi)
          $exact=(($hi-$lo) -le $tiny)
          if($exact){ $mid=$comp.mid; $lo=$mid; $hi=$mid }
          $dec=$qty.decimals; if($exact -and ([math]::Abs($mid-[math]::Round($mid,$dec)) -gt 1e-9)){ $dec=[math]::Max($dec,2) }
          $qty=New-DmQty $lo $hi $dec $exact; $qty.mid=$mid
          $method='account-minus-other-rows'
        }
      }
    }
    if($fail){ if(-not $firstFail){ $firstFail=$fail }; continue }
    $cellOf={ param($r) $q=Get-DmCellQty (Get-DmRowCell $r $c.cell) $which $unit; [ordered]@{ label=[string]$r.label; display=$(if($q){ $q.display } else { $null }) } }
    $oks+=@{ ok=$true; qty=$qty; method=$method; widgetId=[string]$bd.widgetId; dimension=[string]@($bd.dimensions)[0]
             rows=@($sel | ForEach-Object { & $cellOf $_ }); otherRows=@($rest | ForEach-Object { & $cellOf $_ })
             labels=@($matched | ForEach-Object { [string]$_.label }); isInclude=$isInclude
             allRowsDisplay=(Format-DmValue $all.mid 'number' $null $all.decimals); accountDisplay=$acct.display }
  }
  if($oks.Count -eq 0){ return @{ ok=$false; reason=$firstFail } }
  # Two breakdowns by the same dimension can both reconcile with the account and still split it
  # differently (differently filtered or labelled widgets). Never pick one silently.
  foreach($o in $oks){ if(-not (Test-DmOverlap $o.qty $oks[0].qty)){ return @{ ok=$false; reason=("two '$dim' breakdowns both reconcile with the account $($h.metric) but give different subtotals for the requested rows (" + (Format-DmValue $oks[0].qty.mid 'number' $null $oks[0].qty.decimals) + " and " + (Format-DmValue $o.qty.mid 'number' $null $o.qty.decimals) + ") - the request is ambiguous") } } }
  return $oks[0]
}

# ---- WIDGET cross-check: totals of other widgets that slice the metric by the filter dimension ----
function Get-DmWidgetTotals($platform,$h,$filter,$which,$meta,$explicitId){
  # -> one record per candidate widget (callers wrap in @())
  $dim=[string]$filter.dimension; $unit=$h.unit
  $out=@()
  foreach($bd in @($platform.breakdowns)){
    $dims=@($bd.dimensions | ForEach-Object { [string]$_ })
    $isExplicit = ($explicitId -and ([string]$bd.widgetId -eq [string]$explicitId))
    $auto = ($dims.Count -gt 1 -and (@($dims | Where-Object { $_ -ieq $dim }).Count -gt 0))
    if(-not $isExplicit -and -not $auto){ continue }
    $w=[ordered]@{ widgetId=[string]$bd.widgetId; dimensions=($dims -join ' / '); explicit=[bool]$isExplicit; usable=$false; reason=$null; qty=$null; display=$null }
    $cn=Get-DmCellName $bd $h.id
    $rows=@($bd.rows)
    if(-not $cn){ $w.reason="widget does not carry $($h.metric) addressably"; $out+=$w; continue }
    $tot=Get-DmRowsSum $rows $cn $which $unit
    if($tot.cells -gt 0){ $w.display=(Format-DmValue $tot.mid 'number' $null $tot.decimals) }
    if([int]$bd.shown -ne [int]$bd.rowCount -or $rows.Count -ne [int]$bd.rowCount){ $w.reason="widget rows are truncated in the facts ($($rows.Count) of $($bd.rowCount))"; $out+=$w; continue }
    if($tot.unreadable -gt 0){ $w.reason="widget has cells that cannot be read as numbers"; $out+=$w; continue }
    if($tot.cells -eq 0){ $w.reason="widget has no $which-period values"; $out+=$w; continue }
    # A time-SERIES dimension anywhere in the widget (Month, Week, Date ... - not a cyclical one such
    # as "Day of the week") lines its previous column up bucket by bucket. That column is the previous
    # PERIOD only when the widget is one row per month and both windows span exactly that many months.
    $series=@($dims | Where-Object { $_ -match $script:DmTimeDimRx })
    if($which -eq 'previous' -and $series.Count -gt 0){
      if($series.Count -eq 1 -and $series[0] -imatch '^month$'){
        $pw=Get-DmWindow $meta 'previous'; $cw=Get-DmWindow $meta 'current'
        $pm=Get-DmMonthsSpanned $pw.start $pw.end; $cm=Get-DmMonthsSpanned $cw.start $cw.end
        if($null -eq $pm -or $null -eq $cm){ $w.reason="the period windows are not recorded, so the widget's previous column cannot be aligned"; $out+=$w; continue }
        if($pm -ne $rows.Count -or $cm -ne $rows.Count){
          $w.reason=("the widget is bucketed by month with $($rows.Count) row(s) but the previous window $($pw.label) spans $pm month bucket(s), so its row-aligned previous column does not cover the whole previous period")
          $out+=$w; continue
        }
      } else {
        $w.reason="the widget is bucketed by $($series -join ' / '); the alignment of its previous column to the previous window cannot be verified"
        $out+=$w; continue
      }
    }
    $w.usable=$true; $w.qty=$tot
    $out+=$w
  }
  return $out
}

# ===================== term resolution (both periods) =====================
function Get-DmTermPhrase($metricName,$labels,$isInclude){
  # Built ONLY from names that are in the facts (the headline metric, the matched row labels) - never
  # from the request's own spelling, so nothing typed into a request can reach the formula.
  if(@($labels).Count -eq 0){ return [string]$metricName }
  $l=@($labels | ForEach-Object { "'" + [string]$_ + "'" })
  $joined = if($l.Count -le 1){ ($l -join '') } else { ((($l[0..($l.Count-2)]) -join ', ') + ' and ' + $l[-1]) }
  if($isInclude){ return ([string]$metricName + ' from ' + $joined + ' only') }
  return ([string]$metricName + ' excluding ' + $joined)
}
function Resolve-DmTerm($platform,$meta,$term,$wantPrevious){
  # -> @{ ok; reason; headline; phrase; type; currency; current=@{...}; previous=@{ ok; reason; ... } }
  # each period: @{ ok; reason; qty; display; source; crossCheck; notes }
  $fh=Find-DmHeadline $platform $term
  if(-not $fh.headline){ return @{ ok=$false; reason=$fh.reason } }
  $h=$fh.headline
  $ns=Test-DmSummable $platform $h
  if($ns){ return @{ ok=$false; reason=$ns } }
  $scope = if($h.canonical){ [string]$h.canonical.scope } else { '' }
  if($scope -and $scope -ne 'account' -and $scope -notmatch '^table-total:'){ return @{ ok=$false; reason="'$($h.metric)' is scoped '$scope', not an account-level total" } }
  if($h.canonical -and $h.canonical.period -and $meta.currentPeriod -and ([string]$h.canonical.period -ne [string]$meta.currentPeriod)){
    return @{ ok=$false; reason="'$($h.metric)' covers $($h.canonical.period), not the report period $($meta.currentPeriod)" }
  }
  $type = if([string]$h.type -eq 'currency'){ 'currency' } else { 'number' }
  $res=@{ ok=$true; reason=$null; headline=$h; phrase=[string]$h.metric; type=$type; currency=$(if($type -eq 'currency'){ [string]$h.currency } else { $null }); current=$null; previous=$null }
  $hasFilter=[bool]$term.filter
  $explicit = if($term.PSObject.Properties.Name -contains 'widget'){ [string]$term.widget } else { '' }
  if($explicit -and -not $hasFilter){ return @{ ok=$false; reason="a term names a cross-check widget but has no filter" } }
  if($hasFilter -and ($script:DmFactsVersions -notcontains [int]$meta.factsVersion)){
    # Row arithmetic leans on how the analyzer formats a cell (a count without decimals is an exact
    # integer). That is verified for the pinned facts versions only; never guess for another one.
    return @{ ok=$false; reason="filtered terms need facts version $($script:DmFactsVersions -join ' or '); these facts are version '$($meta.factsVersion)' - re-run Analyze-SwydoReport.ps1 on the extraction" }
  }
  $tracked=@()      # widget ids that stand for this filtered value: the one the request names, plus any that matched in the current period
  $rowsWidget=$null # the breakdown the current period resolved from; the previous period must use the same one
  foreach($which in @('current','previous')){
    if($which -eq 'previous' -and -not $wantPrevious){ $res.previous=@{ ok=$false; reason='no trusted previous period in the facts' }; continue }
    $acct=Get-DmAccountQty $h $which
    if($null -eq $acct){
      $pr=@{ ok=$false; reason="'$($h.metric)' has no $which-period account figure" }
      if($which -eq 'current'){ return @{ ok=$false; reason=$pr.reason } }
      $res.previous=$pr; continue
    }
    $hsrc=[ordered]@{ kind='headline'; metricId=[string]$h.id; widgetId=$(if($h.canonical){ [string]$h.canonical.sourceWidgetId } else { $null }); scope=$scope }
    if(-not $hasFilter){
      $res.$which=@{ ok=$true; qty=$acct; display=$acct.display; source=$hsrc; crossCheck='n/a'; notes=@() }
      continue
    }
    if($which -eq 'previous' -and ([string]$term.filter.dimension -match $script:DmTimeDimRx)){
      # rows of a time-series breakdown carry a bucket-aligned previous column, not the previous period
      $res.previous=@{ ok=$false; reason="the '$($term.filter.dimension)' breakdown is a time series: its previous column lines up bucket by bucket and is not the previous period for a given row" }
      continue
    }
    # The ROWS route is the only source of a filtered value. A widget - even one the request names -
    # can only confirm or contradict it: the facts do not record widget filters, so a widget total on
    # its own proves nothing about WHICH rows it covers.
    $rows=Resolve-DmRowsRoute $platform $h $term.filter $which $acct $rowsWidget
    $wts=@(Get-DmWidgetTotals $platform $h $term.filter $which $meta $explicit)
    $notes=@(); $pr=$null
    $ew=@(); if($explicit){ $ew=@($wts | Where-Object { $_.explicit }) }
    if($explicit -and $ew.Count -eq 0){ $pr=@{ ok=$false; reason="the request names a cross-check widget that is not a breakdown of $($platform.name) in the facts" } }
    elseif($explicit -and -not $ew[0].usable){ $pr=@{ ok=$false; reason="the cross-check widget the request names cannot be used for the $which period: $($ew[0].reason)" } }
    elseif(-not $rows.ok){ $pr=@{ ok=$false; reason=$rows.reason } }
    else {
      if($which -eq 'current'){
        $rowsWidget=$rows.widgetId
        $res.phrase=Get-DmTermPhrase $h.metric $rows.labels $rows.isInclude
        foreach($w in $wts){ if($w.explicit){ $tracked+=$w.widgetId } elseif($w.usable -and (Test-DmOverlap $w.qty $rows.qty)){ $tracked+=$w.widgetId } }
      }
      $agree=@(); $disagree=@()
      foreach($w in @($wts | Where-Object { $tracked -contains $_.widgetId })){
        if(-not $w.usable){ $notes+=("widget '$($w.dimensions)' was not used as a cross-check for the $which period: $($w.reason)" + $(if($w.display){ " (it shows $($w.display))" } else { '' })); continue }
        if(Test-DmOverlap $w.qty $rows.qty){ $agree+=$w } else { $disagree+=$w }
      }
      $rowsDisp=Format-DmValue $rows.qty.mid 'number' $null $rows.qty.decimals
      if($disagree.Count -gt 0){
        $d=$disagree[0]
        $pr=@{ ok=$false; reason=("routes disagree for the $which period: the '$($rows.dimension)' rows give $rowsDisp but widget '$($d.dimensions)' gives $($d.display)") }
      } else {
        $src=[ordered]@{ kind='breakdown-rows'; method=$rows.method; metricId=[string]$h.id; widgetId=$rows.widgetId; dimension=$rows.dimension; rows=@($rows.rows)
                         reconciledWith=[ordered]@{ allRows=$rows.allRowsDisplay; account=$rows.accountDisplay } }
        if($rows.method -eq 'account-minus-other-rows'){
          $src.otherRows=@($rows.otherRows)
          $notes+=("the $which-period subtotal for $($res.phrase) is the account $($h.metric) ($($rows.accountDisplay)) minus the other row(s), which pins it more tightly than adding its own rounded rows")
        }
        if($agree.Count -gt 0){ $src.corroboratedBy=@($agree | ForEach-Object { [ordered]@{ widgetId=$_.widgetId; dimensions=$_.dimensions; display=$_.display } }) }
        $disp = if($type -eq 'currency'){ Format-DmValue $rows.qty.mid 'currency' $h.currency 2 } else { $rowsDisp }
        $pr=@{ ok=$true; qty=$rows.qty; display=$disp; source=$src; crossCheck=$(if($agree.Count -gt 0){ 'agreed' } else { 'single-route' }); notes=$notes }
      }
    }
    if($which -eq 'current' -and -not $pr.ok){ return @{ ok=$false; reason=$pr.reason } }
    $res.$which=$pr
  }
  return $res
}

# ===================== request resolution =====================
function Join-DmQty($op,$qs,$phrases){
  # -> @{ q; why }. q is $null when the result is undefined, and why says which side was the problem.
  if($op -eq 'ratio'){
    if($qs[1].lo -le 0){ return @{ q=$null; why="the denominator ($($phrases[1])) is zero or not positive" } }
    if($qs[0].lo -lt 0){ return @{ q=$null; why="the numerator ($($phrases[0])) is negative or not known to be non-negative" } }
    return @{ q=(Div-DmQty $qs[0] $qs[1]); why=$null }
  }
  $acc=$qs[0]
  for($i=1;$i -lt $qs.Count;$i++){ if($op -eq 'sum'){ $acc=Add-DmQty $acc $qs[$i] } else { $acc=Sub-DmQty $acc $qs[$i] } }
  return @{ q=$acc; why=$null }
}
function Format-DmDelta($d){
  # invariant culture, one decimal, explicit sign (the house delta shape, without the caller's culture)
  return ([string]::Format($script:DmInv,'{0:+0.0;-0.0;0.0}',[math]::Round([double]$d,1)) + '%')
}
function Resolve-DmRequest($facts,$req){
  $id=[string]$req.id
  $entry=[ordered]@{ id=$id; v=$script:DmVersion; label=[string]$req.label; status='refused'; derived=$true; marker=$script:DmMarker }
  $notes=@()
  $meta=$facts.meta
  if($req.PSObject.Properties.Name -contains 'source' -and $req.source){ $entry.requestSource=[string]$req.source }
  $refuse={ param($why) $entry.reasons=@($why); return $entry }

  if($meta -and ($meta.PSObject.Properties.Name -contains 'extractionComplete') -and ($meta.extractionComplete -eq $false)){
    return (& $refuse 'the facts declare extractionComplete=false - nothing is derived from a partial extraction')
  }
  if($entry.requestSource -and ($entry.requestSource -match '^annotation:(.+)$')){
    $aid=$Matches[1]
    if(@(@($meta.annotations) | Where-Object { [string]$_.aid -eq $aid }).Count -eq 0){ return (& $refuse "the request's source names an annotation that is not in the facts") }
  }
  $fp=Find-DmPlatform $facts $req
  if(-not $fp.platform){ return (& $refuse $fp.reason) }
  $pl=$fp.platform
  $entry.platformId=[string]$pl.id; $entry.platformName=[string]$pl.name
  $op=[string]$req.op; $entry.op=$op
  $wantPrev = ($meta -and ([string]$meta.compareBasis -ne 'untrusted') -and ($meta.hasComparison -ne $false) -and ($pl.hasComparison -ne $false))

  $terms=@($req.terms | Where-Object { $null -ne $_ })
  $rt=@()
  foreach($t in $terms){ $r=Resolve-DmTerm $pl $meta $t $wantPrev; if(-not $r.ok){ return (& $refuse $r.reason) }; $rt+=$r }

  # ---- compatibility: types and currency ----
  $curCodes=@($rt | Where-Object { $_.type -eq 'currency' } | ForEach-Object { [string]$_.currency } | Select-Object -Unique)
  if($curCodes.Count -gt 1){ return (& $refuse ("components are in different currencies (" + ($curCodes -join ', ') + ")")) }
  $types=@($rt | ForEach-Object { $_.type } | Select-Object -Unique)
  $type=$null; $currency=$null
  if($op -eq 'ratio'){
    if($rt[0].type -eq 'currency' -and $rt[1].type -ne 'currency'){ $type='currency'; $currency=$rt[0].currency } else { $type='number' }
  } else {
    if($types.Count -gt 1){ return (& $refuse ("cannot $op a currency amount and a count (" + (@($rt | ForEach-Object { $_.phrase + ' is ' + $_.type }) -join '; ') + ")")) }
    $type=$types[0]; if($type -eq 'currency'){ $currency=$curCodes[0] }
  }
  $fmt = if($req.PSObject.Properties.Name -contains 'format' -and $req.format){ [string]$req.format } else { $type }
  if($fmt -eq 'currency' -and $type -ne 'currency'){ return (& $refuse "format 'currency' was requested but the result of these components is not a currency amount") }
  if($fmt -eq 'percent' -and -not ($op -eq 'ratio' -and $rt[0].type -eq $rt[1].type)){ return (& $refuse "format 'percent' needs a ratio of two like quantities") }
  if($fmt -ne 'currency' -and $type -eq 'currency'){ return (& $refuse "the result is a currency amount; format '$fmt' would mislabel it") }
  $type=$fmt
  $hasDec=($req.PSObject.Properties.Name -contains 'decimals' -and $null -ne $req.decimals)
  if($hasDec -and $type -ne 'number'){ return (& $refuse "decimals applies only to a plain number result; a $type result has a fixed format") }
  $entry.type=$type; if($currency){ $entry.currency=$currency }

  # ---- formula in plain words (facts names only) ----
  $ph=@($rt | ForEach-Object { $_.phrase })
  switch($op){
    'ratio'      { $entry.formula=($ph[0] + ' divided by ' + $ph[1]) }
    'sum'        { $entry.formula=($ph -join ' plus ') }
    'difference' { $entry.formula=($ph -join ' minus ') }
  }

  # ---- per-period compute ----
  $roles = @(switch($op){ 'ratio' { 'numerator','denominator' } default { 1..$rt.Count | ForEach-Object { "term$_" } } })
  $periodOut=@{}
  foreach($which in @('current','previous')){
    $win=Get-DmWindow $meta $which
    $bad=@($rt | Where-Object { -not $_.$which.ok })
    if($bad.Count -gt 0){
      $periodOut[$which]=@{ ok=$false; reason=[string]$bad[0].$which.reason }
      continue
    }
    $j=Join-DmQty $op @($rt | ForEach-Object { $_.$which.qty }) $ph
    $q=$j.q
    if($null -eq $q){ $periodOut[$which]=@{ ok=$false; reason="$($j.why) in the $which period" }; continue }
    $dec = if($hasDec){ [int]$req.decimals } elseif($op -eq 'ratio'){ 2 } else { $q.decimals }
    $f=Format-DmQty $q $type $currency $dec
    $block=[ordered]@{ period=$win.label; display=$f.display; approximate=$f.approximate }
    if($f.approximate){ $block.displayLow=$f.displayLow; $block.displayHigh=$f.displayHigh }
    $ccs=@($rt | ForEach-Object { $_.$which.crossCheck } | Where-Object { $_ -ne 'n/a' })
    $block.crossCheck = if($ccs.Count -eq 0){ 'n/a' } elseif(@($ccs | Where-Object { $_ -ne 'agreed' }).Count -eq 0){ 'agreed' } else { 'single-route' }
    $inputs=@()
    for($i=0;$i -lt $rt.Count;$i++){ $inputs+=[ordered]@{ role=$roles[$i]; term=$rt[$i].phrase; display=$rt[$i].$which.display; type=$rt[$i].type; source=$rt[$i].$which.source } }
    $block.inputs=@($inputs)
    foreach($r in $rt){ foreach($n in @($r.$which.notes)){ if($n){ $notes+=[string]$n } } }
    if($q.mid -ne 0 -and (Get-DmDisplayNumber $f.display) -eq 0){ $notes+="the $which-period figure is not zero but rounds to zero at the displayed precision" }
    $periodOut[$which]=@{ ok=$true; qty=$q; block=$block }
  }
  if(-not $periodOut['current'].ok){ return (& $refuse $periodOut['current'].reason) }
  $entry.status='resolved'
  $entry.current=$periodOut['current'].block
  if($entry.current.approximate){ $notes+="the current-period figure is approximate: an input is only known to its displayed precision, so the true value lies between $($entry.current.displayLow) and $($entry.current.displayHigh)" }
  $cmp=[ordered]@{ hasComparison=$false }
  if($periodOut['previous'].ok){
    $entry.previous=$periodOut['previous'].block
    if($entry.previous.approximate){ $notes+="the previous-period figure is approximate: the true value lies between $($entry.previous.displayLow) and $($entry.previous.displayHigh)" }
    $c=$periodOut['current'].qty; $p=$periodOut['previous'].qty
    if($p.lo -le 0){ $cmp.reason='the previous-period value is zero or negative, so a percentage change is undefined' }
    elseif($c.lo -lt 0){ $cmp.reason='the current-period value is negative, so a percentage change would mislead' }
    else {
      $cmp.hasComparison=$true; $cmp.displayDelta=(Format-DmDelta ((($c.mid/$p.mid)-1)*100))
      $lo=(Format-DmDelta ((($c.lo/$p.hi)-1)*100)); $hi=(Format-DmDelta ((($c.hi/$p.lo)-1)*100))
      $cmp.approximate=[bool]($lo -ne $hi)
      if($cmp.approximate){ $cmp.displayDeltaLow=$lo; $cmp.displayDeltaHigh=$hi }
    }
  } else {
    $entry.previous=[ordered]@{ status='unresolved'; reason=[string]$periodOut['previous'].reason }
    $cmp.reason=("no comparison: the previous period did not resolve (" + [string]$periodOut['previous'].reason + ")")
  }
  $entry.comparison=$cmp

  # ---- the REPORTED counterpart to present alongside (already-traceable headline strings) ----
  if($req.PSObject.Properties.Name -contains 'alongside' -and $req.alongside){
    $fa=Find-DmHeadline $pl ([pscustomobject]@{ metric=[string]$req.alongside; metricId=$null })
    if($fa.headline){
      $a=$fa.headline; $aCmp=[bool]($a.hasComparison -eq $true)
      $rep=[ordered]@{ metric=[string]$a.metric; metricId=[string]$a.id; type=[string]$a.type; hasComparison=$aCmp; displayCurrent=$a.displayCurrent }
      if($aCmp){ $rep.displayPrevious=$a.displayPrevious; $rep.displayDelta=$a.displayDelta }
      $entry.reported=$rep
    }
    # NB: the request's own text is never echoed into notes - a note is quotable in the report
    else { $notes+='the reported metric the request asked to show alongside has no account-level figure in the facts, so none is given' }
  }
  $entry.notes=@($notes | Select-Object -Unique)
  return $entry
}

# ===================== facts text splice (byte-preserving) =====================
function Find-DmTopLevelMember($text,$name){
  # Locate a TOP-LEVEL member "name": <value> in a JSON object's text. -> @{ keyStart; valueEnd } or $null.
  # String-aware depth scan; never a regex over the whole document.
  $depth=0; $inStr=$false; $esc=$false; $strStart=-1; $n=$text.Length
  $keyStart=-1; $pendingKey=$null
  for($i=0;$i -lt $n;$i++){
    $ch=$text[$i]
    if($inStr){
      if($esc){ $esc=$false } elseif($ch -eq '\'){ $esc=$true } elseif($ch -eq '"'){
        $inStr=$false
        if($depth -eq 1 -and $keyStart -lt 0){ $pendingKey=@{ start=$strStart; text=$text.Substring($strStart+1,$i-$strStart-1) } }
      }
      continue
    }
    switch($ch){
      '"' { $inStr=$true; $strStart=$i }
      ':' { if($depth -eq 1 -and $pendingKey -and $keyStart -lt 0 -and $pendingKey.text -eq $name){ $keyStart=$pendingKey.start }; $pendingKey=$null }
      '{' { $depth++ }
      '[' { $depth++ }
      ']' { $depth-- }
      '}' { $depth--; if($depth -eq 0 -and $keyStart -ge 0){ return @{ keyStart=$keyStart; valueEnd=$i } } }
      ',' { if($depth -eq 1){ if($keyStart -ge 0){ return @{ keyStart=$keyStart; valueEnd=$i } }; $pendingKey=$null } }
    }
  }
  return $null
}
function Set-DmFactsBlock($factsText,$blockJson){
  # Remove any existing top-level derivedMetrics member, then append the new one as the LAST member.
  $t=[string]$factsText
  $span=Find-DmTopLevelMember $t 'derivedMetrics'
  if($span){
    $head=$t.Substring(0,$span.keyStart).TrimEnd()
    $tail=$t.Substring($span.valueEnd)                 # starts at ',' (more members) or the closing '}'
    if($tail.StartsWith(',')){ $tail=$tail.Substring(1) }       # drop OUR trailing comma, keep theirs before us
    elseif($head.EndsWith(',')){ $head=$head.Substring(0,$head.Length-1) }
    $t=$head + $tail
  }
  $end=$t.LastIndexOf('}')
  if($end -lt 0){ throw 'facts text is not a JSON object' }
  $head=$t.Substring(0,$end).TrimEnd()
  $sep = if($head.EndsWith('{')){ '' } else { ',' }
  return ($head + $sep + "`n  " + '"derivedMetrics": ' + $blockJson + "`n" + '}' + "`n")
}
function ConvertTo-DmBlockJson($entries){
  $block=[ordered]@{ tool='Resolve-SwydoMetric.ps1'; version=$script:DmVersion; marker=$script:DmMarker; entries=@($entries) }
  return (ConvertTo-Json -InputObject $block -Depth 20)
}
function Test-DmReplaceSafe($existing,$reqs){
  # -Replace drops every entry the request file does not re-request. An entry a CLIENT NOTE asked for
  # (requestSource annotation:X) may not vanish that way. -> ids that would be silently dropped.
  $kept=@($reqs | ForEach-Object { [string]$_.source } | Where-Object { $_ })
  $lost=@()
  foreach($e in @($existing)){
    if($null -eq $e){ continue }
    $src=[string]$e.requestSource
    if($src -match '^annotation:' -and ($kept -notcontains $src)){ $lost+=[string]$e.id }
  }
  return $lost
}
function Merge-DmEntries($existing,$new){
  # keep earlier entries whose id is not being re-resolved, then the new ones (callers wrap in @())
  $ids=@($new | ForEach-Object { [string]$_.id })
  $out=@()
  foreach($e in @($existing)){ if($null -ne $e -and ($ids -notcontains [string]$e.id)){ $out+=$e } }
  foreach($e in @($new)){ $out+=$e }
  return $out
}

if($myDefineOnly){ return }

# ===================== run =====================
# Exit 2 = nothing written (usage, malformed request, wrong kind of facts, or any unexpected error).
# Exit 1 is reserved for "block written, at least one request refused".
function Exit-DmUsage($msg){ Write-Host "Resolve-SwydoMetric: $msg"; exit 2 }
try {
  if(-not $myFacts -or -not $myRequestFile){ Exit-DmUsage 'usage: Resolve-SwydoMetric.ps1 -Facts <facts.json> -RequestFile <requests.json> [-OutFile <path>] [-Replace]' }
  if(-not (Test-Path -LiteralPath $myFacts)){ Exit-DmUsage "facts not found: $myFacts" }
  if(-not (Test-Path -LiteralPath $myRequestFile)){ Exit-DmUsage "request file not found: $myRequestFile" }

  $factsPath=(Resolve-Path -LiteralPath $myFacts).Path
  $factsText=[IO.File]::ReadAllText($factsPath)
  try { $factsObj=$factsText | ConvertFrom-Json } catch { Exit-DmUsage "facts file is not valid JSON: $($_.Exception.Message)" }
  if(-not $factsObj.platforms -or -not $factsObj.meta){ Exit-DmUsage 'facts file has no meta/platforms - is this a /swydee facts file?' }
  # single-period report facts only: trend facts (Analyze-SwydoTrend.ps1) carry quarter comparisons this tool does not model
  if([string]$factsObj.meta.tool -ne 'Analyze-SwydoReport.ps1'){ Exit-DmUsage "facts were written by '$($factsObj.meta.tool)', not Analyze-SwydoReport.ps1 - derived metrics are supported for single-period report facts only" }
  try { $reqObj=[IO.File]::ReadAllText((Resolve-Path -LiteralPath $myRequestFile).Path) | ConvertFrom-Json } catch { Exit-DmUsage "request file is not valid JSON: $($_.Exception.Message)" }
  $reqs=@(Get-DmRequests $reqObj)
  if($reqs.Count -eq 0){ Exit-DmUsage 'request file holds no requests' }
  $problems=@(); foreach($r in $reqs){ $problems+=@(Test-DmRequest $r) }
  $dupes=@($reqs | Group-Object { [string]$_.id } | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
  foreach($d in $dupes){ $problems+="id '$d' is used by more than one request" }
  if($problems.Count -gt 0){ Write-Host 'Resolve-SwydoMetric: malformed request(s) - nothing written:'; foreach($p in $problems){ Write-Host "  - $p" }; exit 2 }

  $canary=Test-DmFormatConvention
  if($canary){ Exit-DmUsage "the analyzer's number format is not the one this tool was verified against ($canary) - nothing computed" }

  $new=@(); foreach($r in $reqs){ $new+=(Resolve-DmRequest $factsObj $r) }
  $existing=@(); if(($factsObj.PSObject.Properties.Name -contains 'derivedMetrics') -and $factsObj.derivedMetrics){ $existing=@($factsObj.derivedMetrics.entries | Where-Object { $null -ne $_ }) }
  if($myReplace){
    $lost=@(Test-DmReplaceSafe $existing $reqs)
    if($lost.Count -gt 0){ Exit-DmUsage ("-Replace would drop entr" + $(if($lost.Count -eq 1){'y'}else{'ies'}) + " a client note asked for (" + ($lost -join ', ') + ") - re-request them in this file with the same source, or leave -Replace off") }
    $existing=@()
  } else {
    # entries written by an older version of this tool are not carried forward silently
    $newIds=@($new | ForEach-Object { [string]$_.id })
    $stale=@($existing | Where-Object { ($newIds -notcontains [string]$_.id) -and ([int]$_.v -lt $script:DmVersion) } | ForEach-Object { [string]$_.id })
    if($stale.Count -gt 0){ Exit-DmUsage ("the facts hold derived entr" + $(if($stale.Count -eq 1){'y'}else{'ies'}) + " from an older version of this tool (" + ($stale -join ', ') + ") - re-request them in this file, or pass -Replace") }
  }
  $all=@(Merge-DmEntries $existing $new)
  $outText=Set-DmFactsBlock $factsText (ConvertTo-DmBlockJson $all)
  # fail-closed: the spliced document must still parse and carry exactly the entries we meant to write
  try { $check=$outText | ConvertFrom-Json } catch { Exit-DmUsage "internal error - spliced facts do not parse; nothing written ($($_.Exception.Message))" }
  if(@($check.derivedMetrics.entries).Count -ne $all.Count -or @($check.platforms).Count -ne @($factsObj.platforms).Count){ Exit-DmUsage 'internal error - spliced facts lost content; nothing written' }
  Assert-NoCredential $outText
  # .NET resolves a relative path against the PROCESS directory, not the PowerShell location - always
  # hand it a fully resolved path.
  $dest = if($myOutFile){ $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($myOutFile) } else { $factsPath }
  # write beside the target, then swap: a failed write must never leave a half-written facts file
  $tmp=$dest + '.derive.tmp'
  [IO.File]::WriteAllText($tmp,$outText,(New-Object Text.UTF8Encoding($false)))
  Move-Item -LiteralPath $tmp -Destination $dest -Force
} catch {
  if($tmp -and (Test-Path -LiteralPath $tmp)){ Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
  Write-Host "Resolve-SwydoMetric: failed - nothing written ($($_.Exception.Message))"
  exit 2
}

$refused=0
foreach($e in $new){
  if($e.status -eq 'resolved'){
    $line="RESOLVED $($e.id): $($e.formula) = $($e.current.display)"
    if($e.current.approximate){ $line+=" (approximate: $($e.current.displayLow) to $($e.current.displayHigh))" }
    $line+=" [$($e.current.period); cross-check $($e.current.crossCheck)]"
    Write-Host $line
    if($e.comparison.hasComparison){ Write-Host ("  previous $($e.previous.display) [$($e.previous.period); cross-check $($e.previous.crossCheck)] -> $($e.comparison.displayDelta)") }
    else { Write-Host "  $($e.comparison.reason)" }
    foreach($n in @($e.notes)){ Write-Host "  note: $n" }
  } else {
    $refused++
    Write-Host "REFUSED  $($e.id): $(@($e.reasons) -join '; ')"
  }
}
Write-Host ("Resolve-SwydoMetric: {0} resolved, {1} refused -> {2}" -f ($new.Count-$refused),$refused,$dest)
if($refused -gt 0){ exit 1 }
exit 0
