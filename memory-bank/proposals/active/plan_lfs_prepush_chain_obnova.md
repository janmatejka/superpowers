# Obnova ztraceného LFS pre-push řetězu — implementační plán

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Instalátor sám obnoví LFS `pre-push` řetěz v klonech, kde ho starší verze přepsala, a nová verze hooku donutí každý klon instalátor po git updatu spustit.

**Architecture:** Tři vrstvy. (1) Sdílený PowerShell helper parsuje verzi z hlavičky hooku, takže konzumenti porovnávají uspořádáním místo rovnosti a literál verze zmizí z jejich těl. (2) `Restore-LfsChainedHook` v instalátoru obnoví řetěz, když jsou splněny podmínky důkazu, a `Move-ForeignHook` se naučí přepsat řetěz, který si instalátor sám vygeneroval. (3) `mb-state` tentýž stav hlásí read-only, bez instalátoru.

**Tech Stack:** PowerShell 7 (`#Requires -Version 7`, `Set-StrictMode -Version Latest`), POSIX `sh` pro hook, Git LFS, vlastní test harness `_assert.ps1`.

**Spec:** [design_lfs_prepush_chain_obnova.md](design_lfs_prepush_chain_obnova.md)

## Global Constraints

- PowerShell skripty: `#Requires -Version 7`, `Set-StrictMode -Version Latest`, `$ErrorActionPreference = 'Stop'` v testech.
- Hook je bezpříponový POSIX `sh` skript mimo dosah `.gitattributes` — všechny zápisy a kopie jeho obsahu **bajtové**, konce řádků **LF**.
- Exit kódy instalátoru zůstávají `0–4`. Nový kód se nezavádí (rozhodnutí, návrh §2).
- Testy leží vedle kódu v `tests/` a natahují helper přes `. (Join-Path $PSScriptRoot '_assert.ps1')`. Každý adresář `tests/` má vlastní kopii `_assert.ps1`.
- Uživatelský výstup, MB dokumenty a commit messages **česky**; komentáře v kódu a AI-facing texty **anglicky**.
- Žádná repo-specifická hodnota v těle skriptu (větve, prefixy tiketů) — patří do `ums-repo.json`.
- Značka `UMS pre-push guard (Publication Contract)` bez verze zůstává tím, podle čeho instalátor pozná vlastní hook. Verze je **jen** přípona a čtou ji konzumenti.
- Po dokončení plánu spusť `task-brief` pro každé číslo úlohy a ověř, že rozsahy sedí (playbook).

## Ověřovací sada

```
pwsh -NoProfile -File ums/.claude/skills/shared/tests/hook-version.tests.ps1
pwsh -NoProfile -File ums/.claude/hooks/tests/pre-push.tests.ps1
pwsh -NoProfile -File ums/.claude/skills/mb-epic-run/tests/pool-provision.tests.ps1
for t in $(find ums -name "*.tests.ps1"); do echo "== $t"; pwsh -NoProfile -File "$t" || echo "FAILED: $t"; done
```

## Po dokončení plánu

