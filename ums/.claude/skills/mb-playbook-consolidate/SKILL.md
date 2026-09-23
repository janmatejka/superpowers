---
name: mb-playbook-consolidate
description: Use when a Memory Bank playbook needs consolidating — merging duplicates, retiring stale rules, converting the legacy shape, moving rules up or down the Memory Bank tree, or when the shape check reports a playbook over its threshold (konsolidace playbooku, playbook je moc velký, konsoliduj playbooky monorepa, přesun pravidel k předkovi).
license: MIT
metadata:
  author: UMS Project
  version: "1.0"
---

> Contract core: [UMS_MEMORY_BANK_CONTRACT](../shared/UMS_MEMORY_BANK_CONTRACT.md) · References: [playbook-contract.md](../shared/contract/playbook-contract.md), [harvest.md](../shared/contract/harvest.md). Read the named references before acting.

# Command: mb-playbook-consolidate

**Action:** Consolidate the playbook of one Memory Bank, or of every Memory Bank
of a subtree: convert the legacy shape, merge, retire, move between files,
parts and sections, convert to code, and — when a file or chain stays over its
threshold — write an escalation report.
**Execution:** Interactive. Every batch is a table the user approves before
anything is written; nothing runs automatically.

**⛔ GIT PROHIBITION:** no `git add`/`commit` from this skill except through
`mb-git-commit`, one commit per approved batch. The only push is publishing the
session's OWN ticket branch (contract, "Publication Contract"); a shared branch
is never pushed.

**Model selection:** the mechanics are script work (`consolidate-playbook.ps1`).
The judgement is the analyst's — a read-only dispatch on the cheapest capable
tier (contract, "Dispatch Model Policy"), the model named explicitly in the
dispatch.

---

## Contract

The rules of this skill are in (contract/playbook-contract.md, "Consolidation")
and are not repeated here: the table and its values, the two rounds, tree mode,
batches and resumption, end of run. Also binding:

- consult before writing — (contract/playbook-contract.md, "Playbook Contract");
- item shape and sections — (contract/playbook-contract.md, "Playbook shape");
- ratchet — (contract/playbook-contract.md, "Budget, threshold and ratchet");
- legacy conversion versus patch — (contract/playbook-contract.md, "Legacy mode");
- analyst inputs and rules — (contract/playbook-contract.md, "Analyst brief");
- retired lists — (contract/playbook-contract.md, "Retired rules and conversion to code");
- what may be written — (contract/playbook-contract.md, "Writes outside PLAN_MB");
- the report — (contract/playbook-contract.md, "Escalation report");
- moves between files — (contract, "Document Ownership").

Placeholders below: `<skill>` is this skill's directory, `<mb-shared>` its
sibling `shared/`, `<MB_ROOT>` the repository root. Every path handed to
`consolidate-playbook.ps1` (`-Path`, `-Tree`, and every path inside a decisions
file) is **repository-relative**; the script joins `<MB_ROOT>`. The chain and
tree functions take the repository-relative Memory Bank directory (e.g.
`memory-bank/`, `Common/X/memory-bank/`), never an absolute path;
`Test-UmsPlaybookShape -Playbook` takes an absolute path.

```powershell
. <mb-shared>/scripts/Test-UmsPlaybookShape.ps1   # also loads Read-UmsPlaybook, Get-UmsPlaybookChain, Get-UmsMbTree, Get-UmsMbLowestCommonAncestor
. <mb-shared>/scripts/Find-UmsPlaybookMatch.ps1   # identifier match, round 2a
```

## Modes

| Mode | Invocation | Scope |
|---|---|---|
| One Memory Bank | „konsoliduj playbook", `-Path <MB dir>/playbook.md` | that file; the chain is read, not written |
| Tree | „konsoliduj playbooky celého monorepa", `-Tree [<path>]` | every Memory Bank whose owner directory is `<path>` or below it; default `MB_ROOT` (`-Tree .`) |

`<path>` is the owner directory (`MobilChange/SMSInfo3`), not its
`memory-bank/`. The run's scope bounds every write of
(contract/playbook-contract.md, "Writes outside PLAN_MB"): a move to an
ancestor outside the scope is not written — widen the scope or drop the row.

