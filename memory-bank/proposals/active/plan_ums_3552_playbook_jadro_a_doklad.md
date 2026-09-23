# Playbook — jádro a doklad: implementační plán

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Zavést strom playbooků s řetězcem předků, tvar souboru a položky, eskalační práh s ráčnou, harvestovou bránu v2 a konsolidační skill pro jednu MB i celý strom, a ověřit je na playbooku tohoto repa a nanečisto na monorepu.

**Architecture:** Mechaniku nesou sdílené dot-sourcované PowerShell funkce v `ums/.claude/skills/shared/scripts/` (parser, kontrola tvaru, strom a řetězec, shoda identifikátorů) a jeden param-blokový skript nového skillu `mb-playbook-consolidate` (`-Parse`, `-Apply`, `-Baseline`, `-Resume`, `-Stats`). Úsudek (triage, shlukování) nese analytik dispatchovaný skillem; zápis vždy schvaluje člověk nad tabulkou a provádí ho `-Apply`, i v harvestové bráně. Kontrakt se mění v referenci `contract/playbook-contract.md`; jádro jen řádkově neutrálně.

**Tech Stack:** PowerShell 7 (bez Pesteru, vlastní `_assert.ps1`), git, Markdown; nasazení kopií do `.claude/` a revendor overlayů.

**Spec:** [design_ums_3552_playbook_jadro_a_doklad.md](design_ums_3552_playbook_jadro_a_doklad.md)

## Global Constraints

- Práh souboru 600 řádků, práh řetězce 900 řádků, práh sekce 40 položek; překročení je varování, ne tvrdý nález.
- Pravidlo: nejvýš 4 řádky po 80 znacích, `Proč:` jedna věta (heuristika = varování), `Důkaz:` povinný (SHA, archivovaný návrh, test, nebo `návrh <slug>`).
- Postup: tučný název na vlastním řádku a nejvýš 15 řádků těla (položka tedy nejvýš 16 řádků); smí obsahovat blok příkazů nebo tabulku.
- Části doslova `## Pro celý podstrom` a `## Jen pro tento projekt`; sekce doslova začínají `### Když `.
- Ráčnový komentář doslova na druhém řádku: `<!-- playbook-budget: 600; baseline: <N> (<YYYY-MM-DD>[, <důvod>]) -->`.
- Tvrdé nálezy skriptu tvaru jsou právě tři a jen u souboru v novém tvaru: porušení tvaru; růst nad baseline; soubor nad prahem bez ráčnového komentáře.
- Soubor ve starém tvaru dostává jen varování a harvest nezastaví (legacy režim).
- Strom MB se odvozuje z `git ls-files`; `memory-bank/` vnořená v jiné `memory-bank/` se ignoruje.
- Jádro kontraktu `ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md` nesmí přesáhnout 800 řádků (hlídá `contract-shape.tests.ps1`); verze kontraktu se zvedá na 3.1.
- Testy: žádný Pester, `_assert.ps1` v každém adresáři testů, testy offline, fixtury MB pod `tests/fixtures/` nebo v dočasném adresáři; nová sada nastavuje `$ErrorActionPreference = 'Stop'`.
- Soubory vrstvy s LF konci řádků, UTF-8 bez BOM (`.claude/skills/**` a `.claude/hooks/pre-push` mají `eol=lf`).
- Jazyk: skripty, těla skillů, kontrakt a dispatch prompty anglicky; nálezy skriptů, reporty skillů, playbook, MB dokumenty a commit messages česky.
- Commit message se píše nástrojem Write do souboru a commituje `git commit -F <soubor>`; po commitu ověř diakritiku (`git log -1 --format=%B`). Každý commit tiketové větve se hned pushne (`git push origin UMS-3552-playbook-jadro-a-doklad`); chráněné větve (`ums-memory-bank`, `main`) agent nikdy nepushuje.
- Zápis do `playbook.md` vždy až po schválení člověkem (Playbook Contract, consult-before-write).
- Mimo `ums/` na této větvi měníš jen `memory-bank/` (CLAUDE.md, role větví).

## Ověřovací sada

```bash
for t in $(find ums -name "*.tests.ps1"); do echo "== $t"; pwsh -NoProfile -File "$t" || echo "FAILED: $t"; done
pwsh -NoProfile -Command '. ./ums/.claude/skills/shared/scripts/Test-UmsPlaybookShape.ps1; $r = Test-UmsPlaybookShape -Playbook memory-bank/playbook.md; $r.Warn; if ($r.Hard.Count) { $r.Hard; exit 1 }'
```

## Struktura souborů

| Soubor | Odpovědnost |
|---|---|
| `ums/.claude/skills/shared/scripts/Read-UmsPlaybook.ps1` | parser jednoho playbooku: tvar, položky, části, sekce, ráčna |
| `ums/.claude/skills/shared/scripts/Test-UmsPlaybookShape.ps1` | kontrola tvaru a prahů jednoho souboru a celého stromu |
| `ums/.claude/skills/shared/scripts/Get-UmsPlaybookChain.ps1` | strom MB, předkové, řetězec, nejnižší společný předek |
| `ums/.claude/skills/shared/scripts/Find-UmsPlaybookMatch.ps1` | shoda identifikátorů v backticks proti řetězci |
| `ums/.claude/skills/shared/tests/new-playbook-fixture.ps1` | fixturní git repo se stromem MB |
| `ums/.claude/skills/shared/tests/playbook-parse.tests.ps1` | parser |
| `ums/.claude/skills/shared/tests/playbook-shape.tests.ps1` | tvar a prahy souboru |
| `ums/.claude/skills/shared/tests/playbook-chain.tests.ps1` | strom, řetězec, LCA, kontrola stromu |
| `ums/.claude/skills/shared/tests/playbook-match.tests.ps1` | shoda identifikátorů |
| `ums/.claude/skills/shared/tests/tests-hygiene.tests.ps1` | hygiena všech sad vrstvy |
| `ums/.claude/skills/mb-playbook-consolidate/SKILL.md` | nový skill (jedna MB, `-Tree`) |
| `ums/.claude/skills/mb-playbook-consolidate/scripts/consolidate-playbook.ps1` | mechanika konsolidace a zápisu dispozic |
| `ums/.claude/skills/mb-playbook-consolidate/tests/consolidate.tests.ps1` + `_assert.ps1` | testy skriptu |
| `ums/.claude/skills/shared/contract/playbook-contract.md` | normativní text (přepis) |

---

## Fáze A — Mechanika

### Task A1: Parser playbooku

**Files:**
- Create: `ums/.claude/skills/shared/scripts/Read-UmsPlaybook.ps1`
- Create: `ums/.claude/skills/shared/tests/playbook-parse.tests.ps1`

**Interfaces:**
- Consumes: nic
- Produces:
  - `Read-UmsPlaybook([string] $Path)` → `[pscustomobject]` s vlastnostmi `Path` (string), `Shape` (`'new'` | `'legacy'`), `LineCount` (int, počet řádků bez koncového prázdného), `Lines` (string[]), `Ratchet` (`$null` nebo objekt `Budget`, `Baseline`, `Date`, `Reason`), `PreambleEnd` (int, 1-based řádek před prvním `##`, 0 když žádný), `Parts` (hashtable `podstrom`/`projekt` → `[pscustomobject]@{ Start; End }`, 1-based včetně nadpisu), `Sections` (seznam `[pscustomobject]@{ Part; Title; Line }`), `Items` (seznam položek).
  - Položka: `[pscustomobject]@{ Id (int, od 1); Kind ('pravidlo' | 'postup' | 'heading' | 'prose'); Part ('podstrom' | 'projekt' | $null); Section (string | $null); Title (string); StartLine; EndLine (1-based, bez koncových prázdných řádků); LineCount; Proc (string | $null); Dukaz (string | $null) }`.
  - `Get-UmsPlaybookRatchet([string[]] $Lines)` → objekt ráčny nebo `$null`.
  - `$script:UmsPlaybookPartTitles` — ordered hashtable `podstrom` → `Pro celý podstrom`, `projekt` → `Jen pro tento projekt`.

- [ ] **Step 1: Napiš padající test**

`ums/.claude/skills/shared/tests/playbook-parse.tests.ps1`:

```powershell
#Requires -Version 7
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_assert.ps1')
. (Join-Path $PSScriptRoot '..\scripts\Read-UmsPlaybook.ps1')

$tmp = Join-Path ([IO.Path]::GetTempPath()) ("pbparse-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $tmp | Out-Null
$fence = '`' * 3
function Write-Fx([string] $name, [string] $content) {
    $p = Join-Path $tmp $name
    [IO.File]::WriteAllText($p, ($content.Replace('@@FENCE@@', $fence) -replace "`r`n", "`n"), [Text.UTF8Encoding]::new($false))
    $p
}

Write-Host "== new shape"
$p = Write-Fx 'new.md' @'
# Playbook — test

Úvodní věta.

## Pro celý podstrom

### Když píšeš test

- **Pravidlo jedna.** Proč: důvod jedna. Důkaz: abc1234.
- **Pravidlo dvě na dva
  řádky.** Proč: důvod dvě. Důkaz: návrh ums_1_x.

**Postup instalace**
@@FENCE@@bash
- **tohle není položka**
pwsh -File install.ps1
@@FENCE@@
Proč: bez hooku není záruka.

## Jen pro tento projekt

### Když nasazuješ

- **Pravidlo tři.** Proč: důvod tři. Důkaz: test x.tests.ps1.
'@
$pb = Read-UmsPlaybook $p
Assert-Eq $pb.Shape 'new' 'new shape detected'
Assert-Eq $pb.Items.Count 4 'four items (fenced bullet is not an item)'
Assert-Eq $pb.Items[0].Kind 'pravidlo' 'item 1 is a rule'
Assert-Eq $pb.Items[0].Part 'podstrom' 'item 1 part'
Assert-Eq $pb.Items[0].Section 'Když píšeš test' 'item 1 section'
Assert-Eq $pb.Items[0].Proc 'důvod jedna.' 'item 1 Proč'
Assert-Eq $pb.Items[0].Dukaz 'abc1234.' 'item 1 Důkaz'
Assert-Eq $pb.Items[1].LineCount 2 'item 2 spans two lines'
Assert-Eq $pb.Items[2].Kind 'postup' 'item 3 is a procedure'
Assert-Eq $pb.Items[2].Title 'Postup instalace' 'procedure title'
Assert-Eq $pb.Items[2].LineCount 6 'procedure spans title, fence and Proč'
Assert-Eq $pb.Items[3].Part 'projekt' 'item 4 part'
Assert-Eq $pb.Parts['podstrom'].Start 5 'podstrom part starts at its heading'
Assert-Eq $pb.Parts['podstrom'].End 19 'podstrom part ends on the line before the next part heading'
Assert-Eq $pb.PreambleEnd 4 'preamble ends before first H2'
Assert-True ($null -eq $pb.Ratchet) 'no ratchet'

Write-Host "== legacy bold bullets"
$p = Write-Fx 'legacy-bullets.md' @'
# Playbook

## Testy vrstvy

Úvodní odstavec sekce.

- **Pravidlo A.** Proč: a.
- **Pravidlo B.**
  Proč: b.
'@
$pb = Read-UmsPlaybook $p
Assert-Eq $pb.Shape 'legacy' 'non-part H2 means legacy'
Assert-Eq $pb.Items.Count 3 'prose + two rules'
Assert-Eq $pb.Items[0].Kind 'prose' 'intro paragraph is prose'
Assert-Eq $pb.Items[1].Section 'Testy vrstvy' 'legacy section is the H2 title'
Assert-True ($null -eq $pb.Items[1].Part) 'legacy item has no part'
Assert-Eq $pb.Items[2].LineCount 2 'rule B spans two lines'

Write-Host "== legacy heading items"
$p = Write-Fx 'legacy-headings.md' @'
# Úkoly — X

## Úkoly

### Úkol A

1. krok jedna
2. krok dva

### Úkol B

Text úkolu B.

## Git push

Před pushem ověř větev.
'@
$pb = Read-UmsPlaybook $p
Assert-Eq $pb.Items.Count 3 'three heading items'
Assert-Eq (@($pb.Items | Where-Object Kind -eq 'heading')).Count 3 'all are heading items'
Assert-Eq $pb.Items[0].Title 'Úkol A' 'heading item title'
Assert-Eq $pb.Items[0].Section 'Úkoly' 'heading item section is parent heading'
Assert-Eq $pb.Items[0].LineCount 4 'heading item spans heading and body'
Assert-Eq $pb.Items[2].Title 'Git push' 'H2 heading item'

Write-Host "== transitional mix"
$p = Write-Fx 'legacy-mix.md' @'
# Playbook — Y

## Postup build

Spusť build.

## Rules

- **Pravidlo R.** Proč: r.
'@
$pb = Read-UmsPlaybook $p
Assert-Eq $pb.Items.Count 2 'heading item + rule'
Assert-Eq $pb.Items[0].Kind 'heading' 'first is heading item'
Assert-Eq $pb.Items[1].Kind 'pravidlo' 'second is rule'

Write-Host "== ratchet"
$p = Write-Fx 'ratchet.md' @'
# Playbook
<!-- playbook-budget: 600; baseline: 2414 (2026-09-23, konsolidace kolo 1) -->

## Pro celý podstrom
'@
$pb = Read-UmsPlaybook $p
Assert-Eq $pb.Ratchet.Budget 600 'ratchet budget'
Assert-Eq $pb.Ratchet.Baseline 2414 'ratchet baseline'
Assert-Eq $pb.Ratchet.Date '2026-09-23' 'ratchet date'
Assert-Eq $pb.Ratchet.Reason 'konsolidace kolo 1' 'ratchet reason'
Assert-Eq $pb.Shape 'new' 'part-only file is new shape'

Write-Host "== part heading plus foreign H2 is legacy"
$p = Write-Fx 'mixed-h2.md' @'
# P

## Pro celý podstrom

## Něco jiného
'@
Assert-Eq (Read-UmsPlaybook $p).Shape 'legacy' 'foreign H2 forces legacy'

Remove-Item -Recurse -Force $tmp
Complete-Tests
```

- [ ] **Step 2: Spusť test a ověř, že padá**

Run: `pwsh -NoProfile -File ums/.claude/skills/shared/tests/playbook-parse.tests.ps1`
Expected: selže na dot-source (`Read-UmsPlaybook.ps1` neexistuje), nenulový exit.

- [ ] **Step 3: Implementuj parser**

`ums/.claude/skills/shared/scripts/Read-UmsPlaybook.ps1`:

```powershell
#Requires -Version 7
# Dot-source this file, then call Read-UmsPlaybook -Path <playbook.md>.
# Parses a Memory Bank playbook (contract/playbook-contract.md, "Playbook shape")
# into items. Read-only; never writes.
Set-StrictMode -Version Latest

$script:UmsPlaybookPartTitles = [ordered]@{ podstrom = 'Pro celý podstrom'; projekt = 'Jen pro tento projekt' }
$script:UmsFenceRx = '^\s{0,3}(```|~~~)'
$script:UmsRuleRx = '^(?:- |\d+\. )\*\*(.+?)(?:\*\*|$)'
$script:UmsPostupRx = '^\*\*([^*].*?)\*\*\s*$'

function Get-UmsPlaybookRatchet([string[]] $Lines) {
    if ($Lines.Count -lt 2) { return $null }
    $m = [regex]::Match($Lines[1], '^<!-- playbook-budget: (\d+); baseline: (\d+) \((\d{4}-\d{2}-\d{2})(?:, (.+?))?\) -->$')
    if (-not $m.Success) { return $null }
    [pscustomobject]@{
        Budget   = [int]$m.Groups[1].Value
        Baseline = [int]$m.Groups[2].Value
        Date     = $m.Groups[3].Value
        Reason   = $(if ($m.Groups[4].Success) { $m.Groups[4].Value } else { $null })
    }
}

