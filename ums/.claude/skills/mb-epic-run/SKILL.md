---
name: mb-epic-run
description: Use when a ticket is to be STARTED as its own Claude session in a pool slot, or when you need the state of the machine's slot pool — which slot is free, which slot holds which ticket, whether a session is live in one ("rozjeď tiket UMS-1234 do slotu", "pusť sezení na tiket", "co je volné", "stav poolu", "kde běží ten tiket", "co je připravené rozjet"). This is about SLOTS and live sessions, not about documents on branches. Companion of mb-epic-elaboration; the pool is a set of linked worktrees the operator provisioned and marked.
license: MIT
metadata:
  author: UMS Project
  version: "1.0"
allowed-tools: Bash(git status:*), Bash(git rev-parse:*), Bash(git log:*), Bash(git branch:*), Bash(git for-each-ref:*), Bash(git fetch:*), Bash(git stash list:*), Bash(git add:*), Bash(git commit:*), Bash(git push:*), Bash(claude agents:*), Bash(pwsh:*), PowerShell(git status:*), PowerShell(git rev-parse:*), PowerShell(git log:*), PowerShell(git branch:*), PowerShell(git for-each-ref:*), PowerShell(git fetch:*), PowerShell(git stash list:*), PowerShell(git add:*), PowerShell(git commit:*), PowerShell(git push:*), PowerShell(claude agents:*), PowerShell(pwsh:*), Read, Grep, Glob, Edit, Skill
---

> Follow [UMS_MEMORY_BANK_CONTRACT](../shared/UMS_MEMORY_BANK_CONTRACT.md) —
> especially "Worktree Policy" (the pool-slot exception), "Workspace
> Discipline" and its subsection on a pool slot's freedom being derived from
> per-worktree signals only, "Publication Contract" and "Cross-Branch
> Visibility".

# Command: mb-epic-run

**Action:** Show the state of the pool, put both readiness oracles side by
side, start a session on a ticket in a free slot, and point the operator at
the slot that holds a ticket.

**Execution:** Read-only towards every slot. The only TRACKED write this skill
ever makes is one intent line in the epic's ledger, on the ELABORATION branch,
in this repository — never inside a slot. The two state files it asks the
scripts to write (`-Json`) land under this repository's git-ignored
`.superpowers/`.

## Iron rules

These are not style. Each one closes a measured failure.

1. **Never `cd` into a slot.** Ask git about it with `-C <slot>`.
2. **Never run a writing git command in a slot.** No `switch`, no `commit`, no
   `stash`, no `clean`, no `checkout`.
3. **Never write, move or delete ANYTHING inside a slot** — not a briefing,
   not a baton, not a note. The intent travels on argv and in the ledger; the
   session in the slot pulls the rest itself.
4. **Never spawn without the collision check.** A collision check that FAILED
   is not "no collision" — a run that did not complete is a STOP.
5. **A STOP leaves the slot exactly as it was found.** With rule 3 that is
   trivially true, and it must stay trivially true.
6. **Never decide the adapter silently and never fall back to another one.**
   `pool-launch.ps1` returns `unavailable`; report it and stop.
7. **Occupancy `unknown` is not free.** Without the harness signal, spawn only
   on the operator's explicit instruction, never on your own judgement.
8. **Never provision a slot.** `pool-provision.ps1` is the operator's — the
   script's own agent-session-marker guard is what stops an agent from
   running it regardless of `permissions.deny` (contract, Worktree Policy).
9. **Decide on `free`, never on a null pin.** In the JSON `pin == null` means
   IDLE — per the contract, "Active Work" for what IDLE is in `context.md`
   and "Worktree Policy" for the rule that IDLE is decided by the pin and
   never by a branch name — **or** unreadable, and the two are told apart only
   by the string `pin unreadable (fail-closed)` in that slot's `reasons`,
   because the shape carries no third pin-state field. "No pin, so no prior
   work, so this slot is fresh" is wrong in exactly the unreadable case, which
   is the mid-`mb-park` or interrupted-session state. `free` already folds
   both in. Read `free`, and when it is false read `reasons`; never re-derive
   freedom from `pin`.
