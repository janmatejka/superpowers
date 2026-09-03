---
name: mb-epic-run
description: Use when a ticket is to be STARTED as its own Claude session in a pool slot, or when you need the state of the machine's slot pool — which slot is free, which slot holds which ticket, whether a session is live in one ("rozjeď tiket UMS-1234 do slotu", "pusť sezení na tiket", "co je volné", "stav poolu", "kde běží ten tiket", "co je připravené rozjet"). This is about SLOTS and live sessions, not about documents on branches. Companion of mb-epic-elaboration; the pool is a set of linked worktrees the operator provisioned and marked.
license: MIT
metadata:
  author: UMS Project
  version: "1.0"
allowed-tools: Bash(git status:*), Bash(git rev-parse:*), Bash(git log:*), Bash(git branch:*), Bash(git for-each-ref:*), Bash(git fetch:*), Bash(git stash list:*), Bash(claude agents:*), Read, Grep, Glob, PowerShell(pwsh:*)
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
8. **Never provision a slot.** `pool-provision.ps1` is the operator's; it
   refuses to run under an agent-session marker anyway.
9. **Decide on `free`, never on a null pin.** In the JSON `pin == null` means
   IDLE **or** unreadable, and the two are told apart only by the string
   `pin unreadable (fail-closed)` in that slot's `reasons` — the shape carries
   no third pin-state field. "No pin, so no prior work, so this slot is fresh"
   is wrong in exactly the unreadable case, which is the mid-`mb-park` or
   interrupted-session state. `free` already folds both in. Read `free`, and
   when it is false read `reasons`; never re-derive freedom from `pin`.
10. **Never ask git for the worktree list yourself.** `git worktree list` is
    denied to the Bash tool by this layer's `permissions.deny`, where deny
    beats allow — which is also why it is absent from `allowed-tools` above.
    `pool-status.ps1` is the one reader, and it calls git from inside `pwsh`,
    not through the Bash tool. Every "is this branch checked out somewhere"
    question is answered from the **union of `slots[].branch` and
    `excluded[].branch`** in its JSON. That union covers the primary worktree
    too, which is where a ticket branch is most likely to be checked out.

## Operations

All four report in Czech. The scripts speak English (they are developer
tooling, contract "Language Contract"); the rendering into Czech is this
skill's job.

### `status`

1. Run the state script, always with `-Json`, and keep the file for the rest
   of the session:

       pwsh <this skill>/scripts/pool-status.ps1 -Json .superpowers/pool-status.json [-Epic <EPIC>]

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

   `Sezení` renders `session.state` as `běží (pid …)` / `žádné` / `neznámé`.
   `Volný` renders `free`, and under a non-free row list its `reasons`.
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

       pwsh <mb-epic-graph>/scripts/epic-graph.ps1 -Epic <EPIK> -Check
       pwsh <mb-epic-elaboration>/scripts/ledger-status.ps1 -LedgerFile memory-bank/epics/<epic_snake>/ledger.md

Then the pool table from `status`. Classification of readiness is a separate,
queued work item — do not invent one here.

An oracle that fails to run is **reported as failed, with its exit code**, and
never quietly left out of the output. Printing one table where the operator
expects two, with no note, reads as "the other one had nothing to say" — which
is a verdict, and this operation does not give verdicts.

### `spawn <TIKET>`

In this order, and the order is the point.

1. **Eligibility, every item a STOP with a named reason when unmet:**
   - the pool exists (at least one marked worktree — `pool-status.ps1` exit 3
     is the refusal),
   - the ticket appears in the epic's ledger,
   - a free slot exists per the derivation (`free == true`; iron rule 9,
     decide on `free`, never on a null pin),
   - the ticket's branch is not checked out in any worktree. Answer this from
     the **union of `slots[].branch` and `excluded[].branch`** in the
     `pool-status.ps1` JSON, comparing branch names **case-sensitively**. Do
     not run `git worktree list` (iron rule 10, never ask git for the
     worktree list yourself).
   - `mb-doc-index` with the DECLARED INTENT reports no active-work collision:

         pwsh <mb-doc-index>/scripts/doc-index.ps1 -Jira <TIKET> -Json .superpowers/doc-index.json

     Exit `2` is a collision and a STOP. **A run that failed (exit 1, or no
     JSON written) is also a STOP** — a check that did not complete is not
     "no collision".

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

   The prompt is SHORT and one line: what to do, which ticket, and where to
   read the rest. Shape:

   `Převezmi tiket <TIKET>. Zbytek si najdi v ledgeru epiku <EPIK>, cesta memory-bank/epics/<epic_snake>/ledger.md, sekce Rozjetí.`

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
   `session.state == live`. Either report „sezení potvrzeno" or „**žádné nové
   sezení se neobjevilo — ověř na obrazovce**". Never report „spuštěno" as
   „běží".
6. **Operator questions, as a backstop and not as the only check:** is there
   no `⚠ Transcript saving is off` in the status line, and is the WHOLE prompt
   in the first input? Into Jira the ticket goes as running only after the
   first commit on its branch.

### `attach <TIKET>`

Find the slot holding the ticket — from the `pool-status.ps1` JSON, a slot
whose `pin.jira` equals the ticket, or failing that whose `branch` names it —
and **print** the operator's next action: the slot path, the command that gets
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
| Is a branch checked out anywhere | union of `slots[].branch` and `excluded[].branch` — never `git worktree list` |
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
| "The process exists, so the session is running" | All three measured failures had a pid. The registry record with `--name <TICKET>` is the proof. |
| "The branch union said nothing, so the checkout will work" | A prunable worktree keeps its branch reserved while reporting `branch: null`. A refused checkout in the spawned session is a legitimate STOP, not a broken spawn. |
| "I will escape the quote in the prompt" | The launcher refuses a double quote before spawning, because it measured both silent dropping and a split prompt. Rewrite the line without one. |
