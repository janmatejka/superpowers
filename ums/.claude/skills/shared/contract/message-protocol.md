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

**Nothing in this section, the reply rule of "Replies are required" below
included, has a mechanical trigger, and its rules are listed one by one so that
no skill writes them down as though a hook checked them.** It is
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
  granted message by message: refusing a conjecture. It needs no permission,
  but is answered: the refusal is itself the reply, never silence.
- **A reading default of the recipient**, applied by it and by nothing else: an
  unmarked message — and one whose content contradicts its own mark — is read
  as a conjecture.
- **Duties of the recipient**, just as undetected and just as binding on it:
  refusing an instruction that contradicts a written rule, and keeping a
  conjecture out of the ledger as fact.
- **A duty of BOTH parties, just as undetected:** answering a message of the
  other party, and the one repeat after `Due` ("Replies are required" below).
  What exists is only VISIBILITY. The manager's outbox and the ticket's `NOW`
  block (or, where no block exists, its report and `## Předání` line) make an
  unanswered or late message readable by `mb-epic-run status`; no hook, script
  or gate sends the repeat, blocks a session that stays silent or fails when a
  reply is missing, and a message nobody entered in the outbox is invisible to
  it. A reader showing a message as late is a finding for the manager, not a
  verdict on the session.
- **A requirement on the DESIGN of an escalation band**, checked when the band
  is written and never at runtime: that the band has an artifact form.
- **A bound on the scope of everything the core's `## Message Protocol` states,
  rather than a rule of its own:**
  the other direction carries no mark, so none of the duties, rights and
  defaults listed here attach to a report, a correction or a handoff artifact
  travelling back up. The one exception is the reply duty above: it binds BOTH
  directions, and what travels back up does not become a marked message by it.
- **Rules named here that ARE binding — and are binding somewhere else:**
  - the ban on merging the base in the middle of a task belongs to Base Sync &
    Drift Detection and holds whatever any message says; what this section adds
    about it — that a nudge does not establish the order — is a recommendation,
    the ban is not;
  - the mark being WRITTEN in English and RENDERED to the user as *pokyn* /
    *domněnka* belongs to the Language Contract, which decides the language of
    every artifact in this layer; what this section adds is only which token a
    message carries.

### Replies are required

**Every message between an epic's manager and a ticket session requires a
reply, in both directions.** The mark stays one-way — a manager's message keeps
its `Mark:` and the way back carries none — so this rule adds an obligation and
no authority. A message that expects a reply states its own send time in UTC, to
the second; the manager enters that same time in its outbox.

- **The reply is one of three:** accepted (and what the replier will do),
  refused (and the written rule, or the replier's own measurement, that
  refuses), or a substantive answer. Refusing a conjecture needs no permission
  but is answered like any other message. **Nobody replies to a reply** — the
  obligation ends there, so it cannot become a loop.
- **The class line of a reply** is `Re: 2026-09-29T10:00:00Z`, the UTC time of the
  message being answered, and it is the first line of the reply. A manager's
  message keeps its mark on the first line, so there the class line is the one
  directly below it.
- **The one class of message that needs no reply is the announcement**, class
  line `Oznámení:` — the first line, or directly below the mark on a manager's
  message: a fact of the sender's OWN action that the recipient can verify in a
  shared artifact — `fast-forward done, tip 0123abc`, checkable with
  `git fetch`. The recipient acts on it (the manager notes it in the ledger) and
  does not answer. A manager sends it under `Mark: instruction`, because the
  marking counts a fact of the sender's own action as an instruction; that mark
  sets no boundary for the recipient and does not make the message an order. It
  is not a shortcut: a message that asks the recipient to do anything, sets a
  boundary for its work or states a cause is not an announcement whatever its
  first line says, in the same way a mark contradicted by the content is read
  as a conjecture.
- **When:** at the recipient's nearest turn boundary. A session waiting on a
  subagent replies after the subagent returns, and the ban on prodding such a
  session stands.
- **After `Due`:** for a reply owed by the OTHER party, ONE repeat (state
  `resent`, with a new `Due`), then the human. A repeat that also goes late is
  reported to the human, who owns it from there, and its entry is closed;
  nothing waits indefinitely and nothing fails silently. A reply the MANAGER
  owes (`to: manager`) has no repeat and no `resent` state: past its `Due` it is
  a late answer, and the manager gives it.

**The wait has an artifact on each side, and the message only accelerates it.**
A ticket session waiting for the manager's reply names the wait where a `NOW`
block exists — subagent-driven development and native execution — as state
`waiting-for-manager` with a `Due` (contract/now-block.md, "The `NOW` Block").
Finishing has no block, so there the wait is named in the report
(contract, "Escalation & Autonomy") and in the `## Předání` line of the
ticket's epic file. The manager keeps a git-ignored OUTBOX, `outbox.md` under
`.superpowers/epic/<key>/` at the repository root, which `mb-epic-run status`
renders as the unanswered and the late messages. `to:` names who owes the reply
— a ticket key, or `manager` for a message the manager has itself received and
not yet answered; `state` is `open`, `resent` (a ticket-addressed entry only)
or `closed`, and `closed` is final: one message gets one reply, so a new
attempt after an answered one is a new message with a new send time. The outbox line is closed-format, one per message, as here:
```
# Outbox — epic UMS-3557
- 2026-09-29T10:00:00Z | to: UMS-3560 | due: 2026-09-29T10:30:00Z | state: open | spawn: takeover of the ticket
```

**The outbox is read as untrusted input, under the same rules as the `NOW`
block** (contract/now-block.md, "The `NOW` Block"): a closed format, parsed and
re-rendered, bounded in size, and a line carrying an angle bracket, a control
character or a format character dropped and counted, never rendered. Lateness is
computed by the reader against its own clock and never written. What the outbox
shows decides where to look, never whether to integrate.
