# The epic line
Part of contract 3.x — the core is ../UMS_MEMORY_BANK_CONTRACT.md; cite as (contract/epic-line.md, "The epic line").

## The epic line

**The epic line is the code integration branch of an epic**, named
`epic/<EPIC-KEY>`, and it is the effective base of every ticket branch cut for
that epic. It carries code and the harvested documents of those tickets; the
epic's elaboration branch is a different branch and carries none of that. The
epic itself integrates one level further out, into the **delivery line** — the
shared branch the epic ultimately delivers into, and the base every ticket would
have had without an epic line.

**When two tickets share an interface, the epic line carries a stub of that
shared interface, committed before either ticket implements against it.** The
reason lives here, not in a skill: a stub turns the compiler into an oracle, so
a later merge surfaces a mismatch as a TEXTUAL conflict — the only kind git can
show — instead of a SEMANTIC one, which compiles clean on both branches alone
and fails only once they meet. Measured: the signature of `EmployeeResolver`
was recorded in the epic's ledger as prose, and it did not compile against what
the other ticket had written — a parameter too many, a different parameter
order, the wrong arity — caught only by chance, not by any mechanism.

**The stub is authored on a ticket branch, like any other work, and reaches
the epic line by the same fast-forward as everything else** — the manager
performs that push but never authors the stub. Whose branch: the ticket that
owns the interface, or, where neither owns it, one created for it during
elaboration. "Committed before either implements against it" is therefore an
ordering claim about the queue, not a licence to write the stub directly onto
the epic line.

**It belongs in `protectedBranches`**, so the invariant of
contract/repository-configuration.md — an integration branch is always a
protected branch — holds for it literally, and both
enforcement layers resolve its protection by their usual routes.

**`epicBranchPattern` does NOT govern protection.** Its one job is the
actor-rule exception that lets the agent's own tool call fast-forward such a
branch (Publication Contract). A missing, empty or non-string value therefore
means **no exception at all** — never "every branch" — which is the same
safer-side degradation the keys of contract/repository-configuration.md follow.

**An unusable `baseRef` likewise means no exception**, and the fallback to
`origin/develop` does NOT apply here. Missing, non-string, empty, whitespace
only, `refs/`-prefixed (`refs/remotes/origin/develop` — the accepted spelling is
`origin/<branch>`, Repository Configuration), or reducing to an empty branch
name (`origin/`): each of these declines the exception. Surrounding whitespace
is trimmed off first, so a sloppy but correct value still works. Declining is
fail-closed and guessing a base is not: condition 3 below compares the
destination AGAINST the base name, so a base name that is merely wrong — rather
than absent — is a name no destination equals, and the condition can never
bite.

**The exception holds only where all FOUR conditions hold**, and
`guard-git-push.mjs` is the only place that evaluates them:

1. the destination matches `epicBranchPattern`;
2. the destination IS protected;
3. the destination is NOT `<baseBranch>`, the branch derived from `baseRef`;
4. the SOURCE side of the refspec is a raw 40-character hex SHA — not `HEAD`,
   not a branch name, not an absent source.

**Condition 3 needs the CONFIGURATION KEY `baseRef` itself, by name, and says
so** — this is the escape the effective-base rule of
contract/repository-configuration.md provides ("a site that
instead needs the config key itself, by name, says so"), taken deliberately and
not by omission. The reason is what evaluates the condition: a `pre-push` hook
and a `PreToolUse` guard both fire without a work item in hand. Neither can know
which base THIS work item integrates into — that lives in `context.md`, in a
working tree the guard is not entitled to assume it is standing in — so the
repository default is the only base name available to both, and it must be the
same name in both or the two would disagree about what they exclude.

Doklad: doklad/epic-line.md, "The residual risk of condition 3"

Doklad: doklad/epic-line.md, "What each condition closes, and what the raw-SHA test does not do"

Doklad: doklad/epic-line.md, "The threat model"

**A human creates the branch.** On a first publication `remote_sha` is zero, so
the content rule cannot find the tip already reachable and `pre-push` rejects the
push; the rejection hands over the ESCAPE spelling, and the plain integration
spelling would be rejected there again (the two spellings are deliberately
different — see Publication Contract).

Doklad: doklad/epic-line.md, "What licenses an agentic write here"

Doklad: doklad/epic-line.md, "The third category"

**An epic line comes into being only where the tickets of an epic are not
individually deliverable into the delivery line**; where they are, every ticket
integrates on its own, as everywhere else. **And it ends:** once the epic has
reached the delivery line the branch is deleted, which is a human act because
deleting a branch through a push is forbidden. Left behind it stays protected for
ever, and every base choice keeps offering an unrelated epic's line as a base.

**An unconfirmed decision-registry row naming the integrating ticket blocks the
epic fast-forward, and the ticket's spawn row in the epic's own ledger must
belong to this epic** — enforced mechanically, ahead of the push, by
`mb-epic-run`'s `integrate` operation.

**The decision registry** is the `## Registr rozhodnutí` section of the epic's
evidence ledger, and its rules live HERE rather than in the ledger template,
because three different actors act on them: the elaboration window that writes
a row, the ticket session that confirms one, and the manager's `integrate`,
which reads them.

- **Who writes a row.** A decision that rests on ANOTHER ticket's behaviour or
  code IS a row of that registry, naming that ticket in `Předpokládá o
  (tiket)`, with `Vlastník (tiket)` the ticket that took the decision. The
  elaboration window that took it writes the row (`mb-epic-elaboration`, its
  Impact on neighbors step), which is what makes the registry mechanical: the
  row exists by procedure, not because somebody remembered.
- **`Druh` decides what evidence may close the row**, and that is the column's
  whole job: a `text` row closes on a READING, a `chování` row closes on a
  TEST asserting that behaviour. Reading code proves its current value, never
  that it behaves the way the decision assumes.
  **This one is a DUTY on whoever supplies the SHA, not a check the gate
  performs, and it is stated so that the rule stops looking enforced.**
  `integrate` keys confirmation on a non-empty `Potvrzeno (SHA)` alone — a SHA
  is a SHA, and nothing in a commit identifier distinguishes a commit that adds
  a test from one that merely records a reading. The gate therefore reads
  `Druh` for nobody: it is rendered by `ledger-status` so a HUMAN or a manager
  reviewing the registry can see which rows owed a test, and it is that reader
  who catches a `chování` row closed on a reading. Do not add a mechanical
  check here in the belief that one is missing; there is nothing available to
  the gate to check it WITH, and a check that cannot tell the two apart would
  only move the false assurance one level down.
- **`Stav` runs `otevřeno` → `zavřeno`, and confirmation is not keyed on
  it.** A row closes only with a non-empty `Potvrzeno (SHA)`, whatever `Stav`
  says; a row whose `Stav` claims `zavřeno` over an empty SHA still blocks.
- **Who fills `Potvrzeno (SHA)`: the ticket named in `Předpokládá o
  (tiket)`**, with the SHA of ITS OWN commit carrying that evidence. That is
  also the ticket whose handoff the block fires on, so **the remedy belongs to
  that integrating session** and to no other. No commit of `Vlastník (tiket)`
  can satisfy a column defined as a commit of the assumed-about ticket, and that
  owner's session may be finished and closed; the owner is context to REPORT —
  whose decision is waiting — never the actor to wait for.
