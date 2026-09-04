# Návrh (předběžný): Zprávy, viditelnost rozpracovanosti a autonomie orchestrace

- **Jira:** (bez tiketu)
- **Target MB:** memory-bank/
- **Vytvořeno:** 2026-09-04
- **Stav:** předběžný — čeká ve frontě, neaktivovaný
- **Evidence:** praxe sezení `ums01` z 3. a 4. 9. 2026, které řídí epik SKODASMS-237 přes tři tiketová sezení **bez skillu**; jeho odpovědi jsou v této session a všechna čísla níž jsou „co se stalo", ne „co by mělo fungovat"

## Cíl

Orchestrace epiku přes několik tiketových sezení se dnes dělá ručně. UMS-3488
dodalo **mechaniku spuštění** (derivovaný stav slotu, launcher s argv promptem,
skill `mb-epic-run`), ale ne to, co se děje **potom**: orchestrátor nevidí, co
tiketová sezení dělají, nemá formu, jak jim doručit změnu zadání, a jeho
sezení zastavují na místech, kde zastavovat nemají — nebo naopak zastaví víc,
než je potřeba.

Tento návrh pokrývá **pět částí**, které se prakticky nedají oddělit. Autonomie
je z nich ta, která prochází všemi ostatními — proto stojí v pořadí implementace
poslední, ne proto, že by byla nejmenší.

**Části se v textu jmenují, ne číslují.** Číslo sekce a číslo v pořadí
implementace se rozcházejí (unikátnost je pátá sekce, ale třetí v pořadí),
takže odkaz na „část 3" by znamenal dvě různé věci podle toho, kde se čte.

## Scope

**V rozsahu:**

- **Blok `NOW`** v hlavě SDD ledgeru se strukturální spouští — tahová
  viditelnost rozpracovanosti.
- **Protokol zpráv** mezi orchestrátorem epiku a tiketovými sezeními: druhy,
  iniciátor, značení *pokyn* versus *domněnka*, pravidlo relay timingu.
- **Epiková integrační větev** jako pojmenovaná třetí kategorie vedle hlavních
  integračních větví a tiketových větví.
- **Autonomie o dvou osách** — „kdy zastavit" a „kolik zastavit" — volená
  operátorem.
- **Unikátnost orchestrátora epiku** — derivovaná, bez registru, a povinná
  právě proto, že epiková integrační větev dovoluje agentovi pushovat sám.

**Mimo rozsah úplně** (a proč):

- **Žádný nový přenosový kanál.** `ListAgents` a `SendMessage` existují a
  fungují; změřeno, že orchestrátor v hlavním klonu vidí sezení ve slotech
  poolu jako peery. Stavět vlastní transport by bylo zdvojení.
- **Žádná evidence stavu mimo ledger.** Blok `NOW` je v ledgeru, ne ve druhém
  souboru — druhý domov téhož faktu se v této vrstvě rozejde (viz Rozhodnutí).
- **Žádné zápisy orchestrátora do pracovního stromu slotu.** Železné pravidlo
  z UMS-3488 platí dál; zprávy do stromu nezapisují a blok `NOW` píše **sezení
  ve slotu**, ne orchestrátor.
- **Žádná automatická integrace do hlavních integračních větví.** Tam zůstává
  push člověku, bez výjimky.

## Technický návrh

### 1. Blok `NOW` — viditelnost tahem

**Problém není chybějící kanál.** `ListAgents` rozlišuje `busy` a `idle`, ale
`idle` **slévá dva různé stavy**: „stojím a čekám na pokyn" a „legitimně čekám
na dispatchnutého subagenta". Tato jediná nejednoznačnost způsobila u `ums01`
**čtyři chybné závěry za jeden den**. Jeho obcházení je pomalé a stojí turn na
obou stranách: místo pobídky psát dotaz „stojíš, nebo čekáš? jestli čekáš,
ignoruj to".

**Řešení.** Sezení ve slotu drží v **hlavě** svého SDD ledgeru blok se šesti
položkami: `HEAD`, aktuální task, poslední hotový krok, **další akce**, co je
blokované, co není moje.

