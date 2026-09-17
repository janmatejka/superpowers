# Návrh: Playbook — jádro a doklad (tvar, rozpočet, triage, konsolidace)

- **Jira:** UMS-3552 (https://datasyscz.atlassian.net/browse/UMS-3552)
- **Target MB:** memory-bank/
- **Vytvořeno:** 2026-09-17
- **Blokováno:** UMS-3551

Předběžný návrh (fronta `next/`), prohloubený 2026-09-17 ve stejném sezení,
které nasbíralo evidenci. Aktivuje se po integraci UMS-3551, na kterém stojí:
Playbook Contract už bude v referenci `shared/contract/playbook-contract.md`,
citace budou mít standardní tvar a rozpočtové testy budou mít vzor. Dokument
je psaný podle pravidla, které zavádí UMS-3551: jádro v sekcích Cíl, Scope
a Technický návrh, měření v sekci Doklad na konci.

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
`Relates`, rozpočet a ráčna, triage, vyřazování, převod do kódu, vlastnictví
pastí); sdílený skript tvaru a parseru položek; harvestová brána v `mb-harvest`;
sběr kandidátů v overlay SDD (dedup); nový skill konsolidace; testy tvaru
a mechaniky; konsolidace `memory-bank/playbook.md` tohoto repa; převod dvou
už rozhodnutých lekcí na kontroly v `_assert.ps1`.

**Ven:** konsolidace playbooků monorepa (samostatně, po ověření zde — parser
ale musí jejich tvar číst už teď, viz bod 7); autonomní zápis bez člověka;
změna režimu consult-before-write; filtrování playbooku podle tasku při
dispatchi (s rozpočtem se přikládá celý).

## Technický návrh

### 1. Tvar položky a souboru

- Položka: jedno imperativní pravidlo na jednom řádku, tučně uvozené; pak
  `Proč:` na jeden řádek; pak `Důkaz:` — SHA harvestového commitu, archivovaný
  návrh (`proposals/completed/design_<slug>.md`) nebo jméno testu, který
  pravidlo hlídá. Nejvýš čtyři řádky po 80 znacích. Příklad:

  ```markdown
  - **Než spoléháš na prázdný `git diff` po obnově souboru, ověř, že je soubor
    trackovaný.** Proč: netrackovaný soubor `git diff` nevidí, prázdný výstup
    nerozezná obnovu od žádné. Důkaz: 44ccb57.
  ```

- `Proč:` cituje incident jednou větou, ne příběhem; příběh zůstává v gitu
  a v archivovaném návrhu, na které `Důkaz:` míří.
- **Sekce podle okamžiku spuštění**, ne podle tématu. Základní seznam sekcí
  je součástí reference; MB smí přidat vlastní sekci, ale jen ve tvaru „Když
  …", a nová sekce se zapíše do reference jako rozšíření základu:

  | Sekce | Co do ní patří | Dnešní nadpisy tohoto repa, které se do ní slévají |
  |---|---|---|
  | Když píšeš nebo měníš test | konvence sad, fixtures, negativita a mutace, aserce | Testy vrstvy (51 položek, z nich 22 o negativitě) |
  | Když spouštíš sadu nebo důkazní běh | smyčka sad, pracovní adresář, čtení výsledků z markerů, throwaway fixtury | Testy vrstvy (část), Git hooky (testovací běh nad hookem) |
  | Když píšeš PowerShell | pasti jazyka, kódování, kolekce, `Set-StrictMode` | PowerShell v této vrstvě (32) |
  | Když píšeš POSIX hook nebo shell | `set -f`, stdin, CR/CRLF, msys vs. POSIX | Git hooky (10), CRLF u bezpříponových skriptů (2) |
  | Když měníš kontrakt, skill nebo overlay | jeden domov pravidla, sweepy po změně, číslování kroků, pravdivost reportů a komentářů | Kontrakt a skilly (57) |
  | Když nasazuješ nebo revendoruješ | sync, obnova nasazené kopie, instalace hooků, revendor a kotvy | Nasazení vrstvy (22 včetně podsekcí), Upgrade upstreamu (5) |
  | Když píšeš plán, návrh nebo commit | ohraničovače v plánu, diakritika v commitu, briefy | Psaní plánů, návrhů a commitů (3) |

