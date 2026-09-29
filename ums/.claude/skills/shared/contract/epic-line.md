# The epic line
Part of contract 3.x — the core is ../UMS_MEMORY_BANK_CONTRACT.md; cite as (contract/epic-line.md, "The epic line").

## The epic line

**The epic line is the code integration branch of an epic**, named
`epic/<EPIC-KEY>`, and it is the effective base of every ticket branch cut for
that epic. It carries code and the harvested documents of those tickets; the
epic's elaboration branch is a different branch and carries none of that. The
epic itself integrates one level further out, into the **delivery line** — the
shared branch the epic ultimately delivers into, and the base every ticket would
have had without an epic line.

**When two tickets share an interface, the epic line carries a stub of that
shared interface, committed before either ticket implements against it.** The
reason lives here, not in a skill: a stub turns the compiler into an oracle, so
a later merge surfaces a mismatch as a TEXTUAL conflict — the only kind git can
show — instead of a SEMANTIC one, which compiles clean on both branches alone
and fails only once they meet. Measured: the signature of `EmployeeResolver`
was recorded in the epic's ledger as prose, and it did not compile against what
the other ticket had written — a parameter too many, a different parameter
order, the wrong arity — caught only by chance, not by any mechanism.

**The stub is authored on a ticket branch, like any other work, and reaches
the epic line by the same integration as everything else** — after the
manager's `go`, pushed by the ticket that authored it; the manager never
authors the stub. Whose branch: the ticket that owns the interface, or, where
neither owns it, one created for it during elaboration. "Committed before
either implements against it" is therefore an ordering claim about the queue,
not a licence to write the stub directly onto the epic line.

**The epic line is an UNPROTECTED integration base, and `epicBranchPattern` is
what identifies it.** It is deliberately NOT in `protectedBranches`, and it is
the ONE named exception to the invariant of contract/repository-configuration.md
that an integration branch is always a protected branch: a branch that matches
`epicBranchPattern` is a legitimate base — offered among the base candidates and
chosen without the fail-closed STOP. **A protected epic line is UNSUPPORTED**: a
branch matching a protected pattern as well resolves as `protected`, never as
an epic line, so `mb-epic-run spawn` STOPs on it and the remedy is to remove it
from `protectedBranches`. **A missing key means the built-in default `epic/*`** — a
widening a human decided when this model was designed, so that an epic runs with
no extra configuration step. An explicitly empty, blank or non-string value
means **no epic line at all**, never "every branch": no exception, and a base
outside `protectedBranches` stays the fail-closed STOP. Every reader asks
`Test-UmsIntegrationBase` (`Kind` `protected` | `epic-line` | `none`) over
`Get-UmsRepoConfig`; nothing re-derives the answer by hand.

**What still guards the line is `pre-push`**, and nothing else: it bans deleting
a branch through a push and a non-fast-forward push on every branch it polices,
the epic line included, so only a fast-forward ever reaches it.
`guard-git-push.mjs` judges a push to the line like a push to any unprotected
branch; it grants no exception and reads neither `epicBranchPattern` nor
`baseRef`.

Doklad: doklad/epic-line.md, "Why the epic line is unprotected"

Doklad: doklad/epic-line.md, "The threat model"

**`mb-epic-run spawn` creates the line** when `origin/epic/<EPIC-KEY>` does not
exist yet, from the delivery line: `New-UmsEpicLine` fetches and pushes
`<delivery-line sha>:refs/heads/epic/<EPIC-KEY>`, a creation only — an existing
line is never moved. `spawn` records the delivery line in the header of the
epic's ledger (`- **Dodávková linie:** origin/develop`), and every ticket branch
of the epic has `Báze: origin/epic/<EPIC-KEY>`, which the spawn prompt names so
the entry gate's base choice has a recommendation rather than a guess.

**An epic line comes into being only where the tickets of an epic are not
individually deliverable into the delivery line**; where they are, every ticket
integrates on its own, as everywhere else. **And it ends:** the exit of the epic
into the delivery line is a human act (the Escalation floor), and so is deleting
the line after it — deleting a branch through a push is forbidden. Left behind,
every base choice keeps offering an unrelated epic's line as a base.

Doklad: doklad/epic-line.md, "What licenses an agentic write here"

**An unconfirmed decision-registry row naming the integrating ticket blocks the
manager's `go`, and the ticket's spawn row in the epic's own ledger must
belong to this epic** — enforced mechanically, ahead of the answer, by
`mb-epic-run`'s `integrate` operation.

