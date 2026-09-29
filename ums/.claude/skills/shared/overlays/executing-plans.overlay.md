<!-- TARGET: executing-plans/SKILL.md -->
<!-- ANCHOR: EOF -->
<!-- ASSERT: Four things stop you, and only these: an irreversible or destructive -->
<!-- ASSERT: The workspace and ledger are shared with superpowers:subagent-driven-development -->

<!-- UMS-OVERLAY BEGIN (ums-memory-bank v2) -->
## UMS Memory Bank Overlay

> Contract core: [UMS_MEMORY_BANK_CONTRACT](../shared/UMS_MEMORY_BANK_CONTRACT.md) · References: [playbook-contract.md](../shared/contract/playbook-contract.md), [now-block.md](../shared/contract/now-block.md), [session-intent-baton.md](../shared/contract/session-intent-baton.md), [repository-configuration.md](../shared/contract/repository-configuration.md). Read the named references before acting.

The rules of plan execution live in the core and in those references — the
same set subagent-driven-development cites; this block cites them and adds
only what is specific to executing the plan yourself (Native execution).

- **A fifth stop class: context rotation.** The SKILL text above says "Four
  things stop you, **and only these**". In this repository that sentence is
  narrowed: it enumerates the ESCALATION stops (stop, ask, continue in this
  session); context rotation is a HANDOFF stop (this session ends, a fresh one
  continues), additive and leaving the four untouched. When it is permitted —
  after `task-done` and before the next `task-start` — what to write and how a
  resumed session proceeds is defined in (contract/session-intent-baton.md, "The context-rotation stop");
  its `Instruction:` line names `executing-plans`.
- **Rulings and STOPs:** rule on conflicts per the SKILL text above. This
  layer's fail-closed STOPs fall within the four classes, and merging the
  effective base into the agent's OWN ticket branch is not a "side effect
  outside this worktree" and is never put to the user (contract, "Fail-Closed Behavior") — paragraph "Rulings and these STOPs".
- **Authority and the Spec field:** where the upstream text above says the
  spec is the authority the plan argues from, read it with the contract's
  subject split (contract, "Active Work Item (Design + Plan Pair)"): WHAT is
  the design's to decide, HOW and in what order is the plan's. The plan header
  names the design as `**Spec:**`.
- **The `NOW` block:** the ledger opens with it; write it before Task 1 and
  rewrite it at the executing-plans (Native) points of (contract/now-block.md, "When the block is rewritten").
- **Playbook:** there is no implementer to attach it to — resolve the playbook
  chain of `PLAN_MB` yourself (contract/playbook-contract.md, "Playbook chain"):
  dot-source `shared/scripts/Get-UmsPlaybookChain.ps1`, run
  `Get-UmsPlaybookChain <MB_ROOT> <Target MB Pin> -Out` (the second argument is
  the repository-relative `memory-bank/` directory) and READ the returned
  `OutPath` at the start of EVERY session, before the first task that session
  works (Task 1, or the `Next task` of a resumed session), and again after a
  compaction: its procedures bind every task you work, and a session that has
  not read it in its own context works without them. Unlike the base sync and
  the baseline, this reading is per session, not per plan. Take the baseline
  build and test commands (run before Task 1 of the plan only) from the chain's
  `Když stavíš nebo spouštíš testy` sections (a legacy segment carries them
  elsewhere).
- **Playbook candidates:** there is no implementer report to copy from — after
  each `task-done`, write the procedural knowledge the task taught you (not already
  in the brief or the chain) into the current slug's candidate file yourself,
  in the candidate format, running `Find-UmsPlaybookMatch` per entry, under the
  file rules of (contract/playbook-contract.md, "Playbook Contract"). A task
  that taught nothing new writes nothing.
- **Final review:** set the reviewer's model explicitly (contract, "Dispatch Model Policy").
  Build the package as
  `../subagent-driven-development/scripts/review-package PLAN_FILE <MERGE_BASE> HEAD`
  with `MERGE_BASE` = `git merge-base <effective base> HEAD`, never the
  `git merge-base main HEAD` the text above gives as an example (contract/repository-configuration.md, "Repository Configuration").
- **Language:** the ledger, `Ruling:` lines and candidate entries stay English.
  Your own commit messages are Czech; the final message, its "Rulings I made"
  and "Deferred minors" lists and every report to the user are Czech (contract, "Language Contract").
- **Isolation:** git worktrees are banned here (contract, "Worktree Policy"). The
  Setup instruction "use superpowers:using-git-worktrees to create one" resolves
  to branch-in-place: a feature branch in the existing working directory, in
  the workspace the user chose (contract/workspace-discipline.md, "Workspace Discipline").
  Where the upstream text above says "outside this worktree", read "outside
  this clone/workspace". On a harness with no mechanical worktree ban this text
  is the only enforcement.
- **Base sync:** before Task 1 of the plan — a phase boundary — fetch and merge
  the effective base into the ticket branch, assess the intersection and verify
  per (contract, "Base Sync & Drift Detection"); never in the middle of a task.
  The mandatory baseline build/test check runs on the merged tree, before
  Task 1.
- **Publication:** push the OWN ticket branch after every commit — each task's
  commits, the base-merge commit, the fix-pass commits — announcing the branch
  and the outgoing commits (contract, "Publication Contract"); shared branches
  are never pushed by the agent.
- **Finish:** deleting the plan workspace leaves the playbook-candidate file in
  place (contract/playbook-contract.md, "Playbook Contract").
<!-- UMS-OVERLAY END -->