- **Rozpočet:** soubor 600 řádků, sekce 40 položek, položka 4 řádky, `Proč:`
  jeden řádek. Hlídá sdílený skript `Test-UmsPlaybookShape.ps1 -Playbook <cesta>`
  (vrací nálezy česky), volaný sadou vrstvy nad fixturami a harvestovou bránou
  nad cílovým playbookem.
- **Ráčna bez nového souboru:** dokud playbook není v rozpočtu, nese na druhém
  řádku HTML komentář `<!-- playbook-budget: 600; baseline: 2124 (2026-09-17) -->`.
  Skript tvaru čte limit jako menší z rozpočtu a baseline; soubor smí jen
  klesat. Po konsolidaci pod rozpočet se komentář odstraní a platí holý
  rozpočet. Komentář cestuje se souborem, takže ráčna platí v každém klonu.

### 2. Sběr kandidátů (overlay SDD)

- Před kopií kandidáta do `playbook-candidates/<slug>.md` controller porovná
  jeho `Procedure` s existujícími kandidáty i s playbookem a zapíše pole
  `Relates: <položka> (rozšiřuje | duplikuje | nahrazuje)`, když shoda
  existuje; `Corrects` zůstává jako zvláštní případ „nahrazuje".
- Kandidát, který duplikuje jiného kandidáta v souboru, se nezapíše; controller
  to ohlásí v reportu.
- **Mechanická opora je omezená na jazykově neutrální tokeny.** Kandidáti jsou
  anglicky, playbook česky, takže shoda slov nefunguje; sdílený skript
  `Find-UmsPlaybookMatch.ps1 -Text <procedure> -Playbook <cesta>` porovnává
  jen identifikátory v backticks (příkazy, přepínače, soubory, funkce) a vrací
  až tři kandidátní položky; rozhodnutí o vztahu zůstává úsudkem controllera.

### 3. Harvestová brána (mb-harvest)

- Brána předkládá **tabulku dispozic**, ne seznam textů. Připraví ji analytik
  na nejlevnějším schopném tieru (Dispatch Model Policy) podle briefu, který
  je součástí reference; člověk schvaluje tabulku a smí přebít řádek.

  | # | Kandidát | Původ (task) | Cena nepřítomnosti | Existující položka | Dispozice | Kritérium | M/Ú | Selhání |
  |---|---|---|---|---|---|---|---|---|

  `Dispozice` má právě jednu z pěti hodnot: `nový (sekce)` / `sloučit do
  <položka>` / `nahrazuje <položka>` / `do kódu <kde>` / `zahodit <důvod>`.
  `M/Ú` říká, zda rozhodlo mechanické kritérium (1, 2, 4) nebo úsudek (3, 5
  až 8). `Selhání` je `hlasité`, když by sezení řídící se špatnou verzí
  pravidla narazilo na viditelné selhání, jinak `tiché`.
