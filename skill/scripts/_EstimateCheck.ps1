<#
.SYNOPSIS
  The closer's rules for MODELED ESTIMATES (facts.estimates, written by Invoke-SwydoForecast.ps1).
.DESCRIPTION
  Dot-sourced by Test-ReportNumbers.ps1 (which supplies Normalize-Num, Type-FromDisplay, Map-CellType,
  Get-Ulp, Get-MeasureTokens, Find-Candidates). Kept in its own file so the closer carries only hooks.

  An estimate is not a measurement and must never be mistaken for one:
    * its numbers trace ONLY on a line echoing <!-- estimate:EST#n -->,
    * that line must sit directly under the heading "Estimates (modeled)" (exactly that, no sub-headings),
    * that line must carry a visible estimate word (anchors are stripped from the client copy),
    * that line must not compare the estimate with a previous period,
    * every action / total estimate is presented, with its base, its low and its high,
    * the section says in plain words that the figures are not measured,
    * an estimate number anywhere else is flagged as misuse - including inside Recommendations, which
      the tracer otherwise skips, and including a rounded "about 57" of an estimated 56.7,
    * no internal id (EST#n) is visible and no estimate anchor sits on a heading. (A comment spanning
      lines, which could hide a heading or a label from the client copy only, is rejected for every
      report by _CloserGaps.ps1.)
  Everything here is inert when the facts carry no `estimates` block and the report no estimate
  anchor, so every pre-existing facts file verifies exactly as before.
#>
$script:EstAnchorRx  = '<!--\s*estimate:([^\s]+?)\s*-->'
$script:EstSectionRx = '^\s*estimates?\s*\(\s*model+ed\s*\)\s*$'
$script:EstWordRx    = '(?i)\b(estimate[ds]?|model+ed|projected|projection)\b'
# a negator, at most three plain words (no punctuation), then measured / measurement(s)
$script:EstNotMeasRx = '(?i)(\bnot\b|n[''' + [char]0x2019 + ']t\b|\bnever\b|\brather than\b|\binstead of\b)(\s+[\w-]+){0,3}?\s+measure(d|ments?)\b'
# a COMPARISON with another period: a comparing word followed (same clause) by last/previous/prior <period>.
# "last period's level" on its own is how a prior-level method is described, and is allowed.
$script:EstPrevRx    = '(?i)\b(from|than|versus|vs\.?|against|compared (?:to|with))\b[^.;]{0,40}?\b(last|previous|prior)\s+(period|month|week|quarter|year)\b(?![''' + [char]0x2019 + ']s\s+(level|rate|value|pace))|\b(vs\.?|versus)\s+(last|previous|prior)\b|\b(MoM|YoY|QoQ)\b|\b(month|quarter|year|week|period)-over-(month|quarter|year|week|period)\b'
$script:EstApproxIntRx = '(?i)(?:\b(?:about|around|roughly|approximately|approx\.?|nearly|almost|estimated|projected|model+ed)\s+|[~' + [char]0x2248 + ']\s*)(\d[\d,]*)(?![\d.,]*\d)(?!\s*%)'
$script:EstNoEid = 0

