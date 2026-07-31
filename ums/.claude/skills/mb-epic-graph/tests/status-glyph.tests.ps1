# Status-glyph tests (Jira mode): rozhodovací matice z
# ums/docs/design_epic_graph_test_jako_hotovo.md.
# Běhy záměrně BEZ -Check (oracle by do výstupu vložil vlastní ✅).
. (Join-Path $PSScriptRoot '_assert.ps1')
$status = Join-Path $PSScriptRoot 'fixtures\jira\status.json'
$props  = Join-Path $PSScriptRoot 'fixtures\status_proposals'

Write-Host 'Jira mode: fixture runs (malformed status object must not crash)'
$bare = Invoke-Graph @('-Source','Jira','-InputFile',$status,'-EpicKey','DEMO-0')
Assert-Eq $bare.Code 0 'run without -ProposalPath exits 0'
$full = Invoke-Graph @('-Source','Jira','-InputFile',$status,'-EpicKey','DEMO-0','-ProposalPath',$props)
Assert-Eq $full.Code 0 'run with -ProposalPath exits 0'
Assert-Match $bare.Out '\[DEMO-10\]' 'ticket with empty status object still lands in the table'

Complete-Tests
