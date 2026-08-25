# Návrh: Publikační guard míří na agenta, ne na člověka

- **Jira:** (žádný tiket)
- **Target MB:** memory-bank/
- **Vytvořeno:** 2026-08-25

## Cíl

Odstranit tři konkrétní tření, kvůli kterým je dnešní vynucení publikačního
kontraktu pro tým obtěžující, aniž by se ztratila záruka, že agent nepublikuje
neprohlédnutý obsah do sdílené větve:

1. **Hook bije i do lidské práce.** `pre-push` nepozná člověka od agenta, takže
   blokuje i běžný push člověka do chráněné větve z terminálu nebo IDE. Člověk
   si musí pamatovat únikovou proměnnou, nebo sáhne po vypnutí hooků.
2. **Rituál integrace je krkolomný.** Finální integrace se dnes spouští jako
   `! UMS_ALLOW_SHARED_PUSH=1 git push origin HEAD:<báze>`; zaklínadlo je
   nepříjemné právě v okamžiku, kdy je práce hotová.
3. **Kolize s Git LFS hookem.** V klonu, kde už `pre-push` patří LFS,
   `install-git-hooks.ps1` končí s exit 2 a záruka prostě není. Agent to řeší
   ad hoc a týmu není jasné, o co jde.

Zadání znělo „nemusí být tak striktní, ale dostatečně spolehlivé". Návrh proto
vědomě jedno pravidlo odevzdává kontraktu (viz Rozvolnění níže) a za to ruší
všechna tři tření.

## Naměřený stav

Vše níže je změřeno v tomto klonu, ne odvozeno z dokumentace.

- **Hook je živý a funguje, jak kontrakt tvrdí.** Syntetický pipe do
  `.git/hooks/pre-push` odmítl konfigurovaný vzor `ums-memory-bank` (exit 1,
  hláška `UMS:` s nabídkou únikové proměnné) a mlčky přijal
  `feature/ums-install-verify` (exit 0). Generovaný seznam se tedy čte.
- **Značka agentní session v prostředí existuje.** Claude Code do sezení
  nastavuje `AI_AGENT=claude-code_2-1-245_agent`, `CLAUDECODE=1` a
  `CLAUDE_CODE_ENTRYPOINT=cli`. Ani jedna nepochází z uživatelského či
  systémového prostředí ani z PowerShell profilu — ověřeno
  `[Environment]::GetEnvironmentVariable(...,'User'/'Machine')` a neexistencí
  všech tří profilových souborů. Rozlišit agenta od člověka tedy jde
  z prostředí, bez hádání podle TTY (to by selhalo na pushi z VS Code, který
  terminál nemá).
- **`guard-git-push.mjs` má dnes díru.** V `settings.json` je navěšený na
  matcher `Bash`, ale sezení běží přes PowerShell tool
  (`CLAUDE_CODE_USE_POWERSHELL_TOOL=1`). Push provedený přes PowerShell tool
  tou předběžnou kontrolou vůbec neprojde. Dnes to nevadí, protože zárukou je
  git hook; jakmile guard dostane skutečnou práci, je to zásadní.
- **Příkazy zadané uživatelem přes vykřičník PreToolUse hooky nespouštějí.**
  Sonda, ve které uživatel takto zadal `echo` s textem obsahujícím `git`,
  `push` a přepínač vypínající ověření, se pouze vypsala, přestože guard tuhle
  trojici kontroluje bez ohledu na kontext. Harnessový hook je tedy čistě
  agentní hranice.
- **Bezkontextová kontrola guardu má falešné poplachy na obsahu dokumentů.**
  Při psaní tohoto návrhu guard zamítl zápis souboru přes shellový heredoc,
  protože text návrhu tu trojici slov obsahoval. Guard to v komentáři sám
  připouští jako přijatý okraj; je to argument pro to, aby fail-closed
  zpřísnění (bod 3) platilo jen pro rozpoznaný podpříkaz `push`.
- **Kolize s LFS je slepá ulička už z konstrukce.** `install-git-hooks.ps1`
  cizí `pre-push` zásadně nepřepisuje — ohlásí konflikt a skončí exit 2.
  Jakékoli řešení, které si nárokuje výhradní vlastnictví
  `.git/hooks/pre-push`, tedy v repozitáři s LFS nemůže fungovat.

## Návrh

### 1. Hook přestane mířit na člověka