10. **Never ask git for the worktree list yourself.** This layer denies
    `git worktree list` to the Bash tool through `permissions.deny`, where
    deny beats allow, so the command is deliberately absent from
    `allowed-tools` above — and it stays absent regardless of what that deny
    list happens to contain, because the reason is not the deny.
    `pool-status.ps1` is the one reader, and it calls git from inside `pwsh`,
    not through the Bash tool. Every "is this branch checked out somewhere"
    question is answered from the **union of `slots[].branch` and
    `excluded[].branch`** in its JSON. That union covers the primary worktree
    too, which is where a ticket branch is most likely to be checked out.

**`allowed-tools` is not what protects the slots — the rules above are.** The
field RESTRICTS: a tool the list does not name cannot be used at all. It is
therefore deliberately wider than "read-only git", because `spawn` writes a
ledger line, commits it through `mb-git-commit` and publishes the branch, all
three in the ORCHESTRATOR's own repository: that needs `Edit`, `Skill` and
`git add` / `git commit` / `git push`, and without them the step cannot run at
all. Narrowing the field back would break `spawn` and buy nothing for slot
safety, because a tool pattern at the granularity of `Bash(git commit:*)`
**cannot tell `git -C <slot> commit` from a local invocation**. Every
slot-facing call in this skill is read-only and `-C`-scoped by rules 1 and 2;
that is the guarantee, and the field never was.

**The duplicated `Bash(...)` and `PowerShell(...)` entries are not
redundancy — do not prune them.** This fork's sessions run on the PowerShell
tool (contract, "Publication Contract", where the same fact decides how the
push guard reads a redirection), while the same commands are also issued
through the Bash tool. A restricting list names a tool AND its frame, so an
entry present in only one frame leaves the command unusable in the other, and
`git commit` issued through the PowerShell tool would break `spawn`'s step 3,
the ledger write and its commit, for exactly the reason the list was widened.
Every command entry is therefore mirrored in both frames, `pwsh` included.

## Operations

All four report in Czech. The scripts speak English (they are developer
tooling, contract "Language Contract"); the rendering into Czech is this
skill's job.

### `status`

1. Run the state script, always with `-Json`:

       pwsh <this skill>/scripts/pool-status.ps1 -Json .superpowers/pool-status.json [-Epic <EPIC>]

   Keep the file for the rest of the session **for REPORTING only** — to
   answer a follow-up question about what was shown, or to render the table
   again. **Never make a spawn decision from a kept file.** Occupancy is a
   live harness probe, not a durable fact: a slot free at this run can hold a
   session a minute later, so `spawn` starts with a run of its own.

2. Exit `3` means **this repository has no pool**: no linked worktree carries
   the `.superpowers/pool-slot` marker. Report it in Czech, name
   `pool-provision.ps1` as the operator's remedy, and STOP — this is a
   fail-closed refusal, not a degraded mode.
3. Exit `1` is an input or script failure, and its most common cause is the
   `-Json` target directory not existing: the script validates that path
   **before any work**, deliberately, so that a run cannot print a
   healthy-looking report and then die with no file. Do not read it as "no
   pool". Report in Czech and name the remedy, e.g.:
   „Cílový adresář pro `-Json` neexistuje. Založ `.superpowers/` v kořeni
   repozitáře, nebo zvol jinou cestu, a spusť znovu."
4. Render the Czech table from the JSON, one row per slot, with exactly these
   column headers:

