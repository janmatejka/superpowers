# Playbook
<!-- playbook-budget: 600; baseline: 842 (2026-09-24) -->

Postupy, kterými se tato vrstva staví, testuje a nasazuje. Popisný stav — verze
a piny, inventář souborů, konfigurace, pasti prostředí — je v
[tech.md](tech.md); jak vrstva funguje, popisuje [architecture.md](architecture.md).

## Pro celý podstrom

### Když spouštíš sadu nebo důkazní běh

- **Handoff bránu ověřuj DOSLOVNÝM příkazem z `## Ověřovací sada`; PowerShellová
  smyčka je legitimní náhrada jen pro průběžné ověřování za vývoje, ne pro
  citaci vůči bráně.** Proč: brána porovnává citovaný text jako řetězec, ne
  funkční ekvivalenci nástroje. Důkaz: 0a13ef1
- **Deklarovaný ověřovací příkaz s `\"` a zároveň `$(...)`/`$var` spouštěj na
  Windows přes `cmd.exe /c`, text příkazu neuprav.** Proč: PowerShell i Bash
  `\"` čtou jinak než MSVCRT argv escaping a příkaz selže; `cmd.exe /c` ho
  předá beze změny. Důkaz: 3f811a6
- **Zamítnutí nástroje „Security Weaken“ nad hook/guard souborem ber jako
  KONEČNÉ pro ten soubor** — neopakuj pokus, padni na cílený běh bez
  destruktivní mutace a mezeru v důkazu ohlas. Proč: i scoped, hned
  revertovaná probe byla zamítnuta rovnou. Důkaz: 0a13ef1
- **Byla-li oprava aplikována dřív než RED běh proti původní logice,
  `git stash push --keep-index -- <cesta>` vrátí jen ten soubor; spusť RED,
  pak `git stash pop`.** Proč: jednosouborový stash izoluje obnovu beze
  zásahu do zbytku stromu. Důkaz: 0a13ef1
- **Edituje-li se hook se svým colokovaným testem v jednom commitu,
  `git stash push -- <cesta-k-hooku>` (bez `--keep-index`) vrátí jen hook s
  novým test case na místě; spusť RED, pak `git stash pop`.** Proč: umožní
  čistý RED bez ruční rekonstrukce staré verze hooku. Důkaz: 3f811a6
- **Před negativním během proti merge-base baseline pro VLASTNÍ nové asercie
  ověř, jestli sadu dřív neukončí starší asercie JINÉHO tasku ve stejném
  souboru.** Proč: pád na cizí, dřívější asercii znamená NEPROVEDENO pro
  vlastní asercie, ne důkaz pro ně. Důkaz: 0a13ef1
- **Prázdný `git diff` po obnově souboru z negativity-checku nic nedokazuje
  pro netrackovaný (`??`) soubor** — ověř `git status --short`, pak porovnej
  s pre-mutační zálohou. Proč: prázdný diff mlčí před i po chybné obnově.
  Důkaz: 44ccb57
- **Nese-li mutovaný soubor nekomitované úpravy ze stejné vlny, obnovuj
  zálohou (`Copy-Item`/`Move-Item -Force`), ne `git checkout --`**, a ověř
  `sha256sum`+`cmp` proti záloze. Proč: checkout by zahodil i nekomitnutou
  práci ze stejné vlny. Důkaz: 44ccb57
- **Tvrzení „stav/počet X je takový“ ověřuj strojově v TOMTO běhu**, na
  případu, kde má detektor NĚCO najít, ne kde má vrátit prázdno; zelené
  asercie s očekávaným `$null`/`''` v RED běhu nic nedokazují. Proč: negativní
  běh je bezcenný tam, kde je „nic“ legitimní stav. Důkaz: 7da3545
- **Tvrzení briefu „tahle asercie je právě teď červená“ ověř spuštěním
  v TOMTO běhu, nikdy převzetím z briefu/review.** Proč: loose substring
  aserce může být zelená ještě před úpravou, protože stejný literál leží
  jinde v souboru. Důkaz: 3f811a6
- **Počty asercí v dokumentaci vždy získej spuštěním CELÉ sady ve stejném
  sezení**, nikdy aritmetikou nad staršími čísly; součet i počet sad počítej
  strojově, ne ručně nebo z vlastního seznamu dávek. Proč: ruční součet
  i staré review číslo se v praxi rozešly s naměřeným. Důkaz: 7da3545
- **Smyčku přes všechny sady spouštěj jedním FOREGROUND voláním s timeoutem
  600000 ms, nikdy na pozadí; přesune-li se i tak, nejvýš jeden opakovaný
  pokus, pak STOP a report.** Proč: notifikace o dokončení jde koordinátorovi,
  ne subagentovi, který ji nemá jak spotřebovat. Důkaz: 0d40535
- **Úklid throwaway fixtury přes `rm -rf` volej samostatně, ne zřetězeně
  `&&`/`;` s dalšími příkazy; odmítne-li nástroj i izolované volání, fixturu
  v OS temp nech ležet.** Proč: bezpečnostní hlídka reaguje na `rm -rf`
  v řetězci bez ohledu na cíl. Důkaz: 0d40535
- **Hlídka nad `rm -rf` reaguje i na cíl schovaný za `$(...)` substitucí** —
  indirekce ji neobejde. Proč: `rm -rf "$(cat ...)"` bylo zamítnuto stejně
  jako přímá cesta. Důkaz: 4d72c46
- **Při vlně rozšiřující sadu i kód spusť vedle nové sady i HEAD verzi TÉŽE
  sady proti novému kódu** (dočasný soubor v `tests/`, po běhu smaž). Proč:
  součet per-suite čísel sám neřekne, jestli rozdíl je jen z nových asercí.
  Důkaz: 0d40535
- **Při bisekci velké sady dělej `sed -n` probe kopie VE STEJNÉM adresáři
  jako originál**, po skončení smaž. Proč: `$PSScriptRoot`-relativní cesty
  jinde vyžadují ruční přepis. Důkaz: 0d40535
- **Pass/fail českých PowerShellových sad posuzuj z markerů (`FAIL`,
  `<N> passed`, exit kód), ne z prózy.** Proč: české hlášky se v tomhle
  prostředí vykreslují jako mojibake kvůli code page. Důkaz: e0eb939
- **Obnovu netrackovaného cíle mutace ověřuj hashem, ne gitem**; zálohu a
  její SHA-256 zapiš do trvalého artefaktu, ne jen do transkriptu. Proč: git
  je vůči mutacím netrackovaného souboru slepý oběma směry. Důkaz: e0eb939
- **Testovací regex, který potřebuješ vidět bez truncation, nikdy nerekonstruuj
  v throwaway skriptu — spusť reálný test a čti výstup.** Proč: Přepis tiše
  ztratil literální backtick a podhodnotil legacy nálezy o tři. Důkaz: 3f811a6.
- **Test/důkazní běh nad hookem, který si config dohledá podle `cwd`,
  spouštěj z pracovního adresáře cílového repozitáře (`cd "$root" && …`).**
  Proč: běh spuštěný odjinud četl config repa, odkud byl instalátor
  spuštěn, ne fixture repa. Důkaz: 7da3545.

### Když píšeš nebo měníš test

- **Sada leží vedle kódu, který testuje**, v `tests/`, jako `<téma>.tests.ps1`.
  Proč: kolokace drží testovaný kód a jeho sadu dohledatelné pohromadě.
  Důkaz: 1a03314
- **Testy běží offline** — vzdálený repozitář nahraď lokálním bare klonem jako
  „origin".** Proč: sada nesmí záviset na síti, jinak červená neznamená
  regresi, ale výpadek okolí. Důkaz: 1a03314
- **Test na rozpoznání přejmenování gitem přidej `--find-renames` explicitně.**
  Proč: bez flagu závisí na configu `diff.renames`, který se liší mezi
  verzemi gitu. Důkaz: c38e039
- **Read-only nálezy ověřuj i spuštěním proti skutečnému repozitáři, ne jen
  proti fixtuře** (náhledový režim bez `-Apply` nic nemění). Proč: fixtura
  dokazuje jen shodu s vlastním zápisem, skutečné repo dokazuje, že bug byl
  reálný. Důkaz: c38e039
- **Nový regresní strážce ověř jeho vlastní negativitou** — spusť i proti
  neopravenému kódu / dočasně smaž hlídanou podmínku, čti KTERÉ asercie
  zčervenají, pak soubor obnov. Proč: asercie zelené v obou bězích jsou
  zámek, ne důkaz opravy. Důkaz: 7da3545
