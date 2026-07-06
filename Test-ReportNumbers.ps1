<#
.SYNOPSIS
  Deterministically verify a /swydee client report against its facts file:
  every measure number traces to a facts display string, comparison claims are
  backed by comparison data, required findings/caveats are surfaced, no credential leaks.

.DESCRIPTION
  The mechanized half of "the numbers check out". No model judgment here - a pure
  offline tracer (PS 5.1 / .NET only). Functions-first; dot-source with -DefineOnly for
  unit tests. Reads nothing but the two inputs; writes nothing; exits 1 on any violation.

  Checks (per reconciled UNIT_closer_spec review outcome):
   1 tracing        - every measure token in prose matches a typed, platform-scoped fact
                      display string within display tolerance.
   2 comparison     - a comparative claim on a value whose only candidates are
                      hasComparison=false is flagged.
   3 surfacing      - every finding sev>=major OR requiresDownstreamData must echo its
                      fid as <!-- finding:<fid> -->; every comparisonCaveat must appear;
                      a surfaced requiresDownstreamData finding needs a downstream clause.
   4 hygiene        - the report must contain no share-key credential pattern.

.PARAMETER Report   Path to the generated report .md
.PARAMETER Facts    Path to the *.facts.json produced by Analyze-SwydoReport.ps1
.PARAMETER TraceRecommendations  Also trace numbers inside "## Recommendations" (default: skip -
                    recommendations carry proposed targets/thresholds that are not facts).
.PARAMETER DefineOnly  Define functions and exit (for unit tests). No file I/O, no exit code.
#>
param(
  [string]$Report,
  [string]$Facts,
  [switch]$TraceRecommendations,
  [switch]$DefineOnly
)
$ErrorActionPreference = 'Stop'

# ---- constants (ASCII source; currency symbols via [char] to survive PS 5.1 decoding) ----
$script:CurClass = '[\$' + [char]0x20AC + [char]0xA3 + ']'          # $ EUR GBP
$script:DashRx  = '[' + [char]0x2212 + [char]0x2013 + [char]0x2014 + ']'   # minus / en / em dash
$script:TildeRx = '[~' + [char]0x2248 + ']'                                # ~ / approx
# Master token regex - ordered alternation, exempt shapes first so "25-34"/"3x"/"2026" win.
$script:TokRx = '(?<mult>\d+(?:\.\d+)?\s*[xX])' +
                '|(?<range>\d+\s*-\s*\d+)' +
                '|(?<bucket>\d+\+)' +
                '|(?<cur>' + $script:CurClass + '\s?\d[\d,]*(?:\.\d+)?\s*[KMB]?)' +
                '|(?<pct>[+-]?\d[\d,]*(?:\.\d+)?\s*%)' +
                '|(?<year>20\d\d)' +
                '|(?<bare>\d[\d,]*(?:\.\d+)?\s*[KMB]?)'
# Comparative verbs (conservative - excludes idiomatic bare up/down to avoid false positives).
$script:CmpRx = '(?i)\b(grew|grow|grown|growth|fell|fall|fallen|rose|rise|risen|declin\w*|' +
                'increas\w*|decreas\w*|higher|lower|improv\w*|worse|worsen\w*|dropp?\w*|' +
                'climb\w*|surg\w*|plung\w*|gained?|lost|vs\.?|year-over-year|' +
                'quarter-over-quarter|QoQ|YoY|compared)\b'
# Credential leak patterns (fail-closed).
$script:CredRx = 'swy\.do/shares/[A-Za-z0-9]+|/g/[A-Za-z0-9]{20,}/reports/'
# Downstream / lead-quality clause (for requiresDownstreamData findings).
$script:DownRx = '(?i)(downstream|lead[- ]quality|lead quality|conversion quality|' +
                 'qualit\w* of (the )?leads|confirm\w*.{0,40}(sales|crm|close|revenue))'

function Normalize-Num($s){
  # -> [double] (K/M/B expanded, symbols/commas/percent/plus stripped), or $null.
  if($null -eq $s){ return $null }
  $t = ([string]$s).Trim()
  $t = $t -replace $script:DashRx,'-'
  $t = $t -replace '(?i)^\s*(about|approx\.?|around|nearly|almost)\s+',''
  $t = $t -replace $script:TildeRx,''
  $mult = 1.0
  $m = [regex]::Match($t,'(?i)([kmb])\s*$')
  if($m.Success){
    switch($m.Groups[1].Value.ToUpper()){ 'K'{$mult=1e3} 'M'{$mult=1e6} 'B'{$mult=1e9} }
    $t = $t.Substring(0,$m.Index)
  }
  $neg = $t.TrimStart().StartsWith('-')
  $core = $t -replace '[^0-9\.]',''                   # digits + dot only
  if($core -eq '' -or $core -eq '.'){ return $null }
  $d = 0.0
  if([double]::TryParse($core,[ref]$d)){
    if($neg){ $d = -$d }
    return [double]($d * $mult)
  }
  return $null
}

