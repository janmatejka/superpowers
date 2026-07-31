# Tech

Ecosystem: dokumentační a skriptový — Markdown (skilly a kontrakt), PowerShell 7
(nástroje vrstvy), Node.js ESM (hooky), Bash (upstream skripty SDD). Žádný
kompilovaný build, žádný package manager pro vrstvu samotnou.

## Verze a piny

| Co | Hodnota | Zdroj |
|---|---|---|
| Superpowers (upstream) | 6.2.0 | [`package.json`](../package.json), [`.claude-plugin/plugin.json`](../.claude-plugin/plugin.json) |
| Vendor pin vrstvy | tag `v6.2.0`, commit `3dcbd5c4b48e02263fbf4a3c01e3fe4f81d584d9`, vendorováno 2026-07-24 | [`VENDORED_FROM.md`](../ums/.claude/skills/shared/VENDORED_FROM.md) |
| Kontrakt Memory Bank | 2.1 | [`UMS_MEMORY_BANK_CONTRACT.md`](../ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md) |
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
  hook `bpmn-validate.ps1`.
- **Node.js** (ESM, `"type": "module"`) — hook
  [`deny-superpowers-docs.mjs`](../ums/.claude/hooks/deny-superpowers-docs.mjs)
  čte JSON ze stdin a vrací `permissionDecision: deny`.
- **Git Bash** — upstream skripty SDD (`sdd-workspace`, `task-brief`,
  `review-package`) jsou bashové soubory bez přípony.
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
lepidlo (deployuje se jen na cíl `claude`, nikdy na jiné harnessy — přepsalo by
jim vlastní `settings.json`):

| Klíč | Obsah |
|---|---|
| `hooks.SessionStart` | `additionalContext`: vyvolat `using-superpowers`, pak přečíst kontrakt a `memory-bank/context.md` |
| `hooks.PostCompact` | `systemMessage`: po kompaktaci znovu načíst kontrakt, `context.md` a při exekuci plánu i `.superpowers/sdd/progress.md` |
| `hooks.PreToolUse` (`Write|Edit`) | `deny-superpowers-docs.mjs` — blokuje zápis do `docs/superpowers/**` a `docs/plans/**` |
| `hooks.PostToolUse` (`Write|Edit`) | `bpmn-validate.ps1` — validace BPMN v monorepu |
| `permissions.allow` | read-only nástroje (grep, rg, cat, head, tail, ls, wc, diff, sed, find, test, echo; git status/diff/log/show/ls-files/rev-parse/branch/check-ignore/stash list; PowerShell Get-Content/Get-ChildItem/Test-Path/Select-String) |
| `permissions.deny` | `EnterWorktree`, `ExitWorktree`, `Bash(rm -rf:*)`, `Bash(git reset --hard:*)`, `Bash(git push:*)` |
| `skillOverrides` | `using-git-worktrees: off` |
| `worktree.bgIsolation` | `none` |

## Testy

**UMS vrstva** — bezzávislostní PowerShell testy vedle skillů:

- [`mb-epic-graph/tests/`](../ums/.claude/skills/mb-epic-graph/tests/) —
  `e2e.tests.ps1`, `graph-generation.tests.ps1`, `oracle-prose.tests.ps1`,
  `oracle-structural.tests.ps1`, `status-glyph.tests.ps1` + fixtures (proposal
  dokumenty ve starém i novém pojmenování, Jira JSON snapshoty).
- [`mb-epic-elaboration/tests/`](../ums/.claude/skills/mb-epic-elaboration/tests/) —
  `ledger-status.tests.ps1` + fixtures.
- Sdílený helper `_assert.ps1` (`Assert-True`, `Assert-Match`,
  `Assert-NotMatch`, `Assert-Eq`, `Complete-Tests`) — žádný Pester, nenulový
  exit kód při selhání.

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
- **CRLF a `git archive`.** Vendoring přes `git archive` při
  `core.autocrlf=true` rozbije bashové skripty bez přípony. Revendor skript
  proto normalizuje na LF a v monorepu platí `.gitattributes` s
  `.claude/skills/** text eol=lf`. Verifikační pass revendoru CRLF kontroluje
  a navíc funkčně testuje SDD skripty v Git Bash.
- **Anchor miss při aplikaci overlaye je detektor driftu upstreamu**, ne chyba
  k obejití — `ANCHOR-BEFORE` musí matchovat právě jeden řádek cílového souboru.
- Verifikace revendoru padá i na viselých relativních odkazech, zbytcích v5
  souborů, chybějících v6 souborech a nevyvážených overlay markerech.
