# Epic Elaboration Protocol (detail)

AI-facing reference for [SKILL.md](SKILL.md). Read once per session before the
first window. Everything user-facing you produce is Czech; this file and your
dispatch prompts are English (Language Contract).

## 0. Session bootstrap

1. `git rev-parse --show-toplevel` → `MB_ROOT` (fail closed per contract).
2. Locate the epic workspace `<MB_ROOT>/memory-bank/epics/<epic_key_snake>/`
   (e.g. `ums_3304`). If `ledger.md` is missing, this is the FIRST window:
   instantiate it from [ledger-template.md](ledger-template.md) — items come
   from the item-source document (stable IDs, e.g. `WF-6`, `KI-1`; if the
   source has no IDs, mint `E-1..E-n` in the ledger and never renumber),
   tickets from the epic's current children. Creating the ledger is part of
   window #1, subject to the same handshake.
3. Run `pwsh <this skill>/scripts/ledger-status.ps1 -LedgerFile <ledger.md>`
   for state + next-window suggestion. Fix reported ledger inconsistencies
   before proposing new work.
4. Detect mode from `context.md` (`Jira: (bez tiketu)` — or a missing /
   unavailable Atlassian MCP — → Proposals; otherwise Jira). Mode selects the
   graph invocation in the next step.
5. Refresh the dependency view: follow the `mb-epic-graph` skill (fetch
   snapshot → generate + `-Check`). Its findings feed the agenda (mismatches
   are dirty-set candidates). In JIRA-less mode, run `mb-epic-graph` with
   `-Source Proposals -ProposalPath <members>` — no Jira fetch.
6. Read `## Model Routing` from `<MB_ROOT>/memory-bank/context.md`; map any
   sub-dispatch you make: read-only code verification / drafting = Worker,
   review or critique = Reviewer, summarization = Summarizer.

## 1. Window selection (what to propose in the handshake)

Priority order:

1. **Dirty items first** — correctness gate; inconsistency must not
   accumulate. Group dirty items sharing one coherent theme into the window.
2. Among clean candidates, **leverage first**: pick the area whose decisions
   AT THE CURRENT ELABORATION LEVEL most shape dependent matters. Foundations
   usually carry the most leverage, but leverage is the reason, not a
   mechanical base→consumer order. A CONTRACT decision keeps its leverage even
   when its implementation is blocked (decide contracts early so consumers are
   drawn consistently).

Window coherence: one coherent theme; MIXED axes (component + cross-cutting
concern) are allowed when the theme holds. Sizing is SOFT guidance — about one
component or one concern with a few open decisions; not a hard cap. Prefer
narrow-and-closed over wide-and-open.

**Framing handshake message (Czech):** state the proposed boundary, the item
IDs in scope, the known open questions, and what is explicitly OUT of scope.
Wait for confirmation or narrowing. The human always decides the agenda.

## 2. Per-window routine (Layer 1, expanded)

1. **Input context:** read the ticket(s) in scope + ALL their Jira links
   (both directions) + the item-source entries + memory-bank docs
   (`brief.md`, `product.md`, `architecture.md`, `tech.md`) of affected
   component MBs (MB Context Reading Rule). In JIRA-less mode: read the
   proposal(s) in scope + their header dependency fields (`Blokováno:`/
   `Blokuje:`/`Souvisí:`/`Vyčleněno z:`/`Vyčleněno do:`) and the linked
   sibling proposals (both directions), instead of tickets + Jira links.
2. **Reality verification:** dispatch a READ-ONLY exploration (Worker model)
   that confirms/refutes EVERY factual claim of the tickets/items in scope
   with `file:line` in current code and maps the affected code seams. Output
   categories: confirmed / refuted / newly-found. Newly-found facts become new
   ledger items (state `otevřená`, owner `nepřiřazeno` until decided).
3. **Already-solved check:** scan `proposals/completed/` of the affected
   component MBs for prior work covering an item — avoids re-solving; cite
   the completed proposal in the ledger note.
4. **Boundaries & partition:** for each item in scope assign EXACTLY ONE
   owner: this ticket / another existing ticket / a new ticket. Split
   criteria: distinct surface or component releasable independently, distinct
   blocker set, or scope growth. Merge criteria conversely. Ownership moves
   and new tickets are decisions (step 5), not unilateral acts.
5. **Clarification:** binding decisions from the human, one question at a
   time. Record each decision immediately in the artifact it belongs to
   (proposal "Závazná rozhodnutí" section with date), not in a side file.
6. **Design:** write or refine the PRELIMINARY proposal(s) — decisions folded
   INTO scope/design text (not appended as patch notes). Use the
   brainstorming method for the conversation; use the writing-plans structure
   if the elaboration level already warrants a plan draft. Placement:
   `<owner component MB>/proposals/next/proposal_<slug>.md`
   (+ optional `-design.md`), slug per contract naming
   (`<jira>_<short_snake_case_topic>`). NO `context.md` pinning, NO
   `active/`. Header carries `**Jira:**`, `**Blokováno:**`/`**Blokuje:**`/
   `**Souvisí:**`/`**Vyčleněno z:**`/`**Vyčleněno do:**` lines that MUST
   mirror the intended Jira links (the consistency check reads them). In JIRA-less mode there is
   no Jira to mirror: these header fields ARE the dependency edges
   themselves — the single source of truth the graph is generated from,
   exactly as Jira links are in Jira mode.
7. **Impact on neighbors:** enumerate every other ticket this window changed
   the premises of (moved item, changed/new dependency, corrected claim, new
   ticket) → dirty-set rows (`Zašpiněno oknem` = this window, with reason).
   Do NOT chase them.
8. **Write & reconcile (close):** see §3.

## 3. Window closure (exit gate)

A window closes only when its slice is internally consistent. Order:

1. **Present the slice diff (Czech) to the human:** new/changed ticket texts,
   link add/remove list, new tickets, proposal diffs, ledger changes. Get
   approval.
2. **Jira sync** (only after approval; Atlassian write tools): edit ticket
   descriptions, create tickets (linking them to the epic), add/remove links.
   Never leave prose asserting a dependency without creating the matching
   link in the same sync. JIRA-less: there is no Jira sync — reconcile by
   editing proposal headers/bodies; the graph regenerates from the proposals
   themselves.
3. **Regenerate the graph:** per `mb-epic-graph` — fresh snapshot AFTER the
   sync, regenerate `graph.md`, paste the wave table into the epic
   description (replacing the previous generated section; Mermaid only if a
   reviewer asks, via `-Mermaid`). `-Check` findings
   touching the window's items = the window is NOT closed; fix or record a
   human decision. Findings outside the window go to the dirty-set. JIRA-less:
   regenerate with `-Source Proposals`; paste the wave table into the
   přehledový dokument.
4. **Ledger update:** window `uzavřeno` + `Výstup`; item states advanced
   (`zapsaná`→`uzavřená` for reconciled items); ticket rollup updated
   (`hotov` only when ledger-status raises no objection); dirty rows cleaned
   by this window get `Vyčištěno oknem`.
5. **One commit** for the window (ledger + graph.md + proposals; use
   `mb-git-commit`, Czech message referencing the epic and window, e.g.
   `UMS-3304: okno W05 — <téma>`). Branch-in-place if on the default branch;
   git worktrees are banned.
6. **Refresh proposal links (post-commit):** for every ticket the window
   created or whose proposal it changed — plus any window ticket still missing
   the link — set/refresh ONE line in the Jira description:
   `**Návrh (proposal):** [<proposal filename>](<commit-pinned URL>)`. The URL
   is the commit-first Bitbucket permalink from `mb-jira-update` §5–7
   (`src/<sha>/<relative-path>`, `<sha>` = the window commit, branch fallback
   disabled). Idempotent: replace an existing such line, otherwise insert it
   near the top; touch nothing else in the description. The permalink resolves
   once the branch is pushed (`mb-git-commit` does not push) — expected; the
   link is "valid on next push". `mb-epic-graph -Check` reports
   `TIKET BEZ ODKAZU NA PROPOSAL` (VAROVÁNÍ) until the line is present.
   JIRA-less: this step does not apply — the nodes ARE the proposal files.
7. Elaboration converges (fixpoint) when: dirty-set empty AND every item
   `uzavřená` AND every ticket `hotov`. Until then, end the session by
   proposing the next window candidate — not by starting it.

## 4. Ledger state vocabulary (Czech tokens, fixed)

- Item: `otevřená → ověřená → rozhodnutá → zapsaná → uzavřená`;
  `vyvrácená` = verification refuted the premise (note says what happens to
  it: re-owned, re-scoped, or dropped by human decision).
- Ticket rollup: `nezahájen → ověřen → rozhodnut → návrh zapsán → srovnán →
  hotov` (maps to not-started → reality-verified → decided → proposal-written
  → reconciled → done). `hotov` requires all items `uzavřená` + none dirty.
- Window: `navrženo → agenda potvrzena → probíhá → uzavřeno`. At most one
  window in `agenda potvrzena`/`probíhá`.
- Dirty rows are append-only; cleaning fills `Vyčištěno oknem`.

## 5. Invariants (check at every closure; `mb-epic-graph -Check` + ledger-status automate most)

1. Complete partition, no overlaps: every item has exactly one owner ticket
   (duplicate ledger IDs = violation).
2. Links = single source of truth for dependency EXISTENCE (Jira links, or
   proposal header fields in JIRA-less mode); prose explains WHY; graph is
   generated, never hand-edited.
3. Three-way consistency: every dependency stated in prose (ticket
   description or proposal header) has a matching Jira link and vice versa,
   symmetric on both endpoints. This symmetry-on-both-endpoints requirement
   holds in Jira mode. In JIRA-less mode a dependency declared on ONE side
   still defines the edge — `ASYMETRICKÝ ODKAZ` is only a VAROVÁNÍ and does
   NOT fail `-Check` (one-sided declaration is allowed; the graph edge exists
   as soon as one endpoint declares it).
4. No claim without `file:line` verified in CURRENT code (re-verify when the
   window builds on old verification).
5. Placement and language per the MB contract.
6. Every ticket that owns a proposal carries an up-to-date
   `**Návrh (proposal):**` commit-pinned link to it in its Jira description
   (`mb-epic-graph -Check` → `TIKET BEZ ODKAZU NA PROPOSAL` when missing,
   `ODKAZ NA NEEXISTUJÍCÍ PROPOSAL` when stale). Jira mode only — JIRA-less
   nodes are the proposal files themselves.

## 6. Edge cases

- **New ticket needed:** create it in the closure sync (epic child, Czech
  summary/description with owned item IDs), add links, add a ledger Tikety
  row, re-own its items. Its proposal starts as preliminary in the owning
  component MB's `next/`.
- **Item spanning components:** split the item (new IDs suffixed `a`/`b`
  with distinct owners) rather than sharing one item between tickets.
- **Refuted premise of a NOT-in-scope ticket discovered mid-window:** dirty
  row + one-line reason. Even when trivial to fix. (The one exception: the
  fix is part of the window's own approved sync slice because the dependency
  edge touches an in-scope item — then it is in scope.)
- **External dependency (ticket outside the epic):** keep the link; the graph
  shows it dashed; do not elaborate the external ticket, note it in the
  ledger ticket row as `mimo epic`.
- **Human unavailable mid-window:** stop after the current question; the
  window stays `probíhá`; never substitute assumptions for pending decisions.
