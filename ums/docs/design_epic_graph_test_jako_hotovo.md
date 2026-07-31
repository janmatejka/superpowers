# Návrh: Tiket ve stavu „Test" se v grafu epiku počítá jako hotový

- **Jira:** (žádný tiket)
- **Target MB:** — (fork superpowers nemá Memory Bank; dokument žije v `ums/docs/`)
- **Plán:** [plan_epic_graph_test_jako_hotovo.md](plan_epic_graph_test_jako_hotovo.md) (vznikne ve writing-plans)
- **Vytvořeno:** 2026-07-31

## Cíl

Tiket, který je v Jiře ve stavu **Test**, má v plánovacích výstupech skillu
`mb-epic-graph` platit za hotový — **neblokuje** své následníky, takže je lze
plánovat a implementovat, zatímco předchůdce ještě sedí v testu. Zároveň má
zůstat na dashboardu odlišitelný od skutečně uzavřené práce.

## Zjištěný stav (ověřeno proti živé Jiře)

Dotaz `project = UMS ORDER BY updated DESC` (100 tiketů, Atlassian MCP,
2026-07-31) dává tyto stavy workflow:

| stav | id | `statusCategory` |
|---|---|---|
| **Test** | 10205 | `indeterminate` (In Progress) |
| Done | 10204 | `done` |
| Cancelled | 10700 | `done` |
| In Progress | 3 | `indeterminate` |
| Backlog | 10202 | `new` |
| To Do | 10300 | `new` |

Zásadní důsledek: **„Test" leží ve stejné kategorii jako „In Progress"**, takže
podle `statusCategory` je odlišit nelze — match musí jít podle **názvu stavu**.

Dnešní chování `ums/.claude/skills/mb-epic-graph/scripts/epic-graph.ps1`:

- `Test-Unblocked` považuje blokátor za vyřízený jen při `StatusCat -eq 'done'`
  → tiket v Testu své následníky stále blokuje (dostanou ⛔ / ⏳).
- `Get-StatusGlyph` mapuje `indeterminate` na 🔨 → tiket v Testu je v tabulce
  vln nerozeznatelný od rozpracovaného.

Fixtures v `mb-epic-graph/tests/fixtures/jira/` pole `statusCategory` vůbec
neobsahují (mají jen `status.name`), stavové glyphy dosud nemá pokryté žádný
test.

## Scope

**Zahrnuto:** `ums/.claude/skills/mb-epic-graph/scripts/epic-graph.ps1`
(logika + nápověda), `ums/.claude/skills/mb-epic-graph/SKILL.md`,
`ums/.claude/skills/mb-epic-graph/tests/` (nová fixture + testy),
`ums/.claude/skills/mb-epic-elaboration/protocol.md` (jedna věta o readiness).

**Nezahrnuto a proč:**

- `mb-state` — čte pouze lokální MB workflow (pin, pár design+plán, SDD ledger),
  Jira stavy nesahá.
- `mb-jira-update` — stav „Test" jen *nastavuje* při finalizaci, nikdy
  nevyhodnocuje.
- `mb-epic-elaboration` ledger — jeho stav `hotov` je *rozpracovanost* tiketu
  (všechny položky `uzavřená`, nic dirty), nikoli implementační stav; readiness
  si bere z `mb-epic-graph`. Mění se tam jen dokumentační věta.
- Mermaid label — už dnes vypisuje jméno stavu verbatim, tedy „Test".
- `UMS_MEMORY_BANK_CONTRACT.md` a `CLAUDE.md.sample` — nejde o kontraktní
  chování MB vrstvy.

## Technický návrh

### 1. Rozpoznání stavu (`epic-graph.ps1`)

Pevná konstanta ve skriptu (bez parametru CLI):

```powershell
# Stavy, které se pro plánování počítají jako hotové, i když jejich
# statusCategory hotová není. „Test" (id 10205) je v kategorii
# indeterminate stejně jako „In Progress" — rozlišit lze jen názvem.
$script:TestStatusNames = @('Test')
```

Nová funkce vedle `Test-Unblocked`:

```powershell
function Test-DoneForPlanning([string] $key) { ... }
```

Vrací `$true`, když `StatusCat -eq 'done'` **nebo** normalizovaný název stavu
leží v `$TestStatusNames`. Normalizace názvu: `Trim()` +
`Remove-Diacritics` (helper už ve skriptu je) + `ToLowerInvariant()` — match je
tedy case-insensitive a nezávislý na diakritice.

### 2. Odblokování následníků

