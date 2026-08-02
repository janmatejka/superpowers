# Návrh: Dokumentový model Memory Bank — jádro, playbook a sběr zkušeností

- **Jira:** (žádný tiket)
- **Target MB:** memory-bank/
- **Plán:** [plan_dokumentovy_model_mb.md](plan_dokumentovy_model_mb.md)
- **Vytvořeno:** 2026-08-02

## Cíl

Zmenšit počet druhů trvalých dokumentů Memory Bank, dát preskriptivnímu obsahu
(postupy, jak se projekt staví, testuje a mění) vlastní dokument s vlastním
režimem zápisu, a hlavně ho **zapojit** — dnes takový obsah existuje, ale
nevede k němu žádná cesta z místa, kde se rozhoduje. Součástí je i sběr
zkušeností za běhu práce a jejich persistence při harvestu, aby znalost
nezanikala s koncem sezení.

## Východiska (měřeno na monorepu UMS, 80 MB adresářů)

Čísla jsou nosná pro celý návrh, proto je zaznamenáváme:

| Dokument | Výskyt | Průměrná délka |
|---|---|---|
| `architecture.md` | 80 (100 %) | 138 řádků |
| `tech.md` | 80 (100 %) | 75 řádků |
| `brief.md` | 79 (99 %) | 32 řádků |
| `product.md` | 74 (93 %) | 37 řádků |
| `tasks.md` | 10 (12,5 %) | 78 řádků |

Z toho plynou tři zjištění:

1. **`brief.md` + `product.md` = 69 řádků ve dvou souborech.** Obsah se
   částečně opakuje (ověřeno na `FaxChange/fsapi`: varianty DLL, drift a
   sdílená distribuce jsou v obou), ani jeden nemá dost hmoty na vlastní
   existenci.
2. **`architecture.md` + `tech.md` takhle nevypadají.** Dvě samostatně vážné
   velikosti a nepřekrývající se osy — struktura kódu vs. build, verze,
   konfigurace a pasti prostředí. Sloučení by ušetřilo jedno rozhodnutí při
   zápisu a zaplatilo se 213řádkovým souborem.
