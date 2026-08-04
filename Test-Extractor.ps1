<#
.SYNOPSIS
  Offline unit tests for Get-SwydoReport.ps1 - dot-sources the real functions via -DefineOnly
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

Write-Host "== ANLZ-aUniformLattice-2 P1: additive schema-v3 keys =="
# Get-UniqKeySeq must reproduce the sequence the untouched row loop writes.
$seqDup = Get-UniqKeySeq @([pscustomobject]@{name='Clicks';id='google-adwords:clicks'}, [pscustomobject]@{name='Clicks';id='facebook-ads:clicks'})
Assert ($seqDup.Count -eq 2) "P1 Get-UniqKeySeq returns one key per item"
Assert ($seqDup[0] -eq 'Clicks' -and $seqDup[1] -eq 'Clicks [facebook-ads:clicks]') "P1 dup display name => two DIFFERENT cellKeys"
$seqEmpty = Get-UniqKeySeq @([pscustomobject]@{name=$null;id=$null})
Assert ($seqEmpty[0] -eq 'col0') "P1 empty name+id => Uniq-Key col<idx> fallback"

# AC1/AC2: the emitted cellKey is the key the row map actually uses.
$r = Normalize-Widget @{id='w5b';visual='TABLE';section='s1'} $bl $null 0
Assert ($r.metrics[0].cellKey -eq 'Clicks' -and $r.metrics[1].cellKey -eq 'Clicks [facebook-ads:clicks]') "P1 AC1 cellKey emitted per metric"
Assert ($r.rows[0].metrics.Contains($r.metrics[0].cellKey) -and $r.rows[0].metrics.Contains($r.metrics[1].cellKey)) "P1 AC1 every cellKey addresses a real row-map key"
Assert ($r.metrics[0].providerId -eq 'google-adwords' -and $r.metrics[1].providerId -eq 'facebook-ads') "P1 metrics[].providerId is the id prefix"
Assert ($r.rows[0].metrics[$r.metrics[1].cellKey].current -eq 250) "P1 cellKey reads the SECOND metric's own value (the wrong-value path)"

# AC9: dimensions[] stays a plain string array; dimensionRefs carries the ids.
$r6 = Normalize-Widget @{id='w6b';visual='TABLE';section='s1'} $dc $null 0
Assert (@($r6.dimensions).Count -eq 2 -and ($r6.dimensions[0] -is [string]) -and ($r6.dimensions[1] -is [string])) "P1 AC9 dimensions[] is still a string array"
Assert ($r6.dimensions[0] -eq 'Campaign' -and $r6.dimensions[1] -eq 'Campaign') "P1 AC9 dimensions[] values byte-identical"
Assert ($r6.dimensionRefs[0].id -eq 'g:campaign' -and $r6.dimensionRefs[1].id -eq 'f:campaign') "P1 AC9 dimensionRefs carries both ids"

# AC3: rowKey is exact, ordinal-first, pipe-escaped, and '0' for a zero-dimension widget.
Assert ((Get-RowKey 2 @('Alpha','Brand | Search')) -eq '2|Alpha|Brand / Search') "P1 AC3 rowKey exact incl. literal-pipe escape"
Assert ((Get-RowKey 0 @()) -eq '0') "P1 AC3 zero-dimension rowKey is '0', not '0|'"
Assert ((Get-RowKey 5 @($null)) -eq '5|') "P1 AC3 null dim value does not throw"
Assert ($r6.rows[0].rowKey -eq '0|Alpha|Beta') "P1 AC3 rowKey emitted on the row"

# AC4: Build-WidgetInputs pairs each widget with ITS OWN outcome, by id, never positionally.
$wA=@{id='wa';visual='TABLE';section='s1'}; $wB=@{id='wb';visual='TABLE';section='s1'}; $wC=@{id='wc';visual='TABLE';section='s1'}
$ocs=@([ordered]@{id='wb';outcome='incomplete';reason='partial-pages';pagesFetched=3;endCursor='cur';truncated=$true;hasNextPage=$true},
       [ordered]@{id='wa';outcome='filled';reason=$null;pagesFetched=1;endCursor=$null;truncated=$false;hasNextPage=$false})
$inp = Build-WidgetInputs @($wA,$wB,$wC) @{} $ocs
Assert (@($inp).Count -eq 3) "P1 AC4 one input per pulled widget"
Assert ($inp[0].wmeta.id -eq 'wa' -and $inp[0].outcome.outcome -eq 'filled') "P1 AC4 pairing is by id, not by position"
Assert ($inp[1].wmeta.id -eq 'wb' -and $inp[1].outcome.reason -eq 'partial-pages') "P1 AC4 the out-of-order record still lands on its own widget"
Assert ($null -eq $inp[2].outcome) "P1 AC4 a widget with no record gets null, never a guess"
Assert ($inp[0].index -eq 0 -and $inp[2].index -eq 2) "P1 AC4/AC10 documentIndex is the ordinal in the pulled set"

