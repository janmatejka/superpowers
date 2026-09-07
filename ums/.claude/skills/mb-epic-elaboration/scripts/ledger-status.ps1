<#
.SYNOPSIS
Read-only status report over an epic evidence ledger (ledger.md) maintained by
the mb-epic-elaboration skill.

.DESCRIPTION
Parses the ledger's Markdown tables (Položky, Tikety, Okna, Dirty-set,
Rozjetí, Registr rozhodnutí) and its one fenced block (Ověřovací sada),
prints a Czech summary (item counts by state, per-ticket rollup cross-check,
open windows, unresolved dirty rows, the epic's declared autonomy level with
its per-ticket overrides, the declared verification set, the decision
registry) and suggests the next window per the window selection rule (dirty
first, then leverage). Writes nothing; never touches Jira or git.

The Markdown/fenced-block parsing itself lives in the shared
Get-UmsEpicLedger.ps1 (ums/.claude/skills/shared/scripts/), because this
script's ledger shape is consumed by more than this one skill.

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

# Cross-directory dot-source of the shared ledger parser. Unlike the
# optional-dependency loader idiom elsewhere in this layer (e.g.
# mb-epic-run/scripts/pool-provision.ps1), this dependency is NOT optional:
# the report cannot be produced without it, so a missing file is a clean
# fail-closed error naming the path, not a silent fallback.
$ledgerParserLoader = Join-Path $PSScriptRoot '..\..\shared\scripts\Get-UmsEpicLedger.ps1'
if (-not (Test-Path -LiteralPath $ledgerParserLoader -PathType Leaf)) {
    Write-Error "Shared ledger parser not found: $ledgerParserLoader"
    exit 1
}
. $ledgerParserLoader

$items   = Get-UmsLedgerSectionTable $lines 'Položky'
$tickets = Get-UmsLedgerSectionTable $lines 'Členové'
$memberHeading = 'Členové'
if (@($tickets).Count -eq 0) { $tickets = Get-UmsLedgerSectionTable $lines 'Tikety'; $memberHeading = 'Tikety' }
$windows = Get-UmsLedgerSectionTable $lines 'Okna'
$dirty   = Get-UmsLedgerSectionTable $lines 'Dirty-set'
$spawns  = Get-UmsLedgerSectionTable $lines 'Rozjetí'
$verificationSet  = Get-UmsLedgerVerificationSet -LedgerPath $LedgerFile
$decisionRegistry = Get-UmsLedgerDecisionRegistry -LedgerPath $LedgerFile

$items   = @($items   | Where-Object { $_.Count -ge 4 -and $_[0] -and $_[0] -notmatch '^<' })
$tickets = @($tickets | Where-Object { $_.Count -ge 2 -and $_[0] -and $_[0] -notmatch '^<' })
$windows = @($windows | Where-Object { $_.Count -ge 3 -and $_[0] -and $_[0] -notmatch '^<' })
$dirty   = @($dirty   | Where-Object { $_.Count -ge 3 -and $_[0] })
# Seven columns since the Autonomie column was inserted BEFORE the trailing
# Pasti column, so a spawn row must carry cells 0..5 to be one: the report
# reads the four it renders (0,1,2,3) and the autonomy override (5). A row
# with fewer cells is a pre-column leftover the positional read cannot place,
# and dropping it here is what keeps its old Pasti prose from being rendered
# as a slot or a verdict. A SIX-cell leftover still passes this filter and is
# caught loudly below, by the closed-vocabulary check on cell 5.
$spawns  = @($spawns  | Where-Object { $_.Count -ge 6 -and $_[0] -and $_[0] -notmatch '^<' })

$issuesFound = @()   # inconsistency messages

