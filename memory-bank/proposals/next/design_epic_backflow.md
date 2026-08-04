# Návrh: Zpětný tok z návrhu do epiku

- **Jira:** (žádný tiket)
- **Target MB:** memory-bank/
- **Vytvořeno:** 2026-08-04

> Předběžná položka v `proposals/next/`. Nezasahuje do `context.md`, nepočítá se
> do limitu aktivních prací a implementační plán se pro ni předem nepíše.
> Vznikla jako odštěpek z práce `branch_model_integrace`, aby se úvaha
> nemusela odvozovat znovu.

## Cíl

Zavřít chybějící **zpětný tok z návrhu do epiku**. Vrstva má silný dopředný tok
(epic → předběžný návrh v `next/` → aktivace → návrh → plán) i silný koncový
(harvest → MB dokumenty), ale mezi nimi chybí propojení: **když se při
zpřesňování návrhu ukáže jiný rozsah nebo nová závislost, nic to do epiku
nepropíše.**

Graf epiku (`mb-epic-graph`) se generuje z Jira linků a hlaviček návrhů
v okamžiku elaborace. Od té chvíle je to snímek stavu, který se s realitou
rozchází přesně tam, kde je práce nejcennější — v okamžiku, kdy řešitel zjistí,
že tiket obsahuje víc nebo něco jiného, než se při rozpadu epiku předpokládalo.

## Kontext

Práce `branch_model_integrace` tuto mezeru nezavírá, ale dva její výstupy jsou
pro ni předpoklady:

- **Push po každém commitu** dělá vstupy grafu čerstvější — návrh je na `origin`
  dřív, takže graf i orákulum vidí aktuální stav bez čekání na konec větve.
- **`mb-park`** je primitiv, který tato práce potřebuje (viz Technický návrh,
  bod 3). Vznikl nezávisle, pro disciplínu workspace; tento scénář je jeho první
  reálný konzument mimo prokládání tiketů.

## Scope

**V rozsahu:** místo zásahu po schválení návrhu; spouštěč založený na
existujícím orákulu; zápis poznámky do ledgeru elaborace; pravidla o tom, kde
elaborace smí a nesmí běžet.

**Mimo rozsah:** změna algoritmu grafu nebo orákula; automatické přepisování
Jira linků; jakékoli automatické spuštění elaborace.

## Technický návrh

### 1. Spouštěč je existující orákulum, ne metrika rozdílu rozsahu

„Větší změna" jako spouštěč potřebuje mechanickou definici, jinak je to dojem.
Jediné poctivé kotvení je nechat rozhodnout **`mb-epic-graph -Check`**: po
schválení návrhu se orákulum spustí a **nález týkající se tohoto tiketu** je
tím spouštěčem. Žádná nová metrika, žádné hádání — použije se konzistenční
kontrola text ↔ linky, kterou vrstva už má.

Skript je read-only, takže samotné spuštění je bezpečné a levné.

### 2. Elaborace se nabízí, nikdy nespouští

`mb-epic-elaboration` je záměrně **lidské okno** s vlastním ledgerem, dirty-setem
a invarianty. Krok po schválení návrhu ji tedy smí jen **nabídnout**
s doporučením; rozhodnutí je uživatelovo. Tohle pravidlo je nutné napsat
explicitně, protože „graf je nekonzistentní" je přesně ta situace, ve které
agent sklouzne k tomu, že to „jen dorovná".

### 3. Artefakty elaborace nesmí skončit na tiketové větvi

Kontrakt (sekce Cross-Branch Visibility) říká, že elaborační okno se zavírá
**jedním commitem** nesoucím ledger, graf i všechny proposaly okna. Na tiketové
větvi by ten commit při fast-forward integraci odešel do báze jako součást
tiketu — dvě různé jednotky práce v jedné historii.

Elaborace proto patří na vlastní větev, tedy do **samostatného sezení**. Postup:
zaparkovat tiket (`mb-park`), provést elaboraci, vrátit se. Právě proto je
`mb-park` předpokladem této práce.

### 4. Nejlevnější varianta: poznámka do ledgeru

Když uživatel elaboraci nechce hned, nemá se ztratit zjištění. Ledger elaborace
je vlastní evidence toho okna, takže tam poznámka patří — ve tvaru „návrh
`<slug>` změnil `<co>`; okno by mělo přehodnotit `<co>`", bez spuštění čehokoli.
Odloží to lidské okno na dobu, kdy ho člověk chce, a nic se nezapomene.

Tohle je pravděpodobně **jediná část, která se má postavit jako první** — je
nezávislá na zbytku a sama o sobě mezeru z velké části zavírá.

### 5. Místo zásahu

Přirozeným místem je overlay `brainstorming`, kde už dnes po schválení návrhu
sedí Architect Review Gate. Pořadí obou bran je otevřená otázka (níže).

## Otevřené otázky

- **Pořadí vůči Architect Review Gate.** Má se graf kontrolovat před nabídkou
  design review, nebo po jejím vyřešení? Argument pro „před": architekt uvidí
  i důsledky pro epic. Argument pro „po": review může návrh změnit, takže by se
  kontrola dělala dvakrát.
- **Jak se zjistí epic tiketu.** Graf potřebuje vědět, ke kterému epiku tiket
  patří; dnes to plyne z Jira linků, tedy z dotazu do Jiry. Bez Atlassian MCP je
  potřeba JIRA-less cesta, nebo se krok přeskočí.
- **Chování bez tiketu.** Práce bez navázaného tiketu do epiku nepatří, takže
  celý krok pravděpodobně odpadá — potvrdit.

## Rizika

| Riziko | Poznámka |
|---|---|
| Nabídka elaborace se stane šumem, který uživatel odklikává | Spouštěčem je nález orákula, ne každé schválení návrhu; frekvence je tím omezená na skutečné nekonzistence. |
| Poznámka do ledgeru se nikdy nepřečte | Ledger čte `ledger-status.ps1` a otevření dalšího okna; riziko je reálné, ale menší než ztráta zjištění. |
| Krok se stane povinným a zdrží schválení návrhu | Orákulum je read-only skript; když spadne nebo Jira není dostupná, krok se přeskočí s ohlášením, ne fail-closed. |