# AC4 continued + AC5: completeness rides fetch INTENT, so kind='unknown' still reports.
$okOut=[ordered]@{id='w7';outcome='filled';reason=$null;pagesFetched=1;endCursor=$null;truncated=$false;hasNextPage=$false}
$badOut=[ordered]@{id='w8';outcome='incomplete';reason='partial-pages';pagesFetched=2;endCursor='c9';truncated=$true;hasNextPage=$true}
$rok = Normalize-Widget @{id='w7';visual='TABLE';section='s1'} $bl $okOut 0
$rbad = Normalize-Widget @{id='w8';visual='TABLE';section='s1'} (W $null) $badOut 1
Assert ($rok.pagesComplete -eq $true -and $rok.pageInfo.truncated -eq $false) "P1 AC4 clean fetch => pagesComplete true"
Assert ($rbad.pagesComplete -eq $false -and $rbad.pageInfo.endCursor -eq 'c9') "P1 AC4 partial-pages => pagesComplete false + endCursor"
Assert ($rbad.kind -eq 'unknown' -and $rbad.fetchOutcome -eq 'incomplete') "P1 AC5 a failed data widget degrades to kind=unknown but STILL reports completeness"
$emptyOut=[ordered]@{id='w9';outcome='empty-resolved';reason=$null;pagesFetched=1;endCursor=$null;truncated=$false;hasNextPage=$false}
$rem = Normalize-Widget @{id='w9';visual='TABLE';section='s1'} $bl $emptyOut 0
Assert ($rem.pagesComplete -eq $true) "P1 empty-resolved is an honest zero-row answer, not an incomplete one"
$rtxt = Normalize-Widget @{id='w10';visual='TEXT';section='s1'} (W ([pscustomobject]@{visual=@{id='TEXT'};displayOptions=[pscustomobject]@{title=$null};source=$null;manualKpiOptions=$null;content=$null;target=$null})) $okOut 0
Assert (-not $rtxt.Contains('pagesComplete')) "P1 a TEXT widget carries no completeness block"

# AC6: sectionHidden must not throw when the parallel map is unseeded.
Assert ($rok.sectionHidden -eq $false) "P1 AC6 unseeded secHidden => false, no throw"
$script:secHidden = @{ s1 = $true }
$rh = Normalize-Widget @{id='w11';visual='TABLE';section='s1'} $bl $okOut 0
Assert ($rh.sectionHidden -eq $true) "P1 AC6 hidden section => sectionHidden true"
$script:secHidden = @{}

# AC7/AC8: row-kind counts and the encounter-order currency set.
$nT = Node @(5) $null @{t=$true;s=$false}; $nS = Node @(3) $null @{t=$false;s=$true}; $nD = Node @(2) $null $null
$nD.node.meta = [pscustomobject]@{ currencyCode='USD' }; $nT.node.meta = [pscustomobject]@{ currencyCode='EUR' }
$mixed = W ([pscustomobject]@{ visual=@{id='TABLE'}; displayOptions=[pscustomobject]@{title=$null}; source=$src; manualKpiOptions=$null; comparisonFormat='ABSOLUTE'; content=$null; target=$null; dims=$null; metrics=(FieldsConn @([pscustomobject]@{name='Clicks';id='google-adwords:clicks'})); data=[pscustomobject]@{edges=@($nD,$nS,$nT)} })
$rm2 = Normalize-Widget @{id='w12';visual='TABLE';section='s1'} $mixed $okOut 0
Assert ($rm2.hasTotalRow -eq $true) "P1 AC7 hasTotalRow true when a total row is present"
Assert ($rm2.rowKindCounts.data -eq 1 -and $rm2.rowKindCounts.subtotal -eq 1 -and $rm2.rowKindCounts.total -eq 1) "P1 AC7 rowKindCounts sums to the row count"
Assert ($rm2.currencyCode -eq 'USD') "P1 AC8 currencyCode keeps its first-wins value"
Assert ($rm2.currencyCodes[0] -eq 'USD' -and $rm2.currencyCodes[1] -eq 'EUR') "P1 AC8 currencyCodes is encounter order, not sorted"
Assert ($rm2.currencyBasis -eq 'row-meta') "P1 AC8 currencyBasis row-meta when a row carried a code"

# AC12: both schemaVersion writers say 3, and there are exactly two of them.
$srcP1 = Get-Content (Join-Path $PSScriptRoot 'skill\scripts\Get-SwydoReport.ps1') -Raw
$svWrites = @([regex]::Matches($srcP1,'schemaVersion=\d+'))
Assert ($svWrites.Count -eq 2) "P1 AC12 exactly two schemaVersion writers (got $($svWrites.Count))"
Assert (@($svWrites | Where-Object { $_.Value -eq 'schemaVersion=3' }).Count -eq 2) "P1 AC12 both writers emit schemaVersion=3"

