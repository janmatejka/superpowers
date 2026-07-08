---
name: mb-review
description: DEPRECATED in MB v2 — review is owned by the superpowers workflow (spec self-review + user review gate, SDD task reviewer, final branch review). This stub only redirects.
license: MIT
metadata:
  author: UMS Project
  version: "2.0"
---

# Command: mb-review (deprecated)

Retired in Memory Bank v2 (see `../shared/UMS_MEMORY_BANK_CONTRACT.md`).
Review now happens inside the superpowers chain:

- spec: inline self-review + user review gate in `brainstorming`,
- plan: inline self-review in `writing-plans`,
- per task: task reviewer in `subagent-driven-development`,
- whole branch: final reviewer via `requesting-code-review` before finishing.

**Instead:** if the user wants an extra review of the active proposal pair,
dispatch a reviewer subagent (Reviewer Model per the contract's Model Routing
Consumption) over `<PLAN_MB>/proposals/active/` and render findings in Czech.

Announce this redirect to the user in Czech. Do NOT write review state into
`context.md` or the proposal.
