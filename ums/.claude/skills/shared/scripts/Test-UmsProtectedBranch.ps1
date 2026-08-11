<#
.SYNOPSIS
    Tests a branch name against protected-branch patterns (contract:
    "Repository Configuration") and reports whether the answer could be
    computed at all.

.DESCRIPTION
    The layer already matches globs against branch names in two places -
    the POSIX `sh` pre-push hook and guard-git-push.mjs - and the contract
    requires both to give the SAME answer for the same configuration. This
    is the PowerShell side; it exists so no third hand-written copy of the
    matching logic appears inside a skill body.

    Measured difference this function exists to absorb: `-like` throws
    WildcardPatternException on a malformed pattern (`Maint/[0-9`), while
    the hook's `case` statement treats the same pattern as a literal and
    reports no match. Reporting only a bool would therefore either lie
    ("protected" from a catch returning $true) or hide a configuration
    defect. Matched answers the question; Evaluated says whether every
    pattern could be tested; BadPatterns names the ones that could not -
    those protect nothing in the hook either, silently.

    A found match short-circuits: it is proof of protection, so later
    patterns do not need testing and Evaluated stays $true.

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