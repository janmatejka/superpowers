# Cross-Branch Visibility
Part of contract 3.x — the core is ../UMS_MEMORY_BANK_CONTRACT.md; cite as (contract/cross-branch-visibility.md, "Cross-Branch Visibility").

## Cross-Branch Visibility

Documents are never pushed into a shared branch to make them visible; they are
**pulled** — discovered on `origin` across branches by the `mb-doc-index` skill
(read-only). Rules:

- Discovery candidates are the union of the local working tree and the document
  index over `origin`.
- **Taking over a draft from a foreign branch** is a blob copy
  (`git show <ref>:<path> > <path>`), never a cherry-pick — an elaboration
  window closes with ONE commit carrying the ledger, the graph and all of the
  window's proposals, so a cherry-pick would drag in a foreign ledger. The
  taken-over design document records `**Převzato z:** <branch>@<sha>`.
- **A ticket branch is created with an EXPLICIT starting point, always:**
  `git switch -c <TICKET>-<kebab-slug> <chosen base>` after a `git fetch
  origin` — otherwise it cannot see already-merged planning. When the work item
  is being pinned for the FIRST time, `<chosen base>` is the base the user picked
  in the entry gate's Intent phase, NOT the effective base: the `Báze:` line that
  would carry the effective base is written a phase later. Where the work item is
  already pinned, `<chosen base>` IS the effective base (see Repository
  Configuration, the effective base, for the full carve-out and its exception).
  The **local** base branch is
  not used in a ticket workspace: if one exists it is neither updated nor merged —
  every later merge, diff and push of this work item names the remote base, which
  from the pin write onwards is the effective base.
  Immediately after creation the branch is detached from its inherited
  upstream (Publication Contract, the first-publication rule).
  **Postcondition of creation:** `proposals/active/` is empty or absent and
  `context.md` is IDLE (state names, tested by the pin — see the `context.md`
  Schema & Writers section). If it is not, STOP, delete the branch and repeat — a
  fresh ticket branch must never inherit another work item's active state.
  **Invariant: the base never carries ACTIVE state**, so a branch started from it
  is clean by construction; an ACTIVE base means a work item was integrated
  without a harvest and is reported as such.
- **Resurrected queue:** after a takeover the original may still sit in `next/`
  on the source branch and reappear in the base when that branch merges. This is
  detected (`mb-doc-index`, `mb-epic-graph -Check`), not prevented; the cleanup
  is one `git rm` by whoever sees the finding.
