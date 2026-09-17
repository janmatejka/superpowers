# UMS Memory Bank Contract


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
  `playbook-candidates/<slug>.md`, `session-intent.md`) — git-ignored,
  ephemeral, owned by the superpowers execution skills and the Playbook
  Contract. One named exception to the git-ignored rule: `mb-park` commits the
  CURRENT slug's candidate file to the ticket branch, so parking loses no
  evidence (see Playbook Contract).
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

Doklad: contract/doklad/link-conventions.md, "Why no #fragment anchors"

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
  (`**Spec:** [design_<slug>.md](design_<slug>.md)`), never the reverse. Where
  a document must mention the plan, name it as plain text — the pair is found
  by slug, not by link.
- Enforced and consolidated by the `mb-link-audit` skill (read-only audit,
  `-Apply` for the mechanically determinable classes).

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

## Active Work Item (Design + Plan Pair)

One active work item per **branch** = one **design + plan pair** in
`<PLAN_MB>/proposals/active/`. The limit is per branch because every branch
carries its own pin in its own `context.md`; a parked work item on another branch
therefore does not block starting a new one (see Workspace Discipline).

- **`design_<slug>.md`** — the spec, written by `brainstorming`
  (intent source of truth).
- **`plan_<slug>.md`** — the implementation plan, written by
  `writing-plans` (execution source of truth). A conflict between the halves
  is resolved **by its subject**: **what** should be built is the design's to
  decide — it is the binding authority the upstream ruling model measures
  against, and the artifact that survives in `completed/`; **how** and in
  what order is the plan's — it was written against the code, the design was
  not. Either way the discrepancy is recorded as a ruling and surfaced to the
  user, never silently absorbed.

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
- **Báze:** origin/Branches/5.37
- **Started:** YYYY-MM-DD
- **Review:** design-review requested YYYY-MM-DD
```

The `Báze:` line is OPTIONAL — present only when the work item integrates
somewhere other than `baseRef` (see Repository Configuration, the effective base).
Readers MUST tolerate its absence; that is the normal state.

**The pin write DECIDES this line; it never merely adds it.** The pin write of the
entry gate (Workspace Discipline, phase 4) writes the line when the chosen base
differs from `baseRef` and **DELETES any line already in the file** when it does
not — unconditionally, exactly as it rewrites `Jira:`, and for the same reason.

Doklad: contract/doklad/core.md, "Why the pin write decides the Báze line"

The `Review:` line is OPTIONAL — present only between an architect-review
request and its resume (see Architect Review Gate). While present, the
superpowers workflow MUST NOT continue past brainstorming (no writing-plans);
the correct continuation is `mb-architect-review` (resume).

IDLE state: replace the `## Active Work` items with
`(No active work - IDLE phase)`. The `- **Jira:** …` line of the last work item
is **NOT** kept; the `- **Báze:** …` line **is**. `Báze:` stays because the
harvest resets `context.md` in its own `context.md` reset step, but the
INTEGRATION that follows still needs `<baseBranch>`: dropping the line there
would silently send the integration command at the default base — the one branch
the work was deliberately not targeting.

Doklad: contract/doklad/core.md, "Why the IDLE reset drops Jira"

Doklad: contract/doklad/core.md, "Note for whoever changes the IDLE reset"

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

Doklad: contract/doklad/core.md, "Document Ownership, the third case"

**Moving a fact is a legal operation.** `mb-harvest` and `mb-sync` may move a
fact between documents of the same MB. The order is binding: **write into the
target first, only then delete from the source.** Every move is named in the
skill's report, so it is visible both there and in the commit diff. This is
deliberately visibility, not a mechanical check — a move is a local edit
someone reads at commit time.

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
on a ticket branch — a commit that is not pushed exists only in the local
`.git`, never on `origin`; a pool slot shares that `.git` with every other
slot, so the commit is visible from any of them, but it is still absent from
`origin` until pushed. The points below remain listed as its notable special
cases, not as the whole rule:

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

