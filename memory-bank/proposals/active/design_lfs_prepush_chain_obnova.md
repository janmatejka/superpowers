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

V klonu `D:\_datasys\ums` ležely LFS hooky `post-commit`, `post-checkout`
a `post-merge` z 30. 7. 2026, ale `pre-push` byl z 7. 9. 2026 náš guard —
a `pre-push.ums-chained` tam **nebyl**. Starší verze instalátoru LFS hook
přepsala, místo aby ho odsunula.

**Akutní případ je od 14. 9. 8:43 spravený ručně** — `pre-push.ums-chained`
v monorepu existuje, je spustitelný, volá `git lfs pre-push` a nese vlastní
komentář o ruční obnově. Minulý čas výše je tedy stav při měření, ne dnešní.
Na rozsahu položky to nemění nic: ruční zásah opravil jeden klon, ne mezeru
v instalátoru, a ostatní klony nikdo neobešel.

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

### 4. Verze hooku na `v3` — aby se oprava vůbec dostala ke slovu

Body 1–3 samy o sobě neopraví klon, který se aktualizuje **přes git**. Oprava
žije celá v instalátoru, a git update `.claude/` doručí skript, ale nespustí
nic. Automaticky volá instalátor jen
[`sync-with-monorepo.ps1`](../../../ums/sync-with-monorepo.ps1) (funkce
`Install-PublicationHooks`, jen pro `-Scope Monorepo`; u `-Scope UserProfile`
skript výslovně hlásí, že hooky neinstaluje) a
[`pool-provision.ps1`](../../../ums/.claude/skills/mb-epic-run/scripts/pool-provision.ps1)
při zakládání slotu. `git pull` není ani jedno.

