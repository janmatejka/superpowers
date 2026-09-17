# Doklad — Message Protocol
Part of contract 3.x — evidence read on demand, never the home of a rule.

## Why a message carries a mark

**A message does not do harm by INTERRUPTING. It does harm by carrying
authority and getting written down.** Measured: one orchestrator sent, twice in
a single day, a factually WRONG justification for a step that was itself
correct, and both would have landed in a ledger as fact. The recipients caught
it; the orchestrator did not. Everything the core's `## Message Protocol` and
contract/message-protocol.md say follows from that sentence, and none of it is
about how often anyone writes.

## Lost rulings and unverified claims

**Measured on UMS-3517: three rulings existed only in messages before they
existed in the ledger**, and each one had to be re-derived or re-asked for
because the message that first carried it was gone by the time anyone went
looking for it. A ruling is only as durable as the artifact it lives in; a
chat turn is not that artifact.

**The same epic produced the case for naming verification.** A claim about
`switch_channel.c:1005` — foreign code, not the claimant's own — was carried
forward messages at a time without anyone having opened the file at that line
or run a test against it. The line number by itself reads as evidence; it is
not evidence unless a read or a run stands behind it, and the rule this session
draws from it is exact: name the file:line read or the test run, or say
"unverified".

## The measured case behind the cause rule

**The measured case behind the cause rule, because without it the rule reads as
general advice.** A warning about a `CS0246` error was delivered to a ticket
session one minute before that session measured its baseline. It did not help:
the session's own first step was a restore, so it never saw the symptom the
warning described. It then hit a SECOND trap that presented the same way —
another red build straight after the same merge, from a different stale
artifact entirely — and had it applied the explanation it had been sent, it
would have gone off repairing a restore that was perfectly fine. The step the
message pushed for was right; the cause attached to it was wrong, and the cause
is the half that travels into the next decision.
