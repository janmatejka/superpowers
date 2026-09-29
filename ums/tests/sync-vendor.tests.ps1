Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '_assert.ps1')
$ErrorActionPreference = 'Stop'

# Vendorovane skilly v cili (design 3.3): plan (full / vanilla-only / none),
# beh revendoru forku jako proces nad cilem a detekce trackovani gitem. Sada
# stavi fixturu (fork se dvema tagy + monorepo s lokalnim bare originem)
# vyhradne v OS temp; zive monorepo ani tento repozitar se jí netykaji.
. (Join-Path $PSScriptRoot '..\sync-with-monorepo.ps1') -DotSourceOnly
. (Join-Path $PSScriptRoot 'new-sync-fixture.ps1')

$work = Join-Path ([IO.Path]::GetTempPath()) ("ums-sync-vendor-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $work | Out-Null

function Get-AllMd([string] $Dir) {
    return @(Get-ChildItem -LiteralPath $Dir -Recurse -File -Filter '*.md' | ForEach-Object { $_.FullName })
}
function Count-Blocks([string] $SkillsRoot) {
    $n = 0
    foreach ($f in (Get-AllMd $SkillsRoot | Where-Object { $_ -notlike '*\shared\*' })) {
        $n += [regex]::Matches([IO.File]::ReadAllText($f), 'UMS-OVERLAY BEGIN').Count
    }
    return $n
}
function Read-Skill([string] $SkillsRoot, [string] $Rel) { return [IO.File]::ReadAllText((Join-Path $SkillsRoot $Rel)) }
function Get-PinTagOf([string] $SkillsRoot) {
    $m = [regex]::Match([IO.File]::ReadAllText((Join-Path $SkillsRoot 'shared\VENDORED_FROM.md')), '(?m)^- Tag:\s*(\S+)')
    return $m.Groups[1].Value
}

$fxA = $null; $fxB = $null
try {
    # --- Get-UmsVendorPlan: cisté kombinace nad pin soubory --------------------
    $pinT1 = Join-Path $work 'pin-t1.md'; [IO.File]::WriteAllText($pinT1, (New-SyncFixturePin 't1' ('1' * 40) @('alpha')))
    $pinT2 = Join-Path $work 'pin-t2.md'; [IO.File]::WriteAllText($pinT2, (New-SyncFixturePin 't2' ('2' * 40) @('alpha')))
    $pinT2b = Join-Path $work 'pin-t2b.md'; [IO.File]::WriteAllText($pinT2b, (New-SyncFixturePin 't2' ('3' * 40) @('alpha', 'gamma')))
    $pinUp = Join-Path $work 'pin-upper.md'; [IO.File]::WriteAllText($pinUp, (New-SyncFixturePin 'T2' ('2' * 40) @('alpha')))
    $noPin = Join-Path $work 'no-such-pin.md'

    Assert-Eq (Get-UmsVendorPlan $pinT2 $pinT2b $true)  'full'         '(plan) stejný tag, trackovaný cíl: full (shoda je jen v tagu, ne v obsahu pinu)'
    Assert-Eq (Get-UmsVendorPlan $pinT2 $pinT1 $true)   'vanilla-only' '(plan) jiný tag, trackovaný cíl: vanilla-only'
    Assert-Eq (Get-UmsVendorPlan $pinT2 $pinT1 $false)  'full'         '(plan) jiný tag, netrackovaný cíl: full'
    Assert-Eq (Get-UmsVendorPlan $pinT2 $pinT2 $false)  'full'         '(plan) stejný tag, netrackovaný cíl: full'
    Assert-Eq (Get-UmsVendorPlan $pinT2 '' $true)       'none'         '(plan) cíl bez adresáře skillů (prázdný TargetPin), trackovaný: none'
    Assert-Eq (Get-UmsVendorPlan $pinT2 '' $false)      'none'         '(plan) cíl bez adresáře skillů, netrackovaný: none'
    Assert-Eq (Get-UmsVendorPlan $pinT2 $noPin $true)   'full'         '(plan) cíl s adresářem skillů, ale bez pinu (první nasazení), trackovaný: full'
    Assert-Eq (Get-UmsVendorPlan $pinT2 $pinUp $true)   'vanilla-only' '(plan) tagy se liší jen velikostí písmen (T2 vs t2): jiný tag -> vanilla-only'
    $threw = $false
    try { Get-UmsVendorPlan $noPin $pinT1 $true | Out-Null } catch { $threw = $true }
    Assert-True $threw '(plan) pin forku chybí: výjimka, ne tiché full'
    Assert-True ((Get-UmsVendorPlan $pinT2 $pinT1 $true) -is [string]) '(plan) vrací řetězec'

    # --- Test-UmsTracked --------------------------------------------------------
    $fxA = New-SyncFixture
    Assert-True ((Test-UmsTracked $fxA.Mono '.claude/skills/shared/VENDORED_FROM.md') -eq $true) '(tracked) trackovaný soubor: $true'
    Assert-True ((Test-UmsTracked $fxA.Mono '.claude\skills\shared\VENDORED_FROM.md') -eq $true) '(tracked) cesta se zpětnými lomítky: $true'
    Assert-True ((Test-UmsTracked $fxA.Mono '.claude/skills') -eq $true) '(tracked) adresář s trackovanými soubory: $true'
    Set-Content -LiteralPath (Join-Path $fxA.Mono 'untracked.txt') -Value 'x'
    Assert-True ((Test-UmsTracked $fxA.Mono 'untracked.txt') -eq $false) '(tracked) netrackovaný soubor: $false'
    Assert-True ((Test-UmsTracked $fxA.Mono 'nothing-here') -eq $false) '(tracked) neexistující cesta: $false'
    Remove-Item -LiteralPath (Join-Path $fxA.Mono 'untracked.txt')
    $plain = Join-Path $work 'plain'; New-Item -ItemType Directory -Force $plain | Out-Null
    Set-Content -LiteralPath (Join-Path $plain 'a.txt') -Value 'a'
    Assert-True ((Test-UmsTracked $plain 'a.txt') -eq $false) '(tracked) kořen mimo git: $false'
    Assert-True ((Test-UmsTracked $fxA.Mono '.claude/skills/shared/VENDORED_FROM.md') -is [bool]) '(tracked) vrací [bool]'

    # --- fixtura: výchozí stav ------------------------------------------------
    $forkPin = Join-Path $fxA.ForkUms '.claude\skills\shared\VENDORED_FROM.md'
    $monoSkills = Join-Path $fxA.Mono '.claude\skills'
    $monoPin = Join-Path $monoSkills 'shared\VENDORED_FROM.md'
    Assert-Eq (Get-PinTagOf (Join-Path $fxA.ForkUms '.claude\skills')) 't2' '(fixtura) pin forku je na t2'
    Assert-Eq (Get-PinTagOf $monoSkills) 't1' '(fixtura) pin monorepa je na t1'
    Assert-True (Test-Path -LiteralPath (Join-Path $monoSkills 'beta\SKILL.md')) '(fixtura) monorepo nese beta z t1'
    Assert-True (Test-Path -LiteralPath $fxA.MonoBare) '(fixtura) lokální bare origin existuje'
    Assert-Eq (Get-UmsVendorPlan $forkPin $monoPin (Test-UmsTracked $fxA.Mono '.claude/skills/shared/VENDORED_FROM.md')) 'vanilla-only' '(fixtura) fork t2 vs. trackované monorepo t1: plán vanilla-only'

    # --- vanilla-only: jen upstream diff, nic z UMS ------------------------------
    $monoOverlays = Join-Path $monoSkills 'shared\overlays'
    $ovBefore = Get-UmsTreeHashes $monoOverlays @('.')
    $settingsBefore = [IO.File]::ReadAllText((Join-Path $fxA.Mono '.claude\settings.json'))
    Invoke-UmsVendoredDeploy $fxA.ForkUms $monoSkills 'vanilla-only' 6>$null

    Assert-Eq (Get-PinTagOf $monoSkills) 't2' '(vanilla-only) pin cíle přepsán na t2'
    Assert-Eq (Read-Skill $monoSkills 'alpha\SKILL.md') "# Alpha`nline two`n" '(vanilla-only) alpha je pristine t2 (LF, bez overlaye)'
    Assert-True (Test-Path -LiteralPath (Join-Path $monoSkills 'gamma\SKILL.md')) '(vanilla-only) gamma z t2 je v cíli'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $monoSkills 'beta'))) '(vanilla-only) beta, kterou t2 zahodil, z cíle zmizela (cíl má pin t1, revendor vlastní pin nepřepsán forkovým)'
    Assert-True (Test-Path -LiteralPath (Join-Path $monoSkills 'subagent-driven-development\task-reviewer-prompt.md')) '(vanilla-only) sdd z t2 je kompletní'
    Assert-Eq (Count-Blocks $monoSkills) 0 '(vanilla-only) žádný UMS-OVERLAY blok ve vendorovaných skillech'
    $ovAfter = Get-UmsTreeHashes $monoOverlays @('.')
    Assert-Eq $ovAfter.Count $ovBefore.Count '(vanilla-only) shared\overlays cíle: stejný počet souborů'
    $ovSame = $true
    foreach ($k in $ovBefore.Keys) { if (-not $ovAfter.ContainsKey($k) -or $ovAfter[$k] -cne $ovBefore[$k]) { $ovSame = $false } }
    Assert-True ($ovSame -eq $true) '(vanilla-only) shared\overlays cíle se nezměnil (bajtově)'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $monoSkills 'mb-demo'))) '(vanilla-only) NIC dalšího: mb-demo se do cíle nezrcadlil'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $fxA.Mono '.claude\hooks'))) '(vanilla-only) NIC dalšího: hooky se do cíle nezrcadlily'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $monoSkills 'shared\UMS_MEMORY_BANK_CONTRACT.md'))) '(vanilla-only) NIC dalšího: shared se nezrcadlil'
    Assert-Eq ([IO.File]::ReadAllText((Join-Path $fxA.Mono '.claude\settings.json'))) $settingsBefore '(vanilla-only) NIC dalšího: settings.json cíle beze změny'
    $st = (& git -C $fxA.Mono status --porcelain) -join "`n"
    Assert-Match $st '(?m)^ ?[MDA] .*alpha/SKILL\.md' '(vanilla-only) git status cíle ukazuje změnu vendorovaného skillu (co se commitne jako vanilla sync)'
    Assert-True ($st -notmatch 'mb-demo|hooks|settings\.json|overlays') '(vanilla-only) git status cíle nenese nic z UMS'

    # po commitu "vanilla sync" je tag shodný -> druhý běh je full
    Assert-Eq (Get-UmsVendorPlan $forkPin $monoPin $true) 'full' '(dvoufázově) po vanilla fázi má cíl tag forku: další plán je full'

    # --- full: overlaye z NASAZENÝCH fragmentů cíle -------------------------------
    $fragBody = Join-Path $monoOverlays 'alpha.overlay.md'
    $fragText = [IO.File]::ReadAllText($fragBody).Replace('Target-relative link:', 'Target-relative link (TARGET-FRAGMENT-MARK):')
    [IO.File]::WriteAllText($fragBody, $fragText, [Text.UTF8Encoding]::new($false))
    Invoke-UmsVendoredDeploy $fxA.ForkUms $monoSkills 'full' 6>$null
    $alpha = Read-Skill $monoSkills 'alpha\SKILL.md'
    Assert-Eq (Count-Blocks $monoSkills) 2 '(full) dva overlay bloky (tělo + ukazatel) jsou přítomné'
    Assert-Match $alpha 'TARGET-FRAGMENT-MARK' '(full) overlay se bere z fragmentů nasazených v cíli, ne z forku'
    Assert-True ($alpha.IndexOf('UMS pointer:', [StringComparison]::Ordinal) -ge 0 -and
        $alpha.IndexOf('UMS pointer:', [StringComparison]::Ordinal) -lt $alpha.IndexOf('Alpha body block.', [StringComparison]::Ordinal)) '(full) ukazatel stojí před tělem'
    Assert-Eq (Get-PinTagOf $monoSkills) 't2' '(full) pin cíle zůstává t2'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $monoSkills 'beta'))) '(full) beta nevrátila se'

    # --- none: nic se nedělá ---------------------------------------------------------
    $ghost = Join-Path $work 'ghost-skills'
    Invoke-UmsVendoredDeploy $fxA.ForkUms $ghost 'none' 6>$null
    Assert-True (-not (Test-Path -LiteralPath $ghost)) '(none) režim none nevytvoří ani adresář skillů'

    # --- full v jednom průchodu z t1 (netrackovaný cíl): beta zmizí i tady ---------
    $fxB = New-SyncFixture
    $skillsB = Join-Path $fxB.Mono '.claude\skills'
    Invoke-UmsVendoredDeploy $fxB.ForkUms $skillsB 'full' 6>$null
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $skillsB 'beta'))) '(full z t1) beta, kterou t2 zahodil, z cíle zmizela'
    Assert-True (Test-Path -LiteralPath (Join-Path $skillsB 'gamma\SKILL.md')) '(full z t1) gamma přibyla'
    Assert-Eq (Count-Blocks $skillsB) 2 '(full z t1) overlay bloky přítomné'
    Assert-Eq (Get-PinTagOf $skillsB) 't2' '(full z t1) pin cíle je t2'

    # --- selhání revendoru = výjimka s koncem jeho výstupu -------------------------
    $forkPinB = Join-Path $fxB.ForkUms '.claude\skills\shared\VENDORED_FROM.md'
    [IO.File]::WriteAllText($forkPinB, ([IO.File]::ReadAllText($forkPinB) -replace '- Tag: t2', '- Tag: no-such-tag'))
    $msg = ''
    try { Invoke-UmsVendoredDeploy $fxB.ForkUms $skillsB 'full' 6>$null } catch { $msg = $_.Exception.Message }
    Assert-True ($msg -ne '') '(chyba) nenulový exit revendoru je výjimka'
    Assert-Match $msg 'no-such-tag' '(chyba) výjimka nese konec výstupu revendoru (jméno neexistujícího tagu)'
    Assert-Match $msg 'revendor' '(chyba) výjimka říká, že selhal revendor'
}
finally {
    Remove-SyncFixture $fxA
    Remove-SyncFixture $fxB
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Complete-Tests