function Read-UmsPlaybook([string] $Path) {
    $raw = [IO.File]::ReadAllText($Path)
    $list = [Collections.Generic.List[string]]::new()
    foreach ($l in ($raw -split "`n")) { $list.Add($l.TrimEnd("`r")) }
    if ($list.Count -gt 0 -and $list[$list.Count - 1] -eq '') { $list.RemoveAt($list.Count - 1) }
    $lines = $list.ToArray()
    $n = $lines.Count

    # Pass 1: fences and headings (0-based line numbers internally).
    $inFence = $false
    $fenced = [bool[]]::new($n)
    $headings = [Collections.Generic.List[object]]::new()
    for ($i = 0; $i -lt $n; $i++) {
        if ($lines[$i] -match $script:UmsFenceRx) { $fenced[$i] = $true; $inFence = -not $inFence; continue }
        if ($inFence) { $fenced[$i] = $true; continue }
        $m = [regex]::Match($lines[$i], '^(#{1,6})\s+(.+?)\s*$')
        if ($m.Success) { $headings.Add([pscustomobject]@{ Line = $i; Level = $m.Groups[1].Value.Length; Title = $m.Groups[2].Value }) }
    }
    $isHeading = [bool[]]::new($n)
    foreach ($h in $headings) { $isHeading[$h.Line] = $true }

    $partTitles = @($script:UmsPlaybookPartTitles.Values)
    $h2 = @($headings | Where-Object Level -eq 2)
    $isNew = ($h2.Count -gt 0) -and (@($h2 | Where-Object { $partTitles -notcontains $_.Title }).Count -eq 0)
    $firstH2 = if ($h2.Count) { $h2[0].Line } else { $n }

    $parts = @{}
    $sections = [Collections.Generic.List[object]]::new()
    if ($isNew) {
        for ($k = 0; $k -lt $h2.Count; $k++) {
            $key = @($script:UmsPlaybookPartTitles.Keys | Where-Object { $script:UmsPlaybookPartTitles[$_] -eq $h2[$k].Title })[0]
            $end = if ($k + 1 -lt $h2.Count) { $h2[$k + 1].Line } else { $n }
            $parts[$key] = [pscustomobject]@{ Start = $h2[$k].Line + 1; End = $end }
        }
    }

    # Context of a 0-based line: part key and section title.
    $contextOf = {
        param([int] $line, [int] $ownHeading)
        $part = $null; $section = $null
        foreach ($h in $headings) {
            if ($h.Line -ge $line -or $h.Line -eq $ownHeading) { if ($h.Line -ge $line) { break } else { continue } }
            if ($h.Level -eq 2) {
                $section = $null
                $part = if ($isNew) { @($script:UmsPlaybookPartTitles.Keys | Where-Object { $script:UmsPlaybookPartTitles[$_] -eq $h.Title })[0] } else { $null }
                if (-not $isNew) { $section = $h.Title }
            } elseif ($h.Level -ge 3) { $section = $h.Title }
        }
        , @($part, $section)
    }

    $consumed = [bool[]]::new($n)
    $spans = [Collections.Generic.List[object]]::new()   # Kind, Start, End (0-based), Title, OwnHeading

    if (-not $isNew) {
        # Heading items: a heading (level >= 2) whose body has no rule starts and is not empty.
        for ($k = 0; $k -lt $headings.Count; $k++) {
            $h = $headings[$k]
            if ($h.Level -lt 2) { continue }
            $bodyEnd = if ($k + 1 -lt $headings.Count) { $headings[$k + 1].Line - 1 } else { $n - 1 }
            $hasRule = $false; $last = -1
            for ($i = $h.Line + 1; $i -le $bodyEnd; $i++) {
                if (-not $fenced[$i] -and $lines[$i] -match $script:UmsRuleRx) { $hasRule = $true }
                if ($lines[$i].Trim() -ne '') { $last = $i }
            }
            if ($hasRule -or $last -lt 0) { continue }
            for ($i = $h.Line; $i -le $last; $i++) { $consumed[$i] = $true }
            $spans.Add([pscustomobject]@{ Kind = 'heading'; Start = $h.Line; End = $last; Title = $h.Title; OwnHeading = $h.Line })
        }
    }

    # Rules, procedures and prose after the preamble.
    $cur = $null
    $close = { if ($null -ne $cur) { $spans.Add($cur) }; $null }
    for ($i = $firstH2; $i -lt $n; $i++) {
        if ($consumed[$i] -or $isHeading[$i]) { $cur = & $close; continue }
        $line = $lines[$i]
        if (-not $fenced[$i] -and $line -match $script:UmsRuleRx) {
            $cur = & $close
            $cur = [pscustomobject]@{ Kind = 'pravidlo'; Start = $i; End = $i; Title = $Matches[1].Trim(); OwnHeading = -1 }
            continue
        }
        if ($isNew -and -not $fenced[$i] -and $line -match $script:UmsPostupRx) {
            $cur = & $close
            $cur = [pscustomobject]@{ Kind = 'postup'; Start = $i; End = $i; Title = $Matches[1].Trim(); OwnHeading = -1 }
            continue
        }
        if ($line.Trim() -eq '') {
            if ($null -ne $cur -and $cur.Kind -eq 'prose') { $cur = & $close }
            continue
        }
        if ($null -ne $cur) { $cur.End = $i; continue }
        $cur = [pscustomobject]@{ Kind = 'prose'; Start = $i; End = $i; Title = $line.Trim(); OwnHeading = -1 }
    }
    $cur = & $close

    $items = [Collections.Generic.List[object]]::new()
    $id = 0
    foreach ($s in ($spans | Sort-Object Start)) {
        $id++
        $ctx = & $contextOf $s.Start $s.OwnHeading
        $ls = @($lines[$s.Start..$s.End])
        $joined = (($ls | ForEach-Object { $_.Trim() }) -join ' ')
        $pm = [regex]::Match($joined, 'Proč:\s*(.+?)(?=\s*Důkaz:|$)')
        $dm = [regex]::Match($joined, 'Důkaz:\s*(.+?)\s*$')
        $title = $s.Title
        if ($title.Length -gt 80) { $title = $title.Substring(0, 80) }
        $items.Add([pscustomobject]@{
            Id = $id; Kind = $s.Kind; Part = $ctx[0]; Section = $ctx[1]; Title = $title
            StartLine = $s.Start + 1; EndLine = $s.End + 1; LineCount = $s.End - $s.Start + 1
            Proc = $(if ($pm.Success) { $pm.Groups[1].Value } else { $null })
            Dukaz = $(if ($dm.Success) { $dm.Groups[1].Value } else { $null })
        })
    }
    foreach ($h in $headings) {
        if ($isNew -and $h.Level -eq 3) {
            $ctx = & $contextOf $h.Line -1
            $sections.Add([pscustomobject]@{ Part = $ctx[0]; Title = $h.Title; Line = $h.Line + 1 })
        }
    }

    [pscustomobject]@{
        Path = $Path; Shape = $(if ($isNew) { 'new' } else { 'legacy' }); LineCount = $n; Lines = $lines
        Ratchet = (Get-UmsPlaybookRatchet $lines); PreambleEnd = $firstH2
        Parts = $parts; Sections = $sections.ToArray(); Items = $items.ToArray()
    }
}
```

Poznámka pro implementátora: `Title` pravidla, jehož tučný úsek pokračuje na další řádek, je text do konce prvního řádku — test na to nespoléhá. Pokud `$contextOf` s parametrem `ownHeading` vyjde v kódu nepřehledně, přepiš ho na funkci se stejným chováním; testy jsou měřítkem, ne tvar kódu.

- [ ] **Step 4: Spusť test, ověř zelenou a negativitu**

Run: `pwsh -NoProfile -File ums/.claude/skills/shared/tests/playbook-parse.tests.ps1`
Expected: `<N> passed`, exit 0.

Negativita (playbook, „Nový regresní strážce/test ověř jeho vlastní negativitou"): dočasně zakomentuj v parseru řádek `if ($lines[$i] -match $script:UmsFenceRx) ...`, spusť sadu — musí zčervenat aspoň aserce „four items". Obnov soubor a ověř prázdný `git diff` na něm.

- [ ] **Step 5: Commit a push**

Zpráva do souboru přes Write, pak:

```bash
git add ums/.claude/skills/shared/scripts/Read-UmsPlaybook.ps1 ums/.claude/skills/shared/tests/playbook-parse.tests.ps1
git commit -F .superpowers/commit-msg.txt
git push origin UMS-3552-playbook-jadro-a-doklad
```

Zpráva: `UMS-3552: parser playbooku (nový a legacy tvar, části, sekce, ráčna)` + řádky ` - …` + `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

---

### Task A2: Kontrola tvaru a prahů souboru

**Files:**
- Create: `ums/.claude/skills/shared/scripts/Test-UmsPlaybookShape.ps1`
- Create: `ums/.claude/skills/shared/tests/playbook-shape.tests.ps1`

**Interfaces:**
- Consumes: `Read-UmsPlaybook`, `Get-UmsPlaybookRatchet` (A1).
- Produces:
  - `$script:UmsPlaybookLimits` = `@{ File = 600; Chain = 900; Section = 40; RuleLines = 4; RuleWidth = 80; PostupLines = 16 }`.
  - `Test-UmsPlaybookShape([string] $Playbook)` → `[pscustomobject]@{ Playbook; Shape; Lines; Hard (string[]); Warn (string[]) }`. Nálezy česky, každý začíná kódem v hranatých závorkách: `[tvar]`, `[ráčna-růst]`, `[ráčna-chybí]` (tvrdé); `[legacy]`, `[práh-soubor]`, `[práh-sekce]`, `[proč]`, `[ráčna-zbytečná]` (varování).

- [ ] **Step 1: Napiš padající test**

`ums/.claude/skills/shared/tests/playbook-shape.tests.ps1`:

```powershell
#Requires -Version 7
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_assert.ps1')
. (Join-Path $PSScriptRoot '..\scripts\Test-UmsPlaybookShape.ps1')

$tmp = Join-Path ([IO.Path]::GetTempPath()) ("pbshape-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $tmp | Out-Null
function Write-Fx([string] $name, [string] $content) {
    $p = Join-Path $tmp $name
    [IO.File]::WriteAllText($p, ($content -replace "`r`n", "`n"), [Text.UTF8Encoding]::new($false))
    $p
}
function New-Rules([int] $count, [string] $prefix) {
    (1..$count | ForEach-Object { "- **$prefix pravidlo $_.** Proč: důvod $_.`n  Důkaz: abc$_." }) -join "`n"
}
function Has([string[]] $list, [string] $code) { [bool](@($list | Where-Object { $_.StartsWith($code) }).Count) }

Write-Host "== valid small file"
$p = Write-Fx 'ok.md' ("# P`n`n## Pro celý podstrom`n`n### Když píšeš test`n`n" + (New-Rules 3 'A') + "`n")
$r = Test-UmsPlaybookShape $p
Assert-Eq $r.Hard.Count 0 'no hard findings'
Assert-Eq $r.Warn.Count 0 'no warnings'

Write-Host "== shape violations"
$long = 'x' * 81
$p = Write-Fx 'bad.md' @"
# P

## Pro celý podstrom

- **Mimo sekci.** Proč: a. Důkaz: b.

### Tematická sekce

- **Špatná sekce.** Proč: a. Důkaz: b.

### Když něco

- **Bez důkazu.** Proč: a.
- **$long** Proč: a. Důkaz: b.
- **Pět
  řádků
  pravidla
  je
  moc.** Proč: a. Důkaz: b.

Volný text mimo položku.
"@
$r = Test-UmsPlaybookShape $p
Assert-True (Has $r.Hard '[tvar] položka mimo sekci') 'item outside section'
Assert-True (Has $r.Hard '[tvar] sekce není ve tvaru') 'section not "Když"'
Assert-True (Has $r.Hard '[tvar] chybí Důkaz') 'missing Důkaz'
Assert-True (Has $r.Hard '[tvar] řádek delší než 80') 'line too wide'
Assert-True (Has $r.Hard '[tvar] pravidlo má') 'rule too long'
Assert-True (Has $r.Hard '[tvar] text mimo položku') 'prose outside item'

Write-Host "== legacy only warns"
$p = Write-Fx 'legacy.md' ("# P`n`n## Testy`n`n" + (New-Rules 320 'L') + "`n")
$r = Test-UmsPlaybookShape $p
Assert-Eq $r.Hard.Count 0 'legacy never hard'
Assert-True (Has $r.Warn '[legacy]') 'legacy warning'
Assert-True (Has $r.Warn '[práh-soubor]') 'legacy over threshold warning'

Write-Host "== over threshold without ratchet is hard"
$big = "# P`n`n## Pro celý podstrom`n`n" + ((1..8 | ForEach-Object { "### Když krok $_`n`n" + (New-Rules 38 "S$_") + "`n" }) -join "`n")
$p = Write-Fx 'big.md' $big
$r = Test-UmsPlaybookShape $p
Assert-True ($r.Lines -gt 600) 'fixture is over 600 lines'
Assert-True (Has $r.Hard '[ráčna-chybí]') 'missing ratchet is hard'
Assert-True (Has $r.Warn '[práh-soubor]') 'threshold warning'

Write-Host "== ratchet holds, growth is hard, recorded raise passes"
$lines = $big -split "`n"
$withR = @($lines[0], '<!-- playbook-budget: 600; baseline: 9999 (2026-09-23) -->') + @($lines[1..($lines.Count - 1)])
$p = Write-Fx 'ratchet-ok.md' ($withR -join "`n")
$r = Test-UmsPlaybookShape $p
Assert-Eq $r.Hard.Count 0 'under baseline passes'
$withR[1] = '<!-- playbook-budget: 600; baseline: 610 (2026-09-23) -->'
$p = Write-Fx 'ratchet-grow.md' ($withR -join "`n")
$r = Test-UmsPlaybookShape $p
Assert-True (Has $r.Hard '[ráčna-růst]') 'growth over baseline is hard'
$withR[1] = "<!-- playbook-budget: 600; baseline: $($withR.Count) (2026-09-24, nové pravidlo hooku) -->"
$p = Write-Fx 'ratchet-raised.md' ($withR -join "`n")
$r = Test-UmsPlaybookShape $p
Assert-True (-not (Has $r.Hard '[ráčna-růst]')) 'recorded raise passes'

Write-Host "== section threshold, Proč heuristic, useless ratchet"
$p = Write-Fx 'sec.md' ("# P`n<!-- playbook-budget: 600; baseline: 700 (2026-09-23) -->`n`n## Pro celý podstrom`n`n### Když píšeš`n`n" + (New-Rules 41 'Q') + "`n- **Dvě věty.** Proč: první věta. Druhá věta, např. tahle.`n  Důkaz: x.`n")
$r = Test-UmsPlaybookShape $p
Assert-True (Has $r.Warn '[práh-sekce]') 'section over 40 warns'
Assert-True (Has $r.Warn '[proč]') 'two-sentence Proč warns'
Assert-True (Has $r.Warn '[ráčna-zbytečná]') 'ratchet under threshold warns'
Assert-Eq $r.Hard.Count 0 'none of these is hard'

Write-Host "== procedure length"
$body = (1..16 | ForEach-Object { "krok $_" }) -join "`n"
$p = Write-Fx 'postup.md' ("# P`n`n## Jen pro tento projekt`n`n### Když stavíš`n`n**Build**`n$body`n")
$r = Test-UmsPlaybookShape $p
Assert-True (Has $r.Hard '[tvar] postup má') 'procedure over 16 lines is hard'

Remove-Item -Recurse -Force $tmp
Complete-Tests
```

- [ ] **Step 2: Spusť test a ověř, že padá**

Run: `pwsh -NoProfile -File ums/.claude/skills/shared/tests/playbook-shape.tests.ps1`
Expected: selže na dot-source, nenulový exit.

- [ ] **Step 3: Implementuj kontrolu**

`ums/.claude/skills/shared/scripts/Test-UmsPlaybookShape.ps1`:

```powershell
#Requires -Version 7
# Dot-source this file, then call Test-UmsPlaybookShape -Playbook <path>.
# Checks shape, thresholds and ratchet (contract/playbook-contract.md, "Budget, threshold and ratchet").
# Findings are Czech; only three classes are hard, and only for the new shape.
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'Read-UmsPlaybook.ps1')

$script:UmsPlaybookLimits = @{ File = 600; Chain = 900; Section = 40; RuleLines = 4; RuleWidth = 80; PostupLines = 16 }

function Get-UmsSentenceCount([string] $Text) {
    $t = $Text -replace '\b(např|tj|tzn|resp|apod|atd|č|str|viz|mj|popř)\.', '$1'
    ([regex]::Matches($t, '[.!?](?=\s|$)')).Count
}

