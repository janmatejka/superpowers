# Návrh: Vrstva v3 — jádro a doklad (kontrakt 3.0, orchestrace, Jira)

- **Jira:** UMS-3551 (https://datasyscz.atlassian.net/browse/UMS-3551)
- **Target MB:** memory-bank/
- **Vytvořeno:** 2026-09-17
- **Blokuje:** UMS-3552

Dokument je psaný podle pravidla, které sám zavádí: sekce Cíl, Scope,
Technický návrh, Dopady, Rizika a Ověření jsou **jádro** — pravidla a postupy
bez zdůvodnění; měření, historie a zdroje jsou v sekci **Doklad** na konci
a jádro na ně odkazuje jménem podsekce.

## Cíl

1. Zmenšit text, který vrstva vkládá do každého sezení, na rozpočtované jádro
   a přesunout zbytek do referencí načítaných skillem, který je provádí, a do
   dokladu čteného na vyžádání.
2. Zachovat spolehlivost po kompaktaci kontextu i při dlouhém běhu: pravidla
   platná v každé fázi (fail-closed STOPy, eskalační dno, publikace, jazyk)
   zůstávají v jádře a hook je vkládá do kontextu mechanicky.
3. Zavést pravidlo granularity pracovní položky: málo velkých tiketů s TDD,
   fáze v plánu místo tiketů.
4. Zapracovat poznatky správce epiku UMS-3517 do kontraktu, `mb-epic-run`
   a šablony ledgeru.
5. Jira: rámcové popisy tiketů s rozpočtem, odkazy, které přežijí uložení,
   host permalinku z konfigurace.

## Scope

**Dovnitř**

- Kontrakt 3.0 ve třech vrstvách souborů: jádro, reference po tématech,
  doklad; verzní historie do changelogu; mapa fází.
- Hook vkládající jádro, `context.md` a blok `NOW` do kontextu při startu
  sezení a po kompaktaci.
- Bannery `mb-*` skillů a overlayů jmenují jádro a své reference; duplicitní
  parafrázy pravidel v tělech skillů nahrazuje odkaz.
- Pravidlo granularity v jádře, v overlay `brainstorming` a v
  `mb-epic-elaboration`.
- Deset poznatků správce epiku (sekce Technický návrh, bod 5).
- Jira: reference `jira.md` se šablonou popisu, rozpočtem a pravidlem odkazů;
  klíč `permalinkTemplate` v `ums-repo.json`; kontrolní skript popisu; oprava
  dvou driftů.
- Nové testovací sady: tvar kontraktu, zachování textu při přesunu,
  injektážní hook, kontrola popisu tiketu; rozšíření sad `pool-status`,
  `pool-launch`, `ledger-status`.
- `mb-state` hlásí drift nasazené kopie vrstvy vůči zdroji ve forku.

**Ven**

- Tvar, rozpočet, triage a konsolidace playbooku — UMS-3552 (draft v
  `proposals/next/`). Tento návrh jen přesouvá Playbook Contract do reference
  beze změny obsahu.
- Konsolidace playbooků monorepa.
- Autonomní zápis do playbooku bez člověka (navazující položka UMS-3505).
- Výkon `doc-index.ps1` na monorepu; redesign epikové linie.
- Změna chování `pre-push` hooku a `guard-git-push.mjs`.

## Technický návrh

### 1. Princip „jádro a doklad"

- Každý artefakt, který vrstva staví před čtenáře — kontrakt, playbook, popis
  tiketu, zpráva správce — má **jádro** a **doklad**.
- Jádro je pravidlo, pokyn nebo rámec; je rozpočtované a vždy přítomné tam,
  kde se čte.
- Doklad je důvod, měření a historie; je odkazovaný jménem podsekce a čte se
  na vyžádání — autorem změny, ne vykonavatelem pravidla.
- Tři mechanismy: rozdělení jádro/doklad v každém artefaktu; rozpočet
  vynucený testem ve stávající sadě vrstvy; triage při zápisu s verdikty
  nový / sloučit do / nahrazuje / do kódu / zahodit, místo append-only.
- Tento návrh aplikuje princip na kontrakt, hooky a Jiru; UMS-3552 na
  playbook. Doklad: „Proč jádro a doklad".

### 2. Kontrakt 3.0

**2.1 Tři vrstvy souborů v `ums/.claude/skills/shared/`**

| Vrstva | Soubor | Kdo čte | Rozpočet |
|---|---|---|---|
| Jádro | `UMS_MEMORY_BANK_CONTRACT.md` | každé sezení, mechanicky hookem | 600 řádků |
| Reference | `contract/<téma>.md` | skill, který téma provádí | bez rozpočtu, jedno téma na soubor |
| Doklad | `contract/doklad/<téma>.md` | autor změny pravidla | bez rozpočtu |
| Historie | `CHANGELOG.md` | nikdo za běhu | bez rozpočtu |

**2.2 Obsah jádra** (pořadí je pořadí čtení; každá sekce nese jen pravidla a
artefakty, které pravidlo tvoří):

1. Účel a role (deset řádků).
2. Trojvrstvý adresářový model, `MB_ROOT` discovery, Root Memory Bank Gate.
3. Sada dokumentů MB a vlastnictví faktu (tabulka), legacy tolerance
   (tři řádky).
4. Scope lock, konvence odkazů (tabulka přepisů, bez zdůvodnění rendererů).
5. Umístění dokumentů superpowers a hlavičky návrhu i plánu.
6. Pracovní položka: pojmenování, pár, grandfather, fronta `next/`.
7. Schéma `context.md`, test ACTIVE/IDLE, zapisovatelé.
8. **Způsobilost sezení** — fáze 0 vstupní brány: `git fetch origin`,
   verze `pre-push` hooku porovnaná uspořádáním a obě poloviny syntetického
   self-checku s přesnými příkazy; zbytek vstupní brány je v referenci
   `workspace-discipline.md`.
9. **Granularita pracovní položky** (nové, bod 4).
10. Publikační pravidlo: kdo pushuje co, pravidlo první publikace, dvě
    zaklínadla; bez pitvy `guard-git-push.mjs`.
11. Hranice base syncu: seznam hranic fází a zákaz mergovat uprostřed tasku.
12. Zákaz worktrees s odkazem na referenci slotu poolu.
13. Dispatch Model Policy. Language Contract.
14. Message Protocol — jádro: dvě značky, tři důsledky, pořadí artefakt před
    zprávou (bod 5).
15. Escalation & Autonomy — dno (tabulka) a dvě pravidla o ukončení tahu;
    pásma a úrovně jsou v referenci.
16. Fail-Closed Behavior — úplný seznam STOPů.
17. **Mapa fází** (nové): tabulka operace → vlastnící skill → reference.
18. Citace a verze: jak skill jmenuje jádro a referenci; `Contract-Version`.

**2.3 Reference a jejich vlastníci**

| Reference | Obsah dnes v sekcích | Vlastnící skill nebo overlay |
|---|---|---|
| `workspace-discipline.md` | Workspace Discipline, volnost slotu, vstupní brána | overlay brainstorming, `mb-state`, `mb-park`, `mb-epic-run` |
| `target-mb-discovery.md` | Target-MB Discovery & Pinning | overlay brainstorming |
| `brainstorming-paths.md` | Brainstorming Paths | overlay brainstorming, overlay finishing |
| `repository-configuration.md` | Repository Configuration bez epikové linie | `mb-init`, `mb-state`, overlaye, dokumentace hooků |
| `epic-line.md` | The epic line, registr rozhodnutí | `mb-epic-run`, `mb-epic-elaboration`, `guard-git-push.mjs` (komentář) |
| `playbook-contract.md` | Playbook Contract beze změny obsahu | overlay SDD, `mb-harvest`, `mb-park` |
| `session-intent-baton.md` | Session Intent Baton | `session-intent.ps1`, `mb-park`, `mb-abort`, `mb-harvest`, overlay writing-plans, overlay SDD |
| `now-block.md` | The `NOW` Block | overlay SDD, `mb-epic-run` |
| `harvest.md` | Harvest Contract, Document Ownership (postup) | `mb-harvest`, `mb-sync`, `mb-migrate-docs` |
| `integration.md` | Integration, Abandon | overlay finishing, `mb-epic-run`, `mb-abort`, `mb-jira-update` |
| `cross-branch-visibility.md` | Cross-Branch Visibility | `mb-doc-index`, overlay brainstorming |
| `architect-review.md` | Architect Review Gate, Agentic Design Opposition | `mb-architect-review`, overlay brainstorming |
| `epic-backflow.md` | Epic Backflow, per-tiketový soubor epiku (bod 5) | overlay brainstorming, `mb-architect-review`, `mb-epic-elaboration` |
| `message-protocol.md` | Message Protocol mimo jádro | `mb-epic-run` |
| `escalation.md` | pásma, třídy konfliktu, úrovně autonomie, pravidla ledgeru (bod 5) | `mb-epic-run`, `mb-epic-elaboration`, overlay SDD |
| `worktree-pool.md` | Worktree Policy — výjimka slotu | `mb-epic-run`, `pool-provision.ps1` |
| `jira.md` | nové (bod 6) | `mb-jira-update`, `mb-epic-elaboration`, `mb-architect-review`, `mb-epic-graph` |

**2.4 Pravidla tvaru**

- Pravidlo má jeden domov: jádro, nebo právě jedna reference. Skill a overlay
  pravidlo cituje, nikdy neparafrázuje; dnešní duplicitní páry (Doklad,
  „Duplicity kontrakt × skill") se při přesunu nahradí citací.
- Citace má tvar `(kontrakt, „<sekce>")` pro jádro a `(reference <soubor>,
  „<sekce>")` pro referenci. Jiný tvar test neuzná.
- Reference obsahuje postup a jeho artefakty: šablony, příkazy, tabulky
  stavů. Zdůvodnění patří do dokladu; v referenci smí zůstat jedna věta
  „proč" tam, kde bez ní postup nedává smysl.
- Jádro neodkazuje na doklad kvůli platnosti pravidla; platnost nese jádro
  samo.
- Doklad nese u každého měření podmínky běhu: datum, commit, velikost vstupu.
- Banner skillu: `> Contract core: ../shared/UMS_MEMORY_BANK_CONTRACT.md ·
  References: ../shared/contract/<a>.md, ../shared/contract/<b>.md`. Prvním
  krokem skillu je přečíst své reference.
- Verzi nese jen jádro (`Contract-Version: 3.0`); reference nesou řádek
  `Part of contract 3.x` bez vlastního čísla. Změna reference zvedá verzi
  jádra stejně jako dnes změna sekce.
- Verzní preambule se přesouvá do `CHANGELOG.md`; jádro nese jen aktuální
  číslo a odkaz.

**2.5 Postup přesunu (tři commity, každý ověřitelný)**

1. **Přesun beze změny textu.** Každý neprázdný řádek kontraktu 2.19 se
   objeví právě jednou v jádře, referenci, dokladu nebo changelogu. Test
   `contract-move.tests.ps1` ověří multiset řádků (vzor
   `verify-deletion-only.ps1` z `mb-migrate-docs`). V tomto commitu se
   nemění ani slovo.
2. **Extrakce dokladu.** Odstavce zdůvodnění a historie se přesunou z jádra
   a referencí do dokladu a na jejich místě zůstane odkaz jménem podsekce.
   Test zachování textu platí dál; přibývá test rozpočtu jádra.
3. **Nová pravidla.** Body 4 až 7 tohoto návrhu, každý s vlastními testy
   napřed.

**2.6 Test tvaru kontraktu** (`contract-shape.tests.ps1`)

- Jádro má nejvýš 600 řádků a nese `Contract-Version`.
- Každé jméno sekce citované kdekoli v `ums/` existuje právě v jednom souboru
  jádra nebo referencí.
- Každá reference má alespoň jednoho konzumenta v banneru skillu nebo overlaye.
- Řádky eskalačního dna a seznam Fail-Closed STOPů jsou v jádře, ne v
  referenci.
- Jádro neobsahuje značky dokladu (`Measured`, `Naměřeno`, „earlier versions",
  `superseded`).
- Verzní preambule v jádře chybí.

### 3. Mechanické načtení jádra

- `SessionStart` (všechny zdroje startu) a `PostCompact` volají
  `contract-inject.ps1` místo dnešního `echo` s pokynem „přečti si soubor".
- Hook emituje `additionalContext` s obsahem: jádro kontraktu doslova; obsah
  `memory-bank/context.md`; blok `NOW` aktivního plánu, existuje-li ledger
  slugu z pinu; a pokyn vyvolat `using-superpowers` a znovu skill, který
  sezení vykonává. Payload je anglický (Language Contract, hook s výstupem
  pro model).
- Blok `NOW` a cokoli vyzdvižené z ledgeru prochází stejným uzavřeným
  re-renderem a stejnou znakovou třídou jako baton (reference
  `session-intent-baton.md`, „Reader safety").
- Hook je fail-open: na každé chybové cestě emituje dnešní pokyn „přečti si
  jádro" a nikdy nezablokuje start sezení.
- Horní mez payloadu je 48 kB; při překročení hook emituje pokyn ke čtení
  místo obsahu a ohlásí to jedním řádkem.
- Kontrola publikační záruky ze `settings.json` se přesouvá do jádra
  (sekce Způsobilost sezení, bod 2.2) a hook ji neopakuje.
- Skilly načítají své reference při vyvolání; po kompaktaci se skill vyvolá
  znovu, takže referenci načte znovu.
- Ostatní harnessy (Codex, Gemini, Kilo Code) hook nemají; instrukční soubor
  odkazuje jádro a jeho velikost dělá pokyn „přečti si ho" splnitelným. Test
  `contract-inject.tests.ps1`: platný JSON, jádro přítomné celé, `NOW` blok
  přítomný jen s ledgerem slugu z pinu, chybějící jádro → fallback pokyn,
  chybějící `context.md` → jádro přesto, znaková třída odmítne formátovací
  znaky, mez payloadu.

### 4. Granularita pracovní položky

- **Jádro, jedna sekce:** pracovní položka je tak velká, jak velký je souvislý
  celek ověřitelný jednou ověřovací sadou; dělí se jen podle kritérií
  rozštěpení, nikdy kvůli velikosti. Velikost nese plán s fázemi a TDD, ne
  počet tiketů.
- **Kritéria rozštěpení** (reference `epic-backflow.md` a
  `mb-epic-elaboration/protocol.md`, krok hranic): samostatně dodatelný
  povrch nebo komponenta, odlišná množina blokátorů, růst rozsahu — a
  zároveň jiný aktér nebo jiná dodávka. Bez druhé podmínky je odpověď fáze
  v jednom plánu.
- **Cena dělení** je v referenci vyjmenovaná, ne tušená: vlastní návrh, plán,
  brána, harvest, Jira komentáře, řádky registru rozhodnutí a předání na
  každý tiket navíc; každá hranice mezi tikety je místo, kde se ztrácí
  ruling, osiří nález nebo vznikne konflikt nad sdíleným souborem.
- **Overlay `brainstorming`, krok dekompozice:** upstream rozpad na
  podprojekty se ve vrstvě míří nejdřív na fáze jednoho plánu; samostatná
  položka vzniká jen podle kritérií výše a dostává draft v `proposals/next/`
  s rámcovým tiketem (bod 6).
- Doklad: „Granularita".

### 5. Poznatky správce epiku UMS-3517

| Poznatek | Pravidlo | Domov |
|---|---|---|
| Ruling odešel zprávou a v ledgeru nebyl | Ruling je nejdřív commitnutý v ledgeru; zpráva nese SHA commitu a odkaz. Příjemce relaye potvrzuje jen to, co v ledgeru přečetl. | jádro, Message Protocol |
| Tvrzení o cizím kódu bylo zkreslené shrnutí | Tvrzení o kódu nese, čím bylo ověřeno, nebo říká „neověřeno". | jádro, Message Protocol |
| Číselná podlaha testů z jiného stromu | Podlaha selhávajících testů je množina jmen; řádek se slibem „jména dodá sezení" je špinavý, dokud jména nedorazí. `ledger-status.ps1` to hlásí. Každé měřené číslo nese podmínky běhu. | reference `escalation.md`, šablona ledgeru |
| Epic bez epikové linie neměl artefakt předání; backflow psal do sdíleného `notes.md` | **Per-tiketový soubor epiku** `memory-bank/epics/<epik>/tickets/<TIKET>.md` na tiketové větvi: nese poznámky backflow i řádek předání; do báze dojede integrací; správce ho čte z báze modelem tahu. `notes.md` na bázi se nepíše. | reference `epic-backflow.md`, `integration.md` |
| Adoptér odložené práce zanikl | Ruling odkládající práci na jiný tiket nese, co se stane, když ten tiket skončí dřív; `integrate` a finishing projdou odložené řádky jmenující integrující tiket. | reference `escalation.md` |
| Dva controllery v jednom slotu | Víc než jedno živé sezení ve slotu = `free=false` s pojmenovaným důvodem. | `pool-status.ps1` |
| Dvě negativní sondy po spuštění nestačily | Ověření spuštění čeká na podmínku `session.state == live` s timeoutem a hlásí „čekám", ne „neobjevilo se". | `pool-launch.ps1`, `mb-epic-run` |
| Jméno agenta rotuje; dva registry sezení | Adresuj `sessionId`; před odesláním jméno znovu rozřeš; neexistenci nikdy nesuď z jednoho registru. | `mb-epic-run` |
| Po kompaktaci zrcadlo popisu tiketu tři dny staré | Hlavička ledgeru nese „Ověřeno proti: <větev>@<sha>, <datum>"; zrcadlo popisu nese razítko stažení. | šablona ledgeru, reference `jira.md` |
| Zápis do playbooku chybí v dně | Řádek dna: zápis do `playbook.md` schvaluje vždy člověk. | jádro, Escalation & Autonomy |

Poznatek o oprávněném odmítnutí správce je pokrytý dnešním Message Protocolem
a jen se přesouvá do jádra. Doklad: „Poznatky UMS-3517".

### 6. Jira

- **Reference `jira.md`** s šablonou popisu tiketu: Cíl do pěti vět; Rozsah
  dovnitř a ven; Závislosti jen jako linky; řádek `**Návrh (design):**` s
  commit-pinned odkazem, nebo věta, že návrh vznikne v brainstormingu;
  Ověření do tří řádků.
- Rozpočet popisu 2 500 znaků. Podrobnosti patří do `design_<slug>.md` v
  `proposals/next/` na publikované větvi; tiket ho odkazuje.
- Text odkazu nikdy neobsahuje backticks; tučné nikdy neobaluje code span.
- Po každém zápisu popisu nebo komentáře se text přečte zpět
  (`responseContentFormat: markdown`) a ověří, že každý odkaz a každé tučné
  přežilo; text psaný do souboru se porovná diffem.
- **Klíč `permalinkTemplate`** v `ums-repo.json` (konzumenti: `mb-jira-update`
  §7, orákulum `mb-epic-graph`, `mb-architect-review`): šablona s `{sha}` a
  `{path}`. Chybí-li, odvodí se z hostu `origin` (bitbucket.org →
  `src/{sha}/{path}`, github.com → `blob/{sha}/{path}`); neznámý host je
  STOP s otázkou na uživatele. Odvození i dosazení dělá sdílený skript
  `Get-UmsPermalink.ps1`, jediný domov tvaru URL.
- Kontrolní skript `Test-UmsJiraDescription.ps1`: rozpočet, tvar odkazů,
  tučné × code span; volá se před každým zápisem. Testy napřed.
- Opravy driftů: `Návrh (proposal)` → `Návrh (design)` v
  `mb-epic-elaboration/protocol.md`; „řádek Tikety" → sekce
  `## Členové (proposaly)`.
- `mb-epic-elaboration`, krok „Write the slice": text tiketu se píše ze
  šablony; rozpracování jde do draftu v `next/`.

### 7. Drift nasazené kopie ve forku

- `mb-state` ve forku porovná `Contract-Version` a hash souborů `shared/`
  a `mb-*` mezi `ums/.claude/` a `.claude/` a hlásí rozdíl jako nález
  „nasazení za zdrojem" s příkazem obnovy z playbooku.
- `contract-inject.ps1` přidá jeden řádek varování, když zdrojové jádro
  existuje a liší se od nasazeného.

## Dopady

- **Kontrakt:** `UMS_MEMORY_BANK_CONTRACT.md` zmenšený na jádro; nový adresář
  `shared/contract/` s referencemi a `doklad/`; `shared/CHANGELOG.md`.
- **Skilly a overlaye:** bannery všech `mb-*` skillů a čtyř overlayů;
  odstranění parafráz; `mb-epic-elaboration/protocol.md` a
  `ledger-template.md`; `mb-jira-update` §7 až §8; `mb-epic-graph` orákulum
  odkazu; `mb-state`; `mb-epic-run` skripty a SKILL.
- **Hooky a lepidlo:** nový `contract-inject.ps1`; `settings.json`
  (`SessionStart`, `PostCompact`); `CLAUDE.md.sample`, `ums/README.md`,
  `SKILLS_MANIFEST.md`.
- **Sdílené skripty:** `Test-UmsJiraDescription.ps1`, `Get-UmsPermalink.ps1`;
  `Get-UmsRepoConfig.ps1` čte `permalinkTemplate`.
- **Testy:** nové sady `contract-move`, `contract-shape`, `contract-inject`,
  `jira-description`, `permalink`; rozšíření `pool-status`, `pool-launch`,
  `ledger-status`, `repo-config`.
- **Nasazení:** monorepo přes `sync-with-monorepo.ps1 -Direction ToMonorepo`
  a revendor overlayů; fork přes obnovu nasazené kopie (playbook).
- **Memory Bank tohoto repa:** harvest aktualizuje `architecture.md`
  (dokumentová vrstva, hooky), `tech.md` (inventář testů, konfigurace) a
  `brief.md` (kontrakt 3.0).
- **Kompatibilita citací:** citace `(contract, „X")` platí dál, kde X zůstává
  v jádře; přesunuté sekce dostanou nový tvar citace a test tvaru odhalí
  každou zapomenutou.

## Rizika

- **Regrese spolehlivosti po kompaktaci.** Kryje mechanická injektáž, dno a
  STOPy v jádře a test, který jejich přítomnost v jádře vynucuje.
- **Změna pravidla schovaná v přesunu.** Kryje commit beze změny textu s
  testem zachování řádků; pravidla se mění až ve třetím commitu.
- **Rozpočet vytlačí pravidlo z jádra.** Test selže hlasitě; zvýšení rozpočtu
  je změna testu schválená člověkem, ne tiché přesunutí do reference.
- **Payload hooku.** Asi 40 kB při každém startu a kompaktaci proti dnešním
  180 kB čtení souboru; mez 48 kB a fallback na pokyn ke čtení.
- **Rozpad citací.** Test tvaru selže na každé citaci, která nemá cíl.
- **Odvození hostu permalinku** mine nestandardní remote; neznámý host je
  STOP, ne tichý default.

## Ověření a akceptace

- Sada vrstvy zelená (dnes 28 sad, 1 502 asercí) plus nové sady výše; každá
  nová sada prokáže vlastní negativitu (playbook, sekce Testy vrstvy).
- Jádro do 600 řádků; hook vloží jádro do nového sezení a po kompaktaci
  (ověřeno ručně v Claude Code na tomto repu a v monorepu).
- Popis UMS-3551 a UMS-3552 projde `Test-UmsJiraDescription.ps1`; řádek
  `Návrh (design)` nese GitHub permalink z `permalinkTemplate`.
- `mb-epic-run status` hlásí slot se dvěma živými sezeními jako neuvolněný
  (fixture).
- Deklarovanou ověřovací sadu v tvaru ohrazeného bloku nese plán
  (kontrakt, Brainstorming Paths).

## Doklad

### Proč jádro a doklad

| Měření | Hodnota | Podmínky |
|---|---|---|
| Kontrakt 2.19 | 3 066 řádků, 183 kB, asi 46 k tokenů | `ums/.claude/skills/shared/`, 0a13ef1, 2026-09-17 |
| Podíl zdůvodnění a historie v kontraktu | asi 40 %, asi 1 200 řádků | odhad analytika po sekcích nad 2.18, 2026-09-17 |
| Jádro potřebné v každé fázi | asi 470 řádků, 15 % | tamtéž; seznam sekcí v Technickém návrhu 2.2 |
| Verzní preambule | 91 řádků, žádný konzument | tamtéž |
| Sekce bez jediného konzumenta | asi 210 řádků; s právě jedním konzumentem načítaným na vyžádání asi 450 řádků | grep `ums/.claude/` 2026-09-17 |
| Duplicity kontrakt × skill | 20 párů; jeden odstavec zkopírovaný v pěti skillech, v jednom už rozešlý | tamtéž |
| Načtení kontraktu | dvakrát na sezení (start, po kompaktaci) pokynem „přečti si", plus banner v 20 skillech; hook soubor nečte | `.claude/settings.json` 2026-09-17 |
| Codex, Gemini, Kilo Code | kontrakt se při startu nenačítá vůbec | `sync-with-monorepo.ps1` nenasazuje `settings.json` |
| Správce epiku UMS-3517 | trvale potřeboval dno, Message Protocol, Publication Contract a tvary ledgeru; epikovou linii nepoužil nikdy | zpráva sezení „UMS-3517 orchestrace", 2026-09-17 |
| Lokální workspace při startu tohoto sezení | báze 191 commitů za `origin`, nasazená kopie o verzi zpět; nic to nehlásilo | tento fork, 2026-09-17 |

Zdroje mechanismů: Claude Code auto-memory (index + soubory na téma, limit
indexu 200 řádků a 25 kB, konsolidační průchod); Cursor rules (500 řádků na
soubor, čtyři režimy aktivace); Windsurf (popis v systémovém promptu, tělo na
vyžádání); Anthropic skills (tělo SKILL.md do 500 řádků, reference jednu
úroveň hluboko); Letta (bloky paměti s limitem, přepis místo appendu); mem0
(triage ADD / UPDATE / DELETE / NONE při zápisu); ADR (superseded, ne smazané);
Liu et al. 2023 „Lost in the Middle"; IFScale 2025 (adherence klesá s hustotou
instrukcí). Rešerše 2026-09-17, odkazy v transkriptu sezení.

### Duplicity kontrakt × skill

Formát kandidáta playbooku (kontrakt × overlay SDD); triage kandidátů při
harvestu (kontrakt × `mb-harvest`); publikační pravidlo a ověření
dosažitelnosti (kontrakt × `mb-park`); pravidlo první publikace (kontrakt ×
overlay brainstorming × `mb-park`); sekvence integrace (kontrakt × overlay
finishing, téměř doslovná parafráze); tři domovy ověřovací sady; kontrola
z báze; sekvence base syncu na třech místech; vstupní brána (kontrakt ×
overlay brainstorming); čtyři sondy volného workspace (kontrakt ×
`mb-state`); recept ověření hooku na třech místech; enum bloku `NOW`
(kontrakt × `pool-status.ps1`); znaková třída; degradace `epicBranchPattern`
na čtyřech místech; souhrn Target-MB discovery v pěti skillech (jedna kopie
už cituje jiná jména souborů). Analytik 2026-09-17 nad 2.18, čísla řádků v
transkriptu.

### Granularita

- Zkušenost zadavatele: méně velkých tiketů s TDD dopadá lépe než mnoho
  malých souvisejících (2026-09-17).
- Dnešní brainstorming zhustil čtyři položky na dvě bez ztráty rozsahu.
- UMS-3505 dokončený jako jeden tiket: 50 commitů, 27 sad, 1 434 asercí,
  26 ověřovacích bodů (finální review 2026-09-08).
- Cena koordinace mezi tikety v UMS-3517: tři rulingy ztracené ve zprávě,
  osiřelý nález po zaintegrování adoptéra, dvanáct hodin prostoje dvou
  tiketů bez artefaktu předání, dva konflikty modify/delete nad `notes.md`
  (zpráva správce, 2026-09-17).

### Poznatky UMS-3517

Zpráva sezení „UMS-3517 orchestrace" z 2026-09-17, oddíly A až D; ledger
epiku na `origin/UMS-3517-rizeni-epicu`, cesta
`memory-bank/epics/ums_3517/ledger.md`. Třináct poznatků; deset přijatých je
v tabulce Technického návrhu 5, jeden je pokrytý dnešním textem, dva se týkají
jen `mb-epic-run` a jsou v téže tabulce sloučené.

### Jira

- Popisy tiketů UMS-3517: 4 726 B (UMS-3543) až 15 317 B (UMS-3518); po
  výtce zadavatele 2026-09-16 nový tiket 2 236 B (UMS-3549).
- Změřená příčina ztráty odkazů: Jira při `contentFormat: markdown` zahodí
  odkaz, jehož text je v backticks, a uloží jen code span; tučné okolo code
  spanu se rozpadne (zpráva správce, 2026-09-17). Ve vrstvě žádná instrukce
  „URL jako text" neexistuje; `mb-jira-update` §7b odkaz vynucuje regexem
  na Bitbucket, což tento fork na GitHubu nesplní (analytik 2026-09-17).
- Šablona popisu tiketu ve vrstvě neexistuje; jediný předepsaný řádek je
  `**Návrh (design):**`. Drifty: `Návrh (proposal)` v `protocol.md:176` a
  „řádek Tikety" v `protocol.md:227` proti `ledger-template.md:28`.
- Popisy UMS-3551 a UMS-3552 založené 2026-09-17 podle šablony bodu 6 se
  uložily neporušené (1 750 a 1 800 znaků).

## Navazující položky

- **UMS-3552** — playbook: tvar, rozpočet, triage, konsolidace (draft
  `proposals/next/design_ums_3552_playbook_jadro_a_doklad.md`).
- Konsolidace playbooků monorepa po ověření skillu ve forku (KicWorkflow
  3 223 řádků, SMSInfo3 1 446, kořen 408; měřeno 2026-09-17 na `develop`).
- Autonomní zápis do playbooku (navazující položka UMS-3505) — stavební
  kameny zůstávají, dno ho dál drží u člověka.
- Kontrola, že nasazená vrstva odpovídá zdroji na efektivní bázi, jako
  součást vstupní brány mimo fork (monorepo má nasazenou kopii trackovanou,
  takže tam problém nevzniká).
