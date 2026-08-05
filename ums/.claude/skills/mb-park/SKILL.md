---
name: mb-park
description: Set the active work item aside — commit, publish, commit the current slug's playbook candidates and report what stays behind; the pair stays in active/ and context.md keeps its pin. Use for "odlož práci", "zaparkuj tiket", "přepnu se na jiný tiket", or from the entry gate when non-recoverable leftovers are in the way.
license: MIT
metadata:
  author: UMS Project
  version: "1.0"
---

> Follow [UMS_MEMORY_BANK_CONTRACT](../shared/UMS_MEMORY_BANK_CONTRACT.md) —
> especially "Workspace Discipline", which names park as the third end of a work
> item's life cycle and owns the recoverability boundary, plus the "Playbook
> Contract", the "Publication Contract" and "`context.md` Schema & Writers".
> This skill is the set-aside path beside `mb-harvest` (completion) and
> `mb-abort` (abandonment).

# Command: mb-park

**Action:** Set the active work item aside: commit the work in progress, publish
the branch, commit the current slug's playbook candidates, and report what stays
behind in the workspace. Nothing is discarded and nothing is harvested — the
design + plan pair stays in `<PLAN_MB>/proposals/active/` and `context.md` keeps
its pin, i.e. it stays in the ACTIVE state.

**Execution:** Autonomous — this skill deletes nothing, so it has nothing to ask
confirmation for. The harness's own permission prompt for `git push` still
applies.

**The branch stays checked out.** Park is not a branch switch and it never
becomes one: switching away would cost a checkout and a rebuild that nothing
needs. Whoever parks may switch afterwards, at a phase boundary, on a clean tree
(Workspace Discipline) — that is a separate decision, not part of parking.

---

## Workflow

### 0. Resolve MB_ROOT and gate

- `git rev-parse --show-toplevel` → `MB_ROOT`; failure = hard stop
  (`Git repository not found. Memory Bank requires git.`).
- `<MB_ROOT>/memory-bank/` must exist, else stop with the Root Gate error.
- Read `<CTX_DIR>/context.md`. The ACTIVE test is the pin, never the word: the
  `## Active Work` block must carry a `Target MB Pin` together with a
  `Work item` slug (legacy `- **Proposal:**` accepted as its alias). The word
  `ACTIVE` never appears in the file, so never grep for it.
- IDLE — the `(No active work - IDLE phase)` marker, or a block with no pin —
  means **there is nothing to park**: say so and stop, without committing
  anything.
- Record for the report: the slug, the `Jira` line, and the current branch
  (`git rev-parse --abbrev-ref HEAD`).
- **A detached HEAD is a STOP** (`git symbolic-ref -q HEAD` fails). Park's whole
  promise is that the work is recoverable from `origin`, and there is no branch to
  publish; life-cycle operations run on the work item's own branch (Workspace
  Discipline). Report it and let the user check out the ticket branch first.
- **The current branch being the base is a STOP too** — `<baseBranch>`, i.e.
  `baseRef` minus its remote prefix, read from `<CTX_DIR>/ums-repo.json` (contract
  section "Repository Configuration"). Park leaves `context.md` in the ACTIVE state
  by design, and the contract's invariant (Cross-Branch Visibility) is that **the
  base never carries ACTIVE state**: every branch cut from it afterwards would
  inherit a foreign pin, which is why `mb-state` reports a pinned base as an *error*
  rather than a warning. Publishing an ACTIVE pin onto the base would create exactly
  that state, and the base is shared, so the push does not happen either way — park
  on the base can only ever end in a commit nobody can publish and nothing can move
  (`git switch -c` leaves it behind, and carrying a commit across branches to repair
  an ordering mistake is forbidden). **This check belongs HERE, before steps 1–4,
  and its position is the point:** steps 2 and 3 commit, so the same STOP placed at
  publication would first create the very state it exists to prevent — a *committed*
  ACTIVE pin on the local base — and then refuse with no way to undo it. Report it
  with the base variant of the report below and name the way out: move the work to a
  ticket branch (the entry gate's intent phase — an uncommitted change travels with
  `git switch -c` on its own) and park there, or resolve it as finishing /
  `mb-abort`. Nothing has been committed at this point, which is what makes that way
  out available.
- When the pair named by the slug is NOT in `<PLAN_MB>/proposals/active/`, do
  **not** stop: park preserves, and refusing here would push the user toward
  leaving leftovers lying around, which is the one option Workspace Discipline
  does not allow. Park what is there, note the inconsistency in the report and
  suggest `mb-state`.

### 1. Leftover inventory

```bash
git status --porcelain
git stash list
git log --branches --not --remotes --oneline
```

