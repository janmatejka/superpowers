<!-- TARGET: brainstorming/SKILL.md -->
<!-- ANCHOR: EOF -->

<!-- UMS-OVERLAY BEGIN (ums-memory-bank v2) -->
## UMS Memory Bank Overlay

This repository injects a Memory Bank document layer. Read
`../shared/UMS_MEMORY_BANK_CONTRACT.md` before writing the design document.
Adjustments to the checklist above:

- **Item 1 (Explore project context)** additionally requires the six steps below,
  in this order. Create a todo for them. Start as soon as the affected code area is
  identifiable; if it only becomes clear later in the dialog, run them then — but
  they MUST all complete before item 6. Each step does only what it can do at its
  point in the sequence, and only steps 4 to 6 touch the working tree.

  1. **Entry gate.** Run the entry gate of the contract's "Workspace Discipline"
     section — the whole gate, not a part of it. Its eligibility, leftover-inventory
     and park-or-discard phases belong here; its intent and pin-write phases are
     steps 4 and 6 below. Skipping the inventory and that one park-or-discard
     decision is the failure mode to avoid: it leaves the tree dirty, and the
     `git switch -c` of step 4 is then forbidden outright (no auto-stash, no
     switching through `git stash`), which either strands the work or rides foreign
     uncommitted changes onto the ticket branch and into the design commit.
     **Offer park only where park can act:** `mb-park` needs the current branch to
     carry a pin, so on an IDLE branch — typically the base, which is where a new
     ticket starts — it stops with „Není co parkovat" and commits nothing. There the
     one decision is **commit them on this branch** or **discard**; the leftovers
     still have to be resolved either way. Within
     eligibility, an **installed and verified `pre-push` hook is a fail-closed
     precondition**, because hooks do not travel with a clone and a workspace
     missing the hook looks exactly like a working one while carrying no publication
     guarantee. A failing `git fetch origin` is a hard failure too; a missing
     `<CTX_DIR>/ums-repo.json` is only reported once ("built-in defaults apply") and
     never blocks entry.
  2. **Target-MB discovery — READ-ONLY.** Per the contract's "Target-MB Discovery &
     Pinning" section: scan active work items, run the mb-doc-index skill with
     `-Json <path>` — the printed table has no path column, and that step's
     normalization to the owning `memory-bank/` root needs `entries[].path` — and
     take the candidate set as the union of the local scan and the index over
     origin; evidence tags, A/B/C disambiguation — the user always decides. Where a
     queued draft in `proposals/next/` matches the work (confirm with the user when
     the match is only probable), **record the match, its slug, its ticket and its
     path, and read it as design seed — but move nothing.** The move is step 5,
     because it can only happen once the ticket branch exists. This whole step
     writes nothing to the working tree.
  3. **Jira ticket:** ask for it (one question; "none" is a valid answer; skip when
     a draft matched in step 2 already names it). **Then re-run the index with the
     intent declared** (`-Jira <ticket>` and `-Slug <slug>` when known) for the
     cross-clone collision check: a KOLIZE AKTIVNÍ PRÁCE finding — the same slug or
     the same Jira ticket already active on a foreign branch — is a fail-closed STOP
     (exit 2), while foreign active work on OTHER tickets is normal parallel
     operation and never stops anything. Declaring the intent is what makes the
     check work here at all: the design document does not exist yet, so with an
     empty local set an undeclared run cannot tell a collision from ordinary
     parallel work.
  4. **Create the ticket branch** — the entry gate's intent phase — with the tree
     clean, per the rule stated in item 6:
     `git switch -c <TICKET>-<kebab-slug> <baseRef>` after a
     `git fetch origin`, always with the explicit start point. When step 3 answered
     "none", the kebab slug alone names the branch — the ticket code is part of the
     name only when there is one (contract, "Active Work Item (Design + Plan Pair)",
     branch name derived from the slug). Test the creation postcondition here and
     only here: `proposals/active/` empty or absent and `context.md` IDLE.
  5. **Activation**, only when step 2 matched a queued draft: now move ALL files of
     its slug from `proposals/next/` to `active/` — on the ticket branch, where the
     work item belongs — renaming a legacy `proposal_*` draft to `design_<slug>.md`
     during the move (the only permitted legacy conversion), and reuse its slug and
     ticket. A draft that lives on a foreign branch is taken over by blob copy per
     the contract's "Cross-Branch Visibility" section, never a cherry-pick, and
     records `**Převzato z:** <branch>@<sha>` in its header.
  6. **Write the pin** — the entry gate's pin-write phase: `Target MB Pin`, `Jira`,
     `Work item` slug and `Started` into `memory-bank/context.md`. Then read
     `<PLAN_MB>/brief.md`, `architecture.md`, `tech.md` and `playbook.md` (those
     that exist; legacy shape per Memory Bank Document Set) as design context —
     `playbook.md` is prescriptive and BINDS the work, the rest is current-state
     reference.
- **Item 6 (Write design doc)**: save to
  `<PLAN_MB>/proposals/active/design_<slug>.md` (Czech content, header per
  the contract's "Superpowers Document Placement" section) instead of the
  default `docs/superpowers/specs/` path. **By the time you reach this item the
  ticket branch already exists** — item 1 step 4 created it — so here you only
  confirm you are on it and not on the base. **Do not re-create it and do not
  re-test the creation postcondition below:** your own pin and your own
  `proposals/active/` entry are expected to be present by now, and ACTIVE state you
  wrote yourself is not a finding to report and not a reason to delete anything.

  The rule that governed that creation, invoked by item 1 step 4 and stated here in
  full: **always with an explicit starting
  point**, `git switch -c <TICKET>-<kebab-slug> <baseRef>` after a
  `git fetch origin`, where `baseRef` comes from `<CTX_DIR>/ums-repo.json` (the
  contract's "Repository Configuration" section). The implicit form, without a
  starting point, branches off whatever happens to be checked out: run on a
  foreign ticket branch it pulls that branch's pin and its active pair into your
  history. The local base branch is not used in a ticket workspace —
  `<baseRef>` is the only base that counts — and git worktrees are banned
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
