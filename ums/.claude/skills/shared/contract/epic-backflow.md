# Epic Backflow
Part of contract 3.x — the core is ../UMS_MEMORY_BANK_CONTRACT.md; cite as (contract/epic-backflow.md, "Epic Backflow (design → epic)").

## Epic Backflow (design → epic)

Refining a design can change the scope or the dependencies its ticket was
given when the epic was elaborated, and nothing else propagates that back:
the epic graph is a snapshot from elaboration time. This section closes the
gap with one bounded, fail-open step after final design approval.

**Trigger point.** The step runs once per work item, after the design is
FINALLY approved: at `mb-architect-review` resume when a review took place,
otherwise immediately after the user approves the spec. Never before the
review — a review may change the design, so an earlier check would be done
twice.

**When the step does not run:**

- No Jira ticket linked → skipped silently. Work without a ticket belongs to
  no epic; this is normality, not an exception, so nothing is announced.
- Atlassian MCP unavailable, or the ticket belongs to no epic → skipped with
  a one-line announcement.

**The trigger is the existing oracle, never a scope-diff metric.** Run the
`mb-epic-graph` skill with `-Check` (read-only). A finding concerning THIS
ticket is the trigger; findings about other tickets are printed and left
alone. An oracle failure skips the step with an announcement — the step is
fail-open and never blocks an approved design.

**On a finding:**

**Write the finding, always.** Append it to the per-ticket epic file
(contract/epic-backflow.md, "The per-ticket epic file"), section
`## Backflow` — never a shared `notes.md` on the base. The line is
committed on the ticket branch like any other commit of this work item —
it is this work item's record, so it legitimately rides the ticket branch
into the base at integration.

**The ticket session then continues — there is no offer and no choice left
to make here.** The step does NOT offer an inline elaboration window, does
NOT switch branches, and does NOT put anything to the user on a finding.
Only the epic's manager opens elaboration. Three reasons this offer is gone
for good, not the finding it used to gate:

Doklad: doklad/epic-backflow.md, "Why the inline elaboration offer is gone"

Doklad: doklad/epic-backflow.md, "The offer dies, not the finding"

Elaboration artifacts never land on the ticket branch, and that matters more
than ever now: a window closes with one commit on its own branch, while a
ticket branch's commits ride the fast-forward integration into the base as
part of the ticket — two units of work in one history. That mismatch is
exactly what made switching branches mid-ticket the wrong shape (the third
reason above), not merely inconvenient.

A dirty-set row whose concern a window has already resolved (the row lives
on the ticket branch, the window on its own branch — neither sees the other
until both reach the base) is cleaned by the first window that sees both;
dirty rows are never deleted, cleaning is recorded (ledger maintenance
rules).

### Split criteria and the cost of a split

Split criteria: a separately deliverable surface or component, a distinct
blocker set, or scope growth — **and, at the same time**, a different
actor or a different delivery. Without that second condition the default
answer is phases in one plan, not a new ticket.

The cost of a split is named, not assumed: its own design, plan, gate,
harvest, Jira comments, decision-registry rows, and a handoff — for every
ticket beyond the first. Every boundary between tickets is a place where a
ruling is lost, a finding is orphaned, or a conflict opens over a shared
file.

Doklad: doklad/epic-backflow.md, "Granularity"

### The per-ticket epic file

For a ticket that belongs to an epic, ONE file is the whole behaviour of
both backflow and handoff:
`memory-bank/epics/<epic_snake>/tickets/<TICKET>.md`. It lives on the
ticket branch and reaches the base by the same integration as everything
else in the ticket's own history — it can therefore never conflict, unlike
a shared `notes.md` on the base, which did (Doklad: doklad/epic-backflow.md,
"Granularity").

Header: `# <TICKET> — epic <EPIC>`. Two sections, each append-only:

- `## Backflow` — one line per finding:
  `- <YYYY-MM-DD> <nález> (zdroj: mb-epic-graph -Check)`.
- `## Předání` — one line per handoff:
  `- <YYYY-MM-DD> <sha> → <báze>; sada: <příkazy>; commity: <n>`.

The epic is identified from the Jira field `parent` (Jira mode) or from the
design header's `- **Epic:** <KEY>` line (Proposals mode). **A ticket with
no epic writes nothing and misses nothing** — no file exists for it, and
none is expected.

The epic's manager reads the file from the base by ref, never from a working
tree that may not carry it: `git show
<baseRef>:memory-bank/epics/<epic_snake>/tickets/<TICKET>.md` for one
ticket, or `git ls-tree -r --name-only <baseRef>
memory-bank/epics/<epic_snake>/tickets/` to enumerate every integrated
ticket's file at once.
