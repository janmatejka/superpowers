# Návrh: Publikace a viditelnost dokumentů napříč větvemi

- **Jira:** (žádný tiket)
- **Target MB:** memory-bank/
- **Plán:** [plan_publikace_a_viditelnost.md](plan_publikace_a_viditelnost.md)
- **Vytvořeno:** 2026-07-31

## Cíl

Umožnit spolupráci více agentů a lidí na jednom epiku, kde každý pracuje ve svém
clonu a ve své tiketové větvi a merguje se až na konci úkolu. Konkrétně zavřít
jednu poruchu, která se dnes projevuje na několika místech: **vrstva zveřejňuje
odkazy na git objekty, které nemusí být na `origin`, a stav git serveru čte jen
z vlastního working tree.** Výsledkem je, že aktéři o sobě nevědí, dvakrát
navrhují totéž a předání do „Testu" odkazuje na neexistující commity.

## Kontext a nalezená mrtvá místa

Analýza kontraktu v2.1, `mb-epic-elaboration` (+ protocol), `mb-epic-graph`,
`mb-architect-review`, `mb-state`, `mb-jira-update` a všech tří overlayů našla
24 mrtvých míst kooperace. Tato položka zavírá následující:

| # | Mrtvé místo | Dnešní stav |
|---|---|---|
| 1 | Nic nedetekuje dva aktéry na témže tiketu | Discovery skenuje `**/memory-bank/proposals/active/` jen lokálně, takže dva aktéři ve dvou clonech mohou nezávisle rozjet tentýž tiket a nikdo se to nedozví |
| 2 | Vazba tiket → větev nikde neexistuje | Konvence názvu je „doporučená"; větev se zapisuje jen do komentáře design-review requestu, jinak se hádá heuristikou `ls-remote \| grep` |
| 5 | `proposals/next/` je neviditelná fronta | Draft na cizí nemergované větvi discovery nenajde → vznikne druhý návrh téhož tiketu |
| 6 | Graf epiku lže o stavu návrhů | `mb-epic-graph -ProposalPath` čte working tree; tiket s návrhem na cizí větvi se zobrazí jako 💡 „připraven k rozpracování" |
| 7 | Publikace na `origin` je nedefinovaná | Push je vždy nabídka a `permissions.deny` ho blokuje; jediný krok, který spolehlivě pushuje, je design review |
| 19 | Finalizace do „Test" neověřuje dosažitelnost | `mb-jira-update` §7 sám přiznává „the link goes live on the next push", §10 přesto posune tiket do „Test" → tester dostane odkazy vracející 404 |
| 20 | Nic nepublikuje `develop` | Upstream Option 1 „Merge Locally" nepushuje a větev maže; overlay navíc ruší `git pull` ve prospěch fetch + FF „žádný push" → „hotovo" v Jiře znamená prázdno na serveru |

Elaborační protokol tuto poruchu ilustruje nejlépe: po uzavření okna zapisuje do
popisu tiketu `**Návrh (design):**` s commit-pinned odkazem *právě proto*, aby
byl draft dohledatelný — a sám si k tomu poznamenává, že odkaz začne fungovat
„při příštím pushi", který nikdo negarantuje (protocol.md §3.6). Jediný
mechanismus oznamující existenci draftu je tedy mrtvý už při vzniku.

Zbytek mapy (mimo rozsah, viz Navazující položky): 3, 4, 8–18, 21–24.

## Scope

**Uvnitř:**

1. Publikační invariant v kontraktu — žádná reference bez dosažitelnosti.
2. Dvouúrovňová push policy (vlastní tiketová větev vs. sdílené větve) včetně
   mechanického vynucení hookem.
3. Nový read-only skill `mb-doc-index` — model tahu: dokumenty se hledají
   napříč větvemi na `origin`, nikam se netlačí.
4. Zapojení indexu do Target-MB discovery, two-actives guardu, elaborace,
   `mb-epic-graph` a `mb-state`.