# AC13: the field probe classifies on positive evidence, three-state, and bounds its detail.
$vAbsent = Get-FieldProbeVerdict 400 '{"errors":[{"message":"errors:Cannot query field \"serverRowTotal\" on type \"Widget\".","extensions":{"code":"GRAPHQL_VALIDATION_FAILED"}}]}' 'serverRowTotal'
Assert ($vAbsent.present -eq $false) "P1 AC13 validation error naming the field => present false"
$vPresent = Get-FieldProbeVerdict 200 '{"data":{"widget":{"dateRange":{"primary":{"type":"PARENT"}}}}}' 'dateRange'
Assert ($vPresent.present -eq $true) "P1 AC13 200 with data and no errors => present true"
$v401 = Get-FieldProbeVerdict 401 '' 'filters'
Assert ($v401.present -eq 'unknown') "P1 AC13 a 401 is NOT evidence the field exists"
$vOther = Get-FieldProbeVerdict 400 '{"errors":[{"message":"errors:Cannot query field \"somethingElse\" on type \"Widget\".","extensions":{"code":"GRAPHQL_VALIDATION_FAILED"}}]}' 'filters'
Assert ($vOther.present -eq 'unknown') "P1 AC13 a validation error naming ANOTHER field says nothing about this one"
$vLong = Get-FieldProbeVerdict 500 ('x' * 900) 'filters'
Assert ($vLong.detail.Length -le 300) "P1 AC13 probe detail is bounded to 300 chars"
Assert ((Limit-ProbeDetail 'see https://swy.do/shares/AbC123_x-9 now') -notmatch 'AbC123_x-9') "P1 AC13 probe detail scrubs a share link"
$cands = @(Get-FieldProbeCandidates)
Assert ($cands.Count -eq 7) "P1 AC13 seven GraphQL probe candidates"
foreach($need in @('widget.serverRowTotal','widget.dateRange','widget.filters','widget.segments','metrics[].aggregation','dims[].isPartition')){
  Assert (@($cands | Where-Object { $_.field -eq $need }).Count -eq 1) "P1 AC13 probe covers the parent (c3) candidate $need"
}
# Blob-keys probe: node is a GraphQL leaf, so a row-level field is answered from the deserialized blob.
$bkNode = [pscustomobject]@{ node = [pscustomobject]@{ cells=@(1); isTotals=$true; meta=$null } }
$bk = Get-BlobKeyProbe ([pscustomobject]@{ data=[pscustomobject]@{ widget=[pscustomobject]@{ data=[pscustomobject]@{ edges=@($bkNode) } } } })
Assert ($bk.present -eq $false -and ($bk.observedKeys -contains 'isTotals')) "P1 AC13 blob-keys probe reports the observed node key set"

Write-Host "== ANLZ-aUniformLattice-7: an unfiltered report must not claim it was filtered =="
$pfEmpty = Parse-PlatformFilter $null
Assert ($null -ne $pfEmpty) "ANLZ-7 Parse-PlatformFilter never collapses to null (the unary-comma return)"
Assert (@($pfEmpty).Count -eq 0) "ANLZ-7 no filter => an EMPTY array, not null"
$jsonRt = ([ordered]@{ providerFilter=$pfEmpty } | ConvertTo-Json -Depth 100 -Compress)
Assert ($jsonRt -eq '{"providerFilter":[]}') "ANLZ-7 an empty filter serializes as [] and never as {} (got $jsonRt)"
$pfReal = Parse-PlatformFilter 'Google-Adwords, facebook-ads'
Assert ($pfReal.Count -eq 2) "ANLZ-7 a real filter still parses and lowercases"
Assert (($pfReal -join ',') -eq 'facebook-ads,google-adwords') "ANLZ-7 a real filter is still lowercased and sorted-unique"

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

# ============================================================================================
# EXTR-aPatientHarvest-1 - completeness under a slow Swydo backend.
# Offline throughout: a fake ClientWebSocket plus test-scope overrides of Invoke-GQL / Connect-Ws /
# Start-Sleep. No network, no sleeping.
# ============================================================================================
Write-Host "== aPatientHarvest: fake websocket harness =="

