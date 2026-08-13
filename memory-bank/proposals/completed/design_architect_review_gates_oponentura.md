# Návrh: Schvalovací brána design review a nezávislá agentická oponentura

- **Jira:** (žádný tiket)
- **Target MB:** memory-bank/
- **Vytvořeno:** 2026-08-13

**Architectural** cesta brainstormingu: zásah do kontraktu, více souborů
včetně overlay fragmentu (revendor) a nový režim skillu. Původní užší verze
(jen schvalovací brána) byla kandidátem na bounded; rozšířením o oponenturu
bounded klasifikace padá.

Návrh má dvě části, které se skládají: **(A) schvalovací brána** před zápisem
posudku do Jiry a **(B) nezávislá agentická oponentura** návrhu. Oponentura
krmí posudek, brána hlídá jeho publikaci.

## Cíl

**(A)** V režimu **respond** skillu `mb-architect-review` (architekt posuzuje
návrh) dnes mezi strukturovaným posouzením (krok 4) a publikací do Jiry +
vrácením tiketu řešiteli (krok 5) není žádná explicitní schvalovací brána —
agent snadno sklouzne k okamžitému zápisu komentáře do Jiry, jakmile má
poznámky zformulované. Architekt má dostat prostor na konverzaci nad návrhem
PŘED jakýmkoli zápisem mimo klon.

**(B)** Posouzení návrhu dnes stojí jen na lidech (autor, architekt). Chybí
volitelná možnost spustit nezávislého agenta s čistým kontextem, který návrh
podrobí oponentuře — identifikuje nedostatky v architektuře, sémantice,
integraci, bezpečnosti a podobných otázkách — dřív, než návrh stojí čas
lidského architekta nebo než se začne plánovat implementace.

## Scope

- `ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md` — část B: nová
  sekce s normativním popisem oponentury (aktér, pořadí kroků, vstupy,
  formát nálezů, triáž, model + effort), bump kontraktu na v2.10 včetně
  přeformulování „Supersedes" historie dle konvence. Důvod: oponenturu
  konzumují tři místa (brainstorming overlay, respond, režim `oppose`) —
  pravidlo má jeden domov v kontraktu, skilly říkají jen „per ‹sekce›".
- `ums/.claude/skills/mb-architect-review/SKILL.md` — část A: sekce
  „Mode: respond (architect)", kroky 4–5 (dnes řádky 207–215); část B: nový
  režim `oppose` + zapojení oponenta jako pomocníka
  architekta v respond; ve stejném commitu úprava `description` ve
  frontmatteru (triggering nové schopnosti řídí výhradně description).
- Overlay fragment brainstormingu
  (`ums/.claude/skills/shared/overlays/brainstorming.overlay.md`) — část B:
  bod nabídky oponentury po schválení specu; změna fragmentu = pořadí
  kopie → revendor dle `playbook.md`.
- Režimy request a resume beze změny. Část A kontrakt nemění — vnitřní
  pořadí kroků jednoho režimu je čistě lokální věc skillu (Architect Review
  Gate v kontraktu popisuje handoff mezi lidmi).

## Technický návrh

### Část A — schvalovací brána v respond

Rozdělit dnešní krok 4 a podmínit krok 5:

1. **Souhrn do konzole nejdřív.** Po načtení návrhu a MB kontextu vypsat
   architektovi český souhrn návrhu (cíl, scope, technický přístup, dopady,
   rizika) — žádný zápis do Jiry, žádná změna assignee, žádný flag.
2. **Konverzace ve stylu brainstormingu.** Dialog nad body architekta
   (jedna otázka po druhé, pomoc s formulací poznámek) — stejný režim, jaký
   resume používá pro zapracování poznámek do návrhu (krok 6 resume). Výstupem
   je finální znění poznámek posudku.
3. **Explicitní brána.** Předložit finální znění a zeptat se (česky):
   „Zapsat posudek do Jiry a vrátit tiket řešiteli?" Teprve po výslovném
   souhlasu provést dnešní krok 5 (komentář, assignee zpět na řešitele, flag
   Impediment, případný push commitů na tiketové větvi). Bez souhlasu se nic
   do Jiry nezapisuje; architekt může konverzaci přerušit a vrátit se k ní.

Poznámka: krok 5 je jediné místo respond režimu se side effecty mimo klon
(Jira), takže brána sedí přesně před něj — commity na tiketové větvi (pokud
architekt něco upravil) zůstávají pod publikačním pravidlem beze změny.

### Část B — nezávislá agentická oponentura

