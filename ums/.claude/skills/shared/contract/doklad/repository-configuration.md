# Doklad — Repository Configuration
Part of contract 3.x — evidence read on demand, never the home of a rule.

## Why the pool is not repository configuration

**No `pool` block, and two named non-keys.** Neither the list of environment
variables a launcher strips before spawning a session nor the path to the
harness executable is repository configuration: both are properties of the
HARNESS, not of the repository, so they live in the launcher script's own body.
Recording it here is what keeps the section's opening sentence — "no
repository-specific value may live in a skill body or in a script" — true
rather than quietly contradicted. Pool membership is likewise not
configuration: it is derived from `git worktree list` plus the marker file in
the worktree itself (Worktree Policy).
