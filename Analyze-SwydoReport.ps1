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
# Per-category rule config (spec 13.12): effort->result pairs (metric-part regexes) generalize
# "effort with no result"; 'constrained'/'ranking' drive category-special rules. Metric-parts are lowercased.
$script:RuleCfg = @{
  'ads'           = @{ effort=@(@{e='(cost_micros|(^|_)cost$|spend)';r='(conversion|lead)'}, @{e='impression';r='(conversion|lead)'}); constrained='(search_lost_is|impression_share)' }
  'web-analytics' = @{ effort=@(@{e='session';r='conversion'}, @{e='(^|_)user';r='conversion'}) }
  'seo'           = @{ effort=@(@{e='impression';r='click'}); ranking='((^|_)position|(^|_)rank)' }
  'email-crm'     = @{ effort=@(@{e='send';r='open'}, @{e='open';r='click'}) }
  'ecommerce'     = @{ effort=@(@{e='session';r='order'}, @{e='add_to_cart';r='order'}) }
  'calls'         = @{ effort=@(@{e='(^|_)call';r='(qualified|converted)'}) }
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
# What FORM the value takes in prose, so the closer can require prose-token type to match (kills $1.1 vs 1.1%).
# Order matters: fraction first, then ratio-like, then money (id-gated + non-money-micros denylist), else number.
function Metric-Type($id,$unit,$currency){
  $p = Get-MetricPart $id
  if($unit -eq 'fraction'){ return 'percent' }
  if($p -match 'roas|frequency|(^|_)score|quality|(^|_)position|(^|_)rank|aov|per_user|(^|_)ratio$'){ return 'ratio' }
  if($p -notmatch 'engagement_time|_time_micros|duration|(^|_)seconds' -and $p -match 'cost|spend|cpc|cpm|cpa|cpl|revenue|budget|amount_spent|cost_per'){ return 'currency' }
  return 'number'
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
# first metric in a widget whose metric-part matches a regex (for config-driven rules)
function Find-Metric($w,$pat){ if($w.metrics){ foreach($m in $w.metrics){ if((Get-MetricPart $m.id) -match $pat){ return $m } } } return $null }
function Row-Cur($row,$name){ $c=$row.metrics.$name; if($c -and ($c.current -is [double] -or $c.current -is [int] -or $c.current -is [long] -or $c.current -is [decimal])){ return [double]$c.current } return $null }
function Row-Cmp($row,$name){ $c=$row.metrics.$name; if($c -and ($c.compare -is [double] -or $c.compare -is [int] -or $c.compare -is [long] -or $c.compare -is [decimal])){ return [double]$c.compare } return $null }
function Row-Label($row){ $ps=@($row.dimensions.PSObject.Properties); if($ps.Count -gt 0){ return $ps[0].Value } return $null }
function Total-Row($w){ $t=@($w.rows | Where-Object { $_.kind -eq 'total' }); if($t.Count -gt 0){ return $t[0] }; $t=@($w.rows|Where-Object{$_.kind -eq 'data'}); if($t.Count -gt 0){return $t[0]}; return $null }
# Row-level breakdown findings for ONE widget (concentration, new/paused, segment-divergence,
# effort->result, share-mismatch). Pure over the widget + $script:RuleCfg; returns a findings array.
function Get-BreakdownFindings($w){
  $out=[System.Collections.ArrayList]@()
  $wdims=@($w.dimensions); if($wdims.Count -eq 0){ return @() }
  $tr=Total-Row $w; if(-not $tr){ return @() }
  $wprov = if($w.providers -and $w.providers.Count -gt 0){ $w.providers[0].id } else { (@($w.metrics)[0].id -split ':')[0] }
  $wcat = Get-Category $wprov
  $pname = if($w.providers -and $w.providers.Count -gt 0 -and $w.providers[0].name){ $w.providers[0].name } else { $wprov }
  $cc=$w.currencyCode; $dimName=$wdims[0]
  $detail=@($w.rows | Where-Object { $_.kind -eq 'data' -and -not (Test-GroupRow (Row-Label $_)) })
  if($detail.Count -eq 0){ return @() }
  # ANOM_CONCENTRATION
  $primary=$null; foreach($m in @($w.metrics)){ if((Get-Direction $m.id) -eq 'higher-better' -and (Test-Additive $m.id)){ $primary=$m; break } }
  if($primary){ $tot=Row-Cur $tr $primary.name
    if($tot -and $tot -gt 0){ foreach($r in $detail){ $v=Row-Cur $r $primary.name; if($null -ne $v -and ($v/$tot) -ge 0.5){ $sh=[math]::Round(($v/$tot)*100,0)
      [void]$out.Add([ordered]@{ ruleId='ANOM_CONCENTRATION'; severity='info'; platform=$pname; widget=$dimName; statement="${pname}: '$(Row-Label $r)' is $sh% of $($primary.name) ($(Format-Metric $primary.id $primary.unit $v $cc) of $(Format-Metric $primary.id $primary.unit $tot $cc))"; evidence=[ordered]@{ share="$sh%" } }); break } } } }
  # ANOM_SEGMENT_DIVERGENCE + NEW/PAUSED (comparison-gated, grain-capped)
  if($primary){
    $ptot=Row-Cur $tr $primary.name; $ptotPrev=Row-Cmp $tr $primary.name
    $totDelta=Get-DeltaPct $ptot $ptotPrev
    $nNP=0; $nDiv=0
    foreach($r in $detail){
      $rv=Row-Cur $r $primary.name; $rp=Row-Cmp $r $primary.name
      if($null -eq $rv -or $null -eq $rp){ continue }
      $share=if($ptot -and $ptot -gt 0){ $rv/$ptot } else { 0 }
      if($rv -gt 0 -and $rp -eq 0 -and $share -ge 0.05 -and $nNP -lt 5){ $nNP++
        [void]$out.Add([ordered]@{ ruleId='ANOM_NEW'; severity='info'; platform=$pname; widget=$dimName; statement="${pname}: '$(Row-Label $r)' is new this period ($($primary.name) $(Format-Metric $primary.id $primary.unit $rv $cc), was 0)" }) }
      elseif($rv -eq 0 -and $rp -gt 0 -and $nNP -lt 5){ $nNP++
        [void]$out.Add([ordered]@{ ruleId='ANOM_PAUSED'; severity='major'; platform=$pname; widget=$dimName; statement="${pname}: '$(Row-Label $r)' stopped ($($primary.name) 0 this period, was $(Format-Metric $primary.id $primary.unit $rp $cc))" }) }
      elseif($rv -gt 0 -and $rp -gt 0 -and $share -ge 0.15 -and $null -ne $totDelta -and $nDiv -lt 5){
        $rd=Get-DeltaPct $rv $rp
        if($null -ne $rd){ $diverges=(($rd -gt 0) -ne ($totDelta -gt 0)) -or ([math]::Abs($rd-$totDelta) -ge 50)
          if($diverges){ $nDiv++
            [void]$out.Add([ordered]@{ ruleId='ANOM_SEGMENT_DIVERGENCE'; severity='info'; platform=$pname; widget=$dimName; statement="${pname}: '$(Row-Label $r)' $($primary.name) moved $(Format-Delta $rd) vs the $($primary.name) total $(Format-Delta $totDelta)"; evidence=[ordered]@{ rowDelta=(Format-Delta $rd); totalDelta=(Format-Delta $totDelta) } }) } } }
    }
  }
  # config-driven effort->result + share-mismatch
  $cfg=$script:RuleCfg[$wcat]
  if($cfg -and $cfg.effort){
    foreach($pair in $cfg.effort){
      $em=Find-Metric $w $pair.e; $rm=Find-Metric $w $pair.r
      if(-not $em -or -not $rm -or $em.id -eq $rm.id){ continue }
      $totE=Row-Cur $tr $em.name; $totR=Row-Cur $tr $rm.name
      if(-not $totE -or $totE -le 0){ continue }
      $nEmpty=0
      foreach($r in $detail){
        $re=Row-Cur $r $em.name; $rr=Row-Cur $r $rm.name
        if($null -eq $re){ continue }
        $eShare=$re/$totE
        if($eShare -ge 0.02 -and $rr -eq 0){ if($nEmpty -lt 8){ $nEmpty++
          [void]$out.Add([ordered]@{ ruleId='ANOM_EFFORT_NO_RESULT'; severity='major'; platform=$pname; widget=$dimName; requiresDownstreamData=$false; statement="${pname}: '$(Row-Label $r)' used $([math]::Round($eShare*100,0))% of $($em.name) ($(Format-Metric $em.id $em.unit $re $cc)) with 0 $($rm.name)"; evidence=[ordered]@{ effort=(Format-Metric $em.id $em.unit $re $cc); result='0'; effortShare="$([math]::Round($eShare*100,0))%" } }) } }
        elseif($totR -and $totR -gt 0 -and $null -ne $rr -and $rr -gt 0 -and $eShare -ge 0.10){
          $rShare=$rr/$totR
          if(($eShare/$rShare) -ge 3){ $hint=([string](Row-Label $r)) -match '(?i)awareness|brand|video|launch|opening'; $sev=if($hint){'info'}else{'major'}
            [void]$out.Add([ordered]@{ ruleId='ANOM_SHARE_MISMATCH'; severity=$sev; platform=$pname; widget=$dimName; requiresDownstreamData=$true; statement="${pname}: '$(Row-Label $r)' is $([math]::Round($eShare*100,0))% of $($em.name) but only $([math]::Round($rShare*100,1))% of $($rm.name)$(if($hint){' (looks upper-funnel/awareness)'})"; evidence=[ordered]@{ effortShare="$([math]::Round($eShare*100,0))%"; resultShare="$([math]::Round($rShare*100,1))%" } }) }
        }
      }
    }
  }
  return @($out)
}
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
# Per-widget breakdown table for the facts: top-`cap` rows (display-only, tagged), force-including
# any label in $mustLabels (finding-referenced). Row labels via Row-Label (NOT Get-DimLabel).
function Get-Breakdown($w, $cap, $mustLabels){
  if(@($w.dimensions).Count -eq 0){ return $null }
  $cc=$w.currencyCode; $wdims=@($w.dimensions); $dimName=$wdims[0]
  $wprov = if($w.providers -and $w.providers.Count -gt 0){ $w.providers[0].id } else { (@($w.metrics)[0].id -split ':')[0] }
  $wcat = Get-Category $wprov
  $mets=@($w.metrics)
  $detail=@($w.rows | Where-Object { $_.kind -eq 'data' -and -not (Test-GroupRow (Row-Label $_)) })
  if($detail.Count -eq 0){ return $null }
  $isTime = ($dimName -match '(?i)day|week|month|date')
  $orderMet=$null
  if($wcat -eq 'ads'){ foreach($m in $mets){ if((Get-MetricPart $m.id) -match '(cost_micros|(^|_)cost$|spend)'){ $orderMet=$m; break } } }
  if(-not $orderMet){ foreach($m in $mets){ if((Get-Direction $m.id) -eq 'higher-better' -and (Test-Additive $m.id)){ $orderMet=$m; break } } }
  if($isTime){ $sorted=@($detail | Sort-Object { [string](Row-Label $_) }) }
  elseif($orderMet){ $sorted=@($detail | Sort-Object { $v=Row-Cur $_ $orderMet.name; if($null -eq $v){0}else{[double]$v} } -Descending) }
  else { $sorted=@($detail) }
  $top=@($sorted | Select-Object -First $cap)
  if($mustLabels){ foreach($r in $sorted){ $lbl=[string](Row-Label $r); if(($mustLabels -contains $lbl) -and -not @($top | Where-Object { [string](Row-Label $_) -eq $lbl })){ $top+=$r } } }
  $rows=@()
  foreach($r in $top){
    $vals=[ordered]@{}
    foreach($m in $mets){
      $cur=Row-Cur $r $m.name
      if($null -eq $cur){ continue }   # scalar-guard (echo objects)
      $cell=[ordered]@{ display=(Format-Metric $m.id $m.unit $cur $cc); type=(Metric-Type $m.id $m.unit $cc) }
      $cmp=Row-Cmp $r $m.name
      if($null -ne $cmp){ $cell.hasComparison=$true; $cell.displayPrevious=(Format-Metric $m.id $m.unit $cmp $cc); $d=Get-DeltaPct $cur $cmp; if($null -ne $d){ $cell.delta=(Format-Delta $d) } } else { $cell.hasComparison=$false }
      $vals[[string]$m.name]=$cell
    }
    $rows+=[ordered]@{ label=[string](Row-Label $r); values=$vals }
  }
  $out=[ordered]@{ widgetId=$w.id; dimensions=$wdims; metricNames=@($mets|ForEach-Object{$_.name}); rowCount=$detail.Count; shown=$rows.Count; rows=$rows }
  if($detail.Count -gt $rows.Count){ $out.note="showing top $($rows.Count) of $($detail.Count) rows" }
  return $out
}

function Format-Money($val,$currency){ if($null -eq $val){ return $null }; $sym=if($currency -and $script:CurSym[$currency]){ $script:CurSym[$currency] } elseif($currency){ "$currency " } else { '$' }; return ("{0}{1:N2}" -f $sym,$val) }
# Time-series derived metrics + pacing for a time-dimension widget. Derived = ONLY metrics with no
# native equivalent (in practice CPL / cost-per-conv), category-gated. Pacing exposes the ordered series.
function Get-TimeSeries($w){
  $wdims=@($w.dimensions); if($wdims.Count -eq 0){ return $null }
  $dimName=$wdims[0]
  if($dimName -notmatch '(?i)^(day|week|month|date)$'){ return $null }
  $cc=$w.currencyCode
  $wprov = if($w.providers -and $w.providers.Count -gt 0){ $w.providers[0].id } else { (@($w.metrics)[0].id -split ':')[0] }
  $wcat = Get-Category $wprov
  $detail=@($w.rows | Where-Object { $_.kind -eq 'data' -and -not (Test-GroupRow (Row-Label $_)) })
  if($detail.Count -lt 2){ return $null }
  $labels=@($detail | ForEach-Object { [string](Row-Label $_) })
  $orderConf = if(@($labels | Where-Object { $_ -notmatch '^\d{4}-\d{2}(-\d{2})?$|^\d{6}$' }).Count -eq 0){ 'confirmed' } else { 'unconfirmed' }
  $sorted=@($detail | Sort-Object { [string](Row-Label $_) })
  # derived defs: only NON-native, category-gated to ads/ecommerce
  $derivedDefs=@()
  if($wcat -eq 'ads' -or $wcat -eq 'ecommerce'){
    $money=Find-Metric $w '(cost_micros|(^|_)cost$|spend|revenue)'
    $leadM=Find-Metric $w '(^|_)lead|actions::lead'
    $convM=Find-Metric $w '(^|:)conversions$'
    if($money -and $leadM -and -not (Find-Metric $w 'cost_per.*lead|costperactiontype::lead')){ $derivedDefs+=@{name='CPL'; num=$money; den=$leadM} }
    if($money -and $convM -and -not (Find-Metric $w 'cost_per_conversion')){ $derivedDefs+=@{name='cost/conv'; num=$money; den=$convM} }
  }
  $buckets=@()
  foreach($r in $sorted){
    $b=[ordered]@{ label=[string](Row-Label $r) }
    if($derivedDefs.Count -gt 0){
      $der=[ordered]@{}; $gaps=@()
      foreach($dd in $derivedDefs){
        $numv=Row-Cur $r $dd.num.name; $denv=Row-Cur $r $dd.den.name
        if($null -eq $numv){ continue }
        if($null -eq $denv -or $denv -eq 0){ $der[$dd.name]=$null; $gaps+="$($dd.name): 0 $($dd.den.name)"; continue }
        $numBase = if($dd.num.unit -eq 'micros'){ [double]$numv/1e6 } else { [double]$numv }   # denominator RAW
        $der[$dd.name] = Format-Money ($numBase/[double]$denv) $cc
      }
      if($der.Count -gt 0){ $b.derived=$der }
      if($gaps.Count -gt 0){ $b.derivedGaps=$gaps }
    }
    $buckets+=$b
  }
  # pacing on the primary (higher-better additive, else money, else first)
  $primary=$null; foreach($m in @($w.metrics)){ if((Get-Direction $m.id) -eq 'higher-better' -and (Test-Additive $m.id)){ $primary=$m; break } }
  if(-not $primary){ foreach($m in @($w.metrics)){ if((Get-MetricPart $m.id) -match '(cost_micros|(^|_)cost$|spend|revenue)'){ $primary=$m; break } } }
  if(-not $primary -and @($w.metrics).Count -gt 0){ $primary=@($w.metrics)[0] }
  $out=[ordered]@{ widgetId=$w.id; dimension=$dimName; buckets=$buckets }
  if($primary){
    $seq=@(); foreach($r in $sorted){ $v=Row-Cur $r $primary.name; $seq+=[ordered]@{ label=[string](Row-Label $r); display=(Format-Metric $primary.id $primary.unit $v $cc) } }
    $nn=@($sorted | ForEach-Object { Row-Cur $_ $primary.name } | Where-Object { $null -ne $_ } | ForEach-Object { [double]$_ })
    $pacing=[ordered]@{ metric=$primary.name; series=$seq; orderConfidence=$orderConf }
    if($nn.Count -ge 2){
      $firstV=Row-Cur $sorted[0] $primary.name; $lastV=Row-Cur $sorted[-1] $primary.name
      $mn=($nn|Measure-Object -Minimum).Minimum; $mx=($nn|Measure-Object -Maximum).Maximum
      if($mn -gt 0){ $pacing.maxVsMinRatio=("{0:N1}x" -f ($mx/$mn)) }
      $net=Get-DeltaPct $lastV $firstV
      if($null -ne $net){ $pacing.netChange=(Format-Delta $net); $pacing.trend = if($net -gt 5){'rising'}elseif($net -lt -5){'declining'}else{'flat'} }
    }
    $out.pacing=$pacing
  }
  return $out
}

if($DefineOnly){ return }   # dot-source stops here

# ============================ run ============================
if(-not $InFile){ throw "InFile is required" }
if(-not $OutDir){ $OutDir = Split-Path -Parent $InFile }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$doc = [IO.File]::ReadAllText($InFile) | ConvertFrom-Json   # .NET UTF-8 (Get-Content -Raw mis-reads BOM-less UTF-8 as ANSI in PS 5.1)
# schema gate
if($doc.meta.schemaVersion -ne 2){ throw "unsupported schemaVersion (need 2, got '$($doc.meta.schemaVersion)') - re-extract with the current tool" }
if(-not $doc.report -or -not $doc.report.name -or -not $doc.widgets){ throw "not a valid v2 extraction (missing report/widgets)" }
$doc = Scrub-Credential $doc

$periods = Derive-Periods $doc.meta.extractedAt $doc.report.dateRange
$dataWidgets = @($doc.widgets | Where-Object { $_.kind -eq 'data' })
if($dataWidgets.Count -eq 0){ throw "no data widgets to analyze (all text/empty)" }


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
      metric=$m.name; id=$m.id; unit=$m.unit; type=(Metric-Type $m.id $m.unit $cc); direction=$dir; currency=$cc
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
# ANOM_BUDGET_CONSTRAINED: category-special (ads) - impressions lost to budget past threshold
foreach($pk in $platforms.Keys){
  $pf=$platforms[$pk]; $cfg=$script:RuleCfg[$pf.category]
  if(-not $cfg -or -not $cfg.constrained){ continue }
  foreach($hk in $pf.headline.Keys){
    $h=$pf.headline[$hk]
    if((Get-MetricPart $h.id) -match 'search_lost_is' -and $null -ne $h.current -and [double]$h.current -ge 0.10){
      $isTxt=''; foreach($hk2 in $pf.headline.Keys){ if((Get-MetricPart $pf.headline[$hk2].id) -match 'impression_share'){ $isTxt=" (impression share $($pf.headline[$hk2].displayCurrent))" } }
      [void]$anoms.Add([ordered]@{ ruleId='ANOM_BUDGET_CONSTRAINED'; severity='major'; platform=$pf.name; metric=$h.metric; statement="$($pf.name) is budget-constrained: $($h.displayCurrent) of impressions lost to budget$isTxt"; evidence=[ordered]@{ lostToBudget=$h.displayCurrent } })
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

# ---- row-level breakdown rules (per-category, config-driven; see Get-BreakdownFindings) ----
foreach($w in $dataWidgets){ foreach($fnd in (Get-BreakdownFindings $w)){ [void]$anoms.Add($fnd) } }

# ---- breakdown tables into facts (force-include finding-referenced rows) ----
$plLabels=@{}
foreach($fnd in $anoms){ if($fnd.platform -and $fnd.statement){ foreach($mm in [regex]::Matches([string]$fnd.statement,"'([^']+)'")){ $lbl=$mm.Groups[1].Value; if(-not $plLabels.ContainsKey($fnd.platform)){ $plLabels[$fnd.platform]=@() }; if($plLabels[$fnd.platform] -notcontains $lbl){ $plLabels[$fnd.platform]+=$lbl } } } }
foreach($w in $dataWidgets){
  if(@($w.dimensions).Count -eq 0){ continue }
  $wprov = if($w.providers -and $w.providers.Count -gt 0){ $w.providers[0].id } else { (@($w.metrics)[0].id -split ':')[0] }
  if(-not $platforms.ContainsKey($wprov)){ continue }
  $bd = Get-Breakdown $w 20 $plLabels[$platforms[$wprov].name]
  if($bd){ if(-not $platforms[$wprov].Contains('breakdowns')){ $platforms[$wprov]['breakdowns']=[System.Collections.ArrayList]@() }; [void]$platforms[$wprov]['breakdowns'].Add($bd) }
  $ts = Get-TimeSeries $w
  if($ts){ if(-not $platforms[$wprov].Contains('timeSeries')){ $platforms[$wprov]['timeSeries']=[System.Collections.ArrayList]@() }; [void]$platforms[$wprov]['timeSeries'].Add($ts) }
}

# stable unique fid per finding (ruleId#ordinal) so the report can echo it and the closer can verify surfacing
$fidCounts=@{}
foreach($arr in @($wins,$losses,$anoms,$disc,$gaps)){ foreach($fnd in $arr){ $rid=if($fnd.ruleId){$fnd.ruleId}else{'F'}; if(-not $fidCounts.ContainsKey($rid)){ $fidCounts[$rid]=0 }; $fidCounts[$rid]++; $fnd.fid="$rid#$($fidCounts[$rid])" } }

$findings.wins=@($wins); $findings.losses=@($losses); $findings.anomalies=@($anoms); $findings.discrepancies=@($disc); $findings.dataGaps=@($gaps)

# seasonality caveat: adjacent-period comparisons (QoQ/MoM/WoW) can reflect seasonality, not performance.
# Can't detect from one period, so flag the possibility deterministically (spec 13.3).
$hasCmp=[bool](@($platforms.Values|Where-Object{$_.hasComparison}).Count)
$caveats=@()
if($hasCmp -and ($doc.report.dateRange.primary.measure -in 'quarter','month','week')){
  $caveats += "Comparison is $($periods.label), an adjacent $($doc.report.dateRange.primary.measure)-over-$($doc.report.dateRange.primary.measure). Adjacent-period comparisons can reflect seasonality (e.g. Q1 tax season, Q4 holidays), not just performance - validate against the same period a year earlier before attributing changes to the campaigns."
}
$facts=[ordered]@{
  meta=[ordered]@{
    tool='Analyze-SwydoReport.ps1'; factsVersion=1; computedFrom=$doc.meta.tool
    reportName=$doc.report.name; extractedAt=$doc.meta.extractedAt
    currentPeriod=$periods.current; previousPeriod=$periods.previous; periodLabel=$periods.label; periodConfidence=$periods.confidence
    hasComparison=$hasCmp; comparisonCaveats=$caveats;
    providers=@($platforms.Values | ForEach-Object { [ordered]@{ id=$_.id; name=$_.name; category=$_.category } })
    dataWidgets=$dataWidgets.Count; unitBasis=$doc.meta.unitBasis
  }
  platforms=@($platforms.Values)
  findings=$findings
}
$json = $facts | ConvertTo-Json -Depth 40 -Compress   # machine-consumed (report model + closer); compress to cut context load
Assert-NoCredential $json
$stamp=(Get-Date).ToString('yyyy-MM-dd-HH-mm-ss')
$slug=($doc.report.name -replace '[^A-Za-z0-9]+','-').Trim('-').ToLower(); if(-not $slug){$slug='report'}
$path=Join-Path $OutDir "$stamp-$slug.facts.json"
[IO.File]::WriteAllText($path,$json,(New-Object Text.UTF8Encoding($false)))
Write-Host ("facts -> {0}  (platforms {1}, wins {2}, losses {3}, disc {4}, gaps {5}; period {6}/{7})" -f $path,$facts.platforms.Count,$wins.Count,$losses.Count,$disc.Count,$gaps.Count,$periods.label,$periods.confidence)