| Slot | Větev / detached | Pin | Postup v plánu | Špinavé | Nepushnuté | Sezení | Volný |

   `Sezení` renders `session.state` as `běží (pid …)` / `žádné` / `neznámé`,
   and the pids in that first form come from `session.pids`.
   `Špinavé` and `Nepushnuté` render `dirtyCount` and `unpushedCount`, with
   one exception: **`-1` is the unreadable sentinel, not a count — render it
   as `nečitelné`**, never as `-1`.
   `Volný` renders `free`, and under a non-free row list its `reasons`.
   When the run passed `-Epic`, say in the report that `Volný` is
   **epic-relative**: the script then adds a reason for a slot holding a
   ticket branch of that epic, so a slot free for one epic can be non-free
   for another.
5. Print `excluded` as a separate short list (why a worktree is not a slot),
   and the repository-wide `stash` count as ONE line that is explicitly NOT a
   property of any slot.
6. When an epic is in play, add the epic view: for every ticket in its ledger,
   whether some slot holds it.

### `ready <EPIK>`

Runs the two existing oracles **as they are** and prints both outputs next to
the pool table. **No verdict, no classification.** The decision stays with the
operator, who has been making it by hand and correctly; this skill only puts
both tables in one place so they do not have to be collected.

**Oracle one — invoke the `mb-epic-graph` SKILL, not its script.** Run
`mb-epic-graph` for `<EPIK>` in its consistency-check mode. Do not call
`epic-graph.ps1` directly: in its default Jira mode the script refuses to run
without `-InputFile`, and building that snapshot is the sibling skill's own
first step, which needs Jira read tools this skill does not have and must not
have. The sibling owns the pre-step; going around it produces an oracle that
always fails. (Its epic parameter is `-EpicKey`, not `-Epic` — one more reason
not to hand-roll the invocation.)

**Oracle two — the ledger script, run directly.** `<epic_snake>` is the epic
key in lower snake case (`UMS-3400` → `ums_3400`), the directory convention
`mb-epic-elaboration` owns; here it comes straight from the argument, not from
a scan.

       pwsh <mb-epic-elaboration>/scripts/ledger-status.ps1 -LedgerFile memory-bank/epics/<epic_snake>/ledger.md

Then the pool table from `status`. Classification of readiness is a separate,
queued work item — do not invent one here.

An oracle that fails to run is **reported as failed, with its exit code**, and
never quietly left out of the output. Printing one table where the operator
expects two, with no note, reads as "the other one had nothing to say" — which
is a verdict, and this operation does not give verdicts.

### `spawn <TIKET>`

In this order, and the order is the point.

