# Epic Backflow + Design Review Fallback — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

- **Jira:** (žádný tiket)
- **Návrh:** [design_epic_backflow.md](design_epic_backflow.md)
- **Target MB:** memory-bank/

**Goal:** Zavřít zpětný tok z návrhu do epiku (krok po finálním schválení návrhu: orákulum `mb-epic-graph -Check`, fronta poznámky do ledgeru, nabídka inline elaboračního okna) a odblokovat design review workflow fallbackem Jira stavu „Design Review" → „Review" s markerem `[DESIGN REVIEW]`.

**Architecture:** Čistě textové změny vrstvy v `ums/.claude/` — normativní pravidla do kontraktu (bump 2.6 → 2.7), konzumenti (overlay brainstormingu, `mb-architect-review`, `mb-abort`, finishing overlay, `mb-epic-elaboration`, `mb-epic-graph`) na kontrakt jen odkazují. Žádný nový kód ani skript.

**Tech Stack:** Markdown (kontrakt + skilly), PowerShell testy jen jako regresní pojistka (beze změny).

## Global Constraints

- Pravidlo má jeden domov: plné znění v kontraktu, skilly říkají jen „per <jméno sekce>" plus co je čistě lokální (playbook, sekce „Kontrakt a skilly").
- Na kroky sousedů se odkazuje jménem fáze, ne pořadovým číslem; po vložení kroku grep celého souboru na čísla kroků (playbook).
- Jazyk: kontrakt a těla skillů anglicky; ledger/poznámky/hlášky uživateli česky (Language Contract). V anglickém textu smí být české literály hlášek.
- Žádný řádek v plánu/návrhu nezačíná zpětnými apostrofy, pokud to není skutečný ohraničovač bloku (playbook).
- V PowerShellových/markdownových textech žádné kudrnaté uvozovky uvnitř ASCII-uvozeného řetězce (playbook) — zde jen Markdown, platí pro ukázky.
- Autorita zdroje je `ums/.claude/`; kořenový `.claude/` je nasazená kopie a obnovuje se až v posledním tasku.
- Commit po každém tasku (česky), push tiketové větve po každém commitu (Publication Contract).
- Změna overlay fragmentů se do vendorovaných kopií v monorepu promítne až revendorem `-OverlaysOnly` — mimo scope tohoto repa; ohlásit v závěru.

---

### Task 1: Kontrakt — fallback „Design Review" → „Review" + marker

