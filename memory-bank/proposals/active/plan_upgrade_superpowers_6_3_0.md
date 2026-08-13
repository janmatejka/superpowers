# Upgrade superpowers na v6.3.0 — implementační plán

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

- **Jira:** (žádný tiket)
- **Návrh:** [design_upgrade_superpowers_6_3_0.md](design_upgrade_superpowers_6_3_0.md)
- **Target MB:** memory-bank/

**Goal:** Zvednout vendor pin vrstvy na v6.3.0 a uzavřít pět rozporů upstream × vrstva tak, aby po revendoru nezůstal v žádném nasazeném skillu rozporný instrukční text.

**Architecture:** Pravidla se mění nejdřív v kontraktu (v2.8 → v2.9), overlay fragmenty na ně jen odkazují jménem sekce; revendor skript dostane direktivu `ASSERT`, která dělá z `EOF` fragmentů detektory driftu. Lokální nasazení se obnoví revendorem s `-Tag v6.3.0` a celé se to doloží šestivrstvou verifikací (instrukční text nemá testy — dokazuje se čtením, grepy a bežící sadou).

**Tech Stack:** Markdown (kontrakt, fragmenty, MB dokumenty), PowerShell 7 (revendor skript), git.

## Global Constraints

- **Aditivní invariant větve:** trackované změny jen pod `ums/`, `memory-bank/` a v CLAUDE.md; `skills/` se mění výhradně mergem upstreamu (Task 1), nikdy ručně. Kořenový `.claude/` a `.agents/` jsou netrackovaná nasazení.
- **Jazyk:** kontrakt a fragmenty anglicky; MB dokumenty, commit messages a výstupy uživateli česky (s diakritikou, bez transliterace).
- **Pravidlo má jeden domov:** změna pravidla se píše do kontraktu; fragment odkazuje „per <jméno sekce>" a nese jen lokální doplňky. Žádná parafráze důvodů ve fragmentu.
- **Vendorované soubory se needitují ručně** mimo `<!-- UMS-OVERLAY BEGIN/END -->` bloky — vždy fragment + revendor.
- **Publikace:** po každém commitu push vlastní větve (`git push`; upstream už míří na `origin/upgrade-superpowers-6-3-0`), ohlásit odchozí commity. Sdílené větve nikdy.
- **Žádné worktrees** — větev na místě.
- **Baseline před Taskem 1:** spustit celou testovací smyčku vrstvy (16 sad; `pre-push` sada běží přes 2 minuty, to je normální) a potvrdit zelenou. Červená sada = STOP, pre-existing rozbití se řeší před prvním taskem.
- **Kázeň ohrazených bloků:** v editovaných dokumentech žádný řádek nezačíná TROJICÍ zpětných apostrofů, pokud to není skutečný ohraničovač (past `task-brief` matchuje jen trojité); počty fence řádků v každém tasku sudé. Řádek začínající jedním backtickem je legální — verbatim old-stringy v tomto plánu takové nesou a „opravovat" je by rozbilo přesnou shodu.

---

### Task 1: Merge upstreamu v6.3.0

**Files:**
- Modify: merge commit přes celý strom (`skills/`, `README.md`, `package.json`, `.gitignore`, …) — žádná ruční editace

**Interfaces:**
- Produces: strom `skills/` byte-identický s tagem `v6.3.0` (commit `b36e0829c6d0140e93cfef2ca599b1b07d4a7797`) — vstup pro revendor v Tasku 8

- [ ] **Step 1: Ověřit, že tip `vanila/main` je stále release v6.3.0**

```bash
git fetch vanila --tags
git rev-parse vanila/main   # očekávané: b36e0829c6d0140e93cfef2ca599b1b07d4a7797
git describe --tags vanila/main   # očekávané: v6.3.0
```

Pokud se tip pohnul za tag, merguj **tag** `v6.3.0`, ne `vanila/main`, a ohlas to v reportu.

- [ ] **Step 2: Merge**

```bash
git merge v6.3.0
```

Očekávané: bezkonfliktní merge (aditivní invariant). Jakýkoli konflikt = STOP a report — invariant je porušený a je to nález, ne věc k tichému vyřešení.

- [ ] **Step 3: Ověřit invariant merge**

```bash
git diff v6.3.0 HEAD -- skills/ | head -5        # očekávané: prázdné (skills/ == tag)
git diff HEAD^1 HEAD -- ums/ memory-bank/ CLAUDE.md | head -5   # očekávané: prázdné (merge nesáhl na obsah vrstvy)
```

- [ ] **Step 4: Push a ohlásit odchozí commity**

```bash
git log origin/upgrade-superpowers-6-3-0..HEAD --oneline
git push
```

---

### Task 2: Kontrakt v2.8 → v2.9

**Files:**
- Modify: `ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md`

**Interfaces:**
- Produces: jména nových sekcí/pravidel, na která odkazují fragmenty v Tascích 4–6: podsekce „Brainstorming Paths (spike / bounded / architectural)" (v sekci Superpowers Document Placement), odstavec „Rulings and these STOPs" (v sekci Fail-Closed Behavior), odstavec „The first publication of a freshly created ticket branch" (v sekci Publication Contract), pole `**Spec:**` v hlavičce plánu

