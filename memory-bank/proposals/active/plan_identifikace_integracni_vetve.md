# Identifikace integrační větve — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Jira:** (bez tiketu)
**Návrh:** [design_identifikace_integracni_vetve.md](design_identifikace_integracni_vetve.md)
**Target MB:** memory-bank/

**Goal:** Pracovní položka může mít vlastní integrační větev (například `origin/Branches/5.37`), zapsanou v `context.md`, a vrstva fail-closed vynutí, že taková větev je chráněná.

**Architecture:** Volitelný řádek `Báze:` v bloku `## Active Work` je novým zdrojem pravdy pro bázi jedné pracovní položky; když chybí, konzumenti padají na `baseRef` z `ums-repo.json`. Rozhodnutí „je zvolená báze chráněná?" počítá nová sdílená PowerShellová funkce, aby neexistovala třetí ručně psaná kopie porovnávání vzorů vedle `pre-push` a `guard-git-push.mjs`.

**Tech Stack:** Markdown (kontrakt, overlay fragmenty, `mb-*` skilly), PowerShell 7 (sdílené skripty a testy), git.

## Global Constraints

- **Jazyk podle kontraktu, sekce „Language Contract":** kontrakt, overlay fragmenty a těla `mb-*` skillů jsou AI-facing → **anglicky**. Uživatelské hlášky skriptů (`Write-Warning`, chybové texty) → **česky**, stejně jako je má dnes `Get-UmsRepoConfig.ps1`. Commit messages → **česky**.
- **Zdroj se edituje jen v `ums/.claude/`.** Kořenový `.claude/` a `.agents/skills/` jsou netrackovaná nasazení; nikdy se do nich needituje ručně.
- **Pravidlo má jeden domov:** normativní text patří do kontraktu, skill smí říct jen „per <jméno sekce>" plus co je čistě lokální. Věta parafrázující důvod v skillu je budoucí rozchod.
- **Odkazy v Memory Bank dokumentech** jsou relativní k obsahujícímu souboru a bez `#fragment` kotev.
- **`baseRef` už nese remote prefix** — nikdy se neprefixuje `origin/` podruhé. `<baseBranch>` = `baseRef` bez remote a **jediného** následujícího lomítka.
- **Testy:** bez Pesteru, offline, `_assert.ps1` v adresáři sady, `<téma>.tests.ps1`, fixtury pod `tests/fixtures/`.
- **PowerShell:** `#Requires -Version 7`, `Set-StrictMode -Version Latest`, `$ErrorActionPreference = 'Stop'`; české uvozovky jen v jednoduše uvozených literálech; `@()` kolem `Get-Content` před `.Count`.

---

### Task 1: Sdílená funkce pro porovnání větve s chráněnými vzory

**Files:**
- Create: `ums/.claude/skills/shared/scripts/Test-UmsProtectedBranch.ps1`
- Create: `ums/.claude/skills/shared/tests/protected-branch.tests.ps1`

**Interfaces:**
- Consumes: nic (čistá funkce, žádný git, žádné IO).
- Produces: `Test-UmsProtectedBranch([string] $Name, [string[]] $Patterns)` → `[pscustomobject]` s poli `Matched` ([bool]), `Evaluated` ([bool]), `BadPatterns` ([string[]]). Konzumuje ji Task 2 a Task 6.

**Kontext, který nesmí zapadnout.** `-like` a POSIX `case` v hooku se na vadném vzoru chovají různě — změřeno: `'Branches/5.37' -like 'Maint/[0-9'` vyhodí `WildcardPatternException`, zatímco `case` tentýž vzor tiše vyhodnotí jako no-match. Funkce proto rozlišuje „neodpovídá" od „nešlo vyhodnotit" jako **druhou** návratovou hodnotu. Volající pak dá stejnou odpověď jako hook (větev není chráněná), a `BadPatterns` navíc zviditelní vzor, který v hooku tiše nechrání nic.

- [ ] **Step 1: Write the failing test**

Create `ums/.claude/skills/shared/tests/protected-branch.tests.ps1`:

```powershell
#Requires -Version 7
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_assert.ps1')
. (Join-Path $PSScriptRoot '..\scripts\Test-UmsProtectedBranch.ps1')

Write-Host "== presna shoda"
$r = Test-UmsProtectedBranch 'develop' @('develop', 'main')
Assert-True $r.Matched 'develop odpovida vzoru develop'
Assert-True $r.Evaluated 'presna shoda je vyhodnotitelna'

Write-Host "== glob nad radou verzi"
$r = Test-UmsProtectedBranch 'Branches/5.37' @('Branches/*')
Assert-True $r.Matched 'Branches/5.37 odpovida vzoru Branches/*'

Write-Host "== neshoda"
$r = Test-UmsProtectedBranch 'Branches/5.37' @('release/*', 'develop')
Assert-True (-not $r.Matched) 'Branches/5.37 neodpovida vzorum release/* ani develop'
Assert-True $r.Evaluated 'neshoda platnych vzoru je vyhodnotitelna'

Write-Host "== vadny vzor: neshoda, ale NEvyhodnoceno"
$r = Test-UmsProtectedBranch 'Branches/5.37' @('Maint/[0-9')
Assert-True (-not $r.Matched) 'vadny vzor nesmi tvrdit shodu'
Assert-True (-not $r.Evaluated) 'vadny vzor hlasi nevyhodnoceno'
Assert-Eq (@($r.BadPatterns).Count) 1 'vadny vzor je vyjmenovan'
Assert-Eq (@($r.BadPatterns)[0]) 'Maint/[0-9' 'BadPatterns nese presne ten vzor'

Write-Host "== shoda vyhrava nad vadnym vzorem"
$r = Test-UmsProtectedBranch 'Branches/5.37' @('Branches/*', 'Maint/[0-9')
Assert-True $r.Matched 'nalezena shoda je dukaz ochrany bez ohledu na dalsi vzory'

Write-Host "== prazdny a nesmyslny vstup"
$r = Test-UmsProtectedBranch 'develop' @()
Assert-True (-not $r.Matched) 'prazdny seznam vzoru nechrani nic'
Assert-True $r.Evaluated 'prazdny seznam je vyhodnotitelny'
$r = Test-UmsProtectedBranch '' @('develop')
Assert-True (-not $r.Matched) 'prazdne jmeno vetve neodpovida nicemu'
$r = Test-UmsProtectedBranch 'develop' @('', '   ', 'develop')
Assert-True $r.Matched 'prazdne vzory se preskoci, platny vzor rozhodne'
Assert-True $r.Evaluated 'preskoceny prazdny vzor neni vadny vzor'

Complete-Tests
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `pwsh -NoProfile -File ums/.claude/skills/shared/tests/protected-branch.tests.ps1`
Expected: FAIL — dot-source neexistujícího `Test-UmsProtectedBranch.ps1` skončí chybou „The term ... is not recognized" nebo „Cannot find path".

- [ ] **Step 3: Write the implementation**

Create `ums/.claude/skills/shared/scripts/Test-UmsProtectedBranch.ps1`:

```powershell
<#
.SYNOPSIS
    Tests a branch name against protected-branch patterns (contract:
    "Repository Configuration") and reports whether the answer could be
    computed at all.

