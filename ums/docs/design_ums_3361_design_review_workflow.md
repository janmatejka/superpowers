# Návrh: Přejmenování design/plan dokumentů a workflow Design Review

- **Jira:** UMS-3361 (https://datasyscz.atlassian.net/browse/UMS-3361)
- **Target MB:** — (fork superpowers nemá Memory Bank; dokument žije v `ums/docs/`)
- **Plán:** [plan_ums_3361_design_review_workflow.md](plan_ums_3361_design_review_workflow.md) (vznikne ve writing-plans)
- **Vytvořeno:** 2026-07-30

## Cíl

Tři provázaná rozšíření UMS vrstvy (adresář `ums/` forku `janmatejka/superpowers`):

1. **Nová terminologie pracovních dokumentů** — pár `design_<slug>.md` + `plan_<slug>.md` místo `proposal_<slug>-design.md` + `proposal_<slug>.md`.
2. **Workflow Design Review** — po schválení návrhu v brainstormingu lze design předat k posouzení architektovi přes Jira tiket; nový skill `mb-architect-review` (režimy request / respond / resume).
3. **Upřesnění dokončení větve** — dotaz na refresh lokálního `develop` z `origin/develop` před mergem a přechod tiketu přímo do stavu „Test" po finalizačním `mb-jira-update`.

Změny se provádějí v `ums/` tohoto forku; do živého monorepa (`d:\_datasys\ums`) se přenesou následně přes `sync-with-monorepo.ps1` (mimo scope tohoto úkolu).

## Scope

**Zahrnuto:** kontrakt (`UMS_MEMORY_BANK_CONTRACT.md`), overlaye (brainstorming, finishing-a-development-branch), skilly `mb-harvest`, `mb-jira-update`, `mb-state`, `mb-abort`, `mb-scan`, `mb-sync`, `mb-init`, `mb-epic-elaboration` (+ `protocol.md`), `mb-epic-graph` (+ `epic-graph.ps1`, fixtures), nový skill `mb-architect-review`, `CLAUDE.md.sample`, `ums/README.md`, `SKILLS_MANIFEST.md`, hook `deny-superpowers-docs.mjs` (prověření referencí).

**Mimo scope:** design review pro předběžné drafty v `proposals/next/` (epic elaboration); notifikace architekta mimo Jira (mail, chat); nasazení do monorepa a ostatních harnessů (samostatný sync krok); přejmenování existujících dokumentů.

## Technický návrh

### 1. Terminologie a pojmenování

**Nová konvence** (pro nově vytvářené dokumenty):

| Artefakt | Dosud | Nově |
|---|---|---|
| Design/spec (brainstorming) | `proposal_<slug>-design.md` | `design_<slug>.md` |
| Implementační plán (writing-plans) | `proposal_<slug>.md` | `plan_<slug>.md` |

- Pravidla slugu beze změny: `<jira>_<short_snake_case_topic>` (ticket kód lowercase snake case), bez tiketu jen `<short_snake_case_topic>`, ASCII, bez diakritiky, bez datumů.
- Adresáře `proposals/{next,active,completed,abandoned}/` zůstávají beze změny.
- Terminologie v próze skillů: „proposal pair" → **„work item pair (design + plan)"**, česky **„pár návrh+plán"**. Slovo „proposal" přežívá jen jako název adresáře a legacy prefix.

**Grandfather clause (rozšíření stávající):**

- Legacy soubory `proposal_<slug>-design.md` / `proposal_<slug>.md` v klidovém stavu (`completed/`, `abandoned/`, ležící fronta `next/`) a legacy páry v `active/` zůstávají navždy platné artefakty — nepřejmenovávají se ani nekonvertují.
- Jeden work item používá vždy jeden styl pojmenování; smíšený pár (legacy design + nový plan) nevzniká. Nová práce vždy vytváří nový styl.
- **Aktivace legacy draftu z `next/` konvertuje do nového stylu:** přesun `next/` → `active/` přejmenuje draft na `design_<slug>.md` (obsah slouží jako design seed bez ohledu na původní strukturu; případná legacy `-design` polovina se sloučí/použije přednostně). Od aktivace dál jde o work item v novém stylu. To je jediná povolená konverze legacy souboru.
- Discovery globy se rozšiřují na `{design_,plan_,proposal_}*.md`. Párování: nový styl = stejný slug pod prefixy `design_`/`plan_`; legacy = strip `-design` ze stemu. Kandidát = `(vlastnící MB, slug)` bez ohledu na styl.
- Přejmenování slugu při pozdějším zjištění tiketu (aktivace předběžného návrhu) platí dál — v rámci téhož stylu.

**`context.md`:** pole `- **Proposal:** <slug>` se nově zapisuje jako `- **Work item:** <slug>`. Oba názvy pole akceptují **všichni čtenáři** `## Active Work` — `mb-state`, `mb-harvest`, `mb-abort`, `mb-jira-update`, `mb-scan`, `mb-sync`, `mb-git-commit`, `mb-git-message`; zapisovatelé (Target-MB Discovery, harvest/abort reset) píší jen nový. Nově schéma připouští volitelný řádek `- **Review:** design-review requested YYYY-MM-DD` (zapisuje/maže výhradně `mb-architect-review`, viz sekce 2).

**Řádek v popisu Jira tiketu (`mb-jira-update` §7b):** nová podoba `**Návrh (design):** [design_<slug>.md](<commit-pinned URL>)`. Idempotentní refresh nahradí i legacy řádek `**Návrh (proposal):** …` (a stale odkaz na plan/legacy soubor přesměruje na design). Kontrolní hlášky `mb-epic-graph -Check` (`TIKET BEZ ODKAZU NA PROPOSAL`, `ODKAZ NA NEEXISTUJÍCÍ PROPOSAL`) akceptují oba tvary řádku.

**Harvest/abort:** beze změny logiky — archivuje se design polovina (`design_<slug>.md`, resp. legacy `proposal_<slug>-design.md`), plán se maže (`plan_<slug>.md`, resp. legacy `proposal_<slug>.md`); abandon přesouvá obě poloviny. Grandfathered single-file plán se archivuje.

**Epic elaboration a předběžné návrhy:** předběžné drafty v `proposals/next/` jsou nově **`design_<slug>.md`** — detailní plány se předběžně nevytvářejí (plán vzniká až ve writing-plans po aktivaci). Struktura draftu odpovídá design dokumentu (Cíl / Scope / Technický návrh …), ne struktuře plánu. Aktivace (přesun `next/` → `active/`) přesouvá design draft, který brainstorming použije jako seed a dopracuje. Legacy drafty `proposal_<slug>.md` v `next/` zůstávají platné (grandfather; při aktivaci se konvertují, viz výše).

**`epic-graph.ps1` — přesná pravidla parsování:** ze stemu souboru se odstraňuje **právě jeden** prefix dle `^(design_|plan_|proposal_)`; suffix `-design$` se odstraňuje **pouze** po prefixu `proposal_` (legacy). Tím `design_x.md` → slug `x`, zatímco legacy `proposal_design_x.md` → slug `design_x` — žádné chybné sloučení uzlů. Kontrola 6b (odkaz na neexistující proposal) aplikuje nové prefixy jen na cesty pod adresářem `proposals/` — jinak by falešně hlásila běžné dokumenty typu `docs/design_*.md` odkazované z tiketů. JIRA-less režim (`-Source Proposals`) parsuje oba styly; přibude fixture s novým stylem pojmenování.

### 2. Nový skill `mb-architect-review`

Posouzení designu **živým architektem** zprostředkované Jira tiketem. Tři režimy podle role; mechanika Bitbucket odkazů se nereplikuje — referencuje se `mb-jira-update` §5–7 (stejný vzor jako v `mb-epic-elaboration`).

**Vyvolání a detekce režimu.** Uživatel skill vyvolá explicitně s volitelným číslem tiketu (`/mb-architect-review [UMS-XXXX]`) nebo přirozenou frází („Předej návrh UMS-XXXX architektovi", „Posuď návrh v UMS-XXXX", „Převezmi UMS-XXXX po design review"); description skillu nese české i anglické trigger fráze, aby fungovaly i harnessy bez slash formy (Codex, Gemini, Kilocode). Režim uživatel nejmenuje — skill ho určí sám, v tomto pořadí:

1. Explicitní slovo v promptu: „posuď/review" → respond; „převezmi/pokračuj" → resume; „předej" → request.
2. Deterministicky z Jiry: načte tiket a identitu přihlášeného uživatele (`atlassianUserInfo`), porovná s assignee a s původním řešitelem z request komentáře — tiket není v „Design Review" → request (je-li aktivní work item se schváleným designem); tiket v „Design Review" a volající je assignee ≠ původní řešitel → respond; volající je původní řešitel → resume.
3. Nerozhodnutelné (identita nedostupná, stavy si odporují) → jedna otázka s nabídkou režimů; nikdy tichá volba.

Bez zadaného tiketu skill čte tiket z `context.md` aktuální větve (typický request ze stejné session); se zadaným tiketem je prvním krokem branch sync (viz níže).

**Princip předání: stav žije v tiketové větvi.** Interakce nad tiketem probíhá na větvi příslušející tiketu; při každém předání práce kolegovi (request i respond) je aktuální stav commitnutý a **pushnutý na origin**. Design dokument, `context.md` i případné poznámky jsou tak vždy dostupné oběma stranám i Bitbucket odkazům.

**Push policy: žádný push bez explicitního schválení uživatelem** (v repu platí obecné omezení pushování — mj. `mb-git-commit` má zákaz push). Skill push nikdy neprovádí mlčky: vždy ho nabídne s uvedením větve a commitů, které odejdou, a čeká na souhlas. Odmítnutí = STOP předání (bez pushe je handoff nefunkční). Kroky jsou uspořádány tak, aby jedno předání vyžadovalo právě jeden push, tedy jedno schválení.

**Branch sync (společný první krok respond i resume):** uživatel zadá číslo tiketu v úvodním promptu session a skill repo sám přepne a aktualizuje na správnou větev:

1. Rozlišení větve podle tiketu — v pořadí: název větve z request komentáře v tiketu (autoritativní) → hledání remote větví obsahujících kód tiketu v názvu (`git ls-remote --heads origin`, case-insensitive) → dotaz na uživatele. Více kandidátů bez jasné shody = dotaz, nikdy tichá volba.
2. Kontrola čistého working tree — necommitnuté změny = STOP a report (žádný automatický stash).
3. `git fetch origin` + checkout tiketové větve a fast-forward na stav origin; existuje-li lokální větev a divergovala, STOP a report.

Teprve po branch syncu se čte `context.md` a design dokument — obojí žije na tiketové větvi.

**Režim `request`** (řešitel → architekt; volán z brainstorming overlaye po schválení spec, lze i standalone):

1. Preconditions (fail-closed): `context.md` obsahuje Jira tiket a slug; design polovina aktivního work itemu existuje v `<PLAN_MB>/proposals/active/` — **v libovolném stylu** (`design_<slug>.md` i legacy `proposal_<slug>-design.md`). Design musí být commitnutý — SHA stabilizace per `mb-jira-update` §5–6 (nekomitnutý design → potvrzený lokální commit, jinak STOP).
2. Je-li práce dosud na default větvi, vytvoření tiketové větve (branch-in-place). Doporučená konvence: název tiketové větve obsahuje kód tiketu (např. `feature/ums-3302-toast-reconcile`) — usnadňuje branch sync podle čísla tiketu na straně architekta i při resume.
3. Zapíše do `context.md` (`## Active Work`) řádek `- **Review:** design-review requested YYYY-MM-DD` a commitne (součást předání stavu ve větvi; commit dle `mb-git-commit` konvencí).
4. **Push tiketové větve (fail-closed, s explicitním schválením):** pinovaný commit designu musí být dosažitelný na origin. Skill nabídne push větve (uvede větev a odchozí commity) a čeká na souhlas uživatele; při odmítnutí STOP — bez pushe je předání nefunkční (mrtvý Bitbucket odkaz, architekt se k designu nedostane). Jediný push pokrývá design i `context.md` z kroku 3.
5. Do tiketu publikuje český komentář: stručné shrnutí návrhu (Cíl / Scope / klíčová rozhodnutí / rizika, cca 10–15 řádek), commit-pinned Bitbucket odkaz na design (per §7), **název tiketové větve** a **původního řešitele** (accountId + displayName — obojí potřebuje režim respond). Zároveň refresh řádku `**Návrh (design):**` v popisu tiketu (§7b).
6. Výběr architekta: skill načte assignovatelné uživatele projektu, nabídne uživateli výběr (jedna otázka), zvoleného nastaví jako assignee.
7. Přechod tiketu do stavu **„Design Review"** (fail-closed: chybí-li přechod, STOP s pokynem k založení stavu).
8. Append řádku do pole **AgentSessions** (customfield_11248): `YYYY-MM-DD <harness> <session-id> — design review request (<tiket>)`. Session ID se zjišťuje best-effort z harnessu; nelze-li zjistit, řádek bez ID + upozornění uživateli. Je-li pole nedostupné/zamčené, fallback: totéž jako součást komentáře z kroku 5.
9. Oznámení (česky): předáno na design review; pokračování po vrácení tiketu režimem resume, ideálně v původní session. **Workflow se zde zastavuje — writing-plans se nespouští.** `context.md` zůstává připnutý (work item je nadále aktivní; two-actives guard vědomě blokuje jinou práci v repu po dobu review — záměrné omezení, dokumentované v kontraktu).

**Režim `respond`** (architekt, jiná agentská session, typicky jiný klon repa):

1. Vstup: klíč tiketu (z úvodního promptu uživatele). Tiket musí být ve stavu „Design Review".
2. Načte tiket (popis, komentář requestu). Chybí-li request komentář (architekt byl přiřazen ručně mimo skill), fail-closed: zeptá se uživatele na návratového řešitele a větev.
3. **Branch sync** (viz výše) — repo přepne a aktualizuje na tiketovou větev; design dokument a MB kontext cílového projektu (`brief.md`, `architecture.md`, `tech.md`) čte z ní.
4. Provede architekta strukturovaným posouzením (cíl a přiměřenost scope, technický návrh, dopady, rizika, alternativy); poznámky pomůže formulovat.
5. Publikuje poznámky jako český komentář, nastaví assignee zpět na původního řešitele a **nastaví vlajku** (Flagged/Impediment). Stav tiketu se nemění — zůstává „Design Review". Vlajka odpovídá týmové konvenci „práce vrácena, věnuj se tomu" (stejně ji používá tester při vrácení chyby vývojáři). Vznikly-li na tiketové větvi commity (poznámky/úpravy), pushne je před předáním — opět jen s explicitním schválením uživatele (push policy výše).

**Režim `resume`** (řešitel přebírá zpět):

1. Vstup: klíč tiketu z úvodního promptu uživatele (je-li repo už na tiketové větvi, postačí tiket z `context.md`). Očekává stav „Design Review" + vlajku; chybí-li vlajka (architekt zřejmě odpověděl ručně v Jiře), pokračuje po potvrzení uživatelem, nikoli hard-stop.
2. **Branch sync** (viz výše) — repo přepne a aktualizuje na tiketovou větev (architekt mohl pushnout); teprve pak čte `context.md` a poznámky architekta z komentářů, které shrne uživateli.
3. Přechod tiketu do **„In Progress"**, vymazání vlajky, odstranění řádku `Review:` z `context.md`.
4. Pokračování dle kontextu: úpravy designu podle poznámek (brainstorming dialog nad body architekta) → po odsouhlasení writing-plans. Funguje jak v obnovené session (`--resume <session-id>` dle AgentSessions), tak v čerstvé session (`context.md` je stále připnutý).

**Fail-closed pokračování během review:** dokud je v `context.md` řádek `Review: design-review requested`, pokračování workflow (writing-plans a dál) je blokováno — správná cesta je režim resume. `mb-state` tento stav reportuje („čeká na design review u architekta"). Discard/abort cesta (`mb-abort`, finishing Discard) při tiketu ve stavu „Design Review" navíc nabídne úklid Jiry: přechod zpět, vrácení assignee, smazání vlajky — jinak by architektovi zůstal živý úkol na mrtvé práci.

**Model:** kompozice shrnutí je summarizační práce — při delegování běží na nejlevnějším schopném tieru (Dispatch Model Policy). Režimy respond/resume jsou interaktivní, model neřeší.

### 3. Brainstorming overlay — Architect Review Gate

Doplnění overlaye (`brainstorming.overlay.md`): po kroku 8 (uživatel schválil spec), **pokud je navázán Jira tiket**, agent VŽDY nabídne design review — s vlastním doporučením ano/ne podle kritérií netriviálnosti:

- nová komponenta nebo služba,
- zásah do architektury či veřejných kontraktů/rozhraní,
- cross-project dopad (více Memory Bank),
- databázová migrace,
- bezpečnostní dopad.

Přijetí → invoke `mb-architect-review` (request) a konec workflow session (čeká se na architekta). Odmítnutí → normálně krok 9 (writing-plans). Bez Jira tiketu se nabídka nepokládá.

Upstream brainstorming dvakrát deklaruje „the ONLY skill you invoke after brainstorming is writing-plans" — overlay musí toto terminal-state pravidlo **explicitně amendovat**: v tomto repozitáři smí mezi krokem 8 a 9 vstoupit `mb-architect-review`; writing-plans zůstává jediným *implementačním* následníkem. Bez explicitního amendmentu hrozí, že agent pod tlakem silnější upstream instrukce gate přeskočí.

### 4. Finishing overlay + `mb-jira-update`

**Refresh developu (overlay Step 4.5, volba Option 1 — Merge locally):** před mergem agent položí otázku: „Aktualizovat lokální `develop` z `origin/develop`? (fetch + fast-forward, žádný push)". Souhlas → `git fetch origin` a fast-forward update lokální `develop`; není-li FF možný (divergence), STOP a report — žádné automatické řešení konfliktu. Neexistuje-li lokální `develop`, vytvoří se tracking větev z `origin/develop`. Poté standardní `--no-ff` merge feature větve. **Odpověď z tohoto kroku nahrazuje upstream `git pull` v kroku 5 Option 1** — overlay to musí říct explicitně, jinak by upstream instrukce odmítnutý refresh tiše přebila (a při divergenci provedla nechtěný pull-merge).

**Finalizační režim `mb-jira-update`:** finishing overlay vyvolá `mb-jira-update` ve finalizačním režimu **pouze u volby Option 1 (Merge Locally), až po úspěšném merge a verifikaci**, a jen je-li navázán Jira tiket. Po úspěšné publikaci komentáře skill provede přechod tiketu přímo do stavu **„Test"** (stav „Review" se přeskakuje) a smaže případnou vlajku (např. po ručně přeskočeném resume). Volby Option 2 (Push + PR) a Option 3 (Keep As-Is) stav tiketu nemění — integrace ještě neproběhla. Samostatné vyvolání `mb-jira-update` (průběžný status uprostřed práce) stav tiketu nemění — dnešní chování. Chybějící přechod „Test" = upozornění, komentář zůstává publikován (přechod není důvod k rollbacku).

### 5. Kontrakt a dokumentace

- **`UMS_MEMORY_BANK_CONTRACT.md`:** sekce „Active Proposal Pair" se přejmenuje na „Active Work Item (design + plan pair)" a přepíše na novou konvenci s rozšířenou grandfather clause; sekce „Preliminary proposals (`next/`)" nově definuje draft jako `design_<slug>.md` (bez předběžného plánu); aktualizace tabulky Superpowers Document Placement, discovery globů, Harvest Contract §4 a schématu `context.md` (`Work item` + volitelný `Review` řádek; seznam povolených writerů se rozšiřuje o `mb-architect-review`). Nová sekce **„Architect Review Gate"**: princip „stav žije v tiketové větvi" (push při předání vždy s explicitním schválením uživatele, branch sync podle čísla tiketu na začátku respond/resume), životní cyklus request → respond → resume, jmenné konvence Jira (stavy „Design Review" / „In Progress" / „Test", vlajka Flagged dle týmové konvence „vráceno, věnuj se tomu", formát AgentSessions), fail-closed pravidla včetně blokace pokračování při otevřeném review a úklidu Jiry na discard/abort cestě.
- **`CLAUDE.md.sample`:** bullet umístění dokumentů přejde na `design_`/`plan_`; nový bullet Architect Review Gate (nabídka po brainstormingu); bullet dokončení větve doplní develop refresh a přechod do „Test".
- **`ums/README.md`** a **`SKILLS_MANIFEST.md`:** nový skill, aktualizované workflow schéma a terminologie.

## Dopady

- Nové soubory: `ums/.claude/skills/mb-architect-review/SKILL.md`; fixture pro nový styl v `mb-epic-graph/tests/`.
- Změněné soubory: kontrakt, 2 overlaye (brainstorming, finishing), 11 skillů (`mb-harvest`, `mb-jira-update`, `mb-state`, `mb-abort`, `mb-scan`, `mb-sync`, `mb-init`, `mb-git-commit` — staging policy jmenuje archivní soubory, `mb-git-message`, `mb-epic-elaboration`+protocol, `mb-epic-graph`+ps1) + deprecated stuby `mb-act`/`mb-plan` (citují `proposal_<slug>` cesty), `CLAUDE.md.sample`, `README.md`, `SKILLS_MANIFEST.md`.
- Vygenerované overlay bloky ve vendorovaných skillech se po úpravě `*.overlay.md` přegenerují revendor skriptem (v monorepu); ve forku se upraví přímo `.overlay.md` zdroje.
- Existující Memory Bank v monorepu: žádná migrace — legacy dokumenty zůstávají, nové vznikají v novém stylu.

## Rizika

| Riziko | Mitigace |
|---|---|
| Stav „Design Review" ve workflow UMS zatím neexistuje | Prerekvizita (viz níže); skill je fail-closed — bez přechodu se zastaví s instrukcí |
| Pole AgentSessions může být vyhrazeno (Rovo?) | Ověření vlastnictví v administraci; fallback = session řádek v komentáři |
| Session ID nemusí být v každém harnessu zjistitelné | Best-effort + degradace (řádek bez ID, upozornění); resume funguje i z čerstvé session přes `context.md` |
| `epic-graph.ps1` parsuje názvy souborů — regrese při rozšíření prefixů | Pevná strip-rule (jeden prefix, `-design$` jen po `proposal_`), scoping kontroly 6b na `proposals/`, nová fixture + průchod stávajících testů pro oba styly |
| Smíšené styly v jednom `active/` (legacy + nový) | Pravidlo „jeden work item = jeden styl"; aktivace legacy draftu konvertuje do nového stylu |
| Divergence lokálního `develop` při FF refreshi | STOP a report, řešení je na uživateli |
| Předání bez pushe = mrtvý odkaz a nedostupný design | Request fail-closed vyžaduje dosažitelnost commitu na origin (nabídne push tiketové větve) |
| Obecné omezení pushování v repu | Push policy: každý push jen s explicitním schválením uživatele (uvedena větev + commity); jedno předání = jeden push = jedno schválení |
| Two-actives guard blokuje jinou práci po dobu review | Záměrné, dokumentované omezení; nouzově `mb-abort` (s úklidem Jiry) |
| Upstream „ONLY writing-plans" instrukce přebije review gate | Overlay explicitně amenduje terminal-state pravidlo brainstormingu |
| Pokračování workflow při otevřeném review | Řádek `Review:` v `context.md` blokuje writing-plans fail-closed; `mb-state` stav reportuje |
| Branch sync nad špinavým worktree / divergentní lokální větví / více kandidáty | Fail-closed: STOP a report (žádný stash), FF-only aktualizace, při nejednoznačnosti dotaz na uživatele |

## Prerekvizity (administrace Jira, mimo kód)

1. Založit stav **„Design Review"** (kategorie In Progress) a přidat do workflow projektu UMS; na kanban boardu namapovat do sdíleného sloupce se stavem „Review" (projekt je company-managed — mapování více stavů do sloupce je podporováno).
2. Ověřit vlastnictví custom pole **AgentSessions** (customfield_11248, typ Paragraph, aktuálně prázdné napříč instancí) — je-li volné, používá se pro session záznamy; jinak platí fallback do komentáře.
