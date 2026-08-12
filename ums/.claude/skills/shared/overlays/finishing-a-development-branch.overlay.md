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
  of redirection the document paths get. A ticket workspace has no local base
  branch to merge into; if one exists it is neither updated nor merged, and the
  **effective base** is the only base that counts (contract, "Repository
  Configuration"). Resolve it mechanically ONCE before the sequence below, never
  by hand — `<mb-shared>` is this layer's `skills/shared/` directory, the sibling
  of the skill directory this overlay is injected into:

  ```powershell
  . <mb-shared>/scripts/Get-UmsEffectiveBase.ps1
  $base = Get-UmsEffectiveBase (git rev-parse --show-toplevel)
  ```

  `$base.Ref` is `<effective base>` everywhere below, and `$base.Branch` is the
  push destination of step 5 — take it from the helper, never derive it in your
  head. Do NOT execute the upstream Option 1 block: no `git checkout
  <base-branch>`, no `git pull`, no local merge, no `git branch -d`. The sequence
  instead, per the contract's Publication Contract, subsection "Integration":
  1. BEFORE the harvest, base sync at this phase boundary: `git fetch origin`,
     then `git merge <effective base>` on the ticket branch, with the intersection
     assessment and verification of the contract's "Base Sync & Drift Detection"
     section.
  2. Run the harvest above, commit its Memory Bank changes and push the ticket
     branch.
  3. `git fetch origin` and `git merge <effective base>` once more — the base may
     have moved while the harvest ran — and push.
  4. Green verification on the merged tree (build and the targeted tests of the
     playbook). Red = STOP and report. The ticket branch is already on `origin`
     (steps 2 and 3 each pushed it), so what is still untouched is **the base
     ref** — nothing red has reached it. Do not try to un-publish the ticket
     branch: force push is forbidden, and a red ticket branch on `origin` is
     normal, visible work in progress. Fix forward with further commits.
  5. Ask (Czech) „Integrovat větev do `$($base.Branch)` pushem?" and hand the user
     the exact command with the outgoing commits enumerated:
     `! UMS_ALLOW_SHARED_PUSH=1 git push origin HEAD:$($base.Branch)`, with
     `$($base.Branch)` expanded to its value in both the question and the command.
     The refspec form
     is deliberate: integration pushes the ticket branch onto the base ref.
  6. Re-verify reachability **from the base ref**: `git fetch origin`, then
     `git merge-base --is-ancestor <sha> <effective base>` (non-zero exit = the commit is
     NOT on the base). Naming the base is the whole point: steps 2 and 3 already
     pushed this commit to the ticket branch on `origin`, so a bare
     `git branch -r --contains <sha>` reports that ticket branch, comes back
     non-empty and would pass while the base has none of the code — the branch would
     then be closed as integrated after a base push the user never ran or that was
     rejected as non-fast-forward. Without a Jira ticket this is the ONLY gate;
     `mb-jira-update`'s equivalent check never runs. A non-zero exit is a STOP:
     report it in Czech and go back to step 5.

  Step 3 is what makes the push a **fast-forward** — the ticket branch is a
  descendant of `<effective base>`. The ticket branch left behind on `origin` is
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
  do NOT harvest. After the typed confirmation, in this order — the normative source
  for it is the contract's Publication Contract, subsection "Abandon", which the
  `mb-abort` skill follows too:
  1. move the active work item pair to `proposals/abandoned/` — BOTH halves,
     unchanged, nothing deleted (contract, "Active Work Item (Design + Plan
     Pair)", archival asymmetry) — and reset `memory-bank/context.md` to IDLE,
  2. **commit** that move on the ticket branch (Czech commit message) and **push**
     the branch,
  3. only then delete the LOCAL branch — and since git cannot delete the branch you
     are standing on, leave it first by checking out `<effective base>` detached
     (`git switch --detach <effective base>`); a ticket workspace has no local base
     branch to return to.

  The order is the point, twice over. Deleting the branch before the commit would
  destroy the abandon move itself, which exists nowhere else — uncommitted work is
  non-recoverable, and the agent never deletes non-recoverable content (contract,
  "Workspace Discipline"). And because every earlier commit was pushed, `origin`
  still carries this branch with an ACTIVE pin and the pair still in `active/`
  until step 2 lands: `mb-doc-index` enumerates with declared intent over `origin`
  and would keep reporting `KOLIZE AKTIVNÍ PRÁCE` (exit 2) for this ticket
  indefinitely, blocking any later attempt to pin it. The exemption for an
  integrated branch does not help here — the index keys by phase, and `abandoned/`
  is not an active phase, which is exactly why the abandon move must reach
  `origin`. The branch published on `origin` is left in place: deleting a branch
  through a push is forbidden with or without the escape variable.

  If the linked ticket sits in "Design Review" (fallback shape included —
  status "Review" with the `[DESIGN REVIEW]` request-comment marker; contract,
  Architect Review Gate, "Design Review" fallback), offer the Jira cleanup per
  the contract's Architect Review Gate (transition back, restore assignee,
  clear the flag).
<!-- UMS-OVERLAY END -->
