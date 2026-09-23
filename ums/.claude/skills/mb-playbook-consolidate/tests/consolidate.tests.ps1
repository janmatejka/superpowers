#Requires -Version 7
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_assert.ps1')
. (Join-Path $PSScriptRoot '..\..\shared\tests\new-playbook-fixture.ps1')
. (Join-Path $PSScriptRoot '..\..\shared\scripts\Test-UmsPlaybookShape.ps1')
$script = Join-Path $PSScriptRoot '..\scripts\consolidate-playbook.ps1'
function Invoke-Cons([string[]] $ArgList) {
    $out = & pwsh -NoProfile -File $script @ArgList 2>&1
    [pscustomobject]@{ Exit = $LASTEXITCODE; Text = ($out -join "`n") }
}
function Write-Decisions([string] $repo, [object] $obj) {
    $p = Join-Path $repo '.superpowers/decisions.json'
    New-Item -ItemType Directory -Force (Split-Path $p) | Out-Null
    [IO.File]::WriteAllText($p, ($obj | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))
    $p
}

$repo = New-PlaybookFixtureRepo
Write-PlaybookFixtureFile $repo 'A/memory-bank/playbook.md' @'
# Playbook — A

Úvod A.

## Pro celý podstrom

### Když stavíš A

- **A1 pravidlo.** Proč: a. Důkaz: x1.
- **A2 pravidlo.** Proč: a. Důkaz: x2.
- **A3 pravidlo.** Proč: a. Důkaz: x3.

## Jen pro tento projekt

### Když ladíš A

- **A4 pravidlo.** Proč: a. Důkaz: x4.
- **A5 BpmnData pravidlo.** Proč: a. Důkaz: x5.
'@
git -C $repo add -A; git -C $repo commit -q -m cons

Write-Host "== parse"
$r = Invoke-Cons @('-Parse', '-Path', 'A/memory-bank/playbook.md', '-RepoRoot', $repo)
Assert-Eq $r.Exit 0 'parse exits 0'
$j = $r.Text | ConvertFrom-Json
Assert-Eq $j.files[0].items.Count 5 'five items parsed'
Assert-Eq $j.files[0].items[0].id 'A/memory-bank/playbook.md#1' 'global item id'

Write-Host "== apply on new shape"
$d = Write-Decisions $repo @{ run = 'r1'; batch = '01'; decisions = @(
    @{ id = 'A/memory-bank/playbook.md#2'; verdict = 'sloucit'; into = 'A/memory-bank/playbook.md#1'; text = '- **A1+A2 sloučené.** Proč: a. Důkaz: x1.' }
    @{ id = 'A/memory-bank/playbook.md#4'; verdict = 'vyradit'; reason = 'neplatí od abc1234' }
    @{ id = 'A/memory-bank/playbook.md#1'; verdict = 'ponechat' }
    @{ id = 'A/memory-bank/playbook.md#3'; verdict = 'presunout'; target = 'memory-bank/playbook.md'; part = 'podstrom'; section = 'Když píšeš git' }
    @{ id = 'A/memory-bank/playbook.md#5'; verdict = 'presunout'; target = 'A/C/D/memory-bank/playbook.md'; part = 'projekt'; section = 'Když upravuješ BPMN' }
    @{ verdict = 'novy'; target = 'A/memory-bank/playbook.md'; part = 'projekt'; section = 'Když ladíš A'; text = '- **A6 nové.** Proč: a. Důkaz: návrh ums_1_x.' }
) }
$r = Invoke-Cons @('-Apply', $d, '-RepoRoot', $repo, '-Today', '2026-09-23')
Assert-Eq $r.Exit 0 'apply exits 0'
$a = [IO.File]::ReadAllText((Join-Path $repo 'A/memory-bank/playbook.md'))
Assert-Match $a 'A1\+A2 sloučené' 'merged text replaces into-item'
Assert-True (-not ($a -match 'A2 pravidlo')) 'merged source removed'
Assert-True (-not ($a -match 'A4 pravidlo')) 'retired item removed'
Assert-True (-not ($a -match 'A3 pravidlo')) 'moved-up item removed from source'
Assert-True (-not ($a -match 'A5 BpmnData')) 'moved-down item removed from source'
Assert-Match $a 'A6 nové' 'new item inserted'
Assert-Match $a 'Úvod A\.' 'preamble preserved'
$root = [IO.File]::ReadAllText((Join-Path $repo 'memory-bank/playbook.md'))
Assert-Match $root '(?s)## Pro celý podstrom.*### Když píšeš git.*A3 pravidlo' 'moved-up item in ancestor subtree section'
$dpb = [IO.File]::ReadAllText((Join-Path $repo 'A/C/D/memory-bank/playbook.md'))
Assert-Match $dpb '(?s)## Jen pro tento projekt.*### Když upravuješ BPMN.*A5 BpmnData' 'moved-down item in descendant'
$ret = [IO.File]::ReadAllText((Join-Path $repo 'A/memory-bank/playbook-retired.md'))
Assert-Match $ret '(?m)^- A4 pravidlo\. — neplatí od abc1234 \(2026-09-23\)$' 'retired line format'
Assert-Eq (Test-UmsPlaybookShape (Join-Path $repo 'A/memory-bank/playbook.md')).Hard.Count 0 'result passes shape'
$s1 = [IO.File]::ReadAllText((Join-Path $repo 'S1/memory-bank/playbook.md'))
Assert-Match $s1 'S1 pravidlo' 'untouched file untouched'

