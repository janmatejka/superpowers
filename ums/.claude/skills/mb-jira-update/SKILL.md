---
name: mb-jira-update
description: Extract implementation status and deployment instructions from active proposals and publish a summary comment to Jira.
license: MIT
metadata:
  author: UMS Project
  version: "2.0"
---

> Follow [UMS_MEMORY_BANK_CONTRACT](../shared/UMS_MEMORY_BANK_CONTRACT.md) for MB_ROOT resolution, the proposal pair model, and fail-closed rules.

# Command: mb-jira-update

**Action:** Extract implementation status and deployment instructions from active proposals and publish a summary comment to Jira.
**Precondition:** `- **Jira:** <ID>` must exist in `<CTX_DIR>/context.md` (or be provided in the user prompt).

**Model routing:** If invoked as a delegated/isolated session (e.g. offered by `mb-harvest` from the finishing-a-development-branch harvest gate) and root `context.md` has a `## Model Routing` block, that session runs under `Summarizer Model` per [Model Routing Consumption](../shared/UMS_MEMORY_BANK_CONTRACT.md#model-routing-consumption).

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

### 1. Jira Ticket Check
- Check `<CTX_DIR>/context.md` for `- **Jira:** <ID>` (excluding empty, `(no ticket)`, and legacy `(bez tiketu)` variants).
- If missing, check the user prompt using regex `[A-Z]{2,10}-\d+`. 
- If no valid Jira ID is found, STOP and ask the user to provide the Ticket ID.
- Do NOT proceed without a valid Ticket ID.

### 2. Information Extraction
- Read the content of `<CTX_DIR>/context.md`.
- Prefer data from the active proposal pair (design + plan) resolved from the `Proposal` slug in root `context.md` when active work exists.
- If the proposal was already finalized and archived, read the most relevant completed proposal or finalization handoff from `<PLAN_MB>/proposals/completed/proposal_*.md` (the glob matches both pair halves — strip `-design` and group by slug).
- Do not fail only because the proposal is no longer active when a completed proposal/finalization handoff is available.
- Extract the following information:
  - **Summary of changes:** What was implemented or modified.
  - **Current status:** Whether the implementation is complete, in progress, or aborted.
  - **Verification:** A short outline of tests run and any known risks or issues.
  - **Deployment instructions:** Technical notes for the implementation team, including configuration and network requirements for customer deployment.
  - **Implementation team notes:** Explicitly list impacted configuration, database or script changes, and affected modules or files. If the file list is large or repetitive, collapse it into a module-level link so the Jira comment stays readable.

### 3. Invocation Context
- `mb-jira-update` is typically offered by `mb-harvest` (from the finishing-a-development-branch harvest gate) after a successful harvest, or invoked standalone by the user.
- Any local commit created during SHA stabilization (step 6) requires explicit user confirmation.

### 4. Build Referenced File Set (Priority Order)
- Build list of link targets in this order:
  1. Changed deployment-relevant configuration files (typically `scripts/config.json` and other changed config files).
  2. Changed stable Memory Bank docs (`architecture.md`, `tech.md`, `brief.md`/`product.md`, the active proposal pair `proposal_<slug>-design.md` / `proposal_<slug>.md`).
  3. `context.md` only as a supplementary source, because it is unstable.
- Keep only paths that exist and are inside the same git repository as `MB_ROOT`.
- If the resulting file set is large, noisy, or spans many files from the same area, replace the file list with a single module-level link (the smallest meaningful directory that contains the touched files) instead of enumerating every file.
- Prefer a module link plus a short note about the most relevant files over a long file-by-file inventory.

### 5. Git Preconditions (FAIL-CLOSED)
- Verify git is available (`git --version`). If unavailable: **STOP** (fail-closed, do not publish).
- Resolve repository root (`git rev-parse --show-toplevel`). If fails: **STOP**.
- Resolve current HEAD SHA (`git rev-parse HEAD`). If fails or empty: **STOP**.
- Determine whether referenced files are committed in HEAD:
  - `git diff --name-only HEAD -- <referenced-files>`
  - Empty result => all referenced files are committed.

### 6. Stabilize SHA for Referenced Files Only
- If all referenced files are already committed:
  - use SHA from `git rev-parse HEAD`.
- If there are uncommitted referenced files:
  - ask for explicit user confirmation before creating a local commit that stages only the referenced files; without confirmation => **STOP**.
  - after the confirmed commit, refresh SHA via `git rev-parse HEAD`.
- Never commit unrelated repository files.

### 7. Bitbucket Link Format
- Generate commit-first URLs only:
  - `https://bitbucket.org/workspace/repo/src/<commit-sha>/<relative-path>`
  - where `<commit-sha>` is stable SHA from step 5/6 and `<relative-path>` is repo-relative path.
- Branch fallback is disabled by default.
- Only explicit user override may enable branch fallback; without explicit override stay fail-closed.

### 8. Publish to Jira
- First compose the Jira comment body in Czech as a brief, professional implementation note for the delivery team.
- Use this structure:
  - **Summary:** 1–2 sentences describing what changed.
  - **Affected configurations:** only relevant config files or configuration entries.
  - **Affected databases / scripts:** migrations, update scripts, seeds, or other database-related changes.
  - **Affected modules / files:** list only the important changes; if the list is large or repetitive, replace it with a link to the whole module or directory and mention only the most important files.
  - **Verification and risks:** a short note on what was verified and what remains as risk.
- Include the Bitbucket URLs as standard markdown links.
- Use soft redaction for obvious secrets/tokens before publishing.
- Use the MCP tool `mcp_atlassian-mcp-server_addCommentToJiraIssue` to post the formatted message to the target Jira Ticket ID.

### 9. Completion
> "✅ Jira ticket updated."
> - **Ticket:** <Ticket ID>
> - **Content:** (brief preview of the posted message)

