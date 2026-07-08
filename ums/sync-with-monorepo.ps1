<#
.SYNOPSIS
    Syncs the UMS Memory Bank integration layer between this fork branch
    (ums-memory-bank, directory ums/) and the live UMS monorepo.

.DESCRIPTION
    The UMS-owned file set (everything in the monorepo's .claude/ EXCEPT the
    14 vendored superpowers skill directories) is mirrored:

      FromMonorepo (default):  <monorepo>/.claude/*  ->  <fork>/ums/.claude/*
                               <monorepo>/CLAUDE.md  ->  <fork>/ums/CLAUDE.md.sample
      ToMonorepo:              the reverse

    The monorepo is the LIVE deployment and the normal master copy; run the
    default direction after changing the layer in the monorepo. Use
    -ToMonorepo only when the layer was intentionally developed here first.

    Vendored superpowers skills are never synced by this script - they are
    produced in the monorepo by .claude/scripts/revendor-superpowers.ps1
    from this repo's skills/ tree.
#>
#Requires -Version 7
[CmdletBinding()]
param(
    [ValidateSet('FromMonorepo', 'ToMonorepo')]
    [string]$Direction = 'FromMonorepo',
    [string]$MonorepoRoot = 'D:\_datasys\ums',
    [string]$ForkUmsDir = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'

$monoClaude = Join-Path $MonorepoRoot '.claude'
$forkClaude = Join-Path $ForkUmsDir '.claude'
if (-not (Test-Path $monoClaude)) { throw "Monorepo .claude not found at $monoClaude" }

# UMS-owned items relative to the .claude/ root. skills/mb-* is discovered
# dynamically on the source side so new mb-* skills are picked up.
$staticItems = @(
    'settings.json',
    'hooks\deny-superpowers-docs.mjs',
    'scripts\revendor-superpowers.ps1',
    'skills\shared'
)

if ($Direction -eq 'FromMonorepo') { $srcClaude = $monoClaude; $dstClaude = $forkClaude }
else                               { $srcClaude = $forkClaude; $dstClaude = $monoClaude }

$mbSkills = Get-ChildItem -Path (Join-Path $srcClaude 'skills') -Directory -Filter 'mb-*' |
    ForEach-Object { "skills\$($_.Name)" }
$items = $staticItems + $mbSkills

foreach ($rel in $items) {
    $src = Join-Path $srcClaude $rel
    $dst = Join-Path $dstClaude $rel
    if (-not (Test-Path $src)) { throw "Source item missing: $src" }
    if (Test-Path -PathType Container $src) {
        if (Test-Path $dst) { Remove-Item -Recurse -Force $dst }
        New-Item -ItemType Directory -Force (Split-Path $dst) | Out-Null
        Copy-Item -Recurse $src $dst
    }
    else {
        New-Item -ItemType Directory -Force (Split-Path $dst) | Out-Null
        Copy-Item -Force $src $dst
    }
    Write-Host "synced $rel"
}

# Root CLAUDE.md <-> ums/CLAUDE.md.sample
$monoClaudeMd = Join-Path $MonorepoRoot 'CLAUDE.md'
$forkSample   = Join-Path $ForkUmsDir 'CLAUDE.md.sample'
if ($Direction -eq 'FromMonorepo') { Copy-Item -Force $monoClaudeMd $forkSample; Write-Host 'synced CLAUDE.md -> CLAUDE.md.sample' }
else                               { Copy-Item -Force $forkSample $monoClaudeMd; Write-Host 'synced CLAUDE.md.sample -> CLAUDE.md' }

Write-Host "Done ($Direction)." -ForegroundColor Cyan
