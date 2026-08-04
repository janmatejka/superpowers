# Branch Model, Integration and Workspace Discipline — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

- **Jira:** (žádný tiket)
- **Návrh:** [design_branch_model_integrace.md](design_branch_model_integrace.md)
- **Target MB:** memory-bank/

**Goal:** Nahradit integraci přes lokální bázi fast-forward pushem tiketové větve, přesunout hodnoty konkrétního repozitáře z těl skillů do konfigurace a doplnit uzavřenou smyčku práce v opakovaně používaném workspace.

**Architecture:** Normativním zdrojem je kontrakt; skilly, overlaye a hooky na něj odkazují, takže změna pravidla začíná v kontraktu (task 2) a nástroje ji implementují (tasky 3–7). Konfigurace `<CTX_DIR>/ums-repo.json` je jediné místo s hodnotami konkrétního repozitáře; čte ji sdílený PowerShellový loader, `guard-git-push.mjs` přímo, a `pre-push` skrz prostý textový soubor generovaný instalátorem, protože je to POSIX `sh` bez JSON parseru. Disciplína workspace (tasky 8–11) staví na tom, že „volný workspace" je derivovaný stav gitu, ne evidence.

**Tech Stack:** Markdown (kontrakt, skilly, overlaye), PowerShell 7 (nástroje a testy), POSIX `sh` (`pre-push`), Node.js ESM (`guard-git-push.mjs`), git 2.51.

## Global Constraints

- **Zdrojem pravdy je `ums/.claude/`.** Kořenový `.claude/` a `.agents/skills/` jsou netrackovaná nasazení — nikdy je needituj jako zdroj. Po změně zdroje se nasazení obnovuje v tasku 13.
- **Vendorované soubory pod `skills/` se needitují nikdy.** Změny upstream skillů jdou výhradně do fragmentů `ums/.claude/skills/shared/overlays/*.overlay.md`; vendorované kopie s overlay bloky vyrábí revendor v monorepu, ne tato větev.
- **Vrstva je bezzávislostní.** Žádný nový NuGet, npm ani PowerShell modul. Testy jsou obyčejné `.ps1` skripty s vlastní kopií `_assert.ps1` v každém adresáři testů (žádný Pester).
- **Každý nový PowerShellový skript** začíná `Set-StrictMode -Version Latest` a `$ErrorActionPreference = 'Stop'`. `$LASTEXITCODE` čti jen bezprostředně po nativním volání ve stejné větvi kódu.
- **PowerShellové pasti tohoto repa:** obal `Get-Content` do `@()`, než použiješ `.Count` nebo indexaci; nikdy nedávej české kudrnaté uvozovky (U+201C/201D/201E/2018/2019/201A) do řetězce uvozeného dvojitou uvozovkou — parser je bere jako ukončovací znak; `Set-Content -Encoding UTF8` v PS7 nepřidává BOM.
- **Jazyk (Language Contract):** hlášky `pre-push` a `guard-git-push.mjs`, výstupy `doc-index.ps1` a reporty `mb-*` skillů jsou **česky**; `install-git-hooks.ps1` a jeho konzolový výstup jsou **anglicky** (vývojářské nástroje vrstvy). Těla skillů a instrukční text jsou anglicky, uživatelské reporty v nich česky.
- **Bezpříponové shellové soubory musí mít v pracovním stromu LF.** `pre-push` je krytý pravidlem v `ums/.gitattributes`; nesahej na konce řádků.
- **Commit messages česky s diakritikou psanou přímo** (UTF-8 přes heredoc projde). Po commitu ověř `git log -1 --format=%B | od -c` a hledej vícebajtové sekvence.
- **Na této větvi agent NEPUSHUJE.** Pravidlo „push po každém commitu" se zavádí pro tiketové větve; `ums-memory-bank` je integrační báze tohoto forku, takže push připrav jako příkaz pro uživatele (`! UMS_ALLOW_SHARED_PUSH=1 git push origin ums-memory-bank`) a nikdy ho nespouštěj sám.
- **Verze kontraktu se zvyšuje na `2.6` právě jednou**, v tasku 2. Žádný jiný task číslo verze nemění.
- **Hranice pro zastavení:** po tasku 7 je hotová vynucovací vrstva (pravidla, konfigurace, hooky, index) a je konzistentní sama v sobě. Tasky 8–12 přidávají disciplínu workspace a doplňují skilly, které pravidla provádějí; tasky 13–14 dokumentaci a nasazení. Pokud se práce zastaví, zastav ji po tasku 7 nebo po tasku 14, ne uprostřed.

---

### Task 1: Oprava ploché cesty SDD ledgeru