.DESCRIPTION
    The layer already matches globs against branch names in two places -
    the POSIX `sh` pre-push hook and guard-git-push.mjs - and the contract
    requires both to give the SAME answer for the same configuration. This
    is the PowerShell side; it exists so no third hand-written copy of the
    matching logic appears inside a skill body.

    Measured difference this function exists to absorb: `-like` throws
    WildcardPatternException on a malformed pattern (`Maint/[0-9`), while
    the hook's `case` statement treats the same pattern as a literal and
    reports no match. Reporting only a bool would therefore either lie
    ("protected" from a catch returning $true) or hide a configuration
    defect. Matched answers the question; Evaluated says whether every
    pattern could be tested; BadPatterns names the ones that could not -
    those protect nothing in the hook either, silently.

    A found match short-circuits: it is proof of protection, so later
    patterns do not need testing and Evaluated stays $true.

    Dot-source this file, then call Test-UmsProtectedBranch.
#>
Set-StrictMode -Version Latest

function Test-UmsProtectedBranch([string] $Name, [string[]] $Patterns) {
    $bad = [System.Collections.Generic.List[string]]::new()
    $matched = $false

    if (-not [string]::IsNullOrWhiteSpace($Name)) {
        foreach ($pattern in @($Patterns)) {
            if ([string]::IsNullOrWhiteSpace($pattern)) { continue }
            try {
                if ($Name -like $pattern) { $matched = $true; break }
            }
            catch {
                $bad.Add($pattern)
            }
        }
    }

    return [pscustomobject]@{
        Matched     = $matched
        Evaluated   = ($bad.Count -eq 0)
        BadPatterns = @($bad)
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `pwsh -NoProfile -File ums/.claude/skills/shared/tests/protected-branch.tests.ps1`
Expected: PASS, poslední řádek `<N> passed`, exit 0.

- [ ] **Step 5: Ověř sadu její vlastní negativitou**

Dočasně nahraď tělo `catch { $bad.Add($pattern) }` za `catch { }` a spusť sadu znovu. Očekávej červené právě asercie „vadny vzor hlasi nevyhodnoceno" a „vadny vzor je vyjmenovan". Pak soubor obnov z kopie před úpravou a potvrď prázdný `git diff` na cestě skriptu.

Asercie, které zůstanou zelené v obou během, uveď v reportu odděleně jako regresní zámek, ne jako důkaz opravy.

- [ ] **Step 6: Commit**

```bash
git add ums/.claude/skills/shared/scripts/Test-UmsProtectedBranch.ps1 ums/.claude/skills/shared/tests/protected-branch.tests.ps1
git commit -m "identifikace-integracni-vetve: sdílená funkce pro porovnání větve s chráněnými vzory"
```

---

### Task 2: Sestavení kandidátů báze

**Files:**
- Create: `ums/.claude/skills/shared/scripts/Get-UmsBaseCandidates.ps1`
- Create: `ums/.claude/skills/shared/tests/base-candidates.tests.ps1`

**Interfaces:**
- Consumes: `Test-UmsProtectedBranch` z Tasku 1; `Get-UmsRepoConfig` z `ums/.claude/skills/shared/scripts/Get-UmsRepoConfig.ps1`.
- Produces: `Get-UmsBaseCandidates([string] $RepoRoot, [string] $CurrentBranch)` → pole `[pscustomobject]` s poli `Ref` ([string], plně kvalifikovaný, například `origin/Branches/5.37`), `Branch` ([string], bez remote prefixu), `IsDefault` ([bool]), `IsCurrent` ([bool]). Řazení: výchozí báze první, pak aktuální větev, pak zbytek abecedně. Konzumuje ho Task 5 (overlay brainstormingu).

**Poznámka k enumeraci.** Vzdálené větve se čtou `--format='%(refname:lstrip=3)'` a filtrují `grep -v '^HEAD$'` — `%(refname:short)` ponechává remote prefix v každém jménu (a v `protectedBranches` pak nematchne nic) a pro symref `origin/HEAD` vrací holé `origin`.

- [ ] **Step 1: Write the failing test**

Create `ums/.claude/skills/shared/tests/base-candidates.tests.ps1`:

```powershell
#Requires -Version 7
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_assert.ps1')
. (Join-Path $PSScriptRoot '..\scripts\Get-UmsBaseCandidates.ps1')

function Invoke-Git([string] $Root, [string[]] $GitArgs) {
    & git -C $Root @GitArgs 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "git $($GitArgs -join ' ') selhalo v $Root" }
}

$tmp = Join-Path ([IO.Path]::GetTempPath()) ("ums-base-" + [Guid]::NewGuid().ToString('N'))
$bare = Join-Path $tmp 'origin.git'
$work = Join-Path $tmp 'work'
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
& git init --bare --initial-branch=develop $bare | Out-Null
& git init --initial-branch=develop $work | Out-Null
Invoke-Git $work @('remote', 'add', 'origin', $bare)
New-Item -ItemType Directory -Force -Path (Join-Path $work 'memory-bank') | Out-Null
Set-Content -LiteralPath (Join-Path $work 'memory-bank/ums-repo.json') -Encoding UTF8 -Value @'
{ "baseRef": "origin/develop", "protectedBranches": ["develop", "main", "Branches/*"] }
'@
Invoke-Git $work @('add', '-A')
Invoke-Git $work @('-c', 'user.email=t@t', '-c', 'user.name=t', 'commit', '-m', 'init')
foreach ($b in @('main', 'Branches/5.36', 'Branches/5.37', 'feature/UMS-1-neco')) {
    Invoke-Git $work @('branch', $b)
}
Invoke-Git $work @('push', '--no-verify', 'origin', '--all')

Write-Host "== kandidati jsou jen chranene vetve existujici na origin"
$c = Get-UmsBaseCandidates $work 'develop'
$refs = @($c | ForEach-Object { $_.Ref })
Assert-True ($refs -contains 'origin/develop') 'develop je kandidat'
Assert-True ($refs -contains 'origin/Branches/5.37') 'Branches/5.37 je kandidat'
Assert-True ($refs -contains 'origin/main') 'main je kandidat'
Assert-True (-not ($refs -contains 'origin/feature/UMS-1-neco')) 'pracovni vetev neni kandidat'
Assert-True (-not ($refs -contains 'origin')) 'symref origin/HEAD se nestal kandidatem'

Write-Host "== vychozi baze je prvni a je oznacena"
Assert-Eq (@($c)[0].Ref) 'origin/develop' 'vychozi baze je prvni v poradi'
Assert-True (@($c)[0].IsDefault) 'vychozi baze nese IsDefault'

Write-Host "== aktualni vetev je oznacena a razena hned za vychozi"
$c = Get-UmsBaseCandidates $work 'Branches/5.37'
$cur = @($c | Where-Object { $_.IsCurrent })
Assert-Eq (@($cur).Count) 1 'prave jedna vetev je oznacena jako aktualni'
Assert-Eq (@($cur)[0].Ref) 'origin/Branches/5.37' 'aktualni vetev je Branches/5.37'
Assert-Eq (@($c)[1].Ref) 'origin/Branches/5.37' 'aktualni vetev nasleduje hned za vychozi bazi'

Write-Host "== Branch je Ref bez remote prefixu, vcetne lomitka ve jmene"
$b = @($c | Where-Object { $_.Ref -eq 'origin/Branches/5.37' })[0].Branch
Assert-Eq $b 'Branches/5.37' 'strip odebira jen remote a jedno lomitko'

Write-Host "== aktualni vetev mimo chranene se kandidatem nestava"
$c = Get-UmsBaseCandidates $work 'feature/UMS-1-neco'
Assert-True (-not (@($c | ForEach-Object { $_.Ref }) -contains 'origin/feature/UMS-1-neco')) `
    'nechranena aktualni vetev neni nabidnuta jako baze'

Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
Complete-Tests
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `pwsh -NoProfile -File ums/.claude/skills/shared/tests/base-candidates.tests.ps1`
Expected: FAIL — `Get-UmsBaseCandidates.ps1` neexistuje.

- [ ] **Step 3: Write the implementation**

Create `ums/.claude/skills/shared/scripts/Get-UmsBaseCandidates.ps1`:

```powershell
<#
.SYNOPSIS
    Lists the branches that may serve as the integration base of a work
    item: the protected branches that actually exist on origin.

.DESCRIPTION
    Candidates come from the intersection of two facts - what the
    repository configuration protects, and what really exists on the
    remote. The contract's invariant is that an integration branch is
    always a protected branch, so a branch outside protectedBranches is
    never offered here; choosing one is a fail-closed STOP handled by the
    caller, together with the remedy.

    Ordering encodes the recommendation: the configured default first,
    then the branch the session stands on, then the rest alphabetically.

    Dot-source this file, then call Get-UmsBaseCandidates.
#>
#Requires -Version 7
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'Get-UmsRepoConfig.ps1')
. (Join-Path $PSScriptRoot 'Test-UmsProtectedBranch.ps1')

function Get-UmsBaseCandidates([string] $RepoRoot, [string] $CurrentBranch) {
    $cfg = Get-UmsRepoConfig $RepoRoot

    # lstrip=3 drops refs/remotes/origin, leaving the plain branch name -
    # the same shape pre-push matches after stripping refs/heads/.
    # %(refname:short) would keep the remote in every name (matching
    # nothing in protectedBranches) and emit a bare "origin" for the
    # origin/HEAD symref.
    $names = @(& git -C $RepoRoot for-each-ref --format='%(refname:lstrip=3)' refs/remotes/origin/ 2>$null) |
        Where-Object { $_ -and $_ -ne 'HEAD' }

    $defaultBranch = $cfg.BaseRef -replace '^[^/]+/', ''

    $candidates = foreach ($name in $names) {
        $test = Test-UmsProtectedBranch $name $cfg.ProtectedBranches
        if (-not $test.Matched) { continue }
        [pscustomobject]@{
            Ref       = "origin/$name"
            Branch    = $name
            IsDefault = ($name -eq $defaultBranch)
            IsCurrent = ($name -eq $CurrentBranch)
        }
    }

    return @($candidates | Sort-Object `
        @{ Expression = { -not $_.IsDefault } }, `
        @{ Expression = { -not $_.IsCurrent } }, `
        @{ Expression = { $_.Branch } })
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `pwsh -NoProfile -File ums/.claude/skills/shared/tests/base-candidates.tests.ps1`
Expected: PASS, `<N> passed`, exit 0.

- [ ] **Step 5: Ověř sadu její vlastní negativitou**

Dočasně změň `--format='%(refname:lstrip=3)'` na `--format='%(refname:short)'` a spusť sadu znovu. Očekávej červené asercie o kandidátech (jména ponesou prefix `origin/`, takže neprojdou vzory) a o symrefu. Obnov soubor a potvrď prázdný `git diff`.

- [ ] **Step 6: Commit**

```bash
git add ums/.claude/skills/shared/scripts/Get-UmsBaseCandidates.ps1 ums/.claude/skills/shared/tests/base-candidates.tests.ps1
git commit -m "identifikace-integracni-vetve: sestavení kandidátů integrační větve z chráněných větví na origin"
```

---

### Task 3: Čtení efektivní báze z `context.md`

**Files:**
- Create: `ums/.claude/skills/shared/scripts/Get-UmsEffectiveBase.ps1`
- Create: `ums/.claude/skills/shared/tests/effective-base.tests.ps1`

**Interfaces:**
- Consumes: `Get-UmsRepoConfig` z `ums/.claude/skills/shared/scripts/Get-UmsRepoConfig.ps1`.
- Produces: `Get-UmsEffectiveBase([string] $RepoRoot)` → `[pscustomobject]` s poli `Ref` ([string], například `origin/Branches/5.37`), `Branch` ([string], push destinace `<baseBranch>`), `Source` ([string], `'context'` nebo `'config'`). Konzumují ho Tasky 6 (`mb-state`, `mb-park`).

**Proč skript, a ne jen instrukce.** Bez něj by pravidlo „řádek `Báze:` má přednost před `baseRef`" existovalo pouze jako věta v Markdownu, kterou nelze otestovat ani ověřit jinak než čtením. Parsování `context.md` má díky němu jedno místo a derivace `<baseBranch>` jednu implementaci — a právě ta derivace je past, kterou kontrakt popisuje jmenovitě: strip k POSLEDNÍMU lomítku by z `origin/Branches/5.37` udělal `5.37` a push by založil novou vzdálenou větev místo aktualizace báze.

- [ ] **Step 1: Write the failing test**

Create `ums/.claude/skills/shared/tests/effective-base.tests.ps1`:

```powershell
#Requires -Version 7
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_assert.ps1')
. (Join-Path $PSScriptRoot '..\scripts\Get-UmsEffectiveBase.ps1')

$tmp = Join-Path ([IO.Path]::GetTempPath()) ("ums-eff-" + [Guid]::NewGuid().ToString('N'))
$mb = Join-Path $tmp 'memory-bank'
New-Item -ItemType Directory -Force -Path $mb | Out-Null
Set-Content -LiteralPath (Join-Path $mb 'ums-repo.json') -Encoding UTF8 -Value '{ "baseRef": "origin/ums-memory-bank" }'

Write-Host "== bez context.md padne na konfiguraci"
$e = Get-UmsEffectiveBase $tmp
Assert-Eq $e.Ref 'origin/ums-memory-bank' 'bez context.md plati baseRef'
Assert-Eq $e.Source 'config' 'zdroj je konfigurace'

Write-Host "== context.md bez radku Baze padne na konfiguraci"
Set-Content -LiteralPath (Join-Path $mb 'context.md') -Encoding UTF8 -Value @'
# Context

## Active Work

- **Jira:** (bez tiketu)
- **Target MB Pin:** memory-bank/
- **Work item:** neco
- **Started:** 2026-08-11
'@
$e = Get-UmsEffectiveBase $tmp
Assert-Eq $e.Ref 'origin/ums-memory-bank' 'chybejici radek Baze znamena vychozi bazi'
Assert-Eq $e.Source 'config' 'zdroj je konfigurace i s existujicim context.md'

Write-Host "== radek Baze ma prednost pred baseRef"
Set-Content -LiteralPath (Join-Path $mb 'context.md') -Encoding UTF8 -Value @'
# Context

## Active Work

- **Jira:** (bez tiketu)
- **Target MB Pin:** memory-bank/
- **Work item:** neco
- **Báze:** origin/Branches/5.37
- **Started:** 2026-08-11
'@
$e = Get-UmsEffectiveBase $tmp
Assert-Eq $e.Ref 'origin/Branches/5.37' 'radek Baze prebiji baseRef'
Assert-Eq $e.Source 'context' 'zdroj je context.md'

Write-Host "== derivace push destinace strhava jen JEDNO lomitko"
Assert-Eq $e.Branch 'Branches/5.37' 'Branch je Ref bez remote, lomitko ve jmene zustava'

Write-Host "== IDLE stav se zachovanym radkem Baze (integrace bezi po resetu)"
Set-Content -LiteralPath (Join-Path $mb 'context.md') -Encoding UTF8 -Value @'
# Context

## Active Work

(No active work - IDLE phase)

- **Jira:** (bez tiketu)
- **Báze:** origin/Branches/5.37
'@
$e = Get-UmsEffectiveBase $tmp
Assert-Eq $e.Ref 'origin/Branches/5.37' 'zachovany radek plati i v IDLE stavu'
Assert-Eq $e.Source 'context' 'IDLE nemeni zdroj'

Write-Host "== bez konfigurace i bez context.md plati vestaveny default"
$bare = Join-Path ([IO.Path]::GetTempPath()) ("ums-eff2-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path (Join-Path $bare 'memory-bank') | Out-Null
$e = Get-UmsEffectiveBase $bare
Assert-Eq $e.Ref 'origin/develop' 'vestaveny default baseRef'
Assert-Eq $e.Branch 'develop' 'derivace nad vestavenym defaultem'

Remove-Item -Recurse -Force $tmp, $bare -ErrorAction SilentlyContinue
Complete-Tests
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `pwsh -NoProfile -File ums/.claude/skills/shared/tests/effective-base.tests.ps1`
Expected: FAIL — `Get-UmsEffectiveBase.ps1` neexistuje.

- [ ] **Step 3: Write the implementation**

Create `ums/.claude/skills/shared/scripts/Get-UmsEffectiveBase.ps1`:

```powershell
<#
.SYNOPSIS
    Resolves the effective base of the current work item (contract:
    "Repository Configuration", the effective base).

.DESCRIPTION
    A work item may integrate somewhere other than the repository default -
    a maintenance branch of a release series carries the same role as
    develop for the work targeting it. The `- **Báze:**` line of
    context.md is therefore read first, and baseRef is the fallback.

    The line is read wherever it stands in the file, including under an
    IDLE marker: the harvest resets context.md, but the integration that
    follows still needs the push destination, so the line deliberately
    survives the reset.

    Branch strips the remote and the SINGLE following slash - never to the
    last slash. `origin/Branches/5.37` must yield `Branches/5.37`; `5.37`
    would make `git push origin HEAD:5.37` create a new remote branch
    instead of updating the base, and pre-push would not flag it because
    `Branches/*` does not match `5.37`.

    Dot-source this file, then call Get-UmsEffectiveBase.
#>
#Requires -Version 7
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'Get-UmsRepoConfig.ps1')

