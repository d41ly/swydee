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
}
finally {
  # best-effort cleanup of the test tree (remove any junctions first so we do not follow them)
  Get-ChildItem -Recurse -Force $tmp -ErrorAction SilentlyContinue | Where-Object { ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 } | ForEach-Object { try { [IO.Directory]::Delete($_.FullName,$false) } catch {} }
  Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host ("Test-Archive: {0} passed, {1} failed." -f $script:pass,$script:fail)
if($script:fail -gt 0){ exit 1 }