- **Mutaci udělej sebedokazující: smaž podle ČÍSLA ŘÁDKU (ne `sed` s
  regexem), ověř `grep -c` = 0, teprve pak spusť sadu; kotva musí být
  víceřádková a jedinečná (grep count 1).** Proč: přerušený řetěz příkazů
  nechá sadu běžet nemutovanou beze zprávy. Důkaz: 41641a2
- **Negativní běh čti ve TŘECH kategoriích: zčervenalo, zůstalo zeleně
  (zámek), NEPROVEDENO (za bodem přerušení)** — pole možná nepřítomného
  objektu čti přes guardovaný accessor (`-join`), ne přímým `.Pole`. Proč:
  sada, která uprostřed umře, za bodem smrti neměří nic. Důkaz: 44ccb57
- **Po negativitě ověř OBOUSMĚRNĚ, že zčervenaly právě briefem jmenované
  asercie** — víc červených je úplnější důkaz, míň signalizuje alibi fixturu.
  Proč: alibi případ projde už dřívější, starší podmínkou. Důkaz: 44ccb57
- **Před psaním indexových guardů spusť mutaci a přečti, KTERÝ index selže
  první; guarduj CELOU zasaženou kolekci, ne jen review-vzorkované indexy**
  — redundantní guard nech s komentářem proč. Proč: guard jen jmenovaných
  řádků nedovolí sadě ohlásit vlastní selhání. Důkaz: 44ccb57
- **Zúžení řádkového filtru nad artefaktem s instancemi v terénu potřebuje
  detektor migrace a hlášku pro každou zahozenou řádku** — filtruj na počet
  skutečně čtených buněk. Proč: špatný filtr tiše zahodí staré řádky beze
  zprávy. Důkaz: 41641a2
- **Negativní asercii piš na KLÍČ PLUS token jedinečný pro testovanou sekci**,
  nikdy na identifikátor legitimně stojící i jinde v reportu. Proč: token,
  který je zároveň členem jiného seznamu, negaci nerozliší. Důkaz: 41641a2
- **Podmíněný důkazní krok drž na TŘECH stavech** (`$null` = neproběhlo),
  přeskočení vždy ohlas vlastní poznámkou a do agregace přidávej jen pod
  `if ($null -ne $result)`, nikdy prostým AND. Proč: naivní AND se srovnáním
  proti `$null` zezelená/zčervená náhodou. Důkaz: 7da3545
- **Jméno vymyšlené testem pro pozitivní kontrolu (větev, soubor) prověř
  proti reálné konfiguraci uživatele**, měj víc kandidátů a vezmi první
  nekonfliktní; bez něj krok přeskoč a ohlas. Proč: pevné jméno může narazit
  na existující ochranné pravidlo uživatele. Důkaz: 7da3545
- **Aserce o tabulkovém řádku musí číst datové řádky té tabulky, nikdy celý
  soubor jako řetězec**; spáruj kontrolu „klíč právě v jednom řádku“
  s kontrolou počtu řádků. Proč: substring match zůstane zelený i po smazání
  řádku, jehož klíč leží jinde v souboru. Důkaz: 3f811a6
- **V kontrole „X je referencováno odněkud“ vylučuj z prohledávané množiny
  VLASTNÍ soubor X.** Proč: referenční soubor cituje sám sebe v hlavičce,
  bez vyloučení je aserce splněná bezpodmínečně. Důkaz: 3f811a6
- **Fixture repo pro testy nad stářím commitu nastavuj datem jako věk ve
  dnech vůči vytvoření fixtury** (`GIT_AUTHOR_DATE`/`GIT_COMMITTER_DATE`),
  ne absolutním datem. Proč: absolutní datum jen na jedné větvi by časem
  změnilo verdikt sady. Důkaz: 7da3545
- **Vložení testu „na konec, před `Complete-Tests`“ ověř trojmo: pomocné
  funkce definované, fixtura v tom bodě žije s historií, a nic mezi stavbou
  fixtury a vloženým místem stav nemutuje.** Proč: doslovné čtení narazilo
  na fixturu už smazanou dřívějším blokem. Důkaz: 41641a2
- **Před test case pozdě v sekvenci sdílející `$work` s desítkami
  předchozích případů zjisti STROJOVĚ stav klíčové větve** (local vs.
  remote). Proč: case, který dřív nechal větev divergentní, otráví každý
  pozdější prostý push. Důkaz: 0d40535
- **Před stavbou fixtury na faktu z ledgerového `Ruling:` ověř fakt strojově
  v aktuálním sezení** (`ls`/`Get-ChildItem`); mýlí-li se fakt, dodrž
  rozhodnutí a oprav jen nejužší dotčenou část fixtury. Proč: ruling měl
  správné číslo, ale špatné členství. Důkaz: 4d72c46
- **U nového kontrolního případu si odpověz, KTERÝ mechanismus na něj
  dopadá; vyřazuje-li ho jiný, starší mechanismus, je to zámek, ne důkaz** —
  ověř spuštěním proti kódu před opravou. Proč: zelený případ i bez opravy
  s opravou nesouvisí. Důkaz: 0d40535
- **Asertuj proti syrovému textu, který spotřebitel čte, ne proti hodnotě
  parsované zpátky** — drž si RAW vedle parsovaného objektu. Proč:
  `ConvertFrom-Json` tiše přepíše ISO-8601 řetězec na `[datetime]` v locale
  formátu. Důkaz: 41641a2
- **Po aplikaci briefova doslovného snippetu na guard zkontroluj ZBYTEK
  stejné funkce na další příkazy, jejichž předpoklady nová podmínka
  změnila** (typicky zápis souboru hned za kontrolou existence). Proč:
  zúžený guard může selhat o řádek dál se stejnou asercí. Důkaz: 0a13ef1
- **Mutaci odebraného pole může zastínit ranější kontrola nebo volající** —
  ověř, jestli stejný symptom nepokrývá starší validace nebo call site;
  takový případ hlas jako „nefalzifikovatelný zde“, ne jako nález. Proč:
  case zůstal zelený, protože ho zamítla jiná podmínka dřív. Důkaz: e0eb939
- **Každá podmínka ANDovaného predikátu potřebuje fixturu, kde rozhoduje
  JEN ona; ke každému `-cne` přidej case lišící se jen velikostí písmen.**
  Proč: dvě podmínky odmítající tentýž vstup si dělají alibi a ani jedna
  není dokázaná. Důkaz: 41641a2
- **Asercie `(?m)^slovo$` proti textu z `2>&1 | Out-String` potřebuje na Windows
  `\r?` před `$` — oprav v regexu SADY.** Proč: `Out-String` spojuje řádky přes
  CRLF a .NET `$` kotví jen před holým `\n`. Důkaz: 4d72c46.
- **Izolaci fixture repa od zděděného `core.hooksPath` neřeš prázdnou
  hodnotou (`-c core.hooksPath=`) — vynech override, nebo pinuj reálný
  default (`.git/hooks`).** Proč: prázdná hodnota není „bez override" —
  git lfs zapsal hooky přímo do `$tmp`. Důkaz: 7da3545.
- **Když dvě kontroly v hooku zamítají tentýž vstup, testuj i TEXT
  hlášky, ne jen kód — nedosažitelná hláška je špatné pořadí.**
  Proč: mazání trefilo dřív chráněnou-větev kontrolu, uživatel dostal
  špatnou hlášku, ačkoli verdikt byl správný. Důkaz: 0d40535.

### Když píšeš PowerShell

- **Nikdy nedávej kudrnaté uvozovky dovnitř řetězce v odpovídajících ASCII
  uvozovkách — patří jen do jednoduše uvozeného literálu.** Proč: Řetězec s „ se
  tiše uzavře uprostřed věty beze chyby a bez varování. Důkaz: c38e039.
- **Typografickou uvozovku v dvojitě uvozeném řetězci piš jako escape `u{201E}`
  a ověř zápisem do souboru, nikdy přes `-Command` na řádce.** Proč: PowerShell
  bere U+201E jako ukončovací uvozovku a `-Command` navíc zmangluje znak přes
  code page. Důkaz: 3f811a6.
- **Parametr nesoucí `$null` jako „žádná hodnota" nikdy netypuj `[string]` —
  PowerShell `$null` tiše převede na prázdný řetězec.** Proč: Typová koerce
  zapsala reálný prázdný soubor a vedla bisekci k falešné stopě mimo parametr.
  Důkaz: 3f811a6.
- **Nikdy nepojmenuj proměnnou `$host` ani jinou automatickou proměnnou
  (`$error`, `$input`, `$args`, `$matches`, `$pwd`).** Proč: `$host = ...`
  shodilo sadu na první volání hláškou o proměnné jen pro čtení pod
  `Set-StrictMode`. Důkaz: 3f811a6.