3. **`tasks.md` je preskriptivní, ne seznam úkolů.** Deset z deseti
   existujících souborů obsahuje postupy a pravidla („Postup: Instalace a
   aktualizace DB", „Build & Test Guide", „Opakující se úkoly", „Při změně
   síťových rozhraní MUSÍTE aktualizovat endpoints.md"). Skutečných otevřených
   úkolů je v celém korpusu asi 20 řádků na dvou místech. Ten soubor se
   jmenuje špatně.

Kořenová MB monorepa navíc kanonickou sadu vůbec nedodržuje — nemá `brief.md`,
`product.md` ani `tasks.md`, zato má `solution.md`, `data-flows.md`,
`open-questions.md` a `epics/`. Sada dokumentů se v praxi utváří podle
potřeby, takže kontrakt má předepisovat **jádro plus volnou nástavbu**, ne
uzavřený seznam.

**Proč agent postupy ignoruje.** Není to neposlušnost, je to chybějící spoj:

- `MB Context Reading Rule` v kontraktu jmenuje `brief`, `product`,
  `architecture`, `tech` — `tasks.md` v seznamu není, agent nemá pokyn ho číst.
- SDD task brief vzniká skriptem `task-brief`, který extrahuje pouze text tasku
  z plánu. Implementer — ten, kdo staví a spouští testy — se k MB nedostane
  vůbec.
- CLAUDE.md přitom vyžaduje ověřit baseline před prvním taskem („postav dotčené
  projekty a spusť cílené testy"). Jak se konkrétní projekt staví a testuje,
  stojí přesně v souboru, který nikdo nečte.

## Scope

**V rozsahu:**

- Kontrakt v2.3 — sada dokumentů, role a režim zápisu `playbook.md`, tolerance
  staré podoby, doplnění reading rule, sběrný soubor kandidátů.
- Zapojení playbooku do tří míst: reading rule, SDD dispatch a baseline,
  harvest.
- Pravidlo vlastnictví faktu (jeden fakt, jeden domov), přesun mezi dokumenty
  jako legální operace a rozšíření staleness sweepu na detekci duplicit.
- Sběr kandidátů za běhu a interaktivní gate při harvestu.
- Nový skill `mb-migrate-docs` se skriptem, verifikátorem a testy.
- Převod `memory-bank/` tohoto repozitáře (dogfood).
- Aktualizace `ums/README.md` a `SKILLS_MANIFEST.md`.

**Mimo rozsah:**

- **Migrace 153 souborů v monorepu UMS.** Monorepo je jiný git repozitář —
  tato větev se jich fyzicky dotknout nemůže. Vrstva dodá model, toleranci a
  nástroj; přechod spustí uživatel v monorepu, ve vlastním commitu.
- **Průběžný záznam výsledku (`handoff_<slug>.md`)** — položka 1 z
  [tasks.md](../../tasks.md). Sahá do SDD overlay a přidává další druh souboru;
  navrhne se, až bude tento model usazený.

## Technický návrh

### 1. Sada dokumentů

**Povinné jádro projektové MB:** `brief.md`, `architecture.md`, `tech.md`.

**První-třídní volitelný:** `playbook.md`.

**Volná nástavba:** cokoli dalšího, co MB potřebuje (`data-flows.md`,
`use-cases.md`, `open-questions.md`, …). Sem spadá i `tasks.md`, který ztrácí
normativní status a zůstává obyčejným dokumentem tam, kde se používá.

**Orchestrační kořen (`CTX_DIR`) jádrem vázaný není** — má `context.md` a
navigační dokumenty podle toho, co orchestruje. Tak už dnes reálně vypadá.

`product.md` zaniká jako druh; jeho obsah patří do `brief.md`. Kanonická
struktura sloučeného `brief.md`:

```markdown
# Brief — <název>

## Co to je            (účel, zařazení)
## Klíčové funkce      (nebo Rozsah — podle povahy komponenty)
## Pro koho a hodnota  (uživatel, přínos)
## Rizika              (z pohledu produktu)
## Stav a historie
```

Sekce, pro které není obsah, se vynechávají — nezakládají se prázdné.

### 2. `playbook.md`

Preskriptivní dokument: **jak se s tímto projektem pracuje.** Psaný člověkem a
zkušeností, ne odvozený z kódu. Hranice proti `tech.md` není v tématu, ale
v režimu zápisu:

| | `tech.md` | `playbook.md` |
|---|---|---|
| Povaha | popisuje stav | přikazuje postup |
| Zdroj | kód, konfigurace, build soubory | zkušenost, konvence, rozhodnutí týmu |
| Harvest | přepisuje podle skutečnosti | **mění jen se souhlasem uživatele** |
| Příklad | „staví se MSBuild v143, testy xunit" | „testy pouštěj cíleně přes `--filter`; plná sada trvá 40 minut" |

**Režim zápisu — konzultace před zápisem:** `playbook.md` se nikdy nemění bez
souhlasu uživatele. Agent smí navrhnout cokoli — přidat záznam, opravit
překonaný postup, přeformulovat ho nebo smazat ten, který přestal platit — ale
každou změnu předloží ke schválení dřív, než ji zapíše. Pravidlo váže všechny
zapisovatele, tedy i `mb-sync`. Automatický current-state průchod, kterému
podléhají `brief.md`, `architecture.md` a `tech.md` podle Harvest Contract §3,
se na playbook nevztahuje: jeho obsah nevzniká z kódu, takže se z kódu nedá ani
ověřit — soudit o něm umí jen člověk.

Formát záznamu je volný (nadpis + kroky). Když kandidát nesl evidenci, přenáší
se s ním jednořádkové **Proč:** — důvod je součástí postupu, ne šum.

`mb-init` zakládá `playbook.md` **jen tehdy**, když ve fázi detekce buildu a
závislostí našel konkrétní příkazy; do playbooku jdou příkazy, do `tech.md`
verze a stack. Prázdné stuby se nezakládají — přesně tak `tasks.md` skončil na
12,5 %.

### 3. Vlastnictví faktu a přesuny mezi dokumenty

Harvest Contract §3 dnes zakazuje duplikovat fakt, který už je popsaný, ale
nedává kritérium, podle kterého se pozná, kam fakt patří. Bez kritéria může
každý harvest v dobré víře usoudit, že jeho dokument je ten správný domov — a
duplicita vznikne přesně tím způsobem, kterému má pravidlo bránit. Chybí i
sankce přesunu: pravidlo „popisuj nový stav, nevyprávěj o odstranění" se dá
číst tak, že fakt ze špatného dokumentu nesmíš vyndat.

**Tabulka vlastnictví — jeden fakt, jeden domov:**

| Na jakou otázku fakt odpovídá | Domov |
|---|---|
| K čemu to je, pro koho, jaká je hodnota, v jakém je to stavu | `brief.md` |
| Z jakých částí se to skládá, kdo s kým mluví a jak, jaký vzor to sleduje | `architecture.md` |
| Z čeho a čím to běží — stack, verze, závislosti, konfigurace, build, nasazení | `tech.md` |
| Jak mám udělat X — příkazy, postupy, konvence, pasti | `playbook.md` |

**Rozhodovací test pro spornou dvojici `tech` × `architecture`** — záměrně test,
ne taxonomie, protože taxonomie se dá ohnout:

- Změní se ten fakt, když **vyměním knihovnu nebo verzi a kód nechám**?
  → `tech.md`
- Změní se, když **přepíšu kód a závislosti nechám**? → `architecture.md`
- Změní se v **obou** případech (typicky „workflow engine stojí na Orleans")?
  → patří tam, kde ho čtenář hledá první, a druhý dokument na něj **odkáže**
  relativním odkazem; nikdy ho nezopakuje.

Třetí případ je jádro věci. Duplicita nevzniká u faktů, které jednoznačně patří
někam — vzniká u těch, které patří do obou. Pravidlo „jeden domov, odjinud
odkaz" je jediné, co ten případ řeší systematicky.

**Přesun jako legální operace:** `mb-harvest` a `mb-sync` smí fakt přesunout
mezi dokumenty téže MB. Pořadí je závazné — **nejdřív zapsat do cíle, teprve
pak smazat ze zdroje**. Každý přesun se ohlásí ve výstupu, takže je vidět
v reportu i v diffu commitu. Je to záměrně jen viditelnost, ne mechanická
kontrola: přesun je lokální úprava, kterou u commitu někdo přečte, na rozdíl od
hromadné migrace osmdesáti MB, kde verifikátor smysl má.

**Sweep se třemi výústěními:** povinný staleness sweep (Harvest Contract §3)
dnes hledá symboly z diffu větve napříč dokumenty MB a má jediný závěr. Nově
má tři:

1. zásah popisuje **překonaný** stav → srovnej na současnost;
2. zásah je **existující domov** téhož faktu → nepiš druhou kopii, uprav ji na
   místě;
3. zásah je ve **špatném domově** → přesuň podle tabulky.

Jedním průchodem tak vzniká detekce zastarání i detekce duplicity, bez nového
kroku. `mb-sync` dostane totéž pravidlo — tím se stane cestou, kterou se
stávající duplicity v existujících MB postupně uklidí.

### 4. Tři dráty

1. **MB Context Reading Rule** (kontrakt) — `playbook.md` přibude k dokumentům
   čteným před navrhováním a před psaním plánu; `product.md` z výčtu mizí.
2. **SDD overlay** — orchestrátor přikládá **cestu** k `<PLAN_MB>/playbook.md`
   ke každému dispatchi implementera vedle task briefu, a bere z něj postupy
   pro ověření baseline před prvním taskem. Skript `task-brief` se nemění; je
   vendorovaný a drát vede přes overlay, kde vede všechno ostatní.
3. **Harvest** — po implementaci se ptá, jestli větev vyrobila opakovatelný
   postup, který z kódu nevyčteš (viz gate níže).

### 5. Sběr zkušeností za běhu

**Sběrné místo:** `<MB_ROOT>/.superpowers/playbook-candidates.md`. Gitignorovaný
scratch (spadá pod výjimku scope locku pro `.superpowers/`). První řádek nese
identitu, stejným vzorem jako SDD ledger:

```markdown
# Playbook candidates — work item: <slug>
```

Cizí slug znamená cizí práci — soubor se nechá být a založí se nový. Soubor
přežije kompaktaci i pád sezení, což je celý jeho smysl.

**Kdo zapisuje:**

- **Implementer subagent** — dispatch contract dostane povinnou sekci reportu
  `## Playbook candidates`. Prázdná je legitimní a bude běžná.
- **Orchestrátor** — potvrzené kandidáty z reportu **kopíruje** do sběrného
  souboru, nepřeformulovává je.
- **Sezení mimo SDD** (inline exekuce, ruční práce) — zapisuje přímo, stejný
  formát.

**Formát kandidáta** — tři povinná pole, bez nich se záznam nezapisuje:

```markdown
## <short title>
- **Tried:** <what was attempted>
- **Happened:** <what actually happened — the evidence>
- **Procedure:** <the rule that follows from it>
- **Target MB:** <path>/memory-bank/        (only when harvest spans several MBs)
- **Corrects:** <existing playbook entry>   (when it contradicts an entry already there)
```

Zákaz vymýšlení je zde vynucen **formátem**, ne prosbou: kandidát bez pole
`Happened` je neúplný záznam a nezapisuje se. Rozdíl mezi „projekt se testuje
přes `--filter`" a „spustil jsem plnou sadu, po 40 minutách timeout, s
`--filter` doběhla za 90 s" je přesně to, co odděluje zkušenost od dojmu.

**Jazyk:** sběrný soubor je AI-facing scratch, tedy anglicky (Language
Contract). `playbook.md` je trvalý artefakt, tedy česky — harvest při
persistenci překládá.

### 6. Harvest gate

Je-li sběrný soubor neprázdný a jeho slug odpovídá aktuální položce, harvest
**jednou** předloží uživateli seznam kandidátů s jejich evidencí a nechá
vybrat. Schválené se přeloží a zapíší do `playbook.md` cílové MB — nebo té MB,
kterou určuje pole `Target MB`. Neschválené zmizí se scratchem; harvest ohlásí
jejich počet.

Kandidát s polem `Corrects` se předkládá **vedle existujícího záznamu**, kterému
odporuje, a uživatel rozhodne, jestli ho nahradit, nechat oba, nebo kandidáta
zahodit. Tady se projevuje uvolněný režim zápisu: agent smí navrhnout i přepis
nebo smazání, ne jen přírůstek — jen to nesmí udělat sám.

Toto je **jediné místo, kde `mb-harvest` přestává být autonomní**; ve zbytku
zůstává beze změny. Prázdný nebo cizí sběrný soubor gate přeskočí bez dotazu —
nenaléhá se.

### 7. Tolerance staré podoby

Trvalá, stejně jako grandfather klauzule u `proposal_` názvů:

- **Čtení:** existuje-li `product.md`, přečti ho také. Chybí-li `playbook.md`
  a existuje `tasks.md`, ber pro čtení `tasks.md`.
- **Zápis postupů:** do `playbook.md`, pokud existuje; jinak do `tasks.md`,
  pokud existuje; jinak se `playbook.md` založí.
- Žádná MB není nucena migrovat, aby zůstala platná.

### 8. Skill `mb-migrate-docs`

Spustitelný v libovolném repozitáři, opakovaně, idempotentně. Dvě fáze.

**Mechanická fáze** (`scripts/migrate-mb-docs.ps1`, deterministická, výchozí je
náhled bez zápisu):

- `brief.md` ← přilepí `## Produktový pohled` a tělo `product.md` s nadpisy
  posunutými o úroveň níž; `git rm product.md`.
- Chybí-li `brief.md` a `product.md` existuje → prosté přejmenování.
- `tasks.md` → `git mv playbook.md`. Existuje-li `playbook.md` už teď, konflikt
  se **nahlásí a přeskočí** — rozhoduje člověk.
- Přepis relativních odkazů `](product.md)` → `](brief.md)` a `](tasks.md)` →
  `](playbook.md)` napříč MB dokumenty repozitáře.
- MB bez `product.md` i bez `tasks.md` je hotová — přeskočí se a započítá do
  hlášení. Odtud plyne idempotence i opakovatelnost napříč repy.

Skript **necommituje** (staging přes `git mv`/`git rm` ano); na konci skill
nabídne `mb-git-commit`, stejně jako to dělá harvest.

**Agentní fáze** — jeden dispatch na MB, nejlevnější tier, a **jen pro ty MB,
kde mechanická fáze skutečně slučovala** (samotné přejmenování `tasks.md` →
`playbook.md` úklid prózy nepotřebuje). Vstupem je sloučený `brief.md`. Agent
smí **jen mazat celé řádky a měnit jejich pořadí**; nesmí napsat ani jednu
novou větu. Nadpisy vytvořila mechanická fáze, takže agent nic autorovat
nepotřebuje.

**Verifikátor (`-Mode Verify`)** — mechanická kontrola, ne slib:

- Každý neprázdný řádek výstupu (po ořezu koncových mezer) se musí doslova
  vyskytovat v množině neprázdných řádků vstupu.
- Počet řádků výstupu ≤ počet řádků vstupu (fáze je mazací).
- Výstup není prázdný a obsahuje původní `#` nadpis.
- Porušení kterékoli podmínky = výsledek se zahodí, obnoví se mechanická verze,
  MB se nahlásí jako neuklizená.
- Odmazání více než poloviny řádků projde, ale hlásí se jako **VAROVÁNÍ**
  k lidské kontrole.

Cenou za mazací režim je, že dvě polovičně překrývající se věty agent nesloučí
do jedné — smaže tu slabší celou. To je vědomý obchod: záruka nesmí stát na
kázni promptu, ale na kontrole, která ji umí odmítnout. Prózu srovná nejbližší
harvest, kterému `brief.md` jako current-state dokument přepisovat smí.

**Exit kódy** podle konvence `mb-doc-index`: 0 běh v pořádku, 2 nalezen
blokující konflikt (existující `playbook.md`), 1 chyba běhu.

**Testy** podle konvence repozitáře — offline fixture s lokálním bare „origin",
`_assert.ps1` zkopírovaný do adresáře testů, žádný Pester. Pokrýt sloučení,
přejmenování bez `brief.md`, přepis odkazů, konflikt `playbook.md`,
idempotenci a především verifikátor: vstup s podvrženým novým řádkem musí být
odmítnut.

### 9. Dogfood — `memory-bank/` tohoto repozitáře

Převod proběhne ručně a pořádně, jako zkouška toho, jestli hranice v praxi drží:

- `brief.md` (62 ř.) pohltí `product.md` (85 ř.).
- Vznikne `playbook.md` s postupy, které dnes sedí v `tech.md`: konvence testů
  (`_assert.ps1`, offline fixtury, žádný Pester), CRLF past při revendoru,
  postup revendoru upstreamu, deploy vrstvy `sync-with-monorepo.ps1`.
  V `tech.md` zůstanou verze, závislosti, počty testů a konfigurace.
- `tasks.md` zůstává — tenhle repozitář nemá Jiru a jeho zaparkované nálezy
  jsou skutečně seznam úkolů.

## Dopady

**Kontrakt** `ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md` → v2.3:
Three-Tier Directory Model (výčet dokumentů), MB Context Reading Rule, Harvest
Contract §3 (playbook mimo current-state průchod, přesun jako legální operace,
sweep se třemi výústěními) a §5, nová sekce o sadě dokumentů a toleranci, nová
sekce o vlastnictví faktu s rozhodovacím testem, sběrný soubor ve výčtu
legálních cest pod `.superpowers/`.

**Overlay fragmenty** `ums/.claude/skills/shared/overlays/`:
`subagent-driven-development.overlay.md` (playbook v dispatchi, baseline, sekce
reportu), `finishing-a-development-branch.overlay.md` (gate s kandidáty).

**Skilly:** `mb-harvest` (gate, konzultace před zápisem, sada dokumentů, sweep
se třemi výústěními, přesuny v hlášení), `mb-init` (brief pohlcuje produktový
pohled, playbook jen při nalezených příkazech), `mb-sync` (sada, current-state
výčet, pravidlo vlastnictví a přesuny), a úklid výčtu `tasks.md`/`product.md`
v jazykovém boilerplate u `mb-scan`, `mb-git-commit`, `mb-git-message`,
`mb-jira-update`.

**Nové:** `ums/.claude/skills/mb-migrate-docs/` (SKILL.md, skript, testy).

**Dokumentace:** `ums/README.md`, `SKILLS_MANIFEST.md`, a po dokončení harvest
do `memory-bank/architecture.md` a `tech.md`.

**Předběžná podmínka:** nasazená kopie v `.claude/` je na kontraktu 2.1, zdroj
na 2.2. Před exekucí je nutné nasazení obnovit, jinak subagenti pracují podle
staré verze.

## Rizika

- **`brief.md` se stane skladištěm.** Mitigace: pevné pořadí sekcí v kontraktu
  a pravidlo, že prázdné sekce se nezakládají.
- **Hranice playbook / tech se rozmaže.** Mitigace: hranice je definovaná
  režimem zápisu — co harvest mění sám a co jen se souhlasem — ne tématem. To
  je testovatelné kritérium, na rozdíl od „patří to spíš sem".
- **Třetí případ rozhodovacího testu zůstává úsudkem.** „Kde to čtenář hledá
  první" nejde ověřit strojově. Mitigace: ať dopadne jakkoli, výsledek je jeden
  domov a odkaz — tedy žádná duplicita. Špatně zvolený domov je levná chyba,
  kterou opraví přesun; duplicita je drahá, protože se obě kopie rozejdou.
- **Playbook zestárne a nikdo ho neopraví.** Mitigace: agent smí opravu i
  smazání navrhnout a gate ji předloží vedle dotčeného záznamu; sběr kandidátů
  za běhu znamená, že rozpor mezi playbookem a realitou se zachytí právě ve
  chvíli, kdy o něj někdo zakopl.
- **Mazací agent nechá kostrbatou prózu.** Přijato vědomě; srovná ji nejbližší
  harvest.
- **Interaktivní gate zdrží harvest.** Mitigace: jedna dávková otázka, a jen
  když je co předložit.
- **Migraci nelze otestovat na skutečném monorepu.** Mitigace: fixtury
  reprodukující obě podoby MB včetně konfliktních případů; první ostrý běh
  v monorepu proběhne v náhledovém režimu.

## Zamítnuté alternativy

- **Sloučit `architecture.md` + `tech.md`.** Data ukazují 138 + 75 řádků a dvě
  různé osy; vzniklý 213řádkový soubor by mísil strukturu kódu s verzemi a
  buildem. Ušetřilo by to jedno rozhodnutí při zápisu za vyšší cenu při čtení.
- **Projektový skill místo dokumentu.** Skill se vybírá podle popisu proti
  zadání; „pracuju právě v PCInfo" je místo, ne druh úlohy, a na místo se
  skilly spouštějí nespolehlivě. Osmdesát projektových skillů navíc ředí
  trigger všem ostatním. Dokument se načte cestou, protože `Target MB Pin` cíl
  určuje deterministicky.
- **Postupy jako povinná sekce `tech.md`.** Držel by se počet druhů souborů, ale
  jeden soubor by měl dva režimy zápisu — jednu část by harvest měnil sám podle
  kódu, druhou jen se souhlasem uživatele. Rozhraní vedené uvnitř souboru je
  křehké; vedené hranicí souborů je vynutitelné.
- **Otevřené úkoly do `CLAUDE.md` / `AGENTS.md`.** V monorepu je instrukční
  soubor přepisován deploy skriptem z master kopie vrstvy a je jeden na celé
  repo, zatímco úkoly jsou per-projekt (80 MB).
- **Jednorázový agentní přepis bez verifikátoru.** Osmdesát nekontrolovaných
  přepisů dokumentace je přesně ta třída chyby, kterou tenhle repozitář řeší
  mechanickými kontrolami.
- **Jen tolerance, migrace lenivě při doteku MB.** Většiny MB se nikdo
  nedotkne, takže by stará podoba zůstala natrvalo a čtečka by musela umět
  obojí navždy.
- **Strojový detektor duplicit** (skript hlásící identifikátory sdílené dvěma
  dokumenty). Duplicita v próze není spolehlivě strojově detekovatelná — lidé
  i agenti parafrázují, takže přesná shoda skoro nenastává a fuzzy shoda šumí.
  Řada symbolů je navíc ve dvou dokumentech legitimně. Hlučný detektor naučí
  všechny ho ignorovat. Sweep hodnotí agent, který parafrázi pozná; cílená
  kontrola se dá postavit později, až budou reálné příklady duplicit z prvních
  harvestů.

## Navazující položky

- **Průběžný záznam výsledku (`handoff_<slug>.md`)** — položka 1
  z [tasks.md](../../tasks.md). Tento návrh řeší persistenci *postupů*; předání
  *výsledku* implementace pro Jiru a lidský test zůstává otevřené.
- **Migrace monorepa UMS** — spuštění `mb-migrate-docs` v `d:\_datasys\ums`,
  nejdřív v náhledovém režimu, ve vlastním commitu toho repozitáře.