function Test-UmsPlaybookShape([string] $Playbook) {
    $pb = Read-UmsPlaybook $Playbook
    $L = $script:UmsPlaybookLimits
    $hard = [Collections.Generic.List[string]]::new()
    $warn = [Collections.Generic.List[string]]::new()
    $over = $pb.LineCount -gt $L.File

    if ($pb.Shape -eq 'legacy') {
        $warn.Add('[legacy] soubor je ve starém tvaru (bez částí „Pro celý podstrom" / „Jen pro tento projekt") — převede ho kolo 1 konsolidace')
        if ($over) { $warn.Add("[práh-soubor] $($pb.LineCount) řádků > $($L.File)") }
        return [pscustomobject]@{ Playbook = $Playbook; Shape = $pb.Shape; Lines = $pb.LineCount; Hard = $hard.ToArray(); Warn = $warn.ToArray() }
    }

    foreach ($it in $pb.Items) {
        $at = "(řádek $($it.StartLine))"
        if ($it.Kind -eq 'prose') { $hard.Add("[tvar] text mimo položku $at"); continue }
        if (-not $it.Part) { $hard.Add("[tvar] položka mimo část: $($it.Title) $at") }
        if (-not $it.Section) { $hard.Add("[tvar] položka mimo sekci: $($it.Title) $at") }
        if ($it.Kind -eq 'pravidlo') {
            if ($it.LineCount -gt $L.RuleLines) { $hard.Add("[tvar] pravidlo má $($it.LineCount) řádků > $($L.RuleLines) $at") }
            for ($i = $it.StartLine; $i -le $it.EndLine; $i++) {
                if ($pb.Lines[$i - 1].Length -gt $L.RuleWidth) { $hard.Add("[tvar] řádek delší než $($L.RuleWidth) znaků (řádek $i)") }
            }
            if (-not $it.Proc) { $hard.Add("[tvar] chybí Proč: $($it.Title) $at") }
            elseif ((Get-UmsSentenceCount $it.Proc) -gt 1) { $warn.Add("[proč] Proč: má víc než jednu větu $at") }
            if (-not $it.Dukaz) { $hard.Add("[tvar] chybí Důkaz: $($it.Title) $at") }
        }
        if ($it.Kind -eq 'postup' -and $it.LineCount -gt $L.PostupLines) { $hard.Add("[tvar] postup má $($it.LineCount) řádků > $($L.PostupLines) $at") }
    }
    foreach ($s in $pb.Sections) {
        if ($s.Title -notmatch '^Když ') { $hard.Add("[tvar] sekce není ve tvaru „Když …“: $($s.Title) (řádek $($s.Line))") }
    }
    $groups = $pb.Items | Where-Object { $_.Section } | Group-Object { "$($_.Part)|$($_.Section)" }
    foreach ($g in $groups) {
        if ($g.Count -gt $L.Section) { $warn.Add("[práh-sekce] sekce „$(($g.Name -split '\|', 2)[1])“ má $($g.Count) položek > $($L.Section)") }
    }
    if ($over) {
        $warn.Add("[práh-soubor] $($pb.LineCount) řádků > $($L.File) — kandidát na eskalační report")
        if ($null -eq $pb.Ratchet) { $hard.Add('[ráčna-chybí] soubor nad prahem nemá ráčnový komentář na druhém řádku') }
        elseif ($pb.LineCount -gt $pb.Ratchet.Baseline) { $hard.Add("[ráčna-růst] $($pb.LineCount) řádků > baseline $($pb.Ratchet.Baseline) bez zaznamenaného rozhodnutí") }
    } elseif ($null -ne $pb.Ratchet) {
        $warn.Add('[ráčna-zbytečná] soubor je pod prahem — ráčnový komentář lze odstranit')
    }
    [pscustomobject]@{ Playbook = $Playbook; Shape = $pb.Shape; Lines = $pb.LineCount; Hard = $hard.ToArray(); Warn = $warn.ToArray() }
}
```

- [ ] **Step 4: Spusť test, ověř zelenou a negativitu**

Run: `pwsh -NoProfile -File ums/.claude/skills/shared/tests/playbook-shape.tests.ps1`
Expected: `<N> passed`, exit 0.
Negativita: dočasně smaž větev `elseif ($pb.LineCount -gt $pb.Ratchet.Baseline)`; aserce „growth over baseline is hard" musí zčervenat. Obnov a ověř prázdný `git diff`.

- [ ] **Step 5: Commit a push**

```bash
git add ums/.claude/skills/shared/scripts/Test-UmsPlaybookShape.ps1 ums/.claude/skills/shared/tests/playbook-shape.tests.ps1
git commit -F .superpowers/commit-msg.txt
git push origin UMS-3552-playbook-jadro-a-doklad
```

Zpráva: `UMS-3552: kontrola tvaru playbooku, prahy a ráčna`.

---

### Task A3: Strom MB, řetězec, nejnižší společný předek a kontrola stromu

**Files:**
- Create: `ums/.claude/skills/shared/scripts/Get-UmsPlaybookChain.ps1`
- Modify: `ums/.claude/skills/shared/scripts/Test-UmsPlaybookShape.ps1` (přidat `Test-UmsPlaybookTree`)
- Create: `ums/.claude/skills/shared/tests/new-playbook-fixture.ps1`
- Create: `ums/.claude/skills/shared/tests/playbook-chain.tests.ps1`

**Interfaces:**
- Consumes: `Read-UmsPlaybook` (A1), `Test-UmsPlaybookShape`, `$script:UmsPlaybookLimits` (A2).
- Produces:
  - `Get-UmsMbTree([string] $RepoRoot)` → pole `[pscustomobject]@{ Dir ('memory-bank' | 'X/Y/memory-bank'); Owner ('' | 'X/Y'); Playbook (relativní cesta | $null) }` seřazené podle `Owner`.
  - `Get-UmsPlaybookChain([string] $RepoRoot, [string] $Mb, [switch] $Out)` → `[pscustomobject]@{ Mb; Segments; TotalLines; OutPath }`; segment = `[pscustomobject]@{ Mb; Playbook; Part ('podstrom' | 'celý soubor'); StartLine; EndLine; Lines }`. `$Mb` je `Dir` (lomítka i zpětná lomítka, s koncovým lomítkem i bez).
  - `Get-UmsMbLowestCommonAncestor([object[]] $Tree, [string[]] $Mbs)` → `Dir` nejbližší MB na úrovni nejnižšího společného adresářového předka nebo nad ním.
  - `Test-UmsPlaybookTree([string] $RepoRoot, [string] $Under = '')` → pole `[pscustomobject]@{ Mb; Playbook; Hard; Warn; ChainLines }` pro každou MB s playbookem pod `$Under` (Owner s prefixem); řetězec nad prahem je varování `[práh-řetězec]`, s doporučením konsolidace, když jsou všechny úseky v novém tvaru a v prahu.
  - `New-PlaybookFixtureRepo()` (v `new-playbook-fixture.ps1`) → cesta k dočasnému git repu; `New-PlaybookRules([int] $Count, [string] $Prefix)` → text pravidel ve validním tvaru (3 řádky na pravidlo).

- [ ] **Step 1: Napiš fixturní helper**

`ums/.claude/skills/shared/tests/new-playbook-fixture.ps1`:

```powershell
#Requires -Version 7
# Test helper: builds a throwaway git repo with a Memory Bank tree.
Set-StrictMode -Version Latest

function New-PlaybookRules([int] $Count, [string] $Prefix) {
    (1..$Count | ForEach-Object { "- **$Prefix pravidlo $_.**`n  Proč: důvod $Prefix $_.`n  Důkaz: abc$_." }) -join "`n"
}

function Write-PlaybookFixtureFile([string] $Root, [string] $Rel, [string] $Content) {
    $p = Join-Path $Root $Rel
    New-Item -ItemType Directory -Force (Split-Path $p) | Out-Null
    [IO.File]::WriteAllText($p, ($Content -replace "`r`n", "`n"), [Text.UTF8Encoding]::new($false))
}

function New-PlaybookFixtureRepo {
    $root = Join-Path ([IO.Path]::GetTempPath()) ("pbtree-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory $root | Out-Null
    git -C $root init -q -b main
    git -C $root config user.email t@example.invalid
    git -C $root config user.name test
    git -C $root config core.autocrlf false
    $sub = { param($title, $rules) "## Pro celý podstrom`n`n### Když $title`n`n$rules`n" }
    $own = { param($title, $rules) "## Jen pro tento projekt`n`n### Když $title`n`n$rules`n" }
    Write-PlaybookFixtureFile $root 'memory-bank/playbook.md' ("# Playbook — kořen`n`n" + (& $sub 'píšeš git' '- **ROOT-SUB pravidlo.** Proč: r. Důkaz: a1.'))
    Write-PlaybookFixtureFile $root 'memory-bank/brief.md' "# Brief`n"
    Write-PlaybookFixtureFile $root 'A/memory-bank/playbook.md' ("# Playbook — A`n`n" + (& $sub 'stavíš A' '- **A-SUB pravidlo.** Proč: a. Důkaz: a2.') + "`n" + (& $own 'ladíš A' '- **A-OWN pravidlo.** Proč: a. Důkaz: a3.'))
    Write-PlaybookFixtureFile $root 'A/B/memory-bank/playbook.md' ("# Playbook — B`n`n" + (& $own 'testuješ B' '- **B-OWN pravidlo.** Proč: b. Důkaz: a4.'))
    Write-PlaybookFixtureFile $root 'A/C/memory-bank/brief.md' "# Brief C`n"
    Write-PlaybookFixtureFile $root 'A/C/D/memory-bank/playbook.md' ("# Playbook — D`n`n" + (& $own 'testuješ D' '- **D-OWN pravidlo.** Proč: d. Důkaz: a5.'))
    Write-PlaybookFixtureFile $root 'L/memory-bank/playbook.md' "# Úkoly — L`n`n## Build`n`nL-LEGACY text.`n"
    Write-PlaybookFixtureFile $root 'L/M/memory-bank/playbook.md' ("# Playbook — M`n`n" + (& $own 'testuješ M' '- **M-OWN pravidlo.** Proč: m. Důkaz: a6.'))
    Write-PlaybookFixtureFile $root 'S1/memory-bank/playbook.md' ("# Playbook — S1`n`n" + (& $own 'píšeš SQL' '- **S1 pravidlo `sqlcmd`.** Proč: s. Důkaz: a7.'))
    Write-PlaybookFixtureFile $root 'S2/memory-bank/playbook.md' ("# Playbook — S2`n`n" + (& $own 'píšeš SQL' '- **S2 pravidlo `sqlcmd`.** Proč: s. Důkaz: a8.'))
    Write-PlaybookFixtureFile $root 'A/B/memory-bank/X/memory-bank/playbook.md' "# Vnořená`n"
    Write-PlaybookFixtureFile $root '.gitignore' "/DistOut/`n"
    Write-PlaybookFixtureFile $root 'DistOut/W/memory-bank/playbook.md' "# Kopie buildu`n"
    git -C $root add -A
    git -C $root commit -q -m fixture
    $root
}
```

- [ ] **Step 2: Napiš padající test**

`ums/.claude/skills/shared/tests/playbook-chain.tests.ps1`:

```powershell
#Requires -Version 7
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_assert.ps1')
. (Join-Path $PSScriptRoot 'new-playbook-fixture.ps1')
. (Join-Path $PSScriptRoot '..\scripts\Get-UmsPlaybookChain.ps1')
. (Join-Path $PSScriptRoot '..\scripts\Test-UmsPlaybookShape.ps1')

$repo = New-PlaybookFixtureRepo

Write-Host "== tree discovery"
$tree = Get-UmsMbTree $repo
$dirs = @($tree | ForEach-Object Dir)
foreach ($d in 'memory-bank', 'A/memory-bank', 'A/B/memory-bank', 'A/C/memory-bank', 'A/C/D/memory-bank', 'L/memory-bank', 'L/M/memory-bank', 'S1/memory-bank', 'S2/memory-bank') {
    Assert-True ($dirs -contains $d) "tree contains $d"
}
Assert-True (-not ($dirs -match 'DistOut')) 'git-ignored copy is not an MB'
Assert-True (-not ($dirs -match 'memory-bank/X/memory-bank')) 'nested memory-bank is ignored'
Assert-True ($null -eq ($tree | Where-Object Dir -eq 'A/C/memory-bank').Playbook) 'MB without playbook has null Playbook'

Write-Host "== chain of a leaf under an intermediate"
$c = Get-UmsPlaybookChain $repo 'A/B/memory-bank' -Out
Assert-Eq (@($c.Segments | ForEach-Object Mb) -join ',') 'memory-bank,A/memory-bank,A/B/memory-bank' 'root, A, B in order'
Assert-Eq $c.Segments[1].Part 'podstrom' 'ancestor gives its subtree part only'
Assert-Eq $c.Segments[2].Part 'celý soubor' 'target gives the whole file'
$outText = [IO.File]::ReadAllText($c.OutPath)
Assert-Match $outText 'A-SUB pravidlo' 'subtree rule of A is in the chain'
Assert-True (-not ($outText -match 'A-OWN pravidlo')) 'own-project rule of A is not in the chain'
Assert-Match $outText '<!-- úsek: A/memory-bank/playbook.md \(podstrom' 'segment header names its source'
Assert-Match $c.OutPath '[\\/]\.superpowers[\\/]playbook-chain[\\/]A_B\.md$' 'chain file path'

Write-Host "== playbook-less ancestor is skipped"
$c = Get-UmsPlaybookChain $repo 'A/C/D/memory-bank'
Assert-Eq (@($c.Segments | ForEach-Object Mb) -join ',') 'memory-bank,A/memory-bank,A/C/D/memory-bank' 'A/C skipped'

Write-Host "== legacy non-root ancestor gives nothing"
$c = Get-UmsPlaybookChain $repo 'L/M/memory-bank'
Assert-Eq (@($c.Segments | ForEach-Object Mb) -join ',') 'memory-bank,L/M/memory-bank' 'legacy L skipped'

Write-Host "== root chain"
$c = Get-UmsPlaybookChain $repo 'memory-bank/'
Assert-Eq $c.Segments.Count 1 'root chain is the root file'
Assert-Eq $c.Segments[0].Part 'celý soubor' 'root as target gives whole file'

Write-Host "== lowest common ancestor"
Assert-Eq (Get-UmsMbLowestCommonAncestor $tree @('A/B/memory-bank', 'A/C/D/memory-bank')) 'A/memory-bank' 'LCA of B and D is A'
Assert-Eq (Get-UmsMbLowestCommonAncestor $tree @('S1/memory-bank', 'S2/memory-bank')) 'memory-bank' 'LCA of siblings is root'
Assert-Eq (Get-UmsMbLowestCommonAncestor $tree @('A/C/D/memory-bank')) 'A/C/D/memory-bank' 'LCA of one MB is itself'
Assert-Eq (Get-UmsMbLowestCommonAncestor $tree @('A/C/D/memory-bank', 'A/C/memory-bank')) 'A/C/memory-bank' 'LCA may be an MB without playbook'

Write-Host "== tree check: chain over threshold"
$big = New-PlaybookFixtureRepo
Write-PlaybookFixtureFile $big 'memory-bank/playbook.md' ("# P`n`n## Pro celý podstrom`n`n" + ((1..5 | ForEach-Object { "### Když krok $_`n`n" + (New-PlaybookRules 37 "R$_") + "`n" }) -join "`n"))
Write-PlaybookFixtureFile $big 'A/memory-bank/playbook.md' ("# P`n`n## Pro celý podstrom`n`n" + ((1..3 | ForEach-Object { "### Když krok $_`n`n" + (New-PlaybookRules 38 "A$_") + "`n" }) -join "`n"))
git -C $big add -A; git -C $big commit -q -m big
$res = Test-UmsPlaybookTree $big
$b = $res | Where-Object Mb -eq 'A/B/memory-bank'
Assert-True ((Read-UmsPlaybook (Join-Path $big 'memory-bank/playbook.md')).LineCount -le 600) 'root file itself is within threshold'
Assert-True ($b.ChainLines -gt 900) 'chain of B is over 900'
$cw = @($b.Warn | Where-Object { $_.StartsWith('[práh-řetězec]') })
Assert-True ([bool]$cw.Count) 'chain over threshold warns'
Assert-Match ($cw -join ' ') 'konsoliduj' 'conforming chain gets the consolidation hint'
Assert-Eq $b.Hard.Count 0 'chain over threshold is never hard'
Write-PlaybookFixtureFile $big 'A/memory-bank/playbook.md' ("# P`n`n## Testy`n`n" + (New-PlaybookRules 200 'LEG') + "`n")
git -C $big add -A; git -C $big commit -q -m legacy
$res = Test-UmsPlaybookTree $big
$b = $res | Where-Object Mb -eq 'A/B/memory-bank'
Assert-True ($b.ChainLines -le 900) 'legacy non-root ancestor contributes nothing to the chain'
$a = $res | Where-Object Mb -eq 'A/memory-bank'
Assert-True ([bool](@($a.Warn | Where-Object { $_.StartsWith('[legacy]') }).Count)) 'legacy file warns'
Assert-Eq $a.Hard.Count 0 'legacy file is never hard'
$sub = Test-UmsPlaybookTree $big 'A'
Assert-True (-not (@($sub | ForEach-Object Mb) -contains 'S1/memory-bank')) 'Under limits the scope'

Remove-Item -Recurse -Force $repo, $big
Complete-Tests
```

- [ ] **Step 3: Spusť test a ověř, že padá**

Run: `pwsh -NoProfile -File ums/.claude/skills/shared/tests/playbook-chain.tests.ps1`
Expected: selže na dot-source `Get-UmsPlaybookChain.ps1`, nenulový exit.

- [ ] **Step 4: Implementuj strom a řetězec**

`ums/.claude/skills/shared/scripts/Get-UmsPlaybookChain.ps1`:

```powershell
#Requires -Version 7
# Dot-source this file. Memory Bank tree, playbook chain and lowest common ancestor
# (contract/playbook-contract.md, "Playbook chain"). Read-only except the -Out scratch file.
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'Read-UmsPlaybook.ps1')