**Spoušť je strukturální, ne mravní** — a to je na tom celé podstatné:
*další dispatch se skládá Z toho bloku*, takže blok musí být aktuální dřív, než
se dispatch dá vůbec napsat. K tomu jedna kontrolní věta: *když si blok a
`git log` odporují, blok je špatně.* Pravidlo tedy není „udržuj blok aktuální"
(to se dá odkývat a porušit), ale „bez aktuálního bloku nemáš z čeho složit
další krok".

**Dopadá to na existující mechaniku, ne na nový subsystém.** `pool-status.ps1`
už dnes čte `<slot>/.superpowers/sdd/plan_<slug>/progress.md` a reportuje
`progress.lastLine`. Přibude `progress.now` parsovaný z **hlavy** téhož
souboru, a `mb-epic-run status` ho vyrenderuje do české tabulky. Žádný nový
skript, žádná nová evidence.

**Naměřeno u `ums01` (4. 9. 2026), dvakrát nezávisle.** Podruhé blok seděl na
git (`HEAD` v bloku i v gitu `02c293e91`) a — to je ta podstatná část —
**zastihl ho aktuální přesně v tom místě, kde ledger předtím dvakrát selhal**:
mezi přečtením výsledku subagenta a dispatchem dalšího. Dotaz „stojíš, nebo
čekáš?" tím odpadl; blok bez ptaní řekl „čekám na report Tasku 5".

**Opravná vlna: blok SÁM O SOBĚ ji nepřežil, blok S PRAVIDLEM ano.** Naměřeno
u `ums01` 4. 9. 2026 kolem 15:15, a je to nejdůležitější výsledek celé této
části. Blok převzalo druhé sezení od prvního a hned prošlo opravnou vlnou —
a **zaostalo**, přesně jednou a přesně na predikovaném místě: vlna se vrátila,
sezení dispatchlo scoped re-review a **teprve pak** blok přepsalo. To je právě
to pořadí, které hlavička bloku zakazuje.

**Příčina ale nebyla v bloku.** Sezení si vzalo **artefakt bez pravidla, které
ho drží pravdivý** — zkopírovalo tvar, ale ne tu větu o skládání dispatche z
bloku. Vlastní diagnóza toho sezení: *„vzala jsem si nástroj bez disciplíny,
která ho drží pravdivý."* Po doplnění pravidla blok při dvou nezávislých
čteních seděl, včetně stavu „čekám na verdikt re-review".

Z toho plyne návrhové rozhodnutí, které je pro tuto část zásadní: **strukturální
spoušť není ozdoba popisu bloku — je to ta část.** Kdyby se do skillu dostal jen
popis bloku a pravidlo zůstalo v poznámce pod čarou, **reprodukuje se přesně to
selhání, které bylo právě naměřeno.** Blok a jeho pravidlo se nesmí dát převzít
odděleně.

**Hranice fáze naopak přežil.** Blok prvního sezení prošel fetchem, mergem
báze, přeměřením baseline, posouzením průniku cest a dispatchem dalšího tasku —
a byl aktuální. A při dvou `idle` řekl orchestrátorovi bez ptaní, jestli sezení
stojí, nebo čeká na subagenta; jednou stálo, podruhé čekalo a v obou případech
orchestrátor jednal správně napoprvé. **Předtím se musel ptát a ze čtyř odhadů
byly všechny čtyři špatné.**

**Kdo je skutečný adresát bloku — oprava původního zadání.** První verze tohoto
návrhu psala, že se položky volí „pro cizího čtenáře". To je **špatně**, a
opravilo to jedno z těch sezení: **cizí čtenář ten ledger nikdy neuvidí**,
protože SDD workspace se na konci maže a nikdy se necommituje. Skutečným
adresátem je **vlastní nástupkyně po pádu sezení** — a to sezení vzniklo přesně
takhle, jeho předchůdkyně umřela uprostřed tasku. Formulace tedy je:

> Množina položek bloku se volí **pro nástupce, který nemá tvůj kontext.**

