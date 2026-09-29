# Návrh: Upgrade na superpowers v6.4.2, nasazovací skript jako master a epik s povinnými odpověďmi

- **Jira:** (žádný tiket)
- **Target MB:** memory-bank/
- **Vytvořeno:** 2026-09-29

## Cíl

Uživatel chce tři věci, které spolu souvisí přes nasazení vrstvy:

1. **Vrstvu UMS zvednout na poslední vydaný upstream superpowers v6.4.2**
   (dnes pin v6.3.0) tak, aby po revendoru nezůstal v žádném nasazeném skillu
   rozporný instrukční text — a aby pravidla vrstvy platila i pro novou
   „Native" exekuci (`executing-plans`) a přežila kompaktaci kontextu.
2. **Nasazovací skript `sync-with-monorepo.ps1` má nasazovat i vendorované
   superpowers skilly** (včetně jejich skriptů), výchozím směrem má být
   **do monorepa** (`ToMonorepo`), ne z něj, a má pokrýt všechny harnessy,
   které superpowers podporuje; nepodporované (kilocode) se ruší.
3. **Orchestrace epiku:** zprávy mezi správcem epiku a tiketovým sezením
   vyžadují odpověď v obou směrech, a v režimu epiku se zakládá a používá
   **nechráněná** epiková integrační větev místo `develop`, do které agenti
   smějí pushovat (jen fast-forward).

Kritérium úspěchu: revendor v6.4.2 projde verifikací; overlaye pokrývají obě
metody exekuce a po kompaktaci se k nim model vrátí; jeden běh syncu nasadí
celou vrstvu včetně vendorovaných skillů do monorepa, profilu i kořene forku
a nikdy tiše nepřepíše změnu, která vznikla v cíli; epik integruje přes
nechráněnou linii bez lidského pushe mezi tikety.

