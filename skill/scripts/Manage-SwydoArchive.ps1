<#
.SYNOPSIS
  Organize scraped Swydo report data by client + date, and manage retention (age-based cleanup).
.DESCRIPTION
  Three modes (exactly one):
    -Store    file a run's artifacts into <ArchiveRoot>/<client-slug>/<YYYY-MM-DD-HH-MM-SS>/ + manifest.json
    -List     read-only inventory of the archive (by client)
    -Cleanup  remove entries older than -OlderThan (7d|1mo|3mo|1yr), scoped to one -Client XOR -All.
              DRY-RUN by default; deletes ONLY with -Execute.

  Safety (this tool deletes; treated as high-risk):
   - -Execute is the ONLY branch that deletes; every run prints the exact set first.
   - Scope is mandatory and exclusive (-Client xor -All); refuses neither/both.
   - Age uses the calendar day (Today-floored cutoff); an entry exactly N old is KEPT.
   - Undated / unparseable / future-dated entries are KEPT (never deleted).
   - Deletion is contained: path re-resolved against the live FS, must live under ArchiveRoot; entries
     containing a reparse point (junction/symlink) are skipped; delete uses [IO.Directory]::Delete
     (removes the link, never traverses it) - never Remove-Item -Recurse.
   - -All requires a resolved, non-root, non-$HOME archive that carries a .swydee-archive sentinel.
   - Store refuses to archive anything still carrying a Swydo share credential (structural + regex gate).

  PS 5.1 / .NET only. Functions-first; dot-source with -DefineOnly for unit tests (no I/O, no exit).
.PARAMETER DefineOnly  Define functions and return WITHOUT running (for tests).
.EXAMPLE
  .\Manage-SwydoArchive.ps1 -Store -Facts run.facts.json -Report run-report.md -Client "Quincy Credit Union" -ArchiveRoot D:\swydee-archive
  .\Manage-SwydoArchive.ps1 -List -ArchiveRoot D:\swydee-archive
  .\Manage-SwydoArchive.ps1 -Cleanup -OlderThan 3mo -Client "Quincy Credit Union" -ArchiveRoot D:\swydee-archive          # dry-run
  .\Manage-SwydoArchive.ps1 -Cleanup -OlderThan 1yr -All -Execute -ArchiveRoot D:\swydee-archive                          # deletes
#>
param(
  [switch]$Store,
  [switch]$List,
  [switch]$Cleanup,
  # default: an 'archive' folder inside the installed skill (the parent of this scripts/ dir), so the
  # archive travels alongside the skill; falls back to ~/swydee-archive if the script dir is unknown.
  [string]$ArchiveRoot = $(if($PSScriptRoot){ Join-Path (Split-Path $PSScriptRoot -Parent) 'archive' } else { Join-Path $HOME 'swydee-archive' }),
  # Store inputs
  [string]$Facts,
  [string]$Report,
  [string]$Draft,
  [string]$Extraction,
  # Client = client display name for Store; scope selector for Cleanup/List
  [string]$Client,
  # Cleanup
  [string]$OlderThan,
  [switch]$All,
  [switch]$Execute,
  [switch]$DefineOnly
)
$ErrorActionPreference = 'Stop'

# Canonical Swydo share-key pattern (matches Analyze / Test-ReportNumbers; key alphabet broadened to _-).
$script:CredRx   = '(?i)swy\.do/shares/[A-Za-z0-9_-]+|/g/[A-Za-z0-9_-]{20,}/reports/'
$script:StampRx  = '^\d{4}-\d{2}-\d{2}-\d{2}-\d{2}-\d{2}$'
$script:Sentinel = '.swydee-archive'

# ---------------- pure, unit-testable helpers ----------------
function Get-ClientSlug($name){
  $s = ([string]$name) -replace '[^A-Za-z0-9]+','-'
  $s = $s.Trim('-').ToLower()
  if(-not $s){ $s = 'client' }
  return $s
}

function Get-Cutoff($token,$now){
  # Today-floored cutoff so an entry exactly N old sits at the boundary and is KEPT by a `-lt` test.
  $d = $now.Date
  switch(([string]$token).ToLower()){
    '7d'  { return $d.AddDays(-7) }
    '1mo' { return $d.AddMonths(-1) }
    '3mo' { return $d.AddMonths(-3) }
    '1yr' { return $d.AddYears(-1) }
    default { return $null }
  }
}

