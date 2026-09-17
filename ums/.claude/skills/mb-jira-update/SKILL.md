---
name: mb-jira-update
description: Extract implementation status and deployment instructions from active proposals and publish a summary comment to Jira.
license: MIT
metadata:
  author: UMS Project
  version: "2.4"
---

> Contract core: [UMS_MEMORY_BANK_CONTRACT](../shared/UMS_MEMORY_BANK_CONTRACT.md) · References: [jira.md](../shared/contract/jira.md), [integration.md](../shared/contract/integration.md). Read the named references before acting.

# Command: mb-jira-update

**Action:** Extract implementation status and deployment instructions from active proposals and publish a summary comment to Jira.
**Precondition:** `- **Jira:** <ID>` must exist in the design document's header — the active one in `<PLAN_MB>/proposals/active/`, or, after the harvest, the archived one in `<PLAN_MB>/proposals/completed/` — in `<CTX_DIR>/context.md`, or be provided in the user prompt, in that order.

**Model selection:** producing the Czech Jira note is summarization work — if invoked as a delegated/isolated session (e.g. offered by `mb-harvest` from the finishing-a-development-branch harvest gate), run it on the cheapest capable tier (see [UMS_MEMORY_BANK_CONTRACT.md](../shared/UMS_MEMORY_BANK_CONTRACT.md), section "Dispatch Model Policy").

---

## Workflow

### 0. Resolve MB_ROOT (MANDATORY)

Resolve `MB_ROOT` with exactly one discovery step:

```bash
git rev-parse --show-toplevel
```

Rules:

- Use the git root as the only MB root model.
- If `git` is missing or the command exits non-zero, stop immediately with: `Git repository not found. Memory Bank requires git.`
- On success, set `MB_ROOT` to the returned git root and `CTX_DIR` to `<MB_ROOT>/memory-bank/`.

**Scope lock (Memory Bank files):**

- Read and write Memory Bank files only inside `CTX_DIR`, `PLAN_MB`, and `AFFECTED_MBS` during harvest unless the user explicitly requests cross-project synchronization.
- The root `context.md` is the only operational state file described by this handshake.

**Before first write, announce:**

- `[Memory Bank: Active - <ProjectName> @ <MB_ROOT>]`
- `Orchestrační kořen: <CTX_DIR>/, Cílová MB: <PLAN_MB>/`
- `Reason: git-root discovery`

### PLAN_MB Derivation

If `<CTX_DIR>/context.md` exists, read the `## Active Work` → `Target MB Pin` field to derive `PLAN_MB`. If the pin is missing, `context.md` does not exist, or the pin points to a non-existent directory, `PLAN_MB` is **undefined**. Do NOT silently default to `<CTX_DIR>`.

Target-MB Discovery & Pinning runs in the superpowers workflow (contract/target-mb-discovery.md, "Target-MB Discovery & Pinning"); this skill never selects a target itself.

If the protocol is exhausted and no trusted candidate remains, STOP and ask the user to confirm `<CTX_DIR>` as the target or provide an explicit path. Do NOT silently fall back to `<CTX_DIR>`. If the user confirms `<CTX_DIR>`, use it as `PLAN_MB`.

### Language Contract

- Communication with the user in Memory Bank workflows MUST be in Czech.
- Proposals and persistent Memory Bank documents (brief.md, architecture.md, tech.md, playbook.md, context.md) MUST be in Czech.
- Mixed language policy in the same rule surface is invalid and must fail closed.

### 1. Load Context & Detect Phase (MANDATORY)

Use a **Session Cache** keyed by `MB_ROOT` and the current workflow session. Within one workflow session, cached refresh is the default; full reload is an invalidation path, not the normal path.

#### 1.1 Determine load mode

Prefer the lightest valid mode for the current workflow step:

- **bootstrap/full**: first access for `MB_ROOT`, `MB_ROOT` changed, explicit reload/rescan, fingerprint mismatch, before a critical operation, or any uncertainty about context integrity
- **cached**: same-session workflow step with no invalidating write; read `context.md` and the active proposal pair referenced from it
- **delta refresh**: after a Memory Bank write in the current session; re-read only the touched files plus `context.md`, then validate the narrowed fingerprint set