5. Tvrdá finalizace: kontrola dosažitelnosti v `mb-jira-update` a krok publikace
   `develop` ve finishing.

**Mimo:** průběžný záznam výsledku (`handoff_<slug>.md`), testovací předpoklady
z vln grafu, epický deployment přehled, reopen po vrácení z testu,
`mb-claim`/`mb-park`, docs fast-path do `develop`, strukturální oprava
`context.md` a cestující SDD kontext.

## Technický návrh

### 1. Publikační invariant

Nová sekce kontraktu **Publication Contract**:

> **Žádná reference bez dosažitelnosti.** Kdykoli workflow pojmenuje git objekt
> mimo tento clone — odkaz v popisu nebo komentáři tiketu, tabulka vln, předávací
> komentář, odkaz v ledgeru — musí být pinovaný commit v tom okamžiku dosažitelný
> na `origin`. Ověřuje se strojově (`git branch -r --contains <sha>` po
> `git fetch`); nedosažitelnost je fail-closed stop, ne varování.

**Publikační body** (kdy se pushuje vlastní větev): po zápisu a commitu návrhu,
po zápisu a commitu plánu, při uzávěrce elaboračního okna *před* zápisem odkazů
do Jiry, před každým handoffem.

`mb-architect-review` krok 4 (dnes jediné místo, které to dělá správně) se
přepíše jako odkaz na tento invariant, aby pravidlo mělo jediný zdroj.

### 2. Dvouúrovňová push policy

| Úroveň | Pravidlo |
|---|---|
| **Vlastní tiketová větev** (nechráněná) | Agent pushuje sám, bez dotazu, ale vždy ohlásí větev a odchozí commity. Force push zakázán. |
| **Sdílené větve** (`develop`, `main`, `master`, `release/*`) | Agent nepushuje nikdy. Připraví přesný příkaz s výčtem odchozích commitů; uživatel ho schválí nebo provede sám (v sezení `! git push origin develop`). Agent poté znovu ověří dosažitelnost. |

**Mechanika.** Dnešní `permissions.deny: Bash(git push:*)` je binární a deny
vyhrává nad allow, takže allow pravidly to rozvolnit nelze; enumerovat zákazy
podle názvu větve je děravé (`git push` bez argumentů, `HEAD:refs/heads/develop`,
`+refspec`, `--all`). Řešením je **PreToolUse hook `guard-git-push.mjs`** vedle
existujícího `deny-superpowers-docs.mjs`:

- najde **každou** git invokaci v příkazu (tokenizace celého řetězce, ne
  kontextový regex — jinak proklouzne push na druhém řádku víceřádkového
  příkazu, v subshellu, za env prefixem nebo za `git -c k=v`);
- u `push` propustí **jen** invokaci, kterou bezpečně rozparsuje jako
  jednoduchý push nechráněné větve: uzavřený seznam neškodných přepínačů
  (`-u`, `-q`, `-v` a jejich dlouhé tvary), remote jako prosté jméno,
  refspec bez `+` a bez úvodní dvojtečky, cíl mimo chráněná jména; bez
  refspecu se dopočítá aktuální větev z `cwd` a nerozluštitelná větev
  zamítá;
- **cokoli jiného zamítne**, včetně tvarů, kterým nerozumí;
- u `fetch` jedno cílené pravidlo: zamítnout refspec, jehož cíl je chráněný
  lokální ref.

**Fail-closed allowlist, ne deny-list.** Původní návrh vyjmenovával nebezpečné
tvary; review ukázalo, že ta třída je otevřená — `--force-with-lease=…`, shluk
`-dq` (ověřeně smaže větev na remote), víceřádkový příkaz, `$(…)`, env prefix
i `git -c k=v` deny-listem prošly. Uzavřený seznam neškodných tvarů obrací
selhání správným směrem: neobvyklý příkaz se zamítne a přepíše na jednoduchý,
zatímco falešné propuštění pushe do `develop` zpět vzít nejde. Chráněná **jména
větví** zůstávají deny-listem (známá konečná množina, na rozdíl od jmen
tiketových větví).