function ConvertTo-UmsMbDir([string] $Mb) {
    $d = ($Mb -replace '\\', '/').TrimEnd('/')
    if ($d -notmatch '(^|/)memory-bank$') { throw "Not a memory-bank directory: $Mb" }
    $d
}

function Get-UmsMbTree([string] $RepoRoot) {
    $files = @(git -C $RepoRoot ls-files)
    if ($LASTEXITCODE -ne 0) { throw "git ls-files failed in $RepoRoot" }
    $byDir = @{}
    foreach ($f in $files) {
        $m = [regex]::Match($f, '^(?:(.+)/)?memory-bank/([^/]+\.md)$')
        if (-not $m.Success) { continue }
        if (([regex]::Matches($f, '(^|/)memory-bank/')).Count -ne 1) { continue }
        $owner = $m.Groups[1].Value
        $dir = if ($owner) { "$owner/memory-bank" } else { 'memory-bank' }
        if (-not $byDir.ContainsKey($dir)) { $byDir[$dir] = [pscustomobject]@{ Dir = $dir; Owner = $owner; Playbook = $null; Tasks = $null } }
        if ($m.Groups[2].Value -eq 'playbook.md') { $byDir[$dir].Playbook = $f }
        if ($m.Groups[2].Value -eq 'tasks.md') { $byDir[$dir].Tasks = $f }
    }
    @($byDir.Values | ForEach-Object {
        [pscustomobject]@{ Dir = $_.Dir; Owner = $_.Owner; Playbook = $(if ($_.Playbook) { $_.Playbook } else { $_.Tasks }) }
    } | Sort-Object Owner)
}

function Test-UmsOwnerIsAncestor([string] $Ancestor, [string] $Owner) {
    if ($Ancestor -eq $Owner) { return $false }
    ($Ancestor -eq '') -or $Owner.StartsWith("$Ancestor/")
}

function Get-UmsPlaybookChain([string] $RepoRoot, [string] $Mb, [switch] $Out) {
    $dir = ConvertTo-UmsMbDir $Mb
    $tree = Get-UmsMbTree $RepoRoot
    $target = $tree | Where-Object Dir -eq $dir
    $owner = if ($dir -eq 'memory-bank') { '' } else { $dir -replace '/memory-bank$', '' }
    $segments = [Collections.Generic.List[object]]::new()
    $ancestors = @($tree | Where-Object { $_.Playbook -and (Test-UmsOwnerIsAncestor $_.Owner $owner) } | Sort-Object { ($_.Owner -split '/').Count * [int]($_.Owner -ne '') })
    foreach ($a in $ancestors) {
        $pb = Read-UmsPlaybook (Join-Path $RepoRoot $a.Playbook)
        if ($pb.Shape -eq 'new') {
            if ($pb.Parts.ContainsKey('podstrom')) {
                $p = $pb.Parts['podstrom']
                $segments.Add([pscustomobject]@{ Mb = $a.Dir; Playbook = $a.Playbook; Part = 'podstrom'; StartLine = $p.Start; EndLine = $p.End; Lines = $p.End - $p.Start + 1 })
            }
        } elseif ($a.Owner -eq '') {
            $segments.Add([pscustomobject]@{ Mb = $a.Dir; Playbook = $a.Playbook; Part = 'celý soubor'; StartLine = 1; EndLine = $pb.LineCount; Lines = $pb.LineCount })
        }
    }
    if ($target -and $target.Playbook) {
        $pb = Read-UmsPlaybook (Join-Path $RepoRoot $target.Playbook)
        $segments.Add([pscustomobject]@{ Mb = $target.Dir; Playbook = $target.Playbook; Part = 'celý soubor'; StartLine = 1; EndLine = $pb.LineCount; Lines = $pb.LineCount })
    }
    $total = [int](($segments | Measure-Object Lines -Sum).Sum)
    $outPath = $null
    if ($Out) {
        $slug = if ($owner) { $owner -replace '/', '_' } else { 'root' }
        $outDir = Join-Path $RepoRoot '.superpowers/playbook-chain'
        New-Item -ItemType Directory -Force $outDir | Out-Null
        $outPath = Join-Path $outDir "$slug.md"
        $sb = [Text.StringBuilder]::new()
        foreach ($s in $segments) {
            $pb = Read-UmsPlaybook (Join-Path $RepoRoot $s.Playbook)
            [void]$sb.Append("<!-- úsek: $($s.Playbook) ($($s.Part), řádky $($s.StartLine)–$($s.EndLine)) -->`n")
            [void]$sb.Append((@($pb.Lines[($s.StartLine - 1)..($s.EndLine - 1)]) -join "`n")).Append("`n`n")
        }
        [IO.File]::WriteAllText($outPath, $sb.ToString(), [Text.UTF8Encoding]::new($false))
    }
    [pscustomobject]@{ Mb = $dir; Segments = $segments.ToArray(); TotalLines = $total; OutPath = $outPath }
}

function Get-UmsMbLowestCommonAncestor([object[]] $Tree, [string[]] $Mbs) {
    $owners = @($Mbs | ForEach-Object { $d = ConvertTo-UmsMbDir $_; if ($d -eq 'memory-bank') { '' } else { $d -replace '/memory-bank$', '' } })
    $common = @($owners[0] -split '/' | Where-Object { $_ })
    if ($owners.Count -gt 1) {
        foreach ($o in $owners[1..($owners.Count - 1)]) {
            $segs = @($o -split '/' | Where-Object { $_ })
            $k = 0
            while ($k -lt $common.Count -and $k -lt $segs.Count -and $common[$k] -eq $segs[$k]) { $k++ }
            $common = if ($k) { @($common[0..($k - 1)]) } else { @() }
        }
    }
    for ($len = $common.Count; $len -ge 0; $len--) {
        $o = if ($len) { ($common[0..($len - 1)]) -join '/' } else { '' }
        $hit = $Tree | Where-Object Owner -eq $o
        if ($hit) { return $hit.Dir }
    }
    'memory-bank'
}
```

Do `Test-UmsPlaybookShape.ps1` přidej na konec (a dot-source `Get-UmsPlaybookChain.ps1` pod řádek s dot-source parseru):

```powershell
function Test-UmsPlaybookTree([string] $RepoRoot, [string] $Under = '') {
    $L = $script:UmsPlaybookLimits
    $tree = Get-UmsMbTree $RepoRoot
    $scope = @($tree | Where-Object { $_.Playbook -and (($Under -eq '') -or ($_.Owner -eq $Under) -or $_.Owner.StartsWith("$Under/")) })
    foreach ($mb in $scope) {
        $file = Test-UmsPlaybookShape (Join-Path $RepoRoot $mb.Playbook)
        $hard = [Collections.Generic.List[string]]::new(); foreach ($h in $file.Hard) { $hard.Add($h) }
        $warn = [Collections.Generic.List[string]]::new(); foreach ($w in $file.Warn) { $warn.Add($w) }
        $chain = Get-UmsPlaybookChain $RepoRoot $mb.Dir
        if ($chain.TotalLines -gt $L.Chain) {
            $conforming = $true
            foreach ($s in $chain.Segments) {
                $pb = Read-UmsPlaybook (Join-Path $RepoRoot $s.Playbook)
                if ($pb.Shape -ne 'new' -or $pb.Ratchet -or $pb.LineCount -gt $L.File) { $conforming = $false }
            }
            $hint = if ($conforming) { ' — úseky jsou v novém tvaru a v prahu: konsoliduj (přesun k potomkovi, přeřazení do projektu, sloučení), jinak eskalační report' } else { '' }
            $warn.Add("[práh-řetězec] řetězec $($mb.Dir) má $($chain.TotalLines) řádků > $($L.Chain)$hint")
        }
        [pscustomobject]@{ Mb = $mb.Dir; Playbook = $mb.Playbook; Hard = $hard.ToArray(); Warn = $warn.ToArray(); ChainLines = $chain.TotalLines }
    }
}
```

Řetězec nad prahem je vždy jen varování (návrh, bod 3, „Rozpočet je eskalační práh"); tvrdé nálezy stromu jsou jen tvrdé nálezy jeho souborů.

- [ ] **Step 5: Spusť testy (nová sada i A1, A2) a ověř negativitu**

Run: `pwsh -NoProfile -File ums/.claude/skills/shared/tests/playbook-chain.tests.ps1` a obě dřívější sady.
Expected: všechny `<N> passed`.
Negativita: dočasně smaž podmínku počtu výskytů `memory-bank/` v `Get-UmsMbTree`; aserce „nested memory-bank is ignored" musí zčervenat. Obnov a ověř prázdný `git diff`.

- [ ] **Step 6: Commit a push**

```bash
git add ums/.claude/skills/shared/scripts/Get-UmsPlaybookChain.ps1 ums/.claude/skills/shared/scripts/Test-UmsPlaybookShape.ps1 ums/.claude/skills/shared/tests/new-playbook-fixture.ps1 ums/.claude/skills/shared/tests/playbook-chain.tests.ps1
git commit -F .superpowers/commit-msg.txt
git push origin UMS-3552-playbook-jadro-a-doklad
```

Zpráva: `UMS-3552: strom MB, řetězec playbooků a nejnižší společný předek`.

---

### Task A4: Shoda identifikátorů

**Files:**
- Create: `ums/.claude/skills/shared/scripts/Find-UmsPlaybookMatch.ps1`
- Create: `ums/.claude/skills/shared/tests/playbook-match.tests.ps1`

**Interfaces:**
- Consumes: `Get-UmsPlaybookChain`, `Read-UmsPlaybook`, `New-PlaybookFixtureRepo`, `Write-PlaybookFixtureFile`.
- Produces: `Find-UmsPlaybookMatch([string] $Text, [string] $RepoRoot, [string] $Mb, [int] $Top = 3)` → pole `[pscustomobject]@{ Mb; Playbook; ItemId; Title; Score; Shared (string[]) }` seřazené podle `Score` sestupně, jen `Score -gt 0`. Token = obsah párových backticks, oříznutý, malými písmeny.

- [ ] **Step 1: Napiš padající test**

```powershell
#Requires -Version 7
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_assert.ps1')
. (Join-Path $PSScriptRoot 'new-playbook-fixture.ps1')
. (Join-Path $PSScriptRoot '..\scripts\Find-UmsPlaybookMatch.ps1')

$repo = New-PlaybookFixtureRepo
Write-PlaybookFixtureFile $repo 'A/memory-bank/playbook.md' @'
# Playbook — A

## Pro celý podstrom

### Když obnovuješ soubor

- **Po obnově ověř `git ls-files` dřív než `git diff`.** Proč: x. Důkaz: a.
- **Pro `git diff` použij `--find-renames`.** Proč: y. Důkaz: b.

## Jen pro tento projekt

### Když ladíš A

- **Tohle potomci nevidí `git diff`.** Proč: z. Důkaz: c.
'@
git -C $repo add -A; git -C $repo commit -q -m match

Write-Host "== best match first"
$r = @(Find-UmsPlaybookMatch 'Before trusting an empty `git diff`, check `git ls-files`.' $repo 'A/B/memory-bank')
Assert-Eq $r[0].Title 'Po obnově ověř `git ls-files` dřív než `git diff`.' 'two shared tokens rank first'
Assert-Eq $r[0].Score 2 'score counts shared tokens'
Assert-Eq $r[0].Mb 'A/memory-bank' 'match reports its MB'
Assert-True (-not (@($r | ForEach-Object Title) -match 'potomci nevidí')) 'own-project part of an ancestor is not searched'

Write-Host "== case and whitespace"
$r = @(Find-UmsPlaybookMatch 'use ` GIT DIFF ` here' $repo 'A/B/memory-bank')
Assert-True ($r.Count -ge 1) 'tokens are normalized'

Write-Host "== no tokens, top limit"
Assert-Eq @(Find-UmsPlaybookMatch 'no identifiers at all' $repo 'A/B/memory-bank').Count 0 'no tokens, no matches'
Assert-Eq @(Find-UmsPlaybookMatch '`git diff`' $repo 'A/B/memory-bank' -Top 1).Count 1 'Top limits results'

Remove-Item -Recurse -Force $repo
Complete-Tests
```

Ulož jako `ums/.claude/skills/shared/tests/playbook-match.tests.ps1`.

- [ ] **Step 2: Spusť a ověř, že padá**

Run: `pwsh -NoProfile -File ums/.claude/skills/shared/tests/playbook-match.tests.ps1`
Expected: selže na dot-source.

- [ ] **Step 3: Implementuj**

`ums/.claude/skills/shared/scripts/Find-UmsPlaybookMatch.ps1`:

```powershell
#Requires -Version 7
# Dot-source this file. Language-neutral match of a candidate against the playbook chain:
# only identifiers in backticks are compared (contract/playbook-contract.md, "Harvest gate").
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'Get-UmsPlaybookChain.ps1')

function Get-UmsBacktickTokens([string] $Text) {
    @([regex]::Matches($Text, '`([^`]+)`') | ForEach-Object { ($_.Groups[1].Value.Trim() -replace '\s+', ' ').ToLowerInvariant() } | Where-Object { $_ } | Sort-Object -Unique)
}

