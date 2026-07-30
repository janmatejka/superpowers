# UMS-3361: Design/Plan pojmenování + Architect Review — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

- **Jira:** UMS-3361 (https://datasyscz.atlassian.net/browse/UMS-3361)
- **Návrh:** [design_ums_3361_design_review_workflow.md](design_ums_3361_design_review_workflow.md)
- **Target MB:** — (fork superpowers, dokumenty v `ums/docs/`)

**Goal:** Zavést pojmenování `design_<slug>.md` + `plan_<slug>.md` (s trvalým grandfatherem pro `proposal_*`), nový skill `mb-architect-review` (request/respond/resume) a upřesněné finishing chování (develop refresh, přechod tiketu do „Test").

**Architecture:** Vše jsou úpravy obsahu skillů (Markdown), jednoho PowerShell skriptu a jednoho hooku v adresáři `ums/` forku superpowers. Normativním zdrojem je kontrakt (`UMS_MEMORY_BANK_CONTRACT.md`) — mění se první; skilly a overlaye na něj odkazují. Lokální kořenový `.claude/` je netrackovaná deployed kopie — aktualizuje se ručně v posledním tasku, necommituje se.

**Tech Stack:** Markdown (skill content, EN pro AI-facing text, CZ pro user-facing), PowerShell 7 (epic-graph.ps1 + custom test harness), Node/mjs (hook).

## Global Constraints

- Měnit POUZE soubory pod `ums/` (větev `ums-memory-bank`); jedinou výjimkou je netrackovaný lokální `.claude/` v Tasku 12 (bez commitu).
- Git worktrees zakázány; pracuje se branch-in-place na aktuální větvi `ums-memory-bank`.
- Jazyk: těla skillů a kontrakt anglicky (AI-facing); citované uživatelské výstupy, Jira texty a commit messages česky.
- Nové názvy souborů: `design_<slug>.md` (spec) a `plan_<slug>.md` (plán). Adresáře `proposals/{next,active,completed,abandoned}/` se NEMĚNÍ.
- Grandfather: legacy `proposal_<slug>-design.md` / `proposal_<slug>.md` zůstávají platné; nikdy se nekonvertují s jedinou výjimkou aktivace draftu z `next/`.
- Discovery vzor: soubory `{design_,plan_,proposal_}*.md`; párování = strip právě jednoho prefixu `^(design_|plan_|proposal_)` ze stemu, suffix `-design$` se stripuje POUZE po prefixu `proposal_`.
- `context.md`: zapisuje se `- **Work item:** <slug>`; čtenáři akceptují i legacy `- **Proposal:**`. Volitelný řádek `- **Review:** design-review requested YYYY-MM-DD`.
- Jira konvence: stavy „Design Review", „In Progress", „Test"; vlajka = pole Flagged (Impediment); pole AgentSessions = customfield_11248, formát řádku `YYYY-MM-DD <harness> <session-id> — design review request (<tiket>)`.
- Řádek v popisu tiketu: `**Návrh (design):** [<design-file>](<commit-pinned URL>)`; refresh nahrazuje i legacy `**Návrh (proposal):** …`.
- Push policy: žádný `git push` bez explicitního schválení uživatelem (platí pro každý krok každého tasku i pro popisované chování skillů).
- Verze kontraktu: bump `2.0` → `2.1`.
- Commit po každém tasku (české commit message, prefix `UMS-3361:`), bez push.

---

### Task 1: Kontrakt — terminologie, pojmenování, preliminary drafty, context.md (v2.1)

**Files:**
- Modify: `ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md`

**Interfaces:**
- Consumes: —
- Produces: normativní sekce „Active Work Item (Design + Plan Pair)", nové znění „Preliminary work items (`next/`)", schéma `context.md` s poli `Work item` a `Review`, pravidlo párování prefixů. Všechny další tasky tyto texty referencují — názvy sekcí musí být přesně: `## Active Work Item (Design + Plan Pair)`, `## Architect Review Gate` (přidá Task 2).

- [ ] **Step 1: Hlavička a verze**

V `UMS_MEMORY_BANK_CONTRACT.md` změň:

```markdown
- **Contract-Version:** 2.1
- Supersedes v2.0 (renames the document pair to `design_`/`plan_`, adds the
  Architect Review Gate). v1 (mb-plan/mb-act orchestration) remains superseded.
  See `VENDORED_FROM.md` for the vendored Superpowers version.
```

- [ ] **Step 2: Přepsat sekci „Active Proposal Pair" na „Active Work Item (Design + Plan Pair)"**

Nahraď celou sekci `## Active Proposal Pair` (nadpis i tělo, až po `## Superpowers Document Placement`) tímto textem:

````markdown
## Active Work Item (Design + Plan Pair)

One active work item per repository = one **design + plan pair** in
`<PLAN_MB>/proposals/active/`:

- **`design_<slug>.md`** — the spec, written by `brainstorming`
  (intent source of truth).
- **`plan_<slug>.md`** — the implementation plan, written by
  `writing-plans` (execution source of truth). On conflict between the two,
  the plan governs execution; report the discrepancy to the user.

Rules:

- The pair is created by the superpowers workflow and is never duplicated into
  `docs/` or any parallel location.
- Task progress lives in the plan file's checkboxes and in
  `.superpowers/sdd/progress.md` — **not** in `context.md`.
- **Archival asymmetry:** on **completion** (harvest → `completed/`) only the
  design half is retained; the plan half is **deleted** — after implementation
  its task steps are spent; code, git history and the harvested current-state
  MB docs carry the outcome. If there is no design half (grandfathered single
  plan), archive that plan to `completed/` instead of deleting it. On
  **abandon** (`mb-abort` / Discard → `abandoned/`) both halves move together,
  unchanged, nothing deleted. If a half is missing at archive time, warn and
  handle what exists.
- A design file without its plan sibling is a valid intermediate state
  (between brainstorming and writing-plans).
- An empty `proposals/active/` directory may be absent from the working tree
  (git does not track empty directories). Skills MUST tolerate the missing
  directory and recreate it on demand — absence of `active/` means "no active
  work", not a broken Memory Bank.

**Naming:** `design_<slug>.md` / `plan_<slug>.md`. The slug MUST start with
the ticket code whenever one is known: `<jira>_<short_snake_case_topic>`,
ticket code normalized to lowercase snake case
(`UMS-3302` → `ums_3302_toast_reconcile`); without a known ticket use
`<short_snake_case_topic>` alone. ASCII only, no diacritics, no dates in the
name. When the ticket becomes known later, rename the slug's files to include
it (within the same naming style).

**Grandfather clause (legacy `proposal_` naming):** files named
`proposal_<slug>-design.md` (design half) and `proposal_<slug>.md` (plan
half, or a v1 single plan) remain valid artifacts wherever they rest —
`active/`, `next/`, `completed/`, `abandoned/`. Never rename or convert them,
with ONE exception: activating a queued legacy draft from `next/` converts
the work item to the new style (see Preliminary work items below). One work
item uses exactly one naming style; a mixed pair (legacy design + new plan or
vice versa) must never be created. Never touch archived files in
`proposals/completed/`.

**Discovery & pairing rule (all skills):** match files
`{design_,plan_,proposal_}*.md`; strip exactly ONE prefix
`^(design_|plan_|proposal_)` from the file stem, and strip the `-design`
suffix ONLY after the `proposal_` prefix; group by `(owning MB root, slug)`.
One pair (or grandfathered single file) = one candidate. Thus `design_x.md`
→ slug `x`, while legacy `proposal_design_x.md` → slug `design_x` — no
mis-pairing.

**Preliminary work items (`next/`):** work may be planned ahead as design
drafts in `<MB>/proposals/next/` — any number may queue there. A preliminary
draft is a single **`design_<slug>.md`** with design-document structure
(`## Cíl`, `## Scope`, `## Technický návrh`, scaled to what is known).
Detailed implementation plans are NOT written ahead — the plan is produced by
writing-plans after activation. Rules:

- Creating or editing a preliminary draft does NOT touch `context.md`, does
  not require the IDLE state, and does not pin a Target MB.
- When work starts, ALL files of the slug move from `next/` to `active/`
  (see Target-MB Discovery & Pinning). A legacy `proposal_*` draft is renamed
  to `design_<slug>.md` during this move — the only permitted legacy
  conversion; its content serves as the design seed regardless of its
  original structure, and brainstorming refines it rather than starting from
  scratch.
- Queued items in `next/` never count against the two-actives guard.
- A queued item dropped without being started moves to `abandoned/`
  unrenamed.
````

- [ ] **Step 3: Tabulka Superpowers Document Placement**

V sekci `## Superpowers Document Placement` nahraď tabulku:

```markdown
| Superpowers artifact | Default upstream location | UMS location |
|---|---|---|
| Design/spec (brainstorming) | `docs/superpowers/specs/…-design.md` | `<PLAN_MB>/proposals/active/design_<slug>.md` |
| Implementation plan (writing-plans) | `docs/superpowers/plans/….md` | `<PLAN_MB>/proposals/active/plan_<slug>.md` |
```

a v popisu hlaviček dokumentů nahraď názvy souborů: `proposal_<slug>-design.md` → `design_<slug>.md`, `proposal_<slug>.md` → `plan_<slug>.md` (v hlavičce design dokumentu i řádek `- **Plán:** [plan_<slug>.md](plan_<slug>.md)`; v MB metadata bloku plánu `**Návrh:** [design_<slug>-design.md]` oprav na `**Návrh:** [design_<slug>.md](design_<slug>.md)`).

- [ ] **Step 4: Target-MB Discovery & Pinning**

V sekci `## Target-MB Discovery & Pinning`:
- Bod 1: `Scan **/memory-bank/proposals/active/proposal_*.md` → `Scan **/memory-bank/proposals/active/ for {design_,plan_,proposal_}*.md`.
- Bod 2: nahraď větu o strip `-design` odkazem: „apply the Discovery & pairing rule (Active Work Item section): strip exactly one prefix, `-design` only after `proposal_`, group by `(owning MB root, slug)`."
- Bod 6 (Preliminary-queue activation): za „move ALL files of its slug from `next/` to `active/`" doplň „, renaming a legacy `proposal_*` draft to `design_<slug>.md` (the only permitted legacy conversion),".
- Bod 9: `Persist … \`Target MB Pin\`, \`Jira\`, \`Proposal\` slug and \`Started\`` → `\`Target MB Pin\`, \`Jira\`, \`Work item\` slug and \`Started\``.

- [ ] **Step 5: Schéma context.md**

V sekci `## \`context.md\` Schema & Writers` nahraď blok Active state a text pod ním:

````markdown
Active state:

```markdown
# Context

## Active Work

- **Jira:** UMS-XXXX (https://jira.datasys.cz/browse/UMS-XXXX)
- **Target MB Pin:** <relative path>/memory-bank/
- **Work item:** <slug>
- **Started:** YYYY-MM-DD
- **Review:** design-review requested YYYY-MM-DD
```

The `Review:` line is OPTIONAL — present only between an architect-review
request and its resume (see Architect Review Gate). While present, the
superpowers workflow MUST NOT continue past brainstorming (no writing-plans);
the correct continuation is `mb-architect-review` (resume).

IDLE state: replace the `## Active Work` items with
`(No active work - IDLE phase)`; keep the `- **Jira:** …` line of the last
work item if it existed.

Readers MUST accept the legacy field name `- **Proposal:**` as an alias of
`- **Work item:**` (stale files from contract v2.0); writers write only
`Work item`.

Writers (no other writer is allowed):

- **The driving session** during Target-MB Discovery & Pinning — creates or
  updates `## Active Work`.
- **`mb-harvest`** (and `mb-abort`) — resets `## Active Work` to IDLE.
- **`mb-architect-review`** — adds (request) and removes (resume) the
  `Review:` line only.

The v1 fields `Status`, `Run Mode`, `Execution Mode`, `Loop Mode`,
`Affected MBs`, `Implementation Checklist`, and `Auto Loop State` are
abolished — do not write them; ignore them when found in a stale file.
````

- [ ] **Step 6: Harvest Contract §4**

V sekci `## Harvest Contract` bodu 4 nahraď názvy: „move only the design half `design_<slug>.md` (or legacy `proposal_<slug>-design.md`) from `active/` to `completed/` unchanged (durable spec record) and **delete** the plan half `plan_<slug>.md` (or legacy `proposal_<slug>.md`)…" — zbytek bodu (grandfathered single plan, abandon path) zůstává.

- [ ] **Step 7: Verifikace**

Run: `grep -n "Active Proposal Pair\|proposal pair" ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md`
Expected: žádný výskyt (sekce přejmenována, próza mluví o „design + plan pair" / „work item").
Run: `grep -c "proposal_" ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md`
Expected: výskyty pouze v grandfather/legacy kontextech (zkontroluj očima — každý zbývající výskyt musí být v textu o legacy souborech).

- [ ] **Step 8: Commit**

```bash
git add ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md
git commit -m "UMS-3361: kontrakt v2.1 — design_/plan_ pojmenování, Work item pole, preliminary design drafty"
```

---

### Task 2: Kontrakt — nová sekce „Architect Review Gate"

**Files:**
- Modify: `ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md`

**Interfaces:**
- Consumes: sekce a pole z Tasku 1 (`Work item`, `Review:` řádek).
- Produces: sekce `## Architect Review Gate` — referencovaná skillem `mb-architect-review` (Task 3), overlayi (Tasky 4, 5) a `mb-abort` (Task 7).

- [ ] **Step 1: Vložit novou sekci**

Vlož následující sekci mezi `## Harvest Contract` a `## Dispatch Model Policy`:

````markdown
## Architect Review Gate

An approved design may be reviewed by a **human architect** before planning
and implementation. The gate is mediated by the Jira ticket and implemented
by the `mb-architect-review` skill (modes: request / respond / resume). The
brainstorming overlay ALWAYS offers the gate after the user approves the spec
when a Jira ticket is linked (with a yes/no recommendation based on
non-triviality: new component or service, architecture/contract changes,
cross-project impact, DB migration, security impact). No ticket → no offer.

**State lives in the ticket branch.** All interaction over a ticket happens
on that ticket's branch; every handoff (request and respond) ends with the
state committed and — with explicit user approval — pushed to origin. The
design document, `context.md` (including the `Review:` line) and any notes
are thus available to both sides and to Bitbucket links. Recommended branch
naming: include the ticket code (e.g. `feature/ums-3302-toast-reconcile`).

**Push policy:** NEVER push silently. Offer every push explicitly (state the
branch and outgoing commits) and wait for user approval; refusal stops the
handoff. Steps are ordered so one handoff needs exactly one push.

**Branch sync** (first step of respond and resume): resolve the ticket branch
in this order — branch name from the request comment (authoritative) → remote
branches whose name contains the ticket code (`git ls-remote --heads origin`,
case-insensitive) → ask the user; multiple ambiguous candidates always ask.
Require a clean working tree (dirty = STOP, no auto-stash). Then
`git fetch origin`, checkout the ticket branch and fast-forward to origin;
a diverged local branch = STOP and report. Only after branch sync read
`context.md` and the design document — both live on the ticket branch.

**Jira conventions:**

- Status flow: request transitions the ticket to **"Design Review"**; the
  architect's respond leaves the status unchanged; resume transitions to
  **"In Progress"**. Missing "Design Review" transition = fail-closed STOP
  with an instruction to create the status (prerequisite).
- **Flag** (`Flagged` field, value Impediment): set by respond when returning
  the ticket, cleared by resume (and by mb-jira-update finalization if still
  present). Team convention: a flag means "work returned to you — attend to
  it" (same as a tester returning a bug).
- **AgentSessions** (customfield_11248, Paragraph): request APPENDS one line
  `YYYY-MM-DD <harness> <session-id> — design review request (<ticket>)`.
  Session id is best-effort per harness; if undetectable, write the line
  without an id and tell the user. If the field is unavailable, put the same
  line into the request comment instead.
- The request comment records the **original resolver** (accountId +
  displayName) and the **ticket branch name** — respond needs both.

**Fail-closed rules:**

- While `context.md` carries the `Review:` line, continuing the workflow
  (writing-plans and beyond) is blocked; the correct continuation is
  `mb-architect-review` resume.
- Discard/abort paths (`mb-abort`, finishing Discard) with a ticket sitting
  in "Design Review" MUST offer Jira cleanup: transition back, restore
  assignee, clear the flag.
- Respond without a request comment (architect assigned manually): ask the
  user for the return assignee and branch; never guess.
- Resume without the flag (architect answered manually in Jira): warn and
  continue only after user confirmation.
````

- [ ] **Step 2: Verifikace**

Run: `grep -n "Architect Review Gate" ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md`
Expected: nadpis sekce + odkazy; sekce leží mezi Harvest Contract a Dispatch Model Policy.

- [ ] **Step 3: Commit**

```bash
git add ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md
git commit -m "UMS-3361: kontrakt — sekce Architect Review Gate (tiketová větev, push policy, Jira konvence)"
```

---

### Task 3: Nový skill `mb-architect-review`

**Files:**
- Create: `ums/.claude/skills/mb-architect-review/SKILL.md`

**Interfaces:**
- Consumes: kontrakt „Architect Review Gate" (Task 2), `context.md` pole `Work item`/`Review` (Task 1), mechanika `mb-jira-update` §5–7 (beze změny, referencí).
- Produces: skill s režimy request/respond/resume — invokovaný z brainstorming overlaye (Task 4) a nabízený v `mb-state` (Task 8).

- [ ] **Step 1: Vytvořit SKILL.md s tímto úplným obsahem**

````markdown
---
name: mb-architect-review
description: Design review by a human architect via a Jira ticket — hand off an approved design (request), assess it as the architect (respond), or take the ticket back and continue (resume). Use for "předej návrh architektovi", "posuď design/návrh v UMS-XXXX", "převezmi UMS-XXXX po design review", "design review tiketu UMS-XXXX", or when the brainstorming Architect Review Gate offers a review. Accepts an optional ticket key and switches the repo to the ticket branch (branch sync).
license: MIT
metadata:
  author: UMS Project
  version: "1.0"
---

> Follow [UMS_MEMORY_BANK_CONTRACT](../shared/UMS_MEMORY_BANK_CONTRACT.md) —
> especially "Architect Review Gate" (normative for this skill), "Active Work
> Item (Design + Plan Pair)" and "`context.md` Schema & Writers". Bitbucket
> link mechanics (git preconditions, SHA stabilization, commit-pinned URLs,
> description-line refresh) are reused from
> [mb-jira-update](../mb-jira-update/SKILL.md) §5–7b — do not re-derive them.

# Command: mb-architect-review

**Action:** Mediate a design review by a human architect through a Jira
ticket. Three modes by role: request (resolver → architect), respond
(architect), resume (resolver takes the ticket back).
**Language:** all user-facing output, Jira comments and persistent artifacts
in Czech; this skill body and dispatch prompts are English.

## Mode Detection

The user never names the mode. Determine it in this order:

1. **Explicit verb in the prompt:** "posuď / review / assess" → respond;
   "převezmi / pokračuj / take back" → resume; "předej / hand off" → request.
2. **Jira state + caller identity:** load the ticket and the caller
   (`atlassianUserInfo`), compare with the assignee and with the original
   resolver recorded in the request comment:
   - ticket NOT in "Design Review" → request (requires an active work item
     with an approved design; otherwise report there is nothing to review),
   - ticket in "Design Review" AND caller is assignee AND caller ≠ original
     resolver → respond,
   - ticket in "Design Review" AND caller is the original resolver → resume.
3. **Undecidable** (identity unavailable, contradictory state) → ask ONE
   question offering the three modes. Never pick silently.

Ticket key: from the user prompt (preferred for respond/resume — enables
branch sync); without it, read `context.md` on the current branch (typical
for request in the same session).

## Push Policy (MANDATORY)

Never push silently. Before any push, present the branch name and the
outgoing commits and wait for explicit user approval. Refusal = STOP the
handoff with a Czech explanation (handoff needs the push). One handoff =
one push = one approval.

## Branch Sync (first step of respond and resume)

1. Resolve the ticket branch: request-comment branch name (authoritative) →
   `git ls-remote --heads origin` filtered case-insensitively by the ticket
   code → ask the user. Multiple ambiguous candidates: always ask.
2. Require a clean working tree; dirty = STOP and report (no auto-stash).
3. `git fetch origin` + checkout the ticket branch + fast-forward to origin.
   Diverged local branch = STOP and report.
4. Only now read `context.md` and the design document — they live on this
   branch.

## Mode: request (resolver → architect)

1. **Preconditions (fail-closed):** `context.md` has a Jira ticket and a
   `Work item` slug (legacy `Proposal:` accepted); the design half of the
   active work item exists in `<PLAN_MB>/proposals/active/` — either style
   (`design_<slug>.md` or legacy `proposal_<slug>-design.md`). Stabilize the
   SHA per mb-jira-update §5–6 (uncommitted design → user-confirmed local
   commit, else STOP).
2. If still on the default branch, create the ticket branch in place
   (branch-in-place; recommended name contains the ticket code, e.g.
   `feature/ums-3302-toast-reconcile`). Git worktrees are banned.
3. Write the `- **Review:** design-review requested YYYY-MM-DD` line into
   `## Active Work` of `context.md` and commit it (Czech commit message,
   `mb-git-commit` conventions).
4. **Push the ticket branch** (fail-closed, explicit approval per Push
   Policy). The single push covers the design and the `context.md` commit.
   The pinned design commit must be reachable on origin afterwards.
5. Publish a Czech comment to the ticket: a 10–15 line summary of the design
   (Cíl / Scope / klíčová rozhodnutí / rizika), the commit-pinned Bitbucket
   link to the design file (mb-jira-update §7), the **ticket branch name**,
   and the **original resolver** (accountId + displayName). Also refresh the
   `**Návrh (design):**` line in the ticket description (mb-jira-update §7b).
6. Architect selection: fetch assignable users of the project, offer the
   choice to the user (one question), set the chosen architect as assignee.
7. Transition the ticket to **"Design Review"**. Missing transition =
   fail-closed STOP: instruct the user to create the status (contract
   prerequisite).
8. Append to **AgentSessions** (customfield_11248):
   `YYYY-MM-DD <harness> <session-id> — design review request (<ticket>)`.
   Session id best-effort; undetectable → line without id + tell the user.
   Field unavailable → put the line into the comment from step 5 instead.
9. Announce (Czech): handed off to design review; work resumes via resume
   mode after the ticket returns, ideally in this session
   (`--resume <session-id>`). **The workflow stops here — do NOT invoke
   writing-plans.** `context.md` stays pinned; the two-actives guard
   deliberately blocks other work in this repo during the review.

## Mode: respond (architect)

1. Input: ticket key from the opening prompt. The ticket must be in
   "Design Review".
2. Read the ticket (description, request comment). Missing request comment
   (assigned manually) → fail-closed: ask the user for the return assignee
   and the ticket branch.
3. **Branch sync** (above) — then read the design document and the target
   project's MB context (`brief.md`, `architecture.md`, `tech.md`) from the
   ticket branch.
4. Guide the architect through a structured assessment: goal and scope
   adequacy, technical approach, impacts, risks, alternatives. Help phrase
   the notes.
5. Publish the notes as a Czech comment, set the assignee back to the
   original resolver, and **set the flag** (Flagged/Impediment — team
   convention: "returned, attend to it"). Status stays "Design Review".
   If commits were made on the ticket branch, push them — explicit approval
   per Push Policy.

## Mode: resume (resolver takes back)

1. Input: ticket key from the opening prompt (or from `context.md` when
   already on the ticket branch). Expect "Design Review" + flag; missing
   flag → warn ("architekt zřejmě odpověděl ručně") and continue only after
   user confirmation.
2. **Branch sync** (above) — the architect may have pushed. Then read the
   architect's comments and summarize them in Czech.
3. Transition the ticket to **"In Progress"**, clear the flag, remove the
   `Review:` line from `context.md` (commit with the next natural commit).
4. Continue per workflow state: fold the notes into the design
   (brainstorming-style dialog over the architect's points, update the design
   file) → after user approval invoke writing-plans.

## Model Selection

Composing the request summary is summarization work — when delegated, dispatch
on the cheapest capable tier (contract, Dispatch Model Policy). Respond and
resume are interactive; no dispatch by default.
````

- [ ] **Step 2: Verifikace**

Run: `grep -c "Architect Review Gate" ums/.claude/skills/mb-architect-review/SKILL.md`
Expected: ≥ 1 (odkaz na kontrakt).
Run: `grep -n "design_<slug>\|proposal_<slug>-design" ums/.claude/skills/mb-architect-review/SKILL.md`
Expected: oba styly zmíněny v preconditions requestu.

- [ ] **Step 3: Commit**

```bash
git add ums/.claude/skills/mb-architect-review/SKILL.md
git commit -m "UMS-3361: nový skill mb-architect-review (request/respond/resume, branch sync, push policy)"
```

---

### Task 4: Overlay brainstormingu — nové pojmenování + Architect Review Gate

**Files:**
- Modify: `ums/.claude/skills/shared/overlays/brainstorming.overlay.md`

**Interfaces:**
- Consumes: skill `mb-architect-review` (Task 3), kontrakt (Tasky 1–2).
- Produces: fragment aplikovaný do vendorovaného `brainstorming/SKILL.md` (deployment v Tasku 12).

- [ ] **Step 1: Nahradit celý obsah fragmentu**

```markdown
<!-- TARGET: brainstorming/SKILL.md -->
<!-- ANCHOR: EOF -->

<!-- UMS-OVERLAY BEGIN (ums-memory-bank v2) -->
## UMS Memory Bank Overlay

This repository injects a Memory Bank document layer. Read
`../shared/UMS_MEMORY_BANK_CONTRACT.md` before writing the design document.
Adjustments to the checklist above:

- **Item 1 (Explore project context)** additionally requires: as soon as the
  affected code area is identifiable, run Target-MB discovery per the
  contract's "Target-MB Discovery & Pinning" section (scan active work items,
  evidence tags, A/B/C disambiguation — the user always decides; activate a
  matching queued design draft from `proposals/next/` by moving its files to
  `active/` — a legacy `proposal_*` draft is renamed to `design_<slug>.md`
  during the move — and use the draft as design seed), ask for the Jira
  ticket (one question; "none" is a valid answer), persist `Target MB Pin`,
  `Jira`, `Work item` slug and `Started` into `memory-bank/context.md`, then
  read `<PLAN_MB>/brief.md`, `product.md`, `architecture.md`, `tech.md`
  (those that exist) as design context. Create a todo for this. If the
  affected area only becomes clear later in the dialog, this step MUST
  complete before item 6.
- **Item 6 (Write design doc)**: save to
  `<PLAN_MB>/proposals/active/design_<slug>.md` (Czech content, header per
  the contract's "Superpowers Document Placement" section) instead of the
  default `docs/superpowers/specs/` path. Before committing, if you are on
  the default branch, create a feature branch in place first — git worktrees
  are banned in this repository.
- **Architect Review Gate (between item 8 and item 9):** when a Jira ticket
  is linked, ALWAYS offer a design review by a human architect after the
  user approves the spec — with your own yes/no recommendation based on
  non-triviality (new component or service, architecture/contract changes,
  cross-project impact, DB migration, security impact). If accepted, invoke
  the `mb-architect-review` skill (request mode) and END the workflow here —
  work resumes later via its resume mode. If declined, or when no ticket is
  linked, proceed to item 9 as usual. **This amends the terminal-state rule
  above:** in this repository `mb-architect-review` may follow brainstorming;
  writing-plans remains the only *implementation* successor.
- While `memory-bank/context.md` contains a
  `- **Review:** design-review requested` line, the workflow is parked: do
  NOT invoke writing-plans; the correct continuation is `mb-architect-review`
  (resume mode).
- The design document and all user-facing communication are in Czech.
<!-- UMS-OVERLAY END -->
```

- [ ] **Step 2: Verifikace**

Run: `grep -n "design_<slug>\|Architect Review Gate\|Work item" ums/.claude/skills/shared/overlays/brainstorming.overlay.md`
Expected: všechny tři nalezeny; žádný výskyt `proposal_<slug>-design`.

- [ ] **Step 3: Commit**

```bash
git add ums/.claude/skills/shared/overlays/brainstorming.overlay.md
git commit -m "UMS-3361: brainstorming overlay — design_ pojmenování a Architect Review Gate"
```

---

### Task 5: Overlay finishing — develop refresh + finalizace do „Test" + úklid review

**Files:**
- Modify: `ums/.claude/skills/shared/overlays/finishing-a-development-branch.overlay.md`

**Interfaces:**
- Consumes: kontrakt Architect Review Gate (Task 2); finalizační režim `mb-jira-update` (Task 6 — název režimu: „finalization mode").
- Produces: fragment aplikovaný do vendorovaného `finishing-a-development-branch/SKILL.md` (deployment v Tasku 12).

- [ ] **Step 1: Nahradit celý obsah fragmentu**

```markdown
<!-- TARGET: finishing-a-development-branch/SKILL.md -->
<!-- ANCHOR-BEFORE: ## Step 5: Execute Choice -->

<!-- UMS-OVERLAY BEGIN (ums-memory-bank v2) -->
## Step 4.5: UMS Harvest Gate (MANDATORY in this repository)

After the user chooses and BEFORE executing the choice:

- **Option 1, 2, or 3** (Merge Locally / Push and Create PR / Keep As-Is) →
  invoke the `mb-harvest` skill. It harvests knowledge into the affected
  Memory Bank documents, archives the design document to
  `proposals/completed/` (deleting the implementation plan), resets
  `memory-bank/context.md` to IDLE and offers `mb-jira-update`. Commit the
  resulting Memory Bank changes on this branch (Czech commit message), then
  execute the chosen option.
- **Option 1 (Merge Locally) additionally:** BEFORE the merge ask (Czech):
  „Aktualizovat lokální `develop` z `origin/develop`? (fetch + fast-forward,
  žádný push)". On yes: `git fetch origin`, then fast-forward the local base
  branch (create a tracking branch from `origin/develop` when it does not
  exist locally); fast-forward impossible (divergence) = STOP and report.
  **The answer to this question REPLACES the `git pull` of upstream Step 5
  Option 1 — never run `git pull` on the base branch in this repository.**
  Merge with `--no-ff` per repo convention.
- **After Option 1 completes successfully** (merge done, verification green)
  and a Jira ticket is linked: invoke `mb-jira-update` in **finalization
  mode** — after publishing the Czech summary comment it transitions the
  ticket directly to "Test" (skipping "Review") and clears the Flagged field
  if present. Options 2 and 3 never change the ticket status.
- **The discard path** ("If your human partner asks to discard the work") →
  do NOT harvest. After the typed confirmation, move the active work item
  pair to `proposals/abandoned/` and reset `memory-bank/context.md` to IDLE
  before deleting the branch. If the linked ticket sits in "Design Review",
  offer the Jira cleanup per the contract's Architect Review Gate (transition
  back, restore assignee, clear the flag).
<!-- UMS-OVERLAY END -->
```

- [ ] **Step 2: Verifikace**

Run: `grep -n "finalization mode\|git pull\|Design Review" ums/.claude/skills/shared/overlays/finishing-a-development-branch.overlay.md`
Expected: všechny nalezeny; `ANCHOR-BEFORE` řádek beze změny (`## Step 5: Execute Choice`).

- [ ] **Step 3: Commit**

```bash
git add ums/.claude/skills/shared/overlays/finishing-a-development-branch.overlay.md
git commit -m "UMS-3361: finishing overlay — develop refresh, finalizace mb-jira-update do Test, úklid review na discard"
```

---

### Task 6: `mb-jira-update` — pojmenování + finalizační režim

**Files:**
- Modify: `ums/.claude/skills/mb-jira-update/SKILL.md`

**Interfaces:**
- Consumes: kontrakt (Tasky 1–2).
- Produces: „finalization mode" (jméno režimu užívá finishing overlay z Tasku 5); §7b formát řádku `**Návrh (design):**` (užívá `mb-architect-review` a `mb-epic-graph`).

- [ ] **Step 1: Pojmenování v celém skillu**

Proveď tyto náhrady (zachovej okolní text):
- Řádek 85/101 (blok Load Context): `referenced by the \`Proposal\` slug in \`## Active Work\`` → `referenced by the \`Work item\` slug (legacy \`Proposal\` accepted) in \`## Active Work\``.
- Řádek 117: `The \`Proposal\` slug` → `The \`Work item\` slug (legacy \`Proposal\`)`.
- Řádek 123 (ACTIVE_WORK): `(\`proposal_<slug>-design.md\` + \`proposal_<slug>.md\`, or a grandfathered legacy single file)` → `(\`design_<slug>.md\` + \`plan_<slug>.md\`, legacy \`proposal_<slug>-design.md\` + \`proposal_<slug>.md\`, or a grandfathered single plan file)`.
- §2 (Information Extraction): `read the completed design proposal <PLAN_MB>/proposals/completed/proposal_<slug>-design.md` → `read the completed design document <PLAN_MB>/proposals/completed/design_<slug>.md (or legacy proposal_<slug>-design.md)`.
- §4 bod 2: `the design proposal proposal_<slug>-design.md … the implementation plan proposal_<slug>.md` → `the design document design_<slug>.md (or legacy proposal_<slug>-design.md) … the implementation plan plan_<slug>.md (or legacy proposal_<slug>.md)`.
- §52 (PLAN_MB Derivation, discovery popis): glob `**/memory-bank/proposals/active/proposal_*.md` → `**/memory-bank/proposals/active/ files matching {design_,plan_,proposal_}*.md` a závorku o stripování nahraď odkazem na kontraktní „Discovery & pairing rule".

- [ ] **Step 2: §7b — nový tvar řádku v popisu tiketu**

V §7b nahraď specifikaci řádku:

```markdown
- Maintain a single line of the exact form, pointing at the **design**
  document (`design_<slug>.md`, or legacy `proposal_<slug>-design.md`) — the
  durable artifact retained in `completed/` — never the implementation plan,
  which is deleted at harvest:
  `**Návrh (design):** [<design-file>.md](<commit-pinned URL from §7>)`
- Idempotent update: if such a line already exists — including the legacy
  form `**Návrh (proposal):** …` — replace it (refresh SHA + path, re-point a
  stale plan/legacy filename to the design document); otherwise insert it
  near the top of the description. Change nothing else in the description.
  Use `editJiraIssue` (contentFormat markdown).
```

- [ ] **Step 3: Nová sekce „10. Finalization mode"**

Za sekci `### 9. Completion` doplň:

```markdown
### 10. Finalization mode (finishing gate only)

Invoked EXPLICITLY by the finishing-a-development-branch overlay after a
successful local merge (Option 1) with a linked ticket — never self-selected,
never in standalone invocations (standalone runs NEVER change ticket status).

After the comment publishes successfully:

1. Transition the ticket directly to **"Test"** (the "Review" status is
   skipped by team convention). Use `getTransitionsForJiraIssue` +
   `transitionJiraIssue`; a missing "Test" transition is a WARNING to the
   user, not a rollback — the comment stays published.
2. Clear the `Flagged` field if present (leftover from a manually skipped
   architect-review resume).
3. Report (Czech): comment link, new status, flag state.
```

- [ ] **Step 4: Verifikace**

Run: `grep -n "Návrh (design)\|Finalization mode\|Work item" ums/.claude/skills/mb-jira-update/SKILL.md`
Expected: všechny nalezeny.
Run: `grep -n "proposal_<slug>" ums/.claude/skills/mb-jira-update/SKILL.md`
Expected: pouze výskyty s „legacy" v okolním textu.

- [ ] **Step 5: Commit**

```bash
git add ums/.claude/skills/mb-jira-update/SKILL.md
git commit -m "UMS-3361: mb-jira-update — design_/plan_ pojmenování, řádek Návrh (design), finalizační režim do Test"
```

---

### Task 7: `mb-harvest` + `mb-abort` — pojmenování + úklid review při abortu

**Files:**
- Modify: `ums/.claude/skills/mb-harvest/SKILL.md`
- Modify: `ums/.claude/skills/mb-abort/SKILL.md`

**Interfaces:**
- Consumes: kontrakt (Tasky 1–2).
- Produces: —

- [ ] **Step 1: mb-harvest — náhrady**

- Frontmatter description: `archive the design proposal (delete the implementation plan)` → `archive the design document (delete the implementation plan)`.
- §1 Preconditions: `the pair \`proposal_<slug>-design.md\` + \`proposal_<slug>.md\`, or a grandfathered single \`proposal_<slug>.md\`` → `the pair \`design_<slug>.md\` + \`plan_<slug>.md\` (legacy \`proposal_<slug>-design.md\` + \`proposal_<slug>.md\`), or a grandfathered single plan file`; `\`Proposal\` slug` → `\`Work item\` slug (legacy \`Proposal\` accepted)`.
- §4: `Move \`proposal_<slug>-design.md\` … **delete** the implementation plan \`proposal_<slug>.md\`` → `Move the design half (\`design_<slug>.md\`, legacy \`proposal_<slug>-design.md\`) … **delete** the plan half (\`plan_<slug>.md\`, legacy \`proposal_<slug>.md\`)`.
- §6 Announce: `Archivováno (jen design): \`proposals/completed/proposal_<slug>-design.md\`; implementační plán \`proposal_<slug>.md\` smazán` → `Archivováno (jen design): \`proposals/completed/design_<slug>.md\`; implementační plán \`plan_<slug>.md\` smazán (u legacy práce původní proposal_ názvy)`.

- [ ] **Step 2: mb-abort — náhrady + úklid Jiry**

- §1: pojmenování stejně jako u mb-harvest §1.
- §2 Confirmation: `⚠️ Zahodit práci na: proposal_<slug>*.md` → `⚠️ Zahodit práci na: <soubory work itemu dle skutečných názvů>` (skill vypíše reálné nalezené soubory).
- §3: `Move \`proposal_<slug>-design.md\` and \`proposal_<slug>.md\` (whichever exist)` → `Move the design and plan halves (whichever exist, either naming style)`.
- Nový krok mezi §4 (Reset context.md) a §5 (Announce):

```markdown
### 4b. Jira cleanup (Design Review only)

If `context.md` carried a `Review:` line, or the linked ticket is in the
"Design Review" status: offer (Czech, user confirms) the cleanup per the
contract's Architect Review Gate — transition the ticket back to
"In Progress" (or its previous status), restore the assignee to the original
resolver, clear the `Flagged` field. Without cleanup the architect keeps a
live review assignment for abandoned work — say so in the warning.
```

- [ ] **Step 3: Verifikace**

Run: `grep -rn "proposal_<slug>" ums/.claude/skills/mb-harvest/SKILL.md ums/.claude/skills/mb-abort/SKILL.md`
Expected: pouze výskyty s „legacy" v okolí.
Run: `grep -n "Jira cleanup" ums/.claude/skills/mb-abort/SKILL.md`
Expected: sekce 4b existuje.

- [ ] **Step 4: Commit**

```bash
git add ums/.claude/skills/mb-harvest/SKILL.md ums/.claude/skills/mb-abort/SKILL.md
git commit -m "UMS-3361: mb-harvest a mb-abort — nové pojmenování, úklid Jiry při abortu review"
```

---

### Task 8: `mb-state` — oba styly, Work item, stav „čeká na review"

**Files:**
- Modify: `ums/.claude/skills/mb-state/SKILL.md`

**Interfaces:**
- Consumes: kontrakt (Tasky 1–2), skill `mb-architect-review` (Task 3 — jméno pro doporučení dalšího kroku).
- Produces: —

- [ ] **Step 1: Náhrady v §1 (Gather state)**

- `\`Proposal\` slug` → `\`Work item\` slug (legacy \`Proposal\` accepted)`.
- Pair completeness: nahraď čtyři odrážky:

```markdown
- Pair completeness in `<PLAN_MB>/proposals/active/` (per the contract's
  Discovery & pairing rule — both naming styles):
  - `design_<slug>.md` + `plan_<slug>.md` (or legacy pair) → complete pair,
  - design half only → „rozpracovaný návrh (chybí plán)" — valid state
    between brainstorming and writing-plans,
  - plan-style single file (legacy `proposal_<slug>.md`) → grandfathered v1
    work item — valid,
  - nothing / slug mismatch → inconsistent, recommend `mb-harvest` audit or
    `mb-abort`.
- **Review pending:** a `- **Review:** design-review requested YYYY-MM-DD`
  line in `## Active Work` means the design sits with the architect — the
  workflow is parked (no writing-plans) until `mb-architect-review` resume.
```

- Two-actives check a Preliminary queue: glob `proposal_*.md` → `{design_,plan_,proposal_}*.md` (u obou skenů), `(group pairs by slug)` → `(group by slug per the pairing rule)`.

- [ ] **Step 2: Report — nový řádek a další krok**

Do šablony reportu za řádek `Proposal:` (přejmenuj na `Work item:`) doplň:

```
Review: <žádné | ⏳ čeká na design review u architekta od YYYY-MM-DD>
```

Do „Další krok" doplň řádek:

```
- čeká na review → mb-architect-review (resume) po vrácení tiketu; writing-plans je do té doby blokován
```

- [ ] **Step 3: Verifikace**

Run: `grep -n "Work item\|Review pending\|mb-architect-review" ums/.claude/skills/mb-state/SKILL.md`
Expected: vše nalezeno; `grep -n "proposal_<slug>"` vrací jen legacy kontexty.

- [ ] **Step 4: Commit**

```bash
git add ums/.claude/skills/mb-state/SKILL.md
git commit -m "UMS-3361: mb-state — oba styly pojmenování, Work item, report čekajícího review"
```

---

### Task 9: Mechanická vlna — `mb-scan`, `mb-sync`, `mb-git-commit`, `mb-git-message`, `mb-init`, stuby

**Files:**
- Modify: `ums/.claude/skills/mb-scan/SKILL.md`
- Modify: `ums/.claude/skills/mb-sync/SKILL.md`
- Modify: `ums/.claude/skills/mb-git-commit/SKILL.md`
- Modify: `ums/.claude/skills/mb-git-message/SKILL.md`
- Modify: `ums/.claude/skills/mb-init/SKILL.md`
- Modify: `ums/.claude/skills/mb-act/SKILL.md`
- Modify: `ums/.claude/skills/mb-plan/SKILL.md`

**Interfaces:**
- Consumes: kontrakt (Task 1).
- Produces: —

- [ ] **Step 1: Sdílený boilerplate (mb-scan, mb-sync, mb-git-commit, mb-git-message)**

Tyto čtyři skilly nesou identický blok „Load Context & Detect Phase". V každém proveď:
- `referenced by the \`Proposal\` slug in \`## Active Work\`` → `referenced by the \`Work item\` slug (legacy \`Proposal\` accepted) in \`## Active Work\`` (2 výskyty na soubor),
- `The \`Proposal\` slug in root \`context.md\`` → `The \`Work item\` slug (legacy \`Proposal\`) in root \`context.md\``,
- `(\`proposal_<slug>-design.md\` + \`proposal_<slug>.md\`, or a grandfathered legacy single file)` → `(\`design_<slug>.md\` + \`plan_<slug>.md\`, legacy \`proposal_*\` naming, or a grandfathered single plan file)`.

- [ ] **Step 2: Specifika jednotlivých skillů**

- `mb-git-commit` (řádek ~226, proposal archival): → `work-item archival: on completion the design half (design_<slug>.md, legacy proposal_<slug>-design.md) moves proposals/active/→proposals/completed/ and the plan half (plan_<slug>.md, legacy proposal_<slug>.md) is deleted; on abandon both halves move proposals/active/→proposals/abandoned/.`
- `mb-scan` (řádek ~201, Active Proposals): → `Active work items: <count/list> (apply the contract's Discovery & pairing rule: strip one prefix ^(design_|plan_|proposal_), -design only after proposal_, group by slug — one pair or legacy single file = one work item)`.
- `mb-sync` (řádek ~227, tabulka): `| Proposal | No | Archives design, deletes plan | No |` → `| Work item (design+plan) | No | Archives design, deletes plan | No |`.
- `mb-init` (řádek 10): `for MB_ROOT resolution, the proposal pair model, and fail-closed rules` → `for MB_ROOT resolution, the work item (design + plan pair) model, and fail-closed rules`; (řádek 55) `PLAN_MB = active proposal Memory Bank` → `PLAN_MB = the Memory Bank of the active work item`.
- `mb-act`, `mb-plan` (stuby): nahraď zmínky `proposal_<slug>.md` / `proposal_<slug>-design.md` novými názvy s dovětkem `(legacy proposal_* naming grandfathered)`.

- [ ] **Step 3: Verifikace**

Run: `grep -rln "referenced by the \`Proposal\` slug" ums/.claude/skills/`
Expected: žádný soubor.
Run: `grep -rn "proposal_<slug>" ums/.claude/skills/ --include=SKILL.md | grep -v legacy | grep -v epic`
Expected: prázdné (mimo epic skilly, ty řeší Task 10–11 kontext).

- [ ] **Step 4: Commit**

```bash
git add ums/.claude/skills/mb-scan/SKILL.md ums/.claude/skills/mb-sync/SKILL.md ums/.claude/skills/mb-git-commit/SKILL.md ums/.claude/skills/mb-git-message/SKILL.md ums/.claude/skills/mb-init/SKILL.md ums/.claude/skills/mb-act/SKILL.md ums/.claude/skills/mb-plan/SKILL.md
git commit -m "UMS-3361: mechanická vlna — Work item pole a nové pojmenování v utility skillech"
```

---

### Task 10: `mb-epic-elaboration` + `mb-epic-graph` (SKILL texty) — design drafty

**Files:**
- Modify: `ums/.claude/skills/mb-epic-elaboration/SKILL.md`
- Modify: `ums/.claude/skills/mb-epic-elaboration/protocol.md`
- Modify: `ums/.claude/skills/mb-epic-graph/SKILL.md`

**Interfaces:**
- Consumes: kontrakt „Preliminary work items" (Task 1).
- Produces: —

- [ ] **Step 1: mb-epic-elaboration/SKILL.md**

- Fáze 5 tabulky (Write the slice): `write/refine PRELIMINARY proposals in \`<owner MB>/proposals/next/\`` → `write/refine PRELIMINARY design drafts (\`design_<slug>.md\`) in \`<owner MB>/proposals/next/\``.
- Red flag: `\`proposal_*.md\` created under \`proposals/active/\` during elaboration` → `a work-item file (\`design_\`/\`plan_\`/legacy \`proposal_*\`) created under \`proposals/active/\` during elaboration`.
- Quick reference řádek „Preliminary plan draft structure": → `| Preliminary design draft structure | design-document sections (## Cíl, ## Scope, ## Technický návrh — scaled to what is known), saved as \`proposals/next/design_<slug>.md\`; detailed plans are NOT written ahead |`.
- Iron rule 6: `elaboration writes PRELIMINARY proposals to \`proposals/next/\`` → `elaboration writes PRELIMINARY design drafts to \`proposals/next/\``.

- [ ] **Step 2: protocol.md + mb-epic-graph/SKILL.md**

- V `protocol.md` nahraď výskyt(y) `proposal_<slug>` novým názvem `design_<slug>` s dovětkem `(legacy proposal_* files remain valid)` — dle grep nálezu (1 výskyt).
- V `mb-epic-graph/SKILL.md` (3 výskyty `proposal_`): u popisu `-ProposalPath` doplň, že adresáře se prohledávají na `{design_,plan_,proposal_}*.md`; u popisu slug pravidla odkaž kontraktní Discovery & pairing rule; hlášky `TIKET BEZ ODKAZU NA PROPOSAL` / `ODKAZ NA NEEXISTUJÍCÍ PROPOSAL` ponech (kódy zůstávají), jen doplň zmínku, že akceptují oba tvary řádku `**Návrh (design/proposal):**`.

- [ ] **Step 3: Verifikace + Commit**

Run: `grep -n "design_<slug>" ums/.claude/skills/mb-epic-elaboration/SKILL.md ums/.claude/skills/mb-epic-elaboration/protocol.md ums/.claude/skills/mb-epic-graph/SKILL.md`
Expected: nalezeno ve všech třech.

```bash
git add ums/.claude/skills/mb-epic-elaboration/ ums/.claude/skills/mb-epic-graph/SKILL.md
git commit -m "UMS-3361: epic skilly — preliminary drafty jako design_, discovery obou stylů"
```

---

### Task 11: `epic-graph.ps1` — parsování obou stylů + fixture + testy

**Files:**
- Modify: `ums/.claude/skills/mb-epic-graph/scripts/epic-graph.ps1`
- Create: `ums/.claude/skills/mb-epic-graph/tests/fixtures/newstyle/design_na.md`
- Create: `ums/.claude/skills/mb-epic-graph/tests/fixtures/newstyle/plan_na.md`
- Create: `ums/.claude/skills/mb-epic-graph/tests/fixtures/newstyle/design_nb.md`
- Create: `ums/.claude/skills/mb-epic-graph/tests/fixtures/newstyle/proposal_design_kolize.md`
- Create: `ums/.claude/skills/mb-epic-graph/tests/fixtures/newstyle/design_kolize.md`
- Modify: `ums/.claude/skills/mb-epic-graph/tests/graph-generation.tests.ps1`

**Interfaces:**
- Consumes: kontraktní Discovery & pairing rule (Task 1).
- Produces: `ConvertTo-Slug` a `Get-ProposalFiles` chování pro tři prefixy; regex 6b s lookbehind na `proposals/<stav>/`.

- [ ] **Step 1: Napsat rozšíření testů (RED)**

Do `graph-generation.tests.ps1` doplň na konec:

```powershell
Write-Host 'Proposal mode: new-style design_/plan_ naming'
$ns = Join-Path $PSScriptRoot 'fixtures\newstyle'
$rn = Invoke-Graph @('-Source','Proposals','-ProposalPath',$ns,'-EpicKey','demo','-Mermaid')
Assert-Eq $rn.Code 0 'new style exit 0'
Assert-Match $rn.Out 'na --> nb' 'blocks edge na->nb from design headers'
Assert-Eq ([regex]::Matches($rn.Out, '(?m)^\s{4}na\[').Count) 1 'na node declared once (plan sibling merged)'
Assert-Match $rn.Out '(?m)^\s{4}design_kolize\[' 'legacy proposal_design_kolize keeps slug design_kolize'
Assert-Match $rn.Out '(?m)^\s{4}kolize\[' 'new design_kolize.md yields slug kolize (distinct node)'
```

- [ ] **Step 2: Vytvořit fixtures**

`design_na.md` (formát polí i link textu zrcadlí stávající fixtures, viz `fixtures/basic/proposal_alfa.md`):

```markdown
# Návrh: NA

- **Slug:** na
- **Stav:** návrh
- **Blokuje:** [nb](design_nb.md)

## Cíl
Návrh na.
```

`plan_na.md`:

```markdown
# NA Implementation Plan

- **Slug:** na

## Global Constraints
Plán na (sourozenec designu — nesmí vytvořit druhý uzel).
```

`design_nb.md`:

```markdown
# Návrh: NB

- **Slug:** nb
- **Stav:** návrh
- **Blokováno:** [na](design_na.md)

## Cíl
Návrh nb.
```

`proposal_design_kolize.md`:

```markdown
# Návrh: Legacy s matoucím jménem

## Cíl
Legacy soubor — slug musí být design_kolize, ne kolize.
```

`design_kolize.md`:

```markdown
# Návrh: Kolize

## Cíl
Nový soubor — slug kolize.
```

- [ ] **Step 3: Spustit testy — ověřit selhání**

Run: `pwsh ums/.claude/skills/mb-epic-graph/tests/graph-generation.tests.ps1`
Expected: FAIL nových assertů (nové soubory se nenačtou / slugy špatně), stávající asserty PASS.

- [ ] **Step 4: Implementace v epic-graph.ps1**

`ConvertTo-Slug` (řádky ~150–155) nahraď:

```powershell
function ConvertTo-Slug([string] $fileName) {
    $base = [IO.Path]::GetFileNameWithoutExtension($fileName)
    if ($base -match '^proposal_') {
        # legacy style: strip prefix, then the -design sibling suffix
        $base = $base -replace '^proposal_', '' -replace '-design$', ''
    } else {
        # new style: strip exactly one prefix; no suffix handling
        $base = $base -replace '^(design_|plan_)', ''
    }
    return $base
}
```

`Get-ProposalFiles` (řádky ~185–192) nahraď filtr:

```powershell
function Get-ProposalFiles([string[]] $paths) {
    $files = foreach ($p in $paths) {
        if (Test-Path -LiteralPath $p -PathType Container) {
            Get-ChildItem -LiteralPath $p -Recurse -File |
                Where-Object { $_.Name -match '^(proposal_|design_|plan_)[^\\/]*\.md$' }
        }
        elseif (Test-Path -LiteralPath $p) { Get-Item -LiteralPath $p }
        else { Write-Warning "Proposal path not found: $p" }
    }
    return @($files | Where-Object { $_ })
}
```

Regex 6b (řádek ~865) nahraď:

```powershell
# legacy proposal_* names match anywhere; new design_/plan_ names only when
# the reference path sits under a proposals/<state>/ directory (avoids false
# positives on ordinary docs/design_*.md links)
$propRefRx = [regex]'(?:proposal_[A-Za-z0-9_]+(?:-design)?|(?<=proposals/(?:next|active|completed|abandoned)/)(?:design_|plan_)[A-Za-z0-9_]+)\.md'
```

Dále v nápovědě parametru `-ProposalPath` (řádek ~41) změň `searched recursively for "proposal_*.md"` na `searched recursively for {design_,plan_,proposal_}*.md`.

A v hlášce kontroly 6 (řádek ~861, `TIKET BEZ ODKAZU NA PROPOSAL`) změň doporučený tvar řádku z `«**Návrh (proposal):**»` na `«**Návrh (design):**»` (kód nálezu se NEMĚNÍ — Jira-mode testy kontrolují byte-for-byte texty jen v Jira režimu, tato hláška je společná; po změně spusť testy a případný dotčený assert textu uprav ve stejném commitu).

- [ ] **Step 5: Spustit všechny testy — ověřit průchod**

Run: `pwsh ums/.claude/skills/mb-epic-graph/tests/graph-generation.tests.ps1 && pwsh ums/.claude/skills/mb-epic-graph/tests/oracle-structural.tests.ps1 && pwsh ums/.claude/skills/mb-epic-graph/tests/oracle-prose.tests.ps1 && pwsh ums/.claude/skills/mb-epic-graph/tests/e2e.tests.ps1`
Expected: PASS všech (regrese Jira módu „byte-for-byte" beze změny).

- [ ] **Step 6: Commit**

```bash
git add ums/.claude/skills/mb-epic-graph/scripts/epic-graph.ps1 ums/.claude/skills/mb-epic-graph/tests/
git commit -m "UMS-3361: epic-graph.ps1 — parsování design_/plan_ prefixů, scoping kontroly 6b, fixture newstyle"
```

---

### Task 12: Dokumentace + deny hook + lokální deployment overlayí

**Files:**
- Modify: `ums/CLAUDE.md.sample`
- Modify: `ums/README.md`
- Modify: `ums/.claude/skills/shared/SKILLS_MANIFEST.md`
- Modify: `ums/.claude/hooks/deny-superpowers-docs.mjs`
- Modify (netrackované, BEZ commitu): `.claude/skills/brainstorming/SKILL.md`, `.claude/skills/finishing-a-development-branch/SKILL.md`

**Interfaces:**
- Consumes: vše výše.
- Produces: —

- [ ] **Step 1: CLAUDE.md.sample**

- Bullet „Umístění dokumentů": názvy → `design_<slug>.md` / `plan_<slug>.md` (zbytek bulletu beze změny).
- Nový bullet za „Kontext před návrhem":

```markdown
- **Design review architektem:** po schválení návrhu s navázaným Jira tiketem VŽDY nabídni design review (skill `mb-architect-review`, režim request; doporučení dle netriviálnosti). Vyvolání architektem/řešitelem: `/mb-architect-review [UMS-XXXX]` — skill sám určí režim a přepne repo na tiketovou větev. Dokud je v `context.md` řádek `Review: design-review requested`, writing-plans nespouštěj.
```

- Bullet „Dokončení větve" doplň: `Před merge do lokálního develop se zeptej na refresh z origin/develop (fetch + FF, žádný push; nahrazuje upstream git pull). Po úspěšném merge (Option 1) s tiketem spusť mb-jira-update ve finalizačním režimu — tiket jde přímo do „Test".`

- [ ] **Step 2: README.md + SKILLS_MANIFEST.md**

- `SKILLS_MANIFEST.md`: do tabulky aktivních skillů doplň řádek
  `| mb-architect-review | [mb-architect-review/SKILL.md](../mb-architect-review/SKILL.md) | Design review živým architektem přes Jira tiket (request/respond/resume, branch sync dle tiketu, push jen se schválením) |`
  a v řádku kontraktu popis `proposal pár` → `work item (design+plan pár)`.
- `ums/README.md`: grep `proposal_` a přepiš výskyty popisující pojmenování na nový styl s poznámkou o grandfatheru; do popisu workflow doplň větu o Architect Review Gate mezi brainstorming a writing-plans.

- [ ] **Step 3: deny-superpowers-docs.mjs**

V `permissionDecisionReason` nahraď text:

```javascript
'UMS: spec/plan dokumenty patří do <PLAN_MB>/proposals/active/ ' +
'(design_<slug>.md / plan_<slug>.md; legacy proposal_* grandfathered), ne do docs/superpowers/ ani docs/plans/. ' +
```

- [ ] **Step 4: Lokální deployment overlayí (BEZ commitu)**

V netrackovaném `.claude/skills/brainstorming/SKILL.md` a `.claude/skills/finishing-a-development-branch/SKILL.md` nahraď obsah mezi `<!-- UMS-OVERLAY BEGIN` a `<!-- UMS-OVERLAY END -->` (včetně markerů) aktuálním blokem z fragmentů Tasků 4 a 5 (část od `<!-- UMS-OVERLAY BEGIN` dál — bez TARGET/ANCHOR hlaviček).

- [ ] **Step 5: Verifikace**

Run: `grep -rn "proposal_<slug>" ums/CLAUDE.md.sample ums/README.md ums/.claude/skills/shared/SKILLS_MANIFEST.md ums/.claude/hooks/deny-superpowers-docs.mjs | grep -v -i legacy`
Expected: prázdné.
Run: `grep -n "Architect Review Gate" .claude/skills/brainstorming/SKILL.md && grep -n "finalization mode" .claude/skills/finishing-a-development-branch/SKILL.md`
Expected: nalezeno (deployment proběhl).

- [ ] **Step 6: Commit (jen ums/)**

```bash
git add ums/CLAUDE.md.sample ums/README.md ums/.claude/skills/shared/SKILLS_MANIFEST.md ums/.claude/hooks/deny-superpowers-docs.mjs
git commit -m "UMS-3361: dokumentace a deny hook — nové pojmenování, mb-architect-review v manifestu"
```
