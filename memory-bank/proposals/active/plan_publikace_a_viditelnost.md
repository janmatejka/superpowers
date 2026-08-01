# Publikace a viditelnost dokumentů napříč větvemi — implementační plán

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

- **Jira:** (žádný tiket)
- **Návrh:** [design_publikace_a_viditelnost.md](design_publikace_a_viditelnost.md)
- **Target MB:** memory-bank/

**Goal:** Aby agenti a lidé pracující v samostatných clonech na tiketech jednoho epiku o sobě věděli — dokumenty se hledají na `origin` napříč větvemi a každý zveřejněný odkaz na git objekt je v okamžiku zveřejnění dosažitelný.

**Architecture:** Model tahu. Nový read-only skript `doc-index.ps1` sestaví z remote refů index dokumentů (`next`/`active`/`completed`) jedním traversalem `git log --remotes --not <BaseRef>` a vydá českou tabulku i JSON. Konzumenti (Target-MB discovery, `mb-epic-elaboration`, `mb-epic-graph`, `mb-state`) index čtou; publikaci vlastní tiketové větve povoluje nový PreToolUse hook, který zároveň brání pushům do chráněných větví.

**Tech Stack:** PowerShell 7 (skripty a testy), Node.js ESM (hook), Markdown (kontrakt, skilly, overlaye), git plumbing (`log --remotes`, `branch -r --contains`, `cat-file`, `show`, `ls-tree`).

## Global Constraints

- Všechny změny výhradně v `ums/` (aditivní model větve `ums-memory-bank`); MB dokumenty v `memory-bank/`. NIKDY needitovat `skills/`, `hooks/`, `tests/`, `docs/` v kořeni — to je upstream.
- Jazyk: těla skillů, kód, komentáře a AI-facing text **anglicky**; výstupy skriptů, findings, zprávy hooku, commit messages a MB dokumenty **česky**.
- PowerShell skripty: `#Requires -Version 7`, `Set-StrictMode -Version Latest`, `$ErrorActionPreference = 'Stop'`, `try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }`, exit kódy `0` OK / `1` chyba vstupu nebo skriptu / `2` nalezené kolize.
- Node hooky: ESM `.mjs`, čtou JSON ze stdin, **vždy** `process.exit(0)`, zamítnutí přes `hookSpecificOutput.permissionDecision = 'deny'`.
- Testy: žádný Pester, vlastní kopie `_assert.ps1` v `tests/` daného skillu, nenulový exit kód při selhání, **žádná síť** (fixture = lokální bare repo).
- Přesně **tři** overlay bloky (`brainstorming`, `subagent-driven-development`, `finishing-a-development-branch`) — čtvrtý nezavádět.
- Chráněné větve: `develop`, `main`, `master`, `release/*`.
- Výchozí base ref skriptu: `origin/develop`; v tomto forku se používá `origin/ums-memory-bank`.
- Commity: prefix `UMS:` (konvence repa), česky, detailní řádky začínají ` - `. Scoped staging — vyjmenovat cesty, nikdy `git add -A`.

---

### Task 1: Publikační invariant v kontraktu

**Files:**
- Modify: `ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md` (nová sekce před `## Architect Review Gate`; úpravy v `## Target-MB Discovery & Pinning`; zkrácení `**Push policy:**` v Architect Review Gate)

**Interfaces:**
- Consumes: nic (první task).
- Produces: normativní text, na který odkazují všechny další tasky — názvy sekcí `## Publication Contract` a `## Cross-Branch Visibility`, pojmy `Publication points`, `meziclonová kolizní kontrola`, `chráněné větve`.

- [ ] **Step 1: Přečti dotčené sekce kontraktu**

Přečti `## Target-MB Discovery & Pinning` (kroky 1–10), `## Architect Review Gate` (odstavec `**Push policy:**`) a `## Fail-Closed Behavior`. Ověř, že verze v hlavičce je `2.1`.

- [ ] **Step 2: Zvyš verzi kontraktu na 2.2**

Nahraď v hlavičce:

```markdown
- **Contract-Version:** 2.2
- Supersedes v2.1 (adds the Publication Contract and Cross-Branch Visibility
  sections and the two-tier push policy). v2.0 renamed the document pair to
  `design_`/`plan_` and added the Architect Review Gate; v1
  (mb-plan/mb-act orchestration) remains superseded.
  See `VENDORED_FROM.md` for the vendored Superpowers version.
```

- [ ] **Step 3: Vlož sekci `## Publication Contract` přímo před `## Architect Review Gate`**

```markdown
## Publication Contract

**No reference without reachability.** Whenever the workflow names a git object
outside this clone — a link in a ticket description or comment, a wave table, a
handoff comment, a link in an epic ledger — the pinned commit MUST be reachable
on `origin` at that moment. Verify mechanically:

```bash
git fetch origin
git branch -r --contains <sha>     # empty result = not on origin
```

An unreachable commit is a fail-closed STOP with an offer to publish, never a
warning.

**Publication points** (when the actor's own branch is pushed):

1. after the design document is written and committed (brainstorming),
2. after the implementation plan is written and committed (before the first task
   dispatch),
3. at elaboration window closure, BEFORE writing links into Jira,
4. before every handoff (design review request/respond is the reference
   implementation).

**Two-tier push policy:**

| Tier | Rule |
|---|---|
| The actor's own ticket branch (unprotected) | The agent pushes it itself, without asking, but ALWAYS announces the branch and the outgoing commits. Force push is forbidden. |
| Shared branches (`develop`, `main`, `master`, `release/*`) | The agent NEVER pushes. It prepares the exact command with the outgoing commits and the user approves or runs it (in-session: `! git push origin develop`). The agent then re-verifies reachability. |

Mechanically enforced by a git `pre-push` hook installed per clone (it rejects a
protected destination ref, a deletion and a non-fast-forward); the Claude Code
PreToolUse hook `.claude/hooks/guard-git-push.mjs` is only a fast early warning
and lets through what it cannot parse. Other harnesses rely on the pre-push hook
and on contract text, as with every other rule of this layer.
(This paragraph was rewritten during Task 4 fix rounds 2–3 — the original
"protected-ref deny-list" wording described a mechanism that two adversarial
reviews defeated against a real remote; see the design document, section 2.) `mb-git-commit` never pushes — publication is a
workflow step at the points listed above, not a commit tool.
```

- [ ] **Step 4: Vlož sekci `## Cross-Branch Visibility` hned za `## Publication Contract`**

```markdown
## Cross-Branch Visibility

Documents are never pushed into a shared branch to make them visible; they are
**pulled** — discovered on `origin` across branches by the `mb-doc-index` skill
(read-only). Rules:

- Discovery candidates are the union of the local working tree and the document
  index over `origin`.
- **Taking over a draft from a foreign branch** is a blob copy
  (`git show <ref>:<path> > <path>`), never a cherry-pick — an elaboration
  window closes with ONE commit carrying the ledger, the graph and all of the
  window's proposals, so a cherry-pick would drag in a foreign ledger. The
  taken-over design document records `**Převzato z:** <branch>@<sha>`.
- **A ticket branch is created from the CURRENT base ref** (fetch +
  fast-forward), otherwise it cannot see already-merged planning.
- **Resurrected queue:** after a takeover the original may still sit in `next/`
  on the source branch and reappear in the base when that branch merges. This is
  detected (`mb-doc-index`, `mb-epic-graph -Check`), not prevented; the cleanup
  is one `git rm` by whoever sees the finding.
```

- [ ] **Step 5: Zkrať `**Push policy:**` v Architect Review Gate na odkaz**

Nahraď stávající odstavec (začíná `**Push policy:** NEVER push silently.`) tímto:

```markdown
**Push policy:** per the Publication Contract — the ticket branch is the actor's
own branch, so the handoff push is announced, not negotiated; shared branches are
never pushed by the agent. Steps are ordered so one handoff needs exactly one
push.
```

- [ ] **Step 6: Rozšiř `## Target-MB Discovery & Pinning`**

V kroku 1 nahraď text za `Scan` tak, aby zněl:

```markdown
1. Scan `**/memory-bank/proposals/active/` for `{design_,plan_,proposal_}*.md`
   under `<MB_ROOT>`, then run the `mb-doc-index` skill and take the candidate
   set as the UNION of the local scan and the index over `origin`.
```

