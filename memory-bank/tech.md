# Tech

Ecosystem: dokumentační a skriptový — Markdown (skilly a kontrakt), PowerShell 7
(nástroje vrstvy), Node.js ESM (hooky), Bash (upstream skripty SDD). Žádný
kompilovaný build, žádný package manager pro vrstvu samotnou.

## Verze a piny

| Co | Hodnota | Zdroj |
|---|---|---|
| Superpowers (upstream) | 6.2.0 | [`package.json`](../package.json), [`.claude-plugin/plugin.json`](../.claude-plugin/plugin.json) |
| Vendor pin vrstvy | tag `v6.2.0`, commit `3dcbd5c4b48e02263fbf4a3c01e3fe4f81d584d9`, vendorováno 2026-07-24 | [`VENDORED_FROM.md`](../ums/.claude/skills/shared/VENDORED_FROM.md) |
| Kontrakt Memory Bank | 2.3 | [`UMS_MEMORY_BANK_CONTRACT.md`](../ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md) |
| Vendorované skilly | 14 (`brainstorming`, `dispatching-parallel-agents`, `executing-plans`, `finishing-a-development-branch`, `receiving-code-review`, `requesting-code-review`, `subagent-driven-development`, `systematic-debugging`, `test-driven-development`, `using-git-worktrees`, `using-superpowers`, `verification-before-completion`, `writing-plans`, `writing-skills`) | `VENDORED_FROM.md` |
| Overlay bloky | přesně 3 (`brainstorming`, `subagent-driven-development`, `finishing-a-development-branch`) | [`shared/overlays/`](../ums/.claude/skills/shared/overlays/) |

Prosté textové odkazy na verzi upstreamu jsou na dvou místech vrstvy ještě
o jednu verzi pozadu (`ums/README.md` a úvod `SKILLS_MANIFEST.md` uvádějí
v6.1.1) — normativní je pin ve `VENDORED_FROM.md`.

## Runtime a platforma

- **PowerShell 7** (`#Requires -Version 7`, `$ErrorActionPreference = 'Stop'`) —
  [`sync-with-monorepo.ps1`](../ums/sync-with-monorepo.ps1),
  [`revendor-superpowers.ps1`](../ums/.claude/scripts/revendor-superpowers.ps1),
  [`epic-graph.ps1`](../ums/.claude/skills/mb-epic-graph/scripts/epic-graph.ps1),
  [`ledger-status.ps1`](../ums/.claude/skills/mb-epic-elaboration/scripts/ledger-status.ps1),
  [`doc-index.ps1`](../ums/.claude/skills/mb-doc-index/scripts/doc-index.ps1),
  [`install-git-hooks.ps1`](../ums/.claude/hooks/install-git-hooks.ps1),
  hook `bpmn-validate.ps1`.
- **Node.js** (ESM, `"type": "module"`) — hooks
  [`deny-superpowers-docs.mjs`](../ums/.claude/hooks/deny-superpowers-docs.mjs)
  (čte JSON ze stdin, vrací `permissionDecision: deny`) a
  [`guard-git-push.mjs`](../ums/.claude/hooks/guard-git-push.mjs) (fail-open
  early-warning nad `Bash` voláními, viz níže).
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

- stavy `Design Review` (chybějící přechod = fail-closed stop), `In Progress`,
  `Test`,
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
| `hooks.SessionStart` | `additionalContext`: vyvolat `using-superpowers`, pak přečíst kontrakt a `memory-bank/context.md` |
| `hooks.PostCompact` | `systemMessage`: po kompaktaci znovu načíst kontrakt, `context.md` a při exekuci plánu i `.superpowers/sdd/progress.md` |
| `hooks.PreToolUse` (`Write|Edit`) | `deny-superpowers-docs.mjs` — blokuje zápis do `docs/superpowers/**` a `docs/plans/**` |
| `hooks.PreToolUse` (`Bash`) | `guard-git-push.mjs` — fail-open rychlé varování před pushem do chráněné větve nebo s `--no-verify`; NENÍ záruka, tou je git `pre-push` hook (níže) |
| `hooks.PostToolUse` (`Write|Edit`) | `bpmn-validate.ps1` — validace BPMN v monorepu |
| `permissions.allow` | read-only nástroje (grep, rg, cat, head, tail, ls, wc, diff, sed, find, test, echo; git status/diff/log/show/ls-files/rev-parse/branch/check-ignore/stash list/fetch/ls-remote/for-each-ref/ls-tree/cat-file/merge-base; PowerShell Get-Content/Get-ChildItem/Test-Path/Select-String) |
| `permissions.deny` | `EnterWorktree`, `ExitWorktree`, `Bash(rm -rf:*)`, `Bash(git reset --hard:*)` |
| `skillOverrides` | `using-git-worktrees: off` |
| `worktree.bgIsolation` | `none` |

