# Vrstva v3 — jádro a doklad: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rozdělit kontrakt na rozpočtované jádro, reference a doklad, načítat jádro mechanicky hookem, a zapracovat granularitu položky, poznatky UMS-3517 a Jira šablonu s pravidlem odkazů — vše s testy napřed.

**Architecture:** Kontrakt 2.19 se přesouvá ve třech commitech (beze změny textu → extrakce dokladu → nová pravidla) pod dohledem nástroje na zachování řádků a testu tvaru. Nový hook `contract-inject.ps1` vkládá jádro do kontextu při startu a s prvním promptem po kompaktaci. Sdílené skripty `Get-UmsPermalink.ps1` a `Test-UmsJiraDescription.ps1` dávají Jira pravidlům strojovou oporu; `ledger-status.ps1`, `epic-gate.ps1` a `pool-status.ps1` dostávají poznatky správce epiku jako kód.

**Tech Stack:** Markdown (kontrakt, skilly, overlaye), PowerShell 7 (skripty a bezzávislostní `.tests.ps1` sady s `_assert.ps1`), JSON (`settings.json`, `ums-repo.json`), Git.

**Spec:** [design_ums_3551_jadro_a_doklad.md](design_ums_3551_jadro_a_doklad.md)

- **Jira:** UMS-3551 (https://datasyscz.atlassian.net/browse/UMS-3551)
- **Target MB:** memory-bank/

## Global Constraints

- Zdrojem vrstvy je `ums/.claude/`; kořenový `.claude/` je netrackované nasazení a mění se jen obnovou z `ums/.claude/` (playbook, „Obnova nasazené kopie v tomto repu").
- Jádro `ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md` má nejvýš **600 řádků** a nese `Contract-Version: 3.0` (od úlohy 19; do té doby `2.19`).
- Reference leží v `ums/.claude/skills/shared/contract/<téma>.md`, doklad v `ums/.claude/skills/shared/contract/doklad/<téma>.md`, historie v `ums/.claude/skills/shared/CHANGELOG.md`.
- Citace: `(contract, "Section Name")` pro jádro, `(contract/<file>.md, "Section Name")` pro referenci. Jiný tvar neprojde testem tvaru.
- Jazyk: kontrakt, reference, doklad, skilly, overlaye, skripty, testy a jejich hlášky pro model anglicky; vše, co čte uživatel (hlášky STOPů, Jira šablona, commit messages, reporty), česky (contract, "Language Contract").
- Testy: žádný Pester; sada `<téma>.tests.ps1` vedle kódu, dot-source `_assert.ps1` ze svého adresáře, `$ErrorActionPreference = 'Stop'`, offline, každý nový regresní strážce ověřený vlastní negativitou (playbook, „Testy vrstvy").
- Vendorované skilly se needitují mimo `<!-- UMS-OVERLAY -->` bloky; změny overlayů jdou do `shared/overlays/*.overlay.md` a do nasazení se dostanou revendorem.
- Každý task končí commitem s prefixem `UMS-3551:` a českou zprávou; agent pushuje vlastní větev po každém commitu a ohlásí větev i commity.
- Base sync jen na hranicích fází (před prvním dispatchem, před závěrečným review, před harvestem), nikdy uprostřed tasku.
- Číslo asercí v dokumentaci se nikdy neodhaduje; získává se spuštěním sady.

## Ověřovací sada

```
pwsh -NoProfile -Command "$f=0; Get-ChildItem ums -Recurse -Filter *.tests.ps1 | ForEach-Object { Write-Host \"== $($_.FullName)\"; pwsh -NoProfile -File $_.FullName; if ($LASTEXITCODE -ne 0) { $f++ } }; if ($f -gt 0) { Write-Host \"FAILED suites: $f\"; exit 1 } else { Write-Host 'ALL SUITES PASSED' }"
pwsh -NoProfile -File ums/.claude/skills/shared/tests/contract-shape.tests.ps1
pwsh -NoProfile -File ums/.claude/hooks/tests/contract-inject.tests.ps1
pwsh -NoProfile -File ums/.claude/skills/shared/tests/jira-description.tests.ps1
pwsh -NoProfile -File ums/.claude/skills/shared/tests/permalink.tests.ps1
```

---

## Struktura souborů

| Soubor | Odpovědnost |
|---|---|
| `ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md` | jádro kontraktu (rozpočet 600 řádků) |
| `ums/.claude/skills/shared/contract/*.md` | 17 referencí, jedna na téma, načítá vlastnící skill |
| `ums/.claude/skills/shared/contract/doklad/*.md` | zdůvodnění a měření po tématech |
| `ums/.claude/skills/shared/CHANGELOG.md` | verzní historie kontraktu |
| `ums/.claude/skills/shared/scripts/Test-UmsContractMove.ps1` | nástroj zachování řádků při přesunu |
| `ums/.claude/skills/shared/scripts/Get-UmsPermalink.ps1` | jediný domov tvaru permalinku |
| `ums/.claude/skills/shared/scripts/Test-UmsJiraDescription.ps1` | kontrola popisu tiketu před zápisem |
| `ums/.claude/skills/shared/scripts/Get-UmsRepoConfig.ps1` | klíč `permalinkTemplate` |
| `ums/.claude/skills/shared/tests/{contract-move,contract-shape,permalink,jira-description}.tests.ps1` | nové sady |
| `ums/.claude/hooks/contract-inject.ps1` + `hooks/tests/contract-inject.tests.ps1` | injektáž jádra |
| `ums/.claude/settings.json` | registrace hooku na tři události |
| `ums/.claude/skills/mb-epic-elaboration/{ledger-template.md,protocol.md,scripts/ledger-status.ps1,tests/…}` | podlaha testů, „Ověřeno proti", granularita, drifty |
| `ums/.claude/skills/mb-epic-run/{SKILL.md,scripts/pool-status.ps1,scripts/epic-gate.ps1,tests/…}` | poznatky správce |
| `ums/.claude/skills/mb-jira-update/SKILL.md` | permalink z konfigurace, kontrola popisu, zpětné ověření |
| `ums/.claude/skills/shared/overlays/*.overlay.md` | bannery, granularita, per-tiketový soubor epiku |
| `ums/.claude/skills/mb-*/SKILL.md` (19 souborů) | bannery a citace |
| `ums/.claude/skills/mb-state/SKILL.md` | drift nasazení ve forku |
| `ums/.claude/skills/shared/SKILLS_MANIFEST.md`, `ums/README.md`, `ums/CLAUDE.md.sample` | dokumentace vrstvy |

---

## Fáze A — přesun kontraktu

### Task 1: Nástroj zachování řádků `Test-UmsContractMove.ps1`

**Files:**
- Create: `ums/.claude/skills/shared/scripts/Test-UmsContractMove.ps1`
- Test: `ums/.claude/skills/shared/tests/contract-move.tests.ps1`

**Interfaces:**
- Produces: `Compare-UmsLineMultiset([string[]] $Original, [string[]] $Candidate)` → `@{ Missing = [string[]]; Extra = [string[]] }` — porovnání neprázdných řádků po `TrimEnd()` jako multiset (vzor `verify-deletion-only.ps1`); `Test-UmsContractMove -RepoRoot <root> -SnapshotRef <git ref:path> -TargetGlobs <string[]> -AllowExtraPattern <regex>` → `@{ Ok; Missing; Extra; UnexpectedExtra }`, `Ok` = žádný Missing a každý Extra odpovídá `AllowExtraPattern`.

- [ ] **Step 1: Napiš selhávající test na fixturách**

```powershell
#Requires -Version 7
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '_assert.ps1')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\scripts\Test-UmsContractMove.ps1')

$orig = @('# Title', '', 'Rule A.', 'Rule B.', 'Rule B.', '## Section', 'Why: measured once.')
$moved = @('# Title', 'Rule A.', '## Section', 'Rule B.', 'Rule B.', 'Why: measured once.')
$r = Compare-UmsLineMultiset $orig $moved
Assert-Eq @($r.Missing).Count 0 'přeuspořádání bez ztráty nemá Missing'
Assert-Eq @($r.Extra).Count 0 'přeuspořádání bez ztráty nemá Extra'

$lost = @('# Title', 'Rule A.', 'Rule B.', '## Section', 'Why: measured once.')
$r2 = Compare-UmsLineMultiset $orig $lost
Assert-Eq @($r2.Missing).Count 1 'jedna ze dvou stejných řádek chybí → Missing 1 (multiset, ne množina)'
Assert-Eq $r2.Missing[0] 'Rule B.' 'chybějící řádek je pojmenovaný'

$added = @('# Title', 'Rule A.', 'Rule B.', 'Rule B.', '## Section', 'Why: measured once.', 'Part of contract 3.x')
$r3 = Compare-UmsLineMultiset $orig $added
Assert-Eq @($r3.Extra).Count 1 'nový řádek je Extra'

# Test-UmsContractMove proti dočasnému git repu
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("mbmove-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path (Join-Path $tmp 'a') | Out-Null
git -C $tmp init -q
Set-Content -Path (Join-Path $tmp 'a\src.md') -Value $orig -Encoding utf8
git -C $tmp add -A; git -C $tmp -c user.name=t -c user.email=t@t commit -q -m snap
$sha = (git -C $tmp rev-parse HEAD).Trim()
Set-Content -Path (Join-Path $tmp 'a\core.md') -Value @('# Title', 'Rule A.') -Encoding utf8
Set-Content -Path (Join-Path $tmp 'a\ref.md') -Value @('Part of contract 3.x', '## Section', 'Rule B.', 'Rule B.', 'Why: measured once.') -Encoding utf8
$m = Test-UmsContractMove -RepoRoot $tmp -SnapshotRef "$sha`:a/src.md" -TargetGlobs @('a/core.md', 'a/ref.md') -AllowExtraPattern '^Part of contract'
Assert-True $m.Ok 'přesun s povoleným strukturálním řádkem prochází'
Set-Content -Path (Join-Path $tmp 'a\ref.md') -Value @('Part of contract 3.x', '## Section', 'Rule B.', 'Why: measured once.', 'Brand new sentence.') -Encoding utf8
$m2 = Test-UmsContractMove -RepoRoot $tmp -SnapshotRef "$sha`:a/src.md" -TargetGlobs @('a/core.md', 'a/ref.md') -AllowExtraPattern '^Part of contract'
Assert-True (-not $m2.Ok) 'ztracený řádek i nepovolený nový řádek shodí verdikt'
Assert-Eq @($m2.Missing).Count 1 'ztracený Rule B.'
Assert-Eq @($m2.UnexpectedExtra).Count 1 'nová věta je nepovolený Extra'
Remove-Item -Recurse -Force $tmp
Complete-Tests
```

- [ ] **Step 2: Spusť test a ověř, že selže**

Run: `pwsh -NoProfile -File ums/.claude/skills/shared/tests/contract-move.tests.ps1`
Expected: selhání na dot-source (`Test-UmsContractMove.ps1` neexistuje).

- [ ] **Step 3: Napiš skript**

```powershell
#Requires -Version 7
<#
.SYNOPSIS
    Line-multiset preservation check for the contract split (design UMS-3551,
    "Postup přesunu"). Dot-source, then call Compare-UmsLineMultiset or
    Test-UmsContractMove.
#>
Set-StrictMode -Version Latest

function Compare-UmsLineMultiset([string[]] $Original, [string[]] $Candidate) {
    $budget = [System.Collections.Generic.Dictionary[string, int]]::new([StringComparer]::Ordinal)
    foreach ($line in @($Original)) {
        $t = ([string] $line).TrimEnd()
        if ($t -eq '') { continue }
        if ($budget.ContainsKey($t)) { $budget[$t]++ } else { $budget[$t] = 1 }
    }
    $extra = @()
    foreach ($line in @($Candidate)) {
        $t = ([string] $line).TrimEnd()
        if ($t -eq '') { continue }
        if ($budget.ContainsKey($t) -and $budget[$t] -gt 0) { $budget[$t]-- } else { $extra += $t }
    }
    $missing = @()
    foreach ($k in $budget.Keys) { for ($i = 0; $i -lt $budget[$k]; $i++) { $missing += $k } }
    return @{ Missing = @($missing); Extra = @($extra) }
}

function Test-UmsContractMove {
    param(
        [Parameter(Mandatory)] [string] $RepoRoot,
        [Parameter(Mandatory)] [string] $SnapshotRef,
        [Parameter(Mandatory)] [string[]] $TargetGlobs,
        [string] $AllowExtraPattern = '^(# |Part of contract|Doklad: )'
    )
    $snap = & git -C $RepoRoot show $SnapshotRef 2>$null
    if ($LASTEXITCODE -ne 0) { throw "Snapshot '$SnapshotRef' nelze přečíst." }
    $original = @($snap)
    $candidate = @()
    foreach ($g in $TargetGlobs) {
        foreach ($f in @(Get-ChildItem -Path (Join-Path $RepoRoot $g) -File -ErrorAction SilentlyContinue)) {
            $candidate += @(Get-Content -LiteralPath $f.FullName -Encoding utf8)
        }
    }
    $cmp = Compare-UmsLineMultiset $original $candidate
    $unexpected = @($cmp.Extra | Where-Object { $_ -notmatch $AllowExtraPattern })
    return @{
        Ok              = (@($cmp.Missing).Count -eq 0 -and $unexpected.Count -eq 0)
        Missing         = @($cmp.Missing)
        Extra           = @($cmp.Extra)
        UnexpectedExtra = $unexpected
    }
}
```

- [ ] **Step 4: Spusť test, ověř zelenou; pak negativita** — dočasně zaměň `$budget[$t]--` za `$budget[$t] = 0`, spusť, ověř, že zčervená asercie o multisetu, vrať zpět, `git diff` prázdný.

- [ ] **Step 5: Commit**

```bash
git add ums/.claude/skills/shared/scripts/Test-UmsContractMove.ps1 ums/.claude/skills/shared/tests/contract-move.tests.ps1
git commit -m "UMS-3551: nástroj zachování řádků pro přesun kontraktu"
```

### Task 2: Přesun beze změny textu — jádro, 17 referencí, changelog

**Files:**
- Modify: `ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md` (zůstává jádro)
- Create: `ums/.claude/skills/shared/contract/{workspace-discipline,target-mb-discovery,brainstorming-paths,repository-configuration,epic-line,playbook-contract,session-intent-baton,now-block,harvest,integration,cross-branch-visibility,architect-review,epic-backflow,message-protocol,escalation,worktree-pool,jira}.md`
- Create: `ums/.claude/skills/shared/CHANGELOG.md`

**Interfaces:**
- Consumes: `Test-UmsContractMove` (Task 1) se snapshotem `0a13ef1:ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md`.
- Produces: soubory referencí s hlavičkou `# <Title>` + řádek `Part of contract 3.x — the core is ../UMS_MEMORY_BANK_CONTRACT.md; cite as (contract/<file>.md, "Section").`; jádro s sekcemi dle mapy níže. Jména `## ` sekcí zůstávají doslova (citace na ně míří).

Mapa přesunu (blok = od nadpisu po řádek před dalším nadpisem stejné nebo vyšší úrovně; čísla řádků z 0a13ef1 jsou orientační, řídí nadpis):

| Sekce 2.19 (řádek) | Cíl |
|---|---|
| verzní preambule (3–98) | `CHANGELOG.md`, pod `# Contract changelog` |
| `## Purpose & Roles` (100) | jádro |
| `## Three-Tier Directory Model` (120), `## MB_ROOT Discovery` (144), `## Root Memory Bank Gate` (161) | jádro |
| `## Memory Bank Document Set` (181) včetně `### Legacy shape tolerance` (209) | jádro |
| `### Playbook Contract` (225) | `contract/playbook-contract.md` |
| `## Scope Lock` (315) bez podsekcí | jádro |
| `### Session Intent Baton` (341) | `contract/session-intent-baton.md` |
| `### The NOW Block` (460) | `contract/now-block.md` |
| `### Link Conventions` (633) | jádro (jako `## Link Conventions`) |
| `## Repository Configuration` (675) bez `### The epic line` | `contract/repository-configuration.md` |
| `### The epic line` (827) | `contract/epic-line.md` |
| `## Base Sync & Drift Detection` (1000) | jádro |
| `## Workspace Discipline` (1072) včetně `### A pool slot's freedom…` (1110) | `contract/workspace-discipline.md` |
| `## Active Work Item` (1305) | jádro |
| `## Superpowers Document Placement` (1399) bez `### Brainstorming Paths` | jádro |
| `### Brainstorming Paths` (1413) | `contract/brainstorming-paths.md` |
| `## Target-MB Discovery & Pinning` (1475) | `contract/target-mb-discovery.md` |
| `## context.md Schema & Writers` (1571), `## MB Context Reading Rule` (1659) | jádro |
| `## Document Ownership` (1674) | jádro (tabulka) |
| `## Harvest Contract` (1714) | `contract/harvest.md` |
| `## Publication Contract` (1784) bez podsekcí | jádro (v Task 3 se procedurální zbytek přesune do `integration.md`) |
| `### Integration` (2074), `### Abandon` (2243) | `contract/integration.md` |
| `## Cross-Branch Visibility` (2275) | `contract/cross-branch-visibility.md` |
| `## Architect Review Gate` (2314), `## Agentic Design Opposition` (2409) | `contract/architect-review.md` |
| `## Epic Backflow` (2481) | `contract/epic-backflow.md` |
| `## Dispatch Model Policy` (2554), `## Language Contract` (2578) | jádro |
| `## Worktree Policy` (2614) | jádro první odstavec (zákaz); zbytek `contract/worktree-pool.md` |
| `## Message Protocol` (2664) | jádro první tři odstavce a dvě značky se třemi důsledky; zbytek `contract/message-protocol.md` |
| `## Escalation & Autonomy` (2812) | jádro: úvod, dvě pravidla o ukončení tahu, tabulka dna; zbytek `contract/escalation.md` |
| `## Fail-Closed Behavior` (2978) | jádro |
| `## Resolution Protocol` (3029), `## Versioning & Vendoring` (3057) | jádro (beze změny textu; zkrácení až Task 4) |

`contract/jira.md` vzniká v Task 17; v tomto tasku se nezakládá.

- [ ] **Step 1: Ověř výchozí stav nástrojem** — spusť:

```powershell
. ums/.claude/skills/shared/scripts/Test-UmsContractMove.ps1
$r = Test-UmsContractMove -RepoRoot (git rev-parse --show-toplevel) -SnapshotRef '0a13ef1:ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md' -TargetGlobs @('ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md','ums/.claude/skills/shared/contract/*.md','ums/.claude/skills/shared/CHANGELOG.md')
"Ok=$($r.Ok) Missing=$($r.Missing.Count) Extra=$($r.Extra.Count)"
```
Expected: `Ok=True Missing=0 Extra=0` (nic se ještě nepřesunulo).

- [ ] **Step 2: Napiš pomocný skript přesunu do `.superpowers/scratch/split-contract.ps1`** (throwaway, necommituje se): načte jádro po řádcích, najde hranice bloků regexem `^(##|###) ` a pro každou položku mapy vystřihne blok do cílového souboru (`Add-Content`), s hlavičkou reference přesně ve tvaru z Interfaces; preambuli zapíše do `CHANGELOG.md` za `# Contract changelog`; zbytek nechá v jádře. Podsekce `###`, které jdou do jiného souboru než jejich rodič, se z rodiče vyjmou a v cíli povýší nadpisem beze změny textu nadpisu za `### ` (tedy `### The epic line` → `## The epic line` je změna textu a NEPOVOLUJE se; nadpis zůstává `### `).

- [ ] **Step 3: Spusť přesun a nástroj** — Expected: `Ok=True`, `Missing=0`, `Extra` jen řádky `# <Title>` a `Part of contract…`.

- [ ] **Step 4: Přečti jádro a každou referenci jako chladný čtenář** — v jádře nesmí zůstat věta, která odkazuje „níže" na přesunutou sekci bez cíle; takové věty se v TOMTO tasku nemění (text se zachovává), jen se zapíší do `.superpowers/scratch/split-followups.md` pro Task 4.

- [ ] **Step 5: Commit**

```bash
git add ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md ums/.claude/skills/shared/contract ums/.claude/skills/shared/CHANGELOG.md
git commit -m "UMS-3551: přesun kontraktu do jádra a referencí beze změny textu"
```

### Task 3: Extrakce dokladu

**Files:**
- Modify: `ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md`, `ums/.claude/skills/shared/contract/*.md`
- Create: `ums/.claude/skills/shared/contract/doklad/{core,workspace-discipline,repository-configuration,epic-line,playbook-contract,session-intent-baton,now-block,integration,publication,message-protocol,escalation,worktree-pool,epic-backflow,link-conventions}.md`

**Interfaces:**
- Produces: řádek odkazu ve tvaru `Doklad: doklad/<téma>.md, "<podsekce>"` na místě přesunutého odstavce; doklad má `## <podsekce>` nadpisy shodné s citovaným jménem.

Co je doklad (přesouvá se): odstavce začínající nebo nesoucí `Measured`, `measured`, `The reason`, `Earlier versions`, `once claimed`, `The threat model`, `Why an unparseable`, `What does NOT carry over`, historické vysvětlení proč pravidlo vzniklo. Co zůstává: pravidlo, artefakt (šablona, příkaz, tabulka stavů), jediná věta „proč" tam, kde by postup bez ní nedával smysl.

- [ ] **Step 1: Sepiš seznam odstavců k přesunu** do `.superpowers/scratch/doklad-list.md`: soubor, první slova odstavce, cílová podsekce dokladu. Řiď se anatomií v návrhu (Doklad, „Proč jádro a doklad": Publication ~157 řádků, Message Protocol ~89, epic line ~95, pool slot ~86, NOW ~86, baton ~60, Repository Configuration ~60).

- [ ] **Step 2: Přesuň odstavce skriptem** (`.superpowers/scratch/extract-doklad.ps1`): pro každou položku vystřihne odstavec (od řádku po prázdný řádek) a vloží na jeho místo řádek `Doklad: doklad/<téma>.md, "<podsekce>"`; do dokladu zapíše `## <podsekce>` a odstavec doslova.

- [ ] **Step 3: Spusť nástroj zachování** s `-TargetGlobs` rozšířenými o `ums/.claude/skills/shared/contract/doklad/*.md` a `-AllowExtraPattern '^(# |## |Part of contract|Doklad: )'`. Expected: `Ok=True`, `Missing=0`.

- [ ] **Step 4: Změř jádro** — `(Get-Content ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md).Count`; zapiš číslo do ledgeru. Očekávání 600 až 800; dorovnání do rozpočtu je Task 4.

- [ ] **Step 5: Commit**

```bash
git add ums/.claude/skills/shared
git commit -m "UMS-3551: extrakce dokladu z jádra a referencí"
```

### Task 4: Test tvaru kontraktu a dorovnání jádra do rozpočtu

**Files:**
- Create: `ums/.claude/skills/shared/tests/contract-shape.tests.ps1`
- Modify: `ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md` (zkrácení `Purpose & Roles`, sloučení `Resolution Protocol` a `Versioning & Vendoring` do `## Citation & Versioning`, oprava vět z `split-followups.md`)

**Interfaces:**
- Produces: sada `contract-shape.tests.ps1` s kontrolami: rozpočet, verze, bez preambule, dno a STOPy v jádře, bez značek dokladu v jádře, každá citace má cíl, každá reference má konzumenta, žádný legacy tvar citace.

- [ ] **Step 1: Napiš test**

```powershell
#Requires -Version 7
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '_assert.ps1')
$ErrorActionPreference = 'Stop'
$shared = Resolve-Path (Join-Path $PSScriptRoot '..')
$layer = Resolve-Path (Join-Path $shared '..\..')          # ums/.claude
$core = Join-Path $shared 'UMS_MEMORY_BANK_CONTRACT.md'
$refDir = Join-Path $shared 'contract'
$coreLines = @(Get-Content -LiteralPath $core -Encoding utf8)

Assert-True ($coreLines.Count -le 600) "jádro má nejvýš 600 řádků (má $($coreLines.Count))"
Assert-Match ($coreLines -join "`n") '(?m)^- \*\*Contract-Version:\*\* \d+\.\d+' 'jádro nese Contract-Version'
Assert-True (-not (($coreLines -join "`n") -match '(?m)^- (Supersedes|v\d+\.\d+ superseded)')) 'verzní preambule v jádře není'
foreach ($h in @('## Escalation & Autonomy', '## Fail-Closed Behavior', '## Publication Contract', '## Language Contract', '## Message Protocol', '## Session Eligibility', '## Work Item Granularity', '## Phase Map')) {
    Assert-True (($coreLines -match ('^' + [regex]::Escape($h) + '\s*$')).Count -eq 1) "jádro má právě jednu sekci $h"
}
foreach ($k in @('Publication into the delivery line', 'irreversible or destructive', 'security-sensitive', 'not a protected branch', 'epicBranchPattern', 'playbook.md')) {
    Assert-True ((($coreLines -join "`n") -match [regex]::Escape($k))) "řádek dna «$k» je v jádře"
}
Assert-True (-not (($coreLines -join "`n") -match 'Measured|measured 2026|Earlier versions|superseded v|once claimed')) 'jádro nenese značky dokladu'

# --- heading index across core + references -----------------------------------
function Get-Headings([string] $Path) {
    @(Get-Content -LiteralPath $Path -Encoding utf8) | Where-Object { $_ -match '^#{2,4}\s+' } |
        ForEach-Object { ($_ -replace '^#{2,4}\s+', '').Trim() -replace '`', '' }
}
$index = @{ 'core' = @(Get-Headings $core) }
$refs = @(Get-ChildItem -LiteralPath $refDir -File -Filter '*.md')
foreach ($r in $refs) { $index[$r.Name] = @(Get-Headings $r.FullName) }
Assert-True ($refs.Count -ge 17) "existuje aspoň 17 referencí (je $($refs.Count))"

# --- citations ----------------------------------------------------------------
$scan = @(Get-ChildItem -LiteralPath $layer -Recurse -File -Include *.md, *.ps1, *.mjs, pre-push |
    Where-Object { $_.FullName -notmatch '[\\/]doklad[\\/]' -and $_.Name -ne 'CHANGELOG.md' -and $_.FullName -notmatch '[\\/]tests[\\/]' })
$bad = @(); $legacy = @(); $count = 0
foreach ($f in $scan) {
    $text = Get-Content -LiteralPath $f.FullName -Raw -Encoding utf8
    if ($null -eq $text) { continue }
    foreach ($m in [regex]::Matches($text, '\(contract, "(?<s>[^"]+)"\)')) {
        $count++
        $s = $m.Groups['s'].Value -replace '`', ''
        if ($index['core'] -notcontains $s) { $bad += "$($f.Name): (contract, `"$s`")" }
    }
    foreach ($m in [regex]::Matches($text, '\(contract/(?<f>[a-z0-9-]+\.md), "(?<s>[^"]+)"\)')) {
        $count++
        $fn = $m.Groups['f'].Value; $s = $m.Groups['s'].Value -replace '`', ''
        if (-not $index.ContainsKey($fn)) { $bad += "$($f.Name): reference $fn neexistuje"; continue }
        if ($index[$fn] -notcontains $s) { $bad += "$($f.Name): (contract/$fn, `"$s`")" }
    }
    foreach ($m in [regex]::Matches($text, "contract's\s+[`"„]|UMS_MEMORY_BANK_CONTRACT\.md`?,\s*[`"„]|\(contract,\s+section\s")) {
        $legacy += "$($f.Name): $($m.Value)"
    }
}
Assert-True ($count -gt 50) "nalezeno dost citací ke kontrole ($count)"
Assert-Eq @($bad).Count 0 ("každá citace má cíl: " + ($bad -join '; '))
Assert-Eq @($legacy).Count 0 ("žádný legacy tvar citace: " + ($legacy -join '; '))

# --- every reference has a consumer -------------------------------------------
$noConsumer = @()
foreach ($r in $refs) {
    $hits = @($scan | Where-Object { (Get-Content -LiteralPath $_.FullName -Raw -Encoding utf8) -match [regex]::Escape("contract/$($r.Name)") })
    if ($hits.Count -eq 0) { $noConsumer += $r.Name }
}
Assert-Eq @($noConsumer).Count 0 ("každá reference má konzumenta: " + ($noConsumer -join ', '))
Complete-Tests
```

- [ ] **Step 2: Spusť; ověř červenou** — očekávané selhání: rozpočet (jádro > 600), chybějící sekce `Session Eligibility` / `Work Item Granularity` / `Phase Map` (vzniknou v Tasks 7 a 8; do té doby zůstávají červené a task končí s POJMENOVANÝMI červenými aserciemi v ledgeru), legacy citace (opraví Task 5), reference bez konzumenta (Task 5).

- [ ] **Step 3: Dorovnej jádro**: zkrať `## Purpose & Roles` na deset řádků s aktuálním seznamem konzumentů (17 `mb-*` skillů, 4 overlaye, hooky); slouč `## Resolution Protocol` a `## Versioning & Vendoring` do `## Citation & Versioning` (tři odstavce: tvar citace, umístění souborů, verze jen v jádře); z `## Publication Contract` přesuň recept ověření hooku a doručení markeru per harness do `contract/integration.md` pod `### Publication mechanics`; oprav věty ze `split-followups.md` tak, aby ukazovaly na referenci citací. Cíl: `Count -le 600` zelený.

- [ ] **Step 4: Spusť test znovu** — zelené: rozpočet, verze, preambule, dno, značky dokladu, citace s cílem. Červené smí zůstat jen tři sekce z Tasks 7 a 8, legacy tvary a konzumenti (Task 5). Zapiš přesný seznam do ledgeru.

- [ ] **Step 5: Commit**

```bash
git add ums/.claude/skills/shared
git commit -m "UMS-3551: test tvaru kontraktu a dorovnání jádra do rozpočtu"
```

### Task 5: Bannery a citace ve skillech, overlayích a hoocích

**Files:**
- Modify: `ums/.claude/skills/mb-*/SKILL.md` (19 souborů, řádek 10 až 13), `ums/.claude/skills/shared/overlays/{brainstorming,subagent-driven-development,finishing-a-development-branch,writing-plans}.overlay.md`, `ums/.claude/hooks/{pre-push,guard-git-push.mjs,deny-superpowers-docs.mjs,install-git-hooks.ps1,session-intent.ps1}` (jen komentáře s citacemi), `ums/.claude/skills/mb-epic-run/scripts/pool-status.ps1` (komentáře), `ums/.claude/skills/shared/SKILLS_MANIFEST.md`
- Test: `ums/.claude/skills/shared/tests/contract-shape.tests.ps1` (Task 4)

**Interfaces:**
- Produces: banner tvaru `> Contract core: [UMS_MEMORY_BANK_CONTRACT](../shared/UMS_MEMORY_BANK_CONTRACT.md) · References: [<a>.md](../shared/contract/<a>.md), [<b>.md](../shared/contract/<b>.md). Read the named references before acting.`; přiřazení referencí podle tabulky 2.3 návrhu.

Přiřazení (skill → reference): `mb-harvest` → harvest, playbook-contract, session-intent-baton; `mb-park` → workspace-discipline, playbook-contract, session-intent-baton; `mb-abort` → integration, session-intent-baton; `mb-state` → workspace-discipline, repository-configuration; `mb-architect-review` → architect-review, epic-backflow, repository-configuration; `mb-jira-update` → jira, integration; `mb-epic-run` → epic-line, worktree-pool, now-block, message-protocol, escalation, integration; `mb-epic-elaboration` → epic-backflow, epic-line, escalation, jira; `mb-epic-graph` → epic-backflow, jira; `mb-doc-index` → cross-branch-visibility; `mb-init` → repository-configuration; `mb-migrate-docs` → harvest; `mb-sync` → harvest; `mb-scan`, `mb-git-commit`, `mb-git-message`, `mb-link-audit` → jen jádro; `mb-plan`, `mb-act` → jen jádro. Overlaye: brainstorming → workspace-discipline, target-mb-discovery, brainstorming-paths, architect-review, epic-backflow, cross-branch-visibility; SDD → playbook-contract, now-block, session-intent-baton; finishing → integration, harvest; writing-plans → session-intent-baton, integration.

- [ ] **Step 1: Spusť test tvaru a zapiš seznam legacy citací a referencí bez konzumenta** (výchozí červená).

- [ ] **Step 2: Přepiš bannery** podle přiřazení; v každém skillu odstraň odstavce, které pravidlo parafrázují, a nahraď citací (minimálně: pětkrát zkopírovaný odstavec Target-MB discovery v `mb-git-commit`, `mb-git-message`, `mb-scan`, `mb-sync`, `mb-jira-update` → věta `Target-MB Discovery & Pinning runs in the superpowers workflow (contract/target-mb-discovery.md, "Target-MB Discovery & Pinning"); this skill never selects a target itself.`; čtyři sondy volného workspace v `mb-state` → citace `(contract/workspace-discipline.md, "Workspace Discipline")` s ponecháním příkazů; publikační pravidlo a ověření dosažitelnosti v `mb-park` → citace `(contract, "Publication Contract")` s ponecháním příkazů).

- [ ] **Step 3: Přepiš citace v hoocích a skriptech** na standardní tvar (komentáře); `SKILLS_MANIFEST.md` dostane řádky pro `contract/` a `CHANGELOG.md`.

- [ ] **Step 4: Spusť test tvaru** — Expected: zelené citace, legacy 0, konzumenti 0 chybějících; červené jen tři sekce z Tasks 7 a 8.

- [ ] **Step 5: Ověř bannerový grep** — `Select-String -Path ums/.claude/skills/mb-*/SKILL.md -Pattern '^> Follow \[UMS_MEMORY_BANK_CONTRACT\]'` → 0 výskytů; `Select-String -Pattern '^> Contract core:'` → 19 výskytů.

- [ ] **Step 6: Commit**

```bash
git add ums/.claude/skills ums/.claude/hooks
git commit -m "UMS-3551: bannery jmenují jádro a reference, parafrázy nahrazeny citacemi"
```

---

## Fáze B — mechanické načtení jádra

### Task 6: Hook `contract-inject.ps1`

**Files:**
- Create: `ums/.claude/hooks/contract-inject.ps1`
- Create: `ums/.claude/hooks/tests/contract-inject.tests.ps1`
- Modify: `ums/.claude/settings.json` (`SessionStart` první záznam, `PostCompact`, nový `UserPromptSubmit`)

**Interfaces:**
- Consumes: jádro `<deployment>/skills/shared/UMS_MEMORY_BANK_CONTRACT.md` (deployment = rodič adresáře hooku), `memory-bank/context.md`, `.superpowers/sdd/plan_<slug>/progress.md`, marker `.superpowers/contract-reload.flag`.
- Produces: `pwsh -NoProfile -File contract-inject.ps1 [-Event SessionStart|PostCompact|UserPromptSubmit]`; bez `-Event` čte `hook_event_name` ze stdin JSON. Výstup: pro `SessionStart` a `UserPromptSubmit` s markerem JSON `{"hookSpecificOutput":{"hookEventName":"<event>","additionalContext":"<payload>"}}`; pro `PostCompact` JSON `{"systemMessage":"Context was compacted. The contract core is re-injected with your next prompt; until then act on the summary and re-invoke the skill you are executing."}` a zapsaný marker; pro `UserPromptSubmit` bez markeru žádný výstup. Vždy exit 0. Konstanty: `$MaxPayloadBytes = 49152`, `$FallbackText = 'Read <deployment>/skills/shared/UMS_MEMORY_BANK_CONTRACT.md (contract core) and memory-bank/context.md before relying on any Memory Bank-aware behaviour.'`.

Payload (`SessionStart`, `UserPromptSubmit`): `<contract-core>` + celé jádro + `</contract-core>`, prázdný řádek, `<memory-bank-context>` + re-render `context.md` (jen řádky odpovídající `^\s*-\s+\*\*[A-Za-z][A-Za-z ]+:\*\*\s+.*$` nebo přesně `(No active work - IDLE phase)`; ostatní vynechány) + `</memory-bank-context>`, volitelně `<now-block>` + šest `Key: value` řádků re-renderovaných z markerů `<!-- UMS-NOW BEGIN -->`/`<!-- UMS-NOW END -->` ledgeru slugu z pinu (hodnota s `[<>]`, `\p{Cc}` nebo `\p{Cf}` → blok se vynechá a přidá se řádek `now-block: rejected (character class)`) + `</now-block>`, a závěrečný pevný anglický pokyn: `Invoke the Skill tool with skill: using-superpowers first, then read your active skill's references named in its banner. Then run the Session Eligibility check (contract, "Session Eligibility").`

- [ ] **Step 1: Napiš test** (`ums/.claude/hooks/tests/contract-inject.tests.ps1`; vlastní kopie `_assert.ps1` v `hooks/tests/` už existuje):

```powershell
#Requires -Version 7
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '_assert.ps1')
$ErrorActionPreference = 'Stop'
$hookSrc = Join-Path $PSScriptRoot '..\contract-inject.ps1'

function New-Deployment([string] $CoreText) {
    $d = Join-Path ([IO.Path]::GetTempPath()) ("mbinject-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path (Join-Path $d 'hooks'), (Join-Path $d 'skills\shared') | Out-Null
    Copy-Item $hookSrc (Join-Path $d 'hooks\contract-inject.ps1')
    if ($null -ne $CoreText) { [IO.File]::WriteAllText((Join-Path $d 'skills\shared\UMS_MEMORY_BANK_CONTRACT.md'), $CoreText, (New-Object Text.UTF8Encoding($false))) }
    return $d
}
function New-Repo([string] $ContextText) {
    $r = Join-Path ([IO.Path]::GetTempPath()) ("mbrepo-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path (Join-Path $r 'memory-bank'), (Join-Path $r '.superpowers') | Out-Null
    git -C $r init -q
    if ($null -ne $ContextText) { [IO.File]::WriteAllText((Join-Path $r 'memory-bank\context.md'), $ContextText, (New-Object Text.UTF8Encoding($false))) }
    return $r
}
function Invoke-Hook([string] $Deployment, [string] $Repo, [string] $Event) {
    Push-Location $Repo
    try { $out = & pwsh -NoProfile -File (Join-Path $Deployment 'hooks\contract-inject.ps1') -Event $Event 2>&1 | Out-String; $code = $LASTEXITCODE }
    finally { Pop-Location }
    return @{ Out = $out; Code = $code }
}

$core = "# UMS Memory Bank Contract`n`n- **Contract-Version:** 3.0`n`n## Language Contract`n- AI-facing text is English.`n"
$ctxActive = "# Context`n`n## Active Work`n`n- **Jira:** UMS-1 (https://x/UMS-1)`n- **Target MB Pin:** memory-bank/`n- **Work item:** demo_slug`n- **Started:** 2026-09-17`n"

# 1. SessionStart carries core + context
$d = New-Deployment $core; $r = New-Repo $ctxActive
$res = Invoke-Hook $d $r 'SessionStart'
Assert-Eq $res.Code 0 'SessionStart exits 0'
$json = $res.Out | ConvertFrom-Json
Assert-Eq $json.hookSpecificOutput.hookEventName 'SessionStart' 'event name is SessionStart'
Assert-Match $json.hookSpecificOutput.additionalContext '<contract-core>[\s\S]*Contract-Version:\*\* 3\.0[\s\S]*</contract-core>' 'core is embedded whole'
Assert-Match $json.hookSpecificOutput.additionalContext '<memory-bank-context>[\s\S]*Work item:\*\* demo_slug' 'context pin is re-rendered'
Assert-True (-not ($json.hookSpecificOutput.additionalContext -match '<now-block>')) 'no ledger → no NOW block'

# 2. NOW block from the pinned slug's ledger
$led = Join-Path $r '.superpowers\sdd\plan_demo_slug'; New-Item -ItemType Directory -Path $led | Out-Null
$now = "# Ledger`n<!-- UMS-NOW BEGIN -->`nState: waiting-for-subagent`nWaiting on: implementer of task 2`nSince: 2026-09-17T09:00:00Z`nDue: 2026-09-17T09:30:00Z`nTask: 2 — Demo`nLook at: .superpowers/sdd/plan_demo_slug/task-2-brief.md`n<!-- UMS-NOW END -->`n"
[IO.File]::WriteAllText((Join-Path $led 'progress.md'), $now, (New-Object Text.UTF8Encoding($false)))
$json = (Invoke-Hook $d $r 'SessionStart').Out | ConvertFrom-Json
Assert-Match $json.hookSpecificOutput.additionalContext '<now-block>[\s\S]*State: waiting-for-subagent[\s\S]*</now-block>' 'NOW block is re-rendered'

# 3. hostile NOW value is rejected by character class
$hostile = $now -replace 'implementer of task 2', ("implementer" + [char]0x202E + " of task 2")
[IO.File]::WriteAllText((Join-Path $led 'progress.md'), $hostile, (New-Object Text.UTF8Encoding($false)))
$json = (Invoke-Hook $d $r 'SessionStart').Out | ConvertFrom-Json
Assert-True (-not ($json.hookSpecificOutput.additionalContext -match '<now-block>')) 'RTL override → block dropped'
Assert-Match $json.hookSpecificOutput.additionalContext 'now-block: rejected \(character class\)' 'rejection is announced'

# 4. PostCompact writes the marker and a systemMessage
$res = Invoke-Hook $d $r 'PostCompact'
Assert-Eq $res.Code 0 'PostCompact exits 0'
$json = $res.Out | ConvertFrom-Json
Assert-Match $json.systemMessage 'Context was compacted' 'PostCompact emits systemMessage'
Assert-True (Test-Path (Join-Path $r '.superpowers\contract-reload.flag')) 'PostCompact writes the reload marker'

# 5. UserPromptSubmit with marker injects and consumes it
$res = Invoke-Hook $d $r 'UserPromptSubmit'
$json = $res.Out | ConvertFrom-Json
Assert-Eq $json.hookSpecificOutput.hookEventName 'UserPromptSubmit' 'UserPromptSubmit injects when marker present'
Assert-Match $json.hookSpecificOutput.additionalContext '<contract-core>' 'core injected after compaction'
Assert-True (-not (Test-Path (Join-Path $r '.superpowers\contract-reload.flag'))) 'marker consumed'

# 6. UserPromptSubmit without marker is silent
$res = Invoke-Hook $d $r 'UserPromptSubmit'
Assert-Eq $res.Code 0 'silent exit 0'
Assert-True ([string]::IsNullOrWhiteSpace($res.Out)) 'no output without marker'

# 7. missing core → fallback instruction, exit 0
$d2 = New-Deployment $null
$res = Invoke-Hook $d2 $r 'SessionStart'
Assert-Eq $res.Code 0 'missing core still exits 0'
$json = $res.Out | ConvertFrom-Json
Assert-Match $json.hookSpecificOutput.additionalContext 'Read .*UMS_MEMORY_BANK_CONTRACT\.md \(contract core\)' 'fallback instruction emitted'

# 8. missing context.md → core still emitted
$r2 = New-Repo $null
$json = (Invoke-Hook $d $r2 'SessionStart').Out | ConvertFrom-Json
Assert-Match $json.hookSpecificOutput.additionalContext '<contract-core>' 'core without context.md'
Assert-Match $json.hookSpecificOutput.additionalContext '<memory-bank-context>\s*\(context\.md missing\)' 'missing context is named'

# 9. oversize core → fallback
$big = "# UMS Memory Bank Contract`n- **Contract-Version:** 3.0`n" + ('x' * 60000)
$d3 = New-Deployment $big
$json = (Invoke-Hook $d3 $r 'SessionStart').Out | ConvertFrom-Json
Assert-Match $json.hookSpecificOutput.additionalContext 'Read .*\(contract core\)' 'payload over 48 kB falls back to the read instruction'
Assert-True (-not ($json.hookSpecificOutput.additionalContext -match 'xxxxxxxxxx')) 'oversize content is not emitted'

# 10. outside a git repo → exit 0, fallback
$nogit = Join-Path ([IO.Path]::GetTempPath()) ("mbnogit-" + [guid]::NewGuid().ToString('N').Substring(0, 8)); New-Item -ItemType Directory -Path $nogit | Out-Null
$res = Invoke-Hook $d $nogit 'SessionStart'
Assert-Eq $res.Code 0 'no git → exit 0'

Remove-Item -Recurse -Force $d, $d2, $d3, $r, $r2, $nogit
Complete-Tests
```

- [ ] **Step 2: Spusť; ověř červenou** (skript neexistuje).

- [ ] **Step 3: Napiš hook** — struktura podle `session-intent.ps1` (`Set-StrictMode`, `$ErrorActionPreference = 'Stop'`, `$PSNativeCommandUseErrorActionPreference = $false`, jeden tichý `catch`, vždy `exit 0`):

```powershell
#Requires -Version 7
# Contract core injector (contract, "Session Eligibility"; design UMS-3551, §3).
# SessionStart and UserPromptSubmit(after a compaction marker) inject the core
# as additionalContext; PostCompact cannot carry additionalContext (Claude Code
# hooks reference), so it writes a marker and a systemMessage instead.
# Informational hook: every failure path exits 0.
param([string] $Event = '')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$MaxPayloadBytes = 49152
$corePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'skills\shared\UMS_MEMORY_BANK_CONTRACT.md'
$FallbackText = "Read $corePath (contract core) and memory-bank/context.md before relying on any Memory Bank-aware behaviour."
$Instruction = 'Invoke the Skill tool with skill: using-superpowers first, then read your active skill''s references named in its banner. Then run the Session Eligibility check (contract, "Session Eligibility").'

function Emit-Context([string] $EventName, [string] $Text) {
    $p = [pscustomobject] @{ hookSpecificOutput = [pscustomobject] @{ hookEventName = $EventName; additionalContext = $Text } }
    Write-Output ($p | ConvertTo-Json -Depth 5 -Compress)
}
function Test-Hostile([string] $v) { return ($v -match '[<>]' -or $v -match '\p{Cc}' -or $v -match '\p{Cf}') }

try {
    if (-not $Event) {
        $stdin = ''
        try { if (-not [Console]::IsInputRedirected) { $stdin = '' } else { $stdin = [Console]::In.ReadToEnd() } } catch { $stdin = '' }
        if ($stdin) { try { $Event = [string] (($stdin | ConvertFrom-Json).hook_event_name) } catch { $Event = '' } }
    }
    if ($Event -notin @('SessionStart', 'PostCompact', 'UserPromptSubmit')) { exit 0 }

    $root = & git rev-parse --show-toplevel 2>$null
    $hasRoot = ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($root))
    if ($hasRoot) { $root = ([string] $root).Trim() }
    $marker = if ($hasRoot) { Join-Path (Join-Path $root '.superpowers') 'contract-reload.flag' } else { '' }

    if ($Event -eq 'PostCompact') {
        if ($hasRoot) {
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $marker) | Out-Null
            [IO.File]::WriteAllText($marker, [datetimeoffset]::UtcNow.ToString('o'), (New-Object Text.UTF8Encoding($false)))
        }
        Write-Output (([pscustomobject] @{ systemMessage = 'Context was compacted. The contract core is re-injected with your next prompt; until then act on the summary and re-invoke the skill you are executing.' }) | ConvertTo-Json -Compress)
        exit 0
    }
    if ($Event -eq 'UserPromptSubmit') {
        if (-not $hasRoot -or -not (Test-Path -LiteralPath $marker -PathType Leaf)) { exit 0 }
        Remove-Item -LiteralPath $marker -Force
    }

    if (-not (Test-Path -LiteralPath $corePath -PathType Leaf)) { Emit-Context $Event $FallbackText; exit 0 }
    $coreText = Get-Content -LiteralPath $corePath -Raw -Encoding utf8
    if ($null -eq $coreText -or [Text.Encoding]::UTF8.GetByteCount($coreText) -gt $MaxPayloadBytes) { Emit-Context $Event $FallbackText; exit 0 }

    $parts = @('<contract-core>', $coreText.TrimEnd(), '</contract-core>', '')
    $ctxLines = @('(context.md missing)')
    if ($hasRoot) {
        $ctxPath = Join-Path (Join-Path $root 'memory-bank') 'context.md'
        if (Test-Path -LiteralPath $ctxPath -PathType Leaf) {
            $raw = Get-Content -LiteralPath $ctxPath -Encoding utf8
            $ctxLines = @(@($raw) | Where-Object { $_ -match '^\s*-\s+\*\*[A-Za-z][A-Za-z ]+:\*\*\s+.*$' -or $_.Trim() -eq '(No active work - IDLE phase)' } | Where-Object { -not (Test-Hostile $_) })
            if ($ctxLines.Count -eq 0) { $ctxLines = @('(context.md carries no pin)') }
        }
    }
    $parts += @('<memory-bank-context>') + $ctxLines + @('</memory-bank-context>', '')

    if ($hasRoot) {
        $slugLine = @($ctxLines | Where-Object { $_ -match '\*\*(Work item|Proposal):\*\*\s+(?<s>\S+)' })
        if ($slugLine.Count -gt 0 -and $slugLine[0] -match '\*\*(Work item|Proposal):\*\*\s+(?<s>\S+)') {
            $ledger = Join-Path $root (".superpowers/sdd/plan_" + $Matches['s'] + "/progress.md")
            if (Test-Path -LiteralPath $ledger -PathType Leaf) {
                $l = @(Get-Content -LiteralPath $ledger -Encoding utf8)
                $b = [array]::IndexOf($l, '<!-- UMS-NOW BEGIN -->'); $e = [array]::IndexOf($l, '<!-- UMS-NOW END -->')
                if ($b -ge 0 -and $e -gt $b) {
                    $kv = @($l[($b + 1)..($e - 1)] | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
                    $ok = ($kv.Count -eq 6)
                    $rendered = @()
                    foreach ($line in $kv) {
                        $m = [regex]::Match($line, '^(?<k>State|Waiting on|Since|Due|Task|Look at):\s*(?<v>.*)$')
                        if (-not $m.Success -or (Test-Hostile $m.Groups['v'].Value)) { $ok = $false; break }
                        $rendered += "$($m.Groups['k'].Value): $($m.Groups['v'].Value.Trim())"
                    }
                    if ($ok) { $parts += @('<now-block>') + $rendered + @('</now-block>', '') } else { $parts += @('now-block: rejected (character class)', '') }
                }
            }
        }
    }
    $parts += $Instruction
    $payload = $parts -join "`n"
    if ([Text.Encoding]::UTF8.GetByteCount($payload) -gt $MaxPayloadBytes) { Emit-Context $Event $FallbackText; exit 0 }
    Emit-Context $Event $payload
}
catch { }
exit 0
```

- [ ] **Step 4: Spusť test, dolaď do zelené** — pak negativita: zaměň `Test-Hostile` za `return $false`, ověř červenou asercii 3; vrať.

- [ ] **Step 5: Zaregistruj v `ums/.claude/settings.json`** — první `SessionStart` záznam: `"command": "pwsh -NoProfile -File \"$CLAUDE_PROJECT_DIR/.claude/hooks/contract-inject.ps1\""`; `PostCompact` totéž; nový blok `"UserPromptSubmit": [{"hooks":[{"type":"command","command":"pwsh -NoProfile -File \"$CLAUDE_PROJECT_DIR/.claude/hooks/contract-inject.ps1\""}]}]`. Dnešní český text kontroly publikační záruky ze `SessionStart` si ulož do `.superpowers/scratch/eligibility-text.md` pro Task 7. Ověř v dokumentaci hooků (https://code.claude.com/docs/en/hooks, sekce UserPromptSubmit), že přijímá `hookSpecificOutput.additionalContext`; pokud by přijímala jen prostý stdout, hook pro tuto událost emituje payload jako prostý text místo JSON a test 5 se upraví na `Assert-Match $res.Out '<contract-core>'`.

- [ ] **Step 6: Přidej `UserPromptSubmit` do inventáře hooků v `session-intent.tests.ps1`?** Ne — ta sada kontroluje jen svůj záznam. Přidej do `contract-inject.tests.ps1` tvarovou kontrolu registrace: načti `ums/.claude/settings.json`, ověř, že `hooks.SessionStart[0].hooks[0].command`, `hooks.PostCompact[0].hooks[0].command` i `hooks.UserPromptSubmit[0].hooks[0].command` obsahují `contract-inject.ps1`.

- [ ] **Step 7: Commit**

```bash
git add ums/.claude/hooks/contract-inject.ps1 ums/.claude/hooks/tests/contract-inject.tests.ps1 ums/.claude/settings.json
git commit -m "UMS-3551: hook contract-inject vkládá jádro při startu a po kompaktaci"
```

### Task 7: Sekce „Session Eligibility" v jádře

**Files:**
- Modify: `ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md` (nová sekce za `## context.md Schema & Writers`)
- Modify: `ums/.claude/skills/shared/contract/workspace-discipline.md` (fáze 0 vstupní brány odkazuje na jádro místo vlastního textu)
- Test: `contract-shape.tests.ps1` (kontrola sekce `## Session Eligibility`)

- [ ] **Step 1: Spusť test tvaru, potvrď červenou asercii „jádro má právě jednu sekci ## Session Eligibility".**

- [ ] **Step 2: Napiš sekci** (anglicky, ≤ 30 řádků) z textu uloženého v Task 6 Step 5 a z dnešní fáze 0: `git fetch origin` (tvrdé selhání); hook `git rev-parse --git-path hooks/pre-push` existuje, nese marker `UMS pre-push guard (Publication Contract)` s verzí ne nižší než zdrojová hlavička `hooks/pre-push` (porovnání uspořádáním, `Get-UmsHookVersion.ps1`); syntetický self-check obou polovin s přesnými řádky: zamítací řádek musí používat NEOPUBLIKOVANÝ commit (`git commit-tree` visící objekt), protože obsahové pravidlo propouští už publikovaný tip (tasks.md, nález 6) — `printf 'refs/heads/<chráněná> <dangling-sha> refs/heads/<chráněná> <head-sha>\n' | <hook> origin verify` → nenulový exit a hláška `UMS:`; propouštěcí řádek `refs/heads/UMS-0000-probe <dangling-sha> refs/heads/UMS-0000-probe 0000000000000000000000000000000000000000` → exit 0 mlčky; průchod zamítacího řádku = chybějící marker agentní relace, selhání propouštěcího = hook se nespouští; obojí STOP pro práci končící pushem; `install-git-hooks.ps1` jako náprava starší verze; `ums-repo.json` jen informační.

- [ ] **Step 3: V `workspace-discipline.md` nahraď text fáze 0** větou `Phase 0 is the core's (contract, "Session Eligibility"); the phases below assume it passed.` s ponecháním zbytku beze změny.

- [ ] **Step 4: Spusť test tvaru** — sekce zelená; rozpočet stále ≤ 600.

- [ ] **Step 5: Commit**

```bash
git add ums/.claude/skills/shared
git commit -m "UMS-3551: způsobilost sezení jako sekce jádra, syntetický check s neopublikovaným commitem"
```

---

## Fáze C — pravidla

### Task 8: Granularita pracovní položky

**Files:**
- Modify: `ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md` (nová sekce `## Work Item Granularity` za `## Active Work Item`)
- Modify: `ums/.claude/skills/shared/contract/epic-backflow.md` (podsekce `### Split criteria and the cost of a split`)
- Modify: `ums/.claude/skills/mb-epic-elaboration/protocol.md` (krok 4 „Boundaries & partition", řádky 85–89)
- Modify: `ums/.claude/skills/shared/overlays/brainstorming.overlay.md` (nová odrážka před „Agentic opposition offer")
- Test: `contract-shape.tests.ps1` (sekce `## Work Item Granularity`)

- [ ] **Step 1: Spusť test tvaru; potvrď červenou asercii na sekci.**

- [ ] **Step 2: Sekce jádra** (≤ 12 řádků): `A work item is as large as the coherent whole one verification set can verify. It is split only by the split criteria (contract/epic-backflow.md, "Split criteria and the cost of a split"), never for size: size is carried by a plan with phases and TDD, not by the number of tickets. Fewer large tickets beat many small related ones — every ticket boundary is a place where a ruling is lost, a finding is orphaned or a shared file conflicts.`

- [ ] **Step 3: Reference `epic-backflow.md`**, podsekce: kritéria (samostatně dodatelný povrch nebo komponenta, odlišná množina blokátorů, růst rozsahu) **a zároveň** jiný aktér nebo jiná dodávka; cena dělení výčtem (návrh, plán, brána, harvest, Jira komentáře, řádky registru a předání na tiket; ztracený ruling, osiřelý nález, konflikt nad sdíleným souborem); výchozí odpověď „fáze v jednom plánu"; odkaz `Doklad: doklad/epic-backflow.md, "Granularity"` a doklad s evidencí z návrhu (UMS-3505 jeden tiket 50 commitů, UMS-3517 cena koordinace, zkušenost zadavatele 2026-09-17).

- [ ] **Step 4: `protocol.md` krok 4** — za „Split criteria: …" doplň: `A criterion alone does not split: the parts must also belong to a different actor or a different delivery, otherwise they are phases of one plan (contract, "Work Item Granularity"). Name the cost of the split in the ledger note when you do split.`

- [ ] **Step 5: Overlay brainstorming** — nová odrážka: `- **Decomposition (upstream "too large for a single spec"):** in this repository decomposition aims at PHASES of one plan first; a separate work item is created only under the split criteria (contract, "Work Item Granularity"), and then as a preliminary draft in proposals/next/ with a framing ticket (contract/jira.md, "Ticket description template").`

- [ ] **Step 6: Spusť test tvaru** (sekce zelená; citace na `jira.md` bude červená do Task 17 — zapiš do ledgeru). Grep `Select-String -Path ums/.claude -Pattern 'Work Item Granularity' -Recurse` → ≥ 3 soubory.

- [ ] **Step 7: Commit**

```bash
git add ums/.claude/skills
git commit -m "UMS-3551: granularita pracovní položky v jádře, elaboraci a brainstormingu"
```

### Task 9: Message Protocol v jádře, dno a pravidla ledgeru

**Files:**
- Modify: `ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md` (`## Message Protocol`, `## Escalation & Autonomy`)
- Modify: `ums/.claude/skills/shared/contract/escalation.md` (podsekce `### Ledger evidence rules`)
- Test: `contract-shape.tests.ps1` (řádek dna `playbook.md`)

- [ ] **Step 1: Spusť test tvaru; potvrď červenou na řádku dna «playbook.md».**

- [ ] **Step 2: Message Protocol v jádře** — za tři důsledky přidej dvě pravidla (každé jedna věta): `A ruling exists in a committed artifact — the ledger — BEFORE any message mentions it, and the message carries the commit SHA; a relay recipient confirms only what it has read in the ledger, never what it was told.` a `A claim about foreign code names how it was verified (file:line read, test run) or says "unverified".` Odkaz `Doklad: doklad/message-protocol.md, "Lost rulings and unverified claims"` a doklad s případy UMS-3517 (tři rulingy, citace `switch_channel.c:1005`).

- [ ] **Step 3: Dno v jádře** — nový řádek tabulky: `| Writing into playbook.md | the Playbook Contract's consult-before-write regime |`.

- [ ] **Step 4: `escalation.md`, podsekce `### Ledger evidence rules`**: (a) podlaha selhávajících testů je množina JMEN, nikdy číslo; řádek slibující „jména dodá sezení" je špinavý, dokud jména nedorazí (`ledger-status.ps1` hlásí); (b) každé měřené číslo v ledgeru nese podmínky běhu (strom, čistá vs. dávková ústředna, datum); (c) ruling odkládající práci na jiný tiket je řádek dirty-setu s vlastníkem toho tiketu a nese, co se stane, když ten tiket skončí dřív; `mb-epic-run integrate` a Handoff gate otevřené řádky jmenující integrující tiket vypíší (Task 12); (d) hlavička ledgeru nese `Ověřeno proti: <větev>@<sha>, <datum>` a zrcadla popisů tiketů razítko stažení (Task 10, Task 17).

- [ ] **Step 5: Spusť test tvaru** (dno zelené, rozpočet ≤ 600). Commit:

```bash
git add ums/.claude/skills/shared
git commit -m "UMS-3551: ruling před zprávou, dno pro playbook, pravidla evidence ledgeru"
```

### Task 10: Ledger — „Ověřeno proti" a „Podlaha testů"

**Files:**
- Modify: `ums/.claude/skills/mb-epic-elaboration/ledger-template.md` (hlavička řádek za `Poslední aktualizace`; nová sekce `## Podlaha testů` před `## Ověřovací sada`)
- Modify: `ums/.claude/skills/mb-epic-elaboration/scripts/ledger-status.ps1`
- Create: `ums/.claude/skills/mb-epic-elaboration/tests/fixtures/ledger_floor.md`
- Modify: `ums/.claude/skills/mb-epic-elaboration/tests/ledger-status.tests.ps1`

**Interfaces:**
- Produces: sekce `## Podlaha testů` s tabulkou `| Test (jméno) | Stav | Naměřil (tiket) | Podmínky běhu | Pozn. |`, `Stav` ∈ `červený | náladový`; `ledger-status.ps1` vypisuje `## Podlaha testů (N)` a hlásí issue `Podlaha testů musí být množina jmen testů, ne číslo: «<buňka>»` pro první buňku odpovídající `^[\d\s/]+$`, `Řádek podlahy «<buňka>» slibuje jména, která nedorazila` pro buňku obsahující `dodá`, `Řádek podlahy «<buňka>» nemá podmínky běhu` pro prázdný čtvrtý sloupec; hlavičkový řádek `- **Ověřeno proti:** <větev>@<sha>, <YYYY-MM-DD>` vypisuje v souhrnu, chybí-li, přidá poznámku `Hlavička nenese „Ověřeno proti" — stav větví není datovaný.` (poznámka, ne issue).

- [ ] **Step 1: Fixture `ledger_floor.md`** — minimální ledger (hlavička s `- **Epic:** UMS-1`, `- **Autonomie:** sdílená`, bez `Ověřeno proti`) a sekce:

```markdown
## Podlaha testů

| Test (jméno) | Stav | Naměřil (tiket) | Podmínky běhu | Pozn. |
|---|---|---|---|---|
| WfKic.Test.ChannelResync_ReconnectsAfterDrop | červený | UMS-3520 | čistá ústředna, develop@0a13ef1, 2026-09-16 | |
| 8/705/12/725 | červený | UMS-3518 | | číslo z jiného stromu |
| výsledek dodá sezení | červený | UMS-3520 | dávka | |
```

- [ ] **Step 2: Test** — přidej do `ledger-status.tests.ps1` (vzor existujících případů: spuštění `pwsh -File ledger-status.ps1 -LedgerFile <fixture>` a `Assert-Match` na výstup):

```powershell
$floorOut = (& pwsh -NoProfile -File $script -LedgerFile (Join-Path $fixtures 'ledger_floor.md') 2>&1 | Out-String)
Assert-Match $floorOut '## Podlaha testů \(3\)' 'sekce podlahy je vypsaná s počtem řádků'
Assert-Match $floorOut 'Podlaha testů musí být množina jmen testů, ne číslo: «8/705/12/725»' 'číselná podlaha je issue'
Assert-Match $floorOut 'slibuje jména, která nedorazila' 'slib bez jmen je issue'
Assert-Match $floorOut 'nemá podmínky běhu' 'chybějící podmínky jsou issue'
Assert-Match $floorOut 'Hlavička nenese „Ověřeno proti"' 'chybějící Ověřeno proti je poznámka'
Assert-True (-not ($floorOut -match 'ChannelResync_ReconnectsAfterDrop.*issue')) 'pojmenovaný test s podmínkami issue nedostane'
```

- [ ] **Step 3: Spusť; ověř červenou** (sekce se nevypisuje).

- [ ] **Step 4: Implementace v `ledger-status.ps1`** — vedle čtení `Rozjetí` (řádek ~57) přidej `$floor = Get-UmsLedgerSectionTable $lines 'Podlaha testů'`; v bloku issues:

```powershell
foreach ($f in @($floor | Where-Object { $_.Count -ge 1 -and $_[0] -and $_[0] -notmatch '^<' })) {
    if ($f[0] -match '^[\d\s/]+$') { $issuesFound += "Podlaha testů musí být množina jmen testů, ne číslo: «$($f[0])»" }
    elseif ($f[0] -match 'dodá') { $issuesFound += "Řádek podlahy «$($f[0])» slibuje jména, která nedorazila" }
    if ($f.Count -lt 4 -or [string]::IsNullOrWhiteSpace($f[3])) { $issuesFound += "Řádek podlahy «$($f[0])» nemá podmínky běhu" }
}
```
a ve výpisu sekcí `Write-Output "## Podlaha testů ($($floor.Count))"` s řádky `- <jméno> — <stav>, <tiket>, <podmínky>`; hlavička: regex `^\s*-\s+\*\*Ověřeno proti:\*\*\s*(.*)$` → `Write-Output "Ověřeno proti: $v"`, jinak poznámka.

- [ ] **Step 5: Šablona** — hlavička: `- **Ověřeno proti:** <větev>@<sha>, <YYYY-MM-DD> — stav větví, proti kterému správce naposledy přeměřil ledger; po kompaktaci kontextu je to první řádek, který se přečte`; sekce `## Podlaha testů` s vysvětlením (dvě věty: podlaha je množina jmen toho, co červené JE; číslo z jiného stromu není podlaha) a tabulkou se zástupným řádkem `| <jméno testu> | <červený \| náladový> | <UMS-0000> | <strom, konfigurace, datum> | |`.

- [ ] **Step 6: Spusť celou sadu `ledger-status.tests.ps1`** (dnes 41 asercí + nové) — zelená; negativita: dočasně odstraň větev `-match '^[\d\s/]+$'`, ověř červenou jedné asercie, vrať.

- [ ] **Step 7: Commit**

```bash
git add ums/.claude/skills/mb-epic-elaboration
git commit -m "UMS-3551: ledger nese Ověřeno proti a podlahu testů jako množinu jmen"
```

### Task 11: Per-tiketový soubor epiku

**Files:**
- Modify: `ums/.claude/skills/shared/contract/epic-backflow.md` (podsekce `### The per-ticket epic file`)
- Modify: `ums/.claude/skills/shared/overlays/brainstorming.overlay.md` (odrážka Epic Backflow, řádky 238–252)
- Modify: `ums/.claude/skills/shared/overlays/finishing-a-development-branch.overlay.md` (fáze Handoff, za řádek 336 „Exactly one rendering happens")
- Modify: `ums/.claude/skills/mb-epic-elaboration/protocol.md` (§0 bod 3 a §2 bod 1: čtení souborů z báze), `ums/.claude/skills/mb-epic-run/SKILL.md` (operace `integrate` a `status`: čtení souborů)

**Interfaces:**
- Produces: soubor `memory-bank/epics/<epic_snake>/tickets/<TICKET>.md` na tiketové větvi; hlavička `# <TICKET> — epic <EPIC>`; sekce `## Backflow` (řádky `- <YYYY-MM-DD> <nález> (zdroj: mb-epic-graph -Check)`) a `## Předání` (řádek `- <YYYY-MM-DD> <sha> → <báze>; sada: <příkazy>; commity: <n>`). Epic tiketu se zjišťuje z Jira pole `parent` (Jira režim) nebo z hlavičky návrhu `- **Epic:** <KEY>`; bez epiku se soubor nepíše.

- [ ] **Step 1: Reference** — podsekce: soubor je jediné chování backflow i předání pro tiket s epikem; žije na tiketové větvi, do báze dojede integrací; správce ho čte z báze modelem tahu (`git show <baseRef>:memory-bank/epics/<epik>/tickets/<TIKET>.md` nebo z `git ls-tree`); sdílený `notes.md` na bázi se nepíše (Doklad: dva konflikty modify/delete v UMS-3517). Pro tiket bez epiku se nic nepíše a nic nechybí.

- [ ] **Step 2: Overlay brainstorming** — v odrážce Epic Backflow nahraď „queue the ledger note" za: `write the finding into memory-bank/epics/<epic_snake>/tickets/<TICKET>.md, section ## Backflow, on the ticket branch (contract/epic-backflow.md, "The per-ticket epic file") — never into a shared notes.md on the base`.

- [ ] **Step 3: Overlay finishing** — do fáze Handoff přidej odstavec: `When the ticket belongs to an epic (Jira parent, or the design header's Epic line), append one line to memory-bank/epics/<epic_snake>/tickets/<TICKET>.md, section ## Předání — date, <sha>, destination branch, the verification commands, the outgoing commit count — and commit it on the ticket branch BEFORE the Publish phase's final push, so the handoff travels with the integration (contract/epic-backflow.md, "The per-ticket epic file"). This is the handoff artifact for a ticket that integrates without an epic line; the message to the manager, where there is one, is an acceleration over it.` Pozor na pořadí: zápis patří před poslední push fáze Publish, jinak by nebyl součástí integrovaného SHA — přidej větu do fáze Publish, že zahrnuje tento soubor.

- [ ] **Step 4: `protocol.md`** — §0 bod 3 doplň: `Read memory-bank/epics/<epic_snake>/tickets/*.md from the base ref (git ls-tree -r --name-only <baseRef> memory-bank/epics/<epic_snake>/tickets/ then git show) — the pulled backflow and handoff of integrated tickets; each entry is an agenda candidate.` `mb-epic-run/SKILL.md` operace `status`: tabulka doplní sloupec „Předáno" z těchto souborů na bázi.

- [ ] **Step 5: Ověř grepem** — `Select-String -Recurse -Path ums/.claude -Pattern 'notes\.md'` → jen historické zmínky v dokladu; `Select-String -Recurse -Path ums/.claude -Pattern 'tickets/<TICKET>\.md|tickets/\*\.md'` → ≥ 4 soubory. Test tvaru zelený.

- [ ] **Step 6: Commit**

```bash
git add ums/.claude/skills
git commit -m "UMS-3551: per-tiketový soubor epiku nese backflow i předání"
```

### Task 12: Odložené rulingy — varování brány epiku

**Files:**
- Modify: `ums/.claude/skills/mb-epic-run/scripts/epic-gate.ps1` (`Test-UmsEpicGate` vrací navíc `Warnings`)
- Modify: `ums/.claude/skills/mb-epic-run/tests/epic-gate.tests.ps1` + fixture s dirty řádkem
- Modify: `ums/.claude/skills/mb-epic-run/SKILL.md` (operace `integrate` vypisuje varování)

**Interfaces:**
- Produces: `Test-UmsEpicGate` → `@{ Ok; Checks; Blocking; Warnings = [string[]] }`; varování `otevřený řádek dirty-setu jmenuje integrující tiket <T>: <důvod> (zašpiněno oknem <W>)` pro každý řádek `## Dirty-set` s `Položka/Tiket -ceq $Ticket` a prázdným `Vyčištěno oknem`. Neblokuje.

- [ ] **Step 1: Test** — do `epic-gate.tests.ps1` přidej fixture ledger s tabulkou dirty-setu (řádek `| UMS-3520 | W03 | adoptér dialplanové půlky, tiket UMS-3518 už integrován | |`) a `Rozjetí` řádkem pro UMS-3520:

```powershell
$g = Test-UmsEpicGate -RepoRoot $repo -LedgerPath $ledgerDirty -Ticket 'UMS-3520' -Epic 'UMS-3517'
Assert-True $g.Ok 'otevřený dirty řádek neblokuje'
Assert-Eq @($g.Warnings).Count 1 'jedno varování za otevřený dirty řádek jmenující tiket'
Assert-Match $g.Warnings[0] 'adoptér dialplanové půlky' 'varování nese důvod'
$g2 = Test-UmsEpicGate -RepoRoot $repo -LedgerPath $ledgerClean -Ticket 'UMS-3520' -Epic 'UMS-3517'
Assert-Eq @($g2.Warnings).Count 0 'vyčištěný nebo cizí řádek varování nedává'
```

- [ ] **Step 2: Spusť; červená** (`Warnings` neexistuje → `$null.Count` pod StrictMode vyhodí).

- [ ] **Step 3: Implementace** — po bloku decision-ack:

```powershell
$dirtyRows = Get-UmsLedgerSectionTable $lines 'Dirty-set'
$warnings = @()
foreach ($d in @($dirtyRows | Where-Object { $_.Count -ge 3 -and $_[0] -ceq $Ticket -and ($_.Count -lt 4 -or [string]::IsNullOrWhiteSpace($_[3])) })) {
    $warnings += "otevřený řádek dirty-setu jmenuje integrující tiket $Ticket`: $($d[2]) (zašpiněno oknem $($d[1]))"
}
```
a do návratové hodnoty `Warnings = @($warnings)` v obou `return` větvích.

- [ ] **Step 4: Spusť celou sadu `epic-gate.tests.ps1`** (39 + nové) — zelená; negativita: zaměň `-ceq $Ticket` za `-ceq 'nikdo'`, červená, vrať.

- [ ] **Step 5: `mb-epic-run/SKILL.md`, operace `integrate`** — za výpis kontrol brány přidej krok: `Print $gate.Warnings in Czech under „Varování (neblokují)"; an open dirty row naming the integrating ticket means work was deferred onto it — before the fast-forward, re-own the row or close it with a reason, otherwise the finding is orphaned once the ticket is integrated (contract/escalation.md, "Ledger evidence rules").`

- [ ] **Step 6: Commit**

```bash
git add ums/.claude/skills/mb-epic-run
git commit -m "UMS-3551: brána epiku varuje před otevřenými dirty řádky integrujícího tiketu"
```

### Task 13: `pool-status` — víc živých sezení ve slotu

**Files:**
- Modify: `ums/.claude/skills/mb-epic-run/scripts/pool-status.ps1` (řádky ~582 a JSON per slot)
- Modify: `ums/.claude/skills/mb-epic-run/tests/stubs/claude-stub.ps1` (režim `multi`)
- Modify: `ums/.claude/skills/mb-epic-run/tests/pool-status.tests.ps1`
- Modify: `ums/.claude/skills/mb-epic-run/SKILL.md` (render `status`)

**Interfaces:**
- Produces: `session.count` v JSON slotu; důvod `multiple live sessions (pids <a>, <b>) — conflict, one session per workspace` místo `live session (pid …)`, když `pids.Count -gt 1`.

- [ ] **Step 1: Stub** — přidej větev `'multi' { Write-Output '[{"name":"UMS-0001","pid":101,"state":"idle"},{"name":"UMS-0001-old","pid":102,"state":"idle"}]'; exit 0 }`.

- [ ] **Step 2: Test** — vzor případu na řádcích 108–111 `pool-status.tests.ps1`:

```powershell
$env:MBPOOL_STUB_MODE = 'multi'
$r = Invoke-Status
$slot = Get-Slot $r.Data 'slot01'
Assert-Eq $slot.session.state 'live' 'dvě sezení jsou stále live'
Assert-Eq $slot.session.count 2 'počet živých sezení je v JSON'
Assert-True (-not $slot.free) 'slot se dvěma sezeními není volný'
Assert-True (@($slot.reasons) -match 'multiple live sessions \(pids 101, 102\)').Count -eq 1 'důvod jmenuje konflikt a oba pidy'
```

- [ ] **Step 3: Spusť; červená.**

- [ ] **Step 4: Implementace** — řádek 582:

```powershell
if ($session.state -eq 'live') {
    if (@($session.pids).Count -gt 1) { $reasons += "multiple live sessions (pids $($session.pids -join ', ')) — conflict, one session per workspace" }
    else { $reasons += "live session (pid $($session.pids -join ', '))" }
}
```
a do objektu `session` v JSON přidej `count = @($session.pids).Count`.

- [ ] **Step 5: Spusť celou sadu (120 + nové) — zelená; negativita: zaměň `-gt 1` za `-gt 9`, červená, vrať.**

- [ ] **Step 6: SKILL.md `status`** — v pravidlech renderu doplň: důvod začínající `multiple live sessions` se renderuje jako „**konflikt: víc živých sezení**" a je nálezem pro člověka (které sezení pokračuje), ne běžným obsazením.

- [ ] **Step 7: Commit**

```bash
git add ums/.claude/skills/mb-epic-run
git commit -m "UMS-3551: pool-status hlásí víc živých sezení ve slotu jako konflikt"
```

### Task 14: `mb-epic-run` — ověření spuštění a adresování sezení

**Files:**
- Modify: `ums/.claude/skills/mb-epic-run/SKILL.md` (krok 5 operace `spawn`, řádky 422–435; nová podsekce `### Addressing a session`)

- [ ] **Step 1: Krok 5** nahraď: `Wait on a CONDITION, not on a count of probes: re-run pool-status.ps1 every 30 s for up to 5 minutes until the slot's session.state == live; while waiting report „čekám na registraci sezení (Ns)", never „neobjevilo se". Only the timeout is the finding: „žádné nové sezení se neobjevilo do 5 minut — ověř na obrazovce". Measured 2026-09-17: two probes ~40 s apart both read none for a session that registered later.`

- [ ] **Step 2: Podsekce `### Addressing a session`**: dva registry (`ListAgents` / `claude agents --json` pro živé procesy s `cwd`, `sessionId`, `kind`; desktopový `list_sessions` pro tituly a stav) — neexistenci nikdy nesuď z jednoho; jméno agenta rotuje, identita je `sessionId`; před každým odesláním jméno znovu rozřeš podle `cwd` + `sessionId`; ruling do ledgeru před zprávou, zpráva nese SHA (contract, "Message Protocol").

- [ ] **Step 3: Ověř** `Select-String -Path ums/.claude/skills/mb-epic-run/SKILL.md -Pattern 'Two negative probes'` → 0; `-Pattern 'sessionId'` → ≥ 2.

- [ ] **Step 4: Commit**

```bash
git add ums/.claude/skills/mb-epic-run/SKILL.md
git commit -m "UMS-3551: spawn čeká na podmínku, adresování sezení podle sessionId a obou registrů"
```

---

## Fáze D — Jira

### Task 15: `permalinkTemplate` a `Get-UmsPermalink.ps1`

**Files:**
- Modify: `ums/.claude/skills/shared/scripts/Get-UmsRepoConfig.ps1` (klíč `PermalinkTemplate`)
- Modify: `ums/.claude/skills/shared/tests/repo-config.tests.ps1`
- Create: `ums/.claude/skills/shared/scripts/Get-UmsPermalink.ps1`
- Create: `ums/.claude/skills/shared/tests/permalink.tests.ps1`

**Interfaces:**
- Produces: `Get-UmsRepoConfig` vrací `PermalinkTemplate` (default `''`; přijímá jen neprázdný string); `Get-UmsPermalink -RepoRoot <r> -Sha <40hex> -Path <repo-relative> [-Template <t>]` → `@{ Url; Source = 'template'|'derived'; Host; Reason }`; `Url = $null` a `Reason` neprázdný při neznámém hostu, špatném SHA nebo cestě s `..`.

- [ ] **Step 1: Test konfigurace** — do `repo-config.tests.ps1`: soubor s `"permalinkTemplate": "https://git.example/{sha}/{path}"` → `PermalinkTemplate` rovno; bez klíče → `''`; klíč jako číslo → `''`.

- [ ] **Step 2: Test permalinku** (`permalink.tests.ps1`):

```powershell
#Requires -Version 7
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '_assert.ps1')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\scripts\Get-UmsPermalink.ps1')
function New-RepoWithOrigin([string] $Url) {
    $r = Join-Path ([IO.Path]::GetTempPath()) ("mbperma-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $r | Out-Null; git -C $r init -q; git -C $r remote add origin $Url; return $r
}
$sha = '50d222f0ee412a2450f084e40cd1eb3724ed2c38'
$gh = New-RepoWithOrigin 'https://github.com/janmatejka/superpowers'
$p = Get-UmsPermalink -RepoRoot $gh -Sha $sha -Path 'memory-bank/proposals/active/design_x.md'
Assert-Eq $p.Url "https://github.com/janmatejka/superpowers/blob/$sha/memory-bank/proposals/active/design_x.md" 'GitHub https remote → blob permalink'
Assert-Eq $p.Source 'derived' 'zdroj je odvození'
$bb = New-RepoWithOrigin 'git@bitbucket.org:datasyscz/ums.git'
$p = Get-UmsPermalink -RepoRoot $bb -Sha $sha -Path 'Doc/a.md'
Assert-Eq $p.Url "https://bitbucket.org/datasyscz/ums/src/$sha/Doc/a.md" 'Bitbucket ssh remote → src permalink'
$p = Get-UmsPermalink -RepoRoot $bb -Sha $sha -Path 'Doc/a.md' -Template 'https://git.example/{sha}/{path}'
Assert-Eq $p.Url "https://git.example/$sha/Doc/a.md" 'šablona má přednost'
Assert-Eq $p.Source 'template' 'zdroj je šablona'
$other = New-RepoWithOrigin 'https://gitea.internal/x/y.git'
$p = Get-UmsPermalink -RepoRoot $other -Sha $sha -Path 'a.md'
Assert-Eq $p.Url $null 'neznámý host nevrací URL'
Assert-Match $p.Reason 'unknown host' 'důvod jmenuje neznámý host'
$p = Get-UmsPermalink -RepoRoot $gh -Sha 'abc' -Path 'a.md'
Assert-Eq $p.Url $null 'krátké SHA je odmítnuté'
$p = Get-UmsPermalink -RepoRoot $gh -Sha $sha -Path '../secret.md'
Assert-Eq $p.Url $null 'cesta s .. je odmítnutá'
Remove-Item -Recurse -Force $gh, $bb, $other
Complete-Tests
```

- [ ] **Step 3: Spusť; červená.**

- [ ] **Step 4: Implementace `Get-UmsRepoConfig.ps1`** — do defaultů `PermalinkTemplate = ''`; za `epicBranchPattern` blok: `if ($propNames -contains 'permalinkTemplate' -and $json.permalinkTemplate -is [string] -and $json.permalinkTemplate.Trim() -ne '') { $cfg.PermalinkTemplate = [string]$json.permalinkTemplate }`.

- [ ] **Step 5: Implementace `Get-UmsPermalink.ps1`**:

```powershell
#Requires -Version 7
Set-StrictMode -Version Latest
function Get-UmsPermalink {
    param([Parameter(Mandatory)] [string] $RepoRoot, [Parameter(Mandatory)] [string] $Sha, [Parameter(Mandatory)] [string] $Path, [string] $Template = '')
    $out = @{ Url = $null; Source = ''; Host = ''; Reason = '' }
    if ($Sha -notmatch '^[0-9a-f]{40}$') { $out.Reason = 'sha must be 40 lowercase hex characters'; return $out }
    $p = $Path -replace '\\', '/'
    if ($p -match '(^|/)\.\.(/|$)' -or $p.StartsWith('/')) { $out.Reason = 'path must be repo-relative without ..'; return $out }
    if (-not [string]::IsNullOrWhiteSpace($Template)) {
        $out.Url = $Template.Replace('{sha}', $Sha).Replace('{path}', $p); $out.Source = 'template'; return $out
    }
    $remote = & git -C $RepoRoot remote get-url origin 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($remote)) { $out.Reason = 'origin remote not found'; return $out }
    $remote = ([string] $remote).Trim()
    $m = [regex]::Match($remote, '^(?:https?://(?:[^@/]+@)?|git@|ssh://git@)(?<host>[^/:]+)[:/](?<owner>[^/]+)/(?<repo>[^/]+?)(?:\.git)?/?$')
    if (-not $m.Success) { $out.Reason = "cannot parse origin url: $remote"; return $out }
    $host = $m.Groups['host'].Value.ToLowerInvariant(); $owner = $m.Groups['owner'].Value; $repo = $m.Groups['repo'].Value
    $out.Host = $host; $out.Source = 'derived'
    switch ($host) {
        'github.com'    { $out.Url = "https://github.com/$owner/$repo/blob/$Sha/$p" }
        'bitbucket.org' { $out.Url = "https://bitbucket.org/$owner/$repo/src/$Sha/$p" }
        default         { $out.Reason = "unknown host '$host' — set permalinkTemplate in ums-repo.json"; }
    }
    return $out
}
```

- [ ] **Step 6: Spusť obě sady — zelená; negativita: zaměň `'github.com'` za `'github.invalid'`, červená, vrať.**

- [ ] **Step 7: Commit**

```bash
git add ums/.claude/skills/shared/scripts/Get-UmsRepoConfig.ps1 ums/.claude/skills/shared/scripts/Get-UmsPermalink.ps1 ums/.claude/skills/shared/tests/repo-config.tests.ps1 ums/.claude/skills/shared/tests/permalink.tests.ps1
git commit -m "UMS-3551: permalink z konfigurace nebo odvozený z hostu origin"
```

### Task 16: `Test-UmsJiraDescription.ps1`

**Files:**
- Create: `ums/.claude/skills/shared/scripts/Test-UmsJiraDescription.ps1`
- Create: `ums/.claude/skills/shared/tests/jira-description.tests.ps1`

**Interfaces:**
- Produces: `Test-UmsJiraDescription -Text <string> [-Budget 2500] [-RequireSections]` → `@{ Ok; Findings = [string[]]; Length }`; nálezy (česky): `Popis má N znaků, rozpočet je 2500`, `Text odkazu obsahuje backticks: «…»`, `Tučné obaluje code span: «…»`, `Popis obsahuje ostré závorky, které Jira zahodí: «…»`, `Chybí sekce **Cíl**` / `**Rozsah**` / řádek `**Návrh (design):**`.

- [ ] **Step 1: Test**

```powershell
#Requires -Version 7
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '_assert.ps1')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\scripts\Test-UmsJiraDescription.ps1')
$good = "**Cíl**`n`nZmenšit vrstvu.`n`n**Rozsah**`n`nDovnitř:`n- A`n`n**Návrh (design):** [design_x.md](https://github.com/o/r/blob/0123456789abcdef0123456789abcdef01234567/design_x.md)`n`n**Ověření**`n`nSada zelená."
$r = Test-UmsJiraDescription -Text $good -RequireSections
Assert-True $r.Ok 'šablonový popis prochází'
$r = Test-UmsJiraDescription -Text ($good + ('x' * 2500))
Assert-True (-not $r.Ok) 'popis nad rozpočtem neprochází'
Assert-Match ($r.Findings -join ';') 'rozpočet je 2500' 'nález jmenuje rozpočet'
$r = Test-UmsJiraDescription -Text ($good -replace '\[design_x\.md\]', '[`design_x.md`]')
Assert-Match ($r.Findings -join ';') 'Text odkazu obsahuje backticks' 'backticks v textu odkazu jsou nález'
$r = Test-UmsJiraDescription -Text ($good + "`n**tučné `kód` uvnitř**")
Assert-Match ($r.Findings -join ';') 'Tučné obaluje code span' 'tučné kolem code spanu je nález'
$r = Test-UmsJiraDescription -Text ($good + "`nsoubory shared/contract/<téma>.md")
Assert-Match ($r.Findings -join ';') 'ostré závorky' 'ostré závorky jsou nález'
$r = Test-UmsJiraDescription -Text ($good -replace '\*\*Rozsah\*\*', '**Scope**') -RequireSections
Assert-Match ($r.Findings -join ';') 'Chybí sekce \*\*Rozsah\*\*' 'chybějící sekce je nález'
$r = Test-UmsJiraDescription -Text ($good -replace '\*\*Rozsah\*\*', '**Scope**')
Assert-True $r.Ok 'bez -RequireSections se sekce nekontrolují (komentáře)'
Complete-Tests
```

- [ ] **Step 2: Spusť; červená.**

- [ ] **Step 3: Implementace**

```powershell
#Requires -Version 7
Set-StrictMode -Version Latest
function Test-UmsJiraDescription {
    param([Parameter(Mandatory)] [AllowEmptyString()] [string] $Text, [int] $Budget = 2500, [switch] $RequireSections)
    $f = @()
    $len = $Text.Length
    if ($len -gt $Budget) { $f += "Popis má $len znaků, rozpočet je $Budget" }
    foreach ($m in [regex]::Matches($Text, '\[(?<t>[^\]]*)\]\((?<u>https?://[^)]+)\)')) {
        if ($m.Groups['t'].Value -match '`') { $f += "Text odkazu obsahuje backticks: «$($m.Groups['t'].Value)»" }
    }
    foreach ($m in [regex]::Matches($Text, '\*\*[^*\n]*`[^`\n]*`[^*\n]*\*\*')) { $f += "Tučné obaluje code span: «$($m.Value)»" }
    foreach ($m in [regex]::Matches($Text, '<[^>\n]+>')) { $f += "Popis obsahuje ostré závorky, které Jira zahodí: «$($m.Value)»" }
    if ($RequireSections) {
        foreach ($s in @('**Cíl**', '**Rozsah**')) { if ($Text -notmatch [regex]::Escape($s)) { $f += "Chybí sekce $s" } }
        if ($Text -notmatch '\*\*Návrh \(design\):\*\*') { $f += 'Chybí řádek **Návrh (design):**' }
    }
    return @{ Ok = ($f.Count -eq 0); Findings = @($f); Length = $len }
}
```

- [ ] **Step 4: Spusť — zelená; negativita: odstraň větev s backticks, červená, vrať.**

- [ ] **Step 5: Commit**

```bash
git add ums/.claude/skills/shared/scripts/Test-UmsJiraDescription.ps1 ums/.claude/skills/shared/tests/jira-description.tests.ps1
git commit -m "UMS-3551: kontrola popisu tiketu — rozpočet, odkazy, tučné, sekce"
```

### Task 17: Reference `jira.md`, `mb-jira-update`, `mb-epic-elaboration`

**Files:**
- Create: `ums/.claude/skills/shared/contract/jira.md`
- Modify: `ums/.claude/skills/mb-jira-update/SKILL.md` (§7, §7b, §7b-1 krok 2, §8)
- Modify: `ums/.claude/skills/mb-epic-elaboration/protocol.md` (§2 krok 6, §3 krok 7, §6 „New ticket needed")
- Modify: `ums/.claude/skills/mb-epic-elaboration/SKILL.md` (řádek 59 „reformulate ticket text")
- Test: `contract-shape.tests.ps1` (citace na `contract/jira.md`)

**Interfaces:**
- Produces: reference `jira.md` se sekcemi `## Ticket description template`, `## Description budget`, `## Link rules`, `## Read-back verification`, `## Permalink`, `## Description mirrors carry a fetch stamp`.

- [ ] **Step 1: Spusť test tvaru; potvrď červené citace na `contract/jira.md` (z Tasks 5 a 8).**

- [ ] **Step 2: Napiš `jira.md`** (anglicky; šablona jako český artefakt):

```markdown
# Jira (ticket text, links, permalinks)

Part of contract 3.x — the core is ../UMS_MEMORY_BANK_CONTRACT.md; cite as (contract/jira.md, "Section").

## Ticket description template

A ticket description is a FRAME; the detail lives in `design_<slug>.md` (proposals/next/ before activation). The Czech artifact, written verbatim:

    **Cíl**

    <do pěti vět: co se mění a proč>

    **Rozsah**

    Dovnitř:
    - <odrážky>

    Ven:
    - <odrážky>

    **Závislosti**

    <jen věty odkazující na linky; linky jsou pravda, próza je proč>

    **Návrh (design):** [design_<slug>.md](<commit-pinned permalink>)
    — or the sentence „vznikne v brainstormingu na tiketové větvi; odkaz doplní řešitel po commitu" while no commit exists.

    **Ověření**

    <do tří řádků>

## Description budget

2 500 characters. `Test-UmsJiraDescription.ps1 -RequireSections` runs before every description write; a finding is a STOP with the findings shown to the user. Doklad: doklad/jira.md, "Ticket sizes in UMS-3517".

## Link rules

- Link text never contains backticks; bold never wraps a code span; no angle brackets outside links. Jira's markdown normalisation drops the link or splits the bold otherwise. Doklad: doklad/jira.md, "Measured normalisation".
- Every link to a git object is commit-pinned and reachable on origin (contract, "Publication Contract").

## Read-back verification

After every write of a description or comment, read it back (`responseContentFormat: markdown`) and verify each link and each bold survived; text authored in a file is compared by diff (mb-jira-update §7b-1). A mismatch is reported, never patched blind.

## Permalink

The URL shape has ONE home: `Get-UmsPermalink.ps1` (template `permalinkTemplate` from ums-repo.json with `{sha}` and `{path}`, else derived from the origin host: bitbucket.org → `src/{sha}/{path}`, github.com → `blob/{sha}/{path}`; an unknown host is a STOP asking the user). No skill spells a host.

## Description mirrors carry a fetch stamp

A local mirror of a ticket description (`.superpowers/jira-desc/<TICKET>.md`) carries `Fetched: <ISO-8601 UTC>` on its first line; a mirror older than the ticket's `updated` field is re-fetched before use. Doklad: doklad/jira.md, "Stale mirror after compaction".
```

- [ ] **Step 3: `mb-jira-update/SKILL.md`** — §7: nahraď Bitbucket-only text větou `URL from Get-UmsPermalink.ps1 (contract/jira.md, "Permalink"); branch fallback stays disabled`; §7b-1 krok 2: regex `'^\*\*Návrh \(design\):\*\* \[.+\]\(https://bitbucket\.org/\S+\)$'` → `'^\*\*Návrh \(design\):\*\* \[[^`\]]+\]\(https?://\S+\)$'`; před `editJiraIssue` (§7b i §8) krok `Run Test-UmsJiraDescription.ps1 (-RequireSections for descriptions, without it for comments); a finding is a STOP`; §8 „Include the Bitbucket URLs as standard markdown links" → `Include commit-pinned permalinks as markdown links whose text carries no backticks (contract/jira.md, "Link rules")`; po komentáři zpětné přečtení (contract/jira.md, "Read-back verification").

- [ ] **Step 4: `protocol.md`** — §2 krok 6 doplň `Ticket text follows the template (contract/jira.md, "Ticket description template") and its budget; the elaboration itself goes into the draft.`; §3 krok 7: `**Návrh (proposal):**` → `**Návrh (design):**` (legacy tvar zůstává čitelný pro orákulum) a `Bitbucket permalink from mb-jira-update §5–7` → `permalink from Get-UmsPermalink.ps1 (contract/jira.md, "Permalink")`; §6: `add a ledger Tikety row` → `add a row to ## Členové (proposaly)`; invariant 6 (§5) spelling `**Návrh (design):**`. `SKILL.md` řádek 59: `reformulate ticket text` → `write ticket text from the template (contract/jira.md)`.

- [ ] **Step 5: Ověř** — `Select-String -Recurse -Path ums/.claude/skills -Pattern 'Návrh \(proposal\)'` → jen `mb-epic-graph` (tolerance legacy) a `mb-jira-update` §7b (idempotentní náhrada); `-Pattern 'bitbucket\.org'` → jen `Get-UmsPermalink.ps1` a doklad. Test tvaru zelený.

- [ ] **Step 6: Commit**

```bash
git add ums/.claude/skills
git commit -m "UMS-3551: reference jira.md — šablona tiketu, rozpočet, odkazy, permalink z konfigurace"
```

### Task 18: Drift nasazení ve forku

**Files:**
- Modify: `ums/.claude/hooks/contract-inject.ps1` (varovný řádek)
- Modify: `ums/.claude/hooks/tests/contract-inject.tests.ps1` (případ 11)
- Modify: `ums/.claude/skills/mb-state/SKILL.md` (nová položka reportu způsobilosti)

**Interfaces:**
- Produces: první řádek payloadu `WARNING: deployed contract core differs from source ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md — refresh the deployment (playbook, "Obnova nasazené kopie v tomto repu").` když v `MB_ROOT` existuje `ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md` a jeho SHA256 se liší od nasazeného jádra.

- [ ] **Step 1: Test** — v repu z `New-Repo` vytvoř `ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md` s jiným obsahem než `$core`; `Assert-Match … '^WARNING: deployed contract core differs'`; se shodným obsahem `Assert-True (-not (… -match 'WARNING: deployed'))`.

- [ ] **Step 2: Spusť; červená. Implementace**: po načtení `$coreText`, když `$hasRoot` a soubor zdroje existuje, porovnej `(Get-FileHash -Algorithm SHA256).Hash` obou; při rozdílu `$parts = @($warning, '') + $parts`.

- [ ] **Step 3: `mb-state/SKILL.md`** — do sekce způsobilosti workspace přidej položku: ve forku (existuje `ums/.claude/`) porovnat `Contract-Version` a hash `shared/**`, `mb-*/**`, `hooks/**` mezi `ums/.claude/` a `.claude/`; rozdíl je nález „nasazení za zdrojem" s příkazem obnovy z playbooku; mimo fork se položka přeskočí s poznámkou.

- [ ] **Step 4: Spusť `contract-inject.tests.ps1` — zelená. Commit:**

```bash
git add ums/.claude/hooks ums/.claude/skills/mb-state/SKILL.md
git commit -m "UMS-3551: varování před zastaralým nasazením vrstvy ve forku"
```

### Task 19: Uzávěrka — verze 3.0, dokumentace vrstvy, celá sada, nasazení

**Files:**
- Modify: `ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md` (`Contract-Version: 3.0`), `ums/.claude/skills/shared/CHANGELOG.md` (záznam 3.0), `ums/.claude/skills/shared/SKILLS_MANIFEST.md`, `ums/README.md`, `ums/CLAUDE.md.sample`, `ums/.claude/skills/shared/VENDORED_FROM.md` (odkaz na changelog)
- Test: celá sada vrstvy

- [ ] **Step 1: Verze** — jádro `- **Contract-Version:** 3.0`; `CHANGELOG.md` nahoře záznam `3.0 — core / references / doklad split; Session Eligibility; Work Item Granularity; Phase Map; Message Protocol ordering; escalation floor row for playbook.md; jira.md; permalinkTemplate; contract-inject hook (UMS-3551)`. Sweep na `2\.19` přes `ums/` a `memory-bank/` (playbook, „Bump verze kontraktu je vlastní sweep").

- [ ] **Step 2: Dokumentace** — `SKILLS_MANIFEST.md`: řádky pro `contract/`, `doklad/`, `CHANGELOG.md`, nové skripty a sady; `ums/README.md`: odstavec o jádru, referencích a hooku; `ums/CLAUDE.md.sample`: pokyn čte jádro a jmenuje, že hook ho vkládá.

- [ ] **Step 3: Celá sada** — spusť první příkaz Ověřovací sady; očekávání `ALL SUITES PASSED`; zapiš skutečný počet sad a asercí do ledgeru (spuštěním, ne aritmetikou).

- [ ] **Step 4: Obnova nasazené kopie** — podle playbooku zkopíruj `shared/`, `mb-*`, `hooks/`, `scripts/`, `settings.json` z `ums/.claude/` do `.claude/`; spusť `pwsh -NoProfile -File .claude/hooks/contract-inject.ps1 -Event SessionStart` z kořene repa a ověř, že payload nese `Contract-Version:** 3.0` a pin `ums_3551_jadro_a_doklad`; ohlas uživateli, že tři vendorované skilly s overlay bloky se obnoví až revendorem v monorepu.

- [ ] **Step 5: Commit**

```bash
git add ums
git commit -m "UMS-3551: kontrakt 3.0 — verze, changelog, manifest a dokumentace vrstvy"
```

---

## Self-review plánu

- **Pokrytí návrhu:** bod 1 princip → Tasks 2–4; bod 2 kontrakt → Tasks 1–5, 7; bod 3 hook → Task 6; bod 4 granularita → Task 8; bod 5 poznatky → Tasks 9–14; bod 6 Jira → Tasks 15–17; bod 7 drift → Task 18; Dopady (manifest, README, sample, verze) → Task 19. Memory Bank dokumenty tohoto repa aktualizuje harvest, ne plán.
- **Placeholdery:** žádný „TBD"; jediný podmíněný krok je Task 6 Step 5 (ověření pole `additionalContext` u `UserPromptSubmit` v dokumentaci) s oběma větvemi napsanými.
- **Konzistence jmen:** `Compare-UmsLineMultiset`, `Test-UmsContractMove`, `Get-UmsPermalink`, `Test-UmsJiraDescription`, `contract-inject.ps1`, marker `.superpowers/contract-reload.flag`, sekce jádra `Session Eligibility`, `Work Item Granularity`, `Phase Map`, `Citation & Versioning` — použité shodně v Tasks 4, 6, 7, 8, 15–19.
- **Pořadí a červené asercie testu tvaru:** Task 4 zavádí test, který zůstává částečně červený do Tasks 5, 7, 8 a 17; každý z těchto tasků jmenuje, kterou asercii zelená. Plné zelené je podmínkou Task 19.
