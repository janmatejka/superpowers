# Workspace Discipline
Part of contract 3.x — the core is ../UMS_MEMORY_BANK_CONTRACT.md; cite as (contract/workspace-discipline.md, "Workspace Discipline").

## Workspace Discipline

A **workspace** is a clone the user works in. The user creates it and chooses
it; it is used repeatedly and it carries the leftovers of previous work. A
pool slot (Worktree Policy) is likewise a workspace in this contract's sense,
even though it is a linked worktree rather than a clone, and "one session per
workspace" below therefore holds per slot. The layer therefore treats a
workspace as found, never as one the SESSION provisioned: the one provisioning
tool this layer has (`pool-provision.ps1`, Worktree Policy) belongs to the
operator and refuses to run under an agent-session marker.

**The single boundary of responsibility: the agent never destroys anything that
cannot be recovered from `origin`.**

- **Recoverable** — pushed branches, build output, the ledger of an archived plan
  — the agent may handle on its own.
- **Non-recoverable** — uncommitted changes, stashes, unpushed commits, playbook
  candidates — the agent NEVER deletes: it preserves them, or it stops and asks.
  For candidate files the discriminator is the one the Playbook Contract states,
  **tracked means live**: a tracked file is parked evidence that only the harvest
  removes — never overwrite it, append to it — while an untracked file of a
  finished or abandoned slug is ordinary scratch and carries no such protection.

The decision about non-recoverable content belongs to the user; detecting it and
presenting it belongs to the agent.

**"A free workspace" is a derived state, not a record.** (for one clone with its
own `.git`; a pool slot shares `.git` and is covered by the subsection below)
It is derived from empty
output of all three of `git status --porcelain`, `git stash list` and
`git log --branches --not --remotes`, plus a **fourth signal none of those three
can report:** a non-empty **untracked** candidate file of the CURRENT slug,
`<MB_ROOT>/.superpowers/playbook-candidates/<slug>.md`. `.superpowers/` is
git-ignored, so `git status --porcelain` is silent about it while the evidence
exists in this workspace and nowhere else — probe it directly (does it exist, is it
non-empty, is it tracked, per `git ls-files --error-unmatch`). All four are derived
every time, never from a flag or a bookkeeping file that can go stale.

### A pool slot's freedom is derived from per-worktree signals only

Doklad: doklad/workspace-discipline.md, "Why a pool slot's freedom needs per-worktree signals"

The signals that decide a slot's freedom:

| Signal | Source | Scope |
|---|---|---|
| dirty tree | `git -C <slot> status --porcelain` | per-worktree |
| unpushed commits OF THIS SLOT | `git -C <slot> log '@{upstream}..HEAD'`, or `git -C <slot> log HEAD --not --remotes` with no upstream | per-worktree |
| branch, or detached | `git worktree list --porcelain` | per-worktree |
| pin | `<slot>/memory-bank/context.md` | per-worktree |
| plan progress | `<slot>/.superpowers/sdd/plan_<slug>/progress.md` OF THE SLUG THE PIN NAMES | per-worktree |
| **live session** | `claude agents --json --cwd <slot>`, records with a `pid` present | per-worktree |
| stash | `git stash list` | **repo-wide — cannot be attributed to a slot** |
| playbook candidate | `<slot>/.superpowers/playbook-candidates/<slug>.md` | per-worktree, but only meaningful WHILE THE SLOT CARRIES A PIN |

**Occupancy is read from the harness, not from git.** Without that signal the
derivation has a hole git cannot close: a slot with a clean tree and an IDLE
pin in which a session has just started reads as "free" for as long as that
session needs to reach its pin write — the entry gate with a fetch and a
collision scan, on the order of a minute — and a spawn would send a second
session into it, which "one session per workspace" forbids. **A live session
in a slot is therefore a hard reason not to use it.** The signal is
fail-closed: when it cannot be read, occupancy is reported as UNKNOWN and no
spawn proceeds without an explicit operator instruction. PID files under the
user's Claude directory are NOT read — that is an undocumented interface.

**A free slot** carries the marker, a clean tree, an IDLE pin, NO live
session, no unpushed commits on its own HEAD or its own branch, and does not
hold a ticket branch of the epic being spawned.

