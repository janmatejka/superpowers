# UMS Memory Bank Contract

- **Contract-Version:** 2.6
- Supersedes v2.5 (integration is a fast-forward push of the ticket branch, so
  the `--no-ff` convention is dropped; repository-specific values move out of
  skill bodies into `<CTX_DIR>/ums-repo.json`; the active-work limit becomes
  per-branch; workspace discipline and the park operation are added).
- v2.5 superseded v2.4 (the plan half is never linked from a document: the
  `**Plán:**` field is dropped from the design header and cross-references
  between the halves run plan → design only, because the plan is deleted at
  harvest and every link to it dies in the archive).
- v2.4 added Link Conventions under Scope Lock (links relative to the
  containing file, no `#fragment` anchors — section named in words instead —
  and the marking rule for undeterminable targets; enforced by
  `mb-link-audit`).
- v2.3 superseded v2.2 (narrows the mandatory document set to
  `brief.md`/`architecture.md`/`tech.md`, introduces `playbook.md` with the
  consult-before-write regime, adds Document Ownership and the playbook
  candidate collection). v2.2 added the Publication Contract and Cross-Branch
  Visibility; v2.0 renamed the document pair to `design_`/`plan_` and added the
  Architect Review Gate; v1 (mb-plan/mb-act orchestration) remains superseded.
  See `VENDORED_FROM.md` for the vendored Superpowers version.

## Purpose & Roles

Superpowers skills are the **driving workflow** in this repository
(`brainstorming → writing-plans → subagent-driven-development / executing-plans
→ finishing-a-development-branch`). The Memory Bank (MB) is the **document and
knowledge layer** injected into that workflow. This contract defines where
superpowers artifacts live inside the MB tree, how the target MB is selected
and pinned, what `context.md` contains, and how knowledge is harvested when a
branch finishes.

Consumers of this contract:

1. **Vendored superpowers skills** — via `CLAUDE.md` preferences and the marked
   `<!-- UMS-OVERLAY -->` blocks (brainstorming, subagent-driven-development,
   finishing-a-development-branch).
2. **`mb-*` utility skills** — `mb-init`, `mb-state`, `mb-scan`, `mb-sync`,
   `mb-harvest`, `mb-abort`, `mb-park`, `mb-git-commit`, `mb-git-message`,
   `mb-jira-update`.
3. Any other agent or session working with Memory Bank documents.

## Three-Tier Directory Model

UMS Memory Bank uses a three-tier directory model across the monorepo:

- **`CTX_DIR`** — `<MB_ROOT>/memory-bank/` — the orchestration root of the
  repository. Holds `context.md` (Jira link, `Target MB Pin`, `Work item` slug,
  `Started`).
- **`PLAN_MB`** — `<MB_ROOT>/<Target MB Pin>` — the project Memory Bank the
  current work targets. Holds the active design + plan pair and the project
  documents (`brief.md`, `architecture.md`, `tech.md`, and optionally
  `playbook.md` — see Memory Bank Document Set).
- **`AFFECTED_MBS`** — the set of project Memory Banks touched by a harvest.
  Derived at harvest time from the branch diff (see Harvest Contract), not
  hand-maintained in `context.md`.

Derivations:

- `CTX_DIR = <MB_ROOT>/memory-bank/`
- `PLAN_MB = <MB_ROOT>/<Target MB Pin>` where `Target MB Pin` comes from
  `CTX_DIR/context.md`.
- If `Target MB Pin` is not set, `PLAN_MB` is undefined — operations requiring
  `PLAN_MB` MUST fail with an error (or trigger Target-MB Discovery where this
  contract says so).

## `MB_ROOT` Discovery

When a skill or helper needs `MB_ROOT`, use exactly one discovery step:

```bash
git rev-parse --show-toplevel
```

Rules:

- Do not use workspace scans, directory walks, or fallback anchors to discover
  `MB_ROOT`.
- If `git` is missing or the command exits non-zero, stop immediately with:
  `Git repository not found. Memory Bank requires git.`
- On success, set `MB_ROOT` to the returned git root and `CTX_DIR` to
  `<MB_ROOT>/memory-bank/`.

## Root Memory Bank Gate

Before reading or writing any Memory Bank file, verify that
`<MB_ROOT>/memory-bank/` exists.

- If it does not exist, stop with: `` `memory-bank/` does not exist. Run `mb-init`. ``
- The root `memory-bank/` is the orchestration root for the repo.

`mb-init` creates the standard `memory-bank/` structure in two modes:

- **Orchestration root (`CTX_DIR`)** — creates `<MB_ROOT>/memory-bank/` with
  proposal folders and `ums-repo.json` (see Repository Configuration); leaves
  `context.md` absent. The orchestration root is not
  bound by the mandatory core (see Memory Bank Document Set). After `mb-init`,
  the next step is the superpowers workflow — Target-MB Discovery & Pinning
  (below) creates `context.md` during brainstorming.
- **Project MB (`PLAN_MB`)** — creates `<MB_ROOT>/<path>/memory-bank/` with
  `proposals/{next,active,completed,abandoned}/` and project docs. Used when
  initializing project MBs for new components. Does not touch `CTX_DIR`.

## Memory Bank Document Set

**Mandatory core of a project MB:** `brief.md`, `architecture.md`, `tech.md`.

**First-class optional:** `playbook.md` — prescriptive procedures (see
Document Ownership and the Playbook Contract below).

**Free extension:** any further document the MB needs (`data-flows.md`,
`use-cases.md`, `open-questions.md`, `tasks.md`, …). These carry no normative
status; skills update them when they exist and never create them speculatively.

The orchestration root (`CTX_DIR`) is NOT bound by the core — it holds
`context.md` plus whatever navigation the orchestrated tree needs.

`brief.md` covers what earlier versions split between `brief.md` and
`product.md`. Canonical section order (sections without content are omitted,
never created empty):

```markdown
# Brief — <name>

## Co to je
## Klíčové funkce            (or Rozsah, depending on the component)
## Pro koho a hodnota
## Rizika
## Stav a historie
```

### Legacy shape tolerance

Permanent, like the `proposal_` grandfather clause. No MB is forced to migrate
in order to stay valid.

- **Reading:** when `product.md` exists, read it as well. When `playbook.md`
  is absent and `tasks.md` exists, read `tasks.md` in its place.
- **Writing procedures:** into `playbook.md` when it exists; otherwise into
  `tasks.md` when it exists; otherwise create `playbook.md`.
- When `tasks.md` serves as the Memory Bank's procedure document in this way
  (no `playbook.md` present), the Playbook Contract's consult-before-write
  regime binds it in that role — the protection follows the content, not the
  filename.
- Migration to the current shape is performed by the `mb-migrate-docs` skill,
  never as a side effect of unrelated work.

### Playbook Contract

`playbook.md` is prescriptive: **how this project is built, tested and
changed.** Authored by humans and by experience, not derived from code.

**Write regime — consult before writing.** `playbook.md` is NEVER changed
without the user's approval. An agent may propose anything — add an entry, fix
a superseded procedure, rephrase it, delete one that stopped being true — but
every change is presented for approval before it is written. The rule binds
every writer, `mb-sync` included. The automatic current-state pass that
`brief.md`, `architecture.md` and `tech.md` undergo (Harvest Contract §3) does
NOT apply here: the content does not come from code, so it cannot be verified
against code either.

**Exception — `mb-init`'s initial creation.** The first `playbook.md` that
`mb-init` writes, from the build and test commands it detected, needs no
approval: there is nothing yet to overwrite, and detected build commands are
verifiable against the build files themselves — unlike the experience the
consult rule exists to protect. Every LATER change to `playbook.md` follows
the consult rule above.

**Two consult styles, both legal.** `mb-sync` proposes a correction
immediately, at the point where it notices drift; `mb-harvest` batches
candidates into one end-of-branch gate. Both satisfy consult-before-writing —
neither is drift to reconcile with the other.

