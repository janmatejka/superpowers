<#
.SYNOPSIS
Read-only status report over an epic evidence ledger (ledger.md) maintained by
the mb-epic-elaboration skill.

.DESCRIPTION
Parses the ledger's Markdown tables (Položky, Tikety, Okna, Dirty-set), prints
a Czech summary (item counts by state, per-ticket rollup cross-check, open
windows, unresolved dirty rows) and suggests the next window per the window
selection rule (dirty first, then leverage). Writes nothing; never touches
Jira or git.

.PARAMETER LedgerFile
Path to the ledger.md instantiated from ledger-template.md.

.OUTPUTS
Czech text report. Exit code: 0 = OK, 1 = script/input failure,
2 = ledger inconsistencies found (duplicate items, false 'hotov', …).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string] $LedgerFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
$script:ExitCode = 0

if (-not (Test-Path -LiteralPath $LedgerFile)) { Write-Error "Ledger not found: $LedgerFile"; exit 1 }
$lines = Get-Content -LiteralPath $LedgerFile

function Get-SectionTable([string[]] $allLines, [string] $heading) {
    # Returns rows (string[][]) of the first Markdown table after '## <heading>'.
    $rows = @()
    $inSection = $false; $inTable = $false; $headerSkipped = $false
    foreach ($ln in $allLines) {
        if ($ln -match '^##\s+(.*)$') {
            if ($inSection) { break }
            $inSection = ($Matches[1].Trim() -like "$heading*")
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

$items   = Get-SectionTable $lines 'Položky'
$tickets = Get-SectionTable $lines 'Členové'
$memberHeading = 'Členové'
if (@($tickets).Count -eq 0) { $tickets = Get-SectionTable $lines 'Tikety'; $memberHeading = 'Tikety' }
$windows = Get-SectionTable $lines 'Okna'
$dirty   = Get-SectionTable $lines 'Dirty-set'

$items   = @($items   | Where-Object { $_.Count -ge 4 -and $_[0] -and $_[0] -notmatch '^<' })
$tickets = @($tickets | Where-Object { $_.Count -ge 2 -and $_[0] -and $_[0] -notmatch '^<' })
$windows = @($windows | Where-Object { $_.Count -ge 3 -and $_[0] -and $_[0] -notmatch '^<' })
$dirty   = @($dirty   | Where-Object { $_.Count -ge 3 -and $_[0] })

$issuesFound = @()   # inconsistency messages

# --- duplicate item IDs (partition violation) --------------------------------
$dupIds = @($items | Group-Object { $_[0] } | Where-Object Count -gt 1)
foreach ($d in $dupIds) { $issuesFound += "Duplicitní položka «$($d.Name)» ($($d.Count)×) — porušení disjunktního rozkladu." }

# --- items by state / by owner ------------------------------------------------
$byState = $items | Group-Object { $_[3] } | Sort-Object Name
$unassigned = @($items | Where-Object { $_[2] -match '^(nepřiřazeno|nepřirazeno|\?|)$' })

# --- dirty rows ---------------------------------------------------------------
$dirtyOpen = @($dirty | Where-Object { $_.Count -lt 4 -or -not $_[3] })

# --- per-ticket cross-check ---------------------------------------------------
$ticketStates = @{}
foreach ($t in $tickets) { $ticketStates[$t[0]] = $t[1] }
$itemsByOwner = $items | Group-Object { $_[2] }
foreach ($g in $itemsByOwner) {
    $owner = $g.Name
    if ($owner -match '^(nepřiřazeno|nepřirazeno|mimo epic|\?|)$') { continue }
    if (-not $ticketStates.ContainsKey($owner)) {
        $issuesFound += "Vlastník «$owner» položek ($(@($g.Group).Count)) chybí v tabulce Tikety."
        continue
    }
    $open = @($g.Group | Where-Object { $_[3] -ne 'uzavřená' })
    $dirtyHere = @($dirtyOpen | Where-Object { $_[0] -eq $owner -or (@($g.Group | ForEach-Object { $_[0] }) -contains $_[0]) })
    if ($ticketStates[$owner] -eq 'hotov' -and ($open.Count -gt 0 -or $dirtyHere.Count -gt 0)) {
        $why = @(); if ($open.Count -gt 0) { $why += "otevřené položky: $(($open | ForEach-Object { $_[0] }) -join ', ')" }
        if ($dirtyHere.Count -gt 0) { $why += 'položky/tiket v dirty-setu' }
        $issuesFound += "Tiket $owner je «hotov», ale $($why -join '; ')."
    }
    if ($ticketStates[$owner] -ne 'hotov' -and $open.Count -eq 0 -and $dirtyHere.Count -eq 0 -and @($g.Group).Count -gt 0) {
        $issuesFound += "Tiket $owner má vše uzavřené a čisté — kandidát na stav «hotov» (nyní «$($ticketStates[$owner])»)."
    }
}

# --- windows ------------------------------------------------------------------
$openWindows = @($windows | Where-Object { $_[2] -ne 'uzavřeno' })
$activeWindows = @($windows | Where-Object { $_[2] -in @('agenda potvrzena', 'probíhá') })
if ($activeWindows.Count -gt 1) {
    $issuesFound += "Více než jedno rozpracované okno ($(($activeWindows | ForEach-Object { $_[0] }) -join ', ')) — okna se uzavírají po jednom."
}

# --- report -------------------------------------------------------------------
$epicLine = ($lines | Where-Object { $_ -match '^\s*-\s+\*\*Epic:\*\*' } | Select-Object -First 1)
Write-Output "# Stav evidence ledgeru"
if ($epicLine) { Write-Output $epicLine.Trim() }
Write-Output ''
Write-Output "## Položky ($($items.Count) celkem)"
foreach ($s in $byState) { Write-Output ("- {0}: {1}" -f $s.Name, $s.Count) }
if ($unassigned.Count -gt 0) {
    Write-Output ("- ⚠️ bez vlastníka: {0} ({1})" -f $unassigned.Count, (($unassigned | ForEach-Object { $_[0] }) -join ', '))
}
Write-Output ''
Write-Output "## $memberHeading ($($tickets.Count))"
foreach ($t in $tickets) {
    $cnt = @($items | Where-Object { $_[2] -eq $t[0] }).Count
    Write-Output ("- {0}: {1} (položek: {2})" -f $t[0], $t[1], $cnt)
}
Write-Output ''
Write-Output "## Okna"
if ($windows.Count -eq 0) { Write-Output '- žádná' }
foreach ($w in $windows) { Write-Output ("- {0}: {1} — {2}" -f $w[0], $w[2], $w[1]) }
Write-Output ''
Write-Output "## Dirty-set (nevyčištěné: $($dirtyOpen.Count))"
foreach ($d in $dirtyOpen) { Write-Output ("- {0} (okno {1}): {2}" -f $d[0], $d[1], $d[2]) }
Write-Output ''
if ($issuesFound.Count -gt 0) {
    Write-Output '## ❌ Nekonzistence ledgeru'
    foreach ($i in $issuesFound) { Write-Output "- $i" }
    Write-Output ''
    $script:ExitCode = 2
}
Write-Output '## Doporučení dalšího okna'
if ($dirtyOpen.Count -gt 0) {
    Write-Output '- Přednost mají špinavé položky (korektnostní brána — nekonzistence se nesmí hromadit):'
    foreach ($d in $dirtyOpen) { Write-Output ("  - {0} — {1}" -f $d[0], $d[2]) }
} elseif ($unassigned.Count -gt 0) {
    Write-Output ("- Nejdřív přiřadit vlastníky položkám bez vlastníka: {0}." -f (($unassigned | ForEach-Object { $_[0] }) -join ', '))
} else {
    Write-Output '- Dirty-set je prázdný → vyber čisté téma s největší pákou (leverage): rozhodnutí, které nejvíc tvaruje závislé tikety na aktuální úrovni rozpracování — typicky kontrakty základů. Páka je důvod, ne mechanické pořadí základ→konzument.'
}
exit $script:ExitCode
