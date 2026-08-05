# Návrh: Model tiketových větví, integrace a disciplína workspace

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
  v monorepu;
- **práce na více tiketech v opakovaně používaném workspace má uzavřenou
  smyčku** — vstupní brána, parkování a dokončení — s jasně rozdělenou
  odpovědností mezi uživatele a agenta.

Druhá polovina cíle vznikla z rozhodnutí **nezavádět pool workspaců**. Volbu
a zakládání workspace vlastní uživatel; workspace se používá opakovaně a nese
zbytky předchozí práce. Návrh proto neřeší, kdo workspace vyrobí, ale **co se
stane, když uživatel v takovém workspace řekne „budeme implementovat
UMS-5678"**.

Automatizovaný pool (přejmenovávané sloty, manifest, akvizice a uvolnění
skillem) byl zvážen a **zamítnut** — jeho pasti (zámky adresářů při
přejmenování, `MB_ROOT` přeskakující mezi dvěma repozitáři, manifest jako
externí stav mimo repozitáře) plynuly právě z toho, že životní cyklus řídil
agent zevnitř sezení. Analýza je zaznamenaná v části „Zamítnuté varianty".

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
„Future worktree pool (interface only — not implemented)" s manifestem
a mechanikou, kterou nikdo nepostaví — izolace se řeší volbou workspace
uživatelem a větví na místě.

**10. Vrstva odkazuje na cestu ledgeru, která už neexistuje.** Upstream
zavedl adresář per plán (`.superpowers/sdd/<plan-basename>/`) právě proto, že
plochá cesta způsobovala reálnou kontaminaci — `RELEASE-NOTES.md` to popisuje
jako *„observed in the wild, with multiple contamination rounds"*. Vrstva ale
na plochou `.superpowers/sdd/progress.md` odkazuje dodnes: v PostCompact hooku
[settings.json](../../../ums/.claude/settings.json), v [tech.md](../../tech.md)
a v pěti `mb-*` skillech. **Po kompaktaci uprostřed plánu tedy vrstva posílá
agenta na neexistující soubor** a ztratí kontext progresu.

**11. Kandidáti playbooku mají fixní cestu s přepisovacím pravidlem.**
Kontrakt nechává soubor s cizím slugem na prvním řádku **přepsat** a zdůvodňuje
to tím, že patří práci, která *„already finished or was abandoned"* — což
předpokládá sériovou práci. Při přepínání mezi **živými** tikety v jednom
workspace to pravidlo maže živé důkazy, a ty existují jen tam: harvestová brána
z nich čerpá na konci větve. Je to tatáž chyba, jakou upstream opravil u svého
ledgeru (mrtvé místo 10), jen u souboru, který vlastní UMS.

**12. Limit aktivních položek je zdůvodněný „per clone".** Kontrakt to opírá
o věty *„one active work item per clone, because `context.md` holds one pin"*.
Pin ale drží **každá větev vlastní**, takže text čtený doslova zakazuje začít
tiket B, dokud je aktivní tiket A — přičemž A je aktivní na své vlastní větvi,
což je právě ten zamýšlený postup. Mechanika je správná (lokální sken čte
pracovní strom, tedy aktuální větev); špatné je zdůvodnění a s ním i chování
brány.

**13. Chybí operace „odložit".** Vrstva umí práci **dokončit** (finishing +
harvest) a **opustit** (`mb-abort`). Nemá nic pro „nechám to rozdělané a vrátím
se" — a to je přesně to, co opakovaně používaný workspace potřebuje, protože
prokládání tiketů je jeho hlavní režim.

**14. `.claude/` je ignorovaný, takže tam konfigurace nemůže být.** Upstream
`.gitignore` ignoruje **každý** adresář `.claude/` (vede to i
[tech.md](../../tech.md) jako past prostředí) a [ums/.gitignore](../../../ums/.gitignore)
to neguje jen pro `ums/`. Konfigurační soubor v kořenovém `.claude/` by tedy byl
netrackovaný a nepřenosný — přesně opak toho, k čemu má sloužit. Vada, kterou
si do návrhu zavlekla jeho předchozí revize.