# A stand-in for ClientWebSocket. ReceiveAsync hands back a real Task<WebSocketReceiveResult> so the
# production Ws-Recv exercises its genuine Wait/Result/pending logic rather than a mock of it.
function New-FakeWs {
  $ws = [pscustomobject]@{ State='Open'; Q=(New-Object System.Collections.Queue); Sent=(New-Object System.Collections.ArrayList)
                           Disposed=$false; NextFaults=$false; LastTcs=$null; PendingSeg=$null; Receives=0 }
  Add-Member -InputObject $ws -MemberType ScriptMethod -Name ReceiveAsync -Value {
    param($seg,$ct)
    $this.Receives = $this.Receives + 1
    $this.PendingSeg = $seg
    $tcs = New-Object 'System.Threading.Tasks.TaskCompletionSource[System.Net.WebSockets.WebSocketReceiveResult]'
    $this.LastTcs = $tcs
    if($this.NextFaults){ $this.NextFaults=$false; $tcs.SetException((New-Object System.Exception('socket died'))); return $tcs.Task }
    if($this.Q.Count -gt 0){
      $b=[Text.Encoding]::UTF8.GetBytes([string]$this.Q.Dequeue())
      [Array]::Copy($b,0,$seg.Array,$seg.Offset,$b.Length)
      $tcs.SetResult((New-Object System.Net.WebSockets.WebSocketReceiveResult($b.Length,'Text',$true)))
    }
    return $tcs.Task
  }
  Add-Member -InputObject $ws -MemberType ScriptMethod -Name SendAsync -Value {
    param($seg,$type,$eom,$ct)
    [void]$this.Sent.Add([Text.Encoding]::UTF8.GetString($seg.Array,$seg.Offset,$seg.Count))
    $t = New-Object 'System.Threading.Tasks.TaskCompletionSource[bool]'; $t.SetResult($true); return $t.Task
  }
  Add-Member -InputObject $ws -MemberType ScriptMethod -Name Dispose -Value { $this.Disposed=$true }
  # Deliver a frame the way a real socket does: if a receive is already outstanding, COMPLETE it;
  # otherwise buffer for the next one. Without this the fake would only ever hand over frames that
  # were queued before ReceiveAsync was called, which is not how a push channel behaves.
  Add-Member -InputObject $ws -MemberType ScriptMethod -Name Push -Value {
    param($msg)
    if($this.LastTcs -and (-not $this.LastTcs.Task.IsCompleted) -and $this.PendingSeg){
      $b=[Text.Encoding]::UTF8.GetBytes([string]$msg)
      [Array]::Copy($b,0,$this.PendingSeg.Array,$this.PendingSeg.Offset,$b.Length)
      $this.LastTcs.SetResult((New-Object System.Net.WebSockets.WebSocketReceiveResult($b.Length,'Text',$true)))
    } else {
      [void]$this.Q.Enqueue([string]$msg)
    }
  }
  return $ws
}
# Complete a receive that was left pending, writing into the very buffer segment production handed us.
function Complete-FakeRecv($ws,$msg){
  $b=[Text.Encoding]::UTF8.GetBytes([string]$msg)
  [Array]::Copy($b,0,$ws.PendingSeg.Array,$ws.PendingSeg.Offset,$b.Length)
  $ws.LastTcs.SetResult((New-Object System.Net.WebSockets.WebSocketReceiveResult($b.Length,'Text',$true)))
}
$VERDICT_OK  = '{"kind":3,"payload":{"id":"dataRows:view:abc-1","status":"RESOLVED"}}'
$VERDICT_NO  = '{"kind":3,"payload":{"id":"dataRows:view:abc-2","status":"REJECTED"}}'
$KEEPALIVE   = '{"kind":4,"payload":{}}'
function RowsJson($n){
  $edges = @(); for($i=0;$i -lt $n;$i++){ $edges += '{"node":{"cells":[1]}}' }
  return ('{"data":{"widget":{"id":"w","content":null,"data":{"edges":[' + ($edges -join ',') + '],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}}')
}
$EMPTY_JSON = '{"data":{"widget":{"id":"w","content":null,"data":{"edges":[],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}}'

# Neutralise the two things that would reach outside the process.
function Start-Sleep { param([int]$Seconds,[int]$Milliseconds) }
function Connect-Ws {
  $script:connectCalls = $script:connectCalls + 1
  $script:pendingRecv = $null
  if($script:connectShouldWork){ $script:socketId='sock-reconnected'; return $true }
  $script:socketId=$null; return $false
}
function Setup-Fetch($plan){
  Reset-FetchState
  if($null -eq $plan){ $plan = Get-FetchPlan 2 }
  $script:fetchPlan=$plan; $script:runWaitCapSec=60; $script:socketId='sock1'
  $script:dr=$null; $script:cp=$null
  $script:connectCalls=0; $script:connectShouldWork=$true
  $script:gqlCalls=0; $script:gqlVars=(New-Object System.Collections.ArrayList)
  $script:lastFetchOutcome=$null
  return @{ plan=$plan; maxWaitSec=$plan.maxWaitSec }
}
$W = @{ id='w'; visual='TABLE' }
$srcPath = Join-Path $PSScriptRoot 'skill\scripts\Get-SwydoReport.ps1'

Write-Host "== AC1: a timed-out slice must not lose the frame that arrives next =="
Reset-FetchState
$fw = New-FakeWs; $script:ws=$fw
Assert ($null -eq (Ws-Recv 20)) "AC1 empty socket => null"
Assert ($null -ne $script:pendingRecv) "AC1 pending receive is HELD after a timed-out slice"
Complete-FakeRecv $fw $VERDICT_OK
$got = Ws-Recv 200
Assert ($got -eq $VERDICT_OK) "AC1 the late frame is delivered to the NEXT call (shipped code lost it)"
Assert ($null -eq $script:pendingRecv) "AC1 slot cleared once Result was read"
Assert ($fw.Receives -eq 1) "AC1 exactly ONE ReceiveAsync across both calls (no illegal concurrent receive)"

Write-Host "== AC14/AC15: a faulted receive must not deafen the run =="
Reset-FetchState
$fw2 = New-FakeWs; $script:ws=$fw2; $fw2.NextFaults=$true
$null = Ws-Recv 50
Assert ($null -eq $script:pendingRecv) "AC14 a faulted task is cleared, never re-awaited forever"
$fw3 = New-FakeWs; $script:ws=$fw3; [void]$fw3.Q.Enqueue($VERDICT_OK)
Assert ((Ws-Recv 200) -eq $VERDICT_OK) "AC14 receiver is live again after the fault"
Reset-FetchState
$fw4 = New-FakeWs; $script:ws=$fw4
$null = Ws-Recv 20
Assert ($null -ne $script:pendingRecv) "AC15 pending exists before reconnect"
[void](Connect-Ws)
Assert ($null -eq $script:pendingRecv) "AC15 reconnect drops the pre-reconnect receive (no resurrection)"
$srcConn = Get-Content $srcPath -Raw
Assert ($srcConn -match 'function Connect-Ws \{[^\r\n]*\r?\n\s*\$script:pendingRecv = \$null') "AC15 Connect-Ws nulls the pending slot as its FIRST statement"

