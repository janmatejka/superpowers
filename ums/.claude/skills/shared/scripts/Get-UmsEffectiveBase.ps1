<#
.SYNOPSIS
    Resolves the effective base of the current work item (contract:
    "Repository Configuration", the effective base).

.DESCRIPTION
    Reads the `- **Báze:**` line of context.md, falling back to baseRef,
    per contract, "Repository Configuration" (the effective base) - which
    also owns the rule that Branch strips the remote and the SINGLE
    following slash.

    Local to this function: the line is matched in two stages. The LOOSE
    shape (`- **B[áa]ze:`) decides that a line was MEANT to be it; the
    strict value regex decides whether it can be read. A line matching only
    the loose shape - a trailing comment, an empty value, missing
    diacritics - is reported in Malformed instead of passing as "no line at
    all", because context.md is hand-edited and this is its only
    diacritic-bearing field. The fallback to baseRef still applies then;
    Malformed is the caller's cue to REPORT, nothing more.

    Dot-source this file, then call Get-UmsEffectiveBase.
#>
#Requires -Version 7
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'Get-UmsRepoConfig.ps1')

function Get-UmsEffectiveBase([string] $RepoRoot) {
    $ref = $null
    $source = 'config'
    $malformed = $null

    $contextPath = Join-Path $RepoRoot 'memory-bank/context.md'
    if (Test-Path -LiteralPath $contextPath) {
        # @() so a single-line file still exposes .Count and indexing.
        foreach ($line in @(Get-Content -LiteralPath $contextPath)) {
            # Loose shape first, so "not the line" and "the line, unreadable"
            # stop being the same answer. Diacritics optional here on purpose:
            # a mistyped `Baze:` must be reported, not ignored.
            if ($line -notmatch '^\s*-\s*\*\*B[áa]ze:') { continue }
            if ($line -match '^\s*-\s*\*\*Báze:\*\*\s*(\S+)\s*$') {
                $ref = $Matches[1]
                $source = 'context'
                break
            }
            # First offender only - naming one line is enough to send a human
            # to the file, and the scan continues in case a readable line
            # follows.
            if (-not $malformed) { $malformed = $line.Trim() }
        }
    }

    if (-not $ref) {
        $ref = (Get-UmsRepoConfig $RepoRoot).BaseRef
    }

    return [pscustomobject]@{
        Ref       = $ref
        Branch    = ($ref -replace '^[^/]+/', '')
        Source    = $source
        Malformed = $malformed
    }
}
