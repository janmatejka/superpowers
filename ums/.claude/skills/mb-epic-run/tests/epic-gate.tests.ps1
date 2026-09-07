#Requires -Version 7
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_assert.ps1')

# Test-UmsEpicGate lives in THIS skill's own scripts/ (epic-gate.ps1), not
# shared/scripts/: it has exactly one consumer, mb-epic-run's `integrate`
# operation, unlike Get-UmsRepoConfig.ps1/Test-UmsHandoffGate.ps1/
# Get-UmsEpicLedger.ps1, each consumed by two or more skills. It still
# dot-sources the shared ledger parser internally (guarded, cross-directory).
. (Join-Path $PSScriptRoot '..\scripts\epic-gate.ps1')

$fx = Join-Path $PSScriptRoot 'fixtures'
$Ticket = 'UMS-1234'
$Epic = 'UMS-1000'

# --- spawn-epic: Rozjetí row of the ticket belongs to a DIFFERENT epic -------

$r = Test-UmsEpicGate -RepoRoot $PSScriptRoot -LedgerPath (Join-Path $fx 'ledger-wrong-epic.md') -Ticket $Ticket -Epic $Epic
Assert-True (-not $r.Ok) 'cizí epic: brána zamítá'
Assert-Eq (@($r.Checks).Count) 2 'brána vrací právě dvě kontroly'
Assert-True ($r.Blocking -contains 'spawn-epic') 'cizí epic: blokuje kontrola spawn-epic'
Assert-True (-not ($r.Blocking -contains 'decision-ack')) 'cizí epic: decision-ack neblokuje (bez registru)'
$spawnCheck = @($r.Checks | Where-Object { $_.Name -eq 'spawn-epic' })[0]
Assert-Match $spawnCheck.Detail 'UMS-2000' 'cizí epic: Detail jmenuje epic, který ledger SKUTEČNĚ deklaruje'

# --- spawn-epic: ledger declares the right epic but has no Rozjetí row for the ticket

$r = Test-UmsEpicGate -RepoRoot $PSScriptRoot -LedgerPath (Join-Path $fx 'ledger-no-spawn-row.md') -Ticket $Ticket -Epic $Epic
Assert-True (-not $r.Ok) 'chybějící řádek Rozjetí: brána zamítá'
Assert-True ($r.Blocking -contains 'spawn-epic') 'chybějící řádek Rozjetí: blokuje spawn-epic'

# --- spawn-epic: ledger has no '- **Epic:**' header line at all -------------

$r = Test-UmsEpicGate -RepoRoot $PSScriptRoot -LedgerPath (Join-Path $fx 'ledger-no-epic-header.md') -Ticket $Ticket -Epic $Epic
Assert-True (-not $r.Ok) 'chybějící hlavička Epic: brána zamítá'
Assert-True ($r.Blocking -contains 'spawn-epic') 'chybějící hlavička Epic: blokuje spawn-epic'

# --- decision-ack: unconfirmed row naming this ticket ------------------------
# Load-bearing case: Stav says 'zavřeno' but Potvrzeno (SHA) is empty -- the
# check must key on AckSha, never on the Stav word (contract requirement).

$r = Test-UmsEpicGate -RepoRoot $PSScriptRoot -LedgerPath (Join-Path $fx 'ledger-unconfirmed.md') -Ticket $Ticket -Epic $Epic
Assert-True (-not $r.Ok) 'nepotvrzený řádek (Stav zavřeno, SHA prázdné): brána zamítá'
Assert-True ($r.Blocking -contains 'decision-ack') 'nepotvrzený řádek: blokuje decision-ack'
Assert-True (-not ($r.Blocking -contains 'spawn-epic')) 'nepotvrzený řádek: spawn-epic samo neblokuje'
$decisionCheck = @($r.Checks | Where-Object { $_.Name -eq 'decision-ack' })[0]
Assert-Match $decisionCheck.Detail 'Rozhodnutí X' 'nepotvrzený řádek: Detail jmenuje Rozhodnutí'
Assert-Match $decisionCheck.Detail 'UMS-9998' 'nepotvrzený řádek: Detail jmenuje Vlastníka (ne Předpokládá o)'

# --- decision-ack: multiple unconfirmed rows naming this ticket -------------

$r = Test-UmsEpicGate -RepoRoot $PSScriptRoot -LedgerPath (Join-Path $fx 'ledger-multi-unconfirmed.md') -Ticket $Ticket -Epic $Epic
Assert-True (-not $r.Ok) 'dva nepotvrzené řádky: brána zamítá'
$decisionCheck = @($r.Checks | Where-Object { $_.Name -eq 'decision-ack' })[0]
Assert-Match $decisionCheck.Detail 'Rozhodnutí Y1' 'dva nepotvrzené řádky: Detail jmenuje první'
Assert-Match $decisionCheck.Detail 'Rozhodnutí Y2' 'dva nepotvrzené řádky: Detail jmenuje druhý'

# --- both checks pass: confirmed row + own epic + spawn row ------------------
# Also proves cross-ticket isolation: ledger-ok.md carries an UNCONFIRMED row
# for a DIFFERENT ticket (UMS-9999) that must NOT block THIS ticket's check.

$r = Test-UmsEpicGate -RepoRoot $PSScriptRoot -LedgerPath (Join-Path $fx 'ledger-ok.md') -Ticket $Ticket -Epic $Epic
Assert-True $r.Ok 'vše v pořádku: brána projde'
Assert-Eq (@($r.Blocking).Count) 0 'vše v pořádku: nic neblokuje'
Assert-True (($r.Checks | Where-Object { $_.Name -eq 'spawn-epic' })[0].Passed) 'vše v pořádku: spawn-epic PASS'
Assert-True (($r.Checks | Where-Object { $_.Name -eq 'decision-ack' })[0].Passed) 'vše v pořádku: decision-ack PASS'