Write-Host "== Get-FetchPlan / Get-WidgetOutcome (pure) =="
$pl = Get-FetchPlan 90
Assert ($pl.maxWaitSec -eq 90) "plan echoes maxWaitSec"
Assert ($pl.drainSliceMs -gt 0) "drainSliceMs is NON-zero (Wait(0) would no-op the drain)"
Assert ((Get-FetchPlan 0).maxWaitSec -eq 1) "plan floors maxWaitSec at 1"
Assert ((Get-FetchPlan $null).maxWaitSec -eq 90) "plan defaults to 90"
Assert ((Get-WidgetOutcome 'RESOLVED' 3 5000 0) -eq 'filled') "rows => filled"
Assert ((Get-WidgetOutcome $null 3 5000 0) -eq 'filled') "rows without a verdict => filled"
Assert ((Get-WidgetOutcome 'RESOLVED' 0 5000 0) -eq 'empty-resolved') "resolved + no rows => genuinely empty"
Assert ((Get-WidgetOutcome 'resolved' 0 5000 0) -eq 'empty-resolved') "verdict compare is case-insensitive"
Assert ((Get-WidgetOutcome 'REJECTED' 0 5000 0) -eq 'rejected') "refused => rejected"
Assert ((Get-WidgetOutcome $null 0 0 0) -eq 'incomplete') "no verdict => incomplete"
Assert ((Get-WidgetOutcome 'RESOLVED' 0 5000 1) -eq 'incomplete') "AC16 core: resolved+empty is NOT trusted while a compute is outstanding"
Assert ((Get-WidgetOutcome 'WHATEVER' 0 5000 0) -eq 'incomplete') "an unmapped status blocks conservatively"

Write-Host "== AC7/AC8: Get-ExtractionCompleteness (pure) =="
$plan90 = Get-FetchPlan 90
$bs = @{ maxTotalWaitSec=420; totalWaitedMs=1234; budgetExhausted=$false }
$cAll = Get-ExtractionCompleteness @(
  @{ id='a'; visual='KPI'; outcome='filled'; reason=$null; waitedMs=0; lastVerdict=$null; queries=1; pagesFetched=1 }
  @{ id='b'; visual='TABLE'; outcome='empty-resolved'; reason=$null; waitedMs=1200; lastVerdict='RESOLVED'; queries=2; pagesFetched=0 }
) $plan90 $bs
Assert ($cAll.extractionComplete -eq $true) "AC8 filled + empty-resolved => complete"
Assert (@($cAll.incompleteWidgets).Count -eq 0) "AC8 incompleteWidgets is an @()-wrapped EMPTY array"
Assert ($cAll.fetchBudget.totalWaitedMs -eq 1234) "fetchBudget carries what the run actually spent"
Assert ($cAll.fetchBudget.maxWaitSec -eq 90) "fetchBudget echoes the per-widget budget"
$cInc = Get-ExtractionCompleteness @(
  @{ id='a'; visual='KPI'; outcome='filled'; reason=$null; waitedMs=0; lastVerdict=$null; queries=1; pagesFetched=1 }
  @{ id='z'; visual='TABLE'; outcome='incomplete'; reason='budget-exhausted'; waitedMs=90000; lastVerdict=$null; queries=31; pagesFetched=0 }
) $plan90 $bs
Assert ($cInc.extractionComplete -eq $false) "AC7 one unverdicted widget => incomplete"
Assert (@($cInc.incompleteWidgets).Count -eq 1) "AC7 exactly the offending widget is listed"
Assert ($cInc.incompleteWidgets[0].id -eq 'z') "AC7 names the widget"
Assert ($cInc.incompleteWidgets[0].reason -eq 'budget-exhausted') "AC7 carries the reason"
$cRej = Get-ExtractionCompleteness @(@{ id='r'; visual='TABLE'; outcome='rejected'; reason=$null; waitedMs=50; lastVerdict='REJECTED'; queries=1; pagesFetched=0 }) $plan90 $bs
Assert ($cRej.extractionComplete -eq $false) "owner fork 3: REJECTED on the report path blocks publish"
Assert ($cRej.incompleteWidgets[0].reason -eq 'rejected') "rejected carries its own reason"
$cNull = Get-ExtractionCompleteness @() $plan90 $bs
Assert ($cNull.extractionComplete -eq $true) "no widgets => complete"
Assert (@($cNull.incompleteWidgets).Count -eq 0) "empty outcome set => empty array"

Write-Host "== AC2/AC3/AC4/AC5: verdict-driven fetch =="
$opt = Setup-Fetch $null
$fwA = New-FakeWs; $script:ws=$fwA
function Invoke-GQL($q,$vars,[switch]$NoRetry){ $script:gqlCalls++; [void]$script:gqlVars.Add($vars); return (RowsJson 3) }
$o = Fetch-Widget $W $null $null $opt
Assert ($script:gqlCalls -eq 1) "AC5 warm widget costs exactly ONE query"
Assert ($script:lastFetchOutcome.outcome -eq 'filled') "AC5 warm widget => filled"
Assert ($script:lastFetchOutcome.waitedMs -eq 0) "AC5 warm widget waits zero ms"
Assert (@($o.data.widget.data.edges).Count -eq 3) "AC5 the object is returned unchanged"

