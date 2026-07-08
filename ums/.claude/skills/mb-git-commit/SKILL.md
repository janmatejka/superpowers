---
name: mb-git-commit
description: You MUST use this before committing code changes - runs a generic commit workflow with Superpowers scoped staging policy, stages current repository changes, generates a commit message, and executes git commit.
license: MIT
metadata:
  author: UMS Project
  version: "2.0"
---

> Follow [UMS_MEMORY_BANK_CONTRACT](../shared/UMS_MEMORY_BANK_CONTRACT.md) for MB_ROOT resolution, the proposal pair model, and fail-closed rules.

**Command:** mb-git-commit


**Action:** Stage changed code, generate message, and execute git commit.

**Execution:** **Autonomous** - executes `git commit`.

---

## Workflow

### 0. Resolve MB_ROOT (MANDATORY)

Resolve `MB_ROOT` with exactly one discovery step:

```bash
git rev-parse --show-toplevel
```

Rules:

- Use the git root as the only MB root model.
- If `git` is missing or the command exits non-zero, stop immediately with: `Git repository not found. Memory Bank requires git.`
- On success, set `MB_ROOT` to the returned git root and `CTX_DIR` to `<MB_ROOT>/memory-bank/`.

**Scope lock (Memory Bank files):**

- Read and write Memory Bank files only inside `CTX_DIR`, `PLAN_MB`, and `AFFECTED_MBS` during harvest unless the user explicitly requests cross-project synchronization.
- The root `context.md` is the only operational state file described by this handshake.

**Before first write, announce:**

- `[Memory Bank: Active - <ProjectName> @ <MB_ROOT>]`
- `Orchestrační kořen: <CTX_DIR>/, Cílová MB: <PLAN_MB>/`
- `Reason: git-root discovery`

### PLAN_MB Derivation

If `<CTX_DIR>/context.md` exists, read the `## Active Work` → `Target MB Pin` field to derive `PLAN_MB`. If the pin is missing, `context.md` does not exist, or the pin points to a non-existent directory, `PLAN_MB` is **undefined**. Do NOT silently default to `<CTX_DIR>`.

When `PLAN_MB` is undefined, this skill does not select a target itself — Target-MB Discovery & Pinning runs in the superpowers workflow (during brainstorming) per `UMS_MEMORY_BANK_CONTRACT.md`: discovery scan for `**/memory-bank/proposals/active/proposal_*.md` (the glob matches both pair halves — strip a trailing `-design` from the file stem and group by slug; one pair or grandfathered legacy single file = one candidate) → evidence tags (`seed_hit`, `active_hit`, `explicit_hit`, `untrusted`) → A/B/C disambiguation (where options A/B/C represent specific candidate Memory Banks (MBs) derived dynamically from the current conversation context; the agent provides recommendations, but the choice is always made by the user) → persist `Target MB Pin`.

If the protocol is exhausted and no trusted candidate remains, STOP and ask the user to confirm `<CTX_DIR>` as the target or provide an explicit path. Do NOT silently fall back to `<CTX_DIR>`. If the user confirms `<CTX_DIR>`, use it as `PLAN_MB`.

### Language Contract

- Communication with the user in Memory Bank workflows MUST be in Czech.
- Proposals and persistent Memory Bank documents (brief.md, product.md, architecture.md, tech.md, tasks.md, context.md) MUST be in Czech.
- Mixed language policy in the same rule surface is invalid and must fail closed.

### 1. Load Context & Detect Phase (MANDATORY)

Use a **Session Cache** keyed by `MB_ROOT` and the current workflow session. Within one workflow session, cached refresh is the default; full reload is an invalidation path, not the normal path.

#### 1.1 Determine load mode

Prefer the lightest valid mode for the current workflow step:

- **bootstrap/full**: first access for `MB_ROOT`, `MB_ROOT` changed, explicit reload/rescan, fingerprint mismatch, before a critical operation, or any uncertainty about context integrity
- **cached**: same-session workflow step with no invalidating write; read `context.md` and the active proposal pair referenced from it
- **delta refresh**: after a Memory Bank write in the current session; re-read only the touched files plus `context.md`, then validate the narrowed fingerprint set

Rules:

- Do not full reload again just because another workflow step started in the same session.
- If a local step or delegated worker changes Memory Bank files, invalidate only the touched paths.
- If the cache cannot be validated, fall back to full reload.

#### 1.2 Full reload path

Read the root state first, then the work it points to:

- read `<CTX_DIR>/context.md`
- read the active proposal pair (or grandfathered legacy single file) referenced by the `Proposal` slug in `## Active Work`
- read any project docs explicitly needed for the current workflow step; task progress lives in the plan file's checkboxes and `.superpowers/sdd/progress.md`, not in `context.md`

Then:

- refresh the session summary and fingerprint table
- emit marker:
  - first full load in session: `[Memory Bank: Active - <ProjectName> @ <MB_ROOT>]`
  - trigger-based reload: `[Memory Bank: Reloaded - <ProjectName> @ <MB_ROOT>]`
- record `Last Full Reload: <timestamp>`

#### 1.3 Cached path (no trigger)

Do a lightweight refresh from the root state:

- read `<CTX_DIR>/context.md`
- inspect the active proposal pair referenced by the `Proposal` slug in `## Active Work`
- refresh any Memory Bank files touched by the current workflow step (affected MBs are derived from the git diff at harvest, not tracked in `context.md`)
- validate fingerprints against cache; if mismatch appears or the touched set is broader than expected, switch to full reload
- emit marker: `[Memory Bank: Cached - <ProjectName> @ <MB_ROOT>]`
- preserve previously recorded `Last Full Reload`

This policy keeps context fresh while preventing redundant full reads between tasks.

### Phase Detection

**Workflow phase is derived from the root `context.md`:**

- If `<CTX_DIR>/context.md` is missing, set `PHASE = IDLE` — the file is created by the superpowers workflow (Target-MB Discovery & Pinning during brainstorming).
- Read the `## Active Work` section in `<CTX_DIR>/context.md`.
- If `## Active Work` is empty or contains `(No active work - IDLE phase)`, set `PHASE = IDLE`.
- Otherwise set `PHASE = ACTIVE_WORK`.
- The `Proposal` slug in root `context.md` is only a pointer to the active proposal pair; it is not the phase source.
- Ignore any abolished v1 state fields when found in a stale file (contract v2 lists them).

### Phase Implications

- **IDLE:** No active work in root `context.md`; new work starts with the superpowers workflow (describe what to build → brainstorming)
- **ACTIVE_WORK:** Root `context.md` contains active work; the referenced proposal pair (`proposal_<slug>-design.md` + `proposal_<slug>.md`, or a grandfathered legacy single file) lives under `<PLAN_MB>/proposals/active/`. The sub-phase is read from the workflow artifacts, not from `context.md`:
  - **Design only** (no plan sibling yet): between brainstorming and writing-plans
  - **Pair complete, no task progress:** ready for subagent-driven-development / executing-plans
  - **Tasks in progress:** plan checkboxes and `.superpowers/sdd/progress.md` show partial completion
  - **All plan tasks complete:** ready for finishing-a-development-branch (harvest gate → `mb-harvest`)

### Write Safety Gate (MANDATORY)

Before any Memory Bank write operation:

1. List target files.
2. Verify all target files are under `<CTX_DIR>/, <PLAN_MB>/, or <AFFECTED_MBS>/`.
3. If any target is outside `<CTX_DIR>/, <PLAN_MB>/, or <AFFECTED_MBS>/` and the user did not explicitly request cross-project sync, stop and ask.

Scope lock remains active until command completion.

## Runtime-aware delegation

