# Rozhodovací stavové ikony v grafu epiku — implementační plán

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Jira:** (žádný tiket)
**Návrh:** [design_epic_graph_test_jako_hotovo.md](design_epic_graph_test_jako_hotovo.md)
**Target MB:** — (fork superpowers nemá Memory Bank; dokumenty žijí v `ums/docs/`)

**Goal:** Stavová ikona v tabulce vln `mb-epic-graph` odpovídá rozhodovací matici z návrhu — tikety ve stavu `Test`/`Review`/`Documentation` neblokují následníky, `Design Review` má vlastní ikonu a dál blokuje, a běh bez `-ProposalPath` už netvrdí „návrh hotov".

**Architecture:** Veškerá logika je v jednom skriptu `epic-graph.ps1`. Hotovost pro plánování vyhodnocuje nová funkce `Test-DoneForPlanning` (její jediný konzument je `Test-Unblocked`), ikonu určuje kaskáda v `Get-StatusGlyph`. Match podle názvu stavu jde přes společný helper `Test-StatusNameIn`, který je aktivní pouze v režimu Jira — v režimu Proposals plní `Status` volnotextové hlavičkové pole `**Stav:**`. Testy jsou nový samostatný soubor s vlastními fixtures, existujících fixtures se nedotýkáme.

**Tech Stack:** PowerShell 7 (`pwsh`), `Set-StrictMode -Version Latest`, dependency-free test harness `tests/_assert.ps1` (funkce `Assert-Match`, `Assert-NotMatch`, `Assert-Eq`, `Invoke-Graph`, `Complete-Tests`).

## Global Constraints

- Pracuj na aktuální větvi `feature/epic-graph-test-jako-hotovo`. Git worktrees jsou v tomto repu zakázané (branch-in-place).
- **Neměň nic mimo `ums/`.** Na této větvi se edituje výhradně adresář `ums/`.
- Skript běží pod `Set-StrictMode -Version Latest` (`epic-graph.ps1:105`) a `$ErrorActionPreference = 'Stop'` (`:106`): **každý** přístup k členu objektu ze snapshotu musí být chráněný `$obj.PSObject.Properties['name']`, jinak chybějící pole skript shodí.
- Názvy stavů porovnávej **výhradně operátorem `-contains`** nad normalizovanými hodnotami (lowercase, bez diakritiky). NIKDY `.Contains()` — ta je na `IList` ordinal case-sensitive a tiše by shodila case-insensitivní match.
- Uvnitř funkcí se na režim odkazuj přes `$script:Source`, ne `$Source` — parametr není ve scope funkce (stejná past, jakou kód dokumentuje na `:448`–`:451`).
- Nové testy nikdy nepoužívají `-Check` — oracle by do výstupu vložil hlášku „✅ Žádný nesoulad nenalezen" (`:956`) a kolidoval s asserty na ✅.
- `Complete-Tests` (`_assert.ps1:18`) volá `exit`. V testovacím souboru MUSÍ zůstat poslední — nové asserty se vkládají PŘED ni.
- Nedotýkej se existujících fixtures `fixtures/jira/snap.json`, `fixtures/jira/afterwindow.json`, `fixtures/basic/`, `fixtures/newstyle/` ani existujících testovacích souborů.
- Nové soubory zapisuj v UTF-8 bez BOM, LF konce řádků (`ums/.gitattributes`: `.claude/skills/** text eol=lf`).
- Texty legend ve výstupu skriptu jsou **české**; `SKILL.md` a komentáře v kódu drží jazyk okolního textu (`SKILL.md` anglicko-český mix, komentáře ve skriptu česky u lokálních poznámek). Commit messages česky.
- Testy se spouštějí po jednom souboru, runner v repu není:
  `pwsh -NoProfile -File ums/.claude/skills/mb-epic-graph/tests/<soubor>.tests.ps1`

---

## File Structure

**Vytvořit:**

- `ums/.claude/skills/mb-epic-graph/tests/fixtures/jira/status.json` — Jira snapshot pro rozhodovací matici: epic `DEMO-0` + tikety `DEMO-1`…`DEMO-17`, každý s `status.name` i `status.statusCategory.key` (kromě záměrně poškozeného `DEMO-10`).
- `ums/.claude/skills/mb-epic-graph/tests/fixtures/status_proposals/next/design_demo_2.md` — draft atribuovaný na `DEMO-2`.
- `…/status_proposals/next/design_demo_4.md` — draft atribuovaný na `DEMO-4`.
- `…/status_proposals/active/design_demo_8.md` — proposal v `active/` pro `DEMO-8`.
- `…/status_proposals/active/design_demo_13.md` — proposal v `active/` pro `DEMO-13`.
- `…/status_stav/next/design_alfa.md`, `design_beta.md`, `design_gama.md` — fixture pro režim Proposals; `alfa` má `**Stav:** Test`, `gama` má `**Stav:** Design Review`.
- `ums/.claude/skills/mb-epic-graph/tests/status-glyph.tests.ps1` — všechny testy rozhodovací matice (Jira i Proposals režim).

**Modifikovat:**

- `ums/.claude/skills/mb-epic-graph/scripts/epic-graph.ps1` — ochrana `status.name` (`:241`), konstanty + `Test-StatusNameIn` + `Test-DoneForPlanning` (před `:644`), `Test-Unblocked` (`:651`), kaskáda `Get-StatusGlyph` (`:655`–`:675`), nápověda `.PARAMETER NoStatus` (`:60`–`:70`), legendy (`:927`, `:929`).
- `ums/.claude/skills/mb-epic-graph/SKILL.md` — verze (`:7`), degradovaný výčet glyphů (`:94`), rodina glyphů v „Use the outputs" (`:123`–`:132`), požadavek na `fields` u druhého snapshotu (krok 1).

Čísla řádků jsou z výchozího stavu (commit `40ea892`); po prvních editacích se posunou — orientuj se podle citovaného kódu, ne podle čísla.

---

### Task 1: Fixtures a ochrana jména stavu

**Files:**
- Create: `ums/.claude/skills/mb-epic-graph/tests/fixtures/jira/status.json`
- Create: `ums/.claude/skills/mb-epic-graph/tests/fixtures/status_proposals/next/design_demo_2.md`
- Create: `ums/.claude/skills/mb-epic-graph/tests/fixtures/status_proposals/next/design_demo_4.md`
- Create: `ums/.claude/skills/mb-epic-graph/tests/fixtures/status_proposals/active/design_demo_8.md`
- Create: `ums/.claude/skills/mb-epic-graph/tests/fixtures/status_proposals/active/design_demo_13.md`
- Create: `ums/.claude/skills/mb-epic-graph/tests/status-glyph.tests.ps1`
- Modify: `ums/.claude/skills/mb-epic-graph/scripts/epic-graph.ps1:241`

**Interfaces:**
- Consumes: nic (první task).
- Produces: fixture cesty a proměnné, na které staví všechny další tasky — v testovacím souboru `$status` (cesta k `fixtures/jira/status.json`), `$props` (cesta ke `fixtures/status_proposals`), `$bare` (výsledek běhu bez `-ProposalPath`), `$full` (výsledek běhu s `-ProposalPath`); obě jsou hashtable `@{ Out; Code }` z `Invoke-Graph`.

- [ ] **Step 1: Vytvoř Jira fixture**

Vytvoř `tests/fixtures/jira/status.json` s tímto obsahem (`DEMO-10` má úmyslně prázdný objekt `status`; linky se deklarují jednostranně od blokátoru, stejně jako v `snap.json` — asymetrii by řešil jen `-Check`, který nepoužíváme):

