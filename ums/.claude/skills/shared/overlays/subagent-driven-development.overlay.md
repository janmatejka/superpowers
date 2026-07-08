<!-- TARGET: subagent-driven-development/SKILL.md -->
<!-- ANCHOR: EOF -->

<!-- UMS-OVERLAY BEGIN (ums-memory-bank v2) -->
## UMS Memory Bank Overlay

- **Model routing:** `memory-bank/context.md` → `## Model Routing` maps roles
  to models (see `../shared/UMS_MEMORY_BANK_CONTRACT.md`, "Model Routing
  Consumption"). Role map: implementer and fix subagents → Worker Model; task
  reviewer and final whole-branch reviewer → Reviewer Model;
  summarization-only dispatches (commit messages, Jira comments, harvest
  notes) → Summarizer Model. When the block is present, the role's model IS
  the dispatch model; the Model Selection tiering above applies only when the
  block is absent or the role's value is `runtime-default`. Honor
  `Fallback Policy` (missing = `downgrade`).
- **Language:** dispatch prompts, task briefs, implementer/reviewer reports
  and the progress ledger stay English. Commit messages produced by
  implementer subagents MUST be Czech — state this in every implementer
  dispatch. User-facing summaries are Czech.
- **Isolation:** git worktrees are banned in this repository (see CLAUDE.md).
  The using-git-worktrees step resolves to branch-in-place: ensure you are on
  a feature branch (never main/master without explicit consent) and continue
  in the existing working directory.
<!-- UMS-OVERLAY END -->