- [ ] **Step 1: Bod 2.1 — autorita při konfliktu (sekce Active Work Item)**

Nahradit:

```markdown
- **`plan_<slug>.md`** — the implementation plan, written by
  `writing-plans` (execution source of truth). On conflict between the two,
  the plan governs execution; report the discrepancy to the user.
```

za:

```markdown
- **`plan_<slug>.md`** — the implementation plan, written by
  `writing-plans` (execution source of truth). A conflict between the halves
  is resolved **by its subject**: **what** should be built is the design's to
  decide — it is the binding authority the upstream ruling model measures
  against, and the artifact that survives in `completed/`; **how** and in
  what order is the plan's — it was written against the code, the design was
  not. Either way the discrepancy is recorded as a ruling and surfaced to the
  user, never silently absorbed.
```

- [ ] **Step 2: Bod 2.2 — pole `Spec:` (dvě místa + alias)**

Pole se přejmenovává na dvou místech: v sekci Link Conventions (řádek ~302, věta o jednosměrném odkazu plán → návrh) a v sekci Superpowers Document Placement (popis hlavičky plánu, řádek ~780) — na obou nahradit text pole ve tvaru „dvojhvězdičky Návrh: [design_<slug>.md](design_<slug>.md)" za týž tvar se jménem `Spec:`. Hned za popis hlavičky plánu doplnit:

```markdown
  Readers MUST accept the legacy field name `**Návrh:**` as an alias of
  `**Spec:**` (plans written under contract ≤ v2.8); writers write only
  `Spec`. The English name keeps the plan's AI-facing boilerplate English
  (Language Contract) and matches the field upstream's
  subagent-driven-development reads ("if the plan names a Spec, read that
  too") — a differently-named field would make every ruling provisional.
```

- [ ] **Step 3: Bod 2.3 — podsekce Brainstorming Paths**

Do sekce Superpowers Document Placement, za odstavec „Prohibited locations…" a před „Document headers:", vložit:

```markdown
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
```

- [ ] **Step 4: Bod 2.4 — rulingy × STOPy (konec sekce Fail-Closed Behavior)**

Na konec sekce Fail-Closed Behavior doplnit:

```markdown
**Rulings and these STOPs.** Upstream subagent-driven-development (v6.3.0)
rules on conflicts instead of stalling, and stops only for four named
classes. The fail-closed STOPs of this layer are not a fifth class — they
FALL WITHIN those four: a push to a shared branch and the integration push
are "a side effect outside this clone that norms say you ask about first";
an active-work collision, an unprotected base and an unreachable pinned
commit are irreversible in the same sense — duplicated work, or a reference
nobody can resolve, cannot be taken back; a plan too broken to follow is
upstream's fourth class verbatim. One thing is deliberately NOT such a side
effect: **merging the effective base into the agent's OWN ticket branch.**
It is mandatory at phase boundaries (Base Sync & Drift Detection) and is
never put to the user — reading upstream's word "merge" as covering it
would turn the mandatory base sync before the first dispatch into a
question.
```

- [ ] **Step 5: Bod 2.5 — ruling × kandidát (Playbook Contract) a jazyk (Language Contract)**

Do Playbook Contract, za odstavec „The ban on invention is enforced by the FORMAT…", doplnit:

```markdown
**A ruling is a decision; a candidate is a procedure.** A `Ruling:` ledger
line (upstream subagent-driven-development) becomes a playbook candidate
only when it carries `Happened` evidence that reaches beyond this work
item; otherwise it stays in the ledger and in the final "Rulings I made"
list. The format decides, as always — without `Happened` there is no entry.
```

Do Language Contract doplnit odrážku (za odrážku o `playbook-candidates/<slug>.md`):

```markdown
- `Ruling:` lines in the `.superpowers/sdd/` ledger are AI-facing and
  therefore English; the final "Rulings I made" list is user-facing and
  therefore Czech — the same translate-on-presentation split as playbook
  candidates.
```

- [ ] **Step 6: Bod 2.6 — past prvního pushe (Publication Contract)**

Za tabulku dvouúrovňové push policy doplnit:

```markdown
**The first publication of a freshly created ticket branch is
`git push -u origin <branch>` — never a bare `git push`.**
`git switch -c <branch> <chosen base>` sets the new branch's upstream to the
BASE, so a bare push would target the (typically protected) base branch;
`-u` rewrites the upstream, and the trap ends with the first publication.
When inspecting a workspace, a ticket branch whose upstream is a protected
branch is a finding, not a normal state.
```

- [ ] **Step 7: Bod 2.7 — hlavička verzí**

Nahradit první dva položky hlavičky (`- **Contract-Version:** 2.8` a celý odsek `- Supersedes v2.7 (adds the effective base …)`) za:

```markdown
- **Contract-Version:** 2.9
- Supersedes v2.8 (splits the design/plan conflict rule by subject — what
  vs. how; renames the plan-header field `**Návrh:**` to `**Spec:**` with a
  read alias; adds Brainstorming Paths — the document layer's mapping of the
  upstream spike/bounded/architectural router; maps this layer's fail-closed
  STOPs into the upstream ruling model's stop classes; adds the ruling ×
  playbook-candidate boundary and the ledger/report language split; adds the
  first-publication rule `git push -u`).
- v2.8 superseded v2.7 (adds the effective base of a work item — the
  optional `Báze:` line in `context.md` with a fallback to `baseRef` — the
  invariant that an integration branch is always a protected branch, and
  the ordered remedy when it is not).
```

