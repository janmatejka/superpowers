# Návrh: Rozhodovací stavové ikony v grafu epiku (Test = hotový pro plánování)

- **Jira:** (žádný tiket)
- **Target MB:** — (fork superpowers nemá Memory Bank; dokument žije v `ums/docs/`)
- **Plán:** [plan_epic_graph_test_jako_hotovo.md](plan_epic_graph_test_jako_hotovo.md) (vznikne ve writing-plans)
- **Vytvořeno:** 2026-07-31

## Cíl

Stavová ikona v tabulce vln má být **rozhodovací nástroj pro otázku „na kterém
tiketu začít pracovat"**. Z toho plyne vše ostatní:

1. Tiket, jehož práce je hotová a dočítává se ocas (**Test**, **Review**,
   **Documentation**), nesmí blokovat své následníky — jinak dashboard schovává
   práci, která je připravená k započetí.
2. Ikona nesmí tvrdit víc, než skript ví. Dnešní degradace bez `-ProposalPath`
   napíše na odblokovaný To‑Do tiket ▶️ („návrh hotov, spusť implementaci"),
   i když o návrzích nemá žádnou informaci — to je inverzní ke smyslu ▶️.
3. Rodina ikon musí být na první pohled rozlišitelná (🆕 splývalo s ▶️) a musí
   pokrývat i stav **Design Review**, kde tiket čeká na architekta a začínat se
   na něm nemá.

## Zjištěný stav

### Workflow v Jiře (ověřeno live)

`getTransitionsForJiraIssue` na UMS-3361 s `includeUnavailableTransitions`
(Atlassian MCP, 2026-07-31) dává celý stavový prostor:

| stav | id | `statusCategory.key` |
|---|---|---|
| Backlog | 10202 | `new` |
| To Do | 10300 | `new` |
| In Progress | 3 | `indeterminate` |
| **Test** | 10205 | `indeterminate` |
| **Review** | 10206 | `indeterminate` |
| **Documentation** | 11064 | `indeterminate` |
| Done | 10204 | `done` |
| Cancelled | 10700 | `done` |

Zásadní důsledek: **Test, Review i Documentation leží ve stejné kategorii jako
In Progress**, takže podle `statusCategory` je odlišit nelze — match musí jít
podle **názvu stavu**.

**„Design Review" v tomto workflow není.** JQL `status = "Design Review"`
projde bez chyby (název v instanci existuje), ale nevrací žádný tiket a mezi
přechody UMS-3361 se nevyskytuje. Skript s tím musí umět pracovat dopředu
(match podle názvu, nezávisle na kategorii); zapojení stavu do workflow je
úkol v Jiře, ne v kódu — bez něj `mb-architect-review` v režimu request
fail-closed spadne (viz kontrakt, Architect Review Gate).

### Chování `epic-graph.ps1` dnes

- `Test-Unblocked` (`:644`) považuje blokátor za vyřízený jen při
  `StatusCat -eq 'done'` (`:651`). Je to **jediné** místo, kde se hotovost
  vyhodnocuje; jediný konzument je `Get-StatusGlyph` (`:666`).
- `Get-StatusGlyph` (`:655`) mapuje celou kategorii `indeterminate` na 🔨
  (`:664`) → Test, Review, Documentation i Design Review jsou nerozeznatelné od
  rozpracovaného tiketu.
- Degradace bez `-ProposalPath` (`:667`–`:670`) dává odblokovanému To‑Do tiketu
  ▶️ — tvrzení „návrh hotov" z nevědomosti.
- **Název stavu je nechráněný:** `:241` čte `[string]$statusObj.name` bez testu
  `PSObject.Properties['name']`, zatímco `statusCategory` na `:242` chráněné
  je. Pod `Set-StrictMode -Version Latest` (`:105`) a
  `$ErrorActionPreference = 'Stop'` (`:106`) snapshot s `"status": {}` skript
  **shodí** (exit 1). Dnes latentní kosmetická vada (jméno stavu se používá jen
  v Mermaid labelu `:499` a v odsazeném seznamu `:539`); tato změna z názvu dělá
  plánovací vstup, takže oprava patří do scope.
- **V režimu `-Source Proposals` je `Status` volnotextové pole:** `:274` plní
  `Status` z hlavičky `**Stav:**` proposalu (`:299`) a ta není nikde
  enumerovaná — reálné hodnoty jsou „návrh"
  (`tests/fixtures/basic/proposal_alfa.md:4`), „rozpracováno"
  (`proposal_gama.md:4`), stejně legitimně by tam mohlo stát „Test" nebo
  „Design Review". Match podle názvu proto **musí** být omezen na režim Jira,
  jinak by tichou změnou semantiky odblokovával i JIRA-less grafy.
- Vlny, pořadí řádků ani stream-emoji na stavech nezávisí (`Resolve-Wave`
  `:577`, `Get-RootAncestors` `:599`, řádky `:692`, emoji `:612` čtou výhradně
  `$blockedBy`/`$blocksOut`). Konzistenční oracle (`:744`–`:892`) stav nečte
  vůbec a `$script:ExitCode` se plní jen z počtu `CHYBA` (`:891`).

### Stav testů

Jira-mode testy žijí v `tests/graph-generation.tests.ps1` (`:21`–`:51`),
`tests/e2e.tests.ps1` je Proposals-only smoke test. Stavové glyphy má pokryté
právě jeden assert — `graph-generation.tests.ps1:19` (`▶️` pro živý `next/`
proposal bez blokátorů) a ten běží v **Proposals** režimu, kde je
`-ProposalPath` povinný; změna degradovaného glyphu ho tedy nerozbije. Jira
běhy na `snap.json` (`:23`, `:29`, `:44`) žádný glyph netvrdí. Fixtures
v `fixtures/jira/` pole `statusCategory` neobsahují vůbec, jen `status.name`.
`_assert.ps1:18` (`Complete-Tests`) volá `exit`, takže cokoli za jejím voláním
je mrtvý kód. Runner v repu není — každý `*.tests.ps1` se spouští samostatně.

## Scope

**Zahrnuto:** `ums/.claude/skills/mb-epic-graph/scripts/epic-graph.ps1`
(logika, ochrana `status.name`, nápověda, legendy),
`ums/.claude/skills/mb-epic-graph/SKILL.md` (glyphy, požadavek na `fields`
u druhého snapshotu, bump `metadata.version` 1.3 → 1.4),
`ums/.claude/skills/mb-epic-graph/tests/` (nový `status-glyph.tests.ps1` +
nové fixtures).

**Nezahrnuto a proč:**

- **Zapojení stavu „Design Review" do UMS workflow** — administrace Jiry, ne
  kód. Skript ho podporuje dopředu.
- **`Cancelled` odblokovává následníky** stejně jako `Done` (kategorie `done`,
  `:651`). Zůstává tak, záměrně: zrušený tiket už nikdo nedokončí, takže čekat
  na něj nemá smysl. Uvedeno explicitně, aby to nevypadalo jako přehlédnutí.
- **`mb-epic-elaboration` se nemění.** Výběr okna (`protocol.md:32`–`:52`) je
  definovaný jako *dirty-first → leverage* a na hotovosti blokátorů nezávisí —
  `protocol.md:41`–`:43` naopak výslovně říká, že kontraktní rozhodnutí si drží
  leverage i když je jeho implementace blokovaná. Vysvětlení ikon jde jen do
  `mb-epic-graph/SKILL.md`. Jeho `ledger-status.ps1` pracuje výhradně
  s tabulkami `ledger.md`; stav `hotov` je *rozpracovanost* tiketu, ne
  implementační stav.
- `mb-state` — čte pouze lokální MB workflow (pin, pár design+plán, SDD
  ledger), Jira stavy nesahá.
- `mb-jira-update` — stavy jen *nastavuje* při finalizaci, nikdy nevyhodnocuje.
- Mermaid label (`:499`) a odsazený seznam (`:539`) — už dnes vypisují jméno
  stavu verbatim.
- `UMS_MEMORY_BANK_CONTRACT.md` a `CLAUDE.md.sample` — nejde o kontraktní
  chování MB vrstvy.
- **Přenos do monorepa** `d:\_datasys\ums` přes `sync-with-monorepo.ps1` —
  provede se následně, mimo tuto větev (stejný postup jako u UMS-3361).

Grep celého `ums/` potvrzuje, že žádný další konzument hotovosti Jira stavu
v repu neexistuje.

## Technický návrh

### 1. Rozhodovací matice (normativní)

Vstupy jsou tři: **fáze podle JIRA stavu** × **stav návrhu** × **blokátory**.
Odblokováno = všechny přímé `Blocks`-blokátory jsou *hotové pro plánování*;
blokátor mimo snapshot se konzervativně počítá jako blokující.

| fáze (JIRA stav) | hotový pro plánování? | bez návrhu, odblok. | bez návrhu, blokován | draft v `next/`, odblok. | draft v `next/`, blokován | proposal v `active/` | návrh neznámý (bez `-ProposalPath`), odblok. / blokován |
|---|---|---|---|---|---|---|---|
| Done, Cancelled | **ano** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ / ✅ |
| **Test, Review, Documentation** | **ano** (nově) | 🧪 | 🧪 | 🧪 | 🧪 | 🧪 | 🧪 / 🧪 |
| **Design Review** | ne | 👀 | 👀 | 👀 | 👀 | 👀 | 👀 / 👀 |
| In Progress | ne | 🔨 | 🔨 | 🔨 | 🔨 | 🔨 | 🔨 / 🔨 |
| To Do, Backlog, prázdný stav | ne | **💡** | **⛔** | **▶️** | **⏳** | **🔨** | **❔** / **⛔** |

Význam pro rozhodnutí „na čem začít":

```text
▶️ ber hned — návrh existuje, nic neblokuje (dopracuj zadání a spusť implementaci)
💡 nový tiket bez návrhu, odblokovaný — ber, chceš-li nejdřív rozpracovat zadání
⏳ návrh hotov, ale čeká na blokátory — nemá cenu
⛔ blokováno (a bez návrhu) — nemá cenu
🔨 implementuje se — někdo jiný
👀 v design review — čeká na architekta, nezačínej
🧪 v testu / review / dokumentaci — počítá se jako hotový, jen není uzavřený
✅ hotovo (Done, Cancelled)
❔ odblokováno, stav návrhu neznámý (běh bez -ProposalPath)
```

Rodina má tedy 8 symbolů v plném režimu (✅ 🧪 👀 🔨 ▶️ ⏳ 💡 ⛔) a 6
v degradovaném (✅ 🧪 👀 🔨 ❔ ⛔). 🆕 se nepoužívá vůbec — v terminálových
fontech splývalo s ▶️.

### 2. Rozpoznání stavu

Dvě pevné konstanty v `epic-graph.ps1` (bez parametrů CLI), uložené **už
normalizovaně** (lowercase, bez diakritiky):

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

Kontrakt funkce:

1. Klíč mimo `$issues` (externí tiket) → `$false` (stejně konzervativně jako
   dnešní kód na `:651`).
2. `StatusCat -eq 'done'` → `$true`.
3. Jen v režimu **Jira**: normalizovaný název stavu v
   `$script:DoneForPlanningStatusNames` → `$true`. V režimu `Proposals` se krok
   přeskočí — pole `**Stav:**` je volnotextové (viz Zjištěný stav). Uvnitř
   funkce se na režim odkazuj přes `$script:Source`, ne `$Source` (parametr
   není ve scope funkce; stejná past, jakou kód dokumentuje na `:448`–`:451`).
4. Jinak `$false`.

Normalizace názvu: `Trim()` + `Remove-Diacritics` (helper už ve skriptu je) +
`ToLowerInvariant()`. Stejná normalizace se použije pro
`$script:DesignReviewStatusNames`, který je také Jira-only.

Zároveň se opraví `:241` na tvar chráněný stejně jako `:242`:

```powershell
Status = if ($statusObj -and $statusObj.PSObject.Properties['name']) { [string]$statusObj.name } else { '' }
```

### 3. Odblokování následníků

`Test-Unblocked` nahradí přímý test `StatusCat -eq 'done'` (`:651`) voláním
`Test-DoneForPlanning`. Ostatní semantika zůstává.

### 4. Kaskáda `Get-StatusGlyph`

Nová kaskáda (první shoda vyhrává). Pořadí je nosné — obojí nové pravidlo musí
předbíhat jak stupeň `indeterminate`, tak `$proposalActive`, jinak by tiket
v Testu s běžící implementací nebo tiket v design review s připnutým work
itemem spadl na 🔨:

```text
1. -NoStatus                                   → '' (žádný glyph)
2. klíč mimo $issues (externí)                 → ''
3. StatusCat = done                            → ✅
4. Jira & název ∈ DoneForPlanningStatusNames   → 🧪     ← nové
5. Jira & název ∈ DesignReviewStatusNames      → 👀     ← nové
6. StatusCat = indeterminate | $proposalActive  → 🔨
7. bez -ProposalPath                           → odblok. ? ❔ : ⛔   ← ❔ nové (dřív ▶️)
8. $proposalLive (draft v next/)               → odblok. ? ▶️ : ⏳
9. jinak (bez návrhu)                          → odblok. ? 💡 : ⛔   ← 💡 místo 🆕
```

Kaskáda se vrací ještě před vyhodnocením blokátorů, takže tiket v Testu nebo
v design review nese svou ikonu i tehdy, když je sám blokovaný nehotovým
předchůdcem. Je to stejné chování jako dnes u kategorie `done` a je záměrné —
ikona popisuje fázi tiketu, ne jeho blokátory.

Režim `-Source Proposals` se nemění: uzly jsou proposaly, `StatusCat` vzniká ze
stage složky (`completed` → `done`, `active` → `indeterminate`, jinak `new`;
`:293`–`:297`), kroky 4 a 5 jsou vypnuté a `-ProposalPath` je povinný, takže
🧪, 👀 ani ❔ tam nikdy nevzniknou. Uzel ve stage `abandoned` propadne na krok 9
a nese 💡/⛔ (dřív 🆕/⛔) — dosud nezdokumentovaný stav, legenda Proposals
režimu ho doplní jako „💡 opuštěný návrh (abandoned)".

### 5. Místa k úpravě

| soubor | místo | úprava |
|---|---|---|
| `epic-graph.ps1` | `:241` | ochrana `status.name` přes `PSObject.Properties` |
| `epic-graph.ps1` | před `Test-Unblocked` | dvě konstanty + `Test-DoneForPlanning` |
| `epic-graph.ps1` | `:651` (`Test-Unblocked`) | volání `Test-DoneForPlanning` |
| `epic-graph.ps1` | `:655`–`:675` (`Get-StatusGlyph`) | kaskáda dle §4 (🧪, 👀, ❔, 💡) |
| `epic-graph.ps1` | `:60`–`:70` (`.PARAMETER NoStatus`) | celá nová rodina, plná i degradovaná varianta, poznámka o Proposals režimu |
| `epic-graph.ps1` | `:927` (legenda Proposals režimu) | + 💡 „opuštěný návrh (abandoned)" |
| `epic-graph.ps1` | `:929` (legenda tabulky vln, Jira režim) | celá nová rodina včetně 🧪/👀/❔ a věty „hotový pro plánování = Done, Cancelled, Test, Review, Documentation" |
| `SKILL.md` | `:94` (bullet `-ProposalPath`) | degradovaný výčet `✅/🔨/▶️/⛔` → `✅/🧪/👀/🔨/❔/⛔` |
| `SKILL.md` | `:125`–`:126` (výčet glyphů v „Use the outputs") | celá nová rodina + definice „hotový pro plánování" + poznámka, že 🧪/👀/❔ v Proposals režimu nevznikají |
| `SKILL.md` | krok 1 (fetch snapshot, `:44`–`:52`) | druhý (externals) dotaz MUSÍ mít identický seznam `fields` — jinak tiket v Testu ztratí `status` a začne znovu blokovat |
| `SKILL.md` | `:7` (`metadata.version`) | 1.3 → 1.4 |

Beze změny zůstává popis Proposals režimu v `SKILL.md` (`:130`) a
`.SYNOPSIS`/`.DESCRIPTION` (žádný výčet glyphů nenesou). Jiné výskyty 🆕
v `ums/` neexistují.

### 6. Testy

Nový soubor `tests/status-glyph.tests.ps1` (Jira-mode glyph testy). **Ne**
`e2e.tests.ps1` — ten je Proposals-only a končí `Complete-Tests`, za nímž je
mrtvý kód. Spouští se samostatně:
`pwsh -NoProfile -File ums/.claude/skills/mb-epic-graph/tests/status-glyph.tests.ps1`.

Nové fixtures; existující `snap.json`, `afterwindow.json`, `basic/`, `newstyle/`
zůstávají nedotčené (visí na nich současné testy, a všechny stávající běhy
předávají explicitní cestu, nikdy `fixtures/` root).

**a) `fixtures/jira/status.json`** — epic `DEMO-0` (`issuetype: Epic`, běhy ho
předávají jako `-EpicKey DEMO-0`) + 17 tiketů `DEMO-1`…`DEMO-17`. Klíče MUSÍ
být uppercase, atribuce proposalu na `:374` vyžaduje `[A-Z][A-Z0-9]+-\d+`. Každý
řádek nese `status.name` **i** `status.statusCategory.key` (bez kategorie by
`StatusCat` zůstal `''` a testy by měřily něco jiného) — s jednou úmyslnou
výjimkou u DEMO-10:

| tiket | `status.name` | kategorie | blokován | návrh | bez `-ProposalPath` | s `-ProposalPath` | co dokazuje |
|---|---|---|---|---|---|---|---|
| DEMO-1 | Test | indeterminate | — | — | 🧪 | 🧪 | Test má vlastní ikonu |
| DEMO-2 | To Do | new | DEMO-1 | `next/` | ❔ | ▶️ | **jádro:** Test odblokuje následníka |
| DEMO-3 | In Progress | indeterminate | — | — | 🔨 | 🔨 | nezobecnilo se na `indeterminate` |
| DEMO-4 | To Do | new | DEMO-3 | `next/` | ⛔ | ⏳ | In Progress dál blokuje |
| DEMO-5 | Done | done | — | — | ✅ | ✅ | kontrola: `done` fungovalo už dřív |
| DEMO-6 | To Do | new | DEMO-5 | — | ❔ | 💡 | bez návrhu ≠ ▶️ |
| DEMO-7 | test | indeterminate | — | — | 🧪 | 🧪 | match je case-insensitive |
| DEMO-8 | Test | indeterminate | — | `active/` | 🧪 | 🧪 | krok 4 předbíhá `$proposalActive` |
| DEMO-9 | To Do | new | DEMO-99 (externí) | — | ⛔ | ⛔ | externí blokátor blokuje |
| DEMO-10 | `"status": {}` | — | — | — | ❔ | 💡 | prázdný status skript nezhodí |
| DEMO-11 | Review | indeterminate | — | — | 🧪 | 🧪 | Review je hotový pro plánování |
| DEMO-12 | Documentation | indeterminate | — | — | 🧪 | 🧪 | Documentation totéž |
| DEMO-13 | Design Review | indeterminate | — | `active/` | 👀 | 👀 | krok 5 předbíhá `indeterminate` i `$proposalActive` |
| DEMO-14 | To Do | new | DEMO-13 | — | ⛔ | ⛔ | Design Review **neodblokovává** |
| DEMO-15 | To Do | new | DEMO-11 | — | ❔ | 💡 | Review odblokuje následníka |
| DEMO-16 | Cancelled | done | — | — | ✅ | ✅ | Cancelled = `done` (rozhodnuto) |
| DEMO-17 | To Do | new | DEMO-16 | — | ❔ | 💡 | Cancelled odblokuje (záměrně) |

**b) `fixtures/status_proposals/`** — `next/design_demo_2.md`,
`next/design_demo_4.md`, `active/design_demo_8.md`, `active/design_demo_13.md`,
každý s hlavičkou `**Jira:** DEMO-<n>`.