`pre-push` dostane na začátek bránu: **není-li v prostředí značka agentní
session, hook nevynucuje nic** a předá řízení řetězenému cizímu hooku (bod 5).
Člověk v terminálu, ve VS Code i v JetBrains nepozná, že něco takového
existuje — žádná proměnná, žádné vypínání hooků.

Značku si vrstva **injektuje sama** přes konfiguraci každého harnesse
(`env` v `ums/.claude/settings.json` u Claude Code, obdoba u ostatních):
`MB_AGENT_SESSION=1`. Prefix `MB_` ze stejného důvodu jako u lidské výjimky —
vrstva je adoptovatelná jinými projekty a prefix produktu do jména nepatří.
Harnessové proměnné (`AI_AGENT`, `CLAUDECODE` a obdoby) jsou **fallback**;
spoléhat se na ně primárně nelze, protože je vlastní někdo jiný.

Tím se obrací směr degradace, na kterém dnes vrstva stojí: z „chybí
konfigurace → víc ochrany" se stává „chybí značka → žádná ochrana". Kompenzace
je v bodě 6 (vstupní brána ověřuje záruku ve vlastním prostředí).

### 2. Hook přestane řešit *kdo* a začne řešit *co*

Na chráněné větvi projde **fast-forward push, jehož nový vrchol už je
dosažitelný na `origin`** — tedy posun ukazatele na commity, které origin
dávno má a které prošly review na tiketové větvi. Hook to ověří sám:

- `git merge-base --is-ancestor "$remote_sha" "$local_sha"` na fast-forward
  (kontrola už v hooku je, jen se dnes používá jinak),
- `git branch -r --contains "$local_sha"` na „už publikováno"; neprázdný
  výstup stačí. Playbook varuje, že tenhle příkaz vrací **všechny** vzdálené
  větve obsahující commit — tady je to přesně žádaná sémantika: nezáleží na
  tom, kterou cestou se commit na origin dostal.

Vše ostatní na chráněné větvi (lokální commit, non-fast-forward, mazání)
zůstává zamítnuté, protože to znamená publikovat obsah, který nikdo neviděl.

Oba příkazy si musí explicitně uzavřít stdin (`</dev/null`) — hlavní smyčka
hooku čte seznam refů ze stdinu a podpříkaz, který z něj ukousne, způsobí, že
hook tiše přestane kontrolovat zbylé refy (playbook, sekce Git hooky).

### 3. Práce se rozdělí mezi dvě vrstvy

Rozdělení není zdvojená pojistka; každá vrstva dostane **jinou** otázku.

| Vrstva | Otázka | Působnost |
|---|---|---|
| git `pre-push` | *Co* se pushuje | Cokoli, co běží v agentní session — včetně příkazů, které uživatel zadá přes vykřičník |
| `guard-git-push.mjs` (PreToolUse) | *Kdo* pushuje | Jen volání nástroje agentem; příkazy zadané přes vykřičník nevidí |

Guard tedy zakáže agentovi jeho vlastní push do chráněné větve **včetně**
integračního fast-forwardu, a je proto jedinou vrstvou, která drží pravidlo
„okamžik integrace patří člověku". Uživatelův `git push origin HEAD:<báze>`
zadaný přes vykřičník projde: guard na něj nestřílí a hook ho propustí podle
pravidla obsahu.

Guard se současně opraví a zpřísní:

- matcher `Bash|PowerShell` — dnešní díra,
- **fail-closed pro rozpoznaný `git push`**: co neumí s jistotou rozparsovat
  jako neškodné, zamítne (dnes propustí). Agent má vždy čistou cestu — napsat
  příkaz srozumitelně. Ostatní podpříkazy a bezkontextové kontroly zůstávají
  fail-open, aby se nemnožily falešné poplachy na obsahu dokumentů.

**Cena, kterou je nutné pojmenovat:** v harnessech bez PreToolUse (Codex,
Gemini, kilocode) vrstva aktéra chybí, takže tam agent integrační FF push
spustit může. Patří to do matice v [ums/README.md](../../../ums/README.md)
jako jmenované omezení.

### 4. Lidská výjimka: `MB_HUMAN_PUSH`

`UMS_ALLOW_SHARED_PUSH` se přejmenovává na **`MB_HUMAN_PUSH`** a mění význam:
místo „zvedni pravidlo o sdílené větvi" znamená **„člověk za tenhle jeden push
přebírá odpovědnost"**, tedy zvedá celý guard — sdílenou větev, mazání
i force push. Hook to hlasitě oznámí na stderr.

Dvě odůvodnění, obě nutná:

