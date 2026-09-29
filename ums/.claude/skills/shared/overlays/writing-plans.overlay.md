<!-- TARGET: writing-plans/SKILL.md -->
<!-- ANCHOR-BEFORE: **When an execution method has already been supplied:** -->
<!-- ASSERT: **"Plan complete and saved to `docs/superpowers/plans/<filename>.md`. Please review the plan. Which execution approach would you prefer?** -->
<!-- ASSERT: - **Subagent-driven** - A fresh subagent implements each task and a fresh reviewer checks it before the next one starts, then a whole-branch review at the end. Most thorough; costs a fresh context per task and per review. -->
<!-- ASSERT: - **Native** - I implement every task myself in this session, the way this harness runs work, then one fresh reviewer on the most capable model checks the whole branch. Cheapest and fastest; no independent review until the end. Runs well with a mid-tier session model, since the plan carries the design. -->

<!-- UMS-OVERLAY BEGIN (ums-memory-bank v2) -->
**The plan file itself carries a `## Ověřovací sada` section**, per
(contract/integration.md, "Integration") — add it before
linking the plan for review. **The shape is ONE FENCED code block under that
heading, one command per line**, because a single reader parses all three homes
of the set and it reads the fence; a bulleted or plain list under a correct
heading yields nothing and later reads as "no set declared at all".

**The plan path in this section is overridden.** Both "Plan complete and saved
to…" sentences of this handoff — the one above this block and the one below it
— name `docs/superpowers/plans/<filename>.md`. In this repository the plan was
saved to `<PLAN_MB>/proposals/active/plan_<slug>.md`, and that upstream path is
blocked by a PreToolUse hook — name and link the real path. The upstream
sentences stay visible, so they are negated here by name rather than left to
look valid.

**Fresh Session — a modifier of either method, not a third method.** The menu
above stays at its two methods, Subagent-driven and Native. Once the method is
settled — chosen from that menu, or already supplied (the branch below) — and
your human partner has reviewed the plan, ask ONE follow-up question: execute
it in this session, or in a fresh one. Recommend the fresh session for a larger
plan or when the design discussion ran long. Two conditions, both required:

- **The writer precondition holds** (contract/session-intent-baton.md, "Session Intent Baton").
  Where it fails, do not ask at all — no consumer would read the baton, and the
  chosen method runs in this session exactly as the upstream text says.
- **Your human partner has reviewed the plan.** The upstream handoff waits for
  that review before implementation; a fresh session would start implementing
  on its first move, so a plan nobody reviewed is never handed to one. If they
  already asked for a fresh session when supplying the method, that is the
  answer — do not ask again.

**If Fresh Session chosen** (with either method):

1. Write the session intent baton per
   (contract/session-intent-baton.md, "Session Intent Baton"): `Kind: plan-execution`, the plan path, the
   spec path, the branch, the slug, the ticket when there is one, and the
   `Instruction:` line naming the chosen executor — `subagent-driven-development`
   for Subagent-driven, `executing-plans` for Native.
2. Report in Czech, ONE short paragraph, and END THERE — for example: „Plán je
   uložený v `<cesta k plánu>` a pro čerstvé sezení jsem zapsal baton (metoda:
   <Subagent-driven | Native>). Napiš `/clear` — nové sezení začne rovnou
   exekucí plánu, bez této konverzace.“ Do not invoke the executor and do not
   offer to continue in this session after writing the baton — the whole point
   of the option is that this session stops.

**If this session chosen**, or the question was not asked: the "If
Subagent-driven chosen" / "If Native chosen" lines below hold as written.

Why a fresh session beats this one for a large plan: the next session receives
a CONSTRUCTED brief — plan, spec, branch, slug, method — instead of whatever the
operator remembers to re-type, and it starts with none of the brainstorming
transcript.

Deliberately NOT part of this option: a "how many tasks per session" figure.
The context-rotation stop of both executors re-decides at every task boundary
from the actual remaining context (contract/session-intent-baton.md, "The context-rotation stop"), which is better
information than anything available at planning time, when task sizes are
still unknown. If a cap is ever wanted it belongs in the plan file, not in the
baton — the baton is consumed once, a cap applies to the whole execution.

**Where this block sits.** It stands between the two branches of the handoff —
the menu for "no execution method supplied" above, the "already supplied"
branch below — because the path override and the Fresh Session question apply
to both; the "If … chosen" lines at the end of the file follow the answer.
<!-- UMS-OVERLAY END -->
