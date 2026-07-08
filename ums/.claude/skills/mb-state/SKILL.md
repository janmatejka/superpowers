---
name: mb-state
description: Read-only status report of the Memory Bank workflow — Target MB Pin, proposal pair completeness, SDD progress ledger, branch, staleness. Use to check workflow status and get next-step suggestions.
license: MIT
metadata:
  author: UMS Project
  version: "2.0"
---

> Follow [UMS_MEMORY_BANK_CONTRACT](../shared/UMS_MEMORY_BANK_CONTRACT.md) —
> especially "Active Proposal Pair" and "`context.md` Schema & Writers".

# Command: mb-state

**Action:** Report the current Memory Bank state and suggest the next step.
**Execution:** Read-only — does NOT modify files.

---

## Workflow

### 0. Resolve MB_ROOT and gate

- `git rev-parse --show-toplevel` → `MB_ROOT`; failure = hard stop
  (`Git repository not found. Memory Bank requires git.`).
- `<MB_ROOT>/memory-bank/` must exist, else stop with the Root Gate error.

### 1. Gather state (read-only)

- `<CTX_DIR>/context.md` → `Jira`, `Target MB Pin`, `Proposal` slug,
  `Started`, `Model Routing` presence. Missing file or IDLE content →
  `PHASE = IDLE`, otherwise `ACTIVE_WORK`. Ignore stale v1 fields (`Status`,
  `Run Mode`, `Execution Mode`, `Implementation Checklist`,
  `Auto Loop State`) — the v2 schema abolished them; their presence is worth
  a one-line note suggesting a reset at the next harvest.
- Pair completeness in `<PLAN_MB>/proposals/active/`:
  - `proposal_<slug>-design.md` + `proposal_<slug>.md` → complete pair,
  - design only → „rozpracovaný návrh (chybí plán)" — valid state between
    brainstorming and writing-plans,
  - plan only (single file) → grandfathered v1 proposal — valid,
  - nothing / slug mismatch → inconsistent, recommend `mb-harvest` audit or
    `mb-abort`.
- **Two-actives check:** scan `**/memory-bank/proposals/active/proposal_*.md`
  (group pairs by slug); any active slug different from the pinned one is a
  warning — recommend finishing or `mb-abort` before new work.
- Execution progress: does `.superpowers/sdd/progress.md` exist? (Presence =
  plan execution in flight; content shows the last completed task.)
- Git: current branch (`git branch --show-current`), work on main/master is a
  warning.
- Staleness: `Started` older than 7 days → warn that requirements may have
  drifted.

### 2. Report (Czech)

```
📊 Stav Memory Bank

Projekt: <name>   Kořen: <MB_ROOT>
Fáze: IDLE | ACTIVE_WORK
Jira: <ticket|žádný>   Cílová MB: <Target MB Pin|nepřipnuto>
Proposal: <slug> — [kompletní pár | jen návrh | grandfathered v1 | nekonzistentní]
Zahájeno: <Started> <(⚠️ starší než 7 dní)>
Exekuce: [.superpowers/sdd/progress.md nalezen — probíhá | nenalezen]
Větev: <branch> <(⚠️ main/master)>
Další aktivní proposaly: <žádné | ⚠️ výčet cizích slugů>

Další krok:
- IDLE → popiš, co chceš postavit (spustí se brainstorming); mb-scan pro analýzu
- jen návrh → pokračuj writing-plans
- kompletní pár → exekuce dle hlavičky plánu (subagent-driven-development)
- hotová implementace → finishing-a-development-branch (harvest gate)
- opuštěná práce → mb-abort; pozdní sklizeň → mb-harvest
```

## State vs Scan

| | mb-state | mb-scan |
|:--|:----------|:---------|
| Speed | Quick (seconds) | Thorough (minutes) |
| Focus | Workflow state | Code health |
| Use for | Status check | Deep analysis |
