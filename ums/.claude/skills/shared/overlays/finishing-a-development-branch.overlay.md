<!-- TARGET: finishing-a-development-branch/SKILL.md -->
<!-- ANCHOR-BEFORE: ### Step 5: Execute Choice -->

<!-- UMS-OVERLAY BEGIN (ums-memory-bank v2) -->
### Step 4.5: UMS Harvest Gate (MANDATORY in this repository)

After the user chooses and BEFORE executing the choice:

- **Choice 1, 2, or 3** → invoke the `mb-harvest` skill. It harvests
  knowledge into the affected Memory Bank documents, archives the active
  proposal pair to `proposals/completed/`, resets `memory-bank/context.md` to
  IDLE and offers `mb-jira-update`. Commit the resulting Memory Bank changes
  on this branch (Czech commit message), then execute the chosen option.
- **Choice 4 (Discard)** → do NOT harvest. After the typed confirmation, move
  the active proposal pair to `proposals/abandoned/` and reset
  `memory-bank/context.md` to IDLE before deleting the branch.
<!-- UMS-OVERLAY END -->