`git push` už není v `permissions.deny` — je binární a deny vyhrává nad allow,
takže by nešlo rozvolnit jen pro vlastní tiketovou větev. Skutečnou hranicí
dvouúrovňové push policy (kontrakt, Publication Contract) je git `pre-push`
hook [`ums/.claude/hooks/pre-push`](../ums/.claude/hooks/pre-push) (POSIX
`sh`, scope `refs/heads/*`) — git mu předá už rozparsované čtveřice refů, ne
shellový text, takže žádné parsování k obejití neexistuje. Zamítá push do
chráněné větve (`develop`, `main`, `master`, `release/*`) bez
`UMS_ALLOW_SHARED_PUSH=1`, mazání větve a force push vždy. Git hooky jsou
netrackované (`.git/hooks/` nebo cíl `core.hooksPath`), takže je do každého
klonu instaluje samostatný skript
[`install-git-hooks.ps1`](../ums/.claude/hooks/install-git-hooks.ps1) —
idempotentní, cizí hook nikdy nepřepíše, cíl řeší `git rev-parse --git-path
hooks/pre-push` (správně i pro linked worktree). Kdy se spouští a co znamenají
jeho návratové kódy, je v [playbook.md](playbook.md). Konce řádků hooku hlídá
[`ums/.gitattributes`](../ums/.gitattributes) pravidlem `text eol=lf`.

## Testy

Jak se sady spouštějí a jaké konvence platí pro novou sadu, je
v [playbook.md](playbook.md).

**UMS vrstva** — bezzávislostní PowerShell testy vedle skillů, 12 sad, dohromady
388 asercí:

- [`mb-epic-graph/tests/`](../ums/.claude/skills/mb-epic-graph/tests/) —
  `e2e.tests.ps1` (12), `graph-generation.tests.ps1` (27),
  `oracle-prose.tests.ps1` (5), `oracle-structural.tests.ps1` (10),
  `status-glyph.tests.ps1` (78, včetně `-IndexFile` glyfů a findings)
  + fixtures (proposal dokumenty ve starém i novém pojmenování, Jira JSON
  snapshoty, `fixtures/doc-index/*.json`).
- [`mb-epic-elaboration/tests/`](../ums/.claude/skills/mb-epic-elaboration/tests/) —
  `ledger-status.tests.ps1` (9) + fixtures.
- [`mb-doc-index/tests/`](../ums/.claude/skills/mb-doc-index/tests/) —
  `enumeration.tests.ps1` (20; traversal, lokální sken, `-SinceDays`/`-BaseRef`,
  filtrování `tests/fixtures`), `findings.tests.ps1` (28; kolize, self-kolize
  vlastní pushnuté větve, fronta na více větvích, obživlá fronta) proti
  fixture repu generovanému `new-fixture-repo.ps1`.
- [`mb-migrate-docs/tests/`](../ums/.claude/skills/mb-migrate-docs/tests/) —
  `migrate.tests.ps1` (37; plán i `-Apply` mechanické migrace — sloučení
  `product.md` do `brief.md`, přejmenování `tasks.md` na `playbook.md`,
  přepis relativních odkazů v migrovaném stromu, přeskočení MB s
  `KONFLIKT PLAYBOOKU`), `verify.tests.ps1` (38; mazací režim
  `verify-deletion-only.ps1` — multiset-containment kontrola nad řádky,
  `VAROVÁNÍ` při ubrání přes 50 % neprázdných řádků) proti fixture repu
  generovanému `new-fixture-repo.ps1`.
- [`hooks/tests/`](../ums/.claude/hooks/tests/) — `pre-push.tests.ps1` (74;
  end-to-end proti skutečnému lokálnímu bare remote: lidská výjimka,
  mazání/force i s ní zamítnuté, `core.hooksPath` lokální/globální/relativní
  per worktree) a `guard-git-push.tests.ps1` (50; JSON na stdin → rozhodnutí:
  chráněné větve, force, `--no-verify`, lidská výjimka).

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
  varování a potřebuje samostatný běh pro každý worktree. Dvoukolový
  self-test instalátoru navíc musí porovnávat case-sensitive marker
  (`-cmatch 'UMS: '`), ne substring `-match 'UMS'` — ten by broken hook,
  jehož chybová hláška jen cituje vlastní cestu, vyhodnotil jako ověřený
  v každém repozitáři ležícím pod adresářem se jménem obsahujícím „ums".
- **`git branch --show-current` vrací i jméno nenarozené větve** (repo bez
  jediného commitu) — cestu „nejde určit aktuální větev" tak reálně
  vyzkouší jen detached HEAD, ne čerstvě inicializovaný repozitář.
- **Výkon `doc-index.ps1` je ověřený jen v malém měřítku.** V tomto forku má
  `origin` 3 větve a běh trvá cca 1–2 s; očekávaný rozpočet z návrhu (do 15 s
  při stovkách vzdálených větví cílového monorepa) touto větví ověřen není.
