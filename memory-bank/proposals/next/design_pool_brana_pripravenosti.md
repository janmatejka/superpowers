# Návrh (předběžný): Brána připravenosti — co je bezpečné rozjet

- **Jira:** (žádný tiket — vyčlenit z UMS-3488)
- **Target MB:** memory-bank/
- **Vytvořeno:** 2026-09-02
- **Stav:** předběžný, **záměrně odložený** — aktivovat po dvou až třech rozjetích s mechanikou z UMS-3488

## Cíl

Ve vrstvě dnes **nic formálně nepokrývá rozhodnutí, který tiket je bezpečné
rozjet.** `mb-epic-graph` umí říct, co je odblokované, ledger nese špinavé
řádky, `pool-status.ps1` (UMS-3488) ví o slotech — ale nic ty signály
nespojuje, takže rozhodnutí vzniká ručně.

**Proč je tenhle návrh odložený, a ne rozpracovaný.** Rozhodovací pravidla
stojí na **jediném rozhodování** — uzávěrka okna W06, 2. 9. 2026. UMS-3488 to
sám doporučuje: „Doporučuju psát je až po druhém až třetím rozjetí, aby se
ukázalo, co se opakuje a co bylo jednorázové." Evidence se přitom dělí
ostře: **všechna měřená selhání byla mechanická** (viselý `cmd /k`, zděděná
značka dětského sezení, rozpadlý seznam argumentů — tři z pěti pokusů),
zatímco úsudková část běžela **jednou a byla šestkrát ze šesti správně
ručně**. Automatizovat na jednom datovém bodu polovinu, která nikdy
neselhala, dřív než polovinu, která selhala třikrát z pěti, je pozpátku.

Že to není teoretická obava, ukázalo první kolo oponentury: první verze
pravidla propouštěla „jeden **informativní** špinavý řádek" — a
„informativní" **není údaj, který dirty-set nese**, takže by to join nedokázal
spočítat. To je přesně to, co jeden datový bod kupuje: pravidlo vyladěné na
jeden případ.

## Aktivační podmínka

Tenhle návrh se aktivuje (přesun `next/ → active/`), až budou splněné obě:

1. **Mechanika z UMS-3488 je hotová a použitá** — `mb-epic-run ready` tiskne
   obě existující tabulky, `spawn` funguje.
2. **Proběhla dvě až tři další rozjetí** a jejich skutečné rozhodnutí je
   zapsané v ledgeru epiku. Pokud se ruční čtení dvou tabulek v některém z
   nich rozešlo s tím, co by řekla pravidla níž, pravidla se **předělají**,
   ne zakódují.

Do té doby je hodnota mechaniky ta, že klasifikaci **umožňuje ověřit
zpětně**: každé rozjetí zapíše, jak se rozhodlo, takže po třech je k
dispozici vzorek, ne dojem.

## Scope (předpokládaný)

- Klasifikace tiketů epiku do tříd s pojmenovaným důvodem.
- `-Json` pro `epic-graph.ps1` a pro `ledger-status.ps1`.
- Křížová reference v `mb-epic-graph/SKILL.md` na to, že o rozjetí
  nerozhoduje glyph.
- Rozhodnutí, jestli klasifikace patří do `mb-epic-run`, do
  `mb-epic-graph`, nebo do uzávěrky `mb-epic-elaboration`.

