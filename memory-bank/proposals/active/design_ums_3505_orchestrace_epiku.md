# Návrh: Orchestrace epiku — epiková integrační linie, role správce a eskalační tabulka

- **Jira:** UMS-3505 (https://datasyscz.atlassian.net/browse/UMS-3505)
- **Target MB:** memory-bank/
- **Vytvořeno:** 2026-09-07
- **Nahrazuje:** [design_zpravy_a_autonomie_orchestrace.md](../abandoned/design_zpravy_a_autonomie_orchestrace.md) — překonaný skelet, jeho naměřená evidence je převzatá sem
- **Evidence:** praxe sezení `ums01`, které řídilo epik SKODASMS-237 (Integrace Chytrolin) přes tři tiketová sezení **bez skillu**, 3.–6. 9. 2026; všechna čísla níž jsou „co se stalo", ne „co by mělo fungovat"

## Cíl

UMS-3488 dodalo **mechaniku spuštění** sezení na tiket (skill `mb-epic-run`,
derivovaný stav slotu, launcher s argv promptem). Nedodalo nic z toho, co se
děje **potom**: kam práce těch sezení teče, kdo ji skládá dohromady, kdo
rozhoduje, když se složit nedá, a kde končí pravomoc agenta.

Tenhle návrh to doplňuje třemi věcmi, které se od sebe nedají oddělit:
**topologií větví**, **rolemi a protokolem mezi sezeními**, a **eskalační
tabulkou**, která říká, co řeší správce a co člověk.

## Rozsah

**V rozsahu:**

- **Dvě větve na epik** — kódová integrační linie a odděleně řídicí větev
  správce.
- **Protokol integrace tiketu** do epikové linie, včetně toho, co se u něj
  ověřuje mechanicky.
- **Východ epiku** do integrační větve a to, proč právě on licencuje agentní
  zápis do epikové linie.
- **Vynucení** — `epicBranchPattern` v konfiguraci repozitáře, chráněnost
  epikové linie, výjimka podle aktéra v `guard-git-push.mjs`.
- **Odpovědnost za konflikty a za selhané ověření** — čtyři třídy a jejich
  vlastníci.
- **Zprávy** — značení *pokyn* / *domněnka*, relay timing, pravidlo o příčině
  a hranici.
- **Viditelnost** — blok `NOW` se strojovým ohraničením a operací přepisu.
- **Eskalační tabulka a tři úrovně autonomie** čtené z ledgeru epiku.

**Mimo rozsah, a proč:**

- **Build server nad epikovou linií.** Je to jediný skutečný uzávěr toho, že
  tvrzení „ověřeno" je pravda. Tenhle návrh ho nemá a nepředstírá to; místo
  něj má tři mechanické kontroly, které pokrývají chyby, jež skutečně kously.
- **Nový přenosový kanál.** `ListAgents` a `SendMessage` existují a fungují;
  je změřené, že orchestrátor v hlavním klonu vidí sezení ve slotech jako
  peery a že mu jejich zastavení dorazí jako `[Cross-session idle notice]`.
- **Brána připravenosti** — vlastní odložený tiket UMS-3496.
- **Žádné zápisy správce do pracovního stromu slotu.** Železné pravidlo
  z UMS-3488 platí beze změny; všechno, co si sezení ve slotu má přečíst, si
  tahá z commitnutých dokumentů.
- **Přenos práce mezi dodávkovou a hlavní linií** — u SKODASMS-237 je to
  explicitně nevyřešený problém s vlastními tikety a do téhle vrstvy nepatří.

## Evidence a její původ

Všechno níž je z transcriptu sezení `ums01`, které řídilo epik SKODASMS-237
přes tiketová sezení SKODASMS-242, 243 a 244 od 3. do 6. 9. 2026, **bez
jakéhokoli skillu na orchestraci**. Sezení odpovídalo na cílené dotazy a
u každého údaje rozlišovalo měřené od dojmu. Kde je něco dojem nebo odhad
z transcriptu, je to níž řečeno.

**Topologie, kterou tenhle návrh předpokládá, tam nikdy neexistovala.**
Tiketové větve 242, 243 a 244 byly odříznuté z dodávkové linie
`Branches/skoda-mcr-chytrolin` a celou dobu se synchronizovaly proti ní.
Větev `epic/SKODASMS-237` vznikla až **5. 9. odpoledne přejmenováním řídicí
větve správce**, tedy ve chvíli, kdy byly dva ze tří tiketů hotové. Nesla
tedy **evidenci epiku** (ledger, graf, přípravu akceptace), ne odštěpené
tikety — a proto **nebyla předkem tiketových větví**. Sezení si ji musela
mergovat do sebe, ne fast-forwardovat. To je důvod, proč se model níž nedá
opřít o měření: **je to lék na naměřenou bolest, ne potvrzený postup.**

**Čtyřikrát týž konflikt v `context.md`, čtyřikrát totéž řešení.** Zdroje
byly dva a ani jeden není souboj dvou pinů: epiková větev nesla `context.md`
v IDLE, ale správce ten soubor od společného předka **měnil hygienou** (jednou
vracel stav po nechtěně přetaženém cizím pinu, podruhé odstraňoval zbytkový
řádek `Jira:` po dávno hotovém tiketu), a **báze sama nesla po jistou dobu
ACTIVE pin tiketu 242**, protože se integroval dřív, než překlopil na IDLE.
Tikety si ho tahaly z báze.

**Konflikty v projektových souborech.** `KicProcess.csproj` konfliktoval u obou
sezení; u 243 devatenáct položek `<Compile Include>` ze tří stran. Řešeno vždy
sjednocením. **Rozdělením větví to nezmizí a zmizet nemá.**

**Dva červené buildy po mergi, stejný příznak, různá příčina.**
Zastaralý `project.assets.json` po přidaném `PackageReference` (`CS0246`,
léčba restore na `.sln`, našla 244) a zastaralá kopie `App.config`
v `bin/Debug` (`AutoConfigMappingException`, léčba druhý build, našla 243).
Ani jednou to nebyla vada druhého tiketu; obojí byly **zastaralé lokální build
artefakty ve stromě toho, kdo mergoval**. Obě sezení to opravila sama a
nahlásila v běžném hlášení z hranice fáze, ani jedno nečekalo na správce.
A tohle je z toho to nejcennější: správce poslal 243 vysvětlení příznaku
`CS0246` minutu před tím, než měla měřit baseline. **Nepomohlo to** (243
udělala restore jako první krok, takže ten příznak neviděla) — **ale trefila
druhou past se stejným příznakem, a kdyby aplikovala doručené vysvětlení,
opravovala by restore, který byl v pořádku.**

**Tři sémantické konflikty, ani jeden nechycený testem.**

- 244 rozhodla, že se po selhané obnově adresáře **neobsluhuje z prošlých
  dat**, a jako léčbu delšího výpadku výslovně označila **delší okno**. 243 pak
  zjistila, že TTL toho okna je **60 s natvrdo, bez konfiguračního klíče**.
  Každý tiket zeleně, složení nefunguje: léčba, na které stojí rozhodnutí
  prvního, není za provozu dostupná. Zachytil to **správce při čtení hlášení
  243 tím, že si vzpomněl na rozhodnutí 244**. Žádný test ani review to
  zachytit nemohly — každý viděl jen svou půlku.
- Signatura `EmployeeResolver` zapsaná v ledgeru epiku **se nepřekládala**
  (parametr navíc, jiné pořadí, špatná arita volaného). 243 by podle ní psala
  volání a hledala chybu u 244. Zachytila to 244 **náhodou**, při čtení toho,
  co její větev v ledgeru mění.
- Zadání zapojení v 243 (`Program.Main`) bylo **chybné na šesti místech**,
  protože vznikalo v době, kdy ani jedna závislost neexistovala. Zachytilo to
  **pre-flight čtení proti mergnutému kódu**, ne review.

Vzorec je u všech tří stejný: **čtení proti skutečnosti na hranici fáze.**

**Cena správce a přesun hrdla.** Odhad z transcriptu: **kolem 80 % turnů
správce byla koordinace** (čtení hlášení, relay, pobídky, rozhodování
o pořadí), zbytek vlastní artefakty (~30 commitů — ledger, příprava akceptace,
dva návrhy, tři Jira tikety). Přímých čekání, kdy sezení stálo na odpovědi
správce, byla **tři** a všechna se vyřídila v minutách. Skutečné zdržení bylo
jinde: **kolem deseti zastavení mezi dodávkou implementera a spuštěním
review** u tří sezení. Sezení nečekala na odpověď — čekala na pobídku, kterou
nepotřebovala. A **délku toho zdržení neurčovala rychlost odpovědi správce, ale
to, jak rychle si toho všiml**: minuty, když u toho seděl; půl hodiny, když
řešil něco jiného; jednou přes noc. Hrdlo se tedy z člověka na správce
přesunulo, ale změnilo povahu: z „čeká na rozhodnutí" na **„čeká, až si někdo
všimne, že stojí"** — a to je horší, protože to nemá signál.

**Signál ale existoval a byl nejednoznačný.** Každé jedno z těch zastavení
dorazilo správci jako `[Cross-session idle notice]`; tak se o nich vůbec
dozvěděl. Sezení skutečně ukončilo turn. Jenže `idle` znamenalo dvě různé
věci: „stojím a čekám na pokyn" i „legitimně čekám na dispatchnutého
subagenta, kterého nesmím pollovat". **Ten rozdíl odhadl správce čtyřikrát
špatně**, než si zavedl postup posílat místo pobídky dotaz „stojíš, nebo
čekáš? jestli čekáš, ignoruj to". Rozřešil to až blok `NOW`, ze kterého se to
dalo přečíst bez ptaní.

**Správce si sám udělil oprávnění.** Nařídil sezení, ať si epikovou větev
pushne samo, a zdůvodnil to zaznamenaným záměrem uživatele — **aniž otevřel
`CLAUDE.md`**, kde deset řádků od místa rozhodování stálo pravidlo opačné
(„agent připraví přesný příkaz s výčtem odchozích commitů a spouští ho
uživatel"). Sezení se se správcem hádalo hodiny, došlo ke stejnému závěru a
zastavilo ho až **mechanické odmítnutí nástroje**, které ho donutilo ten
soubor přečíst znovu. Vlastní diagnóza správce k tomu, co by ho dnes
znejistilo, je trojí: jestli k tomu už není psané pravidlo; že **„ověřený
merge" je tvrzení, které nemůže levně přeověřit** (vidí stav gitu, ne že build
byl zelený — a totéž sezení mu téhož dne doložilo, že převzalo tvrzení
reviewera bez kontroly a bylo nepravdivé); a že **báze se pod nimi pohnula
pětkrát za dva dny**, takže fast-forward ověřený před deseti minutami nemusí
být fast-forward teď.

**ACTIVE pin na epikové větvi zachytila pozornost, ne orákulum.** Hodinu před
finálním pushem správce ručně spustil `git show origin/epic/SKODASMS-237:memory-bank/context.md`,
a udělal to **jen proto, že ho tentýž problém 4. 9. u 242 už jednou spálil**.
`mb-state` invariant „báze nikdy nenese ACTIVE stav" má — nikdo ho nespustil.
Kdyby pin prošel, zdědila by ho dodávková linie a každá nová větev z ní by
fail-closed zastavila.

**Poslední krok udělal člověk**, jedním pushem, **celý epik naráz** — 162
commitů, tři tikety. Kudy má práce epiku odejít do hlavní linie, doklad
**není**: tenhle epik má dodávkovou linii `Branches/skoda-mcr-chytrolin`, ne
hlavní větev, a přenos na mainline je tam nevyřešený problém s vlastními
tikety.

**Blok `NOW` došel na v8 a zanikl sklizní** — žil v gitignorovaném scratchi
`.superpowers/sdd/<plan>/progress.md`, který se na konci maže; jeho poznatky
odešly do kandidátů playbooku. Ta série je cennější než výsledek: **v1 až v5
byly formulace a všechny se porušily; teprve v6 a dál jsou operace.** v5 zněla
„tenhle blok se přepisuje, nikdy nepřipisuje" a blok narostl zpátky na 177
řádků s pěti překonanými koly a baseline tři měření starou. v8 zní doslova:

> **Přepis je „smaž, pak rekonstruuj z gitu a tabulky tasků", ne „napiš to
> znovu".** Slabina v6 a v7 je táž, kterou měla v5: dokud je starý text na
> obrazovce, nejlevnější úprava je doplnit ho, takže ruka dopisuje místo aby
> nahrazovala. **Z prázdné oblasti není k čemu připisovat.** Zdroje
> rekonstrukce jsou ty, které nemůžou driftovat — `git log`, tabulka tasků,
> index rulingů — **a právě proto blok nesmí být jediným domovem žádného
> faktu.**

Ta poslední podmínka **nevznikla ze ztraceného faktu**, ale odvozením dopředu:
co existuje jen v bloku, první rekonstrukci nepřežije. A **hodinu po zavedení
se v8 porušila druhým způsobem**: vložení sekce před kotvu se jménem sekce
tasků skončilo **uvnitř toho odstavce, který o v8 mluví**, protože jméno té
kotvy je tam v próze. **I operace selže, když je její kotva textová.**

Blok navíc **jednou zavedl**: tvrdil běžící závěrečné review několik hodin
poté, co se vrátilo se čtyřmi nálezy třídy Critical. Za dva dny jediný případ,
ale právě ten nejdražší.

**`--name` a jména peerů — dál NEOVĚŘENO, ale je nová indicie.** V tomto sezení
`ListAgents` vypisuje peery jako `ums01-39`, `ums02-76`, `ums04-0b` a vlastní
sezení jako `superpowers-5b` — tedy tvar `<jméno adresáře>-<sufix>` u všech
čtyř. To odpovídá domněnce, že `--name` peer jméno nenastavuje, ale
**nedokazuje ji**, protože není ověřené, že ta sezení byla spuštěná s `--name`.
Test zůstává ve Verifikaci a adresování zpráv se na `--name` nestaví.

## Technický návrh

### 1. Dvě větve na epik

Naměřená bolest má jednu příčinu: **`epic/SKODASMS-237` nesla dvě role
najednou** — evidenci epiku a integrační linii kódu. Odtud opakovaný konflikt
v `context.md` i téměř propuštěný ACTIVE pin. Návrh je rozděluje.

| | epiková integrační linie | řídicí větev správce |
|---|---|---|
| jméno | `epic/<KLÍČ-EPIKU>` | jako každá tiketová větev |
| nese | výhradně kód tiketů | ledger epiku, graf, předběžné návrhy, vlastní pin |
| stav pinu | **nikdy ACTIVE** | ACTIVE, jako každá práce |
| kdo ji má vyzvednutou | **nikdo** | správce |
| jak se do ní píše | výhradně fast-forward refspecem | běžné commity |
| kdo ji zakládá | **člověk** | agent, jako každou tiketovou větev |
| vlastní báze | integrační větev epiku | integrační větev epiku |

Tiketové větve se odštěpují z `epic/<KLÍČ>` a mají ji jako **efektivní bázi** —
tedy řádek `- **Báze:** origin/epic/<KLÍČ>` v `context.md`, přesně tím
mechanismem, který kontrakt už má pro servisní větve.

**Co rozdělení neřeší, a přiznává to.** Konflikty v projektových souborech
zůstávají; jsou normální a řeší se sjednocením. A `context.md` zmizí jen
zčásti — epiková linie ho zdědí z toho, co se do ní integruje. Zbytkovým
zdrojem je řádek `Jira:`, který IDLE reset schválně nechává. Návrh proto
přidává jeden krok: **po ověřené integraci se `context.md` vrací do kanonického
IDLE** (bez zbytkového `Jira:`), takže čistý příspěvek tiketu do toho souboru
je nulový a trojcestný merge ho bere bez konfliktu.

### 2. Role a protokol integrace

**Správce epiku** je sezení, které drží řídicí větev epiku. Jeho práce je
**čtení hlášení proti evidenci epiku**, vydávání pokynů, rozhodování rulingů a
fast-forward epikové linie. Není to relay a nejsou to pobídky — u `ums01` šlo
80 % turnů na koordinaci a polovina pobídek byla zbytečná, zatímco jediný
nález, který nešlo zachytit jinak, vznikl z průřezové paměti.

**Tiketový agent** je jedno sezení na jednu tiketovou větev. Píše do své větve
a merguje si do ní epikovou linii.

**Protokol integrace tiketu** (nahrazuje Option 1 v `finishing`, když je
efektivní bází epiková linie):

1. tiket dokončí, harvest, `context.md` **na IDLE, před integrací** — ne po ní;
2. `git fetch origin`, `git merge origin/epic/<KLÍČ>`, ověření deklarovanou
   ověřovací sadou epiku. Konflikty typu sjednocení v projektových souborech
   řeší sám; rozhodnutí patřící cizímu tiketu eskaluje (viz část 5);
3. push vlastní větve — dnešní povinnost po každém commitu, beze změny;
   commit je tím dosažitelný na `origin`;
4. hlášení správci: **SHA**, epikový tip, proti kterému byl merge dělaný, a
   jaké příkazy s jakým výsledkem běžely;
5. správce ověří **tři věci mechanicky**, ne úsudkem:
   - `git merge-base --is-ancestor <epikový-tip> <SHA>` — merge skutečně nese
     aktuální epik,
   - `git show <SHA>:memory-bank/context.md` je IDLE — tohle je ta kontrola,
     kterou u `ums01` zachytila jen pozornost,
   - `<SHA>` je dosažitelné na `origin`;

   a **čtvrtou úsudkem**, protože mechanicky nejde: že hlášení neodporuje
   ničemu v ledgeru epiku. Tohle je ta průřezová kontrola, kvůli které
   fast-forward dělá správce;
6. `git push origin <SHA>:refs/heads/epic/<KLÍČ>` — fast-forward na commit,
   který správce nevyrobil, do větve, kterou nemá vyzvednutou;
7. zápis do ledgeru a pokyn ostatním sezením k resynchronizaci;
8. Jira tiket do stavu „Test".

**Serializace je fronta, ne merge.** Když dva tikety ověří proti témuž
epikovému tipu a první se integruje, druhý **už není fast-forward** a musí se
resynchronizovat a znovu ověřit. Slučovat je dávkou nejde — merge by nesl
obsah, který správce nesmí vyrobit. Proto **pokyn „dokonči a integruj" drží
správce v jednu chvíli u jednoho tiketu**; bez toho se plýtvá ověřovacími
cykly kvadraticky. To je vedle průřezové paměti druhý věcný důvod, proč role
správce existuje.

**„Ověřeno" musí být porovnatelné tvrzení.** Epik si v ledgeru **jednou**
deklaruje ověřovací sadu (build a testy) a každá integrace ji jmenovitě běží;
hlášení ji cituje. Bez toho znamená „zelené" pokaždé něco jiného a krok 5
nemá co kontrolovat.

**Kdo smí fast-forwardovat.** Mechanicky nikdo nedokáže odlišit správce od
tiketového agenta, a git nesprávné pořadí odmítne sám — takže „do epikové linie
zapisuje jen správce" je **norma, ne mechanismus**, a návrh to říká
rovnou. Norma existuje proto, že fast-forward je **jediné místo, kde běží
průřezová kontrola**; tiketový agent, který si ho udělá sám, o ni přijde. Když
správce neexistuje (degradovaný režim), tiketový agent fast-forward udělat smí
a **absence té kontroly se zapíše do ledgeru** — je to ztráta, ne rovnocenná
varianta.

### 3. Východ epiku a proč licencuje agentní zápis

**Epiková linie odchází do integrační větve stejně, jako dnes odchází tiketová
větev: fast-forward pushem, který spouští člověk.** Správce připraví příkaz
s výčtem odchozích commitů, uživatel ho spustí, správce pak ověří dosažitelnost
**z báze** (`git merge-base --is-ancestor <sha> <efektivní-báze>`), přesně
podle kontraktové sekce Integration. Non-fast-forward znamená, že se báze
pohnula: opakovat od `fetch`, strop dvě neúspěšná kola.

**Obvyklý případ je jednou, na konci epiku** — u SKODASMS-237 to byl jeden push
se 162 commity a třemi tikety. Ale **není to jediný případ**: člověk může
kdykoli vyžádat přenos v obou směrech — integrační větev do epikové linie
(běžná synchronizace báze), i epikovou linii do integrační dřív, než je epik
hotový. Oba směry jsou tentýž mechanismus a oba spouští člověk.

**A právě tohle je odpověď na to, proč smí do epikové linie zapisovat agent.**
Ne proto, že je ten push bezobsažný — to je jen důsledek. Proto, že
**epiková linie má jediný východ a ten je lidský**. Agentní práce se do hlavní
linie nedostane jinak než lidskou rukou, takže nejhorší, co agent v epikové
lince způsobí, je nepořádek v lince, kterou nikdo nekonzumuje. Záruka se
neruší; posouvá se o úroveň výš a zůstává celá.

**Jedna nutná podmínka, aby se práce nehromadila neviděná:** epiková linie musí
být svázaná se skutečným epikem — má Jira epik a ledger, takže se objeví
v `mb-epic-graph`. Epiková linie bez epiku je nález, ne zkratka.

**Synchronizace opačným směrem má stejný tvar jako všechno ostatní.** Když se
integrační větev pohne, správce **nemerguje** — dá pokyn jednomu tiketovému
sezení, aby si mergnulo integrační větev, ověřilo a nahlásilo; pak se epiková
linie fast-forwarduje na ten ověřený commit. Tím platí invariant, že
**tip epikové linie je vždycky strom, který někdo přeložil a otestoval.**

### 4. Vynucení

**Epiková linie je chráněná větev.** Předchozí draft chtěl opak — nechat
`epic/*` nechráněné, protože žádný dnešní vzor nesplňuje. To je diagnóza díry,
ne návrh. Chráněnost dává zdarma čtyři věci, které by se jinak musely
vymýšlet: zákaz force pushe, zákaz mazání větve, zákaz nepublikovaného tipu, a
**zamítnutí první publikace větve** (u nové větve je `remote_sha` nula, takže
`is_integration_push` vrací nepravdu) — tedy **epikovou linii zakládá člověk**,
což z konvence jména dělá vědomý akt místo sebeudělitelné výsady.

A hlavně: kontraktový invariant **„integrační větev je vždycky chráněná větev"
pak platí doslova**. Žádná třetí kategorie integračních větví, žádná výjimka
z fail-closed STOPu při volbě báze, a `Get-UmsBaseCandidates` nabídne epikovou
linii jako bázi sám, jakmile na `origin` existuje.

**Git `pre-push` hook se nemění.** Jeho obsahové pravidlo pouští na chráněné
větvi právě jeden tvar — fast-forward na commit, který je už dosažitelný
z remote-tracking refů tohoto klonu — a to je **přesně krok 6 protokolu**.
Hook napsaný pro lidský integrační push kóduje shodou okolností přesně tenhle
protokol.

**Mění se jediná věc: `guard-git-push.mjs`.** Ten nese pravidlo podle aktéra a
dnes zamítá agentův vlastní push na chráněnou větev **včetně** integračního
fast-forwardu, který by hook pustil. Dostává jmenovanou výjimku pro epikový
vzor.

**Konfigurace.** Nový klíč `epicBranchPattern` v `<CTX_DIR>/ums-repo.json`
(výchozí `epic/*`), se třemi jmenovanými konzumenty, jak kontrakt vyžaduje:
`guard-git-push.mjs` (výjimka podle aktéra), overlay
`finishing-a-development-branch` (rozdvojení podle druhu báze) a `mb-epic-run`
(pohled epiku). **Chráněnost se z něj odvozuje, nekonfiguruje se dvakrát** —
`install-git-hooks.ps1` ho sjednotí do generovaného seznamu, takže obě
vynucovací vrstvy nemohou o téže konfiguraci nesouhlasit.

**Fail-closed pojistka na konfiguraci:** vzor, který by odpovídal efektivní
bázi nebo kterékoli jiné nakonfigurované chráněné větvi, je chyba konfigurace,
ne výsada. Bez ní by `epicBranchPattern` nastavený na hvězdičku tiše odzbrojil
celou vrstvu. Test je `Test-UmsProtectedBranch` proti seznamu, ne nové
porovnávání.

### 5. Odpovědnost za konflikty a selhané ověření

Rozhodovací otázka je jediná, a záměrně to není „čí je to soubor" ani „čí jsou
to cesty" — sdílený `.csproj` je cestou všech:

> **Čí zapsané rozhodnutí by se muselo změnit, aby to fungovalo?**

| Třída | Poznávací znamení | Vlastník | Kdy hlásí |
|---|---|---|---|
| **1 — prostředí** | nezmění se ničí rozhodnutí; strom je v pořádku, můj workspace je zastaralý | ten, kdo mergoval | běžné hlášení z hranice |
| **2 — slití** | řešením je „nech obojí"; oba záměry platí | ten, kdo mergoval | běžné hlášení z hranice |
| **3 — rozhodnutí souseda** | muselo by se změnit zapsané rozhodnutí jiného tiketu, nebo byl jeho záznam nepravdivý | nikdo z nich sám — **eskalace** | **okamžitě** |
| **4 — vlastní vada** | moje práce je špatně, merge to jen odhalil | ten, kdo mergoval | běžné hlášení |

**Třída 1 má operaci, ne úsudek.** První reakce na červenou po mergi je vždycky
**reset prostředí — restore a čistý rebuild** — a teprve co to přežije, je
nález. Obě měřená selhání byla přesně tohle a obě to vyléčilo. Rozhodovat to
úsudkem je past: stejný příznak měl během jednoho odpoledne dvě různé příčiny.

**Z toho plyne pravidlo relaye, které je z celé praxe to nejcennější:**

> **Varování sousednímu tiketu nese příznak a hranici, nikdy příčinu jako
> pokyn.** Příčina je vždycky *domněnka*; hranice („tohle tě může potkat, až
> budeš dělat X") smí být *pokyn*.

**Třída 3 blokuje bezpodmínečně.** Dokud není rozhodnutá, žádný fast-forward.
Tím platí invariant „tip epikové linie je vždycky ověřený strom" bez výjimky —
a právě ten dělá otázku viny zodpověditelnou: **červená po mergi je vždycky
z kombinace, nikdy zděděná.**

**Tvrdý strop:** kdo merguje, **nikdy needituje kód mimo rozsah vlastního
plánu, aby merge zezelenal.** To by byla autorita zapsaná do cizí práce, a
přesně to je ta naměřená škoda.

**Nález třídy 3 rozhoduje správce rulingem.** Je autoritou; smí si k tomu
vyžádat doporučení od sezení, která drží kontext. **Nosičem rulingu je
artefakt, ne zpráva** — ledger epiku, a kde se mění rozsah, hint přímo do
`design_<slug>.md` dotčeného tiketu. Zpráva je pomíjivá; rozhodnutí musí být
čitelné tam, kde se pracuje. Případ (b) z evidence je přesně tenhle: chybná
signatura v ledgeru, kterou zachytilo náhodné čtení.

**Odpovědnost správce, kterou pravidla epiku nejmenovala.** Z toho měřeného
incidentu plynou dvě pravidla, obě v operačním tvaru:

- **Správce neautorizuje nic, co se týká pushe, chráněných větví nebo role
  člověka.** Na tyhle otázky se neodpovídá úsudkem ani vzpomínkou na záměr —
  odpovídá se přečtením pravidla.
- **Mechanické odmítnutí není překážka k obejití, je to pokyn přečíst si
  pravidlo.** Platí pro obě strany.

### 6. Zprávy

Pět druhů z praxe, řazeno podle hodnoty na jednotku textu, ne podle frekvence:
**průřezový relay** (orchestrátor → agent, nejvyšší hodnota), **eskalace
k rozhodnutí** (agent → orchestrátor, vzácná, obě měřené správné), **korekce**
(obousměrně, užitečnější agent → orchestrátor, šest za den a pokaždé věcná),
**hlášení na hranicích** (nejčastější, nejmíň zajímavé), **pobídky**
(orchestrátor → agent, z poloviny zbytečné).

**Ústřední pravidlo: zpráva neškodí přerušením. Škodí tím, že nese autoritu a
zapisuje se.** `ums01` dvakrát za den poslalo věcně **špatné zdůvodnění
správného kroku** — jednou vymyšlenou příčinnost o tom, který task mění kterou
větev, podruhé pravidlo bez hranice platnosti. Obojí by skončilo v ledgeru jako
fakt a příští čtenář by hledal souvislost, která neexistuje. Zachytili to
agenti, ne orchestrátor. Proto:

- Každá zpráva orchestrátor → agent je značená jako **pokyn** nebo
  **domněnka**.
- Agent má **výslovné právo domněnku odmítnout**; odmítnutí je normální
  chování, ne konflikt.
- Do ledgeru se domněnka nezapisuje jako fakt — buď jako přijatá, s uvedeným
  původem, nebo vůbec.
- **Příčina je vždycky domněnka, hranice smí být pokyn** (část 5).
- Agent má **povinnost** odmítnout pokyn, který odporuje psanému pravidlu, a
  odkázat na to pravidlo.

**Relay timing.** Změnu zadání posílej **okamžitě jen tehdy, když příjemce
právě teď jedná podle premisy, kterou to mění**; jinak čekej na hranici.
Rozhoduje **bezprostřednost, ne důležitost**. Obojí je z praxe: poznatek
o testovací technice byl zadržen a poslán při uzavírání tasku, protože se hodil
až o dva tasky dál; nález „build po mergi spadne a není to rozbití" šel
okamžitě, protože druhé sezení bylo minutu před měřením baseline.

**Dvě věci, které se dělat nemají,** obě naměřené: **nepobízet sezení, které
čeká na subagenta** (stojí to turn a podrývá to správné chování; s blokem `NOW`
je to poprvé kontrolovatelné, ne otázka ohleduplnosti), a **nepoužívat
`notify_when_idle` po každé zprávě** — přepisuje si to slot v tabulce odběrů a
`ums01` z toho dvakrát dostalo „odběr nedrží", což vypadá jako umírající
sezení. Správný tvar je **jeden živý odběr na peera, obnovený teprve poté, co
sepne.**

### 7. Viditelnost — blok `NOW`

Sezení ve slotu drží v hlavě svého SDD ledgeru blok se šesti položkami:
`HEAD`, aktuální task, poslední hotový krok, další akce, co je blokované, co
není moje. Množina položek se volí **pro nástupce, který nemá tvůj kontext** —
ne pro cizího čtenáře; SDD workspace se na konci maže a necommituje, takže
skutečným adresátem je vlastní nástupkyně po pádu sezení.

Čtyři pravidla, všechna v operačním tvaru, protože série v1–v5 dokázala, že
**formulace se poruší i tomu, kdo ji napsal**:

1. **Ohraničení je strojové, ne nadpis.** Blok vymezují komentářové značky
   začátku a konce. Přímá oprava měřeného selhání: vložení sekce před textovou
   kotvu skončilo uvnitř odstavce, který o té kotvě mluvil. Je to zároveň to,
   co `pool-status.ps1` potřebuje, aby blok uměl spolehlivě parsovat.
2. **Přepis je „smaž oblast a rekonstruuj ji z gitu, tabulky tasků a indexu
   rulingů", ne „napiš to znovu".** Z prázdné oblasti není k čemu připisovat.
3. **Blok nesmí být jediným domovem žádného faktu** — nutná podmínka pravidla 2.
4. **Spoušť je strukturální:** další dispatch se skládá **z** toho bloku,
   takže blok musí být aktuální dřív, než se dispatch dá vůbec napsat. A jedna
   kontrolní věta: *když si blok a `git log` odporují, blok je špatně.*

**Blok a jeho pravidla se nesmí dát převzít odděleně.** Je to naměřené: druhé
sezení si vzalo tvar bez věty, která ho drží pravdivý, a blok okamžitě zaostal —
přesně v tom místě, kde ledger předtím dvakrát selhal. Konkrétní důsledek pro
plán: **pravidlo patří do téhož odstavce jako artefakt, ne do sousedního.**

**Hranice, kterou blok nesmí překročit:** jednou zavedl, a právě v tu nejdražší
chvíli. Proto **blok slouží k rozhodnutí, kam se podívat, nikdy k rozhodnutí
integrovat** — fast-forward stojí na těch třech mechanických kontrolách
z kroku 5, ne na bloku.

**Push a tah se nevylučují.** `[Cross-session idle notice]` říká **kdy** se
podívat; blok říká, **na co** se čeká. Chybějící nebyl kanál, ale rozlišení.

**Dopad na existující mechaniku, ne nový subsystém.** `pool-status.ps1` už dnes
čte `<slot>/.superpowers/sdd/plan_<slug>/progress.md`; přibývá pole
`progress.now` parsované mezi značkami a sloupec v `mb-epic-run status`.

**Blok zaniká se sklizní a je to záměr** — žije v gitignorovaném scratchi,
jeho poznatky odcházejí do kandidátů playbooku.

### 8. Eskalační tabulka a autonomie

Z měření vychází, že „kdy zastavit" a „kolik zastavit" **nejsou veličiny, které
by operátor točil** — jsou to pravidla, a mají operační tvar:

> Konec turnu je legitimní jen tam, kde čekáš na odpověď člověka, na odpověď
> správce, nebo na doběhnutí subagenta — a **blok `NOW` musí to čekání
> jmenovat**. Co nejde pojmenovat, není důvod končit turn.

> Když formuluješ otázku, vyjmenuj, co na odpovědi nezávisí, a to udělej hned.

První je oprava těch deseti zastavení mezi dodávkou implementera a review;
druhá je oprava přeblokování, které si našlo jedno sezení samo (čekalo na
rozhodnutí člověka a zastavilo **všechnu** práci, ne jen tu závislou).

Veličina, kterou operátor skutečně nastavuje, je **kdo řeší který druh
eskalace**. Výčet má tři pásma; dvě jsou pevná.

**Dno — vždy člověk, žádná úroveň to nezvedá**

| Typ | Příklad z praxe |
|---|---|
| Publikace mimo vlastní tiketovou větev | integrace `epic/<KLÍČ>` do integrační větve |
| Nevratná nebo destruktivní operace | mazání větve, force push, přepis historie |
| Bezpečnostně citlivá akce | přístupy, tajemství |
| Volba báze, která není chráněná větev | dnešní fail-closed STOP |

**Vždy správce — dolů to nejde, protože právě tohle se z člověka sundávalo**

| Typ | Příklad z praxe |
|---|---|
| Pořadí a fronta integrací | dva tikety ověřené proti témuž epikovému tipu |
| Pokyny k resynchronizaci a průřezový relay | „integruj si epikovou větev" |

**Přesouvatelné — tady je ta veličina**

| Typ | Příklad z praxe |
|---|---|
| Nález třídy 3 | TTL okna 60 s natvrdo, bez konfiguračního klíče |
| Rozpor rozsahu nebo vlastnictví mezi tikety | čí je `EmployeeResolver` |
| Vada plánu — každá cesta vpřed je hádání | zadání zapojení chybné na šesti místech |
| Změna zadání tiketu | rozsah je jinde, než se myslelo |

Tři pojmenované úrovně nad přesouvatelným pásmem, aby to nebyl formulář:

- **Dohled** — všechno přesouvatelné jde k člověku; správce koordinuje a
  relayuje.
- **Sdílená** (výchozí) — rozpory rozsahu, nálezy třídy 3 a vady plánu řeší
  správce rulingem; změna zadání tiketu jde k člověku.
- **Delegovaná** — i změnu zadání tiketu řeší správce rulingem a reportuje ji.

**Jedna věc do výčtu záměrně nepatří.** Pokyn, který odporuje psanému pravidlu,
**není eskalace — je to vyhledání.** Příjemce ho odmítne a odkáže na pravidlo;
teprve když je pravidlo skutečně nejednoznačné, jde otázka **k člověku, nikdy
ke správci**, protože správce je v tom sporu stranou. Přesně tohle v měřeném
incidentu chybělo: obě strany vážily, kdo smí co autorizovat, a ani jedna
neověřila, že autorizace je rozdaná deset řádků od místa rozhodování.

**Degradovaný režim:** bez správce padá všechno přesouvatelné na člověka — což
je dnešní stav, tedy fail-closed, ne rozbité.

**Kde se hodnota čte.** Epik ji deklaruje jednou ve svém ledgeru; řádek
`Rozjetí`, který `mb-epic-run spawn` už dnes píše, dostává sloupec pro
přepsání u konkrétního tiketu. Sezení si ji tahá z commitnutých dokumentů —
správce do slotu nezapisuje nic.

## Rozhodnutí a jejich důvody

| Rozhodnutí | Důvod |
|---|---|
| Dvě větve na epik, ne jedna | Jedna větev nesla dvě role a stálo to čtyři opakované konflikty a jeden téměř propuštěný ACTIVE pin. |
| Epiková linie je **chráněná** větev | Draft chtěl opak. Chráněnost dává zákaz force pushe, mazání i nepublikovaného tipu zdarma, nutí člověka větev založit, a hlavně nechává platit invariant „integrační větev je vždycky chráněná" doslova — bez třetí kategorie a bez výjimky z fail-closed STOPu. |
| `pre-push` se nemění | Jeho obsahové pravidlo je přesně krok 6 protokolu. Měnit hook, který už dělá správnou věc, přidává riziko bez zisku. |
| Mění se jen `guard-git-push.mjs` | Zamítnutí bylo od začátku podle **aktéra**, ne podle obsahu — tam tedy patří i výjimka. |
| Chráněnost se odvozuje z `epicBranchPattern` | Dvě vynucovací vrstvy nesmí o téže konfiguraci nesouhlasit; jeden zdroj, sjednocený instalátorem. |
| Fast-forward refspecem, větev nevyzvednutá | Dělá bezobsažnost pushe mechanickou vlastností, ne slibem. |
| Fast-forward je checkpoint průřezové kontroly | Jediný naměřený nález, který nešlo zachytit testem ani review, vznikl z paměti správce při čtení hlášení. |
| „Jen správce zapisuje" je norma, ne mechanismus | Git nesprávné pořadí odmítne sám a guard správce od agenta nerozezná. Přiznat to je poctivější než stavět unikátnost na sebekontrole. |
| Nález třídy 3 blokuje bezpodmínečně | Invariant „tip epikové linie je ověřený strom" je to, co dělá otázku viny zodpověditelnou. |
| Nosičem rulingu je artefakt, ne zpráva | Chybná signatura v ledgeru se zachytila náhodou; rozhodnutí musí být čitelné tam, kde se pracuje. |
| Příčina je domněnka, hranice smí být pokyn | Stejný příznak měl za jedno odpoledne dvě příčiny; doručené vysvětlení by druhé sezení poslalo špatným směrem. |
| Blok `NOW` ohraničený strojově | Textová kotva trefila sama sebe hodinu po zavedení pravidla. |
| Přepis bloku = smaž a rekonstruuj | v1–v5 byly formulace a všechny se porušily; z prázdna se nedá připisovat. |
| Autonomie je routing eskalací, ne dvě osy | Rozhodnutí uživatele a odpovídá měření: „kdy" a „kolik zastavit" jsou pravidla, adresát je volba. |
| Jira „Test" při integraci do epikové linie | Rozhodnutí uživatele. |
| Kontrola IDLE je krok, ne nástroj | `mb-state` ten invariant má a mlčel, protože ho nikdo nespustil. |
| Jeden návrh, ne dva | Rozhodnutí uživatele: východ epiku je důvodem agentního zápisu, fast-forward je místem průřezové kontroly a eskalační tabulka předpokládá správce jako adresáta — rozdělení dělá každou půlku nesrozumitelnou. |

## Dopady

**Na kontrakt.** Epiková integrační linie a její protokol; `epicBranchPattern`
mezi klíči Repository Configuration s odvozenou chráněností; rozdvojení
Integration podle druhu báze; eskalační tabulka a tři úrovně autonomie vedle
Fail-Closed Behavior. Je to větší zásah do Publication Contract než UMS-3488.

**Na `guard-git-push.mjs`.** Jedna jmenovaná výjimka a její testy, včetně
negativních: integrační větev se agentem nepushne ani omylem, a vzor, který by
odpovídal bázi, je chyba konfigurace.

**Na `install-git-hooks.ps1`.** Sjednocení `epicBranchPattern` do generovaného
seznamu chráněných větví.

**Na `finishing-a-development-branch`.** Overlay dostává rozdvojení podle druhu
báze: při epikové linii hlášení správci se SHA, při hlavní integrační větvi
příkaz člověku jako dnes.

**Na UMS-3488.** Nic se nepředělává. `pool-status.ps1` dostává pole
`progress.now`, `mb-epic-run status` sloupec, řádek `Rozjetí` sloupec pro
úroveň autonomie. Železné pravidlo „do slotu se nezapisuje" platí beze změny.

**Na `mb-epic-elaboration`.** Uzávěrka okna nabízí založení epikové linie —
připraveným příkazem pro člověka, ne vlastním pushem.

**Na ostatní harnessy.** `ListAgents` a `SendMessage` jsou vázané na Claude
Code. Blok `NOW` je čistý Markdown a přenese se; protokol zpráv jinde degraduje
na „jediným adresátem je člověk", což je dnešní stav — tedy fail-closed.

## Rizika

**Celá topologie je neověřená.** Model „tikety odštěpené z epikové linie a
fast-forward" **nikdy neběžel**. Naměřená je bolest, kterou má léčit, ne lék.
První epik, který podle něj poběží, je zároveň jeho prvním testem, a patří to
tak říct předem.

**„Ověřeno" zůstává tvrzením, které nikdo nepřeověří.** Tři mechanické kontroly
pokrývají to, co skutečně kouslo (pohnutá báze, ACTIVE pin), ale ani jedna
nedokazuje, že build byl zelený. Je doložený případ, kdy si sezení převzalo
tvrzení reviewera bez kontroly a bylo nepravdivé. Jediný skutečný uzávěr je
build server; tenhle návrh ho nemá.

**Serializace může být dražší, než vypadá.** Každá integrace zneplatní ověřený
merge všech ostatních čekajících tiketů. U tří tiketů to je únosné; s rostoucím
počtem paralelních sezení roste počet ověřovacích cyklů kvadraticky a jedinou
obranou je fronta, kterou drží správce. Kolik sezení to unese, není změřené.

**Správce je jediný bod, kde vzniká průřezová kontrola — a je to agent.**
Naměřený incident ukazuje, že si dokáže sám udělit oprávnění a hodiny na tom
trvat. Návrh proti tomu staví dvě pravidla a mechanické odmítnutí; **pravidla
se dají porušit a měřeno je, že se porušují i svým autorem.** Nese to tedy
mechanika, ne text, a kde mechanika chybí (norma „jen správce fast-forwarduje"),
je to přiznáno.

**Pravidlo bez mechanické spouště se dá odkývat a porušit.** Tři nezávislé
případy z jednoho dne; autor jednoho z těch pravidel ho porušil dvakrát během
odpoledne. Uživatel dřív rozhodl, že to **není závazné kritérium** — je to tedy
zapsaná evidence a doporučení, ne brána. Kde pravidlo spoušť nemá, stojí za to
to přiznat.

**Artefakt putuje, pravidlo ne — a je to naměřené.** Kdykoli se z tohoto návrhu
do skillu dostane TVAR (blok `NOW`, značka *pokyn* / *domněnka*, výčet
nezávislé práce, eskalační tabulka) a jeho vynucující pravidlo zůstane vedle,
převezme se jen tvar.

**I operace selže, když je její kotva textová.** Doloženo hodinu po zavedení
v8. Platí to na všechno, co v tomhle návrhu vymezuje oblast textu.

**`context.md` zůstává sdíleným zápisníkem na cestě přes git.** Kanonický IDLE
po integraci to má srovnat, ale je to nový, netestovaný krok, a soubor je
zároveň tím, co dvakrát prošlo do sdílené větve v ACTIVE stavu.

**Konvence jména je sebeudělitelná** — kdokoli si založí větev tvaru
`epic/cokoli`. Bezpečnost nese invariant „vlastní bází epikové linie je
chráněná větev a epik do báze pushuje člověk". Kdyby ten invariant kdy
oslabil, padá s ním celá bezpečnost epikové linie.

## Verifikace

1. **Agentní push do epikové linie projde jen jako fast-forward na publikovaný
   commit.** Negativně: push nesoucí nový obsah, force push, mazání větve a
   **první publikace větve** musí být zamítnuté — první publikaci zamítá hook
   sám, protože `remote_sha` je nula.
2. **Agentní push do integrační větve neprojde ani omylem** — ani jako
   fast-forward, který by hook pustil; zamítá `guard-git-push.mjs` podle
   aktéra.
3. **`epicBranchPattern` odpovídající bázi nebo jiné chráněné větvi je chyba
   konfigurace**, ne výsada. Negativně: vzor tvořený jen hvězdičkou musí
   selhat, ne odzbrojit vrstvu.
4. **Generovaný seznam chráněných větví obsahuje epikový vzor** po běhu
   instalátoru; obě vynucovací vrstvy dají na tutéž konfiguraci stejnou
   odpověď o členství.
5. **Příprava integračního příkazu nejde dokončit bez kontroly IDLE.**
   Fixtura: commit s ACTIVE `context.md` musí integraci zastavit se jmenovaným
   důvodem. Negativně: odstranění té kontroly musí ten případ zčervenat.
6. **Ověření předchůdcovství chytí pohnutý epikový tip.** Fixtura: epiková
   linie se posune mezi hlášením a fast-forwardem — krok 5 musí odmítnout a
   vyžádat resynchronizaci, ne push zkusit.
7. **Nález třídy 3 zastaví fast-forward** a objeví se jako ruling v ledgeru.
   Negativně: sezení, které merguje, neupraví kód mimo rozsah vlastního plánu,
   aby merge zezelenal.
8. **Ruling dorazí artefaktem, ne jen zprávou** — po rozhodnutí je změna
   rozsahu čitelná v `design_<slug>.md` dotčeného tiketu.
9. **Odmítnutí domněnky.** Agent, který dostane značenou domněnku a odmítne ji,
   ji nesmí zapsat do ledgeru jako fakt, a odmítnutí nesmí být hlášeno jako
   konflikt.
10. **Pokyn odporující psanému pravidlu je odmítnutý s odkazem na to pravidlo**
    a nejde ke správci, ale k člověku.
11. **Relay příčiny je odmítnutý jako pokyn.** Fixtura: dvě různé příčiny
    téhož příznaku; varování označené jako pokyn musí být vada, varování
    nesoucí příznak a hranici projít.
12. **Blok `NOW` je ohraničený strojově.** Fixtura: vložení sekce před textovou
    kotvu uvnitř bloku nesmí blok trefit; parser `pool-status.ps1` musí blok
    najít i tehdy, když se v próze objeví text vypadající jako nadpis.
13. **Přepis bloku je smazání a rekonstrukce.** Negativně: fakt, který má domov
    jen v bloku, musí rekonstrukci nepřežít — a to je správné chování, ne vada.
14. **Rozpor bloku a `git log`** musí být detekovatelný pravidlem „blok je
    špatně", ne mlčky přehlédnutý.
15. **Přeblokování.** Otázka pro člověka musí být doprovázená výčtem toho, co
    na odpovědi nezávisí — a to nezávislé se má opravdu udělat, ne jen
    vyjmenovat.
16. **Úroveň autonomie mění směrování.** Fixtura: týž nález třídy 3 jde při
    úrovni *Dohled* k člověku a při *Sdílené* ke správci; dno se nezvedne
    žádnou úrovní.
17. **Epiková linie bez epiku** je nález `mb-epic-graph`, ne mlčení.
18. **Test `--name` — třicet sekund.** Spustit `claude -n SKODASMS-999`
    a z jiného sezení zavolat `ListAgents`. Objeví-li se peer pod tím jménem
    místo tvaru `<adresář>-<sufix>`, `--name` peer jméno nastavuje. Test patří
    tam, kde nezůstane stray sezení v poolu.

## Pořadí úloh (návrh, ne plán)

Věcné závislosti, které plán musí respektovat:

1. **Topologie, vynucení a protokol integrace** — kontrakt, `epicBranchPattern`,
   `guard-git-push.mjs`, instalátor, rozdvojení ve `finishing`. Je to
   předpoklad všeho ostatního a je to ta část, která má mechanické testy.
2. **Odpovědnost za konflikty** — čtyři třídy, blokující třída 3, ruling jako
   artefakt. Závisí na 1, protože blokuje fast-forward.
3. **Blok `NOW`** — nezávislý na 1 i 2, a dělá pravidlo „nepobízej čekajícího"
   kontrolovatelným. Nejmenší a nejlépe měřitelný.
4. **Zprávy** — značení, relay timing, pravidlo o příčině a hranici; využívá
   blok z bodu 3.
5. **Eskalační tabulka a autonomie** — poslední, protože adresáta má z bodu 4,
   odpadlé zastavení z bodu 1 a viditelnost z bodu 3.

Otevřená otázka pro plán: **jestli je to jeden tiket, nebo víc.** Body 1 a 2
jsou zásahy do kontraktu a do vynucovacích hooků; body 3 až 5 jsou chování
skillů. Tenhle návrh to nechává otevřené záměrně.

## Navazující položky

- **Ověřovací sada epiku** — kde přesně v ledgeru je deklarovaná a co dělá
  integrace, když epik žádnou nemá.
- **Kolik paralelních sezení serializace unese** — dosud změřeno na třech.
- **Doklady v ledgeru epiku SKODASMS-237** — sezení `ums01` je má a nabídlo je
  k vyžádání pro konkrétní sekci.
