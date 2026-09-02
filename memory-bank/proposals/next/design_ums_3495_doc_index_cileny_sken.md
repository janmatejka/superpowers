# Návrh (předběžný): Cílený sken v `doc-index.ps1`

- **Jira:** UMS-3495 (https://datasyscz.atlassian.net/browse/UMS-3495)
- **Target MB:** memory-bank/
- **Vytvořeno:** 2026-09-02
- **Stav:** předběžný, vyčleněno z UMS-3488 druhou oponenturou

## Cíl

**Toto není o poolu.** Je to živý defekt nasazené vrstvy, který se objevil při
návrhu pool orchestrace a se kterým ta práce nemá nic společného — proto
vlastní tiket, a proto by měl jít **první**.

Vstupní brána (Workspace Discipline, fáze 3 Intent) vyžaduje meziclonovou
kontrolu kolizí a definuje nález `KOLIZE AKTIVNÍ PRÁCE` jako fail-closed
STOP. Ten STOP je dnes **na monorepu nedosažitelný**: `doc-index.ps1` s
deklarovaným záměrem (`-Jira`, `-Slug`) tam nedoběhne. Deklarovaný záměr
záměrně vypíná časové okno a skript prochází historii všech větví, kterých je
na `origin` přes tři stovky.

Měřeno při vstupní bráně SKODASMS-238: `-NoFetch` s deklarovaným záměrem
běžel **přes 25 minut bez jediného řádku výstupu a musel být zabit**. Postup,
který se místo toho použil, je zapsaný v `playbook.md` monorepa, sekce
„Kolizní kontrola před připnutím práce: `mb-doc-index` tu nedoběhne" — dvě
smyčky nad `git for-each-ref`, hotovo asi za minutu.

Dokud to platí, každá vstupní brána na monorepu běží s fail-closed kontrolou,
která neproběhne, a agent buď čeká desítky minut, nebo kontrolu obejde a
napíše do hlášení, že ji obešel. Obojí je špatně.

## Scope

**V rozsahu:**

- Režim **cíleného skenu** v `doc-index.ps1`, který se použije při
  deklarovaném záměru.
- **Ohlášení chybějícího výstupního adresáře** — druhá, nezávislá oprava
  téhož skriptu.
- Testy na obojí a měření proti skutečnému monorepu.
- Narovnání údaje o výkonu v `tech.md`.

**Mimo rozsah:**

- Cokoli o poolu, slotech a spouštění sezení (UMS-3488).
- Změna chování bez deklarovaného záměru — obyčejný běh s časovým oknem
  funguje a nemění se.

## Technický návrh

### 1. Cílený sken při deklarovaném záměru

Dnešní cesta s deklarovaným záměrem enumeruje bez časového omezení a na každý
nalezený commit volá `git branch -r --contains`, což je podle měření
zapsaného v [tech.md](../../tech.md) to nejdražší místo (3,1 s na 33 commitů),
plus `cat-file -e` a `show` na každý pár (větev, cesta).

Cílený sken odpovídá na tutéž otázku bez traversalu historie — dvě smyčky nad
`git for-each-ref refs/remotes/origin/`:

1. **Slug:** `git ls-tree -r --name-only <ref>` filtrovaný na cestu
   `proposals/active/` se hledaným slugem.
2. **Tiket:** `git show <ref>:memory-bank/context.md` a hledání kódu tiketu.

Obojí čte **jen tip každé větve**, což je přesně to, na co se kolizní otázka
ptá: „je tento slug nebo tento tiket **teď** aktivní na cizí větvi?" Historie
k té odpovědi není potřeba — a právě její průchod je to, co skript zabíjí.

Pozor na dvě věci, které jsou v `tech.md` už zaplacené: jména refů se do gitu
vrací zpátky, takže musí přežít round trip přes PowerShell
(`[Console]::OutputEncoding` na UTF-8, jinak větev s diakritikou skončí
`fatal: bad revision`), a refů je tolik, že se předávají přes `--stdin`, ne na
příkazové řádce.

Nálezy zůstávají beze změny: `KOLIZE AKTIVNÍ PRÁCE` (exit 2),
`DRAFT NA VÍCE VĚTVÍCH`, `FRONTA I DOKONČENO`, `CIZÍ AKTIVNÍ PRÁCE`.

### 2. Chybějící výstupní adresář se musí ohlásit

V čerstvém worktree `.superpowers/` neexistuje — vytváří ho až workflow — a
`doc-index.ps1 -Json <path>` do neexistujícího adresáře skončí **exit 1 bez
jediné chybové hlášky**; výstup přitom vypadá normálně. Volající pak nemá jak
odlišit „proběhlo bez nálezu" od „neproběhlo", a to je u fail-closed kontroly
rozdíl mezi průchodem a STOPem.

Oprava: buď adresář vytvořit, nebo — bezpečněji, protože skript je jinak
read-only — **ohlásit a skončit nenulově s hláškou, která říká co a kde**.
Rozhodnout při návrhu; přednost má varianta, která nezapisuje.

## Verifikace

1. **Testy zeleně** — cílený sken proti fixture repu
   (`new-fixture-repo.ps1`): kolize na živé i uspané větvi, self-kolize
   vlastní pushnuté větve, fronta na více větvích, obživlá fronta. Tedy
   tytéž případy, které dnes pokrývá `findings.tests.ps1`, aby se ověřilo,
   že cílený sken dává **shodné nálezy** jako dnešní cesta.
2. **Měření proti skutečnému monorepu** — běh s deklarovaným záměrem musí
   doběhnout a odpovědět; naměřený čas zapsat. Fixtura dokazuje, že kód dělá,
   co jsme do fixtury napsali; skutečné repo dokazuje, že defekt byl reálný.
3. **Chybějící `.superpowers/`** — běh musí ohlásit chybu, ne tiše skončit
   exit 1. Negativitu ověřit tím, že se před opravou tentýž případ chová
   opačně.
4. **Nedotčenost běžné cesty** — běh bez deklarovaného záměru (s časovým
   oknem) dává tytéž výsledky jako dnes.

## Rizika

**Cílený sken vidí jen tipy větví, dnešní cesta vidí historii.** Je potřeba
ověřit, že se tím žádný existující nález neztrácí — proto verifikace č. 1
běží proti stejným fixturám jako dnešní sada. Kdyby se ukázalo, že některý
nález historii skutečně potřebuje, musí zůstat dostupná i dnešní cesta a
volba mezi nimi být explicitní, ne tichá.

**`tech.md` tvrdí o výkonu něco jiného, než co bylo naměřeno.** Dokument
uvádí 32–35 s s `-NoFetch` a 57 s s deklarovaným záměrem při 219 vzdálených
větvích; playbook monorepa uvádí 25+ minut a zabití při 321 větvích. Rozdíl
je řádový, ne o pár procent. Narovnat, a v harvestu uvést obě čísla s počtem
větví, ke kterému patří.

## Navazující položky

- Po dokončení přepsat sekci „Kolizní kontrola před připnutím práce" v
  `playbook.md` monorepa — z popisu obejití na odkaz, že skript už funguje.
  Nechat vedle sebe dvě pravdy by bylo horší než mít jednu zastaralou.
