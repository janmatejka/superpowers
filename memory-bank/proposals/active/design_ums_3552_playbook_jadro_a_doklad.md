# Návrh: Playbook — jádro a doklad (tvar, strom, rozpočet, triage, konsolidace)

- **Jira:** UMS-3552 (https://datasyscz.atlassian.net/browse/UMS-3552)
- **Target MB:** memory-bank/
- **Vytvořeno:** 2026-09-17
- **Aktivováno:** 2026-09-23

Předběžný návrh z fronty `next/`, aktivovaný po integraci UMS-3551 a rozšířený
v brainstormingu 2026-09-23 o dvě věci: dědění playbooků po stromu Memory Bank,
aby se pravidla neopakovala v jednotlivých MB, a režim konsolidace napříč všemi
MB monorepa. UMS-3551 dodal, na čem návrh stojí: Playbook Contract v referenci
`shared/contract/playbook-contract.md`, standardní tvar citací a vzor
rozpočtových testů. Dokument drží pravidlo UMS-3551: jádro v sekcích Cíl, Scope
a Technický návrh, měření v sekci Doklad na konci.

## Cíl

1. Zastavit append-only růst playbooků: každý harvest dnes přidává, nic
   neslučuje, nemaže, nezařazuje do sekce ani neměří velikost.
2. Dát playbooku tvar, který se čte celý a levně: jednořádková pravidla
   v sekcích podle okamžiku spuštění, důkaz odkazem.
3. Zavést dědění po stromu Memory Bank: pravidlo žije jednou, v nejnižším
   společném předkovi MB, kde platí, a každý soubor jednoznačně říká, zda
   pravidlo platí pro celý podstrom, nebo jen pro vlastní projekt.
4. Udělat z triage kandidátů standardní krok harvestu a z konsolidace
   opakovatelný, člověkem schvalovaný průchod — pro jednu MB i pro celý strom.
5. Aplikovat na playbook tohoto repa jako akceptační test velikosti a nanečisto
   na strom monorepa jako akceptační test stromu.

## Scope

**Dovnitř:**

- Playbook Contract v referenci: tvar souboru (dvě části, sekce „Když …"),
  tvar položky, pole `Relates`, rozpočet souboru i řetězce a ráčna, kritéria
  triage a brief analytika, seznam vyřazených, převod do kódu, vlastnictví
  pastí, čtení řetězce po stromu.
- Změna jádra kontraktu: pravidlo čtení kontextu MB (MB Context Reading Rule)
  čte řetězec místo jednoho playbooku; harvest smí zapsat playbook předka
  (rozšíření `AFFECTED_MBS`, viz Technický návrh bod 5); jmenovaná výjimka
  Scope Lock pro konsolidaci (bod 8).
- Legacy režim pro playbooky ve starém tvaru, aby nasazení nezablokovalo
  harvesty v monorepu (bod 3).
- Přizpůsobení všech čtenářů a zapisovatelů playbooku (bod 2), včetně
  `mb-init` (postupy build a test) a `mb-git-commit` (staging schválené dávky).
- Oprava stávajících testovacích sad, které porušují pravidlo sady hygieny
  (bod 6).
- Sdílené skripty `Get-UmsPlaybookChain.ps1`, `Test-UmsPlaybookShape.ps1`,
  `Find-UmsPlaybookMatch.ps1`.
- Harvestová brána v `mb-harvest`; sběr kandidátů v overlay SDD (dedup proti
  řetězci) a přiložení řetězce k dispatchi.
- Nový skill `mb-playbook-consolidate` s režimem jedné MB a režimem `-Tree`.
- Testy tvaru, řetězce a mechaniky nad fixturami; převod dvou už rozhodnutých
  lekcí na sadu `tests-hygiene.tests.ps1`.
- Konsolidace `memory-bank/playbook.md` tohoto repa: pod práh, nebo s ráčnou
  a eskalačním reportem (bod 10).
- Běh `-Tree` nanečisto nad monorepem (bez zápisu) jako doklad.

**Ven:**

- Skutečná konsolidace playbooků monorepa — spustí ji uživatel na vlastním
  tiketu po nasazení vrstvy.
- Doménové playbooky mimo strom (explicitní graf) — odložené rozšíření, viz
  sekce „Odložená rozšíření".
- Autonomní zápis bez člověka; změna režimu consult-before-write.
- Filtrování řetězce podle tasku při dispatchi (s rozpočtem se přikládá celý).

## Technický návrh

### 1. Tvar souboru a položky

Každý `playbook.md` má nejvýš dvě části druhé úrovně a v nich sekce podle
okamžiku spuštění:

```markdown
# Playbook — <jméno MB>

## Pro celý podstrom
### Když píšeš nebo měníš test
- **Pravidlo na jednom řádku.** Proč: jedna věta. Důkaz: <SHA | návrh | test>.
### Když píšeš SQL skript nebo migraci
…

## Jen pro tento projekt
### Když spouštíš sadu nebo důkazní běh
…
```

- **Část** říká, komu pravidlo platí; **sekce** říká, kdy si ho sezení má
  vybavit. V novém tvaru jsou obě osy povinné — položka mimo část nebo mimo
  sekci je nález skriptu tvaru. Soubor ve starém tvaru se řídí legacy režimem
  (bod 3).
- **Nový tvar poznáš mechanicky:** soubor obsahuje aspoň jeden z doslovných
  nadpisů `## Pro celý podstrom` / `## Jen pro tento projekt` a žádný jiný
  nadpis druhé úrovně. Cokoli jiného — včetně playbooků, které nadpisy `##`
  používají jako položky (kořen monorepa) — je starý tvar.
- **Kořenový playbook** (`<MB_ROOT>/memory-bank/playbook.md`) nese hlavně část
  „Pro celý podstrom". Smí nést i „Jen pro tento projekt": platí jen pro práci
  připnutou přímo na kořenovou MB a žádný potomek ji nečte — to je případ
  repozitářů s jedinou MB, kde je kořen `CTX_DIR` i `PLAN_MB` (jako tento
  fork). V monorepu, kde kořen je jen orchestrační, zůstane prázdná.
- **Listový playbook** (MB bez potomka s playbookem) má typicky jen část „Jen
  pro tento projekt". Pravidlo, které v listu platí šíř, patří k předkovi
  a konsolidace ho tam přesune.
- **Mezilehlý playbook** (MB, pod kterou leží další MB s playbookem) nese obě
  části. Právě tady rozdělení rozhoduje: bez něj by potomci četli pravidla
  cizího projektu (Doklad, „Strom vs. dvě úrovně").
- **Sekce podle okamžiku spuštění**, ne podle tématu. Základní seznam je
  součástí reference; MB smí přidat vlastní sekci, ale jen ve tvaru „Když …",
  a nová sekce se zapíše do reference jako rozšíření základu. Výchozí mapování
  dnešních nadpisů tohoto repa:

  | Sekce | Co do ní patří | Dnešní nadpisy tohoto repa, které se do ní slévají |
  |---|---|---|
  | Když píšeš nebo měníš test | konvence sad, fixtures, negativita a mutace, aserce | Testy vrstvy (51 položek, z nich 22 o negativitě) |
  | Když spouštíš sadu nebo důkazní běh | smyčka sad, pracovní adresář, čtení výsledků z markerů, throwaway fixtury | Testy vrstvy (část), Git hooky (testovací běh nad hookem) |
  | Když píšeš PowerShell | pasti jazyka, kódování, kolekce, `Set-StrictMode` | PowerShell v této vrstvě (32) |
  | Když píšeš POSIX hook nebo shell | `set -f`, stdin, CR/CRLF, msys vs. POSIX | Git hooky (10), CRLF u bezpříponových skriptů (2) |
  | Když měníš kontrakt, skill nebo overlay | jeden domov pravidla, sweepy po změně, číslování kroků, pravdivost reportů a komentářů | Kontrakt a skilly (57) |
  | Když nasazuješ nebo revendoruješ | sync, obnova nasazené kopie, instalace hooků, revendor a kotvy | Nasazení vrstvy (22 včetně podsekcí), Upgrade upstreamu (5) |
  | Když píšeš plán, návrh nebo commit | ohraničovače v plánu, diakritika v commitu, briefy | Psaní plánů, návrhů a commitů (3) |

  Sekce, která po kole 2 konsolidace pořád přesahuje 40 položek, se rozdělí na
  užší sekce „Když …" — dnešní „Testy vrstvy" (51) a „Kontrakt a skilly" (57)
  jsou první kandidáti (například „Když píšeš negativní test nebo mutaci",
  „Když měníš skill nebo overlay").
- **Dva druhy položek.** Obojí žije v sekcích „Když …" a počítá se do rozpočtu:
  - **Pravidlo** — to, čím playbook hlavně je; tvar níže, nejvýš 4 řádky.
  - **Postup** — tučný název na vlastním řádku, pak nejvýš 15 řádků kroků,
    blok příkazů nebo tabulka parametrů, a `Proč:` a `Důkaz:` jako u pravidla,
    je-li co doložit. Nese to, co pravidlo neunese: build a test příkazy,
    instalaci hooků, obnovu nasazení. `mb-init` zakládá detekované build
    a test příkazy jako postupy v sekci „Když stavíš nebo spouštíš testy"
    a baseline krok SDD je čte odtud.
- **Pravidlo:** jedno imperativní pravidlo na jednom řádku, tučně uvozené; pak
  `Proč:` na jednu větu; pak `Důkaz:` — SHA harvestového commitu, archivovaný
  návrh (`proposals/completed/design_<slug>.md`), jméno testu, který pravidlo
  hlídá, nebo u nové položky slug jejího návrhu (`Důkaz: návrh <slug>`),
  protože harvestový commit v okamžiku zápisu ještě neexistuje. Nejvýš čtyři
  řádky po 80 znacích. Příklad:

  ```markdown
  - **Než spoléháš na prázdný `git diff` po obnově souboru, ověř, že je soubor
    trackovaný.** Proč: netrackovaný soubor `git diff` nevidí, prázdný výstup
    nerozezná obnovu od žádné. Důkaz: 44ccb57.
  ```

- `Proč:` cituje incident jednou větou, ne příběhem; příběh zůstává v gitu
  a v archivovaném návrhu, na které `Důkaz:` míří. Skript tvaru kontroluje
  „jednu větu" jen heuristicky (délka a počet tečkou ukončených úseků mimo
  běžné zkratky) a hlásí ji jako varování, nikdy jako tvrdý nález.

### 2. Řetězec playbooků ve stromu MB

- **Strom MB** je strom adresářů: MB `A` je předkem MB `B`, když adresář, který
  `A/memory-bank/` obsahuje, je předkem adresáře, který obsahuje
  `B/memory-bank/`. Kořen je `<MB_ROOT>/memory-bank/`. Strom se odvozuje z cest,
  nikdy se neudržuje ručně a nemá žádnou syntaxi v souborech.
- **Které adresáře jsou MB:** jen ty, jejichž `playbook.md` (případně legacy
  `tasks.md`) git trackuje (`git ls-files`), takže git-ignorované kopie typu
  `DistOut/Iso/Work/**` se nezapočítají; adresář `memory-bank/` vnořený uvnitř
  jiného `memory-bank/` se ignoruje (v monorepu existuje prázdný vnořený
  `PCInfo/memory-bank/MobilChange/SMSInfo3/PCInfo/memory-bank/`). Pro předky
  platí totéž: MB bez trackovaného playbooku se v řetězci přeskočí.
- **Řetězec MB `X`** je to, co sezení pracující v `X` čte: od každého předka
  s playbookem, kořen první, jen část „Pro celý podstrom"; z `X` obě části.
  Předek bez playbooku se přeskočí.
- **Sdílený skript** `shared/scripts/Get-UmsPlaybookChain.ps1 -Mb <cesta>`
  vrací seřazený seznam úseků (soubor, část, rozsah řádků); s `-Out` zapíše
  sestavený text s hlavičkou každého úseku (odkud pravidlo pochází) do
  `.superpowers/playbook-chain/<mb>.md` a vrátí tu cestu. Git-ignorovaný
  scratch, generovaný znovu při každém použití, takže nic neobnovitelného.
- **Čtenáři řetězce** — všichni, kdo dnes čtou playbook cílové MB (soupis
  grepem, oponentura 2026-09-23):
  - pravidlo čtení kontextu MB (brainstorming, writing-plans) — mění se jádro
    kontraktu;
  - overlay SDD — dispatch implementátora dnes dostává cestu k playbooku;
    nově dostane cestu k sestavenému řetězci z `-Out`, obsah se do promptu
    nevkládá; baseline krok SDD čte build a test postupy z řetězce;
  - `mb-architect-review` (oponent a architekt dostávají playbook cílové MB)
    a reference `contract/architect-review.md`;
  - `mb-epic-elaboration` (protokol čte playbook dotčených MB);
  - harvestová brána a sběr kandidátů — dedup proti tomu, co už předkové říkají;
  - konsolidační skill.
- **Zapisovatelé mimo harvest a konsolidaci** se přizpůsobí novému tvaru:
  `mb-init` zakládá playbook v novém tvaru (postupy build a test, bod 1);
  `mb-sync` navrhuje opravy jen v playbooku své MB, ale jmenuje část a sekci;
  `mb-migrate-docs` při přejmenování `tasks.md` na `playbook.md` tvar nemění
  (to je práce konsolidace).
- **Zpětná kompatibilita.** Playbook bez částí (dnes všech 23 v monorepu i ten
  v tomto repu) se čte jako „Jen pro tento projekt"; kořen bez částí se čte celý
  jako „Pro celý podstrom". Nic, co se dnes dědí, se neztratí — dnes se nedědí
  nic —, předek ve starém tvaru jen dětem zatím nic nepředá, dokud ho
  konsolidace nerozdělí. Legacy `tasks.md` v roli playbooku se čte stejně
  (kontrakt, Legacy shape tolerance).

### 3. Rozpočet a ráčna

- **Rozpočet souboru:** 600 řádků, sekce 40 položek, položka 4 řádky, `Proč:`
  jedna věta.
- **Rozpočet řetězce:** 900 řádků — to, co sezení v dané MB skutečně čte.
  Kontrola řetězce běží pro každou MB v repu, takže nafouknutý kořen nebo
  podstromová část mezilehlé MB se ukáže u všech jejích potomků najednou.
- **Rozpočet je eskalační práh, ne kritérium úspěchu.** Překročení souboru ani
  řetězce není tvrdý nález, je to varování s velikostí. Říká, že playbook
  pravděpodobně nese obsah, který by měl žít jinde. Konsolidace, která práh
  nedosáhne bez ztráty pravidel stojících za svou cenu, končí **eskalačním
  reportem** (bod 8) — pokynem řešit část obsahu jiným nástrojem než
  playbookem —, ne škrtáním pod práh za každou cenu.
- **Tvrdé nálezy** skriptu tvaru jsou jen tři, všechny u souboru v novém tvaru:
  porušení tvaru (bod 1), růst nad ráčnu bez zaznamenaného lidského rozhodnutí
  (níže) a soubor nad prahem bez ráčnového komentáře — ztracená ráčna je tak
  hlasitá, ne tichá.
- **Legacy režim (přechod).** Soubor ve starém tvaru (bod 1) dostává od skriptu
  tvaru jen varování — tvar, velikost i rozpočet — a harvest nezastaví.
  Harvestová brána hlasitě ohlásí, že legacy soubor roste, o kolik řádků,
  a doporučí konsolidaci. Nasazení vrstvy tak v monorepu nic nemění
  a nezablokuje žádný harvest. Přísná pravidla začnou pro soubor platit
  v okamžiku, kdy ho kolo 1 konsolidace převede do nového tvaru; je-li pak
  nad rozpočtem, kolo 1 mu zapíše ráčnový komentář (`-Baseline`).
- Hlídá sdílený skript `Test-UmsPlaybookShape.ps1 -Playbook <cesta>` (tvar
  a rozpočet souboru) a `-Tree <cesta>` (navíc řetězce všech MB podstromu);
  nálezy vrací česky. Volá ho sada vrstvy nad fixturami, harvestová brána nad
  dotčenými soubory a konsolidace na konci běhu.
- **Ráčna bez nového souboru:** soubor v novém tvaru nad prahem nese na druhém
  řádku HTML komentář `<!-- playbook-budget: 600; baseline: 2414 (2026-09-23) -->`.
  Soubor nesmí přerůst baseline: harvest, který by ho zvětšil, musí přírůstek
  vyrovnat (sloučit, nahradit, vyřadit), nebo člověk v bráně výslovně zvedne
  baseline s důvodem — ten se zapíše do komentáře
  (`baseline: 2430 (2026-10-02, <důvod>)`). Růst je tedy vždy viditelné lidské
  rozhodnutí, nikdy tichý přírůstek. Konsolidace baseline po každé dávce sníží
  na dosaženou velikost; pod prahem se komentář odstraní. Komentář cestuje se
  souborem, takže ráčna platí v každém klonu. Řetězec ráčnu nemá — je součtem
  svých úseků a hlídají ho jejich ráčny.

### 4. Sběr kandidátů (overlay SDD)

- Před kopií kandidáta do `playbook-candidates/<slug>.md` řídicí sezení porovná
  jeho `Procedure` s existujícími kandidáty i se **sestaveným řetězcem** a zapíše
  pole `Relates: <MB>:<položka> (rozšiřuje | duplikuje | nahrazuje)`, když shoda
  existuje; `Corrects` zůstává jako zvláštní případ „nahrazuje".
- Kandidát, který duplikuje jiného kandidáta v souboru nebo pravidlo předka, se
  nezapíše; řídicí sezení to ohlásí v reportu.
- **Mechanická opora je omezená na jazykově neutrální tokeny.** Kandidáti jsou
  anglicky, playbook česky, takže shoda slov nefunguje; sdílený skript
  `Find-UmsPlaybookMatch.ps1 -Text <procedure> -Chain <MB>` porovnává jen
  identifikátory v backticks (příkazy, přepínače, soubory, funkce) a vrací až
  tři kandidátní položky s jejich MB; rozhodnutí o vztahu zůstává úsudkem.

### 5. Harvestová brána (mb-harvest)

- Brána předkládá **tabulku dispozic**, ne seznam textů. Připraví ji analytik
  na nejlevnějším schopném tieru (kontrakt, Dispatch Model Policy) podle briefu,
  který je součástí reference; člověk schvaluje tabulku a smí přebít řádek.

  | # | Kandidát | Původ (task) | Cena nepřítomnosti | Existující položka | Dispozice | Kritérium | M/Ú | Selhání |
  |---|---|---|---|---|---|---|---|---|

  `Dispozice` má právě jednu z pěti hodnot: `nový (<MB>, podstrom | projekt,
  <sekce>)` / `sloučit do <MB>:<položka>` / `nahrazuje <MB>:<položka>` /
  `do kódu <kde>` / `zahodit <důvod>`. `M/Ú` je `M` jen tam, kde rozhodla
  shoda identifikátorů z `Find-UmsPlaybookMatch.ps1` nebo mechanicky
  ověřitelné kritérium 4; všude jinde `Ú` — párování anglických kandidátů proti
  českému playbooku je sémantická práce (Doklad, „Triage UMS-3505": skutečně
  mechanicky rozhodnutelných bylo asi 8 z 50). `Selhání` je `hlasité`, když by
  sezení řídící se špatnou verzí pravidla narazilo na viditelné selhání, jinak
  `tiché`.
- **Dopad u cíle v předkovi.** Řádek, jehož dispozice míří do playbooku
  předka, nese navíc počet a seznam MB, které pravidlo zdědí (z
  `Get-UmsPlaybookChain.ps1`); u kořene je to celé repo. Člověk tak schvaluje
  zápis s viditelným dosahem. Konflikty paralelních tiketů v témž playbooku
  předka řeší běžný merge báze na hranici fáze.
- **Kritéria v pořadí aplikace** (levná a mechanická napřed; převzatá z triage
  UMS-3505, Doklad „Triage UMS-3505"):
  1. Duplicita uvnitř hromady — shlukovat podle tématu, ne podle tasku původu.
  2. Duplicita proti řetězci — už pokryto → zahodit; rozšiřuje → sloučit do;
     jinak nový. `Corrects`/`Relates` musí jmenovat existující položku.
  3. Dosah ve stromu — platí jen pro tuto MB (`projekt`), pro podstrom některého
     předka (`podstrom` té MB), nebo všude (`podstrom` kořene)? Vázaný na jediný
     commit nebo nález je podezřelý, pokud se nezobecňuje. Výchozí cíl je
     `Target MB` kandidáta, jinak `PLAN_MB`, část `projekt`; širší cíl navrhuje
     analytik a schvaluje člověk.
  4. Operační tvar — `Procedure` je operace („před Y ověř X"), ne úsudek („dej
     pozor na X"); neoperativní → zahodit, nebo jednou větou přepsat.
  5. Cena nepřítomnosti — z `Happened`: skutečná (pád sezení, falešná zelená,
     bezpečnostní díra, ztracený soubor) vs. kosmetická; řadí a rozhoduje
     hraniční případy.
  6. Spouštěč — je přirozený okamžik, kdy si sezení pravidlo vybaví? Určuje
     sekci. A hlavně: bylo by to lepší jako kód? Lint, aserce v `_assert.ps1`,
     kontrola ve skriptu → `do kódu`.
  7. Domov — fakt patří do `tech.md`, pravidlo do kontraktu, postup do playbooku
     (viz bod 7).
  8. Čistá cena kontextu — řetězec má stejnou velikost nebo menší; `nahrazuje`
     má větší cenu než stejný obsah jako položka navíc; u `nový` jmenuj sekci
     a preferuj `sloučit do`, má-li sekce blízkého souseda.
- `sloučit do` přepisuje existující položku na jeden řádek pravidla plus
  `Proč:`; `nahrazuje` starou položku odstraní a zapíše ji do seznamu
  vyřazených; `do kódu` zapíše test nebo kontrolu a položku do playbooku
  nepřidá; kandidát shodný s vyřazeným pravidlem z kteréhokoli úseku řetězce
  dostane `zahodit (vyřazeno)`, pokud nenese nové `Happened`.
- **Zápis k předkovi (změna jádra kontraktu).** Schválená dispozice, která
  míří do playbooku předka, přidá tohoto předka do `AFFECTED_MBS` — ale jen pro
  `playbook.md` a `playbook-retired.md`. Dnes se `AFFECTED_MBS` odvozuje
  výhradně z diffu větve, takže by zápis k předkovi porušil Scope Lock; ostatní
  dokumenty předka zůstávají mimo harvest.
- **Pořadí vůči archivaci.** Skript tvaru běží na konci kroku 3 `mb-harvest`
  (aktualizace dokumentů), před krokem 4 (archivace návrhu a smazání plánu)
  a před resetem `context.md` na IDLE — nad každým dotčeným souborem a nad
  řetězcem každé MB, které se změna dotkla. Tvrdý nález se počítá jako
  neúspěšná aktualizace MB podle pravidla částečného selhání Harvest Contractu:
  žádná archivace, žádný reset na IDLE, oprava a nový běh brány. Varování
  (legacy režim, heuristika `Proč:`) harvest nezastaví, jen se vypíšou.

### 6. Seznam vyřazených a převod do kódu

- `playbook-retired.md` vedle každého playbooku, který pravidla vyřazuje: jeden
  řádek na vyřazené pravidlo:
  `- <první slova pravidla> — <nahrazeno «položka» | hlídá test <sada> |
  neplatí od <commit>> (<YYYY-MM-DD>)`. Brána i konsolidace čtou seznamy
  vyřazených z celého řetězce, aby se pravidlo vyřazené v předkovi znovu
  nenaučilo v potomkovi; skript tvaru hlídá jen řádkový tvar.
- Pravidlo ověřitelné strojově se převede na test a z playbooku odejde; dvě už
  rozhodnuté lekce z triage UMS-3505 jsou první: (a) každý `Assert-*` volaný
  v `*.tests.ps1` existuje v sesterském `_assert.ps1` — chybějící helper se
  v RED běhu tváří jako očekávaný RED; (b) každá `*.tests.ps1`, která
  dot-sourcuje svůj předmět, nastavuje `$ErrorActionPreference = 'Stop'`.
  Obojí je grep nad `ums/**/tests/*.tests.ps1` jako vlastní sada
  `tests-hygiene.tests.ps1` ve `shared/tests/`.
- Pravidlo (b) dnes porušuje nejméně 9 stávajících sad (všechny v
  `mb-doc-index/tests` a `mb-epic-graph/tests`, pravděpodobně i
  `guard-git-push.tests.ps1` a `ledger-status.tests.ps1`). Opraví se v tomto
  tiketu — jeden řádek na sadu a ověření, že sada dál prochází —, takže sada
  hygieny je od prvního běhu ostrá, bez allowlistu.

### 7. Vlastnictví pastí prostředí

- Past prostředí má dva domovy podle druhu věty: **fakt o platformě** patří do
  `tech.md`, sekce „Pasti prostředí" (co PowerShell, git nebo msys dělá);
  **postup** patří do playbooku (co uděláš, aby tě to nepotkalo), s `Důkaz:`
  ukazujícím na `tech.md`. Nikdy obojí na obou místech.
- Ve stromu je postup proti pasti prostředí skoro vždy obecný, takže patří do
  podstromové části kořene; fakt zůstává v `tech.md` té MB, kde se projevil.
- První konsolidace tohoto repa rozřeší čtyři dnešní duplicity: pasti
  `Set-StrictMode` nad kolekcemi a návratovými hodnotami, Git Bash vs. WSL stub,
  cíl git hooku přes `git rev-parse --git-path`, UTF-8 round trip přes
  PowerShell do gitu.

### 8. Konsolidační skill `mb-playbook-consolidate` — jedna MB

- Read-only průchod playbookem a seznamy vyřazených řetězce; výstupem je
  tabulka návrhů `| # | Položka | Návrh | Kritérium | Do | Pozn. |`.
  - Návrhy: `ponechat` / `sloučit do <položka>` / `vyřadit (<důvod>)` /
    `přesunout do tech.md` / `převést na test <kde>` /
    `přesunout k předkovi <cesta>` / `přesunout k potomkovi <cesta>` /
    `přeřadit do části podstrom | projekt`.
  - Kritéria: `duplicita` / `přesah` / `jednorázový incident` /
    `převoditelné do kódu` / `špatný domov` / `nad rozpočet sekce` /
    `širší dosah` / `užší dosah`.
- Člověk schvaluje tabulku; zápis, skript tvaru a commit přes `mb-git-commit`
  jako v bráně. Nikdy nepushuje sdílenou větev. Přesun mezi soubory se řídí
  vlastnictvím dokumentů: nejdřív zapsat do cíle, pak smazat ze zdroje, oba
  soubory v jednom commitu.
- **Scope Lock (změna jádra kontraktu).** Konsolidace zapisuje mimo
  `CTX_DIR`/`PLAN_MB` a mimo harvest, takže potřebuje jmenovanou výjimku:
  smí zapsat `playbook.md` a `playbook-retired.md` každé MB v rozsahu běhu
  a `tech.md` jen u řádků s verdiktem `přesunout do tech.md`, a do
  `proposals/next/` jen schválený eskalační report (níže) — autoritou je
  člověkem schválená tabulka dávky, nic mimo ni. `mb-git-commit` dostane
  odpovídající pravidlo stagingu: stagne právě soubory, které schválená dávka
  jmenuje, takže přesun nemůže odejít bez zdrojové nebo cílové poloviny.
- Spouští se ručně, nebo když skript tvaru hlásí tvrdý nález či soubor nad
  prahem; nikdy automaticky.
- **Dvě kola.** Kolo 1 převede tvar: rozdělí soubor na části, přeřadí položky
  do sekcí „Když …", zkrátí `Proč:` na větu a doplní `Důkaz:` ze SHA
  harvestového commitu podle `git log -S`. Kolo 2 slučuje, vyřazuje, přesouvá
  a převádí do kódu. Obě kola schvaluje člověk nad tabulkou.
- **Eskalační report.** Zůstane-li soubor nebo řetězec po kole 2 nad prahem,
  konsolidace neškrtá dál. Baseline nastaví na dosaženou velikost a sepíše
  eskalační report jako předběžný návrh
  `<MB>/proposals/next/design_<mb-slug>_playbook_eskalace.md` — ve frontě, kde
  ho najde `mb-state` i `mb-doc-index` a odkud se aktivuje jako běžná
  následná práce. Report nic neřeší, jen dává podklad:
  - velikost souboru a řetězce proti prahu;
  - zbylé položky seskupené do shluků podle tématu, s velikostí každého shluku;
  - u každého shluku navržený jiný domov a proč: skill (postup vázaný na
    konkrétní druh práce, který se má načíst jen při ní — například úpravy
    BPMN), skript nebo test (mechanicky ověřitelné), samostatný referenční
    dokument MB čtený na vyžádání, `tech.md`;
  - odhad, o kolik by přesun playbook a dotčené řetězce zmenšil.

  Kdo report vytvořil, ho nechá schválit stejně jako tabulku dávky; zápis do
  `proposals/next/` je v rámci výjimky Scope Lock pro konsolidaci.
- **Citace sekcí.** Přejmenování a přesun sekcí rozbije citace podle jména
  sekce, které míří do playbooku odjinud — dnes například `contract-inject.ps1`
  a jeho aserce v `contract-inject.tests.ps1`, `mb-state/SKILL.md` (sekce
  „Obnova nasazené kopie v tomto repu"), `mb-epic-run/README.md` („Testy
  vrstvy") a `architecture.md`. Kolo 1 proto grepem najde každou citaci
  starého názvu mimo playbook a přepíše ji v téže dávce; konec běhu spustí
  `mb-link-audit` nad dotčenými MB.
- Mechanickou část nese skript `consolidate-playbook.ps1`:
  - `-Parse` — JSON položek (id, MB, část, sekce, první slova, řádek pravidla,
    `Proč:`, `Důkaz:`, počet řádků); čte všechny tři tvary, které v monorepu
    žijí: tučně uvozené odrážky, položka pod nadpisem `##` nebo `###` s prózou
    a přechodný mix s koncovým seznamem pravidel;
  - `-Apply <decisions.json>` — provede schválené verdikty a přepíše dotčené
    soubory, neschválené položky nechá doslova;
  - `-Baseline` — zapíše nebo aktualizuje ráčnový komentář.
- Úsudkovou část nese dispatch analytika na nejlevnějším schopném tieru se
  stejným briefem jako brána.

### 9. Režim pro víc MB: `mb-playbook-consolidate -Tree [<cesta>]`

Výchozí cesta je `MB_ROOT`; vyvolání je jednořádkové („konsoliduj playbooky
celého monorepa", `-Tree MobilChange/SMSInfo3`). Průchod má čtyři kroky:

1. **Inventura** — `-Parse -Tree` sestaví strom MB, vypíše velikosti souborů
   i řetězců a označí, co je nad rozpočtem. Nic nepíše.
2. **Kolo 1 (tvar)** po jednotlivých MB, shora dolů — potomek potřebuje vědět,
   co předek už nese v podstromové části. Každá MB má vlastní tabulku,
   schválení a commit.
3. **Kolo 2a (napříč MB)** — analytik shlukuje položky různých MB podle tématu
   (mechanicky pomáhá shoda identifikátorů); skript ke každému shluku
   **mechanicky spočítá nejnižšího společného předka** MB, ve kterých shluk
   žije. Verdikt `přesunout k předkovi <předek>` sloučí duplicity do jedné
   položky v podstromové části předka; `ponechat` nechá každé MB vlastní
   variantu; `přesunout k potomkovi` vrací pravidlo zapsané výš, než platí
   (typicky pravidla o `BpmnData` zapsaná v KicWorkflow). Tabulka je jedna
   napříč MB, schvalovaná po dávkách — jedna dávka na podstrom.
4. **Kolo 2b (uvnitř MB)** — slučování, vyřazování a převody do kódu podle
   bodu 8, po jednotlivých MB.

- **Commity.** Každá dávka je samostatný commit přes `mb-git-commit` na
  tiketové větvi sezení, které průchod spouští, s trailerem
  `Playbook-Consolidation: <běh>/<dávka>`; konsolidace monorepa je tedy
  normální práce na vlastním tiketu a skill nepushuje nic sdíleného.
- **Obnovitelnost bez nového druhu zbytků.** Průchod přes desítky MB přesáhne
  jedno sezení. Dávka se schválí, hned zapíše a commitne, takže jediným nositelem
  stavu jsou commity: `-Resume <běh>` odvodí hotové dávky z trailerů
  v `git log` a pokračuje první nehotovou. Tabulka rozpracované dávky
  v `.superpowers/playbook-consolidation/<běh>/` je git-ignorovaný pracovní
  soubor, který jde kdykoli vygenerovat znovu; neschválená práce tedy není
  neobnovitelný zbytek a Workspace Discipline se nemění.
- **Konec běhu** — `Test-UmsPlaybookShape.ps1 -Tree` nad celým podstromem bez
  tvrdého nálezu; každá MB, jejíž soubor nebo řetězec zůstal nad prahem, má
  ráčnu na dosažené velikosti a eskalační report ve frontě. Report napříč
  stromem je jeden za podstrom, ne jeden za MB, aby shluky, které se opakují
  ve víc MB (kandidáti na společný skill), byly vidět pohromadě.

### 10. Akceptace

- **Fixtury.** Fixturní repo se třemi úrovněmi: kořen, mezilehlá MB s oběma
  částmi, dva listy, a sourozenecký shluk bez společného předka pod kořenem.
  Ověřuje se sestavení řetězce (předek dává jen podstromovou část), výpočet
  nejnižšího společného předka, přesun nahoru i dolů přes `-Apply` s kontrolou,
  že neschválené položky zůstaly doslova, rozpočet souboru i řetězce včetně
  ráčny a čtení legacy tvaru bez částí. Navíc: kořen jako jediná MB s částí
  „Jen pro tento projekt"; soubor a řetězec nad prahem (varování, ne tvrdý
  nález) a z nich vygenerovaný eskalační report; růst nad ráčnu bez
  zaznamenaného rozhodnutí (tvrdý nález) a se zaznamenaným zvýšením baseline
  (prochází); soubor nad prahem bez ráčny (tvrdý nález); legacy soubor nad
  prahem, který harvest nezastaví; git-ignorovaná a vnořená `memory-bank/`,
  které se do stromu nezapočítají; položka druhu postup s blokem příkazů.
- **Toto repo.** Plná konsolidace `memory-bank/playbook.md` (2 414 řádků) ve
  dvou kolech nad schválenou tabulkou: nový tvar, sekce podle okamžiku
  spuštění, vyřazené v seznamu, skript tvaru bez tvrdého nálezu. Playbook je tu
  jen kořenový a zároveň `PLAN_MB`, takže jeho pravidla o artefaktech vrstvy
  patří do části „Jen pro tento projekt" — jde o test velikosti, ne stromu.
  Akceptace je splněná jedním ze dvou výsledků, oba s měřením v Dokladu:
  soubor pod prahem 600 řádků, nebo soubor nad prahem s ráčnou na dosažené
  velikosti a eskalačním reportem ve frontě `proposals/next/`. Práh při
  dnešních 195 tučných odrážkách znamená v průměru asi tři řádky na položku
  nebo vyřazení či převod do kódu zhruba třetiny položek; kolo 2 rozhodne nad
  tabulkou, kolik z toho jde bez ztráty. Samotný přesun obsahu podle reportu
  (například do skillů) je následná práce mimo tento tiket.
- **Monorepo nanečisto.** `-Tree` nad `d:\_datasys\ums` v krocích 1 a 3 bez
  zápisu. Výstupem je inventura a tabulka přesunů napříč MB, přiložená do
  sekce Doklad — důkaz, že parser unese všechny tři tvary položek a že strom
  a nejnižší společní předci vycházejí podle analýzy z 2026-09-23.

## Dopady

- **Jádro kontraktu:** MB Context Reading Rule (řetězec místo jednoho
  playbooku), Harvest Contract a Scope Lock (zápis playbooku předka
  v `AFFECTED_MBS`, výjimka pro konsolidaci); verze kontraktu a `CHANGELOG.md`.
- **Reference:** `contract/harvest.md` (pořadí kontroly tvaru a částečné
  selhání), `contract/architect-review.md` (co dostává oponent).
- **Reference `contract/playbook-contract.md`** se přepisuje: tvar souboru
  a položky, strom a řetězec, `Relates`, rozpočet a ráčna, kritéria triage
  a brief analytika, seznam vyřazených, převod do kódu, vlastnictví pastí.
- **Skripty a testy:** `shared/scripts/Get-UmsPlaybookChain.ps1`,
  `Test-UmsPlaybookShape.ps1`, `Find-UmsPlaybookMatch.ps1`;
  `mb-playbook-consolidate/scripts/consolidate-playbook.ps1`; sady
  `playbook-chain.tests.ps1`, `playbook-shape.tests.ps1`,
  `playbook-match.tests.ps1`, `consolidate.tests.ps1`,
  `tests-hygiene.tests.ps1`; oprava stávajících sad podle pravidla hygieny (b);
  `contract-inject.ps1` a jeho aserce v `contract-inject.tests.ps1`, pokud
  citují přejmenovanou sekci.
- **Skilly a overlaye:** `mb-harvest` (brána v2), overlay SDD (dedup proti
  řetězci, `Relates`, cesta k řetězci v dispatchi, baseline z postupů), overlay
  brainstorming a writing-plans jen tam, kde jmenují čtení playbooku;
  `mb-architect-review`, `mb-epic-elaboration` (čtení řetězce); `mb-init`
  (playbook v novém tvaru); `mb-sync` (část a sekce v návrhu opravy);
  `mb-git-commit` (staging schválené dávky); `mb-state` a `mb-epic-run/README.md`
  (citace sekcí playbooku); nový skill `mb-playbook-consolidate`;
  `SKILLS_MANIFEST.md`.
- **Memory Bank tohoto repa:** `playbook.md` a `playbook-retired.md`, `tech.md`
  (pasti), `architecture.md` (dokumentová vrstva, strom playbooků).

## Rizika

- **Ztráta pravidla při konsolidaci.** Kryje dvoukolový postup, schválení
  tabulky a `git`: každé vyřazení má řádek v seznamu vyřazených s důvodem,
  každý přesun jde v jednom commitu se zdrojem i cílem.
- **Špatně zvolená část.** Pravidlo v „Jen pro tento projekt", které potomci
  potřebují, se jim tiše nepředá. Kryje kritérium 3 brány, verdikt
  `přeřadit do části` v konsolidaci a kolo 2a, které hledá stejné pravidlo
  v sourozencích.
- **Nafouknutý kořen.** Kořen čte každé sezení. Kryje ráčna (růst jen
  zaznamenaným lidským rozhodnutím), dopad vypsaný u každého zápisu k předkovi
  a práh řetězce kontrolovaný pro každou MB, takže přírůstek v kořeni se ukáže
  jako varování všude.
- **Práh jako věčné varování.** Soubor nad prahem s eskalačním reportem, na
  který nikdo nenaváže, zůstane varováním napořád. Kryje jen to, že report leží
  ve frontě a `mb-state` ho vypisuje; rozhodnutí o následné práci je lidské.
- **Falešný `Happened` v kandidátovi.** Triage ho neodhalí (UMS-3505 #15);
  kryje jen pozdější měření a `Důkaz:` odkaz, který jde ověřit.
- **Ráčna schovaná v komentáři se ztratí přepisem souboru.** Soubor v novém
  tvaru nad prahem bez komentáře je tvrdý nález; ztráta je hlasitá.
- **Parser tvarů monorepa.** Ověřuje se nad reálným stromem už zde, nanečisto.

## Odložená rozšíření

- **Doménové playbooky mimo strom** (explicitní graf, hlavička `Zahrnuje:`).
  Dnes je jediné sdílení bez společného předka pod kořenem dvojice malých
  shluků o SQL (Doklad, „Strom vs. dvě úrovně"), které se vejdou do kořene jako
  sekce „Když píšeš SQL skript nebo migraci". Otevřít, když doménová sekce
  v kořeni přeroste rozpočet sekce, nebo když se objeví druhá doména, jejíž
  pravidla by v kořeni zatěžovala nesouvisející projekty.

## Doklad

| Měření | Hodnota | Podmínky |
|---|---|---|
| Playbook tohoto repa | 2 124 řádků, 171 odrážek `- **`, 182 položek včetně číslovaných, 10 nadpisů; dvě sekce nesou 63 % textu | 0a13ef1, 2026-09-17 |
| Playbook tohoto repa při aktivaci | 2 414 řádků | dde102c, 2026-09-23 |
| Růst | +2 200 / −76 řádků za 45 dní; 12 z 15 commitů jsou harvesty a nesou 92 % přírůstku; 6 položek kdy smazáno | `git log --numstat`, 2026-09-17 |
| Duplicity v souboru | nejméně 5 shluků: 9 položek o grep sweepu, 4 o CRLF, 3 „ověř v tomto běhu", 4 o pořadí STOPů, 2 páry „nahrazeno, ale ponecháno" | analytik 2026-09-17 |
| Vazba na jeden incident | 165 z 182 `Proč:` cituje právě jeden incident; asi 53 položek vázaných na artefakty vrstvy, asi 79 obecně znějících, ale jednoincidentních, asi 50 přenositelných | tamtéž |
| Duplicity tech.md × playbook | 4 témata pastí na obou místech; exit kód 4 instalátoru v `tech.md`, ale ne v playbooku, kam `tech.md` odkazuje | tamtéž |
| Mechanismus harvestu | jediný vztah mezi položkami je `Corrects` s verdikty nahradit / ponechat obojí / zahodit; žádný krok neslučuje, nemaže, nezařazuje, neměří | `mb-harvest/SKILL.md`, kontrakt 2.19 |
| Dispatch | dispatch implementátora dostává cestu k playbooku cílové MB (ne jeho obsah); předkové se nečtou | overlay SDD, řádky 112–117; kontrakt 3.0, MB Context Reading Rule |
| Monorepo | 23 playbooků, 8 033 řádků; KicWorkflow 3 325 řádků, SMSInfo3 1 773, kořen 449 | `d:\_datasys\ums`, pracovní strom, 2026-09-23 |
| Konsolidace tohoto repa | 2 414 → 842 (kolo 1) → 774 řádků (kolo 2); 209 položek → 187 (176 pravidel, 11 postupů); vyřazeno 19 (2 v kole 1, 17 v kole 2); převedeno do kódu 0 (žádná položka neříká přesně lekci sady hygieny); přesunuto do `tech.md` 0, 3 položky přepsány na postup s Důkazem v `tech.md`; výsledek: nad prahem, ráčna `baseline: 774` a eskalační report `proposals/next/design_root_playbook_eskalace.md` | běhy `c1` (9d54d10) a `c2` (36988ac), 2026-09-24 |
| Zkušenost správce UMS-3517 | sezení UMS-3518 při mergi nahlásilo plochý playbook přes 150 položek a samo ho rozdělilo do sekcí | zpráva správce, 2026-09-17 |

### Strom vs. dvě úrovně

Dvě read-only analýzy monorepa `d:\_datasys\ums`, 2026-09-23:

- **MB kopírují strom zdrojáků** (kořen → produkt → projekt → podprojekt).
  Kořenový playbook (449 řádků) je ze 100 % obecný: git, PowerShell, CRLF,
  kódování, hooky, nástroje sezení. Mezilehlé MB s vlastními potomky
  s playbookem: `MobilChange/SMSInfo3/`, `KicWorkflow` (potomek `BpmnData`),
  `Setup/`.
- **Mezilehlé playbooky míchají obsah.** SMSInfo3 (158 položek): asi 95 jen pro
  vlastní projekt (MVC, Razor, CSS, DataTables), asi 35 pro potomky (sdílená
  `.sln`, `Directory.Build.props`, `ProjectReference` na `.sqlproj`, linq2db),
  asi 28 obecných, patřících do kořene. KicWorkflow (185 položek): většina jsou
  pravidla o `BpmnData/*.bpmn` a Lua zapsaná o úroveň výš; `Setup/` má jedinou
  položku, jen vlastní.
- **Ruční dědění už existuje.** 5 odkazů potomků na rodiče a 3 odkazy rodiče
  na potomky, všechny na pravidla druhu „pro potomky"; `BpmnData` na
  KicWorkflow neodkazuje vůbec, ačkoli tam leží asi 15 pravidel přímo o ní.
  Kontrakt i overlay SDD dnes čtou jen playbook cílové MB.
- **Duplicita napříč MB** je asi 300 až 400 řádků z 8 033 (4–5 %), soustředěná
  v témech CRLF a editační nástroje (6 playbooků), CP1250/UTF-16 po bajtech
  (8), PowerShell (11), git (4) a opakovaný úvodní odstavec (5, šablona, ne
  pravidlo).
- **Sdílení bez společného předka pod kořenem:** dva malé shluky o SQL
  (idempotence dvojím během proti scratch DB; kopie SQL bloků po bajtech)
  v `Setup/KicSetup`, `Setup/UmsSetup` a `MobilChange/SMSInfo3/SMSInfo3Database`.
- **Velikost čtení** (řádky dnešních souborů):

  | Sezení v | Strom, předek celý | Dvě úrovně | Strom s částmi (odhad po kole 1) |
  |---|---|---|---|
  | `SMSInfo3Database` | 2 519 | 746 (bez pravidel SMSInfo3 pro potomky) | 600–700 |
  | `KicWorkflow/…/BpmnData` | 5 815 | 717 (bez pravidel KicWorkflow o BpmnData) | pod 900 po přesunu pravidel BpmnData k potomkovi |

- **Závěr:** osminásobek čtení nezpůsobuje strom, ale nerozdělený obsah
  mezilehlých playbooků. Dvě úrovně by ztratily pravidla, která potomci
  potřebují a na která dnes ručně odkazují. Strom s částmi „Pro celý podstrom"
  / „Jen pro tento projekt" zachová obojí.

### Oponentura 2026-09-23

Nezávislý oponent (čistý kontext, přístup ke kódu vrstvy i k monorepu, jen
čtení) vznesl 15 nálezů s důkazem — 1 blokující, 6 závažných, 8 drobných;
žádný nebyl odmítnut. Nesporné zapracované: definice nového tvaru a kořen jako
`PLAN_MB` (bod 1), objev stromu přes `git ls-files` a úplný soupis čtenářů
a zapisovatelů, řetězec jako soubor (bod 2), pravidla rozpočtu řetězce (bod 3),
`M/Ú` podle skutečné mechaničnosti a pořadí kontroly tvaru vůči archivaci
(bod 5), výjimka Scope Lock a staging dávky, citace sekcí, obnovitelnost
z commitů (body 8 a 9), rozdělení přerostlých sekcí a `Důkaz: návrh` (bod 1).
Rozhodnuté s uživatelem: legacy režim místo povinné baseline při nasazení
(bod 3); dva druhy položek, pravidlo a postup (bod 1); oprava stávajících sad
v tiketu místo allowlistu (bod 6); přímý zápis k předkovi s viditelným dosahem
místo fronty předka (bod 5).

Ověřeno oponentem v monorepu: 23 playbooků, 8 033 řádků; součty řetězců
2 519 (SMSInfo3Database) a 5 815 (BpmnData); žádný `tasks.md` v roli
playbooku; asi 55 MB bez playbooku včetně mezilehlých `MobilChange/` a
`Common/`; git-ignorovaná kopie `DistOut/Iso/Work/MobilChange/WwwSms/memory-bank`
a prázdná vnořená MB v `PCInfo`. V tomto repu 2 414 řádků a 195 tučných
odrážek.

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

### Monorepo nanečisto

Běh `consolidate-playbook.ps1 -Stats/-Parse -Tree . -RepoRoot d:/_datasys/ums`
a `Test-UmsPlaybookTree` z tohoto forku, 2026-09-24, bez zápisu. HEAD
monorepa `ec159fd` a prázdný `git status --porcelain` před i po běhu.

- **Inventura:** 23 playbooků, 8 033 řádků, 973 položek ve všech třech
  tvarech (314 položek pod nadpisem, 316 tučných pravidel, 343 prozaických
  odstavců); parser nespadl na žádném souboru. Strom neobsahuje git-ignorovanou
  kopii `DistOut/…` ani vnořenou MB v `PCInfo`.
- **Kontrola stromu:** 0 tvrdých nálezů (všech 23 souborů je legacy), varování
  23× `[legacy]`, 2× `[práh-soubor]`, 2× `[práh-řetězec]`.
- **Nad prahem:** soubory `KicWorkflow` 3 325 řádků (řetězec 3 774)
  a `SMSInfo3` 1 773 (řetězec 2 222). Ostatní řetězce 453–750 řádků: legacy
  předek mimo kořen zatím nic nepředává, kořen (449) se čte celý.

| Shluk | MB | Řádky | Nejnižší společný předek | Verdikt | Odhad úspory |
|---|---|---|---|---|---|
| Editace CP1250/UTF-16 zdrojáků po bajtech | 4 | 91 | kořen | přesunout k předkovi | 65 |
| Editační nástroj zplošťuje CRLF | 4 | 65 | kořen | přesunout k předkovi | 45 |
| SQL: idempotence dvojím během proti scratch DB | 2 | 51 | kořen | ponechat | 0 |
| Pravidla o `BpmnData`/`.bpmn`/Lua v `KicWorkflow` | 2 | 206 | `KicWorkflow` | přesunout k potomkovi `BpmnData` | 40 |
| Šablonová položka „Rules“ | 3 | 6 | `SMSInfo3` | přesunout k předkovi | 4 |

Porovnání s analýzou 2026-09-23: nejnižší společní předci vycházejí podle
ní — SQL shluky nesdílejí předka pod kořenem, pravidla o `BpmnData` leží
o úroveň výš, než platí (31 položek, 206 řádků, víc než odhadovaných 15
pravidel). Duplicita napříč MB je menší, než odhad 300–400 řádků: tabulka
nese 162 řádků duplicit a 154 řádků úspory; zbytek odhadu leží uvnitř
jednotlivých MB (kolo 2b). PowerShell a git pasti se napříč MB neopakují.
Mezi MB nejvíc ušetří přesun obsahu `KicWorkflow` k potomkovi, nikoli
slučování duplicit.

Mechanismy převzaté z rešerše 2026-09-17: triage při zápisu (mem0
ADD / UPDATE / DELETE / NONE, Claude Code „neukládej odvoditelné"), index a
detail (Claude Code MEMORY.md, Zettelkasten, Anthropic progressive disclosure),
rozpočet vynucený testem (limit indexu Claude Code 200 řádků, Cursor 500 řádků,
SKILL.md 500 řádků), nahrazení místo tichého smazání (ADR superseded),
pravidelná konsolidace s pojmenovanými kritérii (Wikipedia merge: duplicate /
overlap; Anthropic consolidate-memory), pravidlo tvaru položky (VS Code:
jedna prostá věta plus důvod).