```json
{ "issues": [
  { "key": "DEMO-0",  "fields": { "summary": "Epic stavovych ikon", "issuetype": {"name":"Epic"},  "status": {"name":"To Do","statusCategory":{"key":"new"}}, "issuelinks": [] } },

  { "key": "DEMO-1",  "fields": { "summary": "[graf] Tiket v testu", "issuetype": {"name":"Story"}, "status": {"name":"Test","statusCategory":{"key":"indeterminate"}},
      "issuelinks": [ { "type": {"name":"Blocks"}, "outwardIssue": {"key":"DEMO-2"} } ] } },
  { "key": "DEMO-2",  "fields": { "summary": "[graf] Nasledník tiketu v testu", "issuetype": {"name":"Story"}, "status": {"name":"To Do","statusCategory":{"key":"new"}}, "issuelinks": [] } },

  { "key": "DEMO-3",  "fields": { "summary": "[graf] Tiket v implementaci", "issuetype": {"name":"Story"}, "status": {"name":"In Progress","statusCategory":{"key":"indeterminate"}},
      "issuelinks": [ { "type": {"name":"Blocks"}, "outwardIssue": {"key":"DEMO-4"} } ] } },
  { "key": "DEMO-4",  "fields": { "summary": "[graf] Nasledník tiketu v implementaci", "issuetype": {"name":"Story"}, "status": {"name":"To Do","statusCategory":{"key":"new"}}, "issuelinks": [] } },

  { "key": "DEMO-5",  "fields": { "summary": "[graf] Hotovy tiket", "issuetype": {"name":"Story"}, "status": {"name":"Done","statusCategory":{"key":"done"}},
      "issuelinks": [ { "type": {"name":"Blocks"}, "outwardIssue": {"key":"DEMO-6"} } ] } },
  { "key": "DEMO-6",  "fields": { "summary": "[graf] Nasledník hotoveho tiketu bez navrhu", "issuetype": {"name":"Story"}, "status": {"name":"To Do","statusCategory":{"key":"new"}}, "issuelinks": [] } },

  { "key": "DEMO-7",  "fields": { "summary": "[graf] Tiket ve stavu malymi pismeny", "issuetype": {"name":"Story"}, "status": {"name":"test","statusCategory":{"key":"indeterminate"}}, "issuelinks": [] } },
  { "key": "DEMO-8",  "fields": { "summary": "[graf] Tiket v testu s proposalem v active", "issuetype": {"name":"Story"}, "status": {"name":"Test","statusCategory":{"key":"indeterminate"}}, "issuelinks": [] } },

  { "key": "DEMO-9",  "fields": { "summary": "[graf] Tiket blokovany externim tiketem", "issuetype": {"name":"Story"}, "status": {"name":"To Do","statusCategory":{"key":"new"}},
      "issuelinks": [ { "type": {"name":"Blocks"}, "inwardIssue": {"key":"DEMO-99"} } ] } },
  { "key": "DEMO-10", "fields": { "summary": "[graf] Tiket s prazdnym stavem", "issuetype": {"name":"Story"}, "status": {}, "issuelinks": [] } },

  { "key": "DEMO-11", "fields": { "summary": "[graf] Tiket v review", "issuetype": {"name":"Story"}, "status": {"name":"Review","statusCategory":{"key":"indeterminate"}},
      "issuelinks": [ { "type": {"name":"Blocks"}, "outwardIssue": {"key":"DEMO-15"} } ] } },
  { "key": "DEMO-12", "fields": { "summary": "[graf] Tiket v dokumentaci", "issuetype": {"name":"Story"}, "status": {"name":"Documentation","statusCategory":{"key":"indeterminate"}}, "issuelinks": [] } },

  { "key": "DEMO-13", "fields": { "summary": "[graf] Tiket v design review s proposalem v active", "issuetype": {"name":"Story"}, "status": {"name":"Design Review","statusCategory":{"key":"indeterminate"}},
      "issuelinks": [ { "type": {"name":"Blocks"}, "outwardIssue": {"key":"DEMO-14"} } ] } },
  { "key": "DEMO-14", "fields": { "summary": "[graf] Nasledník tiketu v design review", "issuetype": {"name":"Story"}, "status": {"name":"To Do","statusCategory":{"key":"new"}}, "issuelinks": [] } },

  { "key": "DEMO-15", "fields": { "summary": "[graf] Nasledník tiketu v review", "issuetype": {"name":"Story"}, "status": {"name":"To Do","statusCategory":{"key":"new"}}, "issuelinks": [] } },

  { "key": "DEMO-16", "fields": { "summary": "[graf] Zruseny tiket", "issuetype": {"name":"Story"}, "status": {"name":"Cancelled","statusCategory":{"key":"done"}},
      "issuelinks": [ { "type": {"name":"Blocks"}, "outwardIssue": {"key":"DEMO-17"} } ] } },
  { "key": "DEMO-17", "fields": { "summary": "[graf] Nasledník zruseneho tiketu", "issuetype": {"name":"Story"}, "status": {"name":"To Do","statusCategory":{"key":"new"}}, "issuelinks": [] } }
] }
```

Summary texty jsou úmyslně bez diakritiky a bez slov `blokuje`/`blokováno` — prose-scan oracle by na nich hlásil nálezy, kdyby někdo fixture pustil s `-Check`.

- [ ] **Step 2: Vytvoř proposal fixtures pro Jira režim**

`tests/fixtures/status_proposals/next/design_demo_2.md`:

```markdown
# Návrh: DEMO-2

- **Jira:** DEMO-2
- **Vytvořeno:** 2026-07-31

## Cíl

Fixture pro testy stavových ikon: živý draft ve stage `next/`.
```

`tests/fixtures/status_proposals/next/design_demo_4.md`:

```markdown
# Návrh: DEMO-4

- **Jira:** DEMO-4
- **Vytvořeno:** 2026-07-31

## Cíl

Fixture pro testy stavových ikon: živý draft ve stage `next/`.
```

`tests/fixtures/status_proposals/active/design_demo_8.md`:

```markdown
# Návrh: DEMO-8

- **Jira:** DEMO-8
- **Vytvořeno:** 2026-07-31

## Cíl

Fixture pro testy stavových ikon: proposal ve stage `active/`.
```

`tests/fixtures/status_proposals/active/design_demo_13.md`:

```markdown
# Návrh: DEMO-13

- **Jira:** DEMO-13
- **Vytvořeno:** 2026-07-31

## Cíl

Fixture pro testy stavových ikon: proposal ve stage `active/`.
```

Atribuce na tiket běží přes hlavičku `**Jira:** <KEY>` (`epic-graph.ps1:374`, regex `[A-Z][A-Z0-9]+-\d+` — klíč MUSÍ být uppercase); stage se určuje z názvu složky v cestě (`:380`–`:388`).

- [ ] **Step 3: Napiš selhávající test**

Vytvoř `tests/status-glyph.tests.ps1`:

```powershell
# Status-glyph tests (Jira mode): rozhodovací matice z
# ums/docs/design_epic_graph_test_jako_hotovo.md.
# Běhy záměrně BEZ -Check (oracle by do výstupu vložil vlastní ✅).
. (Join-Path $PSScriptRoot '_assert.ps1')
$status = Join-Path $PSScriptRoot 'fixtures\jira\status.json'
$props  = Join-Path $PSScriptRoot 'fixtures\status_proposals'

Write-Host 'Jira mode: fixture runs (malformed status object must not crash)'
$bare = Invoke-Graph @('-Source','Jira','-InputFile',$status,'-EpicKey','DEMO-0')
Assert-Eq $bare.Code 0 'run without -ProposalPath exits 0'
$full = Invoke-Graph @('-Source','Jira','-InputFile',$status,'-EpicKey','DEMO-0','-ProposalPath',$props)
Assert-Eq $full.Code 0 'run with -ProposalPath exits 0'
Assert-Match $bare.Out '\[DEMO-10\]' 'ticket with empty status object still lands in the table'

Complete-Tests
```

- [ ] **Step 4: Spusť test a ověř, že selže**

