<!-- TARGET: brainstorming/SKILL.md -->
<!-- ANCHOR: EOF -->
<!-- ASSERT: Before your first question, classify the request and say the -->
<!-- ASSERT: **Terminal states are path-bound.** Architectural: the ONLY skill you -->
<!-- ASSERT:   one. No spec file, no implementation plan document. -->

<!-- UMS-OVERLAY BEGIN (ums-memory-bank v2) -->
## UMS Memory Bank Overlay

This repository injects a Memory Bank document layer. Read
`../shared/UMS_MEMORY_BANK_CONTRACT.md` before writing the design document.

**Three paths (per the contract's "Brainstorming Paths" subsection).**
**architectural** and **bounded** both run the entry gate below in full and
both produce `design_<slug>.md`; they diverge only after approval — bounded
writes no plan and does not run subagent-driven-development. **spike** runs
the gate's eligibility, leftover-inventory and decision phases, creates a
branch only once it is to touch the tree, NEVER writes the pin, and writes
nothing under `proposals/`; when its answer turns into work to keep, the
request is reclassified and the gate completes. "This wants an architect's
review" is itself an architectural signal — upgrade the path (the ratchet
is one-way); the Architect Review Gate below is never offered on bounded.

Where an adjustment below names an upstream checklist item, it names it
**by phase name** — all three paths number their own items 1–5, so an
ordinal alone no longer identifies a step.

Adjustments to the checklist above:

- **The "Explore project context" phase (architectural and bounded paths)**
  additionally requires the seven steps below, in this order. Create a todo
  for them. Start as soon as the affected code area is identifiable; if it
  only becomes clear later in the dialog, run them then — but they MUST all
  complete before the design document is written. On a spike, run the
  **Entry gate** step always, and the **Choose the base** / **Create the
  ticket branch** steps only once the spike is to touch the tree; the
  **Target-MB discovery**, **Jira ticket**, **Activation** and **Write the
  pin** steps are skipped — a spike pins nothing (contract, "Brainstorming
  Paths"). Each step does only what it can do at its
  point in the sequence, and only the **Create the ticket branch**, **Activation**
  and **Write the pin** steps touch the working tree.

  1. **Entry gate.** Run the entry gate of the contract's "Workspace Discipline"
     section — the whole gate, not a part of it. Its eligibility, leftover-inventory
     and park-or-discard phases belong here; its intent and pin-write phases are
     the **Create the ticket branch** and **Write the pin** steps below. Skipping
     the inventory and that one park-or-discard decision is the failure mode to
     avoid: it leaves the tree dirty, and the `git switch -c` of the
     **Create the ticket branch** step is then forbidden outright (no auto-stash, no
     switching through `git stash`), which either strands the work or rides foreign
     uncommitted changes onto the ticket branch and into the design commit.
     **Offer park only where park can act:** `mb-park` needs the current branch to
     carry a pin, so on an IDLE branch — typically the base, which is where a new
     ticket starts — it stops with „Není co parkovat" and commits nothing. There the
     one decision is **commit them** or **discard**, and on the base „commit them"
     never means onto the base: a commit there is unpublishable (shared branch),
     `mb-park` refuses it, and the **Create the ticket branch** step's
     `git switch -c ... <chosen base>` has an explicit start point, so it would not
     travel — the work would be stranded. Keep them uncommitted, let them ride into
     the **Create the ticket branch** step's switch (an uncommitted change travels
     with the switch on its own) and commit them on the ticket branch; with no ticket
     branch to create, commit them on a scratch branch. That is the one accounted-for
     exception to the **Create the ticket branch** step's clean tree — it holds only
     for leftovers this inventory just named and the user consciously kept. On a
     non-base IDLE branch (a harvested ticket branch) committing on that branch is
     fine. Either way the leftovers still have to be resolved. Within eligibility, a
     **verified publication guarantee for THIS session is a fail-closed
     precondition** — the hook must exist, be at least v2, and reject a synthetic
     protected-branch line run in this session's own environment; a line that
     passes means the agent-session marker is absent and the hook disables itself
     here. A failing `git fetch origin` is a hard failure too; a missing
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
     path, and read it as design seed — but move nothing.** The move is the
     **Activation** step, because it can only happen once the ticket branch
     exists. This whole step writes nothing to the working tree.
  3. **Jira ticket:** ask for it (one question; "none" is a valid answer; skip when
     a draft matched in the **Target-MB discovery** step already names it).
     **Then re-run the index with the
     intent declared** (`-Jira <ticket>` and `-Slug <slug>` when known) for the
     cross-clone collision check: a KOLIZE AKTIVNÍ PRÁCE finding — the same slug or
     the same Jira ticket already active on a foreign branch — is a fail-closed STOP
     (exit 2), while foreign active work on OTHER tickets is normal parallel
     operation and never stops anything. Declaring the intent is what makes the
     check work here at all: the design document does not exist yet, so with an
     empty local set an undeclared run cannot tell a collision from ordinary
     parallel work.
  4. **Choose the base** — the entry gate's intent phase decision, per the
     contract's "Repository Configuration" section (the effective base and the
     invariant that an integration branch is always a protected branch). Build the
     candidate list mechanically, never by hand — `<mb-shared>` is this layer's
     `skills/shared/` directory, the sibling of the skill directory this overlay is
     injected into, the same directory that holds `UMS_MEMORY_BANK_CONTRACT.md`:

     ```powershell
     . <mb-shared>/scripts/Get-UmsBaseCandidates.ps1
     Get-UmsBaseCandidates (git rev-parse --show-toplevel) (git branch --show-current)
     ```

     Present them in that order (default, current, rest) with `baseRef` as the
     recommendation and let the USER decide. With a linked and reachable Jira
     ticket, a version named in its text orders the list further; an unreachable
     Jira skips that signal with a one-line note. A base outside
     `protectedBranches` is the contract's fail-closed STOP — follow its ordered
     remedy and do NOT continue with an unprotected base.
  5. **Create the ticket branch** — the entry gate's intent phase — with the tree
     clean, or carrying only the leftovers the **Entry gate** step decided to
     commit here (nothing
     else), per the rule stated in the "Write design doc" adjustment below:
     `git switch -c <TICKET>-<kebab-slug> <chosen base>` after a
     `git fetch origin`, always with the explicit start point. When the
     **Jira ticket** step answered
     "none", the kebab slug alone names the branch — the ticket code is part of the
     name only when there is one (contract, "Active Work Item (Design + Plan Pair)",
     branch name derived from the slug). Test the creation postcondition here and
     only here: `proposals/active/` empty or absent and `context.md` IDLE.
  6. **Activation**, only when the **Target-MB discovery** step matched a
     queued draft: now move ALL files of
     its slug from `proposals/next/` to `active/` — on the ticket branch, where the
     work item belongs — renaming a legacy `proposal_*` draft to `design_<slug>.md`
     during the move (the only permitted legacy conversion), and reuse its slug and
     ticket. A draft that lives on a foreign branch is taken over by blob copy per
     the contract's "Cross-Branch Visibility" section, never a cherry-pick, and
     records `**Převzato z:** <branch>@<sha>` in its header.
  7. **Write the pin** — the entry gate's pin-write phase: `Target MB Pin`, `Jira`,
     `Work item` slug and `Started` into `memory-bank/context.md` — and **DECIDE**
     the `Báze:` line from the **Choose the base** step (contract, `context.md`
     Schema & Writers): write it when the chosen base differs from `baseRef`,
     **DELETE** any line already in the file when it does not. Local point: a
     `Báze:` line you find here is one this work item never wrote, so leaving it
     in place is not tidiness deferred — it is this work item silently adopting a
     base nobody chose for it. When the remedy of the **Choose the base**
     step changed `ums-repo.json`, that change is still uncommitted and rode here
     with `switch -c`; commit it together with the pin. Then read
     `<PLAN_MB>/brief.md`, `architecture.md`, `tech.md` and `playbook.md` (those
     that exist; legacy shape per Memory Bank Document Set) as design context —
     `playbook.md` is prescriptive and BINDS the work, the rest is current-state
     reference.
