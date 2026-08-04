# Návrh: Model tiketových větví a integrace do báze

- **Jira:** (žádný tiket)
- **Target MB:** memory-bank/
- **Vytvořeno:** 2026-08-04

## Cíl

Dotáhnout práci s git větvemi tak, aby paralelní práce více aktérů na jednom
monorepu byla viditelná včas a integrace do báze byla jeden nesporný krok.
Konkrétně:

- **tiketová větev se publikuje po každém commitu**, takže ostatní aktéři vidí,
  co se děje, a kolizní kontrola má na čem stát;
- **báze se merguje do tiketové větve na hranicích fází**, aby se drift zjistil
  včas, ne až při harvestu — ale bez toho, aby merge sám o sobě zdržoval práci;
- **výsledek se do báze dostane fast-forward pushem tiketové větve**, ne mergem
  do lokální báze; lokální báze se v tiketovém klonu nepoužívá vůbec;
- **báze a chráněné větve se stanou konfigurací**, protože dnešní zadrátované
  `origin/develop` a `release/*` neodpovídají skutečnosti ani v tomto forku, ani
  v monorepu.

Návrh je **první ze dvou** pracovních položek. Druhá zavede pool samostatných
klonů pro izolaci práce na více tiketech naráz; tento návrh k němu přihlíží
(rezervovaný konfigurační klíč, formulace pravidel platné pro N lokálních
klonů), ale nic z něj nestaví.

## Kontext a nalezená mrtvá místa

Analýza kontraktu v2.5, tří overlayů, `pre-push`, `guard-git-push.mjs`,
`doc-index.ps1`, [CLAUDE.md](../../../CLAUDE.md) a skutečného stavu monorepa
(`d:\_datasys\ums`) našla tato mrtvá místa. Každé z nich tento návrh zavírá,
nebo ho výslovně nechává mimo rozsah.

**1. Zadrátovaná báze.** `doc-index.ps1` má default `-BaseRef origin/develop`
a v tomto forku na něm spadne (`Base ref not found: origin/develop`) — fork
integruje do `ums-memory-bank`. Vrstva je redistribuovatelná, takže báze nemůže
být literál.

**2. Chráněný seznam míjí živé maintenance větve.** `pre-push` chrání
`develop`, `main`, `master`, `release/*`. Na `origin` monorepa přitom žijí
`Branches/5.33` až `Branches/5.37` — do těch dnes agent pushne bez jakékoli
překážky.

**3. Zamítací hláška radí příkaz, který v tiketovém klonu nefunguje.**
`pre-push` nabízí `git push <remote> <branch>`, tedy `git push origin develop`.
V klonu bez lokálního `develop` to neudělá, co si člověk myslí. Mechanika
refspecového tvaru je přitom v pořádku už dnes: hook testuje **cílový** ref,
takže `git push origin HEAD:develop` zamítne stejně, a `guard-git-push.mjs`
bere destinaci za dvojtečkou. Chybí jen správná rada.

**4. Konvence `--no-ff` je s novým modelem neslučitelná.** Když je
`origin/develop` mergnutá do tiketové větve, je předkem jejího tipu, takže push
do `develop` **je** fast-forward. Merge commit s bází jako prvním rodičem nejde
vyrobit, aniž by byla báze někde checkoutnutá. Konvence tedy nejde obejít, jde
jen zrušit.

**5. Souběh při integraci není nikde popsaný.** Bez lokální báze selže FF push
vždy, když se báze mezitím pohnula. Projeví se to navíc hláškou o „vynuceném/force
pushi", ačkoli skutečná příčina je jiná.

**6. Konflikt `memory-bank/context.md` je nevyhnutelný a neřešený.** Je to
trackovaný soubor sdílené větve nesoucí stav jednoho pracovního stromu. Tiket A
ho harvestem resetuje na `IDLE` a pushne do báze; tiket B pak při každém mergi
báze dostane konflikt své `ACTIVE` hlavičky. S mergem na každé hranici fáze to
přestává být výjimka a stává se denním jevem.

