---
name: mb-state
description: Read-only status report of the Memory Bank workflow and of the workspace itself — Target MB Pin, proposal pair completeness, SDD progress ledger, branch, staleness, plus workspace fitness (pre-push hook, repository configuration), leftovers, work parked on other local branches and distance from the base. Use to check workflow status, to ask whether this workspace is fit to work in or what is lying around here, and to get next-step suggestions.
license: MIT
metadata:
  author: UMS Project
  version: "2.3"
---

> Follow [UMS_MEMORY_BANK_CONTRACT](../shared/UMS_MEMORY_BANK_CONTRACT.md) —
> especially "Workspace Discipline", "Repository Configuration",
> "Base Sync & Drift Detection", "Cross-Branch Visibility",
> "Active Work Item (Design + Plan Pair)" and "`context.md` Schema & Writers".

# Command: mb-state

**Action:** Report the current Memory Bank state and suggest the next step.
**Execution:** Read-only — does NOT modify files.

---

## Workflow

### 0. Resolve MB_ROOT and gate

- `git rev-parse --show-toplevel` → `MB_ROOT`; failure = hard stop
  (`Git repository not found. Memory Bank requires git.`).
- `<MB_ROOT>/memory-bank/` must exist, else stop with the Root Gate error.

### 1. Gather state (read-only)

**Everything in this section only reads.** No command below writes, stages,
stashes, commits, pushes, switches or fetches — not even to "refresh" the view.
Where a fact would need a fetch, report it as of the last fetch instead of
performing one. Reading another branch's state never checks that branch out.

- **Workspace readiness** — report this FIRST, because it is the most
  consequential finding here. The user creates the workspace and **git hooks do
  not travel with a clone**, so a workspace missing the hook looks exactly like
  a working one while carrying no publication guarantee at all (contract,
  Workspace Discipline and Publication Contract).

  ```bash
  git rev-parse --git-path hooks/pre-push
  git config --get core.hooksPath
  ```

  - The resolved path must exist **and** carry the case-sensitive marker
    `UMS pre-push guard` within its first five lines — a foreign `pre-push` from
    some other tool occupies the same filename and satisfies "exists" without
    enforcing anything. Do NOT verify by pushing: mb-state is read-only, and the
    executable self-test (feeding the hook a synthetic ref line) belongs to
    `install-git-hooks.ps1` and to the entry gate, not here.
  - `git config --get core.hooksPath` decides **where** the hook above was looked
    for, and `git rev-parse --git-path hooks/pre-push` already honours it — so a
    marker found there is a marker in the directory git itself will execute. An
    absolute value is therefore **not** a bypass and is not reported as one; it is
    a **scope** warning: the directory is shared with other repositories (a global
    husky or pre-commit setup), so installing or removing the layer's hook there
    reaches every repository using that config, and the file may equally have been
    put there by another repository's install. The marker check settles that
    provenance question, which is the only thing that was ever at stake. A missing
    or unmarked hook stays a missing guarantee whatever `core.hooksPath` says.
  - `<CTX_DIR>/ums-repo.json` — its presence decides which values are in force.
    Absent means the **built-in defaults** apply (`origin/develop` as base, the
    built-in protected-branch list, the generic ticket pattern), not the
    repository's own; say which of the two is in force rather than implying the
    configured ones do. This item is informational — a missing configuration is
    reported, never treated as a defect (contract, Repository Configuration).
  - mb-state **reports**, it never stops work: an unverified hook is the loudest
    line in the report and a next-step suggestion, not a hard failure. Failing
    closed on it is the entry gate's job (Workspace Discipline).
