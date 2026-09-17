# Epic Backflow
Part of contract 3.x — the core is ../UMS_MEMORY_BANK_CONTRACT.md; cite as (contract/epic-backflow.md, "Epic Backflow (design -> epic)").

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

**Queue the note, always.** Append a dirty-set row to the epic's ledger
(`<MB_ROOT>/memory-bank/epics/<epic_key_snake>/ledger.md`):
„Položka/Tiket" = this ticket, „Zašpiněno oknem" = `návrh <slug>` (the
dirt came from a design, not a window), „Důvod" = one line
`návrh <slug> změnil <co>; okno by mělo přehodnotit <co>`. When no ledger
exists, write the same line into
`<MB_ROOT>/memory-bank/epics/<epic_key_snake>/notes.md` (created with the
heading `# Poznámky pro elaboraci — <EPIC>`); the next elaboration window
reads it at framing time. The note is committed on the ticket branch like
any other commit of this work item — it is this work item's record, so it
legitimately rides the ticket branch into the base at integration.

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
