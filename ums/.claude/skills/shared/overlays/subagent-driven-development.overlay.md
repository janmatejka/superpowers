<!-- TARGET: subagent-driven-development/SKILL.md -->
<!-- ANCHOR: EOF -->

<!-- UMS-OVERLAY BEGIN (ums-memory-bank v2) -->
## UMS Memory Bank Overlay

- **Model selection:** follow the Model Selection section above — UMS pins no
  models. One UMS guard (see `../shared/UMS_MEMORY_BANK_CONTRACT.md`, "Dispatch
  Model Policy"): summarization-only dispatches (Czech commit messages, Jira
  comments, harvest notes) use the cheapest capable tier. Always set the model
  explicitly on every dispatch.
- **Language:** dispatch prompts, task briefs, implementer/reviewer reports
  and the progress ledger stay English. Commit messages produced by
  implementer subagents MUST be Czech — state this in every implementer
  dispatch. User-facing summaries are Czech.
- **Isolation:** git worktrees are banned in this repository (see CLAUDE.md).
  The using-git-worktrees step resolves to branch-in-place: ensure you are on
  a feature branch (never main/master without explicit consent) and continue
  in the existing working directory.
<!-- UMS-OVERLAY END -->
