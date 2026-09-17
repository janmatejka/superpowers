# Doklad — Workspace Discipline
Part of contract 3.x — evidence read on demand, never the home of a rule.

## Why a pool slot's freedom needs per-worktree signals

A pool slot (Worktree Policy) shares `.git` with every other slot, so the
three-signal derivation above does not hold there as written. Measured: in a
linked worktree only `HEAD` and the index are per-worktree; `refs/stash` and
`refs/heads` are SHARED — `git -C <slot> rev-parse --git-path refs/stash`
returns the same file from two different slots. `git stash list` therefore
answers identically from every slot, and `--branches` is repo-wide by
construction, so ONE unpushed commit anywhere in the repository would make
EVERY slot permanently unfree.

## Why the hook check is the most important agent duty

The hook check is the most important agent duty in this model, because the user
creates the workspace and **git hooks do not travel with a clone** — a workspace
that looks exactly like a working one can be missing the whole publication
guarantee (see Publication Contract) — or hold a hook that is installed and
current, yet disarmed here because the agent-session marker never reaches this
harness. Only a check run in this session's own environment tells the two
apart from a workspace that is genuinely guarded.
