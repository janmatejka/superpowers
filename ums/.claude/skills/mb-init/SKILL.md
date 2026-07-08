---
name: mb-init
description: Initialize Memory Bank structure in the current project directory. Use when setting up a new project with Memory Bank workflow or when no memory-bank/ directory exists.
license: MIT
metadata:
  author: UMS Project
  version: "2.0"
---

> Follow [UMS_MEMORY_BANK_CONTRACT](../shared/UMS_MEMORY_BANK_CONTRACT.md) for MB_ROOT resolution, the proposal pair model, and fail-closed rules.

# Command: mb-init

**Action:** Initialize the root Memory Bank structure.
**Trigger:** Execute in repository scope when the target `memory-bank/` (orchestration root or project MB) is missing.
**Phase:** Creates the transition from no Memory Bank to IDLE

---

## ⚠️ CRITICAL

Initialization must be fail-closed and root-scoped. `mb-init` creates the standard `memory-bank/` structure in two modes: **orchestration root** (`CTX_DIR` = `<MB_ROOT>/memory-bank/`, derived from the git root) and **project MB** (`PLAN_MB` = target path provided by the user). In either mode, never create `context.md` — it is created later by the superpowers workflow (Target-MB Discovery & Pinning during brainstorming).

---

## Workflow

### 0. Resolve MB_ROOT (MANDATORY)

Follow the canonical `UMS_MEMORY_BANK_CONTRACT` from the installed skills root to resolve `MB_ROOT`.

Resolve `MB_ROOT` with exactly one discovery step:

```bash
git rev-parse --show-toplevel
```

Rules:

- Use the git root as the only MB root model.
- If `git` is missing or the command exits non-zero, stop immediately with: `Git repository not found. Memory Bank requires git.`
- On success, set `MB_ROOT` to the returned git root and `CTX_DIR` to `<MB_ROOT>/memory-bank/`.
- Choose the init mode: **orchestration root** — the target is `CTX_DIR` itself (`<MB_ROOT>/memory-bank/`), used when setting up the repo's orchestration root; or **project MB** — ask the user for the target project path and set `PLAN_MB` to the user-provided path. Project-MB mode does not touch `CTX_DIR`.
- If the target `memory-bank/` already exists, stop instead of overwriting it.

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

### 1. Analyze the project to seed the Memory Bank

> **Scope contract:** This step performs **project analysis** (reading source code, configs, and build files), not Memory Bank operations. The Write Safety Gate above applies to MB writes (step 2, inside `memory-bank/`), not to project reads during analysis. For cross-project discovery, lightweight filesystem existence checks (checking for sibling `memory-bank/` directories) are permitted — sibling projects are neither parent nor child Memory Banks.

Use the following phased exploration protocol. Execute phases in order. Each phase has a **goal**, **target output document**, **concrete commands**, a **completion criterion**, and a **fallback** for missing data. Write each phase's findings to the target document before starting the next phase.

