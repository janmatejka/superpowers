<#
.SYNOPSIS
    Read-only handoff gate: may this SHA be handed to a human (or to the epic
    operator) as an integration push?

.DESCRIPTION
    Three checks, in this fetch-first order:

      1. `ancestor`  - `git merge-base --is-ancestor <base> <Sha>` against the
                       base as it stands AFTER `git fetch origin`.
      2. the context check - `git show <Sha>:<CTX_DIR>/context.md`, judged per
                       contract, "`context.md` Schema & Writers". Findings:
                       `active-pin`; `context-missing` (git exit 128);
                       `context-unreadable` (any other nonzero exit). All three
                       block.
      3. `unpublished` - `git branch -r --contains <Sha>` came back empty.

    `<CTX_DIR>` is derived per the contract's definition of it (see "Repository
    Configuration"), the same way Get-UmsEffectiveBase derives it. The base
    comes from configuration: with -BaseRef omitted, `baseRef`.

    The check whose identity depends on its outcome is the context one: its
    Name is the FINDING name when it fails and `context-idle` when it passes,
    so that Blocking is exactly "the names of the failed checks".

    The function never mutates anything, never pushes and prints nothing -
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
    # Configuration"; ACTIVE (and the mandated legacy alias `- **Proposal:**`)
    # per contract, "`context.md` Schema & Writers". Same regex shape as the
    # layer's other two readers of this field.
    $ctxRel = 'memory-bank/context.md'
    $ctxOut = (& git -C $RepoRoot show "${Sha}:$ctxRel" 2>&1) -join "`n"
    $ctxExit = $LASTEXITCODE
    if ($ctxExit -eq 128) {
        & $add 'context-missing' $false "$ctxRel v commitu $Sha neexistuje — to je STOP, ne IDLE"
    }
    elseif ($ctxExit -ne 0) {
        & $add 'context-unreadable' $false "$ctxRel v commitu $Sha nelze přečíst (git skončil s kódem $ctxExit): $ctxOut"
    }
    elseif ($ctxOut -match '(?m)^\s*-\s*\*\*Target MB Pin:' -and
        $ctxOut -match '(?m)^\s*-\s+\*\*(?:Work item|Proposal):\*\*\s*(?<v>\S+)\s*$') {
        & $add 'active-pin' $false "$ctxRel v commitu $Sha je ACTIVE (Target MB Pin spolu s Work item/Proposal) — práce není sklizená"
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