**7. Filtr `doc-index.ps1` je falešně negativní na živých větvích.** Dnešní
`git log --remotes=origin --not <base> --since=<datum>` filtruje podle **data
commitu**. Dlouho žijící větev, na které se pracovalo včera, ale jejíž návrhový
dokument vznikl před šesti měsíci, z indexu vypadne — větev i položka jsou živé.
Proto je default nafouknutý na 120 dní. Navíc `--remotes=origin` musí sestoupit
od každého tipu včetně dávno mrtvých.

**8. Doporučené jméno větve neodpovídá praxi.** Kontrakt doporučuje
`feature/ums-3302-toast-reconcile`; na `origin` jsou tvary
`UMS-1494-description-k-workflow`.

**9. Popsaný, ale nepostavitelný worktree pool.** Kontrakt nese podsekci
„Future worktree pool (interface only — not implemented)" s manifestem a
mechanikou, kterou nikdo nepostaví — izolaci vyřeší pool klonů v druhé položce.

Mimo tento návrh, ale zjištěné a hodné zápisu: tři trackované `.cmd` skripty
(`Doc/Tools/!GenerateAll.cmd`, `Doc/Tools/GenerateCharakteristika_a_popis_produktu_DATASYS_UMS.cmd`,
`MobilChange/SMSInfo3/code_search.cmd`) mají absolutní cestu `_datasys`
zadrátovanou natvrdo.

## Rozhodnutí

| # | Rozhodnutí | Důvod |
|---|---|---|
| 1 | Integrace je **fast-forward push** tiketové větve do báze; konvence `--no-ff` se **ruší** | Nejde obejít (mrtvé místo 4); FF historie je cena za to, že integrace nepotřebuje lokální bázi |
| 2 | Ten push zůstává **lidským příkazem** (`! UMS_ALLOW_SHARED_PUSH=1 git push origin HEAD:<base>`) | Dvouúrovňová policy zůstává celá; mění se tvar příkazu, ne kdo rozhoduje |
| 3 | **Push po každém commitu** vlastní tiketové větve | „Dostatečně často" není vynutitelné pravidlo; force push zůstává zakázaný, takže častý push nemůže nic přepsat |
| 4 | Merge báze je **povinný na hranicích fází**, verifikace po něm **odstupňovaná** | Účelem merge je včasná detekce driftu; drahý je build, ne merge |
| 5 | `baseRef` a `protectedBranches` jsou **konfigurace repozitáře** | Vrstva je redistribuovatelná (mrtvá místa 1, 2) |
| 6 | `doc-index.ps1` filtruje podle **poslední aktivity větve**, ne data commitu | Opravuje falešná negativa a zároveň zrychluje (mrtvé místo 7) |
| 7 | Podsekce worktree poolu se z kontraktu **maže** | Popsané a špatné rozhraní je horší než žádné; zákaz worktrees jako takový zůstává |

Zamítnuté varianty:

- **Zachovat `--no-ff` mergem v základním workspace.** Zachovalo by jeden
  pojmenovaný merge commit na tiket, ale integrace by dál procházela lokální
  bází — přesně to, co má tento model odstranit.
- **Udělat z FF pushe do báze legální agentskou operaci.** Integrace je vždy FF
  z tiketové větve, takže by to dvouúrovňovou policy nezúžilo, ale zrušilo.
- **Přesunout ochranu na server a lokální hook uvolnit.** Vyžadovalo by ověřit,
  že branch permissions na Bitbucketu skutečně existují; mimo rozsah.
- **Přestat trackovat `context.md`.** Zabilo by cross-branch viditelnost, na
  které stojí `mb-doc-index` i handoff design review.

## Scope

**V rozsahu:** kontrakt v2.6; tři overlay fragmenty; `pre-push` a
`guard-git-push.mjs` (seznam z konfigurace, dvě hlášky); `install-git-hooks.ps1`
(generování seznamu); `doc-index.ps1` (konfigurace + filtr aktivity);
`mb-architect-review`, `mb-jira-update`, `mb-state`, `mb-git-commit`;
[CLAUDE.md](../../../CLAUDE.md) a [ums/CLAUDE.md.sample](../../../ums/CLAUDE.md.sample);
Memory Bank dokumenty tohoto repa; čtyři existující testovací sady plus jedna
nová.