Run: `pwsh -NoProfile -File ums/.claude/skills/mb-epic-graph/tests/status-glyph.tests.ps1`

Expected: FAIL — oba běhy vrátí exit code 1 a ve výstupu je `PropertyNotFoundException` / `The property 'name' cannot be found on this object`. Příčina: `:241` čte `$statusObj.name` bez ochrany, `DEMO-10` má `"status": {}`.

- [ ] **Step 5: Ochraň jméno stavu**

V `epic-graph.ps1` nahraď řádek `:241`:

```powershell
            Status = if ($statusObj) { [string]$statusObj.name } else { '' }
```

za:

```powershell
            Status = if ($statusObj -and $statusObj.PSObject.Properties['name']) { [string]$statusObj.name } else { '' }
```

(Tvar je záměrně shodný s ochranou `statusCategory` na následujícím řádku.)

- [ ] **Step 6: Spusť test a ověř, že prochází**

Run: `pwsh -NoProfile -File ums/.claude/skills/mb-epic-graph/tests/status-glyph.tests.ps1`

Expected: PASS — `3 passed`.

- [ ] **Step 7: Ověř, že stávající testy nespadly**

Run:
```bash
pwsh -NoProfile -File ums/.claude/skills/mb-epic-graph/tests/graph-generation.tests.ps1
pwsh -NoProfile -File ums/.claude/skills/mb-epic-graph/tests/e2e.tests.ps1
```
Expected: oba `… passed`, exit 0.

- [ ] **Step 8: Commit**

```bash
git add ums/.claude/skills/mb-epic-graph/tests ums/.claude/skills/mb-epic-graph/scripts/epic-graph.ps1
git commit -m "UMS: epic-graph — fixture rozhodovací matice + ochrana jména stavu

Snapshot s prázdným objektem status skript shazoval: :241 čte status.name bez
testu PSObject.Properties, na rozdíl od chráněného statusCategory na :242.
Pod StrictMode a ErrorActionPreference=Stop to je exit 1."
```

---

### Task 2: Degradovaný běh přestane tvrdit „návrh hotov" (❔)

**Files:**
- Modify: `ums/.claude/skills/mb-epic-graph/scripts/epic-graph.ps1` (`Get-StatusGlyph`, větev `-not $proposalInfoAvailable`, výchozí `:667`–`:670`)
- Modify: `ums/.claude/skills/mb-epic-graph/tests/status-glyph.tests.ps1`

**Interfaces:**
- Consumes: `$status`, `$bare` z Tasku 1.
- Produces: vzor per-tiket assertu, který používají všechny další tasky — `Assert-Match $bare.Out '<glyph> \S+ \[<KEY>\]' '<popis>'`. Buňka tabulky má tvar `"$statusGlyph $(Get-Emoji $k) $keyMd $sum"` (`:683`–`:684`), takže `\S+` je stream-emoji a `\[KEY\]` začátek markdown linku.

- [ ] **Step 1: Napiš selhávající asserty**

Do `status-glyph.tests.ps1` vlož PŘED `Complete-Tests`:

```powershell
Write-Host 'Jira mode without -ProposalPath: unblocked To Do is ❔ (proposal state unknown)'
Assert-Match $bare.Out '❔ \S+ \[DEMO-6\]'  'DEMO-6 (blocker Done, no proposal info) -> ❔'
Assert-Match $bare.Out '❔ \S+ \[DEMO-17\]' 'DEMO-17 (blocker Cancelled) -> ❔'
Assert-Match $bare.Out '❔ \S+ \[DEMO-10\]' 'DEMO-10 (empty status, unblocked) -> ❔'
Assert-NotMatch $bare.Out '▶️ \S+ \[DEMO-6\]' 'no ▶️ without proposal information'
```

- [ ] **Step 2: Spusť test a ověř, že selže**

Run: `pwsh -NoProfile -File ums/.claude/skills/mb-epic-graph/tests/status-glyph.tests.ps1`

Expected: FAIL — čtyři nové asserty selžou, protože degradovaná větev dnes vrací `▶️`.

- [ ] **Step 3: Změň degradovanou větev kaskády**

V `Get-StatusGlyph` nahraď:

```powershell
    if (-not $proposalInfoAvailable) {
        # bez -ProposalPath: 4-stavová degradace (bez rozlišení proposalu)
        if ($unblocked) { return '▶️' } else { return '⛔' }
    }
```

za:

```powershell
    if (-not $proposalInfoAvailable) {
        # bez -ProposalPath o návrzích nic nevíme: ❔ = odblokováno, stav návrhu
        # neznámý. ▶️ zůstává vyhrazeno pro „návrh existuje" (viz níže), aby
        # ikona netvrdila víc, než skript ví.
        if ($unblocked) { return '❔' } else { return '⛔' }
    }
```

- [ ] **Step 4: Spusť test a ověř, že prochází**

Run: `pwsh -NoProfile -File ums/.claude/skills/mb-epic-graph/tests/status-glyph.tests.ps1`

Expected: PASS — `7 passed`.

- [ ] **Step 5: Ověř stávající testy**

Run:
```bash
pwsh -NoProfile -File ums/.claude/skills/mb-epic-graph/tests/graph-generation.tests.ps1
pwsh -NoProfile -File ums/.claude/skills/mb-epic-graph/tests/e2e.tests.ps1
```
Expected: oba `… passed`. Assert na `▶️` (`graph-generation.tests.ps1:19`) běží v Proposals režimu, kde je `-ProposalPath` povinný, takže se ho změna netýká.

- [ ] **Step 6: Commit**

```bash
git add ums/.claude/skills/mb-epic-graph
git commit -m "UMS: epic-graph — bez -ProposalPath nově ❔ místo ▶️

Degradovaná větev kaskády tvrdila „návrh hotov, spusť implementaci\" i tehdy,
když skript o návrzích nemá žádnou informaci. ❔ = odblokováno, stav návrhu
neznámý; ▶️ zůstává vyhrazeno pro doložený živý návrh."
```

---

### Task 3: 💡 místo 🆕 pro tiket bez návrhu

**Files:**
- Modify: `ums/.claude/skills/mb-epic-graph/scripts/epic-graph.ps1` (`Get-StatusGlyph`, poslední větev, výchozí `:674`)
- Modify: `ums/.claude/skills/mb-epic-graph/tests/status-glyph.tests.ps1`

**Interfaces:**
- Consumes: `$full` z Tasku 1 (běh s `-ProposalPath`), vzor assertu z Tasku 2.
- Produces: nic nového pro další tasky.

- [ ] **Step 1: Napiš selhávající asserty**

Do `status-glyph.tests.ps1` vlož PŘED `Complete-Tests`:

```powershell
Write-Host 'Jira mode with -ProposalPath: no proposal -> 💡, live draft blocked -> ⏳'
Assert-Match $full.Out '💡 \S+ \[DEMO-6\]'  'DEMO-6 (unblocked, no proposal) -> 💡'
Assert-Match $full.Out '💡 \S+ \[DEMO-17\]' 'DEMO-17 (blocker Cancelled, no proposal) -> 💡'
Assert-Match $full.Out '💡 \S+ \[DEMO-10\]' 'DEMO-10 (empty status, no proposal) -> 💡'
Assert-Match $full.Out '⏳ \S+ \[DEMO-4\]'  'DEMO-4 (draft in next/, blocked by In Progress) -> ⏳'
Assert-NotMatch $full.Out '🆕' '🆕 is retired from the whole family'
```

- [ ] **Step 2: Spusť test a ověř, že selže**

Run: `pwsh -NoProfile -File ums/.claude/skills/mb-epic-graph/tests/status-glyph.tests.ps1`

Expected: FAIL — asserty na `💡` selžou a `Assert-NotMatch '🆕'` selže také (kaskáda i legenda dnes `🆕` obsahují).

- [ ] **Step 3: Vymeň glyph v poslední větvi kaskády**

