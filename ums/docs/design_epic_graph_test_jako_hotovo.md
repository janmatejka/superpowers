# Návrh: Rozhodovací stavové ikony v grafu epiku

- **Jira:** (žádný tiket)
- **Target MB:** — (fork superpowers nemá Memory Bank; dokument žije v `ums/docs/`)
- **Plán:** [plan_epic_graph_test_jako_hotovo.md](plan_epic_graph_test_jako_hotovo.md) (vznikne ve writing-plans)
- **Vytvořeno:** 2026-07-31

## Cíl

Stavová ikona v tabulce vln skillu `mb-epic-graph` je rozhodovací nástroj pro
otázku **„na kterém tiketu začít pracovat"**. Aby na tuto otázku odpovídala
pravdivě, potřebuje tři věci:

1. **Tiket, jehož práce je odvedená a dočítává se ocas, nesmí blokovat
   následníky.** Konkrétně stavy `Test`, `Review` a `Documentation` — dnes se
   chovají jako rozpracované, takže dashboard schovává práci, která je
   připravená k započetí.
2. **Ikona nesmí tvrdit víc, než skript ví.** Dnes na odblokovaný `To Do` tiket
   napíše ▶️ („návrh hotov, spusť implementaci") i tehdy, když o návrzích nemá
   žádnou informaci.
3. **Rodina ikon musí být rozlišitelná a úplná.** 🆕 splývá s ▶️; stav
   `Design Review`, kde tiket čeká na architekta, nemá vlastní ikonu vůbec.

## Ověřená fakta

### Workflow v Jiře

`getTransitionsForJiraIssue` na UMS-3361 s `includeUnavailableTransitions`
(Atlassian MCP, 2026-07-31) dává celý stavový prostor:

| stav | id | `statusCategory.key` |
|---|---|---|
| Backlog | 10202 | `new` |
| To Do | 10300 | `new` |
| In Progress | 3 | `indeterminate` |
| Test | 10205 | `indeterminate` |
| Review | 10206 | `indeterminate` |
| Documentation | 11064 | `indeterminate` |
| Done | 10204 | `done` |
| Cancelled | 10700 | `done` |

`Test`, `Review` i `Documentation` leží ve **stejné kategorii jako
`In Progress`** — podle `statusCategory` je odlišit nelze, match musí jít podle
**názvu stavu**.

**`Design Review` v tomto workflow není.** JQL `status = "Design Review"`
proběhne bez chyby (název v instanci existuje), ale nevrací žádný tiket a mezi
přechody UMS-3361 se nevyskytuje. Skript ho podpoří dopředu; zapojení stavu do
workflow je úkol v administraci Jiry.

### Jak graf vyhodnocuje stav dnes

`ums/.claude/skills/mb-epic-graph/scripts/epic-graph.ps1`:

- `Test-Unblocked` (`:644`) považuje blokátor za vyřízený jen při
  `StatusCat -eq 'done'` (`:651`). Je to **jediné** místo, kde se hotovost
  vyhodnocuje; jediný konzument je `Get-StatusGlyph` (`:666`).
- `Get-StatusGlyph` (`:655`) mapuje celou kategorii `indeterminate` na 🔨
  (`:664`), takže `Test`, `Review`, `Documentation` i `Design Review` jsou
  nerozeznatelné od rozpracovaného tiketu.
- Degradace bez `-ProposalPath` (`:667`–`:670`) dává odblokovanému `To Do`
  tiketu ▶️ — tvrzení „návrh hotov" z nevědomosti.
- Poslední stupně kaskády (`:671`–`:674`) rozlišují živý návrh (▶️/⏳) od jeho
  absence (🆕/⛔) podle `$proposalLive`, plněného ze stage složky proposalu
  (`:380`–`:388`); `$proposalInfoAvailable` je pouhé `[bool]$ProposalPath`
  (`:112`).
- **Jméno stavu je nechráněné:** `:241` čte `[string]$statusObj.name` bez testu
  `PSObject.Properties['name']`, zatímco `statusCategory` na `:242` chráněné
  je. Pod `Set-StrictMode -Version Latest` (`:105`) a
  `$ErrorActionPreference = 'Stop'` (`:106`) snapshot s `"status": {}` skript
  shodí (exit 1). Dnes je to latentní kosmetická vada — jméno stavu se používá
  jen v Mermaid labelu (`:499`) a v odsazeném seznamu (`:539`).
- **V režimu `-Source Proposals` je `Status` volnotextové:** `:274` ho plní
  z hlavičky `**Stav:**` proposalu (`:299`) a ta není nikde enumerovaná —
  reálné hodnoty jsou „návrh" (`tests/fixtures/basic/proposal_alfa.md:4`),
  „rozpracováno" (`proposal_gama.md:4`), stejně legitimně by tam mohlo stát
  „Test" nebo „Design Review". `StatusCat` v tomto režimu vzniká ze stage
  složky (`:293`–`:297`: `completed` → `done`, `active` → `indeterminate`,
  jinak `new`) a `-ProposalPath` je povinný (`:115`).
- **Vlny a barvení na stavu nezávisí:** `Resolve-Wave` (`:577`),
  `Get-RootAncestors` (`:599`), pořadí řádků (`:692`) i stream-emoji (`:612`)
  čtou výhradně `$blockedBy`/`$blocksOut`.
- **Oracle na stavu nezávisí:** sekce `:744`–`:892` `Status` ani `StatusCat`
  nečte, `$script:ExitCode` se plní jen z počtu `CHYBA` (`:891`).

### Testovací infrastruktura

- Jira-mode testy: `tests/graph-generation.tests.ps1:21`–`:51`.
  `tests/e2e.tests.ps1` je Proposals-only smoke test.
- Stavové glyphy má pokryté právě jeden assert —
  `graph-generation.tests.ps1:19` (`▶️` pro živý `next/` proposal bez
  blokátorů) — a ten běží v **Proposals** režimu, kde je `-ProposalPath`
  povinný. Jira běhy na `snap.json` (`:23`, `:29`, `:44`) žádný glyph netvrdí.
- Fixtures `fixtures/jira/snap.json` a `afterwindow.json` `statusCategory`
  neobsahují vůbec, jen `status.name`.
- Harness `_assert.ps1` umí `Assert-Match`/`Assert-NotMatch` nad celým
  reportem (`:9`–`:14`), `Assert-Eq` (`:15`) a `Invoke-Graph` (`:24`), který
  skript spouští out-of-process a vrací `Out` + `Code`. `Complete-Tests`
  (`:18`) volá `exit`, takže cokoli za jejím voláním je mrtvý kód.
- Runner v repu není; každý `*.tests.ps1` se spouští samostatně.

## Rozhodovací matice (normativní)

Vstupy jsou tři: **fáze podle JIRA stavu** × **stav návrhu** × **blokátory**.
Odblokováno = všechny přímé `Blocks`-blokátory jsou hotové pro plánování;
blokátor mimo snapshot se konzervativně počítá jako blokující.

| fáze (JIRA stav) | hotový pro plánování? | bez návrhu, odblok. | bez návrhu, blokován | draft v `next/`, odblok. | draft v `next/`, blokován | proposal v `active/` | návrh neznámý (bez `-ProposalPath`): odblok. / blokován |
|---|---|---|---|---|---|---|---|
| Done, Cancelled | **ano** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ / ✅ |
| Test, Review, Documentation | **ano** | 🧪 | 🧪 | 🧪 | 🧪 | 🧪 | 🧪 / 🧪 |
| Design Review | ne | 👀 | 👀 | 👀 | 👀 | 👀 | 👀 / 👀 |
| In Progress | ne | 🔨 | 🔨 | 🔨 | 🔨 | 🔨 | 🔨 / 🔨 |
| To Do, Backlog, prázdný stav | ne | **💡** | **⛔** | **▶️** | **⏳** | **🔨** | **❔** / **⛔** |

Význam pro rozhodnutí „na čem začít":

```text
▶️ ber hned — návrh existuje a nic neblokuje (dopracuj zadání a spusť implementaci)
💡 nový tiket bez návrhu, odblokovaný — ber, chceš-li nejdřív rozpracovat zadání
⏳ návrh hotov, ale čeká na blokátory — nemá cenu
⛔ blokováno (a bez návrhu) — nemá cenu
🔨 implementuje se — někdo jiný
👀 v design review — čeká na architekta, nezačínej
🧪 v testu / review / dokumentaci — počítá se jako hotový, jen není uzavřený
✅ hotovo (Done, Cancelled)
❔ odblokováno, stav návrhu neznámý (běh bez -ProposalPath)
```

Rodina má 8 symbolů v plném režimu (✅ 🧪 👀 🔨 ▶️ ⏳ 💡 ⛔) a 6 v degradovaném
(✅ 🧪 👀 🔨 ❔ ⛔). 🆕 se nepoužívá vůbec.

## Technický návrh

### 1. Konstanty a `Test-DoneForPlanning`

Dvě pevné konstanty v `epic-graph.ps1` (bez parametrů CLI), uložené **už
normalizovaně** — lowercase, bez diakritiky:

```powershell
# Stavy, které se pro plánování počítají jako hotové, i když jejich
# statusCategory hotová není: práce je odvedená, dočítává se ocas.
# Test 10205, Review 10206, Documentation 11064 jsou všechny v kategorii
# indeterminate stejně jako In Progress (3) — rozlišit lze jen názvem.
$script:DoneForPlanningStatusNames = @('test', 'review', 'documentation')

# Stav, kdy tiket čeká na posouzení architektem. NENÍ hotový pro plánování
# (návrh se ještě nepřevedl na implementaci), ale má vlastní ikonu, aby se
# na něm nezačínalo. V UMS workflow zatím není zapojen — podpora dopředu.
$script:DesignReviewStatusNames = @('design review')

# Porovnávej operátorem -contains, NIKOLI metodou .Contains() (ta je ordinal
# case-sensitive a tichou regresí by shodila case-insensitivní match).
```

Nová funkce vedle `Test-Unblocked`:

```powershell
function Test-DoneForPlanning([string] $key) { ... }
```

Kontrakt, v tomto pořadí:

1. Klíč mimo `$issues` (externí tiket) → `$false` — stejně konzervativně jako
   dnešní kód na `:651`.
2. `StatusCat -eq 'done'` → `$true`.
3. Jen v režimu **Jira**: normalizovaný název stavu v
   `$script:DoneForPlanningStatusNames` → `$true`.
4. Jinak `$false`.

Normalizace názvu: `Trim()` + `Remove-Diacritics` (helper už ve skriptu je) +
`ToLowerInvariant()`.

Uvnitř funkce se na režim odkazuj přes `$script:Source`, ne `$Source` —
parametr není ve scope funkce; stejná past, jakou kód dokumentuje na
`:448`–`:451`.

### 2. Odblokování následníků

`Test-Unblocked` nahradí přímý test `StatusCat -eq 'done'` (`:651`) voláním
`Test-DoneForPlanning`. Ostatní semantika zůstává.

### 3. Kaskáda `Get-StatusGlyph`

První shoda vyhrává:

```text
1. -NoStatus                                     → '' (žádný glyph)
2. klíč mimo $issues (externí uzel)              → ''
3. StatusCat = done                              → ✅
4. Jira & název ∈ DoneForPlanningStatusNames     → 🧪     ← nové
5. Jira & název ∈ DesignReviewStatusNames        → 👀     ← nové
6. StatusCat = indeterminate | $proposalActive    → 🔨
7. bez -ProposalPath                             → odblok. ? ❔ : ⛔   ← ❔ místo ▶️
8. $proposalLive (draft v next/)                 → odblok. ? ▶️ : ⏳
9. jinak (bez návrhu)                            → odblok. ? 💡 : ⛔   ← 💡 místo 🆕
```

Pořadí kroků 4 a 5 před krokem 6 je nosné: musí předbíhat jak kategorii
`indeterminate`, tak `$proposalActive` — jinak by tiket v `Test` s běžící
implementací, nebo tiket v `Design Review` s připnutým work itemem
v `proposals/active/`, spadl na 🔨.

Kaskáda se vrací ještě před vyhodnocením blokátorů, takže tiket v `Test` nebo
`Design Review` nese svou ikonu i tehdy, když je sám blokovaný nehotovým
předchůdcem. Je to stejné chování jako dnes u kategorie `done` a je záměrné —
ikona popisuje fázi tiketu, ne jeho blokátory.

### 4. Ochrana jména stavu

`:241` se opraví na tvar chráněný stejně jako `:242`:

```powershell
Status = if ($statusObj -and $statusObj.PSObject.Properties['name']) { [string]$statusObj.name } else { '' }
```

Bez toho by snapshot s `"status": {}` skript shodil, a to nově uprostřed
plánovací logiky, ne jen v kosmetickém labelu.

### 5. Režim `-Source Proposals`

Kroky 4 a 5 kaskády jsou v tomto režimu vypnuté (podmínka „Jira"), protože
`**Stav:**` je volnotextové pole — proposal s hodnotou „Test" by jinak tiše
odblokoval své následníky. `-ProposalPath` je zde povinný, takže nevzniká ani
❔. Zbytek chování zůstává: `completed` → ✅, `active` → 🔨, `next` → ▶️/⏳.

Uzel ve stage `abandoned` propadne na krok 9 a nese 💡/⛔ (dnes 🆕/⛔) — dosud
nezdokumentovaný stav; legenda Proposals režimu ho doplní jako
„💡 opuštěný návrh (abandoned)".

### 6. Místa k úpravě

| soubor | místo | úprava |
|---|---|---|
| `epic-graph.ps1` | `:241` | ochrana `status.name` přes `PSObject.Properties` |
| `epic-graph.ps1` | před `Test-Unblocked` | dvě konstanty + `Test-DoneForPlanning` |
| `epic-graph.ps1` | `:651` (`Test-Unblocked`) | volání `Test-DoneForPlanning` |
| `epic-graph.ps1` | `:655`–`:675` (`Get-StatusGlyph`) | kaskáda dle §3 (🧪, 👀, ❔, 💡) |
| `epic-graph.ps1` | `:60`–`:70` (`.PARAMETER NoStatus`) | nová rodina, plná i degradovaná varianta, poznámka o Proposals režimu |
| `epic-graph.ps1` | `:927` (legenda Proposals režimu) | + 💡 „opuštěný návrh (abandoned)" |
| `epic-graph.ps1` | `:929` (legenda tabulky vln, Jira režim) | nová rodina včetně 🧪/👀/❔ + definice „hotový pro plánování = Done, Cancelled, Test, Review, Documentation" |
| `SKILL.md` | `:94` (bullet `-ProposalPath`) | degradovaný výčet `✅/🔨/▶️/⛔` → `✅/🧪/👀/🔨/❔/⛔` |
| `SKILL.md` | `:125`–`:126` (výčet glyphů v „Use the outputs") | nová rodina + definice „hotový pro plánování" + poznámka, že 🧪/👀/❔ v Proposals režimu nevznikají |
| `SKILL.md` | krok 1 (fetch snapshot, `:44`–`:52`) | druhý (externals) dotaz MUSÍ mít identický seznam `fields`; jinak tiket v `Test` ztratí `status` a začne znovu blokovat |
| `SKILL.md` | `:7` (`metadata.version`) | 1.3 → 1.4 |

Beze změny zůstává popis Proposals režimu v `SKILL.md` (`:130`) a
`.SYNOPSIS`/`.DESCRIPTION` (výčet glyphů nenesou). Jiné výskyty 🆕 v `ums/`
neexistují.

## Testy

Nový soubor `tests/status-glyph.tests.ps1` — Jira-mode glyph testy. **Ne**
`e2e.tests.ps1` (Proposals-only, `Complete-Tests` na konci). Spouští se
samostatně:

```powershell
pwsh -NoProfile -File ums/.claude/skills/mb-epic-graph/tests/status-glyph.tests.ps1
```

Existující fixtures (`snap.json`, `afterwindow.json`, `basic/`, `newstyle/`)
zůstávají nedotčené; všechny stávající běhy předávají explicitní cestu, nikdy
`fixtures/` root, takže nové soubory je nemohou ovlivnit.

### Fixtures

**`fixtures/jira/status.json`** — epic `DEMO-0` (`issuetype: Epic`, běhy ho
předávají jako `-EpicKey DEMO-0`) + tikety `DEMO-1`…`DEMO-17`. Klíče MUSÍ být
uppercase — atribuce proposalu na `:374` vyžaduje `[A-Z][A-Z0-9]+-\d+`. Každý
tiket nese `status.name` **i** `status.statusCategory.key` (bez kategorie by
`StatusCat` zůstal `''` a testy by měřily něco jiného), s jednou úmyslnou
výjimkou u `DEMO-10`:

| tiket | `status.name` | kategorie | blokován | návrh | bez `-ProposalPath` | s `-ProposalPath` | co dokazuje |
|---|---|---|---|---|---|---|---|
| DEMO-1 | Test | indeterminate | — | — | 🧪 | 🧪 | Test má vlastní ikonu |
| DEMO-2 | To Do | new | DEMO-1 | `next/` | ❔ | ▶️ | **jádro:** Test odblokuje následníka |
| DEMO-3 | In Progress | indeterminate | — | — | 🔨 | 🔨 | nezobecnilo se na kategorii |
| DEMO-4 | To Do | new | DEMO-3 | `next/` | ⛔ | ⏳ | In Progress dál blokuje |
| DEMO-5 | Done | done | — | — | ✅ | ✅ | kontrola: `done` fungovalo už dřív |
| DEMO-6 | To Do | new | DEMO-5 | — | ❔ | 💡 | bez návrhu ≠ ▶️ |
| DEMO-7 | test | indeterminate | — | — | 🧪 | 🧪 | match je case-insensitive |
| DEMO-8 | Test | indeterminate | — | `active/` | 🧪 | 🧪 | krok 4 předbíhá `$proposalActive` |
| DEMO-9 | To Do | new | DEMO-99 (externí) | — | ⛔ | ⛔ | externí blokátor blokuje |
| DEMO-10 | `"status": {}` | — | — | — | ❔ | 💡 | prázdný status skript nezhodí |
| DEMO-11 | Review | indeterminate | — | — | 🧪 | 🧪 | Review je hotový pro plánování |
| DEMO-12 | Documentation | indeterminate | — | — | 🧪 | 🧪 | Documentation totéž |
| DEMO-13 | Design Review | indeterminate | — | `active/` | 👀 | 👀 | krok 5 předbíhá kategorii i `$proposalActive` |
| DEMO-14 | To Do | new | DEMO-13 | — | ⛔ | ⛔ | Design Review **neodblokovává** |
| DEMO-15 | To Do | new | DEMO-11 | — | ❔ | 💡 | Review odblokuje následníka |
| DEMO-16 | Cancelled | done | — | — | ✅ | ✅ | Cancelled je kategorie `done` |
| DEMO-17 | To Do | new | DEMO-16 | — | ❔ | 💡 | Cancelled odblokuje (záměrně) |

**`fixtures/status_proposals/`** — `next/design_demo_2.md`,
`next/design_demo_4.md`, `active/design_demo_8.md`,
`active/design_demo_13.md`, každý s hlavičkou `**Jira:** DEMO-<n>`.

**`fixtures/status_stav/next/`** — tři proposaly pro JIRA-less pojistku:
`design_alfa.md` s hlavičkou `**Stav:** Test` a `Blokuje:` odkazem na
`design_beta.md`; `design_beta.md`; `design_gama.md` s
`**Stav:** Design Review`.

### Případy

Všechny běhy **bez** `-Check`, aby asserty na ✅ nekolidovaly s hláškou oracle
„✅ Žádný nesoulad nenalezen" (`:956`). U všech běhů se ověřuje exit code 0.

1. **Jira bez `-ProposalPath`** — glyph každého tiketu dle šestého sloupce.
2. **Jira s `-ProposalPath fixtures/status_proposals`** — glyph každého tiketu
   dle sedmého sloupce; pokrývá celou plnou rodinu (▶️ ⏳ 💡 vedle ✅ 🧪 👀 🔨 ⛔).
3. **DEMO-8 = 🧪 a DEMO-13 = 👀** v obou bězích — pořadí kaskády.
4. **DEMO-2, DEMO-15 a DEMO-17 jsou odblokované, DEMO-4 a DEMO-14 ne** —
   matice hotovosti pro plánování: Test/Review/Cancelled ano,
   In Progress/Design Review ne.
5. **DEMO-7 = 🧪 a DEMO-3 = 🔨** — case-insensitivní match bez zobecnění na
   kategorii `indeterminate`.
6. **DEMO-9 = ⛔** — externí blokátor mimo snapshot.
7. **DEMO-10** — exit 0 a glyph z `To Do` větve (❔, resp. 💡).
8. **`-NoStatus`** potlačí 🧪, 👀 i ❔.
9. **Vlny se nemění** — DEMO-1 ve vlně 0, DEMO-2 ve vlně 1 (assert na pozici
   buňky v řádku), shodně v obou bězích.
10. **Proposals režim** (`-Source Proposals -ProposalPath fixtures/status_stav`)
    — `**Stav:** Test` ani `**Stav:** Design Review` nedá 🧪/👀: `alfa` nese ▶️
    (živý `next/`, odblokován), `beta` ⏳ (blokován alfou), `gama` ▶️. Asserty
    `Assert-NotMatch` na 🧪, 👀 a ❔.

Asserty MUSÍ být per-tiket, ne na výskyt glyphu ve výstupu: `Assert-Match`
pracuje nad celým reportem (`_assert.ps1:9`–`:14`), takže
`Assert-Match $out '🧪'` by prošel i tehdy, když 🧪 dostane špatný tiket. Buňka
má deterministický tvar `"$statusGlyph $(Get-Emoji $k) $keyMd $sum"`
(`:683`–`:684`), takže vzor typu `🧪 \S+ \[DEMO-1\]` je vyjádřitelný.

## Rozhodnutí a jejich zdůvodnění

- **Hotové pro plánování = Done, Cancelled, Test, Review, Documentation.**
  U všech pěti je práce odvedená; čekat na ně znamená schovávat připravenou
  práci. Sdílí ikonu 🧪 („v testu/review/dokumentaci"), aby rodina nenarostla
  nad únosnou míru.
- **`Cancelled` odblokovává** stejně jako dnes: zrušený tiket už nikdo
  nedokončí, takže čekání na něj nemá smysl. Uvedeno explicitně, aby to
  nevypadalo jako přehlédnutí.
- **`Design Review` blokuje** — návrh v posouzení není implementace. Vlastní
  ikona 👀 existuje proto, aby dashboard nikoho neposlal na tiket, jehož návrh
  právě posuzuje architekt.
- **Bez `-ProposalPath` se použije ❔**, nikoli ▶️ ani 💡. Obě alternativy
  tvrdí něco o existenci návrhu, o níž skript v tomto běhu nic neví; ❔ je
  jediná pravdivá odpověď. Pro rozhodovací použití dashboardu je
  `-ProposalPath` doporučený vstup.
- **Konstanty, ne parametr CLI.** Stavy workflow jsou vlastnost Jiry, ne
  volání; parametr by přidal povrch k dokumentaci a umožnil nekonzistentní
  výstupy mezi běhy.
- **Match podle názvu, ne podle kategorie**, protože `Test`, `Review`,
  `Documentation` a `In Progress` mají tutéž kategorii `indeterminate`.
- **`mb-epic-elaboration` se nemění.** Výběr okna (`protocol.md:32`–`:52`) je
  definovaný jako *dirty-first → leverage* a na hotovosti blokátorů nezávisí;
  `protocol.md:41`–`:43` naopak výslovně říká, že kontraktní rozhodnutí si drží
  leverage i když je jeho implementace blokovaná. Vysvětlení ikon proto jde jen
  do `mb-epic-graph/SKILL.md`.

## Dopady

- Tabulka vln přestane blokovat práci za tikety v `Test`/`Review`/
  `Documentation` — jejich následníci se posunou na ▶️ (s návrhem) nebo 💡 (bez
  návrhu). Sloupce (vlny) se **nemění**, ty počítá topologie `Blocks`.
- Běhy bez `-ProposalPath` už netvrdí „návrh hotov" — odblokované `To Do`
  tikety nesou ❔.
- Tikety v `Design Review` jsou nově odlišené (👀) a dál blokují.
- Uložené `graph.md` v `memory-bank/epics/<epic>/` se při nejbližší regeneraci
  diffnou o změněné glyphy (🆕 → 💡, ▶️ → ❔ v degradovaných bězích).
- Snapshot s prázdným nebo chybějícím `status` přestane skript shazovat.
- Konzistenční oracle (`-Check`) a exit kódy se nemění.

## Rizika a předpoklady

- **Přejmenování stavu v Jiře** rozbije match podle názvu potichu — tiket by
  se začal chovat jako `In Progress`. Zmírnění: konstanty jsou na jednom místě
  a komentář u nich uvádí i id stavů.
- **Tiket vrácený z testu** (`Test` → `In Progress`/`To Do`) odblokování zase
  odebere a následník se vrátí na ⛔, resp. ⏳. Akceptováno: graf se generuje
  z aktuálního snapshotu, žádný stav si nepamatuje.
- **Neúplný druhý snapshot** (fetch externích blokátorů bez `status` ve
  `fields`) degraduje tiket v `Test` na blokující. Zmírnění: požadavek
  v `SKILL.md` kroku 1.
- **`Design Review` není zapojený do UMS workflow** — do té doby je krok 5
  kaskády mrtvý kód a `mb-architect-review` v režimu request fail-closed spadne
  (viz kontrakt, Architect Review Gate). Předpoklad k doplnění v administraci
  Jiry, ne riziko této změny.
- Riziko zobecnění na celou kategorii `indeterminate` (odblokování už při
  započetí práce) hlídá test č. 5; riziko prosáknutí do JIRA-less režimu
  test č. 10.

## Mimo scope

- Zapojení stavu `Design Review` do UMS workflow (administrace Jiry).
- `mb-state` — čte pouze lokální MB workflow (pin, pár design+plán, SDD
  ledger), Jira stavy nesahá.
- `mb-jira-update` — stavy jen nastavuje při finalizaci, nikdy nevyhodnocuje.
- `mb-epic-elaboration` včetně `ledger-status.ps1` — pracuje s tabulkami
  `ledger.md`; stav `hotov` je rozpracovanost tiketu, ne implementační stav.
- Mermaid label (`:499`) a odsazený seznam (`:539`) — vypisují jméno stavu
  verbatim už dnes.
- `UMS_MEMORY_BANK_CONTRACT.md` a `CLAUDE.md.sample` — nejde o kontraktní
  chování MB vrstvy.
- Přenos do monorepa `d:\_datasys\ums` přes `sync-with-monorepo.ps1` — proběhne
  následně, mimo tuto větev (stejný postup jako u UMS-3361).

Grep celého `ums/` potvrzuje, že žádný další konzument hotovosti Jira stavu
v repu neexistuje.

## Zaparkované nálezy (follow-up)

Nálezy finálního review celé větve, které byly vědomě odloženy — žádný není
nosný a nic na nich nestaví. Jsou tu proto, aby se neztratily; každý je
samostatná práce, ne dodatek k této změně.

1. **Chybí runner testů.** Skill má pět samostatných souborů
   `tests/*.tests.ps1` a žádný `tests/run-all.ps1`; „projde všech pět" není
   jediný příkaz, takže regresi zachytí jen ten, kdo si na všechny soubory
   vzpomene. Reviewer to označil za největší slabinu odolnosti skillu — hrozba
   není revendoring upstreamu (`epic-graph.ps1` je UMS autorský), ale
   round-trip přes `sync-with-monorepo.ps1`.
2. **Překlep v `-ProposalPath` se chová jako „návrh neexistuje".**
   `$proposalInfoAvailable = [bool]$ProposalPath` se plní ze *stringu*, takže
   neexistující cesta jen varuje, ale příznak zůstane `$true` a `$proposalLive`
   prázdné — každý odblokovaný tiket pak dostane 💡 („odblokováno, bez návrhu")
   místo ❔. To je přesně přeceňování, které tato změna odstraňovala, jen jinými
   dveřmi. Levné zpevnění: nastavit příznak jen tehdy, když se aspoň jedna
   zadaná cesta rozřešila.
3. **Prázdné jméno stavu se vykresluje.** U tiketu s prázdným objektem
   `status` (nově dosažitelný stav, viz Task 1) vypíše odsazený seznam `· __`
   — což není platné Markdown zvýraznění a zobrazí se literálně — a Mermaid
   label končí viselcem `· `. Řešením je vynechat suffix `· <stav>`, když je
   jméno prázdné.
4. **Legenda režimu Proposals nedopovídá ⛔.** Po této změně znamená ⛔ v tomto
   režimu přesně „abandoned + blokováno" (`next/` + blokováno je ⏳, stupně 7/8
   ⛔ vyrobit nemohou), legenda říká jen „blokováno". Stejná nepřesnost, jaká
   vedla k doplnění položky 💡. Stage `abandoned` navíc nemá fixture, takže
   tvrzení „💡/⛔ podle odblokování" je zdokumentované, ale netestované
   (chování je předchozí, změnila se jen ikona).
5. **Asymetrie `abandoned` vs. `Cancelled` není nikde zdůvodněná.** Opuštěný
   *návrh* blokuje své následníky dál, zrušený *tiket* je odblokuje. Považujeme
   to za správné (opuštění návrhu nezruší práci), ale návrh explicitně
   argumentuje jen u `Cancelled` a zrcadlový případ nezmiňuje — čtenář o to
   zakopne.
6. **Plán cituje neexistující pravidlo.** `plan_…md`, Global Constraints,
   odkazuje na `ums/.gitattributes` s `.claude/skills/** text eol=lf`. Ten
   soubor ve forku není; kořenový `.gitattributes` kryje `*.md`/`*.json`, ale
   **ne `*.ps1`**. Výsledek je v pořádku (LF), ale proto, že se tak psalo, ne
   proto, že to atribut vynucuje.

Nezaparkováno, uzavřeno rozhodnutím: nápověda `.PARAMETER NoStatus` říká „the
name-based 🧪/👀 never appear there" bez ❔ — věta je záměrně o glyphech
odvozených z **názvu** stavu a ❔ mezi ně nepatří.
