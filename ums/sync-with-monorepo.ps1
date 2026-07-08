<#
.SYNOPSIS
    Syncs the UMS Memory Bank integration layer between this fork branch
    (ums-memory-bank, directory ums/) and the UMS monorepo — for Claude Code
    two-way, for other AI agents as a one-way deploy of the portable subset.

.DESCRIPTION
    Agent 'claude' (default) — two-way sync of the UMS-owned file set
    (everything in the monorepo's .claude/ EXCEPT the 14 vendored superpowers
    skill directories):

      FromMonorepo (default):  <monorepo>/.claude/*  ->  <fork>/ums/.claude/*
                               <monorepo>/CLAUDE.md  ->  <fork>/ums/CLAUDE.md.sample
      ToMonorepo:              the reverse

    The monorepo is the LIVE deployment and the normal master copy; run the
    default direction after changing the layer in the monorepo.

    Other agents (codex, gemini, kilocode) — one-way DEPLOY into the monorepo
    (the Direction parameter is ignored). Deploys the PORTABLE subset from
    this fork's ums/ layer:
      * the skills content (shared/ contract + mb-* utilities) into the
        agent's skills directory, where the agent supports one,
      * the CLAUDE.md.sample preference block into the agent's instructions
        file, wrapped in UMS-MEMORY-BANK BEGIN/END markers (re-runs replace
        the marked block in place),
      * plus a note that the mechanical enforcement (PreToolUse write-guard,
        permission denies, skillOverrides) exists only in Claude Code — for
        these agents the rules apply as instructions text.
    Per-agent target paths live in the $AgentTargets table below — adjust
    there if a harness expects a different layout.

    Vendored superpowers skills are never synced by this script - they are
    produced in the monorepo by .claude/scripts/revendor-superpowers.ps1
    from this repo's skills/ tree.

    Run WITHOUT parameters in an interactive console to be prompted for each
    parameter with its default offered (Enter accepts the default). In a
    non-interactive context (redirected stdin, pwsh -NonInteractive) the
    defaults are used silently, so automation keeps working.
#>
#Requires -Version 7
[CmdletBinding()]
param(
    [ValidateSet('FromMonorepo', 'ToMonorepo')]
    [string]$Direction = 'FromMonorepo',
    [ValidateSet('claude', 'codex', 'gemini', 'kilocode')]
    [string]$Agent = 'claude',
    [string]$MonorepoRoot = 'D:\_datasys\ums',
    [string]$ForkUmsDir = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'

# Per-agent monorepo-side targets (relative to $MonorepoRoot).
#   SkillsDir    - where the agent discovers project-level skills (null = the
#                  agent has no skills mechanism; only the instructions block
#                  is deployed)
#   Instructions - the agent's instructions file that receives the preference
#                  block from CLAUDE.md.sample
$AgentTargets = @{
    claude   = @{ SkillsDir = '.claude\skills'; Instructions = 'CLAUDE.md' }
    codex    = @{ SkillsDir = '.agents\skills'; Instructions = 'AGENTS.md' }
    gemini   = @{ SkillsDir = $null;            Instructions = 'GEMINI.md' }
    kilocode = @{ SkillsDir = $null;            Instructions = '.kilocode\rules\ums-memory-bank.md' }
}

# ------------------------------------------------- interactive parameter setup
function Read-WithDefault([string]$Prompt, [string]$Default) {
    $answer = Read-Host "$Prompt [$Default]"
    if ([string]::IsNullOrWhiteSpace($answer)) { $Default } else { $answer.Trim() }
}

$isNonInteractive = [Console]::IsInputRedirected -or
    ([Environment]::GetCommandLineArgs() -contains '-NonInteractive')

if ($PSBoundParameters.Count -eq 0 -and -not $isNonInteractive) {
    Write-Host 'No parameters given - interactive setup (Enter = default):' -ForegroundColor Cyan

    $agentNames = @('claude', 'codex', 'gemini', 'kilocode')
    do {
        $agentAnswer = Read-WithDefault 'Target AI agent: 1 = claude (two-way sync), 2 = codex, 3 = gemini, 4 = kilocode (2-4 = deploy only)' '1'
        $valid = $agentAnswer -in @('1', '2', '3', '4') -or $agentAnswer -in $agentNames
        if (-not $valid) { Write-Host '  Enter 1-4 or an agent name.' -ForegroundColor Yellow }
    } until ($valid)
    $Agent = if ($agentAnswer -in $agentNames) { $agentAnswer } else { $agentNames[[int]$agentAnswer - 1] }

    if ($Agent -eq 'claude') {
        do {
            $dirAnswer = Read-WithDefault 'Direction: 1 = FromMonorepo (monorepo -> fork), 2 = ToMonorepo (fork -> monorepo)' '1'
            $valid = $dirAnswer -in @('1', '2', 'FromMonorepo', 'ToMonorepo')
            if (-not $valid) { Write-Host '  Enter 1, 2, FromMonorepo, or ToMonorepo.' -ForegroundColor Yellow }
        } until ($valid)
        $Direction = if ($dirAnswer -in @('2', 'ToMonorepo')) { 'ToMonorepo' } else { 'FromMonorepo' }
    }
    else {
        Write-Host "  Agent '$Agent' supports deploy only (fork -> monorepo); Direction is ignored." -ForegroundColor DarkGray
    }

    $attempts = 0
    do {
        $MonorepoRoot = Read-WithDefault 'Monorepo root' $MonorepoRoot
        $valid = Test-Path (Join-Path $MonorepoRoot '.claude')
        if (-not $valid) {
            Write-Host "  No .claude/ found under '$MonorepoRoot'." -ForegroundColor Yellow
            if ((++$attempts) -ge 3) { throw "Monorepo root not valid after 3 attempts." }
        }
    } until ($valid)

    $ForkUmsDir = Read-WithDefault 'Fork ums/ directory' $ForkUmsDir

    Write-Host "Agent=$Agent  Direction=$Direction  MonorepoRoot=$MonorepoRoot  ForkUmsDir=$ForkUmsDir" -ForegroundColor Cyan
}

# ------------------------------------------------------------ shared helpers
function Copy-Mirrored([string]$Src, [string]$Dst) {
    if (-not (Test-Path $Src)) { throw "Source item missing: $Src" }
    if (Test-Path -PathType Container $Src) {
        if (Test-Path $Dst) { Remove-Item -Recurse -Force $Dst }
        New-Item -ItemType Directory -Force (Split-Path $Dst) | Out-Null
        Copy-Item -Recurse $Src $Dst
    }
    else {
        New-Item -ItemType Directory -Force (Split-Path $Dst) | Out-Null
        Copy-Item -Force $Src $Dst
    }
}

# Insert or replace the UMS-MEMORY-BANK marked block in an instructions file.
function Set-MarkedBlock([string]$File, [string]$Content) {
    $begin = '<!-- UMS-MEMORY-BANK BEGIN (generated by ums/sync-with-monorepo.ps1 - edit ums/CLAUDE.md.sample instead) -->'
    $end   = '<!-- UMS-MEMORY-BANK END -->'
    $block = "$begin`n$($Content.TrimEnd("`n"))`n$end"
    if (Test-Path $File) {
        $raw = (Get-Content -Path $File -Raw) -replace "`r`n", "`n"
        $iBegin = $raw.IndexOf($begin)
        $iEnd   = $raw.IndexOf($end)
        if ($iBegin -ge 0 -and $iEnd -gt $iBegin) {
            $new = $raw.Substring(0, $iBegin) + $block + $raw.Substring($iEnd + $end.Length)
        }
        elseif ($iBegin -ge 0 -or $iEnd -ge 0) {
            throw "Corrupted UMS-MEMORY-BANK markers in $File - fix the file manually."
        }
        else {
            $new = $raw.TrimEnd("`n") + "`n`n" + $block + "`n"
        }
    }
    else {
        $new = $block + "`n"
    }
    New-Item -ItemType Directory -Force (Split-Path $File) | Out-Null
    Set-Content -Path $File -NoNewline -Value $new
}

$forkClaude = Join-Path $ForkUmsDir '.claude'
$target = $AgentTargets[$Agent]

# ------------------------------------------------------------------ claude ---
if ($Agent -eq 'claude') {
    $monoClaude = Join-Path $MonorepoRoot '.claude'
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

    foreach ($rel in $staticItems + $mbSkills) {
        Copy-Mirrored (Join-Path $srcClaude $rel) (Join-Path $dstClaude $rel)
        Write-Host "synced $rel"
    }

    # Root CLAUDE.md <-> ums/CLAUDE.md.sample
    $monoClaudeMd = Join-Path $MonorepoRoot 'CLAUDE.md'
    $forkSample   = Join-Path $ForkUmsDir 'CLAUDE.md.sample'
    if ($Direction -eq 'FromMonorepo') { Copy-Item -Force $monoClaudeMd $forkSample; Write-Host 'synced CLAUDE.md -> CLAUDE.md.sample' }
    else                               { Copy-Item -Force $forkSample $monoClaudeMd; Write-Host 'synced CLAUDE.md.sample -> CLAUDE.md' }

    Write-Host "Done (claude, $Direction)." -ForegroundColor Cyan
}
# ------------------------------------------------------- other agents: deploy
else {
    # Portable skills content -> agent's skills directory (when it has one).
    if ($target.SkillsDir) {
        $dstSkills = Join-Path $MonorepoRoot $target.SkillsDir
        $items = @('shared') + (Get-ChildItem -Path (Join-Path $forkClaude 'skills') -Directory -Filter 'mb-*' |
            ForEach-Object { $_.Name })
        foreach ($name in $items) {
            Copy-Mirrored (Join-Path $forkClaude "skills\$name") (Join-Path $dstSkills $name)
            Write-Host "deployed skills\$name -> $($target.SkillsDir)\$name"
        }
    }
    else {
        Write-Host "Agent '$Agent' has no skills directory - deploying instructions block only." -ForegroundColor DarkGray
    }

    # Preference block from CLAUDE.md.sample -> agent's instructions file.
    $content = (Get-Content -Path (Join-Path $ForkUmsDir 'CLAUDE.md.sample') -Raw) -replace "`r`n", "`n"
    if ($target.SkillsDir) {
        # Repoint skill-pack references to the agent's own skills location.
        $skillsFwd = $target.SkillsDir -replace '\\', '/'
        $content = $content -replace [regex]::Escape('.claude/skills/'), "$skillsFwd/"
    }
    $content += @"

> Pozn. pro tento nástroj: mechanická vynucení (PreToolUse write-guard,
> permission deny EnterWorktree/ExitWorktree, skillOverrides) existují jen
> v Claude Code — zde platí výše uvedená pravidla jako závazný text.
"@
    $instrFile = Join-Path $MonorepoRoot $target.Instructions
    Set-MarkedBlock $instrFile $content
    Write-Host "deployed preference block -> $($target.Instructions)"

    Write-Host "Done ($Agent, deploy). Note: this file set may be gitignored in the monorepo (local per-developer deploy)." -ForegroundColor Cyan
}