**Files:**
- Modify: `ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md` (hlavička verze; sekce „Architect Review Gate", odrážka „Status flow" v „Jira conventions")

**Interfaces:**
- Produces: kontraktová definice aliasu „sedí v Design Review" (stav „Design Review", NEBO „Review" + request komentář s první řádkou `[DESIGN REVIEW]`), na kterou se odkazují Tasky 3–5. Marker je VŽDY první řádka request komentáře (ne jen ve fallbacku).

- [ ] **Step 1: Bump verze kontraktu**

V hlavičce nahradit:

```markdown
- **Contract-Version:** 2.6
- Supersedes v2.5 (integration is a fast-forward push of the ticket branch, so
```

za:

```markdown
- **Contract-Version:** 2.7
- Supersedes v2.6 (adds the Epic Backflow section — design-approval check of
  the epic graph with a queued ledger note and an offered inline elaboration
  window — and the "Design Review" → "Review" status fallback with the
  `[DESIGN REVIEW]` request-comment marker).
- v2.6 superseded v2.5 (integration is a fast-forward push of the ticket branch, so
```

- [ ] **Step 2: Přepsat odrážku „Status flow" v Jira conventions (sekce Architect Review Gate)**

Nahradit:

```markdown
- Status flow: request transitions the ticket to **"Design Review"**; the
  architect's respond leaves the status unchanged; resume transitions to
  **"In Progress"**. Missing "Design Review" transition = fail-closed STOP
  with an instruction to create the status (prerequisite).
```

za:

```markdown
- Status flow: request transitions the ticket to **"Design Review"**; the
  architect's respond leaves the status unchanged; resume transitions to
  **"In Progress"**.
- **"Design Review" fallback.** When the "Design Review" transition does not
  exist (the status is not configured in the Jira instance), request falls
  back to the existing **"Review"** status. The request comment ALWAYS begins
  with the marker line **`[DESIGN REVIEW]`** — written unconditionally, so the
  fallback never depends on having predicted the transition's absence — and in
  the fallback state that marker is what distinguishes a design review from an
  ordinary review (code review / test). The fallback is announced to the user;
  the fail-closed STOP fires only when the "Review" transition is missing too.
  Wherever this contract or a skill tests that a ticket "sits in Design
  Review", the test reads: status "Design Review", OR status "Review" AND a
  request comment whose first line carries `[DESIGN REVIEW]`. The marker adds
  no new evidence — the request comment already records the resolver and the
  branch. A deleted marker degrades to the existing "respond without a request
  comment" path (ask the user, never guess). The fallback is a bridge, not a
  mode: once the "Design Review" status exists, the primary path stops using
  the fallback on its own — no configuration, no switch. `mb-epic-graph` does
  not read comments, so a fallback-shaped ticket gets the plain "Review"
  glyph — a documented imprecision of the bridge, not a defect to fix.
```

- [ ] **Step 3: Verify**

Run: `grep -n "Design Review" ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md`
Expected: odrážka „Status flow" už neobsahuje „Missing … = fail-closed STOP"; nová odrážka fallbacku existuje; ostatní výskyty („Discard/abort paths…", „While `context.md` carries…") zatím beze změny (řeší Task 5 aliasem u konzumentů — kontraktová věta „Discard/abort paths… in Design Review" alias přebírá z definice, text se nemění).

- [ ] **Step 4: Commit + push**

```bash
git add ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md
git commit -m "UMS: kontrakt 2.7 — fallback stavu Design Review na Review s markerem [DESIGN REVIEW]"
git push origin epic-backflow
```

---

### Task 2: Kontrakt — nová sekce „Epic Backflow (design → epic)"

**Files:**
- Modify: `ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md` (nová `##` sekce mezi „Architect Review Gate" a „Dispatch Model Policy")

**Interfaces:**
- Consumes: alias „sits in Design Review" z Tasku 1 (nezávislé — jen sousedství sekcí).
- Produces: normativní pravidlo kroku zpětného toku, na které odkazují Task 3 (overlay), Task 4 (resume) a Task 6 (elaborace). Definuje: spouštěcí bod, preconditions, orákulum jako spouštěč, frontu poznámky (dirty-set ledgeru / `notes.md`), nabídku inline okna, fail-open chování.

- [ ] **Step 1: Vložit novou sekci**

Bezprostředně PŘED řádek `## Dispatch Model Policy` vložit:

```markdown
## Epic Backflow (design → epic)

Refining a design can change the scope or the dependencies its ticket was
given when the epic was elaborated, and nothing else propagates that back:
the epic graph is a snapshot from elaboration time. This section closes the
gap with one bounded, fail-open step after final design approval.

**Trigger point.** The step runs once per work item, after the design is
FINALLY approved: at `mb-architect-review` resume when a review took place,
otherwise immediately after the user approves the spec. Never before the
review — a review may change the design, so an earlier check would be done
twice.

**When the step does not run:**

- No Jira ticket linked → skipped silently. Work without a ticket belongs to
  no epic; this is normality, not an exception, so nothing is announced.
- Atlassian MCP unavailable, or the ticket belongs to no epic → skipped with
  a one-line announcement.

**The trigger is the existing oracle, never a scope-diff metric.** Run the
`mb-epic-graph` skill with `-Check` (read-only). A finding concerning THIS
ticket is the trigger; findings about other tickets are printed and left
alone. An oracle failure skips the step with an announcement — the step is
fail-open and never blocks an approved design.

**On a finding, in this order:**

1. **Queue the note, always.** Append a dirty-set row to the epic's ledger
   (`<MB_ROOT>/memory-bank/epics/<epic_key_snake>/ledger.md`):
   „Položka/Tiket" = this ticket, „Zašpiněno oknem" = `návrh <slug>` (the
   dirt came from a design, not a window), „Důvod" = one line
   `návrh <slug> změnil <co>; okno by mělo přehodnotit <co>`. When no ledger
   exists, write the same line into
   `<MB_ROOT>/memory-bank/epics/<epic_key_snake>/notes.md` (created with the
   heading `# Poznámky pro elaboraci — <EPIC>`); the next elaboration window
   reads it at framing time. The note is committed on the ticket branch like
   any other commit of this work item — it is this work item's record, so it
   legitimately rides the ticket branch into the base at integration.
2. **Offer, never launch** (the user decides; "the graph is inconsistent" is
   exactly the situation where an agent slides into "just reconciling it"):
   - **(a) elaborate now — an inline window in this session.** The step
     stands at a phase boundary with a clean tree, so switching branches is
     legal: switch to an elaboration branch created from `<baseRef>`
     (explicit start point, after `git fetch origin`), run the window
     interactively per `mb-epic-elaboration` (the human window is preserved —
     subagents inside the window are a dispatch detail), close it with the
     window's single commit, push, switch back to the ticket branch and
     continue with writing-plans. Returning to the ticket branch is part of
     the step, not a follow-up.
   - **(b) keep the note and continue** — the human window is deferred to
     when the human wants it.

Elaboration artifacts therefore never land on the ticket branch: a window
closes with one commit on its own branch, and on a ticket branch that commit
would ride the fast-forward integration into the base as part of the ticket —
two units of work in one history. `mb-park` is NOT a prerequisite of this
step: parking remains the general workspace tool, but an inline window at a
phase boundary needs no second session.

A dirty-set row whose concern an inline window has already resolved (the row
lives on the ticket branch, the window on its own branch — neither sees the
other until both reach the base) is cleaned by the first window that sees
both; dirty rows are never deleted, cleaning is recorded (ledger maintenance
rules).
```

- [ ] **Step 2: Verify**

Run: `grep -n "^## " ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md`
Expected: `## Epic Backflow (design → epic)` mezi `## Architect Review Gate` a `## Dispatch Model Policy`.

- [ ] **Step 3: Commit + push**

```bash
git add ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md
git commit -m "UMS: kontrakt 2.7 — sekce Epic Backflow (zpětný tok z návrhu do epiku)"
git push origin epic-backflow
```

---

### Task 3: Overlay brainstormingu — krok Epic Backflow za Architect Review Gate

**Files:**
- Modify: `ums/.claude/skills/shared/overlays/brainstorming.overlay.md`

**Interfaces:**
- Consumes: kontraktová sekce „Epic Backflow (design → epic)" (Task 2).
- Produces: overlay bod, který krok spouští v bezreviewové větvi a deleguje ho na resume v review větvi.

- [ ] **Step 1: Vložit nový bod za blok Architect Review Gate**

Za odstavec končící `writing-plans remains the only *implementation* successor.` (bod „Architect Review Gate (between item 8 and item 9)") a PŘED bod `- While `memory-bank/context.md` contains a` vložit:

```markdown
- **Epic Backflow check (after the design is finally approved):** per the
  contract's "Epic Backflow (design → epic)" section. When the Architect
  Review Gate above hands the work off, the design is not finally approved
  yet — the check then belongs to `mb-architect-review` resume, not here; run
  it here only when no review takes place (no ticket → the whole step is
  skipped silently; review declined but ticket linked → run it after the
  user's spec approval). On a finding concerning this ticket: queue the
  ledger note, then offer the inline elaboration window or deferral — never
  launch elaboration unasked. Fail-open: an oracle failure or missing Jira
  skips the step with a one-line announcement.
```

- [ ] **Step 2: Verify**

Run: `grep -n "Epic Backflow" ums/.claude/skills/shared/overlays/brainstorming.overlay.md`
Expected: nový bod mezi Architect Review Gate a bodem o `Review:` řádce; overlay markery zůstávají vyvážené (`grep -c "UMS-OVERLAY" …` = 2).

- [ ] **Step 3: Commit + push**

```bash
git add ums/.claude/skills/shared/overlays/brainstorming.overlay.md
git commit -m "UMS: overlay brainstormingu — krok Epic Backflow po finálním schválení návrhu"
git push origin epic-backflow
```

---

### Task 4: mb-architect-review — alias fallbacku + Epic Backflow v resume

**Files:**
- Modify: `ums/.claude/skills/mb-architect-review/SKILL.md`

**Interfaces:**
- Consumes: alias „sits in Design Review" (Task 1), sekce „Epic Backflow" (Task 2).
- Produces: detekce režimu funkční i ve fallback stavu; request krok „Transition the ticket…" s fallbackem; resume spouští Epic Backflow check.

- [ ] **Step 1: Alias v Mode Detection**

Za číslovaný seznam Mode Detection (za bod 3 „**Undecidable**…Never pick silently.") vložit odstavec:

```markdown
"In Design Review" everywhere in this skill means the contract's test
(Architect Review Gate, "Design Review" fallback): status "Design Review",
OR status "Review" AND a request comment whose first line carries the
`[DESIGN REVIEW]` marker. A "Review" ticket without the marker is an
ordinary review and never enters respond/resume here.
```

- [ ] **Step 2: Marker v request kroku 7 (komentář)**

V kroku 7 requestu nahradit začátek věty:

```markdown
7. Publish a Czech comment to the ticket: a 10–15 line summary of the design
```

za:

```markdown
7. Publish a Czech comment to the ticket, its FIRST line being the
   `[DESIGN REVIEW]` marker (always — the fallback of the contract's
   Architect Review Gate depends on it), followed by: a 10–15 line summary of the design
```

- [ ] **Step 3: Fallback v request kroku 9 (přechod stavu)**

Nahradit:

```markdown
9. Transition the ticket to **"Design Review"**. Missing transition =
   fail-closed STOP: instruct the user to create the status (contract
   prerequisite).
```

za:

```markdown
9. Transition the ticket to **"Design Review"**. When that transition does
   not exist, fall back to **"Review"** and announce the fallback to the
   user (the step-7 marker already distinguishes it); only a missing
   "Review" transition too is the fail-closed STOP (contract, Architect
   Review Gate, "Design Review" fallback).
```

- [ ] **Step 4: Alias v respond kroku 1 a resume kroku 1**

V respond kroku 1 nahradit `The ticket must be in\n   "Design Review".` za `The ticket must sit in\n   "Design Review" (fallback shape included — see Mode Detection above).`
V resume kroku 1 nahradit `Expect "Design Review" + flag; missing` za `Expect the ticket to sit in "Design Review" (fallback shape included) + flag; missing`.

- [ ] **Step 5: Epic Backflow v resume**

Nahradit resume krok:

```markdown
6. Continue per workflow state: fold the notes into the design
   (brainstorming-style dialog over the architect's points, update the design
   file) → after user approval invoke writing-plans.
```

za:

```markdown
6. Continue per workflow state: fold the notes into the design
   (brainstorming-style dialog over the architect's points, update the design
   file) → after user approval run the **Epic Backflow check** per the
   contract's "Epic Backflow (design → epic)" section (the design is finally
   approved here, which is that step's trigger point; fail-open, offer only)
   → then invoke writing-plans.
```

- [ ] **Step 6: Verify**

Run: `grep -n "DESIGN REVIEW\|Epic Backflow\|fallback" ums/.claude/skills/mb-architect-review/SKILL.md`
Expected: alias v Mode Detection, marker v kroku 7, fallback v kroku 9, aliasy v respond/resume krok 1, backflow v resume kroku 6. Bump `version: "1.2"` → `"1.3"` ve frontmatteru.

- [ ] **Step 7: Commit + push**

```bash
git add ums/.claude/skills/mb-architect-review/SKILL.md
git commit -m "UMS: mb-architect-review — fallback Design Review a Epic Backflow check v resume"
git push origin epic-backflow
```

---

### Task 5: Konzumenti aliasu — mb-abort, finishing overlay, mb-epic-graph

**Files:**
- Modify: `ums/.claude/skills/mb-abort/SKILL.md` (sekce 4b)
- Modify: `ums/.claude/skills/shared/overlays/finishing-a-development-branch.overlay.md` (poslední odstavec discard cesty)
- Modify: `ums/.claude/skills/mb-epic-graph/SKILL.md` (sekce o status glyfu)

**Interfaces:**
- Consumes: alias „sits in Design Review" (Task 1).
- Produces: všechny zbývající konzumenty testu stavu čtou alias; dokumentovaná nepřesnost glyfu.

- [ ] **Step 1: mb-abort 4b**

Nahradit:

```markdown
If `context.md` carried a `Review:` line, or the linked ticket is in the
"Design Review" status: offer (Czech, user confirms) the cleanup per the
```

za:

```markdown
If `context.md` carried a `Review:` line, or the linked ticket sits in
"Design Review" (fallback shape included — status "Review" with the
`[DESIGN REVIEW]` request-comment marker; contract, Architect Review Gate,
"Design Review" fallback): offer (Czech, user confirms) the cleanup per the
```

- [ ] **Step 2: finishing overlay**

Nahradit:

```markdown
  If the linked ticket sits in "Design Review", offer the Jira cleanup per the
  contract's Architect Review Gate (transition back, restore assignee, clear the
  flag).
```

za:

```markdown
  If the linked ticket sits in "Design Review" (fallback shape included —
  status "Review" with the `[DESIGN REVIEW]` request-comment marker; contract,
  Architect Review Gate, "Design Review" fallback), offer the Jira cleanup per
  the contract's Architect Review Gate (transition back, restore assignee,
  clear the flag).
```

- [ ] **Step 3: mb-epic-graph — dokumentovaná nepřesnost glyfu**

Za větu `Design Review deliberately keeps\n  blocking: a design under review is not an implementation.` vložit:

```markdown
A ticket in the
  "Design Review" FALLBACK shape (status "Review" + the `[DESIGN REVIEW]`
  request-comment marker; contract, Architect Review Gate) gets the plain
  "Review" glyph (🧪): the graph does not read comments. A documented
  imprecision of the fallback bridge, not a defect — it corrects itself once
  the "Design Review" status exists in Jira.
```

- [ ] **Step 4: Verify**

Run: `grep -rn "DESIGN REVIEW" ums/.claude/skills/mb-abort/ ums/.claude/skills/mb-epic-graph/SKILL.md ums/.claude/skills/shared/overlays/finishing-a-development-branch.overlay.md`
Expected: po jednom výskytu v každém souboru; overlay markery finishing fragmentu vyvážené.

- [ ] **Step 5: Commit + push**

```bash
git add ums/.claude/skills/mb-abort/SKILL.md ums/.claude/skills/shared/overlays/finishing-a-development-branch.overlay.md ums/.claude/skills/mb-epic-graph/SKILL.md
git commit -m "UMS: alias fallbacku Design Review u zbývajících konzumentů + dokumentovaná nepřesnost glyfu"
git push origin epic-backflow
```

---

### Task 6: mb-epic-elaboration — konzumace poznámek zpětného toku

**Files:**
- Modify: `ums/.claude/skills/mb-epic-elaboration/SKILL.md`

**Interfaces:**
- Consumes: tvar poznámky a `notes.md` z kontraktové sekce „Epic Backflow" (Task 2).
- Produces: framing okna čte poznámky zpětného toku; Quick reference řádek.

- [ ] **Step 1: Framing fáze čte backflow poznámky**

V tabulce „The window lifecycle" nahradit obsah buňky fáze 1:

```markdown
| 1 | **Framing handshake** — propose window boundary + agenda (item IDs + open questions), suggest from ledger (dirty first, then leverage) | Human confirms or narrows BEFORE any design/verification work |
```

za:

```markdown
| 1 | **Framing handshake** — propose window boundary + agenda (item IDs + open questions), suggest from ledger (dirty first, then leverage; dirty rows stamped `návrh <slug>` and the epic's `notes.md`, both queued by the contract's Epic Backflow step, count as dirty input here — fold `notes.md` lines into the dirty-set and delete the file in this window's closing commit) | Human confirms or narrows BEFORE any design/verification work |
```

- [ ] **Step 2: Quick reference řádek**

Do tabulky Quick reference za řádek `| New ledger | …` vložit:

```markdown
| Backflow note from a design (contract, "Epic Backflow (design → epic)") | dirty-set row stamped `návrh <slug>`, or `memory-bank/epics/<epic>/notes.md` when no ledger existed — read at framing, folded into the dirty-set |
```

- [ ] **Step 3: Verify**

Run: `grep -n "Backflow\|notes.md" ums/.claude/skills/mb-epic-elaboration/SKILL.md`
Expected: framing buňka i Quick reference řádek; struktura tabulek nezměněná (sloupce/oddělovače — parsuje je `ledger-status.ps1` jen u ledgeru, SKILL.md neparsuje nic, ale konzistence drží čitelnost). Bump `version: "1.3"` → `"1.4"` ve frontmatteru.

- [ ] **Step 4: Commit + push**

```bash
git add ums/.claude/skills/mb-epic-elaboration/SKILL.md
git commit -m "UMS: mb-epic-elaboration — framing okna čte poznámky zpětného toku z návrhů"
git push origin epic-backflow
```

---

### Task 7: Sweep konzistence, regresní testy, obnova nasazení

**Files:**
- Modify: (jen nálezy sweepu, pokud budou)
- Deploy: kořenový `.claude/` (netrackovaná kopie `ums/.claude/`)

**Interfaces:**
- Consumes: všechny předchozí tasky.
- Produces: konzistentní vrstva, zelené testy, aktuální nasazení.

- [ ] **Step 1: Sweep charakteristických tokenů**

Run: `grep -rn "Design Review" ums/ --include="*.md" | grep -v tests/` a `grep -rn "Epic Backflow" ums/ --include="*.md"`
Expected: každý výskyt „Design Review" mimo kontrakt buď cituje alias/fallback, nebo je legitimně jen o primárním stavu (např. glyf 👀 v Jira režimu); žádný restatement pravidla mimo kontrakt. Nálezy opravit v tomto tasku.

- [ ] **Step 2: Kontrola verze kontraktu napříč vrstvou**

Run: `grep -rn "Contract-Version\|kontrakt v2\.6\|contract v2\.6" ums/ memory-bank/ --include="*.md" | grep -v proposals/`
Expected: `ums/` neodkazuje na 2.6 tam, kde míní aktuální verzi (README/manifest — opravit na 2.7); `memory-bank/*.md` (architecture/tech/brief) se NEOPRAVUJE teď — to je práce harvestu na konci větve.

- [ ] **Step 3: Regresní testy vrstvy**

Run: `for t in $(find ums -name "*.tests.ps1"); do echo "== $t"; pwsh -NoProfile -File "$t" || echo "FAILED: $t"; done`
Expected: všech 13 sad zelených (564 asercí), žádný řádek FAILED. Textové změny nesmí nic rozbít; červená sada = STOP a analýza.

- [ ] **Step 4: Obnova nasazené kopie**

```bash
cp -r ums/.claude/skills/shared .claude/skills/
cp -r ums/.claude/skills/mb-architect-review ums/.claude/skills/mb-abort ums/.claude/skills/mb-epic-elaboration ums/.claude/skills/mb-epic-graph .claude/skills/
```

Expected: `Contract-Version: 2.7` v `.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md`. Poznámka: vendorované kopie `brainstorming`/`finishing-…` s overlay bloky vyrábí až revendor v monorepu (`-OverlaysOnly`) — ohlásit uživateli jako navazující krok mimo tento repozitář.

- [ ] **Step 5: Commit + push (jen pokud sweep něco opravil)**

```bash
git add -A ums/
git commit -m "UMS: sweep konzistence po zavedení Epic Backflow a fallbacku Design Review"
git push origin epic-backflow
```