function Add-EstimateCandidate($list,$disp,$type,$role){
  $v = Normalize-Num $disp
  if($null -eq $v){ return }
  if($type){ $ty = Map-CellType $type } else { $ty = Type-FromDisplay $disp }
  # hasComparison=$true: an estimate line may say "against the 614.6 recorded" - the comparison guard is
  # for measured cells. A comparison with a PREVIOUS PERIOD is refused separately (Test-EstimateLine).
  [void]$list.Add([ordered]@{ value=$v; type=$ty; hasComparison=$true; ulp=(Get-Ulp $disp); est=$true; role=$role })
}
function Add-EstimateProse($list,$str){
  if(-not $str){ return }
  foreach($t in @(Get-MeasureTokens ([string]$str))){ [void]$list.Add([ordered]@{ value=$t.value; type=$t.type; hasComparison=$true; ulp=(Get-Ulp $t.raw); est=$true; role='prose' }) }
}
function Build-EstimateIndex($facts){
  # -> @{ eid -> @{ item; cands } }. Empty when the facts carry no estimates block.
  $idx = @{}
  $script:EstNoEid = 0
  if(-not $facts -or -not ($facts.PSObject.Properties.Name -contains 'estimates') -or -not $facts.estimates){ return $idx }
  foreach($it in @($facts.estimates.items)){
    if(-not $it){ continue }
    $eid = [string]$it.eid
    if(-not $eid){ $script:EstNoEid++; continue }
    $cands = New-Object System.Collections.ArrayList
    Add-EstimateCandidate $cands $it.display     $it.type 'base'
    Add-EstimateCandidate $cands $it.displayLow  $it.type 'low'
    Add-EstimateCandidate $cands $it.displayHigh $it.type 'high'
    Add-EstimateCandidate $cands $it.measuredDisplay $it.type 'measured'
    foreach($m in @($it.methods)){
      if(-not $m){ continue }
      Add-EstimateCandidate $cands $m.display $null 'method'
      foreach($in in @($m.inputs)){ if($in){ Add-EstimateCandidate $cands $in.display $null 'input' } }
      Add-EstimateProse $cands $m.formula
    }
    foreach($c in @($it.crossChecks)){
      if(-not $c){ continue }
      Add-EstimateCandidate $cands $c.display $null 'crosscheck'
      foreach($in in @($c.inputs)){ if($in){ Add-EstimateCandidate $cands $in.display $null 'input' } }
      Add-EstimateProse $cands $c.explanation
    }
    foreach($s in @($it.skippedMethods)){ if($s){ Add-EstimateProse $cands $s.reason } }
    Add-EstimateProse $cands $it.statement
    Add-EstimateProse $cands $it.uncertainty
    $idx[$eid] = @{ item=$it; cands=$cands }
  }
  return $idx
}
function Get-EstimateAnchors($line){
  $out = @(); foreach($m in [regex]::Matches([string]$line,$script:EstAnchorRx)){ $out += $m.Groups[1].Value }
  return $out
}
function Test-EstimateSection($header){
  # ONLY a heading whose visible text is exactly "Estimates (modeled)" - comments stripped first, so a
  # hidden comment cannot turn another section into this one, and a header that merely mentions the words
  # ("our estimate and how we modeled it") does not qualify.
  $h = (([string]$header) -replace '<!--.*?-->','') -replace '^\s*#+\s*',''
  return ($h -match ('(?i)' + $script:EstSectionRx))
}
function Get-EstimateLineCandidates($ests,$estIndex,$sectionHeader){
  # an estimate's numbers are in scope only on its anchored line AND only inside the estimates section
  $out = New-Object System.Collections.ArrayList
  if(@($ests).Count -eq 0 -or -not (Test-EstimateSection $sectionHeader)){ return $out }
  foreach($eid in @($ests | Select-Object -Unique)){ if($estIndex.ContainsKey($eid)){ foreach($c in $estIndex[$eid].cands){ [void]$out.Add($c) } } }
  return $out
}
function Test-EstimateLine($line,$ests,$estIndex,$sectionHeader){
  $out = New-Object System.Collections.ArrayList
  if(@($ests).Count -eq 0){ return $out }
  $visible = ([string]$line) -replace '<!--.*?-->',''
  foreach($eid in @($ests | Select-Object -Unique)){
    if(-not $estIndex.ContainsKey($eid)){
      [void]$out.Add([ordered]@{ type='unknown-estimate-anchor'; section=$sectionHeader; detail="estimate anchor '$eid' is not in facts.estimates"; snippet=[string]$eid })
      continue
    }
    if(-not (Test-EstimateSection $sectionHeader)){
      [void]$out.Add([ordered]@{ type='estimate-outside-section'; section=$sectionHeader; detail="estimate '$eid' is cited outside the 'Estimates (modeled)' section; modeled figures may appear only directly under a heading that reads exactly 'Estimates (modeled)' (no sub-headings inside it)"; snippet=[string]$eid })
      continue
    }
    if($visible -notmatch $script:EstWordRx){
      [void]$out.Add([ordered]@{ type='estimate-label-missing'; section=$sectionHeader; detail="line citing estimate '$eid' must say so in visible text (estimate / estimated / modeled / projected)"; snippet=[string]$eid })
    }
    $pm = [regex]::Match($visible,$script:EstPrevRx)
    if($pm.Success){
      [void]$out.Add([ordered]@{ type='estimate-compared-to-previous'; section=$sectionHeader; detail="line citing estimate '$eid' compares it with a previous period ('$($pm.Value)'); an estimate is set beside what was recorded this period, never beside another period"; snippet=$pm.Value })
    }
  }
  return $out
}
function Find-EstimateOwners($tok,$estIndex){
  # eids whose base / low / high or method / cross-check result this token states. The token must be
  # written at least as precisely as the estimate itself: a round "100" or "$4" in a recommendation is a
  # target, not the estimate 100.0 or $3.68 (a ROUNDED estimate is caught by Test-EstimateRounded).
  $owners = @()
  foreach($eid in @($estIndex.Keys | Sort-Object)){
    $own = @($estIndex[$eid].cands | Where-Object { $_.role -in @('base','low','high','method','crosscheck') -and ((Get-Ulp $tok.raw) -le ([double]$_.ulp + 1e-12)) })
    if(@(Find-Candidates $tok $own).Count -gt 0){ $owners += $eid }
  }
  return $owners
}
function Test-EstimateStray($tok,$estIndex,$sectionHeader){
  # called for a number that did NOT trace: if it is a modeled figure, say so (it was used unanchored,
  # outside its section, or without its anchor on the line).
  $out = New-Object System.Collections.ArrayList
  if($estIndex.Count -eq 0){ return $out }
  $owners = @(Find-EstimateOwners $tok $estIndex)
  if($owners.Count -gt 0){
    [void]$out.Add([ordered]@{ type='estimate-misuse'; section=$sectionHeader; detail=("'{0}' is a modeled estimate ({1}), not a measured figure; cite it only on a line carrying <!-- estimate:{2} --> inside the 'Estimates (modeled)' section" -f $tok.raw,($owners -join ', '),$owners[0]); snippet=$tok.raw })
  }
  return $out
}
function Test-EstimateUntraced($sectionText,$measuredCands,$estIndex,$sectionHeader){
  # for a section the tracer skips (Recommendations): an estimate number must still not appear there
  # dressed as a plain figure. A token that also matches a measured fact is left alone.
  $out = New-Object System.Collections.ArrayList
  if($estIndex.Count -eq 0){ return $out }
  foreach($tok in @(Get-MeasureTokens $sectionText)){
    if(@(Find-Candidates $tok $measuredCands).Count -gt 0){ continue }
    foreach($v in @(Test-EstimateStray $tok $estIndex $sectionHeader)){ [void]$out.Add($v) }
  }
  return $out
}
function Test-EstimateRounded($visibleLine,$estIndex,$sectionHeader){
  # "about 57" for an estimated 56.7: a whole number introduced by an approximation word that equals a
  # count estimate's base / low / high rounded either way. Small whole numbers are not measure tokens
  # for the tracer, so without this a rounded estimate could be written anywhere.
  $out = New-Object System.Collections.ArrayList
  foreach($m in [regex]::Matches([string]$visibleLine,$script:EstApproxIntRx)){
    $n = Normalize-Num $m.Groups[1].Value
    if($null -eq $n){ continue }
    foreach($eid in @($estIndex.Keys | Sort-Object)){
      $hit = $false
      foreach($c in $estIndex[$eid].cands){
        if($c.role -notin @('base','low','high') -or $c.type -ne 'number'){ continue }
        $v = [double]$c.value
        if([math]::Abs($v - [math]::Round($v)) -lt 1e-9){ continue }   # already whole: nothing was rounded
        if($n -eq [math]::Floor($v) -or $n -eq [math]::Ceiling($v)){ $hit = $true; break }
      }
      if($hit){
        [void]$out.Add([ordered]@{ type='estimate-misuse'; section=$sectionHeader; detail=("'{0}' is the modeled estimate {1} rounded; quote an estimate's display string verbatim, on its anchored line inside 'Estimates (modeled)'" -f $m.Value.Trim(),$eid); snippet=$m.Value.Trim() })
        break
      }
    }
  }
  return $out
}
function Test-EstimateSurfacing($reportText,$estIndex){
  # report-level rules. Reads the RAW lines (headings included) so it sees what the per-line tracer skips.
  $out = New-Object System.Collections.ArrayList
  if($script:EstNoEid -gt 0){
    [void]$out.Add([ordered]@{ type='estimate-item-without-eid'; section='(facts)'; detail="$($script:EstNoEid) item(s) in facts.estimates carry no eid; re-run Invoke-SwydoForecast.ps1"; snippet='eid' })
  }
  if($estIndex.Count -eq 0){ return $out }
  $lines = (([string]$reportText) -replace "`r`n","`n") -split "`n"
  $cited = @{}; $curHeader = '(intro)'; $inSec = $false; $secText = New-Object System.Text.StringBuilder
  foreach($ln in $lines){
    $rest = $ln -replace '<!--.*?-->',''
    $hm = [regex]::Match($ln,'^(#{1,6})\s+(.*)$')
    if($hm.Success){
      $curHeader = $hm.Groups[2].Value.Trim(); $inSec = (Test-EstimateSection $curHeader)
      foreach($eid in @(Get-EstimateAnchors $ln)){
        [void]$out.Add([ordered]@{ type='estimate-anchor-on-heading'; section=$curHeader; detail="estimate anchor '$eid' sits on a heading; an estimate is cited on a body line inside 'Estimates (modeled)'"; snippet=[string]$eid })
      }
      foreach($v in @(Test-EstimateRounded $rest $estIndex $curHeader)){ [void]$out.Add($v) }
      continue
    }
    if($rest -match '\bEST#\d+'){
      [void]$out.Add([ordered]@{ type='estimate-internal-id-visible'; section=$curHeader; detail="the internal id '$($Matches[0])' is visible in the text; refer to the estimate in words (the id belongs only inside the anchor comment)"; snippet=$Matches[0] })
    }
    $ests = @(Get-EstimateAnchors $ln | Where-Object { $estIndex.ContainsKey($_) })
    if($inSec){
      [void]$secText.AppendLine($rest)
      foreach($eid in $ests){ if(-not $cited.ContainsKey($eid)){ $cited[$eid] = New-Object System.Collections.ArrayList }; [void]$cited[$eid].Add($ln) }
    }
    if(-not ($inSec -and $ests.Count -gt 0)){
      foreach($v in @(Test-EstimateRounded $rest $estIndex $curHeader)){ [void]$out.Add($v) }
    }
  }
  # every action / total estimate is presented (dependent ones - rate, cost per conversion - are optional)
  foreach($eid in @($estIndex.Keys | Sort-Object)){
    if($cited.ContainsKey($eid)){ continue }
    if([string]$estIndex[$eid].item.kind -eq 'dependent'){ continue }
    [void]$out.Add([ordered]@{ type='estimates-not-surfaced'; section='(report)'; detail="the facts carry modeled estimate '$eid' but no body line inside 'Estimates (modeled)' cites it (<!-- estimate:$eid -->); a requested estimate is presented, not dropped"; snippet=[string]$eid })
  }
  # a cited estimate shows its base and both ends of its range
  foreach($eid in @($cited.Keys | Sort-Object)){
    $it = $estIndex[$eid].item
    $toks = @(); foreach($ln in $cited[$eid]){ $toks += @(Get-MeasureTokens $ln) }
    foreach($side in @('base','low','high')){
      $disp = switch($side){ 'base' { $it.display } 'low' { $it.displayLow } default { $it.displayHigh } }
      $want = New-Object System.Collections.ArrayList
      Add-EstimateCandidate $want $disp $it.type $side
      $seen = $false
      foreach($t in $toks){ if(@(Find-Candidates $t $want).Count -gt 0){ $seen = $true; break } }
      if(-not $seen){
        if($side -eq 'base'){ [void]$out.Add([ordered]@{ type='estimate-base-missing'; section='(report)'; detail="estimate '$eid' is cited without its base figure ($disp); a method result or an end of the range is not the estimate"; snippet=[string]$eid }) }
        else { [void]$out.Add([ordered]@{ type='estimate-range-missing'; section='(report)'; detail="estimate '$eid' is cited without its $side end ($disp); an estimate is always given with its range"; snippet=[string]$eid }) }
      }
    }
  }
  # the section's own visible text must say the figures are not measured
  if($cited.Count -gt 0 -and $secText.ToString() -notmatch $script:EstNotMeasRx){
    [void]$out.Add([ordered]@{ type='estimate-disclosure-missing'; section='(report)'; detail="the 'Estimates (modeled)' section must state in plain words that its figures are modeled, not measured"; snippet='not measured' })
  }
  return $out
}
