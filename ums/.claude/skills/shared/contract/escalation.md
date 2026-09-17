# Escalation & Autonomy
Part of contract 3.x — the core is ../UMS_MEMORY_BANK_CONTRACT.md; cite as (contract/escalation.md, "Escalation & Autonomy").


Doklad: doklad/escalation.md, "Why the turn-ending rule's qualifier is exact"

**The quantity an operator DOES set is who decides which KIND of escalation.**
The list has three bands, and two of them are fixed.

**Every kind below has an artifact form, and the form differs by band because
what the escalation DOES differs.** The requirement is `## Message Protocol`'s —
that the design of an escalation band has an artifact form — and this is where
it is discharged, for all three bands.

- **For the two bands where somebody else decides while the work goes on, the
  form is a row with a state in a ledger.** Inside an epic that is a row of the
  epic's evidence ledger — an item row of `## Položky` with its owner and its
  state, the ticket's `## Rozjetí` row, or a `## Registr rozhodnutí` row where
  the question is another ticket's behaviour. Inside a plan's execution it is
  the SDD progress ledger: the open question while it is held, a `Ruling:` line
  once it is answered, and the `NOW` block carrying the WAIT. A state that
  outlives the turn is exactly what these two bands need, because a stranger
  must be able to pick the question up.
- **For the floor the form is the STOP itself and the report that names it**,
  and a row would be the wrong artifact rather than a missing one: these kinds
  are refusals to proceed, so there is no continuing work to carry a state
  about — what a reader needs is that the session STOPPED and why. Where the
  work is a plan in execution, the wait is additionally the `NOW` block's
  `waiting-for-human`, by the naming rule above. Fail-Closed Behavior owns the
  STOPs themselves; this band owns only the answer to "who is asked".

Doklad: doklad/escalation.md, "Why every band needs an artifact form"


Doklad: doklad/escalation.md, "The floor adds no new stops"

Doklad: doklad/escalation.md, "The last row of the floor is not distrust"

**Always the manager — and this band does not move DOWN**, because taking
precisely these off the human is what a manager is for:

| Kind | Measured example |
|---|---|
| The order and the queue of integrations | two tickets verified against the same epic tip |
| Resynchronization prompts and cross-cutting relay | "go and integrate the epic line" |

**The four classes of a conflict or a failed verification, and who owns each**

A merge conflict and a red build after a merge are classified before anything
is done about them, and the deciding question is ONE. It is deliberately not
"whose file is this?" nor "whose paths are these?" — a shared `.csproj` is on
everybody's path:

> **Whose WRITTEN decision would have to change for this to work?**

| Class | Recognised by | Owner | When it is reported |
|---|---|---|---|
| **1 — environment** | nobody's decision changes; the tree is fine, my workspace is stale | whoever merged | the ordinary report at a boundary |
| **2 — confluence** | the answer is "keep both"; both intents stand | whoever merged | the ordinary report at a boundary |
| **3 — a neighbour's decision** | another ticket's written decision would have to change, or its record was untrue | neither of them alone — **an escalation**, ruled in the movable band below | **immediately** |
| **4 — own defect** | my work is wrong and the merge only revealed it | whoever merged | the ordinary report |

**Class 1 has an OPERATION, not a judgement.** The first reaction to a red
build after a merge is ALWAYS **restore and a clean rebuild**, and only what
survives that is a finding at all. Both measured failures were exactly this
and both were cured by it. Deciding it by judgement is the trap: the same
symptom had two different causes in a single afternoon, so a session that
reasons about the cause before it has restored is reasoning about an artifact.
This is the operation that makes the table above usable — without it a session
cannot tell whether what is in front of it is a class-1 nuisance or a class-3
finding, which is precisely where both measured incidents were misclassifiable.

**Class 3 blocks unconditionally**, and it is the only one of the four handled
differently from the rest. The hard cap that goes with it, and it binds every
class: **whoever merges NEVER edits code outside their own plan's scope to make
the merge green.** Making it green that way converts a neighbour's decision
into an unrecorded one.

**The carrier of a class-3 ruling is an ARTIFACT, never a message** — this
section's artifact requirement applied to this kind: the epic's evidence ledger
(a `## Registr rozhodnutí` row where the question is another ticket's
behaviour) and a hint written into the affected ticket's `design_<slug>.md`.
A message may carry it sooner; it never carries it instead.

Doklad: doklad/escalation.md, "Why a class-3 finding is reported immediately"

**The movable band — this is the quantity**

| Kind | Measured example |
|---|---|
| A class-3 finding (the four classes above) | a 60 s TTL window hard-coded, with no configuration key |
| A scope or ownership conflict between tickets | whose `EmployeeResolver` is it |
| A defect in the plan — every way forward is a guess | a wiring brief wrong in six places |
| A change to a ticket's brief | the scope turns out to be somewhere else |

**Three named levels stand over that band, and nothing else about them is
configurable.** They are written into the ledger in Czech, like every other
ledger value, and named in English here (Language Contract):

| Level | Ledger value | Who decides the movable kinds |
|---|---|---|
| Supervised | `dohled` | all of them the human; the manager coordinates |
| Shared (the DEFAULT) | `sdílená` | the manager rules scope conflicts, class-3 findings and plan defects; a change to a ticket's brief goes to the human |
| Delegated | `delegovaná` | the manager rules a change to a ticket's brief as well, and reports it |

**Where there is no epic there is no manager**, and the bands say so rather
than leaving it to be worked out: the middle band is then empty, the movable
band has only two owners left — the session's own ruling and the human — and
the three levels do not exist at all, because they are an epic's declaration.
Nothing here weakens the floor, which binds every session either way.

**Where the value is read.** The epic declares it ONCE, in the header of its
evidence ledger (`- **Autonomie:**`); the ticket's `## Rozjetí` row carries a
column that overrides it for that one ticket, `—` meaning no override. A ledger
that declares nothing is `sdílená`. The session PULLS the value out of the
committed documents — the manager writes nothing into the slot — which is the
same pulled-row rule the spawn line already follows.

**One thing deliberately does NOT belong in this list.** An instruction that
contradicts a written rule is not an escalation — it is a LOOKUP. The
recipient's duty to refuse such an instruction, and its right to refuse a
conjecture, are `## Message Protocol`'s and are not repeated here; what belongs
HERE is the consequence for this list. A refusal settles itself against the
text of the rule and costs nobody a decision, so it is no band's business.
Only where the rule is GENUINELY ambiguous is there a question at all, and that
question goes to the HUMAN, never to the manager — the manager is a party to
that dispute.

### Ledger evidence rules

**(a)** A failing-test floor is a set of NAMES, never a number. A row that
promises "names will follow" is a dirty row until the names arrive —
`ledger-status.ps1` reports it as such.

**(b)** Every measured number in the ledger carries its run conditions: the
tree, a clean vs. a batch hub run, and the date.

**(c)** A ruling that defers work onto another ticket is a dirty-set row owned
by THAT ticket, and it names what happens if that ticket finishes first.
`mb-epic-run integrate` and the Handoff gate print open rows naming the
integrating ticket.

**(d)** The ledger's header carries `Ověřeno proti: <branch>@<sha>, <datum>`,
and a ticket description's mirror carries the same fetch stamp.