Hook je zábradlí proti omylu agenta; skutečnou zárukou zůstává ochrana větví na
serveru. Ověřit při implementaci, že `push.default` je `simple` (git default od
2.0), aby bare `git push` nemohl poslat víc větví.

Hook je Claude-only lepidlo (`settings.json` se na ostatní harnessy záměrně
nenasazuje); pro ostatní harnessy platí totéž pravidlo textem kontraktu, stejně
jako u ostatních pravidel vrstvy. `mb-git-commit` zůstává bez pushe — publikace
není commit tool, ale krok workflow v bodech dle invariantu.

### 3. `mb-doc-index` — model tahu

Nový read-only skill (sourozenec `mb-epic-graph`) se skriptem
`scripts/doc-index.ps1`. Dokumenty se **netlačí do sdílené větve, ale hledají na
`origin`**. Důvody této volby jsou v sekci Zamítnuté alternativy.

**Algoritmus** (navržen tak, aby nerostl s počtem větví — tento fork má 163
vzdálených větví, naivní smyčka `git diff` na větev je nepoužitelná):

1. `git fetch --prune origin`.
2. **Jeden** traversal historie remote větví, omezený cestou, časem i bází:
   `git log --remotes=origin --not <BaseRef> --since=<SinceDays> --name-status
   --format='%H%x09%cI%x09%an' -- ':(glob)**/memory-bank/proposals/next/*.md'
   ':(glob)**/memory-bank/proposals/active/*.md'
   ':(glob)**/memory-bank/proposals/completed/*.md'` → kandidátní commity a
   soubory. `--not <BaseRef>` omezuje výsledek na to, co je na větvích **nad**
   bází, tedy na dosud nemergovanou práci.
3. Pro každý kandidátní soubor `git branch -r --contains <sha>` (které větve ho
   nesou) a `git cat-file -e <ref>:<path>` (existuje ještě na hrotu větve).
4. Hlavičky až na vyžádání: `git show <ref>:<path>` → `**Jira:**`, `**Stav:**`.
5. Sloučení se dvěma dalšími zdroji do jednoho obrázku: lokální working tree jako
   pseudo-větev `local` a obsah base refu (`git ls-tree` nad známými MB cestami,
   odvozenými z lokálního indexu) jako pseudo-větev `base`.
6. Výstup: česká tabulka pro člověka + `-Json <path>` strojově čitelný index.
   Tabulka ukazuje fáze `next`/`active`; `completed` se skenuje jen kvůli detekci
   obživlé fronty a v tabulce se neobjevuje.

**Parametry:** `-BaseRef` (výchozí `origin/develop`; v tomto forku
`origin/ums-memory-bank`), `-SinceDays` (výchozí 120), `-Json`, `-BranchGlob`
(volitelné zúžení na konvenci názvů). Cesty pod `*/tests/fixtures/*` se
vylučují, aby si vrstva nehlásila vlastní testovací data.

**Záznam indexu:** slug, tiket, fáze (`next`/`active`/`completed`), cesta, větev,
commit SHA, datum a autor commitu.

**Findings** (rozhodovací kandidáti pro člověka, ne automatické opravy):

- **stejný slug nebo tiket aktivní na cizí větvi** — hrozí dvojí práce; jediný
  finding, který v discovery zastavuje (viz sekce 4);
- **tentýž slug na více větvích** ve fázi `next` — dvojí rozpracování;
- **slug ve frontě i dokončený** — obživlé `next/` po převzetí draftu;
- **cizí aktivní slugy jiných tiketů** — normální paralelní provoz, jen
  informace v reportu, nikdy stop.

Index je čistě gitový nástroj a popisy tiketů nevidí, takže **nedosažitelný
commit v už publikovaném odkazu nehlásí**. Dosažitelnost se vynucuje v okamžiku
zápisu odkazu (`mb-jira-update` §7, sekce 6); průběžný audit dříve publikovaných
odkazů je mimo rozsah této položky.

