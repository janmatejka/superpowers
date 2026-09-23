#Requires -Version 7
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_assert.ps1')
. (Join-Path $PSScriptRoot '..\scripts\Read-UmsPlaybook.ps1')

$tmp = Join-Path ([IO.Path]::GetTempPath()) ("pbparse-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $tmp | Out-Null
$fence = '`' * 3
function Write-Fx([string] $name, [string] $content) {
    $p = Join-Path $tmp $name
    [IO.File]::WriteAllText($p, ($content.Replace('@@FENCE@@', $fence) -replace "`r`n", "`n"), [Text.UTF8Encoding]::new($false))
    $p
}

Write-Host "== new shape"
$p = Write-Fx 'new.md' @'
# Playbook — test

Úvodní věta.

## Pro celý podstrom

### Když píšeš test

- **Pravidlo jedna.** Proč: důvod jedna. Důkaz: abc1234.
- **Pravidlo dvě na dva
  řádky.** Proč: důvod dvě. Důkaz: návrh ums_1_x.

**Postup instalace**
@@FENCE@@bash
- **tohle není položka**
pwsh -File install.ps1
@@FENCE@@
Proč: bez hooku není záruka.

## Jen pro tento projekt

### Když nasazuješ

- **Pravidlo tři.** Proč: důvod tři. Důkaz: test x.tests.ps1.
'@
$pb = Read-UmsPlaybook $p
Assert-Eq $pb.Shape 'new' 'new shape detected'
Assert-Eq $pb.Items.Count 4 'four items (fenced bullet is not an item)'
Assert-Eq $pb.Items[0].Kind 'pravidlo' 'item 1 is a rule'
Assert-Eq $pb.Items[0].Part 'podstrom' 'item 1 part'
Assert-Eq $pb.Items[0].Section 'Když píšeš test' 'item 1 section'
Assert-Eq $pb.Items[0].Proc 'důvod jedna.' 'item 1 Proč'
Assert-Eq $pb.Items[0].Dukaz 'abc1234.' 'item 1 Důkaz'
Assert-Eq $pb.Items[1].LineCount 2 'item 2 spans two lines'
Assert-Eq $pb.Items[2].Kind 'postup' 'item 3 is a procedure'
Assert-Eq $pb.Items[2].Title 'Postup instalace' 'procedure title'
Assert-Eq $pb.Items[2].LineCount 6 'procedure spans title, fence and Proč'
Assert-Eq $pb.Items[3].Part 'projekt' 'item 4 part'
Assert-Eq $pb.Parts['podstrom'].Start 5 'podstrom part starts at its heading'
Assert-Eq $pb.Parts['podstrom'].End 19 'podstrom part ends on the line before the next part heading'
Assert-Eq $pb.PreambleEnd 4 'preamble ends before first H2'
Assert-True ($null -eq $pb.Ratchet) 'no ratchet'

Write-Host "== new shape blank line closes item (Ruling R1)"
$p = Write-Fx 'new-blankline.md' @'
# Playbook — blank line test

## Pro celý podstrom

### Když píšeš test

- **Pravidlo blank.** Proč: důvod blank. Důkaz: xyz.

Prostý text za pravidlem.
'@
$pb = Read-UmsPlaybook $p
Assert-Eq $pb.Items.Count 2 'blank line splits rule and following text into two items'
Assert-Eq $pb.Items[0].Kind 'pravidlo' 'first item stays a rule'
Assert-Eq $pb.Items[0].LineCount 1 'rule LineCount is unchanged by the blank line and following text'
Assert-Eq $pb.Items[1].Kind 'prose' 'text after the blank line is its own item, not absorbed into the rule'
Assert-Eq $pb.Items[1].Title 'Prostý text za pravidlem.' 'prose item text'

Write-Host "== no ## heading at all (Ruling R3)"
$p = Write-Fx 'no-h2.md' @'
# Kopie

Nějaký text.
- **Pravidlo X.** Proč: x.
'@
$pb = Read-UmsPlaybook $p
Assert-Eq $pb.Shape 'legacy' 'H2-less file is legacy'
Assert-Eq $pb.PreambleEnd 0 'no ## heading means PreambleEnd is 0'
Assert-Eq $pb.Items.Count 2 'items are not silently dropped'
Assert-Eq $pb.Items[0].Kind 'prose' 'prose item before the rule is kept'
Assert-Eq $pb.Items[1].Kind 'pravidlo' 'rule item is kept'

Write-Host "== legacy bold bullets"
$p = Write-Fx 'legacy-bullets.md' @'
# Playbook

## Testy vrstvy

Úvodní odstavec sekce.

- **Pravidlo A.** Proč: a.
- **Pravidlo B.**
  Proč: b.
'@
$pb = Read-UmsPlaybook $p
Assert-Eq $pb.Shape 'legacy' 'non-part H2 means legacy'
Assert-Eq $pb.Items.Count 3 'prose + two rules'
Assert-Eq $pb.Items[0].Kind 'prose' 'intro paragraph is prose'
Assert-Eq $pb.Items[1].Section 'Testy vrstvy' 'legacy section is the H2 title'
Assert-True ($null -eq $pb.Items[1].Part) 'legacy item has no part'
Assert-Eq $pb.Items[2].LineCount 2 'rule B spans two lines'

Write-Host "== legacy heading items"
$p = Write-Fx 'legacy-headings.md' @'
# Úkoly — X

## Úkoly

### Úkol A

1. krok jedna
2. krok dva

### Úkol B

Text úkolu B.

## Git push

Před pushem ověř větev.
'@
$pb = Read-UmsPlaybook $p
Assert-Eq $pb.Items.Count 3 'three heading items'
Assert-Eq (@($pb.Items | Where-Object Kind -eq 'heading')).Count 3 'all are heading items'
Assert-Eq $pb.Items[0].Title 'Úkol A' 'heading item title'
Assert-Eq $pb.Items[0].Section 'Úkoly' 'heading item section is parent heading'
Assert-Eq $pb.Items[0].LineCount 4 'heading item spans heading and body'
Assert-Eq $pb.Items[2].Title 'Git push' 'H2 heading item'

Write-Host "== transitional mix"
$p = Write-Fx 'legacy-mix.md' @'
# Playbook — Y

## Postup build

Spusť build.

## Rules

- **Pravidlo R.** Proč: r.
'@
$pb = Read-UmsPlaybook $p
Assert-Eq $pb.Items.Count 2 'heading item + rule'
Assert-Eq $pb.Items[0].Kind 'heading' 'first is heading item'
Assert-Eq $pb.Items[1].Kind 'pravidlo' 'second is rule'

Write-Host "== ratchet"
$p = Write-Fx 'ratchet.md' @'
# Playbook
<!-- playbook-budget: 600; baseline: 2414 (2026-09-23, konsolidace kolo 1) -->

## Pro celý podstrom
'@
$pb = Read-UmsPlaybook $p
Assert-Eq $pb.Ratchet.Budget 600 'ratchet budget'
Assert-Eq $pb.Ratchet.Baseline 2414 'ratchet baseline'
Assert-Eq $pb.Ratchet.Date '2026-09-23' 'ratchet date'
Assert-Eq $pb.Ratchet.Reason 'konsolidace kolo 1' 'ratchet reason'
Assert-Eq $pb.Shape 'new' 'part-only file is new shape'

Write-Host "== part heading plus foreign H2 is legacy"
$p = Write-Fx 'mixed-h2.md' @'
# P

## Pro celý podstrom

## Něco jiného
'@
Assert-Eq (Read-UmsPlaybook $p).Shape 'legacy' 'foreign H2 forces legacy'

Remove-Item -Recurse -Force $tmp
Complete-Tests
