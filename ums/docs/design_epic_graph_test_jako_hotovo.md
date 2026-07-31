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

Přidruženě: 🆕 se v tabulce vln plete s ▶️, proto ho nahrazuje 💡.

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
neobsahují (mají jen `status.name`) a stavové glyphy dosud nepokrývá žádný test.

## Scope

**Zahrnuto:** `ums/.claude/skills/mb-epic-graph/scripts/epic-graph.ps1`
(logika + nápověda + legenda), `ums/.claude/skills/mb-epic-graph/SKILL.md`,
`ums/.claude/skills/mb-epic-graph/tests/` (dvě nové fixtures + testy),
`ums/.claude/skills/mb-epic-elaboration/protocol.md` (jedna věta o readiness).

**Nezahrnuto a proč:**

- `mb-state` — čte pouze lokální MB workflow (pin, pár design+plán, SDD ledger),
  Jira stavy nesahá.
- `mb-jira-update` — stav „Test" jen *nastavuje* při finalizaci, nikdy
  nevyhodnocuje.
- `mb-epic-elaboration` ledger a jeho `ledger-status.ps1` — stav `hotov` je
  *rozpracovanost* tiketu (všechny položky `uzavřená`, nic dirty), nikoli
  implementační stav; readiness si protokol bere z `mb-epic-graph`. Mění se tam
  jen jedna dokumentační věta.
- Mermaid label — už dnes vypisuje jméno stavu verbatim, tedy „Test".
- `UMS_MEMORY_BANK_CONTRACT.md` a `CLAUDE.md.sample` — nejde o kontraktní
  chování MB vrstvy.

## Technický návrh

### 1. Rozpoznání stavu

Pevná konstanta v `epic-graph.ps1` (bez parametru CLI):

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
leží v `$TestStatusNames`; pro klíč mimo `$issues` (externí tiket) vrací
`$false`, tedy stejně konzervativně jako dnešní kód. Normalizace názvu:
`Trim()` + `Remove-Diacritics` (helper už ve skriptu je) +
`ToLowerInvariant()` — match je case-insensitive a nezávislý na diakritice.

### 2. Odblokování následníků

`Test-Unblocked` nahradí přímý test `StatusCat -eq 'done'` voláním
`Test-DoneForPlanning`. Ostatní semantika zůstává: blokátor s neznámým stavem
(externí, mimo snapshot) se konzervativně počítá jako blokující.

### 3. Stavová ikona a rodina glyphů

Do kaskády `Get-StatusGlyph` přijde nový stupeň **hned za ✅ a před 🔨** — jinak
by ho přebilo jak `indeterminate`, tak `$proposalActive`:

```text
StatusCat = done              → ✅
název ∈ $TestStatusNames      → 🧪     ← nový stupeň
indeterminate / aktivní proposal → 🔨
…zbytek kaskády logicky bez změny (▶️ / ⏳ / 💡 / ⛔)
```

✅ zůstává vyhrazeno pro kategorii `done` (Done, Cancelled). Tiket v Testu tedy
odblokuje své následníky — ti přejdou z ⏳ na ▶️ (mají-li živý proposal), resp.
z ⛔ na 💡 (bez proposalu) — ale sám nese 🧪, takže je na dashboardu
rozeznatelný od uzavřené práce.

Zároveň se stav „k rozpracování (odblokováno, bez návrhu)" přeznačuje z 🆕 na
**💡**: 🆕 se v běžných terminálových fontech renderuje jako podobně velký
tmavý blok jako ▶️ a v tabulce vln se s ním plete. 💡 sedne i sémanticky
(chybí návrh, tiket čeká na rozmyšlení) a nepere se ani s ▶️, ani s ⏳ či 🧪.
Chování se nemění, jde o čistou výměnu symbolu.

Výsledná rodina (Jira režim, plný — tj. s `-ProposalPath`):

```text
✅ hotovo
🧪 v testu (počítá se jako hotový)
🔨 implementuje se
▶️ připraveno k implementaci (návrh hotov, odblokováno)
⏳ návrh hotov, čeká na blokátory
💡 k rozpracování (odblokováno, bez návrhu)
⛔ blokováno
```

Bez `-ProposalPath` zůstává degradace na podmnožinu — nově ✅/🧪/🔨/▶️/⛔
(💡 a ⏳ vyžadují informaci o proposalech).

