---
name: mb-doc-index
description: Use when you need to know which Memory Bank documents exist on other branches — before pinning new work (cross-clone collision check), when activating a queued design draft, when feeding the epic graph, or to answer "who is working on what" (kdo na čem pracuje, existuje už návrh, kolize slugů).
license: MIT
metadata:
  author: UMS Project
  version: "1.0"
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
  [-RepoPath <repo>] [-BaseRef origin/develop] [-SinceDays 120] `
  [-BranchGlob 'origin/feature/*'] [-Json <path>] [-NoFetch]
```

2. Exit codes: `0` OK · `1` input/script failure · `2` collision findings —
   treat `2` as a fail-closed STOP for pinning new work.
3. Findings are decision candidates for the user, never silent fixes:
   `KOLIZE AKTIVNÍ PRÁCE` (CHYBA), `DRAFT NA VÍCE VĚTVÍCH`, `FRONTA I DOKONČENO`
   (VAROVÁNÍ), `CIZÍ AKTIVNÍ PRÁCE` (INFO — normal parallel work).
4. Taking over a draft from a foreign branch is a blob copy, never a
   cherry-pick (contract, Cross-Branch Visibility).

## Notes

- `-BaseRef` defaults to `origin/develop`; in the superpowers fork use
  `origin/ums-memory-bank`.
- The index is git-only and never sees Jira descriptions, so it does NOT report
  unreachable commits inside already published Jira links — reachability is
  enforced at write time by `mb-jira-update` §7.
- Paths under `*/tests/fixtures/*` are excluded so the layer does not index its
  own test data.
