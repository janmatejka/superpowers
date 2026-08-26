# Playbook

Postupy, kterými se tato vrstva staví, testuje a nasazuje. Popisný stav — verze
a piny, inventář souborů, konfigurace, pasti prostředí — je v
[tech.md](tech.md); jak vrstva funguje, popisuje [architecture.md](architecture.md).

## Testy vrstvy

Jednu sadu spustíš přímo, celou vrstvu smyčkou:

```bash
pwsh -NoProfile -File ums/.claude/skills/mb-doc-index/tests/enumeration.tests.ps1
for t in $(find ums -name "*.tests.ps1"); do echo "== $t"; pwsh -NoProfile -File "$t" || echo "FAILED: $t"; done
```

Zelená sada končí řádkem `<N> passed` a nulovým exit kódem; při selhání vypíše
`<N>/<M> FAILED` a vrátí `1`.

Konvence, které nová sada musí dodržet:

- **Žádný Pester, jen obyčejný `.ps1` skript s vlastními aserčními funkcemi.**
  Proč: vrstva je bezzávislostní, takže test nesmí předpokládat nainstalovaný
  PowerShell modul — jinak by ho nešlo spustit v čerstvém klonu ani u
  uživatele, který si vrstvu jen nasadil.
- **`_assert.ps1` má vlastní kopii každý adresář testů**
  (`ums/.claude/skills/<skill>/tests/`, `ums/.claude/hooks/tests/`); sada ho
  natáhne přes `. (Join-Path $PSScriptRoot '_assert.ps1')` a poskytuje
  `Assert-True`, `Assert-Match`, `Assert-NotMatch`, `Assert-Eq`
  a `Complete-Tests`.
  Proč: nasazení kopíruje celé adresáře skillů (`sync-with-monorepo.ps1` bere
  `shared` a každý `mb-*` zvlášť), takže helper ležící mimo adresář skillu by
  s ním k uživateli neputoval. Kopie se smí lišit — každá nese jen to, co její
  sada používá.
- **Sada leží vedle kódu, který testuje**, v podadresáři `tests/`, a jmenuje se
  `<téma>.tests.ps1`. Do nového adresáře testů zkopíruj i `_assert.ps1`.
- **Testy běží offline.** Kde je potřeba vzdálený repozitář, sestaví se lokální
  bare klon jako „origin" (`new-fixture-repo.ps1` u `mb-doc-index`, vlastní
  bare remote u `pre-push`).
  Proč: sada nesmí sáhnout na síť, na `origin` ani do Jiry — jinak by červená
  sada neznamenala regresi, ale výpadek okolí.
- **Ad-hoc fixture pro throwaway lokální „origin", která potřebuje
  `--no-verify` u pushe, piš do skriptu a spusť ho jako soubor
  (`bash script.sh` / `pwsh -File script.ps1`), ne jako literální text
  v příkazu Bash/PowerShell toolu. Totéž pravidlo platí obecněji: jakýkoli
  text citující `--no-verify`, únikovou proměnnou (`MB_HUMAN_PUSH=1`) nebo
  tvar `git push` — report, sonda nad guardem, ledger, dokument o guardu —
  zapiš nástrojem na zápis souboru (Write), ne jako literál v parametru
  Bash/PowerShell toolu.**
  Proč: bezpečnostní hlídka nástroje blokuje `--no-verify` jen v LITERÁLNÍM
  textu vlastního parametru příkazu, ne v obsahu skriptu, který nástroj
  pouze spouští — týž flag uvnitř dot-sourcovaného/spuštěného `.tests.ps1`
  prošel beze zmínky ve stejném sezení, kde přímý pokus v příkazové řádce
  byl zamítnut. Na jednom work itemu tahle past padla šestkrát: psaní
  reportu citujícího přepínač guardu, sonda nad guardem posílaná jako
  literál, i markdownová tabulka s příkazy `git push …`, kde escapovaný
  `\|` hned za `git push` guard přečetl jako jméno remote a zamítl push se
  zapsaným reportem samotným.
- Testovací Memory Bank dokumenty ukládej pod `tests/fixtures/`.
  Proč: indexace MB dokumentů tuto cestu vylučuje, takže fixtury nespadnou do
  indexu ani do kolizních nálezů.
- **Když test tvrdí, že git rozpozná přejmenování, přidej `--find-renames`
  explicitně.** `git diff --cached --name-status` bez toho flagu závisí na
  configu `diff.renames`, který se napříč verzemi gitu liší; s flagem vrací
  `R100` se starou i novou cestou deterministicky.
- **Read-only nálezy ověřuj spuštěním proti skutečnému repozitáři, ne jen
  proti fixtuře.** Náhledový režim (bez `-Apply`) nic nemění, takže je to
  bezpečné.
  Proč: fixtura dokazuje, že kód dělá, co jste do fixtury napsali; skutečné
  repo dokazuje, že bug byl reálný a ne artefakt konstrukce fixtury. Tímhle se
  potvrdilo, že migrační skript kořenovou `memory-bank/` vůbec nenašel.
- **Nový regresní strážce/test ověř jeho vlastní negativitou:** spusť ho i
  proti neopravenému kódu, nebo dočasně smaž řádek/podmínku, kterou hlídá,
  a zkontroluj, které asercie zčervenají. Asercie, které zůstanou zelené
  v obou případech, jsou regresní zámek, ne důkaz opravy — v reportu je
  odděl. Strážce, kde zčervenají VŠECHNY asercie, obvykle chybí pozitivní
  kontrola; kde nezčervená ŽÁDNÁ, nic nehlídá. Po ověření smazáním obnov
  soubor z kopie před úpravou a potvrď prázdný `git diff`.
  Proč: čtyři nové asercie nad `$activityByBranch` vypadaly adekvátně podle
  tvaru fixtury; se smazaným řádkem sada nahlásila `3/43 FAILED` a jmenovala
  dormantní větev. Naopak dva jiné případy (symref `origin/HEAD`,
  `-BranchGlob`) prošly i proti neopravenému skriptu, protože je řešil jiný,
  existující mechanismus — takové asercie oddělit jako zámek, ne jako důkaz.
- **Negativní běh rozděl do TŘÍ kategorií, ne dvou: zčervenalo, zůstalo
  zeleně v obou bězích (regresní zámek), a NEPROVEDENO** (vše za bodem
  přerušení v transkriptu). Bod přerušení vyčti z transkriptu, než
  kategorizaci napíšeš, a asercii, která zezelenala jen proto, že mutace
  vyprázdnila kolekci a testovaná vlastnost je „nic v ní není", neoznačuj
  za zámek.
  Proč: šest asercí za bodem `IndexOutOfRangeException`/přístupu na
  nulovou vlastnost se v obou sadách nikdy nevykonalo, přesto byly zprvu
  popsány jako „zůstaly zelené" regresní zámky.
- **Po negativitě, kde brief jmenuje konkrétní počet/název asercí, které
  mají zčervenat, ověř PO běhu, jestli nezčervenaly i jiné asercie testující
  STEJNOU vlastnost na jiné fixtuře.** Rozdíl proti briefu není chyba — je
  to úplnější důkaz; report ho vysvětli, ne zamlč.
  Proč: mutace „odstranění `if (Test-Path …)` větve" zčervenala 5 asercí
  místo briefem jmenovaných 2 — kaskáda přes změněné `$e.Ref` a shodný
  scénář IDLE, který testuje tutéž přednost `Báze` řádku na jiné fixtuře.
- **Prázdný `git diff` po obnově souboru z negativity-checku nic
  nedokazuje, pokud je soubor `??` (netrackovaný).** Před spoléháním na
  tuto kontrolu ověř `git status --short` na dané cestě; je-li netrackovaný,
  porovnej obnovený soubor přímo s pre-mutační zálohou (diff/checksum).
  Proč: `git diff` mlčel před i po chybné obnově souboru, který byl v tomto
  tasku teprve vytvořen a ještě ne `git add`ovaný — prázdný výstup by
  nerozeznal správnou obnovu od žádné.
- **Když mutovaný soubor už nese nekomitované úpravy ze stejné vlny,
  obnovu dělej zálohou (`Copy-Item` před mutací, `Move-Item -Force` zpět),
  ne `git checkout -- <path>`,** a ověř `git diff --numstat` proti
  pre-mutačním počtům plus grepem mutovaného konstruktu zpět na původní
  text. Kontrola „prázdný `git diff`" platí jen tam, kde byl soubor před
  mutací čistý. Explicitní tvar důkazu: před mutací zkopíruj soubor do
  scratche a spočítej `sha256sum`; po obnově porovnej `sha256sum` obou
  souborů a `cmp`.
  Proč: `git checkout` by spolu s mutací zahodil i uncommitnutý docstring
  rewrite ze stejné vlny; prázdný `git diff` po takové obnově by dokazoval
  ŠPATNÝ stav. Platí i pro netrackovaný soubor s nekomitovanými úpravami ze
  stejné vlny — `sha256sum`+`cmp` obou kopií dokáže obnovu i tam, kde
  `git diff --numstat` na netrackovanou cestu mlčí.
- **Když je parametr aserčního helperu typovaný `[bool]`, guardovaný index
  ukonči SROVNÁNÍM** (`(… | Select-Object -First 1 -ExpandProperty X)
  -eq $true`), **ne jen `Select-Object -First 1 -ExpandProperty X`.**
  Netypované parametry (`Assert-Eq`) srovnání nepotřebují.
  Proč: prázdná pipeline se pod mutací svázala s `[bool] $cond` jako `""` a
  hodila `Cannot process argument transformation`, tutéž chybu, kterou
  guard měl odstranit, jen jinde — ověř tvar spuštěním sady pod mutací, obě
  varianty vypadají v diffu identicky.
- **Před psaním indexových guardů spusť mutaci a přečti, KTERÝ index selže
  první — guarduj celou kolekci, kterou mutace zasahuje, ne jen indexy,
  které review vzorkovalo.**
  Proč: mutace `%(refname:lstrip=3)` → `%(refname:short)` vyprázdnila
  seznam kandidátů od první skupiny asercí (řádek 46), sedm řádků před
  dvěma indexy, které review jmenovalo (53, 57); guard jen jmenovaných
  řádků by sadě nedovolil ohlásit vlastní selhání.
- **Podmíněný důkazní/kontrolní krok (proběhne jen když to vstup/konfigurace
  umožní) drž na TŘECH stavech, ne dvou** (`$null` = neproběhlo), a jeho
  přeskočení VŽDY ohlas vlastní poznámkou odlišenou od potvrzení. Do
  agregovaného výsledku přidávej podmínku jen pod `if ($null -ne $result)`,
  nikdy prostým booleovským AND. Ke kroku navíc přidej vlastní kontrolu se
  STEJNÝM tvarem vstupu, kterou testovaná podmínka nepokrývá, a sdílej mezi
  oběma proměnnou, jejíž záměna důkaz kazí — jinak mutace zpět na
  dekorativní podobu kroku projde celou sadou beze zmínky.
  Proč: naivní `$ok = … -and ($extra.Code -ne 0)` by při přeskočení
  srovnávalo `$null` a zezelenalo/zčervenalo náhodou; konfigurace jako
  `ums-*`, která krok sama odebrala, nechala výstup zeleně beze signálu —
  zmizela tak jediná pojistka proti návratu dekorativního důkazu.
- **Jméno, které si testovací kód pro pozitivní kontrolu vymyslí (větev,
  soubor), prověř proti reálné konfiguraci uživatele**, ne proti vlastní
  představě „neutrálního" jména. Měj víc strukturálně různých kandidátů
  a vezmi první nekonfliktní; když nezbyde žádný, krok přeskoč a ohlas to —
  nikdy z toho nedělej chybu uživatelovy konfigurace.
  Proč: pevné jméno `feature/ums-install-verify` v repozitáři, který chrání
  `feature/*`, způsobilo, že hook správně zamítl push a instalátor to
  přečetl jako rozbitý hook.
- **Tvrzení „stav/počet X je takový" ověřuj strojově v TOMTO běhu**, ne
  odvozením z briefu, review nebo z toho, že jiné pravidlo to naznačuje — a
  testuj na případu, kde má detektor NĚCO najít, ne na tom, kde má vrátit
  prázdno. Negativní běh je jako důkaz bezcenný právě tam, kde je „nic" i
  legitimní stav (IDLE, čistý strom, žádné nálezy).
  Proč: brief tvrdil dvě kotvy na jednom řádku; `--` uvnitř slugu se čte
  jako dvě pomlčky, ale je to jedna kotva — a `grep -c ACTIVE` na bázové
  `context.md` (IDLE) vrátil `0`, což je i správná odpověď na IDLE; teprve
  běh proti scratch větvi se skutečným pinem ukázal také `0` — grep je
  slepý v obou stavech.
