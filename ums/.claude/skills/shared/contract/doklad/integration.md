# Doklad — Integration & Abandon
Part of contract 3.x — evidence read on demand, never the home of a rule.

## Why an unpublished abandon is a collision nobody can clear

Step 3 is the step that is not obvious and therefore the one that gets skipped. An
abandon that is not published exists only in the local `.git` that performed
it (a pool slot shares that `.git` with every other slot, so the commit is
visible there too) — but never on `origin`: the branch still carries the
ACTIVE pin there, with the pair still in `active/`,
so `mb-doc-index` keeps reporting that slug and that ticket as active work — a
`KOLIZE AKTIVNÍ PRÁCE` no later session can clear, which means the ticket can never
be picked up again. The exemption granted to an integrated branch does not help
here: the index keys by phase, and `abandoned/` is not an active phase.
