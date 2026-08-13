# Návrh: Schvalovací brána před zápisem design review do Jiry

- **Jira:** (žádný tiket)
- **Target MB:** memory-bank/
- **Vytvořeno:** 2026-08-13

Předběžný návrh (fronta `next/`) — aktivuje se, až na něj dojde řada.
Kandidát na **bounded** cestu brainstormingu (po upgradu na v6.3.0): dobře
ohraničená změna existujícího flow v jednom souboru; zároveň poslouží jako
akceptační sezení nové bounded cesty.

## Cíl

V režimu **respond** skillu `mb-architect-review` (architekt posuzuje návrh)
dnes mezi strukturovaným posouzením (krok 4) a publikací do Jiry + vrácením
tiketu řešiteli (krok 5) není žádná explicitní schvalovací brána — agent
snadno sklouzne k okamžitému zápisu komentáře do Jiry, jakmile má poznámky
zformulované. Architekt má dostat prostor na konverzaci nad návrhem PŘED
jakýmkoli zápisem mimo klon.

## Scope

Jeden soubor: `ums/.claude/skills/mb-architect-review/SKILL.md`, sekce
„Mode: respond (architect)", kroky 4–5 (dnes řádky 194–215). Ostatní režimy
(request, resume) beze změny. Kontrakt se nemění — publikace do Jiry je už
dnes krokem 5, mění se jen to, že krok 5 smí začít až po explicitním souhlasu.

## Technický návrh

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

## Dopady

- Architekt vidí a ladí posudek před publikací; do Jiry odchází jen
  odsouhlasené znění.
- Žádná změna pro request/resume ani pro kontrakt (Architect Review Gate
  v kontraktu popisuje handoff, ne vnitřní pořadí respond kroků).

## Rizika

- Nízká: změna jednoho instrukčního souboru; nejhorší selhání je, že agent
  bránu ignoruje — pak je chování stejné jako dnes (zápis bez brány), nikdy
  horší.
