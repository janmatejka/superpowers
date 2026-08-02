# Playbook

Postupy, kterými se tato vrstva staví, testuje a nasazuje. Popisný stav — verze
a piny, inventář souborů, konfigurace, pasti prostředí — je v
[tech.md](tech.md); jak vrstva funguje, popisuje [architecture.md](architecture.md).

## Testy vrstvy

Jednu sadu spustíš přímo, celou vrstvu smyčkou:

```bash
pwsh -NoProfile -File ums/.claude/skills/mb-doc-index/tests/enumeration.tests.ps1
for t in $(find ums -name "*.tests.ps1"); do echo "== $t"; pwsh -NoProfile -File "$t" || echo "FAILED: $t"; done
```

Zelená sada končí řádkem `<N> passed` a nulovým exit kódem; při selhání vypíše
`<N>/<M> FAILED` a vrátí `1`.

Konvence, které nová sada musí dodržet:

- **Žádný Pester, jen obyčejný `.ps1` skript s vlastními aserčními funkcemi.**
  Proč: vrstva je bezzávislostní, takže test nesmí předpokládat nainstalovaný
  PowerShell modul — jinak by ho nešlo spustit v čerstvém klonu ani u
  uživatele, který si vrstvu jen nasadil.
- **`_assert.ps1` má vlastní kopii každý adresář testů**
  (`ums/.claude/skills/<skill>/tests/`, `ums/.claude/hooks/tests/`); sada ho
  natáhne přes `. (Join-Path $PSScriptRoot '_assert.ps1')` a poskytuje
  `Assert-True`, `Assert-Match`, `Assert-NotMatch`, `Assert-Eq`
  a `Complete-Tests`.
  Proč: nasazení kopíruje celé adresáře skillů (`sync-with-monorepo.ps1` bere
  `shared` a každý `mb-*` zvlášť), takže helper ležící mimo adresář skillu by
  s ním k uživateli neputoval. Kopie se smí lišit — každá nese jen to, co její
  sada používá.
- **Sada leží vedle kódu, který testuje**, v podadresáři `tests/`, a jmenuje se
  `<téma>.tests.ps1`. Do nového adresáře testů zkopíruj i `_assert.ps1`.
- **Testy běží offline.** Kde je potřeba vzdálený repozitář, sestaví se lokální
  bare klon jako „origin" (`new-fixture-repo.ps1` u `mb-doc-index`, vlastní
  bare remote u `pre-push`).
  Proč: sada nesmí sáhnout na síť, na `origin` ani do Jiry — jinak by červená
  sada neznamenala regresi, ale výpadek okolí.
- Testovací Memory Bank dokumenty ukládej pod `tests/fixtures/`.
  Proč: indexace MB dokumentů tuto cestu vylučuje, takže fixtury nespadnou do
  indexu ani do kolizních nálezů.

## Upgrade upstreamu (revendor)

Vendorované kopie s overlay bloky vznikají až v cíli nasazení, takže revendor
běží **v monorepu**, ne v tomto repu. Postup je dvoucommitový:

1. V tomto forku sloučit nový upstream: `git fetch vanila --tags`, pak
   `git merge vanila/main` (na `main`, odtud do `ums-memory-bank`).
2. V monorepu:
   `pwsh .claude/scripts/revendor-superpowers.ps1 -Tag <nový tag> -NoOverlays`
   → commit „vanilla sync".
3. `pwsh .claude/scripts/revendor-superpowers.ps1 -OverlaysOnly`
   → commit „overlay".

Proč dva commity: první nese výhradně upstream diff, druhý výhradně zásah UMS.
Ve sloučeném commitu už nejde poznat, co přinesl upstream a co vrstva.

- **Vendorované soubory nikdy needituj ručně mimo bloky
  `<!-- UMS-OVERLAY BEGIN/END -->`.** Změna patří do fragmentu
  `shared/overlays/*.overlay.md` a aplikuje se dalším během.
  Proč: revendor rozbalí upstream znovu a overlaye aplikuje na čistý soubor —
  ruční úprava mimo bloky se tím tiše ztratí.
- **Miss kotvy `ANCHOR-BEFORE` je detektor driftu upstreamu, ne chyba
  k obejití.** Kotva musí matchovat právě jeden řádek cílového souboru; když
  nematchuje, upstream ten řádek změnil. Skript přitom vypíše přesně ty
  fragmenty, které potřebují lidský zásah — oprav je, synchronizuj zpět do
  forku a spusť revendor znovu; nikdy kotvu neuvolňuj, aby „prošla".
- Verifikační pass běží vždy jako poslední a shodí skript na viselých
  relativních odkazech, zbytcích v5 souborů, chybějících v6 souborech,
  nevyvážených overlay markerech, CRLF v bashových skriptech a na funkčním
  testu SDD skriptů v Git Bashi. Běh je hotový, teprve když skončí
  `Verification passed.`
- Samotnou verifikaci bez vendoringu spustíš přepínačem `-VerifyOnly`.

## CRLF u bezpříponových shellových skriptů

