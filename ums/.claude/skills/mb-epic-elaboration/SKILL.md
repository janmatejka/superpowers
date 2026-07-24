---
name: mb-epic-elaboration
description: Use when iteratively elaborating a Jira epic — breaking it into tickets, refining ticket scopes and design proposals, deciding which ticket owns a finding/requirement, or when epic tickets, proposals and dependency links have drifted apart (rozpracování epiku, zpřesnění tiketů, dirty tikety po změně souseda).
license: MIT
metadata:
  author: UMS Project
  version: "1.1"
---

> Follow [UMS_MEMORY_BANK_CONTRACT](../shared/UMS_MEMORY_BANK_CONTRACT.md) —
> especially "Preliminary proposals (`next/`)", "Superpowers Document
> Placement", "Language Contract", and "Model Routing Consumption".

# Epic Elaboration (bounded-window fixpoint)

## Overview

An epic is (a) a **partition of atomic items** (findings/requirements with
stable IDs, e.g. `WF-6` from a risk-assessment doc) across tickets, plus
(b) a **dependency graph** between tickets (Jira links: blocks / relates /
split). Elaboration keeps both consistent with **code reality** through
**bounded windows** — small human sittings that each close internally
consistent. The fixpoint is reached ACROSS windows, never within one.

**Režimy.** V **Jira** režimu jsou uzly tikety a hrany Jira linky. V **JIRA-less**
režimu (Jira nedostupná / `context.md` bez tiketu) jsou uzly proposal dokumenty
(slug) a hrany hlavičková pole proposalů (`Blokováno:`/`Blokuje:`/`Souvisí:`/
`Vyčleněno z:`/`Vyčleněno do:`); „sync" na uzávěrce okna je přímá editace `.md`
souborů, ne zápis do Jiry. Disciplína oken, iron rules a invarianty jsou v obou
režimech totožné.

**Core discipline: finish one small window completely rather than touch the
whole epic shallowly.** Violating the letter of this discipline is violating
its spirit.

State lives in one **evidence ledger** per epic:
`<MB_ROOT>/memory-bank/epics/<epic_key_snake>/ledger.md` (Czech), instantiated
from [ledger-template.md](ledger-template.md). The generated dependency graph
is committed next to it as `graph.md`. Never track elaboration state by
editing the item-source document, scattering ad-hoc note files, or keeping it
only in Jira.

## When to use

- "Rozpracuj / pokračuj v rozpracování epiku X", refining epic tickets and
  their proposals, folding new findings into an epic.
- A neighbor ticket changed and dependent tickets are now stale (dirty).
- NOT for implementing a single ticket (superpowers workflow does that), and
  NOT for one-off Jira edits outside an epic breakdown.

## The window lifecycle (every window, in order)

| # | Phase | Gate |
|---|-------|------|
| 1 | **Framing handshake** — propose window boundary + agenda (item IDs + open questions), suggest from ledger (dirty first, then leverage) | Human confirms or narrows BEFORE any design/verification work |
| 2 | **Reality verification** — read-only exploration limited to the window's domain; every factual claim confirmed/refuted with `file:line` in CURRENT code; list newly-found items | No claim without evidence |
| 3 | **Already-solved check** — scan `proposals/completed/` of affected component MBs | Don't re-solve |
| 4 | **Decide** — targeted questions to the human ONE AT A TIME; each answer folds in before the next question | No batched question lists, no "otevřené otázky" files deferred to the end |
| 5 | **Write the slice** — reformulate ticket text, write/refine PRELIMINARY proposals in `<owner MB>/proposals/next/` (Czech; NO pinning, NOT `active/`), decisions folded INTO scope, item owners updated in ledger | Only artifacts inside the window |
| 6 | **Record ripple** — every impact on OTHER tickets (moved item, changed dependency, corrected premise, new ticket) goes to the ledger dirty-set. DO NOT fix them now | Ripple recorded, not chased |
| 7 | **Close** — sync the window's slice to Jira (after user approval): ticket texts, created tickets, link changes; regenerate the graph via the `mb-epic-graph` skill; its `-Check` must pass for the window's items; update ledger (window `uzavřeno`, item/ticket states, cleaned dirty rows); ONE commit for the window (`mb-git-commit`); after the commit, refresh each window ticket's `**Návrh (proposal):**` commit-pinned link (per `mb-jira-update` §5–7) (JIRA-less: sync = úprava hlaviček/těl proposalů místo Jiry; krok s odkazy na proposaly odpadá — uzly JSOU proposaly) | Window internally consistent: ticket ↔ proposal ↔ links ↔ graph agree for its items, and every ticket that owns a proposal links to it, even if the rest of the epic is unfinished |

