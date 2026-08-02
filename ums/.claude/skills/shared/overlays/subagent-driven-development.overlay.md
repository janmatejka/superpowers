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
- **Playbook:** resolve the target Memory Bank's procedure document FIRST —
  `<PLAN_MB>/playbook.md` when it exists, otherwise `<PLAN_MB>/tasks.md` when
  THAT exists (legacy shape, contract, Memory Bank Document Set), otherwise
  neither. Attach the resolved path to EVERY implementer dispatch alongside the
  task brief, introduced as "procedures that bind this project — follow them".
  When neither file exists, say so in the dispatch instead of omitting the line.
  Take the build and test procedures for the baseline check before the first
  task from the same resolved file.
- **Playbook candidates:** every implementer dispatch requires the report to
  end with a `## Playbook candidates` section — procedural knowledge learned
  while doing the task that was not already in the brief or the playbook, each
  entry carrying `Tried` / `Happened` / `Procedure`. An empty section is
  legitimate and common; an entry without `Happened` is not written. As
  controller, COPY confirmed entries verbatim into
  `<MB_ROOT>/.superpowers/playbook-candidates.md` (first line
  `# Playbook candidates — work item: <slug>`; a foreign slug means the file
  is OVERWRITTEN — its path is fixed, so there is no separate file to start
  (see `../shared/UMS_MEMORY_BANK_CONTRACT.md`, "Playbook Contract")). Do not
  rephrase them; the playbook gate presents them to the user.
- **Publication:** before dispatching the first task, publish the branch with the
  committed plan (Publication Contract, publication point 2): an announced push
  of your own ticket branch, alongside the baseline build/test check. Shared
  branches are never pushed by the agent.
<!-- UMS-OVERLAY END -->