**Mimo rozsah:** pool klonů a adopce tří existujících ad-hoc klonů (druhá
položka); mazání zbylých tiketových větví na `origin`; branch permissions na
serveru; oprava tří `.cmd` skriptů se zadrátovaným `_datasys`.

## Technický návrh

### 1. Model větví a integrace

**Založení.** `git fetch origin`, pak `git branch <TICKET>-<kebab-slug>
origin/<baseRef>`. Žádná lokální báze, tedy ani dnešní „fetch + fast-forward
lokální báze". Jméno větve je `<TICKET>-<kebab-slug>` v ASCII; existující větve
s diakritikou se nepřejmenovávají. Bez tiketu se použije `<kebab-slug>` sám.

**Lokální báze se v tiketovém klonu nepoužívá.** Pokud v něm existuje
(adoptovaný klon), neaktualizuje se a nemerguje. Jediné místo, kde je báze
checkoutnutá, je základní workspace.

**Publikace.** Agent pushuje vlastní tiketovou větev **po každém commitu** a
vždy ohlásí větev i odchozí commity. Čtyři dnešní publikační body (návrh, plán,
uzávěrka elaboračního okna, handoff) tím zůstávají v platnosti jako zvláštní
případy a automaticky se doplňují o to, co v seznamu chybělo: commit
implementátora po zeleném tasku, commit po mergi báze, commit MB změn po
harvestu. Force push zůstává zakázaný.

**Integrace.** Sekvence po dokončení harvestu a jeho commitu:

1. `git fetch origin`
2. `git merge origin/<baseRef>` (base sync dle sekce 2)
3. zelená verifikace
4. agent připraví `! UMS_ALLOW_SHARED_PUSH=1 git push origin HEAD:<baseRef>`
   s výčtem odchozích commitů; **uživatel ho spustí**
5. agent znovu ověří dosažitelnost (`git fetch origin`,
   `git branch -r --contains <sha>`)
6. `mb-jira-update` ve finalizačním režimu

**Souběh.** Selhání pushe na non-fast-forward znamená, že se báze pohnula:
opakuj od kroku 1. Strop jsou **dvě neúspěšná kola**, pak zastav a ohlas
uživateli, že někdo integruje současně. Hláška hooku o non-FF dostane větu
odlišující pohnutou bázi od pokusu o force push.

**Zbylá tiketová větev na `origin`** se nemaže — mazání větve přes push je
zakázané a zůstává. Jako kolize se nehlásí, protože `mb-doc-index` klíčuje podle
fáze a návrh je po harvestu v `proposals/completed/`.

### 2. Base sync a detekce driftu

**Hranice fází, na kterých se merguje báze:** před `writing-plans`; před
dispatchem prvního tasku; před requestem a před resume design review; před
whole-branch review; před `mb-harvest`. **Nikdy uprostřed tasku.**

**Sekvence na každé hranici:** `fetch` → `merge origin/<baseRef>` → posouzení
průniku (níže) → případná verifikace → commit → push.

**Posouzení průniku je mechanické.** Obě množiny cest se počítají **po `fetch`,
ale před `merge`**, ze stejného merge-base — tím je definice nezávislá na tom, co
si kdo zapamatoval před fetchem:

```
MB=$(git merge-base HEAD origin/<baseRef>)
prichozi=$(git diff --name-only $MB..origin/<baseRef>)   # co merge přinese
vlastni=$(git diff --name-only  $MB..HEAD)                # co větev změnila
```

Ve fázi návrhu, kdy ještě není co změněno, roli **vlastní** množiny hrají cílové
oblasti pojmenované v návrhu.

Porovnání na úrovni jednotlivých souborů je v .NET příliš úzké — změna ve
sdíleném projektu, který ten váš referencuje, je drift bez shody souborů. Proto
se cesty mapují na **vlastnící projekt nebo solution** a průnik se hledá tam;
jako vždy-protínající se berou sdílené kořeny (`Common/`, `Lib/`,
`SharedAssemblyInfo.xml`, `*.sln`, `Build.proj`). **Je to heuristika**, ne
důkaz — pojmenovaná tak i v kontraktu.

