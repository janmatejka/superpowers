# UMS Memory Bank Contract

- **Contract-Version:** 2.0
- Supersedes v1 (the mb-plan/mb-act orchestration model). See `VENDORED_FROM.md`
  for the vendored Superpowers version this contract is written against.

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
  repository. Holds `context.md` (Jira link, `Target MB Pin`, `Proposal` slug,
  `Started`).
- **`PLAN_MB`** — `<MB_ROOT>/<Target MB Pin>` — the project Memory Bank the
  current work targets. Holds the active proposal pair and the project
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

## Active Proposal Pair

One active work item per repository = one **proposal pair** in
`<PLAN_MB>/proposals/active/`:

- **`proposal_<slug>-design.md`** — the spec, written by `brainstorming`
  (intent source of truth).
- **`proposal_<slug>.md`** — the implementation plan, written by
  `writing-plans` (execution source of truth). On conflict between the two,
  the plan governs execution; report the discrepancy to the user.

Rules:

- The pair is created by the superpowers workflow and is never duplicated into
  `docs/` or any parallel location.
- Task progress lives in the plan file's checkboxes and in
  `.superpowers/sdd/progress.md` — **not** in `context.md`. The v1
  `Implementation Checklist` and `Auto Loop State` are abolished.
- **Archival asymmetry:** on **completion** (harvest → `completed/`) only the
  design half `proposal_<slug>-design.md` is retained; the implementation plan
  `proposal_<slug>.md` is **deleted** — after implementation its task steps are
  spent, and code, git history and the harvested current-state MB docs carry
  the outcome. If there is no design half (grandfathered single plan), archive
  that plan to `completed/` instead of deleting it, so a record remains. On
  **abandon** (`mb-abort` / Discard → `abandoned/`) both halves move together,
  unchanged, nothing deleted. If a half is missing at archive time, warn and
  handle what exists.
- A design file without its plan sibling is a valid intermediate state
  (between brainstorming and writing-plans).
- An empty `proposals/active/` directory may be absent from the working tree
  (git does not track empty directories; no `.gitkeep` convention). Skills
  MUST tolerate the missing directory and recreate it on demand when placing
  a new proposal — absence of `active/` means "no active work", not a broken
  Memory Bank.

**Naming:** `proposal_<slug>.md` / `proposal_<slug>-design.md`. The slug
MUST start with the ticket code whenever one is known:
`<jira>_<short_snake_case_topic>`, with the ticket code normalized to
lowercase snake case (`UMS-3302` → `ums_3302_toast_reconcile`); without a
known ticket use `<short_snake_case_topic>` alone. ASCII only, no
diacritics, no dates in the name (dates live in `Started` and git history).
When the ticket becomes known later (e.g. at activation of a preliminary
proposal), rename the slug's files to include it.

**Preliminary proposals (`next/`):** work items may be planned ahead of time
as preliminary proposals in `<MB>/proposals/next/` — any number may queue
there, unlike the single work item in `active/`. A preliminary proposal is a
draft: a single `proposal_<slug>.md`, optionally already accompanied by a
`proposal_<slug>-design.md`. Rules:

- Creating or editing a preliminary proposal does NOT touch `context.md`,
  does not require the IDLE state, and does not pin a Target MB — it is
  planning, not active work.
- When work on it starts, ALL files of its slug move from `next/` to
  `active/` (see Target-MB Discovery & Pinning) and the normal workflow
  continues — brainstorming treats the moved draft as seed input for the
  design, refining it rather than starting from scratch.
- Queued items in `next/` never count against the two-actives guard.
- A queued item that is dropped without being started moves to `abandoned/`.

**Grandfather clause:** a legacy single-file `proposal_*.md` in
`proposals/active/` (created under contract v1) is a valid plan artifact.
New work always produces the two-file pair. Harvest and archive treat legacy
single files the same as pairs. Never convert or touch the archived proposals
in `proposals/completed/`.

## Superpowers Document Placement

This section implements the upstream escape hatch — brainstorming and
writing-plans both state: *"(User preferences for spec/plan location override
this default)"*. The preference in this repository is:

| Superpowers artifact | Default upstream location | UMS location |
|---|---|---|
| Design/spec (brainstorming) | `docs/superpowers/specs/…-design.md` | `<PLAN_MB>/proposals/active/proposal_<slug>-design.md` |
| Implementation plan (writing-plans) | `docs/superpowers/plans/….md` | `<PLAN_MB>/proposals/active/proposal_<slug>.md` |

