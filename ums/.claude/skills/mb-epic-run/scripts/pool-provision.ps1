#Requires -Version 7
<#
.SYNOPSIS
Provisions a new pool slot: a linked worktree, its pool-slot marker, and a
check that the shared pre-push guard covers it.

.DESCRIPTION
This is an OPERATOR tool, and the guard that makes that true lives in the
script rather than only in prose: the run refuses when an agent-session marker
is in the environment, unless the operator says so explicitly with -Operator.
The guard is here because it travels with the layer even to harnesses where
permissions.deny does not exist (permissions.deny carries the same rule for
Claude Code, in settings.json).

The hook check runs FROM INSIDE the new slot, because that is where the
question is: `git rev-parse --git-path hooks/pre-push` resolves per worktree
and honours core.hooksPath. A shared .git means one installation covers every
slot, so this installs only when the hook is MISSING or older than v2 —
reinstalling a current hook would be a write nobody asked for.

.OUTPUTS
English progress lines. Exit: 0 = OK, 1 = input/script failure,
4 = refused by the agent-session guard.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string] $Path,
    [string] $Base = '',
    [string] $RepoPath = '',
    [switch] $Operator,
    [switch] $NoFetch
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }

# Never name a function `Git`: PowerShell command discovery prefers a function
# over an application, case-insensitively, so `& git ...` inside it would
# recurse until the stack overflows.
function Invoke-RepoGit([string] $Dir, [string[]] $GitArgs) {
    $out = & git -C $Dir @GitArgs 2>&1
    return @{ Out = @($out); Code = $LASTEXITCODE }
}

# This is checked FIRST, before repo resolution, before the fetch, before
# anything that writes: proves the guard fires before any side effect, not
# merely that the exit code is 4. Reads exactly the variables the pre-push
# hook's own entry gate reads (MB_AGENT_SESSION == "1", AI_AGENT non-empty,
# CLAUDECODE == "1"), except the third clause is folded into a non-empty
# CLAUDECODE check: [ "$CLAUDECODE" = "1" ] is a strict subset of "CLAUDECODE
# is non-empty", so testing the exact value adds nothing an OR already gets
# from the broader check — "an agent session" still means the same set of
# processes as the hook's gate, just without a redundant clause.
$agentMarker = ($env:MB_AGENT_SESSION -eq '1') -or
               (-not [string]::IsNullOrEmpty($env:AI_AGENT)) -or
               (-not [string]::IsNullOrEmpty($env:CLAUDECODE))
if ($agentMarker -and -not $Operator) {
    Write-Output 'Refused: an agent-session marker is present in the environment.'
    Write-Output 'Provisioning a pool slot is an OPERATOR action (contract, Worktree Policy).'
    Write-Output 'If you are the operator and you mean it, re-run with -Operator.'
    exit 4
}

if ([string]::IsNullOrWhiteSpace($RepoPath)) {
    $top = & git rev-parse --show-toplevel 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($top)) {
        Write-Error 'Git repository not found. Memory Bank requires git.'; exit 1
    }
    $RepoPath = ([string] $top).Trim()
}
if (-not (Test-Path -LiteralPath $RepoPath -PathType Container)) {
    Write-Error "Repository path does not exist: $RepoPath"; exit 1
}
if (Test-Path -LiteralPath $Path) {
    $existing = @(Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue)
    if ($existing.Count -gt 0) {
        Write-Error "Target path exists and is not empty: $Path"; exit 1
    }
}

if ([string]::IsNullOrWhiteSpace($Base)) {
    # baseRef comes from the repository configuration, and it already carries
    # its remote prefix — never prefix it a second time.
    $loader = Join-Path $PSScriptRoot '..\..\shared\scripts\Get-UmsRepoConfig.ps1'
    if (Test-Path -LiteralPath $loader -PathType Leaf) {
        . $loader
        $cfg = Get-UmsRepoConfig -RepoRoot $RepoPath
        $Base = $cfg.baseRef
    }
    if ([string]::IsNullOrWhiteSpace($Base)) { $Base = 'origin/develop' }
}