V kroku 6 (preliminary-queue activation) doplň na konec:

```markdown
   The queued draft may live on a foreign branch — the index reports it. Take it
   over by blob copy per Cross-Branch Visibility (never cherry-pick) and record
   `**Převzato z:** <branch>@<sha>` in its header.
```

V kroku 8 doplň druhý odstavec:

```markdown
   The two-actives guard stays LOCAL (one active work item per clone, because
   `context.md` holds one pin); extending it to `origin` would forbid parallel
   work across the team. Alongside it runs the **cross-clone collision check**:
   the SAME slug or the SAME Jira ticket active on a foreign branch is a
   fail-closed STOP (double work), and the report carries the branch and the last
   commit date so the user can tell an abandoned branch from live work. Foreign
   active slugs of OTHER tickets are normal parallel operation — list them, never
   stop.
```

- [ ] **Step 7: Doplň fail-closed výčet**

V `## Fail-Closed Behavior` přidej do seznamu hard failures: `an unreachable pinned commit at publication time; the same slug or ticket active on a foreign branch`.

- [ ] **Step 8: Ověř konzistenci**

```bash
grep -n "NEVER push silently" ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md
grep -n "Publication Contract\|Cross-Branch Visibility" ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md
```
Expected: první grep nic (starý absolutní zákaz zmizel), druhý vypíše nové sekce + odkaz z Architect Review Gate.

- [ ] **Step 9: Commit**

```bash
git add ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md
git commit -m "UMS: kontrakt 2.2 — publikační invariant a viditelnost napříč větvemi"
```

---

### Task 2: `doc-index.ps1` — enumerace, JSON, filtry

**Files:**
- Create: `ums/.claude/skills/mb-doc-index/scripts/doc-index.ps1`
- Create: `ums/.claude/skills/mb-doc-index/tests/_assert.ps1` (kopie z `ums/.claude/skills/mb-epic-graph/tests/_assert.ps1`, bez funkce `Invoke-Graph`, s `Invoke-Index`)
- Create: `ums/.claude/skills/mb-doc-index/tests/new-fixture-repo.ps1`
- Create: `ums/.claude/skills/mb-doc-index/tests/enumeration.tests.ps1`

**Interfaces:**
- Consumes: pojmy z Tasku 1 (`Cross-Branch Visibility`).
- Produces: skript `doc-index.ps1` s parametry `-RepoPath`, `-BaseRef` (default `origin/develop`), `-SinceDays` (default 120), `-BranchGlob`, `-Json <path>`, `-NoFetch`; JSON tvaru `{ base, generated, entries: [{ slug, jira, phase, path, branch, commit, date, author }], findings: [{ code, severity, message }] }`; helper `New-FixtureRepo` vracející hashtable `@{ Work=<cesta ke clonu>; Origin=<cesta k bare repu> }`.

- [ ] **Step 1: Napiš fixture builder**

`tests/new-fixture-repo.ps1`:

```powershell
# Builds an offline fixture: a bare "origin" plus a clone with several branches
# carrying Memory Bank documents. Returns @{ Work=<path>; Origin=<path> }.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-Git([string] $RepoDir, [string[]] $GitArgs) {
    $out = & git -C $RepoDir -c user.name=Test -c user.email=test@example.com @GitArgs 2>&1
    if ($LASTEXITCODE -ne 0) { throw "git $($GitArgs -join ' ') failed: $out" }
    return $out
}

function Add-Doc([string] $RepoDir, [string] $RelPath, [string] $Jira) {
    $full = Join-Path $RepoDir $RelPath
    New-Item -ItemType Directory -Force -Path (Split-Path $full) | Out-Null
    Set-Content -LiteralPath $full -Encoding UTF8 -Value @(
        "# Návrh: $([IO.Path]::GetFileNameWithoutExtension($RelPath))"
        ""
        "- **Jira:** $Jira"
        "- **Target MB:** memory-bank/"
    )
    Invoke-Git $RepoDir @('add', $RelPath)
}

function New-FixtureRepo {
    $root = Join-Path ([IO.Path]::GetTempPath()) ("mbidx-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $origin = Join-Path $root 'origin.git'
    $work = Join-Path $root 'work'
    New-Item -ItemType Directory -Force -Path $origin, $work | Out-Null
    & git init --bare -b develop $origin | Out-Null
    & git init -b develop $work | Out-Null
    Invoke-Git $work @('remote', 'add', 'origin', $origin)

    # base: one completed document
    Add-Doc $work 'memory-bank/proposals/completed/design_hotovo.md' 'UMS-0'
    Invoke-Git $work @('commit', '-m', 'base')
    Invoke-Git $work @('push', '-u', 'origin', 'develop')

    # active work item on a foreign branch
    Invoke-Git $work @('checkout', '-b', 'feature/ums-1-alfa', 'develop')
    Add-Doc $work 'memory-bank/proposals/active/design_ums_1_alfa.md' 'UMS-1'
    Invoke-Git $work @('commit', '-m', 'alfa')
    Invoke-Git $work @('push', 'origin', 'feature/ums-1-alfa')

    # the same queued draft on two branches
    foreach ($b in @('feature/ums-2-beta', 'feature/ums-2-beta-dup')) {
        Invoke-Git $work @('checkout', '-b', $b, 'develop')
        Add-Doc $work 'memory-bank/proposals/next/design_ums_2_beta.md' 'UMS-2'
        Invoke-Git $work @('commit', '-m', "beta on $b")
        Invoke-Git $work @('push', 'origin', $b)
    }

    # queued on one branch, completed on another
    Invoke-Git $work @('checkout', '-b', 'feature/ums-3-gama', 'develop')
    Add-Doc $work 'memory-bank/proposals/next/design_ums_3_gama.md' 'UMS-3'
    Invoke-Git $work @('commit', '-m', 'gama next')
    Invoke-Git $work @('push', 'origin', 'feature/ums-3-gama')
    Invoke-Git $work @('checkout', '-b', 'feature/ums-3-gama-done', 'develop')
    Add-Doc $work 'memory-bank/proposals/completed/design_ums_3_gama.md' 'UMS-3'
    Invoke-Git $work @('commit', '-m', 'gama done')
    Invoke-Git $work @('push', 'origin', 'feature/ums-3-gama-done')

    # test fixture path -> must be excluded from the index
    Invoke-Git $work @('checkout', '-b', 'feature/ums-4-fixture', 'develop')
    Add-Doc $work 'ums/.claude/skills/x/tests/fixtures/memory-bank/proposals/active/design_fixture.md' 'UMS-4'
    Invoke-Git $work @('commit', '-m', 'fixture doc')
    Invoke-Git $work @('push', 'origin', 'feature/ums-4-fixture')

    # stale branch (2 years old) -> excluded by default -SinceDays
    Invoke-Git $work @('checkout', '-b', 'feature/ums-5-stare', 'develop')
    Add-Doc $work 'memory-bank/proposals/next/design_ums_5_stare.md' 'UMS-5'
    $old = (Get-Date).AddYears(-2).ToString('yyyy-MM-ddTHH:mm:ss')
    $env:GIT_AUTHOR_DATE = $old; $env:GIT_COMMITTER_DATE = $old
    Invoke-Git $work @('commit', '-m', 'stare')
    Remove-Item Env:GIT_AUTHOR_DATE, Env:GIT_COMMITTER_DATE
    Invoke-Git $work @('push', 'origin', 'feature/ums-5-stare')

    Invoke-Git $work @('checkout', 'develop')
    return @{ Work = $work; Origin = $origin }
}
```

