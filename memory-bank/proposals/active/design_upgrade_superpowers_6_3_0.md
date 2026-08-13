# Návrh: Upgrade vendorovaných superpowers skillů na v6.3.0

- **Jira:** (žádný tiket)
- **Target MB:** memory-bank/
- **Vytvořeno:** 2026-08-13

## Cíl

Zvednout vendor pin vrstvy z v6.2.0 na v6.3.0 tak, že po revendoru **nezůstane
v žádném nasazeném skillu rozporný instrukční text**. Jádro práce není bump
verze — je to uzavření čtyř rozporů mezi upstream textem v6.3.0 a vrstvou UMS,
které by revendor jinak tiše propustil: dva ze tří overlay fragmentů jsou
ukotvené na `EOF` a jediná `ANCHOR-BEFORE` kotva (`## Step 5: Execute Choice`)
v v6.3.0 stále existuje právě jednou, takže detektor driftu tuhle vlnu vůbec
neohlásí, přestože upstream věcně změnil dva ze tří overlayovaných skillů.

Co v6.3.0 přináší a proč upgrade stojí za to:

- **„Rulings, not stalls" v SDD** — agent konflikty a nejasnosti rozhoduje sám,
  zapisuje `Ruling:` do ledgeru a před smazáním workspace předloží vyčerpávající
  seznam „Rulings I made"; STOP jen ve čtyřech jmenovaných třídách. Systémová
  verze toho, co CLAUDE.md tohoto repa dosud řešil ručním pravidlem o odkladu
  eskalačních bodů.
- **Efektivita SDD zdarma** — batchování malých stejnotvarých tasků do jednoho
  dispatche, zákaz worker-spawned reviewerů (upstream: duplicitní review seat na
  task), bounded waiting místo pollingu.
- **Konvergence** — nové pole `**Spec:**` v hlavičce plánu je to, co UMS už dělá
  polem `**Návrh:**`; `render-graphs.js` opravuje `which dot` (na Windows
  neexistuje) na `dot -V`.
- **Router tří cest v brainstormingu** (spike / bounded / architectural) —
  přínos sporný, vrstva ho přebírá konzervativně (viz Technický návrh).

## Rozpory, které upgrade uzavírá

| Upstream v6.3.0 | Vrstva UMS dnes | Uzavření |
|---|---|---|
| „the **spec** is the binding authority, the plan is its argument" (SDD) | kontrakt: „On conflict between the two, the **plan** governs execution" | kontrakt v2.9, rozdělení autority podle předmětu sporu |
| bounded: „no spec file, no implementation plan document" (brainstorming) | overlay: „Item 6: save to `<PLAN_MB>/proposals/active/design_<slug>.md`" | kontrakt v2.9, podsekce Brainstorming Paths + přepis fragmentu |
| „Rule and continue; stop only if every path forward is a guess" (SDD) | fail-closed STOPy vrstvy (kolize, nechráněná báze, nedosažitelný commit, …) | kontrakt v2.9: STOPy vrstvy spadají DOVNITŘ upstreamové čtveřice |
| „If the plan names a Spec, read that too" (SDD) | hlavička plánu nese `**Návrh:**`, ne `Spec` | přejmenování pole na `**Spec:**`, alias pro čtenáře |
| „Item 1 / item 6 / between item 8 and item 9" (odkazy fragmentu) | tři checklisty v6.3.0 mají každý vlastní položky 1–5 | přepis odkazů na jména fází |

## Scope

### V rozsahu

1. Merge upstreamu (`vanila/main`, release v6.3.0) do této větve.
2. Kontrakt v2.8 → v2.9 (sedm bodů níže).
3. Přepis všech tří overlay fragmentů.
4. Direktiva `ASSERT` v revendor skriptu (detektor driftu i pro `EOF` kotvy).
5. Aktualizace dokumentů a pinů vrstvy i Memory Bank.
6. Obnova lokálního nasazení (kořenový `.claude/`, `.agents/skills/`) včetně
   revendoru s `-Tag v6.3.0`.
