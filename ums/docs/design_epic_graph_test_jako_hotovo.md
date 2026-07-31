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

## Zjištěný stav (ověřeno proti živé Jiře a proti kódu)

Dotaz `project = UMS ORDER BY updated DESC` (100 tiketů, Atlassian MCP,
2026-07-31) dává tyto stavy workflow:

| stav | id | `statusCategory.key` |
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

- `Test-Unblocked` (`:644`) považuje blokátor za vyřízený jen při
  `StatusCat -eq 'done'` (`:651`) → tiket v Testu své následníky stále blokuje
  (dostanou ⛔ / ⏳). Je to **jediné** místo, kde se hotovost vyhodnocuje;
  jediný konzument je `Get-StatusGlyph` (`:666`).
- `Get-StatusGlyph` mapuje `indeterminate` na 🔨 (`:664`) → tiket v Testu je
  v tabulce vln nerozeznatelný od rozpracovaného.
- **Název stavu je dnes nechráněný:** `:241` čte `[string]$statusObj.name` bez
  testu `PSObject.Properties['name']`, zatímco `statusCategory` na `:242`
  chráněné je. Pod `Set-StrictMode -Version Latest` (`:105`) a
  `$ErrorActionPreference = 'Stop'` (`:106`) tedy snapshot s `"status": {}`
  skript **shodí** (exit 1). Dnes je to latentní kosmetická vada (jméno stavu
  se používá jen v Mermaid labelu `:499` a v odsazeném seznamu `:539`); tato
  změna z názvu dělá plánovací vstup, takže oprava patří do scope.
- **V režimu `-Source Proposals` je `Status` volnotextové pole:** `:274` plní
  `Status` z hlavičky `**Stav:**` proposalu (`:299`), a ta není nikde
  enumerovaná — reálné hodnoty jsou „návrh"
  (`tests/fixtures/basic/proposal_alfa.md:4`), „rozpracováno"
  (`proposal_gama.md:4`) a stejně legitimně by tam mohlo stát „Test".
  Match podle názvu proto **musí** být omezen na režim Jira, jinak by tichou
  změnou semantiky odblokovával i JIRA-less grafy.
- Vlny, pořadí řádků ani stream-emoji na stavech nezávisí (`Resolve-Wave`
  `:577`, `Get-RootAncestors` `:599`, řádky `:692`, emoji `:612` čtou výhradně
  `$blockedBy`/`$blocksOut`). Konzistenční oracle (`:744`–`:892`) stav nečte
  vůbec a `$script:ExitCode` se plní jen z počtu `CHYBA` (`:891`).

Testovací stav: Jira-mode testy žijí v `tests/graph-generation.tests.ps1`
(`:21`–`:51`), `tests/e2e.tests.ps1` je Proposals-only smoke test. Stavové
glyphy má pokryté právě jeden assert — `graph-generation.tests.ps1:19`
(`▶️` pro živý `next/` proposal bez blokátorů). Fixtures v `fixtures/jira/`
(`snap.json`, `afterwindow.json`) pole `statusCategory` neobsahují vůbec, mají
jen `status.name`. `_assert.ps1:18` končí funkcí `Complete-Tests`, která volá
`exit`, takže cokoli za jejím voláním je mrtvý kód. Runner v repu není —
každý soubor `*.tests.ps1` se spouští samostatně.

## Scope

**Zahrnuto:** `ums/.claude/skills/mb-epic-graph/scripts/epic-graph.ps1`
(logika, ochrana `status.name`, nápověda, legenda),
`ums/.claude/skills/mb-epic-graph/SKILL.md` (glyphy, požadavek na `fields`
u druhého snapshotu, bump `metadata.version` 1.3 → 1.4),
`ums/.claude/skills/mb-epic-graph/tests/` (nový `status-glyph.tests.ps1` + tři
nové fixtures).

**Nezahrnuto a proč:**

- **`Cancelled` odblokovává následníky** stejně jako `Done` (kategorie `done`,
  `:651`). Zůstává tak, záměrně: zrušený tiket už nikdo nedokončí, takže čekat
  na něj nemá smysl. Uvedeno explicitně, aby to nevypadalo jako přehlédnutí.
- **`mb-epic-elaboration` se nemění.** Výběr okna (`protocol.md:32`–`:52`) je
  definovaný jako *dirty-first → leverage* a na hotovosti blokátorů nezávisí —
  `protocol.md:41`–`:43` naopak výslovně říká, že kontraktní rozhodnutí si
  drží leverage i když je jeho implementace blokovaná. Vysvětlení 🧪 jde jen do
  `mb-epic-graph/SKILL.md`. Jeho `ledger-status.ps1` pracuje výhradně
  s tabulkami `ledger.md`; stav `hotov` je *rozpracovanost* tiketu, ne
  implementační stav.