function Get-StampDate($folderName){
  # strict, invariant, full-stamp parse of a leading yyyy-MM-dd-HH-mm-ss; else $null. (pure)
  $s = [string]$folderName
  if($s.Length -lt 19){ return $null }
  $stamp = $s.Substring(0,19)
  if($stamp -notmatch $script:StampRx){ return $null }
  $dt = [datetime]::MinValue
  if([datetime]::TryParseExact($stamp,'yyyy-MM-dd-HH-mm-ss',[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::None,[ref]$dt)){
    if($dt.Year -ge 2000 -and $dt.Year -le 2100){ return $dt }
  }
  return $null
}

function Get-EntryAgeDate($archivedAtStr,$folderName,$now){
  # Age basis = manifest archivedAt (tool-written, authoritative) with folder-stamp fallback.
  # Future-dated => treated as undated (fail-safe: kept). Returns a Date or $null.
  $d = $null
  $dt = [datetime]::MinValue
  if($archivedAtStr -and [datetime]::TryParse([string]$archivedAtStr,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind,[ref]$dt)){ $d = $dt.Date }
  if($null -eq $d){ $s = Get-StampDate $folderName; if($s){ $d = $s.Date } }
  if($null -eq $d){ return $null }
  if($d -gt $now.Date.AddDays(1)){ return $null }
  return $d
}

function Test-Removable($entryDate,$cutoff){
  if($null -eq $entryDate -or $null -eq $cutoff){ return $false }   # unknown age => keep
  return ($entryDate -lt $cutoff)
}

function Get-EntriesToClean($entries,$cutoff){
  # $entries: objects with .date (DateTime or $null). Returns the removable subset. (pure)
  return @($entries | Where-Object { Test-Removable $_.date $cutoff })
}

function Test-PathWithinRoot($childFull,$rootFull){
  # pure string containment on already-RESOLVED full paths. child must be strictly under root
  # (separator-terminated boundary so 'archive-EVIL' cannot match 'archive'); root itself is not a child.
  if(-not $childFull -or -not $rootFull){ return $false }
  $r = ([string]$rootFull).TrimEnd('\','/')
  $c = ([string]$childFull).TrimEnd('\','/')
  if($c.Equals($r,[StringComparison]::OrdinalIgnoreCase)){ return $false }
  $rSep = $r + [IO.Path]::DirectorySeparatorChar
  return $c.StartsWith($rSep,[StringComparison]::OrdinalIgnoreCase)
}

function Test-SafeClientToken($name){
  # a client scope/name must be a single segment - no path separators or traversal.
  $s = [string]$name
  if(-not $s){ return $false }
  return -not ($s -match '[\\/:]' -or $s.Contains('..'))
}

function Assert-NoCredential($text){
  if([string]$text -match $script:CredRx){ throw "credential pattern detected - refusing (share key must never enter the archive)" }
}

function Test-HasCredProps($obj){
  if($null -eq $obj -or $null -eq $obj.meta){ return $false }
  $n = @($obj.meta.PSObject.Properties.Name)
  return (($n -contains 'shareKey') -or ($n -contains 'shareUrl'))
}

# ---------------- FS helpers (I/O; used only in the run section) ----------------
function Resolve-Full($path){ return [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $path).ProviderPath) }

function Test-IsReparse($path){
  try { $it = Get-Item -LiteralPath $path -Force -ErrorAction Stop } catch { return $false }
  return (($it.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)
}

function Test-EntryHasReparse($entryPath){
  if(Test-IsReparse $entryPath){ return $true }
  $rp = @(Get-ChildItem -LiteralPath $entryPath -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 })
  return ($rp.Count -gt 0)
}

function Read-Manifest($entryDir){
  $mf = Join-Path $entryDir 'manifest.json'
  if(-not (Test-Path -LiteralPath $mf)){ return $null }
  try { return ([IO.File]::ReadAllText($mf) | ConvertFrom-Json) } catch { return $null }
}

function Get-DirSize($dir){
  $b = 0; foreach($f in @(Get-ChildItem -LiteralPath $dir -Recurse -Force -File -ErrorAction SilentlyContinue)){ $b += $f.Length }
  return $b
}
function Format-Size($bytes){ if($bytes -ge 1MB){ return ("{0:N1} MB" -f ($bytes/1MB)) } elseif($bytes -ge 1KB){ return ("{0:N0} KB" -f ($bytes/1KB)) } else { return "$bytes B" } }

# Enumerate archive entries as objects {client, slug, stamp, path, manifest, ageDate}.
function Get-ArchiveEntries($rootFull,$now){
  $out = New-Object System.Collections.ArrayList
  if(-not (Test-Path -LiteralPath $rootFull)){ return $out }
  foreach($clientDir in @(Get-ChildItem -LiteralPath $rootFull -Directory -Force -ErrorAction SilentlyContinue)){
    foreach($entryDir in @(Get-ChildItem -LiteralPath $clientDir.FullName -Directory -Force -ErrorAction SilentlyContinue)){
      $mf = Read-Manifest $entryDir.FullName
      $archivedAt = if($mf){ $mf.archivedAt } else { $null }
      $client = if($mf -and $mf.client){ [string]$mf.client } else { $clientDir.Name }
      [void]$out.Add([ordered]@{
        client=$client; slug=$clientDir.Name; stamp=$entryDir.Name; path=$entryDir.FullName
        manifest=$mf; date=(Get-EntryAgeDate $archivedAt $entryDir.Name $now)
      })
    }
  }
  return $out
}

if($DefineOnly){ return }

function Die($m,$c){ [Console]::Error.WriteLine([string]$m); exit [int]$c }

# ============================ run ============================
$modes = @($Store,$List,$Cleanup) | Where-Object { $_ }
if($modes.Count -ne 1){ Die 'Specify exactly one mode: -Store | -List | -Cleanup' 2 }
$now = Get-Date

# ---- STORE ----
if($Store){
  if(-not $Facts -or -not (Test-Path -LiteralPath $Facts)){ Die '-Store requires -Facts <facts.json>' 2 }
  $factsObj = [IO.File]::ReadAllText($Facts) | ConvertFrom-Json
  # credential gate over every input: structural (meta.shareKey/shareUrl) + regex grep.
  $inputs = @()
  foreach($pair in @(@('facts',$Facts),@('report',$Report),@('draft',$Draft),@('extraction',$Extraction))){
    $role=$pair[0]; $p=$pair[1]
    if(-not $p){ continue }
    if(-not (Test-Path -LiteralPath $p)){ Die "$role not found: $p" 2 }
    $txt = [IO.File]::ReadAllText($p)
    try { Assert-NoCredential $txt } catch { Die ("$role file '$p' contains a share credential - refusing to archive. Pass the scrubbed copy.") 3 }
    if($p -match '\.json$'){ try { if(Test-HasCredProps ([IO.File]::ReadAllText($p) | ConvertFrom-Json)){ Die "$role '$p' still has meta.shareKey/shareUrl - refusing." 3 } } catch {} }
    $inputs += ,@($role,$p)
  }
  $clientName = if($Client){ $Client } elseif($factsObj.meta.reportName){ [string]$factsObj.meta.reportName } else { 'client' }
  $slug = Get-ClientSlug $clientName
  $rootFull = [IO.Path]::GetFullPath($ArchiveRoot)
  # slug-collision disambiguation: if the slug dir exists with a DIFFERENT client, suffix a short hash.
  $slugDir = Join-Path $rootFull $slug
  if(Test-Path -LiteralPath $slugDir){
    $existing = @(Get-ArchiveEntries $rootFull $now | Where-Object { $_.slug -eq $slug } | Select-Object -First 1)
    if($existing.Count -gt 0 -and $existing[0].client -and -not ($existing[0].client -eq $clientName)){
      $h = [BitConverter]::ToString((New-Object Security.Cryptography.SHA1Managed).ComputeHash([Text.Encoding]::UTF8.GetBytes($clientName))).Replace('-','').Substring(0,8).ToLower()
      $slug = "$slug-$h"; $slugDir = Join-Path $rootFull $slug
    }
  }
  New-Item -ItemType Directory -Force -Path $rootFull | Out-Null
  $sentinel = Join-Path $rootFull $script:Sentinel
  if(-not (Test-Path -LiteralPath $sentinel)){ [IO.File]::WriteAllText($sentinel,"swydee archive root`n",(New-Object Text.UTF8Encoding($false))) }
  # entry dir = archivedAt stamp; disambiguate same-second collisions.
  $stamp = $now.ToString('yyyy-MM-dd-HH-mm-ss'); $entryDir = Join-Path $slugDir $stamp; $n=2
  while(Test-Path -LiteralPath $entryDir){ $entryDir = Join-Path $slugDir "$stamp-$n"; $n++ }
  New-Item -ItemType Directory -Force -Path $entryDir | Out-Null
  $files = New-Object System.Collections.ArrayList
  foreach($pair in $inputs){
    $role=$pair[0]; $p=$pair[1]; $dest = Join-Path $entryDir (Split-Path $p -Leaf)
    Copy-Item -LiteralPath $p -Destination $dest -Force
    $sha = (Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash.ToLower()
    [void]$files.Add([ordered]@{ name=(Split-Path $dest -Leaf); role=$role; bytes=(Get-Item -LiteralPath $dest).Length; sha256=$sha })
  }
  $manifest = [ordered]@{
    manifestVersion = 1
    client          = $clientName
    clientSlug      = $slug
    reportName      = (Get-ClientSlug $factsObj.meta.reportName)   # slugified; no raw operator text
    periodLabel     = [string]$factsObj.meta.periodLabel
    scrapeDate      = [string]$factsObj.meta.extractedAt
    archivedAt      = $now.ToString('o')
    files           = @($files)
  }
  $mjson = $manifest | ConvertTo-Json -Depth 20
  Assert-NoCredential $mjson                                        # never let the manifest carry a credential
  [IO.File]::WriteAllText((Join-Path $entryDir 'manifest.json'),$mjson,(New-Object Text.UTF8Encoding($false)))
  Write-Host ("stored -> {0}\{1}\{2}  ({3} file(s), client '{4}')" -f (Split-Path $rootFull -Leaf),$slug,(Split-Path $entryDir -Leaf),$files.Count,$clientName)
  exit 0
}

# ---- LIST ----
if($List){
  $rootFull = [IO.Path]::GetFullPath($ArchiveRoot)
  if(-not (Test-Path -LiteralPath $rootFull)){ Write-Host "archive is empty (no $rootFull)"; exit 0 }
  $entries = @(Get-ArchiveEntries $rootFull $now)
  if($Client){ $entries = @($entries | Where-Object { $_.client -and $_.client.Equals($Client,[StringComparison]::OrdinalIgnoreCase) }) }
  if($entries.Count -eq 0){ Write-Host 'no matching entries.'; exit 0 }
  $total = 0
  foreach($grp in ($entries | Group-Object { $_.client } | Sort-Object Name)){   # script-block: reads the key off the ordered-dict
    Write-Host ("`n{0}  ({1} entr{2})" -f $grp.Name,$grp.Count,$(if($grp.Count -eq 1){'y'}else{'ies'}))
    foreach($e in ($grp.Group | Sort-Object stamp)){
      $sz = Get-DirSize $e.path; $total += $sz
      $rel = "$($e.slug)\$($e.stamp)"
      $dlabel = if($e.date){ $e.date.ToString('yyyy-MM-dd') } else { 'UNDATED (not age-eligible)' }
      $line = ("  {0}  {1}  {2}  [{3} files, {4}]" -f $rel,$dlabel,[string]$e.manifest.periodLabel,@($e.manifest.files).Count,(Format-Size $sz))
      Assert-NoCredential $line
      Write-Host $line
    }
  }
  Write-Host ("`ntotal: {0} entr{1}, {2}" -f $entries.Count,$(if($entries.Count -eq 1){'y'}else{'ies'}),(Format-Size $total))
  exit 0
}

# ---- CLEANUP ----
if($Cleanup){
  $cutoff = Get-Cutoff $OlderThan $now
  if($null -eq $cutoff){ Die "-OlderThan must be one of: 7d | 1mo | 3mo | 1yr" 2 }
  # scope: exactly one of -Client / -All (XOR), enforced BEFORE any enumeration.
  $hasClient = [bool]$Client
  if($hasClient -eq [bool]$All){ Die 'Cleanup scope: specify exactly one of -Client <name> or -All' 2 }
  if($hasClient -and -not (Test-SafeClientToken $Client)){ Die "unsafe -Client value" 2 }
  if(-not (Test-Path -LiteralPath $ArchiveRoot)){ Write-Host "nothing to clean (no archive at $ArchiveRoot)"; exit 0 }
  $rootFull = Resolve-Full $ArchiveRoot
  # root safety (esp. for -All): not a drive root, not $HOME, not a reparse point, has the sentinel.
  if($rootFull.TrimEnd('\','/').Length -le 2){ Die "refusing: ArchiveRoot resolves to a drive root ($rootFull)" 2 }
  if($rootFull.Equals([IO.Path]::GetFullPath($HOME),[StringComparison]::OrdinalIgnoreCase)){ Die "refusing: ArchiveRoot is your home directory" 2 }
  if(Test-IsReparse $rootFull){ Die "refusing: ArchiveRoot is a reparse point (symlink/junction)" 2 }
  if(-not (Test-Path -LiteralPath (Join-Path $rootFull $script:Sentinel))){ Die "refusing: '$rootFull' has no $($script:Sentinel) sentinel - not a swydee archive (was anything ever stored here?)" 2 }

  $entries = @(Get-ArchiveEntries $rootFull $now)
  if($hasClient){ $entries = @($entries | Where-Object { $_.client -and $_.client.Equals($Client,[StringComparison]::OrdinalIgnoreCase) }) }
  $removable = @(Get-EntriesToClean $entries $cutoff)
  $undated   = @($entries | Where-Object { $null -eq $_.date })

  $modeLabel = if($Execute){'EXECUTE'}else{'DRY-RUN'}
  $scopeLabel = if($hasClient){"client '$Client'"}else{'ALL clients'}
  Write-Host ("Cleanup {0} | older than {1} (cutoff {2}) | scope: {3}" -f $modeLabel,$OlderThan,$cutoff.ToString('yyyy-MM-dd'),$scopeLabel)
  if($removable.Count -eq 0){ Write-Host '  nothing is old enough to remove.' }
  else {
    $sz=0
    foreach($e in ($removable | Sort-Object stamp)){ $s=Get-DirSize $e.path; $sz+=$s; Write-Host ("  remove: {0}\{1}  ({2}, {3})" -f $e.slug,$e.stamp,$e.date.ToString('yyyy-MM-dd'),(Format-Size $s)) }
    Write-Host ("  => {0} entr{1}, {2}" -f $removable.Count,$(if($removable.Count -eq 1){'y'}else{'ies'}),(Format-Size $sz))
  }
  if($undated.Count -gt 0){ Write-Host ("  ({0} undated/unparseable entr{1} skipped - never auto-deleted)" -f $undated.Count,$(if($undated.Count -eq 1){'y'}else{'ies'})) }

  if(-not $Execute){ Write-Host "`n(dry-run) re-run with -Execute to delete the above."; exit 0 }

  # ---- deletion: per-entry, contained, reparse-safe ----
  $ok=0; $failed=0
  foreach($e in $removable){
    $entryFull = $null
    try { $entryFull = Resolve-Full $e.path } catch { Write-Host ("  SKIP (unresolvable): {0}" -f $e.stamp); $failed++; continue }
    if(-not (Test-PathWithinRoot $entryFull $rootFull)){ Write-Host ("  SKIP (outside archive root): {0}" -f $entryFull); $failed++; continue }
    if(Test-EntryHasReparse $entryFull){ Write-Host ("  SKIP (contains a junction/symlink - remove it by hand): {0}\{1}" -f $e.slug,$e.stamp); $failed++; continue }
    try {
      foreach($f in @(Get-ChildItem -LiteralPath $entryFull -Recurse -Force -File -ErrorAction SilentlyContinue)){ if($f.IsReadOnly){ $f.IsReadOnly=$false } }
      [IO.Directory]::Delete($entryFull,$true)   # .NET recursive delete: removes junction links, never traverses them
      $ok++
    } catch { Write-Host ("  FAILED to delete {0}\{1}: {2}" -f $e.slug,$e.stamp,$_.Exception.Message); $failed++ }
  }
  Write-Host ("`ndeleted {0} entr{1}; {2} failed/skipped." -f $ok,$(if($ok -eq 1){'y'}else{'ies'}),$failed)
  if($failed -gt 0){ exit 1 }
  exit 0
}
