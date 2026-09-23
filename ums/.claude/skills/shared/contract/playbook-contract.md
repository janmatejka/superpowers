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

**Entry format** is the item shape of "Playbook shape" below; a legacy file keeps its free format until consolidation converts it ("Legacy mode").

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

Doklad: doklad/playbook-contract.md, "Why the overwrite licence is keyed to git"

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
- **Relates:** <MB>:<item> (extends | duplicates | replaces)   (when the candidate touches an item of the chain)
```

Corrects is the special case "replaces".

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

### Playbook shape

A playbook in the new shape has at least one and at most two parts, spelled exactly `## Pro celý podstrom` (read by every descendant Memory Bank) and `## Jen pro tento projekt` (read only by work pinned to this Memory Bank), and no other second-level heading. Anything else is the legacy shape ("Legacy mode"). Inside a part, sections are `### Když …` headings named for the moment the rule is needed, never for a topic; the base list of sections lives in this reference and a Memory Bank may add its own `Když …` section, which is then recorded here as an extension. The root playbook carries mainly the subtree part; it may carry the project part only for work pinned to the root Memory Bank itself (single-MB repositories). Two item kinds, both inside a section and both counted against the budget: a **rule** — one imperative bold line, then `Proč:` in one sentence and `Důkaz:` (harvest commit SHA, archived design, the test that guards it, or `návrh <slug>` for a new item), at most four lines of at most 80 characters; a **procedure** — a bold title on its own line and at most 15 lines of steps, a command block or a parameter table, with `Proč:`/`Důkaz:` when there is something to prove. Build and test commands are procedures in `Když stavíš nebo spouštíš testy`.

Base list of sections (what belongs in each):

- `Když stavíš nebo spouštíš testy` — build and test commands as procedures;
  `mb-init` creates them, the SDD baseline step reads them.
- `Když píšeš nebo měníš test` — suite conventions, fixtures, negative tests
  and mutation, assertions.
- `Když spouštíš sadu nebo důkazní běh` — the suite loop, working directory,
  reading results from markers, throwaway fixtures.
- `Když píšeš PowerShell` — language traps, encoding, collections,
  `Set-StrictMode`.
- `Když píšeš POSIX hook nebo shell` — `set -f`, stdin, CR/CRLF, msys versus
  POSIX.
- `Když měníš kontrakt, skill nebo overlay` — one home per rule, sweeps after
  a change, step numbering, truthful reports and comments.
- `Když nasazuješ nebo revendoruješ` — sync, restoring the deployed copy,
  hook installation, revendoring and anchors.
- `Když píšeš plán, návrh nebo commit` — delimiters in plans, diacritics in
  commits, briefs.

`Proč:` cites the incident in one sentence, not as a story; the story stays
in git and in the archived design `Důkaz:` points to. The shape check tests
"one sentence" only heuristically and reports it as a warning, never as a hard
finding.

### Playbook chain

The Memory Bank tree is derived from tracked paths (`git ls-files`): Memory Bank A is an ancestor of B when the directory owning `A/memory-bank/` is an ancestor of the one owning `B/memory-bank/`; a `memory-bank/` nested inside another `memory-bank/` is ignored, and untracked or git-ignored copies do not exist for the tree. The chain of Memory Bank X is what a session working in X reads: from every ancestor that has a playbook, root first, only its `Pro celý podstrom` part (a legacy root counts whole, a legacy non-root ancestor contributes nothing); from X, the whole file. `shared/scripts/Get-UmsPlaybookChain.ps1` computes it; `-Out` writes the assembled chain to `.superpowers/playbook-chain/<mb>.md` (regenerated on every use) and a dispatch receives that path, never the inlined content.

### Budget, threshold and ratchet

Thresholds: 600 lines per file, 900 lines per chain, 40 items per section. Exceeding a threshold is a warning with the size, never a hard finding: it says the playbook probably carries content that belongs elsewhere ("Escalation report"). `shared/scripts/Test-UmsPlaybookShape.ps1` reports exactly three hard findings, all for a new-shape file: a shape violation, growth over the ratchet baseline, and a file over the threshold without its ratchet comment. The ratchet is the literal second line `<!-- playbook-budget: 600; baseline: <N> (<YYYY-MM-DD>[, <reason>]) -->`; the file may not outgrow the baseline unless a human, in the harvest gate, explicitly raises it with a reason, which is written into the comment. Consolidation lowers the baseline to the achieved size after every batch and removes the comment below the threshold.

