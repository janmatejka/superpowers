# Brief

## Co to je

Fork `janmatejka/superpowers` ([GitHub](https://github.com/janmatejka/superpowers)),
ve kterém se **vyvíjí a redistribuuje integrační vrstva UMS Memory Bank v2 nad
projektem Superpowers** (upstream `obra/superpowers`, v tomto repu remote
`vanila`).

Superpowers je knihovna skillů pro kódovací agenty (Claude Code, Codex, Cursor,
Gemini CLI, Copilot CLI, Kimi, OpenCode, Pi, Devin CLI, Hermes Agent, Qwen Code,
Factory Droid, Grok Build, Antigravity, Muse) — řídí pracovní postup
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

Výjimky mimo `ums/` na větvi `ums-memory-bank`: [CLAUDE.md](../CLAUDE.md)
forku a tato Memory Bank ([memory-bank/](.)). Obojí jsou soubory, které
v upstreamu neexistují, takže merge zůstává bezkonfliktní. `CLAUDE.md` je
fork-vlastní — upstream ho smazal, aby Claude Code četl `AGENTS.md`, takže fork
nese první řádek `@AGENTS.md` (import upstream návodů) a za ním blok
„Integrace s UMS Memory Bank".

Historie: vrstva v5 je archivovaná v tagu `archive/mb-integrace-v5-era`, větev
`origin/mb-integrace` je obsoletní.

## Klíčové adresáře

| Cesta | Role |
|---|---|
| [`skills/`](../skills/) | Upstream skill pack (15 skillů, z nich 14 se vendoruje; `diagnosing-superpowers` je vyloučený). Na této větvi se needituje. |
| [`ums/`](../ums/) | UMS vrstva — master kopie, jediné místo pro změny na této větvi; do monorepa, profilu i kořene forku se nasazuje skriptem. |
| [`ums/.claude/skills/shared/`](../ums/.claude/skills/shared/) | Normativní zdroj vrstvy: kontrakt v3.2, manifest, vendor pin, overlay fragmenty. |
| [`ums/.claude/skills/mb-*/`](../ums/.claude/skills/) | Utility skilly Memory Bank (18 aktivních + 2 deprecated stuby). |
| [`memory-bank/`](.) | Memory Bank tohoto repozitáře — orchestrační kořen (`CTX_DIR`) i cílová MB (`PLAN_MB`). |
| `.claude/`, `.agents/` | Netrackovaná **nasazení** vrstvy pro práci v tomto repu, vyrábí je `sync-with-monorepo.ps1 -Scope Fork` (viz [architecture.md](architecture.md), postup v [playbook.md](playbook.md)). |
| [`hooks/`](../hooks/), [`tests/`](../tests/), [`docs/`](../docs/) | Upstream infrastruktura (bootstrap hooky, testy, dokumentace portování). |

## Pro koho a hodnota

Uživatelem UMS vrstvy je **vývojář (řešitel) a architekt pracující v monorepu
UMS** s kódovacím agentem. Vrstva jim dává:

- **Trvalou znalost projektu** — Memory Bank dokumenty (`brief.md`,
  `architecture.md`, `tech.md`, u projektů s vlastními postupy i `playbook.md`,
  který dědí pravidla po stromu Memory Bank, takže sezení v projektu čte
  i podstromová pravidla svých předků) popisují aktuální stav a agent je čte
  před každým návrhem. Znalost tedy nezaniká s koncem sezení.
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
kontext návrhu; návrh se uloží jako `design_<slug>.md` do `proposals/active/`;
po schválení návrhu se nabídne nezávislá agentická oponentura (nejsilnější
model s čistým kontextem, nálezy s evidencí, sporné body dávkovým dialogem)
a s navázaným tiketem se vždy nabídne design review živým architektem
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
a Jira linky hlídá orákulum ve `mb-epic-graph`. Uzávěrka okna pak nabízí
**pool** (`mb-epic-run`): stav slotů, obě orákula připravenosti na jednom
místě a strojově ověřené spuštění sezení na vybraný tiket do volného slotu —
uživatel dřív tuto mechaniku dělal ručně a tři z pěti pokusů selhaly
mechanicky, aniž to bylo poznat na první pohled.

Práce rozjetých tiketů se skládá dohromady na **epikové lince**
(`epic/<KLÍČ>`, kódová integrační větev epiku) — vzniká, jen když tikety
epiku nejsou samostatně dodatelné do sdílené větve. Linie je **nechráněná
větev** rozpoznaná vzorem `epicBranchPattern` (výchozí `epic/*`): zakládá ji
`mb-epic-run spawn` při prvním rozjetí tiketu a fast-forward do ní pushuje
tiketové sezení samo, až když mu správce epiku (sezení držící elaborační
větev) po kontrole předání odpoví `go`. Lidské zůstává jen to, co je dnem
kontraktu: výstup epiku do dodávkové linie a smazání linie po výstupu.
Tiketové sezení a správce prochází stejnou integrační procedurou jako práce
mimo epik, liší se jen v tom, komu se předání adresuje. Každá zpráva mezi
správcem a tiketovým sezením vyžaduje odpověď v obou směrech (výjimkou je
oznámení o vlastním ověřitelném úkonu); čekání dělá viditelným outbox správce
a blok `NOW` tiketu. Konflikty mezi sousedními tikety a nálezy, které patří
jednomu tiketu, ale mění cizí rozhodnutí, řeší mechanický registr rozhodnutí
v ledgeru epiku a eskalační tabulka se třemi úrovněmi autonomie — ne paměť
správce (mechanika viz [architecture.md](architecture.md), sekce 3 a 6).

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
— z forku (master kopie) do monorepa (výchozí), do profilu uživatele nebo do
kořene samotného forku (`-Scope Fork`), pro 15 harnessů, které Superpowers
podporuje; nasazuje i vendorované skilly s overlayi a chrání cíl před tichým
přepsáním ruční změny. Cílové cesty a mechanismy markeru per harness jsou v
[tech.md](tech.md), pipeline v [architecture.md](architecture.md) (sekce 7),
parametry, směry a to, co se kam záměrně nenasazuje, popisuje
[playbook.md](playbook.md).

## Co vrstva záměrně nedělá

- **Nepřipíná modely.** Volbu modelu řídí Superpowers (sekce Model Selection
  ve `subagent-driven-development`). UMS přidává jedinou pojistku: čistě
  summarizační a read-only dispatche běží na nejlevnějším tieru.
- **Neřídí exekuci.** Životní cyklus vlastní Superpowers workflow; v1 skilly
  `mb-plan` a `mb-act` jsou jen přesměrovací stuby.
- **Nepoužívá agentem vytvářené git worktrees.** Izolace se řeší větví na
  místě; zákaz stojí na modelu (jedna session na workspace, žádný workspace,
  který si session provizovala sama), ne na velikosti disku — dřívější
  měření, které zákaz zdůvodňovalo diskem, bylo vyvráceno (kontrakt,
  Worktree Policy). Jedinou výjimkou je **slot poolu** — linked worktree,
  který založí a označí uživatel a který slouží ke strojově ověřenému
  rozjezdu sezení na tiket (`mb-epic-run`, viz [architecture.md](architecture.md)
  sekce 6).
- **Nikdy netlačí do sdílené větve bez souhlasu.** Chráněné větve (v tomto
  repu `ums-memory-bank`, `main`, `master`, `develop`, `release/*`,
  `Branches/*` — konfigurovatelné v `ums-repo.json`, jinak vestavěný fallback
  `develop`/`main`/`master`/`release/*`) agent svým vlastním tool-callem
  nepushuje nikdy — připraví příkaz a čeká na uživatele (lidská úniková cesta
  `MB_HUMAN_PUSH=1`). Vlastní tiketovou větev agent pushuje sám po každém
  commitu, ale vždy ohlásí branch a commity; nechráněnou epikovou linii smí
  fast-forwardovat tiketové sezení po `go` správce epiku; force push a mazání
  větve jsou zakázané vždy.
  Vynucuje to git `pre-push` hook, ale jen uvnitř agentní relace — mimo ni
  nevynucuje nic vlastního; kdo agentovým tool-callem sahá na chráněnou větev
  nebo na únikovou proměnnou, hlídá navíc PreToolUse guard
  `guard-git-push.mjs` (viz [architecture.md](architecture.md), sekce
  Publikace a viditelnost napříč větvemi). Ne `permissions.deny`.

## Vztah k monorepu UMS

Master kopie vrstvy je adresář `ums/` v tomto forku. Monorepo UMS
(`d:\_datasys\ums`, Bitbucket `datasyscz/ums`) je její **nasazená kopie** v jeho
`.claude/` a `CLAUDE.md` (v `CLAUDE.md` skript spravuje jen blok mezi markery,
projektová pravidla monorepa nechává být). Nasazuje se skriptem
[`sync-with-monorepo.ps1`](../ums/sync-with-monorepo.ps1); změny udělané v
monorepu se táhnou zpět vědomě (`-Direction FromMonorepo`, jen pro `claude` +
`Monorepo`, vendorované skilly nikdy).

Monorepo má vlastní Memory Bank (`d:\_datasys\ums\memory-bank\`) pro produkt
UMS; s touto Memory Bank se nemíchá — tato dokumentuje **vývoj vrstvy**, ta
druhá **produkt, na kterém se vrstva používá**.

## Stav

Vrstva je v provozu (kontrakt v3.2, vendor pin upstream v6.4.2), s playbookem
jako stromem podle hierarchie Memory Bank (dvě části podle dosahu, rozpočet
a ráčna jako eskalační práh místo tvrdého limitu, harvestová brána v2
a konsolidační skill `mb-playbook-consolidate`). Práce na této větvi má přes
100 commitů nad `main`; poslední dokončené položky jsou v
[proposals/completed/](proposals/completed/).