Write-Host "== legacy conversion must cover every item"
$d = Write-Decisions $repo @{ run = 'r1'; batch = '02'; decisions = @(
    @{ id = 'L/memory-bank/playbook.md#1'; verdict = 'ponechat' }
) }
$before = [IO.File]::ReadAllText((Join-Path $repo 'L/memory-bank/playbook.md'))
$r = Invoke-Cons @('-Apply', $d, '-RepoRoot', $repo)
Assert-True ($r.Exit -ne 0) 'ponechat on a legacy item is refused'
Assert-Eq ([IO.File]::ReadAllText((Join-Path $repo 'L/memory-bank/playbook.md'))) $before 'refused apply leaves file unchanged'
Write-PlaybookFixtureFile $repo 'L/memory-bank/playbook.md' "# Úkoly — L`n`n## Build`n`nL-LEGACY text.`n`n## Deploy`n`nDeploy text.`n"
git -C $repo add -A; git -C $repo commit -q -m legacy2
$d = Write-Decisions $repo @{ run = 'r1'; batch = '03'; decisions = @(
    @{ id = 'L/memory-bank/playbook.md#1'; verdict = 'presunout'; target = 'L/memory-bank/playbook.md'; part = 'projekt'; section = 'Když stavíš L'; text = "**Build L**`nL-LEGACY text." }
) }
$r = Invoke-Cons @('-Apply', $d, '-RepoRoot', $repo)
Assert-True ($r.Exit -ne 0) 'incomplete legacy conversion is refused'
Assert-Match $r.Text 'L/memory-bank/playbook.md#2' 'refusal names the undecided item'
$d = Write-Decisions $repo @{ run = 'r1'; batch = '03'; decisions = @(
    @{ id = 'L/memory-bank/playbook.md#1'; verdict = 'presunout'; target = 'L/memory-bank/playbook.md'; part = 'projekt'; section = 'Když stavíš L'; text = "**Build L**`nL-LEGACY text." }
    @{ id = 'L/memory-bank/playbook.md#2'; verdict = 'vyradit'; reason = 'nahrazeno «Build L»' }
) }
$r = Invoke-Cons @('-Apply', $d, '-RepoRoot', $repo)
Assert-Eq $r.Exit 0 'complete legacy conversion applies'
Assert-Eq (Test-UmsPlaybookShape (Join-Path $repo 'L/memory-bank/playbook.md')).Shape 'new' 'converted file is new shape'

Write-Host "== item outside section is refused before any write"
Write-PlaybookFixtureFile $repo 'BadShape/memory-bank/playbook.md' "# Playbook — BadShape`n`n## Jen pro tento projekt`n`n- **BS pravidlo.** Proč: b. Důkaz: bs1.`n"
git -C $repo add -A; git -C $repo commit -q -m badshape
$badBefore = [IO.File]::ReadAllText((Join-Path $repo 'BadShape/memory-bank/playbook.md'))
$d = Write-Decisions $repo @{ run = 'r1'; batch = '05'; decisions = @(
    @{ id = 'BadShape/memory-bank/playbook.md#1'; verdict = 'ponechat' }
) }
$r = Invoke-Cons @('-Apply', $d, '-RepoRoot', $repo)
Assert-True ($r.Exit -ne 0) 'item outside part/section is refused'
Assert-Match $r.Text 'není v platném tvaru' 'refusal explains invalid shape'
Assert-Match $r.Text 'BadShape/memory-bank/playbook.md#1' 'refusal names the offending item id'
Assert-Eq ([IO.File]::ReadAllText((Join-Path $repo 'BadShape/memory-bank/playbook.md'))) $badBefore 'refused apply leaves malformed file unchanged'