**Entry format** is free (heading + steps). When a persisted candidate carried
evidence, a one-line `Proč:` travels with it — the reason is part of the
procedure, not noise.

**Candidate collection during work.** Procedural knowledge is gathered while
the work happens, into
`<MB_ROOT>/.superpowers/playbook-candidates/<slug>.md` (git-ignored scratch,
English, first line `# Playbook candidates — work item: <slug>`). **One file per
work-item slug.** Files of FOREIGN slugs have their own paths and are never
overwritten and never deleted.

The overwrite licence for the CURRENT slug's file is narrow and keyed to git —
**tracked means live:**

- **Untracked** — ordinary git-ignored scratch. When its content is stale (a
  leftover of a slug whose work already finished or was abandoned) it is
  OVERWRITTEN; there is nothing to lose.
- **Tracked** — `mb-park` committed it (below), so it is **live parked
  evidence**. It is NEVER overwritten, not even for the slug currently being
  resumed: work continues by APPENDING to it, and only the harvest removes it,
  after its content has reached `playbook.md`.

The former single fixed path assumed strictly serial work, so once live tickets
were interleaved its overwrite rule deleted living evidence; the tracked/untracked
test is what keeps the same accident from returning through a resumed slug.

**`mb-park` commits the current slug's file to the ticket branch** (`git add -f`,
because `.superpowers/` is git-ignored), and the harvest deletes it after writing
the approved entries into `playbook.md`. This is a **named exception** from "the
scratch tree is git-ignored", valid for this one file only: parking must not
lose evidence that exists nowhere else.

Writers: implementer subagents report candidates in their report section
`## Playbook candidates`; the driving session — the same actor named in
"`context.md` Schema & Writers", i.e. the session dispatching the subagents —
COPIES confirmed ones into the collection file without rephrasing; sessions
outside SDD write directly.

Candidate format — the first three fields are mandatory, an entry missing any
of them is not written:

```markdown
## <short title>
- **Tried:** <what was attempted>
- **Happened:** <what actually happened — the evidence>
- **Procedure:** <the rule that follows from it>
- **Target MB:** <path>/memory-bank/        (only when harvest spans several MBs)
- **Corrects:** <existing playbook entry>   (when it contradicts an entry already there)
```

A candidate without a `Target MB` field, in a harvest spanning several Memory
Banks, defaults to `PLAN_MB`. A candidate whose `Corrects` names a
`playbook.md` entry that no longer exists is presented as a NEW entry instead
— tell the user the entry it meant to correct is gone.

The ban on invention is enforced by the FORMAT, not by a request in a prompt:
without `Happened` there is no entry.

## Scope Lock (Memory Bank documents only)

The scope lock governs **Memory Bank document writes only**:

- MB documents are written only under `CTX_DIR`, `PLAN_MB`, and — during
  harvest — `AFFECTED_MBS`.
- Superpowers spec/plan documents are written only under
  `<PLAN_MB>/proposals/` (see Superpowers Document Placement).

Explicitly **legal and outside this lock**:

- Source-code changes anywhere in the repository.
- The superpowers scratch tree `<MB_ROOT>/.superpowers/` (task briefs,
  implementer reports, review packages, progress ledger,
  `playbook-candidates/<slug>.md`) — git-ignored, ephemeral, owned by the
  superpowers execution skills and the Playbook Contract. One named exception to
  the git-ignored rule: `mb-park` commits the CURRENT slug's candidate file to
  the ticket branch, so parking loses no evidence (see Playbook Contract).
- Plan checkboxes and task-progress tracking inside the plan file and the
  `.superpowers/sdd/` ledger.

Other rules:

- Do not hardcode machine-specific or repository-root absolute paths.

### Link Conventions

- **Relative to the containing file, always.** A link in a Memory Bank document
  is resolved from the directory of the file it stands in — never from the
  Memory Bank root, the project root or the repository root. This is the single
  most common defect in practice: a link written against the MB root inside a
  document that lives two levels below it, in `proposals/<state>/`.
- **No `#fragment` anchors.** Name the section in words instead:

  | Instead of | Write |
  |---|---|
  | `[X](architecture.md#kritické-detaily)` | `[architecture.md](architecture.md), sekce „Kritické detaily“` |
  | `[X](#mimo-rozsah)` (same file) | `sekce „Mimo rozsah“` |
  | `[X](KicSetup.iss#L253-L254)` | `[KicSetup.iss](KicSetup.iss), řádky 253–254` |

  The reason is not style: heading slugs are **renderer-specific**. Bitbucket
  Cloud, GitHub and IDE preview each derive a different slug from the same
  heading, so an anchor that resolves in one viewer silently dead-ends in the
  others, and no single spelling can be correct everywhere. A section title is
  stable across all of them, survives a renderer change, and stays meaningful in
  a plain-text read. It follows that headings must never be reworded merely to
  make a slug come out a particular way.
- **A link whose target cannot be determined is not left dangling.** Drop the
  link syntax, keep the text, and mark it with the dead path inside the marker:
  `` `TestBase.cs` [ODKAZ K OVĚŘENÍ: ../TestBase.cs] ``. The marker is greppable
  and carries enough to act on later; a bare dead link carries neither.
- **Never repoint a link across projects to make it resolve.** If a path pointed
  inside the document's own project and the file is not there, it was dropped
  from that project — aiming the sentence at a same-named file elsewhere changes
  what the sentence claims. Mark it and let a human decide.
- **Never link the plan half.** No document links `plan_<slug>.md` — not the
  design header, not a Memory Bank document, not another proposal. The plan is
  **deleted at harvest** (Archival asymmetry), so any link to it is a dead link
  the moment the work completes, and it dies inside `proposals/completed/`,
  which is an immutable archive nobody may repair. Cross-references between the
  halves therefore run one way only: the plan links the design
  (`**Návrh:** [design_<slug>.md](design_<slug>.md)`), never the reverse. Where
  a document must mention the plan, name it as plain text — the pair is found
  by slug, not by link.
- Enforced and consolidated by the `mb-link-audit` skill (read-only audit,
  `-Apply` for the mechanically determinable classes).

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
| `protectedBranches` | the `pre-push` hook (through the generated list below), `guard-git-push.mjs` |
| `ticketPattern` | `mb-state`, the entry gate, `mb-architect-review` |
| `projectMarkers`, `sharedRoots` | the intersection heuristic (see Base Sync & Drift Detection) |

**`baseRef` is a fully-qualified remote-tracking ref** (`origin/develop`,
`origin/ums-memory-bank`) and is used as-is wherever git READS the base: a merge
source, a merge-base, a diff endpoint, a `switch -c` start point, a
`switch --detach` target. It is never prefixed with `origin/` a second time —
`origin/origin/develop` resolves to nothing.

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
`baseRef`.

**A missing file is not an error, and the degradation leans to the safer
side:** `baseRef` falls back to `origin/develop`; `protectedBranches` falls back
to the built-in list, i.e. to *more* protection, never less; and without
`projectMarkers` / `sharedRoots` the verification after a base merge is offered
for **every** non-empty incoming diff rather than for none.

**Every list-valued key accepts a bare string as a single-element list**, and every
consumer must normalize it the same way: `"protectedBranches": "Branches/*"` means
exactly `["Branches/*"]`. The rule exists because `protectedBranches` has two
independent enforcement layers — the generated list the `pre-push` hook reads, and
`guard-git-push.mjs` — and **they must never give different answers for the same
configuration**, which a shape one layer accepts and the other rejects guarantees
they would.

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

## Base Sync & Drift Detection

The base ref is merged into the ticket branch at **phase boundaries** only:

- before `writing-plans`,
- before dispatching the first task,
- before a design-review request and before a design-review resume,
- before the whole-branch review,
- before `mb-harvest`.

**Never in the middle of a task.** A task that starts on one tree and finishes on
another cannot be reviewed against its own brief.