### 4. Zapojení do discovery a two-actives guardu

Změny v kontraktní sekci **Target-MB Discovery & Pinning**:

- za lokální sken se vloží spuštění indexu; množina kandidátů je
  **lokální working tree ∪ cizí větve na `origin`**;
- krok aktivace draftu z `next/` hledá i v indexu. Nalezený draft na cizí větvi →
  nabídni převzetí. Převzetí je **kopie blobu**
  (`git show <ref>:<path> > <path>`), ne cherry-pick: elaborační okno se zavírá
  jedním commitem nesoucím ledger + graph + všechny proposaly okna, takže
  cherry-pick by přitáhl cizí ledger a konflikty. Do hlavičky převzatého návrhu
  se zapíše `**Převzato z:** <branch>@<sha>` — audit trail a podklad pro pozdější
  úklid `next/`;
- **two-actives guard zůstává lokální** — jeho smysl je „jedna aktivní položka na
  clone", protože `context.md` drží jeden pin. Rozšířit ho na `origin` by
  znamenalo „jedna aktivní položka na tým", což by zakázalo právě ten paralelní
  provoz, který má tato položka umožnit;
- vedle něj vzniká **meziclonová kolizní kontrola**: stejný slug nebo tentýž
  Jira tiket aktivní na cizí větvi je fail-closed stop (dvojí práce), a hlášení
  nese větev a datum posledního commitu, aby šlo rozhodnout mezi opuštěnou větví
  a živou prací. Cizí aktivní slugy **jiných** tiketů jsou normální stav — pouze
  se vypíšou;
- nové pravidlo: tiketová větev se zakládá z **aktuálního** base refu
  (fetch + fast-forward), jinak nevidí ani mergnuté plánování.

### 5. Zapojení do elaborace, grafu a stavu

- **`mb-epic-elaboration`:** bootstrap (protocol §0) spouští index a jeho findings
  jdou do agendy okna jako kandidáti dirty-setu. Uzávěrka okna publikuje **push
  vlastní větve** a teprve pak zapisuje commit-pinned odkazy do Jiry, takže odkaz
  platí v okamžiku vzniku. Drafty následných tiketů vzniklé uprostřed okna jdou
  na vlastní větev a push je zveřejní — bez cherry-picku a bez zápisu do
  `develop`.
- **`mb-epic-graph`:** nový parametr `-IndexFile` (JSON z `mb-doc-index`), aby
  stavový glyf „návrh hotov" viděl i drafty na cizích větvích; bez toho graf
  v paralelním provozu systematicky lže. Dva nové findings:
  `DRAFT NA CIZÍ VĚTVI` (info) a `DRAFT NA VÍCE VĚTVÍCH` (varování — stejný kód
  jako v indexu, aby tentýž jev neměl dva názvy). Neznámé
  hlavičkové pole `**Převzato z:**` parser ignoruje.
- **`mb-state`:** nová sekce „Cizí větve" — kdo drží co, s datem a s
  upozorněním na duplicitní slugy.

### 6. Tvrdá finalizace a publikace `develop`

- **`mb-jira-update` §7** dostane povinnou kontrolu dosažitelnosti pinovaného
  commitu; nedosažitelnost = stop s nabídkou pushe. Tím se stejným pravidlem
  opraví i mrtvé odkazy z elaborace.
