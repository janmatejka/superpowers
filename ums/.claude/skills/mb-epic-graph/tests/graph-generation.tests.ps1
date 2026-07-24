. (Join-Path $PSScriptRoot '_assert.ps1')
$basic = Join-Path $PSScriptRoot 'fixtures\basic'

Write-Host 'Proposal mode: clean epic graph'
$r = Invoke-Graph @('-Source','Proposals','-ProposalPath',$basic,'-EpicKey','demo','-Mermaid')
Assert-Eq $r.Code 0 'exit 0 without -Check'
Assert-Match $r.Out 'flowchart TD' 'renders mermaid flowchart'
Assert-Match $r.Out 'alfa --> beta' 'blocks edge alfa->beta'
Assert-Match $r.Out 'beta -\.- gama' 'relates edge beta-gama'
Assert-Match $r.Out 'alfa -\. vyčleněno \.-> gama' 'split edge alfa->gama'
Assert-Eq ([regex]::Matches($r.Out, '(?m)^\s{4}gama\[').Count) 1 'gama node declared once (design sibling merged)'

Write-Host 'Proposal mode: wave table (default view)'
$rw = Invoke-Graph @('-Source','Proposals','-ProposalPath',$basic,'-EpicKey','demo')
Assert-Match $rw.Out '## Tabulka vln' 'wave table is the default view'
Assert-Match $rw.Out '\*\*alfa\*\*' 'proposal-mode keys are bold, not linked'
Assert-NotMatch $rw.Out 'browse/alfa' 'no Jira browse links for slugs'
Assert-Match $rw.Out '←alfa' 'direct-blocker hint uses the slug'
Assert-Match $rw.Out '▶️' 'live next/ proposal without blockers -> ready glyph'

Write-Host 'Jira mode regression'
$snap = Join-Path $PSScriptRoot 'fixtures\jira\snap.json'
$j = Invoke-Graph @('-Source','Jira','-InputFile',$snap,'-EpicKey','DEMO-1','-Mermaid')
Assert-Eq $j.Code 0 'jira mode exit 0'
Assert-Match $j.Out 'DEMO2 --> DEMO3' 'jira blocks edge preserved'
Assert-Match $j.Out 'browse/DEMO-2' 'jira wave table links ticket keys'

Write-Host 'Jira mode: byte-for-byte report wording (no proposal-mode leakage)'
$jc = Invoke-Graph @('-Source','Jira','-InputFile',$snap,'-EpicKey','DEMO-1','-Check')
Assert-Match $jc.Out 'ASYMETRICKÝ LINK' 'jira asymmetry code unchanged'
Assert-Match $jc.Out 'link uvádí jen' 'jira asymmetry text noun unchanged'
Assert-Match $jc.Out 'snapshot:' 'jira generation note uses snapshot:'
Assert-Match $jc.Out 'tiketů:' 'jira generation note uses tiketů:'
Assert-Match $jc.Out 'Jira linky' 'jira consistency note wording unchanged'
Assert-Match $jc.Out 'LINK BEZ PROSE' 'jira link-without-prose code unchanged'

Write-Host 'Jira mode: prose after-window offset skips the key (byte-for-byte)'
# DEMO-4 desc: "DEMO-5 <29 filler chars> blokuje ..." — the classifying keyword
# "blokuje" sits inside the 40-char window measured from the END of the key, but
# beyond 40 chars from its START. The typed blocks finding only appears when the
# after-window offset correctly skips the mention text ($m.Index + $m.Length);
# with the buggy offset 0 the keyword is out of reach and the mention stays bare.
$aw = Join-Path $PSScriptRoot 'fixtures\jira\afterwindow.json'
$ja = Invoke-Graph @('-Source','Jira','-InputFile',$aw,'-EpicKey','DEMO-1','-Check')
Assert-Match $ja.Out 'DEMO-4 blokuje DEMO-5' 'after-window fallback yields typed blocks assertion (offset skips key)'

Write-Host 'Jira mode: prose-corpus attribution still runs (PROPOSAL BEZ TIKETU fires)'
# basic/* proposals have no "**Jira:** KEY" header and no digit-suffixed filename,
# so in Jira mode they stay unattributed and must still emit PROPOSAL BEZ TIKETU.
$jp = Invoke-Graph @('-Source','Jira','-InputFile',$snap,'-EpicKey','DEMO-1','-ProposalPath',$basic,'-Check')
Assert-Match $jp.Out 'PROPOSAL BEZ TIKETU' 'jira mode still emits PROPOSAL BEZ TIKETU for unattributed proposals'

Complete-Tests
