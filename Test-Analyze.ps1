<#
.SYNOPSIS
  Offline unit tests for Analyze-SwydoReport.ps1's pure helpers (unit/direction/additive/
  money/format/delta/period/scrub). Dot-sources via -DefineOnly (no I/O). Run: .\Test-Analyze.ps1
#>
$ErrorActionPreference="Stop"
. "$PSScriptRoot\Analyze-SwydoReport.ps1" -DefineOnly
$pass=0;$fail=0
function A($c,$m){ if($c){$script:pass++}else{$script:fail++;Write-Host "  FAIL: $m" -ForegroundColor Red} }

Write-Host "== Get-Category =="
$cat=@{ 'google-adwords'='ads';'facebook-ads'='ads';'google-analytics-4'='web-analytics';'semrush'='seo';'mailchimp'='email-crm';'shopify'='ecommerce';'callrail'='calls';'weirdnew'='other' }
foreach($k in $cat.Keys){ A ((Get-Category $k) -eq $cat[$k]) "Get-Category $k=>$(Get-Category $k) exp $($cat[$k])" }

Write-Host "== Get-Direction =="
$dir=@{
 'google-adwords:cost_micros'='lower-better';'google-adwords:average_cpc'='lower-better';'google-adwords:cost_per_conversion'='lower-better'
 'facebook-ads:costPerActionType::link_click'='lower-better';'seo:average_position'='lower-better';'x:position'='lower-better';'x:keyword_ranking'='lower-better'
 'ga4:bounce_rate'='lower-better';'email:unsubscribe_rate'='lower-better';'x:search_lost_is_budget'='lower-better'
 'google-adwords:conversions'='higher-better';'google-adwords:ctr'='higher-better';'facebook-ads:ctrLink'='higher-better';'facebook-ads:actions::link_click'='higher-better'
 'google-adwords:impressions'='higher-better';'google-adwords:impression_share'='higher-better';'x:roas'='higher-better';'ga4:sessions'='higher-better';'email:open_rate'='higher-better'
 'google-adwords:conversion_rate'='higher-better';'google-adwords:quality_info_quality_score'='higher-better';'ga4:engagement_rate'='higher-better'
 'google-adwords:cost'='lower-better';'facebook-ads:spend'='neutral';'x:amount_spent'='neutral';'x:budget'='neutral';'x:some_unknown_metric'='neutral'
}
foreach($k in $dir.Keys){ A ((Get-Direction $k) -eq $dir[$k]) "Get-Direction $k=>$(Get-Direction $k) exp $($dir[$k])" }

Write-Host "== Test-Additive =="
$add=@{ 'x:impressions'=$true;'x:clicks'=$true;'facebook-ads:actions::link_click'=$true;'google-adwords:cost_micros'=$true;'x:conversions'=$true;'x:sessions'=$true;'x:orders'=$true;'x:conversions_value_micros'=$true
        'x:reach'=$false;'x:frequency'=$false;'x:ctr'=$false;'x:average_cpc'=$false;'x:cost_per_conversion'=$false;'x:impression_share'=$false;'x:quality_score'=$false;'x:average_position'=$false;'x:roas'=$false }
foreach($k in $add.Keys){ A ((Test-Additive $k) -eq $add[$k]) "Test-Additive $k=>$(Test-Additive $k) exp $($add[$k])" }

Write-Host "== Format-Metric =="
A ((Format-Metric 'google-adwords:cost_micros' 'micros' 10864723050 'USD') -eq '$10,864.72') "cost micros USD"
A ((Format-Metric 'ga4:engagement_time_micros' 'micros' 5000000 $null) -eq '5.00') "non-money micros => seconds not currency"
A ((Format-Metric 'x:ctr' 'fraction' 0.163973 $null) -eq '16.4%') "fraction => %"
A ((Format-Metric 'x:clicks' $null 15627 $null) -eq '15,627') "count integer"
A ((Format-Metric 'x:conversions' $null 860.879162 $null) -eq '860.9') "count fractional"
A ((Format-Metric 'x:spend' 'micros' 7075800000 'EUR') -eq "$([char]0x20AC)7,075.80") "EUR symbol"
A ((Format-Metric 'x:spend' 'micros' 1000000 'SEK') -eq 'SEK 1.00') "unknown currency => code prefix"

