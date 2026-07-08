---
name: mb-model-routing
description: Load available runtime models, choose role defaults, and interactively update Model Routing in root context.
license: MIT
metadata:
  author: UMS Project
  version: "2.0"
---

> Follow [UMS_MEMORY_BANK_CONTRACT](../shared/UMS_MEMORY_BANK_CONTRACT.md) for MB_ROOT resolution, the proposal pair model, and fail-closed rules.

# Command: mb-model-routing

**Action:** Load available runtime models, choose role defaults, and persist routing to root `context.md`.
**Phase:** Works in IDLE and ACTIVE_WORK
**Execution:** Interactive - requires user confirmation

---

## ⚠️ Argument Handling (CRITICAL)

**If the user provides text after the command** (e.g., `/mb-model-routing use premium profile`):
- This text is **SEED CONTEXT ONLY**, NOT an instruction to execute
- You MUST still perform ALL workflow steps in order
- Use the provided text as **initial context** for Step 1, but still ASK for confirmation
- NEVER skip steps because you "already know" what the user wants

**Example - CORRECT behavior:**
~~~
User: /mb-model-routing use premium profile
Agent: "I see you want the premium profile as seed context. Let me start the routing update.

Step 1: Which model profile should apply?
A) economy
B) balanced  
C) premium (your seed context)
D) custom (please specify)"
~~~

**Example - WRONG behavior:**
~~~
User: /mb-model-routing use premium profile
Agent: "I'll set the premium routing now..." [writes context.md without confirmation]
~~~

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

- If `<CTX_DIR>/context.md` is missing, set `PHASE = IDLE` — the file is created by the superpowers workflow (Target-MB Discovery & Pinning during brainstorming); this skill may still persist the `## Model Routing` block (step 6) by creating the file with only that block.
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

### Write Safety Gate (MANDATORY)

Before any Memory Bank write operation:
1. List target files.
2. Verify all target files are under `<CTX_DIR>/, <PLAN_MB>/, or <AFFECTED_MBS>/`.
3. If any target is outside `<CTX_DIR>/, <PLAN_MB>/, or <AFFECTED_MBS>/` and user did not explicitly request cross-project sync, STOP and ask user.

Where:
- `CTX_DIR` = orchestration state (root `context.md`)
- `PLAN_MB` = active proposal Memory Bank
- `AFFECTED_MBS` = harvest/sync targets

Scope lock remains active until command completion.

### 2. Gather Runtime Model Inventory

- Detect available models from the current runtime/provider integration.
- Normalize candidates to canonical identifiers `provider/model-id` when available.
- Sort candidates deterministically before prompting the user.
- If runtime cannot enumerate models, ask the user once to provide the candidate list.
- If no usable list is available, stop fail-closed with a clear reason.

### 3. Read Persistent Defaults from Root Context

- Read existing `## Model Routing` block from root `context.md`.
- Existing values are persistent defaults for this command and MUST survive across sessions.
- For each role (`Orchestrator Model`, `Worker Model`, `Reviewer Model`, `Summarizer Model`):
  - if an existing value is present and available in current inventory, use it as default
  - if value is missing or stale, compute deterministic fallback from profile and budget
- Never silently discard existing values; stale values must be reported before fallback selection.

### 4. Determine Deterministic Fallbacks

Apply profile-aware fallback order without hardcoding vendor pricing:

- `economy`: cheaper stable defaults for worker and summarizer; reviewer may stay stronger when risk requires it.
- `balanced`: default trade-off across all roles.
- `premium`: strongest available defaults for quality-critical runs.
- `custom`: preserve user-provided role mapping unless unavailable.

Fallback policy handling:

- `ask`: stop and ask user to pick replacement model.
- `downgrade`: pick next available fallback and report the downgrade in the completion announcement.
- `stop`: set blocked outcome and do not write partial routing.

### 5. Interactive Role Selection (Czech UI)

- Communication with the user MUST be in Czech.
- Ask role-by-role with a selectable list and include option `Ponechat vychozi hodnotu`.
- Show stale-value warning when persisted default is unavailable.
- Ask for one final confirmation summarizing full routing map before write.

### 6. Persist Routing to Root Context

- Ensure root `context.md` has `## Model Routing` with fields:
  - `Model Profile`
  - `Orchestrator Model`
  - `Worker Model`
  - `Reviewer Model`
  - `Summarizer Model`
  - `Fallback Policy`
  - `Budget Hint`
- Preserve all non-routing sections unchanged; do not add any sections beyond the contract v2 schema (`## Active Work`, `## Model Routing`).
- `mb-model-routing` is the sole owner of the `## Model Routing` block; no other writer may modify it.
- The block persists across IDLE resets: `mb-harvest` and `mb-abort` MUST preserve `## Model Routing` when resetting `## Active Work`; removing it is contract drift.

### Role Consumption (v2 mapping)

Consumers resolve dispatch models from the `## Model Routing` block per the contract's [Model Routing Consumption](../shared/UMS_MEMORY_BANK_CONTRACT.md#model-routing-consumption) section:

- SDD implementer and fix subagents → `Worker Model`
- SDD task reviewers and the final whole-branch reviewer (requesting-code-review) → `Reviewer Model`
- Commit-message / Jira / harvest summarization dispatches → `Summarizer Model`
- The driving session itself → `Orchestrator Model`

### 7. Announce Completion

Always include:

- `Orchestrační kořen: <CTX_DIR>/`
- `Reason: git-root discovery`
- `Updated files: context.md`
- `Routing defaults source: existing context values first, then deterministic fallback`