- **A free workspace** is a derived state, read every time from these four
  commands and never from a flag or a bookkeeping file (contract, Workspace
  Discipline):

  ```bash
  git status --porcelain
  git stash list
  git log --branches --not --remotes --oneline
  git ls-files --error-unmatch <MB_ROOT>/.superpowers/playbook-candidates/<slug>.md
  ```

  The fourth command is the fourth signal, and the three before it cannot report
  it: `.superpowers/` is git-ignored, so a non-empty **untracked** candidate file of
  the CURRENT slug is invisible to `git status --porcelain` while the evidence
  exists only in this workspace. Probe it directly — does it exist, is it non-empty,
  is it tracked. `<slug>` is the `Work item` slug read from `context.md` further
  down this list; with no pin there is no current slug and this signal is simply
  clear (files of other slugs are merely present, never in the way).

  All four clear = "no leftovers". Otherwise split the findings in two, and keep
  the split in the report:

  - **In the way** — a dirty working tree, a stash, and a **non-empty untracked
    candidate file of the CURRENT slug**. They block a safe branch switch and have
    to be resolved before one. The candidate file is in the way because it is
    non-recoverable: switching away leaves it attached to no branch, and committing
    it is what `mb-park`'s named exception exists for (contract, Playbook Contract).
  - **Merely present** — unpushed commits of other branches, candidate files of
    other slugs, and a **tracked** candidate file of the current slug (`mb-park`
    already committed it, so it is recoverable from `origin` — tracked means live,
    and only the harvest removes it). Announced only; mb-state neither touches nor
    recommends touching them beyond naming the owner.

  The boundary behind the split: the agent never destroys anything it cannot get
  back from `origin`. Suggest resolutions, never perform them.
- **Parked work across local branches.** For every local branch matching
  `ticketPattern` from `<CTX_DIR>/ums-repo.json` (never a hardcoded prefix such
  as `UMS-`; without the configuration the built-in generic pattern applies),
  read its pin **without checking the branch out**:

  ```bash
  git for-each-ref --format='%(refname:short) %(committerdate:short)' refs/heads/
  git show <branch>:memory-bank/context.md
  ```

  List slug, ticket and the last commit date per branch. A branch whose
  `git show` fails because it has no `memory-bank/context.md` is **not an
  error** — it is simply a branch with nothing pinned; skip it silently.

  **The ACTIVE test is the pin, never the word.** `ACTIVE` and `IDLE` are state
  names; neither string appears in `context.md`, so grepping for them matches
  nothing and would report every branch IDLE. The mechanical test, here and in
  every other place this skill reads state (the current branch, other local
  branches, the base): does the `## Active Work` block carry a `Target MB Pin`
  together with a `Work item` slug (legacy `- **Proposal:**` accepted as its
  alias)? Pin present = ACTIVE; the `(No active work - IDLE phase)` marker, or a
  block with no pin = IDLE.
- **Distance from the base:**

  ```bash
  git rev-list --count HEAD..<baseRef>
  ```

  `baseRef` comes from `<CTX_DIR>/ums-repo.json` and already carries the remote
  (`origin/develop` is the fallback value), so it is not prefixed with `origin/`
  a second time. The count is how many base commits this branch is missing, as of
  the last fetch — mb-state does not fetch. Above zero, suggest a base sync at the
  **nearest phase boundary** (contract, Base Sync & Drift Detection); never in the
  middle of a task, and mb-state never merges anything itself.
- **Base invariant:** the base must NOT carry an ACTIVE pin.

  ```bash
  git show <baseRef>:memory-bank/context.md
  ```

  Apply the pin test above. A pinned base is an **error**, not a warning: every
  branch cut from it afterwards inherits a foreign pin, and the pin got there
  because a work item was integrated without a harvest (contract, Cross-Branch
  Visibility). Report it as such; a missing file on the base is IDLE, not an
  error.
- **Playbook candidates:** list `<MB_ROOT>/.superpowers/playbook-candidates/*.md`
  and the slug each file is named for. `.superpowers/` is git-ignored, so these
  files are invisible to `git status --porcelain` — the directory listing is the
  only way to see them. Files of other slugs are reported and **never** deleted. The
  CURRENT slug's file is also classified by the leftover split above (untracked and
  non-empty = in the way; tracked = merely present, already parked).