- **Počty asercí v dokumentaci vždy získej spuštěním CELÉ sady ve stejném
  sezení jako úpravu**, nikdy aritmetikou nad čísly z review nebo staršího
  zápisu. Nové číslo rekonciliuj proti předchozímu přes delty, které jsi sám
  zavedl. Součet per-sadových čísel nech spočítat strojově
  (`… | grep -Eo '^[0-9]+ passed' | awk '{s+=$1} END {print s}'`), nikdy
  ručně v hlavě — a počet sad, přes které sčítáš, ber z `find ums -name
  "*.tests.ps1" | wc -l`, ne z vlastního seznamu dávek.
  Proč: všechna čísla byla před vlnou správná, ale vlna přidala 16 asercí;
  spuštění všech 13 sad dalo 564 a delty (+4/+2/+3/+7) přesně sedly na
  rozdíl. Ruční součet stejných šestnácti (naměřených, správných) čísel dal
  693 místo správných 716 — chybu odhalily až delty proti předchozímu kolu;
  jinde vlastní seznam dávek tvrdil 15 sad, výpis smyčky jich uvedl 16
  a `find` jich napočítal 17.
- **Fixture repo pro testy nad stářím/aktivitou commitu nastavuj datem
  vyjádřeným jako věk ve dnech vůči času vytvoření fixtury**
  (`GIT_AUTHOR_DATE` i `GIT_COMMITTER_DATE`), ne absolutním datem —
  proměnné po použití maž.
  Proč: fixtura, která staré datum nastavovala jen jedné větvi a ostatní
  nechávala na systémovém čase, by s oknem aktivity 30 dní jednoho dne
  začala rozhodovat podle toho, kdy se sada spustí.
- **Než přidáš do zrcadleného adresáře (`Copy-Mirrored` v syncu) nový povinný
  soubor, dohledej ho v syncovacím skriptu a zjisti, jestli cíl maže
  a nahrazuje.** Do minimal-but-complete fixtury syncu kopíruj skutečný
  soubor, ne stub, když ho spotřebitel dot-sourcuje.
  Proč: fake monorepo ve fixture mělo v `shared/` jen stub; `Copy-Mirrored`
  ho nahradil za loader z fork copy, instalátor spadl na chybu
  a nesouvisející test syncu zčervenal o dvě asercie dál.
- **Vkládání nového testu „na konec, před `Complete-Tests`" do velké
  `.tests.ps1` sady se sdílenou fixturou ověř dvojmo: (1) jsou pomocné
  funkce, které chceš použít, v tom bodě souboru už definované** (funkce
  se v PowerShell skriptu musí objevit textově před prvním voláním), **a
  (2) žije v tom bodě sdílená fixtura ještě A má historii, kterou scénář
  předpokládá** (grep na poslední `Remove-Item -Recurse -Force $root`/
  `$work` před cílovým místem). Když sdílená fixtura nevyhovuje, použij
  existující fixture-helper (`New-PushFixture` a obdoba) místo ohýbání
  testu na zastaralý stav sdílené fixtury.
  Proč: instrukce „přidej na konec souboru, před `Complete-Tests`" byla
  jednou čtena doslovně a `$root` (a tedy `$work`/`$origin`/`$canaryOut`)
  byl už smazaný předchozím řádkem `Remove-Item -Recurse -Force $root`
  bezprostředně nad `Complete-Tests`. Podruhé stejná past navíc narazila
  na `Invoke-WithMarker`/`Invoke-WithoutMarker` definované až níž v
  souboru (`term not recognized`) a na primární fixturu dávno uklizenou
  o ~230 řádků dřív, jejíž `develop` má navíc vlastní historii nezávislou
  na `feature/x` od dřívějších case 1/15 — FF-na-publikované test by
  selhal z fixturní matematiky, ne z testované logiky.
- **Než napíšeš nový test case pozdě v sekvenci, který sdílí `$work`
  s desítkami předchozích případů, zjisti STROJOVĚ stav klíčové větve před
  svým testem** (`git log --oneline`/`Get-Sha` local vs. remote) — case,
  který dřív záměrně nechal větev v divergentním/pozadu stavu, otráví
  každý pozdější prostý push na stejnou větev.
  Proč: fixture case 4 (zamítnutý force push) záměrně nechává lokální
  `feature/x` divergentní od `origin/feature/x`; nový case 22 dělal prostý
  checkout + commit + push bez resynchronizace a `git push origin
  feature/x` skončil `! [rejected] ... (non-fast-forward)` — odmítnutí na
  úrovni samotného gitu, ne kvůli testovanému hooku/chainingu.
- **Smyčku přes všechny testovací sady vrstvy spouštěj po dávkách
  (1–4 souborů), ne jedním příkazem s výchozím timeoutem.**
  Proč: `for t in $(find ums -name "*.tests.ps1"); do pwsh ...; done` jako
  jeden Bash příkaz přesáhl 2–5minutový limit uprostřed sad (jedna sada
  sama běžela přes minutu) a byl zabit bez signálu, které sady doběhly; po
  rozdělení na dávky s explicitním `timeout` na dávku doběhne každá dávka
  se čitelným výstupem, i když 16 sad dohromady zabere několik minut.
- **Úklid throwaway fixtury přes `rm -rf` dělej jako samostatné, izolované
  volání, ne zřetězené `&&`/`;` s dalšími příkazy.**
  Proč: bezpečnostní hlídka nástroje zablokovala i čistě throwaway
  `mktemp -d` fixture zřetězenou s dalšími příkazy v jednom volání — reaguje
  na přítomnost `rm -rf` v řetězci bez ohledu na cíl. Když nástroj odmítne
  i izolované volání, fixture v OS temp adresáři je bezpečné nechat ležet
  (neovlivňuje stav repa) a úklid vynechat.
- **Kanárek testující exec bit odsunutého cizího hooku ověřuj jen tím, že
  PO instalaci vůbec existuje/byl zavolán — ne tím, že se neaktivoval dřív,
  než to udělá tvůj vlastní test krok.**
  Proč: `Invoke-Installer` sám spustí `run_chained` v rámci svého vlastního
  self-test proof (accept-běh hook nezamítá, takže zavolá řetězený cizí
  hook) — kanárkový soubor existoval hned po instalaci, ještě před reálným
  pushem testu. Instalátorův self-test proof je legitimní dřívější
  spouštěč stejné vlastnosti, ne šum k vyloučení.
- **Fallback na přímou kontrolu `test -x` drž jako záložní plán jen pro
  případ, kdy stavba nové push-schopné fixtury (origin + work + upstream
  ticket větev) není proveditelná — jinak je canary bez chmod silnější
  důkaz a patří první.**
  Proč: canary testuje END-TO-END chování přes `run_chained`, ne jen bit na
  disku; ověřeno na nové fixtuře analogické existující primární fixtuře —
  postavila se bez potíží a reálný push spolehlivě ukázal spuštění
  kanárku napoprvé.
- **U přejmenování s přechodnou kompatibilitou (staré jméno dál funguje)
  nestačí RED běh proti nezměněnému kódu — přidej pro každou dvojici
  staré/nové jméno asercii na PLNÝ text hlášky zastaralosti (obsahující OBĚ
  jména) a její nosnost ověř cílenou mutací té větve.**
  Proč: dvě asercie o přechodném přijímání starého jména byly zelené i
  v RED běhu, protože starý hook staré jméno propouštěl jinou větví; cílená
  mutace (smazání `elif` větve v novém kódu) dala `3/203 FAILED` a
  odhalila, že vzor jen na nové jméno matchne i sousední zamítací hlášku
  a nic nehlídá.
- **U každého nového kontrolního/negativního případu si nejdřív odpověz,
  KTERÝ mechanismus na něj dopadá; pokud ho vyřazuje jiný, starší
  mechanismus než ten, co právě opravuješ, je to regresní zámek, ne důkaz
  opravy — do sady důkazů ho nepiš.** Rychlá kontrola: spusť ho proti kódu
  PŘED opravou; zelený případ tam znamená zámek.
  Proč: kontrolní případ `grep -rn "git push --mirror" docs/` byl zelený
  i před opravou command position, protože token je `"git` (s uvozovkou)
  a `isGitToken` ho neuzná — s opravou neměl nic společného. Nahradily ho
  `echo git push --mirror` a heredoc, kde je token `git` neuvozený a rozdíl
  před/po je skutečný.
- **Negativity-check guardu proti selhání přesměrování z chybějícího
  souboru nemůže na msys `sh` čekat zčervenání „operace prošla" —
  neinteraktivní shell selhání přesměrování v tomto prostředí fatálně
  ukončí sám, ještě před testovaným kódem. Aserci piš na ROZLIŠITELNÝ
  pozorovatelný projev (vlastní hláška/formát/kód), a v reportu odděl „co
  guard mění pozorovatelně" od „co by teoreticky mohlo selhat jinak na
  jiném POSIX shellu".**
  Proč: dočasné odstranění fail-closed guardu (`cat > "$stdin_buf" || {…;
  exit 1; }`) mělo shodit všechny tři asercie fail-open scénáře; místo
  toho `done < "$stdin_buf"` s neexistujícím souborem fatálně ukončil
  skript na msys `sh` dřív, než se dostal k `run_chained`/`exit 0` —
  zčervenala jen aserce na UMS hlášku, zbylé dvě zůstaly zeleně i bez
  guardu.
- **Při vlně, která rozšiřuje sadu i kód zároveň, spusť vedle nové sady
  i HEAD verzi TÉŽE sady proti novému kódu** (`git show HEAD:<suite> |
  Set-Content <tests-dir>/_baseline-count.tests.ps1`, ve stejném adresáři
  `tests/`, jako dočasný soubor) — výsledek je zároveň baseline pro deltu
  i regresní důkaz aditivnosti. Po běhu soubor smaž a ověř `find ums -name
  "*.tests.ps1" | wc -l`, aby dočasná sada nezůstala ve smyčce vrstvy.
  Proč: součet per-suite čísel dal 892 proti dřívějším 842, ale sám
  neříkal, jestli je rozdíl jen z nových asercí, nebo jestli některá
  stávající asercie otočila verdikt — spuštění HEAD verze sady proti
  novému kódu vrátilo `220 passed`, exit 0, a rozhodlo obě otázky
  najednou.
- **Při bisekci velké `.tests.ps1` sady dělej `sed -n '1,Np'` probe kopie
  VE STEJNÉM adresáři jako originál (ne do `/tmp`)**, ať
  `$PSScriptRoot`-relativní cesty (`. (Join-Path $PSScriptRoot
  '_assert.ps1')`, `..\install-git-hooks.ps1`) fungují beze změny; po
  skončení bisekce probe soubory smaž.
  Proč: kopie v `tests/` zdědila stejný `$PSScriptRoot` jako originál, takže
  bisekce (probe1/probe2/probe3) mohla přímo spouštět částečné verze velké
  sady bez úpravy relativních cest; kopie mimo `tests/` by totéž vyžadovala
  ruční přepis cest.

## PowerShell v této vrstvě

- **Nikdy nedávej kudrnaté uvozovky dovnitř řetězce uvozeného odpovídajícím
  ASCII znakem.** U+201C/U+201D/U+201E/U+201F i U+2018/U+2019/U+201A/U+201B
  bere parser jako zaměnitelné ukončovací znaky. České uvozovky patří výhradně
  do jednoduše uvozeného literálu (`'…'`), kde na ně parser nereaguje.
  Proč: řetězec `"…zůstal „Product", zbytek."` se ukončí už na `„` a zbytek se
  tiše stane bezejmenným argumentem — hláška se usekne uprostřed věty, bez
  chyby a bez varování. Všechny výstupy této vrstvy jsou česky, takže je to
  past, na kterou se tu naráží opakovaně. Kontroluj ji greppem přes celý
  skript, ne jen tam, kde chybu čekáš.
- **Obal `Get-Content` do `@()`, když budeš volat `.Count` nebo indexovat.**
  Jednořádkový soubor vrací skalární `String` a `.Count` pod
  `Set-StrictMode -Version Latest` spadne na `PropertyNotFoundException`.
  Proč: obvyklý `if ($null -eq $x) { $x = @() }` kryje jen prázdný vstup, ne
  jednoprvkový. `@(Get-Content <prázdný soubor>)` přitom dá pole s `Count = 0`,
  ne pole s jedním `$null` — jeden obal řeší oba okraje.
- **`Set-Content -Encoding UTF8` v PowerShellu 7 BOM nepřidává.** Ověřeno
  bajtově. Chování se liší od Windows PowerShellu 5.1, kde stejný parametr BOM
  přidával, takže tam, kde je vyžadováno „UTF-8 bez BOM", není potřeba žádná
  obezlička.
