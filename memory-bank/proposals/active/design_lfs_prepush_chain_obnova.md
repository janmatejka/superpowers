# Návrh: Obnova ztraceného LFS pre-push řetězu instalátorem

- **Jira:** — (bez tiketu)
- **Target MB:** memory-bank/
- **Vytvořeno:** 2026-09-14
- **Cesta:** bounded (ohraničená změna existujícího toku `install-git-hooks.ps1`)
- **Evidence:** naměřeno 2026-09-14 v monorepu `D:\_datasys\ums` — tři binárky
  FreeSWITCH (`FreeSwitch/mod/mod_dscurl.dll`, `mod_say_cs.dll`,
  `mod_say_sk.dll`, commit `e3794dc31` z 11. 9.) byly na `origin/develop` jen
  jako LFS pointery; obsah na serveru nebyl. Sonda
  `git -c lfs.storage=<temp> lfs fetch origin develop --include=…` vrátila
  `[404] Object does not exist on the server`.

## Co se stalo

V klonu `D:\_datasys\ums` leží LFS hooky `post-commit`, `post-checkout`
a `post-merge` z 30. 7. 2026, ale `pre-push` je z 7. 9. 2026 náš guard —
a `pre-push.ums-chained` tam **není**. Starší verze instalátoru LFS hook
přepsala, místo aby ho odsunula.

Smudge/clean filtry na tom nezávisí, takže navenek nic nevypadalo rozbitě.
Rozbitý byl jen push: bez hooku od git-lfs `git push` LFS objekty nenahrává.
Pointery odešly, obsah zůstal lokálně, a chyba se projeví až u někoho jiného
při klonu nebo checkoutu.

Rozsah byl přesně tyto tři objekty. Ověřeno porovnáním množiny LFS OIDů na
`develop` před instalací guardu (commit `94c2d8b1e`, 6. 9.) a na HEAD —
porovnáním **podle OIDu**, ne podle cesty, protože 207 LFS souborů repozitáře
nese jen 164 různých OIDů.

## Proč se to neopraví samo

Dnešní `Move-ForeignHook` řeší jen stav, kdy cizí hook na `pre-push`
**ještě leží**: odsune ho na `pre-push.ums-chained` a náš hook ho pak volá.
Klon, kde už byl přepsán, žádný cizí hook nemá. Instalátor tam nevidí nic
k odsunutí, tiše nainstaluje sebe a skončí s exit 0 — opakovaný běh stav
nezmění a nikdo se o něm nedozví. To je ta mezera.

## Oprava

### 1. `install-git-hooks.ps1` — funkce `Restore-LfsChainedHook`

Volaná v hlavní smyčce jen pro `pre-push`, za blokem s cizím hookem a před
`Copy-Item`. Spustí se, jen když platí všechno naráz:

1. `pre-push.ums-chained` neexistuje — když blok výše právě řetězil, soubor
   tam je a krok se přeskočí sám;
2. ve stejném hook adresáři leží LFS sourozenec: `post-commit`,
   `post-checkout` nebo `post-merge`, jehož tělo volá `git lfs <jméno>`;
3. `git lfs` je dosažitelný.

Podmínka 2 je **důkaz, ne domněnka**. Říká „git-lfs sem svoje hooky
nainstaloval, ale `pre-push` mezi nimi chybí". Kde LFS nikdy nebyl, nebo kde
ho `git lfs uninstall` odstranil (maže všechny čtyři hooky naráz), se
nespustí nic — řetěz si nevymýšlíme tam, kam nepatří.

Obsah se **generuje od git-lfs, ne opisuje**: `git init` plus
`git lfs install --local` v dočasném adresáři, ověření, že vygenerovaný
soubor opravdu obsahuje `git lfs pre-push` (nikdy nezapsat soubor, který jsme
si neověřili), bajtová kopie na `<dst>.ums-chained` — bajtová kvůli LF,
protože jde o bezpříponový shellový skript mimo dosah `.gitattributes` —,
provenience stamp ve stejném tvaru jako u `Move-ForeignHook`, a execute bit.
Cílový repozitář se jinak nedotkne ničeho.

Execute bit není kosmetika: `run_chained` gatuje na `[ -x "$chained" ]`
a řetěz bez něj **mlčky přeskočí**, tedy přesně to tiché selhání, kvůli
kterému tahle změna vzniká.

### 2. Exit kódy se nemění

Když `git lfs` chybí nebo `chmod` neprojde, vypíše se červené varování
stejného tvaru jako u dnešního chmodu, ale exit kód zůstane. Kódy 0–4 jsou
dokumentovaný kontrakt vůči `sync-with-monorepo.ps1` a mluví o záruce
Publication Contract, kterou tohle neohrožuje. Rozšiřovat kontrakt kvůli
vedlejší diagnostice by znamenalo, že volající musí nově rozlišovat stav,
který se záruky netýká.

### 3. `mb-state` — detekce i bez instalátoru

Do workspace fitness přibude čistě read-only kontrola: LFS sourozenec je, náš
`pre-push` je, `.ums-chained` není → `⚠️ LFS pre-push chybí (git push
neodesílá LFS objekty)`. Bez ní zůstane poškozený klon poškozený, dokud
někoho nenapadne instalátor pustit. `mb-state` hook nespouští (je read-only),
takže kontrola je `Test-Path` plus jedno čtení souboru — což odpovídá jeho
pravidlu „co soubor JE, nikdy co DĚLÁ".

## Past, kterou hlídá playbook

Proof instalátoru po obnově prochází přes `run_chained` do **skutečného**
`git-lfs`, který resolvuje remote `origin`. Playbook (`Git hooky (POSIX sh)`)
to má naměřené: bez `origin` skončí accept běh exitem 1 a chyba se čte jako
regrese řetězení. Fixtura proto musí mít nakonfigurovaný remote `origin`,
byť fiktivní. Na skutečném repozitáři se to ověřuje zvlášť.

## Testy

Do `ums/.claude/hooks/tests/pre-push.tests.ps1`, kde řetězení už své případy
má. Bez TDD ceremonie — tooling úloha s existující sadou, měřítkem je zelená
sada:

- repo s LFS sourozenci, náš hook, bez řetězu → `.ums-chained` vznikne, je
  spustitelný, obsahuje `git lfs pre-push`, instalátor obnovu pojmenuje;
- druhý běh obnovený soubor nezmění (zrcadlí existující aserci o řetězení);
- repo **bez** LFS hooků → nevznikne nic;
- dnešní cesta s cizím hookem na místě zůstává beze změny;
- kde `git lfs` na stroji není, se případy přeskočí, ne zčervenají.

Negativní běh podle playbooku: sadu spustit i proti neopravenému skriptu
a rozdělit aserce na „zčervenaly" a „zůstaly zelené v obou bězích"
(regresní zámek).

## Šíření

Po opravě `sync-with-monorepo.ps1` do `D:\_datasys\ums`. Repozitář
`pmq_logopedie_nr` sdílí týž mb-* framework — mimo rozsah této položky,
jen se pojmenovává.

## Ověřovací sada

```
pwsh -NoProfile -File ums/.claude/hooks/tests/pre-push.tests.ps1
for t in $(find ums -name "*.tests.ps1"); do echo "== $t"; pwsh -NoProfile -File "$t" || echo "FAILED: $t"; done
```
