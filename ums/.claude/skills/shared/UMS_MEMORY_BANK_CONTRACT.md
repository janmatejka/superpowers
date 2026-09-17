# UMS Memory Bank Contract

- **Contract-Version:** 2.19

## Purpose & Roles

Superpowers skills are the **driving workflow** (`brainstorming → writing-plans →
subagent-driven-development / executing-plans → finishing-a-development-branch`);
the Memory Bank (MB) is the **document and knowledge layer** injected into it.
This contract defines where superpowers artifacts live in the MB tree, how the
target MB is selected and pinned, what `context.md` contains, and how knowledge is
harvested when a branch finishes. Its consumers are the 17 live `mb-*` utility
skills (plus the deprecated `mb-act` / `mb-plan` stubs), the four
`<!-- UMS-OVERLAY -->` overlays over vendored skills (`brainstorming`,
`writing-plans`, `subagent-driven-development`, `finishing-a-development-branch`),
this layer's hooks (`pre-push`, `guard-git-push.mjs`, `deny-superpowers-docs.mjs`,
`session-intent.ps1`), and any other agent working with Memory Bank documents.

## Three-Tier Directory Model

- **`CTX_DIR`** = `<MB_ROOT>/memory-bank/` — the repository's orchestration root.
  Holds `context.md` (Jira link, `Target MB Pin`, `Work item` slug, `Started`).
- **`PLAN_MB`** = `<MB_ROOT>/<Target MB Pin>`, the pin coming from
  `CTX_DIR/context.md` — the project Memory Bank the current work targets. Holds
  the active design + plan pair and the project documents (`brief.md`,
  `architecture.md`, `tech.md`, optionally `playbook.md` — see Memory Bank
  Document Set). If `Target MB Pin` is not set, `PLAN_MB` is undefined and
  operations requiring it MUST fail with an error (or trigger Target-MB Discovery
  where this contract says so).
- **`AFFECTED_MBS`** — the project Memory Banks touched by a harvest, derived at
  harvest time from the branch diff (see Harvest Contract), never hand-maintained
  in `context.md`.

## `MB_ROOT` Discovery

When a skill or helper needs `MB_ROOT`, use exactly one discovery step —
`git rev-parse --show-toplevel` — and no workspace scans, directory walks or
fallback anchors. If `git` is missing or the command exits non-zero, stop
immediately with `Git repository not found. Memory Bank requires git.` On
success, `MB_ROOT` is the returned git root and `CTX_DIR` is
`<MB_ROOT>/memory-bank/`.

## Root Memory Bank Gate

Before reading or writing any Memory Bank file, verify that
`<MB_ROOT>/memory-bank/` — the orchestration root for the repo — exists. If it
does not, stop with: `` `memory-bank/` does not exist. Run `mb-init`. ``

`mb-init` creates the standard structure in two modes:

- **Orchestration root (`CTX_DIR`)** — `<MB_ROOT>/memory-bank/` with proposal
  folders and `ums-repo.json` (see Repository Configuration), `context.md` left
  absent; it is not bound by the mandatory core (Memory Bank Document Set). The
  next step is the superpowers workflow — Target-MB Discovery & Pinning
  (`contract/target-mb-discovery.md`) creates `context.md` during brainstorming.
- **Project MB (`PLAN_MB`)** — `<MB_ROOT>/<path>/memory-bank/` with
  `proposals/{next,active,completed,abandoned}/` and project docs, for new
  components. Does not touch `CTX_DIR`.

## Memory Bank Document Set

**Mandatory core of a project MB:** `brief.md`, `architecture.md`, `tech.md`.
**First-class optional:** `playbook.md` — prescriptive procedures (Document
Ownership below; Playbook Contract in `contract/playbook-contract.md`).
**Free extension:** any further document the MB needs (`data-flows.md`,
`use-cases.md`, `open-questions.md`, `tasks.md`, …) — no normative status; skills
update them when they exist and never create them speculatively. The
orchestration root (`CTX_DIR`) is NOT bound by the core: it holds `context.md`
plus whatever navigation the orchestrated tree needs.

`brief.md` covers the whole of what the product is and what state it is in; a
separate `product.md` is legacy shape only. Canonical section order (sections
without content are omitted, never created empty):

```markdown
# Brief — <name>

## Co to je
## Klíčové funkce            (or Rozsah, depending on the component)
## Pro koho a hodnota
## Rizika
## Stav a historie
```

### Legacy shape tolerance

