# Tech

Ecosystem: dokumentační a skriptový — Markdown (skilly a kontrakt), PowerShell 7
(nástroje vrstvy), Node.js ESM (hooky), Bash (upstream skripty SDD). Žádný
kompilovaný build, žádný package manager pro vrstvu samotnou.

## Verze a piny

| Co | Hodnota | Zdroj |
|---|---|---|
| Superpowers (upstream) | 6.3.0 | [`package.json`](../package.json), [`.claude-plugin/plugin.json`](../.claude-plugin/plugin.json) |
| Vendor pin vrstvy | tag `v6.3.0`, commit `b36e0829c6d0140e93cfef2ca599b1b07d4a7797`, vendorováno 2026-08-13 | [`VENDORED_FROM.md`](../ums/.claude/skills/shared/VENDORED_FROM.md) |
| Kontrakt Memory Bank | 2.11 | [`UMS_MEMORY_BANK_CONTRACT.md`](../ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md) |
| Vendorované skilly | 14 (`brainstorming`, `dispatching-parallel-agents`, `executing-plans`, `finishing-a-development-branch`, `receiving-code-review`, `requesting-code-review`, `subagent-driven-development`, `systematic-debugging`, `test-driven-development`, `using-git-worktrees`, `using-superpowers`, `verification-before-completion`, `writing-plans`, `writing-skills`) | `VENDORED_FROM.md` |
| Overlay bloky | přesně 3 (`brainstorming`, `subagent-driven-development`, `finishing-a-development-branch`) | [`shared/overlays/`](../ums/.claude/skills/shared/overlays/) |

## Konfigurace repozitáře (`ums-repo.json`)

[`ums-repo.json`](ums-repo.json) v `CTX_DIR` nese repozitářově specifické
hodnoty, které kontrakt zakazuje mít v tělech skillů nebo skriptů (kontrakt,
Repository Configuration). Tento repozitář:

| Klíč | Hodnota |
|---|---|
| `baseRef` | `origin/ums-memory-bank` |
| `protectedBranches` | `ums-memory-bank`, `main`, `master`, `develop`, `release/*`, `Branches/*` |
| `ticketPattern` | `^UMS-[0-9]+` |
| `projectMarkers` | `package.json` |
| `sharedRoots` | `ums/.claude/skills/shared/`, `ums/.gitattributes` |

Loader [`Get-UmsRepoConfig.ps1`](../ums/.claude/skills/shared/scripts/Get-UmsRepoConfig.ps1)
nikdy nevyhazuje výjimku: chybějící nebo poškozený soubor degraduje po
jednotlivých klíčích k vestavěným defaultům (`origin/develop` jako báze,
vestavěná čtveřice chráněných větví, obecný vzor tiketu, prázdné
`projectMarkers`/`sharedRoots`) — vždy k bezpečnější straně, nikdy k méně
ochraně. Bare string u kterékoli seznamové hodnoty se normalizuje na
jednoprvkový seznam stejně jako v `guard-git-push.mjs`, takže obě vynucovací
vrstvy (generovaný seznam pro `pre-push` a `guard-git-push.mjs`) dají na
stejnou konfiguraci vždy stejnou odpověď.

## Runtime a platforma

- **PowerShell 7** (`#Requires -Version 7`, `$ErrorActionPreference = 'Stop'`) —
  [`sync-with-monorepo.ps1`](../ums/sync-with-monorepo.ps1),
  [`revendor-superpowers.ps1`](../ums/.claude/scripts/revendor-superpowers.ps1),
  [`epic-graph.ps1`](../ums/.claude/skills/mb-epic-graph/scripts/epic-graph.ps1),
  [`ledger-status.ps1`](../ums/.claude/skills/mb-epic-elaboration/scripts/ledger-status.ps1),
  [`doc-index.ps1`](../ums/.claude/skills/mb-doc-index/scripts/doc-index.ps1),
  [`install-git-hooks.ps1`](../ums/.claude/hooks/install-git-hooks.ps1),
  [`Get-UmsRepoConfig.ps1`](../ums/.claude/skills/shared/scripts/Get-UmsRepoConfig.ps1),
  [`Test-UmsProtectedBranch.ps1`](../ums/.claude/skills/shared/scripts/Test-UmsProtectedBranch.ps1),
  [`Get-UmsBaseCandidates.ps1`](../ums/.claude/skills/shared/scripts/Get-UmsBaseCandidates.ps1),
  [`Get-UmsEffectiveBase.ps1`](../ums/.claude/skills/shared/scripts/Get-UmsEffectiveBase.ps1),
  hook `bpmn-validate.ps1`.
