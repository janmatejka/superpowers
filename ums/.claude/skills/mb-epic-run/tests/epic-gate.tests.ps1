#Requires -Version 7
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_assert.ps1')

# Test-UmsEpicGate lives under shared/scripts (a "shared-style helper", not an
# mb-epic-run-local script) because it is a pure function mirroring
# Test-UmsHandoffGate's return shape, and Get-UmsEpicLedger.ps1's own
# docstring already names "the epic fast-forward gate" as one of its shared
# consumers. This suite lives here (mb-epic-run/tests/), the owning skill for
# the `integrate` operation, exactly as ledger-evidence.tests.ps1 tests
# Get-UmsEpicLedger.ps1 from mb-epic-elaboration/tests/ even though that
# script also lives in shared/scripts.
. (Join-Path $PSScriptRoot '..\..\shared\scripts\Test-UmsEpicGate.ps1')

$fx = Join-Path $PSScriptRoot 'fixtures'
$Ticket = 'UMS-1234'
$Epic = 'UMS-1000'

# --- spawn-epic: Rozjetí row of the ticket belongs to a DIFFERENT epic -------

$r = Test-UmsEpicGate -LedgerPath (Join-Path $fx 'ledger-wrong-epic.md') -Ticket $Ticket -Epic $Epic
Assert-True (-not $r.Ok) 'cizí epic: brána zamítá'
Assert-Eq (@($r.Checks).Count) 2 'brána vrací právě dvě kontroly'
Assert-True ($r.Blocking -contains 'spawn-epic') 'cizí epic: blokuje kontrola spawn-epic'
Assert-True (-not ($r.Blocking -contains 'decision-ack')) 'cizí epic: decision-ack neblokuje (bez registru)'
$spawnCheck = @($r.Checks | Where-Object { $_.Name -eq 'spawn-epic' })[0]
Assert-Match $spawnCheck.Detail 'UMS-2000' 'cizí epic: Detail jmenuje epic, který ledger SKUTEČNĚ deklaruje'

# --- spawn-epic: ledger declares the right epic but has no Rozjetí row for the ticket

$r = Test-UmsEpicGate -LedgerPath (Join-Path $fx 'ledger-no-spawn-row.md') -Ticket $Ticket -Epic $Epic
Assert-True (-not $r.Ok) 'chybějící řádek Rozjetí: brána zamítá'
Assert-True ($r.Blocking -contains 'spawn-epic') 'chybějící řádek Rozjetí: blokuje spawn-epic'

# --- spawn-epic: ledger has no '- **Epic:**' header line at all -------------

$r = Test-UmsEpicGate -LedgerPath (Join-Path $fx 'ledger-no-epic-header.md') -Ticket $Ticket -Epic $Epic
Assert-True (-not $r.Ok) 'chybějící hlavička Epic: brána zamítá'
Assert-True ($r.Blocking -contains 'spawn-epic') 'chybějící hlavička Epic: blokuje spawn-epic'

# --- decision-ack: unconfirmed row naming this ticket ------------------------
# Load-bearing case: Stav says 'zavřeno' but Potvrzeno (SHA) is empty -- the
# check must key on AckSha, never on the Stav word (contract requirement).

$r = Test-UmsEpicGate -LedgerPath (Join-Path $fx 'ledger-unconfirmed.md') -Ticket $Ticket -Epic $Epic
Assert-True (-not $r.Ok) 'nepotvrzený řádek (Stav zavřeno, SHA prázdné): brána zamítá'
Assert-True ($r.Blocking -contains 'decision-ack') 'nepotvrzený řádek: blokuje decision-ack'
Assert-True (-not ($r.Blocking -contains 'spawn-epic')) 'nepotvrzený řádek: spawn-epic samo neblokuje'
$decisionCheck = @($r.Checks | Where-Object { $_.Name -eq 'decision-ack' })[0]
Assert-Match $decisionCheck.Detail 'Rozhodnutí X' 'nepotvrzený řádek: Detail jmenuje Rozhodnutí'
Assert-Match $decisionCheck.Detail 'UMS-9998' 'nepotvrzený řádek: Detail jmenuje Vlastníka (ne Předpokládá o)'

# --- decision-ack: multiple unconfirmed rows naming this ticket -------------

$r = Test-UmsEpicGate -LedgerPath (Join-Path $fx 'ledger-multi-unconfirmed.md') -Ticket $Ticket -Epic $Epic
Assert-True (-not $r.Ok) 'dva nepotvrzené řádky: brána zamítá'
$decisionCheck = @($r.Checks | Where-Object { $_.Name -eq 'decision-ack' })[0]
Assert-Match $decisionCheck.Detail 'Rozhodnutí Y1' 'dva nepotvrzené řádky: Detail jmenuje první'
Assert-Match $decisionCheck.Detail 'Rozhodnutí Y2' 'dva nepotvrzené řádky: Detail jmenuje druhý'

# --- both checks pass: confirmed row + own epic + spawn row ------------------
# Also proves cross-ticket isolation: ledger-ok.md carries an UNCONFIRMED row
# for a DIFFERENT ticket (UMS-9999) that must NOT block THIS ticket's check.

$r = Test-UmsEpicGate -LedgerPath (Join-Path $fx 'ledger-ok.md') -Ticket $Ticket -Epic $Epic
Assert-True $r.Ok 'vše v pořádku: brána projde'
Assert-Eq (@($r.Blocking).Count) 0 'vše v pořádku: nic neblokuje'
Assert-True (($r.Checks | Where-Object { $_.Name -eq 'spawn-epic' })[0].Passed) 'vše v pořádku: spawn-epic PASS'
Assert-True (($r.Checks | Where-Object { $_.Name -eq 'decision-ack' })[0].Passed) 'vše v pořádku: decision-ack PASS'

# --- decision-ack passes trivially: ledger has no '## Registr rozhodnutí' at all

$r = Test-UmsEpicGate -LedgerPath (Join-Path $fx 'ledger-no-registry.md') -Ticket $Ticket -Epic $Epic
Assert-True $r.Ok 'bez sekce Registr rozhodnutí: brána projde triviálně'
Assert-True (($r.Checks | Where-Object { $_.Name -eq 'decision-ack' })[0].Passed) 'bez sekce Registr rozhodnutí: decision-ack PASS'

# --- both checks fail together: Blocking names both -------------------------

$r = Test-UmsEpicGate -LedgerPath (Join-Path $fx 'ledger-both-fail.md') -Ticket $Ticket -Epic $Epic
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
$r = Test-UmsEpicGate -LedgerPath $missing -Ticket $Ticket -Epic $Epic
Assert-True $r.Ok 'chybějící ledger: brána projde triviálně, nepadá'
Assert-Eq (@($r.Blocking).Count) 0 'chybějící ledger: nic neblokuje'
Assert-Eq (@($r.Checks).Count) 2 'chybějící ledger: pořád vrací obě kontroly, jen obě PASS'
Assert-True (($r.Checks | Where-Object { $_.Name -eq 'spawn-epic' })[0].Passed) 'chybějící ledger: spawn-epic PASS'
Assert-True (($r.Checks | Where-Object { $_.Name -eq 'decision-ack' })[0].Passed) 'chybějící ledger: decision-ack PASS'

Complete-Tests
