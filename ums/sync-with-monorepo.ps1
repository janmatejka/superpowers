<#
.SYNOPSIS
    Syncs the UMS Memory Bank integration layer between this fork branch
    (ums-memory-bank, directory ums/) and a deployment target: the UMS
    monorepo (default) or the current user's profile. Claude Code in the
    monorepo is two-way; every other combination is a one-way deploy.

.DESCRIPTION
    Agent 'claude' + Scope 'Monorepo' (default) — two-way sync of the
    UMS-owned file set (everything in the monorepo's .claude/ EXCEPT the 14
    vendored superpowers skill directories):

      FromMonorepo (default):  <monorepo>/.claude/*  ->  <fork>/ums/.claude/*
                               <monorepo>/CLAUDE.md  ->  <fork>/ums/CLAUDE.md.sample
      ToMonorepo:              the reverse

    The monorepo is the LIVE deployment and the normal master copy; run the
    default direction after changing the layer in the monorepo.

    Every other combination — other agents (codex, gemini, kilocode) and/or
    Scope 'UserProfile' — is a one-way DEPLOY from this fork's ums/ layer
    (the Direction parameter is ignored):
      * the skills content (shared/ contract + mb-* utilities) into the
        agent's skills directory, where the agent supports one,
      * glue artifacts (hooks/, scripts/, and any future non-settings items
        of ums/.claude) into the agent's config directory — merged file-by-
        file, never wiping existing content; settings.json is deliberately
        NOT deployed (it is Claude Code's registration file and would clobber
        e.g. an existing .gemini/settings.json — hook registration is manual
        per harness),
      * the CLAUDE.md.sample preference block into the agent's instructions
        file, wrapped in UMS-MEMORY-BANK BEGIN/END markers (re-runs replace
        the marked block in place). UserProfile deploys prepend a scoping
        line so the rules apply only when working in the UMS monorepo.
    Per-agent target paths (per scope) live in the $AgentTargets table below
    — adjust there if a harness expects a different layout.

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
    [ValidateSet('Monorepo', 'UserProfile')]
    [string]$Scope = 'Monorepo',
    [string]$MonorepoRoot = 'D:\_datasys\ums',
    [string]$ForkUmsDir = $PSScriptRoot,
    # Test/advanced override of the user-profile root used by -Scope UserProfile.
    [string]$UserProfileRoot = $HOME
)

$ErrorActionPreference = 'Stop'

# Per-agent, per-scope targets (paths relative to the scope root — monorepo
# root or the user profile).
#   SkillsDir    - where the agent discovers skills (null = no skills
#                  mechanism; only glue + the instructions block is deployed)
#   ConfigDir    - agent config directory receiving glue artifacts (hooks/,
#                  scripts/, ...)
#   Instructions - instructions file that receives the preference block
$AgentTargets = @{
    claude = @{
        Monorepo    = @{ SkillsDir = '.claude\skills'; ConfigDir = '.claude'; Instructions = 'CLAUDE.md' }
        UserProfile = @{ SkillsDir = '.claude\skills'; ConfigDir = '.claude'; Instructions = '.claude\CLAUDE.md' }
    }
    codex = @{
        Monorepo    = @{ SkillsDir = '.agents\skills'; ConfigDir = '.codex'; Instructions = 'AGENTS.md' }
        UserProfile = @{ SkillsDir = '.agents\skills'; ConfigDir = '.codex'; Instructions = '.codex\AGENTS.md' }
    }
    gemini = @{
        Monorepo    = @{ SkillsDir = $null; ConfigDir = '.gemini'; Instructions = 'GEMINI.md' }
        UserProfile = @{ SkillsDir = $null; ConfigDir = '.gemini'; Instructions = '.gemini\GEMINI.md' }
    }
    kilocode = @{
        Monorepo    = @{ SkillsDir = $null; ConfigDir = '.kilocode'; Instructions = '.kilocode\rules\ums-memory-bank.md' }
        UserProfile = @{ SkillsDir = $null; ConfigDir = '.kilocode'; Instructions = '.kilocode\rules\ums-memory-bank.md' }
    }
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
        $agentAnswer = Read-WithDefault 'Target AI agent: 1 = claude, 2 = codex, 3 = gemini, 4 = kilocode' '1'
        $valid = $agentAnswer -in @('1', '2', '3', '4') -or $agentAnswer -in $agentNames
        if (-not $valid) { Write-Host '  Enter 1-4 or an agent name.' -ForegroundColor Yellow }
    } until ($valid)
    $Agent = if ($agentAnswer -in $agentNames) { $agentAnswer } else { $agentNames[[int]$agentAnswer - 1] }

    do {
        $scopeAnswer = Read-WithDefault "Scope: 1 = Monorepo ($MonorepoRoot), 2 = UserProfile ($UserProfileRoot)" '1'
        $valid = $scopeAnswer -in @('1', '2', 'Monorepo', 'UserProfile')
        if (-not $valid) { Write-Host '  Enter 1, 2, Monorepo, or UserProfile.' -ForegroundColor Yellow }
    } until ($valid)
    $Scope = if ($scopeAnswer -in @('2', 'UserProfile')) { 'UserProfile' } else { 'Monorepo' }

    if ($Agent -eq 'claude' -and $Scope -eq 'Monorepo') {
        do {
            $dirAnswer = Read-WithDefault 'Direction: 1 = FromMonorepo (monorepo -> fork), 2 = ToMonorepo (fork -> monorepo)' '1'
            $valid = $dirAnswer -in @('1', '2', 'FromMonorepo', 'ToMonorepo')
            if (-not $valid) { Write-Host '  Enter 1, 2, FromMonorepo, or ToMonorepo.' -ForegroundColor Yellow }
        } until ($valid)
        $Direction = if ($dirAnswer -in @('2', 'ToMonorepo')) { 'ToMonorepo' } else { 'FromMonorepo' }
    }
    else {
        Write-Host "  This combination is deploy-only (fork -> target); Direction is ignored." -ForegroundColor DarkGray
    }

    if ($Scope -eq 'Monorepo') {
        $attempts = 0
        do {
            $MonorepoRoot = Read-WithDefault 'Monorepo root' $MonorepoRoot
            $valid = Test-Path (Join-Path $MonorepoRoot '.claude')
            if (-not $valid) {
                Write-Host "  No .claude/ found under '$MonorepoRoot'." -ForegroundColor Yellow
                if ((++$attempts) -ge 3) { throw "Monorepo root not valid after 3 attempts." }
            }
        } until ($valid)
    }

    $ForkUmsDir = Read-WithDefault 'Fork ums/ directory' $ForkUmsDir

    Write-Host "Agent=$Agent  Scope=$Scope  Direction=$Direction  MonorepoRoot=$MonorepoRoot  ForkUmsDir=$ForkUmsDir" -ForegroundColor Cyan
}

# ------------------------------------------------------------ shared helpers
function Copy-Mirrored([string]$Src, [string]$Dst) {
    # Replaces the destination item entirely - use ONLY for directories this
    # layer owns outright (skill dirs).
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

function Copy-Merged([string]$Src, [string]$Dst) {
    # Merges into the destination: overwrites same-named files, never deletes
    # anything else - safe for shared config dirs (e.g. ~/.claude/hooks with
    # the user's own hooks).
    Get-ChildItem -Path $Src -Recurse -File | ForEach-Object {
        $rel = $_.FullName.Substring($Src.Length).TrimStart('\', '/')
        $dstFile = Join-Path $Dst $rel
        New-Item -ItemType Directory -Force (Split-Path $dstFile) | Out-Null
        Copy-Item -Force $_.FullName $dstFile
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
$target = $AgentTargets[$Agent][$Scope]

# --------------------------------------------- claude + monorepo: two-way sync
if ($Agent -eq 'claude' -and $Scope -eq 'Monorepo') {
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

    Write-Host "Done (claude, Monorepo, $Direction)." -ForegroundColor Cyan
}
# ------------------------------------- everything else: one-way deploy
else {
    $baseRoot = if ($Scope -eq 'UserProfile') { $UserProfileRoot } else { $MonorepoRoot }

    # 1. Portable skills content -> agent's skills directory (when it has one).
    if ($target.SkillsDir) {
        $dstSkills = Join-Path $baseRoot $target.SkillsDir
        $items = @('shared') + (Get-ChildItem -Path (Join-Path $forkClaude 'skills') -Directory -Filter 'mb-*' |
            ForEach-Object { $_.Name })
        foreach ($name in $items) {
            Copy-Mirrored (Join-Path $forkClaude "skills\$name") (Join-Path $dstSkills $name)
            Write-Host "deployed skills\$name -> $($target.SkillsDir)\$name"
        }
    }
    else {
        Write-Host "Agent '$Agent' has no skills directory - deploying glue + instructions block only." -ForegroundColor DarkGray
    }

    # 2. Glue artifacts (hooks/, scripts/, any future non-settings items of
    #    ums/.claude) -> agent's config dir. Merged, never wiping existing
    #    content. settings.json is intentionally skipped: it is Claude Code's
    #    registration file and would clobber the agent's own settings (e.g.
    #    .gemini/settings.json); register hooks manually per harness.
    $dstConfig = Join-Path $baseRoot $target.ConfigDir
    Get-ChildItem -Path $forkClaude -Directory |
        Where-Object { $_.Name -ne 'skills' } |
        ForEach-Object {
            Copy-Merged $_.FullName (Join-Path $dstConfig $_.Name)
            Write-Host "deployed $($_.Name)\ -> $($target.ConfigDir)\$($_.Name)\ (merged)"
        }
    if (-not ($Agent -eq 'claude')) {
        Write-Host "note: settings.json not deployed (Claude Code registration format) - wire hooks manually for '$Agent'." -ForegroundColor DarkGray
    }
    elseif ($Scope -eq 'UserProfile') {
        Write-Host "note: settings.json not deployed - merge hook registration into $($target.ConfigDir)\settings.json manually if wanted." -ForegroundColor DarkGray
    }

    # 3. Preference block from CLAUDE.md.sample -> agent's instructions file.
    $content = (Get-Content -Path (Join-Path $ForkUmsDir 'CLAUDE.md.sample') -Raw) -replace "`r`n", "`n"
    if ($target.SkillsDir) {
        # Repoint skill-pack references to the agent's own skills location.
        $skillsFwd = $target.SkillsDir -replace '\\', '/'
        $content = $content -replace [regex]::Escape('.claude/skills/'), "$skillsFwd/"
    }
    if ($Scope -eq 'UserProfile') {
        $preamble = "> **Rozsah platnosti:** následující pravidla platí POUZE při práci v UMS`n" +
                    "> monorepu (``$MonorepoRoot``). V jiných projektech je ignoruj.`n`n"
        $content = $preamble + $content
    }
    if ($Agent -ne 'claude') {
        $content += @"

> Pozn. pro tento nástroj: mechanická vynucení (PreToolUse write-guard,
> permission deny EnterWorktree/ExitWorktree, skillOverrides) existují jen
> v Claude Code — zde platí výše uvedená pravidla jako závazný text.
"@
    }
    $instrFile = Join-Path $baseRoot $target.Instructions
    Set-MarkedBlock $instrFile $content
    Write-Host "deployed preference block -> $($target.Instructions)"

    $scopeNote = if ($Scope -eq 'UserProfile') { "user profile $baseRoot" } else { 'monorepo (this file set may be gitignored there - local per-developer deploy)' }
    Write-Host "Done ($Agent, $Scope deploy -> $scopeNote)." -ForegroundColor Cyan
}
