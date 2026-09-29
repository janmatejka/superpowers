<#
.SYNOPSIS
    Creates the epic line `epic/<KEY>` on origin from the delivery line, the
    first time a ticket of the epic is spawned (mb-epic-run `spawn`).

.DESCRIPTION
    The epic line is an UNPROTECTED integration base (design 4.2;
    Test-UmsIntegrationBase, Get-UmsBaseCandidates). Creating it is the ONE
    push `spawn` makes to a shared remote, and it is a creation only:

        git fetch origin
        exists origin/epic/<KEY>  -> Existed, nothing is pushed
        else                      -> git push origin <sha of DeliveryRef>:refs/heads/epic/<KEY>

    An existing line is NEVER moved: it is not compared with the delivery
    line and not fast-forwarded to it - it is the epic's own history and only
    the epic's integration pushes advance it. A failed fetch, an unresolvable
    DeliveryRef, a malformed key or a refused push is an exception, never a
    silent Created: the caller must not name a base that does not exist.

    The push is made WITHOUT --no-verify, so the clone's pre-push hook still
    judges it like any other push (a new unprotected branch passes it).

    Returns a hashtable: Branch ('epic/<KEY>'), Existed, Created, Sha (the
    tip of the line on origin, or the sha it was created at).

    Dot-source this file, then call New-UmsEpicLine. Developer tooling: it
    speaks English (contract "Language Contract").
#>
#Requires -Version 7
Set-StrictMode -Version Latest

$UmsEpicKeyPattern = '^[A-Z][A-Z0-9]*-\d+$'

function New-UmsEpicLine([string] $RepoRoot, [string] $EpicKey, [string] $DeliveryRef) {
    # A key becomes part of a ref name pushed to a shared remote: reject
    # anything outside the Jira-key shape before git sees it.
    if ($EpicKey -cnotmatch $UmsEpicKeyPattern) {
        throw "New-UmsEpicLine: epic key '$EpicKey' is not a Jira key (expected e.g. UMS-1234)."
    }
    if ([string]::IsNullOrWhiteSpace($DeliveryRef)) {
        throw 'New-UmsEpicLine: DeliveryRef is empty.'
    }

    # Native stderr must not turn into a terminating error of its own (a
    # caller running under $ErrorActionPreference = 'Stop' would otherwise die
    # on git's progress lines); success is decided by the exit code.
    $ErrorActionPreference = 'Continue'
    $branch = "epic/$EpicKey"

    $out = & git -C $RepoRoot fetch origin 2>&1
    if ($LASTEXITCODE -ne 0) { throw "New-UmsEpicLine: git fetch origin failed: $out" }

    $existing = & git -C $RepoRoot rev-parse --verify --quiet "refs/remotes/origin/$branch" 2>$null
    if ($LASTEXITCODE -eq 0 -and $existing) {
        return @{ Branch = $branch; Existed = $true; Created = $false; Sha = ([string]@($existing)[0]).Trim() }
    }

    $sha = & git -C $RepoRoot rev-parse --verify --quiet "$DeliveryRef^{commit}" 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $sha) {
        throw "New-UmsEpicLine: delivery line '$DeliveryRef' does not resolve to a commit."
    }
    $sha = ([string]@($sha)[0]).Trim()

    $out = & git -C $RepoRoot push origin "${sha}:refs/heads/$branch" 2>&1
    if ($LASTEXITCODE -ne 0) { throw "New-UmsEpicLine: creating origin/$branch failed: $out" }

    return @{ Branch = $branch; Existed = $false; Created = $true; Sha = $sha }
}
