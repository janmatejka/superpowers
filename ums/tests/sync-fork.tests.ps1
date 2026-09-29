Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '_assert.ps1')
$ErrorActionPreference = 'Stop'

# -Scope Fork (design 3.5): nasazeni vrstvy do korene forku bez spineni stromu.
# Sada stavi fixturu (fork + monorepo) vyhradne v OS temp; skutecny fork ani
# zive monorepo ani profil se jí netykaji. Beh skriptu je PROCES nad fixturou
# (pwsh -File .../sync-with-monorepo.ps1 -Scope Fork ...), protoze hlavni telo
# skriptu jde spustit jen jako skript.
. (Join-Path $PSScriptRoot '..\sync-with-monorepo.ps1') -DotSourceOnly
. (Join-Path $PSScriptRoot 'new-sync-fixture.ps1')

$pwshExe = (Get-Process -Id $PID).Path

function Invoke-ForkSync($Fixture, [string[]] $SyncArgs) {
    $script = Join-Path $Fixture.ForkUms 'sync-with-monorepo.ps1'
    $out = & $pwshExe -NoProfile -File $script @SyncArgs 2>&1 | ForEach-Object { "$_" } | Out-String
    return [pscustomobject]@{ Code = $LASTEXITCODE; Output = $out }
}
function Get-Porcelain([string] $Repo) { return ((& git -C $Repo status --porcelain 2>&1 | Out-String).Trim()) }
function Get-FileSha([string] $Path) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }
function Read-Lines([string] $Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    return @([IO.File]::ReadAllText($Path) -split '\r?\n' | Where-Object { $_ -ne '' })
}
function Get-PinTagIn([string] $SkillsRoot) {
    $m = [regex]::Match([IO.File]::ReadAllText((Join-Path $SkillsRoot 'shared\VENDORED_FROM.md')), '(?m)^- Tag:\s*(\S+)')
    return $m.Groups[1].Value
}

