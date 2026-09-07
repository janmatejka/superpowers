<#
.SYNOPSIS
    Read-only handoff gate: may this SHA be handed to a human (or to the epic
    operator) as an integration push?

.DESCRIPTION
    Four checks, in this fetch-first order:

      1. `ancestor`  - `git merge-base --is-ancestor <base> <Sha>` against the
                       base as it stands AFTER `git fetch origin`. The fetch is
                       a precondition of this check, not a check of its own in
                       the contract; when it fails, this script reports the
                       blocking name `fetch-failed` (Detail: the git error)
                       instead of `ancestor`, so that the remedy - reach
                       `origin` - is not read as "the base moved". That fourth
                       NAME is local to this script.
      2. the context check - `git show <Sha>:<CTX_DIR>/context.md`, judged per
                       contract, "`context.md` Schema & Writers". Findings:
                       `active-pin`; `context-missing` (git exit 128);
                       `context-unreadable` (any other nonzero exit). All three
                       block.
      3. `unpublished` - `git branch -r --contains <Sha>` came back empty.
      4. `verification-set` - compares -CitedCommands (what the handoff
                       artifact quotes) against -VerificationSet (what was
                       declared) as TEXT: equal strings in equal order, never
                       normalized (no whitespace trimming beyond what the
                       caller already did, no reordering) and never read
                       semantically - two callers are only measuring the same
                       thing if their commands are spelled identically. This
                       check is a PURE comparison: it does not resolve where
                       the declared set lives, does not read a ledger or a
                       plan, and does not know what an epic is. Resolving the
                       set's home (an epic's ledger for a ticket that belongs
                       to one, the work item's plan otherwise) is entirely the
                       CALLER's job. The check activates ONLY when
                       -VerificationSet is non-empty: with nothing declared
                       there is nothing to compare against, so this check is
                       skipped altogether rather than fabricating a pass or a
                       fail (and both parameters stay optional, so every
                       existing caller and every pre-existing assertion keeps
                       working unchanged). Once active, an empty
                       -CitedCommands is itself a blocking finding - a
                       declared set with nothing cited means the artifact
                       claims verification it does not evidence - and a
                       citation that differs from the declared set is a
                       blocking finding whose Detail names the first
                       differing line (1-based).

    `<CTX_DIR>` is resolved per its definition in the contract,
    `<MB_ROOT>/memory-bank/` - never from configuration and never from a path
    unrelated to MB_ROOT. The base, by contrast, does come from configuration:
    with -BaseRef omitted, `baseRef`.

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
        [string] $BaseRef,
        [string[]] $CitedCommands,
        [string[]] $VerificationSet
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
        & $add 'fetch-failed' $false "git fetch origin selhal, bázi $BaseRef nelze považovat za čerstvou: $fetchOut"
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

    # 4. Verification set. A PURE text comparison: this function does not
    # resolve where the declared set lives (epic ledger vs. work item plan is
    # the caller's decision), does not read a ledger, and does not learn what
    # an epic is. Activates ONLY when a set was declared - with $VerificationSet
    # empty there is nothing to compare against, so no finding is added at all
    # (never a fabricated pass or fail), which is also what keeps every
    # pre-existing caller and assertion working unchanged.
    # $null wrapped in @() is a ONE-element array holding $null, not an empty
    # array (measured: @($null).Count -eq 1) - so the null check must happen
    # BEFORE wrapping, never `@($VerificationSet).Count -gt 0` alone, or an
    # omitted -VerificationSet would wrongly activate this check. And the
    # null-vs-array branch itself must be wrapped from THE OUTSIDE
    # (`$x = @(if (...) {...} else {...})`), never only inside each branch -
    # an `if` whose taken branch is the literal `@()` yields zero output
    # objects for the whole statement, which unwraps to $null on assignment
    # exactly like the empty-pipeline case this layer's playbook documents
    # (measured: without the outer @(), `Test-P` above returns $null, not an
    # empty array, for both the omitted and the explicit-@() case).
    $declaredSet = @(if ($null -eq $VerificationSet) { @() } else { @($VerificationSet) })
    if ($declaredSet.Count -gt 0) {
        $citedSet = @(if ($null -eq $CitedCommands) { @() } else { @($CitedCommands) })
        if ($citedSet.Count -eq 0) {
            & $add 'verification-set' $false "artefakt předání necituje žádné ověřovací příkazy, ale ověřovací sada je deklarovaná ($($declaredSet.Count) příkazů)"
        }
        else {
            # Textual comparison, position by position, equal order required.
            # Never normalize whitespace and never reorder - the whole point
            # of the declared set is that two tickets measure the identical
            # thing, so a "helpful" normalization here would defeat it.
            $maxLen = [Math]::Max($declaredSet.Count, $citedSet.Count)
            $mismatchIndex = -1
            for ($i = 0; $i -lt $maxLen; $i++) {
                $expected = if ($i -lt $declaredSet.Count) { $declaredSet[$i] } else { $null }
                $actual = if ($i -lt $citedSet.Count) { $citedSet[$i] } else { $null }
                if ($expected -cne $actual) { $mismatchIndex = $i; break }
            }
            if ($mismatchIndex -ge 0) {
                $expectedLine = if ($mismatchIndex -lt $declaredSet.Count) { $declaredSet[$mismatchIndex] } else { '(chybí)' }
                $actualLine = if ($mismatchIndex -lt $citedSet.Count) { $citedSet[$mismatchIndex] } else { '(chybí)' }
                & $add 'verification-set' $false "citované příkazy se od deklarované ověřovací sady liší od řádku $($mismatchIndex + 1): citováno '$actualLine', deklarováno '$expectedLine'"
            }
            else {
                & $add 'verification-set' $true "citované příkazy odpovídají deklarované ověřovací sadě ($($declaredSet.Count) příkazů)"
            }
        }
    }

    $blocking = @($checks | Where-Object { -not $_.Passed } | ForEach-Object { $_.Name })
    return [pscustomobject]@{
        Ok       = ($blocking.Count -eq 0)
        Checks   = @($checks)
        Blocking = $blocking
    }
}