`Test-UmsPlaybookTree` checks the chain of every Memory Bank of a subtree, so
an inflated root or subtree part shows at all its descendants at once. A chain
has no ratchet of its own: it is the sum of its segments, each guarded by its
own file's ratchet.

### Legacy mode

A legacy-shape file gets warnings only — shape, size, thresholds — and never stops a harvest; the harvest gate announces loudly that a legacy file grows and by how much, and recommends consolidation. Strict rules apply from the moment round 1 of consolidation converts the file; if it is then over the threshold, round 1 writes its ratchet.

### Harvest gate

The playbook step of the harvest presents a **disposition table**, not a list
of texts. An analyst on the cheapest capable tier
(contract, "Dispatch Model Policy") prepares it per "Analyst brief"; the human
approves the table and may override any row.

```markdown
| # | Kandidát | Původ (task) | Cena nepřítomnosti | Existující položka | Dispozice | Kritérium | M/Ú | Selhání |
|---|---|---|---|---|---|---|---|---|
```

`Dispozice` holds exactly one of five values: `nový (<MB>, podstrom | projekt,
<sekce>)`, `sloučit do <MB>:<položka>`, `nahrazuje <MB>:<položka>`,
`do kódu <kde>`, `zahodit <důvod>`. `M/Ú` is `M` only where the identifier
match of `shared/scripts/Find-UmsPlaybookMatch.ps1` or the mechanically
checkable criterion 4 decided the row, `Ú` everywhere else — pairing English
candidates against a Czech playbook is semantic work. `Selhání` is `hlasité`
when a session following the wrong version of the rule would hit a visible
failure, otherwise `tiché`.

**Impact of an ancestor target.** A row whose disposition targets an
ancestor's playbook also carries the count and the list of the Memory Banks
that inherit the rule (computed with `Get-UmsPlaybookChain.ps1`); for the root
that is the whole repository, so the human approves the write with its reach
visible. Conflicts of parallel tickets in the same ancestor playbook are
resolved by the ordinary base merge at a phase boundary.

**Criteria, in order of application** (cheap and mechanical first):

1. Duplicate within the batch — cluster by topic, not by originating task.
2. Duplicate against the chain — already covered → `zahodit`; extends →
   `sloučit do`; otherwise `nový`. `Corrects`/`Relates` must name an existing
   item.
3. Reach in the tree — this Memory Bank only (`projekt`), the subtree of an
   ancestor (`podstrom` of that Memory Bank), or everywhere (`podstrom` of the
   root)? A rule bound to a single commit or finding is suspect unless it
   generalises. The default target is the candidate's `Target MB`, else
   `PLAN_MB`, part `projekt`; the analyst proposes a wider target and the
   human approves it.
4. Operational form — `Procedure` is an operation ("before Y, check X"), not a
   judgement ("be careful about X"); a non-operational one → `zahodit`, or
   rewrite it in one sentence.
5. Cost of absence — from `Happened`: real (session crash, false green,
   security hole, lost file) versus cosmetic; it orders the rows and decides
   borderline cases.
6. Trigger — is there a natural moment when a session recalls the rule? It
   determines the section. Above all: would it be better as code — a lint, an
   assertion in `_assert.ps1`, a check in a script → `do kódu`.
7. Home — a fact belongs in `tech.md`, a rule in the contract, a procedure in
   the playbook ("Environment traps").
8. Net context cost — the chain stays the same size or shrinks; `nahrazuje`
   is worth more than the same content as an extra item; for `nový` name the
   section and prefer `sloučit do` when the section has a close neighbour.

`sloučit do` rewrites the existing item into one rule line plus `Proč:`;
`nahrazuje` removes the old item and records it in the retired list; `do
kódu` writes the test or check and adds no playbook item. A candidate matching
a retired rule of any chain segment gets `zahodit (vyřazeno)` unless it
carries a new `Happened`.

**Writing.** The approved table becomes a decisions file with the verdicts
`novy`, `sloucit`, `prepsat`, `vyradit` and `prevest-na-test`, applied by
`mb-playbook-consolidate/scripts/consolidate-playbook.ps1 -Apply`; a candidate
merged into an existing item is `prepsat` of that item, and `nahrazuje` is
`vyradit` of the replaced item plus `novy`. A write into an ancestor's playbook
is "Writes outside PLAN_MB".

