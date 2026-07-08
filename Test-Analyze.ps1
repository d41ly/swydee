<#
.SYNOPSIS
  Offline unit tests for Analyze-SwydoReport.ps1's pure helpers (unit/direction/additive/
  money/format/delta/period/scrub). Dot-sources via -DefineOnly (no I/O). Run: .\Test-Analyze.ps1
#>
$ErrorActionPreference="Stop"
. "$PSScriptRoot\skill\scripts\Analyze-SwydoReport.ps1" -DefineOnly
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
# a client note carrying a share link is redacted (not aborted): the pattern used for note redaction
$redacted = 'Latest view: https://swy.do/shares/ABCdef123 weekly' -replace $script:KeyPattern,'[redacted-share-link]'
A ($redacted -notmatch 'swy\.do/shares/ABCdef') "note redaction strips the share link (KeyPattern)"
$rthrew=$false; try{ Assert-NoCredential $redacted }catch{ $rthrew=$true }; A (-not $rthrew) "redacted note passes Assert-NoCredential (no pipeline abort)"

Write-Host "== Get-ProviderFilterFinding (--platform, U2) =="
A ($null -eq (Get-ProviderFilterFinding @() @('google-adwords','facebook-ads'))) "no filter => no finding"
A ($null -eq (Get-ProviderFilterFinding $null @('google-adwords','facebook-ads'))) "null filter (absent/[] deserialized) => no finding (no @(null) trap)"
$pff = Get-ProviderFilterFinding @('google-adwords') @('google-adwords','facebook-ads')
A ($null -ne $pff -and $pff.ruleId -eq 'PROVIDER_FILTERED' -and $pff.severity -eq 'major') "filter with exclusion => major PROVIDER_FILTERED finding"
A ($pff.statement -match 'facebook-ads') "finding names the excluded platform"
A ($null -eq (Get-ProviderFilterFinding @('google-adwords','facebook-ads') @('google-adwords','facebook-ads'))) "filter covers all => no finding"

Write-Host "== Test-IsAnnotation (U3) =="
A (Test-IsAnnotation 'Account notes: - Creatives were updated both on Google Ads and Facebook on June 8th, 2026.' @('Google Ads','Facebook Ads')) "real note kept"
A (-not (Test-IsAnnotation 'Google Ads' @('Google Ads','Facebook Ads'))) "provider header 'Google Ads' dropped"
A (-not (Test-IsAnnotation 'Facebook Ads' @('Google Ads','Facebook Ads'))) "provider header 'Facebook Ads' dropped"
A (-not (Test-IsAnnotation '' @())) "empty dropped"
A (-not (Test-IsAnnotation 'Summary' @())) "single word dropped"
A (Test-IsAnnotation 'Creative refresh launched mid-quarter across all campaigns' @()) "6+ word note kept"

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
function Met($n,$id,$unit=$null){ [pscustomobject]@{name=$n;id=$id;unit=$unit} }
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

Write-Host "== Metric-Type =="
$mt=@{ 'google-adwords:cost_micros'=@('micros','USD','currency'); 'x:ctr'=@('fraction',$null,'percent'); 'x:clicks'=@($null,$null,'number')
       'ga4:engagement_time_micros'=@('micros','USD','number'); 'google-adwords:quality_info_quality_score'=@($null,$null,'ratio')
       'x:frequency'=@($null,$null,'ratio'); 'x:roas'=@($null,$null,'ratio'); 'google-adwords:search_lost_is_budget'=@('fraction',$null,'percent')
       'x:conversions'=@($null,$null,'number'); 'facebook-ads:spend'=@('micros','USD','currency'); 'x:average_impression_frequency_per_user'=@($null,$null,'ratio') }
foreach($k in $mt.Keys){ $v=$mt[$k]; A ((Metric-Type $k $v[0] $v[1]) -eq $v[2]) "Metric-Type $k => $(Metric-Type $k $v[0] $v[1]) exp $($v[2])" }

Write-Host "== Get-Breakdown =="
# F1: letter-less age buckets must NOT collapse (Row-Label, not Get-DimLabel)
$age = Wgt 'facebook-ads' 'Facebook Ads' 'Age' @((Met 'Clicks' 'facebook-ads:clicks')) @(
  (Rw 'total' $null 'Age' @{Clicks=@(4525,$null)}),(Rw 'data' '65+' 'Age' @{Clicks=@(2379,$null)}),
  (Rw 'data' '55-64' 'Age' @{Clicks=@(914,$null)}),(Rw 'data' '18-24' 'Age' @{Clicks=@(25,$null)}))
$bd=Get-Breakdown $age 20 $null
A ($bd.rows.Count -eq 3) "age breakdown keeps all 3 rows (F1: not collapsed to group)"
A ($bd.rows[0].label -eq '65+') "row label via Row-Label = '65+', ordered desc"
$cell=$bd.rows[0].values.Clicks
A ($null -ne $cell.display -and -not $cell.Contains('current')) "cell is display-only, no raw current (F7)"
A ($cell.type -eq 'number') "cell type tagged"
# F2: force-include a finding-referenced row past the cap
$rm=[System.Collections.ArrayList]@(); [void]$rm.Add((Rw 'total' $null 'Kw' @{Impr=@(10000,$null)}))
foreach($i in 1..25){ $v=(30-$i)*10+5; [void]$rm.Add((Rw 'data' "kw$i" 'Kw' @{Impr=@($v,$null)})) }
$rm=@($rm)
$kw=Wgt 'google-adwords' 'Google Ads' 'Kw' @((Met 'Impr' 'google-adwords:impressions')) $rm
$bd2=Get-Breakdown $kw 5 @('kw25')
A (@($bd2.rows | Where-Object { $_.label -eq 'kw25' }).Count -eq 1) "finding-referenced low row force-included past cap (F2)"
A ($bd2.note -match 'of 25') "note reports rowCount ($($bd2.note))"
# F8: time widget sorts chronologically, not by metric
$mon=Wgt 'facebook-ads' 'Facebook Ads' 'Month' @((Met 'Impr' 'facebook-ads:impressions')) @(
  (Rw 'total' $null 'Month' @{Impr=@(407553,$null)}),(Rw 'data' '2026-06' 'Month' @{Impr=@(75054,$null)}),
  (Rw 'data' '2026-04' 'Month' @{Impr=@(225032,$null)}),(Rw 'data' '2026-05' 'Month' @{Impr=@(107467,$null)}))
$bd3=Get-Breakdown $mon 20 $null
A ($bd3.rows[0].label -eq '2026-04' -and $bd3.rows[2].label -eq '2026-06') "time widget sorted chronologically (F8)"

Write-Host "== Format-Money / Get-TimeSeries =="
A ((Format-Money 1000 'USD') -eq '$1,000.00') "Format-Money USD"
A ($null -eq (Format-Money $null 'USD')) "Format-Money null => null"
A ((Format-Money 5 'SEK') -eq 'SEK 5.00') "Format-Money unknown currency code-prefix"
# FB month widget: derived CPL per bucket + impressions pacing
$fbm = Wgt 'facebook-ads' 'Facebook Ads' 'Month' @((Met 'Impr' 'facebook-ads:impressions'),(Met 'Leads' 'facebook-ads:actions::lead'),(Met 'Spend' 'facebook-ads:spend' 'micros')) @(
  (Rw 'total' $null 'Month' @{Impr=@(407553,$null);Leads=@(432,$null);Spend=@(7075800000,$null)}),
  (Rw 'data' '2026-06' 'Month' @{Impr=@(75054,$null);Leads=@(100,$null);Spend=@(2312960000,$null)}),
  (Rw 'data' '2026-04' 'Month' @{Impr=@(225032,$null);Leads=@(149,$null);Spend=@(2274250000,$null)}),
  (Rw 'data' '2026-05' 'Month' @{Impr=@(107467,$null);Leads=@(183,$null);Spend=@(2488590000,$null)}))
