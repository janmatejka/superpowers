---
name: mb-init
description: Initialize Memory Bank structure in the current project directory, including the detected per-repository configuration (ums-repo.json). Use when setting up a new project with Memory Bank workflow, when no memory-bank/ directory exists, or when the repository configuration needs re-detecting against the current topology (obnov ums-repo.json, změnily se větve/projekty).
license: MIT
metadata:
  author: UMS Project
  version: "2.1"
---

> Follow [UMS_MEMORY_BANK_CONTRACT](../shared/UMS_MEMORY_BANK_CONTRACT.md) for MB_ROOT resolution, the work item (design + plan pair) model, and fail-closed rules.

# Command: mb-init

**Action:** Initialize the root Memory Bank structure.
**Trigger:** Execute in repository scope when the target `memory-bank/` (orchestration root or project MB) is missing.
**Phase:** Creates the transition from no Memory Bank to IDLE

---

## ⚠️ CRITICAL

Initialization must be fail-closed and root-scoped. `mb-init` creates the standard `memory-bank/` structure in two modes: **orchestration root** (`CTX_DIR` = `<MB_ROOT>/memory-bank/`, derived from the git root) and **project MB** (`PLAN_MB` = target path provided by the user). In either mode, never create `context.md` — it is created later by the superpowers workflow (Target-MB Discovery & Pinning during brainstorming). Orchestration-root mode additionally detects and writes `<CTX_DIR>/ums-repo.json` (step 3); the same detection serves the refresh mode over an existing configuration.

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
- If the target `memory-bank/` already exists, stop instead of overwriting it. **One exemption:** the configuration refresh mode (see Refresh mode of the repository configuration below), which is invoked deliberately over an initialized Memory Bank and touches `ums-repo.json` only — never a document, never a proposal.

### Write Safety Gate (MANDATORY)

Before any Memory Bank write operation:
1. List target files.
2. Verify all target files are under `<CTX_DIR>/, <PLAN_MB>/, or <AFFECTED_MBS>/`.
3. If any target is outside `<CTX_DIR>/, <PLAN_MB>/, or <AFFECTED_MBS>/` and user did not explicitly request cross-project sync, STOP and ask user.

Where:
- `CTX_DIR` = orchestration state (root `context.md`)
- `PLAN_MB` = the Memory Bank of the active work item
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
- [ ] `brief.md` has project purpose, key directories, who it serves and what value it gives (or `[K DOPLNĚNÍ]`)
- [ ] `architecture.md` has entry point, architectural pattern, Mermaid diagram (or `[K DOPLNĚNÍ]`)
- [ ] Cross-project links in `architecture.md` use valid relative paths per Linking Rules
- [ ] Unknown/missing sections contain `[K DOPLNĚNÍ]` markers (fail-closed), not guesses

### 2. Create the Memory Bank structure

Create the target `memory-bank/` (`<CTX_DIR>/` in orchestration-root mode, `<PLAN_MB>/` in project-MB mode) with:

- `brief.md`
- `architecture.md`
- `tech.md`
- `playbook.md` — **only when Phase 2/3 discovered concrete build or test
  commands.** Put the commands here and the versions and stack into `tech.md`
  (contract, Document Ownership). Never create it empty: an empty stub is
  exactly how the former `tasks.md` ended up used in one MB out of eight.
- `proposals/next/`
- `proposals/active/`
- `proposals/completed/`
- `proposals/abandoned/`

Do **not** create `context.md`.

### 3. Detect the repository configuration (orchestration root only)

Write `<CTX_DIR>/ums-repo.json` — the per-repository values the layer refuses to
carry in its own body. Only in **orchestration-root mode**: the configuration is
per repository, and `CTX_DIR` is the one location guaranteed to exist and to be
tracked. Project-MB mode never writes it. The keys, their consumers and the
degradation rules are in the contract, section named Repository Configuration;
the reader is [Get-UmsRepoConfig.ps1](../shared/scripts/Get-UmsRepoConfig.ps1),
and what is written here must be exactly what it reads.

Every value comes from **this** repository's topology. Never carry one over from
another repository and never invent one: what is not detected is filled from the
built-in default and **reported as a default**, not as a finding.

All detection reads **tracked** files and refs (`git ls-files`,
`git for-each-ref`), never a filesystem walk — an untracked build file does not
travel with a clone, so it cannot justify a shared configuration value.

#### `baseRef` — a fully-qualified remote-tracking ref