Je to užší, konkrétnější a v poolu s krátkou životností sezení je to ten
skutečný případ. (Doplnění: mazání workspace je upstreamový default, který se
dá vědomě přebít — v této session přebit byl, protože ledger nesl rozhodnutí,
jež nikde jinde neexistují. Cizí čtenář tedy není nemožný, jen není ten hlavní.)

**Co zůstává netestované:** sklizeň. Ani jedno sezení jí zatím neprošlo, obě
jsou těsně před ní. `ums01` slíbilo výsledek poslat samo.

### 2. Protokol zpráv

**Pět druhů z praxe, velmi nerovnoměrně hodnotných.** Řazeno podle hodnoty, ne
podle frekvence:

| Druh | Směr | Praxe |
|---|---|---|
| cross-cutting relay | orchestrátor → agent | **nejvyšší hodnota na jednotku textu** |
| eskalace k rozhodnutí | agent → orchestrátor | vzácné, obě měřené byly správné |
| korekce | obousměrně, ale **užitečnější je agent → orchestrátor** | šest za den, pokaždé věcné |
| hlášení na hranicích | agent → orchestrátor | nejčastější, nejmíň zajímavé |
| pobídky | orchestrátor → agent | **z poloviny zbytečné** |

První dva začíná skoro vždy agent, třetí orchestrátor.

**Ústřední pravidlo, a je to nejdražší zjištění celé praxe: zpráva neškodí
přerušením. Škodí tím, že nese autoritu a zapisuje se.** `ums01` dvakrát za
den poslalo věcně **špatné zdůvodnění správného kroku** — jednou vymyšlenou
příčinnost o tom, který task mění kterou větev, podruhé pravidlo bez hranice
platnosti. Obojí by skončilo v ledgeru jako fakt a příští čtenář by podle toho
hledal souvislost, která neexistuje. **Zachytili to agenti, ne orchestrátor.**

Z toho plyne první třída protokolu, ne doporučení:

- Každá zpráva orchestrátor→agent je značená jako **pokyn** nebo **domněnka**.
- Agent má **výslovné právo domněnku odmítnout** a to odmítnutí je normální
  chování, ne konflikt.
- Do ledgeru se domněnka nezapisuje jako fakt; zapisuje se buď jako přijatá
  (a pak s jejím původem), nebo vůbec.

**Relay timing.** Změnu zadání posílej **okamžitě jen tehdy, když příjemce
právě teď jedná podle premisy, kterou to mění**; jinak čekej na hranici.
Rozhoduje **bezprostřednost, ne důležitost** — obojí je z praxe a obojí
dopadlo správně:

- poznatek o testovací technice byl **zadržen** a poslán při uzavírání tasku,
  protože se hodil až o dva tasky dál;
- nález „build po mergi spadne na `CS0246` a není to rozbití" byl poslán
  **okamžitě**, protože druhé sezení bylo minutu před měřením baseline a
  spadlý build by přečetlo jako rozbití od cizího tiketu.

**Dvě věci, které se dělat nemají,** obě naměřené:

- **Nepobízet sezení, které čeká na subagenta.** Stojí to turn a podrývá to
  správné chování. S blokem `NOW` je to poprvé **kontrolovatelné**, ne otázka
  ohleduplnosti — stav je vidět.
- **Nepoužívat `notify_when_idle` po každé zprávě.** Přepisuje si to slot v
  tabulce odběrů; `ums01` z toho dvakrát dostalo „odběr nedrží", což vypadá
  jako umírající sezení.

### 3. Epiková integrační větev

**Reframe, který je potřeba vyslovit první: ta výsada dnes existuje mlčením.**
`pre-push` guard nečte `memory-bank/ums-repo.json` — čte
`$common_dir/ums-protected-branches`, soubor **uvnitř `.git/`**, generovaný
`install-git-hooks.ps1` a **neverzovaný**. Dnešní obsah je `ums-memory-bank`,
`main`, `master`, `develop`, `release/*`, `Branches/*`. Větev jménem
`epic/UMS-3400` **žádný z těch vzorů nesplňuje**, takže ji agent už dnes
pushnout může. Tento návrh tedy **neuděluje novou výsadu — pojmenovává a
ohraničuje výsadu, která tam už je** a která dnes vzniká nedopatřením seznamu.