(Zbytek historie beze změny.)

- [ ] **Step 8: Sweepy po změnách kontraktu**

```bash
grep -rn 'plan governs' ums/.claude/ && echo NALEZ || echo OK-prazdne
grep -rn '\*\*Návrh:\*\*' ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md   # očekávané: jen věta o aliasu
grep -rniE 'the single exception|only exception|jediná výjimka|exactly one|přesně jedn' ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md
```

U třetího grepu přečíst každý zásah a ověřit, že jeho počítací tvrzení zůstává pravdivé i po bodech 2.5/2.6 (nové instance pravidel). Nepravdivé věty opravit hned.

- [ ] **Step 9: Commit a push**

```bash
git add ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md
git commit -m "upgrade-superpowers-6-3-0: kontrakt v2.9
 - autorita konfliktu návrh × plán rozdělená podle předmětu sporu
 - pole hlavičky plánu Návrh: → Spec: (alias pro čtení zachován)
 - podsekce Brainstorming Paths (spike/bounded/architectural)
 - mapování fail-closed STOPů do tříd ruling modelu; base merge vlastní větve není side effect
 - hranice ruling × kandidát playbooku + jazykový split ledger/report
 - pravidlo prvního pushe git push -u"
git push
```

---

### Task 3: Direktiva ASSERT v revendor skriptu

**Files:**
- Modify: `ums/.claude/scripts/revendor-superpowers.ps1`
- Modify: `ums/.claude/skills/shared/overlays/README.md`

**Interfaces:**
- Produces: fragmenty smí nést 0..N řádků `<!-- ASSERT: <exact line text> -->` mezi ANCHOR řádkem a tělem; miss = hard error. Tasky 4–6 direktivu používají.

- [ ] **Step 1: Parsování ASSERT řádků v `Invoke-Overlays`**

V `Invoke-Overlays` nahradit:

```powershell
        $anchorLine = $lines[1]
        $body = ($lines[2..($lines.Count - 1)] -join "`n").TrimStart("`r", "`n")
```

za:

```powershell
        $anchorLine = $lines[1]
        $bodyStart = 2
        $asserts = @()
        while ($bodyStart -lt $lines.Count -and $lines[$bodyStart] -match '^<!-- ASSERT: (.+?) -->$') {
            $asserts += $Matches[1]
            $bodyStart++
        }
        $body = ($lines[$bodyStart..($lines.Count - 1)] -join "`n").TrimStart("`r", "`n")
```

- [ ] **Step 2: Vyhodnocení assertů nad cílem**

Za řádek `$content = (Get-Content -Path $target -Raw) -replace "`r`n", "`n"` (a před kontrolu `UMS-OVERLAY BEGIN`) vložit:

```powershell
        $targetLines = $content -split "`n"
        foreach ($a in $asserts) {
            $hits = @($targetLines | Where-Object { $_.TrimEnd() -eq $a }).Count
            if ($hits -ne 1) { Fail "$($frag.Name): ASSERT '$a' matched $hits lines in target (need exactly 1). Upstream drift - update the fragment." }
        }
```

- [ ] **Step 3: Negativní i pozitivní ověření na fixture**

Ve scratchpadu postavit minimální fixture (nikdy v repu):

```powershell
$fx = Join-Path $env:TEMP "assert-fixture"
Remove-Item -Recurse -Force $fx -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force "$fx/.claude/skills/testskill" | Out-Null
New-Item -ItemType Directory -Force "$fx/.claude/skills/shared/overlays" | Out-Null
Set-Content "$fx/.claude/skills/testskill/SKILL.md" "# Test`nLoad-bearing line here.`n"
Set-Content "$fx/.claude/skills/shared/overlays/testskill.overlay.md" @'
<!-- TARGET: testskill/SKILL.md -->
<!-- ANCHOR: EOF -->
<!-- ASSERT: NO SUCH LINE ANYWHERE -->

<!-- UMS-OVERLAY BEGIN (test) -->
test
<!-- UMS-OVERLAY END -->
'@
pwsh ums/.claude/scripts/revendor-superpowers.ps1 -OverlaysOnly -UmsRoot $fx
```

Očekávané: exit 1 a hláška `ASSERT 'NO SUCH LINE ANYWHERE' matched 0 lines`. Pak ve fragmentu nahradit assert text za `Load-bearing line here.` a spustit znovu — očekávané: `applied testskill.overlay.md` ve výstupu a **žádná** ASSERT hláška (následný verify pass na fixture smí spadnout na nesouvisejících kontrolách — rozlišuje se podle hlášky, ne exit kódu). Fixture smazat.

- [ ] **Step 4: Dokumentace formátu v `overlays/README.md`**

Do sekce „Fragment format" za popis ANCHOR řádku doplnit:

```markdown
Between the anchor line and the body, a fragment may carry any number of
assertion directives:

    <!-- ASSERT: <exact line text> -->