Permanent, like the `proposal_` grandfather clause; no MB is forced to migrate.
**Read** `product.md` when it exists, and `tasks.md` in place of an absent
`playbook.md`. **Write procedures** into `playbook.md`, else into an existing
`tasks.md`, else create `playbook.md`; where `tasks.md` serves as the procedure
document, the Playbook Contract's consult-before-write regime binds it in that
role — the protection follows the content, not the filename. Migration to the
current shape is `mb-migrate-docs`' job, never a side effect of unrelated work.

## Scope Lock (Memory Bank documents only)

The scope lock governs **Memory Bank document writes only**: MB documents are
written only under `CTX_DIR`, `PLAN_MB`, and — during harvest — `AFFECTED_MBS`;
superpowers spec/plan documents only under `<PLAN_MB>/proposals/` (see
Superpowers Document Placement).

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

Do not hardcode machine-specific or repository-root absolute paths.

## Link Conventions

- **Relative to the containing file, always** — never to the Memory Bank root,
  the project root or the repository root.
- **No `#fragment` anchors.** Name the section in words instead:

  | Instead of | Write |
  |---|---|
  | `[X](architecture.md#kritické-detaily)` | `[architecture.md](architecture.md), sekce „Kritické detaily“` |
  | `[X](#mimo-rozsah)` (same file) | `sekce „Mimo rozsah“` |
  | `[X](KicSetup.iss#L253-L254)` | `[KicSetup.iss](KicSetup.iss), řádky 253–254` |

  A heading is therefore **never reworded merely to make a slug come out a
  particular way**.

  Doklad: contract/doklad/link-conventions.md, "Why no #fragment anchors"

- **A link whose target cannot be determined is not left dangling.** Drop the
  link syntax, keep the text, and mark it with the dead path inside the marker:
  `` `TestBase.cs` [ODKAZ K OVĚŘENÍ: ../TestBase.cs] `` — greppable, and it
  carries enough to act on later.
- **Never repoint a link across projects to make it resolve.** A path that
  pointed inside the document's own project and is not there was dropped from
  that project; aiming the sentence at a same-named file elsewhere changes what
  it claims. Mark it and let a human decide.
- **Never link the plan half.** No document links `plan_<slug>.md` — the plan is
  **deleted at harvest** (Archival asymmetry), so the link dies the moment the
  work completes, inside the immutable `proposals/completed/`. Cross-references
  run one way only: the plan links the design
  (`**Spec:** [design_<slug>.md](design_<slug>.md)`), never the reverse; where a
  document must mention the plan, name it as plain text.
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

Sequence at a boundary: `fetch` → `merge <baseRef>` → intersection assessment →
verification where it applies → push. There is no separate commit step, and the
merge is **not** deferred with `--no-commit` until verification passes:
verification runs on the merged tree, and a red result is reported, not un-merged
(see the STOP rule below). **Only the push waits**, and only to the end of the
phase boundary, so that a handoff publishes the merge and the handoff commit in
one push (Architect Review Gate).

**Intersection assessment.** Both sets are computed **after `fetch` and before
`merge`**, from the same merge-base:

```bash
MB=$(git merge-base HEAD <baseRef>)
prichozi=$(git diff --name-only $MB..<baseRef>)
vlastni=$(git diff --name-only  $MB..HEAD)
```

In the design phase the **own** set is the target areas named in the design
document — there is no code diff of one's own yet.

**Mechanics without ecosystem knowledge.** Each path maps to the **nearest
ancestor directory containing a match for `projectMarkers`** (a path with no such
ancestor stays itself) and the intersection is sought over those owners; a path
matching any entry of `sharedRoots` is **always intersecting**. **A `sharedRoots`
entry ending in `/` is a path PREFIX**, everything under it at any depth, **and
any other entry is a GLOB** against the whole path; both spellings are required
and neither substitutes for the other. This is a **heuristic, not proof**: it
decides whether verification is offered, never whether the work is correct.

**Graduated verification:** no intersection → no verification, and a single-line
statement of the fact is the whole report; intersection → the agent lists the
intersecting paths and **offers** a baseline with a recommendation, the user
decides. A merge conflict counts as an intersection automatically. In the design
and design-review phases nothing is built, so it is purely an offer. Before
dispatching the first task a baseline is mandatory. **STOP applies only where
verification actually ran and came back red** — someone else's breakage of the
base is not repaired inside a ticket branch; report it and let the user decide.

