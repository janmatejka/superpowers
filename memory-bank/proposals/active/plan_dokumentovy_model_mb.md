# Dokumentový model Memory Bank Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

- **Jira:** (žádný tiket)
- **Návrh:** [design_dokumentovy_model_mb.md](design_dokumentovy_model_mb.md)
- **Target MB:** memory-bank/

**Goal:** Zúžit povinné jádro projektové Memory Bank na `brief.md` +
`architecture.md` + `tech.md`, zavést a zapojit `playbook.md` jako preskriptivní
dokument se sběrem zkušeností za běhu, dát faktům deterministické vlastnictví
a dodat opakovatelný migrační nástroj.

**Architecture:** Normativní zdroj je kontrakt v `ums/.claude/skills/shared/`;
skilly a overlay fragmenty ho konzumují. Nový skill `mb-migrate-docs` má dva
skripty — mechanický převod a verifikátor mazacího režimu — a orchestruje mezi
nimi levné agentní dispatche. Vendorované upstream skilly se mění výhradně přes
overlay fragmenty.

**Tech Stack:** Markdown (kontrakt, skilly, overlaye), PowerShell 7 (skripty),
git (staging jako snapshot pro verifikátor), vlastní `_assert.ps1` testovací
konvence bez Pesteru.

## Global Constraints

- **Contract-Version se zvedá na `2.3`** a poznámka „Supersedes" jmenuje v2.2.
- **Jazyk — AI-facing anglicky:** těla skillů, overlay fragmenty, kód a
  komentáře skriptů, sběrný soubor `playbook-candidates.md`, dispatch prompty.
- **Jazyk — česky:** obsah MB dokumentů (`brief.md`, `playbook.md`, …), výstupy
  skriptů `migrate-mb-docs.ps1` a `verify-deletion-only.ps1` (tabulky, nálezy —
  potkává je agent i uživatel při MB práci, stejně jako u `doc-index.ps1`),
  commit messages, komunikace s uživatelem.
- **Vendorované soubory se needitují ručně** — změny upstream skillů jen přes
  `ums/.claude/skills/shared/overlays/*.overlay.md` uvnitř bloků
  `<!-- UMS-OVERLAY BEGIN/END -->`.
- **Testy:** PowerShell 7, žádný Pester, `_assert.ps1` zkopírovaný do adresáře
  testů dané sady, offline fixtura s lokálním bare „origin".
- **Skripty:** `#Requires -Version 7`, `Set-StrictMode -Version Latest`,
  `$ErrorActionPreference = 'Stop'`, UTF-8 konzole, comment-based help
  (`.SYNOPSIS`/`.PARAMETER`/`.OUTPUTS`) jako u `doc-index.ps1`.
- **Exit kódy skriptů:** `0` OK · `1` chyba vstupu/běhu · `2` blokující nález.
- **Žádný skript ani skill v této práci necommituje ani nepushuje.** Staging
  (`git add`, `git mv`, `git rm`) je povolený.
- **Git worktrees jsou zakázané** — pracuje se na větvi `ums-memory-bank`
  v místě.
- **`$LASTEXITCODE` se čte jen bezprostředně po nativním volání ve stejné
  větvi** (past `Set-StrictMode` — viz komentář v `doc-index.ps1`).
- **Cesty `*/tests/fixtures/*` se z průchodů MB vylučují**, aby vrstva
  neindexovala vlastní testovací data.

---

## File Structure

**Vytvářené:**

| Soubor | Odpovědnost |
|---|---|
| `ums/.claude/skills/mb-migrate-docs/SKILL.md` | Orchestrace obou fází, pravidla agentního dispatche, hlášení |
| `ums/.claude/skills/mb-migrate-docs/scripts/migrate-mb-docs.ps1` | Mechanická fáze: detekce, sloučení, přejmenování, přepis odkazů |
| `ums/.claude/skills/mb-migrate-docs/scripts/verify-deletion-only.ps1` | Ověření, že agent jen mazal a přeskupoval |
| `ums/.claude/skills/mb-migrate-docs/tests/_assert.ps1` | Kopie asertační konvence vrstvy |
| `ums/.claude/skills/mb-migrate-docs/tests/new-fixture-repo.ps1` | Offline fixtura s MB ve staré i nové podobě |
| `ums/.claude/skills/mb-migrate-docs/tests/migrate.tests.ps1` | Testy mechanické fáze |
| `ums/.claude/skills/mb-migrate-docs/tests/verify.tests.ps1` | Testy verifikátoru |
| `memory-bank/playbook.md` | Postupy vývoje této vrstvy (dogfood) |

**Měněné:**

| Soubor | Změna |
|---|---|
| `ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md` | v2.3: sada dokumentů, vlastnictví faktu, playbook, kandidáti, tolerance |
| `ums/.claude/skills/shared/overlays/subagent-driven-development.overlay.md` | Playbook v dispatchi a baseline, sekce reportu |
| `ums/.claude/skills/shared/overlays/finishing-a-development-branch.overlay.md` | Zmínka gate v Harvest Gate |
| `ums/.claude/skills/mb-harvest/SKILL.md` | Sada dokumentů, sweep se třemi výústěními, playbook gate, přesuny |
| `ums/.claude/skills/mb-init/SKILL.md` | Sada dokumentů, playbook jen při nalezených příkazech |
| `ums/.claude/skills/mb-sync/SKILL.md` | Sada dokumentů, vlastnictví faktu, přesuny |
| `ums/.claude/skills/mb-scan/SKILL.md`, `mb-git-commit/SKILL.md`, `mb-git-message/SKILL.md`, `mb-jira-update/SKILL.md` | Jeden řádek jazykového boilerplate |
| `ums/.claude/skills/shared/SKILLS_MANIFEST.md` | Nový skill v seznamu |
| `ums/README.md` | Dokumentový model, nový skill |
| `memory-bank/brief.md` | Pohltí `product.md` |
| `memory-bank/tech.md` | Postupy odejdou do `playbook.md` |
| `memory-bank/product.md` | Smazán |

---

### Task 1: Kontrakt v2.3

**Files:**
- Modify: `ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md`

**Interfaces:**
- Consumes: nic (první úloha).
- Produces: normativní text, na který se odvolávají všechny další úlohy —
  názvy sekcí `## Memory Bank Document Set`, `## Document Ownership`,
  identifikátor `Harvest Contract §3`, cesta
  `<MB_ROOT>/.superpowers/playbook-candidates.md`, hlavička kandidáta
  (`Tried` / `Happened` / `Procedure` / `Target MB` / `Corrects`).

- [ ] **Step 1: Zvednout verzi**