if (-not $NoFetch) {
    Write-Output "Fetching $RepoPath ..."
    $f = Invoke-RepoGit $RepoPath @('fetch', 'origin')
    if ($f.Code -ne 0) { Write-Error "git fetch origin failed: $($f.Out -join "`n")"; exit 1 }
}

Write-Output "Creating a detached linked worktree at $Path from $Base ..."
$add = Invoke-RepoGit $RepoPath @('worktree', 'add', '--detach', $Path, $Base)
if ($add.Code -ne 0) { Write-Error "git worktree add failed: $($add.Out -join "`n")"; exit 1 }

$markerDir = Join-Path $Path '.superpowers'
New-Item -ItemType Directory -Force -Path $markerDir | Out-Null
$markerText = @(
    '# UMS pool slot marker.',
    '# Membership of the pool is derived, not configured: this file is what makes',
    '# this worktree a slot. Without it a worktree held for release maintenance —',
    '# clean tree, IDLE pin, no unpushed commits — would satisfy every freedom',
    '# condition and a spawn would switch it to a ticket branch.'
) -join "`n"
Set-Content -LiteralPath (Join-Path $markerDir 'pool-slot') -Value $markerText -Encoding utf8
Write-Output 'Marker .superpowers/pool-slot created.'

# --- shared hook check, asked FROM INSIDE the new slot -----------------------
$hookRes = Invoke-RepoGit $Path @('rev-parse', '--git-path', 'hooks/pre-push')
if ($hookRes.Code -ne 0) {
    Write-Output 'WARNING: could not resolve the pre-push hook path from inside the slot.'
}
else {
    $hookRaw = ([string] ($hookRes.Out | Select-Object -First 1)).Trim()
    # The path SHAPE differs by where you ask from: absolute from a slot,
    # relative from the primary worktree. Normalize before doing anything with it.
    $hookPath = if ([IO.Path]::IsPathRooted($hookRaw)) { $hookRaw } else { Join-Path $Path $hookRaw }
    $current = $false
    if (Test-Path -LiteralPath $hookPath -PathType Leaf) {
        $head5 = @(Get-Content -LiteralPath $hookPath -TotalCount 5)
        # -cmatch, case-sensitive: a broken hook whose error message merely
        # quotes its own path would otherwise pass as verified in any
        # repository living under a directory whose name contains "ums".
        $current = [bool](@($head5 | Where-Object { $_ -cmatch 'UMS pre-push guard \(Publication Contract\) v2' }).Count)
    }
    if ($current) {
        Write-Output "Shared pre-push guard is current (v2) at $hookPath — not reinstalling."
    }
    else {
        Write-Output "Shared pre-push guard is missing or older than v2 at $hookPath — installing."
        $installer = Join-Path $PSScriptRoot '..\..\..\hooks\install-git-hooks.ps1'
        if (-not (Test-Path -LiteralPath $installer -PathType Leaf)) {
            Write-Output "WARNING: installer not found at $installer; install the hook by hand."
        }
        else {
            & pwsh -NoProfile -File $installer -RepoRoot $Path
            if ($LASTEXITCODE -ne 0) {
                Write-Output "WARNING: install-git-hooks.ps1 exited $LASTEXITCODE — the publication guarantee is NOT confirmed."
            }
        }
    }
}

# --- size report -------------------------------------------------------------
$bytes = 0
$files = 0
Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue |
    ForEach-Object { $bytes += $_.Length; $files++ }
$gb = [math]::Round($bytes / 1GB, 2)
Write-Output "Slot provisioned: $files files, $gb GB (bytes: $bytes)."
Write-Output 'Next: run the mb-epic-run skill (status) to see the slot in the pool.'
exit 0
