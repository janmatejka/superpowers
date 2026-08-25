# Publikační guard míří na agenta — implementační plán

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Přestavět publikační vynucení tak, aby mířilo na agenta a ne na člověka, aby posuzovalo obsah pushe místo pouhého jména větve, a aby koexistovalo s cizím `pre-push` hookem (Git LFS).

**Architecture:** Git `pre-push` dostane bránu na značku agentní session (bez ní nevynucuje nic a deleguje na řetězený cizí hook), pravidlo obsahu (na chráněné větvi projde fast-forward na commity už dosažitelné na cílovém remote) a jednotnou lidskou výjimku. Pravidlo aktéra („okamžik integrace patří člověku") přebírá harnessový PreToolUse guard, který vidí jen volání nástroje agentem. Instalátor cizí hook neodmítá, ale odsouvá a řetězí.

**Tech Stack:** POSIX `sh` (hook), PowerShell 7 (instalátor, sync, testy), Node.js ESM (PreToolUse guard), git.

**Spec:** [design_push_guard_jen_pro_agenty.md](design_push_guard_jen_pro_agenty.md)

## Global Constraints

- **Zdroj pravdy je `ums/.claude/`.** Kořenový `.claude/` a `.agents/skills/` jsou netrackovaná nasazení — po každé změně zdroje se obnovují (Task 11), nikdy se needitují přímo.
- **Značka agentní session:** `MB_AGENT_SESSION=1`. Fallback jen pro Claude Code: neprázdné `AI_AGENT`, nebo `CLAUDECODE=1`.
- **Lidská výjimka:** `MB_HUMAN_PUSH=1`. Přechodně se přijímá i `UMS_ALLOW_SHARED_PUSH=1` s hláškou o zastaralosti.
- **Řetězený cizí hook:** `.git/hooks/pre-push.ums-chained` (resolvováno vůči adresáři, ze kterého se hook spustil).
- **Hlavička hooku:** řetězec `UMS pre-push guard (Publication Contract)` v prvních pěti řádcích se **nesmí změnit** — je to identita, podle které instalátor pozná svůj hook. Verze se připojuje ZA něj (`… v2`).
- **Hook je POSIX `sh` bez přípony**, konce řádků LF (`ums/.gitattributes`). Žádný bashismus.
- **Podpříkazy uvnitř hlavní `while read` smyčky i mimo ni si uzavírají stdin** (`</dev/null`) — jinak ukousnou seznam refů.
- **Testy:** žádný Pester, jen `.ps1` s `_assert.ps1` vedle sady; offline, proti lokálnímu bare klonu jako „origin"; české popisy asercí, ASCII vzory tam, kde se čte git stderr.
- **Jazyk:** dokumenty, hlášky hooků a commit messages česky; AI-facing texty anglicky.
- **Testovací smyčka celé vrstvy** (spouští se na konci každého tasku, který mění kód):

```bash
for t in $(find ums -name "*.tests.ps1"); do echo "== $t"; pwsh -NoProfile -File "$t" || echo "FAILED: $t"; done
```

---

### Task 1: Rozšíření matcheru a přeměření sondy (prerekvizita)

Celý zbytek plánu stojí na tvrzení, že příkazy zadané uživatelem s vykřičníkem PreToolUse hooky nespouštějí. Původní sonda je zmatená mezerou v matcheru. **Tento task končí otázkou na uživatele a plán se dál nevykonává, dokud nedá odpověď.**

**Files:**
- Modify: `ums/.claude/settings.json` (blok `hooks.PreToolUse`, matcher `Bash`)
- Modify: `ums/.claude/hooks/tests/guard-git-push.tests.ps1` (konec souboru, před `Complete-Tests`)

**Interfaces:**
- Produces: potvrzený nebo vyvrácený předpoklad „vykřičníkové příkazy neprocházejí PreToolUse"; rozšířený matcher `Bash|PowerShell`, na kterém staví Task 6.

- [ ] **Step 1: Napiš selhávající test na registraci matcheru**

Na konec `ums/.claude/hooks/tests/guard-git-push.tests.ps1`, před `Complete-Tests`:

```powershell
# Registrace hooku je konfigurace, ne kód - ale díra v ní znamená, že guard
# na polovinu volání vůbec nevystřelí. Sezení s CLAUDE_CODE_USE_POWERSHELL_TOOL=1
# jede přes PowerShell tool; s matcherem jen na Bash by push tudy prošel bez
# jediné kontroly.
$settingsPath = Join-Path $PSScriptRoot '..\..\settings.json'
$settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
$bashMatchers = @($settings.hooks.PreToolUse | Where-Object {
    ($_.hooks | Where-Object { $_.command -match 'guard-git-push' })
} | ForEach-Object { $_.matcher })
Assert-Eq @($bashMatchers).Count 1 'guard-git-push je registrovaný právě jednou'
Assert-Match $bashMatchers[0] 'Bash' 'matcher guardu pokrývá Bash tool'
Assert-Match $bashMatchers[0] 'PowerShell' 'matcher guardu pokrývá i PowerShell tool'
```

- [ ] **Step 2: Spusť test a ověř, že selže**

Run: `pwsh -NoProfile -File ums/.claude/hooks/tests/guard-git-push.tests.ps1`
Expected: FAIL na asercii „matcher guardu pokrývá i PowerShell tool" (hodnota je dnes `Bash`).

- [ ] **Step 3: Rozšiř matcher**

V `ums/.claude/settings.json` v bloku `hooks.PreToolUse` u položky volající `guard-git-push.mjs`:

```json
        "matcher": "Bash|PowerShell",
```

- [ ] **Step 4: Spusť test a ověř, že projde**

Run: `pwsh -NoProfile -File ums/.claude/hooks/tests/guard-git-push.tests.ps1`
Expected: PASS, počet asercí o 3 vyšší než dřív.

- [ ] **Step 5: Obnov nasazenou kopii, aby sonda měřila novou konfiguraci**

```bash
cp ums/.claude/settings.json .claude/settings.json
```

- [ ] **Step 6: Commit**

```bash
git add ums/.claude/settings.json ums/.claude/hooks/tests/guard-git-push.tests.ps1
git commit -m "push-guard-jen-pro-agenty: matcher guardu pokrývá i PowerShell tool

 - guard-git-push registrovaný jen na Bash nevystřelil na volání přes PowerShell tool
 - test nad settings.json hlídá obě jména nástroje"
git push
```

- [ ] **Step 7: STOP — vyžádej si od uživatele přeměření sondy**

Sezení se musí restartovat, aby se nová registrace načetla. Pak požádej uživatele, ať v sezení zadá přesně:

```text
! echo git push --no-verify
```

Vyhodnocení a co z něj plyne:

- **Vypíše se jen text** → předpoklad potvrzen, vykřičníkové příkazy PreToolUse neaktivují. Pokračuj Taskem 2.
- **Přijde zamítnutí od UMS** → předpoklad vyvrácen. **STOP celého plánu.** Rozdělení práce mezi dvě vrstvy nefunguje, protože guard by blokoval i příkazy člověka; body 3 a 4 návrhu se musí přepracovat. Ohlas to uživateli a vrať se k brainstormingu.

Výsledek zapiš do ledgeru včetně toho, kterým nástrojem sonda prošla.

---

### Task 2: Bufferování stdinu a volání řetězeného hooku (strana hooku)

**Files:**
- Modify: `ums/.claude/hooks/pre-push` (hlavička a hlavní smyčka)
- Test: `ums/.claude/hooks/tests/pre-push.tests.ps1`

**Interfaces:**
- Produces: shellová funkce `run_chained` a soubor `$stdin_buf`, na kterých staví Task 4 (delegace při chybějící značce) a Task 6 (delegace při lidské výjimce).

- [ ] **Step 1: Napiš selhávající test na řetězení**

Na konec `ums/.claude/hooks/tests/pre-push.tests.ps1`, před `Complete-Tests`. Fixtura zapíše falešný „cizí" hook, který dokazuje obojí — že doběhl a že dostal celý stdin:

```powershell
# ---------------------------------------------------------------------------
# Řetězení cizího hooku. Kanárek zapisuje počet přijatých řádků stdinu do
# souboru: kdyby ho hook zavolal bez přehrání stdinu, napíše 0 a LFS by tiše
# přestalo posílat objekty - selhání, které vypadá jako funkční stav.
# ---------------------------------------------------------------------------
$chainDir = Join-Path $work '.git/hooks'
$canaryOut = (Join-Path $root 'canary.txt') -replace '\\', '/'
$chainPath = Join-Path $chainDir 'pre-push.ums-chained'
Set-Content -LiteralPath $chainPath -Encoding ascii -Value @"
#!/bin/sh
wc -l < /dev/stdin > "$canaryOut"
echo "args=\$*" >> "$canaryOut"
exit 0
"@
& $gitBash -c 'chmod +x "$1"' _ ($chainPath -replace '\\', '/') | Out-Null

Invoke-GitOk $work @('checkout', 'feature/x') | Out-Null
Add-Content -Path (Join-Path $work 'g.txt') -Value 'chain test'
Invoke-GitOk $work @('commit', '-am', 'chain test') | Out-Null
$r = Invoke-GitTry $work @('push', 'origin', 'feature/x')
Assert-Eq $r.Code 0 'řetězení: povolený push projde'
Assert-True (Test-Path $canaryOut) 'řetězení: cizí hook byl skutečně zavolán'
$canary = @(Get-Content -LiteralPath $canaryOut)
Assert-Eq $canary[0].Trim() '1' 'řetězení: cizí hook dostal přehraný stdin (1 ref)'
Assert-Match $canary[1] 'args=origin' 'řetězení: cizí hook dostal i argumenty gitu'
```

- [ ] **Step 2: Spusť sadu a ověř, že selže**

Run: `pwsh -NoProfile -File ums/.claude/hooks/tests/pre-push.tests.ps1`
Expected: FAIL na „řetězení: cizí hook byl skutečně zavolán" (soubor kanárka nevznikne).

- [ ] **Step 3: Přidej buffer a delegaci do hooku**

V `ums/.claude/hooks/pre-push` hned za přiřazení `remote_name`, `zero` a `reject`:

```sh
# Adresář, ze kterého git tenhle hook spustil - i pod core.hooksPath a
# v linked worktree. Resolvován absolutně, protože cwd hooku je kořen
# repozitáře, ne adresář hooku.
hooks_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
chained="$hooks_dir/pre-push.ums-chained"

# Git dává hooku JEDEN stdin. Chceme-li ho předat i řetězenému hooku
# (typicky `git lfs pre-push`, který čte tentýž seznam refů), musíme ho
# napřed odložit stranou. Dočasný SOUBOR, ne command substitution: ta podle
# playbooku není průhledný kanál a na msys se chová jinak než POSIX shell.
stdin_buf="${TMPDIR:-/tmp}/ums-prepush-$$"
cat > "$stdin_buf"
trap 'rm -f "$stdin_buf"' EXIT INT TERM

# Nespouští se, když tenhle hook push zamítá: k pushi nedojde, takže cizí
# hook nemá co dělat (LFS by zbytečně nahrávalo objekty).
run_chained() {
    [ -x "$chained" ] || return 0
    "$chained" "$@" < "$stdin_buf"
}
```

- [ ] **Step 4: Přesměruj hlavní smyčku na buffer a zakonči delegací**

Hlavní `while read` smyčka musí číst z bufferu, ne ze stdinu. Změň její zakončení z `done` na:

```sh
done < "$stdin_buf"

if [ "$reject" -ne 0 ]; then
    exit "$reject"
fi

run_chained "$@"
exit $?
```

Původní `exit $reject` na konci souboru odstraň — nahrazuje ho blok výše.

- [ ] **Step 5: Spusť sadu a ověř, že projde**

Run: `pwsh -NoProfile -File ums/.claude/hooks/tests/pre-push.tests.ps1`
Expected: PASS, včetně existující regrese na krádež stdinu (push více refů najednou).

- [ ] **Step 6: Ověř negativitu testu**

Dočasně změň v hooku `"$chained" "$@" < "$stdin_buf"` na `"$chained" "$@" < /dev/null` a spusť sadu znovu. Musí zčervenat aserce „cizí hook dostal přehraný stdin (1 ref)" a NE aserce „cizí hook byl skutečně zavolán". Pak soubor obnov z kopie pořízené před mutací a ověř prázdný `git diff -- ums/.claude/hooks/pre-push`.

- [ ] **Step 7: Commit**

```bash
git add ums/.claude/hooks/pre-push ums/.claude/hooks/tests/pre-push.tests.ps1
git commit -m "push-guard-jen-pro-agenty: hook bufferuje stdin a volá řetězený cizí hook

 - stdin do dočasného souboru, hlavní smyčka čte z něj
 - run_chained předá cizímu hooku argumenty i přehraný stdin
 - řetězený hook se nespouští, když push zamítáme
 - test kanárkem doloží běh i počet přijatých řádků"
git push
```

---

### Task 3: Instalátor odsouvá a řetězí cizí hook

**Files:**
- Modify: `ums/.claude/hooks/install-git-hooks.ps1` (blok instalace kolem řádku 592, `.DESCRIPTION`, výčet exit kódů)
- Test: `ums/.claude/hooks/tests/pre-push.tests.ps1`

**Interfaces:**
- Consumes: `run_chained` a jméno `pre-push.ums-chained` z Tasku 2.
- Produces: funkce `Move-ForeignHook` vracející hashtable `@{ Moved = <bool>; Path = <string>; Refused = <string|null> }`.

- [ ] **Step 1: Napiš selhávající testy**

Na konec `ums/.claude/hooks/tests/pre-push.tests.ps1`, před `Complete-Tests`:

```powershell
# ---------------------------------------------------------------------------
# Cizí hook (typicky Git LFS) se neodmítá, ale odsouvá a řetězí. Do sdíleného
# adresáře hooků se ale řetězit NESMÍ - přejmenování by tiše přesměrovalo
# každý repozitář, který tu cestu používá.
# ---------------------------------------------------------------------------
$rChain = Join-Path ([IO.Path]::GetTempPath()) ("mbchain-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
& git init -q -b develop $rChain | Out-Null
$foreign = Join-Path $rChain '.git/hooks/pre-push'
New-Item -ItemType Directory -Force -Path (Split-Path $foreign) | Out-Null
Set-Content -LiteralPath $foreign -Encoding ascii -Value "#!/bin/sh`nexit 0`n"
$res = Invoke-Installer $rChain $null
Assert-Eq $res.Code 0 'cizí hook: instalace uspěje řetězením, ne exitem 2'
Assert-True (Test-Path (Join-Path $rChain '.git/hooks/pre-push.ums-chained')) 'cizí hook: odsunut na .ums-chained'
Assert-Match $res.Flat 'chained' 'cizí hook: instalátor řetězení pojmenuje'
$ours = Get-Content -LiteralPath $foreign -TotalCount 5
Assert-Match ($ours -join "`n") 'UMS pre-push guard' 'cizí hook: na jeho místě je náš hook'

# Opakovaný běh nesmí přepsat už odsunutý cizí hook vlastním hookem.
$chainedBefore = Get-Content -LiteralPath (Join-Path $rChain '.git/hooks/pre-push.ums-chained') -Raw
$res = Invoke-Installer $rChain $null
$chainedAfter = Get-Content -LiteralPath (Join-Path $rChain '.git/hooks/pre-push.ums-chained') -Raw
Assert-Eq $chainedAfter $chainedBefore 'cizí hook: opakovaná instalace řetězený soubor nemění'
Assert-NotMatch $chainedAfter 'UMS pre-push guard' 'cizí hook: náš hook se nikdy nezřetězí sám se sebou'
Remove-Item -Recurse -Force $rChain

# Sdílený core.hooksPath: řetězení se odmítne, exit 2 zůstává.
$rShared = Join-Path ([IO.Path]::GetTempPath()) ("mbshared-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$sharedHooks = Join-Path $rShared 'shared-hooks'
New-Item -ItemType Directory -Force -Path $rShared, $sharedHooks | Out-Null
& git init -q -b develop $rShared | Out-Null
Set-Content -LiteralPath (Join-Path $sharedHooks 'pre-push') -Encoding ascii -Value "#!/bin/sh`nexit 0`n"
& git -C $rShared config core.hooksPath ($sharedHooks -replace '\\', '/') | Out-Null
$res = Invoke-Installer $rShared $null
Assert-Eq $res.Code 2 'sdílený core.hooksPath: řetězení odmítnuto, exit 2'
Assert-Match $res.Flat 'shared' 'sdílený core.hooksPath: instalátor pojmenuje důvod odmítnutí'
Assert-True (-not (Test-Path (Join-Path $sharedHooks 'pre-push.ums-chained'))) 'sdílený core.hooksPath: cizí hook zůstal nedotčený'
Remove-Item -Recurse -Force $rShared

# Ruční slepenec z dřívějšího ad-hoc obcházení exitu 2: náš kód je v těle
# cizího hooku hlouběji, než kam sahá kontrola identity. Rozplétat se nesmí.
$rMerged = Join-Path ([IO.Path]::GetTempPath()) ("mbmerged-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
& git init -q -b develop $rMerged | Out-Null
$mergedHook = Join-Path $rMerged '.git/hooks/pre-push'
New-Item -ItemType Directory -Force -Path (Split-Path $mergedHook) | Out-Null
Set-Content -LiteralPath $mergedHook -Encoding ascii -Value @"
#!/bin/sh
git lfs pre-push "`$@"
# ručně vlepeno kdysi dávno:
# UMS pre-push guard (Publication Contract)
exit 0
"@
$res = Invoke-Installer $rMerged $null
Assert-Eq $res.Code 2 'ruční slepenec: instalace se nepokouší rozplétat, exit 2'
Assert-Match $res.Flat 'hand-merged' 'ruční slepenec: instalátor pojmenuje, o co jde'
Assert-True (-not (Test-Path (Join-Path $rMerged '.git/hooks/pre-push.ums-chained'))) 'ruční slepenec: nic se neodsunulo'
Remove-Item -Recurse -Force $rMerged
```

- [ ] **Step 2: Spusť sadu a ověř, že selže**

Run: `pwsh -NoProfile -File ums/.claude/hooks/tests/pre-push.tests.ps1`
Expected: FAIL na „cizí hook: instalace uspěje řetězením, ne exitem 2" (dnes vrací 2).

- [ ] **Step 3: Přidej odsunovací funkci**

Do `ums/.claude/hooks/install-git-hooks.ps1` nad blok instalace:

```powershell
$CHAINED_SUFFIX = '.ums-chained'

# Odsune cizí pre-push stranou, aby ho náš hook mohl volat. NIKDY do
# sdíleného adresáře hooků: pod absolutním nebo globálním core.hooksPath tam
# leží hooky jiných repozitářů a přejmenování by je všechny tiše přesměrovalo
# na tenhle hook. Tam zůstává staré chování - nechat být a exit 2.
function Move-ForeignHook([string] $Path, [hashtable] $HooksPathCfg) {
    if ($HooksPathCfg -and ($HooksPathCfg.IsAbsolute -or $HooksPathCfg.Scope -in @('global', 'system'))) {
        return @{ Moved = $false; Path = $null; Refused = 'the hooks directory is shared with other repositories (core.hooksPath), so moving a foreign hook there would silently re-point every one of them' }
    }
    # Ruční slepenec: cizí hook, do kterého někdo kdysi vlepil náš kód, aby
    # obešel exit 2. Marker je schválně hledaný jen v prvních pěti řádcích, aby
    # se cizí hook zmiňující podobnou formulaci nepovažoval za náš - tady ale
    # potřebujeme opak, hlubší výskyt. Slepence se strojově rozplétat nedají.
    if ((Get-Content -LiteralPath $Path -Raw) -match [regex]::Escape($OURS_MARKER)) {
        return @{ Moved = $false; Path = $null; Refused = "this foreign hook contains UMS guard code deeper in its body - a hand-merged hook, which cannot be untangled mechanically; resolve it by hand" }
    }
    $dst = $Path + $CHAINED_SUFFIX
    if (Test-Path -LiteralPath $dst) {
        return @{ Moved = $false; Path = $dst; Refused = "a chained hook is already present at $dst - not overwriting it" }
    }
    Move-Item -LiteralPath $Path -Destination $dst
    $stamp = "# Chained by install-git-hooks.ps1 from $Path"
    Add-Content -LiteralPath $dst -Value $stamp
    return @{ Moved = $true; Path = $dst; Refused = $null }
}
```

- [ ] **Step 4: Zapoj ji do instalační smyčky**

V `foreach ($name in $HOOK_NAMES)` nahraď dnešní blok „SKIP: foreign hook" tímto:

```powershell
    if ((Test-Path $dst) -and -not (Test-IsOurHook $dst)) {
        $chain = Move-ForeignHook $dst $hooksPathCfg
        if (-not $chain.Moved) {
            Write-Host "SKIP: $dst already exists and is not the UMS hook - leaving it alone." -ForegroundColor Yellow
            Write-Host "      $($chain.Refused)" -ForegroundColor Yellow
            $skipped += @{ Name = $name; Path = $dst }
            continue
        }
        Write-Host "chained: foreign $name -> $($chain.Path) (our hook will call it)" -ForegroundColor Cyan
    }
```

- [ ] **Step 5: Spusť sadu a ověř, že projde**

Run: `pwsh -NoProfile -File ums/.claude/hooks/tests/pre-push.tests.ps1`
Expected: PASS.

- [ ] **Step 6: Ověř řetězení proti SKUTEČNÉMU LFS hooku, ne atrapě**

Fixtura dokazuje, že kód dělá to, co jsi do fixtury napsal; skutečný nástroj dokazuje, že to funguje na tvaru, který nikdo nevymyslel. Bez Git LFS na stroji krok přeskoč a ohlas to — nedělej z toho chybu.

```bash
git lfs version || echo "LFS není nainstalované — krok přeskočen, ohlas to v reportu"
```

Je-li LFS dostupné, ve throwaway klonu:

```bash
d=$(mktemp -d) && git init -q -b develop "$d" && git -C "$d" lfs install --local
head -3 "$d/.git/hooks/pre-push"
pwsh -NoProfile -File ums/.claude/hooks/install-git-hooks.ps1 -RepoRoot "$d"
head -3 "$d/.git/hooks/pre-push.ums-chained"
```

Expected: instalátor končí nulou a hlásí `chained:`; odsunutý soubor je skutečný LFS hook (`git lfs pre-push`); na místě původního souboru je náš hook. Výsledek zapiš do ledgeru.

- [ ] **Step 7: Doplň dokumentaci exit kódů v hlavičce skriptu**

V `.DESCRIPTION` u výčtu exit kódů přepiš popis kódu 2:

```text
      2  NOT installed: a foreign pre-push could not be chained - either the
         hooks directory is shared with other repositories (core.hooksPath is
         absolute or comes from global/system config) or a chained hook was
         already there. The foreign hook was left untouched and the guarantee
         is absent here.
```

- [ ] **Step 8: Commit**

```bash
git add ums/.claude/hooks/install-git-hooks.ps1 ums/.claude/hooks/tests/pre-push.tests.ps1
git commit -m "push-guard-jen-pro-agenty: instalátor cizí hook odsune a zřetězí

 - Move-ForeignHook přejmenuje cizí pre-push na .ums-chained a zapíše provenienci
 - řetězení odmítnuto u sdíleného core.hooksPath, tam zůstává exit 2
 - opakovaný běh řetězený soubor nepřepisuje a náš hook se nezřetězí sám se sebou
 - přepsán význam exit kódu 2 v hlavičce skriptu"
git push
```

---

### Task 4: Brána na značku agentní session

**Files:**
- Modify: `ums/.claude/hooks/pre-push` (za blok `run_chained` z Tasku 2)
- Modify: `ums/.claude/hooks/install-git-hooks.ps1` (funkce `Invoke-HookLine`)
- Modify: `ums/.claude/settings.json` (nový klíč `env`)
- Test: `ums/.claude/hooks/tests/pre-push.tests.ps1`

**Interfaces:**
- Consumes: `run_chained` z Tasku 2.
- Produces: shellovou funkci `is_agent_session`; instalátor nastavuje `MB_AGENT_SESSION=1` pro své důkazní běhy.

- [ ] **Step 1: Napiš selhávající párový test**

Na konec `ums/.claude/hooks/tests/pre-push.tests.ps1`, před `Complete-Tests`. Dvojice se liší JEN značkou — bez ní by sada nepoznala hook, který propouští vždy:

```powershell
# ---------------------------------------------------------------------------
# Brána na značku. Sada běží běžně UVNITŘ agentního sezení, takže značku zdědí
# z prostředí - no-marker případy by pak tiše testovaly opak. Odstraníme ji
# stejně, jako se výš izoluje GIT_CONFIG_GLOBAL, a nepřítomnost ověříme.
# ---------------------------------------------------------------------------
function Invoke-WithoutMarker([scriptblock] $Body) {
    $saved = @{}
    foreach ($n in @('MB_AGENT_SESSION', 'AI_AGENT', 'CLAUDECODE')) {
        $saved[$n] = [Environment]::GetEnvironmentVariable($n)
        Remove-Item "Env:$n" -ErrorAction SilentlyContinue
    }
    try { & $Body }
    finally {
        foreach ($n in $saved.Keys) {
            if ($null -ne $saved[$n]) { Set-Item "Env:$n" $saved[$n] }
        }
    }
}

function Invoke-WithMarker([scriptblock] $Body) {
    Invoke-WithoutMarker { $env:MB_AGENT_SESSION = '1'; try { & $Body } finally { Remove-Item Env:MB_AGENT_SESSION -ErrorAction SilentlyContinue } }
}

Invoke-WithoutMarker {
    Assert-Eq $env:MB_AGENT_SESSION $null 'izolace: značka je pro no-marker případy skutečně pryč'
}

Invoke-GitOk $work @('checkout', 'develop') | Out-Null
Add-Content -Path (Join-Path $work 'f.txt') -Value 'marker pair'
Invoke-GitOk $work @('commit', '-am', 'marker pair') | Out-Null
$developBeforePair = Get-Sha $origin 'refs/heads/develop'

# TÁŽ řádka refu dvakrát, liší se jen značka.
$withMarker = Invoke-WithMarker { Invoke-GitTry $work @('push', 'origin', 'develop') }
Assert-True ($withMarker.Code -ne 0) 'značka je: push na chráněnou větev zamítnut'
Assert-Eq (Get-Sha $origin 'refs/heads/develop') $developBeforePair 'značka je: remote se nepohnul'

$withoutMarker = Invoke-WithoutMarker { Invoke-GitTry $work @('push', 'origin', 'develop') }
Assert-Eq $withoutMarker.Code 0 'značka chybí: hook nevynucuje nic, push člověka projde'
Assert-Eq (Get-Sha $origin 'refs/heads/develop') (Get-Sha $work 'develop') 'značka chybí: remote se posunul'
```

- [ ] **Step 2: Spusť sadu a ověř, že selže**

Run: `pwsh -NoProfile -File ums/.claude/hooks/tests/pre-push.tests.ps1`
Expected: FAIL na „značka chybí: hook nevynucuje nic, push člověka projde" (dnes zamítne bez ohledu na značku).

- [ ] **Step 3: Přidej bránu do hooku**

Do `ums/.claude/hooks/pre-push` hned za definici `run_chained`:

```sh
# Vrstva si značku injektuje sama do konfigurace každého harnesse. Proměnné
# AI_AGENT/CLAUDECODE jsou fallback jen pro Claude Code - vlastní je někdo
# jiný a v jiných harnessech nejsou vůbec.
is_agent_session() {
    [ "$MB_AGENT_SESSION" = "1" ] && return 0
    [ -n "$AI_AGENT" ] && return 0
    [ "$CLAUDECODE" = "1" ] && return 0
    return 1
}

# Člověk v terminálu ani v IDE nemá poznat, že tenhle hook existuje. NENÍ to
# `exit 0`: řetězený cizí hook (LFS) musí doběhnout, jinak by instalace téhle
# vrstvy vypnula LFS všem lidem v týmu.
if ! is_agent_session; then
    run_chained "$@"
    exit $?
fi
```

- [ ] **Step 4: Nastav značku pro důkazní běhy instalátoru**

Bez toho hook v důkazu legitimně projde a instalátor spuštěný člověkem z terminálu bude hlásit „PROOF FAILED" pokaždé. V `ums/.claude/hooks/install-git-hooks.ps1` ve funkci `Invoke-HookLine` změň sestavení příkazu — prefix proměnné patří na příkaz spouštějící HOOK, ne na `printf`:

```powershell
    $script = 'cd "$3" && printf "%s\n" "$1" | MB_AGENT_SESSION=1 "$2" origin ums-install-verify'
```

- [ ] **Step 5: Napiš test na důkaz bez značky v prostředí**

Na konec sady, před `Complete-Tests`:

```powershell
# Ruční instalace člověkem z terminálu - prostředí značku nemá. Instalátor si
# ji pro důkazní běhy nastavuje sám, jinak by o funkčním hooku hlásil, že
# záruka není potvrzená.
$rProof = Join-Path ([IO.Path]::GetTempPath()) ("mbproof-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
& git init -q -b develop $rProof | Out-Null
$res = Invoke-WithoutMarker { Invoke-Installer $rProof $null }
Assert-Eq $res.Code 0 'self-test: instalace z prostředí bez značky končí kódem 0'
Assert-Match $res.Flat 'installed \+ verified live' 'self-test: hook je ověřený i bez značky v prostředí instalátoru'
Remove-Item -Recurse -Force $rProof
```

- [ ] **Step 6: Přidej klíč env do settings.json**

Do `ums/.claude/settings.json` na nejvyšší úroveň:

```json
  "env": {
    "MB_AGENT_SESSION": "1"
  },
```

- [ ] **Step 7: Spusť sadu a ověř, že projde**

Run: `pwsh -NoProfile -File ums/.claude/hooks/tests/pre-push.tests.ps1`
Expected: PASS.

- [ ] **Step 8: Ověř negativitu**

Dočasně smaž z hooku tři řádky `if ! is_agent_session; then … fi`. Musí zčervenat aserce „značka chybí: hook nevynucuje nic" a NESMÍ zčervenat „značka je: push na chráněnou větev zamítnut". Pak obnov ze zálohy a ověř prázdný `git diff -- ums/.claude/hooks/pre-push`.

- [ ] **Step 9: Commit**

```bash
git add ums/.claude/hooks/pre-push ums/.claude/hooks/install-git-hooks.ps1 ums/.claude/settings.json ums/.claude/hooks/tests/pre-push.tests.ps1
git commit -m "push-guard-jen-pro-agenty: hook vynucuje jen v agentní session

 - is_agent_session čte MB_AGENT_SESSION, fallback AI_AGENT a CLAUDECODE
 - bez značky hook deleguje na řetězený hook a nic nevynucuje
 - self-test instalátoru si značku pro důkazní běhy nastavuje sám
 - settings.json značku injektuje klíčem env
 - párový test lišící se jen značkou plus izolace značky v sadě"
git push
```

---

### Task 5: Pravidlo obsahu na chráněné větvi

**Files:**
- Modify: `ums/.claude/hooks/pre-push` (větev `is_protected` v hlavní smyčce)
- Test: `ums/.claude/hooks/tests/pre-push.tests.ps1`

**Interfaces:**
- Consumes: `is_agent_session` z Tasku 4, `remote_name` a `zero` z hlavičky hooku.
- Produces: shellovou funkci `is_integration_push <local_sha> <remote_sha>` (návratový kód 0 = integrace).

- [ ] **Step 1: Napiš selhávající testy**

Na konec sady, před `Complete-Tests`:

```powershell
# ---------------------------------------------------------------------------
# Pravidlo obsahu: na chráněné větvi projde fast-forward na commity, které už
# JSOU na cílovém remote. Dosažitelnost se omezuje na remote, do kterého se
# pushuje - tenhle fork má druhý remote (vanila), takže commit dosažitelný jen
# tam by jinak prošel jako publikovaný.
# ---------------------------------------------------------------------------
Invoke-GitOk $work @('checkout', 'feature/x') | Out-Null
Add-Content -Path (Join-Path $work 'g.txt') -Value 'to be integrated'
Invoke-GitOk $work @('commit', '-am', 'integrace') | Out-Null
Invoke-WithMarker { Invoke-GitOk $work @('push', 'origin', 'feature/x') } | Out-Null

# a) FF na commit, který na originu už je -> projde
$r = Invoke-WithMarker { Invoke-GitTry $work @('push', 'origin', 'HEAD:develop') }
Assert-Eq $r.Code 0 'obsah: FF push commitu už publikovaného na originu projde'
Assert-Match $r.Out 'UMS' 'obsah: povolená integrace je ohlášená, ne tichá'
Assert-Eq (Get-Sha $origin 'refs/heads/develop') (Get-Sha $work 'feature/x') 'obsah: develop se posunul na integrovaný commit'

# b) FF na commit, který na originu NENÍ -> zamítnuto
Add-Content -Path (Join-Path $work 'g.txt') -Value 'nepublikovano'
Invoke-GitOk $work @('commit', '-am', 'nepublikovany commit') | Out-Null
$developBeforeUnpub = Get-Sha $origin 'refs/heads/develop'
$r = Invoke-WithMarker { Invoke-GitTry $work @('push', 'origin', 'HEAD:develop') }
Assert-True ($r.Code -ne 0) 'obsah: FF push nepublikovaného commitu zamítnut'
Assert-Eq (Get-Sha $origin 'refs/heads/develop') $developBeforeUnpub 'obsah: develop se po zamítnutí nepohnul'

# c) commit dosažitelný jen na JINÉM remote se nepočítá
$other = Join-Path $root 'other.git'
& git init --bare -q -b develop $other | Out-Null
Invoke-GitOk $work @('remote', 'add', 'vanila', $other) | Out-Null
Invoke-WithMarker { Invoke-GitOk $work @('push', 'vanila', 'HEAD:refs/heads/parkoviste') } | Out-Null
$r = Invoke-WithMarker { Invoke-GitTry $work @('push', 'origin', 'HEAD:develop') }
Assert-True ($r.Code -ne 0) 'obsah: dosažitelnost na jiném remote se nepočítá'
```

- [ ] **Step 2: Spusť sadu a ověř, že selže**

Run: `pwsh -NoProfile -File ums/.claude/hooks/tests/pre-push.tests.ps1`
Expected: FAIL na „obsah: FF push commitu už publikovaného na originu projde" (dnes zamítne každý push na chráněnou větev).

- [ ] **Step 3: Přidej funkci pravidla obsahu**

Do `ums/.claude/hooks/pre-push` k ostatním funkcím, nad hlavní smyčku:

```sh
# Integrace = posun ukazatele chráněné větve na commity, které na TOMTO remote
# už jsou. Dokazuje publikaci, NE prohlédnutí: agent smí pushovat vlastní
# tiketovou větev, takže si dosažitelnost umí vyrobit. Pravidlo aktéra drží
# PreToolUse guard, ne tenhle hook (viz Publication Contract).
#
# Oba podpříkazy mají uzavřený stdin - hlavní smyčka čte seznam refů a příkaz,
# který z něj ukousne, by hook tiše umlčel na zbytku refů.
is_integration_push() {
    _local="$1"
    _remote="$2"
    [ "$_local" = "$zero" ] && return 1
    [ "$_remote" = "$zero" ] && return 1
    git merge-base --is-ancestor "$_remote" "$_local" </dev/null 2>/dev/null || return 1
    _refs=$(git for-each-ref --contains "$_local" --format='%(refname)' \
        "refs/remotes/$remote_name/" </dev/null 2>/dev/null)
    [ -n "$_refs" ]
}
```

- [ ] **Step 4: Zapoj ji do větve chráněné větve**

V hlavní smyčce nahraď dnešní `else` větev pod `if [ "$UMS_ALLOW_SHARED_PUSH" = "1" ]`:

```sh
        elif is_integration_push "$local_sha" "$remote_sha"; then
            echo "UMS: '$b' — fast-forward na commity už publikované na '$remote_name', push povolen." >&2
        else
            echo "UMS: '$b' je sdílená větev — projde jen fast-forward na commity, které už jsou" >&2
            echo "     na '$remote_name' (Publication Contract). Nejdřív publikuj svoji větev." >&2
            echo "     Vědomá výjimka člověka: \`! MB_HUMAN_PUSH=1 git push $remote_name HEAD:$b\`;" >&2
            echo "     agent ji nikdy nenastavuje." >&2
            reject=1
            continue
        fi
```

- [ ] **Step 5: Spusť sadu a ověř, že projde**

Run: `pwsh -NoProfile -File ums/.claude/hooks/tests/pre-push.tests.ps1`
Expected: PASS.

- [ ] **Step 6: Ověř negativitu**

Dočasně smaž z `is_integration_push` řádek s `git for-each-ref` a nahraď ho `_refs=x`. Musí zčervenat aserce „obsah: FF push nepublikovaného commitu zamítnut" i „obsah: dosažitelnost na jiném remote se nepočítá". Obnov a ověř prázdný diff.

- [ ] **Step 7: Commit**

```bash
git add ums/.claude/hooks/pre-push ums/.claude/hooks/tests/pre-push.tests.ps1
git commit -m "push-guard-jen-pro-agenty: pravidlo obsahu místo pravidla aktéra v hooku

 - is_integration_push: fast-forward plus dosažitelnost na remote, do kterého se pushuje
 - dosažitelnost omezena na refs/remotes/<remote>/, jiný remote se nepočítá
 - oba podpříkazy s uzavřeným stdinem kvůli hlavní smyčce
 - zamítací hláška vede na publikaci vlastní větve, ne na výjimku"
git push
```

---

### Task 6: Lidská výjimka MB_HUMAN_PUSH a její protějšek v guardu

**Files:**
- Modify: `ums/.claude/hooks/pre-push` (za bránu na značku)
- Modify: `ums/.claude/hooks/guard-git-push.mjs` (konstanta `HUMAN_ESCAPE_RE` a její použití, funkce `evaluatePush`)
- Test: `ums/.claude/hooks/tests/pre-push.tests.ps1`, `ums/.claude/hooks/tests/guard-git-push.tests.ps1`

**Interfaces:**
- Consumes: `run_chained` z Tasku 2, `is_agent_session` z Tasku 4.
- Produces: shellovou proměnnou `human_escape`; v guardu funkci `carriesHumanEscape(command)`.

- [ ] **Step 1: Napiš selhávající testy pro hook**

Na konec `pre-push.tests.ps1`, před `Complete-Tests`:

```powershell
# ---------------------------------------------------------------------------
# Lidská výjimka zvedá CELÝ guard - sdílenou větev, mazání i force push.
# Mechanickou pojistku proti zneužití agentem drží PreToolUse guard, ne
# zúžení téhle proměnné.
# ---------------------------------------------------------------------------
function Invoke-WithHumanPush([string] $VarName, [scriptblock] $Body) {
    Invoke-WithMarker {
        Set-Item "Env:$VarName" '1'
        try { & $Body } finally { Remove-Item "Env:$VarName" -ErrorAction SilentlyContinue }
    }
}

Invoke-GitOk $work @('checkout', 'feature/x') | Out-Null
$r = Invoke-WithHumanPush 'MB_HUMAN_PUSH' { Invoke-GitTry $work @('push', '--force', 'origin', 'HEAD:feature/x') }
Assert-Eq $r.Code 0 'výjimka: force push vlastní větve s MB_HUMAN_PUSH projde'
Assert-Match $r.Out 'MB_HUMAN_PUSH' 'výjimka: povolení je ohlášené na stderr'

$r = Invoke-WithHumanPush 'UMS_ALLOW_SHARED_PUSH' { Invoke-GitTry $work @('push', 'origin', 'HEAD:develop') }
Assert-Eq $r.Code 0 'výjimka: staré jméno je přechodně stále přijímané'
Assert-Match $r.Out 'MB_HUMAN_PUSH' 'výjimka: staré jméno hlásí, že je zastaralé, a jmenuje nové'
```

- [ ] **Step 2: Spusť sadu a ověř, že selže**

Run: `pwsh -NoProfile -File ums/.claude/hooks/tests/pre-push.tests.ps1`
Expected: FAIL na „výjimka: force push vlastní větve s MB_HUMAN_PUSH projde".

- [ ] **Step 3: Nahraď starou výjimku v hooku**

Do `ums/.claude/hooks/pre-push` hned za bránu `is_agent_session`:

```sh
# Jediný jednotný východ pro člověka: zvedá celý guard, ne jedno pravidlo.
# Jakmile hook platí jen v agentní session, nese značku i člověk, který si
# v sezení rebasuje vlastní tiketovou větev - s úzkou výjimkou by mu nezbylo
# než vypnout hooky úplně. Agent ji podle kontraktu nenastavuje nikdy.
human_escape=0
if [ "$MB_HUMAN_PUSH" = "1" ]; then
    human_escape=1
elif [ "$UMS_ALLOW_SHARED_PUSH" = "1" ]; then
    human_escape=1
    echo "UMS: UMS_ALLOW_SHARED_PUSH je zastaralé jméno — používej MB_HUMAN_PUSH=1." >&2
fi

if [ "$human_escape" = "1" ]; then
    echo "UMS: MB_HUMAN_PUSH=1 — vědomá výjimka člověka, guard je pro tenhle push zvednutý." >&2
    run_chained "$@"
    exit $?
fi
```

Ze staré větve v hlavní smyčce odstraň celý blok `if [ "$UMS_ALLOW_SHARED_PUSH" = "1" ]` včetně jeho `echo` — rozhodnutí padlo výš.

- [ ] **Step 4: Spusť sadu a ověř, že projde**

Run: `pwsh -NoProfile -File ums/.claude/hooks/tests/pre-push.tests.ps1`
Expected: PASS. Existující aserce, které tvrdí, že výjimka NEzvedá mazání a force push, se ruší — jsou to nálezy k přepsání, ne regrese; nahraď je asercemi z kroku 1.

- [ ] **Step 5: Napiš selhávající test pro guard**

Na konec `guard-git-push.tests.ps1`, před `Complete-Tests`:

```powershell
# Přes guard chodí jen volání agenta (vykřičníkové příkazy člověka ne, ověřeno
# v Tasku 1). Agent výjimku podle kontraktu nenastavuje nikdy, takže její
# výskyt je sám o sobě porušením - a jediná mechanická pojistka, která zbývá,
# když hook výjimkou zvedá všechno.
$r = Invoke-Guard '{"tool_input":{"command":"MB_HUMAN_PUSH=1 git push origin HEAD:develop"},"cwd":"' + $cwdJson + '"}'
Assert-Match $r 'deny' 'guard zamítne agentní push nesoucí lidskou výjimku'
Assert-Match $r 'MB_HUMAN_PUSH' 'zamítnutí pojmenuje proměnnou, kvůli které padlo'
```

Jméno helperu `Invoke-Guard` a proměnné `$cwdJson` převezmi z hlavičky té sady; existující případy tvrdící opak (výjimka propouští) přepiš.

- [ ] **Step 6: Uprav guard**

V `ums/.claude/hooks/guard-git-push.mjs` nahraď dnešní blok

```js
  if (HUMAN_ESCAPE_RE.test(command)) process.exit(0);
```

tímto:

```js
  // Dřív tenhle blok celý příkaz PROPOUŠTĚL, protože vrstva uživateli podávala
  // příkaz s výjimkou a vlastní guard by mu ho zamítl. To padlo: vykřičníkové
  // příkazy člověka sem nedorazí, takže cokoli s výjimkou, co sem přijde, je
  // volání agenta - a to je porušení kontraktu, ne publikace člověkem.
  if (HUMAN_ESCAPE_RE.test(command)) {
    deny(
      'UMS: `MB_HUMAN_PUSH` je vědomá výjimka ČLOVĚKA a agent ji nikdy nenastavuje ' +
        '(Publication Contract). Připrav příkaz a nech ho uživateli.',
    );
  }
```

A rozšiř regulární výraz o obě jména:

```js
const HUMAN_ESCAPE_RE = /(^|\s)(MB_HUMAN_PUSH|UMS_ALLOW_SHARED_PUSH)=1(\s|$)/;
```

- [ ] **Step 7: Napiš selhávající test na fail-closed větev guardu**

Guard nově nese skutečné pravidlo, takže nesmí propouštět push, kterému nerozumí. Zpřísnění se týká JEN rozpoznaného podpříkazu `push` — bezkontextové kontroly zůstávají fail-open, jinak by se množily falešné poplachy na obsahu dokumentů (guard takhle zamítl zápis vlastního návrhu tohoto plánu). Na konec `guard-git-push.tests.ps1`, před `Complete-Tests`:

```powershell
# Rozpoznaný push, kterému guard nerozumí, se nově zamítá. Dřív procházel.
$r = Invoke-Guard '{"tool_input":{"command":"git push --mirror origin"},"cwd":"' + $cwdJson + '"}'
Assert-Match $r 'deny' 'guard zamítne rozpoznaný push s neznámým přepínačem'

$r = Invoke-Guard '{"tool_input":{"command":"git push origin a:b c:d"},"cwd":"' + $cwdJson + '"}'
Assert-Match $r 'deny' 'guard zamítne rozpoznaný push s víc refspecy, kterým nerozumí'

# Kontrolní případ: jasně neškodný push na nechráněnou větev musí dál projít,
# jinak by fail-closed zamítal všechno a asercie výš by nic nedokazovaly.
$r = Invoke-Guard '{"tool_input":{"command":"git push -u origin feature/x"},"cwd":"' + $cwdJson + '"}'
Assert-NotMatch $r 'deny' 'kontrola: srozumitelný push na nechráněnou větev prochází'

# Nerozpoznaný tvar propouští dál - zbytkový průchod přiznaný v návrhu.
$r = Invoke-Guard '{"tool_input":{"command":"echo git push --mirror"},"cwd":"' + $cwdJson + '"}'
Assert-NotMatch $r 'deny' 'zbytkový průchod: nerozpoznaný tvar guard nezamítá'
```

- [ ] **Step 8: Spusť sadu a ověř, že selže**

Run: `pwsh -NoProfile -File ums/.claude/hooks/tests/guard-git-push.tests.ps1`
Expected: FAIL na „guard zamítne rozpoznaný push s neznámým přepínačem" (dnes vrací `{ deny: false }`).

- [ ] **Step 9: Obrať degradaci ve funkci evaluatePush**

V `ums/.claude/hooks/guard-git-push.mjs` nahraď obě fail-open návratové hodnoty ve `evaluatePush`:

```js
  const unparseable = (what) => ({
    deny: true,
    reason:
      `UMS: tenhle push neumím spolehlivě přečíst (${what}), a protože nesu pravidlo o tom, ` +
      'kdo smí pushovat do sdílené větve, radši ho zamítám (Publication Contract). ' +
      'Napiš ho srozumitelně: `git push [-u] <remote> <ref>[:<ref>]`.',
  });

  if (flags.some((f) => !PUSH_ALLOWED_FLAGS.has(f))) return unparseable('neznámý přepínač');
```

a dál v téže funkci:

```js
    if (!REMOTE_RE.test(remote)) return unparseable('nesrozumitelné jméno remote');
```

```js
    } else {
      return unparseable('víc nebo poškozené refspecy');
    }
```

Funkce `evaluateFetch` i bezkontextová kontrola zůstávají beze změny.

- [ ] **Step 10: Spusť obě sady a ověř, že projdou**

Run: `pwsh -NoProfile -File ums/.claude/hooks/tests/guard-git-push.tests.ps1`
Run: `pwsh -NoProfile -File ums/.claude/hooks/tests/pre-push.tests.ps1`
Expected: PASS obě. Existující aserce tvrdící, že nerozparsovatelný push PROCHÁZÍ, jsou nálezy k přepsání — nahraď je asercemi z kroku 7.

- [ ] **Step 11: Commit**

```bash
git add ums/.claude/hooks/pre-push ums/.claude/hooks/guard-git-push.mjs ums/.claude/hooks/tests/
git commit -m "push-guard-jen-pro-agenty: jednotná lidská výjimka MB_HUMAN_PUSH

 - výjimka zvedá celý guard hooku včetně mazání a force pushe
 - staré jméno přechodně přijímané s hláškou o zastaralosti
 - guard naopak push s výjimkou zamítá, protože přes něj chodí jen volání agenta
 - guard zamítá i rozpoznaný push, kterému nerozumí; nerozpoznané tvary dál propouští
 - přepsány aserce tvrdící starý úzký rozsah výjimky a fail-open chování"
git push
```

---

### Task 7: Verze hooku a sebekontrola v sezení

**Files:**
- Modify: `ums/.claude/hooks/pre-push` (druhý řádek hlavičky)
- Modify: `ums/.claude/settings.json` (`hooks.SessionStart`)
- Modify: `ums/.claude/skills/shared/overlays/finishing-a-development-branch.overlay.md`
- Modify: `ums/.claude/skills/mb-state/SKILL.md`
- Test: `ums/.claude/hooks/tests/pre-push.tests.ps1`

**Interfaces:**
- Consumes: `is_agent_session` z Tasku 4.
- Produces: řetězec verze `UMS pre-push guard (Publication Contract) v2` na druhém řádku hooku, podle kterého se pozná potřeba upgradu.

- [ ] **Step 1: Napiš selhávající test na verzi**

```powershell
# Identita hooku (prvních pět řádků) se NESMÍ změnit - instalátor podle ní
# pozná svůj vlastní hook. Kdyby ji nová verze přepsala, stará by se
# vyhodnotila jako CIZÍ hook a zřetězila se, místo aby se přepsala.
$hookSrc = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\pre-push') -TotalCount 5
Assert-Match ($hookSrc -join "`n") 'UMS pre-push guard \(Publication Contract\)' 'hlavička hooku si drží identitu pro instalátor'
Assert-Match ($hookSrc -join "`n") 'v2' 'hlavička hooku nese verzi, podle které jde poznat potřeba upgradu'
```

- [ ] **Step 2: Spusť sadu a ověř, že selže**

Run: `pwsh -NoProfile -File ums/.claude/hooks/tests/pre-push.tests.ps1`
Expected: FAIL na asercii o verzi.

- [ ] **Step 3: Doplň verzi do hlavičky**

Druhý řádek `ums/.claude/hooks/pre-push` změň na:

```sh
# UMS pre-push guard (Publication Contract) v2
```

- [ ] **Step 4: Spusť sadu a ověř, že projde**

Run: `pwsh -NoProfile -File ums/.claude/hooks/tests/pre-push.tests.ps1`
Expected: PASS.

- [ ] **Step 5: Přesuň sebekontrolu do SessionStart**

V `ums/.claude/settings.json` v `hooks.SessionStart` rozšiř `additionalContext` o větu (celý řetězec zůstává jednořádkový JSON):

```text
Ověř, že publikační záruka platí na tuhle session: `git rev-parse --git-path hooks/pre-push` musí existovat, nést v prvních pěti řádcích `UMS pre-push guard (Publication Contract) v2` a syntetický pipe chráněné větve musí v TOMTO prostředí skončit nenulově. Chybí-li hook nebo je starší než v2, spusť `pwsh -NoProfile -File .claude/hooks/install-git-hooks.ps1 -RepoRoot .` a ověř znovu; projde-li syntetický pipe nulou, značka agentní session v tomhle harnessu chybí a záruka na tebe neplatí — ohlas to uživateli a nepokračuj v práci, která končí pushem.
```

- [ ] **Step 6: Zopakuj kontrolu fail-closed na začátku finishing overlay**

Do `ums/.claude/skills/shared/overlays/finishing-a-development-branch.overlay.md` na začátek overlay bloku, před první existující bod:

```markdown
- **Publication guarantee self-check (fail-closed, before anything else).**
  A session that resumes a pinned work item never passed the brainstorming
  entry gate, and this is the session that integrates. Re-run the gate's hook
  check here IN THIS SESSION'S ENVIRONMENT (contract, Workspace Discipline):
  the resolved `pre-push` must exist, carry
  `UMS pre-push guard (Publication Contract) v2` within its first five lines,
  and reject a synthetic protected-branch line. A synthetic line that PASSES
  means the agent-session marker is absent here, so the guarantee does not
  apply to this session — STOP and report; do not integrate.
```

- [ ] **Step 7: Rozšiř řádek Workspace v mb-state**

V `ums/.claude/skills/mb-state/SKILL.md` v sekci gather, u kontroly hooku, doplň za odstavec o markeru:

```markdown
  - The hook's own VERSION and whether the guarantee applies to THIS session:
    the first five lines must carry `UMS pre-push guard (Publication Contract) v2`,
    and the synthetic-pipe check must be run **with `MB_AGENT_SESSION=1` set**,
    because the hook deliberately enforces nothing outside an agent session
    (Publication Contract). A hook that passes the synthetic line while the
    marker IS set is a missing guarantee; one that passes without it is
    correct behaviour, not a finding.
```

A do šablony reportu na řádek `Workspace:` přidej alternativu `⚠️ pre-push je starší verze než v2 (spusť install-git-hooks.ps1)`.

- [ ] **Step 8: Commit**

```bash
git add ums/.claude/hooks/pre-push ums/.claude/settings.json ums/.claude/skills/shared/overlays/finishing-a-development-branch.overlay.md ums/.claude/skills/mb-state/SKILL.md ums/.claude/hooks/tests/pre-push.tests.ps1
git commit -m "push-guard-jen-pro-agenty: verze hooku a sebekontrola v každém sezení

 - hlavička nese v2 při zachované identitě pro instalátor
 - SessionStart ověřuje záruku v prostředí sezení a nabízí upgrade
 - finishing overlay opakuje kontrolu fail-closed před integrací
 - mb-state hlásí verzi hooku a spouští syntetický pipe se značkou"
git push
```

---

### Task 8: Injektáž značky do ne-Claude harnessů

**Files:**
- Modify: `ums/sync-with-monorepo.ps1` (blok deploye glue artefaktů kolem řádku 300)
- Test: `ums/.claude/hooks/tests/sync-marker.tests.ps1` (nový soubor; `_assert.ps1` v tomto adresáři už je, nekopíruj ho znovu)

**Interfaces:**
- Consumes: konstantu `MB_AGENT_SESSION` z Tasku 4.
- Produces: funkci `Set-AgentMarker([string] $ConfigDir, [string] $Agent)` zapisující značku do konfigurace daného harnesse.

- [ ] **Step 1: Napiš selhávající test**

Nový soubor `ums/.claude/hooks/tests/sync-marker.tests.ps1`:

```powershell
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '_assert.ps1')
$ErrorActionPreference = 'Stop'

# Bez značky se hook v daném harnessu sám vypne, takže by tam agent běžel
# úplně bez dozoru - ne jen bez předběžného varování. settings.json se na
# ne-Claude cíle záměrně nenasazuje, proto vlastní injektáž.
. (Join-Path $PSScriptRoot '..\..\..\sync-with-monorepo.ps1') -DotSourceOnly

foreach ($agent in @('codex', 'gemini', 'kilocode')) {
    $dir = Join-Path ([IO.Path]::GetTempPath()) ("mbmarker-$agent-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    Set-AgentMarker $dir $agent
    $written = (Get-ChildItem -Recurse -File $dir | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n"
    Assert-Match $written 'MB_AGENT_SESSION' "$agent`: značka je zapsaná do konfigurace harnesse"
    # Opakovaný běh nesmí značku duplikovat.
    Set-AgentMarker $dir $agent
    $again = (Get-ChildItem -Recurse -File $dir | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n"
    Assert-Eq ([regex]::Matches($again, 'MB_AGENT_SESSION').Count) 1 "$agent`: opakovaný běh značku neduplikuje"
    Remove-Item -Recurse -Force $dir
}

Complete-Tests
```

- [ ] **Step 2: Spusť sadu a ověř, že selže**

Run: `pwsh -NoProfile -File ums/.claude/hooks/tests/sync-marker.tests.ps1`
Expected: FAIL — `Set-AgentMarker` neexistuje a `-DotSourceOnly` skript nezná.

- [ ] **Step 3: Přidej přepínač pro dot-sourcing do sync skriptu**

Do bloku `param(...)` v `ums/sync-with-monorepo.ps1` přidej:

```powershell
    [switch] $DotSourceOnly,
```

A hned za `param(...)` blok:

```powershell
# Testy potřebují jen definice funkcí, ne běh celé synchronizace.
if ($DotSourceOnly) { return }
```

Pozor: `return` musí být až za definicemi funkcí, pokud jsou funkce definované níž. Umísti ho na první řádek imperativní části skriptu, tedy pod poslední `function`.

- [ ] **Step 4: Napiš injektážní funkci**

Do `ums/sync-with-monorepo.ps1` k ostatním funkcím:

```powershell
$AGENT_MARKER_NAME = 'MB_AGENT_SESSION'

# Značka agentní session musí dorazit do KAŽDÉHO harnesse, jinak se v něm
# pre-push hook sám vypne a agent tam běží bez záruky. settings.json je
# registrační formát Claude Code a na ostatní cíle se nenasazuje, takže se
# značka zapisuje do jejich vlastní konfigurace. Zápis je idempotentní -
# opakovaný deploy nesmí seznam nafukovat.
function Set-AgentMarker([string] $ConfigDir, [string] $Agent) {
    $file = switch ($Agent) {
        'codex'    { Join-Path $ConfigDir 'config.toml' }
        'gemini'   { Join-Path $ConfigDir 'settings.json' }
        'kilocode' { Join-Path $ConfigDir 'settings.json' }
        default    { throw "Set-AgentMarker: unsupported agent '$Agent'" }
    }
    New-Item -ItemType Directory -Force -Path (Split-Path $file) | Out-Null
    if ((Test-Path -LiteralPath $file) -and ((Get-Content -LiteralPath $file -Raw) -match $AGENT_MARKER_NAME)) {
        return
    }
    if ([IO.Path]::GetExtension($file) -eq '.toml') {
        Add-Content -LiteralPath $file -Value "`n[env]`n$AGENT_MARKER_NAME = `"1`""
        return
    }
    $json = if (Test-Path -LiteralPath $file) { Get-Content -LiteralPath $file -Raw | ConvertFrom-Json } else { [pscustomobject]@{} }
    if (-not $json.PSObject.Properties.Name.Contains('env')) {
        $json | Add-Member -NotePropertyName 'env' -NotePropertyValue ([pscustomobject]@{})
    }
    $json.env | Add-Member -NotePropertyName $AGENT_MARKER_NAME -NotePropertyValue '1' -Force
    $json | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $file -Encoding utf8
}
```

- [ ] **Step 5: Zavolej ji z deploye glue artefaktů**

V bloku, který dnes vypisuje „settings.json not deployed (Claude Code registration format)", přidej za tu hlášku:

```powershell
        Set-AgentMarker $ConfigDir $Agent
        Write-Host "note: agent-session marker ($AGENT_MARKER_NAME) written into '$Agent' config - without it the pre-push guard disables itself there." -ForegroundColor DarkGray
```

- [ ] **Step 6: Spusť sadu a ověř, že projde**

Run: `pwsh -NoProfile -File ums/.claude/hooks/tests/sync-marker.tests.ps1`
Expected: PASS, 6 asercí.

- [ ] **Step 7: Commit**

```bash
git add ums/sync-with-monorepo.ps1 ums/.claude/hooks/tests/sync-marker.tests.ps1
git commit -m "push-guard-jen-pro-agenty: značka se injektuje i do ne-Claude harnessů

 - Set-AgentMarker zapíše MB_AGENT_SESSION do konfigurace codexu, gemini a kilocode
 - zápis idempotentní, TOML i JSON tvar
 - bez značky by se hook v daném harnessu sám vypnul a agent by běžel bez záruky"
git push
```

---

### Task 9: Přepis kontraktu

**Files:**
- Modify: `ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md` (hlavička s verzí, sekce Publication Contract, Workspace Discipline, Repository Configuration)

**Interfaces:**
- Consumes: chování implementované v Tasku 2 až 8 — kontrakt je popisuje, nevymýšlí.
- Produces: kontrakt verze 2.11, na který odkazují všechny skilly.

- [ ] **Step 1: Bumpni verzi a doplň historii**

V hlavičce dokumentu přeformuluj řádek, který byl current předtím, a přidej nový:

```markdown
- Supersedes v2.10 (rewrites the Publication Contract's two-tier push policy
  into an actor/content split, renames the human escape to `MB_HUMAN_PUSH`
  and widens it, and makes the workspace hook check session-scoped).
- v2.10 superseded v2.9 (added the Agentic Design Opposition section).
```

Konvenci ověř přečtením alespoň dvou historických položek pod místem vkládání.

- [ ] **Step 2: Přepiš tabulku dvouúrovňové push policy**

V sekci Publication Contract nahraď dnešní tabulku:

```markdown
**Two enforcement questions, two layers:**

| Layer | Question | Reach |
|---|---|---|
| The git `pre-push` hook | **What** is pushed | Anything running in an agent session, including commands the user types with a leading `!` |
| `guard-git-push.mjs` (PreToolUse) | **Who** pushes | The agent's own tool calls only; commands the user types with `!` never reach it |

The hook enforces NOTHING outside an agent session (marker `MB_AGENT_SESSION`;
`AI_AGENT` / `CLAUDECODE` are a Claude-Code-only fallback), so a human pushing
from a terminal or an IDE is untouched. Inside an agent session it allows, on a
protected branch, only a **fast-forward push whose tip is already reachable on
the remote being pushed to** — a pointer move onto commits that remote already
has.

**That is a guarantee of auditability, not of review.** Tier 1 lets the agent
publish its own ticket branch unassisted, so it can make any commit reachable
on `origin` and then fast-forward the base onto it. The rule that the MOMENT of
integration belongs to the human is carried by the PreToolUse layer alone —
therefore only in harnesses that have one, and only for command shapes it can
parse. Elsewhere it is a contract obligation like every other rule of this
layer, and server-side branch permissions remain the real backstop.
```

- [ ] **Step 3: Přepiš odstavec o lidské výjimce**

```markdown
**The human escape: `MB_HUMAN_PUSH=1`.** It means "a human takes
responsibility for THIS push" and lifts the whole guard — the protected-branch
rule, the deletion ban and the force-push ban alike. The wide scope is
deliberate: once the hook enforces only inside an agent session, a human
rebasing their OWN ticket branch in-session carries the marker too, and a
narrow escape would leave them nothing but disabling hooks entirely. The
mechanical containment against an agent abusing it lives in the PreToolUse
layer, which DENIES any push carrying the variable — only the agent's own tool
calls reach that layer, and the agent must never set it. `UMS_ALLOW_SHARED_PUSH`
is accepted during the transition and answered with a deprecation line.
```

- [ ] **Step 4: Přepiš fail-closed podmínku ve Workspace Discipline**

Ve fázi 0 (Eligibility) nahraď „a fail-closed check of the git hooks":

```markdown
   a **fail-closed check that the publication guarantee applies to THIS
   session** — the resolved `pre-push` exists, carries
   `UMS pre-push guard (Publication Contract) v2` within its first five lines,
   and rejects a synthetic protected-branch line **run in this session's own
   environment**. A synthetic line that PASSES means the agent-session marker
   is absent in this harness, so the hook disables itself here: that is a
   missing guarantee, reported as such. An older-than-v2 hook is repaired by
   re-running `install-git-hooks.ps1` and re-checking, not by proceeding.
   The same check runs at session start and again at the beginning of
   `finishing-a-development-branch`, because the session that integrates never
   passes this gate.
```

- [ ] **Step 5: Oprav nápravu invariantu v Repository Configuration**

U kroku s důkazem doplň:

```markdown
   PROVE it with the synthetic-pipe check (Publication Contract), **with
   `MB_AGENT_SESSION=1` set** — outside an agent session the hook deliberately
   enforces nothing, so an unmarked pipe proves only that the gate works.
```

- [ ] **Step 6: Ověř, že se nikde nezůstalo staré tvrzení**

```bash
grep -rn "UMS_ALLOW_SHARED_PUSH" ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md
grep -rn "lifts THAT ONE RULE\|two-tier" ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md
```

Expected: výskyty jen tam, kde se mluví o přechodné kompatibilitě starého jména.

- [ ] **Step 7: Commit**

```bash
git add ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md
git commit -m "push-guard-jen-pro-agenty: kontrakt v2.11

 - dvouúrovňová push policy nahrazena rozdělením na aktéra a obsah
 - přiznáno, že pravidlo obsahu zaručuje auditovatelnost, ne prohlédnutí
 - lidská výjimka MB_HUMAN_PUSH zvedá celý guard, guard ji naopak zamítá
 - kontrola workspace je nově vázaná na prostředí konkrétní session"
git push
```

---

### Task 10: Doplnění všech konzumentů měněných pravidel

**Files:**
- Modify: `ums/.claude/skills/mb-abort/SKILL.md`, `ums/.claude/skills/mb-jira-update/SKILL.md`, `ums/CLAUDE.md.sample`, `CLAUDE.md`, `ums/.claude/skills/shared/overlays/brainstorming.overlay.md`, `ums/README.md`

**Interfaces:**
- Consumes: jméno `MB_HUMAN_PUSH` z Tasku 6 a formulace kontraktu z Tasku 9.

- [ ] **Step 1: Najdi všechny výskyty**

```bash
grep -rn "UMS_ALLOW_SHARED_PUSH" ums/ CLAUDE.md memory-bank/ --include="*.md" --include="*.mjs" --include="*.ps1" --include="pre-push"
```

Seznam zapiš do ledgeru — po úpravách musí být prázdný mimo místa popisující přechodnou kompatibilitu.

- [ ] **Step 2: Přepiš podávaný příkaz na dvou místech**

V `ums/.claude/skills/mb-abort/SKILL.md` a `ums/.claude/skills/mb-jira-update/SKILL.md` nahraď každý výskyt tvaru s prefixem prostou formou, protože integrační FF push už výjimku nepotřebuje:

```text
`! git push origin HEAD:<baseBranch>`
```

- [ ] **Step 3: Uprav oba instrukční soubory**

V `ums/CLAUDE.md.sample` a v kořenovém `CLAUDE.md` (sekce „Dokončení větve") nahraď větu o proměnné:

```markdown
Agent připraví přesný příkaz s výčtem odchozích commitů, `! git push origin HEAD:<baseBranch>`, a spouští ho uživatel; výjimku `MB_HUMAN_PUSH=1` je potřeba jen tam, kde push není fast-forward na commity už publikované na daném remote.
```

- [ ] **Step 4: Uprav formulaci vstupní brány v brainstorming overlay**

V `ums/.claude/skills/shared/overlays/brainstorming.overlay.md` nahraď větu o fail-closed hooku:

```markdown
     Within eligibility, a **verified publication guarantee for THIS session is
     a fail-closed precondition** — the hook must exist, be at least v2, and
     reject a synthetic protected-branch line run in this session's own
     environment; a line that passes means the agent-session marker is absent
     and the hook disables itself here.
```

- [ ] **Step 5: Doplň matici harnessů**

V `ums/README.md` v sekci „Harness compatibility" nahraď tvrzení o harness-agnostické záruce:

```markdown
The git `pre-push` hook applies in every harness — but only once the
agent-session marker (`MB_AGENT_SESSION`) reaches it; `sync-with-monorepo.ps1`
writes it into each harness's own configuration. The PreToolUse layer, which
carries the rule that the MOMENT of integration belongs to the human, exists
only in Claude Code: in Codex, Gemini and kilocode an agent can therefore run
the integration fast-forward itself.
```

- [ ] **Step 6: Ověř prázdný sweep**

```bash
grep -rn "UMS_ALLOW_SHARED_PUSH" ums/ CLAUDE.md --include="*.md" | grep -v "zastaral\|deprecat\|transition"
```

Expected: prázdný výstup.

- [ ] **Step 7: Commit**

```bash
git add ums/ CLAUDE.md
git commit -m "push-guard-jen-pro-agenty: dorovnání konzumentů měněných pravidel

 - mb-abort a mb-jira-update podávají integrační příkaz bez prefixu
 - oba instrukční soubory popisují novou roli výjimky
 - brainstorming overlay váže fail-closed podmínku na prostředí session
 - matice harnessů přiznává chybějící vrstvu aktéra mimo Claude Code"
git push
```

---

### Task 11: Revendor, nasazení a zelená smyčka

**Files:**
- Modify: `.claude/`, `.agents/skills/` (netrackovaná nasazení)
- Modify: vendorované skilly s overlay bloky (generuje revendor)

**Interfaces:**
- Consumes: všechny předchozí tasky.

- [ ] **Step 1: Obnov nasazenou kopii v tomto repu**

Pořadí kopie → revendor je závazné: revendor čte overlay fragmenty z NASAZENÉ kopie.

```bash
cp -r ums/.claude/. .claude/
```

- [ ] **Step 2: Spusť revendor v monorepu**

Změnily se dva overlay fragmenty (`brainstorming`, `finishing-a-development-branch`), takže je potřeba plný jednoprůchodový revendor s pinovaným tagem, ne `-OverlaysOnly`. Z PowerShellu, ne z Git Bash (msys `tar` past):

```powershell
pwsh .claude/scripts/revendor-superpowers.ps1 -Tag v6.3.0
```

Běh je hotový, teprve když skončí `Verification passed.`

- [ ] **Step 3: Dorovnej Codex kopii v obou repech**

```bash
cp -r .claude/skills/. .agents/skills/
diff -rq .claude/skills .agents/skills
```

Expected: prázdný výstup diffu.

- [ ] **Step 4: Ověř, že vygenerované skilly nesou nový text**

```bash
grep -n "publication guarantee self-check" .claude/skills/finishing-a-development-branch/SKILL.md
grep -n "verified publication guarantee for THIS session" .claude/skills/brainstorming/SKILL.md
```

Expected: po jednom zásahu v každém souboru.

- [ ] **Step 5: Spusť celou testovací smyčku**

```bash
for t in $(find ums -name "*.tests.ps1"); do echo "== $t"; pwsh -NoProfile -File "$t" || echo "FAILED: $t"; done
```

Expected: žádný řádek `FAILED:`. Počty asercí zapiš do ledgeru — čísla získej z tohoto běhu, ne aritmetikou.

- [ ] **Step 6: Ověř instalaci hooku v tomto klonu**

```bash
pwsh -NoProfile -File ums/.claude/hooks/install-git-hooks.ps1 -RepoRoot .
```

Expected: exit 0 a `[installed + verified live]`.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "push-guard-jen-pro-agenty: revendor overlay bloků a zelená smyčka

 - vygenerované vendorované skilly nesou novou sebekontrolu publikační záruky
 - Codex kopie dorovnaná, diff prázdný
 - celá testovací smyčka zelená, instalátor v tomto klonu ověřený"
git push
```