Write-Host "== legacy file without presunout/ponechat is patched in place (harvest gate)"
$gBody = "# Úkoly — G`n`nÚvod G.`n`n## Build`n`n- **G1 pravidlo.**`n  Proč: g1.`n- **G2 pravidlo.**`n  Proč: g2.`n`n## Deploy`n`nDeploy text G.`n"
Write-PlaybookFixtureFile $repo 'G/memory-bank/playbook.md' $gBody
git -C $repo add -A; git -C $repo commit -q -m legacyG
$gPath = Join-Path $repo 'G/memory-bank/playbook.md'
$d = Write-Decisions $repo @{ run = 'h1'; batch = '01'; decisions = @(
    @{ verdict = 'novy'; target = 'G/memory-bank/playbook.md'; part = 'projekt'; section = 'Když stavíš G'; text = '- **G3 nové.** Proč: g3. Důkaz: návrh ums_1_x.' }
) }
$r = Invoke-Cons @('-Apply', $d, '-RepoRoot', $repo, '-Today', '2026-09-23')
Assert-Eq $r.Exit 0 'gate novy into a legacy file applies'
Assert-Eq ([IO.File]::ReadAllText($gPath)) ($gBody + "`n- **G3 nové.** Proč: g3. Důkaz: návrh ums_1_x.`n") 'novy appends after one empty line, old content byte-identical above'
Assert-Eq (Read-UmsPlaybook $gPath).Shape 'legacy' 'patched file stays legacy'
$gBody = [IO.File]::ReadAllText($gPath)
$d = Write-Decisions $repo @{ run = 'h1'; batch = '02'; decisions = @(
    @{ id = 'G/memory-bank/playbook.md#1'; verdict = 'prepsat'; text = "- **G1 přepsané.**`n  Proč: g1 nově." }
) }
$r = Invoke-Cons @('-Apply', $d, '-RepoRoot', $repo, '-Today', '2026-09-23')
Assert-Eq $r.Exit 0 'prepsat of a legacy item applies'
Assert-Eq ([IO.File]::ReadAllText($gPath)) ($gBody.Replace("- **G1 pravidlo.**`n  Proč: g1.", "- **G1 přepsané.**`n  Proč: g1 nově.")) 'prepsat patches only that item'
$gBody = [IO.File]::ReadAllText($gPath)
$d = Write-Decisions $repo @{ run = 'h1'; batch = '03'; decisions = @(
    @{ id = 'G/memory-bank/playbook.md#2'; verdict = 'vyradit'; reason = 'neplatí od abc1234' }
) }
$r = Invoke-Cons @('-Apply', $d, '-RepoRoot', $repo, '-Today', '2026-09-23')
Assert-Eq $r.Exit 0 'vyradit of a legacy item applies'
Assert-Eq ([IO.File]::ReadAllText($gPath)) ($gBody.Replace("- **G2 pravidlo.**`n  Proč: g2.`n", '')) 'vyradit removes only that item'
Assert-Match ([IO.File]::ReadAllText((Join-Path $repo 'G/memory-bank/playbook-retired.md'))) '(?m)^- G2 pravidlo\. — neplatí od abc1234 \(2026-09-23\)$' 'patch-mode retirement writes the retired line'

