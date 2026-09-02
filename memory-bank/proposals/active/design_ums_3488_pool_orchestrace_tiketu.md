# Návrh: Pool orchestrace tiketů (`mb-epic-run`)

- **Jira:** UMS-3488 (https://datasyscz.atlassian.net/browse/UMS-3488)
- **Target MB:** memory-bank/
- **Vytvořeno:** 2026-09-02
- **Oponentura:** agentická, 2026-09-02 — 29 nálezů, 26 zapracováno beze změny rozsahu, 3 rozhodnuta uživatelem, závěry níže

## Cíl

Rozpracování epiku (`mb-epic-elaboration`) dnes končí tím, že v
`proposals/next/` leží předběžné návrhy budoucích tiketů. Odtud dál je ruční
práce: operátor otevře workspace, přepne větev, přečte, co se má dělat, a
nadiktuje sezení zadání. Cíl je, aby **řídicí sezení epiku (orchestrátor)
umělo říct, které tikety je bezpečné rozjet a proč, rozjet plnohodnotné
sezení na tiket do volného slotu poolu, a na požádání říct, jak sloty
stojí.**

Ta první část je ve vrstvě dnes **formálně nepokrytá**. `mb-epic-graph` umí
říct, co je odblokované, ledger nese špinavé řádky, `pool-status.ps1` bude
vědět o slotech — ale nic ty tři signály nespojuje, takže rozhodnutí „tenhle
tiket rozjet, tenhle ne" vzniká ručně a dá se v něm udělat chyba, kterou nic
nezachytí.

Mechanická část toho postupu už je zaplacená. 2. 9. 2026 proběhlo pět pokusů
rozjet sezení ručně; **tři selhaly, každý z jiné příčiny, a všechny tři
vypadaly jako úspěch** — u dvou to bylo ohlášeno jako hotové a u jednoho
zapsáno do Jiry, přestože na tiketu nikdo nepracoval. Postup je zapsaný v
`playbook.md` monorepa, sekce „Rozjetí tiketu do vlastní session"; tenhle
návrh je o tom, co v playbooku být nemůže, protože to není příkaz, ale
úsudek — a o tom, aby se ta mechanika přestala provádět rukou.

Druhý, menší cíl: **dokončit session baton** ze sklizené položky
`baton_rotace_kontextu` dvěma amendmenty, na kterých bezzásahový start
poolu stojí. Bez nich dorazí do nového sezení baton jako kontext, ale sezení
dál čeká na stisk klávesy — a spawn do slotu, který nikdo nesleduje, by se
nikdy nerozjel.

## Scope

**V rozsahu:**

- Dva amendmenty čtenáře batonu: emise `initialUserMessage` vedle
  `additionalContext`, a `Instruction` jako povinný a **validovaný** klíč.
- Nový druh batonu `Kind: ticket-start` s vlastní sadou povinných klíčů,
  vlastními hlídkami a **vazbou na slot** (origin binding).
- Uzavření a re-render **briefingu** čtenářem batonu — briefing prochází
  týmiž kontrolami jako baton a agent nikdy nečte surový soubor.
- Tři skripty vrstvy: `pool-status.ps1` (derivace stavu slotů),
  `pool-launch.ps1` (vyčištění prostředí a spuštění), `pool-provision.ps1`
  (operátorské zakládání slotu, s guardem proti běhu z agentní relace).
- Nový skill `mb-epic-run` se čtyřmi operacemi: `status`, `ready <EPIK>`,
  `spawn <TIKET>`, `attach <TIKET>`.
- **Rozhodovací proces „co je bezpečné rozjet"** — dnes ve vrstvě formálně
  nepokrytý; join glyphu z grafu, dirty-setu z ledgeru a stavu poolu do
  jednoho verdiktu s pojmenovaným důvodem.
- Strojově čitelný výstup `-Json` pro `epic-graph.ps1` a pro
  `ledger-status.ps1`, aby ten join nemusel parsovat vyrenderovanou prózu.
- Režim cíleného skenu v `doc-index.ps1`, aby byla kolizní kontrola na
  monorepu vůbec proveditelná.
- Změny kontraktu na verzi 2.13 a integrace do `mb-epic-elaboration`.

**Mimo rozsah** (a proč):

- **Žádná evidence slotů** — žádný registr, žádné lock soubory, žádný démon.
  Stav slotu je derivovaný při každém dotazu.
- **Orchestrátor nikdy neukončuje sezení tiketu.** Tiket končí harvestem,
  parkem nebo abortem, které provede agent tiketu na své větvi. Orchestrátor
  smí požádat, ne rozhodnout.
- **Žádné agentem vytvářené worktrees.** `pool-provision.ps1` je nástroj
  operátora a je to vynucené guardem ve skriptu plus `permissions.deny`, ne
  jen prózou (viz sekce 5 a 10).
- **Žádné agent teams a žádné `isolation: worktree` subagenty** pro práci na
  tiketu — teammates běží v pracovním adresáři vedoucího, což je přesně to,
  co pool nedělá.
- **Žádné zápisy do Jiry z `mb-epic-run`.** Jira zůstává u `mb-jira-update`
  a u agenta tiketu.
- **Adaptéry `vscode`, `deeplink` a `bg`** se v této práci nestaví (viz
  „Odchylky od zadání").
- **Delivery mode 2 batonu** (spawn-and-abandon) se jen textově opravuje,
  nestaví se.
- **Vážení a doporučení množiny ke spuštění** („spusť tyhle tři") — viz
  „Navazující položky".

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
  `.git/hooks/pre-push`. Kdokoli srovnává rozřešené cesty na identitu napříč
  poolem, musí je nejdřív normalizovat na absolutní; prosté srovnání řetězců
  selže, jakmile se orchestrátor ptá z hlavního klonu.
- **`core.hooksPath` s relativní hodnotou** se resolvuje per-worktree, takže
  v tom případě potřebuje každý slot vlastní běh instalátoru.

### 2. Derivovaný stav slotu

**Členství v poolu je derivované, ne konfigurované.** Pool jsou linked
(ne-primary) worktrees tohoto repozitáře minus ten, ve kterém stojí
orchestrátor. Zdroj je jedno čtení `git worktree list --porcelain`; primary
worktree je jeho první záznam, orchestrátorův vlastní se pozná srovnáním s
`git rev-parse --show-toplevel`. Repozitář bez linked worktree nemá pool a
`mb-epic-run` fail-closed odmítne českou hláškou, která to říká — což je
mimochodem stav **tohoto forku** (nula linked worktrees), takže ta cesta má
vlastní test.

Porcelain záznam nese víc než cestu a větev a derivace to musí unést:
`bare` worktree se přeskočí, `locked` a `prunable` se **nepočítají za
kandidáta** a hlásí se s pojmenovaným důvodem — u `prunable` (adresář je
pryč, záznam zůstal) by `git -C <cesta> status` vůbec nešlo spustit.

**Volnost slotu se derivuje jen ze signálů, které jsou per-worktree.** Tohle
je nejtvrdší korekce oponentury a je měřená: v linked worktree jsou
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
| nezkonzumovaný baton | `<slot>/.superpowers/session-intent.md` | per-worktree ✔ |
| stash | `git stash list` | **repo-wide ✘ — nelze přiřadit slotu** |
| kandidát playbooku | `<slot>/.superpowers/playbook-candidates/<slug>.md` | per-worktree, ale **jen když slot nese pin** |

**Volný slot** je proto: čistý strom, IDLE pin, žádný nezkonzumovaný baton,
žádné nepushnuté commity **na vlastním HEAD či vlastní větvi**, a nedrží
tiketovou větev tohoto epiku.

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
— ohlásí ho a rozhodnutí nechá uživateli v tom slotu, kde zbytky leží. To je
Workspace Discipline, nikoli opatrnost: rozhodnutí o neobnovitelném obsahu
patří uživateli.

**Ledger se páruje na slug z pinu, nikdy na „první nalezený adresář pod
`sdd/`".** Měřeno: slot `ums03` nese pin na `skodasms_251_regexovy_pool_bota`
a v `.superpowers/sdd/` má **oba** adresáře —
`plan_skodasms_239_knihovna_chytrolinconnect` (zbytek po předchozí práci) i
`plan_skodasms_251_regexovy_pool_bota` (ten správný). Derivace „první
nalezený" by vzala 239, protože se řadí dřív, a ohlásila cizí postup jako
postup tohoto tiketu. Fixtura tohle musí reprodukovat věrně: **oba** ledgery
přítomné, cizí řadící se první.

**Idle slot je detached, nebo stojí na větvi, jejíž jméno se rovná jménu
adresáře slotu** — ale ta druhá varianta **není** důkazem, že slot je idle.
Měřeno: `ums04` stojí na větvi `ums04`, má čistý strom a přitom nese
**ACTIVE pin** (`ums_3485_vyhodnoceni_a_zobrazeni_stavu`). Skutečná konvence
poolu tedy je „vlastní větev slot **zaparkuje**, zatímco pin trvá" — tedy
`mb-park` —, ne „vlastní větev znamená idle". Jméno větve proto **nikdy
nerozhoduje o IDLE**; o tom rozhoduje výhradně pin v `context.md`. Tvar se
přijímá kvůli něčemu jinému: je to pojmenované místo, kam slot přepnout, když
je potřeba uvolnit větev vyzvednutou jinde. `pool-provision.ps1` nové sloty
zakládá `--detach`; existující se nemigrují, protože jsou to nalezené
workspace.

**Liveness je best-effort a nikdy nerozhoduje.** Bez postaveného adaptéru
`bg` nemá vrstva zdroj, ze kterého by se dala poznat, takže se hlásí
`unknown`. PID soubory pod `~/.claude/sessions/` se nečtou — je to
nezdokumentované rozhraní, které se může změnit.

### 3. Baton `Kind: ticket-start`

Formát batonu zůstává uzavřený a mechanika beze změny: parsuje se, znovu
renderuje, nikdy neemituje doslova, po emisi se přejmenuje na
`session-intent.consumed.md`, při zamítnutí hlídkou na
`session-intent.stale.md`, každá chybová cesta končí tiše s exit 0.

Klíče podle druhu:

| Kind | Povinné | Volitelné |
|---|---|---|
| `plan-execution`, `plan-resume` | `Kind`, `Plan`, `Branch`, `Slug`, `Instruction` | `Spec`, `Ticket`, `Ledger`, `Next task` |
| `ticket-start` | `Kind`, `Ticket`, `Slug`, `Slot`, `Base`, `Instruction` | `Spec`, `Brief` |

**Povolená množina klíčů je per-druh, ne jeden plochý seznam.** Dnes slouží
`$RenderOrder` současně jako pořadí renderu i jako whitelist
(`if ($RenderOrder -notcontains $key)`), takže přidání `Base`, `Slot` a
`Brief` by je udělalo legálními i na batonech druhu `plan-execution` — kde
pro ně není definovaná žádná kontrola existence. Whitelist se proto rozdělí
per druh; `$RenderOrder` zůstává jen pořadím renderu a dokumentuje se v
souboru jako stabilní.

**`Slot` je origin binding, který `ticket-start` jinak nemá.** U existujících
druhů váže baton k sezení `Branch` proti `HEAD` a `Slug` proti pinu; u
`ticket-start` obojí padá — `Branch` proto, že idle slot na tiketové větvi
nestojí, `Slug` proto, že precondicí je IDLE `context.md`, ve kterém žádný
slug není. Bez třetí vazby by **kterýkoli čistý IDLE slot přijal kterýkoli
`ticket-start` baton**: orchestrátor zapíše baton pro tiket T1 do slotu S,
operátor mezitím otevře sezení v S s úmyslem dělat T2, strom je čistý a pin
IDLE — baton pro T1 vystřelí a sezení začne nesprávný tiket. `Slot` proto
nese absolutní cestu slotu a čtenář ji srovnává s
`git rev-parse --show-toplevel`; neshoda je stale.

Hlídky pro `ticket-start` (každá při selhání → stale, tiše, exit 0):

1. **`Slot` se rovná tomuto worktree** (po normalizaci na absolutní cestu).
2. **Čistý strom** — `git status --porcelain` prázdný.
3. **Žádná lokální větev tiketu** — neexistuje větev odpovídající
   `<Ticket>-*`.
4. **IDLE `context.md`** — žádný pin.

**`Ticket` se validuje na tvar**, proti `ticketPattern` z konfigurace
repozitáře (v monorepu `UMS-\d+`, v tomto forku `^UMS-[0-9]+`); bez platného
tvaru je baton stale. Bez té kontroly je hlídka 3 vakuózní: nesmyslný
`Ticket` nedá smysluplný glob a hlídka propustí cokoli.

**Hlídka 3 se porovnává case-INSENSITIVE, a to je vědomá odchylka od
pravidla vrstvy**, že srovnání operandů z gitu je case-sensitive. Důvod je,
že tady padá chyba na opačnou stranu: case-sensitive porovnání by u batonu s
`UMS-3488` minulo existující větev `ums-3488-…`, hlídka by prošla a tiket by
se rozjel **dvakrát**. U hlídky větve v existujícím kódu je to naopak — tam
case-insensitive srovnání přijme baton ražený pro jinou větev. Obě hlídky
proto mají opačnou polaritu a u obou musí být důvod napsaný přímo v kódu,
jinak to příští kolo „srovná".

`Plan` se u `ticket-start` **nepoužívá** a jeho kontrola existence na tento
druh nedopadá — v okamžiku spawnu plán ještě neexistuje a existovat nemá.
`Spec` je cesta do některého adresáře `proposals/next/` a musí existovat.
`Base` je nápověda, kterou Intent fáze předvybere, **ne požadavek na
checkout**. Všechny cesty jsou relativní k `MB_ROOT`, kromě `Slot`, který je
absolutní z povahy své funkce.

**`Instruction` je povinný a validovaný.** A2 z něj dělá povinný klíč a A1 z
něj dělá **automaticky vykonaný první tah** — dohromady by to bez validace
znamenalo, že se do sezení doručí až osm kilobajtů libovolného textu jako
první uživatelský vstup, bez jediného lidského kroku mezi tím. Čtenář proto
navíc ověří, že hodnota **obsahuje jméno některého existujícího skillu**
(odvozeno z adresářů skillů vedle hooku) a nepřesahuje krátký strop délky;
zbytek smí být próza. Dnešní zapisovatelé tím dostávají povinnost skill
jmenovat: `writing-plans.overlay.md` už to dělá, `subagent-driven-development.overlay.md`
a `mb-epic-run` to musí dělat taky.

Zapisovatelem `ticket-start` batonu je **jiné sezení** (orchestrátor), ne
sezení, které ho přečte. Precondice zapisovatele má dva konjunkty a slot
splňuje oba: hook je registrovaný, protože slot sdílí trackovaný
`.claude/settings.json` téhož repozitáře, a `CLAUDECODE` je neprázdný,
protože ho launcher **záměrně neodebírá** (sekce 5).

### 4. Briefing tiketu: uzavřený a re-renderovaný

Baton je uzavřený blok ukazatelů se stropem 8 KB — briefing se do něj
nevejde a vejít nemá. Zadání nad rámec ukazatelů proto nese samostatný
soubor, na který baton ukazuje klíčem `Brief`.

**Ten soubor prochází týmiž kontrolami jako baton a agent nikdy nečte jeho
surovou podobu.** Bez toho by `Brief` znovuzavedl přesně tu injekční plochu,
kvůli které je formát batonu uzavřený: `.superpowers/` je git-ignorovaný
scratch, do kterého rutinně zapisují implementátorské subagenty, obsah se
dostane do kontextu modelu — a A1 navíc ruší lidský stisk klávesy, který to
dosud tlumil. Citovat odůvodnění batonu a přitom obrátit jeho závěr by byla
regrese vyslovené bezpečnostní vlastnosti.

Mechanika:

- **Strop velikosti se bounduje na čtení** (nejdřív délka souboru, pak
  obsah), jako u batonu, aby strop nebyl strop až po natažení souboru do
  paměti.
- **Struktura je uzavřená**: posloupnost nadpisů druhé úrovně z pevné
  množiny, s prostým textem v tělech. Neznámý nadpis → stale.
- **Znaková třída platí na celý soubor**: lomená závorka nebo řídicí znak →
  stale. Důsledek pro generátor: briefing **nesmí obsahovat lomené
  závorky**, tedy ani zástupné symboly typu lomená-závorka-TIKET — píší se
  prostá jména.
- **Čtenář briefing re-renderuje do `additionalContext` sám**, nikdy
  neemituje tělo doslova a nepředává agentovi cestu k souboru.
- **Consume-on-read je symetrický s batonem**: po emisi se briefing
  přejmenuje vedle batonu, při zamítnutí na stale variantu. Nemaže se nikdy.

**Umístění:** `<slot>/.superpowers/ticket-brief-<TIKET>.md`. Adresář
`.superpowers/` je git-ignorovaný ve forku i v monorepu (ověřeno: ve forku
`.gitignore:4`, v monorepu `.gitignore:541` pravidlem `/.superpowers/`), takže
soubor nikdy nespadne do commitu. Proti `%TEMP%`, kam se briefingy psaly
ručně, má dvě výhody: leží u práce, ke které patří, a přežije restart
stanice.

**Briefing je anglicky.** Language Contract vyjmenovává task briefy mezi
AI-facing artefakty, které MUSÍ být anglicky, a kritériem je publikum
výstupu, ne druh souboru — briefing konzumuje agent. Míchané jazykové
plochy jsou navíc jmenovaná hard failure ve Fail-Closed Behavior. Pravidlo
se tím **nemění**; jen se přestává obcházet.

**Obsah generuje `mb-epic-run` z ledgeru epiku, Jiry a Memory Bank.** Řídí se
principem „to, co si sezení samo neodvodí, nebo odvodí pozdě a draze":

- **Start** — tiket, větev, báze a commit, že **upstream záměrně chybí a jak
  publikovat**. Tenhle bod poznatky jmenují první a je to zaplacená past:
  `git switch -c X origin/Branches/…` nastaví tracking na **chráněnou** bázi,
  takže pozdější push míří rovnou do integrační linie. Náprava je
  `git branch --unset-upstream` hned po založení a první publikace
  `git push -u origin HEAD`.
- **rozsah** — položky ledgeru s ID a stavem,
- **blokátoři a co tiket blokuje**,
- **špinavé řádky** tiketu, i „žádný", protože to je informace,
- **existuje návrh?** — rozhoduje o celém začátku: bez návrhu
  brainstorming, s předběžným návrhem v `next/` jeho prohloubení a
  aktivace přesunem, ne psaní znovu,
- **pasti** — netrackované zbytky ve stromu (v monorepu reálně vnořené
  repozitáře, které se **nemažou naslepo**), posunuté řádkové odkazy v
  nadřazeném návrhu, neopravené dluhy v návrzích, na kterých tiket stojí,
- **odkazy na hotové sousedství** — sklizené návrhy sousedů a vybrané
  položky playbooku komponenty,
- **co se nemění** — u změn kontraktu stejně důležité jako co se mění.

Do briefingu nepatří nic, co si sezení přečte samo za deset sekund (obsah
tiketu, kontrakt).

### 5. Launcher: vyčištění prostředí a dva adaptéry

**Spawn je frontend-agnostický: baton plus launcher.** Orchestrátor zapíše
baton a briefing do slotu a pak vyvolá launcher, který **jen spustí Claude
Code s cwd = slot**. Na příkazové řádce se nepředává žádný prompt; záměr
doručuje baton a první tah rozjede `initialUserMessage` z amendmentu A1.
Jedna cesta doručení, několik spouštěčů.

**Vyčištění zděděného prostředí je povinná součást spuštění, ne pohodlí.**
Orchestrátor je sám sezení Claude Code, takže potomek zdědí jeho proměnné a
naběhne jako **dětská session s vypnutým transcriptem, s identitou a
messaging rourou rodiče**. Změřeno 2. 9. 2026 (pokus 2). `pool-launch.ps1`
proto před spuštěním odebere ze svého shellu **devět** proměnných:

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
mají. Dva nezávislé důvody, oba dohledané v kontraktu a v kódu:

1. **Precondice zapisovatele batonu** je definovaná jako „harness, jehož
   session-start hooky tato vrstva konfiguruje (`CLAUDECODE` neprázdný), a
   registrovaný hook". Odebrání by v každém spawnutém sezení vyhodnotilo
   precondici jako nesplněnou, takže by sezení muselo **odmítnout napsat
   vlastní baton** — a tím by ztratilo třetí volbu exekuce i pátou stop
   třídu, tedy přesně tu schopnost, kterou `baton_rotace_kontextu` dodal a
   kterou tato práce chce dokončit. Selhalo by to tiše: sezení by správně
   ohlásilo, že se záměr automaticky nedoručí.
2. **Na nasazení `-Scope UserProfile` je `CLAUDECODE=1` JEDINÝ nosič
   publikační záruky.** Ten scope záměrně nenasazuje `settings.json`, takže
   `MB_AGENT_SESSION` tam nedorazí a `pre-push` hook má ve své vstupní bráně
   jen fallback na neprázdný `AI_AGENT` nebo `CLAUDECODE=1`. Odebrání by tam
   spawnuté sezení buď pushovalo s odzbrojenou zárukou, nebo (projde-li
   fáze 0 vstupní brány správně) odmítlo veškerou práci s hlášením „chybějící
   záruka".

Cena ponechání je jen to, že potomek nese značku „běžím uvnitř Claude Code",
což žádný z měřených problémů 2. 9. nezpůsobovalo — ty způsobovaly
`CLAUDE_CODE_CHILD_SESSION` a identitní a messaging proměnné.
`CLAUDE_CODE_USE_POWERSHELL_TOOL` se nechává taky — to je nastavení
uživatele, ne stav sezení.

Odebrání musí být ve **stejném volání** jako spuštění: každé volání
PowerShellového nástroje je čerstvý shell dědící od rodiče, takže odebrání
provedené jinde nemá na spuštění vliv.

Adaptéry — každý právě jeden příkaz, žádný skrytý fallback řetěz:

| Adaptér | Příkaz | Stav |
|---|---|---|
| `terminal` | `wt.exe -d <slot> <claude.exe>` | prokázán 2. 9. (pokus 5) |
| `direct` | `Start-Process <claude.exe> -WorkingDirectory <slot>` | prokázán 2. 9. (pokus 4) |

Cesta ke `claude.exe` se nikdy nepíše natvrdo — táhne se z
`Get-Command claude`. Chybí-li `wt.exe` v PATH, `terminal` vrací stav
`unavailable`, volající to ohlásí a zastaví se; skript sám nikdy nerozhoduje,
který adaptér použít, a nikdy nespadne na jiný.

Volba adaptéru je **argument skillu s derivovaným defaultem**:
`mb-epic-run spawn <TIKET> [-Adapter terminal|direct]`; bez argumentu se
default odvodí sondou stanice (je `wt.exe` v PATH → `terminal`, jinak
`direct`). Žádný konfigurační soubor a žádná cesta stanice v trackovaném
souboru.

`pool-launch.ps1` vrací jedno stavové slovo — `started`, `unavailable` nebo
`error` — a nezapisuje nic než spuštění procesu.

**`pool-provision.ps1` je vynucený nástroj operátora, ne konvence.** Skript
**odmítne běh, když je v prostředí marker agentní relace**, dokud nedostane
explicitní operátorský přepínač; guard je ve skriptu, protože tak putuje s
vrstvou i na harnessy, kde `permissions.deny` neexistuje. Vedle toho jdou do
`permissions.deny` záznamy pro `git worktree` a pro samotný skript, což
Claude Code krytí mechanicky ještě před voláním. Skript dělá:
`git fetch origin`, `git worktree add --detach <cesta> origin/<báze>`, a pak
**z vnitřku nového slotu** ověří, že `git rev-parse --git-path hooks/pre-push`
ukazuje na značkovaný hook v2 — instaluje jen tehdy, když chybí nebo je
starší; sdílený a aktuální hook nepřeinstalovává. Rozpad velikosti hlásí do
konzole.

**Existence procesu není důkaz.** `Get-Process claude` vrátila PID ve všech
třech selháních z 2. 9. Ověření patří k obrazovce uživatele: chybí varování
o transcriptu a první tah skutečně proběhl. Do Jiry jde „běží" teprve po
prvním commitu na větvi tiketu; do té doby je pravdivé jen „větev
připravená, sezení spuštěné".

### 6. Rozhodovací proces: co je bezpečné rozjet

Tohle je ta část, kterou dnes ve vrstvě **nic formálně nepokrývá**. Playbook
umí *jak* spustit; nikde není *co* je bezpečné spustit. Rozhodovalo se ručně
nad ledgerem a grafem.

**Mechanika většinou existuje, chybí join — a dvě orákula mu chybí strojová
tvář:**

| Zdroj | Co už umí | Co chybí |
|---|---|---|
| `mb-epic-graph` | **stavový glyph** slučující Jira stav, odblokovanost podle tvrdých `Blocks` a existenci návrhu, a **vlny** (vlna 0 = odblokováno) | `-Json`; dnes emituje jen markdownovou tabulku a Mermaid |
| `ledger-status.ps1` | **dirty-set** z tabulky `Položka/Tiket \| Zašpiněno oknem \| Důvod \| Vyčištěno oknem`; aktuálně špinavé = prázdný poslední sloupec | `-Json`; dnes emituje jen český textový report |
| `doc-index.ps1` | kolize aktivní práce na cizí větvi a kde leží draft | cílený sken (sekce 9) |
| `pool-status.ps1` | volné sloty a jestli je větev tiketu vyzvednutá jinde | staví se v této práci |

**Obě orákula dostanou `-Json`, ne jedno.** Kdyby ho dostal jen graf, join by
musel parsovat český textový report ledgeru — tedy dělat právě to, co je
důvodem pro `-Json` u grafu, a co [playbook.md](../../playbook.md) zakazuje
(a co je v tomhle prostředí navíc mojibake). Alternativa, znovu-implementovat
parsování ledgerové tabulky v skillu, by vyrobila **druhé orákulum
dirty-setu** — tedy přesně vadu, na kterou verifikace grafu sama míří.

Dirty-set navíc **nemá tiket jako klíč**: klíčem je `Položka/Tiket`, takže
„špinavé řádky tiketu X" se skládají průchodem přes sloupec `Vlastník`
tabulky položek — což `ledger-status.ps1` už dnes uvnitř dělá a co je právě
proto potřeba vystavit, ne opisovat.

**Graf musí dostat informaci o návrzích, jinak je `▶️` nedosažitelné.** Bez
`-ProposalPath` glyph degraduje na `❔` („odblokováno, o návrhu nevím") a bez
`-IndexFile` se draft ležící na větvi jiného aktéra glyphuje `💡` místo
`▶️`. `ready` i `spawn` proto **nejdřív spustí `doc-index.ps1 -Json`** a jeho
výstup předají grafu jako `-IndexFile`, spolu s `-ProposalPath` pro lokální
návrhy — stejné pořadí, jaké `mb-epic-elaboration` už má. Bez toho by tiket,
jehož předběžný návrh leží v klonu kolegy, klasifikoval jako „chybí návrh →
start brainstormingem" a spawnuté sezení by přepsalo existující návrh
vlastním: přesně ta kolize, kvůli které cross-branch viditelnost existuje.

**Glyph sám je past, a to je celý důvod, proč join existuje.** SKODASMS-240
svítilo `▶️` „připraveno k implementaci" a přitom mělo tři špinavé řádky —
jeho zadání přestalo po SKODASMS-239 a SKODASMS-250 platit ve třech bodech.
Kdo se řídí ikonou, postaví mock podle zadání, které dvakrát pozbylo
platnosti. Graf o dirty-setu neví a vědět nemá; rozhoduje teprve průnik.

**Výstup je klasifikace do čtyř tříd s pojmenovaným důvodem u každého
tiketu**, řazená podle vlny a pak podle počtu odblokovaných tiketů. Řazení je
derivované z grafu, ne úsudek. Čtyři třídy, ne tři, protože epik vždy
obsahuje i hotové a rozpracované tikety a ty do žádné z původních tří
nepatřily — klasifikace, která nepokrývá celý epik, není klasifikace:

- **ROZJET** — glyph `▶️`, **žádný otevřený špinavý řádek**, návrh
  dosažitelný, žádná kolize, větev nevyzvednutá jinde, volný slot.
- **ROZHODNI** — startovatelné, ale chybí lidské rozhodnutí, které skill
  udělat nemůže: glyph `💡` nebo `❔`, tedy **odblokováno bez návrhu**.
  Legitimní stav, ale znamená start brainstormingem, ne prohloubení.
- **NEROZJET** — jmenovaný blokátor: **kterýkoli otevřený špinavý řádek** (a
  které to jsou), tvrdá `Blocks` závislost na tiketu, který není
  done-for-planning, větev vyzvednutá jinde, kolize aktivní práce, nebo
  selhavší kolizní orákulum.
- **MIMO** — není kandidát: glyph `✅`, `🧪`, `👀` nebo `🔨`, tedy hotovo,
  v testu či review, nebo už se na tom pracuje. Bez téhle třídy by hotový
  tiket, jehož návrh leží v `completed/` a v `next/` tedy žádný není, spadl
  do ROZHODNI jako „chybí návrh" a nabídl by se k rozjetí brainstormingem.

**Špinavý řádek posílá tiket vždy do NEROZJET.** Původní návrh sem propouštěl
„jeden informativní špinavý řádek" do ROZHODNI, což byly dvě chyby v jedné
větě: třídy se na tom případu překrývaly bez pravidla přednosti, a
„informativní" **není údaj, který dirty-set nese** — ledger má jen otevřeno
či vyčištěno, žádnou závažnost, takže by to join nedokázal spočítat. A je to
zároveň ten jediný sporný případ, který operátor reálně potkal („244 jeden
špinavý řádek + otevřená E-26"), a jehož výsledkem bylo, že se 244 nerozjelo.
Fail-closed čtení tedy odpovídá i tomu rozhodnutí.

**Selhavší kolizní orákulum není „žádná kolize".** Playbook to říká obecně:
negativní běh je jako důkaz bezcenný právě tam, kde je „nic" i legitimní
stav. Join proto rozlišuje tři výsledky kontroly — nalezena kolize, kontrola
proběhla bez nálezu, kontrola **neproběhla** — a třetí je NEROZJET, ne
ROZJET. Jedna měřená příčina neproběhnutí je konkrétní: v čerstvém worktree
chybí `.superpowers/` a `doc-index.ps1 -Json` skončí exit 1 **bez jediné
chybové hlášky**, takže výstup vypadá normálně. Skript proto musí na
chybějící výstupní adresář hlásit, ne mlčet — a `ready`, které do slotů
nezapisuje vůbec, si výstup nesmí ukládat do cizího slotu.

Počet volných slotů se hlásí jako **informace, ne jako limit výběru** —
množinu ke spuštění nevybírá skill, vybírá ji operátor. Doporučení „spusť
tyhle" se záměrně nestaví: svádělo by k řízení se výstupem bez čtení důvodů,
což je přesně past 240.

**Per-tiketová brána je tatáž evaluace zúžená na jeden tiket**, ne druhý
mechanismus. `mb-epic-run spawn <TIKET>` ji spustí nad tím jedním tiketem a
cokoli jiného než ROZJET je fail-closed STOP se jmenovaným důvodem; ROZHODNI
navíc potřebuje výslovný pokyn operátora a zapíše baton bez `Spec`. K
evaluaci se tedy dá dostat i bez spawnu — což je vlastní hodnota:
`mb-epic-run ready` odpoví na „co je připravené", aniž cokoli rozjede.

Nad rámec výčtu výše se pravidla **dopisovat nemají**, dokud se neukáže, co
se opakuje: dirty-set a `Blocks` jsou tu proto, že první je jmenovaná past se
změřeným projevem a druhý se jen konzumuje z grafu, kde už je hotový. Ta
zdrženlivost patří do návrhu, ne do implementace.

### 7. Skill `mb-epic-run`

Sourozenec `mb-epic-elaboration`, stejně jako `mb-epic-graph`. Čtyři operace,
všechny reportované česky.

**`status`** — spustí `pool-status.ps1`, vyrenderuje tabulku a přidá pohled
epiku: u každého tiketu v ledgeru, jestli ho nějaký slot drží. Čistě
read-only. Odpovídá na „jak stojí sloty".

**`ready <EPIK>`** — rozhodovací proces ze sekce 6 nad celým epikem:
klasifikace ROZJET / ROZHODNI / NEROZJET / MIMO s pojmenovaným důvodem u
každého tiketu, řazená podle vlny a počtu odblokovaných tiketů, plus počet
volných slotů jako informace. Čistě read-only, **nezapisuje ani do slotů, ani
mimo ně**. Odpovídá na „co je připravené".

**`spawn <TIKET>`** v tomto pořadí:

1. Rozhodovací proces ze sekce 6 zúžený na tento tiket. Cokoli jiného než
   ROZJET je STOP se jmenovaným důvodem; ROZHODNI pokračuje jen s výslovným
   pokynem operátora a bez `Spec`.
2. Volba slotu z derivovaného stavu.
3. Vytvoření `<slot>/.superpowers/`, pokud chybí — v čerstvém worktree není a
   jeho absence je měřená příčina tichého selhání skriptů.
4. Generování briefingu do `<slot>/.superpowers/ticket-brief-<TIKET>.md`
   (anglicky, uzavřená struktura ze sekce 4).
5. Zápis batonu do `<slot>/.superpowers/session-intent.md`. **Nezkonzumovaný
   baton se nikdy nepřepisuje** — místo toho se ohlásí `baton: pending`.
6. Vyvolání `pool-launch.ps1` se zvoleným adaptérem a ohlášení stavového
   slova česky. **Pořadí je závazné: briefing a baton první, launcher druhý.**
7. Zápis do ledgeru epiku: řádek tiketu si poznamená cestu slotu a čas
   spawnu (obsah ledgeru, česky, jeden řádek) — ledger zůstává jediným
   místem, kde stav elaborace žije.
8. Ověřovací otázky na uživatele podle sekce 5.

**`attach <TIKET>`** — najde slot, který tiket drží, a **vytiskne** operátorovi
další akci. Bez postaveného adaptéru `bg` to není `claude attach <id>`, ale
cesta ke slotu a příkaz, kterým se tam dostane. Tiskne, nespouští za
operátora nic, pokud o to nepožádá.

**Železná pravidla těla skillu.** Orchestrátor nikdy nepřepne (`cd`) do
slotu; nikdy ve slotu nespustí zapisující git příkaz; nikdy ve slotu nic
nemaže ani nepřesouvá; nikdy nespawnuje bez kolizní kontroly; a **STOP musí
slot nechat přesně tak, jak ho našel.** Zápisy do cest slotu jdou z
orchestrátoru přes PowerShell (`New-Item`, `Set-Content`), aby fungovaly pod
existujícím allow-listem a mimo projektový adresář orchestrátoru; jediné
zapisující operace jsou vytvoření `.superpowers/`, briefing a baton.

Frontmatter: `name`, česky formulovaná `description` ve stylu ostatních
`mb-*` skillů (triggering řídí výhradně `description`), `allowed-tools`
zúžené na read-only git, dva skripty a vlastní čtení skillu. Skill se
zapisuje do `SKILLS_MANIFEST.md`.

### 8. Amendmenty čtenáře batonu (A1, A2)

**A1 — `initialUserMessage` vedle `additionalContext`.** Dnes dorazí baton do
modelu jen jako kontext, takže příští sezení dál čeká na stisk klávesy.
`SessionStart` přijímá `initialUserMessage`, který se odešle jako první
uživatelský tah. Hook emituje obojí:

- `hookSpecificOutput.hookEventName` = `SessionStart`
- `hookSpecificOutput.additionalContext` = vyrenderovaný blok, plus
  re-renderovaný briefing, je-li přítomen
- `hookSpecificOutput.initialUserMessage` = pevný anglický text, který
  říká, že dorazil baton, že **první mají přednost bootstrap kontroly** a že
  baton nikdy nepřebíjí fail-closed bránu, a teprve pak se jedná podle řádku
  `Instruction`.

Emituje se **jen když se emituje baton**; každá stale i absentní cesta
zůstává tichá jako dnes.

Důsledky: delivery mode 1 (`/clear`) se stává bezzásahovým a delivery mode 2
(spawn-and-abandon) se stává vůbec proveditelným — jak je navržený dnes, by
nová karta spuštěná bez promptu čekala na prompt navždy. Mode 2 sám zůstává
mimo rozsah; opravuje se jen text.

**A1 ruší jediný lidský krok na cestě batonu, a to je bezpečnostní změna, ne
jen pohodlí.** Dokud první tah vyžadoval stisk klávesy, operátor viděl
kontext, na který se má jednat. Po A1 už ne. Proto je s A1 nedělitelně
svázaná validace `Instruction` a uzavření briefingu (sekce 3 a 4) — bez nich
je A1 automatické vykonání nevalidovaného textu ze git-ignorovaného
scratche.

**A2 — `Instruction` je povinný klíč.** Kontrakt říká „poslední řádek je
jediný `Instruction:`", hook ho ale vede jen v `$RenderOrder`. Rozpor se
řeší na straně kontraktu: `Instruction` přibude do `$Required`, dostane
validaci obsahu (sekce 3), test na baton bez něj i na baton s hodnotou, která
žádný skill nejmenuje, a formulace kontraktu řekne „povinný" výslovně.

**Zapisovatele to mění a oprava fragmentu patří do TÉHOŽ tasku.** Overlay
fragment `writing-plans.overlay.md` `Instruction` jmenuje, ale
`subagent-driven-development.overlay.md` ve svém výčtu klíčů páté stop třídy
**ne** — vyjmenovává `Kind`, cestu plánu, cestu ledgeru, větev, slug a číslo
dalšího tasku. Sezení jdoucí podle overlaye doslova by po zpřísnění napsalo
baton, který hook zamítne jako stale. **A tohle je pro tento plán akutní, ne
teoretické:** plán se vykonává pod SDD a počítá s rotací kontextu na hranicích
tasků, takže mezi zpřísněním a opravou fragmentu by každá rotace tiše
ztratila předání. Editace fragmentu proto jde do stejného tasku jako A2 —
nemá na nic dalšího závislost; poslední zůstává jen revendor, který
vygenerované soubory dorovná.

### 9. Cílený sken v `doc-index.ps1`

Vstupní brána vyžaduje meziclonovou kolizní kontrolu a `mb-epic-run` ji
vyžaduje taky. `doc-index.ps1` s deklarovaným záměrem (`-Jira`, `-Slug`) ale
na monorepu **nedoběhne**: deklarovaný záměr vypíná časové okno a skript
prochází historii všech větví, kterých je na `origin` přes tři stovky. Při
vstupní bráně SKODASMS-238 běžel `-NoFetch` **přes 25 minut bez jediného
řádku výstupu a musel být zabit**. Fail-closed STOP, který má chránit před
tichou kolizí, je tam tedy dnes nedosažitelný.

Skript dostane **režim cíleného skenu**, který se použije při deklarovaném
záměru: dvě smyčky nad `git for-each-ref refs/remotes/origin/` — jedna hledá
cestu `proposals/active/*<slug>*` přes `ls-tree`, druhá čte `context.md`
každé větve a hledá kód tiketu — bez traversalu historie a bez
`git branch -r --contains` na každý commit. Cílený sken přes 321 větví
doběhne asi za minutu.

Druhá, nezávislá oprava téhož skriptu: **chybějící výstupní adresář se musí
ohlásit.** V čerstvém worktree `.superpowers/` neexistuje a `-Json` do něj
skončí exit 1 bez jediné hlášky, takže volající to nemá jak odlišit od
„proběhlo bez nálezu" — a v rozhodovacím procesu je ten rozdíl mezi NEROZJET
a ROZJET.

Oprava patří do `doc-index.ps1`, ne do `mb-epic-run`: pravidlo má jeden domov
a kolizní kontrolu implementuje víc konzumentů (Target-MB discovery,
`mb-state`, `mb-epic-elaboration`). Druhá implementace téže kontroly v těle
nového skillu by rozhodnutí „koliduje to?" přestala dělat strojově na jednom
místě.

Že měřený čas neodpovídá tomu, co o výkonu `doc-index.ps1` tvrdí náš
[tech.md](../../tech.md) (32–35 s s `-NoFetch`, 57 s s deklarovaným záměrem,
při 219 vzdálených větvích), je nález k narovnání při harvestu — mezi tím
měřením a tímhle vzrostl počet větví na 321 a rozdíl je řádový, ne o pár
procent.

### 10. Změny kontraktu (2.13)

- **Worktree Policy** — zákaz zůstává, ale **jeho odůvodňující měření
  neobstojí a musí se přepsat**, ne jen doplnit výjimkou. Kontrakt dnes
  tvrdí, že klon monorepa zabírá 25 GB, z toho `.git` 4,1 GB, takže linked
  worktree ušetří 16 %, „což nezaplatí ten další strom". Měřeno 2. 9. 2026:
  slot má 7,7 GB, sdílený `.git` 4,4 GB a hlavní klon 27,2 GB — úspora je
  tedy asi **70 %, ne 16 %**, protože rozdíl mezi slotem a hlavním klonem je
  naakumulovaný build output, ne zdroj. Věta, která nese celou váhu zákazu
  („zákaz stojí na měření, ne na dojmu"), se tím stává nepravdivou; nechat ji
  stát by znamenalo, že příští čtenář buď uvěří nepravdivým 16 %, nebo si
  zákaz nedovodí z ničeho. Nová formulace: zákaz zůstává z důvodů, které
  nejsou o disku (jedno sezení na workspace, žádná agentní provisionace),
  a disk se popíše měřenými čísly.
  K tomu výjimka poolu v jednom odstavci: slot je uživatelem provisionovaný
  linked worktree, který žije napříč mnoha tikety a hledí se na něj jako na
  nalezený workspace; agentem vytvořené worktrees zůstávají zakázané; idle
  slot je detached nebo na větvi jménem shodné s adresářem slotu, ale **o
  IDLE rozhoduje výhradně pin, nikdy jméno větve**. Sdílený `.git` znamená, že
  jednou instalovaný `pre-push` guard pokrývá každý slot a
  `git rev-parse --git-path hooks/pre-push` ho z každého slotu najde — s
  poznámkou, že z primary worktree vrací tentýž příkaz **relativní** cestu,
  takže srovnání na identitu potřebuje normalizaci.
- **Workspace Discipline** — dvě věci, ne jedna. Jedna věta, která slot poolu
  pojmenuje jako workspace ve smyslu kontraktu („jedno sezení na workspace"
  platí per slot). A **oprava derivace „volný workspace" pro pool**: dnešní
  trojice `status` + `stash list` + `log --branches --not --remotes` je
  napsaná pro jeden klon na jeden `.git`; v poolu jsou `refs/stash` i
  `refs/heads` sdílené, takže druhý a třetí signál dávají ze všech slotů
  totožnou odpověď. Kontrakt musí říct, které signály jsou per-worktree a
  které ne, že stash se slotu přiřadit nedá, a že čtvrtý signál (kandidát
  playbooku) je definovaný **jen vůči aktuálnímu slugu**, takže v IDLE slotu
  nepřipadá v úvahu — cizí kandidát zůstává „merely present", jak už kontrakt
  jinde říká.
- **Session Intent Baton** — `Kind: ticket-start`, per-druhové povinné klíče
  **a per-druhový whitelist** (dnes ho zastupuje `$RenderOrder`), nový klíč
  `Slot` jako origin binding, volitelné `Spec` a `Brief`, nepoužitý `Plan`,
  čtyři hlídky, validace tvaru `Ticket` a case pravidlo hlídky větve s
  důvodem, `Instruction` povinný **a validovaný** pro všechny druhy,
  uzavření a re-render briefingu čtenářem, a věta o tom, že zapisovatelem
  `ticket-start` je jiné sezení a čím jsou u slotu splněny **oba** konjunkty
  precondice zapisovatele.
- **Repository Configuration** — **žádný `pool` blok.** Členství v poolu je
  derivované, takže konfigurace nevzniká; informational-only status
  `ums-repo.json` u vstupní brány zůstává nedotčený. Zapsat ale, že seznam
  odebíraných proměnných a cesta ke `claude.exe` **nejsou** repozitářová
  konfigurace (`claude.exe` se hledá, seznam je vlastnost harnessu), aby
  věta „žádná repozitářově specifická hodnota nesmí žít v těle skillu nebo
  skriptu" zůstala pravdivá a nebyla čtena jako porušená.
- **Workspace Discipline / provisionace** — dvě věty přestávají platit tak,
  jak jsou napsané, a musí se upravit jmenovitě: „vrstva hledí na workspace
  jako na nalezený, **nikdy jako na čerstvě provisionovaný**" a „sezení běží
  ve workspace, kde práce už je, a **nikdy neprovisionuje jiný**". Pool
  provisionaci zavádí — ale výhradně pro uživatele, vynuceně (guard ve
  skriptu plus `permissions.deny`), takže úprava je zúžení na aktéra, ne
  zrušení pravidla.
- **Language Contract** — pravidlo se **nemění** a briefing se mu podřizuje:
  je to task brief, tedy AI-facing, tedy anglicky. Doplní se jen poznámka, že
  launcher a status skripty jsou vývojářské nástroje vrstvy (anglicky),
  zatímco reporty `mb-epic-run` jsou pro člověka (česky).

### 11. Integrace do `mb-epic-elaboration`

`SKILL.md` fáze 7 (Close) a `protocol.md` §3.3: po publikaci se spustí
`mb-epic-run ready` nad epikem — uzávěrka okna tím dostane rovnou přehled, co
je připravené a co ne a proč — a u tiketů ve třídě ROZJET se **nabídne**
`mb-epic-run spawn`: nabídka, jedna otázka, rozhodne operátor per tiket.
Pořadí je záměrné: klasifikace před nabídkou, aby nabídka nevznikla u tiketu,
který má špinavé řádky. Přidá se řádek do quick-reference. Jsou to soubory
vrstvy, edituje se přímo, žádný overlay.

`ledger-template.md` dostane konvenci pro poznámku o slotu. **Tady nestačí
„stávající sada zůstane zelená"** — ta je zelená před i po změně a žádnou
poznámku o slotu nikdy neuvidí, takže by to byl regresní zámek, ne důkaz.
Sada dostane **fixturu, která poznámku o slotu nese**, protože parser
tabulek ledgeru končí na prvním řádku bez svislítka a indexuje sloupce
pozičně — a spawn do ledgeru zapisuje při každém spuštění, takže rozbití by
zavedla hot path té nové funkce.

### 12. Sweepy: co tato práce činí nepravdivým

Po změně pravidel je potřeba projít restatementy, které grep na jméno
měněného pojmu nenajde:

- **Bump verze kontraktu je vlastní sweep** — `grep -rn '2\.12' ums/
  memory-bank/ CLAUDE.md`, nálezy rozdělit podle vlastníka: **soubory vrstvy
  opraví implementace ve stejném commitu jako pravidlo; dokumenty Memory Bank
  opraví harvest** (živé zásahy: `architecture.md` na třech místech,
  `brief.md` na dvou, `tech.md`). Dvě skupiny navíc nepatří ani do jedné:
  archiv v `proposals/completed/` se **nikdy needituje**, i když verzi
  obsahuje, a legacy `tasks.md` je potřeba rozhodnout jmenovitě.
- **Počítací a jedinečnostní fráze** — Worktree Policy dnes tvrdí zákaz bez
  výjimky a jeho měření jako uzavřený argument; Workspace Discipline tvrdí
  „nikdy jako čerstvě provisionovaný". Slovník sweepu:
  `jediná|jediný|přesně|nikdy|vždy|žádná výjimka|only|never|exactly|the one|
  single`.
- **Věty, které stojí na měření disku** — 16 % úspory, 25 GB klon, 4,1 GB
  `.git`. Sweep na čísla, ne na pojmy.
- **Inventáře podle druhu artefaktu, ne podle jména** — `tech.md` (počty
  sad, součty asercí, inventář nástrojů, řádek `settings.json`),
  `ums/README.md` (adresářové stromy, matice harnessů),
  `SKILLS_MANIFEST.md`. Grepovat na jména **sourozeneckých** artefaktů, ne
  na jméno nového skillu, který zatím nikde neleží.
- **Věty o batonu, které předpokládají dva druhy** — sekce Session Intent
  Baton v [architecture.md](../../architecture.md), hlavička hooku, testy.
  A věty, které tvrdí, že `$RenderOrder` je whitelist.
- **Věty o `doc-index.ps1` jako o read-only nástroji s daným výkonem** — po
  přidání cíleného skenu se mění obojí.
- **Věty, které stavovému glyphu `mb-epic-graph` přisuzují rozhodovací
  pravomoc.** Glyph `▶️` se čte jako „připraveno k implementaci", ale sám o
  dirty-setu neví. `mb-epic-graph/SKILL.md` dostane **jednořádkovou křížovou
  referenci** na to, že o rozjetí rozhoduje join v `mb-epic-run`, ne glyph —
  odkaz, ne zduplikované pravidlo. Prohledat i `architecture.md`, popis
  glyphů a text, který jde do popisu epiku v Jiře.

## Odchylky od zadání a jejich důvody

Zadání (`dispatch-brief-ticket-pool-orchestration.md`, 2. 9. 2026 15:05) bylo
psané **před** poznatky z ručních pokusů (`poznatky-spousteni-agentu.md`,
15:26) a bez znalosti stavu poolu v monorepu. Odchylky jsou proto doplnění
měřenou zkušeností, ne nesouhlas se záměrem.

| Zadání | Návrh | Důvod |
|---|---|---|
| Part A je aktivní nedotestovaná položka, dokončit ji a pak Part B | A1+A2 jsou první tasky jednoho plánu s Part B | `baton_rotace_kontextu` je už sklizený (návrh v `completed/`, plán smazán, `context.md` IDLE) a integrovaný; archiv v `completed/` je neměnný. Rozhodnutí operátora ze 2. 9. |
| JIRA-less, slug `pool_orchestrace_tiketu` | UMS-3488, slug `ums_3488_pool_orchestrace_tiketu` | Tiket na tuhle práci existoval už 12:30 pod jménem `mb-epic-dispatch`; jméno skillu zůstává `mb-epic-run` a summary tiketu se přepíše při finalizaci |
| FIXED 3: idle slot je detached | detached **nebo** větev jménem shodná s adresářem slotu, ale o IDLE rozhoduje **výhradně pin** | Pool drží `ums04` na větvi `ums04` — a měřeno má přitom ACTIVE pin, takže skutečná konvence je „vlastní větev slot zaparkuje", ne „idle". Tvar se přijímá kvůli uvolnění větve vyzvednuté jinde, ne jako indikátor stavu |
| FIXED 4 / B1: `pool.root` v `ums-repo.json` | žádná konfigurace, členství derivované z `git worktree list` | `ums-repo.json` je trackovaný a sdílený s `pmq_logopedie_nr`, takže absolutní cesta stanice do něj nepatří; derivace je navíc věrnější FIXED 4 („nikdy záznam") a dala v monorepu přesně `ums01..ums04` |
| FIXED 4: volnost ze `status` + `stash list` + `log --branches` | jen per-worktree signály; stash se slotu nepřiřazuje, kandidát playbooku je mimo volnost | `refs/stash` i `refs/heads` jsou v poolu **sdílené** (změřeno), takže druhý a třetí signál by udělaly každý slot navždy nevolným; kandidát cizího slugu kontrakt jinde výslovně nepovažuje za selhání |
| FIXED 4: ledger z `.superpowers/sdd/*/progress.md` | ledger se páruje na slug z pinu | `ums03` má **oba** ledgery a cizí se řadí první, takže „první nalezený" by hlásil cizí postup |
| FIXED 5: čtyři adaptéry (`vscode`, `terminal`, `deeplink`, `bg`) | `terminal` + `direct` | Jen tyhle dva jsou prokázané. `vscode` a `deeplink` by šly poslat nepotvrzené — a lekce dne je, že nepotvrzené spuštění vypadá jako úspěch. `bg` by dal liveness, ale běží mimo obrazovku, kde se ověřuje |
| FIXED 5: „launcher jen spustí Claude Code" | povinné vyčištění devíti proměnných před spuštěním | Bez toho naběhne dětská session s vypnutým transcriptem — pokus 2 z 2. 9. Zadání tuhle třídu problému vůbec nezmiňuje |
| Poznatky: odebrat i `CLAUDECODE` | `CLAUDECODE` se **nechává** | Odebrání by ve spawnutém sezení zneplatnilo precondici zapisovatele batonu (a tím rotaci kontextu), a na nasazení `-Scope UserProfile` je to **jediný** nosič publikační záruky |
| Poznatky: seznam čištěných proměnných nedávat natvrdo | seznam je v `pool-launch.ps1` | Je to vlastnost harnessu, ne repozitáře — proto nepatří do `ums-repo.json`. Uvedeno jako odchylka, protože poznatky ho jmenují vedle položek, které do konfigurace opravdu patří (cesta ke `claude.exe`, adresář poolu, jména větví) |
| B4.1: eligibilita bez dirty-setu | brána nese dirty-set a jmenuje řádky; **kterýkoli** otevřený řádek → NEROZJET | Jmenovaná past s měřeným projevem. „Informativní řádek" nejde spočítat — ledger závažnost nenese — a fail-closed čtení odpovídá i tomu, jak operátor 244 reálně rozhodl |
| Rozhodnutí, **které** tikety rozjet, brief neřeší vůbec | čtvrtá operace `ready <EPIK>`, klasifikace do **čtyř** tříd | Ve vrstvě to dnes formálně nepokrývá nic. Čtvrtá třída MIMO je nutná, protože epik vždy obsahuje hotové a rozpracované tikety — bez ní hotový tiket spadne do ROZHODNI jako „chybí návrh" |
| Odblokovanost podle `Blocks` odložena | zařazena hned | Nepíše se nová logika — graf ji už počítá do glyphu a do vln; join ji jen konzumuje |
| — | `epic-graph.ps1` **a** `ledger-status.ps1` dostanou `-Json` | Obě orákula dnes emitují jen prózu. Kdyby ho dostal jen graf, join by parsoval český report ledgeru nebo si vyrobil druhé orákulum dirty-setu |
| — | `ready`/`spawn` spustí `doc-index -Json` a předají ho grafu jako `-IndexFile` | Bez informace o návrzích glyph degraduje na `❔` a draft na cizí větvi se glyphuje `💡`, takže `▶️` je nedosažitelné a spawn by přepsal cizí návrh |
| Baton nese jen ukazatele | volitelný klíč `Brief`, briefing **uzavřený a re-renderovaný hookem**, anglicky | Briefing souborem je to, co obě úspěšná spuštění udělalo funkčními; ale surový soubor v git-ignorovaném scratchi je injekční plocha, kterou uzavřený formát existuje eliminovat — a A1 ruší lidský krok, co ji tlumil |
| — | `Slot` jako povinný klíč `ticket-start` | Bez něj nemá ten druh **žádnou** origin binding a kterýkoli čistý IDLE slot přijme kterýkoli baton — sezení otevřené s úmyslem dělat T2 rozjede T1 |
| — | validace `Instruction` (jméno skillu + strop) a tvaru `Ticket` | A1+A2 z `Instruction` dělají automaticky vykonaný první tah; bez validace tvaru `Ticket` je hlídka větve vakuózní |
| B3: `pool-provision.ps1 -Root -Count` zakládá `slot-<n>` | `-Path <dir> -Base <ref>`, jeden slot na volání, **s guardem proti agentní relaci** | Bez konfigurovaného rootu není z čeho jméno derivovat a pool má vlastní konvenci. „Nástroj operátora" nesmí vynucovat próza, když `permissions.deny` skript nekryje |
| B7: bez změny overlay fragmentů | jeden řádek v `subagent-driven-development.overlay.md`, **v témž tasku jako A2** + revendor | Fragment `Instruction` nejmenuje, takže by A2 udělalo z jeho batonů stale — a to akutně pro tento plán, který sám rotuje kontext na hranicích tasků |

## Dopady

**Na existující práci v poolu.** Nic se nemigruje. Čtyři slotové worktrees
zůstávají, jak jsou. Měřeno 2. 9. 2026: špinavých záznamů má ums01 **34**,
ums02 **222**, ums03 **221**, ums04 **0** — a ums04 přitom nese ACTIVE pin.
**Žádný slot v poolu tedy dnes není volný**, takže end-to-end verifikace
vyžaduje jako předpoklad provisionovat nový slot; není to volitelný krok.

**Na vstupní bránu.** Cílený sken v `doc-index.ps1` zpřístupní fail-closed
kolizní STOP na monorepu, kde je dnes nedosažitelný. To je zpřísnění: práce,
která dřív prošla, může začít narážet na kolize, které tam byly celou dobu.

**Na batony napsané před touto změnou.** Baton bez `Instruction`, nebo s
hodnotou, která žádný skill nejmenuje, se po A2 stane stale. Je to
git-ignorovaný scratch s životností minut, takže cena je nulová **pro cizí
sezení** — ale nikoli pro tento plán: mezi A2 a opravou overlay fragmentu by
každá jeho vlastní rotace kontextu tiše ztratila předání, což je důvod, proč
obojí jde do jednoho tasku.

**Na nasazení.** Změny zdroje v `ums/.claude/` je potřeba nasadit do
kořenového `.claude/` (a `.agents/skills/`), jinak sezení v tomto repu
pracuje se starou verzí. Změna overlay fragmentu navíc vyžaduje revendor —
plný jednoprůchodový běh s pinovaným tagem, ne `-OverlaysOnly`, protože
nasazené vendorované soubory už overlay bloky nesou.

**Na Kilo Code a ostatní harnessy.** `mb-epic-run`, kontrakt a briefing jsou
čistý Markdown a přenesou se; `initialUserMessage` je mechanismus Claude Code
a jinde spawn zůstane s ručním prvním tahem. Guard v `pool-provision.ps1`
putuje se skriptem, `permissions.deny` ne — proto je nosnou polovinou guard.

## Rizika

**`initialUserMessage` nemusí ve VS Code extension fungovat.** Na tom stojí
bezzásahový start celého spawnu, a operátor pracuje právě v extension.
Ověření je operátorské a je zastavovacím bodem verifikace — **se kontrolním
během mimo extension**, protože bez něj by se selhání nedalo přiřadit:
„extension pole ignoruje" a „to pole nectí žádný harness" vypadají stejně.
Když extension pole ignoruje, návrh to zapíše jako známé omezení toho
frontendu, položka se dokončí a obchází se to ručním prvním tahem —
**workaround se nestaví**.

**Precondice zapisovatele batonu ve spawnutém sezení je tvrzení k ověření.**
Ponechání `CLAUDECODE` ji má zachovat, ale že spawnuté sezení skutečně smí
napsat vlastní baton, se musí změřit v tom sezení, ne dovodit. Vlastní bod
verifikace.

**Pravidla brány stojí na jediném rozhodování.** UMS-3488 sám doporučuje
psát je až po druhém až třetím rozjetí. Riziko se tlumí tím, že se do brány
dostal jen dirty-set — jmenovaná past se změřeným projevem — a `Blocks`,
které se jen konzumují z hotového orákula.

**Worktree, který operátor používá k jinému účelu, se objeví v tabulce
poolu.** Derivace nemá jak poznat záměr. Tlumeno tím, že takový worktree
nebude nikdy „volný" (špinavý strom, pin nebo baton), takže se do něj
nespawnuje; a spawn hlásí, který slot vybral.

**Slot něco stojí na disku, ale méně, než se čekalo.** Sdílený `.git` se
neduplikuje, pracovní strom ano. Změřeno: slot `ums04` **7,7 GB / 80 022
souborů**, sdílený `.git` **4,4 GB**, hlavní klon **27,2 GB / 140 365
souborů** — rozdíl je naakumulovaný build output, ne zdroj. Čerstvý slot je
tedy asi 8 GB a roste s tím, co se v něm postaví.

**Orchestrátor zapisuje do cizího pracovního stromu.** Tlumeno železnými
pravidly ze sekce 7 a tím, že se píše výhradně do git-ignorovaného
`.superpowers/`, a to jen tři věci: adresář, briefing, baton.

## Verifikace

1. **Testy hooku zeleně** včetně nových případů `ticket-start` — happy path
   (detached HEAD i scratch větev, čistý strom, IDLE, s `Spec` i bez, s
   `Brief` i bez), každá ze čtyř hlídek selhávající jednotlivě, `Slot`
   ukazující jinam → stale, `Ticket` neodpovídající `ticketPattern` → stale,
   `Spec` a `Brief` mířící na neexistující soubor, `Plan` přítomný a
   ignorovaný, `Brief` na batonu druhu `plan-execution` → odmítnut
   per-druhovým whitelistem, staré druhy nedotčené novou sadou povinných
   klíčů, `initialUserMessage` přítomný na happy path a **nepřítomný** na
   stale cestě, baton bez `Instruction` → stale, `Instruction` nejmenující
   žádný skill → stale, `Instruction` nad stropem → stale. K hlídce 3 navíc
   **vyhrazený případ na case**: existující větev `ums-3488-x` proti batonu
   s `Ticket: UMS-3488` musí skončit stale. Počet asercí zjištěný spuštěním
   celé sady v témž sezení a zapsaný do ledgeru.
2. **Uzavření briefingu.** Briefing s neznámým nadpisem → stale; briefing
   obsahující lomenou závorku → stale; briefing nad stropem → stale (a strop
   se uplatní **před** natažením obsahu); briefing na happy path
   re-renderovaný do `additionalContext`, přičemž emitovaný text neobsahuje
   cestu k souboru; po emisi přejmenovaný vedle batonu. Negativitu ověřit
   mutací: bez kontroly znakové třídy musí případ s lomenou závorkou
   zčervenat.
3. **Volnost slotu proti skutečnému sdílenému `.git`.** Fixtura s několika
   linked worktrees, ne simulace. Regresní důkaz k F1: **stash vytvořený v
   jednom worktree nesmí udělat jiný slot nevolným**, a **nepushnutý commit
   na větvi A nesmí udělat nevolným slot stojící na větvi B**. Bez téhle
   fixtury je celá derivace nedokázaná — a s původní, kontraktovou trojicí
   signálů oba případy zčervenají, což je ta žádaná negativita.
4. **Testy skriptů zeleně**; `pool-status.ps1` nad fixturou (volný detached,
   tiketová větev s ACTIVE pinem, špinavý detached, slot s **oběma** ledgery,
   kde se cizí řadí první, slot s cizím kandidátem playbooku, `prunable`
   záznam) vyrenderuje správné řádky a cizí kandidát **nesmí** slot udělat
   nevolným.
5. **Vyčištění prostředí.** Potomek vypíše `Env:` do souboru; kontrola
   nepřítomnosti všech **devíti** proměnných a **přítomnosti**
   `CLAUDE_CODE_USE_POWERSHELL_TOOL` i `CLAUDECODE`.
6. **Precondice zapisovatele ve spawnutém sezení** — v tom sezení ověřit, že
   `CLAUDECODE` je neprázdný a hook registrovaný, tedy že sezení smí napsat
   vlastní baton. Tohle je jediný důkaz, že rotace kontextu ve slotu funguje.
7. **Publikační záruka ve spawnutém sezení.** V něm ověřit, že
   `MB_AGENT_SESSION` je nastavený a že syntetický protected-branch pipe
   přes rozřešený hook skončí nenulově — a zrcadlová accept case nulou.
8. **Cílený sken `doc-index.ps1`** — proti fixture repu (nové asercie) a
   **proti skutečnému monorepu**, kde má doběhnout a odpovědět; naměřený čas
   zapsat. Plus: běh s chybějícím `.superpowers/` musí **ohlásit chybu**, ne
   tiše skončit exit 1.
9. **Selhavší kolizní orákulum → NEROZJET.** Vynucené selhání kontroly nesmí
   dát ROZJET. „Nic nenalezeno" a „neproběhlo" musí být v klasifikaci
   rozlišitelné.
10. **Rozhodovací proces: odmítnutí se jmenovaným důvodem.** Fixtura
    reprodukuje stav z 2. 9. 2026: tiket s glyphem `▶️` a **třemi** špinavými
    řádky musí skončit v NEROZJET a **jmenovat ty řádky** — akceptační
    kritérium č. 1 z UMS-3488 a jediný důkaz, že join nepřebírá verdikt z
    glyphu. Dál: tiket s **jedním** otevřeným špinavým řádkem → NEROZJET (ne
    ROZHODNI), tiket bez návrhu → ROZHODNI, hotový a rozpracovaný tiket →
    MIMO (ne ROZHODNI), tiket blokovaný neuzavřeným předchůdcem → NEROZJET
    s jménem blokátoru, čistý tiket → ROZJET. Řazení: vlna vzestupně, pak
    počet odblokovaných klesající. Glyph se přitom počítá **s**
    `-ProposalPath` a `-IndexFile`, jinak je `▶️` nedosažitelné a celá
    fixtura by testovala degradovanou cestu.
11. **`epic-graph.ps1 -Json`** — asercie na tvar (klíč, vlna, glyph, přímé
    blokátory, počet odblokovaných, fáze návrhu) a na to, že `-Json` a
    tabulka vln dávají pro tutéž fixturu **shodné** glyphy a vlny.
12. **`ledger-status.ps1 -Json`** — asercie na tvar dirty-setu včetně
    průchodu přes vlastníka položky, a **fixtura ledgeru nesoucí poznámku o
    slotu**, která musí naparsovat. Samotné „stávající sada zůstala zelená"
    se za důkaz nepočítá.
13. **`pool-provision.ps1` guard** — běh s markerem agentní relace bez
    operátorského přepínače musí odmítnout; s přepínačem projít.
14. **`initialUserMessage` — OPERÁTORSKÝ KROK, ZDE SE ZASTAVÍM.** Postup:
    otevři v tomto workspace čerstvé sezení extension (nové okno, nebo
    `/clear`) ve chvíli, kdy v `<MB_ROOT>/.superpowers/session-intent.md`
    leží platný baton — platný znamená, že projde hlídkami svého druhu.
    Pozoruj **jedinou věc**: rozjede sezení první tah samo, bez tvého stisku
    klávesy? **Pak totéž zopakuj v CLI mimo extension** — bez toho
    kontrolního běhu nelze selhání přiřadit frontendu. Oba výsledky zapiš do
    tohoto návrhu **před harvestem**. Ignoruje-li pole extension a CLI ho
    ctí, je to zapsané omezení toho frontendu a položka se dokončí;
    workaround se nestaví.
15. **End-to-end spawn — OPERÁTORSKÝ KROK.** Předpoklad: **provisionovat
    nový slot**, protože žádný ze čtyř dnešních volný není. Z orchestrátoru
    spusť `mb-epic-run spawn <TIKET>` s adaptérem `terminal`; pozoruj, že
    nové sezení rozjede první tah bez zásahu, projde vstupní bránu, založí
    tiketovou větev a aktivuje draft. Pak `mb-epic-run status` ukáže slot
    jako ACTIVE se slugem. Zopakuj s adaptérem `direct`. Ověření podle
    sekce 5: **není** tam `⚠ Transcript saving is off` a první tah skutečně
    proběhl.
16. **Negativní: dvakrát tentýž tiket** → STOP kolizí, nebo odmítnutým
    checkoutem gitu; slot nedotčený, nic nezapsáno.
17. **Negativní: pool, kde je jediný slot špinavý** → report, žádný zapsaný
    baton ani briefing.
18. **Negativní: repozitář bez linked worktree** → `mb-epic-run` fail-closed
    odmítne českou hláškou, která to říká. Testuje se na **tomto forku**,
    který přesně takový je.
19. **Sweepy ze sekce 12 provedené**, s rozdělením podle vlastníka: soubory
    vrstvy opravené ve stejném commitu jako pravidlo, dokumenty Memory Bank
    předané harvestu jmenovitým seznamem, archiv `completed/` nedotčený.

## Pořadí úloh

1. **Kontrakt 2.13** — pravidlo má jeden domov, takže kontrakt jde **před**
   implementací kteréhokoli z těch pravidel, A2 nevyjímaje. Původní pořadí
   dávalo A2 před kontrakt a tím si samo odporovalo.
2. **A1+A2 + oprava overlay fragmentu** — čtenář batonu:
   `initialUserMessage`, `Instruction` do `$Required` s validací, a
   `Instruction` do výčtu v `subagent-driven-development.overlay.md`
   (zdrojový fragment; revendor až v posledním tasku). Verifikuje se
   **izolovaně**, dřív než se sáhne na `ticket-start`.
3. **Hook: `ticket-start`** — per-druhové povinné klíče i whitelist, klíč
   `Slot`, čtyři hlídky, validace tvaru `Ticket`, case pravidlo, testy.
   Verifikuje se izolovaně.
4. **Hook: uzavření a re-render briefingu** — strop, uzavřená struktura,
   znaková třída, consume-on-read, testy. Vlastní task, aby selhání
   end-to-end běhu nemělo dvě kandidátní příčiny.
5. **`doc-index.ps1`** — cílený sken, ohlášení chybějícího výstupního
   adresáře, testy, měření proti monorepu.
6. **`epic-graph.ps1 -Json`** + testy včetně shody s tabulkou vln.
7. **`ledger-status.ps1 -Json`** + testy včetně fixtury s poznámkou o slotu.
8. **Tři pool skripty** + testy, včetně fixtury se skutečným sdíleným
   `.git` pro volnost slotu a guardu v `pool-provision.ps1`.
9. **Skill `mb-epic-run`** — čtyři operace, plus `SKILLS_MANIFEST.md` a
   jednořádková křížová reference v `mb-epic-graph/SKILL.md`.
10. **Integrace do `mb-epic-elaboration`** + zelené `ledger-status.ps1`.
11. **Dokumentace** — README skillu (anglicky) a český průvodce, včetně
    pohodlí stanice z B6.
12. **`permissions.deny`, nasazení a revendor** — záznamy pro `git worktree`
    a `pool-provision.ps1`, obnova nasazené kopie, plný revendor s pinovaným
    tagem.

Každá úloha končí commitem přes `mb-git-commit` a publikací tiketové větve
(první publikace `git push -u origin <větev>`, protože `switch -c` nechal
upstream na bázi).

## Navazující položky

- **Delivery mode 2 batonu** (spawn-and-abandon) je po A1 proveditelný, ale
  nestaví se.
- **Adaptéry `vscode`, `deeplink`, `bg`** — každý je malý task, ale každý
  potřebuje vlastní operátorské ověření. `bg` je z nich nejcennější: dal by
  `pool-status.ps1` skutečný zdroj liveness a `attach` skutečné
  `claude attach <id>`.
- **Vážení a doporučení množiny ke spuštění** („spusť tyhle tři") se
  nestaví. Rozhodovací proces klasifikuje a řadí; výběr dělá operátor. Až
  bude víc rozjetí za sebou, ukáže se, jestli je vážení vůbec potřeba.
- **`NO_COLOR`** — neověřeno, jestli po odebrání barvy skutečně naskočí, a
  jestli není potřeba i `FORCE_COLOR=1`.
- **Proč selhal `cmd.exe /k` s batchem** (pokus 1 z 2. 9.) — nerozebráno.
  Netýká se žádného stavěného adaptéru.
- **Ve `wt.exe` nelze mít v argumentu středník** — u spawnu bez promptu to
  nevadí, ale kdyby se prompt na příkazovou řádku někdy vrátil, je to past.
- **Konsolidace s playbookem monorepa** — sekce „Rozjetí tiketu do vlastní
  session" a „Kolizní kontrola" na větvi `SKODASMS-237-okno-w06` popisují
  ruční postup, který tato práce automatizuje. Po dokončení je potřeba je
  přepsat na odkaz na skill, ne nechat vedle sebe dvě pravdy.
- **Poznámka o `.gitignore` v `poznatky-spousteni-agentu.md` je obrácená** —
  tvrdí, že kořenový `.superpowers/` ignorovaný není a `memory-bank/.superpowers/`
  je; změřeno je to naopak. Opravit při konsolidaci.
- **Redistribuovatelnost do `pmq_logopedie_nr`** nešla ověřit — repozitář
  není lokálně k dispozici. Derivované členství v poolu a guard ve skriptu
  jsou navržené tak, aby na tom nezáviselo, ale ověřit to bude potřeba.