function Type-FromDisplay($s){
  if($null -eq $s){ return 'number' }
  $t = [string]$s
  if($t -match $script:CurClass){ return 'currency' }
  if($t -match '%'){ return 'percent' }
  return 'number'
}

function Get-MeasureTokens($text){
  # Returns [ordered]@{ raw; value; type; index; signed } for MEASURE tokens only.
  # Exempts years, quarters, buckets (\d+\+), ranges (25-34), multipliers (3x),
  # and small bare integers (<100, no comma/decimal).
  $out = New-Object System.Collections.ArrayList
  if($null -eq $text){ return $out }
  $norm = ([string]$text) -replace $script:DashRx,'-'
  foreach($mm in [regex]::Matches($norm,$script:TokRx)){
    $g = $mm.Groups
    if($g['mult'].Success -or $g['range'].Success -or $g['bucket'].Success -or $g['year'].Success){ continue }
    $raw = $mm.Value.Trim()
    $type = 'number'; $isMeasure = $false
    if($g['cur'].Success){ $type='currency'; $isMeasure=$true }
    elseif($g['pct'].Success){ $type='percent'; $isMeasure=$true }
    elseif($g['bare'].Success){
      $type='number'
      $hasSep = ($raw -match ',') -or ($raw -match '\.') -or ($raw -match '(?i)[kmb]$')
      $val0 = Normalize-Num $raw
      if($hasSep -or ($null -ne $val0 -and [math]::Abs($val0) -ge 100)){ $isMeasure=$true }
    }
    if(-not $isMeasure){ continue }
    $v = Normalize-Num $raw
    if($null -eq $v){ continue }
    [void]$out.Add([ordered]@{ raw=$raw; value=$v; type=$type; index=$mm.Index; signed=($raw -match '^[+-]') })
  }
  return $out
}

function Add-Candidate($list,$disp,$hasCmp){
  $v = Normalize-Num $disp
  if($null -eq $v){ return }
  [void]$list.Add([ordered]@{ value=$v; type=(Type-FromDisplay $disp); hasComparison=[bool]$hasCmp })
}

function Add-StringNumbers($list,$str){
  foreach($t in @(Get-MeasureTokens $str)){
    [void]$list.Add([ordered]@{ value=$t.value; type=$t.type; hasComparison=$true })
  }
}

function Build-FactIndex($facts){
  # -> @{ global=[..]; byPlatform=@{id->[..]}; nameToId=@{name->id} }
  $global   = New-Object System.Collections.ArrayList
  $byPlat   = @{}
  $nameToId = @{}
  foreach($p in @($facts.platforms)){
    $plid = [string]$p.id
    $plist = New-Object System.Collections.ArrayList
    $byPlat[$plid] = $plist
    if($p.name){ $nameToId[[string]$p.name] = $plid }
    # headline
    if($p.headline){
      foreach($hk in $p.headline.PSObject.Properties.Name){
        $h = $p.headline.$hk
        Add-Candidate $plist $h.displayCurrent  $h.hasComparison
        Add-Candidate $plist $h.displayPrevious $h.hasComparison
        Add-Candidate $plist $h.displayDelta    $true
      }
    }
    # breakdown rows
    foreach($bd in @($p.breakdowns)){
      foreach($row in @($bd.rows)){
        if(-not $row.values){ continue }
        foreach($mn in $row.values.PSObject.Properties.Name){
          $cell = $row.values.$mn
          Add-Candidate $plist $cell.display $cell.hasComparison
          if($cell.PSObject.Properties.Name -contains 'displayPrevious'){ Add-Candidate $plist $cell.displayPrevious $cell.hasComparison }
          if($cell.PSObject.Properties.Name -contains 'delta'){ Add-Candidate $plist $cell.delta $true }
        }
      }
    }
    # time series (derived + pacing series + netChange; maxVsMinRatio is a multiplier -> exempt)
    foreach($ts in @($p.timeSeries)){
      foreach($b in @($ts.buckets)){
        if($b.derived){ foreach($dn in $b.derived.PSObject.Properties.Name){ Add-Candidate $plist $b.derived.$dn $false } }
      }
      if($ts.pacing){
        foreach($sp in @($ts.pacing.series)){ Add-Candidate $plist $sp.display $false }
        if($ts.pacing.PSObject.Properties.Name -contains 'netChange'){ Add-Candidate $plist $ts.pacing.netChange $true }
      }
    }
    foreach($c in $plist){ [void]$global.Add($c) }
  }
  # findings -> global (and the finding's own platform list, so per-platform paraphrases trace)
  if($facts.findings){
    foreach($cat in @('wins','losses','anomalies','discrepancies','dataGaps')){
      foreach($f in @($facts.findings.$cat)){
        $targets = ,$global   # (,$x keeps the ArrayList as one element; @($x) would flatten it)
        if($f.platform -and $nameToId.ContainsKey([string]$f.platform)){ $targets += ,$byPlat[$nameToId[[string]$f.platform]] }
        foreach($tl in $targets){
          Add-StringNumbers $tl $f.statement
          if($f.evidence){ foreach($ek in $f.evidence.PSObject.Properties.Name){ Add-StringNumbers $tl ([string]$f.evidence.$ek) } }
        }
      }
    }
  }
  return @{ global=$global; byPlatform=$byPlat; nameToId=$nameToId }
}

