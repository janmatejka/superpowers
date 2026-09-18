# Contract changelog

- **Contract-Version:** 3.0
- 3.0 — core / references / doklad split; Session Eligibility; Work Item
  Granularity; Phase Map; Message Protocol ordering; escalation floor row for
  playbook.md; jira.md; permalinkTemplate; contract-inject hook (UMS-3551).
  The 3 066-line contract becomes a core plus 17 `contract/*.md` references plus
  a `contract/doklad/*.md` evidence tier; every rule keeps its wording, only its
  home moves. The core carries a heading-checked citation form
  (`(contract, "Section")` / `(contract/file.md, "Section")`), a `Phase Map`
  saying which reference each skill and overlay reads, and a line budget
  enforced by `tests/contract-shape.tests.ps1`. New in the core: `Session
  Eligibility` (phase 0 of the entry gate, including the two-way synthetic
  pre-push self-check on an UNPUBLISHED commit), `Work Item Granularity` (a work
  item is as large as one verification set can verify), a `playbook.md` row in
  the escalation floor, and two Message Protocol ordering rules. The first
  publication with `-u`, the two push spellings, the two accepted bypasses and
  the foreign-hook chaining refusal move from the core into
  `contract/integration.md`, section "Publication mechanics"; the core states
  each as a rule and points there. New: `contract/jira.md` (ticket description
  template, budget, links), the `permalinkTemplate` repository-configuration key
  with `scripts/Get-UmsPermalink.ps1` as the single home of the permalink shape,
  `scripts/Test-UmsJiraDescription.ps1`, `scripts/Test-UmsContractMove.ps1`, and
  the `contract-inject.ps1` hook that injects the core at session start and on
  the first prompt after a compaction.
- v2.19 superseded v2.18 (the pre-push hook version is compared by ORDERING against
  the layer's own source header rather than by equality against a literal, so
  a stale layer copy can no longer downgrade a newer installed hook; adds the
  installer's restore of a clobbered Git LFS chain and the `mb-state`
  read-only detection of it).
- v2.18 superseded v2.17 (adds the `NOW` block — the marker-bounded region at the top
  of the SDD progress ledger that makes a stalled session visible without
  anyone reading its transcript, with its six required items, its closed state
  class, the rewrite-as-an-operation rule, the reader-safety rules it takes
  from the Session Intent Baton and the bound of its own lifetime; adds the
  Message Protocol — the single mark every orchestrator message carries, the
  recipient's right to refuse a conjecture and its duty to refuse an
  instruction that contradicts a written rule, relay timing decided by
  immediacy, and the enforcement status of every rule in a section nothing
  checks; and adds Escalation & Autonomy — the two rules about when ending a
  turn is legitimate at all, the three escalation bands and the artifact form
  every kind of escalation must have, and the three named autonomy levels over
  the one movable band, declared once per epic and overridable per ticket).
- v2.17 superseded v2.16 (adds the decision registry and the ticket's spawn
  row as preconditions of the epic fast-forward; adds the verification set — a
  verbatim list of commands whose home is whatever umbrellas the work, with
  a missing set fail-closed — together with the Handoff gate's fourth check;
  adds the shared-interface stub carried on the epic line and names who
  authors it; and removes the offered inline elaboration window from Epic
  Backflow, which now only queues the ledger note before the ticket session
  continues).
- v2.16 superseded v2.15 (Integration measures against the effective base
  rather than the raw `baseRef` key, gains the `Harvest` phase and states the
  Publish phase's re-merge, makes the epic manager's answer to the
  handing-over session an obligation of the Handoff phase, and resolves
  `<CTX_DIR>` by its definition instead of "from the configuration").
- v2.15 superseded v2.14 (states which `baseRef` spellings the epic-line exception
  accepts and that an unusable one yields no exception rather than the default
  base, and qualifies the `origin/develop` fallback accordingly).
