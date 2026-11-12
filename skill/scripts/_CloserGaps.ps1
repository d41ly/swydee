<#
.SYNOPSIS
  Closer rules that close two long-standing tracing gaps (backlog ANLZ-aModeledGap-2).
.DESCRIPTION
  Dot-sourced by Test-ReportNumbers.ps1. Each gap let a fabricated MEASURED number through a report
  that otherwise traced perfectly:

    1 headings   Split-Sections keeps a heading's text out of the section body, so a number in a
                 heading ("### Record month: 999.9 conversions") was never traced.
                 Get-HeadingTraceLine hands the heading text to the per-line tracer, in the heading's
                 own section scope. A heading may quote the figures of a finding that its own section
                 echoes (the finding anchors found in the section body are lent to the heading line;
                 any other anchor written on a heading lends it nothing).
                 Not traced: the level-1 title (client and report names carry digits: "Studio 360"),
                 and any heading at or under a Recommendations heading (targets are not facts).
    2 comments   The client copy strips HTML comments ACROSS lines; every check reads line by line.
                 A comment opening on one line and closing on another could hide a heading (changing
                 which section the following numbers trace in) from the client only.
                 Test-MultilineComments rejects a comment that is left open at the end of a line, and
                 the line that closes it. A bare "-->" with no comment open (an arrow in prose) is fine.

  A third gap - a bare whole number under 100 is not a measure token, so "45 leads" is never traced -
  is NOT closed here. A phrase-pattern rule for it was built and reviewed (review
  2026-11-12-review-aModeledGap-2): it wrongly blocked ordinary prose ("fewer than 20 conversions",
  "28 October leads", "13 conversion actions") and still missed most fabrications, because most small
  integers match some unrelated fact in scope. It stays open as ANLZ-aModeledGap-3; the fix needs
  candidates bound to their metric, not more phrase patterns.
#>
function Get-HeadingTraceLine($sec,$sections){
  # -> @() or @(<one line>): the heading text plus the finding anchors of its own section body
  if($null -eq $sec -or [int]$sec.level -le 1){ return @() }            # pseudo-intro and the title
  # at or under a Recommendations heading? walk the sections up to this one
  $recLevel = 0
  foreach($x in @($sections)){
    if($recLevel -gt 0 -and [int]$x.level -le $recLevel -and $x.kind -ne 'recommendations'){ $recLevel = 0 }
    if($x.kind -eq 'recommendations'){ $recLevel = [int]$x.level }
    if([object]::ReferenceEquals($x,$sec)){ break }
  }
  if($recLevel -gt 0){ return @() }
  # Only FINDING anchors are lent to the heading (its own, and those of its section body). Every
  # other anchor on a heading is dropped from the traced line: an estimate / derived / annotation
  # anchor must sit on a body line to count, so a heading can never stand in for one.
  $anchors = @()
  foreach($m in [regex]::Matches(([string]$sec.header + "`n" + [string]$sec.text),'<!--\s*finding:[^\s]+?\s*-->')){ if($anchors -notcontains $m.Value){ $anchors += $m.Value } }
  $visible = ([string]$sec.header) -replace '<!--.*?-->',''
  return @($visible + ' ' + ($anchors -join ' '))
}

function Test-MultilineComments($reportText){
  $out = New-Object System.Collections.ArrayList
  $n = 0; $open = $false
  foreach($ln in ((([string]$reportText) -replace "`r`n","`n") -split "`n")){
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