# --- autonomy level ----------------------------------------------------------
# Read LOCALLY rather than in the shared Get-UmsEpicLedger.ps1: the header
# bullet is the same shape as the '- **Epic:**' line this script already reads
# for itself (and epic-gate.ps1 reads for itself), and the per-ticket override
# needs no new parser at all — it is cell 5 of the Rozjetí table the shared
# positional reader already returns. The shared file carries what MORE THAN
# ONE skill consumes; this has one consumer today.
# The vocabulary is closed (contract, "Escalation & Autonomy"); the default
# when the epic declares nothing is the middle level.
$autonomyLevels  = @('dohled', 'sdílená', 'delegovaná')
$autonomyDefault = 'sdílená'
$autonomyDeclared = ''
foreach ($ln in $lines) {
    if ($ln -match '^\s*-\s+\*\*Autonomie:\*\*\s*(.*)$') {
        # The value is what stands before the first spaced em dash; the rest of
        # the bullet is the template's own explanatory sentence.
        $autonomyDeclared = (($Matches[1] -split '\s+—\s+', 2)[0]).Trim()
        break
    }
}
if ($autonomyDeclared -match '^<') { $autonomyDeclared = '' }   # unfilled template placeholder
if ($autonomyDeclared -and $autonomyLevels -notcontains $autonomyDeclared) {
    $issuesFound += "Epik deklaruje neznámou úroveň autonomie «$autonomyDeclared» — povolené jsou dohled, sdílená, delegovaná."
}
foreach ($s in $spawns) {
    # The Count guard is redundant while the row filter above stands at >= 6,
    # and is kept anyway: measured, a loosened filter otherwise turns this
    # reportable defect into an unhandled index error under strict mode.
    if ($s.Count -ge 6 -and $s[5] -and $s[5] -ne '—' -and $autonomyLevels -notcontains $s[5]) {
        $issuesFound += "Řádek rozjetí «$($s[0])» má ve sloupci Autonomie neznámou hodnotu «$($s[5])» — povolené jsou dohled, sdílená, delegovaná, nebo — (bez přepsání)."
    }
}

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

# --- spawn rows -----------------------------------------------------------
foreach ($s in $spawns) {
    if (-not $ticketStates.ContainsKey($s[0])) {
        $issuesFound += "Řádek rozjetí pro «$($s[0])» nemá odpovídajícího člena v tabulce $memberHeading."
    }
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
Write-Output '## Autonomie'
if ($autonomyDeclared) {
    Write-Output "- deklarováno epikem: $autonomyDeclared"
} else {
    Write-Output "- nedeklarováno → platí výchozí: $autonomyDefault"
}
Write-Output ''
Write-Output "## Rozjetí ($($spawns.Count))"
if ($spawns.Count -eq 0) { Write-Output '- žádné' }
foreach ($s in $spawns) {
    # Positional, and the two indices moved together when the Autonomie column
    # was inserted before Pasti: the override is cell 5, the trap sentence 6.
    $auto = if ($s.Count -ge 6 -and $s[5] -and $s[5] -ne '—') { " — autonomie: $($s[5])" } else { '' }
    $trap = if ($s.Count -ge 7 -and $s[6]) { " — pasti: $($s[6])" } else { '' }
    Write-Output ("- {0} ({1}): {2}, slot {3}{4}{5}" -f $s[0], $s[1], $s[3], $s[2], $auto, $trap)
}
Write-Output ''
Write-Output "## Ověřovací sada ($($verificationSet.Count))"
if ($verificationSet.Count -eq 0) { Write-Output '- žádná (sada není deklarována)' }
foreach ($cmd in $verificationSet) { Write-Output "- $cmd" }
Write-Output ''
Write-Output "## Registr rozhodnutí ($($decisionRegistry.Count))"
if ($decisionRegistry.Count -eq 0) { Write-Output '- žádný' }
foreach ($d in $decisionRegistry) {
    $ack = if ([string]::IsNullOrWhiteSpace($d.AckSha)) { 'nepotvrzeno' } else { $d.AckSha }
    Write-Output ("- {0} (vlastník {1}, předpokládá o {2}, {3}, {4}, potvrzeno: {5})" -f $d.Decision, $d.Owner, $d.AssumesAbout, $d.Kind, $d.State, $ack)
}
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
