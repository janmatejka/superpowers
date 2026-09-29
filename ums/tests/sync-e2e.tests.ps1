Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '_assert.ps1')
$ErrorActionPreference = 'Stop'

# Telo syncu end-to-end (design 3.1-3.6): vychozi smer ToMonorepo, drift STOP
# (exit 3), -Force, -WhatIf (nic nezapise), vanilla faze (exit 4), FromMonorepo
# bez vendorovanych skillu, varovani o zaruce a castecne selhani (exit 5).
# Beh skriptu je PROCES nad fixturou v OS temp (kopie skriptu ve fixture forku);
# zive monorepo, tento repozitar ani profil uzivatele se jí netykaji. Pripad (1)
# vola skript BEZ parametru: vychozi koren monorepa se presmeruje promennou
# prostredi UMS_SYNC_MONOREPO_ROOT na fixturu a pred behem se overi dot-sourcem,
# ze default opravdu miri na fixturu - jinak se beh preskoci (nikdy D:\_datasys\ums).
. (Join-Path $PSScriptRoot '..\sync-with-monorepo.ps1') -DotSourceOnly
. (Join-Path $PSScriptRoot 'new-sync-fixture.ps1')

$pwshExe = (Get-Process -Id $PID).Path

function Invoke-Sync($Fixture, [string[]] $SyncArgs) {
    $script = Join-Path $Fixture.ForkUms 'sync-with-monorepo.ps1'
    $out = & $pwshExe -NoProfile -NonInteractive -File $script @SyncArgs 2>&1 | ForEach-Object { "$_" } | Out-String
    return [pscustomobject]@{ Code = $LASTEXITCODE; Output = $out }
}
# One string describing every file of a working tree (path + SHA-256), .git excluded.
function Get-TreeState([string] $Dir) {
    $gitDir = [IO.Path]::GetFullPath((Join-Path $Dir '.git')) + [IO.Path]::DirectorySeparatorChar
    $rows = @(Get-ChildItem -LiteralPath $Dir -Recurse -File -Force |
        Where-Object { -not $_.FullName.StartsWith($gitDir, [StringComparison]::OrdinalIgnoreCase) } |
        ForEach-Object { [IO.Path]::GetRelativePath($Dir, $_.FullName) + '=' + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash })
    $arr = [string[]]$rows
    [Array]::Sort($arr, [StringComparer]::Ordinal)
    return ($arr -join "`n")
}
function Get-MonoManifest($Fixture, [string] $Key = 'claude-Monorepo') { return (Join-Path $Fixture.Mono ".git\ums-sync-manifest-$Key.json") }
function Read-Text([string] $Path) { return [IO.File]::ReadAllText($Path) }
function Add-Text([string] $Path, [string] $Line) { [IO.File]::AppendAllText($Path, "$Line`n", [Text.UTF8Encoding]::new($false)) }
function Count-Matches([string] $Text, [string] $Pattern) { return [regex]::Matches($Text, $Pattern).Count }
function Show-OnFail($r, [int] $Want) { if ($r.Code -ne $Want) { Write-Host $r.Output } }
# Retag the fixture monorepo's pin to t2 (as if the vanilla sync were already committed).
function Set-MonoAtT2($Fixture) {
    $pin = Join-Path $Fixture.Mono '.claude\skills\shared\VENDORED_FROM.md'
    Write-FxFile $pin (New-SyncFixturePin 't2' $Fixture.T2Commit @('alpha', 'gamma', 'subagent-driven-development'))
    Invoke-FxGit $Fixture.Mono @('add', '-A') | Out-Null
    Invoke-FxGit $Fixture.Mono @('commit', '-q', '-m', 'pin at t2') | Out-Null
}