- **Jméno podle aktéra.** Síla té proměnné stojí výhradně na kontraktovém
  pravidle „agent ji nenastaví nikdy". Jméno, které říká `HUMAN`, dělá
  z jejího napsání agentem zjevnou lež — na jazykový model to působí jinak
  než neutrální `ALLOW_`.
- **Rozšíření rozsahu.** Jakmile hook platí jen v agentní session, člověk
  v sezení nese značku i při force pushi **vlastní tiketové větve** po
  rebasu. S dnešní úzkou výjimkou by mu nezbylo než hooky úplně vypnout —
  tedy přesně ten folklor, který tento návrh ruší. Mezi „vědomě posouvám
  bázi" a „vědomě přepisuju historii své větve" hook stejně rozlišit neumí.

Po dobu přechodu hook **respektuje obě jména**; u starého vypíše na stderr
jednu řádku o zastaralosti. Bez toho by člověk se starým jménem v historii
shellu narazil po upgradu a člověk s novou dokumentací na neupgradovaném
workspace před ním. Vypínání hooků tím ztrácí poslední legitimní důvod
k existenci a guard ho zamítá dál.

### 5. Řetězení místo kolize

`install-git-hooks.ps1` u cizího `pre-push` přestane končit exitem 2. Odsune
ho na `.git/hooks/pre-push.ums-chained` (interní jméno, konzistentní
s existujícím `ums-protected-branches`), nainstaluje náš a ten na konci zavolá
řetězený hook se stejnými argumenty a se stejným stdinem.

Čtyři detaily, které rozhodují, jestli to funguje nebo tiše rozbije LFS:

- **Stdin se nejdřív celý načte do bufferu a pak přehraje.** `git lfs pre-push`
  čte tentýž seznam refů, a dnešní `while read` ho spotřebuje beze zbytku. Bez
  přehrání by LFS objekty přestaly odcházet — selhání, které vypadá jako
  funkční stav.
- **Delegace platí i na rané ukončení.** Chybí-li značka (bod 1), hook nesmí
  prostě skončit nulou; musí předat řízení řetězenému hooku a vrátit **jeho**
  návratový kód. Jinak by instalace vrstvy vypnula LFS všem lidem v týmu.
- **Idempotence.** Opakovaný běh nesmí zřetězit náš hook sám se sebou ani
  přepsat už odsunutý cizí hook. Rozhoduje značka v hlavičce a existence
  cílového souboru; kolizi instalátor hlásí a nechá být.
- **Ruční slepenec se nerozplétá.** Cizí hook se stopami našeho kódu hlouběji
  v těle (výsledek dřívější ad-hoc opravy) se hlásí a nechává být — exit 2
  zůstává právě pro tenhle případ a pro selhání odsunutí.

Self-test instalátoru se rozšíří o důkaz, že řetězený hook **doběhl a dostal
stdin**; jinak by se „nainstalováno a ověřeno" tvrdilo o instalaci, která LFS
zabila. Odinstalace (vrátit řetězený hook na původní jméno, náš odstranit) se
dokumentuje jako součást této práce — bez ní nemá první poškozený tým kam
ustoupit.

### 6. Hladký přechod

- **Značka v hlavičce hooku zůstává, verze se přidává za ni.** Instalátor
  pozná svůj hook podle řetězce `UMS pre-push guard (Publication Contract)`
  v prvních pěti řádcích. Kdyby se ten řetězec přepsal, nová verze by starou
  vyhodnotila jako **cizí** hook a podle bodu 5 by ji **zřetězila** — starý
  hook by dál blokoval člověka zevnitř řetězu. Prefix se proto nemění a
  instalátor svůj hook v každé verzi přepisuje, nikdy neřetězí.
- **Upgrade proběhne sám.** Vstupní brána dnes fail-closed ověřuje „hook je
  nainstalovaný". Nově ověří „hook je nainstalovaný, je aspoň v2 a záruka
  platí na tuhle session" — tedy syntetický důkaz běží **v prostředí té
  konkrétní session**. Agent tak ověřuje, že guard platí na něj. Při nálezu
  staré verze spustí `install-git-hooks.ps1` (zapisuje jen do `.git/hooks/`
  a do generovaného seznamu, nic nevratného) a pokračuje. Kdo si installer
  nespustí sám, dostane ho od prvního agentního sezení.
- **Přechodové okno u ne-Claude harnessů.** `sync-with-monorepo.ps1` na
  ne-Claude cíle `settings.json` záměrně nenasazuje, takže injektáž značky se
  tam dělá ručně. Než se to stane, nesou značku fallback proměnné z bodu 1,
  a fail-closed kontrola „platí záruka na mě?" případnou mezeru **ohlásí**
  místo tichého běhu bez dozoru.