- **Backtick jako markdown code-span v řetězci v DVOJITÝCH uvozovkách piš
  zdvojený, nebo fixturu postav v JEDNODUCHÝCH.** Proč: Osamocený backtick se v
  double-quoted stringu tiše smaže, takže fixtura nenesla tvar, který tvrdila.
  Důkaz: 3f811a6.
- **Musí-li hodnota být kolekce, obal do `@()` CELÝ výraz, ne jen větev uvnitř;
  u volitelného pole testuj `$null -eq $Param` PŘED obalením.** Proč: Obal jen
  kolem větve nezachytí prázdnou pipeline; `@($null).Count` je 1, ne 0. Důkaz:
  4d72c46.
- **`Mandatory` na `[string[]]` parametru odmítne pole s prázdným řetězcovým
  prvkem — ověř, že to smí být člen kolekce.** Proč: Reálná fixtura přestala
  parsovat, ačkoli stejná funkce bez `Mandatory` totéž pole přijala. Důkaz:
  41641a2.
- **Volání funkce vracející `return , $x` nikdy nekombinuj v jednom příkazu s
  enumerací ani obalením — přiřaď do proměnné zvlášť.** Proč: Zřetězený
  `Where-Object` svázal `$_` s CELOU tabulkou místo s jejími řádky. Důkaz:
  41641a2.
- **`Set-Content -Encoding UTF8` v PowerShellu 7 BOM nepřidává (na rozdíl od
  PowerShellu 5.1).** Proč: Ověřeno bajtově — pro UTF-8 bez BOM není potřeba
  obezlička. Důkaz: c38e039.
- **Český výstup ověřuj přes PowerShell tool nebo bajtově (`xxd`), nikdy očima v
  bashové konzoli, i pro CRLF a stderr přes pipelinu.** Proč: Bashová konzole
  zobrazí zkomolený text i u správného UTF-8 — jen bajtový test je spolehlivý.
  Důkaz: c38e039.
- **Šířku řádku UTF-8 prózy měř ve ZNACÍCH (`.Length` nebo Python `io.open`),
  nikdy `awk 'length'` ani `wc -L`, které počítají bajty.** Proč: Em dash
  nafoukne bajtový počet o dva — řádek ohlášený jako 83 znaků měl ve skutečnosti
  79. Důkaz: 41641a2.
- **Python skript editující soubory téhle vrstvy konce řádků musí DETEKOVAT
  (`newline=''`), ne předpokládat.** Proč: `.ps1` jsou ve stromu CRLF a `.md`
  LF, jednosouborový skript nesmí předpokládat ani jedno. Důkaz: 41641a2.
- **Do `[pscustomobject]@{...}` zahrň VŠECHNA pole hned při konstrukci —
  pozdější `$o.c = 2` potřebuje `Add-Member`.** Proč: Výjimka je NEterminující —
  skript doběhl, JSON se zapsal, pole jen tiše chybělo. Důkaz: 4d72c46.
- **Obsah `.cmd`/`.bat` souborů, včetně komentářů `REM`, drž ve strojové
  ASCII.** Proč: Pomlčka en/em dash v komentáři rozbila parsování řádků níže v
  souboru. Důkaz: 4d72c46.
- **Pod `Set-StrictMode` nevěř, že úspěšný `ConvertFrom-Json` znamená objekt s
  vlastnostmi — ověř typ před `.PSObject.Properties`.** Proč: JSON dovoluje
  kořenové `null`, skalár i pole; `try/catch` se nikdy nespustí a selže až při
  použití. Důkaz: 7da3545.
- **`-like` na neobvyklém vzoru může hodit výjimku nebo v `catch` vracejícím
  bool tiše vrátit špatnou odpověď.** Proč: Neošetřená výjimka shodila funkční
  instalátor; tichá špatná odpověď smazala jedinou pojistku. Důkaz: 7da3545.
- **Volá-li wrapper (`[scriptblock] $Param`) jiný takto parametrizovaný wrapper,
  dej VŠEM funkcím v řetězci RŮZNÁ jména parametru.** Proč: Stejné jméno `$Body`
  napříč dvěma wrappery spadlo na Stack overflow. Důkaz: 0d40535.
- **Má-li POSIX shell v uvozovkách expandovat `$*`/`$@`, piš do PowerShellového
  here-stringu holé `$*` bez zpětného lomítka.** Proč: Zpětné lomítko zapsalo
  escape doslova, který `sh` pak přečetl jako vypnutí expanze. Důkaz: 9a7e158.
- **`$obj.PSObject.Properties.Name` na prázdném `[pscustomobject]@{}` vrací
  `$null` — materializuj přes vnořené `@()`.** Proč: Past se neprojevila u TOML
  větve, jen u JSON s prázdným pscustomobjectem jako fallbackem. Důkaz: 0d40535.
- **`Start-Process -ArgumentList` s polem NEuvozuje prvky s mezerou (na rozdíl
  od `& $exe @array`) — obal je do samostatné dvojice uvozovek.** Proč: Pole se
  spojí do příkazové řádky beze uvozování a prvek s mezerou se rozpadne. Důkaz:
  4d72c46.
- **Porovnání operandů z gitu v PowerShellu piš case-sensitive
  (`-ceq`/`-cne`/`-cmatch`), nikdy defaultním case-insensitive tvarem.** Proč:
  Case-insensitive formulace přijme token ražený pro jinou větev a defekt
  přežije sadu. Důkaz: e0eb939.
- **Než se spolehneš na doslovný `Select-String -Recurse` z briefu, ověř
  parametry v INSTALOVANÉM PowerShellu.** Proč: `-Recurse` u `Select-String` v
  této instalaci vůbec neexistuje — chyba byla chybějící parametr. Důkaz:
  3f811a6.

### Když píšeš POSIX hook nebo shell

- **Windows cesty v `PATH` v msys/Cygwin vždy převeď `cygpath -u` a ověř, že
  náhrada v harnessu skutečně platí.** Proč: `C:/.../shim` se na `:` rozpadne na
  dvě neexistující cesty a shim se nikdy nezavolá. Důkaz: 7da3545.
- **`$(command)` není průhledný kanál pro CR/CRLF testy — hodnotu pod testem
  umísti mimo poslední řádek souboru.** Proč: Jednořádkový CRLF seznam prošel
  testem i bez opravy, protože msys bash strhl trailing CRLF. Důkaz: 7da3545.
- **Manuální spouštění hooků z Git Bash na Windows potřebuje Windows-styl cestu
  (`pwd -W`), ne Unix-styl.** Proč: `node` interpretuje unixovou cestu jako
  drive-relative a chráněná větev prošla jako nechráněná. Důkaz: 7da3545.
- **Per-referenci volání externího procesu nad monorepem drž na konstantní počet
  procesů (jeden `git ls-files` + `xargs`).** Proč: Smyčka nad ~500 projekty
  neběžela do 300 s; streamové zpracování to srazilo na 0,5-2,6 s. Důkaz:
  7da3545.
- **V POSIX shellu chraň neuvozené vzory v `for`-cyklu příkazem `set -f`.**
  Proč: bez něj vzor `branches/*` nahradilo jméno existujícího souboru
  a ochrana chráněné větve tiše zmizela. Důkaz: 7da3545.
- **Před hlavní `while read` smyčkou hooku načti konfiguraci i pomocné
  hodnoty; do smyčky nedávej nic, co čte stdin bez přesměrování.**
  Proč: nepřesměrovaný podpříkaz ve smyčce ukradl stdin, hook přestal
  kontrolovat zbylé refy. Důkaz: 7da3545.
- **CR/CRLF chování POSIX shellu ověřuj empiricky a per platformu,
  nikdy úsudkem ani jedním testem — odstraň CR přímo v pipeline (`tr -d`).**
  Proč: msys `sed`/`grep` CR zahazují, ale neuvozený POSIX shell
  (Linux/macOS/WSL) ne. Důkaz: 7da3545.
- **Bezpříponové bashové skripty (`sdd-workspace`, `task-brief`,
  `review-package`, `ums/.claude/hooks/pre-push`) musí být v pracovním
  stromu s LF.** Proč: git podle přípony nepozná skript a `autocrlf`
  by shebang rozbil. Důkaz: 1a03314.
- **Nevendoruj bezpříponové skripty prostým `git archive` při
  `core.autocrlf=true`.** Proč: konverze na CRLF rozbije shebang a
  skript nejde spustit — `revendor-superpowers.ps1` proto po
  rozbalení normalizuje na LF. Důkaz: 1a03314.
