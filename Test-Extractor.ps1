<#
.SYNOPSIS
  Offline unit tests for Get-SwydoReport.ps1 — dot-sources the real functions via -DefineOnly
  (no network) and exercises the schema-v2 branches that a Google+Facebook report can't trigger:
  provider-scoped units, universal _micros$, collision-safe row keys, manual-KPI decoupling,
  unknown-kind classification, null-safety. Run: .\Test-Extractor.ps1
#>
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\skill\scripts\Get-SwydoReport.ps1" -DefineOnly    # loads the REAL functions, runs nothing
$script:secMap = @{ s1 = "Section 1" }

$pass=0; $fail=0
function Assert($cond,$msg){ if($cond){ $script:pass++ } else { $script:fail++; Write-Host "  FAIL: $msg" -ForegroundColor Red } }
function W([pscustomobject]$widget){ [pscustomobject]@{ data = [pscustomobject]@{ widget = $widget } } }
function Node($cells,$compare,$flags){ $n=[pscustomobject]@{ cells=$cells; compareCells=$compare; meta=$null; isTotals=$false; isSubtotals=$false }; if($flags){$n.isTotals=$flags.t; $n.isSubtotals=$flags.s}; [pscustomobject]@{ node=$n } }
function FieldsConn($items){ [pscustomobject]@{ edges = @($items | ForEach-Object { [pscustomobject]@{ node=$_ } }) } }

Write-Host "== Unit-Of =="
$uz = @{
 'google-adwords:cost_micros'='micros'; 'google-adwords:average_cpc'='micros'; 'google-adwords:average_cpm'='micros'
 'google-adwords:cost_per_conversion'='micros'; 'facebook-ads:spend'='micros'; 'facebook-ads:cpc'='micros'
 'facebook-ads:costPerActionType::link_click'='micros'; 'facebook-ads:ctrLink'='fraction'; 'facebook-ads:ctr'='fraction'
 'google-adwords:ctr'='fraction'; 'google-adwords:conversion_rate'='fraction'; 'google-adwords:interaction_rate'='fraction'
 'google-adwords:video_view_rate'='fraction'; 'google-adwords:search_impression_share'='fraction'; 'google-adwords:search_lost_is_budget'='fraction'
 'google-adwords:impressions'=$null; 'google-adwords:clicks'=$null; 'facebook-ads:reach'=$null
 'bing-ads:spend'=$null; 'linkedin-ads:cpc'=$null; 'tiktok-ads:spend'=$null; 'google-analytics-4:cpc'=$null; 'pinterest:cpm'=$null
 'x:exchange_rate'=$null; 'ga4:events_per_session_rate'=$null
 'google-analytics-4:engagement_time_micros'='micros'; 'google-adwords:conversions_value_micros'='micros'; 'shopify:total_sales_micros'='micros'
}
foreach($k in $uz.Keys){ $g=Unit-Of $k; Assert ($g -eq $uz[$k]) "Unit-Of('$k') => '$g' expected '$($uz[$k])'" }
Assert ((Unit-Of $null) -eq $null) "Unit-Of(null) => null"

Write-Host "== Uniq-Key =="
$m=[ordered]@{}
$k1=Uniq-Key $m 'Clicks' 'google-adwords:clicks' 0; $m[$k1]=1; Assert ($k1 -eq 'Clicks') "first Clicks => 'Clicks'"
$k2=Uniq-Key $m 'Clicks' 'facebook-ads:clicks' 1; $m[$k2]=1; Assert ($k2 -eq 'Clicks [facebook-ads:clicks]') "dup name diff id => id-suffixed"
$k3=Uniq-Key $m 'Clicks' 'facebook-ads:clicks' 2; $m[$k3]=1; Assert ($k3 -eq 'Clicks [facebook-ads:clicks #2]') "dup name+id => index-suffixed"
$kn=Uniq-Key $m $null 'p:x' 4; Assert ($kn -eq 'p:x') "null name => id"
$kz=Uniq-Key $m $null $null 7; Assert ($kz -eq 'col7') "null name+id => col<idx>"