V `Get-StatusGlyph` nahraď:

```powershell
    if ($unblocked) { return '🆕' } else { return '⛔' }        # bez návrhu: k rozpracování / blokováno
```

za:

```powershell
    if ($unblocked) { return '💡' } else { return '⛔' }        # bez návrhu: k rozpracování / blokováno
```

- [ ] **Step 4: Spusť test a ověř zbytkové selhání legendy**

Run: `pwsh -NoProfile -File ums/.claude/skills/mb-epic-graph/tests/status-glyph.tests.ps1`

Expected: asserty na `💡` a `⏳` PASS; `Assert-NotMatch '🆕'` stále FAIL — `🆕` zůstalo v legendě tabulky vln (`:929`). To je správné, legendu opravíš v tomto kroku:

V `epic-graph.ps1` nahraď v legendě Jira režimu (`:929`) sekvenci

```text
· 🆕 k rozpracování (odblokováno, bez návrhu) ·
```

za

```text
· 💡 k rozpracování (odblokováno, bez návrhu) ·
```

Zbytek textu legendy neměň — kompletní přepis legendy dělá Task 7.

- [ ] **Step 5: Spusť test a ověř, že prochází**

Run: `pwsh -NoProfile -File ums/.claude/skills/mb-epic-graph/tests/status-glyph.tests.ps1`

Expected: PASS — `12 passed`.

- [ ] **Step 6: Ověř stávající testy**

Run:
```bash
pwsh -NoProfile -File ums/.claude/skills/mb-epic-graph/tests/graph-generation.tests.ps1
pwsh -NoProfile -File ums/.claude/skills/mb-epic-graph/tests/e2e.tests.ps1
```
Expected: oba `… passed`.

- [ ] **Step 7: Commit**

```bash
git add ums/.claude/skills/mb-epic-graph
git commit -m "UMS: epic-graph — 💡 místo 🆕 pro odblokovaný tiket bez návrhu

🆕 se v terminálových fontech renderuje jako podobně velký tmavý blok jako ▶️
a v tabulce vln se s ním pletlo. 💡 sedne i sémanticky: chybí návrh, tiket
čeká na rozpracování."
```

---

### Task 4: Hotovost pro plánování (Test, Review, Documentation → 🧪)

**Files:**
- Modify: `ums/.claude/skills/mb-epic-graph/scripts/epic-graph.ps1` (nové konstanty a funkce před `Test-Unblocked` `:644`; `Test-Unblocked` `:651`; kaskáda `Get-StatusGlyph` za větví `done`)
- Create: `ums/.claude/skills/mb-epic-graph/tests/fixtures/status_stav/next/design_alfa.md`
- Create: `ums/.claude/skills/mb-epic-graph/tests/fixtures/status_stav/next/design_beta.md`
- Modify: `ums/.claude/skills/mb-epic-graph/tests/status-glyph.tests.ps1`

**Interfaces:**
- Consumes: `$status`, `$props`, `$bare`, `$full` z Tasku 1.
- Produces:
  - `$script:DoneForPlanningStatusNames` — `[string[]]`, normalizované názvy stavů (lowercase, bez diakritiky).
  - `function Test-StatusNameIn([string] $key, [string[]] $names) -> [bool]` — `$true`, když je normalizovaný název stavu tiketu `$key` v `$names`; v jiném režimu než `Jira` vždy `$false`. Task 5 ji používá pro `Design Review`.
  - `function Test-DoneForPlanning([string] $key) -> [bool]` — hotovost pro plánování (kategorie `done` NEBO název v `$script:DoneForPlanningStatusNames`); pro klíč mimo `$issues` vrací `$false`.
  - V testovacím souboru proměnná `$stav` — cesta ke `fixtures/status_stav`.

- [ ] **Step 1: Vytvoř fixture pro režim Proposals**

`tests/fixtures/status_stav/next/design_alfa.md`:

```markdown
# Návrh: alfa

- **Stav:** Test
- **Blokuje:** [design_beta.md](design_beta.md)
- **Vytvořeno:** 2026-07-31

## Cíl

Fixture pro režim Proposals: hlavičkové pole `**Stav:**` je volný text, takže
hodnota „Test" nesmí uzel prohlásit za hotový pro plánování.
```

`tests/fixtures/status_stav/next/design_beta.md`:

```markdown
# Návrh: beta

- **Stav:** návrh
- **Vytvořeno:** 2026-07-31

## Cíl

Fixture pro režim Proposals: následník uzlu alfa.
```

- [ ] **Step 2: Napiš selhávající asserty**

Nejdřív doplň k deklaracím cest na začátku souboru (vedle `$status` a `$props`):

```powershell
$stav   = Join-Path $PSScriptRoot 'fixtures\status_stav'
```

Pak vlož PŘED `Complete-Tests`:

```powershell
Write-Host 'Jira mode: Test/Review/Documentation are done for planning'
Assert-Match $bare.Out '🧪 \S+ \[DEMO-1\]'  'DEMO-1 (Test) -> 🧪'
Assert-Match $bare.Out '🧪 \S+ \[DEMO-7\]'  'DEMO-7 (status name in lower case) -> 🧪'
Assert-Match $bare.Out '🧪 \S+ \[DEMO-8\]'  'DEMO-8 (Test) -> 🧪 without proposal info'
Assert-Match $full.Out '🧪 \S+ \[DEMO-8\]'  'DEMO-8 (Test + active/ proposal) -> 🧪, not 🔨'
Assert-Match $bare.Out '🧪 \S+ \[DEMO-11\]' 'DEMO-11 (Review) -> 🧪'
Assert-Match $bare.Out '🧪 \S+ \[DEMO-12\]' 'DEMO-12 (Documentation) -> 🧪'
Assert-Match $bare.Out '🔨 \S+ \[DEMO-3\]'  'DEMO-3 (In Progress) stays 🔨 — no category-wide generalization'

Write-Host 'Jira mode: successors of Test/Review are unblocked'
Assert-Match $bare.Out '❔ \S+ \[DEMO-2\]'  'DEMO-2 (blocker in Test) -> ❔ without proposal info'
Assert-Match $full.Out '▶️ \S+ \[DEMO-2\]'  'DEMO-2 (blocker in Test, draft in next/) -> ▶️'
Assert-Match $bare.Out '❔ \S+ \[DEMO-15\]' 'DEMO-15 (blocker in Review) -> ❔'
Assert-Match $full.Out '💡 \S+ \[DEMO-15\]' 'DEMO-15 (blocker in Review, no proposal) -> 💡'
Assert-Match $bare.Out '⛔ \S+ \[DEMO-4\]'  'DEMO-4 (blocker In Progress) stays blocked'

Write-Host 'Proposals mode: free-text **Stav:** must not be matched by name'
$sp = Invoke-Graph @('-Source','Proposals','-ProposalPath',$stav,'-EpicKey','stav')
Assert-Eq $sp.Code 0 'proposals mode exits 0'
Assert-NotMatch $sp.Out '🧪 \S+ \*\*alfa\*\*' 'proposal with **Stav:** Test does not get 🧪'
Assert-Match $sp.Out '▶️ \S+ \*\*alfa\*\*' 'alfa (live next/, unblocked) -> ▶️'
Assert-Match $sp.Out '⏳ \S+ \*\*beta\*\*' 'beta (live next/, blocked by alfa) -> ⏳'
```

Asserty na absenci ikony jsou úmyslně **per-uzel** (`🧪 \S+ \*\*alfa\*\*`), ne
globální (`'🧪'`): legenda Proposals režimu bude po Tasku 7 obsahovat větu
„Ikony 🧪/👀/❔ zde nevznikají", takže globální `Assert-NotMatch '🧪'` by v ní
tehdy začal selhávat.

- [ ] **Step 3: Spusť test a ověř, že selže**

