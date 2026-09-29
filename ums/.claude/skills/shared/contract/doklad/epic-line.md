# Doklad — The epic line
Part of contract 3.x — evidence read on demand, never the home of a rule.

## Why the epic line is unprotected

**Until contract 3.2 the epic line was a protected branch with an actor-rule
exception**: it belonged in `protectedBranches`, and `guard-git-push.mjs` let
the agent's own tool call fast-forward it under four conditions (destination
matching `epicBranchPattern`, destination protected, destination not
`<baseBranch>`, raw-SHA source), so that only the manager's `integrate` could
push it. Practice did not follow: in the monorepo (2026-09-29) the lines
`origin/epic/SKODASMS-237` and `origin/epic/UMS-3557` existed, were NOT
protected, and `epicBranchPattern` was absent — the contract of that day would
have stopped both as a base. The four-condition exception was therefore dead
code over a configuration nobody wrote, and it was removed with its tests.

**What replaced it moves the question** from WHO MAY PUSH WHAT back into WHAT
MAY BE A BASE: `epicBranchPattern` no longer exempts a protected branch from the
actor rule, it identifies an unprotected branch as a legitimate base. The
default `epic/*` for a missing key is a deliberate widening, decided by the
user in the design opposition — an epic is meant to run without an extra
configuration step — and it is the human's decision recorded in the design,
not the code's.

## The residual risk: go is not enforced

**Recorded so that the rule does not look enforced.** The `go` of the manager
is what the integration waits for, but nothing binds it to the push: the
`pre-push` hook judges content (a fast-forward, no deletion) and the epic line
is unprotected, so any agent session holding a descendant of the line can
fast-forward it — before any handoff, without a `go`, or with a commit added
after the handoff the manager checked. The tip verification the ticket runs
after `go` catches a line that MOVED; it cannot catch a ticket that pushes more
than it handed over. The user accepted this in the design opposition: binding
the checked commit to the pushed one would need either a protected line with an
agent exception (the removed mechanism) or state shared between two sessions
that a push guard would have to read. What still holds is the hook's floor —
only fast-forwards, no deletion — and the human exit: whatever lands on the
line reaches the delivery line only through a human.

## The threat model

**The threat model is stated because the choice rests on it.** The pattern lives
in a file the agent may edit, so it defends against **mistake, not intent** —
the same trust model the rest of this contract runs on, where an agent never
setting `MB_HUMAN_PUSH=1` is likewise a rule and not a mechanism. A pattern
widened by mistake (`*`) would let an arbitrary unprotected branch be chosen as
a base without the fail-closed STOP; it would not open any protected branch,
because protection wins over the pattern. That is why a change to
`epicBranchPattern` stays on the Escalation floor, with the human,
unconditionally and at every autonomy level.

## What licenses an agentic write here

**What licenses an agentic write here at all is the single exit.** Not that the
push is contentless — it is not. The epic line reaches the delivery line only
through a human act, so the rule that the moment of integration belongs to the
human keeps holding where it decides anything: in the delivery line.

## A bare push and the epic line

**A bare `git push` from a ticket branch does not reach the epic line, and the
mechanism is not the PreToolUse guard's.** The `switch -c` that cuts a ticket
branch from `origin/epic/<EPIC-KEY>` sets the new branch's upstream to the epic
LINE (measured), and with no positional arguments `guard-git-push.mjs` resolves
the target through `addCurrent()`, which contributes the CURRENT BRANCH NAME and
no source — never the destination the upstream would resolve to; a ticket
branch is not a protected name, so its verdict is ALLOW, and the suite pins it
so. What keeps a bare push off the line is git's own `push.default=simple`,
which refuses when the upstream's branch name differs from the local branch's,
and the `git branch --unset-upstream` required right after the `switch -c`.
Since the line is unprotected, the `pre-push` content rule does not stand
behind them here — the unset-upstream step is load-bearing, not hygiene.
