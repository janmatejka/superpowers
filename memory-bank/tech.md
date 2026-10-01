# Tech

Ecosystem: dokumentační a skriptový — Markdown (skilly a kontrakt), PowerShell 7
(nástroje vrstvy), Node.js ESM (hooky), Bash (upstream skripty SDD). Žádný
kompilovaný build, žádný package manager pro vrstvu samotnou.

## Verze a piny

| Co | Hodnota | Zdroj |
|---|---|---|
| Superpowers (upstream) | 6.4.2 | [`package.json`](../package.json), [`.claude-plugin/plugin.json`](../.claude-plugin/plugin.json) |
| Vendor pin vrstvy | tag `v6.4.2`, commit `8ca22dba9a94f28898bbce59f2537ff4d87c747d`, vendorováno 2026-09-29; pin je jediný zdroj tagu i sady skillů (mechanika v [architecture.md](architecture.md), sekce 7) | [`VENDORED_FROM.md`](../ums/.claude/skills/shared/VENDORED_FROM.md) |
| Kontrakt Memory Bank | 3.2, jádro 799 řádků (rozpočet 800, `contract-shape.tests.ps1`) | [`UMS_MEMORY_BANK_CONTRACT.md`](../ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md) |
| Vendorované skilly | 14 (`brainstorming`, `dispatching-parallel-agents`, `executing-plans`, `finishing-a-development-branch`, `receiving-code-review`, `requesting-code-review`, `subagent-driven-development`, `systematic-debugging`, `test-driven-development`, `using-git-worktrees`, `using-superpowers`, `verification-before-completion`, `writing-plans`, `writing-skills`); vyloučený (`Excluded:` v pinu) `diagnosing-superpowers` | `VENDORED_FROM.md` |
| Overlay fragmenty | pět cílů (`brainstorming`, `subagent-driven-development`, `finishing-a-development-branch`, `writing-plans`, `executing-plans`), každý dva fragmenty — `<skill>.overlay.md` (tělo) a `<skill>.pointer.overlay.md` (hlavičkový ukazatel), dohromady 10 souborů + `README.md` | [`shared/overlays/`](../ums/.claude/skills/shared/overlays/) |

## Tvar kontraktu: jádro, reference, doklad, changelog

