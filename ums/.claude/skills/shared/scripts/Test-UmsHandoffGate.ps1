<#
.SYNOPSIS
    Read-only handoff gate: may this SHA be handed to a human (or to the epic
    operator) as an integration push?

.DESCRIPTION
    Three checks, in this order, always preceded by `git fetch origin` so the
    base is FRESH — a base ref remembered before someone else pushed is exactly
    the failure the gate exists for:

      1. `ancestor`  — `git merge-base --is-ancestor <base> <Sha>`: the SHA must
                       descend from the base as it stands AFTER the fetch.
      2. the context check — `git show <Sha>:<CTX_DIR>/context.md`, per contract
                       "`context.md` Schema & Writers". ACTIVE is `Target MB Pin`
                       TOGETHER WITH `Work item`; that is `active-pin`. Git exit
                       128 (the path does not exist at that SHA) is
                       `context-missing` and NEVER "IDLE"; any other nonzero exit
                       is `context-unreadable`. All three are blocking — an
                       unreadable answer fails CLOSED.
      3. `unpublished` — `git branch -r --contains <Sha>` empty means the commit
                       exists nowhere but this machine.

    `<CTX_DIR>` is not hardcoded and not a config key either: the contract
    ("Repository Configuration") DEFINES it as `<MB_ROOT>/memory-bank/`, which
    is how Get-UmsEffectiveBase resolves it too. What DOES come from
    configuration is the base: with -BaseRef omitted, `baseRef` is used.

    The check whose identity depends on its outcome is the context one: its
    Name is the FINDING name when it fails (`active-pin`, `context-missing`,
    `context-unreadable`) and `context-idle` when it passes, so that Blocking
    is exactly "the names of the failed checks" and each name says what is
    wrong without the caller re-deriving it.

    The function never mutates anything, never pushes and prints nothing —
    reporting (in Czech) belongs to the calling skill. `git fetch` is the only
    call that touches the network and it only updates remote-tracking refs.

    Dot-source this file, then call Test-UmsHandoffGate.
#>
#Requires -Version 7
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'Get-UmsRepoConfig.ps1')

function Test-UmsHandoffGate {
    param(
        [Parameter(Mandatory)] [string] $RepoRoot,
        [Parameter(Mandatory)] [string] $Sha,
        [string] $BaseRef
    )

    if (-not $BaseRef) { $BaseRef = (Get-UmsRepoConfig $RepoRoot).BaseRef }

    $checks = [System.Collections.Generic.List[object]]::new()
    $add = {
        param([string] $name, [bool] $passed, [string] $detail)
        $checks.Add([pscustomobject]@{ Name = $name; Passed = $passed; Detail = $detail })
    }

    # 1. Fresh base. The fetch comes first and its failure is not survivable
    # for this check: a stale remote-tracking ref answers "descendant" for
    # exactly the commit range the gate is meant to catch.
    $fetchOut = (& git -C $RepoRoot fetch origin --quiet 2>&1) -join ' '
    $fetchFailed = $LASTEXITCODE -ne 0
    if ($fetchFailed) {
        & $add 'ancestor' $false "git fetch origin selhal, bázi $BaseRef nelze považovat za čerstvou: $fetchOut"
    }
    else {
        $ancestorOut = (& git -C $RepoRoot merge-base --is-ancestor $BaseRef $Sha 2>&1) -join ' '
        if ($LASTEXITCODE -eq 0) {
            & $add 'ancestor' $true "$Sha je potomkem čerstvé báze $BaseRef"
        }
        else {
            & $add 'ancestor' $false "$Sha není potomkem čerstvé báze $BaseRef (báze se pohnula). $ancestorOut".Trim()
        }
    }

    # 2. context.md at that SHA. CTX_DIR per contract, "Repository
    # Configuration": <MB_ROOT>/memory-bank/.
    $ctxRel = 'memory-bank/context.md'
    $ctxOut = (& git -C $RepoRoot show "${Sha}:$ctxRel" 2>&1) -join "`n"
    $ctxExit = $LASTEXITCODE
    if ($ctxExit -eq 128) {
        & $add 'context-missing' $false "$ctxRel v commitu $Sha neexistuje — to je STOP, ne IDLE"
    }
    elseif ($ctxExit -ne 0) {
        & $add 'context-unreadable' $false "$ctxRel v commitu $Sha nelze přečíst (git skončil s kódem $ctxExit): $ctxOut"
    }
    elseif ($ctxOut -match '(?m)^\s*-\s*\*\*Target MB Pin:' -and $ctxOut -match '(?m)^\s*-\s*\*\*Work item:') {
        & $add 'active-pin' $false "$ctxRel v commitu $Sha je ACTIVE (Target MB Pin spolu s Work item) — práce není sklizená"
    }
    else {
        & $add 'context-idle' $true "$ctxRel v commitu $Sha je IDLE"
    }

    # 3. Published. `git branch -r --contains` lists the remote branches that
    # reach the commit; nothing listed means the commit is local-only.
    $remoteBranches = @(
        (& git -C $RepoRoot branch -r --contains $Sha 2>&1) |
            ForEach-Object { "$_".Trim() } | Where-Object { $_ -ne '' }
    )
    if ($LASTEXITCODE -ne 0) {
        & $add 'unpublished' $false "publikaci commitu $Sha nelze zjistit: $($remoteBranches -join ' ')"
    }
    elseif ($remoteBranches.Count -gt 0) {
        & $add 'unpublished' $true "commit $Sha je publikovaný ($($remoteBranches -join ', '))"
    }
    else {
        & $add 'unpublished' $false "commit $Sha není na žádné vzdálené větvi — není publikovaný"
    }

    $blocking = @($checks | Where-Object { -not $_.Passed } | ForEach-Object { $_.Name })
    return [pscustomobject]@{
        Ok       = ($blocking.Count -eq 0)
        Checks   = @($checks)
        Blocking = $blocking
    }
}