- Delegation is allowed only when the delegated worker has verified shared repository state with the parent session.
- Shared repository state means the same repo, branch, worktree, and staging area.
- The delegated worker MUST re-activate this skill (or equivalent command instructions) in its own session and verify git state before any write.
- If shared git state cannot be guaranteed, do not execute the final git write in the delegated worker; return the prepared result to the parent session or keep the entire command in the parent session.
- If delegation proceeds and root `context.md` has a `## Model Routing` block, dispatch the delegated worker with `Summarizer Model` per [Model Routing Consumption](../shared/UMS_MEMORY_BANK_CONTRACT.md#model-routing-consumption).

## Idle Git Fallback

- Applies to `mb-git-*` commands: `mb-git-message` and `mb-git-commit`.
- `mb-git-*` commands may run without an active proposal.
- If no active proposal is found for non-plan resolution, use `reason=idle_git_fallback`.
- In this fallback, use the current working directory as the operational scope and continue with a warning state instead of a hard STOP.
- Warning code: `NO_ACTIVE_PROPOSAL_FALLBACK`.

- `mb-git-*` commands may run without an active proposal.

### 1. Gather Context

- **Get Branch Name:** Run `git rev-parse --abbrev-ref HEAD`
- **Get Working Tree Changes:** Run `git status --short`
- **IF** no changes: Stop and report "No changes to commit."

### 2. Stage Current Work

- Stage files changed during the current work in this repository:
  - `git add -A`
- Verify staged diff:
  - `git diff --staged`
- **IF** staged diff is still empty: Stop and report "No staged changes to commit."

### 3. Generate Commit Message

**Context Variable:**
- `branchName`: from step 1
- `stagedDiff`: from step 2

**Prompt for Generation:**
```text
# Commit Message Conventions

## You are a capable generator that creates concise and useful Git commit messages

## The message must be in Czech.

## Message Structure
- Start with `issue-number:` followed by a short change summary (max 72 characters).
- If `context.md` contains `- **Jira:** <ID>` (where ID is not `(no ticket)` and not legacy `(bez tiketu)`), use that ID as `issue-number`.
- Otherwise derive `issue-number` from the beginning of the current `git branch` name, for example `UMS-0000`.
- If the branch name does not match pattern `XXX-0000`, use the full branch name.
- Current `git branch` is: "${branchName}".
- Following lines should contain change details.
- Each change line starts with ` - ` followed by a compact description on the same line.
- Do not explain why the change was made.
- Do not include non-functional changes such as formatting-only edits, code moves, or variable renames.
- Do not include wrapper text like "Here is a commit message proposal"; output only the message itself.

## Changes (Diff)
${stagedDiff}
```

### 4. Execute

1. **Execute:** Run `git commit -m "GENERATED_MESSAGE"`
2. **Report:** Show result (Success/Error).
3. **Complete command after local commit:** Do not run `git push`.

### 5. Push Guardrail (MANDATORY)

- `mb-git-commit` performs local commit only.
- Never execute `git push` as part of this command.
- Never ask for interactive approval/confirmation to run `git push`.
- If remote update is requested, require a separate explicit user command outside `mb-git-commit`.

---

## Superpowers Overlay (mb-git-commit)

**Precedence rule:** If any instruction conflicts with this overlay, this overlay wins.

### Scoped staging policy (MANDATORY)

Replace broad staging with scoped staging. Stage only files that belong to the current work item — in v2 that legitimately includes:

- source-code changes produced by the superpowers workflow (plan tasks),
- Memory Bank document updates under <CTX_DIR>/, <PLAN_MB>/, and relevant <AFFECTED_MBS>/,
- proposal pair moves from `proposals/active/` to `proposals/completed/` or `proposals/abandoned/`.

Rules:

- Never stage unrelated monorepo changes that do not belong to the current work item.
- Avoid blind `git add .` in monorepo workflows; enumerate paths explicitly.

Example:

- `git add <changed source paths> <CTX_DIR>/ <PLAN_MB>/` (AFFECTED_MBS are staged according to the current work item)
### Commit message policy (MANDATORY)

Keep commit text aligned to Memory Bank state:

- Read `<CTX_DIR>/context.md` before generating the final commit message when active work exists.
- Prefer the active proposal pair (design goal + plan tasks) and verification evidence when `context.md` shows `ACTIVE_WORK`.
- When `ACTIVE_WORK`, consider the current plan task (plan checkboxes and `.superpowers/sdd/progress.md`) – the commit message should reflect which task is being completed.
- **Jira ticket priority:** If `context.md` contains `- **Jira:** <ID>` where ID is not `(no ticket)` and not legacy `(bez tiketu)`, use that ID as the `issue-number` prefix instead of the git branch extraction.
- Use only the staged diff and branch name when the repository is `IDLE`.
- Keep the commit message in Czech and follow the existing branch-prefix convention from the base commit workflow.