- **Nový bezpříponový shellový soubor commitni až s pravidlem
  `text eol=lf` v `.gitattributes`.** Proč: git podle přípony nepozná
  skript, takže bez pravidla ho `core.autocrlf` na Windows převede.
  Důkaz: 1a03314.

### Když píšeš plán, návrh nebo commit

- **V plánu ani návrhu nikdy nezačínej řádek zpětnými apostrofy,
  pokud to není skutečný ohraničovač bloku** — apostrofy v próze
  popiš slovy; po psaní plánu spusť `task-brief` pro každé číslo úlohy.
  Proč: osamocený takový řádek nechá tracking bloků „uvnitř". Důkaz: c38e039.
- **Českou diakritiku v commit message piš přímo, i přes bash
  heredoc** — UTF-8 tudy projde správně, nenahrazuj ji ASCII
  transliterací. Ověř: `git log -1 --format=%B | od -c`.
  Proč: bez ověření tiše vznikne zpráva mimo konvenci repa. Důkaz: c38e039.
- **Diakritika přes PowerShellový here-string (`git commit -m @'...'@`)
  tiše NEPŘEŽIJE** — napiš zprávu nástrojem `Write` do souboru a
  commituj `git commit -F <soubor>`; po commitu ověř bajtově.
  Proč: `@'...'@` commit tiše nahradil diakritiku ASCII. Důkaz: 0a13ef1.

## Jen pro tento projekt

### Když měníš kontrakt, skill nebo overlay

- **Pravidlo má jeden domov — v kontraktu; skill smí jen odkazovat.** Proč: dva
  konzumenti (mb-abort a jiný skill) zavedli vlastní pořadí pro tutéž operaci,
  jen jeden byl prověřen. Důkaz: 7da3545.
- **Když přebíráš pravidla jiné sekce odkazem, kvalifikuj podstatné jméno a
  napiš NEGATIVNÍ seznam, co necestuje.** Proč: obecný odkaz by naimportoval i
  consume-on-read, které by zničilo právě čtený soubor. Důkaz: 41641a2.
- **`allowed-tools` restringuje nástroje — před návrhem seznamu vypiš všechny
  nástroje, které skill používá.** Proč: briefovaný seznam pro mb-epic-run
  vynechal Edit a git-zápisy, takže centrální operace skillu by neběžela. Důkaz:
  4d72c46.
- **Grep lock nad adresářem s AKTIVNÍM návrhem/plánem počítej i s residuem:
  dokumentem, který cituje starou formulaci.** Proč: grep matchnul vlastní
  design/plan dokumenty tasku citující starou formulaci jako problem statement.
  Důkaz: 0a13ef1.
- **Po opravě hardcoded literálu spusť grep lock PŘED commitem; přeživší zásah
  ve jmenovaném souboru oprav i bez briefu.** Proč: grep lock odhalil druhý,
  briefem nejmenovaný výskyt téhož literálu o sedm řádků dřív. Důkaz: 0a13ef1.
- **Git-fakt (tracked/foreign/published) testuj git příkazem nebo cestou, nikdy
  čtením obsahu souboru.** Proč: netrackovaný neprázdný playbook-candidates
  soubor je pro standardní git příkazy neviditelný. Důkaz: 7da3545.
