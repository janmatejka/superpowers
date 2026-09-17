#Requires -Version 7
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '_assert.ps1')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\scripts\Test-UmsJiraDescription.ps1')
$good = "**Cíl**`n`nZmenšit vrstvu.`n`n**Rozsah**`n`nDovnitř:`n- A`n`n**Návrh (design):** [design_x.md](https://github.com/o/r/blob/0123456789abcdef0123456789abcdef01234567/design_x.md)`n`n**Ověření**`n`nSada zelená."
$r = Test-UmsJiraDescription -Text $good -RequireSections
Assert-True $r.Ok 'šablonový popis prochází'
$r = Test-UmsJiraDescription -Text ($good + ('x' * 2500))
Assert-True (-not $r.Ok) 'popis nad rozpočtem neprochází'
Assert-Match ($r.Findings -join ';') 'rozpočet je 2500' 'nález jmenuje rozpočet'
$r = Test-UmsJiraDescription -Text ($good -replace '\[design_x\.md\]', '[`design_x.md`]')
Assert-Match ($r.Findings -join ';') 'Text odkazu obsahuje backticks' 'backticks v textu odkazu jsou nález'
$r = Test-UmsJiraDescription -Text ($good + "`n**tučné ``kód`` uvnitř**")
Assert-Match ($r.Findings -join ';') 'Tučné obaluje code span' 'tučné kolem code spanu je nález'
$r = Test-UmsJiraDescription -Text ($good + "`nsoubory shared/contract/<téma>.md")
Assert-Match ($r.Findings -join ';') 'ostré závorky' 'ostré závorky jsou nález'
$r = Test-UmsJiraDescription -Text ($good -replace '\*\*Rozsah\*\*', '**Scope**') -RequireSections
Assert-Match ($r.Findings -join ';') 'Chybí sekce \*\*Rozsah\*\*' 'chybějící sekce je nález'
$r = Test-UmsJiraDescription -Text ($good -replace '\*\*Rozsah\*\*', '**Scope**')
Assert-True $r.Ok 'bez -RequireSections se sekce nekontrolují (komentáře)'
Complete-Tests
