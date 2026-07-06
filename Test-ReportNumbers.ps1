<#
.SYNOPSIS
  Deterministically verify a /swydee client report against its facts file:
  every measure number traces to a facts display string, comparison claims are
  backed by comparison data, required findings/caveats are surfaced, no credential leaks.

.DESCRIPTION
  The mechanized half of "the numbers check out". No model judgment here - a pure
  offline tracer (PS 5.1 / .NET only). Functions-first; dot-source with -DefineOnly for
  unit tests. Reads nothing but the two inputs; writes nothing; exits 1 on any violation.

  Checks (per reconciled UNIT_closer_spec review outcome + post-build code review):
   1 tracing        - every measure token matches a same-TYPE fact display string within
                      display tolerance (half the coarser ULP), scoped to the section's
                      platform. Finding numbers are in scope only for the paragraph echoing
                      that finding's fid. Ambiguous (>1) or unknown platform anchors are flagged.
   2 comparison     - a comparative claim on a value whose only candidates are
                      hasComparison=false is flagged.
   3 surfacing      - every finding sev>=major OR requiresDownstreamData must echo its fid
                      as <!-- finding:<fid> -->; every comparisonCaveat must appear (object
                      caveats via <!-- caveat:<id> -->); a surfaced requiresDownstreamData
                      finding needs a downstream clause.
   4 hygiene        - the report must contain no share-key credential pattern (case-insensitive).

.PARAMETER Report   Path to the generated report .md
.PARAMETER Facts    Path to the *.facts.json produced by Analyze-SwydoReport.ps1
.PARAMETER TraceRecommendations  Also trace numbers inside "## Recommendations" (default: skip -
                    recommendations carry proposed targets/thresholds that are not facts).
.PARAMETER DefineOnly  Define functions and exit (for unit tests). No file I/O, no exit code.
#>
param(
  [string]$Report,
  [string]$Facts,
  [string]$PublishTo,          # on PASS, write a client copy with the machine anchors stripped
  [switch]$TraceRecommendations,
  [switch]$DefineOnly
)
$ErrorActionPreference = 'Stop'

# ---- constants (ASCII source; currency symbols via [char] to survive PS 5.1 decoding) ----
$script:CurClass = '[\$' + [char]0x20AC + [char]0xA3 + ']'          # $ EUR GBP
$script:DashRx  = '[' + [char]0x2212 + [char]0x2013 + [char]0x2014 + ']'   # minus / en / em dash
$script:TildeRx = '[~' + [char]0x2248 + ']'                                # ~ / approx
# A leading +/- is a sign ONLY at a sign position (start / after space or "(") - never when it is a
# word-joiner or range hyphen ("Ad Group-3.75", "$500-$600", "5%-10%").
$script:SignRx = '(?:(?<![\w.,$%)-])[+-])?'
# A bare number must not be glued to a preceding word/identifier (labels: "Group-3.75", "Q3", "v1.5",
# "ID12345"). The first lookbehind rejects a preceding letter OR digit so a match cannot start in the
# middle of a letter-led alphanumeric run (which would leak/truncate a phantom tail like ID12345 -> 2345).
$script:LabelGuard = '(?<![A-Za-z0-9])(?<![A-Za-z][-_/.])'
# Master token regex - ordered alternation, exempt shapes first so dates/"25-34"/"3x"/"2026" win.
$script:TokRx = '(?<mult>\d+(?:\.\d+)?\s*[xX])' +
                '|(?<date>(?<![\d-])(?:19|20)\d\d-\d{1,2}(?:-\d{1,2})?(?![\d-]))' +
                '|(?<range>\d+\s*-\s*\d+)' +
                '|(?<bucket>\d+\+)' +
                '|(?<cur>' + $script:SignRx + $script:CurClass + '\s?\d[\d,]*(?:\.\d+)?\s*[KMB]?)' +
                '|(?<pct>' + $script:SignRx + '\d[\d,]*(?:\.\d+)?\s*%)' +
                '|(?<year>20\d\d)' +
                '|(?<bare>' + $script:LabelGuard + $script:SignRx + '\d[\d,]*(?:\.\d+)?\s*[KMB]?)'