Write-Host "== Normalize: manual KPI (source null) =="
$mk = W ([pscustomobject]@{ visual=@{id='KPI'}; displayOptions=[pscustomobject]@{title=$null}; source=$null; manualKpiOptions=[pscustomobject]@{value=42; compareValue=30}; content=$null; target=$null; comparisonFormat='ABSOLUTE'; dims=$null; metrics=$null; data=[pscustomobject]@{edges=@()} })
$r = Normalize-Widget @{id='w1';visual='KPI';section='s1'} $mk
Assert ($r.kind -eq 'manualKpi') "manual KPI kind => manualKpi (got '$($r.kind)')"
Assert ($r.manualKpi.value -eq 42 -and $r.manualKpi.compareValue -eq 30) "manual KPI value emitted"
Assert ($null -ne $r.raw) "raw present on manualKpi"

Write-Host "== Normalize: manual + source KPI (decoupled) =="
$src=[pscustomobject]@{ parts=@([pscustomobject]@{ provider=[pscustomobject]@{id='google-adwords';name='Google Ads'} }) }
$ms = W ([pscustomobject]@{ visual=@{id='KPI'}; displayOptions=[pscustomobject]@{title=$null}; source=$src; manualKpiOptions=[pscustomobject]@{value=99; compareValue=$null}; content=$null; target=$null; comparisonFormat='ABSOLUTE'; dims=$null; metrics=$null; data=[pscustomobject]@{edges=@()} })
$r = Normalize-Widget @{id='w2';visual='KPI';section='s1'} $ms
Assert ($r.kind -eq 'data') "manual+source => kind data"
Assert ($r.manualKpi.value -eq 99) "manual+source => manualKpi STILL emitted (decoupled)"

Write-Host "== Normalize: unknown visual (source null, not text) =="
$uk = W ([pscustomobject]@{ visual=@{id='IMAGE'}; displayOptions=[pscustomobject]@{title=$null}; source=$null; manualKpiOptions=$null; content=$null; target=$null })
$r = Normalize-Widget @{id='w3';visual='IMAGE';section='s1'} $uk
Assert ($r.kind -eq 'unknown') "IMAGE/no-source => kind unknown (got '$($r.kind)')"
Assert ($null -ne $r.raw) "raw present on unknown"

Write-Host "== Normalize: null widget (error) =="
$r = Normalize-Widget @{id='w4';visual='KPI';section='s1'} (W $null)
Assert ($r.kind -eq 'unknown' -and $null -eq $r.raw) "null widget => kind unknown, raw null, no throw"

Write-Host "== Normalize: metric name collision (blended Clicks) =="
$mets = FieldsConn @([pscustomobject]@{name='Clicks';id='google-adwords:clicks'}, [pscustomobject]@{name='Clicks';id='facebook-ads:clicks'})
$node = Node @(100,250) $null $null
$bl = W ([pscustomobject]@{ visual=@{id='TABLE'}; displayOptions=[pscustomobject]@{title=$null}; source=$src; manualKpiOptions=$null; comparisonFormat='ABSOLUTE'; content=$null; target=$null; dims=$null; metrics=$mets; data=[pscustomobject]@{edges=@($node)} })
$r = Normalize-Widget @{id='w5';visual='TABLE';section='s1'} $bl
$mm = $r.rows[0].metrics
Assert ($mm.Keys.Count -eq 2) "blended Clicks => 2 distinct metric keys (got $($mm.Keys.Count))"
Assert ($mm['Clicks'].current -eq 100 -and $mm['Clicks [facebook-ads:clicks]'].current -eq 250) "both Clicks values survive (no overwrite)"

Write-Host "== Normalize: dimension name collision =="
$dims = FieldsConn @([pscustomobject]@{name='Campaign';id='g:campaign'}, [pscustomobject]@{name='Campaign';id='f:campaign'})
$objA=[pscustomobject]@{campaign_id='1';campaign_name='Alpha'}; $objB=[pscustomobject]@{campaign_id='2';campaign_name='Beta'}
$node2 = Node @($objA,$objB,7) $null $null
$dc = W ([pscustomobject]@{ visual=@{id='TABLE'}; displayOptions=[pscustomobject]@{title=$null}; source=$src; manualKpiOptions=$null; comparisonFormat='ABSOLUTE'; content=$null; target=$null; dims=$dims; metrics=(FieldsConn @([pscustomobject]@{name='Clicks';id='google-adwords:clicks'})); data=[pscustomobject]@{edges=@($node2)} })
$r = Normalize-Widget @{id='w6';visual='TABLE';section='s1'} $dc
$dd = $r.rows[0].dimensions
Assert ($dd.Keys.Count -eq 2) "dup Campaign dims => 2 keys (got $($dd.Keys.Count))"
Assert ($dd['Campaign'] -eq 'Alpha' -and $dd['Campaign [f:campaign]'] -eq 'Beta') "both Campaign dim labels survive"

