<!-- TARGET: subagent-driven-development/SKILL.md -->
<!-- ANCHOR: EOF -->
<!-- ASSERT: Four things stop you, and only these: an irreversible or destructive -->
<!-- ASSERT: them. The spec is the binding authority, the plan is its argument, and your -->
<!-- ASSERT: todo per task. If the plan names a Spec, read that too: the spec is the -->

<!-- UMS-OVERLAY BEGIN (ums-memory-bank v2) -->
## UMS Memory Bank Overlay

- **Model selection:** follow the Model Selection section above — UMS pins no
  models. One UMS guard (see `../shared/UMS_MEMORY_BANK_CONTRACT.md`, "Dispatch
  Model Policy"): summarization-only dispatches (Czech commit messages, Jira
  comments, harvest notes) use the cheapest capable tier. Always set the model
  explicitly on every dispatch.
- **Rulings and STOPs:** rule on conflicts per the SKILL text above; this
  layer's fail-closed STOPs already fall within the four stop classes — see
  `../shared/UMS_MEMORY_BANK_CONTRACT.md`, section "Fail-Closed Behavior",
  paragraph "Rulings and these STOPs". Locally: merging the effective base
  into the agent's OWN ticket branch is NOT the "side effect outside this
  worktree" the four classes mean — it is mandatory at phase boundaries
  (Base sync below) and is never put to the user.
- **A fifth stop class: context rotation.** The SKILL text above says "Four
  things stop you, **and only these**". In this repository there is a fifth, and
  that sentence is hereby narrowed: it enumerates the ESCALATION stops — the ones
  where you stop and ASK, then continue in this same session. Context rotation is
  a HANDOFF stop: this session ends and a fresh one continues. The layer already
  has one (the Architect Review Gate). The four are untouched and unweakened;
  this is additive.

  Permitted **only at a task boundary** — after the completion line is appended
  to the ledger and the todo is marked complete, and before the next dispatch.
  Nowhere else: mid-task the on-disk state is incomplete and a rotation discards
  a live review cycle.

  At that boundary, when the remaining context looks insufficient for another
  task: write the session intent baton (contract, "Session Intent Baton") with
  `Kind: plan-resume`, the plan path, the ledger path, the branch, the slug, the
  number of the next incomplete task and the required `Instruction:` line naming
  subagent-driven-development; append a plain note to the ledger that the session
  was rotated here (a note, NOT a `Ruling:` — no conflict was decided); report in
  Czech; and stop with the single instruction to type `/clear`.

  **`Instruction` is REQUIRED and its value is VALIDATED** (contract, same
  subsection): the reader accepts it only when it names a skill that exists in
  this deployment and stays under a short length ceiling. A baton written
  without it — or with a value that names no skill — is rejected as stale and
  the handoff is silently lost.

  **This is a judgement call, not a measurement.** Hook input carries no reliable
  token-budget field; do not build a threshold detector and do not claim one
  exists. The operator's own meter overrides you in BOTH directions.

  **Writer precondition:** per the contract subsection, write no baton where no
  consumer will read it — report instead that the intent will not be delivered
  automatically.

  **A resumed session does NOT re-run the base sync or the baseline.** The Base
  sync bullet below says "before dispatching the first task"; that means task 1
  of the PLAN, not task 1 of a session. `Next task: N` in the baton is what tells
  a fresh session which it is. Reading it the other way would make a rotation a
  direct trigger of the mid-phase base merge that same bullet forbids.
- **Authority and the Spec field:** where the upstream text above says "the
  spec is the binding authority, the plan is its argument", read it with the
  contract's subject split — a conflict between the design and the plan is
  resolved per the contract's "Active Work Item (Design + Plan Pair)"
  section: WHAT should be built is the design's to decide, HOW and in what
  order is the plan's (the plan was written against the code). The
  plan header carries `**Spec:** [design_<slug>.md](design_<slug>.md)`, so
  the upstream instruction "if the plan names a Spec, read that too" is
  satisfied and rulings are not provisional; tolerate the legacy
  `**Návrh:**` alias in plans written under contract ≤ v2.8.
- **Batched dispatches:** the resolved procedure document (Playbook below)
  is attached to a batch dispatch exactly as to a single-task dispatch, and
  one batch report ends with ONE `## Playbook candidates` section covering
  the whole batch.
- **Rulings vs playbook candidates:** a ruling is a decision, a candidate is
  a procedure — a ruling becomes a candidate only when it carries `Happened`
  evidence reaching beyond this work item (contract, "Playbook Contract").
- **Finish:** `rm -rf <workspace>` removes `.superpowers/sdd/<plan-basename>/`
  only. The playbook-candidate file lives in
  `.superpowers/playbook-candidates/`, OUTSIDE the plan workspace, and
  survives the workspace deletion — only the harvest removes it (contract,
  "Playbook Contract").
- **Language:** dispatch prompts, task briefs, implementer/reviewer reports
  and the progress ledger stay English. Commit messages produced by
  implementer subagents MUST be Czech — state this in every implementer
  dispatch. User-facing summaries are Czech.
  `Ruling:` ledger lines stay English; the final "Rulings I made" list is
  user-facing and therefore Czech (contract, "Language Contract").
- **Isolation:** git worktrees are banned in this repository (see CLAUDE.md).
  The using-git-worktrees step resolves to branch-in-place: ensure you are on
  a feature branch (never main/master without explicit consent) and continue
  in the existing working directory. Isolation comes from the workspace, and the
  **workspace is the user's choice** — the user creates it and picks it; the
  session runs in the workspace where the work already is and never provisions
  another one (contract, "Workspace Discipline"). "One session per workspace",
  including the pool carve-out, is that same section's own rule — see it by
  name (contract, "Workspace Discipline", "One session per workspace") rather
  than a restatement here.
  Where the upstream text above says "outside this worktree", read "outside
  this clone/workspace" — worktrees are banned here.
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
  `git fetch origin` and then `git merge <effective base>` on the ticket branch
  (the effective base per the contract's "Repository Configuration" section: the
  `Báze:` line of `context.md`, else `baseRef` from `<CTX_DIR>/ums-repo.json`),
  followed by the intersection assessment and the verification that follows from it
  per the contract's "Base Sync & Drift Detection" section.
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