**Conflict handling.** The agent resolves merge conflicts only in files it changed
on this branch itself; anything else is a STOP. A `context.md` conflict is always
resolved by keeping the ticket branch's version, targeted —
`git checkout --ours memory-bank/context.md`, **never `merge -X ours` over the
whole merge**, which would silently drop incoming content everywhere else —
because `context.md` is the state of THIS branch, not a fact about the product. A
conflict on the SAME slug in `proposals/active/` is two actors colliding over one
work item, therefore a STOP.

## Active Work Item (Design + Plan Pair)

One active work item per **branch** = one **design + plan pair** in
`<PLAN_MB>/proposals/active/`. The limit is per branch because every branch
carries its own pin in its own `context.md`; a parked work item on another branch
therefore does not block starting a new one (see Workspace Discipline).

**`design_<slug>.md`** is the spec, written by `brainstorming` (intent source of
truth); **`plan_<slug>.md`** is the implementation plan, written by
`writing-plans` (execution source of truth). A conflict between the halves is
resolved **by its subject**: **what** should be built is the design's to decide —
the binding authority, and the artifact that survives in `completed/`; **how** and
in what order is the plan's, written against the code. Either way the discrepancy
is recorded as a ruling and surfaced to the user, never silently absorbed.

Rules:

- The pair is created by the superpowers workflow and is never duplicated into
  `docs/` or any parallel location.
- Task progress lives in the plan file's checkboxes and in
  `.superpowers/sdd/<plan-basename>/progress.md` — **not** in `context.md`.
- **Archival asymmetry:** on **completion** (harvest → `completed/`) only the
  design half is retained and the plan half is **deleted**; a grandfathered
  single plan with no design half is archived to `completed/` instead of deleted.
  Because the plan does not survive, no document may link it (Link Conventions).
  On **abandon** (`mb-abort` / Discard → `abandoned/`) both halves move together,
  unchanged, nothing deleted. If a half is missing at archive time, warn and
  handle what exists.
- A design file without its plan sibling is a valid intermediate state (between
  brainstorming and writing-plans).
- An empty `proposals/active/` may be absent from the working tree (git does not
  track empty directories). Skills MUST tolerate that and recreate it on demand —
  a missing `active/` means "no active work", not a broken Memory Bank.

**Naming:** `design_<slug>.md` / `plan_<slug>.md`. The slug MUST start with the
ticket code whenever one is known — `<jira>_<short_snake_case_topic>`, ticket code
in lowercase snake case (`UMS-3302` → `ums_3302_toast_reconcile`) — and is
`<short_snake_case_topic>` alone without one. ASCII only, no diacritics, no dates.
When the ticket becomes known later, rename the slug's files to include it, within
the same naming style.

**Branch name derived from the slug.** The ticket branch is
`<TICKET>-<kebab-slug>`: replace `_` with `-` and upper-case the leading ticket
code (`ums_3302_toast_reconcile` → `UMS-3302-toast-reconcile`). The derivation
runs **one way only** and nothing parses a branch name back into a slug: a ticket
branch is recognized by the ticket code it contains (Architect Review Gate, branch
sync) and the slug is then read from `context.md` on that branch — which is why a
branch name carrying diacritics stays valid without renaming.

**Grandfather clause (legacy `proposal_` naming):** `proposal_<slug>-design.md`
(design half) and `proposal_<slug>.md` (plan half, or a v1 single plan) remain
valid wherever they rest. Never rename or convert them, with ONE exception:
activating a queued legacy draft from `next/` converts the work item to the new
style. One work item uses exactly one naming style; a mixed pair must never be
created. Never touch archived files in `proposals/completed/`.

**Discovery & pairing rule (all skills):** match `{design_,plan_,proposal_}*.md`;
strip exactly ONE prefix `^(design_|plan_|proposal_)` from the file stem, and
strip the `-design` suffix ONLY after the `proposal_` prefix; group by
`(owning MB root, slug)`. One pair (or grandfathered single file) = one candidate.
Thus `design_x.md` → slug `x`, while legacy `proposal_design_x.md` → slug
`design_x` — no mis-pairing.

**Preliminary work items (`next/`):** any number of design drafts may queue in
`<MB>/proposals/next/`. A draft is a single **`design_<slug>.md`** with
design-document structure (`## Cíl`, `## Scope`, `## Technický návrh`, scaled to
what is known); implementation plans are NOT written ahead. Creating or editing a
draft does NOT touch `context.md`, does not require the IDLE state and does not
pin a Target MB; queued items never count against the two-actives guard, and one
dropped without being started moves to `abandoned/` unrenamed. When work starts,
ALL files of the slug move from `next/` to `active/` (see Target-MB Discovery &
Pinning), a legacy `proposal_*` draft being renamed to `design_<slug>.md` in that
move — the only permitted legacy conversion; its content is the design seed
whatever its structure, and brainstorming refines it rather than starting over.

