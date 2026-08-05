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
  in the existing working directory. Isolation comes from the workspace, and the
  **workspace is the user's choice** — the user creates it and picks it; the
  session runs in the workspace where the work already is and never provisions
  another one (contract, "Workspace Discipline"). One session per workspace: work
  on several tickets is interleaved, not parallel.
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
  entry carrying the three mandatory fields `Tried` / `Happened` / `Procedure`,
  plus two optional fields, added only when they apply: `Target MB` (state its
  path when the harvest spans several Memory Banks and this procedure belongs
  to one other than `PLAN_MB`) and `Corrects` (name the existing `playbook.md`
  entry when this procedure contradicts one already there). An empty section
  is legitimate and common; an entry without `Happened` is not written. As
  controller, COPY confirmed entries verbatim into
  `<MB_ROOT>/.superpowers/playbook-candidates/<slug>.md` — **one file per
  work-item slug**, first line `# Playbook candidates — work item: <slug>`. Only
  the CURRENT slug's file may be replaced, and only while it is **untracked**
  (ordinary git-ignored scratch, left over from a slug whose work finished or was
  abandoned); a **tracked** file is parked evidence, so APPEND to it and leave its
  removal to the harvest. Files of FOREIGN slugs have their own paths and are
  never overwritten and never deleted (see
  `../shared/UMS_MEMORY_BANK_CONTRACT.md`, "Playbook Contract"). Do not
  rephrase entries; the playbook gate presents them to the user.
- **Base sync:** before dispatching the first task — a phase boundary — run
  `git fetch origin` and then `git merge origin/<baseRef>` on the ticket branch
  (`baseRef` from `<CTX_DIR>/ums-repo.json`, contract section "Repository
  Configuration"), followed by the intersection assessment and the verification
  that follows from it per the contract's "Base Sync & Drift Detection" section.
  **Never merge the base in the middle of a task** — a task that starts on one
  tree and finishes on another cannot be reviewed against its own brief. The
  mandatory baseline build/test check before the first dispatch stays mandatory,
  and it runs on the merged tree.
- **Publication:** the agent pushes its OWN ticket branch **after every commit**,
  always announcing the branch and the outgoing commits (Publication Contract).
  That covers the commit carrying the implementation plan before the first
  dispatch, the base-merge commit, and an implementer's commit for a task that
  verified green. A commit that is not pushed is work only this workspace can
  see. Shared branches are never pushed by the agent.
<!-- UMS-OVERLAY END -->