Two signals are deliberately excluded. **A stash cannot be attributed to a
slot** — it is reported once per repository as information, never as a
property of a slot. **A playbook candidate is defined only against the
CURRENT slug**, and an IDLE slot has no current slug, so every candidate in it
is a foreign one, which this contract already classifies as "merely present":
announced, never touched. Were it part of freedom, the slot would be
permanently unusable with no defined remedy — only the harvest of that slug
may delete the file, and that slug is finished.

**The ledger is paired to the slug FROM THE PIN, never to "the first directory
found under `sdd/`".** Measured: a slot pinned to one slug carried two
directories under `.superpowers/sdd/`, and the leftover of earlier work sorts
first — "first found" would report foreign progress as this ticket's.

A slot with NON-RECOVERABLE leftovers is not free, and the orchestrator does
NOT tidy it: it reports the slot and leaves the decision to the user, in the
slot where the leftovers lie.

Leftovers split in two:

- **In the way** — a dirty tree, a stash, and a non-empty untracked candidate file
  of the CURRENT slug. They block a safe branch switch and must be resolved. The
  candidate file belongs here because it is non-recoverable by the classification
  above: switching away leaves it behind unattached to any branch, and committing it
  is what `mb-park`'s named exception exists for. In a pool slot a stash is NOT a
  per-slot blocker here — see "A pool slot's freedom is derived from per-worktree
  signals only" above; for a clone with its own `.git` a stash still blocks as
  stated.
- **Merely present** — unpushed commits of other branches, candidate files of
  other slugs (and a TRACKED candidate file of the current slug — `mb-park` already
  parked it, so it is recoverable from `origin`). They are announced only; the agent
  does not touch them.

**Entry gate**, in four phases:

0. **Eligibility**, fail-closed except where stated: `MB_ROOT`, `memory-bank/`,
   `git fetch origin`, and a **fail-closed check that the publication guarantee
   applies to THIS session** — the resolved `pre-push` exists, carries the
   marker `UMS pre-push guard (Publication Contract)` within its first five
   lines with a version no lower than the layer's own source header
   (`ums/.claude/hooks/pre-push`, line 2), and rejects a synthetic
   protected-branch line **run in this session's own
   environment** — together with the mirror-image accept case the Publication
   Contract prescribes beside it, because a hook that cannot execute at all
   "rejects" everything while still carrying its marker line.
   A protected-branch line that PASSES means the agent-session marker
   is absent in this harness, so the hook disables itself here: that is a
   missing guarantee, reported as such. A hook older than the layer's own
   source header is repaired by re-running `install-git-hooks.ps1` and
   re-checking, not by proceeding.
   The same check runs at session start and again at the beginning of
   `finishing-a-development-branch`, because the session that integrates never
   passes this gate.
   `core.hooksPath` is inspected but is **informational**: the hook check resolves
   through `git rev-parse --git-path hooks/pre-push`, which honours
   `core.hooksPath`, so a marked hook found there is the hook git will actually
   execute — the value does not bypass anything. An **absolute** value is reported
   as a **scope** warning (the hooks directory is shared with other repositories,
   so an install or a removal there reaches all of them, and the file may have been
   placed there by another repository), and the marker check is what settles that
   provenance. The repository configuration is inspected here too,
   but the item is **informational only** — a missing `ums-repo.json` is reported
   once ("built-in defaults apply", Repository Configuration) and never blocks
   entry, because a repository that has not been migrated yet must still be
   workable. The hook check and the fetch stay hard failures.
