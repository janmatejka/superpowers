---
name: mb-done-git-commit
description: DEPRECATED in MB v2 — finishing is owned by finishing-a-development-branch (harvest via mb-harvest, commit inside the gate). This stub only redirects.
license: MIT
metadata:
  author: UMS Project
  version: "2.0"
---

# Command: mb-done-git-commit (deprecated)

Retired in Memory Bank v2 (see `../shared/UMS_MEMORY_BANK_CONTRACT.md`).

**Instead:** finish work via the `finishing-a-development-branch` skill — its
Step 4.5 (UMS Harvest Gate) invokes `mb-harvest` and then commits the Memory
Bank changes on the branch (Czech commit message). For a standalone
harvest-plus-commit, invoke `mb-harvest` and then `mb-git-commit`.

Announce this redirect to the user in Czech.