$ts=Get-TimeSeries $fbm
A ($ts.buckets[0].label -eq '2026-04' -and $ts.buckets[2].label -eq '2026-06') "timeSeries chronological (Apr..Jun)"
A ($ts.buckets[0].derived.CPL -eq '$15.26') "Apr CPL = $15.26 (spend micros/1e6 / leads, denom raw)"
A ($ts.buckets[1].derived.CPL -eq '$13.60') "May CPL = $13.60"
A ($ts.buckets[2].derived.CPL -eq '$23.13') "Jun CPL = $23.13 (the spike)"
A ($ts.pacing.metric -eq 'Impr') "pacing on primary (Impressions)"
A ($ts.pacing.maxVsMinRatio -eq '3.0x') "April 3.0x June impressions"
A ($ts.pacing.trend -eq 'declining' -and $ts.pacing.series.Count -eq 3) "front-loaded => declining; ordered series exposed"
# zero-denominator bucket => null + gap (not silent)
$fbz = Wgt 'facebook-ads' 'Facebook Ads' 'Month' @((Met 'Leads' 'facebook-ads:actions::lead'),(Met 'Spend' 'facebook-ads:spend' 'micros')) @(
  (Rw 'total' $null 'Month' @{Leads=@(10,$null);Spend=@(1000000000,$null)}),
  (Rw 'data' '2026-04' 'Month' @{Leads=@(0,$null);Spend=@(500000000,$null)}),
  (Rw 'data' '2026-05' 'Month' @{Leads=@(10,$null);Spend=@(500000000,$null)}))
$tsz=Get-TimeSeries $fbz
A ($null -eq $tsz.buckets[0].derived.CPL -and @($tsz.buckets[0].derivedGaps).Count -ge 1) "zero-leads bucket => CPL null + derivedGap (F2)"
# non-time widget => null
$ntw = Wgt 'facebook-ads' 'Facebook Ads' 'Campaign' @((Met 'Leads' 'facebook-ads:actions::lead')) @((Rw 'total' $null 'Campaign' @{Leads=@(10,$null)}),(Rw 'data' 'X' 'Campaign' @{Leads=@(10,$null)}))
A ($null -eq (Get-TimeSeries $ntw)) "non-time widget => no timeSeries"

Write-Host "== U6: Total-Row / Get-WidgetProvider / Test-Blended (-DefineOnly units) =="
# 1. dimensioned table, NO total row -> $null (the live slice-promotion bug: never promote a data slice)
$u6w1=[pscustomobject]@{ dimensions=@('Campaign'); rows=@((Rw 'data' 'A' 'Campaign' @{X=@(10,$null)}),(Rw 'data' 'B' 'Campaign' @{X=@(20,$null)})) }
A ($null -eq (Total-Row $u6w1)) "Total-Row: dimensioned no-total => null (A1 slice-promotion fix)"
# 2. zero-dim KPI, one data row -> that row is the account total
$u6w2=[pscustomobject]@{ dimensions=@(); rows=@((Rw 'data' $null 'x' @{X=@(100,$null)})) }
A ((Row-Cur (Total-Row $u6w2) 'X') -eq 100) "Total-Row: zero-dim KPI data row IS the total"
# 3. dimensioned table WITH a total row -> the total row (unchanged)
$u6w3=[pscustomobject]@{ dimensions=@('Campaign'); rows=@((Rw 'total' $null 'Campaign' @{X=@(30,$null)}),(Rw 'data' 'A' 'Campaign' @{X=@(10,$null)})) }
A ((Row-Cur (Total-Row $u6w3) 'X') -eq 30) "Total-Row: dimensioned WITH total row => total row"
# 4. dimensioned, only subtotal + data -> $null (subtotal never selected; no KPI fallback)
$u6w4=[pscustomobject]@{ dimensions=@('Campaign'); rows=@((Rw 'subtotal' $null 'Campaign' @{X=@(99,$null)}),(Rw 'data' 'A' 'Campaign' @{X=@(10,$null)})) }
A ($null -eq (Total-Row $u6w4)) "Total-Row: dimensioned subtotal+data => null (subtotal not a total)"
# 5. dimensions=$null + one data row -> treated as zero-dim (no @($null).Count==1 trap)
$u6w5=[pscustomobject]@{ dimensions=$null; rows=@((Rw 'data' $null 'x' @{X=@(5,$null)})) }
A ((Row-Cur (Total-Row $u6w5) 'X') -eq 5) "Total-Row: null dimensions => zero-dim, returns data row (no @(null) trap)"
# 6. Get-WidgetProvider: declared wins; else metric prefix; else null
A ((Get-WidgetProvider ([pscustomobject]@{ providers=@([pscustomobject]@{id='facebook-ads';name='FB'}); metrics=@([pscustomobject]@{id='google-adwords:x'}) })) -eq 'facebook-ads') "Get-WidgetProvider: declared provider wins"
A ((Get-WidgetProvider ([pscustomobject]@{ metrics=@([pscustomobject]@{id='google-adwords:clicks'}) })) -eq 'google-adwords') "Get-WidgetProvider: else first-metric prefix"
A ($null -eq (Get-WidgetProvider ([pscustomobject]@{ metrics=@() }))) "Get-WidgetProvider: neither => null"
# 7. Test-Blended
A (Test-Blended ([pscustomobject]@{ providers=@([pscustomobject]@{id='a'},[pscustomobject]@{id='b'}) })) "Test-Blended: >1 provider => true"
A (-not (Test-Blended ([pscustomobject]@{ providers=@([pscustomobject]@{id='a'}) }))) "Test-Blended: 1 provider => false"
A (-not (Test-Blended ([pscustomobject]@{ }))) "Test-Blended: no providers => false"
# 19. ANOM_CONCENTRATION no longer fires on a dimensioned no-total widget (removes first-row-is-100% FP)
$u6conc=[pscustomobject]@{ providers=@([pscustomobject]@{id='google-adwords';name='Google Ads'}); currencyCode='USD'; dimensions=@('Device'); metrics=@((Met 'Conv' 'google-adwords:conversions')); rows=@((Rw 'data' 'MOBILE' 'Device' @{Conv=@(70,$null)}),(Rw 'data' 'DESKTOP' 'Device' @{Conv=@(30,$null)})) }
A (-not (HasRule (Get-BreakdownFindings $u6conc) 'ANOM_CONCENTRATION')) "Get-BreakdownFindings: no ANOM_CONCENTRATION on dimensioned no-total widget (A1 behavior #3)"