## Superpowers Document Placement

This implements the upstream escape hatch — brainstorming and writing-plans both
state *"(User preferences for spec/plan location override this default)"*. The
preference in this repository is:

| Superpowers artifact | Default upstream location | UMS location |
|---|---|---|
| Design/spec (brainstorming) | `docs/superpowers/specs/…-design.md` | `<PLAN_MB>/proposals/active/design_<slug>.md` |
| Implementation plan (writing-plans) | `docs/superpowers/plans/….md` | `<PLAN_MB>/proposals/active/plan_<slug>.md` |

Prohibited locations (mechanically enforced by a PreToolUse hook):
`docs/superpowers/specs/`, `docs/superpowers/plans/`, `docs/plans/`.

## `context.md` Schema & Writers

`<CTX_DIR>/context.md` is a small state file; the workflow itself lives in the
superpowers skills and the design + plan pair. Active state:

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
somewhere other than `baseRef` (Repository Configuration, the effective base);
readers MUST tolerate its absence, which is the normal state. **The pin write
DECIDES this line; it never merely adds it:** the entry gate's pin write
(Workspace Discipline, phase 4) writes it when the chosen base differs from
`baseRef` and **DELETES any line already in the file** when it does not —
unconditionally, exactly as it rewrites `Jira:`.

Doklad: contract/doklad/core.md, "Why the pin write decides the Báze line"

The `Review:` line is OPTIONAL — present only between an architect-review request
and its resume (see Architect Review Gate). While present, the superpowers
workflow MUST NOT continue past brainstorming (no writing-plans); the correct
continuation is `mb-architect-review` (resume).

IDLE state: replace the `## Active Work` items with
`(No active work - IDLE phase)`. The `- **Jira:** …` line of the last work item is
**NOT** kept; the `- **Báze:** …` line **is** — the integration that follows a
harvest still needs `<baseBranch>`, and dropping the line would silently aim the
integration command at the default base.

Doklad: contract/doklad/core.md, "Why the IDLE reset drops Jira"
Doklad: contract/doklad/core.md, "Note for whoever changes the IDLE reset"

**ACTIVE and IDLE are state NAMES, not tokens in the file.** The word `ACTIVE`
never appears in `context.md`, so no skill may grep for it. The mechanical test is
whether the `## Active Work` block **carries a pin**: a `Target MB Pin` together
with a `Work item` slug is ACTIVE; the `(No active work - IDLE phase)` marker, or
a block with no pin, is IDLE. Wherever this contract says a branch is ACTIVE or
IDLE, it means the outcome of that test. Readers MUST accept the legacy field name
`- **Proposal:**` as an alias of `- **Work item:**` (stale v2.0 files); writers
write only `Work item`.

Writers (no other writer is allowed): **the driving session** during Target-MB
Discovery & Pinning creates or updates `## Active Work`; **`mb-harvest`** (and
`mb-abort`) resets it to IDLE; **`mb-architect-review`** adds (request) and
removes (resume) the `Review:` line only. The v1 fields `Status`, `Run Mode`,
`Execution Mode`, `Loop Mode`, `Affected MBs`, `Implementation Checklist` and
`Auto Loop State` are abolished — do not write them; ignore them in stale files.

## Session Eligibility

Phase 0 of the entry gate (Workspace Discipline), run at session start and
again at the start of `finishing-a-development-branch`. Fail-closed except
where stated:

- `git fetch origin` — hard failure.
- The resolved `pre-push` (`git rev-parse --git-path hooks/pre-push`) exists,
  carries the marker `UMS pre-push guard (Publication Contract)` within its
  first five lines, at a version no lower than the layer's own source header
  (`ums/.claude/hooks/pre-push`, line 2) — compared by ORDERING via
  `Get-UmsHookVersion.ps1`, never by equality against a literal, so a stale
  layer copy cannot downgrade a newer installed hook. Lower or absent: run
  `install-git-hooks.ps1` and recheck, not proceed. `ums-repo.json` is
  informational only.
- The synthetic self-check, both halves, in THIS session's own environment.
  The rejecting line MUST use an UNPUBLISHED commit — a dangling object made
  with `git commit-tree`, never an already-published tip, which the content
  rule would let through for the wrong reason: piping
  `refs/heads/<protected> <dangling-sha> refs/heads/<protected> <head-sha>`
  into `pre-push origin verify` must exit NON-ZERO with a `UMS:` message;
  passing means the agent-session marker is absent in this harness and the
  guarantee does not bind this session. The mirror line
  `refs/heads/UMS-0000-probe <dangling-sha> refs/heads/UMS-0000-probe
  0000000000000000000000000000000000000000` must exit ZERO, silently; failing
  means the hook does not run here at all (wrong shebang, missing execute
  bit, different location) and its rejections prove nothing either.