**Označení: konvence jména,** `epic/<EPIC-KEY>`, aby větev jmenovala epik,
který integruje.

**Co konvenci činí bezpečnou, není to, kdo ji smí založit.** Je to invariant o
úroveň výš:

> **Vlastní bází epikové integrační větve musí být chráněná větev, a push
> epik → báze zůstává člověku.**

Nejhorší, co agent vymyšlením `epic/cokoli` způsobí, je staging navíc — ne
průnik do hlavní linie. Záruka se neruší, jen se posouvá o úroveň výš.

**Řetěz důvěry u konfigurace zůstává, jak je.** Protože guard čte generovaný
soubor v `.git/`, editace `ums-repo.json` na tiketové větvi jeho chování
**nezmění**, dokud neproběhne instalátor. A `$common_dir` znamená, že je to
jeden soubor pro celý pool. Tuto vlastnost návrh nechává nedotčenou.

**Guard se pravděpodobně nemusí měnit vůbec** — `epic/*` už dnes nic
nesplňuje. Práce je proto v **kontraktu** a v **chování skillů**, ne v hooku:

- **Kontrakt** — invariant „integrační větev je vždycky chráněná větev" dostává
  **třetí kategorii**. Dnes je volba nechráněné báze fail-closed STOP s
  předepsanou nápravou; epiková integrační větev se stává legitimní bází, u
  které se ta náprava nespouští. Řádek `Báze:` v `context.md` ji smí jmenovat.
- **`finishing-a-development-branch`** — když je efektivní bází epiková
  integrační větev, **integruje agent sám** a jen to ohlásí. Když je bází
  hlavní integrační větev, předá příkaz člověku jako dnes. Právě tohle ruší to
  zastavení, které při orchestraci několika tiketů dělá z operátora úzké
  hrdlo.

**Jedna nutná podmínka, aby se práce nehromadila neviděná:** epiková větev musí
být svázaná se skutečným epikem — má Jira epik a ledger, takže se objeví v
`mb-epic-graph`. Epiková větev bez epiku je nález, ne zkratka.

### 4. Autonomie o dvou osách

Veličina, kterou operátor nastavuje, je **„kdy agent zastaví a ptá se"** — a
praxe říká, že jedna osa na to nestačí.

**Osa 1: kdy zastavit.** Formulace z praxe:

> Konec turnu je legitimní jen tam, kde čekáš na odpověď člověka nebo na
> doběhnutí subagenta.

Naměřené systematické selhání: sezení zastavovala **mezi dodávkou implementera
a review** — dvakrát u jednoho sezení, jednou u druhého. **Není to vlastnost
agenta, je to vlastnost členění:** dodávka vypadá jako konec turnu, protože je
to konec *něčí* práce.

**Osa 2: kolik zastavit.** Opačný a méně samozřejmý případ, který si našlo jedno
sezení samo — **přeblokování**: čekalo na rozhodnutí člověka a zastavilo
**všechnu** práci, ne jen tu závislou, přitom sklizeň na tom rozhodnutí
nezávisela. Pravidlo:

> Když formuluješ otázku pro člověka, vyjmenuj, co na odpovědi nezávisí, a to
> udělej hned.

**Kde se obě části návrhu potkávají.** Se zprávami má „zastav a zeptej se"
**adresáta**: na část otázek umí odpovědět orchestrátor, ne člověk. Bez zpráv
je jediným adresátem člověk, a proto je dnes každé zastavení drahé. A
automatická integrace tiket → epiková větev je jedno z těch
zastavení, které autonomie ruší.

**Nastavení volí operátor** řádkem v `context.md`, stejným způsobem jako
`Báze:`. Konkrétní množina hodnot patří do implementačního plánu; návrh
rozhoduje **osy**, ne jejich stupnici.

### 5. Unikátnost orchestrátora epiku

