# Product

## Komu vrstva slouží

Uživatelem UMS vrstvy je **vývojář (řešitel) a architekt pracující v monorepu
UMS** s kódovacím agentem. Vrstva jim dává:

- **Trvalou znalost projektu** — Memory Bank dokumenty (`brief.md`,
  `product.md`, `architecture.md`, `tech.md`) popisují aktuální stav a agent je
  čte před každým návrhem. Znalost tedy nezaniká s koncem sezení.
- **Auditovatelné pracovní položky** — každá práce má pár návrh + plán
  (`design_<slug>.md` + `plan_<slug>.md`) na známém místě, ne v chatu.
- **Napojení na Jira** — tiket je nosičem stavu: komentáře s implementačním
  souhrnem, přechody stavů, design review mezi řešitelem a architektem.
- **Češtinu na výstupu** — vše, co čte člověk nebo co zůstává v repozitáři
  (návrhy, plány, MB dokumenty, commit messages, Jira komentáře), je česky.
  AI-facing texty (těla skillů, dispatch prompty, task briefy, reporty
  subagentů, SDD ledger) jsou anglicky.

## Jak vypadá práce s vrstvou

1. Uživatel řekne, co chce postavit. Agent spustí `brainstorming`; ten navíc
   vybere a **připne cílovou Memory Bank**, zeptá se na Jira tiket a přečte
   dokumenty cílové MB jako kontext návrhu.
2. Návrh se uloží jako `design_<slug>.md` do `proposals/active/` cílové MB.
   U netriviálních návrhů s tiketem agent nabídne **design review živým
   architektem** — tiket jde do stavu „Design Review" a práce se parkuje.
3. Po schválení vznikne plán (`plan_<slug>.md`) a plán se vykoná
   (`subagent-driven-development`, případně `executing-plans`).
4. Při dokončení větve proběhne **harvest**: znalost se složí do MB dokumentů
   (přítomný čas, aktuální stav — ne changelog), návrh se archivuje do
   `proposals/completed/`, plán se maže, `context.md` se resetuje na IDLE
   a nabídne se aktualizace Jira tiketu.

Uživatel může kdykoli zjistit stav (`mb-state`), zrušit rozpracovanou práci
(`mb-abort`), dosynchronizovat dokumentaci s kódem (`mb-sync`) nebo si nechat
vygenerovat graf závislostí epiku (`mb-epic-graph`).

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
[`ums/README.md`](../ums/README.md#harness-compatibility), technický rozpad
[tech.md](tech.md).

Nasazení k uživateli dělá [`sync-with-monorepo.ps1`](../ums/sync-with-monorepo.ps1):
do monorepa (dvousměrně pro Claude Code) nebo do profilu uživatele
(`-Scope UserProfile`, vždy jednosměrně), pro agenty `claude`, `codex`,
`gemini` a `kilocode`.

## Co vrstva záměrně nedělá

- **Nepřipíná modely.** Volbu modelu řídí Superpowers (sekce Model Selection
  ve `subagent-driven-development`). UMS přidává jedinou pojistku: čistě
  summarizační a read-only dispatche běží na nejlevnějším tieru.
- **Neřídí exekuci.** Životní cyklus vlastní Superpowers workflow; v1 skilly
  `mb-plan` a `mb-act` jsou jen přesměrovací stuby.
- **Nepoužívá git worktrees.** V monorepu UMS jsou zakázané (velikost repa);
  izolace se řeší větví na místě.
- **Nikdy netlačí do remote bez souhlasu.** Push je vždy nabídnut a čeká na
  potvrzení; `git push` je navíc v deny listu.
