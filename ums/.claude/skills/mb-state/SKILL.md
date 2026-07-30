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

- `<CTX_DIR>/context.md` → `Jira`, `Target MB Pin`, `Work item` slug (legacy
  `Proposal` accepted), `Started`. Missing file or IDLE content →
  `PHASE = IDLE`, otherwise `ACTIVE_WORK`. Ignore stale v1 fields (`Status`,
  `Run Mode`, `Execution Mode`, `Implementation Checklist`,
  `Auto Loop State`) — the v2 schema abolished them; their presence is worth
  a one-line note suggesting a reset at the next harvest.
- Pair completeness in `<PLAN_MB>/proposals/active/` (per the contract's
  Discovery & pairing rule — both naming styles):
  - `design_<slug>.md` + `plan_<slug>.md` (or legacy pair) → complete pair,
  - design half only → „rozpracovaný návrh (chybí plán)" — valid state
    between brainstorming and writing-plans,
  - plan-style single file (legacy `proposal_<slug>.md`) → grandfathered v1
    work item — valid,
  - nothing / slug mismatch → inconsistent, recommend `mb-harvest` audit or
    `mb-abort`.
- **Review pending:** a `- **Review:** design-review requested YYYY-MM-DD`
  line in `## Active Work` means the design sits with the architect — the
  workflow is parked (no writing-plans) until `mb-architect-review` resume.
- **Two-actives check:** scan
  `**/memory-bank/proposals/active/{design_,plan_,proposal_}*.md` (group by
  slug per the pairing rule); any active slug different from the pinned one
  is a warning — recommend finishing or `mb-abort` before new work. Queued
  items in `proposals/next/` are NOT counted here.
- **Preliminary queue:** scan
  `**/memory-bank/proposals/next/{design_,plan_,proposal_}*.md` (group by
  slug per the pairing rule, per owning MB) and list the queued preliminary
  proposals — they activate by moving to `active/` when work on them starts
  (contract, Target-MB Discovery & Pinning).
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
Work item: <slug> — [kompletní pár | jen návrh | grandfathered v1 | nekonzistentní]
Review: <žádné | ⏳ čeká na design review u architekta od YYYY-MM-DD>
Zahájeno: <Started> <(⚠️ starší než 7 dní)>
Exekuce: [.superpowers/sdd/progress.md nalezen — probíhá | nenalezen]
Větev: <branch> <(⚠️ main/master)>
Další aktivní proposaly: <žádné | ⚠️ výčet cizích slugů>
Fronta (proposals/next/): <prázdná | výčet slugů s vlastnící MB>

Další krok:
- IDLE → popiš, co chceš postavit (spustí se brainstorming); mb-scan pro analýzu
- fronta neprázdná → řekni, že chceš začít na některém z fronty (přesun next/ → active/ proběhne v brainstormingu)
- jen návrh → pokračuj writing-plans
- kompletní pár → exekuce dle hlavičky plánu (subagent-driven-development)
- čeká na review → mb-architect-review (resume) po vrácení tiketu; writing-plans je do té doby blokován
- hotová implementace → finishing-a-development-branch (harvest gate)
- opuštěná práce → mb-abort; pozdní sklizeň → mb-harvest
```

## State vs Scan

| | mb-state | mb-scan |
|:--|:----------|:---------|
| Speed | Quick (seconds) | Thorough (minutes) |
| Focus | Workflow state | Code health |
| Use for | Status check | Deep analysis |
