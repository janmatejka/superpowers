# Evidence ledger: <EPIC-KEY> — <název epiku>

- **Epic:** <EPIC-KEY> (https://datasyscz.atlassian.net/browse/<EPIC-KEY>) — v režimu Jira; v režimu Proposals odkaz na přehledový dokument, např. [_prehled.md](../proposals/next/_prehled.md)
- **Režim:** <Jira | Proposals>
- **Zdroj položek:** <repo-relativní cesta k dokumentu nálezů/požadavků, např. Doc/security-risk-assessment.md>
- **Založeno:** <YYYY-MM-DD>
- **Poslední aktualizace:** <YYYY-MM-DD> (okno <W##>)
- **Graf závislostí:** generuje se z Jira linků (Jira) nebo z proposal odkazů (Proposals) skillem `mb-epic-graph` — nikdy needitovat ručně

> **Pravidla údržby.** Každá položka má právě jednoho vlastníka — Jira klíč
> v režimu Jira, proposal slug v režimu Proposals. Stavy a disciplínu definuje
> skill `mb-epic-elaboration`. Strukturu tabulek (sloupce, oddělovače) neměnit
> — parsuje je `scripts/ledger-status.ps1`. Řádky dirty-setu se nemažou,
> čištění se zapisuje do posledního sloupce.

## Položky

Stavy položky: `otevřená` → `ověřená` → `rozhodnutá` → `zapsaná` → `uzavřená`;
mimo řadu `vyvrácená` (ověření premisu popřelo — Pozn. říká, co s ní dál).
Vlastník je klíč tiketu (Jira) nebo proposal slug (Proposals), `nepřiřazeno`,
nebo `mimo epic` (s odkazem v Pozn.).

| ID | Popis | Vlastník | Stav | Pozn. |
|----|-------|----------|------|-------|
| <ID-1> | <krátký popis položky> | nepřiřazeno | otevřená | |

## Členové (proposaly)

Stavy člena: `nezahájen` → `ověřen` → `rozhodnut` → `návrh zapsán` →
`srovnán` → `hotov`. `hotov` smí být jen tehdy, když všechny jeho položky
jsou `uzavřená` a žádná z nich není aktuálně v dirty-setu. V režimu Jira je
členem tiket (Jira klíč), v režimu Proposals proposal slug.

| Člen | Stav | Pozn. |
|-------|------|-------|
| <KEY-1 nebo slug-1> | nezahájen | |

## Okna

Stavy okna: `navrženo` → `agenda potvrzena` → `probíhá` → `uzavřeno`.
Agenda vyjmenovává položky (ID) a otevřené otázky okna.

| Okno | Agenda (položky + otázky) | Stav | Datum | Výstup |
|------|---------------------------|------|-------|--------|
| W01 | <téma; položky: ID, ID; otázky: …> | navrženo | <YYYY-MM-DD> | |

## Dirty-set

Aktuálně špinavé = řádky s prázdným sloupcem „Vyčištěno oknem".

| Položka/Tiket | Zašpiněno oknem | Důvod | Vyčištěno oknem |
|---------------|-----------------|-------|-----------------|
