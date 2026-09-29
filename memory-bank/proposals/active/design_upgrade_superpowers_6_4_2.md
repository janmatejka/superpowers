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
| nový skill `diagnosing-superpowers` | seznam 14 skillů natvrdo v revendoru | dynamický seznam = celý upstream, 15 skillů (sekce 1.2) |
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
  uživatel); přidání `epicBranchPattern` do `ums-repo.json` monorepa (změna
  konfigurace ochrany je dno kontraktu).
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
`skills/` pinovaného tagu** (v6.4.2: 15, nově `diagnosing-superpowers`).
Skill, který upstream mezi piny zruší, z cíle smaže — podle řádků `Skills:`
předchozího `VENDORED_FROM.md` v cíli. Fragment mířící na neexistující cíl
zůstává hard error.

#### 1.3 Revendor skript

- **Verifikace:** vypustit požadavek na `writing-plans/plan-document-reviewer-prompt.md`;
  přidat `executing-plans/scripts/task-start` a `task-done` (bash bez
  přípony — pokryje je i CRLF kontrola). Funkční test `sdd-workspace` zůstává
  (marker `plan-path` v6.4.2 adresář při prvním použití nemění).
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
reviewer má explicitní model.

#### 2.4 Overlay `writing-plans`

Nová kotva `ANCHOR-BEFORE: **When an execution method has already been supplied:**`,
ASSERTy na obě položky upstream menu (Subagent-driven, Native) a na řádek
„Plan complete and saved to …". Obsah:

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
- `contract-inject.ps1` čte ledger z `.superpowers/sdd/plan_<slug>/progress.md`.
  Sufix, kterým v6.4.2 řeší kolizi basename, u nás nenastane (`plan_<slug>.md`
  je unikátní) — zapsáno jako předpoklad v `now-block.md`.

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
o hlavičkovém ukazateli. Jádro má 798 řádků z rozpočtu 800 — přírůstky se
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
`git rev-parse --git-common-dir` cíle (netrackovaný, platný pro celý klon);
cíl bez gitu ho má v config adresáři. Před zápisem se porovnají tři stavy —
cíl, manifest, fork:

- soubor změněný v cíli od posledního nasazení, jehož změnu fork nemá →
  STOP se seznamem souborů a nabídkou `-Direction FromMonorepo` nebo
  `-Force`;
- bez manifestu (první běh) → STOP na každý rozdíl;
- adresář `mb-*` jen v cíli → varování.

Manifest pokrývá i vendorované skilly — ruční úprava v cíli se chytí.
Přepínač `-WhatIf` vypíše, co by zapsal, a ohlásí drift, nic nezmění.

#### 3.3 Vendorované skilly

Pro každý cíl s adresářem skillů: nejdřív se zrcadlí `shared/`, pak se volá
revendor forku s `-SkillsRoot <cíl>` — tag z `VENDORED_FROM.md`, overlaye ze
právě nasazeného `shared/overlays/`, takže past „revendor čte zastaralou
kopii fragmentů" odpadá. **Změna tagu u cíle trackovaného gitem**
(monorepo): běh provede jen vanilla fázi a skončí s pokynem commitnout
„vanilla sync" a spustit ho znovu; druhý běh doplní overlaye — pravidlo dvou
revendorových commitů platí dál. Stejný tag nebo netrackovaný cíl: jeden
průchod.

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
forku je ruční a `AGENTS.md` je upstream soubor. Tím odpadá ruční obnova
nasazení, kterou dnes popisuje asi osm pravidel a pastí playbooku.

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
- **Kdy:** na nejbližší hranici tahu příjemce; sezení čekající na subagenta
  odpoví po jeho návratu (zákaz šťouchání do takového sezení platí dál).
