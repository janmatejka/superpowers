# Doklad — Worktree Pool Slots
Part of contract 3.x — evidence read on demand, never the home of a rule.

## The ban does not rest on disk cost

**The ban does not rest on disk cost, and the earlier measurement that said it
did was wrong.** Measured 2026-09-02 on the UMS monorepo: a linked worktree
occupies 7.7 GB, the shared `.git` 4.4 GB and the main clone 27.2 GB, so a
linked worktree saves roughly 70 %, not 16 % — the difference is accumulated
build output, not source. What the ban actually rests on is the model: one
session per workspace, and no workspace an agent provisioned for itself.
