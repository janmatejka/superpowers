# Target-MB Discovery & Pinning
Part of contract 3.x — the core is ../UMS_MEMORY_BANK_CONTRACT.md; cite as (contract/target-mb-discovery.md, "Target-MB Discovery & Pinning").

## Target-MB Discovery & Pinning

Runs **during brainstorming**, as soon as the affected code area is
identifiable — always before the design document is written.

1. Scan `**/memory-bank/proposals/active/` for `{design_,plan_,proposal_}*.md`
   under `<MB_ROOT>`, then run the `mb-doc-index` skill **with `-Json <path>`**
   and take the candidate set as the UNION of the local scan and the index
   over `origin`. The `-Json` output is required, not optional: step 2 below
   normalizes every match to its owning `memory-bank/` root, and only
   `entries[].path` carries that path — the printed table deliberately does
   not. Keep the JSON for the rest of the session (`mb-epic-graph -IndexFile`
   consumes the same file).
2. Normalize each match to its owning `memory-bank/` root; apply the
   Discovery & pairing rule (Active Work Item section): strip exactly one
   prefix, `-design` only after `proposal_`, group by `(owning MB root,
   slug)` — one pair (or legacy single file) = one candidate.
3. Treat `CTX_DIR` as the orchestration root and exclude it from
   affected-project discovery unless the work is intentionally repo-wide.
4. Derive deterministic evidence tags per candidate root:
   - `seed_hit` (matches user seed context),
   - `active_hit` (matches current active work context or `Target MB Pin`),
   - `explicit_hit` (explicit user path).
   Candidates without any evidence tag are `untrusted` and cannot silently
   resolve ambiguity.
5. Resolution:
   - Exactly one trusted candidate → use it.
   - Exactly one untrusted candidate → ambiguous; do not auto-select.
   - Multiple trusted candidates → stop and ask exactly one disambiguation
     question with three options; the user always decides:
     - **A:** most affected project MBs (trusted candidates sorted by
       `score desc`, tie-break `path asc`),
     - **B:** nearest common project directory over the option-A candidates
       (if it has no `memory-bank/`, route to `mb-init`),
     - **C:** explicit directory provided by the user (outside `<MB_ROOT>`
       requires explicit cross-project confirmation).
   - Zero trusted candidates → do not guess. Ask the user for the target
     project path, or route to `mb-init` for a new component.
6. **Preliminary-queue activation:** check the selected MB's
   `proposals/next/` for a queued preliminary proposal matching the work
   (explicit user reference, ticket code, or topic — when the match is only
   probable, confirm with the user). On confirmation, move ALL files of its
   slug from `next/` to `active/`, renaming a legacy `proposal_*` draft to
   `design_<slug>.md` (the only permitted legacy conversion), reuse its slug
   and ticket, and treat the draft as seed input for the design. No match →
   continue with a fresh proposal.
   The queued draft may live on a foreign branch — the index reports it. Take it
   over by blob copy per Cross-Branch Visibility (never cherry-pick) and record
   `**Převzato z:** <branch>@<sha>` in its header.
7. Ask for the Jira ticket (one question; "none" is a valid answer; skip if
   already known from the activated preliminary proposal). If the ticket is
   known and the slug does not start with its code, rename the slug's files
   accordingly (Naming rule in the Active Work Item section).
8. **Two-actives guard:** an active proposal (pair or legacy single) with a
   *different* slug anywhere under `<MB_ROOT>` must be in one of **three**
   resolved states before new work is pinned — finished
   (`finishing-a-development-branch` → harvest), **parked** (`mb-park`), or
   abandoned (`mb-abort`). Which of the three needs a question is decided by the
   recoverability test below: unresolved work stops and asks the user, whereas
   work that is already parked is merely announced. Only `active/` counts;
   queued items in `next/` are ignored by this guard.
   The two-actives guard stays LOCAL; extending it to `origin` would forbid
   parallel work across the team. **The limit is per BRANCH, not per workspace,
   because each branch holds its own pin.** The guard therefore stops only when
   the active slug on the CURRENT branch is **not recoverable from `origin`** —
   it has uncommitted changes or unpushed commits. Committed and pushed work of
   another ticket is **parked** (Workspace Discipline), and starting a new ticket
   on a new branch is then normal operation: announce the parked item, do not
   stop. Alongside it runs the **cross-clone collision check**:
   the SAME slug or the SAME Jira ticket active on a foreign branch is a
   fail-closed STOP (double work), and the report carries the branch and the last
   commit date so the user can tell an abandoned branch from live work. Foreign
   active slugs of OTHER tickets are normal parallel operation — list them, never
   stop.
   **Run it with the intent DECLARED** — the ticket is known by now (step 7
   asked for it) and the slug usually is too:

   ```powershell
   pwsh <mb-doc-index>/scripts/doc-index.ps1 -Jira <ticket> [-Slug <slug>]
   ```

   This is not optional polish. At this point in brainstorming the design
   document does not exist yet, so the local set is empty and a
   local-versus-foreign comparison has nothing to compare: without `-Jira` /
   `-Slug` the colleague's active work on the very same ticket is reported as
   ordinary parallel work (INFO, exit 0) and both actors proceed. With the
   intent declared, the run exits `2` and the STOP fires. Exit `2` here blocks
   pinning; the decision (take over, wait, or proceed deliberately) is the
   user's, never the agent's.
9. Persist into `CTX_DIR/context.md` (creating the file if absent):
   `Target MB Pin`, `Jira`, `Work item` slug and `Started` (see the schema
   below).
10. Invalidation: the pin (and thus `PLAN_MB`) becomes invalid when the active
    proposal slug changes or the pinned path no longer exists — re-run this
    discovery, do not silently fall back.