$warnCursor = [regex]::Escape("the pre-push guarantee does not bind 'cursor' (no documented environment-injection mechanism)")
$fxA = $null; $fxB = $null; $fxC = $null; $fxD = $null
$envBefore = $env:UMS_SYNC_MONOREPO_ROOT
try {
    # --- data: kdo je kryty bez markeru (Pi) a koho zaruka neváže -------------------
    # Guarded accessor: a missing field must fail the assertion, not kill the suite.
    function Get-Guarantee([string] $A, [string] $S) {
        $p = (@(Get-UmsSyncTargets -Agent $A -Scope $S -Root 'C:\r'))[0].PSObject.Properties['Guarantee']
        if ($null -eq $p) { return '<missing>' } else { return [string]$p.Value }
    }
    Assert-Eq (Get-Guarantee pi Monorepo) 'ai-agent-fallback' '(data) pi: kryty fallbackem AI_AGENT (ne varovani)'
    Assert-Eq (Get-Guarantee cursor Monorepo) 'none' '(data) cursor: zaruka neváže'
    Assert-Eq (Get-Guarantee codex Monorepo) 'marker' '(data) codex: marker'
    Assert-Eq (Get-Guarantee hermes Monorepo) 'none' '(data) hermes v projektu: zaruka neváže (mechanismus jen v profilu)'
    Assert-Eq (Get-Guarantee hermes UserProfile) 'marker' '(data) hermes v profilu: marker'

    # ============ fixtura A: monorepo na t1, fork na t2 (pripad 6, pak 4 a -WhatIf) ============
    $fxA = New-SyncFixture
    $monoA = $fxA.Mono
    $skA = Join-Path $monoA '.claude\skills'
    $claudeMdA = Read-Text (Join-Path $monoA 'CLAUDE.md')

    # (6) zmena tagu u trackovaneho cile: jen vanilla faze, exit 4
    $r = Invoke-Sync $fxA @('-MonorepoRoot', $monoA)
    Assert-Eq $r.Code 4 '(6) cil t1, fork t2: exit 4'; Show-OnFail $r 4
    Assert-Match $r.Output 'vanilla sync' '(6) vypis vybidne commitnout "vanilla sync"'
    Assert-Match $r.Output 'run (this script )?again' '(6) vypis vybidne spustit znovu'
    Assert-Eq (Read-Text (Join-Path $skA 'alpha\SKILL.md')) "# Alpha`nline two`n" '(6) alpha je pristine t2 (bez overlaye)'
    Assert-True (Test-Path -LiteralPath (Join-Path $skA 'gamma\SKILL.md')) '(6) gamma z t2 je v cili'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $skA 'beta'))) '(6) beta (v t2 pryc) z cile zmizela'
    Assert-Match (Read-Text (Join-Path $skA 'shared\VENDORED_FROM.md')) '(?m)^- Tag: t2' '(6) pin cile je t2'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $skA 'mb-demo'))) '(6) NIC dalsiho: mb-demo nezrcadlen'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $skA 'shared\UMS_MEMORY_BANK_CONTRACT.md'))) '(6) NIC dalsiho: shared nezrcadlen'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $monoA '.claude\hooks'))) '(6) NIC dalsiho: hooky nezrcadleny'
    Assert-Eq (Read-Text (Join-Path $monoA 'CLAUDE.md')) $claudeMdA '(6) NIC dalsiho: CLAUDE.md beze zmeny'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $monoA '.git\hooks\pre-push'))) '(6) NIC dalsiho: pre-push neinstalovan'
    $st = (& git -C $monoA status --porcelain) -join "`n"
    Assert-True ($st -notmatch 'mb-demo|hooks|CLAUDE\.md|UMS_MEMORY') '(6) git status cile nese jen vendorovane skilly'

    # commit "vanilla sync" v cili, druhy beh: overlaye a cela vrstva
    Invoke-FxGit $monoA @('add', '-A') | Out-Null
    Invoke-FxGit $monoA @('commit', '-q', '-m', 'vanilla sync') | Out-Null
    $r = Invoke-Sync $fxA @('-MonorepoRoot', $monoA)
    Assert-Eq $r.Code 0 '(6) druhy beh po commitu: exit 0'; Show-OnFail $r 0
    $alphaA = Read-Text (Join-Path $skA 'alpha\SKILL.md')
    Assert-Eq (Count-Matches $alphaA 'UMS-OVERLAY BEGIN') 2 '(6) druhy beh: overlay bloky (telo + ukazatel) v alpha'
    Assert-True (Test-Path -LiteralPath (Join-Path $skA 'mb-demo\SKILL.md')) '(6) druhy beh: mb-demo nasazen'
    Assert-True (Test-Path -LiteralPath (Join-Path $skA 'shared\UMS_MEMORY_BANK_CONTRACT.md')) '(6) druhy beh: shared nasazen'
    Assert-True (Test-Path -LiteralPath (Join-Path $monoA '.claude\hooks\pre-push')) '(6) druhy beh: hooky nasazeny'
    Assert-True (Test-Path -LiteralPath (Join-Path $monoA '.claude\scripts\revendor-superpowers.ps1')) '(6) druhy beh: scripts nasazeny'
    $cmdA = Read-Text (Join-Path $monoA 'CLAUDE.md')
    Assert-Match $cmdA 'UMS-MEMORY-BANK BEGIN' '(6) druhy beh: CLAUDE.md nese blok UMS'
    Assert-Match $cmdA '# monorepo CLAUDE\.md' '(6) druhy beh: projektovy obsah CLAUDE.md zustal'
    Assert-True (Test-Path -LiteralPath (Join-Path $monoA '.git\hooks\pre-push')) '(6) druhy beh: pre-push nainstalovan'
    Assert-True (Test-Path -LiteralPath (Get-MonoManifest $fxA)) '(6) druhy beh: manifest zapsan'
    $mA = Read-UmsManifest (Get-MonoManifest $fxA)
    Assert-True ($mA.Files.ContainsKey('.claude\skills\alpha\SKILL.md')) '(6) manifest pokryva vendorovane skilly'
    Assert-True ($mA.Files.ContainsKey('.claude\skills\mb-demo\SKILL.md')) '(6) manifest pokryva UMS polozky'
    Assert-True ($mA.Files.ContainsKey('CLAUDE.md#ums-block')) '(6) manifest pokryva blok instrukci'
    Assert-Eq $mA.Files['.claude\skills\alpha\SKILL.md'] (Get-UmsTreeHashes $monoA @('.claude\skills\alpha\SKILL.md'))['.claude\skills\alpha\SKILL.md'] '(6) manifest nese hash CILE po nasazeni'

    # (4) rucni zmena v cili po nasazeni: exit 3, vypis souboru, cil nezmenen
    $mbA = Join-Path $skA 'mb-demo\SKILL.md'
    Add-Text $mbA 'hand edit in the target'
    Add-Text (Join-Path $skA 'alpha\SKILL.md') 'hand edit of a vendored skill'
    $treeA = Get-TreeState $monoA
    $manA = Read-Text (Get-MonoManifest $fxA)
    $r = Invoke-Sync $fxA @('-MonorepoRoot', $monoA)
    Assert-Eq $r.Code 3 '(4) rucni zmena v cili: exit 3'; Show-OnFail $r 3
    Assert-Match $r.Output ([regex]::Escape('.claude\skills\mb-demo\SKILL.md')) '(4) vypis jmenuje zmeneny UMS soubor'
    Assert-Match $r.Output ([regex]::Escape('.claude\skills\alpha\SKILL.md')) '(4) vypis jmenuje zmeneny vendorovany soubor (manifest je pokryva)'
    Assert-Match $r.Output 'FromMonorepo' '(4) nabidka -Direction FromMonorepo'
    Assert-Match $r.Output '-Force' '(4) nabidka -Force'
    Assert-Eq (Get-TreeState $monoA) $treeA '(4) cil nezmenen'
    Assert-Eq (Read-Text (Get-MonoManifest $fxA)) $manA '(4) manifest nezmenen'

    # (5) -WhatIf s driftem: nic nezapise, exit 0, drift vypsan
    $r = Invoke-Sync $fxA @('-MonorepoRoot', $monoA, '-WhatIf')
    Assert-Eq $r.Code 0 '(5) -WhatIf s driftem: exit 0'; Show-OnFail $r 0
    Assert-Match $r.Output ([regex]::Escape('.claude\skills\mb-demo\SKILL.md')) '(5) -WhatIf vypise drift'
    Assert-Match $r.Output '(?i)would' '(5) -WhatIf vypise, co by zapsal'
    Assert-Eq (Get-TreeState $monoA) $treeA '(5) -WhatIf: hash stromu cile pred/po shodny'
    Assert-Eq (Read-Text (Get-MonoManifest $fxA)) $manA '(5) -WhatIf: manifest nezmenen'

    # -Force prepise drift a obnovi manifest; pak -WhatIf bez driftu: exit 0, nic nezapise
    $r = Invoke-Sync $fxA @('-MonorepoRoot', $monoA, '-Force')
    Assert-Eq $r.Code 0 '(4) -Force po driftu: exit 0'; Show-OnFail $r 0
    Assert-True ((Read-Text $mbA) -notmatch 'hand edit') '(4) -Force: mb-demo vracen na obsah forku'
    Assert-Eq (Count-Matches (Read-Text (Join-Path $skA 'alpha\SKILL.md')) 'UMS-OVERLAY BEGIN') 2 '(4) -Force: alpha znovu vendorovana s overlayi'
    Assert-True ((Read-Text (Join-Path $skA 'alpha\SKILL.md')) -notmatch 'hand edit') '(4) -Force: rucni uprava vendorovaneho skillu prepsana'
    $treeA2 = Get-TreeState $monoA
    $manA2 = Read-Text (Get-MonoManifest $fxA)
    $r = Invoke-Sync $fxA @('-MonorepoRoot', $monoA, '-WhatIf')
    Assert-Eq $r.Code 0 '(5) -WhatIf bez driftu: exit 0'; Show-OnFail $r 0
    Assert-Eq (Get-TreeState $monoA) $treeA2 '(5) -WhatIf bez driftu: strom cile beze zmeny'
    Assert-Eq (Read-Text (Get-MonoManifest $fxA)) $manA2 '(5) -WhatIf bez driftu: manifest beze zmeny'
    $r = Invoke-Sync $fxA @('-MonorepoRoot', $monoA)
    Assert-Eq $r.Code 0 '(4) opakovany beh bez zmen: exit 0 (zadny falesny drift)'; Show-OnFail $r 0
    Remove-SyncFixture $fxA; $fxA = $null

    # ============ fixtura B: monorepo uz na t2 (pripady 2, 3, 5, 7, 1) ============
    $fxB = New-SyncFixture
    $monoB = $fxB.Mono
    $skB = Join-Path $monoB '.claude\skills'
    Set-MonoAtT2 $fxB
    [IO.File]::WriteAllText((Join-Path $monoB '.claude\settings.json'), "{ `"mine`": true }`n")

    # (2) prvni beh bez manifestu s rozdilem: exit 3, vypis souboru, cil nezmenen
    $treeB = Get-TreeState $monoB
    $r = Invoke-Sync $fxB @('-MonorepoRoot', $monoB)
    Assert-Eq $r.Code 3 '(2) prvni beh s rozdilem: exit 3'; Show-OnFail $r 3
    Assert-Match $r.Output ([regex]::Escape('.claude\settings.json')) '(2) vypis jmenuje rozdilny soubor'
    Assert-Match $r.Output '(?i)no deployment manifest' '(2) vypis rika, ze manifest chybi (prvni beh)'
    Assert-Eq (Get-TreeState $monoB) $treeB '(2) cil nezmenen'
    Assert-True (-not (Test-Path -LiteralPath (Get-MonoManifest $fxB))) '(2) manifest nevznikl'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $monoB '.git\hooks\pre-push'))) '(2) pre-push neinstalovan'

    # poskozeny manifest: STOP netvrdi "prvni beh", jmenuje cestu
    $manB = Get-MonoManifest $fxB
    [IO.File]::WriteAllText($manB, '{ not json')
    $r = Invoke-Sync $fxB @('-MonorepoRoot', $monoB)
    Assert-Eq $r.Code 3 '(2) poskozeny manifest: exit 3'; Show-OnFail $r 3
    Assert-Match $r.Output '(?i)corrupt' '(2) poskozeny manifest je nazvan poskozenym'
    Assert-Match $r.Output ([regex]::Escape($manB)) '(2) poskozeny manifest: vypis jmenuje jeho cestu'
    Assert-True ($r.Output -notmatch '(?i)no deployment manifest') '(2) poskozeny manifest netvrdi, ze manifest chybi'
    Remove-Item -LiteralPath $manB

    # (5) -WhatIf s driftem bez manifestu: nic nezapise, exit 0
    $r = Invoke-Sync $fxB @('-MonorepoRoot', $monoB, '-WhatIf')
    Assert-Eq $r.Code 0 '(5) -WhatIf, prvni beh s driftem: exit 0'; Show-OnFail $r 0
    Assert-Match $r.Output ([regex]::Escape('.claude\settings.json')) '(5) -WhatIf vypise drift prvniho behu'
    Assert-Eq (Get-TreeState $monoB) $treeB '(5) -WhatIf: hash stromu cile pred/po shodny'
    Assert-True (-not (Test-Path -LiteralPath $manB)) '(5) -WhatIf: zadny manifest'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $monoB '.git\hooks\pre-push'))) '(5) -WhatIf: zadny hook'

    # (3) totez s -Force: exit 0, manifest vznikl
    $r = Invoke-Sync $fxB @('-MonorepoRoot', $monoB, '-Force')
    Assert-Eq $r.Code 0 '(3) -Force: exit 0'; Show-OnFail $r 0
    Assert-True (Test-Path -LiteralPath $manB) '(3) -Force: manifest vznikl'
    Assert-Eq (Read-Text (Join-Path $monoB '.claude\settings.json')) "{}`n" '(3) -Force: settings.json z forku'
    Assert-Eq (Count-Matches (Read-Text (Join-Path $skB 'alpha\SKILL.md')) 'UMS-OVERLAY BEGIN') 2 '(3) -Force: stejny tag -> jeden pruchod vcetne overlayu'
    Assert-True (Test-Path -LiteralPath (Join-Path $monoB '.git\hooks\pre-push')) '(3) -Force: pre-push nainstalovan'

    # (7) FromMonorepo: UMS polozky a blok zpet do forku, vendorovane skilly nikdy
    $forkSkillsB = Join-Path $fxB.ForkUms '.claude\skills'
    $forkPinB = Join-Path $forkSkillsB 'shared\VENDORED_FROM.md'
    $forkPinBytes = Get-FileHash -LiteralPath $forkPinB -Algorithm SHA256
    $monoMdB = Join-Path $monoB 'CLAUDE.md'
    [IO.File]::WriteAllText($monoMdB, (Read-Text $monoMdB).Replace('Fixture sample block.', 'Fixture sample block (edited in the monorepo).'))
    Add-Text (Join-Path $skB 'mb-demo\SKILL.md') 'monorepo edit'
    $r = Invoke-Sync $fxB @('-MonorepoRoot', $monoB, '-Direction', 'FromMonorepo')
    Assert-Eq $r.Code 0 '(7) FromMonorepo: exit 0'; Show-OnFail $r 0
    foreach ($s in 'alpha', 'gamma', 'subagent-driven-development') {
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $forkSkillsB $s))) "(7) FromMonorepo nepreneslo vendorovany '$s' do ums/.claude/skills"
    }
    Assert-Match (Read-Text (Join-Path $forkSkillsB 'mb-demo\SKILL.md')) 'monorepo edit' '(7) FromMonorepo prenese UMS polozku'
    $sampleB = Read-Text (Join-Path $fxB.ForkUms 'CLAUDE.md.sample')
    Assert-Match $sampleB 'edited in the monorepo' '(7) FromMonorepo: sample = obsah bloku z CLAUDE.md'
    Assert-True ($sampleB -notmatch 'UMS-MEMORY-BANK|# monorepo CLAUDE') '(7) sample nenese markery ani projektovy obsah'
    Assert-Eq (Get-FileHash -LiteralPath $forkPinB -Algorithm SHA256).Hash $forkPinBytes.Hash '(7) pin forku zustal (fork je master verze)'
    $r = Invoke-Sync $fxB @('-MonorepoRoot', $monoB)
    Assert-Eq $r.Code 0 '(7) ToMonorepo po FromMonorepo: exit 0 (manifest obnoven, zadny drift)'; Show-OnFail $r 0

    # (1) bez parametru v neinteraktivnim procesu = ToMonorepo
    $forkMbB = Join-Path $forkSkillsB 'mb-demo\SKILL.md'
    Add-Text $forkMbB 'fork edit (case 1)'
    $env:UMS_SYNC_MONOREPO_ROOT = $monoB
    $scriptB = Join-Path $fxB.ForkUms 'sync-with-monorepo.ps1'
    $defaultRoot = & { . $scriptB -DotSourceOnly; $MonorepoRoot }
    Assert-Eq $defaultRoot $monoB '(1) pojistka: vychozi -MonorepoRoot miri na fixturu (UMS_SYNC_MONOREPO_ROOT)'
    if ($defaultRoot -eq $monoB) {
        $out = & $pwshExe -NoProfile -NonInteractive -File $scriptB 2>&1 | ForEach-Object { "$_" } | Out-String
        $code = $LASTEXITCODE
        Assert-Eq $code 0 '(1) bez parametru: exit 0'; if ($code -ne 0) { Write-Host $out }
        Assert-Match $out 'Direction=ToMonorepo' '(1) bez parametru: vypsany smer je ToMonorepo'
        Assert-True ($out -notmatch 'interactive setup') '(1) neinteraktivni proces: zadna nabidka'
        Assert-Match (Read-Text (Join-Path $skB 'mb-demo\SKILL.md')) 'fork edit \(case 1\)' '(1) zmena forku dorazila do monorepa (fork -> monorepo)'
        Assert-Match (Read-Text $forkMbB) 'fork edit \(case 1\)' '(1) fork zustal (nic se netahalo zpet)'
    }
    else { Write-Host '  SKIP: (1) parameter-free run skipped - the default monorepo root did not resolve to the fixture' }
    $env:UMS_SYNC_MONOREPO_ROOT = $envBefore
    Remove-SyncFixture $fxB; $fxB = $null

    # ============ fixtura C: harnessy bez markeru, sdileny adresar, Fork -WhatIf (pripad 8) ============
    $fxC = New-SyncFixture
    $monoC = $fxC.Mono
    $r = Invoke-Sync $fxC @('-MonorepoRoot', $monoC, '-Agent', 'cursor,pi')
    Assert-Eq $r.Code 0 '(8) -Agent cursor,pi: exit 0'; Show-OnFail $r 0
    Assert-Match $r.Output $warnCursor '(8) cursor: varovani o zaruce'
    Assert-True ($r.Output -notmatch "does not bind 'pi'") '(8) pi: bez varovani (kryje AI_AGENT fallback)'
    Assert-Match $r.Output 'AI_AGENT' '(8) pi: poznamka o fallbacku AI_AGENT'
    Assert-Eq (Count-Matches $r.Output 'vendoring \(full\)') 1 '(8) sdileny .agents/skills se vendoruje jednou'
    Assert-Eq (Count-Matches (Read-Text (Join-Path $monoC 'AGENTS.md')) 'UMS-MEMORY-BANK BEGIN') 1 '(8) sdileny AGENTS.md nese blok jednou'
    Assert-True (Test-Path -LiteralPath (Join-Path $monoC '.agents\skills\alpha\SKILL.md')) '(8) vendorovane skilly v .agents/skills'
    Assert-True (Test-Path -LiteralPath (Join-Path $monoC '.git\ums-sync-manifest-cursor-Monorepo.json')) '(8) manifest cursor'
    Assert-True (Test-Path -LiteralPath (Join-Path $monoC '.git\ums-sync-manifest-pi-Monorepo.json')) '(8) manifest pi'

    # Fork -WhatIf: nic do korene forku, zadny radek v exclude, zadny hook
    $forkC = $fxC.Fork
    $exclFile = Join-Path $forkC '.git\info\exclude'
    $exclBefore = if (Test-Path -LiteralPath $exclFile) { Read-Text $exclFile } else { '' }
    $treeFork = Get-TreeState $forkC
    $r = Invoke-Sync $fxC @('-Scope', 'Fork', '-Agent', 'claude,codex', '-WhatIf')
    Assert-Eq $r.Code 0 '(5) Fork -WhatIf: exit 0'; Show-OnFail $r 0
    Assert-Eq (Get-TreeState $forkC) $treeFork '(5) Fork -WhatIf: strom forku beze zmeny'
    $exclAfter = if (Test-Path -LiteralPath $exclFile) { Read-Text $exclFile } else { '' }
    Assert-Eq $exclAfter $exclBefore '(5) Fork -WhatIf: .git/info/exclude beze zmeny'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $forkC '.git\hooks\pre-push'))) '(5) Fork -WhatIf: zadny hook'
    Assert-Match $r.Output '/\.agents/skills/' '(5) Fork -WhatIf vypise radek exclude, ktery by zapsal'

    # FromMonorepo mimo claude+Monorepo: chyba, nic se nezapise
    $treeMonoC = Get-TreeState $monoC
    $r = Invoke-Sync $fxC @('-MonorepoRoot', $monoC, '-Agent', 'codex', '-Direction', 'FromMonorepo')
    Assert-True ($r.Code -ne 0 -and $r.Code -ne 3 -and $r.Code -ne 4) '(7) FromMonorepo pro codex: chyba (jen claude+Monorepo)'
    Assert-Match $r.Output 'FromMonorepo' '(7) chyba jmenuje FromMonorepo'
    Assert-Eq (Get-TreeState $monoC) $treeMonoC '(7) FromMonorepo pro codex: cil nezmenen'
    Remove-SyncFixture $fxC; $fxC = $null

    # ============ fixtura D: castecne selhani markeru neprerusi beh (exit 5) ============
    $fxD = New-SyncFixture
    $prof = Join-Path $fxD.Root 'profile'
    Write-FxFile (Join-Path $prof '.hermes\config.yaml') "terminal: { backend: local }`n"
    $r = Invoke-Sync $fxD @('-Scope', 'UserProfile', '-UserProfileRoot', $prof, '-Agent', 'hermes,codex')
    Assert-Eq $r.Code 5 '(partial) chyba zapisovace markeru hermes: exit 5'; Show-OnFail $r 5
    Assert-Match $r.Output 'hermes' '(partial) souhrn jmenuje hermes'
    Assert-Match $r.Output '(?i)partial' '(partial) souhrn hlasi castecny stav'
    Assert-Match (Read-Text (Join-Path $prof '.codex\config.toml')) 'MB_AGENT_SESSION' '(partial) codex marker zapsan i po chybe hermes (beh pokracoval)'
    Assert-Eq (Read-Text (Join-Path $prof '.hermes\config.yaml')) "terminal: { backend: local }`n" '(partial) config.yaml hermes nedotcen'
    Assert-True (Test-Path -LiteralPath (Join-Path $prof '.codex\AGENTS.md')) '(partial) codex dostal blok instrukci'
    Assert-True (Test-Path -LiteralPath (Join-Path $prof '.ums-sync-manifest-codex-UserProfile.json')) '(partial) manifest mimo git lezi v koreni cile'
}
finally {
    $env:UMS_SYNC_MONOREPO_ROOT = $envBefore
    foreach ($fx in $fxA, $fxB, $fxC, $fxD) { if ($fx) { Remove-SyncFixture $fx } }
}

Complete-Tests
