<#
.SYNOPSIS
    Lists the branches that may serve as the integration base of a work
    item: the protected branches that actually exist on origin.

.DESCRIPTION
    Offers only protected branches, per contract, "Repository
    Configuration" (the invariant that an integration branch is always a
    protected branch); choosing an unprotected one is a fail-closed STOP
    owned by the caller, together with the remedy.

    Local to this function: candidates are the intersection of that
    configuration with what really exists on origin, and the ordering
    encodes the recommendation - configured default first, then the branch
    the session stands on, then the rest alphabetically.

    Dot-source this file, then call Get-UmsBaseCandidates.
#>
#Requires -Version 7
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'Get-UmsRepoConfig.ps1')
. (Join-Path $PSScriptRoot 'Test-UmsProtectedBranch.ps1')

function Get-UmsBaseCandidates([string] $RepoRoot, [string] $CurrentBranch) {
    $cfg = Get-UmsRepoConfig $RepoRoot

    # lstrip=3 drops refs/remotes/origin, leaving the plain branch name -
    # the same shape pre-push matches after stripping refs/heads/.
    # %(refname:short) would keep the remote in every name (matching
    # nothing in protectedBranches) and emit a bare "origin" for the
    # origin/HEAD symref.
    $names = @(& git -C $RepoRoot for-each-ref --format='%(refname:lstrip=3)' refs/remotes/origin/ 2>$null) |
        Where-Object { $_ -and $_ -ne 'HEAD' }

    $defaultBranch = $cfg.BaseRef -replace '^[^/]+/', ''

    $candidates = foreach ($name in $names) {
        $test = Test-UmsProtectedBranch $name $cfg.ProtectedBranches
        if (-not $test.Matched) { continue }
        [pscustomobject]@{
            Ref       = "origin/$name"
            Branch    = $name
            IsDefault = ($name -eq $defaultBranch)
            IsCurrent = ($name -eq $CurrentBranch)
        }
    }

    return @($candidates | Sort-Object `
        @{ Expression = { -not $_.IsDefault } }, `
        @{ Expression = { -not $_.IsCurrent } }, `
        @{ Expression = { $_.Branch } })
}