Publishing its own branch is not a decision the agent puts to the user, so it
does not negotiate WHETHER to publish — but the harness's own permission prompt
still applies (`Bash(git push:*)` is deliberately in neither `allow` nor `deny`
in this layer's `settings.json`, so the tool call is confirmed like any other):
"does not ask" is not "the push is auto-approved".

The effective list of protected branches is `protectedBranches` (see Repository
Configuration; the built-in fallback is `develop`, `main`, `master`,
`release/*`). Both layers below resolve protection from it, by different
routes: the hook through the plain-text list the installer generates,
`guard-git-push.mjs` by reading `ums-repo.json` itself.

**Two enforcement questions, two layers:**

| Layer | Question | Reach |
|---|---|---|
| The git `pre-push` hook | **What** is pushed | Anything running in an agent session, including commands the user types with a leading `!` |
| `guard-git-push.mjs` (PreToolUse) | **Who** pushes | The agent's own tool calls only; commands the user types with `!` never reach it |

The hook enforces NOTHING outside an agent session (marker `MB_AGENT_SESSION`;
`AI_AGENT` / `CLAUDECODE` are a Claude-Code-only fallback), so a human pushing
from a terminal or an IDE is untouched. Inside an agent session it allows, on a
protected branch, only a **fast-forward push whose tip is already reachable on
the remote being pushed to** — a pointer move onto commits that remote already
has. What it still does for everyone, marker or not: it fails CLOSED when it
cannot buffer git's ref list into a temp file, because a plumbing failure there
would otherwise make every check below it pass silently; and it runs the
chained foreign hook and exits with ITS result, so a chained hook can reject a
push here even where this one enforces nothing of its own.

Doklad: contract/doklad/publication.md, "Auditability, not review"

Doklad: contract/doklad/publication.md, "What the reachability claim proves"

**Two bans hold on every branch the hook polices** — its scope is
`refs/heads/*` — not only on protected ones: deleting a branch through a push,
and a non-fast-forward (force) push. Inside an agent session the hook rejects
both; the human escape below lifts them along with the rest of the guard, and
the two accepted bypasses named further down evade them as they evade
everything else in this hook.

**A freshly created ticket branch is DETACHED from its inherited upstream, and
its first publication is `git push -u origin <branch>` — never a bare
`git push`.** `git switch -c <branch> <chosen base>` sets the new branch's
upstream to the BASE, so until that upstream is rewritten the branch is
pointed at a (typically protected) destination it must never publish to. What
stops a bare push in that state is git's own `push.default=simple` refusing the
name mismatch, plus `pre-push` — **not** the `PreToolUse` guard, which on a
bare push resolves the target as the CURRENT BRANCH NAME and allows it ("The
epic line", where that mechanism is written once). Relying on the guard here
would be relying on the wrong file. Two steps, and both belong at
the source rather than in any one caller's prose: immediately after the
`switch -c`, run `git branch --unset-upstream`, so no accident in between can
aim at the base; and publish the first time with `-u`, which sets the upstream
to the branch itself. When inspecting a workspace, a ticket branch whose
upstream is a protected branch is a finding, not a normal state.

The actual guarantee is the git `pre-push` hook (`.claude/hooks/pre-push`,
scoped to `refs/heads/*` — none of the checks below look at a tag push, though
the fail-closed buffer arm above them rejects the whole push, tags included,
whenever it fires), installed into each workspace by
`install-git-hooks.ps1` — hooks do
not travel with a clone, which is why the entry gate verifies them (Workspace
Discipline). Verify it
non-destructively — never with a real `git push origin develop`, which
either publishes real commits if the hook turns out to be inert (this is
exactly how a linked-worktree installation gap was first confirmed) or
prints a misleading "Everything up-to-date" when there is nothing to push:
resolve the installed path with `git rev-parse --git-path hooks/pre-push`,
confirm it exists and carries the marker
`UMS pre-push guard (Publication Contract)` within its first five lines with
a version no lower than the layer's own source header
(`ums/.claude/hooks/pre-push`, line 2), then pipe a synthetic line straight
into it (`printf 'refs/heads/develop
<sha> refs/heads/develop <sha>\n' | MB_AGENT_SESSION=1 <hook path> origin
verify`), expecting a non-zero exit and the `UMS:` message, AND the
mirror-image accept case (a synthetic ticket-branch creation must exit 0,
silently) — without that second half a hook that cannot execute at all also
"rejects" everything and passes as verified. **The marker on that pipe is
load-bearing**: outside an agent session the hook deliberately enforces
nothing, so an unmarked pipe proves only that the gate works.

Doklad: contract/doklad/publication.md, "How the installer recognizes its own hook"

**The hook is plain git; the marker is not.** The guarantee therefore reaches a
harness only once `MB_AGENT_SESSION` is in the environment the push runs in,
and `sync-with-monorepo.ps1` writes it into each harness's own documented
mechanism: Claude Code through the `env` block of this layer's `settings.json`,
Codex through `config.toml` `[shell_environment_policy].set`, Gemini through a
`.env` file in its config directory. For **Kilo Code no documented mechanism to
inject an environment variable was found**, so there the marker never arrives,
the gate never opens, and the hook enforces nothing of its own — on that
harness the publication guarantee rests on contract text alone. The entry
gate's check is what surfaces this per session: a synthetic protected-branch
line that PASSES is exactly this state, and is reported as a missing
guarantee.

**The human escape: `MB_HUMAN_PUSH=1`.** It means "a human takes
responsibility for THIS push" and lifts the whole guard — the protected-branch
rule, the deletion ban and the force-push ban alike. The wide scope is
deliberate: once the hook enforces only inside an agent session, a human
rebasing their OWN ticket branch in-session carries the marker too, and a
narrow escape would leave them nothing but disabling hooks entirely. The
mechanical containment against an agent abusing it lives in the PreToolUse
layer, which DENIES any push carrying the variable — only the agent's own tool
calls reach that layer, and the agent must never set it. `UMS_ALLOW_SHARED_PUSH`
is accepted during the transition and answered with a deprecation line.

Doklad: contract/doklad/publication.md, "Which rejections name the escape"

**Two spellings, deliberately different.** The command handed to the user for
an integration is the PLAIN `! git push origin HEAD:<baseBranch>` — the refspec
form, because integration pushes the ticket branch onto the base ref, and no
escape, because a fast-forward onto commits the tracking refs already carry is
exactly what the content rule lets through; prefixing the escape there would
teach the user to lift the whole guard for a push that needs nothing lifted.
That is the spelling `guard-git-push.mjs` hands over when it denies the agent's
own push to a protected branch. The escape appears in the OTHER spelling,
`! MB_HUMAN_PUSH=1 git push <remote> HEAD:<branch>`, which the `pre-push` hook's
rejection message hands over — that message fires only where the content rule
cannot apply, and it is the only rejection that hands the escape over at all.
Do not collapse the two into one.

Two known, accepted bypasses — both require deliberate,
visible intent, unlike the CLI-spelling tricks this hook exists to close:
`git push --no-verify` skips it entirely, and a one-shot
`git -c core.hooksPath=<other> push` points git at a hooks directory this layer
never installed into. `--no-verify` is a BYPASS
of the guarantee, never the documented way to publish `develop`: it disables
every hook in the repository, so it is exactly as unsafe as it looks, and
`guard-git-push.mjs` denies it on sight (escape or no escape).

Doklad: contract/doklad/publication.md, "A configured core.hooksPath is not a bypass"

A **foreign `pre-push`** already in the hooks directory is not a reason to
leave the workspace unguarded: the installer moves it aside to `pre-push.ums-chained`,
sets its executable bit and this hook then runs it with the same ref list, so
installing the layer cannot silently turn someone's LFS or lint hook off (a
chained hook without that bit is skipped without a word, which is why the
installer sets it and warns loudly when it cannot — both that `chmod` and that
warning need a POSIX shell, so where none is found the bit is left unset and
nothing says so). It REFUSES to chain where it cannot make the move safe: a
hooks directory shared with other repositories through `core.hooksPath`, a
`.ums-chained` file already sitting there, a hand-merged hook carrying our
marker deep in its body rather than in its header, and a move that simply fails
(a locked or read-only file). **A refusal is not a fallback:** our hook is then
not installed in that workspace at all, the run exits 2, and the publication
guarantee is absent there until someone resolves the foreign hook by hand.

Doklad: contract/doklad/publication.md, "The PreToolUse guard, what it reads and what it misses"

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
- `Ruling:` lines in the `.superpowers/sdd/` ledger are AI-facing and
  therefore English; the final "Rulings I made" list is user-facing and
  therefore Czech — the same translate-on-presentation split as playbook
  candidates.
- User-facing output and persistent artifacts MUST be in Czech: the proposal
  pair content, Memory Bank documents, commit messages, Jira comments, review
  findings rendered to the user, and status summaries.
- Communication with the user in this repository is in Czech.
- AI-facing boilerplate inside the plan file (the "For agentic workers"
  header, `Interfaces:` labels, checkbox syntax) stays English; the task
  content around it is Czech.
- **Developer tooling is English.** The layer's own PowerShell tooling —
  `install-git-hooks.ps1`, `sync-with-monorepo.ps1`,
  `revendor-superpowers.ps1`, `pool-status.ps1`, `pool-launch.ps1`,
  `pool-provision.ps1` and their console output — is written and speaks
  English, matching the code around it; only what an agent or a user meets
  during Memory Bank WORK is Czech (the `pre-push` and `guard-git-push.mjs`
  rejection messages, the `mb-*` skills' reports — `mb-epic-run` included —
  `doc-index.ps1` / `epic-graph.ps1` tables and findings). This is a named
  exception, not a mixed-language rule surface: the boundary is the artifact,
  and each artifact is wholly one language.
- **A hook whose entire output is model context is English**, even though the
  hooks named above appear on the Czech side for their REJECTION MESSAGES. The
  criterion is the audience of the output, not the file's kind: a rejection a
  human reads is Czech, an `additionalContext` payload a model reads is English.
- If language rules conflict across workflow surfaces, Czech requirements for
  user-facing/persistent text take precedence.

## Worktree Policy

**Default: total ban.** Git worktrees must not be created by an agent in this
monorepo. Enforced by: `permissions.deny` on `EnterWorktree`/`ExitWorktree`
and `Bash(git worktree:*)`/`PowerShell(git worktree:*)`,
`skillOverrides: using-git-worktrees: off`, and the CLAUDE.md ban. The
superpowers isolation step resolves to **branch-in-place**: create a feature
branch in the existing working directory (never work on main/master without
explicit user consent).
## Message Protocol

Doklad: contract/doklad/message-protocol.md, "Why a message carries a mark"

**Every message from an orchestrator to a session or subagent it coordinates —
an epic's manager to a ticket session, a plan's orchestrator to an implementer
— carries exactly ONE mark, and the mark is the mechanism.** It is written as
the first line of the message. The other direction carries no mark: authority
runs one way, and a report, a correction or a handoff artifact travelling back
up carries none of it.

- **`Mark: instruction`** — the message states a BOUNDARY: what the recipient
  may or may not do, where its work ends, which branch, base or artifact it
  works with, which of two things goes first, when it stops. The sender owns
  that boundary, or a written rule does, and the recipient can check it against
  whichever of the two is claimed. A fact of the sender's OWN action, verifiable
  by the recipient in a shared artifact — the fast-forward landed, at this SHA,
  onto this branch — is an instruction too: the marking is BINARY and total, and
  a message must never go out unmarked for want of a third mark.
- **`Mark: conjecture`** — the message states a CAUSE or a prediction: why
  something is happening, what a symptom means, what the recipient is about to
  find, what would fix it. Nothing but the recipient's own measurement settles
  it.

The mark is written in English like every other AI-facing text and rendered to
the user as *pokyn* and *domněnka* — the same translate-on-presentation split
as `Ruling:` lines and the `NOW` block's state class (Language Contract).
Three consequences, and they are why the mark exists at all:

- **The recipient MAY refuse a conjecture, and refusing is NORMAL behaviour,
  not friction.** It needs no permission and no round trip: name the conjecture
  being refused, say what was measured instead, and carry on. This direction of
  traffic is where the measured value sits — six agent → orchestrator
  corrections in one day, every one of them substantive.
- **A conjecture is NEVER written into the ledger as fact.** Either it is not
  written at all, or it is written attributed and unverified ("the manager
  believes X; unmeasured"). Once the recipient has measured it, what the ledger
  records is the MEASUREMENT — never the message that predicted it.
- **The recipient MUST refuse an instruction that contradicts a written
  rule** — a rule of this contract, of the plan it is executing, or of the
  skill it is running. It names the rule, states what it refused, does not
  comply, and continues. The duty ends at the refusal: refusing and naming the
  rule is the whole of it.
## Escalation & Autonomy

**"When to stop" and "how much to stop" are not quantities anyone turns —
they are rules**, and they have an operational form. Two of them, and they
bind every session in this layer, epic work or not:

> **Ending a turn is legitimate only where you are waiting for a human's
> answer, a manager's answer, or a subagent to finish — and that waiting must
> be NAMED**: by the `NOW` block's state class where the block exists, and in
> the report everywhere else. What cannot be named is not a reason to end a
> turn.

> **When you formulate a question, name what does NOT depend on the answer —
> and do that part immediately**, in the same turn as the question.
**The floor — always a human, and no autonomy level moves it off one**

| Kind | Measured example |
|---|---|
| Publication into the delivery line | the exit of an epic |
| An irreversible or destructive operation | deleting a branch, a force push, rewriting history |
| A security-sensitive action | accesses, secrets |
| Choosing a base that is not a protected branch | today's fail-closed STOP |
| A change to `epicBranchPattern` or `protectedBranches` | widening a privilege |
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
  the ceiling of two integration rounds; a `pre-push` hook that is missing,
  older than the layer's own source header, or fails EITHER half of the
  synthetic-pipe check run in this session's own environment — the
  protected-branch line it must reject and the
  ticket-branch line it must accept (Workspace Discipline); a failing
  `git fetch origin` in phase 0 of the entry gate; a missing declared
  verification set at a work item's first integration (Publication Contract,
  "Integration", the Handoff gate) — its umbrella (an epic's ledger, or the
  work item's own plan otherwise) naming no set at all is a STOP, not a silent
  pass.
- NOT failures (explicitly legal): writing source code outside
  `memory-bank/`; the `.superpowers/` scratch tree; plan checkboxes; the
  `.superpowers/sdd/<plan-basename>/progress.md` ledger; an absolute
  `core.hooksPath` (a scope warning, not a bypass — the hook check resolves
  through it, see Workspace Discipline); a parked active work item on another
  branch; an untracked playbook-candidate file of another slug.

**Rulings and these STOPs.** Upstream subagent-driven-development (v6.3.0)
rules on conflicts instead of stalling, and stops only for four named
classes. The fail-closed STOPs of this layer are not a fifth class — they
FALL WITHIN those four: a push to a shared branch and the integration push
are "a side effect outside this clone that norms say you ask about first";
an active-work collision, an unprotected base and an unreachable pinned
commit are irreversible in the same sense — duplicated work, or a reference
nobody can resolve, cannot be taken back; a plan too broken to follow is
upstream's fourth class verbatim. One thing is deliberately NOT such a side
effect: **merging the effective base into the agent's OWN ticket branch.**
It is mandatory at phase boundaries (Base Sync & Drift Detection) and is
never put to the user — reading upstream's word "merge" as covering it
would turn the mandatory base sync before the first dispatch into a
question.

Doklad: contract/doklad/escalation.md, "Context rotation as a fifth class"

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
