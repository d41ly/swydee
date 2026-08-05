<#
.SYNOPSIS
  Run swydee's full merge bar from PowerShell.

.DESCRIPTION
  Thin wrapper over tools/run-gates.sh, which is the single source of truth for the leg list
  (tools/gate-legs.json). This script exists only so the bar is reachable with swydee's native
  ergonomics; it deliberately does NOT maintain its own copy of the legs.

  It resolves git-bash by ABSOLUTE PATH on purpose. In PowerShell, bare `bash` resolves to WSL,
  which is a different git build operating on a /mnt/c mount - kit scripts run there mis-resolve
  the repo and report drift that does not exist.

  Exit code is the runner's: 0 = every leg passed, 1 = at least one failed, 2 = could not run.
#>
[CmdletBinding()]
param(
  # Pin a different baseline for the conditional (guarded) legs.
  [string]$GateBase
)

$ErrorActionPreference = 'Stop'

$candidates = @(
  (Join-Path $env:ProgramFiles 'Git\bin\bash.exe'),
  (Join-Path ${env:ProgramFiles(x86)} 'Git\bin\bash.exe'),
  (Join-Path $env:LOCALAPPDATA 'Programs\Git\bin\bash.exe')
)
$bash = $candidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $bash) {
  Write-Host "Run-Gates: git-bash not found. Looked in:" -ForegroundColor Red
  $candidates | ForEach-Object { Write-Host "  $_" }
  Write-Host "Do NOT substitute bare 'bash' - that is WSL, and the kit scripts misbehave there."
  exit 2
}

if ($GateBase) { $env:GATE_BASE = $GateBase }

# This script lives in tools/, but every kit script it invokes assumes cwd == repo root, so push the
# PARENT of $PSScriptRoot. Keeping the argument repo-root-relative ('tools/run-gates.sh') matches
# AGENTS.md 6 and the gate-legs.json argv convention, so all three read the same way.
Push-Location (Split-Path -Parent $PSScriptRoot)
try {
  & $bash 'tools/run-gates.sh'
  $code = $LASTEXITCODE
}
finally {
  Pop-Location
}

exit $code