- `mb-state` — čte pouze lokální MB workflow (pin, pár design+plán, SDD
  ledger), Jira stavy nesahá.
- `mb-jira-update` — stav „Test" jen *nastavuje* při finalizaci, nikdy
  nevyhodnocuje.
- Mermaid label (`:499`) a odsazený seznam (`:539`) — už dnes vypisují jméno
  stavu verbatim, tedy „Test".
- `UMS_MEMORY_BANK_CONTRACT.md` a `CLAUDE.md.sample` — nejde o kontraktní
  chování MB vrstvy.
- **Přenos do monorepa** `d:\_datasys\ums` přes `sync-with-monorepo.ps1` —
  provede se následně, mimo tuto větev (stejný postup jako u UMS-3361).

Grep celého `ums/` potvrzuje, že žádný další konzument hotovosti Jira stavu
v repu neexistuje.

## Technický návrh

### 1. Rozpoznání stavu

Pevná konstanta v `epic-graph.ps1` (bez parametru CLI), uložená **už
normalizovaně**:

```powershell
# Stavy, které se pro plánování počítají jako hotové, i když jejich
# statusCategory hotová není. „Test" (id 10205) je v kategorii
# indeterminate stejně jako „In Progress" — rozlišit lze jen názvem.
# Hodnoty jsou normalizované (lowercase, bez diakritiky); porovnávej
# operátorem -contains, NIKOLI metodou .Contains() (ta je ordinal
# case-sensitive).
$script:DoneForPlanningStatusNames = @('test')
```

Nová funkce vedle `Test-Unblocked`:

```powershell
function Test-DoneForPlanning([string] $key) { ... }
```

Kontrakt funkce:

1. Klíč mimo `$issues` (externí tiket) → `$false` (stejně konzervativně jako
   dnešní kód na `:651`).
2. `StatusCat -eq 'done'` → `$true`.
3. Jen v režimu **Jira**: normalizovaný název stavu v
   `$script:DoneForPlanningStatusNames` → `$true`. V režimu `Proposals` se
   tento krok přeskočí — pole `**Stav:**` je volnotextové (viz Zjištěný stav).
   Uvnitř funkce se na režim odkazuj přes `$script:Source`, ne `$Source`
   (parametr není v scope funkce; stejná past, jakou kód dokumentuje na
   `:448`–`:451`).
4. Jinak `$false`.

Normalizace názvu: `Trim()` + `Remove-Diacritics` (helper už ve skriptu je) +
`ToLowerInvariant()`.

Zároveň se opraví `:241` na tvar chráněný stejně jako `:242`:

```powershell
Status = if ($statusObj -and $statusObj.PSObject.Properties['name']) { [string]$statusObj.name } else { '' }
```

### 2. Odblokování následníků

`Test-Unblocked` nahradí přímý test `StatusCat -eq 'done'` (`:651`) voláním
`Test-DoneForPlanning`. Ostatní semantika zůstává: blokátor s neznámým stavem
(externí, mimo snapshot) se konzervativně počítá jako blokující.

### 3. Stavová ikona a rodina glyphů

Do kaskády `Get-StatusGlyph` přijde nový stupeň **hned za ✅ (`:663`) a před 🔨
(`:664`)** — jinak by ho přebilo jak `indeterminate`, tak `$proposalActive`:

```text
StatusCat = done                          → ✅
Jira režim & název ∈ konstantě            → 🧪     ← nový stupeň
indeterminate / aktivní proposal          → 🔨
…zbytek kaskády logicky bez změny (▶️ / ⏳ / 💡 / ⛔)
```

✅ zůstává vyhrazeno pro kategorii `done` (Done, Cancelled). Tiket v Testu tedy
odblokuje své následníky — ti přejdou z ⏳ na ▶️ (mají-li živý proposal), resp.
z ⛔ na 💡 (bez proposalu; v degradovaném režimu z ⛔ na ▶️) — ale sám nese 🧪,
takže je na dashboardu rozeznatelný od uzavřené práce.

Kaskáda se vrací ještě před `Test-Unblocked`, takže tiket v Testu nese 🧪
i tehdy, když je sám blokovaný nehotovým předchůdcem. Je to stejné chování jako
dnes u kategorie `done` a je záměrné — glyph popisuje fázi tiketu, ne jeho
blokátory.

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