Either failure is a STOP for any work ending in a push.

## MB Context Reading Rule

Before proposing approaches (brainstorming) and before writing the implementation
plan, read `<PLAN_MB>/brief.md`, `architecture.md`, `tech.md` and `playbook.md`
(those that exist; legacy shape per Memory Bank Document Set), plus the root
`memory-bank/architecture.md` and `tech.md` when the work is cross-cutting.
`playbook.md` is prescriptive — its procedures BIND the work, they are not
background reading. The rest is current-state reference: treat it as authoritative
context, and note in the design when it is stale (the fix for staleness is
`mb-sync` or the harvest at finish, not ad-hoc edits). Every link WRITTEN into a
Memory Bank document — by any skill, harvest or ad-hoc edit — follows Link
Conventions.

## Document Ownership

One fact, one home. Duplication is prevented by ownership, not by asking writers
to be careful.

| The question the fact answers | Home |
|---|---|
| What it is for, for whom, what value it has, what state it is in | `brief.md` |
| What parts it consists of, who talks to whom and how, which pattern it follows | `architecture.md` |
| What it runs on and with — stack, versions, dependencies, configuration, build, deployment | `tech.md` |
| How do I do X — commands, procedures, conventions, traps | `playbook.md` |

**Decision test for the contested `tech` × `architecture` pair** — a test, not a
taxonomy, because a taxonomy can be bent:

- Changes when you **swap a library or version and leave the code alone**? →
  `tech.md`
- Changes when you **rewrite the code and leave the dependencies alone**? →
  `architecture.md`
- Changes in **both** cases (typically "the workflow engine runs on Orleans")? →
  it belongs where the reader looks first, and the other document **links** to it
  with a relative link. It never restates it.

**A fact that already has a home keeps it.** The "reader looks first" question
decides where a NEW fact goes and is not re-litigated afterwards, so the sweep's
"wrong home" verdict (Harvest Contract §3) fires only when branch 1 or branch 2
clearly names a different document — never for a placed "both" fact.

Doklad: contract/doklad/core.md, "Document Ownership, the third case"

**Moving a fact is a legal operation.** `mb-harvest` and `mb-sync` may move a fact
between documents of the same MB, in a binding order: **write into the target
first, only then delete from the source.** Every move is named in the skill's
report, so it is visible there and in the commit diff.

## Publication Contract

**No reference without reachability.** Whenever the workflow names a git object
outside this clone — a link in a ticket description or comment, a wave table, a
handoff comment, a link in an epic ledger — the pinned commit MUST be reachable on
`origin` at that moment. Verify mechanically:

```bash
git fetch origin
git branch -r --contains <sha>     # empty result = not on origin
```

An unreachable commit is a fail-closed STOP with an offer to publish, never a
warning.

**The publication rule: the agent pushes its OWN ticket branch after every
commit**, always announcing the branch and the outgoing commits — the normal end
of every commit on a ticket branch, not a list of milestones to remember. An
unpushed commit exists only in the local `.git`, and a pool slot sharing that
`.git` does not change that: visible from any slot, still absent from `origin`.
The points below are notable special cases, not the whole rule:

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

The agent does not negotiate WHETHER to publish its own branch — but the
harness's own permission prompt still applies (`Bash(git push:*)` is deliberately
in neither `allow` nor `deny` in this layer's `settings.json`): **"does not ask"
is not "the push is auto-approved"**. The effective list of protected branches is
`protectedBranches` (see Repository Configuration; built-in fallback `develop`,
`main`, `master`, `release/*`); both layers resolve protection from it by
different routes — the hook through the plain-text list the installer generates,
`guard-git-push.mjs` by reading `ums-repo.json` itself.

**Two enforcement questions, two layers:**

| Layer | Question | Reach |
|---|---|---|
| The git `pre-push` hook | **What** is pushed | Anything running in an agent session, including commands the user types with a leading `!` |
| `guard-git-push.mjs` (PreToolUse) | **Who** pushes | The agent's own tool calls only; commands the user types with `!` never reach it |