1. **Derive the epic, take a FRESH state, then check eligibility.**

   `spawn` is given a ticket, but this step, the intent-line write (step 3)
   and the launch (step 4) all need the EPIC.
   Derive it — never ask for what is derivable, never guess it: scan the
   epic ledgers, `memory-bank/epics/*/ledger.md`, for the ticket code.
   **Exactly one match is the epic; zero matches and more than one match are
   each a STOP with that as the named reason** — a ticket in no ledger is not
   ready to be spawned, and a ticket in two is a question for the operator,
   not a coin flip. The directory name is the epic key in lower snake case
   (`UMS-3400` → `ums_3400`), the convention `mb-epic-elaboration` owns for
   `<MB_ROOT>/memory-bank/epics/<epic_key_snake>/ledger.md`; that value is
   `<epic_snake>` everywhere below.

   Then run the state script **again, now**, with that epic:

       pwsh <this skill>/scripts/pool-status.ps1 -Json .superpowers/pool-status.json -Epic <EPIK>

   **Never decide a spawn from a JSON kept from an earlier `status`.**
   Occupancy is a live harness probe, not a durable fact — that is why
   `claude agents --json` is in this design at all — so a file half an hour
   old can show `free: true` for a slot that has been occupied for twenty
   minutes, and the spawn would land a second session in it.

   **Every item below is a STOP with a named reason when unmet:**
   - the pool exists (at least one marked worktree — `pool-status.ps1` exit 3
     is the refusal),
   - the ticket appears in the epic's ledger (already answered by the
     derivation above),
   - a free slot exists per the derivation (`free == true`; iron rule 9,
     decide on `free`, never on a null pin),
   - the ticket's branch is not checked out in any worktree. Answer this from
     the **union of `slots[].branch` and `excluded[].branch`** in the fresh
     `pool-status.ps1` JSON. **The test is CONTAINMENT, not equality:** no
     branch in the union may contain the ticket code as a **case-sensitive
     substring**. A ticket branch is `<TICKET>-<kebab-slug>`, and the contract
     recognizes one by the ticket code it contains (see "Active Work Item
     (Design + Plan Pair)"), so comparing `UMS-1234` against
     `UMS-1234-pool-orchestrace` for equality would pass this gate every time
     and guard nothing. Do not run `git worktree list` (iron rule 10, never
     ask git for the worktree list yourself).
   - `mb-doc-index` with the DECLARED INTENT reports no active-work collision:

         pwsh <mb-doc-index>/scripts/doc-index.ps1 -Jira <TIKET> -Json .superpowers/doc-index-spawn-<TIKET>.json

     The output filename carries the ticket on purpose: `.superpowers/doc-index.json`
     is the shared name `mb-epic-graph` and `mb-epic-elaboration` also write,
     so a spawn during an elaboration window would silently overwrite a
     differently-scoped index and leave the other skill reading yours.

     Exit `2` is a collision and a STOP. **A run that failed (exit 1, or no
     JSON written) is also a STOP** — a check that did not complete is not
     "no collision".

   **One named override, and only one.** A slot whose ONLY reason is
   `occupancy unknown (fail-closed)` may still be spawned into — but solely on
   the operator's **explicit instruction**, never on your own judgement (iron
   rule 7). Nothing else overrides `free == false`: not a dirty tree, not an
   ACTIVE pin, not unpushed commits, not a held ticket branch, and not two
   reasons of which one happens to be `unknown`. When the override is used,
   record it in two places — in the report to the operator, and in the `Pasti`
   column of the intent line, naming that the operator instructed a spawn into
   a slot with unknown occupancy.

   **The branch union has one known blind spot, and it is not a bug to fix
   here.** A **prunable** worktree still holds its branch in `refs/worktrees`
   until it is pruned, so git will refuse to check that branch out anywhere
   else — yet `pool-status.ps1` reports `branch: null` for a prunable record,
   deliberately, because claiming a live checkout for a directory that is gone
   would be its own wrong answer. So this check can pass for a branch git will
   still refuse. When that happens, the spawned session's entry gate hits the
   refusal at its own `git switch` and stops there: **a STOP by refused
   checkout is the same legitimate outcome as a STOP by collision** — the slot
   is untouched and nothing was written. Report it as that, do not debug it as
   a broken spawn, and do not prune anything on the operator's behalf.
2. **Choose the slot.** Among free slots prefer a detached one, then one whose
   branch name equals its own directory name (the parked shape), then the
   rest. Announce which and why.
3. **Write the intent line** into the epic's ledger section `## Rozjetí`, in
   `memory-bank/epics/<epic_snake>/ledger.md`. The section has **six columns,
   in this order**, and the order is binding because the ledger parser indexes
   them **positionally**:

| Tiket | Datum | Slot | Verdikt | Draft (větev + cesta) | Pasti |

   Fixing the headers is not enough for a positionally parsed table — the
   CELL vocabulary is fixed too, and this skill is the upstream that defines
   it:

   - `Tiket` — the ticket code as written everywhere else, e.g. `UMS-1234`.
   - `Datum` — `YYYY-MM-DD`, nothing else.
   - `Slot` — the slot directory name, or `—` when no slot was taken.
   - `Verdikt` — exactly one of `rozjeto` | `odloženo` | `selhalo`. Not a
     synonym, not a Czech rendering of the launcher's status word: two
     writers putting `rozjeto` and `spuštěno` in one positionally parsed
     column is precisely the divergence the fixed order exists to prevent.
   - `Draft (větev + cesta)` — `<větev> @ <cesta>`, the branch first, then the
     repository-relative path, separated by a spaced at-sign.
   - `Pasti` — free Czech prose, or empty.

   There is deliberately **no column for the chosen base**: a work item's base
   has one home, the `Báze:` line of its `context.md`, and a second home would
   diverge at the first session that picks a different base. A non-trivial
   base goes into `Pasti` as a sentence.

   Then commit that line with `mb-git-commit` and publish the ELABORATION
   branch per the contract's Publication Contract. Nothing is written into the
   slot.

   **This is written BEFORE the launch on purpose**, so that a spawn which
   dies half way still leaves a trace of what was decided and where. The row
   therefore records the DECISION at this moment, not a confirmed outcome —
   and when the launcher then returns anything other than `launched`, say so
   plainly in the report and let the operator decide whether the row's
   `Verdikt` is corrected. Never quietly leave a `rozjeto` row standing behind
   a launch you reported as failed.
4. **Launch:**

       pwsh <this skill>/scripts/pool-launch.ps1 -SlotPath <slot> -Ticket <TIKET> -Adapter <terminal|direct> -Prompt "<one short line>"

   `-SlotPath` takes **`slots[].path` from the JSON, an absolute path** —
   never the slot's name. A name is not a directory and the launcher returns
   `failed` on it.

   **`-Adapter` is the OPERATOR's argument, not yours.** Iron rule 6 forbids
   deciding it silently, and this is where it comes from: the operator names
   `terminal` or `direct`. When the invocation did not carry one, **STOP and
   ask** — do not pick a default, and do not infer one from what happens to be
   installed on this machine.

   The prompt is SHORT and one line: what to do, which ticket, **which branch**
   and where to read the rest. Shape:

   `Převezmi tiket <TIKET>. Zbytek si najdi v ledgeru epiku <EPIK> na větvi <elaborační větev>, cesta memory-bank/epics/<epic_snake>/ledger.md, sekce Rozjetí.`

   **The branch is not optional.** That ledger path exists only on the
   elaboration branch you published in step 3, the intent-line write; the slot
   is detached or parked on something unrelated, and its first act is to cut its
   own ticket branch. Without the branch named, the path resolves to nothing
   in the slot's working tree and the session receives a brief it cannot act
   on — a launch that looks successful and is not, which is the failure class
   this whole design exists to close. It is the same reason the intent row's
   `Draft` column pairs a branch WITH a path: half of that pair does not
   locate a file. Roughly twenty-five characters against a six-hundred
   character budget.

   **The launcher refuses five prompt shapes as hard input errors, before any
   spawn happens** — exit `1`, nothing started, nothing to clean up: a
   **semicolon** (wt.exe reads it as a command separator), a **double quote**
   (measured: silently dropped, or it SPLITS the prompt so the session
   receives only its first fragment), a **trailing backslash** (it escapes the
   quote wrapping the prompt on the direct adapter), an **empty** prompt, and
   anything **over 600 characters**. The fixed part of the template above is
   safe — forward slashes, no quotes. The interpolated fields are the risk:
   check `<TIKET>`, `<EPIK>` and `<epic_snake>` for those characters before
   calling, and rewrite rather than escape.

   Report the status word in Czech: `launched` → „spuštěno", `unavailable` →
   „adaptér není k dispozici", `failed` → „spuštění selhalo".
5. **Mechanical verification, not a process table.** `Get-Process claude`
   returned a pid in all three measured failures, so process existence proves
   nothing. Re-run `pool-status.ps1` and require a record for that slot with
   `session.state == live`.

   **Give the session a few seconds, and retry once.** A probe fired the
   instant the launcher returns can legitimately read `none` — the child has
   not registered yet — and reporting that as "no session appeared" is a false
   alarm on a healthy launch. Wait briefly, probe, and on `none` or `unknown`
   wait once more and probe again. Two negative probes are the finding; one is
   noise.

   Either report „sezení potvrzeno" or „**žádné nové sezení se neobjevilo —
   ověř na obrazovce**". Never report „spuštěno" as „běží".
