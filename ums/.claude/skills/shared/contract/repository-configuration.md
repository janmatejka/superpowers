# Repository Configuration
Part of contract 3.x — the core is ../UMS_MEMORY_BANK_CONTRACT.md; cite as (contract/repository-configuration.md, "Repository Configuration").

## Repository Configuration

**No repository-specific value may live in a skill body or in a script.** The
layer is redistributable: a branch name like `develop`, a ticket prefix like
`UMS-`, or a project marker file belongs to the repository that uses the layer,
not to the layer itself.

**Location: `<CTX_DIR>/ums-repo.json`.** Deliberately **not** in `.claude/`: the
upstream `.gitignore` ignores every `.claude/` directory, so a file placed there
would be untracked and would not travel with a clone. `CTX_DIR` is guaranteed to
exist (Root Memory Bank Gate) and is tracked.

Keys and their consumers — **a key without a named consumer is not
introduced:**

| Key | Consumers |
|---|---|
| `baseRef` | `mb-doc-index`, ticket-branch creation, base sync, integration |
| `protectedBranches` | the `pre-push` hook (through the plain-text list the installer generates — the core's `## Publication Contract`), `guard-git-push.mjs` |
| `epicBranchPattern` | `guard-git-push.mjs` (the actor-rule exception) |
| `ticketPattern` | `mb-state`, the entry gate, `mb-architect-review` |
| `projectMarkers`, `sharedRoots` | the intersection heuristic (see Base Sync & Drift Detection) |

Doklad: doklad/repository-configuration.md, "Why the pool is not repository configuration"

**`baseRef` is a fully-qualified remote-tracking ref** (`origin/develop`,
`origin/ums-memory-bank`) and is used as-is wherever git READS the base: a merge
source, a merge-base, a diff endpoint, a `switch --detach` target — the
`switch -c` start point that creates a ticket branch is a partial case, covered
below in this file — the effective-base carve-out, in the paragraph beginning
"One site is deliberately NOT the effective base". It is never prefixed with `origin/` a
second time — `origin/origin/develop` resolves to nothing.

**`<baseBranch>` is a derivation, not a config key:** `baseRef` minus its remote
prefix — strip the remote name and the **single** following slash, and nothing
else (`origin/develop` → `develop`, `origin/Branches/5.37` → `Branches/5.37`).
Stripping to the LAST slash instead would turn `origin/Branches/5.37` into `5.37`,
and `git push origin HEAD:5.37` then creates a **new** remote branch rather than
updating the base — and `pre-push` would not flag it, because `Branches/*` does not
match `5.37`. It exists for exactly one purpose, the
**push destination**, because a refspec's right-hand side names a branch on the
remote and not a remote-tracking ref: `git push origin HEAD:<baseBranch>`. With
`baseRef` there instead, the push would create a junk branch literally named
`origin/develop` on the remote rather than updating the base — and the `pre-push`
guard would not catch it, because it strips `refs/heads/` and matches the
remainder against `protectedBranches`, where `origin/develop` appears nowhere.
`<baseBranch>` appears at push destinations only; everywhere else the base is
named in its remote-tracking form.

**A missing file is not an error, and the degradation leans to the safer
side:** `baseRef` falls back to `origin/develop` — except for the epic-line
exception, which declines rather than falls back (see The epic line);
`protectedBranches` falls back to the built-in list, i.e. to *more* protection,
never less; and without
`projectMarkers` / `sharedRoots` the verification after a base merge is offered
for **every** non-empty incoming diff rather than for none.

**The effective base of a work item.** A work item may integrate somewhere other
than the repository's default — a maintenance branch of a release series carries
the same role as `develop` for the work targeting it. The base of the CURRENT work
item is therefore read as:

> **Effective base** = the `- **Báze:**` line of the `## Active Work` block in
> `<CTX_DIR>/context.md`; when that line is absent, `baseRef` from
> `<CTX_DIR>/ums-repo.json`.

The line carries the same shape and the same rules as `baseRef` — a fully-qualified
remote-tracking ref, never prefixed with `origin/` a second time, and `<baseBranch>`
is derived from it by stripping the remote and the SINGLE following slash. The pin
write DECIDES whether the line exists — writing it when the chosen base differs
from `baseRef` and deleting any existing line otherwise (see `context.md` Schema &
Writers) — so a repository that always integrates into `baseRef` never carries the
line and behaves exactly as before.

**Binding on the rest of this contract.** Wherever this contract writes `<baseRef>`
as the base of the CURRENT work item — a merge source, a merge-base, a diff
endpoint, a `switch --detach` target, or the `<baseBranch>` derivation — the
effective base is meant, not necessarily the `baseRef` config value. A site that
instead needs the config key itself, by name, says so.

**One site is deliberately NOT the effective base: the start point of the
`git switch -c` that CREATES the ticket branch — but only when the work item is
being pinned for the FIRST time.** There the base is the one the user picked in
the entry gate's Intent phase (Workspace Discipline), because at that moment
`context.md` still describes the PREVIOUS work item — this one's `Báze:` line is
written a phase later, by the pin write. Reading the effective base there would
start the branch from whatever the last work item integrated into. **Where the
work item is already pinned** — `context.md` already carries its `Target MB Pin`
and `Work item` slug for this same work item, so there is no entry-gate
base-choice dialog left to run — that earlier Intent-phase choice is exactly what
the effective base now resolves to, so the effective base IS the correct start
point there.

**Invariant: an integration branch is always a protected branch.** A base that
matches no pattern in the effective `protectedBranches` is a fail-closed STOP at the
moment it is chosen — the agent would be free to push into it, which is the whole
guarantee this layer exists to keep. The remedy is ordered: add the missing pattern
to `ums-repo.json` (a targeted edit; `mb-init` is for founding or regenerating the
configuration as a whole, not for one pattern); re-run `install-git-hooks.ps1`
because the generated list is a build product of the configuration; PROVE it with
the synthetic-pipe check (Publication Contract), **with
`MB_AGENT_SESSION=1` set** — outside an agent session the hook deliberately
enforces nothing, so an unmarked pipe proves only that the gate works — piping
a synthetic ref update for
THIS branch into the installed hook and confirming the non-zero reject (the
installer's own self-test proves only that the generated list is consulted, and
only for ONE sampled pattern beyond its built-in set — the first whose sole glob
metacharacter is `*` — and for a branch name mechanically derived from that
pattern, so it may exercise an older pattern instead of the one just added and
never test the branch actually chosen); and only THEN create the ticket branch and
commit the configuration change ON it — a commit made before the branch exists is
stranded on the shared base. Declining the remedy means choosing a different
base; there is no third path.

A pattern that cannot be evaluated at all (a malformed glob such as `Maint/[0-9`)
counts as NO match, which is the same answer the `pre-push` hook's `case` statement
gives it — and it is reported, because such a pattern silently protects nothing
there either.

**Every list-valued key accepts a bare string as a single-element list**, and every
consumer must normalize it the same way: `"protectedBranches": "Branches/*"` means
exactly `["Branches/*"]`. The rule exists because `protectedBranches` has two
independent enforcement layers — the generated list the `pre-push` hook reads, and
`guard-git-push.mjs` — and **they must never disagree about WHICH branches the
same configuration protects**, which a shape one layer accepts and the other
rejects guarantees they would. The two layers do give different VERDICTS on the
same push, and that is by design (Publication Contract, the actor/content
split); what they may not disagree about is the membership question underneath.

`pre-push` is POSIX `sh` with no JSON parser available, so it does not read the
configuration at all: `install-git-hooks.ps1` generates a plain text list from
it into `<git-common-dir>/ums-protected-branches`, and the hook reads that.
**Changing the list therefore requires a new run of the installer** — the
generated file is a build product of the configuration, not a second source of
truth. The same safer-side degradation binds the installer: if the configuration
loader is missing or the list cannot be written, it still installs the hook, so
protection lands at the built-in list and the run reports exit 4 — never at an
uninstalled hook, which would leave the shared branches unprotected altogether.

`mb-init` populates the configuration by detecting it from the repository
topology. The first version needs no approval (the same exception, for the same
reason, as the first `playbook.md` — there is nothing yet to overwrite and the
detected values are verifiable against the repository itself); every later change
does.
