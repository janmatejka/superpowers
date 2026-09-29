<!-- TARGET: subagent-driven-development/SKILL.md -->
<!-- ANCHOR: EOF -->
<!-- ASSERT: Four things stop you, and only these: an irreversible or destructive -->
<!-- ASSERT: them. The spec is the binding authority, the plan is its argument, and your -->
<!-- ASSERT: todo per task. If the plan names a Spec, read that too: the spec is the -->

<!-- UMS-OVERLAY BEGIN (ums-memory-bank v2) -->
## UMS Memory Bank Overlay

> Contract core: [UMS_MEMORY_BANK_CONTRACT](../shared/UMS_MEMORY_BANK_CONTRACT.md) · References: [playbook-contract.md](../shared/contract/playbook-contract.md), [now-block.md](../shared/contract/now-block.md), [session-intent-baton.md](../shared/contract/session-intent-baton.md), [repository-configuration.md](../shared/contract/repository-configuration.md). Read the named references before acting.

The rules of plan execution live in the core and in those references; this
block cites them and adds only what is specific to dispatching subagents.

- **Model selection:** follow the Model Selection section above — UMS pins no
  models. Set the model explicitly on EVERY dispatch; summarization-only
  dispatches (Czech commit messages, Jira comments, harvest notes, read-only
  scans) use the cheapest capable tier (contract, "Dispatch Model Policy").
- **Rulings and STOPs:** rule on conflicts per the SKILL text above. This
  layer's fail-closed STOPs fall within the four classes, and merging the
  effective base into the agent's OWN ticket branch is not a "side effect
  outside this worktree" and is never put to the user (contract, "Fail-Closed Behavior") — paragraph "Rulings and these STOPs".
- **A fifth stop class: context rotation.** The SKILL text above says "Four
  things stop you, **and only these**". In this repository that sentence is
  narrowed: it enumerates the ESCALATION stops (stop, ask, continue in this
  session); context rotation is a HANDOFF stop (this session ends, a fresh one
  continues), additive and leaving the four untouched. When it is permitted,
  what to write and how a resumed session proceeds is defined in (contract/session-intent-baton.md, "The context-rotation stop");
  its `Instruction:` line names `subagent-driven-development`.
- **Authority and the Spec field:** where the upstream text above says "the
  spec is the binding authority, the plan is its argument", read it with the
  contract's subject split (contract, "Active Work Item (Design + Plan Pair)"):
  WHAT should be built is the design's to decide, HOW and in what order is the
  plan's. The plan header carries `**Spec:** [design_<slug>.md](design_<slug>.md)`,
  so "if the plan names a Spec, read that too" is satisfied and rulings are not
  provisional; tolerate the legacy `**Návrh:**` alias in plans written under
  contract ≤ v2.8.
- **Batched dispatches:** the playbook chain path (Playbook below) is attached
  to a batch dispatch exactly as to a single-task dispatch, and one batch report
  ends with ONE `## Playbook candidates` section covering the whole batch.
- **The `NOW` block:** the progress ledger opens with it; write it before the
  first dispatch and rewrite it at the subagent-driven-development points of (contract/now-block.md, "When the block is rewritten").
- **Finish:** deleting the plan workspace leaves the playbook-candidate file in
  place (contract/playbook-contract.md, "Playbook Contract").
- **Language:** dispatch prompts, task briefs, implementer/reviewer reports and
  the progress ledger stay English. Commit messages produced by implementer
  subagents MUST be Czech — state this in every implementer dispatch.
  User-facing summaries and the final "Rulings I made" list are Czech (contract, "Language Contract").
- **Isolation:** git worktrees are banned here (contract, "Worktree Policy"); the
  using-git-worktrees step resolves to branch-in-place in the existing working
  directory, on a feature branch, in the workspace the user chose (contract/workspace-discipline.md, "Workspace Discipline").
  Where the upstream text above says "outside this worktree", read "outside
  this clone/workspace".
- **Playbook:** resolve the playbook chain of `PLAN_MB` first (contract/playbook-contract.md, "Playbook chain"):
  dot-source `shared/scripts/Get-UmsPlaybookChain.ps1` and run
  `Get-UmsPlaybookChain <MB_ROOT> <Target MB Pin> -Out` (the second argument is
  the repository-relative `memory-bank/` directory). Attach the returned
  `OutPath` to EVERY implementer dispatch alongside the task brief, introduced
  as "procedures that bind this project — follow them" — the path, never the
  inlined content; when the chain has no segment, say so in the dispatch. Take
  the baseline build and test procedures from the chain's
  `Když stavíš nebo spouštíš testy` sections (a legacy segment carries them
  elsewhere).
- **Playbook candidates:** every implementer dispatch requires the report to
  END with a `## Playbook candidates` section in the candidate format of (contract/playbook-contract.md, "Playbook Contract");
  an empty section is legitimate and common. As controller you are that
  section's COPYING writer: run `Find-UmsPlaybookMatch` per entry and copy
  confirmed entries verbatim into the current slug's candidate file under that
  section's file rules; name a dropped duplicate in your report instead. Do not
  rephrase entries; the playbook gate presents them to the user.
- **Base sync:** before the first task of the plan — a phase boundary — fetch
  and merge the effective base into the ticket branch, assess the intersection
  and verify per (contract, "Base Sync & Drift Detection"); never in the
  middle of a task. The mandatory baseline build/test check runs on the merged
  tree, before the first dispatch.
- **Ranges against the base:** where the upstream text above writes
  `git merge-base main HEAD` — the final review's `MERGE_BASE`, the
  intersection sets — cut the range from the effective base (contract/repository-configuration.md, "Repository Configuration").
- **Publication:** push the OWN ticket branch after every commit, announcing the
  branch and the outgoing commits (contract, "Publication Contract"); no other
  branch is pushed during execution. Even onto an epic line — a shared branch
  the agent may push — the integration push belongs to finishing, after the
  manager's `go` (contract/epic-line.md, "Integration after the manager's go").
<!-- UMS-OVERLAY END -->