Run: `pwsh -NoProfile -File ums/.claude/skills/mb-epic-graph/tests/status-glyph.tests.ps1`

Expected: FAIL — tikety v `Test`/`Review`/`Documentation` dnes nesou `🔨` a jejich následníci `⛔`. Proposals asserty už procházejí (chování v tomto režimu se nemění) — to je záměr, jsou to pojistky proti prosáknutí v dalších krocích.

- [ ] **Step 4: Přidej konstantu a obě funkce**

V `epic-graph.ps1` vlož PŘED funkci `Test-Unblocked`:

```powershell
# Stavy, které se pro plánování počítají jako hotové, i když jejich
# statusCategory hotová není: práce je odvedená, dočítává se ocas.
# Test (10205), Review (10206) a Documentation (11064) jsou v kategorii
# indeterminate stejně jako In Progress (3) — rozlišit lze jen názvem.
# Hodnoty jsou normalizované (lowercase, bez diakritiky).
$script:DoneForPlanningStatusNames = @('test', 'review', 'documentation')

function Test-StatusNameIn([string] $key, [string[]] $names) {
    # Match podle NÁZVU stavu. Jen v Jira režimu — v Proposals režimu plní
    # Status volnotextové hlavičkové pole '**Stav:**', takže hodnota „Test"
    # by tiše měnila semantiku JIRA-less grafů. Uvnitř funkce je nutné
    # $script:Source, parametr $Source zde není ve scope.
    # Porovnání jde -contains (case-insensitive), NIKOLI .Contains().
    if ($script:Source -ne 'Jira') { return $false }
    if (-not $issues.Contains($key)) { return $false }
    $n = (Remove-Diacritics ([string]$issues[$key].Status).Trim()).ToLowerInvariant()
    if (-not $n) { return $false }
    return ($names -contains $n)
}

function Test-DoneForPlanning([string] $key) {
    # Hotový pro plánování = neblokuje své následníky.
    if (-not $issues.Contains($key)) { return $false }   # externí tiket: konzervativně ne
    if ($issues[$key].StatusCat -eq 'done') { return $true }
    return (Test-StatusNameIn $key $script:DoneForPlanningStatusNames)
}
```

- [ ] **Step 5: Přepoj `Test-Unblocked` na novou funkci**

V `Test-Unblocked` nahraď:

```powershell
    # odblokováno = všechny přímé Blocks-blokátory jsou hotové (statusCategory=done).
    # Blokátor s neznámým stavem (externí, mimo snapshot) se konzervativně počítá
    # jako blokující — pro přesnost doplň externí blokátory druhým snapshotem.
    $preds = @(@($blockedBy[$k]) | Where-Object { $_ })
    if ($preds.Count -eq 0) { return $true }
    foreach ($p in $preds) {
        if (-not ($issues.Contains($p) -and $issues[$p].StatusCat -eq 'done')) { return $false }
    }
    return $true
```

za:

```powershell
    # odblokováno = všechny přímé Blocks-blokátory jsou hotové pro plánování
    # (kategorie done, nebo Test/Review/Documentation — viz Test-DoneForPlanning).
    # Blokátor s neznámým stavem (externí, mimo snapshot) se konzervativně počítá
    # jako blokující — pro přesnost doplň externí blokátory druhým snapshotem.
    $preds = @(@($blockedBy[$k]) | Where-Object { $_ })
    if ($preds.Count -eq 0) { return $true }
    foreach ($p in $preds) {
        if (-not (Test-DoneForPlanning $p)) { return $false }
    }
    return $true
```

- [ ] **Step 6: Přidej stupeň 🧪 do kaskády**

V `Get-StatusGlyph` vlož nový řádek HNED za větev `done` a PŘED větev `indeterminate` (pořadí je nosné — jinak by 🧪 přebila kategorie `indeterminate` i `$proposalActive`):

```powershell
    if ($cat -eq 'done') { return '✅' }                                    # hotovo
    if (Test-StatusNameIn $k $script:DoneForPlanningStatusNames) { return '🧪' }  # v testu/review/dokumentaci
    if ($cat -eq 'indeterminate' -or $proposalActive.ContainsKey($k)) { return '🔨' }  # implementuje se
```

- [ ] **Step 7: Spusť test a ověř, že prochází**

Run: `pwsh -NoProfile -File ums/.claude/skills/mb-epic-graph/tests/status-glyph.tests.ps1`

Expected: PASS — `28 passed`.

- [ ] **Step 8: Ověř stávající testy**

Run:
```bash
pwsh -NoProfile -File ums/.claude/skills/mb-epic-graph/tests/graph-generation.tests.ps1
pwsh -NoProfile -File ums/.claude/skills/mb-epic-graph/tests/e2e.tests.ps1
pwsh -NoProfile -File ums/.claude/skills/mb-epic-graph/tests/oracle-prose.tests.ps1
pwsh -NoProfile -File ums/.claude/skills/mb-epic-graph/tests/oracle-structural.tests.ps1
```
Expected: všechny `… passed`.

- [ ] **Step 9: Commit**

```bash
git add ums/.claude/skills/mb-epic-graph
git commit -m "UMS: epic-graph — Test/Review/Documentation jsou hotové pro plánování

Všechny tři stavy leží v kategorii indeterminate stejně jako In Progress,
takže match musí jít podle názvu stavu; v režimu Proposals je vypnutý, protože
hlavičkové pole **Stav:** je volný text. Tikety v těchto stavech nesou 🧪
a neblokují své následníky."
```

---

### Task 5: Design Review dostane 👀 a dál blokuje

**Files:**
- Modify: `ums/.claude/skills/mb-epic-graph/scripts/epic-graph.ps1` (konstanta u `$script:DoneForPlanningStatusNames`; kaskáda `Get-StatusGlyph`)
- Create: `ums/.claude/skills/mb-epic-graph/tests/fixtures/status_stav/next/design_gama.md`
- Modify: `ums/.claude/skills/mb-epic-graph/tests/status-glyph.tests.ps1`

**Interfaces:**
- Consumes: `Test-StatusNameIn` z Tasku 4, proměnné `$bare`, `$full`, `$stav`, `$sp`.
- Produces: `$script:DesignReviewStatusNames` — `[string[]]`, normalizované názvy stavů „čeká na architekta".

- [ ] **Step 1: Doplň fixture pro režim Proposals**

`tests/fixtures/status_stav/next/design_gama.md`:

```markdown
# Návrh: gama

- **Stav:** Design Review
- **Vytvořeno:** 2026-07-31

## Cíl

Fixture pro režim Proposals: ani hodnota „Design Review" v poli `**Stav:**`
nesmí uzel označit ikonou 👀.
```

- [ ] **Step 2: Napiš selhávající asserty**

Do `status-glyph.tests.ps1` vlož PŘED `Complete-Tests`:

```powershell
Write-Host 'Jira mode: Design Review has its own glyph and keeps blocking'
Assert-Match $bare.Out '👀 \S+ \[DEMO-13\]' 'DEMO-13 (Design Review) -> 👀'
Assert-Match $full.Out '👀 \S+ \[DEMO-13\]' 'DEMO-13 (Design Review + active/ proposal) -> 👀, not 🔨'
Assert-Match $bare.Out '⛔ \S+ \[DEMO-14\]' 'DEMO-14 (blocker in Design Review) stays ⛔ without proposal info'
Assert-Match $full.Out '⛔ \S+ \[DEMO-14\]' 'DEMO-14 (blocker in Design Review, no proposal) stays ⛔'

Write-Host 'Proposals mode: free-text **Stav:** Design Review must not be matched'
Assert-NotMatch $sp.Out '👀 \S+ \*\*gama\*\*' 'proposal with **Stav:** Design Review does not get 👀'
Assert-Match $sp.Out '▶️ \S+ \*\*gama\*\*' 'gama (live next/, unblocked) -> ▶️'
```