Each must match exactly one line of the target file (same `TrimEnd()`
comparison as `ANCHOR-BEFORE`). A miss is a hard error — this is how an
`ANCHOR: EOF` fragment still detects upstream drift: assert the upstream
sentences the overlay's semantics stand on, and the next upstream change to
them fails the re-vendor loudly instead of applying cleanly.
```

- [ ] **Step 5: Commit a push**

```bash
git add ums/.claude/scripts/revendor-superpowers.ps1 ums/.claude/skills/shared/overlays/README.md
git commit -m "upgrade-superpowers-6-3-0: direktiva ASSERT v revendor skriptu
 - fragment smí nést ASSERT řádky na nosné věty cíle; miss = hard error jako u ANCHOR-BEFORE
 - EOF fragmenty tím přestávají být slepé k driftu upstreamu
 - ověřeno negativně i pozitivně na scratch fixture"
git push
```

---

### Task 4: Fragment brainstorming

**Files:**
- Modify: `ums/.claude/skills/shared/overlays/brainstorming.overlay.md`

**Interfaces:**
- Consumes: jména sekcí kontraktu z Tasku 2 („Brainstorming Paths", pravidlo prvního pushe v Publication Contract); direktivu ASSERT z Tasku 3

- [ ] **Step 1: ASSERT direktivy do hlavičky fragmentu**

Za řádek `<!-- ANCHOR: EOF -->` vložit:

```markdown
<!-- ASSERT: Before your first question, classify the request and say the -->
<!-- ASSERT: **Terminal states are path-bound.** Architectural: the ONLY skill you -->
```

(Obě věty ověřeny jako přesné unikátní řádky `brainstorming/SKILL.md` v6.3.0.)

- [ ] **Step 2: Nový úvod (router + pravidlo jmen fází)**

Nahradit:

```markdown
This repository injects a Memory Bank document layer. Read
`../shared/UMS_MEMORY_BANK_CONTRACT.md` before writing the design document.
Adjustments to the checklist above:
```

za:

```markdown
This repository injects a Memory Bank document layer. Read
`../shared/UMS_MEMORY_BANK_CONTRACT.md` before writing the design document.

**Three paths (per the contract's "Brainstorming Paths" subsection).**
**architectural** and **bounded** both run the entry gate below in full and
both produce `design_<slug>.md`; they diverge only after approval — bounded
writes no plan and does not run subagent-driven-development. **spike** runs
the gate's eligibility, leftover-inventory and decision phases, creates a
branch only once it is to touch the tree, NEVER writes the pin, and writes
nothing under `proposals/`; when its answer turns into work to keep, the
request is reclassified and the gate completes. "This wants an architect's
review" is itself an architectural signal — upgrade the path (the ratchet
is one-way); the Architect Review Gate below is never offered on bounded.

Where an adjustment below names an upstream checklist item, it names it
**by phase name** — all three paths number their own items 1–5, so an
ordinal alone no longer identifies a step.

Adjustments to the checklist above:
```

- [ ] **Step 3: Hlavička sedmikrokového bloku (bývalý „Item 1")**

Nahradit:

```markdown
- **Item 1 (Explore project context)** additionally requires the seven steps below,
  in this order. Create a todo for them. Start as soon as the affected code area is
  identifiable; if it only becomes clear later in the dialog, run them then — but
  they MUST all complete before item 6. Each step does only what it can do at its
