<#
.SYNOPSIS
    Resolves the effective base of the current work item (contract:
    "Repository Configuration", the effective base).

.DESCRIPTION
    A work item may integrate somewhere other than the repository default -
    a maintenance branch of a release series carries the same role as
    develop for the work targeting it. The `- **Báze:**` line of
    context.md is therefore read first, and baseRef is the fallback.

    The line is read wherever it stands in the file, including under an
    IDLE marker: the harvest resets context.md, but the integration that
    follows still needs the push destination, so the line deliberately
    survives the reset.

    Branch strips the remote and the SINGLE following slash - never to the
    last slash. `origin/Branches/5.37` must yield `Branches/5.37`; `5.37`
    would make `git push origin HEAD:5.37` create a new remote branch
    instead of updating the base, and pre-push would not flag it because
    `Branches/*` does not match `5.37`.

    Dot-source this file, then call Get-UmsEffectiveBase.
#>
#Requires -Version 7
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'Get-UmsRepoConfig.ps1')

function Get-UmsEffectiveBase([string] $RepoRoot) {
    $ref = $null
    $source = 'config'

    $contextPath = Join-Path $RepoRoot 'memory-bank/context.md'
    if (Test-Path -LiteralPath $contextPath) {
        # @() so a single-line file still exposes .Count and indexing.
        foreach ($line in @(Get-Content -LiteralPath $contextPath)) {
            if ($line -match '^\s*-\s*\*\*Báze:\*\*\s*(\S+)\s*$') {
                $ref = $Matches[1]
                $source = 'context'
                break
            }
        }
    }

    if (-not $ref) {
        $ref = (Get-UmsRepoConfig $RepoRoot).BaseRef
    }

    return [pscustomobject]@{
        Ref    = $ref
        Branch = ($ref -replace '^[^/]+/', '')
        Source = $source
    }
}
