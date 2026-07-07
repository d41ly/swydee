# Tests for Manage-SwydoArchive.ps1 — pure helpers (dot-source -DefineOnly) + FS integration (subprocess).
# PS 5.1. Run: powershell -File Test-Archive.ps1
$ErrorActionPreference = 'Stop'
$script:tool = "$PSScriptRoot\skill\scripts\Manage-SwydoArchive.ps1"
. $script:tool -DefineOnly

$script:pass=0; $script:fail=0
function Ok($c,$n){ if($c){ $script:pass++ } else { $script:fail++; Write-Host "FAIL: $n" -ForegroundColor Red } }
function Threw($block){ try { & $block; return $false } catch { return $true } }

# ---------------- pure helpers ----------------
Ok ((Get-ClientSlug 'Quincy Credit Union (QCU) Data Extraction Template') -eq 'quincy-credit-union-qcu-data-extraction-template') 'slug: full name'
Ok ((Get-ClientSlug 'Acme, Inc.') -eq 'acme-inc') 'slug: punctuation collapses'
Ok ((Get-ClientSlug '') -eq 'client') 'slug: empty -> client'
Ok ((Get-ClientSlug '***') -eq 'client') 'slug: all-punct -> client'

$now = [datetime]'2026-07-06 14:30:00'
Ok ((Get-Cutoff '7d'  $now) -eq ([datetime]'2026-06-29')) 'cutoff 7d'
Ok ((Get-Cutoff '1mo' $now) -eq ([datetime]'2026-06-06')) 'cutoff 1mo'
Ok ((Get-Cutoff '3mo' $now) -eq ([datetime]'2026-04-06')) 'cutoff 3mo'
Ok ((Get-Cutoff '1yr' $now) -eq ([datetime]'2025-07-06')) 'cutoff 1yr'
Ok ((Get-Cutoff '1mo' $now).TimeOfDay.Ticks -eq 0) 'cutoff is midnight-floored (C4)'
Ok ($null -eq (Get-Cutoff 'nonsense' $now)) 'cutoff: unknown token -> null'

Ok ((Get-StampDate '2026-07-06-18-02-37') -eq ([datetime]'2026-07-06 18:02:37')) 'stampdate: valid'
Ok ($null -eq (Get-StampDate 'legacy-data')) 'stampdate: non-stamp -> null'
Ok ($null -eq (Get-StampDate '2026-13-45-99-99-99')) 'stampdate: invalid calendar -> null'
Ok ($null -eq (Get-StampDate '1999-01-01-00-00-00')) 'stampdate: pre-2000 -> null'

# C4 boundary: an entry exactly 1 month old (by calendar day) is KEPT even when run mid-afternoon
$cut = Get-Cutoff '1mo' $now
Ok (-not (Test-Removable ([datetime]'2026-06-06') $cut)) 'C4: exactly-1mo-old kept (boundary, time-of-day safe)'
Ok (Test-Removable ([datetime]'2026-06-05') $cut) 'older-than-1mo removable'
Ok (-not (Test-Removable ([datetime]'2026-07-01') $cut)) 'recent kept'
Ok (-not (Test-Removable $null $cut)) 'undated (null) kept'

Ok ((Get-EntryAgeDate '2026-01-02T00:00:00.0000000+00:00' '2026-06-30-00-00-00' $now) -eq ([datetime]'2026-01-02')) 'agedate: manifest archivedAt wins over folder stamp'
Ok ((Get-EntryAgeDate $null '2026-06-30-00-00-00' $now) -eq ([datetime]'2026-06-30')) 'agedate: falls back to folder stamp'
Ok ($null -eq (Get-EntryAgeDate $null 'legacy' $now)) 'agedate: neither -> null (undated)'
Ok ($null -eq (Get-EntryAgeDate '2099-01-01T00:00:00Z' 'x' $now)) 'agedate: future -> null (fail-safe keep)'