- **Kritéria v pořadí aplikace** (levná a mechanická napřed; převzatá
  z triage UMS-3505, Doklad „Triage UMS-3505"):
  1. Duplicita uvnitř hromady — shlukovat podle tématu, ne podle tasku původu.
  2. Duplicita proti playbooku — už pokryto → zahodit; rozšiřuje → sloučit do;
     jinak nový. `Corrects`/`Relates` musí jmenovat existující položku.
  3. Dosah — platí mimo tuto pracovní položku? Vázaný na jediný commit nebo
     nález je podezřelý, pokud se nezobecňuje.
  4. Operační tvar — `Procedure` je operace („před Y ověř X"), ne úsudek
     („dej pozor na X"); neoperativní → zahodit, nebo jednou větou přepsat.
  5. Cena nepřítomnosti — z `Happened`: skutečná (pád sezení, falešná zelená,
     bezpečnostní díra, ztracený soubor) vs. kosmetická; řadí a rozhoduje
     hraniční případy.
  6. Spouštěč — je přirozený okamžik, kdy si sezení pravidlo vybaví? A hlavně:
     bylo by to lepší jako kód? Lint, aserce v `_assert.ps1`, kontrola ve
     skriptu → `do kódu`.
  7. Domov — fakt patří do `tech.md`, pravidlo do kontraktu, postup do
     playbooku (viz bod 6).
  8. Čistá cena kontextu — playbook má stejnou velikost nebo menší; `nahrazuje`
     má větší cenu než stejný obsah jako položka navíc; u `nový` jmenuj sekci
     a preferuj `sloučit do`, má-li sekce blízkého sousedа.
- `sloučit do` přepisuje existující položku na jeden řádek pravidla plus
  `Proč:`; `nahrazuje` starou položku odstraní a zapíše ji do seznamu
  vyřazených; `do kódu` zapíše test nebo kontrolu a položku do playbooku
  nepřidá; kandidát shodný s vyřazeným pravidlem dostane `zahodit (vyřazeno)`,
  pokud nenese nové `Happened`.
- Po zápisu brána spustí skript tvaru; nález zastaví harvest před commitem.

### 4. Seznam vyřazených a převod do kódu

- `playbook-retired.md` vedle playbooku: jeden řádek na vyřazené pravidlo:
  `- <první slova pravidla> — <nahrazeno «položka» | hlídá test <sada> |
  neplatí od <commit>> (<YYYY-MM-DD>)`. Brána i konsolidace ho čtou, aby se
  vyřazené pravidlo znovu nenaučilo; skript tvaru hlídá jen jeho řádkový tvar.
- Pravidlo ověřitelné strojově se převede na test a z playbooku odejde; dvě
  už rozhodnuté lekce z triage UMS-3505 jsou první: (a) každý `Assert-*`
  volaný v `*.tests.ps1` existuje v sesterském `_assert.ps1` — chybějící
  helper se v RED běhu tváří jako očekávaný RED; (b) každá `*.tests.ps1`,
  která dot-sourcuje svůj předmět, nastavuje `$ErrorActionPreference = 'Stop'`.
  Obojí je grep nad `ums/**/tests/*.tests.ps1` jako vlastní sada
  `tests-hygiene.tests.ps1` ve `shared/tests/`.

### 5. Konsolidační skill `mb-playbook-consolidate`

- Read-only průchod playbookem a seznamem vyřazených; výstupem je tabulka
  návrhů `| # | Položka | Návrh | Kritérium | Do | Pozn. |` s návrhy `ponechat`
  / `sloučit do <položka>` / `vyřadit (<důvod>)` / `přesunout do tech.md` /
  `převést na test <kde>` a kritériem `duplicita` / `přesah` / `jednorázový
  incident` / `převoditelné do kódu` / `špatný domov` / `nad rozpočet sekce`.
  Člověk schvaluje tabulku; zápis, skript tvaru a commit přes `mb-git-commit`
  jako v bráně. Nikdy nepushuje sdílenou větev.
- Spouští se ručně, nebo když skript tvaru zčervená; nikdy automaticky.
- Mechanickou část nese skript `consolidate-playbook.ps1` se třemi režimy:
  `-Parse` (JSON položek: id, sekce, první slova, řádek pravidla, `Proč:`,
  `Důkaz:`, počet řádků; čte oba tvary položek — tučně uvozené odrážky
  i položky pod `###` nadpisem, které mají playbooky monorepa), `-Apply
  <decisions.json>` (provede schválené verdikty a přepíše soubor), `-Baseline`
  (zapíše nebo aktualizuje ráčnový komentář). Úsudkovou část nese dispatch
  analytika na nejlevnějším schopném tieru se stejným briefem jako brána.
- Testy: parser nad fixturami obou tvarů, `-Apply` nad fixturou s pěti verdikty
  a kontrolou, že neschválené položky zůstaly doslova, ráčna nad fixturou nad
  i pod rozpočtem.

### 6. Vlastnictví pastí prostředí

- Past prostředí má dva domovy podle druhu věty: **fakt o platformě** patří do
  `tech.md`, sekce „Pasti prostředí" (co PowerShell, git nebo msys dělá);
  **postup** patří do playbooku (co uděláš, aby tě to nepotkalo), s `Důkaz:`
  ukazujícím na `tech.md`. Nikdy obojí na obou místech.
- První konsolidace rozřeší čtyři dnešní duplicity: pasti `Set-StrictMode`
  nad kolekcemi a návratovými hodnotami, Git Bash vs. WSL stub, cíl git hooku
  přes `git rev-parse --git-path`, UTF-8 round trip přes PowerShell do gitu.

### 7. Akceptace na tomto repu a příprava monorepa

- Konsolidace `memory-bank/playbook.md` (2 124 řádků, 182 položek) nad
  schválenou tabulkou do rozpočtu: odhad po sloučení duplicitních shluků a
  zkrácení `Proč:` je 110 až 130 položek, tedy 400 až 500 řádků; sekce podle
  okamžiku spuštění; vyřazené v seznamu; skript tvaru zelený bez ráčny.
- Postup je dvoukolový: nejprve mechanický přepis tvaru (zkrácení `Proč:` na
  větu, doplnění `Důkaz:` ze SHA harvestového commitu podle `git log -S`),
  pak tabulka sloučení a vyřazení. Obě kola schvaluje člověk nad tabulkou,
  druhé kolo je ten test, který ověří, že brána i konsolidace unesou reálnou
  velikost.
- Parser a skript tvaru se ověří i nad kopií `KicWorkflow/memory-bank/playbook.md`
  z monorepa (3 223 řádků, 185 nadpisů `###`) jen v režimu `-Parse`, bez
  zápisu — aby pozdější konsolidace monorepa nezačínala opravou parseru.

## Dopady

- **Reference `contract/playbook-contract.md`** (vytvořená UMS-3551) se
  přepisuje: tvar položky, sekce, `Relates`, rozpočet a ráčna, kritéria triage
  a brief analytika, seznam vyřazených, převod do kódu, vlastnictví pastí.
  Jádro kontraktu se nemění, kromě řádku dna pro playbook, který přidá
  UMS-3551.
- **Skripty a testy:** `shared/scripts/Test-UmsPlaybookShape.ps1`,
  `Find-UmsPlaybookMatch.ps1`; `mb-playbook-consolidate/scripts/consolidate-playbook.ps1`;
  sady `playbook-shape.tests.ps1`, `playbook-match.tests.ps1`,
  `consolidate.tests.ps1`, `tests-hygiene.tests.ps1`.
- **Skilly a overlaye:** `mb-harvest` (brána v2), overlay SDD (dedup při
  sběru, `Relates`), nový skill `mb-playbook-consolidate`, `SKILLS_MANIFEST.md`.
- **Memory Bank tohoto repa:** `playbook.md` a `playbook-retired.md`,
  `tech.md` (pasti), `architecture.md` (dokumentová vrstva).

## Rizika

- **Ztráta pravidla při konsolidaci.** Kryje dvoukolový postup, schválení
  tabulky a `git`: každé vyřazení má řádek v seznamu vyřazených s důvodem.
- **Falešný `Happened` v kandidátovi.** Triage ho neodhalí (UMS-3505 #15);
  kryje jen pozdější měření a `Důkaz:` odkaz, který jde ověřit.
- **Ráčna schovaná v komentáři se ztratí přepisem souboru.** Skript tvaru
  bez komentáře uplatní holý rozpočet, tedy zčervená; ztráta je hlasitá.
- **Parser monorepo tvaru.** Ověřuje se nad reálnou kopií už zde.

## Doklad

| Měření | Hodnota | Podmínky |
|---|---|---|
| Playbook tohoto repa | 2 124 řádků, 171 odrážek `- **`, 182 položek včetně číslovaných, 10 nadpisů; dvě sekce nesou 63 % textu | 0a13ef1, 2026-09-17 |
| Růst | +2 200 / −76 řádků za 45 dní; 12 z 15 commitů jsou harvesty a nesou 92 % přírůstku; 6 položek kdy smazáno | `git log --numstat`, 2026-09-17 |
| Duplicity v souboru | nejméně 5 shluků: 9 položek o grep sweepu, 4 o CRLF, 3 „ověř v tomto běhu", 4 o pořadí STOPů, 2 páry „nahrazeno, ale ponecháno" | analytik 2026-09-17 |
| Vazba na jeden incident | 165 z 182 `Proč:` cituje právě jeden incident; asi 53 položek vázaných na artefakty vrstvy, asi 79 obecně znějících, ale jednoincidentních, asi 50 přenositelných | tamtéž |
| Duplicity tech.md × playbook | 4 témata pastí na obou místech; exit kód 4 instalátoru v `tech.md`, ale ne v playbooku, kam `tech.md` odkazuje | tamtéž |
| Mechanismus harvestu | jediný vztah mezi položkami je `Corrects` s verdikty nahradit / ponechat obojí / zahodit; žádný krok neslučuje, nemaže, nezařazuje, neměří | `mb-harvest/SKILL.md`, kontrakt 2.19 |
| Dispatch | celý playbook se přikládá ke každému dispatchi implementátora | overlay SDD, řádky 110–117 |
| Monorepo | 23 playbooků, 7 478 řádků; KicWorkflow 3 223 řádků se 185 nadpisy `###` za 6 týdnů, smazáno 2,9 %; SMSInfo3 1 446 řádků se 133 nadpisy `##` | `d:\_datasys\ums`, `develop`, 2026-09-17 |
| Zkušenost správce UMS-3517 | sezení UMS-3518 při mergi nahlásilo plochý playbook přes 150 položek a samo ho rozdělilo do sekcí | zpráva správce, 2026-09-17 |

### Triage UMS-3505

Dataset `.superpowers/playbook-triage-dataset/ums_3505/` (git-ignored, jen
tento stroj), rozhodnutí 2026-09-08:

- 50 kandidátů, 10 shluků → 17 nových, 24 sloučení, 2 převody do kódu,
  7 zahození; člověk rozhodl 7 výslovných otázek a jedno přebití nad tabulkou,
  ne nad 1 005 řádky zdroje.
- Shoda člověka s návrhem agenta 49 z 50 řádků; jediné přebití bylo v řádku,
  který analytik sám označil za nerozhodnutý.
- Analytik označil 38 řádků jako mechanické a 12 jako úsudkové, ale sám
  varoval, že skutečně mechanicky rozhodnutelných bylo asi 8 z 50 — párování
  anglických kandidátů proti českému playbooku je sémantická práce.
- Hlasité vs. tiché selhání 19 / 31; tiché soustředěno ve shluku negativity
  a mutací (8 z 11). „Použití ověří" dosáhne nejvýš na 19.
- Jeden kandidát měl nepravdivý `Happened`; opravilo ho až pozdější
  nezávislé přeměření, ne triage.
- 5 přímých duplikátů uvnitř hromady, 1 už pokrytý, 52 % kandidátů se dotýká
  existující položky; zdrojem duplicit bylo řazení souboru podle tasku
  (dvojice 360 a 440 řádků od sebe).
- Do kódu 2 z 50 plus 3 hraniční.

Mechanismy převzaté z rešerše 2026-09-17: triage při zápisu (mem0
ADD / UPDATE / DELETE / NONE, Claude Code „neukládej odvoditelné"), index a
detail (Claude Code MEMORY.md, Zettelkasten, Anthropic progressive disclosure),
rozpočet vynucený testem (limit indexu Claude Code 200 řádků, Cursor 500 řádků,
SKILL.md 500 řádků), nahrazení místo tichého smazání (ADR superseded),
pravidelná konsolidace s pojmenovanými kritérii (Wikipedia merge: duplicate /
overlap; Anthropic consolidate-memory), pravidlo tvaru položky (VS Code:
jedna prostá věta plus důvod).