Write-Host "== trend: Test-TrendTimeWidget =="
Assert (Test-TrendTimeWidget @('Month')) "Month => time"
Assert (Test-TrendTimeWidget @('Date')) "Date => time"
Assert (Test-TrendTimeWidget @('Week')) "Week => time"
Assert (-not (Test-TrendTimeWidget @('Campaign'))) "Campaign => not time"
Assert (-not (Test-TrendTimeWidget @('Keyword'))) "Keyword => not time"
Assert (-not (Test-TrendTimeWidget @('Update'))) "Update (contains 'date') => not time"

Write-Host "== trend: ConvertTo-MonthKey =="
Assert ((ConvertTo-MonthKey '2025-04') -eq '2025-04') "YYYY-MM passthrough"
Assert ((ConvertTo-MonthKey '2025-04-15') -eq '2025-04') "YYYY-MM-DD => YYYY-MM"
Assert ((ConvertTo-MonthKey '202504') -eq '2025-04') "YYYYMM => YYYY-MM"
Assert ($null -eq (ConvertTo-MonthKey 'Total')) "non-month => null"
Assert ($null -eq (ConvertTo-MonthKey $null)) "null => null"

Write-Host "== trend: month ordinal arithmetic =="
Assert ((OrdinalToMonthKey (MonthKeyToOrdinal '2025-04')) -eq '2025-04') "ordinal roundtrip"
Assert (((MonthKeyToOrdinal '2025-04') - (MonthKeyToOrdinal '2025-03')) -eq 1) "adjacent within year => 1"
Assert (((MonthKeyToOrdinal '2025-01') - (MonthKeyToOrdinal '2024-12')) -eq 1) "year boundary => 1"
Assert ($null -eq (MonthKeyToOrdinal 'x')) "bad => null"

Write-Host "== trend: Test-TrailingContiguous =="
Assert (Test-TrailingContiguous @('2025-01','2025-02','2025-03') 2) "consecutive => true"
Assert (Test-TrailingContiguous @('2024-12','2025-01') 2) "year-boundary consecutive => true"
Assert (-not (Test-TrailingContiguous @('2025-01','2025-03') 2)) "gap in trailing 2 => false"
Assert (-not (Test-TrailingContiguous @('2025-05') 2)) "single => false"
Assert (Test-TrailingContiguous @('2025-01','2025-05','2025-06') 2) "trailing 2 consecutive (older gap ok) => true"

Write-Host "== trend: Select-CeilingBracket =="
$b1=Select-CeilingBracket @{48=0;36=0;24=25;18=18;12=12}; Assert ($b1.R -eq 24 -and $b1.F -eq 36) "30mo-ish => bracket [24,36]"
$b2=Select-CeilingBracket @{48=40;36=36;24=24;18=18;12=12}; Assert ($b2.R -eq 48 -and $null -eq $b2.F) "widest has rows => R=48, no F"
$b3=Select-CeilingBracket @{48=0;36=0;24=0;18=0;12=0};      Assert ($null -eq $b3.R -and $b3.F -eq 12) "all empty => R null"
$b4=Select-CeilingBracket @{48=0;36=0;24=0;18=20;12=12};    Assert ($b4.R -eq 18 -and $b4.F -eq 24) "FB-like overshoot => bracket [18,24]"

Write-Host "== trend: Get-NextBisectN =="
Assert ((Get-NextBisectN 24 36) -eq 30) "mid(24,36)=30"
Assert ((Get-NextBisectN 18 24) -eq 21) "mid(18,24)=21"
Assert ($null -eq (Get-NextBisectN 24 25)) "converged (F-R<=1) => null"
Assert ($null -eq (Get-NextBisectN 18 $null)) "no F => null"

