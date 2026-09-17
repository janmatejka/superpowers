# Brainstorming Paths
Part of contract 3.x — the core is ../UMS_MEMORY_BANK_CONTRACT.md; cite as (contract/brainstorming-paths.md, "Brainstorming Paths (spike / bounded / architectural)").

### Brainstorming Paths (spike / bounded / architectural)

Upstream brainstorming (v6.3.0) classifies each request before its first
question and announces the path. The document layer asks a single question
of that classification: **will the result integrate?**

- **Anything that will integrate needs a pin and a design — bounded
  included.** Bounded differs from architectural in exactly two ways: it
  writes no `plan_<slug>.md` and it does not run
  subagent-driven-development. Its short in-chat design is, upon approval,
  WRITTEN to `<PLAN_MB>/proposals/active/design_<slug>.md` (same header,
  body scaled to the change), so harvest, integration, Jira and the archive
  work unchanged. A design without a plan sibling is already a valid state
  (Active Work Item).
  **That written design also carries the `## Ověřovací sada` section**, in
  the shape every home of the set uses — one fenced code block, one command
  per line (Publication Contract, "Integration"). It is written HERE because
  this is where a bounded work item's only document is written: the plan
  step, which is where every other work item declares its set, is the step
  bounded skips. Without it, every bounded work item would reach the Sync
  phase of integration, find nothing declared, and hit that phase's
  fail-closed STOP — a guaranteed stop on the normal path rather than an
  exceptional one.
- **A spike pins nothing and writes nothing under `proposals/`.** The entry
  gate (Workspace Discipline) runs its eligibility, leftover-inventory and
  decision phases; a branch is created as soon as the spike is to touch the
  tree — a spike that modifies files never runs on the base; a purely
  read-only probe needs no branch. The pin-write phase is ALWAYS skipped.
  When the answer turns into work to keep, the request is reclassified and
  the gate completes.
- The ratchet is upstream's and one-way. "This wants an architect's review"
  is itself an architectural signal — the Architect Review Gate exists on
  the architectural path only.

Document headers:

- `design_<slug>.md` starts with:
  ```markdown
  # Návrh: <název>

  - **Jira:** UMS-XXXX | (žádný tiket)
  - **Target MB:** <relative path>/memory-bank/
  - **Vytvořeno:** YYYY-MM-DD
  ```
  The header carries **no reference to the plan half** — the plan is named
  `plan_<slug>.md` by the naming rule, so the field added nothing and became a
  dead link the moment harvest deleted the plan (Link Conventions).
  Body sections follow the established proposal corpus: `## Cíl`, `## Scope`,
  `## Technický návrh`, `## Dopady`, `## Rizika` (scaled to complexity).
- `plan_<slug>.md` keeps the upstream plan header verbatim (the
  "For agentic workers: REQUIRED SUB-SKILL …" block is load-bearing for
  subagent-driven-development), followed by an MB metadata block (`**Jira:**`,
  `**Spec:** [design_<slug>.md](design_<slug>.md)`, `**Target MB:**`), then the
  upstream structure (`## Global Constraints`, tasks with `**Interfaces:**`
  and checkbox steps).
  Readers MUST accept the legacy field name `**Návrh:**` as an alias of
  `**Spec:**` (plans written under contract ≤ v2.8); writers write only
  `Spec`. The English name keeps the plan's AI-facing boilerplate English
  (Language Contract) and matches the field upstream's
  subagent-driven-development reads ("if the plan names a Spec, read that
  too") — a differently-named field would make every ruling provisional.