Kontrakt 3.2 je čtyři soubory/adresáře v `ums/.claude/skills/shared/`, každý
s jiným čtenářem a jiným rozpočtem (mechanika a citační tvar jsou v
[architecture.md](architecture.md), sekce „Jádro kontraktu"):

| Vrstva | Cesta | Čtenář | Rozpočet |
|---|---|---|---|
| Jádro | [`UMS_MEMORY_BANK_CONTRACT.md`](../ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md) | každé sezení, mechanicky hookem `contract-inject.ps1` | 800 řádků (aktuálně 799), vynuceno `contract-shape.tests.ps1` |
| Reference | [`shared/contract/*.md`](../ums/.claude/skills/shared/contract/) — 17 souborů podle tématu | skill nebo overlay, který téma provádí (jádro, sekce „Phase Map") | bez rozpočtu, jedno téma na soubor |
| Doklad | [`shared/contract/doklad/*.md`](../ums/.claude/skills/shared/contract/doklad/) — 15 souborů | autor změny pravidla, na vyžádání | bez rozpočtu |
| Historie | [`shared/CHANGELOG.md`](../ums/.claude/skills/shared/CHANGELOG.md) | nikdo za běhu, jen při čtení historie verzí | bez rozpočtu |

## Konfigurace repozitáře (`ums-repo.json`)

[`ums-repo.json`](ums-repo.json) v `CTX_DIR` nese repozitářově specifické
hodnoty, které kontrakt zakazuje mít v tělech skillů nebo skriptů
(kontrakt/repository-configuration.md, Repository Configuration). Tento repozitář:

| Klíč | Hodnota |
|---|---|
| `baseRef` | `origin/ums-memory-bank` |
| `protectedBranches` | `ums-memory-bank`, `main`, `master`, `develop`, `release/*`, `Branches/*` |
| `ticketPattern` | `^UMS-[0-9]+` |
| `projectMarkers` | `package.json` |
| `sharedRoots` | `ums/.claude/skills/shared/`, `ums/.gitattributes` |
| `epicBranchPattern` | nenastaveno — platí vestavěný default `epic/*` |
| `permalinkTemplate` | nenastaveno — odvozeno z hostu `origin` (`github.com`) skriptem `Get-UmsPermalink.ps1` |

Loader [`Get-UmsRepoConfig.ps1`](../ums/.claude/skills/shared/scripts/Get-UmsRepoConfig.ps1)
nikdy nevyhazuje výjimku: chybějící nebo poškozený soubor degraduje po
jednotlivých klíčích k vestavěným defaultům (`origin/develop` jako báze,
vestavěná čtveřice chráněných větví, obecný vzor tiketu, prázdné
`projectMarkers`/`sharedRoots`) — vždy k bezpečnější straně, nikdy k méně
ochraně. Bare string u kterékoli seznamové hodnoty se normalizuje na
jednoprvkový seznam stejně jako v `guard-git-push.mjs`, takže obě vynucovací
vrstvy (generovaný seznam pro `pre-push` a `guard-git-push.mjs`) dají na
stejnou konfiguraci vždy stejnou odpověď.

**Jediná výjimka z „degradace vždy k víc ochraně" je `epicBranchPattern`.**
Klíč má tři stavy: **chybí** = vestavěný default `epic/*` (rozšíření
privilegia bez konfiguračního kroku, které rozhodl člověk a které kontrakt
zapisuje — kontrakt/epic-line.md, „The epic line"); **přítomný neprázdný řetězec**
= ten vzor; **přítomný cokoli jiného** (prázdný nebo jen z mezer, číslo, pole,
`null`) = žádná epiková linie, výslovné vypnutí, ne návrat k defaultu (kontrola
`-is [string]` je nosná — bez ní by nestringová hodnota shodila `.Trim()`).
Klíč nečte `pre-push` ani `guard-git-push.mjs`; vzor rozpoznává epikovou linii
jako nechráněnou bázi přes `Test-UmsIntegrationBase` (role linie:
[architecture.md](architecture.md), sekce 3, „Epiková linie"). Změna vzoru je v
eskalačním dně kontraktu, bezpodmínečně u člověka.

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
  [`Test-UmsIntegrationBase.ps1`](../ums/.claude/skills/shared/scripts/Test-UmsIntegrationBase.ps1)
  (`Test-UmsIntegrationBase` — smí větev sloužit jako báze a jakého `Kind`:
  `protected`, `epic-line`, `none`; viz [architecture.md](architecture.md), sekce 3),
  [`Get-UmsBaseCandidates.ps1`](../ums/.claude/skills/shared/scripts/Get-UmsBaseCandidates.ps1),
  [`Get-UmsEffectiveBase.ps1`](../ums/.claude/skills/shared/scripts/Get-UmsEffectiveBase.ps1),
  [`Test-UmsHandoffGate.ps1`](../ums/.claude/skills/shared/scripts/Test-UmsHandoffGate.ps1)
  (brána předání — viz [architecture.md](architecture.md), sekce 3),
  [`Get-UmsEpicLedger.ps1`](../ums/.claude/skills/shared/scripts/Get-UmsEpicLedger.ps1)
  (čtení `## Ověřovací sada` ledgeru epiku po refu),
  [`Get-UmsHookVersion.ps1`](../ums/.claude/skills/shared/scripts/Get-UmsHookVersion.ps1)
  (`Get-UmsHookVersion`/`Test-UmsHookNeedsInstall` — verze `pre-push` hooku
  porovnaná uspořádáním proti zdrojové hlavičce vrstvy, nikdy rovností; čtou ji
  `install-git-hooks.ps1` a `pool-provision.ps1` — viz [architecture.md](architecture.md),
  sekce Publikace a viditelnost napříč větvemi),
  [`epic-gate.ps1`](../ums/.claude/skills/mb-epic-run/scripts/epic-gate.ps1)
  (dvě epikové kontroly operace `integrate`, sekce 6),
  [`epic-line.ps1`](../ums/.claude/skills/mb-epic-run/scripts/epic-line.ps1)
  (`New-UmsEpicLine` — založení `epic/<KLÍČ>` z dodávkové linie při `spawn`,
  jen založení, existující linii nikdy neposune),
  [`outbox.ps1`](../ums/.claude/skills/mb-epic-run/scripts/outbox.ps1)
  (`Add-UmsOutboxEntry`, `Set-UmsOutboxState`, `Get-UmsOutbox` — outbox
  správce, sekce 6),
  [`session-intent.ps1`](../ums/.claude/hooks/session-intent.ps1) (`SessionStart`
  hook, čtenář session intent batonu — viz [architecture.md](architecture.md),
  sekce Session Intent Baton),
  [`contract-inject.ps1`](../ums/.claude/hooks/contract-inject.ps1) (`SessionStart`,
  `PostCompact` a `UserPromptSubmit` hook, mechanická injektáž jádra kontraktu —
  viz [architecture.md](architecture.md), sekce „Jádro kontraktu"),
  [`Get-UmsPermalink.ps1`](../ums/.claude/skills/shared/scripts/Get-UmsPermalink.ps1)
  (`Get-UmsPermalink` — `permalinkTemplate` s dosazením `{sha}`/`{path}`, jinak
  odvození z hostu `origin`, `github.com` a `bitbucket.org`; neznámý host vrací
  `Reason` a žádné `Url`; SHA musí být 40 malých hex znaků, cesta bez `..`),
  [`Test-UmsJiraDescription.ps1`](../ums/.claude/skills/shared/scripts/Test-UmsJiraDescription.ps1)
  (`Test-UmsJiraDescription` — rozpočet 2 500 znaků, tvar odkazů, tučné ×
  code span; `-RequireSections` pro popisy tiketů, bez přepínače pro
  komentáře),
  [`Test-UmsContractMove.ps1`](../ums/.claude/skills/shared/scripts/Test-UmsContractMove.ps1)
  (multiset porovnání řádků mezi zdrojem a cílem přesunu, vzor
  `verify-deletion-only.ps1` z `mb-migrate-docs`), hook `bpmn-validate.ps1`,
  [`Get-UmsPlaybookChain.ps1`](../ums/.claude/skills/shared/scripts/Get-UmsPlaybookChain.ps1)
  (`Get-UmsMbTree` — strom MB odvozený z trackovaných playbooků/`tasks.md`;
  `Get-UmsPlaybookChain -Out` — řetězec MB do
  `.superpowers/playbook-chain/<mb>.md`; `Get-UmsMbLowestCommonAncestor`),
  [`Read-UmsPlaybook.ps1`](../ums/.claude/skills/shared/scripts/Read-UmsPlaybook.ps1)
  (`Read-UmsPlaybook`, `Get-UmsPlaybookRatchet` — parser tří tvarů položek
  a čtení ráčnového komentáře),
  [`Test-UmsPlaybookShape.ps1`](../ums/.claude/skills/shared/scripts/Test-UmsPlaybookShape.ps1)
  (`Test-UmsPlaybookShape` — tvar a rozpočet jednoho souboru;
  `Test-UmsPlaybookTree` — navíc rozpočet řetězců celého podstromu;
  `Get-UmsRetiredListWarnings`, `Get-UmsSentenceCount` pro heuristiku
  `Proč:`),
  [`Find-UmsPlaybookMatch.ps1`](../ums/.claude/skills/shared/scripts/Find-UmsPlaybookMatch.ps1)
  (`Find-UmsPlaybookMatch` — až tři kandidátní položky řetězce podle shody
  identifikátorů v backticks; `Get-UmsBacktickTokens`),
  [`mb-playbook-consolidate/scripts/consolidate-playbook.ps1`](../ums/.claude/skills/mb-playbook-consolidate/scripts/consolidate-playbook.ps1)
  (`-Parse`, `-Apply <decisions.json>`, `-Baseline`, `-Resume <běh>`, `-Stats`,
  `-Tree`; mechanická půlka harvestové brány i konsolidace — zápis vždy LF,
  viz „Pasti prostředí" níže).
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
  (kontrakt/architect-review.md, Architect Review Gate, „Design Review" fallback); fail-closed
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
| `hooks.SessionStart` | Dva záznamy. První (bez matcheru, na každý zdroj startu) spouští `contract-inject.ps1` sedmkrát (`-Part 1..7` — strop 10 000 znaků na `additionalContext` jednoho hooku, viz [architecture.md](architecture.md), sekce „Jádro kontraktu"), dohromady emituje `additionalContext`: jádro kontraktu doslova, řádky `context.md` a (existuje-li ledger slugu z pinu) blok `NOW`, plus pokyn vyvolat `using-superpowers` a spustit fázi 0 vstupní brány (jádro, sekce „Způsobilost sezení" — fail-closed ověření verze `pre-push` hooku a obě poloviny jeho syntetického self-checku). Druhý, matcher `clear\|startup`, spouští `session-intent.ps1` — čtenáře session intent batonu (viz [architecture.md](architecture.md), sekce Session Intent Baton); `resume`, `compact` a `fork` matcher vynechává, protože takové sezení si nese vlastní transkript i baton, který samo napsalo |
| `hooks.PostCompact` | Spouští `contract-inject.ps1`; protože `PostCompact` `additionalContext` nepřijímá (jen `systemMessage`), hook zapíše markery `.superpowers/contract-reload.flag` a `contract-reload.part<k>.flag` (jeden na díl) a vrátí `systemMessage` s pokynem jednat podle shrnutí a znovu vyvolat vykonávaný skill |
| `hooks.UserPromptSubmit` | Spouští `contract-inject.ps1` po dílech jako `SessionStart`; každý díl se svým markerem z `PostCompact` vloží svůj řez a svůj marker smaže, bez markeru mlčí — jádro se tak mechanicky vrací s prvním promptem po kompaktaci |
| `hooks.PreToolUse` (`Write|Edit`) | `deny-superpowers-docs.mjs` — blokuje zápis do `docs/superpowers/**` a `docs/plans/**` |
| `hooks.PreToolUse` (`Bash|PowerShell`) | `guard-git-push.mjs` — nese pravidlo podle AKTÉRA (jen vlastní tool-cally agenta, ne příkazy uživatele psané přes `!`): na rozpoznaný `git push` leans fail-CLOSED (nečitelný cíl zamítá, nečeká na vyjasnění), zamítá push agenta na chráněnou větev včetně integračního fast-forwardu, obě jména únikové proměnné v POSIX i PowerShellovém zápisu a `--no-verify` bez kontextu, na epikovou linii (nechráněná báze) žádnou výjimku nenese a nečte `epicBranchPattern` ani `baseRef`; NENÍ záruka publikace — tou zůstává git `pre-push` hook (níže), který navíc vynucuje jen uvnitř agentní relace |
| `hooks.PostToolUse` (`Write|Edit`) | `bpmn-validate.ps1` — validace BPMN v monorepu |
| `permissions.allow` | read-only nástroje (grep, rg, cat, head, tail, ls, wc, diff, sed, find, test, echo; git status/diff/log/show/ls-files/rev-parse/branch/check-ignore/stash list/fetch/ls-remote/for-each-ref/ls-tree/cat-file/merge-base; PowerShell Get-Content/Get-ChildItem/Test-Path/Select-String) |
| `permissions.deny` | `EnterWorktree`, `ExitWorktree`, `Bash(rm -rf:*)`, `Bash(git reset --hard:*)`, `Bash(git worktree:*)`, `PowerShell(git worktree:*)`, `Bash(pool-provision.ps1:*)`, `PowerShell(pool-provision.ps1:*)` — poslední čtveřice vynucuje mechanicky, že worktree i jeho provisionaci zakládá jen uživatel (kontrakt, Worktree Policy) |
| `skillOverrides` | `using-git-worktrees: off` |
| `worktree.bgIsolation` | `none` |

`git push` už není v `permissions.deny` — je binární a deny vyhrává nad allow,
takže by nešlo rozvolnit jen pro vlastní tiketovou větev. Skutečnou hranicí
publikačního pravidla (kontrakt, Publication Contract) je git `pre-push` hook
(verze podle hlavičky ve vrstvě) [`ums/.claude/hooks/pre-push`](../ums/.claude/hooks/pre-push) (POSIX
`sh`, scope `refs/heads/*`) — git mu předá už rozparsované čtveřice refů, ne
shellový text, takže žádné parsování k obejití neexistuje. Vynucuje jen
uvnitř agentní relace: vstupní brána je marker `MB_AGENT_SESSION=1` (fallback
na jakékoli neprázdné `AI_AGENT` — nastavuje ho kterýkoli harness, Pi ho
nastavuje sám — nebo na `CLAUDECODE=1`, viz níže tabulka doručení markeru per
harness); mimo relaci hook nic vlastního
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

Tam, kde je náš `pre-push` už nainstalovaný a repozitář používá Git LFS,
instalátor navíc obnoví ztracený LFS `pre-push` řetěz na `<jméno>.ums-chained`
regenerací přímo z git-lfs (`Restore-LfsChainedHook` — mechanika, pět
podmínek a provenienční stopa jsou v [architecture.md](architecture.md),
sekce Publikace a viditelnost napříč větvemi). **Exit kódy zůstávají 0–4
beze změny** — neobnovený řetěz nedostává vlastní kód, protože kódy mluví
k záruce guard hooku, ne k LFS uploadu; ohlašuje se jen řádkem `note:` na
místě volání a trvale přes `mb-state`.

**Doručení markeru `MB_AGENT_SESSION`** dělá
[`sync-with-monorepo.ps1`](../ums/sync-with-monorepo.ps1) do dokumentovaného
mechanismu každého harnessu; cesty a mechanismy jsou v jediné tabulce
`Get-UmsSyncTargets` (zápis markeru `Set-AgentMarker`). Sloupec „Záruka" říká,
zda `pre-push` hook v daném harnessu pozná agentní relaci:

| Harness | Skilly (projekt / profil) | Instrukční soubor (projekt / profil) | Marker `MB_AGENT_SESSION` | Záruka |
|---|---|---|---|---|
| Claude Code (`claude`) | `.claude/skills` | `CLAUDE.md` / `.claude/CLAUDE.md` | `env` blok [`ums/.claude/settings.json`](../ums/.claude/settings.json) — `-Scope UserProfile` tento soubor záměrně nenasazuje, takže tam zůstává jen fallback `CLAUDECODE=1`/neprázdný `AI_AGENT` | ano |
| Codex (`codex`) | `.agents/skills` | `AGENTS.md` / `.codex/AGENTS.md` | `.codex/config.toml`, `[shell_environment_policy].set` (merguje se do existující tabulky) | ano |
| Gemini CLI (`gemini`) | `.agents/skills` | `GEMINI.md` / `.gemini/GEMINI.md` | `.gemini/.env` | ano |
| Qwen Code (`qwen`) | `.qwen/skills` | `QWEN.md` / `.qwen/QWEN.md` | `.qwen/.env` | ano |
| OpenCode (`opencode`) | `.agents/skills` | `AGENTS.md` / `.config/opencode/AGENTS.md` | plugin `plugins/ums-agent-session.js` s hookem `shell.env` | ano |
| Pi (`pi`) | `.agents/skills` | `AGENTS.md` / `.pi/agent/AGENTS.md` | nic se nezapisuje — CLI Pi nastavuje `AI_AGENT=pi` (ne při vložení přes SDK) | ano, přes fallback `AI_AGENT` |
| Hermes (`hermes`) | `.agents/skills` / `.hermes/skills` | `.hermes.md` / — | jen profil: `terminal.env_passthrough` v `config.yaml` + `.hermes/.env` (v projektu `NotSupportedException`) | profil ano, projekt **ne** |
| Cursor, Devin, Droid, Kimi, Muse (`cursor`, `devin`, `droid`, `kimi`, `muse`) | `.agents/skills` | `AGENTS.md` / — | žádný zdokumentovaný mechanismus | **ne** |
| Copilot CLI (`copilot`) | `.agents/skills` | `.github/copilot-instructions.md` / — | žádný zdokumentovaný mechanismus | **ne** |
| Antigravity (`antigravity`) | `.agents/skills` / `.gemini/antigravity-cli/skills` | `AGENTS.md` / — | žádný zdokumentovaný mechanismus | **ne** |
| Grok Build (`grok`) | `.grok/skills` | `AGENTS.md` / — | žádný zdokumentovaný mechanismus | **ne** |

Profilové cesty skillů a instrukčních souborů jsou vůči `$HOME`, projektové
vůči kořeni cíle; není-li uvedena profilová cesta skillů, je stejná jako
projektová. `kilocode` není cíl (upstream Superpowers ho nepodporuje) a sync
ho odmítne jménem. U harnessů bez mechanismu skript marker nezapíše, vytiskne
varování „the pre-push guarantee does not bind '<agent>'" a `pre-push` hook tam
poznává agentní relaci jen tehdy, když `MB_AGENT_SESSION` nebo `AI_AGENT`
nastaví někdo jiný; sdílený cíl (`.agents/skills`, `AGENTS.md`) se zapíše
jednou. Konfigurační adresář harnessu (`.codex`, `.gemini`, …) slouží k merge
lepidla (`hooks/`, `scripts/`) a k zápisu markeru; `settings.json` dostává jen
Claude.

Tvrzení „git hook je harness-agnostický" proto platí jen pro samotné
spuštění hooku (je to prostý git mechanismus, ne funkce Claude Code) — jeho
vynucovací branu ale otevírá marker, a ten se k harnessům se sloupcem „Záruka"
**ne** nedostane.

## Testy

Jak se sady spouštějí a jaké konvence platí pro novou sadu, je
v [playbook.md](playbook.md).

**UMS vrstva** — bezzávislostní PowerShell testy vedle skillů (sady sync
skriptu v [`ums/tests/`](../ums/tests/), sada revendoru v
[`ums/.claude/scripts/tests/`](../ums/.claude/scripts/tests/)), 49 sad,
dohromady 2973 asercí (naměřeno 1. 10. 2026 smyčkou přes celou vrstvu z
PowerShellu, ne aritmetikou). Tři asercie selhávají kvůli prostředí, ne kvůli
kódu: dvě v `pool-launch.tests.ps1` — Gate 3, „cíl Start-Process, který reálně
nespustí proces" — protože sandbox neumožňuje ověřit skutečné spuštění
procesu, a jedna v `contract-inject.tests.ps1` („varování o rozchodu je první
řádek payloadu"), která při spuštění s přesměrovaným výstupem (smyčka z Git
Bash, `Start-Process` s přesměrováním) narazila na kódovou stránku a
diakritiku v textu varování. Šlo o tutéž chybu kódování, kvůli které harness
odmítal výstup hooku (viz „Pasti prostředí"); od opravy výstupu na čisté
ASCII by měla procházet. Spuštěná přímo z PowerShellu sada prochází:

- [`ums/tests/`](../ums/tests/) — šest sad `sync-with-monorepo.ps1` se
  společným `_assert.ps1`, fixture builderem `new-sync-fixture.ps1` (fork
  s dvěma tagy a fragmenty, monorepo jako git repo s lokálním bare originem)
  a `fixtures/claude-md-legacy.md`; všechny píší jen do OS temp, živé monorepo,
  profil ani tento repozitář se jich netýkají: `sync-targets.tests.ps1` (328;
  `Get-UmsSyncTargets` — 15 harnessů × scope, jediný zdroj cest, odmítnutý
  `kilocode` jménem), `sync-drift.tests.ps1` (65; hash stromu po normalizaci
  CRLF, manifest per worktree ověřený na skutečném linked worktree,
  trojstavové porovnání cíl × manifest × fork, `mb-*` jen v cíli),
  `sync-vendor.tests.ps1` (50; plán vendoringu — plný / jen vanilla fáze /
  žádný —, revendor jako proces nad cílem, detekce trackování gitem),
  `sync-claudemd.tests.ps1` (68; `Set-MarkedBlock`/`Get-MarkedBlockContent` —
  náhrada bloku na místě, migrace souboru bez markerů podle nadpisů sekcí
  s bajtově nedotčeným zbytkem), `sync-fork.tests.ps1` (61; `-Scope Fork` —
  nesahá na `CLAUDE.md` ani `AGENTS.md`, zapíše `.git/info/exclude` tak, že
  `git status --porcelain` zůstane prázdný) a `sync-e2e.tests.ps1` (148; tělo
  skriptu jako proces nad fixturou — výchozí směr, drift STOP exit 3, `-Force`,
  `-WhatIf` bez zápisu, vanilla fáze exit 4 a její hláška, `FromMonorepo` bez
  vendorovaných skillů, varování o záruce, částečné selhání exit 5,
  neinteraktivní `-Force` bez cíle exit 1; jednotkově `Test-UmsNeedsTargetMenu`,
  `Get-UmsDriftAction` a `ConvertFrom-UmsDriftAnswer` — samotné interaktivní
  dotazy procesem ověřit nejdou, sady běží s přesměrovaným vstupem; případ bez
  parametrů přesměruje kořen monorepa proměnnou `UMS_SYNC_MONOREPO_ROOT` na
  fixturu a před během ověří, že default opravdu míří na fixturu).
- [`ums/.claude/scripts/tests/`](../ums/.claude/scripts/tests/) —
  `revendor.tests.ps1` (117) s `_assert.ps1` a `new-revendor-fixture.ps1`
  (offline „upstream" je lokální git repo se dvěma tagy): čtení a zápis pinu
  (Tag, Commit, Skills, Excluded), `-PinOnly` (bez rozhodnutí o novém skillu
  selže a jmenuje ho, `-Exclude`, idempotence), vendor fáze čtoucí tag i sadu
  skillů z pinu (`-SkillsRoot` mimo `UmsRoot`, `-PinSource`, bez `-Tag`),
  mazání skillů, které opustily pin, poloha hlavičkového ukazatele, víc
  fragmentů na cíl (tělo první, ukazatel druhý, jedna hláška „cíl není
  pristine"), požadované soubory podle pinu, funkční test `sdd-workspace`
  pod Git Bash i v cíli, který je linked worktree (pool slot), `Resolve-UmsGitBash`
  a zvlášť vyjmutý funkční test mimo git repo.

- [`mb-epic-graph/tests/`](../ums/.claude/skills/mb-epic-graph/tests/) —
  `e2e.tests.ps1` (12), `graph-generation.tests.ps1` (27),
  `oracle-prose.tests.ps1` (5), `oracle-structural.tests.ps1` (10),
  `status-glyph.tests.ps1` (78, včetně `-IndexFile` glyfů a findings)
  + fixtures (proposal dokumenty ve starém i novém pojmenování, Jira JSON
  snapshoty, `fixtures/doc-index/*.json`).
- [`mb-epic-elaboration/tests/`](../ums/.claude/skills/mb-epic-elaboration/tests/) —
  `ledger-status.tests.ps1` (49; sekce ledgeru „## Rozjetí" — pozičně
  parsovaná tabulka řádků záměru o SEDMI sloupcích, poslední dva jsou
  `Autonomie` a `Pasti` — její orphan případ, tiket v řádku záměru bez
  odpovídajícího člena epiku, a řádek ze šestisloupcové éry, který se hlásí
  jako nedostatečný, nikdy se nečte jako úroveň autonomie; plus podlaha
  ledgeru — číselný slib bez jmen selhávajících testů je špinavý, dokud
  jména nedorazí, fixture `ledger_floor.md`),
  `ledger-evidence.tests.ps1` (40; ověřovací sada a registr rozhodnutí)
  + fixtures (`ledger_rozjeti.md`, `ledger_rozjeti_orphan.md`,
  `ledger_verification_set.md`, `ledger_decision_registry.md`).
- [`mb-epic-run/tests/`](../ums/.claude/skills/mb-epic-run/tests/) — testy
  mechaniky poolu (`mb-epic-run`, viz [architecture.md](architecture.md),
  sekce 6), vlastní `_assert.ps1` a fixture builder
  `new-pool-fixture.ps1` (skutečné linked worktrees se sdíleným `.git`, ne
  simulace): `pool-status.tests.ps1` (124; volnost jen z per-worktree signálů,
  marker, obsazenost stubovaná `tests/stubs/claude-stub.ps1`, ledger podle
  slugu z pinu, `-1` jako nečitelný sentinel u `dirtyCount`/`unpushedCount`,
  blok `NOW` včetně tvarů, které ho dělají malformovaným, znaková třída
  a strop toho, co smí z cizího ledgeru ven, tvar slugu jako komponenty cesty
  a kulturně nezávislé timestampy),
  `pool-launch.tests.ps1` (41; vyčištění devíti proměnných, oba adaptéry
  proti `tests/stubs/argv-probe.ps1`/`argv-probe.cmd`, pět odmítnutých tvarů
  promptu, stavové slovo na vlastní řádce), `pool-provision.tests.ps1` (28;
  guard proti agentní relaci, marker, kontrola sdíleného hooku — verze
  porovnaná uspořádáním proti zdrojové hlavičce, ne rovností — exit 5 při
  nepotvrzené publikační záruce), `epic-gate.tests.ps1` (44; brána předání
  a její čtyři kontroly, vazba fast-forwardu na vlastní epik, nepotvrzený
  řádek registru rozhodnutí jako mechanická zábrana), `epic-line.tests.ps1`
  (20; `New-UmsEpicLine` proti lokálnímu bare originu — první volání linii
  založí z dodávkové linie, druhé ji nemění, existující linie se nepřepíše,
  ani když se dodávková linie posunula, `DeliveryRef` smí být SHA, chybný
  vstup a odmítnutý push jsou výjimka), `outbox.tests.ps1` (58; `outbox.ps1` —
  uzavřený formát řádku, stavy `open`→`resent`→`closed`, čtenář parsuje a
  znovu vykresluje, řádek s nepovoleným znakem se zahodí a spočítá,
  poškozený titulek nebo přerostlý soubor dává prázdný výsledek bez výjimky),
  `frontmatter.tests.ps1` (2).
- [`mb-doc-index/tests/`](../ums/.claude/skills/mb-doc-index/tests/) —
  `enumeration.tests.ps1` (43; okno aktivity podle tipu větve, čerstvá větev
  se starým návrhovým commitem, uspaná větev dosažitelná přes commit společný
  se živou větví, symref `origin/HEAD`, `-BranchGlob` před
  filtrem aktivity, báze z `ums-repo.json` vs. explicitní `-BaseRef`, jméno
  větve s diakritikou, lokální sken, filtrování `tests/fixtures`),
  `findings.tests.ps1` (33; kolize včetně uspané větve při deklarovaném záměru,
  self-kolize vlastní pushnuté větve, fronta na více větvích, obživlá fronta),
  `output-target.tests.ps1` (12; cíl `-Json` kontrolovaný před prací —
  chybějící adresář zastaví běh dřív, než vypíše report, plus tři pozitivní
  kontroly, aby sada nezezelenala nad skriptem, který `-Json` odmítá vždy),
  `targeted-scan.tests.ps1` (16; **počítá skutečná volání gitu**
  zaznamenávajícím `git.bat` shimem v PATH — deklarovaný záměr nesmí přidat
  ani jedno `branch -r --contains` nad okenní běh, a uspaná větev musí být
  přesto dosažena) proti fixture repu generovanému `new-fixture-repo.ps1`
  (commity mají explicitní `GIT_AUTHOR_DATE`/`GIT_COMMITTER_DATE`, aby byl věk
  tipů deterministický).
- [`mb-migrate-docs/tests/`](../ums/.claude/skills/mb-migrate-docs/tests/) —
  `migrate.tests.ps1` (37; plán i `-Apply` mechanické migrace — sloučení
  `product.md` do `brief.md`, přejmenování `tasks.md` na `playbook.md`,
  přepis relativních odkazů v migrovaném stromu, přeskočení MB s
  `KONFLIKT PLAYBOOKU`), `verify.tests.ps1` (38; mazací režim
  `verify-deletion-only.ps1` — multiset-containment kontrola nad řádky,
  `VAROVÁNÍ` při ubrání přes 50 % neprázdných řádků) proti fixture repu
  generovanému `new-fixture-repo.ps1`.
- [`shared/tests/`](../ums/.claude/skills/shared/tests/) —
  `repo-config.tests.ps1` (45; loader `Get-UmsRepoConfig.ps1` — per-key
  defaulty, degradace na bezpečnější stranu u chybějícího i poškozeného
  souboru, tři stavy `epicBranchPattern` (chybí = default `epic/*`, prázdný nebo
  nestringový = žádná linie), normalizace bare stringu na jednoprvkový seznam v paritě
  s `guard-git-push.mjs`), `protected-branch.tests.ps1` (15; `Test-UmsProtectedBranch`
  — přesná shoda, glob, neshoda, vadný vzor jako NEshoda-a-nevyhodnoceno
  odlišená od platné neshody, shoda vyhrává nad vadným vzorem dál v seznamu,
  prázdný seznam i prázdné jméno větve), `base-candidates.tests.ps1` (23;
  `Get-UmsBaseCandidates` proti lokálnímu bare klonu jako `origin` — kandidáti
  jsou chráněné větve a epikové linie (`IsEpicLine`) reálně existující na `origin`, symref `origin/HEAD`
  se nestává kandidátem, výchozí báze první a označená `IsDefault`, aktuální
  větev označená `IsCurrent` a řazená hned za výchozí, `Branch` strhává jen
  remote prefix a jedno lomítko), `effective-base.tests.ps1` (22;
  `Get-UmsEffectiveBase` — přednost řádku `Báze:` před `baseRef`, fallback při
  jeho absenci i bez `context.md`, tři tvary nesrozumitelného řádku
  (komentář za hodnotou, prázdná hodnota, chybějící diakritika) hlášené v
  `Malformed` a odlišené od „řádek chybí úplně", zachování řádku v IDLE stavu),
  `handoff-gate.tests.ps1` (32; `Test-UmsHandoffGate` — čerstvý tip báze,
  kanonický IDLE `context.md` commitu, dosažitelnost na `origin`),
  `hook-version.tests.ps1` (11; `Get-UmsHookVersion`/`Test-UmsHookNeedsInstall`
  — verze čtená z hlavičky (`v2`, `v3`, hook bez přípony jako 0, cizí hook
  jako `$null`), značka pod pátým řádkem se nepočítá, a srovnání uspořádáním:
  novější nainstalovaná verze se nedegraduje, i když je zdrojová hlavička
  starší), `contract-shape.tests.ps1` (31; jádro do 800 řádků a nese
  `Contract-Version`, každé jméno sekce citované kdekoli v `ums/` existuje
  právě v jednom souboru jádra nebo referencí, každá reference má konzumenta
  v banneru skillu nebo overlaye, bannery overlaye SDD a `executing-plans`
  citují stejnou množinu referencí, žádný relativní odkaz ve `shared/` nemíří
  mimo kořen skillů, eskalační dno a Fail-Closed STOPy jsou v jádře, jádro
  nenese značky dokladu ani verzní preambuli), `integration-base.tests.ps1`
  (19; `Test-UmsIntegrationBase` — `Kind` `protected`/`epic-line`/`none`,
  chráněná větev vyhrává nad vzorem epiku, prázdný vzor nedává žádnou linii,
  vadný vzor je neshoda a je jmenovitě nahlášený),
  `contract-move.tests.ps1` (9; `Test-UmsContractMove` — multiset řádků mezi
  zdrojem a cílem přesunu, ztracený řádek i nepovolený nový řádek shazují
  verdikt, vzor `verify-deletion-only.ps1`), `permalink.tests.ps1` (9;
  `Get-UmsPermalink` — šablona s `{sha}`/`{path}`, odvození z hostu
  `github.com`/`bitbucket.org`, neznámý host i krátké SHA i cesta s `..`
  jsou odmítnuté), `jira-description.tests.ps1` (8; `Test-UmsJiraDescription`
  — rozpočet 2 500 znaků, tvar odkazů, tučné × code span, `-RequireSections`
  jen pro popis tiketu, ne pro komentář), `playbook-parse.tests.ps1` (47;
  `Read-UmsPlaybook` — všechny tři tvary položek monorepa (tučně uvozené
  odrážky, položka pod nadpisem, prozaický odstavec se seznamem pravidel),
  části a sekce, ráčnový komentář), `playbook-shape.tests.ps1` (29;
  `Test-UmsPlaybookShape`/`Test-UmsPlaybookTree` — tvar nového formátu,
  rozpočet souboru/sekce/položky jako varování, tři tvrdé nálezy — porušení
  tvaru, růst nad ráčnu bez zaznamenaného rozhodnutí, soubor nad prahem bez
  ráčnového komentáře — a legacy soubor jen s varováním), `playbook-chain.tests.ps1`
  (36; `Get-UmsMbTree`/`Get-UmsPlaybookChain -Out`/`Get-UmsMbLowestCommonAncestor`
  — strom jen z trackovaných playbooků, git-ignorovaná a vnořená `memory-bank/`
  vyloučené, řetězec nese jen podstromovou část předků), `playbook-match.tests.ps1`
  (7; `Find-UmsPlaybookMatch` — shoda jen podle identifikátorů v backticks,
  nejvýš tři kandidáti) proti fixturám `new-playbook-fixture.ps1` (kořen,
  mezilehlá MB s oběma částmi, dva listy, sourozenecký shluk bez společného
  předka pod kořenem), a `tests-hygiene.tests.ps1` (79; grep nad
  `ums/**/tests/*.tests.ps1` — každý volaný `Assert-*` existuje v sesterském
  `_assert.ps1` nebo v `.ps1` vlastního adresáře, a každá sada, která
  dot-sourcuje svůj předmět, nastavuje `$ErrorActionPreference = 'Stop'`).
- [`mb-playbook-consolidate/tests/`](../ums/.claude/skills/mb-playbook-consolidate/tests/)
  — `consolidate.tests.ps1` (84; `consolidate-playbook.ps1` — `-Parse` všech
  tří tvarů, `-Apply` podle schválených rozhodnutí (`novy`/`prepsat`/`vyradit`/
  `prevest-na-test`) s kontrolou, že neschválené položky zůstávají doslova,
  `-Baseline`, `-Resume` odvozený z trailerů `Playbook-Consolidation:
  <běh>/<dávka>` v `git log`, `-Stats`, `-Tree`) s vlastním `_assert.ps1`.
- [`hooks/tests/`](../ums/.claude/hooks/tests/) — `contract-inject.tests.ps1`
  (90; platný JSON i jako surové bajty z dítěte bez okna (striktní parser,
  čisté ASCII, ne-ASCII text jádra přežije), doručení po dílech (reálné jádro
  ve více dílech pod stropem 10 000 znaků, spojené díly = celý payload,
  kapacita při bajtovém stropu, neřezatelný řádek → fallback, marker po
  kompaktaci na díl, registrace `-Part 1..N`), jádro přítomné celé, blok `NOW` jen s ledgerem slugu
  z pinu a jen v uzavřeném tvaru, ledger nalezený podle markeru `plan-path`
  (včetně dvou Memory Bank se stejným basename plánu, dvojznačnosti dvou
  nárokujících adresářů a msys tvaru cesty), pokyn po kompaktaci o
  oříznutém těle skillu, chybějící jádro i mez 48 kB dávají fallback
  pokyn ke čtení, chybějící `context.md` nezastaví injektáž jádra, znaková
  třída odmítá formátovací znaky, `PostCompact` zapíše marker a vrátí
  `systemMessage`, `UserPromptSubmit` s markerem vloží jádro a marker smaže,
  bez markeru mlčí, varování při rozchodu nasazené a zdrojové kopie jádra),
  `pre-push.tests.ps1` (255;
  end-to-end proti skutečnému lokálnímu bare remote: marker `MB_AGENT_SESSION`
  jako vstupní brána, obsahové pravidlo fast-forwardu na už dosažitelný tip,
  lidská výjimka `MB_HUMAN_PUSH`/zastaralé `UMS_ALLOW_SHARED_PUSH`,
  mazání/force i s ní zamítnuté, bufferovací rameno nad markerem, chaining
  cizího hooku (`run_chained`) i jeho čtyři odmítnuté případy,
  `core.hooksPath` lokální/globální/relativní per worktree, generovaný
  seznam chráněných větví a self-test instalátoru včetně důvodů přeskočení,
  obnova ztraceného Git LFS `pre-push` řetězu (`Restore-LfsChainedHook`) včetně
  výjimky `Move-ForeignHook` pro řetěz nesoucí vlastní provenienční stopu;
  běží přes dvě minuty, což je normální), `guard-git-push.tests.ps1` (369;
  JSON na stdin → rozhodnutí podle aktéra a fail-closed čtení cíle: chráněné
  větve včetně integračního fast-forwardu, push do epikové linie posuzovaný
  jako do kterékoli nechráněné větve (žádná výjimka), force, `--no-verify`, obě jména
  únikové proměnné v POSIX i PowerShellovém zápisu, přesměrování krokovaná
  jako v reálném shellu, pojmenované mezery jako `bash -c` nebo git alias) a
  `sync-marker.tests.ps1` (61; `Set-AgentMarker` per harness — Codex
  `config.toml`, Gemini a Qwen `.env`, plugin OpenCode, Hermes `env_passthrough`
  jen v profilu, Pi bez zápisu; harnessy bez mechanismu hlásí
  `NotSupportedException` a nezapisují nic) a `session-intent.tests.ps1` (136; čtenář session intent
  batonu — uzavřený formát s re-renderem, branch a slug guard
  case-sensitive, existence `Plan`, věk bez tvrdé expirace, consume-on-read
  vč. replay okna mezi emisí a přejmenováním, čtyři regresní zámky
  (chybějící/prázdný soubor, zamčený soubor, cizí git repozitář) odlišené od
  pozitivní kontroly, shapová kontrola registrace v `settings.json`, a od
  UMS-3488 navíc `initialUserMessage` vedle `additionalContext` na happy
  path i jeho nepřítomnost na stale cestě (A1), a `Instruction` jako povinný
  a validovaný klíč — chybějící, nejmenující žádný skill nebo nad stropem
  200 znaků dělá baton stale, prázdný nebo nečitelný seznam skillů je
  fail-closed (A2)).

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
  `.agents/` je naproti tomu **trackovaný upstream adresář**
  (`.agents/plugins/marketplace.json`), takže nasazené `.agents/skills/` neskrývá
  žádný `.gitignore`, jen `.git/info/exclude` tohoto klonu — zapisuje ho
  `sync-with-monorepo.ps1 -Scope Fork` (idempotentně, jen adresáře, které git
  dosud neignoruje); bez něj by `git status --porcelain` nebyl prázdný a
  vstupní brána i base sync by stály na „špinavém stromu".
- **`bash` na tomto stroji může být tichý past.** Prosté `bash` v PATH může
  resolvnout na WSL launcher stub místo Git Bash — ten potichu zahodí
  poziční argumenty a běží nad jiným filesystémem. `install-git-hooks.ps1`
  proto Git Bash hledá explicitně (`bin\bash.exe`/`usr\bin\bash.exe` vedle
  `git.exe`), nikdy přes `bash` z PATH. WSL `bash` z PATH navíc nečte absolutní
  windowsovou cestu (`C:/…`) — skript předaný takovou cestou z pwsh skončí
  exit 127 — a v linked worktree nepřečte windowsový `gitdir` v souboru `.git`
  (`fatal: not a git repository`, exit 128). `revendor-superpowers.ps1` proto
  spouští funkční test `sdd-workspace` pod Git Bash z instalace gitu
  (`Resolve-UmsGitBash`: `<Git>\bin\bash.exe` vedle `<Git>\cmd\git.exe`); bez
  Git Bash na Windows test ohlášeně přeskočí.
- **`sdd-workspace` pod Git Bash zapíše do markeru `plan-path` absolutní msys
  cestu** (`/c/Users/…`), ne windowsovou (`C:/…`). Kdo marker čte, musí
  akceptovat oba tvary; test `contract-inject.tests.ps1` proto pokrývá i msys
  tvar.
- **`git check-ignore` na neexistující cestu ji bere jako soubor**, takže vzor
  jen pro adresář (`dir/`) na ni neplatí. Zda git adresář ignoruje, ověřuje
  `Get-UmsForkExcludes` sondou uvnitř něj (`<dir>/.ums-probe`).
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
- **Výkon `doc-index.ps1` je změřený v obou měřítkách, a číslo vždy patří k
  počtu refů, při kterém vzniklo.** V tomto forku (4 refy pod
  `refs/remotes/origin/`) trvá běh 2,0 s s `-NoFetch` a 3,0 s včetně
  `git fetch`. Proti monorepu UMS (**337** vzdálených větví, `.git` 4,4 GB)
  trvá běh s `-NoFetch` a defaultním oknem 30 dní **103–107 s** a běh s
  deklarovaným záměrem **~160 s**. Rozpočet z návrhu (do 15 s) splněný není.
  Starší měření téhož dokumentu (32–35 s a 57 s) vzniklo při **219** refech a
  neplatí pro dnešní velikost repa — rozdíl je růstem repozitáře, ne regresí
  kódu; ověřeno záměnou verzí těsně po sobě.
  Čtení refů ani traverzace nejsou úzké místo (`for-each-ref` 219 refů 0,10 s,
  `git log --stdin` 0,12 s / 33 commitů). Zbývající cena je **spawn procesu na
  dvojici** (větev, cesta) — `cat-file -e` a pak `show` — plus
  `git branch -r --contains` jednou na commit v okenním traversalu. Refy se do
  `git log` předávají přes `--stdin`, protože stovky jmen refů na příkazové
  řádce míří k 32k limitu Windows.
- **Deklarovaný záměr (`-Jira`/`-Slug`) nerozšiřuje hlavní traversal, má
  vlastní široký průchod.** Odokenění hlavního traversalu bylo příčinou toho,
  že běh na monorepu **nedoběhl vůbec** (přes 25 minut bez výstupu, zabito):
  ten traversal řeší větve commitů jedním `branch -r --contains` **na commit**,
  takže bez okna se počet volání násobí celou historií. Deklarovaný záměr proto
  obsluhuje samostatný průchod — jeden `git log --stdin --source` nad všemi
  refy, omezený na `proposals/active/`, kde `%S` pojmenuje větev, takže
  per-commit řešení větví není potřeba vůbec. Počet procesů je konstantní.
  Průchod je záměrně úzký na `active/`, protože kolizní srovnání jinou fázi
  neporovnává; výstup deklarovaného běhu je proto **nadmnožinou** okenního pro
  `active/` (změřeno: 0 chybí, +7 navíc) a nenese `next/` ani `completed/`
  z uspaných větví. Jediný konzument deklarovaného záměru je kolizní kontrola
  Target-MB discovery; `mb-epic-elaboration` index volá bez záměru, takže jeho
  `-IndexFile` vstup to nezúžilo.
- **Cíl `-Json` se kontroluje před prací, ne až při zápisu.** Zápis na konci
  znamenal, že chybějící adresář nechal vypsat celý normální report a teprve
  pak běh spadl: exit 1, žádný soubor, a volající čtoucí stdout viděl zdravý
  běh. V čerstvém worktree je přitom chybějící `.superpowers/` normální stav —
  vytváří ho workflow, ne checkout.
- **Jména refů se v `doc-index.ps1` vrací zpátky do gitu, takže musí přežít
  round trip přes PowerShell.** `git for-each-ref` tiskne jméno větve jako
  surové UTF-8 a to, co z něj PowerShell dekóduje, přesně to pošle na stdin
  `git log --stdin`. Bez `[Console]::OutputEncoding = UTF8` (dekódovací strana,
  ta nese váhu; `$OutputEncoding` je pojistka na kódovací straně) skončí větev
  s diakritikou jako `fatal: bad revision` a celý index spadne na exit 1.
  Monorepo takové větve reálně má (`origin/UMS-1646-mobilní-klient-pro-alarminfo`),
  fixture repo testů je proto taky má.
- **`consolidate-playbook.ps1 -Apply` v režimu patch (legacy soubor v místě)
  přepíše CRLF pracovní strom na LF**, i beze změny obsahu mimo dotčené
  položky: parser (`Read-UmsPlaybook.ps1`) při čtení odstraňuje `\r`
  (`-replace "` r`n", "` n"`) a zapisovatel skládá řádky zpátky jen s `` `n ``,
  takže výsledný soubor je čistě LF bez ohledu na to, jaké konce řádků měl
  předtím. S `core.autocrlf=true` to git při `git add` normalizuje zpátky —
  relevantní zvlášť pro běh nad monorepem, kde `core.autocrlf` bývá zapnuté
  a playbooky dosud nemají `text eol=lf` v `.gitattributes`.
- **PowerShell hook pod Claude Code na Windows píše stdout v OEM kódové
  stránce (852), ne v UTF-8.** Harness spouští hook bez okna, `pwsh` dostane
  vlastní konzoli s OEM stránkou a `Write-Output` kóduje podle
  `[Console]::OutputEncoding`. `ConvertTo-Json` ne-ASCII neescapuje, takže
  `→` se zapíše jako bajt 0x1A, `…` jako 0x07 a `„ “` jako holé `"`. Harness
  (Bun) payload odmítne hláškou „Hook output looks like a JSON object but is
  not valid JSON — JSON Parse error: Unterminated string" a sezení začne bez
  jádra kontraktu (1. 10. 2026, Claude Code 2.1.286). Hook proto emituje JSON
  přes `ConvertTo-Json -EscapeHandling EscapeNonAscii` (čisté ASCII, stejné
  v každé stránce). Ruční test `& pwsh … | Out-String` chybu nevidí, protože
  dekóduje stejnou stránkou, jakou dítě kódovalo. Výstup hooku ověřuj jako
  surové bajty z dítěte s `CreateNoWindow` striktním parserem
  (`Invoke-PwshHookRaw` + `Test-StrictHookJson` v `hooks/tests/_assert.ps1`).
