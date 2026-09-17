# Worktree Pool Slots
Part of contract 3.x — the core is ../UMS_MEMORY_BANK_CONTRACT.md; cite as (contract/worktree-pool.md, "Worktree Policy").


**The ban does not rest on disk cost, and the earlier measurement that said it
did was wrong.** Measured 2026-09-02 on the UMS monorepo: a linked worktree
occupies 7.7 GB, the shared `.git` 4.4 GB and the main clone 27.2 GB, so a
linked worktree saves roughly 70 %, not 16 % — the difference is accumulated
build output, not source. What the ban actually rests on is the model: one
session per workspace, and no workspace an agent provisioned for itself.

**One exception: a POOL SLOT.** A pool slot is a linked worktree the USER
created and MARKED (the marker file `.superpowers/pool-slot`), which lives
across many tickets and hosts at most one session. The layer looks at it as a
FOUND workspace — Workspace Discipline, the entry gate, `mb-park` /
`mb-harvest` / `mb-abort`, the Publication Contract and the cross-clone
collision check all apply to it unchanged. Agent-created worktrees stay
banned; provisioning a slot is an operator action, defended by two
independent mechanisms of unequal reach: `permissions.deny` blocks the
invocation shapes it matches (`PowerShell(pool-provision.ps1:*)`,
`Bash(pool-provision.ps1:*)`), but a `pwsh -NoProfile -File <path>`
invocation was measured **not** to be intercepted by either deny entry, in
either tool frame. The guarantee that an agent cannot provision a slot
therefore rests on the script's **own** agent-session-marker guard — exactly
the layer this design already relies on for harnesses where
`permissions.deny` does not exist at all.

An idle slot is detached, or stands on a branch whose name equals the slot
directory's name — but **IDLE is decided by the pin and never by a branch
name.** Measured: a slot standing on its own eponymous branch with a clean
tree carried an ACTIVE pin, so the pool's real convention is "its own branch
PARKS the slot while the pin persists". The name shape is accepted for a
different reason: it is a named place to switch a slot to when a branch
checked out elsewhere has to be released.

**A shared `.git` is what keeps the publication guarantee.** Measured: from
each of four slots `git rev-parse --git-path hooks/pre-push` returns the same
file under the main clone's `.git`, so ONE run of `install-git-hooks.ps1`
covers every slot. Two traps of that check: the path SHAPE differs by where
you ask from (absolute from a slot, relative `.git/hooks/pre-push` from the
PRIMARY worktree), so any cross-slot identity comparison must normalize to an
absolute path; and a RELATIVE `core.hooksPath` resolves per worktree, which
means each slot then needs its own installer run.