Upstream scopoval pracovní adresář plánu na `.superpowers/sdd/<plan-basename>/` (viz `RELEASE-NOTES.md`: *„observed in the wild, with multiple contamination rounds"*), ale vrstva na sedmi místech odkazuje na plochou `.superpowers/sdd/progress.md`, která neexistuje. Nejzávažnější je PostCompact hook: po kompaktaci uprostřed plánu posílá agenta na neexistující soubor.

**Files:**
- Modify: `ums/.claude/settings.json` (PostCompact `systemMessage`)
- Modify: `ums/.claude/skills/mb-act/SKILL.md`
- Modify: `ums/.claude/skills/mb-git-commit/SKILL.md`
- Modify: `ums/.claude/skills/mb-git-message/SKILL.md`
- Modify: `ums/.claude/skills/mb-jira-update/SKILL.md`
- Modify: `memory-bank/tech.md`

**Interfaces:**
- Consumes: nic (první task).
- Produces: kanonický tvar cesty `.superpowers/sdd/<plan-basename>/progress.md`, který používají všechny další tasky, když ledger zmiňují.

- [ ] **Step 1: Zdokumentuj výchozí stav (evidence před opravou)**

```bash
cd <repo root>
rg -n 'superpowers/sdd/progress\.md' ums/ memory-bank/ | tee /tmp/ledger-before.txt
rg -c 'superpowers/sdd/progress\.md' ums/ memory-bank/
```

Expected: nálezy v `ums/.claude/settings.json`, `mb-act/SKILL.md`, `mb-git-commit/SKILL.md` (3×), `mb-git-message/SKILL.md` (2×), `mb-jira-update/SKILL.md` (2×), `memory-bank/tech.md`. Zapiš celkový počet — v kroku 5 musí být nula.

- [ ] **Step 2: Oprav PostCompact hook**

V `ums/.claude/settings.json` v `hooks.PostCompact` nahraď v textu `systemMessage` řetězec

`also re-read .superpowers/sdd/progress.md.`

za

`also re-read the ledger of the plan you are executing: .superpowers/sdd/<plan-basename>/progress.md (per-plan directory; there is no flat progress.md).`

Nesahej na strukturu JSONu ani na uvozování — je to jednořádkový `echo` s vnořeným JSONem, takže escapované uvozovky musí zůstat escapované.

- [ ] **Step 3: Oprav pět `mb-*` skillů**

V každém výskytu nahraď `.superpowers/sdd/progress.md` za `.superpowers/sdd/<plan-basename>/progress.md`. Věty, které ledger zmiňují jako zdroj progresu (například „task progress lives in the plan file's checkboxes and `.superpowers/sdd/progress.md`"), zůstávají jinak nezměněné — mění se jen cesta.

- [ ] **Step 4: Oprav `memory-bank/tech.md`**

V tabulce konfigurace pro Claude Code nahraď u řádku `hooks.PostCompact` text `.superpowers/sdd/progress.md` za `.superpowers/sdd/<plan-basename>/progress.md`.

- [ ] **Step 5: Ověř, že plochá cesta nikde nezůstala**

```bash
rg -n 'superpowers/sdd/progress\.md' ums/ memory-bank/ ; echo "exit=$?"
```

Expected: žádný výstup a `exit=1` (ripgrep nenašel nic). Jakýkoli nález je regrese.

```bash
node --input-type=module -e "import('node:fs').then(fs=>{JSON.parse(fs.readFileSync('ums/.claude/settings.json','utf8'));console.log('settings.json is valid JSON')})"
```

Expected: `settings.json is valid JSON`.

- [ ] **Step 6: Commit**

```bash
git add ums/.claude/settings.json ums/.claude/skills/mb-act/SKILL.md \
        ums/.claude/skills/mb-git-commit/SKILL.md ums/.claude/skills/mb-git-message/SKILL.md \
        ums/.claude/skills/mb-jira-update/SKILL.md memory-bank/tech.md
git commit -m "UMS: oprava odkazů na SDD ledger na cestu per plán

Upstream scopoval pracovní adresář plánu na .superpowers/sdd/<plan-basename>/,
vrstva ale na sedmi místech odkazovala na plochou progress.md, která už
neexistuje. Nejzávažnější byl PostCompact hook: po kompaktaci uprostřed
plánu posílal agenta na neexistující soubor."
```

---

### Task 2: Kontrakt v2.6

Normativní zdroj. Mění se pět existujících sekcí, přidávají tři nové a jedna podsekce se maže. **Netříští se na víc tasků** záměrně: napůl aktualizovaný kontrakt si vnitřně odporuje, což je horší než jeden velký přehled ke kontrole.

**Files:**
- Modify: `ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md`

**Interfaces:**
- Consumes: kanonická cesta ledgeru z tasku 1.
- Produces: `Contract-Version: 2.6`; jména nových sekcí `Repository Configuration`, `Base Sync & Drift Detection`, `Workspace Discipline`; cestu konfigurace `<CTX_DIR>/ums-repo.json`; cestu kandidátů `<MB_ROOT>/.superpowers/playbook-candidates/<slug>.md`. Na tato jména se odkazují tasky 3–12.

- [ ] **Step 1: Hlavička verze**

Nastav `- **Contract-Version:** 2.6` a nad dosavadní řádek o v2.4 vlož:

```markdown
- Supersedes v2.5 (integration is a fast-forward push of the ticket branch, so
  the `--no-ff` convention is dropped; repository-specific values move out of
  skill bodies into `<CTX_DIR>/ums-repo.json`; the active-work limit becomes
  per-branch; workspace discipline and the park operation are added).
```

- [ ] **Step 2: Publication Contract**

- Nahraď výčet čtyř publikačních bodů pravidlem: **agent pushuje vlastní tiketovou větev po každém commitu**, vždy s ohlášením větve a odchozích commitů; dosavadní čtyři body zůstávají uvedené jako jeho zvláštní případy a doplňují se o commit implementátora po zeleném tasku, commit po mergi báze a commit MB změn po harvestu.
- V tabulce dvouúrovňové policy změň příklad příkazu u sdílených větví na refspecový tvar: `! UMS_ALLOW_SHARED_PUSH=1 git push origin HEAD:<baseRef>`.
- Přidej podsekci **Integration** se sekvencí: `fetch` → `merge origin/<baseRef>` → zelená verifikace → agent připraví lidský příkaz s výčtem odchozích commitů → uživatel spustí → agent znovu ověří dosažitelnost → `mb-jira-update` finalizace. Selhání pushe na non-fast-forward znamená pohnutou bázi: opakuj od `fetch`, **strop dvě neúspěšná kola**, pak STOP a report.
- Doplň, že zbylá tiketová větev na `origin` se nemaže (mazání větve přes push zůstává zakázané) a jako kolize se nehlásí, protože index klíčuje podle fáze.

- [ ] **Step 3: Cross-Branch Visibility**

Nahraď pravidlo *„A ticket branch is created from the CURRENT base ref (fetch + fast-forward)"* za: tiketová větev se zakládá `git switch -c <TICKET>-<kebab-slug> origin/<baseRef>` **vždy s explicitním výchozím bodem**; lokální báze se v tiketovém klonu nepoužívá — pokud existuje, neaktualizuje se a nemerguje. Doplň postkondici založení: `proposals/active/` je prázdný nebo chybí a `context.md` je `IDLE`; jinak STOP, větev smazat, zopakovat. Doplň invariant, že **báze nikdy nenese `ACTIVE` stav**.

- [ ] **Step 4: Architect Review Gate**

Změň doporučené jméno větve z `feature/ums-3302-toast-reconcile` na `<TICKET>-<kebab-slug>` (například `UMS-3302-toast-reconcile`), s poznámkou, že nová jména jsou ASCII a existující s diakritikou se nepřejmenovávají. Doplň asymetrii: bázi merguje **jen strana řešitele** (request a resume); architekt v režimu respond nemerguje nikdy, protože branch sync má pravidlo „divergence = STOP" a merge z obou stran by ho zastavil. Merge báze patří **před** handoff push.

- [ ] **Step 5: Active Work Item**

Nahraď zdůvodnění *„one active work item per clone, because `context.md` holds one pin"* za: limit je **per větev**, protože pin drží každá větev vlastní. Two-actives guard se zastaví jen tehdy, když aktivní slug na **aktuální větvi** není obnovitelný z `origin` (má necommitnuté změny nebo nepushnuté commity); commitnutá a pushnutá práce jiného tiketu **je zaparkovaná** a začít nový tiket na nové větvi je normální provoz, který se jen ohlásí. Meziclonová kolizní kontrola zůstává beze změny.

- [ ] **Step 6: Playbook Contract**

- Změň cestu sběrného souboru z fixní `<MB_ROOT>/.superpowers/playbook-candidates.md` na **per slug**: `<MB_ROOT>/.superpowers/playbook-candidates/<slug>.md`, první řádek zůstává `# Playbook candidates — work item: <slug>`.
- Přepiš pravidlo o přepisu: přepisuje se soubor **téhož slugu** se zastaralým obsahem; cizí slugy mají vlastní soubory a nikdy se nemažou. Zdůvodni to jedním souvětím: přepisovací pravidlo předpokládalo sériovou práci, ale při prokládání živých tiketů mazalo živé důkazy.
- Doplň, že `mb-park` soubor aktuálního slugu **commituje na tiketovou větev** (`git add -f`, protože `.superpowers/` je ignorovaný) a harvest ho po zápisu do `playbook.md` maže. Označ to jako **pojmenovanou výjimku** z pravidla „scratch je git-ignored", platnou pro tento jeden soubor.

- [ ] **Step 7: Scope Lock**

Ve výčtu legálního scratch tree nahraď `playbook-candidates.md` za `playbook-candidates/<slug>.md` a doplň jednu větu o té pojmenované výjimce (soubor aktuálního slugu se při parkování commituje).

- [ ] **Step 8: Nová sekce `Repository Configuration`**

Vlož za sekci `Scope Lock`. Obsah:

- **Žádná hodnota specifická pro repozitář nesmí být v těle skillu ani ve skriptu.** Vrstva je redistribuovatelná.
- Umístění: `<CTX_DIR>/ums-repo.json`. **Ne v `.claude/`** — upstream `.gitignore` ignoruje každý adresář `.claude/`, takže soubor by byl netrackovaný a nepřenosný. `CTX_DIR` je garantovaně existující (Root Memory Bank Gate) i trackovaný.
- Klíče a jejich konzumenti: `baseRef` (doc-index, zakládání větve, base sync, integrace), `protectedBranches` (`pre-push` přes generovaný seznam, `guard-git-push.mjs`), `ticketPattern` (`mb-state`, vstupní brána, `mb-architect-review`), `projectMarkers` a `sharedRoots` (heuristika průniku). **Klíč bez pojmenovaného konzumenta se nezavádí.**
- Chybějící soubor není chyba a **degradace míří k bezpečnější straně**: `baseRef` → `origin/develop`, `protectedBranches` → vestavěný seznam (tedy k *více* ochrany), a bez `projectMarkers`/`sharedRoots` se verifikace po mergi báze nabídne při **každém** neprázdném příchozím diffu.
- `pre-push` je POSIX `sh` bez JSON parseru, proto z konfigurace generuje prostý textový seznam `install-git-hooks.ps1` do `<git-common-dir>/ums-protected-branches`; **změna seznamu vyžaduje nový běh instalátoru.**
- Naplnění detekuje `mb-init` z topologie repozitáře; první verze nepotřebuje schválení (stejná výjimka a ze stejného důvodu jako první `playbook.md`), každá pozdější změna ano.

- [ ] **Step 9: Nová sekce `Base Sync & Drift Detection`**

Vlož za `Repository Configuration`. Obsah:

- Hranice fází, na kterých se merguje báze: před `writing-plans`; před dispatchem prvního tasku; před requestem a před resume design review; před whole-branch review; před `mb-harvest`. **Nikdy uprostřed tasku.**
- Sekvence: `fetch` → `merge origin/<baseRef>` → posouzení průniku → případná verifikace → commit → push.
- Posouzení průniku, obě množiny počítané **po `fetch` a před `merge`** ze stejného merge-base:

  ```
  MB=$(git merge-base HEAD origin/<baseRef>)
  prichozi=$(git diff --name-only $MB..origin/<baseRef>)
  vlastni=$(git diff --name-only  $MB..HEAD)
  ```

  Ve fázi návrhu roli **vlastní** množiny hrají cílové oblasti pojmenované v návrhu.
- Mechanika bez znalosti ekosystému: každá cesta se mapuje na **nejbližší nadřazený adresář obsahující shodu s `projectMarkers`** (cesta bez takového předka zůstává sama sebou) a průnik se hledá tam; cesta odpovídající některému vzoru ze `sharedRoots` je **vždy protínající**. Označ to výslovně jako **heuristiku**, ne důkaz.
- Odstupňovaná verifikace: bez průniku žádná (jen jednořádkové konstatování); s průnikem agent vypíše protínající se cesty a **nabídne** baseline s doporučením, rozhoduje uživatel; konflikt v mergi je automaticky průnik; ve fázi návrhu a design review se nic nestaví, takže je to čistě nabídka; před dispatchem prvního tasku je baseline povinná už dnes.
- **STOP platí jen tam, kde verifikace proběhla a je červená.** Cizí rozbití báze se neopravuje uvnitř tiketové větve. Konflikt v mergi řeší agent jen v souborech, které na větvi sám měnil, jinak STOP.
- Konflikt `context.md` se řeší vždy ponecháním verze tiketové větve, cíleně `git checkout --ours memory-bank/context.md`, **nikdy `merge -X ours` na celý merge**; je to stav této větve, ne fakt o produktu. Konflikt na témže slugu v `proposals/active/` je kolize dvou aktérů, tedy STOP.

- [ ] **Step 10: Nová sekce `Workspace Discipline`**

Vlož za `Base Sync & Drift Detection`. Obsah:

- Workspace zakládá a vybírá **uživatel**; používá se opakovaně a nese zbytky předchozí práce.
- **Jediná hranice odpovědnosti: agent nikdy nezničí nic, co nejde získat zpátky z `origin`.** Obnovitelné (pushnuté větve, build output, ledger archivovaného plánu) smí agent řešit sám; neobnovitelné (necommitnuté změny, stash, nepushnuté commity, kandidáti playbooku) nikdy nemaže — zachová, nebo zastaví a zeptá se. Rozhodnutí o neobnovitelném patří uživateli, detekce a předložení agentovi.
- **„Volný workspace" je derivovaný stav**, ne evidence: prázdný výstup `git status --porcelain`, `git stash list` a `git log --branches --not --remotes`.
- Zbytky se dělí na **v cestě** (špinavý strom, stash — blokují bezpečné přepnutí a musí být vyřešené) a **pouze přítomné** (nepushnuté commity jiných větví, kandidáti jiných slugů — jen se ohlásí, agent na ně nesahá).
- **Vstupní brána** ve čtyřech fázích: (0) způsobilost — `MB_ROOT`, `memory-bank/`, konfigurace, **kontrola git hooků fail-closed**, `core.hooksPath` nenastavený nebo relativní, `git fetch origin`; (1) inventura zbytků; (2) právě jedno rozhodnutí uživatele, jen když je v cestě něco neobnovitelného — **zaparkovat** nebo **zahodit** s vypsaným potvrzením, přičemž „nechat ležet" v témže workspace neexistuje; (3) záměr — lokální větev tiketu existuje → resume, tiket aktivní na cizí větvi → STOP, čeká předběžný návrh v `next/` → aktivace, jinak nová větev; (4) zápis pinu.
- Kontrola hooků je v tomto modelu nejdůležitější agentí povinnost, protože workspace zakládá uživatel a git hooky se s klonem nepřenášejí.
- **Přepínání:** `git status --porcelain` prázdný, **žádné přepínání přes `git stash`, žádný auto-stash** (tatáž formulace jako branch sync v `mb-architect-review`), a jen na hranicích fází.
- **Park** je třetí konec životního cyklu vedle dokončení a opuštění: commit, push, ohlášení zbytků, commit kandidátů aktuálního slugu, větev zůstává checkoutnutá, `context.md` zůstává `ACTIVE`.
- **Jedno sezení na workspace.** Práce na více tiketech je prokládaná, ne paralelní.
- Životní cyklus (harvest, `mb-abort`, finalizace Jiry) se spouští na vlastní větvi toho tiketu.

- [ ] **Step 11: Fail-Closed Behavior a Worktree Policy**

Do výčtu hard failures přidej: nemožný base sync na hranici fáze (divergence nebo špinavý strom), strop dvou integračních kol, chybějící nebo neověřený `pre-push` hook ve workspace, selhání `git fetch origin` ve fázi 0.

V sekci `Worktree Policy & Pool Interface` **smaž celou podsekci „Future worktree pool (interface only — not implemented)"** a přejmenuj sekci na `Worktree Policy`. Zákaz worktrees, jeho tři vynucovací mechanismy i větev na místě zůstávají beze změny. Zdůvodnění zákazu doplň měřením: klon monorepa má 25 GB, z toho `.git` 4,1 GB, takže linked worktree by ušetřil 16 % — izolace se řeší volbou workspace uživatelem.

- [ ] **Step 12: Ověř vnitřní konzistenci kontraktu**

```bash
rg -n 'playbook-candidates\.md|per clone|--no-ff|feature/ums-|Future worktree pool' ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md ; echo "exit=$?"
```

Expected: žádný výstup a `exit=1`. Každý nález je zapomenutá změna z kroků 2–11.

```bash
rg -n '^- \*\*Contract-Version:\*\* 2\.6$' ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md
rg -c '^## ' ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md
```

Expected: verze nalezena; počet sekcí o 3 vyšší než před taskem (nové `Repository Configuration`, `Base Sync & Drift Detection`, `Workspace Discipline`).

- [ ] **Step 13: Commit**

```bash
git add ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md
git commit -m "UMS: kontrakt v2.6 — FF integrace, konfigurace repa, disciplína workspace

Integrace je fast-forward push tiketové větve, takže konvence --no-ff se
ruší (s mergnutou bází ji nelze vyrobit). Hodnoty konkrétního repozitáře
se přesouvají do <CTX_DIR>/ums-repo.json. Limit aktivních položek je per
větev a zastaví jen práci neobnovitelnou z origin. Nové sekce Repository
Configuration, Base Sync & Drift Detection a Workspace Discipline;
podsekce nepostavitelného worktree poolu smazána, zákaz worktrees
zůstává."
```

---

### Task 3: Konfigurace repozitáře — soubor a sdílený loader

**Files:**
- Create: `ums/.claude/skills/shared/scripts/Get-UmsRepoConfig.ps1`
- Create: `ums/.claude/skills/shared/tests/repo-config.tests.ps1`
- Create: `ums/.claude/skills/shared/tests/_assert.ps1`
- Create: `memory-bank/ums-repo.json`

**Interfaces:**
- Consumes: jména klíčů a cestu konfigurace z tasku 2.
- Produces: funkci `Get-UmsRepoConfig([string] $RepoRoot)` vracející hashtable s klíči `BaseRef` (string), `ProtectedBranches` (string[]), `TicketPattern` (string), `ProjectMarkers` (string[]), `SharedRoots` (string[]), `Source` (`'file'` nebo `'default'`). Konzumují ji tasky 5 a 7.

- [ ] **Step 1: Napiš selhávající test**

Vytvoř `ums/.claude/skills/shared/tests/_assert.ps1` s obsahem:

```powershell
# Dependency-free assertion helper for shared-config tests.
Set-StrictMode -Version Latest
$script:Failures = 0
$script:Total = 0
function Assert-True([bool] $cond, [string] $msg) {
    $script:Total++
    if ($cond) { Write-Host "  ok  : $msg" } else { Write-Host "  FAIL: $msg"; $script:Failures++ }
}
function Assert-Eq($actual, $expected, [string] $msg) {
    Assert-True ($actual -eq $expected) "$msg  (got '$actual', want '$expected')"
}
function Complete-Tests {
    Write-Host ""
    if ($script:Failures -gt 0) { Write-Host "$script:Failures/$script:Total FAILED"; exit 1 }
    Write-Host "$script:Total passed"; exit 0
}
```

Vytvoř `ums/.claude/skills/shared/tests/repo-config.tests.ps1`:

```powershell
#Requires -Version 7
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_assert.ps1')
. (Join-Path $PSScriptRoot '..\scripts\Get-UmsRepoConfig.ps1')

$tmp = Join-Path ([IO.Path]::GetTempPath()) ("ums-cfg-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path (Join-Path $tmp 'memory-bank') | Out-Null

Write-Host "== chybejici soubor -> defaulty"
$c = Get-UmsRepoConfig $tmp
Assert-Eq $c.Source 'default' 'chybejici soubor hlasi Source=default'
Assert-Eq $c.BaseRef 'origin/develop' 'default baseRef'
Assert-True (@($c.ProtectedBranches).Count -eq 4) 'default protectedBranches ma 4 vzory'
Assert-True (@($c.SharedRoots).Count -eq 0) 'default sharedRoots je prazdny'

Write-Host "== plny soubor"
@'
{
  "baseRef": "origin/ums-memory-bank",
  "protectedBranches": ["develop", "Branches/*"],
  "ticketPattern": "^UMS-[0-9]+",
  "projectMarkers": ["*.csproj"],
  "sharedRoots": ["Common/"]
}
'@ | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $tmp 'memory-bank\ums-repo.json')
$c = Get-UmsRepoConfig $tmp
Assert-Eq $c.Source 'file' 'existujici soubor hlasi Source=file'
Assert-Eq $c.BaseRef 'origin/ums-memory-bank' 'baseRef ze souboru'
Assert-Eq (@($c.ProtectedBranches)[1]) 'Branches/*' 'protectedBranches ze souboru'
Assert-Eq (@($c.SharedRoots).Count) 1 'sharedRoots ma jeden prvek a je pole'

Write-Host "== jednoprvkove pole zustava polem"
'{ "protectedBranches": ["develop"] }' | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $tmp 'memory-bank\ums-repo.json')
$c = Get-UmsRepoConfig $tmp
Assert-Eq (@($c.ProtectedBranches).Count) 1 'jednoprvkove pole ma Count 1'

Write-Host "== chybejici klic bere svuj default, ne cely default"
'{ "baseRef": "origin/trunk" }' | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $tmp 'memory-bank\ums-repo.json')
$c = Get-UmsRepoConfig $tmp
Assert-Eq $c.BaseRef 'origin/trunk' 'baseRef ze souboru'
Assert-True (@($c.ProtectedBranches).Count -eq 4) 'chybejici protectedBranches padne na default'

Write-Host "== rozbity JSON -> defaulty, ne vyjimka"
'{ not json' | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $tmp 'memory-bank\ums-repo.json')
$c = Get-UmsRepoConfig $tmp
Assert-Eq $c.Source 'default' 'rozbity JSON degraduje na defaulty'
Assert-Eq $c.BaseRef 'origin/develop' 'rozbity JSON nezpusobi vyjimku'

Remove-Item -Recurse -Force $tmp
Complete-Tests
```

- [ ] **Step 2: Spusť test a ověř, že selže**

Run: `pwsh -NoProfile -File ums/.claude/skills/shared/tests/repo-config.tests.ps1`
Expected: FAIL — dot-source `Get-UmsRepoConfig.ps1` skončí chybou „nelze najít cestu", protože skript zatím neexistuje.

- [ ] **Step 3: Napiš loader**

Vytvoř `ums/.claude/skills/shared/scripts/Get-UmsRepoConfig.ps1`:

```powershell
<#
.SYNOPSIS
    Reads the per-repository UMS configuration (contract: "Repository
    Configuration") and fills in per-key defaults for everything absent.

.DESCRIPTION
    Location is <RepoRoot>/memory-bank/ums-repo.json — deliberately NOT
    .claude/, which upstream .gitignore ignores wholesale, so a config file
    there would be untracked and therefore not shared.

    Never throws on a missing or malformed file: degradation is toward the
    SAFER side (built-in protected list = more protection, not less; empty
    projectMarkers/sharedRoots = the drift heuristic offers verification more
    often, not less). A malformed file writes one warning to the warning
    stream and falls back to defaults.

    Dot-source this file, then call Get-UmsRepoConfig.
#>
Set-StrictMode -Version Latest

function Get-UmsRepoConfig([string] $RepoRoot) {
    $cfg = @{
        BaseRef           = 'origin/develop'
        ProtectedBranches = @('develop', 'main', 'master', 'release/*')
        TicketPattern     = '^[A-Z][A-Z0-9]+-[0-9]+'
        ProjectMarkers    = @()
        SharedRoots       = @()
        Source            = 'default'
    }

    if (-not $RepoRoot) { return $cfg }
    $path = Join-Path $RepoRoot 'memory-bank/ums-repo.json'
    if (-not (Test-Path -LiteralPath $path)) { return $cfg }

    try {
        $raw = Get-Content -LiteralPath $path -Raw -ErrorAction Stop
        $json = $raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Write-Warning "ums-repo.json nelze přečíst ($path): $($_.Exception.Message). Používám vestavěné defaulty."
        return $cfg
    }

    $cfg.Source = 'file'
    # Each key falls back INDIVIDUALLY: a file naming only baseRef must not
    # wipe the built-in protected list.
    if ($json.PSObject.Properties.Name -contains 'baseRef' -and $json.baseRef) {
        $cfg.BaseRef = [string]$json.baseRef
    }
    if ($json.PSObject.Properties.Name -contains 'ticketPattern' -and $json.ticketPattern) {
        $cfg.TicketPattern = [string]$json.ticketPattern
    }
    foreach ($pair in @(
            @{ Key = 'protectedBranches'; Field = 'ProtectedBranches' },
            @{ Key = 'projectMarkers'; Field = 'ProjectMarkers' },
            @{ Key = 'sharedRoots'; Field = 'SharedRoots' })) {
        if ($json.PSObject.Properties.Name -contains $pair.Key) {
            # @() so a single-element JSON array still exposes .Count.
            $values = @($json.($pair.Key)) | Where-Object { $_ } | ForEach-Object { [string]$_ }
            if (@($values).Count -gt 0) { $cfg[$pair.Field] = @($values) }
        }
    }
    return $cfg
}
```

Česká diakritika v hlášce je správně a smí tam být — past playbooku se týká **kudrnatých uvozovek** (U+201C a spol.) uvnitř řetězce uvozeného dvojitou uvozovkou, ne diakritiky. Do této hlášky tedy žádné české uvozovky nepiš.

- [ ] **Step 4: Spusť test a ověř, že prochází**

Run: `pwsh -NoProfile -File ums/.claude/skills/shared/tests/repo-config.tests.ps1`
Expected: PASS, poslední řádek `13 passed` a exit 0.

- [ ] **Step 5: Vytvoř konfiguraci pro tento repozitář**

Vytvoř `memory-bank/ums-repo.json`:

```json
{
  "baseRef": "origin/ums-memory-bank",
  "protectedBranches": ["ums-memory-bank", "main", "master", "develop", "release/*", "Branches/*"],
  "ticketPattern": "^UMS-[0-9]+",
  "projectMarkers": ["*.csproj", "*.vcxproj", "*.sln", "package.json"],
  "sharedRoots": ["ums/.claude/skills/shared/", "ums/.gitattributes"]
}
```

Zdůvodnění hodnot pro tento fork: `baseRef` je integrační větev forku; `main` je zrcadlo upstreamu a `ums-memory-bank` je báze, takže obojí je chráněné; `sharedRoots` míří na normativní zdroj vrstvy, protože změna v `shared/` se dotýká všech skillů.

- [ ] **Step 6: Ověř loader proti skutečné konfiguraci**

```bash
pwsh -NoProfile -Command ". ums/.claude/skills/shared/scripts/Get-UmsRepoConfig.ps1; \$c = Get-UmsRepoConfig (git rev-parse --show-toplevel); \$c.Source; \$c.BaseRef; \$c.ProtectedBranches -join ','"
```

Expected: `file`, `origin/ums-memory-bank`, seznam šesti vzorů.

- [ ] **Step 7: Commit**

```bash
git add ums/.claude/skills/shared/scripts/Get-UmsRepoConfig.ps1 \
        ums/.claude/skills/shared/tests/ memory-bank/ums-repo.json
git commit -m "UMS: konfigurace repozitáře a sdílený loader

Nový <CTX_DIR>/ums-repo.json drží hodnoty konkrétního repozitáře, které
dosud byly zadrátované ve skillech a skriptech. Loader dosazuje defaulty
po jednotlivých klíčích a nikdy nevyhodí výjimku — degradace míří
k bezpečnější straně (vestavěný chráněný seznam = více ochrany)."
```

---

### Task 4: `pre-push` — chráněné větve z generovaného seznamu a dvě hlášky

**Files:**
- Modify: `ums/.claude/hooks/pre-push`
- Modify: `ums/.claude/hooks/tests/pre-push.tests.ps1`

**Interfaces:**
- Consumes: cestu `<git-common-dir>/ums-protected-branches` z tasku 2 (formát: jeden glob na řádek, `#` je komentář).
- Produces: chování hooku, které task 5 (generátor seznamu) a task 13 (self-test) předpokládají.

- [ ] **Step 1: Napiš selhávající testy**

Do `ums/.claude/hooks/tests/pre-push.tests.ps1` přidej čtyři případy proti existujícímu bare remote fixture:

1. `Branches/5.37` je zamítnutá, když je v generovaném seznamu — vytvoř `<git-common-dir>/ums-protected-branches` s obsahem `develop`, `Branches/*` a ověř, že push do `refs/heads/Branches/5.37` skončí nenulově a hláškou `UMS:`.
2. `Branches/5.37` **projde**, když generovaný seznam chybí — ověřuje fallback na vestavěný seznam, který `Branches/*` neobsahuje.
3. `develop` je zamítnutá i bez generovaného seznamu (fallback nesmí ochranu ubrat).
4. Seznam obsahující jen komentáře a prázdné řádky se chová jako chybějící soubor (fallback), ne jako „nic není chráněné".

K tomu dva případy na hlášky: zamítnutí sdílené větve obsahuje `HEAD:` (refspecový tvar), a zamítnutí non-fast-forward obsahuje slovo `báze` (odlišení pohnuté báze od force pushe).

- [ ] **Step 2: Spusť sadu a ověř, že nové případy selžou**

Run: `pwsh -NoProfile -File ums/.claude/hooks/tests/pre-push.tests.ps1`
Expected: FAIL — případ 1 projde push místo zamítnutí (`Branches/*` hook nezná), a oba případy na hlášky nenajdou svůj text.

- [ ] **Step 3: Implementuj čtení seznamu**

V `ums/.claude/hooks/pre-push` nahraď zadrátovaný `case` blok. Před hlavní `while read` smyčku vlož načtení vzorů **jednou** (nikdy `while read` uvnitř smyčky, která už čte stdin hooku — ta by mu stdin sebrala):

```sh
# Protected-branch patterns come from the repository configuration
# (contract: "Repository Configuration"), materialized as one glob per line
# by install-git-hooks.ps1 — this is POSIX sh, there is no JSON parser here.
# A missing, empty or comment-only file falls back to the built-in list:
# degradation must always lead to MORE protection, never less.
common_dir=$(git rev-parse --git-common-dir 2>/dev/null)
[ -z "$common_dir" ] && common_dir='.git'
protected_file="$common_dir/ums-protected-branches"

protected_patterns=''
if [ -f "$protected_file" ]; then
    protected_patterns=$(sed -e 's/#.*//' "$protected_file" \
        | tr -d '[:blank:]' \
        | tr '[:upper:]' '[:lower:]' \
        | grep -v '^$')
fi
if [ -z "$protected_patterns" ]; then
    protected_patterns='develop
main
master
release/*'
fi

# $pat is deliberately UNQUOTED inside `case` so it is treated as a glob.
is_protected() {
    for pat in $protected_patterns; do
        case "$1" in
            $pat) return 0 ;;
        esac
    done
    return 1
}
```

V hlavní smyčce nahraď

```sh
    case "$remote_ref_lc" in
        refs/heads/develop|refs/heads/main|refs/heads/master|refs/heads/release/*)
```

za výpočet jména větve a volání funkce:

```sh
    branch_lc=${remote_ref_lc#refs/heads/}
    if is_protected "$branch_lc"; then
```

a odpovídajícím způsobem uzavři blok (`fi` místo `;; esac`). Zbytek logiky (lidská výjimka, mazání, non-fast-forward) zůstává nezměněný.

- [ ] **Step 4: Oprav dvě hlášky**

V zamítnutí sdílené větve nahraď radu

```sh
                echo "     \`! UMS_ALLOW_SHARED_PUSH=1 git push $remote_name $b\`" >&2
```

za refspecový tvar, který funguje i v klonu bez lokální báze:

```sh
                echo "     \`! UMS_ALLOW_SHARED_PUSH=1 git push $remote_name HEAD:$b\`" >&2
```

V zamítnutí non-fast-forward doplň za existující dva řádky třetí:

```sh
            echo "     Pokud integrujes tiketovou vetev, baze se nejspis pohnula: udelej" >&2
            echo "     git fetch a merge origin/<baze>, znovu over a zkus push jeste raz." >&2
```

**Tyto dvě hlášky napiš česky s diakritikou** (`integruješ`, `báze`, `ověř`) — v plánu jsou v ASCII jen proto, že jde o `sh` skript v ohraničeném bloku a diakritika by se v něm dala snadno přehlédnout. Ostatní hlášky hooku už diakritiku mají, takže se nová nesmí odlišovat.

- [ ] **Step 5: Spusť sadu a ověř, že prochází**

Run: `pwsh -NoProfile -File ums/.claude/hooks/tests/pre-push.tests.ps1`
Expected: PASS, `<N> passed` s N o šest vyšším než před taskem, exit 0.

- [ ] **Step 6: Ověř, že soubor zůstal LF a spustitelný**

```bash
file ums/.claude/hooks/pre-push
git diff --cached --stat -- ums/.claude/hooks/pre-push
rg -c $'\r' ums/.claude/hooks/pre-push ; echo "exit=$?"
```

Expected: `POSIX shell script`; žádný CR (`exit=1`).

- [ ] **Step 7: Commit**

```bash
git add ums/.claude/hooks/pre-push ums/.claude/hooks/tests/pre-push.tests.ps1
git commit -m "UMS: pre-push čte chráněné větve z generovaného seznamu

Vzory přicházejí z konfigurace repozitáře přes prostý textový soubor,
protože hook je POSIX sh bez JSON parseru. Chybějící, prázdný nebo jen
komentářový soubor padá na vestavěný seznam — degradace vede vždy k více
ochrany. Zamítnutí sdílené větve radí refspecový tvar (v tiketovém klonu
bez lokální báze dosavadní rada nefungovala) a zamítnutí non-fast-forward
rozlišuje pohnutou bázi od force pushe."
```

---

### Task 5: `install-git-hooks.ps1` generuje seznam chráněných větví

**Files:**
- Modify: `ums/.claude/hooks/install-git-hooks.ps1`
- Modify: `ums/.claude/hooks/tests/pre-push.tests.ps1`

**Interfaces:**
- Consumes: `Get-UmsRepoConfig` z tasku 3; formát seznamu a chování fallbacku z tasku 4.
- Produces: soubor `<git-common-dir>/ums-protected-branches` a nový exit kód **4** = seznam se nepodařilo zapsat.

- [ ] **Step 1: Napiš selhávající test**

Do `pre-push.tests.ps1` přidej případ: ve fixture repu vytvoř `memory-bank/ums-repo.json` s `protectedBranches` obsahujícím `Branches/*`, spusť instalátor a ověř, že (a) soubor `<git-common-dir>/ums-protected-branches` existuje, (b) obsahuje řádek `Branches/*`, (c) nemá CR, (d) push do `Branches/5.37` je po instalaci zamítnutý, (e) instalátor skončil exit 0.

- [ ] **Step 2: Spusť sadu a ověř, že nový případ selže**

Run: `pwsh -NoProfile -File ums/.claude/hooks/tests/pre-push.tests.ps1`
Expected: FAIL — `ums-protected-branches` neexistuje.

- [ ] **Step 3: Implementuj generování**

V `install-git-hooks.ps1` přidej ke konstantám:

```powershell
$PROTECTED_LIST_NAME = 'ums-protected-branches'
$EXIT_LIST_FAILED = 4
```

Za dot-source konstant vlož načtení loaderu s primární cestou a fallbackem (Resolution Protocol kontraktu — `$SourceDir` je `ums/.claude/hooks`, takže `..\skills\shared\scripts` je sesterská cesta):

```powershell
$loader = Join-Path $SourceDir '..\skills\shared\scripts\Get-UmsRepoConfig.ps1'
if (-not (Test-Path -LiteralPath $loader)) {
    $loader = Join-Path $PSScriptRoot '..\skills\shared\scripts\Get-UmsRepoConfig.ps1'
}
if (-not (Test-Path -LiteralPath $loader)) {
    throw "Get-UmsRepoConfig.ps1 not found next to the hooks directory: $loader"
}
. $loader
```

Přidej funkci, která seznam zapíše. LF konce řádků explicitně, UTF-8 bez BOM (PS7 `Set-Content -Encoding UTF8` BOM nepřidává — ověřeno bajtově):

```powershell
# Materializes protectedBranches as one glob per line for the pre-push hook,
# which is POSIX sh and cannot parse JSON. Written into the COMMON dir so a
# single install covers every working tree of the repository.
function Write-ProtectedList([string] $Root, [string[]] $Patterns) {
    $common = & git -C $Root rev-parse --git-common-dir 2>&1
    if ($LASTEXITCODE -ne 0) { throw "git rev-parse --git-common-dir failed for '$Root': $common" }
    $common = (($common | Select-Object -First 1).ToString()).Trim()
    if (-not [IO.Path]::IsPathRooted($common)) { $common = Join-Path $Root $common }
    $dst = Join-Path $common $PROTECTED_LIST_NAME
    $header = '# Generated by install-git-hooks.ps1 from memory-bank/ums-repo.json - do not edit.'
    $body = (@($header) + @($Patterns)) -join "`n"
    [IO.File]::WriteAllText($dst, $body + "`n", (New-Object Text.UTF8Encoding($false)))
    return $dst
}
```

Za blok, který hlásí `core.hooksPath`, vlož vlastní zápis a jeho hlášení:

```powershell
$repoCfg = Get-UmsRepoConfig $RepoRoot
try {
    $listPath = Write-ProtectedList $RepoRoot $repoCfg.ProtectedBranches
    Write-Host "protected-branch list ($($repoCfg.Source)) -> $listPath" -ForegroundColor Cyan
    Write-Host "  patterns: $($repoCfg.ProtectedBranches -join ', ')" -ForegroundColor DarkGray
}
catch {
    Write-Host "WARNING: could not write the protected-branch list: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host '         pre-push falls back to its built-in list (develop, main, master, release/*),' -ForegroundColor Red
    Write-Host '         so any additional protected pattern from the configuration is NOT enforced here.' -ForegroundColor Red
    $script:ListFailed = $true
}
```

Na začátku skriptu inicializuj `$script:ListFailed = $false` a v souhrnu, pokud je `$true` a `$exitCode` je dosud `$EXIT_OK`, nastav `$exitCode = $EXIT_LIST_FAILED`.

- [ ] **Step 4: Rozšiř self-test o třetí běh**

Do `Test-HookIsLive` přidej třetí syntetický běh, který dokazuje, že hook **konzultuje vygenerovaný seznam**: použij první vzor z konfigurace, který není ve vestavěném seznamu; pokud takový neexistuje, tento díl přeskoč a ohlas to. Podpis funkce rozšiř na `Test-HookIsLive([string] $Shell, [string] $HookPath, [string[]] $Patterns)`:

```powershell
    # Third run: proves the hook actually READS the generated list, not just
    # that its built-in fallback works. Uses the first configured pattern that
    # the built-in list does not already cover; with no such pattern there is
    # nothing this run could distinguish, so it is skipped and reported.
    $builtin = @('develop', 'main', 'master', 'release/*')
    $extra = @($Patterns | Where-Object { $builtin -notcontains $_ }) | Select-Object -First 1
    $extraResult = $null
    if ($extra) {
        $sample = ($extra -replace '\*', 'x')
        $extraResult = Invoke-HookLine $Shell $HookPath "refs/heads/$sample $SHA_FAKE refs/heads/$sample $SHA_FAKE"
    }
```

Do výsledku funkce přidej `Extra = $extraResult; ExtraPattern = $extra` a do podmínky `$ok` přidej: pokud `$extraResult` není `$null`, musí mít nenulový exit kód a `UMS: ` ve výstupu.

**Uprav i místo volání**, jinak se třetí běh nikdy nespustí — v souhrnu nahraď `Test-HookIsLive $shell $hook.Path` za `Test-HookIsLive $shell $hook.Path $repoCfg.ProtectedBranches`. V souhrnu vypiš buď `verified: the generated protected-branch list is consulted (pattern '<extra>')`, nebo `note: no configured pattern beyond the built-in list, so the generated list could not be proven live`.

Doplň nový exit kód do bloku `.DESCRIPTION` v hlavičce (`4  the protected-branch list could not be written - configured patterns beyond the built-in list are NOT enforced`).

- [ ] **Step 5: Spusť sadu a ověř, že prochází**

Run: `pwsh -NoProfile -File ums/.claude/hooks/tests/pre-push.tests.ps1`
Expected: PASS, exit 0.

- [ ] **Step 6: Spusť instalátor proti tomuto klonu**

```bash
pwsh -NoProfile -File ums/.claude/hooks/install-git-hooks.ps1 -RepoRoot .
echo "exit=$?"
cat "$(git rev-parse --git-common-dir)/ums-protected-branches"
```

Expected: `exit=0`, řádek `protected-branch list (file) -> …`, `verified:` u obou původních běhů i u třetího (vzor `ums-memory-bank` ve vestavěném seznamu není), a vypsaný soubor obsahuje šest vzorů z tasku 3.

- [ ] **Step 7: Commit**

```bash
git add ums/.claude/hooks/install-git-hooks.ps1 ums/.claude/hooks/tests/pre-push.tests.ps1
git commit -m "UMS: instalátor generuje seznam chráněných větví pro pre-push

Seznam se materializuje z ums-repo.json do <git-common-dir>, protože hook
je POSIX sh bez JSON parseru; změna konfigurace tedy vyžaduje nový běh
instalátoru. Self-test dostal třetí běh, který dokazuje, že hook seznam
skutečně čte, ne že jen funguje jeho vestavěný fallback. Nový exit kód 4
znamená, že seznam se nepodařilo zapsat a vzory nad vestavěný seznam
nejsou vynucené."
```

---

### Task 6: `guard-git-push.mjs` — chráněný seznam z konfigurace

**Files:**
- Modify: `ums/.claude/hooks/guard-git-push.mjs`
- Modify: `ums/.claude/hooks/tests/guard-git-push.tests.ps1`

**Interfaces:**
- Consumes: `memory-bank/ums-repo.json` a jeho klíč `protectedBranches` z tasku 3; refspecový tvar rady z tasku 4.
- Produces: nic pro další tasky.

- [ ] **Step 1: Napiš selhávající testy**

Do `guard-git-push.tests.ps1` přidej případy: (1) s konfigurací obsahující `Branches/*` je `git push origin Branches/5.37` zamítnutý; (2) bez konfigurace tentýž příkaz projde (fallback nezná `Branches/*`); (3) bez konfigurace je `git push origin develop` stále zamítnutý; (4) rozbitá konfigurace se chová jako chybějící; (5) zamítací hláška obsahuje `HEAD:`.

Testy předávají `cwd` v JSONu na stdin, takže fixture je jen adresář s `memory-bank/ums-repo.json`.

- [ ] **Step 2: Spusť sadu a ověř, že nové případy selžou**

Run: `pwsh -NoProfile -File ums/.claude/hooks/tests/guard-git-push.tests.ps1`
Expected: FAIL — případ 1 propustí push a případ 5 nenajde `HEAD:`.

- [ ] **Step 3: Implementuj čtení konfigurace**

V `guard-git-push.mjs` přidej import a nahraď konstantu `PROTECTED` funkcí, která vzory načte z konfigurace a přeloží glob na regulární výraz:

```javascript
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const BUILTIN_PROTECTED = ['develop', 'main', 'master', 'release/*'];

// Glob -> anchored, case-insensitive regex. Only `*` is a wildcard here; every
// other regex metacharacter is escaped, so a pattern like `release/*` cannot
// accidentally mean something else.
const globToRe = (glob) =>
  new RegExp('^' + String(glob).replace(/[.*+?^${}()|[\]\\]/g, '\\$&').replace(/\\\*/g, '.*') + '$', 'i');