7. Verifikační baterie (šest vrstev, viz Verifikace).

### Mimo rozsah (vědomě)

- **Povýšení bounded na plnohodnotný lehký režim** — rozlišení „záměrně bez
  plánu" od „nedokončeno" v `mb-state` a `mb-harvest`, rulingy jako vstup do
  harvestové brány, Epic Backflow na bounded cestě. Samostatná pracovní položka,
  až bude z tří cest praxe; fragment finishing dostane jen minimum (jedna věta),
  aby agent na harvest varování neuvízl.
- **FF push zrcadla `main` na `vanila/main`** a **nasazení do monorepa**
  (`sync ToMonorepo` + dvoucommitový revendor tam) — samostatné uživatelem
  řízené kroky mimo tuto větev; pro `main` agent připraví příkaz (chráněná
  větev).
- Jakékoli změny upstream souborů mimo `ums/` (aditivní invariant větve).

## Technický návrh

### 1. Merge upstreamu — první krok, před jakýmkoli psaním

`git merge vanila/main` (před tím ověřit, že tip je stále release commit
v6.3.0). Aditivní invariant tvrdí bezkonfliktnost — ověří se skutečným mergem,
ne tvrzením. Upstream v rozsahu v6.2.0..v6.3.0 nesahá na `CLAUDE.md` a root
`.gitignore` mění jen o Python ignory.

### 2. Kontrakt → v2.9, sedm bodů

**2.1 Autorita při konfliktu** (sekce Active Work Item). Nahradit větu „On
conflict between the two, the plan governs execution; report the discrepancy to
the user." rozdělením podle předmětu sporu — vytažením toho, co kontrakt už má
v labelech „intent source of truth" × „execution source of truth":

> A conflict between the halves is resolved **by its subject**: **what** should
> be built is the design's to decide — it is the binding authority upstream's
> ruling model measures against, and the artifact that survives in
> `completed/`; **how** and in what order is the plan's — it was written
> against the code, the design was not. Either way the discrepancy is recorded
> as a ruling and surfaced to the user, never silently absorbed.

**2.2 `**Návrh:**` → `**Spec:**`** (Superpowers Document Placement + Link
Conventions; ověřeno, že pole má právě dva výskyty, oba v kontraktu — žádný
`mb-*` skill ho nečte, archiv žádný nenese, plány se harvestem mažou, takže bez
migrace). Anglické jméno je konzistentní s Language Contract (AI-facing
boilerplate v plánu je anglicky). Čtenáři tolerují `**Návrh:**` jako alias —
stejný mechanismus jako `- **Proposal:**` pro `Work item`. Směr odkazu
plán → návrh se nemění.

**2.3 Nová podsekce „Brainstorming Paths"** (do Superpowers Document
Placement). Dokumentová vrstva se ptá na jedinou otázku — **bude se to
integrovat?**

- **Cokoli, co se má integrovat, potřebuje pin a návrh**, bounded včetně.
  Bounded se od architectural liší přesně dvěma věcmi: nepíše `plan_<slug>.md`
  a nepouští SDD; jeho krátký návrh z chatu se po schválení **zapíše** do
  `<PLAN_MB>/proposals/active/design_<slug>.md`, takže harvest, integrace, Jira
  i archiv fungují beze změny. Návrh bez plánu je už dnes platný stav.
- **Spike nepinuje nic a nezapisuje nic** pod `proposals/`. Vstupní brána mu
  proběhne ve fázích způsobilosti, inventáře a případného rozhodnutí; větev se
  mu založí, **jakmile má sahat na strom** — spike, který mění soubory, nikdy
  neběží na bázi; čistě read-only průzkum větev nepotřebuje. **Fáze zápisu
  pinu se přeskočí vždy.** Když se odpověď promění v práci, request se
  reklasifikuje a brána doběhne.
- Ratchet je upstreamový a jednosměrný. „Tohle chce review architekta" je sám
  o sobě architektonický signál — Architect Review Gate existuje jen na
  architektonické cestě.

