<!-- TARGET: writing-plans/SKILL.md -->
<!-- ANCHOR-BEFORE: **Which approach?"** -->
<!-- ASSERT: **"Plan complete and saved to `docs/superpowers/plans/<filename>.md`. Two execution options:** -->
<!-- ASSERT: **1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration -->
<!-- ASSERT: **2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints -->

<!-- UMS-OVERLAY BEGIN (ums-memory-bank v2) -->
**3. Fresh Session** (recommended for larger plans, or when the design
discussion ran long) - I write a session intent baton and stop; you type
`/clear`, and the next session starts on the plan with none of this
conversation.

**Two corrections to the sentence above, which this repository overrides.**
First: it says "Two execution options"; here there are THREE, and the menu you
present to your human partner lists all three. Second: it names
`docs/superpowers/plans/<filename>.md`; in this repository the plan was saved to
`<PLAN_MB>/proposals/active/plan_<slug>.md` and that upstream path is blocked by
a PreToolUse hook — name the real path when you present the menu. The upstream
sentence stays visible above this block, so it is negated here by name rather
than left to look valid.

**If Fresh Session chosen:**

1. Write the session intent baton per `../shared/UMS_MEMORY_BANK_CONTRACT.md`,
   section "Session Intent Baton": `Kind: plan-execution`, the plan path, the
   spec path, the branch, the slug, the ticket when there is one, and an
   `Instruction:` line naming subagent-driven-development.
2. Report in Czech, ONE short paragraph, and END THERE. Do not dispatch
   anything. Do not offer to continue in this session after writing the baton —
   the whole point of the option is that this session stops.

**Writer precondition:** per that same contract section, write no baton where no
consumer will read it. Where the precondition fails, do NOT offer option 3 at
all — the menu stays at two and the upstream text holds as written.

Why this beats option 1 for a large plan: the next session receives a
CONSTRUCTED brief — plan, spec, branch, slug — instead of whatever the operator
remembers to re-type, and it starts with none of the brainstorming transcript.

Deliberately NOT part of this option: a "how many tasks per session" figure. The
context-rotation stop in subagent-driven-development re-decides at every task
boundary from the actual remaining context, which is better information than
anything available at planning time, when task sizes are still unknown. If a cap
is ever wanted it belongs in the plan file, not in the baton — the baton is
consumed once, a cap applies to the whole execution.

**A note on where this block sits.** A fragment has a single anchor, so the
handling of option 3 stands BEFORE the "Which approach?" question while the
handling of options 1 and 2 stands after it. That asymmetry is deliberate:
priority goes to the menu your human partner actually sees, which must be
complete at the moment the question is asked.
<!-- UMS-OVERLAY END -->
