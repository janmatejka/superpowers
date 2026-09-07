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

    # Čtvrtá kontrola, `verification-set`, je čistě textové srovnání dvou
    # parametrů (-VerificationSet = deklarovaná sada, -CitedCommands = co
    # artefakt cituje). Testuje se TADY, dokud je $f.MergedSha ještě zeleným
    # potomkem NEPOSUNUTÉ báze — Move-GateBase o pár řádků níž bázi posune
    # a od té chvíle by MergedSha sám o sobě zablokoval kontrolu `ancestor`,
    # což by kontaminovalo asercie „blokuje POUZE verification-set".
    $declared = @('pwsh ./build.ps1', 'pwsh ./test.ps1')

    Write-Host "== verification-set: citace odpovídá deklarované sadě"
    $r = Test-UmsHandoffGate -RepoRoot $f.Clone -Sha $f.MergedSha -BaseRef $f.BaseRef `
        -VerificationSet $declared -CitedCommands $declared
    Assert-True $r.Ok 'shodná citace nic neblokuje'
    Assert-Eq (@($r.Checks).Count) 4 's deklarovanou sadou přibývá čtvrtá kontrola'
    Assert-Eq (@($r.Blocking).Count) 0 'shodná citace neblokuje nic'
    # Ok/Blocking samotné by prošly i vacuous (kdyby čtvrtá kontrola vůbec
    # neexistovala) — tahle asercie potřebuje, aby kontrola verification-set
    # SKUTEČNĚ existovala a SKUTEČNĚ prošla.
    Assert-Eq (@(@($r.Checks | Where-Object { $_.Name -eq 'verification-set' -and $_.Passed -eq $true })).Count) 1 `
        'čtvrtá kontrola je pojmenovaná verification-set a sama prošla'

    # NEGATIVNÍ: bez sady se kontrola vůbec nepřidá — nesmí fabrikovat ani
    # průchod, ani selhání tam, kde není co porovnávat.
    Write-Host "== bez deklarované sady se kontrola verification-set nepřidává"
    $r = Test-UmsHandoffGate -RepoRoot $f.Clone -Sha $f.MergedSha -BaseRef $f.BaseRef `
        -CitedCommands $declared
    Assert-Eq (@($r.Checks).Count) 3 'bez deklarované sady zůstávají jen tři kontroly'
    Assert-Eq (@(@($r.Checks | Where-Object { $_.Name -eq 'verification-set' })).Count) 0 `
        'kontrola verification-set se bez deklarované sady vůbec neobjeví'

    # NEGATIVNÍ: chybějící citace u deklarované sady je blokující nález.
    Write-Host "== verification-set: chybějící citace blokuje, když je sada deklarovaná"
    $r = Test-UmsHandoffGate -RepoRoot $f.Clone -Sha $f.MergedSha -BaseRef $f.BaseRef `
        -VerificationSet $declared -CitedCommands @()
    Assert-True (-not $r.Ok) 'chybějící citace blokuje, když je sada deklarovaná'
    Assert-Eq ($r.Blocking -join ',') 'verification-set' 'chybějící citace blokuje POUZE kontrolu verification-set'

    # NEGATIVNÍ: citace odlišná od deklarované sady je blokující nález a
    # hláška jmenuje první rozdílný řádek — srovnání je TEXTOVÉ, ne sémantické.
    Write-Host "== verification-set: odlišná citace blokuje a hláška jmenuje první rozdílný řádek"
    $r = Test-UmsHandoffGate -RepoRoot $f.Clone -Sha $f.MergedSha -BaseRef $f.BaseRef `
        -VerificationSet $declared -CitedCommands @('pwsh ./build.ps1', 'pwsh ./jiny-test.ps1')
    Assert-True (-not $r.Ok) 'odlišná citace blokuje'
    Assert-Eq ($r.Blocking -join ',') 'verification-set' 'odlišná citace blokuje POUZE kontrolu verification-set'
    $diffDetail = "$(@($r.Checks | Where-Object { $_.Name -eq 'verification-set' } |
            ForEach-Object { $_.Detail }) -join ' ')"
    Assert-Match $diffDetail 'jiny-test\.ps1' 'nález jmenuje odlišně citovaný řádek'
    Assert-Match $diffDetail 'test\.ps1' 'nález jmenuje i deklarovaný řádek, se kterým se liší'

    # NEGATIVNÍ, case-sensitivní komparátor (-cne) potřebuje vlastní případ:
    # dvě hodnoty lišící se JEN velikostí písmen musí být vyhodnoceny jako
    # rozdílné, protože srovnání je textové, ne sémantické.
    Write-Host "== verification-set: rozdíl jen ve velikosti písmen je taky blokující (textové, ne sémantické srovnání)"
    $r = Test-UmsHandoffGate -RepoRoot $f.Clone -Sha $f.MergedSha -BaseRef $f.BaseRef `
        -VerificationSet @('pwsh ./Build.ps1') -CitedCommands @('pwsh ./build.ps1')
    Assert-True (-not $r.Ok) 'rozdíl jen ve velikosti písmen blokuje'
    Assert-Eq ($r.Blocking -join ',') 'verification-set' 'case-rozdíl blokuje POUZE kontrolu verification-set'

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

    # NEGATIVNÍ: ACTIVE pin zapsaný starým jménem pole. Kontrakt
    # („`context.md` Schema & Writers") čtenářům přikazuje `- **Proposal:**`
    # přijímat jako alias `- **Work item:**`; bez toho brána pustí nesklizenou
    # práci ze starého context.md rovnou do integračního pushe.
    Write-Host "== ACTIVE pin starým jménem pole (Proposal): blokuje jen kontrola contextu"
    $r = Test-UmsHandoffGate -RepoRoot $f.Clone -Sha $f.LegacyActiveSha -BaseRef $f.BaseRef
    Assert-Eq ($r.Blocking -join ',') 'active-pin' 'legacy alias Proposal je ACTIVE stejně jako Work item'

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

    # NEGATIVNÍ: selhaný `git fetch` je fail-closed a hlásí se pod vlastním
    # blokujícím jménem `fetch-failed`, ne jako `ancestor` (proč: hlavička
    # Test-UmsHandoffGate.ps1).
    Write-Host "== nedosažitelný origin: blokuje vlastní jméno fetch-failed"
    $deadUrl = Join-Path $f.Root 'origin-neexistuje.git'
    Set-GateOriginUrl $f $deadUrl
    try {
        $r = Test-UmsHandoffGate -RepoRoot $f.Clone -Sha $f.MergedSha -BaseRef $f.BaseRef
        Assert-True (-not $r.Ok) 'selhaný fetch je STOP (fail-closed)'
        Assert-Eq ($r.Blocking -join ',') 'fetch-failed' 'selhaný fetch má vlastní jméno fetch-failed, ne ancestor'
        $fetchDetail = "$(@($r.Checks | Where-Object { $_.Name -eq 'fetch-failed' } |
                ForEach-Object { $_.Detail }) -join ' ')"
        Assert-Match $fetchDetail 'fetch' 'nález selhaného fetche nese chybu gitu'
    }
    finally {
        Set-GateOriginUrl $f $f.Origin
    }
}
finally {
    Remove-GateFixture $f
}
Complete-Tests