**Odstupňovaná verifikace:**

| Situace | Chování |
|---|---|
| Bez průniku | Žádná verifikace. Jednořádkové konstatování v reportu, pokračuje se. |
| S průnikem | Agent vypíše protínající se cesty a **nabídne** baseline (build a cílené testy dle `playbook.md` cílové MB) s doporučením. **Rozhoduje uživatel.** |
| Konflikt v mergi | Automaticky průnik, hlásí se vždy. |
| Fáze návrhu a design review | Nic se nestaví; verifikace je čistě nabídka. Hodnota průniku je jiná — může znamenat, že drift zasahuje do samotného návrhu, a to patří do návrhu. |
| Před dispatchem prvního tasku | Baseline je povinná už dnes ([CLAUDE.md](../../../CLAUDE.md)); tím se nic nemění. |

**STOP platí jen tam, kde verifikace skutečně proběhla a je červená.** Cizí
rozbití báze se nikdy neopravuje uvnitř tiketové větve. Konflikt v mergi řeší
agent jen v souborech, které na větvi sám měnil; jinak STOP.

**Design review má asymetrii, která musí být napsaná.** Merguje **jen strana
řešitele** (request a resume). Architekt v režimu respond nemerguje nikdy —
`mb-architect-review` dělá vlastní branch sync s pravidlem „divergence = STOP",
takže merge z obou stran by skill zastavil na jeho vlastní pojistce. Merge báze
patří **před** handoff push.

**Konflikt `memory-bank/context.md`** se při mergi báze řeší vždy ponecháním
verze tiketové větve — cíleně `git checkout --ours memory-bank/context.md`,
nikdy `merge -X ours` na celý merge. Je to stav tohoto klonu, ne fakt o
produktu. U `proposals/active/` konflikt nevzniká (jiný slug = jiné soubory);
konflikt na **témže** slugu je kolize dvou aktérů, tedy STOP.

### 3. Konfigurace repozitáře

Nový trackovaný soubor `<MB_ROOT>/.claude/ums-repo.json`:

```json
{
  "baseRef": "origin/develop",
  "protectedBranches": ["develop", "main", "master", "release/*", "Branches/*"],
  "clonePool": { "enabled": false }
}
```

- `clonePool` je **rezervovaný a vypnutý** — místo pro druhou položku.
- **Chybějící soubor není chyba.** `baseRef` degraduje na `origin/develop`,
  ochrana na dnešní zadrátovaný seznam. Vrstva musí fungovat i v repu, který
  konfiguraci nepřijal.
- V tomto forku bude `baseRef` rovno `origin/ums-memory-bank`, čímž mizí
  spadnutí z mrtvého místa 1.

### 4. Chráněné větve a dvě vrstvy vynucení

`guard-git-push.mjs` čte JSON přímo. `pre-push` je POSIX `sh` bez JSON parseru a
parsování JSONu sedem do něj nepatří, takže:

- `install-git-hooks.ps1` z trackovaného JSONu **vygeneruje** prostý soubor
  `<git-common-dir>/ums-protected-branches`, jeden glob na řádek;
- hook ho přečte smyčkou `while read` + `case` (matching zůstává
  case-insensitive, jak je dnes);
- **chybějící soubor = dnešní zadrátovaný seznam.** Fallback vede vždy k *více*
  ochrany, nikdy k méně.

**Důsledek, který musí být napsaný:** změna seznamu vyžaduje nový běh
instalátoru. Ten se ze [sync-with-monorepo.ps1](../../../ums/sync-with-monorepo.ps1)
volá sám při `-Scope Monorepo`.

Do seznamu se přidává `Branches/*` (mrtvé místo 2). Ostatní zvláštnosti na
`origin` (`Branch_6ede93f5`, `KIC_Skoda_…`) vypadají jako ad-hoc a legacy
větve, ne integrační — **zůstávají nechráněné, a je to rozhodnutí, ne
opomenutí.**