function Find-UmsPlaybookMatch([string] $Text, [string] $RepoRoot, [string] $Mb, [int] $Top = 3) {
    $want = Get-UmsBacktickTokens $Text
    if (-not $want.Count) { return @() }
    $chain = Get-UmsPlaybookChain $RepoRoot $Mb
    $hits = [Collections.Generic.List[object]]::new()
    foreach ($s in $chain.Segments) {
        $pb = Read-UmsPlaybook (Join-Path $RepoRoot $s.Playbook)
        foreach ($it in $pb.Items) {
            if ($it.StartLine -lt $s.StartLine -or $it.EndLine -gt $s.EndLine) { continue }
            $itemText = (@($pb.Lines[($it.StartLine - 1)..($it.EndLine - 1)]) -join ' ')
            $shared = @(Get-UmsBacktickTokens $itemText | Where-Object { $want -contains $_ })
            if ($shared.Count) {
                $hits.Add([pscustomobject]@{ Mb = $s.Mb; Playbook = $s.Playbook; ItemId = $it.Id; Title = $it.Title; Score = $shared.Count; Shared = $shared })
            }
        }
    }
    @($hits | Sort-Object -Property @{ Expression = 'Score'; Descending = $true }, @{ Expression = 'ItemId'; Descending = $false } | Select-Object -First $Top)
}
```

- [ ] **Step 4: Spusť, ověř zelenou a negativitu**

Run: sada A4. Expected: `<N> passed`.
Negativita: dočasně vynech podmínku `if ($it.StartLine -lt $s.StartLine ...)`; aserce „own-project part of an ancestor is not searched" musí zčervenat. Obnov a ověř `git diff`.

- [ ] **Step 5: Commit a push**

```bash
git add ums/.claude/skills/shared/scripts/Find-UmsPlaybookMatch.ps1 ums/.claude/skills/shared/tests/playbook-match.tests.ps1
git commit -F .superpowers/commit-msg.txt
git push origin UMS-3552-playbook-jadro-a-doklad
```

Zpráva: `UMS-3552: shoda identifikátorů kandidáta proti řetězci playbooků`.

---

### Task A5: Skript konsolidace `consolidate-playbook.ps1`

**Files:**
- Create: `ums/.claude/skills/mb-playbook-consolidate/scripts/consolidate-playbook.ps1`
- Create: `ums/.claude/skills/mb-playbook-consolidate/tests/consolidate.tests.ps1`
- Create: `ums/.claude/skills/mb-playbook-consolidate/tests/_assert.ps1` (kopie `ums/.claude/skills/shared/tests/_assert.ps1`)

**Interfaces:**
- Consumes: `Read-UmsPlaybook`, `Get-UmsMbTree`, `Get-UmsPlaybookChain`, `Test-UmsPlaybookShape`, `$script:UmsPlaybookLimits`, `$script:UmsPlaybookPartTitles`; fixturní helper `..\..\shared\tests\new-playbook-fixture.ps1`.
- Produces (CLI, výstup JSON na stdout, chyby `throw` s českou zprávou a exit 1):
  - `-Parse (-Path <playbook> | -Tree <owner nebo '.'>) [-RepoRoot]` → `{ "files": [ { "playbook", "mb", "shape", "lines", "ratchet", "items": [ { "id": "<playbook>#<n>", "kind", "part", "section", "title", "startLine", "endLine", "lineCount", "proc", "dukaz" } ] } ] }`.
  - `-Apply <decisions.json> [-RepoRoot] [-Today]` → `{ "written": [cesty], "retired": <n> }`. Rozhodnutí: `{ "run", "batch", "decisions": [ ... ] }`, verdikty (ASCII klíče): `ponechat`, `prepsat {text}`, `presunout {target, part, section, text?}`, `sloucit {into, text}`, `vyradit {reason}`, `prevest-na-test {test}`, `do-tech {target, text?}`, `novy {target, part, section, text}` (bez `id`, pro harvest).
  - `-Baseline -Path <playbook> [-Reason <text>] [-Today]` → zapíše ráčnu `baseline = počet řádků včetně komentáře`; pod prahem komentář odstraní.
  - `-Resume <run> [-RepoRoot]` → `{ "run", "done": ["01", ...] }` z trailerů `Playbook-Consolidation: <run>/<batch>`.
  - `-Stats (-Path | -Tree) [-RepoRoot]` → `{ "mbs": [ { "mb", "playbook", "lines", "overThreshold", "chainLines", "sections": [ { "part", "section", "items", "lines" } ] } ] }`.

- [ ] **Step 1: Zkopíruj `_assert.ps1` a napiš padající test**

`ums/.claude/skills/mb-playbook-consolidate/tests/consolidate.tests.ps1`:

```powershell
#Requires -Version 7
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_assert.ps1')
. (Join-Path $PSScriptRoot '..\..\shared\tests\new-playbook-fixture.ps1')
. (Join-Path $PSScriptRoot '..\..\shared\scripts\Test-UmsPlaybookShape.ps1')
$script = Join-Path $PSScriptRoot '..\scripts\consolidate-playbook.ps1'
function Invoke-Cons([string[]] $ArgList) {
    $out = & pwsh -NoProfile -File $script @ArgList 2>&1
    [pscustomobject]@{ Exit = $LASTEXITCODE; Text = ($out -join "`n") }
}
function Write-Decisions([string] $repo, [object] $obj) {
    $p = Join-Path $repo '.superpowers/decisions.json'
    New-Item -ItemType Directory -Force (Split-Path $p) | Out-Null
    [IO.File]::WriteAllText($p, ($obj | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))
    $p
}

$repo = New-PlaybookFixtureRepo
Write-PlaybookFixtureFile $repo 'A/memory-bank/playbook.md' @'
# Playbook — A

Úvod A.

## Pro celý podstrom

### Když stavíš A

- **A1 pravidlo.** Proč: a. Důkaz: x1.
- **A2 pravidlo.** Proč: a. Důkaz: x2.
- **A3 pravidlo.** Proč: a. Důkaz: x3.

## Jen pro tento projekt

### Když ladíš A

- **A4 pravidlo.** Proč: a. Důkaz: x4.
- **A5 BpmnData pravidlo.** Proč: a. Důkaz: x5.
'@
git -C $repo add -A; git -C $repo commit -q -m cons

Write-Host "== parse"
$r = Invoke-Cons @('-Parse', '-Path', 'A/memory-bank/playbook.md', '-RepoRoot', $repo)
Assert-Eq $r.Exit 0 'parse exits 0'
$j = $r.Text | ConvertFrom-Json
Assert-Eq $j.files[0].items.Count 5 'five items parsed'
Assert-Eq $j.files[0].items[0].id 'A/memory-bank/playbook.md#1' 'global item id'

Write-Host "== apply on new shape"
$d = Write-Decisions $repo @{ run = 'r1'; batch = '01'; decisions = @(
    @{ id = 'A/memory-bank/playbook.md#2'; verdict = 'sloucit'; into = 'A/memory-bank/playbook.md#1'; text = '- **A1+A2 sloučené.** Proč: a. Důkaz: x1.' }
    @{ id = 'A/memory-bank/playbook.md#4'; verdict = 'vyradit'; reason = 'neplatí od abc1234' }
    @{ id = 'A/memory-bank/playbook.md#1'; verdict = 'ponechat' }
    @{ id = 'A/memory-bank/playbook.md#3'; verdict = 'presunout'; target = 'memory-bank/playbook.md'; part = 'podstrom'; section = 'Když píšeš git' }
    @{ id = 'A/memory-bank/playbook.md#5'; verdict = 'presunout'; target = 'A/C/D/memory-bank/playbook.md'; part = 'projekt'; section = 'Když upravuješ BPMN' }
    @{ verdict = 'novy'; target = 'A/memory-bank/playbook.md'; part = 'projekt'; section = 'Když ladíš A'; text = '- **A6 nové.** Proč: a. Důkaz: návrh ums_1_x.' }
) }
$r = Invoke-Cons @('-Apply', $d, '-RepoRoot', $repo, '-Today', '2026-09-23')
Assert-Eq $r.Exit 0 'apply exits 0'
$a = [IO.File]::ReadAllText((Join-Path $repo 'A/memory-bank/playbook.md'))
Assert-Match $a 'A1\+A2 sloučené' 'merged text replaces into-item'
Assert-True (-not ($a -match 'A2 pravidlo')) 'merged source removed'
Assert-True (-not ($a -match 'A4 pravidlo')) 'retired item removed'
Assert-True (-not ($a -match 'A3 pravidlo')) 'moved-up item removed from source'
Assert-True (-not ($a -match 'A5 BpmnData')) 'moved-down item removed from source'
Assert-Match $a 'A6 nové' 'new item inserted'
Assert-Match $a 'Úvod A\.' 'preamble preserved'
$root = [IO.File]::ReadAllText((Join-Path $repo 'memory-bank/playbook.md'))
Assert-Match $root '(?s)## Pro celý podstrom.*### Když píšeš git.*A3 pravidlo' 'moved-up item in ancestor subtree section'
$dpb = [IO.File]::ReadAllText((Join-Path $repo 'A/C/D/memory-bank/playbook.md'))
Assert-Match $dpb '(?s)## Jen pro tento projekt.*### Když upravuješ BPMN.*A5 BpmnData' 'moved-down item in descendant'
$ret = [IO.File]::ReadAllText((Join-Path $repo 'A/memory-bank/playbook-retired.md'))
Assert-Match $ret '(?m)^- A4 pravidlo\. — neplatí od abc1234 \(2026-09-23\)$' 'retired line format'
Assert-Eq (Test-UmsPlaybookShape (Join-Path $repo 'A/memory-bank/playbook.md')).Hard.Count 0 'result passes shape'
$s1 = [IO.File]::ReadAllText((Join-Path $repo 'S1/memory-bank/playbook.md'))
Assert-Match $s1 'S1 pravidlo' 'untouched file untouched'

Write-Host "== legacy conversion must cover every item"
$d = Write-Decisions $repo @{ run = 'r1'; batch = '02'; decisions = @(
    @{ id = 'L/memory-bank/playbook.md#1'; verdict = 'ponechat' }
) }
$before = [IO.File]::ReadAllText((Join-Path $repo 'L/memory-bank/playbook.md'))
$r = Invoke-Cons @('-Apply', $d, '-RepoRoot', $repo)
Assert-True ($r.Exit -ne 0) 'ponechat on a legacy item is refused'
Assert-Eq ([IO.File]::ReadAllText((Join-Path $repo 'L/memory-bank/playbook.md'))) $before 'refused apply leaves file unchanged'
Write-PlaybookFixtureFile $repo 'L/memory-bank/playbook.md' "# Úkoly — L`n`n## Build`n`nL-LEGACY text.`n`n## Deploy`n`nDeploy text.`n"
git -C $repo add -A; git -C $repo commit -q -m legacy2
$d = Write-Decisions $repo @{ run = 'r1'; batch = '03'; decisions = @(
    @{ id = 'L/memory-bank/playbook.md#1'; verdict = 'presunout'; target = 'L/memory-bank/playbook.md'; part = 'projekt'; section = 'Když stavíš L'; text = "**Build L**`nL-LEGACY text." }
) }
$r = Invoke-Cons @('-Apply', $d, '-RepoRoot', $repo)
Assert-True ($r.Exit -ne 0) 'incomplete legacy conversion is refused'
Assert-Match $r.Text 'L/memory-bank/playbook.md#2' 'refusal names the undecided item'
$d = Write-Decisions $repo @{ run = 'r1'; batch = '03'; decisions = @(
    @{ id = 'L/memory-bank/playbook.md#1'; verdict = 'presunout'; target = 'L/memory-bank/playbook.md'; part = 'projekt'; section = 'Když stavíš L'; text = "**Build L**`nL-LEGACY text." }
    @{ id = 'L/memory-bank/playbook.md#2'; verdict = 'vyradit'; reason = 'nahrazeno «Build L»' }
) }
$r = Invoke-Cons @('-Apply', $d, '-RepoRoot', $repo)
Assert-Eq $r.Exit 0 'complete legacy conversion applies'
Assert-Eq (Test-UmsPlaybookShape (Join-Path $repo 'L/memory-bank/playbook.md')).Shape 'new' 'converted file is new shape'

Write-Host "== ratchet after apply and -Baseline"
$bigRules = (1..4 | ForEach-Object { "### Když krok $_`n`n" + (New-PlaybookRules 50 "B$_") + "`n" }) -join "`n"
Write-PlaybookFixtureFile $repo 'S2/memory-bank/playbook.md' ("# P`n`n## Jen pro tento projekt`n`n" + $bigRules)
git -C $repo add -A; git -C $repo commit -q -m big
$d = Write-Decisions $repo @{ run = 'r1'; batch = '04'; decisions = @(
    @{ id = 'S2/memory-bank/playbook.md#1'; verdict = 'vyradit'; reason = 'duplicita' }
) }
$r = Invoke-Cons @('-Apply', $d, '-RepoRoot', $repo, '-Today', '2026-09-23')
$s2 = Join-Path $repo 'S2/memory-bank/playbook.md'
$pb = Read-UmsPlaybook $s2
Assert-True ($null -ne $pb.Ratchet) 'over-threshold result gets a ratchet'
Assert-Eq $pb.Ratchet.Baseline $pb.LineCount 'baseline equals achieved size'
Assert-Eq (Test-UmsPlaybookShape $s2).Hard.Count 0 'ratcheted file has no hard finding'
Add-Content -NoNewline $s2 "`n- **Navíc.** Proč: a. Důkaz: b.`n"
Assert-True ([bool](@((Test-UmsPlaybookShape $s2).Hard | Where-Object { $_.StartsWith('[ráčna-růst]') }).Count)) 'growth is hard'
$r = Invoke-Cons @('-Baseline', '-Path', 'S2/memory-bank/playbook.md', '-Reason', 'nové pravidlo', '-RepoRoot', $repo, '-Today', '2026-09-24')
Assert-Eq $r.Exit 0 'baseline exits 0'
Assert-Eq (Read-UmsPlaybook $s2).Ratchet.Reason 'nové pravidlo' 'reason recorded'
Assert-Eq (Test-UmsPlaybookShape $s2).Hard.Count 0 'recorded raise passes'

Write-Host "== resume from trailers"
git -C $repo add -A
git -C $repo commit -q -m "UMS-1: dávka 01" -m "Playbook-Consolidation: r9/01"
git -C $repo commit -q --allow-empty -m "UMS-1: dávka 02" -m "Playbook-Consolidation: r9/02"
$r = Invoke-Cons @('-Resume', 'r9', '-RepoRoot', $repo)
Assert-Eq (($r.Text | ConvertFrom-Json).done -join ',') '01,02' 'done batches from trailers'

Write-Host "== stats"
$r = Invoke-Cons @('-Stats', '-Tree', '.', '-RepoRoot', $repo)
$st = ($r.Text | ConvertFrom-Json).mbs | Where-Object mb -eq 'S2/memory-bank'
Assert-True $st.overThreshold 'stats flags over-threshold MB'
Assert-True ($st.sections.Count -ge 4) 'stats lists sections'

Remove-Item -Recurse -Force $repo
Complete-Tests
```

- [ ] **Step 2: Spusť a ověř, že padá**

Run: `pwsh -NoProfile -File ums/.claude/skills/mb-playbook-consolidate/tests/consolidate.tests.ps1`
Expected: selže (skript neexistuje), nenulový exit.

- [ ] **Step 3: Implementuj skript**

`ums/.claude/skills/mb-playbook-consolidate/scripts/consolidate-playbook.ps1`:

```powershell
#Requires -Version 7
<#
Mechanical half of playbook consolidation and of the harvest gate
(contract/playbook-contract.md, "Consolidation"). Judgement is the analyst's,
approval is the human's; this script only executes approved decisions.
Output: JSON on stdout. Errors: Czech message, exit 1.
#>
[CmdletBinding(DefaultParameterSetName = 'Parse')]
param(
    [Parameter(ParameterSetName = 'Parse', Mandatory)] [switch] $Parse,
    [Parameter(ParameterSetName = 'Apply', Mandatory)] [string] $Apply,
    [Parameter(ParameterSetName = 'Baseline', Mandatory)] [switch] $Baseline,
    [Parameter(ParameterSetName = 'Resume', Mandatory)] [string] $Resume,
    [Parameter(ParameterSetName = 'Stats', Mandatory)] [switch] $Stats,
    [string] $Path,
    [string] $Tree,
    [string] $Reason,
    [string] $RepoRoot,
    [string] $Today = (Get-Date -Format 'yyyy-MM-dd')
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$shared = Join-Path $PSScriptRoot '..\..\shared\scripts'
. (Join-Path $shared 'Test-UmsPlaybookShape.ps1')
if (-not $RepoRoot) { $RepoRoot = (git rev-parse --show-toplevel) }
$utf8 = [Text.UTF8Encoding]::new($false)

function Get-RelPlaybooks {
    if ($Path) { return @($Path -replace '\\', '/') }
    $under = if ($Tree -in @('', '.')) { '' } else { ($Tree -replace '\\', '/').TrimEnd('/') }
    @(Get-UmsMbTree $RepoRoot | Where-Object { $_.Playbook -and (($under -eq '') -or $_.Owner -eq $under -or $_.Owner.StartsWith("$under/")) } | ForEach-Object Playbook)
}
function Get-MbOf([string] $rel) { ($rel -replace '/[^/]+$', '') }
function Write-Lf([string] $rel, [string[]] $lines) {
    $p = Join-Path $RepoRoot $rel
    New-Item -ItemType Directory -Force (Split-Path $p) | Out-Null
    [IO.File]::WriteAllText($p, (($lines -join "`n") + "`n"), $utf8)
}
function Get-ItemLines($pb, $it) { @($pb.Lines[($it.StartLine - 1)..($it.EndLine - 1)]) }
function Split-Text([string] $t) { @(($t -replace "`r`n", "`n").TrimEnd("`n") -split "`n") }
function Get-RatchetLine([int] $n, [string] $reason) {
    $r = if ($reason) { ", $reason" } else { '' }
    "<!-- playbook-budget: $($script:UmsPlaybookLimits.File); baseline: $n ($Today$r) -->"
}
function Set-Ratchet([string[]] $lines, [string] $reason) {
    $body = [Collections.Generic.List[string]]::new()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($i -eq 1 -and (Get-UmsPlaybookRatchet $lines)) { continue }
        $body.Add($lines[$i])
    }
    if ($body.Count -le $script:UmsPlaybookLimits.File) { return $body.ToArray() }
    $withComment = $body.Count + 1
    @($body[0], (Get-RatchetLine $withComment $reason)) + @($body.GetRange(1, $body.Count - 1))
}

