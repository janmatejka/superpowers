---
name: mb-architect-review
description: Design review by a human architect via a Jira ticket — hand off an approved design (request), assess it as the architect (respond), or take the ticket back and continue (resume). Use for "předej návrh architektovi", "posuď design/návrh v UMS-XXXX", "převezmi UMS-XXXX po design review", "design review tiketu UMS-XXXX", or when the brainstorming Architect Review Gate offers a review. Accepts an optional ticket key and switches the repo to the ticket branch (branch sync).
license: MIT
metadata:
  author: UMS Project
  version: "1.2"
---

> Follow [UMS_MEMORY_BANK_CONTRACT](../shared/UMS_MEMORY_BANK_CONTRACT.md) —
> especially "Architect Review Gate" (normative for this skill), "Base Sync &
> Drift Detection", "Repository Configuration", "Active Work
> Item (Design + Plan Pair)" and "`context.md` Schema & Writers". Bitbucket
> link mechanics (git preconditions, SHA stabilization, commit-pinned URLs,
> description-line refresh) are reused from
> [mb-jira-update](../mb-jira-update/SKILL.md) §5–7b — do not re-derive them.

# Command: mb-architect-review

**Action:** Mediate a design review by a human architect through a Jira
ticket. Three modes by role: request (resolver → architect), respond
(architect), resume (resolver takes the ticket back).
**Language:** all user-facing output, Jira comments and persistent artifacts
in Czech; this skill body and dispatch prompts are English.

## Mode Detection

The user never names the mode. Determine it in this order:

1. **Explicit verb in the prompt:** "posuď / review / assess" → respond;
   "převezmi / pokračuj / take back" → resume; "předej / hand off" → request.
2. **Jira state + caller identity:** load the ticket and the caller
   (`atlassianUserInfo`), compare with the assignee and with the original
   resolver recorded in the request comment:
   - ticket NOT in "Design Review" → request (requires an active work item
     with an approved design; otherwise report there is nothing to review),
   - ticket in "Design Review" AND caller is assignee AND caller ≠ original
     resolver → respond,
   - ticket in "Design Review" AND caller is the original resolver → resume.
3. **Undecidable** (identity unavailable, contradictory state) → ask ONE
   question offering the three modes. Never pick silently.

Ticket key: from the user prompt (preferred for respond/resume — enables
branch sync); without it, read `context.md` on the current branch (typical
for request in the same session).

## Push Policy

Per the contract's **Publication Contract**: the ticket branch is the actor's
own branch, so the handoff push is announced (branch + outgoing commits), not
negotiated; shared branches are never pushed by the agent. One handoff = one
push. A refusal to publish stops the handoff — without the push the other side
sees neither the design nor `context.md`.

**The step order is what makes one push true:** on the resolver's side the base
merge comes FIRST and is not pushed on its own, the handoff state is committed
after it, and the single closing push publishes both commits together. That push
satisfies the publication rule for the merge commit as well — a base merge is
never left unpublished, it merely shares the push with the commit that follows it
inside the same handoff.

## Branch Sync (first step of respond and resume)

1. Resolve the ticket branch: request-comment branch name (authoritative) →
   remote branches whose name contains the ticket code
   (`git ls-remote --heads origin`, case-insensitive) → ask the user. Multiple
   ambiguous candidates: always ask. The branch name has the shape
   `<TICKET>-<kebab-slug>` (contract, Architect Review Gate), and the ticket
   code is recognised by `ticketPattern` from `<CTX_DIR>/ums-repo.json`
   (contract section "Repository Configuration") — never by a hardcoded prefix
   such as `UMS-`; without the configuration the built-in generic pattern
   applies. Existing branches carrying diacritics are NOT renamed.
2. Require a clean working tree; dirty = STOP and report (no auto-stash).
3. `git fetch origin` + checkout the ticket branch + fast-forward to origin.
   Diverged local branch = STOP and report.
4. Only now read `context.md` and the design document — they live on this
   branch.

**Branch sync itself never merges the base.** The base merge is asymmetric and
belongs to the RESOLVER's side only — request (step 3 there) and resume (step 3
there). **In respond mode the base is NEVER merged**, not even when the base has
moved meanwhile and not "just to assess a current tree": a base merge from both
sides produces two different merge commits over the same base, which is exactly
the divergence step 3 above stops on, so the resolver's next sync would STOP.
This is a prohibition, not a preference (contract, Architect Review Gate).

## Mode: request (resolver → architect)

1. **Preconditions (fail-closed):** `context.md` has a Jira ticket and a
   `Work item` slug (legacy `Proposal:` accepted); the design half of the
   active work item exists in `<PLAN_MB>/proposals/active/` — either style
   (`design_<slug>.md` or legacy `proposal_<slug>-design.md`). Stabilize the
   SHA per mb-jira-update §5–6 (uncommitted design → user-confirmed local
   commit, else STOP).
2. If still on the default branch, create the ticket branch in place
   (branch-in-place, always with an explicit starting point after a
   `git fetch origin`: `git switch -c <TICKET>-<kebab-slug> <baseRef>`, where
   `baseRef` comes from `<CTX_DIR>/ums-repo.json` — contract section
   "Repository Configuration"). Normally brainstorming created the branch
   already, so this is the exception, not the rule. Git worktrees are banned.
