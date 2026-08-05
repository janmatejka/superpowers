<!-- TARGET: brainstorming/SKILL.md -->
<!-- ANCHOR: EOF -->

<!-- UMS-OVERLAY BEGIN (ums-memory-bank v2) -->
## UMS Memory Bank Overlay

This repository injects a Memory Bank document layer. Read
`../shared/UMS_MEMORY_BANK_CONTRACT.md` before writing the design document.
Adjustments to the checklist above:

- **Item 1 (Explore project context)** additionally requires: before any work is
  pinned, run the **whole entry gate** of the contract's "Workspace Discipline"
  section — all of its phases, in its order: eligibility, leftover inventory,
  the single park-or-discard decision, intent, pin write. Running only the
  eligibility phase is the failure mode to avoid: skipping the inventory and that
  one decision leads to a `git switch -c` on a dirty tree, which this repository
  forbids outright (no auto-stash, no switching through `git stash`), and foreign
  uncommitted changes then ride onto the ticket branch and land in the design
  commit. Within eligibility, an **installed and verified `pre-push` hook is a
  fail-closed precondition**, because hooks do not travel with a clone and a
  workspace missing the hook looks exactly like a working one while carrying no
  publication guarantee. A failing `git fetch origin` is a hard failure too; a
  missing `<CTX_DIR>/ums-repo.json` is only reported once ("built-in defaults
  apply") and never blocks entry. Then: as soon as the
  affected code area is identifiable, run Target-MB discovery per the
  contract's "Target-MB Discovery & Pinning" section (scan active work items,
  run the mb-doc-index skill with `-Json <path>` — the printed table has no
  path column, and step 2's normalization to the owning `memory-bank/` root
  needs `entries[].path` — and treat the candidate set as the union of the
  local scan and the index over origin; evidence tags, A/B/C disambiguation
  — the user always decides; activate a matching queued design draft from
  `proposals/next/` by moving its files to `active/` — a legacy `proposal_*`
  draft is renamed to `design_<slug>.md` during the move — and use the draft
  as design seed), ask for the Jira
  ticket (one question; "none" is a valid answer), **then re-run the index
  with the intent declared** (`-Jira <ticket>` and `-Slug <slug>` when known)
  for the cross-clone collision check: a KOLIZE AKTIVNÍ PRÁCE finding — the
  same slug or the same Jira ticket already active on a foreign branch — is a
  fail-closed STOP (exit 2), while foreign active work on OTHER tickets is
  normal parallel operation and never stops anything. Declaring the intent is
  what makes the check work here at all: the design document does not exist
  yet, so with an empty local set an undeclared run cannot tell a collision
  from ordinary parallel work. Then persist `Target MB Pin`,
  `Jira`, `Work item` slug and `Started` into `memory-bank/context.md` — when the
  intent is a NEW ticket branch, create the branch BEFORE this pin write (item 6
  states how), so the pin lands on the branch that owns it and the branch's
  IDLE postcondition still holds when it is created — then
  read `<PLAN_MB>/brief.md`, `architecture.md`, `tech.md` and `playbook.md`
  (those that exist; legacy shape per Memory Bank Document Set) as design
  context — `playbook.md` is prescriptive and BINDS the work, the rest is
  current-state reference. Create a todo for this. If the
  affected area only becomes clear later in the dialog, this step MUST
  complete before item 6.
- **Item 6 (Write design doc)**: save to
  `<PLAN_MB>/proposals/active/design_<slug>.md` (Czech content, header per
  the contract's "Superpowers Document Placement" section) instead of the
  default `docs/superpowers/specs/` path. **By the time you reach this item the
  ticket branch already exists** — item 1's entry gate created it, before the pin
  write — so here you only confirm you are on it and not on the base. **Do not
  re-create it and do not re-test the creation postcondition below:** your own pin
  and your own `proposals/active/` entry are expected to be present by now, and
  ACTIVE state you wrote yourself is not a finding to report and not a reason to
  delete anything.

  The rule that governed that creation, stated here for reference and for the case
  where the branch still has to be made: **always with an explicit starting
  point**, `git switch -c <TICKET>-<kebab-slug> origin/<baseRef>` after a
  `git fetch origin`, where `baseRef` comes from `<CTX_DIR>/ums-repo.json` (the
  contract's "Repository Configuration" section). The implicit form, without a
  starting point, branches off whatever happens to be checked out: run on a
  foreign ticket branch it pulls that branch's pin and its active pair into your
  history. The local base branch is not used in a ticket workspace —
  `origin/<baseRef>` is the only base that counts — and git worktrees are banned
  in this repository (branch-in-place). **Postcondition, tested at creation time
  and only then:** `proposals/active/` is empty or absent and `context.md` is IDLE.
  If it is not, STOP, delete the just-created branch and repeat; an ACTIVE base
  means a work item was integrated without a harvest, and that is the finding to
  report (the contract's "Cross-Branch Visibility" section).

  After committing the design, push the branch — the agent pushes its OWN ticket
  branch after every commit, always announcing the branch and the outgoing commits
  (Publication Contract).
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