Režim `-Source Proposals` se nemění: uzly jsou proposaly a `StatusCat` tam
vzniká ze stage složky (`completed` → `done`, `active` → `indeterminate`,
jinak `new`), takže 🧪 v tomto režimu nikdy nevznikne; 🆕 se v jeho legendě
nevyskytuje už dnes (proposal uzly stav „bez návrhu" nemají). Obojí
zdokumentovat explicitně.

### 4. Místa k úpravě (legendy a nápověda)

Doplnit 🧪 a přepsat 🆕 → 💡 přesně zde:

| soubor | místo | úprava |
|---|---|---|
| `epic-graph.ps1` | `.PARAMETER NoStatus` (výčet glyphů i degradovaná varianta) | + 🧪, 🆕 → 💡 |
| `epic-graph.ps1` | kaskáda `Get-StatusGlyph` | + stupeň 🧪, 🆕 → 💡 |
| `epic-graph.ps1` | legenda tabulky vln, Jira režim (`**První ikona = stav tiketu**`) | + 🧪, 🆕 → 💡 |
| `SKILL.md` | bullet `-ProposalPath` (degradovaný výčet `✅/🔨/▶️/⛔`) | + 🧪 |
| `SKILL.md` | výčet glyphů v „Use the outputs" | + 🧪, 🆕 → 💡 |

Beze změny zůstávají: legenda pro Proposals režim
(`**První ikona = stav proposalu**`) a popis Proposals režimu v `SKILL.md`
(`completed/` = ✅, `active/` = 🔨, `next/` = ▶️/⏳) — jen se u nich doplní
poznámka, že 🧪 se v tomto režimu nevyskytuje. `.SYNOPSIS`/`.DESCRIPTION`
žádný výčet glyphů nenesou, takže se nemění.

Jiné výskyty 🆕 v `ums/` neexistují.

### 5. Testy

Nová fixture `tests/fixtures/jira/status.json` — existující `snap.json`
zůstává nedotčený (visí na něm současné testy a `statusCategory` neobsahuje).
Nese epic, tři blokující páry pokrývající všechny tři kategorie stavů a jeden
samostatný tiket;
klíče v tabulce jsou zástupné, ve fixture ponesou konzistentní projektový
prefix. Druhá nová fixture `tests/fixtures/status_proposals/next/` obsahuje dva
design drafty s hlavičkou `**Jira:**` mířící na tikety B a D — díky nim jde
v jednom běhu pokrýt celá rodina glyphů:

| tiket | stav | blokuje | návrh | bez `-ProposalPath` | s `-ProposalPath` |
|---|---|---|---|---|---|
| A | Test | B | — | 🧪 | 🧪 |
| B | To Do | — | ano | ▶️ | ▶️ (návrh + odblokováno) |
| C | In Progress | D | — | 🔨 | 🔨 |
| D | To Do | — | ano | ⛔ | ⏳ (návrh, ale blokován) |
| E | Done | F | — | ✅ | ✅ |
| F | To Do | — | — | ▶️ | 💡 (odblokováno, bez návrhu) |
| G | test | — | — | 🧪 | 🧪 |

Testy v `tests/e2e.tests.ps1`:

1. Běh bez `-ProposalPath` — glyphy a odblokování dle pátého sloupce; jádro
   změny (B a F přešly z ⛔ na ▶️ tím, že jejich blokátory jsou Test / Done).
2. Běh s `-ProposalPath` — glyphy dle šestého sloupce; pokrývá celou rodinu
   včetně 💡 (nikoli 🆕, tedy pojistka proti návratu starého glyphu při
   budoucím revendoringu) a přechodu D → ⏳ vs. B → ▶️.
3. Tiket G (stav `test` malými písmeny) nese 🧪 a „In Progress" zůstává 🔨 —
   match je case-insensitive a nezobecnil se na celou kategorii
   `indeterminate`.
4. `-NoStatus` potlačí i 🧪.

### 6. Dokumentace rozpracování epiku

`mb-epic-elaboration/protocol.md` — jedna věta u výběru okna: tiket ve stavu
„Test" se počítá jako hotový, takže okno lze naplánovat i na tiket, jehož
jediný blokátor sedí v testu.

## Dopady

- Tabulka vln v popisu epiku: tikety za tiketem v Testu se posunou z ⛔ na 💡,
  resp. z ⏳ na ▶️. Sloupce (vlny) se **nemění** — vlny počítá topologie
  `Blocks`, ne stavy.
- Uložené `graph.md` v `memory-bank/epics/<epic>/` se při nejbližší regeneraci
  diffnou o změněné glyphy (včetně všech dosavadních 🆕 → 💡) — očekávané.
- Konzistenční oracle (`-Check`) se nemění; exit kódy zůstávají.

## Rizika

- **Tiket vrácený z testu** (Test → In Progress / To Do) odblokování zase
  odebere a následník se vrátí na ⛔, resp. ⏳. Akceptováno: graf se vždy generuje
  z aktuálního snapshotu, žádný stav si nepamatuje.
- **Přejmenování stavu v Jiře** rozbije match podle názvu potichu (tiket by se
  začal chovat jako In Progress). Zmírnění: konstanta je na jednom místě
  s komentářem, který uvádí i `id 10205`.
- Riziko rozšíření na celou kategorii `indeterminate` (a tedy odblokování už
  při započetí práce) hlídá test č. 3.