- [ ] **Step 2: Napiš `_assert.ps1` pro tento skill**

Zkopíruj `ums/.claude/skills/mb-epic-graph/tests/_assert.ps1`, funkci `Invoke-Graph` nahraď:

```powershell
# Runs doc-index.ps1 out-of-process; returns @{ Out=<stdout>; Code=<exit code> }.
function Invoke-Index([string[]] $ScriptArgs) {
    $script = Join-Path $PSScriptRoot '..\scripts\doc-index.ps1'
    try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
    $out = & pwsh -NoProfile -File $script @ScriptArgs 2>&1 | Out-String
    return @{ Out = $out; Code = $LASTEXITCODE }
}
```

- [ ] **Step 3: Napiš padající test enumerace**

`tests/enumeration.tests.ps1`:

```powershell
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '_assert.ps1')
. (Join-Path $PSScriptRoot 'new-fixture-repo.ps1')

$fx = New-FixtureRepo
$json = Join-Path $fx.Work 'index.json'
$r = Invoke-Index @('-RepoPath', $fx.Work, '-BaseRef', 'origin/develop', '-NoFetch', '-Json', $json)

Assert-Eq $r.Code 0 'čistý běh bez kolizí končí kódem 0'
Assert-Match $r.Out 'ums_1_alfa' 'tabulka obsahuje aktivní slug z cizí větve'
Assert-Match $r.Out 'origin/feature/ums-1-alfa' 'tabulka uvádí větev, která slug drží'
Assert-NotMatch $r.Out 'design_fixture' 'cesty pod tests/fixtures/ se vylučují'
Assert-NotMatch $r.Out 'ums_5_stare' 'commit starší než -SinceDays se nezapočítá'
Assert-NotMatch $r.Out 'design_hotovo' 'dokončené dokumenty z báze nejsou v tabulce'

$idx = Get-Content -LiteralPath $json -Raw | ConvertFrom-Json
$alfa = @($idx.entries | Where-Object { $_.slug -eq 'ums_1_alfa' })[0]
Assert-Eq $alfa.phase 'active' 'fáze se určuje z cesty'
Assert-Eq $alfa.jira 'UMS-1' 'tiket se čte z hlavičky dokumentu'
Assert-True ($alfa.commit.Length -ge 7) 'záznam nese commit SHA'
Assert-Eq $idx.base 'origin/develop' 'JSON nese použitou bázi'

$stare = Invoke-Index @('-RepoPath', $fx.Work, '-BaseRef', 'origin/develop', '-NoFetch', '-SinceDays', '1000')
Assert-Match $stare.Out 'ums_5_stare' 'vyšší -SinceDays starou větev zahrne'

$glob = Invoke-Index @('-RepoPath', $fx.Work, '-BaseRef', 'origin/develop', '-NoFetch', '-BranchGlob', 'origin/feature/ums-1-*')
Assert-Match $glob.Out 'ums_1_alfa' '-BranchGlob propustí odpovídající větev'
Assert-NotMatch $glob.Out 'ums_2_beta' '-BranchGlob odfiltruje ostatní větve'

Remove-Item -Recurse -Force (Split-Path $fx.Work)
Complete-Tests
```

- [ ] **Step 4: Spusť test a ověř, že padá**

Run: `pwsh -NoProfile -File ums/.claude/skills/mb-doc-index/tests/enumeration.tests.ps1`
Expected: FAIL — `doc-index.ps1` neexistuje.

- [ ] **Step 5: Implementuj `doc-index.ps1`**

Struktura (doplň těla podle testů; veškerý uživatelský výstup česky, komentáře anglicky):

```powershell
#Requires -Version 7
<#
.SYNOPSIS
Read-only index of Memory Bank documents across origin branches (pull model).

.DESCRIPTION
Builds the candidate set for Target-MB discovery, the cross-clone collision
check and the epic graph: one history traversal over remote refs above the base
ref, filtered by path and age. Writes nothing but the optional -Json file.

.OUTPUTS
Czech table + findings. Exit: 0 = OK, 1 = input/script failure, 2 = collisions.
#>
[CmdletBinding()]
param(
    [string] $RepoPath = '',
    [string] $BaseRef = 'origin/develop',
    [int]    $SinceDays = 120,
    [string] $BranchGlob = '',
    [string] $Json = '',
    [switch] $NoFetch
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
$script:ExitCode = 0

# --- repo resolution (contract: one discovery step) -------------------------
if (-not $RepoPath) { $RepoPath = (& git rev-parse --show-toplevel) }
if ($LASTEXITCODE -ne 0 -or -not $RepoPath) {
    Write-Error 'Git repository not found. Memory Bank requires git.'; exit 1
}
function Git([string[]] $GitArgs) { & git -C $RepoPath @GitArgs 2>$null }

if (-not $NoFetch) { Git @('fetch', '--prune', 'origin') | Out-Null }
Git @('rev-parse', '--verify', '--quiet', $BaseRef) | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Error "Base ref not found: $BaseRef"; exit 1 }

# --- one traversal: commits above the base that touched MB proposal paths ---
$since = (Get-Date).AddDays(-$SinceDays).ToString('yyyy-MM-dd')
$log = Git @(
    'log', '--remotes=origin', '--not', $BaseRef, "--since=$since",
    '--name-only', '--format=%x01%H%x09%cI%x09%an', '--',
    ':(glob)**/memory-bank/proposals/next/*.md',
    ':(glob)**/memory-bank/proposals/active/*.md',
    ':(glob)**/memory-bank/proposals/completed/*.md'
)
# Parse: records start with \x01; following lines are paths.
# Skip paths matching '/tests/fixtures/'.
# For each (path) keep the NEWEST commit that touched it.

# --- which branches carry it, and does it still exist on their tip? --------
# per candidate commit:  git branch -r --contains <sha>   (filter by -BranchGlob)
# per (branch, path):    git cat-file -e <branch>:<path>  (exists on tip?)
# header fields:         git show <branch>:<path>  ->  '- **Jira:** <id>'

# --- pseudo-branches 'local' and 'base' ------------------------------------
# local: Get-ChildItem over **/memory-bank/proposals/{next,active}/*.md in the
#        working tree (same fixture exclusion)
# base:  git ls-tree -r --name-only <BaseRef> over the MB proposal dirs known
#        from the local tree (cheap; base content is normally visible anyway)

# --- slug + phase ---------------------------------------------------------
# slug: strip exactly one prefix ^(design_|plan_|proposal_) from the file stem,
#       strip '-design' ONLY after the proposal_ prefix (contract pairing rule)
# phase: the parent directory name (next|active|completed)

# --- output ---------------------------------------------------------------
# Czech table (phases next/active only), then findings (Task 3), then -Json.
```

Parsování logu a derivace slugu (obojí implementuj přesně takto — testy na tom
stojí):

```powershell
# Records are separated by \x01; the header line is SHA \t ISO date \t author,
# every following non-empty line is a path touched by that commit.
$commits = @()
$cur = $null
foreach ($ln in ($log -split "`n")) {
    $ln = $ln.TrimEnd("`r")
    if ($ln.StartsWith([char]1)) {
        $parts = $ln.Substring(1) -split "`t"
        $cur = [pscustomobject]@{ Sha = $parts[0]; Date = $parts[1]; Author = $parts[2]; Paths = @() }
        $commits += $cur
        continue
    }
    if (-not $ln -or -not $cur) { continue }
    if ($ln -match '/tests/fixtures/') { continue }      # never index own test data
    $cur.Paths += ($ln -replace '\\', '/')
}

