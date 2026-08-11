# Návrh: Identifikace integrační větve per pracovní položka

- **Jira:** (žádný tiket)
- **Target MB:** memory-bank/
- **Vytvořeno:** 2026-08-11

## Cíl

Umožnit, aby pracovní položka měla **vlastní integrační (bázovou) větev** — typicky
servisní větev řady `Branches/5.37` místo `develop` — a aby se s takovou větví
zacházelo stejně jako s `develop` nebo `main`: nikdy do ní agent nepushuje sám.

Dnes je báze jediná hodnota `baseRef` v [ums-repo.json](../../ums-repo.json), platná
pro celý repozitář. Práce mířící do servisní větve tak dostane špatnou bázi ve všech
čtyřech krocích, kde na ní záleží: větev se založí z `develop`, base sync merguje
`develop`, integrace nabídne push do `develop` a kontrola dosažitelnosti se ptá
`develop`.

### Naměřený stav v monorepu

V živém monorepu UMS (`d:\_datasys\ums`) **`memory-bank/ums-repo.json` neexistuje**,
takže platí vestavěné defaulty. Vygenerovaný seznam, který čte `pre-push`, obsahuje
jen `develop`, `main`, `master`, `release/*` — přestože v repu žije pět servisních
větví `Branches/5.33` až `Branches/5.37`.

Ověřeno strojově, syntetickým refem podaným přímo hooku v tom repozitáři:

| Cílová větev | Výsledek hooku |
|---|---|
| `develop` | exit 1 — zamítnuto |
| `Branches/5.37` | **exit 0 — propuštěno** |

Servisní větev je tedy v reálném nasazení pro agenta **nechráněná**. To není důsledek
chybějící funkce — [mb-init](../../../ums/.claude/skills/mb-init/SKILL.md) release
řady detekovat umí a `Branches/*` sám doporučuje — ale důsledek toho, že konfigurace
v tom repozitáři nikdy nevznikla a nic si toho nevšimlo. Kontrakt totiž degradaci na
vestavěný seznam popisuje jako posun „k bezpečnější straně"; vůči skutečné topologii
repozitáře je to ale posun k **menší** ochraně.

## Scope

Uvnitř:

- per-položkový zápis báze a pravidlo, jak ji čtou všichni konzumenti,
- volba báze při zakládání práce, s kandidáty odvozenými ze tří signálů,
- fail-closed vynucení invariantu „integrační větev je vždy chráněná větev",
- sdílená strojová funkce pro porovnání jména větve s chráněnými vzory.

Mimo:

- **jedna pracovní položka = jedna báze.** Oprava, která má skončit ve dvou větvích,
  se dělá jako dvě samostatné práce sekvenčně (první dokončit a sklidit, pak druhá
  cherry-pickem, mergem nebo reimplementací podle povahy změny). Návrh tomu nesmí
  bránit — viz „Dopady", ověření druhého průchodu.
- **náprava konfigurace v monorepu.** Je to cílený zápis `ums-repo.json` a jeden běh
  instalátoru hooků, ne změna vrstvy; provede se zvlášť.
- změna klíčů v `ums-repo.json`. Žádný nový klíč nevzniká — kontrakt zakazuje
  zavádět klíč bez pojmenovaného konzumenta a kandidáti báze se odvodí z
  `protectedBranches`, který už existuje.

## Technický návrh

### 1. Řádek `Báze:` v `context.md`

Do bloku `## Active Work` přibude **volitelný** řádek:

```markdown
- **Jira:** (bez tiketu)
- **Target MB Pin:** memory-bank/
- **Work item:** ums_3400_oprava_neceho
- **Báze:** origin/Branches/5.37
- **Started:** 2026-08-11
```

Hodnota je plně kvalifikovaný remote-tracking ref, tedy **stejný tvar jako
`baseRef`** — včetně pravidla, že se nikdy neprefixuje `origin/` podruhé, a včetně
odvození push destinace `<baseBranch>` stripnutím remote a **jediného** následujícího
lomítka (`origin/Branches/5.37` → `Branches/5.37`, nikdy `5.37`). Kontrakt tuto past
popisuje v sekci „Repository Configuration"; nově se vztahuje i na tento zdroj
hodnoty.

Proč `context.md` a ne jinam: je to soubor **per větev** (proto v něm žije pin),
cestuje s klonem a je čitelný napříč větvemi přes `git show <branch>:memory-bank/context.md`.
Díky tomu vidí bázi cizí a zaparkované práce i `mb-doc-index` a `mb-state`. Git config
per větev (`branch.<name>.umsBaseRef`) by obojí nesplnil — necestuje s klonem, stejně
jako hooky, a z jiné větve je nečitelný.

### 2. Pravidlo efektivní báze

Jedna věta v kontraktu, na kterou se všichni konzumenti odkazují:

> **Efektivní báze** = řádek `Báze:` z bloku `## Active Work` v `<CTX_DIR>/context.md`;
> když chybí, `baseRef` z `<CTX_DIR>/ums-repo.json`.

