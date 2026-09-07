#Requires -Version 7
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_assert.ps1')
. (Join-Path $PSScriptRoot 'new-gate-fixture.ps1')
. (Join-Path $PSScriptRoot '..\scripts\Test-UmsHandoffGate.ps1')

$f = New-GateFixture
try {
    Write-Host "== brána projde pro publikovaný, IDLE, potomkovský commit"
    $r = Test-UmsHandoffGate -RepoRoot $f.Clone -Sha $f.MergedSha -BaseRef $f.BaseRef
    Assert-True $r.Ok 'brána projde pro publikovaný, IDLE, potomkovský commit'
    Assert-Eq (@($r.Checks).Count) 3 'brána vrací právě tři kontroly'
    Assert-Eq (@($r.Blocking).Count) 0 'u průchodu není nic blokující'

    # NEGATIVNÍ: báze se pohnula po zapamatování tipu. Tohle je ta kontrola,
    # kvůli které brána vůbec existuje — 244 kvůli tomu dvakrát přepisovala
    # výčet odchozích commitů. Bázi posouvá druhý klon, takže dokud brána
    # nefetchne, vidí první klon zastaralý origin/<base> a kontrola by prošla.
    Write-Host "== báze se pohnula: blokuje jen kontrola ancestor"
    Move-GateBase $f
    $r = Test-UmsHandoffGate -RepoRoot $f.Clone -Sha $f.MergedSha -BaseRef $f.BaseRef
    Assert-True (-not $r.Ok) 'brána zamítne, když se báze pohnula'
    Assert-Match ($r.Blocking -join ',') 'ancestor' 'blokující kontrola je jmenovaná'
    Assert-Eq ($r.Blocking -join ',') 'ancestor' 'pohnutá báze blokuje POUZE kontrolu ancestor'

    # NEGATIVNÍ: ACTIVE pin. Měřený únik u 242, zachycený jen pozorností.
    # Tahle větev je odříznutá z commitu, kterým Move-GateBase bázi posunul,
    # takže ji kontrola ancestor nemá čím zamítnout — alibi neexistuje.
    Write-Host "== ACTIVE pin: blokuje jen kontrola contextu"
    $r = Test-UmsHandoffGate -RepoRoot $f.Clone -Sha $f.ActiveSha -BaseRef $f.BaseRef
    Assert-True (-not $r.Ok) 'brána zamítne commit s ACTIVE pinem'
    Assert-Eq ($r.Blocking -join ',') 'active-pin' 'ACTIVE pin blokuje POUZE kontrolu contextu'

    # NEGATIVNÍ: nepublikovaný commit.
    Write-Host "== nepublikovaný commit: blokuje jen kontrola publikace"
    $r = Test-UmsHandoffGate -RepoRoot $f.Clone -Sha $f.UnpushedSha -BaseRef $f.BaseRef
    Assert-True (-not $r.Ok) 'brána zamítne nepublikovaný commit'
    Assert-Eq ($r.Blocking -join ',') 'unpublished' 'nepublikovaný commit blokuje POUZE kontrolu publikace'

    # NEGATIVNÍ, A JE TO TA NEJDŮLEŽITĚJŠÍ: chybějící context.md je STOP,
    # ne IDLE. git show na neexistující cestu končí kódem 128 a ten se snadno
    # přečte jako „není ACTIVE".
    Write-Host "== chybějící context.md je STOP, ne IDLE"
    $r = Test-UmsHandoffGate -RepoRoot $f.Clone -Sha $f.NoContextSha -BaseRef $f.BaseRef
    Assert-True (-not $r.Ok) 'chybějící context.md je STOP, ne IDLE'
    Assert-Eq ($r.Blocking -join ',') 'context-missing' 'chybějící context.md blokuje POUZE kontrolu contextu'
    # "$(...)" a fallback na prázdný string: kdyby nález 'context-missing'
    # chyběl, tahle asercie musí ZČERVENAT, ne shodit celou sadu a nechat
    # zbytek neprovedený.
    $missingDetail = "$(@($r.Checks | Where-Object { $_.Name -eq 'context-missing' } |
            ForEach-Object { $_.Detail }) -join ' ')"
    Assert-Match $missingDetail 'context\.md' 'nález chybějícího contextu jmenuje soubor'

    # Bez -BaseRef se báze bere z konfigurace repozitáře (kontrakt,
    # „Repository Configuration"), ne z natvrdo zapsaného jména.
    Write-Host "== bez -BaseRef se báze bere z konfigurace"
    $r = Test-UmsHandoffGate -RepoRoot $f.Clone -Sha $f.ActiveSha
    Assert-Eq ($r.Blocking -join ',') 'active-pin' 'konfigurační báze dává týž výsledek jako explicitní'
}
finally {
    Remove-GateFixture $f
}
Complete-Tests
