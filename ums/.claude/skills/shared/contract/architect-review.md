# Architect Review Gate
Part of contract 3.x — the core is ../UMS_MEMORY_BANK_CONTRACT.md; cite as (contract/architect-review.md, "Architect Review Gate").

## Architect Review Gate

An approved design may be reviewed by a **human architect** before planning
and implementation. The gate is mediated by the Jira ticket and implemented
by the `mb-architect-review` skill (modes: request / respond / resume). The
brainstorming overlay ALWAYS offers the gate after the user approves the spec
when a Jira ticket is linked (with a yes/no recommendation based on
non-triviality: new component or service, architecture/contract changes,
cross-project impact, DB migration, security impact). No ticket → no offer.

**State lives in the ticket branch.** All interaction over a ticket happens
on that ticket's branch; every handoff (request and respond) ends with the
state committed and pushed to origin per the Publication Contract (the ticket
branch is the actor's own branch, so the push is announced, not negotiated).
The design document, `context.md` (including the `Review:` line) and any
notes are thus available to both sides and to Bitbucket links. Recommended branch
naming: `<TICKET>-<kebab-slug>`, for example `UMS-3302-toast-reconcile`, derived
from the work-item slug by the Naming rule in the Active Work Item section. New
names are ASCII; existing branches carrying diacritics are NOT renamed — a rename
would break the request comment's authoritative branch name for no benefit.

**Push policy:** per the Publication Contract — the ticket branch is the actor's
own branch, so the handoff push is announced, not negotiated; shared branches are
never pushed by the agent. Steps are ordered so one handoff needs exactly **one**
push, and the order is what makes that true: the base merge (resolver side only)
comes FIRST and is not pushed on its own, the handoff state is committed after it,
and the single closing push publishes both commits together. That push satisfies
the publication rule for the merge commit as well — a base merge is never left
unpublished, it merely shares the push with the commit that follows it inside the
same handoff.

**Base merge is asymmetric: only the RESOLVER's side merges the base** (request
and resume). The architect in respond mode NEVER merges it. Branch sync's rule is
"divergence = STOP", and a base merge from both sides produces exactly that
divergence — the two sides would create different merge commits over the same
base and the next sync would stop. The resolver's base merge belongs **before**
the handoff push (Base Sync & Drift Detection).

**Branch sync** (first step of respond and resume): resolve the ticket branch
in this order — branch name from the request comment (authoritative) → remote
branches whose name contains the ticket code (`git ls-remote --heads origin`,
case-insensitive) → ask the user; multiple ambiguous candidates always ask.
Require a clean working tree (dirty = STOP, no auto-stash). Then
`git fetch origin`, checkout the ticket branch and fast-forward to origin;
a diverged local branch = STOP and report. Only after branch sync read
`context.md` and the design document — both live on the ticket branch.

**Jira conventions:**

- Status flow: request transitions the ticket to **"Design Review"**; the
  architect's respond leaves the status unchanged; resume transitions to
  **"In Progress"**.
- **"Design Review" fallback.** When the "Design Review" transition does not
  exist (the status is not configured in the Jira instance), request falls
  back to the existing **"Review"** status. The request comment ALWAYS begins
  with the marker line **`[DESIGN REVIEW]`** — written unconditionally, so the
  fallback never depends on having predicted the transition's absence — and in
  the fallback state that marker is what distinguishes a design review from an
  ordinary review (code review / test). The fallback is announced to the user;
  the fail-closed STOP fires only when the "Review" transition is missing too.
  Wherever this contract or a skill tests that a ticket "sits in Design
  Review", the test reads: status "Design Review", OR status "Review" AND a
  request comment whose first line carries `[DESIGN REVIEW]`. The marker adds
  no new evidence — the request comment already records the resolver and the
  branch. A deleted marker degrades to the existing "respond without a request
  comment" path (ask the user, never guess). The fallback is a bridge, not a
  mode: once the "Design Review" status exists, the primary path stops using
  the fallback on its own — no configuration, no switch. `mb-epic-graph` does
  not read comments, so a fallback-shaped ticket gets the plain "Review"
  glyph — a documented imprecision of the bridge, not a defect to fix.
- **Flag** (`Flagged` field, value Impediment): set by respond when returning
  the ticket, cleared by resume (and by mb-jira-update finalization if still
  present). Team convention: a flag means "work returned to you — attend to
  it" (same as a tester returning a bug).