Dvě hlášky hooku: zamítnutí pushe do sdílené větve radí refspecový tvar
(`git push <remote> HEAD:<base>`); zamítnutí non-FF rozlišuje pohnutou bázi od
force pushe.

### 5. `doc-index.ps1`: filtr podle aktivity větve

Dnešní `--since` se ruší a nahrazuje dvoustupňovým filtrem:

1. `git for-each-ref --format='%(refname) %(committerdate:unix)'
   refs/remotes/origin/` — vyřadit větve, jejichž **tip** je starší než okno.
   Jedno čtení refů bez procházení historie.
2. `git log <přeživší refy> --not <base> --name-only …` **bez** datového
   omezení commitů, takže se historie návrhu na živé větvi najde celá.

**Dvě okna, ne jedno.** Přehledová tabulka jede na novém defaultu **30 dní**.
Kontrola s deklarovaným záměrem (`-Jira` / `-Slug`) běží **bez omezení** —
kontrakt chce, aby nález nesl větev a datum posledního commitu, aby uživatel
poznal opuštěnou větev od živé práce. Kdyby se 30denní filtr aplikoval i na ni,
uspaná větev kolegy na témže tiketu by z nálezů zmizela, a to je právě ta
informace, kterou je před pinováním potřeba nejvíc. Druhý průchod se dělá jen
při deklarovaném záměru.

**Tři implementační pasti:**

- `refs/remotes/origin/HEAD` je symref na bázi a musí se vynechat, jinak
  duplikuje bázi;
- stovky refů na příkazové řádce narazí na 32k limit Windows — refy se posílají
  přes `git log --stdin`;
- `-BranchGlob` se aplikuje **před** filtrem aktivity, ne po něm.

## Dopady

**Kontrakt v2.5 → 2.6.** Mění se *Publication Contract* (publikační body →
pravidlo push-po-commitu, refspecový příkaz, integrační sekvence se stropem dvou
kol), *Cross-Branch Visibility* (zakládání z `origin/<baseRef>` bez lokální
báze), *Architect Review Gate* (jméno větve, merge asymetrie) a *Fail-Closed
Behavior* (nemožný base sync, strop integračních kol). Přidávají se sekce **Base
Sync & Drift Detection** a **Repository Configuration**. Maže se podsekce
„Future worktree pool (interface only — not implemented)"; zákaz worktrees
zůstává beze změny.

**Tři overlaye.** `brainstorming` — zakládání větve z `origin/<baseRef>`.
`subagent-driven-development` — base sync před prvním dispatchem, push po každém
zeleném tasku, zákaz merge uprostřed tasku. `finishing-a-development-branch` —
největší přepis: upstream Option 1 „Merge Locally" se **nahrazuje** integrací
pushem tiketové větve; mizí otázka na refresh lokální báze i věta o `--no-ff`.
Je to jediný fragment s kotvou `ANCHOR-BEFORE`, ta zůstává na
`## Step 5: Execute Choice`.

Dvě věci se přitom samy zjednoduší: `mb-jira-update` dnes finalizuje „po zeleném
lokálním mergi" a dosažitelnost ověřuje zvlášť — nově je spouštěčem přímo
ověřený FF push, což je to, co ta brána vždy chtěla. A u `mb-harvest` je po
mergi báze `merge-base(<base>, HEAD)` rovno tipu báze, takže derivace
`AFFECTED_MBS` z diffu obsahuje jen vlastní práci a nic cizího.

| Kde | Co |
|---|---|
| [CLAUDE.md](../../../CLAUDE.md) + [ums/CLAUDE.md.sample](../../../ums/CLAUDE.md.sample) | zrušit `--no-ff` a refresh lokální báze; přidat integraci FF pushem, base sync, push po každém commitu — **obě kopie**, sample je to, co sync injektuje do cílů |
| [architecture.md](../../architecture.md) | sekce o publikaci a viditelnosti (publikační body, tabulka policy), invariant o dvouúrovňové publikaci, popis finishing overlaye; invariant „Bez worktrees" zůstává |
| [brief.md](../../brief.md) | odrážka o sdílených větvích — smysl zůstává, mění se příkaz |
| [tech.md](../../tech.md) | pin kontraktu (dnes uvádí 2.3, tedy už teď zpožděný o dvě verze), nový `ums-repo.json` a generovaný seznam, počty asercí, změřený výkon `doc-index.ps1` |
| `mb-architect-review` | branch sync, merge asymetrie, rozpoznání větve podle kódu tiketu |
| `mb-jira-update` | spouštěč finalizace = ověřený FF push |
| `mb-state` | přidat vzdálenost od báze (`git rev-list --count HEAD..origin/<baseRef>`) |
| `mb-git-commit` | zůstává „nikdy nepushuje"; formulovat tak, aby to nekolidovalo s pravidlem push-po-commitu (pushuje volající) |