Write-Host "== U6: end-to-end body (write v2 extraction, run the REAL script, read back facts) =="
# The 135 cases above are -DefineOnly unit tests that never exercise the run body. These run the script.
$AnalyzeScript = "$PSScriptRoot\skill\scripts\Analyze-SwydoReport.ps1"
function Cell($cur,$cmp=$null){ [pscustomobject]@{ current=$cur; compare=$cmp } }
# zero-dim (KPI) data row: no dimensions; the single row IS the account total
function KRow($mv){ $mm=[ordered]@{}; foreach($k in $mv.Keys){ $mm[$k]=$mv[$k] }; [pscustomobject]@{ kind='data'; metrics=[pscustomobject]$mm } }
# dimensioned row (kind = total|data|subtotal)
function DRow($kind,$label,$dim,$mv){ $dm=[ordered]@{}; $dm[$dim]=$label; $mm=[ordered]@{}; foreach($k in $mv.Keys){ $mm[$k]=$mv[$k] }; [pscustomobject]@{ kind=$kind; dimensions=[pscustomobject]$dm; metrics=[pscustomobject]$mm } }
# data widget: dims=@() for a KPI; $prov/$pname used unless $providersOverride given (blended); $cc currency
function DW($id,$prov,$pname,$dims,$mets,$rows,$providersOverride,$cc){
  $provs = if($providersOverride){ $providersOverride } else { @([pscustomobject]@{id=$prov;name=$pname}) }
  $ccv = if($cc){ $cc } else { 'USD' }
  [pscustomobject]@{ kind='data'; id=$id; providers=$provs; currencyCode=$ccv; dimensions=@($dims); metrics=$mets; rows=$rows }
}
function MkDoc($widgets,$measure){
  if(-not $measure){ $measure='quarter' }
  [pscustomobject]@{
    meta=[pscustomobject]@{ schemaVersion=2; tool='Get-SwydoReport.ps1'; extractedAt='2026-07-06T02:23:57+03:00'; warnings=@(); providerFilter=@(); providerInventory=@(); clientId='C1'; unitBasis=$null }
    report=[pscustomobject]@{ name='E2E Test'; client='E2E Client'; dateRange=[pscustomobject]@{ primary=[pscustomobject]@{ count=-1; measure=$measure; type='RELATIVE' } }; sections=@() }
    widgets=@($widgets)
  }
}
function RunAnalyze($doc){
  $d = Join-Path ([IO.Path]::GetTempPath()) ('swy-'+[Guid]::NewGuid().ToString('N').Substring(0,10))
  New-Item -ItemType Directory -Force -Path $d | Out-Null
  $in = Join-Path $d 'in.json'
  [IO.File]::WriteAllText($in, ($doc | ConvertTo-Json -Depth 40), (New-Object Text.UTF8Encoding($false)))
  & $AnalyzeScript -InFile $in -OutDir $d *> $null
  $fp = @(Get-ChildItem -Path $d -Filter '*.facts.json' | Sort-Object LastWriteTime -Descending)[0].FullName
  $txt = [IO.File]::ReadAllText($fp)
  [pscustomobject]@{ dir=$d; path=$fp; text=$txt; facts=($txt | ConvertFrom-Json) }
}
function Plat($facts,$id){ @($facts.platforms | Where-Object { $_.id -eq $id })[0] }
function Hl($facts,$provId,$metricId){ $pf=Plat $facts $provId; if(-not $pf -or -not $pf.headline){ return $null }; if($pf.headline.PSObject.Properties.Name -contains $metricId){ return $pf.headline.$metricId } return $null }
function AllFind($facts){ $all=@(); foreach($c in 'wins','losses','anomalies','discrepancies','dataGaps'){ $all += @($facts.findings.$c) }; return @($all) }
function HasFind($facts,$ruleId){ [bool](@((AllFind $facts) | Where-Object { $_.ruleId -eq $ruleId }).Count) }
function GetFind($facts,$ruleId){ @((AllFind $facts) | Where-Object { $_.ruleId -eq $ruleId })[0] }

