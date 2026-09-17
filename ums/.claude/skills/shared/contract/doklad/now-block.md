# Doklad — The NOW Block
Part of contract 3.x — evidence read on demand, never the home of a rule.

## The block's two readers

**It has two readers and they take different items from it:** the session's
own successor after this one dies — that is where the SHAPE of the items comes
from — and the epic manager looking in from outside through `mb-epic-run
status`, which is where the state class and the due time come from. A block
written for only one of the two omits precisely what the other came for.

## Why an unparseable timestamp is malformed

**Why an unparseable timestamp is malformed rather than tolerated.** `dueAt`
and `late` are mandated outputs of the reader that renders this block, and
neither exists without a `Due:` it can parse; the two ways of tolerating one —
emitting a partial object, or a `late` that is null — are both forbidden by the
shape that reader must produce, so there is nothing left to degrade to. A
`Since:` that cannot be an instant is the same class of defect, and both get
the same fail-closed answer the state class already gets for a value outside
its enum.

## What does not carry over from the baton

**What does NOT carry over from the baton, and why** — the quantifier in
contract/now-block.md, in the reader-safety paragraph, is bounded on purpose. **Consume-on-read does not:** the baton is a one-shot
instruction renamed away the moment it is emitted, while the `NOW` block is a
STANDING artifact re-read on every look, and renaming a live progress ledger
would destroy the execution it reports on. Neither does the `Instruction`
skill-name validation, nor the `Branch`/`Slug` origin binding, nor the rule
that the reader exits 0 silently on every failure path: those are the baton's
DELIVERY and identity rules, owned by a `SessionStart` hook that must never
stop a session from starting. This block's reader is a status command and may
fail loudly like any other.