**Shape check before archiving.** At the end of harvest rule 3, before rule 4
(archive) and before the IDLE reset, `Test-UmsPlaybookShape` runs on every
written file and `Test-UmsPlaybookTree` on the chain of every Memory Bank the
change touched. A hard finding counts as a failed Memory Bank update under the
partial-failure rule of (contract/harvest.md, "Harvest Contract"): no archive,
no IDLE reset — fix it and rerun the gate. Growth over the ratchet is resolved
by balancing it (merge, replace, retire) or by a human raising the baseline
with a reason: `consolidate-playbook.ps1 -Baseline -Path <file> -Reason
<reason>`. Warnings (legacy mode, the `Proč:` heuristic) never stop the
harvest; they are printed.

### Analyst brief

One brief serves the harvest gate and consolidation. The analyst is read-only:
it returns a table and writes nothing.

- **Inputs:** for the gate, the current slug's candidates file and the
  `Find-UmsPlaybookMatch.ps1` output per candidate; for consolidation, the
  `consolidate-playbook.ps1 -Parse` JSON; for both, the path of the assembled
  chain (`Get-UmsPlaybookChain -Out`), the retired lists of every chain segment
  and the `consolidate-playbook.ps1 -Stats` output.
- **Output:** a table in the shape of "Harvest gate" or "Consolidation", one
  row per candidate or item.
- **Rules:** apply the criteria in their order; every row names its criterion,
  and a gate row its `M/Ú`; a row the analyst cannot decide is marked
  undecided, not guessed; never invent or complete a `Happened`.
- **Dispatch:** the cheapest capable tier
  (contract, "Dispatch Model Policy"), with the model named explicitly in the
  dispatch.

### Retired rules and conversion to code

`playbook-retired.md` lives next to every playbook that retires rules, one
line per retired rule:

```markdown
- <first words of the rule> — <nahrazeno «položka» | hlídá test <sada> | neplatí od <commit>> (<YYYY-MM-DD>)
```

`consolidate-playbook.ps1 -Apply` appends these lines for the verdicts
`vyradit` and `prevest-na-test`. The harvest gate and consolidation read the
retired lists of the whole chain, so a rule retired in an ancestor is not
learnt again in a descendant.

A rule a machine can check is converted into a test and leaves the playbook.
The first two conversions are the suite `shared/tests/tests-hygiene.tests.ps1`
over every `ums/**/tests/*.tests.ps1`: (a) every `Assert-*` a suite calls
exists in the sibling `_assert.ps1` — a missing helper would pass for an
expected RED in a RED run; (b) every suite that dot-sources its subject sets
`$ErrorActionPreference = 'Stop'`. The suite runs without an allowlist.

### Environment traps

An environment trap has two homes by the kind of sentence: the **fact about
the platform** (what PowerShell, git or msys does) belongs in `tech.md`,
section `Pasti prostředí`; the **procedure** (what you do so it does not hit
you) belongs in the playbook, with `Důkaz:` pointing to `tech.md`. Never both
in both places. In the tree the procedure is almost always general and belongs
in the root's `Pro celý podstrom` part; the fact stays in `tech.md` of the
Memory Bank where it showed up.

### Consolidation

The skill `mb-playbook-consolidate` runs on demand, or when the shape check
reports a hard finding or a file over the threshold — never automatically. It
is a read-only pass over the playbook and the retired lists of its chain whose
output is a proposal table:

```markdown
| # | Položka | Návrh | Kritérium | Do | Pozn. |
|---|---|---|---|---|---|
```

- **Návrh:** `ponechat` / `sloučit do <položka>` / `vyřadit (<důvod>)` /
  `přesunout do tech.md` / `převést na test <kde>` /
  `přesunout k předkovi <cesta>` / `přesunout k potomkovi <cesta>` /
  `přeřadit do části podstrom | projekt`.
- **Kritérium:** `duplicita` / `přesah` / `jednorázový incident` /
  `převoditelné do kódu` / `špatný domov` / `nad rozpočet sekce` /
  `širší dosah` / `užší dosah`.

The human approves the table; writing (`consolidate-playbook.ps1 -Apply`, with
`prepsat` for a rewritten item, `presunout` for every move between files,
parts or sections, `sloucit`, `vyradit`, `prevest-na-test`, `do-tech`), the
shape check and the commit through `mb-git-commit` go as in the harvest gate.
A move between files follows Document Ownership: written to the target first,
then removed from the source, both files in one commit. Consolidation never
pushes a shared branch.