**Dispatch.** Volitelné spuštění nezávislého subagenta s čistým kontextem.
Vstup oponenta: design dokument + MB dokumenty cílové MB (`brief.md`,
`architecture.md`, `tech.md`, `playbook.md` — ty, které existují) + čtecí
přístup ke kódu repozitáře, aby integrační tvrzení návrhu ověřil proti
realitě. Dispatch prompt a výstup oponenta jsou AI-facing → anglicky
(Language Contract).

**Model a effort.** Oponentura je posouzení návrhu, tedy „architecture and
design task" dle superpowers SDD Model Selection: dispatch VŽDY na nejsilnější
dostupný model, nikdy session default, a s nejvyšším reasoning effortem,
který harness u dispatche umí nastavit (Claude Code `effort`, Codex reasoning
effort; harness bez takového parametru nastaví jen model). Obojí uvést
explicitně — vynechaný parametr tiše dědí session, což tuto sekci obchází.
Levný tier je tu falešná úspora: slabá oponentura generuje šum, který pak
stojí dražší triáž a dialog s uživatelem.

**Výstup.** Strukturovaný seznam nálezů; každý nález nese kategorii
(architektura / sémantika / integrace / bezpečnost / jiné), závažnost,
tvrzení a evidenci (odkaz na místo v návrhu, MB dokumentu nebo kódu).
Nález bez evidence oponent nevydává.

**Triáž nálezů řídícím agentem.** Každý nález se roztřídí:

1. **Relevantní a nesporný** → zapracovat rovnou do návrhu.
2. **Sporný, nebo měnící zadání** → soustředěný dialog s uživatelem:
   dávkově, více otázek v jedné iteraci — strukturované otázky harness,
   kde jsou k dispozici, jinak číslovaný seznam v jedné zprávě. Cíl:
   uživatel odpoví na víc bodů najednou, ne ping-pong po jedné otázce.
3. **Irelevantní nebo mylný** → odmítnout s důvodem.

**Závěrečný souhrn (česky).** Po triáži a dialogu předložit uživateli
přehled: „zapracováno bez dotazu" (s možností cokoli vrátit), rozhodnutí
ze sporných bodů, odmítnuté nálezy s důvody. Nic se nezapracovává tiše bez
stopy.

**Tři body zásahu** (všude nabídka — nikdy automatické spuštění):

1. **Brainstorming, po schválení specu** — nabídka oponentury zařazená před
   nabídku Architect Review Gate; agentická oponentura může předfiltrovat
   problémy před lidským architektem. Zapracování nálezů mění schválený spec,
   takže po něm následuje re-approval změněných pasáží uživatelem (souhrn
   výše je jeho podkladem).
2. **Respond režim** — pomocník architekta: nálezy oponenta krmí strukturované
   posouzení (fáze souhrnu a konverzace z části A), tedy poznámky posudku, ne
   přímé úpravy návrhu — návrh v respond patří řešiteli. Triáž tu provádí
   architekt v konverzaci, ne řídící agent sám.
3. **Samostatně na vyžádání** — nový režim `oppose` skillu
   `mb-architect-review`: kdykoli nad existujícím design dokumentem,
   bez vazby na fázi workflow a bez Jira side effectů (žádná transition,
   žádný flag — jen oponentura + triáž + úpravy návrhu na tiketové větvi).

## Dopady

- Architekt vidí a ladí posudek před publikací; do Jiry odchází jen
  odsouhlasené znění.
- Návrhy projdou levnější agentickou oponenturou dřív, než stojí čas lidského
  architekta; lidský architekt dostává návrh už zbavený mechanicky
  odhalitelných vad.
- Kontrakt roste o sekci oponentury (v2.10); request/resume beze změny.
- Nový bod nabídky v brainstorming overlay = změna fragmentu a revendor
  (dopad na monorepo pipeline dle `playbook.md`); po změně zdroje v `ums/`
  je nutné obnovit nasazenou kopii v kořenovém `.claude/` tohoto repa.

## Rizika

- Část A nízké: změna jednoho instrukčního souboru; nejhorší selhání je, že
  agent bránu ignoruje — pak je chování stejné jako dnes (zápis bez brány),
  nikdy horší.
- Oponentura na nejsilnějším modelu není zadarmo — proto je všude volitelná
  nabídka, nikdy automatický běh.
- Šum z oponentury (nálezy bez reálné váhy) může uživatele zahltit — tlumí ho
  povinná evidence u každého nálezu, triáž řídícím agentem a dávkový dialog.
- Zapracování nálezů po schválení specu mění schválený dokument — kryje
  re-approval změněných pasáží (bod zásahu 1).
