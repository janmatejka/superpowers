---
name: mb-doc-index
description: Use when you need to know which Memory Bank documents exist on other branches — before pinning new work (cross-clone collision check), when activating a queued design draft, when feeding the epic graph, or to answer "who is working on what" (kdo na čem pracuje, existuje už návrh, kolize slugů).
license: MIT
metadata:
  author: UMS Project
  version: "1.1"
---

> Follow [UMS_MEMORY_BANK_CONTRACT](../shared/UMS_MEMORY_BANK_CONTRACT.md) —
> especially "Cross-Branch Visibility", "Publication Contract" and
> "Target-MB Discovery & Pinning".

# Command: mb-doc-index

**Action:** Index Memory Bank documents across `origin` branches (pull model) and
report collisions.
**Execution:** Read-only towards git; the only write is the optional `-Json` file.

## Workflow

1. Run the script (Czech table + findings; `-Json` for machine consumers):

```powershell
pwsh <this skill>/scripts/doc-index.ps1 `
  [-RepoPath <repo>] [-BaseRef <ref>] [-SinceDays 30] `
  [-BranchGlob 'origin/feature/*'] [-Jira UMS-1234] [-Slug <slug>] `
  [-Json <path>] [-NoFetch]
```

2. Exit codes: `0` OK · `1` input/script failure · `2` collision findings —
   treat `2` as a fail-closed STOP for pinning new work.
3. Findings are decision candidates for the user, never silent fixes:
   `KOLIZE AKTIVNÍ PRÁCE` (CHYBA), `DRAFT NA VÍCE VĚTVÍCH`, `FRONTA I DOKONČENO`
   (VAROVÁNÍ), `CIZÍ AKTIVNÍ PRÁCE` (INFO — normal parallel work).
4. **`-Jira` / `-Slug` = DECLARED INTENT** — the cross-clone collision check
   for work that does not exist locally yet. Without them, `KOLIZE AKTIVNÍ
   PRÁCE` can only be computed as local-active × foreign-active, so during
   Target-MB discovery (which runs BEFORE the design document is written, so
   the local set is empty) a colleague's active work on the very same ticket
   degrades into `CIZÍ AKTIVNÍ PRÁCE` and the run exits `0`. With the ticket
   or slug declared, a foreign ACTIVE entry matching it is `KOLIZE AKTIVNÍ
   PRÁCE` (CHYBA, exit 2) even with an empty local set. Foreign active work
   on OTHER tickets stays INFO either way, and your own already-pushed branch
   never collides with your own declared intent.
5. Taking over a draft from a foreign branch is a blob copy, never a
   cherry-pick (contract, Cross-Branch Visibility).

## Notes

- `-BaseRef` comes from `memory-bank/ums-repo.json` (`baseRef`) when not given —
  no need to remember that this fork's base is `origin/ums-memory-bank`. An
  explicit `-BaseRef` always wins; with no config the fallback is
  `origin/develop`.
- `-SinceDays` is an activity window over BRANCHES, not commits: only origin
  branches whose TIP is that recent are considered, and their history is then
  walked with no date limit, so a design document committed long ago on a live
  branch is still found. `-Jira`/`-Slug` (declared intent) enumerate without any
  window — a dormant foreign branch on the same ticket must still stop pinning —
  and the window then only trims the printed table, never the findings.
- The index is git-only and never sees Jira descriptions, so it does NOT report
  unreachable commits inside already published Jira links — reachability is
  enforced at write time by `mb-jira-update` §6b.
- Paths under `*/tests/fixtures/*` are excluded so the layer does not index its
  own test data.
- The printed table has no path column (slug, ticket, phase, branch, commit,
  author). Consumers that need the owning `memory-bank/` root — Target-MB
  discovery step 2 — must run with `-Json` and read `entries[].path`.
- The local (`branch = local`) part of the index comes from one
  `git ls-files --cached --others --exclude-standard` call, not a recursive
  directory walk: the target monorepo is very large and this script is on the
  hot path of discovery, `mb-state` and every elaboration bootstrap.
  Uncommitted documents are still indexed; gitignored ones are not.