$opt = Setup-Fetch $null
$fwB = New-FakeWs; $script:ws=$fwB
# The verdict arrives AFTER the query that kicks off the compute, so it must be enqueued there. A
# frame queued before the call would be eaten by the pre-fire drain - correctly, since such a frame
# could only belong to a previous widget. That is exactly the mis-attribution AC16 covers.
function Invoke-GQL($q,$vars,[switch]$NoRetry){ $script:gqlCalls++; if($script:gqlCalls -eq 1){ $script:ws.Push($VERDICT_OK); return $EMPTY_JSON }; return (RowsJson 2) }
$o = Fetch-Widget $W $null $null $opt
Assert ($script:lastFetchOutcome.outcome -eq 'filled') "AC2 RESOLVED then rows => filled"
Assert ($script:gqlCalls -eq 2) "AC2 re-queries as soon as the verdict lands (2 calls, not a poll cycle)"
Assert ($script:lastFetchOutcome.lastVerdict -eq 'RESOLVED') "AC2 verdict recorded"

$opt = Setup-Fetch $null
$fwC = New-FakeWs; $script:ws=$fwC
function Invoke-GQL($q,$vars,[switch]$NoRetry){ $script:gqlCalls++; if($script:gqlCalls -eq 1){ $script:ws.Push($VERDICT_NO) }; return $EMPTY_JSON }
$o = Fetch-Widget $W $null $null $opt
Assert ($script:lastFetchOutcome.outcome -eq 'rejected') "AC3 REJECTED => rejected"
Assert ($script:gqlCalls -eq 1) "AC3 no re-query after a refusal (rows are never coming)"

$opt = Setup-Fetch $null
$fwD = New-FakeWs; $script:ws=$fwD
function Invoke-GQL($q,$vars,[switch]$NoRetry){ $script:gqlCalls++; if($script:gqlCalls -eq 1){ $script:ws.Push($KEEPALIVE); $script:ws.Push($VERDICT_OK); return $EMPTY_JSON }; return (RowsJson 1) }
$o = Fetch-Widget $W $null $null $opt
Assert ($script:lastFetchOutcome.outcome -eq 'filled') "AC4 keepalive does not end the wait"
Assert (@($fwD.Sent | Where-Object { $_ -match '"kind":5' }).Count -ge 1) "AC4 a kind:4 keepalive is answered with kind:5"

$opt = Setup-Fetch $null
$fwE = New-FakeWs; $script:ws=$fwE
function Invoke-GQL($q,$vars,[switch]$NoRetry){ $script:gqlCalls++; if($script:gqlCalls -eq 1){ $script:ws.Push($VERDICT_OK) }; return $EMPTY_JSON }
$o = Fetch-Widget $W $null $null $opt
Assert ($script:lastFetchOutcome.outcome -eq 'empty-resolved') "AC8 resolved + still empty => genuinely empty, not a failure"
Assert ($script:lastFetchOutcome.lastVerdict -eq 'RESOLVED') "AC8 the verdict that justified 'empty' is recorded"

Write-Host "== AC7 live / AC16: budget exhaustion and the stale-verdict trap =="
$opt = Setup-Fetch (Get-FetchPlan 1)
$fwF = New-FakeWs; $script:ws=$fwF
function Invoke-GQL($q,$vars,[switch]$NoRetry){ $script:gqlCalls++; return $EMPTY_JSON }
$o = Fetch-Widget $W $null $null $opt
Assert ($script:lastFetchOutcome.outcome -eq 'incomplete') "AC7 silent socket => incomplete"
Assert ($script:lastFetchOutcome.reason -eq 'budget-exhausted') "AC7 reason is budget-exhausted"
Assert ($script:connectCalls -ge 1) "AC16 an unverdicted widget forces a reconnect, orphaning its compute"
Assert ($script:outstandingComputes -eq 0) "AC16 a SUCCESSFUL reconnect clears the outstanding counter"

$opt = Setup-Fetch (Get-FetchPlan 1)
$script:connectShouldWork = $false
$fwG = New-FakeWs; $script:ws=$fwG
function Invoke-GQL($q,$vars,[switch]$NoRetry){ $script:gqlCalls++; return $EMPTY_JSON }
$o = Fetch-Widget $W $null $null $opt
Assert ($script:outstandingComputes -ge 1) "AC16 a failed reconnect leaves the compute outstanding"
$script:socketId='sock1'; $script:gqlCalls=0     # count B's queries, not A's
$fwH = New-FakeWs; $script:ws=$fwH
# Widget A's compute finishes late and pushes ITS verdict while widget B is waiting. Reading that as
# B's answer is the silent-gap bug: B would be certified 'empty-resolved' and ship as zero activity.
function Invoke-GQL($q,$vars,[switch]$NoRetry){ $script:gqlCalls++; if($script:gqlCalls -eq 1){ $script:ws.Push($VERDICT_OK) }; return $EMPTY_JSON }
$o = Fetch-Widget @{ id='wB'; visual='TABLE' } $null $null $opt
Assert ($script:lastFetchOutcome.outcome -eq 'incomplete') "AC16 a stale RESOLVED does NOT certify widget B as empty"
Assert ($script:lastFetchOutcome.reason -eq 'stale-verdict-risk') "AC16 the reason names the risk"

