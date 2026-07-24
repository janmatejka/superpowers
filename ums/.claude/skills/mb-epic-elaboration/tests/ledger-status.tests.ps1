. (Join-Path $PSScriptRoot '_assert.ps1')
$ledger = Join-Path $PSScriptRoot 'fixtures\ledger_proposals.md'

$r = Invoke-Ledger $ledger
Assert-Match $r.Out 'konferencni_bezplatne_obdobi' 'slug member listed'
Assert-Match $r.Out '2 celkem' 'two items parsed'
Assert-Match $r.Out 'monetizace_play' 'second member listed'
# monetizace_play owns only E-2 (otevřená) so it is not a false-hotov; konferencni owns E-1 (uzavřená) and is hotov -> clean.
Assert-Eq $r.Code 0 'proposal ledger parses clean (exit 0)'
Assert-NotMatch $r.Out 'Nekonzistence' 'no cross-check errors'
Assert-Match $r.Out '## Členové \(2\)' 'members parsed under Členové heading'

# Legacy Jira ledger (## Tikety only) must keep its heading byte-for-byte.
$legacy = Join-Path $PSScriptRoot 'fixtures\ledger_legacy_tikety.md'
$rl = Invoke-Ledger $legacy
Assert-Eq $rl.Code 0 'legacy ledger parses clean (exit 0)'
Assert-Match $rl.Out '## Tikety \(' 'legacy heading preserved'
Assert-NotMatch $rl.Out '## Členové' 'no new heading for legacy ledger'
Complete-Tests
