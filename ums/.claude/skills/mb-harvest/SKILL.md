---
name: mb-harvest
description: Harvest knowledge into Memory Bank documents, archive the design document (delete the implementation plan), reset context.md to IDLE. Invoked by finishing-a-development-branch (UMS Harvest Gate) or standalone when completed work needs harvesting.
license: MIT
metadata:
  author: UMS Project
  version: "2.1"
---

> Follow [UMS_MEMORY_BANK_CONTRACT](../shared/UMS_MEMORY_BANK_CONTRACT.md) —
> especially "Harvest Contract", "Memory Bank Document Set",
> "Document Ownership", "Active Work Item (Design + Plan Pair)" and
> "`context.md` Schema & Writers". This skill is the only IDLE-resetting writer
> of `context.md` besides `mb-abort`.

# Command: mb-harvest

**Action:** Fold implemented knowledge into the affected Memory Bank documents,
archive the design proposal to `completed/` and delete the implementation plan,
reset `context.md` to IDLE.
**Execution:** Autonomous except where it must ask: the playbook gate in step 3
(which experiences to persist), and step 2's fallback when the branch diff is
unavailable (which projects are affected).

**⛔ GIT PROHIBITION:** no `git commit`/`add`/`push` from this skill. When
invoked from the finishing-a-development-branch Harvest Gate, that overlay owns
the commit. When invoked standalone, offer `mb-git-commit` at the end.

**Model selection:** harvesting is summarization work — when delegated to a
subagent, dispatch it on the cheapest capable tier (contract, Dispatch Model
Policy).

---

## Workflow

### 0. Resolve MB_ROOT and gate

- `git rev-parse --show-toplevel` → `MB_ROOT`; failure = hard stop
  (`Git repository not found. Memory Bank requires git.`).
- `<MB_ROOT>/memory-bank/` must exist, else stop with the Root Gate error.
- Scope lock per contract: MB document writes only under `CTX_DIR`, `PLAN_MB`,
  `AFFECTED_MBS`.

### 1. Preconditions (fail-closed)

- Read `<CTX_DIR>/context.md` → `Target MB Pin`, `Work item` slug (legacy
  `Proposal` accepted), `Jira`.
- `PLAN_MB = <MB_ROOT>/<Target MB Pin>` must exist.
- The active proposal must exist in `<PLAN_MB>/proposals/active/` and match
  the slug: the pair `design_<slug>.md` + `plan_<slug>.md` (legacy
  `proposal_<slug>-design.md` + `proposal_<slug>.md`), or a grandfathered
  single plan file. A missing plan half with a present design half is a
  warning (archive what exists); a slug mismatch or empty `active/` is a hard
  stop — report and suggest `mb-state`.

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
actually modified/created files, then update per affected MB, placing every
fact in its owning document (contract, Document Ownership):

- `brief.md` — purpose, value, scope, product risks, state; only when those
  changed
- `architecture.md` — components, responsibilities, relations, patterns,
  diagrams, cross-project links
- `tech.md` — stack, versions, dependencies, configuration, build and
  deployment notes
- `playbook.md` — NOT updated here; it changes only through the playbook gate
  below

When a fact sits in the wrong document, MOVE it: write into the target first,
then delete from the source, and name the move in the final report.

Legacy shape: when `product.md` still exists, read it as context — do NOT write
into it. A fact that belongs in `brief.md` goes to `brief.md`; converting the
MB is `mb-migrate-docs`' job, not a side effect of this harvest.

Style rules (contract, Harvest Contract §3): present tense, fold facts into
existing sections, no duplication, **no changelog sections** ("Nedávné změny",
"Recent Changes", "Historie změn", …), describe the new state instead of
narrating removals. History lives in `proposals/completed/` and git.

Continue with remaining affected MBs if one update fails; collect failures for
the final report. All harvested content is Czech.

**Staleness sweep (cheap, MANDATORY):** for each affected MB, grep ALL its
`memory-bank/*.md` documents (not just architecture/tech) for the key symbols,
element ids and variable names touched by the branch diff. Every hit gets one
of three verdicts:

1. **Superseded** — the passage describes a state that no longer holds → fold
   it to current state.
2. **Existing home** — the passage is where this fact already lives → do NOT
   write a second copy elsewhere; update it in place.
3. **Wrong home** — the fact sits in a document that does not own it
   (contract, Document Ownership) → move it, target first.

One pass therefore catches both staleness (a walkthrough still describing
pre-refactor names) and duplication (the same fact drifting into two
documents).

**Playbook gate (a non-autonomous step):** read
`<MB_ROOT>/.superpowers/playbook-candidates.md`.

- Missing, empty, or carrying a foreign work-item slug → skip silently, no
  question.
- Otherwise present ALL candidates to the user in ONE Czech list: for each, the
  proposed procedure and its evidence (`Tried` / `Happened`). A candidate with
  `Corrects` is shown NEXT TO the existing `playbook.md` entry it contradicts,
  with three choices: replace / keep both / drop.
- Write only what the user approved, translated into Czech, into
  `playbook.md` of the target MB — or of the MB named by the candidate's
  `Target MB` field. Create `playbook.md` when it does not exist; write into
  `tasks.md` instead when that is the MB's legacy shape (contract, Memory Bank
  Document Set).
- Keep a persisted candidate's evidence as a one-line `Proč:`.
- Report the number of candidates the user did not approve. They vanish with
  the scratch file — do not re-ask.

### 4. Archive the design, delete the plan

Move the design half (`design_<slug>.md`, legacy `proposal_<slug>-design.md`)
from `<PLAN_MB>/proposals/active/` to `<PLAN_MB>/proposals/completed/`,
unchanged (durable spec record), and **delete** the plan half (`plan_<slug>.md`,
legacy `proposal_<slug>.md`) from `active/` — after
implementation its task steps are spent; code, git history and the harvested
current-state MB docs carry the outcome. (No git here — the file removal is
recorded by the harvest commit owned by the finishing overlay / `mb-git-commit`.)
If there is no design half (grandfathered single plan), archive that plan to
`completed/` instead of deleting it, so a record remains. Never touch proposals
of other Memory Banks.

Note: after archiving the last file, the now-empty `active/` directory
disappears from the working tree (git does not track empty directories; the
repo has no `.gitkeep` convention). This is expected — discovery globs tolerate
it and `mb-init`/the next brainstorming recreate it on demand.

### 5. Reset context.md (conditional)

**Only if every affected MB update succeeded**, overwrite
`<CTX_DIR>/context.md` with the IDLE baseline per the contract schema:
`## Active Work` → `(No active work - IDLE phase)` + keep the `- **Jira:** …`
line of the finished work item. On partial failure, leave `context.md`
unchanged and report which MBs failed.

### 6. Announce (Czech)

> „✅ Práce sklizena do Memory Bank."
> - Cílová MB: `<PLAN_MB>/`, aktualizované dokumenty: …
> - Archivováno (jen design): `proposals/completed/design_<slug>.md`; implementační plán `plan_<slug>.md` smazán (u legacy práce původní proposal_ názvy)
> - Případné neúspěchy: …
> - Přesuny faktů mezi dokumenty: … (nebo „žádné")
> - Playbook: zapsáno <N> zkušeností do `<MB>/<playbook.md nebo tasks.md dle podoby MB>`, neschváleno <M>
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
