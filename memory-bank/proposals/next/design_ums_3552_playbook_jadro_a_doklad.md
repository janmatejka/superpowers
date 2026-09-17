# Návrh: Playbook — jádro a doklad (tvar, rozpočet, triage, konsolidace)

- **Jira:** UMS-3552 (https://datasyscz.atlassian.net/browse/UMS-3552)
- **Target MB:** memory-bank/
- **Vytvořeno:** 2026-09-17
- **Blokováno:** UMS-3551

Předběžný návrh (fronta `next/`), škálovaný na to, co je známé. Aktivuje se
po integraci UMS-3551, na kterém stojí: Playbook Contract už bude v referenci
`shared/contract/playbook-contract.md` a rozpočtové testy budou mít vzor.

## Cíl

1. Zastavit append-only růst playbooků: každý harvest dnes přidává, nic
   neslučuje, nemaže, nezařazuje do sekce ani neměří velikost.
2. Dát playbooku tvar, který se čte celý a levně: jednořádková pravidla
   v sekcích podle okamžiku spuštění, důkaz odkazem.
3. Udělat z triage kandidátů standardní krok harvestu a z konsolidace
   opakovatelný, člověkem schvalovaný průchod.
4. Aplikovat na playbook tohoto repa jako akceptační test.

## Scope

**Dovnitř:** Playbook Contract v referenci (tvar položky, sekce, pole
`Relates`, rozpočet, triage, vyřazování, převod do kódu); harvestová brána
v `mb-harvest`; sběr kandidátů v overlay SDD (dedup); nový skill konsolidace;
testy tvaru a mechaniky; konsolidace `memory-bank/playbook.md` tohoto repa;
převod dvou už rozhodnutých lekcí na kontroly v `_assert.ps1`.

**Ven:** konsolidace playbooků monorepa (samostatně, po ověření zde);
autonomní zápis bez člověka; změna režimu consult-before-write.

## Technický návrh

### 1. Tvar položky a souboru

- Položka: jedno imperativní pravidlo na jednom řádku, tučně uvozené; pak
  `Proč:` na jeden řádek; pak odkaz na důkaz — SHA harvestového commitu,
  archivovaný návrh, nebo test, který pravidlo hlídá. Nejvýš čtyři řádky.
- Sekce podle **okamžiku spuštění**, ne podle tématu: „Když píšeš test",
  „Když spouštíš sadu", „Když edituješ kontrakt nebo skill", „Když nasazuješ
  vrstvu", „Když commituješ nebo píšeš plán", „Když píšeš PowerShell",
  „Když píšeš POSIX hook". Seznam sekcí je součástí reference; nová sekce je
  změna reference.
- `Proč:` cituje incident, ne příběh; příběh zůstává v gitu a v archivovaném
  návrhu, na které odkaz míří.
- Rozpočet souboru 600 řádků, sekce do 40 položek. Test `playbook-shape.tests.ps1`
  hlídá oba rozpočty, délku položky a jednořádkové `Proč:`.
- **Ráčna:** dokud playbook není v rozpočtu, test drží baseline v souboru
  `.superpowers/playbook-baseline.json` nebo vedle sady a selže, když soubor
  vyroste nad baseline; po konsolidaci baseline klesne na rozpočet.

### 2. Sběr kandidátů (overlay SDD)

- Před kopií kandidáta do `playbook-candidates/<slug>.md` controller
  porovná jeho `Procedure` s existujícími kandidáty i s playbookem a zapíše
  pole `Relates: <položka> (rozšiřuje | duplikuje | nahrazuje)`, když shoda
  existuje; `Corrects` zůstává jako zvláštní případ „nahrazuje".
- Kandidát, který duplikuje jiného kandidáta v souboru, se nezapíše; controller
  to ohlásí v reportu.

### 3. Harvestová brána (mb-harvest)

- Brána předkládá **tabulku dispozic**, ne seznam textů: řádek na kandidáta
  s verdiktem `nový` / `sloučit do <položka>` / `nahrazuje <položka>` /
  `do kódu <kde>` / `zahodit <důvod>`, kritériem, které rozhodlo, a odhadem
  hlasitého či tichého selhání.
- Tabulku připraví analytik na nejlevnějším schopném tieru (Dispatch Model
  Policy); člověk schvaluje tabulku a smí přebít řádek. Kritéria a jejich
  pořadí jsou v referenci (převzatá z triage UMS-3505).
- `sloučit do` přepisuje existující položku na jeden řádek pravidla plus
  `Proč:`; `nahrazuje` starou položku odstraní a zapíše ji do seznamu
  vyřazených; `do kódu` zapíše test nebo kontrolu a položku do playbooku
  nepřidá.
- Po zápisu brána spustí `playbook-shape.tests.ps1`; červená sada zastaví
  harvest před commitem.

### 4. Seznam vyřazených a převod do kódu

- `playbook-retired.md` vedle playbooku: jeden řádek na vyřazené pravidlo
  s důvodem (`nahrazeno <položka>`, `hlídá test <sada>`, `neplatí od
  <commit>`). Brána i konsolidace ho čtou, aby se vyřazené pravidlo znovu
  nenaučilo.
- Pravidlo ověřitelné strojově se převede na test a z playbooku odejde; dvě
  už rozhodnuté lekce z triage UMS-3505 (existence každého volaného
  `Assert-*` helperu v sesterském `_assert.ps1`; `$ErrorActionPreference =
  'Stop'` v každé sadě, která dot-sourcuje svůj předmět) jsou první dvě.

### 5. Konsolidační skill

- Nový skill `mb-playbook-consolidate`: read-only průchod playbookem a
  seznamem vyřazených, výstupem je tabulka návrhů sloučení, rozdělení a
  vyřazení s pojmenovaným kritériem (duplicita, přesah, jednorázový incident,
  převoditelné do kódu, špatný domov); člověk schvaluje tabulku; zápis a
  test tvaru jako v bráně.
- Spouští se ručně, nebo když test tvaru zčervená; nikdy automaticky.
- Mechanická část (parser položek, shlukování podle sekce a slov, baseline,
  zápis) má vlastní sadu; úsudková část je dispatch analytika.

### 6. Akceptace na tomto repu

- Konsolidace `memory-bank/playbook.md` (2 124 řádků, 171 až 182 položek)
  do rozpočtu nad schválenou tabulkou; sekce podle okamžiku spuštění;
  vyřazené v seznamu; test tvaru zelený bez ráčny.
- Duplicity v `tech.md`, sekce „Pasti prostředí", proti playbooku se vyřeší
  podle vlastnictví faktu (past prostředí patří do `tech.md`, postup do
  playbooku), ne oběma.

## Doklad

| Měření | Hodnota | Podmínky |
|---|---|---|
| Playbook tohoto repa | 2 124 řádků, 171 odrážek `- **`, 10 nadpisů; dvě sekce nesou 63 % textu | 0a13ef1, 2026-09-17 |
| Růst | +2 200 / −76 řádků za 45 dní; 12 z 15 commitů jsou harvesty a nesou 92 % přírůstku; 6 položek kdy smazáno | `git log --numstat`, 2026-09-17 |
| Duplicity v souboru | nejméně 5 shluků: 9 položek o grep sweepu, 4 o CRLF, 3 „ověř v tomto běhu", 4 o pořadí STOPů, 2 páry „nahrazeno, ale ponecháno" | analytik 2026-09-17 |
| Vazba na jeden incident | 165 z 182 `Proč:` cituje právě jeden incident; asi 53 položek vázaných na artefakty vrstvy, asi 79 obecně znějících, ale jednoincidentních | tamtéž |
| Mechanismus harvestu | jediný vztah mezi položkami je `Corrects` s verdikty nahradit / ponechat obojí / zahodit; žádný krok neslučuje, nemaže, nezařazuje, neměří | `mb-harvest/SKILL.md`, kontrakt 2.19 |
| Dispatch | celý playbook se přikládá ke každému dispatchi implementátora | overlay SDD, řádky 110–117 |
| Triage UMS-3505 | 50 kandidátů → 17 nových, 24 sloučení, 2 do kódu, 7 zahozeno; 52 % se dotýká existující položky; člověk souhlasil v 49 z 50 řádků a četl souhrn a šest řádků; skutečně mechanicky rozhodnutelných asi 8 z 50; jeden kandidát s nepravdivým `Happened` | `.superpowers/playbook-triage-dataset/ums_3505/`, 2026-09-08 |
| Monorepo | 23 playbooků, 7 478 řádků; KicWorkflow 3 223 řádků za 6 týdnů, smazáno 2,9 %; SMSInfo3 1 446 řádků se 133 nadpisy `##` | `d:\_datasys\ums`, `develop`, 2026-09-17 |
| Zkušenost správce UMS-3517 | sezení UMS-3518 při mergi nahlásilo plochý playbook přes 150 položek a samo ho rozdělilo do sekcí | zpráva správce, 2026-09-17 |

Mechanismy převzaté z rešerše: triage při zápisu (mem0, Claude Code „neukládej
odvoditelné"), index a detail (Claude Code, Zettelkasten, Anthropic
progressive disclosure), rozpočet vynucený testem (limit indexu Claude Code,
Cursor 500 řádků, SKILL.md 500 řádků), nahrazení místo tichého smazání (ADR
superseded), pravidelná konsolidace s pojmenovanými kritérii (Wikipedia
merge: duplicate / overlap; Anthropic consolidate-memory). Rešerše
2026-09-17.
