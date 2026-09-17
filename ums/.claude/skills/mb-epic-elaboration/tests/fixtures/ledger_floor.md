# Evidence ledger: UMS-1 — testovací epic pro sekci Podlaha testů

- **Epic:** UMS-1 (https://datasyscz.atlassian.net/browse/UMS-1)
- **Režim:** Jira
- **Autonomie:** sdílená
- **Zdroj položek:** Doc/test.md
- **Založeno:** 2026-09-01
- **Poslední aktualizace:** 2026-09-16 (okno W01)

## Položky

| ID | Popis | Vlastník | Stav | Pozn. |
|----|-------|----------|------|-------|
| E-1 | první položka | UMS-3520 | otevřená | |

## Členové (proposaly)

| Člen | Stav | Pozn. |
|-------|------|-------|
| UMS-3520 | nezahájen | |

## Okna

| Okno | Agenda (položky + otázky) | Stav | Datum | Výstup |
|------|---------------------------|------|-------|--------|
| W01 | mechanika podlahy; položky: E-1 | navrženo | 2026-09-16 | |

## Dirty-set

| Položka/Tiket | Zašpiněno oknem | Důvod | Vyčištěno oknem |
|---------------|-----------------|-------|-----------------|

## Podlaha testů

| Test (jméno) | Stav | Naměřil (tiket) | Podmínky běhu | Pozn. |
|---|---|---|---|---|
| WfKic.Test.ChannelResync_ReconnectsAfterDrop | červený | UMS-3520 | čistá ústředna, develop@0a13ef1, 2026-09-16 | |
| 8/705/12/725 | červený | UMS-3518 | | číslo z jiného stromu |
| výsledek dodá sezení | červený | UMS-3520 | dávka | |
| WfKic.Test.SlotResume_KeepsQueuePosition | červený | UMS-3521 | | |

## Ověřovací sada

```
<příkaz 1: build>
<příkaz 2: cílené testy>
```

## Registr rozhodnutí

| Rozhodnutí | Vlastník (tiket) | Předpokládá o (tiket) | Druh | Stav | Potvrzeno (SHA) |
|------------|------------------|-----------------------|------|------|-----------------|