Write-Host "== trend: Test-CeilingFresh / Get-CurrentMonthKey =="
$nowT=[datetimeoffset]'2026-07-06T00:00:00Z'
Assert (Test-CeilingFresh (([datetimeoffset]'2026-07-01T00:00:00Z').ToString('o')) $nowT 30) "5 days => fresh"
Assert (-not (Test-CeilingFresh (([datetimeoffset]'2026-05-01T00:00:00Z').ToString('o')) $nowT 30)) "66 days => stale"
Assert (-not (Test-CeilingFresh $null $nowT 30)) "null discoveredAt => not fresh"
Assert ((Get-CurrentMonthKey ([datetimeoffset]'2026-07-06T12:00:00Z')) -eq '2026-07') "current month key"

Write-Host "== trend: Get-TrendMonthCells =="
function TNode($cells,$isT,$isS,$cc){ [pscustomobject]@{ node=[pscustomobject]@{ cells=$cells; compareCells=$null; meta=[pscustomobject]@{currencyCode=$cc}; isTotals=$isT; isSubtotals=$isS } } }
$twobj = W ([pscustomobject]@{
  metrics=(FieldsConn @([pscustomobject]@{name='Cost';id='google-adwords:cost_micros'}, [pscustomobject]@{name='Clicks';id='google-adwords:clicks'}))
  dims=(FieldsConn @([pscustomobject]@{name='Month';id='d:month'}))
  data=[pscustomobject]@{ edges=@(
    (TNode @($null,999,999) $true $false 'USD')          # total => excluded
    (TNode @($null,999,999) $false $true 'USD')          # subtotal => excluded
    (TNode @('2025-04',1000000,50) $false $false 'USD')
    (TNode @('2025-05',2000000,60) $false $false 'USD')
    (TNode @('Total',1,1) $false $false 'USD')           # non-month label => excluded
  ) }
})
$mc = Get-TrendMonthCells $twobj
Assert ($mc.windowStatus -eq 'ok') "windowStatus ok"
Assert (@($mc.months).Count -eq 2) "2 real month rows (totals/subtotals/non-month excluded), got $(@($mc.months).Count)"
Assert ($mc.months[0].month -eq '2025-04') "first month 2025-04"
Assert ($mc.months[0].values['google-adwords:cost_micros'] -eq 1000000) "cost cell mapped by metric id"
Assert ($mc.months[0].values['google-adwords:clicks'] -eq 50) "clicks cell mapped by metric id"
Assert ($mc.months[0].currency -eq 'USD') "currency from node meta"
$mce = Get-TrendMonthCells (W ([pscustomobject]@{ metrics=(FieldsConn @()); dims=(FieldsConn @([pscustomobject]@{name='Month';id='d:month'})); data=[pscustomobject]@{edges=@()} }))
Assert ($mce.windowStatus -eq 'overshoot-empty') "empty window => overshoot-empty"
# currency resolved WIDGET-WIDE: a month row missing meta.currencyCode still gets the widget currency (M1)
$twmix = W ([pscustomobject]@{
  metrics=(FieldsConn @([pscustomobject]@{name='Cost';id='google-adwords:cost_micros'}))
  dims=(FieldsConn @([pscustomobject]@{name='Month';id='d:month'}))
  data=[pscustomobject]@{ edges=@(
    (TNode @('2025-04',1000000) $false $false 'USD')
    (TNode @('2025-05',0)       $false $false $null)   # low-activity month omits currency
  ) }
})
$mcm = Get-TrendMonthCells $twmix
Assert ($mcm.months[0].currency -eq 'USD' -and $mcm.months[1].currency -eq 'USD') "widget-wide currency: both months USD (not forked by a null-currency row)"
$mcx = Get-TrendMonthCells (W $null)
Assert ($mcx.windowStatus -eq 'error') "null widget => error"

Write-Host "== provider filter (--platform) =="
Assert (((Parse-PlatformFilter @('google-adwords','Facebook-Ads')) -join ',') -eq 'facebook-ads,google-adwords') "parse: lowercased + sorted-unique"
Assert (((Parse-PlatformFilter 'google-adwords, facebook-ads') -join ',') -eq 'facebook-ads,google-adwords') "parse: comma-list split + trim"
Assert ((Parse-PlatformFilter @()).Count -eq 0) "parse: empty => none"
Assert (Test-ProviderMatch @('google-adwords') @('google-adwords')) "match: hit"
Assert (-not (Test-ProviderMatch @('facebook-ads') @('google-adwords'))) "match: miss"
Assert (Test-ProviderMatch @('google-adwords','facebook-ads') @('facebook-ads')) "match: blended widget kept if ANY provider wanted (whole widget)"
Assert (Test-ProviderMatch @('anything') @()) "match: no filter => keep all"