Write-Host "== Get-DeltaPct =="
A ((Get-DeltaPct 15627 8719) -eq 79.2) "delta normal"
A ($null -eq (Get-DeltaPct 100 0)) "prev 0, cur !=0 => null (NEW)"
A ((Get-DeltaPct 0 0) -eq 0.0) "0 vs 0 => 0"
A ($null -eq (Get-DeltaPct 5 $null)) "null compare => null"
A ((Format-Delta 79.2) -eq '+79.2%') "delta display +"
A ((Format-Delta -8.1) -eq '-8.1%') "delta display -"

Write-Host "== Derive-Periods =="
$dr=[pscustomobject]@{ primary=[pscustomobject]@{count=-1;measure='quarter';type='RELATIVE'} }
$p=Derive-Periods '2026-07-06T02:23:57+03:00' $dr
A ($p.current -eq 'Q2 2026' -and $p.previous -eq 'Q1 2026') "quarter derivation => Q2 2026 vs Q1 2026 (got $($p.current)/$($p.previous))"
A ($p.confidence -eq 'derived') "period confidence derived"
$p2=Derive-Periods '2026-02-15T00:00:00+00:00' $dr   # extracted in Q1 -> last complete = Q4 2025
A ($p2.current -eq 'Q4 2025' -and $p2.previous -eq 'Q3 2025') "cross-year quarter (got $($p2.current)/$($p2.previous))"

Write-Host "== Scrub / Assert-NoCredential =="
$doc=[pscustomobject]@{ meta=[pscustomobject]@{ shareKey='ofDCabc'; shareUrl='https://swy.do/shares/ofDCabc'; extractedAt='2026' } }
$doc=Scrub-Credential $doc
A (-not ($doc.meta.PSObject.Properties.Name -contains 'shareKey')) "shareKey removed"
A (-not ($doc.meta.PSObject.Properties.Name -contains 'shareUrl')) "shareUrl removed"
$threw=$false; try{ Assert-NoCredential 'blah https://swy.do/shares/ofDCQ6RBcXQ leak' }catch{ $threw=$true }; A $threw "Assert-NoCredential throws on leak"
$threw=$false; try{ Assert-NoCredential 'clean report, no secrets' }catch{ $threw=$true }; A (-not $threw) "Assert-NoCredential passes clean"

Write-Host "== Get-DimLabel =="
A ((Get-DimLabel ([pscustomobject]@{campaign_id='1';campaign_name='Auto Loans'})) -eq 'Auto Loans') "dim label from name"
A ((Get-DimLabel 'MOBILE') -eq 'MOBILE') "dim label string passthrough"
A (Test-GroupRow (Get-DimLabel ([pscustomobject]@{count=3}))) "id-only object => (group)"

Write-Host "== Find-Metric / Row helpers =="
$w=[pscustomobject]@{ metrics=@([pscustomobject]@{name='Impr';id='google-adwords:impressions'},[pscustomobject]@{name='Cost';id='google-adwords:cost_micros'},[pscustomobject]@{name='Conv';id='google-adwords:conversions'}) }
A ((Find-Metric $w '(cost_micros|(^|_)cost$|spend)').name -eq 'Cost') "Find-Metric cost pattern"
A ((Find-Metric $w '(conversion|lead)').name -eq 'Conv') "Find-Metric conversion pattern"
A ((Find-Metric $w 'impression').name -eq 'Impr') "Find-Metric impression pattern"
A ($null -eq (Find-Metric $w 'nonexistent')) "Find-Metric miss => null"
$row=[pscustomobject]@{ dimensions=[pscustomobject]@{ Campaign='HELOC' }; metrics=[pscustomobject]@{ Cost=[pscustomobject]@{current=1312576559;compare=$null}; Conv=[pscustomobject]@{current=34.3;compare=0} } }
A ((Row-Cur $row 'Cost') -eq 1312576559) "Row-Cur scalar"
A ($null -eq (Row-Cur $row 'Missing')) "Row-Cur missing => null"
A ((Row-Cmp $row 'Conv') -eq 0) "Row-Cmp reads compare"
A ((Row-Label $row) -eq 'HELOC') "Row-Label first dimension"

