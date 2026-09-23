# UMS Memory Bank — Skills Manifest

## Přehled

Skill pack MB v2: Superpowers (vendorované, v6.3.0) řídí workflow, Memory Bank
je dokumentová/znalostní vrstva. Normativní pravidla: [kontrakt 3.1](UMS_MEMORY_BANK_CONTRACT.md).

## Sdílené prostředky

| Prostředek | Cesta | Popis |
|---|---|---|
| Kontrakt 3.1 (jádro) | [shared/UMS_MEMORY_BANK_CONTRACT.md](UMS_MEMORY_BANK_CONTRACT.md) | MB_ROOT, sada dokumentů, vlastnictví faktu, work item (design+plan pár) a jeho granularita, způsobilost sezení, publikace, message protocol, eskalace, fail-closed, Phase Map a citační forma — jediné, co nese `Contract-Version`; rozpočet řádků vynucuje `tests/contract-shape.tests.ps1` |
| Kontrakt 3.1 (reference) | [shared/contract/](contract/) | 17 per-tématických referencí vyňatých z jádra (Target-MB discovery, Repository Configuration, Workspace Discipline, Session Intent Baton, Playbook Contract, Harvest Contract, Integration & Abandon + Publication mechanics, epic-line, epic-backflow, worktree-pool, now-block, message-protocol, escalation, architect-review, cross-branch-visibility, brainstorming-paths, jira); načítá je vlastnící skill podle `Phase Map` v jádře, citovat jako `(contract/<soubor>.md, "Sekce")` |
| Doklad ke kontraktu | [shared/contract/doklad/](contract/doklad/) | Evidenční vrstva (měření, historie rozhodnutí, zdůvodnění) vyňatá z jádra a referencí; čte se na vyžádání a nikdy se necituje jako normativní zdroj |
| Changelog kontraktu | [shared/CHANGELOG.md](CHANGELOG.md) | Historie verzí kontraktu (v1 → v2 → 3.0); jediný domov per-verzní historie, jádro nese jen `Contract-Version` |
| Vendor pin | [shared/VENDORED_FROM.md](VENDORED_FROM.md) | Upstream tag/commit vendorovaných superpowers skillů a re-vendor postup |
| Overlay fragmenty | [shared/overlays/](overlays/README.md) | UMS bloky aplikované do vendorovaných skillů |

## Sdílené skripty a sady

| Skript | Cesta | Popis |
|---|---|---|
| Zachování řádků při přesunu | [shared/scripts/Test-UmsContractMove.ps1](scripts/Test-UmsContractMove.ps1) | Multimnožinové srovnání neprázdných řádků před a po přesunu kontraktu (`Compare-UmsLineMultiset`) |
| Permalink | [shared/scripts/Get-UmsPermalink.ps1](scripts/Get-UmsPermalink.ps1) | Jediný domov tvaru permalinku: z `permalinkTemplate`, jinak odvozený z hostu `origin` |
| Kontrola popisu tiketu | [shared/scripts/Test-UmsJiraDescription.ps1](scripts/Test-UmsJiraDescription.ps1) | Rozpočet, odkazy, tučné, sekce — před zápisem do Jiry |
| Konfigurace repa | [shared/scripts/Get-UmsRepoConfig.ps1](scripts/Get-UmsRepoConfig.ps1) | Čtení `ums-repo.json` včetně klíče `permalinkTemplate` |
| Injektáž jádra | [hooks/contract-inject.ps1](../../hooks/contract-inject.ps1) | Vloží jádro kontraktu do kontextu při startu sezení a s prvním promptem po kompaktaci (marker `.superpowers/contract-reload.flag`); registrován v `settings.json` |
| Sady vrstvy | `shared/tests/*.tests.ps1`, `hooks/tests/*.tests.ps1`, `mb-*/tests/*.tests.ps1` | Bezzávislostní `.ps1` sady s vlastním `_assert.ps1`; nové v 3.0: `contract-move`, `contract-shape`, `permalink`, `jira-description`, `contract-inject` |

## Vendorované Superpowers skilly (v6.3.0)

14 skillů vendorovaných z obra/superpowers — viz `VENDORED_FROM.md`.
UMS overlay bloky mají přesně 4: `brainstorming`, `subagent-driven-development`,
`finishing-a-development-branch` a `writing-plans`. Ostatní jsou byte-identické s upstreamem.

## Aktivní mb-* skilly