A **fourth item** belongs in the inventory, and none of the three commands can
report it: the current slug's candidate file
`<MB_ROOT>/.superpowers/playbook-candidates/<slug>.md`. `.superpowers/` is
git-ignored, so a non-empty **untracked** candidate file is invisible to
`git status --porcelain` — probe it directly: does it exist, is it non-empty, and
is it tracked?

```bash
git ls-files --error-unmatch <MB_ROOT>/.superpowers/playbook-candidates/<slug>.md
```

Non-empty and untracked is **work to park**, exactly like a dirty tree: the
evidence exists only in this workspace, and committing it is what the named
exception in step 3 is for. This is the state the three git commands hide, and
mistaking it for "nothing to do" loses evidence in precisely the case the
exception was created for — the last task is committed and pushed, and the
candidates were appended afterwards.

- The work **is already parked** only when all FOUR are clear: nothing to commit,
  no stash, nothing unpushed, AND no untracked candidate content. Then announce
  it and stop; do not manufacture an empty commit. It is a derived state, read
  from git and from the file every time, never from a flag or a bookkeeping file
  that can go stale.
- Anything else continues through steps 2–4 — including a clean tree whose only
  leftover is a fresh untracked candidate file. Step 3 then carries the single
  commit of this park; step 2 finds nothing to commit and says so.
- Classify the rest per Workspace Discipline: a dirty tree and a stash are **in
  the way**; unpushed commits of other branches and candidate files of other
  slugs are **merely present**. Park resolves only what it commits below;
  everything merely present is reported and left untouched.

### 2. Commit the work in progress

Invoke the `mb-git-commit` skill. Never hand-roll a `git commit` here — the same
division of labour `mb-abort` uses, so the repository's single commit-message
convention (Czech, ticket prefix, ` - ` detail lines) holds across the whole
layer.

When step 1 found the working tree clean, there is nothing to commit here: skip
to step 3, whose staged candidate file then becomes the park's only commit.

**A stash is never folded into the park.** Park does not pop it, does not apply
it and does not drop it; its existence is reported in the report below and the
decision about it stays with the user. The same holds for unpushed commits on
other branches. This is the recoverability boundary of Workspace Discipline: the
agent never destroys anything it cannot get back from `origin`, and a stash
exists nowhere but this workspace.

### 3. Commit the current slug's playbook candidates

The file is `<MB_ROOT>/.superpowers/playbook-candidates/<slug>.md` — the CURRENT
slug only. Files of other slugs have their own paths and are neither read, nor
committed, nor deleted.

