# Harvest Contract
Part of contract 3.x — the core is ../UMS_MEMORY_BANK_CONTRACT.md; cite as (contract/harvest.md, "Harvest Contract").

## Harvest Contract

Consumed by `mb-harvest` (invoked from the finishing-a-development-branch
overlay, or standalone). Code is the source of truth; documentation follows
code.

1. **Preconditions (fail-closed):** `context.md` has a `Target MB Pin` and
   `Work item` slug; the active proposal (pair or legacy single) exists in
   `<PLAN_MB>/proposals/active/` and matches the slug.
2. **Affected MBs:** derive from
   `git diff --name-only $(git merge-base <baseRef> HEAD)..HEAD`
   (the effective base per Repository Configuration, not necessarily the
   `baseRef` config value), mapping each
   changed path to its nearest owning `memory-bank/` directory. Fall back to
   asking the user when the diff is unavailable.
3. **Harvest style — CURRENT-STATE (MANDATORY):** the current-state documents
   (`architecture.md`, `tech.md`, `brief.md`) describe the current state in
   present tense, as reference documentation. They are NOT a changelog.
   `playbook.md` is NOT one of them — it changes only through the gate below.
   - Place every fact in its owning document (see Document Ownership); fold it
     into the relevant current-state section and do not duplicate a fact that
     is already described elsewhere.
   - DO NOT create or append dated changelog sections ("Nedávné změny",
     "Recent Changes", "Changelog", "Historie změn", "Naposledy provedeno").
   - History lives in `proposals/completed/` and git — never in state docs.
   - When a change removes something, describe the new state; do not narrate
     the removal.
   - Continue with remaining affected MBs if one update fails; capture
     failures for the final report.

   **Staleness sweep (cheap, MANDATORY):** for each affected MB, grep ALL its
   `memory-bank/*.md` documents for the key symbols, element ids and variable
   names touched by the branch diff. Each hit has one of three outcomes:
   1. the hit describes a **superseded** state → fold it to current state;
   2. the hit is the fact's **existing home** → do not write a second copy;
      update it in place;
   3. the hit sits in the **wrong home** → move it per Document Ownership.

   One pass therefore detects staleness and duplication alike. Report every
   move.

   **Playbook gate (a non-autonomous step of the harvest):** when
   `<MB_ROOT>/.superpowers/playbook-candidates/<slug>.md` of the current work
   item is non-empty, present the candidates with their evidence to the user
   ONCE and let them choose. Approved ones are translated into Czech and written
   to `playbook.md` of the target MB — or of the MB named by the candidate's
   `Target MB` field. A candidate carrying `Corrects` is presented NEXT TO the
   entry it contradicts, and the user decides between replacing it, keeping both,
   or dropping the candidate. Unapproved candidates vanish with the file; report
   their count. A missing or empty file for the current slug skips the gate
   without a question; files of other slugs are not read and not touched.
   After the gate, DELETE the current slug's file — `git rm` when `mb-park`
   committed it (Playbook Contract), plain deletion otherwise — so no spent
   candidates travel on into the base.
4. **Archive:** move only the design half `design_<slug>.md` (or legacy
   `proposal_<slug>-design.md`) from `active/` to `completed/` unchanged
   (durable spec record) and **delete** the plan half `plan_<slug>.md` (or
   legacy `proposal_<slug>.md`) (remove the file; the harvest commit records
   the deletion). If there is no design half (grandfathered single plan),
   archive that plan to `completed/` so a record remains. Abandon path
   (`mb-abort`, or Discard in finishing) moves BOTH halves to `abandoned/`
   instead, deleting nothing.
5. **Reset:** only if every affected MB update succeeds, reset
   `context.md` `## Active Work` to IDLE per the schema above. On partial
   failure, leave `context.md` unchanged and report.
6. **Announce (Czech)** and offer `mb-jira-update` when a Jira ticket is
   linked.

All harvested document content is Czech.