- **Node.js** (ESM, `"type": "module"`) — hooks
  [`deny-superpowers-docs.mjs`](../ums/.claude/hooks/deny-superpowers-docs.mjs)
  (čte JSON ze stdin, vrací `permissionDecision: deny`) a
  [`guard-git-push.mjs`](../ums/.claude/hooks/guard-git-push.mjs) (pravidlo
  podle aktéra nad `Bash`/`PowerShell` voláními, viz níže).
- **Git Bash / POSIX sh** — upstream skripty SDD (`sdd-workspace`, `task-brief`,
  `review-package`) jsou bashové soubory bez přípony; totéž platí pro
  [`ums/.claude/hooks/pre-push`](../ums/.claude/hooks/pre-push) (`#!/bin/sh`),
  git hook bez přípony, který git spouští přímo (ne přes PowerShell).
- Vývojová platforma je Windows; primární shell PowerShell, Git Bash dostupný.

## Externí závislosti

Vrstva je bezzávislostní vůči knihovnám. Jediné externí rozhraní je **Atlassian
MCP** (Jira) — vyžadují ho `mb-jira-update`, `mb-architect-review`,
`mb-epic-graph` (režim Jira) a `mb-epic-elaboration`. Bez něj mají skilly
JIRA-less režim nebo se zastaví (fail-closed).

Jira konvence, na které se vrstva spoléhá:

- stavy `Design Review`, `In Progress`, `Test`; chybějící přechod do
  `Design Review` není stop — request spadne na existující stav `Review`
  a rozliší ho marker `[DESIGN REVIEW]` na první řádce request komentáře
  (kontrakt, Architect Review Gate, „Design Review" fallback); fail-closed
  stop nastává až bez přechodu do `Review`,
- pole `Flagged` s hodnotou Impediment jako signál „práce se ti vrací",
- `customfield_11248` (AgentSessions, Paragraph) — append jednoho řádku
  o sezení při design review requestu.

Instance je Jira Cloud `datasyscz.atlassian.net`; příklad schématu `context.md`
v kontraktu ještě uvádí starší host `jira.datasys.cz`.

## Konfigurace pro Claude Code

[`ums/.claude/settings.json`](../ums/.claude/settings.json) je registrační
lepidlo Claude Code (pravidla jeho nasazení jsou v
[playbook.md](playbook.md)):

| Klíč | Obsah |
|---|---|
| `env` | `MB_AGENT_SESSION: "1"` — vstupní marker agentní relace; bez něj `pre-push` hook nevynucuje nic vlastního (viz níže) |
| `hooks.SessionStart` | `additionalContext`: vyvolat `using-superpowers`, pak přečíst kontrakt a `memory-bank/context.md`; entry gate stejného kroku navíc fail-closed ověří verzi `pre-push` hooku (`UMS pre-push guard (Publication Contract) v2`) a spustí synteticky obě poloviny jeho self-checku (zamítnutí i propuštění) — postup je v [playbook.md](playbook.md) |
| `hooks.PostCompact` | `systemMessage`: po kompaktaci znovu načíst kontrakt, `context.md` a při exekuci plánu i `.superpowers/sdd/<plan-basename>/progress.md` |
| `hooks.PreToolUse` (`Write|Edit`) | `deny-superpowers-docs.mjs` — blokuje zápis do `docs/superpowers/**` a `docs/plans/**` |
| `hooks.PreToolUse` (`Bash|PowerShell`) | `guard-git-push.mjs` — nese pravidlo podle AKTÉRA (jen vlastní tool-cally agenta, ne příkazy uživatele psané přes `!`): na rozpoznaný `git push` leans fail-CLOSED (nečitelný cíl zamítá, nečeká na vyjasnění), zamítá push agenta na chráněnou větev včetně integračního fast-forwardu, obě jména únikové proměnné v POSIX i PowerShellovém zápisu a `--no-verify` bez kontextu; NENÍ záruka publikace — tou zůstává git `pre-push` hook (níže), který navíc vynucuje jen uvnitř agentní relace |
| `hooks.PostToolUse` (`Write|Edit`) | `bpmn-validate.ps1` — validace BPMN v monorepu |
| `permissions.allow` | read-only nástroje (grep, rg, cat, head, tail, ls, wc, diff, sed, find, test, echo; git status/diff/log/show/ls-files/rev-parse/branch/check-ignore/stash list/fetch/ls-remote/for-each-ref/ls-tree/cat-file/merge-base; PowerShell Get-Content/Get-ChildItem/Test-Path/Select-String) |
| `permissions.deny` | `EnterWorktree`, `ExitWorktree`, `Bash(rm -rf:*)`, `Bash(git reset --hard:*)` |
| `skillOverrides` | `using-git-worktrees: off` |
| `worktree.bgIsolation` | `none` |

`git push` už není v `permissions.deny` — je binární a deny vyhrává nad allow,
takže by nešlo rozvolnit jen pro vlastní tiketovou větev. Skutečnou hranicí
publikačního pravidla (kontrakt, Publication Contract) je git `pre-push` hook
(`v2`) [`ums/.claude/hooks/pre-push`](../ums/.claude/hooks/pre-push) (POSIX
`sh`, scope `refs/heads/*`) — git mu předá už rozparsované čtveřice refů, ne
shellový text, takže žádné parsování k obejití neexistuje. Vynucuje jen
uvnitř agentní relace: vstupní brána je marker `MB_AGENT_SESSION=1` (u
Claude Code fallback na neprázdný `AI_AGENT` nebo `CLAUDECODE=1`, viz níže
tabulka doručení markeru per harness); mimo relaci hook nic vlastního
nevynucuje a jen deleguje na zřetězený cizí hook. Nad touto branou stojí
jedno rameno platné pro každého bez ohledu na marker: neúspěch bufferovat
gitem předaný seznam refů do dočasného souboru zamítne push úplně, tagy
nevyjímaje.

Uvnitř agentní relace na chráněné větvi hook pustí jen **fast-forward, jehož
tip je už dosažitelný z remote-tracking refů tohoto klonu** pro pushovaný
remote (`is_integration_push`) — lokální, zapisovatelný stav, který
`git update-ref` splní i bez skutečné publikace; hook nikdy nekontaktuje
`origin`. Mazání větve a force push zamítá vždy, s výjimkou
`MB_HUMAN_PUSH=1` (přechodně přijímané i pod starším jménem
`UMS_ALLOW_SHARED_PUSH=1`, s hláškou o zastaralosti) — ta zvedá celou
ochranu hooku najednou, ne jen pravidlo o chráněné větvi. Detailní rozpad
je v [architecture.md](architecture.md), sekce Publikace a viditelnost
napříč větvemi.

Chráněné patterny jsou konfigurace, ne tělo hooku: [`ums-repo.json`](ums-repo.json)
klíčem `protectedBranches` (tento repozitář: `ums-memory-bank`, `main`,
`master`, `develop`, `release/*`, `Branches/*`). `pre-push` je POSIX `sh` bez
JSON parseru, takže je nečte přímo —
[`install-git-hooks.ps1`](../ums/.claude/hooks/install-git-hooks.ps1) je při
instalaci materializuje přes loader
[`Get-UmsRepoConfig.ps1`](../ums/.claude/skills/shared/scripts/Get-UmsRepoConfig.ps1)
do `<git-common-dir>/ums-protected-branches`, jeden glob na řádek, a hook čte
jen tento vygenerovaný soubor. **Změna konfigurace se tedy projeví až po
dalším běhu instalátoru.** Bez konfigurace, bez `ums-repo.json` nebo s
nedostupným loaderem hook spadá na vestavěnou čtveřici `develop`, `main`,
`master`, `release/*` — vždy k víc ochraně, nikdy k méně.

Cizí `pre-push`, který instalace v cíli najde, se nevyřazuje z provozu:
instalátor ho přesune na `<jméno>.ums-chained`, nastaví mu spustitelnost a
hook mu po sobě přehraje bufferovaný stdin (`run_chained`), i ve větvi, kdy
sám zamítá — nenulový exit zřetězeného hooku je jeho veto a hook ho
propaguje. Instalace chaining odmítne (a hook se do klonu vůbec
nenainstaluje, exit kód **2**) ve čtyřech případech: sdílený adresář
`core.hooksPath`, `.ums-chained` už existuje, ručně sloučený hook nesoucí náš
marker hluboko v těle místo v hlavičce, nebo selhání samotného přesunu.

Git hooky jsou netrackované (`.git/hooks/` nebo cíl `core.hooksPath`), takže
je do každého klonu instaluje samostatný skript
[`install-git-hooks.ps1`](../ums/.claude/hooks/install-git-hooks.ps1) —
idempotentní, cizí hook zřetězí (viz výše, exit kód 2), cíl řeší
`git rev-parse --git-path hooks/pre-push` (správně i pro linked worktree).
Instalátor vrací exit kód **4**, když se seznam chráněných větví nepodařilo
obnovit — nešlo ho zapsat, nebo chybí loader `Get-UmsRepoConfig.ps1` vedle
adresáře s hooky — hook se i tak instaluje a vynucuje, co je aktuálně na
disku (starší běh, nebo vestavěný fallback), nikdy neskončí bez hooku (na
rozdíl od exit kódu 2, kde se v klonu vůbec nenainstaluje). Kdy se spouští a
co znamenají ostatní návratové kódy, je v [playbook.md](playbook.md). Konce
řádků hooku hlídá [`ums/.gitattributes`](../ums/.gitattributes) pravidlem
`text eol=lf`.

**Doručení markeru `MB_AGENT_SESSION` mimo Claude Code** dělá
[`sync-with-monorepo.ps1`](../ums/sync-with-monorepo.ps1) do dokumentovaného
mechanismu každého harnessu:

| Harness | Mechanismus |
|---|---|
| Claude Code | `env` blok [`ums/.claude/settings.json`](../ums/.claude/settings.json) — `-Scope UserProfile` tento soubor záměrně nenasazuje, takže tam zůstává jen fallback `CLAUDECODE=1`/neprázdný `AI_AGENT` |
| Codex | `config.toml`, `[shell_environment_policy].set` (merguje se do existující tabulky) |
| Gemini | `.env` soubor v `.gemini/` |
| Kilo Code | žádný zdokumentovaný mechanismus nalezen — skript vyhodí `NotSupportedException`, vypíše varování a nic nezapíše; na tomto harnessu marker nikdy nedorazí a `pre-push` hook tam nevynucuje nic vlastního |

Tvrzení „git hook je harness-agnostický" proto platí jen pro samotné
spuštění hooku (je to prostý git mechanismus, ne funkce Claude Code) — jeho
vynucovací branu ale otevírá marker, a ten se ke Kilo Code nedostane.

## Testy

Jak se sady spouštějí a jaké konvence platí pro novou sadu, je
v [playbook.md](playbook.md).

**UMS vrstva** — bezzávislostní PowerShell testy vedle skillů, 17 sad, dohromady
954 asercí:

- [`mb-epic-graph/tests/`](../ums/.claude/skills/mb-epic-graph/tests/) —
  `e2e.tests.ps1` (12), `graph-generation.tests.ps1` (27),
  `oracle-prose.tests.ps1` (5), `oracle-structural.tests.ps1` (10),
  `status-glyph.tests.ps1` (78, včetně `-IndexFile` glyfů a findings)
  + fixtures (proposal dokumenty ve starém i novém pojmenování, Jira JSON
  snapshoty, `fixtures/doc-index/*.json`).
- [`mb-epic-elaboration/tests/`](../ums/.claude/skills/mb-epic-elaboration/tests/) —
  `ledger-status.tests.ps1` (9) + fixtures.
- [`mb-doc-index/tests/`](../ums/.claude/skills/mb-doc-index/tests/) —
  `enumeration.tests.ps1` (43; okno aktivity podle tipu větve, čerstvá větev
  se starým návrhovým commitem, uspaná větev dosažitelná přes commit společný
  se živou větví, symref `origin/HEAD`, `-BranchGlob` před
  filtrem aktivity, báze z `ums-repo.json` vs. explicitní `-BaseRef`, jméno
  větve s diakritikou, lokální sken, filtrování `tests/fixtures`),
  `findings.tests.ps1` (33; kolize včetně uspané větve při deklarovaném záměru,
  self-kolize vlastní pushnuté větve, fronta na více větvích, obživlá fronta)
  proti fixture repu generovanému `new-fixture-repo.ps1` (commity mají
  explicitní `GIT_AUTHOR_DATE`/`GIT_COMMITTER_DATE`, aby byl věk tipů
  deterministický).
- [`mb-migrate-docs/tests/`](../ums/.claude/skills/mb-migrate-docs/tests/) —
  `migrate.tests.ps1` (37; plán i `-Apply` mechanické migrace — sloučení
  `product.md` do `brief.md`, přejmenování `tasks.md` na `playbook.md`,
  přepis relativních odkazů v migrovaném stromu, přeskočení MB s
  `KONFLIKT PLAYBOOKU`), `verify.tests.ps1` (38; mazací režim
  `verify-deletion-only.ps1` — multiset-containment kontrola nad řádky,
  `VAROVÁNÍ` při ubrání přes 50 % neprázdných řádků) proti fixture repu
  generovanému `new-fixture-repo.ps1`.
- [`shared/tests/`](../ums/.claude/skills/shared/tests/) —
  `repo-config.tests.ps1` (33; loader `Get-UmsRepoConfig.ps1` — per-key
  defaulty, degradace na bezpečnější stranu u chybějícího i poškozeného
  souboru, normalizace bare stringu na jednoprvkový seznam v paritě
  s `guard-git-push.mjs`), `protected-branch.tests.ps1` (15; `Test-UmsProtectedBranch`
  — přesná shoda, glob, neshoda, vadný vzor jako NEshoda-a-nevyhodnoceno
  odlišená od platné neshody, shoda vyhrává nad vadným vzorem dál v seznamu,
  prázdný seznam i prázdné jméno větve), `base-candidates.tests.ps1` (12;
  `Get-UmsBaseCandidates` proti lokálnímu bare klonu jako `origin` — kandidáti
  jsou jen chráněné větve reálně existující na `origin`, symref `origin/HEAD`
  se nestává kandidátem, výchozí báze první a označená `IsDefault`, aktuální
  větev označená `IsCurrent` a řazená hned za výchozí, `Branch` strhává jen
  remote prefix a jedno lomítko), `effective-base.tests.ps1` (22;
  `Get-UmsEffectiveBase` — přednost řádku `Báze:` před `baseRef`, fallback při
  jeho absenci i bez `context.md`, tři tvary nesrozumitelného řádku
  (komentář za hodnotou, prázdná hodnota, chybějící diakritika) hlášené v
  `Malformed` a odlišené od „řádek chybí úplně", zachování řádku v IDLE stavu).
- [`hooks/tests/`](../ums/.claude/hooks/tests/) — `pre-push.tests.ps1` (230;
  end-to-end proti skutečnému lokálnímu bare remote: marker `MB_AGENT_SESSION`
  jako vstupní brána, obsahové pravidlo fast-forwardu na už dosažitelný tip,
  lidská výjimka `MB_HUMAN_PUSH`/zastaralé `UMS_ALLOW_SHARED_PUSH`,
  mazání/force i s ní zamítnuté, bufferovací rameno nad markerem, chaining
  cizího hooku (`run_chained`) i jeho čtyři odmítnuté případy,
  `core.hooksPath` lokální/globální/relativní per worktree, generovaný
  seznam chráněných větví a self-test instalátoru včetně důvodů přeskočení;
  běží přes dvě minuty, což je normální), `guard-git-push.tests.ps1` (332;
  JSON na stdin → rozhodnutí podle aktéra a fail-closed čtení cíle: chráněné
  větve včetně integračního fast-forwardu, force, `--no-verify`, obě jména
  únikové proměnné v POSIX i PowerShellovém zápisu, přesměrování krokovaná
  jako v reálném shellu, pojmenované mezery jako `bash -c` nebo git alias) a
  `sync-marker.tests.ps1` (18; `Set-AgentMarker` per harness — Codex
  `config.toml`, Gemini `.env`, Kilo Code hlásí `NotSupportedException` a
  nezapisuje nic).

**Upstream** — [`tests/`](../tests/) obsahuje shellové a Node.js testy
infrastruktury pluginu po harnessech (`claude-code`, `codex`, `kimi`,
`opencode`, `pi`, `antigravity`, `hooks`, `shell-lint`, `brainstorm-server`, …).
Eval harness pro chování skillů žije v samostatném repu klonovaném do `evals/`
(ignorováno); [`.pre-commit-config.yaml`](../.pre-commit-config.yaml) hlídá jen
jeho Python (ruff, ty).

## Pasti prostředí

- **`.gitignore` ignoruje každý `.claude/`** (upstream pravidlo, spolu
  s `.superpowers/`, `.worktrees/`, `evals/`). Vrstva to aditivně neguje
  souborem [`ums/.gitignore`](../ums/.gitignore) s řádkem `!.claude/`. Při
  přesunech souborů na to pozor — mimo `ums/` zůstává `.claude/` netrackovaný.
- **`bash` na tomto stroji může být tichý past.** Prosté `bash` v PATH může
  resolvnout na WSL launcher stub místo Git Bash — ten potichu zahodí
  poziční argumenty a běží nad jiným filesystémem. `install-git-hooks.ps1`
  proto Git Bash hledá explicitně (`bin\bash.exe`/`usr\bin\bash.exe` vedle
  `git.exe`), nikdy přes `bash` z PATH.
- **PowerShell má case-insensitive názvy proměnných.** Lokální `$jira = …`
  uvnitř funkce tiše přepíše parametr `-Jira` (a naopak) — `doc-index.ps1`
  proto drží hlavičkovou hodnotu dokumentu v `$docJira`, nikdy v `$jira`.
- **Funkce pojmenovaná `Git` by stínila `git.exe`.** PowerShellovo
  rozpoznávání příkazů upřednostní funkci před aplikací i case-insensitive,
  takže `& git …` uvnitř takové funkce by rekurzivně volalo samo sebe až do
  přetečení zásobníku — wrapper v `doc-index.ps1` se proto jmenuje
  `Invoke-RepoGit`, ne `Git`.
- **Nepřiřazený výstup uvnitř funkce se přilepí k návratové hodnotě volající
  funkce.** PowerShell vrací vše, co spadne do pipeline, takže volání jako
  `Invoke-Git $repo @('add', $path)` bez `| Out-Null` promění hashtable
  vracenou nadřazenou funkcí v pole — pod `Set-StrictMode` se to projeví až
  u volajícího, daleko od příčiny. Fixture builder
  [`new-fixture-repo.ps1`](../ums/.claude/skills/mb-doc-index/tests/new-fixture-repo.ps1)
  proto zahazuje výstup na každém takovém místě.
- **`$LASTEXITCODE` čtený před jakýmkoli nativním příkazem pod
  `Set-StrictMode -Version Latest` shazuje výjimku** ("cannot be retrieved
  because it has not been set") — v `doc-index.ps1` nastává, když je
  `-RepoPath` zadaný explicitně a `git rev-parse --show-toplevel` se vůbec
  nespustí.
- **Cíl git hooku se musí resolvovat `git rev-parse --git-path
  hooks/<name>`**, jinak instalace tiše mine linked worktree nebo
  `core.hooksPath`. **Relativní `core.hooksPath`** se navíc resolvuje
  per-worktree (ne per-repository) — instalace do hlavního klonu nechá
  ostatní linked worktree bez hooku; `install-git-hooks.ps1` na to hlásí
  varování a potřebuje samostatný běh pro každý worktree. Self-test
  instalátoru (dvě povinná kola plus třetí, podmíněné, kdykoli konfigurace
  jmenuje chráněný vzor nad rámec vestavěné čtveřice — s vlastní kontrolou na
  neschovaném jméně, aby se nepřehlédlo, že třetí kolo přestalo rozlišovat)
  navíc musí porovnávat case-sensitive marker
  (`-cmatch 'UMS: '`), ne substring `-match 'UMS'` — ten by broken hook,
  jehož chybová hláška jen cituje vlastní cestu, vyhodnotil jako ověřený
  v každém repozitáři ležícím pod adresářem se jménem obsahujícím „ums".
- **`git branch --show-current` vrací i jméno nenarozené větve** (repo bez
  jediného commitu) — cestu „nejde určit aktuální větev" tak reálně
  vyzkouší jen detached HEAD, ne čerstvě inicializovaný repozitář.
- **Výkon `doc-index.ps1` je změřený v obou měřítkách.** V tomto forku (4 refy
  pod `refs/remotes/origin/`) trvá běh 2,0 s s `-NoFetch` a 3,0 s včetně
  `git fetch`. Proti monorepu UMS (219 vzdálených větví, `.git` 4,1 GB) trvá
  běh s `-NoFetch` a defaultním oknem 30 dní **32–35 s**; deklarovaný záměr
  (`-Jira`/`-Slug`), který enumeruje bez časového omezení, **57 s**. Rozpočet
  z návrhu (do 15 s) tedy splněný není — předchozí implementace filtrující
  podle data commitu byla na témže repu ještě pomalejší (39,7 s). Čtení refů
  ani traverzace nejsou úzké místo (`for-each-ref` 219 refů 0,10 s,
  `git log --stdin` 0,12 s / 33 commitů); čas žere `git branch -r --contains`
  na každý commit (3,1 s / 33 commitů) a pak `cat-file -e` + `show` na každý
  pár (větev, cesta) — 139 párů v tom běhu. Refy se do `git log` předávají
  přes `--stdin`, protože 219 jmen refů na příkazové řádce má 13,7 kB a míří
  k 32k limitu Windows.
- **Jména refů se v `doc-index.ps1` vrací zpátky do gitu, takže musí přežít
  round trip přes PowerShell.** `git for-each-ref` tiskne jméno větve jako
  surové UTF-8 a to, co z něj PowerShell dekóduje, přesně to pošle na stdin
  `git log --stdin`. Bez `[Console]::OutputEncoding = UTF8` (dekódovací strana,
  ta nese váhu; `$OutputEncoding` je pojistka na kódovací straně) skončí větev
  s diakritikou jako `fatal: bad revision` a celý index spadne na exit 1.
  Monorepo takové větve reálně má (`origin/UMS-1646-mobilní-klient-pro-alarminfo`),
  fixture repo testů je proto taky má.
