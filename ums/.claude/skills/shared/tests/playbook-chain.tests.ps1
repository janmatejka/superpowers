#Requires -Version 7
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_assert.ps1')
. (Join-Path $PSScriptRoot 'new-playbook-fixture.ps1')
. (Join-Path $PSScriptRoot '..\scripts\Get-UmsPlaybookChain.ps1')
. (Join-Path $PSScriptRoot '..\scripts\Test-UmsPlaybookShape.ps1')

$repo = New-PlaybookFixtureRepo

Write-Host "== tree discovery"
$tree = Get-UmsMbTree $repo
$dirs = @($tree | ForEach-Object Dir)
foreach ($d in 'memory-bank', 'A/memory-bank', 'A/B/memory-bank', 'A/C/memory-bank', 'A/C/D/memory-bank', 'L/memory-bank', 'L/M/memory-bank', 'S1/memory-bank', 'S2/memory-bank') {
    Assert-True ($dirs -contains $d) "tree contains $d"
}
Assert-True (-not ($dirs -match 'DistOut')) 'git-ignored copy is not an MB'
Assert-True (-not ($dirs -match 'memory-bank/X/memory-bank')) 'nested memory-bank is ignored'
Assert-True ($null -eq ($tree | Where-Object Dir -eq 'A/C/memory-bank').Playbook) 'MB without playbook has null Playbook'

Write-Host "== chain of a leaf under an intermediate"
$c = Get-UmsPlaybookChain $repo 'A/B/memory-bank' -Out
Assert-Eq (@($c.Segments | ForEach-Object Mb) -join ',') 'memory-bank,A/memory-bank,A/B/memory-bank' 'root, A, B in order'
Assert-Eq $c.Segments[1].Part 'podstrom' 'ancestor gives its subtree part only'
Assert-Eq $c.Segments[2].Part 'celý soubor' 'target gives the whole file'
$outText = [IO.File]::ReadAllText($c.OutPath)
Assert-Match $outText 'A-SUB pravidlo' 'subtree rule of A is in the chain'
Assert-True (-not ($outText -match 'A-OWN pravidlo')) 'own-project rule of A is not in the chain'
Assert-Match $outText '<!-- úsek: A/memory-bank/playbook.md \(podstrom' 'segment header names its source'
Assert-Match $c.OutPath '[\\/]\.superpowers[\\/]playbook-chain[\\/]A_B\.md$' 'chain file path'

Write-Host "== playbook-less ancestor is skipped"
$c = Get-UmsPlaybookChain $repo 'A/C/D/memory-bank'
Assert-Eq (@($c.Segments | ForEach-Object Mb) -join ',') 'memory-bank,A/memory-bank,A/C/D/memory-bank' 'A/C skipped'

Write-Host "== legacy non-root ancestor gives nothing"
$c = Get-UmsPlaybookChain $repo 'L/M/memory-bank'
Assert-Eq (@($c.Segments | ForEach-Object Mb) -join ',') 'memory-bank,L/M/memory-bank' 'legacy L skipped'

Write-Host "== root chain"
$c = Get-UmsPlaybookChain $repo 'memory-bank/'
Assert-Eq $c.Segments.Count 1 'root chain is the root file'
Assert-Eq $c.Segments[0].Part 'celý soubor' 'root as target gives whole file'

Write-Host "== lowest common ancestor"
Assert-Eq (Get-UmsMbLowestCommonAncestor $tree @('A/B/memory-bank', 'A/C/D/memory-bank')) 'A/memory-bank' 'LCA of B and D is A'
Assert-Eq (Get-UmsMbLowestCommonAncestor $tree @('S1/memory-bank', 'S2/memory-bank')) 'memory-bank' 'LCA of siblings is root'
Assert-Eq (Get-UmsMbLowestCommonAncestor $tree @('A/C/D/memory-bank')) 'A/C/D/memory-bank' 'LCA of one MB is itself'
Assert-Eq (Get-UmsMbLowestCommonAncestor $tree @('A/C/D/memory-bank', 'A/C/memory-bank')) 'A/C/memory-bank' 'LCA may be an MB without playbook'

Write-Host "== tree check: chain over threshold"
$big = New-PlaybookFixtureRepo
Write-PlaybookFixtureFile $big 'memory-bank/playbook.md' ("# P`n`n## Pro celý podstrom`n`n" + ((1..5 | ForEach-Object { "### Když krok $_`n`n" + (New-PlaybookRules 37 "R$_") + "`n" }) -join "`n"))
Write-PlaybookFixtureFile $big 'A/memory-bank/playbook.md' ("# P`n`n## Pro celý podstrom`n`n" + ((1..3 | ForEach-Object { "### Když krok $_`n`n" + (New-PlaybookRules 38 "A$_") + "`n" }) -join "`n"))
git -C $big add -A; git -C $big commit -q -m big
$res = Test-UmsPlaybookTree $big
$b = $res | Where-Object Mb -eq 'A/B/memory-bank'
Assert-True ((Read-UmsPlaybook (Join-Path $big 'memory-bank/playbook.md')).LineCount -le 600) 'root file itself is within threshold'
Assert-True ($b.ChainLines -gt 900) 'chain of B is over 900'
$cw = @($b.Warn | Where-Object { $_.StartsWith('[práh-řetězec]') })
Assert-True ([bool]$cw.Count) 'chain over threshold warns'
Assert-Match ($cw -join ' ') 'konsoliduj' 'conforming chain gets the consolidation hint'
Assert-Eq $b.Hard.Count 0 'chain over threshold is never hard'
Write-PlaybookFixtureFile $big 'A/memory-bank/playbook.md' ("# P`n`n## Testy`n`n" + (New-PlaybookRules 200 'LEG') + "`n")
git -C $big add -A; git -C $big commit -q -m legacy
$res = Test-UmsPlaybookTree $big
$b = $res | Where-Object Mb -eq 'A/B/memory-bank'
Assert-True ($b.ChainLines -le 900) 'legacy non-root ancestor contributes nothing to the chain'
$a = $res | Where-Object Mb -eq 'A/memory-bank'
Assert-True ([bool](@($a.Warn | Where-Object { $_.StartsWith('[legacy]') }).Count)) 'legacy file warns'
Assert-Eq $a.Hard.Count 0 'legacy file is never hard'
$sub = Test-UmsPlaybookTree $big 'A'
Assert-True (-not (@($sub | ForEach-Object Mb) -contains 'S1/memory-bank')) 'Under limits the scope'

Remove-Item -Recurse -Force $repo, $big
Complete-Tests