- `<CTX_DIR>/context.md` → `Jira`, `Target MB Pin`, `Work item` slug (legacy
  `Proposal` accepted), `Started`. Apply the same pin test as above — a missing
  file, or a `## Active Work` block carrying no pin → `PHASE = IDLE`, a pin
  present → `ACTIVE_WORK`; never grep for the word. Ignore stale v1 fields (`Status`,
  `Run Mode`, `Execution Mode`, `Implementation Checklist`,
  `Auto Loop State`) — the v2 schema abolished them; their presence is worth
  a one-line note suggesting a reset at the next harvest.
- Pair completeness in `<PLAN_MB>/proposals/active/` (per the contract's
  Discovery & pairing rule — both naming styles):
  - `design_<slug>.md` + `plan_<slug>.md` (or legacy pair) → complete pair,
  - design half only → „rozpracovaný návrh (chybí plán)" — valid state
    between brainstorming and writing-plans,
  - plan-style single file (legacy `proposal_<slug>.md`) → grandfathered v1
    work item — valid,
  - nothing / slug mismatch → inconsistent, recommend `mb-harvest` audit or
    `mb-abort`.
- **Review pending:** a `- **Review:** design-review requested YYYY-MM-DD`
  line in `## Active Work` means the design sits with the architect — the
  workflow is parked (no writing-plans) until `mb-architect-review` resume.
- **Two-actives check:** scan
  `**/memory-bank/proposals/active/{design_,plan_,proposal_}*.md` (group by
  slug per the pairing rule). The limit is **one active work item per branch**,
  not per clone, so what counts as a finding depends on where the slug sits:
  - **On the current branch** — an active slug different from the pinned one is
    a warning: recommend finishing, parking (`mb-park`) or `mb-abort` before new
    work.
  - **On another local branch** — that is **parked work, not a collision**. Each
    branch carries its own pin in its own `context.md`, and parked work is
    recoverable from `origin` by definition, so it never blocks starting another
    ticket. Report it under parked work and move on (contract, Active Work Item
    and Workspace Discipline).

  Queued items in `proposals/next/` are NOT counted here.
- **Preliminary queue:** scan
  `**/memory-bank/proposals/next/{design_,plan_,proposal_}*.md` (group by
  slug per the pairing rule, per owning MB) and list the queued preliminary
  proposals — they activate by moving to `active/` when work on them starts
  (contract, Target-MB Discovery & Pinning).
- **Foreign branches:** run the `mb-doc-index` skill **with `-NoFetch`**. The
  switch is not optional here: without it the script runs
  `git fetch --prune origin`, which rewrites remote-tracking refs and
  `FETCH_HEAD` and moves `origin/<branch>` under the user — a write, and one
  mb-state has no business performing offline, on a metered connection, or in
  the middle of a task. **The foreign-branch view is therefore as of the last
  fetch**, exactly like the base distance above; say so rather than implying it
  is live. Report foreign active work items (slug, ticket, branch, last commit —
  invoke with `-Json` for the commit date, which the default table does not
  print) and its findings. When `context.md` carries active work, pass its identity as
  declared intent (`-Jira <ticket>` / `-Slug <work item>`): the collision
  check is otherwise computed against the local working tree only, so it
  stays blind while the pin exists but the design document does not. A
  `KOLIZE AKTIVNÍ PRÁCE` finding is a warning here (mb-state
  never stops work) with the recommendation to resolve it before pinning new
  work.
- Execution progress: does `.superpowers/sdd/<plan-basename>/progress.md` exist? (Presence =
  plan execution in flight; content shows the last completed task.)
- Git: current branch (`git branch --show-current`), work on main/master is a
  warning.
- Staleness: `Started` older than 7 days → warn that requirements may have
  drifted.

### 2. Report (Czech)