- **Tvrzení „cesta je netrackovaný deployment" ověřuj `git status
  --ignored=matching` a kódem `!!`.** Proč: `!!` odliší ignorované od „shodou
  okolností beze změny"; ověřeno na `.claude` a `.agents/skills`. Důkaz:
  44ccb57.
- **Po vložení/odstranění kroku grepni CELÝ soubor na `step [0-9]` i plurál a
  odkazuj na kroky jménem, ne číslem.** Proč: vložení kroku posunulo křížové
  reference na číslo kroku beze zmínky, grep na termín je nenašel. Důkaz:
  7da3545.
- **Větu o pořadí kroků NEOPRAVUJ místo přesunu operace do správného kroku.**
  Proč: „aktivace na tiketové větvi" nezměnila, že vytvoření větve zůstalo za
  komitujícím krokem. Důkaz: 7da3545.
- **Po rozšíření STOP/gate testu na širší množinu stavů přečti VŠECHNY pozdější
  kroky téhož skillu na mrtvé větve.** Proč: rozšíření STOPu nechalo v mb-parku
  bod pro starou užší podmínku nedosažitelný. Důkaz: 44ccb57.
- **Když overlay přesune akci dřív, existující bod checklistu musí explicitně
  pozastavit vlastní kontrolu.** Proč: agent u nezměněného bodu znovu vykonal
  STOP instrukci a nahlásil integraci bez harvestu jako hotovou. Důkaz: 7da3545.
- **Overlay úpravu verifikuj proti KONTRAKTU, ne proti briefu; po každé změně
  pravidla grepni celou vrstvu na jeho token.** Proč: fragment psaný jen z
  briefu by povolil přepis TRACKED souboru, který kontrakt zakazuje. Důkaz:
  7da3545.
- **Obecná definiční věta nezneplatní specifickou větu tvrdící VÝHRADNÍ hodnotu
  — grepuj i exkluzivní slovník.** Proč: placeholder token byl krytý obecnou
  větou, ale věta tvrdící „jediná" zůstala v rozporu. Důkaz: 44ccb57.
- **Po zavedení druhé instance něčeho, co věta počítá jako „jedinou", grepuj
  celý dokument na tu počítací frázi.** Proč: slovo „jediná" se stalo
  nepravdivým ve dvou nezávislých větách při vzniku druhé instance výjimky.
  Důkaz: 44ccb57.
- **Nabídka kandidátů s pravidlem spouštěným MIMO seznam musí explicitně napsat,
  že volná odpověď je přípustná.** Proč: nabídka jen z chráněných větví
  nenapsala, že odpověď mimo ni je přijata, STOP byl nedosažitelný. Důkaz:
  44ccb57.
- **Report tvrdící konkrétní stav ho musí PŘEČÍST v tomto běhu, ne dovodit z
  jiného pravidla nebo paměti.** Proč: degradovaná cesta tvrdila chráněné větve
  odvozené z „hook má fallback", ale `main` byl nechráněný. Důkaz: 7da3545.
- **Dvě hlášení o témže stavu musí čerpat z JEDNOHO zdroje pravdy; po změně na
  jednom místě sesynchronizuj obě.** Proč: souhrn a varování o chráněných
  větvích si odporovaly, čtenář varování odešel s mylným dojmem. Důkaz: 7da3545.
- **Přejmenování toho, co fail-closed brána OVĚŘUJE, vyžaduje přepočítat i její
  příkaz, ne ho jen přejmenovat.** Proč: `git branch -r --contains` po
  přejmenování cíle dál procházel starou, už netestovanou věc. Důkaz: 7da3545.
- **Když kontrakt zdůvodňuje manuální krok slabinou automatu, popiš slabinu jako
  MECHANISMUS, ne jako verdikt.** Proč: věta „self-test nic neprokazuje" byla
  měřitelně nepravdivá — instalátor má třetí ověřovací běh. Důkaz: 44ccb57.
- **Než chybějící hodnotu degraduješ na neutrální default, dohledej, kam teče, a
  polaritu testu.** Proč: prázdný default na levé straně `!==` udělal podmínku
  trvale pravdivou, hlídka byla slabší. Důkaz: 41641a2.
- **Než na chybějící závislost vrátíš tvrdou výjimku, dohledej volajícího a zvol
  cestu s VÍC ochrany.** Proč: `throw` na chybějícím loaderu by v degradované
  cestě volajícího nechal repozitář bez hooku. Důkaz: 7da3545.
- **Než opravíš cestu v instrukci, rozliš markdown odkaz (proti adresáři
  souboru) od shell argumentu (proti kořeni repa).** Proč: nahrazení PowerShell
  placeholderu spellingem z markdown odkazu by ukázalo mimo repozitář. Důkaz:
  44ccb57.
- **Hodnotu z konfigurace, která už nese prefix, nikdy neprefixuj podruhé;
  sweepuj obě chybná hláskování zvlášť.** Proč: `HEAD..origin/origin/...`
  skončilo `fatal: ambiguous argument` kvůli zdvojenému prefixu. Důkaz: 7da3545.
- **Rozšíření skillu o novou schopnost vyžaduje ve STEJNÉM commitu upravit i
  `description`.** Proč: `mb-state` dostal novou způsobilost, ale `description`
  dál slibovala jen starý, užší rozsah. Důkaz: 7da3545.
- **Když detektor vybírá jednu hodnotu z rovnocenných kandidátů, přečti DVA
  nezávislé signály, ne jeden.** Proč: `symbolic-ref origin/HEAD` samotný by ve
  forku napsal `origin/main` místo skutečné větve. Důkaz: 7da3545.
- **Bump verze v dokumentu s running „Supersedes" historií musí přeformulovat i
  řádek, který byl current předtím.** Proč: bez přeformulování by vznikly dvě
  neverzované věty bez rozlišení přechodu verzí. Důkaz: 44ccb57.
- **Pro každý volitelný řádek `context.md`, který reset zachovává, ověř zvlášť,
  co ho PŘEPISUJE.** Proč: nový `Báze:` řádek nic nepřepisovalo, jedna
  maintenance větev by tiše určila výchozí bázi všem. Důkaz: 44ccb57.
- **Novou tiketovou větev publikuj explicitním `git push -u origin <branch>`,
  nikdy bare push.** Proč: `switch -c` nastaví upstream na bázi, ne na novou
  větev, takže bare push by cílil na bázi. Důkaz: 44ccb57.
- **V komentáři u rozhodovacího kódu nepiš počet, jedinečnost ani uzavřený výčet
  cest.** Proč: náhrada tvrzení o jedinečnosti jednou výčtovou větou se rozbila
  hned dvěma novými nepravdami. Důkaz: 0d40535.
- **Slovník sweepu po opravě nepravdivé věty skládej ze slov, kterými se POČÍTÁ,
  ne z měněných konceptů.** Proč: slovník omezený na pojmy kola minul dvě věty
  přežívající tři kola. Důkaz: 0d40535.
- **Když review najde věty odporující kódu, udělej greppovaný inventář slovníku
  přes VŠECHNY dotčené soubory.** Proč: oprava jen jmenovaných vět nechala tři
  další nepravdivé věty mimo diff té opravy. Důkaz: 0d40535.
- **Ke greppu na jména pojmů přidej druhý průchod po sekcích věcně dotčených
  změnou a přečti je celé.** Proč: grep na jména pojmů nenašel dvě nepravdivé
  věty formulované jinými slovy než pravidlo samo. Důkaz: 0d40535.
- **Tvrdí-li dokumentace, že vlastnost platí pro KAŽDOU položku seznamu, projdi
  seznam sondou.** Proč: šestý nosič v seznamu byl omylem jiné třídy, věta o
  všech šesti by odešla nepravdivá. Důkaz: 0d40535.
- **Upřesnění komentářového bloku nepřidávej jako nový odstavec — přepiš přímo
  VĚTU, kterou mění.** Proč: nová věta skončila pod tou, kterou vyvracela, a obě
  zůstaly vedle sebe. Důkaz: 0d40535.
- **Po úpravě komentářového bloku přečti ho CELÝ odshora dolů a sluč dvojice
  věta–výjimka do jedné.** Proč: absolutní věta stála nad přesnou výjimkou o 17
  řádků níž, cizí čtenář narazí na nepravdivou první. Důkaz: 0d40535.
- **Nadpis komentáře musí být týž tvar pravidla jako věta pod ním, ne jeho
  silnější zkratka.** Proč: nadpis byl silnější než skutečné pravidlo a
  porušoval ho vlastní správný kód pod ním. Důkaz: 0d40535.
- **Popisuje-li soubor mechanismus na víc místech, po úpravě jednoho srovnej ho
  se všemi ostatními.** Proč: druhá formulace výjimky měla opravu už z
  předchozího kola, stromový komentář ne. Důkaz: 0d40535.
- **U absolutní věty o hooku přečti kód NAD branou, na kterou se odvolává, a
  výjimku napiš do stejného odstavce.** Proč: „hook nevynucuje nic mimo agent
  session" nebrala v úvahu větev nad branou (buffer stdinu). Důkaz: 0d40535.
- **Při rozšíření působnosti pravidla vypiš mechanismy, které o něm NĚCO
  SLIBUJÍ, a ověř slib i pro nové případy.** Proč: rozšíření výjimky ze dvou na
  tři zdi nechalo větu o rejection message nepravdivou pro dvě z nich. Důkaz:
  0d40535.
- **U rozhodovacího ramene popisovaného prózou si opiš konkrétní řádek a
  spočítej podmínky, teprve pak piš větu.** Proč: popis „posture + jedna
  výjimka" svedl k under-claimu — rameno má dvě podmínky. Důkaz: 0d40535.
- **Popis chování rozhodovací funkce piš až po přečtení CELÉ funkce, nikdy jen z
  hlavičky nebo rulingů.** Proč: věty sepsané z hlavičky a rulingů byly obě
  nepravdivé proti kódu ve dvou případech. Důkaz: 0d40535.
- **Před vložením snippetu nahrazujícího strukturovaný útvar přepiš v něm odkazy
  na strukturu na jméno pravidla.** Proč: snippet vložený doslova odkazoval na
  tabulku, kterou týž krok o kus dál mazal. Důkaz: 0d40535.
- **Ohrazený příklad, proti kterému někdo napíše parser, přečti znovu proti
  pravidlům na třídy znaků téže sekce.** Proč: kanonický příklad nesl
  placeholder v ostrých závorkách, který stejná sekce jinde zakazuje. Důkaz:
  41641a2.
- **Sdílí-li pravidlo a ohrazený artefakt „stejný odstavec", dej pravidlo těsně
  NAD ohrazení bez prázdného řádku.** Proč: v Markdownu ohrazení odstavec
  ukončí, obojí nemůže doslova sdílet jeden odstavec. Důkaz: 41641a2.
- **Po definici uzavřeného výčtu s povinnými poli projdi KAŽDÝ člen a vypiš mu
  celý záznam doslova.** Proč: člen, kvůli kterému artefakt vznikl, byl zároveň
  jediný nezapsatelný — dělal ho neviditelným. Důkaz: 41641a2.
- **Duplicitu ohraničeného regionu čti jako signál malformed → nepřítomný, ne
  jako přednost páru.** Proč: „poslední pár vyhrává" by tiše povýšilo
  nedůvěryhodného kandidáta a schovalo vadu pisatele. Důkaz: 41641a2.
- **Ruší-li úloha pojmenovaný koncept, grepuj i frázi, kterou byl pojmenovaný v
  próze, ne jen token proměnné.** Proč: širší slovníkový sweep našel dva další
  výskyty mimo brief scope, které by grep na proměnnou minul. Důkaz: 0d40535.
- **Popisuje-li komentář bezpečnostní vlastnost jako „X je pravda", ověř,
  dokazuje-li to kód PŘÍMO, nebo přes proxy.** Proč: komentář sliboval kontakt s
  remote, ale kód kontroloval jen lokální, zapisovatelný ref. Důkaz: 0d40535.
- **Konfigurační klíč/soubor pro cizí nástroj ověř proti primární dokumentaci
  PŘED implementací.** Proč: brief cílil na `[env]`/`"env"` klíč, který ani
  Codex, ani Gemini CLI takto nečtou. Důkaz: 0d40535.
- **Než přijmeš navrženou podmínku jako kompletní, projdi VŠECHNY případy proti
  ní jako červené testy.** Proč: „fail-closed jen na command position" jednou
  podmínkou nestačilo — chybělo rameno o expanzi. Důkaz: 0d40535.
- **Ke KAŽDÉMU rozšíření vzoru z povolovacího na zamítací dopiš negativní
  asercie na hodnotu, konec i prefix.** Proč: pozitivní asercie na sedm zápisů
  by prošly i výrazu matchujícímu skoro cokoli. Důkaz: 0d40535.
- **Před KAŽDÝM splicem vytáhni čísla řádků znovu (`grep -n`), nikdy z
  dřívějšího výpisu, a přečti výsledek.** Proč: splice s čísly z dřívějšího
  výpisu byl posunutý — syntax check nad komentářem to neodhalí. Důkaz: 0d40535.
- **Bump verze kontraktu je vlastní sweep na starou verzi, mimo sweep na slovník
  měněného pravidla.** Proč: oba slovníkové sweepy minuly samotnou verzi — sedm
  restatementů `2.11` a chybějící `brief.md`. Důkaz: e0eb939.
- **Sweep na restatementy pouštěj přes `ums/` i `memory-bank/` jedním příkazem,
  grepuj nejkratší fragment.** Proč: druhý restatement ležel v
  `architecture.md`, dvouslovný token ho ve flektivním jazyce minul. Důkaz:
  41641a2.
- **Inventáře sweepuj podle DRUHU artefaktu (kdo počítá věci tohoto druhu), ne
  podle jména nového konceptu.** Proč: čtyři inventární věty zůstaly nepravdivé
  — žádná neobsahovala jméno nového konceptu. Důkaz: e0eb939.
- **Grep tool bez `output_mode: "content"` zahodí `-n` — předej ho explicitně,
  chceš-li čísla řádků.** Proč: vynechání tiše spadne na výpis souborů se shodou
  bez čísel řádků. Důkaz: e0eb939.
- **Vložení odstavce/nadpisu do prózy cíli na konec ÚTVARU ověřený čtením
  dopředu, ne na řádek, co jen vypadá jako konec.** Proč: řádek vypadající jako
  konec odstavce byl uprostřed zalomené věty — vložení by ji rozdělilo. Důkaz:
  41641a2.
- **H1 nadpis reference v `contract/`, duplikující vlastní `###`/`##` nadpis,
  NEMAZAT — shape-suita indexuje jen `^#{2,4}`.** Proč: smazání H1 duplikátu by
  proměnilo zelenou citaci v červenou; opraveno povýšením `###`→`##`. Důkaz:
  3f811a6.
