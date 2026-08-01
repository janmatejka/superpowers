# UMS Memory Bank Contract

- **Contract-Version:** 2.2
- Supersedes v2.1 (adds the Publication Contract and Cross-Branch Visibility
  sections and the two-tier push policy). v2.0 renamed the document pair to
  `design_`/`plan_` and added the Architect Review Gate; v1
  (mb-plan/mb-act orchestration) remains superseded.
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
   `mb-harvest`, `mb-abort`, `mb-git-commit`, `mb-git-message`,
   `mb-jira-update`.
3. Any other agent or session working with Memory Bank documents.

## Three-Tier Directory Model

UMS Memory Bank uses a three-tier directory model across the monorepo:

- **`CTX_DIR`** — `<MB_ROOT>/memory-bank/` — the orchestration root of the
  repository. Holds `context.md` (Jira link, `Target MB Pin`, `Work item` slug,
  `Started`).
- **`PLAN_MB`** — `<MB_ROOT>/<Target MB Pin>` — the project Memory Bank the
  current work targets. Holds the active design + plan pair and the project
  documents (`brief.md`, `product.md`, `architecture.md`, `tech.md`,
  `tasks.md`).
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
  proposal folders and core docs; leaves `context.md` absent. After `mb-init`,
  the next step is the superpowers workflow — Target-MB Discovery & Pinning
  (below) creates `context.md` during brainstorming.
- **Project MB (`PLAN_MB`)** — creates `<MB_ROOT>/<path>/memory-bank/` with
  `proposals/{next,active,completed,abandoned}/` and project docs. Used when
  initializing project MBs for new components. Does not touch `CTX_DIR`.

## Scope Lock (Memory Bank documents only)

The scope lock governs **Memory Bank document writes only**:

- MB documents are written only under `CTX_DIR`, `PLAN_MB`, and — during
  harvest — `AFFECTED_MBS`.
- Superpowers spec/plan documents are written only under
  `<PLAN_MB>/proposals/` (see Superpowers Document Placement).

Explicitly **legal and outside this lock**:

- Source-code changes anywhere in the repository.
- The superpowers scratch tree `<MB_ROOT>/.superpowers/` (task briefs,
  implementer reports, review packages, progress ledger) — git-ignored,
  ephemeral, owned by the superpowers execution skills.
- Plan checkboxes and task-progress tracking inside the plan file and the
  `.superpowers/sdd/` ledger.

Other rules:

- Relative links from Memory Bank docs must stay relative to the file that
  contains them.
- Do not hardcode machine-specific or repository-root absolute paths.

## Active Work Item (Design + Plan Pair)

One active work item per repository = one **design + plan pair** in
`<PLAN_MB>/proposals/active/`:

- **`design_<slug>.md`** — the spec, written by `brainstorming`
  (intent source of truth).
- **`plan_<slug>.md`** — the implementation plan, written by
  `writing-plans` (execution source of truth). On conflict between the two,
  the plan governs execution; report the discrepancy to the user.

Rules:

- The pair is created by the superpowers workflow and is never duplicated into
  `docs/` or any parallel location.
- Task progress lives in the plan file's checkboxes and in
  `.superpowers/sdd/progress.md` — **not** in `context.md`.