$rootF = 'C:\Users\me\swydee-archive'
Ok (Test-PathWithinRoot 'C:\Users\me\swydee-archive\acme\2026-01-01-00-00-00' $rootF) 'within: legit child'
Ok (-not (Test-PathWithinRoot 'C:\Users\me\swydee-archive-EVIL\x' $rootF)) 'within: sibling-prefix rejected (archive-EVIL)'
Ok (-not (Test-PathWithinRoot $rootF $rootF)) 'within: root itself is not a child'
Ok (Test-PathWithinRoot 'C:\USERS\ME\SWYDEE-ARCHIVE\acme\e' $rootF) 'within: case-insensitive'
Ok ((Normalize-Root '\\?\C:\Temp\a') -eq 'C:\Temp\a') 'normroot: strips extended-length prefix'
Ok ((Normalize-Root 'C:\Temp\a') -eq 'C:\Temp\a') 'normroot: plain path unchanged'
Ok ((Normalize-Root '\\?\UNC\srv\share\a') -eq '\\srv\share\a') 'normroot: UNC extended prefix -> \\'
$cs1=$null;$t1=$false; try { $cs1 = Test-ChainSafe 'C:\a\b' 'C:\zzz' } catch { $t1=$true }
Ok ((-not $t1) -and ($cs1 -eq $false)) 'chainsafe total: non-ancestor root -> false, no throw'
$cs2=$null;$t2=$false; try { $cs2 = Test-ChainSafe 'C:\x' 'C:\x' } catch { $t2=$true }
Ok ((-not $t2) -and ($cs2 -eq $false)) 'chainsafe total: equal path -> false, no throw'

Ok (Test-SafeClientToken 'Quincy Credit Union') 'client token: ok'
Ok (-not (Test-SafeClientToken '..\evil')) 'client token: traversal rejected'
Ok (-not (Test-SafeClientToken 'a/b')) 'client token: slash rejected'
Ok (-not (Test-SafeClientToken 'C:x')) 'client token: drive-relative rejected'

Ok (Threw { Assert-NoCredential 'see https://swy.do/shares/aB3x_K9-q2 now' }) 'cred: url with _- key throws'
Ok (Threw { Assert-NoCredential 'SWY.DO/SHARES/ABC123' }) 'cred: uppercase throws (case-insensitive)'
Ok (-not (Threw { Assert-NoCredential 'clean marketing prose, no keys' })) 'cred: clean text ok'
Ok (Test-HasCredProps ([pscustomobject]@{ meta=[pscustomobject]@{ shareKey='x' } })) 'credprops: shareKey detected'
Ok (Test-HasCredProps ([pscustomobject]@{ meta=[pscustomobject]@{ shareUrl='x' } })) 'credprops: shareUrl detected'
Ok (-not (Test-HasCredProps ([pscustomobject]@{ meta=[pscustomobject]@{ reportName='x' } }))) 'credprops: clean meta ok'
Ok (Test-CredName 'shareKey') 'credname: shareKey'
Ok (Test-CredName 'share_key') 'credname: share_key normalized'
Ok (Test-CredName 'apiToken') 'credname: apiToken'
Ok (-not (Test-CredName 'reportName')) 'credname: reportName is not credential-like'
Ok (Test-HasCredProps ([pscustomobject]@{ shareKey='K' })) 'credprops: TOP-LEVEL shareKey (no meta) detected'
Ok (Test-HasCredProps ([pscustomobject]@{ meta=[pscustomobject]@{ share_key='K' } })) 'credprops: renamed share_key detected'
Ok (Test-HasCredProps ([pscustomobject]@{ a=[pscustomobject]@{ b=[pscustomobject]@{ apiToken='K' } } })) 'credprops: deeply-nested token detected'
Ok (Threw { Assert-NoCredential 'app.swydo.com/g/short/reports/RID99' }) 'cred: short /g/ key now caught (regex floor dropped)'
Ok ((Get-EntryAgeDate '2026-06-06T00:30:00+13:00' 'x' $now) -eq ([datetime]'2026-06-06')) 'agedate: store-frame date from offset (tz-stable)'

