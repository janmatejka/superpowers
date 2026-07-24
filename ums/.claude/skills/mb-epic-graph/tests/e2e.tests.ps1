# End-to-end smoke test: Proposals mode over the `basic` fixture, with -Check -OutFile.
. (Join-Path $PSScriptRoot '_assert.ps1')
$basic = Join-Path $PSScriptRoot 'fixtures\basic'
$tmp = Join-Path ([IO.Path]::GetTempPath()) 'epic-e2e-graph.md'
$r = Invoke-Graph @('-Source','Proposals','-ProposalPath',$basic,'-EpicKey','demo','-Check','-Mermaid','-IndentedList','-OutFile',$tmp)
Assert-Eq $r.Code 0 'clean basic epic with -Check -> exit 0'
Assert-True (Test-Path $tmp) 'OutFile written'
$doc = Get-Content -LiteralPath $tmp -Raw
Assert-Match $doc '## Tabulka vln' 'has wave table section (default)'
Assert-Match $doc '## Mermaid' 'has mermaid section (-Mermaid)'
Assert-Match $doc '## Odsazený seznam' 'has indented list section (-IndentedList)'
Assert-Match $doc '## Kontrola konzistence' 'has consistency section'
Assert-Match $doc 'Vygenerováno z hlaviček proposalů' 'proposal-mode source phrase'
Assert-NotMatch $doc 'PROPOSAL BEZ TIKETU' 'no spurious PROPOSAL BEZ TIKETU in proposal mode'

# default output: wave table only, Mermaid and indented list are opt-in
$rd = Invoke-Graph @('-Source','Proposals','-ProposalPath',$basic,'-EpicKey','demo')
Assert-Match $rd.Out '## Tabulka vln \(do přehledového dokumentu\)' 'default output leads with the wave table (proposal-mode heading)'
Assert-Match $rd.Out 'Vlna 0 \(ihned\)' 'wave table has wave-0 header'
Assert-NotMatch $rd.Out '## Mermaid' 'mermaid absent by default'
Assert-NotMatch $rd.Out '## Odsazený seznam' 'indented list absent by default'
Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue
Complete-Tests