Nahradit řádky 3–8 (blok `- **Contract-Version:**` a „Supersedes"):

```markdown
- **Contract-Version:** 2.3
- Supersedes v2.2 (narrows the mandatory document set to
  `brief.md`/`architecture.md`/`tech.md`, introduces `playbook.md` with the
  consult-before-write regime, adds Document Ownership and the playbook
  candidate collection). v2.2 added the Publication Contract and Cross-Branch
  Visibility; v2.0 renamed the document pair to `design_`/`plan_` and added the
  Architect Review Gate; v1 (mb-plan/mb-act orchestration) remains superseded.
  See `VENDORED_FROM.md` for the vendored Superpowers version.
```

- [ ] **Step 2: Opravit výčet dokumentů v Three-Tier Directory Model**

V odrážce `**PLAN_MB**` nahradit `(brief.md, product.md, architecture.md,
tech.md, tasks.md)` textem:

```markdown
  documents (`brief.md`, `architecture.md`, `tech.md`, and optionally
  `playbook.md` — see Memory Bank Document Set).
```

- [ ] **Step 3: Vložit sekci `## Memory Bank Document Set`**

Vložit celou novou sekci BEZPROSTŘEDNĚ PŘED existující řádek
`## Scope Lock (Memory Bank documents only)`:

```markdown
## Memory Bank Document Set

**Mandatory core of a project MB:** `brief.md`, `architecture.md`, `tech.md`.

**First-class optional:** `playbook.md` — prescriptive procedures (see
Document Ownership and the Playbook Contract below).

**Free extension:** any further document the MB needs (`data-flows.md`,
`use-cases.md`, `open-questions.md`, `tasks.md`, …). These carry no normative
status; skills update them when they exist and never create them speculatively.

The orchestration root (`CTX_DIR`) is NOT bound by the core — it holds
`context.md` plus whatever navigation the orchestrated tree needs.

`brief.md` covers what earlier versions split between `brief.md` and
`product.md`. Canonical section order (sections without content are omitted,
never created empty):

```markdown
# Brief — <name>

## Co to je
## Klíčové funkce            (or Rozsah, depending on the component)
## Pro koho a hodnota
## Rizika
## Stav a historie
```

### Legacy shape tolerance

Permanent, like the `proposal_` grandfather clause. No MB is forced to migrate
in order to stay valid.

- **Reading:** when `product.md` exists, read it as well. When `playbook.md`
  is absent and `tasks.md` exists, read `tasks.md` in its place.
- **Writing procedures:** into `playbook.md` when it exists; otherwise into
  `tasks.md` when it exists; otherwise create `playbook.md`.
- Migration to the current shape is performed by the `mb-migrate-docs` skill,
  never as a side effect of unrelated work.

### Playbook Contract

`playbook.md` is prescriptive: **how this project is built, tested and
changed.** Authored by humans and by experience, not derived from code.

**Write regime — consult before writing.** `playbook.md` is NEVER changed
without the user's approval. An agent may propose anything — add an entry, fix
a superseded procedure, rephrase it, delete one that stopped being true — but
every change is presented for approval before it is written. The rule binds
every writer, `mb-sync` included. The automatic current-state pass that
`brief.md`, `architecture.md` and `tech.md` undergo (Harvest Contract §3) does
NOT apply here: the content does not come from code, so it cannot be verified
against code either.

**Entry format** is free (heading + steps). When a persisted candidate carried
evidence, a one-line `Proč:` travels with it — the reason is part of the
procedure, not noise.

**Candidate collection during work.** Procedural knowledge is gathered while
the work happens, into `<MB_ROOT>/.superpowers/playbook-candidates.md`
(git-ignored scratch, English, first line
`# Playbook candidates — work item: <slug>`). A foreign slug means foreign
work: leave that file alone and start a new one.

Writers: implementer subagents report candidates in their report section
`## Playbook candidates`; the orchestrator COPIES confirmed ones into the
collection file without rephrasing; sessions outside SDD write directly.

Candidate format — the first three fields are mandatory, an entry missing any
of them is not written:

```markdown
## <short title>
- **Tried:** <what was attempted>
- **Happened:** <what actually happened — the evidence>
- **Procedure:** <the rule that follows from it>
- **Target MB:** <path>/memory-bank/        (only when harvest spans several MBs)
- **Corrects:** <existing playbook entry>   (when it contradicts an entry already there)
```

The ban on invention is enforced by the FORMAT, not by a request in a prompt:
without `Happened` there is no entry.
```

- [ ] **Step 4: Vložit sekci `## Document Ownership`**

Vložit BEZPROSTŘEDNĚ PŘED existující řádek `## Harvest Contract`:

```markdown
## Document Ownership

One fact, one home. Duplication between documents is prevented by ownership,
not by asking writers to be careful.

| The question the fact answers | Home |
|---|---|
| What it is for, for whom, what value it has, what state it is in | `brief.md` |
| What parts it consists of, who talks to whom and how, which pattern it follows | `architecture.md` |
| What it runs on and with — stack, versions, dependencies, configuration, build, deployment | `tech.md` |
| How do I do X — commands, procedures, conventions, traps | `playbook.md` |

**Decision test for the contested `tech` × `architecture` pair** —
deliberately a test, not a taxonomy, because a taxonomy can be bent:

- Does the fact change when you **swap a library or version and leave the code
  alone**? → `tech.md`
- Does it change when you **rewrite the code and leave the dependencies
  alone**? → `architecture.md`
- Does it change in **both** cases (typically "the workflow engine runs on
  Orleans")? → it belongs where the reader looks first, and the other document
  **links** to it with a relative link. It never restates it.

The third case carries the rule. Duplication does not arise for facts that
clearly belong somewhere — it arises for the ones that belong in both.

**Moving a fact is a legal operation.** `mb-harvest` and `mb-sync` may move a
fact between documents of the same MB. The order is binding: **write into the
target first, only then delete from the source.** Every move is named in the
skill's report, so it is visible both there and in the commit diff. This is
deliberately visibility, not a mechanical check — a move is a local edit
someone reads at commit time.
```

- [ ] **Step 5: Aktualizovat MB Context Reading Rule**

V sekci `## MB Context Reading Rule` nahradit první odstavec:

```markdown
Before proposing approaches (brainstorming) and before writing the
implementation plan, read `<PLAN_MB>/brief.md`, `architecture.md`, `tech.md`
and `playbook.md` (those that exist; legacy shape per Memory Bank Document
Set), plus the root `memory-bank/architecture.md` and `tech.md` when the work
is cross-cutting. `playbook.md` is prescriptive — its procedures BIND the work,
they are not background reading. The rest is current-state reference: treat it
as authoritative context, and note in the design when it is stale (the fix for
staleness is `mb-sync` or the harvest at finish, not ad-hoc edits).
```

- [ ] **Step 6: Přepsat Harvest Contract §3**

Nahradit celý bod 3 (`**Harvest style — CURRENT-STATE (MANDATORY):** …` až po
odrážku `Continue with remaining affected MBs …`):

```markdown
3. **Harvest style — CURRENT-STATE (MANDATORY):** the current-state documents
   (`architecture.md`, `tech.md`, `brief.md`) describe the current state in
   present tense, as reference documentation. They are NOT a changelog.
   `playbook.md` is NOT one of them — it changes only through the gate below.
   - Place every fact in its owning document (see Document Ownership); fold it
     into the relevant current-state section and do not duplicate a fact that
     is already described elsewhere.
   - DO NOT create or append dated changelog sections ("Nedávné změny",
     "Recent Changes", "Changelog", "Historie změn", "Naposledy provedeno").
   - History lives in `proposals/completed/` and git — never in state docs.
   - When a change removes something, describe the new state; do not narrate
     the removal.
   - Continue with remaining affected MBs if one update fails; capture
     failures for the final report.

   **Staleness sweep (cheap, MANDATORY):** for each affected MB, grep ALL its
   `memory-bank/*.md` documents for the key symbols, element ids and variable
   names touched by the branch diff. Each hit has one of three outcomes:
   1. the hit describes a **superseded** state → fold it to current state;
   2. the hit is the fact's **existing home** → do not write a second copy;
      update it in place;
   3. the hit sits in the **wrong home** → move it per Document Ownership.

   One pass therefore detects staleness and duplication alike. Report every
   move.

   **Playbook gate (the only non-autonomous step of the harvest):** when
   `<MB_ROOT>/.superpowers/playbook-candidates.md` is non-empty AND its slug
   matches the current work item, present the candidates with their evidence
   to the user ONCE and let them choose. Approved ones are translated into
   Czech and written to `playbook.md` of the target MB — or of the MB named by
   the candidate's `Target MB` field. A candidate carrying `Corrects` is
   presented NEXT TO the entry it contradicts, and the user decides between
   replacing it, keeping both, or dropping the candidate. Unapproved
   candidates vanish with the scratch; report their count. An empty or foreign
   collection file skips the gate without a question.
```

- [ ] **Step 7: Doplnit sběrný soubor do Scope Locku a jazyk do Language Contract**

V sekci `## Scope Lock (Memory Bank documents only)`, v odrážce o
`<MB_ROOT>/.superpowers/`, doplnit `playbook-candidates.md` do závorky:

```markdown
- The superpowers scratch tree `<MB_ROOT>/.superpowers/` (task briefs,
  implementer reports, review packages, progress ledger,
  `playbook-candidates.md`) — git-ignored, ephemeral, owned by the superpowers
  execution skills and the Playbook Contract.
```

V sekci `## Language Contract` doplnit za odrážku o AI-facing textu:

```markdown
- `playbook-candidates.md` is AI-facing scratch and is therefore English;
  `playbook.md` is a persistent artifact and is therefore Czech. The harvest
  gate translates on persistence.
```

- [ ] **Step 8: Ověřit konzistenci**

Run:
```bash
grep -n "product.md\|tasks.md" ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md
```
Expected: všechny zásahy leží v sekci `## Memory Bank Document Set` (výčet
volné nástavby a pravidla tolerance staré podoby). Žádný zásah v Three-Tier
Directory Model, MB Context Reading Rule ani Harvest Contract.

Run:
```bash
grep -c "Contract-Version:\*\* 2.3" ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md
```
Expected: `1`

- [ ] **Step 9: Commit**

```bash
git add ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md
git commit -m "UMS: kontrakt 2.3 — sada dokumentů, playbook a vlastnictví faktu"
```

---

### Task 2: Migrační skript — mechanická fáze

**Files:**
- Create: `ums/.claude/skills/mb-migrate-docs/scripts/migrate-mb-docs.ps1`
- Create: `ums/.claude/skills/mb-migrate-docs/tests/_assert.ps1`
- Create: `ums/.claude/skills/mb-migrate-docs/tests/new-fixture-repo.ps1`
- Create: `ums/.claude/skills/mb-migrate-docs/tests/migrate.tests.ps1`

**Interfaces:**
- Consumes: nic z Tasku 1 (skript nečte kontrakt).
- Produces:
  - `migrate-mb-docs.ps1` s parametry
    `-RepoPath <string>`, `-Path <string>`, `-Apply <switch>`,
    `-Json <string>`.
  - JSON tvar: `{ generated, repo, mbs: [ { path, merged, renamed, notes } ],
    findings: [ { code, severity, message } ] }`, kde `merged` je `bool`
    (proběhlo sloučení `product.md` → `brief.md`) a `renamed` je `bool`
    (`tasks.md` → `playbook.md`).
  - Exit kódy `0` / `1` / `2`.
  - `tests/_assert.ps1` s funkcemi `Assert-True`, `Assert-Match`,
    `Assert-NotMatch`, `Assert-Eq`, `Complete-Tests`.
  - `tests/new-fixture-repo.ps1` s funkcí `New-FixtureRepo` vracející
    `@{ Work = <path>; Origin = <path> }`.

- [ ] **Step 1: Zkopírovat asertační helper**

```bash
mkdir -p ums/.claude/skills/mb-migrate-docs/tests ums/.claude/skills/mb-migrate-docs/scripts
cp ums/.claude/skills/mb-doc-index/tests/_assert.ps1 ums/.claude/skills/mb-migrate-docs/tests/_assert.ps1
```

Pak v kopii nahradit první řádek a funkci `Invoke-Index` takto (zbytek souboru
zůstává beze změny):

```powershell
# Dependency-free assertion helper for mb-migrate-docs tests.
```

```powershell
# Runs a script of this skill out-of-process; returns @{ Out=<stdout>; Code=<exit code> }.
function Invoke-Script([string] $Name, [string[]] $ScriptArgs) {
    $script = Join-Path $PSScriptRoot "..\scripts\$Name"
    try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
    $out = & pwsh -NoProfile -File $script @ScriptArgs 2>&1 | Out-String
    return @{ Out = $out; Code = $LASTEXITCODE }
}
```

- [ ] **Step 2: Napsat fixturu**

Vytvořit `ums/.claude/skills/mb-migrate-docs/tests/new-fixture-repo.ps1`:

```powershell
# Builds an offline fixture repo with Memory Banks in the legacy and the
# current shape, plus the conflict and link-rewrite cases.
# Returns @{ Work=<path>; Origin=<path> }.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-Git([string] $RepoDir, [string[]] $GitArgs) {
    $out = & git -C $RepoDir -c user.name=Test -c user.email=test@example.com @GitArgs 2>&1
    if ($LASTEXITCODE -ne 0) { throw "git $($GitArgs -join ' ') failed: $out" }
    return $out
}

function Add-File([string] $RepoDir, [string] $RelPath, [string[]] $Lines) {
    $full = Join-Path $RepoDir $RelPath
    New-Item -ItemType Directory -Force -Path (Split-Path $full) | Out-Null
    Set-Content -LiteralPath $full -Encoding UTF8 -Value $Lines
    Invoke-Git $RepoDir @('add', '--', $RelPath) | Out-Null
}

function New-FixtureRepo {
    $root = Join-Path ([IO.Path]::GetTempPath()) ("mbmig-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $origin = Join-Path $root 'origin.git'
    $work = Join-Path $root 'work'
    New-Item -ItemType Directory -Force -Path $origin, $work | Out-Null
    & git init --bare -b develop $origin | Out-Null
    & git init -b develop $work | Out-Null
    Invoke-Git $work @('remote', 'add', 'origin', $origin) | Out-Null

    # A: legacy shape, the full case — brief + product + tasks, with a link
    #    from architecture.md into both files that must be rewritten.
    Add-File $work 'A/memory-bank/brief.md' @(
        '# Brief - A', '', '## Cíl projektu', 'Komponenta A dělá věci.',
        'Sdílená věta o třech variantách DLL.')
    Add-File $work 'A/memory-bank/product.md' @(
        '# Product - A', '', '## Pro koho', 'Pro vývojáře.',
        'Sdílená věta o třech variantách DLL.', '',
        '### Detail', 'Podrobnost.', '', '```bash', '# tohle není nadpis', 'echo ahoj', '```')
    Add-File $work 'A/memory-bank/tasks.md' @(
        '# Tasks - A', '', '## Postup: build', 'Spusť msbuild.')
    Add-File $work 'A/memory-bank/architecture.md' @(
        '# Architektura - A', '', 'Viz [product](product.md) a [tasks](tasks.md).')

    # B: already migrated — nothing to do, proves idempotence.
    Add-File $work 'B/memory-bank/brief.md' @('# Brief - B', '', 'Hotovo.')
    Add-File $work 'B/memory-bank/architecture.md' @('# Architektura - B')
    Add-File $work 'B/memory-bank/tech.md' @('# Tech - B')
    Add-File $work 'B/memory-bank/playbook.md' @('# Playbook - B')

    # C: conflict — both tasks.md and playbook.md exist.
    Add-File $work 'C/memory-bank/brief.md' @('# Brief - C')
    Add-File $work 'C/memory-bank/tasks.md' @('# Tasks - C')
    Add-File $work 'C/memory-bank/playbook.md' @('# Playbook - C')

    # D: product.md without brief.md — rename path.
    Add-File $work 'D/memory-bank/product.md' @('# Product - D', '', 'Jen produkt.')

    # E: fixture path — must be skipped entirely.
    Add-File $work 'E/tests/fixtures/memory-bank/product.md' @('# Product - fixture')
    Add-File $work 'E/tests/fixtures/memory-bank/brief.md' @('# Brief - fixture')

    Invoke-Git $work @('commit', '-m', 'fixture') | Out-Null
    Invoke-Git $work @('push', '-u', 'origin', 'develop') | Out-Null
    return @{ Work = $work; Origin = $origin }
}
```

- [ ] **Step 3: Napsat testy mechanické fáze (musí selhat)**

Vytvořit `ums/.claude/skills/mb-migrate-docs/tests/migrate.tests.ps1`:

```powershell
#Requires -Version 7
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_assert.ps1')
. (Join-Path $PSScriptRoot 'new-fixture-repo.ps1')

$fx = New-FixtureRepo
$work = $fx.Work

Write-Host "== Plan mode (default) =="
$r = Invoke-Script 'migrate-mb-docs.ps1' @('-RepoPath', $work)
Assert-Eq $r.Code 2 'Plan hlásí konflikt v C -> exit 2'
Assert-Match $r.Out 'A[/\\]memory-bank' 'Plan jmenuje MB A'
Assert-Match $r.Out 'KONFLIKT PLAYBOOKU' 'Plan hlásí konflikt playbooku'
Assert-True (Test-Path (Join-Path $work 'A/memory-bank/product.md')) 'Plan nic nemaže'

Write-Host "== Apply =="
$json = Join-Path ([IO.Path]::GetTempPath()) ("mbmig-" + [guid]::NewGuid().ToString('N').Substring(0,8) + '.json')
$r = Invoke-Script 'migrate-mb-docs.ps1' @('-RepoPath', $work, '-Apply', '-Json', $json)
Assert-Eq $r.Code 2 'Apply doběhne, ale konflikt v C drží exit 2'

$briefA = Get-Content -LiteralPath (Join-Path $work 'A/memory-bank/brief.md') -Raw
Assert-Match $briefA '## Produktový pohled' 'A: vložen nadpis produktového pohledu'
Assert-Match $briefA '### Pro koho' 'A: nadpisy produktu posunuty o úroveň'
Assert-Match $briefA '#### Detail' 'A: vnořený nadpis posunut také'
Assert-NotMatch $briefA '(?m)^## Product - A$' 'A: H1 produktu zahozen, ne posunut'
Assert-Match $briefA '(?m)^# tohle není nadpis$' 'A: řádek uvnitř fence se neposouvá'
Assert-True (-not (Test-Path (Join-Path $work 'A/memory-bank/product.md'))) 'A: product.md odstraněn'
Assert-True (Test-Path (Join-Path $work 'A/memory-bank/playbook.md')) 'A: tasks.md přejmenován na playbook.md'
Assert-True (-not (Test-Path (Join-Path $work 'A/memory-bank/tasks.md'))) 'A: tasks.md už neexistuje'

$archA = Get-Content -LiteralPath (Join-Path $work 'A/memory-bank/architecture.md') -Raw
Assert-Match $archA '\[product\]\(brief\.md\)' 'A: odkaz na product.md přepsán na brief.md'
Assert-Match $archA '\[tasks\]\(playbook\.md\)' 'A: odkaz na tasks.md přepsán na playbook.md'

Assert-True (Test-Path (Join-Path $work 'C/memory-bank/tasks.md')) 'C: konfliktní tasks.md zůstal'
Assert-True (Test-Path (Join-Path $work 'D/memory-bank/brief.md')) 'D: product.md přejmenován na brief.md'
Assert-True (-not (Test-Path (Join-Path $work 'D/memory-bank/product.md'))) 'D: product.md už neexistuje'
Assert-Match $r.Out 'PRODUCT BEZ BRIEFU' 'D: hlášeno varování o chybějícím briefu'
Assert-True (Test-Path (Join-Path $work 'E/tests/fixtures/memory-bank/product.md')) 'E: fixture cesta přeskočena'

$idx = Get-Content -LiteralPath $json -Raw | ConvertFrom-Json
$mbA = $idx.mbs | Where-Object { $_.path -match 'A[/\\]memory-bank' }
Assert-Eq $mbA.merged $true 'JSON: A má merged=true'
Assert-Eq $mbA.renamed $true 'JSON: A má renamed=true'
$mbB = $idx.mbs | Where-Object { $_.path -match 'B[/\\]memory-bank' }
Assert-Eq $mbB.merged $false 'JSON: B nic neslučovalo'

Write-Host "== Staging =="
$staged = (& git -C $work diff --cached --name-only) -join "`n"
Assert-Match $staged 'A/memory-bank/brief.md' 'Sloučený brief.md je ve stagingu'
Assert-Match $staged 'A/memory-bank/product.md' 'Odstranění product.md je ve stagingu'

Write-Host "== Idempotence =="
Invoke-Git $work @('commit', '-m', 'migrace') | Out-Null
$r2 = Invoke-Script 'migrate-mb-docs.ps1' @('-RepoPath', $work)
Assert-Match $r2.Out 'A[/\\]memory-bank.*(hotovo|beze změny)' 'Druhý běh hlásí A jako hotovou'
Assert-NotMatch $r2.Out '(?m)^\s*\|\s*A[/\\]memory-bank\s*\|\s*sloučit' 'Druhý běh už neplánuje sloučení'

Write-Host "== Špinavý strom =="
Set-Content -LiteralPath (Join-Path $work 'B/memory-bank/brief.md') -Encoding UTF8 -Value @('# Brief - B', 'změna')
$r3 = Invoke-Script 'migrate-mb-docs.ps1' @('-RepoPath', $work, '-Apply')
Assert-Eq $r3.Code 1 'Apply nad špinavým stromem končí chybou'
Assert-Match $r3.Out 'pracovní strom' 'Zpráva jmenuje pracovní strom'

Complete-Tests
```

- [ ] **Step 4: Spustit testy a ověřit, že selžou**

Run: `pwsh -NoProfile -File ums/.claude/skills/mb-migrate-docs/tests/migrate.tests.ps1`
Expected: FAIL — `migrate-mb-docs.ps1` neexistuje.

- [ ] **Step 5: Napsat skript**

Vytvořit `ums/.claude/skills/mb-migrate-docs/scripts/migrate-mb-docs.ps1`.
Klíčové části, které MUSÍ být implementované přesně takto:

```powershell
#Requires -Version 7
<#
.SYNOPSIS
Mechanical migration of Memory Bank documents to the current document set.

.DESCRIPTION
Merges product.md into brief.md, renames tasks.md to playbook.md and rewrites
relative links. Moves text only — never authors a sentence. Idempotent: an MB
already in the current shape is skipped. Stages its changes (git add/mv/rm) but
never commits.

.PARAMETER RepoPath
Repository root. Defaults to the toplevel of the current directory.

.PARAMETER Path
Optional repo-relative subtree to limit the scan to.

.PARAMETER Apply
Perform the changes. Without it the script only reports the plan.

.PARAMETER Json
Optional path to also write the result as JSON.

.OUTPUTS
Czech table + findings. Exit: 0 = OK, 1 = input/script failure, 2 = blocking
conflict.
#>
[CmdletBinding()]
param(
    [string] $RepoPath = '',
    [string] $Path = '',
    [switch] $Apply,
    [string] $Json = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
$script:ExitCode = 0
```

Posun nadpisů se sledováním fenced bloků — bez toho by se komentáře uvnitř
```` ``` ```` bloků považovaly za nadpisy:

```powershell
function Get-ProductBody([string[]] $Lines) {
    # Drop leading blanks and the leading H1, then demote every heading one
    # level. Lines inside fenced blocks are never touched.
    $i = 0
    while ($i -lt $Lines.Count -and $Lines[$i].Trim() -eq '') { $i++ }
    if ($i -lt $Lines.Count -and $Lines[$i] -match '^#\s') { $i++ }
    while ($i -lt $Lines.Count -and $Lines[$i].Trim() -eq '') { $i++ }

    $out = [System.Collections.Generic.List[string]]::new()
    $inFence = $false
    for (; $i -lt $Lines.Count; $i++) {
        $line = $Lines[$i]
        if ($line -match '^\s*```') { $inFence = -not $inFence; $out.Add($line); continue }
        if (-not $inFence -and $line -match '^(#{1,5})(\s.*)$') {
            $out.Add('#' + $Matches[1] + $Matches[2])
        } else {
            $out.Add($line)
        }
    }
    return $out.ToArray()
}
```

Přepis odkazů — přepisuje se JEN tehdy, když cíl odkazu už neexistuje a
náhrada ano. Tím se nikdy nepřepíše odkaz do MB, která zatím nemigrovala:

```powershell
function Update-Links([string] $MdFile, [hashtable] $Map) {
    # $Map: 'product.md' -> 'brief.md', 'tasks.md' -> 'playbook.md'
    # Returns $true when the file was rewritten.
    $dir = Split-Path -Parent $MdFile
    $text = Get-Content -LiteralPath $MdFile -Raw
    if ($null -eq $text) { return $false }
    $original = $text
    foreach ($old in $Map.Keys) {
        $new = $Map[$old]
        $pattern = '\]\(([^)]*?)' + [regex]::Escape($old) + '\)'
        $text = [regex]::Replace($text, $pattern, {
            param($m)
            $prefix = $m.Groups[1].Value
            $oldTarget = Join-Path $dir ($prefix + $old)
            $newTarget = Join-Path $dir ($prefix + $new)
            # Rewrite ONLY when the old target is gone and the new one exists.
            # That is what keeps links into a not-yet-migrated MB untouched.
            if ((-not (Test-Path -LiteralPath $oldTarget)) -and (Test-Path -LiteralPath $newTarget)) {
                return '](' + $prefix + $new + ')'
            }
            return $m.Value
        })
    }
    if ($text -eq $original) { return $false }
    [IO.File]::WriteAllText($MdFile, $text, [Text.UTF8Encoding]::new($false))
    return $true
}
```

Volá se po přesunech, nad VŠEMI `*.md` pod všemi nalezenými `memory-bank/`
kořeny (odkazy vedou i napříč MB), a každý přepsaný soubor se stageuje.

Ostatní požadavky na skript:

- Výčet MB: `git -C <repo> ls-files --cached --others --exclude-standard`
  filtrovaný na cesty obsahující `/memory-bank/`, z nich odvozené unikátní
  kořeny; vyloučit cesty odpovídající `*/tests/fixtures/*`. Po nativním volání
  ihned zkontrolovat `$LASTEXITCODE` a při nenulovém skončit s exit 1.
- `-Apply` nad špinavým pracovním stromem (`git status --porcelain` neprázdné)
  = STOP, exit 1, česká zpráva jmenující pracovní strom. Důvod: staging slouží
  jako snímek pro verifikátor a `git checkout --` jako obnova.
- Sloučení: obsah `brief.md`, prázdný řádek, prázdný řádek,
  `## Produktový pohled`, prázdný řádek, výstup `Get-ProductBody`. Zapsat
  UTF-8 bez BOM, pak `git add` sloučeného souboru a `git rm` produktu.
- `product.md` bez `brief.md`: `git mv product.md brief.md` + nález
  `PRODUCT BEZ BRIEFU` (VAROVÁNÍ) — nadpis souboru zůstává „Product", což
  musí zkontrolovat člověk.
- `tasks.md` + existující `playbook.md`: nález `KONFLIKT PLAYBOOKU` (CHYBA),
  MB se přeskočí, `$script:ExitCode = 2`.
- Tabulka: sloupce `MB`, `Akce`, `Poznámka`. Řetězce akcí jsou závazné, protože
  na ně míří testy: `sloučit product.md`, `přejmenovat tasks.md`,
  `beze změny (hotovo)`, `přeskočeno (konflikt)`. Když MB potřebuje obojí,
  akce je `sloučit product.md + přejmenovat tasks.md`.
- Nálezy se tisknou pod tabulkou ve tvaru `- [SEVERITA] KÓD: zpráva`,
  severity `CHYBA` / `VAROVÁNÍ` / `INFO`, stejně jako u `doc-index.ps1`.
- `-Json` zapíše popsaný tvar i v režimu bez `-Apply`.

- [ ] **Step 6: Spustit testy a ověřit, že projdou**

Run: `pwsh -NoProfile -File ums/.claude/skills/mb-migrate-docs/tests/migrate.tests.ps1`
Expected: PASS, poslední řádek `<N> passed`.

- [ ] **Step 7: Commit**

```bash
git add ums/.claude/skills/mb-migrate-docs/scripts/migrate-mb-docs.ps1 ums/.claude/skills/mb-migrate-docs/tests/
git commit -m "UMS: mb-migrate-docs — mechanická fáze migrace MB dokumentů"
```

---

### Task 3: Verifikátor mazacího režimu

**Files:**
- Create: `ums/.claude/skills/mb-migrate-docs/scripts/verify-deletion-only.ps1`
- Create: `ums/.claude/skills/mb-migrate-docs/tests/verify.tests.ps1`

**Interfaces:**
- Consumes: `Invoke-Script` a `New-FixtureRepo` z Tasku 2.
- Produces: `verify-deletion-only.ps1` s parametry `-RepoPath <string>`,
  `-File <string>` (cesta relativní ke kořeni repa). Originál čte ze
  **stagingu** (`git show :<file>`), kandidáta z pracovního stromu. Exit `0`
  vyhovuje, `2` porušeno, `1` chyba.

- [ ] **Step 1: Napsat testy (musí selhat)**

Vytvořit `ums/.claude/skills/mb-migrate-docs/tests/verify.tests.ps1`:

```powershell
#Requires -Version 7
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_assert.ps1')
. (Join-Path $PSScriptRoot 'new-fixture-repo.ps1')

$fx = New-FixtureRepo
$work = $fx.Work
$rel = 'A/memory-bank/brief.md'
$full = Join-Path $work $rel
$orig = Get-Content -LiteralPath $full

function Reset-Candidate { Set-Content -LiteralPath $full -Encoding UTF8 -Value $orig }

Write-Host "== Beze změny projde =="
$r = Invoke-Script 'verify-deletion-only.ps1' @('-RepoPath', $work, '-File', $rel)
Assert-Eq $r.Code 0 'Nezměněný soubor vyhovuje'

Write-Host "== Smazání projde =="
Set-Content -LiteralPath $full -Encoding UTF8 -Value ($orig | Select-Object -First 2)
$r = Invoke-Script 'verify-deletion-only.ps1' @('-RepoPath', $work, '-File', $rel)
Assert-Eq $r.Code 0 'Smazání řádků vyhovuje'

Write-Host "== Přeskupení projde =="
Set-Content -LiteralPath $full -Encoding UTF8 -Value ($orig | Sort-Object)
$r = Invoke-Script 'verify-deletion-only.ps1' @('-RepoPath', $work, '-File', $rel)
Assert-Eq $r.Code 0 'Přeskupení řádků vyhovuje'

Write-Host "== Nový řádek neprojde =="
Reset-Candidate
Add-Content -LiteralPath $full -Encoding UTF8 -Value 'Tuhle větu nikdo nenapsal.'
$r = Invoke-Script 'verify-deletion-only.ps1' @('-RepoPath', $work, '-File', $rel)
Assert-Eq $r.Code 2 'Přidaný řádek je porušení'
Assert-Match $r.Out 'Tuhle větu nikdo nenapsal' 'Porušující řádek je ve zprávě'

Write-Host "== Změna uvnitř řádku neprojde =="
Reset-Candidate
$mutated = $orig | ForEach-Object { $_ -replace 'Komponenta A dělá věci\.', 'Komponenta A dělá jiné věci.' }
Set-Content -LiteralPath $full -Encoding UTF8 -Value $mutated
$r = Invoke-Script 'verify-deletion-only.ps1' @('-RepoPath', $work, '-File', $rel)
Assert-Eq $r.Code 2 'Přeformulovaný řádek je porušení'

Write-Host "== Delší výstup než vstup neprojde =="
Reset-Candidate
Add-Content -LiteralPath $full -Encoding UTF8 -Value ($orig[0])
$r = Invoke-Script 'verify-deletion-only.ps1' @('-RepoPath', $work, '-File', $rel)
Assert-Eq $r.Code 2 'Duplikovaný řádek zvyšuje počet řádků -> porušení'

Write-Host "== Prázdný výstup neprojde =="
Set-Content -LiteralPath $full -Encoding UTF8 -Value @()
$r = Invoke-Script 'verify-deletion-only.ps1' @('-RepoPath', $work, '-File', $rel)
Assert-Eq $r.Code 2 'Prázdný soubor je porušení'

Write-Host "== Ztráta H1 neprojde =="
Set-Content -LiteralPath $full -Encoding UTF8 -Value ($orig | Where-Object { $_ -notmatch '^#\s' })
$r = Invoke-Script 'verify-deletion-only.ps1' @('-RepoPath', $work, '-File', $rel)
Assert-Eq $r.Code 2 'Smazaný H1 nadpis je porušení'

Write-Host "== Varování při velkém úbytku =="
Reset-Candidate
Set-Content -LiteralPath $full -Encoding UTF8 -Value @($orig[0])
$r = Invoke-Script 'verify-deletion-only.ps1' @('-RepoPath', $work, '-File', $rel)
Assert-Eq $r.Code 0 'Velký úbytek stále vyhovuje'
Assert-Match $r.Out 'VAROVÁNÍ' 'Velký úbytek je hlášen jako varování'

Write-Host "== Obnova stagingem =="
& git -C $work checkout -- $rel
$restored = Get-Content -LiteralPath $full
Assert-Eq ($restored -join "`n") ($orig -join "`n") 'git checkout -- obnoví mechanickou verzi'

Complete-Tests
```

- [ ] **Step 2: Spustit testy a ověřit, že selžou**

Run: `pwsh -NoProfile -File ums/.claude/skills/mb-migrate-docs/tests/verify.tests.ps1`
Expected: FAIL — `verify-deletion-only.ps1` neexistuje.

- [ ] **Step 3: Napsat verifikátor**

Vytvořit `ums/.claude/skills/mb-migrate-docs/scripts/verify-deletion-only.ps1`.
Jádro:

```powershell
#Requires -Version 7
<#
.SYNOPSIS
Verifies that an agent only deleted and reordered lines of a Memory Bank
document — that it authored nothing.

.DESCRIPTION
The original is the STAGED blob (git show :<file>), written there by
migrate-mb-docs.ps1 -Apply; the candidate is the working-tree file the agent
edited. Every non-empty candidate line must occur verbatim among the original's
non-empty lines, the candidate must not be longer than the original, must not
be empty and must keep its H1 heading. On violation restore with
'git checkout -- <file>'.

.PARAMETER RepoPath
Repository root.

.PARAMETER File
Repo-relative path of the document to check.

.OUTPUTS
Czech verdict. Exit: 0 = passed, 1 = input/script failure, 2 = violation.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $RepoPath,
    [Parameter(Mandatory)] [string] $File
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }

$originalText = (& git -C $RepoPath show ":$File") -join "`n"
if ($LASTEXITCODE -ne 0) {
    Write-Error "Soubor '$File' není ve stagingu — verifikátor nemá s čím porovnávat."; exit 1
}
$original = $originalText -split "`r?`n"
$candidate = Get-Content -LiteralPath (Join-Path $RepoPath $File)
if ($null -eq $candidate) { $candidate = @() }

$origSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($line in $original) { [void] $origSet.Add($line.TrimEnd()) }

$violations = @()
foreach ($line in $candidate) {
    $t = $line.TrimEnd()
    if ($t -eq '') { continue }
    if (-not $origSet.Contains($t)) { $violations += $t }
}
```

Dále musí skript:

- při `$candidate.Count -gt $original.Count` přidat porušení
  `Výstup má víc řádků než vstup` (chytí duplikaci řádku, kterou samotná
  množinová kontrola propustí);
- při prázdném kandidátovi (žádný neprázdný řádek) přidat porušení;
- když originál obsahoval řádek `^#\s` a kandidát ne, přidat porušení;
- při jakémkoli porušení vypsat české nálezy včetně prvních až deseti
  porušujících řádků a skončit exit 2, s instrukcí
  `Obnov mechanickou verzi: git checkout -- <File>`;
- bez porušení vypsat počet ubraných řádků a při úbytku nad 50 %
  (`(orig-cand)/orig > 0.5`, počítáno z neprázdných řádků) vypsat
  `VAROVÁNÍ` a přesto skončit exit 0.

- [ ] **Step 4: Spustit testy a ověřit, že projdou**

Run: `pwsh -NoProfile -File ums/.claude/skills/mb-migrate-docs/tests/verify.tests.ps1`
Expected: PASS

- [ ] **Step 5: Regresní běh obou sad**

Run:
```bash
pwsh -NoProfile -File ums/.claude/skills/mb-migrate-docs/tests/migrate.tests.ps1
pwsh -NoProfile -File ums/.claude/skills/mb-migrate-docs/tests/verify.tests.ps1
```
Expected: obě PASS.

- [ ] **Step 6: Commit**

```bash
git add ums/.claude/skills/mb-migrate-docs/scripts/verify-deletion-only.ps1 ums/.claude/skills/mb-migrate-docs/tests/verify.tests.ps1
git commit -m "UMS: mb-migrate-docs — verifikátor mazacího režimu"
```

---

### Task 4: SKILL.md pro mb-migrate-docs

**Files:**
- Create: `ums/.claude/skills/mb-migrate-docs/SKILL.md`
- Modify: `ums/.claude/skills/shared/SKILLS_MANIFEST.md`

**Interfaces:**
- Consumes: rozhraní obou skriptů z Tasků 2 a 3 (parametry, exit kódy, JSON
  tvar).
- Produces: nic pro další úlohy kromě zmínky v manifestu.

- [ ] **Step 1: Napsat SKILL.md**

Vytvořit `ums/.claude/skills/mb-migrate-docs/SKILL.md` s frontmatterem ve
stejném tvaru jako `mb-doc-index/SKILL.md`:

```markdown
---
name: mb-migrate-docs
description: Use when a repository's Memory Banks still use the legacy document shape — product.md alongside brief.md, or tasks.md instead of playbook.md — and you want them migrated to the current document set (migrace MB dokumentů, sloučení product do brief, přejmenování tasks na playbook).
license: MIT
metadata:
  author: UMS Project
  version: "1.0"
---
```

Tělo skillu (anglicky) musí obsahovat:

- odkaz na kontrakt („especially Memory Bank Document Set and Document
  Ownership");
- **Action / Execution** hlavičku ve stylu ostatních `mb-*` skillů, s výslovným
  `⛔ GIT PROHIBITION: no git commit/push from this skill` (staging je
  povolený, protože ho dělají skripty);
- workflow o čtyřech krocích:

  1. **Plan** — `pwsh <skill>/scripts/migrate-mb-docs.ps1 [-RepoPath <repo>]
     [-Path <subtree>] -Json <tmp.json>` bez `-Apply`. Ukázat uživateli tabulku
     a nálezy. Exit 2 (`KONFLIKT PLAYBOOKU`) NENÍ důvod nepokračovat — konfliktní
     MB se přeskočí, ostatní se migrují; rozhodnutí o konfliktu patří člověku.
  2. **Apply** — po souhlasu uživatele stejný příkaz s `-Apply`. Vyžaduje čistý
     pracovní strom.
  3. **Agentní úklid** — pro každou MB z JSON s `merged: true` (a JEN pro ně)
     jeden dispatch na nejlevnějším tieru s tímto zadáním:

     > Read `<path>/brief.md`. It was mechanically assembled from two documents
     > and now repeats itself. Remove the duplication. You may ONLY delete whole
     > lines and reorder existing lines. You MUST NOT write a single new
     > sentence, rephrase a line, merge two sentences into one, or add a
     > heading — every line you leave must be byte-identical to a line that is
     > there now. When two lines say the same thing, delete the weaker one
     > whole. Write the result back to the same file. Reply with the number of
     > lines removed and nothing else.

     Po každém dispatchi spustit
     `pwsh <skill>/scripts/verify-deletion-only.ps1 -RepoPath <repo> -File <path>/brief.md`.
     Exit 2 → `git checkout -- <path>/brief.md` a MB označit jako neuklizenou.
     Exit 0 s `VAROVÁNÍ` → nechat, ale vypsat k lidské kontrole.
  4. **Report a commit** — česká tabulka (MB, sloučeno, přejmenováno, ubráno
     řádků, stav úklidu), seznam přeskočených konfliktů a neuklizených MB, pak
     nabídnout `mb-git-commit`.

- **Notes** sekci s: idempotencí (opakované spuštění v témže i jiném repu),
  poznámkou, že prózu srovná nejbližší harvest, a poznámkou, že
  `playbook.md` vzniklý přejmenováním se dál řídí Playbook Contract
  (konzultace před zápisem).

- [ ] **Step 2: Zapsat skill do manifestu**

V `ums/.claude/skills/shared/SKILLS_MANIFEST.md`, v tabulce
`## Aktivní mb-* skilly`, přidat jako poslední řádek:

```markdown
| mb-migrate-docs | [mb-migrate-docs/SKILL.md](../mb-migrate-docs/SKILL.md) | Migrace MB dokumentů na aktuální sadu (product.md → brief.md, tasks.md → playbook.md; mechanická fáze + mazací agent pod verifikátorem) |
```

Ve stejném souboru rozšířit popis kontraktu v tabulce `## Sdílené prostředky`
o nová témata — nahradit buňku popisu řádku „Kontrakt v2":

```markdown
| Kontrakt v2 | [shared/UMS_MEMORY_BANK_CONTRACT.md](UMS_MEMORY_BANK_CONTRACT.md) | MB_ROOT, sada dokumentů, vlastnictví faktu, work item (design+plan pár), Target-MB discovery, harvest a playbook gate, dispatch model policy, fail-closed |
```

- [ ] **Step 3: Ověřit**

Run:
```bash
grep -n "mb-migrate-docs" ums/.claude/skills/shared/SKILLS_MANIFEST.md
head -8 ums/.claude/skills/mb-migrate-docs/SKILL.md
```
Expected: manifest obsahuje nový řádek; frontmatter má `name: mb-migrate-docs`
a `version: "1.0"`.

- [ ] **Step 4: Commit**

```bash
git add ums/.claude/skills/mb-migrate-docs/SKILL.md ums/.claude/skills/shared/SKILLS_MANIFEST.md
git commit -m "UMS: skill mb-migrate-docs a jeho zápis do manifestu"
```

---

### Task 5: mb-harvest — sada, sweep, gate a přesuny

**Files:**
- Modify: `ums/.claude/skills/mb-harvest/SKILL.md`

**Interfaces:**
- Consumes: z Tasku 1 názvy sekcí `Memory Bank Document Set`,
  `Document Ownership`, znění Harvest Contract §3, cestu
  `<MB_ROOT>/.superpowers/playbook-candidates.md` a formát kandidáta.
- Produces: nic pro další úlohy.

- [ ] **Step 1: Zvednout verzi a doplnit hlavičku**

Ve frontmatteru změnit `version: "2.0"` na `version: "2.1"`.

V úvodním citátovém bloku doplnit odkaz na nové sekce:

```markdown
> Follow [UMS_MEMORY_BANK_CONTRACT](../shared/UMS_MEMORY_BANK_CONTRACT.md) —
> especially "Harvest Contract", "Memory Bank Document Set",
> "Document Ownership", "Active Work Item (Design + Plan Pair)" and
> "`context.md` Schema & Writers". This skill is the only IDLE-resetting writer
> of `context.md` besides `mb-abort`.
```

Řádek `**Execution:** Autonomous — no confirmation.` nahradit:

```markdown
**Execution:** Autonomous, with ONE exception — the playbook gate in step 3
asks the user which collected experiences to persist.
```

- [ ] **Step 2: Přepsat sekci 3 (Harvest)**

Nahradit výčet dokumentů a odstavec o stylu:

```markdown
Code is the source of truth; the proposal pair is a navigation guide. Read the
actually modified/created files, then update per affected MB, placing every
fact in its owning document (contract, Document Ownership):

- `brief.md` — purpose, value, scope, product risks, state; only when those
  changed
- `architecture.md` — components, responsibilities, relations, patterns,
  diagrams, cross-project links
- `tech.md` — stack, versions, dependencies, configuration, build and
  deployment notes
- `playbook.md` — NOT updated here; it changes only through the playbook gate
  below

When a fact sits in the wrong document, MOVE it: write into the target first,
then delete from the source, and name the move in the final report.

Legacy shape: when `product.md` still exists, read it and keep it consistent;
migrating it is `mb-migrate-docs`' job, not a side effect of this harvest.

Style rules (contract, Harvest Contract §3): present tense, fold facts into
existing sections, no duplication, **no changelog sections** ("Nedávné změny",
"Recent Changes", "Historie změn", …), describe the new state instead of
narrating removals. History lives in `proposals/completed/` and git.
```

- [ ] **Step 3: Přepsat staleness sweep na tři výústění**

Nahradit odstavec `**Staleness sweep (cheap, MANDATORY):** …`:

```markdown
**Staleness sweep (cheap, MANDATORY):** for each affected MB, grep ALL its
`memory-bank/*.md` documents (not just architecture/tech) for the key symbols,
element ids and variable names touched by the branch diff. Every hit gets one
of three verdicts:

1. **Superseded** — the passage describes a state that no longer holds → fold
   it to current state.
2. **Existing home** — the passage is where this fact already lives → do NOT
   write a second copy elsewhere; update it in place.
3. **Wrong home** — the fact sits in a document that does not own it
   (contract, Document Ownership) → move it, target first.

One pass therefore catches both staleness (a walkthrough still describing
pre-refactor names) and duplication (the same fact drifting into two
documents).
```

- [ ] **Step 4: Vložit playbook gate**

Vložit jako novou podsekci na konec části 3, hned za staleness sweep:

```markdown
**Playbook gate (the only non-autonomous step):** read
`<MB_ROOT>/.superpowers/playbook-candidates.md`.

- Missing, empty, or carrying a foreign work-item slug → skip silently, no
  question.
- Otherwise present ALL candidates to the user in ONE Czech list: for each, the
  proposed procedure and its evidence (`Tried` / `Happened`). A candidate with
  `Corrects` is shown NEXT TO the existing `playbook.md` entry it contradicts,
  with three choices: replace / keep both / drop.
- Write only what the user approved, translated into Czech, into
  `playbook.md` of the target MB — or of the MB named by the candidate's
  `Target MB` field. Create `playbook.md` when it does not exist; write into
  `tasks.md` instead when that is the MB's legacy shape (contract, Memory Bank
  Document Set).
- Keep a persisted candidate's evidence as a one-line `Proč:`.
- Report the number of candidates the user did not approve. They vanish with
  the scratch file — do not re-ask.
```

- [ ] **Step 5: Rozšířit hlášení**

V sekci 6 (Announce) doplnit dva řádky do výčtu:

```markdown
> - Přesuny faktů mezi dokumenty: … (nebo „žádné")
> - Playbook: zapsáno <N> zkušeností do `<MB>/playbook.md`, neschváleno <M>
```

- [ ] **Step 6: Ověřit**

Run:
```bash
grep -n "product.md\|playbook" ums/.claude/skills/mb-harvest/SKILL.md
```
Expected: `product.md` jen v odstavci o legacy podobě; `playbook` v seznamu
dokumentů, v gate a v hlášení.

- [ ] **Step 7: Commit**

```bash
git add ums/.claude/skills/mb-harvest/SKILL.md
git commit -m "UMS: mb-harvest — playbook gate, sweep se třemi výústěními a přesuny faktů"
```

---

### Task 6: Overlay fragmenty

**Files:**
- Modify: `ums/.claude/skills/shared/overlays/subagent-driven-development.overlay.md`
- Modify: `ums/.claude/skills/shared/overlays/finishing-a-development-branch.overlay.md`

**Interfaces:**
- Consumes: z Tasku 1 cestu sběrného souboru a formát kandidáta; z Tasku 5
  existenci playbook gate v `mb-harvest`.
- Produces: nic pro další úlohy.

- [ ] **Step 1: Rozšířit SDD overlay**

Do bloku `<!-- UMS-OVERLAY BEGIN (ums-memory-bank v2) -->` v
`subagent-driven-development.overlay.md` přidat dvě odrážky ZA stávající
odrážku `**Isolation:**` a PŘED `**Publication:**` (pořadí odrážek je součástí
zadání — publikace zůstává poslední):

```markdown
- **Playbook:** attach the path `<PLAN_MB>/playbook.md` to EVERY implementer
  dispatch alongside the task brief, introduced as "procedures that bind this
  project — follow them"; when the file does not exist, say so instead of
  omitting the line. Take the build and test procedures for the baseline check
  before the first task from the same file. Legacy shape: when `playbook.md` is
  absent and `tasks.md` exists, use `tasks.md` (contract, Memory Bank Document
  Set).
- **Playbook candidates:** every implementer dispatch requires the report to
  end with a `## Playbook candidates` section — procedural knowledge learned
  while doing the task that was not already in the brief or the playbook, each
  entry carrying `Tried` / `Happened` / `Procedure`. An empty section is
  legitimate and common; an entry without `Happened` is not written. As
  controller, COPY confirmed entries verbatim into
  `<MB_ROOT>/.superpowers/playbook-candidates.md` (first line
  `# Playbook candidates — work item: <slug>`; a foreign slug means a foreign
  file — start a new one). Do not rephrase them; the harvest gate presents them
  to the user.
```

- [ ] **Step 2: Rozšířit finishing overlay**

V odrážce `**Option 1, 2, or 3** …` v
`finishing-a-development-branch.overlay.md` nahradit větu popisující, co
`mb-harvest` dělá:

```markdown
- **Option 1, 2, or 3** (Merge Locally / Push and Create PR / Keep As-Is) →
  invoke the `mb-harvest` skill. It harvests knowledge into the affected
  Memory Bank documents, runs the playbook gate (asks the user which collected
  experiences to persist — the harvest's only non-autonomous step), archives
  the design document to `proposals/completed/` (deleting the implementation
  plan), resets `memory-bank/context.md` to IDLE and offers `mb-jira-update`.
  Commit the resulting Memory Bank changes on this branch (Czech commit
  message), then execute the chosen option.
```

- [ ] **Step 3: Ověřit, že se nezměnil tvar fragmentu**

Run:
```bash
head -3 ums/.claude/skills/shared/overlays/subagent-driven-development.overlay.md
head -3 ums/.claude/skills/shared/overlays/finishing-a-development-branch.overlay.md
grep -c "UMS-OVERLAY BEGIN\|UMS-OVERLAY END" ums/.claude/skills/shared/overlays/subagent-driven-development.overlay.md ums/.claude/skills/shared/overlays/finishing-a-development-branch.overlay.md
```
Expected: `TARGET:` a `ANCHOR:`/`ANCHOR-BEFORE:` řádky beze změny; v každém
souboru právě 2 značky bloku.

- [ ] **Step 4: Commit**

```bash
git add ums/.claude/skills/shared/overlays/
git commit -m "UMS: overlaye — playbook v SDD dispatchi a sběr kandidátů"
```

---

### Task 7: mb-init, mb-sync a úklid výčtů

**Files:**
- Modify: `ums/.claude/skills/mb-init/SKILL.md`
- Modify: `ums/.claude/skills/mb-sync/SKILL.md`
- Modify: `ums/.claude/skills/mb-scan/SKILL.md`
- Modify: `ums/.claude/skills/mb-git-commit/SKILL.md`
- Modify: `ums/.claude/skills/mb-git-message/SKILL.md`
- Modify: `ums/.claude/skills/mb-jira-update/SKILL.md`

**Interfaces:**
- Consumes: z Tasku 1 sadu dokumentů, `Document Ownership` a Playbook Contract.
- Produces: nic pro další úlohy.

- [ ] **Step 1: mb-init — vytvářená sada**

V sekci `### 2. Create the Memory Bank structure` nahradit výčet souborů:

```markdown
- `brief.md`
- `architecture.md`
- `tech.md`
- `playbook.md` — **only when Phase 2/3 discovered concrete build or test
  commands.** Put the commands here and the versions and stack into `tech.md`
  (contract, Document Ownership). Never create it empty: an empty stub is
  exactly how the former `tasks.md` ended up used in one MB out of eight.
- `proposals/next/`
- `proposals/active/`
- `proposals/completed/`
- `proposals/abandoned/`
```

- [ ] **Step 2: mb-init — checklist a hlášení**

V `### Analysis Completion Checklist` nahradit řádek o `brief.md`:

```markdown
- [ ] `brief.md` has project purpose, key directories, who it serves and what value it gives (or `[K DOPLNĚNÍ]`)
```

V `### 4. Announce` nahradit řádek `Updated files:`:

```markdown
- `Updated files: brief.md, architecture.md, tech.md, proposals/next/, proposals/active/, proposals/completed/, proposals/abandoned/` (plus `playbook.md` when concrete commands were found)
```

- [ ] **Step 3: mb-sync — sada, vlastnictví a přesuny**

V sekci `**Compare:**` nahradit řádky o `brief.md`/`product.md`:

```markdown
- Features, purpose and value vs `<affected_mb>/brief.md`
```

V sekci `### 3. Update Documentation` nahradit úvodní varovný odstavec:

```markdown
**⚠️ CURRENT-STATE STYLE (MANDATORY):** the current-state MB docs
(`architecture.md`, `tech.md`, `brief.md`) describe the CURRENT STATE in
present tense, as reference documentation. They are NOT a changelog.
`playbook.md` is NOT one of them — see the playbook rule below.
- Place every fact in its owning document (contract, Document Ownership); FOLD
  it into the relevant current-state section (present tense). If a fact is
  already described there, do not duplicate it.
- When a fact sits in the wrong document, MOVE it: write into the target first,
  then delete from the source, and name the move in the report.
- DO NOT create or append dated changelog sections such as "Nedávné změny",
  "Recent Changes", "Nedávné technické změny", "Changelog", "Historie změn", or
  "Last performed / Naposledy provedeno" logbook entries.
- History (what changed, when, by which ticket/commit) lives in
  `proposals/completed/` and git — never in the state docs.
- When a change removes/deprecates something, update the docs to describe the
  new state; do not narrate the removal ("Odstraněné relikty (YYYY-MM)").
```

Nahradit podsekci `#### <affected_mb>/brief.md / <affected_mb>/product.md`:

```markdown
#### `<affected_mb>/brief.md`
- Only if core purpose, value or features changed

#### `<affected_mb>/playbook.md`
- **Never change it without the user's approval** (contract, Playbook
  Contract). When the sync finds a procedure that no longer matches reality,
  PROPOSE the correction — with the evidence — and write only what the user
  approves.
```

- [ ] **Step 4: Úklid jazykového boilerplate v šesti skillech**

V `mb-sync`, `mb-scan`, `mb-git-commit`, `mb-git-message`, `mb-jira-update`
nahradit řádek začínající
`- Proposals and persistent Memory Bank documents (brief.md, product.md, …`:

```markdown
- Proposals and persistent Memory Bank documents (brief.md, architecture.md, tech.md, playbook.md, context.md) MUST be in Czech.
```

- [ ] **Step 5: Ověřit, že nikde nezůstal starý výčet**

Run:
```bash
grep -rn "brief.md, product.md" ums/.claude/skills/ ; echo "exit=$?"
```
Expected: žádný výstup, `exit=1`.

Run:
```bash
grep -rln "product\.md" ums/.claude/skills/
```
Expected: jen `shared/UMS_MEMORY_BANK_CONTRACT.md`, `mb-harvest/SKILL.md`
(legacy odstavec) a `mb-migrate-docs/` (migrace).

- [ ] **Step 6: Commit**

```bash
git add ums/.claude/skills/mb-init/SKILL.md ums/.claude/skills/mb-sync/SKILL.md ums/.claude/skills/mb-scan/SKILL.md ums/.claude/skills/mb-git-commit/SKILL.md ums/.claude/skills/mb-git-message/SKILL.md ums/.claude/skills/mb-jira-update/SKILL.md
git commit -m "UMS: mb-init a mb-sync na novou sadu dokumentů, úklid výčtů"
```

---

### Task 8: Dogfood — Memory Bank tohoto repozitáře

**Files:**
- Modify: `memory-bank/brief.md`
- Modify: `memory-bank/tech.md`
- Create: `memory-bank/playbook.md`
- Delete: `memory-bank/product.md`

**Interfaces:**
- Consumes: z Tasku 1 kanonickou strukturu `brief.md`, tabulku
  `Document Ownership` a Playbook Contract.
- Produces: nic pro další úlohy.

Tuto úlohu dělej **ručně a prozaicky**, ne skriptem — je to zkouška, jestli
hranice v praxi drží, a zároveň jediná MB v tomto repu.

- [ ] **Step 1: Sloučit product.md do brief.md**

Přečti `memory-bank/brief.md` (62 ř.) a `memory-bank/product.md` (85 ř.).
Přepiš `brief.md` do kanonického pořadí sekcí z kontraktu:

- `## Co to je` — ze současné sekce „Co je tento repozitář"
- `## Role větví (závazné)` a `## Klíčové adresáře` — zůstávají (jsou to
  „klíčové funkce / rozsah" tohoto repa)
- `## Pro koho a hodnota` — ze sekcí „Komu vrstva slouží" a „Jak vypadá práce
  s vrstvou" produktu
- `## Rozpracování epiků`, `## Podporované harnessy`,
  `## Co vrstva záměrně nedělá` — z produktu, beze změny významu
- `## Vztah k monorepu UMS` a `## Stav` — zůstávají

Fakta, která se v obou souborech opakují, ponech jen jednou. Odkazy z jiných
dokumentů na `product.md` přesměruj na `brief.md`.

Pak: `git rm memory-bank/product.md`

- [ ] **Step 2: Vytáhnout postupy z tech.md do playbook.md**

Přečti `memory-bank/tech.md` (192 ř.) a rozděl jeho obsah podle rozhodovacího
testu z kontraktu. Do nového `memory-bank/playbook.md` patří to preskriptivní:

- konvence testů — `_assert.ps1` se kopíruje do každého adresáře testů, žádný
  Pester, offline fixtura s lokálním bare „origin", jak se sada spouští
- postup revendoru upstreamu (`revendor-superpowers.ps1 -Tag <nový> -NoOverlays`
  → commit „vanilla sync" → `-OverlaysOnly` → commit „overlay")
- CRLF past na Windows a jak se jí vyhnout
- nasazení vrstvy `sync-with-monorepo.ps1` (parametry, směry, co se kam
  nenasazuje)
- obnova nasazené kopie `.claude/` v tomto repu po změně zdroje v `ums/`

V `tech.md` zůstává popisné: verze kontraktu a vendor pin, seznam souborů
vrstvy, počty testů a asercí, tabulka `settings.json`, pasti prostředí jako
konstatování stavu.

U každého postupu, který má důvod (například proč se `_assert.ps1` kopíruje
místo sdílení), přidej jednořádkové `Proč:`.

- [ ] **Step 3: Ověřit, že se nic neztratilo ani nezdvojilo**

Run:
```bash
wc -l memory-bank/*.md
grep -rn "product\.md" memory-bank/ ; echo "exit=$?"
```
Expected: `product.md` neexistuje a nikde na něj nevede odkaz (`exit=1`);
`playbook.md` existuje.

Ručně zkontroluj: každý fakt z původního `product.md` je v `brief.md` právě
jednou, a každý postup z původního `tech.md` je buď v `playbook.md`, nebo
v `tech.md` — nikdy v obou.

- [ ] **Step 4: Commit**

```bash
git add memory-bank/brief.md memory-bank/tech.md memory-bank/playbook.md memory-bank/product.md
git commit -m "UMS: memory-bank tohoto repa na novou sadu dokumentů"
```

---

### Task 9: Zastaralé verze a závěrečná kontrola konzistence

**Files:**
- Modify: `ums/README.md`
- Modify: `ums/.claude/skills/shared/SKILLS_MANIFEST.md`

**Interfaces:**
- Consumes: vše z Tasků 1–8.
- Produces: nic.

`ums/README.md` dokumentovou sadu nikde nepopisuje (ověřeno — je to layout
a deployment dokument, jednotlivé `mb-*` skilly nevyjmenovává), takže se v něm
kvůli nové sadě nemění nic. Mění se v něm jen dvě zastaralé hodnoty, které
tato práce odhalila.

- [ ] **Step 1: Opravit zastaralý vendor pin na dvou místech**

Skutečná vendorovaná verze je `v6.2.0`
(`ums/.claude/skills/shared/VENDORED_FROM.md`, řádek `- Tag: v6.2.0`), ale dvě
místa uvádějí `v6.1.1`. Je to zastaralá hodnota, ne součást tohoto návrhu —
oprav ji a v commit message to přiznej jako doprovodnou opravu.

V `ums/README.md` řádek 8:

```markdown
**Model:** vendored superpowers skills (v6.2.0) drive the workflow
```

V `ums/.claude/skills/shared/SKILLS_MANIFEST.md` v sekci `## Přehled`:

```markdown
Skill pack MB v2: Superpowers (vendorované, v6.2.0) řídí workflow, Memory Bank
je dokumentová/znalostní vrstva. Normativní pravidla: [kontrakt v2](UMS_MEMORY_BANK_CONTRACT.md).
```

- [ ] **Step 2: Doplnit nový skill do stromu v README**

V `ums/README.md`, v bloku `## Layout`, nahradit řádek popisující `shared/`:

```
        ├── shared/           ← contract v2.3, manifest, VENDORED_FROM.md, overlays/*.overlay.md
```

- [ ] **Step 3: Kontrola konzistence napříč vrstvou**

Run:
```bash
grep -rn "Contract-Version" ums/ | grep -v "2.3" ; echo "exit=$?"
grep -rn "brief.md, product.md" ums/ ; echo "exit=$?"
grep -rn "tasks\.md" ums/.claude/skills/ | grep -v "mb-migrate-docs\|Document Set\|legacy\|Legacy"
```
Expected: první dva bez výstupu (`exit=1`); třetí jen zásahy, které legacy
podobu popisují záměrně.

- [ ] **Step 4: Regresní běh všech testů vrstvy**

Run:
```bash
for t in $(find ums -name "*.tests.ps1"); do echo "== $t"; pwsh -NoProfile -File "$t" || echo "FAILED: $t"; done
```
Expected: každá sada končí `<N> passed`, žádné `FAILED:`. Sady existující před
touto prací (hooky, mb-doc-index, mb-epic-elaboration, mb-epic-graph) musí
zůstat zelené — tato práce se jich nedotýká, takže červená sada znamená
regresi, ne očekávanou změnu.

- [ ] **Step 5: Commit**

```bash
git add ums/README.md ums/.claude/skills/shared/SKILLS_MANIFEST.md
git commit -m "UMS: oprava zastaralého vendor pinu v README a manifestu"
```

---

## Poznámka k exekuci

Před dispatchem prvního tasku obnov nasazenou kopii vrstvy v kořenovém
`.claude/` ze zdroje v `ums/.claude/` — nasazená kopie je na kontraktu 2.1,
takže by subagenti jinak pracovali podle dvě verze staré normy. Nasazení do
monorepa (`d:\_datasys\ums`) do této práce NEPATŘÍ; to je samostatná akce
uživatele po dokončení větve.