switch ($PSCmdlet.ParameterSetName) {
    'Parse' {
        $files = foreach ($rel in Get-RelPlaybooks) {
            $pb = Read-UmsPlaybook (Join-Path $RepoRoot $rel)
            [ordered]@{
                playbook = $rel; mb = (Get-MbOf $rel); shape = $pb.Shape; lines = $pb.LineCount; ratchet = $pb.Ratchet
                items = @($pb.Items | ForEach-Object { [ordered]@{ id = "$rel#$($_.Id)"; kind = $_.Kind; part = $_.Part; section = $_.Section; title = $_.Title; startLine = $_.StartLine; endLine = $_.EndLine; lineCount = $_.LineCount; proc = $_.Proc; dukaz = $_.Dukaz } })
            }
        }
        @{ files = @($files) } | ConvertTo-Json -Depth 6
    }
    'Baseline' {
        $rel = $Path -replace '\\', '/'
        $pb = Read-UmsPlaybook (Join-Path $RepoRoot $rel)
        $lines = @($pb.Lines)
        $out = Set-Ratchet $lines $Reason
        Write-Lf $rel $out
        @{ written = @($rel) } | ConvertTo-Json
    }
    'Resume' {
        $vals = @(git -C $RepoRoot log --format='%(trailers:key=Playbook-Consolidation,valueonly)')
        $done = @($vals | Where-Object { $_ -like "$Resume/*" } | ForEach-Object { ($_ -split '/', 2)[1].Trim() } | Sort-Object -Unique)
        @{ run = $Resume; done = $done } | ConvertTo-Json
    }
    'Stats' {
        $mbs = foreach ($rel in Get-RelPlaybooks) {
            $pb = Read-UmsPlaybook (Join-Path $RepoRoot $rel)
            $chain = Get-UmsPlaybookChain $RepoRoot (Get-MbOf $rel)
            $secs = @($pb.Items | Group-Object { "$($_.Part)|$($_.Section)" } | ForEach-Object {
                $parts = $_.Name -split '\|', 2
                [ordered]@{ part = $parts[0]; section = $parts[1]; items = $_.Count; lines = [int](($_.Group | Measure-Object LineCount -Sum).Sum) }
            })
            [ordered]@{ mb = (Get-MbOf $rel); playbook = $rel; lines = $pb.LineCount; overThreshold = ($pb.LineCount -gt $script:UmsPlaybookLimits.File); chainLines = $chain.TotalLines; sections = $secs }
        }
        @{ mbs = @($mbs) } | ConvertTo-Json -Depth 6
    }
    'Apply' {
        $doc = Get-Content -Raw $Apply | ConvertFrom-Json
        $decisions = @($doc.decisions)
        # Load every involved file once.
        $model = @{}   # rel -> @{ Pb; Preamble; Parts = ordered part -> ordered section -> List[string[]] ; Legacy }
        $load = {
            param([string] $rel)
            if ($model.ContainsKey($rel)) { return }
            $full = Join-Path $RepoRoot $rel
            $parts = [ordered]@{ podstrom = [ordered]@{}; projekt = [ordered]@{} }
            if (-not (Test-Path $full)) {
                $owner = (Get-MbOf $rel) -replace '/?memory-bank$', ''
                $name = if ($owner) { $owner } else { 'kořen' }
                $model[$rel] = @{ Pb = $null; Preamble = @("# Playbook — $name"); Parts = $parts; Legacy = $false; ItemRef = @{} }
                return
            }
            $pb = Read-UmsPlaybook $full
            $pre = @($pb.Lines[0..([Math]::Max(0, $pb.PreambleEnd - 1))] | Select-Object -First ([Math]::Max(1, $pb.PreambleEnd)))
            $pre = @($pre | Where-Object { -not ($_ -match '^<!-- playbook-budget:') })
            $ref = @{}
            if ($pb.Shape -eq 'new') {
                foreach ($it in $pb.Items) {
                    if (-not $parts[$it.Part].Contains($it.Section)) { $parts[$it.Part][$it.Section] = [Collections.Generic.List[object]]::new() }
                    $entry = [pscustomobject]@{ Id = $it.Id; Lines = (Get-ItemLines $pb $it) }
                    $parts[$it.Part][$it.Section].Add($entry)
                    $ref[$it.Id] = $entry
                }
            }
            $model[$rel] = @{ Pb = $pb; Preamble = $pre; Parts = $parts; Legacy = ($pb.Shape -eq 'legacy'); ItemRef = $ref }
        }
        $parseId = { param([string] $id) $k = $id.LastIndexOf('#'); @($id.Substring(0, $k), [int]$id.Substring($k + 1)) }
        foreach ($d in $decisions) {
            if ($d.PSObject.Properties['id']) { & $load (& $parseId $d.id)[0] }
            if ($d.PSObject.Properties['target'] -and $d.verdict -ne 'do-tech') { & $load $d.target }
            if ($d.PSObject.Properties['into']) { & $load (& $parseId $d.into)[0] }
        }
        # Legacy completeness.
        foreach ($rel in @($model.Keys)) {
            $m = $model[$rel]
            if (-not $m.Legacy) { continue }
            $decided = @($decisions | Where-Object { $_.PSObject.Properties['id'] -and ((& $parseId $_.id)[0] -eq $rel) })
            if (@($decided | Where-Object verdict -eq 'ponechat').Count) { throw "Legacy soubor $rel: verdikt ponechat nelze použít, položka potřebuje část a sekci (presunout)." }
            $ids = @($decided | ForEach-Object { (& $parseId $_.id)[1] })
            $missing = @($m.Pb.Items | Where-Object { $ids -notcontains $_.Id } | ForEach-Object { "$rel#$($_.Id)" })
            if ($missing.Count) { throw "Legacy soubor $rel se převádí celý; položky bez rozhodnutí: $($missing -join ', ')" }
        }
        $retired = @{}
        $addRetired = { param([string] $rel, [string] $title, [string] $why)
            $r = (Get-MbOf $rel) + '/playbook-retired.md'
            if (-not $retired.ContainsKey($r)) { $retired[$r] = [Collections.Generic.List[string]]::new() }
            $words = (@($title -split '\s+') | Select-Object -First 8) -join ' '
            $retired[$r].Add("- $words — $why ($Today)")
        }
        $insert = { param([string] $rel, [string] $part, [string] $section, [string[]] $lines)
            $p = $model[$rel].Parts[$part]
            if (-not $p.Contains($section)) { $p[$section] = [Collections.Generic.List[object]]::new() }
            $p[$section].Add([pscustomobject]@{ Id = -1; Lines = $lines })
        }
        $remove = [Collections.Generic.List[object]]::new()
        $techAppend = @{}
        foreach ($d in $decisions) {
            $src = $null; $it = $null; $srcLines = $null
            if ($d.PSObject.Properties['id']) {
                $pair = & $parseId $d.id
                $src = $pair[0]
                $it = $model[$src].Pb.Items | Where-Object Id -eq $pair[1]
                if (-not $it) { throw "Neznámá položka $($d.id)" }
                $srcLines = Get-ItemLines $model[$src].Pb $it
            }
            $text = if ($d.PSObject.Properties['text']) { Split-Text $d.text } else { $srcLines }
            switch ($d.verdict) {
                'ponechat' { }
                'prepsat' { $model[$src].ItemRef[$it.Id].Lines = $text }
                'presunout' { $remove.Add(@($src, $it.Id)); & $insert $d.target $d.part $d.section $text }
                'novy' { & $insert $d.target $d.part $d.section $text }
                'sloucit' { $ip = & $parseId $d.into; $model[$ip[0]].ItemRef[$ip[1]].Lines = $text; $remove.Add(@($src, $it.Id)) }
                'vyradit' { $remove.Add(@($src, $it.Id)); & $addRetired $src $it.Title $d.reason }
                'prevest-na-test' { $remove.Add(@($src, $it.Id)); & $addRetired $src $it.Title "hlídá test $($d.test)" }
                'do-tech' { $remove.Add(@($src, $it.Id)); if (-not $techAppend.ContainsKey($d.target)) { $techAppend[$d.target] = [Collections.Generic.List[string]]::new() }; foreach ($l in $text) { $techAppend[$d.target].Add($l) } }
                default { throw "Neznámý verdikt $($d.verdict)" }
            }
        }
        foreach ($r in $remove) {
            $m = $model[$r[0]]
            if ($m.Legacy) { continue }
            foreach ($part in $m.Parts.Values) { foreach ($sec in $part.Values) { $x = @($sec | Where-Object Id -eq $r[1]); foreach ($e in $x) { [void]$sec.Remove($e) } } }
        }
        $written = [Collections.Generic.List[string]]::new()
        foreach ($rel in $model.Keys) {
            $m = $model[$rel]
            $out = [Collections.Generic.List[string]]::new()
            foreach ($l in $m.Preamble) { $out.Add($l) }
            while ($out.Count -and $out[$out.Count - 1] -eq '') { $out.RemoveAt($out.Count - 1) }
            foreach ($key in $script:UmsPlaybookPartTitles.Keys) {
                $secs = @($m.Parts[$key].Keys | Where-Object { $m.Parts[$key][$_].Count })
                if (-not $secs.Count) { continue }
                $out.Add(''); $out.Add("## $($script:UmsPlaybookPartTitles[$key])")
                foreach ($s in $secs) {
                    $out.Add(''); $out.Add("### $s"); $out.Add('')
                    $first = $true
                    foreach ($e in $m.Parts[$key][$s]) {
                        if (-not $first -and ($e.Lines[0] -match '^\*\*')) { $out.Add('') }
                        foreach ($l in $e.Lines) { $out.Add($l) }
                        if ($e.Lines[0] -match '^\*\*') { $out.Add('') }
                        $first = $false
                    }
                }
            }
            while ($out.Count -and $out[$out.Count - 1] -eq '') { $out.RemoveAt($out.Count - 1) }
            Write-Lf $rel (Set-Ratchet $out.ToArray() $null)
            $written.Add($rel)
        }
        foreach ($r in $retired.Keys) {
            $full = Join-Path $RepoRoot $r
            $existing = if (Test-Path $full) { @((Get-Content -Raw $full).TrimEnd("`n") -split "`n") } else { @('# Vyřazená pravidla', '') }
            Write-Lf $r (@($existing) + @($retired[$r]))
            $written.Add($r)
        }
        foreach ($t in $techAppend.Keys) {
            $full = Join-Path $RepoRoot $t
            $lines = if (Test-Path $full) { @((Get-Content -Raw $full).TrimEnd("`n") -split "`n") } else { @('# Tech') }
            $idx = [Array]::IndexOf($lines, '## Pasti prostředí')
            if ($idx -lt 0) { $lines = @($lines) + @('', '## Pasti prostředí', '') + @($techAppend[$t]) }
            else {
                $end = $idx + 1
                while ($end -lt $lines.Count -and $lines[$end] -notmatch '^## ') { $end++ }
                $lines = @($lines[0..($end - 1)]) + @($techAppend[$t]) + $(if ($end -lt $lines.Count) { @('') + @($lines[$end..($lines.Count - 1)]) } else { @() })
            }
            Write-Lf $t $lines
            $written.Add($t)
        }
        @{ written = $written.ToArray(); retired = [int](($retired.Values | ForEach-Object Count | Measure-Object -Sum).Sum) } | ConvertTo-Json
    }
}
```

Poznámky pro implementátora:
- Serializace vkládá mezi pravidla bez prázdných řádků a kolem postupů prázdný řádek; pokud to rozbije parser (pravidlo po postupu), uprav serializaci tak, aby každá položka byla oddělena prázdným řádkem — parser prázdné řádky toleruje. Testy jsou měřítkem.
- Rozhodnutí se aplikují nad původním parsem (ID z `-Parse`); pořadí verdiktů v souboru nesmí ovlivnit výsledek, kromě pořadí vkládání do sekce.
- Preambule legacy souboru = řádky před prvním `##`; u převáděného legacy souboru se staré nadpisy nepřenášejí, obsah nesou jen rozhodnutí.

- [ ] **Step 4: Spusť sadu, ověř zelenou a negativitu**

Run: `pwsh -NoProfile -File ums/.claude/skills/mb-playbook-consolidate/tests/consolidate.tests.ps1`
Expected: `<N> passed`.
Negativita: dočasně vynech kontrolu `$missing` v legacy completeness; aserce „incomplete legacy conversion is refused" musí zčervenat. Obnov a ověř `git diff`.

- [ ] **Step 5: Commit a push**

```bash
git add ums/.claude/skills/mb-playbook-consolidate/scripts/consolidate-playbook.ps1 ums/.claude/skills/mb-playbook-consolidate/tests/
git commit -F .superpowers/commit-msg.txt
git push origin UMS-3552-playbook-jadro-a-doklad
```

Zpráva: `UMS-3552: skript konsolidace playbooku (parse, apply, baseline, resume, stats)`.

---

### Task A6: Sada hygieny a oprava stávajících sad

**Files:**
- Create: `ums/.claude/skills/shared/tests/tests-hygiene.tests.ps1`
- Modify (přidat `$ErrorActionPreference = 'Stop'` pod `Set-StrictMode`): `ums/.claude/hooks/tests/guard-git-push.tests.ps1`, `ums/.claude/skills/mb-doc-index/tests/enumeration.tests.ps1`, `findings.tests.ps1`, `output-target.tests.ps1`, `targeted-scan.tests.ps1`, `ums/.claude/skills/mb-epic-elaboration/tests/ledger-status.tests.ps1`, `ums/.claude/skills/mb-epic-graph/tests/e2e.tests.ps1`, `graph-generation.tests.ps1`, `oracle-prose.tests.ps1`, `oracle-structural.tests.ps1`, `status-glyph.tests.ps1`

**Interfaces:**
- Consumes: nic
- Produces: sada `tests-hygiene.tests.ps1` (pravidla (a) a (b) z návrhu, bod 6).

- [ ] **Step 1: Napiš sadu**

```powershell
#Requires -Version 7
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_assert.ps1')
# Hygiene of every test suite of the layer (contract/playbook-contract.md, "Retired rules and conversion to code").
$layer = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path   # ums/.claude
$suites = @(Get-ChildItem -Recurse -File -Path $layer -Filter '*.tests.ps1')
Assert-True ($suites.Count -ge 30) "found $($suites.Count) suites"
foreach ($s in $suites) {
    $text = [IO.File]::ReadAllText($s.FullName)
    $rel = $s.FullName.Substring($layer.Length + 1)
    # (a) every Assert-* called is defined in the suite or in a .ps1 of its directory
    $defs = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($f in @($s) + @(Get-ChildItem -File -Path $s.DirectoryName -Filter '*.ps1')) {
        foreach ($m in [regex]::Matches([IO.File]::ReadAllText($f.FullName), '(?m)^\s*function\s+(Assert-\w+)')) { [void]$defs.Add($m.Groups[1].Value) }
    }
    $called = @([regex]::Matches($text, '(?<![\w-])(Assert-\w+)') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
    $undef = @($called | Where-Object { -not $defs.Contains($_) })
    Assert-True ($undef.Count -eq 0) "$rel calls only defined asserts $(if ($undef.Count) { '(missing: ' + ($undef -join ', ') + ')' })"
    # (b) a suite that dot-sources its subject sets ErrorActionPreference Stop
    $dotSources = @([regex]::Matches($text, '(?m)^\s*\.\s+(.+)$') | ForEach-Object { $_.Groups[1].Value } | Where-Object { $_ -notmatch "_assert\.ps1" })
    if ($dotSources.Count) {
        Assert-Match $text "(?m)^\s*\`$ErrorActionPreference\s*=\s*'Stop'" "$rel dot-sources its subject and sets ErrorActionPreference Stop"
    }
}
Complete-Tests
```

- [ ] **Step 2: Spusť a ověř, že padá na (b)**

Run: `pwsh -NoProfile -File ums/.claude/skills/shared/tests/tests-hygiene.tests.ps1`
Expected: FAIL u 11 sad vyjmenovaných v Files (zkontroluj, že seznam FAIL sedí; odchylku zapiš jako Ruling).

- [ ] **Step 3: Oprav sady**