**2.4 Rulingy × fail-closed STOPy** (sekce Fail-Closed Behavior). STOPy vrstvy
**spadají dovnitř upstreamové čtveřice**, ne vedle ní:

> Ruling model řídí všechno uvnitř tasku. Nedosáhne na fail-closed STOPy této
> vrstvy, protože ty už patří do upstreamových tříd: push do sdílené větve a
> integrační push jsou „side effect mimo tento klon, kde normy velí se zeptat";
> kolize aktivní práce, nechráněná báze a nedosažitelný pinovaný commit jsou
> nevratné ve stejném smyslu — zdvojenou práci ani referenci, kterou nikdo
> nerozřeší, aktér zpětně nevezme; rozbitý plán je čtvrtá třída sama o sobě.
> **Jedna věc naopak takovým side effectem NENÍ: merge efektivní báze do
> VLASTNÍ tiketové větve.** Je povinný na hranicích fází a uživateli se
> nepředkládá — číst upstreamové slovo „merge" tak, že ho pokrývá, by proměnilo
> povinný base sync před prvním dispatchem v otázku.

(V kontraktu formulováno anglicky; zde česky pro čtenáře návrhu.)

**2.5 Ruling × kandidát playbooku** (Playbook Contract, jedna věta). *Ruling je
rozhodnutí, kandidát je postup.* Ruling se stane kandidátem jen tehdy, když
nese `Happened` evidenci přesahující tuhle pracovní položku; jinak zůstává
v ledgeru a v seznamu „Rulings I made". Rozhoduje formát — bez `Happened` není
kandidát. Do Language Contract: `Ruling:` řádky v ledgeru jsou AI-facing →
anglicky; závěrečný seznam „Rulings I made" je uživatelský → česky (týž
translate-on-presentation split jako u kandidátů).

**2.6 Past prvního pushe** (Publication Contract, opt-in). Jedna věta: první
publikace čerstvě založené tiketové větve je `git push -u origin <branch>`,
nikdy bare `git push` — `git switch -c <branch> <báze>` nastavil upstream nové
větve na BÁZI, takže bare push by mířil do chráněné větve. Past je dnes
zachycená jen v playbooku tohoto repa; fragment brainstormingu na větu odkáže
v místě prvního pushe návrhu.

**2.7 Hlavička verzí.** Nový řádek v2.9 (souhrn: rozdělení autority pár,
`Spec:` pole, Brainstorming Paths, mapování STOPů do ruling modelu, ruling ×
kandidát, past prvního pushe) a **přeformulování** stávajícího řádku na „v2.8
superseded v2.7" — konvence running „Supersedes" historie dle playbooku.

### 3. Overlay fragmenty

#### 3.1 `brainstorming.overlay.md` — přepis odkazů a nový úvod

a) **Nový úvodní odstavec o routeru.** Normativní zdroj je kontraktová
podsekce Brainstorming Paths; fragment jen mapuje: architectural i bounded
běží vstupní bránu celou a oba produkují `design_<slug>.md`; rozcházejí se až
po schválení (bounded bez plánu a bez SDD). Spike běží způsobilost, inventář
a založení větve, NE zápis pinu, a nepíše nic pod `proposals/`. A dále: kde
úprava níže jmenuje položku upstream checklistu, jmenuje ji **jménem fáze** —
všechny tři cesty číslují vlastní položky 1–5, ordinál sám o sobě už krok
neidentifikuje.

b) **„Item 1" → fáze „Explore project context"** (architektonická a bounded
cesta), sedm kroků beze změny obsahu; doplnit, že u spike se krok zápisu pinu
přeskočí a krok aktivace z `next/` nemá co aktivovat.

c) **„Item 6 (Write design doc)" → jména podle cesty.** Věcný rozdíl: na
architektonické cestě se návrh zapíše a commitne a teprve pak si ho uživatel
čte; na bounded cestě je návrh schválený v chatu a zápis ho následuje — po
schválení se týž dokument uloží do `<PLAN_MB>/proposals/active/design_<slug>.md`
a **nečeká se na druhé kolo schválení** (bounded cesta žádnou revizi souboru
nemá; bez této věty by agent uvízl).