function Get-Slug([string] $Path) {
    # Contract pairing rule: strip exactly ONE prefix; '-design' only after 'proposal_'.
    $stem = [IO.Path]::GetFileNameWithoutExtension($Path)
    if ($stem -match '^proposal_(.+)$') { return ($Matches[1] -replace '-design$', '') }
    if ($stem -match '^(design_|plan_)(.+)$') { return $Matches[2] }
    return $stem
}

function Get-Phase([string] $Path) { return (Split-Path (Split-Path $Path -Parent) -Leaf) }
```

Tabulka (hlavička přesně takto, aby na ni šlo grepovat):

```
📇 Index dokumentů (báze origin/develop, posledních 120 dní)

| Slug | Tiket | Fáze | Větev | Poslední commit | Autor |
|---|---|---|---|---|---|
```

- [ ] **Step 6: Spusť test a ověř, že prochází**

Run: `pwsh -NoProfile -File ums/.claude/skills/mb-doc-index/tests/enumeration.tests.ps1`
Expected: PASS, `N passed`, exit 0.

- [ ] **Step 7: Commit**

```bash
git add ums/.claude/skills/mb-doc-index/scripts/doc-index.ps1 ums/.claude/skills/mb-doc-index/tests/
git commit -m "UMS: mb-doc-index — enumerace dokumentů napříč větvemi origin"
```

---

### Task 3: `doc-index.ps1` — findings, exit kódy a SKILL.md

**Files:**
- Modify: `ums/.claude/skills/mb-doc-index/scripts/doc-index.ps1`
- Create: `ums/.claude/skills/mb-doc-index/tests/findings.tests.ps1`
- Create: `ums/.claude/skills/mb-doc-index/SKILL.md`
- Modify: `ums/.claude/skills/shared/SKILLS_MANIFEST.md` (registrace nového skillu)

**Interfaces:**
- Consumes: `New-FixtureRepo`, `Invoke-Index` (Task 2).
- Produces: kódy findings `KOLIZE AKTIVNÍ PRÁCE` (CHYBA, exit 2), `DRAFT NA VÍCE VĚTVÍCH` (VAROVÁNÍ), `FRONTA I DOKONČENO` (VAROVÁNÍ), `CIZÍ AKTIVNÍ PRÁCE` (INFO); tyto kódy konzumují Tasky 5 a 6.

- [ ] **Step 1: Napiš padající test findings**

`tests/findings.tests.ps1`:

```powershell
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '_assert.ps1')
. (Join-Path $PSScriptRoot 'new-fixture-repo.ps1')

$fx = New-FixtureRepo

# 1) foreign active work on ANOTHER ticket = information only, exit 0
$r = Invoke-Index @('-RepoPath', $fx.Work, '-BaseRef', 'origin/develop', '-NoFetch')
Assert-Eq $r.Code 0 'cizí aktivní práce jiného tiketu běh nezastaví'
Assert-Match $r.Out 'CIZÍ AKTIVNÍ PRÁCE' 'cizí aktivní práce se vypíše jako informace'
Assert-Match $r.Out 'DRAFT NA VÍCE VĚTVÍCH.*ums_2_beta' 'duplicitní draft je varování'
Assert-Match $r.Out 'FRONTA I DOKONČENO.*ums_3_gama' 'obživlá fronta je varování'

# 2) the SAME slug active locally and on a foreign branch = collision, exit 2
$local = Join-Path $fx.Work 'memory-bank/proposals/active/design_ums_1_alfa.md'
New-Item -ItemType Directory -Force -Path (Split-Path $local) | Out-Null
Set-Content -LiteralPath $local -Encoding UTF8 -Value @('# Návrh: alfa', '', '- **Jira:** UMS-1')
$c = Invoke-Index @('-RepoPath', $fx.Work, '-BaseRef', 'origin/develop', '-NoFetch')
Assert-Eq $c.Code 2 'stejný slug aktivní lokálně i na cizí větvi = exit 2'
Assert-Match $c.Out 'KOLIZE AKTIVNÍ PRÁCE' 'kolize se hlásí jako CHYBA'
Assert-Match $c.Out 'origin/feature/ums-1-alfa' 'hlášení kolize nese větev'
Assert-Match $c.Out '\d{4}-\d{2}-\d{2}' 'hlášení kolize nese datum posledního commitu'

# 3) the same TICKET under a different slug is a collision too
Remove-Item -LiteralPath $local
$other = Join-Path $fx.Work 'memory-bank/proposals/active/design_ums_1_jinak.md'
Set-Content -LiteralPath $other -Encoding UTF8 -Value @('# Návrh: jinak', '', '- **Jira:** UMS-1')
$t = Invoke-Index @('-RepoPath', $fx.Work, '-BaseRef', 'origin/develop', '-NoFetch')
Assert-Eq $t.Code 2 'tentýž tiket pod jiným slugem je také kolize'

Remove-Item -Recurse -Force (Split-Path $fx.Work)
Complete-Tests
```

- [ ] **Step 2: Spusť test a ověř, že padá**

Run: `pwsh -NoProfile -File ums/.claude/skills/mb-doc-index/tests/findings.tests.ps1`
Expected: FAIL — findings se netiskne, exit kód 0 místo 2.

- [ ] **Step 3: Implementuj findings**

Do `doc-index.ps1` doplň sekci findings a nastav `$script:ExitCode = 2` u kódu `KOLIZE AKTIVNÍ PRÁCE`:

```powershell
function Add-Finding([string] $Code, [string] $Severity, [string] $Message) {
    $script:Findings += [pscustomobject]@{ code = $Code; severity = $Severity; message = $Message }
    if ($Severity -eq 'CHYBA') { $script:ExitCode = 2 }
}
# KOLIZE AKTIVNÍ PRÁCE   – phase 'active' for the same slug OR the same non-empty
#                          jira on 'local' and on a foreign branch
# DRAFT NA VÍCE VĚTVÍCH  – phase 'next' for one slug on 2+ branches
# FRONTA I DOKONČENO     – one slug in 'next' and in 'completed' anywhere
# CIZÍ AKTIVNÍ PRÁCE     – phase 'active' on a foreign branch, different ticket
```

Výstup findings (formát ať jde grepovat): `SEVERITA  KÓD  detail`, například
`CHYBA  KOLIZE AKTIVNÍ PRÁCE  ums_1_alfa (UMS-1) je aktivní i na origin/feature/ums-1-alfa (2026-07-30, Test)`.

- [ ] **Step 4: Spusť oba testy a ověř, že procházejí**

```bash
pwsh -NoProfile -File ums/.claude/skills/mb-doc-index/tests/enumeration.tests.ps1
pwsh -NoProfile -File ums/.claude/skills/mb-doc-index/tests/findings.tests.ps1
```
Expected: oba PASS, exit 0.

- [ ] **Step 5: Napiš `SKILL.md`**

```markdown
---
name: mb-doc-index
description: Use when you need to know which Memory Bank documents exist on other branches — before pinning new work (cross-clone collision check), when activating a queued design draft, when feeding the epic graph, or to answer "who is working on what" (kdo na čem pracuje, existuje už návrh, kolize slugů).
license: MIT
metadata:
  author: UMS Project
  version: "1.0"
---

> Follow [UMS_MEMORY_BANK_CONTRACT](../shared/UMS_MEMORY_BANK_CONTRACT.md) —
> especially "Cross-Branch Visibility", "Publication Contract" and
> "Target-MB Discovery & Pinning".

# Command: mb-doc-index

**Action:** Index Memory Bank documents across `origin` branches (pull model) and
report collisions.
**Execution:** Read-only towards git; the only write is the optional `-Json` file.

