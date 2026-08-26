# Návrh: Publikační guard míří na agenta, ne na člověka

- **Jira:** (žádný tiket)
- **Target MB:** memory-bank/
- **Vytvořeno:** 2026-08-25
- **Oponentura:** agentická, 2026-08-25 — 16 nálezů, závěry zapracovány níže

## Cíl

Odstranit tři konkrétní tření, kvůli kterým je dnešní vynucení publikačního
kontraktu pro tým obtěžující, aniž by se ztratila záruka, že agent nepublikuje
na sdílenou větev obsah, který nikde jinde neexistuje:

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
vědomě snižuje sílu jedné záruky (viz Rozvolnění níže) a za to ruší všechna
tři tření.

## Prerekvizita: jedno měření, na kterém stojí rozdělení vrstev

Návrh dělí práci mezi git hook a harnessový PreToolUse guard (bod 3) a
předpokládá, že **příkazy, které uživatel zadá s vykřičníkem, PreToolUse hooky
nespouštějí**. Sonda, která to naznačila, je ale zmatená: guard je dnes
registrovaný jen na matcher `Bash`, zatímco sezení běželo přes PowerShell tool,
takže nulový výsledek stejně dobře vysvětluje mezera v matcheru.

**První úlohou implementace je tohle měření zopakovat čistě** — po rozšíření
matcheru na `Bash|PowerShell` a s výslovným uvedením, kterým nástrojem sonda
prošla. Ukáže-li se, že vykřičníkové příkazy hooky spouštějí, rozdělení práce
mezi dvě vrstvy nefunguje, rituál integrace se vrací a návrh se musí vrátit
k přepracování bodu 3 a 4. Nic dalšího se do té doby neimplementuje.

## Naměřený stav

Vše níže je změřeno v tomto klonu, ne odvozeno z dokumentace. Jediné tvrzení
o chování, které měření nemá, je předmětem prerekvizity výše.

- **Hook je živý a funguje, jak kontrakt tvrdí.** Syntetický pipe do
  `.git/hooks/pre-push` odmítl konfigurovaný vzor `ums-memory-bank` (exit 1,
  hláška `UMS:` s nabídkou únikové proměnné) a mlčky přijal
  `feature/ums-install-verify` (exit 0). Generovaný seznam se tedy čte.
- **Značka agentní session v prostředí existuje.** Claude Code do sezení
  nastavuje `AI_AGENT=claude-code_2-1-245_agent`, `CLAUDECODE=1` a
  `CLAUDE_CODE_ENTRYPOINT=cli`. Ani jedna nepochází z uživatelského či
  systémového prostředí ani z PowerShell profilu — ověřeno
  `[Environment]::GetEnvironmentVariable(...,'User'/'Machine')` a neexistencí
  všech tří profilových souborů.
- **Klíč `env` v `settings.json` do prostředí nástrojů skutečně doputuje.**
  Uživatelský `~/.claude/settings.json` nese `env` s
  `CLAUDE_CODE_USE_POWERSHELL_TOOL=1` a tatáž proměnná je v prostředí procesů
  spouštěných nástroji. Že prostředí dojde až do git hooku, dokládá existující
  sada `pre-push.tests.ps1`, která přes prostředí testuje lidskou výjimku.
- **`guard-git-push.mjs` má dnes díru.** V `settings.json` je navěšený na
  matcher `Bash`, ale sezení běží přes PowerShell tool
  (`CLAUDE_CODE_USE_POWERSHELL_TOOL=1`). Push provedený přes PowerShell tool
  tou předběžnou kontrolou vůbec neprojde.
- **Bezkontextová kontrola guardu má falešné poplachy na obsahu dokumentů.**
  Guard zamítl zápis tohoto návrhu přes shellový heredoc, protože jeho text
  obsahoval `git`, `push` a přepínač vypínající ověření pohromadě. Guard to
  v komentáři sám připouští jako přijatý okraj; je to argument pro to, aby
  fail-closed zpřísnění (bod 3) platilo jen pro rozpoznaný podpříkaz `push`.
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

Značku `MB_AGENT_SESSION=1` si vrstva **injektuje sama**. Prefix `MB_` ze
stejného důvodu jako u lidské výjimky: vrstva je adoptovatelná jinými projekty
a prefix produktu do jména nepatří. Doručení značky je **součást této práce pro
všechny harnessy**, ne jen pro Claude Code:

- Claude Code — klíč `env` v `ums/.claude/settings.json`,
- Codex, Gemini, kilocode — `sync-with-monorepo.ps1` se rozšíří tak, aby
  značku zavedl do jejich vlastní konfigurace. Dnes se na ně `settings.json`
  záměrně nenasazuje, takže bez tohoto rozšíření by tam hook sám sebe vypnul
  a ty harnessy by přišly nejen o předběžné varování, ale i o **záruku git
  hooku** — což by rozporovalo tvrzení v `ums/README.md`, že git hook je
  harness-agnostický.

Harnessové proměnné (`AI_AGENT`, `CLAUDECODE` a obdoby) jsou jen **fallback**
pro Claude Code; spoléhat se na ně nelze, protože je vlastní někdo jiný a
v jiných harnessech nejsou vůbec.

Tím se obrací směr degradace, na kterém dnes vrstva stojí: z „chybí
konfigurace → víc ochrany" se stává „chybí značka → žádná ochrana".
Kompenzace je v bodě 6.

### 2. Hook přestane řešit *kdo* a začne řešit *co*

Na chráněné větvi projde **fast-forward push, jehož nový vrchol už je
dosažitelný na tomtéž remote** — tedy posun ukazatele na commity, které tam
už jsou. Hook to ověří sám:

- `git merge-base --is-ancestor "$remote_sha" "$local_sha"` na fast-forward
  (kontrola už v hooku je, jen se dnes používá jinak),
- `git for-each-ref --contains "$local_sha" "refs/remotes/$remote_name/"` na
  „už publikováno". **Omezení na remote, do kterého se pushuje, je nutné** —
  tento fork má druhý remote `vanila`, takže commit dosažitelný jen tam by
  jinak prošel jako publikovaný.

Oba příkazy si musí explicitně uzavřít stdin (`</dev/null`) — hlavní smyčka
hooku čte seznam refů ze stdinu a podpříkaz, který z něj ukousne, způsobí, že
hook tiše přestane kontrolovat zbylé refy (playbook, sekce Git hooky).

Vše ostatní na chráněné větvi (lokální commit, non-fast-forward, mazání)
zůstává zamítnuté.

**Co tohle pravidlo NEzaručuje.** Dosažitelnost na remote dokazuje publikaci,
nikdy ne prohlédnutí. A dokazuje ji jen potud, pokud jsou remote-tracking refy
v tomhle klonu poctivé: `for-each-ref` čte `refs/remotes/<remote>/*`, což je
lokální a zapisovatelný stav — `git update-ref refs/remotes/origin/x <sha>` ho
splní, aniž by cokoli odešlo, a zastaralý tracking ref po smazané či přepsané
vzdálené větvi lže stejně i bez úmyslu. Autoritativní ověření proti remote
(`ls-remote`) se sem záměrně nedává: přidalo by síťové kolo ke každému
integračnímu pushi a hranice, kterou by uzavřelo, je stejně ta, kterou další
odstavec připouští. Kontrakt agentovi výslovně dovoluje pushovat vlastní
tiketovou větev bez ptaní, takže posloupnost dvou jednotlivě povolených
příkazů — push vlastní větve, pak FF push do báze — dostane na sdílenou větev
libovolný agentem napsaný obsah. Pravidlo obsahu tedy **nenahrazuje** pravidlo
aktéra; drží ho jen vrstva z bodu 3. Kontrakt tuto hranici zná: skutečným
backstopem proti odhodlanému aktérovi zůstává ochrana větví na serveru.

Formulace „commity, které prošly review na tiketové větvi" je proto z tohoto
návrhu odstraněna jako nepravdivá. Ze stejného důvodu se tu **nelze opírat
o playbook** — jeho pravidlo o `branch -r --contains` říká přesný opak
(brána, která tímto příkazem testuje „už pushnuto", přestane testovat to, co
její vlastní próza tvrdí, protože commit je na originu přes tiketovou větev).

### 3. Práce se rozdělí mezi dvě vrstvy

Rozdělení není zdvojená pojistka; každá vrstva dostane **jinou** otázku.

| Vrstva | Otázka | Působnost |
|---|---|---|
| git `pre-push` | *Co* se pushuje | Cokoli, co běží v agentní session — včetně příkazů zadaných s vykřičníkem |
| `guard-git-push.mjs` (PreToolUse) | *Kdo* pushuje | Jen volání nástroje agentem (podmíněno prerekvizitním měřením) |

Guard zakáže agentovi jeho vlastní push do chráněné větve **včetně**
integračního fast-forwardu, a nese tedy pravidlo „okamžik integrace patří
člověku" sám. Uživatelův `git push origin HEAD:<báze>` zadaný s vykřičníkem
projde: guard na něj nestřílí a hook ho propustí podle pravidla obsahu.

Guard se opraví a zpřísní:

- matcher `Bash|PowerShell` — dnešní díra,
- **fail-closed pro rozpoznaný `git push`**: co neumí s jistotou rozparsovat
  jako neškodné, zamítne. Ostatní podpříkazy a bezkontextové kontroly zůstávají
  fail-open, aby se nemnožily falešné poplachy na obsahu dokumentů.
- **Push nesoucí `MB_HUMAN_PUSH` guard zamítne.** Přes guard chodí jen volání
  agenta a agent tu proměnnou podle kontraktu nenastavuje nikdy, takže její
  výskyt je sám o sobě porušením. Tím zůstává mechanická pojistka i s plně
  zvednutou výjimkou v hooku (bod 4). **Podmíněno prerekvizitou:** kdyby se
  ukázalo, že vykřičníkové příkazy guardem procházejí, musí guard výjimku
  naopak propouštět, jinak by vrstva blokovala příkaz, který sama uživateli
  podává.

**Dvě omezení, která je nutné pojmenovat, ne zamlčet:**

- Guard byl do dnešní role degradován po dvou kolech oponentury a fail-closed
  větev tu příčinu neruší. Případ, který ho porazil, je **nerozpoznání**: u
  tvaru `bash -c 'git push …'` není token `'git` rozpoznán jako git, žádný
  podpříkaz `push` se nenajde a fail-closed větev se nikdy nezapne. Zbytkový
  průchod se tímto přijímá jako známý; není to vrstva, o které lze tvrdit, že
  pravidlo drží bez mezery.
- V harnessech bez PreToolUse (Codex, Gemini, kilocode) vrstva aktéra chybí
  úplně, takže tam agent integrační FF push spustit může. Patří to do matice
  v [ums/README.md](../../../ums/README.md) jako jmenované omezení.

### 4. Lidská výjimka: `MB_HUMAN_PUSH`

`UMS_ALLOW_SHARED_PUSH` se přejmenovává na **`MB_HUMAN_PUSH`** a mění význam:
místo „zvedni pravidlo o sdílené větvi" znamená **„člověk za tenhle jeden push
přebírá odpovědnost"**, tedy v hooku zvedá celý guard — sdílenou větev, mazání
i force push. Hook to hlasitě oznámí na stderr.

Odůvodnění jména: síla té proměnné stojí výhradně na kontraktovém pravidle
„agent ji nenastaví nikdy". Jméno, které říká `HUMAN`, dělá z jejího napsání
agentem zjevnou lež — na jazykový model to působí jinak než neutrální `ALLOW_`.

Odůvodnění rozsahu: jakmile hook platí jen v agentní session, člověk v sezení
nese značku i při force pushi **vlastní tiketové větve** po rebasu. S úzkou
výjimkou by mu nezbylo než hooky úplně vypnout — tedy přesně ten folklor,
který tento návrh ruší. Mechanickou pojistku proti zneužití agentem drží
guard (bod 3), ne zúžení výjimky.

Po dobu přechodu hook **respektuje obě jména**; u starého vypíše na stderr
jednu řádku o zastaralosti. Bez toho by člověk se starým jménem v historii
shellu narazil po upgradu a člověk s novou dokumentací na neupgradovaném
workspace před ním.

### 5. Řetězení místo kolize

`install-git-hooks.ps1` u cizího `pre-push` přestane končit exitem 2. Odsune
ho na `.git/hooks/pre-push.ums-chained` (interní jméno, konzistentní
s existujícím `ums-protected-branches`), nainstaluje náš a ten na konci zavolá
řetězený hook se stejnými argumenty a se stejným stdinem.

Šest detailů, které rozhodují, jestli to funguje nebo něco tiše rozbije:

- **Řetězení se odmítne, když `core.hooksPath` je absolutní nebo pochází
  z globální či systémové konfigurace.** Ten adresář je sdílený s dalšími
  repozitáři a přejmenování cizího `pre-push` v něm by tiše přesměrovalo
  všechny. Exit 2 zůstává právě pro tento případ; řetězí se jen v adresáři
  hooků privátním pro repozitář.
- **Stdin se nejdřív celý načte do dočasného souboru a pak přehraje**, nikdy
  přes command substitution — ta podle playbooku není průhledný kanál a na
  msys se chová jinak než skutečný POSIX shell. `git lfs pre-push` čte tentýž
  seznam refů a dnešní `while read` ho spotřebuje beze zbytku; bez přehrání by
  LFS objekty přestaly odcházet, tedy selhání, které vypadá jako funkční stav.