Sequence at a boundary: `fetch` → `merge <baseRef>` → intersection
assessment → verification where it applies → push.

There is no separate commit step: `merge` creates the merge commit itself, and it
is **not** deferred with `--no-commit` until verification passes — verification is
supposed to run on the merged tree, which is the whole point of merging first, and
a red result is reported, not un-merged (see the STOP rule below). **Only the push
waits.** It may be deferred to the end of the phase boundary so that a handoff
publishes the merge and the handoff commit in one push (Architect Review Gate).

**Intersection assessment.** Both sets are computed **after `fetch` and before
`merge`**, from the same merge-base:

```bash
MB=$(git merge-base HEAD <baseRef>)
prichozi=$(git diff --name-only $MB..<baseRef>)
vlastni=$(git diff --name-only  $MB..HEAD)
```

In the design phase the role of the **own** set is played by the target areas
named in the design document — there is no code diff of one's own yet.

**Mechanics without ecosystem knowledge.** Each path maps to the **nearest
ancestor directory containing a match for `projectMarkers`** (a path with no such
ancestor stays itself), and the intersection is sought over those owners; a path
matching any entry of `sharedRoots` is **always intersecting**. **How a
`sharedRoots` entry matches:** an entry ending in `/` is a **path prefix** — every
path under that directory matches, at any depth — and any other entry is a **glob**
against the whole path. Both spellings are needed and neither can stand in for the
other: `mb-init` writes directories with a trailing slash
(`ums/.claude/skills/shared/`), and a trailing-slash directory is not a glob, so
glob-only matching would miss every file inside it. This is
explicitly a **heuristic, not proof** — it decides whether verification is
offered, never whether the work is correct.

**Graduated verification:**

- No intersection → no verification; a single-line statement of the fact is the
  whole report.
- Intersection → the agent lists the intersecting paths and **offers** a baseline
  with a recommendation; the user decides.
- A merge conflict counts as an intersection automatically.
- In the design and design-review phases nothing is built, so it is purely an
  offer.
- Before dispatching the first task a baseline is mandatory already today.

**STOP applies only where verification actually ran and came back red.** Someone
else's breakage of the base is not repaired inside a ticket branch — report it
and let the user decide.

**Conflict handling.** The agent resolves merge conflicts only in files it
changed on this branch itself; anything else is a STOP. A `context.md` conflict
is always resolved by keeping the ticket branch's version, targeted:
`git checkout --ours memory-bank/context.md` — **never `merge -X ours` over the
whole merge**, which would silently drop incoming content everywhere else.
`context.md` is the state of THIS branch, not a fact about the product. A
conflict on the SAME slug in `proposals/active/` is two actors colliding over one
work item, therefore a STOP.

## Workspace Discipline

A **workspace** is a clone the user works in. The user creates it and chooses
it; it is used repeatedly and it carries the leftovers of previous work. The
layer therefore treats a workspace as found, never as freshly provisioned.

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

**"A free workspace" is a derived state, not a record.** It is derived from empty
output of all three of `git status --porcelain`, `git stash list` and
`git log --branches --not --remotes`, plus a **fourth signal none of those three
can report:** a non-empty **untracked** candidate file of the CURRENT slug,
`<MB_ROOT>/.superpowers/playbook-candidates/<slug>.md`. `.superpowers/` is
git-ignored, so `git status --porcelain` is silent about it while the evidence
exists in this workspace and nowhere else — probe it directly (does it exist, is it
non-empty, is it tracked, per `git ls-files --error-unmatch`). All four are derived
every time, never from a flag or a bookkeeping file that can go stale.

Leftovers split in two:

- **In the way** — a dirty tree, a stash, and a non-empty untracked candidate file
  of the CURRENT slug. They block a safe branch switch and must be resolved. The
  candidate file belongs here because it is non-recoverable by the classification
  above: switching away leaves it behind unattached to any branch, and committing it
  is what `mb-park`'s named exception exists for.
- **Merely present** — unpushed commits of other branches, candidate files of
  other slugs (and a TRACKED candidate file of the current slug — `mb-park` already
  parked it, so it is recoverable from `origin`). They are announced only; the agent
  does not touch them.

**Entry gate**, in four phases:

0. **Eligibility**, fail-closed except where stated: `MB_ROOT`, `memory-bank/`, a
   **fail-closed check of the git hooks**, and `git fetch origin`.
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
     and the intent phase's `git switch -c <branch> <baseRef>` has an explicit start
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
   and no auto-stash is permitted. Carrying the leftovers to the ticket branch is the
   single exception to that emptiness, and it is safe only because those leftovers
   were just enumerated by name in phase 1 and consciously kept — never for content
   nobody accounted for.
3. **Intent:** a local branch for the ticket exists → resume; the ticket is
   active on a foreign branch → STOP (cross-clone collision check); a
   preliminary design draft waits in `next/` → activation; otherwise a new
   branch.
4. **Pin write** into `context.md`.

The hook check is the most important agent duty in this model, because the user
creates the workspace and **git hooks do not travel with a clone** — a workspace
that looks exactly like a working one can be missing the whole publication
guarantee (see Publication Contract).

**Switching branches:** only with `git status --porcelain` empty, **no switching
through `git stash`, no auto-stash** (the same rule as branch sync in
`mb-architect-review`), and only at phase boundaries. The single exception is the
base-IDLE remedy of phase 2 above — leftovers the inventory just named and the user
chose to keep ride with the branch-creating `switch -c` on purpose, because on the
base there is nowhere else for them to go.

**Park** (the `mb-park` skill) is the third end of a work item's life cycle,
alongside completion (harvest) and abandonment (`mb-abort`): commit, push,
announce the leftovers, commit the current slug's playbook candidates (Playbook
Contract), leave the branch checked out, and leave `context.md` in the ACTIVE
state — a state name, not a literal token; the test is the pin in the
`## Active Work` block (see the `context.md` Schema & Writers section). Parked
work is recoverable from `origin` by definition, which is why it does not block
starting another ticket (Active Work Item).

**One session per workspace.** Work on several tickets is interleaved, not
parallel — two sessions in one clone would fight over the same working tree and
the same `context.md`.

Life-cycle operations (harvest, `mb-abort`, Jira finalization) always run on that
ticket's own branch.

## Active Work Item (Design + Plan Pair)

One active work item per **branch** = one **design + plan pair** in
`<PLAN_MB>/proposals/active/`. The limit is per branch because every branch
carries its own pin in its own `context.md`; a parked work item on another branch
therefore does not block starting a new one (see Workspace Discipline).

- **`design_<slug>.md`** — the spec, written by `brainstorming`
  (intent source of truth).
- **`plan_<slug>.md`** — the implementation plan, written by
  `writing-plans` (execution source of truth). On conflict between the two,
  the plan governs execution; report the discrepancy to the user.

Rules:

- The pair is created by the superpowers workflow and is never duplicated into
  `docs/` or any parallel location.
- Task progress lives in the plan file's checkboxes and in
  `.superpowers/sdd/<plan-basename>/progress.md` — **not** in `context.md`.
- **Archival asymmetry:** on **completion** (harvest → `completed/`) only the
  design half is retained; the plan half is **deleted** — after implementation
  its task steps are spent; code, git history and the harvested current-state
  MB docs carry the outcome. If there is no design half (grandfathered single
  plan), archive that plan to `completed/` instead of deleting it. Because the
  plan does not survive, no document may link it (Link Conventions). On
  **abandon** (`mb-abort` / Discard → `abandoned/`) both halves move together,
  unchanged, nothing deleted. If a half is missing at archive time, warn and
  handle what exists.
- A design file without its plan sibling is a valid intermediate state
  (between brainstorming and writing-plans).
- An empty `proposals/active/` directory may be absent from the working tree
  (git does not track empty directories). Skills MUST tolerate the missing
  directory and recreate it on demand — absence of `active/` means "no active
  work", not a broken Memory Bank.

