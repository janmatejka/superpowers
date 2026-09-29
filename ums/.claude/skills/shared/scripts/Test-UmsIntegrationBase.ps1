<#
.SYNOPSIS
    Says whether a branch may serve as the integration base of a work item,
    and of which kind.

.DESCRIPTION
    Two kinds of branch may be a base:

      protected   a branch matching Config.ProtectedBranches - the original
                  invariant (contract/repository-configuration.md, "Repository Configuration").
      epic-line   an UNPROTECTED branch matching Config.EpicBranchPattern
                  (built-in default `epic/*`, see Get-UmsRepoConfig): the
                  epic line `epic/<KEY>` is a legitimate integration base
                  that nobody protects (design 4.2). An empty pattern means
                  there is no epic line and nothing matches it.

    A protected branch WINS: a branch that is both protected and matches the
    epic pattern is 'protected'. Anything else is 'none' and Allowed is
    $false.

    Matching is PowerShell `-like`, via Test-UmsProtectedBranch for both
    lists so the two share one implementation and one failure mode: a
    pattern `-like` cannot evaluate (`epic/[`, `Maint/[0-9`) counts as NO
    match and is reported in BadPatterns, never thrown. BadPatterns collects
    the unevaluable patterns of BOTH lists that were tried.

    Config is the hashtable Get-UmsRepoConfig returns; only ProtectedBranches
    and EpicBranchPattern are read.

    Dot-source this file, then call Test-UmsIntegrationBase.
#>
#Requires -Version 7
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'Test-UmsProtectedBranch.ps1')

function Test-UmsIntegrationBase([string] $Branch, $Config) {
    $bad = [System.Collections.Generic.List[string]]::new()

    $prot = Test-UmsProtectedBranch $Branch @($Config.ProtectedBranches)
    foreach ($p in @($prot.BadPatterns)) { $bad.Add($p) }
    if ($prot.Matched) {
        return @{ Allowed = $true; Kind = 'protected'; BadPatterns = [string[]]@($bad) }
    }

    $epicPattern = [string]$Config.EpicBranchPattern
    if (-not [string]::IsNullOrWhiteSpace($epicPattern)) {
        $epic = Test-UmsProtectedBranch $Branch @($epicPattern)
        foreach ($p in @($epic.BadPatterns)) { $bad.Add($p) }
        if ($epic.Matched) {
            return @{ Allowed = $true; Kind = 'epic-line'; BadPatterns = [string[]]@($bad) }
        }
    }

    return @{ Allowed = $false; Kind = 'none'; BadPatterns = [string[]]@($bad) }
}
