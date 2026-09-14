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

1. **hooks adresář není sdílený** — `core.hooksPath` není absolutní a nepochází
   z `global` ani `system` scope;
2. **na `pre-push` leží náš hook** (`Test-IsOurHook`), nebo ho tam tenhle běh
   právě zapisuje;
3. **zdravý LFS řetěz tam není** — `pre-push.ums-chained` buď neexistuje, nebo
   existuje, ale nevolá `git lfs pre-push`, nebo ho volá a nemá execute bit;
4. **repozitář LFS opravdu používá** (důkaz níže);
5. `git lfs` je dosažitelný.

**Podmínka 1 je bezpečnostní a je symetrická k `Move-ForeignHook`.** Ten
v přesně téhle situaci odmítá (`install-git-hooks.ps1:611-614`) s odůvodněním,
že adresář je sdílený s jinými repozitáři a zásah by je tiše přesměroval.
Zápis `.ums-chained` tam je totéž o patro níž: zapnul by `git lfs pre-push`
každému repozitáři, který ten adresář používá. Navíc by v takovém adresáři
mohli být LFS sourozenci úplně cizího repozitáře, takže by i důkaz lhal.

**Podmínka 2 sjednocuje spouštění s detekcí v bodě 3.** Bez ní by se obnova
spustila i tam, kde `pre-push` vůbec není — první instalace, nebo repozitář,
kde LFS pre-push někdo odstranil schválně (`git lfs install --manual`). To by
vzkřísilo hook, který nikdo neztratil. Dvě pravidla mířící na tentýž stav
nesmí mít různé spouštěče, jinak se report `mb-state` a akce instalátoru
rozejdou.

**Podmínka 3 netestuje existenci, ale zdraví.** Slot řetězu je jen jeden
(`$CHAINED_SUFFIX`, `pre-push:112`), takže `.ums-chained` může nést cizí
non-LFS hook — husky, pre-commit — a LFS řetěz je přitom ztracený. Pouhý
`Test-Path` by ten stav prohlásil za v pořádku. Stejně tak execute bit:
`run_chained` gatuje na `[ -x "$chained" ]` a řetěz bez něj **mlčky přeskočí**,
tedy přesně to tiché selhání, kvůli kterému tahle změna vzniká. Dnešní
`chmod +x` sedí uvnitř větve „právě jsme odsunuli cizí hook", takže existující
řetěz neopraví žádný opakovaný běh.

**Podmínka 4 je důkaz, ne domněnka — a nesmí záviset na tom, kdo vlastní hooks
adresář.** Původní znění bralo jako důkaz jen LFS sourozence (`post-commit`,
`post-checkout`, `post-merge` volající `git lfs <jméno>`). To má systematické
false negatives: husky s `core.hooksPath=.husky`, vymazaný `.git/hooks`, nebo
přestěhovaný hooks adresář nechají repozitář používající LFS bez jediného
sourozence. Důkazem je proto **kterýkoli** z těchto, v tomhle pořadí:

- LFS sourozenec, jak výše (nejsilnější — říká „git-lfs sem svoje hooky
  instaloval, ale `pre-push` mezi nimi chybí");
- `filter=lfs` v `.gitattributes`;
- neprázdný objektový sklad `.git/lfs/`;
- `git config --get-regexp '^lfs\.'` vrátí cokoli.

Kde není ani jeden, se nespustí nic — řetěz si nevymýšlíme tam, kam nepatří.
To pokrývá i `git lfs uninstall`, který maže všechny čtyři hooky naráz.

Obsah se **generuje od git-lfs, ne opisuje**: `git init` plus
`git lfs install --local` v dočasném adresáři, ověření, že vygenerovaný
soubor opravdu obsahuje `git lfs pre-push` (nikdy nezapsat soubor, který jsme
si neověřili), bajtová kopie na `<dst>.ums-chained` — bajtová kvůli LF,
protože jde o bezpříponový shellový skript mimo dosah `.gitattributes` —,
provenience stamp ve stejném tvaru jako u `Move-ForeignHook`, a execute bit.

**Generování musí být izolované od uživatelovy konfigurace, jinak není inertní.**
`git init` ctí `init.templateDir` a `git lfs install --local` si hooks adresář
resolvuje přes `core.hooksPath`, který může přijít z global scope — na takovém
stroji by generovací krok zapsal `pre-push` do sdíleného globálního hooks
adresáře, tedy mimo dočasný adresář i mimo cílový repozitář. Že je ta konfigurace
na těchhle strojích živá, instalátor sám ví (`install-git-hooks.ps1:301-317`
a `:571-573`). Generovací běh proto jede s `--template=` (prázdná šablona),
`-c core.hooksPath=` (prázdná hodnota, přebije dědění) a `GIT_CONFIG_GLOBAL`
i `GIT_CONFIG_SYSTEM` nasměrovanými na neexistující soubor. Teprve s touhle
izolací platí, že se cílový repozitář ani nic jiného mimo dočasný adresář
nedotkne.

**Obnovený řetěz se značkuje, protože ta značka pak něco rozhoduje.** Provenience
stamp není jen stopa pro člověka: `Move-ForeignHook` dnes bezpodmínečně odmítá,
když `.ums-chained` existuje (`install-git-hooks.ps1:625-627`), a obnova ten
soubor vyrábí tam, kde dosud nebyl. Až git-lfs někdy znovu nainstaluje svůj
`pre-push`, instalátor by odmítl instalovat vůbec a skončil exitem 2 — záruka
by zmizela v klonu, kde by před touhle změnou řetězení fungovalo. Existující
test ten stav už pinuje (`pre-push.tests.ps1:1185-1195`). `Move-ForeignHook`
proto smí přepsat řetěz, **který nese náš stamp a volá `git lfs`**, když
příchozí cizí hook také volá `git lfs`. Pro skutečně cizí řetěz zůstává dnešní
odmítnutí beze změny.

### 2. Exit kódy se nemění — a je to rozhodnutí, ne opomenutí

Když `git lfs` chybí nebo `chmod` neprojde, vypíše se červené varování
stejného tvaru jako u dnešního chmodu, ale exit kód zůstane.

**Vzniká tím asymetrie a je potřeba ji pojmenovat.** Skript jeden kód už
utrácí přesně za tuhle třídu faktu: exit 2 znamená „cizí `pre-push` se
nepodařilo zřetězit, záruka tu není" (`install-git-hooks.ps1:62-68`). Po téhle
změně je tedy **nezřízený** řetěz hlasitý, ale **neobnovený** tichý, přestože
pro LFS jde o tentýž konec. Oba volající — `sync-with-monorepo.ps1:331`
i `pool-provision.ps1:170-173` — čtou výhradně exit kód, takže červený řádek
nevidí.

**Přesto zůstává exit 0, protože ty dva stavy se liší v tom, o čem kontrakt
0–4 mluví.** Exit 2 říká „publikační záruka tu není" — guard není nainstalovaný.
Neobnovený LFS řetěz naproti tomu znamená, že guard **je** nainstalovaný
a funguje; rozbité je něco vedle. Hlásit to exitem 2 by byla lež a rozšiřovat
kontrakt na 0–5 by znamenalo, že volající musí nově rozlišovat stav, který se
záruky netýká. **Kanálem pro tenhle fakt je proto bod 3**, ne návratový kód —
a tahle věta je tu proto, aby se to při příštím čtení nečetlo jako opomenutí.

### 3. `mb-state` — detekce i bez instalátoru

Do workspace fitness přibude čistě read-only kontrola. Spouštěcí stav je
**tentýž jako v bodě 1** (podmínky 1–4), aby se report a akce instalátoru
nerozešly: hooks adresář není sdílený, na `pre-push` leží náš hook, repozitář
používá LFS, a zdravý řetěz tam není. Hláška:
`⚠️ LFS pre-push řetěz chybí nebo je neúplný`.

**Hláška mluví o tom, co soubor JE.** Původní znění „(git push neodesílá LFS
objekty)" je tvrzení o tom, co soubor DĚLÁ, a to `mb-state` svým vlastním
pravidlem zakazuje (`mb-state/SKILL.md:51-59`). Důsledek patří do „Další krok",
ne do stavového řádku.

**Zařazení na řádku `Workspace:`.** Není to chybějící záruka — guard je
nainstalovaný a funguje —, takže to nepatří do první alternace, která je
vyhrazená právě té jedné třídě (`mb-state/SKILL.md:296-314`). Jede to
**vedle `✅ způsobilý`** jako samostatná položka, stejně jako varování
o absolutním `core.hooksPath`. K tomu patří vlastní odrážka v „Další krok":
*LFS řetěz chybí/neúplný → spusť `install-git-hooks.ps1` a znovu ověř* —
šablona páruje jednu odrážku ke každému nálezu.

**Cena kontroly, řečená poctivě.** Není to „`Test-Path` plus jedno čtení
souboru": je to resolve hook adresáře (`git rev-parse --git-path hooks/pre-push`),
čtení `core.hooksPath`, hlavička našeho hooku, test existence a obsahu
`.ums-chained`, a důkaz o LFS — v nejhorším případě tři sourozenci s čtením těl,
jinak `.gitattributes` / `.git/lfs/` / `git config`. Pořád jen čtení, žádné
spuštění hooku, takže read-only pravidlo drží; ale je to řádově víc než jeden
`Test-Path` a návrh to nemá zlehčovat.

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

#### Konzumenti musí porovnávat uspořádáním, ne rovností

Tohle je předpoklad bumpu, ne jeho detail. Dnes všichni konzumenti dělají
**přesnou shodu** na aktuální literál a zápornou větev jen *formulují* jako
„chybí nebo starší". Novější hook je proto k nerozeznání od staršího:
kopie vrstvy ve verzi v2 uvidí v3 hook, vyhodnotí „missing or older" a
přeinstaluje ho **ze svého v2 zdroje** — tedy degraduje.

Není to hypotéza. `pool-provision.ps1:156` testuje `-cmatch '… v2'`, na
`:162` hlásí „missing or older than v2" a na `:169` spouští instalátor
`Join-Path $PSScriptRoot '..\..\..\hooks\install-git-hooks.ps1'`, tedy kopii
ze **svého vlastního** worktree. Slot na starším commitu má starší vrstvu,
hook přitom leží ve sdíleném common dir — takže jeden zaostalý slot degraduje
hook celému repozitáři a všem jeho worktree. Dvě kopie vrstvy různého stáří
si ho můžou přehazovat tam a zpět.

Součástí bodu 4 je proto změna porovnání: konzument si z hlavičky
**vyparsuje číslo verze** a jedná jen tehdy, je-li nalezená verze **striktně
nižší** než jeho vlastní. Chybějící nebo nečitelná verze se počítá jako
nejnižší (dnešní pre-v2 hook), novější se nechá být. Tím padá i past pro každý
příští bump, ne jen pro tenhle.

**Tvrzení o šíření je potřeba zúžit na to, co je ověřené.** Kanál není „jakýkoli
git update `.claude/`" — vstupní brána žije v `settings.json`, a ten
`sync-with-monorepo.ps1` na ne-claude cíle ani na `-Scope UserProfile` záměrně
nenasazuje (`:405-407`, `:425-427`). Ověřeno platí tohle: **v monorepu
`d:\_datasys\ums` je `.claude/settings.json` trackovaný a text brány nese**,
takže kdokoli si monorepo pullne, dostane bránu po gitu, zatímco jeho
`.git/hooks/pre-push` je per-klon a zaostane — a právě tam bump zabere.
Kořenové `.claude/` tohohle forku trackované není, takže pro fork samotný
kanál neexistuje. O `pmq_logopedie_nr` návrh netvrdí nic, dokud se neověří,
jak tam vrstva přistává.

**Verze hooku leží na těchto místech** (čísla řádků k 2026-09-14; kromě
`pre-push:2` jde všude o konzumenty, kteří přejdou na porovnání uspořádáním):

| Soubor | Místa |
|---|---|
| `ums/.claude/hooks/pre-push` | 2 — zdroj značky |
| `ums/.claude/settings.json` | 62 — vstupní brána, dvě místa v jednom řetězci (značka + „starší než v2") |
| `ums/.claude/skills/mb-state/SKILL.md` | 71–72, 264, 292, 302, 304 |
| `ums/.claude/skills/shared/overlays/brainstorming.overlay.md` | 68 — „at least v2" |
| `ums/.claude/skills/shared/overlays/finishing-a-development-branch.overlay.md` | 16 |
| `ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md` | 1182, 1189, 1897, 1910–1911, 2980 |
| `ums/.claude/skills/mb-epic-run/scripts/pool-provision.ps1` | 156, 159, 162 — plus próza postpodmínky na 18, 29, 130, 190 |
| `ums/.claude/hooks/tests/pre-push.tests.ps1` | 22, 1589–1617 |
| `ums/.claude/skills/mb-epic-run/tests/pool-provision.tests.ps1` | 71, 77, 83 a zejména 149 — regex `guard is (?:current \(v2\)\|missing or older than v2)` má obě větve textu brány zadrátované a bez úpravy spadne |
| `memory-bank/tech.md` | 117 — „publikačního pravidla … je git `pre-push` hook (`v2`)" |
| `memory-bank/architecture.md` | 463 — „Skutečnou hranicí je git `pre-push` hook (`v2`, …)" |

Poslední dva řádky leží **mimo `ums/`**, což je přesně důvod, proč je grep
zámek níž nesmí omezovat na `ums/`.

**Past v tom soupisu:** `v2` v repozitáři znamená tři různé věci. Verze
kontraktu (`Contract-Version: 2.18`, „contract v2.9 superseded…"), generace
Memory Banku („MB v2", „the v2 schema abolished them") a overlay značka
`<!-- UMS-OVERLAY BEGIN (ums-memory-bank v2) -->` s verzí hooku nesouvisí a
**nesmí se přepsat**. Mění se jen řádky z tabulky výše.

Protože se mění normativní věty kontraktu, jde s tím `Contract-Version` na
**2.19** se supersedes řádkem.

**Bump je jednorázový — ale jen s porovnáním uspořádáním.** První sezení
v každém klonu po git updatu hook přeinstaluje, `Restore-LfsChainedHook`
proběhne v témže běhu a brána pak mlčí. Klon, který poškozený nebyl, dostane
bajtově stejný hook s novou hlavičkou. Bez té změny porovnání by to
jednorázové nebylo: starší kopie vrstvy by hook vracela na v2 a novější zpátky
na v3, takže věta „žádná škoda" platí až po ní.

**Jedno instalátorové spuštění udělá obojí, a pořadí to zaručuje.** `Test-IsOurHook`
matchuje bezverzový `$OURS_MARKER` (`install-git-hooks.ps1:150`, `:328-333`), takže
v2 hook blok s cizím hookem (`:677-706`) přeskočí; obnova vložená mezi ten blok
a `Copy-Item` (`:708`) proběhne první a teprve pak se zapíše v3. Ověřeno čtením,
ne odhadem.

**Co to nepokrývá, řečeno rovnou:** klon, kde nikdo neotevře agentní sezení
(čistě lidský uživatel), bránu nikdy nespustí. Tam zůstává jedinou cestou
`sync-with-monorepo.ps1` nebo ruční běh instalátoru. Verzní brána je kanál pro
agentní sezení, ne pro celý svět.

## Past, kterou hlídá playbook

Proof instalátoru po obnově prochází přes `run_chained` do **skutečného**
`git-lfs`, který resolvuje remote `origin`. Playbook (`Git hooky (POSIX sh)`)
to má naměřené: bez `origin` skončí accept běh exitem 1 a chyba se čte jako
regrese řetězení. Fixtura proto musí mít nakonfigurovaný remote `origin`,
byť fiktivní.

**Netýká se to jen fixtury, a to je potřeba přiznat.** Hlavička instalátoru
uvádí jako vlastnost návrhu, že proof běhy se repozitáře ani remote nedotknou
(„no git command runs, every sha is fabricated", `install-git-hooks.ps1:45-48`).
Po obnově to přestane platit doslova: accept běh jde přes `run_chained`
(`pre-push:340`) do skutečného `git-lfs` s vymyšlenými shami a instalátor na
jeho výsledku staví (`:534`). Reálný běh v klonu, jehož guard je v pořádku,
tak může skončit exitem 1 kvůli tomu, že se git-lfs zakuckal. **Obnova tedy
tuhle invariantu instalátoru mění a ta věta v hlavičce se musí upravit s ní** —
jinak zůstane v souboru tvrzení, které přestalo být pravdivé.

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
  **Řádek 1606 se musí přenastavit** (`-replace '\s+v2\s*$', ''`): po bumpu
  končí hlavička na ` v3`, strip na `v2` je no-op a sanity aserce na 1607 —
  která si dokazuje, že se fixtura opravdu změnila — spadne;
- **degradace:** v3 hook + konzument ve verzi v2 → hook zůstane v3
  (porovnání uspořádáním). Tenhle případ je důkaz, že bump je jednorázový.

Do `ums/.claude/skills/mb-epic-run/tests/pool-provision.tests.ps1`: verzní
brána slotu čte `v3` — slot s `v2` se přeinstaluje, slot s `v3` ne, **slot
s novější verzí se nechá být**. Regex na řádku 149 nese obě větve textu brány,
takže se přepíše s ním.

**Případy, které dnešní soupis nepokrývá** a bez kterých by nálezy oponentury
zůstaly bez zámku:

- obnova pod absolutním nebo global `core.hooksPath` → nespustí se nic;
- `.ums-chained` existuje, ale je to non-LFS hook → obnova se nespustí a
  `mb-state` to přesto nahlásí (ztracený řetěz se nesmí schovat za cizí soubor);
- `.ums-chained` volá `git lfs`, ale nemá execute bit → execute bit se opraví;
- repozitář používá LFS, ale hooks adresář vlastní husky (žádní sourozenci) →
  důkaz projde přes `.gitattributes` / `.git/lfs/` / `git config`;
- po obnově git-lfs znovu nainstaluje svůj `pre-push` → instalátor náš
  vygenerovaný řetěz přepíše a skončí 0, **ne** exitem 2;
- proof běh v repozitáři se skutečným `origin` po obnově (nejen ve fixtuře).

Negativní běh podle playbooku: sadu spustit i proti neopravenému skriptu
a rozdělit aserce na „zčervenaly" a „zůstaly zelené v obou bězích"
(regresní zámek). Neopravený skript se získá z gitu (`git show <báze>:<cesta>`
do dočasného souboru), ne ručním vracením změn — sada musí umět běžet proti
oběma verzím bez editace pracovního stromu.

## Šíření

Po opravě `sync-with-monorepo.ps1` do `D:\_datasys\ums` — tahle cesta instalátor
spustí sama a nepotřebuje verzní bránu k ničemu.

Verzní bump (bod 4) je pro **druhou** cestu, a ta je ověřená přesně jedna:
monorepo má `.claude/settings.json` trackovaný a text brány v něm, takže kdo si
monorepo pullne, dostane novou bránu po gitu, zatímco jeho `.git/hooks/pre-push`
je per-klon a zaostane. První agentní sezení po takovém pullu je jediný okamžik,
kdy se tam instalátor rozběhne.

Kořenové `.claude/` tohohle forku trackované není, takže pro fork samotný tahle
cesta neexistuje — fork se nasazuje sync skriptem.

Repozitář `pmq_logopedie_nr` sdílí týž mb-* framework — mimo rozsah této
položky, jen se pojmenovává. **Jestli z bodu 4 těží, závisí na tom, zda tam
`settings.json` přistává trackovaně; to ověřeno není a návrh to netvrdí.**

## Ověřovací sada

```
pwsh -NoProfile -File ums/.claude/hooks/tests/pre-push.tests.ps1
pwsh -NoProfile -File ums/.claude/skills/mb-epic-run/tests/pool-provision.tests.ps1
for t in $(find ums -name "*.tests.ps1"); do echo "== $t"; pwsh -NoProfile -File "$t" || echo "FAILED: $t"; done
```

Po bumpu navíc grep jako zámek proti nedodělanému přepisu. **Hledat jen plný
literál značky nestačí** — většina míst verzi parafrázuje („starší než v2",
„at least v2", „current (v2)", „` v2` suffix") — a **omezit hledání na `ums/`
taky ne**, protože dvě místa leží v `memory-bank/`. Zámek je proto:

```
grep -rnE "Publication Contract\) v2|(older|starší) než v2|older-than-v2|at least v2|current \(v2\)|\( ?v2[,)]| v2\` suffix" ums/ memory-bank/
```

Co zbude, musí být jen řádky, které o staré verzi mluví **záměrně**: upgrade
fixtura v `pre-push.tests.ps1` a věta kontraktu o rozpoznání pre-v2 hooku.
Cokoli jiného je nedodělaný přepis.
