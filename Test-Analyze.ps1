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

Write-Host "== U8/D-period: Get-PeriodMeta (-DefineOnly) =="
function PmDR($measure){ [pscustomobject]@{ primary=[pscustomobject]@{ count=-1; measure=$measure; type='RELATIVE' } } }
function PmRes($startYm,$endYm,$aligned,$version){ if($null -eq $version){ $version=1 }; [pscustomobject]@{ resolverVersion=$version; rule='relative-last-complete'; anchorDate='2026-07-06'; primary=[pscustomobject]@{ measure='quarter'; count=-1; startDate='2026-04-01'; endDate='2026-06-30'; startYm=$startYm; endYm=$endYm; calendarAligned=$aligned } } }

# U8-A1: resolved input -> full triple copied
$pm1 = Get-PeriodMeta (PmDR 'quarter') (PmRes '2026-04' '2026-06' $true $null)
A ($pm1.measure -eq 'quarter') "A1 measure quarter"
A ($pm1.startYm -eq '2026-04' -and $pm1.endYm -eq '2026-06') "A1 startYm/endYm copied"
A ($pm1.calendarAligned -eq $true) "A1 calendarAligned true"
A ((@($pm1.Keys) -join ',') -eq 'measure,startYm,endYm,calendarAligned') "A1 exactly four keys"

# U8-A2: resolved $null (legacy doc) -> measure from wire, null triple
$pm2 = Get-PeriodMeta (PmDR 'quarter') $null
A ($pm2.measure -eq 'quarter' -and $null -eq $pm2.startYm -and $null -eq $pm2.endYm -and $pm2.calendarAligned -eq $false) "A2 legacy => measure from wire, null triple"

# U8-A3 (FP): malformed startYm -> null triple (regex guard, no partial copy)
foreach($bad in @('2026-4','garbage',$null,'2026-13','2026-00')){
  $pmB = Get-PeriodMeta (PmDR 'quarter') (PmRes $bad '2026-06' $true $null)
  A ($null -eq $pmB.startYm -and $null -eq $pmB.endYm -and $pmB.calendarAligned -eq $false) "A3 malformed startYm '$bad' => null triple"
}
# Unicode-digit fixture: '2026-04' rendered in Arabic-Indic digits must be REJECTED (guard is [0-9], not \d)
$ai = -join @([char]0x0662,[char]0x0660,[char]0x0662,[char]0x0666,'-',[char]0x0660,[char]0x0664)
$pmU = Get-PeriodMeta (PmDR 'quarter') (PmRes $ai '2026-06' $true $null)
A ($null -eq $pmU.startYm -and $pmU.calendarAligned -eq $false) "A3 Unicode-digit startYm => rejected (null triple)"
# and a Unicode-digit endYm with a valid startYm
$pmU2 = Get-PeriodMeta (PmDR 'quarter') (PmRes '2026-04' $ai $true $null)
A ($null -eq $pmU2.startYm -and $null -eq $pmU2.endYm) "A3 Unicode-digit endYm => rejected (both null)"

# U8-A4 (FP): unrecognized resolverVersion -> null triple (not trusted)
$pm4 = Get-PeriodMeta (PmDR 'quarter') (PmRes '2026-04' '2026-06' $true 99)
A ($null -eq $pm4.startYm -and $null -eq $pm4.endYm -and $pm4.calendarAligned -eq $false) "A4 resolverVersion 99 => null triple"

# U8-A5: dateRange $null -> measure 'custom', null triple
$pm5 = Get-PeriodMeta $null $null
A ($pm5.measure -eq 'custom' -and $null -eq $pm5.startYm -and $pm5.calendarAligned -eq $false) "A5 null dateRange => measure custom, null triple"