**Naming:** `design_<slug>.md` / `plan_<slug>.md`. The slug MUST start with
the ticket code whenever one is known: `<jira>_<short_snake_case_topic>`,
ticket code normalized to lowercase snake case
(`UMS-3302` → `ums_3302_toast_reconcile`); without a known ticket use
`<short_snake_case_topic>` alone. ASCII only, no diacritics, no dates in the
name. When the ticket becomes known later, rename the slug's files to include
it (within the same naming style).

**Branch name derived from the slug.** The ticket branch is
`<TICKET>-<kebab-slug>`: take the slug, replace `_` with `-`, and upper-case the
leading ticket code (`ums_3302_toast_reconcile` → `UMS-3302-toast-reconcile`).
The derivation runs **one way only** — the slug names the documents and the branch
name follows from it. Nothing parses a branch name back into a slug: a ticket
branch is recognized by the ticket code it contains (Architect Review Gate,
branch sync), and the slug is then read from `context.md` on that branch, which
is also why a branch whose name carries diacritics stays valid without renaming.

**Grandfather clause (legacy `proposal_` naming):** files named
`proposal_<slug>-design.md` (design half) and `proposal_<slug>.md` (plan
half, or a v1 single plan) remain valid artifacts wherever they rest —
`active/`, `next/`, `completed/`, `abandoned/`. Never rename or convert them,
with ONE exception: activating a queued legacy draft from `next/` converts
the work item to the new style (see Preliminary work items below). One work
item uses exactly one naming style; a mixed pair (legacy design + new plan or
vice versa) must never be created. Never touch archived files in
`proposals/completed/`.

**Discovery & pairing rule (all skills):** match files
`{design_,plan_,proposal_}*.md`; strip exactly ONE prefix
`^(design_|plan_|proposal_)` from the file stem, and strip the `-design`
suffix ONLY after the `proposal_` prefix; group by `(owning MB root, slug)`.
One pair (or grandfathered single file) = one candidate. Thus `design_x.md`
→ slug `x`, while legacy `proposal_design_x.md` → slug `design_x` — no
mis-pairing.

**Preliminary work items (`next/`):** work may be planned ahead as design
drafts in `<MB>/proposals/next/` — any number may queue there. A preliminary
draft is a single **`design_<slug>.md`** with design-document structure
(`## Cíl`, `## Scope`, `## Technický návrh`, scaled to what is known).
Detailed implementation plans are NOT written ahead — the plan is produced by
writing-plans after activation. Rules:

- Creating or editing a preliminary draft does NOT touch `context.md`, does
  not require the IDLE state, and does not pin a Target MB.
- When work starts, ALL files of the slug move from `next/` to `active/`
  (see Target-MB Discovery & Pinning). A legacy `proposal_*` draft is renamed
  to `design_<slug>.md` during this move — the only permitted legacy
  conversion; its content serves as the design seed regardless of its
  original structure, and brainstorming refines it rather than starting from
  scratch.
- Queued items in `next/` never count against the two-actives guard.
- A queued item dropped without being started moves to `abandoned/`
  unrenamed.

## Superpowers Document Placement

This section implements the upstream escape hatch — brainstorming and
writing-plans both state: *"(User preferences for spec/plan location override
this default)"*. The preference in this repository is:

| Superpowers artifact | Default upstream location | UMS location |
|---|---|---|
| Design/spec (brainstorming) | `docs/superpowers/specs/…-design.md` | `<PLAN_MB>/proposals/active/design_<slug>.md` |
| Implementation plan (writing-plans) | `docs/superpowers/plans/….md` | `<PLAN_MB>/proposals/active/plan_<slug>.md` |

Prohibited locations (mechanically enforced by a PreToolUse hook):
`docs/superpowers/specs/`, `docs/superpowers/plans/`, `docs/plans/`.

Document headers:

- `design_<slug>.md` starts with:
  ```markdown
  # Návrh: <název>

  - **Jira:** UMS-XXXX | (žádný tiket)
  - **Target MB:** <relative path>/memory-bank/
  - **Vytvořeno:** YYYY-MM-DD
  ```
  The header carries **no reference to the plan half** — the plan is named
  `plan_<slug>.md` by the naming rule, so the field added nothing and became a
  dead link the moment harvest deleted the plan (Link Conventions).
  Body sections follow the established proposal corpus: `## Cíl`, `## Scope`,
  `## Technický návrh`, `## Dopady`, `## Rizika` (scaled to complexity).
- `plan_<slug>.md` keeps the upstream plan header verbatim (the
  "For agentic workers: REQUIRED SUB-SKILL …" block is load-bearing for
  subagent-driven-development), followed by an MB metadata block (`**Jira:**`,
  `**Návrh:** [design_<slug>.md](design_<slug>.md)`, `**Target MB:**`), then the
  upstream structure (`## Global Constraints`, tasks with `**Interfaces:**`
  and checkbox steps).

## Target-MB Discovery & Pinning

Runs **during brainstorming**, as soon as the affected code area is
identifiable — always before the design document is written.

1. Scan `**/memory-bank/proposals/active/` for `{design_,plan_,proposal_}*.md`
   under `<MB_ROOT>`, then run the `mb-doc-index` skill **with `-Json <path>`**
   and take the candidate set as the UNION of the local scan and the index
   over `origin`. The `-Json` output is required, not optional: step 2 below
   normalizes every match to its owning `memory-bank/` root, and only
   `entries[].path` carries that path — the printed table deliberately does
   not. Keep the JSON for the rest of the session (`mb-epic-graph -IndexFile`
   consumes the same file).
2. Normalize each match to its owning `memory-bank/` root; apply the
   Discovery & pairing rule (Active Work Item section): strip exactly one
   prefix, `-design` only after `proposal_`, group by `(owning MB root,
   slug)` — one pair (or legacy single file) = one candidate.
3. Treat `CTX_DIR` as the orchestration root and exclude it from
   affected-project discovery unless the work is intentionally repo-wide.
4. Derive deterministic evidence tags per candidate root:
   - `seed_hit` (matches user seed context),
   - `active_hit` (matches current active work context or `Target MB Pin`),
   - `explicit_hit` (explicit user path).
   Candidates without any evidence tag are `untrusted` and cannot silently
   resolve ambiguity.
5. Resolution:
   - Exactly one trusted candidate → use it.
   - Exactly one untrusted candidate → ambiguous; do not auto-select.
   - Multiple trusted candidates → stop and ask exactly one disambiguation
     question with three options; the user always decides:
     - **A:** most affected project MBs (trusted candidates sorted by
       `score desc`, tie-break `path asc`),
     - **B:** nearest common project directory over the option-A candidates
       (if it has no `memory-bank/`, route to `mb-init`),
     - **C:** explicit directory provided by the user (outside `<MB_ROOT>`
       requires explicit cross-project confirmation).
   - Zero trusted candidates → do not guess. Ask the user for the target
     project path, or route to `mb-init` for a new component.
6. **Preliminary-queue activation:** check the selected MB's
   `proposals/next/` for a queued preliminary proposal matching the work
   (explicit user reference, ticket code, or topic — when the match is only
   probable, confirm with the user). On confirmation, move ALL files of its
   slug from `next/` to `active/`, renaming a legacy `proposal_*` draft to
   `design_<slug>.md` (the only permitted legacy conversion), reuse its slug
   and ticket, and treat the draft as seed input for the design. No match →
   continue with a fresh proposal.
   The queued draft may live on a foreign branch — the index reports it. Take it
   over by blob copy per Cross-Branch Visibility (never cherry-pick) and record
   `**Převzato z:** <branch>@<sha>` in its header.
7. Ask for the Jira ticket (one question; "none" is a valid answer; skip if
   already known from the activated preliminary proposal). If the ticket is
   known and the slug does not start with its code, rename the slug's files
   accordingly (Naming rule in the Active Work Item section).
