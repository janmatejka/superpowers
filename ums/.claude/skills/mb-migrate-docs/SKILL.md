---
name: mb-migrate-docs
description: Use when a repository's Memory Banks still use the legacy document shape — product.md alongside brief.md, or tasks.md instead of playbook.md — and you want them migrated to the current document set (migrace MB dokumentů, sloučení product do brief, přejmenování tasks na playbook).
license: MIT
metadata:
  author: UMS Project
  version: "1.0"
---

> Follow [UMS_MEMORY_BANK_CONTRACT](../shared/UMS_MEMORY_BANK_CONTRACT.md) —
> especially "Memory Bank Document Set" and "Document Ownership".

# Command: mb-migrate-docs

**Action:** Migrate every Memory Bank under the given scope to the current
document set — merge `product.md` into `brief.md`, rename `tasks.md` to
`playbook.md`, rewrite relative links across the migrated tree — then remove
the duplication the merge leaves in `brief.md` under a deletion-only verifier.
**Execution:** Interactive. The plan is shown to the user before `-Apply`; the
per-MB cleanup dispatch and the final commit both require the user's
go-ahead.

**⛔ GIT PROHIBITION:** no `git commit`/`push` from this skill. Staging
(`git add`/`mv`/`rm`) is performed by the scripts themselves and is allowed —
it is the snapshot `verify-deletion-only.ps1` diffs the cleanup agent's output
against. Offer `mb-git-commit` at the end.

**Model selection:** Plan/Apply/Report are script-driven, not model work. The
Step 3 cleanup dispatch runs on the cheapest capable tier (Dispatch Model
Policy) — its job is deletion and reordering of existing lines, not
authorship.

---

## Workflow

### 1. Plan

Run without `-Apply`:

```powershell
pwsh <this skill>/scripts/migrate-mb-docs.ps1 `
  [-RepoPath <repo>] [-Path <subtree>] -Json <tmp.json>
```

Show the user the printed Czech table and findings verbatim. Exit codes: `0`
OK, `1` input/script failure — stop and report, `2` blocking conflict
(`KONFLIKT PLAYBOOKU`, an MB with both `tasks.md` and `playbook.md` present).
Exit `2` is NOT a reason to stop the whole run: the conflicting MB is skipped
automatically and every other MB in scope still migrates. Deciding the
conflict (which file wins) is the user's call, never this skill's.

### 2. Apply

After the user approves the plan, re-run the identical command with `-Apply`,
keeping `-Json` pointed at a file you will still have after the run (the next
step reads it). The script itself refuses to run `-Apply` over a dirty
working tree — a clean tree is a precondition, not something this skill
enforces separately.

### 3. Agentic cleanup — merged MBs only

Read the `-Json` output's `mbs[]`. For every entry with `merged: true` — and
ONLY those; a rename-only or already-current MB has no duplication to clean —
dispatch one subagent, on the cheapest capable tier, with this exact task
(fill in `<path>` from the entry's `path` field):

> Read `<path>/brief.md`. It was mechanically assembled from two documents and
> now repeats itself. Remove the duplication. You may ONLY delete whole lines
> and reorder existing lines. You MUST NOT write a single new sentence,
> rephrase a line, merge two sentences into one, or add a heading — every
> line you leave must be byte-identical to a line that is there now. When two
> lines say the same thing, delete the weaker one whole. Write the result
> back to the same file. Reply with the number of lines removed and nothing
> else.

Immediately after each dispatch returns, run:

```powershell
pwsh <this skill>/scripts/verify-deletion-only.ps1 -RepoPath <repo> -File <path>/brief.md
```

- **Exit `2` (violation):** run `git checkout -- <path>/brief.md` to restore
  the mechanical (pre-cleanup) version, and record that MB as **not cleaned
  up** for the report.
- **Exit `0` with a `VAROVÁNÍ`** (more than 50% of non-empty lines removed):
  keep the cleanup agent's result, but list the MB for human review in the
  final report — a warning is not a block.
- **Exit `0` with no warning:** cleaned; record the reported line count.
- **Exit `1` (input/script failure — e.g. the file is not staged):** this
  should not happen in normal operation, since Step 2 just staged every
  `brief.md` it touched. If it does, stop and report the failure for that MB
  — do not guess which of the two branches above it belongs to.

### 4. Report and commit

Print a Czech table — MB, sloučeno (yes/no), přejmenováno (yes/no), ubráno
řádků, stav úklidu — followed by the list of MBs skipped for
`KONFLIKT PLAYBOOKU` and the list of MBs left un-cleaned after a Step 3
violation. Then offer `mb-git-commit`.

---

## Notes

- **Idempotence.** Re-running the script — in the same repository on a later
  day, or against a copy of the same tree in a different repository — is
  safe: an MB already in the current shape (`brief.md` + `playbook.md`, no
  `product.md`/`tasks.md` left) reports `beze změny (hotovo)` and nothing is
  touched. Nothing about this skill assumes it runs exactly once.
- **The cleanup agent's prose is provisional, not final.** The nearest
  `mb-harvest` treats the merged `brief.md` as an ordinary current-state
  document still open for editing — it owes the cleanup agent's wording no
  preservation, only the facts it carries.
- **`playbook.md` produced by the rename is bound by the Playbook Contract
  from the moment it exists** (consult-before-write regime, contract) — the
  rename does not exempt it, and no writer may treat a freshly renamed
  `playbook.md` as free-form scratch.
- **The rename assumes `tasks.md` holds procedures.** In the target monorepo
  that holds for all ten occurrences, but an MB whose `tasks.md` really is a
  list of open items must be excluded with `-Path` — no script can tell the
  two apart, which is why the plan mode exists and why the human reads it
  before `-Apply`.
- **What "Ubráno 0 z N" from the verifier does and does not prove.** Task 3's
  review established the verifier's exact reach by execution, not by
  intention: its multiset-containment check proves that no new LINE was
  authored — it does NOT prove that no new MEANING was created. Reordering
  across the whole file is unconstrained by design, so a cleanup agent can
  rebuild a materially different document out of recombined existing lines —
  a heading moved under a different section, a sentence reparented next to a
  different paragraph — and the verifier will report "Ubráno 0 z N" with no
  warning at all, because every candidate line still existed somewhere in the
  original. This is not a loophole to close: invented text — a genuinely new
  sentence, a rephrase, two lines merged into one — is mechanically and
  reliably blocked, and that is the guarantee the verifier exists to give.
  What it does NOT give is a guarantee about the document's resulting shape.
  Treat a Step 3 pass as "no authorship happened", never as "the result reads
  correctly" — the latter is what the harvest-time read (previous bullet) and
  the human review the report asks for (Step 4) are still there to catch.
