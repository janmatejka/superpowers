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

# --- fix-round-1 fixtures ------------------------------------------------------
# Added here, in this test file, rather than in new-fixture-repo.ps1: that file
# is Task 2's own interface (New-FixtureRepo/Invoke-Git) and this task may only
# touch its own two files. Each fixture below is dedicated to ONE review
# finding so tests never depend on each other's mutations.
function Add-CommittedFile([string] $RelPath, [string[]] $Lines) {
    $f = Join-Path $work $RelPath
    New-Item -ItemType Directory -Force -Path (Split-Path $f) | Out-Null
    Set-Content -LiteralPath $f -Encoding UTF8 -Value $Lines
    Invoke-Git $work @('add', '--', $RelPath) | Out-Null
    return $f
}

# Multi-line document: enough non-empty lines (11) to exercise ratio math below
# 50%, the C1 multiset-vs-count cases, the findings cap/tail, and the
# case-sensitivity / leading-whitespace mutation kills.
$multiRel = 'A/memory-bank/verify-multiline.md'
$multiLines = @(
    '# Multiline fixture', '',
    'Řádek jedna.', 'Řádek dva.', 'Řádek tři.', 'Řádek čtyři.', 'Řádek pět.',
    'Řádek šest.', 'Řádek sedm.', 'Řádek osm.', 'Řádek devět.', 'Řádek deset.'
)
$multiFull = Add-CommittedFile $multiRel $multiLines
function Reset-Multi { Set-Content -LiteralPath $multiFull -Encoding UTF8 -Value $multiLines }

# Fenced document: a REAL H1 plus a fenced block that itself contains a line
# matching '^#\s' — proves the H1 guard is fence-aware, not fooled by a
# comment that merely happens to start with "# " inside a ``` block.
$fencedRel = 'A/memory-bank/verify-fenced.md'
$fencedLines = @(
    '# Fenced fixture', '', 'Nějaký text.', '',
    '```bash', '# tohle není nadpis', 'echo ahoj', '```', '', 'Zbytek textu.'
)
$fencedFull = Add-CommittedFile $fencedRel $fencedLines

# BOM document: committed WITH a UTF-8 byte-order mark, to prove the U+FEFF on
# the staged blob (git show keeps it) is stripped before comparison with the
# candidate (Get-Content strips it on read).
$bomRel = 'A/memory-bank/verify-bom.md'
$bomFull = Join-Path $work $bomRel
$bomLines = @('# BOM fixture', '', 'Věta jedna.', 'Věta dva.', 'Věta tři.')
New-Item -ItemType Directory -Force -Path (Split-Path $bomFull) | Out-Null
[IO.File]::WriteAllText($bomFull, (($bomLines -join "`n") + "`n"), [Text.UTF8Encoding]::new($true))
Invoke-Git $work @('add', '--', $bomRel) | Out-Null
function Reset-Bom { [IO.File]::WriteAllText($bomFull, (($bomLines -join "`n") + "`n"), [Text.UTF8Encoding]::new($true)) }

# No-H1 document: isolates the empty-output guard from the H1 guard — a doc
# that never had an H1 to begin with, so emptying it can only ever trip the
# "empty" rule, never the "H1 disappeared" rule.
$noH1Rel = 'A/memory-bank/verify-no-h1.md'
$noH1Lines = @('Poznámka bez nadpisu.', '', 'Další řádek.')
$noH1Full = Add-CommittedFile $noH1Rel $noH1Lines

# Staged-diff document: committed once here, then its INDEX (not HEAD) is
# mutated by the C2 test below to prove the verifier reads the staged blob,
# not HEAD.
$stagedRel = 'A/memory-bank/verify-staged-diff.md'
$stagedFull = Join-Path $work $stagedRel
$stagedLines = @('# Staged diff fixture', '', 'Základní věta.')
Add-CommittedFile $stagedRel $stagedLines | Out-Null

Invoke-Git $work @('commit', '-m', 'verify fixtures (fix round 1)') | Out-Null