- **Dokumentuj syntax citace ŽIVOU instancí, nikdy metasyntaktickým
  placeholderem typu `"<section>"`.** Proč: placeholder prochází stejným
  scannerem jako reálná citace a vyrobil 24. rozbitou citaci. Důkaz: 3f811a6.
- **Hlavička nové `contract/<jméno>.md` reference v „cite as" příkladu musí
  jmenovat REÁLNÝ nadpis, ne placeholder.** Proč: doslovný placeholder „Section"
  spadl na „každá citace má cíl", sekce toho jména neexistuje. Důkaz: 3f811a6.
- **Citaci `(contract[/soubor.md], "Sekce")` piš celou na JEDNÉ fyzické řádce,
  nikdy ji nenech rozlomit zalomením.** Proč: čtyři různé tvary zalomení
  proměnily existující, správně cílenou citaci na „citace nemá cíl". Důkaz:
  3f811a6.
- **Briefova tabulka „skill → přiřazená reference" řídí jen hlavičkovou řádku,
  inline citace smí mířit jinam.** Proč: `mb-jira-update` cituje referenci mimo
  svou přiřazenou sadu, přesto je citace platná. Důkaz: 3f811a6.
- **Mechanický split Markdown dokumentu podle nadpisového regexu musí nejdřív
  vyloučit nadpisy uvnitř ohraničení.** Proč: 5 ze 44 matchujících řádků v
  kontraktu bylo uvnitř ohraničení — naivní split by je rozřezal. Důkaz:
  3f811a6.
- **`[IO.File]::ReadAllText -split "n"` na LF-terminated souboru vrátí o jeden
  element víc, než je řádků.** Proč: kontrakt má 3066 řádků, split dal pole o
  3067 prvcích — odhalil to partition self-check. Důkaz: 3f811a6.
- **Ověřování „přežilo pravidlo kompresi?" dělej `[regex]::IsMatch` s mezerou
  jako `\s+`, nikdy `String.Contains`.** Proč: substring test nahlásil 4 fráze
  jako chybějící, ačkoli byly jen rozdělené řádkovým zalomením. Důkaz: 3f811a6.
- **Kompresi normativního textu ověřuj proti PRE-WAVE COMMITU (token diff), ne
  proti zůstávající zelené sadě.** Proč: komprese 20 sekcí nechala sadu zelenou
  po celou dobu, přestože reálně ztratila dvě ilustrace. Důkaz: 3f811a6.
- **Je-li task gatovaný nástrojem na „zachovej každý řádek", zkontroluj move
  mapu proti jeho allow-pattern PŘED editem.** Proč: default allow-pattern
  nezachytí `## ` povýšení nadpisu, které briefova move mapa žádala. Důkaz:
  3f811a6.
- **Novou `###` podsekci do kontraktové reference vkládej na PŘIROZENOU hranici,
  nikdy doprostřed jedné myšlenky.** Proč: vložení mezi dvě navazující věty
  rozdělilo jednu myšlenkovou linku a matlo návaznost. Důkaz: 3f811a6.
- **Acceptance check jmenující GLOBÁLNÍ invariant grepuj přes CELOU vrstvu, ne
  jen briefův seznam Files.** Proč: `mb-epic-elaboration/SKILL.md` mimo seznam
  dál popisoval zrušené chování jako živé. Důkaz: 3f811a6.
- **Vzdálené větve vypisuj `--format='%(refname:lstrip=3)'`, ne
  `%(refname:short)`, a filtruj `grep -v '^HEAD$'`.** Proč: `%(refname:short)`
  nechal remote prefix a bare `origin` pro symref jako fantomovou položku.
  Důkaz: 7da3545.
- **`git ls-tree` nepodporuje pathspec magic `:(glob)` — na cesty v libovolné
  hloubce použij sondu `cat-file -e`.** Proč: `:(glob)` skončí `fatal: pathspec
  magic not supported`, zatímco `git log` se stejným pathspecem funguje. Důkaz:
  9a7e158.
- **Skill snippet, který dot-sourcuje jeden skript a volá funkce z jiného,
  projdi řádek po řádku — každá volaná funkce dot-sourcovaná explicitně.** Proč:
  `mb-state` funguje jen transitivním tahem, který se rozbije na první
  reorganizaci pořadí. Důkaz: 44ccb57.
- **Rozšíříš-li guard o další nástroj, pro KAŽDOU textovou kontrolu napiš vstup
  v novém nástroji a přidej asercii dřív, než první novou.** Proč: Matcher
  `Bash|PowerShell` nechal review přehlédnout, že vzor pro `NAME=` nematchne
  `$env:` přiřazení. Důkaz: 0d40535.
- **U rozšíření vzoru `JMÉNO<oddělovač>HODNOTA` piš negativa na třech osách
  zvlášť — HODNOTA, TERMINÁTOR, PREFIX/SUFFIX.** Proč: Bez lookaheadu za
  hodnotou by regex nechal `10` matchnout jako `1`. Důkaz: 0d40535.
- **Před psaním negativní tabulky zjisti, jde-li o novou TŘÍDU konstruktu, nebo
  člena existující — člen dědí pravidlo třídy.** Proč: Sourozenecké konstrukty s
  hodnotou nula už zamítaly stejným způsobem. Důkaz: 0d40535.
- **Než usoudíš, které tokeny se dostanou ke spouštěnému programu, spusť skript
  tisknoucí svoje `argv` — ne úsudkem.** Proč: Dvě podobná přesměrování se
  lišila jedním znakem a jen jedno skutečně provedlo push. Důkaz: 0d40535.
- **Rozpoznává-li tokenizer nově shellový konstrukt, zjisti, co s ním dělá
  SKUTEČNÝ shell — odstranění je skip-a-pokračuj, NIKDY break.** Proč: Break je
  vždy permisivnější; doslovné ukončení by pustilo únik přes chráněnou větev.
  Důkaz: 0d40535.
- **Signaturu sdíleného helperu přečti, nehádej — fail-closed verdikt proti
  defaultu ber jako signál špatného volání.** Proč: Volání se špatným jménem
  parametru propustilo přepínač do `$args` a vyrobilo falešný STOP. Důkaz:
  e0eb939.
- **Uzavřený re-render musí sanitizovat HODNOTY, ne jen jména polí — odmítej
  třídu znaků, ne výčet hláskování.** Proč: Whitelistovaný klíč s nebezpečnou
  hodnotou prošel a byl re-renderován doslovně. Důkaz: e0eb939.

### Když stavíš nebo spouštíš testy

**Spuštění testovací sady**
- Jedna sada přímo: `pwsh -NoProfile -File <cesta>.tests.ps1`.
- Celá vrstva smyčkou:
```bash
for t in $(find ums -name "*.tests.ps1"); do echo "== $t"; pwsh -NoProfile -File "$t" || echo "FAILED: $t"; done
```
- Zelená sada končí `<N> passed` a exit kódem 0.
- Červená vypíše `<N>/<M> FAILED` a vrátí exit kód 1.
Důkaz: 1a03314

### Když píšeš nebo měníš test

- **Sadu piš jako obyčejný `.ps1` s vlastními aserčními funkcemi, nikdy jako
  Pester.** Proč: vrstva je bezzávislostní, test nesmí předpokládat
  nainstalovaný PowerShell modul. Důkaz: 1a03314
- **Každý adresář testů má vlastní kopii `_assert.ps1`** (dot-sourced,
  poskytuje `Assert-True/Match/NotMatch/Eq` a `Complete-Tests`); kopie se
  smí lišit. Proč: nasazení kopíruje adresáře skillů jednotlivě, helper mimo
  adresář skillu by s ním nedoputoval. Důkaz: 1a03314