Režim `-Source Proposals` se nemění: uzly jsou proposaly, `StatusCat` vzniká ze
stage složky (`completed` → `done`, `active` → `indeterminate`, jinak `new`;
`:293`–`:297`) a name-match je v tomto režimu vypnutý, takže 🧪 nikdy
nevznikne. 🆕 se v jeho legendě nevyskytuje už dnes (proposal uzly stav „bez
návrhu" nemají). Obojí zdokumentovat explicitně.

### 4. Místa k úpravě (legendy, nápověda, dokumentace)

| soubor | místo | úprava |
|---|---|---|
| `epic-graph.ps1` | `:241` | ochrana `status.name` přes `PSObject.Properties` |
| `epic-graph.ps1` | `:651` (`Test-Unblocked`) | volání `Test-DoneForPlanning` |
| `epic-graph.ps1` | `:663`–`:674` (kaskáda) | + stupeň 🧪, 🆕 → 💡 |
| `epic-graph.ps1` | `:60`–`:70` (`.PARAMETER NoStatus`) | + 🧪, 🆕 → 💡, u popisu Proposals režimu poznámka, že 🧪 tam nevzniká |
| `epic-graph.ps1` | `:929` (legenda tabulky vln, Jira režim) | + 🧪, 🆕 → 💡 |
| `SKILL.md` | `:94` (bullet `-ProposalPath`, degradovaný výčet `✅/🔨/▶️/⛔`) | + 🧪 |
| `SKILL.md` | `:125`–`:126` (výčet glyphů v „Use the outputs") | + 🧪 (včetně věty, že Test se počítá jako hotový a v Proposals režimu nevzniká), 🆕 → 💡 |
| `SKILL.md` | krok 1 (fetch snapshot, `:44`–`:52`) | druhý (externals) dotaz MUSÍ mít identický seznam `fields` — jinak tiket v Testu ztratí `status` a začne znovu blokovat |
| `SKILL.md` | `:7` (`metadata.version`) | 1.3 → 1.4 |

Beze změny zůstává legenda pro Proposals režim
(`**První ikona = stav proposalu**`, `:927`) a popis Proposals režimu
v `SKILL.md` (`:130`, `completed/` = ✅, `active/` = 🔨, `next/` = ▶️/⏳).
`.SYNOPSIS`/`.DESCRIPTION` žádný výčet glyphů nenesou. Jiné výskyty 🆕
v `ums/` neexistují.

### 5. Testy

Nový soubor `tests/status-glyph.tests.ps1` (Jira-mode glyph testy). **Ne**
`e2e.tests.ps1` — ten je Proposals-only a končí `Complete-Tests`, za nímž je
mrtvý kód. Spouští se samostatně:
`pwsh -NoProfile -File ums/.claude/skills/mb-epic-graph/tests/status-glyph.tests.ps1`.

Tři nové fixtures; existující `snap.json` a `afterwindow.json` zůstávají
nedotčené (visí na nich současné testy):

**a) `fixtures/jira/status.json`** — epic + 10 tiketů. Klíče MUSÍ být uppercase
(`DEMO-…`), atribuce proposalu na `:374` vyžaduje `[A-Z][A-Z0-9]+-\d+`. Každý
řádek nese `status.name` **i** `status.statusCategory.key` (bez kategorie by
`StatusCat` zůstal `''` a testy by měřily něco jiného) — s jednou úmyslnou
výjimkou u DEMO-10:

| tiket | `status.name` | kategorie | blokován | návrh | bez `-ProposalPath` | s `-ProposalPath` |
|---|---|---|---|---|---|---|
| DEMO-1 | Test | indeterminate | — | — | 🧪 | 🧪 |
| DEMO-2 | To Do | new | DEMO-1 | `next/` | ▶️ | ▶️ |
| DEMO-3 | In Progress | indeterminate | — | — | 🔨 | 🔨 |
| DEMO-4 | To Do | new | DEMO-3 | `next/` | ⛔ | ⏳ |
| DEMO-5 | Done | done | — | — | ✅ | ✅ |
| DEMO-6 | To Do | new | DEMO-5 | — | ▶️ | 💡 |
| DEMO-7 | test | indeterminate | — | — | 🧪 | 🧪 |
| DEMO-8 | Test | indeterminate | — | `active/` | 🧪 | 🧪 |
| DEMO-9 | To Do | new | DEMO-99 (externí) | — | ⛔ | ⛔ |
| DEMO-10 | `"status": {}` | — | — | — | ▶️ | 💡 |

**b) `fixtures/status_proposals/`** — `next/design_demo_2.md`,
`next/design_demo_4.md`, `active/design_demo_8.md`, každý s hlavičkou
`**Jira:** DEMO-<n>`.