Write-Host "== AC6/AC17: transport faults never truncate silently =="
$opt = Setup-Fetch (Get-FetchPlan 1)
$fwI = New-FakeWs; $script:ws=$fwI; [void]$fwI.Q.Enqueue($VERDICT_OK)
function Invoke-GQL($q,$vars,[switch]$NoRetry){ $script:gqlCalls++; if($script:gqlCalls -eq 1){ return (New-FetchFailure 'transport' 3 'timed out') }; return (RowsJson 2) }
$o = Fetch-Widget $W $null $null $opt
Assert ($script:lastFetchOutcome.outcome -eq 'incomplete') "AC6 a transport fault ends the widget, it does not kill the run"
Assert ($script:lastFetchOutcome.reason -eq 'transport-failed') "AC6 reason is transport-failed"
Assert (Test-FetchFailed (New-FetchFailure 'transport' 3 'x')) "the failure marker is recognisable"
Assert (-not (Test-FetchFailed '{"data":{}}')) "a JSON string is NOT a failure marker"
Assert (-not (Test-FetchFailed $null)) "null is not a failure marker"

$opt = Setup-Fetch $null
$fwJ = New-FakeWs; $script:ws=$fwJ
$P1 = '{"data":{"widget":{"id":"w","content":null,"data":{"edges":[{"node":{"cells":[1]}}],"pageInfo":{"hasNextPage":true,"endCursor":"CUR1"}}}}}'
function Invoke-GQL($q,$vars,[switch]$NoRetry){ $script:gqlCalls++; if($script:gqlCalls -eq 1){ return $P1 }; return (New-FetchFailure 'transport' 3 'page 2 died') }
$o = Fetch-Widget $W $null $null $opt
Assert ($script:lastFetchOutcome.outcome -eq 'incomplete') "AC17 a faulted page is NOT a last page"
Assert ($script:lastFetchOutcome.reason -eq 'partial-pages') "AC17 reason is partial-pages"
Assert ($script:lastFetchOutcome.endCursor -eq 'CUR1') "AC17 records where the truncation happened"
$cPart = Get-ExtractionCompleteness @($script:lastFetchOutcome) (Get-FetchPlan 90) @{ maxTotalWaitSec=420; totalWaitedMs=0; budgetExhausted=$false }
Assert ($cPart.extractionComplete -eq $false) "AC17 a truncated widget makes the extraction incomplete"

Write-Host "== AC12/AC18: run budget and socket loss =="
$opt = Setup-Fetch (Get-FetchPlan 5)
$script:runWaitCapSec = 0
function Invoke-GQL($q,$vars,[switch]$NoRetry){ $script:gqlCalls++; return $EMPTY_JSON }
$o = Fetch-Widget $W $null $null $opt
Assert ($script:lastFetchOutcome.outcome -eq 'incomplete') "AC12 an exhausted run budget ends the widget"
Assert ($script:lastFetchOutcome.reason -eq 'run-budget-exhausted') "AC12 reason distinguishes run budget from widget budget"
Assert ($script:gqlCalls -eq 0) "AC12 no query is issued once the run budget is gone"

$opt = Setup-Fetch (Get-FetchPlan 5)
$script:connectShouldWork=$false; $script:socketId=$null
function Invoke-GQL($q,$vars,[switch]$NoRetry){ $script:gqlCalls++; return $EMPTY_JSON }
$o = Fetch-Widget $W $null $null $opt
Assert ($script:lastFetchOutcome.reason -eq 'socket-lost') "AC18 no socketId => socket-lost, not a full-budget wait"
Assert ($script:gqlCalls -eq 0) "AC18 never queries without a socketId"
Reset-FetchState
$script:fetchPlan=(Get-FetchPlan 5); $script:connectShouldWork=$false; $script:connectCalls=0
$r1=Reset-Socket; $r2=Reset-Socket; $r3=Reset-Socket; $r4=Reset-Socket
Assert ((-not $r1) -and (-not $r4)) "AC18 failed reconnects report failure"
Assert ($script:connectCalls -eq (Get-FetchPlan 5).maxReconnects) "AC18 reconnect attempts stop exactly at maxReconnects"

Write-Host "== AC19: the request the run body sends is byte-identical to pre-change =="
$opt = Setup-Fetch $null
$script:dr = [pscustomobject]@{ primary=[pscustomobject]@{ count=-1; measure='quarter'; type='RELATIVE' } }
$script:cp = 'PREVIOUS_PERIOD'
$fwK = New-FakeWs; $script:ws=$fwK
function Invoke-GQL($q,$vars,[switch]$NoRetry){ $script:gqlCalls++; [void]$script:gqlVars.Add($vars); return (RowsJson 1) }
$null = Fetch-Widget $W $null $null $opt
$v = $script:gqlVars[0]
Assert ($v.sid -eq 'sock1') "AC19 socketId unchanged"
Assert ($v.cp -eq 'PREVIOUS_PERIOD') "AC19 compare period unchanged"
Assert ($v.dr.primary.measure -eq 'quarter') "AC19 a null dr still resolves to the report range"
Assert ($null -eq $v.after) "AC19 first page still asks after=null"