```

za:

```markdown
- **The "Explore project context" phase (architectural and bounded paths)**
  additionally requires the seven steps below, in this order. Create a todo
  for them. Start as soon as the affected code area is identifiable; if it
  only becomes clear later in the dialog, run them then — but they MUST all
  complete before the design document is written. On a spike, run the
  **Entry gate** step always, and the **Choose the base** / **Create the
  ticket branch** steps only once the spike is to touch the tree; the
  **Target-MB discovery**, **Jira ticket**, **Activation** and **Write the
  pin** steps are skipped — a spike pins nothing (contract, "Brainstorming
  Paths"). Each step does only what it can do at its
```

- [ ] **Step 4: Bod zápisu návrhu (bývalý „Item 6")**

Nahradit úvod bodu:

```markdown
- **Item 6 (Write design doc)**: save to
```

za:

```markdown
- **The "Write design doc" phase (architectural path; on bounded, writing
  the chat-approved design)**: save to
```

Dále v témže bodu nahradit `**By the time you reach this item the
  ticket branch already exists** — item 1's **Create the ticket branch** step
  created it` za `**By the time you reach this phase the
  ticket branch already exists** — the **Create the ticket branch** step
  above created it`, a `invoked by item 1's **Create the ticket
  branch** step and stated here in full` za `invoked by the **Create the
  ticket branch** step above and stated here in full`.

Na konec bodu (za odstavec „After committing the design, push the branch…") doplnit:

```markdown
  On the **bounded** path the design was approved IN CHAT; after that
  approval write the same content to
  `<PLAN_MB>/proposals/active/design_<slug>.md` (same header, body scaled
  to the change), commit and push — and do NOT wait for a second approval
  round: the bounded path has no written-spec review phase.
```

- [ ] **Step 5: Publikace návrhu — první push s `-u`**

Nahradit:

```markdown
  After committing the design, push the branch — the agent pushes its OWN ticket
  branch after every commit, always announcing the branch and the outgoing commits
  (Publication Contract).
```

za:

```markdown
  After committing the design, push the branch — the agent pushes its OWN ticket
  branch after every commit, always announcing the branch and the outgoing commits
  (Publication Contract). If this is the branch's FIRST publication, push with
  `git push -u origin <branch>`, never bare — per the contract's first-publication
  rule (Publication Contract): `switch -c` left the upstream pointing at the base.
```

- [ ] **Step 6: Architect Review Gate — kotva a bounded věta**

Nahradit `- **Architect Review Gate (between item 8 and item 9):** when a Jira ticket` za `- **Architect Review Gate (architectural path only — after the user approves the
  written spec, before the transition to implementation):** when a Jira ticket`.

Na konec téhož bodu (za větu o amendmentu, viz Step 7) nedávat nic — bounded větu nese úvod ze Step 2.

- [ ] **Step 7: Amendment terminálních stavů**

Nahradit:

```markdown
  **This amends the terminal-state rule
  above:** in this repository `mb-architect-review` may follow brainstorming;
  writing-plans remains the only *implementation* successor.
```

za:

```markdown
  **This amends the path-bound terminal states
  above:** architectural — in this repository `mb-architect-review` may follow
  brainstorming; writing-plans remains the only *implementation* successor.
  Bounded — implementation proceeds directly through the normal development
  workflow, but the work item still ends in finishing-a-development-branch:
  it has a pin and a design, so the Harvest Gate and the integration path
  apply to it exactly as to architectural work. Spike — a reported
  recommendation, no MB artifact and no finishing.
```

- [ ] **Step 8: Epic Backflow — pojmenovaný odklad pro bounded a oprava „item 8/9"**

V bodu Epic Backflow nahradit `run it here only when no review takes place` až po konec věty závorky beze změny; na konec bodu doplnit:

```markdown
  On the **bounded** path this check does NOT run for now — bounded is by
  definition a bounded change of an existing flow, so a scope or dependency
  shift of its ticket is unlikely; `mb-epic-graph -Check` stays available on
  demand. This is a named deferral, not an omission.
```

Dále v celém fragmentu ověřit a opravit zbylé ordinály: `proceed to item 9 as usual` → `proceed to the transition to implementation as usual`.

- [ ] **Step 9: Sweep ordinálů ve fragmentu**

```bash
grep -niE 'item [0-9]|items [0-9]|\bstep [0-9]' ums/.claude/skills/shared/overlays/brainstorming.overlay.md
```

Očekávané: žádný zásah odkazující na upstream checklist (interní odkazy na vlastních sedm kroků jsou legální jen jako jména kroků, ne čísla — zásahy přečíst a rozhodnout).

- [ ] **Step 10: Commit a push**

```bash
git add ums/.claude/skills/shared/overlays/brainstorming.overlay.md
git commit -m "upgrade-superpowers-6-3-0: fragment brainstorming pro tři cesty v6.3.0
 - úvod mapuje router (architectural/bounded plná brána, spike bez pinu)
 - odkazy na upstream checklist jménem fáze místo ordinálů
 - bounded: zápis schváleného návrhu bez druhého kola review; gate jen architectural
 - amendment path-bound terminálních stavů (bounded končí ve finishing)
 - Epic Backflow: pojmenovaný odklad pro bounded
 - první push větve s -u dle kontraktu; ASSERT kotvy na nosné věty upstreamu"
git push
```

---

### Task 5: Fragment subagent-driven-development

**Files:**
- Modify: `ums/.claude/skills/shared/overlays/subagent-driven-development.overlay.md`

**Interfaces:**
- Consumes: jména sekcí kontraktu z Tasku 2; direktivu ASSERT z Tasku 3

- [ ] **Step 1: ASSERT direktivy do hlavičky fragmentu**

Za řádek `<!-- ANCHOR: EOF -->` vložit:

```markdown
<!-- ASSERT: Four things stop you, and only these: an irreversible or destructive -->
<!-- ASSERT: them. The spec is the binding authority, the plan is its argument, and your -->
<!-- ASSERT: todo per task. If the plan names a Spec, read that too: the spec is the -->
```

(Věty ověřeny jako přesné unikátní řádky `subagent-driven-development/SKILL.md` v6.3.0.)

- [ ] **Step 2: Nové odrážky (rulingy, autorita/Spec, batch, ruling × kandidát, finish)**

Za odrážku `- **Model selection:** …` vložit:

```markdown
- **Rulings and STOPs:** rule on conflicts per the SKILL text above; this
  layer's fail-closed STOPs already fall within the four stop classes — see
  `../shared/UMS_MEMORY_BANK_CONTRACT.md`, section "Fail-Closed Behavior",
  paragraph "Rulings and these STOPs". Locally: merging the effective base
  into the agent's OWN ticket branch is NOT the "side effect outside this
  worktree" the four classes mean — it is mandatory at phase boundaries
  (Base sync below) and is never put to the user.
- **Authority and the Spec field:** a conflict between the design and the
  plan is resolved per the contract's "Active Work Item (Design + Plan
  Pair)" section — by subject: WHAT is the design's, HOW is the plan's. The
  plan header carries `**Spec:** [design_<slug>.md](…)`, so the upstream
  instruction "if the plan names a Spec, read that too" is satisfied and
  rulings are not provisional; tolerate the legacy `**Návrh:**` alias in
  plans written under contract ≤ v2.8.
