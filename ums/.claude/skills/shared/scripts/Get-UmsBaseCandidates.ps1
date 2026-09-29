<#
.SYNOPSIS
    Lists the branches that may serve as the integration base of a work
    item: the branches on origin that Test-UmsIntegrationBase allows - the
    protected ones and, unless switched off, the epic line.

.DESCRIPTION
    Offers protected branches and the epic line `epic/<KEY>` (an UNPROTECTED
    integration base identified by epicBranchPattern, default `epic/*`),
    per contract, "Repository Configuration" and design 4.2. Choosing any
    other branch is a fail-closed STOP owned by the caller, together with the
    remedy. Test-UmsIntegrationBase decides what is allowed; this function
    only intersects that with what really exists on origin.

    Local to this function: candidates are the intersection of that
    configuration with what really exists on origin, and the ordering
    encodes the recommendation - configured default first, then the branch
    the session stands on, then the rest alphabetically. IsEpicLine is true
    for a candidate allowed ONLY as an epic line (a branch that is also
    protected is 'protected' and IsEpicLine is false), so the caller can
    name the base kind when it offers one.

    Dot-source this file, then call Get-UmsBaseCandidates.
#>
#Requires -Version 7
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'Get-UmsRepoConfig.ps1')
. (Join-Path $PSScriptRoot 'Test-UmsIntegrationBase.ps1')

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
        $test = Test-UmsIntegrationBase $name $cfg
        if (-not $test.Allowed) { continue }
        [pscustomobject]@{
            Ref        = "origin/$name"
            Branch     = $name
            IsDefault  = ($name -eq $defaultBranch)
            IsCurrent  = ($name -eq $CurrentBranch)
            IsEpicLine = ($test.Kind -eq 'epic-line')
        }
    }

    return @($candidates | Sort-Object `
        @{ Expression = { -not $_.IsDefault } }, `
        @{ Expression = { -not $_.IsCurrent } }, `
        @{ Expression = { $_.Branch } })
}