- **Guardovaný index u `[bool]`-typovaného parametru aserčního helperu ukonči
  SROVNÁNÍM** (`(...) -eq $true`), ne jen `Select-Object -First 1`. Proč:
  prázdná pipeline se pod mutací sváže jako `""` a hodí typovou chybu.
  Důkaz: 3f811a6
- **Totéž platí na volací straně: je-li argument `[bool]` parametru
  `(pipeline).vlastnost`, koncové srovnání musí být UVNITŘ téže vnější
  závorky.** Proč: bez závorky PowerShell čte srovnání jako další poziční
  argumenty volání. Důkaz: 44ccb57
- **Před přidáním souboru do zrcadleného adresáře (`Copy-Mirrored`) ověř,
  jestli sync cíl maže a nahrazuje; fixtura ať má reálný soubor, ne stub.**
  Proč: stub nahrazený syncem shodil nesouvisející test o dvě asercie dál.
  Důkaz: 7da3545
- **Fixtura razící kopii verzované značky ať čte hodnotu ze zdroje pravdy
  sdíleným helperem** (`Get-UmsHookVersion`), ne literálem. Proč: literál
  zestárne stejně jako opravovaný gate při dalším bumpu verze. Důkaz:
  0a13ef1
- **Fixtura s linked worktrees pro GENUINE čistý strom potřebuje v základním
  commitu `.gitignore` pro `.superpowers/`, `.gitattributes` s `eol=lf`
  a zápis obsahu přes `Set-Content -NoNewline`.** Proč: bez toho vypadá
  strom špinavý nebo se přepis liší bajtově kvůli CRLF. Důkaz: 4d72c46
- **Kanárek exec bitu odsunutého cizího hooku ověřuj jen tím, že PO instalaci
  existuje/byl zavolán**, ne tím, že se neaktivoval dřív než tvůj test krok.
  Proč: instalátorův self-test proof legitimně spustí hook dřív. Důkaz:
  0d40535
- **Fallback na přímou kontrolu `test -x` drž jen pro případ, kdy nová
  push-schopná fixtura není proveditelná** — canary bez chmod je silnější
  důkaz a patří první. Proč: canary testuje end-to-end chování, ne jen bit
  na disku. Důkaz: 0d40535
- **U přejmenování s přechodnou kompatibilitou nestačí RED proti nezměněnému
  kódu — přidej pro každou dvojici jmen asercii na plnou hlášku a ověř
  cílenou mutací.** Proč: obě jména mohla projít starou zamítací větví beze
  změny chování. Důkaz: 0d40535
- **Negativity-check guardu proti selhání přesměrování na msys `sh` piš na
  rozlišitelný pozorovatelný projev, ne na zčervenání „operace prošla“.**
  Proč: neinteraktivní shell na chybějícím souboru skončí fatálně dřív, než
  se dostane k testovanému kódu. Důkaz: 0d40535
- **Sráží-li se tolerantní věta kontraktu s jeho pravidlem o uzavřeném
  formátu, napiš fixturu pro OBĚ čtení** (tolerantní i uzavřené) na stejném
  hraničním místě. Proč: kterékoli čtení samo dá sadu souhlasící jen s
  polovinou sekce. Důkaz: 41641a2
- **Skutečná volání gitu počítej `git.bat` shimem dřív v `PATH`, ne mockem**
  — funguje i pro volání z potomka; ověř, že se shim použil a že výstup
  sedí bajtově s během bez něj. Proč: mock nezachytí volání z potomka a
  neověřený shim může zkreslovat. Důkaz: 9a7e158
- **Fixturu „guard tenhle tvar nerozpozná" postav na UVOZENÉM `git`
  tokenu, ne na neuvozeném za jiným příkazem, a výstup ověř ručně.**
  Proč: `echo git push --mirror` guard zamítl (neuvozený token), ale
  `bash -c 'git push --mirror'` prošel. Důkaz: 0d40535.
- **Sada, jejíž reálné asercie závisí na značce, kterou sama zavádí,
  musí tu značku nastavit explicitně na úrovni CELÉ sady.**
  Proč: `$env:MB_AGENT_SESSION` na úrovni souboru neposunulo počet
  passed — sada tajně závisela na harnessu. Důkaz: 0d40535.
- **Testovací Memory Bank dokumenty ukládej pod `tests/fixtures/`.** Proč:
  indexace MB dokumentů tuto cestu vylučuje, fixtury nespadnou do indexu.
  Důkaz: 44ccb57.

### Když spouštíš sadu nebo důkazní běh

- **Text citující `--no-verify`, `MB_HUMAN_PUSH=1` nebo `git push` piš do
  souboru a spouštěj jako skript, ne jako literál v parametru Bash/PowerShell
  toolu; totéž nad ~100 řádky payloadu.** Proč: hlídka nástroje čte jen
  literální text parametru, ne obsah spouštěného souboru. Důkaz: 44ccb57
- **Krok ověřující řetězení proti reálnému LFS hooku prováděj v
  throwaway klonu s nakonfigurovaným (byť fiktivním) remote `origin`.**
  Proč: self-test proof bez `origin` spadl na „Invalid remote name" —
  `run_chained` volá skutečný git-lfs. Důkaz: 0d40535.
- **Před nabídkou kandidátů báze ověř `git log <kandidát>..<větev>`**
  **a dokaž přijetí hookem poctivou čtveřicí refů před předáním příkazu.**
  Proč: báze 34 commitů pozadu byla jednou zvolena mlčky, protože nic
  ve vstupní bráně na integraci nekouká. Důkaz: e0eb939.

### Když nasazuješ nebo revendoruješ

- **Revendor spouštěj v monorepu, ne v tomto forku.**
  Proč: vendorované kopie s overlay bloky vznikají až v cíli nasazení,
  ne ve forku samotném. Důkaz: 1a03314.
**Postup revendoru upstreamu (dvoucommitový)**
1. V tomto forku slouč nový upstream: `git fetch vanila --tags`, pak
   `git merge vanila/main` (na `main`, odtud do `ums-memory-bank`).
2. V monorepu: `pwsh .claude/scripts/revendor-superpowers.ps1 -Tag <tag>
   -NoOverlays` → commit „vanilla sync".
3. `pwsh .claude/scripts/revendor-superpowers.ps1 -OverlaysOnly` → commit
   „overlay".
Proč: první commit nese jen upstream diff, druhý jen zásah UMS.
Důkaz: 1a03314.
- **Revendorové commity nikdy neslučuj do jednoho.**
  Proč: sloučený commit nejde rozlišit na to, co přinesl upstream
  a co je zásah vrstvy. Důkaz: 1a03314.
- **Vendorované soubory nikdy needituj ručně mimo bloky
  `<!-- UMS-OVERLAY BEGIN/END -->` — změnu piš do fragmentu
  `shared/overlays/*.overlay.md`.** Proč: revendor rozbalí upstream
  znovu a ruční úprava mimo bloky se tiše ztratí. Důkaz: 1a03314.
- **Miss kotvy `ANCHOR-BEFORE` oprav ve fragmentu a spusť revendor
  znovu — nikdy ji neuvolňuj, aby „prošla".** Proč: je to detektor
  driftu upstreamu, kotva musí matchovat přesně jeden řádek.
  Důkaz: 1a03314.
- **Revendor spouštěj z PowerShellu, ne z Git Bash shellu.**
  Proč: Git Bash zdědí msys `tar` z PATH, který windowsovou cestu čte
  jako vzdálený host a spadne na „Cannot connect to C: resolve failed".
  Důkaz: ae2230c.
- **Spouštění `sync-with-monorepo.ps1` bez parametrů je bezpečné
  interaktivně i neinteraktivně** — v konzoli doptá defaulty, jinak
  je použije potichu. Proč: běh musí fungovat i bez terminálu (CI,
  agent). Důkaz: 1a03314.
**Parametry `sync-with-monorepo.ps1`**
| Parametr | Hodnoty | Default |
|---|---|---|
| `-Agent` | `claude`, `codex`, `gemini`, `kilocode` | `claude` |
| `-Scope` | `Monorepo`, `UserProfile` | `Monorepo` |
| `-Direction` | `FromMonorepo`, `ToMonorepo` | `FromMonorepo` |
| `-MonorepoRoot` | cesta ke klonu monorepa | `D:\_datasys\ums` |
Důkaz: 1a03314.
- **Traktuj `claude`+`Monorepo` jako jedinou obousměrnou kombinaci
  syncu.** Proč: jen ona táhne oběma směry (`FromMonorepo` z
  monorepa, `ToMonorepo` opačně) — jinak jde vždy jednosměrný
  deploy z `ums/`. Důkaz: 1a03314.
