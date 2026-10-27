#Requires -Version 5.1
<#
  intent-guard installer (Windows / PowerShell 5.1+)

  - copies SKILL.md  -> <SkillsDir>\intent-guard\SKILL.md
  - writes AGENTS-snippet.md into <AgentsFile>
    (idempotent: replaces an existing marker block; skips only when unchanged)
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
# Repo snippet is LF; normalise to the target file's EOL so we never mix endings.
$snippetRaw = [System.IO.File]::ReadAllText($snippetSrc, [System.Text.Encoding]::UTF8)
$snippetLf  = ($snippetRaw -replace "`r`n", "`n").TrimEnd()
function WithEol([string]$text, [string]$eol) { ($text -replace "`n", $eol) + $eol }

if (-not (Test-Path $AgentsFile)) {
    $parent = Split-Path -Parent $AgentsFile
    if ($parent -and -not (Test-Path $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    [System.IO.File]::WriteAllText($AgentsFile, (WithEol $snippetLf "`n"), $utf8)
    Write-Host "[ok] created $AgentsFile"
    return
}

$existing = [System.IO.File]::ReadAllText($AgentsFile, [System.Text.Encoding]::UTF8)
$hasStart = $existing -match '<!-- intent-guard:start -->'
$hasEnd   = $existing -match '<!-- intent-guard:end -->'
if (($existing -match 'intent-guard') -and (-not ($hasStart -and $hasEnd))) {
    Write-Host "[warn] '$AgentsFile' mentions 'intent-guard' but has NO complete marker block."
    Write-Host "       Possibly a manual note (e.g. 'do not use intent-guard') or a partial install."
    Write-Host "       Please inspect the file manually; aborting instead of appending a duplicate."
    Write-Host "       Expected markers: <!-- intent-guard:start --> ... <!-- intent-guard:end -->"
    return
}

# Existing marker block: replace in place so upgrades reach already-installed hosts.
if ($hasStart -and $hasEnd) {
    # Parity with install.sh: exactly one start, one end, and end after start.
    $startCount = ([regex]::Matches($existing, [regex]::Escape('<!-- intent-guard:start -->'))).Count
    $endCount   = ([regex]::Matches($existing, [regex]::Escape('<!-- intent-guard:end -->'))).Count
    $startIdx   = $existing.IndexOf('<!-- intent-guard:start -->')
    $endIdx     = $existing.IndexOf('<!-- intent-guard:end -->')
    if (($startCount -ne 1) -or ($endCount -ne 1) -or ($endIdx -lt $startIdx)) {
        Write-Host "[error] marker block is reversed or duplicated in '$AgentsFile'; left untouched."
        Write-Host "        Expect exactly one <!-- intent-guard:start --> followed by one <!-- intent-guard:end -->."
        Write-Host "        Fix the file manually, then re-run the installer."
        return
    }
    $eol = if ($existing -match "`r`n") { "`r`n" } else { "`n" }
    $body = WithEol $snippetLf $eol
    $pattern = '(?s)<!-- intent-guard:start -->.*?<!-- intent-guard:end -->'
    $replaced = [regex]::Replace($existing, $pattern, $body.TrimEnd(), 1)
    if ($replaced -eq $existing) {
        Write-Host "[skip] marker block already matches; left untouched."
        return
    }
    $backup = "$AgentsFile.bak-intent-guard-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Copy-Item $AgentsFile $backup -Force
    [System.IO.File]::WriteAllText($AgentsFile, $replaced, $utf8)
    Write-Host "[ok] replaced resident block -> $AgentsFile"
    Write-Host "[bk] backup: $backup"
    return
}

$backup = "$AgentsFile.bak-intent-guard-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
Copy-Item $AgentsFile $backup -Force
$eol = if ($existing -match "`r`n") { "`r`n" } else { "`n" }
$new = $existing.TrimEnd() + $eol + $eol + (WithEol $snippetLf $eol)
[System.IO.File]::WriteAllText($AgentsFile, $new, $utf8)

Write-Host "[ok] appended resident block -> $AgentsFile"
Write-Host "[bk] backup: $backup"
Write-Host ""
Write-Host "Rollback:"
Write-Host "  Remove-Item -Recurse -Force '$skillDestDir'"
Write-Host "  Copy-Item '$backup' '$AgentsFile' -Force"