`Test-Unblocked` nahradí přímý test `StatusCat -eq 'done'` voláním
`Test-DoneForPlanning`. Ostatní semantika zůstává: blokátor s neznámým stavem
(externí, mimo snapshot) se konzervativně počítá jako blokující.

### 3. Stavová ikona

Do kaskády `Get-StatusGlyph` přijde nový stupeň **hned za ✅ a před 🔨** — jinak
by ho přebilo jak `indeterminate`, tak `$proposalActive`:

```
done              → ✅
název ∈ Test      → 🧪     ← nový stupeň
indeterminate / aktivní proposal → 🔨
…zbytek kaskády bez změny (▶️ / ⏳ / 🆕 / ⛔)
```

✅ zůstává vyhrazeno pro kategorii `done` (Done, Cancelled). Tiket v Testu tedy
odblokuje následníky (dostanou ▶️ místo ⛔), ale sám nese 🧪, takže je na
dashboardu rozeznatelný od uzavřené práce.

Režim `-Source Proposals` se nemění: uzly jsou proposaly a `StatusCat` tam
vzniká ze stage složky (`completed` → `done`, `active` → `indeterminate`,
jinak `new`), takže 🧪 v tomto režimu nikdy nevznikne. Zdokumentovat explicitně.

### 4. Legendy a nápověda

Doplnit „🧪 v testu (počítá se jako hotový)" do:

- legendy tabulky vln pro Jira režim (`**První ikona = stav tiketu**`),
- `.PARAMETER NoStatus` v hlavičce skriptu a `.SYNOPSIS`/`.DESCRIPTION` tam,
  kde se glyphy vypisují,
- popisu glyphů v `mb-epic-graph/SKILL.md` (sekce „Use the outputs" a
  `-NoStatus`).

Legenda pro Proposals režim (`**První ikona = stav proposalu**`) zůstává bez 🧪.

### 5. Testy

Nová fixture `tests/fixtures/jira/status.json` — existující `snap.json`
zůstává nedotčený (visí na něm současné testy a `statusCategory` neobsahuje).
Fixture má epic a tři blokující páry se všemi relevantními kategoriemi (klíče
v tabulce jsou zástupné, ve fixture ponesou konzistentní projektový prefix):

| tiket | stav | blokuje | očekávaný glyph |
|---|---|---|---|
| A | Test | B | 🧪 |
| B | To Do | — | ▶️ (odblokován) |
| C | In Progress | D | 🔨 |
| D | To Do | — | ⛔ (stále blokován) |
| E | Done | F | ✅ |
| F | To Do | — | ▶️ |

Testy v `tests/e2e.tests.ps1` (běží bez `-ProposalPath`, tedy v degradovaném
4-stavovém režimu doplněném o 🧪):

1. Glyphy a odblokování dle tabulky výše — pokrývá jádro změny.
2. Match na názvu je case-insensitive (varianta `test` v fixture nebo druhá
   drobná fixture) a „In Progress" zůstává 🔨 — pojistka, že se nezobecnilo
   na celou kategorii `indeterminate`.
3. `-NoStatus` potlačí i 🧪.

### 6. Dokumentace rozpracování epiku

`mb-epic-elaboration/protocol.md` — jedna věta u readiness/window selection:
tiket ve stavu „Test" se počítá jako hotový, takže okno lze naplánovat i na
tiket, jehož jediný blokátor sedí v testu.

## Dopady

- Tabulka vln v popisu epiku: tikety za tiketem v Testu se posunou z ⛔/⏳ na
  ▶️/🆕. Sloupce (vlny) se **nemění** — vlny počítá topologie `Blocks`, ne
  stavy.
- Konzistenční oracle (`-Check`) se nemění; exit kódy zůstávají.
- `graph.md` v `memory-bank/epics/<epic>/` se při nejbližší regeneraci
  diffne o změněné glyphy — očekávané.

## Rizika

- **Tiket vrácený z testu** (Test → In Progress / To Do) odblokování zase
  odebere a následník se vrátí na ⛔. Akceptováno: graf se vždy generuje
  z aktuálního snapshotu, žádný stav si nepamatuje.
- **Přejmenování stavu v Jiře** rozbije match podle názvu potichu (tiket by se
  začal chovat jako In Progress). Zmírnění: konstanta je na jednom místě
  s komentářem, který uvádí i `id 10205`.
- Riziko rozšíření na celou kategorii `indeterminate` (a tedy odblokování už
  při započetí práce) hlídá test č. 2.