Do každé z 11 sad přidej pod řádek `Set-StrictMode -Version Latest` řádek `$ErrorActionPreference = 'Stop'`. Pak každou sadu spusť samostatně. Sada, která s `Stop` zčervená, zčervenala proto, že nějaké volání dřív tiše selhávalo (non-terminating error): najdi ho a oprav příčinu (typicky chybějící `-ErrorAction SilentlyContinue` u očekávaně selhávajícího příkazu nebo `2>$null` u gitu, který má selhat). Nikdy neoprav tím, že `Stop` odebereš. Každou takovou opravu popiš v reportu.

- [ ] **Step 4: Spusť celou vrstvu**

Run: `for t in $(find ums -name "*.tests.ps1"); do echo "== $t"; pwsh -NoProfile -File "$t" || echo "FAILED: $t"; done`
Expected: žádný řádek `FAILED:`.

- [ ] **Step 5: Commit a push**

```bash
git add ums/.claude/skills/shared/tests/tests-hygiene.tests.ps1 ums/.claude/hooks/tests/guard-git-push.tests.ps1 ums/.claude/skills/mb-doc-index/tests ums/.claude/skills/mb-epic-elaboration/tests/ledger-status.tests.ps1 ums/.claude/skills/mb-epic-graph/tests
git commit -F .superpowers/commit-msg.txt
git push origin UMS-3552-playbook-jadro-a-doklad
```

Zpráva: `UMS-3552: sada hygieny testů a ErrorActionPreference Stop ve stávajících sadách`.

---

## Fáze B — Kontrakt a skilly

Před prvním taskem fáze B: sync báze na hranici fáze (fetch, merge `origin/ums-memory-bank`, porovnání průniku, push) — kontrakt, Base Sync & Drift Detection.

### Task B1: Kontrakt 3.1

**Files:**
- Modify: `ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md` (řádek 3 verze; Three-Tier `AFFECTED_MBS` ř. 31–33; Scope Lock ř. 96–101; MB Context Reading Rule ř. 403–415; Document Set ř. 64–66)
- Modify: `ums/.claude/skills/shared/contract/playbook-contract.md` (přepis)
- Modify: `ums/.claude/skills/shared/contract/harvest.md` (pravidlo 3 playbook gate, pravidlo 5)
- Modify: `ums/.claude/skills/shared/contract/architect-review.md:109`
- Modify: `ums/.claude/skills/shared/CHANGELOG.md`
- Test: `ums/.claude/skills/shared/tests/contract-shape.tests.ps1` (beze změny, musí zůstat zelená)

**Interfaces:**
- Consumes: jména skriptů a limity z fáze A.
- Produces: sekce reference citovatelné ve tvaru `(contract/playbook-contract.md, "<název>")` — přesné nadpisy: `Playbook Contract`, `Playbook shape`, `Playbook chain`, `Budget, threshold and ratchet`, `Legacy mode`, `Harvest gate`, `Analyst brief`, `Retired rules and conversion to code`, `Environment traps`, `Consolidation`, `Writes outside PLAN_MB`, `Escalation report`. Úlohy B2 a B3 je citují přesně takto.

- [ ] **Step 1: Ověř výchozí stav**

Run: `pwsh -NoProfile -File ums/.claude/skills/shared/tests/contract-shape.tests.ps1`
Expected: `<N> passed`. Zaznamenej počet řádků jádra (`(Get-Content ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md).Count`, dnes 799).

- [ ] **Step 2: Přepiš referenci `playbook-contract.md`**

Zachovej hlavičku (ř. 1–2) a sekci `### Playbook Contract` s režimem consult-before-write, výjimkou `mb-init`, dvěma konzultačními styly a sběrem kandidátů (ř. 4–91). V ní nahraď odstavec „**Entry format** is free (heading + steps)…" (ř. 30–32) větou: `**Entry format** is the item shape of "Playbook shape" below; a legacy file keeps its free format until consolidation converts it ("Legacy mode").` Do formátu kandidáta přidej řádek `- **Relates:** <MB>:<item> (extends | duplicates | replaces)   (when the candidate touches an item of the chain)` a pod blok větu `Corrects is the special case "replaces".`

Za sekci přidej tyto sekce (anglicky, normativně; obsah přesně podle návrhu, body 1–9):

```markdown
### Playbook shape

A playbook in the new shape has at most two parts, spelled exactly `## Pro celý podstrom` (read by every descendant Memory Bank) and `## Jen pro tento projekt` (read only by work pinned to this Memory Bank), and no other second-level heading. Anything else is the legacy shape ("Legacy mode"). Inside a part, sections are `### Když …` headings named for the moment the rule is needed, never for a topic; the base list of sections lives in this reference and a Memory Bank may add its own `Když …` section, which is then recorded here as an extension. The root playbook carries mainly the subtree part; it may carry the project part only for work pinned to the root Memory Bank itself (single-MB repositories). Two item kinds, both inside a section and both counted against the budget: a **rule** — one imperative bold line, then `Proč:` in one sentence and `Důkaz:` (harvest commit SHA, archived design, the test that guards it, or `návrh <slug>` for a new item), at most four lines of at most 80 characters; a **procedure** — a bold title on its own line and at most 15 lines of steps, a command block or a parameter table, with `Proč:`/`Důkaz:` when there is something to prove. Build and test commands are procedures in `Když stavíš nebo spouštíš testy`.

### Playbook chain

The Memory Bank tree is derived from tracked paths (`git ls-files`): Memory Bank A is an ancestor of B when the directory owning `A/memory-bank/` is an ancestor of the one owning `B/memory-bank/`; a `memory-bank/` nested inside another `memory-bank/` is ignored, and untracked or git-ignored copies do not exist for the tree. The chain of Memory Bank X is what a session working in X reads: from every ancestor that has a playbook, root first, only its `Pro celý podstrom` part (a legacy root counts whole, a legacy non-root ancestor contributes nothing); from X, the whole file. `shared/scripts/Get-UmsPlaybookChain.ps1` computes it; `-Out` writes the assembled chain to `.superpowers/playbook-chain/<mb>.md` (regenerated on every use) and a dispatch receives that path, never the inlined content.

### Budget, threshold and ratchet

Thresholds: 600 lines per file, 900 lines per chain, 40 items per section. Exceeding a threshold is a warning with the size, never a hard finding: it says the playbook probably carries content that belongs elsewhere ("Escalation report"). `shared/scripts/Test-UmsPlaybookShape.ps1` reports exactly three hard findings, all for a new-shape file: a shape violation, growth over the ratchet baseline, and a file over the threshold without its ratchet comment. The ratchet is the literal second line `<!-- playbook-budget: 600; baseline: <N> (<YYYY-MM-DD>[, <reason>]) -->`; the file may not outgrow the baseline unless a human, in the harvest gate, explicitly raises it with a reason, which is written into the comment. Consolidation lowers the baseline to the achieved size after every batch and removes the comment below the threshold.

### Legacy mode

A legacy-shape file gets warnings only — shape, size, thresholds — and never stops a harvest; the harvest gate announces loudly that a legacy file grows and by how much, and recommends consolidation. Strict rules apply from the moment round 1 of consolidation converts the file; if it is then over the threshold, round 1 writes its ratchet.

### Harvest gate

(obsah návrhu bod 5: tabulka dispozic, pět dispozic s cílem ve stromu, osm kritérií v pořadí, `M/Ú` jen pro shodu identifikátorů a kritérium 4, dopad u cíle v předkovi, zápis přes `consolidate-playbook.ps1 -Apply` s verdikty `novy`/`sloucit`/`prepsat`/`vyradit`/`prevest-na-test`, kontrola tvaru na konci kroku 3 před archivací a tvrdý nález jako neúspěšná aktualizace MB; růst nad ráčnu = vyrovnat, nebo lidsky zvednout baseline přes `-Baseline -Reason`)

### Analyst brief

(brief analytika pro bránu i konsolidaci: vstupy — kandidáti nebo `-Parse` JSON, sestavený řetězec, seznamy vyřazených řetězce, `-Stats`; výstup — tabulka ve tvaru z "Harvest gate" resp. "Consolidation"; pravidla — kritéria v pořadí, u každého řádku kritérium a M/Ú, nerozhodnutý řádek označit, nikdy nevymýšlet `Happened`; dispatch na nejlevnějším schopném tieru, model uveden explicitně)

### Retired rules and conversion to code

(návrh bod 6: `playbook-retired.md` vedle playbooku, řádkový tvar, čtení vyřazených z celého řetězce, převod strojově ověřitelného pravidla na test; sada `shared/tests/tests-hygiene.tests.ps1` jako první dva převody)

### Environment traps

(návrh bod 7)

### Consolidation

(návrh bod 8 a 9: skill `mb-playbook-consolidate`, tabulka návrhů, verdikty a kritéria, dvě kola, přepis citací sekcí a `mb-link-audit`, `-Tree` ve čtyřech krocích, výpočet LCA `Get-UmsMbLowestCommonAncestor`, dávky, trailer `Playbook-Consolidation: <run>/<batch>`, `-Resume` z trailerů, konec běhu `Test-UmsPlaybookTree`, nikdy push sdílené větve)

### Writes outside PLAN_MB

Two named exceptions to the Scope Lock, both limited to what a human approved in a table. The harvest gate: an approved disposition targeting an ancestor's playbook adds that ancestor to `AFFECTED_MBS` for `playbook.md` and `playbook-retired.md` only. Consolidation: it may write `playbook.md` and `playbook-retired.md` of every Memory Bank in the run's scope, `tech.md` only for rows with the verdict `do-tech`, and `proposals/next/` only for an approved escalation report. `mb-git-commit` stages exactly the files an approved batch names.

### Escalation report

