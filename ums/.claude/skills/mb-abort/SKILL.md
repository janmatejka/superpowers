---
name: mb-abort
description: Discard the active work item — archive the proposal pair to abandoned/ and reset context.md to IDLE. Use when canceling or abandoning current work without completing it.
license: MIT
metadata:
  author: UMS Project
  version: "2.0"
---

> Follow [UMS_MEMORY_BANK_CONTRACT](../shared/UMS_MEMORY_BANK_CONTRACT.md) —
> especially "Active Proposal Pair" and "`context.md` Schema & Writers".
> This skill is the abandon-path counterpart of `mb-harvest`.

# Command: mb-abort

**Action:** Archive the active proposal pair to `abandoned/`, reset
`context.md` to IDLE. Code changes are NOT reverted.
**Execution:** Requires **explicit confirmation**.

The escape hatch outside `finishing-a-development-branch` — use it when work
is abandoned mid-flight (requirements changed, wrong approach, blocked,
priorities changed). Inside finishing, option 4 (Discard) performs the same
archive/reset via the UMS Harvest Gate overlay.

---

## Workflow

### 0. Resolve MB_ROOT and gate

- `git rev-parse --show-toplevel` → `MB_ROOT`; failure = hard stop
  (`Git repository not found. Memory Bank requires git.`).
- `<MB_ROOT>/memory-bank/` must exist, else stop with the Root Gate error.

### 1. Preconditions

- Read `<CTX_DIR>/context.md` → `Target MB Pin`, `Proposal` slug.
- The active proposal (pair `proposal_<slug>-design.md` + `proposal_<slug>.md`,
  or a grandfathered single file) must exist in
  `<PLAN_MB>/proposals/active/`. If not, report and suggest `mb-state`.

### 2. Confirmation (Czech)

```
⚠️ Zahodit práci na: proposal_<slug>*.md

Proposal pár bude archivován do: <PLAN_MB>/proposals/abandoned/
Změny v kódu NEBUDOU vráceny — případný revert proveď ručně přes git.

Potvrď 'yes' pro pokračování.
```

Proceed only on exact "yes"; otherwise cancel and suggest `mb-state`.

### 3. Archive the pair

Move `proposal_<slug>-design.md` and `proposal_<slug>.md` (whichever exist)
from `<PLAN_MB>/proposals/active/` to `<PLAN_MB>/proposals/abandoned/`,
unchanged. Never touch proposals of other Memory Banks.

### 4. Reset context.md

Overwrite `<CTX_DIR>/context.md` with the IDLE baseline per the contract
schema: `## Active Work` → `(No active work - IDLE phase)` + keep the
`- **Jira:** …` line if it existed. Do not preserve any other section or
history.

### 5. Announce (Czech)

> „✅ Práce zrušena. Archivováno do `abandoned/`."
> „⚠️ Změny v kódu NEBYLY vráceny — případně zkontroluj git."
> „Fáze: IDLE. Pro návrhy spusť `mb-state`."
