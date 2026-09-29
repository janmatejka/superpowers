@AGENTS.md

<!-- UMS-MEMORY-BANK BEGIN (fork-only section, exists on branch ums-memory-bank; keep at end of file for conflict-free upstream merges) -->

## Integrace s UMS Memory Bank (jen tento fork)

Tento fork (`janmatejka/superpowers`, upstream remote `vanila` = obra/superpowers) nese integraci s UMS Memory Bank v2. S uživatelem komunikuj v této agendě česky.

### Role větví — dodržuj striktně

- **`main`** = čisté read-only zrcadlo upstreamu (fast-forward na `vanila/main`). NIKDY na něj nedávej UMS obsah; slouží jako zdroj vendoringu a pro případné upstream PR.
- **`ums-memory-bank`** = jediná větev s UMS obsahem, VÝHRADNĚ v adresáři `ums/` (aditivní model). Mimo `ums/` na této větvi neměň žádný soubor; tolerované výjimky jsou právě dvě, obě jen nové soubory neexistující v upstreamu: `CLAUDE.md` forku (v upstreamu neexistuje — upstream ho smazal, aby Claude Code četl `AGENTS.md`; první řádek `@AGENTS.md` upstream návody importuje) a `memory-bank/` (Memory Bank tohoto repa). Díky tomu je `git merge vanila/main` vždy bezkonfliktní.
- Stará v5 integrace je archivovaná v tagu `archive/mb-integrace-v5-era`; větev `origin/mb-integrace` je obsoletní.

### Architektura MB v2 (zkráceně)

Superpowers řídí workflow (brainstorming → writing-plans → subagent-driven-development → finishing); Memory Bank je dokumentová vrstva. Pracovní položka = pár `design_<slug>.md` + `plan_<slug>.md` v `<PLAN_MB>/proposals/active/` (starší `proposal_<slug>-design.md` + `proposal_<slug>.md` zůstává platné tam, kde už leží); `context.md` nese jen Jira + Target MB Pin + slug; harvest dělá skill `mb-harvest` z overlay kroku 4.5 ve finishing. Volbu modelu řídí superpowers (SDD Model Selection), UMS nepřipíná modely (jen nejlevnější tier pro summarizaci/read-only — viz Dispatch Model Policy). Přesně 5 overlay bloků (brainstorming, SDD, finishing, writing-plans, executing-plans), každý s hlavičkovým ukazatelem (`*.pointer.overlay.md` — Claude Code po kompaktaci re-injektuje tělo skillu zkrácené na 5 000 tokenů od začátku souboru), generované z `ums/.claude/skills/shared/overlays/*.overlay.md`. Worktrees jsou v UMS zakázané (branch-in-place). Normativní zdroj: `ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md`; detaily a matice kompatibility harness: `ums/README.md`.

### Živé nasazení a synchronizace