// Same source of truth as the pre-push hook, read directly (this is Node, a
// JSON parser is available). A missing or malformed file falls back to the
// built-in list: degradation must lead to MORE protection, never less.
const loadProtected = (cwd) => {
  try {
    const raw = readFileSync(join(cwd || process.cwd(), 'memory-bank', 'ums-repo.json'), 'utf8');
    const list = JSON.parse(raw)?.protectedBranches;
    if (Array.isArray(list) && list.length > 0) return list.map(globToRe);
  } catch { /* missing or malformed -> built-in list below */ }
  return BUILTIN_PROTECTED.map(globToRe);
};

const isProtected = (ref, patterns) => patterns.some((re) => re.test(stripRef(ref)));
```

`isProtected` je volaná z `evaluatePush` a `evaluateFetch` — obě funkce dostanou vzory parametrem (`evaluatePush(args, cwd, patterns)`, `evaluateFetch(args, patterns)`), vzory se načtou **jednou** v `process.stdin.on('end')` a předají dál. Nenačítej je při každém volání.

- [ ] **Step 4: Oprav zamítací hlášku**

V `sharedBranchMessage` nahraď `git push origin ${branch}` za `git push origin HEAD:${branch}`. Ve hlášce `evaluateFetch` o žolíkovém refspecu nahraď natvrdo vypsaný výčet `(develop, main, master, release/*)` za neutrální formulaci `(sdílené větve dle konfigurace repozitáře)`, aby text nelhal, když je seznam jiný.

- [ ] **Step 5: Spusť sadu a ověř, že prochází**

Run: `pwsh -NoProfile -File ums/.claude/hooks/tests/guard-git-push.tests.ps1`
Expected: PASS, exit 0.

- [ ] **Step 6: Commit**

```bash
git add ums/.claude/hooks/guard-git-push.mjs ums/.claude/hooks/tests/guard-git-push.tests.ps1
git commit -m "UMS: guard-git-push čte chráněné větve z konfigurace

Obě vrstvy vynucení tím drží jeden zdroj pravdy; kontrakt na jejich
neshodě výslovně varuje. Glob se překládá na zakotvený case-insensitive
regex, chybějící nebo rozbitá konfigurace padá na vestavěný seznam.
Zamítací hláška radí refspecový tvar."
```

---

### Task 7: `doc-index.ps1` — báze z konfigurace a filtr podle aktivity větve

**Files:**
- Modify: `ums/.claude/skills/mb-doc-index/scripts/doc-index.ps1`
- Modify: `ums/.claude/skills/mb-doc-index/tests/enumeration.tests.ps1`
- Modify: `ums/.claude/skills/mb-doc-index/tests/findings.tests.ps1`
- Modify: `ums/.claude/skills/mb-doc-index/tests/new-fixture-repo.ps1`

**Interfaces:**
- Consumes: `Get-UmsRepoConfig` z tasku 3.
- Produces: `-BaseRef` s prázdným defaultem (rozliší „nezadáno" od hodnoty), `-SinceDays` s defaultem 30 v novém významu **poslední aktivita větve**, a chování „při deklarovaném záměru bez časového omezení".

- [ ] **Step 1: Přepiš testy enumerace**

Semantika `-SinceDays` se mění, takže sada se **nerozšiřuje, ale přepisuje**. V `new-fixture-repo.ps1` nastavuj commitům datum explicitně přes `GIT_COMMITTER_DATE` a `GIT_AUTHOR_DATE`, aby byly deterministické. Nové případy:

1. Větev, jejíž **tip** je starší než okno, v tabulce není.
2. Větev, jejíž tip je v okně, ale její návrhový dokument vznikl commitem **starším** než okno, v tabulce **je** — to je opravená falešná negativa; ve staré semantice vypadla.
3. `refs/remotes/origin/HEAD` (symref na bázi) nezpůsobí duplicitní záznam ani chybu.
4. `-BranchGlob` se aplikuje před filtrem aktivity: větev mimo glob se nezapočítá, i kdyby byla čerstvá.
5. Bez `-BaseRef` se báze vezme z `memory-bank/ums-repo.json` fixture repa; s explicitním `-BaseRef` má parametr přednost.
6. Neexistující báze z konfigurace hlásí `Base ref not found:` a exit 1 (chování zůstává).

Do `findings.tests.ps1` přidej: uspaná větev (tip starší než okno) se **stejným Jira tiketem** je při `-Jira <ticket>` stále hlášená jako `KOLIZE AKTIVNÍ PRÁCE` s exitem 2, zatímco bez deklarovaného záměru se v tabulce neobjeví.

- [ ] **Step 2: Spusť sady a ověř, že selžou**

Run: `pwsh -NoProfile -File ums/.claude/skills/mb-doc-index/tests/enumeration.tests.ps1`
Run: `pwsh -NoProfile -File ums/.claude/skills/mb-doc-index/tests/findings.tests.ps1`
Expected: FAIL — případ 2 nenajde záznam (starý `--since` ho odfiltruje) a případ 5 spadne na `Base ref not found: origin/develop`.

- [ ] **Step 3: Implementuj bázi z konfigurace**

Změň default parametru na prázdný řetězec a doplň dokumentaci v `.PARAMETER BaseRef`, že prázdná hodnota znamená „vezmi z konfigurace":

```powershell
    [string] $BaseRef = '',
    [int]    $SinceDays = 30,
```

Za resolvování `$RepoPath` a před ověření báze vlož:

```powershell
# Repository configuration (contract: "Repository Configuration"). An explicit
# -BaseRef always wins; the empty default means "take it from the config",
# whose own fallback is origin/develop.
$loader = Join-Path $PSScriptRoot '..\..\shared\scripts\Get-UmsRepoConfig.ps1'
if (-not (Test-Path -LiteralPath $loader)) {
    Write-Error "Get-UmsRepoConfig.ps1 not found at $loader"; exit 1
}
. $loader
$script:RepoCfg = Get-UmsRepoConfig $RepoPath
if (-not $BaseRef) { $BaseRef = $script:RepoCfg.BaseRef }
```

- [ ] **Step 4: Implementuj filtr podle aktivity větve**

Nahraď dosavadní výpočet `$since` a volání `git log --remotes=origin --not $BaseRef --since=…` dvoustupňovým filtrem. Nejdřív enumerace refů:

```powershell
# Stage 1: pick branches by their TIP's age - one ref read, no history walk.
# This replaces the old --since, which filtered by COMMIT date and therefore
# dropped a live branch whose design document was committed long ago.
# refs/remotes/origin/HEAD is a symref to the base and must be skipped, or it
# duplicates the base.
function Get-ActiveRemoteRefs([int] $Days, [string] $Glob) {
    $cutoff = if ($Days -gt 0) { [DateTimeOffset]::UtcNow.AddDays(-$Days).ToUnixTimeSeconds() } else { 0 }
    $raw = Invoke-RepoGit @('for-each-ref', '--format=%(refname) %(committerdate:unix)', 'refs/remotes/origin/')
    Stop-OnGitFailure 'for-each-ref refs/remotes/origin/'
    $out = @()
    foreach ($line in @($raw)) {
        if (-not $line) { continue }
        $parts = ($line.ToString().Trim() -split ' ', 2)
        if (@($parts).Count -lt 2) { continue }
        $refName = $parts[0]
        if ($refName -eq 'refs/remotes/origin/HEAD') { continue }
        $short = $refName -replace '^refs/remotes/', ''
        # Glob BEFORE the activity filter, so an excluded branch never counts.
        if ($Glob -and ($short -notlike $Glob)) { continue }
        $stamp = 0
        [void][int64]::TryParse($parts[1], [ref] $stamp)
        if ($cutoff -gt 0 -and $stamp -lt $cutoff) { continue }
        $out += [pscustomobject]@{ Ref = $refName; Short = $short; Activity = $stamp }
    }
    return $out
}
```

Pak traversal přes `--stdin`, protože stovky refů na příkazové řádce narazí na 32k limit Windows:

```powershell
# Declared intent must NOT be narrowed by the display window: a colleague's
# dormant branch on the SAME ticket is exactly what has to stop pinning. So
# enumerate WIDE when intent is declared and filter narrow only for display.
$enumDays = if ($Jira -or $Slug) { 0 } else { $SinceDays }
$activeRefs = Get-ActiveRemoteRefs $enumDays $BranchGlob
$displayCutoff = [DateTimeOffset]::UtcNow.AddDays(-$SinceDays).ToUnixTimeSeconds()

$log = ''
if (@($activeRefs).Count -gt 0) {
    $revs = (@($activeRefs | ForEach-Object { $_.Ref }) + @("^$BaseRef")) -join "`n"
    $log = $revs | & git -C $RepoPath log --stdin --name-only `
        '--format=%x01%H%x09%cI%x09%an' '--' `
        ':(glob)**/memory-bank/proposals/next/*.md' `
        ':(glob)**/memory-bank/proposals/active/*.md' `
        ':(glob)**/memory-bank/proposals/completed/*.md' 2>$null
    Stop-OnGitFailure 'log --stdin --not <BaseRef>'
}
```

Ke každé položce indexu doplň pole `activity` (hodnota `Activity` větve, ze které záznam pochází) a v místě, kde se skládá `$printable`, přidej k filtru fází ještě `$_.activity -ge $displayCutoff -or -not $_.activity`. Nálezy se počítají z **plné** množiny, ne z `$printable`.

Uprav hlavičku výstupu, aby neříkala nepravdu o významu okna:

```powershell
Write-Output "📇 Index dokumentů (báze $BaseRef, větve s aktivitou za posledních $SinceDays dní)"
```

a řádek o prázdné tabulce na `_(žádné položky ve fázích next/active mezi větvemi aktivními v okně -SinceDays)_`.

- [ ] **Step 5: Spusť sady a ověř, že procházejí**

Run: `pwsh -NoProfile -File ums/.claude/skills/mb-doc-index/tests/enumeration.tests.ps1`
Run: `pwsh -NoProfile -File ums/.claude/skills/mb-doc-index/tests/findings.tests.ps1`
Expected: PASS u obou, exit 0.

- [ ] **Step 6: Ověř proti skutečnému repozitáři a změř**

Read-only běh, takže je bezpečný. Nejdřív tento fork:

```bash
pwsh -NoProfile -Command "Measure-Command { pwsh -NoProfile -File ums/.claude/skills/mb-doc-index/scripts/doc-index.ps1 } | Select-Object -ExpandProperty TotalSeconds"
```

Pak proti klonu se stovkami vzdálených větví (v tomto prostředí monorepo UMS; cestu předej parametrem, nezapisuj ji do skriptů):

```bash
pwsh -NoProfile -Command "Measure-Command { pwsh -NoProfile -File ums/.claude/skills/mb-doc-index/scripts/doc-index.ps1 -RepoPath <cesta ke klonu> -NoFetch } | Select-Object -ExpandProperty TotalSeconds"
git -C <cesta ke klonu> branch -r | wc -l
```

Expected: běh proti forku pod 3 s; běh proti velkému klonu s vypsaným počtem větví. **Obě čísla zapiš** do `memory-bank/tech.md` na místo dosavadní věty „Výkon `doc-index.ps1` je ověřený jen v malém měřítku", kterou tím nahradíš. Pokud velký klon není k dispozici, ponech tu věto beze změny a nahlas to jako neověřené — nevymýšlej číslo.

- [ ] **Step 7: Commit**

```bash
git add ums/.claude/skills/mb-doc-index/ memory-bank/tech.md
git commit -m "UMS: doc-index filtruje podle aktivity větve a bere bázi z konfigurace

Dosavadní --since filtroval podle data commitu, takže živá větev, jejíž
návrhový dokument vznikl dávno, z indexu vypadla — proto byl default
nafouknutý na 120 dní. Nově se vzory vybírají podle data tipu větve
(jedno čtení refů) a přeživší větve se traversují bez datového omezení,
takže se historie návrhu najde celá. Default je 30 dní.

Deklarovaný záměr (-Jira/-Slug) běží bez časového omezení: uspaná větev
kolegy na témže tiketu je právě ta informace, která musí zastavit
pinování. Refy se předávají přes git log --stdin kvůli 32k limitu
příkazové řádky, symref origin/HEAD se vynechává a -BranchGlob se
aplikuje před filtrem aktivity."
```

---

### Task 8: Tři overlay fragmenty

**Files:**
- Modify: `ums/.claude/skills/shared/overlays/brainstorming.overlay.md`
- Modify: `ums/.claude/skills/shared/overlays/subagent-driven-development.overlay.md`
- Modify: `ums/.claude/skills/shared/overlays/finishing-a-development-branch.overlay.md`

**Interfaces:**
- Consumes: jména sekcí kontraktu a cestu kandidátů z tasku 2.
- Produces: nic pro další tasky (vendorované kopie vyrábí revendor v monorepu, mimo tuto větev).

- [ ] **Step 1: `brainstorming.overlay.md`**

V odrážce **Item 6** nahraď větu o založení větve: místo „if you are on the default branch, create a feature branch in place first" napiš, že tiketová větev se zakládá `git switch -c <TICKET>-<kebab-slug> origin/<baseRef>` po `git fetch origin`, **vždy s explicitním výchozím bodem** (implicitní tvar na cizí tiketové větvi vtáhne do historie její pin a její aktivní pár), a že po založení musí platit postkondice: `proposals/active/` prázdný nebo chybějící a `context.md` ve stavu `IDLE`, jinak STOP a větev smazat. `baseRef` přichází z `<CTX_DIR>/ums-repo.json`.

Větu o publikaci (`publication point 1`) nahraď odkazem na pravidlo push po každém commitu.

Do odrážky **Item 1** doplň, že před pinováním práce se ověří způsobilost workspace dle sekce `Workspace Discipline` kontraktu — instalovaný a ověřený `pre-push` hook je fail-closed podmínka.

- [ ] **Step 2: `subagent-driven-development.overlay.md`**

- Odrážku **Isolation** ponech (zákaz worktrees platí), jen doplň, že volbu workspace vlastní uživatel a sezení běží v tom workspace, kde práce je.
- Do odrážky **Playbook candidates** změň cestu na `<MB_ROOT>/.superpowers/playbook-candidates/<slug>.md` a přepiš věto o přepisu: přepisuje se soubor **téhož slugu**, cizí slugy mají vlastní soubory a nikdy se nemažou.
- Odrážku **Publication** přepiš na pravidlo push po každém commitu, s poznámkou, že to zahrnuje commit implementátora po zeleném tasku.
- Přidej odrážku **Base sync**: před dispatchem prvního tasku `fetch` a `merge origin/<baseRef>`, pak posouzení průniku a případná verifikace dle sekce `Base Sync & Drift Detection`; **nikdy nemerguj bázi uprostřed tasku**. Povinná baseline před prvním dispatchem zůstává.

- [ ] **Step 3: `finishing-a-development-branch.overlay.md`**

Přepiš odrážky k Option 1. Kotva `ANCHOR-BEFORE: ## Step 5: Execute Choice` zůstává nezměněná.

- Smaž otázku na refresh lokální báze i větu „Merge with `--no-ff` per repo convention".
- Napiš, že upstream Option 1 „Merge Locally" se v tomto repozitáři **nahrazuje** integrací pushem tiketové větve (stejný typ přesměrování jako u cesty k dokumentům): před harvestem base sync, po harvestu a jeho commitu `fetch` a `merge origin/<baseRef>`, zelená verifikace, a pak předání příkazu `! UMS_ALLOW_SHARED_PUSH=1 git push origin HEAD:<baseRef>` uživateli s výčtem odchozích commitů. Agent nepushuje sdílenou větev a nikdy si tu proměnnou nenastavuje; `--no-verify` není náhrada.
- Doplň souběh: selhání pushe na non-fast-forward znamená pohnutou bázi, opakuj od `fetch`, strop dvě kola, pak STOP a report.
- Ponech, že `mb-jira-update` ve finalizačním režimu běží až po ověřené dosažitelnosti, a přeformuluj spouštěč z „po zeleném lokálním mergi" na „po ověřeném FF pushi do báze".

- [ ] **Step 4: Ověř, že fragmenty nelžou o kontraktu**

```bash
rg -n 'no-ff|lokálního develop|playbook-candidates\.md|publication point' ums/.claude/skills/shared/overlays/ ; echo "exit=$?"
```

Expected: žádný výstup a `exit=1`.

```bash
rg -n 'ANCHOR-BEFORE: ## Step 5: Execute Choice' ums/.claude/skills/shared/overlays/finishing-a-development-branch.overlay.md
```

Expected: jeden nález — kotva se nesmí změnit, jinak revendor přestane fragment aplikovat.

- [ ] **Step 5: Commit**

```bash
git add ums/.claude/skills/shared/overlays/
git commit -m "UMS: overlaye — FF integrace, base sync, zakládání větve z báze

finishing dostal největší přepis: upstream Option 1 se nahrazuje
integrací pushem tiketové větve, mizí otázka na refresh lokální báze
i konvence --no-ff. brainstorming zakládá větev s explicitním výchozím
bodem a kontroluje postkondici. SDD dostal base sync na hranici před
prvním dispatchem, zákaz merge uprostřed tasku a cestu kandidátů
per slug. Kotva ANCHOR-BEFORE zůstává nezměněná."
```

---

### Task 9: `mb-park` a kandidáti playbooku per slug

**Files:**
- Create: `ums/.claude/skills/mb-park/SKILL.md`
- Modify: `ums/.claude/skills/shared/SKILLS_MANIFEST.md`
- Modify: `ums/.claude/skills/mb-harvest/SKILL.md`

**Interfaces:**
- Consumes: sekci `Workspace Discipline` a cestu kandidátů z tasku 2.
- Produces: skill `mb-park` volaný ze vstupní brány (task 10) — jeho jméno a chování „commit, push, ohlášení zbytků, commit kandidátů, větev zůstává checkoutnutá".

- [ ] **Step 1: Napiš `mb-park/SKILL.md`**

Struktura podle sesterského `mb-abort/SKILL.md` (frontmatter `name`/`description`, `# Command: mb-park`, `## Workflow` s číslovanými kroky, `## Report (Czech)`). Tělo anglicky, report česky. Kroky:

0. **Resolve and gate** — `MB_ROOT` jedním `git rev-parse --show-toplevel`; existence `memory-bank/`; `context.md` musí být `ACTIVE_WORK` (IDLE = není co parkovat, řekni to a skonči); přečti `Work item` slug.
1. **Inventura** — `git status --porcelain`, `git stash list`, `git log --branches --not --remotes`. Prázdný strom, prázdný stash a nic nepushnutého znamená, že práce **už je zaparkovaná** — ohlas to a skonči bez commitu.
2. **Commit** — vyvolej `mb-git-commit` (nikdy necommituj sám, aby platila jedna konvence commit messages). Stash se nikdy nezahrnuje: jeho existence se ohlásí, ale park ho neřeší.
3. **Kandidáti** — pokud `<MB_ROOT>/.superpowers/playbook-candidates/<slug>.md` existuje a je neprázdný, přidej ho `git add -f` a commitni (pojmenovaná výjimka dle kontraktu). Harvest ho po zápisu do `playbook.md` smaže.
4. **Publikace** — push vlastní tiketové větve s ohlášením větve a odchozích commitů. Sdílenou větev agent nepushuje; když je aktuální větev v `protectedBranches`, připrav příkaz pro uživatele.
5. **Report** — co je zaparkované (slug, tiket, větev), co ve workspace zůstává neobnovitelného (stash, kandidáti jiných slugů, nepushnuté commity jiných větví), a že `context.md` zůstává `ACTIVE` na této větvi. Větev zůstává checkoutnutá — žádné zbytečné přepnutí, tedy žádný zbytečný rebuild.

Do `## Poznámky` napiš, čím se park liší od `mb-abort` (nezahazuje, pár zůstává v `active/`) a od finishing (neharvestuje, neuzavírá).

- [ ] **Step 2: Zaregistruj skill do manifestu**

Do tabulky skillů v `SKILLS_MANIFEST.md` přidej za řádek `mb-abort`:

```markdown
| mb-park | [mb-park/SKILL.md](../mb-park/SKILL.md) | Odložení rozpracované práce: commit, publikace, commit kandidátů playbooku; pár zůstává v `active/` a `context.md` v ACTIVE |
```

- [ ] **Step 3: Uprav `mb-harvest` na cestu per slug**

V `mb-harvest/SKILL.md` nahraď každý výskyt `.superpowers/playbook-candidates.md` za `.superpowers/playbook-candidates/<slug>.md`. V popisu playbookové brány doplň: soubor může být **commitnutý na větvi** (park ho tam přidal), takže po zápisu do `playbook.md` se maže `git rm -f`, ne jen `Remove-Item`; když trackovaný není, stačí smazání souboru. Pravidlo „prázdný nebo cizí soubor bránu přeskočí bez otázky" zůstává, jen „cizí" teď znamená „soubor jiného slugu", který se **nečte ani nemaže**.

- [ ] **Step 4: Ověř konzistenci**

```bash
rg -n 'playbook-candidates\.md' ums/ ; echo "exit=$?"
```

Expected: žádný výstup a `exit=1` — všechny výskyty nesou cestu per slug.

```bash
rg -n 'mb-park' ums/.claude/skills/shared/SKILLS_MANIFEST.md
ls ums/.claude/skills/mb-park/SKILL.md
```

Expected: nález v manifestu a existující soubor skillu.

- [ ] **Step 5: Commit**

```bash
git add ums/.claude/skills/mb-park/ ums/.claude/skills/shared/SKILLS_MANIFEST.md \
        ums/.claude/skills/mb-harvest/SKILL.md
git commit -m "UMS: skill mb-park a kandidáti playbooku per slug

Vrstva umí práci dokončit a opustit, ale neměla nic pro odložení — a to
je hlavní režim opakovaně používaného workspace. mb-park commituje,
publikuje a nechává pár v active/ i context.md v ACTIVE.

Kandidáti playbooku dostali cestu per slug: fixní cesta s přepisovacím
pravidlem mazala živé důkazy při přepínání mezi živými tikety. Park je
navíc commituje na větev, takže zaparkovaná práce je celá obnovitelná
z origin a pokračovat lze v jakémkoli workspace."
```

---

### Task 10: `mb-state` jako orákulum způsobilosti workspace

**Files:**
- Modify: `ums/.claude/skills/mb-state/SKILL.md`

**Interfaces:**
- Consumes: definici volného workspace, třídění zbytků a `ticketPattern` z tasků 2 a 3; jméno `mb-park` z tasku 9.
- Produces: nic pro další tasky.

- [ ] **Step 1: Rozšiř `### 1. Gather state (read-only)`**

Přidej odrážky, každou s konkrétním příkazem:

- **Workspace readiness:** `git rev-parse --git-path hooks/pre-push` — soubor musí existovat a nést case-sensitive marker `UMS pre-push guard` na prvních pěti řádcích; `git config --get core.hooksPath` musí být nenastavený nebo relativní; `<CTX_DIR>/ums-repo.json` existuje (jinak se hlásí, že platí defaulty). Chybějící nebo neověřený hook je **nejzávažnější nález** — workspace zakládá uživatel a hooky se s klonem nepřenášejí.
- **Volný workspace:** `git status --porcelain`, `git stash list`, `git log --branches --not --remotes` — všechny tři prázdné znamenají „bez zbytků". Rozděl nálezy na **v cestě** (špinavý strom, stash) a **pouze přítomné** (nepushnuté commity jiných větví, kandidáti jiných slugů).
- **Zaparkovaná práce napříč lokálními větvemi:** pro každou lokální větev odpovídající `ticketPattern` přečti její pin bez přepnutí:

  ```
  git for-each-ref --format='%(refname:short) %(committerdate:short)' refs/heads/
  git show <branch>:memory-bank/context.md
  ```

  Vypiš slug, tiket a datum posledního commitu. Neexistující `context.md` na větvi není chyba.
- **Vzdálenost od báze:** `git rev-list --count HEAD..origin/<baseRef>` — kolik commitů báze chybí; nad nulou doporuč base sync na nejbližší hranici fáze.
- **Invariant báze:** `git show origin/<baseRef>:memory-bank/context.md` musí být `IDLE`; `ACTIVE` na bázi je **chyba**, protože každá nová větev z báze pak zdědí cizí pin.
- **Kandidáti playbooku:** vypiš soubory `.superpowers/playbook-candidates/*.md` a jejich slugy; soubory jiných slugů se jen hlásí a nikdy nemažou.

U two-actives odrážky uprav formulaci: aktivní slug **na aktuální větvi** odlišný od pinu je varování; slugy jiných lokálních větví jsou zaparkovaná práce, ne kolize.

Odrážku o exekučním progresu uprav na cestu per plán z tasku 1.

- [ ] **Step 2: Rozšiř `### 2. Report (Czech)`**

Do šablony reportu přidej řádky:

```
Workspace: [✅ způsobilý | ⚠️ pre-push hook chybí/neověřený | ⚠️ ums-repo.json chybí (platí defaulty)]
Zbytky: [žádné | v cestě: <výčet> | pouze přítomné: <výčet>]
Zaparkováno: <žádné | výčet větev → slug (tiket, datum)>
Báze: <baseRef> — chybí <N> commitů <(⚠️ ACTIVE stav na bázi)>
Kandidáti playbooku: <žádní | výčet slugů>
```

Do „Další krok" přidej: `zbytky v cestě → mb-park (odložit) nebo zahodit po potvrzení`, `pre-push chybí → install-git-hooks.ps1 a znovu ověřit`, `báze chybí commity → base sync na nejbližší hranici fáze`.

- [ ] **Step 3: Ověř, že skill zůstal read-only**

```bash
rg -n 'git (add|commit|push|switch|checkout|merge|rm|stash)' ums/.claude/skills/mb-state/SKILL.md ; echo "exit=$?"
```

Expected: buď žádný výstup, nebo jen výskyty uvnitř doporučení „Další krok" jako text pro uživatele — žádný krok workflow nesmí měnit stav. Zkontroluj každý nález očima.

- [ ] **Step 4: Commit**

```bash
git add ums/.claude/skills/mb-state/SKILL.md
git commit -m "UMS: mb-state jako orákulum způsobilosti workspace

Odpovídá na tři otázky uzavřené smyčky: je workspace volný (tři git
příkazy, žádná evidence), co je tu zaparkovaného napříč lokálními
větvemi, a co je v cestě. Přidána kontrola instalovaného pre-push hooku
(workspace zakládá uživatel a hooky se s klonem nepřenášejí), vzdálenost
od báze a invariant, že báze nese IDLE. Zůstává read-only."
```

---

### Task 11: `mb-init` detekuje konfiguraci repozitáře

**Files:**
- Modify: `ums/.claude/skills/mb-init/SKILL.md`

**Interfaces:**
- Consumes: schéma a klíče konfigurace z tasků 2 a 3.
- Produces: nic pro další tasky.

- [ ] **Step 1: Přidej režim detekce konfigurace**

Do workflow `mb-init` přidej krok, který se spouští v režimu orchestračního kořene (`CTX_DIR`) a vytváří `<CTX_DIR>/ums-repo.json`. Detekce po klíčích, každá s konkrétním příkazem:

- `baseRef` — `git symbolic-ref --quiet refs/remotes/origin/HEAD` (dá výchozí větev vzdáleného repozitáře); když chybí, zkus v tomto pořadí `origin/develop`, `origin/main`, `origin/master` přes `git rev-parse --verify --quiet`; když neuspěje nic, zapiš `origin/develop` a řekni to.
- `protectedBranches` — vestavěné čtyři vzory plus detekované: pro každý prefix vzdálených větví, který má víc než jednu větev a vypadá jako release řada (`git for-each-ref --format='%(refname:short)' refs/remotes/origin/` a seskupení podle prvního segmentu před `/`), navrhni `<prefix>/*`. Kandidáty **vypiš** a nech uživatele potvrdit, které patří dovnitř.
- `ticketPattern` — z jmen existujících vzdálených větví odvoď nejčastější předponu tvaru `^[A-Z]+-[0-9]+`; když žádná není, zapiš obecný `^[A-Z][A-Z0-9]+-[0-9]+`.
- `projectMarkers` — podle nalezených build souborů: `*.sln`/`*.csproj` (dotnet), `*.vcxproj` (MSVC), `package.json` (node), `pom.xml`, `build.gradle`, `Cargo.toml`, `pyproject.toml`. Zapiš jen ty, které se v repozitáři skutečně vyskytují.
- `sharedRoots` — adresáře prvního nebo druhého řádu, které obsahují projektové soubory referencované z víc než jednoho jiného projektu, plus nalezené sdílené build soubory (`Directory.Build.props`, `Directory.Packages.props`, `*.targets` v kořeni, `SharedAssemblyInfo*`, kořenové `*.sln`, `Build.proj`).

Napiš výslovně, že **první zapsaná verze schválení nepotřebuje** — je to tatáž výjimka a ze stejného důvodu jako první `playbook.md` (detekované hodnoty jsou ověřitelné proti build souborům samotným) — a že se v reportu vypíše, co bylo detekováno a co dosazeno jako default.

- [ ] **Step 2: Přidej režim obnovy**

Přidej režim nad **existujícím** souborem: detekuj znovu, porovnej s obsahem souboru a předlož **rozdíl** po klíčích. Zapiš až po schválení uživatele; nic nezapisuj, když se rozdíl nenajde. Odkaž na kontrakt, sekci `Repository Configuration`, kde je pravidlo o schvalování pozdějších změn.

Doplň poznámku, že po změně `protectedBranches` je nutný nový běh `install-git-hooks.ps1`, jinak `pre-push` pracuje se starým vygenerovaným seznamem.

- [ ] **Step 3: Ověř**

```bash
rg -n 'ums-repo\.json' ums/.claude/skills/mb-init/SKILL.md
rg -n 'install-git-hooks' ums/.claude/skills/mb-init/SKILL.md
```

Expected: oba nálezy přítomné — schéma i připomínka nového běhu instalátoru.

- [ ] **Step 4: Commit**

```bash
git add ums/.claude/skills/mb-init/SKILL.md
git commit -m "UMS: mb-init detekuje konfiguraci repozitáře

Naplnění ums-repo.json má podporu, ne ruční sepisování: baseRef,
protectedBranches, ticketPattern, projectMarkers a sharedRoots se
detekují z topologie repozitáře. První verze schválení nepotřebuje —
tatáž výjimka a ze stejného důvodu jako první playbook.md. Přidán režim
obnovy, který nad existujícím souborem předloží rozdíl po klíčích."
```

---

### Task 12: Tři skilly, které změněná pravidla implementují

Kontrakt v tasku 2 pravidla **vyslovil**; tyto tři skilly je **provádějí**, takže bez nich by pravidlo existovalo jen jako text.

**Files:**
- Modify: `ums/.claude/skills/mb-architect-review/SKILL.md`
- Modify: `ums/.claude/skills/mb-jira-update/SKILL.md`
- Modify: `ums/.claude/skills/mb-git-commit/SKILL.md`

**Interfaces:**
- Consumes: integrační sekvenci, merge asymetrii a `ticketPattern` z tasků 2 a 3; pravidlo push po každém commitu z tasku 2.
- Produces: nic pro další tasky.

- [ ] **Step 1: `mb-architect-review` — branch sync a merge asymetrie**

- V kroku branch sync (první krok režimů respond a resume) doplň **merge asymetrii**: bázi merguje jen strana **řešitele** (request a resume). V režimu **respond** se báze nemerguje nikdy — skill má vlastní pravidlo „diverged local branch = STOP" a merge z obou stran by ho na té pojistce zastavil. Napiš to jako zákaz, ne jako doporučení.
- V režimech request a resume doplň base sync **před** handoff push: `fetch`, `merge origin/<baseRef>`, posouzení průniku a případná nabídka verifikace dle sekce `Base Sync & Drift Detection`. Pořadí kroků zůstává takové, aby jeden handoff potřeboval právě jeden push.
- V pořadí rozpoznávání tiketové větve (jméno z request komentáře → vzdálené větve obsahující kód tiketu → dotaz uživateli) doplň, že tvar jména je `<TICKET>-<kebab-slug>` a kód tiketu se poznává podle `ticketPattern` z konfigurace, ne podle zadrátovaného `UMS-`. Pravidlo „víc nejednoznačných kandidátů se vždy ptá" zůstává.

- [ ] **Step 2: `mb-jira-update` — spouštěč finalizace**

V sekci finalizačního režimu nahraď spouštěč „po zeleném lokálním mergi" za **„po ověřeném fast-forward pushi tiketové větve do báze"**. Brána dosažitelnosti (§6b) i vlastní brána finalizačního režimu zůstávají beze změny — mění se jen popis toho, co jim předchází, protože lokální merge už v modelu neexistuje. Doplň jednu větu, že dokud push do báze není ověřený jako dosažitelný na `origin`, tiket do „Test" nepřechází.

- [ ] **Step 3: `mb-git-commit` — vyjasnit hranici vůči publikaci**

Pravidlo „nikdy nepushuje" **zůstává**. Doplň k němu jednu větu, aby nekolidovalo s novým pravidlem push po každém commitu: publikaci provádí **volající** workflow krok bezprostředně po commitu, ne tento skill; commit a push jsou dvě odpovědnosti a tento skill má jen tu první. Bez toho by dvě pravidla vedle sebe vypadala jako rozpor.

- [ ] **Step 4: Ověř**

```bash
rg -n 'po zeleném lokálním mergi|lokální merge|--no-ff' ums/.claude/skills/mb-jira-update/SKILL.md ; echo "exit=$?"
```

Expected: žádný výstup a `exit=1`.

```bash
rg -n 'respond' ums/.claude/skills/mb-architect-review/SKILL.md | rg -n 'nemerguje|never merges'
rg -n 'ticketPattern' ums/.claude/skills/mb-architect-review/SKILL.md
rg -n 'volající|caller' ums/.claude/skills/mb-git-commit/SKILL.md
```

Expected: nález u všech tří — zákaz merge v režimu respond, `ticketPattern` místo zadrátovaného prefixu, a věta o tom, že pushuje volající.

- [ ] **Step 5: Commit**

```bash
git add ums/.claude/skills/mb-architect-review/SKILL.md \
        ums/.claude/skills/mb-jira-update/SKILL.md \
        ums/.claude/skills/mb-git-commit/SKILL.md
git commit -m "UMS: tři skilly implementují změněná pravidla o větvích

mb-architect-review dostal merge asymetrii (v režimu respond se báze
nemerguje nikdy, jinak by se skill zastavil na vlastním pravidle
o divergenci), base sync před handoff pushem a rozpoznávání tiketu podle
ticketPattern místo zadrátovaného prefixu.

mb-jira-update finalizuje po ověřeném FF pushi do báze, ne po lokálním
mergi, který v modelu už neexistuje.

mb-git-commit dál nikdy nepushuje — doplněna jen věta, že publikaci dělá
volající krok, aby to nevypadalo jako rozpor s pravidlem push po každém
commitu."
```

---

### Task 13: `CLAUDE.md` a `CLAUDE.md.sample`

**Files:**
- Modify: `CLAUDE.md`
- Modify: `ums/CLAUDE.md.sample`

**Interfaces:**
- Consumes: pravidla z tasku 2 a jméno `mb-park` z tasku 9.
- Produces: nic pro další tasky.

- [ ] **Step 1: Uprav `ums/CLAUDE.md.sample`**

V odrážce **Dokončení větve** smaž větu „Merge do develop dělej vždy `--no-ff` (explicitní merge commit dle konvence repa)." a větu „Před merge do lokálního develop se zeptej na refresh z origin/develop (fetch + FF, žádný push; nahrazuje upstream git pull)." Nahraď je: integrace je fast-forward push tiketové větve do báze; agent připraví `! UMS_ALLOW_SHARED_PUSH=1 git push origin HEAD:<baseRef>` s výčtem odchozích commitů a spouští ho uživatel; při selhání na non-fast-forward se báze pohnula, opakuj od `fetch`, strop dvě kola. Lokální báze se v tiketovém klonu nepoužívá.

Do odrážky **Exekuce plánu (SDD)** doplň: bázi merguj na hranicích fází (nikdy uprostřed tasku), po mergi porovnej příchozí a vlastní cesty a verifikaci **nabídni** podle průniku; povinná baseline před prvním dispatchem zůstává.

Přidej novou odrážku **Práce na více tiketech**: workspace vybírá a zakládá uživatel; sezení běží v tom workspace, kde práce je; jedno sezení na workspace; odložení je `mb-park`, ne `mb-abort`; přepínej jen na hranicích fází a jen s čistým stromem, žádný stash.

V sekci **Zákaz git worktree** ponech zákaz i mechanismy a přepiš jen zdůvodnění: měřením klon monorepa 25 GB, z toho `.git` 4,1 GB, takže linked worktree by ušetřil 16 %; izolace se řeší volbou workspace uživatelem.

- [ ] **Step 2: Uprav `CLAUDE.md` tohoto forku**

V sekci „Integrace s UMS Memory Bank (jen tento fork)" proveď tytéž tři změny (dokončení větve, exekuce plánu, více tiketů) a doplň jednu větu specifickou pro fork: integrační báze je `ums-memory-bank`, je uvedená v `memory-bank/ums-repo.json` mezi chráněnými větvemi, takže ji agent nepushuje.

- [ ] **Step 3: Ověř**

```bash
rg -n 'no-ff|lokálního develop|refresh z origin' CLAUDE.md ums/CLAUDE.md.sample ; echo "exit=$?"
```

Expected: žádný výstup a `exit=1`.

```bash
rg -n 'mb-park|HEAD:<baseRef>|jedno sezení na workspace' CLAUDE.md ums/CLAUDE.md.sample
```

Expected: nálezy v obou souborech.

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md ums/CLAUDE.md.sample
git commit -m "UMS: preference — FF integrace, base sync, práce na více tiketech

Zrušena konvence --no-ff i refresh lokální báze; integrace je
fast-forward push tiketové větve, který spouští uživatel. Doplněn base
sync na hranicích fází s odstupňovanou verifikací a nová odrážka o práci
na více tiketech (workspace vlastní uživatel, jedno sezení na workspace,
odložení je mb-park). Zákaz worktrees zůstává, mění se jen jeho
zdůvodnění na změřená čísla."
```

---

### Task 14: Obnova nasazení a celá testovací smyčka

Kořenový `.claude/` a `.agents/skills/` jsou netrackovaná **nasazení**, ale sezení v tomto repu čte právě je. Bez obnovy by agent po zbytek práce pracoval podle staré verze kontraktu i skillů.

**Files:**
- Modify: `.claude/` (netrackované nasazení — necommituje se)
- Modify: `.agents/skills/` (netrackované nasazení — necommituje se)

**Interfaces:**
- Consumes: všechny předchozí tasky.
- Produces: způsobilé pracovní prostředí pro navazující práci a zelenou celkovou sadu.

- [ ] **Step 1: Spusť celou testovací smyčku nad zdrojem**

```bash
for t in $(find ums -name "*.tests.ps1"); do echo "== $t"; pwsh -NoProfile -File "$t" || echo "FAILED: $t"; done
```

Expected: každá sada končí `<N> passed`; žádný řádek `FAILED:`. Sad je o jednu víc než před prací (nová `shared/tests/repo-config.tests.ps1`).

- [ ] **Step 2: Obnov nasazení UMS obsahu**

```bash
cp -r ums/.claude/skills/shared .claude/skills/
for d in ums/.claude/skills/mb-*; do cp -r "$d" .claude/skills/; done
cp -r ums/.claude/hooks/. .claude/hooks/
cp -r ums/.claude/scripts/. .claude/scripts/
cp ums/.claude/settings.json .claude/settings.json
mkdir -p .agents/skills && cp -r ums/.claude/skills/. .agents/skills/
```

- [ ] **Step 3: Ověř, že nasazení je aktuální**

```bash
rg -n '^- \*\*Contract-Version:\*\*' .claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md
ls -d ums/.claude/skills/mb-* | sed 's#.*/##' | sort > /tmp/src-skills.txt
ls -d .claude/skills/mb-*      | sed 's#.*/##' | sort > /tmp/dep-skills.txt
diff /tmp/src-skills.txt /tmp/dep-skills.txt && echo "skilly souhlasi"
ls .claude/skills/mb-park/SKILL.md
```

Expected: verze `2.6`; `skilly souhlasi`; `mb-park` v nasazení existuje (chybějící skill je nejrychlejší příznak zastaralého nasazení).

Tři upstream skilly s overlay bloky (`brainstorming`, `subagent-driven-development`, `finishing-a-development-branch`) se kopií **nevyrobí** — vznikají revendorem v monorepu. Ohlas to uživateli jako zbývající krok mimo tuto větev, neobcházej to ruční editací vendorovaných souborů.

- [ ] **Step 4: Přeinstaluj git hooky a ověř záruku**

```bash
pwsh -NoProfile -File ums/.claude/hooks/install-git-hooks.ps1 -RepoRoot .
echo "exit=$?"
```

Expected: `exit=0` a `[installed + verified live]`. Nenulový exit neignoruj: `1` self-test selhal, `2` ponechán cizí hook, `3` chybí shell pro self-test, `4` nepodařilo se zapsat seznam chráněných větví.

- [ ] **Step 5: Ohlas stav a připrav publikaci**

Nasazení se necommituje (je netrackované). Ohlas uživateli: výsledek testovací smyčky, exit kód instalátoru, a příkaz k publikaci větve, který **spustí uživatel**:

```bash
git log --oneline origin/ums-memory-bank..HEAD
echo "! UMS_ALLOW_SHARED_PUSH=1 git push origin ums-memory-bank"
```

`ums-memory-bank` je integrační báze tohoto forku a je v `protectedBranches`, takže agent ji nepushuje ani si nenastavuje `UMS_ALLOW_SHARED_PUSH`.

---

## Co tento plán záměrně nedělá

- **Neaktualizuje `architecture.md`, `brief.md` ani `tech.md`** nad rámec jedné cílené opravy cesty ledgeru (task 1) a zápisu změřeného výkonu (task 7). Current-state dokumenty vlastní `mb-harvest` na konci větve podle Harvest Contract; plán by je duplikoval.
- **Nepíše do `playbook.md`.** Procedurální znalost se během práce sbírá do `<MB_ROOT>/.superpowers/playbook-candidates/branch_model_integrace.md` a prochází harvestovou bránou ke schválení. Kandidáti se hodí zejména u tasků 4 a 7 (pasti POSIX `sh` a `git log --stdin`).
- **Nekontroluje `d:\_datasys\ums\memory-bank\playbook.md`** (Memory Bank produktu, nikoli vrstvy) — je to výslovný výstup návrhu, ale patří do harvestu, kde se derivují `AFFECTED_MBS`.
- **Nerevendoruje vendorované skilly.** Overlay bloky vznikají v monorepu; tato větev mění jen fragmenty.