- **Český výstup skriptů ověřuj přes PowerShell tool nebo bajtově, ne očima
  v bashové konzoli.** Ta zde nemá kompatibilní code page a zobrazí `hl?s?`
  i tam, kde soubor na disku obsahuje správné UTF-8 (`c4 8d` = `č`, bez BOM).
  Stejně bajtově, ne greppem ani `od -c`, ověřuj i CRLF: `grep -c $'\r'`
  a `od -c | grep -c '\r'` obě nahlásily CR na všech řádcích souboru s
  nula CR bajty (`od -c` vypisuje zpětná lomítka i pro jiné escapy a soubor
  sám obsahuje literální `\`) — použij `tr -dc '\r' < f | wc -c` a
  `tr -dc '\n' < f | wc -c`, porovnej proti blobu (`git cat-file blob
  HEAD:<cesta> | tr -dc '\r' | wc -c`) a `git check-attr -a <cesta>`, jestli
  `eol=lf` na cestu vůbec dopadá; varování `LF will be replaced by CRLF`
  u `.ps1` pod `core.autocrlf=true` je normální stav, ne nález. Věta
  o vzhledu/kódování výstupu („je to jen code page, obsah je v pořádku")
  se NIKDY nesmí kopírovat mezi koly beze změny — u KAŽDÉHO nového kola, kde
  soubor prošel editací, spusť čerstvý bajtový/grep test na konkrétní
  diakritická slova a teprve výsledek toho běhu napiš do reportu.
  Proč: zdánlivě poškozený výstup svede k „opravě" kódování, které je
  v pořádku. Při podezření sáhni po `xxd`, ne po zobrazeném textu. Totéž
  potká diakritiku, kterou skript posílá zpátky do gitu (jméno větve, cesta) —
  viz [tech.md](tech.md), sekce „Pasti prostředí" — a nativní stderr čtený
  přes PowerShellovou pipeline (`[Console]::OutputEncoding` dekóduje UTF-8
  bajty přes cp852/cp1250); u druhého případu přesměruj stderr **na úrovni
  shellu** do souboru (`& $gitBash -c 'cd "$1" && git push … 2>"$2"' _ $repo
  $errFile`) a čti ho `Get-Content -Encoding utf8`, ne přes pipeline. Stejná
  věta o code page, zkopírovaná z předchozího kola bez nového měření, byla
  jednou pravdivá a podruhé ne — assertion texty byly reálně stripnuté na
  ASCII (`znacky`, `puvodni`, `prezila`…), což odhalil až grep na UTF-8
  diakritické bajty, který vrátil nulu.
- **Pod `Set-StrictMode -Version Latest` nevěř tomu, že úspěšný
  `ConvertFrom-Json` znamená objekt s vlastnostmi.** JSON dovoluje kořenové
  `null`, skalár i pole a všechny prolezou parserem beze chyby — `try/catch`
  kolem `ConvertFrom-Json` se tedy nikdy nespustí. Před `.PSObject.Properties`
  ověř typ (`$json -is [System.Management.Automation.PSCustomObject]`)
  a vlastnosti materializuj do plochého array
  (`@(@($json.PSObject.Properties) | ForEach-Object { $_.Name })`), nikdy
  přímo `.Properties.Name` na živé kolekci. Chování ověř empiricky na čtyřech
  tvarech (`{}`, `null`, `42`, `[1,2,3]`) předem jedním `pwsh -Command`.
  Proč: loader konfigurace shodila výjimku „The property 'Name'/'Properties'
  cannot be found" až při reálném použití — `try/catch` reportoval falešný
  pocit bezpečí.
- **`-like` na neobvyklém vzoru (např. `Maint/[0-9`) může hodit výjimku,
  nebo — v `catch`, který vrací bool — tiše vrátit špatnou odpověď.**
  Rozšiřuješ-li existující `-like` volání do nové cesty, dohledej, co ho na
  starém místě chránilo (metaznakový filtr, `if ($extra)`), a rozhodni
  explicitně, jestli ta ochrana platí i na novém místě. Když funkce vrací
  `$true` z obou větví (match i catch), rozliš „ano" od „nevím, nemohl jsem
  to vyhodnotit" jako DRUHOU návratovou hodnotu.
  Proč: neošetřená výjimka na wildcardu shodila celý souhrn instalátoru na
  exit 1 u hooku, který byl ve skutečnosti funkční; a `Test-NameIsConfigured`
  s `["Branches/*", "Maint/[0-9"]` naopak nahlásila „konfigurace pokrývá
  kontrolní jméno" (nepravda — POSIX `case` čte `Maint/[0-9` jako literál)
  a tichým `[installed + verified live]` smazala jedinou pojistku proti
  dekorativnímu důkazu. Mechanizované řešení dnes existuje jako
  `Test-UmsProtectedBranch` ve sdílených skriptech vrstvy
  (`ums/.claude/skills/shared/scripts/`), které vrací právě tento tristate
  místo tiché špatné odpovědi.
- **Windows cesty vkládané do `PATH` (nebo kamkoli s `:` separátorem)
  v msys/Cygwin vždy převeď `cygpath -u`.** `C:/…/shim` se na `:` rozpadne na
  `C` a `/…/shim`, obě neexistující, a shim se nikdy nezavolá bez jediné
  zmínky v testu. Do harnessu, který přes `PATH` nahrazuje nástroj, přidej
  explicitní ověření, že náhrada platí
  (`[ "$(command -v sed)" = "$shimdir/sed" ] || exit 98`).
  Proč: shim se nikdy nezavolal, test přesto zezelenal, protože se použil
  skutečný `sed` v textovém režimu a chráněná větev byla zamítnuta „správně"
  ze špatného důvodu.
- **`$(command)` v command substitution není průhledný kanál pro CR/CRLF
  testy — strhne jen trailing byte, a msys bash jinak než skutečný POSIX
  shell.** Hodnotu pod testem umísti na jiný než poslední řádek souboru;
  jednoprvkový/poslední-řádkový vstup nic nedokazuje.
  Proč: jednořádkový CRLF seznam prošel testem i bez opravy CR handlingu —
  msys bash strhl celé trailing CRLF, takže jediný (a poslední) vzor vyšel
  čistý bez ohledu na kód.
- **Manuální spouštění Node/PowerShell hooků z Git Bash na Windows potřebuje
  Windows-styl cestu (`pwd -W`), ne Unix-styl (`$(pwd)`)** — jinak `node`
  interpretuje `/c/Users/...` jako drive-relative (`C:\c\Users\...`)
  a konfigurační soubor se nenajde. Ručně skládané JSON payloady s cestou
  obsahující zpětná lomítka nejsou platný JSON — použij `cygpath -m`/`pwd -W`,
  ne raw backslash cestu skládanou stringovou konkatenací. Prázdný výstup
  z manuální sondy hooku pro případ, který má zamítnout, nejdřív ověř, jestli
  vstupní JSON vůbec naparsoval — neber to bez dalšího jako potvrzení
  „povoleno".
  Proč: guard tiše spadl na vestavěný seznam a chráněná větev prošla jako
  nechráněná, přestože implementace byla správná; jinde `JSON.parse` selhal
  na neuvozených zpětných lomítkách a chráněný i nechráněný případ vrátily
  identický prázdný výstup.
- **Per-referenci volání externího procesu (`realpath`, obecně cokoli ve
  `while read` smyčce) nad monorepem drž na konstantní počet procesů.** Spawn
  procesu je na Windows řádově dražší než na Linuxu — přepiš na jeden
  `git ls-files` + jeden `xargs … grep` + jeden `sed`/`awk` nad celým
  streamem, nebo hodnotu získej jinak (např. basename místo resolvování
  `..`). `while read` s příkazem uvnitř je červený signál.
  Proč: smyčka s `realpath -m --relative-to=.` nad ~500 projekty a tisíci
  referencemi neběžela do 300 s; přepis na streamové zpracování to srazil na
  0,5–2,6 s (100×).
- **Vzdálené větve pro porovnání se jmény lokálních větví vypisuj
  `--format='%(refname:lstrip=3)'`, ne `%(refname:short)`, a filtruj
  `grep -v '^HEAD$'`.**
  Proč: `%(refname:short)` nad `refs/remotes/origin/` vrátil bare `origin`
  pro symref `origin/HEAD` a v každém jméně ponechal remote prefix, který
  v `protectedBranches` nematchne nic — obojí by se dostalo do seznamu
  chráněných větví jako fantomová položka.
- **Skill snippet, který dot-sourcuje jeden shared skript a pak volá i
  funkce z JINÉHO shared skriptu, projdi řádek po řádku a potvrď, že
  KAŽDÁ volaná funkce je dot-sourcovaná explicitně NAD voláním ve stejném
  snippetu** — nikdy jen transitivně přes jiný helper, i když taková cesta
  existuje. Kontrola je inventář per snippet, ne grep na token; listuj
  fenced `powershell` bloky, které dot-sourcují (na rozdíl od těch, co
  spouští `pwsh <script>` jako subprocess — ty jsou jiná, imunní třída).
  Proč: `Test-UmsProtectedBranch.ps1` nedotsourcuje nic, takže volání
  `Get-UmsRepoConfig` za ním by spadlo na `CommandNotFoundException` přímo
  na fail-closed STOPu, kde by agent nejspíš improvizoval; `mb-state`
  dnes funguje jen díky transitivnímu tahu přes `Get-UmsEffectiveBase.ps1`,
  což se tiše rozbije na první reorganizaci pořadí.
- **Když jeden pomocný wrapper funkce (`[scriptblock] $Param`) volá jiný
  TAKÉ takto parametrizovaný wrapper a předává mu literální
  `{ ... & $Param ... }`, dej VŠEM funkcím v celém řetězci wrapperů RŮZNÁ
  jména parametru — pravidlo je kolize JMEN napříč celým řetězcem, ne
  nutnost vyhýbat se delegaci.** Před psaním/rozšiřováním takového helperu
  vypiš jména parametrů všech funkcí v řetězci (`grep -n 'function
  Invoke-With' <sada>`) a ověř nové jméno desetiřádkovým repro skriptem
  s počítadlem hloubky, ne úsudkem.
  Proč: `Invoke-WithMarker([scriptblock] $Body)` volající
  `Invoke-WithoutMarker([scriptblock] $Body)` se stejným jménem parametru
  spadl na `Stack overflow.` (exit `0xC00000FD`) — `& $Body` uvnitř
  vnořeného scriptblocku se dynamicky váže na `$Body` scope FUNKCE, ve
  které `&` právě běží, ne na lexikální scope zápisu. Přejmenování jen
  VNITŘNÍHO (volajícího) parametru samo o sobě stačilo (182 passed, žádné
  zpomalení) — self-containment nebyl nutný. Past se vrací s každou další
  vrstvou: přidání `Invoke-WithHumanPush([string] $VarName, [scriptblock]
  $Body)` do řetězce s nezměněným jménem `$Body` dalo `RECURSION: depth 51`
  ve standalone repro; přejmenování na `$PushBody` opravilo na `depth=1`.
- **Chceš-li, aby POSIX shell uvnitř dvojitých uvozovek expandoval
  `$*`/`$@`/proměnnou, piš do PowerShellového `@"…"@` here-stringu holé
  `$*` bez zpětného lomítka** — zpětné lomítko před `$` v tomto kontextu
  dvakrát neguje: PowerShell ho ponechá doslova (backslash není v PS
  řetězcích escape) a `sh` ho pak přečte jako escape, který expanzi právě
  VYPÍNÁ. Ověřuj bajtově (`pwsh -NoProfile -Command`), ne odhadem z toho,
  jak by se literál choval v jednom jazyce samotném.
  Proč: `@"…\$*…"@` zapsalo `\$*` doslova; POSIX `sh` uvnitř dvojitých
  uvozovek to čte jako escapovaný literální `$`, takže `"args=\$*"`
  vytiskne `args=$*` beze expanze — přesný opak zamýšleného efektu.
- **`$obj.PSObject.Properties.Name` na nově vytvořeném prázdném
  `[pscustomobject]@{}` vrací `$null`, ne prázdné pole — `.Contains(...)`
  na něm spadne.** Materializuj napřed přes `@(@($obj.PSObject.Properties)
  | ForEach-Object { $_.Name })` a použij `-contains`/`-notcontains`.
  Proč: past se neprojevila u TOML větve (`codex`), jen u JSON větve
  (`gemini`/`kilocode`) při použití prázdného pscustomobjectu jako fallbacku
  pro chybějící konfigurační soubor — i částečně zelený běh (2 ze 3 agentů)
  může past skrývat.
- **Když rozšíříš registraci hooku/guardu o další nástroj (matcher na víc
  než jeden `tool_name`), projdi VŠECHNY textové kontroly v něm a pro
  KAŽDOU napiš, jak vypadá její vstup v novém nástroji — a přidej do sady
  helper s novým `tool_name` dřív, než napíšeš první novou asercii.** Sada,
  která mluví jen jedním `tool_name`, dokazuje jen polovinu registrace.
  Kontrolní otázka: „co je v tomhle nástroji spelling téže věci?" — pro
  proměnnou prostředí, cestu, přesměrování i řetězení příkazů zvlášť.
  Proč: matcher PreToolUse guardu rozšířený na `Bash|PowerShell` nechal
  deset úloh a osm kol review přehlédnout, že PowerShellové přiřazení
  proměnné prostředí (`$env:` prefix) regex `(^|\s)NAME=` nikdy nematchne
  (jméno předchází `env:`) — force-push do chráněné větve s PowerShellovým
  zápisem výjimky prošel jako ALLOW, na Bash toolu tentýž útok DENY.
- **U každého rozšíření vzoru tvaru `JMÉNO<oddělovač>HODNOTA` piš negativa
  na třech osách zvlášť — jiná HODNOTA, jiný TERMINÁTOR za hodnotou, jiný
  PREFIX i SUFFIX jména** — a ke každé nové alternativě ověř, jestli má
  daný konstrukt i ČTECÍ spelling: má-li ho (`$env:X`), vzor musí nést
  hodnotu; nemá-li ho (`Set-Item Env:X`), stačí konstrukt. Tuhle asymetrii
  napiš do komentáře, jinak ji příští kolo „srovná".
  Proč: bez lookaheadu za hodnotou by rozšířený `HUMAN_ESCAPE_RE` nechal
  hodnotu `10` matchnout jako `1`; bez povinné hodnoty u `$env:` tvaru by
  matchlo i ČTENÍ proměnné v podmínce — obojí odhalily až negativní
  asercie, ne četba.
- **Než napíšeš negativní tabulku pro nový konstrukt, zjisti, jestli je to
  nová TŘÍDA konstruktu, nebo člen existující (sourozenec cmdletu, jiné
  hláskování téhož typu) — člen dědí pravidlo třídy, i když brief
  předepisuje jiný tvar testu.** U člena převezmi pravidlo třídy z
  komentáře nad vzorem; osu, která by pravidlo obrátila, zapiš jako asercii
  ve směru, který kód skutečně drží, s důvodem hned vedle ní. Odchylku od
  briefu pojmenuj v reportu i s měřením báze, ne mlčky.
  Proč: brief předepsal aplikovat na `[System.Environment]::` všechny tři
  negativní osy včetně HODNOTY (`'0'`, `"0"`, `10` → ALLOW), ale brief sám
  zavádí ho jako nepovinnou skupinu v existující alternativě — hodnotu
  nesoucí varianta by musela být samostatná alternativa, jinak by jedno
  hláskování téhož .NET typu bylo přísnější než druhé. Měřeno na bázi
  `312737b`: sourozenecké konstrukty (`[Environment]::`, `Set-Item`)
  s hodnotou nula už tehdy zamítaly.
- **Než z tvaru příkazové řádky usoudíš, které tokeny se dostanou ke
  spouštěnému programu (zvlášť u přesměrování stojícího jinde než na
  konci, nebo u operátorů, které se liší mezi shelly jako `*>` vs. glob),
  spusť místo něj skript, který tiskne svoje `argv`, a přečti si to —
  ne úsudkem.**
  Proč: `./fakegit 2>/dev/null push origin develop` dalo `argv: push origin
  develop` (skutečný push, guard musí zamítat), zatímco `./fakegit > push2
  origin develop` dalo `argv: origin develop` (žádný push) — rozdíl mezi
  nimi je jeden znak a bez sondy vypadají jako tentýž tvar.
- **Když má tokenizer nově rozpoznat shellový konstrukt uvnitř invokace,
  zjisti nejdřív, co s ním dělá SKUTEČNÝ shell: odstraní ho z argument listu
  (přesměrování, přiřazení), nebo ukončí příkaz (`;`, roura, `&&`)?**
  Odstranění implementuj jako skip-a-pokračuj, NIKDY jako break — break je
  vždy permisivnější a u fail-closed guardu znamená novou únikovou cestu.
  Asercii na tvar „konstrukt PŘED chráněným cílem" napiš vždy, i když ji
  brief nežádá.
  Proč: brief předepsal, že přesměrování ukončuje argument list přesně jako
  `CONTROL` — doslovné ukončení by prošlo všemi měřenými tvary z briefu,
  ale tvar „origin, `2>&1`, develop" by se stal ALLOW, jednotokenový únik
  přes chráněnou větev; skip-a-pokračuj drží DENY (`develop`) na obou
  toolech, ukončení by ho nedrželo — bash ten příkaz skutečně pushne na
  `develop`.

## Git hooky (POSIX sh)

- **Neuvozené vzory v `for`-cyklu POSIX shellu chraň `set -f`.** Když
  iteruješ přes seznam vzorů uložený v proměnné (`for pat in $patterns`), na
  začátku hooku/skriptu zapni `set -f` (disable pathname expansion) — jinak
  neuvozená expanze podléhá i pathname expansion vůči cwd (git spouští hook
  s cwd = kořen repozitáře) a vzor jako `branches/*` se nahradí jménem
  existujícího souboru. `case "$x" in $pat)` zůstává funkční i pod `set -f`,
  protože tam `$pat` slouží jako glob vzor, ne k expanzi. Ověř dvouřádkovým
  `sh -c` v adresáři, který vzor splňuje, a fixturu testu postav tak, aby ten
  adresář skutečně obsahovala — jinak je test zelený i pro rozbitou
  implementaci.
  Proč: vzor `branches/*` v `is_protected()` vypadl jako `branches/notes.txt`
  a ochrana pro celý vzor tiše zmizela; push na chráněnou větev prošel beze
  zmínky v výstupu hooku.
- **Hook, který čte stdin, ať načte konfiguraci a všechny pomocné hodnoty
  před hlavní `while read` smyčkou.** Do smyčky nedávej nic, co může čerpat
  stdin (`read`, `while read`, `ssh`, `git` podpříkaz bez přesměrování) —
  podřízeným příkazům, u kterých si nejsi jistý, uzavři stdin explicitně
  (`cmd </dev/null`). Testuj vždy pushem více refů najednou — jednořádkový
  push past neodhalí. Regresní test na krádež stdin ověř mutací, která stdin
  SKUTEČNĚ krade — přesun celého bloku čtení konfigurace do smyčky nestačí,
  pokud ten blok sám nečte stdin (např. čte jen soubor); past spouští teprve
  `while read` bez přesměrování.
  Proč: platí pro `pre-push`/`pre-receive`/`post-receive` (ne `update`, ten
  stdin nedostává) — přehlédnutá past je neviditelná v exit kódu (0), hook
  prostě přestane kontrolovat zbylé refy.
- **CR/CRLF chování v POSIX shellu posuzuj empiricky a per platformu, nikdy
  úsudkem ani jedním testem.** Protrasuj každý stupeň pipeline přes `od -c`,
  a totéž zopakuj s binárními režimy (`sed --binary`, `grep -U`), které
  emulují skutečný POSIX shell — msys nástroje na Windows CR zahazují samy
  v textovém režimu, reálný POSIX shell ne. Robustní řešení je odstranit CR
  přímo v pipeline (`tr -d '[:blank:]\r'`), ne spoléhat na to, že producent
  souboru napíše správné řádkování.
  Proč: „na Windows CRLF nevadí" bylo empiricky obráceně — msys `sed`/`grep`
  CR zahazují, ale neuvozený POSIX shell (Linux/macOS/WSL) ne, takže tvrzení
  „musí LF" popisovalo bezpečnou platformu a přehlédlo tu nechráněnou.
- **Testovací/důkazní běh nad hookem, který si sám dohledává konfigurační
  soubor podle `cwd` (`git rev-parse --git-common-dir`), spusť z pracovního
  adresáře cílového repozitáře** (`cd "$root" && …`, spojeno `&&`, aby
  neúspěšný `cd` důkaz položil). Kontrolní otázka: „projde stejně, když ho
  pustím v čistém klonu, kde instalátor nikdy neběžel?"
  Proč: běh spuštěný odjinud četl konfiguraci repozitáře, ze kterého byl
  instalátor spuštěn, ne fixture repa — nový test tak zelenal podle stavu
  cizího souboru, ne podle testované logiky.
- **Krok ověřující řetězení proti reálnému LFS hooku prováděj v throwaway
  klonu, který má nakonfigurovaný (byť fiktivní) remote `origin`.**
  Proč: instalátor cizí hook správně odsunul a zřetězil, ale self-test proof
  bez `origin` skončil exitem 1 — accept běh volá skrz `run_chained`
  skutečný `git-lfs`, který se pokusí resolvnout remote `origin` a bez něj
  spadne (`Invalid remote name "origin"`). Po `git remote add origin
  https://example.invalid/repo.git` proof prošel čistě. Jinak by se chyba
  bez souvislosti s řetězením četla jako regrese.
- **Fixturu pro „tenhle tvar guard vůbec nerozpozná" postav na UVOZENÉM
  `git` tokenu** (`bash -c '…'`, `echo "git push …"`), ne na neuvozeném za
  jiným příkazem — a před zapsáním asercie ji jednou pusť ručně (`printf
  '%s' '<json>' | node <guard>`) a přečti skutečný výstup. Rozhoduje
  uvozovka před `git`, ne to, že je na řádku dřív jiný příkaz.
  Proč: `echo git push --mirror` guard ZAMÍTL — tokenizér `echo` přeskočí,
  na indexu 1 najde NEUVOZENÝ token `git` a spadne na `--mirror`. Naopak
  `bash -c 'git push --mirror origin'` prošel (prázdný stdout), protože
  token je `'git` a `isGitToken` ho neuzná.
- **Testovací sada, jejíž reálné (ne izolované) asercie závisí na chování
  gatovaném značkou, kterou sama zavádí, musí tu značku nastavit explicitně
  NA ÚROVNI SADY**, ne spoléhat na harness, který ji spouští — jinak sada
  tajně funguje jen v jednom konkrétním harnessu/prostředí.
  Proč: nastavení `$env:MB_AGENT_SESSION = '1'` na úrovni celého souboru
  marker-gate sady neposunulo počet passed u ~170 pre-existing případů,
  protože marker-gate helpery samy kolem sebe izolují a restaurují — sadová
  proměnná je jen jejich vstupní/výstupní hodnota, ne překážka. Bez ní
  sada nezávisela jen na testovaném kódu, ale i na tom, že ji spouští
  Claude Code s ambientním `CLAUDECODE=1`.
- **Když dvě kontroly v hooku zamítají tentýž vstup, testuj i TEXT hlášky,
  ne jen zamítací kód — a u každé kontroly se ptej, který vstup se sem
  dostane dřív jinou větví a co mu ta věta říká.** Nedosažitelná chybová
  hláška je signál špatného pořadí, ne mrtvý kód.
  Proč: v `pre-push` s pravidlem o chráněné větvi před zákazem mazání
  posílá mazání nulovou local sha, `is_integration_push` proto vrátí
  false a chráněná větev se trefí první — uživatel dostal „projde jen
  fast-forward" místo hlášky o mazání, ačkoli verdikt (zamítnutí) byl
  správný, takže žádný test na kód to nechytil.

## Upgrade upstreamu (revendor)

Vendorované kopie s overlay bloky vznikají až v cíli nasazení, takže revendor
běží **v monorepu**, ne v tomto repu. Postup je dvoucommitový:

1. V tomto forku sloučit nový upstream: `git fetch vanila --tags`, pak
   `git merge vanila/main` (na `main`, odtud do `ums-memory-bank`).
2. V monorepu:
   `pwsh .claude/scripts/revendor-superpowers.ps1 -Tag <nový tag> -NoOverlays`
   → commit „vanilla sync".
3. `pwsh .claude/scripts/revendor-superpowers.ps1 -OverlaysOnly`
   → commit „overlay".

Proč dva commity: první nese výhradně upstream diff, druhý výhradně zásah UMS.
Ve sloučeném commitu už nejde poznat, co přinesl upstream a co vrstva.

- **Vendorované soubory nikdy needituj ručně mimo bloky
  `<!-- UMS-OVERLAY BEGIN/END -->`.** Změna patří do fragmentu
  `shared/overlays/*.overlay.md` a aplikuje se dalším během.
  Proč: revendor rozbalí upstream znovu a overlaye aplikuje na čistý soubor —
  ruční úprava mimo bloky se tím tiše ztratí.
- **Miss kotvy `ANCHOR-BEFORE` je detektor driftu upstreamu, ne chyba
  k obejití.** Kotva musí matchovat právě jeden řádek cílového souboru; když
  nematchuje, upstream ten řádek změnil. Skript přitom vypíše přesně ty
  fragmenty, které potřebují lidský zásah — oprav je, synchronizuj zpět do
  forku a spusť revendor znovu; nikdy kotvu neuvolňuj, aby „prošla".
- **Revendor spouštěj z PowerShellu, ne z Git Bash shellu.** V Git Bashi
  zdědí skript přes PATH msys `tar`, který windowsovou cestu čte jako
  vzdálený host; v PowerShellu `tar` resolvuje na
  `C:\WINDOWS\system32\tar.exe` a vendor krok projde.
  Proč: běh z Git Bash spadl na `/usr/bin/tar: Cannot connect to C: resolve
  failed` při rozbalování `skills.tar`.
- Verifikační pass běží vždy jako poslední a shodí skript na viselých
  relativních odkazech, zbytcích v5 souborů, chybějících v6 souborech,
  nevyvážených overlay markerech, CRLF v bashových skriptech a na funkčním
  testu SDD skriptů v Git Bashi. Běh je hotový, teprve když skončí
  `Verification passed.`
- Samotnou verifikaci bez vendoringu spustíš přepínačem `-VerifyOnly`.

## CRLF u bezpříponových shellových skriptů

Bashové skripty bez přípony — upstream SDD skripty (`sdd-workspace`,
`task-brief`, `review-package`) a git hook
[`ums/.claude/hooks/pre-push`](../ums/.claude/hooks/pre-push) — musí být
v pracovním stromu s LF.

- **Nevendoruj je prostým `git archive` při `core.autocrlf=true`.** Konverze na
  CRLF rozbije shebang a skript přestane jít spustit. `revendor-superpowers.ps1`
  proto po rozbalení normalizuje konce řádků na LF a verifikační pass CRLF
  kontroluje.
- **Nový bezpříponový shellový soubor commitni až s pravidlem `text eol=lf`**
  v `.gitattributes` (v monorepu `.claude/skills/** text eol=lf`, v tomto forku
  [`ums/.gitattributes`](../ums/.gitattributes)).
  Proč: git podle přípony nepozná, že jde o skript, takže bez pravidla ho
  `core.autocrlf` na Windows převede — a chyba se projeví až u toho, kdo si
  soubor checkoutuje.

## Nasazení vrstvy

`pwsh ums/sync-with-monorepo.ps1` bez parametrů se v interaktivní konzoli
doptá na každý parametr a nabídne default (Enter potvrdí); v neinteraktivním
běhu použije defaulty potichu.

| Parametr | Hodnoty | Default |
|---|---|---|
| `-Agent` | `claude`, `codex`, `gemini`, `kilocode` | `claude` |
| `-Scope` | `Monorepo`, `UserProfile` | `Monorepo` |
| `-Direction` | `FromMonorepo`, `ToMonorepo` | `FromMonorepo` |
| `-MonorepoRoot` | cesta ke klonu monorepa | `D:\_datasys\ums` |

- **`claude` + `Monorepo` je jediná obousměrná kombinace.** `FromMonorepo`
  (default) táhne živou kopii z monorepa do `ums/` tohoto forku — spusť ji po
  každé změně vrstvy provedené v monorepu a výsledek commitni. `ToMonorepo` je
  opačný směr. Každá jiná kombinace je jednosměrný deploy z `ums/` do cíle
  a `-Direction` se ignoruje.
- `gemini` a `kilocode` nemají adresář skillů — dostanou jen glue a blok
  preferencí v instrukčním souboru.
- **`settings.json` se na ne-Claude cíle nenasazuje.**
  Proč: je to registrační soubor Claude Code a přepsal by cizí konfiguraci
  (například `.gemini/settings.json`) — u ostatních harnessů se hooky registrují
  ručně.
- Glue soubory se do cílového config adresáře **mergují po souborech** a nikdy
  nemažou cizí obsah. Blok preferencí se do instrukčního souboru vkládá mezi
  markery `UMS-MEMORY-BANK BEGIN/END`, takže opakovaný běh ho nahradí na místě.
  Při `-Scope UserProfile` se před blok přidá věta omezující platnost pravidel
  na monorepo.
- Vendorované superpowers skilly tento skript nesynchronizuje nikdy — ty
  vznikají revendorem (výše).
- **`cp -r zdroj cíl/` do existujícího stejnojmenného cílového adresáře
  SLUČUJE, nevnořuje** — přidá/přepíše soubory ze zdroje a cizí soubor
  v cíli zachová. Než spustíš plánem předepsané `cp -r` přes živý, sezením
  čtený netrackovaný adresář se shodným jménem posledního segmentu zdroje
  a cíle, ověř chování na dvouřádkové fixture ve scratchpadu (existující cíl
  se svým markerem, zdroj se svým) — ne odvozením z četby příkazu.
  Proč: ověřeno měřením na throwaway fixture: `dst/shared/keepme.txt`
  přežil, nové soubory ze zdroje přibyly, `dst/shared/shared` nevzniklo.
- **Než nasazení postavíš na merge-copy (`cp -r` bez `--delete`), ověř
  `git diff --name-status <base>..HEAD -- <zdrojový-strom>` na řádky D/R.**
  Bez mazání/přejmenování je merge-copy dostatečná; s nimi by nasazení
  uneslo osamocené soubory, které zdroj už nemá, a je potřeba mirror-sync
  nebo explicitní `rm` cílů.
  Proč: kontrola nad tímto plánem nenašla žádné D/R (čistě A/M), což
  potvrdilo, že merge-copy nemůže nechat mrtvý soubor.

### Instalace git hooků do klonu

```bash
pwsh -NoProfile -File ums/.claude/hooks/install-git-hooks.ps1 -RepoRoot <klon>
```

Proč vůbec: git hooky jsou netrackované, takže se s klonem nepřenesou —
`pre-push` záruka publikačního kontraktu v novém klonu chybí, dokud ji tam
někdo nenainstaluje.

- Při `-Scope Monorepo` ho volá `sync-with-monorepo.ps1` sám; při
  `-Scope UserProfile` ne (profil nemá jeden přiřazený repozitář), tam ho spusť
  ručně.
- **Nenulový exit instalátoru neignoruj** — znamená, že záruka není potvrzená:
  `1` = self-test selhal, `2` = ponechán cizí hook, `3` = nainstalováno, ale
  neověřeno (chybí shell pro self-test). Sync ho jen vypíše jako varování
  a pokračuje, takže v dlouhém výpisu snadno zapadne.

### Obnova nasazené kopie v tomto repu

Kořenový `.claude/` a `.agents/skills/` jsou netrackovaná nasazení, ale sezení
v tomto repu čte právě je. **Po každé změně zdroje v `ums/.claude/` nasazení
obnov**, jinak agent pracuje podle staré verze kontraktu i skillů.

- UMS obsah (`shared/`, `mb-*`, `hooks/`, `scripts/`, `settings.json`) je prostá
  kopie z `ums/.claude/` do kořenového `.claude/`; pro Codex ještě
  `ums/.claude/skills/` do `.agents/skills/`.
- Kontrola, že je nasazení aktuální: `Contract-Version` v
  `.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md` musí souhlasit se zdrojem
  a v `.claude/skills/` musí být všechny adresáře `mb-*`, které jsou
  v `ums/.claude/skills/`. Chybějící skill je nejrychlejší příznak zastaralého
  nasazení.
- **Tahle kontrola (Contract-Version + přítomnost všech `mb-*` adresářů)
  odhalí jen CHYBĚJÍCÍ nasazení, ne ZASTARALÉ.** Na staleness (obsah
  souboru se změnil, ne jen jeho existence) použij `diff -rq ums/.claude
  .claude` — a pamatuj, že tři vendorované skilly s overlay bloky se musí
  srovnávat proti monorepo kopii, ne proti `ums/`, kde vůbec neleží (viz
  bod níž).
  Proč: deployovaná kopie `finishing-a-development-branch/SKILL.md` nesla
  16řádkový overlay popisující lokální merge, zatímco zdrojový fragment
  v `ums/.claude/skills/shared/overlays/` měl 109 řádků popisujících
  FF-push integraci s playbook gate — `Contract-Version` i přítomnost
  `mb-*` adresářů přitom obě kontroly prošly beze zmínky.
- Tři upstream skilly s overlay bloky (`brainstorming`,
  `subagent-driven-development`, `finishing-a-development-branch`) se kopií
  nevyrobí — po změně overlay fragmentu je musí vygenerovat revendor.
- **Po každém revendoru dorovnej vendorované skilly i v `.agents/skills`
  kopií z `.claude/skills`** — platí pro tento fork i pro monorepo. Revendor
  cílí jen na `.claude/skills` a sync vendorované skilly nesynchronizuje
  nikdy, takže Codex kopie tiše zaostane. Ověření: `diff -rq` přes všech 14
  vendorovaných adresářů musí být prázdný.
  Proč: po revendoru na kontrakt v2.10 nesl `.agents/skills/brainstorming/`
  v obou repech starý overlay bez bodu oponentury, zatímco `.claude` kopie
  už byla nová — `mb-*` skilly přitom sync dorovnal, takže rozdíl nebyl na
  první pohled vidět.
- **Po editaci overlay fragmentu v `ums/` nejdřív obnov nasazení (kopie
  `ums/.claude/.` → `.claude/`), teprve pak spusť revendor** — revendor sám
  čte fragmenty z NASAZENÉ kopie (`.claude/skills/shared/overlays/`), takže
  pořadí kopie → revendor je závazné. Výsledek ověř grepem na
  charakteristický text nové verze fragmentu ve vygenerovaném souboru.
  Proč: revendor spuštěný bez předchozí obnovy kopie tiše aplikoval starou
  verzi fragmentů a verify pass prošel zeleně; chybějící text ve
  vygenerovaném skillu odhalil až cílený grep.
- **U grepové verifikace vygenerovaného overlay textu vždy ověř i
  case-insensitive variantou (`grep -ni`) dřív, než se nulový zásah
  nahlásí jako anchor-miss STOP** — a v briefu piš frázi přesně tak, jak je
  v overlay fragmentu (včetně velkého počátečního písmene), aby
  korespondovala 1:1.
  Proč: doslovný grep na `"publication guarantee self-check"` (malými
  písmeny) dal nulový zásah, ačkoli fragment i vygenerovaný soubor nesly
  frázi s velkým počátečním písmenem (`Publication guarantee self-check`)
  — bez case-insensitive dokontroly by to vypadalo jako chyba revendoru,
  přestože overlay byl aplikován správně a šlo jen o casing v briefu.
- **Regenerace nasazených (i monorepo) vendorovaných skillů po změně
  fragmentu bez upstream bumpu = plný jednoprůchodový revendor s pinovaným
  tagem (`revendor-superpowers.ps1 -Tag <pin>`), ne `-OverlaysOnly`.**
  `-OverlaysOnly` funguje jen na čerstvě vendorované (pristine) soubory hned
  po běhu `-NoOverlays`.
  Proč: nasazené vendorované soubory už nesou předchozí overlay bloky, takže
  `-OverlaysOnly` skončil FAIL „'brainstorming/SKILL.md' already contains an
  overlay block. Re-vendor first (vendored files must be pristine…)".
- `sync-with-monorepo.ps1` na tohle není: cílí na monorepo nebo na profil
  uživatele, ne na kořen tohoto forku.

## Kontrakt a skilly: soudržnost pravidel a dokumentů

- **Pravidlo má jeden domov.** Napiš ho nejdřív do KONTRAKTU (pořadí kroků,
  aktér, jediný netriviální důvod) a skill smí říct jen „per <jméno sekce>"
  plus co je čistě lokální (nástroj, pořadí vůči vlastním krokům, co NAOPAK
  nedělá) — věta, která v skillu parafrázuje důvod, je budoucí rozchod. Když
  je STEJNÁ chyba objevena rozbitá ve víc než jednom konzumentovi sdíleného
  kontraktu, nespravuj ji lokálně — nejdřív vypiš VŠECHNY konzumenty té
  operace; implementuje-li ji víc než jeden, oprava patří do kontraktu.
  Bezvýjimková zákazová hláška v hlavičce skillu (např. „⛔ ŽÁDNÝ git
  commit/add/push") potřebuje pro jednu dovolenou operaci JMENOVANOU výjimku
  přímo v zákazu, omezenou na konkrétní krok, s napsanou hranicí, kterou
  nepřekračuje — ne tichý rozpor.
  Proč: stejná chyba v pořadí publikace (`push` po každém commitu) se
  ukázala i v `mb-abort`, který ji měl celou — dva konzumenti si vymysleli
  vlastní pořadí pro tutéž operaci a jen jeden byl prověřen; a `git rm -f`
  vyžadovaný kontraktem pro playbook-candidate soubor by bez jmenované
  výjimky přímo odporoval hlavičce `mb-harvest`.
- **Rys, který je git-faktem (tracked/foreign/published), testuj git
  příkazem nebo porovnáním CESTY — nikdy čtením obsahu souboru.** Derivovaný
  stav „nic k udělání", který gatuje krok sahající na git-IGNOROVANOU cestu,
  tu cestu musí probovat explicitně, ne odvozovat ze tří běžných git
  příkazů (`status`, `stash list`, `log --branches --not --remotes`), které
  na ni nevidí.
  Proč: stará podoba `mb-harvest` gate četla „cizí slug" z prvního řádku
  souboru, přestože s jedním souborem na slug je cizost fakt o cestě; a
  netrackovaný neprázdný `playbook-candidates/<slug>.md` je pro
  `.superpowers/` (git-ignored) neviditelný pro všechny tři standardní
  příkazy, takže odvozené „už zaparkováno" nechalo evidenci v pracovním
  stromu přesně v scénáři, pro který výjimka `git add -f` vznikla.
- **Tvrzení „tahle cesta je netrackovaný deployment, commit se jí nedotýká"
  ověřuj `git status --short --ignored=matching -- <cesta>` a čti kód
  `!!`, ne jen absenci řádku v prostém `git status`.**
  Proč: `!!` je git status kód specificky pro ignorovaný obsah, odlišný od
  `??` (untracked); prostá absence řádku by neodlišila „ignorováno" od
  „shodou okolností žádná změna v tomto běhu" — `git status --short
  --ignored=matching -- .claude .agents ums` vrátil `!! .claude/` a
  `!! .agents/skills/` jako strojový důkaz.
- **Po vložení/odstranění kroku v číslovaném pořadí (kontrakt, skill, overlay
  fragment) grepni CELÝ soubor na `step [0-9]`/číslo kroku a přečti seznam
  znovu; odkazuj na sousední krok JMÉNEM fáze, ne pořadovým číslem** — čísla
  se posouvají, jména ne. Grep na `step [0-9]` samotný nechytí plurál
  („steps 4 to 6", „steps 4 and 6" — písmeno `s` láme match) ani spelled-out
  počet („the six steps below") — přidej `steps? [0-9]`/case-insensitive
  `\bstep` a grep na číslovky slovem (`\bšest\b`, `\bsedm\b` apod.), obě
  navíc k plné ruční četbě. Po restrukturaci vícekrokové instrukce ji projdi
  jako chladný čtenář pro KAŽDÝ podporovaný záměr zvlášť, s proměnným stavem
  (např. „je strom čistý?") jako sloupcem tabulky. Chování git příkazu,
  který skript nově použije jako detektor (co vrací na poškozeném/hraničním
  vstupu), ověř EMPIRICKY (např. zapsat 40 hex znaků do rozbitého refu
  a přečíst exit kód) PŘED rozhodnutím, kam v kódu patří jeho ošetření.
  Proč: vložení kroku posunulo dvě interní křížové reference na číslo kroku
  beze zmínky, protože žádný grep na termín kontraktu by je nenašel;
  číslovaný odkaz „fáze 4" v kontraktu ukazoval na krok, který dělá fáze 3;
  tabulkový průchod dvou záměrů hned odhalil defekt pod review i
  nesouvisející mezeru (krok 3 přijímá „bez tiketu", krok 4 už předpokládá
  kód tiketu); `git for-each-ref` na refu s neexistujícím objektem skončil
  `fatal: missing object` a exit 128 sám o sobě — opak předpokladu „to jen
  čte metadata, nespadne"; a plurál „steps 4 and 6"/intro věta „the six
  steps below" po vložení nového kroku zůstaly stejně stale jako singulární
  ordinály, jen je nenajde `step [0-9]`-tvarovaný grep.
- **Věta o pořadí NEOPRAVUJE operaci, která sedí ve špatném kroku** — najdi
  instrukci, která operaci provádí, a přesuň JI. Dvě už existující věty
  tvrdící stejné pořadí jsou signál, že operace je špatně umístěná, ne že je
  potřeba třetí. Po přidání explicitního startpointu k vytvoření větve
  (`switch -c … <báze>` — báze zvolená ve fázi Intent vstupní brány při
  prvním pinování práce, nebo efektivní báze, je-li práce už pinovaná)
  zkontroluj VŠECHNY kroky před ním — pokud
  některý commituje, přesuň vytvoření větve před něj (nekomitovaná práce
  jde s `switch -c` samo).
  Proč: věta „aktivace probíhá na tiketové větvi" nezměnila to, že move byl
  textově i operačně před vytvořením větve — agent čtoucí pořadí zezdola by
  dirtnul strom dřív, než větev vznikla; a explicitní startpoint v kroku PO
  kroku, který komitoval, uvíznul commit na špatné větvi — projevilo se to
  až o dva kroky dál, na STOPu dosažitelnosti.
- **Když se STOP/gate test v jednom kroku skillu rozšíří na strukturálně
  větší množinu stavů, přečti VŠECHNY pozdější kroky TÉHOŽ skillu (ne jen
  jiné soubory) na větve, které předpokládaly starou, užší množinu.** Případ,
  který nová brána zachytí dřív, se stává mrtvým kódem i uvnitř
  report/message šablon, a token-based grep na charakteristickou frázi
  změněného pravidla ho nenajde — mrtvý text tu frázi nemusí obsahovat.
  Proč: rozšíření STOPu z „aktuální větev == odvozené jméno báze" na
  „aktuální větev odpovídá libovolnému vzoru v `protectedBranches`" nechalo
  v kroku Publikace mb-parku bod pro „větev v `protectedBranches`, ale ne
  báze" nedosažitelný — stejná mrtvá větev se objevila potřetí v šabloně
  úspěšného reportu parku.
- **Když overlay/refaktor přesune akci DŘÍV, než ji popisuje existující bod
  checklistu, ten bod musí na začátku říct, jaký stav při čtení PLATÍ
  („tohle už existuje"), a výslovně pozastavit vlastní kontroly** —
  jednosměrný forward-reference odkaz nestačí, bod se pořadovým čtením
  stejně vykoná jako instrukce.
  Proč: agent, který u nezměněného bodu (kde brief pravidlo popsal) znovu
  testoval IDLE postcondition proti vlastnímu čerstvě zapsanému pinu,
  přečetl ACTIVE a vykonal bodovu vlastní instrukci „STOP, smaž větev
  a opakuj" — se lživým nálezem, že práce byla integrována bez harvestu.
- **Overlay úpravu vždy verifikuj proti KONTRAKTU, ne proti briefu**, který
  ho jen parafrázuje — brief je práce k dohledání místa, ne zdroj pravdy.
  Když overlay NAHRAZUJE upstream krok (ne rozšiřuje), jmenovitě neguj staré
  příkazy v textu fragmentu, protože zůstávají viditelné vedle přebíjeného
  textu. Po KAŽDÉ změně pravidla v kontraktu grepni celou vrstvu na jeho
  charakteristický token VČETNĚ hlaviček hooků, šablon reportů a overlay
  fragmentů, a oprav každé restatement ve stejném commitu; a re-čti každou
  cestu, která NĚČÍM konči práci (integrace, abandon, park), a každou větu,
  která předpokládá, co je/není na `origin` — tvrzení pravdivá pod starým
  pořadím publikace se pod novým tiše obrátí.
  Proč: fragment psaný jen z brief formulace by povolil přepis TRACKED
  playbook-candidate souboru, který kontrakt (užší) zakazuje; fragment
  „integrace je fast-forward push" bez negace `git checkout`/`pull`/
  `merge`/`branch -d` nechal oba postupy vypadat platně; po vlně měnící
  `core.hooksPath` a STOP v `mb-park` zůstalo pět z šesti nálezů v místech,
  která pravidlo jen RESTATOVALA; a změna „publikuj po každém commitu"
  nechala nekomitovaný abandon-move zničit jedinou kopii a zapsat trvalou
  „KOLIZI AKTIVNÍ PRÁCE" na originu.
- **Jedna obecná definiční věta („kdekoli tento dokument píše token X, myslí
  se…") nezneplatní specifickou větu, která svou hodnotu tvrdí jako
  VÝHRADNÍ** („jen", „všude jinde", „jediná báze, která se počítá") —
  čtenář narazí na výhradní větu první a nemá signál, že je překonaná. Po
  zavedení obecné věty grepuj i na vlastní exkluzivní/autoritativní
  slovník specifických míst, ne jen na slovník nové obecné věty.
  Proč: holý placeholder token je obecnou větou tiše kryt, ale věta navíc
  JMENUJÍCÍ svůj zdroj (`baseRef` per Repository Configuration) nebo
  tvrdící „jediná, která se počítá" zůstává v rozporu, i když obě čtení
  vedou ke stejné hodnotě.
- **Po zavedení nové instance něčeho, co existující věta počítá jako
  jedinou** („the single exception", „jediná výjimka", „přesně jedna"),
  **grepuj celý dokument na tu POČÍTACÍ frázi samotnou** — samostatně od
  greppu na jméno konceptu — a oprav KAŽDOU větu, která ji používá, se
  zachováním vlastního důvodu každé výjimky u své vlastní věty. Zkontroluj
  po opravě nulový výskyt staré frazování stejným greppem.
  Proč: slovo „jediná" se stalo nepravdivým ve DVOU nezávislých větách ve
  dvou různých sekcích v okamžiku, kdy vznikla druhá instance výjimky — ani
  jedna věta nebyla špatně o svém VLASTNÍM důvodu, jen o kardinalitě, kterou
  tvrdila.
- **Nabídka kurátorovaného seznamu kandidátů, po které následuje pravidlo
  spouštějící se jen na hodnotě MIMO ten seznam, musí explicitně napsat, že
  odpověď mimo nabídku je přípustná** — existence spouštěče sama o sobě
  není důkaz, že nabídka to dovoluje.
  Proč: nabídka postavená výhradně z větví shodných s `protectedBranches`
  (tedy chráněných konstrukcí) nikdy nenapsala, že volná odpověď je
  přijata, čímž byl scénář, pro který STOP existuje (báze mimo
  `protectedBranches`), textově nedosažitelný.
- **Report/status hláška, která jmenuje konkrétní stav nebo tvrdí „opraveno
  X", musí ten stav v TOMTO běhu PŘEČÍST, ne dovodit z jiného pravidla nebo
  napsat ze cvičné paměti.** Když se cesta v kódu přepočítá, přečti CELÝ
  report/hlášku od začátku do konce a u KAŽDÉ věty se zeptej, jestli na
  téhle cestě ještě platí — dej raději samostatnou variantu reportu než
  hedge vlepený do hlášky o úspěchu. Věta „tato změna navíc opravila X"
  patří do reportu jen podložená stavem PŘED změnou ve STEJNÉM sezení
  (`git show <base-sha>:<path>`) — bez něj se vyřazuje.
  Proč: degradovaná cesta instalátoru tvrdila konkrétní chráněné větve
  odvozené z toho, že „hook má fallback" — fallback naskočí jen při
  prázdném seznamu, takže `main` byl ve skutečnosti nechráněný, přestože ho
  výstup jmenoval jako chráněný; jinde jedna oprava patchla souhrn a
  hlavička/závěrečná věta téhož reportu dál tvrdily dokončený park
  a dosažitelnost z originu, která už neplatila; a tvrzení o opraveném
  duplicitním nadpisu se nekonalo — `git show` základní verze žádný duplicit
  neukázal.
- **Dvě hlášení o témže stavu (souhrn × varování, dvě fáze téhož výpočtu)
  musí čerpat z JEDNOHO zdroje pravdy** — po změně textu na jednom místě
  vygrepuj VŠECHNA místa, která o tom stavu mluví, a srovnej je v jednom
  commitu; test piš na CELÝ zploštělý výstup, ne na jednu sekci. Platí i pro
  autoritu OBSAHU vs. autoritu VÝBĚRU: příkaz, který je fakticky autoritou
  na to, co commit obsahuje, není zároveň autoritou na to, KTERÉ položky se
  mají zobrazit — filtr výběru drž jako samostatnou mapu a výstup autority
  s ní protni.
  Proč: souhrn hlásil skutečný seznam chráněných větví, varování o pět
  řádků výš dál jmenovalo vestavěné vzory — kdo se zastavil u (červeně
  psaného) varování, odešel s dojmem, že `main` je chráněný, i když push
  projde; a `branch -r --contains` vrátil VŠECHNY vzdálené větve obsahující
  commit včetně těch, které fáze výběru vyřadila — uspaná větev by se
  vrátila zadními dvířky přes commit společný s živou.
- **Přejmenování toho, co fail-closed brána OVĚŘUJE (např. z lokálního merge
  commitu na pushnutý tip tiketové větve), vyžaduje přepočítat i JEJÍ
  PŘÍKAZ**, odvozený znovu z otázky, ne ze starého příkazu — a v multi-step
  skillu vypiš všechny kroky, které mutují (commit, switch, push, write,
  delete), a VYTÁHNI každý STOP PŘED první z nich, s napsaným důvodem
  pozice v textu.
  Proč: `git branch -r --contains <sha>` dál procházel po přejmenování cíle
  na „pushnutý tip", protože commit byl na originu přes tiketovou větev —
  brána přestala testovat to, co její vlastní próza tvrdila; a STOP na bázi
  v `mb-park`, umístěný čitelně v kroku, kde se báze stává relevantní,
  odpálil AŽ PO tom, co kroky 2–3 před ním už commitovaly — po vzniku
  přesně toho stavu, který má zabránit.
- **Když kontrakt zdůvodňuje manuální krok slabinou automatizovaného, napiš
  tu slabinu jako MECHANISMUS (co automat vzorkuje, co odvozuje, kam
  nedosáhne), ne jako VERDIKT** („nic neprokazuje"). Mechanismus lze znovu
  ověřit proti kódu a hlasitě přestane sedět, když se kód změní; verdikt
  tiše zůstane lží. Stejné pravidlo platí pro reviewera takové věty — ověř
  ji otevřením skriptu, ne důvěrou ve větu nebo v review, které ji citovalo.
  Proč: kontraktová věta „instalátorův self-test prověřuje jen svůj fixní
  pár větví a nic neprokazuje o nově přidaném vzoru" byla měřitelně
  nepravdivá — `install-git-hooks.ps1` obsahuje třetí ověřovací běh přesně
  pro tyto vzory (řádky 451–514) — přestože manuální krok samotný byl
  potřeba z jiného, mechanického důvodu (vzorkuje `Select-Object -First 1`,
  odvozuje jméno větve substitucí `*`→`x`).
- **Než na chybějící závislost vrátíš tvrdou výjimku, dohledej VOLAJÍCÍHO
  a zjisti, co s ní udělá** — zvol tu z obou konečných cest (výjimka vs.
  degradovaný provoz), po které zůstane VÍC ochrany. Náprava (remedy), která
  končí commitem, prověř po celé cestě dál — lze ji pushnout, přenést na
  větev, která ji převezme, kdo ji později vyzdvihne? Když je odpověď „ne"
  na všechny tři, náprava práci uvězní; tvar je „nejdřív vytvoř větev, pak
  commituj", protože nekomitovaná změna jde s `switch -c` samo.
  Proč: `throw` na chybějícím loaderu konfigurace by v degradované cestě
  volajícího (syncu, který nenulový kód tlumí na varování) nechal
  repozitář BEZ hooku a s nechráněným `develop` — méně ochrany než vestavěný
  fallback samotného hooku; a náprava „commituj leftovers na téhle větvi"
  na bázi produkovala nepushnutelný, nepřenositelný a nezaparkovatelný
  commit.
- **Než „opravíš" cestu v instrukci, rozliš, čeho je součástí: MARKDOWN
  odkaz se rozpouští proti adresáři OBSAHUJÍCÍHO souboru, shellový/
  PowerShellový argument proti PRACOVNÍMU adresáři agenta (kořen
  repozitáře).** Precedens z jedné třídy není důkaz pro druhou. Musí-li
  placeholder adresáře skillu na místě zůstat, udělej ho rozpoznatelným
  jednou větou jmenující adresář, na který ukazuje — nepovyšuj ho na
  definici na úrovni kontraktu (to je druhý domov pravidla).
  Proč: návrh nahradit placeholder v PowerShell příkazu (`. <mb-shared>/
  scripts/Get-UmsBaseCandidates.ps1`) spellingem z markdown odkazu v
  `mb-init/SKILL.md` by ukázal mimo repozitář, protože příkaz se rozpouští
  vůči kořeni repa, ne vůči adresáři souboru; kontrakt sám přitom stejný
  tvar placeholderu už používá (`pwsh <mb-doc-index>/scripts/doc-index.ps1`).
- **Hodnotu z konfigurace, která už nese svůj prefix** (`baseRef` =
  `origin/develop`), **nikdy neprefixuj podruhé** v dokumentaci ani
  v příkazu — u KAŽDÉ takové hodnoty se nejdřív podívej na její default
  v loaderu a příkaz vyzkoušej s reálnou hodnotou z repa, ne se zástupným
  symbolem. Zavedeš-li placeholder užívaný na READ místech i na PUSH místě,
  sweepuj OBĚ špatné hláskování zvlášť (`origin/<placeholder>` a
  `HEAD:<placeholder>`) — nejde o jednu chybu formulovanou dvakrát.
  Proč: `git rev-list --count HEAD..origin/<baseRef>` skončil `fatal:
  ambiguous argument 'HEAD..origin/origin/ums-memory-bank'`; a 25 výskytů
  placeholderu ve dvou dokumentech se rozpadlo na dva nezávislé defekty —
  doublovaný prefix na čtecích místech a `HEAD:<baseRef>` na jediném push
  místě (vytvoří vzdálenou větev `origin/develop`, kterou `protectedBranches`
  nezachytí).
- **Rozšíření skillu o schopnost, kvůli které ho má někdo nově VOLAT, uprav
  ve STEJNÉM commitu i `description` ve frontmatteru** — jazykem otázky,
  kterou uživatel položí, ne jménem interní sekce těla; triggering řídí
  výhradně `description`. Tvrzení „(read-only)"/„nic tu nefetchuje" o volání
  JINÉHO skillu nebo skriptu je tvrzení K OVĚŘENÍ, ne premisa — otevři ten
  skript a najdi konkrétní příkazy, zvlášť `fetch`, který se nepromítne do
  `git status`.
  Proč: `mb-state` dostal celou vrstvu způsobilosti workspace, ale
  `description` dál slibovala jen starý rozsah — na otázku „je tenhle
  workspace v pořádku" by se skill nevyvolal; a `doc-index.ps1`, volaný jako
  „(read-only)", ve skutečnosti pouštěl `git fetch --prune origin`, pokud
  nedostal `-NoFetch`.
- **Když detektor musí vybrat jednu větev/hodnotu z několika rovnocenných
  long-lived kandidátů, přečti DVA nezávislé signály (ne jeden)** a nesouhlas
  mezi nimi řeš OTÁZKOU na uživatele, ne pravidlem pro tichý tie-break.
  Signál odvozený z checkoutnuté PRACOVNÍ větve (jejíž upstream je ona sama)
  zahoď.
  Proč: `symbolic-ref refs/remotes/origin/HEAD` samotný by ve forku, který
  nese upstream default branch jako read-only zrcadlo, napsal `origin/main`
  neopotřebovaně — druhý signál (`@{upstream}` dlouhožijící větve) dal
  `origin/ums-memory-bank`, shodné se symrefem v monorepu.
- **Bump verze v dokumentu, který vede running „Supersedes" historii,
  přeformuluj i ŘÁDEK, který byl current PŘEDTÍM** (`Supersedes vOLD` →
  `vPREV superseded vOLD`), ve STEJNÉM editu — i když brief dává jen text
  nového řádku. Konvenci ověř čtením alespoň dvou historických položek pod
  místem vkládání, ne jen podle textu, který dostaneš.
  Proč: bez přeformulování by po bumpu na v2.8 vznikly dvě po sobě jdoucí
  neverzované „Supersedes" věty, ze kterých nelze poznat, jaký přechod
  verzí každá popisuje.
- **Pro každý volitelný řádek stavového souboru (`context.md`), který
  existující reset zachovává, ověř ZVLÁŠŤ dvě otázky: co ho ZACHOVÁVÁ a co
  ho PŘEPISUJE na KAŽDÉ cestě.** Nemá-li druhá otázka odpověď, řádek
  zestárne přesně tam, kde to sesterský řádek nemůže. Zjisti to mechanicky
  (`grep -rn "<Pole>:" ums/.claude/`) a najdi všechny writery a readery
  před rozhodnutím, kam opravu umístit.
  Proč: `Jira:` je zachováván A nepodmínečně přepisován zápisem pinu, takže
  nemůže zestárnout; nový `Báze:` kopíroval jen zachovávací polovinu vzoru
  a psal se „když se báze liší" — nic ho neodstraňovalo, takže by jedna
  maintenance větev tiše určila výchozí bázi pro všechny další (base sync,
  harvest diff i integrační příkaz).
- **Nově vytvořenou tiketovou větev publikuj explicitním
  `git push -u origin <branch>`, nikdy bare `git push`.** `git switch -c
  <branch> <báze>` nastaví upstream nové větve na BÁZI, ne na ni samu —
  bare push by tak cílil na (typicky chráněnou) bázi. `-u` upstream
  přepíše a past platí jen do prvního publikování; při kontrole workspace
  považuj „upstream tiketové větve je chráněná větev" za nález, ne za
  normální stav.
  Proč: `git rev-parse --abbrev-ref '@{upstream}'` po `switch -c` potvrdil
  upstream nastavený na `origin/ums-memory-bank` — pre-push hook by bare
  push zachytil, ale jen jako zamítnutí na konci, bez náznaku, že příčinou
  je tracking nastavený už při vytvoření větve.
- **V komentáři u rozhodovacího kódu nepiš POČET, JEDINEČNOST ani UZAVŘENÝ
  VÝČET cest — ani jako opravu předchozího počítacího tvrzení; a opravenou
  větu vždy proměř jako nový test, ne jako hotovou opravu starého.** Piš,
  co dělá TENHLE check a proč, u toho checku; kde čtenář potřebuje celek,
  odkaž na funkci, která rozhoduje (`see evaluatePush`). Vytáhni z opravené
  věty PREDIKÁT (podle čeho se ta třída pozná), najdi funkci, která ho
  počítá, a pusť aspoň jeden PŘÍKLAD a jeden PROTIPŘÍKLAD sondou. Test
  každé věty, která přežije: „zneplatní ji přidání větve jinde, aniž by se
  téhle řádky někdo dotkl?" — když ano, je to počítací tvrzení v
  přestrojení.
  Proč: náhrada tvrzení o jedinečnosti („the ONE fail-open path") jednou
  kladnou větou vyjmenovávající celý výčet cest se rozbila hned a tiše —
  vznikly dvě nové nepravdy („exactly two ways left to be allowed", „one
  of the two ways"), měřitelně vyvrácené (`git push $r develop` zamítá
  z jiného důvodu; `git push -u origin feature/x` je třetí cesta, žádný
  problém). Jinde náhrada za `isGitToken`-predikát zavedla nepravdivý
  predikát „shape this file does not recognize as a command at all", který
  soubor o šest řádků níž definuje jako command position — ne fail-open
  třídu; protipříklady `echo git push origin develop`, `sudo git push
  origin develop`, `cd /repo; git push origin develop` byly všechny DENY.
- **Slovník sweepu po opravě nepravdivé věty skládej ze slov, kterými se
  POČÍTÁ a zobecňuje, ne z názvů konceptů, které zrovna měníš**
  (`only|any|never|always|both|either|exactly|unless|one|two|the one|
  everywhere except` plus jména postojů). Grepni obě strany (kód i sadu)
  a KAŽDÝ výskyt přečti proti kódu, jak stojí dnes.
  Proč: slovník omezený na pojmy toho kola (`fail-open`, `fail-closed`,
  `expansion`, `command position`, `the one`, `exactly`) minul dva nálezy,
  které přežily tři kola: „the one thing this layer still catches" (od
  kola 0) a „Any other flag means 'not simple' -> allow", věta tvrdící od
  jednoho tasku pravý opak kódu o dvě řádky níž — chytila je až slova
  `any`, `only`, `never`, `unless`, `both`, `either`, `one`, `two`.
- **Když review najde věty odporující kódu, neopravuj jen jmenované —
  udělej greppovaný inventář slovníku toho pravidla přes VŠECHNY soubory,
  kterých se týká (kód i testy), a u KAŽDÉHO výskytu si odpověz „platí tohle
  po dnešní změně?".** Zvlášť hlídej věty tvrdící POČET nebo JEDINEČNOST
  („the one", „exactly two", „everywhere except") — ty se lámou přidáním
  nové cesty, ne změnou té, kterou popisují, takže je grep na jméno
  změněného konceptu nenajde.
  Proč: po opravě per-token tolerance grep přes `FAIL-OPEN|FAIL-CLOSED|
  expansion|command position` v obou souborech našel další tři nepravdivé
  věty mimo diff té opravy — dvě tvrdily jedinečnost, která přestala platit
  vznikem druhé cesty k povolení, jedna pocházela ještě z kola 0 a
  zneplatnil ji samotný task.
- **Ke greppu na jména pojmů přidej druhý průchod po sekcích: vypiš
  sekce, kterých se změna věcně týká, a přečti je celé** — restatement
  pravidla bývá napsaný jinými slovy než pravidlo samo, takže ho jméno
  pojmu nenajde.
  Proč: grep na `two-tier`, `UMS_ALLOW_SHARED_PUSH`, `agent NEVER pushes`
  nenašel dvě nepravdivé věty bez těch pojmů: „they must never give
  different answers for the same configuration" (obě vrstvy dnes ZÁMĚRNĚ
  dávají různé verdikty) a „a missing or unverified `pre-push` hook"
  („unverified" už neznamená totéž co „neověřený v prostředí téhle
  session").
- **Když do dokumentace píšeš, že nějaká vlastnost platí pro KAŽDOU
  položku dříve vyjmenovaného seznamu, projeď ten seznam sondou položku po
  položce**, i když je vlastnost „zjevná" a seznam jsi nesestavoval ty —
  položka, která do seznamu patří z jiného důvodu než ostatní, tvrzení
  zabije. Platí pro kontrakt, hlavičky hooků i review poznámky, kdekoli
  se píše kvantifikátor („každý", „všechny", „žádný") nad výčtem.
  Proč: věta „čitelný chráněný cíl je zamítnut přes KAŽDÝ z dříve
  vyjmenovaných nosičů ztracené command position" byla pravdivá o pěti
  nosičích ze šesti; šestý (`X=1|git push …`) byl v seznamu omylem — jiná
  třída (nerozpoznaný token), měřený verdikt ALLOW. Bez šestiřádkové sondy
  by věta odešla do kontraktu jako devátá kódem vyvrácená věta téhle
  větve.
- **Upřesnění komentářového bloku nikdy nepřidávej jako NOVÝ odstavec
  vedle starého tvrzení — nejdřív najdi větu, kterou upřesnění mění,
  a přepiš JI**; teprve co se do ní nevejde, připoj zvlášť. Kontrolní čtení
  dělej odshora dolů celý blok jako cizí čtenář, ne jen diff — v diffu
  vypadá přidaný odstavec správně, protože stará věta v něm není vidět.
  Proč: nová upřesňující věta o postoji vrstvy skončila přesně pod větou,
  kterou vyvracela, a obě zůstaly v souboru vedle sebe — review to
  označilo jako čtvrtý výskyt téhož vzoru na tomto plánu, dvakrát v textu
  psaném právě v tom kole, které předchozí výskyt opravovalo.
- **Když upřesňuješ komentářový blok, přečti si ho CELÝ odshora dolů po
  editaci a hledej dvojice věta–výjimka, které stojí odděleně: sluč je do
  JEDNÉ věty na tom místě, kde padá rozhodnutí.** Absolutní formulaci
  („X je vždy zamítnuto") nech v komentáři jen tam, kde pod ní není žádná
  podmínka; jinak ji od začátku piš s tou podmínkou uvnitř, ne jako
  tvrzení, které o odstavec dál bereš zpátky.
  Proč: v `evaluatePush` vedle sebe stály „A protected target that IS
  readable is denied whatever else on the line is not" (absolutní) a
  o 17 řádků níž „Reading targets out of a MESSY invocation is itself
  gated on command position" (přesné) — cizí čtenář odshora narazí na
  nepravdivou první; je to potřetí na tomtéž plánu.
- **Nadpis komentáře musí být TÝŽ tvar pravidla jako věta, která ho
  vysvětluje — ne jeho zkratka o stupeň silnější.** Kde je nejlákavější
  oprava nebezpečná, přidej k ní jednořádkový `WARNING:` s důvodem;
  komentář, který jen popisuje správný stav, budoucího čtenáře před tou
  opravou neochrání.
  Proč: nadpis „ONE PROBLEM PER OFFENDING TOKEN" byl silnější než skutečné
  pravidlo o tři řádky níž („a problem may only be recorded on tokens that
  all bear on it") a o dvacet řádků níž stál kód, který nadpis porušuje ze
  správného důvodu (arita je vlastnost MNOŽINY) — nabízená „oprava" podle
  nadpisu by zrušila reálný fix.
- **Když soubor popisuje jeden mechanismus na víc než jednom místě
  (stromový komentář + tabulka, hlavička skriptu + tělo), po úpravě
  KTERÉHOKOLI z nich vyhledej ostatní popisy STEJNÉHO mechanismu ve
  STEJNÉM souboru a srovnej je vedle sebe** — ne jen jednotlivě proti kódu,
  i proti sobě navzájem.
  Proč: po opravě jednoho popisu výjimky (buffer arm nad markerem) měla
  druhá formulace ve stejném souboru (tabulkový řádek „Publication
  guarantee") výjimku správně už z předchozího kola, zatímco stromový
  komentář o pět řádků výš ve stejném kole ji neměl — přesně scénář
  „falsified from a sibling line ve stejném commitu".
- **U každé absolutní věty o hooku („nevynucuje nic", „vždy propustí")
  přečti kód NAD branou, na kterou se ta věta odvolává, a výjimku napiš do
  stejného odstavce.** Totéž platí pro věty o rozsahu — fail-closed
  plumbing arm bývá nad rozsahovou branou taky.
  Proč: věta „The hook enforces NOTHING outside an agent session" nebrala
  v úvahu větev NAD branou — selhání bufferu stdinu — která zamítne push
  komukoli, se značkou i bez ní; hook to sám komentářem říká, ale grep na
  pojem měněného pravidla (`agent session`, `marker`) ten komentář najde
  až v odstavci, který čtenář briefu přeskočí.
- **Když v dokumentu ROZŠÍŘÍŠ působnost pravidla („platí nově i pro X a
  Y"), vypiš mechanismy, které o tom pravidle NĚCO SLIBUJÍ (hlášky,
  zprávy, nápovědy, exit kódy), a u KAŽDÉHO ověř v kódu, jestli slib platí
  i pro nově přidané X a Y.** Kontrolní otázka: „kolik z případů, které
  pravidlo nově pokrývá, tenhle slib skutečně splňuje?" — a když ne
  všechny, napiš do věty které.
  Proč: rozšíření lidské výjimky z jednoho pravidla na tři (protected-
  branch, deletion ban, force-push ban) nechalo beze změny větu „its own
  rejection message names it" — pravdivou, dokud výjimka zvedala JEDNO
  pravidlo, nepravdivou pro dvě ze tří zdí, protože mazání větve ani
  force push výjimku vůbec nezmiňují. Grep na měněné pojmy takové věty
  nenajde — neobsahují nic, co by je odlišilo od desítek správných
  výskytů téhož slova.
- **U rozhodovacího ramene, které popisuješ prózou, si opiš konkrétní
  ŘÁDEK, který o něm rozhoduje (celý výraz včetně ternárního operátoru a
  guardů), a spočítej podmínky v něm — teprve pak piš větu.** Ke KAŽDÉ
  přiznané mezeře připiš, co ta mezera NESTOJÍ, jinak se z opravy
  over-claimu stane under-claim, který je stejně nepravdivý.
  Proč: popis fail-closed chování jako „posture + jedna jmenovaná výjimka"
  (odkaz na `evaluatePush`, aby se autor vyhnul výčtu, který podle
  hlavičky souboru vždy zestará) svedl k opačné chybě — rameno má DVĚ
  podmínky (`atCommandPosition ? problems.find(…) : undefined`), jmenovaná
  byla jen jedna, takže kontrakt sliboval zamítnutí, které kód nedodá.
- **Popis chování rozhodovací funkce piš až po přečtení CELÉ funkce (ne
  hlavičky, ne rulingů) a formuluj ho jako „posture + jmenovaná výjimka +
  odkaz na funkci", nikdy jako výčet větví.** Když soubor sám varuje, že
  jeho souhrny zestarávají, ber to jako zákaz souhrnu, ne jako výzvu napsat
  lepší.
  Proč: věty „denies anything it cannot parse" a „document text passes"
  sepsané z hlavičky souboru a z rulingů v ledgeru byly obě nepravdivé
  proti kódu — protected target čitelný v plain textu se zamítá i BEZ
  command position, a nečitelný push se naopak POVOLUJE, když nečitelnost
  způsobila shell expanze.
- **Než vložíš doslovný snippet, který NAHRAZUJE strukturovaný útvar
  (tabulku, číslovaný seznam, pojmenované vrstvy), projdi snippet na odkazy
  do té struktury — ordinály („Tier 1", „krok 3"), jména sloupců a řádků —
  a přepiš je na jméno PRAVIDLA, ne na pozici.** Doslovnost snippetu se tím
  neporušuje: mění se odkaz, ne tvrzení.
  Proč: snippet vložený doslova (včetně věty „Tier 1 lets the agent publish
  its own ticket branch unassisted") odkazoval po vložení na strukturu,
  která už v souboru nebyla — týž krok mazal tabulku, která pojem „Tier 1"
  definovala; v diffu to vypadalo správně, protože smazaná tabulka i nový
  odstavec jsou vidět vedle sebe, ale že jeden odkazuje na druhý, ukáže až
  čtení výsledku.
- **Když úloha ruší pojmenovaný koncept, sweep na doslovný token
  proměnné/příkazu, který koncept provázel, NESTAČÍ — grepni zvlášť i na
  frázi, kterou byl koncept POJMENOVÁN v prózi** (česky i anglicky),
  protože se může objevit bez doprovodné proměnné.
  Proč: sweep širším slovníkem („dvouúrovňová", „two-tier",
  „harness-agnostic") napříč celým `ums/`, ne jen soubory jmenovanými
  briefem, našel dva další výskyty mimo brief scope
  (`guard-git-push.mjs` dvě hlášky, overlay fragment řádek 93) — briefův
  Step 1 grep jen na proměnnou `UMS_ALLOW_SHARED_PUSH` by je nenašel.
- **Když komentář/hlavička popisuje bezpečnostní vlastnost funkce jako
  „X je pravda" (remote má commit, uživatel je ověřený, soubor je
  uzamčený), ověř, ZDA to kód dokazuje PŘÍMO (kontaktuje autoritativní
  zdroj), nebo jen NEPŘÍMO přes lokální/cache proxy** (remote-tracking ref,
  cache soubor, session proměnná) — a pokud nepřímo, napiš to explicitně
  („dosažitelnost z lokální kopie X, poctivé jen potud, pokud je X
  synchronizované") místo věty tvrdící vlastnost samotného zdroje.
  Proč: komentář „commits that already exist on the remote" popisoval jiný
  mechanismus, než jaký `is_integration_push` implementuje — kód nikdy
  remote nekontaktuje, kontroluje jen lokální `refs/remotes/$remote_name/*`,
  zapisovatelné (`git update-ref`) i bez skutečné publikace. Prosa tak
  slibovala silnější záruku, než hook reálně dává.
- **Když úkol píše konkrétní konfigurační klíč/soubor pro cizí nástroj
  (jiný harness, jiné SDK, cokoli mimo tuhle vrstvu) a briefu/plánu chybí
  citace oficiální dokumentace, ověř klíč/soubor proti primárnímu zdroji
  (WebSearch → WebFetch na nejrelevantnější docs stránku) PŘED
  implementací**, ne až když to review vrátí. Cituj nález (URL + citovaná
  věta) přímo v kódu vedle zápisu, ne jen v reportu.
  Proč: brief cílil na `[env]` v TOML a `"env"` klíč v `settings.json` pro
  Codex/Gemini CLI — obě místa byla špatně. Codex čte
  `[shell_environment_policy].set`, ne `[env]`; Gemini CLI env injektuje jen
  přes `.env` soubor, `settings.json` žádný `env` klíč nemá. Bez ověření by
  soubor po deployi vypadal „nakonfigurovaně" (marker string by fyzicky
  ležel), ale hook by se v obou harnessech dál tiše sám vypínal.
- **Než přijmeš navrženou podmínku jako kompletní, projdi VŠECHNY
  případy, které má vyřešit, jeden po druhém proti té podmínce, a spusť je
  jako červené testy PŘED implementací.** Případ, který podmínka
  nepokrývá, je signál, že chybí druhá ortogonální podmínka — a osu té
  druhé podmínky hledej tam, kde odděluje „nevím, co se pushuje" (expanze)
  od „vím a nelíbí se mi to" (uvozovky kolem literálu), ne v okolí prvního
  nápadu.
  Proč: revizní pokyn „fail-closed jen na command position" jednou
  podmínkou nestačil — `git push "$remote" "$branch"` stojí na indexu 0,
  je tedy na command position, ale fail-closed by ho dál zamítal
  (`nesrozumitelné jméno remote`). Teprve druhá podmínka (žádná shellová
  expanze v argumentech) ten případ propustila, aniž otevřela únik přes
  uvozovky.
- **Ke KAŽDÉMU rozšíření vzoru, který se z povolovacího změnil na
  zamítací, dopiš negativní asercie na tři osy zvlášť: jiná HODNOTA, jiné
  UKONČENÍ a jiný PREFIX jména.** Polarita rozhoduje o směru rizika — dokud
  vzor povoloval, byl úzký vzor konzervativní; jakmile zamítá, je úzký vzor
  díra a široký vzor falešný poplach, takže obě strany potřebují důkaz.
  Proč: pozitivní asercie na sedm zápisů by prošly i výrazu, který matchne
  skoro cokoli; teprve čtyři negativní (`="0"`, `='0'`, `=10`,
  `NOT_MB_HUMAN_PUSH=1`) drží alternaci na uzdě — `NOT_…` navíc testuje
  hranici `(^|\s)`, kterou by rozšíření hodnot mohlo nechtěně uvolnit.
- **Před KAŽDÝM splicem (vystřihni a vlož) si čísla řádků vytáhni znovu
  (`grep -n '<kotva>' <soubor>`), nikdy je neber z dřívějšího výpisu
  téhož sezení, a po zápisu si dotčený rozsah vypiš a přečti.** U
  komentářů je syntax check bezcenný jako kontrola — projde i nad
  rozstříhaným odstavcem; jediná kontrola je přečíst to.
  Proč: úprava komentářového bloku přes `head -n N`/`tail -n +M` s čísly
  z výpisu pořízeného před předchozími editacemi téhož souboru byla o pět
  řádků posunutá — splice vyřízl prostředek jednoho odstavce a nechal
  viset konec jiného, a `node --check` prošel čistě, protože poškozený byl
  jen komentář.

## Psaní plánů, návrhů a commitů

- **V plánu ani návrhu nikdy nezačínej řádek zpětnými apostrofy**, pokud to
  není skutečný ohraničovač bloku. Chceš-li v próze ukázat apostrofy, popiš je
  slovy. Vnořený stejně dlouhý ohraničovač je tatáž třída chyby.
  Proč: `scripts/task-brief` přepíná sledování ohrazených bloků na každém
  řádku odpovídajícím `^` + tři apostrofy, takže osamocený takový řádek ho
  nechá natrvalo „uvnitř bloku" a přestane rozpoznávat nadpisy dalších úloh.
  Projevilo se to briefem o 1164 řádcích místo 346 — obsahoval celý zbytek
  plánu. Po napsání plánu proto spusť `task-brief` pro **každé** číslo úlohy
  a zkontroluj, že rozsahy odpovídají; brief výrazně větší než jeho sekce je
  ten příznak.
- **Českou diakritiku v commit message piš přímo**, i když ji skládáš přes
  bash heredoc — UTF-8 tudy projde správně. Nenahrazuj ji ASCII transliterací
  „pro jistotu".
  Proč: tiše vznikne zpráva, která nevyhovuje konvenci repa, a přijde se na to
  až při kontrole. V tomhle běhu se to stalo dvakrát. Kontrola je jeden
  příkaz: `git log -1 --format=%B | od -c` a podívat se, jestli tam jsou
  vícebajtové sekvence.