# Comparative verbs (conservative - excludes idiomatic bare up/down to avoid false positives).
$script:CmpRx = '(?i)\b(grew|grow|grown|growth|fell|fall|fallen|rose|rise|risen|declin\w*|' +
                'increas\w*|decreas\w*|higher|lower|improv\w*|worse|worsen\w*|dropp?\w*|' +
                'climb\w*|surg\w*|plung\w*|gained?|lost|vs\.?|year-over-year|' +
                'quarter-over-quarter|QoQ|YoY|compared)\b'
# Credential leak patterns (fail-closed; case-insensitive so SWY.DO/... can't slip through).
$script:CredRx = '(?i)swy\.do/shares/[A-Za-z0-9]+|/g/[A-Za-z0-9]{20,}/reports/'
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
  $neg = ($t -match '^[^\d]*-')                        # a '-' before the first digit (incl. "$-2,500")
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

function Map-CellType($t){
  # Facts breakdown cells carry an authoritative type (currency|percent|count|ratio|number).
  # Collapse to the tracer's 3 comparable types. Preferred over inferring from the display string.
  switch -Regex ([string]$t){ '^(?i)currency$' { 'currency' } '^(?i)percent$' { 'percent' } default { 'number' } }
}

function Get-Ulp($disp){
  # Smallest represented step of a display string = 10^(-decimals) * (K/M/B multiplier).
  # Used for tolerance: a display rounds the true value by at most half its ULP.
  if($null -eq $disp){ return 1.0 }
  $t = ([string]$disp).Trim() -replace $script:DashRx,'-'
  $mult = 1.0
  $m = [regex]::Match($t,'(?i)([kmb])\s*$')
  if($m.Success){ switch($m.Groups[1].Value.ToUpper()){ 'K'{$mult=1e3} 'M'{$mult=1e6} 'B'{$mult=1e9} }; $t = $t.Substring(0,$m.Index) }
  $dec = 0
  $dm = [regex]::Match($t,'\.(\d+)')
  if($dm.Success){ $dec = $dm.Groups[1].Value.Length }
  return [double]([math]::Pow(10,-$dec) * $mult)
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
    if($g['year'].Success -or $g['date'].Success){ continue }   # calendar years and ISO date labels
    $end = $mm.Index + $mm.Length
    if($g['mult'].Success -or $g['range'].Success -or $g['bucket'].Success){
      # buckets/ranges/multipliers are demographic/ROAS shapes and are exempt ONLY when small
      # (65+, 25-34, 3x). A large "40000+" / "25000-30000" / "12500x" is a measure smuggled past the
      # tokenizer by trivial phrasing - fall through and require EVERY number in it to trace.
      $enums = @([regex]::Matches($mm.Value,'\d[\d,]*(?:\.\d+)?') | ForEach-Object { Normalize-Num $_.Value })
      $emax = ($enums | Measure-Object -Maximum).Maximum
      # a range/bucket whose numbers are all year-like (1900-2099) is a year range, not a smuggled count
      $allYears = ($enums.Count -gt 0) -and (@($enums | Where-Object { $_ -lt 1900 -or $_ -gt 2099 }).Count -eq 0)
      if($null -eq $emax -or $emax -lt 1000 -or $allYears){ continue }
      foreach($e in $enums){ if($null -ne $e){ [void]$out.Add([ordered]@{ raw=$mm.Value.Trim(); value=$e; type='number'; index=$mm.Index; end=$end; signed=$false }) } }
      continue
    }
    $raw = $mm.Value.Trim()
    $type = 'number'; $isMeasure = $false
    if($g['cur'].Success){ $type='currency'; $isMeasure=$true }
    elseif($g['pct'].Success){ $type='percent'; $isMeasure=$true }
    elseif($g['bare'].Success){
      $type='number'
      $hasSep = ($raw -match ',') -or ($raw -match '\.') -or ($raw -match '(?i)[kmb]$')
      $val0 = Normalize-Num $raw
      # list-size / lookback context integers ("top 100", "first 200", "past 90 days") are not measures.
      # \b anchors the word so "Desktop 987654" / "homepage 500" are NOT exempted; and only small values
      # are exempted (a large "last 45000" is a measure that must trace).
      $pre = if($mm.Index -gt 0){ $norm.Substring([math]::Max(0,$mm.Index-8), [math]::Min(8,$mm.Index)) } else { '' }
      $isContext = ($pre -match '(?i)\b(top|first|last|next|past|page)\s*$')
      if(-not $hasSep -and $isContext -and ($null -eq $val0 -or [math]::Abs($val0) -lt 1000)){ $isMeasure=$false }
      elseif($hasSep -or ($null -ne $val0 -and [math]::Abs($val0) -ge 100)){ $isMeasure=$true }
    }
    if(-not $isMeasure){ continue }
    $v = Normalize-Num $raw
    if($null -eq $v){ continue }
    [void]$out.Add([ordered]@{ raw=$raw; value=$v; type=$type; index=$mm.Index; end=$end; signed=($raw -match '^[+-]') })
  }
  return $out
}