- **The "Write design doc" phase (architectural path; on bounded, writing
  the chat-approved design)**: save to
  `<PLAN_MB>/proposals/active/design_<slug>.md` (Czech content, header per
  the contract's "Superpowers Document Placement" section) instead of the
  default `docs/superpowers/specs/` path. **By the time you reach this phase the
  ticket branch already exists** — the **Create the ticket branch** step
  above created it — so here you only confirm you are on it and not on the base. **Do
  not re-create it and do not re-test the creation postcondition below:** your own
  pin and your own `proposals/active/` entry are expected to be present by now,
  and ACTIVE state you wrote yourself is not a finding to report and not a reason
  to delete anything.

  The rule that governed that creation, invoked by the **Create the ticket
  branch** step above and stated here in full: **always with an explicit starting
  point**, `git switch -c <TICKET>-<kebab-slug> <chosen base>` after a
  `git fetch origin`, where the chosen base defaults to `baseRef` from
  `<CTX_DIR>/ums-repo.json` (the contract's "Repository Configuration" section)
  unless the user picked a different protected branch in the **Choose the
  base** step above. The implicit form, without a starting point, branches off whatever
  happens to be checked out: run on a foreign ticket branch it pulls that
  branch's pin and its active pair into your history. The local base branch is
  not used in a ticket workspace — the chosen base is the only base that counts —
  and git worktrees are banned in this repository (branch-in-place).
  **Postcondition, tested at creation time and only then:** `proposals/active/` is
  empty or absent and `context.md` is IDLE. If it is not, STOP, delete the
  just-created branch and repeat; an ACTIVE base means a work item was
  integrated without a harvest, and that is the finding to
  report (the contract's "Cross-Branch Visibility" section).

  After committing the design, push the branch — the agent pushes its OWN ticket
  branch after every commit, always announcing the branch and the outgoing commits
  (Publication Contract). If this is the branch's FIRST publication, push with
  `git push -u origin <branch>`, never bare — per the contract's first-publication
  rule (Publication Contract): `switch -c` left the upstream pointing at the base.

  On the **bounded** path the design was approved IN CHAT; after that
  approval write the same content to
  `<PLAN_MB>/proposals/active/design_<slug>.md` (same header, body scaled
  to the change), commit and push — and do NOT wait for a second approval
  round: the bounded path has no written-spec review phase. This OVERRIDES
  the upstream bounded rule "No spec file, no implementation plan document"
  in its first half only: the design file IS written here (it is the durable
  Memory Bank record the harvest archives); "no implementation plan
  document" continues to hold.
- **Agentic opposition offer (architectural path only — after the user
  approves the written spec, BEFORE the Architect Review Gate offer):**
  offer an independent agentic opposition of the design per the contract's
  "Agentic Design Opposition (oponentura)" section — an offer, never an
  automatic run. On acceptance: dispatch the opponent (most capable model,
  highest exposed reasoning effort, both explicit), triage the findings
  per that section (uncontested → fold into the design; contested or
  scope-changing → one BATCHED dialog with the user; wrong → reject with
  the reason), then present the Czech closing summary and have the user
  RE-APPROVE the changed passages. Only after that re-approval is the
  design finally approved — the Architect Review Gate offer and the Epic
  Backflow check below follow it. On the **bounded** path the offer does
  not run (the design was approved in chat; standalone opposition stays
  available on demand via `mb-architect-review` oppose mode) — a named
  deferral, like the Epic Backflow one below.
- **Architect Review Gate (architectural path only — after the user approves the
  written spec, before the transition to implementation):** when a Jira ticket
  is linked, ALWAYS offer a design review by a human architect after the
  user approves the spec — with your own yes/no recommendation based on
  non-triviality (new component or service, architecture/contract changes,
  cross-project impact, DB migration, security impact). If accepted, invoke
  the `mb-architect-review` skill (request mode) and END the workflow here —
  work resumes later via its resume mode. If declined, or when no ticket is
  linked, proceed to the transition to implementation as usual. **This amends
  the path-bound terminal states above:** architectural — in this repository
  `mb-architect-review` may follow brainstorming; writing-plans remains the
  only *implementation* successor. Bounded — implementation proceeds directly
  through the normal development workflow, but the work item still ends in
  finishing-a-development-branch: it has a pin and a design, so the Harvest
  Gate and the integration path apply to it exactly as to architectural work.
  Spike — a reported recommendation, no MB artifact and no finishing.
- **Epic Backflow check (after the design is finally approved):** per the
  contract's "Epic Backflow (design → epic)" section. When the Architect
  Review Gate above hands the work off, the design is not finally approved
  yet — the check then belongs to `mb-architect-review` resume, not here; run
  it here only when no review takes place (no ticket → the whole step is
  skipped silently; review declined but ticket linked → run it after the
  user's spec approval). On a finding concerning this ticket: queue the
  ledger note, then offer the inline elaboration window or deferral — never
  launch elaboration unasked. Fail-open: an oracle failure or missing Jira
  skips the step with a one-line announcement.
  On the **bounded** path this check does NOT run for now — bounded is by
  definition a bounded change of an existing flow, so a scope or dependency
  shift of its ticket is unlikely; `mb-epic-graph -Check` stays available on
  demand. This is a named deferral, not an omission.
- While `memory-bank/context.md` contains a
  `- **Review:** design-review requested` line, the workflow is parked: do
  NOT invoke writing-plans; the correct continuation is `mb-architect-review`
  (resume mode).
- The design document and all user-facing communication are in Czech.
<!-- UMS-OVERLAY END -->
