# Doklad — Publication Contract
Part of contract 3.x — evidence read on demand, never the home of a rule.

## Auditability, not review

**That is a guarantee of auditability, not of review.** The publication rule
lets the agent publish its own ticket branch unassisted, so it can make any
commit reachable on `origin` and then fast-forward the base onto it. The rule
that the MOMENT of integration belongs to the human is carried by the
PreToolUse layer alone — therefore only in harnesses that have one, and only
for command shapes it can parse; the epic line is its one deliberate carve-out
(Repository Configuration, "The epic line"). Elsewhere it is a contract
obligation like every other rule of this layer, and server-side branch
permissions remain the real backstop.

## What the reachability claim proves

Read the reachability claim narrowly: the hook never contacts the remote. It
asks whether the pushed tip is reachable from THIS CLONE's own
`refs/remotes/<remote>/*` for the remote being pushed to. Those refs are local,
writable artifacts — a `git update-ref` satisfies the test with nothing
published, and a stale tracking ref left behind by an earlier fetch answers
just as confidently. That is accepted, and it is why the paragraph above calls
the result auditability rather than proof of publication: what keeps an agent
away from the push that would exploit it is the actor rule, in the harnesses
that carry one.

## How the installer recognizes its own hook

`install-git-hooks.ps1` runs these checks itself after installing — with the
marker set on each run — reports the result and exits non-zero whenever the
guarantee is not in place. The substring
`UMS pre-push guard (Publication Contract)` is what the installer recognizes
its OWN hook by, so a pre-v2 hook is still recognized as ours and overwritten
rather than treated as a foreign hook; the version suffix is compared by
ORDERING against the layer's own source header, not by equality against a
literal, so it distinguishes a hook that is at least as new as the layer from
one a stale workspace still carries, and an older one is repaired by
re-running the installer.

## Which rejections name the escape

The hook announces the escape on stderr whenever it honours it. Of its
rejections only the shared-branch one names the escape; the deletion and
force-push rejections do not, so a human who hits either of those two walls has
to know the escape already. That the agent never sets it is contract text, like
every other rule of this layer that no mechanism can enforce — which is why the escape is a
named variable rather than a flag the agent could plausibly have typed by
accident.

## A configured core.hooksPath is not a bypass

A **configured** `core.hooksPath` (local or global — routine with tools like husky
or pre-commit) is a different thing and is **not** a bypass. It moves the
directory git looks in, and every check in this layer resolves the hook through
`git rev-parse --git-path hooks/pre-push`, which honours it: the installer
installs there and proves the hook live there, and `mb-state` and the entry gate
find it there. The remaining concern is **provenance and scope**, not bypass — a
shared hooks directory may already hold another repository's `pre-push`, and an
install or a removal in it reaches every repository using that config. The
`UMS pre-push guard` marker check settles provenance, and an absolute value is
therefore reported as a scope warning rather than a missing guarantee (a relative
value is resolved per working tree instead, so each linked worktree needs its own
install). A missing or unmarked hook stays fail-closed either way.

## The PreToolUse guard, what it reads and what it misses

The PreToolUse hook (`.claude/hooks/guard-git-push.mjs`) is not a guarantee —
it does not see shell syntax the way git itself does. What it carries is the
actor rule, so on what it DOES recognize as a `git push` it leans
fail-CLOSED: a push whose destination it cannot read is denied rather than
waved through. Two conditions bound that arm, both named in the file itself: an
unreadable token carrying a shell EXPANSION excuses the problem it caused,
because such a token names something that is genuinely not in the string at
all; and the arm fires only where the `git` token is visibly at a COMMAND
POSITION, which anything other than a closed list of left neighbours hides — a
newline, a separator glued to the previous token (`cd /repo; git push …`) or to
the `git` token itself (`X=1|git push …`), and a shell KEYWORD that is not an
operator (`if true; then git push …`). An accepted gap in every one of those
shapes, because promoting them to
separators would re-open the heredoc case this rule exists to protect. What
that gap does NOT cost is the deny on a target the guard can read in plain
text: a cleanly-written invocation naming a protected branch is judged whether
or not command position holds. Shell REDIRECTION is a separate thing from those
separators and is handled the way a real shell handles it: it is REMOVED from
the invocation's arguments (with its target, whether that sits in the next token
or glued to the operator) and the scan carries on past it, so `git push origin
<branch> 2>&1 | tail -3` is read as the push it is and `… > develop` writes a
file rather than pushing a branch — while a protected branch written AFTER a
redirection is still judged, because in a shell it is still an argument. That
holds for a redirection standing between `git` and its SUBCOMMAND as well
(`git 2>&1 push origin develop`, which a shell hands to git as plain `push
origin develop`); until the pre-subcommand scan stepped over redirections the
same way, that shape made the `push` token invisible and was a silent ALLOW.
PowerShell's all-streams spellings (`*>`, `*>>`, `*>&1`) count as redirections
here too, because this fork's sessions run on the PowerShell tool.
**Two routes reach past the guard's judgement altogether, both
named and neither closed.** A
`git` token it cannot recognize as one at all (`bash -c 'git push …'`, whose
token is `'git`, quote and all) never reaches it; and neither does a recognized
`git` whose SUBCOMMAND token is not `push` because a git ALIAS stands in for it
(`git -c alias.zz=push zz origin <base>`, measured ALLOW with the guard silent —
the pre-subcommand loop skips `-c` and its argument exactly as intended, and `zz`
is simply not `push`). The alias route costs more than the first one: `pre-push`
still stops a non-fast-forward, but the integration FAST-FORWARD — precisely what
the actor rule reserves for the human — goes through in a single ordinary tool
call. Closing it would mean asking git what a token means, the class of parsing
this layer was deliberately demoted for, so it is named here instead. The count
is TWO and not three because the redirection-before-subcommand shape, which
belonged to the alias's own class (a recognized `git` whose subcommand token is
not `push`), is closed — it needed no knowledge of what git makes of a token,
only shell syntax this file already reads. The command-position carriers listed
further up are a weaker, separate class and are deliberately not counted among
these two: they blunt the fail-closed arm, but a protected target the guard can
read in plain text is still denied through them — measured on a newline, on
`cd /repo;`, and on the keywords `then`, `do` and `{`, all five DENY. The one
entry in that list which is NOT merely weaker is `X=1|git push …`: there the
token IS `X=1|git`, so it is the first route above wearing a command-position
disguise, and nothing about the push is judged at all. Subcommands
other than `push` are not its concern either, and `git fetch` keeps its own
narrower, best-effort refspec rule. Two checks deliberately read the raw command TEXT
rather than a parsed invocation — the escape variable's name, and
`--no-verify` — and the accepted price is that an agent merely WRITING either
one from a shell tool is denied as well. Read the verdict from `evaluatePush`
itself; this contract deliberately does not restate its branches, because every
earlier summary of them went stale. Neither hook stops a determined adversary; server-side
branch permissions on `origin` remain the real backstop for that. A harness without a
PreToolUse layer follows the actor rule by contract text only, as with every
other rule of this layer. `mb-git-commit` never pushes — publication is a
workflow step governed by the publication rule above, not a job of the commit
tool.