Rozšíření je **aditivní**: řádek se zapisuje jen tam, kde se báze liší od výchozí,
takže existující větve, existující `context.md` soubory i repozitář bez
`ums-repo.json` fungují beze změny chování.

**Reset na IDLE řádek zachová**, stejně jako dnes zachovává řádek `Jira:`. Bez toho by
návrh nefungoval: harvest resetuje `context.md` ve svém kroku 5, ale integrace do báze
přichází až po něm a `<baseBranch>` ještě potřebuje — po resetu by spadla na výchozí
bázi a nabídla push do špatné větve.

Zapisovatelé `context.md` se nerozšiřují. Řádek píše řídicí sezení při pinování (týž
zapisovatel jako `Target MB Pin`), zachovávají ho `mb-harvest` a `mb-abort`. Taxativní
seznam tří zapisovatelů v kontraktu zůstává, jen jeden z nich dostane další pole.

### 3. Volba báze

Ptá se **jednou**, mezi otázkou na Jira tiket a založením tiketové větve (intent fáze
entry gate). Později se už neptá — řádek platí do konce práce.

Kandidáti se skládají ze tří nezávislých signálů:

1. **Chráněné větve reálně existující na `origin`** — vzory `protectedBranches`
   porovnané se seznamem z
   `git for-each-ref --format='%(refname:lstrip=3)' refs/remotes/origin/`
   s odfiltrovaným `HEAD`. Formát `%(refname:short)` je tu past: ponechává remote
   prefix v každém jménu a pro symref `origin/HEAD` vrací holé `origin`.
