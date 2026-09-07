<#
.SYNOPSIS
    Positional Markdown-table and fenced-block readers for an epic evidence
    ledger (ledger.md, template: mb-epic-elaboration/ledger-template.md).

.DESCRIPTION
    Three read-only, side-effect-free parsers shared by ledger-status.ps1
    (mb-epic-elaboration) and by consumers in other skills — the epic
    fast-forward gate and the shared handoff gate — that need the same two
    trailing sections of the ledger without re-deriving their shape:

      - Get-UmsLedgerSectionTable: generic Markdown-table reader, moved here
        unchanged from ledger-status.ps1's former local Get-SectionTable.
        Finds the first '## <Heading>' line (prefix match, so 'Členové
        (proposaly)' matches heading 'Členové'), then the first pipe-table
        under it, and returns its data rows (header and separator row
        skipped) as string[][], columns read POSITIONALLY. The table ends at
        the first line that is not a table row (no leading '|'), or at the
        next '##' heading. Filtering placeholder rows (first cell starting
        with '<') and short rows is the caller's job, exactly as it was
        before this file existed.

      - Get-UmsLedgerVerificationSet: reads the '## Ověřovací sada' fenced
        code block (one shell command per line, per the CONTRACT's
        Publication Contract, section "Integration") and
        returns the commands, IN FILE ORDER, as a flat string array. Lines
        that are angle-bracket template placeholders (e.g.
        '<příkaz 1: build>') are dropped — the same rule the table reader's
        callers apply to a placeholder row's first cell. A ledger with no
        such section, or a section with no fenced block, returns an EMPTY
        array, never an error: the epic fast-forward gate treats "no
        verification set declared" as its own fail-closed condition, not as
        a parse failure here.

      - Get-UmsLedgerDecisionRegistry: reads the '## Registr rozhodnutí'
        table and returns one object per row with exactly the fields
        Decision, Owner, AssumesAbout, Kind, State, AckSha — read
        POSITIONALLY from the six columns in that order (Rozhodnutí,
        Vlastník (tiket), Předpokládá o (tiket), Druh, Stav, Potvrzeno
        (SHA)). AckSha is the load-bearing field: per the CONTRACT ("The
        epic line", the decision registry), an empty 'Potvrzeno (SHA)' cell
        means unconfirmed regardless of what Stav says, so a row with fewer
        than six cells still yields an object with an empty AckSha rather
        than throwing. The template's own example row
        (first cell starting with '<') is dropped, same rule as above.

    None of the three functions print anything, mutate anything, or touch
    git/Jira/network.

    Dot-source this file, then call Get-UmsLedgerSectionTable,
    Get-UmsLedgerVerificationSet or Get-UmsLedgerDecisionRegistry.
#>
#Requires -Version 7
Set-StrictMode -Version Latest

function Get-UmsLedgerSectionTable {
    # NOTE: deliberately NOT [Parameter(Mandatory = $true)] on $Lines. A
    # Mandatory [string[]] parameter implicitly rejects any array containing
    # an empty-string element — and a ledger's blank lines are exactly that
    # — so Mandatory here would throw "Cannot bind argument ... because it
    # is an empty string" on every real ledger. Plain positional params (as
    # the pre-extraction local Get-SectionTable used) carry no such check.
    param(
        [string[]] $Lines,
        [string] $Heading
    )
    $rows = @()
    $inSection = $false; $inTable = $false; $headerSkipped = $false
    foreach ($ln in $Lines) {
        if ($ln -match '^##\s+(.*)$') {
            if ($inSection) { break }
            $inSection = ($Matches[1].Trim() -like "$Heading*")
            continue
        }
        if (-not $inSection) { continue }
        if ($ln -match '^\s*\|') {
            if (-not $inTable) { $inTable = $true; continue }            # header row
            if (-not $headerSkipped) { $headerSkipped = $true; continue } # |---| row
            $cells = @(($ln.Trim() -replace '^\||\|$', '') -split '\|' | ForEach-Object { $_.Trim() })
            $rows += , $cells
        } elseif ($inTable) { break }
    }
    return , $rows
}

function Get-UmsLedgerVerificationSet {
    param(
        [Parameter(Mandatory = $true)] [string] $LedgerPath
    )
    if (-not (Test-Path -LiteralPath $LedgerPath -PathType Leaf)) {
        throw "Ledger not found: $LedgerPath"
    }
    $lines = Get-Content -LiteralPath $LedgerPath
    $heading = 'Ověřovací sada'
    $inSection = $false; $inFence = $false
    $commands = @()
    foreach ($ln in $lines) {
        if ($ln -match '^##\s+(.*)$') {
            if ($inSection) { break }
            $inSection = ($Matches[1].Trim() -like "$heading*")
            continue
        }
        if (-not $inSection) { continue }
        if ($ln -match '^\s*```') {
            if ($inFence) { break }   # closing fence: only the FIRST fenced block is read
            $inFence = $true
            continue
        }
        if (-not $inFence) { continue }
        $trimmed = $ln.Trim()
        if ($trimmed -eq '') { continue }
        if ($trimmed -match '^<') { continue }   # template placeholder, e.g. <příkaz 1: build>
        $commands += $trimmed
    }
    return , @($commands)
}

function Get-UmsLedgerDecisionRegistry {
    param(
        [Parameter(Mandatory = $true)] [string] $LedgerPath
    )
    if (-not (Test-Path -LiteralPath $LedgerPath -PathType Leaf)) {
        throw "Ledger not found: $LedgerPath"
    }
    $lines = Get-Content -LiteralPath $LedgerPath
    # Two statements, not one chained pipeline: Get-UmsLedgerSectionTable
    # returns via 'return , $rows' to emit its array-of-rows as a SINGLE
    # pipeline object (so a caller assigning it to a variable gets the true
    # array-of-arrays, not one row per pipeline tick). Piping the function
    # call's OUTPUT directly into Where-Object in the SAME pipeline
    # statement consumes exactly that one unenumerated object, so
    # Where-Object's $_ would be the WHOLE table, not one row at a time.
    # Assigning to a variable first, then piping THAT variable (as
    # ledger-status.ps1 already does for every other section), gives the
    # per-row enumeration this filter needs.
    $allRows = Get-UmsLedgerSectionTable $lines 'Registr rozhodnutí'
    $rows = @($allRows | Where-Object { $_.Count -ge 1 -and $_[0] -and $_[0] -notmatch '^<' })
    $result = @()
    foreach ($r in $rows) {
        $result += [pscustomobject]@{
            Decision     = if ($r.Count -ge 1) { $r[0] } else { '' }
            Owner        = if ($r.Count -ge 2) { $r[1] } else { '' }
            AssumesAbout = if ($r.Count -ge 3) { $r[2] } else { '' }
            Kind         = if ($r.Count -ge 4) { $r[3] } else { '' }
            State        = if ($r.Count -ge 5) { $r[4] } else { '' }
            AckSha       = if ($r.Count -ge 6) { $r[5] } else { '' }
        }
    }
    return , @($result)
}