The hook's scope is `refs/heads/*` and it enforces NOTHING outside an agent
session (marker `MB_AGENT_SESSION`; `AI_AGENT` / `CLAUDECODE` are a
Claude-Code-only fallback), so a human pushing from a terminal or an IDE is
untouched. Inside one it allows, on a protected branch, only a **fast-forward
push whose tip is already reachable on the remote being pushed to**, and it
rejects **two bans on every branch it polices, not only protected ones: deleting
a branch through a push, and a non-fast-forward (force) push.** Marker or not, it
also fails CLOSED — whole push, tags included — when it cannot buffer git's ref
list into a temp file, and it runs the chained foreign hook and exits with ITS
result, so a chained hook can reject a push even where this one enforces nothing
of its own. The human escape below lifts the bans with the rest of the guard, and
the two accepted bypasses evade them as they evade everything else here.

Doklad: contract/doklad/publication.md, "Auditability, not review"
Doklad: contract/doklad/publication.md, "What the reachability claim proves"

**A freshly created ticket branch is DETACHED from its inherited upstream, and its
first publication is `git push -u origin <branch>` — never a bare `git push`.**
`git switch -c <branch> <chosen base>` sets the new branch's upstream to the BASE,
a typically protected destination it must never publish to. What stops a bare push
in that state is git's own `push.default=simple` plus `pre-push` — **not** the
`PreToolUse` guard, which on a bare push resolves the target as the CURRENT BRANCH
NAME and allows it ("The epic line", where that mechanism is written once). Two
steps, both at the source: run `git branch --unset-upstream` immediately after the
`switch -c`, and publish the first time with `-u`. A ticket branch whose upstream
is a protected branch is a finding, not a normal state.

The guarantee itself is that `pre-push` hook (`.claude/hooks/pre-push`), installed
into each workspace by `install-git-hooks.ps1`; hooks do not travel with a clone,
which is why the entry gate verifies them (Workspace Discipline). **Verify it
non-destructively, and in both directions**: never with a real
`git push origin develop`, and never with the reject half alone, because a hook
that cannot execute at all also "rejects" everything. **The hook is plain git; the
marker is not** — the guarantee reaches a harness only once `MB_AGENT_SESSION` is
in the environment the push runs in, and where a harness offers no documented way
to inject one, the gate never opens and the publication guarantee rests on contract
text alone. The entry gate surfaces exactly that per session: a synthetic
protected-branch line that PASSES is this state, and is reported as a missing
guarantee. Both recipes — verification and per-harness marker delivery — are in
`contract/integration.md`, section "Publication mechanics".

Doklad: contract/doklad/publication.md, "How the installer recognizes its own hook"

**The human escape: `MB_HUMAN_PUSH=1`** means "a human takes responsibility for
THIS push" and lifts the whole guard — protected-branch rule, deletion ban and
force-push ban alike. The containment against an agent abusing it is the
PreToolUse layer, which DENIES any push carrying the variable, and **the agent
must never set it**. `UMS_ALLOW_SHARED_PUSH` is accepted during the transition and
answered with a deprecation line.

Doklad: contract/doklad/publication.md, "Which rejections name the escape"
Doklad: contract/doklad/publication.md, "Why the human escape is deliberately wide"

**Two spellings, deliberately different — do not collapse them into one.** An
integration command handed to the user is the PLAIN
`! git push origin HEAD:<baseBranch>`, refspec form and NO escape; that is what
`guard-git-push.mjs` hands over when it denies the agent's own push to a
protected branch. The escape appears only in the OTHER spelling,
`! MB_HUMAN_PUSH=1 git push <remote> HEAD:<branch>`, handed over by the
`pre-push` hook's rejection message — the only rejection that offers the escape
at all.

Doklad: contract/doklad/publication.md, "Why the two spellings must not be collapsed"

Two known, accepted bypasses, both requiring deliberate visible intent:
`git push --no-verify` skips the hook entirely, and a one-shot
`git -c core.hooksPath=<other> push` points git at a hooks directory this layer
never installed into. `--no-verify` is a BYPASS of the guarantee, never the
documented way to publish `develop` — it disables every hook in the repository,
and `guard-git-push.mjs` denies it on sight, escape or no escape.

Doklad: contract/doklad/publication.md, "A configured core.hooksPath is not a bypass"

A **foreign `pre-push`** already in the hooks directory is not a reason to leave
the workspace unguarded: the installer moves it aside to `pre-push.ums-chained`
and this hook runs it with the same ref list, so installing the layer cannot
silently turn someone's LFS or lint hook off. It REFUSES to chain where it cannot
make the move safe (the four conditions are in `contract/integration.md`, section
"Publication mechanics"), and **a refusal is not a fallback:** our hook is then
not installed in that workspace at all, the run exits 2, and the publication
guarantee is absent there until someone resolves the foreign hook by hand.