```bash
git symbolic-ref --quiet refs/remotes/origin/HEAD
```

This prints a **full ref path** (`refs/remotes/origin/main`), which is not the
value to write. Strip the prefix:

```bash
git symbolic-ref --quiet refs/remotes/origin/HEAD | sed 's#^refs/remotes/##'
```

The result — `origin/main` — is the qualified form the key requires. Writing a
bare branch name (`main`) breaks every consumer that hands the value to git
as-is; `doc-index.ps1` runs `rev-parse --verify` on it directly.

When the symref is absent (non-zero exit, no output — a clone that never had
`origin/HEAD` set), probe in this order and take the first hit:

```bash
for r in origin/develop origin/main origin/master; do
  git rev-parse --verify --quiet "refs/remotes/$r" >/dev/null && echo "$r" && break
done
```

When nothing resolves, write `origin/develop` and **say that it is the
fallback**, not a detected value.

Never write `<baseBranch>` into the file. It is a **derivation** of `baseRef`
(the ref minus its remote prefix) with exactly one use, a push destination — it
is not a key, and the loader does not read it.

**Two signals, and a question when they disagree.** `origin/HEAD` reports the
**remote's** default branch, which is not always the branch work integrates into:
a fork that keeps its upstream's default branch as a read-only mirror and
integrates into a long-lived branch of its own has `origin/HEAD` naming the
mirror. So read the second signal too — the upstream of the branch currently
checked out:

```bash
git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null
```

- **Both resolve and agree** → that is the value. Nothing to ask; the
  approval-free first write applies in full.
- **They disagree** → **ask the user which one is the base**, showing both with
  their provenance (`origin/HEAD` says X, the checked-out branch tracks Y). An
  ambiguous base is precisely where the first-write exception does not reach: the
  exception rests on values being verifiable against the repository, and here the
  repository says two things. Writing the mirror unasked would point base sync,
  `doc-index.ps1` and every merge-base at a read-only branch, and correcting it
  afterwards would need an approval anyway — so ask once, now.
- **Ignore the second signal when the checked-out branch cannot be a base:** its
  name matches the detected `ticketPattern`, or it sits under one of the
  working-branch namespaces found while grouping prefixes below. A ticket
  branch's upstream is itself and would be a worse answer than the mirror.
- **No upstream at all** (a fresh clone, a detached HEAD) → the symref alone
  decides, no question.

Report the chosen value with its provenance on its own line either way.

#### `protectedBranches` — proposals, always confirmed

The built-in four (`develop`, `main`, `master`, `release/*`), plus the branch
behind `baseRef` when it is not already one of them (a repository whose base is
its own long-lived branch must protect that branch), plus detected release
series.

Enumerate remote branches as the hook sees them:

```bash
git for-each-ref --format='%(refname:lstrip=3)' refs/remotes/origin/ | grep -v '^HEAD$'
```

`lstrip=3` drops `refs/remotes/origin`, leaving the plain branch name — the same
shape `pre-push` matches after stripping `refs/heads/`. Do **not** use
`%(refname:short)` here: it keeps the remote in the name (`origin/main`, which
matches nothing in the protected list) and it emits a bare `origin` for the
`origin/HEAD` symref; the `grep -v '^HEAD$'` above is what keeps that entry out.

Group by the first segment and keep prefixes holding more than one branch:

```bash
git for-each-ref --format='%(refname:lstrip=3)' refs/remotes/origin/ | grep -v '^HEAD$' |
  grep '/' | sed 's#/.*##' | sort | uniq -c | sort -rn | awk '$1 > 1'
```

Then look at what each candidate prefix actually holds:

```bash
git for-each-ref --format='%(refname:lstrip=3)' refs/remotes/origin/ | grep '^<prefix>/' | head -5
```

A **release series** has version-like or date-like children (`Branches/5.33`,
`release/5.34`). A prefix whose children carry ticket keys or slugs
(`feature/UMS-1967-…`, `bugfix/…`, `codex/…`) is a **working-branch namespace**
and must not be protected.

**List the candidates and let the user confirm which belong in.** This key is
the exception inside the first-write exception below: it is the only one that
reaches a security boundary, so it is never written on detection alone. Being
wrong hurts in both directions — a release series left out leaves a live shared
branch unprotected, and a `feature/*` let in blocks every legitimate ticket
push.