function Find-Candidates($tok,$cands){
  # matching = same type + |value| within display tolerance (percent: 0.5 abs; else max(0.5, 1% rel))
  $hits = New-Object System.Collections.ArrayList
  $a = [math]::Abs($tok.value)
  foreach($c in $cands){
    if($c.type -ne $tok.type){ continue }
    $b = [math]::Abs($c.value)
    if($tok.type -eq 'percent'){ $tol = 0.5 } else { $tol = [math]::Max(0.5, 0.01*$b) }
    if([math]::Abs($a-$b) -le $tol){ [void]$hits.Add($c) }
  }
  return $hits
}

function Split-Sections($reportText){
  # -> list of @{ header; kind(platform|recommendations|general); platformId; text }
  $sections = New-Object System.Collections.ArrayList
  $lines = ($reportText -replace "`r`n","`n") -split "`n"
  $cur = [ordered]@{ header='(intro)'; kind='general'; platformId=$null; lines=(New-Object System.Collections.ArrayList) }
  function _finalize($s){
    $txt = ($s.lines -join "`n")
    $secpid = $null
    $pm = [regex]::Match($txt,'<!--\s*platform:([^\s]+?)\s*-->')
    if($pm.Success){ $secpid = $pm.Groups[1].Value }
    $kind = 'general'
    if($s.header -match '(?i)recommend'){ $kind='recommendations' }
    elseif($secpid){ $kind='platform' }
    return [ordered]@{ header=$s.header; kind=$kind; platformId=$secpid; text=$txt }
  }
  foreach($ln in $lines){
    $hm = [regex]::Match($ln,'^(#{2,})\s+(.*)$')
    if($hm.Success){
      [void]$sections.Add((_finalize $cur))
      $cur = [ordered]@{ header=$hm.Groups[2].Value.Trim(); kind='general'; platformId=$null; lines=(New-Object System.Collections.ArrayList) }
    } else {
      [void]$cur.lines.Add($ln)
    }
  }
  [void]$sections.Add((_finalize $cur))
  return $sections
}