## Workflow

1. Run the script (Czech table + findings; `-Json` for machine consumers):

```powershell
pwsh <this skill>/scripts/doc-index.ps1 `
  [-RepoPath <repo>] [-BaseRef origin/develop] [-SinceDays 120] `
  [-BranchGlob 'origin/feature/*'] [-Json <path>] [-NoFetch]
```

2. Exit codes: `0` OK · `1` input/script failure · `2` collision findings —
   treat `2` as a fail-closed STOP for pinning new work.
3. Findings are decision candidates for the user, never silent fixes:
   `KOLIZE AKTIVNÍ PRÁCE` (CHYBA), `DRAFT NA VÍCE VĚTVÍCH`, `FRONTA I DOKONČENO`
   (VAROVÁNÍ), `CIZÍ AKTIVNÍ PRÁCE` (INFO — normal parallel work).
4. Taking over a draft from a foreign branch is a blob copy, never a
   cherry-pick (contract, Cross-Branch Visibility).

## Notes

- `-BaseRef` defaults to `origin/develop`; in the superpowers fork use
  `origin/ums-memory-bank`.
- The index is git-only and never sees Jira descriptions, so it does NOT report
  unreachable commits inside already published Jira links — reachability is
  enforced at write time by `mb-jira-update` §7.
- Paths under `*/tests/fixtures/*` are excluded so the layer does not index its
  own test data.
```

- [ ] **Step 6: Zaregistruj skill do manifestu**

Do tabulky `## Aktivní mb-* skilly` v `ums/.claude/skills/shared/SKILLS_MANIFEST.md` přidej řádek (za `mb-epic-graph`, ať jsou nástroje pohromadě):

```markdown
| mb-doc-index | [mb-doc-index/SKILL.md](../mb-doc-index/SKILL.md) | Read-only index dokumentů napříč větvemi origin (model tahu) + kolizní findings pro discovery |
```

- [ ] **Step 7: Commit**

```bash
git add ums/.claude/skills/mb-doc-index/ ums/.claude/skills/shared/SKILLS_MANIFEST.md
git commit -m "UMS: mb-doc-index — findings, exit kódy, dokumentace a registrace skillu"
```

---

### Task 4: Hook `guard-git-push.mjs` a `settings.json`

**Files:**
- Create: `ums/.claude/hooks/guard-git-push.mjs`
- Create: `ums/.claude/hooks/tests/_assert.ps1` (kopie s helperem `Invoke-Hook`)
- Create: `ums/.claude/hooks/tests/guard-git-push.tests.ps1`
- Modify: `ums/.claude/settings.json`

**Interfaces:**
- Consumes: pravidla z Tasku 1 (dvouúrovňová push policy, seznam chráněných větví).
- Produces: hook zamítající pushe do chráněných větví; registrace v `settings.json` (`PreToolUse` matcher `Bash`), uvolněný `permissions.deny`, rozšířený `permissions.allow`.

- [ ] **Step 1: Napiš padající test hooku**

`ums/.claude/hooks/tests/guard-git-push.tests.ps1`:

```powershell
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '_assert.ps1')

function Test-Cmd([string] $Command, [string] $Cwd = '') {
    $payload = @{ tool_name = 'Bash'; tool_input = @{ command = $Command } }
    if ($Cwd) { $payload.cwd = $Cwd }
    return Invoke-Hook ($payload | ConvertTo-Json -Depth 5 -Compress)
}

# allowed: the actor's own ticket branch
Assert-Eq (Test-Cmd 'git push origin feature/ums-1-alfa') '' 'push tiketové větve projde'
Assert-Eq (Test-Cmd 'git push -u origin feature/ums-1-alfa') '' 'push s -u projde'
Assert-Eq (Test-Cmd 'git status') '' 'jiný git příkaz se neřeší'
Assert-Eq (Test-Cmd 'echo "git push origin develop"') '' 'zmínka v echu se neřeší'

# denied: shared branches
foreach ($c in @(
    'git push origin develop',
    'git push origin main',
    'git push origin release/2026.1',
    'git push origin HEAD:refs/heads/develop',
    'cd /repo && git push origin develop',
    'git -C /repo push origin master'
)) { Assert-Match (Test-Cmd $c) 'permissionDecision.*deny' "zamítnuto: $c" }

# denied: destructive shapes even on a ticket branch
foreach ($c in @(
    'git push --force origin feature/ums-1-alfa',
    'git push -f origin feature/ums-1-alfa',
    'git push --force-with-lease origin feature/ums-1-alfa',
    'git push origin +feature/ums-1-alfa',
    'git push origin :feature/ums-1-alfa',
    'git push --delete origin feature/ums-1-alfa',
    'git push --all origin',
    'git push --mirror origin'
)) { Assert-Match (Test-Cmd $c) 'permissionDecision.*deny' "zamítnuto: $c" }

# bare push resolves the current branch from cwd
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("mbhook-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
& git init -b develop $tmp | Out-Null
Assert-Match (Test-Cmd 'git push' $tmp) 'permissionDecision.*deny' 'bare push na develop je zamítnut'
& git -C $tmp checkout -q -b feature/ums-9-x
Assert-Eq (Test-Cmd 'git push' $tmp) '' 'bare push na tiketové větvi projde'
Remove-Item -Recurse -Force $tmp

# unparseable input must not block
Assert-Eq (Invoke-Hook 'not json') '' 'nerozparsovatelný vstup neblokuje'

Complete-Tests
```

`ums/.claude/hooks/tests/_assert.ps1` = kopie helperu z `mb-epic-graph/tests/_assert.ps1`, kde místo `Invoke-Graph` je:

```powershell
# Pipes a JSON payload into the hook; returns its stdout (empty = allowed).
function Invoke-Hook([string] $PayloadJson) {
    $hook = Join-Path $PSScriptRoot '..\guard-git-push.mjs'
    try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
    return ($PayloadJson | & node $hook | Out-String).Trim()
}
```

- [ ] **Step 2: Spusť test a ověř, že padá**

Run: `pwsh -NoProfile -File ums/.claude/hooks/tests/guard-git-push.tests.ps1`
Expected: FAIL — hook neexistuje.

- [ ] **Step 3: Implementuj hook**