Write-Host "== U8: Resolve-ReportPeriod =="
# build a wire-shaped dateRange fixture: { primary: { count, measure, type } }
function DR($count,$measure,$type){ [pscustomobject]@{ primary=[pscustomobject]@{ count=$count; measure=$measure; type=$type }; comparison=$null; baseDate=$null; timeZone=$null } }
function AT($y,$m,$d){ New-Object DateTime($y,$m,$d) }

# U8-E1: the live-verified pair (quarter/-1 @ 2026-07-06) => 2026-04..2026-06, wrapper fields
$r1 = Resolve-ReportPeriod (DR -1 'quarter' 'RELATIVE') (AT 2026 7 6)
Assert ($r1.resolverVersion -eq 1) "E1 resolverVersion 1"
Assert ($r1.rule -eq 'relative-last-complete') "E1 rule"
Assert ($r1.anchorDate -eq '2026-07-06') "E1 anchorDate"
Assert (-not $r1.Contains('note')) "E1 no note when resolved"
Assert ($r1.primary.startDate -eq '2026-04-01') "E1 startDate 2026-04-01"
Assert ($r1.primary.endDate -eq '2026-06-30') "E1 endDate 2026-06-30"
Assert ($r1.primary.startYm -eq '2026-04') "E1 startYm 2026-04"
Assert ($r1.primary.endYm -eq '2026-06') "E1 endYm 2026-06"
Assert ($r1.primary.calendarAligned -eq $true) "E1 calendarAligned true"
Assert ($r1.primary.measure -eq 'quarter' -and $r1.primary.count -eq -1) "E1 measure/count echo"

# U8-E2: cross-year quarter (mirrors TA label pin @ 2026-02-15 => Q4 2025)
$r2 = Resolve-ReportPeriod (DR -1 'quarter' 'RELATIVE') (AT 2026 2 15)
Assert ($r2.primary.startYm -eq '2025-10' -and $r2.primary.endYm -eq '2025-12') "E2 2025-10..2025-12"

# U8-E3: boundary day (July 1 belongs to the new quarter; Q2 is last complete)
$r3 = Resolve-ReportPeriod (DR -1 'quarter' 'RELATIVE') (AT 2026 7 1)
Assert ($r3.primary.startYm -eq '2026-04' -and $r3.primary.endYm -eq '2026-06') "E3 boundary day still Q2"

# U8-E4: month/-1 UNRESOLVED under the unattended domain (shrunk to quarter/-1 only)
$r4 = Resolve-ReportPeriod (DR -1 'month' 'RELATIVE') (AT 2026 7 6)
Assert ($null -eq $r4.primary) "E4 month/-1 -> null (unattended domain: quarter-only)"
Assert ($r4.Contains('note') -and $r4.note -match 'measure') "E4 month note names measure"

# U8-E5: year/-1 UNRESOLVED under the unattended domain
$r5 = Resolve-ReportPeriod (DR -1 'year' 'RELATIVE') (AT 2026 7 6)
Assert ($null -eq $r5.primary) "E5 year/-1 -> null (unattended domain: quarter-only)"
Assert ($r5.Contains('note') -and $r5.note -match 'measure') "E5 year note names measure"

# U8-E8 (FP): week/-1 -> null, note names measure, no throw
$r8 = Resolve-ReportPeriod (DR -1 'week' 'RELATIVE') (AT 2026 7 6)
Assert ($null -eq $r8.primary -and $r8.note -match 'measure') "E8 week/-1 -> null with measure note"

# U8-E9 (FP): day/-30 -> null (count out of domain first)
$r9 = Resolve-ReportPeriod (DR -30 'day' 'RELATIVE') (AT 2026 7 6)
Assert ($null -eq $r9.primary) "E9 day/-30 -> null"

# U8-E10 (FP): multi-count relative -> all null with a count note (EC-7)
foreach($cc in @(-3,-2,0,1)){
  $rc = Resolve-ReportPeriod (DR $cc 'quarter' 'RELATIVE') (AT 2026 7 6)
  Assert ($null -eq $rc.primary -and $rc.note -match 'count') "E10 quarter/$cc -> null with count note"
}
$rm3 = Resolve-ReportPeriod (DR -3 'month' 'RELATIVE') (AT 2026 7 6)
Assert ($null -eq $rm3.primary -and $rm3.note -match 'count') "E10 month/-3 -> null (count note)"