Prohibited locations (mechanically enforced by a PreToolUse hook):
`docs/superpowers/specs/`, `docs/superpowers/plans/`, `docs/plans/`.

Document headers:

- `proposal_<slug>-design.md` starts with:
  ```markdown
  # Návrh: <název>

  - **Jira:** UMS-XXXX | (žádný tiket)
  - **Target MB:** <relative path>/memory-bank/
  - **Plán:** [proposal_<slug>.md](proposal_<slug>.md)
  - **Vytvořeno:** YYYY-MM-DD
  ```
  Body sections follow the established proposal corpus: `## Cíl`, `## Scope`,
  `## Technický návrh`, `## Dopady`, `## Rizika` (scaled to complexity).
- `proposal_<slug>.md` keeps the upstream plan header verbatim (the
  "For agentic workers: REQUIRED SUB-SKILL …" block is load-bearing for
  subagent-driven-development), followed by an MB metadata block (`**Jira:**`,
  `**Návrh:** [proposal_<slug>-design.md](…)`, `**Target MB:**`), then the
  upstream structure (`## Global Constraints`, tasks with `**Interfaces:**`
  and checkbox steps).

## Target-MB Discovery & Pinning

Runs **during brainstorming**, as soon as the affected code area is
identifiable — always before the design document is written.

1. Scan `**/memory-bank/proposals/active/proposal_*.md` under `<MB_ROOT>`.
2. Normalize each match to its owning `memory-bank/` root; strip a trailing
   `-design` from the file stem and group by `(owning MB root, slug)` — one
   pair (or legacy single file) = one candidate.
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
   slug from `next/` to `active/`, reuse its slug and ticket, and treat the
   draft as seed input for the design. No match → continue with a fresh
   proposal.
7. Ask for the Jira ticket (one question; "none" is a valid answer; skip if
   already known from the activated preliminary proposal). If the ticket is
   known and the slug does not start with its code, rename the slug's files
   accordingly (Naming rule in Active Proposal Pair).
8. **Two-actives guard:** if an active proposal (pair or legacy single) with a
   *different* slug already exists anywhere under `<MB_ROOT>`, stop and ask
   the user — finish it (`finishing-a-development-branch` → harvest) or
   abandon it (`mb-abort`) before pinning new work. Only `active/` counts;
   queued items in `next/` are ignored by this guard.
9. Persist into `CTX_DIR/context.md` (creating the file if absent):
   `Target MB Pin`, `Jira`, `Proposal` slug, `Started` (see the schema below).
10. Invalidation: the pin (and thus `PLAN_MB`) becomes invalid when the active
    proposal slug changes or the pinned path no longer exists — re-run this
    discovery, do not silently fall back.

## `context.md` Schema & Writers

`<CTX_DIR>/context.md` is a small state file — the workflow itself lives in
the superpowers skills and the proposal pair.

Active state:

```markdown
# Context

## Active Work

- **Jira:** UMS-XXXX (https://jira.datasys.cz/browse/UMS-XXXX)
- **Target MB Pin:** <relative path>/memory-bank/
- **Proposal:** <slug>
- **Started:** YYYY-MM-DD
```

IDLE state: replace the `## Active Work` items with
`(No active work - IDLE phase)`; keep the `- **Jira:** …` line of the last
work item if it existed.

Writers (no other writer is allowed):

- **The driving session** during Target-MB Discovery & Pinning — creates or
  updates `## Active Work`.
- **`mb-harvest`** (and `mb-abort`) — resets `## Active Work` to IDLE.

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
   `Proposal` slug; the active proposal (pair or legacy single) exists in
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
4. **Archive:** move only the design half `proposal_<slug>-design.md` from
   `active/` to `completed/` unchanged (durable spec record) and **delete** the
   implementation plan `proposal_<slug>.md` (remove the file; the harvest
   commit records the deletion). If there is no design half (grandfathered
   single plan), archive that plan to `completed/` so a record remains. Abandon
   path (`mb-abort`, or Discard in finishing) moves BOTH halves to `abandoned/`
   instead, deleting nothing.
5. **Reset:** only if every affected MB update succeeds, reset
   `context.md` `## Active Work` to IDLE per the schema above. On partial
   failure, leave `context.md` unchanged and report.
6. **Announce (Czech)** and offer `mb-jira-update` when a Jira ticket is
   linked.

All harvested document content is Czech.

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
  slug; mixed-language rule surfaces.
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