- **Finalizační režim §10** navíc ověří, že merge commit je na `origin`. Když
  není, stop s pravdivým vysvětlením („kód je jen lokálně, tester nemá co
  testovat") a s příkazem k publikaci pro uživatele.
- **Finishing overlay, Option 1** dostane krok „publikovat `develop`?" —
  nabídka, výslovný souhlas, provedení uživatelem. Dnes v celém řetězci není
  žádný krok, který `develop` publikuje.
- Je-li `develop` na serveru chráněný proti přímému pushi, stop to řekne a
  nabídne alternativu (větev + výjimečné PR). **Ověřit v prvním tasku
  implementace** — rozhoduje o tvaru tohoto kroku.

### 7. Zamítnuté alternativy

**Push plánovacích dokumentů do `develop`** (docs fast-path plumbingem
`commit-tree` nad `origin/develop`, bez checkoutu): funkční a race-safe, ale
potřebuje právo pushovat do `develop`, mění význam `develop` (plánovací
dokumenty tam přistanou bez kódu, který plánují) a hlavně **nezvládne
rozpracované elaborační okno** — publikoval by nekonsolidované plánování.
Ponecháno jako volitelná konsolidace při uzávěrce okna v pozdější položce; jeho
jediná výhoda proti tahu je, že maže účetní práci s obživlým `next/`.

**Cherry-pick commitu s draftem:** špatná granularita, viz sekce 4.

**Oddělené docs repo jako submodul monorepa:** zamítnuto, protože rozbíjí to, na
čem kontrakt stojí:

1. rozpojí verzování kódu a dokumentace — harvest stojí na tom, že dokumentace
   následuje kód a že `AFFECTED_MBS` se derivují z **diffu větve**; se submodulem
   není doc změna v diffu tiketu vůbec;
2. `MB_ROOT` discovery je jediný krok `git rev-parse --show-toplevel` a kontrakt
   explicitně zakazuje walky a fallback ankory — v submodulu vrátí kořen
   submodulu, takže se přepisuje třívrstvý model, scope lock i Write Safety Gate
   (kontrakt v3.0, dotkne se každého skillu);
3. gitlink je jeden soubor, který mění každá tiketová větev → konflikt na každé
   paralelní dvojici; vyměnili bychom kolizi `context.md` za horší, a přesně
   v případu, který léčíme;
4. MB dokumenty jsou per-projekt a leží u kódu, který popisují — jedno docs repo
   je buď zploští (padá lokalita, na které stojí Target-MB discovery a evidence
   tagy), nebo potřebuje submodul na komponentu;
5. detached HEAD a zapomenutý push v submodulu je klasická past, kterou
   fail-closed pravidla nezachytí.

Kdy by naopak byl správně: kdyby dokumentová vrstva měla obsluhovat epiky
**napříč více repozitáři**. Tam argument lokality padá. Do té doby ne.

**Průběžná aktualizace trvalých MB dokumentů během exekuce:** zamítnuto —
implementátorské subagenty MB dokumenty vůbec nečtou (task brief je awk výřez
tasku z plánu, v celém adresáři SDD skillu není zmínka o Memory Bank), takže by
nikomu nepomohla; navíc by na větvi tvrdila o projektu něco, co v `develop`
není, a znásobila kolize ve sdílených dokumentech. Skutečná mezivětvová
zastaralost se léčí integrací blokéra, ne průběžnou dokumentací.

## Dopady

| Artefakt | Změna |
|---|---|
| `UMS_MEMORY_BANK_CONTRACT.md` | nová sekce Publication Contract; rozšíření Target-MB Discovery & Pinning (sken s indexem, aktivace draftu z cizí větve, meziclonová kolizní kontrola, zakládání větve z aktuální báze); krátká sekce o viditelnosti napříč větvemi včetně pravidla pro obživlý `next/`; Architect Review Gate odkáže na invariant |
| `mb-doc-index` (nový skill) | `SKILL.md`, `scripts/doc-index.ps1`, `tests/` |
| `mb-epic-graph` | `-IndexFile`, dva nové findings, rozšíření testů |
| `mb-epic-elaboration` | `SKILL.md` + `protocol.md` §0 a §3 |
| `mb-state` | sekce „Cizí větve" |
| `mb-jira-update` | §7 kontrola dosažitelnosti, §10 brána |
| `mb-architect-review` | krok 4 → odkaz na invariant |
| overlay `brainstorming` | discovery s indexem, publikace po zápisu návrhu |
| overlay `subagent-driven-development` | publikace plánu před dispatchem prvního tasku (vedle baseline checku) |
| overlay `finishing-a-development-branch` | krok „publikovat `develop`?" u Option 1 |
| `ums/.claude/settings.json` | z `permissions.deny` zmizí `Bash(git push:*)`; přidán PreToolUse hook; do `permissions.allow` čtecí příkazy indexu (`git fetch`, `ls-remote`, `for-each-ref`, `ls-tree`, `merge-base`, `branch -r`) |
| `ums/.claude/hooks/guard-git-push.mjs` | nový hook |
| `memory-bank/architecture.md`, `tech.md` | harvest na konci větve |

**Zůstává zachováno:** invariant *přesně tři overlay bloky* — publikace plánu se
přilepí na SDD overlay, čtvrtý overlay nezavádíme.

**Testy:**

- `doc-index.ps1` proti fixture repu (lokální bare „origin" + několik větví,
  deterministicky, bez sítě): cizí aktivní slug, duplicitní slug, slug ve frontě
  i dokončený, filtrování cest `tests/fixtures`, prázdný výsledek, respektování
  `-SinceDays` a `-BaseRef`;
- `guard-git-push.mjs` unit testy (JSON na stdin → rozhodnutí): `develop`,
  `main`, `release/*`, force i `+refspec`, `--all`/`--mirror`, `--delete`, bare
  `git push` na chráněné i tiketové větvi;
- rozšíření stávajících testů `epic-graph.ps1` o `-IndexFile` (glyf a findings).

## Rizika

| Riziko | Ošetření |
|---|---|
| Latence indexu při stovkách větví | jeden traversal `git log --remotes` s filtrem cest a `-SinceDays`; cache v rámci sezení; volitelný `-BranchGlob` |
| Chráněný `develop` na serveru zablokuje publikaci | ověřit v prvním tasku; fail-closed stop nabídne větev + výjimečné PR |
| Rozvolněný push umožní agentovi publikovat rozpracovanou práci | ohlášení každého pushe, zákaz force, jen vlastní tiketová větev (nízká škoda, plně revertovatelné) |
| Falešný pozitiv two-actives guardu z opuštěných větví | hlášení nese datum posledního commitu; rozhoduje člověk, ne skript |
| Obživlé `next/` po převzetí draftu | detekce v indexu i v `mb-epic-graph -Check`; úklid je jeden `git rm` |
| Hook chrání jen Claude Code | ostatní harnessy mají pravidlo textem kontraktu — stejný model jako u ostatních pravidel vrstvy |
| Drift upstreamu v kotvě finishing overlaye | jediný `ANCHOR-BEFORE` fragment se nemění, přidává se obsah do existujícího bloku |

## Navazující položky (mimo rozsah)

V tomto pořadí, každá jako samostatná pracovní položka:

1. **Průběžný záznam výsledku** — `handoff_<slug>.md` psaný orchestrátorem SDD po
   projití task review, čtený task briefem, konzumovaný harvestem (kříží ho
   s `git diff` oběma směry) a `mb-jira-update`; archivace do `completed/` vedle
   návrhu. Zavírá 12 (částečně) a 21.
2. **Předání pro člověka** — testovací předpoklady z vln grafu (které tikety musí
   být nasazené) a epický deployment přehled. Zavírá 22 a 23.
3. **Vrácení z testu** — reopen semantika v kontraktu a protokol návratu (dnes je
   po Option 1 `context.md` IDLE, plán smazaný, větev smazaná). Zavírá 24.
4. **Origin jako sdílené médium, dokončení** — normativní název tiketové větve,
   `Base:` v hlavičce návrhu a v Jiře pro stacked větve (dnes je `<base>`
   v harvestu nespecifikovaná). Zavírá 15 a zpřesňuje 14.
5. **Claim a park** — `mb-claim` (Jira jako registr vlastnictví), `mb-park`
   (design review nedrží pin). Zavírá 3 a 18.
6. **Strukturální oprava** — `context.md` mimo kolizní cestu, cestující SDD
   kontext, epická vrstva v kontraktu, mergovatelný dirty-set. Zavírá 4, 8, 9,
   10, 12, 17.
