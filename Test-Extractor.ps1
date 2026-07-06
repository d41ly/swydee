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

Write-Host ""
Write-Host ("RESULT: {0} passed, {1} failed" -f $pass, $fail) -ForegroundColor $(if($fail){'Red'}else{'Green'})
if($fail){ exit 1 }
