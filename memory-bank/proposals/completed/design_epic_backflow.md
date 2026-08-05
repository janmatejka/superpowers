# Návrh: Zpětný tok z návrhu do epiku + fallback Jira stavu Design Review

- **Jira:** (žádný tiket)
- **Target MB:** memory-bank/
- **Vytvořeno:** 2026-08-04
- **Schváleno:** 2026-08-05

## Cíl

Dvě spojené úpravy vrstvy:

1. **Zavřít chybějící zpětný tok z návrhu do epiku.** Vrstva má silný dopředný
   tok (epic → předběžný návrh v `next/` → aktivace → návrh → plán) i silný
   koncový (harvest → MB dokumenty), ale mezi nimi chybí propojení: když se
   při zpřesňování návrhu ukáže jiný rozsah nebo nová závislost, nic to do
   epiku nepropíše. Graf epiku (`mb-epic-graph`) je snímek z okamžiku
   elaborace a od té chvíle se s realitou rozchází přesně tam, kde je práce
   nejcennější.
2. **Odblokovat design review workflow fallbackem Jira stavu.** Stav
   „Design Review" se v Jira instanci zatím nepodařilo nakonfigurovat a
   kontrakt na jeho absenci reaguje fail-closed STOPem — celý design review
   workflow je tím blokovaný. Fallback ho převede na existující stav „Review"
   s rozlišovacím markerem.

## Scope

**V rozsahu:**

- nový krok „kontrola grafu epiku" v overlay `brainstorming` za Architect
  Review Gate, spouštěný po finálním schválení návrhu (po resume, když review
  bylo; hned po schválení specu, když nebylo),
- zafrontování poznámky do ledgeru elaborace a nabídka inline elaboračního
  okna na hranici fáze,
- normativní pravidla obou úprav v kontraktu (bump 2.6 → 2.7),
- fallback stavu „Design Review" → „Review" + marker `[DESIGN REVIEW]`
  v request komentáři, včetně aliasu ve všech konzumentech detekce stavu.

**Mimo rozsah:** změna algoritmu grafu nebo orákula (skript `epic-graph.ps1`
se kódově nemění); automatické přepisování Jira linků; jakékoli automatické
spuštění elaborace; konfigurace stavu „Design Review" v Jiře samotné.

## Technický návrh

### Část 1 — Zpětný tok z návrhu do epiku

#### 1.1 Spouštěč je existující orákulum, ne metrika rozdílu rozsahu

„Větší změna" jako spouštěč potřebuje mechanickou definici, jinak je to dojem.
Jediné poctivé kotvení je nechat rozhodnout **`mb-epic-graph -Check`**: po
finálním schválení návrhu se orákulum spustí a **nález týkající se tohoto
tiketu** je tím spouštěčem. Žádná nová metrika — použije se konzistenční
kontrola text ↔ linky, kterou vrstva už má. Nálezy k cizím tiketům se jen
vypíšou. Skript je read-only, takže samotné spuštění je bezpečné a levné.

#### 1.2 Kdy krok běží a kdy odpadá

- **Pořadí vůči Architect Review Gate:** kontrola běží **po vyřešení review**
  — při `mb-architect-review` resume, nebo hned po schválení specu, když
  review nebylo. Review může návrh změnit, takže kontrola před ním by se
  dělala dvakrát.
- **Bez tiketu krok tiše odpadá** — práce bez tiketu do epiku nepatří; není
  to výjimka, ale normalita, proto bez ohlášení.
- **Bez dostupného Atlassian MCP se krok přeskočí s jednovětým ohlášením.**
- **Fail-open:** když orákulum spadne nebo Jira není dostupná, krok se
  přeskočí s ohlášením — nikdy neblokuje schválený návrh.

#### 1.3 Elaborace se nabízí, nikdy nespouští

`mb-epic-elaboration` je záměrně **lidské okno** s vlastním ledgerem,
dirty-setem a invarianty. Krok ji smí jen **nabídnout**; rozhodnutí je
uživatelovo. Toto pravidlo je v kontraktu explicitně, protože „graf je
nekonzistentní" je přesně ta situace, ve které agent sklouzne k tomu, že to
„jen dorovná".

#### 1.4 Poznámka do ledgeru se frontuje vždy, elaborace je volba

Při nálezu orákula se **vždy zafrontuje poznámka do ledgeru elaborace** ve
tvaru „návrh `<slug>` změnil `<co>`; okno by mělo přehodnotit `<co>`" — nic
se neztratí, i když uživatel elaboraci odloží. Poznámka se zapisuje do
ledgeru posledního elaboračního okna epiku; když žádný neexistuje, do nového
souboru poznámek vedle místa, kde ledger vzniká, aby ji příští okno našlo
(přesný tvar určí implementační plán podle mechaniky `mb-epic-elaboration`).

Pak agent nabídne:

- **(a) elaborovat hned — inline okno v tomto sezení.** Krok stojí na hranici
  fáze s čistým stromem, takže přepnutí větve je legální: sezení přepne na
  elaborační větev založenou z `<baseRef>`, interaktivně proběhne okno,
  uzávěrka jedním commitem, push, návrat na tiketovou větev, pokračuje
  writing-plans. Subagenti se uvnitř okna smí použít na mechanickou práci —
  to je dispatch detail, ne architektura.
- **(b) nechat jen poznámku a pokračovat** — lidské okno se odkládá na dobu,
  kdy ho člověk chce.

