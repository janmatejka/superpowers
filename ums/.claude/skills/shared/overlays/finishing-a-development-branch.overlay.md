<!-- TARGET: finishing-a-development-branch/SKILL.md -->
<!-- ANCHOR-BEFORE: ## Step 5: Execute Choice -->

<!-- UMS-OVERLAY BEGIN (ums-memory-bank v2) -->
## Step 4.5: UMS Harvest Gate (MANDATORY in this repository)

After the user chooses and BEFORE executing the choice:

- **Option 1, 2, or 3** (Merge Locally / Push and Create PR / Keep As-Is) →
  invoke the `mb-harvest` skill. It harvests knowledge into the affected
  Memory Bank documents, archives the design document to
  `proposals/completed/` (deleting the implementation plan), resets
  `memory-bank/context.md` to IDLE and offers `mb-jira-update`. Commit the
  resulting Memory Bank changes on this branch (Czech commit message), then
  execute the chosen option.
- **Option 1 (Merge Locally) additionally:** BEFORE the merge ask (Czech):
  „Aktualizovat lokální `develop` z `origin/develop`? (fetch + fast-forward,
  žádný push)". On yes: `git fetch origin`, then fast-forward the local base
  branch (create a tracking branch from `origin/develop` when it does not
  exist locally); fast-forward impossible (divergence) = STOP and report.
  **The answer to this question REPLACES the `git pull` of upstream Step 5
  Option 1 — never run `git pull` on the base branch in this repository.**
  Merge with `--no-ff` per repo convention.
- **After Option 1 completes successfully** (merge done, verification green)
  and a Jira ticket is linked: invoke `mb-jira-update` in **finalization
  mode** — after publishing the Czech summary comment it transitions the
  ticket directly to "Test" (skipping "Review") and clears the Flagged field
  if present. Options 2 and 3 never change the ticket status.
- **The discard path** ("If your human partner asks to discard the work") →
  do NOT harvest. After the typed confirmation, move the active work item
  pair to `proposals/abandoned/` and reset `memory-bank/context.md` to IDLE
  before deleting the branch. If the linked ticket sits in "Design Review",
  offer the Jira cleanup per the contract's Architect Review Gate (transition
  back, restore assignee, clear the flag).
<!-- UMS-OVERLAY END -->
