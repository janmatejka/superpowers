<!-- TARGET: brainstorming/SKILL.md -->
<!-- ANCHOR: EOF -->

<!-- UMS-OVERLAY BEGIN (ums-memory-bank v2) -->
## UMS Memory Bank Overlay

This repository injects a Memory Bank document layer. Read
`../shared/UMS_MEMORY_BANK_CONTRACT.md` before writing the design document.
Adjustments to the checklist above:

- **Item 1 (Explore project context)** additionally requires: as soon as the
  affected code area is identifiable, run Target-MB discovery per the
  contract's "Target-MB Discovery & Pinning" section (scan active work items,
  run the mb-doc-index skill and treat the candidate set as the union of the
  local scan and the index over origin; a KOLIZE AKTIVNÍ PRÁCE finding — the
  same slug or the same Jira ticket already active on a foreign branch — is
  a fail-closed STOP; foreign active work on other tickets is normal;
  evidence tags, A/B/C disambiguation — the user always decides; activate a
  matching queued design draft from `proposals/next/` by moving its files to
  `active/` — a legacy `proposal_*` draft is renamed to `design_<slug>.md`
  during the move — and use the draft as design seed), ask for the Jira
  ticket (one question; "none" is a valid answer), persist `Target MB Pin`,
  `Jira`, `Work item` slug and `Started` into `memory-bank/context.md`, then
  read `<PLAN_MB>/brief.md`, `product.md`, `architecture.md`, `tech.md`
  (those that exist) as design context. Create a todo for this. If the
  affected area only becomes clear later in the dialog, this step MUST
  complete before item 6.
- **Item 6 (Write design doc)**: save to
  `<PLAN_MB>/proposals/active/design_<slug>.md` (Czech content, header per
  the contract's "Superpowers Document Placement" section) instead of the
  default `docs/superpowers/specs/` path. Before committing, if you are on
  the default branch, create a feature branch in place first — git worktrees
  are banned in this repository. After committing the design, publish the
  branch (Publication Contract, publication point 1) — an announced push of
  your own ticket branch.
- **Architect Review Gate (between item 8 and item 9):** when a Jira ticket
  is linked, ALWAYS offer a design review by a human architect after the
  user approves the spec — with your own yes/no recommendation based on
  non-triviality (new component or service, architecture/contract changes,
  cross-project impact, DB migration, security impact). If accepted, invoke
  the `mb-architect-review` skill (request mode) and END the workflow here —
  work resumes later via its resume mode. If declined, or when no ticket is
  linked, proceed to item 9 as usual. **This amends the terminal-state rule
  above:** in this repository `mb-architect-review` may follow brainstorming;
  writing-plans remains the only *implementation* successor.
- While `memory-bank/context.md` contains a
  `- **Review:** design-review requested` line, the workflow is parked: do
  NOT invoke writing-plans; the correct continuation is `mb-architect-review`
  (resume mode).
- The design document and all user-facing communication are in Czech.
<!-- UMS-OVERLAY END -->