Doklad: contract/doklad/publication.md, "The chained hook's executable bit"

**What neither layer promises.** The `PreToolUse` guard is not a guarantee: it
sees only what it RECOGNIZES as a `git push`, and on what it does recognize it
leans fail-CLOSED. Neither hook stops a determined adversary — **server-side
branch permissions on `origin` are the real backstop**, and nothing in this layer
substitutes for them. A harness with no `PreToolUse` layer at all follows the
actor rule by contract text only, as it does every other rule here. And
**`mb-git-commit` never pushes**: publication is a workflow step of this
contract, not a job of the commit tool.

Doklad: contract/doklad/publication.md, "The PreToolUse guard, what it reads and what it misses"

## Dispatch Model Policy

Model selection is owned by the superpowers workflow: SDD's **Model Selection**
section scales the model to each task's size, complexity and risk. UMS does
**not** pin models per role and carries no `## Model Routing` block.

UMS adds one guard so routine bookkeeping never runs on an expensive model by
accident: a dispatch whose entire job is **summarization or read-only
inspection** — commit messages, Jira comments, harvest notes, read-only scans,
reality-verification passes — SHOULD request the cheapest capable tier.
Everything else follows the skill's own Model Selection.

**Always specify the model explicitly when dispatching a subagent.** An omitted
model inherits the session's model (often the most capable and most expensive),
silently defeating both the superpowers tiering and this guard.

This policy is additive: it never overrides a more specific per-skill instruction
naming an exact model or session-isolation requirement, and sessions outside any
Memory Bank workflow are unaffected.

## Language Contract

- AI-facing instruction text (skill bodies, dispatch prompts, task briefs,
  implementer/reviewer reports, the `.superpowers/sdd/` ledger, orchestration
  metadata) MUST be in English.
- `playbook-candidates/<slug>.md` is AI-facing scratch and therefore English;
  `playbook.md` is a persistent artifact and therefore Czech — the harvest gate
  translates on persistence. `Ruling:` lines in the ledger are English for the
  same reason, while the final "Rulings I made" list is user-facing and Czech.
- User-facing output and persistent artifacts MUST be in Czech: the proposal pair
  content, Memory Bank documents, commit messages, Jira comments, review findings
  rendered to the user, status summaries, and communication with the user.
- AI-facing boilerplate inside the plan file (the "For agentic workers" header,
  `Interfaces:` labels, checkbox syntax) stays English; the task content around
  it is Czech.
- **Developer tooling is English.** The layer's own PowerShell tooling
  (`install-git-hooks.ps1`, `sync-with-monorepo.ps1`, `revendor-superpowers.ps1`,
  `pool-status.ps1`, `pool-launch.ps1`, `pool-provision.ps1`) and its console
  output match the code around them; only what an agent or user meets during
  Memory Bank WORK is Czech — the `pre-push` and `guard-git-push.mjs` rejection
  messages, the `mb-*` skills' reports (`mb-epic-run` included), `doc-index.ps1`
  / `epic-graph.ps1` tables and findings. This is a named exception, not a mixed
  rule surface: the boundary is the artifact, and each artifact is wholly one
  language.
- **A hook whose entire output is model context is English**, even where the same
  hook is on the Czech side for its REJECTION MESSAGES. The criterion is the
  audience of the output, not the file's kind: a rejection a human reads is Czech,
  an `additionalContext` payload a model reads is English.
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

**A message does no harm by INTERRUPTING; it does harm by carrying authority
and getting written down.** Everything in this section follows from that
sentence, and none of it is about how often anyone writes.

Doklad: contract/doklad/message-protocol.md, "Why a message carries a mark"

**Every message from an orchestrator to a session or subagent it coordinates —
an epic's manager to a ticket session, a plan's orchestrator to an implementer —
carries exactly ONE mark on its first line, and the mark is the mechanism.** The
other direction carries no mark: authority runs one way, and a report, a
correction or a handoff artifact travelling back up carries none of it.

- **`Mark: instruction`** — the message states a BOUNDARY: what the recipient may
  or may not do, where its work ends, which branch, base or artifact it works
  with, which of two things goes first, when it stops. The sender owns that
  boundary, or a written rule does, and the recipient can check it against
  whichever is claimed. A fact of the sender's OWN action, verifiable by the
  recipient in a shared artifact (the fast-forward landed, at this SHA, onto this
  branch), is an instruction too: the marking is BINARY and total, and a message
  must never go out unmarked for want of a third mark.