1. **Leftover inventory** per the split above.
2. **Exactly one user decision**, and only when something non-recoverable is in
   the way: **park** it or **discard** it, with the confirmation spelled out.
   "Leave it lying around" does not exist within the same workspace — that
   option is what made leftovers ambiguous in the first place.
   **Park is only offered where park can act:** `mb-park` requires the current
   branch to carry a pin, so on an IDLE branch — the base, or a ticket branch whose
   work item is already harvested — it stops with "nothing to park" and commits
   nothing. What is offered instead depends on which IDLE branch it is:
   - **On a non-base IDLE branch** (a harvested ticket branch): **commit them on
     this branch** or **discard**. Committing is fine there — the branch is the
     agent's own and publishable.
   - **On the base — never commit the leftovers onto the base.** A commit made
     there is stranded by construction: the base is shared, so neither the agent nor
     `pre-push` will publish it; `mb-park` refuses it twice (IDLE, and its base STOP);
     and the intent phase's `git switch -c <branch> <chosen base>` — the base chosen
     in that same Intent phase — has an explicit start
     point, so the commit does not travel to the ticket branch either, while carrying
     a commit across branches to repair that is forbidden. The result is work left
     lying around in the one place nothing in this layer can retrieve it from, which
     is exactly what this section forbids. Offer instead: **carry the leftovers
     uncommitted through the intent phase and commit them on the ticket branch**, an
     uncommitted change travels with `git switch -c` on its own (the same reason
     `mb-architect-review` commits the design only after the switch); when there is
     no ticket branch to create, commit them on a scratch branch. **Discard** stays
     available with the confirmation spelled out.
   Either way the decision is still exactly one, and the leftovers still have to be
   resolved: the intent phase's `git switch -c` needs `git status --porcelain` empty
   and no auto-stash is permitted, with exactly two exceptions. Carrying the
   leftovers to the ticket branch is the first, and it is safe only because those
   leftovers were just enumerated by name in phase 1 and consciously kept — never
   for content nobody accounted for. The `ums-repo.json` edit from the invariant's
   remedy (Repository Configuration) is the second, and it is safe for a different
   reason: the edit cannot be committed before the ticket branch exists (a commit
   made on the base is stranded there), so it rides uncommitted into this same
   `switch -c` and is committed only once the branch does exist.
3. **Intent:** a local branch for the ticket exists → resume; the ticket is
   active on a foreign branch → STOP (cross-clone collision check); a
   preliminary design draft waits in `next/` → activation; otherwise a new
   branch.
   **Choosing the base** belongs here, before the branch is created, because
   `git switch -c` needs it as its start point. Offer the candidates — the protected
   branches that exist on `origin`, ordered default first, then the branch the
   session stands on, then the rest — and let the USER decide; the offer is not a
   restriction, and a free-form answer outside it is accepted — it is the only way
   the STOP below can ever fire. When a Jira ticket is
   linked and reachable, a version mentioned in its text is a further ordering
   signal (fail-open: an unreachable Jira skips that signal silently). Phase 4
   DECIDES the `Báze:` line from this choice — writes it when the choice differs
   from `baseRef`, REMOVES any existing one when it does not (`context.md` Schema
   & Writers) — because the line survives both the IDLE reset and the integration
   push and would otherwise be inherited by the next work item. A base
   outside `protectedBranches` triggers the fail-closed STOP and its ordered remedy
   (Repository Configuration, the invariant).
4. **Pin write** into `context.md`.

Doklad: doklad/workspace-discipline.md, "Why the hook check is the most important agent duty"

**Switching branches:** only with `git status --porcelain` empty, **no switching
through `git stash`, no auto-stash** (the same rule as branch sync in
`mb-architect-review`), and only at phase boundaries. There are exactly two
exceptions, both riding the branch-creating `switch -c` on purpose because neither
has anywhere else to go before the ticket branch exists: the base-IDLE remedy of
phase 2 above — leftovers the inventory just named and the user chose to keep — and
the `ums-repo.json` edit from the invariant's remedy (Repository Configuration),
which cannot be committed on the base it is repairing.

**Park** (the `mb-park` skill) is the third end of a work item's life cycle,
alongside completion (harvest) and abandonment (`mb-abort`): commit, push,
announce the leftovers, commit the current slug's playbook candidates (Playbook
Contract), leave the branch checked out, and leave `context.md` in the ACTIVE
state — a state name, not a literal token; the test is the pin in the
`## Active Work` block (see the `context.md` Schema & Writers section). Parked
work is recoverable from `origin` by definition, which is why it does not block
starting another ticket (Active Work Item).

**One session per workspace.** Work on several tickets is interleaved, not
parallel — two sessions in one workspace would fight over the same working
tree and the same `context.md`. A pool (Worktree Policy) spans several
workspaces, each still bound to that same one-session rule on its own, so
sessions running in parallel across different slots are not a violation of it.

Life-cycle operations (harvest, `mb-abort`, Jira finalization) always run on that
ticket's own branch.