```
📊 Stav Memory Bank

Projekt: <name>   Kořen: <MB_ROOT>
Workspace: <✅ způsobilý | ⚠️ pre-push hook chybí/neověřený> <+ ⚠️ core.hooksPath je absolutní — hook je společný pro víc repozitářů (ověřen značkou, ale instalace/odinstalace zasáhne i je)> <+ ℹ️ ums-repo.json chybí (platí vestavěné defaulty)>
Fáze: IDLE | ACTIVE_WORK
Jira: <ticket|žádný>   Cílová MB: <Target MB Pin|nepřipnuto>
Work item: <slug> — [kompletní pár | jen návrh | grandfathered v1 | nekonzistentní]
Review: <žádné | ⏳ čeká na design review u architekta od YYYY-MM-DD>
Zahájeno: <Started> <(⚠️ starší než 7 dní)>
Exekuce: [.superpowers/sdd/<plan-basename>/progress.md nalezen — probíhá | nenalezen]
Větev: <branch> <(⚠️ main/master)>
Báze: <baseRef> — chybí <N> commitů <(⚠️ ACTIVE stav na bázi — větev z ní zdědí cizí pin)>
Zbytky: [žádné | v cestě: <výčet> | pouze přítomné: <výčet>]
Zaparkováno: <žádné | výčet větev → slug (tiket, datum)>
Další aktivní proposaly: <žádné | ⚠️ výčet cizích slugů na TÉTO větvi>
Fronta (proposals/next/): <prázdná | výčet slugů s vlastnící MB>
Cizí větve: <žádné | výčet slug@větev (datum)>
Kolize: <žádné | ⚠️ výčet>
Kandidáti playbooku: <žádní | výčet slugů>

Další krok:
- IDLE → popiš, co chceš postavit (spustí se brainstorming); mb-scan pro analýzu
- fronta neprázdná → řekni, že chceš začít na některém z fronty (přesun next/ → active/ proběhne v brainstormingu)
- jen návrh → pokračuj writing-plans
- kompletní pár → exekuce dle hlavičky plánu (subagent-driven-development)
- čeká na review → mb-architect-review (resume) po vrácení tiketu; writing-plans je do té doby blokován
- hotová implementace → finishing-a-development-branch (harvest gate)
- opuštěná práce → mb-abort; pozdní sklizeň → mb-harvest
- zbytky v cestě a větev MÁ pin → mb-park (odložit), nebo zahodit po tvém výslovném potvrzení
- zbytky v cestě a větev je IDLE → commitni je, nebo zahoď po tvém výslovném potvrzení (mb-park by řekl „Není co parkovat")
- pre-push chybí/neověřený → spusť install-git-hooks.ps1 a znovu ověř
- báze chybí commity → base sync na nejbližší hranici fáze (ne uprostřed tasku)
```

Two notes on the template. The `Workspace:` line is **not** one alternation over
all findings: a missing hook, an absolute `core.hooksPath` and a missing
configuration are independent findings that can hold at once, so list every one
that applies. Only the FIRST position is an alternation, and `✅ způsobilý` is
withheld for exactly one class of finding — a **missing guarantee**, today only the
missing or unmarked `pre-push` hook. Everything that is not a missing guarantee
rides ALONGSIDE `✅ způsobilý` instead of replacing it: `✅ způsobilý` with no
further item means no finding at all, `✅ způsobilý` followed by items means the
workspace is fit AND those items hold. A missing `ums-repo.json` carries `ℹ️`, not
`⚠️` — its absence is informational and never a defect, the same weight the
gather step and the contract give it. An absolute `core.hooksPath` is a warning
about SCOPE, never a claim that the hook is bypassed: the hook was resolved through
that very path, so a verified marker there is a live guarantee, and `✅ způsobilý`
plus this one warning is the correct line for such a workspace — never a line
without `✅`.

Everything under „Další krok" is a suggestion addressed to the **user**. mb-state
performs none of it: it does not park, does not install the hook, does not sync
the base and does not discard anything.

## State vs Scan

| | mb-state | mb-scan |
|:--|:----------|:---------|
| Speed | Quick (seconds) | Thorough (minutes) |
| Focus | Workflow state | Code health |
| Use for | Status check | Deep analysis |