Rules:

- Do not full reload again just because another workflow step started in the same session.
- If a local step or delegated worker changes Memory Bank files, invalidate only the touched paths.
- If the cache cannot be validated, fall back to full reload.

#### 1.2 Full reload path

Read the root state first, then the work it points to:

- read `<CTX_DIR>/context.md`
- read the active proposal pair (or grandfathered legacy single file) referenced by the `Work item` slug (legacy `Proposal` accepted) in `## Active Work`
- read any project docs explicitly needed for the current workflow step; task progress lives in the plan file's checkboxes and `.superpowers/sdd/<plan-basename>/progress.md`, not in `context.md`

Then:

- refresh the session summary and fingerprint table
- emit marker:
  - first full load in session: `[Memory Bank: Active - <ProjectName> @ <MB_ROOT>]`
  - trigger-based reload: `[Memory Bank: Reloaded - <ProjectName> @ <MB_ROOT>]`
- record `Last Full Reload: <timestamp>`

#### 1.3 Cached path (no trigger)

Do a lightweight refresh from the root state:

- read `<CTX_DIR>/context.md`
- inspect the active proposal pair referenced by the `Work item` slug (legacy `Proposal` accepted) in `## Active Work`
- refresh any Memory Bank files touched by the current workflow step (affected MBs are derived from the git diff at harvest, not tracked in `context.md`)
- validate fingerprints against cache; if mismatch appears or the touched set is broader than expected, switch to full reload
- emit marker: `[Memory Bank: Cached - <ProjectName> @ <MB_ROOT>]`
- preserve previously recorded `Last Full Reload`

This policy keeps context fresh while preventing redundant full reads between tasks.

### Phase Detection

**Workflow phase is derived from the root `context.md`:**

- If `<CTX_DIR>/context.md` is missing, set `PHASE = IDLE` — the file is created by the superpowers workflow (Target-MB Discovery & Pinning during brainstorming).
- Read the `## Active Work` section in `<CTX_DIR>/context.md`.
- If `## Active Work` is empty or contains `(No active work - IDLE phase)`, set `PHASE = IDLE`.
- Otherwise set `PHASE = ACTIVE_WORK`.
- The `Work item` slug (legacy `Proposal`) in root `context.md` is only a pointer to the active proposal pair; it is not the phase source.
- Ignore any abolished v1 state fields when found in a stale file (contract v2 lists them).

### Phase Implications

- **IDLE:** No active work in root `context.md`; new work starts with the superpowers workflow (describe what to build → brainstorming)
- **ACTIVE_WORK:** Root `context.md` contains active work; the referenced proposal pair (`design_<slug>.md` + `plan_<slug>.md`, legacy `proposal_<slug>-design.md` + `proposal_<slug>.md`, or a grandfathered single plan file) lives under `<PLAN_MB>/proposals/active/`. The sub-phase is read from the workflow artifacts, not from `context.md`:
  - **Design only** (no plan sibling yet): between brainstorming and writing-plans
  - **Pair complete, no task progress:** ready for subagent-driven-development / executing-plans
  - **Tasks in progress:** plan checkboxes and `.superpowers/sdd/<plan-basename>/progress.md` show partial completion
  - **All plan tasks complete:** ready for finishing-a-development-branch (harvest gate → `mb-harvest`)

### Write Safety Gate (MANDATORY)

Before any Memory Bank write operation:

1. List target files.
2. Verify all target files are under `<CTX_DIR>/, <PLAN_MB>/, or <AFFECTED_MBS>/`.
3. If any target is outside `<CTX_DIR>/, <PLAN_MB>/, or <AFFECTED_MBS>/` and the user did not explicitly request cross-project sync, stop and ask.

Scope lock remains active until command completion.