- **Batched dispatches:** the resolved procedure document (Playbook below)
  is attached to a batch dispatch exactly as to a single-task dispatch, and
  one batch report ends with ONE `## Playbook candidates` section covering
  the whole batch.
- **Rulings vs playbook candidates:** a ruling is a decision, a candidate is
  a procedure — a ruling becomes a candidate only when it carries `Happened`
  evidence reaching beyond this work item (contract, "Playbook Contract").
- **Finish:** `rm -rf <workspace>` removes `.superpowers/sdd/<plan-basename>/`
  only. The playbook-candidate file lives in
  `.superpowers/playbook-candidates/`, OUTSIDE the plan workspace, and
  survives the workspace deletion — only the harvest removes it (contract,
  "Playbook Contract").
```

- [ ] **Step 3: Doplnění jazykové odrážky**

V odrážce `- **Language:** …` za větu `User-facing summaries are Czech.` doplnit:

```markdown
  `Ruling:` ledger lines stay English; the final "Rulings I made" list is
  user-facing and therefore Czech (contract, "Language Contract").
```

- [ ] **Step 4: Doplnění izolační odrážky (worktree terminologie)**

V odrážce `- **Isolation:** …` za větu `One session per workspace: work
  on several tickets is interleaved, not parallel.` doplnit:

```markdown
  Where the upstream text above says "outside this worktree", read "outside
  this clone/workspace" — worktrees are banned here.
```

- [ ] **Step 5: Commit a push**

```bash
git add ums/.claude/skills/shared/overlays/subagent-driven-development.overlay.md
git commit -m "upgrade-superpowers-6-3-0: fragment SDD pro ruling model v6.3.0
 - STOPy vrstvy mapované do čtyř tříd; base merge vlastní větve není side effect
 - autorita konfliktu per kontrakt; hlavička plánu nese Spec: (alias Návrh: tolerován)
 - batch dispatche: playbook i jedna sekce kandidátů za dávku
 - ruling × kandidát; kandidáti přežívají rm -rf workspace
 - jazyk ledgeru vs. seznamu rulingů; worktree → clone/workspace; ASSERT kotvy"
git push
```

---

### Task 6: Fragment finishing-a-development-branch

**Files:**
- Modify: `ums/.claude/skills/shared/overlays/finishing-a-development-branch.overlay.md`

**Interfaces:**
- Consumes: podsekci „Brainstorming Paths" z Tasku 2; direktivu ASSERT z Tasku 3

- [ ] **Step 1: ASSERT direktiva do hlavičky fragmentu**

Za řádek `<!-- ANCHOR-BEFORE: ## Step 5: Execute Choice -->` vložit:

```markdown
<!-- ASSERT: 1. Merge back to <base-branch> locally -->
```

(Řádek Option 1 ze Step 4, který tento overlay nahrazuje; ověřen v v6.3.0.)

- [ ] **Step 2: Bounded věta do harvest gate**

V prvním bodu (Option 1/2/3 → `mb-harvest`), za větu `Then execute the chosen option.` doplnit:

```markdown
  For a **bounded** work item (contract, "Brainstorming Paths") a missing
  plan half in `active/` is the EXPECTED shape — the harvest reports it and
  archives the design (its documented warning path); it is not unfinished
  work and not a reason to stop.
```

- [ ] **Step 3: Commit a push**

```bash
git add ums/.claude/skills/shared/overlays/finishing-a-development-branch.overlay.md
git commit -m "upgrade-superpowers-6-3-0: fragment finishing — bounded bez plánu je očekávaný tvar
 - harvest u bounded položky hlásí chybějící plán, nezastavuje
 - ASSERT kotva na řádek Option 1, který overlay nahrazuje"
git push
```

---

### Task 7: Dokumenty a piny

**Files:**
- Modify: `ums/.claude/skills/shared/SKILLS_MANIFEST.md`
- Modify: `ums/README.md`
- Modify: `memory-bank/tech.md`
- Modify: `memory-bank/brief.md`
- Modify: `memory-bank/architecture.md`
- Modify: `CLAUDE.md`, `ums/CLAUDE.md.sample`
- Modify: `ums/.claude/scripts/revendor-superpowers.ps1` (jen komentář)