**15. Skilly nesou hodnoty konkrétního repozitáře.** `origin/develop`,
`release/*` a v předchozí revizi i seznam sdílených kořenů byly zapsané přímo
ve skillech a skriptech, takže vrstva mimo UMS nefunguje správně, aniž by to
kdokoli poznal — degraduje tiše (mrtvé místo 1 je jediný případ, kdy to spadne
hlasitě). Do téže třídy patří i Jira konvence zapsané ve skillech (stavy
`Design Review` a `Test`, pole `Flagged`, `customfield_11248`); ty tento návrh
neřeší, ale nový konfigurační soubor je jejich přirozený budoucí domov.

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
| 8 | **„Volný workspace" je derivovaný stav gitu**, ne záznam v evidenci | Tři příkazy nemohou zastarat ani lhát; ruší potřebu manifestu |
| 9 | Hranice odpovědnosti: **agent nikdy nezničí nic, co nejde získat z `origin`** | Jediné pravidlo, ze kterého jde odvodit celou dělbu; totožné s dvouúrovňovou push policy |
| 10 | Limit aktivních položek je **per větev**, a zastaví jen práci neobnovitelnou z `origin` | Commitnutá a pushnutá práce jiného tiketu **je** zaparkovaná; nejčastější případ musí být bez ptaní (mrtvé místo 12) |
| 11 | Nová operace **`mb-park`**; kandidáti playbooku dostanou cestu per slug a park je commitne na větev | Doplňuje chybějící třetí konec životního cyklu (mrtvé místo 13) a činí zaparkovanou práci **celou** obnovitelnou z `origin` (mrtvé místo 11) |
| 12 | Pool workspaců se **nezavádí**; volbu a zakládání workspace vlastní uživatel | Pasti poolu plynuly z toho, že životní cyklus řídil agent zevnitř sezení — viz níže |
| 13 | **Žádná hodnota konkrétního repozitáře v těle skillu**; vše v `<CTX_DIR>/ums-repo.json` | Vrstva je redistribuovatelná a mimo UMS by tiše degradovala (mrtvé místo 15) |
| 14 | Konfigurace jde do **kořenové Memory Bank**, ne do `.claude/` | `.claude/` je upstreamem ignorovaný, soubor by byl netrackovaný (mrtvé místo 14) |
| 15 | Heuristika průniku zná jen **mechaniku** (nejbližší předek s projektovým markerem + vždy-protínající vzory); hodnoty dodá konfigurace | Odstraňuje z pravidla znalost .NET i UMS, aniž by se pravidlo oslabilo |
| 16 | Naplnění konfigurace detekuje **`mb-init`**, první verze bez schvalování, každá další změna se schvaluje | Přesný precedens: totéž a ze stejného důvodu už kontrakt povoluje pro první `playbook.md` |

Zamítnuté varianty:

- **Automatizovaný pool workspaců** (přejmenovávané sloty, manifest, akvizice
  a uvolnění skillem). Zamítnuto po analýze sedmi pastí, z nichž čtyři plynou
  z toho, že životní cyklus řídí agent zevnitř sezení: **(a)** `CLAUDE_PROJECT_DIR`
  je fixní od začátku sezení a `MB_ROOT` je `git rev-parse --show-toplevel`, takže
  by přeskakoval mezi dvěma repozitáři podle pracovního adresáře jednotlivého
  volání — a náhradním cílem je základní workspace checkoutnutý na bázi, tedy ten
  jediný, který má zůstat čistý; **(b)** Windows zamkne adresář, který je
  pracovním adresářem běžícího procesu, takže sezení nemůže při uvolnění
  přejmenovat samo sebe; **(c)** manifest by musel ležet mimo všechny repozitáře
  (u klonů není sdílená `.git`), tedy mimo `CLAUDE_PROJECT_DIR`, s atomicitou
  a zastaráváním; **(d)** nic by nebránilo dvěma sezením v jednom slotu.
  Zbylé tři pasti (chybějící hooky v čerstvém klonu, `--reference` bez
  `--dissociate`, zbytky po předchozím tiketu) jsou řešitelné a **tento návrh je
  řeší** jako součást vstupní brány, protože platí i pro workspace vyrobený
  uživatelem.