8. **Two-actives guard:** an active proposal (pair or legacy single) with a
   *different* slug anywhere under `<MB_ROOT>` must be in one of **three**
   resolved states before new work is pinned — finished
   (`finishing-a-development-branch` → harvest), **parked** (`mb-park`), or
   abandoned (`mb-abort`). Which of the three needs a question is decided by the
   recoverability test below: unresolved work stops and asks the user, whereas
   work that is already parked is merely announced. Only `active/` counts;
   queued items in `next/` are ignored by this guard.
   The two-actives guard stays LOCAL; extending it to `origin` would forbid
   parallel work across the team. **The limit is per BRANCH, not per workspace,
   because each branch holds its own pin.** The guard therefore stops only when
   the active slug on the CURRENT branch is **not recoverable from `origin`** —
   it has uncommitted changes or unpushed commits. Committed and pushed work of
   another ticket is **parked** (Workspace Discipline), and starting a new ticket
   on a new branch is then normal operation: announce the parked item, do not
   stop. Alongside it runs the **cross-clone collision check**:
   the SAME slug or the SAME Jira ticket active on a foreign branch is a
   fail-closed STOP (double work), and the report carries the branch and the last
   commit date so the user can tell an abandoned branch from live work. Foreign
   active slugs of OTHER tickets are normal parallel operation — list them, never
   stop.
   **Run it with the intent DECLARED** — the ticket is known by now (step 7
   asked for it) and the slug usually is too:

   ```powershell
   pwsh <mb-doc-index>/scripts/doc-index.ps1 -Jira <ticket> [-Slug <slug>]
   ```

   This is not optional polish. At this point in brainstorming the design
   document does not exist yet, so the local set is empty and a
   local-versus-foreign comparison has nothing to compare: without `-Jira` /
   `-Slug` the colleague's active work on the very same ticket is reported as
   ordinary parallel work (INFO, exit 0) and both actors proceed. With the
   intent declared, the run exits `2` and the STOP fires. Exit `2` here blocks
   pinning; the decision (take over, wait, or proceed deliberately) is the
   user's, never the agent's.
9. Persist into `CTX_DIR/context.md` (creating the file if absent):
   `Target MB Pin`, `Jira`, `Work item` slug and `Started` (see the schema
   below).
10. Invalidation: the pin (and thus `PLAN_MB`) becomes invalid when the active
    proposal slug changes or the pinned path no longer exists — re-run this
    discovery, do not silently fall back.

## `context.md` Schema & Writers

`<CTX_DIR>/context.md` is a small state file — the workflow itself lives in
the superpowers skills and the design + plan pair.

Active state:

```markdown
# Context

## Active Work

- **Jira:** UMS-XXXX (https://jira.datasys.cz/browse/UMS-XXXX)
- **Target MB Pin:** <relative path>/memory-bank/
- **Work item:** <slug>
- **Started:** YYYY-MM-DD
- **Review:** design-review requested YYYY-MM-DD
```

The `Review:` line is OPTIONAL — present only between an architect-review
request and its resume (see Architect Review Gate). While present, the
superpowers workflow MUST NOT continue past brainstorming (no writing-plans);
the correct continuation is `mb-architect-review` (resume).

IDLE state: replace the `## Active Work` items with
`(No active work - IDLE phase)`; keep the `- **Jira:** …` line of the last
work item if it existed.

**ACTIVE and IDLE are state NAMES, not tokens in the file.** The word `ACTIVE`
never appears in `context.md`, so no skill may look for it — a grep for it
matches nothing and would report every branch as idle. The mechanical test is
whether the `## Active Work` block **carries a pin**: a `Target MB Pin` together
with a `Work item` slug is the ACTIVE state; the `(No active work - IDLE phase)`
marker, or a block with no pin, is the IDLE state. Wherever this contract says a
branch is ACTIVE or IDLE, it means the outcome of that test.

Readers MUST accept the legacy field name `- **Proposal:**` as an alias of
`- **Work item:**` (stale files from contract v2.0); writers write only
`Work item`.

Writers (no other writer is allowed):

- **The driving session** during Target-MB Discovery & Pinning — creates or
  updates `## Active Work`.
- **`mb-harvest`** (and `mb-abort`) — resets `## Active Work` to IDLE.
- **`mb-architect-review`** — adds (request) and removes (resume) the
  `Review:` line only.

The v1 fields `Status`, `Run Mode`, `Execution Mode`, `Loop Mode`,
`Affected MBs`, `Implementation Checklist`, and `Auto Loop State` are
abolished — do not write them; ignore them when found in a stale file.

## MB Context Reading Rule

Before proposing approaches (brainstorming) and before writing the
implementation plan, read `<PLAN_MB>/brief.md`, `architecture.md`, `tech.md`
and `playbook.md` (those that exist; legacy shape per Memory Bank Document
Set), plus the root `memory-bank/architecture.md` and `tech.md` when the work
is cross-cutting. `playbook.md` is prescriptive — its procedures BIND the work,
they are not background reading. The rest is current-state reference: treat it
as authoritative context, and note in the design when it is stale (the fix for
staleness is `mb-sync` or the harvest at finish, not ad-hoc edits).

Every link WRITTEN into a Memory Bank document — by any skill, harvest or
ad-hoc edit — follows Link Conventions (Scope Lock): relative to the containing
file, no `#fragment` anchors.

## Document Ownership

One fact, one home. Duplication between documents is prevented by ownership,
not by asking writers to be careful.

| The question the fact answers | Home |
|---|---|
| What it is for, for whom, what value it has, what state it is in | `brief.md` |
| What parts it consists of, who talks to whom and how, which pattern it follows | `architecture.md` |
| What it runs on and with — stack, versions, dependencies, configuration, build, deployment | `tech.md` |
| How do I do X — commands, procedures, conventions, traps | `playbook.md` |

**Decision test for the contested `tech` × `architecture` pair** —
deliberately a test, not a taxonomy, because a taxonomy can be bent:

- Does the fact change when you **swap a library or version and leave the code
  alone**? → `tech.md`
- Does it change when you **rewrite the code and leave the dependencies
  alone**? → `architecture.md`