**Playbook se v taskech nepíše.** `playbook.md` má konzultační režim — postupy
k práci s větvemi se během práce sbírají jako kandidáti do
`.superpowers/playbook-candidates.md` a procházejí harvestovou bránou ke
schválení. Zvlášť to platí pro **druhou Memory Bank**:
`d:\_datasys\ums\memory-bank\playbook.md` je MB produktu a pravděpodobně nese
dnešní merge postup. Kdyby se pravidla změnila jen ve vrstvě, produktový
playbook by dál lidem říkal, ať mergují do lokální báze. **Kontrola toho souboru
je výslovný výstup této práce.**

**Testy.** `pre-push.tests.ps1` — `Branches/*`, generovaný seznam, fallback při
jeho chybění, refspecový tvar `HEAD:<base>`, nové hlášky.
`guard-git-push.tests.ps1` — seznam z konfigurace. `enumeration.tests.ps1` —
**přepis** na filtr aktivity větve (ne rozšíření: mění se semantika), `--stdin`,
vynechání symrefu `HEAD`, pořadí `-BranchGlob`; fixtury s explicitně nastaveným
`GIT_COMMITTER_DATE`, aby byly deterministické. `findings.tests.ps1` — uspaná
větev s týmž tiketem musí být v kolizní kontrole stále hlášená. Nová sada pro
čtení konfigurace a fallbacky, s vlastní kopií `_assert.ps1` dle konvence repa.

**Jedno měření.** [tech.md](../../tech.md) přiznává, že výkon `doc-index.ps1` je
ověřený jen v malém měřítku (3 větve, 1–2 s; rozpočet do 15 s při stovkách větví
neověřen). Skript je read-only, takže jedno měření proti skutečnému monorepu je
bezpečné; číslo se zapíše do `tech.md`. Nový filtr by měl výsledek zlepšit,
protože mrtvé větve se přestanou procházet.

## Rizika

| Riziko | Ošetření |
|---|---|
| **Ztráta per-tiket merge commitu** v bázi — `git log --first-parent` přestane být přehledem tiketů | Vědomě přijato (rozhodnutí 1). Přehled tiketů nese Jira a `proposals/completed/`. |
| **Push po každém commitu zatíží `doc-index.ps1`** víc větvemi i commity | Nový filtr aktivity (sekce 5) jde protisměrně; ověří to měření proti monorepu. |
| **Konfigurace se rozejde s hookem**, protože seznam se generuje při instalaci | Fallback na zadrátovaný seznam vede vždy k více ochrany. Nový běh instalátoru je součástí `sync-with-monorepo.ps1` při `-Scope Monorepo`. |
| **Heuristika průniku propustí drift** (změna, která rozbije build bez shody projektů) | Přiznaná heuristika; povinná baseline před prvním dispatchem zůstává, a whole-branch review před finishing je druhá síť. |
| **Odstupňovaná verifikace svede k přeskakování testů** i tam, kde je průnik zřejmý | Rozhodnutí je uživatelovo a průnik se vypisuje jmenovitě, takže je viditelné, co se přeskakuje. |
| **Souběžná integrace dvou aktérů** zacyklí smyčku fetch–merge–push | Strop dvě kola, pak STOP a report. |
| **Upstream drift** rozbije kotvu finishing fragmentu | Existující detektor: miss `ANCHOR-BEFORE` shodí revendor, což je zamýšlené chování, ne chyba k obejití. |
