<#
.SYNOPSIS
  The single way a tool adds ONE top-level member to a facts JSON file without re-serializing it.
.DESCRIPTION
  A facts file is the record of provenance: its measured content must stay byte-for-byte what
  Analyze-SwydoReport.ps1 wrote. Round-tripping it through ConvertFrom-Json / ConvertTo-Json can
  change number formatting, escapes and depth, so a tool that enriches the facts (modeled estimates,
  derived metrics, ...) splices its member into the TEXT instead.

  Every such tool dot-sources THIS file rather than keeping a copy (AGENTS.md section 12; backlog
  ANLZ-aModeledGap-4). The member is always re-appended LAST, so two tools can each own a member and
  re-run in any order without disturbing the other's.

  Find-FactsMember   locate "<name>": <value> at depth 1 (strings and nesting respected)
  Remove-FactsMember drop it wherever it sits; every other byte is kept
  Set-FactsMember    remove any existing one, append the new JSON value as the last member, then
                     verify: the result parses, the member is there, no other member appeared or vanished
#>
function Find-FactsMember($text,$name){
  # -> @{ keyStart; valueEnd } where valueEnd indexes the ',' or '}' after the value, or $null.
  $depth = 0; $inStr = $false; $esc = $false; $strStart = -1; $lastStr = $null; $keyStart = -1
  $n = $text.Length
  for($i = 0; $i -lt $n; $i++){
    $ch = $text[$i]
    if($inStr){
      if($esc){ $esc = $false }
      elseif($ch -eq '\'){ $esc = $true }
      elseif($ch -eq '"'){ $inStr = $false; if($depth -eq 1){ $lastStr = @{ start=$strStart; text=$text.Substring($strStart+1,$i-$strStart-1) } } }
      continue
    }
    if($ch -eq '"'){ $inStr = $true; $strStart = $i }
    elseif($ch -eq ':'){ if($depth -eq 1 -and $keyStart -lt 0 -and $lastStr -and $lastStr.text -ceq $name){ $keyStart = $lastStr.start }; $lastStr = $null }
    elseif($ch -eq '{' -or $ch -eq '['){ $depth++ }
    elseif($ch -eq ']'){ $depth-- }
    elseif($ch -eq '}'){ $depth--; if($depth -eq 0 -and $keyStart -ge 0){ return @{ keyStart=$keyStart; valueEnd=$i } } }
    elseif($ch -eq ','){ if($depth -eq 1){ if($keyStart -ge 0){ return @{ keyStart=$keyStart; valueEnd=$i } }; $lastStr = $null } }
  }
  return $null
}
function Remove-FactsMember($factsText,$name){
  $t = [string]$factsText
  $span = Find-FactsMember $t $name
  if($null -eq $span){ return $t }
  $head = $t.Substring(0,$span.keyStart).TrimEnd()
  $tail = $t.Substring($span.valueEnd)                  # starts at ',' (more members follow) or the closing '}'
  if($tail.StartsWith(',')){ $tail = $tail.Substring(1) }
  elseif($head.EndsWith(',')){ $head = $head.Substring(0,$head.Length-1) }
  return ($head + $tail)
}
function Set-FactsMember($factsText,$name,$valueJson){
  # $valueJson: the member's value, already serialized. Throws 'INPUT: ...' when the text is not a JSON
  # object, and a plain error when the spliced result fails verification.
  $t = Remove-FactsMember $factsText $name
  $end = $t.LastIndexOf('}')
  if($end -lt 0){ throw 'INPUT: the facts file is not a JSON object.' }
  $head = $t.Substring(0,$end).TrimEnd()
  $sep = ','; if($head.EndsWith('{')){ $sep = '' }
  $out = $head + $sep + '"' + $name + '":' + $valueJson + $t.Substring($end)
  $before = @(($t | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $_.Name })
  $chk = $out | ConvertFrom-Json
  $after = @($chk.PSObject.Properties | ForEach-Object { $_.Name } | Where-Object { $_ -cne $name })
  if($null -eq $chk.PSObject.Properties[$name] -or (($before -join '|') -cne ($after -join '|'))){ throw "internal: spliced facts failed re-parse verification for member '$name'" }
  return $out
}