**Two rounds, both approved by a human over the table.** Round 1 converts the
shape: splits the file into parts, re-sorts items into `Když …` sections,
shortens `Proč:` to one sentence and fills `Důkaz:` from the harvest commit
SHA found by `git log -S`; a legacy file is converted whole. Round 1 also
greps every citation of an old section name outside the playbook and rewrites
it in the same batch; the end of the run runs `mb-link-audit` over the touched
Memory Banks. Round 2 merges, retires, moves and converts to code; a section
still over 40 items after round 2 splits into narrower `Když …` sections.

**Tree mode `-Tree [<path>]`** (default `MB_ROOT`) runs in four steps:

1. **Inventory** — `consolidate-playbook.ps1 -Stats -Tree` and `-Parse -Tree`
   build the tree and list the sizes of files and chains, marking what is over
   a threshold. Writes nothing.
2. **Round 1 (shape)** per Memory Bank, top down — a descendant needs to know
   what its ancestor already carries in the subtree part. Every Memory Bank
   has its own table, approval and commit.
3. **Round 2a (across Memory Banks)** — the analyst clusters items of
   different Memory Banks by topic (identifier match helps mechanically); for
   every cluster `Get-UmsMbLowestCommonAncestor` computes the lowest common
   ancestor of the Memory Banks it lives in. `přesunout k předkovi <předek>`
   merges the duplicates into one item in the ancestor's subtree part;
   `ponechat` leaves every Memory Bank its own variant; `přesunout k
   potomkovi` returns a rule written higher than it applies. The table is one
   across Memory Banks, approved in batches — one batch per subtree.
4. **Round 2b (within a Memory Bank)** — merging, retiring and conversions to
   code as in round 2, per Memory Bank.

**Batches and resumption.** Every batch is its own commit through
`mb-git-commit` on the ticket branch of the session running the pass, with the
trailer `Playbook-Consolidation: <run>/<batch>`; consolidating a monorepo is
ordinary work on its own ticket. A batch is approved, written and committed at
once, so commits are the only carrier of state: `consolidate-playbook.ps1
-Resume <run>` derives the finished batches from the trailers in `git log` and
the pass continues with the first unfinished one. The table of a batch in
progress under `.superpowers/playbook-consolidation/<run>/` is git-ignored
scratch that can be regenerated at any time, so unapproved work is no
unrecoverable leftover and Workspace Discipline does not change.

**End of run:** `Test-UmsPlaybookTree` over the whole subtree without a hard
finding; every Memory Bank whose file or chain stays over a threshold has its
ratchet at the achieved size and an escalation report in the queue ("Escalation
report").

### Writes outside PLAN_MB

Two named exceptions to the Scope Lock, both limited to what a human approved in a table. The harvest gate: an approved disposition targeting an ancestor's playbook adds that ancestor to `AFFECTED_MBS` for `playbook.md` and `playbook-retired.md` only. Consolidation: it may write `playbook.md` and `playbook-retired.md` of every Memory Bank in the run's scope, `tech.md` only for rows with the verdict `do-tech`, and `proposals/next/` only for an approved escalation report. `mb-git-commit` stages exactly the files an approved batch names.

### Escalation report

When a file or a chain is still over its threshold after round 2,
consolidation does not cut further. It sets the baseline to the achieved size
and writes an escalation report as a preliminary design
`<MB>/proposals/next/design_<mb-slug>_playbook_eskalace.md` — in the queue
where `mb-state` and `mb-doc-index` find it and from which it is activated as
ordinary follow-up work. The report resolves nothing; it gives the grounds:

- the size of the file and of the chain against the threshold;
- the remaining items grouped into clusters by topic, with each cluster's size;
- for every cluster a proposed other home and why: a skill (a procedure bound
  to one kind of work, loaded only for it), a script or test (mechanically
  checkable), a separate reference document of the Memory Bank read on
  demand, or `tech.md`;
- an estimate of how much the move would shrink the playbook and the affected
  chains.

Whoever created the report has it approved like the batch table; writing it
into `proposals/next/` falls under the consolidation exception of "Writes
outside PLAN_MB". In `-Tree` mode there is one report per subtree, not one per
Memory Bank, so clusters recurring in several Memory Banks — candidates for a
shared skill — are seen together.
