# Evidence ledger: UMS-3401 — testovací epic pro sekci Ověřovací sada

- **Epic:** UMS-3401 (https://datasyscz.atlassian.net/browse/UMS-3401)
- **Režim:** Jira
- **Zdroj položek:** Doc/test.md
- **Založeno:** 2026-09-01
- **Poslední aktualizace:** 2026-09-03 (okno W01)

## Položky

| ID | Popis | Vlastník | Stav | Pozn. |
|----|-------|----------|------|-------|
| E-1 | první položka | UMS-3401 | uzavřená | |

## Členové (proposaly)

| Člen | Stav | Pozn. |
|-------|------|-------|
| UMS-3401 | hotov | |

## Okna

| Okno | Agenda (položky + otázky) | Stav | Datum | Výstup |
|------|---------------------------|------|-------|--------|
| W01 | mechanika sady; položky: E-1 | uzavřeno | 2026-09-02 | |

## Dirty-set

| Položka/Tiket | Zašpiněno oknem | Důvod | Vyčištěno oknem |
|---------------|-----------------|-------|-----------------|

## Rozjetí

| Tiket | Datum | Slot | Verdikt | Draft (větev + cesta) | Pasti |
|-------|-------|------|---------|-----------------------|-------|

## Ověřovací sada

```
pwsh ./build.ps1
pwsh ./test.ps1 -Tag smoke
<příkaz 3: manuální krok>
```

## Registr rozhodnutí

| Rozhodnutí | Vlastník (tiket) | Předpokládá o (tiket) | Druh | Stav | Potvrzeno (SHA) |
|------------|------------------|-----------------------|------|------|-----------------|
