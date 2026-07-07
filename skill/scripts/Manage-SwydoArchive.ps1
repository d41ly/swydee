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
  [switch]$MergeClient,   # fold one client folder into another (-From <slug> -Into <slug>); dry-run then -Execute
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
  # MergeClient
  [string]$From,
  [string]$Into,
  [switch]$DefineOnly
)
$ErrorActionPreference = 'Stop'

# Canonical Swydo share-key pattern (matches Analyze / Test-ReportNumbers; key alphabet broadened to _-).
$script:CredRx   = '(?i)swy\.do/shares/[A-Za-z0-9_-]+|/g/[A-Za-z0-9_-]+/reports/'   # /g/ key can be short - extractor captures [^/]+
$script:StampRx  = '^\d{4}-\d{2}-\d{2}-\d{2}-\d{2}-\d{2}$'
$script:Sentinel = '.swydee-archive'

# ---------------- pure, unit-testable helpers ----------------
function Get-ClientSlug($name){
  $s = ([string]$name) -replace '[^A-Za-z0-9]+','-'
  $s = $s.Trim('-').ToLower()
  if(-not $s){ $s = 'client' }
  return $s
}
# Strip report-title boilerplate so a name-based slug is stable across a client's reports:
# drop a leading "Copy of ", and a trailing "- [Swydee] <word> [Data] Export/Report". Parentheticals kept.
function Normalize-ClientName($name){
  $s = [string]$name
  $s = $s -replace '(?i)^\s*copy of\s+',''
  $s = $s -replace '(?i)\s*[-:]\s*(swydee\s+)?\S+\s+(data\s+)?(export|report)\s*$',''
  $s = $s -replace '(?i)\s*[-:]\s*(data\s+)?(export|report)\s*$',''
  $s = ($s -replace '\s+',' ').Trim()
  if(-not $s){ return ([string]$name) }   # never normalize to empty
  return $s
}
function Get-ShortHash($s){
  $h = [BitConverter]::ToString((New-Object Security.Cryptography.SHA1Managed).ComputeHash([Text.Encoding]::UTF8.GetBytes([string]$s)))
  return $h.Replace('-','').Substring(0,8).ToLower()
}
# Canonical archive slug for a client. $existing = hashtable clientId -> @{slug;name}. Rules:
#  - a KNOWN clientId's registered slug WINS (stable; report title / -Client can't re-split it);
#  - a NEW clientId slugs from the normalized name, deduped against a slug owned by a DIFFERENT id;
#  - NO clientId => normalized-name slug, NOT registrable (can't dedupe safely without an id).
function Resolve-ClientSlug($clientId,$clientName,$existing){
  $cid = [string]$clientId
  if($cid -and $existing -and $existing.ContainsKey($cid)){
    return [ordered]@{ slug=[string]$existing[$cid].slug; name=[string]$existing[$cid].name; isNew=$false; source='id' }
  }
  $base = if([string]::IsNullOrWhiteSpace([string]$clientName)){ 'client' } else { [string]$clientName }
  $slug = Get-ClientSlug (Normalize-ClientName $base)
  # dedupe ONLY when we have a clientId to key on: suffix only if a DIFFERENT id already owns this slug.
  # A no-clientId client is NOT registrable and must resolve to the plain slug (never a divergent suffix,
  # which would SPLIT its folder - the inverse of canonicalization).
  if($cid -and $existing){
    foreach($k in @($existing.Keys)){ if(($k -ne $cid) -and ([string]$existing[$k].slug -eq $slug)){ $slug = $slug + '-' + (Get-ShortHash $cid); break } }
  }
  $src = if($cid){ 'newid' } else { 'noid' }
  return [ordered]@{ slug=$slug; name=$base; isNew=[bool]$cid; source=$src }
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
  # DateTimeOffset.Date keeps the STORE's offset, so a cleanup machine in a different tz/DST reads the
  # same calendar date (avoids boundary drift). Falls back to the folder stamp.
  $d = $null
  $dto = [DateTimeOffset]::MinValue
  if($archivedAtStr -and [DateTimeOffset]::TryParse([string]$archivedAtStr,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::None,[ref]$dto)){ $d = $dto.Date }
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

function Test-CredName($name){
  # normalized (strip non-alnum, lowercase) match against credential-like field names.
  $x = (([string]$name) -replace '[^A-Za-z0-9]','').ToLower()
  return ($x -in @('sharekey','shareurl','apikey','apitoken','accesstoken','accesskey','bearertoken','authtoken','secret','clientsecret','password','token','bearer','jwt'))
}
function Test-HasCredProps($obj){
  # RECURSIVE over the whole parsed object (not just .meta): true if ANY property name anywhere is
  # credential-like. Catches a top-level or renamed key (share_key/apiToken/token) that a swy.do-URL
  # regex misses. (URL-shaped values are caught separately by Assert-NoCredential over the file text.)
  if($null -eq $obj -or $obj -is [string] -or $obj -is [ValueType]){ return $false }
  if($obj -is [System.Collections.IEnumerable] -and -not ($obj -is [System.Collections.IDictionary])){
    foreach($i in $obj){ if(Test-HasCredProps $i){ return $true } }; return $false
  }
  $names=@(); $vals=New-Object System.Collections.ArrayList
  if($obj -is [System.Collections.IDictionary]){ foreach($k in $obj.Keys){ $names+=[string]$k; [void]$vals.Add($obj[$k]) } }
  elseif($obj.PSObject){ foreach($pp in $obj.PSObject.Properties){ $names+=[string]$pp.Name; [void]$vals.Add($pp.Value) } }
  foreach($nm in $names){ if(Test-CredName $nm){ return $true } }
  foreach($v in $vals){ if(Test-HasCredProps $v){ return $true } }
  return $false
}

# ---------------- FS helpers (I/O; used only in the run section) ----------------
function Normalize-Root($path){
  # strip a leading extended-length prefix (\\?\C:\.. or \\?\UNC\srv\..) that breaks Join-Path/Split-Path
  # under PS 5.1, then normalize. Keeps the location usable rather than crashing on it.
  $p = [string]$path
  if($p -match '^\\\\\?\\UNC\\'){ $p = '\\' + $p.Substring(8) }
  elseif($p -match '^\\\\\?\\'){ $p = $p.Substring(4) }
  return [IO.Path]::GetFullPath($p)
}
function Resolve-Full($path){ return (Normalize-Root (Resolve-Path -LiteralPath $path).ProviderPath) }

function Test-IsReparse($path){
  try { $it = Get-Item -LiteralPath $path -Force -ErrorAction Stop } catch { return $false }
  return (($it.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)
}

function Test-EntryHasReparse($entryPath){
  if(Test-IsReparse $entryPath){ return $true }
  $rp = @(Get-ChildItem -LiteralPath $entryPath -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 })
  return ($rp.Count -gt 0)
}

function Test-ChainSafe($entryFull,$rootFull){
  # TRUE only if NO reparse point sits on the ANCESTOR chain from the entry up to (not incl) root.
  # A junction at the client-dir level would otherwise let [IO.Directory]::Delete traverse OUT of the
  # archive (containment on the non-dereferenced path can't see it). Root is verified non-reparse earlier.
  if(-not (Test-PathWithinRoot $entryFull $rootFull)){ return $false }   # total: fail-safe on any non-ancestor/degenerate input
  $rootN = ([string]$rootFull).TrimEnd('\','/')
  $cur = ([string]$entryFull).TrimEnd('\','/')
  $guard = 0
  while($true){
    if(Test-IsReparse $cur){ return $false }
    $parent = Split-Path $cur -Parent
    if(-not $parent){ return $false }
    $parentN = ([string]$parent).TrimEnd('\','/')
    if($parentN.Equals($rootN,[StringComparison]::OrdinalIgnoreCase)){ break }
    if($parentN.Length -ge $cur.Length){ return $false }
    $cur = $parentN
    if(++$guard -gt 64){ return $false }
  }
  return $true
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

# Client registry: <ArchiveRoot>/clients.json maps a stable Swydo clientId -> canonical {slug,name,aliases}.
function Read-ClientRegistry($rootFull){
  $reg = [ordered]@{ version=1; clients=@{} }
  $p = Join-Path $rootFull 'clients.json'
  if(Test-Path -LiteralPath $p){
    # FAIL-CLOSED: an existing-but-unparseable registry must NOT silently become empty (a later Write would
    # then clobber every clientId->slug mapping and re-split folders). Refuse instead.
    $j=$null
    try { $j = [IO.File]::ReadAllText($p) | ConvertFrom-Json } catch { throw "client registry '$p' is unreadable/corrupt - refusing (would clobber existing client->slug mappings). Fix or remove it." }
    if($j -and $j.clients){ foreach($pp in $j.clients.PSObject.Properties){ $c=$pp.Value
      $reg.clients[$pp.Name]=[ordered]@{ slug=[string]$c.slug; name=[string]$c.name; aliases=@($c.aliases); firstSeen=[string]$c.firstSeen; lastSeen=[string]$c.lastSeen } } }
  }
  return $reg
}
function Write-ClientRegistry($rootFull,$reg){
  $p = Join-Path $rootFull 'clients.json'
  $json = ConvertTo-Json -InputObject $reg -Depth 20    # -InputObject: never pipe an ordered dict
  Assert-NoCredential $json
  if(Test-HasCredProps ($json | ConvertFrom-Json)){ throw 'client registry would carry a credential-like field - refusing' }
  $tmp = "$p.tmp"
  [IO.File]::WriteAllText($tmp,$json,(New-Object Text.UTF8Encoding($false)))
  if(Test-Path -LiteralPath $p){ [IO.File]::Replace($tmp,$p,"$p.bak") }   # atomic + keeps a backup (no Delete->Move gap)
  else { [IO.File]::Move($tmp,$p) }
}

if($DefineOnly){ return }

function Die($m,$c){ [Console]::Error.WriteLine([string]$m); exit [int]$c }

# ============================ run ============================
$modes = @($Store,$List,$Cleanup,$MergeClient) | Where-Object { $_ }
if($modes.Count -ne 1){ Die 'Specify exactly one mode: -Store | -List | -Cleanup | -MergeClient' 2 }
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
    # structural check on ANY input that parses as JSON (not gated on the .json extension - Copy-Item
    # archives whatever is passed, so a .txt/.dat with credential fields must not slip through).
    $parsed=$null; try { $parsed = $txt | ConvertFrom-Json } catch { $parsed=$null }
    if($null -ne $parsed){
      if(Test-HasCredProps $parsed){ Die "$role '$p' has a credential-like field (shareKey/shareUrl/token/secret...) - refusing. Scrub it (remove those fields)." 3 }
      # re-serialize to de-escape \u sequences, then regex again - catches a share URL hidden as escaped JSON.
      try { Assert-NoCredential ($parsed | ConvertTo-Json -Depth 100 -Compress) } catch { Die "$role '$p' embeds a share URL in its data (possibly escaped) - refusing." 3 }
    }
    $inputs += ,@($role,$p)
  }
  # Canonical client folder: key by the stable Swydo clientId via the registry (report title / -Client can't
  # re-split it); the canonical name prefers meta.client (Swydo entity) over -Client over reportName.
  $rootFull = Normalize-Root $ArchiveRoot
  New-Item -ItemType Directory -Force -Path $rootFull | Out-Null
  $clientId = [string]$factsObj.meta.clientId
  $canonName = if($factsObj.meta.client){ [string]$factsObj.meta.client } elseif($Client){ [string]$Client } elseif($factsObj.meta.reportName){ [string]$factsObj.meta.reportName } else { 'client' }
  $reg = Read-ClientRegistry $rootFull
  $res = Resolve-ClientSlug $clientId $canonName $reg.clients
  $slug = $res.slug; $clientName = $res.name
  if($clientId){
    if($reg.clients.ContainsKey($clientId)){
      $e = $reg.clients[$clientId]; $e.slug = $slug; $e.lastSeen = $now.ToString('o')
      foreach($al in @($canonName,$Client)){ if($al -and ($e.name -ne $al) -and (@($e.aliases) -notcontains $al)){ $e.aliases = @(@($e.aliases) + $al) } }
    } else {
      $al=@(); if($Client -and ($Client -ne $canonName)){ $al=@($Client) }
      $reg.clients[$clientId] = [ordered]@{ slug=$slug; name=$canonName; aliases=$al; firstSeen=$now.ToString('o'); lastSeen=$now.ToString('o') }
    }
    Write-ClientRegistry $rootFull $reg
  }
  $slugDir = Join-Path $rootFull $slug
  $sentinel = Join-Path $rootFull $script:Sentinel
  if(-not (Test-Path -LiteralPath $sentinel)){ [IO.File]::WriteAllText($sentinel,"swydee archive root`n",(New-Object Text.UTF8Encoding($false))) }
  # entry dir = archivedAt stamp; disambiguate same-second collisions.
  $stamp = $now.ToString('yyyy-MM-dd-HH-mm-ss'); $entryDir = Join-Path $slugDir $stamp; $n=2
  while(Test-Path -LiteralPath $entryDir){ $entryDir = Join-Path $slugDir "$stamp-$n"; $n++ }
  New-Item -ItemType Directory -Force -Path $entryDir | Out-Null
  # everything past dir-creation is wrapped: on ANY failure, roll back the partial entry so a
  # half-written entry (esp. one holding a copied credential file) can never be left behind.
  try {
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
      clientId        = $clientId
      clientSlug      = $slug
      reportName      = (Get-ClientSlug $factsObj.meta.reportName)   # slugified; no raw operator text
      periodLabel     = [string]$factsObj.meta.periodLabel
      scrapeDate      = [string]$factsObj.meta.extractedAt
      archivedAt      = $now.ToString('o')
      files           = @($files)
    }
    $mjson = $manifest | ConvertTo-Json -Depth 20
    Assert-NoCredential $mjson                                      # never let the manifest carry a credential
    [IO.File]::WriteAllText((Join-Path $entryDir 'manifest.json'),$mjson,(New-Object Text.UTF8Encoding($false)))
  } catch {
    try { [IO.Directory]::Delete($entryDir,$true) } catch {}        # rollback the partial entry
    Die ("store failed, rolled back partial entry: " + $_.Exception.Message) 3
  }
  Write-Host ("stored -> {0}\{1}\{2}  ({3} file(s), client '{4}')" -f (Split-Path $rootFull -Leaf),$slug,(Split-Path $entryDir -Leaf),$files.Count,$clientName)
  exit 0
}

# ---- LIST ----
if($List){
  $rootFull = Normalize-Root $ArchiveRoot
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
    if(-not (Test-ChainSafe $entryFull $rootFull)){ Write-Host ("  SKIP (a parent folder is a junction/symlink - would delete outside the archive): {0}\{1}" -f $e.slug,$e.stamp); $failed++; continue }
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

# ---- MERGE CLIENT (fold -From slug into -Into slug; dry-run then -Execute) ----
if($MergeClient){
  # Merge-Ledgers lives in Update-SwydoLedger; dot-sourcing it re-runs THIS script's param block (Update
  # dot-sources Manage) and would RESET $From/$Into/$Execute/$ArchiveRoot. So capture them first, dot-source
  # once, then use only the $mc* locals below.
  $mcFrom=[string]$From; $mcInto=[string]$Into; $mcExecute=[bool]$Execute; $mcRoot=$ArchiveRoot; $mcNow=$now
  . "$PSScriptRoot\Update-SwydoLedger.ps1" -DefineOnly     # Merge-Ledgers (+ Test-ValuesDiffer, Copy-Cell)
  if(-not $mcFrom -or -not $mcInto){ Die '-MergeClient requires -From <slug> -Into <slug>' 2 }
  if(-not (Test-SafeClientToken $mcFrom) -or -not (Test-SafeClientToken $mcInto)){ Die 'unsafe -From/-Into slug (single path segment only)' 2 }
  if($mcFrom.Equals($mcInto,[StringComparison]::OrdinalIgnoreCase)){ Die '-From and -Into are the same folder' 2 }
  if(-not (Test-Path -LiteralPath $mcRoot)){ Die "no archive at $mcRoot" 2 }
  $rootFull = Resolve-Full $mcRoot
  if(-not (Test-Path -LiteralPath (Join-Path $rootFull $script:Sentinel))){ Die "refusing: '$rootFull' is not a swydee archive (no $($script:Sentinel) sentinel)" 2 }
  $fromDir = Join-Path $rootFull $mcFrom
  if(-not (Test-Path -LiteralPath $fromDir)){ Die "-From folder not found: $mcFrom" 2 }
  $intoDir = Join-Path $rootFull $mcInto
  $fromFull = Resolve-Full $fromDir
  if(-not (Test-PathWithinRoot $fromFull $rootFull)){ Die "refusing: -From resolves outside the archive" 2 }
  if(-not (Test-ChainSafe $fromFull $rootFull) -or (Test-EntryHasReparse $fromFull)){ Die "refusing: -From contains or is reached through a junction/symlink" 2 }
  New-Item -ItemType Directory -Force -Path $intoDir | Out-Null

  $snaps = @(Get-ChildItem -LiteralPath $fromDir -Directory -Force -ErrorAction SilentlyContinue)
  $fromLedgerP = Join-Path $fromDir 'ledger.json'; $intoLedgerP = Join-Path $intoDir 'ledger.json'
  $mergedLedger=$null; $ledgerConflicts=@()
  if(Test-Path -LiteralPath $fromLedgerP){
    $fromObj = [IO.File]::ReadAllText($fromLedgerP) | ConvertFrom-Json
    $intoObj = $null; if(Test-Path -LiteralPath $intoLedgerP){ $intoObj = [IO.File]::ReadAllText($intoLedgerP) | ConvertFrom-Json }
    $m = Merge-Ledgers $intoObj $fromObj ($mcNow.ToString('o'))
    $mergedLedger = $m.ledger; $ledgerConflicts = @($m.conflicts)
  }
  $rootFiles = @(Get-ChildItem -LiteralPath $fromDir -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'ledger.json' })

  $modeLabel = if($mcExecute){'EXECUTE'}else{'DRY-RUN'}
  Write-Host ("MergeClient {0} | from '{1}' -> into '{2}'" -f $modeLabel,$mcFrom,$mcInto)
  Write-Host ("  snapshots to move: {0}" -f $snaps.Count); foreach($s in $snaps){ Write-Host ("    {0}" -f $s.Name) }
  if($mergedLedger){ Write-Host ("  ledger: union -> {0} cell(s), {1} conflict(s) (older-firstSeen kept; newer noted as restatement)" -f @($mergedLedger.cells.Keys).Count,$ledgerConflicts.Count); foreach($c in $ledgerConflicts){ Write-Host ("    conflict {0}: keep {1} / note {2}" -f $c.key,$c.kept,$c.dropped) } }
  Write-Host ("  other files to move: {0}" -f $rootFiles.Count); foreach($f in $rootFiles){ Write-Host ("    {0}" -f $f.Name) }
  if(-not $mcExecute){ Write-Host "`n(dry-run) re-run with -Execute to merge and delete '$mcFrom'."; exit 0 }

  foreach($s in $snaps){ $dest=Join-Path $intoDir $s.Name; $n=2; while(Test-Path -LiteralPath $dest){ $dest=Join-Path $intoDir ($s.Name + "-m$n"); $n++ }; Move-Item -LiteralPath $s.FullName -Destination $dest -Force }
  if($mergedLedger){ $json = ConvertTo-Json -InputObject $mergedLedger -Depth 100 -Compress; Assert-NoCredential $json; if(Test-HasCredProps ($json | ConvertFrom-Json)){ Die 'merged ledger has a credential-like field - refusing' 3 }; [IO.File]::WriteAllText($intoLedgerP,$json,(New-Object Text.UTF8Encoding($false))); if(Test-Path -LiteralPath $fromLedgerP){ [IO.File]::Delete($fromLedgerP) } }
  foreach($f in $rootFiles){ $base=[IO.Path]::GetFileNameWithoutExtension($f.Name); $ext=[IO.Path]::GetExtension($f.Name); $dest=Join-Path $intoDir $f.Name; $n=2; while(Test-Path -LiteralPath $dest){ $dest=Join-Path $intoDir ("$base-m$n$ext"); $n++ }; Move-Item -LiteralPath $f.FullName -Destination $dest -Force }
  if((Test-ChainSafe $fromFull $rootFull) -and -not (Test-EntryHasReparse $fromFull)){ try { [IO.Directory]::Delete($fromFull,$true) } catch { Write-Host ("  (could not remove empty '$mcFrom': " + $_.Exception.Message + ")") } }
  # re-point any registry client whose slug was $mcFrom -> $mcInto
  $reg = Read-ClientRegistry $rootFull; $changed=$false
  foreach($cid in @($reg.clients.Keys)){ if($reg.clients[$cid].slug -eq $mcFrom){ $reg.clients[$cid].slug = $mcInto; $changed=$true } }
  if($changed){ Write-ClientRegistry $rootFull $reg }
  Write-Host ("`nmerged '{0}' -> '{1}' ({2} snapshot(s), {3} file(s){4})." -f $mcFrom,$mcInto,$snaps.Count,$rootFiles.Count,$(if($mergedLedger){", ledger unioned"}else{""}))
  exit 0
}
