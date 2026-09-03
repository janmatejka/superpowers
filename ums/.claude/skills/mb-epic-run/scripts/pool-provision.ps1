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
English progress lines. Exit: 0 = OK (provisioned and the publication
guarantee is confirmed), 1 = input/script failure, 4 = refused by the
agent-session guard, 5 = the slot WAS provisioned (worktree and marker are in
place — never unwound) but the shared pre-push guard's presence could not be
confirmed: the hook path could not be resolved from inside the slot, the
installer script was not found, or install-git-hooks.ps1 itself exited
non-zero. A caller must not treat exit 5 as success — the postcondition this
script exists to establish (a marked v2 hook resolvable from inside the slot)
is exactly what is unconfirmed in that case.
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
# merely that the exit code is 4. Reads the same three variables the
# pre-push hook's own entry gate reads (MB_AGENT_SESSION, AI_AGENT,
# CLAUDECODE), but this guard is deliberately BROADER than that gate on the
# third one: the hook requires CLAUDECODE == "1" exactly, while this guard
# fires on ANY non-empty CLAUDECODE. [ "$CLAUDECODE" = "1" ] is a strict
# subset of "CLAUDECODE is non-empty", so a fourth clause testing the exact
# value would add nothing an OR already gets from the broader one — that is
# why it was dropped, not because the two checks are equivalent. Keeping the
# broader check is correct: over-caution is right for an operator guard,
# which must never UNDER-enforce, and a value the hook itself would not
# recognise as "1" still means something that set CLAUDECODE is running here.
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
# $guaranteeUnconfirmed tracks whether the postcondition this script exists to
# establish (a marked v2 hook resolvable from inside the slot) was actually
# reached. The worktree and the marker are NEVER unwound over this — the slot
# genuinely exists and the operator needs to see it — but a run that could not
# confirm the guarantee must not claim success (exit 0) either; see exit 5.
$guaranteeUnconfirmed = $false
$hookRes = Invoke-RepoGit $Path @('rev-parse', '--git-path', 'hooks/pre-push')
if ($hookRes.Code -ne 0) {
    Write-Output 'WARNING: could not resolve the pre-push hook path from inside the slot. The publication guarantee is NOT confirmed.'
    $guaranteeUnconfirmed = $true
}
else {
    $hookRaw = ([string] ($hookRes.Out | Select-Object -First 1)).Trim()
    # The path SHAPE differs by where you ask from: absolute from a slot,
    # relative from the primary worktree. Normalize before doing anything with it.
    $hookPath = if ([IO.Path]::IsPathRooted($hookRaw)) { $hookRaw } else { Join-Path $Path $hookRaw }
    $current = $false
    if (Test-Path -LiteralPath $hookPath -PathType Leaf) {
        $head5 = @(Get-Content -LiteralPath $hookPath -TotalCount 5)
        # -cmatch, case-sensitive: this reads the hook's STATIC file content
        # and never executes it, unlike install-git-hooks.ps1's own live-hook
        # proof (whose broken-hook/stderr-quoting risk is where this exact
        # phrasing was borrowed from, and does not apply here). The real
        # reason to stay case-sensitive: this is an identity check against the
        # EXACT marker string install-git-hooks.ps1 itself stamps, so a
        # hand-edited or differently-cased paraphrase in a hook's header is
        # never mistaken for that stamp.
        $current = [bool](@($head5 | Where-Object { $_ -cmatch 'UMS pre-push guard \(Publication Contract\) v2' }).Count)
    }
    if ($current) {
        Write-Output "Shared pre-push guard is current (v2) at $hookPath — not reinstalling."
    }
    else {
        Write-Output "Shared pre-push guard is missing or older than v2 at $hookPath — installing."
        $installer = Join-Path $PSScriptRoot '..\..\..\hooks\install-git-hooks.ps1'
        if (-not (Test-Path -LiteralPath $installer -PathType Leaf)) {
            Write-Output "WARNING: installer not found at $installer; install the hook by hand. The publication guarantee is NOT confirmed."
            $guaranteeUnconfirmed = $true
        }
        else {
            & pwsh -NoProfile -File $installer -RepoRoot $Path
            if ($LASTEXITCODE -ne 0) {
                Write-Output "WARNING: install-git-hooks.ps1 exited $LASTEXITCODE — the publication guarantee is NOT confirmed."
                $guaranteeUnconfirmed = $true
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

if ($guaranteeUnconfirmed) {
    # The worktree and the marker above are NOT unwound: the slot genuinely
    # exists and the operator needs to see it. What must not happen is
    # reporting exit 0 — this run never reached the postcondition (a marked v2
    # hook resolvable from inside the slot) that a successful run promises.
    Write-Output 'Slot provisioned, but the publication guarantee could NOT be confirmed (see WARNING above).'
    exit 5
}
Write-Output 'Next: run the mb-epic-run skill (status) to see the slot in the pool.'
exit 0
