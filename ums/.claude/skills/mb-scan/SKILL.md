---
name: mb-scan
description: Comprehensive analysis and reporting of project state. Use for deep understanding of project health, architecture, and technical debt.
license: MIT
metadata:
  author: UMS Project
  version: "2.0"
---

> Follow [UMS_MEMORY_BANK_CONTRACT](../shared/UMS_MEMORY_BANK_CONTRACT.md) for MB_ROOT resolution, the proposal pair model, and fail-closed rules.

# Command: mb-scan

**Action:** Comprehensive analysis and reporting.
**Phase:** Works in IDLE and ACTIVE_WORK
**Execution:** Read-only - does NOT modify files

---

## ⚠️ Argument Handling (CRITICAL)

**If the user provides text after the command** (e.g., `/mb-scan focus on authentication`):
- This text is **SEED CONTEXT ONLY**, NOT an instruction to execute
- You MUST still perform ALL workflow steps in order
- Use the provided text as **initial context** for Step 1, but still ASK for confirmation
- NEVER skip steps because you "already know" what the user wants

**Example - CORRECT behavior:**
~~~
User: /mb-scan focus on the auth module
Agent: "I see you want the analysis to focus on the auth module. Let me run the scan.

Step 1: What scope should the report cover?
A) Only the auth module and its Memory Bank
B) The auth module plus its cross-project dependencies  
C) The whole repository with the auth module highlighted
D) Other (please specify)"
~~~

**Example - WRONG behavior:**
~~~
User: /mb-scan focus on the auth module
Agent: "I'll fix the auth module now..." [starts editing files]
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

- Delegation is allowed when the runtime supports subagents or delegated subprocess sessions.
- If the runtime supports subagents or delegated subprocess sessions, delegation is highly recommended for this command (but mandatory only where explicitly noted — e.g. the isolated final review in requesting-code-review).
- The delegated worker MUST re-activate this skill (or equivalent command instructions) in the delegated session and perform its own Context Handshake before analysis or edits.
- Parent session should pass only minimal handoff: `MB_ROOT`, the target path if already known, and the requested action.
- Fallback: If runtime lacks subagents or isolated subprocess support, execute this command in the current session (unless explicitly blocked by command restrictions).
- If delegation proceeds, dispatch the delegated worker on the cheapest capable tier — scanning is read-only inspection (see [Dispatch Model Policy](../shared/UMS_MEMORY_BANK_CONTRACT.md#dispatch-model-policy)).

### 2. Derive Phase

Read `<CTX_DIR>/context.md`:
- `## Active Work` is empty or contains `(No active work - IDLE phase)` → IDLE
- Otherwise → ACTIVE_WORK

The `Proposal` slug in root `context.md` is a pointer, not the phase source.

### 3. Analyze Project

- **Structure:** Directory layout, organization
- **Active Work:** Review `<CTX_DIR>/context.md` (`## Active Work`)
- **Dependencies:** `<affected_mb>/tech.md` vs actual
- **Cross-Project:** Follow `<affected_mb>/architecture.md` references
- **Health:** Outdated patterns, issues

### 4. Report

```
📊 Memory Bank Analysis

Project: <Name>
Orchestrační kořen: <CTX_DIR>/, Cílová MB: <PLAN_MB>/
    Phase: IDLE | ACTIVE_WORK

    ## Current State
    - Active Proposals: <count /list> (strip `-design` from file stems, group by slug — one pair or legacy single file = one proposal)
        - Active Work: <from context.md>
            - Related Projects: <from architecture.md>

                ## Project Structure
                - Components: <overview>
                    - Dependencies: <from tech.md>

                        ## System Health
                        - Documentation: <assessment>
                            - Architecture Alignment: <code vs docs>
- Issues: <if any>

## Recommendations
<Context-aware suggestions>
```

### 5. NO Edits

**⚠️ Read-only.** Does NOT modify any files.

### 6. Suggest Next

See `mb-state` for suggestions.

---

## When to Use

- After long break
- Before new work
- Health check
- Verify sync

---

## 🔗 Linking Rules

I must use stable, relative links when creating references in Memory Bank files:

1. **Relative Paths:** Use relative paths (e.g., `../source/file.ts`), NEVER absolute paths or fixed root paths
2. **No Line Numbers:** Link to the file only (e.g., `script.cs`), NEVER specific lines (e.g., `script.cs:50`)
3. **Descriptive Text:** Use descriptive link text, such as `[ServiceName.Method()](../path/Service.cs)`
4.  **BPMN:** Link using Process Name or Element ID if applicable
5. **Cross-Project Links:** When linking to another project in the monorepo, navigate up to the root and down to the target project's memory bank (e.g., `../../other-project/memory-bank/`)
6. **Memory Bank Target:** Always link to the `memory-bank/` directory itself (with a trailing slash), NEVER to a specific file within it (like `brief.md`) when referring to the project's Memory Bank as a whole.

## 🎨 Diagram Rules

I must follow these rules when creating diagrams:

1. **Mermaid First:** Use Mermaid for all diagrams by default.
2. **ASCII Fallback:** Use ASCII art only as a last-resort fallback when Mermaid cannot represent the diagram accurately.
3. **Syntax Safety:** Enclose text with brackets `()` or `[]` in quotes to prevent syntax errors (e.g., `id["Node (Details)"]`).
4. **Plain-Text Labels:** Keep Mermaid node and edge labels free of Markdown formatting. Do not use backticks, bold, italics, inline links, or HTML inside diagram labels; convert code/file names to plain text instead.