- **Archival asymmetry:** on **completion** (harvest → `completed/`) only the
  design half is retained; the plan half is **deleted** — after implementation
  its task steps are spent; code, git history and the harvested current-state
  MB docs carry the outcome. If there is no design half (grandfathered single
  plan), archive that plan to `completed/` instead of deleting it. On
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
  - **Plán:** [plan_<slug>.md](plan_<slug>.md)
  - **Vytvořeno:** YYYY-MM-DD
  ```
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
   under `<MB_ROOT>`, then run the `mb-doc-index` skill and take the candidate
   set as the UNION of the local scan and the index over `origin`.
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
8. **Two-actives guard:** if an active proposal (pair or legacy single) with a
   *different* slug already exists anywhere under `<MB_ROOT>`, stop and ask
   the user — finish it (`finishing-a-development-branch` → harvest) or
   abandon it (`mb-abort`) before pinning new work. Only `active/` counts;
   queued items in `next/` are ignored by this guard.
   The two-actives guard stays LOCAL (one active work item per clone, because
   `context.md` holds one pin); extending it to `origin` would forbid parallel
   work across the team. Alongside it runs the **cross-clone collision check**:
   the SAME slug or the SAME Jira ticket active on a foreign branch is a
   fail-closed STOP (double work), and the report carries the branch and the last
   commit date so the user can tell an abandoned branch from live work. Foreign
   active slugs of OTHER tickets are normal parallel operation — list them, never
   stop.
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
implementation plan, read `<PLAN_MB>/brief.md`, `product.md`,
`architecture.md`, `tech.md` (those that exist), plus the root
`memory-bank/architecture.md` and `tech.md` when the work is cross-cutting.
These documents are current-state reference — treat them as authoritative
context, and note in the design when they are stale (the fix for staleness is
`mb-sync` or the harvest at finish, not ad-hoc edits).

## Harvest Contract

Consumed by `mb-harvest` (invoked from the finishing-a-development-branch
overlay, or standalone). Code is the source of truth; documentation follows
code.

1. **Preconditions (fail-closed):** `context.md` has a `Target MB Pin` and
   `Work item` slug; the active proposal (pair or legacy single) exists in
   `<PLAN_MB>/proposals/active/` and matches the slug.
2. **Affected MBs:** derive from
   `git diff --name-only $(git merge-base <base> HEAD)..HEAD`, mapping each
   changed path to its nearest owning `memory-bank/` directory. Fall back to
   asking the user when the diff is unavailable.
3. **Harvest style — CURRENT-STATE (MANDATORY):** persistent MB docs
   (`architecture.md`, `tech.md`, `brief.md`, `product.md`, `tasks.md`)
   describe the current state in present tense, as reference documentation.
   They are NOT a changelog:
   - Fold harvested facts into the relevant current-state section; do not
     duplicate facts already described.
   - DO NOT create or append dated changelog sections ("Nedávné změny",
     "Recent Changes", "Changelog", "Historie změn", "Naposledy provedeno").
   - History lives in `proposals/completed/` and git — never in state docs.
   - When a change removes something, describe the new state; do not narrate
     the removal.
   - Update `architecture.md` (components, patterns, diagrams, cross-project
     links), `tech.md` (dependencies, versions, configuration, build notes),
     and `brief.md`/`product.md` only if core features or UX changed.
   - Continue with remaining affected MBs if one update fails; capture
     failures for the final report.
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

**Publication points** (when the actor's own branch is pushed):

1. after the design document is written and committed (brainstorming),
2. after the implementation plan is written and committed (before the first task
   dispatch),
3. at elaboration window closure, BEFORE writing links into Jira,
4. before every handoff (design review request/respond is the reference
   implementation).

**Two-tier push policy:**

| Tier | Rule |
|---|---|
| The actor's own ticket branch (unprotected) | The agent pushes it itself, without asking, but ALWAYS announces the branch and the outgoing commits. Force push is forbidden. |
| Shared branches (`develop`, `main`, `master`, `release/*`) | The agent NEVER pushes. It prepares the exact command with the outgoing commits and the user approves or runs it (in-session: `! git push origin develop`). The agent then re-verifies reachability. |

Mechanically enforced for Claude Code by the PreToolUse hook
`.claude/hooks/guard-git-push.mjs` (deny-by-default: it allows a push only when
parsed with confidence as a simple push to a branch outside the protected-name
deny-list, and denies every other shape, including ones it cannot parse). Other
harnesses follow this rule by contract text only, as with every other rule of
this layer. `mb-git-commit` never pushes — publication is a workflow step at
the points listed above, not a commit tool.

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
- **A ticket branch is created from the CURRENT base ref** (fetch +
  fast-forward), otherwise it cannot see already-merged planning.
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
notes are thus available to both sides and to Bitbucket links. Recommended
branch naming: include the ticket code (e.g. `feature/ums-3302-toast-reconcile`).

**Push policy:** per the Publication Contract — the ticket branch is the actor's
own branch, so the handoff push is announced, not negotiated; shared branches are
never pushed by the agent. Steps are ordered so one handoff needs exactly one
push.

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
- User-facing output and persistent artifacts MUST be in Czech: the proposal
  pair content, Memory Bank documents, commit messages, Jira comments, review
  findings rendered to the user, and status summaries.
- Communication with the user in this repository is in Czech.
- AI-facing boilerplate inside the plan file (the "For agentic workers"
  header, `Interfaces:` labels, checkbox syntax) stays English; the task
  content around it is Czech.
- If language rules conflict across workflow surfaces, Czech requirements for
  user-facing/persistent text take precedence.

## Worktree Policy & Pool Interface

**Default: total ban.** Git worktrees must not be used in this monorepo — the
repository is extremely large and worktree creation is expensive (time and
disk). Enforced by: `permissions.deny` on `EnterWorktree`/`ExitWorktree`,
`skillOverrides: using-git-worktrees: off`, and the CLAUDE.md ban. The
superpowers isolation step resolves to **branch-in-place**: create a feature
branch in the existing working directory (never work on main/master without
explicit user consent).

**Future worktree pool (interface only — not implemented):**

- Activation requires BOTH: `<MB_ROOT>/.claude/worktree-pool.json` with
  `"enabled": true`, AND an explicit user request for isolated/parallel
  execution of the work item. Otherwise the ban stands.
- Pool manifest shape:
  `{ "enabled": bool, "slots": [{ "path": …, "state": "free"|"assigned",
  "branch": …, "slug": …, "assignedAt": … }] }`.
  Slots are pre-provisioned real linked worktrees (`git worktree add`),
  created and rebuilt only by an out-of-band admin script — never by a skill.
- Assignment: at execution start, claim a `free` slot (update manifest →
  `git -C <slot> fetch && git -C <slot> checkout -B <branch> <base>` →
  continue with the slot as working directory).
- Detection: slots are genuine linked worktrees, so upstream
  `using-git-worktrees` Step 0 recognizes them without patching
  (`GIT_DIR != GIT_COMMON` → already isolated, skip creation).
- Release: a future `mb-worktree-release` utility detaches the slot to the
  base commit and marks the manifest `free`. Finishing's provenance rule
  already protects slots (they are not under `.worktrees/`).
- Enabling the pool later = flip `skillOverrides` for `using-git-worktrees`
  back on; nothing else changes.

## Fail-Closed Behavior

When anything important is missing or ambiguous:

- Stop instead of guessing. Do not silently downgrade to another root,
  repository, or artifact location.
- Hard failures: missing git; missing root `memory-bank/`; undefined
  `PLAN_MB` at spec-write time; ambiguous target MB; a second active proposal
  slug; mixed-language rule surfaces; an unreachable pinned commit at
  publication time; the same slug or ticket active on a foreign branch.
- NOT failures (explicitly legal): writing source code outside
  `memory-bank/`; the `.superpowers/` scratch tree; plan checkboxes; the
  `.superpowers/sdd/progress.md` ledger.

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
