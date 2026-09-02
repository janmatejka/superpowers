# Návrh: Mechanika poolu — spuštění sezení na tiket do slotu

- **Jira:** UMS-3488 (https://datasyscz.atlassian.net/browse/UMS-3488)
- **Target MB:** memory-bank/
- **Vytvořeno:** 2026-09-02
- **Oponentura:** dvě agentické, 2026-09-02 — první 29 nálezů (defekty artefaktu), druhá 10 výzev tvaru řešení; výsledkem je rozkrájení práce na tři tikety a tento návrh je prostřední z nich

## Cíl

Rozpracování epiku (`mb-epic-elaboration`) dnes končí tím, že v
`proposals/next/` leží předběžné návrhy budoucích tiketů. Odtud dál je ruční
práce: operátor otevře workspace, přepne větev, přečte, co se má dělat, a
nadiktuje sezení zadání. Cíl tohoto tiketu je **zautomatizovat tu mechaniku
— a jen ji.**

Mechanika je zaplacená. 2. 9. 2026 proběhlo pět pokusů rozjet sezení ručně;
**tři selhaly, každý z jiné příčiny, a všechny tři vypadaly jako úspěch** —
u dvou to bylo ohlášeno jako hotové a u jednoho zapsáno do Jiry, přestože na
tiketu nikdo nepracoval. Všechna tři selhání byla **mechanická**: viselý
`cmd /k`, zděděná značka dětského sezení, a rozpadlý seznam argumentů. To je
ta část, která má cenu být kódem.

**Rozhodovací část — „který tiket je bezpečné rozjet" — do tohoto tiketu
záměrně nepatří.** Běžela jednou, ručně, a byla šestkrát ze šesti správně.
Automatizovat na jednom datovém bodu polovinu, která nikdy neselhala, dřív
než polovinu, která selhala třikrát z pěti, je pozpátku; UMS-3488 to sám
doporučuje odložit o dvě až tři rozjetí. Návrh té části leží jako předběžný v
[`../next/design_pool_brana_pripravenosti.md`](../next/design_pool_brana_pripravenosti.md).

Druhý, menší cíl: **dokončit session baton** dvěma amendmenty ze sklizené
položky `baton_rotace_kontextu`. Ty s poolem nesouvisejí — jsou to nezávislé
opravy, které jen leží ve stejném souboru.

## Scope

**V rozsahu:**

- **A2** — `Instruction` se stává povinným a validovaným klíčem batonu, včetně
  opravy overlay fragmentu, který ho ve svém výčtu nejmenuje.
- **A1** — čtenář batonu emituje `initialUserMessage` vedle
  `additionalContext`, takže `/clear` ve vlastním workspace přestane čekat na
  stisk klávesy.
- Tři skripty vrstvy: `pool-status.ps1`, `pool-launch.ps1`,
  `pool-provision.ps1`.
- Nový skill `mb-epic-run` se čtyřmi operacemi: `status`, `ready`, `spawn`,
  `attach`.
- Zápis **záměru jedním řádkem do commitnutého ledgeru** epiku (model tahu).
- Přesun opravy pasti s upstreamem na chráněnou bázi do overlaye
  `brainstorming` — chrání každé sezení, ne jen spawnuté.
- Změny kontraktu na verzi 2.13 a integrace do `mb-epic-elaboration`.

**Mimo rozsah, ve vlastních tiketech:**

- **Cílený sken v `doc-index.ps1`** a ohlášení chybějícího výstupního
  adresáře. **Není to o poolu** — je to živý defekt nasazené vrstvy, kvůli
  kterému dnes na monorepu každá vstupní brána běží s fail-closed kontrolou,
  která nedoběhne. Návrh:
  [`../next/design_doc_index_cileny_sken.md`](../next/design_doc_index_cileny_sken.md).
- **Brána připravenosti a klasifikace tiketů**, `-Json` pro `epic-graph.ps1` a
  `ledger-status.ps1`, případný generovaný briefing. Návrh:
  [`../next/design_pool_brana_pripravenosti.md`](../next/design_pool_brana_pripravenosti.md).

**Mimo rozsah úplně** (a proč):

- **Žádná evidence slotů** — žádný registr, žádné lock soubory, žádný démon.
  Stav slotu je derivovaný při každém dotazu.
- **Žádný nový druh batonu.** `Kind: ticket-start` se nestaví; záměr do slotu
  doručuje argv (sekce 3).
- **Orchestrátor nikdy neukončuje sezení tiketu** a **nezapisuje do
  pracovního stromu slotu vůbec nic**. Tiket končí harvestem, parkem nebo
  abortem, které provede agent tiketu na své větvi.
- **Žádné agentem vytvářené worktrees.** `pool-provision.ps1` je nástroj
  operátora vynucený guardem ve skriptu plus `permissions.deny`.
- **Žádné agent teams a žádné `isolation: worktree` subagenty** pro práci na
  tiketu.
- **Žádné zápisy do Jiry z `mb-epic-run`.**
- **Adaptéry `vscode`, `deeplink` a `bg`** se nestaví — prokázané jsou dva.

## Technický návrh

### 1. Slot poolu jako workspace kontraktu

Slot je **linked git worktree**, který zakládá uživatel, žije napříč mnoha
tikety, hostí nejvýš jedno sezení a nese jednu tiketovou větev a jeden pin v
`context.md`. Kontrakt na něj hledí jako na **nalezený workspace** —
Workspace Discipline, vstupní brána, `mb-park`/`mb-harvest`/`mb-abort`,
Publication Contract a meziclonová kolizní kontrola na něj platí. **S jednou
výjimkou, kterou je nutné pojmenovat, protože kontrakt ji nepředvídal:
derivace „volný workspace" je napsaná pro jeden klon na jeden `.git` a v
poolu se sdíleným `.git` neplatí, jak je** — viz sekce 2.

Worktree Policy dostává **právě jednu výjimku**: slot poolu, který
provisionoval uživatel. Agentem vytvořené worktrees zůstávají zakázané.

**Sdílený `.git` je to, co drží publikační záruku.** Změřeno v monorepu: z
každého ze čtyř slotů vrací `git rev-parse --git-path hooks/pre-push` cestu
`D:/_datasys/ums/.git/hooks/pre-push`, tedy tentýž soubor. Jedna instalace
`install-git-hooks.ps1` proto pokrývá všechny sloty a fail-closed kontrola
vstupní brány funguje v každém slotu bez další instalace.

Dvě pasti té kontroly:

- **Tvar cesty se liší podle toho, odkud se ptáš.** Ze slotu vrací
  `--git-path` absolutní cestu, z **primary** worktree relativní
  `.git/hooks/pre-push`. Srovnání na identitu napříč poolem proto potřebuje
  normalizaci na absolutní cestu; prosté srovnání řetězců selže, jakmile se
  orchestrátor ptá z hlavního klonu.
- **`core.hooksPath` s relativní hodnotou** se resolvuje per-worktree, takže
  v tom případě potřebuje každý slot vlastní běh instalátoru.

### 2. Derivovaný stav slotu

**Členství v poolu je derivované, ne konfigurované — ale s vědomým
souhlasem.** Kandidáty vypíše jedno čtení `git worktree list --porcelain`
(linked, ne-primary, ne ten, ve kterém stojí orchestrátor); slotem je z nich
ten, který nese **marker** `.superpowers/pool-slot`. Žádná centrální
konfigurace nevzniká: marker je vlastnost toho worktree, ne záznam někde
jinde, a zakládá ho `pool-provision.ps1`.

Marker existuje kvůli konkrétnímu destruktivnímu scénáři: worktree držený
záměrně čistý na release větvi, s IDLE `context.md` a bez nepushnutých
commitů, **splňuje každou podmínku volnosti**. Jediná větevní podmínka je
„nedrží tiketovou větev tohoto epiku", což release větev není. Spawn by v něm
provedl `git switch -c <TIKET>-<slug>` — krok, který předepisuje overlay
`brainstorming` — a operátor by přišel o vyzvednutý stav. Obnovitelné, ale je
to „workspace se bere jako nalezený" rozbité vlastním nástrojem vrstvy.
Existující čtyři sloty dostanou marker jedním operátorským příkazem.

Repozitář bez označeného worktree nemá pool a `mb-epic-run` fail-closed
odmítne českou hláškou, která to říká — což je stav **tohoto forku** (nula
linked worktrees), takže ta cesta má vlastní test.

Porcelain záznam nese víc než cestu a větev a derivace to musí unést:
`bare` worktree se přeskočí, `locked` a `prunable` se **nepočítají za
kandidáta** a hlásí se s pojmenovaným důvodem — u `prunable` (adresář je
pryč, záznam zůstal) by `git -C <cesta> status` vůbec nešlo spustit.

**Volnost slotu se derivuje jen ze signálů, které jsou per-worktree.** Toto
je nejtvrdší korekce první oponentury a je měřená: v linked worktree jsou
per-worktree pouze `HEAD` a `index`; `refs/stash` i `refs/heads` jsou
**sdílené** (`git -C <slot> rev-parse --git-path refs/stash` vrací z ums01 i
z ums02 týž soubor `D:/_datasys/ums/.git/refs/stash`). Kontraktová trojice
`status` + `stash list` + `log --branches --not --remotes` proto v poolu
nefunguje: `git stash list` vrátí ze všech slotů totéž, a `--branches` je
repo-wide už konstrukcí, takže **jeden nepushnutý commit kdekoli v repu by
udělal každý slot navždy nevolným.**

| Signál | Zdroj | Rozsah |
|---|---|---|
| špinavý strom | `git -C <slot> status --porcelain` | per-worktree ✔ |
| nepushnuté commity **tohoto slotu** | `git -C <slot> log '@{upstream}..HEAD'`, bez upstreamu `git -C <slot> log HEAD --not --remotes` | per-worktree ✔ |
| větev, nebo detached | `git worktree list --porcelain` | per-worktree ✔ |
| pin | `<slot>/memory-bank/context.md` | per-worktree ✔ |
| postup v plánu | `<slot>/.superpowers/sdd/plan_<slug>/progress.md` **toho slugu, který nese pin** | per-worktree ✔ |
| **živé sezení** | `claude agents --json --cwd <slot>`, záznamy s přítomným `pid` | per-worktree ✔ |
| stash | `git stash list` | **repo-wide ✘ — nelze přiřadit slotu** |
| kandidát playbooku | `<slot>/.superpowers/playbook-candidates/<slug>.md` | per-worktree, ale **jen když slot nese pin** |

**Obsazenost slotu čte harness, ne git.** `claude agents --json` je
zdokumentované, nepotřebuje TTY, umí `--cwd` filtr a vypisuje **i
interaktivní** sezení. Změřeno 2. 9. 2026: vrátil `ums01` (idle, pid 29404),
`ums02` (busy, pid 36244), `ums03` (waiting, pid 30856) a hlavní klon (busy,
pid 32904); `ums04` v seznamu nebyl, protože v něm sezení neběželo.
`--cwd <slot>` vrátil právě ten jeden záznam. Filtrovat se musí na
**přítomný `pid`** — záznamy bez něj jsou ukončená background sezení.

Bez tohoto signálu má derivace **díru, kterou git zavřít neumí**: slot s
čistým stromem a IDLE pinem, ve kterém právě naběhlo sezení, je „volný" po
celou dobu, než to sezení dojde k zápisu pinu — a to je vstupní brána s
`git fetch` a kolizním skenem, tedy řádově minuta. Spawn by do něj poslal
druhé sezení, což „jedno sezení na workspace" zakazuje. **Živé sezení ve
slotu je proto tvrdý důvod slot nepoužít.** PID soubory pod
`~/.claude/sessions/` se dál nečtou — to je nezdokumentované rozhraní; tenhle
signál je něco jiného, dokumentované CLI.

**Volný slot** je proto: nese marker, čistý strom, IDLE pin, **žádné živé
sezení**, žádné nepushnuté commity na vlastním HEAD či vlastní větvi, a
nedrží tiketovou větev tohoto epiku.

Dva signály z volnosti záměrně vypadly:

- **Stash se slotu přiřadit nedá.** Hlásí se jednou za repozitář jako
  informace, nikdy jako vlastnost slotu.
- **Kandidát playbooku je definovaný jen vůči AKTUÁLNÍMU slugu.** IDLE slot
  žádný aktuální slug nemá, takže každý kandidát v něm je cizí — a cizí
  kandidát kontrakt výslovně jmenuje jako „merely present", který se jen
  ohlašuje a agent se ho nedotýká. Kdyby byl součástí volnosti, byl by slot
  navždy nepoužitelný bez definované nápravy: smazat ho smí jen harvest toho
  slugu, a ten slug je dokončený. Měřeno živě: ums02 nese
  `playbook-candidates/skodasms_241_gated_cesta.md` (14 670 B).

Slot s **neobnovitelnými zbytky** volný není a orchestrátor ho **neuklízí**
— ohlásí ho a rozhodnutí nechá uživateli v tom slotu, kde zbytky leží.

**Ledger se páruje na slug z pinu, nikdy na „první nalezený adresář pod
`sdd/`".** Měřeno: slot `ums03` nese pin na `skodasms_251_regexovy_pool_bota`
a v `.superpowers/sdd/` má **oba** adresáře —
`plan_skodasms_239_knihovna_chytrolinconnect` (zbytek po předchozí práci) i
`plan_skodasms_251_regexovy_pool_bota` (ten správný). Derivace „první
nalezený" by vzala 239, protože se řadí dřív, a ohlásila cizí postup jako
postup tohoto tiketu.

**Idle slot je detached, nebo stojí na větvi, jejíž jméno se rovná jménu
adresáře slotu** — ale ta druhá varianta **není** důkazem, že slot je idle.
Měřeno: `ums04` stojí na větvi `ums04`, má čistý strom a přitom nese
**ACTIVE pin** (`ums_3485_vyhodnoceni_a_zobrazeni_stavu`). Skutečná konvence
poolu tedy je „vlastní větev slot **zaparkuje**, zatímco pin trvá" — tedy
`mb-park` —, ne „vlastní větev znamená idle". Jméno větve proto **nikdy
nerozhoduje o IDLE**; o tom rozhoduje výhradně pin. Tvar se přijímá kvůli
něčemu jinému: je to pojmenované místo, kam slot přepnout, když je potřeba
uvolnit větev vyzvednutou jinde.

### 3. Doručení záměru: argv a řádek v ledgeru

**Prompt jde na příkazovou řádku jako jeden zauvozovkovaný argument.** To je
měřený tvar z 2. 9. 2026: pokus 3 předal `-ArgumentList $p` bez uvozovek,
řetězec se rozpadl na deset argumentů a sezení dostalo jako zadání jediné
slovo (na obrazovce to vypadalo jako vstup uživatele); pokus 4 s doslovnými
uvozovkami předal celý prompt včetně diakritiky a pomlčky, a pokus 5 totéž
přes `wt.exe`.

**Nový druh batonu se nestaví, a to je vědomý obrat proti prvnímu návrhu.**
Baton je *ambientní* kanál: `SessionStart` hook s matcherem `startup`
vystřelí v každém sezení, které v tom worktree kdokoli otevře. Argv je kanál
*cílený* — prompt dorazí do procesu, který jsi spustil, a do žádného jiného.
Všechna oprava, kterou by baton potřeboval — klíč `Slot` jako origin
binding, hlídka na čistý strom, hlídka na neexistující větev tiketu, hlídka
na IDLE pin, validace tvaru `Ticket` — je opravná práce za tu jedinou změnu
kanálu. A abstrakce „jedna cesta doručení, několik spouštěčů" nemá člena,
který by ji potřeboval: **oba** postavené launchery prompt nesou, a všechny
tři odložené taky.

**Dlouhé zadání do promptu nepatří.** Prompt je krátký a jednořádkový: co
dělat, který tiket, a **kde si přečíst zbytek**. Bez středníku, protože
`wt.exe` ho bere jako oddělovač vlastních příkazů.

**Zbytek se netlačí, ale tahá.** Orchestrátor zapíše **jeden řádek do
ledgeru epiku**, commitne ho a pushne na elaborační větvi; do pracovního
stromu slotu **nezapíše nic**. Řádek nese tiket, verdikt, cestu k draftu
(větev a cesta, protože draft může ležet na cizí větvi), zvolenou bázi a
krátký seznam pastí. Sezení ve slotu si pak rozsah, blokátory, špinavé řádky
i umístění draftu **najde samo** — všechno už je v commitnutých dokumentech a
`mb-doc-index` spouští vstupní brána tak jako tak.

Tři důvody, proč je tahová varianta lepší než generovaný briefing ve slotu:

1. **Sedí na model tahu, na kterém vrstva stojí.** Dokumenty se hledají, ne
   tlačí; draft se přebírá kopií blobu. Tažený artefakt si konzument vybral a
   umí ho načíst znovu; tlačený je jednorázový side effect bez idempotence.
2. **Odpadá otrávení slotu.** Neúspěšný launch (`unavailable`, chybějící
   `wt.exe`) by nechal ve slotu nezkonzumovaný baton a briefing — a
   orchestrátor si sám zakázal ve slotu uklízet. Slot by byl nevolný bez
   nápravy uvnitř modelu a železné pravidlo „STOP nechá slot přesně tak, jak
   ho našel" by bylo porušené ještě před voláním launcheru.
3. **Odpadá sanitizér.** Briefing ve slotu by musel projít uzavřením a
   re-renderem, aby nebyl injekční plochou — a to znamená zákaz lomených
   závorek, tedy briefing, který neumí odcitovat XML, BPMN ani C# generiku.
   V monorepu, jehož tikety jsou právě o tom, je to funkční ztráta. Vrstva
   navíc čte Jira popisy, cizí design bloby a ledgery **surové**, takže
   zpevnit jediný kanál na standard, který žádný jiný nesplňuje, kupuje málo.

**Past s upstreamem se opravuje u zdroje, ne v zadání.** Poznatky ji jmenují
jako druhou past přípravy: `git switch -c X origin/<báze>` nastaví tracking
na **chráněnou** bázi, takže pozdější push míří rovnou do integrační linie.
Ten příkaz ale předepisuje overlay `brainstorming` pro **každé** sezení, ne
jen pro spawnuté. Oprava proto patří tam (a do kontraktu): po založení větve
`git branch --unset-upstream`, první publikace `git push -u origin HEAD`.
Opsat to do zadání každého spawnu by chránilo jen spawnutá sezení a
opakovalo by to navždy.

### 4. Launcher a mechanické ověření spuštění

**Vyčištění zděděného prostředí je povinná součást spuštění.** Orchestrátor
je sám sezení Claude Code, takže potomek zdědí jeho proměnné a naběhne jako
**dětská session s vypnutým transcriptem, s identitou a messaging rourou
rodiče**. Změřeno 2. 9. 2026 (pokus 2). `pool-launch.ps1` proto před
spuštěním odebere ze svého shellu **devět** proměnných:

| Proměnná | Co působí, když zůstane |
|---|---|
| `CLAUDE_CODE_CHILD_SESSION` | sezení se hlásí jako dětské, vypne ukládání transcriptu |
| `CLAUDE_CODE_SESSION_ID` | potomek se tváří jako totéž sezení |
| `CLAUDE_CODE_BRIDGE_SESSION_ID` | totéž pro bridge |
| `CLAUDE_CODE_MESSAGING_SOCKET` | potomek by komunikoval rourou rodiče |
| `CLAUDE_CODE_MESSAGING_TOKEN` | totéž |
| `CLAUDE_CODE_SSE_PORT` | totéž |
| `CLAUDE_PID` | identita rodiče |
| `CLAUDE_CODE_ENTRYPOINT` | značka o vstupním bodu rodiče |
| `NO_COLOR` | sezení je černobílé; hodnotu nastavuje harness rodiče pod VS Code |

**`CLAUDECODE` se záměrně NEODEBÍRÁ**, i když ho poznatky ve svém seznamu
mají. Dva nezávislé důvody:

1. **Precondice zapisovatele batonu** je definovaná jako „harness, jehož
   session-start hooky tato vrstva konfiguruje (`CLAUDECODE` neprázdný), a
   registrovaný hook". Odebrání by v každém spawnutém sezení vyhodnotilo
   precondici jako nesplněnou, takže by sezení muselo **odmítnout napsat
   vlastní baton** — a tím by ztratilo třetí volbu exekuce i pátou stop
   třídu, tedy rotaci kontextu. Selhalo by to tiše.
2. **Na nasazení `-Scope UserProfile` je `CLAUDECODE=1` JEDINÝ nosič
   publikační záruky.** Ten scope záměrně nenasazuje `settings.json`, takže
   `MB_AGENT_SESSION` tam nedorazí a `pre-push` hook má ve své vstupní bráně
   jen fallback na neprázdný `AI_AGENT` nebo `CLAUDECODE=1`.

`CLAUDE_CODE_USE_POWERSHELL_TOOL` se nechává taky — to je nastavení
uživatele, ne stav sezení. Odebrání musí být ve **stejném volání** jako
spuštění: každé volání PowerShellového nástroje je čerstvý shell dědící od
rodiče.

Seznam proměnných je v těle skriptu, ne v `ums-repo.json` — je to vlastnost
harnessu, ne repozitáře. Poznatky ho jmenují vedle položek, které do
konfigurace opravdu patří (cesta ke `claude.exe`, adresář poolu, jména
větví), a tohle je proti nim vědomá odchylka.

Adaptéry — každý právě jeden příkaz, žádný skrytý fallback řetěz:

| Adaptér | Příkaz | Stav |
|---|---|---|
| `terminal` | `wt.exe -d <slot> <claude.exe> --name <TIKET> "<prompt>"` | prokázán 2. 9. (pokus 5) |
| `direct` | `Start-Process <claude.exe> -WorkingDirectory <slot>` s `--name` a zauvozovkovaným promptem | prokázán 2. 9. (pokus 4) |

Cesta ke `claude.exe` se nikdy nepíše natvrdo — táhne se z
`Get-Command claude`. Chybí-li `wt.exe` v PATH, `terminal` vrací stav
`unavailable`, volající to ohlásí a zastaví se; skript sám nikdy nerozhoduje,
který adaptér použít, a nikdy nespadne na jiný. Volba je argument skillu s
defaultem odvozeným sondou stanice.

**Mechanické ověření spuštění, ne tabulka procesů.** Ústřední lekce dne je,
že všechna tři selhání vypadala jako úspěch a že `Get-Process claude` vrátil
PID ve všech třech. Existence procesu proto důkaz není — ale **záznam v
session registru harnessu** je něco jiného: launcher předá
`--name <TIKET>` a orchestrátor po spuštění ověří, že
`claude agents --json --cwd <slot>` vrací záznam s přítomným `pid`, tímto
jménem a časem startu po okamžiku spawnu. Buď ohlásí „sezení potvrzeno", nebo
„**žádné nové sezení se neobjevilo — ověř na obrazovce**". Tím se dvě ze tří
měřených selhání (pokus 1: proces existoval, sezení nikdy nenaběhlo; pokus 3:
dorazil špatný obsah) stávají strojově detekovatelnými a operátorovy dvě
otázky zůstávají záložní kontrolou, ne jedinou kontrolou.

Operátorské otázky zůstávají: není ve status řádku `⚠ Transcript saving is
off` a je v prvním vstupu **celý** prompt. Do Jiry jde „běží" teprve po
prvním commitu na větvi tiketu.

**`pool-provision.ps1` je vynucený nástroj operátora, ne konvence.** Skript
**odmítne běh, když je v prostředí marker agentní relace**, dokud nedostane
explicitní operátorský přepínač; guard je ve skriptu, protože tak putuje s
vrstvou i na harnessy, kde `permissions.deny` neexistuje. Vedle toho jdou do
`permissions.deny` záznamy pro `git worktree` a pro samotný skript. Skript
dělá: `git fetch origin`, `git worktree add --detach <cesta> origin/<báze>`,
založí marker `.superpowers/pool-slot`, a pak **z vnitřku nového slotu**
ověří, že `git rev-parse --git-path hooks/pre-push` ukazuje na značkovaný
hook v2 — instaluje jen tehdy, když chybí nebo je starší. Rozpad velikosti
hlásí do konzole.

### 5. Amendmenty čtenáře batonu (A1, A2)

Obojí je **nezávislé na poolu** — s doručením přes argv už na nich spawn
nestojí. Zůstávají v tomto tiketu proto, že jsou malé, specifikované a leží
ve stejném souboru.

**A2 — `Instruction` je povinný a validovaný klíč.** Kontrakt říká „poslední
řádek je jediný `Instruction:`", hook ho ale vede jen v `$RenderOrder`.
Rozpor se řeší na straně kontraktu: `Instruction` přibude do `$Required`.
Navíc se validuje obsah — hodnota musí **obsahovat jméno některého
existujícího skillu** (odvozeno z adresářů skillů vedle hooku) a nepřesáhnout
krátký strop délky. Důvod je A1: baton je git-ignorovaný scratch, do kterého
rutinně zapisují implementátorské subagenty, a A1 z `Instruction` dělá
automaticky vykonaný první tah. Bez validace by se doručilo až osm kilobajtů
libovolného textu jako první uživatelský vstup.

**Zapisovatele to mění a oprava fragmentu patří do TÉHOŽ tasku.** Overlay
`writing-plans.overlay.md` `Instruction` jmenuje, ale
`subagent-driven-development.overlay.md` ve svém výčtu klíčů páté stop třídy
**ne**. Sezení jdoucí podle overlaye doslova by po zpřísnění napsalo baton,
který hook zamítne jako stale — a **pro tento plán je to akutní**, protože se
vykonává pod SDD a počítá s rotací kontextu na hranicích tasků. Editace
fragmentu proto jde do stejného tasku jako A2; poslední zůstává jen revendor.

**A1 — `initialUserMessage` vedle `additionalContext`.** Hook emituje obojí;
`initialUserMessage` nese pevný anglický text, který říká, že dorazil baton,
že **první mají přednost bootstrap kontroly** a že baton nikdy nepřebíjí
fail-closed bránu, a teprve pak se jedná podle řádku `Instruction`. Emituje
se jen když se emituje baton; každá stale i absentní cesta zůstává tichá.

Hodnota A1 je v **delivery mode 1**: `/clear` ve vlastním workspace přestane
čekat na stisk klávesy. Pro pool už nosné není, takže operátorské ověření ve
VS Code extension přestává být blokující — pool poběží i tam, kde extension
to pole ignoruje.

### 6. Skill `mb-epic-run`

Sourozenec `mb-epic-elaboration`, stejně jako `mb-epic-graph`. Čtyři operace,
všechny reportované česky.

**`status`** — spustí `pool-status.ps1`, vyrenderuje tabulku (slot, marker,
větev nebo detached, pin nebo IDLE, postup v plánu, dirty a unpushed, živé
sezení) a přidá pohled epiku: u každého tiketu v ledgeru, jestli ho nějaký
slot drží.

**`ready <EPIK>`** — spustí `epic-graph.ps1` a `ledger-status.ps1`, **jak
jsou**, a vytiskne oba výstupy vedle tabulky poolu. **Žádný verdikt, žádná
klasifikace.** Rozhodnutí zůstává operátorovi, který ho zatím dělal ručně a
správně; skill mu k tomu jen položí obě tabulky na jedno místo, aby je
nemusel sbírat. Návrh klasifikace je předběžný v
[`../next/design_pool_brana_pripravenosti.md`](../next/design_pool_brana_pripravenosti.md)
a každé rozjetí se do ledgeru zapíše, aby se po dvou až třech ukázalo, co se
opakuje.

**`spawn <TIKET>`** v tomto pořadí:

1. Kontrola způsobilosti: pool existuje (aspoň jeden označený worktree),
   tiket je v ledgeru, existuje volný slot podle derivace ze sekce 2, větev
   tiketu není vyzvednutá jinde, a `mb-doc-index` nehlásí kolizi aktivní
   práce. Cokoli z toho nesplněné je STOP se jmenovaným důvodem.
   **Selhavší kolizní kontrola není „žádná kolize"** — nedoběhlá kontrola je
   STOP, ne průchod.
2. Volba slotu.
3. Zápis řádku záměru do ledgeru epiku, commit a push na elaborační větvi.
4. Vyvolání `pool-launch.ps1` se zvoleným adaptérem, krátkým promptem a
   `--name <TIKET>`; ohlášení stavového slova česky.
5. Mechanické ověření podle sekce 4, pak operátorské otázky.

**`attach <TIKET>`** — najde slot, který tiket drží, a **vytiskne**
operátorovi další akci: cestu ke slotu, příkaz, kterým se tam dostane, a
stav sezení z `claude agents --json`. Tiskne, nespouští za operátora nic.

**Železná pravidla těla skillu.** Orchestrátor nikdy nepřepne (`cd`) do
slotu; nikdy ve slotu nespustí zapisující git příkaz; nikdy ve slotu nic
nemaže, nepřesouvá **ani nezapisuje**; nikdy nespawnuje bez kolizní kontroly;
a **STOP musí slot nechat přesně tak, jak ho našel** — což je teď triviálně
splnitelné, protože do slotu nezapisuje vůbec.

Frontmatter: `name`, česky formulovaná `description` ve stylu ostatních
`mb-*` skillů, `allowed-tools` zúžené na read-only git, `claude agents`, tři
skripty a vlastní čtení skillu. Skill se zapisuje do `SKILLS_MANIFEST.md`.

### 7. Změny kontraktu (2.13)

- **Worktree Policy** — zákaz zůstává, ale **jeho odůvodňující měření
  neobstojí a musí se přepsat**, ne jen doplnit výjimkou. Kontrakt dnes
  tvrdí, že klon monorepa zabírá 25 GB, z toho `.git` 4,1 GB, takže linked
  worktree ušetří 16 %, „což nezaplatí ten další strom". Měřeno: slot má
  7,7 GB, sdílený `.git` 4,4 GB a hlavní klon 27,2 GB — úspora je asi
  **70 %, ne 16 %**, protože rozdíl je naakumulovaný build output, ne zdroj.
  Věta nesoucí celou váhu zákazu se tím stává nepravdivou. Nová formulace:
  zákaz zůstává z důvodů, které nejsou o disku (jedno sezení na workspace,
  žádná agentní provisionace), a disk se popíše měřenými čísly.
  K tomu výjimka poolu: slot je uživatelem **označený** linked worktree,
  hledí se na něj jako na nalezený workspace; agentem vytvořené worktrees
  zůstávají zakázané; idle slot je detached nebo na větvi jménem shodné s
  adresářem slotu, ale **o IDLE rozhoduje výhradně pin, nikdy jméno větve**.
  Sdílený `.git` znamená, že jednou instalovaný `pre-push` guard pokrývá
  každý slot — s poznámkou o relativní cestě z primary worktree.
- **Workspace Discipline** — tři věci. Slot poolu je workspace ve smyslu
  kontraktu („jedno sezení na workspace" platí per slot). **Oprava derivace
  „volný workspace" pro pool**: která signály jsou per-worktree a které ne,
  že stash se slotu přiřadit nedá, že čtvrtý signál je definovaný jen vůči
  aktuálnímu slugu, a že **živé sezení ve slotu** je vlastní signál, který
  žádný git příkaz nezná. A **zúžení dvou vět na aktéra**: „vrstva hledí na
  workspace jako na nalezený, nikdy jako na čerstvě provisionovaný" a
  „sezení nikdy neprovisionuje jiný workspace" — pool provisionaci zavádí,
  ale výhradně pro uživatele a vynuceně.
- **Session Intent Baton** — `Instruction` povinný **a validovaný** pro oba
  existující druhy. **Žádný nový druh**; věta o tom, že baton je kanál pro
  rotaci kontextu ve vlastním workspace, a že záměr do cizího workspace se
  doručuje jinak, aby příští čtenář nezaváděl `ticket-start` znovu bez
  důvodu.
- **Repository Configuration** — **žádný `pool` blok.** Zapsat, že seznam
  odebíraných proměnných a cesta ke `claude.exe` **nejsou** repozitářová
  konfigurace, aby věta „žádná repozitářově specifická hodnota nesmí žít v
  těle skillu nebo skriptu" zůstala pravdivá.
- **Brainstorming / vstupní brána** — po `git switch -c` následuje
  `git branch --unset-upstream` a první publikace je `git push -u origin
  HEAD`. Dnes to kontrakt řeší jen tou první publikací; odpojení upstreamu
  chybí a je to měřená past.
- **Language Contract** — pravidlo se nemění; poznámka, že launcher a status
  skripty jsou vývojářské nástroje vrstvy (anglicky), zatímco reporty
  `mb-epic-run` jsou pro člověka (česky).

### 8. Integrace do `mb-epic-elaboration`

`SKILL.md` fáze 7 (Close) a `protocol.md` §3.3: po publikaci se nabídne
`mb-epic-run ready` (obě tabulky na jedno místo) a u tiketů, které operátor
vybere, `mb-epic-run spawn` — nabídka, jedna otázka, rozhodne operátor per
tiket. Přidá se řádek do quick-reference. Jsou to soubory vrstvy, edituje se
přímo, žádný overlay.

`ledger-template.md` dostane konvenci pro **řádek záměru** (sekce 3).
**Nestačí „stávající sada zůstane zelená"** — ta je zelená před i po změně a
žádný řádek záměru nikdy neuvidí. Sada dostane **fixturu, která ten řádek
nese**, protože parser tabulek ledgeru končí na prvním řádku bez svislítka a
indexuje sloupce pozičně.

### 9. Sweepy: co tato práce činí nepravdivým

- **Bump verze kontraktu je vlastní sweep** — `grep -rn '2\.12' ums/
  memory-bank/ CLAUDE.md`; nálezy podle vlastníka: **soubory vrstvy opraví
  implementace ve stejném commitu jako pravidlo; dokumenty Memory Bank opraví
  harvest**. Dvě skupiny nepatří ani do jedné: archiv v
  `proposals/completed/` se **nikdy needituje**, a legacy `tasks.md` je
  potřeba rozhodnout jmenovitě.
- **Počítací a jedinečnostní fráze** — Worktree Policy tvrdí zákaz bez
  výjimky a měření jako uzavřený argument; Workspace Discipline tvrdí „nikdy
  jako čerstvě provisionovaný". Slovník:
  `jediná|jediný|přesně|nikdy|vždy|žádná výjimka|only|never|exactly|single`.
- **Věty, které stojí na měření disku** — 16 %, 25 GB, 4,1 GB. Sweep na
  čísla, ne na pojmy.
- **Inventáře podle druhu artefaktu** — `tech.md` (počty sad, součty asercí,
  inventář nástrojů, řádek `settings.json`), `ums/README.md`,
  `SKILLS_MANIFEST.md`. Grepovat na jména **sourozeneckých** artefaktů.
- **Věty o batonu jako o obecném nosiči záměru** — po tomto tiketu je baton
  nosič **rotace kontextu ve vlastním workspace**; záměr do cizího workspace
  jde argv. Prohledat sekci Session Intent Baton v
  [architecture.md](../../architecture.md), hlavičku hooku a testy.

## Odchylky od zadání a jejich důvody

Zadání (`dispatch-brief-ticket-pool-orchestration.md`, 2. 9. 2026 15:05) bylo
psané **před** poznatky z ručních pokusů (`poznatky-spousteni-agentu.md`,
15:26) a bez znalosti stavu poolu. Dvě agentické oponentury pak obrátily i
část rozhodnutí prvního návrhu.

| Zadání | Návrh | Důvod |
|---|---|---|
| Part A je aktivní nedotestovaná položka | A1+A2 jsou tasky tohoto plánu | `baton_rotace_kontextu` je už sklizený a integrovaný; archiv v `completed/` je neměnný |
| JIRA-less, slug `pool_orchestrace_tiketu` | UMS-3488 | Tiket existoval už 12:30 pod jménem `mb-epic-dispatch`; jméno skillu zůstává `mb-epic-run` |
| Jedna práce | **tři tikety** — `doc-index` opravy, mechanika, brána | Bundle mísil živý defekt nasazené vrstvy, prokázanou mechaniku a nedokázaný úsudek. Oprava fail-closed brány na monorepu nemá čekat za jedenácti úlohami |
| FIXED 5: baton + launcher, nic na příkazové řádce | **argv** + řádek v ledgeru; žádný `Kind: ticket-start` | Baton je ambientní kanál, argv cílený. `Slot`, čtyři hlídky a validace `Ticket` byly všechno opravná práce za tu změnu kanálu — a oba postavené launchery prompt nesou |
| Briefing jako soubor ve slotu (a po prvním kole uzavřený a re-renderovaný) | **žádný briefing**; záměr jedním řádkem do commitnutého ledgeru | Sedí na model tahu; odpadá otrávení slotu nezkonzumovaným batonem po neúspěšném launchi; a sanitizér by zakázal lomené závorky, tedy XML, BPMN i C# generiku — v monorepu, jehož tikety jsou právě o tom |
| B4: brána připravenosti jako součást spawnu | `ready` **jen tiskne** obě existující tabulky | Všechna měřená selhání byla mechanická; úsudková část běžela jednou a byla 6/6 správně ručně. UMS-3488 sám radí odložit. Tím padá i `-Json` pro obě orákula — existovalo jen pro join |
| FIXED 3: idle slot je detached | detached **nebo** vlastní větev, ale o IDLE rozhoduje **výhradně pin** | `ums04` stojí na větvi `ums04` a měřeno má ACTIVE pin, takže vlastní větev slot **parkuje**, ne dělá idle |
| FIXED 4: `pool.root` v `ums-repo.json` | derivace z `git worktree list` **plus marker** ve worktree | `ums-repo.json` je trackovaný a sdílený s `pmq_logopedie_nr`. Marker není centrální konfigurace a brání spawnu do worktree drženého pro release maintenance, který jinak splní každou podmínku volnosti |
| FIXED 4: volnost ze `status` + `stash list` + `log --branches` | jen per-worktree signály, plus **živé sezení** | `refs/stash` i `refs/heads` jsou v poolu sdílené (měřeno), takže dva ze tří signálů by udělaly každý slot navždy nevolným |
| FIXED 4: liveness best-effort, „unknown" | `claude agents --json --cwd` | Zdokumentované, bez TTY, filtruje na slot a **právě teď vypisuje tento pool**. Bez něj je slot „volný" po celou minutu, než v něm naběhlé sezení dojde k zápisu pinu — a spawn by poslal druhé |
| FIXED 4: ledger z `.superpowers/sdd/*/progress.md` | ledger se páruje na slug z pinu | `ums03` má **oba** ledgery a cizí se řadí první |
| FIXED 5: čtyři adaptéry | `terminal` + `direct` | Jen tyhle dva jsou prokázané |
| FIXED 5: „launcher jen spustí Claude Code" | povinné vyčištění devíti proměnných + `--name` + ověření v session registru | Bez vyčištění naběhne dětská session s vypnutým transcriptem (pokus 2). `--name` a registr dělají ze dvou ze tří měřených selhání strojově detekovatelné události |
| Poznatky: odebrat i `CLAUDECODE` | **nechává se** | Rušilo by precondici zapisovatele batonu, a na `-Scope UserProfile` je to jediný nosič publikační záruky |
| Poznatky: seznam proměnných nedávat natvrdo | seznam je v `pool-launch.ps1` | Je to vlastnost harnessu, ne repozitáře |
| B6: past s upstreamem do briefingu | do overlaye `brainstorming` a do kontraktu | Ten `switch -c` předepisuje overlay pro **každé** sezení; oprava u zdroje chrání všechna, opis do zadání jen spawnutá |
| B3: `pool-provision.ps1 -Root -Count` | `-Path`, `-Base`, **guard proti agentní relaci**, zakládá marker | „Nástroj operátora" nesmí vynucovat próza, když `permissions.deny` skript nekryje |
| B7: bez změny overlay fragmentů | jeden řádek v `subagent-driven-development.overlay.md` **v témž tasku jako A2** + revendor | Fragment `Instruction` nejmenuje, takže by A2 udělalo z jeho batonů stale — akutně pro tento plán, který sám rotuje kontext |

## Dopady

**Na existující práci v poolu.** Nic se nemigruje, ale sloty potřebují
**marker** — jeden operátorský příkaz na každý. Měřeno 2. 9. 2026: špinavých
záznamů má ums01 34, ums02 222, ums03 221, ums04 0; ums04 nese ACTIVE pin a
ve třech ze čtyř slotů právě běželo sezení. **Žádný slot dnes není volný**,
takže end-to-end verifikace vyžaduje provisionovat nový — není to volitelný
krok.

**Na batony napsané před touto změnou.** Baton bez `Instruction`, nebo s
hodnotou, která žádný skill nejmenuje, se po A2 stane stale. Cena je nulová
pro cizí sezení, ale **ne pro tento plán**: mezi A2 a opravou overlay
fragmentu by každá jeho vlastní rotace kontextu tiše ztratila předání — proto
obojí jde do jednoho tasku.

**Na vstupní bránu.** Nic z tohoto tiketu ji nemění. Oprava kolizní kontroly
je vlastní tiket a měla by jít **první**, protože dnes na monorepu ta
fail-closed kontrola nedoběhne vůbec.

**Na nasazení.** Změny zdroje v `ums/.claude/` je potřeba nasadit do
kořenového `.claude/` (a `.agents/skills/`). Změna overlay fragmentu navíc
vyžaduje revendor — plný jednoprůchodový běh s pinovaným tagem, ne
`-OverlaysOnly`.

**Na ostatní harnessy.** `mb-epic-run` a kontrakt jsou čistý Markdown a
přenesou se. `claude agents --json` je vázané na Claude Code, takže na jiných
harnessech obsazenost slotu není k dispozici — a protože je to **tvrdý** důvod
slot nepoužít, degraduje to fail-closed: bez toho signálu skill ohlásí, že
obsazenost neumí zjistit, a spawn nechá na výslovném pokynu operátora. Guard
v `pool-provision.ps1` putuje se skriptem, `permissions.deny` ne.

## Rizika

**Prompt na příkazové řádce má měřené pasti.** Musí být obalený doslovnými
uvozovkami (jinak se rozpadne na jednotlivé argumenty — pokus 3) a nesmí
obsahovat středník (`wt.exe` ho bere jako oddělovač). Obojí se ověřuje
sondou, která si vypíše `$args`, **před** prvním ostrým spuštěním; to je ta
disciplína, která 2. 9. udělala rozdíl mezi pokusem 3 a 4.

**Precondice zapisovatele batonu ve spawnutém sezení je tvrzení k ověření.**
Ponechání `CLAUDECODE` ji má zachovat, ale že spawnuté sezení skutečně smí
napsat vlastní baton, se musí změřit v tom sezení, ne dovodit.

**`claude agents --json` je nezdokumentované co do stability tvaru.** Je to
zdokumentovaný přepínač, ale semantika položek bez `pid` a případné
staleness okno ověřené nejsou. Konzument proto filtruje na přítomný `pid` a
signál je fail-closed: nejde-li přečíst, obsazenost se hlásí jako neznámá a
spawn čeká na pokyn.

**Worktree bez markeru se do poolu nedostane, a to je záměr.** Cena je, že
operátor musí sloty jednou označit a na nový slot si na to vzpomenout —
`pool-provision.ps1` to dělá sám, ruční `git worktree add` ne.

**Slot něco stojí na disku, ale méně, než se čekalo.** Měřeno: slot 7,7 GB /
80 022 souborů, sdílený `.git` 4,4 GB, hlavní klon 27,2 GB / 140 365 souborů
— rozdíl je build output. Čerstvý slot je asi 8 GB.

## Verifikace

1. **Testy hooku zeleně** — A1: `initialUserMessage` přítomný na happy path
   a **nepřítomný** na stale cestě. A2: baton bez `Instruction` → stale,
   `Instruction` nejmenující žádný skill → stale, `Instruction` nad stropem
   → stale, oba existující druhy nedotčené jinak. Verifikuje se
   **izolovaně**, dřív než se sáhne na skripty. Počet asercí zjištěný
   spuštěním celé sady v témž sezení a zapsaný do ledgeru.
2. **Volnost slotu proti skutečnému sdílenému `.git`.** Fixtura s několika
   linked worktrees, ne simulace. Regresní důkaz: **stash vytvořený v jednom
   worktree nesmí udělat jiný slot nevolným**, a **nepushnutý commit na
   větvi A nesmí udělat nevolným slot stojící na větvi B**. S původní,
   kontraktovou trojicí signálů oba případy zčervenají — to je ta žádaná
   negativita.
3. **Obsazenost.** `claude agents --json` se stubuje: záznam s `pid` v cwd
   slotu → slot obsazený a **nepoužitelný**; záznam bez `pid` → ignorován;
   nečitelný výstup → obsazenost neznámá a spawn čeká, nikdy neprojde.
4. **Marker.** Neoznačený linked worktree se v tabulce poolu vůbec neobjeví;
   označený ano.
5. **Ledger a kandidáti.** Fixtura se slotem, který má **oba** ledgery (cizí
   se řadí první) → hlásí se postup toho z pinu; slot s **cizím** kandidátem
   playbooku → **zůstává volný**.
6. **Vyčištění prostředí.** Potomek vypíše `Env:` do souboru; kontrola
   nepřítomnosti všech **devíti** proměnných a **přítomnosti**
   `CLAUDE_CODE_USE_POWERSHELL_TOOL` i `CLAUDECODE`.
7. **Doručení promptu měřené na neškodném cíli.** Skript, který si vypíše
   `$args` do souboru, spuštěný přes **oba** adaptéry se skutečným
   zamýšleným promptem; kontrola „jeden argument, text beze ztráty, včetně
   diakritiky". Tenhle krok se dělá **před** ostrým spuštěním. (V prvním
   návrhu byl tento bod regresní zámek, protože se žádný argument
   nepředával; s doručením přes argv je to skutečný důkaz.)
8. **Mechanické ověření spuštění.** Po spawnu s `--name <TIKET>` musí
   `claude agents --json --cwd <slot>` vrátit záznam s tím jménem, přítomným
   `pid` a časem startu po okamžiku spawnu; chybí-li, skill hlásí „ověř na
   obrazovce", ne „spuštěno".
9. **Publikační záruka ve spawnutém sezení** — `MB_AGENT_SESSION` nastavený,
   syntetický protected-branch pipe nenulově a zrcadlová accept case nulou.
10. **Precondice zapisovatele ve spawnutém sezení** — `CLAUDECODE` neprázdný
    a hook registrovaný, tedy sezení smí napsat vlastní baton.
11. **`pool-provision.ps1` guard** — běh s markerem agentní relace bez
    operátorského přepínače musí odmítnout; s přepínačem projít. A ověřit, že
    zakládá marker a že nepřeinstalovává aktuální sdílený hook.
12. **`ledger-status.ps1` na fixtuře nesoucí řádek záměru** musí naparsovat.
    Samotné „stávající sada zůstala zelená" se za důkaz nepočítá.
13. **Negativní: dvakrát tentýž tiket** → STOP kolizí, nebo odmítnutým
    checkoutem gitu; slot nedotčený, nic nezapsáno.
14. **Negativní: žádný volný slot** → report, který slot co drží, žádný
    launch.
15. **Negativní: repozitář bez označeného worktree** → fail-closed odmítnutí
    českou hláškou. Testuje se na **tomto forku**.
16. **Negativní: selhavší kolizní kontrola** → STOP, ne průchod.
17. **End-to-end spawn — OPERÁTORSKÝ KROK.** Předpoklad: **provisionovat nový
    slot**, protože žádný ze čtyř dnešních volný není. Z orchestrátoru
    `mb-epic-run spawn <TIKET>` s adaptérem `terminal`; pozoruj, že nové
    sezení dostalo **celý** prompt, projde vstupní bránu, založí tiketovou
    větev a aktivuje draft. Pak `mb-epic-run status` ukáže slot obsazený a
    po zápisu pinu ACTIVE se slugem. Zopakuj s adaptérem `direct`. Ověření:
    **není** tam `⚠ Transcript saving is off` a v prvním vstupu je celý
    prompt.
18. **A1 ve VS Code extension — OPERÁTORSKÝ KROK, NEBLOKUJÍCÍ.** Čerstvé
    sezení extension s platným batonem: rozjede první tah samo? Pak totéž v
    CLI mimo extension jako kontrolní běh, bez kterého nelze selhání
    přiřadit frontendu. Oba výsledky zapsat do návrhu před harvestem. Na
    poolu to nestojí, takže negativní výsledek položku nezastaví.
19. **Sweepy ze sekce 9 provedené**, s rozdělením podle vlastníka: soubory
    vrstvy ve stejném commitu jako pravidlo, dokumenty Memory Bank předané
    harvestu jmenovitým seznamem, archiv `completed/` nedotčený.

## Pořadí úloh

1. **Kontrakt 2.13** — pravidlo má jeden domov, takže kontrakt jde **před**
   implementací kteréhokoli z těch pravidel, A2 nevyjímaje.
2. **A1+A2 + oprava overlay fragmentu** — verifikuje se **izolovaně**.
3. **`pool-status.ps1`** — per-worktree signály, marker, obsazenost z
   `claude agents --json`, ledger podle pinu; testy včetně fixtury se
   skutečným sdíleným `.git`.
4. **`pool-launch.ps1`** — vyčištění devíti proměnných, dva adaptéry,
   `--name`, zauvozovkovaný argv prompt, stavové slovo; testy plus sonda
   `$args` přes oba adaptéry.
5. **`pool-provision.ps1`** — guard, marker, kontrola sdíleného hooku,
   hlášení velikosti; testy.
6. **Skill `mb-epic-run`** — čtyři operace, `SKILLS_MANIFEST.md`.
7. **Integrace do `mb-epic-elaboration`** + řádek záměru v
   `ledger-template.md` + fixtura pro `ledger-status.ps1`.
8. **Past s upstreamem do overlaye `brainstorming`** a do kontraktu.
9. **Dokumentace** — README skillu (anglicky) a český průvodce, včetně
   pohodlí stanice a příkazu na označení existujících slotů.
10. **`permissions.deny`, nasazení a revendor.**

Každá úloha končí commitem přes `mb-git-commit` a publikací tiketové větve
(první publikace `git push -u origin <větev>`, protože `switch -c` nechal
upstream na bázi).

## Navazující položky

- **Dva vyčleněné tikety** — `doc-index` opravy a brána připravenosti; návrhy
  leží v `proposals/next/`.
- **Adaptéry `vscode`, `deeplink`, `bg`** — každý je malý task, ale každý
  potřebuje vlastní operátorské ověření. `bg` je z nich nejzajímavější:
  `claude attach <id>` otevře background sezení v terminálu a `claude logs
  <id>` vytiskne jeho výstup, což by z kontroly „není tam varování o
  transcriptu" udělalo strojovou kontrolu.
- **Je `mb-epic-run` správný domov?** Druhá oponentura namítá, že je to
  čtvrté české `description` v téže sémantické čtvrti („rozpracuj epik" /
  „graf závislostí" / „co je připravené rozjet" / „kdo na čem pracuje") a že
  triggering řídí výhradně `description`. Zůstává jako skill, protože
  spouštění je skutečně nová schopnost — ale jestli se ukáže, že operátor
  netrefuje, patří `ready` do `mb-epic-graph` a zbytek jsou skripty volané z
  uzávěrky elaborace.
- **`NO_COLOR`** — neověřeno, jestli po odebrání barvy naskočí, a jestli není
  potřeba i `FORCE_COLOR=1`.
- **Proč selhal `cmd.exe /k` s batchem** (pokus 1) — nerozebráno; netýká se
  žádného stavěného adaptéru.
- **Konsolidace s playbookem monorepa** — sekce „Rozjetí tiketu do vlastní
  session" a „Kolizní kontrola" na větvi `SKODASMS-237-okno-w06` popisují
  ruční postup, který tato práce automatizuje. Po dokončení je přepsat na
  odkaz na skill, ne nechat vedle sebe dvě pravdy.
- **Poznámka o `.gitignore` v `poznatky-spousteni-agentu.md` je obrácená** —
  tvrdí, že kořenový `.superpowers/` ignorovaný není a
  `memory-bank/.superpowers/` je; změřeno je to naopak.
- **Redistribuovatelnost do `pmq_logopedie_nr`** nešla ověřit — repozitář
  není lokálně k dispozici.