**Run and batch names.** Pick the run name once, `<YYYY-MM-DD>-<scope-slug>`
(`root` for the whole repository). Batch names are derived, never invented, so
`-Resume` works even after the scratch is gone: `k1-<mb-slug>`,
`k2a-<subtree-slug>`, `k2b-<mb-slug>`, `eskalace-<subtree-slug>`, with a
suffix `-2`, `-3` for a follow-up batch of the same step. `<mb-slug>` is the
owner path with `/` → `_`, `root` for the root Memory Bank.

**Scratch.** Tables and decisions files live under
`<MB_ROOT>/.superpowers/playbook-consolidation/<run>/` — `<batch>.md` (the
table) and `<batch>.json` (the decisions). Git-ignored, regenerable; never
committed.

## Single Memory Bank

Work runs on the session's ticket branch; consolidation is ordinary work on its
own ticket (contract/playbook-contract.md, "Consolidation").

1. **Inventory (read-only).**

   ```powershell
   pwsh -NoProfile -File <skill>/scripts/consolidate-playbook.ps1 -Stats -Path <MB dir>/playbook.md
   pwsh -NoProfile -File <skill>/scripts/consolidate-playbook.ps1 -Parse -Path <MB dir>/playbook.md
   $chain = Get-UmsPlaybookChain <MB_ROOT> <MB dir> -Out
   ```

   Read the `playbook-retired.md` beside every playbook in `$chain.Segments`
   that has one. Show the user the sizes against the thresholds (`lines`,
   `overThreshold`, `chainLines`, `sections[].items`).
2. **Analyst.** Dispatch per (contract/playbook-contract.md, "Analyst brief"):
   the `-Parse` JSON, `$chain.OutPath`, the retired lists, the `-Stats` output —
   paths and outputs, never the inlined chain. It returns one row per item and
   writes nothing; undecided rows stay undecided.
3. **Table.** Present it in Czech, in exactly this shape, and save it as
   `<batch>.md`:

   ```markdown
   | # | Položka | Návrh | Kritérium | Do | Pozn. |
   |---|---|---|---|---|---|
   ```

   `Položka` is the `id` from `-Parse` plus the first words; `Do` is the target
   (file, part, section) for every move; `Pozn.` names every citation rewrite
   of the row (step 6). A row moving to an ancestor lists the count and the
   Memory Banks that inherit the rule (every `Get-UmsMbTree` entry below that
   ancestor).
4. **Approval — consult before writing.** The user approves the table and may
   override any row; undecided rows are decided by the user. Nothing is written
   into any playbook, `playbook-retired.md`, `tech.md` or citation before this
   approval — not even a row the analyst was sure about.
