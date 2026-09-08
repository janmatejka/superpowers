# Orchestrace epiku — implementační plán

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Zavést epikovou integrační linii, sjednotit cestu integrace pro oba režimy do jedné procedury s jednou bránou a jedním artefaktem předání, a přidat evidenci a viditelnost, které z orchestrace epiku dělají kontrolovatelnou práci.

**Architecture:** Vrstva se mění na třech místech a v tomhle pořadí. (1) Pravidlo dostane domov v kontraktu, konfigurace nový klíč a `guard-git-push.mjs` jednu úzce podmíněnou výjimku podle aktéra. (2) Cesta integrace se sjednotí: `finishing` dostane bránu předání a artefakt předání se dvěma vykresleními, a správcova strana vznikne jako vlastní operace `mb-epic-run integrate`. (3) Evidence (registr rozhodnutí, ověřovací sada) a viditelnost (blok `NOW` se stavovou třídou a termínem) z toho udělají věci, které se dají zkontrolovat strojově místo pamětí agenta.

**Tech Stack:** POSIX `sh` (`pre-push`), Node ESM (`guard-git-push.mjs`), PowerShell 7 (sdílené skripty, `pool-*.ps1`, testové sady), Markdown (kontrakt, skilly, overlay fragmenty). Bez knihovních závislostí; testy jsou obyčejné `.ps1` s vlastními aserčními funkcemi.

**Spec:** [design_ums_3505_orchestrace_epiku.md](design_ums_3505_orchestrace_epiku.md)

## Global Constraints

