#Requires -Version 7
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_assert.ps1')

# This suite exercises the shared parser functions (Get-UmsEpicLedger.ps1)
# DIRECTLY, dot-sourced here, because the object shape they hand to Task 11
# (epic fast-forward gate) and Task 12 (shared handoff gate) cannot be
# proven by observing ledger-status.ps1's printed report alone — that is
# what the existing ledger-status.tests.ps1 (23 assertions, untouched
# regression baseline) already does via its Invoke-Ledger helper. A few
# report-level assertions are added at the end of this file to prove the
# report WIRES the parser in (decision: ledger-status.ps1 must also report
# the two new sections), but the bulk of this suite is function-level.
. (Join-Path $PSScriptRoot '..\..\shared\scripts\Get-UmsEpicLedger.ps1')

$fxVerification = Join-Path $PSScriptRoot 'fixtures\ledger_verification_set.md'
$fxRegistry     = Join-Path $PSScriptRoot 'fixtures\ledger_decision_registry.md'
$fxNoSections   = Join-Path $PSScriptRoot 'fixtures\ledger_rozjeti.md'   # carries neither new section

# --- Get-UmsLedgerVerificationSet --------------------------------------------

$vs = Get-UmsLedgerVerificationSet -LedgerPath $fxVerification
Assert-Eq (@($vs).Count) 2 'verification set: two real commands parsed (placeholder line dropped)'
Assert-Eq $vs[0] 'pwsh ./build.ps1' 'verification set: first command in FILE ORDER'
Assert-Eq $vs[1] 'pwsh ./test.ps1 -Tag smoke' 'verification set: second command in FILE ORDER'
Assert-True (-not (@($vs) | Where-Object { $_ -match '^<' })) 'verification set: no placeholder line survives'

$vsMissing = Get-UmsLedgerVerificationSet -LedgerPath $fxNoSections
Assert-Eq (@($vsMissing).Count) 0 'verification set: missing section yields an EMPTY array, not an error'
Assert-Eq $vsMissing.GetType().FullName 'System.Object[]' 'verification set: missing-section result is still an array'

# --- Get-UmsLedgerDecisionRegistry --------------------------------------------

$reg = Get-UmsLedgerDecisionRegistry -LedgerPath $fxRegistry
Assert-Eq (@($reg).Count) 3 'decision registry: three real rows parsed (template placeholder row dropped)'

$d1 = $reg[0]
Assert-Eq $d1.Decision 'D1 potvrzené chování' 'decision registry: row 1 Decision (column 1, positional)'
Assert-Eq $d1.Owner 'UMS-3402' 'decision registry: row 1 Owner (column 2, positional)'
Assert-Eq $d1.AssumesAbout 'UMS-3403' 'decision registry: row 1 Předpokládá o (column 3, positional)'
Assert-Eq $d1.Kind 'chování' 'decision registry: row 1 Druh (column 4, positional)'
Assert-Eq $d1.State 'zavřeno' 'decision registry: row 1 Stav (column 5, positional)'
Assert-Eq $d1.AckSha 'abc1234' 'decision registry: row 1 Potvrzeno (SHA) (column 6, positional) — confirmed'

# Row 2 is the load-bearing case named by the brief: an empty 'Potvrzeno
# (SHA)' cell means unconfirmed EVEN THOUGH Stav itself says 'zavřeno'. The
# consumer must key "unconfirmed" on AckSha, never on the Stav word.
$d2 = $reg[1]
Assert-Eq $d2.Decision 'D2 nepotvrzené i přes zavřeno' 'decision registry: row 2 Decision'
Assert-Eq $d2.State 'zavřeno' 'decision registry: row 2 Stav says zavřeno...'
Assert-True ([string]::IsNullOrWhiteSpace($d2.AckSha)) 'decision registry: ...yet AckSha is empty -> unconfirmed regardless of Stav'

# Row 3 is a malformed row with fewer than six cells (no Druh/Stav/SHA
# columns at all in the source line). It must still yield an object with
# an empty AckSha, not throw.
$d3 = $reg[2]
Assert-Eq $d3.Decision 'D3 krátký řádek bez Druhu/Stavu/SHA' 'decision registry: row 3 (short row) Decision still read'
Assert-Eq $d3.Owner 'UMS-3402' 'decision registry: row 3 Owner still read'
Assert-Eq $d3.AssumesAbout 'UMS-3405' 'decision registry: row 3 Předpokládá o still read'
Assert-Eq $d3.Kind '' 'decision registry: row 3 Druh missing -> empty, not throw'
Assert-Eq $d3.State '' 'decision registry: row 3 Stav missing -> empty, not throw'
Assert-Eq $d3.AckSha '' 'decision registry: row 3 AckSha missing -> empty, not throw'