function Add-Candidate($list,$disp,$hasCmp,$explicitType){
  # $explicitType (from the fact cell's own type field) is authoritative; fall back to the display
  # string only when the fact carries no type (kills e.g. a symbol-less currency reading as a count).
  $v = Normalize-Num $disp
  if($null -eq $v){ return }
  if($explicitType){ $ty = Map-CellType $explicitType } else { $ty = Type-FromDisplay $disp }
  [void]$list.Add([ordered]@{ value=$v; type=$ty; hasComparison=[bool]$hasCmp; ulp=(Get-Ulp $disp) })
}

function Add-StringNumbers($list,$str){
  # Numbers pulled from a finding's statement/evidence prose. hasComparison=$true (never trips the
  # comparison guard - these are computed facts, and the guard is for headline/breakdown cells).
  foreach($t in @(Get-MeasureTokens $str)){
    [void]$list.Add([ordered]@{ value=$t.value; type=$t.type; hasComparison=$true; ulp=(Get-Ulp $t.raw) })
  }
}

function Build-FactIndex($facts){
  # -> @{ global; byPlatform=@{id->[..]}; nameToId; byFid=@{fid->[..]} }
  # global/byPlatform hold ONLY measured display strings (headline/breakdown/timeSeries).
  # Finding statement/evidence numbers go into byFid ONLY - they are in scope for a report
  # paragraph solely when that paragraph echoes the finding's fid, never platform-wide/global.
  # (Otherwise every number in model-authored finding prose becomes a fabrication haystack.)
  $global   = New-Object System.Collections.ArrayList
  $byPlat   = @{}
  $nameToId = @{}
  $byFid    = @{}
  foreach($p in @($facts.platforms)){
    $plid = [string]$p.id
    $plist = New-Object System.Collections.ArrayList
    $byPlat[$plid] = $plist
    if($p.name){ $nameToId[[string]$p.name] = $plid }
    # headline (delta is always a percent; current/previous carry the metric's type when present)
    if($p.headline){
      foreach($hk in $p.headline.PSObject.Properties.Name){
        $h = $p.headline.$hk
        Add-Candidate $plist $h.displayCurrent  $h.hasComparison $h.type
        Add-Candidate $plist $h.displayPrevious $h.hasComparison $h.type
        Add-Candidate $plist $h.displayDelta    $true            'percent'
      }
    }
    # breakdown rows (cells carry an authoritative type)
    foreach($bd in @($p.breakdowns)){
      foreach($row in @($bd.rows)){
        if(-not $row.values){ continue }
        foreach($mn in $row.values.PSObject.Properties.Name){
          $cell = $row.values.$mn
          Add-Candidate $plist $cell.display $cell.hasComparison $cell.type
          if($cell.PSObject.Properties.Name -contains 'displayPrevious'){ Add-Candidate $plist $cell.displayPrevious $cell.hasComparison $cell.type }
          if($cell.PSObject.Properties.Name -contains 'delta'){ Add-Candidate $plist $cell.delta $true 'percent' }
        }
      }
    }
    # time series (derived CPL/cost-per-conv are money; pacing series inherits its display; netChange is %)
    foreach($ts in @($p.timeSeries)){
      foreach($b in @($ts.buckets)){
        if($b.derived){ foreach($dn in $b.derived.PSObject.Properties.Name){ Add-Candidate $plist $b.derived.$dn $false 'currency' } }
      }
      if($ts.pacing){
        foreach($sp in @($ts.pacing.series)){ Add-Candidate $plist $sp.display $false $null }
        if($ts.pacing.PSObject.Properties.Name -contains 'netChange'){ Add-Candidate $plist $ts.pacing.netChange $true 'percent' }
      }
    }
    foreach($c in $plist){ [void]$global.Add($c) }
  }
  # findings -> byFid only
  if($facts.findings){
    foreach($cat in @('wins','losses','anomalies','discrepancies','dataGaps')){
      foreach($f in @($facts.findings.$cat)){
        $fid = [string]$f.fid
        if(-not $fid){ continue }
        if(-not $byFid.ContainsKey($fid)){ $byFid[$fid] = New-Object System.Collections.ArrayList }
        Add-StringNumbers $byFid[$fid] $f.statement
        if($f.evidence){ foreach($ek in $f.evidence.PSObject.Properties.Name){ Add-StringNumbers $byFid[$fid] ([string]$f.evidence.$ek) } }
      }
    }
  }
  return @{ global=$global; byPlatform=$byPlat; nameToId=$nameToId; byFid=$byFid }
}