### 1. Jira Ticket Check
- Check the `- **Jira:** <ID>` header line of the active design document in
  `<PLAN_MB>/proposals/active/` (`design_<slug>.md`, legacy
  `proposal_<slug>-design.md`) for `<ID>` (excluding empty, `(no ticket)`, and
  legacy `(bez tiketu)` variants). This is the primary source — see
  `context.md` Schema & Writers, "IDLE state", for why `context.md` no longer
  carries the ticket after harvest.
- If missing, check the same header line of the ARCHIVED design document in
  `<PLAN_MB>/proposals/completed/` (`design_<slug>.md`, legacy
  `proposal_<slug>-design.md`) — the harvest moves the design there and the
  finalization mode runs after the harvest, so in that mode this is the source
  that actually carries the ticket.
- If missing, check `<CTX_DIR>/context.md` for `- **Jira:** <ID>` (same exclusions).
- If still missing, check the user prompt using regex `[A-Z]{2,10}-\d+`.
- If no valid Jira ID is found, STOP and ask the user to provide the Ticket ID.
- Do NOT proceed without a valid Ticket ID.

### 2. Information Extraction
- Read the content of `<CTX_DIR>/context.md`.
- Prefer data from the active proposal pair (design + plan) resolved from the `Work item` slug (legacy `Proposal` accepted) in root `context.md` when active work exists.
- If the proposal was already finalized and archived, read the completed design document `<PLAN_MB>/proposals/completed/design_<slug>.md` (or legacy `proposal_<slug>-design.md`) (after harvest only the design half is retained there; the implementation plan is deleted).
- Do not fail only because the proposal is no longer active when a completed proposal/finalization handoff is available.
- Extract the following information:
  - **Summary of changes:** What was implemented or modified.
  - **Current status:** Whether the implementation is complete, in progress, or aborted.
  - **Verification:** A short outline of tests run and any known risks or issues.
  - **Deployment instructions:** Technical notes for the implementation team, including configuration and network requirements for customer deployment.
  - **Implementation team notes:** Explicitly list impacted configuration, database or script changes, and affected modules or files. If the file list is large or repetitive, collapse it into a module-level link so the Jira comment stays readable.

### 3. Invocation Context
- `mb-jira-update` is typically offered by `mb-harvest` (from the finishing-a-development-branch harvest gate) after a successful harvest, or invoked standalone by the user.
- Any local commit created during SHA stabilization (step 6) requires explicit user confirmation.

### 4. Build Referenced File Set (Priority Order)
- Build list of link targets in this order:
  1. Changed deployment-relevant configuration files (typically `scripts/config.json` and other changed config files).
  2. Changed stable Memory Bank docs (`architecture.md`, `tech.md`, `brief.md`, the design document `design_<slug>.md` (or legacy `proposal_<slug>-design.md`) — the durable artifact kept after completion; the implementation plan `plan_<slug>.md` (or legacy `proposal_<slug>.md`) exists only while work is active and is deleted at harvest).
  3. `context.md` only as a supplementary source, because it is unstable.
- Keep only paths that exist and are inside the same git repository as `MB_ROOT`.
- If the resulting file set is large, noisy, or spans many files from the same area, replace the file list with a single module-level link (the smallest meaningful directory that contains the touched files) instead of enumerating every file.
- Prefer a module link plus a short note about the most relevant files over a long file-by-file inventory.

### 5. Git Preconditions (FAIL-CLOSED)
- Verify git is available (`git --version`). If unavailable: **STOP** (fail-closed, do not publish).
- Resolve repository root (`git rev-parse --show-toplevel`). If fails: **STOP**.
- Resolve current HEAD SHA (`git rev-parse HEAD`). If fails or empty: **STOP**.
- Determine whether referenced files are committed in HEAD:
  - `git diff --name-only HEAD -- <referenced-files>`
  - Empty result => all referenced files are committed.

### 6. Stabilize SHA for Referenced Files Only
- If all referenced files are already committed:
  - use SHA from `git rev-parse HEAD`.
- If there are uncommitted referenced files:
  - ask for explicit user confirmation before creating a local commit that stages only the referenced files; without confirmation => **STOP**.
  - after the confirmed commit, refresh SHA via `git rev-parse HEAD`.
- Never commit unrelated repository files.