- Master kopie vrstvy je tento fork (`ums/`); monorepo `d:\_datasys\ums` a ostatní cíle jsou nasazené kopie. Změna vrstvy se dělá tady a nasazuje se skriptem; změny udělané v monorepu se táhnou zpět vědomě přes `-Direction FromMonorepo`.
- Sync/deploy: `pwsh ums/sync-with-monorepo.ps1` — bez parametrů interaktivní nabídka; výchozí `-Direction ToMonorepo` (fork → cíl); `-Agent` je seznam (čárkou) z 15 harnessů (`claude`, `codex`, `gemini`, `qwen`, `opencode`, `pi`, `hermes`, `cursor`, `copilot`, `devin`, `droid`, `kimi`, `muse`, `antigravity`, `grok`; `kilocode` zrušen), `-Scope Monorepo|UserProfile|Fork`, `-WhatIf`, `-Force`. `FromMonorepo` jen pro claude+Monorepo, jinak jednosměrný deploy. Skript chrání cíl manifestem driftu (exit 3 = ruční změna v cíli, řešení `-Direction FromMonorepo` nebo `-Force`). `settings.json` se na ne-Claude cíle záměrně nenasazuje; glue se merguje bez mazání cizích souborů.
- Upgrade upstreamu: po `git merge vanila/main` zvedni pin ve forku (`revendor-superpowers.ps1 -UmsRoot ums -PinOnly -Tag <nový>`) a nasaď skriptem; změna tagu u cíle trackovaného gitem jsou dva běhy — první skončí exit 4 po vanilla fázi (commit „vanilla sync" v cíli), druhý zrcadlí vrstvu a aplikuje overlaye (commit „overlay"). Anchor-miss overlay fragmentu = detektor driftu upstreamu, ne chyba k obejití. Vendorované soubory v cíli nikdy needituj mimo `<!-- UMS-OVERLAY -->` bloky. Superpowers se v cílech UMS neinstaluje současně jako plugin (skilly by byly dvakrát, jednou bez overlaye).
- Pozor Windows: `git archive` + `core.autocrlf=true` rozbíjí CRLF konverzí bash skripty bez přípony — revendor skript normalizuje na LF; v monorepu platí `.gitattributes: .claude/skills/** text eol=lf`.
- Upstream `.gitignore` ignoruje každý `.claude/` adresář — `ums/.gitignore` s `!.claude/` to aditivně neguje; při přesunech souborů na to nezapomeň.
- Kořenový `.claude/` (a `.agents/skills/`) tohoto forku je netrackovaná **nasazená** kopie vrstvy, kterou sezení používá; autorita je `ums/.claude/`. Po změně zdroje nasazení obnov `pwsh ums/sync-with-monorepo.ps1 -Scope Fork` (bez ruční obnovy; skript zapíše `.git/info/exclude`, nikdy instrukční soubory), jinak pracuješ se starou verzí.

### Memory Bank tohoto repa

