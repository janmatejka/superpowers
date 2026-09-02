# Návrh: Pool orchestrace tiketů (`mb-epic-run`)

- **Jira:** UMS-3488 (https://datasyscz.atlassian.net/browse/UMS-3488)
- **Target MB:** memory-bank/
- **Vytvořeno:** 2026-09-02

## Cíl

Rozpracování epiku (`mb-epic-elaboration`) dnes končí tím, že v
`proposals/next/` leží předběžné návrhy budoucích tiketů. Odtud dál je ruční
práce: operátor otevře workspace, přepne větev, přečte, co se má dělat, a
nadiktuje sezení zadání. Cíl je, aby **řídicí sezení epiku (orchestrátor)
umělo rozjet plnohodnotné sezení na tiket do volného slotu poolu a na
požádání říct, jak sloty stojí.**

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
  `additionalContext`, a `Instruction` jako povinný klíč.
- Nový druh batonu `Kind: ticket-start` s vlastní sadou povinných klíčů a
  vlastními hlídkami.
- Tři skripty vrstvy: `pool-status.ps1` (derivace stavu slotů),
  `pool-launch.ps1` (vyčištění prostředí a spuštění), `pool-provision.ps1`
  (operátorské zakládání slotu).
- Nový skill `mb-epic-run` se třemi operacemi: `status`, `spawn <TIKET>`,
  `attach <TIKET>`.
- Brána připravenosti nad ledgerem epiku včetně dirty-setu.
- Generovaný briefing tiketu jako soubor ve slotu.
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
  operátora. Zákaz v `permissions.deny` (`EnterWorktree`, `ExitWorktree`),
  `skillOverrides.using-git-worktrees: off` a `worktree.bgIsolation: "none"`
  zůstávají nedotčené.
- **Žádné agent teams a žádné `isolation: worktree` subagenty** pro práci na
  tiketu — teammates běží v pracovním adresáři vedoucího, což je přesně to,
  co pool nedělá.
- **Žádné zápisy do Jiry z `mb-epic-run`.** Jira zůstává u `mb-jira-update`
  a u agenta tiketu.
- **Adaptéry `vscode`, `deeplink` a `bg`** se v této práci nestaví (viz
  „Odchylky od zadání").
- **Delivery mode 2 batonu** (spawn-and-abandon) se jen textově opravuje,
  nestaví se.

## Technický návrh

### 1. Slot poolu jako workspace kontraktu

Slot je **linked git worktree**, který zakládá uživatel, žije napříč mnoha
tikety, hostí nejvýš jedno sezení a nese jednu tiketovou větev a jeden pin v
`context.md`. Kontrakt na něj hledí jako na **nalezený workspace** — Workspace
Discipline, vstupní brána, `mb-park`/`mb-harvest`/`mb-abort`, Publication
Contract a meziclonová kolizní kontrola na něj platí beze změny. Nic v této
práci je neobchází ani nepřepisuje.

Worktree Policy dostává **právě jednu výjimku**: slot poolu, který
provisionoval uživatel. Agentem vytvořené worktrees zůstávají zakázané.

**Sdílený `.git` je to, co drží publikační záruku.** Změřeno v monorepu: z
každého ze čtyř slotů vrací `git rev-parse --git-path hooks/pre-push` cestu
`D:/_datasys/ums/.git/hooks/pre-push`, tedy tentýž soubor. Jedna instalace
`install-git-hooks.ps1` proto pokrývá všechny sloty a fail-closed kontrola
vstupní brány funguje v každém slotu bez další instalace. `core.hooksPath` se
inspektuje jako dnes — s tou známou pastí, že **relativní** hodnota se
resolvuje per-worktree, takže by v tom případě každý slot potřeboval vlastní
běh instalátoru.

### 2. Derivovaný stav slotu

**Členství v poolu je derivované, ne konfigurované.** Pool jsou linked
(ne-primary) worktrees tohoto repozitáře minus ten, ve kterém stojí
orchestrátor. Zdroj je jedno čtení `git worktree list --porcelain`; primary
worktree je jeho první záznam, orchestrátorův vlastní se pozná srovnáním s
`git rev-parse --show-toplevel`. Repozitář bez linked worktree nemá pool a
`mb-epic-run` fail-closed odmítne českou hláškou, která to říká.

Stav každého slotu se derivuje z:

| Zdroj | Co říká |
|---|---|
| `git worktree list --porcelain` | cesta → větev, nebo detached |
| `<slot>/memory-bank/context.md` | pin (slug + Target MB Pin), nebo IDLE |
| `<slot>/.superpowers/sdd/plan_<slug>/progress.md` | postup v plánu **toho** slugu |
| `git -C <slot> status --porcelain` | špinavý strom |
| `git -C <slot> stash list` | stash |
| `git -C <slot> log --branches --not --remotes` | nepushnuté commity |
| `<slot>/.superpowers/playbook-candidates/<slug>.md` | netrackovaný neprázdný kandidát playbooku |
| `<slot>/.superpowers/session-intent.md` | nezkonzumovaný baton = „spawnuto, sezení ještě nezačalo" |

**Ledger se páruje na slug z pinu, nikdy na „jakýkoli adresář pod
`sdd/`".** Změřeno: slot `ums03` nese pin na `skodasms_251_regexovy_pool_bota`,
ale v `.superpowers/sdd/` mu leží ledger od `plan_skodasms_239_knihovna_chytrolinconnect`
— zbytek po předchozí práci v tom slotu. Derivace, která by vzala první
nalezený adresář, by v tabulce ohlásila cizí postup jako postup tohoto
tiketu.

**Idle slot je detached, nebo stojí na větvi, jejíž jméno se rovná jménu
adresáře slotu.** Druhá varianta je konvence, kterou pool v monorepu už
používá (`ums04` na větvi `ums04`) a která má vlastní hodnotu: je to
pojmenované místo, kam slot přepnout, když je potřeba uvolnit větev
vyzvednutou jinde. `pool-provision.ps1` nové sloty zakládá `--detach`;
existující se nemigrují, protože jsou to nalezené workspace.

**Liveness je best-effort a nikdy nerozhoduje.** Bez postaveného adaptéru
`bg` nemá vrstva zdroj, ze kterého by se dala poznat, takže se hlásí
`unknown`. PID soubory pod `~/.claude/sessions/` se nečtou — je to
nezdokumentované rozhraní, které se může změnit.

**Volný slot** je derivovaný stav: čistý strom, IDLE pin, žádný
nezkonzumovaný baton, žádný stash, žádné nepushnuté commity, žádný
netrackovaný neprázdný kandidát playbooku, a nedrží tiketovou větev tohoto
epiku. Slot s **neobnovitelnými zbytky** volný není a orchestrátor ho
**neuklízí** — ohlásí ho a rozhodnutí nechá uživateli v tom slotu, kde
zbytky leží. To je Workspace Discipline, nikoli opatrnost: rozhodnutí o
neobnovitelném obsahu patří uživateli.

### 3. Baton `Kind: ticket-start`

Formát batonu zůstává uzavřený a mechanika beze změny: parsuje se, znovu
renderuje, nikdy neemituje doslova, po emisi se přejmenuje na
`session-intent.consumed.md`, při zamítnutí hlídkou na
`session-intent.stale.md`, každá chybová cesta končí tiše s exit 0.

Klíče podle druhu:

| Kind | Povinné | Volitelné |
|---|---|---|
| `plan-execution`, `plan-resume` | `Kind`, `Plan`, `Branch`, `Slug`, `Instruction` | `Spec`, `Ticket`, `Ledger`, `Next task` |
| `ticket-start` | `Kind`, `Ticket`, `Slug`, `Base`, `Instruction` | `Spec`, `Brief` |

`Plan` se u `ticket-start` **nepoužívá** a jeho kontrola existence na tento
druh nedopadá — v okamžiku spawnu plán ještě neexistuje a existovat nemá.
`Spec` je cesta do některého adresáře `proposals/next/` a musí existovat;
`Brief` je cesta ke generovanému briefingu a musí existovat taky. Obě jsou
relativní k `MB_ROOT`, jako všechny cesty v batonu.

Hlídky pro `ticket-start` (každá při selhání → stale, tiše, exit 0):

1. **Čistý strom** — `git status --porcelain` prázdný.
2. **Žádná lokální větev tiketu** — neexistuje větev odpovídající
   `<Ticket>-*`.
3. **IDLE `context.md`** — žádný pin.

Existující hlídky (`Branch` proti `HEAD`, `Slug` proti pinu, existence
`Plan`) platí **jen pro `plan-execution` a `plan-resume`**. `Base` je
nápověda, kterou Intent fáze předvybere, **ne požadavek na checkout** — idle
slot je detached nebo na scratch větvi, takže na bázi nikdy nestojí.

Zapisovatelem `ticket-start` batonu je **jiné sezení** (orchestrátor), ne
sezení, které ho přečte. Precondice zapisovatele („piš baton jen tam, kde
ho někdo přečte") je u slotu splněná tím, že slot sdílí trackovaný
`.claude/settings.json` téhož repozitáře, ve kterém je čtenář registrovaný.

`$RenderOrder` se rozšiřuje na `Kind`, `Plan`, `Spec`, `Brief`, `Branch`,
`Slug`, `Base`, `Ticket`, `Ledger`, `Next task`, `Instruction` a zůstává
zdokumentovaný v souboru jako stabilní. Kontrola hodnot (zákaz `[<>]` a
`\p{Cc}`) i strop velikosti platí beze změny.

### 4. Briefing tiketu jako soubor

Baton je uzavřený blok ukazatelů se stropem 8 KB — briefing se do něj
nevejde a vejít nemá. Zadání nad rámec ukazatelů proto nese samostatný
soubor, na který baton ukazuje klíčem `Brief`.

**Umístění:** `<slot>/.superpowers/ticket-brief-<TIKET>.md`. Adresář
`.superpowers/` je git-ignorovaný ve forku i v monorepu (ověřeno: ve forku
`.gitignore:4`, v monorepu `.gitignore:541` pravidlem `/.superpowers/`), takže
soubor nikdy nespadne do commitu — stejné odůvodnění, jaké má sám baton.
Proti `%TEMP%`, kam se briefingy psaly ručně, má dvě výhody: leží u práce,
ke které patří, a přežije restart stanice.

**Obsah generuje `mb-epic-run` z ledgeru epiku, Jiry a Memory Bank.** Řídí se
principem „to, co si sezení samo neodvodí, nebo odvodí pozdě a draze":

- **rozsah** — položky ledgeru s ID a stavem,
- **blokátoři a co tiket blokuje**,
- **špinavé řádky** tiketu, i „žádný", protože to je informace,
- **existuje návrh?** — rozhoduje o celém začátku: bez návrhu
  brainstorming, s předběžným návrhem v `next/` jeho prohloubení a
  aktivace přesunem, ne psaní znovu,
- **pasti** — netrackované zbytky ve stromu, posunuté řádkové odkazy v
  nadřazeném návrhu, neopravené dluhy v návrzích, na kterých tiket stojí,
- **odkazy na hotové sousedství** — sklizené návrhy sousedů a vybrané
  položky playbooku komponenty,
- **co se nemění** — u změn kontraktu stejně důležité jako co se mění.

Do briefingu nepatří nic, co si sezení přečte samo za deset sekund (obsah
tiketu, kontrakt). Briefing je česky — čte ho i člověk, když spawn ověřuje.

### 5. Launcher: vyčištění prostředí a dva adaptéry

**Spawn je frontend-agnostický: baton plus launcher.** Orchestrátor zapíše
baton do slotu a pak vyvolá launcher, který **jen spustí Claude Code s cwd =
slot**. Na příkazové řádce se nepředává žádný prompt; záměr doručuje baton a
první tah rozjede `initialUserMessage` z amendmentu A1. Jedna cesta doručení,
několik spouštěčů.

**Vyčištění zděděného prostředí je povinná součást spuštění, ne pohodlí.**
Orchestrátor je sám sezení Claude Code, takže potomek zdědí jeho proměnné a
naběhne jako **dětská session s vypnutým transcriptem, s identitou a
messaging rourou rodiče**. Změřeno 2. 9. 2026 (pokus 2). `pool-launch.ps1`
proto před spuštěním odebere ze svého shellu deset proměnných:

| Proměnná | Co působí, když zůstane |
|---|---|
| `CLAUDE_CODE_CHILD_SESSION` | sezení se hlásí jako dětské, vypne ukládání transcriptu |
| `CLAUDE_CODE_SESSION_ID` | potomek se tváří jako totéž sezení |
| `CLAUDE_CODE_BRIDGE_SESSION_ID` | totéž pro bridge |
| `CLAUDE_CODE_MESSAGING_SOCKET` | potomek by komunikoval rourou rodiče |
| `CLAUDE_CODE_MESSAGING_TOKEN` | totéž |
| `CLAUDE_CODE_SSE_PORT` | totéž |
| `CLAUDE_PID` | identita rodiče |
| `CLAUDECODE` | značka „běžím uvnitř Claude Code" |
| `CLAUDE_CODE_ENTRYPOINT` | totéž |
| `NO_COLOR` | sezení je černobílé; hodnotu nastavuje harness rodiče pod VS Code |

`CLAUDE_CODE_USE_POWERSHELL_TOOL` se **nechává** — to je nastavení uživatele,
ne stav sezení.

Odebrání musí být ve **stejném volání** jako spuštění: každé volání
PowerShellového nástroje je čerstvý shell dědící od rodiče, takže odebrání
provedené jinde nemá na spuštění vliv.

**Odebrání `CLAUDECODE` se nesmí dotknout publikační záruky.** Marker agentní
relace `MB_AGENT_SESSION=1` přichází do spawnutého sezení z `env` bloku
trackovaného `.claude/settings.json`, ne z dědičnosti, a `CLAUDECODE` je jen
fallback. Že to tak v praxi je, je **tvrzení k ověření, ne premisa** — má
vlastní bod verifikace.

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

**Existence procesu není důkaz.** `Get-Process claude` vrátila PID ve všech
třech selháních z 2. 9. Ověření patří k obrazovce uživatele: chybí varování
o transcriptu a první tah skutečně proběhl. Do Jiry jde „běží" teprve po
prvním commitu na větvi tiketu; do té doby je pravdivé jen „větev
připravená, sezení spuštěné".

### 6. Brána připravenosti

Spawn tiketu je krok uzávěrky elaboračního okna (fáze 7), takže se nabízí jen
u tiketů, jejichž předběžný návrh v tom okně přistál v `proposals/next/`.
Spawn tiketu bez návrhu vyžaduje **výslovný pokyn operátora** a zapíše baton
bez `Spec` — takové sezení začne vstupní bránou a brainstormingem.

Brána je **fail-closed se jmenovitým důvodem u každého odmítnutého tiketu**:

1. **Pool existuje** — aspoň jeden linked worktree mimo orchestrátorův.
2. **Tiket je v ledgeru epiku.**
3. **Prázdný dirty-set tiketu.** Tohle je ta past, kterou graf neumí: tiket
   může svítit „připraveno k implementaci" a přitom mít špinavé řádky, které
   říkají, že jeho zadání po sousedních tiketech přestalo platit. Brána
   odmítne a **řekne které řádky** to jsou. Data jsou v ledgeru, takže je to
   čtení, ne nová evidence.
4. **Návrh, nebo výslovný pokyn** — draft `design_<slug>.md` v některém
   `proposals/next/` na aktuální větvi nebo dosažitelný přes `mb-doc-index`.
5. **Žádná kolize aktivní práce** na cizí větvi (viz sekce 9).
6. **Větev tiketu není vyzvednutá jinde** — poznají to derivované stavy
   slotů, a kdyby ne, poslední slovo má git sám: větev nelze vyzvednout ve
   dvou worktrees. Tenhle odmítnutý checkout **je** to vynucení, že tiket
   běží nejvýš v jednom slotu; žádná evidence ho nereplikuje.
7. **Volný slot** podle derivace ze sekce 2. Není-li žádný, brána ohlásí,
   který slot co drží, a zastaví se.

Pravidla brány dnes stojí na **jediném rozhodování** (uzávěrka okna W06,
2. 9. 2026). Dirty-set je do brány zařazený proto, že je to jmenovaná past se
změřeným projevem; ostatní pravidla nad rámec výčtu výše se dopsat nemají,
dokud se neukáže, co se opakuje. Ta zdrženlivost patří do návrhu, ne do
implementace.

### 7. Skill `mb-epic-run`

Sourozenec `mb-epic-elaboration`, stejně jako `mb-epic-graph`. Tři operace,
všechny reportované česky.

**`status`** — spustí `pool-status.ps1`, vyrenderuje tabulku a přidá pohled
epiku: u každého tiketu v ledgeru, jestli ho nějaký slot drží. Čistě
read-only.

**`spawn <TIKET>`** v tomto pořadí:

1. Brána připravenosti (sekce 6). Odmítnutí = STOP se jmenovaným důvodem.
2. Volba slotu z derivovaného stavu.
3. Generování briefingu do `<slot>/.superpowers/ticket-brief-<TIKET>.md`.
4. Zápis batonu do `<slot>/.superpowers/session-intent.md` (adresář vytvořit,
   když chybí — v čerstvém worktree není). **Nezkonzumovaný baton se nikdy
   nepřepisuje** — místo toho se ohlásí `baton: pending`.
5. Vyvolání `pool-launch.ps1` se zvoleným adaptérem a ohlášení stavového
   slova česky. **Pořadí je závazné: baton první, launcher druhý.**
6. Zápis do ledgeru epiku: řádek tiketu si poznamená cestu slotu a čas
   spawnu (obsah ledgeru, česky, jeden řádek) — ledger zůstává jediným
   místem, kde stav elaborace žije.
7. Ověřovací otázky na uživatele podle sekce 5.

**`attach <TIKET>`** — najde slot, který tiket drží, a **vytiskne** operátorovi
další akci. Bez postaveného adaptéru `bg` to není `claude attach <id>`, ale
cesta ke slotu a příkaz, kterým se tam dostane. Tiskne, nespouští za
operátora nic, pokud o to nepožádá.

**Železná pravidla těla skillu.** Orchestrátor nikdy nepřepne (`cd`) do
slotu; nikdy ve slotu nespustí zapisující git příkaz; nikdy ve slotu nic
nemaže ani nepřesouvá; nikdy nespawnuje bez kolizní kontroly; a **STOP musí
slot nechat přesně tak, jak ho našel.** Zápisy do cest slotu jdou z
orchestrátoru přes PowerShell (`New-Item`, `Set-Content`), aby fungovaly pod
existujícím allow-listem a mimo projektový adresář orchestrátoru.

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
- `hookSpecificOutput.additionalContext` = vyrenderovaný blok, beze změny
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

**A2 — `Instruction` je povinný klíč.** Kontrakt říká „poslední řádek je
jediný `Instruction:`", hook ho ale vede jen v `$RenderOrder`. Rozpor se
řeší na straně kontraktu: `Instruction` přibude do `$Required`, dostane test
(baton bez `Instruction` → stale) a formulace kontraktu řekne „povinný"
výslovně.

**Zapisovatele to tentokrát mění.** Overlay fragment
`writing-plans.overlay.md` `Instruction` jmenuje (řádek 27), ale
`subagent-driven-development.overlay.md` ve svém výčtu klíčů páté stop třídy
**ne** — vyjmenovává `Kind`, cestu plánu, cestu ledgeru, větev, slug a číslo
dalšího tasku. Sezení jdoucí podle overlaye doslova by po zpřísnění napsalo
baton, který hook zamítne jako stale. Fragment proto dostane `Instruction` do
výčtu a s ním je potřeba **revendor**.

### 9. Cílený sken v `doc-index.ps1`

Vstupní brána vyžaduje meziclonovou kolizní kontrolu a `mb-epic-run spawn` ji
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

- **Worktree Policy** — zákaz i jeho měření zůstávají; přibývá jeden
  odstavec s výjimkou poolu: slot je uživatelem provisionovaný linked
  worktree, který žije napříč mnoha tikety a hledí se na něj jako na nalezený
  workspace; agentem vytvořené worktrees zůstávají zakázané; idle slot je
  detached nebo na větvi jménem shodné s adresářem slotu (s důvodem: jednu
  větev nelze vyzvednout dvakrát). Sdílený `.git` znamená, že jednou
  instalovaný `pre-push` guard pokrývá každý slot a
  `git rev-parse --git-path hooks/pre-push` ho z každého slotu najde, takže
  fail-closed kontrola vstupní brány funguje beze změny; `core.hooksPath` se
  inspektuje jako dnes.
- **Workspace Discipline** — jedna věta, která slot poolu pojmenuje jako
  workspace ve smyslu kontraktu; „jedno sezení na workspace" platí per slot.
- **Session Intent Baton** — `Kind: ticket-start`, per-druhové povinné klíče,
  volitelné `Spec` a `Brief`, nepoužitý `Plan`, tři hlídky, `Base` jako
  nápověda, `Instruction` povinný pro všechny druhy, a věta o tom, že
  zapisovatelem `ticket-start` je jiné sezení a čím je u slotu splněná
  precondice zapisovatele.
- **Repository Configuration** — **žádný `pool` blok.** Členství v poolu je
  derivované, takže konfigurace nevzniká; informational-only status
  `ums-repo.json` u vstupní brány zůstává nedotčený.
- **Language Contract** — pravidlo se nemění; doplní se poznámka, že
  launcher a status skripty jsou vývojářské nástroje vrstvy (anglicky),
  zatímco reporty `mb-epic-run` a generovaný briefing jsou pro člověka
  (česky).

### 11. Integrace do `mb-epic-elaboration`

`SKILL.md` fáze 7 (Close) a `protocol.md` §3.3: po publikaci se u každého
tiketu, jehož draft v tomto okně přistál v `next/`, **nabídne**
`mb-epic-run spawn` — nabídka, jedna otázka, rozhodne operátor per tiket.
Přidá se řádek do quick-reference. Jsou to soubory vrstvy, edituje se přímo,
žádný overlay.

`ledger-template.md` dostane konvenci pro poznámku o slotu, pokud ji ledger
potřebuje, aby přežil parsování v `ledger-status.ps1`; ta sada musí na
fixturách zůstat zelená.

### 12. Sweepy: co tato práce činí nepravdivým

Po změně pravidel je potřeba projít restatementy, které grep na jméno
měněného pojmu nenajde:

- **Bump verze kontraktu je vlastní sweep** — `grep -rn '2\.12' ums/
  memory-bank/ CLAUDE.md`, nálezy rozdělit podle vlastníka: soubory vrstvy
  patří implementaci, dokumenty Memory Bank harvestu.
- **Počítací a jedinečnostní fráze** — Worktree Policy dnes tvrdí zákaz bez
  výjimky, takže věty typu „worktrees jsou zakázané", „žádná výjimka",
  „přesně jedna" se lámou přidáním výjimky, ne změnou toho, co popisují.
  Slovník sweepu: `jediná|jediný|přesně|nikdy|vždy|žádná výjimka|only|never|
  exactly|the one`.
- **Inventáře podle druhu artefaktu, ne podle jména** — `tech.md` (počty
  sad, součty asercí, inventář nástrojů, řádek `settings.json`),
  `ums/README.md` (adresářové stromy, matice harnessů),
  `SKILLS_MANIFEST.md`. Grepovat na jména **sourozeneckých** artefaktů, ne
  na jméno nového skillu, který zatím nikde neleží.
- **Věty o batonu, které předpokládají dva druhy** — sekce Session Intent
  Baton v [architecture.md](../../architecture.md), hlavička hooku, testy.
- **Věty o `doc-index.ps1` jako o read-only nástroji s daným výkonem** — po
  přidání cíleného skenu se mění obojí.

## Odchylky od zadání a jejich důvody

Zadání (`dispatch-brief-ticket-pool-orchestration.md`, 2. 9. 2026 15:05) bylo
psané **před** poznatky z ručních pokusů (`poznatky-spousteni-agentu.md`,
15:26) a bez znalosti stavu poolu v monorepu. Odchylky jsou proto doplnění
měřenou zkušeností, ne nesouhlas se záměrem.

| Zadání | Návrh | Důvod |
|---|---|---|
| Part A je aktivní nedotestovaná položka, dokončit ji a pak Part B | A1+A2 jsou první dva tasky jednoho plánu s Part B | `baton_rotace_kontextu` je už sklizený (návrh v `completed/`, plán smazán, `context.md` IDLE) a integrovaný (větev bit-identická s `origin/ums-memory-bank`); archiv v `completed/` je neměnný. Rozhodnutí operátora ze 2. 9. |
| JIRA-less, slug `pool_orchestrace_tiketu` | UMS-3488, slug `ums_3488_pool_orchestrace_tiketu` | Tiket na tuhle práci existoval už 12:30 pod jménem `mb-epic-dispatch`; jméno skillu zůstává `mb-epic-run` a summary tiketu se přepíše při finalizaci |
| FIXED 3: idle slot je detached | detached **nebo** větev jménem shodná s adresářem slotu | Pool v monorepu drží `ums04` na větvi `ums04`; scratch větev je navíc pojmenované místo, kam slot přepnout při uvolnění větve vyzvednuté jinde |
| FIXED 4 / B1: `pool.root` v `ums-repo.json` | žádná konfigurace, členství derivované z `git worktree list` | `ums-repo.json` je trackovaný a sdílený s `pmq_logopedie_nr`, takže absolutní cesta stanice do něj nepatří; derivace je navíc věrnější FIXED 4 („nikdy záznam") a dala v monorepu přesně `ums01..ums04` |
| FIXED 4: ledger z `.superpowers/sdd/*/progress.md` | ledger se páruje na slug z pinu | `ums03` nese cizí ledger po předchozí práci — derivace „první nalezený adresář" by hlásila cizí postup |
| FIXED 5: čtyři adaptéry (`vscode`, `terminal`, `deeplink`, `bg`) | `terminal` + `direct` | Jen tyhle dva jsou prokázané. `vscode` a `deeplink` by šly poslat nepotvrzené — a lekce dne je, že nepotvrzené spuštění vypadá jako úspěch. `bg` by dal liveness, ale běží mimo obrazovku, kde se ověřuje |
| FIXED 5: „launcher jen spustí Claude Code" | povinné vyčištění deseti proměnných před spuštěním | Bez toho naběhne dětská session s vypnutým transcriptem — pokus 2 z 2. 9. Zadání tuhle třídu problému vůbec nezmiňuje |
| B4.1: eligibilita bez dirty-setu | brána nese dirty-set a jmenuje řádky | Jmenovaná past s měřeným projevem: tiket svítí „připraveno" a jeho zadání dvakrát přestalo platit. Akceptační kritérium UMS-3488 |
| B4.2: kolize přes `mb-doc-index` jak je | `doc-index.ps1` dostane cílený sken | Jak je napsané, na monorepu neproveditelné (25 min, zabito). Oprava navíc narovná vstupní bránu, ne jen spawn |
| Baton nese jen ukazatele | volitelný klíč `Brief` a generovaný briefing ve slotu | Briefing souborem je to, co obě úspěšná spuštění udělalo funkčními; a brána, která zná špinavé řádky, je nesmí zatajit agentovi, kterého spouští |
| B3: `pool-provision.ps1 -Root -Count` zakládá `slot-<n>` | `-Path <dir> -Base <ref>`, jeden slot na volání | Bez konfigurovaného rootu není z čeho jméno derivovat, a pool má vlastní konvenci (`ums01..ums04`). UMS-3488 výslovně žádá nedávat jména slotů natvrdo |
| B7: bez změny overlay fragmentů | jeden řádek v `subagent-driven-development.overlay.md` + revendor | Fragment ve výčtu klíčů páté stop třídy `Instruction` nejmenuje, takže by A2 udělalo z jeho batonů stale. B7 tuhle cestu připouští |

## Dopady

**Na existující práci v poolu.** Nic se nemigruje. Čtyři slotové worktrees
zůstávají, jak jsou, včetně `ums01` s 32 špinavými záznamy a `ums03` s
215 — derivace je ohlásí jako nevolné a rozhodnutí nechá operátorovi.

**Na vstupní bránu.** Cílený sken v `doc-index.ps1` zpřístupní fail-closed
kolizní STOP na monorepu, kde je dnes nedosažitelný. To je zpřísnění: práce,
která dřív prošla, může začít narážet na kolize, které tam byly celou dobu.

**Na batony napsané před touto změnou.** Baton bez `Instruction` se po A2
stane stale. Je to git-ignorovaný scratch s životností minut, takže cena je
nulová, ale sezení, které mezi změnou a příštím `/clear` baton drží, ho
uvidí zneplatněný.

**Na nasazení.** Změny zdroje v `ums/.claude/` je potřeba nasadit do
kořenového `.claude/` (a `.agents/skills/`), jinak sezení v tomto repu
pracuje se starou verzí. Změna overlay fragmentu navíc vyžaduje revendor —
plný jednoprůchodový běh s pinovaným tagem, ne `-OverlaysOnly`, protože
nasazené vendorované soubory už overlay bloky nesou.

**Na Kilo Code a ostatní harnessy.** Nic nového. `mb-epic-run`, kontrakt a
briefing jsou čistý Markdown a přenesou se; `initialUserMessage` je
mechanismus Claude Code a jinde spawn zůstane s ručním prvním tahem.

## Rizika

**`initialUserMessage` nemusí ve VS Code extension fungovat.** Na tom stojí
bezzásahový start celého spawnu, a operátor pracuje právě v extension.
Ověření je operátorské a je zastavovacím bodem verifikace. Když extension
pole ignoruje, návrh to zapíše jako známé omezení toho frontendu, položka se
dokončí a obchází se to ručním prvním tahem — **workaround se nestaví**.

**Vyčištění `CLAUDECODE` může teoreticky odzbrojit `pre-push` guard** ve
spawnutém sezení, kdyby `MB_AGENT_SESSION` nedorazil z `settings.json`.
Vlastní bod verifikace; kdyby se to potvrdilo, `CLAUDECODE` se ze seznamu
odebíraných proměnných vyřadí (cena je jen značka „běžím uvnitř Claude
Code", ne dětská session).

**Pravidla brány stojí na jediném rozhodování.** UMS-3488 sám doporučuje
psát je až po druhém až třetím rozjetí. Riziko se tlumí tím, že se do brány
dostal jen dirty-set — jmenovaná past se změřeným projevem — a nic dalšího
nad rámec výčtu ze sekce 6.

**Worktree, který operátor používá k jinému účelu, se objeví v tabulce
poolu.** Derivace nemá jak poznat záměr. Tlumeno tím, že takový worktree
nebude nikdy „volný" (špinavý strom, pin nebo baton), takže se do něj
nespawnuje; a spawn hlásí, který slot vybral.

**Slot něco stojí na disku, ale méně, než se čekalo.** Sdílený `.git` se
neduplikuje, pracovní strom ano. Změřeno v monorepu 2. 9. 2026: slot `ums04`
má **7,7 GB / 80 022 souborů**, sdílený `.git` **4,4 GB**, a hlavní klon
celkem **27,2 GB / 140 365 souborů** — rozdíl mezi slotem a hlavním klonem je
naakumulovaný build output, ne zdroj. Čerstvý slot je tedy asi 8 GB a roste s
tím, co se v něm postaví. `pool-provision.ps1` tenhle rozpad hlásí v konzoli,
aby operátor nezakládal slot naslepo.

**Orchestrátor zapisuje do cizího pracovního stromu.** Tlumeno železnými
pravidly ze sekce 7 (žádný zapisující git příkaz, žádné mazání, žádné
přesouvání, STOP nechá slot nedotčený) a tím, že se píše výhradně do
git-ignorovaného `.superpowers/`.

## Verifikace

1. **Testy hooku zeleně** včetně nových případů `ticket-start` — happy path
   (detached HEAD i scratch větev, čistý strom, IDLE, s `Spec` i bez, s
   `Brief` i bez), každá ze tří hlídek selhávající jednotlivě, `Spec` a
   `Brief` mířící na neexistující soubor, `Plan` přítomný a ignorovaný,
   staré druhy nedotčené novou sadou povinných klíčů, `initialUserMessage`
   přítomný na happy path a **nepřítomný** na stale cestě, baton bez
   `Instruction` → stale. Počet asercí zjištěný spuštěním celé sady v témž
   sezení a zapsaný do ledgeru.
2. **Testy skriptů zeleně**; `pool-status.ps1` nad fixturou se třemi
   worktrees (volný detached, tiketová větev s ACTIVE pinem, špinavý
   detached) vyrenderuje tři správné řádky. Fixtura navíc obsahuje slot s
   ledgerem **cizího** slugu, aby se ověřilo párování ledgeru na pin.
3. **Doručení promptu měřené na neškodném cíli, ne na agentovi.** Skript,
   který si vypíše `$args` do souboru, spuštěný přes oba adaptéry;
   kontrola „jeden argument, text beze ztráty". Tenhle krok se dělá
   **před** ostrým spuštěním — je to ta disciplína, která 2. 9. udělala
   rozdíl mezi pokusem 3 a 4.
4. **Vyčištění prostředí.** Potomek vypíše `Env:` do souboru; kontrola
   nepřítomnosti všech deseti proměnných a **přítomnosti**
   `CLAUDE_CODE_USE_POWERSHELL_TOOL`.
5. **Publikační záruka ve spawnutém sezení.** V něm ověřit, že
   `MB_AGENT_SESSION` je nastavený a že syntetický protected-branch pipe
   přes rozřešený hook skončí nenulově — a zrcadlová accept case nulou.
   Bez tohohle je odebrání `CLAUDECODE` tvrzení bez důkazu.
6. **Cílený sken `doc-index.ps1`** — proti fixture repu (nové asercie) a
   **proti skutečnému monorepu**, kde má doběhnout a odpovědět; naměřený čas
   zapsat.
7. **Brána: odmítnutí se jmenovaným důvodem.** Fixture ledger se stavem
   tiketu se třemi špinavými řádky; očekávaný výstup jmenuje ty řádky, ne
   jen „odmítnuto".
8. **`initialUserMessage` ve VS Code extension — OPERÁTORSKÝ KROK, ZDE SE
   ZASTAVÍM.** Postup: otevři v tomto workspace čerstvé sezení extension
   (nové okno, nebo `/clear`) ve chvíli, kdy v
   `<MB_ROOT>/.superpowers/session-intent.md` leží platný baton — platný
   znamená, že projde hlídkami: `Branch` se rovná aktuální větvi, `Slug`
   pinu v `context.md`, soubor z `Plan` existuje a je tam řádek
   `Instruction`. Pozoruj **jedinou věc**: rozjede sezení první tah samo,
   bez tvého stisku klávesy? Výsledek zapiš do tohoto návrhu (funguje /
   extension pole ignoruje) **před harvestem**. Ignoruje-li ho, je to
   zapsané omezení toho frontendu a položka se dokončí; workaround se
   nestaví.
9. **End-to-end spawn — OPERÁTORSKÝ KROK.** Provisionuj jeden slot; z
   orchestrátoru spusť `mb-epic-run spawn <TIKET>` s adaptérem `terminal`;
   pozoruj, že nové sezení rozjede první tah bez zásahu, projde vstupní
   bránu, založí tiketovou větev a aktivuje draft. Pak `mb-epic-run status`
   ukáže slot jako ACTIVE se slugem. Zopakuj s adaptérem `direct`. Ověření
   podle sekce 5: **není** tam `⚠ Transcript saving is off` a první tah
   skutečně proběhl.
10. **Negativní: dvakrát tentýž tiket** → STOP kolizí, nebo odmítnutým
    checkoutem gitu; slot nedotčený, nic nezapsáno.
11. **Negativní: pool, kde je jediný slot špinavý** → report, žádný zapsaný
    baton.
12. **Negativní: repozitář bez linked worktree** → `mb-epic-run` fail-closed
    odmítne českou hláškou, která to říká.
13. **Sweepy ze sekce 12 provedené a nálezy opravené** v témž commitu jako
    pravidlo, které je vyvolalo.

## Pořadí úloh

1. **A1+A2** — čtenář batonu: `initialUserMessage`, `Instruction` do
   `$Required`, testy. Verifikuje se **izolovaně**, dřív než se sáhne na
   `ticket-start`: selhání end-to-end běhu musí mít jednu kandidátní
   příčinu, ne dvě.
2. **Kontrakt 2.13** — pravidlo má jeden domov, takže kontrakt jde před
   implementací toho pravidla.
3. **Hook `ticket-start`** — per-druhové povinné klíče, tři hlídky,
   `$RenderOrder`, testy. Verifikuje se izolovaně.
4. **`doc-index.ps1` cílený sken** + testy + měření proti monorepu.
5. **Tři pool skripty** + testy.
6. **Skill `mb-epic-run`** + `SKILLS_MANIFEST.md`.
7. **Integrace do `mb-epic-elaboration`** + zelené `ledger-status.ps1`.
8. **Dokumentace** — README skillu (anglicky) a český průvodce, včetně
   pohodlí stanice z B6.
9. **Overlay + revendor** — `Instruction` do výčtu v
   `subagent-driven-development.overlay.md`, obnova nasazení, plný revendor
   s pinovaným tagem.

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
- **Zbytek brány připravenosti** z UMS-3488 (odblokovanost podle tvrdých
  `Blocks` linků z grafu) — dopsat až po druhém až třetím rozjetí, aby se
  ukázalo, co se opakuje.
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