```javascript
// PreToolUse guard for `git push` (contract v2.2, "Publication Contract"):
// the actor's own ticket branch is pushed freely, shared branches never by the
// agent. Deny-list of protected refs plus destructive push shapes.
import { execFileSync } from 'node:child_process';

const PROTECTED = [/^develop$/i, /^main$/i, /^master$/i, /^release\//i];
const DENY_FLAGS = ['--force', '-f', '--force-with-lease', '--force-if-includes',
                    '--all', '--mirror', '--delete', '-d', '--prune'];

const isProtected = (ref) => {
  const name = String(ref).replace(/^refs\/heads\//, '');
  return PROTECTED.some((re) => re.test(name));
};

const currentBranch = (cwd) => {
  try {
    return execFileSync('git', ['branch', '--show-current'],
      { cwd: cwd || process.cwd(), encoding: 'utf8' }).trim();
  } catch { return ''; }
};

const deny = (reason) => {
  process.stdout.write(JSON.stringify({
    hookSpecificOutput: {
      hookEventName: 'PreToolUse',
      permissionDecision: 'deny',
      permissionDecisionReason: reason,
    },
  }));
  process.exit(0);
};

let raw = '';
process.stdin.on('data', (c) => (raw += c));
process.stdin.on('end', () => {
  let input = {};
  try { input = JSON.parse(raw); } catch { process.exit(0); }
  const command = String(input?.tool_input?.command ?? '');
  // Only real invocations: `git push` or `git -C <path> push`, not a mention
  // inside a quoted string.
  const m = command.match(/(^|[;&|]\s*)git(\s+-[A-Za-z-]+(=\S+)?|\s+-C\s+\S+)*\s+push\b([^;&|]*)/);
  if (!m) process.exit(0);
  const tail = (m[4] || '').trim();
  const tokens = tail.split(/\s+/).filter(Boolean);

  if (tokens.some((t) => DENY_FLAGS.includes(t))) {
    deny('UMS: destruktivní push (force / delete / all / mirror) je zakázaný — viz Publication Contract v .claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md.');
  }
  const refspecs = tokens.filter((t) => !t.startsWith('-'));
  // drop the remote name (first positional)
  const specs = refspecs.slice(1);
  if (specs.length === 0) {
    const cur = currentBranch(input?.cwd);
    if (!cur) {
      deny('UMS: nelze zjistit aktuální větev, takže push nelze posoudit — spusť ho s explicitní větví (`git push origin <vetev>`).');
    }
    if (isProtected(cur)) {
      deny(`UMS: '${cur}' je sdílená větev — agent do ní nepushuje. Připrav příkaz a nech ho uživateli: \`! git push origin ${cur}\` (Publication Contract, dvouúrovňová push policy).`);
    }
    process.exit(0);
  }
  for (const spec of specs) {
    if (spec.startsWith('+') || spec.startsWith(':')) {
      deny('UMS: vynucený (+) ani mazací (:) refspec není povolený — viz Publication Contract.');
    }
    const dst = spec.includes(':') ? spec.split(':').pop() : spec;
    if (isProtected(dst)) {
      deny(`UMS: '${dst}' je sdílená větev — agent do ní nepushuje. Připrav příkaz a nech ho uživateli: \`! git push origin ${String(dst).replace(/^refs\/heads\//, '')}\` (Publication Contract, dvouúrovňová push policy).`);
    }
  }
  process.exit(0);
});
```

- [ ] **Step 4: Spusť test a ověř, že prochází**

Run: `pwsh -NoProfile -File ums/.claude/hooks/tests/guard-git-push.tests.ps1`
Expected: PASS, exit 0.

- [ ] **Step 5: Uprav `settings.json`**

Z `permissions.deny` odstraň `"Bash(git push:*)"`. Do `permissions.allow` přidej:

```json
      "Bash(git fetch:*)",
      "Bash(git ls-remote:*)",
      "Bash(git for-each-ref:*)",
      "Bash(git ls-tree:*)",
      "Bash(git cat-file:*)",
      "Bash(git merge-base:*)"
```

Do `hooks.PreToolUse` přidej nový blok:

```json
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "node \"$CLAUDE_PROJECT_DIR/.claude/hooks/guard-git-push.mjs\""
          }
        ]
      }
```

- [ ] **Step 6: Ověř JSON a chování politiky**

```bash
node -e "JSON.parse(require('fs').readFileSync('ums/.claude/settings.json','utf8')); console.log('ok')"
grep -n "git push" ums/.claude/settings.json
```
Expected: `ok`; grep ukáže jen hook, žádné deny pravidlo na push.

- [ ] **Step 7: Commit**

```bash
git add ums/.claude/hooks/guard-git-push.mjs ums/.claude/hooks/tests/ ums/.claude/settings.json
git commit -m "UMS: hook guard-git-push a dvouúrovňová politika pushování"
```

---

### Task 5: `mb-epic-graph -IndexFile`

**Files:**
- Modify: `ums/.claude/skills/mb-epic-graph/scripts/epic-graph.ps1`
- Modify: `ums/.claude/skills/mb-epic-graph/SKILL.md`
- Create: `ums/.claude/skills/mb-epic-graph/tests/fixtures/doc-index/index.json`
- Modify: `ums/.claude/skills/mb-epic-graph/tests/status-glyph.tests.ps1`

**Interfaces:**
- Consumes: JSON tvar z Tasku 2 (`entries[].slug|jira|phase|branch|date`), kódy findings z Tasku 3.
- Produces: parametr `-IndexFile <path>`; findings `DRAFT NA CIZÍ VĚTVI` (INFO) a `DRAFT NA VÍCE VĚTVÍCH` (VAROVÁNÍ) ve výstupu `-Check`; glyf ▶️/⏳ i pro návrh existující jen na cizí větvi.

**Pozn. k pojmenování:** specifikace navrhovala pro druhý finding název
`SLUG NA VÍCE VĚTVÍCH`; používá se `DRAFT NA VÍCE VĚTVÍCH` shodně s
`mb-doc-index` (Task 3) — dva názvy pro tentýž jev by byly zdroj zmatku.

- [ ] **Step 1: Přečti stávající mechaniku glyfu a prose-checku**

Přečti v `epic-graph.ps1` část, která z `-ProposalPath` staví mapu tiket → proposal, a část, která z ní vybírá glyf (▶️/⏳/💡/❔). Poznač si jméno té struktury — nový zdroj do ní jen přidává záznamy.

- [ ] **Step 2: Zjisti, na jakém snapshotu a epiku stávající test běží**

```bash
grep -n "InputFile\|EpicKey\|fixtures/jira" ums/.claude/skills/mb-epic-graph/tests/status-glyph.tests.ps1 | head -20
grep -o '"key": *"[A-Z]*-[0-9]*"' ums/.claude/skills/mb-epic-graph/tests/fixtures/jira/status.json | sort -u
```
Zapiš si konkrétní snapshot, klíč epiku a klíč tiketu **bez proposalu** (v tabulce vln má dnes glyf 💡 nebo ❔) — ten použiješ ve fixture indexu i v asercích místo zástupných hodnot níže.

- [ ] **Step 3: Vytvoř fixture index**

`tests/fixtures/doc-index/index.json` — `jira` nastav na tiket zjištěný v předchozím kroku, `slug` na jeho kód v snake_case:

```json
{
  "base": "origin/develop",
  "generated": "2026-07-30T10:00:00+02:00",
  "entries": [
    {
      "slug": "ums_2884_alfa", "jira": "UMS-2884", "phase": "next",
      "path": "memory-bank/proposals/next/design_ums_2884_alfa.md",
      "branch": "origin/feature/ums-2884-alfa",
      "commit": "1111111111111111111111111111111111111111",
      "date": "2026-07-30T09:00:00+02:00", "author": "Test"
    },
    {
      "slug": "ums_2884_alfa", "jira": "UMS-2884", "phase": "next",
      "path": "memory-bank/proposals/next/design_ums_2884_alfa.md",
      "branch": "origin/feature/ums-2884-alfa-dup",
      "commit": "2222222222222222222222222222222222222222",
      "date": "2026-07-29T09:00:00+02:00", "author": "Test"
    }
  ],
  "findings": []
}
```

- [ ] **Step 4: Napiš padající testy do `status-glyph.tests.ps1`**

Na konec souboru (před `Complete-Tests`); `<SNAP>`, `<EPIC>` a `<TIKET>` nahraď hodnotami zjištěnými ve Stepu 2:

```powershell
# --- -IndexFile: a draft living only on a foreign branch counts as "návrh hotov"
$idx = Join-Path $PSScriptRoot 'fixtures/doc-index/index.json'
$snap = Join-Path $PSScriptRoot 'fixtures/jira/<SNAP>'
$r = Invoke-Graph @('-InputFile', $snap, '-EpicKey', '<EPIC>', '-Check', '-IndexFile', $idx)
Assert-Match $r.Out '▶️|⏳' 'glyf zohlední návrh existující jen na cizí větvi'
Assert-Match $r.Out 'DRAFT NA CIZÍ VĚTVI' 'graf hlásí draft na cizí větvi jako informaci'
Assert-Match $r.Out 'DRAFT NA VÍCE VĚTVÍCH' 'graf hlásí tentýž draft na dvou větvích'
Assert-True ($r.Code -ne 1) 'nové findings nejsou skriptová chyba'

