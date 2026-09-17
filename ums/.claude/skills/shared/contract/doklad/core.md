# Doklad — Core
Part of contract 3.x — evidence read on demand, never the home of a rule.

## Why the pin write decides the Báze line

The line has two ways to outlive the work item that wrote it: the IDLE reset of the
core's `` ## `context.md` Schema & Writers `` (whose own consumers are
contract/harvest.md and contract/integration.md) keeps it on purpose, and the
integration push carries that IDLE `context.md` onto
the base itself, from where every later work item's branch is cut. A pin write that
only ever ADDS the line therefore lets one work item's maintenance branch become
the silent default for all the work that follows it — base sync, harvest diff and
the integration command would all name a branch nobody chose.

## Why the IDLE reset drops Jira

**`Jira:` goes because of the invariant this reset exists to keep: the
post-harvest `context.md` of every ticket integrating into the same branch is
byte-for-byte identical.** That is what makes the integration merge
conflict-free — the ticket's net contribution to the file is nothing, so the
three-way merge has nothing to reconcile. A residual `Jira:` line breaks it,
because on a branch many tickets integrate into every ticket writes a different
value into that one line, and "the last work item" then names not an identity but
whoever integrated most recently. The ticket's identity lives in the design
document's header; it was never this line's job. The rule is **not**
epic-specific: every shared branch that more than one ticket integrates into
collects that residue.

## Note for whoever changes the IDLE reset

Note for whoever changes this reset: `mb-jira-update` runs after the harvest
(Publication Contract, "Integration"), so the change must verify where
`mb-jira-update` takes the ticket key from at that point.

## Document Ownership, the third case

The third case carries the rule. Duplication does not arise for facts that
clearly belong somewhere — it arises for the ones that belong in both.
