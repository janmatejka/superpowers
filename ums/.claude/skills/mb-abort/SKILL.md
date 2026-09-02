---
name: mb-abort
description: Discard the active work item — archive the proposal pair to abandoned/ and reset context.md to IDLE. Use when canceling or abandoning current work without completing it.
license: MIT
metadata:
  author: UMS Project
  version: "2.0"
---

> Follow [UMS_MEMORY_BANK_CONTRACT](../shared/UMS_MEMORY_BANK_CONTRACT.md) —
> especially "Active Work Item (Design + Plan Pair)", "`context.md` Schema & Writers"
> and the Publication Contract's "Abandon" subsection, which owns the order of the
> steps below.
> This skill is the abandon-path counterpart of `mb-harvest`.

# Command: mb-abort

**Action:** Archive the active proposal pair to `abandoned/`, reset
`context.md` to IDLE, then commit and publish that change. Code changes are NOT
reverted.
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

- Read `<CTX_DIR>/context.md` → `Target MB Pin`, `Work item` slug (legacy
  `Proposal` accepted).
- The active proposal (pair `design_<slug>.md` + `plan_<slug>.md` (legacy
  `proposal_<slug>-design.md` + `proposal_<slug>.md`), or a grandfathered
  single plan file) must exist in `<PLAN_MB>/proposals/active/`. If not,
  report and suggest `mb-state`.

### 2. Confirmation (Czech)

```
⚠️ Zahodit práci na: <soubory work itemu dle skutečných názvů>

Pár návrh+plán bude archivován do: <PLAN_MB>/proposals/abandoned/
Změny v kódu NEBUDOU vráceny — případný revert proveď ručně přes git.

Potvrď 'yes' pro pokračování.
```

Proceed only on exact "yes"; otherwise cancel and suggest `mb-state`.

### 3. Archive the pair

Move the design and plan halves (whichever exist, either naming style)
from `<PLAN_MB>/proposals/active/` to `<PLAN_MB>/proposals/abandoned/`,
unchanged. Never touch proposals of other Memory Banks.

### 4. Reset context.md

Overwrite `<CTX_DIR>/context.md` with the IDLE baseline per the contract
schema (`context.md` Schema & Writers): `## Active Work` →
`(No active work - IDLE phase)`, keeping the `- **Jira:** …` and
`- **Báze:** …` lines of the abandoned work item exactly as that section
specifies. Do not preserve any other section or history.

- Invalidate the session intent baton (contract, "Session Intent Baton"). The
  work item ends here, so an outstanding `plan-execution` baton is void.

### 4a. Commit and publish the abandon

Per the contract's Publication Contract, subsection "Abandon" — steps 1–3 of that
sequence are this skill's job, and step 3 is what makes the abandon visible outside
this workspace:

- Commit the archive move and the IDLE reset through the `mb-git-commit` skill, never
  a hand-rolled `git commit`, so the repository's single commit-message convention
  holds. Commit message in Czech.
- Then publish: the agent pushes its OWN ticket branch, announcing the branch and the
  outgoing commits. If the current branch is shared (`protectedBranches`, see the
  contract's Repository Configuration section), the agent does NOT push — it prepares
  the exact command `! MB_HUMAN_PUSH=1 git push origin HEAD:<the current shared
  branch>` together with the outgoing commits and the user runs it. The commit
  the archive move just made is local only, so the content rule cannot apply here
  (it is not yet reachable from any `refs/remotes/<remote>/*`) and the escape is
  the only form that gets it through; the agent never pushes a shared branch and
  never sets that variable itself.

This skill deletes no branches — step 4 of the contract's sequence belongs to the
finishing Discard path.

### 4b. Jira cleanup (Design Review only)

If `context.md` carried a `Review:` line, or the linked ticket sits in
"Design Review" (fallback shape included — status "Review" with the
`[DESIGN REVIEW]` request-comment marker; contract, Architect Review Gate,
"Design Review" fallback): offer (Czech, user confirms) the cleanup per the
contract's Architect Review Gate — transition the ticket back to
"In Progress" (or its previous status), restore the assignee to the original
resolver, clear the `Flagged` field. Without cleanup the architect keeps a
live review assignment for abandoned work — say so in the warning.

### 5. Announce (Czech)

> „✅ Práce zrušena. Archivováno do `abandoned/`."
> „⚠️ Změny v kódu NEBYLY vráceny — případně zkontroluj git."
> „Fáze: IDLE. Pro návrhy spusť `mb-state`."