function Get-UmsEffectiveBase([string] $RepoRoot) {
    $ref = $null
    $source = 'config'

    $contextPath = Join-Path $RepoRoot 'memory-bank/context.md'
    if (Test-Path -LiteralPath $contextPath) {
        # @() so a single-line file still exposes .Count and indexing.
        foreach ($line in @(Get-Content -LiteralPath $contextPath)) {
            if ($line -match '^\s*-\s*\*\*Báze:\*\*\s*(\S+)\s*$') {
                $ref = $Matches[1]
                $source = 'context'
                break
            }
        }
    }

    if (-not $ref) {
        $ref = (Get-UmsRepoConfig $RepoRoot).BaseRef
    }

    return [pscustomobject]@{
        Ref    = $ref
        Branch = ($ref -replace '^[^/]+/', '')
        Source = $source
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `pwsh -NoProfile -File ums/.claude/skills/shared/tests/effective-base.tests.ps1`
Expected: PASS, `<N> passed`, exit 0.

- [ ] **Step 5: Ověř sadu její vlastní negativitou**

Dočasně změň `'^[^/]+/'` na `'^.*/'` a spusť sadu znovu. Očekávej červenou právě asercii „Branch je Ref bez remote, lomitko ve jmene zustava" (dostane `5.37`). Obnov soubor a potvrď prázdný `git diff`.

Pak dočasně odstraň větev `if (Test-Path …)` a ověř, že zčervenají obě asercie o přednosti řádku. Obnov znovu.

- [ ] **Step 6: Commit**

```bash
git add ums/.claude/skills/shared/scripts/Get-UmsEffectiveBase.ps1 ums/.claude/skills/shared/tests/effective-base.tests.ps1
git commit -m "identifikace-integracni-vetve: čtení efektivní báze z context.md s fallbackem na baseRef"
```

---

### Task 4: Kontrakt — efektivní báze, schéma `context.md`, invariant

**Files:**
- Modify: `ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md` (sekce „Repository Configuration" ~ř. 304–377, „Workspace Discipline" ~ř. 450–573, „`context.md` Schema & Writers" ~ř. 795–846, hlavička verze ~ř. 1–27)

**Interfaces:**
- Consumes: chování `Test-UmsProtectedBranch` z Tasku 1 (rozlišení „neodpovídá" × „nešlo vyhodnotit").
- Produces: normativní pojmy, na které se odkazují Tasky 5 a 6 — **„efektivní báze"**, **„invariant chráněné integrační větve"** a řádek `- **Báze:**` ve schématu `## Active Work`.

**Text je anglicky** (AI-facing instruction text), příklad schématu zůstává v tvaru, v jakém ho skilly čtou.

- [ ] **Step 1: Přidej definici efektivní báze do „Repository Configuration"**

Za odstavec začínající `**A missing file is not an error, and the degradation leans to the safer side:**` vlož:

```markdown
**The effective base of a work item.** A work item may integrate somewhere other
than the repository's default — a maintenance branch of a release series carries
the same role as `develop` for the work targeting it. The base of the CURRENT work
item is therefore read as:

> **Effective base** = the `- **Báze:**` line of the `## Active Work` block in
> `<CTX_DIR>/context.md`; when that line is absent, `baseRef` from
> `<CTX_DIR>/ums-repo.json`.

The line carries the same shape and the same rules as `baseRef` — a fully-qualified
remote-tracking ref, never prefixed with `origin/` a second time, and `<baseBranch>`
is derived from it by stripping the remote and the SINGLE following slash. It is
written only where the base differs from the default, so a repository that always
integrates into `baseRef` never sees it and behaves exactly as before.

**Invariant: an integration branch is always a protected branch.** A base that
matches no pattern in the effective `protectedBranches` is a fail-closed STOP at the
moment it is chosen — the agent would be free to push into it, which is the whole
guarantee this layer exists to keep. The remedy is ordered: add the missing pattern
to `ums-repo.json` (a targeted edit; `mb-init` is for founding or regenerating the
configuration as a whole, not for one pattern), re-run `install-git-hooks.ps1`
because the generated list is a build product of the configuration, PROVE with the
hook's own self-test that this specific branch is now rejected, and only then create
the ticket branch and commit the configuration change ON it — a commit made before
the branch exists is stranded on the shared base. Declining the remedy means
choosing a different base; there is no third path.

A pattern that cannot be evaluated at all (a malformed glob such as `Maint/[0-9`)
counts as NO match, which is the same answer the `pre-push` hook's `case` statement
gives it — and it is reported, because such a pattern silently protects nothing
there either.
```

- [ ] **Step 2: Rozšiř schéma `context.md`**

V sekci „`context.md` Schema & Writers" doplň do bloku aktivního stavu řádek `Báze:` a za blok jeho popis:

```markdown
- **Jira:** UMS-XXXX (https://jira.datasys.cz/browse/UMS-XXXX)
- **Target MB Pin:** <relative path>/memory-bank/
- **Work item:** <slug>
- **Báze:** origin/Branches/5.37
- **Started:** YYYY-MM-DD
- **Review:** design-review requested YYYY-MM-DD
```

```markdown
The `Báze:` line is OPTIONAL — present only when the work item integrates
somewhere other than `baseRef` (see Repository Configuration, the effective base).
Readers MUST tolerate its absence; that is the normal state.
```

- [ ] **Step 3: Zajisti, aby reset na IDLE řádek zachoval**

Uprav větu o IDLE stavu tak, aby zachovávala i tento řádek:

```markdown
IDLE state: replace the `## Active Work` items with
`(No active work - IDLE phase)`; keep the `- **Jira:** …` line of the last
work item if it existed, and keep the `- **Báze:** …` line for the same reason
with a sharper edge: the harvest resets `context.md` in its step 5, but the
INTEGRATION that follows still needs `<baseBranch>`. Dropping the line there would
silently send the integration command at the default base — the one branch the work
was deliberately not targeting.
```

- [ ] **Step 4: Doplň volbu báze do entry gate**

V sekci „Workspace Discipline", ve fázi 3 (**Intent**), doplň za výčet rozhodnutí:

```markdown
   **Choosing the base** belongs here, before the branch is created, because
   `git switch -c` needs it as its start point. Offer the candidates — the protected
   branches that exist on `origin`, ordered default first, then the branch the
   session stands on, then the rest — and let the USER decide; when a Jira ticket is
   linked and reachable, a version mentioned in its text is a further ordering
   signal (fail-open: an unreachable Jira skips that signal silently). Write the
   `Báze:` line in phase 4 only when the choice differs from `baseRef`. A base
   outside `protectedBranches` triggers the fail-closed STOP and its ordered remedy
   (Repository Configuration, the invariant).
```

- [ ] **Step 5: Zvyš verzi kontraktu**

V hlavičce souboru změň `- **Contract-Version:** 2.7` na `2.8` a nad řádek `- Supersedes v2.6 …` vlož:

```markdown
- Supersedes v2.7 (adds the effective base of a work item — the optional
  `Báze:` line in `context.md` with a fallback to `baseRef` — the invariant that an
  integration branch is always a protected branch, and the ordered remedy when it is
  not).
```

- [ ] **Step 6: Ověř, že v kontraktu nezůstal rozpor**

```bash
grep -n "Contract-Version" ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md
grep -n "effective base\|Effective base\|Báze:" ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md
grep -n "keep the \`- \*\*Jira:\*\*" ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md
```

Expected: verze `2.8` právě jednou; definice efektivní báze právě v jedné sekci (Repository Configuration), jinde jen odkazy na ni; věta o IDLE zmiňuje oba zachovávané řádky.

- [ ] **Step 7: Commit**

```bash
git add ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md
git commit -m "identifikace-integracni-vetve: kontrakt v2.8 — efektivní báze work itemu a invariant chráněné integrační větve"
```

---

### Task 5: Overlay fragmenty

**Files:**
- Modify: `ums/.claude/skills/shared/overlays/brainstorming.overlay.md` (kroky 3–4 a 6 v Item 1, ~ř. 56–87)
- Modify: `ums/.claude/skills/shared/overlays/subagent-driven-development.overlay.md` (base sync, ~ř. 51–59)
- Modify: `ums/.claude/skills/shared/overlays/finishing-a-development-branch.overlay.md` (~ř. 25, 30, 35, 43, 45, 48, 59, 90–91)

**Interfaces:**
- Consumes: pojmy „efektivní báze" a „invariant chráněné integrační větve" z Tasku 4; `Get-UmsBaseCandidates` z Tasku 2.
- Produces: nic pro další tasky (fragmenty jsou koncoví konzumenti).

**Pravidlo, které tenhle task nesmí porušit:** fragment smí říct „per <jméno sekce kontraktu>" plus co je čistě lokální (nástroj, pořadí vůči vlastním krokům). Věta parafrázující DŮVOD patří do kontraktu, ne sem.

- [ ] **Step 1: Vlož volbu báze do brainstorming fragmentu**

Do Item 1 vlož nový krok mezi stávající krok 3 (Jira ticket) a krok 4 (Create the ticket branch), a přečísluj následující kroky na 5, 6, 7:

```markdown
  4. **Choose the base** — the entry gate's intent phase decision, per the
     contract's "Repository Configuration" section (the effective base and the
     invariant that an integration branch is always a protected branch). Build the
     candidate list mechanically, never by hand:

     ```powershell
     . <mb-shared>/scripts/Get-UmsBaseCandidates.ps1
     Get-UmsBaseCandidates (git rev-parse --show-toplevel) (git branch --show-current)
     ```

     Present them in that order (default, current, rest) with `baseRef` as the
     recommendation and let the USER decide. With a linked and reachable Jira
     ticket, a version named in its text orders the list further; an unreachable
     Jira skips that signal with a one-line note. A base outside
     `protectedBranches` is the contract's fail-closed STOP — follow its ordered
     remedy and do NOT continue with an unprotected base.
```

V následujícím kroku (vytvoření větve) nahraď `<baseRef>` za `<zvolená báze>`:

```markdown
     `git switch -c <TICKET>-<kebab-slug> <chosen base>` after a
     `git fetch origin`, always with the explicit start point.
```

V kroku „Write the pin" doplň zápis řádku:

```markdown
     … `Target MB Pin`, `Jira`, `Work item` slug and `Started` into
     `memory-bank/context.md` — plus the `Báze:` line when the chosen base differs
     from `baseRef` (contract, `context.md` Schema & Writers). When the remedy of
     the previous step changed `ums-repo.json`, that change is still uncommitted and
     rode here with `switch -c`; commit it together with the pin.
```

- [ ] **Step 2: Uprav base sync v SDD fragmentu**

Nahraď `git merge <baseRef>` a jeho vysvětlivku:

```markdown
- **Base sync:** before dispatching the first task — a phase boundary — run
  `git fetch origin` and then `git merge <effective base>` on the ticket branch
  (the effective base per the contract's "Repository Configuration" section: the
  `Báze:` line of `context.md`, else `baseRef` from `<CTX_DIR>/ums-repo.json`),
  followed by the intersection assessment and the verification that follows from it
  per the contract's "Base Sync & Drift Detection" section.
```

- [ ] **Step 3: Uprav finishing fragment**

Nahraď každý z devíti výskytů `<baseRef>` / `<baseBranch>` odkazem na efektivní bázi. Na prvním výskytu (~ř. 25–26) uveď definici jednou:

```markdown
  one exists it is neither updated nor merged, and the **effective base** is the
  only base that counts (contract, "Repository Configuration": the `Báze:` line of
  `context.md`, else `baseRef` from `<CTX_DIR>/ums-repo.json`; `<baseBranch>` is
  derived from it by stripping the remote and the single following slash).
```

Na zbylých místech piš `<effective base>` (čtecí místa: merge, merge-base, switch --detach) a `<baseBranch>` (jediné push místo, `git push origin HEAD:<baseBranch>`) — obě hláskování sweepuj zvlášť, jde o dva nezávislé defekty, ne o jeden dvakrát.

- [ ] **Step 4: Ověř, že nezůstal osamocený `baseRef`**

```bash
grep -n "baseRef\|baseBranch\|effective base" ums/.claude/skills/shared/overlays/*.md
```

Expected: `baseRef` už jen uvnitř definic efektivní báze (tj. jako fallback), nikde jako samostatný příkaz k provedení. Push místo je právě jedno a používá `<baseBranch>`.

- [ ] **Step 5: Ověř přečíslování kroků v brainstorming fragmentu**

```bash
grep -n "step [0-9]\|item 1 step [0-9]\|kroku [0-9]" ums/.claude/skills/shared/overlays/brainstorming.overlay.md
```

Expected: žádná vnitřní křížová reference neukazuje na posunuté číslo. Kde reference existuje, odkazuj na sousední krok **jménem fáze**, ne pořadovým číslem — čísla se posouvají, jména ne.

- [ ] **Step 6: Commit**

```bash
git add ums/.claude/skills/shared/overlays/
git commit -m "identifikace-integracni-vetve: overlay fragmenty čtou efektivní bázi a nabízejí volbu integrační větve"
```

---

### Task 6: Skilly `mb-*`

**Files:**
- Modify: `ums/.claude/skills/mb-state/SKILL.md` (ř. 133–145, 234)
- Modify: `ums/.claude/skills/mb-park/SKILL.md` (ř. 56–74, 174, 250)
- Modify: `ums/.claude/skills/mb-harvest/SKILL.md` (ř. 64–76)
- Modify: `ums/.claude/skills/mb-jira-update/SKILL.md` (ř. 266–288)
- Modify: `ums/.claude/skills/mb-architect-review/SKILL.md` (ř. 111, 122–129, 137, 193, 218)

**Interfaces:**
- Consumes: pojmy z Tasku 4; `Test-UmsProtectedBranch` z Tasku 1 a `Get-UmsEffectiveBase` z Tasku 3 (pro `mb-park` a `mb-state`).
- Produces: nic pro další tasky.

- [ ] **Step 1: `mb-state` — čti efektivní bázi a řekni, odkud je**

Nahraď `<baseRef>` v obou příkazech (`git rev-list --count HEAD..<baseRef>` a `git show <baseRef>:memory-bank/context.md`) za `<effective base>` s odkazem „per the contract's Repository Configuration section". V šabloně reportu rozšiř řádek `Báze:` tak, aby uváděl původ a ochranu:

```
Báze: <effective base> (z context.md | výchozí z ums-repo.json) — chybí <N> commitů <(⚠️ ACTIVE stav na bázi — větev z ní zdědí cizí pin)> <(⛔ není mezi chráněnými větvemi)>
```

- [ ] **Step 2: `mb-park` — zpřísni STOP na kteroukoli chráněnou větev**

Nahraď dosavadní test „aktuální větev je `<baseBranch>`" testem proti celému seznamu:

```markdown
- **The current branch being ANY protected branch is a STOP** — tested with
  `Test-UmsProtectedBranch` (shared script) against the effective
  `protectedBranches`, not against a single derived name. Park leaves `context.md`
  in the ACTIVE state by design, and the contract's invariant is that a shared
  branch never carries ACTIVE state; publishing one there is impossible anyway, so
  park on such a branch can only ever end in a commit nobody can publish and nothing
  can move. Testing the whole list is both simpler and stricter than deriving one
  name from the base: a work item whose base is `origin/Branches/5.37` must not be
  parked on `develop` either.
```

Na ř. 174 (`or against <baseRef> when the branch has no upstream yet`) použij efektivní bázi; na ř. 250 v české hlášce nahraď `<baseRef>` za konkrétní efektivní bázi.

- [ ] **Step 3: `mb-harvest` — odvození `AFFECTED_MBS`**

Nahraď `git merge-base <baseRef> HEAD` za efektivní bázi a uprav navazující odstavec tak, aby jmenoval oba zdroje (řádek `Báze:`, jinak `baseRef`), včetně důvodu, proč se nepoužívá lokální bázová větev — ten zůstává beze změny.

- [ ] **Step 4: `mb-jira-update` — brána dosažitelnosti a lidský příkaz**

Nahraď `<baseRef>` v `git merge-base --is-ancestor <sha> <baseRef>` a `<baseBranch>` v `! UMS_ALLOW_SHARED_PUSH=1 git push origin HEAD:<baseBranch>` odvozením z efektivní báze. Zdůrazni, že `<baseBranch>` se odvozuje ze **zvolené** báze — kontrola dosažitelnosti proti výchozí bázi by u práce mířící do servisní větve prošla nebo neprošla ze špatného důvodu.

- [ ] **Step 5: `mb-architect-review` — branch sync a base merge**

Nahraď všech sedm výskytů `<baseRef>` efektivní bází. Pozor na ř. 122–129: větev se zakládá z efektivní báze, ale v režimu `request` je `context.md` už napsaný, takže řádek `Báze:` existuje a čte se z něj; v režimu, kde větev teprve vzniká, platí volba z entry gate.

- [ ] **Step 6: Ověř sweep napříč skilly**

```bash
grep -rn "baseRef\|baseBranch" ums/.claude/skills/mb-*/SKILL.md
```

Expected: `baseRef` se vyskytuje pouze jako pojmenovaný fallback uvnitř odkazu na efektivní bázi, nikde jako samostatná instrukce. Push místo je jediné (v `mb-jira-update`) a používá `<baseBranch>`.

- [ ] **Step 7: Commit**

```bash
git add ums/.claude/skills/mb-state/SKILL.md ums/.claude/skills/mb-park/SKILL.md ums/.claude/skills/mb-harvest/SKILL.md ums/.claude/skills/mb-jira-update/SKILL.md ums/.claude/skills/mb-architect-review/SKILL.md
git commit -m "identifikace-integracni-vetve: mb-* skilly čtou efektivní bázi, mb-park zpřísňuje STOP na chráněné větve"
```

---

### Task 7: Celá testová sada a obnova nasazení

**Files:**
- Modify: žádný zdrojový soubor; task ověřuje výsledek Tasků 1–6
- Refresh: `.claude/` a `.agents/skills/` (netrackovaná nasazení)

**Interfaces:**
- Consumes: výstup všech předchozích tasků.
- Produces: doložený zelený stav vrstvy.

- [ ] **Step 1: Spusť všechny testové sady vrstvy**

```bash
for t in $(find ums -name "*.tests.ps1"); do echo "== $t"; pwsh -NoProfile -File "$t" || echo "FAILED: $t"; done
```

Expected: každá sada končí `<N> passed` a nulovým exit kódem; žádný řádek `FAILED:`. Sada `pre-push.tests.ps1` běží přes dvě minuty, což je normální.

- [ ] **Step 2: Zaznamenej nový celkový počet asercí**

Sečti čísla z výstupu kroku 1 v tomto běhu a rekonciliuj proti dosavadním 564 přes delty, které zavedly Tasky 1, 2 a 3. Číslo nikdy neodvozuj aritmetikou z review nebo staršího zápisu — musí pocházet z běhu celé sady ve stejném sezení.

- [ ] **Step 3: Obnov nasazenou kopii vrstvy**

```bash
cp -r ums/.claude/hooks ums/.claude/scripts ums/.claude/skills ums/.claude/settings.json .claude/
cp -r ums/.claude/skills/. .agents/skills/
```

Vendorované skilly s overlay bloky (`brainstorming`, `subagent-driven-development`, `finishing-a-development-branch`) tímhle **nevzniknou** — vyrábí je revendor v monorepu. Do doby, než revendor proběhne, nese lokální nasazení jejich starou podobu; uveď to v reportu.

- [ ] **Step 4: Ověř, že nasazení odpovídá zdroji**

```bash
diff -rq ums/.claude .claude | grep -v "^Only in .claude/skills:" | grep -v "settings.local.json"
grep -m1 "Contract-Version" .claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md
```

Expected: první příkaz nevypíše žádný řádek `differ`; druhý vypíše `2.8`.

- [ ] **Step 5: Commit**

```bash
git add -A ums/
git commit -m "identifikace-integracni-vetve: zelená sada vrstvy po zavedení efektivní báze"
```

Pokud krok 1 až 4 nevytvořily žádnou změnu ve sledovaných souborech, commit vynech a ohlas to — nasazení je netrackované a samo o sobě není co commitovat.

---

## Co zůstává mimo tento plán

- **Revendor v monorepu** (`revendor-superpowers.ps1 -OverlaysOnly`) — overlay fragmenty se do vendorovaných skillů promítnou až tam.
- **Sync `ToMonorepo`** — fork nese novější testy hooků, které v monorepu chybí; musí předcházet nasazení této práce.
- **Náprava konfigurace monorepa** — vytvoření `ums-repo.json` s `Branches/*` a běh instalátoru hooků; bez ní zůstávají servisní větve v monorepu pro agenta nechráněné bez ohledu na tuto práci.