- Does it change in **both** cases (typically "the workflow engine runs on
  Orleans")? → it belongs where the reader looks first, and the other document
  **links** to it with a relative link. It never restates it.

**A fact that already has a home keeps it.** The "reader looks first" question
decides where a NEW fact goes; it is not re-litigated afterwards. The sweep's
"wrong home" verdict (Harvest Contract §3) therefore fires only when branch 1
or branch 2 of the test clearly names a different document — never for a
"both" fact that is already placed. Without this rule two successive harvests
can move the same fact back and forth.

The third case carries the rule. Duplication does not arise for facts that
clearly belong somewhere — it arises for the ones that belong in both.

**Moving a fact is a legal operation.** `mb-harvest` and `mb-sync` may move a
fact between documents of the same MB. The order is binding: **write into the
target first, only then delete from the source.** Every move is named in the
skill's report, so it is visible both there and in the commit diff. This is
deliberately visibility, not a mechanical check — a move is a local edit
someone reads at commit time.

## Harvest Contract

Consumed by `mb-harvest` (invoked from the finishing-a-development-branch
overlay, or standalone). Code is the source of truth; documentation follows
code.

1. **Preconditions (fail-closed):** `context.md` has a `Target MB Pin` and
   `Work item` slug; the active proposal (pair or legacy single) exists in
   `<PLAN_MB>/proposals/active/` and matches the slug.
2. **Affected MBs:** derive from
   `git diff --name-only $(git merge-base <baseRef> HEAD)..HEAD`
   (`baseRef` per Repository Configuration), mapping each
   changed path to its nearest owning `memory-bank/` directory. Fall back to
   asking the user when the diff is unavailable.
3. **Harvest style — CURRENT-STATE (MANDATORY):** the current-state documents
   (`architecture.md`, `tech.md`, `brief.md`) describe the current state in
   present tense, as reference documentation. They are NOT a changelog.
   `playbook.md` is NOT one of them — it changes only through the gate below.
   - Place every fact in its owning document (see Document Ownership); fold it
     into the relevant current-state section and do not duplicate a fact that
     is already described elsewhere.
   - DO NOT create or append dated changelog sections ("Nedávné změny",
     "Recent Changes", "Changelog", "Historie změn", "Naposledy provedeno").
   - History lives in `proposals/completed/` and git — never in state docs.
   - When a change removes something, describe the new state; do not narrate
     the removal.
   - Continue with remaining affected MBs if one update fails; capture
     failures for the final report.

   **Staleness sweep (cheap, MANDATORY):** for each affected MB, grep ALL its
   `memory-bank/*.md` documents for the key symbols, element ids and variable
   names touched by the branch diff. Each hit has one of three outcomes:
   1. the hit describes a **superseded** state → fold it to current state;
   2. the hit is the fact's **existing home** → do not write a second copy;
      update it in place;
   3. the hit sits in the **wrong home** → move it per Document Ownership.

   One pass therefore detects staleness and duplication alike. Report every
   move.

   **Playbook gate (a non-autonomous step of the harvest):** when
   `<MB_ROOT>/.superpowers/playbook-candidates/<slug>.md` of the current work
   item is non-empty, present the candidates with their evidence to the user
   ONCE and let them choose. Approved ones are translated into Czech and written
   to `playbook.md` of the target MB — or of the MB named by the candidate's
   `Target MB` field. A candidate carrying `Corrects` is presented NEXT TO the
   entry it contradicts, and the user decides between replacing it, keeping both,
   or dropping the candidate. Unapproved candidates vanish with the file; report
   their count. A missing or empty file for the current slug skips the gate
   without a question; files of other slugs are not read and not touched.
   After the gate, DELETE the current slug's file — `git rm` when `mb-park`
   committed it (Playbook Contract), plain deletion otherwise — so no spent
   candidates travel on into the base.
4. **Archive:** move only the design half `design_<slug>.md` (or legacy
   `proposal_<slug>-design.md`) from `active/` to `completed/` unchanged
   (durable spec record) and **delete** the plan half `plan_<slug>.md` (or
   legacy `proposal_<slug>.md`) (remove the file; the harvest commit records
   the deletion). If there is no design half (grandfathered single plan),
   archive that plan to `completed/` so a record remains. Abandon path
   (`mb-abort`, or Discard in finishing) moves BOTH halves to `abandoned/`
   instead, deleting nothing.
5. **Reset:** only if every affected MB update succeeds, reset
   `context.md` `## Active Work` to IDLE per the schema above. On partial
   failure, leave `context.md` unchanged and report.
6. **Announce (Czech)** and offer `mb-jira-update` when a Jira ticket is
   linked.

All harvested document content is Czech.

## Publication Contract

**No reference without reachability.** Whenever the workflow names a git object
outside this clone — a link in a ticket description or comment, a wave table, a
handoff comment, a link in an epic ledger — the pinned commit MUST be reachable
on `origin` at that moment. Verify mechanically:

```bash
git fetch origin
git branch -r --contains <sha>     # empty result = not on origin
```

An unreachable commit is a fail-closed STOP with an offer to publish, never a
warning.

**The publication rule: the agent pushes its OWN ticket branch after every
commit**, always announcing the branch and the outgoing commits. Publication is
therefore not a list of milestones to remember but the normal end of every commit
on a ticket branch — a commit that is not pushed is work only this workspace can
see. The points below remain listed as its notable special cases, not as the
whole rule:

1. after the design document is written and committed (brainstorming),
2. after the implementation plan is written and committed (before the first task
   dispatch),
3. after an implementer's commit for a task that verified green,
4. after the commit that merges the base ref into the ticket branch (see Base
   Sync & Drift Detection),
5. at elaboration window closure, BEFORE writing links into Jira,
6. before every handoff (design review request/respond is the reference
   implementation),
7. after the Memory Bank changes of a harvest are committed.

**Two-tier push policy:**

| Tier | Rule |
|---|---|
| The actor's own ticket branch (unprotected) | The agent pushes it itself — publishing its own branch is not a decision it puts to the user — but it ALWAYS announces the branch and the outgoing commits. The harness's own permission prompt still applies (`Bash(git push:*)` is deliberately in neither `allow` nor `deny`, so the tool call is confirmed like any other): "does not ask" means it does not negotiate whether to publish, not that the push is auto-approved. Force push is forbidden. |
| Shared branches (the effective list is `protectedBranches` — see Repository Configuration; the built-in fallback is `develop`, `main`, `master`, `release/*`) | The agent NEVER pushes. It prepares the exact command with the outgoing commits and the user approves or runs it (in-session: `! UMS_ALLOW_SHARED_PUSH=1 git push origin HEAD:<baseBranch>` — the refspec form, because integration pushes the ticket branch onto the base ref; see the human escape below). The agent then re-verifies reachability. |

The actual guarantee is the git `pre-push` hook (`.claude/hooks/pre-push`,
scoped to `refs/heads/*` — tag pushes are out of scope and always pass
through), installed into each workspace by `install-git-hooks.ps1` — hooks do
not travel with a clone, which is why the entry gate verifies them (Workspace
Discipline). Verify it
non-destructively — never with a real `git push origin develop`, which
either publishes real commits if the hook turns out to be inert (this is
exactly how a linked-worktree installation gap was first confirmed) or
prints a misleading "Everything up-to-date" when there is nothing to push:
resolve the installed path with `git rev-parse --git-path hooks/pre-push`,
confirm it exists and carries the `UMS pre-push guard` marker near the top,
then pipe a synthetic line straight into it (`printf 'refs/heads/develop
<sha> refs/heads/develop <sha>\n' | <hook path> origin verify`), expecting a
non-zero exit and the `UMS:` message, AND the mirror-image accept case (a
synthetic ticket-branch creation must exit 0, silently) — without that
second half a hook that cannot execute at all also "rejects" everything and
passes as verified. `install-git-hooks.ps1` runs both checks itself after
installing, reports the result and exits non-zero whenever the guarantee is
not in place.

**The human escape: `UMS_ALLOW_SHARED_PUSH=1`.** A git hook cannot tell a
human from an agent, so the rule above — which asks the USER to publish a
shared branch — would otherwise be blocked by the layer's own guard, with no
way through it that is not also a way around every other hook. The escape
closes that: with `UMS_ALLOW_SHARED_PUSH=1` in the environment the `pre-push`
hook lets a push to a shared branch through (announcing that it did), and
`guard-git-push.mjs` does not stand in front of a command carrying it. It
lifts THAT ONE RULE and nothing else — branch deletion and force push stay
forbidden with it set. The hook's own rejection message names the escape, so
whoever hits the wall learns the way through it at that moment. **The escape
belongs to the human. An agent MUST NEVER set it** — not in a command, not in
its environment, not "just to unblock the merge": doing so silently converts
the two-tier policy into a one-tier one. Like every other rule of this layer
that no mechanism can enforce, that is a contract obligation, and it is the
reason the escape is a named variable rather than a flag the agent could
plausibly have typed by accident.

Two known, accepted bypasses — both require deliberate,
visible intent, unlike the CLI-spelling tricks this hook exists to close:
`git push --no-verify` skips it entirely, and a one-shot
`git -c core.hooksPath=<other> push` points git at a hooks directory this layer
never installed into. `--no-verify` is a BYPASS
of the guarantee, never the documented way to publish `develop`: it disables
every hook in the repository, so it is exactly as unsafe as it looks, and
`guard-git-push.mjs` denies it on sight (escape or no escape).

A **configured** `core.hooksPath` (local or global — routine with tools like husky
or pre-commit) is a different thing and is **not** a bypass. It moves the
directory git looks in, and every check in this layer resolves the hook through
`git rev-parse --git-path hooks/pre-push`, which honours it: the installer
installs there and proves the hook live there, and `mb-state` and the entry gate
find it there. The remaining concern is **provenance and scope**, not bypass — a
shared hooks directory may already hold another repository's `pre-push`, and an
install or a removal in it reaches every repository using that config. The
`UMS pre-push guard` marker check settles provenance, and an absolute value is
therefore reported as a scope warning rather than a missing guarantee (a relative
value is resolved per working tree instead, so each linked worktree needs its own
install). A missing or unmarked hook stays fail-closed either way. The PreToolUse hook
(`.claude/hooks/guard-git-push.mjs`) is only a best-effort, fail-open early
warning for the common accident, not a guarantee — it does not see shell
syntax the way git itself does, so it allows anything it cannot parse with
confidence. Neither hook stops a determined adversary; server-side branch
permissions on `origin` remain the real backstop for that. Other harnesses
follow this rule by contract text only, as with every other rule of this
layer. `mb-git-commit` never pushes — publication is a workflow step governed by
the publication rule above, not a job of the commit tool.

### Integration

Integrating finished work is a **fast-forward push of the ticket branch onto the
base ref**, not a local merge into a local base branch. The base has already been
merged into the ticket branch at the last phase boundary (Base Sync & Drift
Detection), so the ticket branch is a descendant of `<baseRef>` and the
push is a fast-forward. Sequence:

1. `git fetch origin`,
2. `git merge <baseRef>` on the ticket branch,
3. green verification (build and targeted tests),
4. the agent prepares the human command with the outgoing commits enumerated,
5. the user runs it — the base ref is a shared branch, so the agent never pushes
   it itself,
6. the agent re-verifies reachability **from the base ref**: `git fetch origin`,
   then `git merge-base --is-ancestor <sha> <baseRef>` (non-zero exit = not on the
   base). A bare `git branch -r --contains <sha>` is NOT sufficient here — the
   publication rule has already pushed that commit to the ticket branch on
   `origin`, so `--contains` reports the ticket branch, the result is non-empty and
   the check passes while the base carries none of the code. That is exactly the
   state this step exists to catch: the user never ran step 5, or it was rejected
   as non-fast-forward and nobody retried. The check must name the base, and it
   must run with **no** Jira ticket too — `mb-jira-update`'s own gate does not
   exist then,
7. `mb-jira-update` finalization.

A push rejected as **non-fast-forward** means the base moved while the sequence
ran: repeat from step 1. **At most two failed rounds** — after the second, STOP
and report to the user instead of racing the base indefinitely.

The ticket branch left behind on `origin` is **not deleted** (deleting a branch
through a push stays forbidden) and it is not reported as a collision: the
document index keys by phase, so an integrated ticket's branch no longer counts
as active work.

### Abandon

Abandoning a work item is the other way it ends on a ticket branch, and it is
**published like any other outcome**. The sequence is the same whichever door it is
reached through — the `mb-abort` skill, or Discard in
`finishing-a-development-branch`:

1. move BOTH halves of the pair to `proposals/abandoned/`, unchanged, deleting
   nothing (Active Work Item, archival asymmetry),
2. reset `context.md` to IDLE (see the `context.md` Schema & Writers section),
3. **commit** that move and **push** it — the ticket branch is the actor's own, so
   the agent pushes it and announces the outgoing commits; a shared current branch
   is the user's command, as everywhere,
4. only where a branch is actually being left behind: detach
   (`git switch --detach <baseRef>` — git cannot delete the branch that is
   checked out, and a ticket workspace has no local base branch to return to) and
   delete the **local** branch. The remote branch is never deleted.

Step 3 is the step that is not obvious and therefore the one that gets skipped. An
abandon that is not published exists only in the workspace that performed it: on
`origin` the branch still carries the ACTIVE pin with the pair still in `active/`,
so `mb-doc-index` keeps reporting that slug and that ticket as active work — a
`KOLIZE AKTIVNÍ PRÁCE` no later session can clear, which means the ticket can never
be picked up again. The exemption granted to an integrated branch does not help
here: the index keys by phase, and `abandoned/` is not an active phase.

`mb-abort` performs steps 1–3 and deletes no branches; step 4 belongs to the
finishing Discard path, which is the caller that ends the branch as well as the work
item.

## Cross-Branch Visibility

Documents are never pushed into a shared branch to make them visible; they are
**pulled** — discovered on `origin` across branches by the `mb-doc-index` skill
(read-only). Rules:

- Discovery candidates are the union of the local working tree and the document
  index over `origin`.
- **Taking over a draft from a foreign branch** is a blob copy
  (`git show <ref>:<path> > <path>`), never a cherry-pick — an elaboration
  window closes with ONE commit carrying the ledger, the graph and all of the
  window's proposals, so a cherry-pick would drag in a foreign ledger. The
  taken-over design document records `**Převzato z:** <branch>@<sha>`.
- **A ticket branch is created with an EXPLICIT starting point, always:**
  `git switch -c <TICKET>-<kebab-slug> <baseRef>` after a `git fetch
  origin` — otherwise it cannot see already-merged planning. The **local** base
  branch is not used in a ticket workspace: if one exists it is neither updated
  nor merged, and `<baseRef>` is the only base that counts (`baseRef` per
  Repository Configuration).
  **Postcondition of creation:** `proposals/active/` is empty or absent and
  `context.md` is IDLE (state names, tested by the pin — see the `context.md`
  Schema & Writers section). If it is not, STOP, delete the branch and repeat — a
  fresh ticket branch must never inherit another work item's active state.
  **Invariant: the base never carries ACTIVE state**, so a branch started from it
  is clean by construction; an ACTIVE base means a work item was integrated
  without a harvest and is reported as such.
- **Resurrected queue:** after a takeover the original may still sit in `next/`
  on the source branch and reappear in the base when that branch merges. This is
  detected (`mb-doc-index`, `mb-epic-graph -Check`), not prevented; the cleanup
  is one `git rm` by whoever sees the finding.

## Architect Review Gate

An approved design may be reviewed by a **human architect** before planning
and implementation. The gate is mediated by the Jira ticket and implemented
by the `mb-architect-review` skill (modes: request / respond / resume). The
brainstorming overlay ALWAYS offers the gate after the user approves the spec
when a Jira ticket is linked (with a yes/no recommendation based on
non-triviality: new component or service, architecture/contract changes,
cross-project impact, DB migration, security impact). No ticket → no offer.

**State lives in the ticket branch.** All interaction over a ticket happens
on that ticket's branch; every handoff (request and respond) ends with the
state committed and pushed to origin per the Publication Contract (the ticket
branch is the actor's own branch, so the push is announced, not negotiated).
The design document, `context.md` (including the `Review:` line) and any
notes are thus available to both sides and to Bitbucket links. Recommended branch
naming: `<TICKET>-<kebab-slug>`, for example `UMS-3302-toast-reconcile`, derived
from the work-item slug by the Naming rule in the Active Work Item section. New
names are ASCII; existing branches carrying diacritics are NOT renamed — a rename
would break the request comment's authoritative branch name for no benefit.

**Push policy:** per the Publication Contract — the ticket branch is the actor's
own branch, so the handoff push is announced, not negotiated; shared branches are
never pushed by the agent. Steps are ordered so one handoff needs exactly **one**
push, and the order is what makes that true: the base merge (resolver side only)
comes FIRST and is not pushed on its own, the handoff state is committed after it,
and the single closing push publishes both commits together. That push satisfies
the publication rule for the merge commit as well — a base merge is never left
unpublished, it merely shares the push with the commit that follows it inside the
same handoff.

**Base merge is asymmetric: only the RESOLVER's side merges the base** (request
and resume). The architect in respond mode NEVER merges it. Branch sync's rule is
"divergence = STOP", and a base merge from both sides produces exactly that
divergence — the two sides would create different merge commits over the same
base and the next sync would stop. The resolver's base merge belongs **before**
the handoff push (Base Sync & Drift Detection).

**Branch sync** (first step of respond and resume): resolve the ticket branch
in this order — branch name from the request comment (authoritative) → remote
branches whose name contains the ticket code (`git ls-remote --heads origin`,
case-insensitive) → ask the user; multiple ambiguous candidates always ask.
Require a clean working tree (dirty = STOP, no auto-stash). Then
`git fetch origin`, checkout the ticket branch and fast-forward to origin;
a diverged local branch = STOP and report. Only after branch sync read
`context.md` and the design document — both live on the ticket branch.

**Jira conventions:**

- Status flow: request transitions the ticket to **"Design Review"**; the
  architect's respond leaves the status unchanged; resume transitions to
  **"In Progress"**. Missing "Design Review" transition = fail-closed STOP
  with an instruction to create the status (prerequisite).
- **Flag** (`Flagged` field, value Impediment): set by respond when returning
  the ticket, cleared by resume (and by mb-jira-update finalization if still
  present). Team convention: a flag means "work returned to you — attend to
  it" (same as a tester returning a bug).
- **AgentSessions** (customfield_11248, Paragraph): request APPENDS one line
  `YYYY-MM-DD <harness> <session-id> — design review request (<ticket>)`.
  Session id is best-effort per harness; if undetectable, write the line
  without an id and tell the user. If the field is unavailable, put the same
  line into the request comment instead.
- The request comment records the **original resolver** (accountId +
  displayName) and the **ticket branch name** — respond needs both.

**Fail-closed rules:**

- While `context.md` carries the `Review:` line, continuing the workflow
  (writing-plans and beyond) is blocked; the correct continuation is
  `mb-architect-review` resume.
- Discard/abort paths (`mb-abort`, finishing Discard) with a ticket sitting
  in "Design Review" MUST offer Jira cleanup: transition back, restore
  assignee, clear the flag.
- Respond without a request comment (architect assigned manually): ask the
  user for the return assignee and branch; never guess.
- Resume without the flag (architect answered manually in Jira): warn and
  continue only after user confirmation.

## Dispatch Model Policy

Model selection is owned by the superpowers workflow. SDD's **Model
Selection** section scales the model to each task's size, complexity and risk
(cheap for mechanical work, a standard tier for integration/judgment, the most
capable model for design and the final whole-branch review, one tier up for a
stuck fix round). UMS does **not** pin models per role and carries no
`## Model Routing` block.

UMS adds one guard so routine bookkeeping never runs on an expensive model by
accident: a dispatch whose entire job is **summarization or read-only
inspection** — commit messages, Jira comments, harvest notes, read-only scans,
reality-verification passes — SHOULD request the cheapest capable tier.
Everything else follows the skill's own Model Selection.

Always specify the model explicitly when dispatching a subagent. An omitted
model inherits the session's model (often the most capable and most
expensive), which silently defeats both the superpowers tiering and this
guard.

