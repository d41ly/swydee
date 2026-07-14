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
  [double]$BrandSharePct = 25.0,# U10/D11: rule (b) dominance gate - matched brand set must be >= this % of outcome total
  [string[]]$NotesFile,         # optional plain-text context/notes file(s) ingested as annotations (client-supplied)
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
# U7a/R14: smallest represented step for a metric VALUE. MUST mirror Format-Metric's format specifiers AND its
# runtime integer-vs-fractional branch (kept adjacent so drift is caught by test U7a-T0). Value-aware: a
# fractional count/ratio (conversions 12.7, ROAS 4.2) steps by 0.1, an integer count by 1.0.
function Get-MetricUlp($id,$unit,$currency,$value){
  if($unit -eq 'micros'){ return 0.01 }               # N2
  if($unit -eq 'fraction'){ return 0.001 }             # {value*100:N1}% => 0.1% == 0.001 fraction
  # NB: money is N2 (0.01) ONLY when unit=='micros' (handled above). A money-id with a NULL/other unit is
  # rendered by Format-Metric as a COUNT (N0/N1), so it MUST fall through to the value-aware branch - do NOT
  # return 0.01 on the money id-pattern alone, or #4/#5 tolerance collapses and false-fires on rounding (R14).
  if($null -ne $value -and ([math]::Abs([double]$value - [math]::Round([double]$value)) -lt 1e-9)){ return 1.0 }
  return 0.1                                            # fractional count / ratio-typed (unit null)
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
# U10/D3: does this metric id measure downstream value (conversion value / revenue / ROAS)?
# target-guard FIRST (a target_roas/target_cpa is a bid SETTING, not measured value - it must NOT suppress).
function Test-ValueMetricId($id){
  $p = Get-MetricPart $id
  if($p -match '(?i)(^|_)target'){ return $false }
  return [bool]($p -match 'conversions?_value|conversion_value|action_?values?|value_per_|(^|_)value$|revenue|roas|return_on_ad_spend')
}
# U10/D2: does this widget expose a cross-row cost-efficiency ranking surface?
function Test-RankableCostWidget($w){
  $wdims=@($w.dimensions | Where-Object {$_}); if($wdims.Count -eq 0){ return $false }
  if($wdims[0] -match '(?i)day|week|month|date'){ return $false }
  $detail=@($w.rows | Where-Object { $_.kind -eq 'data' -and -not (Test-GroupRow (Row-Label $_)) })
  if($detail.Count -lt 2){ return $false }
  if(Find-Metric $w 'cost_per_conversion|cost_per.*lead|costperactiontype::lead|(^|_)cpa$|(^|_)cpl$'){ return $true }
  $costM=Find-Metric $w 'cost_micros|(^|_)cost$|spend|amount_spent'
  $outM =Find-Metric $w '(^|:)conversions?$|(^|_)lead|actions::lead'
  return [bool]($costM -and $outM)
}
# U10/D6: deterministic brand-token derivation from the Swydo client entity name (meta.client).
# phrase (>=2 tokens, parentheticals stripped) may FIRE via Test-BrandLabel; abbr/lead ANNOTATE only.
function Get-BrandTokens($clientName){
  $out=[ordered]@{ phrase=$null; abbr=@(); lead=$null }
  $s=[string]$clientName; if([string]::IsNullOrWhiteSpace($s)){ return $out }
  foreach($m in [regex]::Matches($s,'\(([^)]+)\)')){
    foreach($t in ($m.Groups[1].Value -split '[^A-Za-z]+')){ if($t.Length -ge 3){ $out.abbr+=$t.ToLower() } }
  }
  $core=(($s -replace '\([^)]*\)',' ') -replace '\s+',' ').Trim()
  $toks=@($core -split '[^A-Za-z0-9]+' | Where-Object { $_ })
  if($toks.Count -ge 2){ $out.phrase=(($toks -join ' ').ToLower()) }
  if($toks.Count -gt 0 -and $toks[0].Length -ge 4){ $out.lead=$toks[0].ToLower() }
  return $out
}
function Test-PMaxLabel($label){
  return [bool](([string]$label) -match '(?i)((^|[^a-z])p[\s._-]?max([^a-z]|$))|performance[\s._-]*max')
}
# U10/D6-S2: self-declared "brand" (lookahead [\s_-]+new kills "Brand New"/"Brand-New"); S3: full client phrase
# (space-padded Contains so client "Metro Bank" does NOT match campaign "Metro Bankers Golf Promo").
function Test-BrandLabel($label,$tokens){
  $l=[string]$label
  if($l -match '(?i)\bbrand(ed)?\b(?![\s_-]+new\b)'){ return $true }
  if($tokens -and $tokens.phrase){
    $norm=((($l -replace '[^A-Za-z0-9]+',' ') -replace '\s+',' ').Trim().ToLower())
    if((' '+$norm+' ').Contains(' '+$tokens.phrase+' ')){ return $true }
  }
  return $false
}
function Get-MatchedBrandToken($label,$tokens){
  if(-not $tokens){ return $null }
  $norm=' ' + ((([string]$label -replace '[^A-Za-z0-9]+',' ') -replace '\s+',' ').Trim().ToLower()) + ' '
  foreach($t in @($tokens.abbr)){ if($t -and $norm.Contains(" $t ")){ return $t } }
  if($tokens.lead -and $norm.Contains(" $($tokens.lead) ")){ return $tokens.lead }
  return $null
}
# U6: the provider a widget's headline is attributed to (declared provider, else first-metric id-prefix).
# One source of truth for discovery, headline population, and the GAP_NO_ACCOUNT_TOTAL pass so they can't drift.
function Get-WidgetProvider($w){
  if($w.providers -and @($w.providers).Count -gt 0){ return $w.providers[0].id }
  $m0=@($w.metrics); if($m0.Count -gt 0){ return ($m0[0].id -split ':')[0] }
  return $null
}
# U6/D6: a blended (multi-provider) widget is never a headline source.
function Test-Blended($w){ return [bool]($w.providers -and @($w.providers).Count -gt 1) }
function Row-Cur($row,$name){ $c=$row.metrics.$name; if($c -and ($c.current -is [double] -or $c.current -is [int] -or $c.current -is [long] -or $c.current -is [decimal])){ return [double]$c.current } return $null }
function Row-Cmp($row,$name){ $c=$row.metrics.$name; if($c -and ($c.compare -is [double] -or $c.compare -is [int] -or $c.compare -is [long] -or $c.compare -is [decimal])){ return [double]$c.compare } return $null }
function Row-Label($row){ $ps=@($row.dimensions.PSObject.Properties); if($ps.Count -gt 0){ return $ps[0].Value } return $null }
function Total-Row($w){
  $t=@($w.rows | Where-Object { $_.kind -eq 'total' }); if($t.Count -gt 0){ return $t[0] }
  # U6/A1 KPI-only fallback: the first data row IS the account total ONLY when the widget carries no
  # dimensions. A dimensioned table with no total row has NO account total here (never promote a slice).
  # @($w.dimensions | Where-Object {$_}) avoids the @($null).Count==1 trap on a null/scalar dimensions prop.
  if(@($w.dimensions | Where-Object {$_}).Count -eq 0){
    $t=@($w.rows | Where-Object { $_.kind -eq 'data' }); if($t.Count -gt 0){ return $t[0] }
  }
  return $null
}
# Row-level breakdown findings for ONE widget (concentration, new/paused, segment-divergence,
# effort->result, share-mismatch). Pure over the widget + $script:RuleCfg; returns a findings array.
function Get-BreakdownFindings($w,$clientName){
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
  # U10 rule (b): brand-demand-harvest suspects dominating the outcome total (data_gaps.md Tier 1.2).
  if($wcat -eq 'ads' -and $dimName -match '(?i)campaign'){
    # robust display name (@()-wrap so a JSON-collapsed single-provider scalar still yields the name, not the id -
    # keeps this finding's platform == the discovered $platforms[..].name so the $plLabels force-include matches).
    $bpname = if(@($w.providers).Count -gt 0 -and @($w.providers)[0].name){ [string](@($w.providers)[0].name) } else { $pname }
    $btok=Get-BrandTokens $clientName
    $om=Find-Metric $w '(^|:)conversions?$'; if(-not $om){ $om=Find-Metric $w '(^|_)lead|actions::lead' }
    if($om){
      $btot=Row-Cur $tr $om.name
      if($btot -and $btot -gt 0){
        $bm=[System.Collections.ArrayList]@(); $bsum=0.0; $btk=$null
        foreach($r in $detail){
          $lbl=[string](Row-Label $r)
          $sig=$null
          if(Test-PMaxLabel $lbl){ $sig='pmax' } elseif(Test-BrandLabel $lbl $btok){ $sig='brand-name' }
          if(-not $sig){ continue }
          $v=Row-Cur $r $om.name
          if($null -ne $v -and $v -gt 0){
            $bsum+=[double]$v; [void]$bm.Add($lbl)
            if(-not $btk){ $btk=Get-MatchedBrandToken $lbl $btok }
          }
        }
        if(@($bm).Count -gt 0 -and ($bsum/$btot) -ge ($BrandSharePct/100)){
          $bshare="$([math]::Round(($bsum/$btot)*100,0))%"
          $bLbls = if(@($bm).Count -gt 5){ @($bm[0..4]) + @("+$(@($bm).Count-5) more") } else { @($bm) }
          $bconf = if($bsum -lt $SmallN){ 'low' } else { 'normal' }
          $bev=[ordered]@{ campaigns=($bLbls -join '; '); share=$bshare
            matchedTotal=(Format-Metric $om.id $om.unit $bsum $cc); total=(Format-Metric $om.id $om.unit $btot $cc) }
          if($btk){ $bev.brandToken=$btk }
          [void]$out.Add([ordered]@{ ruleId='ANOM_BRAND_BASELINE'; severity='info'; platform=$bpname; widget=$dimName; confidence=$bconf
            statement="${bpname}: brand-demand-suspect campaigns ($(($bLbls | ForEach-Object { "'$_'" }) -join ', ')) account for $bshare of $($om.name) ($(Format-Metric $om.id $om.unit $bsum $cc) of $(Format-Metric $om.id $om.unit $btot $cc)) - Performance Max / brand-named campaigns harvest existing brand demand, so treat this share as baseline-suspect context, not proof of driven demand"
            evidence=$bev })
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
# U8/D-period read-through: facts.meta.period, consumed by U7b #6 (cross-widget-reconciliation-spec
# R18 gate 1). A pure COPY of the extractor-persisted resolution -- NO date arithmetic here (resolve
# once, at extraction time, persist as data; the analyzer/model never derives months from a label).
# Null triple (startYm/endYm=$null, calendarAligned=$false) for legacy/unresolved/unrecognized input;
# U7b hard-degrades that to info RECON_TREND_COVERAGE, never major. The YYYY-MM guard uses [0-9] and an
# explicit month range (NOT \d, which admits Unicode digits + months 13-99) so hand-edited garbage
# (e.g. '2026-13', Arabic-Indic digits) cannot reach facts.meta.period. meta.period is ALWAYS present.
function Get-PeriodMeta($dateRange,$resolved){
  $meas='custom'
  if($dateRange -and $dateRange.primary -and $dateRange.primary.measure){ $meas=([string]$dateRange.primary.measure).ToLowerInvariant() }
  $out=[ordered]@{ measure=$meas; startYm=$null; endYm=$null; calendarAligned=$false }
  $rp=$null; if($resolved -and ($resolved.resolverVersion -eq 1)){ $rp=$resolved.primary }
  if($rp -and ([string]$rp.startYm -match '^[0-9]{4}-(0[1-9]|1[0-2])$') -and ([string]$rp.endYm -match '^[0-9]{4}-(0[1-9]|1[0-2])$')){
    $out.startYm=[string]$rp.startYm; $out.endYm=[string]$rp.endYm
    $out.calendarAligned=($rp.calendarAligned -eq $true)
  }
  return $out
}
# credential scrub: remove shareKey/shareUrl in place on a parsed doc
function Scrub-Credential($doc){
  if($doc.meta){ 'shareKey','shareUrl' | ForEach-Object { if($doc.meta.PSObject.Properties.Name -contains $_){ $doc.meta.PSObject.Properties.Remove($_) } } }
  return $doc
}
$script:KeyPattern = '(?i)swy\.do/shares/[A-Za-z0-9_-]+|/g/[A-Za-z0-9_-]+/reports/'
function Assert-NoCredential($text){ if($text -match $script:KeyPattern){ throw "CREDENTIAL LEAK: share key/url found in output" } }
# --platform (U2): a major dataGap forcing the report to disclose which platforms were excluded. $null if no
# filter or nothing excluded. Pure so it is unit-testable via -DefineOnly.
function Get-ProviderFilterFinding($providerFilter,$providerInventory){
  $pf=@(@($providerFilter) | Where-Object { $_ }); if($pf.Count -eq 0){ return $null }   # null/[]/[null] => no filter
  $excluded=@(@($providerInventory) | Where-Object { $_ -and ($_ -notin $pf) })
  if($excluded.Count -eq 0){ return $null }
  return [ordered]@{ ruleId='PROVIDER_FILTERED'; severity='major'; statement=("Report limited to platform(s) " + ($pf -join ', ') + "; excluded (not pulled): " + ($excluded -join ', ') + " - this is a partial view of the account.") }
}
# U3: is a TEXT widget a real client note (keep) vs a layout header like "Google Ads" (drop)? Pure.
# $knownNames = provider/section display names to reject as headers. Kept if it looks like commentary:
# a "note/context/change/..." lead, a colon, a year, or >=6 words.
function Test-IsAnnotation($text,$knownNames){
  $t = ([string]$text).Trim()
  if(-not $t){ return $false }
  $tl = $t.ToLower()
  foreach($n in @($knownNames)){ if($n -and ($tl -eq ([string]$n).ToLower())){ return $false } }   # exact header label
  $wc = @($t -split '\s+' | Where-Object { $_ }).Count
  if($wc -lt 3){ return $false }
  if($t -match '(?i)\b(note|notes|context|updated?|change[ds]?|launch\w*|paused?|added|removed|migrat\w*|switch\w*|refresh\w*|test\w*)\b'){ return $true }
  if($t.Contains(':')){ return $true }
  if($t -match '\b(19|20)\d\d\b'){ return $true }
  return ($wc -ge 6)
}
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

# ============================ U7a: cross-widget reconciliation helpers + checks ============================
# Summable = a count/total that legitimately adds across partition rows. Ratios/rates/averages/dedup/per-X
# are NOT summable. (R4; distinct from Test-Additive on purpose - the {users,value} divergence is intentional:
# Test-Additive treats a bare 'value' as additive for DISC/concentration, while Test-Summable requires an
# explicit *_value/revenue and rejects GA4 users; do NOT "unify" them without a green-count audit.)
function Test-Summable($id){
  $p = Get-MetricPart $id
  if($p -match 'per[_a-z]'){ return $false }                                                # screenPageViewsPerSession, value_per_conversion
  if($p -match 'reach|frequency|unique|users?$|ctr|_rate$|rate$|average|avg|position|rank|roas|aov|cpc|cpm|cpa|cpl|share|score|cost_per|costper|(^|_)ratio$'){ return $false }
  if($p -match 'impression|click|conversion|lead|spend|cost_micros|(^|_)cost$|session|order|send|open|revenue|(^|_)call|phone_call|amount_spent|conversions?_value|conversion_value|purchase|bounce'){ return $true }
  return $false
}
# R5: two figures share a basis iff identical unit AND identical currency (null-safe equality).
function Test-SameBasis($ua,$ca,$ub,$cb){ return (($ua -eq $ub) -and ($ca -eq $cb)) }
# R16: a known-disjoint (partition) dimension where each row is a distinct bucket, so detail sums are
# legitimately additive. Only these authorize the #4 major; overlap dims (action_type, ...) stay info.
function Test-PartitionDim($dim){
  if($null -eq $dim){ return $false }
  $d = ([string]$dim).ToLowerInvariant() -replace '[^a-z0-9]',''
  return [bool]($d -match 'campaign|adgroup|adset|keyword|searchterm|date|day|week|month|landingpage|pagepath|country|region|device|channel|sourcemedium')
}
# R20: ratio spec for #3. $null for a non-ratio id. Numerators are role-pinned (cost-only for cost ratios,
# value-only for roas/aov) so an ambiguous (money) regex can't mis-pair. numPat/denPat are metric-part regexes.
function Get-RatioSpec($id){
  $p = Get-MetricPart $id
  $cost = 'cost_micros|(^|_)cost$|spend|amount_spent'
  $val  = 'conversions?_value|conversion_value|revenue|(^|_)value$'
  # link-basis CTR (ctrLink, inline_link_click_ctr, ...) matched BEFORE plain ctr so it is not treated as an
  # all-CTR and mis-paired against total clicks (R20).
  if($p -match 'ctrlink|link.*ctr|ctr.*link'){         return [ordered]@{ kind='ctr-link'; numPat='link_click'; numRole='link'; denPat='impression'; scale=1; resultKind='percent' } }
  if($p -match '(^|_)ctr$'){                            return [ordered]@{ kind='ctr'; numPat='(^|_)clicks?$'; numRole='all'; denPat='impression'; scale=1; resultKind='percent' } }
  if($p -match 'average_cpm|(^|_)cpm$'){                return [ordered]@{ kind='cpm'; numPat=$cost; numRole='cost'; denPat='impression'; scale=1000; resultKind='currency' } }
  if($p -match 'average_cpc|(^|_)cpc$'){                return [ordered]@{ kind='cpc'; numPat=$cost; numRole='cost'; denPat='(^|_)clicks?$'; scale=1; resultKind='currency' } }
  if($p -match 'cost_per.*lead|(^|_)cpl$'){            return [ordered]@{ kind='cpl'; numPat=$cost; numRole='cost'; denPat='(^|_)lead'; scale=1; resultKind='currency' } }
  # NB: costPerActionType::<action> is deliberately NOT reconciled here. Its denominator is the <action> count
  # (link_click, video_view, ...), NOT conversions; the spec table (R20 line 186) blanket-maps it to conversions,
  # but that recomputes an unrelated ratio and produced false findings (incl. a false DISC_RATIO_UNIT major when
  # link_clicks >> conversions). Only the unambiguous google cost_per_conversion / cpa is reconciled.
  if($p -match 'cost_per_conversion|(^|_)cpa$'){        return [ordered]@{ kind='cpa'; numPat=$cost; numRole='cost'; denPat='(^|:)conversions?$'; scale=1; resultKind='currency' } }
  if($p -match 'conversion_rate|conv_rate|(^|_)cvr$'){ return [ordered]@{ kind='cvr'; numPat='(^|:)conversions?$'; numRole='conv'; denPat='(^|_)clicks?$|session'; scale=1; resultKind='percent' } }
  if($p -match 'roas'){                                 return [ordered]@{ kind='roas'; numPat=$val; numRole='value'; denPat='cost_micros|(^|_)cost$|spend'; scale=1; resultKind='ratio' } }
  if($p -match 'aov|average_order_value'){             return [ordered]@{ kind='aov'; numPat=$val; numRole='value'; denPat='order'; scale=1; resultKind='currency' } }
  return $null
}
# Check #3: validate a natively-reported ratio against its total-row components as ratio-of-totals. Reported-unit
# gated (R13); component-disambiguated (R20); resultKind-driven display (R19). Major ONLY on a confirmed-unit
# ~1e6 signature (a genuine provider arithmetic error); same-basis mismatch is info.
function Get-RatioReconFindings($w,$periods){
  $out=[System.Collections.ArrayList]@()
  $tr = Total-Row $w; if(-not $tr){ return @() }   # no total row (incl. time-dimensioned native ratio) => skip
  $cc = $w.currencyCode
  $prov = Get-WidgetProvider $w
  $pname = if($w.providers -and @($w.providers).Count -gt 0 -and $w.providers[0].name){ $w.providers[0].name } else { $prov }
  foreach($rm in @($w.metrics)){
    $spec = Get-RatioSpec $rm.id; if(-not $spec){ continue }
    $rk = $spec.resultKind
    # R13 reported-unit gate: skip unless the reported ratio's OWN unit is confirmed & resultKind-consistent
    $unitOk = $false
    if($rk -eq 'percent'){ $unitOk = ($rm.unit -eq 'fraction') }
    elseif($rk -eq 'currency'){ $unitOk = ($rm.unit -eq 'micros') }
    elseif($rk -eq 'ratio'){ $unitOk = ($null -ne (Row-Cur $tr $rm.name)) }   # roas: numeric reported cell (unit null OK)
    if(-not $unitOk){ continue }
    # components via R20; ambiguity (multiple same-role candidates) => skip
    $numCands=@(@($w.metrics) | Where-Object { (Get-MetricPart $_.id) -match $spec.numPat })
    $denCands=@(@($w.metrics) | Where-Object { (Get-MetricPart $_.id) -match $spec.denPat })
    if($numCands.Count -ne 1 -or $denCands.Count -ne 1){ continue }
    $num=$numCands[0]; $den=$denCands[0]
    if($num.id -eq $rm.id -or $den.id -eq $rm.id -or $num.id -eq $den.id){ continue }
    # R20 role-qualifier agreement: an unqualified (all) ratio pairs only with an unqualified numerator; a link
    # ratio only with a link-qualified numerator. Stops an all-CTR mis-recomputing against link_clicks (or a
    # link-CTR against total clicks) when the correctly-qualified sibling metric is absent from the widget.
    $numIsLink = ((Get-MetricPart $num.id) -match 'link')
    if($spec.numRole -eq 'all' -and $numIsLink){ continue }
    if($spec.numRole -eq 'link' -and -not $numIsLink){ continue }
    # money/value components must have a CONFIRMED (non-null) unit before any unit-signature eval (R20)
    if($null -eq $num.unit -and ($num.id -match '(?i)cost|spend|revenue|value|amount_spent')){ continue }
    if((Test-Money $den.id $den.unit $cc) -and $null -eq $den.unit){ continue }
    $numv=Row-Cur $tr $num.name; $denv=Row-Cur $tr $den.name; $repv=Row-Cur $tr $rm.name
    if($null -eq $numv -or $null -eq $denv -or $null -eq $repv -or $denv -eq 0){ continue }
    $numBase = if($num.unit -eq 'micros'){ [double]$numv/1e6 } else { [double]$numv }
    $denBase = if($den.unit -eq 'micros'){ [double]$denv/1e6 } else { [double]$denv }
    if($denBase -eq 0){ continue }
    $recomputedBase = ($numBase/$denBase) * $spec.scale
    $reportedBase = if($rm.unit -eq 'micros'){ [double]$repv/1e6 } else { [double]$repv }
    if($recomputedBase -eq 0){ continue }
    $r = $reportedBase / $recomputedBase
    $dispReported = Format-Metric $rm.id $rm.unit $repv $cc
    $dispRecomputed = switch($rk){
      'currency' { Format-Money $recomputedBase $cc }
      'percent'  { Format-Metric $rm.id 'fraction' $recomputedBase $cc }
      default    { Format-Metric $rm.id $rm.unit $recomputedBase $cc }   # ratio -> same formatter as the reported cell (R3/R19; no hand-rolled numbers)
    }
    $dispNum = Format-Metric $num.id $num.unit $numv $cc
    $dispDen = Format-Metric $den.id $den.unit $denv $cc
    $unitSig = (($r -ge 1e5 -and $r -le 1e7) -or ((1/$r) -ge 1e5 -and (1/$r) -le 1e7))
    if($unitSig){
      [void]$out.Add([ordered]@{ ruleId='DISC_RATIO_UNIT'; severity='major'; platform=$pname; metric=$rm.name; widgetId=$w.id
        statement="$pname '$($rm.name)' reported $dispReported but the $($spec.kind) of the total-row components is $dispRecomputed (micros-not-divided: reported ratio ~1e6x its components)"
        evidence=[ordered]@{ reported=$dispReported; recomputed=$dispRecomputed; components="$dispNum / $dispDen" } })
    } else {
      $ulp=[math]::Max((Get-MetricUlp $rm.id $rm.unit $cc $reportedBase),(Get-MetricUlp $rm.id $rm.unit $cc $recomputedBase))
      if([math]::Abs($reportedBase-$recomputedBase) -gt (2*$ulp)){
        [void]$out.Add([ordered]@{ ruleId='DISC_RATIO_RECOMPUTE'; severity='info'; platform=$pname; metric=$rm.name; widgetId=$w.id
          statement="$pname '$($rm.name)' reported $dispReported but the $($spec.kind) of the total-row components is $dispRecomputed (provider ratio basis differs: filtered denominator or average-of-ratios)"
          evidence=[ordered]@{ reported=$dispReported; recomputed=$dispRecomputed; components="$dispNum / $dispDen" } })
      }
    }
  }
  return @($out)
}
# Check #4: within one dimensioned widget with an explicit total row, Sum(detail) ~= total. Over-sum on a
# partition dim (R16) is a major double-count; over-sum on an overlap/multi-dim is info; under-sum is an honest
# (other) remainder. Tolerance scales with row count (R15). Summable metrics only (R4).
function Get-DetailSumFindings($w,$periods){
  $out=[System.Collections.ArrayList]@()
  $dims=@($w.dimensions | Where-Object {$_}); if($dims.Count -eq 0){ return @() }
  $tr=Total-Row $w; if(-not $tr){ return @() }
  $cc=$w.currencyCode
  $prov=Get-WidgetProvider $w
  $pname=if($w.providers -and @($w.providers).Count -gt 0 -and $w.providers[0].name){ $w.providers[0].name } else { $prov }
  $detail=@($w.rows | Where-Object { $_.kind -eq 'data' -and -not (Test-GroupRow (Row-Label $_)) })
  if($detail.Count -eq 0){ return @() }
  $isPartition = (($dims.Count -eq 1) -and (Test-PartitionDim $dims[0]))
  foreach($m in @($w.metrics)){
    if(-not (Test-Summable $m.id)){ continue }
    $totalRaw=Row-Cur $tr $m.name; if($null -eq $totalRaw){ continue }
    $sumRaw=0.0; $k=0; $any=$false
    foreach($rr in $detail){ $v=Row-Cur $rr $m.name; if($null -ne $v){ $sumRaw += [double]$v; $k++; $any=$true } }
    if(-not $any){ continue }
    $totalBase = if($m.unit -eq 'micros'){ [double]$totalRaw/1e6 } else { [double]$totalRaw }
    $sumBase   = if($m.unit -eq 'micros'){ $sumRaw/1e6 } else { $sumRaw }
    $ulp=[math]::Max((Get-MetricUlp $m.id $m.unit $cc $sumBase),(Get-MetricUlp $m.id $m.unit $cc $totalBase))
    $tol=[math]::Max(2,$k) * $ulp
    $dispSum=Format-Metric $m.id $m.unit $sumRaw $cc
    $dispTotal=Format-Metric $m.id $m.unit $totalRaw $cc
    if(($sumBase - $totalBase) -gt $tol){
      if($isPartition){
        [void]$out.Add([ordered]@{ ruleId='DISC_DETAIL_EXCEEDS_TOTAL'; severity='major'; platform=$pname; metric=$m.name; widgetId=$w.id
          statement="$pname '$($m.name)' detail rows sum to $dispSum, exceeding the widget total $dispTotal on the '$($dims[0])' partition - possible duplicated/double-counted rows"
          evidence=[ordered]@{ shownSum=$dispSum; total=$dispTotal } })
      } else {
        [void]$out.Add([ordered]@{ ruleId='RECON_ROW_OVERSUM'; severity='info'; platform=$pname; metric=$m.name; widgetId=$w.id
          statement="$pname '$($m.name)' listed rows sum to $dispSum, above the widget total $dispTotal; the '$($dims[0])' dimension may double-count (overlapping/multi-attribution values)"
          evidence=[ordered]@{ shownSum=$dispSum; total=$dispTotal } })
      }
    }
    elseif(($totalBase - $sumBase) -gt $tol){
      $remainderRaw=[double]$totalRaw - $sumRaw
      if($remainderRaw -ge 0){
        $dispOther=Format-Metric $m.id $m.unit $remainderRaw $cc
        [void]$out.Add([ordered]@{ ruleId='RECON_ROW_REMAINDER'; severity='info'; platform=$pname; metric=$m.name; widgetId=$w.id
          statement="$pname '$($m.name)': listed rows sum to $dispSum of a $dispTotal total; $dispOther is in unshown rows (other)"
          evidence=[ordered]@{ total=$dispTotal; shownSum=$dispSum; other=$dispOther } })
      }
    }
  }
  return @($out)
}
# Check #5: a dimensioned slice total exceeding a MEASURED account KPI. Info only (R17): filtered KPI cards and
# per-widget date ranges make "subset exceeds whole" legitimately possible and undetectable from schema v2. The
# account KPI is found by scanning ALL non-blended zero-dim data widgets of the same provider (not the doc-order
# headline winner); ambiguous ceiling => skip. Summable metrics only (ratio/dedup slices can exceed the account).
function Get-SliceAccountFindings($w,$dataWidgets,$periods){
  $out=[System.Collections.ArrayList]@()
  $dims=@($w.dimensions | Where-Object {$_}); if($dims.Count -eq 0){ return @() }
  $tr=Total-Row $w; if(-not $tr){ return @() }
  $cc=$w.currencyCode
  $prov=Get-WidgetProvider $w
  $pname=if($w.providers -and @($w.providers).Count -gt 0 -and $w.providers[0].name){ $w.providers[0].name } else { $prov }
  foreach($m in @($w.metrics)){
    if(-not (Test-Summable $m.id)){ continue }
    $sliceRaw=Row-Cur $tr $m.name; if($null -eq $sliceRaw){ continue }
    $kpiCands=@()
    foreach($ow in @($dataWidgets)){
      if(Test-Blended $ow){ continue }
      if(@($ow.dimensions | Where-Object {$_}).Count -ne 0){ continue }   # zero-dim account KPI only
      if((Get-WidgetProvider $ow) -ne $prov){ continue }
      $otr=Total-Row $ow; if(-not $otr){ continue }
      $om=@(@($ow.metrics) | Where-Object { $_.id -eq $m.id }); if($om.Count -eq 0){ continue }
      $ov=Row-Cur $otr $om[0].name; if($null -eq $ov){ continue }
      $kpiCands += @{ unit=$om[0].unit; currency=$ow.currencyCode; value=[double]$ov }
    }
    if($kpiCands.Count -eq 0){ continue }
    $uniqVals=@($kpiCands | ForEach-Object { $_.value } | Sort-Object -Unique)
    if($uniqVals.Count -gt 1){ continue }   # ambiguous ceiling
    $kpi=$kpiCands[0]
    if(-not (Test-SameBasis $m.unit $cc $kpi.unit $kpi.currency)){ continue }
    $sliceBase = if($m.unit -eq 'micros'){ [double]$sliceRaw/1e6 } else { [double]$sliceRaw }
    $kpiBase   = if($kpi.unit -eq 'micros'){ $kpi.value/1e6 } else { $kpi.value }
    $ulp=[math]::Max((Get-MetricUlp $m.id $m.unit $cc $sliceBase),(Get-MetricUlp $m.id $kpi.unit $kpi.currency $kpiBase))
    if(($sliceBase - $kpiBase) -gt (2*$ulp)){
      $dispSlice=Format-Metric $m.id $m.unit $sliceRaw $cc
      $dispKpi=Format-Metric $m.id $kpi.unit $kpi.value $kpi.currency
      [void]$out.Add([ordered]@{ ruleId='RECON_SLICE_OVER_ACCOUNT'; severity='info'; platform=$pname; metric=$m.name; widgetId=$w.id
        statement="$pname '$($m.name)' slice total $dispSlice exceeds the measured account KPI $dispKpi (dimension '$($dims[0])')"
        evidence=[ordered]@{ slice=$dispSlice; account=$dispKpi; dimension=$dims[0]; note='slice exceeds measured account KPI; if the KPI card is filtered or the table spans a different period this is expected' } })
    }
  }
  return @($out)
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
$periodMeta = Get-PeriodMeta $doc.report.dateRange $doc.report.dateRangeResolved   # U8: D-period read-through
$dataWidgets = @($doc.widgets | Where-Object { $_.kind -eq 'data' })
if($dataWidgets.Count -eq 0){ throw "no data widgets to analyze (all text/empty)" }

# U3: collect client-supplied CONTEXT annotations (text widgets that are real notes, not layout headers)
# + optional -NotesFile. Verbatim, non-causal; each gets a stable aid the report anchors (<!-- annotation:aid -->)
# so the closer scopes its numbers to the quoting line only. Credential-in-note is caught by Assert-NoCredential.
$knownNames = @()
foreach($w in $doc.widgets){ if($w.providers){ foreach($pp in $w.providers){ if($pp.name){ $knownNames += [string]$pp.name } } } }
$knownNames += @(@($doc.report.sections) | ForEach-Object { [string]$_.name })
$knownNames = @($knownNames | Where-Object { $_ } | Sort-Object -Unique)
$annotations=@(); $annN=0
# redact any share-link pattern IN the note before it enters facts: a client pasting a live swy.do link
# into a note would otherwise trip the whole-doc Assert-NoCredential and abort every run (fail-closed but
# a pipeline-wedge). Redacting keeps it fail-closed AND lets the report proceed.
foreach($w in $doc.widgets){
  if($w.kind -ne 'text'){ continue }
  $atext = ([string]$w.text).Trim()
  if(Test-IsAnnotation $atext $knownNames){ $atext = ($atext -replace $script:KeyPattern,'[redacted-share-link]'); $annN++; $annotations += [ordered]@{ aid="ANN#$annN"; section=[string]$w.section; source='report'; text=$atext } }
}
foreach($nf in @($NotesFile)){ if($nf -and (Test-Path -LiteralPath $nf)){ $ntext=([IO.File]::ReadAllText($nf)).Trim(); if($ntext){ $ntext = ($ntext -replace $script:KeyPattern,'[redacted-share-link]'); $annN++; $annotations += [ordered]@{ aid="ANN#$annN"; section='(notes)'; source=(Split-Path $nf -Leaf); text=$ntext } } } }


# per-platform headline (role-qualified) + provider discovery.
# U6/A2: provider discovery still walks ALL data widgets (so a blended-only or no-total-only provider keeps
# its platform entry + surfaces GAP_NO_ACCOUNT_TOTAL); a blended widget (D6) and a dimensioned no-total table
# (A1 -> $tr=$null) never SUPPLY a headline value. Every legacy field is populated byte-for-byte as before
# (raw total-row cell, NOT Row-Cur's [double] cast); only the additive `canonical` provenance is new.
$platforms=@{}
$displaced=@{}   # U9/D2: per-provider list of rank displacements (a later zero-dim KPI supersedes a doc-earlier table total)
foreach($w in $dataWidgets){
  # discovery: register EVERY provider present on the widget (each side of a blended widget included), so a
  # provider that appears ONLY as a non-primary side of a blended widget still earns a platform entry (empty
  # headline) + GAP_NO_ACCOUNT_TOTAL rather than vanishing silently. Single-provider widgets are unaffected.
  foreach($pe in @($w.providers)){
    if($pe.id -and -not $platforms.ContainsKey($pe.id)){
      $pn = if($pe.name){ $pe.name } else { $pe.id }
      $platforms[$pe.id]=[ordered]@{ id=$pe.id; name=$pn; category=(Get-Category $pe.id); headline=[ordered]@{}; hasComparison=$false }
    }
  }
  $prov = Get-WidgetProvider $w
  if(-not $prov){ continue }
  if(-not $platforms.ContainsKey($prov)){   # metric-prefix-only widget (no providers[]) discovered here
    $pname = if($w.providers -and @($w.providers).Count -gt 0 -and $w.providers[0].name){ $w.providers[0].name } else { $prov }
    $platforms[$prov]=[ordered]@{ id=$prov; name=$pname; category=(Get-Category $prov); headline=[ordered]@{}; hasComparison=$false }
  }
  if(Test-Blended $w){ continue }             # D6: never a headline source (discovery above still counted it)
  $tr = Total-Row $w
  if(-not $tr){ continue }                     # A1: dimensioned no-total -> $null -> contributes no headline value
  $cc   = $w.currencyCode
  $dims = @($w.dimensions | Where-Object {$_})
  $isKpi= ($dims.Count -eq 0)
  $scope= if($isKpi){ 'account' } else { "table-total:$($dims[0])" }   # honest scope; never bare 'account' for a table total
  $src  = if($isKpi){ 'kpi-widget' } else { 'total-row' }
  foreach($m in $w.metrics){
    $cell = $tr.metrics.$($m.name)
    if(-not $cell){ continue }
    if(-not ($cell.current -is [double] -or $cell.current -is [int] -or $cell.current -is [long] -or $cell.current -is [decimal])){ continue }  # scalar-guard: drop echo objects
    $key = $m.id  # role-qualified store key by metric id (dedup across widgets keeps first/total)
    $existing = $null
    if($platforms[$prov].headline.Contains($key)){ $existing = $platforms[$prov].headline[$key] }
    if($null -ne $existing){
      # U9/D2: a TRUE zero-dim KPI (rank 1) supersedes a document-earlier table total (rank 2) for the same
      # metric id; same-rank candidates keep document-order first-wins (identical to pre-U9 for every other pair).
      # Null-check $existing.canonical so a metric id colliding with the boolean 'hasComparison' key (an ordered-
      # dict entry, case-insensitive) degrades to exact pre-U9 first-wins and never corrupts hasComparison / D7.
      if(-not ($isKpi -and $existing.canonical -and ($existing.canonical.source -ne 'kpi-widget'))){ continue }
      if(-not $displaced.ContainsKey($prov)){ $displaced[$prov]=[System.Collections.ArrayList]@() }
      [void]$displaced[$prov].Add([ordered]@{ metricId=$key; supersededWidgetId=$existing.canonical.sourceWidgetId })
    }
    $dir = Get-Direction $m.id
    $delta = Get-DeltaPct $cell.current $cell.compare
    $hasCmp = ($null -ne $cell.compare)
    if($hasCmp){ $platforms[$prov].headline.hasComparison=$true; $platforms[$prov].hasComparison=$true }
    $dispCur = (Format-Metric $m.id $m.unit $cell.current $cc)
    $platforms[$prov].headline[$key]=[ordered]@{
      metric=$m.name; id=$m.id; unit=$m.unit; type=(Metric-Type $m.id $m.unit $cc); direction=$dir; currency=$cc
      current=$cell.current; previous=$cell.compare; deltaPct=$delta; hasComparison=$hasCmp
      displayCurrent=$dispCur
      displayPrevious=(Format-Metric $m.id $m.unit $cell.compare $cc)
      displayDelta=(Format-Delta $delta)
      # ---- U6 provenance (additive; canonical.display IS displayCurrent so the closer needs no change) ----
      canonical=[ordered]@{ display=$dispCur; sourceWidgetId=$w.id; scope=$scope; period=$periods.current; source=$src }
    }
    # U9/D5: a displaced cell records the widget it superseded (last canonical key; absent on non-flipped cells).
    if($null -ne $existing){ $platforms[$prov].headline[$key].canonical.supersededWidgetId = $existing.canonical.sourceWidgetId }
  }
}
# U9/D7: platforms that had a displacement recompute comparison flags from the SURVIVING headline cells.
# Value-only: no key is added or removed. Non-flip reports never enter this branch (byte-identical).
foreach($dpk in @($displaced.Keys)){
  if(-not $platforms.ContainsKey($dpk)){ continue }
  $pfD=$platforms[$dpk]; $anyCmp=$false
  foreach($hk in @($pfD.headline.Keys)){
    if($hk -eq 'hasComparison'){ continue }
    if($pfD.headline[$hk].hasComparison){ $anyCmp=$true; break }
  }
  if($pfD.headline.Contains('hasComparison')){ $pfD.headline['hasComparison']=$anyCmp }
  $pfD.hasComparison=$anyCmp
}

# findings
$findings=[ordered]@{ wins=@(); losses=@(); anomalies=@(); discrepancies=@(); dataGaps=@() }
# NOTE: PowerShell variables are case-insensitive, so accumulators must NOT collide with loop vars ($w, etc.)
$wins=[System.Collections.ArrayList]@(); $losses=[System.Collections.ArrayList]@(); $anoms=[System.Collections.ArrayList]@(); $disc=[System.Collections.ArrayList]@(); $gaps=[System.Collections.ArrayList]@()

# GAP_WARNINGS (from extraction)
foreach($warn in @($doc.meta.warnings)){ if($warn){ [void]$gaps.Add([ordered]@{ ruleId='GAP_WARNINGS'; severity='major'; statement=$warn }) } }
# PROVIDER_FILTERED: --platform pulled a subset; force the exclusion into the report so a partial view is never
# mistaken for a complete one (the completeness gate covers only what was pulled).
$pff = Get-ProviderFilterFinding $doc.meta.providerFilter $doc.meta.providerInventory
if($pff){ [void]$gaps.Add($pff) }
# U6/A2.4: GAP_NO_ACCOUNT_TOTAL - one info finding per provider for metric ids that were OBSERVED (attributed
# by metric-id prefix, so a blended widget contributes each metric to its true owner) but got NO headline cell
# (all their widgets were dimensioned-no-total and/or blended). Info => never force-surfaced => never blocks.
$observed=@{}
foreach($w in $dataWidgets){
  foreach($m in @($w.metrics)){
    $mp=($m.id -split ':')[0]; if(-not $mp){ continue }
    if(-not $observed.ContainsKey($mp)){ $observed[$mp]=[System.Collections.Generic.HashSet[string]]::new() }
    [void]$observed[$mp].Add($m.id)
  }
}
foreach($prov in @($observed.Keys)){
  if(-not $platforms.ContainsKey($prov)){ continue }   # only discovered platforms
  $pf=$platforms[$prov]
  $missing=@($observed[$prov] | Where-Object { -not $pf.headline.Contains($_) } | Sort-Object)
  if($missing.Count -eq 0){ continue }
  $shown = if($missing.Count -gt 20){ (@($missing[0..19]) + @("+$($missing.Count-20) more")) } else { $missing }
  [void]$gaps.Add([ordered]@{
    ruleId='GAP_NO_ACCOUNT_TOTAL'; severity='info'; platform=$pf.name
    statement="no account-level total available for $($missing.Count) metric(s) of $($pf.name): only dimensioned rows with no total row (or blended widgets); metrics: $($shown -join ', ')"
    evidence=[ordered]@{ metrics=@($shown); count="$($missing.Count)" }
  })
}
# U9/D4: GAP_HEADLINE_SOURCE_CHANGED - one info finding per provider with >= 1 rank displacement (a later zero-dim
# KPI superseded a document-earlier table total). Provenance note, routed to $gaps (a sourcing note, NOT a numbers-
# disagree discrepancy). D11-style rollup: ids + count only, NO metric values echoed (the displaced total is
# deliberately not re-surfaced; RECON_SLICE_OVER_ACCOUNT carries values when its gates pass). Flip-only, info.
foreach($dpk in @($displaced.Keys)){
  $items=@($displaced[$dpk]); if($items.Count -eq 0){ continue }
  $dmet=@($items | ForEach-Object { $_.metricId } | Sort-Object -Unique)
  $dwid=@($items | ForEach-Object { $_.supersededWidgetId } | Where-Object { $_ } | Sort-Object -Unique)
  $dshown = if($dmet.Count -gt 20){ (@($dmet[0..19]) + @("+$($dmet.Count-20) more")) } else { $dmet }
  $pnameD = if($platforms.ContainsKey($dpk)){ $platforms[$dpk].name } else { $dpk }
  [void]$gaps.Add([ordered]@{
    ruleId='GAP_HEADLINE_SOURCE_CHANGED'; severity='info'; platform=$pnameD
    statement="headline for $($dmet.Count) metric(s) of ${pnameD} comes from the account KPI card rather than the document-earlier table total: $($dshown -join ', '); superseded widget(s): $($dwid -join ', ')"
    evidence=[ordered]@{ metrics=@($dshown); count="$($dmet.Count)"; supersededWidgets=@($dwid) }
  })
}
# U10 rule (a): cost-per-result rankings with no measured downstream value (data_gaps.md Tier 1.1).
# ONE finding per report, listing every affected ads platform. Value attribution is by metric-id
# prefix (blended widgets contribute value metrics to their true owner, like the $observed map).
$valueProv=@{}
foreach($w in $dataWidgets){
  foreach($m in @($w.metrics)){
    if(-not (Test-ValueMetricId $m.id)){ continue }
    $mp=($m.id -split ':')[0]; if(-not $mp -or $valueProv[$mp]){ continue }
    foreach($r in @($w.rows)){ $v=Row-Cur $r $m.name; if($null -ne $v -and $v -gt 0){ $valueProv[$mp]=$true; break } }
  }
}
$rankProv=@{}    # providerId -> $true when it carries >= 1 rankable non-blended ads widget
$explNames=@{}   # providerId -> ArrayList of EXPLICIT cost-per-outcome display names (never raw spend columns)
$pairOnly=@{}    # providerId -> $true when a rankable surface exists only via the cost+outcome PAIR
foreach($w in $dataWidgets){
  if(Test-Blended $w){ continue }
  $prov=Get-WidgetProvider $w; if(-not $prov){ continue }
  if((Get-Category $prov) -ne 'ads'){ continue }
  if(-not (Test-RankableCostWidget $w)){ continue }
  $rankProv[$prov]=$true
  $rmet=Find-Metric $w 'cost_per_conversion|cost_per.*lead|costperactiontype::lead|(^|_)cpa$|(^|_)cpl$'
  if($rmet){
    if(-not $explNames.ContainsKey($prov)){ $explNames[$prov]=[System.Collections.ArrayList]@() }
    if($explNames[$prov] -notcontains [string]$rmet.name){ [void]$explNames[$prov].Add([string]$rmet.name) }
  } else {
    $pairOnly[$prov]=$true
  }
}
$affected=@($rankProv.Keys | Where-Object { -not $valueProv[$_] } | Sort-Object)
if($affected.Count -gt 0){
  $affNames=@($affected | ForEach-Object { if($platforms.ContainsKey($_)){ $platforms[$_].name } else { $_ } })
  $rmNames=@(); $hasPair=$false
  foreach($p in $affected){
    if($explNames.ContainsKey($p)){ foreach($n in @($explNames[$p])){ if($rmNames -notcontains $n){ $rmNames+=$n } } }
    if($pairOnly[$p]){ $hasPair=$true }
  }
  $rmShown = if(@($rmNames).Count -gt 6){ (@($rmNames[0..5]) + @("+$(@($rmNames).Count-6) more")) } else { @($rmNames) }
  # parenthetical lists ONLY explicit cost-per-outcome names; pair-only surfaces get a generic digit-free phrase
  # (raw spend columns like 'Cost'/'Amount spent' are NEVER labelled as cost-per-result comparisons).
  $parts=@()
  if(@($rmShown).Count -gt 0){ $parts+=($rmShown -join ', ') }
  if($hasPair){ $parts+='tables pairing cost with conversions/leads' }
  $paren=($parts -join ' and ')
  [void]$gaps.Add([ordered]@{
    ruleId='GAP_COST_RANKING_NO_VALUE'; severity='major'; requiresDownstreamData=$true
    statement=("Cost-per-result comparisons (" + $paren + ") are reported for " + ($affNames -join ', ') + " with no positive conversion-value, revenue, or ROAS recorded; cost-based rankings order campaigns by acquisition cost alone - confirm downstream (funded/closed) value before treating a cheaper cost-per-result as better.")
    evidence=[ordered]@{ platforms=($affNames -join ', '); rankingMetrics=($rmShown -join ', ') }
  })
}
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

# ---- U7a cross-widget reconciliation (#3 ratio-recompute, #4 detail-vs-total, #5 slice-vs-account) ----
# Only a provably-impossible direction is major (DISC_RATIO_UNIT confirmed-unit ~1e6; DISC_DETAIL_EXCEEDS_TOTAL
# on a partition dim); every other relation is info. Disjoint from DISC_CROSS_WIDGET (identical dimSig only),
# so no pair double-fires. Blended widgets excluded (R6).
$u7discRules=@('DISC_RATIO_UNIT','DISC_RATIO_RECOMPUTE','DISC_DETAIL_EXCEEDS_TOTAL','RECON_SLICE_OVER_ACCOUNT')
foreach($w in $dataWidgets){
  if(Test-Blended $w){ continue }
  $u7f=@(); $u7f+=@(Get-RatioReconFindings $w $periods); $u7f+=@(Get-DetailSumFindings $w $periods); $u7f+=@(Get-SliceAccountFindings $w $dataWidgets $periods)
  foreach($f in $u7f){ if($f.ruleId -in $u7discRules){ [void]$disc.Add($f) } else { [void]$gaps.Add($f) } }
}

# ---- row-level breakdown rules (per-category, config-driven; see Get-BreakdownFindings) ----
foreach($w in $dataWidgets){ foreach($fnd in (Get-BreakdownFindings $w $doc.report.client)){ [void]$anoms.Add($fnd) } }

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
  # {id,text}: the id is a stable anchor the report echoes (<!-- caveat:seasonality -->) and the
  # closer greps, so the surfacing check is not a brittle keyword match on free text.
  $caveats += [ordered]@{ id='seasonality'; text="Comparison is $($periods.label), an adjacent $($doc.report.dateRange.primary.measure)-over-$($doc.report.dateRange.primary.measure). Adjacent-period comparisons can reflect seasonality (e.g. Q1 tax season, Q4 holidays), not just performance - validate against the same period a year earlier before attributing changes to the campaigns." }
}
$facts=[ordered]@{
  meta=[ordered]@{
    tool='Analyze-SwydoReport.ps1'; factsVersion=1; canonicalVersion=2; computedFrom=$doc.meta.tool
    reportName=$doc.report.name; clientId=$doc.meta.clientId; client=$doc.report.client; extractedAt=$doc.meta.extractedAt
    providerInventory=@($doc.meta.providerInventory); providerFilter=@($doc.meta.providerFilter); annotations=@($annotations)
    currentPeriod=$periods.current; previousPeriod=$periods.previous; periodLabel=$periods.label; periodConfidence=$periods.confidence; period=$periodMeta
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