- **Artefakt čekání:** tiketová strana — blok NOW se stavem
  `waiting-for-manager` a `Due`; správce — git-ignorovaný outbox
  `.superpowers/epic/<KLÍČ>/outbox.md` (komu, kdy, `Due`), který
  `mb-epic-run status` vykreslí jako nezodpovězené a opožděné zprávy.
- **Po `Due`:** jedno zopakování, pak eskalace člověku — žádné nekonečné
  čekání ani tichý pád.
- Domov: jádro (sekce Message Protocol), `message-protocol.md`, `mb-epic-run`
  (spawn, status, integrate), overlay finishing (fáze Handoff).

#### 4.2 Nechráněná linie epiku

- **Konfigurace:** linie `epic/<KLÍČ>` se vyřazuje z chráněných větví.
  `epicBranchPattern` (výchozí `epic/*`) dostává novou roli —
  **identifikuje linii epiku jako legitimní nechráněnou bázi**. Invariant
  „integrační větev je vždy chráněná"
  (kontrakt/repository-configuration.md, „Repository Configuration")
  dostane jedinou jmenovitou výjimku pro linii
  odpovídající vzoru; chybějící nebo prázdný vzor = žádná výjimka, STOP pro
  nechráněnou bázi platí dál. Stav monorepa (2026-09-29): linie
  `origin/epic/SKODASMS-237` a `origin/epic/UMS-3557` existují, nejsou
  chráněné a `epicBranchPattern` chybí — dnešní kontrakt by je jako bázi
  zastavil; návrh ho uvádí do souladu s praxí.
- **Založení:** `mb-epic-run spawn` při prvním rozjetí tiketu epiku, když
  `origin/epic/<KLÍČ>` neexistuje, ji založí z dodávkové linie
  (`git push origin <sha dodávkové linie>:refs/heads/epic/<KLÍČ>`) a zapíše
  dodávkovou linii do hlavičky ledgeru epiku
  (`- **Dodávková linie:** origin/develop`). Tiketové větve epiku mají
  `Báze: origin/epic/<KLÍČ>`; `Get-UmsBaseCandidates` nabízí linie epiku
  mezi kandidáty.
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
- **Úklid:** výjimka se čtyřmi podmínkami v `guard-git-push.mjs` a její
  testy se ruší (mrtvý kód); `epic-line.md` a jeho doklad se přepíšou;
  `Get-UmsRepoConfig` mění význam klíče.

### 5. Dokumenty

`SKILLS_MANIFEST.md`, `ums/README.md` (verze, 15 skillů, 5 overlayů, matice
harnessů, pokyn o pluginu), `shared/CHANGELOG.md` (3.2), sekce forku
v `CLAUDE.md` (fork je master, výchozí `ToMonorepo`, `-Scope Fork`, pět
overlayů), `CLAUDE.md.sample` (bez sekce WF engine; odrážka „Exekuce plánu
(SDD)" → SDD i Native). Memory Bank (`brief.md`, `architecture.md`,
`tech.md`, `playbook.md`) aktualizuje harvest — včetně pravidel playbooku,
která nový sync zneplatní („Pořadí FromMonorepo → ToMonorepo je pevné",
ruční obnova nasazení, „sync vendorované skilly nesynchronizuje nikdy").

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
  `CLAUDE.md` ani `AGENTS.md`, cíle harnessů, odmítnutý kilocode);
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
| Nechráněná linie epiku: agent do ní pushne, co správce neviděl | push jen po go s ověřeným tipem; hook pustí jen fast-forward; výstup do dodávkové linie je lidský |
| Jádro kontraktu přeroste 800 řádků | přírůstky vyvážit zhuštěním; hlídá `contract-shape` |
| Plán přesáhne kontext jednoho sezení | pátá stop třída (rotace) a Fresh Session; hranice fází jako místa rotace |
| Duplicitní skilly při současně nainstalovaném pluginu | pokyn v `ums/README.md` |
| Nasazení do forku uprostřed exekuce změní skilly pod běžícím sezením | nasazovat jen na hranici fáze |
