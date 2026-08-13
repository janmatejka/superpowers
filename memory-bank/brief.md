# Brief

## Co to je

Fork `janmatejka/superpowers` ([GitHub](https://github.com/janmatejka/superpowers)),
ve kterém se **vyvíjí a redistribuuje integrační vrstva UMS Memory Bank v2 nad
projektem Superpowers** (upstream `obra/superpowers`, v tomto repu remote
`vanila`).

Superpowers je knihovna skillů pro kódovací agenty (Claude Code, Codex, Cursor,
Gemini CLI, Copilot CLI, Kimi, OpenCode, pi, Devin CLI, Hermes Agent) — řídí
pracovní postup
brainstorming → writing-plans → subagent-driven-development → finishing.
UMS vrstva k tomu přidává **dokumentovou a znalostní vrstvu** (Memory Bank),
napojení na Jira a pravidla specifická pro monorepo UMS.

Cílem repozitáře **není** vývoj samotného Superpowers. Upstream se sem jen
zrcadlí, aby z něj šlo vendorovat, a aby se dala UMS vrstva držet aktuální
proti nové upstream verzi.

## Role větví (závazné)

| Větev | Role |
|---|---|
| `main` | Čisté read-only zrcadlo upstreamu — fast-forward na `vanila/main`. Nikdy nenese UMS obsah. Zdroj vendoringu a základna pro případné upstream PR. |
| `ums-memory-bank` | Jediná větev s UMS obsahem, výhradně v adresáři [`ums/`](../ums/) (aditivní model). Díky tomu je `git merge vanila/main` vždy bezkonfliktní. |

Výjimky mimo `ums/` na větvi `ums-memory-bank`: sekce „Integrace s UMS Memory
Bank" na konci [CLAUDE.md](../CLAUDE.md) a tato Memory Bank
([memory-bank/](.)). Obojí jsou nové soubory, které v upstreamu neexistují, takže
merge zůstává bezkonfliktní.

Historie: vrstva v5 je archivovaná v tagu `archive/mb-integrace-v5-era`, větev
`origin/mb-integrace` je obsoletní.

## Klíčové adresáře

| Cesta | Role |
|---|---|
| [`skills/`](../skills/) | Vendorovatelný upstream skill pack (14 skillů). Na této větvi se needituje. |
| [`ums/`](../ums/) | UMS vrstva — zrcadlo živé kopie z monorepa, jediné místo pro změny na této větvi. |
| [`ums/.claude/skills/shared/`](../ums/.claude/skills/shared/) | Normativní zdroj vrstvy: kontrakt v2.9, manifest, vendor pin, overlay fragmenty. |
| [`ums/.claude/skills/mb-*/`](../ums/.claude/skills/) | Utility skilly Memory Bank (14 aktivních + 2 deprecated stuby). |
| [`memory-bank/`](.) | Memory Bank tohoto repozitáře — orchestrační kořen (`CTX_DIR`) i cílová MB (`PLAN_MB`). |
| `.claude/`, `.agents/` | Netrackovaná **nasazení** vrstvy pro práci v tomto repu (viz [architecture.md](architecture.md), obnova v [playbook.md](playbook.md)). |
| [`hooks/`](../hooks/), [`tests/`](../tests/), [`docs/`](../docs/) | Upstream infrastruktura (bootstrap hooky, testy, dokumentace portování). |

## Pro koho a hodnota

Uživatelem UMS vrstvy je **vývojář (řešitel) a architekt pracující v monorepu
UMS** s kódovacím agentem. Vrstva jim dává:

- **Trvalou znalost projektu** — Memory Bank dokumenty (`brief.md`,
  `architecture.md`, `tech.md`, u projektů s vlastními postupy i `playbook.md`)
  popisují aktuální stav a agent je čte před každým návrhem. Znalost tedy
  nezaniká s koncem sezení.
- **Auditovatelné pracovní položky** — každá práce má pár návrh + plán
  (`design_<slug>.md` + `plan_<slug>.md`) na známém místě, ne v chatu.
- **Napojení na Jira** — tiket je nosičem stavu: komentáře s implementačním
  souhrnem, přechody stavů, design review mezi řešitelem a architektem.
- **Spolupráci více aktérů na jednom epiku** — každý pracuje ve svém clonu
  a tiketové větvi; skill `mb-doc-index` řekne, kdo na čem už pracuje (jiná
  větev se stejným slugem nebo tiketem je hlášená chyba, ne tichá kolize) a
  publikační invariant zaručí, že odkaz zapsaný do Jiry vždy odkazuje na
  commit, který na `origin` skutečně existuje.
- **Češtinu na výstupu** — vše, co čte člověk nebo co zůstává v repozitáři
  (návrhy, plány, MB dokumenty, commit messages, Jira komentáře), je česky.
  AI-facing texty (těla skillů, dispatch prompty, task briefy, reporty
  subagentů, SDD ledger) jsou anglicky.

Hlavní tah práce vypadá takto: uživatel řekne, co chce postavit; `brainstorming`
připne cílovou Memory Bank, zeptá se na Jira tiket a přečte její dokumenty jako
kontext návrhu; návrh se uloží jako `design_<slug>.md` do `proposals/active/`
s navázaným tiketem se vždy nabídne design review živým architektem
(netrivialita ovlivňuje jen doporučení agenta, ne to, zda se review nabídne);
po schválení vznikne `plan_<slug>.md` a plán se vykoná
(`subagent-driven-development`, případně `executing-plans`); při dokončení větve
se znalost harvestem složí zpět do MB dokumentů a návrh se archivuje. Mechaniku
jednotlivých kroků popisuje [architecture.md](architecture.md).

Mimo tento tah může uživatel kdykoli zjistit stav (`mb-state`, včetně cizích
větví a kolizí), zrušit rozpracovanou práci (`mb-abort`), dosynchronizovat
dokumentaci s kódem (`mb-sync`), nechat vygenerovat graf závislostí epiku
(`mb-epic-graph`) nebo zjistit, kdo na čem pracuje napříč větvemi
(`mb-doc-index`).

## Rozpracování epiků

Pro velké celky vrstva nabízí iterativní rozpracování epiku
(`mb-epic-elaboration`) po ohraničených lidských „oknech": epic je rozdělením
atomických položek mezi tikety plus grafem závislostí mezi tikety. Předběžné
návrhy budoucích tiketů čekají jako `design_<slug>.md` v `proposals/next/`
a aktivují se, až na tiket dojde řada. Konzistenci mezi textem tiketů, návrhy
a Jira linky hlídá orákulum ve `mb-epic-graph`.

## Podporované harnessy

Obsah vrstvy je přenositelný — kontrakt, `mb-*` skilly, overlay fragmenty
a konvence dokumentů jsou čistý Markdown, takže fungují všude, kde se nahrají
skilly. Nepřenositelné je jen **lepidlo**: injektáž kontraktu na začátku sezení,
mechanické blokování zápisu do zakázaných cest a zákaz worktrees. Ty jsou
plnohodnotné jen v Claude Code; jinde degradují na textové pravidlo
v instrukčním souboru. Detailní matici má
[`ums/README.md`](../ums/README.md), sekce „Harness compatibility“, technický
rozpad [tech.md](tech.md).

Nasazení k uživateli dělá [`sync-with-monorepo.ps1`](../ums/sync-with-monorepo.ps1)
— do monorepa nebo do profilu uživatele, pro agenty `claude`, `codex`, `gemini`
a `kilocode`; parametry, směry a to, co se kam záměrně nenasazuje, popisuje
[playbook.md](playbook.md).

## Co vrstva záměrně nedělá

- **Nepřipíná modely.** Volbu modelu řídí Superpowers (sekce Model Selection
  ve `subagent-driven-development`). UMS přidává jedinou pojistku: čistě
  summarizační a read-only dispatche běží na nejlevnějším tieru.
- **Neřídí exekuci.** Životní cyklus vlastní Superpowers workflow; v1 skilly
  `mb-plan` a `mb-act` jsou jen přesměrovací stuby.
- **Nepoužívá git worktrees.** V monorepu UMS jsou zakázané (velikost repa);
  izolace se řeší větví na místě.
- **Nikdy netlačí do sdílené větve bez souhlasu.** Chráněné větve (v tomto
  repu `ums-memory-bank`, `main`, `master`, `develop`, `release/*`,
  `Branches/*` — konfigurovatelné v `ums-repo.json`, jinak vestavěný fallback
  `develop`/`main`/`master`/`release/*`) agent nepushuje nikdy — připraví
  příkaz a čeká na uživatele (lidská výjimka `UMS_ALLOW_SHARED_PUSH=1`).
  Vlastní tiketovou větev agent pushuje sám po každém commitu, ale vždy
  ohlásí branch a commity; force push je zakázaný vždy. Vynucuje to git
  `pre-push` hook, ne `permissions.deny`.

## Vztah k monorepu UMS

Živá (master) kopie vrstvy je v monorepu UMS (`d:\_datasys\ums`, Bitbucket
`datasyscz/ums`) v jeho `.claude/` a `CLAUDE.md`. Adresář `ums/` v tomto forku
je její **redistribuovatelné zrcadlo** — synchronizuje se skriptem
[`sync-with-monorepo.ps1`](../ums/sync-with-monorepo.ps1).

Monorepo má vlastní Memory Bank (`d:\_datasys\ums\memory-bank\`) pro produkt
UMS; s touto Memory Bank se nemíchá — tato dokumentuje **vývoj vrstvy**, ta
druhá **produkt, na kterém se vrstva používá**.

## Stav

Vrstva je v provozu (kontrakt v2.9, vendor pin upstream v6.3.0). Práce na této
větvi má přes 100 commitů nad `main`; poslední dokončené položky jsou v
[proposals/completed/](proposals/completed/).
