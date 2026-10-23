#Requires -Version 5.1
<#
  intent-guard installer (Windows / PowerShell 5.1+)

  - copies SKILL.md  -> <SkillsDir>\intent-guard\SKILL.md
  - appends AGENTS-snippet.md -> <AgentsFile>  (idempotent; skips if already present)
  - backs up <AgentsFile> before modifying

  Override targets:
    -SkillsDir   D:\some\dir          (default: $HOME\.agents\skills)
    -AgentsFile  D:\repo\AGENTS.md    (default: $HOME\.dsh\AGENTS.md)
#>
[CmdletBinding()]
param(
    [string]$SkillsDir  = $(if ($env:AGENTS_SKILLS_DIR) { $env:AGENTS_SKILLS_DIR } else { Join-Path $HOME '.agents\skills' }),
    [string]$AgentsFile = $(if ($env:AGENTS_FILE)       { $env:AGENTS_FILE }       else { Join-Path $HOME '.dsh\AGENTS.md' })
)

$ErrorActionPreference = 'Stop'
$root       = Split-Path -Parent $MyInvocation.MyCommand.Path
$skillSrc   = Join-Path $root 'SKILL.md'
$snippetSrc = Join-Path $root 'AGENTS-snippet.md'
$utf8       = New-Object System.Text.UTF8Encoding($false)

if (-not (Test-Path $skillSrc))   { throw "SKILL.md not found next to installer: $skillSrc" }
if (-not (Test-Path $snippetSrc)) { throw "AGENTS-snippet.md not found next to installer: $snippetSrc" }

# --- 1. skill body ---------------------------------------------------------
$skillDestDir = Join-Path $SkillsDir 'intent-guard'
New-Item -ItemType Directory -Force -Path $skillDestDir | Out-Null
Copy-Item $skillSrc (Join-Path $skillDestDir 'SKILL.md') -Force
Write-Host "[ok] skill  -> $(Join-Path $skillDestDir 'SKILL.md')"

# --- 2. resident block -----------------------------------------------------
$snippet = [System.IO.File]::ReadAllText($snippetSrc, [System.Text.Encoding]::UTF8).TrimEnd() + "`r`n"

if (-not (Test-Path $AgentsFile)) {
    $parent = Split-Path -Parent $AgentsFile
    if ($parent -and -not (Test-Path $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    [System.IO.File]::WriteAllText($AgentsFile, $snippet, $utf8)
    Write-Host "[ok] created $AgentsFile"
    return
}

$existing = [System.IO.File]::ReadAllText($AgentsFile, [System.Text.Encoding]::UTF8)
$hasStart = $existing -match '<!-- intent-guard:start -->'
$hasEnd   = $existing -match '<!-- intent-guard:end -->'
if ($hasStart -and $hasEnd) {
    Write-Host "[skip] '$AgentsFile' already contains the intent-guard marker block; left untouched."
    return
}
if (($existing -match 'intent-guard') -and (-not ($hasStart -and $hasEnd))) {
    Write-Host "[warn] '$AgentsFile' mentions 'intent-guard' but has NO complete marker block."
    Write-Host "       Possibly a manual note (e.g. 'do not use intent-guard') or a partial install."
    Write-Host "       Please inspect the file manually; aborting instead of appending a duplicate."
    Write-Host "       Expected markers: <!-- intent-guard:start --> ... <!-- intent-guard:end -->"
    return
}

$backup = "$AgentsFile.bak-intent-guard-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
Copy-Item $AgentsFile $backup -Force
$new = $existing.TrimEnd() + "`r`n`r`n" + $snippet
[System.IO.File]::WriteAllText($AgentsFile, $new, $utf8)

Write-Host "[ok] appended resident block -> $AgentsFile"
Write-Host "[bk] backup: $backup"
Write-Host ""
Write-Host "Rollback:"
Write-Host "  Remove-Item -Recurse -Force '$skillDestDir'"
Write-Host "  Copy-Item '$backup' '$AgentsFile' -Force"