# 9. zero-dim KPI -> headline cell with account-scope canonical provenance
$r9 = RunAnalyze (MkDoc @( (DW 'w-kpi' 'google-adwords' 'Google Ads' @() @((Met 'Cost' 'google-adwords:cost_micros' 'micros'),(Met 'Clicks' 'google-adwords:clicks')) @((KRow @{Cost=(Cell 10864723050);Clicks=(Cell 15627)}))) ))
$h9 = Hl $r9.facts 'google-adwords' 'google-adwords:cost_micros'
A ($null -ne $h9) "e2e9: zero-dim KPI produces a headline cell"
A ($h9.canonical.scope -eq 'account' -and $h9.canonical.source -eq 'kpi-widget' -and $h9.canonical.sourceWidgetId -eq 'w-kpi') "e2e9: canonical scope=account source=kpi-widget sourceWidgetId=w-kpi"
# 8. slice-promotion regression: dimensioned no-total widget -> large top slice appears in NO headline cell + gap
$r8 = RunAnalyze (MkDoc @( (DW 'w-notot' 'google-adwords' 'Google Ads' @('Campaign') @((Met 'Cost' 'google-adwords:cost_micros' 'micros')) @((DRow 'data' 'Big' 'Campaign' @{Cost=(Cell 5000000000)}),(DRow 'data' 'Small' 'Campaign' @{Cost=(Cell 100000000)}))) ))
A ($null -eq (Hl $r8.facts 'google-adwords' 'google-adwords:cost_micros')) "e2e8: dimensioned no-total => NO headline cell (slice not promoted)"
A (HasFind $r8.facts 'GAP_NO_ACCOUNT_TOTAL') "e2e8: dimensioned no-total => GAP_NO_ACCOUNT_TOTAL emitted"
# 10. dimensioned WITH total row -> table-total scope
$r10 = RunAnalyze (MkDoc @( (DW 'w-tot' 'google-adwords' 'Google Ads' @('Campaign') @((Met 'Cost' 'google-adwords:cost_micros' 'micros')) @((DRow 'total' $null 'Campaign' @{Cost=(Cell 3000000000)}),(DRow 'data' 'A' 'Campaign' @{Cost=(Cell 1000000000)}))) ))
$h10 = Hl $r10.facts 'google-adwords' 'google-adwords:cost_micros'
A ($null -ne $h10 -and $h10.canonical.scope -eq 'table-total:Campaign' -and $h10.canonical.source -eq 'total-row') "e2e10: dimensioned total row => scope=table-total:Campaign source=total-row (never bare account)"
# 11. two widgets same (prov,metricId): document-order first-wins decides sourceWidgetId (no rank reordering)
$r11 = RunAnalyze (MkDoc @(
  (DW 'w-first' 'google-adwords' 'Google Ads' @('Campaign') @((Met 'Cost' 'google-adwords:cost_micros' 'micros')) @((DRow 'total' $null 'Campaign' @{Cost=(Cell 2000000000)}),(DRow 'data' 'A' 'Campaign' @{Cost=(Cell 2000000000)}))),
  (DW 'w-second' 'google-adwords' 'Google Ads' @() @((Met 'Cost' 'google-adwords:cost_micros' 'micros')) @((KRow @{Cost=(Cell 9999000000)})))
))
A ((Hl $r11.facts 'google-adwords' 'google-adwords:cost_micros').canonical.sourceWidgetId -eq 'w-first') "e2e11: document-order first-wins (w-first, not the later KPI card)"
# 12/13. every headline cell carries the canonical struct; canonical.display==displayCurrent; no value/basisVersion/synthesizedFrom
A ($h9.canonical.display -eq $h9.displayCurrent) "e2e12: canonical.display == displayCurrent"
foreach($kk in 'display','sourceWidgetId','scope','period','source'){ A ($h9.canonical.PSObject.Properties.Name -contains $kk) "e2e12: canonical carries '$kk'" }
foreach($bad in 'value','basisVersion','synthesizedFrom'){ A (-not ($h9.canonical.PSObject.Properties.Name -contains $bad)) "e2e13: canonical has NO '$bad'" }
# 14. meta versions
A ($r9.facts.meta.canonicalVersion -eq 1 -and $r9.facts.meta.factsVersion -eq 1) "e2e14: meta.canonicalVersion=1, factsVersion=1"
# 15. GAP_NO_ACCOUNT_TOTAL shape: info + fid + evidence.metrics
$g15 = GetFind $r8.facts 'GAP_NO_ACCOUNT_TOTAL'
A ($g15.severity -eq 'info' -and $g15.fid -and @($g15.evidence.metrics).Count -ge 1) "e2e15: GAP_NO_ACCOUNT_TOTAL severity=info, has fid, evidence.metrics listed"
# 16. cardinality/dedup: one provider, 25 no-total metrics -> exactly ONE gap, count=25, metrics capped at 20 + '+N more'
$mets16=@(); $mv16=@{}; foreach($i in 1..25){ $mets16 += (Met "M$i" "google-adwords:m$i"); $mv16["M$i"]=(Cell (1000+$i)) }
$r16 = RunAnalyze (MkDoc @( (DW 'w16' 'google-adwords' 'Google Ads' @('Campaign') $mets16 @((DRow 'data' 'A' 'Campaign' $mv16),(DRow 'data' 'B' 'Campaign' $mv16))) ))
$g16=@((AllFind $r16.facts) | Where-Object { $_.ruleId -eq 'GAP_NO_ACCOUNT_TOTAL' })
A ($g16.Count -eq 1) "e2e16: exactly ONE GAP_NO_ACCOUNT_TOTAL for the provider (deduped)"
A ($g16[0].evidence.count -eq '25' -and @($g16[0].evidence.metrics).Count -eq 21 -and ($g16[0].evidence.metrics[-1] -match '^\+5 more$')) "e2e16: count=25, metrics capped at 20 + '+5 more' sentinel"
# 17. blended-only provider (B is the blended widget's primary): discovered, empty headline, gap names B's metric
$r17 = RunAnalyze (MkDoc @(
  (DW 'w-blend' $null $null @() @((Met 'BLeads' 'provb:leads'),(Met 'AClicks' 'google-adwords:clicks')) @((KRow @{BLeads=(Cell 50);AClicks=(Cell 200)})) @([pscustomobject]@{id='provb';name='Provider B'},[pscustomobject]@{id='google-adwords';name='Google Ads'})),
  (DW 'w-a' 'google-adwords' 'Google Ads' @() @((Met 'AClicks' 'google-adwords:clicks')) @((KRow @{AClicks=(Cell 200)})))
))
$pfB = Plat $r17.facts 'provb'
A ($null -ne $pfB -and @($pfB.headline.PSObject.Properties.Name | Where-Object { $_ }).Count -eq 0) "e2e17: blended-only provider B discovered with EMPTY headline"
$g17 = @((AllFind $r17.facts) | Where-Object { $_.ruleId -eq 'GAP_NO_ACCOUNT_TOTAL' -and $_.platform -eq 'Provider B' })
A ($g17.Count -eq 1 -and ($g17[0].evidence.metrics -contains 'provb:leads')) "e2e17: GAP_NO_ACCOUNT_TOTAL names Provider B's metric (provb:leads)"
A (-not ($r17.text -match '"sourceWidgetId":"w-blend"')) "e2e17: blended widget is never a canonical.sourceWidgetId"
# REVIEW FIX (major): a provider appearing ONLY as a NON-primary side of a blended widget (never providers[0])
# must still be discovered + surface GAP_NO_ACCOUNT_TOTAL (all-providers discovery closes the silent-drop hole).
$r17b = RunAnalyze (MkDoc @(
  (DW 'w-blend2' 'google-adwords' 'Google Ads' @() @((Met 'AClicks' 'google-adwords:clicks'),(Met 'BLeads' 'provc:leads')) @((KRow @{AClicks=(Cell 200);BLeads=(Cell 50)})) @([pscustomobject]@{id='google-adwords';name='Google Ads'},[pscustomobject]@{id='provc';name='Provider C'})),
  (DW 'w-a2' 'google-adwords' 'Google Ads' @() @((Met 'AClicks' 'google-adwords:clicks')) @((KRow @{AClicks=(Cell 200)})))
))
A ($null -ne (Plat $r17b.facts 'provc')) "e2e17b: non-primary blended-only provider C IS discovered (all-providers discovery)"
$g17b = @((AllFind $r17b.facts) | Where-Object { $_.ruleId -eq 'GAP_NO_ACCOUNT_TOTAL' -and $_.platform -eq 'Provider C' })
A ($g17b.Count -eq 1 -and ($g17b[0].evidence.metrics -contains 'provc:leads')) "e2e17b: GAP_NO_ACCOUNT_TOTAL names Provider C's metric (no silent drop)"
# 18. DISC unchanged: two zero-dim KPI widgets disagreeing => DISC_CROSS_WIDGET (major)
$r18a = RunAnalyze (MkDoc @(
  (DW 'k1' 'google-adwords' 'Google Ads' @() @((Met 'Clicks' 'google-adwords:clicks')) @((KRow @{Clicks=(Cell 100)}))),
  (DW 'k2' 'google-adwords' 'Google Ads' @() @((Met 'Clicks' 'google-adwords:clicks')) @((KRow @{Clicks=(Cell 200)})))
))
A (HasFind $r18a.facts 'DISC_CROSS_WIDGET') "e2e18: two disagreeing zero-dim KPIs => DISC_CROSS_WIDGET fires"
# ...two dimensioned NO-TOTAL widgets whose top slices differ => NO DISC (they drop out via A1)
$r18b = RunAnalyze (MkDoc @(
  (DW 'd1' 'google-adwords' 'Google Ads' @('Campaign') @((Met 'Clicks' 'google-adwords:clicks')) @((DRow 'data' 'A' 'Campaign' @{Clicks=(Cell 100)}))),
  (DW 'd2' 'google-adwords' 'Google Ads' @('Campaign') @((Met 'Clicks' 'google-adwords:clicks')) @((DRow 'data' 'A' 'Campaign' @{Clicks=(Cell 200)})))
))
A (-not (HasFind $r18b.facts 'DISC_CROSS_WIDGET')) "e2e18: two dimensioned no-total widgets => NO DISC_CROSS_WIDGET (A1 drops them)"
# 20. byte-identical: int KPI current stays an integer in JSON (not 1000.0); displayCurrent unchanged
$h20 = Hl $r9.facts 'google-adwords' 'google-adwords:clicks'
A ($h20.displayCurrent -eq '15,627') "e2e20: int KPI displayCurrent byte-identical ('15,627')"
A ($r9.text -match '"current":15627,' -and -not ($r9.text -match '"current":15627\.0')) "e2e20: emitted current is integer 15627 in JSON, not 15627.0 (raw cell, not Row-Cur [double])"
# 21. seasonality caveat: only comparison-bearing widget is a dimensioned no-total table -> hasComparison false, no caveat
$r21 = RunAnalyze (MkDoc @(
  (DW 'kc' 'google-adwords' 'Google Ads' @() @((Met 'Clicks' 'google-adwords:clicks')) @((KRow @{Clicks=(Cell 100)}))),
  (DW 'dc' 'google-adwords' 'Google Ads' @('Campaign') @((Met 'Conv' 'google-adwords:conversions')) @((DRow 'data' 'A' 'Campaign' @{Conv=@(50,40)})))
))
A ($r21.facts.meta.hasComparison -eq $false -and @($r21.facts.meta.comparisonCaveats).Count -eq 0) "e2e21: only-no-total-table comparison => hasComparison false, no seasonality caveat (behavior #5)"

