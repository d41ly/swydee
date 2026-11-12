<#
.SYNOPSIS
  Closer rules that close two long-standing tracing gaps (backlog ANLZ-aModeledGap-2, -7, -8).
.DESCRIPTION
  Dot-sourced by Test-ReportNumbers.ps1. Each gap let a fabricated MEASURED number through a report
  that otherwise traced perfectly:

    1 headings   Split-Sections keeps a heading's text out of the section body, so a number in a
                 heading ("### Record month: 999.9 conversions") was never traced.
                 Get-HeadingTraceLine hands the heading text to the per-line tracer, in the heading's
                 own section scope.
                 LENDING. A heading is lent the FINDING anchors written on it and in its own direct
                 body (up to the next heading of any level), so it may quote the figures of a finding
                 its section echoes. Nothing is lent from a child section, and an annotation, estimate
                 or derived anchor on a heading lends nothing: those figures belong on body lines.
                 NOT TRACED. The title (Split-Sections: the first heading, when level 1), and - unless
                 -TraceRecommendations is on - any heading of a Recommendations section (targets are
                 not facts; the estimate / derived misuse scans still read those headings).
                 NAMES. A platform display name or the client name that carries digits ("Search Ads
                 360", "Studio 360") is removed from the heading line before tracing: a required
                 platform heading must not fail on its own name. Other digit labels ("Promo 2500",
                 "401(k)") are not masked - they fail in body text too (backlog ANLZ-aModeledGap-9).
    2 comments   The client copy strips HTML comments ACROSS lines; every check reads line by line.
                 A comment opening on one line and closing on another could hide a heading (changing
                 which section the following numbers trace in) from the client only.
                 Test-MultilineComments rejects a comment that is left open at the end of a line, and
                 the line that closes it. A bare "-->" with no comment open (an arrow in prose) is fine.
                 It is the ONLY emitter of `multiline-comment` and runs for every report.

  A third gap - a bare whole number under 100 is not a measure token, so "45 leads" is never traced -
  is NOT closed here. A phrase-pattern rule for it was built and reviewed (review
  2026-11-12-review-aModeledGap-2): it wrongly blocked ordinary prose ("fewer than 20 conversions",
  "28 October leads", "13 conversion actions") and still missed most fabrications, because most small
  integers match some unrelated fact in scope. It stays open as ANLZ-aModeledGap-3; the fix needs
  candidates bound to their metric, not more phrase patterns.
#>
function Get-HeadingMaskNames($facts){
  # platform display names and the client name that contain a digit, longest first
  $names = @()
  if($facts){
    foreach($p in @($facts.platforms)){ if($p -and $p.name){ $names += [string]$p.name } }
    if($facts.meta -and $facts.meta.client){ $names += [string]$facts.meta.client }
  }
  return @($names | Where-Object { $_ -match '\d' } | Select-Object -Unique | Sort-Object { $_.Length } -Descending)
}

function Get-HeadingTraceLine($sec,$traceRecs,$facts){
  # -> @() or a one-element array: the heading's visible text (names masked) plus its lent finding anchors.
  # NB callers must wrap the result in @(): PowerShell unrolls a one-element array on return.
  if($null -eq $sec -or [int]$sec.level -lt 1){ return @() }               # the pseudo-section before any heading
  if($sec.isTitle){ return @() }
  if($sec.kind -eq 'recommendations' -and -not $traceRecs){ return @() }
  $anchors = @()
  foreach($m in [regex]::Matches(([string]$sec.header + "`n" + [string]$sec.text),'<!--\s*finding:[^\s]+?\s*-->')){ if($anchors -notcontains $m.Value){ $anchors += $m.Value } }
  $visible = ([string]$sec.header) -replace '<!--.*?-->',''
  foreach($nm in @(Get-HeadingMaskNames $facts)){
    $visible = [regex]::Replace($visible,('(?i)(?<![A-Za-z0-9])' + [regex]::Escape($nm) + '(?![A-Za-z0-9])'),' ')
  }
  return @($visible + ' ' + ($anchors -join ' '))
}

function Test-MultilineComments($reportText){
  $out = New-Object System.Collections.ArrayList
  $n = 0; $open = $false
  foreach($ln in (((([string]$reportText) -replace "`r`n","`n") -replace "`r","`n") -split "`n")){
    $n++
    $hasOpen = $ln.Contains('<!--'); $hasClose = $ln.Contains('-->')
    if(-not $hasOpen -and -not ($hasClose -and $open)){ continue }      # nothing comment-shaped to judge
    $rest = $ln
    if($hasOpen -and $hasClose){ $rest = $ln -replace '<!--.*?-->','' } # drop the comments complete on this line
    $closesEarlier = ($open -and $rest.Contains('-->'))
    $leavesOpen = $rest.Contains('<!--')
    if($closesEarlier -or $leavesOpen){
      $snip = $rest.Trim(); if($snip.Length -gt 80){ $snip = $snip.Substring(0,80) + '...' }
      [void]$out.Add([ordered]@{ type='multiline-comment'; section='(report)'; detail="line $n opens or closes an HTML comment that spans lines; every comment (anchor) must open and close on one line, because the client copy strips comments across lines while the checks read line by line"; snippet=$snip })
    }
    if($closesEarlier){ $open = $false }
    if($leavesOpen){ $open = $true }
  }
  return $out
}