# --- decision-ack passes trivially: ledger has no '## Registr rozhodnutí' at all

$r = Test-UmsEpicGate -RepoRoot $PSScriptRoot -LedgerPath (Join-Path $fx 'ledger-no-registry.md') -Ticket $Ticket -Epic $Epic
Assert-True $r.Ok 'bez sekce Registr rozhodnutí: brána projde triviálně'
Assert-True (($r.Checks | Where-Object { $_.Name -eq 'decision-ack' })[0].Passed) 'bez sekce Registr rozhodnutí: decision-ack PASS'

# --- both checks fail together: Blocking names both -------------------------

$r = Test-UmsEpicGate -RepoRoot $PSScriptRoot -LedgerPath (Join-Path $fx 'ledger-both-fail.md') -Ticket $Ticket -Epic $Epic
Assert-True (-not $r.Ok) 'obě kontroly padají: brána zamítá'
Assert-Eq (@($r.Blocking).Count) 2 'obě kontroly padají: Blocking jmenuje obě'
Assert-True ($r.Blocking -contains 'spawn-epic') 'obě kontroly padají: spawn-epic je mezi blokujícími'
Assert-True ($r.Blocking -contains 'decision-ack') 'obě kontroly padají: decision-ack je mezi blokujícími'

# --- both checks pass trivially: the ledger file does not exist at all ------
# Design's explicit choice: a ledger that does not exist is a PASS with a
# Detail saying why, never a block and never a throw -- the caller
# (mb-epic-run's `integrate`) has already STOPped earlier if no ledger
# matched the ticket at all.

$missing = Join-Path $fx 'does-not-exist.md'
$r = Test-UmsEpicGate -RepoRoot $PSScriptRoot -LedgerPath $missing -Ticket $Ticket -Epic $Epic
Assert-True $r.Ok 'chybějící ledger: brána projde triviálně, nepadá'
Assert-Eq (@($r.Blocking).Count) 0 'chybějící ledger: nic neblokuje'
Assert-Eq (@($r.Checks).Count) 2 'chybějící ledger: pořád vrací obě kontroly, jen obě PASS'
Assert-True (($r.Checks | Where-Object { $_.Name -eq 'spawn-epic' })[0].Passed) 'chybějící ledger: spawn-epic PASS'
Assert-True (($r.Checks | Where-Object { $_.Name -eq 'decision-ack' })[0].Passed) 'chybějící ledger: decision-ack PASS'

# --- -RepoRoot: a RELATIVE -LedgerPath resolves against the repo root -------
# THE defect this parameter closes. Test-Path resolves a relative path against
# the PROCESS CWD, so with the manager's pwsh standing anywhere but the repo
# root -- a subdirectory of the elaboration worktree, or an MB_ROOT that is not
# the repo root -- the very same relative path that names a real, BLOCKING
# ledger used to miss the file, and BOTH checks returned "ledger neexistuje -
# kontrola nemá vstup, prochází triviálně" with Ok=$true. A path slip became an
# approval. Here the CWD is deliberately somewhere else (the OS temp
# directory), -RepoRoot points at this tests directory, and the relative path
# must still find the blocking fixture.

$origCwd = (Get-Location).Path
try {
    Set-Location ([System.IO.Path]::GetTempPath())
    $r = Test-UmsEpicGate -RepoRoot $PSScriptRoot `
        -LedgerPath 'fixtures/ledger-unconfirmed.md' -Ticket $Ticket -Epic $Epic
}
finally { Set-Location $origCwd }
Assert-True (-not $r.Ok) 'relativní cesta z cizího CWD: brána zamítá (cesta se řeší proti -RepoRoot)'
Assert-True ($r.Blocking -contains 'decision-ack') 'relativní cesta z cizího CWD: blokuje decision-ack'
$relCheck = @($r.Checks | Where-Object { $_.Name -eq 'decision-ack' })[0]
Assert-NotMatch $relCheck.Detail 'neexistuje' 'relativní cesta z cizího CWD: ledger se NAŠEL, žádný triviální průchod'
Assert-Match $relCheck.Detail 'Rozhodnutí X' 'relativní cesta z cizího CWD: Detail jmenuje řádek ze SPRÁVNÉHO souboru'
$relSpawn = @($r.Checks | Where-Object { $_.Name -eq 'spawn-epic' })[0]
Assert-NotMatch $relSpawn.Detail 'neexistuje' 'relativní cesta z cizího CWD: ani spawn-epic neprochází triviálně'

# --- -RepoRoot: an ABSOLUTE -LedgerPath is used as given, CWD irrelevant -----
# Positive control for the branch above: the resolution must not corrupt an
# absolute path by prefixing -RepoRoot onto it.

try {
    Set-Location ([System.IO.Path]::GetTempPath())
    $r = Test-UmsEpicGate -RepoRoot ([System.IO.Path]::GetTempPath()) `
        -LedgerPath (Join-Path $fx 'ledger-ok.md') -Ticket $Ticket -Epic $Epic
}
finally { Set-Location $origCwd }
Assert-True $r.Ok 'absolutní cesta při nesouvisejícím -RepoRoot: brána projde (cesta se bere, jak je)'
Assert-True (($r.Checks | Where-Object { $_.Name -eq 'spawn-epic' })[0].Passed) 'absolutní cesta: spawn-epic PASS'

Complete-Tests