Rozsah je jedna pracovní položka ve fázích — rozdělení nesplňuje kritéria
(kontrakt/epic-backflow.md, „Split criteria and the cost of a split"): stejný
aktér, stejná dodávka (`ums-memory-bank`).

## Co v6.4.2 přináší a kde se to potkává s vrstvou

| Upstream v6.4.2 | Vrstva UMS dnes | Uzavření |
|---|---|---|
| `writing-plans`: menu „Subagent-driven / Native" s doporučením; věta `**Which approach?"**` zmizela | overlay kotví `ANCHOR-BEFORE: **Which approach?"**` — revendor by spadl | nová kotva a ASSERTy, Fresh Session jako modifikátor obou metod (sekce 2.4) |
| `executing-plans` přestavěný na plnohodnotnou Native exekuci se sdíleným ledgerem a workspace SDD | žádný overlay — base sync, publikace, playbook, rotace kontextu, NOW by se u Native tiše vypnuly | pátý overlay + pravidla rozprostřená do existujících referencí (sekce 2.1–2.3) |
| `writing-plans/plan-document-reviewer-prompt.md` smazán | verifikace revendoru ho vyžaduje | vypustit z verifikace (sekce 1.3) |
| nový skill `diagnosing-superpowers` (čte transkripty sezení, po schválení zakládá issue/archiv na GitHubu) | seznam 14 skillů natvrdo v revendoru | skill se NEvendoruje (chování superpowers je deformované overlayem a hrozí únik kódu); dynamický seznam s explicitním vyloučením, 14 skillů (sekce 1.2) |
| brainstorming: „Establish Shared Understanding", HARD-GATE „written-spec approval only permits invoking writing-plans" | overlay mezi schválení spec a writing-plans vkládá oponenturu a Architect Review Gate | ASSERT na větu + jmenovitý dodatek (sekce 2.5) |
| finální review: `MERGE_BASE` např. `git merge-base main HEAD` | v tomto forku je `main` zrcadlo upstreamu — balík by nesl celou historii UMS | pravidlo efektivní báze pro každý rozsah (sekce 2.2) |
| upstream smazal kořenový `CLAUDE.md` (návody přesunuty do `AGENTS.md`) | fork má `CLAUDE.md` upravený s blokem UMS — merge konfliktuje (modify/delete) | fork-vlastní `CLAUDE.md` = `@AGENTS.md` + blok forku (sekce 1.1) |
| TDD: zelenou definuje celá sada projektu; review: „Declined to judge", `git merge-base origin/main HEAD`; SDD: vlastnictví workspace markerem `plan-path`; skripty volané přes interpret | — | bez zásahu; předpoklad o cestě ledgeru zapsán (sekce 2.6) |

Nezávisle na upstreamu, ale odhalené při jeho analýze: **Claude Code po
kompaktaci znovu vloží tělo vyvolaného skillu, nejvýš 5 000 tokenů na skill**
(dokumentace Claude Code, context window). Overlaye stojí na konci souborů
nebo blízko něj — odhad (znaky / 3,5):

| Skill | Celkem | Overlay začíná na | Důsledek |
|---|---|---|---|
| `subagent-driven-development` | ~12,3k tok | ~9,2k | overlay celý za limitem |
| `finishing-a-development-branch` | ~10k | ~0,8k | ~9,2k overlaye, většina za limitem |
| `brainstorming` | ~9,7k | ~4,4k | skoro celý za limitem |
| `executing-plans` v6.4.2 | ~5,8k samotný upstream | — | nový overlay celý za limitem |
| `writing-plans` | ~2,9k | ~1,9k | vejde se |

Směr ořezu dokumentace neuvádí. Oprava je v sekci 2.7.

## Scope

### V rozsahu

1. Převzetí driftu monorepa do forku (53 řádků UMS-3588 v
   `shared/contract/playbook-contract.md`) jako první commit.
2. Merge upstreamu v6.4.2, vyřešení `CLAUDE.md` forku, revendor skript
   (dynamický seznam, `-SkillsRoot`, `-PinOnly`, tag z pinu, víc fragmentů na
   cíl, verifikace), bump pinu.
3. Kontrakt 3.1 → 3.2: rozprostření pravidel exekuce, pět overlayů
   s hlavičkovými ukazateli, `contract-inject` po kompaktaci.
4. Přepracování `sync-with-monorepo.ps1` (sekce 3) s novou testovací sadou.
5. Orchestrace epiku (sekce 4): povinné odpovědi, nechráněná linie epiku.
6. Dokumenty vrstvy, nasazení do forku novým `-Scope Fork`, verifikační
   baterie; na konci harvest do Memory Bank.

### Mimo rozsah (vědomě)

- **Kroky na chráněných větvích a v monorepu spouští uživatel** — agent
  připraví příkaz nebo diff: fast-forward zrcadla `main` na `vanila/main`;
  první `ToMonorepo` deploy do monorepa a jeho dva revendorové commity
  (monorepo teď stojí na tiketové větvi UMS-2890 — kam nasadit, rozhodne
  uživatel). Konfigurační krok v `ums-repo.json` monorepa odpadá díky
  vestavěnému defaultu `epic/*` (sekce 4.2).
- **Pojmenovaný odklad:** rozdělení projektových pravidel monorepního
  `CLAUDE.md` (sekce „WF engine" a další) do samostatných sekcí nebo do
  playbooků — patří do konsolidace playbooku. Tato práce jen zařídí, že sync
  spravuje výhradně blok superpowers × MB a projektová pravidla nechává být.
- **Bootstrap `using-superpowers` v harnessech bez pluginu** (upstream
  akceptační test) — vrstva nasazuje skilly do nativních adresářů; zavedení
  bootstrapu per harness je samostatná práce.
- Jakékoli změny upstream souborů mimo `ums/` (aditivní invariant) — s
  výjimkou `CLAUDE.md`, který se tímto stává souborem, jenž v upstreamu
  neexistuje.

## Technický návrh

### 1. Upgrade upstreamu na v6.4.2

#### 1.1 Merge a `CLAUDE.md` forku

`git merge vanila/main` (tip `8ca22db` je release commit v6.4.2). Zkušební
`git merge-tree` ukázal jediný konflikt: `CLAUDE.md` (modify/delete). Upstream
ho smazal, protože Claude Code čte `AGENTS.md` jen tehdy, když `CLAUDE.md`
neexistuje. Řešení: fork si `CLAUDE.md` ponechá jako **vlastní soubor**
s prvním řádkem `@AGENTS.md` (import upstream návodů, aby je Claude Code
dál viděl) a za ním dnešní blok `UMS-MEMORY-BANK` forku beze změny obsahu
(kromě vět, které tento návrh mění — sekce 5). Soubor pak v upstreamu
neexistuje, takže budoucí mergy zůstávají bezkonfliktní; věta „tato sekce
CLAUDE.md na konci souboru" v rolích větví se přepíše na „`CLAUDE.md` forku".

Zrcadlo `main` je 55 commitů za `vanila/main`; jeho fast-forward je chráněná
větev — příkaz připraví agent, spustí uživatel.

#### 1.2 Seznam vendorovaných skillů

Revendor přestane nést seznam natvrdo: vendoruje **všechny adresáře
`skills/` pinovaného tagu kromě vyloučených**. Vyloučení je explicitní
seznam `Excluded:` ve `VENDORED_FROM.md` forku; v6.4.2 vylučuje
`diagnosing-superpowers` — čte transkripty sezení a po schválení zakládá
issue nebo archiv na GitHubu (`obra/superpowers`), což je v proprietárním
monorepu kanál pro únik kódu, a hlásil by upstreamu chování, které overlay
UMS záměrně deformuje. Vendorovaných skillů je tedy dál 14.

**Nový upstream skill, který není ani v předchozím pinu (`Skills:`), ani
v `Excluded:`, revendor zastaví** a vyžádá si rozhodnutí — nic nového se
nevendoruje potichu. Skill, který upstream mezi piny zruší, z cíle smaže
podle řádků `Skills:` předchozího `VENDORED_FROM.md` v cíli. Fragment
mířící na neexistující cíl zůstává hard error.

#### 1.3 Revendor skript

- **Verifikace:** vypustit požadavek na `writing-plans/plan-document-reviewer-prompt.md`;
  přidat `executing-plans/scripts/task-start` a `task-done` (bash bez
  přípony — pokryje je i CRLF kontrola). Funkční test `sdd-workspace` zůstává
  (marker `plan-path` v6.4.2 adresář při prvním použití nemění), ale
  cestu skriptu bere relativně k `-SkillsRoot` a v cíli mimo git repozitář
  (profil uživatele — `sdd-workspace` potřebuje `git rev-parse
  --show-toplevel`) se přeskočí s ohlášením, ne potichu.
- **`-SkillsRoot <cesta>`** — dnes je cíl natvrdo `<UmsRoot>/.claude/skills`;
  sync ho potřebuje pro `.agents/skills`, `.qwen/skills` atd.
- **Tag z pinu:** bez `-Tag` si revendor přečte tag z `VENDORED_FROM.md`
  v `shared/` cíle (tam ho sync právě zrcadlil z forku).
- **`-PinOnly`** zapíše tag a commit do `VENDORED_FROM.md` zadaného kořene
  bez vendoringu — tím se dělá bump pinu ve forku (`-UmsRoot ums`).
- **Víc fragmentů na jeden cíl** (hlavičkový ukazatel + tělo, sekce 2.7):
  kontrola „cíl je pristine" proběhne jednou na cíl před jeho prvním
  fragmentem, ne u každého fragmentu.
- **Kontrola polohy ukazatele:** každý overlayovaný skill nese blok
  ukazatele v prvních 12 000 znacích souboru.

`VENDORED_FROM.md` ve forku je od teď **jediný zdroj pravdy o tagu**; řádek
„Vendored on top of repo state" zůstává per-repo hodnotou cíle.

### 2. Kontrakt 3.2 a overlaye

#### 2.1 Pravidla exekuce plánu — rozprostřená, ne sloučená

Varianta „jedna nová reference `plan-execution.md`" byla zvážena a
zamítnuta: většina pravidel, která dnes nese overlay SDD, už domov má
(jádro: Base Sync & Drift Detection, Publication Contract, Fail-Closed
Behavior, Language Contract, Worktree Policy; `playbook-contract.md`;
`now-block.md`; `session-intent-baton.md`). Sloučený soubor by je buď
převyprávěl (porušení „jeden fakt, jeden domov", které `contract-shape`
sémanticky nepozná), nebo byl rozcestník — a byl by organizovaný podle
konzumenta, ne tématu, tedy tvar monolitu, který se dřív drobil.

Bez domova jsou jen čtyři drobnosti a každá jde do reference svého tématu:

| Pravidlo | Cíl |
|---|---|
| Pátá, předávací stop třída: jen na hranici tasku, obnovené sezení nespouští znovu base sync ani baseline, úsudek ne měření; `Instruction:` jmenuje právě běžící exekutor | `session-intent-baton.md` |
| Kdy se přepisuje blok NOW — pro SDD (dispatch, report, konec tahu) i Native (začátek tasku, `task-done`, konec tahu) | `now-block.md` |
| Kandidáti playbooku přežívají smazání plan workspace; u Native je zapisuje exekutor sám | `playbook-contract.md` |
| Každý rozsah proti bázi (review balík, `MERGE_BASE`, intersekce) se počítá z efektivní báze, nikdy z lokálního `main` | `repository-configuration.md`, u efektivní báze |

#### 2.2 Overlay SDD

Zúží se na banner s citacemi referencí a mechaniku specifickou pro SDD:
explicitní model u každého dispatche a nejlevnější tier pro summarizaci;
cesta k sestavenému řetězci playbooků u každého dispatche i dávky; sekce
`## Playbook candidates` v reportu implementátora; české commit messages
implementátorů; čtení „outside this worktree" jako klon/workspace. ASSERTy
zůstávají.

#### 2.3 Nový overlay `executing-plans`

Kotva `EOF`; ASSERTy na „Four things stop you, and only these: an
irreversible or destructive" a na větu o workspace a ledgeru sdíleném se
SDD. Banner cituje **stejnou sadu referencí** jako overlay SDD — nová aserce
v `contract-shape.tests.ps1` hlídá, že se bannery nerozejdou. Lokálně:
exekutor čte řetězec playbooků sám (nepřikládá ho), kandidáty playbooku
zapisuje sám stejným formátem a přes `Find-UmsPlaybookMatch`, finální
reviewer má explicitní model; a stejná odrážka o izolaci jako v SDD —
upstream Setup „use superpowers:using-git-worktrees to create one" se čte
jako větev na místě a „a side effect outside this worktree" jako mimo
tento klon/workspace (na harnessech bez mechanického zákazu worktree je
text jediné vynucení).

#### 2.4 Overlay `writing-plans`

Nová kotva `ANCHOR-BEFORE: **When an execution method has already been supplied:**`,
ASSERTy na obě položky upstream menu (Subagent-driven, Native) a na celý
řádek `**"Plan complete and saved to … Please review the plan. Which
execution approach would you prefer?**` (v6.4.2 má dva řádky začínající
„Plan complete…" a ASSERT musí matchovat právě jeden). Obsah:

- sekce `## Ověřovací sada` v plánu (beze změny tvaru);
- oprava cesty `docs/superpowers/plans/` na
  `<PLAN_MB>/proposals/active/plan_<slug>.md`;
- **Fresh Session jako modifikátor obou metod:** po volbě metody jedna
  doplňující volba „v tomto sezení / v čerstvém". Nabízí se jen při splněné
  precondici zapisovatele batonu a jen nad plánem, který uživatel už prošel
  (upstream nově vyžaduje revizi plánu před exekucí). `Instruction:` batonu
  `plan-execution` jmenuje zvolený skill (`subagent-driven-development` nebo
  `executing-plans`).

#### 2.5 Overlay `brainstorming`

ASSERT na větu HARD-GATE „written-spec approval only permits invoking
writing-plans" a jmenovitý dodatek: v UMS stojí mezi schválením spec a
writing-plans nabídka oponentury a Architect Review Gate (v souladu
s dnešním pozměněním terminálních stavů). Jedna věta: upstream „Carry
intent into the design" se v návrhu propisuje do sekce `## Cíl`.

Overlay `finishing-a-development-branch`: obsahově beze změny, jen dostane
hlavičkový ukazatel (sekce 2.7) a úpravu fáze Handoff pro epik (sekce 4).

#### 2.6 Hooky a předpoklady

- `session-intent.ps1` validuje `Instruction` proti adresářům skillů
  nasazení — `executing-plans` projde bez změny kódu; přibude test.
- `contract-inject.ps1` dnes čte ledger natvrdo z
  `.superpowers/sdd/plan_<slug>/progress.md`. V6.4.2 ale při kolizi
  basename (typicky znovu rozjetý slug po abortu — `mb-abort` plan
  workspace nemaže) založí `plan_<slug>-<rodič>/` a hook by četl blok NOW
  opuštěného běhu. Hook proto najde ledger podle markeru `plan-path`
  (hodnota = cesta `plan_<slug>.md` aktivního páru); bez shody žádný blok.
  Test pokryje kolizní případ; `now-block.md` popíše domov ledgeru přes
  marker, ne přes jméno adresáře.

#### 2.7 Přežití kompaktace

Dvě úpravy, obě v existujících mechanismech:

1. **Hlavičkový ukazatel** v každém z pěti overlayovaných skillů — druhý
   malý blok `UMS-OVERLAY` (3–5 řádků) hned za frontmatter, kotvený
   `ANCHOR-BEFORE` na řádek H1 a chráněný ASSERTem: skill v tomto repu nese
   na konci blok UMS-OVERLAY, který váže; je-li tělo skillu po kompaktaci
   oříznuté, přečti ten blok ze souboru dřív, než budeš pokračovat. Přežije
   ořez v obou směrech (zachovaný začátek nese ukazatel, zachovaný konec
   blok).
2. **`contract-inject` po kompaktaci:** dnešní pokyn „re-invoke the skill
   you are executing" jde přes `systemMessage` hooku `PostCompact`, u něhož
   dokumentace neříká, zda ho model vidí. Pokyn v `additionalContext`
   (který model prokazatelně dostává) se rozšíří o: tělo vyvolaného skillu
   mohlo být znovu vloženo oříznuté na 5 000 tokenů — přečti jeho
   UMS-OVERLAY blok. Plus test.

Čerstvé sezení přes `/clear` s batonem je pokryté beze změny: baton nese
`Instruction:` se jménem skillu, sezení skill vyvolá a načte celý
`SKILL.md` s overlayem.

#### 2.8 Kontrakt, jádro

„čtyři overlaye" → pět; řádky Phase Map (Playbook Contract, Session Intent
Baton, The `NOW` Block) doplní „overlay executing-plans"; zmínka „(v6.3.0)"
v „Rulings and these STOPs" se zobecní; v „Citation & Versioning" jedna věta
o hlavičkovém ukazateli. Za sekci 4 přibývají: řádek dna eskalace
„Choosing a base that is not a protected branch" dostane výjimku pro linii
epiku, „Rulings and these STOPs" přestane jmenovat nechráněnou bázi bez
výjimky, a Message Protocol jednu větu o povinné odpovědi (mechanika je
v `message-protocol.md`). Jádro má 799 řádků z rozpočtu 800 — přírůstky se
vyváží zhuštěním (hlídá `contract-shape.tests.ps1`). Doklad s naměřenými
velikostmi skillů a limitem 5 000 tokenů.

### 3. Nasazovací skript `sync-with-monorepo.ps1`

#### 3.1 Směr a role kopií

Výchozí `-Direction` je `ToMonorepo` (v interaktivní nabídce volba 1).
**Master kopií vrstvy se stává fork.** `FromMonorepo` zůstává jako vědomý
tah změn udělaných v monorepu zpět, jen pro `claude` + `Monorepo`;
vendorované skilly zpět nikdy netáhne.

#### 3.2 Ochrana proti driftu

Po úspěšném běhu (i `FromMonorepo`) se zapíše **manifest**: relativní cesta
→ SHA256 obsahu po normalizaci na LF, SHA commitu forku, čas. Leží v
`git rev-parse --git-dir` cíle — **per worktree**, ne ve sdíleném common
dir: `.claude/` i `.agents/` jsou v monorepu trackované, takže pool sloty
na jiných větvích nesou jiný obsah a společný manifest by u každého hlásil
falešný drift. Cíl bez gitu ho má v config adresáři. Před zápisem se
porovnají tři stavy —
cíl, manifest, fork:

- soubor změněný v cíli od posledního nasazení, jehož změnu fork nemá →
  STOP se seznamem souborů a nabídkou `-Direction FromMonorepo` nebo
  `-Force`;
- bez manifestu (první běh) → STOP na každý rozdíl;
- adresář `mb-*` jen v cíli → varování.

Manifest pokrývá i vendorované skilly — ruční úprava v cíli se chytí.
Přepínač `-WhatIf` vypíše, co by zapsal, a ohlásí drift, nic nezmění.

#### 3.3 Vendorované skilly

Pro každý cíl s adresářem skillů se volá revendor forku s
`-SkillsRoot <cíl>`; tag čte z pinu FORKU a overlaye z `shared/overlays/`
právě nasazeného do cíle, takže past „revendor čte zastaralou kopii
fragmentů" odpadá.

- **Stejný tag nebo netrackovaný cíl:** jeden průchod — zrcadlení UMS
  položek (včetně `shared/`), pak revendor s overlayi. Revendor po
  zrcadlení přepíše `VENDORED_FROM.md` v cíli, takže řádek „Vendored on top
  of repo state" zůstává per-repo hodnotou cíle.
- **Změna tagu u cíle trackovaného gitem** (monorepo): první běh provede
  **jen vanilla fázi** — revendor nového tagu bez overlayů, NIC dalšího
  (žádné zrcadlení `shared/`, hooků ani `mb-*`) — a skončí s pokynem
  commitnout „vanilla sync" a spustit ho znovu. Commit tak nese jen upstream
  diff (playbook: první commit jen upstream, druhý jen zásah UMS). Druhý
  běh zrcadlí vrstvu a aplikuje overlaye — commit „overlay".

#### 3.4 `CLAUDE.md` a instrukční soubory

Pro `claude` stejný mechanismus bloku mezi markery jako u ostatních agentů.
`CLAUDE.md.sample` ponese jen sekce kontrakt, preference a zákaz worktree;
sekce „WF engine" z něj zmizí a zůstane jen v monorepním `CLAUDE.md`.
**Migrace při prvním běhu:** v cíli bez markerů sync najde sekce se jmény,
která patří bloku, nahradí je blokem na místě první z nich a zbytek souboru
nechá být; liší-li se od sample, je to drift podle 3.2. `FromMonorepo`
vytáhne do sample jen obsah bloku.

#### 3.5 `-Scope Fork`

Kořen = git toplevel forku. `claude` → `.claude/` (`settings.json`, hooky,
`scripts/`, `shared/`, `mb-*`, vendorované skilly); ostatní harnessy → jejich
adresář skillů. Instalace `pre-push` ano. Instrukční soubory ne — `CLAUDE.md`
forku je ruční a `AGENTS.md` je upstream soubor. **Nasazení nesmí špinit
strom:** upstream `.gitignore` ignoruje jen `.claude/`, zatímco `.agents/`
je trackovaný upstream adresář (`.agents/plugins/marketplace.json`) —
`.agents/skills/` dnes skrývá jen `.git/info/exclude` tohoto klonu. Scope
Fork proto do `.git/info/exclude` zapíše (idempotentně) řádek pro každý
adresář skillů, který nasazuje a který git neignoruje; `.gitignore` zůstává
nedotčený (aditivita). Jinak by `git status --porcelain` nebyl prázdný
a vstupní brána i base sync by stály na „špinavém stromu". Tím odpadá ruční
obnova nasazení, kterou dnes popisuje asi osm pravidel a pastí playbooku.

#### 3.6 Harnessy

Tabulka `$AgentTargets` pro 15 harnessů superpowers v6.4.2 (průzkum
upstream dokumentace a oficiálních stránek harnessů, 2026-09-29); kilocode
se ruší (upstream ho nepodporuje).

| Harness | Skilly (projekt / profil) | Instrukce (projekt / profil) | Marker `MB_AGENT_SESSION` |
|---|---|---|---|
| Claude Code | `.claude/skills` / `~/.claude/skills` | `CLAUDE.md` / `~/.claude/CLAUDE.md` | `settings.json` `env` (projekt); hook má fallback `CLAUDECODE` |
| Codex | `.agents/skills` / `~/.agents/skills` | `AGENTS.md` / `~/.codex/AGENTS.md` | `config.toml` `[shell_environment_policy] set` |
| Gemini CLI | `.agents/skills` / `~/.agents/skills` | `GEMINI.md` / `~/.gemini/GEMINI.md` | `.gemini/.env` |
| Qwen Code | `.qwen/skills` / `~/.qwen/skills` | `QWEN.md` / `~/.qwen/QWEN.md` | `.qwen/.env` |
| OpenCode | `.agents/skills` / `~/.agents/skills` | `AGENTS.md` / `~/.config/opencode/AGENTS.md` | plugin s hookem `shell.env` |
| Pi | `.agents/skills` / `~/.agents/skills` | `AGENTS.md` / `~/.pi/agent/AGENTS.md` | nejdřív ověřit fallback `AI_AGENT=pi`, jinak `shellCommandPrefix` |
| Hermes | `.agents/skills` / `~/.hermes/skills` | `.hermes.md` / — | jen profil: `env_passthrough` + `~/.hermes/.env` |
| Cursor, Copilot CLI, Devin, Droid, Kimi, Muse, Antigravity | `.agents/skills` / `~/.agents/skills` (Antigravity profil `~/.gemini/antigravity-cli/skills`) | `AGENTS.md`, kde ho čte; Copilot `.github/copilot-instructions.md`; bez souboru se ohlásí | nedoloženo — pojmenované varování „záruka tu neplatí" |
| Grok Build | `.grok/skills` / `~/.grok/skills` | `AGENTS.md` / — | nedoloženo — varování |

`-Agent` přijme seznam; cíle sdílené více harnessy (`.agents/skills`,
`AGENTS.md`) se zapíšou jednou. Každý mechanismus markeru a každá cesta se
před implementací znovu ověří proti primární dokumentaci (pravidlo
playbooku); nedoložené se nehádá, ohlásí se. Lepidlo (`hooks/`, `scripts/`)
se ostatním harnessům dál přimergovává do config adresáře beze změny
chování; `settings.json` dostává jen Claude. `ums/README.md` dostane pokyn:
v cílech UMS neinstalovat superpowers zároveň jako plugin (skilly by byly
dvakrát, jednou bez overlaye).

### 4. Orchestrace epiku

#### 4.1 Povinná odpověď na zprávy správce ↔ tiket

- **Každá zpráva** mezi správcem epiku a tiketovým sezením **vyžaduje
  odpověď, v obou směrech.** Směr správce → tiket si ponechává značku
  `Mark: instruction | conjecture`; zpětný směr dál značku nenese — autorita
  zůstává jednosměrná.
- **Odpověď** má první řádek `Re: <čas UTC původní zprávy>` a jedno ze tří:
  „přijato — udělám X", „odmítnuto — pravidlo / moje měření", nebo věcnou
  odpověď. **Na odpověď se neodpovídá** (žádná smyčka). Odmítnutí domněnky
  dál nepotřebuje svolení, ale už ne mlčky.
- **Oznámení** je jediná pojmenovaná třída zprávy bez povinné odpovědi:
  fakt o VLASTNÍM úkonu odesílatele, ověřitelný příjemcem ve sdíleném
  artefaktu (typicky „fast-forward proběhl, tip `<SHA>`" — ověřitelné
  `git fetch`). Nese první řádek `Oznámení:`; příjemce na něj jedná (správce
  zapíše poznámku do ledgeru), ale neodpovídá. Bez této třídy by potvrzení
  po pushi v sekci 4.2 bylo buď odpovědí na odpověď, nebo zprávou čekající
  na odpověď, kterou nikdo nepošle.
- **Kdy:** na nejbližší hranici tahu příjemce; sezení čekající na subagenta
  odpoví po jeho návratu (zákaz šťouchání do takového sezení platí dál).
- **Artefakt čekání:** tiketová strana — blok NOW se stavem
  `waiting-for-manager` a `Due`; správce — git-ignorovaný outbox
  `.superpowers/epic/<KLÍČ>/outbox.md` (komu, kdy, `Due`), který
  `mb-epic-run status` vykreslí jako nezodpovězené a opožděné zprávy.
- **Po `Due`:** jedno zopakování, pak eskalace člověku — žádné nekonečné
  čekání ani tichý pád.
- Domov: mechanika v `message-protocol.md`; v jádře (sekce Message
  Protocol) jedna věta, že zprávy správce ↔ tiket vyžadují odpověď kromě
  oznámení (rozpočet jádra, sekce 2.8). Konzumenti: `mb-epic-run` (spawn,
  status, integrate), overlay finishing (fáze Handoff). Stav pravidla se
  v `message-protocol.md` zapíše poctivě: nic ho mechanicky nespouští,
  outbox a blok NOW ho jen dělají viditelným.

#### 4.2 Nechráněná linie epiku

- **Konfigurace:** linie `epic/<KLÍČ>` se vyřazuje z chráněných větví.
  `epicBranchPattern` (výchozí `epic/*`) dostává novou roli —
  **identifikuje linii epiku jako legitimní nechráněnou bázi**. Invariant
  „integrační větev je vždy chráněná"
  (kontrakt/repository-configuration.md, „Repository Configuration")
  dostane jedinou jmenovitou výjimku pro linii
  odpovídající vzoru. **Chybějící klíč = vestavěný default `epic/*`**
  (rozhodnutí uživatele při oponentuře: epik má jet bez dalšího
  konfiguračního kroku; rozšíření privilegia tím rozhodl člověk v tomto
  návrhu, ne kód). Explicitně prázdná nebo nesmyslná hodnota = žádná
  výjimka, STOP pro nechráněnou bázi platí dál. Stav monorepa (2026-09-29): linie
  `origin/epic/SKODASMS-237` a `origin/epic/UMS-3557` existují, nejsou
  chráněné a `epicBranchPattern` chybí — dnešní kontrakt by je jako bázi
  zastavil; návrh ho uvádí do souladu s praxí.
- **Založení:** `mb-epic-run spawn` při prvním rozjetí tiketu epiku, když
  `origin/epic/<KLÍČ>` neexistuje, ji založí z dodávkové linie
  (`git push origin <sha dodávkové linie>:refs/heads/epic/<KLÍČ>`) a zapíše
  dodávkovou linii do hlavičky ledgeru epiku
  (`- **Dodávková linie:** origin/develop`). Tiketové větve epiku mají
  `Báze: origin/epic/<KLÍČ>`; `Get-UmsBaseCandidates` nabízí linie epiku
  mezi kandidáty a **spawn bázi jmenuje v promptu tiketového sezení**
  (dnes prompt ani ledger bázi nenese), takže volba báze ve vstupní bráně
  má doporučení, ne hádání.
- **Integrace „tiket po go správce":** tiket odešle předávací artefakt
  a čeká (NOW `waiting-for-manager`); `mb-epic-run integrate` provede
  kontroly epiku (`spawn-epic`, `decision-ack`), úsudkovou kontrolu nad
  epikem a handoff bránu, **sám nepushuje** a povinně odpoví **go**
  (s tipem linie, proti kterému kontroloval) nebo **STOP** (s blokující
  kontrolou); tiket na go udělá `git fetch`, ověří, že tip linie je pořád
  ten zkontrolovaný (jinak resync a nové předání), provede
  `git push origin HEAD:epic/<KLÍČ>`, potvrzení z báze a odpoví správci;
  správce zapíše poznámku do ledgeru.
- **Co zůstává hlídané:** hook dál zakazuje force push a mazání na každé
  větvi, tedy i na linii — do ní jde jen fast-forward. Výstup epiku do
  dodávkové linie a smazání linie po výstupu zůstávají lidské (dno
  kontraktu).
- **Co hlídané NENÍ (vědomě, rozhodnutí uživatele při oponentuře):**
  mechanicky nic nesváže to, co správce zkontroloval, s tím, co do linie
  dojde — hook pustí jakýkoli fast-forward z jakéhokoli agentního sezení,
  i bez „go" a i commit přidaný po předání. „Go" je pravidlo kontraktu,
  ne mechanismus; doklad `epic-line.md` to zapíše jako přijaté zbytkové
  riziko, aby pravidlo nevypadalo vynucené.
- **Úklid:** výjimka se čtyřmi podmínkami v `guard-git-push.mjs` a její
  testy se ruší (mrtvý kód); `epic-line.md` a jeho doklad se přepíšou;
  `Get-UmsRepoConfig` mění význam klíče a default.
- **Konzumenti starého invariantu**, které se musí přepsat, aby si
  kontrakt neodporoval: `contract/integration.md` (fáze Handoff — „jen
  správce provádí fast-forward pod výjimkou podle aktéra"); jádro (řádek
  dna eskalace „Choosing a base that is not a protected branch" a
  „Rulings and these STOPs" — nechráněná báze jako nevratný krok);
  `contract/workspace-discipline.md` (nabídka kandidátů báze jen
  z chráněných větví, STOP mimo `protectedBranches`);
  `contract/escalation.md` (pásmo správce); overlay `brainstorming` (krok
  „Choose the base", „do NOT continue with an unprotected base"); overlay
  SDD (věta „Shared branches are never pushed by the agent" — linie epiku
  sdílená je, ale nechráněná); `Get-UmsBaseCandidates.ps1` (hlavička
  „Offers only protected branches"); `mb-epic-run` (spawn, integrate,
  iron rules); overlay finishing (fáze Handoff a Confirmation);
  `ums/README.md` (řádek matice o pravidle podle aktéra). Plán začne
  grep sweepem vrstvy na „protected", „actor-rule exception", „manager
  performs" a „epicBranchPattern", aby výčet nebyl jen z paměti.

### 5. Dokumenty

`SKILLS_MANIFEST.md`, `ums/README.md` (verze, 14 skillů a vyloučený
`diagnosing-superpowers` s důvodem, 5 overlayů, matice harnessů, pokyn
o pluginu), `shared/CHANGELOG.md` (3.2), sekce forku v `CLAUDE.md` (fork je
master, výchozí `ToMonorepo`, `-Scope Fork`, pět overlayů),
`CLAUDE.md.sample` (bez sekce WF engine; odrážka „Exekuce plánu (SDD)" →
SDD i Native). Memory Bank (`brief.md`, `architecture.md`, `tech.md`)
aktualizuje harvest.

**Pravidla playbooku, která tato práce zneplatní nebo přepíše** (sekce
„Když nasazuješ nebo revendoruješ", části „Jen pro tento projekt"; zápis
do playbooku jde přes harvestovou bránu v režimu consult-before-write,
tento výčet je vstupem pro její schválení):

| Pravidlo (nadpis nebo první slova) | Osud |
|---|---|
| „Revendor spouštěj v monorepu, ne v tomto forku" | přepsat — revendor volá sync do každého cíle, fork je master |
| „Postup revendoru upstreamu (dvoucommitový)" | přepsat — kroky 2–3 dělá sync ve dvou bězích (sekce 3.3), bump pinu `-PinOnly` |
| tabulka „Parametry `sync-with-monorepo.ps1`" | přepsat — default `ToMonorepo`, `-Scope Fork`, `-WhatIf`, `-Force`, harnessy bez kilocode |
| „Traktuj `claude`+`Monorepo` jako jedinou obousměrnou kombinaci" | ponechat, doplnit, že `FromMonorepo` netáhne vendorované skilly |
| „Pořadí `FromMonorepo` → `ToMonorepo` je pevné" | vyřadit — nahrazuje ho ochrana proti driftu (sekce 3.2) |
| „Co `sync-with-monorepo.ps1` nasazuje a jak" (odrážka „Vendorované superpowers skilly tento skript nesynchronizuje nikdy") | přepsat |
| „Po každé změně zdroje v `ums/.claude/` obnov nasazenou kopii" a „Co je nasazená kopie" | přepsat na `-Scope Fork` |
| „Kontrola nasazení odhalí jen chybějící, ne zastaralé" (vendorované skilly srovnávat proti MONOREPO kopii) | přepsat — nasazení forku vendorované skilly nese, drift hlásí manifest |
| „Po každém revendoru dorovnej vendorované skilly i v `.agents/skills`" | vyřadit — sync nasazuje do každého adresáře skillů |
| „Po editaci overlay fragmentu v `ums/` nejdřív obnov nasazení, teprve pak spusť revendor" | vyřadit — pořadí zajišťuje sync sám |
| „Regenerace nasazených vendorovaných skillů po změně fragmentu bez upstream bumpu" | přepsat — `-Scope Fork` |
| „Editaci jen TĚLA overlay fragmentu ověřuj diffem, ne revendorem" (věta „`sync-with-monorepo.ps1` na tohle není — cílí na monorepo nebo profil") | přepsat — sync cílí i na kořen forku |

## Fáze a pořadí

0. Převzetí driftu monorepa (`playbook-contract.md`).
1. Upstream v6.4.2: merge, `CLAUDE.md` forku, revendor skript, bump pinu.
2. Kontrakt 3.2 a overlaye: rozprostření, pět overlayů s ukazateli,
   `contract-inject`, testy.
3. Sync skript + sada `sync-with-monorepo.tests.ps1` (fixtury: fork
   s tagem a fragmenty, monorepo jako git repo s lokálním bare originem).
4. Epik: povinné odpovědi a outbox; nechráněná linie, založení při spawn,
   integrace go → push tiketem; úklid guardu; testy.
5. Dokumenty; nasazení do forku `-Scope Fork` (jen na hranici fáze);
   verifikační baterie.

Pak finishing: harvest a integrace fast-forward pushem, který spouští
uživatel. Commity po logických celcích, každý pushnutý, česky s diakritikou.

## Verifikace

- **Ověřovací sada** (doslovné příkazy deklaruje plán): smyčka všech
  `*.tests.ps1` ve vrstvě; `revendor-superpowers.ps1 -VerifyOnly` nad
  nasazením forku; `sync-with-monorepo.ps1 -Scope Fork -WhatIf`.
- **Nové a upravené testy:** `sync-with-monorepo.tests.ps1` (default směr,
  drift STOP / `-Force` / po manifestu, vendorované skilly s overlayem
  a ukazatelem, dvoufázový režim při změně tagu, migrace bloku `CLAUDE.md`,
  `FromMonorepo` netáhne vendorované skilly, `-Scope Fork` nesahá na
  `CLAUDE.md` ani `AGENTS.md` a zapíše `.git/info/exclude` tak, že
  `git status --porcelain` zůstane prázdný, manifest per worktree, cíle
  harnessů, odmítnutý kilocode); revendor (nový upstream skill mimo pin
  i `Excluded:` zastaví běh, vyloučený skill se nenasadí, funkční test
  přeskočený mimo git repo s ohlášením); `contract-inject` (ledger podle
  markeru `plan-path` i v kolizním adresáři);
  `contract-shape` (bannery SDD a `executing-plans` citují stejnou sadu);
  `session-intent` (baton jmenující `executing-plans`); `contract-inject`
  (pokyn po kompaktaci); guard a `mb-epic-run` testy pro linii epiku
  a outbox.
- **Grep sweepy** na staré tvary: `Inline Execution`, `Two execution
  options`, `Which approach`, `v6.3.0`, „přesně 4" / „four overlays",
  `kilocode`, `FromMonorepo` jako default, `plan-document-reviewer`.
- **Cold-reader průchod** vygenerovaných skillů: cesta × metoda exekuce
  (SDD / Native) × čerstvé sezení / kompaktace.
- **Tabulka uzavření rozporů** upstream × vrstva ve vygenerovaných souborech
  (soubor:řádek), jako u upgradu na v6.3.0.

## Rizika

| Riziko | Zmírnění |
|---|---|
| Směr ořezu 5 000 tokenů po kompaktaci není zdokumentovaný | ukazatel v hlavičce + blok na konci přežijí oba směry; doklad s čísly |
| Harnessy mění cesty a env mechanismy | ověření proti primární dokumentaci před implementací; nedoložené = pojmenované varování |
| Ochrana proti driftu hlásí poplach po přepnutí větve v monorepu | nález jmenuje soubory a nabízí `FromMonorepo` / `-Force`; STOP je bezpečnější než tiché přepsání |
| Nechráněná linie epiku: agent do ní pushne, co správce neviděl | **přijaté zbytkové riziko** (rozhodnutí uživatele): „go" je text kontraktu, ne mechanismus; hook pustí jen fast-forward; výstup do dodávkové linie je lidský; doklad riziko pojmenuje |
| Vestavěný default `epic/*` rozšiřuje privilegium bez konfigurace | rozhodl člověk v tomto návrhu; explicitně prázdná hodnota ho vypne |
| Jádro kontraktu přeroste 800 řádků | přírůstky vyvážit zhuštěním; hlídá `contract-shape` |
| Plán přesáhne kontext jednoho sezení | pátá stop třída (rotace) a Fresh Session; hranice fází jako místa rotace |
| Duplicitní skilly při současně nainstalovaném pluginu | pokyn v `ums/README.md` |
| Nasazení do forku uprostřed exekuce změní skilly pod běžícím sezením | nasazovat jen na hranici fáze |

## Oponentura (2026-09-29)

Nezávislý oponent (čistý kontext, model Fable 5.1) vznesl 14 nálezů; všechny
ověřené proti kódu, žádný odmítnutý.

- **Zapracováno bez dotazu:** F1 výčet konzumentů starého invariantu
  (sekce 4.2, 2.8); F3 `.git/info/exclude` pro `-Scope Fork` (3.5); F4
  čistý commit „vanilla sync" (3.3); F5 funkční test revendoru relativní
  k `-SkillsRoot` a přeskočený mimo git (1.3); F6 třída oznámení (4.1);
  F7 izolace v overlayi `executing-plans` (2.3); F8 ledger podle markeru
  `plan-path` (2.6); F9 výčet pravidel playbooku (5); F10 ASSERT na celý
  řádek (2.4); F13 manifest per worktree (3.2); F14 mechanika odpovědí
  mimo jádro (4.1).
- **Rozhodnuto uživatelem:** F2 — linie epiku zůstává volná, „go" je jen
  text kontraktu, zbytkové riziko přijaté a pojmenované; F11 —
  `diagnosing-superpowers` se nevendoruje ani nenasazuje (deformované
  chování pod overlayem, riziko úniku kódu), odtud explicitní `Excluded:`
  a STOP na nový neznámý upstream skill; F12 — chybějící
  `epicBranchPattern` = vestavěný default `epic/*`.

## Verifikační evidence

Měřeno 2026-09-29 na větvi `upgrade-superpowers-6-4-2`. Cesty `soubor:řádek`
bez prefixu jsou relativní k NASAZENÉMU `.claude/skills/` kořene forku.

### Nasazení do kořene forku (`-Scope Fork`)

- **Nanečisto** (`sync-with-monorepo.ps1 -Scope Fork -Agent claude,codex -WhatIf`):
  exit 0. Protože manifest ještě neexistoval (první běh), nahlásil drift 35
  souborů pro `claude` a 31 pro `codex` vůči dosavadnímu ručnímu nasazení.
  Všechny ležely pod `.claude/` nebo `.agents/skills/` a žádný nebyl
  trackovaný gitem.
- **První ostré nasazení s `-Force` selhalo (exit 1)** na ověření revendoru
  v `.agents/skills`: „dangling link in shared\SKILLS_MANIFEST.md:
  ../../hooks/contract-inject.ps1".
  - Odkaz ze `shared/` mířil mimo kořen skillů. Resolvuje jen v rozložení
    Claude Code, kde `hooks/` leží vedle `skills/`. Cíl codex nese podle
    návrhu jen skilly (sekce 3.5), takže tam visel.
  - Ruční nasazení verifikaci nad `.agents/skills` nikdy nespouštělo.
    Fixtura `sync-fork.tests.ps1` odkaz tohoto tvaru nemá, proto ho testy
    neodhalily. `-WhatIf` verifikaci revendoru nespouští.
  - **Oprava v aed57a4:** každá cesta mimo kořen skillů je ve `shared/`
    prostý text, ne odkaz. `contract-shape.tests.ps1` nově hlídá, že žádný
    relativní odkaz ve `shared/` nemíří mimo kořen skillů (RED 1/31, GREEN
    31/31). Verifikace revendoru zůstala beze změny.
- **Opakované nasazení s `-Force`** proběhlo s exit 0.
  - Stále to byl první běh, protože nepovedený běh manifest nezapsal. Drift
    proto obsahoval jen dva soubory změněné opravou.
  - `Verification passed.` pro `.claude\skills` i `.agents\skills`.
  - `pre-push` nainstalovaný a ověřený naživo. Seznam chráněných větví je
    v `.git/ums-protected-branches`.
  - Manifesty zapsané do `.git/ums-sync-manifest-claude-Fork.json`
    a `.git/ums-sync-manifest-codex-Fork.json`.
  - `.git/info/exclude` nedostal nový řádek: `/.agents/skills/` tam už byl
    právě jednou.
  - `git status --porcelain` zůstal prázdný.
- **Stav nasazení:**
  - V `.claude/skills` i `.agents/skills` je po 38 adresářích: 20 `mb-*`,
    `shared`, 14 vendorovaných skillů v6.4.2 a 3 cizí pozůstatky ručního
    nasazení (Kroky pro uživatele).
  - `diagnosing-superpowers` chybí.
  - V každém z pěti overlayovaných skillů jsou právě 2 bloky
    `UMS-OVERLAY BEGIN` (ukazatel a tělo).
  - `.claude/settings.json` je bajtově shodný se zdrojem.

### Ověřovací sada

Tři příkazy deklarované plánem, spuštěné doslova na HEAD aed57a4:

| Příkaz | Výsledek |
|---|---|
| smyčka `for t in $(find ums -name "*.tests.ps1"); …` (Git Bash) | 202 sad, konec `LOOP-DONE exit=0`. `FAILED:` jen u dvou známých selhání prostředí z baseline: `ums/.claude/hooks/tests/contract-inject.tests.ps1` 1/56 (drift warning is the first line of the payload — code page při spuštění pwsh z Git Bash; z PowerShellu sada prochází) a `ums/.claude/skills/mb-epic-run/tests/pool-launch.tests.ps1` 2/41 (Gate 3, skutečné spuštění procesu). Žádné nové selhání. |
| `pwsh -NoProfile -File ums/.claude/scripts/revendor-superpowers.ps1 -VerifyOnly -UmsRoot .` | exit 0, všech šest kontrol, `Verification passed.` |
| `pwsh -NoProfile -File ums/sync-with-monorepo.ps1 -Scope Fork -Agent claude,codex -WhatIf` | exit 0, bez driftu (manifesty existují) |

### Opravy návrhu (rozhodnutí controlleru)

- **Sekce 2.7 a riziko „Směr ořezu 5 000 tokenů po kompaktaci není
  zdokumentovaný":** dokumentace Claude Code (context window) směr uvádí —
  „Truncation keeps the start of the file". Přežije tedy polovina
  s hlavičkovým ukazatelem. Mechanismus zůstává beze změny (doklad
  [compaction.md](../../../ums/.claude/skills/shared/contract/doklad/compaction.md)).
- **Kolizní příklad v sekci 2.6** (slug znovu rozjetý po `mb-abort` vede na
  `plan_<slug>-<rodič>/`) je chybný.
  - Upstream `sdd-workspace` přiřazuje workspace podle uloženého
    `plan-path`. Znovu rozjetý slug na téže aktivní cestě proto starý
    workspace i ledger ZNOVU POUŽIJE.
  - Hledání ledgeru podle `plan-path` opravuje jinou kolizi: stejný
    basename ve dvou Memory Bank.
  - Zastaralý workspace po abortu je následná práce (`mb-abort` plan
    workspace nemaže).
  - Pod Git Bash na Windows zapisuje upstream do `plan-path` ABSOLUTNÍ msys
    cestu; `contract-inject` ji přijímá (Task 9).

### Cold-reader průchod nasazených skillů

Otázka zní: vede vygenerovaný text čtenáře bez kontextu ke správným krokům
UMS? Metoda exekuce existuje jen tam, kde je plán (architektonická cesta).
Bounded a spike plán nepíšou, proto metodu nemají.

| Cesta | Metoda | Pokračování | Verdikt | Doklad |
|---|---|---|---|---|
| architektonická | SDD | čerstvé sezení s batonem | ano | `writing-plans/SKILL.md:220–248`: baton `Kind: plan-execution`, `Instruction:` = `subagent-driven-development`, stop česky. `.claude/hooks/session-intent.ps1:176–205` ověří `Instruction` proti adresářům nasazení, `:321–325` pustí nejdřív bootstrap. Overlay SDD: base sync a baseline před prvním taskem `subagent-driven-development/SKILL.md:642–646`, řetězec playbooků k dispatchi `:625–634`, NOW `:612–613`, explicitní model `:586–589`. |
| architektonická | SDD | rotace kontextu (baton `plan-resume`) | ano | `subagent-driven-development/SKILL.md:594–600`. Base sync ani baseline se neopakují (`shared/contract/session-intent-baton.md:146–150`). |
| architektonická | SDD | kompaktace | ano | Ukazatel `subagent-driven-development/SKILL.md:6–12` začíná na znaku 147; tělo overlaye až na znaku 32 806, tedy za oknem 5 000 tokenů. Nese ho zachovaný začátek. `.claude/hooks/contract-inject.ps1:14` přikazuje přečíst blok UMS-OVERLAY, `:88–135` najde ledger s blokem NOW podle `plan-path`. |
| architektonická | Native | čerstvé sezení s batonem | ano | `writing-plans/SKILL.md:241–242` (`Instruction:` = `executing-plans`). Overlay: base sync `executing-plans/SKILL.md:445–449`, řetězec playbooků čte exekutor sám v každém sezení `:411–423`, NOW `:409–410`, izolace místo worktree `:438–444`, finální review s explicitním modelem a efektivní bází `:430–434`. |
| architektonická | Native | rotace kontextu (baton `plan-resume`) | ano | Pátá stop třída `executing-plans/SKILL.md:392–399` zužuje upstream `:47` („Four things stop you, and only these"). |
| architektonická | Native | kompaktace | ano | Ukazatel `executing-plans/SKILL.md:6–12` začíná na znaku 220, tělo na znaku 20 697. Playbook se znovu čte i po kompaktaci (`:418`). Ledger podle upstream `:139–145`. |
| bounded | — | čerstvé sezení | **mezera (pojmenovaná)** | Baton nemá druh pro bounded: vyžaduje `Plan` (`.claude/hooks/session-intent.ps1:34`, `:209`) a zapisují ho jen `writing-plans` a exekutoři plánu (`shared/contract/session-intent-baton.md:74–79`). Pokračování nese pin v `context.md`, který `contract-inject` vykreslí, a záměr, který operátor napíše sám. Nic se neztratí, ale nic se ani nedoručí automaticky. |
| bounded | — | kompaktace | **mezera (menší)** | Ukazatele `brainstorming/SKILL.md:6–12` a `finishing-a-development-branch/SKILL.md:6–12` platí, dokud dané skilly běží. Implementace mezi nimi jde „normálním workflow" (`brainstorming/SKILL.md:177`, `:194–196`) bez overlayovaného skillu; `contract-inject` vrátí jádro a pin. Hranice fází v jádře (`shared/UMS_MEMORY_BANK_CONTRACT.md:154–160`) ale před implementací bounded práce žádnou nemají. Base sync a baseline před prvním commitem tak text nikde nepožaduje (u SDD i Native ano). Integraci jistí fáze Sync ve finishing (`finishing-a-development-branch/SKILL.md:150–153`). |
| spike | — | čerstvé sezení / kompaktace | ano | Nepinuje a nezapisuje do `proposals/` (`brainstorming/SKILL.md:306–312`, `:324–329`). Terminální stav je doporučení bez finishing (`:564`). Po kompaktaci platí ukazatel `:6–12`; čerstvé sezení nemá co nést. |
| všechny integrující | finishing | kompaktace | ano | Ukazatel `finishing-a-development-branch/SKILL.md:6–12` výslovně počítá s ořezem UVNITŘ dlouhého bloku (`:92–553`). Kontrola záruky publikace je první `:97–111`, harvest `:112–127`. Bounded bez plánu je očekávaný tvar (`:124–127`). |

**Verdikt:** architektonická cesta vede ke správným krokům UMS pro obě metody
(SDD i Native) a pro všechny tři druhy pokračování; spike také. Bounded má
dvě pojmenované mezery: chybí baton pro čerstvé sezení a před implementací
není předepsaný base sync ani baseline. Obě jsou starší než tento upgrade
a patří do následné práce, ne do této položky.

### Tabulka uzavření rozporů (přepočtená proti nasazení)

Výchozí je tabulka z Task 8, která vznikla nad dočasnou generací. Řádky jsou
přepočtené proti nasazenému `.claude/skills`. „Upstream" znamená pristine
v6.4.2; ve vygenerovaném souboru je každý overlayovaný `SKILL.md` posunutý
o 8 řádků hlavičkovým ukazatelem.

| # | Řádek návrhu | Upstream v6.4.2 → nasazeno | Věta vrstvy v nasazení | Stav |
|---|---|---|---|---|
| 1 | `writing-plans`: menu Subagent-driven / Native | `:189` → `writing-plans/SKILL.md:197` („…Which execution approach would you prefer?**"); položky `:199`, `:200`; „When an execution method has already been supplied" `:271`; druhé „Plan complete…" `:273` | blok `:204–269` (ASSERTy `:197`, `:199`, `:200`): `## Ověřovací sada` `:205–210`, přepis cesty plánu (neguje obě věty `:197` a `:273`) `:212–218`, Fresh Session jako modifikátor obou metod `:220–234`, baton `:236–242`, český stop `:243–248`, pokračování v tomto sezení `:250–251` | uzavřeno |
| 2 | `executing-plans` jako Native exekuce | „Four things stop you…" `:39` → `executing-plans/SKILL.md:47`; worktree `:111` → `:118–119`; sdílený ledger `:121` → `:129–131`; `git merge-base main HEAD` `:238` → `:246` | blok `:383–458`: pátá stop třída `:392–399`, rulingy `:400–403`, autorita Spec `:404–408`, NOW `:409–410`, playbook `:411–423`, kandidáti `:424–429`, finální review `:430–434`, jazyk `:435–437`, izolace `:438–444`, base sync `:445–449`, publikace `:450–455`, konec `:456–457`; ukazatel `:6–12` | uzavřeno |
| 3 | smazaný `plan-document-reviewer-prompt.md` | v6.4.2 ho nemá | `writing-plans/` v nasazení nese jen `SKILL.md`; požadované soubory revendoru přidávají `executing-plans\scripts\task-start` / `task-done` (`.claude/scripts/revendor-superpowers.ps1:404–405`); test `ums/.claude/scripts/tests/revendor.tests.ps1:230`, `:234` | uzavřeno |
| 4 | nový `diagnosing-superpowers` | adresář v6.4.2 existuje | `shared/VENDORED_FROM.md:22–23` („- Excluded:" / „diagnosing-superpowers"); adresář chybí v `.claude/skills` i `.agents/skills`; pin nese 14 skillů | uzavřeno |
| 5 | brainstorming: Establish Shared Understanding, HARD-GATE | HARD-GATE `:49` → `brainstorming/SKILL.md:57`; „Carry intent into the design" `:29` → `:37` | dodatek k HARD-GATE `:524–533` (oponentura a Architect Review Gate mezi schválením spec a writing-plans; ani jedno není implementační úkon); věta do `## Cíl` `:469–474`; doplnění terminálních stavů `:557–564` | uzavřeno |
| 6 | `MERGE_BASE` např. `git merge-base main HEAD` | `subagent-driven-development/SKILL.md:457`; `executing-plans/SKILL.md:246`; `requesting-code-review/SKILL.md:28` („# or: git merge-base origin/main HEAD", mimo overlay, viz řádek 8) | `subagent-driven-development/SKILL.md:647–649` a `executing-plans/SKILL.md:430–434` → efektivní báze | uzavřeno |
| 7 | upstream smazal kořenový `CLAUDE.md` | v6.4.2 soubor nemá | mimo vendorovaný strom: `CLAUDE.md:1` forku `@AGENTS.md`, `:3` blok UMS-MEMORY-BANK | uzavřeno (mimo vygenerovaný strom) |
| 8 | TDD celá sada; review „Declined to judge"; SDD marker `plan-path`; skripty přes interpret | `test-driven-development/SKILL.md:185`; `requesting-code-review/code-reviewer.md:43`; `subagent-driven-development/scripts/sdd-workspace:13`, `:62–66` | bez overlaye (návrh: bez zásahu). Ledger podle markeru: `.claude/hooks/contract-inject.ps1:88–135`, domov popsaný v `shared/contract/now-block.md:19–33` | **uzavřeno — Task 9 (351888e, f45d75d)**; v Task 8 byla změna hooku ještě otevřená |
| C | kompaktace zachová ZAČÁTEK skillu (≤ 5 000 tokenů) | — (dokumentace: „Truncation keeps the start of the file") | ukazatel `:6–12` v pěti skillech. První `UMS-OVERLAY BEGIN` je na znaku 248 (brainstorming), 220 (executing-plans), 166 (finishing), 147 (SDD) a 132 (writing-plans), všude pod limitem 12 000 z verifikace revendoru. Pokyn po kompaktaci je v `.claude/hooks/contract-inject.ps1:14`. | uzavřeno |

**Grep sweepy nad nasazením:**

- Vzor `Inline Execution|Two execution options|Which approach?` (rozlišuje
  velikost písmen) nad `*/SKILL.md` má **0 zásahů**.
- Bez rozlišení velikosti padají zásahy jen do upstream řádků mimo bloky:
  `executing-plans/SKILL.md:3`, `:22`, `:36`, `:56`, `:63`, `:70` (bloky
  `:6–12`, `:383–458`) a `writing-plans/SKILL.md:202` (bloky `:6–12`,
  `:204–269`).
- Ve skillech a hoocích nasazení (bez testů, CHANGELOG a dokladů) se
  `four overlays`, `přesně 4`, `plan-document-reviewer` ani `kilocode`
  nevyskytují.
- `v6.3.0` zbývá jen jako „(v6.3.0+)" v `shared/UMS_MEMORY_BANK_CONTRACT.md:726`.
  To je zobecnění podle sekce 2.8, ne pozůstatek.

## Kroky pro uživatele

Připravené příkazy. Agent je nespouští, protože jde o chráněné větve nebo
monorepo. Kroky 2 až 5 se týkají monorepa `D:\_datasys\ums`.

1. **Fast-forward zrcadla `main`.** Chráněná větev, `origin/main` je 55
   commitů za `vanila/main` (tip `8ca22db`, v6.4.2):
   `! git push origin vanila/main:main`
2. **Cílová větev monorepa je na tobě.** Monorepo teď stojí na tiketové
   větvi `UMS-2890-pipeline-prichozich-udalosti`. Před prvním nasazením
   přepni na větev, kam má vrstva jít.
3. **První nasazení do monorepa.** Nejdřív nanečisto:
   `pwsh ums/sync-with-monorepo.ps1 -Agent claude -Scope Monorepo -WhatIf`
   - Čekej **exit 3**: bez manifestu je drift každý rozdíl. Projdi seznam
     driftu a teprve pak rozhodni o `-Force`.
   - STOP při prvním běhu nabízí `-Direction FromMonorepo`. **Tuto nabídku
     pro tento upgrade nepřijímej.** Bez manifestu je směr neznámý
     a přepsal by novější UMS položky forku (např. overlaye pro v6.4.2)
     staršími z monorepa.
4. **Dvoufázové nasazení při změně tagu (v6.3.0 → v6.4.2).**
   - Běh s `-Force`, který skončí **exit 4**, zapsal JEN vanilla revendor.
     Commitni ho v monorepu jako „vanilla sync".
   - Druhý běh se na týchž nevendorovaných souborech zastaví znovu
     a potřebuje `-Force` znovu. Hlášení prvního běhu tvrdí, že byly
     přepsané, ale to ještě neplatí.
   - Po druhém běhu commitni „overlay".
5. **Při prvním nasazení se migruje `CLAUDE.md` monorepa** na blok mezi
   markery. Sekce patřící vrstvě se nahradí na místě; projektové sekce
   (např. „WF engine") zůstanou nedotčené. Zkontroluj diff před commitem
   „overlay".
6. **V cílech UMS neinstaluj superpowers zároveň jako plugin.** Skilly by
   byly dvakrát, jednou bez overlaye.
7. **Cizí adresáře v kořeni forku jsou na tvém rozhodnutí.** V `.claude/skills`
   i `.agents/skills` zůstaly z dřívějšího ručního nasazení `vs-mcp-debugging`,
   `wf-bpmn-authoring` a `wf-element-dev`. Nejsou v pinu a sync je nevlastní
   (nemaže je). Chceš-li je odstranit:
   ```powershell
   Remove-Item -Recurse -Force .claude/skills/vs-mcp-debugging, .claude/skills/wf-bpmn-authoring, .claude/skills/wf-element-dev, .agents/skills/vs-mcp-debugging, .agents/skills/wf-bpmn-authoring, .agents/skills/wf-element-dev
   ```