- **`Mark: conjecture`** — the message states a CAUSE or a prediction: why
  something is happening, what a symptom means, what the recipient is about to
  find, what would fix it. Nothing but the recipient's own measurement settles it.

The mark is English like every other AI-facing text and rendered to the user as
*pokyn* and *domněnka* (Language Contract). Three consequences, and they are why
the mark exists at all:

- **The recipient MAY refuse a conjecture, and refusing is NORMAL behaviour, not
  friction.** It needs no permission and no round trip: name the conjecture being
  refused, say what your own measurement showed instead, and carry on.
- **A conjecture is NEVER written into the ledger as fact.** Either it is not
  written at all, or it is written attributed and flagged as unverified ("the
  manager believes X; not verified here"). Once the recipient has a measurement,
  the ledger records the MEASUREMENT — never the message that predicted it.
- **The recipient MUST refuse an instruction that contradicts a written
  rule** — a rule of this contract, of the plan it is executing, or of the
  skill it is running. It names the rule, states what it refused, does not
  comply, and continues. The duty ends at the refusal: refusing and naming the
  rule is the whole of it.

## Escalation & Autonomy

**"When to stop" and "how much to stop" are not quantities anyone turns — they
are rules.** Two of them bind every session in this layer, epic work or not:

> **Ending a turn is legitimate only where you are waiting for a human's
> answer, a manager's answer, or a subagent to finish — and that waiting must
> be NAMED**: by the `NOW` block's state class where the block exists, and in
> the report everywhere else. What cannot be named is not a reason to end a
> turn.

> **When you formulate a question, name what does NOT depend on the answer —
> and do that part immediately**, in the same turn as the question.

**The floor — always a human, and no autonomy level moves it off one**

| Kind | Example |
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

**Rulings and these STOPs.** Upstream subagent-driven-development (v6.3.0) rules
on conflicts instead of stalling and stops only for four named classes. This
layer's fail-closed STOPs are not a fifth class — they FALL WITHIN those four: a
push to a shared branch and the integration push are "a side effect outside this
clone that norms say you ask about first"; an active-work collision, an
unprotected base and an unreachable pinned commit are irreversible in the same
sense; a plan too broken to follow is upstream's fourth class verbatim. One thing
is deliberately NOT such a side effect: **merging the effective base into the
agent's OWN ticket branch.** It is mandatory at phase boundaries (Base Sync &
Drift Detection) and is never put to the user — reading upstream's word "merge"
as covering it would turn the mandatory base sync before the first dispatch into
a question.

Doklad: contract/doklad/escalation.md, "Context rotation as a fifth class"

## Citation & Versioning

**Citation form.** A rule of this core is cited by contract plus section name —
`(contract, "Fail-Closed Behavior")`; a rule of a reference file, by reference
path plus section name — `(contract/epic-line.md, "The epic line")`. The section
is named in words, spelled exactly as its heading reads, so every citation is
mechanically checkable against the heading index — never as a `#fragment` anchor
(Link Conventions). Evidence is never cited as a rule: `contract/doklad/*.md` is
read on demand and settles no question this contract does not settle itself.

**File placement.** The core is `<skills_root>/shared/UMS_MEMORY_BANK_CONTRACT.md`,
its references `<skills_root>/shared/contract/*.md`, their evidence
`<skills_root>/shared/contract/doklad/*.md`. A `SKILL.md` resolves the core as
`../shared/UMS_MEMORY_BANK_CONTRACT.md` relative to its own directory, falling back
to `<skills_root>/shared/UMS_MEMORY_BANK_CONTRACT.md`; **never search the filesystem
recursively**, and if both paths fail stop with
`UMS_MEMORY_BANK_CONTRACT.md not found at <skills_root>/shared/.` Skills and docs
link this contract relatively from their own directory.

**Version lives in the core only.** The `Contract-Version` line at the top of this
file is the single authority for the contract's version; no reference or evidence
file carries one, and the per-version history is kept in `shared/CHANGELOG.md`. The
vendored superpowers upstream version is pinned separately in
`shared/VENDORED_FROM.md` (tag, commit, skill list). UMS modifications to vendored
skills exist ONLY as marked `<!-- UMS-OVERLAY BEGIN/END -->` blocks, generated from
`shared/overlays/*.overlay.md` by `.claude/scripts/revendor-superpowers.ps1`; never
edit vendored files by hand outside those blocks. Upgrading upstream: re-run the
vendoring script per the procedure in `VENDORED_FROM.md` — an overlay anchor miss
is the upstream-drift detector, not a defect to work around.