### 6b. Reachability gate (Publication Contract, MANDATORY)
- Runs on the SHA stabilized in §6 — a commit created there is local only, so
  this gate is the step that gets it onto `origin` before anything links to it.
- Verify: `git fetch origin` then `git branch -r --contains <sha>`. Empty
  result = **STOP** before publishing anything.
- Report the branch to publish and let the actor push it (own ticket branch,
  announced) or hand the command to the user for a shared branch
  (`! MB_HUMAN_PUSH=1 git push origin HEAD:<the current shared branch>` — this
  commit is local only per §6b's own opening line, so the content rule cannot
  apply yet and the escape is the only form that gets it through; the agent
  never runs it and never sets `MB_HUMAN_PUSH` itself, and never substitutes
  `--no-verify`). Re-verify after the push.
- A published link to an unreachable commit is the failure this gate exists to
  prevent.

### 7. Permalink Format
- URL from Get-UmsPermalink.ps1 (contract/jira.md, "Permalink"); branch fallback stays disabled.
- Only explicit user override may enable branch fallback; without explicit override stay fail-closed.

### 7b. Refresh the proposal link in the ticket description
- Besides the comment, keep ONE canonical, up-to-date link to the proposal in
  the ticket **description**, so it is always discoverable (not buried in
  comment history).
- Maintain a single line of the exact form, pointing at the **design**
  document (`design_<slug>.md`, or legacy `proposal_<slug>-design.md`) — the
  durable artifact retained in `completed/` — never the implementation plan,
  which is deleted at harvest:
  `**Návrh (design):** [<design-file>.md](<commit-pinned URL from §7>)`
- Idempotent update: if such a line already exists — including the legacy
  form `**Návrh (proposal):** …` — replace it (refresh SHA + path, re-point a
  stale plan/legacy filename to the design document); otherwise insert it
  near the top of the description. Change nothing else in the description.
- Run `Test-UmsJiraDescription.ps1 -RequireSections` on the resulting
  description before sending it; a finding is a STOP.
  Use `editJiraIssue` (contentFormat markdown).
- The permalink resolves immediately: §6b's reachability gate guarantees the
  pinned commit is on `origin` before the link is published.
- `mb-epic-graph -Check` reports `TIKET BEZ ODKAZU NA PROPOSAL` until the line
  is present, and `ODKAZ NA NEEXISTUJÍCÍ PROPOSAL` if it points at a stale
  filename — both VAROVÁNÍ.

#### 7b-1. Change one line WITHOUT risking the rest of the description

**The API has no partial-description edit.** `editJiraIssue` replaces the whole
field, so touching one line means re-emitting the entire description — often
many kilobytes of Czech prose with tables, `„ "` quotes, `$${…}` literals and
escaped quotes. Re-emitting it from context is the failure mode this repository
has already paid for (see the memory note about five diacritic slips across five
descriptions), and a silently mangled description is worse than a stale link.

There is no Atlassian CLI and no credentials on this machine, so a native
file-based update (`acli … --description-file`) is NOT available — verify before
assuming otherwise; if one ever is installed, prefer it and skip this whole
dance.

**Use this four-step procedure. It makes the edit scripted rather than retyped,
and it PROVES the result instead of trusting it.** Measured working on 2026-09-11
against a 10 202-character description.

1. **Download WITHOUT retyping — force the harness to persist the response.**
   The agent cannot pipe an MCP result into a file, but when a result exceeds the
   output limit the harness saves it to `…/tool-results/<name>.txt` and returns
   the path. Make it overflow on purpose by asking for more than one issue, then
   extract the field mechanically:

   ```powershell
   $j     = Get-Content $persistedFile -Raw | ConvertFrom-Json
   $desc  = ($j.issues.nodes | Where-Object { $_.key -eq '<TICKET>' }).fields.description
   [System.IO.File]::WriteAllText($orig, $desc, (New-Object System.Text.UTF8Encoding($false)))
   ```

   Use `searchJiraIssuesUsingJql` with `key = <EPIC> OR parent = <EPIC>`,
   `fields: [summary, description]`, `responseContentFormat: markdown` — measured
   to overflow reliably (76 159 characters for one epic). A single-issue
   `getJiraIssue` does NOT overflow even with `fields: ["*all"]`, so it does not
   produce a file; do not rely on it for this step. The `UTF8Encoding($false)`
   matters — a BOM would show up as a diff on line 1 later.

   **This is the step that removes transcription from the read path entirely.**
   Only fall back to writing the description out by hand if no persisted file can
   be produced, and say so in the report when you do.