Write-Host "== U7a: reconciliation helper units (-DefineOnly) =="
foreach($id in 'x:impressions','x:clicks','x:conversions','x:sessions','x:spend','x:cost_micros','x:conversions_value','x:bounces'){ A (Test-Summable $id) "Test-Summable TRUE: $id" }
foreach($id in 'google-analytics-4:activeUsers','google-analytics-4:totalUsers','google-analytics-4:newUsers','x:uniqueUsers','x:ctr','x:average_cpc','x:impression_share','x:average_position','x:roas','ga4:screenPageViewsPerSession','ga4:eventsPerSession','x:value_per_conversion'){ A (-not (Test-Summable $id)) "Test-Summable FALSE: $id" }
# intentional Test-Additive vs Test-Summable divergence (R4; must NOT be silently unified)
A ((Test-Additive 'ga4:activeUsers') -and -not (Test-Summable 'ga4:activeUsers')) "predicate split: activeUsers additive but NOT summable (GA4 user)"
A ((Test-Additive 'x:value') -and -not (Test-Summable 'x:value')) "predicate split: bare 'value' additive but NOT summable"
A (Test-SameBasis 'micros' 'USD' 'micros' 'USD') "Test-SameBasis: (micros,USD)==(micros,USD)"
A (-not (Test-SameBasis 'micros' 'USD' 'micros' 'EUR')) "Test-SameBasis: currency differs => false"
A (Test-SameBasis $null $null $null $null) "Test-SameBasis: (null,null)==(null,null)"
A (-not (Test-SameBasis 'micros' 'USD' $null 'USD')) "Test-SameBasis: unit null differs => false"
foreach($d in 'campaign','ad_group','keyword','date','Day','Landing Page','device'){ A (Test-PartitionDim $d) "Test-PartitionDim TRUE: $d" }
foreach($d in 'action_type','conversion_action','audience'){ A (-not (Test-PartitionDim $d)) "Test-PartitionDim FALSE: $d" }
# Get-MetricUlp value-aware (mirrors Format-Metric N0/N1) + drift cross-check
A ((Get-MetricUlp 'x:cost_micros' 'micros' 'USD' 10864.72) -eq 0.01) "Get-MetricUlp micros => 0.01"
A ((Get-MetricUlp 'x:ctr' 'fraction' $null 0.05) -eq 0.001) "Get-MetricUlp fraction => 0.001"
A ((Get-MetricUlp 'x:clicks' $null $null 9) -eq 1.0) "Get-MetricUlp integer count => 1.0"
A ((Get-MetricUlp 'x:conversions' $null $null 12.7) -eq 0.1) "Get-MetricUlp fractional count => 0.1"
A ((Get-MetricUlp 'x:roas' $null $null 4.2) -eq 0.1) "Get-MetricUlp ratio-typed (roas 4.2) => 0.1"
function _fmtUlp($disp){ $m=[regex]::Match([string]$disp,'\.(\d+)'); $dec=if($m.Success){$m.Groups[1].Value.Length}else{0}; [math]::Pow(10,-$dec) }
A ((Get-MetricUlp 'x:clicks' $null $null 9) -eq (_fmtUlp (Format-Metric 'x:clicks' $null 9 $null))) "Get-MetricUlp integer matches Format-Metric N0 step (no drift)"
A ((Get-MetricUlp 'x:conversions' $null $null 12.7) -eq (_fmtUlp (Format-Metric 'x:conversions' $null 12.7 $null))) "Get-MetricUlp fractional matches Format-Metric N1 step (no drift)"
# REVIEW FIX (major): a money-id with NULL unit renders as a COUNT (N0/N1), NOT cents - ulp must mirror that
A ((Get-MetricUlp 'x:cost' $null 'USD' 1000) -eq 1.0) "Get-MetricUlp null-unit money integer => 1.0 (mirrors Format-Metric count, NOT 0.01)"
A ((Get-MetricUlp 'x:cost' $null 'USD' 12.5) -eq 0.1) "Get-MetricUlp null-unit money fractional => 0.1"
A ((Get-MetricUlp 'x:cost' $null 'USD' 1000) -eq (_fmtUlp (Format-Metric 'x:cost' $null 1000 'USD'))) "Get-MetricUlp null-unit money matches Format-Metric step (fixes #4/#5 false-major)"
$rsK=@{ 'google-adwords:ctr'='ctr'; 'facebook-ads:ctrLink'='ctr-link'; 'google-adwords:average_cpc'='cpc'; 'x:cpm'='cpm'; 'x:cpl'='cpl'; 'google-adwords:cost_per_conversion'='cpa'; 'x:conversion_rate'='cvr'; 'x:roas'='roas'; 'x:aov'='aov' }
foreach($k in $rsK.Keys){ A ((Get-RatioSpec $k).kind -eq $rsK[$k]) "Get-RatioSpec $k => $((Get-RatioSpec $k).kind) exp $($rsK[$k])" }
A ($null -eq (Get-RatioSpec 'x:impressions')) "Get-RatioSpec: non-ratio => null"
A ((Get-RatioSpec 'x:roas').numPat -match 'value') "Get-RatioSpec: roas numerator is value-only"
A ((Get-RatioSpec 'x:average_cpc').numPat -match 'cost') "Get-RatioSpec: cpc numerator is cost-only"