Použij existující `$sp` z Tasku 4 — soubor se spouští odshora, takže tentýž běh
už vidí i nově přidanou fixture `design_gama.md`; druhý identický běh by byl
jen zbytečný subproces.

- [ ] **Step 3: Spusť test a ověř, že selže**

Run: `pwsh -NoProfile -File ums/.claude/skills/mb-epic-graph/tests/status-glyph.tests.ps1`

Expected: FAIL — `DEMO-13` dnes nese `🔨` (kategorie `indeterminate`), takže první dva asserty selžou. Asserty na `⛔` u `DEMO-14` a Proposals pojistky procházejí už teď.

- [ ] **Step 4: Přidej konstantu**

V `epic-graph.ps1` vlož pod `$script:DoneForPlanningStatusNames`:

```powershell
# Stav, kdy tiket čeká na posouzení architektem. NENÍ hotový pro plánování
# (návrh se ještě nepřevedl na implementaci), ale má vlastní ikonu, aby na něj
# dashboard nikoho neposílal. V UMS workflow zatím není zapojen — podpora
# dopředu (viz mb-architect-review a kontrakt, Architect Review Gate).
$script:DesignReviewStatusNames = @('design review')
```

- [ ] **Step 5: Přidej stupeň 👀 do kaskády**

V `Get-StatusGlyph` vlož nový řádek za stupeň 🧪 a PŘED větev `indeterminate`:

```powershell
    if (Test-StatusNameIn $k $script:DoneForPlanningStatusNames) { return '🧪' }  # v testu/review/dokumentaci
    if (Test-StatusNameIn $k $script:DesignReviewStatusNames) { return '👀' }     # čeká na architekta
    if ($cat -eq 'indeterminate' -or $proposalActive.ContainsKey($k)) { return '🔨' }  # implementuje se
```

- [ ] **Step 6: Spusť test a ověř, že prochází**

Run: `pwsh -NoProfile -File ums/.claude/skills/mb-epic-graph/tests/status-glyph.tests.ps1`

Expected: PASS — `34 passed`.

- [ ] **Step 7: Ověř stávající testy**

Run:
```bash
pwsh -NoProfile -File ums/.claude/skills/mb-epic-graph/tests/graph-generation.tests.ps1
pwsh -NoProfile -File ums/.claude/skills/mb-epic-graph/tests/e2e.tests.ps1
```
Expected: oba `… passed`.

- [ ] **Step 8: Commit**

```bash
git add ums/.claude/skills/mb-epic-graph
git commit -m "UMS: epic-graph — stav Design Review nese 👀 a dál blokuje

Návrh v posouzení není implementace, takže následníky neodblokovává; vlastní
ikona brání tomu, aby dashboard poslal někoho na tiket, jehož návrh právě
posuzuje architekt. Stupeň kaskády je před kategorií indeterminate i před
$proposalActive — tiket předaný architektovi má připnutý work item v active/."
```

---

### Task 6: Regresní pojistky rodiny ikon

**Files:**
- Modify: `ums/.claude/skills/mb-epic-graph/tests/status-glyph.tests.ps1`

**Interfaces:**
- Consumes: `$status`, `$props`, `$bare`, `$full` z Tasku 1.
- Produces: nic — čistě testovací task.

Tyto asserty projdou hned při prvním spuštění; nejsou TDD, jsou to pojistky proti tichým regresím při budoucím revendoringu upstreamu (chování, které nikdo netestuje, se zpravidla rozbije jako první).

- [ ] **Step 1: Přidej asserty na hotovost, externí blokátor a `-NoStatus`**

Do `status-glyph.tests.ps1` vlož PŘED `Complete-Tests`:

```powershell
Write-Host 'Jira mode: done category and external blockers'
Assert-Match $bare.Out '✅ \S+ \[DEMO-5\]'  'DEMO-5 (Done) -> ✅'
Assert-Match $bare.Out '✅ \S+ \[DEMO-16\]' 'DEMO-16 (Cancelled, category done) -> ✅'
Assert-Match $bare.Out '⛔ \S+ \[DEMO-9\]'  'DEMO-9 (blocker outside the snapshot) stays ⛔'
Assert-NotMatch $bare.Out '(?:✅|🧪|👀|🔨|▶️|⏳|💡|⛔|❔) \S+ \[DEMO-99\]' 'external node DEMO-99 carries no status glyph'

Write-Host 'Jira mode: -NoStatus suppresses the whole family'
$ns = Invoke-Graph @('-Source','Jira','-InputFile',$status,'-EpicKey','DEMO-0','-ProposalPath',$props,'-NoStatus')
Assert-Eq $ns.Code 0 '-NoStatus exits 0'
Assert-Match $ns.Out '\[DEMO-1\]' 'tickets are still listed with -NoStatus'
Assert-NotMatch $ns.Out '🧪' '-NoStatus suppresses 🧪'
Assert-NotMatch $ns.Out '👀' '-NoStatus suppresses 👀'
Assert-NotMatch $ns.Out '❔' '-NoStatus suppresses ❔'
Assert-NotMatch $ns.Out '💡' '-NoStatus suppresses 💡'
```

- [ ] **Step 2: Přidej asserty na neměnnost vln**

Do `status-glyph.tests.ps1` vlož PŘED `Complete-Tests`. Řádek tabulky vzniká jako `'| ' + ($cells -join ' | ') + ' |'` (`:730`), takže tiket ve vlně 1 má před svou buňkou jednu prázdnou:

```powershell
Write-Host 'Wave columns depend on Blocks topology only, not on status'
Assert-Match $bare.Out '(?m)^\| 🧪 \S+ \[DEMO-1\]'    'DEMO-1 sits in wave 0'
Assert-Match $bare.Out '(?m)^\|\s+\| ❔ \S+ \[DEMO-2\]' 'DEMO-2 sits in wave 1'
Assert-Match $full.Out '(?m)^\| 🧪 \S+ \[DEMO-1\]'    'DEMO-1 sits in wave 0 (with -ProposalPath)'
Assert-Match $full.Out '(?m)^\|\s+\| ▶️ \S+ \[DEMO-2\]' 'DEMO-2 sits in wave 1 (with -ProposalPath)'
```

- [ ] **Step 3: Spusť test a ověř, že prochází**

Run: `pwsh -NoProfile -File ums/.claude/skills/mb-epic-graph/tests/status-glyph.tests.ps1`

Expected: PASS — `48 passed`. Pokud některý assert selže, NEUPRAVUJ ho, aby prošel: znamená to, že chování neodpovídá rozhodovací matici v návrhu — zastav a reportuj.

- [ ] **Step 4: Commit**

```bash
git add ums/.claude/skills/mb-epic-graph/tests/status-glyph.tests.ps1
git commit -m "UMS: epic-graph — regresní pojistky rodiny ikon

Kategorie done, externí blokátor bez ikony, -NoStatus potlačí i nové glyphy
a sloupce vln zůstávají řízené jen topologií Blocks."
```

---

### Task 7: Legendy a nápověda ve skriptu

**Files:**
- Modify: `ums/.claude/skills/mb-epic-graph/scripts/epic-graph.ps1` (`.PARAMETER NoStatus` `:60`–`:70`; legenda Proposals `:927`; legenda Jira `:929`)
- Modify: `ums/.claude/skills/mb-epic-graph/tests/status-glyph.tests.ps1`

**Interfaces:**
- Consumes: `$bare`, `$full`, `$sp` (Proposals běh) z předchozích tasků.
- Produces: nic pro kód; texty legend jsou uživatelský výstup, na který se váží asserty.

- [ ] **Step 1: Napiš selhávající asserty na text legend**

Do `status-glyph.tests.ps1` vlož PŘED `Complete-Tests`:

```powershell
Write-Host 'Legend documents the whole family'
Assert-Match $full.Out '🧪 v testu/review/dokumentaci' 'jira legend documents 🧪'
Assert-Match $full.Out '👀 v design review' 'jira legend documents 👀'
Assert-Match $full.Out '💡 k rozpracování' 'jira legend documents 💡'
Assert-Match $full.Out '❔ odblokováno, stav návrhu neznámý' 'jira legend documents ❔'
Assert-Match $full.Out 'hotové pro plánování' 'jira legend defines what unblocks a successor'
Assert-Match $sp.Out '💡 opuštěný návrh' 'proposals legend documents the abandoned stage'
Assert-NotMatch $sp.Out '🧪 v testu' 'proposals legend does not advertise 🧪 as a ticket state'
```

- [ ] **Step 2: Spusť test a ověř, že selže**

Run: `pwsh -NoProfile -File ums/.claude/skills/mb-epic-graph/tests/status-glyph.tests.ps1`

Expected: FAIL — legendy dnes 🧪, 👀, ❔ ani „hotové pro plánování" a „opuštěný návrh" neobsahují.

- [ ] **Step 3: Přepiš legendu Jira režimu**

V `epic-graph.ps1` nahraď celý řádek legendy Jira režimu (výchozí `:929`):

```powershell
        [void]$report.AppendLine('**První ikona = stav tiketu** (JIRA stav + připravenost + existence návrhu, sloučeno do jedné): ✅ hotovo · 🔨 implementuje se · ▶️ připraveno k implementaci (návrh hotov, odblokováno) · ⏳ návrh hotov, čeká na blokátory · 💡 k rozpracování (odblokováno, bez návrhu) · ⛔ blokováno. Odblokováno = všechny `Blocks`-blokátory hotové.')
```

za:

```powershell
        [void]$report.AppendLine('**První ikona = stav tiketu** (JIRA stav + připravenost + existence návrhu, sloučeno do jedné): ✅ hotovo · 🧪 v testu/review/dokumentaci — počítá se jako hotový · 👀 v design review — čeká na architekta, nezačínej · 🔨 implementuje se · ▶️ připraveno k implementaci (návrh hotov, odblokováno) · ⏳ návrh hotov, čeká na blokátory · 💡 k rozpracování (odblokováno, bez návrhu) · ⛔ blokováno · ❔ odblokováno, stav návrhu neznámý (běh bez `-ProposalPath`). Odblokováno = všechny `Blocks`-blokátory hotové pro plánování (Done, Cancelled, Test, Review, Documentation).')
```

- [ ] **Step 4: Doplň legendu Proposals režimu**

Nahraď řádek legendy Proposals režimu (výchozí `:927`):

```powershell
        [void]$report.AppendLine('**První ikona = stav proposalu** (fáze složky + připravenost, sloučeno do jedné): ✅ hotovo (completed) · 🔨 implementuje se (active) · ▶️ připraveno k implementaci (odblokováno) · ⏳ čeká na blokátory · ⛔ blokováno. Odblokováno = všechny `Blocks`-blokátory hotové.')
```

za:

```powershell
        [void]$report.AppendLine('**První ikona = stav proposalu** (fáze složky + připravenost, sloučeno do jedné): ✅ hotovo (completed) · 🔨 implementuje se (active) · ▶️ připraveno k implementaci (odblokováno) · ⏳ čeká na blokátory · 💡 opuštěný návrh (abandoned) · ⛔ blokováno. Odblokováno = všechny `Blocks`-blokátory hotové. Ikony 🧪/👀/❔ zde nevznikají — hlavičkové pole `**Stav:**` je volný text a stav návrhu je vždy znám ze složky.')
```

- [ ] **Step 5: Přepiš nápovědu `.PARAMETER NoStatus`**

Nahraď v hlavičkovém komentáři skriptu celý blok (výchozí `:60`–`:70`):

```text
.PARAMETER NoStatus
Suppress the per-ticket status glyph in the wave table (the leading symbol
before the stream emoji). By default each ticket shows one merged status glyph
derived from its Jira status category, blocker readiness, and — when
-ProposalPath is given — whether a live proposal exists: ✅ done, 🔨 in
progress, ▶️ ready to implement (proposal + unblocked), ⏳ proposal ready but
still blocked, 🆕 ready to elaborate (unblocked, no proposal), ⛔ blocked.
Without -ProposalPath it degrades to ✅/🔨/▶️/⛔ (no proposal distinction).
In -Source Proposals the glyph comes from the proposal stage folder:
completed/ = done, active/ = in progress, next/ = live proposal.
```

za:

```text
.PARAMETER NoStatus
Suppress the per-ticket status glyph in the wave table (the leading symbol
before the stream emoji). By default each ticket shows one merged status glyph
derived from its Jira status NAME and category, blocker readiness, and — when
-ProposalPath is given — whether a live proposal exists: ✅ done, 🧪 in
test/review/documentation (counts as done for planning), 👀 in design review
(waiting for the architect, still blocking), 🔨 in progress, ▶️ ready to
implement (proposal + unblocked), ⏳ proposal ready but still blocked,
💡 ready to elaborate (unblocked, no proposal), ⛔ blocked.
Without -ProposalPath it degrades to ✅/🧪/👀/🔨/❔/⛔, where ❔ means
"unblocked, proposal state unknown" — the run has no proposal information, so
it must not claim ▶️.
"Done for planning" (i.e. a blocker that no longer blocks) = status category
done (Done, Cancelled) or status name Test / Review / Documentation.
In -Source Proposals the glyph comes from the proposal stage folder:
completed/ = done, active/ = in progress, next/ = live proposal,
abandoned/ = 💡. The name-based 🧪/👀 never appear there, because the
'**Stav:**' header field is free text.
```

- [ ] **Step 6: Spusť test a ověř, že prochází**

Run: `pwsh -NoProfile -File ums/.claude/skills/mb-epic-graph/tests/status-glyph.tests.ps1`

Expected: PASS — `55 passed`. Počty jsou orientační — pokud se liší o pár assertů (např. jsi jich přidal víc), pokračuj; podstatné je, že žádný neselhal.

- [ ] **Step 7: Ověř stávající testy**

Run:
```bash
pwsh -NoProfile -File ums/.claude/skills/mb-epic-graph/tests/graph-generation.tests.ps1
pwsh -NoProfile -File ums/.claude/skills/mb-epic-graph/tests/e2e.tests.ps1
```
Expected: oba `… passed`. `e2e.tests.ps1` porovnává i tvar výstupu — pokud spadne na legendě, zkontroluj, jestli test nefixuje její přesné znění, a reportuj (legendu upravuje tento task záměrně).

- [ ] **Step 8: Commit**

```bash
git add ums/.claude/skills/mb-epic-graph
git commit -m "UMS: epic-graph — legendy a nápověda popisují celou rodinu ikon

Legenda Jira režimu nese 🧪/👀/❔ a definuje „hotové pro plánování\"; legenda
Proposals režimu doplňuje dosud nezdokumentovaný stav abandoned (💡) a říká,
že 🧪/👀/❔ v tomto režimu nevznikají."
```

---

### Task 8: Dokumentace skillu `SKILL.md`

**Files:**
- Modify: `ums/.claude/skills/mb-epic-graph/SKILL.md:7` (verze)
- Modify: `ums/.claude/skills/mb-epic-graph/SKILL.md:44`–`:52` (krok 1 — snapshot)
- Modify: `ums/.claude/skills/mb-epic-graph/SKILL.md:94` (bullet `-ProposalPath`)
- Modify: `ums/.claude/skills/mb-epic-graph/SKILL.md:123`–`:132` (výčet glyphů)

**Interfaces:**
- Consumes: finální rodinu ikon a definici „hotový pro plánování" z Tasků 4, 5 a 7 — texty musí být s legendou skriptu konzistentní.
- Produces: nic pro kód.

- [ ] **Step 1: Bump verze skillu**

V `SKILL.md` nahraď `  version: "1.3"` za `  version: "1.4"`.