d) **Architect Review Gate:** „mezi body 8 a 9" → „po schválení zapsaného
návrhu a před přechodem k implementaci, jen architektonická cesta". Plus věta:
na bounded cestě se gate nenabízí a „tohle by chtělo posudek architekta" je
signál pro upgrade cesty, ne pro nabídnutí review v bounded režimu.

e) **Amendment pravidla o terminálním stavu** (upstream je nově path-bound):
architectural — `mb-architect-review` smí následovat brainstorming,
writing-plans zůstává jediným implementačním následníkem; bounded —
implementace jde normálním workflow, **ale stále končí ve
finishing-a-development-branch** (má pin a návrh, takže Harvest Gate
a integrační cesta platí stejně jako u architectural); spike — reportované
doporučení, žádný MB artefakt. Prostřední věta je nutná — upstream u bounded
finishing vůbec nezmiňuje a bez ní by bounded práce skončila nezintegrovaná
a nesklizená.

f) **Epic Backflow — pojmenovaný odklad.** Zůstává na architektonické cestě;
u bounded se výslovně napíše, že se zatím nespouští a proč (bounded je
definičně ohraničená změna existujícího flow, posun scope/závislostí tiketu je
nepravděpodobný), s poznámkou, že `mb-epic-graph -Check` zůstává ručně
k dispozici. Pojmenovaný odklad, ne mlčení.

g) **První push** nové větve odkáže na kontraktovou větu z bodu 2.6
(`git push -u origin <branch>`).

#### 3.2 `subagent-driven-development.overlay.md` — pět dodatků

1. **Rulingy × STOPy** — nová odrážka odkazující na kontrakt jménem sekce (bez
   parafráze důvodu) plus čistě lokální doplněk: merge efektivní báze do
   vlastní tiketové větve NENÍ ten „side effect mimo worktree", který upstream
   míní — je povinný na hranicích fází a uživateli se nepředkládá.
2. **Autorita a `Spec:`** — konflikt návrh × plán se řeší per kontrakt (jméno
   sekce); hlavička plánu nese `**Spec:**` s cestou k `design_<slug>.md`,
   takže upstreamové „if the plan names a Spec, read that too" je splněné
   a rulingy nejsou provizorní.
3. **Batchované dispatche** — procedurální dokument (playbook) se přikládá
   i k dávce; jeden report dávky = jedna sekce `## Playbook candidates` za
   celou dávku.
4. **Ruling × kandidát** — jedna věta + odkaz na kontrakt (bod 2.5).
5. **Finish** — explicitně: `rm -rf <workspace>` maže
   `.superpowers/sdd/<plan-basename>/`; kandidáti playbooku leží
   v `.superpowers/playbook-candidates/` mimo plan workspace a přežívají —
   maže je až harvest. Bez této věty vypadá upstreamová instrukce v UMS
   kontextu jako ztráta evidence.

Terminologie: „outside this worktree" → klon/workspace (worktrees zakázané).
Jazyková odrážka: `Ruling:` v ledgeru anglicky, závěrečný seznam „Rulings
I made" česky.

#### 3.3 `finishing-a-development-branch.overlay.md` — jedna věta

Kotva `## Step 5: Execute Choice` v v6.3.0 drží (ověřeno: právě jeden výskyt);
upstream změna Step 6 se týká worktrees (v UMS zakázané) — bez zásahu. Jediný
dodatek: u bounded pracovní položky je `active/` bez plánu **očekávaný stav** —
harvest chybějící plán jen ohlásí (dle kontraktu je to warning), nejde
o nedokončenou práci. Skutečné rozlišení v `mb-harvest`/`mb-state` je
v odložené části.

### 4. Direktiva `ASSERT` v revendor skriptu (opt-in #2)

Rozšíření formátu fragmentu o volitelnou direktivu (0..N na fragment), řazenou
za `TARGET`/`ANCHOR` řádky:

```
<!-- ASSERT: <exact line text> -->
```