- **AgentSessions** (customfield_11248, Paragraph): request APPENDS one line
  `YYYY-MM-DD <harness> <session-id> — design review request (<ticket>)`.
  Session id is best-effort per harness; if undetectable, write the line
  without an id and tell the user. If the field is unavailable, put the same
  line into the request comment instead.
- The request comment records the **original resolver** (accountId +
  displayName) and the **ticket branch name** — respond needs both.

**Fail-closed rules:**

- While `context.md` carries the `Review:` line, continuing the workflow
  (writing-plans and beyond) is blocked; the correct continuation is
  `mb-architect-review` resume.
- Discard/abort paths (`mb-abort`, finishing Discard) with a ticket sitting
  in "Design Review" MUST offer Jira cleanup: transition back, restore
  assignee, clear the flag.
- Respond without a request comment (architect assigned manually): ask the
  user for the return assignee and branch; never guess.
- Resume without the flag (architect answered manually in Jira): warn and
  continue only after user confirmation.

## Agentic Design Opposition (oponentura)

An optional adversarial review of a design document by an INDEPENDENT
subagent with a clean context — the opponent has seen none of the dialog
that produced the design, so it reads what the document says, not what its
author meant. Always an OFFER the user accepts or declines; never an
automatic run (the dispatch is not free — see Model and effort below).

**Dispatch (by the driving session).** The opponent receives: the design
document; the target MB's documents (`brief.md`, `architecture.md`,
`tech.md`, `playbook.md` — those that exist, legacy shape per Memory Bank
Document Set); and read access to the repository code, so integration
claims are checked against reality rather than against the design's own
prose. The dispatch prompt and the findings are AI-facing and therefore
English (Language Contract). The opponent looks for defects in
architecture, semantics, integration, security and similar concerns.

**Model and effort.** Opposition is design-assessment work — an
"architecture and design task" in the driving workflow's Model Selection —
so it is dispatched on the MOST CAPABLE available model, never the session
default, and with the highest reasoning effort the harness exposes on a
dispatch (a harness without such a parameter sets the model alone). State
both explicitly; an omitted parameter silently inherits the session's
(Dispatch Model Policy). A cheap tier is a false economy here: weak
opposition produces noise whose triage and user dialog cost more than the
dispatch saved.

**Findings format.** A structured list; every finding carries a category
(architecture / semantics / integration / security / other), a severity, a
claim, and EVIDENCE — a reference to the place in the design, the MB
document or the code the claim stands on. A finding without evidence is
not emitted. As with playbook candidates, the format enforces the ban on
invention — without evidence there is no finding.

**Triage (by the driving session).** Every finding lands in exactly one
bucket:

1. **Relevant and uncontested** → folded into the design directly.
2. **Contested, or scope-changing** → resolved with the user in a BATCHED
   dialog: several questions per iteration — the harness's structured
   questions where available, a numbered list in one message otherwise —
   so the user answers several points at once instead of a
   one-question-per-turn ping-pong.
3. **Irrelevant or wrong** → rejected, with the reason recorded for the
   closing summary.

**Closing summary (Czech).** After triage and dialog the user receives one
summary: what was folded in without asking (with the offer to revert any
of it), the decisions taken on contested points, and the rejected findings
with reasons. Nothing is folded in silently.

**Consumption points** — three, each an offer:

1. **Brainstorming, architectural path** — after the user approves the
   written spec, BEFORE the Architect Review Gate offer: agentic
   opposition can pre-filter mechanically findable defects before the
   design costs a human architect's time. Folding findings into an
   approved spec changes it, so the changed passages go back for the
   user's re-approval (the closing summary is its input); the design
   counts as FINALLY approved — for the Epic Backflow trigger and the
   Architect Review Gate offer — only after that re-approval.
2. **`mb-architect-review`, respond mode** — the architect's aide: the
   findings feed the structured assessment (its summary and conversation
   phases), never direct design edits — in respond the design belongs to
   the resolver. Triage is the architect's, made in the conversation, not
   the driving session's own.
3. **`mb-architect-review`, oppose mode** — standalone, on demand, over an
   existing design document; no Jira side effects (no transition, no
   flag). The one consumption point where the fold lands outside a
   brainstorming session: the design edits are committed and pushed on the
   ticket branch like any other commit of the work item.