Vstupní brána sezení to nezachytí, a to je jádro mezery:
[`settings.json`](../../../ums/.claude/settings.json) spouští reinstalaci jen
když hook **chybí nebo je starší než v2**. Poškozený klon má náš hook a **je
v2** — body 1–3 se těla `pre-push` nedotýkají. Brána projde, instalátor se
nespustí, řetěz zůstane utržený. Tytéž dvě podmínky čte `pool-provision.ps1`
(„current (v2) … not reinstalling").

**Změna je jediný řádek**: hlavička
[`ums/.claude/hooks/pre-push`](../../../ums/.claude/hooks/pre-push) přejde na
`UMS pre-push guard (Publication Contract) v3`. Tělo hooku se jinak nemění —
bump je **nosič šíření, ne změna chování**, a je to tu napsané proto, aby
čtenář nehledal mezi v2 a v3 behaviorální rozdíl, který neexistuje.

Funguje to, protože `$OURS_MARKER` v instalátoru je **bez verze**
(`'UMS pre-push guard (Publication Contract)'`): instalátor pozná kteroukoli
svou verzi jako vlastní a přepíše ji na místě, zatímco verzní příponu čtou jen
konzumenti. Přesně tak je ten kanál v kontraktu popsaný („the ` v2` suffix is
what distinguishes a current hook from the one a stale workspace still
carries"). Bump tedy používá zavedený upgrade kanál vrstvy, nezakládá nový.

**Verze hooku leží na těchto místech** (čísla řádků k 2026-09-14):

| Soubor | Místa |
|---|---|
| `ums/.claude/hooks/pre-push` | 2 — zdroj značky |
| `ums/.claude/settings.json` | 62 — vstupní brána, dvě místa v jednom řetězci (značka + „starší než v2") |
| `ums/.claude/skills/mb-state/SKILL.md` | 71–72, 264, 292, 302, 304 |
| `ums/.claude/skills/shared/overlays/brainstorming.overlay.md` | 68 — „at least v2" |
| `ums/.claude/skills/shared/overlays/finishing-a-development-branch.overlay.md` | 16 |
| `ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md` | 1182, 1189, 1897, 1910–1911, 2980 |
| `ums/.claude/skills/mb-epic-run/scripts/pool-provision.ps1` | 156, 159, 162 |
| `ums/.claude/hooks/tests/pre-push.tests.ps1` | 22, 1589–1617 |
| `ums/.claude/skills/mb-epic-run/tests/pool-provision.tests.ps1` | aserce verzní brány |

**Past v tom soupisu:** `v2` v repozitáři znamená tři různé věci. Verze
kontraktu (`Contract-Version: 2.18`, „contract v2.9 superseded…"), generace
Memory Banku („MB v2", „the v2 schema abolished them") a overlay značka
`<!-- UMS-OVERLAY BEGIN (ums-memory-bank v2) -->` s verzí hooku nesouvisí a
**nesmí se přepsat**. Mění se jen řádky z tabulky výše.

Protože se mění normativní věty kontraktu, jde s tím `Contract-Version` na
**2.19** se supersedes řádkem.

**Bump je jednorázový.** První sezení v každém klonu po git updatu hook
přeinstaluje, `Restore-LfsChainedHook` proběhne v témže běhu a brána pak mlčí.
Klon, který poškozený nebyl, dostane bajtově stejný hook s novou hlavičkou —
žádná škoda.

**Co to nepokrývá, řečeno rovnou:** klon, kde nikdo neotevře agentní sezení
(čistě lidský uživatel), bránu nikdy nespustí. Tam zůstává jedinou cestou
`sync-with-monorepo.ps1` nebo ruční běh instalátoru. Verzní brána je kanál pro
agentní sezení, ne pro celý svět.

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

K verznímu bumpu (bod 4) tamtéž:

- aserce na řádku 22 („hlavička nese verzi") přejde na `v3`;
- **spojený akceptační případ, kvůli kterému bod 4 vzniká**: repo s LFS
  sourozenci, náš hook ve verzi **v2**, bez `.ums-chained` → po běhu
  instalátoru je hlavička `v3` **a zároveň** `.ums-chained` existuje a je
  spustitelný. Dvě poloviny změny se musí potkat v jednom běhu, jinak si každá
  dokazuje jen sebe;
- existující upgrade fixtura (1589–1617) dnes simuluje „pre-v2" odstraněním
  přípony; přibude protějšek v2 → v3 — hook s `v2` je rozpoznán jako NÁŠ
  (ne odsunut do `.ums-chained` jako cizí) a po instalaci nese `v3`.

Do `ums/.claude/skills/mb-epic-run/tests/pool-provision.tests.ps1`: verzní
brána slotu čte `v3` — slot s `v2` se přeinstaluje, slot s `v3` ne.

Negativní běh podle playbooku: sadu spustit i proti neopravenému skriptu
a rozdělit aserce na „zčervenaly" a „zůstaly zelené v obou bězích"
(regresní zámek).

## Šíření

Po opravě `sync-with-monorepo.ps1` do `D:\_datasys\ums` — tahle cesta instalátor
spustí sama a nepotřebuje verzní bránu k ničemu.

Verzní bump (bod 4) je pro **druhou** cestu: klon, který si `.claude/`
aktualizuje přes `git pull` a sync skript nespustí. Tam je první agentní sezení
po updatu jediný okamžik, kdy se instalátor rozběhne.

Repozitář `pmq_logopedie_nr` sdílí týž mb-* framework — mimo rozsah této
položky, jen se pojmenovává; z bodu 4 ale těží stejně, protože bránu nese
vrstva, ne tenhle repozitář.

## Ověřovací sada

```
pwsh -NoProfile -File ums/.claude/hooks/tests/pre-push.tests.ps1
pwsh -NoProfile -File ums/.claude/skills/mb-epic-run/tests/pool-provision.tests.ps1
for t in $(find ums -name "*.tests.ps1"); do echo "== $t"; pwsh -NoProfile -File "$t" || echo "FAILED: $t"; done
```

Po bumpu navíc grep jako zámek proti nedodělanému přepisu — v `ums/` nesmí
zůstat žádná verze hooku `v2` mimo řádky, které o staré verzi mluví záměrně
(upgrade fixtura, věta kontraktu o rozpoznání pre-v2 hooku):

```
grep -rn "Publication Contract) v2" ums/
```