Write-Host "== Get-BreakdownFindings (per-category synthetic fixtures) =="
function Met($n,$id){ [pscustomobject]@{name=$n;id=$id;unit=$null} }
function Rw($kind,$label,$dimName,$mv){ $dm=[ordered]@{}; $dm[$dimName]=$label; $mm=[ordered]@{}; foreach($k in $mv.Keys){ $mm[$k]=[pscustomobject]@{current=$mv[$k][0];compare=$mv[$k][1]} }; [pscustomobject]@{ kind=$kind; dimensions=[pscustomobject]$dm; metrics=[pscustomobject]$mm } }
function Wgt($prov,$pname,$dim,$mets,$rows){ [pscustomobject]@{ providers=@([pscustomobject]@{id=$prov;name=$pname}); currencyCode='USD'; dimensions=@($dim); metrics=$mets; rows=$rows } }
function HasRule($fs,$id){ [bool](@($fs | Where-Object { $_.ruleId -eq $id }).Count) }
function RuleSev($fs,$id){ (@($fs | Where-Object { $_.ruleId -eq $id })[0]).severity }

# SEO (semrush): impressions->clicks; a keyword with impressions but 0 clicks
$seo = Wgt 'semrush' 'SEMrush' 'Keyword' @((Met 'Impr' 'semrush:impressions'),(Met 'Clicks' 'semrush:clicks')) @(
  (Rw 'total' $null 'Keyword' @{Impr=@(1000,$null);Clicks=@(50,$null)}),
  (Rw 'data' 'dead-kw' 'Keyword' @{Impr=@(900,$null);Clicks=@(0,$null)}),
  (Rw 'data' 'ok-kw' 'Keyword' @{Impr=@(100,$null);Clicks=@(50,$null)}))
$f=Get-BreakdownFindings $seo
A (HasRule $f 'ANOM_EFFORT_NO_RESULT') "SEO impr->clicks: effort-no-result fires (non-ad config generalizes)"

# email (mailchimp): sends->opens; a campaign sent with 0 opens
$eml = Wgt 'mailchimp' 'Mailchimp' 'Campaign' @((Met 'Sends' 'mailchimp:sends'),(Met 'Opens' 'mailchimp:opens')) @(
  (Rw 'total' $null 'Campaign' @{Sends=@(1000,$null);Opens=@(200,$null)}),
  (Rw 'data' 'blast-x' 'Campaign' @{Sends=@(500,$null);Opens=@(0,$null)}),
  (Rw 'data' 'newsletter' 'Campaign' @{Sends=@(500,$null);Opens=@(200,$null)}))
$f=Get-BreakdownFindings $eml
A (HasRule $f 'ANOM_EFFORT_NO_RESULT') "email sends->opens: effort-no-result fires"

# ecommerce (shopify): sessions->orders
$ecom = Wgt 'shopify' 'Shopify' 'Channel' @((Met 'Sessions' 'shopify:sessions'),(Met 'Orders' 'shopify:orders')) @(
  (Rw 'total' $null 'Channel' @{Sessions=@(1000,$null);Orders=@(30,$null)}),
  (Rw 'data' 'referral-dead' 'Channel' @{Sessions=@(400,$null);Orders=@(0,$null)}),
  (Rw 'data' 'organic' 'Channel' @{Sessions=@(600,$null);Orders=@(30,$null)}))
$f=Get-BreakdownFindings $ecom
A (HasRule $f 'ANOM_EFFORT_NO_RESULT') "ecommerce sessions->orders: effort-no-result fires"

# ads share-mismatch: high impression share, low conversion share (+ awareness hint downgrade)
$adsSM = Wgt 'google-adwords' 'Google Ads' 'Campaign' @((Met 'Impr' 'google-adwords:impressions'),(Met 'Conv' 'google-adwords:conversions')) @(
  (Rw 'total' $null 'Campaign' @{Impr=@(1000,$null);Conv=@(100,$null)}),
  (Rw 'data' 'DisplayPush' 'Campaign' @{Impr=@(400,$null);Conv=@(2,$null)}),
  (Rw 'data' 'Search' 'Campaign' @{Impr=@(600,$null);Conv=@(98,$null)}))
