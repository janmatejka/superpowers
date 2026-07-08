# UMS Memory Bank — Skills Manifest

## Přehled

Skill pack MB v2: Superpowers (vendorované, v6.1.1) řídí workflow, Memory Bank
je dokumentová/znalostní vrstva. Normativní pravidla: [kontrakt v2](UMS_MEMORY_BANK_CONTRACT.md).

## Sdílené prostředky

| Prostředek | Cesta | Popis |
|---|---|---|
| Kontrakt v2 | [shared/UMS_MEMORY_BANK_CONTRACT.md](UMS_MEMORY_BANK_CONTRACT.md) | MB_ROOT, proposal pár, Target-MB discovery, harvest, model routing, fail-closed |
| Vendor pin | [shared/VENDORED_FROM.md](VENDORED_FROM.md) | Upstream tag/commit vendorovaných superpowers skillů |
| Overlay fragmenty | [shared/overlays/](overlays/README.md) | UMS bloky aplikované do vendorovaných skillů |

## Vendorované Superpowers skilly (v6.1.1)

14 skillů vendorovaných z obra/superpowers — viz `VENDORED_FROM.md`.
UMS overlay bloky mají přesně 3: `brainstorming`, `subagent-driven-development`,
`finishing-a-development-branch`. Ostatní jsou byte-identické s upstreamem.

## Aktivní mb-* skilly

| Skill | Soubor | Popis |
|---|---|---|
| mb-harvest | [mb-harvest/SKILL.md](../mb-harvest/SKILL.md) | Harvest znalostí do MB, archivace proposal páru, reset context.md (volán z finishing) |
| mb-abort | [mb-abort/SKILL.md](../mb-abort/SKILL.md) | Zrušení aktivní práce (pár → abandoned/, reset context.md) |
| mb-init | [mb-init/SKILL.md](../mb-init/SKILL.md) | Inicializace memory-bank/ struktury (CTX_DIR nebo projektová MB) |
| mb-state | [mb-state/SKILL.md](../mb-state/SKILL.md) | Read-only stav: pin, slug, úplnost páru, staleness |
| mb-scan | [mb-scan/SKILL.md](../mb-scan/SKILL.md) | Read-only hloubková analýza projektu |
| mb-sync | [mb-sync/SKILL.md](../mb-sync/SKILL.md) | Synchronizace MB dokumentů s realitou kódu |
| mb-git-message | [mb-git-message/SKILL.md](../mb-git-message/SKILL.md) | Návrh commit message (bez commitu) |
| mb-git-commit | [mb-git-commit/SKILL.md](../mb-git-commit/SKILL.md) | Scoped commit (nikdy push) |
| mb-jira-update | [mb-jira-update/SKILL.md](../mb-jira-update/SKILL.md) | České shrnutí implementace do Jira |
| mb-model-routing | [mb-model-routing/SKILL.md](../mb-model-routing/SKILL.md) | Správa `## Model Routing` bloku v context.md |

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