function Invoke-Closer($reportText, $facts, [switch]$TraceRecs){
  $violations = New-Object System.Collections.ArrayList
  $measured = 0; $traced = 0
  $index = Build-FactIndex $facts
  $sections = Split-Sections $reportText

  # 1 + 2: per-section number tracing and comparison guard
  foreach($sec in $sections){
    if($sec.kind -eq 'recommendations' -and -not $TraceRecs){ continue }
    $scope = $index.global
    if($sec.kind -eq 'platform' -and $sec.platformId -and $index.byPlatform.ContainsKey($sec.platformId)){ $scope = $index.byPlatform[$sec.platformId] }
    $toks = @(Get-MeasureTokens $sec.text)
    # comparative-word char positions in this section
    $cmpPos = @(); foreach($cm in [regex]::Matches($sec.text,$script:CmpRx)){ $cmpPos += $cm.Index }
    foreach($tok in $toks){
      $measured++
      $hits = Find-Candidates $tok $scope
      if($hits.Count -gt 0){
        $traced++
      } else {
        [void]$violations.Add([ordered]@{ type='untraceable-number'; section=$sec.header; detail="'$($tok.raw)' ($($tok.type)) has no matching fact in scope"; snippet=$tok.raw })
        continue
      }
      # comparison guard: token is a comparison claim if it is signed, or a comparative verb is near it
      $isCmp = $tok.signed
      if(-not $isCmp){ foreach($cp in $cmpPos){ if([math]::Abs($cp-$tok.index) -le 40){ $isCmp=$true; break } } }
      if($isCmp){
        $anyCmp = $false; foreach($h in $hits){ if($h.hasComparison){ $anyCmp=$true; break } }
        if(-not $anyCmp){
          [void]$violations.Add([ordered]@{ type='comparison-without-data'; section=$sec.header; detail="comparison claim on '$($tok.raw)' but the matching fact(s) have no comparison data"; snippet=$tok.raw })
        }
      }
    }
  }

  # 3a: surfacing gate - findings sev>=major OR requiresDownstreamData must echo their fid
  $reqDownSurfaced = $false
  if($facts.findings){
    foreach($cat in @('wins','losses','anomalies','discrepancies','dataGaps')){
      foreach($f in @($facts.findings.$cat)){
        $sev = [string]$f.severity
        $mustSurface = ($sev -in @('major','critical','high')) -or ($f.requiresDownstreamData -eq $true)
        if(-not $mustSurface){ continue }
        $fid = [string]$f.fid
        if($fid -and $reportText.Contains("finding:$fid")){
          if($f.requiresDownstreamData -eq $true){ $reqDownSurfaced = $true }
        } else {
          $sn = [string]$f.statement; if($sn.Length -gt 80){ $sn = $sn.Substring(0,80) + '...' }
          [void]$violations.Add([ordered]@{ type='unsurfaced-finding'; section=$cat; detail="[$($f.ruleId) sev=$sev] not surfaced (missing <!-- finding:$fid -->)"; snippet=$sn })
        }
      }
    }
  }

  # 3b: required caveats (seasonality) must appear
  if($facts.meta -and @($facts.meta.comparisonCaveats).Count -gt 0){
    if($reportText -notmatch '(?i)seasonalit'){
      [void]$violations.Add([ordered]@{ type='missing-caveat'; section='(report)'; detail='comparisonCaveats present in facts but no seasonality caveat in report'; snippet='seasonality' })
    }
  }

  # 3c: a surfaced requiresDownstreamData finding needs a downstream/lead-quality clause somewhere
  if($reqDownSurfaced -and ($reportText -notmatch $script:DownRx)){
    [void]$violations.Add([ordered]@{ type='missing-downstream-caveat'; section='(report)'; detail='a surfaced requiresDownstreamData finding has no downstream/lead-quality clause'; snippet='downstream/lead-quality' })
  }

  # 4: credential hygiene (fail-closed)
  foreach($cm in [regex]::Matches($reportText,$script:CredRx)){
    [void]$violations.Add([ordered]@{ type='credential-leak'; section='(report)'; detail='report contains a Swydo share-key pattern'; snippet=$cm.Value })
  }

  return [ordered]@{ measuresChecked=$measured; traced=$traced; violations=$violations }
}

if($DefineOnly){ return }

# ---- run ----
if(-not $Report -or -not $Facts){ Write-Error 'Usage: Test-ReportNumbers.ps1 -Report <report.md> -Facts <facts.json>'; exit 2 }
if(-not (Test-Path $Report)){ Write-Error "Report not found: $Report"; exit 2 }
if(-not (Test-Path $Facts)){ Write-Error "Facts not found: $Facts"; exit 2 }

$reportText = [IO.File]::ReadAllText($Report)
$factsText  = [IO.File]::ReadAllText($Facts)
# NB: name the parsed object $factsObj, NOT $facts - $facts collides (case-insensitively) with the
# [string]-typed $Facts param and would coerce the PSCustomObject back to a string.
$factsObj = $factsText | ConvertFrom-Json

$res = Invoke-Closer $reportText $factsObj -TraceRecs:$TraceRecommendations

Write-Host ("Test-ReportNumbers: {0} measure numbers checked, {1} traced, {2} violation(s)." -f $res.measuresChecked,$res.traced,$res.violations.Count)
if($res.violations.Count -eq 0){
  Write-Host 'PASS - all numbers trace; required findings/caveats present; no credential leak.'
  exit 0
}
$byType = $res.violations | Group-Object { $_.type }   # script-block: reads the key off the ordered-dict
foreach($grp in $byType){
  Write-Host ''
  Write-Host ("[{0}] x{1}" -f $grp.Name,$grp.Count)
  foreach($v in $grp.Group){ Write-Host ("  - ({0}) {1}" -f $v.section,$v.detail) }
}
Write-Host ''
Write-Host ("FAIL - {0} violation(s)." -f $res.violations.Count)
exit 1