**The decision registry** is the `## Registr rozhodnutí` section of the epic's
evidence ledger, and its rules live HERE rather than in the ledger template,
because three different actors act on them: the elaboration window that writes
a row, the ticket session that confirms one, and the manager's `integrate`,
which reads them.

- **Who writes a row.** A decision that rests on ANOTHER ticket's behaviour or
  code IS a row of that registry, naming that ticket in `Předpokládá o
  (tiket)`, with `Vlastník (tiket)` the ticket that took the decision. The
  elaboration window that took it writes the row (`mb-epic-elaboration`, its
  Impact on neighbors step), which is what makes the registry mechanical: the
  row exists by procedure, not because somebody remembered.
- **`Druh` decides what evidence may close the row**, and that is the column's
  whole job: a `text` row closes on a READING, a `chování` row closes on a
  TEST asserting that behaviour. Reading code proves its current value, never
  that it behaves the way the decision assumes.
  **This one is a DUTY on whoever supplies the SHA, not a check the gate
  performs, and it is stated so that the rule stops looking enforced.**
  `integrate` keys confirmation on a non-empty `Potvrzeno (SHA)` alone — a SHA
  is a SHA, and nothing in a commit identifier distinguishes a commit that adds
  a test from one that merely records a reading. The gate therefore reads
  `Druh` for nobody: it is rendered by `ledger-status` so a HUMAN or a manager
  reviewing the registry can see which rows owed a test, and it is that reader
  who catches a `chování` row closed on a reading. Do not add a mechanical
  check here in the belief that one is missing; there is nothing available to
  the gate to check it WITH, and a check that cannot tell the two apart would
  only move the false assurance one level down.
- **`Stav` runs `otevřeno` → `zavřeno`, and confirmation is not keyed on
  it.** A row closes only with a non-empty `Potvrzeno (SHA)`, whatever `Stav`
  says; a row whose `Stav` claims `zavřeno` over an empty SHA still blocks.
- **Who fills `Potvrzeno (SHA)`: the ticket named in `Předpokládá o
  (tiket)`**, with the SHA of ITS OWN commit carrying that evidence. That is
  also the ticket whose handoff the block fires on, so **the remedy belongs to
  that integrating session** and to no other. No commit of `Vlastník (tiket)`
  can satisfy a column defined as a commit of the assumed-about ticket, and that
  owner's session may be finished and closed; the owner is context to REPORT —
  whose decision is waiting — never the actor to wait for.

## Integration after the manager's go

**A ticket integrates into the epic line only after the manager's `go`, and the
push is the ticket's own.** The integration procedure is the one of
(contract/integration.md, "Integration"); on an epic line its Handoff and
Confirmation phases run in this order:

1. **Handoff.** The ticket session sends the handoff artifact to the epic's
   manager as a message and waits for the answer, the wait NAMED — the `NOW`
   block's `waiting-for-manager` where the block exists; in finishing, which has
   none, the report and the `## Předání` line of the ticket's epic file.
2. **The manager checks and pushes nothing.** `mb-epic-run integrate` runs the
   epic checks (`spawn-epic`, `decision-ack`), the cross-cutting judgement check
   over the epic's evidence and the Handoff gate re-run against the freshly
   fetched line.
3. **The manager answers — mandatory, one handoff, one answer.** `go` carries
   the epic-line tip the checks ran against; `STOP` carries the blocking check.
   The answer is a reply (contract/message-protocol.md, "Replies are required").
   After a `STOP` the ticket deals with the cause and sends a NEW handoff.
4. **On `go` the ticket pushes.** `git fetch origin`, then verify that
   `origin/epic/<EPIC-KEY>` still IS the tip the `go` names — if it moved, the
   `go` is spent: resynchronize (the Publish phase) and send a new handoff. Then
   `git push origin HEAD:epic/<EPIC-KEY>`, a fast-forward, and the Confirmation
   phase from the base.
5. **The ticket announces it.** An `Oznámení:` to the manager — the landed
   fast-forward and the line's new tip, checkable with `git fetch`; no reply.
   The manager writes the ledger note and prompts the other sessions to
   resynchronize: integration is a queue, one ticket at a time.

**Accepted residual risk: `go` is a rule of this contract, not a mechanism.**
Nothing mechanical binds what the manager checked to what reaches the line: the
hook lets any fast-forward from any agent session through onto the unprotected
line — without a `go`, or with a commit added after the handoff. The tip
verification of step 4 is the ticket session's DUTY, not a gate; a human
accepted this when the model was designed, and it is written here so that the
rule stops looking enforced.

Doklad: doklad/epic-line.md, "The residual risk: go is not enforced"
