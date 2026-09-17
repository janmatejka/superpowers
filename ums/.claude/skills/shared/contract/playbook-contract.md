# Playbook Contract
Part of contract 3.x — the core is ../UMS_MEMORY_BANK_CONTRACT.md; cite as (contract/playbook-contract.md, "Playbook Contract").

### Playbook Contract

`playbook.md` is prescriptive: **how this project is built, tested and
changed.** Authored by humans and by experience, not derived from code.

**Write regime — consult before writing.** `playbook.md` is NEVER changed
without the user's approval. An agent may propose anything — add an entry, fix
a superseded procedure, rephrase it, delete one that stopped being true — but
every change is presented for approval before it is written. The rule binds
every writer, `mb-sync` included. The automatic current-state pass that
`brief.md`, `architecture.md` and `tech.md` undergo (Harvest Contract §3) does
NOT apply here: the content does not come from code, so it cannot be verified
against code either.

**Exception — `mb-init`'s initial creation.** The first `playbook.md` that
`mb-init` writes, from the build and test commands it detected, needs no
approval: there is nothing yet to overwrite, and detected build commands are
verifiable against the build files themselves — unlike the experience the
consult rule exists to protect. Every LATER change to `playbook.md` follows
the consult rule above.

**Two consult styles, both legal.** `mb-sync` proposes a correction
immediately, at the point where it notices drift; `mb-harvest` batches
candidates into one end-of-branch gate. Both satisfy consult-before-writing —
neither is drift to reconcile with the other.

**Entry format** is free (heading + steps). When a persisted candidate carried
evidence, a one-line `Proč:` travels with it — the reason is part of the
procedure, not noise.

**Candidate collection during work.** Procedural knowledge is gathered while
the work happens, into
`<MB_ROOT>/.superpowers/playbook-candidates/<slug>.md` (git-ignored scratch,
English, first line `# Playbook candidates — work item: <slug>`). **One file per
work-item slug.** Files of FOREIGN slugs have their own paths and are never
overwritten and never deleted.

The overwrite licence for the CURRENT slug's file is narrow and keyed to git —
**tracked means live:**

- **Untracked** — ordinary git-ignored scratch. When its content is stale (a
  leftover of a slug whose work already finished or was abandoned) it is
  OVERWRITTEN; there is nothing to lose.
- **Tracked** — `mb-park` committed it (below), so it is **live parked
  evidence**. It is NEVER overwritten, not even for the slug currently being
  resumed: work continues by APPENDING to it, and only the harvest removes it,
  after its content has reached `playbook.md`.

The former single fixed path assumed strictly serial work, so once live tickets
were interleaved its overwrite rule deleted living evidence; the tracked/untracked
test is what keeps the same accident from returning through a resumed slug.

**`mb-park` commits the current slug's file to the ticket branch** (`git add -f`,
because `.superpowers/` is git-ignored), and the harvest deletes it after writing
the approved entries into `playbook.md`. This is a **named exception** from "the
scratch tree is git-ignored", valid for this one file only: parking must not
lose evidence that exists nowhere else.

Writers: implementer subagents report candidates in their report section
`## Playbook candidates`; the driving session — the same actor named in
"`context.md` Schema & Writers", i.e. the session dispatching the subagents —
COPIES confirmed ones into the collection file without rephrasing; sessions
outside SDD write directly.

Candidate format — the first three fields are mandatory, an entry missing any
of them is not written:

```markdown
## <short title>
- **Tried:** <what was attempted>
- **Happened:** <what actually happened — the evidence>
- **Procedure:** <the rule that follows from it>
- **Target MB:** <path>/memory-bank/        (only when harvest spans several MBs)
- **Corrects:** <existing playbook entry>   (when it contradicts an entry already there)
```

A candidate without a `Target MB` field, in a harvest spanning several Memory
Banks, defaults to `PLAN_MB`. A candidate whose `Corrects` names a
`playbook.md` entry that no longer exists is presented as a NEW entry instead
— tell the user the entry it meant to correct is gone.

The ban on invention is enforced by the FORMAT, not by a request in a prompt:
without `Happened` there is no entry.

**A ruling is a decision; a candidate is a procedure.** A `Ruling:` ledger
line (upstream subagent-driven-development) becomes a playbook candidate
only when it carries `Happened` evidence that reaches beyond this work
item; otherwise it stays in the ledger and in the final "Rulings I made"
list. The format decides, as always — without `Happened` there is no entry.