$f=Get-BreakdownFindings $adsSM
A (HasRule $f 'ANOM_SHARE_MISMATCH' -and (RuleSev $f 'ANOM_SHARE_MISMATCH') -eq 'major') "ads share-mismatch fires (major)"
$adsAware = Wgt 'google-adwords' 'Google Ads' 'Campaign' @((Met 'Impr' 'google-adwords:impressions'),(Met 'Conv' 'google-adwords:conversions')) @(
  (Rw 'total' $null 'Campaign' @{Impr=@(1000,$null);Conv=@(100,$null)}),
  (Rw 'data' 'Brand Awareness' 'Campaign' @{Impr=@(400,$null);Conv=@(2,$null)}),
  (Rw 'data' 'Search' 'Campaign' @{Impr=@(600,$null);Conv=@(98,$null)}))
A ((RuleSev (Get-BreakdownFindings $adsAware) 'ANOM_SHARE_MISMATCH') -eq 'info') "awareness-named row downgrades share-mismatch to info"

# concentration
$conc = Wgt 'google-adwords' 'Google Ads' 'Device' @((Met 'Conv' 'google-adwords:conversions')) @(
  (Rw 'total' $null 'Device' @{Conv=@(100,$null)}),
  (Rw 'data' 'MOBILE' 'Device' @{Conv=@(70,$null)}),
  (Rw 'data' 'DESKTOP' 'Device' @{Conv=@(30,$null)}))
A (HasRule (Get-BreakdownFindings $conc) 'ANOM_CONCENTRATION') "concentration fires (MOBILE 70%)"

# PAUSED (previously unexercised): result nonzero prior, 0 now
$paused = Wgt 'google-adwords' 'Google Ads' 'Campaign' @((Met 'Conv' 'google-adwords:conversions')) @(
  (Rw 'total' $null 'Campaign' @{Conv=@(100,110)}),
  (Rw 'data' 'DeadCampaign' 'Campaign' @{Conv=@(0,50)}),
  (Rw 'data' 'Live' 'Campaign' @{Conv=@(100,60)}))
A (HasRule (Get-BreakdownFindings $paused) 'ANOM_PAUSED') "paused fires (0 now, was 50)"

# segment-divergence: a bucket moving opposite the total
$segd = Wgt 'google-adwords' 'Google Ads' 'Device' @((Met 'Conv' 'google-adwords:conversions')) @(
  (Rw 'total' $null 'Device' @{Conv=@(120,130)}),
  (Rw 'data' 'MOBILE' 'Device' @{Conv=@(40,100)}),
  (Rw 'data' 'DESKTOP' 'Device' @{Conv=@(80,30)}))
A (HasRule (Get-BreakdownFindings $segd) 'ANOM_SEGMENT_DIVERGENCE') "segment-divergence fires (DESKTOP up while MOBILE down)"

# no false-fire: healthy widget with no anomalies
$ok = Wgt 'google-adwords' 'Google Ads' 'Campaign' @((Met 'Conv' 'google-adwords:conversions'),(Met 'Cost' 'google-adwords:cost_micros')) @(
  (Rw 'total' $null 'Campaign' @{Conv=@(100,90);Cost=@(1000000000,900000000)}),
  (Rw 'data' 'A' 'Campaign' @{Conv=@(34,30);Cost=@(340000000,300000000)}),
  (Rw 'data' 'B' 'Campaign' @{Conv=@(33,30);Cost=@(330000000,300000000)}),
  (Rw 'data' 'C' 'Campaign' @{Conv=@(33,30);Cost=@(330000000,300000000)}))
$f=Get-BreakdownFindings $ok
A (-not (HasRule $f 'ANOM_EFFORT_NO_RESULT') -and -not (HasRule $f 'ANOM_CONCENTRATION') -and -not (HasRule $f 'ANOM_PAUSED')) "healthy balanced widget: no false anomalies (got $(@($f).Count))"

Write-Host ""
Write-Host ("RESULT: {0} passed, {1} failed" -f $pass,$fail) -ForegroundColor $(if($fail){'Red'}else{'Green'})
if($fail){ exit 1 }