**Pořadí `FromMonorepo` → `ToMonorepo` je pevné**
Před `-Direction ToMonorepo` vždy nejdřív spusť `-Direction FromMonorepo`
a slouč do forku vše, kde je monorepo napřed — až pak `ToMonorepo`.
Default skriptu (`FromMonorepo`) tenhle krok neudělá automaticky.
Proč: přímé `ToMonorepo` by přepsalo 89 řádků, kde byl monorepo napřed
— `ToMonorepo` zrcadlí každý `mb-*` skill bez ohledu na to, který
strom je novější.
Důkaz: 0a13ef1.
**Kde hledat drift forku a monorepa**
- Porovnávej jen UMS-vlastněné položky (`skills/mb-*`, `skills/shared`,
  `hooks/*`) po jednotlivých adresářích, přesně jak je enumeruje
  `sync-with-monorepo.ps1` — nikdy plošný diff celého `skills` stromu.
- `hooks/tests/` sync nesynchronizuje nikdy, rozdíl tam je očekávaný.
- `gemini` a `kilocode` nemají adresář skillů — dostanou jen glue
  a blok preferencí v instrukčním souboru.
Proč: plošný diff dal 190 souborů / 203 242 řádků šumu z cizích
(nevlastněných) skillů, které fork mirror vůbec nemá.
Důkaz: 0a13ef1.
**Co `sync-with-monorepo.ps1` nasazuje a jak**
- `settings.json` se na ne-Claude cíle nenasazuje — je to registrační
  soubor Claude Code, přepsal by cizí konfiguraci; u ostatních
  harnessů se hooky registrují ručně.
- Glue soubory se do cílového adresáře mergují po souborech, cizí
  obsah nikdy nemažou. Blok preferencí jde mezi markery
  `UMS-MEMORY-BANK BEGIN/END`, opakovaný běh ho nahradí na místě.
- Vendorované superpowers skilly tento skript nesynchronizuje nikdy —
  vznikají jen revendorem.
Důkaz: 1a03314.
- **`cp -r zdroj cíl/` do existujícího adresáře SLUČUJE, nevnořuje**
  — ověř to na dvouřádkové fixture ve scratchpadu, ne odvozením
  z četby příkazu. Proč: ověřeno měřením — cizí soubor v cíli
  přežil, nové soubory přibyly. Důkaz: 7da3545.
- **Než nasazení postavíš na merge-copy (`cp -r` bez `--delete`),
  ověř `git diff --name-status <base>..HEAD` na řádky D/R.** Bez
  mazání/přejmenování je merge-copy dostatečná, s nimi ne.
  Proč: bez D/R merge-copy nemůže nechat mrtvý soubor. Důkaz: 7da3545.
**Instalace git hooků do klonu**
```bash
pwsh -NoProfile -File ums/.claude/hooks/install-git-hooks.ps1 -RepoRoot <klon>
```
Proč: git hooky jsou netrackované, takže se s klonem nepřenesou.
Důkaz: 1a03314.
- **V novém klonu bez instalace hooků `pre-push` záruka chybí.**
  Proč: git hooky jsou netrackované a s klonem se nepřenesou — záruka
  publikačního kontraktu je aktivní, jen když ji někdo nainstaluje.
  Důkaz: 1a03314.
- **Při `-Scope UserProfile` spusť instalátor hooků ručně** — při
  `-Scope Monorepo` ho volá `sync-with-monorepo.ps1` sám.
  Proč: profil nemá jeden přiřazený repozitář, díky kterému by
  ho šlo zavolat automaticky. Důkaz: 1a03314.
- **Nenulový exit instalátoru hooků neignoruj** — `1` = self-test
  selhal, `2` = ponechán cizí hook, `3` = nainstalováno, ale neověřeno.
  Proč: sync ho jen vypíše jako varování a v dlouhém výpisu zapadne,
  takže nepotvrzená záruka snadno unikne pozornosti. Důkaz: 1a03314.
- **Po každé změně zdroje v `ums/.claude/` obnov nasazenou kopii
  (`.claude/`, `.agents/skills/`)** — obojí je netrackované, sezení
  v tomto repu čte právě je. Proč: jinak agent pracuje podle staré
  verze kontraktu i skillů. Důkaz: 1a03314.
**Co je nasazená kopie**
- UMS obsah (`shared/`, `mb-*`, `hooks/`, `scripts/`, `settings.json`)
  je prostá kopie z `ums/.claude/` do kořenového `.claude/`; pro Codex
  ještě `ums/.claude/skills/` do `.agents/skills/`.
- Kontrola aktuálnosti: `Contract-Version` v
  `.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md` musí souhlasit
  se zdrojem a všechny `mb-*` adresáře ze zdroje musí být přítomny.
Proč: chybějící skill je nejrychlejší příznak zastaralého nasazení.
Důkaz: 1a03314.
**Kontrola nasazení odhalí jen chybějící, ne zastaralé**
`Contract-Version` + přítomnost všech `mb-*` adresářů odhalí jen
CHYBĚJÍCÍ nasazení. Na staleness (obsah se změnil, ne jen existence)
použij `diff -rq ums/.claude .claude` — čtyři vendorované skilly s
overlay bloky srovnávej proti MONOREPO kopii, ne proti `ums/`, kde
vůbec neleží (nevyrobí se kopií, jen revendorem — `brainstorming`,
`subagent-driven-development`, `finishing-a-development-branch`,
`writing-plans`).
Proč: deployovaná kopie nesla 16řádkový overlay o lokálním merge,
zatímco zdrojový fragment měl 109 řádků o FF-push integraci — obě
kontroly to prošly beze zmínky.
Důkaz: 44ccb57.
- **Po každém revendoru dorovnej vendorované skilly i v
  `.agents/skills` kopií z `.claude/skills`** (fork i monorepo).
  Proč: revendor cílí jen na `.claude/skills`, sync tam
  nesynchronizuje nikdy. Ověř `diff -rq`. Důkaz: f69c145.
- **Po editaci overlay fragmentu v `ums/` nejdřív obnov nasazení
  (kopie do `.claude/`), teprve pak spusť revendor** — revendor čte
  fragmenty z NASAZENÉ kopie. Ověř grepem na text nové verze.
  Proč: bez pořadí tiše aplikuje starou verzi. Důkaz: e3dfc90.
- **Grepovou verifikaci vygenerovaného overlay textu ověřuj i
  case-insensitive (`grep -ni`)** dřív, než nulový zásah nahlásíš
  jako anchor-miss STOP. Proč: grep malými písmeny minul frázi
  s velkým počátečním písmenem. Důkaz: 0d40535.
**Grepová verifikace overlay textu potřebuje ztištěný whitespace**
Ověř variantu se ZTIŠTĚNÝM veškerým whitespace, ne jen s nahrazenými
novými řádky: `tr -s '[:space:]' ' ' < soubor | grep -o '<fráze>' |
wc -l`. Prosté `tr '\n' ' '` nestačí — odsazení pokračovacího řádku
(typicky dvě mezery) v textu zůstane a vzor čeká jednu mezeru, ne tři.
Proč: Markdown tvrdě zalomil frázi mezi dvěma slovy s odsazením
přesně uprostřed — druhá, nezávislá třída falešné příčiny vedle
casingu.
Důkaz: 0d40535.
- **Regenerace nasazených vendorovaných skillů po změně fragmentu
  bez upstream bumpu = plný revendor s pinovaným tagem (`-Tag <pin>`),
  ne `-OverlaysOnly`.** Proč: `-OverlaysOnly` funguje jen na
  pristine soubory. Důkaz: 4d72c46.
**Editaci jen TĚLA overlay fragmentu ověřuj diffem, ne revendorem**
Zkontroluj: `git diff <báze>..HEAD -- <adresář overlayů> | grep -E
"^[+-].*(ANCHOR|ASSERT|UMS-OVERLAY)"` je prázdný a každý overlay má
právě jeden pár `UMS-OVERLAY BEGIN/END`. Revendor je samostatný krok
nasazení; do jeho proběhnutí drž nasazené vendorované skilly jako
zastaralé. `sync-with-monorepo.ps1` na tohle není — cílí na monorepo
nebo profil, ne na kořen tohoto forku.
Proč: pokus ověřit anchoring přes redeploy neuspěl (tar/PATH pasti),
selhání nástroje není nález o samotné editaci.
Důkaz: ae2230c.