#### Phase 0: Ecosystem Detection → `tech.md`
- **Goal:** Determine the project ecosystem (C#/.NET, Node.js, Python, Go, Rust, or other).
- **Detection signals:**
  - `.csproj` or `.sln` files → C#/.NET
  - `package.json` → Node.js
  - `requirements.txt` or `pyproject.toml` → Python
  - `go.mod` → Go
  - `Cargo.toml` → Rust
- **Output:** Write the detected ecosystem to `tech.md` as the first line (e.g., `Ecosystem: C#/.NET`).
- **Completion:** At least one known ecosystem signal found OR `[K DOPLNĚNÍ]` recorded.
- **Fallback:** Write `[K DOPLNĚNÍ]` + recommend `mb-scan` for manual follow-up.
- **Important:** The current version of this protocol targets C#/.NET ecosystems. For other ecosystems, phases 2–5 produce `[K DOPLNĚNÍ]` markers; the agent presents a summary with `mb-scan` as the recommended next step.

#### Phase 1: Repository Structure Discovery → `brief.md`
- **Goal:** Map directory structure and identify key folders and files.
- **Commands:**
  - `fd -t d -d 3` — directory tree to 3 levels
  - `ls` — root-level files
  - `rg -l "README|CONTRIBUTING|LICENSE"` — project docs
- **Output in `brief.md`:** Project purpose (from README, project name, or directory context), key directories and their roles, project name (from directory name, `.csproj`, or `package.json`).
- **Completion:** Brief includes purpose statement and directory overview.
- **Fallback:** `[K DOPLNĚNÍ]` with directory listing summary.

#### Phase 2: Technology Stack Detection → `tech.md`
- **Goal:** Identify runtime, framework, build tools, and versions.
- **For .NET:** `rg "TargetFramework"` (framework version), `rg "PackageReference"` (NuGet deps), check for `Directory.Build.props`, `global.json`.
- **Output in `tech.md`:** Stack section with runtime version, framework, and key packages.
- **Completion:** Runtime and framework identified.
- **Fallback:** `[K DOPLNĚNÍ]` + available tool output.

#### Phase 3: Build & Dependency Analysis → `tech.md`
- **Goal:** Identify build system, test frameworks, and dependencies.
- **For .NET:** `fd -e sln` (solution files), `rg "<ProjectReference"` (project refs), `rg "<PackageReference Include"` (packages), `rg "xunit|nunit|MSTest|Microsoft.NET.Test.Sdk"` (test framework).
- **Output in `tech.md`:** Dependencies section with versions.
- **Completion:** Build tools and major dependencies listed.
- **Fallback:** `[K DOPLNĚNÍ]` + partial findings.

#### Phase 4: Entry Point & Runtime Discovery → `architecture.md`
- **Goal:** Locate application entry points, configuration, and startup sequence.
- **For .NET:** `rg "static void Main"` or `rg "Program\\.cs"` (entry points), `rg "Startup"` (ASP.NET), `fd appsettings` (config), `rg "app\\.Run|app\\.Listen|WebApplication"` (host).
- **Output in `architecture.md`:** Entry points, configuration sources, startup flow description.
- **Completion:** Entry point located.
- **Fallback:** `[K DOPLNĚNÍ]` with what was found.

#### Phase 5: Architectural Pattern Recognition → `architecture.md`
- **Goal:** Detect layers, separation of concerns, and design patterns.
- **For .NET detection signals:**
  - `Controllers/`, `Views/`, `Models/` directories → MVC pattern
  - `*.Core/`, `*.Infrastructure/`, `*.Web/` projects → Layered architecture
  - `*.Domain/`, `*.Application/` projects → DDD/Onion architecture
  - `rg -l "Controller$"` — API controllers
  - `rg ": DbContext"` — Entity Framework
  - `rg "Repository"` — Repository pattern
  - `rg "I[A-Z]\w*Service"` — Service interfaces
- **Output in `architecture.md`:** Detected pattern + **Mermaid component diagram** with plain-text component labels and component relationships.
- **Completion:** Architecture pattern identified and Mermaid diagram created.
- **Diagram note:** Mermaid node labels must stay plain text; strip Markdown formatting (especially backticks) before writing the diagram.
- **Fallback:** `[K DOPLNĚNÍ]` + directory-based component listing.

#### Phase 6: Monorepo Dependency Discovery → `architecture.md` (cross-references)
- **Goal:** Detect references to other projects within the monorepo.
- **Contract boundary:** Reading `.csproj`/`.sln` files for dependency detection is project analysis, not MB operations. Checking for sibling `memory-bank/` directories is a lightweight filesystem existence check — explicitly permitted because sibling projects are neither parent nor child Memory Banks.
- **For .NET projects in monorepo:**
  1. Find all `.csproj` and `.sln` files in the project
  2. Extract `<ProjectReference>` and `<Reference>` elements
  3. For each reference, check whether the target path contains `memory-bank/`
  4. If sibling MB exists: record a relative link in `architecture.md`
  5. If MB does not exist: mark as `*(future MB)*` with comment
- **Completion:** All project references checked for MB presence.
- **Fallback:** `[K DOPLNĚNÍ]` — no project references found or only external packages.

#### Phase 7: Cross-Project Linking → `architecture.md` (links)
- **Goal:** Create stable relative links to existing Memory Banks of dependent projects.
- **Linking Rules:**
  - Relative paths from `memory-bank/` to target: `../../OtherProject/memory-bank/`
  - Link to the whole MB directory (with trailing slash), not individual files
  - Descriptive link text: `[ProjectName](../../ProjectName/memory-bank/)`
  - No line numbers in links
  - Mermaid diagrams with escaped bracket text per Diagram Rules
- **Completion:** All discovered sibling MBs have valid relative links in `architecture.md`.
- **Fallback:** If no sibling MBs exist, state "No cross-project dependencies detected."

### Analysis Completion Checklist

Before moving to step 2, verify:
- [ ] `tech.md` has ecosystem, technology stack, and dependencies (or `[K DOPLNĚNÍ]`)
- [ ] `brief.md` has project purpose and key directories (or `[K DOPLNĚNÍ]`)
- [ ] `architecture.md` has entry point, architectural pattern, Mermaid diagram (or `[K DOPLNĚNÍ]`)
- [ ] Cross-project links in `architecture.md` use valid relative paths per Linking Rules
- [ ] Unknown/missing sections contain `[K DOPLNĚNÍ]` markers (fail-closed), not guesses

### 2. Create the Memory Bank structure

Create the target `memory-bank/` (`<CTX_DIR>/` in orchestration-root mode, `<PLAN_MB>/` in project-MB mode) with:

- `brief.md`
- `product.md`
- `architecture.md`
- `tech.md`
- `proposals/active/`
- `proposals/completed/`
- `proposals/abandoned/`

Do **not** create `context.md`.

### 3. Review output

Present a short summary of the project role, technology stack, and the new Memory Bank root.

### 4. Announce

Always include:

- `Cílová MB: <PLAN_MB>/` (v režimu orchestračního kořene: `<CTX_DIR>/`)
- `Reason: git-root discovery`
- `Updated files: brief.md, product.md, architecture.md, tech.md, proposals/active/, proposals/completed/, proposals/abandoned/`

### 5. Next step

After initialization:

- Phase: IDLE
- Suggest: `mb-state`, `mb-scan`, or start the superpowers workflow (describe what to build → brainstorming)
- The next planning step is the superpowers workflow: `brainstorming` runs Target-MB Discovery & Pinning, which creates the root `context.md`.
- Root `context.md` is created during the first brainstorming run, never by `mb-init`.

---

**Language:** Memory Bank documents MUST be in Czech.

---

## 🔗 Linking Rules

I must use stable, relative links when creating references in Memory Bank files:

1. **Relative Paths:** Use relative paths (e.g., `../source/file.ts`), NEVER absolute paths or fixed root paths
2. **No Line Numbers:** Link to the file only (e.g., `script.cs`), NEVER specific lines (e.g., `script.cs:50`)
3. **Descriptive Text:** Use descriptive link text, such as `[ServiceName.Method()](../path/Service.cs)`
4.  **BPMN:** Link using Process Name or Element ID if applicable
5. **Cross-Project Links:** When linking to another project in the monorepo, navigate up to the root and down to the target project's memory bank (e.g., `../../other-project/memory-bank/`)
6. **Memory Bank Target:** Always link to the `memory-bank/` directory itself (with a trailing slash), NEVER to a specific file within it (like `brief.md`) when referring to the project's Memory Bank as a whole.
   - **Rationale:** A directory target is the best entry point for navigating the MB tree — for both AI agents and humans browsing the docs. The agent derives the specific doc (`brief.md`, `architecture.md`, …) from the known MB convention, so pointing below the `memory-bank/` directory adds no value. Crucially, a `memory-bank/` target is stable and validatable and fails loudly when wrong (a missing directory), whereas a project-directory target silently "exists" even when no MB is present and cannot be validated as pointing to curated knowledge.

## 🎨 Diagram Rules

I must follow these rules when creating diagrams:

1. **Mermaid First:** Use Mermaid for all diagrams by default.
2. **ASCII Fallback:** Use ASCII art only as a last-resort fallback when Mermaid cannot represent the diagram accurately.
3. **Syntax Safety:** Enclose text with brackets `()` or `[]` in quotes to prevent syntax errors (e.g., `id["Node (Details)"]`).
4. **Plain-Text Labels:** Keep Mermaid node and edge labels free of Markdown formatting. Do not use backticks, bold, italics, inline links, or HTML inside diagram labels; convert code/file names to plain text instead.