# U8-E11 (FP): non-RELATIVE type, null type, null dateRange, missing primary -> null, no throw
$r11a = Resolve-ReportPeriod (DR -1 'quarter' 'PERIOD') (AT 2026 7 6)
Assert ($null -eq $r11a.primary -and $r11a.note -match 'type') "E11 type PERIOD -> null with type note"
$r11b = Resolve-ReportPeriod (DR -1 'quarter' $null) (AT 2026 7 6)
Assert ($null -eq $r11b.primary -and $r11b.note -match 'type') "E11 type null -> null with type note"
$r11c = Resolve-ReportPeriod $null (AT 2026 7 6)
Assert ($null -eq $r11c.primary -and $r11c.note -match 'primary') "E11 null dateRange -> null, no throw"
$r11d = Resolve-ReportPeriod ([pscustomobject]@{ primary=$null }) (AT 2026 7 6)
Assert ($null -eq $r11d.primary -and $r11d.note -match 'primary') "E11 missing primary -> null, no throw"

# U8-E12: count typing tolerance + fractional banker's-rounding guard (the [double] cast must-fix)
$r12a = Resolve-ReportPeriod (DR ([long]-1) 'quarter' 'RELATIVE') (AT 2026 7 6)
Assert ($r12a.primary.startYm -eq '2026-04') "E12 [long]-1 resolves"
$r12b = Resolve-ReportPeriod (DR ([double]-1.0) 'quarter' 'RELATIVE') (AT 2026 7 6)
Assert ($r12b.primary.startYm -eq '2026-04') "E12 [double]-1.0 resolves"
$r12c = Resolve-ReportPeriod (DR '-1' 'quarter' 'RELATIVE') (AT 2026 7 6)
Assert ($r12c.primary.startYm -eq '2026-04') "E12 string '-1' resolves"
$r12d = Resolve-ReportPeriod (DR 'abc' 'quarter' 'RELATIVE') (AT 2026 7 6)
Assert ($null -eq $r12d.primary) "E12 'abc' count -> null (no crash)"
# the [double]-not-[int] must-fix: fractional counts must NOT resolve (banker's rounding to -1)
$r12e = Resolve-ReportPeriod (DR -1.4 'quarter' 'RELATIVE') (AT 2026 7 6)
Assert ($null -eq $r12e.primary) "E12 count -1.4 -> null (would be -1 under [int] banker's round)"
$r12f = Resolve-ReportPeriod (DR -0.6 'quarter' 'RELATIVE') (AT 2026 7 6)
Assert ($null -eq $r12f.primary) "E12 count -0.6 -> null (would be -1 under [int] banker's round)"

# U8-E13: every resolved output is invariant-culture shaped + calendarAligned recomputable from dates
$r13 = Resolve-ReportPeriod (DR -1 'quarter' 'RELATIVE') (AT 2026 7 6)
$sd=[datetime]::ParseExact($r13.primary.startDate,'yyyy-MM-dd',$null); $ed=[datetime]::ParseExact($r13.primary.endDate,'yyyy-MM-dd',$null)
Assert ((($sd.Day -eq 1) -and ($ed.AddDays(1).Day -eq 1)) -eq $r13.primary.calendarAligned) "E13 calendarAligned recomputable"
Assert ($r13.primary.startYm -match '^[0-9]{4}-(0[1-9]|1[0-2])$') "E13 startYm shape"
Assert ($r13.primary.endYm -match '^[0-9]{4}-(0[1-9]|1[0-2])$') "E13 endYm shape"
Assert ($r13.anchorDate -match '^[0-9]{4}-[0-9]{2}-[0-9]{2}$') "E13 anchorDate shape"

# U8-E14: wrapper key contract
$k1 = @($r1.Keys)
Assert (($k1 -join ',') -eq 'resolverVersion,rule,anchorDate,primary') "E14 resolved wrapper keys exactly 4"
$k4 = @($r4.Keys)
Assert (($k4 -join ',') -eq 'resolverVersion,rule,anchorDate,primary,note') "E14 unresolved wrapper adds note"

Write-Host ""
Write-Host ("RESULT: {0} passed, {1} failed" -f $pass, $fail) -ForegroundColor $(if($fail){'Red'}else{'Green'})
if($fail){ exit 1 }