- v2.14 superseded v2.13 (adds the epic line — the code integration branch of an
  epic, its membership in `protectedBranches`, and the `epicBranchPattern` key
  whose only consumer is the actor-rule exception in `guard-git-push.mjs`;
  rewrites Integration into ONE procedure for every effective base, with a
  handoff gate of three checks against a freshly fetched base and a single
  handoff artifact in two renderings; and drops the `Jira:` line from the IDLE
  reset, so the post-harvest `context.md` of every ticket integrating into the
  same branch is byte-for-byte identical).
- v2.13 superseded v2.12 (adds the pool-slot exception to the Worktree Policy and
  rewrites that policy's disk measurement; corrects the derivation of "a free
  workspace" for a shared-`.git` pool — which signals are per-worktree, that a
  stash cannot be attributed to a slot, and that a LIVE SESSION in a slot is a
  signal of its own that no git command knows; narrows two Workspace Discipline
  sentences to the actor; makes the baton's `Instruction` key required AND
  validated and states that the baton carries intent within one's OWN workspace
  only; records that neither the launcher's environment-variable list nor the
  path to `claude.exe` is repository configuration; and adds
  `git branch --unset-upstream` after the `switch -c` that creates a ticket
  branch).
- v2.12 superseded v2.11 (added the Session Intent Baton — an ephemeral,
  never-committed handoff file with a closed format, its reader's guards and
  exceptions, the writer precondition and the session-start precedence rule —
  and recorded that context rotation is a fifth, handoff-shaped stop class).
- v2.11 superseded v2.10 (rewrites the Publication Contract's two-tier push policy
  into an actor/content split, renames the human escape to `MB_HUMAN_PUSH`
  and widens it, and makes the workspace hook check session-scoped).
- v2.10 superseded v2.9 (added the Agentic Design Opposition section).
- v2.9 superseded v2.8 (splits the design/plan conflict rule by subject — what
  vs. how; renames the plan-header field `**Návrh:**` to `**Spec:**` with a
  read alias; adds Brainstorming Paths — the document layer's mapping of the
  upstream spike/bounded/architectural router; maps this layer's fail-closed
  STOPs into the upstream ruling model's stop classes; adds the ruling ×
  playbook-candidate boundary and the ledger/report language split; adds the
  first-publication rule `git push -u`).
- v2.8 superseded v2.7 (adds the effective base of a work item — the optional
  `Báze:` line in `context.md` with a fallback to `baseRef` — the invariant that an
  integration branch is always a protected branch, and the ordered remedy when it is
  not).
- v2.7 superseded v2.6 (adds the Epic Backflow section — design-approval check of
  the epic graph with a queued ledger note and an offered inline elaboration
  window — and the "Design Review" → "Review" status fallback with the
  `[DESIGN REVIEW]` request-comment marker).
- v2.6 superseded v2.5 (integration is a fast-forward push of the ticket branch, so
  the `--no-ff` convention is dropped; repository-specific values move out of
  skill bodies into `<CTX_DIR>/ums-repo.json`; the active-work limit becomes
  per-branch; workspace discipline and the park operation are added).
- v2.5 superseded v2.4 (the plan half is never linked from a document: the
  `**Plán:**` field is dropped from the design header and cross-references
  between the halves run plan → design only, because the plan is deleted at
  harvest and every link to it dies in the archive).
- v2.4 added Link Conventions under Scope Lock (links relative to the
  containing file, no `#fragment` anchors — section named in words instead —
  and the marking rule for undeterminable targets; enforced by
  `mb-link-audit`).
- v2.3 superseded v2.2 (narrows the mandatory document set to
  `brief.md`/`architecture.md`/`tech.md`, introduces `playbook.md` with the
  consult-before-write regime, adds Document Ownership and the playbook
  candidate collection). v2.2 added the Publication Contract and Cross-Branch
  Visibility; v2.0 renamed the document pair to `design_`/`plan_` and added the
  Architect Review Gate; v1 (mb-plan/mb-act orchestration) remains superseded.
  See `VENDORED_FROM.md` for the vendored Superpowers version.