# meta.period is ALWAYS present (all branches return the 4-key dict)
A ((@($pm2.Keys) -join ',') -eq 'measure,startYm,endYm,calendarAligned') "A5 shape always 4 keys (legacy)"

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
function MkDoc($widgets,$measure,$resolved){
  if(-not $measure){ $measure='quarter' }
  $rep=[pscustomobject]@{ name='E2E Test'; client='E2E Client'; dateRange=[pscustomobject]@{ primary=[pscustomobject]@{ count=-1; measure=$measure; type='RELATIVE' } }; sections=@() }
  if($null -ne $resolved){ $rep | Add-Member -NotePropertyName dateRangeResolved -NotePropertyValue $resolved }   # U8: additive key ONLY when non-null (legacy fixtures stay byte-identical)
  [pscustomobject]@{
    meta=[pscustomobject]@{ schemaVersion=2; tool='Get-SwydoReport.ps1'; extractedAt='2026-07-06T02:23:57+03:00'; warnings=@(); providerFilter=@(); providerInventory=@(); clientId='C1'; unitBasis=$null }
    report=$rep
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
# 11. two widgets same (prov,metricId): U9/D2 rank precedence - a later zero-dim KPI (w-second) supersedes the
# doc-earlier table total (w-first). THIS IS THE U9 FLIP PIN (was document-order first-wins pre-U9).
$r11 = RunAnalyze (MkDoc @(
  (DW 'w-first' 'google-adwords' 'Google Ads' @('Campaign') @((Met 'Cost' 'google-adwords:cost_micros' 'micros')) @((DRow 'total' $null 'Campaign' @{Cost=(Cell 2000000000)}),(DRow 'data' 'A' 'Campaign' @{Cost=(Cell 2000000000)}))),
  (DW 'w-second' 'google-adwords' 'Google Ads' @() @((Met 'Cost' 'google-adwords:cost_micros' 'micros')) @((KRow @{Cost=(Cell 9999000000)})))
))
$h11 = Hl $r11.facts 'google-adwords' 'google-adwords:cost_micros'
A ($h11.canonical.sourceWidgetId -eq 'w-second') "e2e11/U9: rank-1 KPI (w-second) supersedes doc-earlier table total (w-first)"
A ($h11.canonical.scope -eq 'account' -and $h11.canonical.source -eq 'kpi-widget') "e2e11/U9: winner canonical scope=account source=kpi-widget"
A ($h11.canonical.supersededWidgetId -eq 'w-first') "e2e11/U9: canonical.supersededWidgetId names the displaced table (w-first)"
# 12/13. every headline cell carries the canonical struct; canonical.display==displayCurrent; no value/basisVersion/synthesizedFrom
A ($h9.canonical.display -eq $h9.displayCurrent) "e2e12: canonical.display == displayCurrent"
foreach($kk in 'display','sourceWidgetId','scope','period','source'){ A ($h9.canonical.PSObject.Properties.Name -contains $kk) "e2e12: canonical carries '$kk'" }
foreach($bad in 'value','basisVersion','synthesizedFrom'){ A (-not ($h9.canonical.PSObject.Properties.Name -contains $bad)) "e2e13: canonical has NO '$bad'" }
# 14. meta versions
A ($r9.facts.meta.canonicalVersion -eq 2 -and $r9.facts.meta.factsVersion -eq 1) "e2e14/U9: meta.canonicalVersion=2 (D6 global bump), factsVersion=1"
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

Write-Host "== U8/D-period: e2e (real script over a v2 doc) =="
function MkQtrResolved(){ [pscustomobject]@{ resolverVersion=1; rule='relative-last-complete'; anchorDate='2026-07-06'; primary=[pscustomobject]@{ measure='quarter'; count=-1; startDate='2026-04-01'; endDate='2026-06-30'; startYm='2026-04'; endYm='2026-06'; calendarAligned=$true } } }
$wKPI = @( (DW 'w-p' 'google-adwords' 'Google Ads' @() @((Met 'Cost' 'google-adwords:cost_micros' 'micros'),(Met 'Clicks' 'google-adwords:clicks')) @((KRow @{Cost=(Cell 10864723050);Clicks=(Cell 15627)}))) )

# U8-A6: doc WITH dateRangeResolved -> facts.meta.period == the 4-key resolved triple
$rA6 = RunAnalyze (MkDoc $wKPI 'quarter' (MkQtrResolved))
$per = $rA6.facts.meta.period
A ($null -ne $per) "A6 meta.period present"
A ($per.measure -eq 'quarter' -and $per.startYm -eq '2026-04' -and $per.endYm -eq '2026-06' -and $per.calendarAligned -eq $true) "A6 meta.period == resolved triple"
A ((@($per.PSObject.Properties.Name) -join ',') -eq 'measure,startYm,endYm,calendarAligned') "A6 meta.period key set exactly four"

# U8-A7 (FP): legacy doc (no dateRangeResolved) -> meta.period present, null triple, no GAP_WARNINGS, finding parity
$rA7 = RunAnalyze (MkDoc $wKPI)          # no resolved param => no dateRangeResolved key (legacy)
$perL = $rA7.facts.meta.period
A ($null -ne $perL -and $null -eq $perL.startYm -and $null -eq $perL.endYm -and $perL.calendarAligned -eq $false) "A7 legacy => meta.period present, null triple"
A (-not (HasFind $rA7.facts 'GAP_WARNINGS')) "A7 legacy => no GAP_WARNINGS from period"
A ((AllFind $rA7.facts).Count -eq (AllFind $rA6.facts).Count) "A7 zero-findings parity (resolved vs legacy same finding count)"

# U8-A8 (byte-stability): the human-facing period labels are byte-identical on BOTH fixtures
foreach($rr in @($rA6,$rA7)){
  A ($rr.facts.meta.currentPeriod -eq 'Q2 2026') "A8 currentPeriod 'Q2 2026' unchanged"
  A ($rr.facts.meta.previousPeriod -eq 'Q1 2026') "A8 previousPeriod 'Q1 2026' unchanged"
  A ($rr.facts.meta.periodConfidence -eq 'derived') "A8 periodConfidence 'derived' unchanged"
}
$hlA6 = Hl $rA6.facts 'google-adwords' 'google-adwords:cost_micros'
A ($hlA6.canonical.period -eq (Hl $rA7.facts 'google-adwords' 'google-adwords:cost_micros').canonical.period) "A8 canonical.period byte-identical resolved vs legacy"

# U8-A9 (closer pin): closer over facts carrying a populated meta.period stays clean (haystack unchanged)
$repA9 = "## Google Ads`n<!-- platform:google-adwords -->`nCost was `$10,864.72 on 15,627 clicks this period.`n"
$resA9 = Invoke-Closer $repA9 $rA6.facts
A ($resA9.violations.Count -eq 0) "A9 closer clean with populated meta.period ('2026-04' tokens do not become traceable numbers; got $($resA9.violations.Count))"

# U8-A10 (cross-derivation pin, D13): same anchor -> months and label agree
A ($per.startYm -eq '2026-04' -and $per.endYm -eq '2026-06' -and $rA6.facts.meta.currentPeriod -eq 'Q2 2026') "A10 months (2026-04..2026-06) and label (Q2 2026) agree on the same anchor"

Write-Host "== U9: headline rank precedence (zero-dim KPI beats doc-earlier table total) =="
# U9-T1 flip core (E1): table-then-KPI -> KPI wins; GAP_HEADLINE_SOURCE_CHANGED info + fid + id/count evidence.
$t1 = RunAnalyze (MkDoc @(
  (DW 'w1-tab' 'google-adwords' 'Google Ads' @('Campaign') @((Met 'Cost' 'google-adwords:cost_micros' 'micros')) @((DRow 'total' $null 'Campaign' @{Cost=(Cell 2000000000)}),(DRow 'data' 'A' 'Campaign' @{Cost=(Cell 2000000000)}))),
  (DW 'w1-kpi' 'google-adwords' 'Google Ads' @() @((Met 'Cost' 'google-adwords:cost_micros' 'micros')) @((KRow @{Cost=(Cell 9999000000)})))
))
$h1 = Hl $t1.facts 'google-adwords' 'google-adwords:cost_micros'
A ($h1.current -eq 9999000000) "U9-T1: headline current is the KPI's (9999000000)"
A ($h1.displayCurrent -eq (Format-Metric 'google-adwords:cost_micros' 'micros' 9999000000 'USD')) "U9-T1: displayCurrent is the KPI's"
$f1 = GetFind $t1.facts 'GAP_HEADLINE_SOURCE_CHANGED'
A ($null -ne $f1 -and $f1.severity -eq 'info' -and $f1.fid) "U9-T1: GAP_HEADLINE_SOURCE_CHANGED present, info, has fid"
A (@($f1.evidence.metrics) -contains 'google-adwords:cost_micros') "U9-T1: evidence.metrics contains the flipped metric id"
A (@($f1.evidence.supersededWidgets) -contains 'w1-tab') "U9-T1: evidence.supersededWidgets contains the table widget id"
A ($f1.evidence.count -eq '1') "U9-T1: evidence.count == '1'"

# U9-T2 no-flip byte guard (E2): KPI-then-table -> KPI wins at first encounter, byte-identical except D6 token.
$t2 = RunAnalyze (MkDoc @(
  (DW 'w2-kpi' 'google-adwords' 'Google Ads' @() @((Met 'Cost' 'google-adwords:cost_micros' 'micros')) @((KRow @{Cost=(Cell 9999000000)}))),
  (DW 'w2-tab' 'google-adwords' 'Google Ads' @('Campaign') @((Met 'Cost' 'google-adwords:cost_micros' 'micros')) @((DRow 'total' $null 'Campaign' @{Cost=(Cell 2000000000)}),(DRow 'data' 'A' 'Campaign' @{Cost=(Cell 2000000000)})))
))
$h2 = Hl $t2.facts 'google-adwords' 'google-adwords:cost_micros'
A ($h2.canonical.sourceWidgetId -eq 'w2-kpi' -and $h2.canonical.source -eq 'kpi-widget') "U9-T2: KPI-first wins at first encounter (no displacement)"
A ($t2.text -notmatch 'supersededWidgetId') "U9-T2: no supersededWidgetId anywhere in non-flip facts"
A (-not (HasFind $t2.facts 'GAP_HEADLINE_SOURCE_CHANGED')) "U9-T2: no precedence finding on non-flip"
A ($t2.facts.meta.canonicalVersion -eq 2) "U9-T2: canonicalVersion=2 even on non-flip (D6 global)"
A ($t2.text -match '"current":9999000000,') "U9-T2: legacy current field byte-pinned unchanged"
A ($t2.text -match [regex]::Escape('"displayCurrent":"$9,999.00"')) "U9-T2: legacy displayCurrent string byte-pinned unchanged"

# U9-T3 same-rank doc-order pins (E3)
$t3a = RunAnalyze (MkDoc @(
  (DW 'w3a-k1' 'google-adwords' 'Google Ads' @() @((Met 'Cost' 'google-adwords:cost_micros' 'micros')) @((KRow @{Cost=(Cell 100000000)}))),
  (DW 'w3a-k2' 'google-adwords' 'Google Ads' @() @((Met 'Cost' 'google-adwords:cost_micros' 'micros')) @((KRow @{Cost=(Cell 200000000)})))
))
A ((Hl $t3a.facts 'google-adwords' 'google-adwords:cost_micros').canonical.sourceWidgetId -eq 'w3a-k1') "U9-T3a: two KPIs => doc-first wins"
A (-not (HasFind $t3a.facts 'GAP_HEADLINE_SOURCE_CHANGED')) "U9-T3a: same-rank KPIs => no precedence finding"
$t3b = RunAnalyze (MkDoc @(
  (DW 'w3b-t1' 'google-adwords' 'Google Ads' @('Campaign') @((Met 'Cost' 'google-adwords:cost_micros' 'micros')) @((DRow 'total' $null 'Campaign' @{Cost=(Cell 300000000)}),(DRow 'data' 'A' 'Campaign' @{Cost=(Cell 300000000)}))),
  (DW 'w3b-t2' 'google-adwords' 'Google Ads' @('Device') @((Met 'Cost' 'google-adwords:cost_micros' 'micros')) @((DRow 'total' $null 'Device' @{Cost=(Cell 400000000)}),(DRow 'data' 'B' 'Device' @{Cost=(Cell 400000000)})))
))
A ((Hl $t3b.facts 'google-adwords' 'google-adwords:cost_micros').canonical.sourceWidgetId -eq 'w3b-t1') "U9-T3b: two table totals => doc-first wins"
A (-not (HasFind $t3b.facts 'GAP_HEADLINE_SOURCE_CHANGED')) "U9-T3b: same-rank totals => no precedence finding"

# U9-T4 single displacement (E7): table, KPI-1, KPI-2 -> KPI-1 wins; second cannot re-displace; one metric entry.
$t4 = RunAnalyze (MkDoc @(
  (DW 'w4-tab' 'google-adwords' 'Google Ads' @('Campaign') @((Met 'Cost' 'google-adwords:cost_micros' 'micros')) @((DRow 'total' $null 'Campaign' @{Cost=(Cell 2000000000)}),(DRow 'data' 'A' 'Campaign' @{Cost=(Cell 2000000000)}))),
  (DW 'w4-k1' 'google-adwords' 'Google Ads' @() @((Met 'Cost' 'google-adwords:cost_micros' 'micros')) @((KRow @{Cost=(Cell 5000000000)}))),
  (DW 'w4-k2' 'google-adwords' 'Google Ads' @() @((Met 'Cost' 'google-adwords:cost_micros' 'micros')) @((KRow @{Cost=(Cell 6000000000)})))
))
$h4 = Hl $t4.facts 'google-adwords' 'google-adwords:cost_micros'
A ($h4.canonical.sourceWidgetId -eq 'w4-k1') "U9-T4: first KPI (w4-k1) wins; second KPI cannot re-displace"
A ($h4.canonical.supersededWidgetId -eq 'w4-tab') "U9-T4: supersededWidgetId still names the rank-2 table, never a KPI"
$f4 = GetFind $t4.facts 'GAP_HEADLINE_SOURCE_CHANGED'
A (@($f4.evidence.metrics).Count -eq 1 -and $f4.evidence.count -eq '1') "U9-T4: exactly one displacement recorded (no chaining)"

# U9-T5 blended never displaces (E4)
$t5 = RunAnalyze (MkDoc @(
  (DW 'w5-tab' 'google-adwords' 'Google Ads' @('Campaign') @((Met 'Cost' 'google-adwords:cost_micros' 'micros')) @((DRow 'total' $null 'Campaign' @{Cost=(Cell 2000000000)}),(DRow 'data' 'A' 'Campaign' @{Cost=(Cell 2000000000)}))),
  (DW 'w5-blend' $null $null @() @((Met 'Cost' 'google-adwords:cost_micros' 'micros')) @((KRow @{Cost=(Cell 9999000000)})) @([pscustomobject]@{id='google-adwords';name='Google Ads'},[pscustomobject]@{id='provb';name='Provider B'}))
))
A ((Hl $t5.facts 'google-adwords' 'google-adwords:cost_micros').canonical.sourceWidgetId -eq 'w5-tab') "U9-T5: blended zero-dim widget never displaces (table stays)"
A (-not (HasFind $t5.facts 'GAP_HEADLINE_SOURCE_CHANGED')) "U9-T5: blended non-displacement => no finding"
A ($t5.text -notmatch 'w5-blend') "U9-T5: blended widget absent from any canonical.sourceWidgetId"

# U9-T6 (D9): #5 independence - the u5a layout (table 120 > KPI 100) flips headline to the KPI, #5 still fires,
# and the headline winner + #5's ceiling now cite the same figure.
$h6 = Hl $u5a.facts 'google-adwords' 'google-adwords:cost_micros'
A ($h6.canonical.sourceWidgetId -eq 'w5a-kpi' -and $h6.canonical.source -eq 'kpi-widget') "U9-T6: u5a headline flips to the 100 KPI (w5a-kpi)"
A (HasFind $u5a.facts 'RECON_SLICE_OVER_ACCOUNT') "U9-T6: #5 still fires (re-derived from dataWidgets, flip-independent)"
A ($h6.displayCurrent -eq $f5a.evidence.account) "U9-T6: headline winner and #5 evidence.account now cite the same figure"
A (HasFind $u5a.facts 'GAP_HEADLINE_SOURCE_CHANGED') "U9-T6: the u5a flip is disclosed"

# U9-T7 key-order stability: only the MIDDLE of three metrics flips -> headline key order unchanged.
$t7 = RunAnalyze (MkDoc @(
  (DW 'w7-tab' 'google-adwords' 'Google Ads' @('Campaign') @((Met 'Clicks' 'google-adwords:clicks'),(Met 'Impr' 'google-adwords:impressions'),(Met 'Conv' 'google-adwords:conversions')) @((DRow 'total' $null 'Campaign' @{Clicks=(Cell 10);Impr=(Cell 100);Conv=(Cell 5)}),(DRow 'data' 'A' 'Campaign' @{Clicks=(Cell 10);Impr=(Cell 100);Conv=(Cell 5)}))),
  (DW 'w7-kpi' 'google-adwords' 'Google Ads' @() @((Met 'Impr' 'google-adwords:impressions')) @((KRow @{Impr=(Cell 999)})))
))
$pi_c = $t7.text.IndexOf('google-adwords:clicks'); $pi_i = $t7.text.IndexOf('google-adwords:impressions'); $pi_v = $t7.text.IndexOf('google-adwords:conversions')
A ($pi_c -ge 0 -and $pi_c -lt $pi_i -and $pi_i -lt $pi_v) "U9-T7: headline key order stable across in-place flip (clicks<impressions<conversions)"
A ((Hl $t7.facts 'google-adwords' 'google-adwords:impressions').canonical.sourceWidgetId -eq 'w7-kpi') "U9-T7: middle metric flipped to the KPI"

# U9-T8 rollup + cap (FP-2): 25 table-won metrics displaced by a later 25-metric KPI -> ONE finding, count 25, cap 20.
$mets8=@(); $mv8=@{}; foreach($i in 1..25){ $mets8 += (Met "M$i" "google-adwords:m$i"); $mv8["M$i"]=(Cell (1000+$i)) }
$t8 = RunAnalyze (MkDoc @(
  (DW 'w8-tab' 'google-adwords' 'Google Ads' @('Campaign') $mets8 @((DRow 'total' $null 'Campaign' $mv8),(DRow 'data' 'A' 'Campaign' $mv8))),
  (DW 'w8-kpi' 'google-adwords' 'Google Ads' @() $mets8 @((KRow $mv8)))
))
$f8=@((AllFind $t8.facts) | Where-Object { $_.ruleId -eq 'GAP_HEADLINE_SOURCE_CHANGED' })
A ($f8.Count -eq 1) "U9-T8: exactly ONE GAP_HEADLINE_SOURCE_CHANGED per provider (rollup)"
A ($f8[0].evidence.count -eq '25') "U9-T8: evidence.count == '25' (full count)"
A (@($f8[0].evidence.metrics).Count -eq 21 -and ($f8[0].evidence.metrics[-1] -match '^\+5 more$')) "U9-T8: metrics capped at 20 + '+5 more' sentinel"

# U9-T9 comparison recompute (E10): displaced compare-bearing cell + compareless KPI -> hasComparison false; control stays true.
$t9 = RunAnalyze (MkDoc @(
  (DW 'w9-tab' 'google-adwords' 'Google Ads' @('Campaign') @((Met 'Cost' 'google-adwords:cost_micros' 'micros')) @((DRow 'total' $null 'Campaign' @{Cost=(Cell 2000000000 1000000000)}),(DRow 'data' 'A' 'Campaign' @{Cost=(Cell 2000000000 1000000000)}))),
  (DW 'w9-kpi' 'google-adwords' 'Google Ads' @() @((Met 'Cost' 'google-adwords:cost_micros' 'micros')) @((KRow @{Cost=(Cell 5000000000)})))
))
A ($t9.facts.meta.hasComparison -eq $false) "U9-T9: displaced compare cell + compareless KPI => meta.hasComparison false (D7)"
A (@($t9.facts.meta.comparisonCaveats).Count -eq 0) "U9-T9: seasonality caveat drops when comparison drops"
$t9b = RunAnalyze (MkDoc @(
  (DW 'w9b-tab' 'google-adwords' 'Google Ads' @('Campaign') @((Met 'Cost' 'google-adwords:cost_micros' 'micros'),(Met 'Clicks' 'google-adwords:clicks')) @((DRow 'total' $null 'Campaign' @{Cost=(Cell 2000000000 1000000000);Clicks=(Cell 50 40)}),(DRow 'data' 'A' 'Campaign' @{Cost=(Cell 2000000000 1000000000);Clicks=(Cell 50 40)}))),
  (DW 'w9b-kpi' 'google-adwords' 'Google Ads' @() @((Met 'Cost' 'google-adwords:cost_micros' 'micros')) @((KRow @{Cost=(Cell 5000000000)})))
))
A ($t9b.facts.meta.hasComparison -eq $true) "U9-T9: surviving compare-bearing cell (Clicks) keeps meta.hasComparison true"

# U9-T10 winner-follows-facts (D8/E9): flip changes WIN->LOSS; null-unit KPI variant recomputes GAP_UNIT_UNCONFIRMED.
$t10 = RunAnalyze (MkDoc @(
  (DW 'w10-tab' 'google-adwords' 'Google Ads' @('Campaign') @((Met 'Clicks' 'google-adwords:clicks')) @((DRow 'total' $null 'Campaign' @{Clicks=(Cell 200 100)}),(DRow 'data' 'A' 'Campaign' @{Clicks=(Cell 200 100)}))),
  (DW 'w10-kpi' 'google-adwords' 'Google Ads' @() @((Met 'Clicks' 'google-adwords:clicks')) @((KRow @{Clicks=(Cell 50 100)})))
))
A ((HasFind $t10.facts 'LOSS') -and -not (HasFind $t10.facts 'WIN')) "U9-T10: WIN/LOSS follow the KPI winner (LOSS from KPI, not WIN from displaced table)"
$t10b = RunAnalyze (MkDoc @(
  (DW 'w10b-tab' 'google-adwords' 'Google Ads' @('Campaign') @((Met 'Cost' 'google-adwords:cost_micros' 'micros')) @((DRow 'total' $null 'Campaign' @{Cost=(Cell 2000000000)}),(DRow 'data' 'A' 'Campaign' @{Cost=(Cell 2000000000)}))),
  (DW 'w10b-kpi' 'google-adwords' 'Google Ads' @() @((Met 'Cost' 'google-adwords:cost_micros')) @((KRow @{Cost=(Cell 500000000)})))
))
$g10b = GetFind $t10b.facts 'GAP_UNIT_UNCONFIRMED'; $h10b = Hl $t10b.facts 'google-adwords' 'google-adwords:cost_micros'
A ($h10b.canonical.sourceWidgetId -eq 'w10b-kpi') "U9-T10b: null-unit money KPI displaced the micros table (winner-follows-facts)"
A ($null -ne $g10b -and $g10b.statement -match [regex]::Escape([string]$h10b.displayCurrent)) "U9-T10b: GAP_UNIT_UNCONFIRMED recomputes from the KPI raw display"

# U9-T11 closer graceful-ignore + no-value evidence (FP-3)
$rep11 = "## Google Ads`n<!-- platform:google-adwords -->`nCost was $($h1.displayCurrent) this period.`n"
$res11 = Invoke-Closer $rep11 $t1.facts
A ($res11.violations.Count -eq 0) "U9-T11: closer clean over flip facts, finding not cited (info never force-surfaces; got $($res11.violations.Count))"
A ($f1.statement -notmatch '[\$%]') "U9-T11: precedence statement carries no formatted metric value (id-only)"

# U9-T12 gap invariance (D9)
$t12 = RunAnalyze (MkDoc @(
  (DW 'w12-tab' 'google-adwords' 'Google Ads' @('Campaign') @((Met 'Cost' 'google-adwords:cost_micros' 'micros')) @((DRow 'total' $null 'Campaign' @{Cost=(Cell 2000000000)}),(DRow 'data' 'A' 'Campaign' @{Cost=(Cell 2000000000)}))),
  (DW 'w12-kpi' 'google-adwords' 'Google Ads' @() @((Met 'Cost' 'google-adwords:cost_micros' 'micros')) @((KRow @{Cost=(Cell 5000000000)}))),
  (DW 'w12-notot' 'google-adwords' 'Google Ads' @('Campaign') @((Met 'Clicks' 'google-adwords:clicks')) @((DRow 'data' 'A' 'Campaign' @{Clicks=(Cell 10)}),(DRow 'data' 'B' 'Campaign' @{Clicks=(Cell 20)})))
))
$g12 = GetFind $t12.facts 'GAP_NO_ACCOUNT_TOTAL'
A ($null -ne $g12 -and (@($g12.evidence.metrics) -contains 'google-adwords:clicks')) "U9-T12: uncovered metric (clicks, no total) still gets GAP_NO_ACCOUNT_TOTAL"
A (-not (@($g12.evidence.metrics) -contains 'google-adwords:cost_micros')) "U9-T12: flipped metric (cost) NOT in gap (headline key exists)"
A (HasFind $t12.facts 'GAP_HEADLINE_SOURCE_CHANGED') "U9-T12: cost flip disclosed"

# U9-T13 null-dimensions KPI displaces (E5): dimensions literally $null (not @()) is treated as zero-dim.
$w13tab = (DW 'w13-tab' 'google-adwords' 'Google Ads' @('Campaign') @((Met 'Cost' 'google-adwords:cost_micros' 'micros')) @((DRow 'total' $null 'Campaign' @{Cost=(Cell 2000000000)}),(DRow 'data' 'A' 'Campaign' @{Cost=(Cell 2000000000)})))
$w13kpi = [pscustomobject]@{ kind='data'; id='w13-kpi'; providers=@([pscustomobject]@{id='google-adwords';name='Google Ads'}); currencyCode='USD'; dimensions=$null; metrics=@((Met 'Cost' 'google-adwords:cost_micros' 'micros')); rows=@((KRow @{Cost=(Cell 5000000000)})) }
$t13 = RunAnalyze (MkDoc @($w13tab,$w13kpi))
$h13 = Hl $t13.facts 'google-adwords' 'google-adwords:cost_micros'
A ($h13.canonical.sourceWidgetId -eq 'w13-kpi' -and $h13.canonical.source -eq 'kpi-widget') "U9-T13: null-dimensions KPI treated as zero-dim => displaces the table"

# U9-T14 non-numeric KPI cell does not displace (E6): echo-object current fails the scalar guard.
$t14 = RunAnalyze (MkDoc @(
  (DW 'w14-tab' 'google-adwords' 'Google Ads' @('Campaign') @((Met 'Cost' 'google-adwords:cost_micros' 'micros')) @((DRow 'total' $null 'Campaign' @{Cost=(Cell 2000000000)}),(DRow 'data' 'A' 'Campaign' @{Cost=(Cell 2000000000)}))),
  (DW 'w14-kpi' 'google-adwords' 'Google Ads' @() @((Met 'Cost' 'google-adwords:cost_micros' 'micros')) @((KRow @{Cost=(Cell ([pscustomobject]@{lo=1;hi=2}))})))
))
A ((Hl $t14.facts 'google-adwords' 'google-adwords:cost_micros').canonical.sourceWidgetId -eq 'w14-tab') "U9-T14: echo-object KPI cell fails scalar guard => table stays"
A (-not (HasFind $t14.facts 'GAP_HEADLINE_SOURCE_CHANGED')) "U9-T14: no displacement => no finding"

# U9-T15 DISC unchanged (D9): two disagreeing KPIs after a table -> flip to doc-first KPI + DISC_CROSS_WIDGET major.
$t15 = RunAnalyze (MkDoc @(
  (DW 'w15-tab' 'google-adwords' 'Google Ads' @('Campaign') @((Met 'Cost' 'google-adwords:cost_micros' 'micros')) @((DRow 'total' $null 'Campaign' @{Cost=(Cell 2000000000)}),(DRow 'data' 'A' 'Campaign' @{Cost=(Cell 2000000000)}))),
  (DW 'w15-k1' 'google-adwords' 'Google Ads' @() @((Met 'Cost' 'google-adwords:cost_micros' 'micros')) @((KRow @{Cost=(Cell 5000000000)}))),
  (DW 'w15-k2' 'google-adwords' 'Google Ads' @() @((Met 'Cost' 'google-adwords:cost_micros' 'micros')) @((KRow @{Cost=(Cell 8000000000)})))
))
A ((Hl $t15.facts 'google-adwords' 'google-adwords:cost_micros').canonical.sourceWidgetId -eq 'w15-k1') "U9-T15: flip to doc-first KPI (w15-k1); second KPI cannot re-displace"
A (HasFind $t15.facts 'DISC_CROSS_WIDGET') "U9-T15: DISC_CROSS_WIDGET still fires on the disagreeing KPI pair (headline-independent)"

# U9-T16 displacement-guard null-check (AMENDMENTS): a metric id colliding with the boolean 'hasComparison'
# headline key must NOT be displaced/corrupted - it degrades to exact pre-U9 first-wins.
$t16 = RunAnalyze (MkDoc @(
  (DW 'w16-a' 'google-adwords' 'Google Ads' @() @((Met 'Clicks' 'google-adwords:clicks')) @((KRow @{Clicks=(Cell 200 100)}))),
  (DW 'w16-b' 'google-adwords' 'Google Ads' @() @((Met 'HC' 'hasComparison')) @((KRow @{HC=(Cell 5)})))
))
A ($t16.facts.meta.hasComparison -eq $true) "U9-T16: 'hasComparison'-colliding metric id degrades to first-wins; boolean key uncorrupted"
A (-not (HasFind $t16.facts 'GAP_HEADLINE_SOURCE_CHANGED')) "U9-T16: collision with the boolean key does not register as a displacement"

Write-Host "== U10: rule (a)/(b) pure predicates (-DefineOnly) =="
function BF($fs,$id){ @($fs | Where-Object { $_.ruleId -eq $id })[0] }
# 1. Test-ValueMetricId TRUE (incl. widened value_per_ catching value_per_all_conversions; return_on_ad_spend)
foreach($id in 'google-adwords:conversions_value','google-adwords:all_conversions_value','google-adwords:value_per_conversion','google-adwords:value_per_all_conversions','facebook-ads:actionValues::purchase','x:purchase_roas','shopify:revenue','x:websitePurchaseRoas','bing-ads:return_on_ad_spend'){ A (Test-ValueMetricId $id) "U10-1 Test-ValueMetricId TRUE: $id" }
# 2. Test-ValueMetricId FALSE (incl. target_-guard: target_roas/target_cpa must NOT suppress)
foreach($id in 'google-adwords:cost_micros','google-adwords:conversions','facebook-ads:actions::lead','facebook-ads:costPerActionType::lead','google-adwords:active_view_non_viewable_impression_rate','google-adwords:search_lost_is_budget','google-analytics-4:eventValue','google-adwords:target_roas','google-adwords:target_cpa'){ A (-not (Test-ValueMetricId $id)) "U10-2 Test-ValueMetricId FALSE: $id" }
# 3. Test-RankableCostWidget TRUE
$rk1 = Wgt 'google-adwords' 'Google Ads' 'Campaign' @((Met 'Cost' 'google-adwords:cost_micros' 'micros'),(Met 'Conv' 'google-adwords:conversions')) @((Rw 'total' $null 'Campaign' @{Cost=@(1000,$null);Conv=@(100,$null)}),(Rw 'data' 'A' 'Campaign' @{Cost=@(600,$null);Conv=@(60,$null)}),(Rw 'data' 'B' 'Campaign' @{Cost=@(400,$null);Conv=@(40,$null)}))
A (Test-RankableCostWidget $rk1) "U10-3 rankable: campaign + cost + conversions (implicit pair)"
$rk2 = Wgt 'google-adwords' 'Google Ads' 'Campaign' @((Met 'CPA' 'google-adwords:cost_per_conversion')) @((Rw 'total' $null 'Campaign' @{CPA=@(10,$null)}),(Rw 'data' 'A' 'Campaign' @{CPA=@(9,$null)}),(Rw 'data' 'B' 'Campaign' @{CPA=@(11,$null)}))
A (Test-RankableCostWidget $rk2) "U10-3 rankable: campaign + explicit cost_per_conversion"
$rk3 = Wgt 'facebook-ads' 'Facebook Ads' 'Campaign' @((Met 'Spend' 'facebook-ads:spend' 'micros'),(Met 'Leads' 'facebook-ads:actions::lead')) @((Rw 'total' $null 'Campaign' @{Spend=@(1000,$null);Leads=@(100,$null)}),(Rw 'data' 'A' 'Campaign' @{Spend=@(600,$null);Leads=@(60,$null)}),(Rw 'data' 'B' 'Campaign' @{Spend=@(400,$null);Leads=@(40,$null)}))
A (Test-RankableCostWidget $rk3) "U10-3 rankable: campaign + spend + actions::lead (FB pair)"
# 4. Test-RankableCostWidget FALSE
$nr1 = [pscustomobject]@{ dimensions=@(); metrics=@((Met 'CPA' 'google-adwords:cost_per_conversion')); rows=@((Rw 'data' $null 'x' @{CPA=@(10,$null)})) }
A (-not (Test-RankableCostWidget $nr1)) "U10-4 not rankable: zero-dim KPI"
$nr2 = Wgt 'google-adwords' 'Google Ads' 'Month' @((Met 'CPA' 'google-adwords:cost_per_conversion')) @((Rw 'total' $null 'Month' @{CPA=@(10,$null)}),(Rw 'data' '2026-04' 'Month' @{CPA=@(9,$null)}),(Rw 'data' '2026-05' 'Month' @{CPA=@(11,$null)}))
A (-not (Test-RankableCostWidget $nr2)) "U10-4 not rankable: Month time dim (E6)"
$nr3 = Wgt 'google-adwords' 'Google Ads' 'Campaign' @((Met 'Cost' 'google-adwords:cost_micros' 'micros')) @((Rw 'total' $null 'Campaign' @{Cost=@(1000,$null)}),(Rw 'data' 'A' 'Campaign' @{Cost=@(600,$null)}),(Rw 'data' 'B' 'Campaign' @{Cost=@(400,$null)}))
A (-not (Test-RankableCostWidget $nr3)) "U10-4 not rankable: cost only, no outcome (E8)"
$nr4 = Wgt 'google-adwords' 'Google Ads' 'Campaign' @((Met 'Conv' 'google-adwords:conversions')) @((Rw 'total' $null 'Campaign' @{Conv=@(100,$null)}),(Rw 'data' 'A' 'Campaign' @{Conv=@(60,$null)}),(Rw 'data' 'B' 'Campaign' @{Conv=@(40,$null)}))
A (-not (Test-RankableCostWidget $nr4)) "U10-4 not rankable: outcome only, no cost (E8)"
$nr5 = Wgt 'google-adwords' 'Google Ads' 'Campaign' @((Met 'Cost' 'google-adwords:cost_micros' 'micros'),(Met 'Conv' 'google-adwords:conversions')) @((Rw 'total' $null 'Campaign' @{Cost=@(1000,$null);Conv=@(100,$null)}),(Rw 'data' 'A' 'Campaign' @{Cost=@(1000,$null);Conv=@(100,$null)}))
A (-not (Test-RankableCostWidget $nr5)) "U10-4 not rankable: single detail row (<2)"
$nr6 = Wgt 'facebook-ads' 'Facebook Ads' 'Campaign' @((Met 'CPC' 'facebook-ads:costPerActionType::link_click'),(Met 'Clicks' 'facebook-ads:actions::link_click')) @((Rw 'total' $null 'Campaign' @{CPC=@(2,$null);Clicks=@(100,$null)}),(Rw 'data' 'A' 'Campaign' @{CPC=@(2,$null);Clicks=@(60,$null)}),(Rw 'data' 'B' 'Campaign' @{CPC=@(2,$null);Clicks=@(40,$null)}))
A (-not (Test-RankableCostWidget $nr6)) "U10-4 not rankable: only link_click cost-per (click denominator, not an outcome)"
# 5. Test-PMaxLabel TRUE
foreach($l in 'inS - PMax - Quincy General','Performance Max - Brand','pmax_general','P Max Launch','P.Max 2026'){ A (Test-PMaxLabel $l) "U10-5 PMax TRUE: $l" }
# 6. Test-PMaxLabel FALSE
foreach($l in 'TopMax Deals','CompMax','Search - Auto Loans','High Performance Maximizer','Performance Maximization Campaign'){ A (-not (Test-PMaxLabel $l)) "U10-6 PMax FALSE: $l" }
A (-not (Test-PMaxLabel '')) "U10-6 PMax FALSE: empty"
A (-not (Test-PMaxLabel $null)) "U10-6 PMax FALSE: null"
# 7. Get-BrandTokens
$bt1 = Get-BrandTokens 'Quincy Credit Union (QCU)'
A ($bt1.phrase -eq 'quincy credit union' -and (@($bt1.abbr) -contains 'qcu') -and $bt1.lead -eq 'quincy') "U10-7 tokens QCU: phrase/abbr/lead"
$bt2 = Get-BrandTokens 'First National Bank'
A ($bt2.lead -eq 'first' -and @($bt2.abbr).Count -eq 0 -and $bt2.phrase -eq 'first national bank') "U10-7 tokens First National Bank: lead first, no abbr"
$bt3 = Get-BrandTokens $null; $bt4 = Get-BrandTokens ''
A ($null -eq $bt3.phrase -and @($bt3.abbr).Count -eq 0 -and $null -eq $bt3.lead) "U10-7 tokens null => empty shape (no throw)"
A ($null -eq $bt4.phrase -and $null -eq $bt4.lead) "U10-7 tokens '' => empty shape"
$bt5 = Get-BrandTokens 'Acme'
A ($null -eq $bt5.phrase -and $bt5.lead -eq 'acme') "U10-7 tokens single-token Acme: no phrase, lead acme"
# 8. Test-BrandLabel TRUE
A (Test-BrandLabel 'Quincy Credit Union - Search' $bt1) "U10-8 brand TRUE: full client phrase (S3)"
A (Test-BrandLabel 'Brand - Exact' $null) "U10-8 brand TRUE: 'Brand' self-declared (S2)"
A (Test-BrandLabel 'Branded Search' $null) "U10-8 brand TRUE: 'Branded' (S2)"
# 9. Test-BrandLabel FALSE (F1 hyphen/space, F10, F3 abbr-never-fires, F4 lead-never-fires, S3 boundary)
A (-not (Test-BrandLabel 'Brand New Auto Loans' $null)) "U10-9 brand FALSE: 'Brand New' idiom (F1)"
A (-not (Test-BrandLabel 'Brand-New Auto Loans Sale' $null)) "U10-9 brand FALSE: 'Brand-New' hyphenated (F1 lookahead fix)"
A (-not (Test-BrandLabel 'Rebranding Campaign' $null)) "U10-9 brand FALSE: 'Rebranding' word boundary (F10)"
A (-not (Test-BrandLabel 'QCU | Mortgages' $bt1)) "U10-9 brand FALSE: abbr never fires (F3)"
A (-not (Test-BrandLabel 'First Time Buyer Promo' $bt2)) "U10-9 brand FALSE: lead token never fires (F4)"
$btMetro = Get-BrandTokens 'Metro Bank'
A (-not (Test-BrandLabel 'Metro Bankers Golf Promo' $btMetro)) "U10-9 brand FALSE: 'Metro Bankers Golf Promo' vs 'Metro Bank' (S3 token boundary)"
A (Test-BrandLabel 'Metro Bank - Q2' $btMetro) "U10-9 brand TRUE control: 'Metro Bank - Q2' matches phrase"
# 10. Get-MatchedBrandToken (annotation-only)
A ((Get-MatchedBrandToken 'inS - PMax - Quincy General' $bt1) -eq 'quincy') "U10-10 matched: lead 'quincy'"
A ((Get-MatchedBrandToken 'General QCU - Awareness Video' $bt1) -eq 'qcu') "U10-10 matched: abbr 'qcu'"
A ($null -eq (Get-MatchedBrandToken 'Auto Loans' $bt1)) "U10-10 matched: none => null"

Write-Host "== U10: rule (b) Get-BreakdownFindings fixtures (-DefineOnly) =="
# 11. PMax row at 40% => ONE ANOM_BRAND_BASELINE info; evidence byte-equal to Format-Metric
$b11 = Wgt 'google-adwords' 'Google Ads' 'Campaign' @((Met 'Conv' 'google-adwords:conversions')) @((Rw 'total' $null 'Campaign' @{Conv=@(100,$null)}),(Rw 'data' 'inS - PMax - Alpha' 'Campaign' @{Conv=@(40,$null)}),(Rw 'data' 'Search Beta' 'Campaign' @{Conv=@(60,$null)}))
$f11 = @(Get-BreakdownFindings $b11 'Some Client')
$bb11 = BF $f11 'ANOM_BRAND_BASELINE'
A (@($f11 | Where-Object { $_.ruleId -eq 'ANOM_BRAND_BASELINE' }).Count -eq 1 -and $bb11.severity -eq 'info') "U10-11 PMax 40% => ONE ANOM_BRAND_BASELINE (info)"
A ($bb11.evidence.share -eq '40%' -and $bb11.evidence.matchedTotal -eq (Format-Metric 'google-adwords:conversions' $null 40 'USD') -and $bb11.evidence.total -eq (Format-Metric 'google-adwords:conversions' $null 100 'USD')) "U10-11 evidence share/matchedTotal/total byte-equal to Format-Metric"
# 12. two PMax rows 15%+13% combined 28% => fires once, both labels quoted (combined-set semantics)
$b12 = Wgt 'google-adwords' 'Google Ads' 'Campaign' @((Met 'Conv' 'google-adwords:conversions')) @((Rw 'total' $null 'Campaign' @{Conv=@(100,$null)}),(Rw 'data' 'PMax - One' 'Campaign' @{Conv=@(15,$null)}),(Rw 'data' 'PMax - Two' 'Campaign' @{Conv=@(13,$null)}),(Rw 'data' 'Search' 'Campaign' @{Conv=@(72,$null)}))
$f12 = @(Get-BreakdownFindings $b12 $null); $bb12 = BF $f12 'ANOM_BRAND_BASELINE'
A (@($f12 | Where-Object { $_.ruleId -eq 'ANOM_BRAND_BASELINE' }).Count -eq 1 -and $bb12.evidence.share -eq '28%') "U10-12 two PMax rows combined 28% => fires once, rolled up"
A ($bb12.statement -match "PMax - One" -and $bb12.statement -match "PMax - Two") "U10-12 both matched labels quoted (D7 combined-set)"
# 13. PMax row at 10% => silent (F6)
$b13 = Wgt 'google-adwords' 'Google Ads' 'Campaign' @((Met 'Conv' 'google-adwords:conversions')) @((Rw 'total' $null 'Campaign' @{Conv=@(100,$null)}),(Rw 'data' 'PMax - Low' 'Campaign' @{Conv=@(10,$null)}),(Rw 'data' 'Search' 'Campaign' @{Conv=@(90,$null)}))
A (-not (HasRule (Get-BreakdownFindings $b13 $null) 'ANOM_BRAND_BASELINE')) "U10-13 PMax 10% => silent (F6)"
# 14. 'Brand New Auto Loans' dominant => silent (F1)
$b14 = Wgt 'google-adwords' 'Google Ads' 'Campaign' @((Met 'Conv' 'google-adwords:conversions')) @((Rw 'total' $null 'Campaign' @{Conv=@(100,$null)}),(Rw 'data' 'Brand New Auto Loans' 'Campaign' @{Conv=@(80,$null)}),(Rw 'data' 'Search' 'Campaign' @{Conv=@(20,$null)}))
A (-not (HasRule (Get-BreakdownFindings $b14 $null) 'ANOM_BRAND_BASELINE')) "U10-14 'Brand New' dominant => silent (F1)"
$b14b = Wgt 'google-adwords' 'Google Ads' 'Campaign' @((Met 'Conv' 'google-adwords:conversions')) @((Rw 'total' $null 'Campaign' @{Conv=@(100,$null)}),(Rw 'data' 'Brand-New Auto Loans Sale' 'Campaign' @{Conv=@(80,$null)}),(Rw 'data' 'Search' 'Campaign' @{Conv=@(20,$null)}))
A (-not (HasRule (Get-BreakdownFindings $b14b $null) 'ANOM_BRAND_BASELINE')) "U10-14 'Brand-New' hyphenated dominant => silent (F1 lookahead)"
# 15. convention-prefix ('QCU | ...') everywhere, QCU client => silent (F3)
$b15 = Wgt 'google-adwords' 'Google Ads' 'Campaign' @((Met 'Conv' 'google-adwords:conversions')) @((Rw 'total' $null 'Campaign' @{Conv=@(100,$null)}),(Rw 'data' 'QCU | Auto Loans' 'Campaign' @{Conv=@(60,$null)}),(Rw 'data' 'QCU | Mortgages' 'Campaign' @{Conv=@(40,$null)}))
A (-not (HasRule (Get-BreakdownFindings $b15 'Quincy Credit Union (QCU)') 'ANOM_BRAND_BASELINE')) "U10-15 QCU-prefix everywhere => silent (F3 abbr never fires)"
# 16. 'Quincy Credit Union - Brand' dominant with client => fires with evidence.brandToken
$b16 = Wgt 'google-adwords' 'Google Ads' 'Campaign' @((Met 'Conv' 'google-adwords:conversions')) @((Rw 'total' $null 'Campaign' @{Conv=@(100,$null)}),(Rw 'data' 'Quincy Credit Union - Brand' 'Campaign' @{Conv=@(60,$null)}),(Rw 'data' 'Search' 'Campaign' @{Conv=@(40,$null)}))
$bb16 = BF @(Get-BreakdownFindings $b16 'Quincy Credit Union (QCU)') 'ANOM_BRAND_BASELINE'
A ($null -ne $bb16 -and $bb16.evidence.brandToken -eq 'quincy') "U10-16 full-client-phrase row fires with evidence.brandToken 'quincy'"
# 17. matched sum 12 of 20 (60%, sum<30) => confidence low (F11)
$b17 = Wgt 'google-adwords' 'Google Ads' 'Campaign' @((Met 'Conv' 'google-adwords:conversions')) @((Rw 'total' $null 'Campaign' @{Conv=@(20,$null)}),(Rw 'data' 'PMax - Small' 'Campaign' @{Conv=@(12,$null)}),(Rw 'data' 'Search' 'Campaign' @{Conv=@(8,$null)}))
$bb17 = BF @(Get-BreakdownFindings $b17 $null) 'ANOM_BRAND_BASELINE'
A ($null -ne $bb17 -and $bb17.confidence -eq 'low') "U10-17 matched sum 12 (<30) => confidence low (F11)"
# 18. non-campaign dim => silent; non-ads => silent; dimensioned no-total => silent
$b18a = Wgt 'google-adwords' 'Google Ads' 'Device' @((Met 'Conv' 'google-adwords:conversions')) @((Rw 'total' $null 'Device' @{Conv=@(100,$null)}),(Rw 'data' 'PMax Mobile' 'Device' @{Conv=@(80,$null)}),(Rw 'data' 'DESKTOP' 'Device' @{Conv=@(20,$null)}))
A (-not (HasRule (Get-BreakdownFindings $b18a $null) 'ANOM_BRAND_BASELINE')) "U10-18 non-campaign dim (Device + PMax row) => silent (F8)"
$b18b = Wgt 'shopify' 'Shopify' 'Campaign' @((Met 'Conv' 'shopify:conversions')) @((Rw 'total' $null 'Campaign' @{Conv=@(100,$null)}),(Rw 'data' 'PMax - Brand' 'Campaign' @{Conv=@(80,$null)}),(Rw 'data' 'Organic' 'Campaign' @{Conv=@(20,$null)}))
A (-not (HasRule (Get-BreakdownFindings $b18b $null) 'ANOM_BRAND_BASELINE')) "U10-18 non-ads category (shopify) => silent (E7)"
$b18c = [pscustomobject]@{ providers=@([pscustomobject]@{id='google-adwords';name='Google Ads'}); currencyCode='USD'; dimensions=@('Campaign'); metrics=@((Met 'Conv' 'google-adwords:conversions')); rows=@((Rw 'data' 'PMax - Brand' 'Campaign' @{Conv=@(80,$null)}),(Rw 'data' 'Search' 'Campaign' @{Conv=@(20,$null)})) }
A (-not (HasRule (Get-BreakdownFindings $b18c $null) 'ANOM_BRAND_BASELINE')) "U10-18 dimensioned no-total campaign => silent (F9 early-return)"
# 19. existing adsAware fixture: still ANOM_SHARE_MISMATCH info, NO ANOM_BRAND_BASELINE (F6 pin, one-arg call)
$fAware = Get-BreakdownFindings $adsAware
A ((HasRule $fAware 'ANOM_SHARE_MISMATCH') -and -not (HasRule $fAware 'ANOM_BRAND_BASELINE')) "U10-19 adsAware ('Brand Awareness' 2%) => share-mismatch yes, brand-baseline no (F6)"
# 26. live-shape QCU regression (direct Get-BreakdownFindings, clientName explicit per AMENDMENTS)
$b26 = Wgt 'google-adwords' 'Google Ads' 'Campaign' @((Met 'Conv' 'google-adwords:conversions')) @(
  (Rw 'total' $null 'Campaign' @{Conv=@(860.9,$null)}),
  (Rw 'data' 'inS - PMax - Quincy General' 'Campaign' @{Conv=@(214.9,$null)}),
  (Rw 'data' 'inS - PMax - Mortgages' 'Campaign' @{Conv=@(111.6,$null)}),
  (Rw 'data' 'inS - PMax - Visa Traditional Card' 'Campaign' @{Conv=@(40.5,$null)}),
  (Rw 'data' 'inS - PMax - HELOC' 'Campaign' @{Conv=@(34.3,$null)}),
  (Rw 'data' 'inS - PMax - Hanover' 'Campaign' @{Conv=@(3,$null)}),
  (Rw 'data' 'Search - Auto Loans' 'Campaign' @{Conv=@(200,$null)}),
  (Rw 'data' 'Search - HELOC' 'Campaign' @{Conv=@(156.6,$null)}),
  (Rw 'data' 'Display Prospecting' 'Campaign' @{Conv=@(100,$null)}))
$bb26 = BF @(Get-BreakdownFindings $b26 'Quincy Credit Union (QCU)') 'ANOM_BRAND_BASELINE'
A ($null -ne $bb26 -and $bb26.evidence.share -eq '47%') "U10-26 QCU live shape: share '47%'"
A ($bb26.evidence.matchedTotal -eq '404.3' -and $bb26.evidence.total -eq '860.9') "U10-26 QCU: matchedTotal '404.3', total '860.9'"
A ($bb26.evidence.brandToken -eq 'quincy') "U10-26 QCU: brandToken 'quincy'"

Write-Host "== U10: rule (a)/(b) e2e (real script) + closer integration =="
# helpers to build ads campaign widgets that fire rule (a)
$gPair = @((Met 'Cost' 'google-adwords:cost_micros' 'micros'),(Met 'Conv' 'google-adwords:conversions'))
$gRows = @((DRow 'total' $null 'Campaign' @{Cost=(Cell 1000000000);Conv=(Cell 100)}),(DRow 'data' 'A' 'Campaign' @{Cost=(Cell 340000000);Conv=(Cell 34)}),(DRow 'data' 'B' 'Campaign' @{Cost=(Cell 330000000);Conv=(Cell 33)}),(DRow 'data' 'C' 'Campaign' @{Cost=(Cell 330000000);Conv=(Cell 33)}))
$fPair = @((Met 'Spend' 'facebook-ads:spend' 'micros'),(Met 'Leads' 'facebook-ads:actions::lead'))
$fRows = @((DRow 'total' $null 'Campaign' @{Spend=(Cell 900000000);Leads=(Cell 90)}),(DRow 'data' 'A' 'Campaign' @{Spend=(Cell 300000000);Leads=(Cell 30)}),(DRow 'data' 'B' 'Campaign' @{Spend=(Cell 300000000);Leads=(Cell 30)}),(DRow 'data' 'C' 'Campaign' @{Spend=(Cell 300000000);Leads=(Cell 30)}))
# 20. two rankable ads platforms, no value anywhere => exactly ONE GAP_COST_RANKING_NO_VALUE, digit-free statement
$r20 = RunAnalyze (MkDoc @(
  (DW 'g20' 'google-adwords' 'Google Ads' @('Campaign') $gPair $gRows),
  (DW 'f20' 'facebook-ads' 'Facebook Ads' @('Campaign') $fPair $fRows)
))
$g20 = @((AllFind $r20.facts) | Where-Object { $_.ruleId -eq 'GAP_COST_RANKING_NO_VALUE' })
A ($g20.Count -eq 1) "U10-20 exactly ONE GAP_COST_RANKING_NO_VALUE"
A ($g20[0].severity -eq 'major' -and $g20[0].requiresDownstreamData -eq $true -and $g20[0].fid -eq 'GAP_COST_RANKING_NO_VALUE#1') "U10-20 severity major, requiresDownstreamData true, fid #1"
A ($g20[0].evidence.platforms -match 'Google Ads' -and $g20[0].evidence.platforms -match 'Facebook Ads') "U10-20 evidence.platforms names both"
A ($g20[0].statement -match 'downstream' -and $g20[0].statement -notmatch '\d') "U10-20 statement has 'downstream', no digit (pair-only phrase)"
A ($g20[0].statement -match 'pairing cost with conversions/leads' -and $g20[0].evidence.rankingMetrics -notmatch 'Cost') "U10-20 pair-only: generic phrase, spend column NOT labelled cost-per-result"
A ($g20[0].statement -match 'no positive conversion-value, revenue, or ROAS recorded') "U10-20 value clause reworded ('no positive ... recorded')"
# 21. + Google zero-dim KPI carrying conversions_value>0 => finding names Facebook only (E1/E2)
$r21b = RunAnalyze (MkDoc @(
  (DW 'g21' 'google-adwords' 'Google Ads' @('Campaign') $gPair $gRows),
  (DW 'f21' 'facebook-ads' 'Facebook Ads' @('Campaign') $fPair $fRows),
  (DW 'gv21' 'google-adwords' 'Google Ads' @() @((Met 'CV' 'google-adwords:conversions_value')) @((KRow @{CV=(Cell 500)})))
))
$g21 = @((AllFind $r21b.facts) | Where-Object { $_.ruleId -eq 'GAP_COST_RANKING_NO_VALUE' })
A ($g21.Count -eq 1 -and $g21[0].evidence.platforms -match 'Facebook Ads' -and $g21[0].evidence.platforms -notmatch 'Google Ads') "U10-21 value on Google KPI => finding names Facebook only (E1/E2)"
# 22. value metric present but all cells 0 => still fires (E4)
$gRows0 = @((DRow 'total' $null 'Campaign' @{Cost=(Cell 1000000000);Conv=(Cell 100);CV=(Cell 0)}),(DRow 'data' 'A' 'Campaign' @{Cost=(Cell 340000000);Conv=(Cell 34);CV=(Cell 0)}),(DRow 'data' 'B' 'Campaign' @{Cost=(Cell 330000000);Conv=(Cell 33);CV=(Cell 0)}),(DRow 'data' 'C' 'Campaign' @{Cost=(Cell 330000000);Conv=(Cell 33);CV=(Cell 0)}))
$r22b = RunAnalyze (MkDoc @( (DW 'g22' 'google-adwords' 'Google Ads' @('Campaign') @($gPair[0],$gPair[1],(Met 'CV' 'google-adwords:conversions_value')) $gRows0) ))
$g22 = @((AllFind $r22b.facts) | Where-Object { $_.ruleId -eq 'GAP_COST_RANKING_NO_VALUE' })
A ($g22.Count -eq 1 -and $g22[0].evidence.platforms -match 'Google Ads') "U10-22 zero-valued value column still fires (E4)"
A ($g22[0].statement -match 'no positive conversion-value') "U10-22 reworded clause stays true in present-but-zero branch"
# 23. all rankable platforms carry value>0 => absent (E3)
$gRowsV = @((DRow 'total' $null 'Campaign' @{Cost=(Cell 1000000000);Conv=(Cell 100);CV=(Cell 500)}),(DRow 'data' 'A' 'Campaign' @{Cost=(Cell 340000000);Conv=(Cell 34);CV=(Cell 170)}),(DRow 'data' 'B' 'Campaign' @{Cost=(Cell 330000000);Conv=(Cell 33);CV=(Cell 165)}),(DRow 'data' 'C' 'Campaign' @{Cost=(Cell 330000000);Conv=(Cell 33);CV=(Cell 165)}))
$r23 = RunAnalyze (MkDoc @( (DW 'g23' 'google-adwords' 'Google Ads' @('Campaign') @($gPair[0],$gPair[1],(Met 'CV' 'google-adwords:conversions_value')) $gRowsV) ))
A (-not (HasFind $r23.facts 'GAP_COST_RANKING_NO_VALUE')) "U10-23 value>0 on rankable platform => absent (E3)"
# 24. KPI-only / time-only / shopify => absent (E5/E6/E7)
$r24a = RunAnalyze (MkDoc @( (DW 'k24' 'google-adwords' 'Google Ads' @() @((Met 'CPA' 'google-adwords:cost_per_conversion')) @((KRow @{CPA=(Cell 10)}))) ))
A (-not (HasFind $r24a.facts 'GAP_COST_RANKING_NO_VALUE')) "U10-24 zero-dim cost-per KPI => absent (E5)"
$r24b = RunAnalyze (MkDoc @( (DW 'm24' 'google-adwords' 'Google Ads' @('Month') @((Met 'Cost' 'google-adwords:cost_micros' 'micros'),(Met 'Conv' 'google-adwords:conversions')) @((DRow 'total' $null 'Month' @{Cost=(Cell 1000000000);Conv=(Cell 100)}),(DRow 'data' '2026-04' 'Month' @{Cost=(Cell 600000000);Conv=(Cell 60)}),(DRow 'data' '2026-05' 'Month' @{Cost=(Cell 400000000);Conv=(Cell 40)}))) ))
A (-not (HasFind $r24b.facts 'GAP_COST_RANKING_NO_VALUE')) "U10-24 time-dim-only cost breakdown => absent (E6)"
$r24c = RunAnalyze (MkDoc @( (DW 's24' 'shopify' 'Shopify' @('Channel') @((Met 'Sessions' 'shopify:sessions'),(Met 'Orders' 'shopify:orders'),(Met 'Rev' 'shopify:revenue' 'micros')) @((DRow 'total' $null 'Channel' @{Sessions=(Cell 1000);Orders=(Cell 30);Rev=(Cell 5000000000)}),(DRow 'data' 'Organic' 'Channel' @{Sessions=(Cell 600);Orders=(Cell 20);Rev=(Cell 3000000000)}),(DRow 'data' 'Direct' 'Channel' @{Sessions=(Cell 400);Orders=(Cell 10);Rev=(Cell 2000000000)}))) ))
A (-not (HasFind $r24c.facts 'GAP_COST_RANKING_NO_VALUE')) "U10-24 shopify (non-ads) => absent (E7)"
# 25. rule (b) e2e: dominant PMax row, force-included in breakdown past the cap (A:757-758 synergy)
$rows25 = [System.Collections.ArrayList]@()
[void]$rows25.Add((DRow 'total' $null 'Campaign' @{Cost=(Cell 21000000000);Conv=(Cell 121)}))
foreach($i in 1..21){ [void]$rows25.Add((DRow 'data' ("Camp{0:D2}" -f $i) 'Campaign' @{Cost=(Cell (1000000000*$i));Conv=(Cell 1)})) }
[void]$rows25.Add((DRow 'data' 'inS - PMax - Brand' 'Campaign' @{Cost=(Cell 1000000);Conv=(Cell 100)}))
$r25 = RunAnalyze (MkDoc @( (DW 'g25' 'google-adwords' 'Google Ads' @('Campaign') @((Met 'Cost' 'google-adwords:cost_micros' 'micros'),(Met 'Conv' 'google-adwords:conversions')) @($rows25)) ))
$bb25 = GetFind $r25.facts 'ANOM_BRAND_BASELINE'
A ($null -ne $bb25 -and $bb25.fid) "U10-25 ANOM_BRAND_BASELINE in findings.anomalies with fid"
$pf25 = Plat $r25.facts 'google-adwords'; $bdRows25 = @($pf25.breakdowns[0].rows | ForEach-Object { $_.label })
A ($bdRows25 -contains 'inS - PMax - Brand') "U10-25 flagged low-cost PMax label force-included in breakdown past top-20 cap"
# 27-29. closer over rule (a): dedicated single-platform facts (balanced rows => only GAP_COST_RANKING_NO_VALUE)
$rC = RunAnalyze (MkDoc @( (DW 'gc' 'google-adwords' 'Google Ads' @('Campaign') $gPair $gRows) ))
$gcF = GetFind $rC.facts 'GAP_COST_RANKING_NO_VALUE'
$repC27 = "## Google Ads`n<!-- platform:google-adwords -->`n$($gcF.statement) <!-- finding:$($gcF.fid) -->`n"
$resC27 = Invoke-Closer $repC27 $rC.facts
A ($resC27.violations.Count -eq 0) "U10-27 rule(a) statement + fid => 0 violations (got $($resC27.violations.Count): $(($resC27.violations | ForEach-Object { $_.type }) -join ','))"
$resC28 = Invoke-Closer ($repC27 -replace '<!--\s*finding:[^>]+?-->','') $rC.facts
A ([bool](@($resC28.violations | Where-Object { $_.type -eq 'unsurfaced-finding' }).Count)) "U10-28 fid stripped => unsurfaced-finding (forced-caveat path)"
$repC29 = "## Google Ads`n<!-- platform:google-adwords -->`nCost efficiency rankings appear in this section. <!-- finding:$($gcF.fid) -->`n"
$resC29 = Invoke-Closer $repC29 $rC.facts
A ([bool](@($resC29.violations | Where-Object { $_.type -eq 'missing-downstream-caveat' }).Count)) "U10-29 surfaced but no downstream clause => missing-downstream-caveat (3c engages)"
# 30. closer over rule (b): byFid scoping pin (47%/404.3 byFid-only; 860.9 traces platform-wide)
$r30 = RunAnalyze (MkDoc @( (DW 'g30' 'google-adwords' 'Google Ads' @('Campaign') @((Met 'Conv' 'google-adwords:conversions')) @(
  (DRow 'total' $null 'Campaign' @{Conv=(Cell 860.9)}),
  (DRow 'data' 'inS - PMax - Quincy General' 'Campaign' @{Conv=(Cell 214.9)}),
  (DRow 'data' 'inS - PMax - Mortgages' 'Campaign' @{Conv=(Cell 111.6)}),
  (DRow 'data' 'inS - PMax - Visa Traditional Card' 'Campaign' @{Conv=(Cell 40.5)}),
  (DRow 'data' 'inS - PMax - HELOC' 'Campaign' @{Conv=(Cell 34.3)}),
  (DRow 'data' 'inS - PMax - Hanover' 'Campaign' @{Conv=(Cell 3)}),
  (DRow 'data' 'Search - Auto Loans' 'Campaign' @{Conv=(Cell 200)}),
  (DRow 'data' 'Search - HELOC' 'Campaign' @{Conv=(Cell 156.6)}),
  (DRow 'data' 'Display Prospecting' 'Campaign' @{Conv=(Cell 100)}))) ))
$bb30 = GetFind $r30.facts 'ANOM_BRAND_BASELINE'
A ($null -ne $bb30 -and $bb30.evidence.share -eq '47%') "U10-30 rule(b) e2e fires (share 47%)"
# 30a: omit rule (b) entirely => 0 violations (info advisory, D8)
$rep30omit = "## Google Ads`n<!-- platform:google-adwords -->`nConversions totalled 860.9 this period.`n"
$res30omit = Invoke-Closer $rep30omit $r30.facts
A ($res30omit.violations.Count -eq 0) "U10-30a omitting info rule(b) => 0 violations (D8 advisory; 860.9 traces)"
# 30b: quote 47%/404.3/860.9 on the fid-anchored line => all trace
$rep30ok = "## Google Ads`n<!-- platform:google-adwords -->`nBrand-demand suspects were 47% of conversions (404.3 of 860.9). <!-- finding:$($bb30.fid) -->`n"
$res30ok = Invoke-Closer $rep30ok $r30.facts
A (-not [bool](@($res30ok.violations | Where-Object { $_.type -eq 'untraceable-number' }).Count)) "U10-30b 47%/404.3/860.9 on fid line => all trace (0 untraceable)"
# 30c: same numbers on a NON-anchored line => 47% and 404.3 untraceable; 860.9 traces platform-wide
$rep30bad = "## Google Ads`n<!-- platform:google-adwords -->`nBrand-demand suspects were 47% of conversions (404.3 of 860.9).`n"
$res30bad = Invoke-Closer $rep30bad $r30.facts
$unt30 = @($res30bad.violations | Where-Object { $_.type -eq 'untraceable-number' } | ForEach-Object { $_.snippet })
A (($unt30 -join '|') -match '47' -and ($unt30 -join '|') -match '404\.3') "U10-30c non-anchored: 47% and 404.3 flagged untraceable"
A (-not (($unt30 -join '|') -match '860')) "U10-30c non-anchored: widget total 860.9 traces platform-wide (never flagged)"

Write-Host ""
Write-Host ("RESULT: {0} passed, {1} failed" -f $pass,$fail) -ForegroundColor $(if($fail){'Red'}else{'Green'})
if($fail){ exit 1 }