- **Konce řádků.** Hook je bezpříponový shellový soubor; pravidlo
  `text eol=lf` v [ums/.gitattributes](../../../ums/.gitattributes) platí dál
  a revendor normalizuje na LF.

## Rozvolnění, které tento návrh vědomě přijímá

Dnes rozhoduje o okamžiku integrace člověk proto, že mu hook ten příkaz
fyzicky nedá spustit. Po této změně to drží jen vrstva aktéra
(`guard-git-push.mjs`), tedy **jen v Claude Code**. Jinde se pravidlo stává
kontraktovým závazkem jako řada jiných pravidel vrstvy.

Co se **neztrácí**: agent nemůže na sdílenou větev dostat obsah, který není na
`origin`, ať už je harness jakýkoli. Guard obsahu je git hook a ten platí
všude.

## Dopady

| Místo | Změna |
|---|---|
| [UMS_MEMORY_BANK_CONTRACT.md](../../../ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md), Publication Contract | Dvouúrovňová push policy „vlastní × sdílená" se nahrazuje dvojicí *aktér* + *obsah*; nová role a jméno lidské výjimky; verze kontraktu 2.10 → 2.11 |
| Tentýž dokument, Workspace Discipline | Fail-closed podmínka vstupní brány z „hook je nainstalovaný" na „hook je nainstalovaný, je v2 a platí na tuhle session" |
| [pre-push](../../../ums/.claude/hooks/pre-push) | Brána na značku, pravidlo obsahu, řetězení, obě jména výjimky, verze v hlavičce |
| [install-git-hooks.ps1](../../../ums/.claude/hooks/install-git-hooks.ps1) | Odsunutí a zřetězení cizího hooku, nový self-test, změna významu exit 2 |
| [guard-git-push.mjs](../../../ums/.claude/hooks/guard-git-push.mjs) | Matcher `Bash\|PowerShell`, fail-closed pro rozpoznaný `push`, promotován zpět na nositele pravidla o aktérovi |
| [settings.json](../../../ums/.claude/settings.json) | `env` se značkou `MB_AGENT_SESSION`, rozšířený matcher |
| [mb-state](../../../ums/.claude/skills/mb-state/SKILL.md) | Řádek `Workspace:` hlásí i verzi hooku a přítomnost značky |
| Overlay `finishing-a-development-branch` | Integrační příkaz ztrácí prefix s proměnnou |
| [ums/README.md](../../../ums/README.md) | Matice harnessů: chybějící vrstva aktéra mimo Claude Code |
| MB dokumenty | Při harvestu: [brief.md](../../brief.md) (sekce Co vrstva záměrně nedělá), [architecture.md](../../architecture.md) (Publikační invariant, Dvouvrstvá mechanika vynucení), [tech.md](../../tech.md) (verze, konfigurace, testy) |

Po každé změně zdroje v `ums/.claude/` je nutná obnova nasazené kopie
v kořenovém `.claude/` a `.agents/skills/`, jinak sezení pracuje podle staré
verze (playbook, sekce Obnova nasazené kopie v tomto repu).

## Testy

Obě sady už běží proti skutečnému gitu s lokálním bare remote, takže se
rozšiřují, nezakládají.

- **pre-push:** chybí značka → průchod plus doložený běh řetězeného hooku;
  značka je + chráněná větev + non-fast-forward → zamítnutí; značka je +
  fast-forward už na originu → průchod; značka je + fast-forward s commitem,
  který na originu není → zamítnutí; obě jména výjimky včetně řádky
  o zastaralosti; force push a mazání pod novou výjimkou → průchod; push více
  refů najednou (regrese na krádež stdinu).
- **Řetězení:** cizí hook zachovaný a přejmenovaný; stdin přehraný v plném
  rozsahu; návratový kód řetězeného hooku propagovaný; opakovaná instalace
  idempotentní; ruční slepenec ohlášený a nedotčený. Ověřit i proti
  **skutečnému** LFS hooku, ne jen atrapě.
- **guard-git-push:** agentní FF push do chráněné větve zamítnutý;
  nerozparsovatelný push zamítnutý (nová fail-closed větev); příkazy mimo
  `push` dál fail-open.
- **Negativita:** každý nový strážce ověřit i proti neopravenému kódu podle
  pravidla v [playbook.md](../../playbook.md) a v reportu oddělit důkazy od
  regresních zámků.
