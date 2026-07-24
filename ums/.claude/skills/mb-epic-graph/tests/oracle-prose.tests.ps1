. (Join-Path $PSScriptRoot '_assert.ps1')
$prose = Join-Path $PSScriptRoot 'fixtures\prose'

Write-Host 'Proposal mode: prose <-> header findings'
$r = Invoke-Graph @('-Source','Proposals','-ProposalPath',$prose,'-EpicKey','demo','-Check')
Assert-Match $r.Out 'PROSE BEZ ODKAZU' 'prose-only relates(pa->pc) -> PROSE BEZ ODKAZU'
Assert-Match $r.Out 'ODKAZ BEZ PROSE' 'unexplained relates(pd-pe) -> ODKAZ BEZ PROSE'
Assert-Match $r.Out 'TYP ODKAZU NESOUHLASÍ' 'prose blokuje vs header souvisí (pf/pg) -> TYP ODKAZU NESOUHLASÍ'
Assert-NotMatch $r.Out 'PROSE BEZ LINKU' 'no Jira wording'
Assert-Eq $r.Code 2 'PROSE BEZ ODKAZU is CHYBA -> exit 2'

Complete-Tests
