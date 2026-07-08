---
name: mb-harvest
description: Harvest knowledge into Memory Bank documents, archive the active proposal pair, reset context.md to IDLE. Invoked by finishing-a-development-branch (UMS Harvest Gate) or standalone when completed work needs harvesting.
license: MIT
metadata:
  author: UMS Project
  version: "2.0"
---

> Follow [UMS_MEMORY_BANK_CONTRACT](../shared/UMS_MEMORY_BANK_CONTRACT.md) —
> especially "Harvest Contract", "Active Proposal Pair" and "`context.md`
> Schema & Writers". This skill is the only IDLE-resetting writer of
> `context.md` besides `mb-abort`.

# Command: mb-harvest

**Action:** Fold implemented knowledge into the affected Memory Bank documents,
archive the active proposal pair to `completed/`, reset `context.md` to IDLE.
**Execution:** Autonomous — no confirmation.

**⛔ GIT PROHIBITION:** no `git commit`/`add`/`push` from this skill. When
invoked from the finishing-a-development-branch Harvest Gate, that overlay owns
the commit. When invoked standalone, offer `mb-git-commit` at the end.

**Model routing:** when harvesting is delegated to a subagent, that dispatch
runs under **Summarizer Model** per the contract's Model Routing Consumption.

---

## Workflow

### 0. Resolve MB_ROOT and gate

- `git rev-parse --show-toplevel` → `MB_ROOT`; failure = hard stop
  (`Git repository not found. Memory Bank requires git.`).
- `<MB_ROOT>/memory-bank/` must exist, else stop with the Root Gate error.
- Scope lock per contract: MB document writes only under `CTX_DIR`, `PLAN_MB`,
  `AFFECTED_MBS`.

### 1. Preconditions (fail-closed)

- Read `<CTX_DIR>/context.md` → `Target MB Pin`, `Proposal` slug, `Jira`.
- `PLAN_MB = <MB_ROOT>/<Target MB Pin>` must exist.
- The active proposal must exist in `<PLAN_MB>/proposals/active/` and match
  the slug: the pair `proposal_<slug>-design.md` + `proposal_<slug>.md`, or a
  grandfathered single `proposal_<slug>.md`. A missing plan half with a
  present design half is a warning (archive what exists); a slug mismatch or
  empty `active/` is a hard stop — report and suggest `mb-state`.

### 2. Derive affected MBs

```bash
git diff --name-only $(git merge-base <base-branch> HEAD)..HEAD
```

Map each changed path to its nearest owning `memory-bank/` directory
(walk up from the file; a project MB owns the paths beside it). The result is
`AFFECTED_MBS` (always includes `PLAN_MB` when its project code changed).
If the diff is unavailable (no base branch, detached state), ask the user to
name the affected projects.

### 3. Harvest (current-state style — MANDATORY)

Code is the source of truth; the proposal pair is a navigation guide. Read the
actually modified/created files, then update per affected MB:

- `architecture.md` — new components/services, patterns, diagrams,
  cross-project links
- `tech.md` — dependencies, version changes, configuration, build/deploy notes
- `brief.md` / `product.md` — only if core features or UX changed

Style rules (contract, Harvest Contract §3): present tense, fold facts into
existing sections, no duplication, **no changelog sections** ("Nedávné změny",
"Recent Changes", "Historie změn", …), describe the new state instead of
narrating removals. History lives in `proposals/completed/` and git.

Continue with remaining affected MBs if one update fails; collect failures for
the final report. All harvested content is Czech.

### 4. Archive the pair

Move `proposal_<slug>-design.md` and `proposal_<slug>.md` from
`<PLAN_MB>/proposals/active/` to `<PLAN_MB>/proposals/completed/`, unchanged
(historical record). Never touch proposals of other Memory Banks.

### 5. Reset context.md (conditional)

**Only if every affected MB update succeeded**, overwrite
`<CTX_DIR>/context.md` with the IDLE baseline per the contract schema:
`## Active Work` → `(No active work - IDLE phase)` + keep the `- **Jira:** …`
line of the finished work item; preserve the whole `## Model Routing` block
exactly. On partial failure, leave `context.md` unchanged and report which MBs
failed.

### 6. Announce (Czech)

> „✅ Práce sklizena do Memory Bank."
> - Cílová MB: `<PLAN_MB>/`, aktualizované dokumenty: …
> - Archivováno: `proposals/completed/proposal_<slug>*.md`
> - Případné neúspěchy: …
>
> 💡 Pokud je navázán Jira tiket, nabídni `mb-jira-update`.
> 💡 Při samostatném vyvolání (mimo finishing) nabídni `mb-git-commit`.

---

## Linking Rules

1. Relative paths only, never absolute or repo-root-fixed.
2. No line numbers in links.
3. Descriptive link text (`[ServiceName.Method()](../path/Service.cs)`).
4. Cross-project links navigate up to root and down to the target
   `memory-bank/` directory (with trailing slash).

## Diagram Rules

1. Mermaid first; ASCII art only as a last resort.
2. Quote labels containing brackets; keep labels free of Markdown formatting.
