<#
.SYNOPSIS
    Tests a branch name against protected-branch patterns (contract:
    "Repository Configuration") and reports whether the answer could be
    computed at all.

.DESCRIPTION
    The PowerShell side of the glob matching the POSIX `sh` pre-push hook
    and guard-git-push.mjs also perform; per contract, "Repository
    Configuration", all three must give the SAME answer for the same
    configuration, and an unevaluable pattern counts as NO match and is
    reported.

    Local to this function - the return contract, three fields because a
    bare bool cannot carry it: Matched answers the question; Evaluated says
    whether every pattern tested could be evaluated at all (PowerShell
    `-like` THROWS on `Maint/[0-9` where the hook's `case` reads it as a
    literal); BadPatterns names the ones that could not.

    A found match short-circuits the REST of the list, but patterns already
    caught as unevaluable stay in BadPatterns - so Matched $true together
    with Evaluated $false is a normal result, not a contradiction.

    Dot-source this file, then call Test-UmsProtectedBranch.
#>
Set-StrictMode -Version Latest

function Test-UmsProtectedBranch([string] $Name, [string[]] $Patterns) {
    $bad = [System.Collections.Generic.List[string]]::new()
    $matched = $false

    if (-not [string]::IsNullOrWhiteSpace($Name)) {
        foreach ($pattern in @($Patterns)) {
            if ([string]::IsNullOrWhiteSpace($pattern)) { continue }
            try {
                if ($Name -like $pattern) { $matched = $true; break }
            }
            catch {
                $bad.Add($pattern)
            }
        }
    }

    return [pscustomobject]@{
        Matched     = $matched
        Evaluated   = ($bad.Count -eq 0)
        BadPatterns = @($bad)
    }
}