Šíření (návrh, sekce „Šíření") není úloha plánu — je to ruční krok uživatele na hranici dokončení: `pwsh ums/sync-with-monorepo.ps1`, **nejdřív `-Direction FromMonorepo`** a teprve potom `ToMonorepo`, jinak deploy přepíše to, v čem je monorepo napřed.

Tahle sekce stojí **před** úlohami záměrně: `task-brief` drží rozsah úlohy až do dalšího nadpisu `Task`, takže cokoli za poslední úlohou by se přililo do jejího briefu.

---

### Task 1: Helper pro čtení a porovnání verze hooku

**Files:**
- Create: `ums/.claude/skills/shared/scripts/Get-UmsHookVersion.ps1`
- Create: `ums/.claude/skills/shared/tests/hook-version.tests.ps1`

**Interfaces:**
- Consumes: nic (první úloha).
- Produces: `Get-UmsHookVersion([string] $Path)` → `[int]` verze, `0` pro náš hook bez verzní přípony, `$null` když soubor neexistuje nebo nenese naši značku. `Test-UmsHookNeedsInstall([string] $InstalledPath, [string] $SourceHookPath)` → `[bool]`; `$true`, právě když je nainstalovaná verze nižší než zdrojová, nebo nainstalovaný hook není náš či chybí.

- [ ] **Step 1: Napiš padající test**

Vytvoř `ums/.claude/skills/shared/tests/hook-version.tests.ps1`:

```powershell
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '_assert.ps1')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\scripts\Get-UmsHookVersion.ps1')

function New-HookFile([string] $Label, [string] $FirstLines) {
    $p = Join-Path ([IO.Path]::GetTempPath()) ("mbhookver-$Label-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    [IO.File]::WriteAllText($p, $FirstLines, (New-Object System.Text.UTF8Encoding($false)))
    return $p
}

$v3 = New-HookFile 'v3' "#!/bin/sh`n# UMS pre-push guard (Publication Contract) v3`n#`n"
$v2 = New-HookFile 'v2' "#!/bin/sh`n# UMS pre-push guard (Publication Contract) v2`n#`n"
$v0 = New-HookFile 'v0' "#!/bin/sh`n# UMS pre-push guard (Publication Contract)`n#`n"
$foreign = New-HookFile 'foreign' "#!/bin/sh`nexit 0`n"
$deep = New-HookFile 'deep' "#!/bin/sh`n#`n#`n#`n#`n# UMS pre-push guard (Publication Contract) v3`n"

Assert-Eq (Get-UmsHookVersion $v3) 3 'verze v3 se přečte jako 3'
Assert-Eq (Get-UmsHookVersion $v2) 2 'verze v2 se přečte jako 2'
Assert-Eq (Get-UmsHookVersion $v0) 0 'náš hook bez přípony je verze 0'
Assert-Eq (Get-UmsHookVersion $foreign) $null 'cizí hook nevrací verzi'
Assert-Eq (Get-UmsHookVersion (Join-Path $PSScriptRoot 'neexistuje')) $null 'chybějící soubor nevrací verzi'
Assert-Eq (Get-UmsHookVersion $deep) $null 'značka pod pátým řádkem se nepočítá'

Assert-True (Test-UmsHookNeedsInstall $v2 $v3) 'nainstalovaná v2 proti zdrojové v3 chce instalaci'
Assert-True (-not (Test-UmsHookNeedsInstall $v3 $v3)) 'shodná verze instalaci nechce'
Assert-True (-not (Test-UmsHookNeedsInstall $v3 $v2)) 'NOVĚJŠÍ nainstalovaná verze se NEDEGRADUJE'
Assert-True (Test-UmsHookNeedsInstall $v0 $v2) 'hook bez přípony chce instalaci'
Assert-True (Test-UmsHookNeedsInstall $foreign $v3) 'cizí hook chce instalaci'

Remove-Item -Force $v3, $v2, $v0, $foreign, $deep
Complete-Tests
```

Zkopíruj `ums/.claude/hooks/tests/_assert.ps1` do `ums/.claude/skills/shared/tests/_assert.ps1`, pokud tam ještě není.

- [ ] **Step 2: Spusť test a ověř, že padá**

Run: `pwsh -NoProfile -File ums/.claude/skills/shared/tests/hook-version.tests.ps1`
Expected: FAIL — soubor `Get-UmsHookVersion.ps1` neexistuje, dot-source skončí chybou.

- [ ] **Step 3: Napiš minimální implementaci**

Vytvoř `ums/.claude/skills/shared/scripts/Get-UmsHookVersion.ps1`:

```powershell
#Requires -Version 7
Set-StrictMode -Version Latest

# The version suffix of the pre-push hook header. The identity marker itself
# is version-less on purpose (install-git-hooks.ps1 recognises its OWN hook by
# it, whatever version), so the version lives only in the suffix and only
# consumers read it.
#
# Consumers compare by ORDERING, never by equality: an exact-match test cannot
# tell a NEWER hook from an older one, so a stale layer copy would reinstall
# over a newer hook and DOWNGRADE it. The hook lives in the shared common dir,
# so one stale worktree would downgrade it for the whole repository.
$script:UmsHookMarker = 'UMS pre-push guard \(Publication Contract\)'
$script:UmsHookMarkerLines = 5

# Returns [int] version, 0 for our hook without a suffix (pre-v2), or $null
# when the file is missing or is not our hook at all.
function Get-UmsHookVersion([string] $Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    $head = @(Get-Content -LiteralPath $Path -TotalCount $script:UmsHookMarkerLines -ErrorAction SilentlyContinue)
    if (-not $head) { return $null }
    # Case-sensitive by default in .NET: an identity check against the exact
    # marker the installer stamps, so a differently-cased paraphrase is never
    # mistaken for it.
    $m = [regex]::Match(($head -join "`n"), $script:UmsHookMarker + '(?:\s+v(\d+))?')
    if (-not $m.Success) { return $null }
    if (-not $m.Groups[1].Success) { return 0 }
    return [int] $m.Groups[1].Value
}

# $SourceHookPath is the layer's OWN hook source. Reading the current version
# from it rather than from a literal is what makes every future bump free for
# consumers: nobody has to be edited again.
function Test-UmsHookNeedsInstall([string] $InstalledPath, [string] $SourceHookPath) {
    $installed = Get-UmsHookVersion $InstalledPath
    if ($null -eq $installed) { return $true }
    $source = Get-UmsHookVersion $SourceHookPath
    if ($null -eq $source) { return $false }
    return ($installed -lt $source)
}
```

- [ ] **Step 4: Spusť test a ověř, že prochází**

Run: `pwsh -NoProfile -File ums/.claude/skills/shared/tests/hook-version.tests.ps1`
Expected: PASS, všech 11 asercí zeleně.

- [ ] **Step 5: Commit**

```bash
git add ums/.claude/skills/shared/scripts/Get-UmsHookVersion.ps1 ums/.claude/skills/shared/tests/hook-version.tests.ps1 ums/.claude/skills/shared/tests/_assert.ps1
git commit -m "lfs-prepush-chain-obnova: helper pro porovnání verze hooku uspořádáním"
```

---

### Task 2: Hlavička hooku na v3 a pool-provision na porovnání uspořádáním

**Files:**
- Modify: `ums/.claude/hooks/pre-push:2`
- Modify: `ums/.claude/skills/mb-epic-run/scripts/pool-provision.ps1:146-162` a prózu na řádcích 18, 29, 130, 190
- Modify: `ums/.claude/skills/mb-epic-run/tests/pool-provision.tests.ps1:71,77,83,149`
- Modify: `ums/.claude/hooks/tests/pre-push.tests.ps1:22` a `:1606`

**Interfaces:**
- Consumes: `Get-UmsHookVersion`, `Test-UmsHookNeedsInstall` z Tasku 1.
- Produces: hlavička hooku nese `v3`; `pool-provision.ps1` neobsahuje žádný verzní literál.

- [ ] **Step 1: Napiš padající test do pool-provision.tests.ps1**

Přidej na konec sekce s verzní bránou:

Použij zdejší idiom — fixtura přes `$NewFixture`, spuštění přes
`Invoke-Provision $fx.Main $slot`:

```powershell
# Novější hook, než nese vrstva slotu, se NESMÍ degradovat.
$fxNewer = & $NewFixture -SlotCount 0 -Label 'newerhook'
try {
    $slotNewer = Join-Path $fxNewer.Root 'slotNewer'
    $hookNewer = Join-Path $fxNewer.Main '.git/hooks/pre-push'
    New-Item -ItemType Directory -Force -Path (Split-Path $hookNewer) | Out-Null
    [IO.File]::WriteAllText($hookNewer, "#!/bin/sh`n# UMS pre-push guard (Publication Contract) v99`n", (New-Object System.Text.UTF8Encoding($false)))
    $before = [IO.File]::ReadAllText($hookNewer)
    Invoke-WithoutSessionEnv {
        $script:rNewer = Invoke-Provision $fxNewer.Main $slotNewer
    }
    Assert-Eq ([IO.File]::ReadAllText($hookNewer)) $before 'novější hook ve slotu zůstane nedotčený (žádná degradace)'
    Assert-Match $script:rNewer.Out 'not reinstalling' 'novější hook: skript reinstalaci vynechá'
}
finally {
    Remove-Item -Recurse -Force $fxNewer.Root -ErrorAction SilentlyContinue
}
```

- [ ] **Step 2: Spusť a ověř, že padá**

Run: `pwsh -NoProfile -File ums/.claude/skills/mb-epic-run/tests/pool-provision.tests.ps1`
Expected: FAIL — dnešní `-cmatch '… v2'` na `v99` nesedí, skript hook přeinstaluje ze své v2 kopie a obsah se změní.

- [ ] **Step 3: Přepiš verzní bránu v pool-provision.ps1**

Nahraď blok na řádcích 145-162 tímto (dot-source patří k ostatním na začátek skriptu):

```powershell
. (Join-Path $PSScriptRoot '..\..\shared\scripts\Get-UmsHookVersion.ps1')

$sourceHook = Join-Path $PSScriptRoot '..\..\..\hooks\pre-push'
$needsInstall = Test-UmsHookNeedsInstall $hookPath $sourceHook
if (-not $needsInstall) {
    $v = Get-UmsHookVersion $hookPath
    Write-Output "Shared pre-push guard is current (v$v) at $hookPath $([char]0x2014) not reinstalling."
}
else {
    $v = Get-UmsHookVersion $hookPath
    $found = if ($null -eq $v) { 'missing or foreign' } else { "v$v" }
    Write-Output "Shared pre-push guard is $found at $hookPath $([char]0x2014) installing."
```

Zbytek větve (`$installer = …` dál) zůstává beze změny.

**Pomlčka za cestou je em dash (U+2014), ne spojovník.** Regex v testu na řádku
149 na ni matchuje (`at (?<p>\S+) —`), takže záměna za `-` tichým způsobem
rozbije aserci o reportované cestě. Ve zdrojovém souboru ji piš přímo; zápis
přes `[char]0x2014` je tady jen proto, aby se v plánu nedala přehlédnout.

- [ ] **Step 4: Srovnej prózu ve stejném skriptu**

Na řádcích 18, 29, 130 a 190 nahraď „older than v2" a „a marked v2 hook" formulací bez čísla: „older than the layer's own hook" a „a marked hook at least as new as the layer's own". Číslo verze do prózy nepatří — Task 1 ho odsud odstranil právě proto.

- [ ] **Step 5: Oprav regex v testu**

`pool-provision.tests.ps1:149` nese obě větve textu brány:

```powershell
$m7 = [regex]::Match($script:r7.Out, 'guard is (?:current \(v\d+\)|missing or foreign|v\d+) at (?<p>\S+) —')
```

Em dash na konci zůstává — je to tentýž znak, který skript vypisuje.

Stejně srovnej aserce na řádcích 71, 77 a 83.

- [ ] **Step 6: Zvedni hlavičku hooku**

`ums/.claude/hooks/pre-push`, řádek 2:

```sh
# UMS pre-push guard (Publication Contract) v3
```

Tělo hooku se nemění.

- [ ] **Step 7: Srovnej dvě aserce v pre-push.tests.ps1**

Řádek 22 — ať netestuje konkrétní číslo, ale že verze vůbec je:

```powershell
Assert-Match ($hookSrc -join "`n") 'Publication Contract\) v\d+' 'hlavička hooku nese verzi, podle které jde poznat potřeba upgradu'
```

Řádek 1606 — strip musí odpovídat aktuální verzi, jinak je to no-op a sanity aserce na 1607 spadne:

```powershell
$oldStyleLine8 = $realHookLines8[1] -replace '\s+v\d+\s*$', ''
```

- [ ] **Step 8: Spusť obě sady a ověř, že procházejí**

Run: `pwsh -NoProfile -File ums/.claude/skills/mb-epic-run/tests/pool-provision.tests.ps1`
Run: `pwsh -NoProfile -File ums/.claude/hooks/tests/pre-push.tests.ps1`
Expected: PASS obě, včetně nové aserce o nedegradaci.

- [ ] **Step 9: Commit**

```bash
git add ums/.claude/hooks/pre-push ums/.claude/skills/mb-epic-run/scripts/pool-provision.ps1 ums/.claude/skills/mb-epic-run/tests/pool-provision.tests.ps1 ums/.claude/hooks/tests/pre-push.tests.ps1
git commit -m "lfs-prepush-chain-obnova: hlavička hooku na v3, pool-provision porovnává uspořádáním"
```

---

### Task 3: Prozaičtí konzumenti verze

**Files:**
- Modify: `ums/.claude/settings.json:62`
- Modify: `ums/.claude/skills/mb-state/SKILL.md:71-72,264,292,302,304`
- Modify: `ums/.claude/skills/shared/overlays/brainstorming.overlay.md:68`
- Modify: `ums/.claude/skills/shared/overlays/finishing-a-development-branch.overlay.md:16`
- Modify: `ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md:1-16,1182,1189,1897,1910-1911,2980`
- Modify: `memory-bank/tech.md:117`, `memory-bank/architecture.md:463`

**Interfaces:**
- Consumes: hlavička `v3` z Tasku 2.
- Produces: žádný prozaický konzument nenese číslo verze; všichni odkazují na zdrojovou hlavičku.

- [ ] **Step 1: Přepiš vstupní bránu v settings.json**

V `additionalContext` nahraď obě místa s `v2`. Formulace, která bump přežije:

> Ověř, že publikační záruka platí na tuhle session: `git rev-parse --git-path hooks/pre-push` musí existovat a nést v prvních pěti řádcích značku `UMS pre-push guard (Publication Contract)` s verzí **ne nižší, než jakou nese druhý řádek `.claude/hooks/pre-push`** ve vrstvě. Je-li nižší nebo hook chybí, spusť `pwsh -NoProfile -File .claude/hooks/install-git-hooks.ps1 -RepoRoot .` a ověř znovu.

Zbytek řetězce (syntetický pipe, ledger) se nemění. JSON zůstává validní — ověř `pwsh -c "Get-Content ums/.claude/settings.json -Raw | ConvertFrom-Json | Out-Null"`.

- [ ] **Step 2: Přepiš mb-state SKILL.md**

Na řádcích 71-72 nahraď popis `v2` popisem porovnání: hlavička musí nést verzi **ne nižší** než zdrojová hlavička vrstvy; nižší verze je chybějící záruka se stejnou nápravou. Na řádcích 264, 292, 302 a 304 nahraď „starší verze než v2" za „starší verze než zdrojová" a „older than v2" za „older than the layer's source".

- [ ] **Step 3: Přepiš oba overlaye**

`brainstorming.overlay.md:68` — „be at least v2" → „be at least the layer's own version".
`finishing-a-development-branch.overlay.md:16` — stejná náhrada literálu jako v settings.json.

- [ ] **Step 4: Přepiš kontrakt a zvedni Contract-Version**

Na řádcích 1182, 1189, 1897, 1910-1911 a 2980 nahraď literál `v2` odkazem na zdrojovou hlavičku. Věta na 1910-1911 o rozpoznání pre-v2 hooku **zůstává o v2 záměrně** — mluví o historickém tvaru, ne o aktuální verzi; jen ji doplň, že porovnání je uspořádáním.

V hlavičce souboru nastav `- **Contract-Version:** 2.19` a přidej supersedes řádek:

> - Supersedes v2.18 (the pre-push hook version is compared by ORDERING against the layer's own source header rather than by equality against a literal, so a stale layer copy can no longer downgrade a newer installed hook; adds the installer's restore of a clobbered Git LFS chain and the `mb-state` read-only detection of it).

- [ ] **Step 5: Přepiš dvě místa v memory-bank/**

`tech.md:117` a `architecture.md:463` — obě věty nesou „(`v2`)". Nahraď za „(verze podle hlavičky ve vrstvě)". Tahle dvě místa leží mimo `ums/`, což je důvod, proč grep zámek níž není omezený na `ums/`.

- [ ] **Step 6: Spusť grep zámek**

Run:

```
grep -rnE "Publication Contract\) v2|(older|starší) než v2|older-than-v2|at least v2|current \(v2\)" ums/ memory-bank/
```

Expected: zbudou **jen** řádky mluvící o staré verzi záměrně — upgrade fixtura v `pre-push.tests.ps1` a věta kontraktu o rozpoznání pre-v2 hooku. Cokoli jiného je nedodělaný přepis.

- [ ] **Step 7: Commit**

```bash
git add ums/.claude/settings.json ums/.claude/skills/mb-state/SKILL.md ums/.claude/skills/shared/overlays ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md memory-bank/tech.md memory-bank/architecture.md
git commit -m "lfs-prepush-chain-obnova: prozaičtí konzumenti verze odkazují na zdrojovou hlavičku, kontrakt na 2.19"
```

---

### Task 4: Restore-LfsChainedHook

**Files:**
- Modify: `ums/.claude/hooks/install-git-hooks.ps1` — nová funkce před hlavní smyčkou, volání ve smyčce mezi blokem cizího hooku (`:677-706`) a `Copy-Item` (`:708`); hlavička `:45-48`
- Modify: `ums/.claude/hooks/tests/pre-push.tests.ps1` — nový blok na konec

**Interfaces:**
- Consumes: `$shell`, `$CHAINED_SUFFIX`, `Get-HooksPathConfig`, `Test-IsOurHook` — vše už v `install-git-hooks.ps1`.
- Produces: `Restore-LfsChainedHook([string] $Path, [hashtable] $HooksPathCfg, [string] $Shell)` → hashtable `@{ Restored = [bool]; Path = [string]; Reason = [string] }`. `Reason` je neprázdný, právě když `Restored` je `$false`.

- [ ] **Step 1: Napiš padající test**

Přidej na konec `pre-push.tests.ps1` před `Complete-Tests`:

```powershell
# ---------------------------------------------------------------------------
# Obnova ztraceného LFS řetězu: náš hook na místě, LFS sourozenci tam jsou,
# ale .ums-chained chybí - starší instalátor ho přepsal místo odsunutí.
# ---------------------------------------------------------------------------
function New-LfsSiblingRepo([string] $Label) {
    $r = Join-Path ([IO.Path]::GetTempPath()) ("mblfs-$Label-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    & git init -q -b develop $r | Out-Null
    & git -C $r remote add origin "$r/../fake-origin" | Out-Null
    $h = Join-Path $r '.git/hooks'
    New-Item -ItemType Directory -Force -Path $h | Out-Null
    foreach ($n in @('post-commit', 'post-checkout', 'post-merge')) {
        [IO.File]::WriteAllText((Join-Path $h $n), "#!/bin/sh`ngit lfs $n `"`$@`"`n", (New-Object System.Text.UTF8Encoding($false)))
    }
    return $r
}

$rLfs = New-LfsSiblingRepo 'restore'
$res = Invoke-Installer $rLfs $null
$chained = Join-Path $rLfs '.git/hooks/pre-push.ums-chained'
Assert-True (Test-Path $chained) 'obnova: .ums-chained vznikl'
Assert-Match ([IO.File]::ReadAllText($chained)) 'git lfs pre-push' 'obnova: obnovený řetěz volá git lfs pre-push'
Assert-Match ([IO.File]::ReadAllText($chained)) 'Restored by install-git-hooks.ps1' 'obnova: obnovený řetěz nese provenience stamp'
Assert-Match $res.Flat 'restored' 'obnova: instalátor obnovu pojmenuje'
Assert-Eq $res.Code 0 'obnova: instalace končí kódem 0'

# Druhý běh obnovený soubor nemění.
$chainedBefore = [IO.File]::ReadAllText($chained)
$res = Invoke-Installer $rLfs $null
Assert-Eq ([IO.File]::ReadAllText($chained)) $chainedBefore 'obnova: opakovaný běh obnovený soubor nemění'

# Repozitář bez jakékoli stopy po LFS - nevznikne nic.
$rNoLfs = Join-Path ([IO.Path]::GetTempPath()) ("mbnolfs-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
& git init -q -b develop $rNoLfs | Out-Null
Invoke-Installer $rNoLfs $null | Out-Null
Assert-True (-not (Test-Path (Join-Path $rNoLfs '.git/hooks/pre-push.ums-chained'))) 'bez LFS: žádný řetěz nevznikne'

# .ums-chained existuje, ale je to cizí non-LFS hook -> obnova se nespustí.
$rForeignChain = New-LfsSiblingRepo 'foreignchain'
[IO.File]::WriteAllText((Join-Path $rForeignChain '.git/hooks/pre-push.ums-chained'), "#!/bin/sh`nexit 0`n", (New-Object System.Text.UTF8Encoding($false)))
$before = [IO.File]::ReadAllText((Join-Path $rForeignChain '.git/hooks/pre-push.ums-chained'))
Invoke-Installer $rForeignChain $null | Out-Null
Assert-Eq ([IO.File]::ReadAllText((Join-Path $rForeignChain '.git/hooks/pre-push.ums-chained'))) $before 'cizí řetěz: obnova ho nepřepíše'

# Důkaz o LFS i bez sourozenců - .gitattributes s filter=lfs.
$rAttr = Join-Path ([IO.Path]::GetTempPath()) ("mbattr-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
& git init -q -b develop $rAttr | Out-Null
& git -C $rAttr remote add origin "$rAttr/../fake-origin" | Out-Null
[IO.File]::WriteAllText((Join-Path $rAttr '.gitattributes'), "*.dll filter=lfs diff=lfs merge=lfs -text`n", (New-Object System.Text.UTF8Encoding($false)))
Invoke-Installer $rAttr $null | Out-Null
Assert-True (Test-Path (Join-Path $rAttr '.git/hooks/pre-push.ums-chained')) 'důkaz z .gitattributes: řetěz se obnoví i bez sourozenců'

Remove-Item -Recurse -Force $rLfs, $rNoLfs, $rForeignChain, $rAttr
```

- [ ] **Step 2: Spusť a ověř, že padá**

Run: `pwsh -NoProfile -File ums/.claude/hooks/tests/pre-push.tests.ps1`
Expected: FAIL na první aserci — `.ums-chained` nevznikne, funkce zatím neexistuje.

- [ ] **Step 3: Implementuj funkci**

**Pozor na pořadí definic.** `$RESTORE_STAMP` a `Test-IsLfsHook` musí stát
**před** `Move-ForeignHook` (tedy před řádkem 611), protože je Task 5 použije
uvnitř jeho těla; zbytek (`Test-RepoUsesLfs`, `Restore-LfsChainedHook`) jde až
za něj, za řádek 667. Na runtime by fungovalo obojí, ale čtenář nemá lovit
definici o padesát řádků níž.

Před `Move-ForeignHook`:

```powershell
$RESTORE_STAMP = '# Restored by install-git-hooks.ps1 (git-lfs pre-push chain)'

# Does this hook body call `git lfs <name>`? Used both as evidence that
# git-lfs installed its hooks here and as the identity test for an existing
# chain - existence alone proves nothing, the slot is single and may hold a
# husky/pre-commit hook while the LFS chain is lost.
function Test-IsLfsHook([string] $Path, [string] $Verb) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    $body = Get-Content -LiteralPath $Path -Raw -ErrorAction SilentlyContinue
    if (-not $body) { return $false }
    return ($body -match ('git\s+lfs\s+' + [regex]::Escape($Verb)))
}
```

Za `Move-ForeignHook` (za řádek 667):

```powershell

# Evidence that THIS repository uses LFS. Deliberately NOT limited to the
# hooks directory: husky (core.hooksPath=.husky), a wiped .git/hooks or a
# relocated hooks dir leaves a genuinely LFS-using repo with zero siblings.
function Test-RepoUsesLfs([string] $Root, [string] $HooksDir) {
    foreach ($n in @('post-commit', 'post-checkout', 'post-merge')) {
        if (Test-IsLfsHook (Join-Path $HooksDir $n) $n) { return $true }
    }
    $attr = Join-Path $Root '.gitattributes'
    if ((Test-Path -LiteralPath $attr) -and ((Get-Content -LiteralPath $attr -Raw) -match 'filter=lfs')) { return $true }
    $store = & git -C $Root rev-parse --git-path lfs 2>$null
    if ($LASTEXITCODE -eq 0 -and $store) {
        $storePath = if ([IO.Path]::IsPathRooted($store)) { $store } else { Join-Path $Root $store }
        if ((Test-Path -LiteralPath $storePath) -and @(Get-ChildItem -LiteralPath $storePath -Recurse -File -ErrorAction SilentlyContinue).Count -gt 0) { return $true }
    }
    & git -C $Root config --get-regexp '^lfs\.' 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { return $true }
    return $false
}

# Generates the chain FROM git-lfs rather than transcribing it, and does so in
# isolation: `git init` honours init.templateDir and `git lfs install --local`
# resolves its hooks dir through core.hooksPath, which may come from GLOBAL
# config - without isolation the generation step would write into the user's
# shared hooks directory, outside both the temp dir and the target repo.
function Restore-LfsChainedHook([string] $Path, [hashtable] $HooksPathCfg, [string] $Shell) {
    if ($HooksPathCfg -and ($HooksPathCfg.IsAbsolute -or $HooksPathCfg.Scope -in @('global', 'system'))) {
        return @{ Restored = $false; Path = $null; Reason = 'the hooks directory is shared with other repositories (core.hooksPath), so restoring a chain there would enable it for every one of them' }
    }
    $dst = $Path + $CHAINED_SUFFIX
    $healthy = (Test-IsLfsHook $dst 'pre-push')
    if ($healthy -and $Shell) {
        $unix = $dst -replace '\\', '/'
        & $Shell -c 'test -x "$1"' _ $unix 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { return @{ Restored = $false; Path = $dst; Reason = $null } }
        & $Shell -c 'chmod +x "$1"' _ $unix 2>&1 | Out-Null
        return @{ Restored = $true; Path = $dst; Reason = $null }
    }
    if ((Test-Path -LiteralPath $dst) -and -not $healthy) {
        return @{ Restored = $false; Path = $dst; Reason = "a chained hook that is not a git-lfs hook is already present at $dst - not overwriting it" }
    }
    if (-not (Get-Command git-lfs -ErrorAction SilentlyContinue)) {
        return @{ Restored = $false; Path = $null; Reason = 'git lfs is not on PATH' }
    }
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('umslfsgen-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    try {
        New-Item -ItemType Directory -Force -Path $tmp | Out-Null
        $nul = Join-Path $tmp 'no-such-config'
        $env:GIT_CONFIG_GLOBAL = $nul
        $env:GIT_CONFIG_SYSTEM = $nul
        & git init -q --template= -b main $tmp 2>$null | Out-Null
        & git -C $tmp -c core.hooksPath= lfs install --local 2>$null | Out-Null
        $gen = Join-Path $tmp '.git/hooks/pre-push'
        if (-not (Test-IsLfsHook $gen 'pre-push')) {
            return @{ Restored = $false; Path = $null; Reason = 'git lfs did not generate a recognisable pre-push hook' }
        }
        $bytes = [IO.File]::ReadAllBytes($gen)
        [IO.File]::WriteAllBytes($dst, $bytes)
        [IO.File]::AppendAllText($dst, "`n$RESTORE_STAMP`n")
        if ($Shell) {
            $unix = $dst -replace '\\', '/'
            $out = & $Shell -c 'chmod +x "$1"' _ $unix 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Host "WARNING: restored $dst but could not make it executable ($out) - our hook will silently skip it until this is fixed by hand." -ForegroundColor Red
            }
        }
        return @{ Restored = $true; Path = $dst; Reason = $null }
    }
    finally {
        Remove-Item Env:GIT_CONFIG_GLOBAL -ErrorAction SilentlyContinue
        Remove-Item Env:GIT_CONFIG_SYSTEM -ErrorAction SilentlyContinue
        Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
    }
}
```

- [ ] **Step 4: Zavolej ji v hlavní smyčce**

V `install-git-hooks.ps1` vlož mezi konec bloku cizího hooku (`}` na řádku 706) a `Copy-Item` (řádek 708):

```powershell
    # Only pre-push carries a chain, and only where our hook is (or is about
    # to be) the installed one - a repo whose pre-push is foreign is handled
    # by the block above, and one with no pre-push at all never lost a chain.
    if ($name -eq 'pre-push' -and (-not (Test-Path $dst) -or (Test-IsOurHook $dst))) {
        if (Test-RepoUsesLfs $RepoRoot (Split-Path $dst)) {
            $restore = Restore-LfsChainedHook $dst $hooksPathCfg $shell
            if ($restore.Restored) {
                Write-Host "restored: git-lfs pre-push chain -> $($restore.Path)" -ForegroundColor Cyan
            }
            elseif ($restore.Reason) {
                Write-Host "note: git-lfs chain not restored - $($restore.Reason)" -ForegroundColor Yellow
            }
        }
    }
```

Podmínka `-not (Test-Path $dst)` pokrývá první instalaci do repozitáře, který LFS používá a hook tam ještě nemá.

- [ ] **Step 5: Srovnej hlavičku skriptu s realitou**

Na řádcích 45-48 stojí, že proof běhy se ničeho nedotknou („no git command runs, every sha is fabricated"). Po obnově to neplatí doslova — accept běh jde přes `run_chained` do skutečného `git-lfs`. Uprav větu:

```
    No run pushes anything and every sha is fabricated. Where a git-lfs chain
    is present the accept run does reach real git-lfs through run_chained, so
    the run is not free of git entirely - it still writes nothing and pushes
    nothing.
```

K tomu doplň ke konstantám komentář, proč neobnovený řetěz nemá vlastní exit kód: kódy 0-4 mluví o publikační záruce, guard je v takovém případě nainstalovaný a funguje, kanálem pro tenhle fakt je `mb-state`.

- [ ] **Step 6: Spusť sadu a ověř, že prochází**

Run: `pwsh -NoProfile -File ums/.claude/hooks/tests/pre-push.tests.ps1`
Expected: PASS, včetně všech šesti nových asercí.

- [ ] **Step 7: Commit**

```bash
git add ums/.claude/hooks/install-git-hooks.ps1 ums/.claude/hooks/tests/pre-push.tests.ps1
git commit -m "lfs-prepush-chain-obnova: instalátor obnoví ztracený LFS pre-push řetěz"
```

---

### Task 5: Move-ForeignHook smí přepsat vlastní obnovený řetěz

**Files:**
- Modify: `ums/.claude/hooks/install-git-hooks.ps1:624-627`
- Modify: `ums/.claude/hooks/tests/pre-push.tests.ps1` — nový blok

**Interfaces:**
- Consumes: `$RESTORE_STAMP`, `Test-IsLfsHook` a testovací helper `New-LfsSiblingRepo` — vše z Tasku 4.
- Produces: `Move-ForeignHook` vrací `Moved = $true` i tam, kde `.ums-chained` existuje, je-li to náš obnovený LFS řetěz a příchozí cizí hook je také LFS.

- [ ] **Step 1: Napiš padající test**

```powershell
# Po obnově git-lfs znovu nainstaluje svůj pre-push. Instalátor ho musí
# zřetězit přes náš vlastní obnovený řetěz, ne skončit exitem 2.
$rReinstall = New-LfsSiblingRepo 'reinstall'
Invoke-Installer $rReinstall $null | Out-Null
$chainedPath = Join-Path $rReinstall '.git/hooks/pre-push.ums-chained'
Assert-True (Test-Path $chainedPath) 'reinstalace: předpoklad - řetěz byl obnoven'
[IO.File]::WriteAllText((Join-Path $rReinstall '.git/hooks/pre-push'), "#!/bin/sh`ngit lfs pre-push `"`$@`"`n", (New-Object System.Text.UTF8Encoding($false)))
$res = Invoke-Installer $rReinstall $null
Assert-Eq $res.Code 0 'reinstalace: instalátor neskončí exitem 2, náš obnovený řetěz smí přepsat'
Assert-NotMatch ([IO.File]::ReadAllText($chainedPath)) 'Restored by install-git-hooks' 'reinstalace: na místě je teď skutečný hook od git-lfs, ne náš generovaný'
$head = Get-Content -LiteralPath (Join-Path $rReinstall '.git/hooks/pre-push') -TotalCount 5
Assert-Match ($head -join "`n") 'UMS pre-push guard' 'reinstalace: na pre-push je zase náš hook'
Remove-Item -Recurse -Force $rReinstall
```

- [ ] **Step 2: Spusť a ověř, že padá**

Run: `pwsh -NoProfile -File ums/.claude/hooks/tests/pre-push.tests.ps1`
Expected: FAIL — `Assert-Eq $res.Code 0` dostane 2, protože `Move-ForeignHook` odmítá na existujícím `.ums-chained`.

- [ ] **Step 3: Uprav Move-ForeignHook**

Nahraď řádky 624-627:

```powershell
    $dst = $Path + $CHAINED_SUFFIX
    if (Test-Path -LiteralPath $dst) {
        # One exception to "never overwrite an existing chain": a chain THIS
        # script generated itself (stamp) that calls git-lfs, being replaced
        # by a real git-lfs hook. Without it the restore of Task 4 would
        # manufacture the very exit-2 refusal it exists to prevent - the
        # guarantee would vanish in a clone where chaining used to work.
        $body = Get-Content -LiteralPath $dst -Raw -ErrorAction SilentlyContinue
        $isOurRestored = $body -and ($body -match [regex]::Escape($RESTORE_STAMP)) -and (Test-IsLfsHook $dst 'pre-push')
        if (-not ($isOurRestored -and (Test-IsLfsHook $Path 'pre-push'))) {
            return @{ Moved = $false; Path = $dst; Refused = "a chained hook is already present at $dst - not overwriting it" }
        }
    }
```

- [ ] **Step 4: Spusť sadu a ověř, že prochází**

Run: `pwsh -NoProfile -File ums/.claude/hooks/tests/pre-push.tests.ps1`
Expected: PASS. Existující aserce na řádcích 1185-1197 (cizí non-LFS hook vedle existujícího `.ums-chained` → exit 2) musí zůstat **zelená** — výjimka platí jen pro náš stamp plus LFS na obou stranách.

- [ ] **Step 5: Commit**

```bash
git add ums/.claude/hooks/install-git-hooks.ps1 ums/.claude/hooks/tests/pre-push.tests.ps1
git commit -m "lfs-prepush-chain-obnova: řetěz s vlastním stampem smí ustoupit skutečnému git-lfs hooku"
```

---

### Task 6: Detekce v mb-state

**Files:**
- Modify: `ums/.claude/skills/mb-state/SKILL.md` — gather sekce (kolem řádku 41), šablona reportu (`:264`), „Další krok" (`:281-293`), poznámky pod šablonou (`:296-314`)

**Interfaces:**
- Consumes: spouštěcí podmínky z Tasku 4 (tentýž stav, aby se report a akce nerozešly).
- Produces: žádné — `mb-state` je read-only skill, kód nevzniká.

- [ ] **Step 1: Doplň kontrolu do gather sekce**

Za odstavec o `core.hooksPath` přidej anglicky psaný odstavec: hooks adresář není sdílený, na `pre-push` leží náš hook, repozitář používá LFS (sourozenec volající `git lfs <name>`, nebo `filter=lfs` v `.gitattributes`, nebo neprázdný `.git/lfs/`, nebo `git config --get-regexp '^lfs\.'`), a zdravý řetěz tam není (`.ums-chained` chybí, nevolá `git lfs pre-push`, nebo nemá execute bit). Zdůrazni, že se **nic nespouští** — jen `Test-Path` a čtení souborů.

- [ ] **Step 2: Zařaď hlášku na správné místo šablony**

Na řádku 264 přidej položku **vedle** `✅ způsobilý`, ne do první alternace:

```
<+ ⚠️ LFS pre-push řetěz chybí nebo je neúplný>
```

Do poznámek pod šablonou dopiš jednu větu: není to chybějící záruka — guard je nainstalovaný a funguje —, takže to jede alongside, stejně jako varování o absolutním `core.hooksPath`.

- [ ] **Step 3: Přidej odrážku do „Další krok"**

```
- LFS řetěz chybí/neúplný → spusť install-git-hooks.ps1 a znovu ověř
```

- [ ] **Step 4: Ověř, že hláška neříká, co soubor DĚLÁ**

Run: `grep -n "neodesílá LFS" ums/.claude/skills/mb-state/SKILL.md`
Expected: žádný výstup. Důsledek („git push neodesílá LFS objekty") patří do „Další krok", ne do stavového řádku — `mb-state` hlásí, co soubor JE.

- [ ] **Step 5: Commit**

```bash
git add ums/.claude/skills/mb-state/SKILL.md
git commit -m "lfs-prepush-chain-obnova: mb-state hlásí chybějící LFS řetěz i bez instalátoru"
```

---

### Task 7: Spojený akceptační případ a zbylé nepokryté stavy

**Files:**
- Modify: `ums/.claude/hooks/tests/pre-push.tests.ps1` — závěrečný blok

**Interfaces:**
- Consumes: vše z Tasků 1-5, zejména testovací helper `New-LfsSiblingRepo` a `Find-GitBash` (ten už v sadě je, řádek 60).
- Produces: žádné — poslední úloha, jen zámek.

- [ ] **Step 1: Napiš spojený akceptační test**

```powershell
# Obě poloviny změny se musí potkat v JEDNOM běhu instalátoru, jinak si každá
# dokazuje jen sebe: klon s LFS, náš hook ve staré verzi, bez řetězu.
$rBoth = New-LfsSiblingRepo 'both'
$hookBoth = Join-Path $rBoth '.git/hooks/pre-push'
$srcHead = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\pre-push') -TotalCount 5
$srcVersion = [regex]::Match(($srcHead -join "`n"), 'Publication Contract\) v(\d+)').Groups[1].Value
[IO.File]::WriteAllText($hookBoth, "#!/bin/sh`n# UMS pre-push guard (Publication Contract) v1`n# stale`n", (New-Object System.Text.UTF8Encoding($false)))
$res = Invoke-Installer $rBoth $null
$headBoth = Get-Content -LiteralPath $hookBoth -TotalCount 5
Assert-Match ($headBoth -join "`n") ('Publication Contract\) v' + $srcVersion) 'spojený případ: hlavička po instalaci nese zdrojovou verzi'
Assert-True (Test-Path (Join-Path $rBoth '.git/hooks/pre-push.ums-chained')) 'spojený případ: v témže běhu vznikl i LFS řetěz'
Assert-Eq $res.Code 0 'spojený případ: instalace končí kódem 0'
Remove-Item -Recurse -Force $rBoth
```

- [ ] **Step 2: Napiš test na sdílený core.hooksPath a na neexekutovatelný řetěz**

```powershell
# Sdílený hooks adresář: obnova se nesmí spustit vůbec.
$rShared = New-LfsSiblingRepo 'shared'
$sharedHooks = Join-Path ([IO.Path]::GetTempPath()) ("mbsharedhooks-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $sharedHooks | Out-Null
Invoke-GitOk $rShared @('config', 'core.hooksPath', $sharedHooks) | Out-Null
Invoke-Installer $rShared $null | Out-Null
Assert-True (-not (Test-Path (Join-Path $sharedHooks 'pre-push.ums-chained'))) 'sdílený hooks adresář: obnova se nespustí'

# Řetěz volá git lfs, ale nemá execute bit -> opraví se.
$rNoX = New-LfsSiblingRepo 'noexec'
Invoke-Installer $rNoX $null | Out-Null
$chainNoX = Join-Path $rNoX '.git/hooks/pre-push.ums-chained'
$bash = Find-GitBash
& $bash -c 'chmod -x "$1"' _ ($chainNoX -replace '\\', '/') | Out-Null
Invoke-Installer $rNoX $null | Out-Null
& $bash -c 'test -x "$1"' _ ($chainNoX -replace '\\', '/') | Out-Null
Assert-Eq $LASTEXITCODE 0 'neexekutovatelný řetěz: opakovaný běh instalátoru execute bit vrátí'

Remove-Item -Recurse -Force $rShared, $sharedHooks, $rNoX
```

- [ ] **Step 3: Případy bez git-lfs na stroji se přeskočí, nezčervenají**

Návrh to žádá výslovně. Obal všechny bloky závislé na skutečném `git-lfs`
strážcem na začátku sady:

```powershell
$script:HasGitLfs = [bool](Get-Command git-lfs -ErrorAction SilentlyContinue)
if (-not $script:HasGitLfs) {
    Write-Host 'SKIP: git-lfs není na PATH - případy obnovy řetězu se přeskakují (ne fail).' -ForegroundColor Yellow
}
```

Každý blok obnovy pak podmiň `if ($script:HasGitLfs) { … }`. Bloky, které
skutečný `git-lfs` nepotřebují (sdílený `core.hooksPath`, cizí řetěz, důkaz
z `.gitattributes` bez generování), zůstávají nepodmíněné.

- [ ] **Step 4: Spusť celou sadu**

Run: `pwsh -NoProfile -File ums/.claude/hooks/tests/pre-push.tests.ps1`
Expected: PASS, žádná aserce neregresovala.

- [ ] **Step 5: Negativní běh jako regresní zámek**

Získej neopravený skript z gitu do dočasného souboru a spusť sadu proti němu — bez editace pracovního stromu:

```bash
git show $(git merge-base HEAD origin/ums-memory-bank):ums/.claude/hooks/install-git-hooks.ps1 > /tmp/install-old.ps1
```

Pak sadu spusť proti `/tmp/install-old.ps1` (parametr `$installScript` v hlavičce sady) a rozděl výsledek na dvě skupiny: aserce, které **zčervenaly** (ty dokazují, že změna něco dělá) a aserce, které **zůstaly zelené v obou bězích** (regresní zámek). Zapiš obě skupiny do reportu úlohy.

- [ ] **Step 6: Spusť celou ověřovací sadu**

Run:

```
for t in $(find ums -name "*.tests.ps1"); do echo "== $t"; pwsh -NoProfile -File "$t" || echo "FAILED: $t"; done
```

Expected: žádné `FAILED:`.

- [ ] **Step 7: Commit**

```bash
git add ums/.claude/hooks/tests/pre-push.tests.ps1
git commit -m "lfs-prepush-chain-obnova: spojený akceptační případ a zámky na zbylé stavy"
```