**Proč to je až teď potřeba.** Dokud integraci spouštěl člověk, byli dva
orchestrátoři téhož epiku nepořádek. Jakmile epiková integrační větev dovolí agentovi pushovat do
`epic/<EPIC-KEY>` sám, přetahují se o tutéž větev — a protokol zpráv to zhoršuje, protože
si každý z nich píše s týmiž tiketovými sezeními a může jim doručit protikladné
pokyny. Unikátnost se tím stává **předpokladem automatické integrace**, ne
hygienou.

**Klíčové zjištění: mechanismus už existuje a je zdarma.** Git odmítne vyzvednout
tutéž větev ve dvou worktreích jednoho repozitáře. Sloty poolu sdílejí `.git`,
takže **v rámci poolu je držení větve exkluzivní a vynucuje to git sám** — je to
tentýž mechanismus, na který už UMS-3488 spoléhá u tiketových větví („větev tiketu
není vyzvednutá jinde").

Z toho plyne definice, která nepotřebuje registr, lock soubor ani démona:

> **Orchestrátorem epiku je sezení, které drží epikovou elaborační větev.**

A důležitý důsledek, který tu definici činí dostatečnou: **unikátnost je potřeba
jen pro operace, které zapisují** — `spawn` zapisuje řádek záměru do ledgeru,
commituje a pushuje na elaborační větvi. Ty operace už dnes **vyžadují na té
větvi stát**. Čtecí operace (`status`, `attach`) uniká nepotřebují a smí je
spustit kdokoli odkudkoli.

**Dvě tiery, protože git exkluzivita má hranici.** Ta záruka platí mezi
worktreei **jednoho** repozitáře. Dva různé klony si tutéž větev vyzvednout
mohou:

| Rozsah | Mechanismus | Stav |
|---|---|---|
| worktreee jednoho `.git` (celý pool) | git odmítne druhý checkout | existuje, zdarma |
| napříč klony | `mb-doc-index` s deklarovaným záměrem — `KOLIZE AKTIVNÍ PRÁCE`, exit 2 | existuje, používá se |
| **dvě sezení v témže worktree** | **nic** | **díra, viz níž** |

**Ta jediná díra a její uzávěr.** Git nepomůže, když v **jednom** worktree na
téže větvi běží dvě sezení — a přesně tenhle případ „jedno sezení na workspace"
zakazuje prózou. Signál na to ale existuje: `claude agents --json --cwd <cesta>`
vypisuje **i interaktivní** sezení a filtruje se na přítomný `pid`. UMS-3488 ho
používá, ale jen **na sloty, na které se orchestrátor dívá zvenčí** — nikdy sám
na sebe.

Uzávěr je proto **sebekontrola, ne nový mechanismus**: na začátku každé
zapisující operace se orchestrátor zeptá na **svůj vlastní** pracovní adresář a
najde-li víc než jeden záznam s `pid`, je to STOP se jmenovaným důvodem. Platí
tu stejná fail-closed pravidla jako u obsazenosti slotu: nečitelný výstup je
`unknown` a `unknown` **není** „jsem sám".

**Co se záměrně nestaví:**

- **Žádný lock soubor a žádný registr.** Stav se derivuje při každém dotazu —
  totéž rozhodnutí jako u členství v poolu. Lock by navíc přežil spadlé sezení a
  vyrobil by třídu problémů, kterou dnes nemáme.
- **Žádné adresování podle `--name`.** Bylo by lákavé pojmenovat orchestrátory
  `epic/<EPIC-KEY>` a duplikát poznat z `ListAgents` — ale že `--name` peer jméno
  nastavuje, **není ověřené** (viz Rizika), takže by to byla unikátnost postavená
  na neměřeném předpokladu. Až se to změří a bude to platit, je to **druhý,
  nezávislý signál** — přírůstek, ne základ.
- **Žádná unikátnost pro čtecí operace.** Dva orchestrátoři, kteří jen čtou, si
  nepřekáží; blokovat je by bylo omezení bez zisku.

**Zbytková slabina, přiznaná:** mezi sebekontrolou a zápisem je stejné okno
„zkontroluj a jednej", jaké má UMS-3488 mezi kontrolou volnosti slotu a
spuštěním. Zúžit ho lze tím, že sebekontrola proběhne **co nejblíž** zápisu, ne
na začátku dlouhé operace — odstranit ne.

## Rozhodnutí a jejich důvody

| Rozhodnutí | Důvod |
|---|---|
| Blok `NOW` v ledgeru, ne ve vlastním souboru | Druhý domov téhož faktu se rozejde. Ledger navíc už čte `pool-status.ps1`. |
| Blok píše sezení ve slotu, ne orchestrátor | Železné pravidlo z UMS-3488: orchestrátor do pracovního stromu slotu nezapisuje nic. |
| Tahová viditelnost, ne pushované statusy | Model tahu, na kterém stojí celá vrstva; a push status by zastaral přesně tam, kde je potřeba. |
| Značení *pokyn* / *domněnka* jako první třída | Naměřená škoda nebyla přerušení, ale autorita zapsaná do ledgeru. |
| Konvence jména místo seznamu v konfiguraci | Rozhodnutí uživatele. Bezpečnost nese invariant o úroveň výš, ne obtížnost založení větve. |
| Guard se nemění | `epic/*` dnes žádný vzor nesplňuje; měnit hook, který už dělá správnou věc, přidává riziko bez zisku. |
| Metapravidlo o mechanické spoušti není brána | Rozhodnutí uživatele: příliš svazující. Zapsáno jako evidence v Rizicích. |
| Unikátnost orchestrátora derivovaná z držení větve, ne z registru | Git tu exkluzivitu už vynucuje zdarma a UMS-3488 na ni spoléhá u tiketů. Lock soubor by navíc přežil spadlé sezení. |
| Unikátnost jen pro zapisující operace | `spawn` už dnes na elaborační větvi stát musí; čtecí operace si nepřekážejí. |
| Jeden návrh, ne dva | Rozhodnutí uživatele: „kolik zastavit" je stejně tak otázka autonomie jako toho, co se komu posílá. |

## Dopady

**Na UMS-3488.** Nic se nepředělává. `pool-status.ps1` dostává jedno pole,
`mb-epic-run status` jeden sloupec. Odebrání devíti proměnných v
`pool-launch.ps1` je **předpokladem** zpráv, ne překážkou: právě ono dělá ze
spuštěného sezení samostatného peera místo dětského sezení s identitou rodiče.

**Na kontrakt.** Třetí kategorie integračních větví, `Báze:` smí jmenovat
epikovou větev, protokol zpráv a dvě osy autonomie. Je to větší zásah do
Publication Contract a do STOP tříd než UMS-3488.

**Na `finishing-a-development-branch`.** Overlay dostává rozdvojení podle druhu
báze.

**Na unikátnost nic nového nepřidává, jen se o ni opírá.** Dva ze tří tierů
existují a používají se (git exkluzivita větve, meziklonová kolizní kontrola);
nový je jen sebekontrola vlastního pracovního adresáře, a ta používá tentýž
signál `claude agents --json --cwd`, jaký UMS-3488 už volá na sloty. Přírůstek
je tedy jedno volání a jedno pravidlo, ne mechanismus.

**Na ostatní harnessy.** `ListAgents`/`SendMessage` jsou vázané na Claude Code.
Blok `NOW` je čistý Markdown a přenese se; protokol zpráv na jiném harnessu
degraduje na „jediným adresátem je člověk", což je dnešní stav — tedy
fail-closed, ne rozbité.

## Rizika

**Blok `NOW` neprošel místy, kde ledger nejspíš zastarává.** Dvacet minut a dva
doklady. Neprošel opravnou vlnou ani sklizní. Než se na něm postaví rozhodování
orchestrátora, patří to doměřit — `ums01` má před sebou jedenáct tasků, takže
data přibudou sama.

**Blok nikdo cizí nezdědil, a to je jeho účel.** Autorem pravidla i bloku je
totéž sezení, které pravidlo předtím dvakrát porušilo. Užitečnost pro autora
neříká nic o užitečnosti pro cizího čtenáře.

**`--name` peer jméno pravděpodobně nenastavuje — a je to NEOVĚŘENÉ.**
`claude --help` popisuje `-n, --name` jako *display name* pro prompt box,
`/resume` picker a titulek terminálu; **`ListAgents` v tom výčtu není.** Všechna
dnes viditelná peer jména jsou defaulty tvaru `<adresář>-<sufix>`, takže z
pozorování se to rozhodnout nedá. **Nestavět adresování zpráv na `--name`,
dokud to někdo nezmění na měření** — jinak splynutí adresy zprávy a důkazu
spuštění vypadá jako hezká vlastnost a tiše se rozejde. Test je jednořádkový a
je ve Verifikaci.

**Pravidlo bez mechanické spouště se dá odkývat a porušit.** Tři nezávislé
případy z jednoho dne; autor jednoho z těch pravidel ho porušil dvakrát během
odpoledne. Použitelným se stalo teprve s mechanickou spouští nebo spustitelnou
zkouškou. **Uživatel rozhodl, že to NENÍ závazné kritérium tohoto návrhu** —
je to tedy zapsaná evidence a doporučení, ne brána. Kde pravidlo spoušť nemá,
stojí za to to přiznat.

**Artefakt putuje, pravidlo ne — a je to naměřené.** Druhé sezení si vzalo blok `NOW` bez věty, která ho drží pravdivý, a blok okamžitě zaostal. Je to obecnější riziko než blok sám: kdykoli se z tohoto návrhu do skillu dostane TVAR (blok, značka pokyn/domněnka, výčet nezávislé práce) a jeho vynucující pravidlo zůstane vedle, převezme se jen tvar. Konkrétní důsledek pro plán: pravidlo patří do TÉHOŽ odstavce jako artefakt, ne do sousedního.

**Unikátnost orchestrátora stojí na třech mechanismech, z nichž jeden je díra.**
Git exkluzivita pokrývá pool, `mb-doc-index` pokrývá klony, a **dvě sezení v
témže worktree nepokrývá nic než sebekontrola, kterou tento návrh zavádí** —
tedy nejnovější a nejméně prověřená část. Kdyby sebekontrola selhala nebo se ji
někdo rozhodl přeskočit, automatická integrace do epikové větve se stane
nebezpečnou dřív než cokoli jiného v tomto návrhu.

**Konvence jména je sebeudělitelná.** Kdokoli si založí `epic/cokoli`. Vědomé
rozhodnutí; bezpečnost nese invariant „vlastní bází epikové větve je chráněná
větev a epik → báze pushuje člověk". Kdyby se ten invariant někdy oslabil,
padá s ním celá bezpečnost epikové integrační větve.

## Verifikace

1. **Test `--name` — třicet sekund, a udělá ho kdokoli, komu to nic nerozbije.**
   Spustit `claude -n SKODASMS-999` a z jiného sezení zavolat `ListAgents`.
   Objeví-li se peer jako `SKODASMS-999` místo `<adresář>-<sufix>`, `--name` to
   nastavuje. `ums01` test **odmítlo provést samo** — znamenalo by nechat v
   poolu stray interaktivní sezení, které uživatel nezadal, a to je přesně ten
   druh nepořádku, který pak někdo hodinu vyšetřuje. Správný úsudek, ne
   vynechání.
2. **Blok `NOW` čtený nástupcem po pádu sezení.** Sezení, které blok nepsalo a
   nemá kontext svého předchůdce, se z něj musí zorientovat na jedno přečtení.
   **Částečně provedeno a s výsledkem:** převzetí druhým sezením proběhlo a
   fungovalo — ale až po doplnění pravidla, viz bod 3.
3. **Blok `NOW` v opravné vlně — PROVEDENO, a výsledek je podmíněný.** Blok bez
   pravidla vlnu **nepřežil** (re-review dispatchnuto dřív než přepis bloku);
   blok s pravidlem ano. Test se tedy neptá „přežije blok", ale **„dá se blok
   převzít odděleně od pravidla?"** — a odpověď je, že nesmí. Negativně: převzetí
   jen tvaru bez věty o skládání dispatche musí selhat, a selhalo.
4. **Blok `NOW` ve sklizni.** Poslední z hustých míst; **netestováno**, obě
   měřená sezení jsou těsně před ní.
5. **Rozpor bloku a `git log`.** Umělý rozpor musí být detekovatelný pravidlem
   „blok je špatně", ne mlčky přehlédnutý.
6. **Odmítnutí domněnky.** Agent, který dostane značenou domněnku a odmítne ji,
   nesmí ji zapsat do ledgeru jako fakt — a odmítnutí nesmí být hlášeno jako
   konflikt.
7. **Relay timing negativně.** Zpráva poslaná příjemci, který podle měněné
   premisy právě nejedná, se má zadržet na hranici; test na to, že se
   nezadržuje ta, u které příjemce na spadnutí je.
8. **Přeblokování.** Otázka pro člověka musí být doprovázená výčtem toho, co na
   odpovědi nezávisí — a to nezávislé se má opravdu udělat, ne jen vyjmenovat.
9. **Integrace do epikové větve.** Agent integruje sám při epikové bázi a
   předává příkaz při hlavní; negativně: hlavní integrační větev se agentem
   nepushne ani omylem.
10. **Epiková větev bez epiku** je nález `mb-epic-graph`, ne mlčení.
11. **Unikátnost — git tier.** Fixtura se dvěma worktreei jednoho `.git`: druhý
    checkout téže elaborační větve musí git odmítnout. Tohle je důkaz, že se na
    tu záruku smí spoléhat, ne že ji stavíme.
12. **Unikátnost — sebekontrola.** Stub `claude agents --json --cwd <vlastní
    cesta>` vrátí **dva** záznamy s `pid` → zapisující operace je STOP; jeden
    záznam → projde; nečitelný výstup → `unknown`, a `unknown` **není** „jsem
    sám". Negativně: odstranění sebekontroly musí ten dvouzáznamový případ
    zčervenat.
13. **Unikátnost — čtecí operace neuzamčené.** `status` a `attach` musí projít i
    tehdy, když sebekontrola najde druhé sezení; blokovat je by bylo omezení bez
    zisku.

## Pořadí úloh (návrh, ne plán)

Uživatel rozhodl, že viditelnost a protokol zpráv jsou **rovnocenné** a pořadí implementace
rozhodne plán. Věcné závislosti, které plán musí respektovat:

1. **Blok `NOW`** — nezávislý, a dělá pobídkové pravidlo protokolu
   kontrolovatelným. Nejmenší a nejlépe měřitelný.
2. **Protokol zpráv** — značení a relay timing; využívá blok pro „nepobízej
   čekajícího".
3. **Unikátnost orchestrátora** — **musí být hotová dřív než epiková integrační větev**, protože
   ta dovolí agentovi integrovat sám a dva orchestrátoři by se o epikovou větev
   přetahovali. Je malá: sebekontrola plus zápis dvou tierů, které už existují.
4. **Epiková integrační větev** — kontrakt a `finishing`; nezávislá na bloku NOW i na protokolu,
   ale **závislá na unikátnosti**.
5. **Autonomie** — poslední, protože její stupnice se opírá o všechny předchozí:
   adresáta má z protokolu zpráv, odpadlé zastavení z epikové větve a viditelnost z bloku NOW.

## Navazující položky

- **`mb-epic-run` jako domov, nebo ne?** Část 3 a 4 jsou zásahy do kontraktu a
  do `finishing`, ne do skillu poolu. Části 1 a 2 sedí k `mb-epic-run`. Až se
  bude psát plán, patří rozhodnout, jestli to je jeden tiket, nebo dva —
  tenhle návrh to nechává otevřené záměrně.
- **Třetí a čtvrté měření bloku `NOW`** od `ums01`; nabídlo je samo.
- **Doklady v ledgeru epiku SKODASMS-237** — `ums01` je má a nabídlo je k
  vyžádání pro konkrétní sekci.