- **Delegace platí i na rané ukončení.** Chybí-li značka (bod 1), hook nesmí
  prostě skončit nulou; musí předat řízení řetězenému hooku a vrátit **jeho**
  návratový kód. Jinak by instalace vrstvy vypnula LFS všem lidem v týmu.
- **Idempotence.** Opakovaný běh nesmí zřetězit náš hook sám se sebou ani
  přepsat už odsunutý cizí hook.
- **Provenience.** U řetězeného souboru se zaznamená, odkud a kdy vznikl, aby
  šlo poznat zbytek po nástroji, který v repozitáři už není (odinstalované
  LFS), a instalátor uměl ohlásit řetězený hook, který neumí přiřadit.
- **Ruční slepenec se nerozplétá.** Cizí hook se stopami našeho kódu hlouběji
  v těle (výsledek dřívější ad-hoc opravy) se hlásí a nechává být.

Self-test instalátoru se rozšíří o důkaz, že řetězený hook **doběhl a dostal
stdin**. Odinstalace (vrátit řetězený hook na původní jméno, náš odstranit) se
dokumentuje jako součást této práce.

### 6. Hladký přechod a sebekontrola

- **Značka v hlavičce hooku zůstává, verze se přidává za ni.** Instalátor
  pozná svůj hook podle řetězce `UMS pre-push guard (Publication Contract)`
  v prvních pěti řádcích. Kdyby se ten řetězec přepsal, nová verze by starou
  vyhodnotila jako **cizí** hook a podle bodu 5 by ji **zřetězila** — starý
  hook by dál blokoval člověka zevnitř řetězu. Prefix se proto nemění a
  instalátor svůj hook v každé verzi přepisuje, nikdy neřetězí.
- **Každý syntetický důkaz si musí značku sám nastavit.** Self-test
  instalátoru, náprava invariantu chráněné báze v kontraktu i recept
  v `mb-state` ověřují hook pipnutím syntetické řádky. Bez značky by hook
  legitimně prošel a všechny tři by hlásily „záruka není potvrzena" o hooku,
  který funguje — instalátor spouštěný člověkem z terminálu by skončil
  exitem 1 pokaždé.
- **Sebekontrola běží na začátku sezení a znovu před integrací.** Kompenzace
  obráceného směru degradace nemůže bydlet jen ve vstupní bráně
  brainstormingu: sezení, které vykonává plán nebo dokončuje větev, bránou
  vůbec neprochází, a přitom právě ono integruje. Kontrola „je hook
  nainstalovaný, je aspoň v2 a platí na tuhle session?" se proto přesune do
  SessionStart a fail-closed se zopakuje na začátku overlay
  `finishing-a-development-branch`.
- **Upgrade proběhne sám.** Při nálezu staré verze agent spustí
  `install-git-hooks.ps1` (zapisuje jen do `.git/hooks/` a do generovaného
  seznamu, nic nevratného) a pokračuje. Kdo si installer nespustí sám,
  dostane ho od prvního agentního sezení.
- **Konce řádků.** Hook je bezpříponový shellový soubor; pravidlo
  `text eol=lf` v [ums/.gitattributes](../../../ums/.gitattributes) platí dál
  a revendor normalizuje na LF.

## Rozvolnění, které tento návrh vědomě přijímá

Dnes rozhoduje o okamžiku integrace člověk proto, že mu hook ten příkaz
fyzicky nedá spustit. Po této změně to drží **jen vrstva aktéra**, tedy jen
v harnessech s PreToolUse a jen pro tvary příkazu, které umí rozpoznat. Jinde
se pravidlo stává kontraktovým závazkem jako řada jiných pravidel vrstvy.

Co zůstává mechanicky vynucené ve všech harnessech: na sdílenou větev
nepřistane nic, co není zároveň publikované pod nějakou větví na tomtéž
remote. To není záruka prohlédnutí — je to záruka **auditovatelnosti a
obnovitelnosti**: obsah je dohledatelný, posun báze je čistý posun ukazatele
a jde vrátit.

## Dopady