`Invoke-Overlays` při aplikaci fragmentu ověří, že text matchuje **právě jeden
řádek** cílového souboru (týž mechanismus jako `ANCHOR-BEFORE`: porovnání
`TrimEnd()` řádků, miss = hard error se jménem fragmentu a textu). Do fragmentů
přijdou asserty na věty, na kterých overlay sémanticky stojí — např.
`**Terminal states are path-bound.** Architectural: the ONLY skill you`
v brainstormingu, `Four things stop you, and only these: an irreversible or
destructive` v SDD. Příští upstream změna těchto vět shodí revendor stejně,
jako dnes padá `ANCHOR-BEFORE` miss — `EOF` kotvy tím přestávají být slepé.

Náklad: ~20 řádků v `revendor-superpowers.ps1`, odstavec
v `overlays/README.md`, 2–3 asserty na fragment. Testovací sada na revendor
skript se nezavádí — nejhorší selhání je „chrání slaběji, než jsme mysleli",
ne škoda.

### 5. Dokumenty a piny

| Soubor | Změna |
|---|---|
| `ums/.claude/skills/shared/SKILLS_MANIFEST.md` | 2× v6.2.0 → v6.3.0 |
| `ums/README.md` | 2× verze; harness matice doplnit Devin CLI a Hermes Agent (nové v v6.3.0) |
| [tech.md](../../tech.md) | řádky pinů (verze, tag, commit, datum); smazat poznámku o zaostávajících textových zmínkách (tímto se uzavře); kontrakt 2.8 → 2.9 |
| [brief.md](../../brief.md) | řádek stavu (kontrakt v2.9, pin v6.3.0) |
| [architecture.md](../../architecture.md) | kontrakt v2.8 → v2.9 (3 místa); popis Overlay 1 přes „body 1/6/8–9" → jména fází; doplnit ASSERT direktivu do popisu vendoringu |
| `CLAUDE.md` (fork) + `ums/CLAUDE.md.sample` | řádek o odkladu eskalačních bodů SDD nahradit odkazem na ruling model (upstream to teď dělá systémově; ruční pravidlo by bylo duplicitní restatement) |
| `ums/.claude/scripts/revendor-superpowers.ps1` | komentář „v6.2.0 sdd-workspace" aktualizovat; ASSERT direktiva (bod 4) |
| `ums/.claude/skills/shared/VENDORED_FROM.md` | píše revendor skript sám (tag, commit, datum) |

### 6. Lokální nasazení a pořadí provedení

1. Merge upstreamu (bod 1).
2. Kontrakt v2.9 (bod 2).
3. Fragmenty (bod 3) + ASSERT direktiva (bod 4).
4. Dokumenty a piny (bod 5).
5. Obnova nasazení: kopie `ums/.claude/` → kořenový `.claude/`
   (+ `ums/.claude/skills/` → `.agents/skills/`), pak
   `revendor-superpowers.ps1 -Tag v6.3.0 -UmsRoot <kořen forku>` — tři overlay
   skilly se kopií nevyrobí. Vygenerovaný `VENDORED_FROM.md` z nasazení
   převzít do trackovaného `ums/.../shared/VENDORED_FROM.md`; liší se jediným
   řádkem „Vendored on top of repo state" (per-repo hodnota) — správné, ne
   drift. Ověřeno: kořenová nasazená kopie je aktuální (v2.8, 3 overlay
   bloky), takže je plnohodnotným cílem revendoru.
6. Verifikační baterie (níže).
7. Finishing → harvest → integrace FF pushem (sdílený push spouští uživatel).

Commity průběžně po logických celcích, každý pushnutý (publikační pravidlo);
česky, s diakritikou.

## Verifikace — šest vrstev

Na instrukční text neexistují testy; správnost se dokazuje čtením
a sezením. Vrstvy:

1. **Revendor verify pass** — `-VerifyOnly` končí `Verification passed.`
2. **Tabulka uzavření rozporů** — pro každý z pěti rozporů řádek: upstream
   věta (soubor:řádek **ve vygenerovaném souboru**, ne ve fragmentu) × věta
   vrstvy × mechanismus uzavření (jmenovitá negace / precedence / shoda jména
   pole). Čte se proti vygenerovaným souborům — fragment vedle přebíjeného
   textu se čte jinak než výsledek.
3. **Grep sweepy** (dle playbooku): `item [0-9]`, `steps? [0-9]`, `\bstep`
   (case-insensitive), číslovky slovem — nulový výskyt starých tvarů;
   charakteristické tokeny změněných pravidel přes celou vrstvu včetně hlaviček
   hooků, šablon reportů a fragmentů (`Návrh:`, `plan governs`, `execution
   source of truth`, `worktree`, `2.8`); počítací fráze („the single
   exception", „jediná výjimka", „exactly one") — body 2.5/2.6 zavádějí nové
   instance, které mohou tiše zneplatnit existující kardinalitní věty.
4. **Cold-reader průchod per záměr** — tabulka: cesta (spike / bounded /
   architectural) × tiket (ano / ne) × strom (čistý / zbytky v cestě) →
   dostane se chladný čtenář ke správným krokům? Jediná obrana proti bodu
   checklistu, který restrukturalizace nechala stát a agent ho vykoná.
5. **Sady vrstvy** — celá smyčka (16 sad, 613 asercí; `pre-push` sada běží
   přes dvě minuty, normální). Na skripty se sahá jen v revendoru (ASSERT) —
   očekávaná změna nula, jakákoli červená je nález. ASSERT větev se ověří
   negativně ručně: fragment s assertem na neexistující řádek musí revendor
   shodit.
6. **Akceptační sezení** — první reálné použití bounded cesty je odložená
   práce sama (rozlišení bounded v `mb-state`/`mb-harvest` je učebnicově
   bounded změna): užitečná práce a zároveň test klasifikace, brány, pinu,
   návrhu a harvestu.

## Dopady

- **Chování agenta v monorepu:** SDD přestane stavět na eskalacích — rozhodne,
  zaloguje ruling, pokračuje; uživatel dostane seznam rulingů na konci. Méně
  uvíznutých běhů, za cenu občasného reworku špatného rulingu (viditelného,
  vratného).
- **Drobná práce zlevní:** bounded cesta = pin + krátký návrh + normální
  implementace, bez plánu a SDD ceremonie. Spike nezanechává v MB nic.
- **Dokumentová vrstva beze změny chování:** harvest, integrace, Jira, archiv
  fungují pro bounded stejně jako dnes pro architectural (návrh bez plánu je
  platný stav už v v2.8).
- **Budoucí revendory bezpečnější:** ASSERT direktiva dělá z `EOF` fragmentů
  detektory driftu.
- **Nasazení do monorepa** (mimo rozsah) převezme vše bez dalších úprav —
  fragmenty i kontrakt jsou tatáž vrstva.

## Rizika

| Riziko | Zmírnění |
|---|---|
| EOF kotvy neohlásí ani příští drift (tento upgrade je slepý stejně) | ASSERT direktiva (bod 4); tabulka uzavření rozporů zůstane v archivovaném návrhu jako seznam míst k re-čtení |
| Kontrakt 1574 řádků — rozejití pravidel při zásahu | grep sweepy (verifikace 3); pravidlo se píše do kontraktu, fragment odkazuje jménem sekce |
| Merge 53 upstream commitů | první krok, ověřený skutečným mergem; invariant aditivnosti |
| Epic Backflow se u bounded nespustí | pojmenovaný odklad ve fragmentu; `mb-epic-graph -Check` ručně |
| Sezení pracuje se starou nasazenou kopií | obnova nasazení je krok 5 provedení, ne úklid po; staleness kontrola `diff -rq` proti nasazení (playbook) |
| Agent na bounded cestě uvízne na harvest varování „chybí plán" | jedna věta ve fragmentu finishing (bod 3.3) |
| ASSERT slabší, než se čeká (chybný match) | negativní ruční ověření (verifikace 5); nejhorší selhání je slabší ochrana, ne škoda |