(návrh bod 8, „Eskalační report": kdy vzniká, umístění `<MB>/proposals/next/design_<mb-slug>_playbook_eskalace.md`, obsah čtyř bodů, schválení, jeden report na podstrom v `-Tree`; report nic neřeší)
```

Odstavce v závorkách jsou zadání, ne text: napiš je jako normativní anglický text se stejnou hustotou jako první čtyři sekce, věcně přesně podle citovaného bodu návrhu, bez přidávání pravidel, která návrh nemá. Konflikt se znělem návrhu rozhoduje návrh (Ruling do ledgeru).

- [ ] **Step 3: Uprav jádro, řádkově neutrálně**

- ř. 3: `- **Contract-Version:** 3.1`.
- Three-Tier, `AFFECTED_MBS` (ř. 31–33): věta končí `… derived at harvest time from the branch diff (see Harvest Contract) plus ancestors an approved playbook disposition targets (contract/playbook-contract.md, "Writes outside PLAN_MB"), never hand-maintained in context.md.` — přeformuluj tak, aby odstavec zůstal na 3–4 řádcích.
- Scope Lock (ř. 98–101): za „…(see Superpowers Document Placement)." připoj `The playbook writes of harvest and consolidation are the named exceptions of (contract/playbook-contract.md, "Writes outside PLAN_MB").`
- Document Set (ř. 64–66): „`playbook.md` — prescriptive procedures (Document Ownership below; Playbook Contract in `contract/playbook-contract.md`)" nech, jen doplň `, read as a chain along the Memory Bank tree`.
- MB Context Reading Rule (ř. 405–411): `read <PLAN_MB>/brief.md, architecture.md, tech.md and playbook.md` → `read <PLAN_MB>/brief.md, architecture.md, tech.md and the playbook chain of PLAN_MB (contract/playbook-contract.md, "Playbook chain")`; `playbook.md is prescriptive — its procedures BIND` → `the playbook chain is prescriptive — its procedures BIND`.
- Když jádro přesáhne 800 řádků, zkrať formulace jen v právě editovaných odstavcích; jinde nic neměň.

- [ ] **Step 4: Uprav `harvest.md`, `architect-review.md`, `CHANGELOG.md`**

- `harvest.md`, pravidlo 3, část o playbook gate (ř. 19–57): nahraď popis brány odkazem `The playbook gate is (contract/playbook-contract.md, "Harvest gate"); its shape check runs at the end of this rule, before rule 4, and a hard finding counts as a failed Memory Bank update under rule 5.` Zachovej text o kandidátech, které tam dnes jsou, pokud ho reference neopakuje.
- `harvest.md`, pravidlo 5: připoj `A hard finding of the playbook shape check is such a failure.`
- `architect-review.md:109`: `` `tech.md`, `playbook.md` `` → `` `tech.md` and the playbook chain (contract/playbook-contract.md, "Playbook chain") ``.
- `CHANGELOG.md`: změň `- **Contract-Version:** 3.0` na `3.1` a nad položku 3.0 přidej `- 3.1 — strom playbooků a řetězec předků, tvar souboru a položky, eskalační práh s ráčnou, legacy režim, harvestová brána v2, konsolidace jedné MB i stromu, výjimky Scope Lock pro zápis playbooku (UMS-3552).` (Drž jazyk, kterým jsou psané dosavadní položky changelogu; je-li anglický, přelož.)

- [ ] **Step 5: Spusť kontraktové sady**

Run: `pwsh -NoProfile -File ums/.claude/skills/shared/tests/contract-shape.tests.ps1` a `pwsh -NoProfile -File ums/.claude/hooks/tests/contract-inject.tests.ps1`
Expected: obě `<N> passed` (jádro ≤ 800 řádků, citace existují, každá reference má konzumenta, payload se vejde).

- [ ] **Step 6: Commit a push**

```bash
git add ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md ums/.claude/skills/shared/contract/playbook-contract.md ums/.claude/skills/shared/contract/harvest.md ums/.claude/skills/shared/contract/architect-review.md ums/.claude/skills/shared/CHANGELOG.md
git commit -F .superpowers/commit-msg.txt
git push origin UMS-3552-playbook-jadro-a-doklad
```

Zpráva: `UMS-3552: kontrakt 3.1 — strom playbooků, tvar, práh a konsolidace`.

---

### Task B2: Harvestová brána, overlaye a ostatní čtenáři a zapisovatelé

**Files:**
- Modify: `ums/.claude/skills/mb-harvest/SKILL.md:129-174` (playbook gate) a krok 3/4 hranice
- Modify: `ums/.claude/skills/shared/overlays/subagent-driven-development.overlay.md:112-138`
- Modify: `ums/.claude/skills/shared/overlays/brainstorming.overlay.md:151-153`
- Modify: `ums/.claude/skills/mb-git-commit/SKILL.md:221-236`
- Modify: `ums/.claude/skills/mb-init/SKILL.md:164-167`
- Modify: `ums/.claude/skills/mb-sync/SKILL.md:202-210`
- Modify: `ums/.claude/skills/mb-architect-review/SKILL.md:~210, ~289`
- Modify: `ums/.claude/skills/mb-epic-elaboration/protocol.md:71`
- Modify: `ums/.claude/skills/mb-migrate-docs/SKILL.md:114-117`

**Interfaces:**
- Consumes: sekce reference z B1 (přesné názvy), skripty z A1–A5.
- Produces: skilly a overlaye, které čtou řetězec a zapisují přes `-Apply`.

- [ ] **Step 1: `mb-harvest` — brána v2**

Nahraď playbook gate (ř. 129–173) textem (anglicky), který říká:
1. Resolve the chain: `Get-UmsPlaybookChain <MB_ROOT> <PLAN_MB> -Out` and read the retired lists of every chain segment.
2. Dispatch the analyst (cheapest capable tier, model explicit) with the brief of (contract/playbook-contract.md, "Analyst brief"): candidates file, chain path, retired lists, `Find-UmsPlaybookMatch` output per candidate.
3. Present the disposition table (columns and five dispositions of "Harvest gate"); every row whose target is an ancestor lists the inheriting Memory Banks (count and list, from `Get-UmsMbTree`); the human approves the table and may override rows.
4. Translate the approved table into a decisions file (`novy`, `sloucit`, `prepsat`, `vyradit`, `prevest-na-test`) under `.superpowers/` and run `consolidate-playbook.ps1 -Apply <file>`; `do kódu` rows are implemented as a test or check, never as a playbook item.
5. Run `Test-UmsPlaybookShape` on every written file and `Test-UmsPlaybookTree <MB_ROOT>` for every Memory Bank whose chain includes a written file. Warnings are printed (legacy growth loudly, with the line delta). A hard finding: `[ráčna-růst]` → ask the human to balance (merge/replace/retire) or raise the baseline with `consolidate-playbook.ps1 -Baseline -Path <file> -Reason <text>`; any other hard finding → fix and rerun the gate. Until clean, do NOT proceed to step 4 (archive) or step 5 (IDLE reset) — this is the partial-failure rule of (contract/harvest.md, "Harvest Contract").
6. Delete the candidates file only after the approved entries are written (existing rule).

Zachovej stávající pravidla o `Corrects` (kandidát vedle položky, kterou opravuje; zmizelá položka → nový) — převeď je na řádky tabulky (`Corrects` = dispozice `nahrazuje`).

- [ ] **Step 2: Overlay SDD**

V ř. 112–119 nahraď resoluci jednoho souboru: controller spustí `Get-UmsPlaybookChain <MB_ROOT> <PLAN_MB> -Out`, k dispatchi přiloží vrácenou cestu (`.superpowers/playbook-chain/<mb>.md`), obsah nevkládá; build a test postupy pro baseline bere z řetězce (sekce `Když stavíš nebo spouštíš testy`). V ř. 120–138 přidej: před kopií kandidáta controller spustí `Find-UmsPlaybookMatch`, doplní `Relates:` a kandidáta duplikujícího jiného kandidáta nebo položku řetězce nezapíše (ohlásí v reportu). Neměň kotvy, asserty ani markery bloku (playbook, „Editaci, která mění jen TĚLO overlay fragmentu, ověřuj diffem"): ověř `git diff origin/ums-memory-bank..HEAD -- ums/.claude/skills/shared/overlays | grep -E "^[+-].*(ANCHOR|ASSERT|UMS-OVERLAY)"` prázdný.

- [ ] **Step 3: Overlay brainstorming**

ř. 151–153: `read <PLAN_MB>/brief.md, architecture.md, tech.md and playbook.md` → `… tech.md and the playbook chain of PLAN_MB (contract/playbook-contract.md, "Playbook chain")`; „`playbook.md` is prescriptive" → „the playbook chain is prescriptive". Stejná kontrola kotev jako ve Step 2.

- [ ] **Step 4: Ostatní skilly**

- `mb-git-commit` (ř. 221–236): přidej pravidlo „Playbook batch (harvest gate or consolidation): stage exactly the files listed in the `written` array of `consolidate-playbook.ps1 -Apply` output, plus the decisions' `do-tech` targets — nothing more, nothing less (contract/playbook-contract.md, "Writes outside PLAN_MB")."
- `mb-init` (ř. 164–167): playbook se zakládá v novém tvaru — `# Playbook — <name>`, `## Jen pro tento projekt` (u kořene repa s jedinou MB), `### Když stavíš nebo spouštíš testy`, detekované příkazy jako postupy (tučný název, blok příkazů). Uveď šablonu doslova v SKILL.md.
- `mb-sync` (ř. 202–210): návrh opravy playbooku jmenuje část a sekci; soubor ve starém tvaru nepřevádí (to je konsolidace).
- `mb-architect-review` (~210, ~289) a `mb-epic-elaboration/protocol.md:71`: `playbook.md` → „the playbook chain (contract/playbook-contract.md, "Playbook chain")".
- `mb-migrate-docs` (ř. 114–117): věta „The rename does not change the item shape; converting to the new shape is consolidation's job (contract/playbook-contract.md, "Consolidation")."

- [ ] **Step 5: Ověř**

Run: `pwsh -NoProfile -File ums/.claude/skills/shared/tests/contract-shape.tests.ps1` (nové citace musí existovat) a celou vrstvu smyčkou z Ověřovací sady.
Expected: bez `FAILED:`.

- [ ] **Step 6: Commit a push**

```bash
git add ums/.claude/skills/mb-harvest/SKILL.md ums/.claude/skills/shared/overlays/subagent-driven-development.overlay.md ums/.claude/skills/shared/overlays/brainstorming.overlay.md ums/.claude/skills/mb-git-commit/SKILL.md ums/.claude/skills/mb-init/SKILL.md ums/.claude/skills/mb-sync/SKILL.md ums/.claude/skills/mb-architect-review/SKILL.md ums/.claude/skills/mb-epic-elaboration/protocol.md ums/.claude/skills/mb-migrate-docs/SKILL.md
git commit -F .superpowers/commit-msg.txt
git push origin UMS-3552-playbook-jadro-a-doklad
```

Zpráva: `UMS-3552: harvestová brána v2, řetězec v overlayích a skillech`.

---

### Task B3: Skill `mb-playbook-consolidate`, manifest a nasazení

**Files:**
- Create: `ums/.claude/skills/mb-playbook-consolidate/SKILL.md`
- Modify: `ums/.claude/skills/shared/SKILLS_MANIFEST.md` (tabulka `## Aktivní mb-* skilly`)
- Nasazení (netrackované): `.claude/`, `.agents/skills/`

**Interfaces:**
- Consumes: `consolidate-playbook.ps1` (A5), `Test-UmsPlaybookTree`, `Get-UmsMbLowestCommonAncestor` (A3), reference (B1).
- Produces: skill vyvolatelný „konsoliduj playbook", „konsoliduj playbooky celého monorepa", `-Tree <cesta>`.

- [ ] **Step 1: Napiš SKILL.md**

Frontmatter:

```markdown
---
name: mb-playbook-consolidate
description: Use when a Memory Bank playbook needs consolidating — merging duplicates, retiring stale rules, converting the legacy shape, moving rules up or down the Memory Bank tree, or when the shape check reports a playbook over its threshold (konsolidace playbooku, playbook je moc velký, konsoliduj playbooky monorepa, přesun pravidel k předkovi).
---
```

Tělo (anglicky, reporty česky) s oddíly: `Contract` (odkaz na jádro a na `(contract/playbook-contract.md, "Consolidation")`); `Modes` (jedna MB: `-Path`; strom: `-Tree [<cesta>]`, výchozí `MB_ROOT`); `Single Memory Bank` (Parse → analyst → tabulka `| # | Položka | Návrh | Kritérium | Do | Pozn. |` → schválení → decisions → `-Apply` → shape → commit přes `mb-git-commit` s trailerem → push vlastní tiketové větve; kolo 1 a kolo 2; kolo 1 přepisuje citace sekcí nalezené grepem mimo playbook v téže dávce); `Tree` (čtyři kroky z návrhu bodu 9 s příkazy `-Stats -Tree`, `-Parse -Tree`, LCA přes `Get-UmsMbLowestCommonAncestor`, dávka na podstrom, pořadí kola 1 shora dolů); `Escalation report` (šablona předběžného návrhu v češtině se sekcemi `## Cíl`, `## Scope`, `## Technický návrh` — velikosti proti prahu z `-Stats`, shluky s velikostí, navržený domov a proč, odhad úspory — a umístění z reference); `Resume` (`-Resume <run>`); `End of run` (`Test-UmsPlaybookTree` bez tvrdého nálezu, `mb-link-audit` nad dotčenými MB); `Never` (nepushuje sdílenou větev, nepíše bez schválené tabulky, nemění MB mimo výjimku Scope Lock, nedělá nic automaticky).

- [ ] **Step 2: Manifest**

Do tabulky přidej řádek `| mb-playbook-consolidate | [mb-playbook-consolidate/SKILL.md](../mb-playbook-consolidate/SKILL.md) | Konsolidace playbooku jedné MB nebo celého stromu: slučování, vyřazování, převod tvaru, přesuny ve stromu, eskalační report. |`. Uprav počet aktivních skillů všude, kde ho manifest nebo `memory-bank/brief.md` uvádějí (grep `17 aktivních`, `17 live`); `brief.md` patří do MB tohoto repa, uprav ho jen tam, kde číslo uvádí.

- [ ] **Step 3: Nasazení v tomto repu**

Podle playbooku, sekce „Obnova nasazené kopie v tomto repu": zkopíruj `ums/.claude/skills/shared`, všechny `ums/.claude/skills/mb-*`, `ums/.claude/hooks`, `ums/.claude/scripts` do `.claude/` a `ums/.claude/skills/{shared,mb-*}` do `.agents/skills/`. Pak revendor s pinovaným tagem z `ums/.claude/skills/shared/VENDORED_FROM.md`: `pwsh -NoProfile -File .claude/scripts/revendor-superpowers.ps1 -Tag <pin>`; potom dorovnej čtyři vendorované skilly do `.agents/skills` kopií z `.claude/skills`. Ověř grepem (i `-i` a s ztišeným whitespace) frázi `Get-UmsPlaybookChain` v `.claude/skills/subagent-driven-development/SKILL.md` a `playbook chain` v `.claude/skills/brainstorming/SKILL.md`. Když revendor nejde spustit (klasifikátor, `tar`), neobcházej ho: ohlas nasazené vendorované skilly jako zastaralé a jmenuj příkaz pro uživatele.

- [ ] **Step 4: Ověř**

Run: celá vrstva smyčkou z Ověřovací sady; `pwsh -NoProfile -File .claude/skills/mb-playbook-consolidate/scripts/consolidate-playbook.ps1 -Stats -Path memory-bank/playbook.md` (nasazená kopie funguje).
Expected: bez `FAILED:`; JSON s `lines` = počet řádků playbooku.

- [ ] **Step 5: Commit a push**

```bash
git add ums/.claude/skills/mb-playbook-consolidate/SKILL.md ums/.claude/skills/shared/SKILLS_MANIFEST.md memory-bank/brief.md
git commit -F .superpowers/commit-msg.txt
git push origin UMS-3552-playbook-jadro-a-doklad
```

Zpráva: `UMS-3552: skill mb-playbook-consolidate a manifest`.

---

## Fáze C — Akceptace

Před prvním taskem fáze C: sync báze na hranici fáze. Tasky C1 a C2 vede **controller sám, ne implementátor**: zápis do `playbook.md` je lidské dno (kontrakt, Escalation & Autonomy) a každá tabulka čeká na schválení uživatelem. Čekání na schválení je pojmenované čekání na člověka, ne STOP.

### Task C1: Kolo 1 nad `memory-bank/playbook.md`

**Files:**
- Modify: `memory-bank/playbook.md`, `memory-bank/playbook-retired.md` (nový, jen pokud kolo 1 něco vyřadí)
- Modify (citace sekcí): `ums/.claude/hooks/contract-inject.ps1:~59`, `ums/.claude/hooks/tests/contract-inject.tests.ps1:~167`, `ums/.claude/skills/mb-state/SKILL.md:131,295`, `ums/.claude/skills/mb-epic-run/README.md:~147`, `memory-bank/architecture.md` (a cokoli dalšího, co grep najde)

**Interfaces:**
- Consumes: skill `mb-playbook-consolidate` (B3).

- [ ] **Step 1:** `consolidate-playbook.ps1 -Parse -Path memory-bank/playbook.md` a `-Stats`; ulož do `.superpowers/playbook-consolidation/c1/`.
- [ ] **Step 2:** Dispatch analytika (nejlevnější schopný tier, model explicitně) s briefem z reference: navrhni pro KAŽDOU položku `presunout` do téhož souboru s částí (`projekt` pro pravidla o artefaktech této vrstvy, `podstrom` jen pro to, co by platilo v každém repu s touto vrstvou — v repu s jedinou MB rozhoduje dosah, ne čtenář) a sekcí „Když …" (výchozí mapování z návrhu bod 1; přerostlé sekce rozděl), a přepsaný text ve tvaru pravidla nebo postupu (`Proč:` jedna věta, `Důkaz:` ze SHA harvestového commitu podle `git log -S "<první slova>" -- memory-bank/playbook.md`). Kolo 1 nic neslučuje ani nevyřazuje, kromě položek, které analytik označí jako přesné duplikáty (ty jen navrhne, rozhodne uživatel).
- [ ] **Step 3:** Předlož uživateli tabulku v dávkách po sekcích (česky, s počty řádků před a po). Čekej na schválení; přebití řádků zapracuj.
- [ ] **Step 4:** Zapiš decisions a spusť `-Apply`; pak `Test-UmsPlaybookShape -Playbook memory-bank/playbook.md` — tvrdé nálezy oprav úpravou decisions a novým `-Apply` (z čistého stavu `git checkout -- memory-bank/playbook.md`), ne ruční editací.
- [ ] **Step 5:** Grepem najdi citace starých názvů sekcí mimo playbook (`Testy vrstvy`, `PowerShell v této vrstvě`, `Git hooky`, `Upgrade upstreamu`, `CRLF u bezpříponových`, `Nasazení vrstvy`, `Instalace git hooků do klonu`, `Obnova nasazené kopie v tomto repu`, `Kontrakt a skilly`, `Psaní plánů, návrhů a commitů`) a přepiš je na nový název sekce nebo název postupu; `contract-inject.ps1` a jeho aserci změň společně. Spusť `contract-inject.tests.ps1` a celou vrstvu.
- [ ] **Step 6:** Commit (trailer `Playbook-Consolidation: c1/<dávka>` pro každou dávku, nebo jeden commit s trailerem `c1/01`, podle toho, jak uživatel schvaloval) a push. Zpráva: `UMS-3552: playbook v novém tvaru (konsolidace kolo 1)`.

### Task C2: Kolo 2, vyřazené, pasti a eskalace

**Files:**
- Modify: `memory-bank/playbook.md`, `memory-bank/playbook-retired.md`, `memory-bank/tech.md` (sekce „Pasti prostředí")
- Create (jen nad prahem): `memory-bank/proposals/next/design_ums_repo_playbook_eskalace.md`

- [ ] **Step 1:** Dispatch analytika s briefem kola 2 nad výsledkem C1: slučování shluků (Doklad návrhu: grep sweep 9, CRLF 4, „ověř v tomto běhu" 3, pořadí STOPů 4, páry „nahrazeno, ale ponecháno"), vyřazení jednorázových a překonaných, `prevest-na-test` pro dvě lekce pokryté `tests-hygiene.tests.ps1` (jmenuj sadu), `do-tech` a sloučení čtyř duplicit pastí tech.md × playbook (návrh bod 7).
- [ ] **Step 2:** Předlož tabulku po dávkách; čekej na schválení.
- [ ] **Step 3:** `-Apply`, shape check, commit s trailerem `c2/<dávka>`, push — po každé dávce.
- [ ] **Step 4:** Po poslední dávce `-Stats`. Je-li soubor pod 600 řádků: ráčna zmizela, konec. Jinak sepiš eskalační report podle šablony skillu (shluky zbylých položek s velikostí, navržený domov — skill, skript/test, referenční dokument, `tech.md` — a proč, odhad úspory), předlož ho ke schválení a commitni do `memory-bank/proposals/next/`.
- [ ] **Step 5:** Změř a zapiš do návrhu, sekce Doklad, řádek „Konsolidace tohoto repa": řádky před/po, položky před/po, vyřazené, převedené do kódu, přesunuté do `tech.md`, výsledek (pod prahem / ráčna + report). Commit a push. Zpráva: `UMS-3552: konsolidace playbooku kolo 2 a doklad`.

### Task C3: Monorepo nanečisto

**Files:**
- Modify: `memory-bank/proposals/active/design_ums_3552_playbook_jadro_a_doklad.md` (Doklad, nová podsekce „Monorepo nanečisto")

- [ ] **Step 1:** Zaznamenej `git -C d:/_datasys/ums status --porcelain` a `git -C d:/_datasys/ums rev-parse HEAD` (před).
- [ ] **Step 2:** `consolidate-playbook.ps1 -Stats -Tree . -RepoRoot d:/_datasys/ums` a `-Parse -Tree . -RepoRoot d:/_datasys/ums` do `.superpowers/playbook-consolidation/mono/` (v tomto repu, ne v monorepu). Ověř, že parser nespadl na žádném z 23 playbooků a že strom neobsahuje `DistOut` ani vnořenou MB v `PCInfo`.
- [ ] **Step 3:** `Test-UmsPlaybookTree d:/_datasys/ums` — zapiš počty varování podle kódu a potvrď nulu tvrdých nálezů (všechno je legacy).
- [ ] **Step 4:** Dispatch analytika (read-only, nejlevnější schopný tier) na kolo 2a nad `-Parse` JSON: shluky napříč MB (CRLF, CP1250/UTF-16, PowerShell, git, SQL, BpmnData v KicWorkflow); ke každému shluku spočítej LCA přes `Get-UmsMbLowestCommonAncestor` a navrhni verdikt. Nic nezapisuj.
- [ ] **Step 5:** Ověř „po" stav monorepa (status a HEAD beze změny). Do Doklad návrhu zapiš inventuru (MB, řádky, řetězce nad prahem) a tabulku přesunů (shluk, MB, LCA, verdikt, odhad řádků) a porovnání s analýzou 2026-09-23. Commit a push. Zpráva: `UMS-3552: doklad — běh -Tree nanečisto nad monorepem`.
