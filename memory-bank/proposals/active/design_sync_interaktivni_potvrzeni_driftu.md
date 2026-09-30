# Návrh: Sync — cíl jen po výběru, dotaz na přepsání driftu, srozumitelný exit 4

- **Jira:** (žádný tiket)
- **Target MB:** memory-bank/
- **Vytvořeno:** 2026-09-30
- **Cesta:** bounded

## Cíl

Spuštění `ums/sync-with-monorepo.ps1` nesmí nikdy tiše přepsat cíl, který si
operátor nevybral, a když skript narazí na drift, má nabídnout přepsání rovnou —
bez opětovného zadávání parametrů. Neinteraktivní automatizace se nemění, jen je
bezpečnější.

Podnět (2026-09-30): při nasazení do `pmq_logopedie_nr` skript ohlásil drift
a skončil exit 3; opakované spuštění jen s `-Force` přeskočilo interaktivní
nabídku (podmínka „žádný parametr“) a s výchozími hodnotami přepsalo
`D:\_datasys\ums`. Běh tam skončil vanilla fází (exit 4), což vypadalo jako
chyba; po revertu zůstal v `.git` zastaralý manifest, který by příští běh
hlásil jako falešný drift.

Kritérium úspěchu: interaktivní běh s pouhým `-Force` nebo `-WhatIf` se zeptá na
cíl; neinteraktivní `-Force` bez zadaného cíle nic nezapíše; drift se dá potvrdit
jedním dotazem; hláška exit 4 řekne, že nejde o chybu, a jak postupovat při
revertu.

## Scope

- V rozsahu: nabídka cíle, odmítnutí neinteraktivního `-Force` bez cíle, dotaz
  na drift, text hlášky exit 4, testy, `ums/README.md`.
- Mimo rozsah: změna výchozího `-MonorepoRoot`, detekce revertnutého cíle,
  playbook (mění se jen přes harvestovou bránu).

## Technický návrh

1. **Nabídka cíle.** Čistá funkce `Test-UmsNeedsTargetMenu` vrátí `$true`, když
   není zadaný žádný z parametrů `-Agent`, `-Scope`, `-MonorepoRoot`,
   `-UserProfileRoot`, `-Direction`, `-ForkUmsDir`. Interaktivní nabídka se řídí
   jí — `-Force`, `-WhatIf` ani `-DotSourceOnly` se nepočítají — místo dnešní
   podmínky „žádný parametr“.
2. **Neinteraktivní `-Force` bez cíle** skončí exit 1 s hláškou, že `-Force`
   potřebuje explicitní cíl; nic se nezapíše. `-WhatIf` a běh bez `-Force`
   zůstávají na výchozích hodnotách.
3. **Dotaz na drift.** Interaktivní běh bez `-Force` a bez `-WhatIf` vypíše drift
   všech cílů a zeptá se jednou za celý běh („Overwrite the drifted files listed
   above (same as -Force)? [y/N]“): `y` = pokračuje jako s `-Force`, jinak dnešní
   STOP s nápovědou a exit 3. U prvního běhu (bez manifestu) dotaz upozorní, že
   směr změny není známý a `-Direction FromMonorepo` by přepsal novější fork.
   Rozhodnutí počítá čistá funkce `Resolve-UmsDriftAction` (vstup: `-Force`,
   `-WhatIf`, interaktivita, odpověď; výstup: `proceed` / `stop` / `preview`);
   `Read-Host` zůstává tenkou obálkou.
4. **Hláška exit 4** řekne, že vanilla fáze proběhla úspěšně a exit 4 není chyba,
   a že při revertu cíle místo commitu je nutné nejdřív smazat manifest (s cestou),
   jinak další běh ohlásí falešný drift.

Testy (TDD, prostý PowerShell): jednotkové případy obou funkcí přes dot-source;
end-to-end neinteraktivní `-Force` bez cíle → exit 1 a strom cíle beze změny
(hash), `-Force` s cílem beze změny chování, případ (6) ověří nový text exit 4.
Dokumentace: `ums/README.md` (parametry, dotaz na drift, exit 1 u `-Force`).

## Ověřovací sada

```
for t in ums/tests/*.tests.ps1; do echo "== $t"; pwsh -NoProfile -File "$t" || echo "FAILED: $t"; done
pwsh -NoProfile -File ums/.claude/hooks/tests/sync-marker.tests.ps1
pwsh -NoProfile -File ums/.claude/hooks/tests/pre-push.tests.ps1
```