$without = Invoke-Graph @('-InputFile', $snap, '-EpicKey', '<EPIC>', '-Check')
Assert-NotMatch $without.Out 'DRAFT NA CIZÍ VĚTVI' 'bez -IndexFile se nové findings netiskne'
Assert-Match $without.Out '💡|❔' 'bez -IndexFile zůstává tiket bez známého návrhu'
```

- [ ] **Step 5: Spusť test a ověř, že padá**

Run: `pwsh -NoProfile -File ums/.claude/skills/mb-epic-graph/tests/status-glyph.tests.ps1`
Expected: FAIL — `-IndexFile` není známý parametr.

- [ ] **Step 6: Implementuj `-IndexFile`**

- do `param()` přidej `[string] $IndexFile = ''`;
- po načtení `-ProposalPath` (nebo místo něj, když není zadaný) načti JSON a přidej jeho `entries` do téže mapy tiket → proposal; u záznamu si drž `branch`, aby šlo hlásit findings;
- findings: `DRAFT NA CIZÍ VĚTVI` (INFO) pro každý záznam s `branch` různým od `local`/`base`; `DRAFT NA VÍCE VĚTVÍCH` (VAROVÁNÍ) pro slug se dvěma a více různými `branch` ve fázi `next`;
- **žádné nové CHYBY** — `-Check` gate se tímto nesmí zhoršit (jinak by paralelní provoz zavíral okna);
- `-Source Proposals` zůstává nedotčený: `-IndexFile` je funkce Jira režimu.

- [ ] **Step 7: Spusť celou testovou sadu skillu**

```bash
for f in ums/.claude/skills/mb-epic-graph/tests/*.tests.ps1; do pwsh -NoProfile -File "$f" || exit 1; done
```
Expected: všechny PASS.

- [ ] **Step 8: Zdokumentuj parametr v `SKILL.md`**

Do výčtu parametrů přidej `-IndexFile <path>` (JSON z `mb-doc-index`; sytí glyf o návrhy na cizích větvích) a do seznamu findings `DRAFT NA CIZÍ VĚTVI` (info) a `DRAFT NA VÍCE VĚTVÍCH` (varování) s poznámkou, že `-Check` nezhazují.

- [ ] **Step 9: Commit**

```bash
git add ums/.claude/skills/mb-epic-graph/
git commit -m "UMS: mb-epic-graph — -IndexFile, glyf a findings pro cizí větve"
```

---

### Task 6: Konzumenti indexu — `mb-state` a `mb-epic-elaboration`

**Files:**
- Modify: `ums/.claude/skills/mb-state/SKILL.md`
- Modify: `ums/.claude/skills/mb-epic-elaboration/SKILL.md`
- Modify: `ums/.claude/skills/mb-epic-elaboration/protocol.md`

**Interfaces:**
- Consumes: skill `mb-doc-index`, jeho findings a exit kódy (Task 3); `-IndexFile` (Task 5).
- Produces: nic pro další tasky (koncoví konzumenti).

- [ ] **Step 1: `mb-state` — sekce „Cizí větve"**

Do „1. Gather state" přidej odrážku:

```markdown
- **Cizí větve:** run the `mb-doc-index` skill (read-only). Report foreign
  active work items (slug, ticket, branch, last commit date) and its findings.
  A `KOLIZE AKTIVNÍ PRÁCE` finding is a warning here (mb-state never stops
  work) with the recommendation to resolve it before pinning new work.
```

Do reportu v „2. Report (Czech)" přidej řádky:

```
Cizí větve: <žádné | výčet slug@větev (datum)>
Kolize: <žádné | ⚠️ výčet>
```

- [ ] **Step 2: `mb-epic-elaboration/protocol.md` §0 — index v bootstrapu**

Za bod 3 (ledger-status) vlož nový bod a přečísluj zbytek:

```markdown
4. Run the `mb-doc-index` skill (read-only, `-BaseRef` = the repo's base branch).
   Its findings feed the window agenda: `DRAFT NA VÍCE VĚTVÍCH` and
   `FRONTA I DOKONČENO` are dirty-set candidates; `KOLIZE AKTIVNÍ PRÁCE` is a
   decision for the human BEFORE any drafting starts.
```

- [ ] **Step 3: `protocol.md` §3 — publikace před zápisem odkazů**

V §3 přesuň publikaci před krok s odkazy: za bod 5 (one commit) vlož

```markdown
6. **Publish the branch** (Publication Contract, publication point 3): push the
   actor's own branch — announced, not negotiated. The commit-pinned links
   written in the next step MUST be reachable on `origin`, so this push precedes
   them. Never push a shared branch.
```

a v následujícím bodě (dnes 6) smaž větu, že odkaz platí „valid on next push", a nahraď ji: `The permalink resolves immediately — the branch was published in the previous step.`

- [ ] **Step 4: `protocol.md` §2 a §6 — drafty následných tiketů**

Do §2 bodu 6 (Design) doplň:

```markdown
   Drafts of FOLLOW-UP tickets created mid-window live in `next/` on the actor's
   own branch and become visible to others by pushing that branch (never by
   pushing a shared branch, never by cherry-pick).
```

Do §6 (Edge cases) přidej odrážku:

```markdown
- **Draft already exists on a foreign branch** (reported by `mb-doc-index`):
  do not write a second one. Either take it over by blob copy (contract,
  Cross-Branch Visibility) or leave it to its owner — the human decides.
```

- [ ] **Step 5: `mb-epic-elaboration/SKILL.md` — quick reference a red flags**

Do tabulky „Quick reference" přidej řádek:

```markdown
| Dokumenty na cizích větvích, kolize slugů | `mb-doc-index` skill (read-only) |
```

Do „Red flags" přidej: `- Writing a new draft for a ticket that mb-doc-index already reports on a foreign branch.`

- [ ] **Step 6: Ověř odkazy a jazyk**

```bash
grep -rn "mb-doc-index" ums/.claude/skills/mb-state/SKILL.md ums/.claude/skills/mb-epic-elaboration/
grep -n "valid on next push" ums/.claude/skills/mb-epic-elaboration/protocol.md
```
Expected: první grep najde nové zmínky; druhý nic.

- [ ] **Step 7: Commit**

```bash
git add ums/.claude/skills/mb-state/SKILL.md ums/.claude/skills/mb-epic-elaboration/
git commit -m "UMS: mb-state a mb-epic-elaboration konzumují index dokumentů"
```

---

### Task 7: Konzumenti invariantu — `mb-jira-update` a `mb-architect-review`

**Files:**
- Modify: `ums/.claude/skills/mb-jira-update/SKILL.md` (§5–7, §10)
- Modify: `ums/.claude/skills/mb-architect-review/SKILL.md` (Push Policy, krok 4)
- Modify: `ums/.claude/skills/shared/SKILLS_MANIFEST.md` (popis `mb-architect-review` už neplatí)

**Interfaces:**
- Consumes: `## Publication Contract` (Task 1).
- Produces: nic pro další tasky.

- [ ] **Step 1: `mb-jira-update` §5 — kontrola dosažitelnosti**

Za odrážky o HEAD SHA přidej:

```markdown
- **Reachability gate (Publication Contract, MANDATORY):** after the SHA is
  stabilized, verify it is on `origin`:
  `git fetch origin` then `git branch -r --contains <sha>`. Empty result =
  **STOP** before publishing anything; report the branch to publish and let the
  actor push it (own ticket branch) or hand the command to the user (shared
  branch). Re-verify after the push. A published link to an unreachable commit
  is the failure this gate exists to prevent.
```

- [ ] **Step 2: `mb-jira-update` §7 — smaž alibi**

Nahraď větu `The permalink resolves once the pinned commit is on Bitbucket; if the branch is not yet pushed, the link goes live on the next push (expected).` textem:

```markdown
- The permalink resolves immediately: §5's reachability gate guarantees the
  pinned commit is on `origin` before the link is published.
```

Totéž v §7b (věta o „goes live on the next push").

- [ ] **Step 3: `mb-jira-update` §10 — brána finalizace**

Před bod 1 vlož:

```markdown
0. **Publication gate:** verify the merge commit of the work (HEAD of the base
   branch) is reachable on `origin` (`git branch -r --contains <sha>`). If it is
   not, **STOP** without transitioning: tell the user in Czech that the code is
   local only and the tester would have nothing to test, and hand over the exact
   command (`! git push origin <base>`). The agent never pushes a shared branch.
   Re-verify after the user's push, then continue. If the server refuses a direct
   push to the base branch, report it and offer the fallback (short branch +
   an exceptional PR).
```

- [ ] **Step 4: `mb-architect-review` — Push Policy na odkaz**

Nahraď sekci `## Push Policy (MANDATORY)` textem:

```markdown
## Push Policy

Per the contract's **Publication Contract**: the ticket branch is the actor's
own branch, so the handoff push is announced (branch + outgoing commits), not
negotiated; shared branches are never pushed by the agent. One handoff = one
push. A refusal to publish stops the handoff — without the push the other side
sees neither the design nor `context.md`.
```

V kroku 4 režimu request nahraď `**Push the ticket branch** (fail-closed, explicit approval per Push Policy).` za `**Publish the ticket branch** (announced push per the Publication Contract; the pinned design commit MUST be reachable on origin before step 5 writes the link).`

- [ ] **Step 5: Sjednoť popis v manifestu**

V `ums/.claude/skills/shared/SKILLS_MANIFEST.md` nahraď v řádku `mb-architect-review` část `push jen se schválením` za `publikace větve dle Publication Contract` — dvouúrovňová politika starý popis ruší.

- [ ] **Step 6: Ověř, že nikde nezůstal starý slib**

```bash
grep -rn "goes live on the next push\|valid on next push\|explicit approval per Push Policy\|push jen se schválením" ums/.claude/
```
Expected: žádný výstup.

- [ ] **Step 7: Commit**

```bash
git add ums/.claude/skills/mb-jira-update/SKILL.md ums/.claude/skills/mb-architect-review/SKILL.md ums/.claude/skills/shared/SKILLS_MANIFEST.md
git commit -m "UMS: mb-jira-update a mb-architect-review vynucují dosažitelnost commitu"
```

---

### Task 8: Overlaye

**Files:**
- Modify: `ums/.claude/skills/shared/overlays/brainstorming.overlay.md`
- Modify: `ums/.claude/skills/shared/overlays/subagent-driven-development.overlay.md`
- Modify: `ums/.claude/skills/shared/overlays/finishing-a-development-branch.overlay.md`

**Interfaces:**
- Consumes: Publication Contract (Task 1), skill `mb-doc-index` (Task 3), brána §10 (Task 7).
- Produces: nic — poslední obsahový task.

- [ ] **Step 1: `brainstorming.overlay.md` — index v discovery**

V odrážce k bodu 1 doplň za „scan active work items": `run the mb-doc-index skill and treat the candidate set as the union of the local scan and the index over origin; a KOLIZE AKTIVNÍ PRÁCE finding is a fail-closed STOP (someone already works on this ticket), foreign active work on other tickets is normal`.

- [ ] **Step 2: `brainstorming.overlay.md` — publikace návrhu**

Do odrážky k bodu 6 doplň na konec: `After committing the design, publish the branch (Publication Contract, publication point 1) — an announced push of your own ticket branch.`

- [ ] **Step 3: `subagent-driven-development.overlay.md` — publikace plánu**

Přidej čtvrtou odrážku (čtvrtý overlay blok NEZAVÁDĚT):

```markdown
- **publikace** — before dispatching the first task, publish the branch with the
  committed plan (Publication Contract, publication point 2): an announced push
  of your own ticket branch, alongside the baseline build/test check. Shared
  branches are never pushed by the agent.
```

- [ ] **Step 4: `finishing-a-development-branch.overlay.md` — publikace develop**

Do bloku Option 1 přidej odstavec:

```markdown
- **Option 1, after a green merge:** ask (Czech) „Publikovat `develop` na
  origin?" and hand the user the exact command (`! git push origin develop`) with
  the outgoing commits — the agent never pushes a shared branch. Until it is
  published, `mb-jira-update` finalization stops at its publication gate and the
  ticket does NOT move to „Test".
```

- [ ] **Step 5: Ověř kotvy a vyváženost markerů**

```bash
grep -c "UMS-OVERLAY BEGIN\|UMS-OVERLAY END" ums/.claude/skills/shared/overlays/*.overlay.md
grep -n "ANCHOR-BEFORE" ums/.claude/skills/shared/overlays/*.overlay.md
```
Expected: každý fragment má vyvážené markery; `ANCHOR-BEFORE` zůstává jen ve finishing fragmentu a je nezměněný.

- [ ] **Step 6: Commit**

```bash
git add ums/.claude/skills/shared/overlays/
git commit -m "UMS: overlaye — index v discovery, publikace návrhu, plánu a develop"
```

---

### Task 9: Verifikace celku a nabídka nasazení

**Files:**
- Modify: žádné (jen ověření); případné opravy nálezů v souborech předchozích tasků

**Interfaces:**
- Consumes: vše z Tasků 1–8.
- Produces: zelený běh testů vrstvy jako podklad pro harvest.

- [ ] **Step 1: Spusť všechny testy vrstvy**

```bash
for f in ums/.claude/skills/*/tests/*.tests.ps1 ums/.claude/hooks/tests/*.tests.ps1; do
  echo "== $f"; pwsh -NoProfile -File "$f" || exit 1
done
```
Expected: každý soubor `N passed`, celkový exit 0.

- [ ] **Step 2: Zkontroluj relativní odkazy v nových a změněných dokumentech**

Vyjmi z každého změněného `.md` odkazy `](...)` na relativní cesty a ověř existenci cíle vůči adresáři souboru. Expected: žádný viselec (revendor verifikace na tom jinak padne).

- [ ] **Step 3: Ověř dvě otevřené otázky ze specifikace**

```bash
git config --get push.default
git ls-remote --heads origin develop
```
Expected: `push.default` je `simple` nebo nenastavený (tedy `simple`); u monorepa zjisti, zda Bitbucket brání přímému pushi do `develop` (branch permissions). Nález zapiš do `memory-bank/tech.md` sekce „Pasti prostředí" při harvestu — pokud je `develop` chráněný, uveď v `mb-jira-update` §10 fallback jako výchozí cestu.

- [ ] **Step 4: Ověř index na skutečném repu**

```bash
pwsh -NoProfile -File ums/.claude/skills/mb-doc-index/scripts/doc-index.ps1 -BaseRef origin/ums-memory-bank
```
Expected: běh do 15 s (163 vzdálených větví), tabulka bez cizích aktivních položek, exit 0. Delší běh = zúž `-SinceDays` a zaznamenej reálný čas.

- [ ] **Step 5: Nabídni nasazení (NEPROVÁDĚJ bez potvrzení)**

Oznam uživateli česky, že vrstva je hotová a nasazení do monorepa a lokální `.claude/` se provádí `pwsh ums/sync-with-monorepo.ps1 -Agent claude -Scope Monorepo -Direction ToMonorepo`. Sync **spusť jen na explicitní pokyn** — mění živou master kopii vrstvy mimo tento repozitář.

- [ ] **Step 6: Commit případných oprav**

```bash
git add <opravené soubory>
git commit -m "UMS: opravy z verifikačního průchodu publikace a viditelnosti"
```
