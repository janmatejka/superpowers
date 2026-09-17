# Integration & Abandon
Part of contract 3.x — the core is ../UMS_MEMORY_BANK_CONTRACT.md; cite as (contract/integration.md, "Integration").

### Integration

Integrating finished work is a **fast-forward push of the ticket branch onto the
base ref**, not a local merge into a local base branch. The base has already been
merged into the ticket branch at the last phase boundary (Base Sync & Drift
Detection), so the ticket branch is a descendant of `<effective base>` and the
push is a fast-forward. `<effective base>` below is always the resolved base of
this work item (Repository Configuration, "The effective base of a work item"),
never the raw `baseRef` configuration key.

**ONE procedure, whatever the effective base is.** A delivery line, a maintenance
branch of a release series and an epic line (Repository Configuration, "The epic
line") are integrated through the same phases in the same order. **Every phase
below runs for every base**, and the question "is the base an epic line?" is
asked exactly TWICE — in the Sync phase, to pick the HOME the declared
verification set is read from, and in the Handoff phase, to pick the RENDERING
of the artifact. Neither adds, removes or reorders a step, and they are not two
independent conditions: **both read the ONE base resolution made once, before
the sequence starts** (the effective base and the `epicBranchPattern` match
derived from it). One derivation, consulted twice, is what keeps this a single
procedure; a THIRD site asking the same question — or either of these two
re-deriving the answer for itself — would not be, and the test named in the
design's verification point 3 exists to turn red on exactly that.
The phases, in order:

- **Sync.** `git fetch origin`, then `git merge <effective base>` on the ticket
  branch. **The declared verification set (fourth check of the Handoff gate
  below) is resolved in THIS phase**, in whichever of its homes applies:
  the Harvest phase deletes the plan and archives the design, and both are
  homes, and a set learned after the Green verification has run cannot be the
  set that run measured.
- **Harvest.** The knowledge harvest and the IDLE reset of `context.md` (Harvest
  Contract; in `finishing-a-development-branch` it is the UMS Harvest Gate),
  committed on the ticket branch. It precedes the Handoff gate because that
  gate's context check is what the reset leaves behind.
- **Publish.** `git fetch origin` and `git merge <effective base>` once more —
  the base may have moved while the harvest ran — then the agent pushes its own
  ticket branch, announcing the outgoing commits: the publication rule, as after
  every commit.
- **Green verification.** The declared verification set, run VERBATIM and in
  its declared order, on the merged tree. That run is what "green" means for
  this work item, and its commands are what the Handoff artifact cites;
  running a build and tests chosen here instead, and then citing the declared
  set, is precisely the incomparability the set exists to remove.
- **Handoff gate.** Four checks, and they run as one mechanical check rather
  than as items somebody ticks off, **after a fresh `git fetch origin`** —
  against the freshly fetched `<effective base>`, never against a tip
  remembered from the Sync phase. A remembered tip passes in exactly the case
  the gate exists for, and whoever pushes is then handed a command that
  bounces:
  1. `git merge-base --is-ancestor <freshly fetched base> <sha>` — the commit
     being handed over carries the CURRENT base;
  2. the `context.md` of that same commit is IDLE, which is what the harvest's
     reset leaves behind (Harvest Contract) — so the harvest precedes the
     handoff. Resolve `<CTX_DIR>` per its definition (`<MB_ROOT>/memory-bank/`),
     never from a path unrelated to `MB_ROOT`, and use this contract's own
     predicate (`context.md` Schema & Writers): a `Target MB Pin` together with
     a `Work item` slug is ACTIVE. A
     **missing file is a fail-closed STOP, not "IDLE"** — `git show` on a path
     that does not exist exits 128, and that exit reads all too easily as "no
     pin found";
  3. `<sha>` is reachable on `origin`. The hook enforces this at push time
     anyway; the gate carries it so the error arrives earlier and legibly.
  4. the commands the Handoff artifact is about to quote match, AS TEXT, the
     verification set declared for this work item. **The verification set is
     a verbatim list of commands, one per line inside ONE FENCED code block,
     declared once**, and its home is whatever umbrellas the work:
     - **a ticket that belongs to an epic** — the epic's own ledger, section
       "Ověřovací sada", declared once for the whole epic so every ticket
       measures the identical thing. **That ledger is on the epic's
       ELABORATION branch**, `memory-bank/epics/<epic_key_snake>/ledger.md`,
       and a ticket branch does not carry it: a ticket branch is cut from the
       epic LINE, which carries code and harvested documents and none of the
       elaboration branch's documents ("The epic line"). The ticket session
       therefore reads it BY REF — `git show <elaboration branch>:<that
       path>` — after a fetch, never from its own working tree, where the
       path does not exist and its absence would read as "nothing declared".
       Name the branch wherever this path is named; the branch is a value the
       session was given (`mb-epic-run`'s spawn prompt names branch and path
       together) or asks the epic's manager for.
     - **anything else** — **the work item's own plan, under that SAME
       heading, `## Ověřovací sada`, in the SAME shape**. This is not an epic
       peculiarity; work outside an epic declares a set too, just with the
       plan as its home instead of a ledger. A plan written before this rule
       existed declares its set the same way any plan does — by gaining that
       section — and until it does, the missing-set case below is fail-closed
       exactly as stated, no differently for an old plan than for a new one.
     - **a BOUNDED work item, which writes no `plan_<slug>.md` at all**
       (Brainstorming Paths) — **its `design_<slug>.md`**, under that same
       heading and in that same shape. Bounded is the one path whose plan
       half legitimately does not exist, and the design half always does:
       Brainstorming Paths requires the approved short design to be WRITTEN
       to `<PLAN_MB>/proposals/active/design_<slug>.md` precisely so that
       "harvest, integration, Jira and the archive work unchanged", and this
       is that sentence continued rather than a new rule. **There is no
       bounded exemption**, and the reason is the one stated below for the
       missing-set case: a work item whose handoff artifact quotes output
       with nothing to compare it against measures a different "green" every
       time, and nothing about a small change makes its reader need less.
       Resolution stays in the Sync phase for the same reason it does for a
       plan — the Harvest phase archives the design to `proposals/completed/`.
     **The shape, in all three homes, is one FENCED code block under that
     heading, one command per line** — that is what the single reader
     (`Get-UmsLedgerVerificationSet`) parses, and a bulleted or plain list
     under a correct heading yields NOTHING and reads downstream as "no set
     declared at all", which is a fail-closed STOP whose stated reason would
     then be false.
     The comparison is TEXTUAL, not semantic: equal strings in equal order,
     never normalized and never reordered, because the entire point is that
     two measurements of "green" are measuring the identical thing. The check
     activates only where a set IS declared — with nothing declared there is
     nothing to compare against, so it is skipped rather than fabricating a
     pass or a fail — but resolving the set happens EARLIER, in the Sync
     phase, and **a missing declared set at that resolution step is itself
     fail-closed** (Fail-Closed Behavior): the first integration of a ticket
     whose umbrella declares no verification set at all is a STOP, not a
     silent pass, because without one, "green" means something different every
     time and the Handoff artifact would then quote output with nothing to
     compare it against.
- **Handoff.** ONE artifact — the destination branch, `<sha>`, the enumerated
  outgoing commits, and the commands the **Green verification** phase ran —
  the declared set — quoted verbatim **with their output**, the SAME commands
  in the SAME order that the Handoff gate's fourth check just compared as text
  against that set — so "verified" is a claim the reader can compare rather
  than an assurance. It has **two
  renderings**, and the SECOND of the procedure's two readings of the one base
  resolution decides between them — **is there a manager?**, answered by
  whether the effective base is an epic line. It picks a rendering and never a
  step; the first reading, in the Sync phase, picks a HOME and likewise never a
  step:
  - **no manager** → the artifact is rendered as the PLAIN human command with the
    outgoing commits enumerated (per the two spellings above). The user runs it:
    the base is a protected branch and the moment of integration belongs to the
    human, so the agent never pushes it itself, not even as the fast-forward the
    `pre-push` hook would accept.
  - **a manager** → the artifact is rendered as a message to the epic's manager,
    the session holding the epic's elaboration branch, who performs the
    fast-forward under the actor-rule exception ("The epic line"). Only a manager
    performs that fast-forward; where there is none, no agent does it either and
    the artifact falls back to the human-command rendering above. **The manager
    owes the handing-over session an answer on both outcomes** — landed: the
    target branch and the new tip SHA; STOP: the blocking check — because that
    session's Confirmation phase is gated on it and never runs without it.
- **Confirmation.** After the push lands — whoever ran it — the TICKET session,
  on the ticket's own branch, re-verifies reachability **from the base ref**:
  `git fetch origin`, then `git merge-base --is-ancestor <sha> <effective base>`
  (non-zero exit = not on the
  base). A bare `git branch -r --contains <sha>` is NOT sufficient here — the
  publication rule has already pushed that commit to the ticket branch on
  `origin`, so `--contains` reports the ticket branch, the result is non-empty and
  the check passes while the base carries none of the code. That is exactly the
  state this phase exists to catch: the push was never run, or it was rejected
  as non-fast-forward and nobody retried. The check must name the base, and it
  must run with **no** Jira ticket too — `mb-jira-update`'s own gate does not
  exist then.
- **`mb-jira-update` finalization**, in that same ticket session on that same
  branch, whoever performed the push. The ticket's life cycle runs on the
  ticket's own branch, so a push performed by somebody else moves nothing about
  where the finalization belongs.

A push rejected as **non-fast-forward** means the base moved while the procedure
ran: repeat from the Publish phase. **At most two failed rounds** — after the
second, STOP and report to the user instead of racing the base indefinitely.

The ticket branch left behind on `origin` is **not deleted** (deleting a branch
through a push stays forbidden) and it is not reported as a collision: the
document index keys by phase, so an integrated ticket's branch no longer counts
as active work.

### Abandon

Abandoning a work item is the other way it ends on a ticket branch, and it is
**published like any other outcome**. The sequence is the same whichever door it is
reached through — the `mb-abort` skill, or Discard in
`finishing-a-development-branch`:

1. move BOTH halves of the pair to `proposals/abandoned/`, unchanged, deleting
   nothing (Active Work Item, archival asymmetry),
2. reset `context.md` to IDLE (see the `context.md` Schema & Writers section),
3. **commit** that move and **push** it — the ticket branch is the actor's own, so
   the agent pushes it and announces the outgoing commits; a shared current branch
   is the user's command, as everywhere,
4. only where a branch is actually being left behind: detach
   (`git switch --detach <baseRef>` — git cannot delete the branch that is
   checked out, and a ticket workspace has no local base branch to return to) and
   delete the **local** branch. The remote branch is never deleted.

Step 3 is the step that is not obvious and therefore the one that gets skipped. An
abandon that is not published exists only in the local `.git` that performed
it (a pool slot shares that `.git` with every other slot, so the commit is
visible there too) — but never on `origin`: the branch still carries the
ACTIVE pin there, with the pair still in `active/`,
so `mb-doc-index` keeps reporting that slug and that ticket as active work — a
`KOLIZE AKTIVNÍ PRÁCE` no later session can clear, which means the ticket can never
be picked up again. The exemption granted to an integrated branch does not help
here: the index keys by phase, and `abandoned/` is not an active phase.

`mb-abort` performs steps 1–3 and deletes no branches; step 4 belongs to the
finishing Discard path, which is the caller that ends the branch as well as the work
item.