2. **Větev, na které sezení stojí**, je-li mezi kandidáty — nabídne se první.
3. **Zmínka v Jira tiketu**, je-li tiket navázaný a Jira dostupná — hledá se shoda
   textu tiketu s existujícími kandidáty (například „5.37"). Krok je fail-open:
   nedostupná Jira ho tiše přeskočí.

Výchozí doporučení zůstává `baseRef`. Rozhoduje vždy člověk; signály jen řadí
a doporučují.

### 4. Vynucení ochrany

**Invariant: integrační větev je vždy chráněná větev.** Zvolená báze musí odpovídat
některému vzoru v efektivním `protectedBranches`. Když neodpovídá, je to fail-closed
STOP s nabídkou — ne varování: nechráněná báze znamená, že do ní agent smí pushnout,
což je přesně stav naměřený výše.

Náprava má **závazné pořadí**:

1. **cíleně doplnit chybějící vzor** do `ums-repo.json` — jeden řádek v klíči
   `protectedBranches`, a když soubor neexistuje, minimální soubor s klíči, které jsou
   v tu chvíli známé; zatím **necommitnuto**,
2. spustit [install-git-hooks.ps1](../../../ums/.claude/hooks/install-git-hooks.ps1) —
   vygenerovaný `ums-protected-branches` je build produkt konfigurace, ne druhý zdroj
   pravdy, takže bez tohoto kroku se nezmění nic,
3. **ověřit self-testem na té konkrétní zvolené větvi**, že ji hook nyní odmítá a jinou
   dál propouští — strojově, ne odvozením z toho, že soubor obsahuje správný řádek,
4. teprve pak `git switch -c <větev> <zvolená báze>` a commit změněného
   `ums-repo.json` **na tiketové větvi**.

Pořadí kroku 4 není kosmetika: `ums-repo.json` je trackovaný soubor v `memory-bank/`,
takže commit před vytvořením větve by uvízl na bázi — na sdílené větvi, kam ho nikdo
nepublikuje a odkud ho `switch -c` s explicitním počátečním bodem neodnese.
Necommitnutá změna naopak se `switch -c` odjede sama; je to tentýž mechanismus, na
kterém stojí výjimka pro zbytky pojmenované inventurou entry gate.

**Proč cílený zápis, a ne `mb-init`.** Re-detekce celé konfigurace je nepoměrně dražší
operace než doplnění jednoho vzoru — prochází topologii repozitáře, navrhuje všech pět
klíčů a nechává si potvrdit celý chráněný seznam. Náprava, kterou tento STOP potřebuje,
je přitom jednořádková a její správnost stvrzuje krok 3, ne detekce. Minimální soubor
stačí i tam, kde konfigurace chybí celá: loader degraduje **po jednotlivých klíčích**,
takže nezapsané klíče prostě zůstanou na vestavěných hodnotách. `mb-init` zůstává
správnou volbou tam, kde se má konfigurace založit nebo přegenerovat jako celek —
ne uprostřed zakládání práce.

Když uživatel konfiguraci měnit nechce, zvolí jinou bázi. Třetí cesta neexistuje.

### 5. Sdílená funkce pro porovnání se vzory

Nový skript vedle
[Get-UmsRepoConfig.ps1](../../../ums/.claude/skills/shared/scripts/Get-UmsRepoConfig.ps1)
poskytne dvě věci: test „odpovídá jméno větve některému chráněnému vzoru?" a sestavení
seznamu kandidátů báze.

Důvod je normativní, ne pohodlí: porovnání globů proti jménům větví už existuje
**dvakrát** — v [pre-push](../../../ums/.claude/hooks/pre-push) (POSIX `sh`) a
v `guard-git-push.mjs` (JS) — a kontrakt vyžaduje, aby obě vynucovací vrstvy daly na
stejnou konfiguraci stejnou odpověď. Třetí kopie zapsaná do instrukcí skillu by to
pravidlo porušila hned při vzniku a rozhodnutí „je zvolená báze chráněná?" by přestalo
být strojové.

Loader `Get-UmsRepoConfig.ps1` se **nemění** — per-položková báze není konfigurace
repozitáře.

### 6. Dotčení konzumenti

| Co | Zásah |
|---|---|
| Kontrakt | Pravidlo efektivní báze; řádek `Báze:` ve schématu `context.md` a jeho zachování při resetu; volba báze v intent fázi entry gate; invariant chráněné integrační větve |
| Overlay `brainstorming` | Volba báze mezi tiketem a `switch -c`; zápis řádku spolu s pinem |
| Overlay `subagent-driven-development` | Base sync čte efektivní bázi |
| Overlay `finishing-a-development-branch` | Base sync, integrace a odvození push destinace z efektivní báze |
| `mb-architect-review` | Base merge a zakládání větve z efektivní báze |
| `mb-harvest` | Odvození `AFFECTED_MBS` z diffu proti efektivní bázi |
| `mb-jira-update` | Kontrola dosažitelnosti a znění lidského příkazu |
| `mb-park` | Efektivní báze plus zpřísněný STOP (viz „Dopady") |
| `mb-state` | Vzdálenost od efektivní báze; report uvede, odkud báze pochází |
| `mb-init` | Beze změny — release řady už detekuje |
| `mb-doc-index` | Beze změny — jeho `-BaseRef` je repo-wide pohled napříč větvemi, ne báze jedné práce |
| `Get-UmsRepoConfig.ps1` | Beze změny |

### 7. Testy

Podle konvencí procedurálního dokumentu této Memory Bank: bez Pesteru, offline nad
lokálním bare klonem jako `origin`, vlastní kopie `_assert.ps1` v adresáři sady.
Pokrýt:

- porovnání jména větve se vzory, včetně vzoru s metaznakem (`Maint/[0-9`), na kterém
  `-like` umí vyhodit výjimku — a rozlišení „neodpovídá" od „nešlo vyhodnotit",
- sestavení kandidátů (odfiltrovaný `HEAD`, jméno větve s diakritikou, prefix v
  jméně),
- přednost řádku `Báze:` před `baseRef` a chování při jeho absenci,
- zachování řádku při resetu na IDLE,
- fail-closed při nechráněné zvolené bázi.

Nový regresní strážce ověřit jeho vlastní negativitou — spustit ho i proti
neopravenému stavu a vypsat, které asercie zčervenají; ty, které zůstanou zelené
v obou případech, uvést odděleně jako regresní zámek, ne jako důkaz opravy.

## Dopady

**Pro práci do výchozí báze se nemění nic.** Řádek `Báze:` nevzniká, čtení padá na
`baseRef`, otázka na bázi má jediného doporučeného kandidáta.

**Migrace není potřeba.** Rozšíření je aditivní; starší `context.md` bez řádku je
platný stav, ne chyba.

**Zpřísnění v `mb-park`.** Dnešní STOP „aktuální větev je báze" se počítá z jedné
hodnoty. Nově platí pro **kteroukoli** chráněnou větev, nezávisle na tom, jaká báze je
zvolená — jednodušší i přísnější zároveň.

**Ověření druhého průchodu.** Scénář „oprava do `Branches/5.37`, pak totéž do
`develop`" návrh neblokuje: druhá práce má vlastní větev, vlastní `context.md` a
vlastní řádek `Báze:`. Meziklonová kolizní kontrola ji nezastaví, protože
`mb-doc-index` klíčuje podle fáze a první práce je po harvestu ve `completed/`, což
aktivní fáze není.

**Nasazení.** Změna overlay fragmentů znamená revendor v monorepu — vendorované skilly
kopií nevzniknou. Postup je v procedurálním dokumentu této Memory Bank, sekce „Upgrade
upstreamu (revendor)".

## Rizika

- **Rozptyl čtení báze.** Konzumentů je osm; opomenuté místo se projeví až
  u pushe do špatné větve. Mitigace: pravidlo má jediný domov v kontraktu, skilly na
  něj jen odkazují, a po změně se grepne celá vrstva na charakteristický token včetně
  hlaviček hooků, šablon reportů a overlay fragmentů.
- **Zapomenutý běh instalátoru po změně konfigurace.** Doplněný vzor bez nového běhu
  `install-git-hooks.ps1` nechrání nic. Mitigace: krok 3 nápravy je strojový self-test
  na konkrétní zvolené větvi, takže opomenutí se projeví okamžitě a v tom samém běhu.
- **Řádek ztracený při resetu na IDLE.** Projevil by se až u integrace, tedy nejpozději
  a nejdráž. Mitigace: vlastní asercie v testech.
- **Rozchod se dvěma existujícími implementacemi porovnání vzorů.** Mitigace: sdílená
  funkce místo třetí kopie; testy s metaznakovým vzorem.