This policy is additive: it never overrides a more specific per-skill
instruction that already names an exact model or session-isolation
requirement. Sessions outside any Memory Bank workflow are unaffected.

## Language Contract

- AI-facing instruction text (skill bodies, dispatch prompts, task briefs,
  implementer/reviewer reports, the `.superpowers/sdd/` ledger, orchestration
  metadata) MUST be in English.
- `playbook-candidates/<slug>.md` is AI-facing scratch and is therefore English;
  `playbook.md` is a persistent artifact and is therefore Czech. The harvest
  gate translates on persistence.
- User-facing output and persistent artifacts MUST be in Czech: the proposal
  pair content, Memory Bank documents, commit messages, Jira comments, review
  findings rendered to the user, and status summaries.
- Communication with the user in this repository is in Czech.
- AI-facing boilerplate inside the plan file (the "For agentic workers"
  header, `Interfaces:` labels, checkbox syntax) stays English; the task
  content around it is Czech.
- **Developer tooling is English.** The layer's own PowerShell tooling —
  `install-git-hooks.ps1`, `sync-with-monorepo.ps1`,
  `revendor-superpowers.ps1` and their console output — is written and speaks
  English, matching the code around it; only what an agent or a user meets
  during Memory Bank WORK is Czech (the `pre-push` and `guard-git-push.mjs`
  rejection messages, the `mb-*` skills' reports, `doc-index.ps1` /
  `epic-graph.ps1` tables and findings). This is a named exception, not a
  mixed-language rule surface: the boundary is the artifact, and each
  artifact is wholly one language.
