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
