---
name: mb-act
description: DEPRECATED in MB v2 — execution is owned by the superpowers workflow (subagent-driven-development / executing-plans). This stub only redirects.
license: MIT
metadata:
  author: UMS Project
  version: "2.0"
---

# Command: mb-act (deprecated)

Retired in Memory Bank v2 — Superpowers is the driving workflow
(see `../shared/UMS_MEMORY_BANK_CONTRACT.md`).

**Instead:** execute the active plan
(`<PLAN_MB>/proposals/active/proposal_<slug>.md`) via
`subagent-driven-development` (recommended) or `executing-plans`, exactly as
the plan's "For agentic workers" header says. Task progress lives in the plan
checkboxes and `.superpowers/sdd/progress.md`, not in `context.md`.

Announce this redirect to the user in Czech. Do NOT execute any v1
orchestration: do not write `context.md`, do not maintain an Implementation
Checklist.
