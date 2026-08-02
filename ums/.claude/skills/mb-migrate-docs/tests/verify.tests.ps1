#Requires -Version 7
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_assert.ps1')
. (Join-Path $PSScriptRoot 'new-fixture-repo.ps1')

$fx = New-FixtureRepo
$work = $fx.Work
$rel = 'A/memory-bank/brief.md'
$full = Join-Path $work $rel
$orig = Get-Content -LiteralPath $full

function Reset-Candidate { Set-Content -LiteralPath $full -Encoding UTF8 -Value $orig }

Write-Host "== Beze změny projde =="
$r = Invoke-Script 'verify-deletion-only.ps1' @('-RepoPath', $work, '-File', $rel)
Assert-Eq $r.Code 0 'Nezměněný soubor vyhovuje'

Write-Host "== Smazání projde =="
Set-Content -LiteralPath $full -Encoding UTF8 -Value ($orig | Select-Object -First 2)
$r = Invoke-Script 'verify-deletion-only.ps1' @('-RepoPath', $work, '-File', $rel)
Assert-Eq $r.Code 0 'Smazání řádků vyhovuje'

Write-Host "== Přeskupení projde =="
Set-Content -LiteralPath $full -Encoding UTF8 -Value ($orig | Sort-Object)
$r = Invoke-Script 'verify-deletion-only.ps1' @('-RepoPath', $work, '-File', $rel)
Assert-Eq $r.Code 0 'Přeskupení řádků vyhovuje'

Write-Host "== Nový řádek neprojde =="
Reset-Candidate
Add-Content -LiteralPath $full -Encoding UTF8 -Value 'Tuhle větu nikdo nenapsal.'
$r = Invoke-Script 'verify-deletion-only.ps1' @('-RepoPath', $work, '-File', $rel)
Assert-Eq $r.Code 2 'Přidaný řádek je porušení'
Assert-Match $r.Out 'Tuhle větu nikdo nenapsal' 'Porušující řádek je ve zprávě'

Write-Host "== Změna uvnitř řádku neprojde =="
Reset-Candidate
$mutated = $orig | ForEach-Object { $_ -replace 'Komponenta A dělá věci\.', 'Komponenta A dělá jiné věci.' }
Set-Content -LiteralPath $full -Encoding UTF8 -Value $mutated
$r = Invoke-Script 'verify-deletion-only.ps1' @('-RepoPath', $work, '-File', $rel)
Assert-Eq $r.Code 2 'Přeformulovaný řádek je porušení'

Write-Host "== Delší výstup než vstup neprojde =="
Reset-Candidate
Add-Content -LiteralPath $full -Encoding UTF8 -Value ($orig[0])
$r = Invoke-Script 'verify-deletion-only.ps1' @('-RepoPath', $work, '-File', $rel)
Assert-Eq $r.Code 2 'Duplikovaný řádek zvyšuje počet řádků -> porušení'

Write-Host "== Prázdný výstup neprojde =="
Set-Content -LiteralPath $full -Encoding UTF8 -Value @()
$r = Invoke-Script 'verify-deletion-only.ps1' @('-RepoPath', $work, '-File', $rel)
Assert-Eq $r.Code 2 'Prázdný soubor je porušení'

Write-Host "== Ztráta H1 neprojde =="
Set-Content -LiteralPath $full -Encoding UTF8 -Value ($orig | Where-Object { $_ -notmatch '^#\s' })
$r = Invoke-Script 'verify-deletion-only.ps1' @('-RepoPath', $work, '-File', $rel)
Assert-Eq $r.Code 2 'Smazaný H1 nadpis je porušení'

Write-Host "== Varování při velkém úbytku =="
Reset-Candidate
Set-Content -LiteralPath $full -Encoding UTF8 -Value @($orig[0])
$r = Invoke-Script 'verify-deletion-only.ps1' @('-RepoPath', $work, '-File', $rel)
Assert-Eq $r.Code 0 'Velký úbytek stále vyhovuje'
Assert-Match $r.Out 'VAROVÁNÍ' 'Velký úbytek je hlášen jako varování'

Write-Host "== Obnova stagingem =="
& git -C $work checkout -- $rel
$restored = Get-Content -LiteralPath $full
Assert-Eq ($restored -join "`n") ($orig -join "`n") 'git checkout -- obnoví mechanickou verzi'

Complete-Tests