Write-Host "== ratchet after apply and -Baseline"
$bigRules = (1..4 | ForEach-Object { "### Když krok $_`n`n" + (New-PlaybookRules 50 "B$_") + "`n" }) -join "`n"
Write-PlaybookFixtureFile $repo 'S2/memory-bank/playbook.md' ("# P`n`n## Jen pro tento projekt`n`n" + $bigRules)
git -C $repo add -A; git -C $repo commit -q -m big
$d = Write-Decisions $repo @{ run = 'r1'; batch = '04'; decisions = @(
    @{ id = 'S2/memory-bank/playbook.md#1'; verdict = 'vyradit'; reason = 'duplicita' }
) }
$r = Invoke-Cons @('-Apply', $d, '-RepoRoot', $repo, '-Today', '2026-09-23')
$s2 = Join-Path $repo 'S2/memory-bank/playbook.md'
$pb = Read-UmsPlaybook $s2
Assert-True ($null -ne $pb.Ratchet) 'over-threshold result gets a ratchet'
Assert-Eq $pb.Ratchet.Baseline $pb.LineCount 'baseline equals achieved size'
Assert-Eq (Test-UmsPlaybookShape $s2).Hard.Count 0 'ratcheted file has no hard finding'
Add-Content -Path $s2 -NoNewline -Value "`n- **Navíc.** Proč: a. Důkaz: b.`n"
Assert-True ([bool](@((Test-UmsPlaybookShape $s2).Hard | Where-Object { $_.StartsWith('[ráčna-růst]') }).Count)) 'growth is hard'
$r = Invoke-Cons @('-Baseline', '-Path', 'S2/memory-bank/playbook.md', '-Reason', 'nové pravidlo', '-RepoRoot', $repo, '-Today', '2026-09-24')
Assert-Eq $r.Exit 0 'baseline exits 0'
Assert-Eq (Read-UmsPlaybook $s2).Ratchet.Reason 'nové pravidlo' 'reason recorded'
Assert-Eq (Test-UmsPlaybookShape $s2).Hard.Count 0 'recorded raise passes'

Write-Host "== -Apply never raises a ratchet"
# Fixture in the writer's own layout, so a size-neutral rewrite really is size-neutral.
$rRules = (1..2 | ForEach-Object { "### Když krok $_`n`n" + (New-PlaybookRules 105 "R$_") + "`n" }) -join "`n"
Write-PlaybookFixtureFile $repo 'R/memory-bank/playbook.md' ("# P`n`n## Jen pro tento projekt`n`n" + $rRules)
git -C $repo add -A; git -C $repo commit -q -m ratchetR
$rPath = Join-Path $repo 'R/memory-bank/playbook.md'
$r = Invoke-Cons @('-Baseline', '-Path', 'R/memory-bank/playbook.md', '-Reason', 'zvýšeno člověkem', '-RepoRoot', $repo, '-Today', '2026-09-20')
$base = (Read-UmsPlaybook $rPath).Ratchet
Assert-Eq $base.Reason 'zvýšeno člověkem' 'fixture ratchet carries a human reason'
$d = Write-Decisions $repo @{ run = 'r2'; batch = '01'; decisions = @(
    @{ id = 'R/memory-bank/playbook.md#1'; verdict = 'prepsat'; text = "- **R1 přepsané 1.**`n  Proč: jinak.`n  Důkaz: abc1." }
) }
$r = Invoke-Cons @('-Apply', $d, '-RepoRoot', $repo, '-Today', '2026-09-23')
Assert-Eq $r.Exit 0 'size-neutral apply exits 0'
$rat = (Read-UmsPlaybook $rPath).Ratchet
Assert-Eq $rat.Baseline $base.Baseline 'size-neutral apply keeps the baseline'
Assert-Eq $rat.Reason 'zvýšeno člověkem' 'size-neutral apply keeps the human reason'
$d = Write-Decisions $repo @{ run = 'r2'; batch = '02'; decisions = @(
    @{ verdict = 'novy'; target = 'R/memory-bank/playbook.md'; part = 'projekt'; section = 'Když krok 1'; text = '- **R navíc.** Proč: r. Důkaz: návrh ums_1_x.' }
) }
$r = Invoke-Cons @('-Apply', $d, '-RepoRoot', $repo, '-Today', '2026-09-24')
Assert-Eq $r.Exit 0 'growing apply exits 0'
$rat = (Read-UmsPlaybook $rPath).Ratchet
Assert-Eq $rat.Baseline $base.Baseline 'growing apply does not raise the baseline'
Assert-Eq $rat.Date '2026-09-20' 'growing apply leaves the comment unchanged'
Assert-True ([bool](@((Test-UmsPlaybookShape $rPath).Hard | Where-Object { $_.StartsWith('[ráčna-růst]') }).Count)) 'growth through -Apply is reported as [ráčna-růst]'
$d = Write-Decisions $repo @{ run = 'r2'; batch = '03'; decisions = @(
    @{ id = 'R/memory-bank/playbook.md#2'; verdict = 'vyradit'; reason = 'duplicita' }
    @{ id = 'R/memory-bank/playbook.md#3'; verdict = 'vyradit'; reason = 'duplicita' }
) }
$r = Invoke-Cons @('-Apply', $d, '-RepoRoot', $repo, '-Today', '2026-09-25')
$pbR = Read-UmsPlaybook $rPath
Assert-Eq $pbR.Ratchet.Baseline $pbR.LineCount 'shrinking apply lowers the baseline to the achieved size'
Assert-True ($pbR.LineCount -lt $base.Baseline) 'achieved size is below the old baseline'
Assert-Eq $pbR.Ratchet.Reason $null 'lowered baseline drops the reason'
Assert-Eq $pbR.Ratchet.Date '2026-09-25' 'lowered baseline carries today'
Write-PlaybookFixtureFile $repo 'R2/memory-bank/playbook.md' ("# P`n`n## Jen pro tento projekt`n`n" + $rRules)
git -C $repo add -A; git -C $repo commit -q -m ratchetR2
$d = Write-Decisions $repo @{ run = 'r2'; batch = '04'; decisions = @(
    @{ verdict = 'novy'; target = 'R2/memory-bank/playbook.md'; part = 'projekt'; section = 'Když krok 1'; text = '- **R2 navíc.** Proč: r. Důkaz: návrh ums_1_x.' }
) }
$r = Invoke-Cons @('-Apply', $d, '-RepoRoot', $repo, '-Today', '2026-09-24')
$r2Path = Join-Path $repo 'R2/memory-bank/playbook.md'
Assert-Eq (Read-UmsPlaybook $r2Path).Ratchet $null 'a growing apply never adds a ratchet'
Assert-True ([bool](@((Test-UmsPlaybookShape $r2Path).Hard | Where-Object { $_.StartsWith('[ráčna-chybí]') }).Count)) 'so the shape check reports [ráčna-chybí]'