Write-Host "== U7a: Check #3 ratio-recompute (e2e) =="
$u3a = RunAnalyze (MkDoc @( (DW 'w3a' 'google-adwords' 'Google Ads' @() @((Met 'Clicks' 'google-adwords:clicks'),(Met 'Impr' 'google-adwords:impressions'),(Met 'CTR' 'google-adwords:ctr' 'fraction')) @((KRow @{Clicks=(Cell 500);Impr=(Cell 10000);CTR=(Cell 0.05)}))) ))
A (-not (HasFind $u3a.facts 'DISC_RATIO_RECOMPUTE') -and -not (HasFind $u3a.facts 'DISC_RATIO_UNIT')) "u7a#3a: correct CTR (5.0%) => no ratio finding"
$u3b = RunAnalyze (MkDoc @( (DW 'w3b' 'google-adwords' 'Google Ads' @() @((Met 'Clicks' 'google-adwords:clicks'),(Met 'Impr' 'google-adwords:impressions'),(Met 'CTR' 'google-adwords:ctr' 'fraction')) @((KRow @{Clicks=(Cell 500);Impr=(Cell 10000);CTR=(Cell 0.08)}))) ))
A (HasFind $u3b.facts 'DISC_RATIO_RECOMPUTE') "u7a#3b: avg-of-ratios CTR (0.08 vs 0.05) => info DISC_RATIO_RECOMPUTE"
A ((GetFind $u3b.facts 'DISC_RATIO_RECOMPUTE').evidence.recomputed -eq '5.0%') "u7a#3b: recomputed rendered '5.0%' (Format-Metric fraction, R19)"
A ((GetFind $u3b.facts 'DISC_RATIO_RECOMPUTE').severity -eq 'info') "u7a#3b: severity info (not major)"
A ((GetFind $u3b.facts 'DISC_RATIO_RECOMPUTE').evidence.recomputed -eq (Format-Metric 'google-adwords:ctr' 'fraction' 0.05 'USD')) "u7a#3b: recompute string byte-equal to Format-Metric fraction (R3 drift)"
$u3c = RunAnalyze (MkDoc @( (DW 'w3c' 'google-adwords' 'Google Ads' @() @((Met 'Cost' 'google-adwords:cost_micros' 'micros'),(Met 'Clicks' 'google-adwords:clicks'),(Met 'CPC' 'google-adwords:average_cpc' 'micros')) @((KRow @{Cost=(Cell 1000000);Clicks=(Cell 1);CPC=(Cell 1000000000000)}))) ))
$f3c = GetFind $u3c.facts 'DISC_RATIO_UNIT'
A ($null -ne $f3c -and $f3c.severity -eq 'major') "u7a#3c: confirmed-micros CPC ~1e6x components => major DISC_RATIO_UNIT"
A ($f3c -and ($f3c.statement -match 'micros') -and $f3c.fid) "u7a#3c: cause mentions micros; fid assigned"
$u3d = RunAnalyze (MkDoc @( (DW 'w3d' 'bing-ads' 'Bing Ads' @() @((Met 'Clicks' 'bing-ads:clicks'),(Met 'Impr' 'bing-ads:impressions'),(Met 'CTR' 'bing-ads:ctr')) @((KRow @{Clicks=(Cell 500);Impr=(Cell 10000);CTR=(Cell 5.0)}))) ))
A (-not (HasFind $u3d.facts 'DISC_RATIO_RECOMPUTE') -and -not (HasFind $u3d.facts 'DISC_RATIO_UNIT')) "u7a#3d: reported CTR unit null (percent-scaled) => R13 skip"
$u3e = RunAnalyze (MkDoc @( (DW 'w3e' 'microsoft-advertising' 'Microsoft' @() @((Met 'Cost' 'microsoft-advertising:cost_micros' 'micros'),(Met 'Clicks' 'microsoft-advertising:clicks'),(Met 'CPC' 'microsoft-advertising:average_cpc')) @((KRow @{Cost=(Cell 2500000000);Clicks=(Cell 1000);CPC=(Cell 2500000)}))) ))
A (-not (HasFind $u3e.facts 'DISC_RATIO_UNIT')) "u7a#3e: CPC unit null (micros-scale) => R13 skip, NOT a false major"
$u3f = RunAnalyze (MkDoc @( (DW 'w3f' 'google-adwords' 'Google Ads' @() @((Met 'Cost' 'google-adwords:cost_micros' 'micros'),(Met 'Clicks' 'google-adwords:clicks'),(Met 'CPC' 'google-adwords:average_cpc' 'micros')) @((KRow @{Cost=(Cell 1000000);Clicks=(Cell 0);CPC=(Cell 5000000)}))) ))
A (-not (HasFind $u3f.facts 'DISC_RATIO_UNIT') -and -not (HasFind $u3f.facts 'DISC_RATIO_RECOMPUTE')) "u7a#3f: zero denominator (clicks=0) => skip, no crash"
$u3g = RunAnalyze (MkDoc @( (DW 'w3g' 'google-adwords' 'Google Ads' @() @((Met 'Cost' 'google-adwords:cost_micros'),(Met 'Clicks' 'google-adwords:clicks'),(Met 'CPC' 'google-adwords:average_cpc' 'micros')) @((KRow @{Cost=(Cell 5000000000);Clicks=(Cell 1000);CPC=(Cell 5000000000000)}))) ))
A (-not (HasFind $u3g.facts 'DISC_RATIO_UNIT')) "u7a#3g: cost component unit null => skip (defers to GAP_UNIT_UNCONFIRMED)"
$u3h = RunAnalyze (MkDoc @( (DW 'w3h' 'facebook-ads' 'Facebook' @() @((Met 'Clicks' 'facebook-ads:clicks'),(Met 'LinkClicks' 'facebook-ads:actions::link_click'),(Met 'Impr' 'facebook-ads:impressions'),(Met 'CTR' 'facebook-ads:ctr' 'fraction')) @((KRow @{Clicks=(Cell 500);LinkClicks=(Cell 300);Impr=(Cell 10000);CTR=(Cell 0.08)}))) ))
A (-not (HasFind $u3h.facts 'DISC_RATIO_RECOMPUTE') -and -not (HasFind $u3h.facts 'DISC_RATIO_UNIT')) "u7a#3h: unqualified CTR with both clicks & link_click => ambiguous, skip"
$u3i = RunAnalyze (MkDoc @( (DW 'w3i' 'google-adwords' 'Google Ads' @('Month') @((Met 'Clicks' 'google-adwords:clicks'),(Met 'Impr' 'google-adwords:impressions'),(Met 'CTR' 'google-adwords:ctr' 'fraction')) @((DRow 'data' '2026-04' 'Month' @{Clicks=(Cell 500);Impr=(Cell 10000);CTR=(Cell 0.08)}),(DRow 'data' '2026-05' 'Month' @{Clicks=(Cell 600);Impr=(Cell 11000);CTR=(Cell 0.05)}))) ))
A (-not (HasFind $u3i.facts 'DISC_RATIO_RECOMPUTE') -and -not (HasFind $u3i.facts 'DISC_RATIO_UNIT')) "u7a#3i: time-dim native ratio (no total row) => #3 skips"
$u3j = RunAnalyze (MkDoc @( (DW 'w3j' 'google-adwords' 'Google Ads' @() @((Met 'Revenue' 'google-adwords:revenue' 'micros'),(Met 'Cost' 'google-adwords:cost_micros' 'micros'),(Met 'ROAS' 'google-adwords:roas')) @((KRow @{Revenue=(Cell 5500000000);Cost=(Cell 1000000000);ROAS=(Cell 4.2)}))) ))
$f3j = GetFind $u3j.facts 'DISC_RATIO_RECOMPUTE'
A ($null -ne $f3j -and $f3j.evidence.recomputed -eq '5.5') "u7a#3j: ROAS recompute via Format-Metric => plain '5.5' (R3/R19, no hand-rolled numbers)"
A ($f3j -and ($f3j.evidence.recomputed -notmatch '[\$x]')) "u7a#3j: recomputed has no currency symbol and no x-suffix (traceable, not <mult>-exempt)"
# REVIEW FIX (major): costPerActionType::<action> must NOT be reconciled against conversions (wrong denominator)
$u3k = RunAnalyze (MkDoc @( (DW 'w3k' 'facebook-ads' 'Facebook' @() @((Met 'Cost' 'facebook-ads:spend' 'micros'),(Met 'Conv' 'facebook-ads:conversions'),(Met 'CPLC' 'facebook-ads:costPerActionType::link_click' 'micros')) @((KRow @{Cost=(Cell 5000000000);Conv=(Cell 1);CPLC=(Cell 25000)}))) ))
A (-not (HasFind $u3k.facts 'DISC_RATIO_UNIT') -and -not (HasFind $u3k.facts 'DISC_RATIO_RECOMPUTE')) "u7a#3k: costPerActionType::link_click NOT reconciled vs conversions => no false DISC_RATIO_* (major fix)"
# REVIEW FIX (minor R20): all-CTR with only link_clicks (no plain clicks) => role mismatch => skip
$u3l = RunAnalyze (MkDoc @( (DW 'w3l' 'facebook-ads' 'Facebook' @() @((Met 'LinkClicks' 'facebook-ads:actions::link_click'),(Met 'Impr' 'facebook-ads:impressions'),(Met 'CTR' 'facebook-ads:ctr' 'fraction')) @((KRow @{LinkClicks=(Cell 100);Impr=(Cell 10000);CTR=(Cell 0.05)}))) ))
A (-not (HasFind $u3l.facts 'DISC_RATIO_RECOMPUTE') -and -not (HasFind $u3l.facts 'DISC_RATIO_UNIT')) "u7a#3l: all-CTR + only link_clicks => R20 role mismatch => skip (no spurious info)"
# REVIEW FIX (minor R20): link-CTR with only plain clicks (no link_clicks) => detected as link, no link numerator => skip
$u3m = RunAnalyze (MkDoc @( (DW 'w3m' 'facebook-ads' 'Facebook' @() @((Met 'Clicks' 'facebook-ads:clicks'),(Met 'Impr' 'facebook-ads:impressions'),(Met 'LinkCTR' 'facebook-ads:inline_link_click_ctr' 'fraction')) @((KRow @{Clicks=(Cell 800);Impr=(Cell 10000);LinkCTR=(Cell 0.02)}))) ))
A (-not (HasFind $u3m.facts 'DISC_RATIO_RECOMPUTE') -and -not (HasFind $u3m.facts 'DISC_RATIO_UNIT')) "u7a#3m: link-CTR + only plain clicks => skip (link-CTR routed to ctr-link spec, no link numerator)"