Write-Host "== AC23: the drain consumes a leftover verdict =="
Reset-FetchState
$script:fetchPlan=(Get-FetchPlan 2)
$fwL = New-FakeWs; $script:ws=$fwL; [void]$fwL.Q.Enqueue($VERDICT_OK); [void]$fwL.Q.Enqueue($KEEPALIVE)
$n = Drain-Ws $script:fetchPlan
Assert ($n -eq 2) "AC23 the drain consumes everything already buffered"
Assert ($null -eq (Ws-Recv 20)) "AC23 nothing is left to be mistaken for the next widget's verdict"

Write-Host "== AC11: ceiling evidence (pure) =="
Assert (Test-CeilingStillValid ([ordered]@{ state='has-months'; months=@('2025-01','2025-02') }) 2) "months present => admissible"
Assert (-not (Test-CeilingStillValid ([ordered]@{ state='rejected'; months=@() }) 2)) "a refusal is not evidence of history"
Assert (-not (Test-CeilingStillValid ([ordered]@{ state='unsettled'; months=@() }) 2)) "an unanswered window is NEVER read as a ceiling"
Assert (-not (Test-CeilingStillValid ([ordered]@{ state='empty-resolved'; months=@() }) 2)) "resolved-but-empty carries no months"
Assert (-not (Test-CeilingStillValid $null 2)) "null probe => not admissible"
Assert (-not (Test-CeilingStillValid ([ordered]@{ state='has-months'; months=@('2025-01','2025-03') }) 2)) "gapped months => not admissible"

Write-Host "== Get-TrendMonthCells: unsettled is not overshoot =="
$emptyW = W ([pscustomobject]@{ metrics=(FieldsConn @()); dims=(FieldsConn @([pscustomobject]@{name='Month';id='d:month'})); data=[pscustomobject]@{edges=@()} })
Assert ((Get-TrendMonthCells $emptyW).windowStatus -eq 'overshoot-empty') "empty with no outcome => overshoot-empty (unchanged)"
Assert ((Get-TrendMonthCells $emptyW @{ outcome='incomplete' }).windowStatus -eq 'unsettled') "empty from an INCOMPLETE fetch => unsettled, never overshoot"
Assert ((Get-TrendMonthCells (W $null) @{ outcome='incomplete' }).windowStatus -eq 'unsettled') "null widget from an incomplete fetch => unsettled"
Assert ((Get-TrendMonthCells (W $null)).windowStatus -eq 'error') "null widget with no outcome => error (unchanged)"

Write-Host "== Count-Edges: the @(`$null).Count trap (caught by live verification) =="
# @($null).Count is 1. Left unguarded, a null edge list reads as ONE row and an empty widget is
# classified 'filled' - the exact silent failure this unit exists to prevent.
Assert ((Count-Edges $null) -eq 0) "null object => 0 rows, not 1"
Assert ((Count-Edges (W $null)) -eq 0) "null widget => 0 rows, not 1"
Assert ((Count-Edges (W ([pscustomobject]@{ data=$null }))) -eq 0) "null data => 0 rows, not 1"
Assert ((Count-Edges (W ([pscustomobject]@{ data=[pscustomobject]@{ edges=$null } }))) -eq 0) "null edges => 0 rows, not 1"
Assert ((Count-Edges (W ([pscustomobject]@{ data=[pscustomobject]@{ edges=@() } }))) -eq 0) "empty edges => 0 rows"
Assert ((Count-Edges (($EMPTY_JSON | ConvertFrom-Json))) -eq 0) "a real empty response => 0 rows"
Assert ((Count-Edges (((RowsJson 3) | ConvertFrom-Json))) -eq 3) "a real 3-row response => 3 rows"
Assert ((Count-Edges (((RowsJson 1) | ConvertFrom-Json))) -eq 1) "a genuine single row is still 1 (not confused with the null case)"
# and end to end: a widget whose response has no edges must never come back 'filled'
$opt = Setup-Fetch (Get-FetchPlan 1)
$fwM = New-FakeWs; $script:ws=$fwM
function Invoke-GQL($q,$vars,[switch]$NoRetry){ $script:gqlCalls++; return '{"data":{"widget":{"id":"w","content":null,"data":null}}}' }
$o = Fetch-Widget $W $null $null $opt
Assert ($script:lastFetchOutcome.outcome -ne 'filled') "a null data block never classifies as filled"

Write-Host "== AC22: no unbounded network call may exist in the extractor =="
$srcG = Get-Content $srcPath -Raw
$callSites = @([regex]::Matches($srcG,'Invoke-(WebRequest|RestMethod)[^\r\n]*'))
Assert ($callSites.Count -ge 3) "AC22 the scan actually found the call sites (guard against a silent zero-match pass)"
$unbounded = @($callSites | Where-Object { $_.Value -notmatch '-TimeoutSec' })
Assert ($unbounded.Count -eq 0) ("AC22 every HTTP call passes -TimeoutSec (unbounded: " + (@($unbounded | ForEach-Object { $_.Value.Trim() }) -join ' | ') + ")")
Assert (@([regex]::Matches($srcG,'\.Wait\(\s*\)')).Count -eq 0) "AC22 no .Wait() is called without a bound"

Write-Host ""
Write-Host ("RESULT: {0} passed, {1} failed" -f $pass, $fail) -ForegroundColor $(if($fail){'Red'}else{'Green'})
if($fail){ exit 1 }