- [ ] **Step 2: Doplň požadavek na `fields` u druhého snapshotu**

V kroku „1. Fetch a snapshot" nahraď větu:

```markdown
Multiple files merge — fetch external blockers reported by the check
(e.g. `key in (UMS-2884, …)`) into a second file when you want them fully
labeled.
```

za:

```markdown
Multiple files merge — fetch external blockers reported by the check
(e.g. `key in (UMS-2884, …)`) into a second file when you want them fully
labeled. The second query MUST use the SAME `fields` list: later files win on
duplicate keys, so a snapshot without `status` silently strips a ticket's
planning state and a ticket in `Test` would start blocking its successors
again.
```

- [ ] **Step 3: Uprav bullet `-ProposalPath`**

Nahraď v bulletu `-ProposalPath` část:

```markdown
  bez `-ProposalPath` glyph degraduje na ✅/🔨/▶️/⛔.
```

za:

```markdown
  bez `-ProposalPath` glyph degraduje na ✅/🧪/👀/🔨/❔/⛔, kde ❔ = odblokováno,
  stav návrhu neznámý (běh o návrzích nic neví, takže netvrdí ▶️).
```

- [ ] **Step 4: Přepiš výčet glyphů v „Use the outputs"**

Nahraď část odstavce:

```markdown
  **status glyph**, then the **stream emoji**. The status glyph merges Jira
  status category, blocker readiness and proposal existence into ONE symbol —
  ✅ done · 🔨 in progress · ▶️ ready to implement (proposal + unblocked) ·
  ⏳ proposal ready but still blocked · 🆕 ready to elaborate (unblocked, no
  proposal) · ⛔ blocked — where "unblocked" = every `Blocks` blocker is done
  (an external/unknown-status blocker counts as blocking; external tickets get
  no glyph). In Proposals mode the glyph comes from the proposal stage
  (`completed/` = ✅, `active/` = 🔨, `next/` = ▶️/⏳ by readiness). It uses a
  symbolic family deliberately distinct from the
  square/circle stream palette; suppress it with `-NoStatus`.
```

za:

```markdown
  **status glyph**, then the **stream emoji**. The status glyph merges Jira
  status (name AND category), blocker readiness and proposal existence into ONE
  symbol — ✅ done · 🧪 in test/review/documentation, counts as done for
  planning · 👀 in design review, waiting for the architect (still blocking) ·
  🔨 in progress · ▶️ ready to implement (proposal + unblocked) · ⏳ proposal
  ready but still blocked · 💡 ready to elaborate (unblocked, no proposal) ·
  ⛔ blocked · ❔ unblocked but the run has no proposal information (no
  `-ProposalPath`) — where "unblocked" = every `Blocks` blocker is DONE FOR
  PLANNING, i.e. status category done (Done, Cancelled) or status name Test /
  Review / Documentation (an external/unknown-status blocker counts as
  blocking; external tickets get no glyph). Design Review deliberately keeps
  blocking: a design under review is not an implementation. In Proposals mode
  the glyph comes from the proposal stage (`completed/` = ✅, `active/` = 🔨,
  `next/` = ▶️/⏳ by readiness, `abandoned/` = 💡) and the name-based 🧪/👀
  never appear, because the `**Stav:**` header field is free text. It uses a
  symbolic family deliberately distinct from the
  square/circle stream palette; suppress it with `-NoStatus`.
```

- [ ] **Step 5: Ověř, že v `ums/` nezůstal starý glyph ani stará verze**

Run:
```bash
pwsh -NoProfile -Command "Select-String -Path ums/.claude/skills/mb-epic-graph/SKILL.md -Pattern 'version: \"1.4\"', '🧪', '👀', '❔', '💡' | Select-Object -ExpandProperty Line"
pwsh -NoProfile -Command "Select-String -Path ums/.claude/skills/**/*.md, ums/.claude/skills/**/*.ps1 -Pattern '🆕' -List"
```
Expected: první příkaz vypíše řádky s verzí 1.4 a všemi novými ikonami; druhý příkaz nevypíše nic (žádný výskyt 🆕 v `ums/`).

- [ ] **Step 6: Spusť celou testovací sadu**

Run:
```bash
pwsh -NoProfile -File ums/.claude/skills/mb-epic-graph/tests/status-glyph.tests.ps1
pwsh -NoProfile -File ums/.claude/skills/mb-epic-graph/tests/graph-generation.tests.ps1
pwsh -NoProfile -File ums/.claude/skills/mb-epic-graph/tests/e2e.tests.ps1
pwsh -NoProfile -File ums/.claude/skills/mb-epic-graph/tests/oracle-prose.tests.ps1
pwsh -NoProfile -File ums/.claude/skills/mb-epic-graph/tests/oracle-structural.tests.ps1
```
Expected: všech pět souborů `… passed`, exit 0.

- [ ] **Step 7: Commit**

```bash
git add ums/.claude/skills/mb-epic-graph/SKILL.md
git commit -m "UMS: mb-epic-graph SKILL.md — nová rodina ikon a verze 1.4

Doplněna definice „done for planning\" (Done, Cancelled, Test, Review,
Documentation), ikony 🧪/👀/❔/💡, poznámka že Design Review dál blokuje,
chování v Proposals režimu a požadavek na identický seznam fields u druhého
(externals) snapshotu."
```

---

### Task 9: Závěrečné ověření proti návrhu

**Files:**
- Modify: žádný (pouze kontrola; případné nálezy se řeší reportem, ne tichou opravou)

**Interfaces:**
- Consumes: výsledný stav skriptu, testů a `SKILL.md`.
- Produces: report pro uživatele.

- [ ] **Step 1: Porovnej implementaci s rozhodovací maticí**

Otevři `ums/docs/design_epic_graph_test_jako_hotovo.md`, sekci „Rozhodovací matice (normativní)", a projdi kaskádu v `Get-StatusGlyph` řádek po řádku. Pro každý řádek matice ověř, že existuje assert v `status-glyph.tests.ps1`. Chybějící kombinaci reportuj, nedoplňuj kód.

- [ ] **Step 2: Ověř, že fixture odpovídá tabulce v návrhu**

Zkontroluj, že `fixtures/jira/status.json` obsahuje všech 17 tiketů z tabulky návrhu (`DEMO-1`…`DEMO-17`) se stavy a kategoriemi dle sloupců „`status.name`" a „kategorie".

- [ ] **Step 3: Vypiš skutečnou tabulku vln pro kontrolu očima**

Run:
```bash
pwsh -NoProfile -File ums/.claude/skills/mb-epic-graph/scripts/epic-graph.ps1 -Source Jira -InputFile ums/.claude/skills/mb-epic-graph/tests/fixtures/jira/status.json -EpicKey DEMO-0 -ProposalPath ums/.claude/skills/mb-epic-graph/tests/fixtures/status_proposals
```
Expected: tabulka vln, v níž `DEMO-1` nese 🧪, `DEMO-2` ▶️, `DEMO-3` 🔨, `DEMO-4` ⏳, `DEMO-5` ✅, `DEMO-6` 💡, `DEMO-13` 👀, `DEMO-14` ⛔. Výstup přilož do reportu uživateli.

- [ ] **Step 4: Ověř čistotu větve**

Run: `git status --short`
Expected: žádné neočekávané změny mimo `ums/` (soubory `CLAUDE.md`, `CLAUDE.md.bak`, `.agents/` jsou artefakty nasazení mimo scope — nezahrnuj je do commitů).

- [ ] **Step 5: Reportuj uživateli**

Shrnutí česky: co se změnilo, kolik assertů běží, výstup tabulky vln ze Stepu 3 a upozornění, že stav „Design Review" není zapojený do UMS workflow (krok 5 kaskády je do té doby mrtvý kód a `mb-architect-review` request fail-closed spadne). Poté nabídni `finishing-a-development-branch`.