- **Autorita je `ums/.claude/`**, ne kořenový `.claude/`. Kořenový `.claude/` je netrackovaná **nasazená** kopie; edituje se zdroj v `ums/`, pak se nasazení obnoví (`playbook.md`, „Obnova nasazené kopie v tomto repu"). Editace v kořenovém `.claude/` se ztratí.
- **Aditivnost fork větve:** na větvi `ums-memory-bank` se mimo `ums/`, `memory-bank/` a sekci v `CLAUDE.md` nemění nic.
- **Pravidlo má jeden domov:** nové pravidlo se píše NEJDŘÍV do `ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md`; skill smí říct jen „per `<jméno sekce>`" plus to, co je čistě lokální. Věta, která v skillu parafrázuje důvod, je budoucí rozchod.
- **Po každé změně pravidla v kontraktu** grepni celou vrstvu na jeho charakteristický token, včetně hlaviček hooků, šablon reportů a overlay fragmentů, a oprav každé restatement ve stejném commitu.
- **Odkazuj na sousední krok jménem fáze, ne pořadovým číslem.** Po vložení nebo odebrání kroku grepni celý soubor na `steps? [0-9]` (case-insensitive) i na číslovky slovem.
- **Testy:** žádný Pester. Obyčejný `.ps1` vedle testovaného kódu, v podadresáři `tests/`, jméno `<téma>.tests.ps1`, načtení helperu přes `. (Join-Path $PSScriptRoot '_assert.ps1')`. Do nového adresáře testů zkopíruj `_assert.ps1`. Testy běží offline; kde je potřeba remote, sestav lokální bare klon.
- **Nový test ověř jeho vlastní negativitou:** spusť ho i proti neopravenému kódu, nebo dočasně smaž řádek, který hlídá, a zkontroluj, které asercie zčervenají. Pak obnov soubor a potvrď prázdný `git diff`.
- **Nikdy nepiš do parametru Bash/PowerShell toolu literální text obsahující `--no-verify`, `MB_HUMAN_PUSH=1` nebo tvar `git push …`.** Takový text zapiš nástrojem Write do souboru a soubor spusť. Bezpečnostní hlídka blokuje literál v příkazové řádce, ne obsah spouštěného skriptu; na jednom work itemu tahle past padla šestkrát.
- **Jazyk:** kontrakt, skilly a jejich těla anglicky; MB dokumenty, commit messages a výstupy pro uživatele česky. Skripty vrstvy jsou vývojářské nástroje a mluví anglicky.
- **Publikace:** po každém commitu pushni tiketovou větev `UMS-3505-orchestrace-epiku` a ohlas větev i odchozí commity. Na chráněnou větev agent nepushuje nikdy.
- **Commit messages** končí řádky:
  `Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>`
  `Claude-Session: https://claude.ai/code/session_01WrUC7GqxzYNuzEyuC9EhJP`

## Ověřovací sada

Doslovný výčet příkazů, jeden na řádek. Co sada je a jak ji brána předání
porovnává s citací v artefaktu předání, popisuje kontrakt, sekce
„Integration" (Publication Contract).

```
for t in $(find ums -name "*.tests.ps1" | sort); do echo "== $t"; pwsh -NoProfile -File "$t" || echo "FAILED: $t"; done
```

---

## Jak se plán vykonává — tři fáze, každá v čistém kontextu

Plán má **tři fáze**. Každá je samostatně funkční a samostatně ověřitelná, a
**každá se spouští v novém sezení s čistým kontextem.** Fáze na sebe navazují
věcně, ne kontextem: sezení, které vykonává fázi 2, nesmí potřebovat nic
z konverzace, ve které vznikla fáze 1.

Proto má každá fáze dva rámující bloky:

- **Vstup fáze** — co musí platit, než se začne, co si sezení přečte, a co už
  existuje z předchozích fází. Tohle je celý brief; nic dalšího se
  nepředpokládá.
- **Výstup fáze** — co se ověří, co se commitne, a **doslovný prompt, kterým
  uživatel spustí další fázi.**

Fáze se nespojují do jednoho běhu ani tehdy, když se to zdá levné. Důvod je
naměřený: kontext, který přeteče uprostřed rozdělané fáze, stojí víc než
studený start s konstruovaným briefem.

---

# FÁZE 1 — Cesta integrace

**Co fáze dodává:** epiková linie je chráněná větev, do které smí agent
fast-forwardovat úzce podmíněným pushem; cesta integrace je jedna procedura
s jednou bránou a jedním artefaktem předání pro oba režimy; správcova strana
existuje jako operace `mb-epic-run integrate`.

**Po fázi 1 je model funkční end-to-end** — tiket se dá dokončit a integrovat
do epikové linie i do dodávkové linie, a rozdíl je jediné vykreslení předání.

## Vstup fáze 1

**Předpoklady, ověř je než začneš:**

- [x] Jsi na větvi `UMS-3505-orchestrace-epiku`. Ověř: `git branch --show-current`
- [x] Strom je čistý. Ověř: `git status --porcelain` (prázdný výstup)
- [x] `memory-bank/context.md` nese pin `ums_3505_orchestrace_epiku` a Jira `UMS-3505`
- [x] Publikační záruka platí v tomhle sezení. Ověř podle instrukce v hlavičce sezení (`SessionStart` hook); syntetický pipe na chráněnou větev musí skončit nenulově
- [x] Baseline testů vrstvy je zelená **před první změnou**. Spusť smyčku ze sekce „Testy vrstvy" v [playbook.md](../../playbook.md) a zapiš počty; červená sada existující před tvou prací se řeší nebo reportuje PŘEDEM, ne uprostřed tasku

**Co si přečti (v tomhle pořadí):**

1. [design_ums_3505_orchestrace_epiku.md](design_ums_3505_orchestrace_epiku.md) — celý; hlavně „Slovník", „Jedna procedura, dva příjemci", části 1 až 4
2. `ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md` — sekce „Repository Configuration", „Publication Contract" včetně podsekce „Integration", „Fail-Closed Behavior"
3. [playbook.md](../../playbook.md) — sekce „Testy vrstvy", „PowerShell v této vrstvě", „Git hooky (POSIX sh)", „Kontrakt a skilly: soudržnost pravidel a dokumentů"
4. [architecture.md](../../architecture.md) — sekce 3 (publikace a viditelnost) a 6 (pool)

**Co ještě neexistuje a v téhle fázi se nestaví:** registr rozhodnutí, deklarovaná ověřovací sada, stub sdíleného rozhraní, blok `NOW`, eskalační tabulka, tři úrovně autonomie. Brána předání v téhle fázi nese **tři univerzální kontroly**; dvě epikové přibudou ve fázi 2.

---

### Task 1: Kontrakt — epiková linie a klíč `epicBranchPattern`

Pravidlo má jeden domov a ten je tady. Žádný skill se v této fázi neupravuje dřív, než je pravidlo v kontraktu.

**Files:**
- Modify: `ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md`
- Modify: `ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md` — hlavička s verzí (bump na 2.14)

**Interfaces:**
- Produces: pojmy `epic line` / `epiková linie`, `epicBranchPattern`, `handoff gate`, `handoff artifact` — každý další task na ně odkazuje jménem sekce, ne číslem.

- [x] **Step 1: Přečti sekci Repository Configuration a najdi tabulku klíčů**

Spusť: `grep -n "| Key | Consumers |" -A 8 ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md`

Očekávané: tabulka se čtyřmi řádky (`baseRef`, `protectedBranches`, `ticketPattern`, `projectMarkers`/`sharedRoots`).

- [x] **Step 2: Přidej řádek klíče do tabulky**

Do tabulky klíčů přidej právě jeden řádek. Kontrakt vyžaduje, aby klíč bez jmenovaného konzumenta nevznikl — konzument je jediný:

| `epicBranchPattern` | `guard-git-push.mjs` (the actor-rule exception) |

- [x] **Step 3: Napiš podsekci o epikové linii**

Za odstavec o efektivní bázi přidej podsekci `### The epic line`. Musí obsahovat, každé jednou větou nebo dvěma:

- co epiková linie je (kódová integrační větev epiku, jméno tvaru `epic/<EPIC-KEY>`);
- že **patří mezi `protectedBranches`** a že tím platí invariant „an integration branch is always a protected branch" doslova;
- že `epicBranchPattern` **neřídí ochranu**, jen výjimku podle aktéra, a že chybějící nebo nečitelná hodnota znamená **žádnou výjimku**;
- **čtyři podmínky výjimky**: cíl odpovídá `epicBranchPattern`; cíl je chráněný; cíl NENÍ větev odvozená z `baseRef`; zdrojem refspecu je surové 40místné hex SHA;
- že první publikaci epikové linie hook zamítne (`remote_sha` je nula), takže větev **zakládá člověk**, a že hook u ní nabízí tvar s únikovou proměnnou, ne prostý integrační tvar;
- že vzniká **třetí kategorie** — „chráněná větev, do které agent smí pushovat" — a že se přesunula z otázky co smí být bází do otázky kdo smí pushovat co;
- že epiková linie **vzniká jen tam, kde tikety epiku nejsou samostatně dodatelné do dodávkové linie**, a po východu epiku se maže (lidský úkon, mazání přes push je zakázané).

- [x] **Step 4: Přepiš podsekci Integration na jednu proceduru**

V podsekci `### Integration` nahraď dnešní sedmikrokovou sekvenci sjednocenou procedurou podle části 2 návrhu. Musí být zřejmé, že:

- procedura je **jedna pro každou efektivní bázi** — dodávkovou linii, servisní větev i epikovou linii;
- před předáním běží **brána předání** se třemi kontrolami proti čerstvě staženému `<baseRef>`;
- **artefakt předání** je jeden (cílová větev, SHA, výčet odchozích commitů, doslovné ověřovací příkazy s výstupem) a má **dvě vykreslení**, o kterých rozhoduje jediná podmínka „existuje správce?";
- po landnutí pushe ověřuje dosažitelnost **z báze** a spouští `mb-jira-update` **tiketové sezení na vlastní větvi**, ať push provedl kdokoli.

- [x] **Step 5: Zapiš odchylku kanonického IDLE**

V sekci `## \`context.md\` Schema & Writers` uprav popis IDLE stavu: řádek `Jira:` se **nezachovává**; zachovává se jen `Báze:`. Napiš tam invariant slovy: post-harvest `context.md` všech tiketů integrujících do téže větve je bajt po bajtu stejný — to je to, co dělá merge bezkonfliktním. A poznámku, že plán musí ověřit, odkud `mb-jira-update` po harvestu bere klíč tiketu.

- [x] **Step 6: Bumpni verzi kontraktu a projdi konzumenty**

Zvyš verzi kontraktu na `2.14` všude, kde je uvedená.

Spusť a projdi každý zásah:

Příkaz: `grep -rn "2\.13" ums/ memory-bank/ CLAUDE.md`

Očekávané: každý výskyt je buď historická zmínka (nechat), nebo pin verze (aktualizovat). Rozhodnutí zapiš do commit message.

- [x] **Step 7: Grep na charakteristické tokeny nového pravidla**

Příkaz: `grep -rn "epicBranchPattern\|epic line\|epiková linie\|handoff gate" ums/ memory-bank/`

Očekávané: výskyty jen v kontraktu a v návrhu. Kdekoli jinde by to znamenalo restatement, který se rozejde.

- [x] **Step 8: Commit a push**

Příkaz: `git add ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md && git commit` s českou zprávou o zavedení epikové linie a klíče, a `git push origin UMS-3505-orchestrace-epiku`.

---

### Task 2: `Get-UmsRepoConfig` — klíč `epicBranchPattern`

**Files:**
- Modify: `ums/.claude/skills/shared/scripts/Get-UmsRepoConfig.ps1`
- Test: `ums/.claude/skills/shared/tests/repo-config.tests.ps1`

**Interfaces:**
- Consumes: pojem `epicBranchPattern` z Tasku 1
- Produces: `$cfg.EpicBranchPattern` — `[string]`, výchozí prázdný řetězec `''` (žádná epiková linie). Čtou ho tasky fáze 2 a 3.

- [x] **Step 1: Napiš padající testy**

Do `repo-config.tests.ps1` přidej čtyři asercie. Prázdná hodnota je výchozí, protože chybějící vzor musí znamenat „žádná výjimka", nikdy „všechno":

```powershell
# epicBranchPattern: nový klíč, výchozí je PRÁZDNO (žádná epiková linie).
$r = New-ConfigFixture '{ "epicBranchPattern": "epic/*" }'
Assert-Eq (Get-UmsRepoConfig $r).EpicBranchPattern 'epic/*' 'epicBranchPattern se načte z konfigurace'
Remove-Item -Recurse -Force $r

$r = New-ConfigFixture '{ "baseRef": "origin/develop" }'
Assert-Eq (Get-UmsRepoConfig $r).EpicBranchPattern '' 'chybějící epicBranchPattern degraduje na prázdno, ne na vzor'
Remove-Item -Recurse -Force $r

$r = New-ConfigFixture '{ "epicBranchPattern": "" }'
Assert-Eq (Get-UmsRepoConfig $r).EpicBranchPattern '' 'prázdná hodnota se chová jako chybějící'
Remove-Item -Recurse -Force $r

$r = New-ConfigFixture '{ "epicBranchPattern": 42 }'
Assert-Eq (Get-UmsRepoConfig $r).EpicBranchPattern '' 'nestringová hodnota degraduje na prázdno, nestringifikuje se'
Remove-Item -Recurse -Force $r
```

Pokud sada helper `New-ConfigFixture` nemá, zkopíruj jeho tvar z `ums/.claude/hooks/tests/guard-git-push.tests.ps1` a přizpůsob ho.

- [x] **Step 2: Spusť testy a ověř, že padají**

Příkaz: `pwsh -NoProfile -File ums/.claude/skills/shared/tests/repo-config.tests.ps1`

Očekávané: FAIL, hláška o chybějící vlastnosti `EpicBranchPattern`.

- [x] **Step 3: Přidej klíč do loaderu**

V `Get-UmsRepoConfig.ps1` přidej do výchozího `$cfg` položku `EpicBranchPattern = ''` a hned za blok pro `ticketPattern` přidej stejně tvarovanou podmínku. Tvar je záměrně stejný jako u `ticketPattern` (jeden řetězec), ne jako u seznamových klíčů:

```powershell
    if ($propNames -contains 'epicBranchPattern' -and $json.epicBranchPattern -is [string] -and $json.epicBranchPattern.Trim() -ne '') {
        $cfg.EpicBranchPattern = [string]$json.epicBranchPattern
    }
```

Test `-is [string]` je load-bearing: bez něj by `42` prošlo stringifikací na vzor `"42"`, což je táž třída chyby, jakou komentáře v tomhle souboru už jednou popisují u seznamových klíčů.

- [x] **Step 4: Spusť testy a ověř, že prochází**

Příkaz: `pwsh -NoProfile -File ums/.claude/skills/shared/tests/repo-config.tests.ps1`

Očekávané: PASS, řádek `<N> passed`, exit 0.

- [x] **Step 5: Ověř negativitu testu**

Dočasně smaž podmínku `-is [string]` z kroku 3, spusť sadu znovu a zkontroluj, že zčervená právě asercie o nestringové hodnotě. Pak soubor obnov a potvrď prázdný `git diff` na něm.

- [x] **Step 6: Commit a push**

---

### Task 3: `guard-git-push.mjs` — oprava case-insensitivity `stripRef`

Samostatná oprava existující vady, nalezená oponenturou a změřená. Dělá se **před** výjimkou, protože výjimka na `stripRef` staví.

**Files:**
- Modify: `ums/.claude/hooks/guard-git-push.mjs:175`
- Modify: `ums/.claude/hooks/pre-push` — nepravdivý komentář o shodě vrstev
- Test: `ums/.claude/hooks/tests/guard-git-push.tests.ps1`

**Interfaces:**
- Produces: `stripRef` shodně case-insensitivní s hookem. Task 4 na tom staví.

- [x] **Step 1: Napiš padající test**

```powershell
# Hook lower-casuje celý ref, guard musí odpovědět stejně — jinak vrstvy
# nesouhlasí o členství, což je právě to, co pre-push ve svém komentáři
# zakazuje. Změřeno oponenturou: refs/HEADS/develop guardem projde.
$cfgCase = New-ConfigFixture '{ "protectedBranches": ["develop"] }'
Assert-Match (Test-Cmd 'git push origin UMS-1:refs/HEADS/develop' $cfgCase) 'permissionDecision.*deny' 'zamítnuto: refs/HEADS/ se strippuje case-insensitive stejně jako v hooku'
Assert-Match (Test-Cmd 'git push origin UMS-1:Refs/Heads/develop' $cfgCase) 'permissionDecision.*deny' 'zamítnuto: smíšená velikost písmen v prefixu refs/heads/'
Remove-Item -Recurse -Force $cfgCase
```

- [x] **Step 2: Spusť sadu a ověř, že nové asercie padají**

Příkaz: `pwsh -NoProfile -File ums/.claude/hooks/tests/guard-git-push.tests.ps1`

Očekávané: FAIL na obou nových aserciích — guard je pustí.

- [x] **Step 3: Oprav `stripRef`**

```javascript
const stripRef = (ref) => String(ref).replace(/^refs\/heads\//i, '');
```

- [x] **Step 4: Spusť sadu a ověř, že prochází**

Očekávané: PASS, `<N> passed`, exit 0.

- [x] **Step 5: Oprav nepravdivý komentář v `pre-push`**

V `ums/.claude/hooks/pre-push` najdi větu tvrdící, že `guard-git-push.mjs` je v porovnání jmen taky case-insensitive. Ta věta byla nepravdivá do tohoto tasku. Přepiš ji tak, aby tvrdila, co teď platí, a **jmenovitě zmiň, že to bylo změřeno a opraveno** — jinak příští čtenář neví, jestli je to zase jen tvrzení.

Příkaz na dohledání: `grep -n "case-insensitive" ums/.claude/hooks/pre-push`

- [x] **Step 6: Commit a push**

---

### Task 4: `guard-git-push.mjs` — výjimka pro epikovou linii

**Files:**
- Modify: `ums/.claude/hooks/guard-git-push.mjs` — `loadProtected` okolí (nová `loadEpicRule`), `evaluatePush` (zachování zdroje refspecu, podmínka výjimky)
- Test: `ums/.claude/hooks/tests/guard-git-push.tests.ps1`

**Interfaces:**
- Consumes: `epicBranchPattern` z `ums-repo.json` (Task 1 ho zavedl v kontraktu; guard si ho čte sám, ne přes PowerShell loader)
- Produces: chování, na které se odkazuje `finishing` overlay a `mb-epic-run integrate`

- [x] **Step 1: Napiš padající testy — pozitivní i všechny čtyři negativní**

Negativní půlka je tu důležitější než pozitivní: výjimka, která je širší, než se myslí, je přesně ta vada, kvůli které tenhle návrh vznikl.

```powershell
# ---------------------------------------------------------------------------
# Epiková výjimka podle aktéra. Čtyři podmínky, každá s vlastním negativem.
# ---------------------------------------------------------------------------
$SHA = '0123456789abcdef0123456789abcdef01234567'
$cfgEpic = New-ConfigFixture '{ "baseRef": "origin/develop", "protectedBranches": ["develop", "epic/*"], "epicBranchPattern": "epic/*" }'

# POZITIVNÍ: přesně tvar protokolu.
Assert-NotMatch (Test-Cmd "git push origin ${SHA}:refs/heads/epic/UMS-3400" $cfgEpic) 'permissionDecision.*deny' 'povoleno: refspec se surovým SHA do epic/* projde výjimkou'

# NEGATIVNÍ 1 — zdroj není surové SHA. Tohle zavírá past se zděděným
# upstreamem: switch -c z origin/epic/<KLÍČ> nastaví upstream na epikovou
# linii, takže holý push by jinak prošel.
Assert-Match (Test-Cmd 'git push origin HEAD:refs/heads/epic/UMS-3400' $cfgEpic) 'permissionDecision.*deny' 'zamítnuto: HEAD jako zdroj není surové SHA'
Assert-Match (Test-Cmd 'git push origin UMS-3400-x:refs/heads/epic/UMS-3400' $cfgEpic) 'permissionDecision.*deny' 'zamítnuto: jméno větve jako zdroj není surové SHA'
Assert-Match (Test-Cmd 'git push origin epic/UMS-3400' $cfgEpic) 'permissionDecision.*deny' 'zamítnuto: refspec bez zdroje výjimku neotevírá'

# NEGATIVNÍ 2 — cíl neodpovídá epikovému vzoru.
Assert-Match (Test-Cmd "git push origin ${SHA}:refs/heads/develop" $cfgEpic) 'permissionDecision.*deny' 'zamítnuto: surové SHA do develop výjimku nedostane'

# NEGATIVNÍ 3 — cíl je větev odvozená z baseRef. Zavírá epicBranchPattern
# nastavený tak široce, že by pohltil bázi.
$cfgWide = New-ConfigFixture '{ "baseRef": "origin/develop", "protectedBranches": ["develop"], "epicBranchPattern": "*" }'
Assert-Match (Test-Cmd "git push origin ${SHA}:refs/heads/develop" $cfgWide) 'permissionDecision.*deny' 'zamítnuto: vzor pohlcující bázi výjimku neotevírá'
Remove-Item -Recurse -Force $cfgWide

# NEGATIVNÍ 4 — cíl odpovídá vzoru, ale NENÍ chráněný. Výjimka se vztahuje
# jen na chráněné větve; jinak by konfigurace udělovala právo na jmenný
# prostor, který nikdo nehlídá.
$cfgUnprot = New-ConfigFixture '{ "baseRef": "origin/develop", "protectedBranches": ["develop"], "epicBranchPattern": "epic/*" }'
Assert-NotMatch (Test-Cmd "git push origin ${SHA}:refs/heads/epic/UMS-3400" $cfgUnprot) 'permissionDecision.*deny' 'povoleno: nechráněná větev nebyla zamítnutá ani předtím — výjimka tu nic nemění'
Remove-Item -Recurse -Force $cfgUnprot

# BEZ KLÍČE: výjimka neexistuje vůbec.
$cfgNoKey = New-ConfigFixture '{ "protectedBranches": ["develop", "epic/*"] }'
Assert-Match (Test-Cmd "git push origin ${SHA}:refs/heads/epic/UMS-3400" $cfgNoKey) 'permissionDecision.*deny' 'zamítnuto: chybějící epicBranchPattern znamená žádnou výjimku'
Remove-Item -Recurse -Force $cfgNoKey

# TÝŽ TVAR V POWERSHELLOVÉM ZÁPISU — guard je registrovaný na Bash|PowerShell.
Assert-NotMatch (Test-CmdPs "git push origin ${SHA}:refs/heads/epic/UMS-3400" $cfgEpic) 'permissionDecision.*deny' 'povoleno: výjimka platí i na PowerShell toolu'

Remove-Item -Recurse -Force $cfgEpic
```

- [x] **Step 2: Spusť sadu a ověř, že padá pozitivní asercie**

Očekávané: FAIL na pozitivní aserci (guard dnes zamítá vše) a PASS na negativních — což je správně, protože negativní půlka popisuje stav, který má zůstat.

- [x] **Step 3: Zaveď čtení epikového pravidla**

Vedle `loadProtected` přidej funkci, která ze stejného souboru přečte `epicBranchPattern` a `baseRef`. Degradace vždy k větší ochraně — nečitelná hodnota znamená žádnou výjimku:

```javascript
// The exception is NARROW on purpose: it is the only place in this layer
// where the actor rule stops being categorical. A missing, empty or
// non-string value yields no exception at all, which is the same
// safer-side degradation loadProtected follows.
const loadEpicRule = (cwd) => {
  try {
    const raw = readFileSync(join(cwd || process.cwd(), 'memory-bank', 'ums-repo.json'), 'utf8');
    const parsed = JSON.parse(raw);
    if (!parsed || typeof parsed !== 'object') return null;
    const pat = parsed.epicBranchPattern;
    if (typeof pat !== 'string' || pat.trim() === '') return null;
    const baseRef = typeof parsed.baseRef === 'string' ? parsed.baseRef : '';
    // <baseBranch> = baseRef minus the remote and the SINGLE following slash.
    const baseBranch = baseRef.replace(/^[^/]+\//, '');
    return { re: globToRe(pat), baseBranch };
  } catch { return null; }
};

const RAW_SHA_RE = /^[0-9a-fA-F]{40}$/;
```

- [x] **Step 4: Zachovej zdroj refspecu, ne jen cíl**

V `evaluatePush` dnes řádek `targets.push(bare.includes(':') ? bare.split(':').pop() : bare)` **zdroj zahazuje**. Bez zdroje nejde vyhodnotit podmínka o surovém SHA. Uprav sběr tak, aby vedle cíle nesl i zdroj (nebo `null`, když refspec zdroj nemá), a nechej `targets` dál obsahovat cíle, aby se zbytek funkce nemusel měnit.

- [x] **Step 5: Zaveď výjimku na místě, kde se zamítá**

V místě, kde `evaluatePush` hledá `hit` mezi cíli, přeskoč cíl, který splňuje **všechny čtyři** podmínky. Napiš to jako jednu funkci s vlastním komentářem, ne jako podmínku v řádku:

```javascript
// FOUR conditions, and every one of them closes a measured or reasoned
// hole. Dropping any of them widens the exception past what the contract
// grants: the pattern alone would let a configured `feature/*` grant
// push rights over a namespace nobody protects; without the protected
// test the exception would apply where there was nothing to except;
// without the base test an `epicBranchPattern` of `*` would swallow the
// integration branch; and without the raw-SHA test a bare `git push`
// on a branch whose upstream `switch -c` set to the epic line would pass.
const isEpicFastForward = (dest, src, patterns, epic) =>
  epic !== null &&
  src !== null && RAW_SHA_RE.test(src) &&
  epic.re.test(stripRef(dest)) &&
  isProtected(dest, patterns) &&
  stripRef(dest).toLowerCase() !== epic.baseBranch.toLowerCase();
```

Předej `epic` do `evaluatePush` stejnou cestou jako `patterns` (spočítej ho v hlavním vstupním bodě vedle `loadProtected`).

- [x] **Step 6: Spusť sadu a ověř, že prochází celá**

Příkaz: `pwsh -NoProfile -File ums/.claude/hooks/tests/guard-git-push.tests.ps1`

Očekávané: PASS, `<N> passed`, exit 0. Zkontroluj, že `<N>` vzrostlo přesně o počet nových asercií — žádná stará nesmí zmizet.

- [x] **Step 7: Ověř negativitu — čtyřikrát**

Postupně odeber z `isEpicFastForward` vždy **jednu** ze čtyř podmínek, spusť sadu a zapiš, které asercie zčervenaly. Každé odebrání musí zčervenat právě svou negativní aserci. Podmínka, jejíž odebrání nezčervená nic, nic nehlídá a patří do reportu jako nález. Po každém kole soubor obnov.

- [x] **Step 8: Ověř, že hook pustí přesně tentýž tvar**

Napiš sondu **nástrojem Write do souboru** (ne jako literál v příkazu — hlídka blokuje literální `git push` v příkazové řádce) do `$CLAUDE_JOB_DIR/tmp/epic-probe.sh`. Sonda postaví dočasný repozitář s bare „origin", publikovanou epikovou linií a tiketovou větví, zapíše `epic/*` do `<git-common-dir>/ums-protected-branches` a napipuje do nainstalovaného hooku syntetickou čtveřici refů s `MB_AGENT_SESSION=1`.

Očekávané: hook vypíše hlášku o povoleném fast-forwardu a skončí kódem 0 pro publikovaný tip, a nenulově pro nepublikovaný a pro nulový `remote_sha` (první publikace).

Tenhle krok je důkaz, že obě vrstvy dávají na týž push shodnou odpověď. Bez něj je Task 4 jen tvrzení.

- [x] **Step 9: Commit a push**

---

### Task 5: `mb-harvest` — kanonický IDLE

**Files:**
- Modify: `ums/.claude/skills/mb-harvest/SKILL.md` — krok „Reset context.md (conditional)"

**Interfaces:**
- Consumes: odchylku IDLE z Tasku 1
- Produces: post-harvest tvar `context.md`, na kterém stojí bezkonfliktní merge; čte ho Task 6 (kontrola IDLE) i fáze 2

Tenhle task nemá strojový test — `mb-harvest` je instrukční Markdown. Ověření je proto dokumentované a studené.

- [x] **Step 1: Najdi krok resetu**

Příkaz: `grep -n "Reset context.md" -A 12 ums/.claude/skills/mb-harvest/SKILL.md`

- [x] **Step 2: Přepiš instrukci resetu**

Instrukce musí říct právě tohle a nic navíc: `## Active Work` → `(No active work - IDLE phase)`; **řádek `Jira:` se NEZACHOVÁVÁ**; řádek `Báze:` se zachovává. A jednu větu proč, s odkazem na sekci kontraktu, ne s vlastním zdůvodněním — parafráze důvodu ve skillu je budoucí rozchod.

- [x] **Step 3: Dohledej, odkud `mb-jira-update` bere klíč tiketu**

Příkaz: `grep -n "Jira:" ums/.claude/skills/mb-jira-update/SKILL.md`

Pokud klíč čte z `context.md`, je to **blokující nález**: reset by mu ho vzal. Řešení zapiš jako ruling a proveď ho v tomhle tasku — klíč se bere z hlavičky návrhu v `proposals/active/`, kde je vždy.

- [x] **Step 4: Studený test tvaru**

Vezmi `memory-bank/context.md` z tohohle repa, zapiš si jeho aktuální obsah, ručně na něm proveď reset podle nové instrukce a porovnej výsledek s tvarem, který instrukce popisuje. Pak obnov původní obsah a potvrď prázdný `git diff` na tom souboru.

Tenhle krok je náhrada za test: instrukce, kterou nejde jednou provést podle písmene, je vada.

- [x] **Step 5: Commit a push**

---

### Task 6: Brána předání — sdílený skript

**Files:**
- Create: `ums/.claude/skills/shared/scripts/Test-UmsHandoffGate.ps1`
- Create: `ums/.claude/skills/shared/tests/handoff-gate.tests.ps1`
- Create: `ums/.claude/skills/shared/tests/new-gate-fixture.ps1`

**Interfaces:**
- Consumes: `Get-UmsRepoConfig` (pro `CTX_DIR` a `baseRef`), kanonický IDLE z Tasku 5
- Produces: `Test-UmsHandoffGate -RepoRoot <cesta> -Sha <sha> -BaseRef <ref>` → objekt s poli `Ok` (`[bool]`), `Checks` (pole objektů `Name`/`Passed`/`Detail`) a `Blocking` (pole jmen neúspěšných kontrol). Volají ho Task 7 (`finishing`) a Task 8 (`mb-epic-run integrate`); fáze 2 do něj přidá porovnání ověřovací sady.

- [x] **Step 1: Napiš fixturu**

`new-gate-fixture.ps1` postaví dočasný repozitář: bare „origin", pracovní klon, bázi s IDLE `context.md`, tiketovou větev s commitem, a vrátí cesty a SHA. Musí umět vyrobit i variantu s **ACTIVE** `context.md` a variantu s **nepublikovaným** commitem — bez nich nejdou napsat negativní asercie.

- [x] **Step 2: Napiš padající testy**

```powershell
. (Join-Path $PSScriptRoot '_assert.ps1')
. (Join-Path $PSScriptRoot 'new-gate-fixture.ps1')
. (Join-Path $PSScriptRoot '..' 'scripts' 'Test-UmsHandoffGate.ps1')

$f = New-GateFixture
$r = Test-UmsHandoffGate -RepoRoot $f.Clone -Sha $f.MergedSha -BaseRef $f.BaseRef
Assert-True $r.Ok 'brána projde pro publikovaný, IDLE, potomkovský commit'

# NEGATIVNÍ: báze se pohnula po zapamatování tipu. Tohle je ta kontrola,
# kvůli které brána vůbec existuje — 244 kvůli tomu dvakrát přepisovala
# výčet odchozích commitů.
Move-GateBase $f
$r = Test-UmsHandoffGate -RepoRoot $f.Clone -Sha $f.MergedSha -BaseRef $f.BaseRef
Assert-True (-not $r.Ok) 'brána zamítne, když se báze pohnula'
Assert-Match ($r.Blocking -join ',') 'ancestor' 'blokující kontrola je jmenovaná'

# NEGATIVNÍ: ACTIVE pin. Měřený únik u 242, zachycený jen pozorností.
$r = Test-UmsHandoffGate -RepoRoot $f.Clone -Sha $f.ActiveSha -BaseRef $f.BaseRef
Assert-True (-not $r.Ok) 'brána zamítne commit s ACTIVE pinem'

# NEGATIVNÍ: nepublikovaný commit.
$r = Test-UmsHandoffGate -RepoRoot $f.Clone -Sha $f.UnpushedSha -BaseRef $f.BaseRef
Assert-True (-not $r.Ok) 'brána zamítne nepublikovaný commit'

# NEGATIVNÍ, A JE TO TA NEJDŮLEŽITĚJŠÍ: chybějící context.md je STOP,
# ne IDLE. git show na neexistující cestu končí kódem 128 a ten se snadno
# přečte jako "není ACTIVE".
$r = Test-UmsHandoffGate -RepoRoot $f.Clone -Sha $f.NoContextSha -BaseRef $f.BaseRef
Assert-True (-not $r.Ok) 'chybějící context.md je STOP, ne IDLE'

Remove-GateFixture $f
Complete-Tests
```

- [x] **Step 3: Spusť testy a ověř, že padají**

Příkaz: `pwsh -NoProfile -File ums/.claude/skills/shared/tests/handoff-gate.tests.ps1`

Očekávané: FAIL — skript neexistuje.

- [x] **Step 4: Napiš skript**

Tři kontroly, v tomhle pořadí, a **vždy nejdřív `git fetch origin`**:

1. `git merge-base --is-ancestor <čerstvá báze> <Sha>` — nenulový exit je blokující nález `ancestor`;
2. `git show <Sha>:<CTX_DIR>/context.md` — ACTIVE je přítomnost `Target MB Pin` **spolu s** `Work item`; exit 128 (cesta neexistuje) je blokující nález `context-missing`, **nikdy** „IDLE". `<CTX_DIR>` se odvozuje z konfigurace, ne z natvrdo zapsané cesty;
3. `git branch -r --contains <Sha>` — prázdný výsledek je blokující nález `unpublished`.

Skript nikdy nic nemění a nikdy nepushuje. Reportuje česky jen tehdy, když ho volá skill; sám vrací objekt.

- [x] **Step 5: Spusť testy a ověř, že prochází**

Očekávané: PASS, `<N> passed`, exit 0.

- [x] **Step 6: Ověř negativitu**

Postupně vyřaď každou ze tří kontrol a zkontroluj, že zčervená právě její asercie. Obnov soubor.

- [x] **Step 7: Ověř proti skutečnému repozitáři**

Spusť bránu proti tomuhle repu s SHA aktuálního `HEAD` a bází `origin/ums-memory-bank`. Read-only, takže je to bezpečné. Fixtura dokazuje, že kód dělá, co jsi do fixtury napsal; skutečné repo dokazuje, že to funguje na reálném tvaru.

- [x] **Step 8: Commit a push**

---

### Task 7: `finishing` overlay — brána a artefakt předání

**Files:**
- Modify: `ums/.claude/skills/shared/overlays/finishing-a-development-branch.overlay.md`

**Interfaces:**
- Consumes: `Test-UmsHandoffGate.ps1` (Task 6), kanonický IDLE (Task 5), pojmy z kontraktu (Task 1)
- Produces: artefakt předání ve tvaru, který spotřebovává `mb-epic-run integrate` (Task 8)

- [x] **Step 1: Přečti současnou sekvenci**

Příkaz: `grep -n "Do NOT execute the upstream Option 1" -A 45 ums/.claude/skills/shared/overlays/finishing-a-development-branch.overlay.md`

- [x] **Step 2: Vlož bránu předání jako nový krok**

Mezi zelené ověření a předání vlož krok volající `Test-UmsHandoffGate.ps1`. Blokující nález je STOP s českou hláškou jmenující kontrolu; u nálezu `ancestor` je náprava návrat k mergi báze, ne opakování pushe.

- [x] **Step 3: Přepiš krok předání na artefakt se dvěma vykresleními**

Krok, který dnes rovnou nabízí příkaz člověku, přepiš tak, aby nejdřív sestavil **artefakt předání** (cílová větev, SHA, výčet odchozích commitů, doslovné ověřovací příkazy s výstupem) a teprve pak ho vykreslil podle jediné podmínky:

- efektivní báze **neodpovídá** `epicBranchPattern` → česká otázka a příkaz s `!` pro uživatele, jako dnes;
- efektivní báze **odpovídá** → zpráva správci epiku; sezení nekončí turn čekáním na push, ale na odpověď správce.

**Negace starých příkazů je povinná**, ne volitelná: fragment nahrazuje upstream krok, takže musí jmenovitě říct, co se NEDĚLÁ — jinak zůstane starý text vedle nového vypadat platně.

- [x] **Step 4: Ověř, že fragment má kotvu a projde vendoringem**

Příkaz: `grep -n "ANCHOR-BEFORE\|ASSERT:" ums/.claude/skills/shared/overlays/finishing-a-development-branch.overlay.md`

Očekávané: kotvy a `ASSERT` direktivy odpovídají větám, které v upstream souboru pořád jsou. Anchor-miss je detektor driftu upstreamu, ne chyba k obejití.

- [x] **Step 5: Grep na čísla kroků**

Příkaz: `grep -nEi "steps? [0-9]|krok(u|y|ů)? [0-9]" ums/.claude/skills/shared/overlays/finishing-a-development-branch.overlay.md`

Očekávané: žádný odkaz nemíří na krok, který se vložením posunul. Kde odkaz je, přepiš ho na jméno fáze.

- [x] **Step 6: Studený průchod tabulkou**

Projdi fragment jako chladný čtenář **dvakrát**, jednou pro každý režim, s proměnnou „odpovídá báze epikovému vzoru?" jako sloupcem. Obě čtení musí dát úplnou a neprotiřečící si sekvenci. Tohle je jediný test, který tenhle task má.

- [x] **Step 7: Commit a push**

---

### Task 8: `mb-epic-run integrate` — správcova strana

**Files:**
- Modify: `ums/.claude/skills/mb-epic-run/SKILL.md` — nová sekce `### \`integrate <TIKET>\``, aktualizace `## Operations` a `## Quick reference`, rozšíření `allowed-tools`
- Test: `ums/.claude/skills/mb-epic-run/tests/pool-status.tests.ps1` (asercie o `allowed-tools`) nebo nová sada podle toho, kde už asercie o frontmatteru jsou

**Interfaces:**
- Consumes: artefakt předání (Task 7), `Test-UmsHandoffGate.ps1` (Task 6)
- Produces: operace `integrate`; fáze 2 do ní přidá dvě epikové kontroly

- [x] **Step 1: Vypiš inventář nástrojů, které operace používá**

Než přebereš jakýkoli navržený seznam, vypiš **všechny** nástroje, které `integrate` vlastními kroky potřebuje: `git fetch`, čtení předání, spuštění brány (`pwsh`), `git push` s refspecem, `Edit` pro zápis do ledgeru, `git add`/`git commit`/`git push` na elaborační větvi. Pole `allowed-tools` **restringuje**, ne jen předschvaluje — seznam zúžený na postoj skillu vůči cizím workspace by centrální operaci znemožnil.

- [x] **Step 2: Napiš padající test na `allowed-tools`**

```powershell
$fm = Get-Content -Raw (Join-Path $PSScriptRoot '..' 'SKILL.md')
Assert-Match $fm 'allowed-tools:.*git push' 'allowed-tools kryje git push — integrate pushuje refspecem'
Assert-Match $fm 'allowed-tools:.*Edit' 'allowed-tools kryje Edit — integrate zapisuje do ledgeru'
```

- [x] **Step 3: Spusť sadu a ověř stav**

Příkaz: `pwsh -NoProfile -File ums/.claude/skills/mb-epic-run/tests/pool-status.tests.ps1`

Očekávané: `git push` i `Edit` v poli už jsou (viz frontmatter), takže asercie projdou hned — jsou to **regresní zámky**, ne důkaz opravy, a tak je i označ v reportu.

- [x] **Step 4: Napiš sekci operace**

Sekce `### \`integrate <TIKET>\`` popisuje šest kroků podle části 2 návrhu, podsekce „Operace správce": `fetch` a přečtení předání; dvě epikové kontroly (**v téhle fázi zapsané jako „přibývají ve fázi 2", ne implementované**); úsudková kontrola proti evidenci epiku; přeběhnutí tří univerzálních kontrol brány proti čerstvě staženému tipu; fast-forward refspecem; zápis do ledgeru a pobídka k resynchronizaci.

Uveď **předpoklad, který se dá přehlédnout**: hook posuzuje dosažitelnost z remote-tracking refů tohoto klonu, takže správce musí mít po pushi tiketového agenta fetchnuto.

- [x] **Step 5: Přidej operaci do železných pravidel**

`integrate` **nikdy** nesahá do pracovního stromu slotu a **nikdy** nemerguje. Jediný zápis mimo vlastní repozitář je fast-forward refspecem. Zapiš to mezi železná pravidla skillu, ne jen do popisu operace.

- [x] **Step 6: Spusť celou sadu skillu**

Příkaz: `for t in ums/.claude/skills/mb-epic-run/tests/*.tests.ps1; do pwsh -NoProfile -File "$t"; done`

Očekávané: všechny zelené.

- [x] **Step 7: Commit a push**

- [x] **Konec tasku.** `task-brief` končí až u dalšího nadpisu `Task`, takže
  brief tohohle tasku nese navíc i uzávěrku fáze a vstupní brief fáze další.
  **Nic z toho tenhle task nevykonává** — uzávěrku dělá řídicí sezení, ne
  implementátor tasku.

---

## Výstup fáze 1

- [x] **Ověření celé vrstvy.** Spusť smyčku ze sekce „Testy vrstvy" v playbooku. Porovnej počty s baseline zapsanou ve vstupu fáze. Každý rozdíl vysvětli.
- [x] **Nasazení obnov**, ať sezení pracuje s tím, co je ve zdroji: postup je v [playbook.md](../../playbook.md), sekce „Obnova nasazené kopie v tomto repu".
- [x] **Report** česky: co je hotové, které asercie jsou regresní zámky a ne důkaz opravy, jaké rulingy jsi udělal, a co zůstalo otevřené.
- [x] **Zaškrtej hotové kroky** v tomhle souboru, commitni a pushni.

**Prompt pro spuštění fáze 2 v čistém kontextu** — předej ho uživateli k vložení:

> Pokračuj plánem UMS-3505, **fází 2 (Evidence epiku)**. Jsi v repu
> `c:\Users\matejka\source\repos\superpowers` na větvi
> `UMS-3505-orchestrace-epiku`. Plán je
> `memory-bank/proposals/active/plan_ums_3505_orchestrace_epiku.md`, návrh
> `memory-bank/proposals/active/design_ums_3505_orchestrace_epiku.md`.
> Přečti si vstupní brief fáze 2 v plánu a řiď se jím; fáze 1 je hotová a
> zaškrtaná. Použij skill subagent-driven-development.

---

# FÁZE 2 — Evidence epiku

**Co fáze dodává:** rozhodnutí, která stojí na chování jiného tiketu, přestávají být pamětí agenta a stávají se řádkem s potvrzením, který mechanicky blokuje fast-forward. „Ověřeno" se stává porovnatelným tvrzením. A tiketové sezení přestává dostávat nabídku elaborace epiku.

## Vstup fáze 2

**Předpoklady:**

- [x] Fáze 1 je hotová a zaškrtaná v tomhle souboru; poslední commit fáze 1 je na `origin`
- [x] Jsi na `UMS-3505-orchestrace-epiku`, strom čistý, baseline testů zelená
- [x] Existuje `Test-UmsHandoffGate.ps1` se třemi kontrolami a operace `mb-epic-run integrate`

**Co si přečti:** návrh, části 2 (podsekce o ověřovací sadě) a 5 celá; kontrakt, sekce „Epic Backflow (design → epic)"; `ums/.claude/skills/mb-epic-elaboration/ledger-template.md` a `scripts/ledger-status.ps1`.

**Klíčová hranice téhle fáze:** registr rozhodnutí, ověřovací sada a stub sdíleného rozhraní se váží na **epik**, ne na epikovou **linii**. Tiket, který patří do epiku a integruje se přímo do dodávkové linie, je má taky.

---

### Task 9: Ledger — sekce registru rozhodnutí a ověřovací sady

**Files:**
- Modify: `ums/.claude/skills/mb-epic-elaboration/ledger-template.md`

**Interfaces:**
- Produces: dvě nové sekce s pozičními sloupci, které parsuje Task 10

- [x] **Step 1: Přidej sekci `## Ověřovací sada`**

Doslovný výčet příkazů, jeden na řádek, deklarovaný jednou pro celý epik. Do textu sekce zapiš, že **chybějící sada je fail-closed STOP u první integrace** a proč: bez ní znamená „zelené" pokaždé něco jiného.

- [x] **Step 2: Přidej sekci `## Registr rozhodnutí`**

Sloupce, pozičně, **neměnit ani nepřehazovat** (stejná poznámka jako u `Rozjetí`):

| Rozhodnutí | Vlastník (tiket) | Předpokládá o (tiket) | Druh | Stav | Potvrzeno (SHA) |

`Druh` je `text` nebo `chování`. U druhu `chování` se řádek nezavírá přečtením, ale **testem, který to chování tvrdí**.

Do textu sekce dej měřený příklad, protože abstraktní popis by se špatně poznával: rozhodnutí 244 „po výpadku se neobsluhuje z prošlých dat, léčbou je delší okno", vlastník 244, předpokládá o 243, druh `chování` — a TTL toho okna bylo v kódu 243 natvrdo 60 s bez konfiguračního klíče.

- [x] **Step 3: Commit a push**

---

### Task 10: `ledger-status.ps1` — parsování registru a sady

**Files:**
- Modify: `ums/.claude/skills/mb-epic-elaboration/scripts/ledger-status.ps1`
- Test: `ums/.claude/skills/mb-epic-elaboration/tests/` — sada podle existující konvence adresáře

**Interfaces:**
- Consumes: tvar sekcí z Tasku 9
- Produces: `VerificationSet` (pole řetězců) a `DecisionRegistry` (pole objektů s poli `Decision`, `Owner`, `AssumesAbout`, `Kind`, `State`, `AckSha`). Čte je Task 11 a Task 12.

- [x] **Step 1: Napiš padající testy nad fixturou ledgeru**

Asercie, které musí existovat: sada se načte jako pole příkazů v pořadí; chybějící sekce dá prázdné pole (ne chybu); řádek registru bez `Potvrzeno (SHA)` se objeví s prázdným `AckSha`; **řádek šablony s hranatými placeholdery se do výsledku nepočítá** — jinak by šablona sama blokovala každou integraci.

- [x] **Step 2: Spusť a ověř, že padají**

- [x] **Step 3: Implementuj parsování**

Pozičně, stejnou technikou, jakou skript už používá pro `Rozjetí` a `Dirty-set`.

- [x] **Step 4: Spusť a ověř, že prochází**

- [x] **Step 5: Ověř negativitu** — smaž filtr placeholderových řádků a zkontroluj, že zčervená právě jeho asercie. Obnov.

- [x] **Step 6: Ověř proti skutečnému ledgeru**, pokud v repu nějaký je; jinak zapiš do reportu, že tenhle krok nešel provést a proč.

- [x] **Step 7: Commit a push**

---

### Task 11: Dvě epikové kontroly v `mb-epic-run integrate`

**Files:**
- Modify: `ums/.claude/skills/mb-epic-run/SKILL.md` — sekce `integrate`
- Create: `ums/.claude/skills/mb-epic-run/scripts/epic-gate.ps1`
- Test: `ums/.claude/skills/mb-epic-run/tests/epic-gate.tests.ps1`

**Interfaces:**
- Consumes: `DecisionRegistry` a řádky `Rozjetí` (Task 10)
- Produces: `Test-UmsEpicGate -LedgerPath <cesta> -Ticket <TIKET> -Epic <EPIK>` → objekt s `Ok` a `Blocking` ve stejném tvaru, jaký vrací `Test-UmsHandoffGate`, aby je skill mohl reportovat společně

- [x] **Step 1: Napiš padající testy**

Čtyři asercie: řádek `Rozjetí` tiketu patřící **jinému** epiku je blokující nález; nepotvrzený řádek registru jmenující tenhle tiket je blokující nález; potvrzený řádek projde; **ledger bez registru projde triviálně** — bez ledgeru ta kontrola nemá vstup a nesmí zastavovat.

- [x] **Step 2: Spusť a ověř, že padají**

- [x] **Step 3: Implementuj skript**

- [x] **Step 4: Spusť a ověř, že prochází**

- [x] **Step 5: Ověř negativitu obou kontrol zvlášť**

- [x] **Step 6: Zapoj kontroly do sekce `integrate`**

Nahraď poznámku „přibývají ve fázi 2" z Tasku 8 skutečným voláním. Grepni sekci na tu poznámku, ať nezůstane.

Příkaz: `grep -n "fázi 2\|phase 2" ums/.claude/skills/mb-epic-run/SKILL.md`

- [x] **Step 7: Commit a push**

---

### Task 12: Ověřovací sada v bráně předání

**Files:**
- Modify: `ums/.claude/skills/shared/scripts/Test-UmsHandoffGate.ps1`
- Modify: `ums/.claude/skills/shared/tests/handoff-gate.tests.ps1`
- Modify: `ums/.claude/skills/shared/overlays/finishing-a-development-branch.overlay.md`

**Interfaces:**
- Consumes: `VerificationSet` (Task 10)
- Produces: čtvrtou kontrolu brány, `verification-set`

- [x] **Step 1: Napiš padající testy**

Tři asercie: citované příkazy shodné s deklarovanou sadou projdou; **chybějící citace je blokující nález**; citace, která se od sady liší, je blokující nález a hláška jmenuje první rozdílný řádek. Porovnává se jako **text**, ne sémanticky.

- [x] **Step 2: Spusť a ověř, že padají**

- [x] **Step 3: Rozšiř skript o parametr `-CitedCommands` a čtvrtou kontrolu**

Kontrola se aktivuje jen tam, kde je sada deklarovaná; kde není a práce patří do epiku, je to STOP podle Tasku 9. Kde práce do epiku nepatří, domovem je plán a chování je stejné.

- [x] **Step 4: Spusť a ověř, že prochází**

- [x] **Step 5: Ověř negativitu**

- [x] **Step 6: Doplň citaci do artefaktu předání v overlay**

Artefakt už pole na ověřovací příkazy má (Task 7); tady se doplní, že se **cituje doslova** a že je brána porovnává jako text.

- [x] **Step 7: Commit a push**

---

### Task 13: Stub sdíleného rozhraní

**Files:**
- Modify: `ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md` — podsekce o epikové lince
- Modify: `ums/.claude/skills/mb-epic-elaboration/protocol.md`

**Interfaces:**
- Consumes: pojem epikové linie (Task 1)

Doc-only task; ověření je studené čtení a grep konzumentů.

- [x] **Step 1: Napiš pravidlo do kontraktu**

Když dva tikety sdílejí rozhraní, epiková linie nese jeho **stub commitnutý dřív, než proti němu kterýkoli z nich implementuje**. Překladač se tím stává orákulem a merge mění sémantický konflikt na textový.

Do textu dej měřený případ, protože bez něj to zní jako obecná rada: signatura `EmployeeResolver` zapsaná v ledgeru jako próza se nepřekládala — parametr navíc, jiné pořadí, špatná arita — a zachytila to náhoda.

- [x] **Step 2: Odkaž z `mb-epic-elaboration`**

Jen odkaz na sekci kontraktu plus to, co je čistě lokální (kdy se ve fázích elaborace stub zakládá). Žádná parafráze důvodu.

- [x] **Step 3: Grep konzumentů**

Příkaz: `grep -rn "stub" ums/.claude/skills/`

- [x] **Step 4: Commit a push**

---

### Task 14: Zrušení nabídky elaborace na hranici fáze

**Files:**
- Modify: `ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md` — sekce „Epic Backflow (design → epic)"
- Modify: `ums/.claude/skills/shared/overlays/brainstorming.overlay.md` — Epic Backflow check

**Interfaces:**
- Consumes: nic; je to samostatné odebrání nabídky

- [x] **Step 1: Přepiš sekci Epic Backflow v kontraktu**

Krok „Queue the note, always" **zůstává beze změny**. Krok „Offer, never launch" se ruší celý včetně varianty (a) s inline oknem: tiketové sezení nález zapíše a pokračuje; elaboraci epiku otevírá jedině správce epiku.

Napiš tam tři důvody, protože bez nich to vypadá jako ubrání funkce: rozpracování epiku je průřezová práce a patří tomu, kdo drží průřezovou paměť; nabídka je zastavení navíc tam, kde bylo naměřeno deset zbytečných; a přepnutí větve uprostřed tiketu je práce na dvou pracovních položkách zároveň.

A jmenovitě: **zaniká nabídka, ne nález.** Bez správce řádek čeká na příští elaborační okno, stejně jako dnes čeká dirty-set.

- [x] **Step 2: Uprav overlay `brainstorming`**

Odstraň nabídku a **jmenovitě neguj** starý postup — fragment nahrazuje upstream text, takže bez negace zůstane starý vedle nového vypadat platně.

- [x] **Step 3: Grepni celou vrstvu na zbytky nabídky**

Příkaz: `grep -rn "inline elaborační\|inline window\|elaborate now" ums/`

Očekávané: žádný výskyt, který by nabídku popisoval jako živou.

- [x] **Step 4: Studený průchod**

Přečti sekci Epic Backflow jako chladný čtenář a projdi obě větve — nález je, nález není. Ani jedna nesmí vést k otázce pro uživatele.

- [x] **Step 5: Commit a push**

- [x] **Konec tasku.** `task-brief` končí až u dalšího nadpisu `Task`, takže
  brief tohohle tasku nese navíc i uzávěrku fáze a vstupní brief fáze další.
  **Nic z toho tenhle task nevykonává** — uzávěrku dělá řídicí sezení, ne
  implementátor tasku.

---

## Výstup fáze 2

- [x] Ověření celé vrstvy smyčkou z playbooku; porovnání s baseline
- [x] Obnova nasazené kopie
- [x] Report česky včetně rozlišení regresních zámků od důkazů opravy
- [x] Zaškrtání kroků, commit, push

**Prompt pro spuštění fáze 3 v čistém kontextu:**

> Pokračuj plánem UMS-3505, **fází 3 (Viditelnost a chování)**. Jsi v repu
> `c:\Users\matejka\source\repos\superpowers` na větvi
> `UMS-3505-orchestrace-epiku`. Plán je
> `memory-bank/proposals/active/plan_ums_3505_orchestrace_epiku.md`, návrh
> `memory-bank/proposals/active/design_ums_3505_orchestrace_epiku.md`.
> Přečti si vstupní brief fáze 3 v plánu a řiď se jím; fáze 1 a 2 jsou hotové
> a zaškrtané. Použij skill subagent-driven-development.

---

# FÁZE 3 — Viditelnost a chování

**Co fáze dodává:** zastavené sezení je vidět bez toho, aby se na něj někdo díval; zprávy nesou značku a nedoručují příčinu jako pokyn; a eskalace mají artefaktovou formu, takže fungují i tam, kde `SendMessage` neexistuje.

**Povaha téhle fáze je jiná** než u předchozích dvou: `pool-status.ps1` má strojové testy, ale pravidla o zprávách a autonomii jsou behaviorální a testují se evaly, ne `.ps1` sadou. Kde test není, je ověřením studený průchod a je to v plánu napsané.

## Vstup fáze 3

**Předpoklady:**

- [x] Fáze 1 a 2 jsou hotové a zaškrtané; poslední commit je na `origin`
- [x] Jsi na `UMS-3505-orchestrace-epiku`, strom čistý, baseline testů zelená

**Co si přečti:** návrh, části 6, 7 a 8 celé; kontrakt, sekce „Session Intent Baton" (blok `NOW` od ní musí být odlišený) a „Fail-Closed Behavior"; `ums/.claude/skills/mb-epic-run/scripts/pool-status.ps1`, funkce `Get-SlotProgress`.

---

### Task 15: Formát bloku `NOW`

**Files:**
- Modify: `ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md`
- Modify: `ums/.claude/skills/shared/overlays/subagent-driven-development.overlay.md`

**Interfaces:**
- Produces: formát bloku, který parsuje Task 16 — strojové značky začátku a konce, šest položek, stavová třída z uzavřeného výčtu, očekávaný čas dalšího ohlášení

- [x] **Step 1: Napiš sekci kontraktu**

Musí obsahovat: strojové ohraničení komentářovými značkami (**ne nadpis** — vložení sekce před textovou kotvu skončilo uvnitř odstavce, který o té kotvě mluvil); šest položek; **stavovou třídu z uzavřeného výčtu** (stojím / čekám na subagenta / čekám na člověka / čekám na správce); **očekávaný čas dalšího ohlášení**; a čtyři pravidla v operačním tvaru.

- [x] **Step 2: Odliš blok od Session Intent Batonu**

Jednou větou, jinak implementátor postaví druhý baton: baton nese, co má nové sezení udělat po restartu; blok nese, na co se právě teď čeká.

- [x] **Step 3: Napiš pravidlo o přepisu jako operaci**

Doslova podle návrhu: přepis je „smaž oblast a rekonstruuj ji z gitu, tabulky tasků a indexu rulingů", ne „napiš to znovu". Z prázdné oblasti není k čemu připisovat. A nutná podmínka: **blok nesmí být jediným domovem žádného faktu.**

**Pravidlo patří do TÉHOŽ odstavce jako artefakt**, ne do sousedního — je naměřené, že se tvar převezme bez pravidla a blok okamžitě zaostane.

- [x] **Step 4: Napiš hranici, kterou blok nesmí překročit**

Blok slouží k rozhodnutí, kam se podívat, **nikdy k rozhodnutí integrovat**. Doklad: jednou tvrdil běžící review několik hodin poté, co se vrátilo se čtyřmi Criticaly.

- [x] **Step 5: Zapiš omezení životnosti**

Blok žije v `.superpowers/sdd/<plan>/progress.md`, který SDD na konci maže, a `pool-status.ps1` ho renderuje jen dokud slot nese pin. Během brainstormingu, psaní plánu a celého dokončování blok **není** — pravidlo o konci turnu ho proto jmenuje jen tam, kde je.

- [x] **Step 6: Grep konzumentů a commit**

---

### Task 16: `pool-status.ps1` — parsování bloku a sloupec „po termínu"

**Files:**
- Modify: `ums/.claude/skills/mb-epic-run/scripts/pool-status.ps1` — `Get-SlotProgress`
- Test: `ums/.claude/skills/mb-epic-run/tests/pool-status.tests.ps1`

**Interfaces:**
- Consumes: formát z Tasku 15
- Produces: `progress.now` s poli `state`, `dueAt`, `late` (`[bool]`) a `items`

- [x] **Step 1: Napiš padající testy**

Asercie, které musí existovat, a tři z nich jsou bezpečnostní:

- blok se najde mezi značkami a rozparsuje se na šest položek;
- **text vypadající jako nadpis uvnitř prózy blok nerozbije** — to je ta měřená vada;
- `late` se **spočítá** z `dueAt` a aktuálního času, nečte se ze souboru;
- chybějící blok dá `$null`, ne chybu;
- **čtenář tělo nevypisuje tak, jak leží**: znaky mimo povolenou třídu se odmítnou a nadměrná velikost se ořízne — soubor je gitignorovaný scratch v **cizím** pracovním stromě, do kterého rutinně píšou implementátorské subagenty, a jeho obsah se renderuje do kontextu správce;
- **zdvojená a vnořená koncová značka mají definované chování** a to chování je aserované, ne ponechané náhodě.

- [x] **Step 2: Spusť a ověř, že padají**

- [x] **Step 3: Implementuj parsování, re-render a limity**

Aplikuj pravidla čtenáře, která kontrakt zavedl pro Session Intent Baton — formát je uzavřený a je to bezpečnostní vlastnost, ne úhlednost.

- [x] **Step 4: Spusť a ověř, že prochází**

- [x] **Step 5: Ověř negativitu každé bezpečnostní asercie zvlášť**

- [x] **Step 6: Commit a push**

---

### Task 17: `mb-epic-run status` — render sloupce

**Files:**
- Modify: `ums/.claude/skills/mb-epic-run/SKILL.md` — sekce `status`

- [x] **Step 1: Doplň sloupce do popisu tabulky**

Česká tabulka dostane sloupec se stavovou třídou a sloupec „po termínu". Zdůrazni, že „po termínu" je **spočítané**, ne přečtené — v tom je celý rozdíl proti tomu, co se dnes musí přečíst.

- [x] **Step 2: Zapiš pravidlo o pobídce**

Stavová třída „čekám na subagenta" **není důvod k pobídce**. S blokem je to poprvé kontrolovatelné, ne otázka ohleduplnosti.

- [x] **Step 3: Commit a push**

---

### Task 18: Protokol zpráv

**Files:**
- Modify: `ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md` — nová sekce
- Modify: `ums/.claude/skills/mb-epic-run/SKILL.md` — odkaz, ne parafráze

Doc-only; ověření je studený průchod.

- [x] **Step 1: Napiš sekci kontraktu**

Značení **pokyn / domněnka**; právo domněnku odmítnout; domněnka se do ledgeru nezapisuje jako fakt; **příčina je vždycky domněnka, hranice smí být pokyn**; povinnost odmítnout pokyn odporující psanému pravidlu; relay timing (bezprostřednost, ne důležitost); jeden živý odběr na peera obnovený až po sepnutí; a že resynchronizace je **tažená** — merge báze uprostřed tasku kontrakt zakazuje, takže zpráva pořadí urychluje, nezakládá ho.

- [x] **Step 2: Označ pravidla bez mechanické spouště**

Sekce musí **jmenovitě** říct, která z těch pravidel jsou doporučení a ne brány. Bez toho je implementátor zapíše do skillu, jako by byly vynucené — a je naměřené, že pravidlo bez spouště se poruší i svým autorem.

- [x] **Step 3: Napiš příklad k pravidlu o příčině**

Bez měřeného případu to zní jako obecná rada: varování o `CS0246` doručené minutu před měřením baseline nepomohlo, protože příjemce udělal restore jako první krok — ale trefil druhou past se stejným příznakem a doručené vysvětlení by ho poslalo opravovat restore, který byl v pořádku.

- [x] **Step 4: Odkaz z `mb-epic-run`, grep konzumentů, commit**

---

### Task 19: Eskalační tabulka a tři úrovně autonomie

**Files:**
- Modify: `ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md`
- Modify: `ums/.claude/skills/mb-epic-elaboration/ledger-template.md` — deklarace úrovně a sloupec v `Rozjetí`
- Modify: `ums/.claude/skills/mb-epic-elaboration/scripts/ledger-status.ps1` — čtení úrovně
- Test: sada `mb-epic-elaboration`

**Interfaces:**
- Consumes: registr a sekce ledgeru (Task 9)
- Produces: `AutonomyLevel` čtený sezením z commitnutých dokumentů

- [x] **Step 1: Napiš eskalační tabulku do kontraktu**

Tři pásma podle části 8 návrhu. **Každý druh má řádek se stavem v ledgeru** — to je jeho artefaktová forma a to, co ho drží funkčním i bez `SendMessage`, které je vázané na Claude Code a ve vrstvě se dnes nepoužívá nikde.

Do dna patří i **změna `epicBranchPattern` a `protectedBranches`** — ne z nedůvěry, ale protože rozšíření výsady je rozhodnutí a kontrakt u změn konfigurace repozitáře schválení vyžaduje tak jako tak.

- [x] **Step 2: Zapiš, co do výčtu nepatří**

Pokyn odporující psanému pravidlu **není eskalace, je to vyhledání**. Příjemce ho odmítne a odkáže na pravidlo; teprve když je pravidlo skutečně nejednoznačné, jde otázka **k člověku, nikdy ke správci** — správce je v tom sporu stranou.

- [x] **Step 3: Napiš dvě pravidla o konci turnu**

Konec turnu je legitimní jen tam, kde čekáš na odpověď člověka, na odpověď správce, nebo na doběhnutí subagenta — a to čekání musí být pojmenované: tam, kde blok existuje, jeho stavovou třídou; jinde v hlášení. A: když formuluješ otázku, vyjmenuj, co na odpovědi nezávisí, a to udělej hned.

- [x] **Step 4: Přidej deklaraci úrovně do ledgeru a sloupec do `Rozjetí`**

Pozor: sloupce `Rozjetí` parsuje `ledger-status.ps1` **pozičně**, takže přidání sloupce je změna, kterou musí sada zachytit. Napiš na to test **dřív**, než sloupec přidáš.

- [x] **Step 5: Napiš padající test na čtení úrovně a na nový sloupec**

- [x] **Step 6: Spusť, implementuj, spusť znovu**

- [x] **Step 7: Ověř negativitu**

- [x] **Step 8: Commit a push**

- [x] **Konec tasku.** `task-brief` končí až u dalšího nadpisu `Task`, takže
  brief tohohle tasku nese navíc i uzávěrku fáze a vstupní brief fáze další.
  **Nic z toho tenhle task nevykonává** — uzávěrku dělá řídicí sezení, ne
  implementátor tasku.

---

## Výstup fáze 3 a uzavření tiketu

- [x] Ověření celé vrstvy smyčkou z playbooku
- [x] Obnova nasazené kopie
- [x] **Projdi seznam Verifikace v návrhu** (26 bodů) a u každého zapiš: pokrytý testem (kterým), pokrytý studeným průchodem, nebo nepokrytý a proč. Nepokrytý bod není selhání — nezapsaný nepokrytý bod ano.
- [x] Report česky
- [ ] `finishing-a-development-branch` — Harvest Gate, harvest skillem `mb-harvest`, a integrace podle **nové** procedury, kterou tenhle plán právě zavedl. Je to první ostrý průchod tou cestou; co na něm nesedí, je nález.

---

## Self-review plánu

**Pokrytí návrhu.** Části 1 až 4 → fáze 1 (tasky 1 až 8). Část 5 → fáze 2 (tasky 9 až 13). Části 6 až 8 → fáze 3 (tasky 15 až 19). Zrušení nabídky elaborace → task 14. „Stavy mimo šťastnou cestu" → tabulka je součástí kontraktu psaného v tasku 1, krok 4.

**Vědomé mezery, zapsané, ne přehlédnuté:**

- **Odchylka IDLE resetu má dosah na každou práci v repu**, ne jen epikovou. Task 5 to řeší, ale strojový test na to neexistuje, protože `mb-harvest` je instrukční Markdown. Náhradou je studený test tvaru v kroku 4 a první ostrý průchod ve výstupu fáze 3.
- **Task 5 krok 3 může odhalit blokující nález** (`mb-jira-update` bere klíč z `context.md`). Je to jediné místo plánu, kde se očekává ruling s možným dopadem na cizí skill.
- **Přidání sloupce do `Rozjetí`** (task 19) mění poziční parsování. Test se píše před změnou schválně.
- **Briefy tasků 8, 14 a 19 přetékají přes hranici fáze.** Skript task-brief
  končí až u dalšího nadpisu Task, takže poslední task každé fáze dostane
  navíc uzávěrku fáze a vstupní brief fáze další. Ověřeno spuštěním pro všech
  devatenáct čísel: šestnáct briefů sedí na řádek, tři přetékají o hranici
  fáze. Není to rozbitý ohraničovač bloku (ohraničovačů je osmnáct, tedy devět
  párů) a přesah je ohraničený a předvídatelný, ne runaway — proto je
  pojmenovaný přímo v těch třech tascích místo přestrukturování plánu.
- **Behaviorální pravidla fáze 3 nemají strojový test.** Je to v úvodu fáze napsané a ověřením je studený průchod. Evaly nejsou součástí tohohle plánu.

---

## Procházka seznamu Verifikace návrhu (26 bodů)

Zapsáno při uzávěrce fáze 3, měřeno proti `a798fe0`. Legenda: **T** = pokrytý
jmenovaným testem, **I** = pokrytý inspekcí (studeným průchodem), **N** =
nepokrytý. Nepokrytý bod není selhání; nezapsaný nepokrytý bod ano.

| # | Bod | Stav | Čím |
|---|-----|------|-----|
| 1 | FF na epikovou linii jen v protokolární podobě | **T částečně** | `guard-git-push.tests.ps1`, blok „Epiková výjimka" — pozitivní případ i všechny čtyři negativní; `--force`/`-f` odmítá `PUSH_ALLOWED_FLAGS`. **Ale** „nový obsah" a „první publikace" stojí na obsahovém pravidle `pre-push`, testovaném obecně a **nikdy s epikovou fixturou** — obě půlky jsou testované jen odděleně (nález M4, odložen). |
| 2 | Agentní push do dodávkové linie neprojde ani omylem | **T pro konfigurovanou bázi** | `guard-git-push.tests.ps1` (pět případů). Pro **efektivní** bázi jinou než `baseRef` záruka neplatí — nález I6, uzavřený rulingem R26 dokumentací; zbytkové riziko kryje eskalační dno, které změnu `epicBranchPattern`/`protectedBranches` bezpodmínečně dává člověku. |
| 3 | JEDNA PROCEDURA (nejdůležitější test celého návrhu) | **I** | Base-režimová otázka se klade právě dvakrát: Sync volí **domov**, Handoff volí **vykreslení**. Ověřeno proti textu overlay fragmentu, ne proti tvrzení. Oprava C1 přidala třetí větev, ale ta se rozhoduje `Test-Path` uvnitř ramene „báze nesedí" — ptá se, který dokument položka **má**, ne jaká je báze. Test by zůstal zelený. |
| 4 | `epicBranchPattern` mimo `protectedBranches` je chyba konfigurace | **N** | Žádná taková kontrola ve vrstvě neexistuje a žádné sezení není instruováno ji provést. Navazující položka. |
| 5 | `Get-UmsBaseCandidates` nabízí epikovou linii, víceúrovňový glob | **I** | `lstrip=3`, `Test-UmsProtectedBranch` s `-like` napříč lomítkem. `base-candidates.tests.ps1` **nemá žádný epikový případ** — mezera v pokrytí testem, ne v chování. |
| 6 | Brána předání čte čerstvý tip | **T** | `handoff-gate.tests.ps1` (posun báze, selhaný fetch jako STOP, vlastní jméno `fetch-failed`). |
| 7 | Chybějící `context.md` je STOP, ne IDLE; ACTIVE = pár pinu | **T** | `handoff-gate.tests.ps1`. |
| 8 | FF vázaný na vlastní epik tiketu | **T** | `epic-gate.tests.ps1` (`wrong-epic`, `no-epic-header`, `no-spawn-row`). |
| 9 | Nepotvrzený řádek registru blokuje, po potvrzení projde | **T** | `epic-gate.tests.ps1` (`unconfirmed` včetně „zavřeno" nad prázdnou SHA, `multi-unconfirmed`, `ok`). |
| 10 | Behaviorální předpoklad se zavírá testem, ne přečtením | **N, a nevynutitelné konstrukcí** | `Druh` nemá mechanického konzumenta a mít ho nemůže — SHA je SHA. Nález I7: kontrakt teď **říká**, že je to povinnost toho, kdo SHA dodává, ne kontrola brány, a výslovně zakazuje domnělou kontrolu dodávat. |
| 11 | Stub sdíleného rozhraní překládá dřív, než proti němu kdokoli implementuje | **I** | Kontrakt + `protocol.md`. Půlka „kompilátor jako orákulum" je vlastnost produktu, zde netestovatelná. |
| 12 | Epik bez deklarované sady je STOP; artefakt cituje doslovně; brána porovnává jako text | **T porovnání, I STOP** | `handoff-gate.tests.ps1` (chybějící citace, odlišná citace, rozdíl jen ve velikosti písmen, „blokuje POUZE verification-set"). Sám STOP je próza overlaye — a právě tady byl Critical C1 a nález I4. |
| 13 | Post-harvest `context.md` bajtově identický | **I** | Kontrakt „IDLE state"; `mb-harvest` i `mb-abort` srovnané. Bez testu. |
| 14 | Potvrzení běží na tiketové větvi před Jirou a i bez Jira tiketu | **I** | Overlay fáze Confirmation + kontrakt; `mb-jira-update` přepnutý na fázovou terminologii. |
| 15 | Holý `git push` po `switch -c` musí být odmítnut | **N touto vrstvou** | Odmítnutí obstarává `push.default=simple` gitu a obsahové pravidlo `pre-push`, ne guard: cíl se odvodí jako **jméno aktuální větve**, ta není chráněná, a test na surovou SHA se nedosáhne. Chování drží; **vysvětlení v kontraktu bylo chybné a nález M5 ho opravil**. |
| 16 | Blok strojově ohraničený, přežije prózu vypadající jako nadpis, zdvojené a vnořené značky definované, nadměrný oříznutý | **T** | `pool-status.tests.ps1`, případy 17/18/19 — osm malformed tvarů, zdvojená koncová značka za oblastí definovaná jako ignorovaná, strop 200 znaků, odmítnutí znakové třídy. |
| 17 | Přepis je smaž-a-rekonstruuj; fakt bydlící jen v bloku nesmí přežít | **I** | Kontrakt + SDD overlay. Netestovatelné. |
| 18 | „Po termínu" se počítá, ne čte; „čekám na subagenta" není důvod k pobídce | **T výpočet, I pobídka** | Tytéž bajty, posunuté hodiny, `late` se překlopí; rovnost není po termínu. |
| 19 | Když si blok a `git log` odporují, blok je špatně | **I** | Kontrakt. |
| 20 | Vyjmenuj, co na odpovědi nezávisí, a udělej to hned | **I** | Druhé operační pravidlo sekce Escalation & Autonomy. |
| 21 | Autonomie mění směrování; dno se nehýbe; `epicBranchPattern` je na dně | **T + I, po doplnění taxonomie** | Směrovací půlka pokrytá (tři úrovně, tři pásma, pět řádků dna; `ledger-status.ps1` čte deklaraci i override, s testy). **Taxonomie tříd konfliktů byla ve vrstvě celá chybějící** a byla doplněna v opravné vlně — klauzuli po klauzuli proti části 5 návrhu, včetně záměrné asymetrie, že třída 4 nenese „na hranici". Sezení teď umí rozhodnout, jestli červený build před ním vůbec je nález, a kdo hlásí nález třídy 1/2/4 a kdy. |
| 22 | Každé eskalační pásmo má artefaktovou formu | **I** | Vyřízeno výslovně pro všechna tři pásma; formou dna je sám STOP a hlášení, které ho pojmenuje. |
| 23 | Opuštěný tiket nechá epikovou linii netknutou a zavře své řádky | **N** | Nic neváže `mb-abort` na zavření řádků `Rozjetí` a registru; pravidlo „nepublikované opuštění je nález" neexistuje. Navazující položka. |
| 24 | Epiková linie bez epiku je nález `mb-doc-index`, ne ticho | **N** | `mb-doc-index` nebyl tímto plánem měněn a epikovou logiku nemá. Navazující položka. |
| 25 | `stripRef` je case-insensitive | **T** | `guard-git-push.tests.ps1` (`refs/HEADS/`, `Refs/Heads/`); komentář `pre-push` doplněn o paritu. |
| 26 | Epic Backflow už nenabízí elaboraci, poznámka se dostane do dalšího okna | **I** | `brainstorming.overlay.md`, `mb-architect-review`, kontrakt. Bez testu. |

**Souhrn: 13 bodů pokrytých jmenovaným testem, 8 inspekcí, 5 nepokrytých
(4, 10, 15, 23, 24), 1 pokrytý až po doplnění v opravné vlně (21).**

Z pěti nepokrytých je bod 10 nevynutitelný konstrukcí a kontrakt to teď říká;
bod 15 drží v praxi a opravena byla jen jeho mylná explikace. Zbývají **tři
skutečné navazující položky: 4, 23 a 24.**