- [ ] **Step 1: SKILLS_MANIFEST.md** — obě `v6.2.0` → `v6.3.0` (řádek 5 a nadpis „Vendorované Superpowers skilly").

- [ ] **Step 2: ums/README.md** — řádek 8 `(v6.2.0)` → `(v6.3.0)`; příklad `-Tag v6.2.0` → `-Tag v6.3.0`; v sekci „Harness compatibility" do výčtu portable harnessů `(Claude Code, Codex native discovery, Cursor, Copilot CLI, Kimi, OpenCode, pi)` doplnit `Devin CLI, Hermes Agent` (nové harnessy v6.3.0).

- [ ] **Step 3: memory-bank/tech.md** — tabulka Verze a piny: Superpowers 6.2.0 → 6.3.0; vendor pin na `tag v6.3.0, commit b36e0829c6d0140e93cfef2ca599b1b07d4a7797, vendorováno <datum z vygenerovaného VENDORED_FROM.md po Tasku 8>`; kontrakt 2.8 → 2.9. Smazat odstavec „Prosté textové odkazy na verzi upstreamu…" (řádky 17–19) — tímto upgradem se uzavírá.

- [ ] **Step 4: memory-bank/brief.md** — řádek 142: `kontrakt v2.8, vendor pin upstream v6.2.0` → `kontrakt v2.9, vendor pin upstream v6.3.0`; do výčtu harnessů na řádku 10–11 doplnit `Devin CLI, Hermes Agent`.

- [ ] **Step 5: memory-bank/architecture.md** — tři výskyty `v2.8`/`kontrakt v2.8` → v2.9 (řádky 13, 200, 342); v popisu Overlay 1 nahradit „Mění tři body upstream checklistu" a odkazy „Bod 1 (Explore project context)"/„Bod 6 (Write design doc)"/„mezi body 8 a 9" formulacemi přes jména fází a doplnit větu o routeru (architectural/bounded plná brána + pin, spike bez pinu, per kontrakt „Brainstorming Paths"); do sekce 6 (Vendoring) doplnit větu o ASSERT direktivě (EOF fragmenty s asserty na nosné věty; miss = detektor driftu jako ANCHOR-BEFORE).

- [ ] **Step 6: CLAUDE.md + ums/CLAUDE.md.sample** — v odrážce „Exekuce plánu (SDD)" nahradit větu `Eskalační body plánu („zastav a reportuj uživateli") smíš odložit na konec větve, pokud neblokují navazující tasky; skutečně blokující rozhodnutí běh zastaví.` za: `Konflikty, nejasnosti a eskalační body plánu rozhoduj rulingy dle SDD („Rulings, not stalls"): rozhodni, zapiš Ruling do ledgeru, pokračuj a na konci předlož seznam „Rulings I made"; STOP jen pro čtyři jmenované třídy (kontrakt, Fail-Closed Behavior) — merge báze do vlastní tiketové větve mezi ně nepatří.` (v obou souborech; zbytek odrážky beze změny).

- [ ] **Step 7: revendor komentář** — `# v6.2.0 sdd-workspace is plan-scoped` → `# Since v6.2.0, sdd-workspace is plan-scoped` (verze-agnostické, ať se to při příštím upgradu nemusí honit).

- [ ] **Step 8: Commit a push**

```bash
git add ums/.claude/skills/shared/SKILLS_MANIFEST.md ums/README.md memory-bank/tech.md memory-bank/brief.md memory-bank/architecture.md CLAUDE.md ums/CLAUDE.md.sample ums/.claude/scripts/revendor-superpowers.ps1
git commit -m "upgrade-superpowers-6-3-0: dokumenty a piny na v6.3.0 a kontrakt v2.9
 - manifest, README vrstvy (vč. Devin CLI a Hermes Agent), tech, brief, architecture
 - CLAUDE.md: eskalační body nahrazeny ruling modelem SDD
 - revendor komentář verze-agnostický"
git push
```

Pozn.: hodnota „vendorováno <datum>" v tech.md se doplní až po Tasku 8 (v jeho commitu) — Step 3 ji zapíše jako dosavadní datum a Task 8 ji zaktualizuje, NEBO se Step 3 tech.md řádku pinu odloží do Tasku 8. Exekutor zvolí druhou variantu, je čistší: v Tasku 7 změnit v tech.md jen verzi Superpowers, kontrakt a smazat odstavec o zaostávajících zmínkách; řádek vendor pinu celý přepsat v Tasku 8.

---

### Task 8: Lokální nasazení a revendor v6.3.0

**Files:**
- Modify (netrackované): `.claude/**`, `.agents/skills/**`
- Modify: `ums/.claude/skills/shared/VENDORED_FROM.md` (zpětná kopie z nasazení)
- Modify: `memory-bank/tech.md` (řádek vendor pinu — viz pozn. v Tasku 7)

**Interfaces:**
- Consumes: strom `skills/` z Tasku 1, fragmenty z Tasků 4–6, skript z Tasku 3
- Produces: nasazená vrstva, se kterou poběží verifikace v Tasku 9

- [ ] **Step 1: Kontrola D/R před merge-copy (playbook)**

```bash
git diff --name-status $(git merge-base origin/ums-memory-bank HEAD)..HEAD -- ums/ | grep -E '^(D|R)' || echo OK-zadne-mazani
```

Očekávané: `OK-zadne-mazani` (čistě A/M → merge-copy stačí). Jinak explicitně smazat odpovídající cíle v `.claude/` a `.agents/skills/` před kopií.

- [ ] **Step 2: Kopie zdroje do nasazení**

```bash
cp -r ums/.claude/. .claude/
```

(Merge sémantika ověřená v playbooku — cizí soubory v cíli přežijí.)

- [ ] **Step 3: Revendor nad kořenem forku**

```powershell
pwsh .claude/scripts/revendor-superpowers.ps1 -Tag v6.3.0
```

Spouští se **nasazená** kopie skriptu — `$UmsRoot` se z ní resolvuje na kořen forku, takže `$SkillsRoot` je kořenový `.claude/skills`. (Zdrojová kopie v `ums/.claude/scripts/` by vendorovala do `ums/.claude/skills/`, kam 14 vendorovaných skillů nepatří.) Očekávané: `applied` pro všechny 3 fragmenty, žádná ASSERT hláška, závěr `Verification passed.`

Pozn. k částečnému selhání: pokud aplikace fragmentů spadne uprostřed (např. ASSERT miss u druhého fragmentu), první fragment už je aplikovaný a opakovaný běh `-OverlaysOnly` skončí na „already contains an overlay block" — oprava se dělá opravou fragmentu + novým **plným** během (`-Tag v6.3.0`), který vendoruje načisto.

- [ ] **Step 4: Zpětná kopie VENDORED_FROM.md a Codex nasazení**

```bash
cp .claude/skills/shared/VENDORED_FROM.md ums/.claude/skills/shared/VENDORED_FROM.md
cp -r .claude/skills/. .agents/skills/
```

- [ ] **Step 5: Staleness kontrola nasazení**

```bash
diff -rq ums/.claude .claude | grep -v '^Only in .claude' || true
```

Očekávané: žádný řádek `differ` (soubory společné oběma stromům jsou identické; `Only in .claude` položky jsou vendorované skilly — legální).

- [ ] **Step 6: Doplnit vendor pin v tech.md**

Řádek vendor pinu v `memory-bank/tech.md` přepsat hodnotami z čerstvého `ums/.claude/skills/shared/VENDORED_FROM.md` (tag `v6.3.0`, commit `b36e0829c6d0140e93cfef2ca599b1b07d4a7797`, datum z vygenerovaného souboru).

- [ ] **Step 7: Commit a push**

```bash
git add ums/.claude/skills/shared/VENDORED_FROM.md memory-bank/tech.md
git commit -m "upgrade-superpowers-6-3-0: revendor na v6.3.0, obnova nasazení
 - VENDORED_FROM.md: tag v6.3.0, commit b36e082
 - tech.md: řádek vendor pinu
 - kořenový .claude/ a .agents/skills/ obnoveny (netrackované)"
git push
```

---

### Task 9: Verifikační baterie

**Files:**
- Modify: `memory-bank/proposals/active/design_upgrade_superpowers_6_3_0.md` (sekce „Verifikační evidence")

**Interfaces:**
- Consumes: nasazené vygenerované skilly z Tasku 8

- [ ] **Step 1: Tabulka uzavření rozporů**

Pro každý z pěti rozporů z návrhu (sekce „Rozpory, které upgrade uzavírá") dohledat ve **vygenerovaných** souborech (`.claude/skills/brainstorming/SKILL.md`, `.claude/skills/subagent-driven-development/SKILL.md`) přesný řádek upstream věty a řádek věty vrstvy (overlay blok nebo kontrakt) a zapsat řádek tabulky: upstream věta (soubor:řádek) × věta vrstvy (soubor:řádek) × mechanismus uzavření. Tabulku připojit do návrhu jako novou sekci `## Verifikační evidence`.

- [ ] **Step 2: Cold-reader průchod**

Projít vygenerovaný `brainstorming/SKILL.md` (s overlay blokem) očima chladného čtenáře pro šest kombinací: {spike, bounded, architectural} × {s tiketem, bez tiketu}, u bounded navíc {čistý strom, zbytky v cestě}. U každé zapsat do téže sekce návrhu jeden řádek: kombinace → posloupnost kroků, ke které text vede → OK/DEFEKT. Každý DEFEKT opravit ve fragmentu (+ nový revendor `-Tag v6.3.0` + aktualizace evidence) před pokračováním.

- [ ] **Step 3: Grep sweepy přes vrstvu**

```bash
grep -rn 'plan governs' ums/.claude/ .claude/skills/shared/ && echo NALEZ || echo OK
grep -rniE '\bitem [0-9]|\bitems [0-9]' ums/.claude/skills/shared/overlays/ && echo NALEZ || echo OK
grep -rn '2\.8' ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md   # očekávané: jen historie verzí
grep -rn '\*\*Návrh:\*\*' ums/ memory-bank/*.md   # očekávané: jen alias věta kontraktu (+ tento plán, který je legacy)
grep -rniE 'the single exception|only exception|jediná výjimka' ums/.claude/   # každý zásah přečíst
```

Nálezy vyhodnotit proti očekáváním; odchylky opravit ve stejném commitu.

- [ ] **Step 4: Celá testovací smyčka vrstvy**

```bash
for t in $(find ums -name "*.tests.ps1"); do echo "== $t"; pwsh -NoProfile -File "$t" || echo "FAILED: $t"; done
```

Očekávané: všech 16 sad zelených (613 asercí; `pre-push` sada přes 2 minuty). Na testované skripty se nesahalo (ASSERT je v revendoru, který sadu nemá) — **jakákoli červená je nález**, ne šum.

- [ ] **Step 5: Commit evidence a push**

```bash
git add memory-bank/proposals/active/design_upgrade_superpowers_6_3_0.md
git commit -m "upgrade-superpowers-6-3-0: verifikační evidence
 - tabulka uzavření pěti rozporů proti vygenerovaným souborům
 - cold-reader průchod tří cest; grep sweepy; testovací smyčka zelená"
git push
```

---

## Po dokončení

Finishing-a-development-branch (harvest gate → `mb-harvest` → integrace FF pushem; sdílený push spouští uživatel). Mimo tuto větev zbývají uživatelem řízené kroky: FF `main` na `vanila/main` a nasazení do monorepa (`sync ToMonorepo` + dvoucommitový revendor).