Write-Host "== U7a: Check #4 detail-sum vs total (e2e) =="
$u4a = RunAnalyze (MkDoc @( (DW 'w4a' 'google-adwords' 'Google Ads' @('campaign') @((Met 'Clicks' 'google-adwords:clicks')) @((DRow 'total' $null 'campaign' @{Clicks=(Cell 100)}),(DRow 'data' 'A' 'campaign' @{Clicks=(Cell 80)}),(DRow 'data' 'B' 'campaign' @{Clicks=(Cell 80)}))) ))
$f4a = GetFind $u4a.facts 'DISC_DETAIL_EXCEEDS_TOTAL'
A ($null -ne $f4a -and $f4a.severity -eq 'major') "u7a#4a: partition (campaign) detail 160 > total 100 => major DISC_DETAIL_EXCEEDS_TOTAL"
A ($f4a -and $f4a.fid -and $f4a.evidence.shownSum -and $f4a.evidence.total) "u7a#4a: fid + evidence shownSum/total"
$u4b = RunAnalyze (MkDoc @( (DW 'w4b' 'facebook-ads' 'Facebook' @('action_type') @((Met 'Conv' 'facebook-ads:conversions')) @((DRow 'total' $null 'action_type' @{Conv=(Cell 100)}),(DRow 'data' 'purchase' 'action_type' @{Conv=(Cell 80)}),(DRow 'data' 'lead' 'action_type' @{Conv=(Cell 80)}))) ))
A ((HasFind $u4b.facts 'RECON_ROW_OVERSUM') -and (GetFind $u4b.facts 'RECON_ROW_OVERSUM').severity -eq 'info') "u7a#4b: overlap dim (action_type) oversum => info RECON_ROW_OVERSUM"
A (-not (HasFind $u4b.facts 'DISC_DETAIL_EXCEEDS_TOTAL')) "u7a#4b: overlap dim NOT major"
$u4c = RunAnalyze (MkDoc @( (DW 'w4c' 'google-adwords' 'Google Ads' @('campaign','device') @((Met 'Clicks' 'google-adwords:clicks')) @((DRow 'total' $null 'campaign' @{Clicks=(Cell 100)}),(DRow 'data' 'A' 'campaign' @{Clicks=(Cell 80)}),(DRow 'data' 'B' 'campaign' @{Clicks=(Cell 80)}))) ))
A ((HasFind $u4c.facts 'RECON_ROW_OVERSUM') -and -not (HasFind $u4c.facts 'DISC_DETAIL_EXCEEDS_TOTAL')) "u7a#4c: multi-dim oversum => info, not major"
$u4d = RunAnalyze (MkDoc @( (DW 'w4d' 'google-adwords' 'Google Ads' @('campaign') @((Met 'Clicks' 'google-adwords:clicks')) @((DRow 'total' $null 'campaign' @{Clicks=(Cell 100)}),(DRow 'data' 'A' 'campaign' @{Clicks=(Cell 30)}),(DRow 'data' 'B' 'campaign' @{Clicks=(Cell 30)}))) ))
$f4d = GetFind $u4d.facts 'RECON_ROW_REMAINDER'
A ($null -ne $f4d -and $f4d.evidence.other) "u7a#4d: under-sum (60 of 100) => info RECON_ROW_REMAINDER with (other)"
$u4e = RunAnalyze (MkDoc @( (DW 'w4e' 'facebook-ads' 'Facebook' @('action_type') @((Met 'Conv' 'facebook-ads:conversions')) @((DRow 'total' $null 'action_type' @{Conv=(Cell 100)}),(DRow 'data' 'A' 'action_type' @{Conv=(Cell 90)}),(DRow 'data' 'B' 'action_type' @{Conv=(Cell 60)}))) ))
A (-not (HasFind $u4e.facts 'RECON_ROW_REMAINDER')) "u7a#4e: sum(150) > total(100) => oversum branch, never RECON_ROW_REMAINDER"
$u4f = RunAnalyze (MkDoc @( (DW 'w4f' 'facebook-ads' 'Facebook' @('campaign') @((Met 'Reach' 'facebook-ads:reach')) @((DRow 'total' $null 'campaign' @{Reach=(Cell 100)}),(DRow 'data' 'A' 'campaign' @{Reach=(Cell 80)}),(DRow 'data' 'B' 'campaign' @{Reach=(Cell 80)}))) ))
A (-not (HasFind $u4f.facts 'DISC_DETAIL_EXCEEDS_TOTAL') -and -not (HasFind $u4f.facts 'RECON_ROW_OVERSUM')) "u7a#4f: dedup metric (reach) not summed => no #4 finding"
$rows4g1=@((DRow 'total' $null 'campaign' @{Clicks=(Cell 100)})); foreach($i in 1..9){ $rows4g1 += (DRow 'data' "c$i" 'campaign' @{Clicks=(Cell 10)}) }; $rows4g1 += (DRow 'data' 'c10' 'campaign' @{Clicks=(Cell 15)})
$u4g1 = RunAnalyze (MkDoc @( (DW 'w4g1' 'google-adwords' 'Google Ads' @('campaign') @((Met 'Clicks' 'google-adwords:clicks')) $rows4g1) ))
A (-not (HasFind $u4g1.facts 'DISC_DETAIL_EXCEEDS_TOTAL')) "u7a#4g: 10 rows summing +5 (< row-count tol) => no major"
$rows4g2=@((DRow 'total' $null 'campaign' @{Clicks=(Cell 100)})); foreach($i in 1..9){ $rows4g2 += (DRow 'data' "c$i" 'campaign' @{Clicks=(Cell 10)}) }; $rows4g2 += (DRow 'data' 'c10' 'campaign' @{Clicks=(Cell 25)})
$u4g2 = RunAnalyze (MkDoc @( (DW 'w4g2' 'google-adwords' 'Google Ads' @('campaign') @((Met 'Clicks' 'google-adwords:clicks')) $rows4g2) ))
A (HasFind $u4g2.facts 'DISC_DETAIL_EXCEEDS_TOTAL') "u7a#4g: 10 rows summing +15 (> row-count tol) => major"
$u4j = RunAnalyze (MkDoc @( (DW 'w4j' 'google-adwords' 'Google Ads' @('campaign') @((Met 'Clicks' 'google-adwords:clicks')) @((DRow 'data' 'A' 'campaign' @{Clicks=(Cell 80)}),(DRow 'data' 'B' 'campaign' @{Clicks=(Cell 80)}))) ))
A (-not (HasFind $u4j.facts 'DISC_DETAIL_EXCEEDS_TOTAL') -and -not (HasFind $u4j.facts 'RECON_ROW_OVERSUM')) "u7a#4j: dimensioned no-total => #4 skip (Total-Row null)"
# REVIEW FIX (major): a null-unit money metric must use the count ULP (1.0), so a small +4 rounding drift over
# 10 rows stays within row-count tolerance (max(2,10)*1=10) instead of collapsing to 0.1 and false-firing major.
$rows4k=@((DRow 'total' $null 'campaign' @{Cost=(Cell 996)})); foreach($i in 1..10){ $rows4k += (DRow 'data' "c$i" 'campaign' @{Cost=(Cell 100)}) }
$u4k = RunAnalyze (MkDoc @( (DW 'w4k' 'someads' 'SomeAds' @('campaign') @((Met 'Cost' 'someads:cost')) $rows4k) ))
A (-not (HasFind $u4k.facts 'DISC_DETAIL_EXCEEDS_TOTAL')) "u7a#4k: null-unit money (cost) +4 over total within row-count tol => NO false major (Get-MetricUlp fix)"

