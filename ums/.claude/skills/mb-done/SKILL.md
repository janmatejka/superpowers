---
name: mb-done
description: DEPRECATED in MB v2 — finishing is owned by finishing-a-development-branch, whose UMS Harvest Gate invokes mb-harvest. This stub only redirects.
license: MIT
metadata:
  author: UMS Project
  version: "2.0"
---

# Command: mb-done (deprecated)

Retired in Memory Bank v2 (see `../shared/UMS_MEMORY_BANK_CONTRACT.md`).

**Instead:** finish work via the `finishing-a-development-branch` skill — its
Step 4.5 (UMS Harvest Gate) invokes `mb-harvest`, which harvests knowledge,
archives the proposal pair to `completed/` and resets `context.md` to IDLE.
For a late/standalone harvest (work already merged without the gate), invoke
`mb-harvest` directly.

Announce this redirect to the user in Czech.