$fxA = $null; $fxB = $null; $fxC = $null
try {
    # --- ConvertTo-UmsAgentList: -Agent je seznam a kazda hodnota se deli carkami ----
    # (pwsh -File ... -Agent claude,codex dorucí JEDEN retezec 'claude,codex').
    Assert-Eq (@(ConvertTo-UmsAgentList @('claude,codex')) -join '|') 'claude|codex' '(agenti) jeden retezec s carkou se rozdeli'
    Assert-Eq (@(ConvertTo-UmsAgentList @('claude', 'codex')) -join '|') 'claude|codex' '(agenti) pole zustane polem'
    Assert-Eq (@(ConvertTo-UmsAgentList @(' claude , codex ,, gemini')) -join '|') 'claude|codex|gemini' '(agenti) mezery a prazdne prvky se zahodi'
    Assert-Eq (@(ConvertTo-UmsAgentList @('claude', 'codex,claude', 'CODEX')) -join '|') 'claude|codex' '(agenti) duplicity (i jiná velikost písmen) se zapíší jednou, pořadí prvního výskytu'
    Assert-Eq (@(ConvertTo-UmsAgentList @('Claude')) -join '|') 'claude' '(agenti) jméno se převede na malá písmena'
    Assert-Eq @(ConvertTo-UmsAgentList @()).Count 0 '(agenti) prázdný vstup dá prázdný seznam'

    # --- Add-UmsGitExclude / Get-UmsForkExcludes nad fixturou ----------------------
    $fxA = New-SyncFixture
    $repo = $fxA.Fork
    $excl = Join-Path $repo '.git\info\exclude'
    $before = @(Read-Lines $excl)

    $added1 = @(Add-UmsGitExclude $repo @('/.agents/skills/', '/.qwen/skills/'))
    Assert-Eq ($added1 -join '|') '/.agents/skills/|/.qwen/skills/' '(exclude) první volání vrátí přidané řádky'
    $added2 = @(Add-UmsGitExclude $repo @('/.agents/skills/', '/.qwen/skills/'))
    Assert-Eq $added2.Count 0 '(exclude) druhé volání nepřidá nic'
    $lines = @(Read-Lines $excl)
    Assert-Eq @($lines | Where-Object { $_ -ceq '/.agents/skills/' }).Count 1 '(exclude) řádek /.agents/skills/ je v souboru právě jednou'
    Assert-Eq @($lines | Where-Object { $_ -ceq '/.qwen/skills/' }).Count 1 '(exclude) řádek /.qwen/skills/ je v souboru právě jednou'
    Assert-Eq $lines.Count ($before.Count + 2) '(exclude) dosavadní řádky zůstaly, přibyly právě dva'
    $added3 = @(Add-UmsGitExclude $repo @('/.agents/skills/', '/.grok/skills/'))
    Assert-Eq ($added3 -join '|') '/.grok/skills/' '(exclude) smíšený seznam přidá jen chybějící'
    Assert-Eq @(Add-UmsGitExclude $repo @()).Count 0 '(exclude) prázdný seznam vzorů nic nepřidá'

    # Soubor bez koncového newline: přidaný řádek nesmí splynout s posledním.
    $fxA2Excl = Join-Path $repo '.git\info\exclude'
    [IO.File]::WriteAllText($fxA2Excl, "# keep`n/.no-newline-at-end", [Text.UTF8Encoding]::new($false))
    Add-UmsGitExclude $repo @('/.pi/skills/') | Out-Null
    $l2 = @(Read-Lines $fxA2Excl)
    Assert-True (($l2 -ccontains '/.no-newline-at-end') -and ($l2 -ccontains '/.pi/skills/')) '(exclude) soubor bez koncového newline: staré řádky zůstaly celé, nový je samostatný'

    # čistý stav pro Get-UmsForkExcludes: vrať exclude bez řádků, které jsme přidali
    [IO.File]::WriteAllText($fxA2Excl, "# clean`n", [Text.UTF8Encoding]::new($false))
    $need = @(Get-UmsForkExcludes $repo @('.claude', '.claude/skills', '.agents/skills', '.qwen\skills'))
    Assert-Eq ($need -join '|') '/.agents/skills/|/.qwen/skills/' '(excludes) .claude je ignorovaný gitem, .agents/skills a .qwen/skills ne; lomítka se normalizují'
    Add-UmsGitExclude $repo $need | Out-Null
    $need2 = @(Get-UmsForkExcludes $repo @('.claude', '.agents/skills', '.qwen/skills'))
    Assert-Eq $need2.Count 0 '(excludes) po zápisu jsou adresáře ignorované, nic dalšího se nevyžaduje'
    # dosud neexistující adresář se rozhoduje stejně jako existující
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $repo '.agents\skills'))) '(excludes) .agents/skills před nasazením neexistuje'
    Assert-Eq (Get-Porcelain $repo) '' '(excludes) exclude nespinil strom fixtury'
    Remove-SyncFixture $fxA; $fxA = $null

    # --- e2e: proces -Scope Fork -Agent claude,codex -Force nad fixturou --------------
    $fxB = New-SyncFixture
    $fork = $fxB.Fork
    $claudeMdBefore = Get-FileSha (Join-Path $fork 'CLAUDE.md')
    $agentsMdBefore = Get-FileSha (Join-Path $fork 'AGENTS.md')
    Assert-Eq (Get-Porcelain $fork) '' '(fork) výchozí strom fixtury je čistý'

    # Předchozí nasazení na t1 (pin + skill beta, který v t2 zmizel): pin cíle musí přežít
    # zrcadlení shared/, jinak revendor nepozná, že beta z pinu odešla (rozhodnutí R3).
    foreach ($rel in '.agents/skills', '.claude/skills') {
        $sk = Join-Path $fork $rel
        Write-FxFile (Join-Path $sk 'shared/VENDORED_FROM.md') (New-SyncFixturePin 't1' $fxB.T1Commit @('alpha', 'beta', 'subagent-driven-development'))
        Write-FxFile (Join-Path $sk 'beta/SKILL.md') "# beta (deployed at t1)`n"
    }
    $r = Invoke-ForkSync $fxB @('-Scope', 'Fork', '-Agent', 'claude,codex', '-Force')
    Assert-Eq $r.Code 0 '(fork) proces skončil s kódem 0'; if ($r.Code -ne 0) { Write-Host $r.Output }

    Assert-Eq (Get-Porcelain $fork) '' '(fork) git status --porcelain fixtury je po nasazení prázdný'
    Assert-Eq (Get-FileSha (Join-Path $fork 'CLAUDE.md')) $claudeMdBefore '(fork) CLAUDE.md je bajtově beze změny'
    Assert-Eq (Get-FileSha (Join-Path $fork 'AGENTS.md')) $agentsMdBefore '(fork) AGENTS.md je bajtově beze změny'

    $exLines = @(Read-Lines (Join-Path $fork '.git\info\exclude'))
    Assert-Eq @($exLines | Where-Object { $_ -ceq '/.agents/skills/' }).Count 1 '(fork) .git/info/exclude nese /.agents/skills/ právě jednou'
    Assert-Eq @($exLines | Where-Object { $_ -match '\.claude' }).Count 0 '(fork) .claude je ignorovaný gitem, do exclude se nezapisuje'

    $agSkills = Join-Path $fork '.agents\skills'
    $clSkills = Join-Path $fork '.claude\skills'
    Assert-True (Test-Path -LiteralPath (Join-Path $agSkills 'mb-demo\SKILL.md')) '(fork) .agents/skills/mb-demo/SKILL.md existuje'
    Assert-True (Test-Path -LiteralPath (Join-Path $agSkills 'shared\UMS_MEMORY_BANK_CONTRACT.md')) '(fork) .agents/skills/shared nese kontrakt'
    Assert-True (Test-Path -LiteralPath (Join-Path $clSkills 'mb-demo\SKILL.md')) '(fork) .claude/skills/mb-demo/SKILL.md existuje'
    Assert-True (Test-Path -LiteralPath (Join-Path $clSkills 'shared\UMS_MEMORY_BANK_CONTRACT.md')) '(fork) .claude/skills/shared nese kontrakt'
    foreach ($sk in $agSkills, $clSkills) {
        $tag = Split-Path -Leaf (Split-Path -Parent $sk)
        Assert-True (Test-Path -LiteralPath (Join-Path $sk 'alpha\SKILL.md')) "(fork) vendorovaný alpha je v $tag/skills"
        Assert-True (Test-Path -LiteralPath (Join-Path $sk 'gamma\SKILL.md')) "(fork) vendorovaný gamma (nový v t2) je v $tag/skills"
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $sk 'beta'))) "(fork) beta (z předchozího pinu, v t2 pryč) je v $tag/skills odstraněná - pin cíle přežil zrcadlení"
        Assert-Eq (Get-PinTagIn $sk) 't2' "(fork) pin v $tag/skills je po revendoru na t2"
        Assert-Match ([IO.File]::ReadAllText((Join-Path $sk 'alpha\SKILL.md'))) 'UMS-OVERLAY BEGIN' "(fork) alpha v $tag/skills nese overlay blok z nasazeného shared/overlays"
    }

    # claude: stejná sada UMS položek jako claude+Monorepo
    Assert-True (Test-Path -LiteralPath (Join-Path $fork '.claude\settings.json')) '(fork) .claude/settings.json nasazen'
    Assert-True (Test-Path -LiteralPath (Join-Path $fork '.claude\hooks\install-git-hooks.ps1')) '(fork) .claude/hooks nasazeny'
    Assert-True (Test-Path -LiteralPath (Join-Path $fork '.claude\hooks\pre-push')) '(fork) .claude/hooks/pre-push nasazen'
    Assert-True (Test-Path -LiteralPath (Join-Path $fork '.claude\scripts\revendor-superpowers.ps1')) '(fork) .claude/scripts/revendor-superpowers.ps1 nasazen'
    # ostatní harnessy: jen skilly - žádné lepidlo ani marker do konfiguračního adresáře, žádné instrukce
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $fork '.codex'))) '(fork) codex: žádný .codex (lepidlo ani marker se do kořene forku nepíše)'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $agSkills '..\hooks'))) '(fork) codex: žádné hooks vedle .agents/skills'

    # pre-push je nainstalovaný a ověřený (skutečný instalátor, ne stub)
    $hook = Join-Path $fork '.git\hooks\pre-push'
    Assert-True (Test-Path -LiteralPath $hook) '(fork) .git/hooks/pre-push je nainstalovaný'
    Assert-True ($r.Output -notmatch 'install-git-hooks\.ps1 exited with') '(fork) instalátor hooků nehlásí nenulový exit'

    # opakovaný běh: idempotentní, strom dál čistý
    $r2 = Invoke-ForkSync $fxB @('-Scope', 'Fork', '-Agent', 'claude,codex', '-Force')
    Assert-Eq $r2.Code 0 '(fork) opakovaný běh skončil s kódem 0'; if ($r2.Code -ne 0) { Write-Host $r2.Output }
    Assert-Eq (Get-Porcelain $fork) '' '(fork) po opakovaném běhu je strom dál čistý'
    $exLines2 = @(Read-Lines (Join-Path $fork '.git\info\exclude'))
    Assert-Eq @($exLines2 | Where-Object { $_ -ceq '/.agents/skills/' }).Count 1 '(fork) po opakovaném běhu je řádek v exclude stále jednou'
    Assert-Eq (Get-FileSha (Join-Path $fork 'CLAUDE.md')) $claudeMdBefore '(fork) CLAUDE.md beze změny i po druhém běhu'
    Assert-Eq (Get-FileSha (Join-Path $fork 'AGENTS.md')) $agentsMdBefore '(fork) AGENTS.md beze změny i po druhém běhu'
    Remove-SyncFixture $fxB; $fxB = $null

    # --- neznámý agent selže předem, nic se nezapíše -----------------------------------
    $fxC = New-SyncFixture
    $r3 = Invoke-ForkSync $fxC @('-Scope', 'Fork', '-Agent', 'claude,kilocode', '-Force')
    Assert-True ($r3.Code -ne 0) '(fork) neznámý agent (kilocode): nenulový exit'
    Assert-Match $r3.Output 'kilocode' '(fork) chyba jmenuje neznámého agenta'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $fxC.Fork '.claude'))) '(fork) neznámý agent: do kořene forku se nezapsalo nic'
    Assert-Eq (Get-Porcelain $fxC.Fork) '' '(fork) neznámý agent: strom čistý'

    # --- starý jednoagentní i nový víceagentní běh mimo Fork zůstává funkční ------------
    $prof = Join-Path $fxC.Root 'profile'
    New-Item -ItemType Directory -Force $prof | Out-Null
    $r4 = Invoke-ForkSync $fxC @('-Scope', 'UserProfile', '-Agent', 'codex,gemini', '-UserProfileRoot', $prof)
    Assert-Eq $r4.Code 0 '(profil) -Agent codex,gemini skončil s kódem 0'
    Assert-True (Test-Path -LiteralPath (Join-Path $prof '.agents\skills\mb-demo\SKILL.md')) '(profil) sdílený .agents/skills nasazen'
    Assert-True (Test-Path -LiteralPath (Join-Path $prof '.codex\AGENTS.md')) '(profil) codex dostal blok preferencí'
    Assert-True (Test-Path -LiteralPath (Join-Path $prof '.gemini\GEMINI.md')) '(profil) gemini dostal blok preferencí'
    $r5 = Invoke-ForkSync $fxC @('-Scope', 'UserProfile', '-Agent', 'nesmysl', '-UserProfileRoot', $prof)
    Assert-True ($r5.Code -ne 0) '(profil) neznámý agent: nenulový exit'
}
finally {
    foreach ($fx in $fxA, $fxB, $fxC) { if ($fx) { Remove-SyncFixture $fx } }
}

Complete-Tests