# None of the parsed rows is the template's own example row (first cell
# starts with '<') -- proven by the count above (3, not 4) and reinforced
# here on the actual field.
Assert-True (-not (@($reg) | Where-Object { $_.Decision -match '^<' })) 'decision registry: template placeholder row is not counted'

$regMissing = Get-UmsLedgerDecisionRegistry -LedgerPath $fxNoSections
Assert-Eq (@($regMissing).Count) 0 'decision registry: missing section yields an EMPTY array, not an error'
Assert-Eq $regMissing.GetType().FullName 'System.Object[]' 'decision registry: missing-section result is still an array'

# --- LedgerPath itself missing: both functions fail loudly, not silently ----

$missingPath = Join-Path $PSScriptRoot 'fixtures\does-not-exist-ledger.md'
$threw = $false
try { Get-UmsLedgerVerificationSet -LedgerPath $missingPath | Out-Null } catch { $threw = $true; $exMsg = $_.Exception.Message }
Assert-True $threw 'verification set: a missing LedgerPath throws rather than returning something silently'
Assert-Match $exMsg ([regex]::Escape($missingPath)) 'verification set: the thrown message names the missing path'

$threw2 = $false
try { Get-UmsLedgerDecisionRegistry -LedgerPath $missingPath | Out-Null } catch { $threw2 = $true; $exMsg2 = $_.Exception.Message }
Assert-True $threw2 'decision registry: a missing LedgerPath throws rather than returning something silently'
Assert-Match $exMsg2 ([regex]::Escape($missingPath)) 'decision registry: the thrown message names the missing path'

# --- Get-UmsLedgerSectionTable: the moved reader keeps its old behaviour ----
# Regression proof that the extraction (ledger-status.ps1's former local
# Get-SectionTable -> shared Get-UmsLedgerSectionTable) preserved the
# positional call shape (Lines, Heading) and the "first pipe-less line ends
# the table" rule, against a fixture this suite does not otherwise touch.
$lines = Get-Content -LiteralPath $fxNoSections
$spawnRowsRaw = Get-UmsLedgerSectionTable $lines 'Rozjetí'
$spawnRows = @($spawnRowsRaw | Where-Object { $_.Count -ge 4 -and $_[0] -and $_[0] -notmatch '^<' })
Assert-Eq (@($spawnRows).Count) 2 'Get-UmsLedgerSectionTable: positional reading of Rozjetí unaffected by the move'
Assert-Eq $spawnRows[0][0] 'UMS-3488' 'Get-UmsLedgerSectionTable: first spawn row, column 1'
Assert-Eq $spawnRows[0][3] 'rozjeto' 'Get-UmsLedgerSectionTable: first spawn row, column 4 (positional, not name-matched)'

# --- ledger-status.ps1 wiring: the CLI report must SHOW the two sections ---
# (decision, not brief: "a status tool that silently ignores two sections of
# the document it reports on is half a tool"). These use the existing
# Invoke-Ledger helper (out-of-process) because what is being proven here is
# that the script wires the shared parser into its OWN report, not the
# parser's object shape (already proven above).
$rv = Invoke-Ledger $fxVerification
Assert-Eq $rv.Code 0 'ledger-status.ps1: a ledger with a real Ověřovací sada still parses clean (exit 0)'
Assert-Match $rv.Out '## Ověřovací sada \(2\)' 'ledger-status.ps1: reports the verification set section with its count'
Assert-Match $rv.Out 'pwsh ./build\.ps1' 'ledger-status.ps1: reports a verification-set command'
Assert-NotMatch $rv.Out '<příkaz 3' 'ledger-status.ps1: does not report the placeholder line'

$rr = Invoke-Ledger $fxRegistry
Assert-Eq $rr.Code 0 'ledger-status.ps1: a ledger with a real Registr rozhodnutí still parses clean (exit 0) -- this task adds no new gating'
Assert-Match $rr.Out '## Registr rozhodnutí \(3\)' 'ledger-status.ps1: reports the decision registry section with its count'
Assert-Match $rr.Out 'D2 nepotvrzené.*nepotvrzeno' 'ledger-status.ps1: reports the unconfirmed decision with the unconfirmed marker'
Assert-Match $rr.Out 'D1 potvrzené.*abc1234' 'ledger-status.ps1: reports the confirmed decision with its SHA'

Complete-Tests
