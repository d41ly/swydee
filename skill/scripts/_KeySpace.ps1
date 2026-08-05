<#
.SYNOPSIS
  The single source of the row-map key space, shared by the extractor and the analyzer.
.DESCRIPTION
  Get-SwydoReport.ps1 keys rows[].metrics and rows[].dimensions with Uniq-Key, NOT with the display
  name. Analyze-SwydoReport.ps1 has to address those same cells. Before ANLZ-aCandidTally-1 the
  analyzer read them by display name, which returns the FIRST holder's cell whenever two display
  names collide, so a metric selected by id published another metric's number.

  Both scripts dot-source THIS file rather than keeping a copy each, so there is one definition and
  no drift gate to maintain (AGENTS.md section 12). AC22 asserts the single definition.

  ANLZ-aCandidTally-1 B3: this file carries NO param() block, no -DefineOnly switch and no early
  return, and it is the one file under skill/scripts/ that deliberately breaks the functions-first
  param() convention. A param() block on a DOT-SOURCED file rebinds its declared names in the
  CALLER's scope, so a `[switch]$DefineOnly` here would set $DefineOnly=$false inside both callers
  and drop them straight through their own -DefineOnly guards into their run bodies. That reds six
  suites with a message naming neither this file nor the dot-source.

  Both dot-sources must therefore sit ABOVE the callers' guards, and they do.
#>

# Collision-proof, null-safe key for an OrderedDictionary map.
# The map MUST be an [ordered]@{} or a plain @{}: both compare keys CASE-INSENSITIVELY, which is
# what makes 'Clicks' and 'clicks' a collision. A Generic.HashSet[string] compares ordinally and
# would derive a bare key where this function derived a suffixed one.
function Uniq-Key($map,$name,$id,$idx){
  $base = if([string]::IsNullOrEmpty($name)){ if([string]::IsNullOrEmpty($id)){ "col$idx" } else { [string]$id } } else { [string]$name }
  if(-not $map.Contains($base)){ return $base }
  $k = "$base [$id]"
  if(-not $map.Contains($k)){ return $k }
  return "$base [$id #$idx]"
}
# ANLZ-aUniformLattice-2 S13/D5: the Uniq-Key SEQUENCE a metric or dimension list produces, derived
# once. The per-row loops build the same sequence against a fresh map each row, so this reproduces it
# exactly without touching them. Pure; -DefineOnly testable through either caller.
function Get-UniqKeySeq($items){
  $probe=[ordered]@{}; $out=@()
  $arr=@($items)
  for($i=0;$i -lt $arr.Count;$i++){
    $k = Uniq-Key $probe $arr[$i].name $arr[$i].id $i
    $probe[$k]=1
    $out += $k
  }
  # unary comma: `return @(x)` collapses a ONE-element array to a scalar, and the caller then
  # indexes into a string. Same PowerShell trap as ANLZ-aUniformLattice-7.
  return ,@($out)
}