**c) `fixtures/status_stav/next/`** — tři proposaly pro JIRA-less kontrolu:
`design_alfa.md` s hlavičkou `**Stav:** Test` a `Blokuje:` odkazem na
`design_beta.md`; `design_beta.md`; `design_gama.md` s `**Stav:** Design Review`.

Testy (všechny běhy **bez** `-Check`, aby asserty na ✅ nekolidovaly s hláškou
oracle „✅ Žádný nesoulad nenalezen" `:956`; očekávaný exit code 0 u všech):

1. **Jira bez `-ProposalPath`** — glyph každého tiketu dle šestého sloupce.
2. **Jira s `-ProposalPath fixtures/status_proposals`** — glyph každého tiketu
   dle sedmého sloupce. Pokrývá celou plnou rodinu (▶️ ⏳ 💡 vedle ✅ 🧪 👀 🔨 ⛔).
3. **DEMO-8 = 🧪, DEMO-13 = 👀** v obou bězích — pořadí kaskády (kroky 4 a 5
   před krokem 6).
4. **DEMO-2/DEMO-15/DEMO-17 odblokované, DEMO-4/DEMO-14 ne** — matice
   hotovosti pro plánování: Test/Review/Cancelled ano, In Progress/Design
   Review ne.
5. **DEMO-7 = 🧪 a DEMO-3 = 🔨** — case-insensitivní match bez zobecnění na
   kategorii.
6. **DEMO-9 = ⛔** — externí blokátor mimo snapshot.
7. **DEMO-10** — exit 0 a glyph z To‑Do větve (❔, resp. 💡).
8. **`-NoStatus`** potlačí 🧪, 👀 i ❔ (`Assert-NotMatch`).
9. **Vlny se nemění** — DEMO-1 ve vlně 0, DEMO-2 ve vlně 1 (assert na pozici
   buňky), shodně v obou bězích.
10. **Proposals režim** (`-Source Proposals -ProposalPath fixtures/status_stav`)
    — `**Stav:** Test` ani `**Stav:** Design Review` NEDÁ 🧪/👀: `alfa` nese ▶️
    (živý `next/`, odblokován), `beta` ⏳ (blokován alfou), `gama` ▶️. Asserty
    `Assert-NotMatch` na 🧪, 👀 a ❔.

Asserty MUSÍ být per-tiket, ne jen na výskyt glyphu ve výstupu: harness umí
`Assert-Match`/`Assert-NotMatch` nad celým reportem (`_assert.ps1:9`–`:14`),
takže `Assert-Match $out '🧪'` by prošel i tehdy, když 🧪 dostane špatný tiket.
Buňka má deterministický tvar `"$statusGlyph $(Get-Emoji $k) $keyMd $sum"`
(`:683`–`:684`), takže vzor typu `🧪 \S+ \[DEMO-1\]` je vyjádřitelný.

## Dopady

- Tabulka vln přestane blokovat práci za tikety v **Test / Review /
  Documentation** — jejich následníci se posunou na ▶️ (s návrhem) nebo 💡 (bez
  návrhu). Sloupce (vlny) se **nemění** — vlny počítá topologie `Blocks`, ne
  stavy.
- Běh bez `-ProposalPath` už netvrdí „návrh hotov": odblokované To‑Do tikety
  nesou ❔. Pro rozhodovací použití dashboardu je `-ProposalPath` doporučený
  vstup, ne volitelná ozdoba.
- Tikety v **Design Review** jsou nově odlišené (👀) a dál blokují — dashboard
  tak neposílá nikoho pracovat na tiketu, jehož návrh ještě posuzuje architekt.
- Uložené `graph.md` v `memory-bank/epics/<epic>/` se při nejbližší regeneraci
  diffnou o změněné glyphy (🆕 → 💡, ▶️ → ❔ v degradovaných bězích) —
  očekávané.
- Konzistenční oracle (`-Check`) se nemění; exit kódy zůstávají.
- Snapshot s prázdným nebo chybějícím `status` přestane skript shazovat.

## Rizika

- **Přejmenování stavu v Jiře** rozbije match podle názvu potichu (tiket by se
  začal chovat jako In Progress). Zmírnění: konstanty jsou na jednom místě
  s komentářem, který uvádí i id stavů.
- **Tiket vrácený z testu** (Test → In Progress / To Do) odblokování zase
  odebere a následník se vrátí na ⛔, resp. ⏳. Akceptováno: graf se vždy
  generuje z aktuálního snapshotu, žádný stav si nepamatuje.
- **Neúplný druhý snapshot** (fetch externích blokátorů bez `status` ve
  `fields`) degraduje tiket v Testu na blokující. Zmírnění: požadavek
  v `SKILL.md` kroku 1.
- **„Design Review" není zapojen do UMS workflow** — do té doby je krok 5
  kaskády mrtvý kód a `mb-architect-review` request fail-closed spadne. Není to
  riziko této změny, ale předpoklad, který je potřeba v Jiře doplnit.
- Riziko zobecnění na celou kategorii `indeterminate` (odblokování už při
  započetí práce) hlídá test č. 5; riziko prosáknutí do JIRA-less režimu
  test č. 10.