- Missing or empty (step 1's probe already established which) → nothing to do;
  the step is silent.
- Non-empty → stage it with `git add -f`, **whatever its tracked-ness**. The `-f`
  is required because `.superpowers/` is git-ignored, and committing this one file
  is a **named exception** from "the scratch tree is git-ignored" (Playbook
  Contract): parked evidence exists nowhere else, so without the exception every
  experience learned on this branch would be lost the moment the workspace moves
  on. Both non-empty states need the explicit path: an **untracked** file needs
  `-f` to get past the ignore rule at all, and a **tracked** file with newly
  appended entries needs naming because `mb-git-commit`'s scoped staging
  enumerates Memory Bank and source paths, and `.superpowers/` is not among them.
  A tracked file that is unchanged leaves git nothing to record, and that is the
  correct outcome — the evidence is already parked.
- The `git add -f` must happen **before** `mb-git-commit` is invoked —
  `mb-git-commit`'s own staging never picks up an ignored path. Preferably stage
  it before the invocation in step 2, so one commit carries the work and the
  evidence together; when step 2 has already committed (or found nothing to
  commit), invoke `mb-git-commit` once more for this file alone.
- Once committed the file is **tracked, and tracked means live** (Playbook
  Contract): it is live parked evidence. Resumed work on this slug APPENDS to it,
  and only the harvest removes it — after its content has reached `playbook.md`.
  Park never truncates it, never rewrites it and never overwrites it.

### 4. Publication

Per the Publication Contract, a commit that is not pushed is work only this
workspace can see — and parked work whose commits sit locally is not recoverable
from `origin`, which is the whole promise of parking.

- The ticket branch is the actor's OWN branch: the agent pushes it and announces
  the branch together with the outgoing commits (`git log --oneline @{u}..HEAD`,
  or against `<baseRef>` when the branch has no upstream yet; `baseRef`
  from `<CTX_DIR>/ums-repo.json`, contract section "Repository Configuration").
- **The base never reaches this step.** Step 0 already stopped on it, before any
  commit existed — do not re-check it here and do not prepare a push command for it.
  A base path arriving here at all means step 0 was skipped, and then steps 2 and 3
  have already put a committed ACTIVE pin on the local base: report that as the
  finding it is instead of pushing.
- When the current branch is in `protectedBranches` **without being the base**
  (same section; the built-in fallback is `develop`, `main`, `master`,
  `release/*`) the agent does NOT push.
  It prepares the exact command carrying `UMS_ALLOW_SHARED_PUSH=1` with the
  outgoing commits enumerated and the user runs it. The agent never sets that
  variable itself, and it never reaches for `--no-verify` — that disables every
  hook in the repository, so it is a bypass of the guarantee, not a way to
  publish.
- **Re-verify reachability AFTER a push has actually happened** — the agent's own
  on its own branch, the user's on a shared one — in that order, as in the
  contract's Publication Contract, subsection "Integration":

  ```bash
  git fetch origin
  git branch -r --contains <sha>
  ```

  An empty result then means the park is not published, so the claim "recoverable
  from `origin`" is false — a fail-closed STOP with an offer to publish, never a
  warning. On the shared-branch path the check therefore waits for the user; do
  not run it against the prepared command and report a STOP whose only remedy is
  the command the user has not run yet.

---

## Report (Czech)

This report is the report of a park that HAPPENED, so it is reachable only from
steps 1–4. The base path never produces it: step 0 stops there before any commit,
and its own message is the base variant at the end of this section — nothing may
claim a park, a push or recoverability from `origin` on that path.

> „🅿️ Práce zaparkována."
>
> - Work item: `<slug>`, tiket: `<UMS-XXXX | (žádný tiket)>`, větev: `<branch>`
> - Publikováno: `<branch>` → `origin`, commity: `<seznam>` (u sdílené větve:
>   „připraven příkaz pro tebe — agent sdílenou větev nepushuje")
> - Pár návrh+plán zůstává v `<PLAN_MB>/proposals/active/`; `context.md` zůstává
>   na této větvi v aktivním stavu (pin se nemaže). Nic se nezahodilo a nic se
>   nesklízelo.
> - Větev zůstává checkoutnutá — žádné zbytečné přepnutí, tedy žádný zbytečný
>   rebuild.
> - Kandidáti playbooku: `<slug>.md` je commitnutý na větvi (živý důkaz — smaže
>   ho až harvest po zápisu do `playbook.md`) | „žádní kandidáti"
> - Ve workspace zůstává, park to neřeší: stash `<N položek>`, nepushnuté commity
>   jiných větví `<seznam>`, kandidáti jiných slugů `<seznam>` — o neobnovitelném
>   obsahu rozhoduješ ty. | „žádné zbytky"
> - Pokračovat lze v kterémkoli workspace: `git fetch origin` a checkout větve
>   `<branch>`.

Early exits, all without a commit and without a push:

> „ℹ️ Není co parkovat — `context.md` na této větvi nemá pin (stav IDLE)."

> „ℹ️ Práce je už zaparkovaná — čistý strom, prázdný stash, nic nepushnutého
> a žádní necommitnutí kandidáti playbooku. Nedělám prázdný commit."

The base variant (step 0), which is a STOP, not a park:

> „⛔ Neparkuji — jsi na bázi `<branch>`."
>
> - Aktivní práce (`<slug>`, tiket `<UMS-XXXX | žádný tiket>`) je na bázi. Park
>   nechává `context.md` v aktivním stavu, a báze nikdy nesmí nést aktivní pin —
>   každá další větev z ní by zdědila cizí pin (invariant Cross-Branch Visibility,
>   `mb-state` to hlásí jako chybu, ne varování).
> - **Nic jsem necommitnul, nic nepushnul a nic nezahodil.** Báze je sdílená větev,
>   takže push by neproběhl ani po commitu, a commit z báze by se na tiketovou větev
>   nedostal.
> - Cesta dál: přesuň práci na tiketovou větev — `git switch -c <TIKET>-<slug>
>   <baseRef>`, necommitnuté změny jdou s přepnutím samy — a zaparkuj tam. Nebo práci
>   uzavři přes finishing-a-development-branch, případně zahoď přes `mb-abort`.

---

## Notes

**Against `mb-abort`.** Abort ENDS the work item: both halves of the pair move to
`proposals/abandoned/` and `context.md` is reset to IDLE. Park ends nothing — the
pair stays in `active/`, the pin stays where it is, and the work is later resumed
on this branch. The two skills share only the commit-and-publish tail.

**Against finishing-a-development-branch.** Finishing COMPLETES the work item:
the harvest runs the playbook gate, archives the design half to `completed/`,
deletes the plan half, resets `context.md` to IDLE and hands over to integration.
Park harvests nothing and closes nothing; the candidate file is committed, not
consumed.

**Park deletes no branch**, local or remote, and it switches nothing.

Park is the "park" side of the entry gate's single decision about non-recoverable
leftovers, and it is one of the three resolved states the two-actives guard
accepts (finished, parked, abandoned) — parked work is recoverable from `origin`
by definition, so it is announced and does not block starting another ticket.
