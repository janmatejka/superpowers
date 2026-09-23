#Requires -Version 7
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_assert.ps1')
. (Join-Path $PSScriptRoot '..\scripts\Test-UmsPlaybookShape.ps1')

$tmp = Join-Path ([IO.Path]::GetTempPath()) ("pbshape-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $tmp | Out-Null
function Write-Fx([string] $name, [string] $content) {
    $p = Join-Path $tmp $name
    [IO.File]::WriteAllText($p, ($content -replace "`r`n", "`n"), [Text.UTF8Encoding]::new($false))
    $p
}
function New-Rules([int] $count, [string] $prefix) {
    (1..$count | ForEach-Object { "- **$prefix pravidlo $_.** Proč: důvod $_.`n  Důkaz: abc$_." }) -join "`n"
}
function Has([string[]] $list, [string] $code) { [bool](@($list | Where-Object { $_.StartsWith($code) }).Count) }

Write-Host "== valid small file"
$p = Write-Fx 'ok.md' ("# P`n`n## Pro celý podstrom`n`n### Když píšeš test`n`n" + (New-Rules 3 'A') + "`n")
$r = Test-UmsPlaybookShape $p
Assert-Eq $r.Hard.Count 0 'no hard findings'
Assert-Eq $r.Warn.Count 0 'no warnings'

Write-Host "== shape violations"
$long = 'x' * 81
$p = Write-Fx 'bad.md' @"
# P

## Pro celý podstrom

- **Mimo sekci.** Proč: a. Důkaz: b.

### Tematická sekce

- **Špatná sekce.** Proč: a. Důkaz: b.

### Když něco

- **Bez důkazu.** Proč: a.
- **$long** Proč: a. Důkaz: b.
- **Pět
  řádků
  pravidla
  je
  moc.** Proč: a. Důkaz: b.

Volný text mimo položku.
"@
$r = Test-UmsPlaybookShape $p
Assert-True (Has $r.Hard '[tvar] položka mimo sekci') 'item outside section'
Assert-True (Has $r.Hard '[tvar] sekce není ve tvaru') 'section not "Když"'
Assert-True (Has $r.Hard '[tvar] chybí Důkaz') 'missing Důkaz'
Assert-True (Has $r.Hard '[tvar] řádek delší než 80') 'line too wide'
Assert-True (Has $r.Hard '[tvar] pravidlo má') 'rule too long'
Assert-True (Has $r.Hard '[tvar] text mimo položku') 'prose outside item'

Write-Host "== legacy only warns"
$p = Write-Fx 'legacy.md' ("# P`n`n## Testy`n`n" + (New-Rules 320 'L') + "`n")
$r = Test-UmsPlaybookShape $p
Assert-Eq $r.Hard.Count 0 'legacy never hard'
Assert-True (Has $r.Warn '[legacy]') 'legacy warning'
Assert-True (Has $r.Warn '[práh-soubor]') 'legacy over threshold warning'

Write-Host "== over threshold without ratchet is hard"
$big = "# P`n`n## Pro celý podstrom`n`n" + ((1..8 | ForEach-Object { "### Když krok $_`n`n" + (New-Rules 38 "S$_") + "`n" }) -join "`n")
$p = Write-Fx 'big.md' $big
$r = Test-UmsPlaybookShape $p
Assert-True ($r.Lines -gt 600) 'fixture is over 600 lines'
Assert-True (Has $r.Hard '[ráčna-chybí]') 'missing ratchet is hard'
Assert-True (Has $r.Warn '[práh-soubor]') 'threshold warning'

Write-Host "== ratchet holds, growth is hard, recorded raise passes"
$lines = $big -split "`n"
$withR = @($lines[0], '<!-- playbook-budget: 600; baseline: 9999 (2026-09-23) -->') + @($lines[1..($lines.Count - 1)])
$p = Write-Fx 'ratchet-ok.md' ($withR -join "`n")
$r = Test-UmsPlaybookShape $p
Assert-Eq $r.Hard.Count 0 'under baseline passes'
$withR[1] = '<!-- playbook-budget: 600; baseline: 610 (2026-09-23) -->'
$p = Write-Fx 'ratchet-grow.md' ($withR -join "`n")
$r = Test-UmsPlaybookShape $p
Assert-True (Has $r.Hard '[ráčna-růst]') 'growth over baseline is hard'
$withR[1] = "<!-- playbook-budget: 600; baseline: $($withR.Count) (2026-09-24, nové pravidlo hooku) -->"
$p = Write-Fx 'ratchet-raised.md' ($withR -join "`n")
$r = Test-UmsPlaybookShape $p
Assert-True (-not (Has $r.Hard '[ráčna-růst]')) 'recorded raise passes'

Write-Host "== section threshold, Proč heuristic, useless ratchet"
$p = Write-Fx 'sec.md' ("# P`n<!-- playbook-budget: 600; baseline: 700 (2026-09-23) -->`n`n## Pro celý podstrom`n`n### Když píšeš`n`n" + (New-Rules 41 'Q') + "`n- **Dvě věty.** Proč: první věta. Druhá věta, např. tahle.`n  Důkaz: x.`n")
$r = Test-UmsPlaybookShape $p
Assert-True (Has $r.Warn '[práh-sekce]') 'section over 40 warns'
Assert-Match ($r.Warn -join ' ') 'sekce.*m.* 42 ' 'section warning text contains section name and count'
Assert-True (Has $r.Warn '[proč]') 'two-sentence Proč warns'
Assert-True (Has $r.Warn '[ráčna-zbytečná]') 'ratchet under threshold warns'
Assert-Eq $r.Hard.Count 0 'none of these is hard'

Write-Host "== procedure length"
$body = (1..16 | ForEach-Object { "krok $_" }) -join "`n"
$p = Write-Fx 'postup.md' ("# P`n`n## Jen pro tento projekt`n`n### Když stavíš`n`n**Build**`n$body`n")
$r = Test-UmsPlaybookShape $p
Assert-True (Has $r.Hard '[tvar] postup má') 'procedure over 16 lines is hard'

Remove-Item -Recurse -Force $tmp
Complete-Tests
