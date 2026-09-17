# Session Intent Baton
Part of contract 3.x — the core is ../UMS_MEMORY_BANK_CONTRACT.md; cite as (contract/session-intent-baton.md, "Session Intent Baton").

### Session Intent Baton

The **baton** is how the operator's intent survives a `/clear`. It lives at
`<MB_ROOT>/.superpowers/session-intent.md`, is written by whoever ends a phase
and is consumed by a `SessionStart` hook in the next session. It is AI-facing
scratch and therefore English.

**Shape.** The first line is the identity line, `# Session intent — <ISO-8601
UTC>`. The body is a block of `Key: value` lines. Required: `Kind`
(`plan-execution` | `plan-resume`), `Plan`, `Branch`, `Slug` and
`Instruction`. Optional: `Spec`, `Ticket`, `Ledger`, `Next task` — omitted when
they have no value, never written empty. The last line is that single
`Instruction:` line naming the skill to invoke. Paths are relative to
`MB_ROOT`.

**`Instruction` is required AND validated, and the reason is what the reader
does with it.** Earlier versions named it "the last line" in prose while the
reader carried it only in its render order, so a baton without it was
delivered. Its value must NAME AN EXISTING SKILL — the reader derives the set
of legal names from the skill directories beside its own hook directory — and
must not exceed a short length ceiling. Without both checks the reader would
hand up to the whole size ceiling of attacker-chosen text as an automatically
executed first move. An empty or unreadable skill list makes every
`Instruction` unmatchable and therefore every baton stale, and that is the
right answer rather than a degradation to skip: the documented fallback for a
lost baton is the operator typing the intent, which costs nothing.

**The format is CLOSED, and that is a security property rather than tidiness.**
The file is git-ignored scratch in the working tree, so anything that writes
there can write it — implementer subagents write into `.superpowers/` routinely
— and its content reaches the model's context. A reader therefore NEVER emits the
body as it lies: it parses the known keys and RE-RENDERS them. An unknown key, a
line outside the `Key: value` shape, a body over the size ceiling, or a parsed
value containing **an angle bracket, a control character or a FORMAT
character** makes the baton stale.

Doklad: doklad/session-intent-baton.md, "Why the baton's format is closed"

**`Branch` and `Slug` are origin binding, not decoration** — they are what the
reader validates against this session's own `HEAD` and `context.md` pin. `Kind`
must be one of its two values and `Plan` must name an existing file: a plan the
harvest deleted is a stale baton, not an instruction pointing at nothing. A baton
missing any required key is invalid and is treated as stale.

**Consume-on-read.** The reader renames the file to `session-intent.consumed.md`
immediately after emitting it, overwriting any previous consumed file. A baton
rejected by a guard is renamed to `session-intent.stale.md` instead and nothing
is emitted. Neither file is ever deleted — a confused operator must still be able
to read what it said.

**The baton carries intent within ONE'S OWN workspace, and no further.** It is
an AMBIENT channel: a `SessionStart` hook fires in every session anyone opens
in that worktree, so the baton cannot address a particular process. Delivering
intent into a DIFFERENT workspace — a pool slot — is therefore not a third
`Kind` but a different channel entirely: the prompt travels on the launched
process's argv and the rest is PULLED from a committed ledger line. Every
guard a `ticket-start` baton would have needed (a `Slot` origin binding, a
clean-tree check, a check that the ticket branch does not exist, an IDLE-pin
check, a shape check on `Ticket`) is repair work bought by that one change of
channel, and both proven launchers carry a prompt already. Do not reintroduce
a `ticket-start` kind without a member that needs one.

**Invalidation** is that same rename to `session-intent.stale.md`, performed by
whoever ENDS or SETS ASIDE a work item; a silent no-op when no baton is present.
It is not a numbered step of any sequence — the baton is git-ignored, so it has
no ordering relationship with a commit or a push — it is bookkeeping done before
the skill reports its result. It runs where the skill ACTED, never where it
refused to act: a STOP that reports "nothing was committed, pushed or discarded"
must stay true.

**Writer precondition.** A baton is written only where a consumer will read it:
the harness must be one whose session-start hooks this layer configures
(`CLAUDECODE` non-empty), and the hook must exist and be registered. This layer's
`settings.json` is deliberately not deployed to non-Claude harnesses while the
skills are, so without this check a writer would leave an instruction nobody
reads. The rule lives here because two consumers implement it.

**Precedence.** Several `SessionStart` hooks may each contribute their own
`additionalContext`, in no guaranteed order. The session-eligibility check of the
bootstrap block — the publication-guarantee self-check — is a PRECONDITION of
acting on a baton, never the other way round. A baton never overrides a
fail-closed gate.

**Reader exception to `MB_ROOT` Discovery.** A hook that may only contribute
context must never prevent a session from starting, so the baton reader exits 0
silently on EVERY failure path, including the missing-git case that section makes
a hard failure. This is the one exception and it is stated here so a later reader
does not "repair" the hook against that section.

**The baton is NEVER committed, and the reason is the recoverability boundary of
Workspace Discipline** — does this information exist anywhere else?
`playbook-candidates/<slug>.md` does not, which is why the Playbook Contract's
named exception and `mb-park`'s `git add -f` exist. `sdd/<plan-basename>/` does,
in the plan checkboxes and the git log, which is why it is deleted and never
committed. The baton belongs to neither tier: its lifetime is seconds to minutes
and losing it costs nothing — the fallback is the operator typing the intent,
which is today's behaviour. Committing it would actively harm: the file would
return on every checkout of that branch, in any workspace and any fresh clone,
and a `startup` days later would replay a stale instruction — precisely the
failure consume-on-read exists to prevent, reintroduced through git. It would
also force `mb-park` to decide whether to commit it, and a committed "execute
this plan" instruction published to `origin` is a live hazard for every resuming
session. There is therefore no exception here, and the Playbook Contract's "one
named exception to the git-ignored rule" stays true.
