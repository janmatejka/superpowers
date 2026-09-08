# Návrh: Orchestrace epiku — epiková integrační linie, role správce a eskalační tabulka

- **Jira:** UMS-3505 (https://datasyscz.atlassian.net/browse/UMS-3505)
- **Target MB:** memory-bank/
- **Vytvořeno:** 2026-09-07
- **Nahrazuje:** [design_zpravy_a_autonomie_orchestrace.md](../abandoned/design_zpravy_a_autonomie_orchestrace.md) — překonaný skelet, jeho naměřená evidence je převzatá sem
- **Evidence:** praxe sezení `ums01`, které řídilo epik SKODASMS-237 (Integrace Chytrolin) přes tři tiketová sezení **bez skillu**, 3.–6. 9. 2026; všechna čísla níž jsou „co se stalo", ne „co by mělo fungovat"
- **Oponentura:** tři agentické, 2026-09-07 — výchozí adversariální (27 nálezů), ověření mechaniky reprodukovatelnými sondami (10 tvrzení, z toho 2 vyvrácená a 4 částečná), a posouzení smysluplnosti řešení proti prior artu. Žádný nález nebyl zamítnut jako nesprávný; co z nich zůstalo sporné, rozhodl uživatel.

## Slovník

Tři pojmy se v předchozí verzi tohoto textu prolínaly a je nutné je držet
oddělené:

| Pojem | Význam |
|---|---|
| **dodávková linie** | Sdílená větev, do které epik nakonec dodává — u SKODASMS-237 `Branches/skoda-mcr-chytrolin`. Nikdy do ní nepushuje agent. |
| **epiková linie** | `epic/<KLÍČ>` — kódová integrační větev epiku. Chráněná; agent do ní smí výhradně fast-forward. |
| **řídicí větev** | Elaborační větev epiku; nese ledger, graf a předběžné návrhy. Vlastní ji správce. |

Kontraktový pojem „integrační větev" (= báze pracovní položky, vždy chráněná)
zahrnuje **obojí** — epikovou linii i dodávkovou linii. Kde záleží na tom
která, používá tento návrh jména z tabulky, nikdy ten obecný pojem.

## Jedna procedura, dva příjemci

Nadřazený požadavek: **práce na samostatném tiketu, kde do chráněné integrační
větve pushuje člověk, musí dál fungovat.** První verze tohoto návrhu to řešila
slibem „mimo epikový režim se nemění nic" — a byla to falešná ochrana. Průchod
návrhem našel **patnáct míst, kde se chování větvilo, a deset z nich nemělo
s epikem nic společného.** Dvě z nich jsou přímo měřené vady, které se staly
**mimo** epikový režim:

- ACTIVE pin tiketu 242 unikl 4. 9. do **dodávkové linie** — epiková větev
  tehdy ještě neexistovala, vznikla 5. 9.;
- 244 dvakrát přepisovala výčet odchozích commitů, protože se pohnula
  **dodávková** báze.

Zmrazit chování mimo epik by tedy znamenalo opravit obě vady jen tam, kde se
nestaly. Návrh proto **sjednocuje proceduru a dělí práci podle aktéra, ne podle
režimu.**

**Tiketový agent má jednu proceduru pro oba režimy.** Liší se jediná věc —
**komu se práce předává** — a je to jedna podmínka na jednom místě:

> **Předání integrace je jeden artefakt** (cílová větev, SHA, výčet odchozích
> commitů, ověřovací příkazy a jejich výstup), kterému vždy předchází **jedna
> brána**. Vykreslí se buď jako příkaz pro člověka, nebo jako zpráva správci.

**Správcova práce je vlastní skill**, ne druhá varianta téže procedury —
operace `mb-epic-run integrate` vedle `status`, `ready`, `spawn` a `attach`.
V jednotiketovém režimu ten skill **prostě neexistuje**; není co degradovat a
není druhá formulace, která by se rozešla s první.

Rozhraní mezi nimi je ten artefakt předání. Co je nad ním navíc epikové, jsou
**dvě kontroly, které bez ledgeru epiku nemají vstup** a projdou triviálně.

**A jedna hranice, kterou je potřeba držet:** registr rozhodnutí, stub
sdíleného rozhraní a deklarovaná ověřovací sada se váží na **epik**, ne na
epikovou **linii**. Tiket, který patří do epiku a integruje se přímo do
dodávkové linie, je má taky — jeho sousedé existují bez ohledu na topologii
větví.

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

- **Dvě větve na epik** — epiková linie a řídicí větev — a podmínka, za které
  epiková linie vůbec vzniká.
- **Jedna procedura integrace pro oba režimy** — brána předání a artefakt
  předání se dvěma vykresleními, strojové brány místo položek v checklistu.
- **Správcova strana jako vlastní skill** (`mb-epic-run integrate`), ne druhá
  varianta téže procedury.
- **Zrušení nabídky inline elaborace epiku** na hranici fáze tiketového sezení.
- **Východ epiku** do dodávkové linie a to, proč právě on licencuje agentní
  zápis do epikové linie.
- **Vynucení** — `epic/*` mezi chráněnými větvemi, klíč `epicBranchPattern`
  čtený **z báze**, výjimka podle aktéra v `guard-git-push.mjs`.
- **Odpovědnost za konflikty a za selhané ověření** — čtyři třídy, registr
  rozhodnutí s potvrzením, a sdílené rozhraní jako překládající se stub.
- **Zprávy** — značení *pokyn* / *domněnka*, relay timing, pravidlo o příčině
  a hranici, a artefaktová forma pro každé pásmo eskalace.
- **Viditelnost** — blok `NOW` se strojovým ohraničením, stavovou třídou a
  očekávaným časem dalšího ohlášení.
- **Eskalační tabulka a tři úrovně autonomie** čtené z ledgeru epiku.

**Mimo rozsah, a proč:**

- **Build server nad epikovou linií.** Je to jediný skutečný uzávěr toho, že
  tvrzení „ověřeno" je pravda, a je to i podmínka, za které by šlo nasadit
  optimistický model (rychlá presubmit brána, pomalé testy asynchronně, oddělený
  „green head"). Tenhle návrh build server nemá a nepředstírá to; místo něj má
  brány, které pokrývají chyby, jež skutečně kously.
- **Dávkování integrací s bisekcí.** Dokumentovaná odpověď na kvadratickou cenu
  serializace. Není potřeba při třech tiketech; je zapsaná jako pojmenovaný únik
  v Rizicích, včetně spouštěcí podmínky.
- **Nový přenosový kanál.** `ListAgents` a `SendMessage` existují a fungují;
  je změřené, že orchestrátor v hlavním klonu vidí sezení ve slotech jako
  peery a že mu jejich zastavení dorazí jako `[Cross-session idle notice]`.
- **Brána připravenosti** — vlastní odložený tiket UMS-3496.
- **Žádné zápisy správce do pracovního stromu slotu.** Železné pravidlo
  z UMS-3488 platí beze změny.
- **Přenos práce mezi dodávkovou a hlavní linií** — u SKODASMS-237 je to
  explicitně nevyřešený problém s vlastními tikety a do téhle vrstvy nepatří.
- **Feature flagy a branch by abstraction.** Textbooková prevence problému
  skládání, ale je to vlastnost produktu, ne téhle vrstvy — vrstva ji nemůže
  nařídit. Kde je dostupná, je to lepší odpověď než epiková linie.

## Evidence a její původ

Všechno níž je z transcriptu sezení `ums01`, které řídilo epik SKODASMS-237
přes tiketová sezení SKODASMS-242, 243 a 244 od 3. do 6. 9. 2026, **bez
jakéhokoli skillu na orchestraci**. Sezení odpovídalo na cílené dotazy a
u každého údaje rozlišovalo měřené od dojmu.

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
Tikety si ho tahaly z báze. Druhý takový únik nastal 6. 9. u 243.

**Konflikty v projektových souborech.** `KicProcess.csproj` konfliktoval u obou
sezení; u 243 devatenáct položek `<Compile Include>` ze tří stran. Řešeno vždy
sjednocením. **Rozdělením větví to nezmizí a zmizet nemá.**

**Dva červené buildy po mergi, stejný příznak, různá příčina.**
Zastaralý `project.assets.json` po přidaném `PackageReference` (`CS0246`,
léčba restore na `.sln`, našla 244) a zastaralá kopie `App.config`
v `bin/Debug` (`AutoConfigMappingException`, léčba druhý build, našla 243).
Ani jednou to nebyla vada druhého tiketu; obojí byly **zastaralé lokální build
artefakty ve stromě toho, kdo mergoval**. Obě sezení to opravila sama a
nahlásila v běžném hlášení z hranice fáze. A tohle je z toho to nejcennější:
správce poslal 243 vysvětlení příznaku `CS0246` minutu před tím, než měla měřit
baseline. **Nepomohlo to** (243 udělala restore jako první krok, takže ten
příznak neviděla) — **ale trefila druhou past se stejným příznakem, a kdyby
aplikovala doručené vysvětlení, opravovala by restore, který byl v pořádku.**

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
správce byla koordinace**, zbytek vlastní artefakty (~30 commitů). Přímých
čekání, kdy sezení stálo na odpovědi správce, byla **tři** a všechna se
vyřídila v minutách. Skutečné zdržení bylo jinde: **kolem deseti zastavení mezi
dodávkou implementera a spuštěním review** u tří sezení. Sezení nečekala na
odpověď — čekala na pobídku, kterou nepotřebovala. A **délku toho zdržení
neurčovala rychlost odpovědi správce, ale to, jak rychle si toho všiml**:
minuty, půl hodiny, jednou přes noc. Hrdlo se z člověka na správce přesunulo,
ale změnilo povahu: z „čeká na rozhodnutí" na **„čeká, až si někdo všimne, že
stojí"** — a to je horší, protože to nemá signál.

**Signál ale existoval a byl nejednoznačný.** Každé jedno z těch zastavení
dorazilo správci jako `[Cross-session idle notice]`; tak se o nich vůbec
dozvěděl. Sezení skutečně ukončilo turn. Jenže `idle` znamenalo dvě různé
věci: „stojím a čekám na pokyn" i „legitimně čekám na dispatchnutého
subagenta, kterého nesmím pollovat". **Ten rozdíl odhadl správce čtyřikrát
špatně**, než si zavedl postup posílat místo pobídky dotaz „stojíš, nebo
čekáš? jestli čekáš, ignoruj to".

**Správce si sám udělil oprávnění.** Nařídil sezení, ať si epikovou větev
pushne samo, a zdůvodnil to zaznamenaným záměrem uživatele — **aniž otevřel
`CLAUDE.md`**, kde deset řádků od místa rozhodování stálo pravidlo opačné.
Sezení se hádalo hodiny, došlo ke stejnému závěru a zastavilo ho až
**mechanické odmítnutí nástroje**. Vlastní diagnóza správce k tomu, co by ho
dnes znejistilo, je trojí: jestli k tomu už není psané pravidlo; že **„ověřený
merge" je tvrzení, které nemůže levně přeověřit** (vidí stav gitu, ne že build
byl zelený — a totéž sezení mu téhož dne doložilo, že převzalo tvrzení
reviewera bez kontroly a bylo nepravdivé); a že **báze se pod nimi pohnula
pětkrát za dva dny**.

Tohle je **jediný zaznamenaný výkon správcovské pravomoci** v celé praxi, a byl
špatně. Průřezová pozornost je naopak doložená kladně (případ výše). Návrh na
to odpovídá tím, že pravomoc pokud možno nahrazuje mechanismem — viz část 5.

**ACTIVE pin na epikové větvi zachytila pozornost, ne orákulum.** Hodinu před
finálním pushem správce ručně spustil `git show origin/epic/SKODASMS-237:memory-bank/context.md`,
a udělal to **jen proto, že ho tentýž problém 4. 9. u 242 už jednou spálil**.
`mb-state` invariant „báze nikdy nenese ACTIVE stav" má — nikdo ho nespustil.

**Poslední krok udělal člověk**, jedním pushem, **celý epik naráz** — 162
commitů, tři tikety. Kudy má práce epiku odejít do hlavní linie, doklad
**není**: tenhle epik má dodávkovou linii, ne hlavní větev, a přenos na
mainline je tam nevyřešený problém s vlastními tikety.

**Blok `NOW` došel na v8 a zanikl sklizní** — žil v gitignorovaném scratchi
`.superpowers/sdd/<plan>/progress.md`, který se na konci maže; jeho poznatky
odešly do kandidátů playbooku. Ta série je cennější než výsledek: **v1 až v5
byly formulace a všechny se porušily; teprve v6 a dál jsou operace.** v5 zněla
„tenhle blok se přepisuje, nikdy nepřipisuje" a blok narostl zpátky na 177
řádků. v8 zní doslova:

> **Přepis je „smaž, pak rekonstruuj z gitu a tabulky tasků", ne „napiš to
> znovu".** Slabina v6 a v7 je táž, kterou měla v5: dokud je starý text na
> obrazovce, nejlevnější úprava je doplnit ho, takže ruka dopisuje místo aby
> nahrazovala. **Z prázdné oblasti není k čemu připisovat.** Zdroje
> rekonstrukce jsou ty, které nemůžou driftovat — `git log`, tabulka tasků,
> index rulingů — **a právě proto blok nesmí být jediným domovem žádného
> faktu.**

Ta poslední podmínka nevznikla ze ztraceného faktu, ale odvozením dopředu. A
**hodinu po zavedení se v8 porušila druhým způsobem**: vložení sekce před kotvu
se jménem sekce tasků skončilo **uvnitř toho odstavce, který o v8 mluví**,
protože jméno té kotvy je tam v próze. **I operace selže, když je její kotva
textová.**

Blok navíc **jednou zavedl**: tvrdil běžící závěrečné review několik hodin
poté, co se vrátilo se čtyřmi nálezy třídy Critical.

**`--name` peer jméno NASTAVUJE — změřeno 7. 9. 2026**, neinteraktivním během
`claude -n <jméno> -p "…"`, takže v poolu nezůstalo stray sezení. Původní závěr
draftu byl opačný a stál za pozornost hlavně tím, **proč byl špatný**:
`claude --help` popisuje `--name` jako display name pro prompt box, `/resume`
picker a titulek terminálu, `ListAgents` v tom výčtu není — a **nepřítomnost
v neúplném výčtu se vzala jako popření**. Táž třída chyby, jakou tenhle návrh
loví jinde.

**Co z toho ale NEPLYNE:** že se adresa zprávy a mechanický důkaz spuštění
slučují. `mb-epic-run` to výslovně zakazuje — jeho sonda obsazenosti **jména
nečte**, klíčuje na záznam s `pid` pro daný slot. `--name` je tedy pohodlná
adresa, ne důkaz. Doměřit zůstává, jestli jméno přežije `--resume`, a co dělá
kolize dvou sezení téhož jména.

## Technický návrh

### 1. Dvě větve na epik

Naměřená bolest má jednu příčinu: **`epic/SKODASMS-237` nesla dvě role
najednou** — evidenci epiku a integrační linii kódu. Odtud opakovaný konflikt
v `context.md` i téměř propuštěný ACTIVE pin.

| | epiková linie | řídicí větev |
|---|---|---|
| jméno | `epic/<KLÍČ-EPIKU>` | elaborační větev epiku, jako dnes |
| nese | kód tiketů **a jejich sklizené MB dokumenty a archivované návrhy** | ledger epiku, graf, předběžné návrhy |
| stav pinu | **nikdy ACTIVE** | **IDLE** — elaborace je bez pinu |
| kdo ji má vyzvednutou | **nikdo** | správce |
| jak se do ní píše | výhradně fast-forward refspecem | běžné commity |
| kdo ji zakládá | **člověk** | agent, jako každou větev |
| kam integruje | dodávková linie, lidským pushem | dodávková linie, lidským pushem |

**Řídicí větev JE elaborační větev epiku** — ta, na které `mb-epic-elaboration`
uzavírá okna a `mb-epic-run spawn` píše řádek `Rozjetí`. Nezavádí se nová
větev a nemění se, kde ji spuštěná sezení hledají. Elaborace je definovaná jako
práce **bez pinu**, takže řídicí větev zůstává IDLE; správce nemá pracovní
položku a nemá co harvestovat.

Tiketové větve se odštěpují z `epic/<KLÍČ>` a mají ji jako **efektivní bázi** —
řádek `- **Báze:** origin/epic/<KLÍČ>` v `context.md`. Ověřeno, že odvození
cíle pushe z takové hodnoty je správné i pro víceúrovňové jméno
(`origin/epic/UMS-3400` → `epic/UMS-3400`).

**Povinné odpojení upstreamu.** `git switch -c UMS-x origin/epic/<KLÍČ>`
nastaví upstream nové větve **na epikovou linii** (změřeno). Bez následného
`git branch --unset-upstream` by holý `git push` mířil do epikové linie — a po
výjimce podle aktéra (část 4) by prošel oběma vrstvami, kdykoli by to byl
fast-forward na publikované commity. Kontrakt to odpojení už vyžaduje; tady
přestává být hygienou a stává se bezpečnostním krokem.

**Kanonický IDLE — jedna definice, jedno místo, jeden zapisovatel, a platí
všude.** Rozdělení větví konflikt v `context.md` **neodstraní samo**: každá
integrační větev ho zdědí z toho, co se do ní integruje. Invariant, který ho
odstraní:

> **Post-harvest `context.md` všech tiketů, které integrují do téže větve, je
> bajt po bajtu stejný.** Obsahuje IDLE marker a řádek `Báze:` té větve (nebo
> ho neobsahuje, když je bází `baseRef`), a **neobsahuje řádek `Jira:`.**

Pak je čistý příspěvek tiketu do toho souboru nulový a trojcestný merge ho bere
bez konfliktu; nový tiket odštěpený z té větve navíc zdědí správnou bázi.
Zapisuje to **`mb-harvest` ve svém existujícím resetu**, na tiketové větvi —
žádný čtvrtý zapisovatel `context.md` nevzniká.

**Není to epikové pravidlo a nesmí být napsané jako epikové.** Zbytkový `Jira:`
sbírá každá sdílená větev, do které integruje víc tiketů — a je to jeden ze
dvou měřených zdrojů opakovaného konfliktu, přičemž ten druhý (ACTIVE pin 242)
se stal na **dodávkové** lince. Napsat tuhle opravu jen pro epikový režim by
znamenalo opravit ji tam, kde se ta chyba nestala.

Vypuštění řádku `Jira:` je vědomá **odchylka od kontraktu**, který ho v IDLE
zachovává jako „poslední pracovní položku". Na větvi, do které integruje mnoho
tiketů, ta věta nedává smysl — je to ten, kdo integroval naposled. Identita
tiketu je v hlavičce návrhu a v ledgeru, ne ve zbytkovém řádku; **plán musí
ověřit, odkud `mb-jira-update` bere klíč po harvestu**, protože dnes ho může
brát právě odtud.

**Vlastní báze epikové linie není v jejím `context.md`.** Je v ledgeru epiku,
protože epiková linie žádnou pracovní položku nemá. Kdyby se odvozovala
z `Báze:` na epikové lince, vycházelo by `HEAD:epic/<KLÍČ>` — epiková linie
sama do sebe.

### 2. Role a protokol integrace

**Správce epiku** je sezení, které drží řídicí větev. Jeho mandát je
**pozornost, průřezová paměť a pořadí fronty** — tedy to, co je z praxe
doložené kladně. Rozhodovací pravomoc má tam, kde nic mechanického stát
nemůže; všude jinde ji návrh nahrazuje bránou (část 5).

**Tiketový agent** je jedno sezení na jednu tiketovou větev.

#### Procedura tiketového agenta — jedna, pro oba režimy

Nahrazuje Option 1 v `finishing`. `<BÁZE>` je efektivní báze pracovní položky:
dodávková linie, servisní větev nebo epiková linie — procedura mezi nimi
nerozlišuje.

1. tiket dokončí; **harvest**, včetně kanonického IDLE — **před integrací**;
2. `git fetch origin`, `git merge <BÁZE>`, ověření **deklarovanou ověřovací
   sadou**. Konflikty typu sjednocení v projektových souborech řeší sám;
   rozhodnutí patřící cizímu tiketu eskaluje (část 5);
3. push vlastní větve — dnešní povinnost po každém commitu;
4. **brána předání — skript, ne položky v checklistu.** Nejdřív `git fetch
   origin`, pak porovnává proti **čerstvě staženému `<BÁZE>`**, nikdy proti
   hodnotě, kterou si zapamatoval z kroku 2. Tři kontroly, všechny univerzální:
   - `git merge-base --is-ancestor <čerstvá báze> <SHA>` — merge nese aktuální
     bázi. Proti zapamatované hodnotě projde přesně v tom případě, kvůli
     kterému existuje, a člověk pak dostane příkaz, který se odrazí (244 kvůli
     tomu dvakrát přepisovala výčet commitů);
   - `context.md` commitu, který se integruje, je IDLE — čteno z `<CTX_DIR>`
     odvozeného z konfigurace, ne z natvrdo zapsané cesty. **Predikát je
     kontraktový:** ACTIVE je přítomnost `Target MB Pin` spolu s `Work item`.
     **Chybějící soubor je fail-closed STOP, ne „IDLE"** — `git show` na
     neexistující cestu končí kódem 128 a ten se dá snadno přečíst jako „není
     ACTIVE". Tohle je ta kontrola, kterou u 242 zachytila jen pozornost;
   - `<SHA>` je dosažitelné na `origin`. Tuhle podmínku vynutí i hook při
     pushi; v bráně je proto, aby chyba přišla dřív a srozumitelněji;
5. **artefakt předání** — cílová větev, `<SHA>`, výčet odchozích commitů,
   a **doslovný výpis příkazů ověřovací sady s jejich výstupem**. Jeden
   artefakt, dvě vykreslení, a rozhoduje o nich **jediná podmínka celé
   procedury**:
   - **není správce** → příkaz pro člověka, `! git push origin
     HEAD:<baseBranch>`, jako dnes;
   - **je správce** (efektivní bází je epiková linie) → zpráva správci;
6. **po landnutí pushe** — ať ho udělal člověk, nebo správce — tiketové sezení
   ověří dosažitelnost **z báze** (`git merge-base --is-ancestor <SHA>
   <BÁZE>`) a teprve pak spustí `mb-jira-update`. Životní cyklus běží na větvi
   toho tiketu, jak vyžaduje kontrakt; tahle brána platí i bez Jira tiketu.

#### Operace správce — vlastní skill, ne druhá varianta téhož

`mb-epic-run integrate`, vedle `status`, `ready`, `spawn` a `attach`. Vstupem
je artefakt předání. V jednotiketovém režimu tenhle skill neexistuje
a není co degradovat.

1. `git fetch origin`, přečtení předání;
2. **dvě epikové kontroly navíc** — obě bez ledgeru epiku nemají vstup a
   projdou triviálně:
   - **řádek `Rozjetí` tohoto tiketu patří tomuto epiku** — bez toho nic
     neváže fast-forward na *vlastní* epik a agent by směl posunout kteroukoli
     existující `epic/*` větev;
   - **žádný nepotvrzený řádek registru rozhodnutí nejmenuje tento tiket**
     (část 5);
3. **jedna věc úsudkem**, protože mechanicky nejde: že hlášení neodporuje
   ničemu v evidenci epiku. To je ta průřezová kontrola, kvůli které
   fast-forward dělá správce;
4. přeběhnutí tří univerzálních kontrol brány předání proti čerstvě staženému
   tipu — mezi předáním a pushem uběhl čas a báze se mohla pohnout;
5. `git push origin <SHA>:refs/heads/epic/<KLÍČ>`. **Předpoklad, který se dá
   přehlédnout:** hook posuzuje dosažitelnost z remote-tracking refů *tohoto
   klonu*, takže správce musí mít po pushi tiketového agenta fetchnuto. V poolu
   sdílených worktreí je to zdarma, v odděleném klonu ne;
6. zápis do ledgeru a pobídka ostatním sezením k resynchronizaci.

**Serializace je fronta, ne merge.** Když dva tikety ověří proti témuž
epikovému tipu a první se integruje, druhý **už není fast-forward** a musí se
resynchronizovat a znovu ověřit. Proto **pokyn „dokonči a integruj" drží
správce v jednu chvíli u jednoho tiketu**. Dávkování s bisekcí je dokumentovaný
únik, kdyby to přestalo stačit — a je proveditelné, protože batch smí složit
**tiketový agent** (mergne si publikovanou větev souseda a ověří obojí), takže
správce nikdy neautoruje obsah, který autorovat nesmí. Podmínka spuštění a
odhadovaný strop jsou v Rizicích.

**„Ověřeno" musí být porovnatelné tvrzení, a to v obou režimech.** Ověřovací
sada je **doslovný výčet příkazů**; artefakt předání je cituje i s výstupem.
Domov má podle toho, co práci zastřešuje: **u tiketu v epiku je to ledger
epiku** (deklarováno jednou pro celý epik, aby všechny tikety měřily totéž),
**jinak plán pracovní položky**, který build a testy jmenuje už dnes.
**Chybějící sada je fail-closed STOP** — bez ní znamená „zelené" pokaždé něco
jiného a nemá se co porovnávat.

Ve vrstvě pro to dnes není žádný precedent; kontrakt zná jen „green
verification (build and targeted tests)". Bez build serveru je tohle jediná
věc, která z „ověřeno" dělá srovnatelný údaj — a proto se nepíše jako epiková
zvláštnost.

**Kdo smí fast-forwardovat.** Mechanicky nikdo neodliší správce od tiketového
agenta, a git nesprávné pořadí odmítne sám — takže „do epikové linie zapisuje
jen správce" je **norma, ne mechanismus**. Norma existuje proto, že
fast-forward je jediné místo, kde běží průřezová úsudková kontrola. Bez správce
(degradovaný režim) fast-forward **neprovádí nikdo z agentů**: příkaz se
připraví člověku, přesně jako dnešní kontraktová Integrace, a v ledgeru se
zapíše, že průřezová kontrola neproběhla. Tím je degradovaný režim skutečně
fail-closed, ne jen tak nazvaný.

### 3. Východ epiku a proč licencuje agentní zápis

**Epiková linie odchází do dodávkové linie fast-forward pushem, který spouští
člověk.** Správce připraví příkaz s výčtem odchozích commitů, uživatel ho
spustí, správce ověří dosažitelnost **z dodávkové linie**. Cíl se odvozuje
z ledgeru epiku, ne z `context.md` epikové linie. Non-fast-forward znamená, že
se dodávková linie pohnula: opakovat od `fetch`, strop dvě neúspěšná kola.

**Obvyklý případ je jednou, na konci epiku** — u SKODASMS-237 to byl jeden push
se 162 commity. Ale člověk může kdykoli vyžádat přenos **v obou směrech**:
dodávková linie do epikové (běžná synchronizace) i epiková do dodávkové dřív,
než je epik hotový.

**A právě tohle je odpověď na to, proč smí do epikové linie zapisovat agent.**
Ne proto, že je ten push bezobsažný — to není pravda a je to změřené (viz
část 4). Proto, že **epiková linie má jediný východ a ten je lidský**. Agentní
práce se do dodávkové linie nedostane jinak než lidskou rukou.

**Podmínka, za které epiková linie vůbec vzniká.** Je to *collaboration
branch* — sdílená větev pro práci, která ještě není způsobilá pro hlavní linii
— a ta se v literatuře drží jako ústupek s vyslovenou podmínkou, ne jako
výchozí volba. Podmínka, která v měřeném případě skutečně platila, je
produktová:

> **Epiková linie vzniká jen tam, kde tikety epiku nejsou samostatně
> dodatelné do dodávkové linie.** Kde jsou, integruje každý tiket sám, jako
> dnes.

**A zaniká.** Po východu epiku se maže, jako release větev. Mazání větve přes
push je zakázané, takže je to lidský úkon; návrh na něj upozorňuje proto, že
`epic/*` mezi chráněnými větvemi jinak roste donekonečna a `Get-UmsBaseCandidates`
nabízí každou existující epikovou linii jako bázi každé nesouvisející práci.

**Nutná podmínka viditelnosti:** epiková linie musí být svázaná se skutečným
epikem. Enumeraci větví na `origin` umí **`mb-doc-index`**, ne `mb-epic-graph`
— ten je parametrizovaný klíčem epiku a jeho uzly jsou Jira issues nebo
soubory návrhů, refy nikdy nevypisuje.

**Synchronizace opačným směrem má stejný tvar jako všechno ostatní.** Když se
dodávková linie pohne, správce **nemerguje** — dá pokyn jednomu tiketovému
sezení, aby si ji mergnulo, ověřilo a nahlásilo; pak se epiková linie
fast-forwarduje. Tím platí invariant, že **tip epikové linie je vždycky strom,
který někdo přeložil a otestoval.**

### 4. Vynucení

Předchozí verze tohoto návrhu měla konfigurační schéma, které oponentura
vyvrátila měřením na dvou probe repozitářích. Zapsáno tak, jak to je:

> Klíč `epicBranchPattern` sám o sobě **nefunguje ani v jednom směru**.
> `Get-UmsRepoConfig` ho nezná, takže `Get-UmsBaseCandidates` epikovou linii
> nenabídne a volba té báze je fail-closed STOP; a `guard-git-push.mjs` čte
> `protectedBranches` z `ums-repo.json` přímo, ne generovaný seznam, takže
> **agentní push do `epic/*` už dnes projde mlčky**. Věta „instalátor ho
> sjednotí, takže obě vynucovací vrstvy nemohou nesouhlasit" byla nepravdivá:
> generovaný seznam čte jen `pre-push`.

Schéma je proto **dvouklíčové a každý klíč má jinou práci**:

- **`epic/*` patří do `protectedBranches`.** To je ochrana, a čtou ji všechny
  vrstvy stejně — `pre-push` přes generovaný seznam, `guard-git-push.mjs` a
  všechny PowerShellové konzumenty přes `ums-repo.json`. Ověřeno měřením, že
  s ním `Get-UmsBaseCandidates` epikovou linii nabídne a víceúrovňový glob
  funguje.
- **`epicBranchPattern` je JEN výjimka podle aktéra**, s jediným konzumentem:
  `guard-git-push.mjs`. Neřídí ochranu, jen to, komu se odpouští.

**Čte se z pracovního stromu, jako `protectedBranches`** — tedy stejnou cestou
jako všechno ostatní v `ums-repo.json`, bez zvláštního zacházení. Nečitelná
nebo chybějící hodnota znamená **žádnou výjimku**; degradace vždy k větší
ochraně, jako u ostatních klíčů.

**Model hrozby, vyslovený, protože na něm ta volba stojí.** Oponentura označila
za kritické, že se tím z kategorického pravidla podle aktéra stává
glob-podmíněné, jehož glob leží v souboru, který agent smí editovat — agent by
si mohl deklarovat `epicBranchPattern: "feature/*"` a udělit si právo pushovat
do jmenného prostoru vlastní volby. Zvažovalo se to zúžit čtením hodnoty
z báze, tedy až po lidském pushi.

**Uživatel rozhodl, že se s diverzí agenta nepočítá:** konfigurace ani skripty
se před agenty nechrání. Vrstva brání **omylu, ne úmyslu** — a je to týž model
důvěry, na kterém stojí zbytek kontraktu (že agent nikdy nenastaví
`MB_HUMAN_PUSH=1`, je taky pravidlo, ne vynucený mechanismus). Za toho
předpokladu je čtení z báze složitost, která nekupuje nic: rozšíření vzoru
nevznikne omylem, a to, co omylem vzniknout může, zachytí trojí podmínka níž.
Cena je pojmenovaná v Rizicích: kdyby se model hrozby někdy změnil, tenhle klíč
je první místo, které se musí přehodnotit.

**Výjimka je podmíněná trojnásobně**, aby nešla rozšířit tvarem příkazu:

1. cíl odpovídá `epicBranchPattern` **a zároveň** je v `protectedBranches`;
2. push má tvar `<SHA>:refs/heads/<cíl>` se **surovým SHA** jako zdrojem — ne
   `HEAD`, ne jméno větve. To zavírá past s upstreamem z části 1;
3. `epicBranchPattern` je **podmnožinou** `protectedBranches`. Kontroluje se na
   **jménech** existujících větví na `origin`, ne porovnáním vzoru se vzorem —
   `Test-UmsProtectedBranch` porovnává jméno s globem, takže překryv
   `Branches/epic-*` proti `Branches/*` by nepoznal. A kontrola se **vztahuje
   na repozitářový `baseRef` a na ne-epikové chráněné větve**, ne na efektivní
   bázi: efektivní bází tiketu *je* epiková linie, takže doslovné znění
   z předchozí verze hlásilo chybu u každého legitimního epikového tiketu.

**Co chráněnost skutečně kupuje: dvě věci, ne čtyři.** Zákaz mazání a zákaz
force pushe platí v `pre-push` pro **každou** větev, chráněnou i nechráněnou.
Specifické pro chráněnost je jen: tip musí být už publikovaný, a **první
publikace větve se zamítne** (`remote_sha` je nula) — proto epikovou linii
zakládá člověk. Nafouknutý výčet oslaboval správné rozhodnutí.

**Zakládající push má tvar s únikem.** Měřeno: hook u první publikace nabízí
`! MB_HUMAN_PUSH=1 git push origin HEAD:epic/<KLÍČ>`. Prostý integrační tvar
tam **neprojde**, protože obsahové pravidlo se o nulový `remote_sha` opře.
Kontrakt ty dva tvary rozlišuje záměrně a skill, který by nabídl prostý,
by uživateli připravil příkaz, který skončí zamítnutím.

**Třetí kategorie existuje, jen je jinde.** Předchozí verze tvrdila, že žádná
nevzniká. Vzniká: „chráněná větev, do které agent smí pushovat". Rozdíl proti
draftu je, že se přesunula z otázky *co smí být bází* do otázky *kdo smí
pushovat co* — kategorie menší a na lépe hlídaném místě, ne kategorie žádná.

**`pre-push` se nemění**, ale nese nepravdivý komentář, který se v tomto zásahu
opraví: tvrdí, že `guard-git-push.mjs` je v porovnání jmen taky
case-insensitive. Změřeno, že není — `refs/HEADS/develop` guardem projde,
zatímco hook ho zamítne. Exploatovatelnost je malá (git tím vyrobí odpadní ref,
nepohne větví), ale vyslovený invariant „vrstvy spolu nesmí nesouhlasit" je
porušený. Oprava je jeden regulární výraz.

**Instalátor** klíč `epicBranchPattern` do generovaného seznamu **nesjednocuje**
— ochranu nese `protectedBranches`, který tam patří už dnes. Ověřeno, že
self-test instalátoru s `epic/*` v seznamu projde a že obě jeho kola (přijetí i
zamítnutí) se chovají správně.

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
> pokyn.** Příčina je vždycky *domněnka*; hranice smí být *pokyn*.

**Třída 3 blokuje bezpodmínečně** a je jediná, která se řeší jinak než ostatní
tři. Tvrdý strop: kdo merguje, **nikdy needituje kód mimo rozsah vlastního
plánu, aby merge zezelenal.**

**Nález třídy 3 rozhoduje správce rulingem**; smí si vyžádat doporučení od
sezení, která drží kontext. **Nosičem rulingu je artefakt, ne zpráva** — ledger
epiku a hint do `design_<slug>.md` dotčeného tiketu.

Tady ale návrh jde o krok dál, než kam došla praxe, protože měřený záchyt
případu (a) stál na tom, že si správce **náhodou vzpomněl** — a paměť agenta
jako záruka je přesně to, co tenhle návrh jinde odmítá. Proto dvě mechaniky:

**Registr rozhodnutí v ledgeru epiku.** Ledger dnes nemá sekci, kde by tvrzení
o chování *jiného* tiketu mohlo bydlet — má `Položky`, `Členy`, `Okna`,
`Dirty-set` a `Rozjetí`. Přibývá sekce s řádky
`Rozhodnutí | Vlastník (tiket) | Předpokládá o (tiket) | Stav | Potvrzeno (SHA)`.
Rozhodnutí, které stojí na chování jiného tiketu, **je řádek jmenující ten
tiket**, a ten ho musí potvrdit commitem. **Nepotvrzený řádek jmenující
integrovaný tiket je mechanická zábrana fast-forwardu** (kontroluje ji operace `integrate`), ne
věc, na kterou si má někdo vzpomenout. Případ (a) je přesně takový řádek:
*„po výpadku se neobsluhuje z prošlých dat; léčbou je delší okno"* s vlastníkem
244 a předpokladem o 243.

**Elaborace epiku se tiketovému sezení přestává nabízet.** Dnes Epic Backflow
check na hranici fáze **nabídne inline elaborační okno** — přepnutí na
elaborační větev a rozpracování epiku uprostřed práce na tiketu. To se ruší:

> **Tiketové sezení nález zapíše a pokračuje. Elaboraci epiku otevírá jedině
> jeho správce.**

Tři důvody, všechny už v tomto návrhu jinde: rozpracování epiku je **průřezová
práce**, a ta patří tomu, kdo drží průřezovou paměť; nabídka je **zastavení
navíc** přesně tam, kde bylo naměřeno deset zbytečných zastavení; a přepnutí
větve uprostřed tiketu je práce na dvou pracovních položkách zároveň, což
kontrakt jinde nedovoluje.

Zaniká tím jen **nabídka**, ne nález. Zápis do ledgeru zůstává — to je ten
artefakt, kterým se nález doručí. Bez správce (jednotiketový režim tiketu, který
do epiku patří) řádek prostě čeká na příští elaborační okno, stejně jako dnes
čeká dirty-set; nic se neztrácí, jen se to odkládá. Platí to **v obou režimech**,
protože důvod je vlastnictví práce, ne topologie větví.

**A kde je předpoklad o chování, potvrzuje se testem.** Řádek registru se
u behaviorálního předpokladu nezavírá přečtením, ale testem, který to chování
tvrdí — u případu (a) testem, že je okno konfigurovatelné. Je to jediná cesta,
jak ze sémantického konfliktu udělat mechanický; oponentura hledala levnější
nástroj a vrátila čistý zápor: kontraktové testy vidí jen zprávy přes hranici a
schema-diff pozná jen změnu *deklarovaného* pole, nikdy chybějící deklaraci.

**Sdílené rozhraní je překládající se stub na epikové lince, ne próza
v ledgeru.** Když dva tikety sdílejí rozhraní, epiková linie nese jeho stub
**commitnutý dřív, než proti němu kterýkoli z nich implementuje**. Překladač se
tím stává orákulem a merge mění sémantický konflikt na textový. To je přímá
odpověď na případ (b) — nepřekládající se signatura `EmployeeResolver`
zapsaná v ledgeru jako próza; ruling by příští signaturu kontrolovatelnou
neudělal.

**Odpovědnost správce, kterou pravidla epiku nejmenovala.** Dvě pravidla
v operačním tvaru:

- **Správce neautorizuje nic, co se týká pushe, chráněných větví nebo role
  člověka.** Na tyhle otázky se neodpovídá úsudkem ani vzpomínkou na záměr —
  odpovídá se přečtením pravidla.
- **Mechanické odmítnutí není překážka k obejití, je to pokyn přečíst si
  pravidlo.** Platí pro obě strany.

### 6. Zprávy

Pět druhů z praxe — **popis, ne pravidlo**, a slouží k tomu, kam vyplatí
investovat: **průřezový relay** (nejvyšší hodnota na jednotku textu),
**eskalace k rozhodnutí** (vzácná, obě měřené správné), **korekce**
(užitečnější agent → orchestrátor, šest za den a pokaždé věcná), **hlášení na
hranicích** (nejčastější, nejmíň zajímavé), **pobídky** (z poloviny zbytečné).

**Ústřední pravidlo: zpráva neškodí přerušením. Škodí tím, že nese autoritu a
zapisuje se.** `ums01` dvakrát za den poslalo věcně **špatné zdůvodnění
správného kroku**; obojí by skončilo v ledgeru jako fakt. Zachytili to agenti,
ne orchestrátor. Proto:

- Každá zpráva orchestrátor → agent je značená jako **pokyn** nebo
  **domněnka**.
- Agent má **právo domněnku odmítnout**; odmítnutí je normální chování.
- Do ledgeru se domněnka nezapisuje jako fakt.
- **Příčina je vždycky domněnka, hranice smí být pokyn.**
- Agent má **povinnost** odmítnout pokyn, který odporuje psanému pravidlu.

**Relay timing.** Změnu zadání posílej **okamžitě jen tehdy, když příjemce
právě teď jedná podle premisy, kterou to mění**; jinak čekej na hranici.
Rozhoduje **bezprostřednost, ne důležitost**.

**Resynchronizace je tažená, ne tlačená.** Pokyn „integruj si epikovou linii"
je pobídka, ne doručovací záruka: tiketové sezení si svou efektivní bázi
merguje na každé hranici fáze samo, a **uprostřed tasku to kontrakt zakazuje**.
Zpráva tedy pořadí urychluje, nezakládá ho.

**Každé pásmo eskalace musí mít artefaktovou formu.** `SendMessage` a
`ListAgents` jsou vázané na Claude Code a **ve vrstvě se dnes nepoužívají
nikde**; pásmo „vždy správce" by na jiném harnessu nemělo adresáta vůbec. Proto
má každá eskalace řádek se stavem v ledgeru a zpráva je jen zrychlením nad ním.
Pak se na Codexu nebo Gemini ztrácí rychlost, ne správnost — a to je teprve to,
co „fail-closed, ne rozbité" znamená.

**Dvě věci, které se dělat nemají,** obě naměřené: **nepobízet sezení, které
čeká na subagenta**, a **nepoužívat `notify_when_idle` po každé zprávě** —
přepisuje si to slot v tabulce odběrů. Správný tvar je jeden živý odběr na
peera, obnovený teprve poté, co sepne.

**Adresování.** `--name <TIKET>`, který pool nastavuje už dnes, je použitelná
adresa. **Není to důkaz spuštění** — sonda obsazenosti jména nečte. Do doměření
chování při `--resume` a při kolizi jmen je adresování kódem tiketu pohodlí, ne
záruka doručení.

### 7. Viditelnost — blok `NOW`

**Blok není Session Intent Baton a je nutné to říct.** Baton nese, co má nové
sezení udělat po restartu (`Next task`, `Branch`, `Slug`); blok `NOW` nese, na
co se **právě teď čeká**. Baton je instrukce k obnovení, blok je stav čekání.
Bez toho rozlišení bude implementátor stavět druhý baton.

Blok má dva adresáty a je potřeba je jmenovat oba, protože si vybírají jiné
položky: **vlastní nástupkyni po pádu sezení** (odtud tvar položek) a
**správce, který se dívá zvenčí** přes `mb-epic-run status` (odtud stavová
třída níž). Předchozí verze psala „ne pro cizího čtenáře" a implementátor
volící obsah podle té věty by vynechal přesně to, co správce potřebuje.

Čtyři pravidla, všechna v operačním tvaru, protože série v1–v5 dokázala, že
**formulace se poruší i tomu, kdo ji napsal**:

1. **Ohraničení je strojové, ne nadpis** — komentářové značky začátku a konce.
   Přímá oprava měřeného selhání, kdy vložení sekce před textovou kotvu
   skončilo uvnitř odstavce, který o té kotvě mluvil.
2. **Přepis je „smaž oblast a rekonstruuj z gitu, tabulky tasků a indexu
   rulingů", ne „napiš to znovu".** Z prázdné oblasti není k čemu připisovat.
3. **Blok nesmí být jediným domovem žádného faktu** — nutná podmínka pravidla 2.
4. **Spoušť je strukturální:** další dispatch se skládá **z** toho bloku. A
   kontrolní věta: *když si blok a `git log` odporují, blok je špatně.*

**Blok a jeho pravidla se nesmí dát převzít odděleně** — naměřeno; pravidlo
patří do téhož odstavce jako artefakt.

**Dvě strojově čitelná pole navíc, a jsou to ta, která řeší měřenou bolest.**
Blok, který se musí přečíst, má tutéž vadu jako `idle` — pořád potřebuje toho,
kdo se podívá, a měřená cena nebyla „co", ale „jak rychle si toho někdo
všiml". Proto:

- **stavová třída** z uzavřeného výčtu: stojím / čekám na subagenta / čekám na
  člověka / čekám na správce. To je přesně ta dvojznačnost `idle`, kterou
  správce čtyřikrát odhadl špatně, a je to dvouhodnotové pole, ne próza;
- **očekávaný čas dalšího ohlášení**. `pool-status.ps1` z něj **spočítá sloupec
  „po termínu"** — tabulka poolu pak řekne, že sezení stojí, aniž to někdo
  musel číst.

**Bezpečnost čtenáře jako u batonu.** `pool-status.ps1` parsuje gitignorovaný
soubor v **cizím** pracovním stromě a `mb-epic-run status` ho renderuje do
kontextu správce — do toho souboru přitom rutinně píšou implementátorské
subagenty. Platí proto tatáž pravidla, která kontrakt zavedl pro baton: formát
je uzavřený, čtenář tělo **nikdy nevypisuje tak, jak leží**, ale parsuje,
re-renderuje, omezuje velikost a odmítá znaky mimo povolenou třídu. Chování při
zdvojené nebo vnořené koncové značce musí být definované.

**Hranice, kterou blok nesmí překročit:** jednou zavedl, a právě v tu nejdražší
chvíli. Proto **blok slouží k rozhodnutí, kam se podívat, nikdy k rozhodnutí
integrovat** — fast-forward stojí na bráně předání a na kontrolách operace `integrate`.

**Kde blok NEEXISTUJE, a je to omezení, ne vlastnost.** Žije v
`.superpowers/sdd/<plan>/progress.md`, který SDD na konci maže, a
`pool-status.ps1` ho renderuje jen dokud slot nese pin. Během brainstormingu,
psaní plánu, design review a **celého dokončování včetně integrace** tedy blok
není. Pravidlo o konci turnu (část 8) proto jmenuje blok jen tam, kde blok je;
jinde se čekání jmenuje v hlášení. Dát bloku životnost pracovní položky je
navazující položka, ne součást tohoto návrhu.

### 8. Eskalační tabulka a autonomie

„Kdy zastavit" a „kolik zastavit" **nejsou veličiny, které by operátor točil** —
jsou to pravidla, a mají operační tvar:

> Konec turnu je legitimní jen tam, kde čekáš na odpověď člověka, na odpověď
> správce, nebo na doběhnutí subagenta — a **to čekání musí být pojmenované**:
> tam, kde blok `NOW` existuje, jeho stavovou třídou; jinde v hlášení. Co nejde
> pojmenovat, není důvod končit turn.

> Když formuluješ otázku, vyjmenuj, co na odpovědi nezávisí, a to udělej hned.

Veličina, kterou operátor nastavuje, je **kdo řeší který druh eskalace**. Výčet
má tři pásma; dvě jsou pevná. **Každý druh má řádek se stavem v ledgeru** — to
je jeho artefaktová forma a to, co ho drží funkčním i bez zpráv.

**Dno — vždy člověk, žádná úroveň to nezvedá**

| Typ | Příklad z praxe |
|---|---|
| Publikace do dodávkové linie | východ epiku |
| Nevratná nebo destruktivní operace | mazání větve, force push, přepis historie |
| Bezpečnostně citlivá akce | přístupy, tajemství |
| Volba báze, která není chráněná větev | dnešní fail-closed STOP |
| Změna `epicBranchPattern` nebo `protectedBranches` | rozšíření výsady |

**Vždy správce — dolů to nejde, protože právě tohle se z člověka sundávalo**

| Typ | Příklad z praxe |
|---|---|
| Pořadí a fronta integrací | dva tikety ověřené proti témuž epikovému tipu |
| Pokyny k resynchronizaci a průřezový relay | „integruj si epikovou linii" |

**Přesouvatelné — tady je ta veličina**

| Typ | Příklad z praxe |
|---|---|
| Nález třídy 3 | TTL okna 60 s natvrdo, bez konfiguračního klíče |
| Rozpor rozsahu nebo vlastnictví mezi tikety | čí je `EmployeeResolver` |
| Vada plánu — každá cesta vpřed je hádání | zadání zapojení chybné na šesti místech |
| Změna zadání tiketu | rozsah je jinde, než se myslelo |

Tři pojmenované úrovně nad přesouvatelným pásmem:

- **Dohled** — všechno přesouvatelné jde k člověku; správce koordinuje.
- **Sdílená** (výchozí) — rozpory rozsahu, nálezy třídy 3 a vady plánu řeší
  správce rulingem; změna zadání tiketu jde k člověku.
- **Delegovaná** — i změnu zadání tiketu řeší správce rulingem a reportuje ji.

**Jedna věc do výčtu záměrně nepatří.** Pokyn, který odporuje psanému pravidlu,
**není eskalace — je to vyhledání.** Příjemce ho odmítne a odkáže na pravidlo;
teprve když je pravidlo skutečně nejednoznačné, jde otázka **k člověku, nikdy
ke správci**, protože správce je v tom sporu stranou.

**Kde se hodnota čte.** Epik ji deklaruje jednou ve svém ledgeru; řádek
`Rozjetí` dostává sloupec pro přepsání u konkrétního tiketu. Sezení si ji tahá
z commitnutých dokumentů — správce do slotu nezapisuje nic.

## Stavy mimo šťastnou cestu

Protokol části 2 má jednu cestu; tohle jsou stavy, které musí být pokryté, ať
je řeší kdokoli.

| Stav | Řešení |
|---|---|
| Tiket se **opouští**, ne dokončuje | `mb-abort` na tiketové větvi, publikovaný — nepublikované opuštění nechá na `origin` ACTIVE pin a trvalou `KOLIZE AKTIVNÍ PRÁCE`. Do epikové linie se nic neintegruje; správce uzavře řádek `Rozjetí` a řádky registru, které tiket vlastnil. |
| Tiketové sezení **umře mezi krokem 3 a 4** | Práce je na `origin` (publikuje se po každém commitu), hlášení chybí. Nástupkyně ho složí z vlastní větve a ledgeru; správce to pozná ze sloupce „po termínu". |
| **Umře správce** | Epiková linie se nehýbe, což je bezpečný stav. Novým správcem je sezení, které vyzvedne řídicí větev — git exkluzivitou je to nejvýš jedno v rámci poolu. Fronta se rekonstruuje z ledgeru. |
| Sezení dostane pokyn integrovat, ale **mezitím se epiková linie pohnula** | Brána předání to odmítne proti čerstvě staženému tipu a vyžádá resynchronizaci. Strop dvě neúspěšná kola, pak STOP a report. |
| Epik **nemá deklarovanou ověřovací sadu** | Fail-closed STOP u první integrace. |
| Pracovní položka **nemá Jira tiket** | Řádky ledgeru se klíčují slugem; krok 8 přeskočí finalizaci a ověření dosažitelnosti proběhne i tak — jeho brána na Jiře nezávisí. |

## Rozhodnutí a jejich důvody

| Rozhodnutí | Důvod |
|---|---|
| Dvě větve na epik | Jedna větev nesla dvě role a stálo to čtyři opakované konflikty a dva úniky ACTIVE pinu. |
| Řídicí větev je existující elaborační větev, bez pinu | Elaborace je definovaná jako práce bez pinu; nová větev by rozdvojila místo, kde spuštěná sezení hledají ledger. |
| Post-harvest `context.md` je bajt po bajtu stejný napříč tikety epiku | To je ten invariant, který konflikt odstraňuje; samotné rozdělení větví ho neodstraní. |
| Vypuštění řádku `Jira:`, a to univerzálně | Na každé větvi, kam integruje mnoho tiketů, „poslední pracovní položka" nedává smysl. Je to jeden ze dvou měřených zdrojů opakovaného konfliktu a druhý z nich se stal na dodávkové lince — psát tu opravu jen pro epik by ji zavedlo tam, kde se ta chyba nestala. Vědomá odchylka od kontraktu. |
| `epic/*` do `protectedBranches`, `epicBranchPattern` jen pro výjimku | Změřeno, že samotný nový klíč nefunguje ani v jednom směru: základna nejde zvolit a guard mlčí. |
| Jedna procedura pro oba režimy, dělení podle AKTÉRA | Rozhodnutí uživatele: dvě odlišné složité formulace v jednom skillu nejsou efektivní. Průchod návrhem našel patnáct větvení a deset z nich s epikem nesouviselo. Správcova práce je vlastní skill, protože je to jiná role, ne druhá varianta téhož. |
| Brána a kanonický IDLE platí univerzálně | Obě měřené vady, které opravují (únik ACTIVE pinu u 242, dvakrát přepsaný výčet commitů u 244), se staly MIMO epikový režim. |
| Předání integrace je jeden artefakt se dvěma vykresleními | Jediná podmínka celé procedury je „je správce?"; všechno ostatní je společné. |
| Elaborace epiku se tiketovému sezení přestává nabízet | Rozhodnutí uživatele: rozpracování epiku přísluší jeho správci. Navíc je to zastavení navíc přesně tam, kde bylo naměřeno deset zbytečných, a přepnutí větve uprostřed tiketu je práce na dvou položkách zároveň. Zaniká nabídka, ne nález — zápis do ledgeru zůstává. |
| `epicBranchPattern` se čte z pracovního stromu, bez zvláštního zacházení | Rozhodnutí uživatele: nepočítá se s diverzí agenta, konfigurace ani skripty se před agenty nechrání. Vrstva brání omylu, ne úmyslu — týž model důvěry jako u `MB_HUMAN_PUSH`. Čtení z báze bylo zvažováno a zamítnuto jako složitost, která za tohoto předpokladu nekupuje nic. |
| Výjimka podmíněná i tvarem pushe (surové SHA) | `switch -c` nastaví upstream na epikovou linii; bez toho by holý `git push` prošel oběma vrstvami. |
| Chráněnost kupuje dvě věci, ne čtyři | Zákaz mazání a force pushe platí na každé větvi. Nafouknutý výčet oslaboval správné rozhodnutí. |
| Třetí kategorie se přiznává | Vzniká „chráněná větev, do které agent smí" — jen v aktérské vrstvě místo ve volbě báze. |
| Brána předání je skript, ne checklist | `mb-state` ten invariant měl a mlčel, protože ho nikdo nespustil. Táž vada o aktéra dál. |
| Brána porovnává proti čerstvě staženému tipu | Proti nahlášené hodnotě projde přesně v tom případě, kvůli kterému existuje. |
| Registr rozhodnutí s potvrzením jako mechanická zábrana | Jediný měřený záchyt třídy 3 stál na tom, že si správce náhodou vzpomněl. |
| Behaviorální předpoklad se zavírá testem | Oponentura vrátila čistý zápor: žádný levnější nástroj to nechytí. |
| Sdílené rozhraní je stub na epikové lince | Dělá z překladače orákulum; ruling by příští signaturu kontrolovatelnou neudělal. |
| Kroky 6–8 zůstávají tiketovému sezení | Kontrakt: životní cyklus běží na větvi toho tiketu. |
| Blok dostává stavovou třídu a termín | Blok, který se musí přečíst, má tutéž vadu jako `idle`; termín dělá ze sloupce výpočet, ne pozorování. |
| Každé pásmo eskalace má artefaktovou formu | `SendMessage` je harness-specifické lepidlo a ve vrstvě se dnes nepoužívá nikde. |
| Zachovány čtyři třídy konfliktů | Rozhodnutí uživatele: výčet učí rozpoznávat druh selhání, i když tři z nich vedou k témuž jednání. |
| Zachovány tři úrovně autonomie | Rozhodnutí uživatele. |
| Agentní push do epikové linie zachován | Rozhodnutí uživatele po předložení protiargumentu; riziko je pojmenované v Rizicích a nese ho model hrozby (omyl, ne úmysl), ne mechanismus. |
| Epiková linie vzniká jen pro nesamostatně dodatelné tikety, a zaniká | Collaboration branch je ústupek s podmínkou, ne výchozí volba; bez zániku roste seznam chráněných větví donekonečna. |

## Dopady

**Na kontrakt.** Sekce Integration dostává **bránu předání a artefakt předání
se dvěma vykresleními** — a to je největší dopad celého návrhu, protože platí
pro **každou** integraci v repu, ne jen epikovou. Dál: epiková linie a její
protokol; `epic/*` mezi chráněnými větvemi a klíč `epicBranchPattern`
s jediným konzumentem; odchylka IDLE resetu (univerzální); registr rozhodnutí;
eskalační tabulka a tři úrovně autonomie; a přiznání třetí kategorie
v aktérské vrstvě. Je to větší zásah do Publication Contract než UMS-3488.

**Na `guard-git-push.mjs`.** Trojnásobně podmíněná výjimka, jeden nový klíč
čtený týmž způsobem jako `protectedBranches`, oprava case-insensitivity
v `stripRef` a negativní testy. Je to 732řádkový soubor s 1104 řádky testů;
zásah do něj je sám o sobě riziko.

**Na `mb-harvest`.** Kanonický IDLE v existujícím resetu — žádný nový
zapisovatel `context.md`. **Platí univerzálně**, ne jen v epikovém režimu.
Plán musí ověřit, odkud `mb-jira-update` po harvestu bere klíč tiketu.

**Na `finishing-a-development-branch`.** Jedna procedura pro oba režimy:
brána předání, artefakt předání, a **jediná podmínka** rozhodující o jeho
vykreslení (příkaz člověku / zpráva správci). Overlay se nerozdvojuje na dvě
sekvence — to je celý smysl tohohle uspořádání.

**Na `mb-epic-run`.** Nová operace `integrate` — správcova strana předání.
Nese dvě epikové kontroly, úsudkovou kontrolu proti ledgeru a fast-forward
refspecem. Její `allowed-tools` musí krýt `git push`, `Edit` a git zápisová
slovesa ve VLASTNÍM repozitáři skillu; pole restringuje, ne jen předschvaluje.

**Na `mb-epic-elaboration`.** Ledger dostává sekci registru rozhodnutí a
deklaraci ověřovací sady; uzávěrka okna nabízí založení epikové linie
připraveným příkazem **v tvaru s `MB_HUMAN_PUSH=1`**.

**Na overlay `brainstorming`.** Epic Backflow check **přestává nabízet inline
elaborační okno**; zapíše nález do ledgeru a pokračuje. Nabídka se ruší
v obou režimech, protože důvod je vlastnictví práce, ne topologie větví.

**Na UMS-3488.** `pool-status.ps1` dostává pole `progress.now` se stavovou
třídou, výpočet sloupce „po termínu" a čtenářská bezpečnostní pravidla; řádek
`Rozjetí` sloupec pro úroveň autonomie. Železné pravidlo „do slotu se
nezapisuje" platí beze změny.

**Na `mb-doc-index`.** Nález „epiková linie bez epiku" — je to jediný skill,
který enumeruje refy na `origin`.

**Na ostatní harnessy.** Blok `NOW` je čistý Markdown a přenese se; eskalace
mají artefaktovou formu, takže se ztrácí rychlost, ne správnost. **Pozor
ale:** `pre-push` vynucuje jen tam, kam dorazí značka agentní relace — na
harnessu, kde nedorazí (kontrakt jmenuje Kilo Code), nemá epiková linie žádnou
mechanickou ochranu.

## Rizika

**Dosah je širší, než na kolik je evidence.** Brána předání a kanonický IDLE
platí pro **každou** integraci v repu, ne jen epikovou — a je to vědomé, protože
obě vady, které opravují, se staly mimo epikový režim. Ale je to zásah do cesty,
kterou dnes projde všechno; regrese tam se neprojeví na epiku, nýbrž na běžné
práci. **Aditivní varianta byla zvažována a zamítnuta** (opravovala by vady tam,
kde se nestaly), takže tohle riziko je cena za to rozhodnutí, ne přehlédnutí.

**Celá topologie je neověřená.** Model „tikety odštěpené z epikové linie a
fast-forward" nikdy neběžel. Naměřená je bolest, kterou má léčit, ne lék.

**Výsada agentního pushe je konfigurovatelná, a tím rozšiřitelná — a stojí to
na modelu hrozby, ne na mechanismu.** Kdo změní `epicBranchPattern`, rozšíří
i výsadu; hodnota se čte z pracovního stromu, takže na to nestojí v cestě nic
kromě toho, že se s diverzí agenta nepočítá. **Toto riziko bylo uživateli
předloženo dvakrát** — nejdřív s doporučením výjimku zrušit úplně, podruhé
s návrhem číst hodnotu z báze — a uživatel obojí rozhodl proti: výjimka
zůstává a konfigurace se před agenty nechrání. Zůstává tedy jako riziko, ne
jako otevřená otázka. **Kdyby se model hrozby někdy změnil, tenhle klíč je
první místo k přehodnocení** a čtení z báze je připravená mitigace.

Změna `epicBranchPattern` i `protectedBranches` je přesto v eskalační tabulce
na dně, u člověka — ne z nedůvěry, ale proto, že rozšíření výsady je
rozhodnutí, a kontrakt u změn konfigurace repozitáře schválení vyžaduje tak
jako tak.

**Známé obchvaty guardu jsou teď na horké cestě.** `--no-verify`, jednorázový
`core.hooksPath` a git alias zastupující `push` (změřeno: `git -c alias.zz=push
zz …` guard mlčky pustí) byly dosud přijatelné, protože pravidlo podle aktéra
bylo kategorické. Teď vedou přímo k pushi do chráněné větve. Skutečným
backstopem zůstává ochrana větví na serveru, kterou tahle vrstva nemá.

**„Ověřeno" zůstává tvrzením, které nikdo nepřeověří.** Brána pokrývá pohnutý
tip, ACTIVE pin, cizí epik a nepotvrzené rozhodnutí — nedokazuje, že build byl
zelený, a je doložený případ převzatého nepravdivého tvrzení reviewera. Ani
nedetekuje, že se `<SHA>` posunulo *po* napsání hlášení: tiketový agent smí mezi
kroky 4 a 6 pushnout další commity a kontrola předchůdcovství projde dál.
Jediný uzávěr je build server.

**Serializace může být dražší, než vypadá.** Každá integrace zneplatní ověřený
merge všech ostatních čekajících tiketů. Hrubý odhad, kdy to přestává platit:
**čtyři až šest souběžných tiketů** — při kvadratickém růstu ověřovacích cyklů a
plném buildu na každé ověření; správce sám je při třech na 80 % koordinace, tedy
saturuje ve stejném pásmu. Pojmenovaný únik je **dávkování s bisekcí**, kde
batch skládá tiketový agent; spouštěcí podmínka je „jedno ověření trvá déle než
odstup mezi integracemi". Změřeno to není.

**Správce je jediný bod průřezové kontroly — a je to agent.** Registr, stub a
brána z něj sundávají všechno, co šlo převést na mechanismus; zbytek je úsudek
a ten se porušuje, měřeně i svým autorem.

**Pravidla bez mechanické spouště jsou v tomto návrhu doporučení, ne brány.**
Jmenovitě: obě pravidla o pravomoci správce, tvrdý strop o editaci cizího kódu,
pravidlo o příčině a hranici, značení *pokyn* / *domněnka* a právo domněnku
odmítnout, relay timing, jeden živý odběr na peera, a „blok slouží k rozhodnutí
kam se podívat". **Návrh je takto označuje záměrně**, aby je implementátor
nezapsal do skillu, jako by byly vynucené. Uživatel dřív rozhodl, že mechanická
spoušť není závazným kritériem.

**Artefakt putuje, pravidlo ne — a je to naměřené.** Kdykoli se odsud do skillu
dostane TVAR a jeho vynucující pravidlo zůstane vedle, převezme se jen tvar.

**I operace selže, když je její kotva textová.** Doloženo hodinu po zavedení v8.

**Zásah do `guard-git-push.mjs` je sám riziko.** Nejbezpečnostněji citlivý soubor
vrstvy; a jeho vlastní chování má měřené mezery (case-sensitivní `stripRef`,
zamítnutí celého tool-callu u víc refspeců v jednom příkazu — takže zakládání
epikové linie vedle řídicí větve se musí rozdělit do dvou příkazů).

**Konvence jména je sebeudělitelná — pro člověka.** Agent si `epic/cokoli`
nezaloží, první publikaci hook zamítne (změřeno). Riziko je u člověka a u těch
tří obchvatů výše.

## Verifikace

1. **Fast-forward na epikovou linii projde jen ve tvaru protokolu.** Pozitivně:
   `<SHA>:refs/heads/epic/<KLÍČ>` se surovým, publikovaným SHA. Negativně: nový
   obsah, force push, mazání, **první publikace větve**, a **`HEAD:` nebo jméno
   větve jako zdroj**.
2. **Agentní push do dodávkové linie neprojde ani omylem** — ani jako
   fast-forward, který by hook pustil.
3. **JEDNA PROCEDURA — nejdůležitější test celého návrhu.** Tentýž průchod
   `finishing` musí projít pro pracovní položku s dodávkovou bází i pro
   položku s epikovou bází, a **jediné, co se liší, je vykreslení artefaktu
   předání** — příkaz pro člověka proti zprávě správci. Negativně: jakákoli
   druhá podmínka na režim, která se do procedury dostane, musí ten test
   zčervenat. Brána předání, kanonický IDLE a deklarovaná ověřovací sada běží
   v obou případech; jediné, co se v jednotiketovém režimu neděje, je operace
   `integrate` — protože není správce, kdo by ji spustil.
   Chybějící nebo nečitelný `epicBranchPattern` znamená, že epiková linie
   neexistuje, tedy příkaz pro člověka pro všechno — nikdy chybu.
4. **`epicBranchPattern` mimo `protectedBranches` je chyba konfigurace.**
   Kontrola běží na jménech existujících větví na `origin` a proti
   repozitářovému `baseRef`, ne proti efektivní bázi — negativně: **legitimní
   epikový tiket nesmí tuhle kontrolu rozsvítit.**
5. **`Get-UmsBaseCandidates` nabídne epikovou linii** a víceúrovňový glob
   funguje; odvození cíle pushe z `origin/epic/<KLÍČ>` dá `epic/<KLÍČ>`.
6. **Brána předání čte čerstvý tip.** Fixtura: epiková linie se posune mezi
   hlášením a fast-forwardem — brána musí odmítnout. Negativně: brána krmená
   hodnotou z hlášení musí ten případ propustit, což je důkaz, že na tom
   pořadí záleží.
7. **Chybějící `context.md` je STOP, ne IDLE.** A ACTIVE se pozná přítomností
   `Target MB Pin` spolu s `Work item`, ne hledáním slova.
8. **Fast-forward je vázaný na vlastní epik** — commit tiketu, jehož řádek
   `Rozjetí` patří jinému epiku, brána odmítne.
9. **Nepotvrzený řádek registru blokuje.** Fixtura: rozhodnutí 244 jmenující
   243 bez potvrzujícího SHA musí zastavit integraci 243; po potvrzení projít.
10. **Behaviorální předpoklad se zavírá testem**, ne přečtením — negativně:
    potvrzení bez testu u řádku označeného jako behaviorální neprojde.
11. **Sdílené rozhraní se překládá dřív, než proti němu někdo implementuje** —
    stub na epikové lince, a merge nepřekládající se signatury musí spadnout
    na překladači, ne až na review.
12. **Epik bez deklarované ověřovací sady je STOP** u první integrace; hlášení
    musí sadu citovat doslova a brána ji porovnat jako text.
13. **Post-harvest `context.md` dvou tiketů téhož epiku je bajt po bajtu
    shodný**, a merge druhého do epikové linie neprodukuje konflikt v tom
    souboru. Negativně: ponechaný řádek `Jira:` ten konflikt vyrobí.
14. **Kroky 6–8 běží na tiketové větvi** — po pushi správce ověří tiketové
    sezení dosažitelnost z epikové linie a teprve pak finalizuje Jira; bez
    Jira tiketu ta brána běží taky.
15. **Odpojení upstreamu.** Po `switch -c origin/epic/<KLÍČ>` musí holý
    `git push` být zamítnutý — jako pojistka proti zapomenutému
    `--unset-upstream`.
16. **Blok `NOW` je ohraničený strojově**, přežije v próze text vypadající jako
    nadpis, a čtenář ho parsuje a re-renderuje — zdvojená a vnořená koncová
    značka mají definované chování; nadměrná velikost se ořízne.
17. **Přepis bloku je smazání a rekonstrukce.** Negativně: fakt, který má domov
    jen v bloku, musí rekonstrukci nepřežít.
18. **Sloupec „po termínu" se počítá, ne čte.** Fixtura: sezení s propadlým
    termínem se v tabulce poolu objeví jako opožděné bez zásahu člověka; a
    stavová třída „čekám na subagenta" nesmí být důvodem k pobídce.
19. **Rozpor bloku a `git log`** je detekovatelný pravidlem „blok je špatně".
20. **Přeblokování.** Otázka pro člověka musí být doprovázená výčtem toho, co
    na odpovědi nezávisí — a to nezávislé se má opravdu udělat.
21. **Úroveň autonomie mění směrování.** Týž nález třídy 3 jde při úrovni
    *Dohled* k člověku a při *Sdílené* ke správci; dno se nezvedne žádnou
    úrovní, a změna `epicBranchPattern` je na dně.
22. **Každé pásmo eskalace má řádek v ledgeru** — na harnessu bez
    `SendMessage` musí eskalace pořád existovat, jen pomaleji.
23. **Opuštěný tiket** nechá epikovou linii nedotčenou, publikuje `mb-abort` a
    uzavře své řádky ledgeru; negativně: nepublikované opuštění je nález.
24. **Epiková linie bez epiku** je nález `mb-doc-index`, ne mlčení.
25. **`stripRef` v `guard-git-push.mjs` je case-insensitive** —
    `refs/HEADS/<chráněná>` musí být zamítnuto, stejně jako to dělá hook.
26. **Epic Backflow nenabízí elaboraci.** Nález na hranici fáze skončí jako
    řádek v ledgeru a sezení pokračuje; negativně: sezení se nesmí zeptat,
    nesmí přepnout větev a nesmí zastavit. A ten řádek musí být pro příští
    elaborační okno viditelný — jinak se nález ztratil, ne odložil.

## Pořadí úloh (návrh, ne plán)

1. **Topologie a vynucení** — kontrakt, `epic/*` mezi chráněnými,
   `epicBranchPattern` čtený z báze, výjimka a její negativní testy, kanonický
   IDLE v `mb-harvest`, rozdvojení ve `finishing`. Předpoklad všeho ostatního a
   část s mechanickými testy.
2. **Brána a artefakt předání** — skript se třemi univerzálními kontrolami a jedno předání se dvěma vykresleními, ve `finishing`. Dvě epikové kontroly patří operaci `integrate`. Závisí na 1.
3. **Registr rozhodnutí a ověřovací sada** — sekce ledgeru a brána nad nimi.
   Závisí na 2, protože do ní přidává kontrolu.
4. **Blok `NOW`** — ohraničení, stavová třída, termín, čtenářská bezpečnost,
   sloupec v `pool-status.ps1`. Nezávislý na 1 až 3.
5. **Operace `mb-epic-run integrate`** — správcova strana předání: dvě epikové
   kontroly, úsudková kontrola proti ledgeru, fast-forward refspecem. Závisí na
   2 (spotřebovává artefakt předání) a na 3 (čte registr).
6. **Zprávy a eskalační tabulka** — artefaktová forma pásem, značení, relay
   timing, tři úrovně autonomie, a zrušení nabídky elaborace v Epic Backflow.
   Poslední, protože adresáta i viditelnost bere z předchozích.

Otevřená otázka pro plán: **jestli je to jeden tiket, nebo víc.** Body 1 až 3
jsou kontrakt a vynucovací mechanika; body 4 a 5 jsou chování skillů.

## Navazující položky

- **Životnost bloku `NOW` mimo SDD** — dnes zaniká s plan workspace, takže během
  dokončování a integrace neexistuje.
- **Kolik paralelních sezení serializace unese** — odhad 4 až 6, změřeno na
  třech.
- **`--name` po `--resume` a při kolizi dvou sezení téhož jména** — gatuje
  pohodlí adresování, ne správnost.
- **Sloupec `interactive` u neinteraktivních běhů** nerozlišuje režim spuštění;
  nestavět na něm bez měření.
- **Doklady v ledgeru epiku SKODASMS-237** — sezení `ums01` je má a nabídlo je
  k vyžádání.

Doplněno při uzávěrce fáze 3 z procházky seznamu Verifikace a z otázky
položené po ní:

- **Kontrola, že `epicBranchPattern` leží uvnitř `protectedBranches`** (bod 4
  Verifikace) — nikde ve vrstvě neexistuje a žádné sezení ji nemá uloženou;
  eskalační dno dnes kryje jen *změnu* těch klíčů, ne jejich *nesoulad*.
- **Vazba opuštění tiketu na zavření jeho řádků** (bod 23) — `mb-abort` nezavírá
  řádky `Rozjetí` ani registru a pravidlo „nepublikované opuštění je nález"
  není napsané.
- **Epiková logika v `mb-doc-index`** (bod 24) — epiková linie bez epiku je
  dnes ticho, ne nález.
- **Playbook chybí v eskalačním dně.** Zápis do `playbook.md` „vždycky
  schvaluje člověk a žádná úroveň to nezvedá" má přesně tvar řádku dna, ale
  sekce Escalation & Autonomy ho nejmenuje — pravidlo bydlí jen v Playbook
  Contractu. Čtenář tabulky může usoudit, že spadá do pohyblivého pásma.
  Oprava je jeden řádek dna plus odkaz; je to změna kontraktu, tedy vlastní
  tiket.
- **Autonomie tvorby playbooku v plně autonomním režimu** — orchestrace
  tiketů nesmí stát na nepřítomném člověku, kandidáti se mají zapracovávat
  autonomně a další práce je ověřuje použitím. Změna kontraktu nejvyšší třídy
  (playbook je preskriptivní, špatná položka je závazné pravidlo, ne špatná
  informace). Stavební kameny z existujících vzorů vrstvy: autonomní položka
  je domněnka až do potvrzení použitím (Message Protocol; stavy `navrženo` →
  `ověřeno` → `vyvráceno`); závazné vs. doporučené položky; pole `Confirms:`
  v reportu implementátora, aby se potvrzení použitím **zaznamenávalo**;
  nedestruktivnost vůči lidsky autorizovaným položkám; commitnutá fronta
  úsudkových kandidátů místo blokující brány; dedup při sběru a stárnutí
  nepotvrzených. Dataset pro návrh vzniká z triáže kandidátů tohoto work
  itemu (kritérium × mechanické/úsudkové × hlasité/tiché selhání).