For the detailed per-window routine, window sizing/selection, ledger state
vocabulary, invariants, and Jira sync mechanics, read
[protocol.md](protocol.md) before running your first window in a session.

## Iron rules

1. **No work before the handshake.** Drafting artifacts and marking them
   "k potvrzení" afterwards is the violation, not a mitigation — the human
   confirms the agenda first, then work happens.
2. **One window at a time.** A ticket is "done" only when all its items are
   closed and clean; windows may be sub-ticket or cross-ticket, but they stay
   small (soft guide: one component or one concern, a few open decisions).
   Prefer narrow-and-closed over wide-and-open.
3. **Dirty, don't chase.** Vertical tracing into code is bounded to the
   window's domain; horizontal ripple to other tickets is recorded in the
   dirty-set and resolved by some LATER window — that is what keeps every
   iteration finite.
4. **Links are the single source of truth** for dependency existence; prose
   explains WHY; the graph is GENERATED from links (`mb-epic-graph`) and
   never hand-edited or hand-curated. A disputed link is a decision for the
   human, then a link fix, then regeneration — never a silently prettified
   graph. V JIRA-less režimu jsou „links" hlavičková pole proposalů — táž
   disciplína (pole = CO, próza = PROČ, graf generovaný).
5. **Every item has exactly one owner ticket.** Split when a part has a
   distinct releasable surface, a distinct blocker set, or scope grew; merge
   conversely. A refuted premise re-opens ownership (decide, don't assume).
6. **Placement/language per MB contract:** elaboration writes PRELIMINARY
   proposals to `proposals/next/` without pinning `context.md`; user-facing
   artifacts (ledger, proposals, ticket text, Jira comments, commit messages)
   are Czech; never edit the item-source document to track state.

## Rationalizations (all mean: STOP, run the window protocol)

| Excuse | Reality |
|--------|---------|
| "The user asked for the whole epic today" | Deliver a closed window today and propose the next ones. A shallow pass over everything closes nothing and creates rework across all tickets. |
| "Batching questions is kinder / more efficient" | Answers change later questions. One at a time; fold each answer in before asking the next. |
| "This discovery is too important to leave for later" | That is exactly what the dirty-set is for. Record it; dirty items have top priority when selecting the NEXT window. |
| "I marked everything 'ke schválení', so drafting all tickets was safe" | Mass drafts on unconfirmed assumptions are the failure. Handshake → decisions → then write. |
| "The disputed link would pollute the graph, I'll omit it" | The graph mirrors links exactly. Flag the mismatch, get the decision, fix the LINK, regenerate. |
| "Proposals go to active/ since I'm working on them" | Elaboration is planning: `next/`, no pin, no two-actives conflict. `active/` is for the single implementation work item. |
| "A contract decision is pointless while its ticket is blocked" | Contract decisions carry the most leverage precisely then — decide the contract so consumers are drawn consistently before code unblocks. |

## Red flags — STOP and return to the protocol

- Starting verification or drafting before the human confirmed the agenda.
- A second ticket's proposal getting rewritten "while I'm here".
- Writing an "open questions" file instead of asking the first question.
- Editing the wave table / Mermaid graph text by hand, or omitting a link from it.
- `proposal_*.md` created under `proposals/active/` during elaboration.
- Editing the risk-assessment/source doc to reflect new findings' state.
- Ledger shows more than one window `probíhá`.

## Quick reference

| Need | Use |
|------|-----|
| Epic graph + prose↔links consistency (Jira i JIRA-less) | `mb-epic-graph` skill (companion); JIRA-less: `-Source Proposals -ProposalPath <members>` |
| Detekce režimu | `context.md` → `Jira:` prázdné/(bez tiketu) = JIRA-less |
| Ledger status, next-window suggestion | `pwsh scripts/ledger-status.ps1 -LedgerFile <ledger.md>` (read-only) |
| New ledger | Copy [ledger-template.md](ledger-template.md) → `memory-bank/epics/<epic>/ledger.md`, fill items from the source doc |
| Design conversation inside a window | brainstorming skill's method (one question at a time, sections as you go), scoped to the agenda |
| Preliminary plan draft structure | writing-plans structure, saved as `proposals/next/proposal_<slug>.md` |
| Sub-dispatch models | `## Model Routing` in root `context.md` (verification dispatch = Worker, review = Reviewer) |