5. **Decisions file.** Translate the approved rows into `<batch>.json`:

   ```json
   { "run": "<run>", "batch": "<batch>", "decisions": [ { "id": "memory-bank/playbook.md#12", "verdict": "presunout", "target": "memory-bank/playbook.md", "part": "podstrom", "section": "Když píšeš PowerShell", "text": "…" } ] }
   ```

   | Návrh v tabulce | `verdict` | Pole |
   |---|---|---|
   | `ponechat` (new-shape file only) | `ponechat` | `id` |
   | rewritten item (round 1 shortening, `Důkaz:`) | `prepsat` | `id`, `text` |
   | `sloučit do <položka>` | `sloucit` | `id` (the merged-away item), `into` (the kept item's `id`), `text` (the merged item) |
   | `vyřadit (<důvod>)` | `vyradit` | `id`, `reason` |
   | `přesunout do tech.md` | `do-tech` | `id`, `target` (`<MB dir>/tech.md`), optional `text` |
   | `převést na test <kde>` | `prevest-na-test` | `id`, `test` — the test is written first, in this batch |
   | `přesunout k předkovi` / `k potomkovi` / `přeřadit do části`, every move of a section | `presunout` | `id`, `target` (playbook path), `part` (`podstrom` \| `projekt`), `section` (`Když …`), optional `text` |
   | a new item (the merged item of a cross-MB cluster) | `novy` | `target`, `part`, `section`, `text` |

   An `id` is `<playbook path>#<n>` exactly as `-Parse` prints it. Every `text`
   is Czech, in the item shape. Merging duplicates into one item where none of
   them stays (a cluster moved to an ancestor): `presunout` one of them with the
   merged `text`, `vyradit` the others with `reason` `nahrazeno «<položka>»`.
6. **Citation rewrites (round 1, and every batch that renames or moves a
   section).** For every old section name the batch renames or moves, grep the
   repository outside the playbook — `git grep -n -F "<old name>"` — and
   rewrite each citation to the new name in the same batch, citation text only
   (contract/playbook-contract.md, "Writes outside PLAN_MB"). Hits in Memory
   Bank documents outside the run's scope are not rewritten: list them in
   `Pozn.` and in the report.
7. **Apply.** Note each target file's line count, then:

   ```powershell
   pwsh -NoProfile -File <skill>/scripts/consolidate-playbook.ps1 -Apply <MB_ROOT>/.superpowers/playbook-consolidation/<run>/<batch>.json
   ```

   Its `written` array names every file it wrote (playbooks,
   `playbook-retired.md`, `tech.md`). The script never raises a ratchet
   (contract/playbook-contract.md, "Budget, threshold and ratchet"). Never
   re-apply a decisions file already applied; a correction is a NEW decisions
   file.
8. **Shape check.** `Test-UmsPlaybookShape -Playbook (Join-Path <MB_ROOT> <file>)`
   on every written playbook, `Test-UmsPlaybookTree <MB_ROOT> <owner>` for its
   owner directory (`''` for the root). Print every warning.
   - `[ráčna-růst]` / `[ráčna-chybí]` — a human decision: balance it by a new
     approved batch, or raise with the user's reason,
     `consolidate-playbook.ps1 -Baseline -Path <file> -Reason <text>`
     (`<file>` repository-relative, as in `written`) — the only way a ratchet is
     raised; add the file to the batch's commit.
   - Any other hard finding — back to the user as a changed row, written by a
     new decisions file; never a hand edit of the playbook.
9. **Commit.** `mb-git-commit`, playbook batch: it stages exactly `written`
   plus the citation rewrites of step 6 (and a test written for
   `prevest-na-test`, and a `-Baseline` file). The message's LAST paragraph
   carries the trailer next to the other trailers:

   ```
   Playbook-Consolidation: <run>/<batch>
   ```

   Git reads trailers only from the last paragraph, and `-Resume` reads them
   from there. One batch, one commit — the source and the target of a move
   are never split.
10. **Publish** the own ticket branch per (contract, "Publication Contract"),
    never a shared branch.

**Round 1 (shape)** converts the file whole
(contract/playbook-contract.md, "Legacy mode"): for a legacy file, one row per
item, every row `presunout` into its part and `Když …` section with the item
rewritten in the item shape — `Proč:` shortened to one sentence, `Důkaz:`
filled from the harvest commit that brought the text
(`git log -S "<distinctive phrase>" --reverse --format="%h %s" -- <playbook>`,
first line). `-Apply` converts a legacy file only when the batch has
`presunout` or `ponechat` for one of its items, and then refuses a batch that
leaves any item undecided or marks one `ponechat`; a batch with neither
patches the file in place instead. If the converted file is over 600 lines, `-Apply` writes its
ratchet unless the batch grew the file — then the shape check reports
`[ráčna-chybí]` and step 8 applies. Round 1 merges nothing; a new-shape file
skips round 1.

**Round 2** merges, retires, moves, converts to code (`sloucit`, `vyradit`,
`presunout`, `do-tech`, `prevest-na-test`). A section still over 40 items
after round 2 splits into narrower `Když …` sections — `presunout` rows in a
batch of its own. A file still over 600 lines, or a chain over 900, after round
2 goes to "Escalation report" below.

## Tree

Per (contract/playbook-contract.md, "Consolidation"), paragraph "Tree mode":

1. **Inventory — writes nothing.**

   ```powershell
   pwsh -NoProfile -File <skill>/scripts/consolidate-playbook.ps1 -Stats -Tree <path>
   pwsh -NoProfile -File <skill>/scripts/consolidate-playbook.ps1 -Parse -Tree <path>
   ```

   Show the user one Czech row per Memory Bank: `| MB | Řádky | Nad prahem | Řetězec | Tvar |`
   (`lines`, `overThreshold`, `chainLines` against 900, `shape` from `-Parse`),
   and the planned batch list of the run.
2. **Round 1 per Memory Bank, top down** — ancestors before descendants
   (fewer path segments of the owner first), because a descendant needs to know
   what its ancestor already carries in the subtree part. Each Memory Bank is
   its own batch `k1-<mb-slug>`: steps 1–10 of "Single Memory Bank".
3. **Round 2a — across Memory Banks, one batch per subtree** (`k2a-<subtree-slug>`).
   The analyst clusters items of different Memory Banks by topic;
   `Find-UmsPlaybookMatch <item text> <MB_ROOT> <MB dir>` helps mechanically.
   For every cluster compute the lowest common ancestor:

   ```powershell
   $tree = Get-UmsMbTree <MB_ROOT>
   Get-UmsMbLowestCommonAncestor $tree @('<MB dir 1>', '<MB dir 2>')
   ```

   Rows: `přesunout k předkovi <předek>` (one item in the ancestor's
   `Pro celý podstrom`, the duplicates retired), `ponechat` (every Memory Bank
   keeps its own variant), `přesunout k potomkovi <cesta>` (a rule written
   higher than it applies). One table across the subtree's Memory Banks,
   approved, written and committed as one batch.
4. **Round 2b — within each Memory Bank** (`k2b-<mb-slug>`), as round 2 of
   "Single Memory Bank".

## Escalation report

When a file or a chain is still over its threshold after round 2, stop cutting
(contract/playbook-contract.md, "Escalation report"). Confirm the ratchet sits
at the achieved size (step 8), then draft the report in Czech, show it to the
user, and write it only after approval, as
`<MB>/proposals/next/design_<mb-slug>_playbook_eskalace.md` — in its own batch
`eskalace-<…>`, committed like any other. In `-Tree` mode one report per
subtree, placed in the Memory Bank returned by
`Get-UmsMbLowestCommonAncestor` over the Memory Banks still over a threshold;
when that Memory Bank lies outside the run's scope, ask the user where it goes.

```markdown
# Návrh: Eskalace playbooku — <MB nebo podstrom>

## Cíl

Playbook <cesta> zůstal po konsolidaci (běh <run>) nad prahem. Tento
předběžný návrh dává podklad pro přesun obsahu jinam; nic neřeší.

## Scope

- Dotčené MB: <seznam>
- Dotčené řetězce: <seznam MB, jejichž řetězec je nad 900>

## Technický návrh

### Velikosti proti prahu

| MB | Soubor (řádky / 600) | Řetězec (řádky / 900) | Ráčna |
|---|---|---|---|

### Shluky

| Shluk | Položky | Řádky | Navržený domov | Proč |
|---|---|---|---|---|

Domov je jeden z: skill (postup vázaný na jeden druh práce, načtený jen pro
ni), skript nebo test (mechanicky ověřitelné), samostatný referenční dokument
MB čtený na vyžádání, `tech.md`.

### Odhad úspory

| Soubor / řetězec | Teď | Po přesunu |
|---|---|---|
```

Sizes come from `-Stats` (`lines`, `chainLines`), cluster sizes from the
`lineCount` of the `-Parse` items.

## Resume

```powershell
pwsh -NoProfile -File <skill>/scripts/consolidate-playbook.ps1 -Resume <run>
```

`done` lists the batches whose trailer is in `git log`. Rebuild the batch list
from the inventory (the names are derived), skip the done ones, and continue
with the first unfinished batch — regenerate its table; a table in the scratch
without its commit was never approved-and-written and is redone.

## End of run

- `Test-UmsPlaybookTree <MB_ROOT> <owner>` over the whole scope (`''` for the
  root) — no hard finding may remain.
- Every Memory Bank whose file or chain stays over a threshold has its ratchet
  at the achieved size and an escalation report in `proposals/next/`.
- `mb-link-audit` (`-Path <owner>`, without `-Path` for the root) over every
  Memory Bank a batch touched.
- Report to the user in Czech: `| Dávka | Commit | Zapsáno | Vyřazeno | Velikost před → po |`,
  the citation hits left outside the scope, and the escalation reports written.

## Never

- Never write a playbook, `playbook-retired.md`, `tech.md`, citation or report
  without the user's approval of that batch's table.
- Never push a shared branch; only the own ticket branch is published.
- Never write a Memory Bank document outside the Scope Lock exception of
  (contract/playbook-contract.md, "Writes outside PLAN_MB") — nothing beyond
  what the approved batch names.
- Never run automatically — not from a harvest, a shape finding or another
  skill; they may only recommend this skill.
- Never hand-edit a playbook instead of a decisions file, re-apply an applied
  decisions file, or raise a ratchet with `-Apply`.
- Never invent a `Důkaz:` or a `Happened` — an item without evidence says so in
  `Pozn.` and the user decides.