**c) `fixtures/status_stav/next/`** — dva proposaly pro JIRA-less kontrolu:
`design_alfa.md` s hlavičkou `**Stav:** Test` a `Blokuje:` odkazem na
`design_beta.md`, a `design_beta.md`.

Testy (všechny běhy **bez** `-Check`, aby asserty na ✅ nekolidovaly
s hláškou oracle „✅ Žádný nesoulad nenalezen" `:956`; očekávaný exit code 0):

1. **Jira režim bez `-ProposalPath`** — glyph každého tiketu dle šestého
   sloupce. Jádro změny je DEMO-2 (blokátor v Testu, dřív ⛔). DEMO-6 je
   kontrolní řádek — blokátor v `Done` odblokovával už dnes.
2. **Jira režim s `-ProposalPath fixtures/status_proposals`** — glyph dle
   sedmého sloupce. Pokrývá celou rodinu včetně 💡 (nikoli 🆕 — pojistka proti
   návratu starého glyphu při revendoringu) a rozdílu DEMO-4 (⏳) vs DEMO-2
   (▶️), tedy přechodu, který je hlavním dopadem změny.
3. **DEMO-8 nese 🧪, ne 🔨** — dokazuje, že nový stupeň kaskády předbíhá
   `$proposalActive` (`:664`).
4. **DEMO-7 (`test` malými písmeny) nese 🧪 a DEMO-3 („In Progress") zůstává
   🔨** — match je case-insensitive a nezobecnil se na celou kategorii
   `indeterminate`.
5. **DEMO-9 zůstává ⛔** — externí blokátor mimo snapshot se počítá jako
   blokující.
6. **DEMO-10 (`"status": {}`) skript nezhodí** — exit 0 a glyph z To-Do větve
   (▶️, resp. 💡).
7. **`-NoStatus` potlačí i 🧪** (`Assert-NotMatch '🧪'`).
8. **Vlny se nemění** — DEMO-1 ve vlně 0, DEMO-2 ve vlně 1 (assert na pozici
   buňky), stejně pro oba běhy.
9. **Proposals režim (`-Source Proposals -ProposalPath fixtures/status_stav`)
   — `**Stav:** Test` NEDÁ 🧪**: `design_alfa.md` nese ▶️ (živý `next/`,
   odblokován) a `design_beta.md` zůstává ⏳ (blokován alfou). Assert
   `Assert-NotMatch '🧪'`.

Asserty MUSÍ být per-tiket, ne jen na výskyt glyphu ve výstupu: harness umí
`Assert-Match`/`Assert-NotMatch` nad celým reportem (`_assert.ps1:9`–`:14`),
takže `Assert-Match $out '🧪'` by prošel i tehdy, když 🧪 dostane špatný tiket.
Buňka má deterministický tvar `"$statusGlyph $(Get-Emoji $k) $keyMd $sum"`
(`:683`–`:684`), takže vzor typu `🧪 \S+ \[DEMO-1\]` je vyjádřitelný.

Nové fixtures nemohou rozbít existující testy — všechny stávající běhy
předávají explicitní cestu k fixture, nikdy `fixtures/` root.

## Dopady

- Tabulka vln v popisu epiku: tikety za tiketem v Testu se posunou z ⛔ na 💡
  (v degradovaném režimu na ▶️), resp. z ⏳ na ▶️. Sloupce (vlny) se
  **nemění** — vlny počítá topologie `Blocks`, ne stavy.
- Uložené `graph.md` v `memory-bank/epics/<epic>/` se při nejbližší regeneraci
  diffnou o změněné glyphy (včetně všech dosavadních 🆕 → 💡) — očekávané.
- Konzistenční oracle (`-Check`) se nemění; exit kódy zůstávají.
- Snapshot s prázdným nebo chybějícím `status` přestane skript shazovat.

## Rizika

- **Tiket vrácený z testu** (Test → In Progress / To Do) odblokování zase
  odebere a následník se vrátí na ⛔, resp. ⏳. Akceptováno: graf se vždy
  generuje z aktuálního snapshotu, žádný stav si nepamatuje.
- **Přejmenování stavu v Jiře** rozbije match podle názvu potichu (tiket by se
  začal chovat jako In Progress). Zmírnění: konstanta je na jednom místě
  s komentářem, který uvádí i `id 10205`.
- **Neúplný druhý snapshot** (fetch externích blokátorů bez `status` ve
  `fields`) tiket v Testu degraduje na blokující. Zmírnění: požadavek
  v `SKILL.md` kroku 1.
- Riziko rozšíření na celou kategorii `indeterminate` (a tedy odblokování už
  při započetí práce) hlídá test č. 4; riziko prosáknutí do JIRA-less režimu
  test č. 9.