| Skill | Soubor | Popis |
|---|---|---|
| mb-harvest | [mb-harvest/SKILL.md](../mb-harvest/SKILL.md) | Harvest znalostí do MB, archivace proposal páru, reset context.md (volán z finishing) |
| mb-abort | [mb-abort/SKILL.md](../mb-abort/SKILL.md) | Zrušení aktivní práce (pár → abandoned/, reset context.md) |
| mb-park | [mb-park/SKILL.md](../mb-park/SKILL.md) | Odložení rozpracované práce: commit, publikace, commit kandidátů playbooku; pár zůstává v `active/` a `context.md` v ACTIVE |
| mb-init | [mb-init/SKILL.md](../mb-init/SKILL.md) | Inicializace memory-bank/ struktury (CTX_DIR nebo projektová MB) |
| mb-state | [mb-state/SKILL.md](../mb-state/SKILL.md) | Read-only stav workflow i workspace: pin, slug, úplnost páru, staleness + způsobilost workspace (pre-push hook, konfigurace repa), zbytky, zaparkovaná práce na jiných větvích, vzdálenost od báze |
| mb-scan | [mb-scan/SKILL.md](../mb-scan/SKILL.md) | Read-only hloubková analýza projektu |
| mb-sync | [mb-sync/SKILL.md](../mb-sync/SKILL.md) | Synchronizace MB dokumentů s realitou kódu |
| mb-git-message | [mb-git-message/SKILL.md](../mb-git-message/SKILL.md) | Návrh commit message (bez commitu) |
| mb-git-commit | [mb-git-commit/SKILL.md](../mb-git-commit/SKILL.md) | Scoped commit (nikdy push) |
| mb-jira-update | [mb-jira-update/SKILL.md](../mb-jira-update/SKILL.md) | České shrnutí implementace do Jira |
| mb-epic-elaboration | [mb-epic-elaboration/SKILL.md](../mb-epic-elaboration/SKILL.md) | Iterativní rozpracování epiku po ohraničených oknech (evidence ledger, dirty-set, invarianty; preliminary proposaly v `next/`) |
| mb-epic-graph | [mb-epic-graph/SKILL.md](../mb-epic-graph/SKILL.md) | Generovaný graf závislostí epiku z Jira linků + konzistenční orákulum prose ↔ linky (read-only skript) |
| mb-doc-index | [mb-doc-index/SKILL.md](../mb-doc-index/SKILL.md) | Read-only index dokumentů napříč větvemi origin (model tahu) + kolizní findings pro discovery |
| mb-epic-run | [mb-epic-run/SKILL.md](../mb-epic-run/SKILL.md) | Mechanika poolu: stav slotů (derivovaný, per-worktree), obě orákula připravenosti na jednom místě, spuštění sezení na tiket do volného slotu se strojovým ověřením, a dohledání slotu, který tiket drží |
| mb-architect-review | [mb-architect-review/SKILL.md](../mb-architect-review/SKILL.md) | Design review živým architektem přes Jira tiket (request/respond/resume, branch sync dle tiketu, publikace větve dle Publication Contract) |
| mb-migrate-docs | [mb-migrate-docs/SKILL.md](../mb-migrate-docs/SKILL.md) | Migrace MB dokumentů na aktuální sadu (product.md → brief.md, tasks.md → playbook.md; mechanická fáze + mazací agent pod verifikátorem) |
| mb-link-audit | [mb-link-audit/SKILL.md](../mb-link-audit/SKILL.md) | Kontrola a konsolidace odkazů v MB dle Link Conventions (kotvy → textové určení sekce, špatná hloubka `../`, zastaralý text odkazu, absolutní cesty; neurčitelné cíle se značkují) |
| mb-playbook-consolidate | [mb-playbook-consolidate/SKILL.md](../mb-playbook-consolidate/SKILL.md) | Konsolidace playbooku jedné MB nebo celého stromu: slučování, vyřazování, převod tvaru, přesuny ve stromu, eskalační report. |

## Odstraněné v1 skilly (MB v1 → v2)

Lifecycle převzalo superpowers workflow; v1 orchestrační skilly byly odstraněny.
Mapování náhrad (pokud někdo zavolá starý název, přesměruj podle tabulky):

| Odstraněný skill | Náhrada |
|---|---|
| mb-plan | brainstorming (Target-MB discovery proběhne v něm) + writing-plans |
| mb-act | subagent-driven-development / executing-plans |
| mb-auto | superpowers workflow (autonomní Ralph-loop zrušen) |
| mb-manual | bez náhrady (Run Mode zrušen) |
| mb-review | spec self-review + user review gate (brainstorming), task-reviewer (SDD) |
| mb-done | finishing-a-development-branch → mb-harvest |
| mb-done-git-commit | finishing-a-development-branch → mb-harvest + commit ve finishing |