| Místo | Změna |
|---|---|
| Kontrakt, Publication Contract | Dvouúrovňová push policy „vlastní × sdílená" se nahrazuje dvojicí *aktér* + *obsah*; nová role, jméno a rozsah lidské výjimky; verze 2.10 → 2.11 |
| Kontrakt, Workspace Discipline | Fail-closed podmínka z „hook je nainstalovaný" na „hook je nainstalovaný, je v2 a platí na tuhle session" |
| Kontrakt, Repository Configuration | Náprava invariantu chráněné báze: syntetický důkaz musí nastavit značku |
| [pre-push](../../../ums/.claude/hooks/pre-push) | Brána na značku, pravidlo obsahu, řetězení, obě jména výjimky, verze v hlavičce |
| [install-git-hooks.ps1](../../../ums/.claude/hooks/install-git-hooks.ps1) | Řetězení s odmítnutím u sdíleného `core.hooksPath`, provenience, značka pro důkazní běhy, nový self-test, změna významu exit 2 |
| [guard-git-push.mjs](../../../ums/.claude/hooks/guard-git-push.mjs) | Matcher, fail-closed pro rozpoznaný `push`, zamítnutí výjimky, nositel pravidla o aktérovi |
| [settings.json](../../../ums/.claude/settings.json) | `env` se značkou, rozšířený matcher |
| [sync-with-monorepo.ps1](../../../ums/sync-with-monorepo.ps1) | Injektáž značky do konfigurace Codexu, Gemini a kilocode |
| [mb-state](../../../ums/.claude/skills/mb-state/SKILL.md) | Řádek `Workspace:` hlásí verzi hooku a značku; recept ověření značku nastavuje |
| Overlay `brainstorming` | Formulace fail-closed podmínky vstupní brány |
| Overlay `finishing-a-development-branch` | Integrační příkaz bez prefixu; fail-closed sebekontrola na začátku |
| [mb-abort](../../../ums/.claude/skills/mb-abort/SKILL.md), [mb-jira-update](../../../ums/.claude/skills/mb-jira-update/SKILL.md) | Výskyty starého jména výjimky v próze i v podávaném příkazu |
| [CLAUDE.md.sample](../../../ums/CLAUDE.md.sample), kořenový [CLAUDE.md](../../../CLAUDE.md) | Totéž |
| [ums/README.md](../../../ums/README.md) | Matice harnessů: chybějící vrstva aktéra mimo Claude Code |
| MB dokumenty | Při harvestu: [brief.md](../../brief.md) (Co vrstva záměrně nedělá), [architecture.md](../../architecture.md) (Publikační invariant, Dvouvrstvá mechanika vynucení, integrační příkaz, invariant 6), [tech.md](../../tech.md) (verze, konfigurace, testy), [playbook.md](../../playbook.md) (instalační sekce a významy exit kódů) |

Po každé změně zdroje v `ums/.claude/` je nutná obnova nasazené kopie
v kořenovém `.claude/` a `.agents/skills/`, jinak sezení pracuje podle staré
verze (playbook, sekce Obnova nasazené kopie v tomto repu).

## Testy

Obě sady už běží proti skutečnému gitu s lokálním bare remote, takže se
rozšiřují, nezakládají.

- **Značka, párově.** Tatáž řádka refu dvakrát: se značkou → zamítnuto, bez
  značky → průchod. Bez téhle dvojice by sada nepoznala hook, který propouští
  bez ohledu na značku. Sada si navíc musí značku **explicitně odstranit a
  její nepřítomnost ověřit** před no-marker případy — jinak běh uvnitř
  agentního sezení tiše testuje opak (stejná izolace, jakou sada už dělá pro
  `GIT_CONFIG_GLOBAL`).
- **Pravidlo obsahu.** Chráněná větev + non-fast-forward → zamítnuto; FF
  s vrcholem dosažitelným na cílovém remote → průchod; FF s commitem, který
  na cílovém remote není → zamítnuto; commit dosažitelný jen na jiném remote
  → zamítnuto.
- **Výjimka.** Obě jména včetně řádky o zastaralosti; force push a mazání pod
  novou výjimkou → průchod; push více refů najednou (regrese na krádež stdinu).
- **Řetězení.** Cizí hook zachovaný a přejmenovaný; stdin přehraný v plném
  rozsahu, testováno na **více refech** a pod skutečným POSIX sh, ne jen msys;
  návratový kód řetězeného hooku propagovaný; delegace i bez značky; opakovaná
  instalace idempotentní; sdílený `core.hooksPath` → odmítnuto s exit 2; ruční
  slepenec ohlášený a nedotčený. Ověřit i proti **skutečnému** LFS hooku.
- **Self-test instalátoru.** Běh z prostředí bez značky musí projít (instalátor
  si značku nastavuje sám) — přesně scénář ruční instalace člověkem.
- **guard-git-push.** Agentní FF push do chráněné větve zamítnutý;
  nerozparsovatelný `push` zamítnutý; push s `MB_HUMAN_PUSH` zamítnutý;
  příkazy mimo `push` dál fail-open.
- **Negativita.** Každý nový strážce ověřit i proti neopravenému kódu podle
  pravidla v [playbook.md](../../playbook.md) a v reportu oddělit důkazy od
  regresních zámků.