Bashové skripty bez přípony — upstream SDD skripty (`sdd-workspace`,
`task-brief`, `review-package`) a git hook
[`ums/.claude/hooks/pre-push`](../ums/.claude/hooks/pre-push) — musí být
v pracovním stromu s LF.

- **Nevendoruj je prostým `git archive` při `core.autocrlf=true`.** Konverze na
  CRLF rozbije shebang a skript přestane jít spustit. `revendor-superpowers.ps1`
  proto po rozbalení normalizuje konce řádků na LF a verifikační pass CRLF
  kontroluje.
- **Nový bezpříponový shellový soubor commitni až s pravidlem `text eol=lf`**
  v `.gitattributes` (v monorepu `.claude/skills/** text eol=lf`, v tomto forku
  [`ums/.gitattributes`](../ums/.gitattributes)).
  Proč: git podle přípony nepozná, že jde o skript, takže bez pravidla ho
  `core.autocrlf` na Windows převede — a chyba se projeví až u toho, kdo si
  soubor checkoutuje.

## Nasazení vrstvy

`pwsh ums/sync-with-monorepo.ps1` bez parametrů se v interaktivní konzoli
doptá na každý parametr a nabídne default (Enter potvrdí); v neinteraktivním
běhu použije defaulty potichu.

| Parametr | Hodnoty | Default |
|---|---|---|
| `-Agent` | `claude`, `codex`, `gemini`, `kilocode` | `claude` |
| `-Scope` | `Monorepo`, `UserProfile` | `Monorepo` |
| `-Direction` | `FromMonorepo`, `ToMonorepo` | `FromMonorepo` |
| `-MonorepoRoot` | cesta ke klonu monorepa | `D:\_datasys\ums` |

- **`claude` + `Monorepo` je jediná obousměrná kombinace.** `FromMonorepo`
  (default) táhne živou kopii z monorepa do `ums/` tohoto forku — spusť ji po
  každé změně vrstvy provedené v monorepu a výsledek commitni. `ToMonorepo` je
  opačný směr. Každá jiná kombinace je jednosměrný deploy z `ums/` do cíle
  a `-Direction` se ignoruje.
- `gemini` a `kilocode` nemají adresář skillů — dostanou jen glue a blok
  preferencí v instrukčním souboru.
- **`settings.json` se na ne-Claude cíle nenasazuje.**
  Proč: je to registrační soubor Claude Code a přepsal by cizí konfiguraci
  (například `.gemini/settings.json`) — u ostatních harnessů se hooky registrují
  ručně.
- Glue soubory se do cílového config adresáře **mergují po souborech** a nikdy
  nemažou cizí obsah. Blok preferencí se do instrukčního souboru vkládá mezi
  markery `UMS-MEMORY-BANK BEGIN/END`, takže opakovaný běh ho nahradí na místě.
  Při `-Scope UserProfile` se před blok přidá věta omezující platnost pravidel
  na monorepo.
- Vendorované superpowers skilly tento skript nesynchronizuje nikdy — ty
  vznikají revendorem (výše).

### Instalace git hooků do klonu

```bash
pwsh -NoProfile -File ums/.claude/hooks/install-git-hooks.ps1 -RepoRoot <klon>
```

Proč vůbec: git hooky jsou netrackované, takže se s klonem nepřenesou —
`pre-push` záruka publikačního kontraktu v novém klonu chybí, dokud ji tam
někdo nenainstaluje.

- Při `-Scope Monorepo` ho volá `sync-with-monorepo.ps1` sám; při
  `-Scope UserProfile` ne (profil nemá jeden přiřazený repozitář), tam ho spusť
  ručně.
- **Nenulový exit instalátoru neignoruj** — znamená, že záruka není potvrzená:
  `1` = self-test selhal, `2` = ponechán cizí hook, `3` = nainstalováno, ale
  neověřeno (chybí shell pro self-test). Sync ho jen vypíše jako varování
  a pokračuje, takže v dlouhém výpisu snadno zapadne.

### Obnova nasazené kopie v tomto repu

Kořenový `.claude/` a `.agents/skills/` jsou netrackovaná nasazení, ale sezení
v tomto repu čte právě je. **Po každé změně zdroje v `ums/.claude/` nasazení
obnov**, jinak agent pracuje podle staré verze kontraktu i skillů.

- UMS obsah (`shared/`, `mb-*`, `hooks/`, `scripts/`, `settings.json`) je prostá
  kopie z `ums/.claude/` do kořenového `.claude/`; pro Codex ještě
  `ums/.claude/skills/` do `.agents/skills/`.
- Kontrola, že je nasazení aktuální: `Contract-Version` v
  `.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md` musí souhlasit se zdrojem
  a v `.claude/skills/` musí být všechny adresáře `mb-*`, které jsou
  v `ums/.claude/skills/`. Chybějící skill je nejrychlejší příznak zastaralého
  nasazení.
- Tři upstream skilly s overlay bloky (`brainstorming`,
  `subagent-driven-development`, `finishing-a-development-branch`) se kopií
  nevyrobí — po změně overlay fragmentu je musí vygenerovat revendor.
- `sync-with-monorepo.ps1` na tohle není: cílí na monorepo nebo na profil
  uživatele, ne na kořen tohoto forku.