Write-Host "== -Baseline removes a stale ratchet comment once under threshold"
Write-PlaybookFixtureFile $repo 'Small/memory-bank/playbook.md' "# P`n<!-- playbook-budget: 600; baseline: 999 (2020-01-01) -->`n`n## Jen pro tento projekt`n`n### Když malý`n`n- **Small pravidlo.** Proč: s. Důkaz: s1.`n"
git -C $repo add -A; git -C $repo commit -q -m small
$small = Join-Path $repo 'Small/memory-bank/playbook.md'
Assert-True ($null -ne (Read-UmsPlaybook $small).Ratchet) 'fixture starts with a ratchet comment'
$r = Invoke-Cons @('-Baseline', '-Path', 'Small/memory-bank/playbook.md', '-RepoRoot', $repo, '-Today', '2026-09-23')
Assert-Eq $r.Exit 0 '-Baseline on a small file exits 0'
Assert-Eq (Read-UmsPlaybook $small).Ratchet $null '-Baseline drops the ratchet comment once the file is at/below threshold'
# -Apply writes through the same Set-Ratchet call as -Baseline (see consolidate-playbook.ps1,
# function Set-Ratchet used by both the 'Apply' and 'Baseline' parameter sets) — one covered
# path is enough to prove "pod prahem komentář odstraní" for both entry points.

Write-Host "== resume from trailers"
git -C $repo add -A
git -C $repo commit -q -m "UMS-1: dávka 01" -m "Playbook-Consolidation: r9/01"
git -C $repo commit -q --allow-empty -m "UMS-1: dávka 02" -m "Playbook-Consolidation: r9/02"
$r = Invoke-Cons @('-Resume', 'r9', '-RepoRoot', $repo)
Assert-Eq (($r.Text | ConvertFrom-Json).done -join ',') '01,02' 'done batches from trailers'

Write-Host "== stats"
$r = Invoke-Cons @('-Stats', '-Tree', '.', '-RepoRoot', $repo)
$st = ($r.Text | ConvertFrom-Json).mbs | Where-Object mb -eq 'S2/memory-bank'
Assert-True $st.overThreshold 'stats flags over-threshold MB'
Assert-True ($st.sections.Count -ge 4) 'stats lists sections'

Remove-Item -Recurse -Force $repo
Complete-Tests