6. **Operator questions, as a backstop and not as the only check:** is there
   no `⚠ Transcript saving is off` in the status line, and is the WHOLE prompt
   in the first input? Into Jira the ticket goes as running only after the
   first commit on its branch.

### `attach <TIKET>`

Find the slot holding the ticket — from the `pool-status.ps1` JSON, a slot
whose `pin.jira` equals the ticket, or failing that whose `branch` contains
the ticket code as a case-sensitive substring (the same containment test
`spawn`'s eligibility gate, step 1, uses; the two must not disagree) — and
**print** the operator's next action: the slot path, the command that gets
them there, and the session state from the same JSON. Prints; runs nothing on
the operator's behalf, and starts nothing.

When no slot holds the ticket, say exactly that and stop. Do not guess at the
nearest slot, and do not start one: putting a ticket into a slot is `spawn`,
with its whole eligibility gate, and offering `spawn` is the only thing
`attach` may do about it.

## Quick reference

| Need | Use |
|---|---|
| State of the pool | `pool-status.ps1 -Json <path>` (exit 3 = no pool, exit 1 = input/script failure, often a missing `-Json` directory) |
| Both readiness oracles in one place | `ready <EPIK>` |
| Start a ticket in a slot | `spawn <TIKET>` |
| Where does a ticket run | `attach <TIKET>` |
| Is a branch checked out anywhere | ticket code as a case-sensitive SUBSTRING of the union of `slots[].branch` and `excluded[].branch` — never `git worktree list`, never equality |
| Which epic owns a ticket | scan `memory-bank/epics/*/ledger.md` for the code; zero or more than one is a STOP |
| Dependency graph oracle | the `mb-epic-graph` **skill** — never `epic-graph.ps1` directly (Jira mode refuses without `-InputFile`) |
| Which adapter | the operator's argument; STOP and ask when it was not given |
| Provision a NEW slot | `pool-provision.ps1` — **operator only**, refuses under an agent-session marker. Its exit `5` means the slot exists but its publication guarantee was NOT confirmed — that is not success |
| Cross-clone collision | `mb-doc-index` with `-Jira` (declared intent); exit 2 = STOP |
| Model for sub-dispatches | contract, "Dispatch Model Policy" |

## Rationalizations (all mean: STOP)

| Excuse | Reality |
|---|---|
| "The collision check errored, so there is no collision" | A check that did not complete is a STOP. Exit 1 is not exit 0. |
| "Occupancy is unknown, but the tree is clean, so it is free" | Unknown is fail-closed. A session that started a minute ago has not reached its pin write yet. |
| "The pin is null, so nobody has worked here — it is fresh" | A null pin is IDLE **or** unreadable, and unreadable is the mid-park state. Read `free` and `reasons`, never `pin` (iron rule 9). |
| "wt.exe is missing, I will use direct instead" | The adapter is the caller's choice. `unavailable` is a report, never a fallback. |
| "I will just tidy that leftover in the slot" | Iron rule 3, never write, move or delete anything inside a slot. The decision belongs to the user, in the slot where the leftovers lie. |
| "This worktree looks free even without the marker" | A worktree held for release maintenance satisfies every freedom condition. The marker is what prevents that spawn. |
| "The process exists, so the session is running" | All three measured failures had a pid. The proof is the harness's own registry: a record for THAT SLOT with `session.state == live`, from a fresh `pool-status.ps1` run. (`pool-launch.ps1` also passes `--name <TICKET>`, but the occupancy probe does not read names, so do not claim it as the check.) |
| "The branch union said nothing, so the checkout will work" | A prunable worktree keeps its branch reserved while reporting `branch: null`. A refused checkout in the spawned session is a legitimate STOP, not a broken spawn. |
| "I will escape the quote in the prompt" | The launcher refuses a double quote before spawning, because it measured both silent dropping and a split prompt. Rewrite the line without one. |