Artefakty elaborace tím nikdy neskončí na tiketové větvi (okno se zavírá
jedním commitem na vlastní větvi; na tiketové větvi by při fast-forward
integraci odešel do báze jako součást tiketu — dvě různé jednotky práce
v jedné historii). Dřívější úvaha draftu „vlastní větev ⇒ samostatné sezení
⇒ `mb-park`" byla silnější, než kontrakt vyžaduje — parkování zůstává
obecným nástrojem workspace, ale tento krok ho nepotřebuje.

#### 1.5 Místo zásahu a domov pravidla

Nový krok žije v overlay fragmentu `brainstorming.overlay.md` za Architect
Review Gate; větev „po resume" znamená malý doplněk kroku resume ve skillu
`mb-architect-review`. Normativní pravidlo (pořadí, fail-open povaha, zákaz
automatického spuštění elaborace, podmínky inline okna: jen hranice fáze
s čistým stromem, elaborační větev z `<baseRef>`, návrat na tiketovou větev
jako součást kroku) dostane **novou podsekci v kontraktu** — pravidlo má
jeden domov, overlay a skilly na něj odkazují.

### Část 2 — Fallback Jira stavu „Design Review" → „Review"

Domov pravidla: kontrakt, sekce Architect Review Gate, Jira conventions.

1. **Request** nejdřív zkusí přechod do „Design Review". Když přechod
   neexistuje, použije přechod do **„Review"** a do request komentáře přidá
   zřetelný první řádek **`[DESIGN REVIEW]`** — marker rozlišující design
   review od běžného review (code review / test). Fallback se uživateli
   ohlásí; STOP nastává až když chybí i přechod do „Review".
2. **Detekce režimu** (`mb-architect-review`, určení request/respond/resume):
   „tiket v Design Review" se rozšiřuje na „tiket v Design Review, NEBO
   v Review s request komentářem nesoucím marker `[DESIGN REVIEW]`". Request
   komentář už dnes nese řešitele a větev, takže žádná nová evidence
   nevzniká — marker jen zpřesňuje existující nosič.
3. **Resume a úklidové cesty** (`mb-abort`, krok Jira úklidu; finishing
   overlay) používají stejný alias: „sedí v Design Review" zahrnuje fallback
   tvar. Resume přechází do „In Progress" beze změny.
4. **`mb-epic-graph`** (glyf 👀): graf do Jira komentářů nevidí, takže
   fallback tvar dostane glyf podle stavu „Review". To je přiznaná,
   dokumentovaná nepřesnost fallbacku, ne vada k řešení — glyf je
   informativní a opraví se sám, až stav v Jiře vznikne.

**Degradace markeru:** smaže-li marker někdo v Jiře, detekce režimu spadne na
existující cestu „respond bez request komentáře: zeptej se uživatele, nikdy
nehádej" — bezpečná degradace.

**Dočasnost:** fallback je můstek — až „Design Review" v Jiře vznikne,
primární cesta ho přirozeně přestane používat; žádná konfigurace, žádný
přepínač.

## Dopady

Vše `ums/.claude/`, čistě textové změny — žádný nový kód:

| Soubor | Změna |
|---|---|
| `shared/UMS_MEMORY_BANK_CONTRACT.md` | nová podsekce zpětného toku; úprava Jira conventions (fallback); bump verze 2.6 → 2.7 |
| `shared/overlays/brainstorming.overlay.md` | nový krok za Architect Review Gate (odkaz na kontrakt) |
| `mb-architect-review/SKILL.md` | detekce režimu s aliasem fallbacku; resume spouští kontrolu grafu |
| `mb-abort/SKILL.md` | krok Jira úklidu — alias „Design Review" včetně fallback tvaru |
| `shared/overlays/finishing-a-development-branch.overlay.md` | totéž aliasování v nabídce Jira úklidu |
| `mb-epic-elaboration/SKILL.md` | tvar a místo poznámky do ledgeru; vstupní cesta „inline okno z brainstorming kroku" |
| `mb-epic-graph/SKILL.md` | dokumentovaná nepřesnost glyfu u fallback tvaru |

Nasazení: změna overlay fragmentů se do vendorovaných kopií promítne až
revendorem v monorepu (`-OverlaysOnly`); kořenový `.claude/` tohoto repa je
po změně zdroje potřeba obnovit kopií. Obojí popisuje `playbook.md` cílové
MB — implementační plán na to dostane explicitní kroky.

## Ověření

Žádný nový skript ⇒ žádná nová testovací sada. Stávajících 13 sad
(564 asercí) musí zůstat zelených — regresní pojistka (`epic-graph.ps1` se
kódově nemění). Textové změny se verifikují proti kontraktu čtením každého
konzumenta; po změně pravidla grep celé vrstvy na charakteristický token
(zde „Design Review") a oprava každého restatementu ve stejném commitu.

## Rizika

| Riziko | Poznámka |
|---|---|
| Nabídka elaborace se stane šumem, který uživatel odklikává | Spouštěčem je nález orákula, ne každé schválení návrhu; frekvence je omezená na skutečné nekonzistence. |
| Poznámka do ledgeru se nikdy nepřečte | Ledger čte `ledger-status.ps1` a otevření dalšího okna; riziko je reálné, ale menší než ztráta zjištění. |
| Krok se stane povinným a zdrží schválení návrhu | Orákulum je read-only skript; když spadne nebo Jira není dostupná, krok se přeskočí s ohlášením, ne fail-closed. |
| Marker `[DESIGN REVIEW]` v komentáři někdo smaže | Detekce spadne na existující cestu „zeptej se uživatele, nikdy nehádej" — bezpečná degradace. |
| Inline okno rozbije stav tiketové větve | Kryje existující pravidlo: přepnutí jen na hranici fáze s čistým stromem; elaborační větev z `<baseRef>`; návrat je součástí kroku. |
