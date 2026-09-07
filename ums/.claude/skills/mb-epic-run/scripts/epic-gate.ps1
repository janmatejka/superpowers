<#
.SYNOPSIS
    Read-only epic gate: may this ticket's finished work be fast-forwarded
    into ITS OWN epic line?

.DESCRIPTION
    Two mechanical checks, in this order, consuming the epic evidence
    ledger's `## Rozjetí` and `## Registr rozhodnutí` sections via
    Get-UmsEpicLedger.ps1:

      1. `spawn-epic`   - what binds the fast-forward to the ticket's OWN
                         epic. Passes when the ledger at -LedgerPath
                         declares itself the ledger of -Epic (its
                         '- **Epic:**' header line names that key) AND
                         carries a '## Rozjetí' row whose 'Tiket' cell is
                         -Ticket. Fails when the header names a DIFFERENT
                         epic (the Detail says which one it actually
                         names), when the header is missing entirely, or
                         when this ledger has no spawn row for the ticket.
                         Without this check nothing stops the manager from
                         moving any existing `epic/*` branch.
      2. `decision-ack` - no unconfirmed decision names this ticket. Fails
                         when any '## Registr rozhodnutí' row has
                         AssumesAbout (column "Předpokládá o (tiket)")
                         equal to -Ticket AND an empty AckSha (column
                         "Potvrzeno (SHA)"). The Detail names each such
                         row's Decision and Owner ("Vlastník (tiket)" - the
                         ticket that MADE the decision, reported but never
                         matched against -Ticket). Confirmation is keyed on
                         AckSha being non-empty, NEVER on the Stav word -
                         the contract says so outright (section "The epic
                         line", the decision registry), and a row whose
                         Stav claims 'zavřeno' with an empty AckSha still
                         fails this check.

    BOTH CHECKS PASS TRIVIALLY WHEN THEIR INPUT IS ABSENT: a ledger file
    that does not exist, or a ledger with no '## Registr rozhodnutí'
    section, is a PASS with a Detail saying why - never a block and never
    a throw. This is the design's explicit choice: a check without input
    must not stop anything, and the caller (mb-epic-run, `integrate`) has
    already STOPped earlier if no ledger matched the ticket at all. Do NOT
    turn either absent-input case into a block or a throw - that would
    punish a ledger that legitimately has no decision registry yet, or a
    caller deriving a path that turns out not to exist.

    -LedgerPath IS RESOLVED AGAINST -RepoRoot when it is relative, exactly
    as Test-UmsHandoffGate takes a -RepoRoot: Test-Path resolves a relative
    path against the PROCESS CWD, so without this the manager's pwsh
    standing anywhere but the repository root turned a real, blocking
    ledger into "ledger neexistuje - prochazi trivialne" and let the
    fast-forward through. An absolute -LedgerPath is used as given. Every
    Detail names the RESOLVED path, so a remaining absence is legible.

    Ticket/epic-key comparisons are case-sensitive (-ceq/-cne), matching
    this layer's convention for values that come from an external key
    space rather than free text.

    Pure: reads files, prints nothing, mutates nothing, and touches
    neither git nor the network - unlike Test-UmsHandoffGate, which
    fetches. Returns Ok / Checks (Name/Passed/Detail) / Blocking in
    exactly Test-UmsHandoffGate's shape, so the manager's skill can report
    both gates' findings together.

    This gate lives here, in mb-epic-run's own scripts/ (not shared/), because
    it has exactly one consumer — mb-epic-run's `integrate` operation — unlike
    Get-UmsEpicLedger.ps1 and Test-UmsHandoffGate.ps1, each consumed by two or
    more skills. It still reaches across into shared/scripts/ for the ledger
    parser, guarded below the same way ledger-status.ps1
    (mb-epic-elaboration/scripts/) already does for the same dependency: this
    one is NOT optional, so a missing parser is a fail-closed throw naming the
    path, not a silent skip.

    Dot-source this file (it dot-sources Get-UmsEpicLedger.ps1 itself),
    then call Test-UmsEpicGate.
#>
#Requires -Version 7
Set-StrictMode -Version Latest

# Cross-directory dot-source of the shared ledger parser. Mandatory, not
# optional: this gate cannot function without it, so a missing file is a
# fail-closed error naming the path, not a silent fallback (same idiom, and
# now the same English error text, as
# mb-epic-elaboration/scripts/ledger-status.ps1 — layer scripts are
# developer tooling and speak English, contract "Language Contract").
$ledgerParserLoader = Join-Path $PSScriptRoot '..\..\shared\scripts\Get-UmsEpicLedger.ps1'
if (-not (Test-Path -LiteralPath $ledgerParserLoader -PathType Leaf)) {
    throw "Shared ledger parser not found: $ledgerParserLoader"
}
. $ledgerParserLoader

function Test-UmsEpicGate {
    param(
        [Parameter(Mandatory = $true)] [string] $RepoRoot,
        [Parameter(Mandatory = $true)] [string] $LedgerPath,
        [Parameter(Mandatory = $true)] [string] $Ticket,
        [Parameter(Mandatory = $true)] [string] $Epic
    )

    # Resolve BEFORE any Test-Path: a relative -LedgerPath must mean the
    # same file whatever the caller's working directory is. Without this,
    # a wrong CWD silently became "no input, trivial pass" for BOTH checks.
    $ledger = if ([System.IO.Path]::IsPathRooted($LedgerPath)) { $LedgerPath }
              else { Join-Path $RepoRoot $LedgerPath }

    $checks = [System.Collections.Generic.List[object]]::new()
    $add = {
        param([string] $name, [bool] $passed, [string] $detail)
        $checks.Add([pscustomobject]@{ Name = $name; Passed = $passed; Detail = $detail })
    }

    if (-not (Test-Path -LiteralPath $ledger -PathType Leaf)) {
        & $add 'spawn-epic' $true "ledger $ledger neexistuje - kontrola nemá vstup, prochází triviálně"
        & $add 'decision-ack' $true "ledger $ledger neexistuje - kontrola nemá vstup, prochází triviálně"
        return [pscustomobject]@{ Ok = $true; Checks = @($checks); Blocking = @() }
    }

    $lines = @(Get-Content -LiteralPath $ledger)

    # 1. spawn-epic. Header line format per ledger-template.md:
    # '- **Epic:** <EPIC-KEY> (https://...)'.
    $declaredEpic = ''
    foreach ($ln in $lines) {
        if ($ln -match '^\s*-\s*\*\*Epic:\*\*\s*(?<epic>\S+)') {
            $declaredEpic = $Matches['epic']
            break
        }
    }
    if ([string]::IsNullOrWhiteSpace($declaredEpic)) {
        & $add 'spawn-epic' $false "ledger $ledger nemá řádek '- **Epic:**' - nelze určit, kterému epiku patří"
    }
    elseif ($declaredEpic -cne $Epic) {
        & $add 'spawn-epic' $false "ledger $ledger je ledgerem epiku $declaredEpic, ne $Epic"
    }
    else {
        $rozjetiRows = Get-UmsLedgerSectionTable $lines 'Rozjetí'
        # Assign first, then filter THAT variable - never chain the section
        # reader's output directly into Where-Object in one pipeline
        # statement (Get-UmsEpicLedger.ps1's own note on
        # Get-UmsLedgerDecisionRegistry: doing so collapses the whole table
        # into a single unenumerated pipeline object).
        $spawnRows = @($rozjetiRows | Where-Object {
                $_.Count -ge 1 -and $_[0] -and $_[0] -notmatch '^<' -and $_[0] -ceq $Ticket
            })
        if ($spawnRows.Count -eq 0) {
            & $add 'spawn-epic' $false "ledger epiku $Epic nemá řádek Rozjetí pro tiket $Ticket"
        }
        else {
            & $add 'spawn-epic' $true "ledger epiku $Epic deklaruje sám sebe a má řádek Rozjetí pro tiket $Ticket"
        }
    }

    # 2. decision-ack. Assign first, THEN wrap in @() - wrapping the call
    # itself directly in @(Get-UmsLedgerDecisionRegistry ...) collapses
    # differently than a plain assignment followed by @() on the variable,
    # because the function's own 'return , @($result)' already emits a
    # single pipeline object; measured empirically (a zero-row ledger gave
    # Count 1, not 0, when wrapped at the call site).
    $decisionsRaw = Get-UmsLedgerDecisionRegistry -LedgerPath $ledger
    $decisions = @($decisionsRaw)
    $unconfirmed = @($decisions | Where-Object {
            $_.AssumesAbout -ceq $Ticket -and [string]::IsNullOrWhiteSpace($_.AckSha)
        })
    if ($unconfirmed.Count -eq 0) {
        if ($decisions.Count -eq 0) {
            & $add 'decision-ack' $true "ledger $ledger nemá (neprázdnou) sekci Registr rozhodnutí - kontrola nemá vstup, prochází triviálně"
        }
        else {
            & $add 'decision-ack' $true "žádný nepotvrzený řádek registru nejmenuje tiket $Ticket ve sloupci Předpokládá o (tiket)"
        }
    }
    else {
        $names = ($unconfirmed | ForEach-Object { "$($_.Decision) (vlastník $($_.Owner))" }) -join '; '
        & $add 'decision-ack' $false "nepotvrzené rozhodnutí jmenující $Ticket ve sloupci Předpokládá o (tiket): $names"
    }

    $blocking = @($checks | Where-Object { -not $_.Passed } | ForEach-Object { $_.Name })
    return [pscustomobject]@{
        Ok       = ($blocking.Count -eq 0)
        Checks   = @($checks)
        Blocking = $blocking
    }
}
