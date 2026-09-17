# Doklad — The epic line
Part of contract 3.x — evidence read on demand, never the home of a rule.

## The residual risk of condition 3

**The residual risk, plainly:** in a repository whose work items integrate into
maintenance branches other than `baseRef`, combined with an over-broad
`epicBranchPattern` (`*` is contemplated as a realistic mistake in
contract/epic-line.md, in the four-condition list),
condition 3 excludes `baseRef`'s own branch and nothing else — so the actual
delivery line of such a work item is excluded by conditions 1 and 2 only.
**The control that covers it is not another condition here**, and adding one
would mean resolving an effective base inside a push guard, which is new design:
it is the Escalation floor (`## Escalation & Autonomy`), which puts a change to
`epicBranchPattern` or `protectedBranches` with the HUMAN, unconditionally and
at every autonomy level. The pattern is how that risk is entered, so the pattern
is where it is guarded.

## What each condition closes, and what the raw-SHA test does not do

Each condition closes its own hole. Without the protected test, configuration
would grant push rights over a namespace nothing guards. Without the
`baseBranch` exclusion, a pattern of `*` would swallow the base itself. And the
raw-SHA test is what keeps a REFSPEC-LESS invocation from reaching the
exception: the `switch -c` that cuts a ticket branch from
`origin/epic/<EPIC-KEY>` sets the new branch's upstream to the epic LINE
(measured), so the `git branch --unset-upstream` required with it stops being
hygiene here.
**What the raw-SHA test does NOT do is stop a bare `git push`, and the mechanism
is worth stating exactly, because it is not this guard's.** Verified in
`guard-git-push.mjs`: with no positional arguments the evaluation resolves the
target through `addCurrent()`, which contributes the CURRENT BRANCH NAME and no
source at all — never the destination the upstream would resolve to. A ticket
branch is not a protected name, so the guard's verdict on a bare push from one
is ALLOW, and the suite pins it as such. What actually keeps a bare push off
`origin/epic/<KEY>` is git's own `push.default=simple`, which refuses when the
upstream's branch name differs from the local branch's, plus the `pre-push`
content rule while the ticket branch is unpublished. The guarantee holds; it is
simply owed to git and to `pre-push`, and a reader who believed this guard
carried it would look for it in the wrong file.

## The threat model

**The threat model is stated because the choice rests on it.** The pattern lives
in a file the agent may edit, so this exception defends against **mistake, not
intent** — the same trust model the rest of this contract runs on, where an agent
never setting `MB_HUMAN_PUSH=1` is likewise a rule and not a mechanism. Reading
the pattern from the base instead was weighed and dropped as complexity that buys
nothing under that assumption.

## What licenses an agentic write here

**What licenses an agentic write here at all is the single exit.** Not that the
push is contentless — it is not. The epic line reaches the delivery line only
through a human fast-forward, so the rule that the moment of integration belongs
to the human keeps holding where it decides anything.

## The third category

**A third category does exist:** "a protected branch an agent may push to". What
the epic line changes is where the category sits — it moved out of the question
WHAT MAY BE A BASE into the question WHO MAY PUSH WHAT, which is the smaller of
the two and the better guarded.