```
Navržené chráněné větve — potvrď, které patří dovnitř:
  vestavěné:  develop, main, master, release/*
  báze:       develop (z baseRef — už mezi vestavěnými)
  Branches/*  — 5 větví, řada verzí (Branches/5.33, Branches/5.34)      ✅ doporučeno
  feature/*   — 68 větví, pracovní jmenný prostor (feature/UMS-1967-…)  ❌ nedoporučeno
  bugfix/*    — 40 větví, pracovní jmenný prostor (bugfix/UMS-2113-…)   ❌ nedoporučeno
```

#### `ticketPattern`

```bash
git for-each-ref --format='%(refname:lstrip=3)' refs/remotes/origin/ | grep -v '^HEAD$' |
  sed 's#.*/##' | grep -oE '^[A-Z]+-[0-9]+' | sed 's/-[0-9]*$//' | sort | uniq -c | sort -rn
```

`sed 's#.*/##'` keeps the last path segment, so a key nested in a namespace
(`feature/UMS-1967-…`) is still seen. Take the **most frequent** prefix and write
`^<PREFIX>-[0-9]+`. A long tail of single occurrences (one `SKODASMS` beside 188
`UMS`) is noise, not a second pattern — the key holds one value.

No match at all → write the generic `^[A-Z][A-Z0-9]+-[0-9]+` and report it as a
default. This is the normal outcome in a repository whose branches never carry
ticket keys; detection cannot know a project key that appears nowhere in the
topology. If the user names the key during this same run, use it — it is still
the first version.

#### `projectMarkers`

```bash
git ls-files | grep -Ei '\.(sln|csproj|vcxproj)$|(^|/)(package\.json|pom\.xml|build\.gradle(\.kts)?|Cargo\.toml|pyproject\.toml)$'
```

That lists **paths**; the key holds **patterns**, so aggregate the hits to the
kinds present and how many of each:

```bash
git ls-files | grep -Ei '\.(sln|csproj|vcxproj)$|(^|/)(package\.json|pom\.xml|build\.gradle(\.kts)?|Cargo\.toml|pyproject\.toml)$' |
  grep -Eoi '\.(sln|csproj|vcxproj)$|(package\.json|pom\.xml|build\.gradle(\.kts)?|Cargo\.toml|pyproject\.toml)$' |
  sort -f | uniq -ci
```

Each surviving kind becomes one pattern: an **extension** hit becomes `*.<ext>`
(`.csproj` → `*.csproj`), a **whole-filename** hit stays the filename
(`package.json` → `package.json`). The counts do not go into the file — they go
into the report, as the evidence for each pattern.

Write **only the patterns that actually occur**. A pattern for an ecosystem the
repository does not use matches nothing and only misleads the next reader about
what this repository is.

#### `sharedRoots`

Two sources; the union is the proposal.

**(a) Projects referenced from more than one other project.** For .NET/MSVC
trees:

```bash
git ls-files -z '*.csproj' '*.vcxproj' |
  xargs -0 grep -HoE 'Include="[^"]*\.(csproj|vcxproj)"' |
  sed -E 's#^([^:]+):.*[\\/"]([^\\/"]+)\.(csproj|vcxproj)"$#\2\t\1#' |
  sort -u | cut -f1 | uniq -c | sort -rn | awk '$1 > 1'
```

The output is `<count> <referenced project>` — how many **distinct** project
files reference it. The `sort -u` on the (target, referrer) pair comes first so
that a `vcxproj` repeating the same reference once per configuration counts once.
Locate each and roll the path up to its **first or second** segment:

```bash
git ls-files '*/<Name>.csproj' '*/<Name>.vcxproj' '<Name>.csproj' '<Name>.vcxproj'
```

`Common/UmsLib/UmsLib/UmsLib.csproj` → `Common/UmsLib/`. Directories are written
with a trailing slash. The mapping is by project **basename**, so two projects
sharing a basename in different directories collapse into one candidate — a
reason to look at the located path before accepting it, not a reason to skip the
detection.

**(b) Shared build files.**

```bash
git ls-files | grep -Ei '(^|/)(Directory\.Build\.props|Directory\.Packages\.props|Build\.proj|SharedAssemblyInfo[^/]*)$|^[^/]+\.(sln|targets)$'
```

Accept a hit only where the file really sits **above more than one project** — a
root `*.sln`, a root `*.targets`, a `Directory.Build.props` over a project group.
A `SharedAssemblyInfo.cs` that every project keeps in its own `Properties/`
folder is per-project boilerplate despite the name, and sixteen of them are
sixteen private files, not sixteen shared roots.