# ---------------- client canonicalization (U1) ----------------
Ok ((Normalize-ClientName 'Quincy Credit Union (QCU) - Swydee Quarterly Data Export') -eq 'Quincy Credit Union (QCU)') 'normalize: strip quarterly export boilerplate'
Ok ((Normalize-ClientName 'Copy of Quincy Credit Union (QCU) - Swydee Monthly Data Export') -eq 'Quincy Credit Union (QCU)') 'normalize: strip Copy-of + monthly export boilerplate'
Ok ((Normalize-ClientName 'Acme Co') -eq 'Acme Co') 'normalize: plain name unchanged'
Ok ((Normalize-ClientName ' - Data Export') -ne '') 'normalize: never empties'
# same clientId -> the registered slug WINS even when the name differs (no re-split)
$reg = @{ 'idAAA' = [ordered]@{ slug='quincy-credit-union'; name='Quincy Credit Union' } }
$ra = Resolve-ClientSlug 'idAAA' 'Quincy Credit Union (QCU) - Swydee Monthly Data Export' $reg
Ok ($ra.slug -eq 'quincy-credit-union' -and $ra.source -eq 'id') 'resolve: known id -> registered slug wins'
# new id, same slug as a DIFFERENT id -> deduped with a suffix (never fuses two clients)
$rb = Resolve-ClientSlug 'idBBB' 'Quincy Credit Union' $reg
Ok ($rb.slug -ne 'quincy-credit-union' -and $rb.slug -like 'quincy-credit-union-*' -and $rb.isNew) 'resolve: different id + same name -> suffixed (no fuse)'
# new id, fresh slug
$rc = Resolve-ClientSlug 'idCCC' 'Fresh Client' @{}
Ok ($rc.slug -eq 'fresh-client' -and $rc.isNew -and $rc.source -eq 'newid') 'resolve: new id -> normalized slug, registrable'
# no clientId -> normalized-name slug, NOT registrable
$rd = Resolve-ClientSlug $null 'Copy of Foo - Report' @{}
Ok ($rd.slug -eq 'foo' -and (-not $rd.isNew) -and $rd.source -eq 'noid') 'resolve: no id -> normalized slug, not registrable'
# registry round-trip (write-temp-then-rename + cred gate)
$rtmp = Join-Path $env:TEMP ("clireg-" + [guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Force $rtmp | Out-Null
try {
  $w = [ordered]@{ version=1; clients=@{ 'idAAA'=[ordered]@{ slug='quincy-credit-union'; name='Quincy Credit Union'; aliases=@('Quincy Credit Union (QCU)'); firstSeen='2026-07-07T00:00:00Z'; lastSeen='2026-07-07T00:00:00Z' } } }
  Write-ClientRegistry $rtmp $w
  Ok (Test-Path (Join-Path $rtmp 'clients.json')) 'registry: written'
  $back = Read-ClientRegistry $rtmp
  Ok ($back.clients['idAAA'].slug -eq 'quincy-credit-union' -and (@($back.clients['idAAA'].aliases) -contains 'Quincy Credit Union (QCU)')) 'registry: round-trips slug + aliases'
  Ok (Threw { Write-ClientRegistry $rtmp ([ordered]@{ version=1; clients=@{ 'x'=[ordered]@{ slug='y'; name='https://swy.do/shares/LEAK' } } }) }) 'registry: fail-closed on a credential-shaped value'
} finally { Remove-Item -Recurse -Force $rtmp -ErrorAction SilentlyContinue }

# ---------------- FS integration (subprocess) ----------------
function RunTool { param([string[]]$a)
  $prev=$ErrorActionPreference; $ErrorActionPreference='Continue'
  $ef=[IO.Path]::GetTempFileName()
  try {
    $o = & powershell -NoProfile -ExecutionPolicy Bypass -File $script:tool @a 2>$ef   # stderr -> file (NOT 2>&1: that wraps + terminates in 5.1)
    $code=$LASTEXITCODE
    $err=Get-Content -Raw $ef -ErrorAction SilentlyContinue
    return @{ code=$code; out=(($o -join "`n") + "`n" + [string]$err) }
  } finally { $ErrorActionPreference=$prev; Remove-Item $ef -ErrorAction SilentlyContinue }
}

$tmp = Join-Path $env:TEMP ("swydee-archtest-" + [Guid]::NewGuid().ToString('N').Substring(0,8))
$root = Join-Path $tmp 'archive'
New-Item -ItemType Directory -Force $tmp | Out-Null
try {
  # a clean facts file + a credential-bearing one
  $cleanFacts = Join-Path $tmp 'clean.facts.json'
  [IO.File]::WriteAllText($cleanFacts, '{"meta":{"reportName":"Acme Bank Report","periodLabel":"Q2 2026","extractedAt":"2026-07-06T10:00:00Z"}}', (New-Object Text.UTF8Encoding($false)))
  $dirtyExtract = Join-Path $tmp 'raw.extraction.json'
  [IO.File]::WriteAllText($dirtyExtract, '{"meta":{"shareUrl":"https://swy.do/shares/ABC123def456","shareKey":"ABC123def456"}}', (New-Object Text.UTF8Encoding($false)))

  # STORE (clean) -> entry created + sentinel + manifest
  $r = RunTool @('-Store','-Facts',$cleanFacts,'-Client','Acme Bank','-ArchiveRoot',$root)
  Ok ($r.code -eq 0) "store clean: exit 0 ($($r.out))"
  Ok (Test-Path (Join-Path $root '.swydee-archive')) 'store: sentinel written'
  $entry = @(Get-ChildItem -Recurse -Filter manifest.json $root)
  Ok ($entry.Count -eq 1) 'store: one manifest created'

  # STORE with a credential-bearing extraction -> REFUSED, nothing archived
  $r2 = RunTool @('-Store','-Facts',$cleanFacts,'-Extraction',$dirtyExtract,'-Client','Acme Bank','-ArchiveRoot',$root)
  Ok ($r2.code -ne 0) 'store: credential-bearing extraction refused (non-zero)'
  Ok (@(Get-ChildItem -Recurse -Filter manifest.json $root).Count -eq 1) 'store: refusal archived nothing new'
  # a credential-bearing extraction with a NON-.json extension is still refused (structural check is not gated on extension)
  $dirtyTxt = Join-Path $tmp 'raw.extraction.txt'
  [IO.File]::WriteAllText($dirtyTxt, '{"meta":{"shareKey":"LIVEKEY_txt"}}', (New-Object Text.UTF8Encoding($false)))
  $r3 = RunTool @('-Store','-Facts',$cleanFacts,'-Extraction',$dirtyTxt,'-Client','Acme Bank','-ArchiveRoot',$root)
  Ok ($r3.code -ne 0) 'store: .txt extraction with a key field refused (extension-independent)'
  Ok (@(Get-ChildItem -Recurse -Filter manifest.json $root).Count -eq 1) 'store: .txt refusal archived nothing new'
  # a share URL hidden as \u-escaped JSON in a value: raw-text grep misses it, re-serialize catches it; no orphan left
  $escFacts = Join-Path $tmp 'esc.facts.json'
  # a share URL embedded in a facts VALUE (not just meta.shareUrl) must be refused, and must leave no
  # orphan entry behind (input gate fires before the entry dir is created; rollback covers late failures).
  [IO.File]::WriteAllText($escFacts, '{"meta":{"reportName":"r","periodLabel":"see https://swy.do/shares/LiveKey123456","extractedAt":"2026-07-06T10:00:00Z"}}', (New-Object Text.UTF8Encoding($false)))
  $r4 = RunTool @('-Store','-Facts',$escFacts,'-Client','EscTest','-ArchiveRoot',$root)
  Ok ($r4.code -ne 0) 'store: share URL in a facts value refused'
  Ok (-not (Test-Path (Join-Path $root 'esctest'))) 'store: refusal left NO orphan entry'

  # Build aged/undated entries by hand (Store always stamps "now"), + sentinel already present
  function New-AgedEntry($slug,$stamp,$client,$archivedAt){
    $d = Join-Path (Join-Path $root $slug) $stamp; New-Item -ItemType Directory -Force $d | Out-Null
    $mf = [ordered]@{ manifestVersion=1; client=$client; clientSlug=$slug; archivedAt=$archivedAt; periodLabel='Q1 2026'; files=@() }
    [IO.File]::WriteAllText((Join-Path $d 'manifest.json'), ($mf|ConvertTo-Json -Depth 10), (New-Object Text.UTF8Encoding($false)))
    [IO.File]::WriteAllText((Join-Path $d 'facts.json'), '{"ok":1}', (New-Object Text.UTF8Encoding($false)))
    return $d
  }
  $old = New-AgedEntry 'globex' '2025-01-01-00-00-00' 'Globex' ((Get-Date).AddMonths(-6).ToString('o'))
  $recent = New-AgedEntry 'globex' '2026-07-01-00-00-00' 'Globex' ((Get-Date).AddDays(-2).ToString('o'))
  $undated = New-AgedEntry 'globex' 'legacy-import' 'Globex' ''

  # LIST shows client names in the group header (Group-Object key off ordered-dict)
  $lst = RunTool @('-List','-ArchiveRoot',$root)
  Ok ($lst.out -match 'Globex' -and $lst.out -match 'Acme Bank') 'list: client-group headers are populated'

  # scope guards
  Ok ((RunTool @('-Cleanup','-OlderThan','7d','-ArchiveRoot',$root)).code -ne 0) 'cleanup: no scope -> error'
  Ok ((RunTool @('-Cleanup','-OlderThan','7d','-All','-Client','Globex','-ArchiveRoot',$root)).code -ne 0) 'cleanup: both scopes -> error'
  Ok ((RunTool @('-Cleanup','-OlderThan','bogus','-All','-ArchiveRoot',$root)).code -ne 0) 'cleanup: bad threshold -> error'

  # DRY-RUN: lists the old one, deletes nothing
  $dr = RunTool @('-Cleanup','-OlderThan','1mo','-Client','Globex','-ArchiveRoot',$root)
  Ok ($dr.code -eq 0 -and $dr.out -match 'DRY-RUN' -and $dr.out -match '2025-01-01') 'cleanup dry-run: previews the old entry'
  Ok ((Test-Path $old) -and (Test-Path $recent) -and (Test-Path $undated)) 'cleanup dry-run: deletes NOTHING'

  # crafted junction inside the OLD entry, pointing at a victim dir with a canary (tests C2)
  $victim = Join-Path $tmp 'victim'; New-Item -ItemType Directory -Force $victim | Out-Null
  $canary = Join-Path $victim 'canary.txt'; [IO.File]::WriteAllText($canary,'do not delete',(New-Object Text.UTF8Encoding($false)))
  $junctionMade = $false
  try { New-Item -ItemType Junction -Path (Join-Path $old 'link') -Target $victim -ErrorAction Stop | Out-Null; $junctionMade = $true } catch {}

  # EXECUTE: old removed (unless it has the junction -> skipped), recent + undated kept, victim canary intact
  $ex = RunTool @('-Cleanup','-OlderThan','1mo','-Client','Globex','-Execute','-ArchiveRoot',$root)
  Ok (Test-Path $recent) 'cleanup execute: recent entry KEPT'
  Ok (Test-Path $undated) 'cleanup execute: undated entry KEPT (fail-safe)'
  Ok (Test-Path $canary) 'cleanup execute: junction victim canary INTACT (C2 - no traversal out of root)'
  if($junctionMade){ Ok ((Test-Path $old) -and ($ex.out -match 'junction|symlink')) 'cleanup execute: entry with a junction is SKIPPED, not deleted' }
  else { Ok (-not (Test-Path $old)) 'cleanup execute: old entry removed (junction unavailable, plain delete)' }

  # CRITICAL (ancestor junction): a junction at the CLIENT-DIR level must not let -Execute delete outside the root
  $victim2 = Join-Path $tmp 'victim2'; $vEntry = Join-Path $victim2 '2025-01-01-00-00-00'
  New-Item -ItemType Directory -Force $vEntry | Out-Null
  [IO.File]::WriteAllText((Join-Path $vEntry 'manifest.json'), (@{ manifestVersion=1; client='BigClient'; clientSlug='bigclient'; archivedAt=((Get-Date).AddMonths(-6).ToString('o')); periodLabel='x'; files=@() } | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
  $canary2 = Join-Path $vEntry 'report.md'; [IO.File]::WriteAllText($canary2,'OUTSIDE-ROOT canary',(New-Object Text.UTF8Encoding($false)))
  $ancJunc=$false
  try { New-Item -ItemType Junction -Path (Join-Path $root 'bigclient') -Target $victim2 -ErrorAction Stop | Out-Null; $ancJunc=$true } catch {}
  if($ancJunc){
    $exA = RunTool @('-Cleanup','-OlderThan','1mo','-Client','BigClient','-Execute','-ArchiveRoot',$root)
    Ok (Test-Path $canary2) 'CRITICAL: ancestor-junction victim OUTSIDE root SURVIVES -Execute'
    Ok ($exA.out -match 'parent folder is a junction') 'ancestor-junction entry SKIPPED with clear reason'
  } else { Write-Host '  (ancestor-junction test skipped: could not create junction)' }
}
finally {
  # best-effort cleanup of the test tree (remove any junctions first so we do not follow them)
  Get-ChildItem -Recurse -Force $tmp -ErrorAction SilentlyContinue | Where-Object { ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 } | ForEach-Object { try { [IO.Directory]::Delete($_.FullName,$false) } catch {} }
  Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

# ---------------- canon FS integration: same clientId across differently-titled reports -> ONE folder ----------------
$ctmp = Join-Path $env:TEMP ("canonfs-" + [guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Force $ctmp | Out-Null
try {
  function MkFacts($path,$cid,$name,$report){ [IO.File]::WriteAllText($path, (@{ meta=@{ tool='Analyze-SwydoReport.ps1'; factsVersion=1; clientId=$cid; client=$name; reportName=$report; periodLabel='Q2 2026'; extractedAt='2026-07-07T00:00:00Z' }; platforms=@(); findings=@{ wins=@();losses=@();anomalies=@();discrepancies=@();dataGaps=@() } } | ConvertTo-Json -Depth 20), (New-Object Text.UTF8Encoding($false))) }
  $arch=Join-Path $ctmp 'archive'
  $f1=Join-Path $ctmp 'q.facts.json'; MkFacts $f1 'mAfFiMTXCo29uAY4x' 'Quincy Credit Union' 'Quincy Credit Union (QCU) - Swydee Quarterly Data Export'
  $f2=Join-Path $ctmp 'm.facts.json'; MkFacts $f2 'mAfFiMTXCo29uAY4x' 'Quincy Credit Union' 'Copy of Quincy Credit Union (QCU) - Swydee Monthly Data Export'
  $s1=RunTool @('-Store','-Facts',$f1,'-ArchiveRoot',$arch)
  $s2=RunTool @('-Store','-Facts',$f2,'-ArchiveRoot',$arch)
  Ok ($s1.code -eq 0 -and $s2.code -eq 0) 'canon-fs: both stores exit 0'
  $clientDirs=@(Get-ChildItem -Directory $arch -ErrorAction SilentlyContinue)
  Ok ($clientDirs.Count -eq 1 -and $clientDirs[0].Name -eq 'quincy-credit-union') 'canon-fs: same clientId -> ONE folder (quincy-credit-union), not split by report title'
  Ok (Test-Path (Join-Path $arch 'clients.json')) 'canon-fs: registry written'
  $creg=[IO.File]::ReadAllText((Join-Path $arch 'clients.json'))|ConvertFrom-Json
  Ok ($creg.clients.'mAfFiMTXCo29uAY4x'.slug -eq 'quincy-credit-union') 'canon-fs: registry maps clientId -> slug'
  $f3=Join-Path $ctmp 'other.facts.json'; MkFacts $f3 'DIFFERENTID999' 'Quincy Credit Union' 'Quincy Credit Union - Export'
  $s3=RunTool @('-Store','-Facts',$f3,'-ArchiveRoot',$arch)
  Ok ($s3.code -eq 0 -and (@(Get-ChildItem -Directory $arch).Count -eq 2)) 'canon-fs: different clientId + same name -> distinct folder (no fuse)'
} finally { Remove-Item -Recurse -Force $ctmp -ErrorAction SilentlyContinue }

# ---------------- -MergeClient: fold a split folder into the canonical one ----------------
$mtmp = Join-Path $env:TEMP ("merge-" + [guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Force $mtmp | Out-Null
try {
  $arch=Join-Path $mtmp 'archive'; New-Item -ItemType Directory -Force $arch | Out-Null
  [IO.File]::WriteAllText((Join-Path $arch '.swydee-archive'),"x",(New-Object Text.UTF8Encoding($false)))
  function MkSnap($slug,$stamp){ $d=Join-Path (Join-Path $arch $slug) $stamp; New-Item -ItemType Directory -Force $d | Out-Null; [IO.File]::WriteAllText((Join-Path $d 'manifest.json'), (@{manifestVersion=1;client='Quincy Credit Union';clientSlug=$slug;archivedAt='2026-05-01T00:00:00Z';periodLabel='x';files=@()}|ConvertTo-Json), (New-Object Text.UTF8Encoding($false))) }
  function MkLedger($slug,$mo,$v,$fs){ [IO.File]::WriteAllText((Join-Path (Join-Path $arch $slug) 'ledger.json'), (@{ledgerVersion=1;client='Quincy Credit Union';updatedAt=$fs;cells=@{ ("g:clicks|bv|"+$mo)=@{providerId='g';metricId='g:clicks';basisVersion='bv';month=$mo;value=$v;display="$v";state='final';firstSeen=$fs;lastRefreshed=$fs;restatementCount=0;keptNullCount=0} };coverage=@{}}|ConvertTo-Json -Depth 10), (New-Object Text.UTF8Encoding($false))) }
  MkSnap 'quincy-credit-union-qcu' '2026-05-01-00-00-00'; MkLedger 'quincy-credit-union-qcu' '2025-01' 111 '2026-02-01T00:00:00Z'
  MkSnap 'quincy-credit-union'     '2026-06-01-00-00-00'; MkLedger 'quincy-credit-union'     '2025-02' 222 '2026-01-01T00:00:00Z'
  $dry = RunTool @('-MergeClient','-From','quincy-credit-union-qcu','-Into','quincy-credit-union','-ArchiveRoot',$arch)
  Ok ($dry.code -eq 0 -and (Test-Path (Join-Path $arch 'quincy-credit-union-qcu')) -and ($dry.out -match 'DRY-RUN')) 'mergeclient: dry-run previews, changes nothing'
  $ex = RunTool @('-MergeClient','-From','quincy-credit-union-qcu','-Into','quincy-credit-union','-ArchiveRoot',$arch,'-Execute')
  Ok ($ex.code -eq 0) 'mergeclient: execute exit 0'
  Ok (-not (Test-Path (Join-Path $arch 'quincy-credit-union-qcu'))) 'mergeclient: From folder removed'
  Ok ((Test-Path (Join-Path $arch 'quincy-credit-union\2026-05-01-00-00-00')) -and (Test-Path (Join-Path $arch 'quincy-credit-union\2026-06-01-00-00-00'))) 'mergeclient: both snapshots now under Into'
  $ml=[IO.File]::ReadAllText((Join-Path $arch 'quincy-credit-union\ledger.json'))|ConvertFrom-Json
  Ok (@($ml.cells.PSObject.Properties).Count -eq 2) 'mergeclient: ledgers unioned (2 cells)'
} finally { Remove-Item -Recurse -Force $mtmp -ErrorAction SilentlyContinue }

Write-Host ''
Write-Host ("Test-Archive: {0} passed, {1} failed." -f $script:pass,$script:fail)
if($script:fail -gt 0){ exit 1 }
