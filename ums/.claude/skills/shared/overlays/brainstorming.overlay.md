<!-- TARGET: brainstorming/SKILL.md -->
<!-- ANCHOR: EOF -->

<!-- UMS-OVERLAY BEGIN (ums-memory-bank v2) -->
## UMS Memory Bank Overlay

This repository injects a Memory Bank document layer. Read
`../shared/UMS_MEMORY_BANK_CONTRACT.md` before writing the design document.
Adjustments to the checklist above:

- **Item 1 (Explore project context)** additionally requires: as soon as the
  affected code area is identifiable, run Target-MB discovery per the
  contract's "Target-MB Discovery & Pinning" section (scan active proposal
  pairs, evidence tags, A/B/C disambiguation — the user always decides), ask
  for the Jira ticket (one question; "none" is a valid answer), persist
  `Target MB Pin`, `Jira`, `Proposal` slug and `Started` into
  `memory-bank/context.md`, then read `<PLAN_MB>/brief.md`, `product.md`,
  `architecture.md`, `tech.md` (those that exist) as design context. Create a
  todo for this. If the affected area only becomes clear later in the dialog,
  this step MUST complete before item 6.
- **Item 6 (Write design doc)**: save to
  `<PLAN_MB>/proposals/active/proposal_<slug>-design.md` (Czech content,
  header per the contract's "Superpowers Document Placement" section) instead
  of the default `docs/superpowers/specs/` path. Before committing, if you are
  on the default branch, create a feature branch in place first — git
  worktrees are banned in this repository.
- The design document and all user-facing communication are in Czech.
<!-- UMS-OVERLAY END -->