Write-Host "== Beze změny projde =="
$r = Invoke-Script 'verify-deletion-only.ps1' @('-RepoPath', $work, '-File', $rel)
Assert-Eq $r.Code 0 'Nezměněný soubor vyhovuje'
Assert-Match $r.Out 'Verifikace mazacího režimu prošla' 'Úspěšný verdikt obsahuje očekávaný text (I3e)'

Write-Host "== Smazání projde =="
Set-Content -LiteralPath $full -Encoding UTF8 -Value ($orig | Select-Object -First 2)
$r = Invoke-Script 'verify-deletion-only.ps1' @('-RepoPath', $work, '-File', $rel)
Assert-Eq $r.Code 0 'Smazání řádků vyhovuje'
Assert-Match $r.Out 'Ubráno neprázdných řádků: \d+ z \d+' 'Zpráva obsahuje řádek s počtem ubraných řádků (I3f)'

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
Assert-Match $r.Out ([regex]::Escape("Obnov mechanickou verzi: git checkout -- $rel")) 'Zpráva obsahuje přesnou instrukci obnovy (I3b)'

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
Assert-Eq $r.Code 2 'Duplikovaný řádek nad rámec původního výskytu -> porušení (multiset, ne jen počet)'

Write-Host "== Prázdný výstup neprojde =="
Set-Content -LiteralPath $full -Encoding UTF8 -Value @()
$r = Invoke-Script 'verify-deletion-only.ps1' @('-RepoPath', $work, '-File', $rel)
Assert-Eq $r.Code 2 'Prázdný soubor je porušení'

Write-Host "== Smazaný soubor pracovního stromu neprojde (I2) =="
Reset-Candidate
Remove-Item -LiteralPath $full -Force
$r = Invoke-Script 'verify-deletion-only.ps1' @('-RepoPath', $work, '-File', $rel)
Assert-Eq $r.Code 2 'Smazaný soubor pracovního stromu je porušení, ne pád skriptu'
Assert-Match $r.Out ([regex]::Escape("Obnov mechanickou verzi: git checkout -- $rel")) 'Zpráva obsahuje instrukci obnovy i pro smazaný soubor'
Reset-Candidate

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

Write-Host "== Úbytek pod 50 % nehlásí VAROVÁNÍ (I3) =="
Reset-Multi
Set-Content -LiteralPath $multiFull -Encoding UTF8 -Value ($multiLines[0..9])
$r = Invoke-Script 'verify-deletion-only.ps1' @('-RepoPath', $work, '-File', $multiRel)
Assert-Eq $r.Code 0 'Malý úbytek (pod 50 %) vyhovuje'
Assert-NotMatch $r.Out 'VAROVÁNÍ' 'Malý úbytek nehlásí varování'

Write-Host "== Duplikace přeživšího řádku nad rámec originálu je porušení i při stálém počtu neprázdných řádků (C1) =="
Reset-Multi
# Delete FIVE lines (Řádek šest..deset), then repeat one SURVIVING line
# ('Řádek jedna.') five more times. Non-empty count: original=11,
# candidate=11 (H1 + 5 survivors + 5 duplicates) — EQUAL, not larger. The
# old set+count check would have passed this (every line individually a
# member of the original's set, count not increased); multiset containment
# correctly rejects it because 'Řádek jedna.' is spent six times against a
# budget of one.
$survivors = @($multiLines[0]) + @($multiLines[2..6])
$dup = $survivors + (1..5 | ForEach-Object { $multiLines[2] })
Set-Content -LiteralPath $multiFull -Encoding UTF8 -Value $dup
$r = Invoke-Script 'verify-deletion-only.ps1' @('-RepoPath', $work, '-File', $multiRel)
Assert-Eq $r.Code 2 'Duplikace přeživšího řádku nad rámec původního výskytu je porušení'