Write-Host "== U7a: Check #5 slice vs account KPI (e2e) =="
$u5a = RunAnalyze (MkDoc @(
  (DW 'w5a-tab' 'google-adwords' 'Google Ads' @('campaign') @((Met 'Spend' 'google-adwords:cost_micros' 'micros')) @((DRow 'total' $null 'campaign' @{Spend=(Cell 120000000)}),(DRow 'data' 'A' 'campaign' @{Spend=(Cell 120000000)}))),
  (DW 'w5a-kpi' 'google-adwords' 'Google Ads' @() @((Met 'Spend' 'google-adwords:cost_micros' 'micros')) @((KRow @{Spend=(Cell 100000000)})))
))
$f5a = GetFind $u5a.facts 'RECON_SLICE_OVER_ACCOUNT'
A ($null -ne $f5a -and $f5a.severity -eq 'info') "u7a#5a: slice(120) > account KPI(100), same basis => info RECON_SLICE_OVER_ACCOUNT (scan-all finds later KPI => doc-order-loss covered)"
A ($f5a -and $f5a.evidence.slice -and $f5a.evidence.account -and $f5a.evidence.note) "u7a#5a: evidence slice/account/note present"
$u5b = RunAnalyze (MkDoc @(
  (DW 'w5b-tab' 'google-adwords' 'Google Ads' @('campaign') @((Met 'Spend' 'google-adwords:cost_micros' 'micros')) @((DRow 'total' $null 'campaign' @{Spend=(Cell 80000000)}),(DRow 'data' 'A' 'campaign' @{Spend=(Cell 80000000)}))),
  (DW 'w5b-kpi' 'google-adwords' 'Google Ads' @() @((Met 'Spend' 'google-adwords:cost_micros' 'micros')) @((KRow @{Spend=(Cell 100000000)})))
))
A (-not (HasFind $u5b.facts 'RECON_SLICE_OVER_ACCOUNT')) "u7a#5b: slice(80) <= account(100) => no finding"
$u5c = RunAnalyze (MkDoc @(
  (DW 'w5c-tab' 'google-adwords' 'Google Ads' @('campaign') @((Met 'Spend' 'google-adwords:cost_micros' 'micros')) @((DRow 'total' $null 'campaign' @{Spend=(Cell 120000000)}),(DRow 'data' 'A' 'campaign' @{Spend=(Cell 120000000)})) $null 'EUR'),
  (DW 'w5c-kpi' 'google-adwords' 'Google Ads' @() @((Met 'Spend' 'google-adwords:cost_micros' 'micros')) @((KRow @{Spend=(Cell 100000000)})) $null 'USD')
))
A (-not (HasFind $u5c.facts 'RECON_SLICE_OVER_ACCOUNT')) "u7a#5c: mixed currency (EUR slice vs USD KPI) => SameBasis false => skip"
$u5d = RunAnalyze (MkDoc @(
  (DW 'w5d-tab' 'google-adwords' 'Google Ads' @('campaign') @((Met 'Spend' 'google-adwords:cost_micros' 'micros')) @((DRow 'total' $null 'campaign' @{Spend=(Cell 120000000)}),(DRow 'data' 'A' 'campaign' @{Spend=(Cell 120000000)}))),
  (DW 'w5d-kpi' 'google-adwords' 'Google Ads' @() @((Met 'Spend' 'google-adwords:cost_micros')) @((KRow @{Spend=(Cell 100)})))
))
A (-not (HasFind $u5d.facts 'RECON_SLICE_OVER_ACCOUNT')) "u7a#5d: account KPI unit null => SameBasis false => skip"
$u5e = RunAnalyze (MkDoc @(
  (DW 'w5e-tab' 'google-adwords' 'Google Ads' @('campaign') @((Met 'CTR' 'google-adwords:ctr' 'fraction')) @((DRow 'total' $null 'campaign' @{CTR=(Cell 0.06)}),(DRow 'data' 'A' 'campaign' @{CTR=(Cell 0.06)}))),
  (DW 'w5e-kpi' 'google-adwords' 'Google Ads' @() @((Met 'CTR' 'google-adwords:ctr' 'fraction')) @((KRow @{CTR=(Cell 0.04)})))
))
A (-not (HasFind $u5e.facts 'RECON_SLICE_OVER_ACCOUNT')) "u7a#5e: ratio metric (CTR) not summable => #5 skip"
$u5g = RunAnalyze (MkDoc @( (DW 'w5g' 'google-adwords' 'Google Ads' @('campaign') @((Met 'Spend' 'google-adwords:cost_micros' 'micros')) @((DRow 'total' $null 'campaign' @{Spend=(Cell 120000000)}),(DRow 'data' 'A' 'campaign' @{Spend=(Cell 120000000)}))) ))
A (-not (HasFind $u5g.facts 'RECON_SLICE_OVER_ACCOUNT')) "u7a#5g: no zero-dim account KPI => no ceiling => skip"
$u5h = RunAnalyze (MkDoc @(
  (DW 'w5h-tab' 'google-adwords' 'Google Ads' @('campaign') @((Met 'Spend' 'google-adwords:cost_micros' 'micros')) @((DRow 'total' $null 'campaign' @{Spend=(Cell 120000000)}),(DRow 'data' 'A' 'campaign' @{Spend=(Cell 120000000)}))),
  (DW 'w5h-k1' 'google-adwords' 'Google Ads' @() @((Met 'Spend' 'google-adwords:cost_micros' 'micros')) @((KRow @{Spend=(Cell 100000000)}))),
  (DW 'w5h-k2' 'google-adwords' 'Google Ads' @() @((Met 'Spend' 'google-adwords:cost_micros' 'micros')) @((KRow @{Spend=(Cell 90000000)})))
))
A (-not (HasFind $u5h.facts 'RECON_SLICE_OVER_ACCOUNT')) "u7a#5h: two differing zero-dim account KPIs => ambiguous ceiling => skip"

Write-Host "== U6/U7a closer integration (dot-source the REAL closer; Test-Closer stays 119, untouched) =="
. "$PSScriptRoot\skill\scripts\Test-ReportNumbers.ps1" -DefineOnly
# 22. closer graceful-ignore: facts carrying `canonical` on every headline cell still trace displayCurrent
$r22 = RunAnalyze (MkDoc @( (DW 'wc' 'google-adwords' 'Google Ads' @() @((Met 'Cost' 'google-adwords:cost_micros' 'micros'),(Met 'Clicks' 'google-adwords:clicks')) @((KRow @{Cost=(Cell 10864723050);Clicks=(Cell 15627)}))) ))
$rep22 = "## Google Ads`n<!-- platform:google-adwords -->`nCost was `$10,864.72 on 15,627 clicks this period.`n"
$res22 = Invoke-Closer $rep22 $r22.facts
A ($res22.violations.Count -eq 0) "closer22: canonical ignored; displayCurrent traces (0 violations, got $($res22.violations.Count))"
# U7a-T-closer: the new findings ride the same byFid/force-surface mechanism (closer UNCHANGED).
function CloserHasT($res,$t){ [bool](@($res.violations | Where-Object { $_.type -eq $t }).Count) }
# #4 major force-surfaces and its numbers trace ONLY on the fid-anchored line
$repU4 = "## Google Ads`n<!-- platform:google-adwords -->`nCampaign rows summed to $($f4a.evidence.shownSum), above the $($f4a.evidence.total) account total. <!-- finding:$($f4a.fid) -->`n"
$resU4 = Invoke-Closer $repU4 $u4a.facts
A ($resU4.violations.Count -eq 0) "closer-u7a4: #4 major surfaces + numbers trace on its fid line (0 violations, got $($resU4.violations.Count): $(($resU4.violations | ForEach-Object { $_.type }) -join ','))"
$resU4b = Invoke-Closer ($repU4 -replace '<!--\s*finding:[^>]+?-->','') $u4a.facts
A (CloserHasT $resU4b 'unsurfaced-finding') "closer-u7a4: dropping the #4 major's fid => unsurfaced-finding (force-surface gate)"
# #3 ROAS recompute traces on the fid line and is NOT <mult>-exempt / NOT currency-mistyped
$repU3 = "## Google Ads`n<!-- platform:google-adwords -->`nReported ROAS was $($f3j.evidence.reported); the components imply $($f3j.evidence.recomputed). <!-- finding:$($f3j.fid) -->`n"
$resU3 = Invoke-Closer $repU3 $u3j.facts
A (-not (CloserHasT $resU3 'untraceable-number')) "closer-u7a3: ROAS recompute ($($f3j.evidence.recomputed)) traces on fid line (plain numeric, not <mult>-exempt)"

Write-Host ""
Write-Host ("RESULT: {0} passed, {1} failed" -f $pass,$fail) -ForegroundColor $(if($fail){'Red'}else{'Green'})
if($fail){ exit 1 }
