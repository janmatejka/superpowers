. (Join-Path $PSScriptRoot '_assert.ps1')
$findings = Join-Path $PSScriptRoot 'fixtures\findings'
$cycle = Join-Path $PSScriptRoot 'fixtures\cycle'

Write-Host 'Proposal mode: structural findings'
$r = Invoke-Graph @('-Source','Proposals','-ProposalPath',$findings,'-EpicKey','demo','-Check')
Assert-Match $r.Out 'CHYBĚJÍCÍ CÍL' 'broken link -> CHYBĚJÍCÍ CÍL'
Assert-Match $r.Out 'EXTERNÍ CÍL' 'non-member existing target -> EXTERNÍ CÍL'
Assert-Match $r.Out 'ASYMETRICKÝ ODKAZ' 'one-sided declaration -> ASYMETRICKÝ ODKAZ'
Assert-Eq $r.Code 2 'CHYBA present -> exit 2'
Assert-NotMatch $r.Out 'ASYMETRICKÝ LINK' 'no Jira-mode wording ASYMETRICKÝ LINK'
Assert-NotMatch $r.Out 'EXTERNÍ TIKET' 'no Jira-mode wording EXTERNÍ TIKET'
Assert-NotMatch $r.Out '(?m)^\s{4}_?prehled\[' 'index file not a node'
Assert-NotMatch $r.Out 'PROPOSAL BEZ TIKETU' 'no Jira-flavored PROPOSAL BEZ TIKETU in proposal mode'

Write-Host 'Proposal mode: cycle'
$c = Invoke-Graph @('-Source','Proposals','-ProposalPath',$cycle,'-EpicKey','demo','-Check')
Assert-Match $c.Out 'CYKLUS' 'blocks cycle -> CYKLUS'
Assert-Eq $c.Code 2 'cycle -> exit 2'

Complete-Tests
