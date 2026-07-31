# Brief

## Co je tento repozitář

Fork `janmatejka/superpowers` ([GitHub](https://github.com/janmatejka/superpowers)),
ve kterém se **vyvíjí a redistribuuje integrační vrstva UMS Memory Bank v2 nad
projektem Superpowers** (upstream `obra/superpowers`, v tomto repu remote
`vanila`).

Superpowers je knihovna skillů pro kódovací agenty (Claude Code, Codex, Cursor,
Gemini CLI, Copilot CLI, Kimi, OpenCode, pi) — řídí pracovní postup
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
| [`ums/.claude/skills/shared/`](../ums/.claude/skills/shared/) | Normativní zdroj vrstvy: kontrakt v2.1, manifest, vendor pin, overlay fragmenty. |
| [`ums/.claude/skills/mb-*/`](../ums/.claude/skills/) | Utility skilly Memory Bank (13 aktivních + 2 deprecated stuby). |
| [`memory-bank/`](.) | Memory Bank tohoto repozitáře — orchestrační kořen (`CTX_DIR`) i cílová MB (`PLAN_MB`). |
| `.claude/`, `.agents/` | Netrackovaná **nasazení** vrstvy pro práci v tomto repu (viz [architecture.md](architecture.md)). |
| [`hooks/`](../hooks/), [`tests/`](../tests/), [`docs/`](../docs/) | Upstream infrastruktura (bootstrap hooky, testy, dokumentace portování). |

## Vztah k monorepu UMS

Živá (master) kopie vrstvy je v monorepu UMS (`d:\_datasys\ums`, Bitbucket
`datasyscz/ums`) v jeho `.claude/` a `CLAUDE.md`. Adresář `ums/` v tomto forku
je její **redistribuovatelné zrcadlo** — synchronizuje se skriptem
[`sync-with-monorepo.ps1`](../ums/sync-with-monorepo.ps1).

Monorepo má vlastní Memory Bank (`d:\_datasys\ums\memory-bank\`) pro produkt
UMS; s touto Memory Bank se nemíchá — tato dokumentuje **vývoj vrstvy**, ta
druhá **produkt, na kterém se vrstva používá**.

## Stav

Vrstva je v provozu (kontrakt v2.1, vendor pin upstream v6.2.0). Práce na této
větvi má 102 commitů nad `main`; poslední dokončené položky jsou v
[proposals/completed/](proposals/completed/).