function Find-Candidates($tok,$cands){
  # match = same TYPE and value within tolerance = half the REPORT TOKEN's ULP. Keying tolerance to
  # the token (not the coarser of the two) means a report stating more precision than a coarse fact
  # ("1,249,000" vs "1.2M") must round TO the fact and is otherwise flagged, while a coarse report
  # token ("1.2M") still matches a precise fact within its own coarse step, and off-by-one on
  # equal-precision integers (432 vs 433) is caught.
  # Explicitly-signed tokens (+/-x%) must match on SIGNED value - a "+12.5%" claim cannot trace a
  # -12.5% fact; unsigned tokens match on magnitude (prose "down 12.5%" legitimately drops the sign).
  $hits = New-Object System.Collections.ArrayList
  $tol = [math]::Max(0.5 * (Get-Ulp $tok.raw), 0.001)
  foreach($c in $cands){
    if($c.type -ne $tok.type){ continue }
    if($tok.signed){ $d = [math]::Abs([double]$tok.value - [double]$c.value) }
    else { $d = [math]::Abs([math]::Abs([double]$tok.value) - [math]::Abs([double]$c.value)) }
    if($d -le $tol){ [void]$hits.Add($c) }
  }
  return $hits
}

function Split-Sections($reportText){
  # -> list of @{ header; kind(platform|recommendations|general); platformId; platformIdCount; level; text }
  $sections = New-Object System.Collections.ArrayList
  $lines = ($reportText -replace "`r`n","`n") -split "`n"
  $cur = [ordered]@{ header='(intro)'; level=0; lines=(New-Object System.Collections.ArrayList) }
  function _finalize($s){
    $txt = ($s.lines -join "`n")
    # search the header line too, so '## Google Ads <!-- platform:google_ads -->' is not silently dropped
    $hay = [string]$s.header + "`n" + $txt
    $secpids = @(); foreach($pm in [regex]::Matches($hay,'<!--\s*platform:([^\s]+?)\s*-->')){ $secpids += $pm.Groups[1].Value }
    $secpid = if($secpids.Count -gt 0){ $secpids[0] } else { $null }
    $kind = 'general'
    if($s.header -match '(?i)recommend'){ $kind='recommendations' }
    elseif($secpid){ $kind='platform' }
    return [ordered]@{ header=$s.header; kind=$kind; platformId=$secpid; platformIdCount=$secpids.Count; level=$s.level; text=$txt }
  }
  foreach($ln in $lines){
    $hm = [regex]::Match($ln,'^(#{1,6})\s+(.*)$')
    if($hm.Success){
      [void]$sections.Add((_finalize $cur))
      $cur = [ordered]@{ header=$hm.Groups[2].Value.Trim(); level=$hm.Groups[1].Value.Length; lines=(New-Object System.Collections.ArrayList) }
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

  # 1 + 2: per-LINE number tracing + comparison guard. A finding's numbers (byFid) are in scope ONLY
  # for the line that echoes its <!-- finding:fid --> - the finding's numbers and the fid must sit on
  # the same line (per report-template). Line scope (not paragraph) stops a fabricated number on a
  # sibling line from borrowing a co-located finding's number.
  $ctxPlatform = $null; $ctxLevel = 0   # last-seen platform section, for scoping unanchored subsections
  foreach($sec in $sections){
    if($sec.kind -eq 'recommendations' -and -not $TraceRecs){ continue }
    # C1: more than one platform anchor in one section is ambiguous (silent-take-first would mis-scope)
    if($sec.platformIdCount -gt 1){
      [void]$violations.Add([ordered]@{ type='ambiguous-platform-anchor'; section=$sec.header; detail="section carries $($sec.platformIdCount) platform anchors; expected at most one"; snippet=[string]$sec.platformId })
    }
    # Resolve the section's effective platform. Precedence: explicit anchor > header text naming a
    # known platform > inheritance from an enclosing (deeper) platform section. A section is NEVER
    # silently widened to global just because it omitted the anchor - that laundered wrong-platform
    # numbers (a missing anchor, unlike a wrong one, used to fall through to global).
    #   $eff:  a platformId -> that scope;  '' -> empty scope (broken anchor);  $null -> global.
    $eff = $null
    if($sec.platformId){
      if($index.byPlatform.ContainsKey($sec.platformId)){ $eff = $sec.platformId }
      else {
        $eff = ''   # C2: unknown/typo anchor -> empty scope + flag (do NOT fall back to global)
        [void]$violations.Add([ordered]@{ type='unknown-platform-anchor'; section=$sec.header; detail="platform anchor '$($sec.platformId)' not in facts.platforms"; snippet=[string]$sec.platformId })
      }
      $ctxPlatform = $eff; $ctxLevel = $sec.level
    } else {
      # Resolve by header text, but ONLY when the header plausibly IS a platform section (names exactly
      # one platform, word-boundary, not a comparison/portfolio header). Nested names (Google / Google
      # Ads) collapse to the most specific; a header naming several distinct platforms stays global.
      $named = $null
      $isCompare = ($sec.header -match '(?i)\b(vs|versus|compar\w*|across|combined|portfolio|blended|overall|total)\b')
      if(-not $isCompare){
        $nm = @()
        foreach($pn in $index.nameToId.Keys){
          if($pn -and ($sec.header -match ('(?i)(?<![A-Za-z0-9])' + [regex]::Escape([string]$pn) + '(?![A-Za-z0-9])'))){ $nm += [string]$pn }
        }
        if($nm.Count -gt 0){
          $longest = @($nm | Sort-Object { $_.Length } -Descending)[0]
          $distinct = @($nm | Where-Object { -not $longest.ToLower().Contains($_.ToLower()) })
          if($distinct.Count -eq 0){ $named = $index.nameToId[$longest] }   # nested -> most specific; else global
        }
      }
      if($named){ $eff = $named; $ctxPlatform = $eff; $ctxLevel = $sec.level }
      elseif($ctxPlatform -and $sec.level -gt $ctxLevel){ $eff = $ctxPlatform }   # deeper subsection inherits
      else { $eff = $null; if($sec.level -le $ctxLevel){ $ctxPlatform = $null; $ctxLevel = $sec.level } }
    }
    if($null -eq $eff){ $base = $index.global }
    elseif($eff -eq ''){ $base = (New-Object System.Collections.ArrayList) }
    else { $base = $index.byPlatform[$eff] }
    foreach($line in (($sec.text -replace "`r`n","`n") -split "`n")){
      $fids = @(); foreach($fm in [regex]::Matches($line,'<!--\s*finding:([^\s]+?)\s*-->')){ $fids += $fm.Groups[1].Value }
      $cands = New-Object System.Collections.ArrayList
      foreach($c in $base){ [void]$cands.Add($c) }
      foreach($fid in $fids){ if($index.byFid.ContainsKey($fid)){ foreach($c in $index.byFid[$fid]){ [void]$cands.Add($c) } } }
      $cmpMatches = [regex]::Matches($line,$script:CmpRx)
      foreach($tok in @(Get-MeasureTokens $line)){
        $measured++
        $hits = @(Find-Candidates $tok $cands)   # @() -> real array so .Count is reliable (PS 5.1 unwrap)
        if($hits.Count -gt 0){
          $traced++
        } else {
          [void]$violations.Add([ordered]@{ type='untraceable-number'; section=$sec.header; detail="'$($tok.raw)' ($($tok.type)) has no matching fact in scope"; snippet=$tok.raw })
          continue
        }
        # comparison guard: signed token, or a comparative verb near it on the SAME clause (no
        # sentence/clause punctuation between the verb and the number - avoids tainting an unrelated
        # no-comparison metric mentioned later in the same sentence).
        $isCmp = $tok.signed
        if(-not $isCmp){
          $tEnd = if($null -ne $tok.end){ [int]$tok.end } else { $tok.index + $tok.raw.Length }
          foreach($cm in $cmpMatches){
            $vEnd = $cm.Index + $cm.Length
            if($vEnd -le $tok.index){ $gap = $line.Substring($vEnd, $tok.index - $vEnd) }
            elseif($cm.Index -ge $tEnd){ $gap = $line.Substring($tEnd, $cm.Index - $tEnd) }
            else { continue }
            if($gap.Length -le 25 -and $gap -notmatch '[.;,:]'){ $isCmp=$true; break }
          }
        }
        if($isCmp){
          $anyCmp = $false; foreach($h in $hits){ if($h.hasComparison){ $anyCmp=$true; break } }
          if(-not $anyCmp){
            [void]$violations.Add([ordered]@{ type='comparison-without-data'; section=$sec.header; detail="comparison claim on '$($tok.raw)' but the matching fact(s) have no comparison data"; snippet=$tok.raw })
          }
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
        # delimited anchor match (NOT bare .Contains): 'finding:ANOM#1' is a substring of
        # 'finding:ANOM#10', so a required #1 could be masked by an echoed #10.
        $fidAnchored = $fid -and ($reportText -match ('<!--\s*finding:' + [regex]::Escape($fid) + '\s*-->'))
        if($fidAnchored){
          if($f.requiresDownstreamData -eq $true){ $reqDownSurfaced = $true }
        } else {
          $sn = [string]$f.statement; if($sn.Length -gt 80){ $sn = $sn.Substring(0,80) + '...' }
          [void]$violations.Add([ordered]@{ type='unsurfaced-finding'; section=$cat; detail="[$($f.ruleId) sev=$sev] not surfaced (missing <!-- finding:$fid -->)"; snippet=$sn })
        }
      }
    }
  }

  # 3b: every required caveat must appear. Object caveats {id,text} are matched by their
  #     <!-- caveat:id --> anchor (per-caveat, forward-compatible); legacy string caveats fall
  #     back to a 'seasonalit' keyword grep (fires at most once).
  if($facts.meta){
    $legacyMissingFlagged = $false
    foreach($cav in @($facts.meta.comparisonCaveats)){
      if($null -eq $cav){ continue }
      if($cav -is [string]){
        if(-not $legacyMissingFlagged -and ($reportText -notmatch '(?i)seasonalit')){
          [void]$violations.Add([ordered]@{ type='missing-caveat'; section='(report)'; detail='comparisonCaveats present but no seasonality caveat in report'; snippet='seasonality' })
          $legacyMissingFlagged = $true
        }
      } else {
        $cid = [string]$cav.id
        # delimited anchor (same prefix-collision hazard as fids: caveat:s1 vs caveat:s10)
        if($cid -and -not ($reportText -match ('<!--\s*caveat:' + [regex]::Escape($cid) + '\s*-->'))){
          [void]$violations.Add([ordered]@{ type='missing-caveat'; section='(report)'; detail="caveat '$cid' not surfaced (missing <!-- caveat:$cid -->)"; snippet=$cid })
        }
      }
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

function Strip-Anchors($text){
  # Produce the client-facing copy: remove the machine anchors (<!-- platform/finding/caveat:... -->,
  # and any HTML comment), trim the trailing whitespace they leave, and collapse the resulting blank
  # runs. Deterministic: the published file is the VERIFIED text minus comments - no number can change.
  $t = ([string]$text) -replace "`r`n","`n"
  $t = $t -replace '(?s)<!--.*?-->',''
  $t = ($t -split "`n" | ForEach-Object { $_ -replace '[ \t]+$','' }) -join "`n"
  return ($t -replace '\n{3,}', "`n`n")
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
  if($PublishTo){
    [IO.File]::WriteAllText($PublishTo, (Strip-Anchors $reportText), (New-Object Text.UTF8Encoding($false)))
    Write-Host ("published client report (anchors stripped) -> {0}" -f $PublishTo)
  }
  exit 0
}
# NB: on FAIL we deliberately do NOT publish - no clean deliverable is produced for a report that
# hasn't passed verification.
$byType = $res.violations | Group-Object { $_.type }   # script-block: reads the key off the ordered-dict
foreach($grp in $byType){
  Write-Host ''
  Write-Host ("[{0}] x{1}" -f $grp.Name,$grp.Count)
  foreach($v in $grp.Group){ Write-Host ("  - ({0}) {1}" -f $v.section,$v.detail) }
}
Write-Host ''
Write-Host ("FAIL - {0} violation(s)." -f $res.violations.Count)
exit 1
