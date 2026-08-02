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
| Harvest | přepisuje podle skutečnosti | **jen připisuje, nikdy nepřepisuje** |
| Příklad | „staví se MSBuild v143, testy xunit" | „testy pouštěj cíleně přes `--filter`; plná sada trvá 40 minut" |

**Režim zápisu (append-only) s jedinou výjimkou:** kandidát označený jako
oprava — playbook tvrdí X, realita je Y — smí existující záznam přepsat, ale
jen když to uživatel u toho konkrétního záznamu schválí. Bez schválení se
připíše jako nový záznam a rozpor zůstane viditelný; to je pořád lepší než
tichý přepis. Harvest tedy `playbook.md` **nikdy nezpracovává
current-state stylem** — je to jediný trvalý MB dokument vyjmutý z pravidla
„popisuj aktuální stav" v Harvest Contract §3.

Formát záznamu je volný (nadpis + kroky). Když kandidát nesl evidenci, přenáší
se s ním jednořádkové **Proč:** — důvod je součástí postupu, ne šum.

`mb-init` zakládá `playbook.md` **jen tehdy**, když ve fázi detekce buildu a
závislostí našel konkrétní příkazy; do playbooku jdou příkazy, do `tech.md`
verze a stack. Prázdné stuby se nezakládají — přesně tak `tasks.md` skončil na
12,5 %.

### 3. Tři dráty

1. **MB Context Reading Rule** (kontrakt) — `playbook.md` přibude k dokumentům
   čteným před navrhováním a před psaním plánu; `product.md` z výčtu mizí.
2. **SDD overlay** — orchestrátor přikládá **cestu** k `<PLAN_MB>/playbook.md`
   ke každému dispatchi implementera vedle task briefu, a bere z něj postupy
   pro ověření baseline před prvním taskem. Skript `task-brief` se nemění; je
   vendorovaný a drát vede přes overlay, kde vede všechno ostatní.
3. **Harvest** — po implementaci se ptá, jestli větev vyrobila opakovatelný
   postup, který z kódu nevyčteš (viz gate níže).

### 4. Sběr zkušeností za běhu

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
- **Corrects:** <existing playbook entry>   (only for a correction)
```

Zákaz vymýšlení je zde vynucen **formátem**, ne prosbou: kandidát bez pole
`Happened` je neúplný záznam a nezapisuje se. Rozdíl mezi „projekt se testuje
přes `--filter`" a „spustil jsem plnou sadu, po 40 minutách timeout, s
`--filter` doběhla za 90 s" je přesně to, co odděluje zkušenost od dojmu.

**Jazyk:** sběrný soubor je AI-facing scratch, tedy anglicky (Language
Contract). `playbook.md` je trvalý artefakt, tedy česky — harvest při
persistenci překládá.

### 5. Harvest gate

Je-li sběrný soubor neprázdný a jeho slug odpovídá aktuální položce, harvest
**jednou** předloží uživateli seznam kandidátů s jejich evidencí a nechá
vybrat. Vybrané se přeloží a připíší do `playbook.md` cílové MB — nebo té MB,
kterou určuje pole `Target MB`. Nevybrané zmizí se scratchem; harvest ohlásí
jejich počet.

Toto je **jediné místo, kde `mb-harvest` přestává být autonomní**; ve zbytku
zůstává beze změny. Prázdný nebo cizí sběrný soubor gate přeskočí bez dotazu —
nenaléhá se.

### 6. Tolerance staré podoby

Trvalá, stejně jako grandfather klauzule u `proposal_` názvů:

- **Čtení:** existuje-li `product.md`, přečti ho také. Chybí-li `playbook.md`
  a existuje `tasks.md`, ber pro čtení `tasks.md`.
- **Zápis postupů:** do `playbook.md`, pokud existuje; jinak do `tasks.md`,
  pokud existuje; jinak se `playbook.md` založí.
- Žádná MB není nucena migrovat, aby zůstala platná.

### 7. Skill `mb-migrate-docs`

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

### 8. Dogfood — `memory-bank/` tohoto repozitáře

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
Contract §3 (výjimka pro playbook) a §5, nová sekce o sadě dokumentů a
toleranci, sběrný soubor ve výčtu legálních cest pod `.superpowers/`.

**Overlay fragmenty** `ums/.claude/skills/shared/overlays/`:
`subagent-driven-development.overlay.md` (playbook v dispatchi, baseline, sekce
reportu), `finishing-a-development-branch.overlay.md` (gate s kandidáty).

**Skilly:** `mb-harvest` (gate, append-only, sada dokumentů), `mb-init` (brief
pohlcuje produktový pohled, playbook jen při nalezených příkazech), `mb-sync`
(sada, current-state výčet), a úklid výčtu `tasks.md`/`product.md`
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
  režimem zápisu (co harvest smí přepsat), ne tématem — to je testovatelné
  kritérium, na rozdíl od „patří to spíš sem".
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
  jeden soubor by měl dva režimy zápisu — harvest by musel jednu sekci vyjímat
  z current-state pravidla. Křehké.
- **Otevřené úkoly do `CLAUDE.md` / `AGENTS.md`.** V monorepu je instrukční
  soubor přepisován deploy skriptem z master kopie vrstvy a je jeden na celé
  repo, zatímco úkoly jsou per-projekt (80 MB).
- **Jednorázový agentní přepis bez verifikátoru.** Osmdesát nekontrolovaných
  přepisů dokumentace je přesně ta třída chyby, kterou tenhle repozitář řeší
  mechanickými kontrolami.
- **Jen tolerance, migrace lenivě při doteku MB.** Většiny MB se nikdo
  nedotkne, takže by stará podoba zůstala natrvalo a čtečka by musela umět
  obojí navždy.

## Navazující položky

- **Průběžný záznam výsledku (`handoff_<slug>.md`)** — položka 1
  z [tasks.md](../../tasks.md). Tento návrh řeší persistenci *postupů*; předání
  *výsledku* implementace pro Jiru a lidský test zůstává otevřené.
- **Migrace monorepa UMS** — spuštění `mb-migrate-docs` v `d:\_datasys\ums`,
  nejdřív v náhledovém režimu, ve vlastním commitu toho repozitáře.
