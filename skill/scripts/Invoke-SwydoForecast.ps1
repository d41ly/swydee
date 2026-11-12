<#
.SYNOPSIS
  Estimate what a DECLARED-incomplete metric would have been (e.g. conversions lost to a tracking
  outage) and write the result as a labelled, closer-traceable `estimates` block in the facts file.

.DESCRIPTION
  "The model narrates; the tools compute" - this is the only place a modeled number is produced.
  Nothing is inferred: the caller DECLARES which metric / conversion actions are incomplete, over
  which dates, and who said so (-DeclaredBy). Without that declaration the tool refuses.

  Methods (each is recorded with every input value, its display string and its source):
    prior-level family (assumes last period's level carried into this one)
      prior-rate-clicks        previous value / previous clicks      x current clicks
      prior-rate-impressions   previous value / previous impressions x current impressions
      unaffected-ratio         previous value x (current / previous of the actions NOT declared affected)
      ledger-rate              mean monthly conversion rate over the trailing ledger months x current
                               clicks (a METHOD when the whole metric is incomplete, a CROSS-CHECK on the
                               account total otherwise - the ledger holds no per-action history)
    current-run-rate family (uses only what this period recorded)
      run-rate                 recorded value / tracked days x period days (or a supplied partial window)

  low = smallest method, high = largest method. The base blends the two FAMILY means, weighting the
  current-run-rate family by the share of the period that was tracked (tracked days / period days) and
  the prior-level family by the rest: the more of the period was actually observed, the more the
  observed pace counts. Three correlated prior-level methods still count as ONE line of evidence.
  With one family only, the base is that family's mean. When a partial tracked window is supplied
  (spec `partials`), the weight is that window's share of the period instead. At least two methods are
  required; fewer is a refusal with a stated reason, never a point guess. A method result below what
  was actually recorded is floored to the recorded value.

  With per-action estimates and a breakdown that reconciles to the headline, the tool also derives
  the account total, the conversion rate and the cost per conversion (each verified against the
  measured identity first; an identity that does not hold is a refusal for that metric).

  Output: the facts file gains ONE top-level property, `estimates`, appended textually so the measured
  facts are byte-for-byte untouched. Test-ReportNumbers.ps1 traces estimate numbers ONLY on a line
  carrying <!-- estimate:EST#n --> inside the "Estimates (modeled)" section.

  Fail-closed: exit 2 on bad input (unreadable JSON, a credential-bearing or non-facts file - this
  tool never reads a raw extraction, a non-count metric, an unmatched partial); the facts are left
  untouched. Exit 1 when every requested estimate was refused: no estimate is written, and an
  estimates block left by an EARLIER run is removed from the facts so a stale estimate cannot survive.
  Exit 0 when at least one estimate was written.

.PARAMETER Facts          The *.facts.json from Analyze-SwydoReport.ps1 (never the raw extraction).
.PARAMETER Ledger         Optional archive/<client>/ledger.json for the trailing-rate history.
.PARAMETER Spec           Optional JSON spec (see SKILL.md). Flags fill whatever the spec omits.
.PARAMETER Metric         Incomplete metric's display name (default "Conversions").
.PARAMETER Action         Affected conversion action label(s), ';'-separated. Omit => the whole metric.
.PARAMETER OutageStart    First day with lost tracking (yyyy-MM-dd, inclusive).
.PARAMETER OutageEnd      Last day with lost tracking (yyyy-MM-dd, inclusive).
.PARAMETER DeclaredBy     Who/what states the outage (e.g. "client note ANN#1", "user"). Required.
.PARAMETER Platform       Provider id; required only when the facts hold more than one platform.
.PARAMETER HistoryMonths  Trailing ledger months for the history rate (default 6; at least 3 must exist).
.PARAMETER MinTrackedDays Fewest tracked days the run-rate method accepts (default 3).
.PARAMETER OutFile        Write the facts+estimates here instead of updating -Facts in place.
.PARAMETER DefineOnly     Define functions and return (for unit tests).
#>
param(
  [string]$Facts,
  [string]$Ledger = "",
  [string]$Spec = "",
  [string]$Metric = "",
  [string]$Action = "",
  [string]$OutageStart = "",
  [string]$OutageEnd = "",
  [string]$DeclaredBy = "",
  [string]$Platform = "",
  [int]$HistoryMonths = 6,
  [int]$MinTrackedDays = 3,
  [string]$OutFile = "",
  [switch]$DefineOnly
)
$ErrorActionPreference = 'Stop'

# ---- constants (ASCII source; currency symbols via [char] - PS 5.1 reads BOM-less UTF-8 as ANSI) ----
$script:FcInv    = [Globalization.CultureInfo]::InvariantCulture
$script:FcCurSym = @{ USD='$'; EUR=([char]0x20AC); GBP=([char]0xA3); CAD='CA$'; AUD='A$' }
$script:FcCredRx = '(?i)swy\.do/shares/|"shareKey"|"shareUrl"|/g/[A-Za-z0-9_-]+/reports/'
$script:FcLabel  = 'Estimates (modeled)'
$script:FcMaxSpread = 2.0   # ledger history: largest month may be at most this multiple of the smallest

# ---- formatting (mirrors Format-Metric's specifiers: counts N1, fraction N1%, money N2) ----
# Estimated counts are ALWAYS one decimal: a whole-number display under 100 is not a measure token to
# the closer, and an estimate must never be able to slip past the tracer.
function Format-FcCount($v){ return ([double]$v).ToString('N1',$script:FcInv) }
function Format-FcPercent($frac){ return ((([double]$frac)*100).ToString('N1',$script:FcInv) + '%') }
function Format-FcMoney($v,$currency){
  $sym = '$'
  if($currency -and $script:FcCurSym[[string]$currency]){ $sym = $script:FcCurSym[[string]$currency] }
  elseif($currency){ $sym = ([string]$currency + ' ') }
  return ([string]$sym + ([double]$v).ToString('N2',$script:FcInv))
}
function ConvertFrom-FcDisplay($s){
  # a facts display string ("1,234.5", "$12.30", "30.5%") -> [double], or $null. Percent stays in
  # display units (30.5), it is NOT turned into a fraction - callers here only parse counts.
  if($null -eq $s){ return $null }
  $t = ([string]$s) -replace '[^0-9\.\-]',''
  if($t -eq '' -or $t -eq '.' -or $t -eq '-'){ return $null }
  $d = 0.0
  if([double]::TryParse($t,[Globalization.NumberStyles]::Float,$script:FcInv,[ref]$d)){ return [double]$d }
  return $null
}
function ConvertTo-FcDate($s){
  $d = [datetime]::MinValue
  if([datetime]::TryParseExact([string]$s,'yyyy-MM-dd',$script:FcInv,[Globalization.DateTimeStyles]::None,[ref]$d)){ return $d }
  return $null
}
function Get-FcDays($a,$b){ return [int](($b - $a).TotalDays) + 1 }   # inclusive day count
function Test-FcNum($v){ return ($v -is [double] -or $v -is [int] -or $v -is [long] -or $v -is [decimal] -or $v -is [single]) }
function Get-FcProp($o,$name){
  if($null -eq $o){ return $null }
  if($o -is [System.Collections.IDictionary]){ if($o.Contains($name)){ return $o[$name] } else { return $null } }
  $p = $o.PSObject.Properties[$name]
  if($p){ return $p.Value }
  return $null
}
function New-FcInput($name,$value,$display,$source){
  return [ordered]@{ name=[string]$name; display=[string]$display; value=$value; source=[string]$source }
}

# ---- facts access ----
function Get-FcHeadline($plat,$name){
  # the headline cell whose display NAME equals $name. Exactly one, or a stated reason.
  $hits = @()
  if($plat.headline){
    foreach($p in $plat.headline.PSObject.Properties){
      $c = $p.Value
      if($null -eq $c -or $c -is [bool] -or $c -is [string]){ continue }
      if([string](Get-FcProp $c 'metric') -eq [string]$name){ $hits += $c }
    }
  }
  if($hits.Count -eq 1){ return @{ ok=$true; cell=$hits[0]; reason=$null } }
  if($hits.Count -eq 0){ return @{ ok=$false; cell=$null; reason="no headline metric named '$name'" } }
  return @{ ok=$false; cell=$null; reason="headline metric name '$name' is ambiguous ($($hits.Count) metrics share it)" }
}
function Get-FcRaw($cell,$which){
  # raw current|previous of a headline cell in DISPLAY units (micros -> base units). $null if absent.
  $v = Get-FcProp $cell $which
  if(-not (Test-FcNum $v)){ return $null }
  if([string](Get-FcProp $cell 'unit') -eq 'micros'){ return [double]$v/1e6 }
  return [double]$v
}
function Get-FcActionBreakdown($plat,$metric,$dimension,$actions){
  # the breakdown cut by $dimension whose rows carry $metric AND include every declared action as a
  # row label (a widget that also lists the dimension but is cut by month has no such rows).
  # Exactly one, or a stated reason.
  $hits = @(); $seen = @()
  foreach($bd in @($plat.breakdowns)){
    if($null -eq $bd){ continue }
    $dims = @($bd.dimensions | ForEach-Object { [string]$_ })
    if($dims -notcontains [string]$dimension){ continue }
    $labels = @()
    foreach($r in @($bd.rows)){ if($r.values -and $r.values.PSObject.Properties[$metric]){ $labels += [string]$r.label } }
    if($labels.Count -eq 0){ continue }
    $seen += $labels
    $all = $true
    foreach($a in @($actions)){ if(@($labels | Where-Object { $_ -eq [string]$a }).Count -ne 1){ $all = $false; break } }
    if($all){ $hits += $bd }
  }
  if($hits.Count -eq 1){ return @{ ok=$true; breakdown=$hits[0]; reason=$null } }
  if($hits.Count -eq 0){
    if($seen.Count -eq 0){ return @{ ok=$false; breakdown=$null; reason="no breakdown by '$dimension' carries '$metric'" } }
    return @{ ok=$false; breakdown=$null; reason=("no breakdown by '{0}' has every declared action as exactly one row. Rows seen: {1}" -f $dimension,((@($seen | Select-Object -Unique)) -join ' | ')) }
  }
  return @{ ok=$false; breakdown=$null; reason="$($hits.Count) breakdowns by '$dimension' list the declared action(s); cannot tell which one is the account split" }
}

# ---- identity: is this report's conversion rate really conversions / clicks? ----
function Test-FcRateIdentity($reported,$conversions,$clickCount){
  # RELATIVE tolerance (2% of the reported rate). The facts keep the unrounded fraction, so no display
  # allowance is needed - and any absolute allowance lets a different definition through on low-rate
  # accounts (0.13% vs 0.143%).
  if(-not (Test-FcNum $reported) -or -not (Test-FcNum $conversions) -or -not (Test-FcNum $clickCount)){ return $false }
  if([double]$clickCount -le 0 -or [double]$reported -le 0){ return $false }
  $tol = 0.02 * [math]::Abs([double]$reported)
  return ([math]::Abs(([double]$conversions/[double]$clickCount) - [double]$reported) -le $tol)
}

# ---- ledger access ----
function Test-FcHistoryStable($h){
  # a trailing mean is only meaningful over a stable stretch. A month at zero, or the largest month
  # more than $script:FcMaxSpread times the smallest, signals a tracking/setup change inside the window.
  return ($h.min -gt 0 -and ($h.max / $h.min) -le $script:FcMaxSpread)
}
function Get-FcPrevMonths($ym,$n){
  # the $n calendar months immediately before 'yyyy-MM', oldest first
  if([string]$ym -notmatch '^(\d{4})-(\d{2})$'){ return @() }
  $d = New-Object datetime ([int]$Matches[1]),([int]$Matches[2]),1
  $out = @()
  for($i=$n; $i -ge 1; $i--){ $out += $d.AddMonths(-$i).ToString('yyyy-MM',$script:FcInv) }
  return $out
}
function Get-FcLedgerTrailing($ledgerDoc,$providerId,$metricId,$currentYm,$n,$excludeMonths){
  # mean of the monthly values of ONE ledger series over the trailing $n months before $currentYm.
  # Unweighted mean of monthly values (the ledger keeps the rate, not its numerator/denominator).
  # -> @{ ok; mean; months; unit; reason }
  if($null -eq $ledgerDoc -or $null -eq $ledgerDoc.cells){ return @{ ok=$false; reason='no ledger supplied' } }
  $want = @(Get-FcPrevMonths $currentYm $n | Where-Object { @($excludeMonths) -notcontains $_ })
  if($want.Count -eq 0){ return @{ ok=$false; reason="period month '$currentYm' is not a calendar month key" } }
  $byMonth = @{}; $dupe = $null; $unit = $null
  foreach($p in $ledgerDoc.cells.PSObject.Properties){
    $c = $p.Value
    if([string]$c.metricId -ne [string]$metricId -or [string]$c.providerId -ne [string]$providerId){ continue }
    $mk = [string]$c.month
    if($want -notcontains $mk){ continue }
    if(-not (Test-FcNum $c.value)){ continue }
    if($byMonth.ContainsKey($mk)){ $dupe = $mk; continue }
    $byMonth[$mk] = [double]$c.value; $unit = [string]$c.unit
  }
  if($dupe){ return @{ ok=$false; reason="ledger holds more than one series for $metricId in $dupe (a basis change); history is ambiguous" } }
  $used = @($want | Where-Object { $byMonth.ContainsKey($_) })
  if($used.Count -lt 3){ return @{ ok=$false; reason="ledger has only $($used.Count) of the trailing $n months for $metricId (need at least 3)" } }
  $sum = 0.0; $mn = $null; $mx = $null
  foreach($mk in $used){ $v = $byMonth[$mk]; $sum += $v; if($null -eq $mn -or $v -lt $mn){ $mn = $v }; if($null -eq $mx -or $v -gt $mx){ $mx = $v } }
  return @{ ok=$true; mean=($sum/$used.Count); min=$mn; max=$mx; months=$used; unit=$unit; reason=$null }
}

# ---- range resolution ----
function Resolve-FcRange($methods,$runWeight=$null){
  # low/high over ALL methods. base: with both families and a tracked share ($runWeight, 0..1), the
  # current-run-rate family mean gets $runWeight and the prior-level family mean gets the rest;
  # otherwise the plain mean of the per-family means.
  $fam = [ordered]@{}
  $lo = $null; $hi = $null
  foreach($m in @($methods)){
    $v = [double]$m.value
    if($null -eq $lo -or $v -lt $lo){ $lo = $v }
    if($null -eq $hi -or $v -gt $hi){ $hi = $v }
    if(-not $fam.Contains($m.family)){ $fam[$m.family] = New-Object System.Collections.ArrayList }
    [void]$fam[$m.family].Add($v)
  }
  $famMeans = [ordered]@{}; $acc = 0.0
  foreach($k in $fam.Keys){ $s=0.0; foreach($v in $fam[$k]){ $s += $v }; $famMeans[$k] = $s/$fam[$k].Count; $acc += $famMeans[$k] }
  $base = $acc/$famMeans.Count; $w = $null
  if($null -ne $runWeight -and $famMeans.Contains('prior-level') -and $famMeans.Contains('current-run-rate') -and $famMeans.Count -eq 2){
    $w = [math]::Min(1.0,[math]::Max(0.0,[double]$runWeight))
    $base = $w * $famMeans['current-run-rate'] + (1 - $w) * $famMeans['prior-level']
  }
  return @{ low=$lo; high=$hi; base=$base; familyMeans=$famMeans; runWeight=$w }
}

# ---- the methods for ONE target (an action row, or the whole metric) ----
function Get-FcMethods($t){
  # $t: label, cur, curDisplay, curSource, prev, prevDisplay, prevSource, clicks, impressions,
  #     unaffected, period, partial, ledgerRate, minTrackedDays, compareOk
  $methods = New-Object System.Collections.ArrayList
  $skipped = New-Object System.Collections.ArrayList
  function _add($id,$family,$name,$value,$formula,$inputs,$assumption){
    $note = $null
    if($null -ne $t.floor -and $value -lt [double]$t.floor){ $value = [double]$t.floor; $note = 'result was below what was actually recorded, so it is held at the recorded value' }
    $m = [ordered]@{ id=$id; family=$family; name=$name; value=[math]::Round([double]$value,4); display=(Format-FcCount $value); formula=$formula; inputs=@($inputs); assumption=$assumption }
    if($note){ $m.note = $note }
    [void]$methods.Add($m)
  }
  function _skip($id,$reason){ [void]$skipped.Add([ordered]@{ id=$id; reason=[string]$reason }) }
  $prevIn = $null
  if($null -ne $t.prev){ $prevIn = New-FcInput 'previous-period value' $t.prev $t.prevDisplay $t.prevSource }

  # prior-level family -------------------------------------------------------------------------
  foreach($tr in @(@{ id='prior-rate-clicks'; key='clicks'; word='clicks' }, @{ id='prior-rate-impressions'; key='impressions'; word='impressions' })){
    $k = $t[$tr.key]
    if(-not $t.compareOk){ _skip $tr.id 'the previous-period comparison is not trusted for this report'; continue }
    if($null -eq $t.prev){ _skip $tr.id 'no previous-period value for the target'; continue }
    if($null -eq $k -or -not $k.ok){ $why = 'not available'; if($k -and $k.reason){ $why = $k.reason }; _skip $tr.id ("{0}: {1}" -f $tr.word,$why); continue }
    if($null -eq $k.prev){ _skip $tr.id ("no previous-period {0}" -f $tr.word); continue }
    if($k.prev -le 0){ _skip $tr.id ("previous-period {0} are zero" -f $tr.word); continue }
    $val = [double]$t.prev / [double]$k.prev * [double]$k.cur
    _add $tr.id 'prior-level' ("last period's rate per {0}, applied to this period's {0}" -f $tr.word) $val `
      ("{0} previous-period / {1} previous-period {2} x {3} current-period {2}" -f $t.prevDisplay,$k.prevDisplay,$tr.word,$k.curDisplay) `
      @($prevIn, (New-FcInput ("previous-period {0}" -f $tr.word) $k.prev $k.prevDisplay $k.prevSource), (New-FcInput ("current-period {0}" -f $tr.word) $k.cur $k.curDisplay $k.curSource)) `
      ("the rate per {0} seen last period also held this period" -f $tr.word)
  }
  $u = $t.unaffected
  if($null -eq $u){ }   # whole-metric mode: there is no unaffected remainder to lean on
  elseif(-not $t.compareOk){ _skip 'unaffected-ratio' 'the previous-period comparison is not trusted for this report' }
  elseif($null -eq $t.prev){ _skip 'unaffected-ratio' 'no previous-period value for the target' }
  elseif(-not $u.ok){ _skip 'unaffected-ratio' $u.reason }
  else {
    $val = [double]$t.prev * [double]$u.cur / [double]$u.prev
    _add 'unaffected-ratio' 'prior-level' 'last period''s value, moved by the same proportion as the actions that kept tracking' $val `
      ("{0} previous-period x ({1} current-period / {2} previous-period for {3})" -f $t.prevDisplay,$u.curDisplay,$u.prevDisplay,$u.names) `
      @($prevIn, (New-FcInput 'unaffected actions, current period' $u.cur $u.curDisplay $u.source), (New-FcInput 'unaffected actions, previous period' $u.prev $u.prevDisplay $u.source)) `
      'the affected action moved in step with the actions whose tracking was not interrupted'
  }
  $lr = $t.ledgerRate
  if($null -ne $lr){
    if(-not $lr.ok){ _skip 'ledger-rate' $lr.reason }
    elseif($null -eq $t.clicks -or -not $t.clicks.ok){ _skip 'ledger-rate' 'current-period clicks are not available' }
    else {
      $val = [double]$lr.mean * [double]$t.clicks.cur
      _add 'ledger-rate' 'prior-level' ("the average monthly conversion rate of the previous {0} months, applied to this period's clicks" -f $lr.months.Count) $val `
        ("{0} average conversion rate ({1} to {2}) x {3} current-period clicks" -f $lr.display,$lr.months[0],$lr.months[-1],$t.clicks.curDisplay) `
        @((New-FcInput 'trailing average conversion rate' $lr.mean $lr.display $lr.source), (New-FcInput 'current-period clicks' $t.clicks.cur $t.clicks.curDisplay $t.clicks.curSource)) `
        'this period converted at the average rate of the preceding months'
    }
  }

  # current-run-rate family --------------------------------------------------------------------
  $pd = $t.period
  if($null -eq $pd -or -not $pd.ok){ $why = 'the report period is not resolved to dates'; if($pd -and $pd.reason){ $why = $pd.reason }; _skip 'run-rate' $why }
  elseif($t.partial){
    $pt = $t.partial
    if(-not $pt.ok){ _skip 'run-rate' $pt.reason }
    elseif($pt.days -lt [math]::Max(1,[int]$t.minTrackedDays)){ _skip 'run-rate' ("the supplied tracked window is only {0} day(s) (minimum {1})" -f $pt.days,[math]::Max(1,[int]$t.minTrackedDays)) }
    else {
      $val = [double]$pt.value / [double]$pt.days * [double]$pd.days
      _add 'run-rate' 'current-run-rate' 'the daily pace of the supplied tracked window, extended to the full period' $val `
        ("{0} recorded {1} to {2} / {3} days x {4} days in the period" -f $pt.display,$pt.start,$pt.end,$pt.days,$pd.days) `
        @((New-FcInput 'recorded in the tracked window' $pt.value $pt.display $pt.source), (New-FcInput 'tracked-window days' $pt.days ([string]$pt.days) ("{0}..{1}" -f $pt.start,$pt.end)), (New-FcInput 'period days' $pd.days ([string]$pd.days) $pd.source)) `
        'the daily pace of the tracked window held on the days tracking was lost'
    }
  }
  elseif($pd.trackedDays -lt [math]::Max(1,[int]$t.minTrackedDays)){ _skip 'run-rate' ("only {0} tracked day(s) in the period (minimum {1})" -f $pd.trackedDays,[math]::Max(1,[int]$t.minTrackedDays)) }
  elseif($null -eq $t.cur){ _skip 'run-rate' 'no recorded current-period value for the target' }
  else {
    $val = [double]$t.cur / [double]$pd.trackedDays * [double]$pd.days
    _add 'run-rate' 'current-run-rate' 'the daily pace of the tracked days, extended to the full period' $val `
      ("{0} recorded / {1} tracked days x {2} days in the period" -f $t.curDisplay,$pd.trackedDays,$pd.days) `
      @((New-FcInput 'recorded current-period value' $t.cur $t.curDisplay $t.curSource), (New-FcInput 'tracked days' $pd.trackedDays ([string]$pd.trackedDays) $pd.trackedSource), (New-FcInput 'period days' $pd.days ([string]$pd.days) $pd.source)) `
      'everything recorded fell on tracked days, and those days ran at the same daily pace as the lost ones'
  }
  return @{ methods=$methods; skipped=$skipped }
}

function Get-FcUncertainty($methods,$range,$t){
  $parts = New-Object System.Collections.ArrayList
  $fm = $range.familyMeans
  $both = ($fm.Contains('prior-level') -and $fm.Contains('current-run-rate'))
  $wWhy = 'the share of the period that was tracked'
  if($t.partial -and $t.partial.ok -and $t.period -and $t.period.ok){ $wWhy = ("the share of the period covered by the supplied tracked window, {0} of {1} days" -f $t.partial.days,$t.period.days) }
  if($both){
    [void]$parts.Add(("Range {0} to {1} across {2} methods; the base of {3} blends the two independent lines of evidence, giving this period's tracked-day pace a weight of {4} ({5}) and last period's level the rest." -f (Format-FcCount $range.low),(Format-FcCount $range.high),@($methods).Count,(Format-FcCount $range.base),(Format-FcPercent $range.runWeight),$wWhy))
    $pl = [double]$fm['prior-level']; $rr = [double]$fm['current-run-rate']
    if($pl -gt 0){
      $ratio = $rr/$pl
      if($ratio -lt 0.75 -or $ratio -gt (1/0.75)){
        [void]$parts.Add(("The two lines of evidence disagree widely: the tracked-day pace gives {0} of the prior-level figure. Either the metric genuinely moved this period, or the tracked days were not fully tracked. Treat the base as indicative, not precise." -f (Format-FcPercent $ratio)))
      }
    }
  } elseif($fm.Contains('prior-level')){
    [void]$parts.Add(("Range {0} to {1} across {2} methods, base {3} (their mean). Every method assumes last period's level carried into this one; there is no usable evidence from this period's tracked days, so the range understates the real uncertainty." -f (Format-FcCount $range.low),(Format-FcCount $range.high),@($methods).Count,(Format-FcCount $range.base)))
  } else {
    [void]$parts.Add(("Range {0} to {1} across {2} methods, base {3} (their mean)." -f (Format-FcCount $range.low),(Format-FcCount $range.high),@($methods).Count,(Format-FcCount $range.base)))
  }
  $rrm = @($methods | Where-Object { $_.id -eq 'run-rate' })
  if($rrm.Count -gt 0 -and $null -ne $t.runRateObserved -and [double]$t.runRateObserved -lt 30){
    [void]$parts.Add(("The tracked-day pace rests on only {0} recorded, a small sample." -f $t.runRateObservedDisplay))
  }
  [void]$parts.Add('This is a modeled figure, not a measurement.')
  return ($parts -join ' ')
}

# ---- spec ----
function Resolve-FcSpec($specObj,$flags){
  # merge: the spec file wins where it speaks, the flags fill the rest. -> hashtable or throws 'INPUT: ...'
  $s = @{ declaredBy=''; platform=''; metric=''; actions=@(); outageStart=''; outageEnd=''; partials=@(); excludeMonths=@(); actionDimension='Conversion action name'
          names=@{ clicks='Clicks'; impressions='Impressions'; cost='Cost'; conversionRate='Conversion rate'; costPerConversion='Cost / conversion' } }
  if($specObj){
    foreach($k in @('declaredBy','platform','metric','actionDimension')){ $v = Get-FcProp $specObj $k; if($v){ $s[$k] = [string]$v } }
    $o = Get-FcProp $specObj 'outage'
    if($o){ $s.outageStart = [string](Get-FcProp $o 'start'); $s.outageEnd = [string](Get-FcProp $o 'end') }
    $s.actions = @(@(Get-FcProp $specObj 'actions') | Where-Object { $_ } | ForEach-Object { [string]$_ })
    $s.partials = @(@(Get-FcProp $specObj 'partials') | Where-Object { $_ })
    $s.excludeMonths = @(@(Get-FcProp $specObj 'excludeMonths') | Where-Object { $_ } | ForEach-Object { [string]$_ })
    $mn = Get-FcProp $specObj 'metricNames'
    if($mn){ foreach($k in @($s.names.Keys)){ $v = Get-FcProp $mn $k; if($v){ $s.names[$k] = [string]$v } } }
  }
  if(-not $s.declaredBy -and $flags.declaredBy){ $s.declaredBy = [string]$flags.declaredBy }
  if(-not $s.platform -and $flags.platform){ $s.platform = [string]$flags.platform }
  if(-not $s.metric -and $flags.metric){ $s.metric = [string]$flags.metric }
  if(-not $s.metric){ $s.metric = 'Conversions' }
  if($s.actions.Count -eq 0 -and $flags.action){ $s.actions = @(([string]$flags.action -split ';') | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
  if(-not $s.outageStart -and $flags.outageStart){ $s.outageStart = [string]$flags.outageStart }
  if(-not $s.outageEnd -and $flags.outageEnd){ $s.outageEnd = [string]$flags.outageEnd }
  $seenAct = @{}; $uniq = @()
  foreach($a in @($s.actions)){ $k = ([string]$a).Trim(); if($k -and -not $seenAct.ContainsKey($k.ToLowerInvariant())){ $seenAct[$k.ToLowerInvariant()] = $true; $uniq += $k } }
  $s.actions = @($uniq)
  if($s.declaredBy -match '[A-Za-z0-9_-]{20,}'){ throw 'INPUT: -DeclaredBy looks like it contains a key or token. Name the source in words ("client note ANN#1", "user").' }
  if(-not $s.declaredBy.Trim()){ throw 'INPUT: no declaration source. Say who states the data is incomplete (-DeclaredBy "client note ANN#1" / "user"); an outage is never inferred.' }
  if(-not $s.outageStart -or -not $s.outageEnd){ throw 'INPUT: the incomplete window is not declared. Pass -OutageStart and -OutageEnd (first and last day with lost tracking, yyyy-MM-dd).' }
  if($null -eq (ConvertTo-FcDate $s.outageStart) -or $null -eq (ConvertTo-FcDate $s.outageEnd)){ throw 'INPUT: -OutageStart / -OutageEnd must be yyyy-MM-dd dates.' }
  if((ConvertTo-FcDate $s.outageEnd) -lt (ConvertTo-FcDate $s.outageStart)){ throw 'INPUT: -OutageEnd is before -OutageStart.' }
  return $s
}

# ---- the core ----
function Get-FcEstimates($factsDoc,$ledgerDoc,$fcSpec,[int]$histN=6,[int]$minDays=3,$nowIso=$null){
  # -> [ordered] estimates block { ..., items=[...], refused=[...] }. Throws 'INPUT: ...' on unusable input.
  if($null -eq $factsDoc -or $null -eq $factsDoc.meta -or $null -eq $factsDoc.platforms){ throw 'INPUT: not a facts document (no meta/platforms).' }
  $meta = $factsDoc.meta
  if($meta.PSObject.Properties['extractionComplete'] -and $meta.extractionComplete -eq $false){ throw 'INPUT: the facts declare extractionComplete=false. Re-extract first; an estimate over a partial extraction would model the wrong gap.' }
  $plats = @($factsDoc.platforms)
  $plat = $null
  if($fcSpec.platform){ $plat = @($plats | Where-Object { [string]$_.id -eq $fcSpec.platform })[0]; if($null -eq $plat){ throw "INPUT: platform '$($fcSpec.platform)' is not in the facts." } }
  elseif($plats.Count -eq 1){ $plat = $plats[0] }
  else { throw ("INPUT: the facts hold {0} platforms; say which one with -Platform ({1})." -f $plats.Count,(@($plats | ForEach-Object { $_.id }) -join ', ')) }
  $plid = [string]$plat.id
  $items = New-Object System.Collections.ArrayList
  $refused = New-Object System.Collections.ArrayList
  $compareOk = ([string]$meta.compareBasis -ne 'untrusted') -and ($meta.hasComparison -ne $false)

  # period + declared window
  $period = @{ ok=$false; reason='the facts carry no resolved period dates (meta.periodResolved)' }
  $ps = $null; $pe = $null
  if($meta.periodResolved -and $meta.periodResolved.current){ $ps = ConvertTo-FcDate $meta.periodResolved.current.start; $pe = ConvertTo-FcDate $meta.periodResolved.current.end }
  $os = ConvertTo-FcDate $fcSpec.outageStart; $oe = ConvertTo-FcDate $fcSpec.outageEnd
  $outDays = $null; $tracked = $null; $perDays = $null
  if($ps -and $pe){
    if($oe -lt $ps -or $os -gt $pe){ throw ("INPUT: the declared window {0}..{1} does not touch the report period {2}..{3}." -f $fcSpec.outageStart,$fcSpec.outageEnd,$ps.ToString('yyyy-MM-dd'),$pe.ToString('yyyy-MM-dd')) }
    $cs = $os; if($cs -lt $ps){ $cs = $ps }
    $ce = $oe; if($ce -gt $pe){ $ce = $pe }
    $perDays = Get-FcDays $ps $pe; $outDays = Get-FcDays $cs $ce; $tracked = $perDays - $outDays
    $period = @{ ok=$true; days=$perDays; trackedDays=$tracked; outageDays=$outDays; start=$ps; end=$pe; clipStart=$cs; clipEnd=$ce
                 source=("meta.periodResolved {0}..{1}" -f $ps.ToString('yyyy-MM-dd'),$pe.ToString('yyyy-MM-dd'))
                 trackedSource=("period days minus the declared window {0}..{1} ({2})" -f $cs.ToString('yyyy-MM-dd'),$ce.ToString('yyyy-MM-dd'),$fcSpec.declaredBy) }
  }
  $periodLabel = [string]$meta.currentPeriod

  # traffic
  function _traffic($name){
    $h = Get-FcHeadline $plat $name
    if(-not $h.ok){ return @{ ok=$false; reason=$h.reason } }
    $c = Get-FcRaw $h.cell 'current'; $p = Get-FcRaw $h.cell 'previous'
    if($null -eq $c -or $c -le 0){ return @{ ok=$false; reason="'$name' has no current value" } }
    # ok = the CURRENT value is usable. prev may be $null: only the prior-rate methods need it.
    return @{ ok=$true; cur=$c; prev=$p; curDisplay=[string]$h.cell.displayCurrent; prevDisplay=[string]$h.cell.displayPrevious
              curSource="facts headline '$name' displayCurrent"; prevSource="facts headline '$name' displayPrevious"; cell=$h.cell }
  }
  $clicks = _traffic $fcSpec.names.clicks
  $impr   = _traffic $fcSpec.names.impressions

  # the incomplete metric's headline
  $hm = Get-FcHeadline $plat $fcSpec.metric
  $hCur = $null; $hPrev = $null
  if($hm.ok){
    $mt = [string]$hm.cell.type; $mu = [string]$hm.cell.unit
    if(($mt -and $mt -ne 'number') -or $mu -in @('fraction','micros')){ throw ("INPUT: '{0}' is a {1} metric. Only plain counts (conversions, calls, leads) can be estimated; a rate or a money figure is not something a tracking gap removes day by day." -f $fcSpec.metric,$(if($mt){$mt}else{$mu})) }
    $hCur = Get-FcRaw $hm.cell 'current'; $hPrev = Get-FcRaw $hm.cell 'previous'
  }
  # M4: every supplied partial observation must belong to a declared target - a typo must not silently
  # fall back to the tracked-days run-rate
  foreach($pp in @($fcSpec.partials)){
    $pa = [string](Get-FcProp $pp 'action')
    if($fcSpec.actions.Count -gt 0){
      if(@($fcSpec.actions | Where-Object { $_ -eq $pa }).Count -ne 1){ throw ("INPUT: a partial observation names action '{0}', which is not a declared action ({1})." -f $pa,($fcSpec.actions -join ' | ')) }
    } elseif($pa){ throw ("INPUT: a partial observation names action '{0}', but the whole metric is the target; omit ""action"" on a partial for the whole metric." -f $pa) }
  }

  # ledger history (account-level conversion rate / cost per conversion)
  $curYm = $null
  if($meta.period -and $meta.period.calendarAligned -eq $true -and [string]$meta.period.startYm -eq [string]$meta.period.endYm){ $curYm = [string]$meta.period.startYm }
  $ledgerOk = $true; $ledgerWhy = $null
  if($null -eq $ledgerDoc){ $ledgerOk = $false; $ledgerWhy = 'no ledger supplied' }
  elseif(([string]$ledgerDoc.client).Trim().ToLower() -ne ([string]$meta.client).Trim().ToLower()){ $ledgerOk = $false; $ledgerWhy = 'the ledger belongs to a different client than the facts' }
  elseif(-not $curYm){ $ledgerOk = $false; $ledgerWhy = 'the report period is not one calendar month, so monthly ledger history does not apply' }
  elseif($fcSpec.metric -ne 'Conversions'){ $ledgerOk = $false; $ledgerWhy = "ledger rate history is used for 'Conversions' only" }
  $ledgerRate = @{ ok=$false; reason=$ledgerWhy }
  $ledgerCpa  = @{ ok=$false; reason=$ledgerWhy }
  $hRate = Get-FcHeadline $plat $fcSpec.names.conversionRate
  $hCpa  = Get-FcHeadline $plat $fcSpec.names.costPerConversion
  $hCost = Get-FcHeadline $plat $fcSpec.names.cost
  # the identity holds for an incomplete metric too (both sides are what was recorded), so it can be
  # checked on this period's measured figures
  $rateIdOk = ($hRate.ok -and $clicks.ok -and (Test-FcRateIdentity $hRate.cell.current $hCur $clicks.cur))
  if($ledgerOk){
    if(-not $rateIdOk){ $ledgerRate = @{ ok=$false; reason='in this report the conversion rate is not conversions / clicks (or cannot be checked), so a ledger rate cannot be turned into conversions' } }
    elseif($hRate.ok -and [string]$hRate.cell.unit -eq 'fraction'){
      $ledgerRate = Get-FcLedgerTrailing $ledgerDoc $plid ([string]$hRate.cell.id) $curYm $histN $fcSpec.excludeMonths
      if($ledgerRate.ok -and -not (Test-FcHistoryStable $ledgerRate)){
        $ledgerRate = @{ ok=$false; reason=("the conversion rate over {0} to {1} ranges from {2} to {3}, too unstable to average (a tracking or setup change inside the window is likely); a shorter -HistoryMonths may cover a stable stretch" -f $ledgerRate.months[0],$ledgerRate.months[-1],(Format-FcPercent $ledgerRate.min),(Format-FcPercent $ledgerRate.max)) }
      }
      if($ledgerRate.ok){
        $ledgerRate.display = Format-FcPercent $ledgerRate.mean
        $ledgerRate.source = ("ledger {0}, unweighted mean of {1} monthly values {2}..{3}" -f $hRate.cell.id,$ledgerRate.months.Count,$ledgerRate.months[0],$ledgerRate.months[-1])
      }
    } else { $ledgerRate = @{ ok=$false; reason="the facts have no fraction-typed '$($fcSpec.names.conversionRate)' headline to match a ledger series" } }
    if($hCpa.ok -and [string]$hCpa.cell.unit -eq 'micros'){
      $ledgerCpa = Get-FcLedgerTrailing $ledgerDoc $plid ([string]$hCpa.cell.id) $curYm $histN $fcSpec.excludeMonths
      if($ledgerCpa.ok -and -not (Test-FcHistoryStable $ledgerCpa)){
        $ledgerCpa = @{ ok=$false; reason=("the cost per conversion over {0} to {1} ranges from {2} to {3}, too unstable to average (a tracking or setup change inside the window is likely); a shorter -HistoryMonths may cover a stable stretch" -f $ledgerCpa.months[0],$ledgerCpa.months[-1],(Format-FcMoney ($ledgerCpa.min/1e6) $hCpa.cell.currency),(Format-FcMoney ($ledgerCpa.max/1e6) $hCpa.cell.currency)) }
      }
      if($ledgerCpa.ok){
        $ledgerCpa.mean = $ledgerCpa.mean/1e6
        $ledgerCpa.display = Format-FcMoney $ledgerCpa.mean $hCpa.cell.currency
        $ledgerCpa.source = ("ledger {0}, unweighted mean of {1} monthly values {2}..{3}" -f $hCpa.cell.id,$ledgerCpa.months.Count,$ledgerCpa.months[0],$ledgerCpa.months[-1])
      }
    } else { $ledgerCpa = @{ ok=$false; reason="the facts have no micros-typed '$($fcSpec.names.costPerConversion)' headline to match a ledger series" } }
  }

  function _partial($actionName){
    # the supplied tracked-window observation for this target, validated. $null when none was supplied.
    $hit = @($fcSpec.partials | Where-Object { [string](Get-FcProp $_ 'action') -eq [string]$actionName })
    if($hit.Count -eq 0){ return $null }
    if($hit.Count -gt 1){ return @{ ok=$false; reason='more than one partial observation was supplied for this target' } }
    $pv = Get-FcProp $hit[0] 'value'; $a = ConvertTo-FcDate (Get-FcProp $hit[0] 'start'); $b = ConvertTo-FcDate (Get-FcProp $hit[0] 'end')
    $src = [string](Get-FcProp $hit[0] 'source')
    if(-not (Test-FcNum $pv) -or [double]$pv -lt 0){ return @{ ok=$false; reason='the partial observation has no numeric value' } }
    if($null -eq $a -or $null -eq $b -or $b -lt $a){ return @{ ok=$false; reason='the partial observation has no valid start/end dates' } }
    if(-not $src.Trim()){ return @{ ok=$false; reason='the partial observation names no source' } }
    if(-not $period.ok){ return @{ ok=$false; reason=$period.reason } }
    if($a -lt $period.start -or $b -gt $period.end){ return @{ ok=$false; reason='the partial window is not inside the report period' } }
    if($a -le $period.clipEnd -and $b -ge $period.clipStart){ return @{ ok=$false; reason='the partial window overlaps the declared outage window' } }
    return @{ ok=$true; value=[double]$pv; display=(Format-FcCount $pv); days=(Get-FcDays $a $b); start=$a.ToString('yyyy-MM-dd'); end=$b.ToString('yyyy-MM-dd'); source=("spec partial: {0}" -f $src) }
  }
  function _item($kind,$actionName,$mres,$tgt){
    # share of the period actually observed: the supplied partial window if one was used, else the tracked days
    $rw = $null
    if($tgt.partial -and $tgt.partial.ok -and $period.ok){ $rw = [double]$tgt.partial.days / [double]$period.days }
    elseif($period.ok){ $rw = [double]$period.trackedDays / [double]$period.days }
    $rng = Resolve-FcRange $mres.methods $rw
    $eid = 'EST#' + ($items.Count + 1)
    $what = "'$($fcSpec.metric)'"; if($actionName){ $what = "'$actionName' $($fcSpec.metric)" }
    $rec = 'nothing usable was recorded'; if($null -ne $tgt.cur){ $rec = "$($tgt.curDisplay) were actually recorded" }
    $it = [ordered]@{
      eid=$eid; kind=$kind; platformId=$plid; metric=$fcSpec.metric; action=$actionName; period=$periodLabel; type='number'
      display=(Format-FcCount $rng.base); displayLow=(Format-FcCount $rng.low); displayHigh=(Format-FcCount $rng.high)
      value=[math]::Round($rng.base,4); low=[math]::Round($rng.low,4); high=[math]::Round($rng.high,4)
      measuredDisplay=$tgt.curDisplay; measuredSource=$tgt.curSource
      statement=("Modeled estimate: {0} for {1} would have been about {2} (range {3} to {4}) with complete tracking; {5}." -f $what,$periodLabel,(Format-FcCount $rng.base),(Format-FcCount $rng.low),(Format-FcCount $rng.high),$rec)
      method='Several simple methods are computed side by side. Low is the smallest result, high is the largest, and the base blends the two lines of evidence: the tracked-day pace is weighted by the share of the period that was observed (the tracked days, or a supplied tracked window), and the prior-level methods (which count as one line of evidence) get the rest.'
      methods=@($mres.methods); skippedMethods=@($mres.skipped); crossChecks=@()
      uncertainty=(Get-FcUncertainty $mres.methods $rng $tgt)
    }
    [void]$items.Add($it)
    return $it
  }

  $totalItem = $null
  if($fcSpec.actions.Count -gt 0){
    # ---------------- per-action mode ----------------
    $ab = Get-FcActionBreakdown $plat $fcSpec.metric $fcSpec.actionDimension $fcSpec.actions
    if(-not $ab.ok){ throw ("INPUT: {0}. Per-action estimates need that breakdown; omit -Action to estimate the whole metric instead." -f $ab.reason) }
    $bd = $ab.breakdown
    $rows = @($bd.rows | Where-Object { $_.values -and $_.values.PSObject.Properties[$fcSpec.metric] })
    $complete = ([int]$bd.shown -eq [int]$bd.rowCount)
    $unRows = @($rows | Where-Object { $fcSpec.actions -notcontains [string]$_.label })
    $unaffected = @{ ok=$false; reason='every action in the breakdown is declared affected' }
    if(-not $complete){ $unaffected = @{ ok=$false; reason=("the breakdown shows {0} of {1} rows, so the unaffected remainder is not fully known" -f $bd.shown,$bd.rowCount) } }
    elseif($unRows.Count -gt 0){
      $uc = 0.0; $up = 0.0; $bad = $null
      foreach($r in $unRows){
        $cell = $r.values.($fcSpec.metric)
        $c = ConvertFrom-FcDisplay $cell.display; $p = $null
        if($cell.hasComparison -eq $true){ $p = ConvertFrom-FcDisplay (Get-FcProp $cell 'displayPrevious') }
        if($null -eq $c -or $null -eq $p){ $bad = [string]$r.label; break }
        $uc += $c; $up += $p
      }
      if($bad){ $unaffected = @{ ok=$false; reason="unaffected action '$bad' has no current or previous value" } }
      elseif($up -le 0){ $unaffected = @{ ok=$false; reason='the unaffected actions had no previous-period volume' } }
      else { $unaffected = @{ ok=$true; cur=$uc; prev=$up; curDisplay=(Format-FcCount $uc); prevDisplay=(Format-FcCount $up); names=((@($unRows | ForEach-Object { "'" + [string]$_.label + "'" })) -join ' + ')
                              source=("sum of the '{0}' breakdown rows not declared affected ({1})" -f $fcSpec.actionDimension,((@($unRows | ForEach-Object { [string]$_.label })) -join '; ')) } }
    }
    $actionItems = @(); $measAffected = 0.0
    foreach($a in $fcSpec.actions){
      $row = @($rows | Where-Object { [string]$_.label -eq $a })[0]
      $cell = $row.values.($fcSpec.metric)
      $cur = ConvertFrom-FcDisplay $cell.display
      $prev = $null; $prevDisp = $null
      if($cell.hasComparison -eq $true){ $prevDisp = [string](Get-FcProp $cell 'displayPrevious'); $prev = ConvertFrom-FcDisplay $prevDisp }
      $pt = _partial $a
      $floor = $cur; if($pt -and $pt.ok -and ($null -eq $floor -or $pt.value -gt $floor)){ $floor = $pt.value }
      $tgt = @{ label=$a; cur=$cur; curDisplay=[string]$cell.display; curSource=("facts breakdown '{0}' row '{1}' display" -f $fcSpec.actionDimension,$a)
                prev=$prev; prevDisplay=$prevDisp; prevSource=("facts breakdown '{0}' row '{1}' displayPrevious" -f $fcSpec.actionDimension,$a)
                clicks=$clicks; impressions=$impr; unaffected=$unaffected; period=$period; partial=$pt; ledgerRate=$null
                minTrackedDays=$minDays; compareOk=$compareOk; floor=$floor
                runRateObserved=$cur; runRateObservedDisplay=[string]$cell.display }
      if($pt -and $pt.ok){ $tgt.runRateObserved = $pt.value; $tgt.runRateObservedDisplay = $pt.display }
      $mres = Get-FcMethods $tgt
      if($mres.methods.Count -lt 2){
        $why = @($mres.skipped | ForEach-Object { "{0}: {1}" -f $_.id,$_.reason }) -join '; '
        [void]$refused.Add([ordered]@{ target=("'{0}' {1}" -f $a,$fcSpec.metric); reason=("only {0} method could be computed, and a range needs at least two ({1})" -f $mres.methods.Count,$why) })
        continue
      }
      $actionItems += (_item 'action' $a $mres $tgt)
      if($null -ne $cur){ $measAffected += $cur }
    }
    # account total = measured headline - recorded affected + estimated affected
    $tw = "'$($fcSpec.metric)' account total"
    if($actionItems.Count -ne $fcSpec.actions.Count){ [void]$refused.Add([ordered]@{ target=$tw; reason='not every declared action could be estimated; a total would mix estimates with figures known to be incomplete' }) }
    elseif(-not $hm.ok -or $null -eq $hCur){ $why = $hm.reason; if(-not $why){ $why = 'the headline has no current value' }; [void]$refused.Add([ordered]@{ target=$tw; reason=$why }) }
    elseif(-not $complete){ [void]$refused.Add([ordered]@{ target=$tw; reason=("the action breakdown shows {0} of {1} rows, so it cannot be reconciled to the headline" -f $bd.shown,$bd.rowCount) }) }
    else {
      $sum = 0.0; foreach($r in $rows){ $v = ConvertFrom-FcDisplay $r.values.($fcSpec.metric).display; if($null -ne $v){ $sum += $v } }
      $tol = 0.05 * $rows.Count + 0.06
      if([math]::Abs($sum - $hCur) -gt $tol){
        [void]$refused.Add([ordered]@{ target=$tw; reason=("the action rows sum to {0} but the headline is {1}; the breakdown is not the full account split, so estimates cannot be added back into the total" -f (Format-FcCount $sum),$hm.cell.displayCurrent) })
      } else {
        $eLow = 0.0; $eBase = 0.0; $eHigh = 0.0
        foreach($ai in $actionItems){ $eLow += $ai.low; $eBase += $ai.value; $eHigh += $ai.high }
        $tLow = $hCur - $measAffected + $eLow; $tBase = $hCur - $measAffected + $eBase; $tHigh = $hCur - $measAffected + $eHigh
        $eids = (@($actionItems | ForEach-Object { $_.eid }) -join ', ')
        $mk = {
          param($id,$nm,$val,$est)
          [ordered]@{ id=$id; family='bottom-up'; name=$nm; value=[math]::Round($val,4); display=(Format-FcCount $val)
            formula=("{0} measured total - {1} recorded for the affected action(s) + {2} estimated for them" -f $hm.cell.displayCurrent,(Format-FcCount $measAffected),(Format-FcCount $est))
            inputs=@((New-FcInput 'measured account total' $hCur ([string]$hm.cell.displayCurrent) ("facts headline '{0}' displayCurrent" -f $fcSpec.metric)),
                     (New-FcInput 'recorded for the affected action(s)' $measAffected (Format-FcCount $measAffected) ("sum of the affected rows of the '{0}' breakdown" -f $fcSpec.actionDimension)),
                     (New-FcInput 'estimated for the affected action(s)' ([math]::Round($est,4)) (Format-FcCount $est) ("estimates {0}" -f $eids)))
            assumption='the actions not declared affected are complete as measured' }
        }
        $tm = @((& $mk 'bottom-up-low' 'measured total with the low action estimate(s)' $tLow $eLow), (& $mk 'bottom-up-base' 'measured total with the base action estimate(s)' $tBase $eBase), (& $mk 'bottom-up-high' 'measured total with the high action estimate(s)' $tHigh $eHigh))
        $eid = 'EST#' + ($items.Count + 1)
        $totalItem = [ordered]@{
          eid=$eid; kind='total'; platformId=$plid; metric=$fcSpec.metric; action=$null; period=$periodLabel; type='number'
          display=(Format-FcCount $tBase); displayLow=(Format-FcCount $tLow); displayHigh=(Format-FcCount $tHigh)
          value=[math]::Round($tBase,4); low=[math]::Round($tLow,4); high=[math]::Round($tHigh,4)
          measuredDisplay=[string]$hm.cell.displayCurrent; measuredSource=("facts headline '{0}' displayCurrent" -f $fcSpec.metric)
          statement=("Modeled estimate: total '{0}' for {1} would have been about {2} (range {3} to {4}) with complete tracking; {5} were actually recorded." -f $fcSpec.metric,$periodLabel,(Format-FcCount $tBase),(Format-FcCount $tLow),(Format-FcCount $tHigh),$hm.cell.displayCurrent)
          method=("The measured total, with the affected action(s) swapped from what was recorded to what was estimated. The actions that kept tracking stay exactly as measured.")
          methods=$tm; skippedMethods=@(); crossChecks=@()
          uncertainty=("Range {0} to {1}, base {2}; the whole range comes from the affected-action estimate(s), so it inherits their uncertainty. This is a modeled figure, not a measurement." -f (Format-FcCount $tLow),(Format-FcCount $tHigh),(Format-FcCount $tBase))
        }
        [void]$items.Add($totalItem)
      }
    }
  } else {
    # ---------------- whole-metric mode ----------------
    if(-not $hm.ok){ throw ("INPUT: {0}." -f $hm.reason) }
    $pt = _partial $null
    if($null -eq $pt){ $pt = _partial '' }
    $floor = $hCur; if($pt -and $pt.ok -and ($null -eq $floor -or $pt.value -gt $floor)){ $floor = $pt.value }
    $tgt = @{ label=$fcSpec.metric; cur=$hCur; curDisplay=[string]$hm.cell.displayCurrent; curSource=("facts headline '{0}' displayCurrent" -f $fcSpec.metric)
              prev=$hPrev; prevDisplay=[string]$hm.cell.displayPrevious; prevSource=("facts headline '{0}' displayPrevious" -f $fcSpec.metric)
              clicks=$clicks; impressions=$impr; unaffected=$null; period=$period; partial=$pt; ledgerRate=$ledgerRate
              minTrackedDays=$minDays; compareOk=$compareOk; floor=$floor
              runRateObserved=$hCur; runRateObservedDisplay=[string]$hm.cell.displayCurrent }
    if($pt -and $pt.ok){ $tgt.runRateObserved = $pt.value; $tgt.runRateObservedDisplay = $pt.display }
    $mres = Get-FcMethods $tgt
    if($mres.methods.Count -lt 2){
      $why = @($mres.skipped | ForEach-Object { "{0}: {1}" -f $_.id,$_.reason }) -join '; '
      [void]$refused.Add([ordered]@{ target=("'{0}'" -f $fcSpec.metric); reason=("only {0} method could be computed, and a range needs at least two ({1})" -f $mres.methods.Count,$why) })
    } else {
      $totalItem = _item 'total' $null $mres $tgt
    }
  }

  # ---------------- cross-check + dependent metrics (need an account total) ----------------
  if($totalItem){
    if($fcSpec.actions.Count -gt 0 -and $fcSpec.metric -eq 'Conversions'){
      if($ledgerRate.ok -and $clicks.ok){
        $lv = [double]$ledgerRate.mean * [double]$clicks.cur
        $inside = ($lv -ge $totalItem.low -and $lv -le $totalItem.high)
        $word = 'inside'; if($lv -lt $totalItem.low){ $word = 'below' } elseif($lv -gt $totalItem.high){ $word = 'above' }
        $totalItem.crossChecks = @([ordered]@{ id='ledger-rate'; display=(Format-FcCount $lv); value=[math]::Round($lv,4); withinRange=$inside
          explanation=("Independent check from the client's history: {0} average conversion rate over {1} to {2} x {3} current-period clicks = {4}, which is {5} the estimated range. It is a check, not part of the estimate, because it ignores what the unaffected actions actually measured." -f $ledgerRate.display,$ledgerRate.months[0],$ledgerRate.months[-1],$clicks.curDisplay,(Format-FcCount $lv),$word)
          inputs=@((New-FcInput 'trailing average conversion rate' $ledgerRate.mean $ledgerRate.display $ledgerRate.source), (New-FcInput 'current-period clicks' $clicks.cur $clicks.curDisplay $clicks.curSource)) })
      } else {
        $why = $ledgerRate.reason; if($ledgerRate.ok){ $why = 'current-period clicks are not available' }
        $totalItem.skippedMethods = @($totalItem.skippedMethods) + @([ordered]@{ id='ledger-rate (cross-check)'; reason=[string]$why })
      }
    }
    if($fcSpec.metric -eq 'Conversions'){
      # conversion rate = conversions / clicks (verified on the measured figures before it is reused)
      $tw = "'$($fcSpec.names.conversionRate)'"
      if(-not $hRate.ok){ [void]$refused.Add([ordered]@{ target=$tw; reason=$hRate.reason }) }
      elseif(-not $clicks.ok){ [void]$refused.Add([ordered]@{ target=$tw; reason=("clicks: {0}" -f $clicks.reason) }) }
      elseif($null -eq $hCur -or [string]$hRate.cell.unit -ne 'fraction' -or -not (Test-FcNum $hRate.cell.current) -or $clicks.cur -le 0){ [void]$refused.Add([ordered]@{ target=$tw; reason='the measured conversion rate, conversions or clicks are not usable numbers' }) }
      elseif(-not $rateIdOk){ [void]$refused.Add([ordered]@{ target=$tw; reason=("in this report the measured rate ({0}) is not conversions / clicks, so the tool will not rebuild it from an estimate" -f $hRate.cell.displayCurrent) }) }
      else {
        $rl = $totalItem.low/$clicks.cur; $rb = $totalItem.value/$clicks.cur; $rh = $totalItem.high/$clicks.cur
        $eid = 'EST#' + ($items.Count + 1)
        [void]$items.Add([ordered]@{
          eid=$eid; kind='dependent'; platformId=$plid; metric=$fcSpec.names.conversionRate; action=$null; period=$periodLabel; type='percent'
          display=(Format-FcPercent $rb); displayLow=(Format-FcPercent $rl); displayHigh=(Format-FcPercent $rh)
          value=[math]::Round($rb,6); low=[math]::Round($rl,6); high=[math]::Round($rh,6)
          measuredDisplay=[string]$hRate.cell.displayCurrent; measuredSource=("facts headline '{0}' displayCurrent" -f $fcSpec.names.conversionRate)
          statement=("Modeled estimate: '{0}' for {1} would have been about {2} (range {3} to {4}) with complete tracking; {5} was measured." -f $fcSpec.names.conversionRate,$periodLabel,(Format-FcPercent $rb),(Format-FcPercent $rl),(Format-FcPercent $rh),$hRate.cell.displayCurrent)
          method=("Estimated total conversions divided by the measured clicks. The same division reproduces the measured rate from the measured conversions, which is how the tool confirmed the definition.")
          methods=@([ordered]@{ id='from-estimated-total'; family='dependent'; name='estimated conversions / measured clicks'; value=[math]::Round($rb,6); display=(Format-FcPercent $rb)
            formula=("{0} estimated conversions / {1} clicks (low {2}, high {3})" -f $totalItem.display,$clicks.curDisplay,$totalItem.displayLow,$totalItem.displayHigh)
            inputs=@((New-FcInput 'estimated total conversions (base)' $totalItem.value $totalItem.display ("estimate {0}" -f $totalItem.eid)), (New-FcInput 'estimated total conversions (low)' $totalItem.low $totalItem.displayLow ("estimate {0}" -f $totalItem.eid)), (New-FcInput 'estimated total conversions (high)' $totalItem.high $totalItem.displayHigh ("estimate {0}" -f $totalItem.eid)), (New-FcInput 'current-period clicks' $clicks.cur $clicks.curDisplay $clicks.curSource))
            assumption='clicks were measured completely; only conversions were lost' })
          skippedMethods=@(); crossChecks=@()
          uncertainty=("Range {0} to {1}, base {2}; it moves one-for-one with the conversions estimate. This is a modeled figure, not a measurement." -f (Format-FcPercent $rl),(Format-FcPercent $rh),(Format-FcPercent $rb))
        })
      }
      # cost per conversion = cost / conversions
      $tw = "'$($fcSpec.names.costPerConversion)'"
      $cost = $null; if($hCost.ok){ $cost = Get-FcRaw $hCost.cell 'current' }
      $cpaCur = $null; if($hCpa.ok){ $cpaCur = Get-FcRaw $hCpa.cell 'current' }
      if(-not $hCpa.ok){ [void]$refused.Add([ordered]@{ target=$tw; reason=$hCpa.reason }) }
      elseif(-not $hCost.ok){ [void]$refused.Add([ordered]@{ target=$tw; reason=$hCost.reason }) }
      elseif($null -eq $cost -or $null -eq $cpaCur -or $null -eq $hCur -or $hCur -le 0 -or $cpaCur -le 0){ [void]$refused.Add([ordered]@{ target=$tw; reason='the measured cost, cost per conversion or conversions are not usable numbers' }) }
      elseif([math]::Abs(($cost/$hCur) - $cpaCur) / $cpaCur -gt 0.005){ [void]$refused.Add([ordered]@{ target=$tw; reason=("in this report the measured cost per conversion ({0}) is not cost / conversions, so the tool will not rebuild it from an estimate" -f $hCpa.cell.displayCurrent) }) }
      elseif($totalItem.low -le 0){ [void]$refused.Add([ordered]@{ target=$tw; reason='the low conversions estimate is zero' }) }
      else {
        $cur3 = $hCpa.cell.currency
        $cb = $cost/$totalItem.value; $cLo = $cost/$totalItem.high; $cHi = $cost/$totalItem.low   # more conversions -> lower cost each
        $eid = 'EST#' + ($items.Count + 1)
        $cc = @(); $sk = @()
        if($ledgerCpa.ok){
          $cc = @([ordered]@{ id='ledger-cost-per-conversion'; display=$ledgerCpa.display; value=[math]::Round($ledgerCpa.mean,4); withinRange=($ledgerCpa.mean -ge $cLo -and $ledgerCpa.mean -le $cHi)
            explanation=("For context from the client's history: the average monthly cost per conversion over {0} to {1} was {2}." -f $ledgerCpa.months[0],$ledgerCpa.months[-1],$ledgerCpa.display)
            inputs=@((New-FcInput 'trailing average cost per conversion' ([math]::Round($ledgerCpa.mean,4)) $ledgerCpa.display $ledgerCpa.source)) })
        } elseif($ledgerCpa.reason){ $sk = @([ordered]@{ id='ledger-cost-per-conversion (context)'; reason=[string]$ledgerCpa.reason }) }
        [void]$items.Add([ordered]@{
          eid=$eid; kind='dependent'; platformId=$plid; metric=$fcSpec.names.costPerConversion; action=$null; period=$periodLabel; type='currency'
          display=(Format-FcMoney $cb $cur3); displayLow=(Format-FcMoney $cLo $cur3); displayHigh=(Format-FcMoney $cHi $cur3)
          value=[math]::Round($cb,4); low=[math]::Round($cLo,4); high=[math]::Round($cHi,4)
          measuredDisplay=[string]$hCpa.cell.displayCurrent; measuredSource=("facts headline '{0}' displayCurrent" -f $fcSpec.names.costPerConversion)
          statement=("Modeled estimate: '{0}' for {1} would have been about {2} (range {3} to {4}) with complete tracking; {5} was measured." -f $fcSpec.names.costPerConversion,$periodLabel,(Format-FcMoney $cb $cur3),(Format-FcMoney $cLo $cur3),(Format-FcMoney $cHi $cur3),$hCpa.cell.displayCurrent)
          method=("Measured cost divided by the estimated total conversions. The same division reproduces the measured cost per conversion from the measured conversions, which is how the tool confirmed the definition. Cost itself is measured, not estimated.")
          methods=@([ordered]@{ id='from-estimated-total'; family='dependent'; name='measured cost / estimated conversions'; value=[math]::Round($cb,4); display=(Format-FcMoney $cb $cur3)
            formula=("{0} cost / {1} estimated conversions (the high conversions estimate {2} gives the low cost, the low estimate {3} gives the high cost)" -f $hCost.cell.displayCurrent,$totalItem.display,$totalItem.displayHigh,$totalItem.displayLow)
            inputs=@((New-FcInput 'measured cost' $cost ([string]$hCost.cell.displayCurrent) ("facts headline '{0}' displayCurrent" -f $fcSpec.names.cost)), (New-FcInput 'estimated total conversions (base)' $totalItem.value $totalItem.display ("estimate {0}" -f $totalItem.eid)), (New-FcInput 'estimated total conversions (low)' $totalItem.low $totalItem.displayLow ("estimate {0}" -f $totalItem.eid)), (New-FcInput 'estimated total conversions (high)' $totalItem.high $totalItem.displayHigh ("estimate {0}" -f $totalItem.eid)))
            assumption='cost was measured completely; only conversions were lost' })
          skippedMethods=$sk; crossChecks=$cc
          uncertainty=("Range {0} to {1}, base {2}; it moves inversely with the conversions estimate. This is a modeled figure, not a measurement." -f (Format-FcMoney $cLo $cur3),(Format-FcMoney $cHi $cur3),(Format-FcMoney $cb $cur3))
        })
      }
    }
  }

  if(-not $nowIso){ $nowIso = (Get-Date).ToString('o') }
  $declared = [ordered]@{ declaredBy=$fcSpec.declaredBy; platformId=$plid; metric=$fcSpec.metric; actions=@($fcSpec.actions); outageStart=$fcSpec.outageStart; outageEnd=$fcSpec.outageEnd
                          period=$periodLabel; periodDays=$perDays; outageDays=$outDays; trackedDays=$tracked }
  return [ordered]@{
    tool='Invoke-SwydoForecast.ps1'; estimatesVersion=1; generatedAt=$nowIso; label=$script:FcLabel
    disclosure='These figures are modeled estimates of what a declared-incomplete metric would have been. They are not measurements, they are computed only because the data was declared incomplete, and they may be cited only inside the "Estimates (modeled)" section with their range.'
    declared=$declared; items=@($items); refused=@($refused)
  }
}

# ---- textual splice: add/replace the block without re-serializing the measured facts ----
function Find-FcTopLevelMember($text,$name){
  # locate the top-level member "<name>": <value> by scanning the JSON text (strings and nesting
  # respected). -> @{ keyStart; valueEnd } where valueEnd indexes the ',' or '}' after the value, or $null.
  $depth = 0; $inStr = $false; $esc = $false; $strStart = -1; $lastStr = $null; $keyStart = -1
  $n = $text.Length
  for($i = 0; $i -lt $n; $i++){
    $ch = $text[$i]
    if($inStr){
      if($esc){ $esc = $false }
      elseif($ch -eq '\'){ $esc = $true }
      elseif($ch -eq '"'){ $inStr = $false; if($depth -eq 1){ $lastStr = @{ start=$strStart; text=$text.Substring($strStart+1,$i-$strStart-1) } } }
      continue
    }
    if($ch -eq '"'){ $inStr = $true; $strStart = $i }
    elseif($ch -eq ':'){ if($depth -eq 1 -and $keyStart -lt 0 -and $lastStr -and $lastStr.text -ceq $name){ $keyStart = $lastStr.start }; $lastStr = $null }
    elseif($ch -eq '{' -or $ch -eq '['){ $depth++ }
    elseif($ch -eq ']'){ $depth-- }
    elseif($ch -eq '}'){ $depth--; if($depth -eq 0 -and $keyStart -ge 0){ return @{ keyStart=$keyStart; valueEnd=$i } } }
    elseif($ch -eq ','){ if($depth -eq 1){ if($keyStart -ge 0){ return @{ keyStart=$keyStart; valueEnd=$i } }; $lastStr = $null } }
  }
  return $null
}
function Remove-FcBlock($factsText){
  # drop an existing top-level `estimates` member wherever it sits; every other byte is kept.
  $t = [string]$factsText
  $span = Find-FcTopLevelMember $t 'estimates'
  if($null -eq $span){ return $t }
  $head = $t.Substring(0,$span.keyStart).TrimEnd()
  $tail = $t.Substring($span.valueEnd)                  # starts at ',' (more members follow) or the closing '}'
  if($tail.StartsWith(',')){ $tail = $tail.Substring(1) }
  elseif($head.EndsWith(',')){ $head = $head.Substring(0,$head.Length-1) }
  return ($head + $tail)
}
function Add-FcBlock($factsText,$block){
  # -> facts text with `estimates` as the LAST top-level member (replacing any earlier one).
  $t = Remove-FcBlock $factsText
  $end = $t.LastIndexOf('}')
  if($end -lt 0){ throw 'INPUT: the facts file is not a JSON object.' }
  $head = $t.Substring(0,$end).TrimEnd()
  $sep = ','; if($head.EndsWith('{')){ $sep = '' }
  $json = ConvertTo-Json -InputObject $block -Depth 20 -Compress
  $out = $head + $sep + '"estimates":' + $json + $t.Substring($end)
  # verify: still parses, the block is there, and no other top-level member appeared or vanished
  $before = @(($t | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $_.Name })
  $chk = $out | ConvertFrom-Json
  $after = @($chk.PSObject.Properties | ForEach-Object { $_.Name } | Where-Object { $_ -ne 'estimates' })
  if($null -eq $chk.estimates -or @($chk.estimates.items).Count -ne @($block.items).Count -or (($before -join '|') -ne ($after -join '|'))){ throw 'internal: spliced facts failed re-parse verification' }
  return $out
}

if($DefineOnly){ return }

# ---- run ----
function Stop-FcUsage($msg){ [Console]::Error.WriteLine("Invoke-SwydoForecast: $msg"); exit 2 }
function Resolve-FcPath($p){
  # resolve ONCE against the PowerShell location. [IO.File] resolves against the PROCESS directory, which
  # differs after Set-Location - mixing the two could read one file and overwrite another.
  if(-not $p){ return '' }
  return $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath([string]$p)
}
function Read-FcJson($path,$what){
  # credential gate BEFORE anything is parsed or echoed; unparseable JSON is a usage error (exit 2)
  if(-not (Test-Path -LiteralPath $path)){ Stop-FcUsage "$what not found: $path" }
  $text = [IO.File]::ReadAllText($path)
  if($text -match $script:FcCredRx){ Stop-FcUsage "the $what file carries a share credential (a raw extraction is never a valid input). Refusing to read it further." }
  $parsed = $null
  try { $parsed = $text | ConvertFrom-Json } catch { Stop-FcUsage "the $what file is not valid JSON: $path" }
  return @{ text=$text; doc=$parsed }
}
function Write-FcText($path,$text){
  # write beside the target, then copy over it: the original is never deleted first
  $tmp = $path + '.fc-tmp'
  [IO.File]::WriteAllText($tmp,$text,(New-Object Text.UTF8Encoding($false)))
  [IO.File]::Copy($tmp,$path,$true)
  [IO.File]::Delete($tmp)
}
if(-not $Facts){ Stop-FcUsage 'usage: Invoke-SwydoForecast.ps1 -Facts <facts.json> -DeclaredBy <who> -OutageStart <yyyy-MM-dd> -OutageEnd <yyyy-MM-dd> [-Action "<name>[;<name>]"] [-Metric <name>] [-Ledger <ledger.json>] [-Spec <spec.json>]' }
if($MinTrackedDays -lt 1){ Stop-FcUsage '-MinTrackedDays must be at least 1.' }
$myFactsPath = Resolve-FcPath $Facts; $myLedgerPath = Resolve-FcPath $Ledger; $mySpecPath = Resolve-FcPath $Spec; $myOutFile = Resolve-FcPath $OutFile
$myIn = Read-FcJson $myFactsPath 'facts'
$myFactsText = $myIn.text; $myFactsDoc = $myIn.doc
if($null -eq $myFactsDoc -or $null -eq $myFactsDoc.meta -or [string]$myFactsDoc.meta.tool -ne 'Analyze-SwydoReport.ps1'){ Stop-FcUsage 'the input is not a facts file written by Analyze-SwydoReport.ps1 (trend facts and raw extractions are not supported).' }
$myLedgerDoc = $null
if($myLedgerPath){ $myLedgerDoc = (Read-FcJson $myLedgerPath 'ledger').doc }
$mySpecObj = $null
if($mySpecPath){ $mySpecObj = (Read-FcJson $mySpecPath 'spec').doc }
try {
  $mySpec = Resolve-FcSpec $mySpecObj @{ declaredBy=$DeclaredBy; platform=$Platform; metric=$Metric; action=$Action; outageStart=$OutageStart; outageEnd=$OutageEnd }
  $myBlock = Get-FcEstimates $myFactsDoc $myLedgerDoc $mySpec $HistoryMonths $MinTrackedDays
} catch {
  $m = [string]$_.Exception.Message
  if($m.StartsWith('INPUT: ')){ Stop-FcUsage $m.Substring(7) }
  throw
}
foreach($r in @($myBlock.refused)){ Write-Host ("REFUSED {0}: {1}" -f $r.target,$r.reason) }
foreach($it in @($myBlock.items)){
  foreach($v in @($it.value,$it.low,$it.high)){
    if($null -eq $v -or [double]::IsNaN([double]$v) -or [double]::IsInfinity([double]$v)){ Stop-FcUsage ("internal: estimate {0} is not a finite number; nothing was written." -f $it.eid) }
  }
}
if(-not $myOutFile){ $myOutFile = $myFactsPath }
if(@($myBlock.items).Count -eq 0){
  # nothing to write - but an estimates block from an EARLIER run must not outlive this refusal
  $myClean = Remove-FcBlock $myFactsText
  if($myClean -ne $myFactsText -and $myOutFile -eq $myFactsPath){
    Write-FcText $myFactsPath $myClean
    Write-Host 'Invoke-SwydoForecast: no estimate could be produced; the estimates block left by an earlier run was removed.'
  } else {
    Write-Host 'Invoke-SwydoForecast: no estimate could be produced; nothing was written.'
  }
  exit 1
}
try { $myOutText = Add-FcBlock $myFactsText $myBlock }
catch { $m = [string]$_.Exception.Message; if($m.StartsWith('INPUT: ')){ Stop-FcUsage $m.Substring(7) }; Stop-FcUsage ("could not add the estimates block to the facts ({0}); nothing was written." -f $m) }
if($myOutText -match $script:FcCredRx){ Stop-FcUsage 'refusing to write: output would carry a share credential.' }
Write-FcText $myOutFile $myOutText
foreach($it in @($myBlock.items)){
  $what = $it.metric; if($it.action){ $what = "'{0}' {1}" -f $it.action,$it.metric }
  Write-Host ("{0} {1}: {2} (range {3} to {4}); measured {5}" -f $it.eid,$what,$it.display,$it.displayLow,$it.displayHigh,$it.measuredDisplay)
}
Write-Host ("Invoke-SwydoForecast: {0} estimate(s), {1} refused -> {2}" -f @($myBlock.items).Count,@($myBlock.refused).Count,$myOutFile)
exit 0
