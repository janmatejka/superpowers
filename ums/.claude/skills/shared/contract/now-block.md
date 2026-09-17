# The NOW Block
Part of contract 3.x — the core is ../UMS_MEMORY_BANK_CONTRACT.md; cite as (contract/now-block.md, "The `NOW` Block").

### The `NOW` Block

**The `NOW` block records what is being WAITED ON RIGHT NOW**, so that a
stalled session is visible without anyone reading its transcript. **It is not
a second Session Intent Baton:** the baton carries what a NEW session must do
after a restart, the block carries what the CURRENT session is waiting for.

**It lives at the top of `.superpowers/sdd/<plan-basename>/progress.md`** —
the SDD progress ledger that Fail-Closed Behavior already names as legal
git-ignored scratch — directly under that file's title line, exactly one
marker pair per ledger; a second pair is not a variant but a malformed block
(Marker behaviour below). It is AI-facing scratch and therefore English
(Language Contract), its state class included; `mb-epic-run status` translates
on render, the same translate-on-presentation split as `Ruling:` lines.

**It has two readers and they take different items from it:** the session's
own successor after this one dies — that is where the SHAPE of the items comes
from — and the epic manager looking in from outside through `mb-epic-run
status`, which is where the state class and the due time come from. A block
written for only one of the two omits precisely what the other came for.

**The boundary is MACHINE, not a heading**, and that is the first rule:
comment markers, because a section inserted before a TEXTUAL anchor once
landed inside the very paragraph that talked about that anchor. Prose between
the markers that looks like a heading therefore changes nothing — the region
is the markers and only the markers.

**Rewriting the block is an OPERATION, and that operation stands in this same
paragraph as the artifact deliberately: it is measured that the shape gets
taken over without the rule, and the block falls behind within the hour. The
operation is: DELETE everything between the two markers, then RECONSTRUCT the
six items from `git log`, the plan's task table and the ledger's ruling index
— never "write it again" over the text standing there. From an empty region
there is nothing to append to, which is the entire reason for deleting first.
And the necessary condition that makes reconstruction possible at all: the
block is NEVER the only home of any fact.** This is the artifact:
```
<!-- UMS-NOW BEGIN -->
State: waiting-for-subagent
Waiting on: implementer of task 12, dispatched, no report yet
Since: 2026-09-07T09:12:00Z
Due: 2026-09-07T09:42:00Z
Task: 12 — Handoff gate, the three universal checks
Look at: .superpowers/sdd/plan_ums_3505/task-12-brief.md; git log -3 --oneline
<!-- UMS-NOW END -->
```

**Six items, all six required, one `Key: value` line each, in this order.**
The key is everything before the first colon; the value is the rest of the
line, trimmed. A missing item, an unknown key, a line outside the `Key: value`
shape, a duplicated key, or a `Since:` or `Due:` whose value is not a valid
ISO-8601 UTC timestamp makes the block malformed. **A BLANK line inside the
region is SKIPPED, not malformed** — the region is bounded by its markers and
not by its content, so a writer may keep the six lines clear of them; the
Session Intent Baton's reader already skips blank lines the same way, and this
reader inherits that behaviour rather than inventing a second one.

- **`State:`** — the state class, one of the four values below and nothing
  else.
- **`Waiting on:`** — the awaited thing named concretely enough for a stranger
  to act on it: which subagent, which question and to whom, which decision of
  the manager. Never a mood and never "work in progress".
- **`Since:`** — ISO-8601 UTC, when THIS wait began.
- **`Due:`** — ISO-8601 UTC, the expected time of the next report. Lateness is
  COMPUTED by the reader against its own clock and is never written into the
  block; a written lateness would be a fact whose only home is here.
- **`Task:`** — the plan task in flight: its number, an em dash, then its
  title, copied from the plan's task table — `Task: 12 — Handoff gate`, an em
  dash and never a comma, so a title carrying a comma of its own stays
  readable. The separator is the WRITER's problem and never the parser's: the
  value is everything after the first colon, trimmed, and no reader splits it
  further.
- **`Look at:`** — where the next reader looks FIRST: paths and git refs,
  separated by `; `. Pointers only, which is what keeps this item from
  becoming the home of a fact.

**Why an unparseable timestamp is malformed rather than tolerated.** `dueAt`
and `late` are mandated outputs of the reader that renders this block, and
neither exists without a `Due:` it can parse; the two ways of tolerating one —
emitting a partial object, or a `late` that is null — are both forbidden by the
shape that reader must produce, so there is nothing left to degrade to. A
`Since:` that cannot be an instant is the same class of defect, and both get
the same fail-closed answer the state class already gets for a value outside
its enum.

**The state class is a CLOSED enum of exactly four values.** This is the
`idle` ambiguity a manager guessed wrong four times; it is an enumerated
field, not prose, and any other value makes the block malformed:

| Written in the block | Rendered by `mb-epic-run status` | `Waiting on:` |
|---|---|---|
| `stalled` | stojím | `nothing outstanding` and what would unblock it |
| `waiting-for-subagent` | čekám na subagenta | the subagent and its task |
| `waiting-for-human` | čekám na člověka | the question and to whom it went |
| `waiting-for-manager` | čekám na správce | the decision asked of the manager |

**`stalled` must be WRITABLE, or the artifact fails at the one thing it exists
for.** It is the honest value when nothing is running and nothing has been
asked, so a session that CAN name what it waits for must never write it — but
all six items stay required, and a stalled session that simply left one out
would render as NO BLOCK, which is precisely the invisibility this block
exists to prevent. Its two values are therefore fixed rather than left to
invention: `Waiting on:` opens with the literal `nothing outstanding`,
followed by ` — ` and what would unblock the session — never empty, never a
mood, never "work in progress"; and `Due:` keeps its ISO-8601 UTC spelling but
means the time the STALL IS TO BE RE-CHECKED rather than a promised report —
never empty, never `-` and never `unknown`, so lateness still computes and a
stall nobody came back to goes late by itself.

**The trigger is structural, and that is the fourth rule:** the next dispatch
is composed FROM this block, so a block nobody rewrote is a dispatch nobody
can compose. The control sentence: **when the block and `git log` disagree,
the block is wrong.**

**Reader safety is the baton's SAFETY rules, named rather than restated.**
`pool-status.ps1` parses this git-ignored file in a FOREIGN working tree — one
that implementer subagents write into routinely — and `mb-epic-run status`
renders the result into the manager's context. That is the exposure the
Session Intent Baton already has, so the READER-SAFETY rules of that
subsection apply here unchanged and are not re-derived: the format is CLOSED,
the reader NEVER emits what it read as it lies but parses it and RE-RENDERS
it, it bounds the size of what it reads and of what it renders, and it rejects
a value by CHARACTER CLASS rather than by any one tag's spelling.

**Those rules bind everything a reader emits OUT OF THIS FILE, not only the
marker region.** The untrusted thing is the FILE — a git-ignored ledger in
someone else's working tree — and never one field of it, so ANY other excerpt
a reader lifts out of the ledger and renders into a human's or a model's
context (the last line, a heading, a ruling, a count) passes the same parse,
re-render, size bound and character-class check as the block itself. A reader
that sanitizes the block and then emits a raw line from three lines below it
has sanitized nothing.

**What does NOT carry over from the baton, and why** — the quantifier above is
bounded on purpose. **Consume-on-read does not:** the baton is a one-shot
instruction renamed away the moment it is emitted, while the `NOW` block is a
STANDING artifact re-read on every look, and renaming a live progress ledger
would destroy the execution it reports on. Neither does the `Instruction`
skill-name validation, nor the `Branch`/`Slug` origin binding, nor the rule
that the reader exits 0 silently on every failure path: those are the baton's
DELIVERY and identity rules, owned by a `SessionStart` hook that must never
stop a session from starting. This block's reader is a status command and may
fail loudly like any other.

**Marker behaviour is defined rather than left to chance.** The region runs
from the FIRST begin marker to the FIRST end marker after it. A further begin
marker inside that region, or a begin marker with no end marker after it,
makes the block MALFORMED. A duplicated end marker after the region lies
outside it and is ignored. **A SECOND COMPLETE PAIR anywhere in the file also
makes the block malformed**, and that is the fail-closed answer on purpose: a
second pair is the signature of a writer that APPENDED instead of rewriting,
so the first pair is stale while the second may be a fragment, and neither can
be shown to be the current one — rendering either would produce a confidently
stale block, the failure that once claimed a running review for hours.
**A malformed block is treated exactly as an ABSENT one** — no block, no
error, nothing rendered — and absence sends the reader to go and look at the
slot, which is what this block is for.

**The boundary the block must never cross: it decides WHERE TO LOOK, never
WHETHER TO INTEGRATE.** It once claimed a running final review for hours after
that review had come back with four Critical findings. The fast-forward rests
on the Handoff gate and on the checks of `mb-epic-run integrate` (Publication
Contract, "Integration"), and on nothing this block says.

**Where the block does NOT exist, and that is a limitation rather than a
property.** Its home is deleted when subagent-driven-development finishes, and
`pool-status.ps1` renders it only while the slot carries an ACTIVE pin. During
brainstorming, writing-plans, design review and the whole of finishing —
integration included — there is therefore NO block. A rule about ending a turn
may name the block only where the block exists; elsewhere the wait is named in
the report instead. Giving the block the lifetime of a work item is a
follow-up item, not part of this contract.