Source (a) covers .NET/MSVC only. In another ecosystem it yields nothing and
`sharedRoots` stays at whatever (b) and the user contribute — an empty list is
legal and degrades safely (contract, Repository Configuration: verification is
then offered for every incoming diff rather than for none). A directory that is
shared for reasons no build file records cannot be detected at all; it is human
knowledge, added by the user.

#### The write, and what needs approval

Write `<CTX_DIR>/ums-repo.json` with exactly these five keys — `baseRef` and
`ticketPattern` as strings, `protectedBranches`, `projectMarkers` and
`sharedRoots` as arrays of strings. Nothing else: a key the loader does not read
is dead weight, and `<baseBranch>` is not a key.

**The first written version needs no approval.** It is the same exception, for
the same reason, as the first `playbook.md`: there is nothing yet to overwrite,
and every detected value is verifiable against the repository's own build files
and refs — unlike the experience the consult regime exists to protect.
**Every later change does need approval** (contract, Repository Configuration),
and the boundary is exactly that: first write free, every subsequent one
approved. `protectedBranches` is confirmed even in the first write, per above.

Report per key what was **detected** and what was **substituted as a default**:

```
ums-repo.json vytvořen:
  baseRef:           origin/develop (detekováno z origin/HEAD)
  protectedBranches: develop, main, master, release/*, Branches/* (potvrzeno uživatelem)
  ticketPattern:     ^UMS-[0-9]+ (detekováno, 188 z 218 vzdálených větví)
  projectMarkers:    *.sln, *.csproj, *.vcxproj, package.json, pom.xml (detekováno)
  sharedRoots:       Common/UmsLib/, Build.proj (detekováno)
  Další krok: spusť install-git-hooks.ps1 — pre-push čte vygenerovaný seznam, ne tento soubor.
```

### Refresh mode of the repository configuration

Runs over an **existing** `<CTX_DIR>/ums-repo.json`, on deliberate invocation
(the user asks to refresh or verify the configuration). It is the exemption from
the stop-on-existing rule in step 0 and touches that one file only. An
initialized Memory Bank with **no** configuration file is not this mode: there is
nothing to compare against, so the first-write path of step 3 applies unchanged.

1. Detect every key again, exactly as in step 3.
2. Compare against the file and present the difference **per key** — for the two
   scalars as `old → new`, for the three lists split into: detected and present,
   detected and missing from the file, present in the file and not detected.
   A scalar difference carries a **recommendation**, not just the two values, and
   the mirror case of step 3 decides it for `baseRef`: when detection would move
   the base toward the remote's default branch while the file names a different
   long-lived branch, the standing recommendation is to **keep the file's value**
   — that is the read-only-mirror shape, not drift, and the file is the side that
   knows. Say so in the diff; do not present the flip as the obvious answer. The
   two signals of step 3 apply here too: with the checked-out long-lived branch
   tracking exactly what the file says, there is nothing to propose at all.
3. **No difference → write nothing.** Report that the configuration matches the
   topology and stop. Never rewrite the file to reformat or reorder it.
4. A difference is **written only after the user approves it** — the rule for
   later changes is in the contract, section named Repository Configuration.
5. Entries in the file that detection did not find are **not** proposed for
   removal by default. They usually carry knowledge no build file records — a
   shared directory nothing references, a ticket prefix that never reaches a
   branch name. Name them, propose keeping them, and let the user decide.

After `protectedBranches` changes, **`install-git-hooks.ps1` must run again.**
`pre-push` is POSIX `sh` with no JSON parser, so it never reads
`ums-repo.json`: it reads the plain text list the installer generates into
`<git-common-dir>/ums-protected-branches`. Until the installer runs again the
hook enforces the **previous** list — the new value is in the file and not in
force. State this as a required next step in the report, not as a footnote.

### 4. Review output

Present a short summary of the project role, technology stack, and the new Memory Bank root.

### 5. Announce

Always include:

- `Cílová MB: <PLAN_MB>/` (v režimu orchestračního kořene: `<CTX_DIR>/`)
- `Reason: git-root discovery`
- `Updated files: brief.md, architecture.md, tech.md, proposals/next/, proposals/active/, proposals/completed/, proposals/abandoned/` (plus `playbook.md` when concrete commands were found, plus `ums-repo.json` in orchestration-root mode)
- the per-key detected/default report from step 3, and `install-git-hooks.ps1` as the next step whenever `protectedBranches` was written or changed

### 6. Next step

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