- **Worktree pool místo klonů.** Měřením zamítnuto: klon monorepa má 25 GB,
  z toho `.git` jen 4,1 GB (841 MiB packy + 3,3 GB LFS). Pracovní strom a build
  output, tedy ~21 GB, potřebuje linked worktree úplně stejně — úspora by byla
  16 %, ne většina. Zdůvodnění zákazu worktrees v kontraktu („worktree creation
  is expensive") tedy neplatí ani obráceně.

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
(generování seznamu); `doc-index.ps1` (konfigurace + filtr aktivity); **nový
skill `mb-park`**; rozšíření `mb-init` (detekce konfigurace a režim obnovy)
a `mb-state` (orákulum způsobilosti workspace);
`mb-architect-review`, `mb-jira-update`, `mb-harvest`, `mb-git-commit`; oprava
ploché cesty ledgeru v [settings.json](../../../ums/.claude/settings.json)
a v pěti `mb-*` skillech; přesun kandidátů playbooku na cestu per slug;
[CLAUDE.md](../../../CLAUDE.md) a [ums/CLAUDE.md.sample](../../../ums/CLAUDE.md.sample);
Memory Bank dokumenty tohoto repa; čtyři existující testovací sady plus jedna
nová.

**Mimo rozsah:** automatizovaný pool workspaců a adopce tří existujících ad-hoc
klonů; zakládání workspace (vlastní uživatel — návrh jen ověřuje způsobilost);
mazání zbylých tiketových větví na `origin`; branch permissions na serveru;
oprava tří `.cmd` skriptů se zadrátovaným `_datasys`; **přesun Jira konvencí do
konfigurace** (stavy, `Flagged`, `customfield_11248` — pojmenované jako budoucí
obsah téhož souboru, mrtvé místo 15).

## Technický návrh

### 1. Model větví a integrace

**Založení.** `git fetch origin`, pak `git switch -c <TICKET>-<kebab-slug>
<baseRef>` — **vždy s explicitním výchozím bodem**, nikdy implicitní
tvar. Žádná lokální báze, tedy ani dnešní „fetch + fast-forward lokální báze".
Jméno větve je `<TICKET>-<kebab-slug>` v ASCII; existující větve s diakritikou
se nepřejmenovávají. Bez tiketu se použije `<kebab-slug>` sám.

Implicitní tvar je totiž nejpravděpodobnější destruktivní chyba celého modelu:
`git switch -c UMS-5678` spuštěné na větvi `UMS-1234` založí novou větev z 1234
a vtáhne do historie 5678 její pin v `context.md` i její aktivní pár. Proto
k tomu patří **mechanická postkondice**, která tu chybu chytí strukturálně
místo disciplínou — hned po založení musí platit:

- `proposals/active/` je prázdný nebo chybí;
- `context.md` je ve stavu `IDLE`.

Když neplatí, větev vznikla z něčeho jiného: **STOP**, větev smazat, zopakovat.

**Báze nikdy nesmí nést `ACTIVE` stav.** Věta „nová větev z báze = čistý štít"
platí jen za tohoto invariantu. Zaručuje ho harvest před integrací (Option 1
harvestuje vždy), ale kontroluje ho `mb-state` — kdyby jednou selhal, každá
další větev zdědí cizí pin.

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
2. `git merge <baseRef>` (base sync dle sekce 2)
3. zelená verifikace
4. agent připraví `! UMS_ALLOW_SHARED_PUSH=1 git push origin HEAD:<baseBranch>`
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

**Sekvence na každé hranici:** `fetch` → `merge <baseRef>` → posouzení
průniku (níže) → případná verifikace → commit → push.

**Posouzení průniku je mechanické.** Obě množiny cest se počítají **po `fetch`,
ale před `merge`**, ze stejného merge-base — tím je definice nezávislá na tom, co
si kdo zapamatoval před fetchem:

```
MB=$(git merge-base HEAD <baseRef>)
prichozi=$(git diff --name-only $MB..<baseRef>)   # co merge přinese
vlastni=$(git diff --name-only  $MB..HEAD)                # co větev změnila
```

Ve fázi návrhu, kdy ještě není co změněno, roli **vlastní** množiny hrají cílové
oblasti pojmenované v návrhu.

Porovnání na úrovni jednotlivých souborů je příliš úzké — změna ve sdíleném
projektu, který ten váš referencuje, je drift bez shody souborů. Pravidlo je
proto dvoustupňové a **neobsahuje žádnou znalost konkrétního ekosystému ani
repozitáře**:

1. Každá cesta se namapuje na **nejbližší nadřazený adresář obsahující shodu
   s `projectMarkers`** (konfigurace, sekce 3) a průnik se hledá na této úrovni.
   Cesta bez takového předka zůstává sama sebou.
2. Cesta odpovídající některému vzoru ze `sharedRoots` se považuje za
   **vždy protínající**.

Skill tedy zná jen tuhle mechaniku; co je projekt a co je sdílený kořen, říká
konfigurace repozitáře. **Je to heuristika**, ne důkaz — pojmenovaná tak
i v kontraktu.

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
nikdy `merge -X ours` na celý merge. Je to stav **této větve**, ne fakt
o produktu. U `proposals/active/` konflikt nevzniká (jiný slug = jiné soubory);
konflikt na **témže** slugu je kolize dvou aktérů, tedy STOP.

### 3. Konfigurace repozitáře

**Žádná hodnota specifická pro konkrétní repozitář nesmí být v těle skillu.**
Vrstva je redistribuovatelná a `UMS` je jen jeden z jejích cílů, takže báze,
chráněné větve, vzor kódu tiketu ani sdílené kořeny nesmí být zadrátované
v Markdownu skillu. Všechny žijí v jednom souboru per repozitář.

**Umístění: `<CTX_DIR>/ums-repo.json`**, tedy v kořenové Memory Bank — ne
v `.claude/`. Důvod je mechanický: upstream `.gitignore` ignoruje **každý**
adresář `.claude/` a `ums/.gitignore` to neguje pouze pro `ums/`, takže soubor
v kořenovém `.claude/` by byl v tomto forku netrackovaný, a tedy nepřenosný
(mrtvé místo 14). `CTX_DIR` je naopak podle kontraktu garantovaně existující
(Root Memory Bank Gate) i trackovaný a kontrakt o něm říká, že drží `context.md`
plus to, co orchestrovaný strom potřebuje.

```json
{
  "baseRef": "origin/develop",
  "protectedBranches": ["develop", "main", "master", "release/*", "Branches/*"],
  "ticketPattern": "^[A-Z][A-Z0-9]+-[0-9]+",
  "projectMarkers": ["*.csproj", "*.vcxproj", "*.sln", "package.json"],
  "sharedRoots": ["Common/", "Lib/", "SharedAssemblyInfo.xml", "*.sln", "Build.proj"]
}
```

| Klíč | K čemu | Konzument |
|---|---|---|
| `baseRef` | integrační báze repozitáře | `doc-index.ps1`, zakládání větve, base sync, integrace |
| `protectedBranches` | co agent nikdy nepushne | `pre-push` (přes generovaný seznam), `guard-git-push.mjs` |
| `ticketPattern` | co je tiketová větev a jak z ní přečíst kód tiketu | `mb-state` (výpis zaparkované práce), vstupní brána, `mb-architect-review` |
| `projectMarkers` | jak namapovat cestu na vlastnící projekt | heuristika průniku (sekce 2) |
| `sharedRoots` | co se vždy považuje za protínající | heuristika průniku (sekce 2) |

`ticketPattern` se do návrhu vrací — v předchozí revizi jsem ho odstranil jako
nekonzumovaný, ale disciplína workspace mu dala tři konzumenty.

**Chybějící soubor není chyba, ale degradace míří k bezpečnější straně.**
`baseRef` padne na `origin/develop`, ochrana na dnešní zadrátovaný seznam
(tedy k *více* ochrany, nikdy k méně). U heuristiky průniku je bezpečnější
strana ta štědřejší: bez `sharedRoots` a `projectMarkers` se verifikace
**nabídne při každém neprázdném příchozím diffu**, protože bez znalosti
topologie repozitáře nelze tvrdit, že drift nemůže zasáhnout do práce.

V tomto forku bude `baseRef` rovno `origin/ums-memory-bank`, čímž mizí spadnutí
z mrtvého místa 1.

**Naplnění souboru má podporu, ne ruční sepisování.** Detekci a návrh obsahu
dělá `mb-init`, který už dnes stejnou věc umí pro `playbook.md` — z build
souborů detekuje příkazy a první verzi napíše bez schvalování, protože
detekované hodnoty jsou ověřitelné proti build souborům samotným. Sdílené kořeny
a projektové markery patří do téže třídy: derivují se z topologie repozitáře
(kde leží solution soubory, které projekty referencuje víc než jeden jiný, kde
jsou sdílené `props`/`targets`), takže platí tatáž výjimka. **Každá pozdější
změna už schválení vyžaduje** — přesně jako u `playbook.md`, a ze stejného
důvodu: topologie se mění a jen člověk ví, jestli je nová hodnota záměr.

`mb-init` proto dostane i **režim obnovy** nad existujícím souborem: detekuje
znovu, rozdíl předloží a zapíše až po schválení.

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

### 6. Disciplína workspace: dělba odpovědnosti a uzavřená smyčka

Workspace zakládá a vybírá **uživatel**. Používá se opakovaně, takže při vstupu
do nové práce v něm mohou ležet zbytky té předchozí. Tato sekce definuje, kdo
za co odpovídá a jak smyčka začíná a končí.

#### 6.1 Jediná hranice odpovědnosti

**Agent nikdy nesmí zničit nic, co nejde získat zpátky z `origin`.** Z toho se
odvodí všechno ostatní:

- **Obnovitelné z `origin`** — pushnuté větve, build output, ledger plánu, jehož
  návrh je už archivovaný. S tím smí agent hýbat sám; chyba nic nestojí.
- **Neobnovitelné** — necommitnuté změny, položky ve stashi, nepushnuté commity,
  nasbíraní kandidáti playbooku. To agent **nikdy nemaže**: buď zachová, nebo
  zastaví a zeptá se.

Rozhodnutí o neobnovitelných zbytcích patří **uživateli** (jen on ví, jestli je
to smetí nebo cennost), **detekce a předložení agentovi** (uživatel si nesmí
muset pamatovat, že má něco zkontrolovat), a všechno mechanicky ověřitelné je
čistě na agentovi bez otázek. Je to tatáž hranice, jakou vrstva už používá
u pushe: vlastní věc si agent udělá sám, o nevratné se ptá.

#### 6.2 „Volný workspace" je derivovaný stav, ne evidence

Workspace je bez zbytků, právě když jsou všechny tři výstupy prázdné:

```
git status --porcelain              # čistý pracovní strom
git stash list                      # žádný odložený stav
git log --branches --not --remotes  # nic nepushnutého
```

Tím se ruší jakákoli potřeba manifestu — stav se **derivuje z reality**, takže
nemůže zastarat ani lhát. Ignorovaný build output se v `--porcelain` neobjeví,
takže se řeší jen to, co skutečně někoho zajímá.

Zbytky se dělí na dvě třídy a to rozdělení je pro bránu nosné:

- **V cestě** — špinavý pracovní strom a stash. Blokují bezpečné přepnutí větve,
  takže musí být vyřešené.
- **Pouze přítomné** — nepushnuté commity na *jiných* větvích a kandidáti jiných
  slugů. Neblokují nic; jen se ohlásí a agent na ně nesmí sáhnout.

#### 6.3 Vstupní brána

**Fáze 0 — způsobilost workspace.** Vlastní agent, fail-closed, bez otázek:
`MB_ROOT` a existence `memory-bank/`; konfigurace a `baseRef`; **kontrola git
hooků** (`git rev-parse --git-path hooks/pre-push` a case-sensitive marker
`UMS pre-push guard`; při chybění `install-git-hooks.ps1` s fail-closed
vyhodnocením exit kódu); `core.hooksPath` nenastavený nebo relativní;
`git fetch origin`.

Kontrola hooků je v tomto modelu **nejdůležitější agentí povinnost**, protože
workspace zakládá uživatel a git hooky se s klonem nepřenášejí — bez ní se
první tiket v novém workspace rozjede bez publikační záruky.

**Fáze 1 — inventura zbytků.** Tři příkazy z 6.2 plus sken kandidátů,
roztříděné podle obnovitelnosti a podle toho, co je v cestě.

**Fáze 2 — právě jedno rozhodnutí uživatele**, a jen když je v cestě něco
neobnovitelného: **zaparkovat** (doporučeno, jde-li o soudržnou práci) nebo
**zahodit** (s vypsaným potvrzením, jako discard ve finishing). Možnost „nechat
ležet" v témže workspace neexistuje — špinavý strom bezpečné přepnutí
neumožňuje; kdo chce zbytky opravdu nechat, musí si vybrat jiný workspace, a to
mu agent řekne.

**Fáze 3 — určení záměru:**

| Zjištění | Výsledek |
|---|---|
| Lokální větev pro tiket existuje | **resume** — přepnout, ověřit postkondice, ohlásit stav z checkboxů plánu a ledgeru |
| Tiket je aktivní na cizí větvi na `origin` | **STOP** — kolizní kontrola (sekce 1 a 5) |
| V `proposals/next/` čeká předběžný návrh | aktivace dle kontraktu |
| Nic z toho | **nová větev** z `<baseRef>` s postkondicí (sekce 1) |

**Fáze 4** — zápis pinu a vstup do workflow.

**Nejčastější případ musí být bez ptaní.** Strom čistý, stojíte na `UMS-1234`,
`context.md` je `ACTIVE` na jejím slugu: dnešní limit aktivních prací by to
zastavil, ale ta práce je commitnutá a pushnutá, tedy **už zaparkovaná**. Brána
se proto zastaví jen tehdy, když aktivní slug na **aktuální větvi** není
obnovitelný z `origin`; jinak jen ohlásí „UMS-1234 zůstává zaparkovaný na své
větvi" a pokračuje.

#### 6.4 Přepínání a nová operace `mb-park`

**Nebezpečný případ přepnutí není to zablokované, ale tichý přenos.** Git nese
necommitnuté změny s sebou, když je soubor na cílové větvi shodný — a pin
napsaný pro tiket A, který takhle přijede na větev B, je stav, ze kterého se
člověk nevymotá. Pravidlo: `git status --porcelain` prázdný, **žádné přepínání
přes `git stash`, žádný auto-stash** — doslova tatáž formulace, jakou
`mb-architect-review` už používá při branch syncu, aby vrstva neměla dvě různá
pravidla na totéž. Přepínat se smí **jen na hranicích fází**, nikdy uprostřed
tasku.

Protože se pushuje po každém commitu, je „čisto a zapushováno" normální stav,
takže to pravidlo prakticky nic nestojí.

**`mb-park`** doplňuje chybějící třetí konec životního cyklu (dokončit /
opustit / **odložit**): commitnout vše (`mb-git-commit`), pushnout, ohlásit
zbytky, a **nechat větev checkoutnutou** — žádné zbytečné přepnutí znamená
žádný zbytečný rebuild. `context.md` zůstává `ACTIVE` na zaparkované větvi;
proto je per-branch semantika pinu nosná.

**Kandidáti playbooku dostanou cestu per slug**
(`.superpowers/playbook-candidates/<slug>.md`) a `mb-park` je přidá na tiketovou
větev (`git add -f`). Tím je zaparkovaná práce **celá** obnovitelná z `origin`
včetně důkazů, takže definice volného workspace v 6.2 platí bez výjimky
a v tiketu lze pokračovat v jakémkoli workspace. Harvestová brána je přečte,
schválené přeloží do `playbook.md` a soubor při archivaci smaže. Přepisovací
semantika kontraktu zůstává **uvnitř** slugu; mizí jen ztráta napříč tikety.

Je to vědomá výjimka z pravidla „scratch je git-ignored" a platí jen pro tento
jeden soubor. Jazykový kontrakt ji unese: kandidáti jsou AI-facing, tedy
anglicky, a do češtiny se překládají teprve při zápisu do `playbook.md`.

**Životní cyklus se spouští na vlastní větvi tiketu.** Harvest, `mb-abort`
i finalizace Jiry — jinak se archivuje cizí pár.

### 7. Co se s větví nepřepne

Memory Bank v repozitáři je výhoda i nevýhoda a stojí za to ji pojmenovat.
**Výhoda: `git checkout` JE přepnutí kontextu** — tiketová větev je úplná,
sebeopisná jednotka práce (návrh, plán, pin i kód v jednom commit grafu), takže
není co ztratit ani co srovnávat. **Nevýhoda je zrcadlová: co není v gitu, se
nepřepne.**

| Co | Přepne se s větví? | Důsledek |
|---|---|---|
| `context.md`, `proposals/` | **ano** (trackované) | výhoda: checkout = přepnutí kontextu |
| `.superpowers/sdd/<plan_slug>/` ledger | ne, ale je **per plán** | bezpečné; návrat k tiketu najde ledger, kde byl. Progres je navíc uložený dvojmo — checkboxy plánu jsou trackované, takže ledger je komfort, ne jediný záznam |
| `.superpowers/playbook-candidates/` | ne | řešeno cestou per slug a commitem při parkování (6.4) |
| build output (`obj/`, `bin/`, `DistOut/`) | ne | **rebuild na každé přepnutí** — přijatá cena za absenci poolu; proto se přepíná jen na hranicích fází |
| git hooky | ne (leží mimo pracovní strom) | v pořádku; instalace se ověřuje ve fázi 0 |

**Jedno sezení na workspace.** Dvě sezení v jednom klonu si perou o HEAD a git
operace uprostřed buildu ho rozbije. Práce na více tiketech je proto
**prokládaná, ne paralelní** — „tiket A čeká na review, přepnu na B". Skutečný
paralelismus vyžaduje víc workspaců, a ty vyrábí uživatel.

**Vidět odloženou práci** je nová potřeba, kterou přináší prokládání: `mb-state`
vypíše lokální tiketové větve s jejich pinem a datem posledního commitu (jeden
`git show <branch>:memory-bank/context.md` na větev), aby otázka „co mám
rozpracovaného?" měla odpověď.

### 8. Tabulka odpovědností

| Věc | Detekuje | Rozhoduje | Provádí | Fail mode |
|---|---|---|---|---|
| Git hooky ve workspace | agent | — | agent | fail-closed, bez hooku se nepracuje |
| Konfigurace, `baseRef` | agent | — | agent | fallback na default |
| Špinavý strom, stash | agent | **uživatel** | agent dle volby | STOP, nikdy auto-stash |
| Nepushnuté commity na jiných větvích | agent | **uživatel** | nikdo (jen report) | agent nemaže |
| Kandidáti jiných slugů | agent | **uživatel** | nikdo | agent nepřepisuje |
| Build output | — | — | nikdo | nikdy `git clean` |
| Lokální větev obsažená v bázi | agent | — | agent smí smazat | — |
| Volba a založení workspace | — | **uživatel** | uživatel | agent jen ověří způsobilost |
| Založení tiketové větve | agent | — | agent | postkondice `active/` + `IDLE` |
| Push do báze | agent připraví | **uživatel** | uživatel | `pre-push` hook |

## Dopady

**Kontrakt v2.5 → 2.6.** Mění se *Publication Contract* (publikační body →
pravidlo push-po-commitu, refspecový příkaz, integrační sekvence se stropem dvou
kol), *Cross-Branch Visibility* (zakládání z `<baseRef>` bez lokální
báze), *Architect Review Gate* (jméno větve, merge asymetrie), *Fail-Closed
Behavior* (nemožný base sync, strop integračních kol), *Active Work Item*
(limit **per větev** a jen pro práci neobnovitelnou z `origin`, plus postkondice
založení) a *Playbook Contract* (kandidáti na cestě per slug, commit při
parkování, brána je čte pro aktuální slug). Přidávají se sekce **Base Sync
& Drift Detection**, **Repository Configuration** a **Workspace Discipline**
(hranice odpovědnosti, definice volného workspace, vstupní brána, parkování).
V *Scope Locku* se upraví výčet scratch souborů o novou cestu kandidátů a jednu
pojmenovanou výjimku, že právě tento soubor se při parkování commituje.
Maže se podsekce „Future worktree pool (interface only — not implemented)";
zákaz worktrees zůstává beze změny.

**Tři overlaye.** `brainstorming` — zakládání větve z `<baseRef>`.
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
| `mb-state` | **rozšíření na read-only orákulum způsobilosti workspace**: je volný (tři příkazy z 6.2), co je tu zaparkovaného (pin a datum na každou lokální tiketovou větev), co je v cestě, vzdálenost od báze (`git rev-list --count HEAD..<baseRef>`), kontrola invariantu `IDLE` na bázi. Zůstává read-only — jednající skilly jsou oddělené |
| **`mb-park`** (nový) | commit, push, ohlášení zbytků, commit kandidátů (`git add -f`), větev zůstává checkoutnutá; `context.md` zůstává `ACTIVE` |
| `mb-init` | detekce `ums-repo.json` z topologie repozitáře (první verze bez schvalování, jako `playbook.md`) a **režim obnovy** nad existujícím souborem s předložením rozdílu |
| `mb-harvest` | čte kandidáty z cesty per slug (i commitnuté) a soubor při archivaci maže |
| `mb-git-commit` | zůstává „nikdy nepushuje"; formulovat tak, aby to nekolidovalo s pravidlem push-po-commitu (pushuje volající) |
| [settings.json](../../../ums/.claude/settings.json) | PostCompact hook: opravit plochou `.superpowers/sdd/progress.md` na cestu per plán (mrtvé místo 10) |
| pět `mb-*` skillů | tatáž oprava ploché cesty ledgeru (`mb-act`, `mb-git-commit`, `mb-git-message`, `mb-jira-update` a další nález greppem) |

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

`mb-park` a rozšířený `mb-state` zůstávají **čistě instrukční Markdown** —
kontroly z 6.2 jsou obyčejné git příkazy v těle skillu, takže nový spustitelný
kód nevzniká a testovatelný povrch se nezvětšuje. Jediná nová sada je tedy ta
konfigurační.

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
| **Rebuild na každé přepnutí** mezi tikety v jednom workspace | Vědomě přijatá cena za absenci poolu. Zmírňuje ji pravidlo přepínat jen na hranicích fází a to, že uživatel může pro paralelní práci použít druhý workspace. |
| **Dvě sezení v jednom workspace** si perou o HEAD | Pravidlo „jedno sezení na workspace" je konvence, kterou nemá co vynutit; `mb-state` ale nesoulad větve a pinu ohlásí, takže se to projeví hned, ne u pushe. |
| **Uživatel obejde vstupní bránu** a začne pracovat bez ověření hooků | Nejde zabránit. Zmírnění: kontrola je fail-closed a levná, a `pre-push` chybí jen v čerstvém klonu — v opakovaně používaném workspace je už nainstalovaný. |
| **`git add -f` na kandidáty** je výjimka z pravidla „scratch je git-ignored" a může se rozšířit | Výjimka je pojmenovaná, platí pro jeden soubor a soubor se při archivaci maže, takže se v repozitáři nekumuluje. |
| **Heuristika „obnovitelné z `origin`" selže**, když je `origin` nedostupný | Fáze 0 začíná `git fetch origin`; jeho selhání je STOP, protože bez čerstvé znalosti `origin` nelze o obnovitelnosti rozhodnout. |
| **Detekovaná konfigurace je špatná nebo zastará** (repozitář se přestrukturuje, `sharedRoots` už neodpovídají) | Režim obnovy `mb-init` předloží rozdíl ke schválení; a degradace míří ke štědřejší nabídce verifikace, takže špatná konfigurace vede k nadbytečným buildům, ne k propuštěnému driftu. |
| **Konfigurace se rozšíří v nekontrolovaný registr nastavení** | Do souboru patří jen to, co má **jmenovaného konzumenta** (tabulka v sekci 3); klíč bez konzumenta se nezavádí — v předchozí revizi byl takový klíč z návrhu odstraněn. |

## Odchylky od finálního stavu

Dvě tvrzení tohoto návrhu byla během implementace — po whole-branch review —
nahrazena a v odevzdaném kontraktu (verze 2.6) už neplatí. Návrh se kvůli tomu
nepřepisuje: zůstává záznamem toho, jak se rozhodovalo. Tento seznam je jeho
oprava, a platí to, co říká kontrakt.

1. **Ověření dosažitelnosti po integraci** — sekce 1, krok 6 integrační sekvence,
   předepisuje `git branch -r --contains <sha>`. Nahrazeno
   `git merge-base --is-ancestor <sha> <baseRef>` (nenulový exit = commit není na
   bázi). Publikační pravidlo totiž týž commit už pushlo na tiketovou větev, takže
   `--contains` ho na `origin` najde i tehdy, když na bázi vůbec není — kontrola by
   procházela vždy a neověřovala nic. Kontrakt v sekci Publication Contract,
   podsekci o integraci, proto výslovně říká, že samotné `git branch -r --contains`
   tady nestačí.

2. **Požadavek na `core.hooksPath` ve fázi 0 vstupní brány** — sekce 6.3 vyžaduje
   hodnotu „nenastavenou nebo relativní". Zrušeno: **nastavený** `core.hooksPath`
   (i globální, běžný u husky nebo pre-commit) není obcházení. Kontrola hooku se
   resolvuje přes `git rev-parse --git-path hooks/pre-push`, které tuto hodnotu
   respektuje, instalátor instaluje právě tam a hook tam živě ověří. Absolutní
   hodnota je proto varování o **rozsahu** (adresář je společný s jinými
   repozitáři), provenienci řeší kontrola značky `UMS pre-push guard` a fail-closed
   zůstává jen chybějící nebo neoznačený hook. Kontrakt to takto uvádí ve vstupní
   bráně (sekce Workspace Discipline) i v sekci Publication Contract.
