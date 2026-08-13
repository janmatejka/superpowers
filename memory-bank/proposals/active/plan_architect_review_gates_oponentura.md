# Schvalovací brána design review a agentická oponentura — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

- **Jira:** (žádný tiket)
- **Spec:** [design_architect_review_gates_oponentura.md](design_architect_review_gates_oponentura.md)
- **Target MB:** memory-bank/

**Goal:** Přidat do vrstvy UMS (A) explicitní schvalovací bránu před zápisem posudku design review do Jiry a (B) volitelnou nezávislou agentickou oponenturu návrhu se třemi body zásahu.

**Architecture:** Normativní popis oponentury jde do kontraktu jako nová sekce (bump v2.10) — tři konzumenti (brainstorming overlay, respond, nový režim `oppose`) na ni jen odkazují. Část A je čistě lokální restrukturalizace respond režimu `mb-architect-review`. Overlay fragment brainstormingu dostává nový bod nabídky; vendorované kopie se regenerují revendorem (pořadí kopie → revendor je závazné).

**Tech Stack:** Markdown (kontrakt, skilly, overlay fragmenty), PowerShell 7 (revendor, testy vrstvy), Git Bash (testovací smyčka).

## Global Constraints

- **Jazykový kontrakt:** těla skillů, kontrakt a overlay fragmenty anglicky; commit messages a výstupy pro uživatele česky. České uvozovky v PowerShellových stringách jen v jednoduše uvozených literálech.
- **Vendorované soubory se nikdy needitují ručně mimo `<!-- UMS-OVERLAY -->` bloky** — změna overlay obsahu patří do fragmentu `ums/.claude/skills/shared/overlays/*.overlay.md`.
- **Pořadí obnovy nasazení je závazné: kopie `ums/.claude/.` → `.claude/`, teprve pak revendor** — revendor čte fragmenty z NASAZENÉ kopie.
- **Publikace:** po každém commitu push vlastní tiketové větve (`architect-review-gates-oponentura`) s ohlášením commitů. Nikdy push sdílených větví.
- **Jméno kontraktové sekce je nosné:** `## Agentic Design Opposition (oponentura)` — skilly a fragment na ni odkazují doslovným jménem; změna jména = oprava všech odkazů ve stejném commitu.
- **Jméno režimu je `oppose`** — všude stejně (Mode Detection, sekce režimu, description).
- Po vložení/odstranění kroku v číslovaném seznamu grep celého souboru na `steps? [0-9]` (case-insensitive `\bstep`) i na číslovky slovem; na sousední kroky odkazovat jménem fáze, ne číslem.
- Po změně kardinality („three modes") grep na počítací frázi samotnou a oprava každého výskytu.
- Git worktrees zakázané (branch-in-place). Žádný `git stash`.

---

### Task 1: Kontrakt — sekce Agentic Design Opposition + bump v2.10

**Files:**
- Modify: `ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md` (hlavička verzí, řádky 3–10; nová sekce mezi `## Architect Review Gate` a `## Epic Backflow (design → epic)`)

**Interfaces:**
- Produces: sekce `## Agentic Design Opposition (oponentura)` — Tasks 2–4 na ni odkazují doslovným jménem `"Agentic Design Opposition (oponentura)"`.

- [x] **Step 1: Bump hlavičky verze**

Nahradit řádky 3–4 (současný stav):

```markdown
- **Contract-Version:** 2.9
- Supersedes v2.8 (splits the design/plan conflict rule by subject — what
```

za:

```markdown
- **Contract-Version:** 2.10
- Supersedes v2.9 (adds the Agentic Design Opposition section — an optional
  independent-subagent review of a design with evidence-bearing findings,
  driving-session triage and a batched user dialog; consumed by the
  brainstorming overlay and by the respond and oppose modes of
  `mb-architect-review`).
- v2.9 superseded v2.8 (splits the design/plan conflict rule by subject — what
```

Zbytek původní věty v2.8 („vs. how; renames …") zůstává beze změny — jen se z „Supersedes v2.8 (…)" stává „v2.9 superseded v2.8 (…)" dle konvence running historie.

- [x] **Step 2: Vložit novou sekci**

Vložit PŘED řádek `## Epic Backflow (design → epic)` (tj. na konec sekce Architect Review Gate) tento text:

```markdown
## Agentic Design Opposition (oponentura)

An optional adversarial review of a design document by an INDEPENDENT
subagent with a clean context — the opponent has seen none of the dialog
that produced the design, so it reads what the document says, not what its
author meant. Always an OFFER the user accepts or declines; never an
automatic run (the dispatch is not free — see Model and effort below).

**Dispatch (by the driving session).** The opponent receives: the design
document; the target MB's documents (`brief.md`, `architecture.md`,
`tech.md`, `playbook.md` — those that exist, legacy shape per Memory Bank
Document Set); and read access to the repository code, so integration
claims are checked against reality rather than against the design's own
prose. The dispatch prompt and the findings are AI-facing and therefore
English (Language Contract). The opponent looks for defects in
architecture, semantics, integration, security and similar concerns.

**Model and effort.** Opposition is design-assessment work — an
"architecture and design task" in the driving workflow's Model Selection —
so it is dispatched on the MOST CAPABLE available model, never the session
default, and with the highest reasoning effort the harness exposes on a
dispatch (a harness without such a parameter sets the model alone). State
both explicitly; an omitted parameter silently inherits the session's
(Dispatch Model Policy). A cheap tier is a false economy here: weak
opposition produces noise whose triage and user dialog cost more than the
dispatch saved.

**Findings format.** A structured list; every finding carries a category
(architecture / semantics / integration / security / other), a severity, a
claim, and EVIDENCE — a reference to the place in the design, the MB
document or the code the claim stands on. A finding without evidence is
not emitted. As with playbook candidates, the format enforces the ban on
invention — without evidence there is no finding.

**Triage (by the driving session).** Every finding lands in exactly one
bucket:

1. **Relevant and uncontested** → folded into the design directly.
2. **Contested, or scope-changing** → resolved with the user in a BATCHED
   dialog: several questions per iteration — the harness's structured
   questions where available, a numbered list in one message otherwise —
   so the user answers several points at once instead of a
   one-question-per-turn ping-pong.
3. **Irrelevant or wrong** → rejected, with the reason recorded for the
   closing summary.

**Closing summary (Czech).** After triage and dialog the user receives one
summary: what was folded in without asking (with the offer to revert any
of it), the decisions taken on contested points, and the rejected findings
with reasons. Nothing is folded in silently.

**Consumption points** — three, each an offer:

1. **Brainstorming, architectural path** — after the user approves the
   written spec, BEFORE the Architect Review Gate offer: agentic
   opposition can pre-filter mechanically findable defects before the
   design costs a human architect's time. Folding findings into an
   approved spec changes it, so the changed passages go back for the
   user's re-approval (the closing summary is its input); the design
   counts as FINALLY approved — for the Epic Backflow trigger and the
   Architect Review Gate offer — only after that re-approval.
2. **`mb-architect-review`, respond mode** — the architect's aide: the
   findings feed the structured assessment (its summary and conversation
   phases), never direct design edits — in respond the design belongs to
   the resolver. Triage is the architect's, made in the conversation, not
   the driving session's own.
3. **`mb-architect-review`, oppose mode** — standalone, on demand, over an
   existing design document; no Jira side effects (no transition, no
   flag). The one consumption point where the fold lands outside a
   brainstorming session: the design edits are committed and pushed on the
   ticket branch like any other commit of the work item.
```

- [x] **Step 3: Ověřit grepy**

Spustit a přečíst výsledky:

```bash
grep -n "Contract-Version" ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md
grep -n "Agentic Design Opposition" ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md
grep -n "Supersedes v2" ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md
```

Očekávané: verze `2.10`; nadpis sekce právě jednou + výskyty v hlavičce verzí; právě jedna věta `Supersedes v2.9`, starší přechody ve tvaru `vX superseded vY`.

- [x] **Step 4: Commit a push**

```bash
git add ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md
git commit -m "architect-review-gates-oponentura: kontrakt v2.10 — sekce Agentic Design Opposition
 - normativní popis oponentury: dispatch s čistým kontextem, nejsilnější model + nejvyšší effort, nálezy s evidencí, triáž se soustředěným dialogem, český závěrečný souhrn
 - tři body konzumace: brainstorming po schválení specu, respond jako pomocník architekta, samostatný režim oppose"
git push origin architect-review-gates-oponentura
```

---

### Task 2: mb-architect-review — schvalovací brána v respond (část A)

**Files:**
- Modify: `ums/.claude/skills/mb-architect-review/SKILL.md` (sekce `## Mode: respond (architect)`, kroky 4–5, dnes řádky 207–215)

**Interfaces:**
- Consumes: kontraktová sekce `"Agentic Design Opposition (oponentura)"` (Task 1) — odkaz jménem v kroku souhrnu.
- Produces: fáze respond režimu pojmenované **Summary** / **Assessment** / **Explicit gate** / **Publish** — Task 3 na ně odkazuje jménem.

- [x] **Step 1: Nahradit kroky 4–5 respond režimu**

Nahradit přesně tento text (současné kroky 4–5):

```markdown
4. Guide the architect through a structured assessment: goal and scope
   adequacy, technical approach, impacts, risks, alternatives. Help phrase
   the notes.
5. Publish the notes as a Czech comment, set the assignee back to the
   original resolver, and **set the flag** (Flagged/Impediment — team
   convention: "returned, attend to it"). The status stays unchanged
   ("Design Review", or "Review" in the fallback shape).
   If commits were made on the ticket branch, push them (announced push per
   Push Policy — the ticket branch is unprotected, so no approval is needed).
```

tímto textem (kroky 4–7):

```markdown
4. **Summary to the console first.** Print the architect a Czech summary
   of the design (goal, scope, technical approach, impacts, risks) — no
   Jira write, no assignee change, no flag: every side effect outside the
   clone waits for the Publish step below. Offer the agentic opposition as
   an aide (contract, "Agentic Design Opposition (oponentura)"): on
   acceptance dispatch the opponent per that section and feed its findings
   into the assessment below — they inform the notes, they never edit the
   design (in respond the design belongs to the resolver), and the triage
   is the architect's, made in the conversation.
5. **Assessment as a conversation.** Guide the architect through a
   structured assessment: goal and scope adequacy, technical approach,
   impacts, risks, alternatives — brainstorming-style, one question at a
   time; help phrase the notes. The output is the final wording of the
   review notes.
6. **Explicit gate.** Present the final wording and ask (Czech): „Zapsat
   posudek do Jiry a vrátit tiket řešiteli?" Without that explicit consent
   nothing reaches Jira; the architect may break off the conversation and
   return to it later — until the gate passes, the notes exist only in
   this session.
7. **Publish — only after the gate passes.** The notes as a Czech comment,
   the assignee back to the original resolver, and **set the flag**
   (Flagged/Impediment — team convention: "returned, attend to it"). The
   status stays unchanged ("Design Review", or "Review" in the fallback
   shape). If commits were made on the ticket branch, push them (announced
   push per Push Policy — the ticket branch is unprotected, so no approval
   is needed).
```

- [x] **Step 2: Sweep na odkazy na čísla kroků**

```bash
grep -inE "\bsteps? [0-9]" ums/.claude/skills/mb-architect-review/SKILL.md
grep -inE "\b(one|two|three|four|five|six|seven)\b.*steps?" ums/.claude/skills/mb-architect-review/SKILL.md
```

Přečíst každý nález a ověřit, že žádný neodkazuje na starý respond krok 4 nebo 5 (odkazy na request kroky — „request step 4", „step 3"/„step 6"/„step 7" v request sekci — jsou v pořádku, request se nemění). Nález odkazující na respond kroky opravit jménem fáze (Summary / Assessment / Explicit gate / Publish).

- [x] **Step 3: Commit a push**

```bash
git add ums/.claude/skills/mb-architect-review/SKILL.md
git commit -m "architect-review-gates-oponentura: schvalovací brána v respond režimu
 - kroky 4-5 rozděleny na souhrn do konzole, konverzaci nad posudkem, explicitní bránu a publikaci
 - do Jiry se zapisuje až po výslovném souhlasu architekta; nabídka oponentury jako pomocníka v kroku souhrnu"
git push origin architect-review-gates-oponentura
```

---

### Task 3: mb-architect-review — režim oppose, Mode Detection, description (část B)

**Files:**
- Modify: `ums/.claude/skills/mb-architect-review/SKILL.md` (frontmatter, úvod, `## Mode Detection`, nová sekce za `## Mode: resume (resolver takes back)` před `## Model Selection`, doplnění `## Model Selection`)

**Interfaces:**
- Consumes: kontraktová sekce `"Agentic Design Opposition (oponentura)"` (Task 1); fáze respond režimu (Task 2).
- Produces: režim `oppose` — overlay fragment (Task 4) ho jmenuje jako samostatnou cestu k oponentuře na vyžádání.

- [x] **Step 1: Aktualizovat frontmatter description a verzi**

Nahradit řádek `description:` (řádek 3) za:

```yaml
description: Design review by a human architect via a Jira ticket — hand off an approved design (request), assess it as the architect (respond), take the ticket back and continue (resume) — or run an independent agentic opposition of a design (oppose). Use for "předej návrh architektovi", "posuď design/návrh v UMS-XXXX", "převezmi UMS-XXXX po design review", "design review tiketu UMS-XXXX", "zoponuj návrh / oponentura návrhu", or when the brainstorming Architect Review Gate offers a review. Accepts an optional ticket key and switches the repo to the ticket branch (branch sync).
```

a `version: "1.3"` na `version: "1.4"`.

- [x] **Step 2: Aktualizovat úvod (Action) a Mode Detection**

V úvodu nahradit větu:

```markdown
**Action:** Mediate a design review by a human architect through a Jira
ticket. Three modes by role: request (resolver → architect), respond
(architect), resume (resolver takes the ticket back).
```

za:

```markdown
**Action:** Mediate a design review by a human architect through a Jira
ticket, or run an independent agentic opposition of a design. Four modes:
request (resolver → architect), respond (architect), resume (resolver
takes the ticket back), oppose (standalone agentic opposition — no human
handoff, no Jira side effects).
```

V `## Mode Detection` bodu 1 nahradit:

```markdown
1. **Explicit verb in the prompt:** "posuď / review / assess" → respond;
   "převezmi / pokračuj / take back" → resume; "předej / hand off" → request.
```

za:

```markdown
1. **Explicit verb in the prompt:** "posuď / review / assess" → respond;
   "převezmi / pokračuj / take back" → resume; "předej / hand off" →
   request; "zoponuj / oponentura / oppose" → oppose. Oppose enters ONLY
   through this rule — it is never inferred from Jira state.
```

V bodu 3 nahradit:

```markdown
3. **Undecidable** (identity unavailable, contradictory state) → ask ONE
   question offering the three modes. Never pick silently.
```

za:

```markdown
3. **Undecidable** (identity unavailable, contradictory state) → ask ONE
   question offering request / respond / resume (oppose is not offered
   here — it enters only by explicit ask). Never pick silently.
```

- [x] **Step 3: Vložit sekci režimu oppose**

Vložit za konec sekce `## Mode: resume (resolver takes back)` (před `## Model Selection`):

```markdown
## Mode: oppose (standalone opposition)

Entered only by an explicit ask (Mode Detection) — never inferred from
Jira state. No Jira side effects in this mode: no transition, no flag, no
comment — a linked ticket is context, not a state machine.

1. Input: an optional ticket key. With one, run Branch sync (above) to
   that ticket's branch; without one, stay on the current branch. Then
   read `context.md` and take the design half of the active work item from
   `<PLAN_MB>/proposals/active/` — or the design document the user named
   explicitly (a queued draft in `proposals/next/` is a valid target too).
   No design document → report there is nothing to oppose and stop.
2. **Shared-branch guard.** When the current branch matches any pattern of
   the effective `protectedBranches` (`Test-UmsProtectedBranch`, contract
   section "Repository Configuration"), the fold step below is
   unavailable: offer a read-only run (findings and closing summary only,
   no edits) or STOP and let the user pick a branch. A design is never
   edited on a shared branch.
3. Read the target MB's documents (`brief.md`, `architecture.md`,
   `tech.md`, `playbook.md` — those that exist; legacy shape per the
   contract's Memory Bank Document Set).
4. Dispatch the opponent and run the triage per the contract's "Agentic
   Design Opposition (oponentura)" section — most capable model, highest
   exposed reasoning effort, both explicit; findings with evidence only;
   contested and scope-changing findings go to the user in the batched
   dialog.
5. Fold the approved changes into the design document, commit (Czech
   commit message, `mb-git-commit` conventions) and push (announced, per
   Push Policy). The changed passages go back to the user for re-approval
   — the closing summary is its input.
6. Close with the contract's Czech closing summary (folded in without
   asking / decided on contested points / rejected with reasons).
```

- [x] **Step 4: Doplnit Model Selection**

Na konec sekce `## Model Selection` přidat odstavec:

```markdown
The opposition dispatch (oppose mode, or the respond aide) follows the
contract's "Agentic Design Opposition (oponentura)" section: the most
capable available model with the highest reasoning effort the harness
exposes, both stated explicitly — the one dispatch of this skill that must
never run on a cheap tier.
```

- [x] **Step 5: Sweep na kardinalitu a jména**

```bash
grep -in "three modes\|three review modes" ums/.claude/skills/mb-architect-review/SKILL.md
grep -n "oppose" ums/.claude/skills/mb-architect-review/SKILL.md
grep -n "Agentic Design Opposition" ums/.claude/skills/mb-architect-review/SKILL.md
```

Očekávané: žádný výskyt „three modes"; `oppose` ve frontmatteru, úvodu, Mode Detection a sekci režimu; odkaz na kontraktovou sekci v respond kroku Summary, v sekci oppose a v Model Selection.

- [x] **Step 6: Commit a push**

```bash
git add ums/.claude/skills/mb-architect-review/SKILL.md
git commit -m "architect-review-gates-oponentura: režim oppose a napojení oponentury
 - nový samostatný režim oppose: bez Jira side effectů, guard proti editaci návrhu na sdílené větvi, dispatch a triáž per kontrakt
 - Mode Detection: explicitní sloveso pro oppose, nikdy odvození z Jira stavu; oprava kardinality čtyř režimů
 - description frontmatteru rozšířena o oponenturu (trigger), verze 1.4, Model Selection odkazuje na kontraktovou sekci"
git push origin architect-review-gates-oponentura
```

---

### Task 4: Overlay fragment brainstormingu — bod nabídky oponentury

**Files:**
- Modify: `ums/.claude/skills/shared/overlays/brainstorming.overlay.md` (nový odrážkový bod před bod `- **Architect Review Gate`)

**Interfaces:**
- Consumes: kontraktová sekce `"Agentic Design Opposition (oponentura)"` (Task 1); režim `oppose` (Task 3).

- [x] **Step 1: Vložit bod nabídky**

Vložit PŘED řádek začínající `- **Architect Review Gate (architectural path only` tento bod:

```markdown
- **Agentic opposition offer (architectural path only — after the user
  approves the written spec, BEFORE the Architect Review Gate offer):**
  offer an independent agentic opposition of the design per the contract's
  "Agentic Design Opposition (oponentura)" section — an offer, never an
  automatic run. On acceptance: dispatch the opponent (most capable model,
  highest exposed reasoning effort, both explicit), triage the findings
  per that section (uncontested → fold into the design; contested or
  scope-changing → one BATCHED dialog with the user; wrong → reject with
  the reason), then present the Czech closing summary and have the user
  RE-APPROVE the changed passages. Only after that re-approval is the
  design finally approved — the Architect Review Gate offer and the Epic
  Backflow check below follow it. On the **bounded** path the offer does
  not run (the design was approved in chat; standalone opposition stays
  available on demand via `mb-architect-review` oppose mode) — a named
  deferral, like the Epic Backflow one below.
```

- [x] **Step 2: Ověřit strukturu fragmentu**

```bash
grep -c "UMS-OVERLAY BEGIN\|UMS-OVERLAY END" ums/.claude/skills/shared/overlays/brainstorming.overlay.md
grep -n "Agentic opposition offer\|Architect Review Gate (architectural" ums/.claude/skills/shared/overlays/brainstorming.overlay.md
```

Očekávané: počet markerů 2 (jeden BEGIN + jeden END); bod oponentury na nižším čísle řádku než bod Architect Review Gate.

- [x] **Step 3: Commit a push**

```bash
git add ums/.claude/skills/shared/overlays/brainstorming.overlay.md
git commit -m "architect-review-gates-oponentura: nabídka oponentury v brainstorming overlay
 - nový bod architektonické cesty: po schválení specu, před nabídkou Architect Review Gate, per kontraktová sekce
 - re-approval změněných pasáží posouvá finální schválení; na bounded cestě jmenovitý odklad"
git push origin architect-review-gates-oponentura
```

---

### Task 5: Obnova nasazení, revendor a testovací smyčka

**Files:**
- Modify (netrackovaná nasazení, negeneruje commit): `.claude/`, `.agents/skills/`

**Interfaces:**
- Consumes: všechny změny Tasků 1–4 v `ums/.claude/`.

- [x] **Step 1: Ověřit, že merge-copy stačí**

```bash
git diff --name-status origin/ums-memory-bank...HEAD -- ums/
```

Očekávané: jen řádky `A`/`M` (žádné `D`/`R`) — merge-copy nemůže nechat mrtvý soubor. Kdyby se objevilo `D`/`R`, smazat odpovídající cíle v `.claude/` explicitně.

- [x] **Step 2: Obnovit nasazené kopie (pořadí závazné: kopie PŘED revendorem)**

```bash
cp -r ums/.claude/. .claude/
cp -r ums/.claude/skills/. .agents/skills/
```

- [x] **Step 3: Revendor s overlay fragmenty**

```bash
pwsh -NoProfile -File .claude/scripts/revendor-superpowers.ps1 -OverlaysOnly
```

Očekávané: běh končí `Verification passed.` a exit 0. Miss kotvy/ASSERT = drift detektor, ne chyba k obejití — STOP a report.

- [x] **Step 4: Grep charakteristického textu ve vygenerovaných a nasazených souborech**

```bash
grep -n "Agentic opposition offer" .claude/skills/brainstorming/SKILL.md
grep -n "Mode: oppose" .claude/skills/mb-architect-review/SKILL.md
grep -n "Contract-Version:\*\* 2.10" .claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md
grep -n "Mode: oppose" .agents/skills/mb-architect-review/SKILL.md
```

Očekávané: každý grep aspoň jeden nález (revendor bez předchozí kopie tiše aplikuje staré fragmenty — přesně tohle ho odhalí).

- [x] **Step 5: Ověřit, že nasazení negeneruje commit**

```bash
git status --short --ignored=matching -- .claude .agents | head -5
git status --short
```

Očekávané: `.claude/` a `.agents/` s kódem `!!` (ignorováno), pracovní strom jinak čistý.

- [x] **Step 6: Testovací smyčka vrstvy**

```bash
for t in $(find ums -name "*.tests.ps1"); do echo "== $t"; pwsh -NoProfile -File "$t" || echo "FAILED: $t"; done
```

Očekávané: žádný řádek `FAILED:` (16 sad; sada `pre-push.tests.ps1` běží přes dvě minuty, což je normální). Změny jsou instrukční Markdown, testy kryjí regresi skriptů a hooků.

- [x] **Step 7: Commit není — ohlásit výsledek**

Nasazené kopie jsou netrackované; tento task nekomituje nic. Do reportu: výstup verify passu, výsledky grepů, výsledek testovací smyčky.

---

### Task 6: Propagace do monorepa (živá kopie vrstvy)

**Files:**
- Modify (mimo tento repozitář, bez git operací agenta): `d:\_datasys\ums\.claude\` (živá kopie vrstvy), vendorovaný `d:\_datasys\ums\.claude\skills\brainstorming\SKILL.md`

**Interfaces:**
- Consumes: všechny změny Tasků 1–4 v `ums/.claude/`.

- [x] **Step 1: Sync vrstvy do monorepa**

```bash
pwsh -NoProfile -File ums/sync-with-monorepo.ps1 -Agent claude -Scope Monorepo -Direction ToMonorepo
```

Očekávané: úspěšný běh; nenulový exit instalátoru hooků neignorovat — vypsat do reportu s kódem (1/2/3/4 dle playbooku).

- [x] **Step 2: Revendor v monorepu (overlay fragmenty)**

```bash
pwsh -NoProfile -File 'D:\_datasys\ums\.claude\scripts\revendor-superpowers.ps1' -OverlaysOnly
```

Očekávané: `Verification passed.`, exit 0.

- [x] **Step 3: Grep v monorepu**

```bash
grep -n "Agentic opposition offer" /d/_datasys/ums/.claude/skills/brainstorming/SKILL.md
grep -n "Mode: oppose" /d/_datasys/ums/.claude/skills/mb-architect-review/SKILL.md
grep -n "2.10" /d/_datasys/ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md
```

Očekávané: každý grep aspoň jeden nález.

- [x] **Step 4: Žádné git operace v monorepu — report uživateli**

Monorepo je cizí repozitář s vlastním workflow: agent v něm nic nekomituje ani nepushuje. Do závěrečného reportu vypsat `git -C 'D:\_datasys\ums' status --short -- .claude CLAUDE.md` a předat uživateli k commitnutí v monorepu.

---

## Self-Review (plán proti specu)

- Část A (brána v respond) → Task 2. Část B kontrakt → Task 1; režim oppose + pomocník architekta + description → Tasks 2–3; bod nabídky v brainstormingu → Task 4; revendor + obnova nasazení → Task 5; „živá kopie je v monorepu" → Task 6.
- Model + effort: kontraktová sekce (Task 1, „Model and effort"), zopakováno v oppose (Task 3) a v overlay bodu (Task 4).
- Dávkový dialog, evidence nálezů, závěrečný souhrn, re-approval: kontraktová sekce, konzumenti odkazují.
- Request a resume beze změny: žádný task na ně nesahá.