3. **Base sync — resolver side (phase boundary):** `git fetch origin`, then
   `git merge <baseRef>` on the ticket branch, then the intersection assessment
   and, where it applies, the offered verification, per the contract's "Base Sync
   & Drift Detection" section. In the design phase the role of the own set is
   played by the target areas named in the design document and nothing is built,
   so verification is purely an offer. Conflicts: resolve only in files this
   branch changed itself, a `context.md` conflict always targeted with
   `git checkout --ours` (never `merge -X ours` over the whole merge); anything
   else is a STOP. **Do not push the merge commit on its own** — step 5's single
   push publishes it together with the handoff state. The SHA stabilized in step 1
   stays valid: a merge adds a commit, it never rewrites the design commit, and a
   merge conflict on the same slug in `proposals/active/` is a STOP anyway, so the
   pinned content cannot change underneath the link. Do not re-stabilize it.
4. Write the `- **Review:** design-review requested YYYY-MM-DD` line into
   `## Active Work` of `context.md` and commit it (Czech commit message,
   `mb-git-commit` conventions).
5. **Publish the ticket branch** (announced push per the Publication
   Contract; the pinned design commit MUST be reachable on origin before step
   6 writes the link). The single push covers the base merge, the design and the
   `context.md` commit.
6. Publish a Czech comment to the ticket: a 10–15 line summary of the design
   (Cíl / Scope / klíčová rozhodnutí / rizika), the commit-pinned Bitbucket
   link to the design file (mb-jira-update §7), the **ticket branch name**,
   and the **original resolver** (accountId + displayName). Also refresh the
   `**Návrh (design):**` line in the ticket description (mb-jira-update §7b).
7. Architect selection: fetch assignable users of the project, offer the
   choice to the user (one question), set the chosen architect as assignee.
8. Transition the ticket to **"Design Review"**. Missing transition =
   fail-closed STOP: instruct the user to create the status (contract
   prerequisite).
9. Append to **AgentSessions** (customfield_11248):
   `YYYY-MM-DD <harness> <session-id> — design review request (<ticket>)`.
   Session id best-effort; undetectable → line without id + tell the user.
   Field unavailable → put the line into the comment from step 6 instead.
10. Announce (Czech): handed off to design review; work resumes via resume
    mode after the ticket returns, ideally in this session
    (`--resume <session-id>`). **The workflow stops here — do NOT invoke
    writing-plans.** `context.md` stays pinned; the two-actives guard
    deliberately blocks other work in this repo during the review.

## Mode: respond (architect)

1. Input: ticket key from the opening prompt. The ticket must be in
   "Design Review".
2. Read the ticket (description, request comment). Missing request comment
   (assigned manually) → fail-closed: ask the user for the return assignee
   and the ticket branch.
3. **Branch sync** (above) — **and no base merge here: respond is the
   architect's side of the asymmetry, so `git merge <baseRef>` is forbidden in
   this mode**, however stale the base looks. Assess the design on the tree the
   resolver handed over. Then read the design document and the target project's
   MB context (`brief.md`, `architecture.md`, `tech.md`, `playbook.md`) from the
   ticket branch.
4. Guide the architect through a structured assessment: goal and scope
   adequacy, technical approach, impacts, risks, alternatives. Help phrase
   the notes.
5. Publish the notes as a Czech comment, set the assignee back to the
   original resolver, and **set the flag** (Flagged/Impediment — team
   convention: "returned, attend to it"). Status stays "Design Review".
   If commits were made on the ticket branch, push them (announced push per
   Push Policy — the ticket branch is unprotected, so no approval is needed).

## Mode: resume (resolver takes back)

1. Input: ticket key from the opening prompt (or from `context.md` when
   already on the ticket branch). Expect "Design Review" + flag; missing
   flag → warn ("architekt zřejmě odpověděl ručně") and continue only after
   user confirmation.
2. **Branch sync** (above) — the architect may have pushed. Then read the
   architect's comments and summarize them in Czech.
3. **Base sync — resolver side (phase boundary):** `git fetch origin`, then
   `git merge <baseRef>` on the ticket branch, with the intersection assessment
   and the offered verification per the contract's "Base Sync & Drift Detection"
   section (same mechanics and same conflict rules as request step 3). Resume
   merges the base because it is the resolver's side; respond never does.
4. Transition the ticket to **"In Progress"**, clear the flag, remove the
   `Review:` line from `context.md` (commit with the next natural commit — that
   commit's push publishes the base merge with it). If no further commit follows
   shortly, push the base merge on its own: a base merge is never left
   unpublished.
5. Continue per workflow state: fold the notes into the design
   (brainstorming-style dialog over the architect's points, update the design
   file) → after user approval invoke writing-plans.

## Model Selection

Composing the request summary is summarization work — when delegated, dispatch
on the cheapest capable tier (contract, Dispatch Model Policy). Respond and
resume are interactive; no dispatch by default.