Write-Host "== Záměna prázdného řádku za duplicitní obsah neprojde se záporným počtem ubraných řádků (C1) =="
Reset-Multi
# Same total line count as the original (12), but the sole blank line is
# dropped and one content line is duplicated instead: non-empty count goes
# from 11 to 12 — the document GREW. The old count-only guard compared
# TOTAL line count (12 <= 12, passes) and the set check found every line a
# member (passes) — printing a NEGATIVE "removed" number while returning
# exit 0. Multiset containment must reject this before that message is ever
# produced.
$swapped = @($multiLines[0]) + @($multiLines[2..11]) + @($multiLines[2])
Set-Content -LiteralPath $multiFull -Encoding UTF8 -Value $swapped
$r = Invoke-Script 'verify-deletion-only.ps1' @('-RepoPath', $work, '-File', $multiRel)
Assert-Eq $r.Code 2 'Záměna prázdného řádku za duplicitní obsah je porušení'

Write-Host "== Nálezy nad limit 10 jsou useknuté s dovětkem (I3) =="
Reset-Multi
$invented = 1..15 | ForEach-Object { "Vymyšlená věta $_." }
Set-Content -LiteralPath $multiFull -Encoding UTF8 -Value ($multiLines + $invented)
$r = Invoke-Script 'verify-deletion-only.ps1' @('-RepoPath', $work, '-File', $multiRel)
Assert-Eq $r.Code 2 'Patnáct vymyšlených řádků je porušení'
$bulletLines = @(($r.Out -split "`r?`n") | Where-Object { $_ -match '^-\s' -and $_ -notmatch 'a dalších' })
Assert-Eq $bulletLines.Count 10 'Nálezy jsou oříznuty na prvních 10'
Assert-Match $r.Out 'a dalších 5 porušení' 'Dovětek hlásí zbylých 5 porušení'
Reset-Multi

Write-Host "== Cesta bez staged obsahu vrací chybu, exit 1 (I3) =="
$neverStagedRel = 'A/memory-bank/never-staged.md'
$neverStagedFull = Join-Path $work $neverStagedRel
Set-Content -LiteralPath $neverStagedFull -Encoding UTF8 -Value @('# Nikdy nestageováno')
$r = Invoke-Script 'verify-deletion-only.ps1' @('-RepoPath', $work, '-File', $neverStagedRel)
Assert-Eq $r.Code 1 'Soubor mimo staging (nikdy negit-add-ovaný) končí chybou 1'
Assert-Match $r.Out 'staging' 'Zpráva zmiňuje staging'

Write-Host "== Verifikátor čte STAGING, ne HEAD (C2) =="
# Stage a change to the dedicated file WITHOUT committing — the index now
# differs from HEAD, exactly the shape migrate-mb-docs.ps1 -Apply leaves
# behind (git add, no commit). The candidate below is valid ONLY against the
# staged content: it keeps a sentence that exists in the index but not in
# HEAD. Comparing against HEAD instead (the regression this test exists to
# catch) would flag that sentence as invented and fail with exit 2.
$stagedExtra = $stagedLines + @('Nová stageovaná věta, není v HEAD.')
Set-Content -LiteralPath $stagedFull -Encoding UTF8 -Value $stagedExtra
Invoke-Git $work @('add', '--', $stagedRel) | Out-Null

$stagedCandidate = @($stagedLines[0], 'Nová stageovaná věta, není v HEAD.')
Set-Content -LiteralPath $stagedFull -Encoding UTF8 -Value $stagedCandidate
$r = Invoke-Script 'verify-deletion-only.ps1' @('-RepoPath', $work, '-File', $stagedRel)
Assert-Eq $r.Code 0 'Kandidát platný jen proti staged obsahu prochází -> verifikátor čte index, ne HEAD'

$headContent = ((& git -C $work show "HEAD:$stagedRel") -join "`n")
Assert-NotMatch $headContent 'Nová stageovaná věta' 'HEAD skutečně neobsahuje stageovanou větu (test je smysluplný)'

Invoke-Git $work @('reset', '--', $stagedRel) | Out-Null
Invoke-Git $work @('checkout', '--', $stagedRel) | Out-Null