`memory-bank/` je Memory Bank vývoje UMS vrstvy — plní současně roli `CTX_DIR` i `PLAN_MB` (práce je repo-wide, `Target MB Pin` míří na `memory-bank/`). [`architecture.md`](memory-bank/architecture.md) mapuje workflow superpowers, pět overlay bodů zásahu UMS, dokumentovou vrstvu (sadu dokumentů, vlastnictví faktu, playbookový konzultační režim) a vendoring/deploy pipeline; [`brief.md`](memory-bank/brief.md) role větví a adresářů; [`tech.md`](memory-bank/tech.md) verze, piny, konfiguraci, inventář hooků a testů a pasti prostředí; [`playbook.md`](memory-bank/playbook.md) postupy — jak testy spustit, jak revendorovat a nasadit vrstvu, instalaci git hooků a konvence pro psaní plánů a commitů. Memory Bank produktu UMS (`d:\_datasys\ums\memory-bank\`) je jiná MB — nemíchat.



## Memory Bank contract

Na začátku práce (a znovu po jakékoli kompaktaci/sumarizaci kontextu) načti a dodržuj kontrakt v [.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md](.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md). Definuje `MB_ROOT` discovery, třívrstvý model adresářů (`CTX_DIR`/`PLAN_MB`/`AFFECTED_MBS`), pár návrh+plán (work item), Target-MB discovery, harvest a fail-closed chování.

## Superpowers × Memory Bank (uživatelské preference)

Superpowers skilly řídí workflow; Memory Bank je dokumentová vrstva. Tyto preference jsou závazné:

- **Umístění dokumentů:** návrhové spec dokumenty ukládej jako `<PLAN_MB>/proposals/active/design_<slug>.md`, implementační plány jako `<PLAN_MB>/proposals/active/plan_<slug>.md`. **Nikdy nezapisuj do `docs/superpowers/` ani `docs/plans/`** (blokováno hookem). `PLAN_MB` = `Target MB Pin` z `memory-bank/context.md`; pokud pin chybí, proveď Target-MB discovery dle kontraktu ještě před zápisem spec.
- **Kontext před návrhem:** před navrhováním přístupů si přečti `brief.md`, `architecture.md`, `tech.md` a `playbook.md` cílové Memory Bank (existující z nich). `playbook.md` je preskriptivní — jeho postupy práci závazně řídí, zbytek je referenční popis stavu.
- **Design review architektem:** po schválení návrhu s navázaným Jira tiketem VŽDY nabídni design review (skill `mb-architect-review`, režim request; doporučení dle netriviálnosti). Vyvolání architektem/řešitelem: `/mb-architect-review [UMS-XXXX]` — skill sám určí režim a přepne repo na tiketovou větev. Dokud je v `context.md` řádek `Review: design-review requested`, writing-plans nespouštěj.
- **Jazyk:** výstupy pro uživatele, proposaly, MB dokumenty, commit messages a Jira komentáře česky; AI-facing instrukce a mezivýstupy subagentů anglicky.
- **Exekuce plánu (SDD):** před dispatchem prvního tasku ověř baseline — postav dotčené projekty a spusť cílené testy na bázi větve; pre-existing rozbití vyřeš/reportuj předem, ne uprostřed tasku. Konflikty, nejasnosti a eskalační body plánu rozhoduj rulingy dle SDD („Rulings, not stalls"): rozhodni, zapiš Ruling do ledgeru, pokračuj a na konci předlož seznam „Rulings I made"; STOP jen pro čtyři eskalační třídy (kontrakt, Fail-Closed Behavior) plus pátou, předávací — rotaci kontextu na hranici tasku — merge báze do vlastní tiketové větve mezi ně nepatří. Bázi merguj výhradně na hranicích fází, nikdy uprostřed tasku; po mergi porovnej příchozí a vlastní cesty a verifikaci podle jejich průniku uživateli **nabídni** — povinná baseline před prvním dispatchem tím zůstává nedotčená.
- **Dokončení větve:** finishing-a-development-branch v tomto repu zahrnuje harvest znalostí skillem `mb-harvest` (viz overlay ve skillu) — bez harvestu se práce neuzavírá. Integrace je fast-forward push tiketové větve do báze — báze je do tiketové větve mergnutá už z hranic fází, takže tiketová větev je jejím potomkem a push je fast-forward. Agent připraví přesný příkaz s výčtem odchozích commitů, `! git push origin HEAD:<baseBranch>`, a spouští ho uživatel; pro tento integrační push je výjimka `MB_HUMAN_PUSH=1` potřeba jen tam, kde není fast-forward na commity už publikované na daném remote — obecně je to ale jediná cesta i kolem zákazu mazání větve a force pushe. Lokální báze se v tiketovém klonu nepoužívá. Když push selže na non-fast-forward, báze se mezitím pohnula — opakuj od `fetch`, strop dvě neúspěšná kola, pak STOP a report uživateli. Po ověřené fast-forward integraci s tiketem spusť mb-jira-update ve finalizačním režimu — tiket jde přímo do „Test". Integrační báze tohoto forku je `ums-memory-bank` a je uvedená mezi chráněnými větvemi v `memory-bank/ums-repo.json`, takže ji agent nikdy nepushuje.
- **Práce na více tiketech:** workspace vybírá a zakládá uživatel; sezení běží v tom workspace, kde daná práce je — jedno sezení na workspace. Odložení rozpracované práce je `mb-park`, ne `mb-abort`. Mezi tikety přepínej jen na hranicích fází a jen s čistým stromem — žádný `git stash`.
- **Volba modelu:** volbu modelu řídí superpowers (SDD sekce Model Selection — škáluje dle složitosti a rizika tasku). UMS nepřipíná modely; jediná pojistka: čistě summarizační/read-only dispatche (commit messages, Jira komenty, harvest notes, read-only scany) běží na nejlevnějším tieru (viz kontrakt, Dispatch Model Policy). Model vždy uváděj u dispatche explicitně.

<!-- UMS-MEMORY-BANK END -->