- If language rules conflict across workflow surfaces, Czech requirements for
  user-facing/persistent text take precedence.

## Worktree Policy

**Default: total ban.** Git worktrees must not be used in this monorepo — the
repository is extremely large and worktree creation is expensive (time and
disk). Enforced by: `permissions.deny` on `EnterWorktree`/`ExitWorktree`,
`skillOverrides: using-git-worktrees: off`, and the CLAUDE.md ban. The
superpowers isolation step resolves to **branch-in-place**: create a feature
branch in the existing working directory (never work on main/master without
explicit user consent).

The ban rests on a measurement, not on an impression: a clone of the monorepo
occupies 25 GB, of which `.git` is 4.1 GB, so a linked worktree — which shares
only `.git` — saves 16 %. That is not enough to pay for the extra tree, its
build output and its hook installation. Isolation is achieved instead by the user
choosing a workspace (Workspace Discipline).

## Fail-Closed Behavior

When anything important is missing or ambiguous:

- Stop instead of guessing. Do not silently downgrade to another root,
  repository, or artifact location.
- Hard failures: missing git; missing root `memory-bank/`; undefined
  `PLAN_MB` at spec-write time; ambiguous target MB; a second active proposal
  slug **on the current branch that is not recoverable from `origin`** (the limit
  is per branch and a parked slug is normal operation — see Active Work Item);
  mixed-language rule surfaces; an unreachable pinned commit at
  publication time; the same slug or ticket active on a foreign branch; a base
  sync that cannot be performed at a phase boundary (divergence or a dirty tree);
  the ceiling of two integration rounds; a missing or unverified `pre-push` hook
  in the workspace; a failing `git fetch origin` in phase 0 of the entry gate.
- NOT failures (explicitly legal): writing source code outside
  `memory-bank/`; the `.superpowers/` scratch tree; plan checkboxes; the
  `.superpowers/sdd/<plan-basename>/progress.md` ledger; an absolute
  `core.hooksPath` (a scope warning, not a bypass — the hook check resolves
  through it, see Workspace Discipline); a parked active work item on another
  branch; an untracked playbook-candidate file of another slug.

## Resolution Protocol

This file is shared across multiple skills in the following directory
structure:

```
<skills_root>/
├── shared/
│   ├── UMS_MEMORY_BANK_CONTRACT.md   ← this file
│   ├── SKILLS_MANIFEST.md
│   ├── VENDORED_FROM.md
│   └── overlays/
├── <skill-1>/
│   └── SKILL.md
└── ...
```

When referencing this file from `SKILL.md`:

1. **Primary path:** resolve `../shared/UMS_MEMORY_BANK_CONTRACT.md` relative
   to the skill file directory.
2. **Fallback:** `<skills_root>/shared/UMS_MEMORY_BANK_CONTRACT.md`.
3. **DO NOT use recursive filesystem search.** If both paths fail, stop with:
   `UMS_MEMORY_BANK_CONTRACT.md not found at <skills_root>/shared/.`

Skills and docs that reference this contract must use relative links from
their own directory.

## Versioning & Vendoring

- The vendored superpowers upstream version is pinned in
  `shared/VENDORED_FROM.md` (tag, commit, skill list).
- UMS modifications to vendored skills exist ONLY as marked
  `<!-- UMS-OVERLAY BEGIN/END -->` blocks, generated from
  `shared/overlays/*.overlay.md` by `.claude/scripts/revendor-superpowers.ps1`.
  Never edit vendored files by hand outside those blocks.
- Upgrading upstream: re-run the vendoring script per the procedure in
  `VENDORED_FROM.md`; an overlay anchor miss is the upstream-drift detector.