**Mimo rozsah:** doporučení množiny ke spuštění („spusť tyhle tři"). Vážící
výstup by sváděl k řízení se jím bez čtení důvodů, což je právě past 240
(níž). Množinu vybírá operátor.

## Návrh klasifikace (k ověření, ne k zakódování)

**Glyph sám je past, a to je celý důvod, proč by join existoval.**
SKODASMS-240 svítilo `▶️` „připraveno k implementaci" a přitom mělo tři
špinavé řádky — jeho zadání přestalo po SKODASMS-239 a SKODASMS-250 platit ve
třech bodech. Kdo se řídí ikonou, postaví mock podle zadání, které dvakrát
pozbylo platnosti. Graf o dirty-setu neví a vědět nemá.

Zdroje, které by se spojovaly (žádný se nepřepočítává podruhé):

| Zdroj | Co dává | Co mu chybí |
|---|---|---|
| `mb-epic-graph` | stavový glyph (Jira stav + odblokovanost podle `Blocks` + existence návrhu) a vlny | `-Json` |
| `ledger-status.ps1` | dirty-set; aktuálně špinavé = prázdný sloupec „Vyčištěno oknem" | `-Json`; klíčem je `Položka/Tiket`, takže „špinavé řádky tiketu X" jdou přes sloupec `Vlastník` tabulky položek |
| `doc-index.ps1` | kolize aktivní práce a kde leží draft | cílený sken (vlastní tiket) |
| `pool-status.ps1` | volné a obsazené sloty | staví se v UMS-3488 |

**Graf musí dostat informaci o návrzích, jinak je `▶️` nedosažitelné.** Bez
`-ProposalPath` glyph degraduje na `❔` a bez `-IndexFile` se draft ležící na
větvi jiného aktéra glyphuje `💡` místo `▶️`. Klasifikace proto musí nejdřív
spustit `doc-index.ps1 -Json` a jeho výstup předat grafu — stejné pořadí,
jaké `mb-epic-elaboration` už má. Bez toho by tiket, jehož předběžný návrh
leží v klonu kolegy, klasifikoval jako „chybí návrh → start brainstormingem"
a spawnuté sezení by přepsalo existující návrh vlastním.

Navrhované třídy — **čtyři, ne tři**, protože epik vždy obsahuje i hotové a
rozpracované tikety a klasifikace, která nepokrývá celý epik, není
klasifikace:

- **ROZJET** — glyph `▶️`, žádný otevřený špinavý řádek, návrh dosažitelný,
  žádná kolize, větev nevyzvednutá jinde, volný slot.
- **ROZHODNI** — glyph `💡` nebo `❔`: odblokováno **bez návrhu**. Legitimní
  stav, ale znamená start brainstormingem, ne prohloubení — a to rozhodnutí
  skill udělat nemůže.
- **NEROZJET** — jmenovaný blokátor: **kterýkoli otevřený špinavý řádek** (a
  které to jsou), tvrdá `Blocks` závislost na tiketu, který není
  done-for-planning, větev vyzvednutá jinde, kolize aktivní práce, nebo
  **selhavší kolizní orákulum** (nedoběhlá kontrola není „žádná kolize").
- **MIMO** — není kandidát: glyph `✅`, `🧪`, `👀` nebo `🔨`. Bez téhle třídy
  by hotový tiket, jehož návrh leží v `completed/` a v `next/` tedy žádný
  není, spadl do ROZHODNI jako „chybí návrh" a nabídl by se k rozjetí
  brainstormingem.

**Špinavý řádek posílá tiket vždy do NEROZJET.** Fail-closed čtení odpovídá i
tomu, jak operátor 244 („jeden špinavý řádek + otevřená E-26") reálně
rozhodl — nerozjelo se.

Řazení podle vlny a pak podle počtu odblokovaných tiketů. Obojí je
derivované z grafu, ne úsudek.

Počet volných slotů se hlásí jako **informace, ne limit výběru**.

## Otevřené otázky pro aktivaci

1. **Sedí čtyři třídy na tři další rozjetí?** Zapsaná rozhodnutí to ukážou.
   Zvlášť: potvrdí se, že každý otevřený špinavý řádek je stopka, nebo se
   najde případ, kdy operátor rozjede i tak?
2. **Kam klasifikace patří?** Druhá oponentura namítá, že `mb-epic-run` je
   čtvrté české `description` v téže sémantické čtvrti a že triggering řídí
   výhradně `description`; alternativa je režim `mb-epic-graph` (už počítá
   vlny a už konzumuje `-IndexFile`) nebo krok uzávěrky
   `mb-epic-elaboration`. Rozhodnout podle toho, jestli operátor v praxi
   trefuje správný skill.
3. **Stačí `-Json` jen na ledgeru?** Tabulka vln je už dnes strojově
   čitelnější než český textový report a `epic-graph.ps1` sám JSON
   **konzumuje** (`-IndexFile`), takže asymetrie je menší, než se zdálo.
4. **Nezaslouží si `ready` místo klasifikace jen vykřičník?** Mezivarianta:
   tisknout obě tabulky a přidat jen zvýraznění u tiketu s otevřeným
   špinavým řádkem, se jmenovanými řádky — chytilo by to jediný změřený
   úsudkový problém bez kódování celé taxonomie.

## Rizika

**Klasifikátor, kterému operátor přestane věřit, je horší než dvě tabulky.**
Návrh sám říká, že nebezpečí je „řízení se výstupem bez čtení důvodů" — a
klasifikátor, který jmenuje důvod, je jeden krok od toho, aby se čtenému
verdiktu věřilo bez čtení důvodu. Dvě tabulky vedle sebe si čtení vynucují.

**`-Json` na dvě orákula existuje jen pro tento join.** Pokud se klasifikace
neaktivuje, je to práce bez konzumenta — proto je odložená s ní, ne
dopředu.
