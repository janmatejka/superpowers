<!-- TARGET: finishing-a-development-branch/SKILL.md -->
<!-- ANCHOR-BEFORE: ## Step 5: Execute Choice -->

<!-- UMS-OVERLAY BEGIN (ums-memory-bank v2) -->
## Step 4.5: UMS Harvest Gate (MANDATORY in this repository)

After the user chooses and BEFORE executing the choice:

- **Option 1, 2, or 3** (Merge Locally / Push and Create PR / Keep As-Is) →
  invoke the `mb-harvest` skill. It harvests knowledge into the affected
  Memory Bank documents, runs the playbook gate (asks the user which collected
  experiences to persist), archives the design document to
  `proposals/completed/` (deleting the implementation plan), resets
  `memory-bank/context.md` to IDLE and offers `mb-jira-update`. Commit the
  resulting Memory Bank changes on this branch (Czech commit message) and push the
  ticket branch — the publication rule holds here as everywhere: the agent pushes
  its own ticket branch after every commit, announcing the branch and the outgoing
  commits. Then execute the chosen option. For Option 1 the harvest is step 2 of
  the integration sequence below, so a base sync precedes it.
- **Option 1 ("Merge back to <base-branch> locally") is REPLACED in this
  repository by integration through a push of the ticket branch** — the same kind
  of redirection the document paths get. Do NOT execute the upstream Option 1
  block: no `git checkout <base-branch>`, no `git pull`, no local merge, no
  `git branch -d`. A ticket workspace has no local base branch to merge into; if
  one exists it is neither updated nor merged, and `origin/<baseRef>` is the only
  base that counts (`baseRef` from `<CTX_DIR>/ums-repo.json`, contract section
  "Repository Configuration"). The sequence instead, per the contract's
  Publication Contract, subsection "Integration":
  1. BEFORE the harvest, base sync at this phase boundary: `git fetch origin`,
     then `git merge origin/<baseRef>` on the ticket branch, with the intersection
     assessment and verification of the contract's "Base Sync & Drift Detection"
     section.
  2. Run the harvest above, commit its Memory Bank changes and push the ticket
     branch.
  3. `git fetch origin` and `git merge origin/<baseRef>` once more — the base may
     have moved while the harvest ran — and push.
  4. Green verification on the merged tree (build and the targeted tests of the
     playbook). Red = STOP and report; nothing has left this clone yet.
  5. Ask (Czech) „Integrovat větev do `<baseRef>` pushem?" and hand the user the
     exact command with the outgoing commits enumerated:
     `! UMS_ALLOW_SHARED_PUSH=1 git push origin HEAD:<baseRef>`. The refspec form
     is deliberate: integration pushes the ticket branch onto the base ref.
  6. Re-verify reachability: `git fetch origin`, then
     `git branch -r --contains <sha>` (an empty result = not on origin).

  Step 3 is what makes the push a **fast-forward** — the ticket branch is a
  descendant of `origin/<baseRef>`. The ticket branch left behind on `origin` is
  **not deleted**; deleting a branch through a push stays forbidden, and the
  document index keys by phase, so an integrated ticket no longer counts as
  active work.
- **The agent never pushes a shared branch and never sets
  `UMS_ALLOW_SHARED_PUSH` itself** — it is the human's deliberate escape from the
  `pre-push` guard (Publication Contract), which would otherwise reject the very
  command handed over, and setting it as an agent silently converts the two-tier
  push policy into a one-tier one. Do NOT substitute `--no-verify`: it is a bypass
  of the guarantee, not a way to publish, and it disables every hook in the
  repository.
- **A push rejected as non-fast-forward** means the base moved while the sequence
  ran: repeat from step 3 (`fetch`). **At most two failed rounds** — after the
  second, STOP and report to the user instead of racing the base indefinitely.
- **After a verified fast-forward push into the base ref** — reachability
  re-verified in step 6 — and with a Jira ticket linked: invoke `mb-jira-update`
  in **finalization mode**; after publishing the Czech summary comment it
  transitions the ticket directly to "Test" (skipping "Review") and clears the
  Flagged field if present. Until the commit is reachable on `origin`,
  finalization stops at its publication gate and the ticket does NOT move to
  „Test". Options 2 and 3 never change the ticket status.
- **The discard path** ("If your human partner asks to discard the work") →
  do NOT harvest. After the typed confirmation, move the active work item
  pair to `proposals/abandoned/` and reset `memory-bank/context.md` to IDLE
  before deleting the LOCAL branch; the branch already published on `origin` stays
  there, because deleting a branch through a push is forbidden with or without the
  escape variable. If the linked ticket sits in "Design Review",
  offer the Jira cleanup per the contract's Architect Review Gate (transition
  back, restore assignee, clear the flag).
<!-- UMS-OVERLAY END -->
