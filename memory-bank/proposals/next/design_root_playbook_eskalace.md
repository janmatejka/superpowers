# Návrh: Eskalace playbooku — memory-bank/ (fork superpowers)

## Cíl

Playbook `memory-bank/playbook.md` zůstal po konsolidaci (běhy `c1` a `c2`,
UMS-3552) nad prahem: 774 řádků proti 600. Kolo 2 dál neškrtalo, protože
zbylé položky stojí za svou cenu. Jen část z nich patří jinam než do
playbooku, který se čte celý při každé práci. Tento předběžný návrh dává
podklad pro přesun obsahu jinam; nic neřeší.

## Scope

- Dotčené MB: `memory-bank/` (kořen, jediná MB tohoto repa).
- Dotčené řetězce: žádný není nad 900 řádků (řetězec kořene = soubor, 774).

## Technický návrh

### Velikosti proti prahu

| MB | Soubor (řádky / 600) | Řetězec (řádky / 900) | Ráčna |
|---|---|---|---|
| `memory-bank/` | 774 / 600 | 774 / 900 | `baseline: 774 (2026-09-24)` |

Vývoj: 2 414 řádků před konsolidací → 842 po kole 1 (převod tvaru) → 774 po
kole 2 (4 sloučení, 17 vyřazení, 3 přepisy, rozdělení přerostlé sekce).

### Shluky

| Shluk | Položky | Řádky | Navržený domov | Proč |
|---|---|---|---|---|
| Mechanika kontraktu a referencí (nadpisy, citace, rozdělení souboru, komprese, verzování) — sekce `Když měníš kontrakt nebo referenci` | 26 | 87 | samostatný referenční dokument MB čtený na vyžádání (např. `memory-bank/contract-authoring.md`) | Potřebuje je jen práce na textu kontraktu; každé jiné sezení je čte zbytečně. Většina pochází z jedné review vlny (0d40535, 3f811a6). |
| Přesnost tvrzení o kódu v reportech a komentářích — sekce `Když píšeš report nebo komentář` | 27 | 85 | referenční dokument MB, nebo krok v šablonách reportu implementátora a reviewera | Společný princip „než napíšeš větu o chování kódu, ověř ji čtením celé funkce“ se liší jen mechanismem. Patří do šablony reportu, kterou sezení skutečně otevře, spíš než do playbooku. |
| Pasti PowerShellu (`@()` kolem celého `if`/`else`, `$null` koerce, kudrnaté uvozovky jako oddělovače řetězců, `Set-StrictMode`) — sekce `Když píšeš PowerShell` | 20 | 72 | skript nebo test (statická kontrola skriptů vrstvy, po vzoru `tests-hygiene.tests.ps1` nad AST) | Velká část je mechanicky ověřitelná; převod do kódu (kontrakt, „Retired rules and conversion to code“) pravidlo z playbooku odstraní úplně. |

Domov je jeden z: skill (postup vázaný na jeden druh práce, načtený jen pro
ni), skript nebo test (mechanicky ověřitelné), samostatný referenční dokument
MB čtený na vyžádání, `tech.md`.

### Odhad úspory

| Soubor / řetězec | Teď | Po přesunu |
|---|---|---|
| `memory-bank/playbook.md` po přesunu shluků 1 a 2 (odkaz na referenční dokument cca 4 řádky) | 774 | cca 606 |
| `memory-bank/playbook.md` po přesunu shluků 1–3 (pasti PowerShellu převedené do testu) | 774 | cca 534 |

Přesun shluků 1 a 2 práh těsně nedosáhne; všechny tři shluky soubor pod práh
dostanou a ráčna by šla odstranit.