Write-Host "== Nadpis H1 uvnitř ohraničeného bloku nenahrazuje skutečný H1 (C3) =="
$fencedNoH1 = @($fencedLines | Where-Object { $_ -ne $fencedLines[0] })
Set-Content -LiteralPath $fencedFull -Encoding UTF8 -Value $fencedNoH1
$r = Invoke-Script 'verify-deletion-only.ps1' @('-RepoPath', $work, '-File', $fencedRel)
Assert-Eq $r.Code 2 'Smazání skutečného H1 je porušení, i když ve fence přežije řádek se znakem #'
Assert-Match $r.Out 'H1' 'Nález zmiňuje H1'

Write-Host "== BOM na staged blobu nerozbíjí porovnání beze změny (I1) =="
$r = Invoke-Script 'verify-deletion-only.ps1' @('-RepoPath', $work, '-File', $bomRel)
Assert-Eq $r.Code 0 'Byte-identický kandidát (Get-Content bez BOM) odpovídá BOM originálu ve stagingu'

Write-Host "== BOM nevypíná H1 guard (I1) =="
Set-Content -LiteralPath $bomFull -Encoding UTF8 -Value ($bomLines | Select-Object -Skip 1)
$r = Invoke-Script 'verify-deletion-only.ps1' @('-RepoPath', $work, '-File', $bomRel)
Assert-Eq $r.Code 2 'Smazání H1 je porušení i když originál nese BOM'
Reset-Bom

Write-Host "== Prázdný výstup bez nadpisu H1 je porušení jen kvůli prázdnotě, ne H1 (I3) =="
Set-Content -LiteralPath $noH1Full -Encoding UTF8 -Value @()
$r = Invoke-Script 'verify-deletion-only.ps1' @('-RepoPath', $work, '-File', $noH1Rel)
Assert-Eq $r.Code 2 'Prázdný soubor bez H1 je stále porušení'
Assert-Match $r.Out 'prázdn' 'Nález zmiňuje prázdnotu'
Assert-NotMatch $r.Out 'Nadpis H1' 'Nález nezmiňuje H1 - originál žádný neměl (izolace prázdného pravidla)'

Write-Host "== Změna velikosti písmen je porušení (Ordinal, ne OrdinalIgnoreCase) (I3) =="
Reset-Candidate
$caseMutated = $orig | ForEach-Object { $_ -replace 'Komponenta', 'komponenta' }
Set-Content -LiteralPath $full -Encoding UTF8 -Value $caseMutated
$r = Invoke-Script 'verify-deletion-only.ps1' @('-RepoPath', $work, '-File', $rel)
Assert-Eq $r.Code 2 'Změna velikosti písmen je porušení'

Write-Host "== Přidaná úvodní mezera je porušení (TrimEnd, ne Trim) (I3) =="
Reset-Candidate
$leadingWs = $orig | ForEach-Object { if ($_ -eq 'Komponenta A dělá věci.') { '  ' + $_ } else { $_ } }
Set-Content -LiteralPath $full -Encoding UTF8 -Value $leadingWs
$r = Invoke-Script 'verify-deletion-only.ps1' @('-RepoPath', $work, '-File', $rel)
Assert-Eq $r.Code 2 'Přidaná úvodní mezera je porušení'

Write-Host "== Přidání/odebrání jen prázdných řádků neprojde jako porušení (I4) =="
Reset-Candidate
$blankShuffled = @($orig[0], $orig[2], '', '', $orig[3], $orig[4], '')
Set-Content -LiteralPath $full -Encoding UTF8 -Value $blankShuffled
$r = Invoke-Script 'verify-deletion-only.ps1' @('-RepoPath', $work, '-File', $rel)
Assert-Eq $r.Code 0 'Přidání i odebrání prázdných řádků beze změny obsahu je v pořádku'

Write-Host "== Obnova stagingem =="
& git -C $work checkout -- $rel
$restored = Get-Content -LiteralPath $full
Assert-Eq ($restored -join "`n") ($orig -join "`n") 'git checkout -- obnoví mechanickou verzi'

Complete-Tests
