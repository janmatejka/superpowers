# Message Protocol
Part of contract 3.x — the core is ../UMS_MEMORY_BANK_CONTRACT.md; cite as (contract/message-protocol.md, "Message Protocol").


**`instruction` here is the MARK, and it is a different thing from
`Instruction`, the required key of the Session Intent Baton.** The baton's
`Instruction` is a key of a CLOSED, validated format and its value names a
skill to invoke; this section's `instruction` is one of two values a `Mark:`
line may carry, and it classifies what a message asserts. `Mark:` is the
spelling precisely so nothing mechanical can confuse them — no reader of either
one ever sees the other's spelling — and the two senses are named apart here so
they cannot drift into one.

**A cause is ALWAYS a conjecture; a boundary MAY be an instruction.** "May",
because a boundary the sender does not own — one that belongs to the user, or
one a written rule decides differently — is a conjecture too. An UNMARKED
message is read as a conjecture, and so is a message whose content contradicts
its own mark: `Mark: instruction` over an explanation of a cause is a
conjecture whatever its first line says.


Doklad: doklad/message-protocol.md, "The measured case behind the cause rule"

**Relay timing is decided by IMMEDIACY, not by importance.** Send a change of
premise immediately ONLY when the recipient is acting on that premise right
now; otherwise hold it until a boundary — a point where that session reports
anyway, the end of its current task or a phase boundary, whichever comes
first. A change that matters enormously but
touches nothing the recipient is doing this minute waits for the boundary, and
a small change to the premise under its current step does not.

**Two things are measured as actively harmful, so they are named rather than
left to judgement.** The first is prodding a session that is WAITING ON A
SUBAGENT: it cannot act until the subagent returns, so the message buys nothing
and costs the interruption. The second is re-arming a "notify when idle" style
subscription after every message — it overwrites its own slot in the
subscription table, so the orchestrator ends up with one notification where it
believed it had armed several. The rule that replaces it: **one live
subscription per peer, renewed only after it has fired.**

**Resynchronization is PULLED, never pushed.** "Go integrate the epic line" is
a nudge and never a delivery guarantee: a ticket session merges its own
effective base at every phase boundary itself, and merging the base in the
MIDDLE of a task is forbidden (Base Sync & Drift Detection). A message
therefore speeds the order up; it does not establish it, and no message
legitimately produces a mid-task merge. An orchestrator that needs a session to
stand on a newer base waits for that session's next phase boundary.

**Every escalation band must have an ARTIFACT form, and a message is an
acceleration over that artifact, never the artifact itself.** `SendMessage` and
`ListAgents` are tied to a single harness and are used NOWHERE in this layer
today, so a rule that lived only in a message would have no addressee at all on
another one. The state therefore stands in an artifact every harness can read
and write — a ledger row, the `NOW` block, the report at a phase boundary — and
the message only gets it there sooner. What a harness without messaging loses is
then SPEED, not correctness, which is what "fail-closed, not broken" means here.

**Nothing in this section has a mechanical trigger, and its rules are listed one
by one so that no skill writes them down as though a hook checked them.** It is
measured in this project that a rule with no trigger gets broken even by its own
author, so the status of each is stated instead of implied:

- **Recommendations** — nothing detects a breach and nothing fails when one
  happens: marking a message at all; WHICH of the two marks is right ("a cause
  is ALWAYS a conjecture; a boundary MAY be an instruction"); the relay-timing
  rule; one live subscription per peer; not prodding a session that waits on a
  subagent; and "a nudge is not a delivery guarantee". The mark-choice rule is
  the sharpest thing in this section and is therefore the likeliest to be
  re-encoded downstream as an enforced gate. It is not one, and there is
  nothing in this layer to enforce it with.
- **A right of the recipient**, exercised by the recipient alone and never
  granted message by message: refusing a conjecture.
- **A reading default of the recipient**, applied by it and by nothing else: an
  unmarked message — and one whose content contradicts its own mark — is read
  as a conjecture.
- **Duties of the recipient**, just as undetected and just as binding on it:
  refusing an instruction that contradicts a written rule, and keeping a
  conjecture out of the ledger as fact.
- **A requirement on the DESIGN of an escalation band**, checked when the band
  is written and never at runtime: that the band has an artifact form.
- **A bound on the scope of everything the core's `## Message Protocol` states,
  rather than a rule of its own:**
  the other direction carries no mark, so none of the duties, rights and
  defaults listed here attach to a report, a correction or a handoff artifact
  travelling back up.
- **Rules named here that ARE binding — and are binding somewhere else:**
  - the ban on merging the base in the middle of a task belongs to Base Sync &
    Drift Detection and holds whatever any message says; what this section adds
    about it — that a nudge does not establish the order — is a recommendation,
    the ban is not;
  - the mark being WRITTEN in English and RENDERED to the user as *pokyn* /
    *domněnka* belongs to the Language Contract, which decides the language of
    every artifact in this layer; what this section adds is only which token a
    message carries.