2. **Patch by script, never by hand.** Let PowerShell do the replacement, and
   make it refuse to run if the target line is not in the expected shape — a
   silent no-match is how this step turns into a whole-description rewrite:

   ```powershell
   $lines = Get-Content $orig
   if ($lines[0] -notmatch '^\*\*Návrh \(design\):\*\* \[[^`\]]+\]\(https?://\S+\)$') {
       throw "první řádek nemá očekávaný tvar: $($lines[0])"
   }
   $lines[0] = '**Návrh (design):** [<design-file>.md](<commit-pinned URL>)'
   Set-Content -Path $new -Value $lines -Encoding UTF8
   ```

   Then `Compare-Object (Get-Content $orig) (Get-Content $new)` — it MUST report
   exactly one replaced line (two entries, one `=>` and one `<=`). This is the
   step that guarantees the intended diff; nothing after it can widen the change.
3. **Send** `desc-new.md`'s content through `editJiraIssue`.
4. **Prove it, with two independent comparisons.** Read the description back **by
   the same persisted-file route as step 1** — not by retyping — into
   `desc-after.md`, then:

   - `Compare-Object desc-new.md desc-after.md` → **must be empty.** This is the
     load-bearing check: it proves what Jira stored is what step 2 produced, so
     no transcription error crept into the send.
   - `Compare-Object desc-orig.md desc-after.md` → **must be exactly the one
     line.** Independent confirmation that nothing else moved.
   - Compare character counts as a third, cheap signal, and expect the delta to
     equal the intended edit. Watch the line-ending trap: `Set-Content` writes
     CRLF while a file written by the `Write` tool is LF, so a CRLF file reads
     one character longer per line. Compare `Get-Content -Raw` lengths only
     between files of the same line ending, or reason about the offset.

   If the first comparison is non-empty, the description in Jira is NOT what you
   meant to write — restore it from Jira's description history and retry; do not
   patch the patch.
5. **Delete the three scratch files** when the checks pass.

**Where the residual risk actually sits.** With step 1 and step 4 both going
through the persisted file, the ONLY place the description passes through the
agent's own output is step 3, the `editJiraIssue` argument. That is precisely
what the first comparison in step 4 measures, and it measures it mechanically:
`desc-new.md` came from a script, `desc-after.md` came from Jira through a
parser, and neither was retyped. An empty diff between them is therefore real
evidence that the send was faithful, not a self-confirming check.

This supersedes the older habit of reading the returned `description` out of the
tool response by eye — see the memory notes on Jira description edits; that
method could not distinguish a faithful send from a slip reproduced twice.

### 8. Publish to Jira
- First compose the Jira comment body in Czech as a brief, professional implementation note for the delivery team.
- Use this structure:
  - **Summary:** 1–2 sentences describing what changed.
  - **Affected configurations:** only relevant config files or configuration entries.
  - **Affected databases / scripts:** migrations, update scripts, seeds, or other database-related changes.
  - **Affected modules / files:** list only the important changes; if the list is large or repetitive, replace it with a link to the whole module or directory and mention only the most important files.
  - **Verification and risks:** a short note on what was verified and what remains as risk.
- Include commit-pinned permalinks as markdown links whose text carries no backticks (contract/jira.md, "Link rules").
- Use soft redaction for obvious secrets/tokens before publishing.
- Run `Test-UmsJiraDescription.ps1` (without `-RequireSections`) on the comment
  body before sending it; a finding is a STOP.
- Use the MCP tool `mcp_atlassian-mcp-server_addCommentToJiraIssue` to post the formatted message to the target Jira Ticket ID.
- Read the posted comment back and verify each link and each bold survived
  (contract/jira.md, "Read-back verification").

### 9. Completion
> "✅ Jira ticket updated."
> - **Ticket:** <Ticket ID>
> - **Content:** (brief preview of the posted message)

### 10. Finalization mode (finishing gate only)

Invoked EXPLICITLY by the finishing-a-development-branch overlay **after a
verified fast-forward push of the ticket branch into the base ref** — the
integration path that replaces the upstream local-merge option (contract,
Publication Contract, subsection "Integration"; it is the last phase of that
sequence) — with a linked ticket. Never self-selected, never in standalone
invocations (standalone runs NEVER change ticket status).

**Until that push into the base is verified reachable on `origin`, the ticket
does NOT move to „Test".** The gate below is what enforces it, and its rules —
STOP before publishing, the escape belongs to the human, re-verify after the push
— are unchanged by the move to a push-based integration. What the move does change
is which commit the gate asks about and against what: the tip of the ticket branch,
tested for reachability **from the base ref**, because on a ticket branch that
commit is already on `origin` regardless of whether the base ever received it.

0. **Publication gate (FIRST, before the comment is published):** verify the tip
   commit of the ticket branch that was pushed onto the base ref is reachable
   **from the base ref on `origin`**. Resolve the base mechanically first, never by
   hand — `<mb-shared>` is this layer's `skills/shared/` directory, the sibling of
   `mb-jira-update/`:

   ```powershell
   . <mb-shared>/scripts/Get-UmsEffectiveBase.ps1
   $base = Get-UmsEffectiveBase (git rev-parse --show-toplevel)
   ```

   ```bash
   git fetch origin
   git merge-base --is-ancestor <sha> <effective base>   # non-zero exit = not on the base
   ```

   `<effective base>` is `$base.Ref` — the work item's own CHOSEN base (contract,
   "Repository Configuration", the effective base) — running this gate against the
   default `baseRef` instead would,
   for work integrating into a maintenance branch, pass or fail for the wrong
   reason: it would be asking the question about a branch this work item was never
   targeting. The base must be named in the check, and `git fetch origin` must
   precede it.
   A bare `git branch -r --contains <sha>` is NOT sufficient here: the publication
   rule already pushed that commit to the ticket branch on `origin`, so
   `--contains` reports the ticket branch, the result is non-empty and the gate
   would pass while the base carries none of the code — exactly the state this
   gate exists to catch when the user never runs the base push or it was rejected
   as non-fast-forward and nobody retried. Filtering the `--contains` output for
   `<effective base>` is an equally valid spelling; a check that does not name the
   base is not. Without the fetch, the remote-tracking refs may be stale and a push
   made from another clone would be reported as missing. If the commit is not on
   the base, **STOP** — do not
   publish the comment and do not transition: tell the user in Czech that the work
   has not reached the base and the tester would have nothing to test, and hand over
   the exact command (`! git push origin HEAD:$($base.Branch)`,
   with `$($base.Branch)` expanded to its value — the
   refspec form, because integration pushes the ticket branch onto the base ref, and
   the destination comes from the resolve above, never from a derivation done by
   hand (contract/repository-configuration.md, "Repository Configuration"); this is the user's own command —
   the agent never runs it and never sets `MB_HUMAN_PUSH`, and `--no-verify` is
   not a substitute — it disables every hook). Re-verify after the user's push
   with the same two commands — the
   fetch included, since the push may well have happened in another clone — then
   continue. If the server
   refuses a direct push to the base branch, report it and offer the fallback
   (short branch + an exceptional PR).

Then, after the comment publishes successfully:

1. Transition the ticket directly to **"Test"** (the "Review" status is
   skipped by team convention). Use `getTransitionsForJiraIssue` +
   `transitionJiraIssue`; a missing "Test" transition is a WARNING to the
   user, not a rollback — the comment stays published.
2. Clear the `Flagged` field if present (leftover from a manually skipped
   architect-review resume).
3. Report (Czech): comment link, new status, flag state.

