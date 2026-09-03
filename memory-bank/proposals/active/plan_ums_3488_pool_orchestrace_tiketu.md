# Mechanika poolu — spuštění sezení na tiket do slotu: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Zautomatizovat mechaniku rozjetí sezení na tiket do slotu poolu — derivovaný stav slotu, launcher se strojově ověřeným spuštěním, skill `mb-epic-run` — a dokončit session baton dvěma amendmenty.

**Architecture:** Slot poolu je uživatelem provisionovaný, markerem označený linked git worktree; jeho stav se **derivuje** při každém dotazu jen z per-worktree signálů plus obsazenosti z `claude agents --json`, žádná evidence nevzniká. Záměr se do slotu doručuje **argv** (jeden zauvozovkovaný prompt) a **jedním řádkem v commitnutém ledgeru** epiku — do pracovního stromu slotu orchestrátor nezapíše nic. Tři PowerShellové skripty (`pool-status`, `pool-launch`, `pool-provision`) nesou mechaniku, skill `mb-epic-run` je řídí a reportuje česky.

**Tech Stack:** PowerShell 7 (skripty a testy vrstvy, bezzávislostní vlastní asercie), Markdown (kontrakt, skilly, overlay fragmenty), git (worktree, hooky), Claude Code CLI (`claude agents --json`, `wt.exe`).

**Jira:** UMS-3488 (https://datasyscz.atlassian.net/browse/UMS-3488)

**Spec:** [design_ums_3488_pool_orchestrace_tiketu.md](design_ums_3488_pool_orchestrace_tiketu.md)

**Target MB:** memory-bank/

## Global Constraints

Tyto podmínky platí implicitně pro **každou** úlohu níže.

- **PowerShell 7.** Každý nový `.ps1` začíná `#Requires -Version 7`, dále `Set-StrictMode -Version Latest` a `$ErrorActionPreference = 'Stop'`. Kde skript volá nativní příkazy a sám vyhodnocuje jejich exit kód, přidej i `$PSNativeCommandUseErrorActionPreference = $false` (vzor: `ums/.claude/hooks/session-intent.ps1`).
- **Nulové závislosti.** Žádný Pester, žádný PowerShell modul, žádný balíček. Testy jsou obyčejné `.ps1` skripty s vlastními aserčními funkcemi.
- **Konvence testů** (playbook, sekce „Testy vrstvy"): sada leží v `tests/` vedle kódu a jmenuje se `<téma>.tests.ps1`; **každý adresář testů má vlastní kopii `_assert.ps1`** (natahuje se přes `. (Join-Path $PSScriptRoot '_assert.ps1')`); sady běží **offline** (žádná síť, žádný `origin`, žádná Jira); fixtury jsou pod `tests/fixtures/`.
- **Sadu spouštěj po dávkách 1–4 souborů**, nikdy celou smyčku jedním příkazem — jedna sada běží přes minutu a výchozí timeout ji zabije bez signálu, které doběhly.
- **Pass/fail posuzuj z markerů, ne z prózy:** grepni `FAIL`, řádek `<N> passed` a přečti exit kód. České asserční hlášky se v bashové konzoli vykreslují jako mojibake — to není nález.
- **Počty asercí do dokumentace získávej spuštěním CELÉ sady ve stejném sezení jako úpravu**, nikdy aritmetikou; součet nech spočítat strojově a počet sad ber z `find ums -name "*.tests.ps1" | wc -l`.
- **Každý nový regresní strážce ověř vlastní negativitou** a výsledek rozděl do TŘÍ kategorií: zčervenalo / zůstalo zeleně v obou bězích (regresní zámek) / NEPROVEDENO (vše za bodem přerušení). Po mutaci obnov soubor ze zálohy pořízené PŘED mutací a shodu doluž `sha256sum` + `cmp` — u netrackovaného souboru je prázdný `git diff` bezcenný.
- **PowerShellové pasti, které tato vrstva má změřené:** české uvozovky (`„`/`"`) nikdy uvnitř dvojitě uvozeného literálu, jen v `'…'`; `@()` kolem `Get-Content` před `.Count`/indexací; porovnání operandů z gitu case-sensitive (`-ceq`/`-cne`/`-cmatch`); funkci nikdy nepojmenuj `Git`; nepřiřazený výstup uvnitř funkce zahazuj `| Out-Null`; `[Console]::OutputEncoding = [Text.Encoding]::UTF8` všude, kde se čte český nebo diakritický výstup potomka.
- **Jazyk** (kontrakt, Language Contract): skripty vrstvy, jejich komentáře i konzolový výstup **anglicky**; kontrakt, těla skillů a overlay fragmenty **anglicky**; reporty `mb-epic-run` pro uživatele, MB dokumenty, commit messages a tento plán **česky**.
- **Commit a publikace po každé úloze:** commit přes skill `mb-git-commit` (scoped staging, česká zpráva s prefixem `UMS-3488:` a detailními řádky `` - ``), pak publikace vlastní tiketové větve. Větev `UMS-3488-pool-orchestrace-tiketu` **je už publikovaná**, takže se pushuje běžně, bez `-u`.
- **Bázi (`origin/ums-memory-bank`) merguj jen na hranicích fází, nikdy uprostřed úlohy.**
- **Vendorované soubory nikdy needituj mimo bloky `<!-- UMS-OVERLAY BEGIN/END -->`.** Změna patří do fragmentu v `ums/.claude/skills/shared/overlays/`.
- **Po každé změně zdroje v `ums/.claude/` obnov nasazenou kopii** (`.claude/`, pro Codex i `.agents/skills/`), jinak sezení pracuje podle staré verze. Změna overlay fragmentu navíc vyžaduje **plný jednoprůchodový revendor s pinovaným tagem** `v6.3.0` (ne `-OverlaysOnly`) a pořadí je závazné: nejdřív kopie zdroje do `.claude/`, teprve pak revendor.
- **Worktrees vytváří výhradně uživatel.** Agent žádný `git worktree add` nespouští; `pool-provision.ps1` je operátorský nástroj a agent ho nevolá.
- **Kontrakt jde z 2.12 na 2.13** a ten bump je **vlastní sweep**, oddělený od slovníkových sweepů: `grep -rn '2\.12' ums/ memory-bank/ CLAUDE.md`; soubory vrstvy opravuje implementace ve stejném commitu jako pravidlo, dokumenty Memory Bank předává harvestu jmenovitým seznamem, `proposals/completed/` se **nikdy needituje**.
- **V plánu ani v žádném zapsaném dokumentu nezačínej řádek zpětnými apostrofy**, pokud to není skutečný ohraničovač bloku — `scripts/task-brief` na tom ztratí hranice úloh.

## File Structure

| Cesta | Vzniká / mění se | Odpovědnost |
|---|---|---|
| `ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md` | mění | Normativní zdroj: verze 2.13, výjimka poolu ve Worktree Policy, per-worktree derivace volnosti, povinný a validovaný `Instruction`, odpojení upstreamu po `switch -c` |
| `ums/.claude/hooks/session-intent.ps1` | mění | Čtenář batonu: A2 (povinný a validovaný `Instruction`), A1 (`initialUserMessage`) |
| `ums/.claude/hooks/tests/session-intent.tests.ps1` | mění | Pokrytí A1 a A2 |
| `ums/.claude/skills/shared/overlays/subagent-driven-development.overlay.md` | mění | Výčet klíčů batonu páté stop třídy musí jmenovat `Instruction` |
| `ums/.claude/skills/shared/overlays/brainstorming.overlay.md` | mění | `git branch --unset-upstream` po vytvoření tiketové větve |
| `ums/.claude/skills/mb-epic-run/SKILL.md` | vzniká | Skill se čtyřmi operacemi (`status`, `ready`, `spawn`, `attach`), železná pravidla, české reporty |
| `ums/.claude/skills/mb-epic-run/scripts/pool-status.ps1` | vzniká | Derivace stavu slotů — jediný zdroj pravdy o tom, co je slot a kdy je volný |
| `ums/.claude/skills/mb-epic-run/scripts/pool-launch.ps1` | vzniká | Vyčištění zděděného prostředí, dva adaptéry, argv prompt, stavové slovo |
| `ums/.claude/skills/mb-epic-run/scripts/pool-provision.ps1` | vzniká | Operátorský nástroj: guard, `worktree add`, marker, kontrola sdíleného hooku |
| `ums/.claude/skills/mb-epic-run/tests/_assert.ps1` | vzniká | Kopie aserčního helperu pro tento adresář testů |
| `ums/.claude/skills/mb-epic-run/tests/new-pool-fixture.ps1` | vzniká | Builder fixtury: repozitář se **skutečnými** linked worktrees a sdíleným `.git` |
| `ums/.claude/skills/mb-epic-run/tests/pool-status.tests.ps1` | vzniká | Volnost, marker, obsazenost, párování ledgeru na slug z pinu |
| `ums/.claude/skills/mb-epic-run/tests/pool-launch.tests.ps1` | vzniká | Vyčištění prostředí, doručení promptu přes oba adaptéry, `unavailable` |
| `ums/.claude/skills/mb-epic-run/tests/pool-provision.tests.ps1` | vzniká | Guard proti agentní relaci, marker, kontrola hooku |
| `ums/.claude/skills/mb-epic-run/README.md` | vzniká | Anglický popis skriptů a jejich rozhraní |
| `ums/.claude/skills/shared/SKILLS_MANIFEST.md` | mění | Zápis nového skillu |
| `ums/.claude/skills/mb-epic-elaboration/SKILL.md` | mění | Fáze 7 (Close) nabízí `mb-epic-run ready`/`spawn`; řádek v quick-reference |
| `ums/.claude/skills/mb-epic-elaboration/protocol.md` | mění | §3.3 uzávěrky |
| `ums/.claude/skills/mb-epic-elaboration/ledger-template.md` | mění | Konvence sekce „Rozjetí" (řádek záměru) |
| `ums/.claude/skills/mb-epic-elaboration/scripts/ledger-status.ps1` | mění | Čtení a report sekce „Rozjetí" |
| `ums/.claude/skills/mb-epic-elaboration/tests/fixtures/ledger_rozjeti.md` | vzniká | Fixtura **nesoucí** řádek záměru |
| `ums/.claude/skills/mb-epic-elaboration/tests/ledger-status.tests.ps1` | mění | Asercie nad novou fixturou |
| `ums/.claude/settings.json` | mění | `permissions.deny` pro `git worktree` a `pool-provision.ps1` |
| `ums/README.md` | mění | Strom adresářů, matice harnessů, verze kontraktu |
| `docs/pool-rozjeti-tiketu.md` (v `ums/`) | vzniká | Český průvodce operátora |

**Rozhodnutí o hranicích, které plán dělá nad rámec návrhu.** Návrh mluví o „třech skriptech vrstvy" bez určení adresáře. Plán je ukládá do `ums/.claude/skills/mb-epic-run/scripts/`, protože `sync-with-monorepo.ps1` kopíruje **celé adresáře skillů** — skript ležící mimo adresář skillu by s ním k uživateli neputoval (stejný důvod, pro který má každý adresář testů vlastní `_assert.ps1`).

---

### Task 1: Kontrakt 2.13

Pravidlo má jeden domov. Kontrakt jde **před** implementací kteréhokoli z těch pravidel, A2 nevyjímaje — proto je to první úloha a proto do ní patří **všech pět** okruhů změn ze sekce 7 návrhu, včetně pravidla o odpojení upstreamu, jehož overlay implementace přijde až v úloze 8.

**Files:**
- Modify: `ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md`
- Modify: `ums/README.md:40` (jen řetězec verze — je to soubor vrstvy, tedy vlastník je implementace)

**Interfaces:**
- Consumes: nic z předchozích úloh (první úloha plánu).
- Produces: normativní text, na který se odvolávají úlohy 2 (`Instruction` povinný a validovaný), 3 (per-worktree derivace volnosti, marker, `claude agents` jako signál), 5 (výjimka poolu z Worktree Policy, provisionace výhradně uživatelem), 6 (slot je workspace ve smyslu kontraktu) a 8 (`git branch --unset-upstream`). Žádné programové rozhraní.

- [ ] **Step 1: Přečti obě verzovací konvence, než sáhneš na hlavičku**

Otevři `ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md` a přečti řádky 1–45. Konvence běžící historie je: aktuální verze má řádek `Supersedes vPREV (…)`, všechny starší mají tvar `vX superseded vY (…)`. Bump proto **přeformulovává i řádek, který byl current předtím** — jinak vzniknou dvě po sobě jdoucí neverzované věty „Supersedes", ze kterých nelze poznat, jaký přechod každá popisuje.

- [ ] **Step 2: Bump verze a historie**

Změň řádek 3 na `- **Contract-Version:** 2.13`, přeformuluj stávající první „Supersedes" řádek a vlož nový. Výsledná hlavička začíná takto:

```markdown
# UMS Memory Bank Contract

- **Contract-Version:** 2.13
- Supersedes v2.12 (adds the pool-slot exception to the Worktree Policy and
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
```

Zbytek historie (`v2.11 superseded v2.10` a níž) zůstává beze změny.

- [ ] **Step 3: Přepiš Worktree Policy**

Najdi sekci `## Worktree Policy`. Věta nesoucí celou váhu zákazu (25 GB / 4,1 GB / 16 %) je **měřením vyvrácená** a musí se přepsat, ne jen doplnit výjimkou. Nahraď celou sekci tímto textem:

```markdown
## Worktree Policy

**Default: total ban.** Git worktrees must not be created by an agent in this
monorepo. Enforced by: `permissions.deny` on `EnterWorktree`/`ExitWorktree`,
`skillOverrides: using-git-worktrees: off`, and the CLAUDE.md ban. The
superpowers isolation step resolves to **branch-in-place**: create a feature
branch in the existing working directory (never work on main/master without
explicit user consent).

**The ban does not rest on disk cost, and the earlier measurement that said it
did was wrong.** Measured 2026-09-02 on the UMS monorepo: a linked worktree
occupies 7.7 GB, the shared `.git` 4.4 GB and the main clone 27.2 GB, so a
linked worktree saves roughly 70 %, not 16 % — the difference is accumulated
build output, not source. What the ban actually rests on is the model: one
session per workspace, and no workspace an agent provisioned for itself.

**One exception: a POOL SLOT.** A pool slot is a linked worktree the USER
created and MARKED (the marker file `.superpowers/pool-slot`), which lives
across many tickets and hosts at most one session. The layer looks at it as a
FOUND workspace — Workspace Discipline, the entry gate, `mb-park` /
`mb-harvest` / `mb-abort`, the Publication Contract and the cross-clone
collision check all apply to it unchanged. Agent-created worktrees stay
banned; provisioning a slot is an operator action (`pool-provision.ps1`,
which refuses to run under an agent-session marker without an explicit
operator switch).

An idle slot is detached, or stands on a branch whose name equals the slot
directory's name — but **IDLE is decided by the pin and never by a branch
name.** Measured: a slot standing on its own eponymous branch with a clean
tree carried an ACTIVE pin, so the pool's real convention is "its own branch
PARKS the slot while the pin persists". The name shape is accepted for a
different reason: it is a named place to switch a slot to when a branch
checked out elsewhere has to be released.

**A shared `.git` is what keeps the publication guarantee.** Measured: from
each of four slots `git rev-parse --git-path hooks/pre-push` returns the same
file under the main clone's `.git`, so ONE run of `install-git-hooks.ps1`
covers every slot. Two traps of that check: the path SHAPE differs by where
you ask from (absolute from a slot, relative `.git/hooks/pre-push` from the
PRIMARY worktree), so any cross-slot identity comparison must normalize to an
absolute path; and a RELATIVE `core.hooksPath` resolves per worktree, which
means each slot then needs its own installer run.
```

- [ ] **Step 4: Oprav derivaci „volný workspace" ve Workspace Discipline**

V sekci `## Workspace Discipline` najdi odstavec začínající `**"A free workspace" is a derived state, not a record.**` a **za něj** vlož novou podsekci. Nepřepisuj původní odstavec — popisuje klon s vlastním `.git` a tam platí; nová podsekce ho zužuje na ten případ a pro pool dává vlastní derivaci.

Do původního odstavce přidej hned za jeho první větu závorku `(for one clone with its own `.git`; a pool slot shares `.git` and is covered by the subsection below)`. Pak vlož:

```markdown
### A pool slot's freedom is derived from per-worktree signals only

A pool slot (Worktree Policy) shares `.git` with every other slot, so the
three-signal derivation above does not hold there as written. Measured: in a
linked worktree only `HEAD` and the index are per-worktree; `refs/stash` and
`refs/heads` are SHARED — `git -C <slot> rev-parse --git-path refs/stash`
returns the same file from two different slots. `git stash list` therefore
answers identically from every slot, and `--branches` is repo-wide by
construction, so ONE unpushed commit anywhere in the repository would make
EVERY slot permanently unfree.

The signals that decide a slot's freedom:

| Signal | Source | Scope |
|---|---|---|
| dirty tree | `git -C <slot> status --porcelain` | per-worktree |
| unpushed commits OF THIS SLOT | `git -C <slot> log '@{upstream}..HEAD'`, or `git -C <slot> log HEAD --not --remotes` with no upstream | per-worktree |
| branch, or detached | `git worktree list --porcelain` | per-worktree |
| pin | `<slot>/memory-bank/context.md` | per-worktree |
| plan progress | `<slot>/.superpowers/sdd/plan_<slug>/progress.md` OF THE SLUG THE PIN NAMES | per-worktree |
| **live session** | `claude agents --json --cwd <slot>`, records with a `pid` present | per-worktree |
| stash | `git stash list` | **repo-wide — cannot be attributed to a slot** |
| playbook candidate | `<slot>/.superpowers/playbook-candidates/<slug>.md` | per-worktree, but only meaningful WHILE THE SLOT CARRIES A PIN |

**Occupancy is read from the harness, not from git.** Without that signal the
derivation has a hole git cannot close: a slot with a clean tree and an IDLE
pin in which a session has just started reads as "free" for as long as that
session needs to reach its pin write — the entry gate with a fetch and a
collision scan, on the order of a minute — and a spawn would send a second
session into it, which "one session per workspace" forbids. **A live session
in a slot is therefore a hard reason not to use it.** The signal is
fail-closed: when it cannot be read, occupancy is reported as UNKNOWN and no
spawn proceeds without an explicit operator instruction. PID files under the
user's Claude directory are NOT read — that is an undocumented interface.

**A free slot** carries the marker, a clean tree, an IDLE pin, NO live
session, no unpushed commits on its own HEAD or its own branch, and does not
hold a ticket branch of the epic being spawned.

Two signals are deliberately excluded. **A stash cannot be attributed to a
slot** — it is reported once per repository as information, never as a
property of a slot. **A playbook candidate is defined only against the
CURRENT slug**, and an IDLE slot has no current slug, so every candidate in it
is a foreign one, which this contract already classifies as "merely present":
announced, never touched. Were it part of freedom, the slot would be
permanently unusable with no defined remedy — only the harvest of that slug
may delete the file, and that slug is finished.

**The ledger is paired to the slug FROM THE PIN, never to "the first directory
found under `sdd/`".** Measured: a slot pinned to one slug carried two
directories under `.superpowers/sdd/`, and the leftover of earlier work sorts
first — "first found" would report foreign progress as this ticket's.

A slot with NON-RECOVERABLE leftovers is not free, and the orchestrator does
NOT tidy it: it reports the slot and leaves the decision to the user, in the
slot where the leftovers lie.
```

- [ ] **Step 5: Zúž dvě věty Workspace Discipline na aktéra**

Pool provisionaci zavádí, ale výhradně pro uživatele a vynuceně, takže dvě absolutní věty přestaly platit jak jsou.

V úvodu sekce `## Workspace Discipline` najdi větu `The layer therefore treats a workspace as found, never as freshly provisioned.` a nahraď ji větou:

```markdown
The layer therefore treats a workspace as found, never as one the SESSION
provisioned: the one provisioning tool this layer has (`pool-provision.ps1`,
Worktree Policy) belongs to the operator and refuses to run under an
agent-session marker.
```

Pak grepni celý soubor na druhou takovou větu — `grep -n 'never provisions\|freshly provisioned\|provisiony' ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md` — a stejným způsobem zúž i ji. **Grepni navíc počítací a jedinečnostní slovník**, protože ten se láme přidáním nové instance, ne změnou té popisované:

```bash
grep -nE 'jediná|jediný|přesně|žádná výjimka|only|never|always|exactly|single|the one|no exception' ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md | grep -in 'worktree\|provision\|workspace'
```

Každý zásah přečti proti textu, jak stojí po krocích 3–4, a oprav každou větu, která tvrdí kardinalitu, jež právě přestala platit.

- [ ] **Step 6: `Instruction` povinný a validovaný v sekci Session Intent Baton**

V sekci `### Session Intent Baton` najdi odstavec `**Shape.**` a jeho větu o povinných klíčích. Nahraď část o povinných klíčích a doplň validaci:

```markdown
**Shape.** The first line is the identity line, `# Session intent — <ISO-8601
UTC>`. The body is a block of `Key: value` lines. Required: `Kind`
(`plan-execution` | `plan-resume`), `Plan`, `Branch`, `Slug` and
`Instruction`. Optional: `Spec`, `Ticket`, `Ledger`, `Next task` — omitted when
they have no value, never written empty. The last line is that single
`Instruction:` line naming the skill to invoke. Paths are relative to
`MB_ROOT`.

**`Instruction` is required AND validated, and the reason is what the reader
does with it.** Earlier versions named it "the last line" in prose while the
reader carried it only in its render order, so a baton without it was
delivered. Its value must NAME AN EXISTING SKILL — the reader derives the set
of legal names from the skill directories beside its own hook directory — and
must not exceed a short length ceiling. Without both checks the reader would
hand up to the whole size ceiling of attacker-chosen text as an automatically
executed first move. An empty or unreadable skill list makes every
`Instruction` unmatchable and therefore every baton stale, and that is the
right answer rather than a degradation to skip: the documented fallback for a
lost baton is the operator typing the intent, which costs nothing.
```

- [ ] **Step 7: Baton je nosič záměru ve VLASTNÍM workspace**

Do téže sekce, za odstavec `**Consume-on-read.**`, vlož odstavec, který zabrání příštímu čtenáři znovu bez důvodu zavádět nový druh batonu:

```markdown
**The baton carries intent within ONE'S OWN workspace, and no further.** It is
an AMBIENT channel: a `SessionStart` hook fires in every session anyone opens
in that worktree, so the baton cannot address a particular process. Delivering
intent into a DIFFERENT workspace — a pool slot — is therefore not a third
`Kind` but a different channel entirely: the prompt travels on the launched
process's argv and the rest is PULLED from a committed ledger line. Every
guard a `ticket-start` baton would have needed (a `Slot` origin binding, a
clean-tree check, a check that the ticket branch does not exist, an IDLE-pin
check, a shape check on `Ticket`) is repair work bought by that one change of
channel, and both proven launchers carry a prompt already. Do not reintroduce
a `ticket-start` kind without a member that needs one.
```

- [ ] **Step 8: Repository Configuration — co konfigurace NENÍ**

V sekci `## Repository Configuration`, za tabulku klíčů a jejich konzumentů, vlož:

```markdown
**No `pool` block, and two named non-keys.** Neither the list of environment
variables a launcher strips before spawning a session nor the path to the
harness executable is repository configuration: both are properties of the
HARNESS, not of the repository, so they live in the launcher script's own body.
Recording it here is what keeps the section's opening sentence — "no
repository-specific value may live in a skill body or in a script" — true
rather than quietly contradicted. Pool membership is likewise not
configuration: it is derived from `git worktree list` plus the marker file in
the worktree itself (Worktree Policy).
```

- [ ] **Step 9: Odpojení upstreamu po `switch -c`**

Kontrakt dnes řeší past jen první publikací (`git push -u`); odpojení upstreamu chybí a je to změřená past. V sekci `## Publication Contract` najdi odstavec začínající `**The first publication of a freshly created ticket branch is` a nahraď ho:

```markdown
**A freshly created ticket branch is DETACHED from its inherited upstream, and
its first publication is `git push -u origin <branch>` — never a bare
`git push`.** `git switch -c <branch> <chosen base>` sets the new branch's
upstream to the BASE, so until that upstream is rewritten every bare push
targets the (typically protected) base branch. Two steps, and both belong at
the source rather than in any one caller's prose: immediately after the
`switch -c`, run `git branch --unset-upstream`, so no accident in between can
aim at the base; and publish the first time with `-u`, which sets the upstream
to the branch itself. When inspecting a workspace, a ticket branch whose
upstream is a protected branch is a finding, not a normal state.
```

Pak grepni kontrakt na každé další místo, které `switch -c` popisuje — `grep -n 'switch -c' ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md` — a u každého se ptej, jestli po této změně ještě platí, jak stojí. Sekce „Cross-Branch Visibility" nese vlastní formulaci vytvoření větve; doplň do ní jednu větu odkazující na pravidlo jménem, ne opis: `Immediately after creation the branch is detached from its inherited upstream (Publication Contract, the first-publication rule).`

- [ ] **Step 10: Language Contract — poznámka o skriptech poolu**

V sekci `## Language Contract`, do odrážky `**Developer tooling is English.**`, doplň jména nových skriptů do výčtu, aby výčet zůstal úplný:

```markdown
- **Developer tooling is English.** The layer's own PowerShell tooling —
  `install-git-hooks.ps1`, `sync-with-monorepo.ps1`,
  `revendor-superpowers.ps1`, `pool-status.ps1`, `pool-launch.ps1`,
  `pool-provision.ps1` and their console output — is written and speaks
  English, matching the code around it; only what an agent or a user meets
  during Memory Bank WORK is Czech (the `pre-push` and `guard-git-push.mjs`
  rejection messages, the `mb-*` skills' reports — `mb-epic-run` included —
  `doc-index.ps1` / `epic-graph.ps1` tables and findings). This is a named
  exception, not a mixed-language rule surface: the boundary is the artifact,
  and each artifact is wholly one language.
```

- [ ] **Step 11: Sweep bumpu verze — vlastní průchod, oddělený od slovníkových sweepů**

Spusť:

```bash
grep -rn '2\.12' ums/ memory-bank/ CLAUDE.md
```

Rozděl nálezy podle vlastníka a v TÉTO úloze oprav jen soubory vrstvy:

- `ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md:3` — hotovo krokem 2.
- `ums/README.md:40` — přepiš `contract v2.12` na `contract v2.13`.
- `memory-bank/architecture.md` (3 výskyty), `memory-bank/brief.md` (2), `memory-bank/tech.md` (1), `memory-bank/tasks.md` (1) — **dokumenty Memory Bank, patří harvestu.** Nezasahuj do nich; zapiš je do ledgeru plánu jako jmenovitý předávací seznam pro harvest.
- `memory-bank/proposals/completed/design_baton_rotace_kontextu.md` — **archiv, nikdy needituj.**

`memory-bank/tasks.md` je legacy dokument, který v tomto repu žije vedle `playbook.md`; rozhodni ho jmenovitě v předávacím seznamu (patří harvestu stejně jako ostatní MB dokumenty), ne mlčky.

- [ ] **Step 12: Ověř zásahy grepem, ne četbou diffu**

Každé tvrzení ověř v tomto běhu strojově:

```bash
grep -n 'Contract-Version' ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md
grep -c 'v2.12 superseded v2.11' ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md
grep -n 'pool-slot\|POOL SLOT\|per-worktree signals only' ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md
grep -n 'unset-upstream' ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md
grep -rn '2\.12' ums/
```

Očekávané: `Contract-Version: 2.13`; právě jeden výskyt `v2.12 superseded v2.11`; nenulové zásahy na pool i `unset-upstream`; poslední grep **prázdný** (v `ums/` nesmí zůstat žádná 2.12).

Pak přečti celou sekci `## Worktree Policy` a celou `## Workspace Discipline` **odshora dolů jako cizí čtenář**, ne jako diff — přidaný odstavec vypadá v diffu správně i tam, kde stojí přímo pod větou, kterou vyvrací.

- [ ] **Step 13: Commit a publikace**

Použij skill `mb-git-commit` se scoped stagingem právě těchto dvou cest:

```bash
git add ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md ums/README.md
```

Zpráva (česky, prefix z `context.md`):

```text
UMS-3488: kontrakt 2.13 — výjimka poolu, per-worktree volnost slotu, validovaný Instruction
 - Worktree Policy: měření disku přepsáno na naměřených 70 %, výjimka pro uživatelem označený slot poolu, o IDLE rozhoduje výhradně pin
 - Workspace Discipline: derivace volnosti slotu jen z per-worktree signálů, živé sezení jako vlastní fail-closed signál, stash a cizí kandidát mimo volnost, ledger podle slugu z pinu
 - Session Intent Baton: Instruction povinný a validovaný proti seznamu skillů, baton je nosič záměru jen ve vlastním workspace
 - Repository Configuration: seznam odebíraných proměnných ani cesta ke claude.exe nejsou konfigurace repozitáře
 - Publication Contract: po switch -c následuje git branch --unset-upstream
```

Pak publikuj větev.

---

### Task 2: A1 + A2 čtenáře batonu a oprava overlay fragmentu

Verifikuje se **izolovaně**, dřív než se sáhne na skripty poolu. Oprava overlay fragmentu jde do **téhož** tasku jako A2: fragment `subagent-driven-development.overlay.md` `Instruction` ve svém výčtu klíčů nejmenuje, takže sezení jdoucí podle něj doslova by po zpřísnění napsalo baton, který hook zamítne jako stale — a pro **tento plán** je to akutní, protože se vykonává pod SDD a počítá s rotací kontextu na hranicích tasků.

**Files:**
- Modify: `ums/.claude/hooks/session-intent.ps1`
- Modify: `ums/.claude/hooks/tests/session-intent.tests.ps1`
- Modify: `ums/.claude/skills/shared/overlays/subagent-driven-development.overlay.md`
- Test: `ums/.claude/hooks/tests/session-intent.tests.ps1`

**Interfaces:**
- Consumes: kontraktový text z Tasku 1, kroky 6 a 7 (`Instruction` required + validated).
- Produces: čtenář batonu, na jehož zpřísněný formát spoléhá každá rotace kontextu při exekuci tohoto plánu. Konstanty, které smí číst jen tento soubor: `$MaxInstruction = 200`, `$SkillsDir`. Žádné rozhraní pro pozdější úlohy.

- [ ] **Step 1 (A1, BRÁNA): ověř `initialUserMessage` proti primárnímu zdroji, než napíšeš řádek kódu**

`initialUserMessage` je konfigurační klíč **cizího nástroje** (výstupní schéma hooků Claude Code), takže playbook žádá ověření proti primární dokumentaci PŘED implementací a citaci (URL + citovaná věta) přímo v kódu vedle zápisu, ne jen v reportu.

Stav při psaní tohoto plánu, ať ho neopakuješ zbytečně: `WebFetch` na `https://code.claude.com/docs/en/hooks` i na `…/hooks.md` vrátil obsah **uříznutý před** sekcí výstupů `SessionStart`, takže existenci klíče ani nepotvrdil, ani nevyvrátil; `WebSearch` naopak popsal `initialUserMessage` jako `SessionStart` výstup vedle `watchPaths` a `reloadSkills`. **To není důkaz.** Ověř sám:

```text
WebSearch: claude code hooks SessionStart hookSpecificOutput initialUserMessage
WebFetch:  https://code.claude.com/docs/llms.txt  → najdi URL stránky s referencí hooků
WebFetch:  <ta URL>  → prompt cílený na sekci výstupů SessionStart
```

Dvě konečné cesty, obě legální, žádná třetí:

- **Klíč existuje** → pokračuj kroky 2–4 (A1) i 5–10 (A2). Nad blok, který ho emituje, napiš dvouřádkový komentář s URL a citovanou větou.
- **Klíč neexistuje, nebo se ho nepodaří v dokumentaci najít** → **A1 se nestaví.** Zapiš do ledgeru `Ruling:` s tím, co jsi hledal a co našel, přeskoč kroky 2–4 i asercie A1 v kroku 8, a pokračuj rovnou A2. Pool na A1 nestojí (záměr do slotu jde argv, ne batonem), takže to úlohu nezastaví; do reportu úlohy to ale patří jmenovitě, protože je to odchylka od návrhu.

- [ ] **Step 2 (A1): napiš padající test na přítomnost `initialUserMessage` na happy path**

Do `ums/.claude/hooks/tests/session-intent.tests.ps1` přidej **na konec, těsně před `Complete-Tests`** — a předtím ověř dvojmo, co playbook žádá: (1) že `New-BatonFixture`, `Write-Baton`, `Write-Pin`, `New-ValidBatonBody`, `New-PlanFile` a `Invoke-Baton` jsou v tom bodě souboru už definované, a (2) že poslední `Remove-Item -Recurse -Force` nad sdílenou fixturou nestojí nad tvým místem. Když sdílená fixtura nevyhovuje, postav si vlastní přes `New-BatonFixture`.

```powershell
# --- A1: initialUserMessage on the happy path -------------------------------
$fx = New-BatonFixture 'a1-happy'
try {
    New-PlanFile $fx.Work
    Write-Pin $fx.Work 'x'
    Write-Baton $fx.Work (New-ValidBatonBody $fx.Work)
    $r = Invoke-Baton $fx.Work
    Assert-Eq $r.Code 0 'A1 happy path exits 0'
    Assert-Match $r.Out '"initialUserMessage"' 'A1 emits initialUserMessage next to additionalContext'
    Assert-Match $r.Out '"additionalContext"' 'A1 does not replace additionalContext'
    $json = $r.Out | ConvertFrom-Json
    Assert-Match $json.hookSpecificOutput.initialUserMessage 'bootstrap' 'initialUserMessage states the bootstrap checks come first'
    Assert-Match $json.hookSpecificOutput.initialUserMessage 'fail-closed' 'initialUserMessage states a baton never overrides a fail-closed gate'
}
finally { Remove-Item -Recurse -Force $fx.Root -ErrorAction SilentlyContinue }

# --- A1: silent on every stale path ----------------------------------------
$fx = New-BatonFixture 'a1-stale'
try {
    New-PlanFile $fx.Work
    Write-Pin $fx.Work 'x'
    # Wrong branch => stale; nothing may be emitted at all.
    Write-Baton $fx.Work ((New-ValidBatonBody $fx.Work) -replace 'Branch: baton-branch', 'Branch: some-other-branch')
    $r = Invoke-Baton $fx.Work
    Assert-Eq $r.Code 0 'A1 stale path still exits 0'
    Assert-Eq $r.Out '' 'A1 stale path emits nothing at all'
    Assert-NotMatch $r.Out 'initialUserMessage' 'A1 emits no initialUserMessage on the stale path'
    Assert-True (Test-Path -LiteralPath (Get-BatonPath $fx.Work 'session-intent.stale.md')) 'stale baton renamed'
}
finally { Remove-Item -Recurse -Force $fx.Root -ErrorAction SilentlyContinue }
```

- [ ] **Step 3 (A1): spusť sadu a potvrď, že nové asercie PADAJÍ**

```bash
pwsh -NoProfile -File ums/.claude/hooks/tests/session-intent.tests.ps1
```

Očekávané: `<N>/<M> FAILED`, mezi selhanými `A1 emits initialUserMessage next to additionalContext`. Případ „stale path emits nothing" projde už teď (dnešní hook na stale cestě nic neemituje) — to je **regresní zámek**, ne důkaz A1; v reportu ho tak označ.

- [ ] **Step 4 (A1): implementuj emisi**

V `ums/.claude/hooks/session-intent.ps1` nahraď blok stavějící `$payload` tímto (blok `$body` zůstává beze změny, `$payload` se rozšiřuje):

```powershell
    # Fixed English text, never derived from the baton: this string becomes the
    # session's first USER message, so nothing attacker-chosen may reach it.
    # Ordering is load-bearing — the bootstrap checks are a PRECONDITION of
    # acting on a baton, never the other way round (contract, "Session Intent
    # Baton", Precedence).
    #
    # Field verified against the Claude Code hooks reference: <URL>
    # "<quoted sentence naming initialUserMessage as a SessionStart output>"
    $firstMove = @(
        'A session intent baton from the previous session in this workspace has been delivered above.',
        'Run the bootstrap checks of the session-start context FIRST — the publication-guarantee self-check is a precondition, and a baton never overrides a fail-closed gate.',
        'Only then act on the baton''s Instruction line.'
    ) -join ' '

    $payload = [pscustomobject] @{
        hookSpecificOutput = [pscustomobject] @{
            hookEventName      = 'SessionStart'
            additionalContext  = $body
            initialUserMessage = $firstMove
        }
    }
```

`$firstMove` se staví **až v této větvi**, tedy jen tam, kde se baton skutečně emituje; každá stale i absentní cesta se vrací dřív a zůstává tichá.

- [ ] **Step 5 (A1): spusť sadu a potvrď, že asercie PROCHÁZÍ**

```bash
pwsh -NoProfile -File ums/.claude/hooks/tests/session-intent.tests.ps1
```

Očekávané: `<N> passed`, exit 0.

- [ ] **Step 6 (A2): napiš padající testy na povinný a validovaný `Instruction`**

Přidej na konec sady, před `Complete-Tests`:

```powershell
# --- A2: Instruction is required and validated ------------------------------
# The reader derives legal instruction words from the skill directories beside
# its own hooks directory, so the fixture must provide them.
function New-SkillDirs([string] $Work, [string[]] $Names) {
    $skills = Join-Path (Join-Path $Work '.claude') 'skills'
    foreach ($n in $Names) { New-Item -ItemType Directory -Force -Path (Join-Path $skills $n) | Out-Null }
    return $skills
}

# a) missing Instruction => stale
$fx = New-BatonFixture 'a2-missing'
try {
    New-PlanFile $fx.Work; Write-Pin $fx.Work 'x'
    $body = (New-ValidBatonBody $fx.Work) -replace '(?m)^Instruction:.*$', ''
    Write-Baton $fx.Work $body
    $r = Invoke-Baton $fx.Work
    Assert-Eq $r.Out '' 'A2 baton without Instruction emits nothing'
    Assert-True (Test-Path -LiteralPath (Get-BatonPath $fx.Work 'session-intent.stale.md')) 'A2 baton without Instruction is stale'
}
finally { Remove-Item -Recurse -Force $fx.Root -ErrorAction SilentlyContinue }

# b) Instruction naming no existing skill => stale
$fx = New-BatonFixture 'a2-noskill'
try {
    New-PlanFile $fx.Work; Write-Pin $fx.Work 'x'
    New-SkillDirs $fx.Work @('subagent-driven-development', 'mb-harvest') | Out-Null
    $body = (New-ValidBatonBody $fx.Work) -replace '(?m)^Instruction:.*$', 'Instruction: Do whatever you feel like doing right now.'
    Write-Baton $fx.Work $body
    $r = Invoke-Baton $fx.Work
    Assert-Eq $r.Out '' 'A2 Instruction naming no skill emits nothing'
    Assert-True (Test-Path -LiteralPath (Get-BatonPath $fx.Work 'session-intent.stale.md')) 'A2 Instruction naming no skill is stale'
}
finally { Remove-Item -Recurse -Force $fx.Root -ErrorAction SilentlyContinue }

# c) Instruction over the length ceiling => stale (even though it names a skill)
$fx = New-BatonFixture 'a2-long'
try {
    New-PlanFile $fx.Work; Write-Pin $fx.Work 'x'
    New-SkillDirs $fx.Work @('subagent-driven-development') | Out-Null
    $long = 'Invoke the subagent-driven-development skill. ' + ('x' * 300)
    $body = (New-ValidBatonBody $fx.Work) -replace '(?m)^Instruction:.*$', "Instruction: $long"
    Write-Baton $fx.Work $body
    $r = Invoke-Baton $fx.Work
    Assert-Eq $r.Out '' 'A2 over-long Instruction emits nothing'
    Assert-True (Test-Path -LiteralPath (Get-BatonPath $fx.Work 'session-intent.stale.md')) 'A2 over-long Instruction is stale'
}
finally { Remove-Item -Recurse -Force $fx.Root -ErrorAction SilentlyContinue }

# d) empty skill list => every Instruction unmatchable => stale (fail-closed)
$fx = New-BatonFixture 'a2-noskillsdir'
try {
    New-PlanFile $fx.Work; Write-Pin $fx.Work 'x'
    Write-Baton $fx.Work (New-ValidBatonBody $fx.Work)   # no .claude/skills at all
    $r = Invoke-Baton $fx.Work
    Assert-Eq $r.Out '' 'A2 unreadable skill list is fail-closed'
    Assert-True (Test-Path -LiteralPath (Get-BatonPath $fx.Work 'session-intent.stale.md')) 'A2 unreadable skill list makes the baton stale'
}
finally { Remove-Item -Recurse -Force $fx.Root -ErrorAction SilentlyContinue }

# e) POSITIVE control: a valid Instruction naming an existing skill still passes,
#    for BOTH kinds — without this the four cases above are satisfied by a
#    reader that rejects everything.
foreach ($kind in @('plan-execution', 'plan-resume')) {
    $fx = New-BatonFixture "a2-ok-$kind"
    try {
        New-PlanFile $fx.Work; Write-Pin $fx.Work 'x'
        New-SkillDirs $fx.Work @('subagent-driven-development') | Out-Null
        $body = (New-ValidBatonBody $fx.Work) -replace 'Kind: plan-execution', "Kind: $kind"
        Write-Baton $fx.Work $body
        $r = Invoke-Baton $fx.Work
        Assert-Match $r.Out '<session-intent' "A2 valid Instruction still delivered for $kind"
        Assert-Match $r.Out 'Instruction: Invoke the subagent-driven-development skill' "A2 Instruction rendered for $kind"
        Assert-True (Test-Path -LiteralPath (Get-BatonPath $fx.Work 'session-intent.consumed.md')) "A2 valid baton consumed for $kind"
    }
    finally { Remove-Item -Recurse -Force $fx.Root -ErrorAction SilentlyContinue }
}
```

- [ ] **Step 7 (A2): spusť sadu a potvrď, které asercie padají**

```bash
pwsh -NoProfile -File ums/.claude/hooks/tests/session-intent.tests.ps1
```

Očekávané: padají případy a), b), c), d); případ e) prochází už teď (dnešní hook validní baton doručí) — **regresní zámek**, ne důkaz A2. Případ a) může projít nebo padnout podle toho, jestli `New-ValidBatonBody` po odstranění řádku nechá prázdný řádek: prázdné řádky parser přeskakuje, takže baton bez `Instruction` je dnes **platný a doručený**, tedy asercie musí padnout. Pokud neplatí, čti skutečný výstup a oprav fixturu, ne asercii.

- [ ] **Step 8 (A2): implementuj validaci**

V `ums/.claude/hooks/session-intent.ps1`:

1. Rozšiř konstanty pod `$MaxBytes`:

```powershell
$MaxBytes = 8192
# Instruction becomes an automatically executed first move (see the payload at
# the bottom), so its value is bounded twice: it must NAME a skill that exists
# in this deployment, and it must be short. 200 characters is roughly three
# times the canonical instruction and leaves no room for a payload.
$MaxInstruction = 200
$Required = @('Kind', 'Plan', 'Branch', 'Slug', 'Instruction')
```

2. Za blok kontrolující `$Required` a `$KindValues` vlož validaci hodnoty:

```powershell
    # Instruction validation. The legal words are the skill directory names of
    # THIS deployment, taken from the skills directory beside this hook's own
    # directory ($PSScriptRoot is <deployment>/hooks, skills are its sibling).
    # An empty or unreadable list matches nothing and the baton goes stale —
    # deliberately fail-closed: the documented fallback for a lost baton is the
    # operator typing the intent, so the cost of being wrong this way is zero,
    # while the cost the other way is up to $MaxBytes of arbitrary text handed
    # over as the session's first user message.
    $instruction = $fields['Instruction']
    if ($instruction.Length -gt $MaxInstruction) {
        Move-Aside $batonPath 'session-intent.stale.md'
        exit 0
    }
    $skillNames = @()
    try {
        $skillsDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'skills'
        if (Test-Path -LiteralPath $skillsDir -PathType Container) {
            $skillNames = @(Get-ChildItem -LiteralPath $skillsDir -Directory -ErrorAction Stop |
                ForEach-Object { $_.Name })
        }
    }
    catch { $skillNames = @() }
    # -cmatch, never -match: skill names are lower-case path names and the
    # comparison must not accept a differently-cased near-miss, the same reason
    # the branch and slug guards below are case-sensitive.
    $namesASkill = $false
    foreach ($n in $skillNames) {
        if ($instruction -cmatch [regex]::Escape($n)) { $namesASkill = $true; break }
    }
    if (-not $namesASkill) {
        Move-Aside $batonPath 'session-intent.stale.md'
        exit 0
    }
```

Umísti blok **za** kontrolu `$KindValues` a **před** kontrolu existence `Plan` — validace tvaru předchází sáhnutí na filesystem cíle.

- [ ] **Step 9 (A2): spusť sadu a potvrď zeleň**

```bash
pwsh -NoProfile -File ums/.claude/hooks/tests/session-intent.tests.ps1
```

Očekávané: `<N> passed`, exit 0. Zapiš přesné `<N>` do ledgeru — je to baseline pro deltu v Tasku 10.

- [ ] **Step 10 (A2): negativita nové validace**

Ověř, že nové asercie skutečně něco hlídají, ne že jsou zámek. Postup, doslova:

```bash
cp ums/.claude/hooks/session-intent.ps1 /tmp/si-backup.ps1
sha256sum ums/.claude/hooks/session-intent.ps1 > /tmp/si-hash.txt
```

Pak proveď **dvě samostatné mutace**, po každé spusť sadu a soubor obnov:

1. `$Required` vrať na `@('Kind', 'Plan', 'Branch', 'Slug')` → očekávaně zčervená případ a). Případy b)–d) mohou zůstat zeleně, pokud je zamítne validace hodnoty dřív — to je **očekávaná odchylka**, ne rozbitý test; zapiš ji.
2. Záměna `-cmatch` za `-match` v cyklu nad `$skillNames` → sama o sobě neprokáže nic, protože žádný testovací případ se neliší jen velikostí písmen. **Přidej proto vyhrazený případ**, jehož dvě hodnoty se liší JEN case (`Instruction: Invoke the Subagent-Driven-Development skill …` proti adresáři `subagent-driven-development`), a znovu změř — bez něj `-cmatch` nic nehlídá.

Obnovu po každé mutaci doluž:

```bash
cp /tmp/si-backup.ps1 ums/.claude/hooks/session-intent.ps1
sha256sum -c /tmp/si-hash.txt && cmp /tmp/si-backup.ps1 ums/.claude/hooks/session-intent.ps1 && echo RESTORED
```

Výsledek rozděl do tří kategorií — **zčervenalo** / **regresní zámek** / **NEPROVEDENO** (vše za případným bodem přerušení, vyčteným z transkriptu, ne odhadem).

- [ ] **Step 11: oprav overlay fragment `subagent-driven-development`**

V `ums/.claude/skills/shared/overlays/subagent-driven-development.overlay.md`, na řádku 37, výčet klíčů batonu `Instruction` nejmenuje. Nahraď větu:

```markdown
  At that boundary, when the remaining context looks insufficient for another
  task: write the session intent baton (contract, "Session Intent Baton") with
  `Kind: plan-resume`, the plan path, the ledger path, the branch, the slug, the
  number of the next incomplete task and the required `Instruction:` line naming
  subagent-driven-development; append a plain note to the ledger that the session
  was rotated here (a note, NOT a `Ruling:` — no conflict was decided); report in
  Czech; and stop with the single instruction to type `/clear`.

  **`Instruction` is REQUIRED and its value is VALIDATED** (contract, same
  subsection): the reader accepts it only when it names a skill that exists in
  this deployment and stays under a short length ceiling. A baton written
  without it — or with a value that names no skill — is rejected as stale and
  the handoff is silently lost.
```

Pak grepni **oba** fragmenty, které baton píší, jestli výčet klíčů někde jinde nezůstal neúplný:

```bash
grep -n 'Kind: plan-\|Instruction' ums/.claude/skills/shared/overlays/subagent-driven-development.overlay.md ums/.claude/skills/shared/overlays/writing-plans.overlay.md
```

`writing-plans.overlay.md` `Instruction` už jmenuje (řádek 27) — potvrď to, neopravuj naslepo.

- [ ] **Step 12: obnov nasazenou kopii a ověř ji**

Změnil se hook, tedy soubor, který **toto sezení** používá:

```bash
cp -r ums/.claude/hooks/. .claude/hooks/
diff -rq ums/.claude/hooks .claude/hooks
```

Očekávané: `diff` prázdný. (Overlay fragment se nasazuje revendorem — ten je až v Tasku 10, protože do té doby se fragment může ještě změnit.)

- [ ] **Step 13: Commit a publikace**

```bash
git add ums/.claude/hooks/session-intent.ps1 ums/.claude/hooks/tests/session-intent.tests.ps1 ums/.claude/skills/shared/overlays/subagent-driven-development.overlay.md
```

```text
UMS-3488: baton — Instruction povinný a validovaný, initialUserMessage, oprava overlay fragmentu
 - A2: Instruction přibyl do povinných klíčů; hodnota musí jmenovat existující skill (odvozeno z adresářů vedle hooku, case-sensitive) a nepřesáhnout 200 znaků, jinak je baton stale
 - prázdný nebo nečitelný seznam skillů je fail-closed — každý Instruction je nedohledatelný a baton stale
 - A1: hook emituje initialUserMessage vedle additionalContext s pevným anglickým textem o přednosti bootstrap kontrol; stale i absentní cesty zůstávají tiché
 - overlay subagent-driven-development jmenuje Instruction ve výčtu klíčů páté stop třídy, aby rotace kontextu tohoto plánu nepsala stale batony
```

Pokud krok 1 rozhodl, že se A1 nestaví, vypusť z zprávy oba řádky o A1 a doplň řádek o tom, že klíč nešlo ověřit proti primárnímu zdroji.

Pak publikuj větev.

---

### Task 3: `pool-status.ps1` — derivace stavu slotu

Jediný zdroj pravdy o tom, co je slot a kdy je volný. Skript je **anglický vývojářský nástroj**: tiskne anglický přehled a volitelně JSON; českou tabulku renderuje až skill v Tasku 6.

**Files:**
- Create: `ums/.claude/skills/mb-epic-run/scripts/pool-status.ps1`
- Create: `ums/.claude/skills/mb-epic-run/tests/_assert.ps1`
- Create: `ums/.claude/skills/mb-epic-run/tests/new-pool-fixture.ps1`
- Create: `ums/.claude/skills/mb-epic-run/tests/pool-status.tests.ps1`
- Create: `ums/.claude/skills/mb-epic-run/tests/stubs/claude-stub.ps1`

**Interfaces:**
- Consumes: kontraktovou derivaci volnosti z Tasku 1, krok 4 (tabulka signálů, fail-closed obsazenost, ledger podle slugu z pinu).
- Produces:
  - Skript `pool-status.ps1` s parametry `-RepoPath <string>`, `-Epic <string>`, `-Json <string>`, `-ClaudeCommand <string>`.
  - Exit kódy: `0` OK · `1` vstupní/skriptové selhání · `3` **repozitář nemá pool** (žádný označený linked worktree).
  - JSON kontrakt, který konzumuje Task 6 (skill) a Task 4 nepřímo (volba slotu). Tvar je závazný:

```json
{
  "repoRoot": "D:/_datasys/ums",
  "generatedAt": "2026-09-03T10:00:00Z",
  "occupancySource": "claude",
  "stashCount": 2,
  "slots": [
    {
      "path": "D:/_datasys/ums01",
      "name": "ums01",
      "branch": "SKODASMS-251-regexovy-pool-bota",
      "detached": false,
      "head": "0123456789abcdef0123456789abcdef01234567",
      "dirtyCount": 34,
      "unpushedCount": 0,
      "unpushedSource": "upstream",
      "pin": { "targetMb": "memory-bank/", "slug": "skodasms_251_regexovy_pool_bota", "jira": "SKODASMS-251" },
      "progress": { "path": ".superpowers/sdd/plan_skodasms_251_regexovy_pool_bota/progress.md", "exists": true, "lines": 42, "lastLine": "Task 3 complete." },
      "session": { "state": "live", "pids": [29404] },
      "free": false,
      "reasons": ["dirty tree (34 entries)", "live session (pid 29404)", "ACTIVE pin: skodasms_251_regexovy_pool_bota"]
    }
  ],
  "excluded": [ { "path": "D:/_datasys/ums05", "reason": "no pool-slot marker" } ],
  "stash": ["stash@{0}: WIP on develop"]
}
```

  - `session.state` je právě jedno z `live` / `none` / `unknown`; `unknown` je **fail-closed** a Task 6 na něj spawn nepustí.
  - `pin` je `null` právě tehdy, když je slot IDLE; `progress` je `null`, když slot nenese pin.
  - `free` je `true` právě tehdy, když je `reasons` prázdné.

- [ ] **Step 1: Zkopíruj aserční helper a napiš builder fixtury**

`_assert.ps1` musí mít vlastní kopii každý adresář testů, protože nasazení kopíruje celé adresáře skillů. Vezmi kopii z `ums/.claude/skills/mb-epic-elaboration/tests/_assert.ps1`, zahoď z ní `Invoke-Ledger` a doplň runner tohoto skriptu:

```powershell
# Dependency-free assertion helper for mb-epic-run tests.
Set-StrictMode -Version Latest
$script:Failures = 0
$script:Total = 0
function Assert-True([bool] $cond, [string] $msg) {
    $script:Total++
    if ($cond) { Write-Host "  ok  : $msg" } else { Write-Host "  FAIL: $msg"; $script:Failures++ }
}
function Assert-Match([string] $text, [string] $pattern, [string] $msg) {
    Assert-True ([bool]([regex]::IsMatch($text, $pattern))) "$msg  [/$pattern/]"
}
function Assert-NotMatch([string] $text, [string] $pattern, [string] $msg) {
    Assert-True (-not [regex]::IsMatch($text, $pattern)) "$msg  [must NOT match /$pattern/]"
}
function Assert-Eq($actual, $expected, [string] $msg) {
    Assert-True ($actual -eq $expected) "$msg  (got '$actual', want '$expected')"
}
function Complete-Tests {
    Write-Host ""
    if ($script:Failures -gt 0) { Write-Host "$script:Failures/$script:Total FAILED"; exit 1 }
    Write-Host "$script:Total passed"; exit 0
}

# Runs a pool script out-of-process; returns @{ Out=<stdout>; Code=<exit code> }.
function Invoke-PoolScript([string] $Name, [string[]] $ScriptArgs) {
    $script = Join-Path $PSScriptRoot "..\scripts\$Name"
    try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
    $out = & pwsh -NoProfile -File $script @ScriptArgs 2>&1 | Out-String
    return @{ Out = $out; Code = $LASTEXITCODE }
}
```

Builder fixtury `new-pool-fixture.ps1` staví **skutečné** linked worktrees se sdíleným `.git` — simulace by nedokázala nic o tom, co je a co není per-worktree. Poznámka k `Out-Null`: každé volání gitu uvnitř funkce, jehož výstup se nepřiřazuje, se zahazuje, jinak se přilepí k návratové hodnotě.

```powershell
#Requires -Version 7
<#
.SYNOPSIS
Builds a throwaway repository with a bare "origin", a main clone and N REAL
linked worktrees sharing one .git — the only shape in which the per-worktree
question this suite exists to answer can be asked at all.

.OUTPUTS
Hashtable: Root, Origin, Main, Slots (ordered array of worktree paths).
#>
[CmdletBinding()]
param(
    [int] $SlotCount = 3,
    [string] $Label = 'pool'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-FixtureGit([string] $Dir, [string[]] $GitArgs) {
    $out = & git -C $Dir @GitArgs 2>&1
    if ($LASTEXITCODE -ne 0) { throw "git $($GitArgs -join ' ') in $Dir failed: $out" }
    return $out
}

$root = Join-Path ([IO.Path]::GetTempPath()) ("mbpool-$Label-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$origin = Join-Path $root 'origin.git'
$main = Join-Path $root 'main'
New-Item -ItemType Directory -Force -Path $root | Out-Null

& git init -q --bare -b develop $origin | Out-Null
& git clone -q $origin $main | Out-Null
Invoke-FixtureGit $main @('config', 'user.email', 'test@example.invalid') | Out-Null
Invoke-FixtureGit $main @('config', 'user.name', 'Test') | Out-Null
'base' | Out-File -FilePath (Join-Path $main 'f.txt') -Encoding utf8
Invoke-FixtureGit $main @('add', '-A') | Out-Null
Invoke-FixtureGit $main @('commit', '-m', 'base') | Out-Null
Invoke-FixtureGit $main @('push', '-u', 'origin', 'develop') | Out-Null

$slots = @()
for ($i = 1; $i -le $SlotCount; $i++) {
    $name = 'slot{0:d2}' -f $i
    $path = Join-Path $root $name
    Invoke-FixtureGit $main @('worktree', 'add', '--detach', $path, 'origin/develop') | Out-Null
    $slots += $path
}

return @{ Root = $root; Origin = $origin; Main = $main; Slots = $slots }
```

Helpery, které sada nad fixturou používá (dej je do `_assert.ps1`, aby je viděly všechny tři sady tohoto adresáře):

```powershell
function Set-SlotMarker([string] $Slot) {
    $dir = Join-Path $Slot '.superpowers'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    Set-Content -LiteralPath (Join-Path $dir 'pool-slot') -Value '' -Encoding utf8
}
function Set-SlotPin([string] $Slot, [string] $Slug, [string] $Jira = 'UMS-0000') {
    $mb = Join-Path $Slot 'memory-bank'
    New-Item -ItemType Directory -Force -Path $mb | Out-Null
    $text = "# Context`n`n## Active Work`n`n- **Jira:** $Jira`n- **Target MB Pin:** memory-bank/`n- **Work item:** $Slug`n"
    Set-Content -LiteralPath (Join-Path $mb 'context.md') -Value $text -Encoding utf8
}
function Set-SlotIdle([string] $Slot) {
    $mb = Join-Path $Slot 'memory-bank'
    New-Item -ItemType Directory -Force -Path $mb | Out-Null
    Set-Content -LiteralPath (Join-Path $mb 'context.md') `
        -Value "# Context`n`n## Active Work`n`n(No active work - IDLE phase)`n" -Encoding utf8
}
function New-SlotLedger([string] $Slot, [string] $PlanBase, [string] $LastLine) {
    $dir = Join-Path (Join-Path (Join-Path $Slot '.superpowers') 'sdd') $PlanBase
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    Set-Content -LiteralPath (Join-Path $dir 'progress.md') -Value "# progress`n`n$LastLine`n" -Encoding utf8
}
```

Stub harnessu `tests/stubs/claude-stub.ps1` — kanonizovaná odpověď `claude agents --json --cwd <slot>`; chování řídí proměnná prostředí, aby jeden stub obsloužil všechny tři případy obsazenosti:

```powershell
#Requires -Version 7
# Test seam for `claude agents --json --cwd <path>`. MBPOOL_STUB_MODE selects:
#   live    -> one record WITH a pid           (slot occupied)
#   nopid   -> one record WITHOUT a pid        (finished background session; ignored)
#   empty   -> empty array                     (slot free)
#   garbage -> unparseable output              (occupancy unknown, fail-closed)
param([Parameter(ValueFromRemainingArguments = $true)] $Rest)
switch ($env:MBPOOL_STUB_MODE) {
    'live'    { Write-Output '[{"name":"UMS-0000","pid":29404,"state":"idle"}]'; exit 0 }
    'nopid'   { Write-Output '[{"name":"UMS-0000","state":"exited"}]';           exit 0 }
    'garbage' { Write-Output 'not json at all';                                  exit 0 }
    default   { Write-Output '[]';                                               exit 0 }
}
```

- [ ] **Step 2: Napiš padající sadu `pool-status.tests.ps1`**

Sada pokrývá verifikační body 2, 3, 4, 5 a 15 návrhu. Dva z nich jsou **regresní důkazy s vyžádanou negativitou**: s kontraktovou trojicí signálů (`status` + `stash list` + `log --branches --not --remotes`) musí zčervenat.

```powershell
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '_assert.ps1')
$ErrorActionPreference = 'Stop'
$NewFixture = Join-Path $PSScriptRoot 'new-pool-fixture.ps1'
$Stub = Join-Path $PSScriptRoot 'stubs\claude-stub.ps1'

function Invoke-Status([string] $Repo, [string[]] $Extra = @()) {
    $json = Join-Path ([IO.Path]::GetTempPath()) ('mbpool-' + [guid]::NewGuid().ToString('N') + '.json')
    $a = @('-RepoPath', $Repo, '-Json', $json, '-ClaudeCommand', $Stub) + $Extra
    $r = Invoke-PoolScript 'pool-status.ps1' $a
    $data = $null
    if (Test-Path -LiteralPath $json) { $data = Get-Content -LiteralPath $json -Raw | ConvertFrom-Json }
    Remove-Item -LiteralPath $json -Force -ErrorAction SilentlyContinue
    return @{ Out = $r.Out; Code = $r.Code; Data = $data }
}
function Get-Slot($Data, [string] $Name) {
    return @($Data.slots | Where-Object { $_.name -eq $Name }) | Select-Object -First 1
}

# --- case 1: no marked worktree => the repository has no pool (exit 3) -------
# This is the state of the superpowers fork itself (zero linked worktrees), so
# the path has to be proven, not assumed.
$env:MBPOOL_STUB_MODE = 'empty'
$fx = & $NewFixture -SlotCount 2 -Label 'nopool'
try {
    $r = Invoke-Status $fx.Main
    Assert-Eq $r.Code 3 'repository without a marked worktree exits 3'
    Assert-Match $r.Out 'no pool' 'exit 3 says the repository has no pool'
    Assert-Eq @($r.Data.slots).Count 0 'no slots reported'
    Assert-True (@($r.Data.excluded | Where-Object { $_.reason -match 'marker' }).Count -ge 2) 'unmarked worktrees are excluded with a named reason'
}
finally { Remove-Item -Recurse -Force $fx.Root -ErrorAction SilentlyContinue }

# --- case 2: marker decides membership --------------------------------------
$fx = & $NewFixture -SlotCount 2 -Label 'marker'
try {
    Set-SlotMarker $fx.Slots[0]
    Set-SlotIdle $fx.Slots[0]
    $r = Invoke-Status $fx.Main
    Assert-Eq $r.Code 0 'a marked worktree makes a pool'
    Assert-Eq @($r.Data.slots).Count 1 'only the marked worktree is a slot'
    Assert-Eq (Get-Slot $r.Data 'slot01').free $true 'clean marked IDLE slot is free'
    Assert-NotMatch (($r.Data.slots | ForEach-Object { $_.name }) -join ',') 'slot02' 'the unmarked worktree is not a slot'
}
finally { Remove-Item -Recurse -Force $fx.Root -ErrorAction SilentlyContinue }

# --- case 3: REGRESSION PROOF — a stash in one worktree must not unfree another
# refs/stash is SHARED across a pool, so `git stash list` answers identically
# from every slot. With the contract's original three-signal derivation this
# case goes red; that is the negativity this assertion exists for.
$fx = & $NewFixture -SlotCount 2 -Label 'stash'
try {
    foreach ($s in $fx.Slots) { Set-SlotMarker $s; Set-SlotIdle $s }
    'dirty' | Out-File -FilePath (Join-Path $fx.Slots[0] 'f.txt') -Encoding utf8
    & git -C $fx.Slots[0] stash push -u -m 'fixture stash' 2>&1 | Out-Null
    $r = Invoke-Status $fx.Main
    Assert-Eq (Get-Slot $r.Data 'slot02').free $true 'a stash created in slot01 does NOT make slot02 unfree'
    Assert-True (@($r.Data.stash).Count -ge 1) 'the stash is still reported, once per repository'
    Assert-NotMatch (((Get-Slot $r.Data 'slot02').reasons -join ' ')) 'stash' 'stash is not a reason attached to a slot'
}
finally { Remove-Item -Recurse -Force $fx.Root -ErrorAction SilentlyContinue }

# --- case 4: REGRESSION PROOF — an unpushed commit on branch A must not
# unfree a slot standing on branch B. `--branches` is repo-wide by
# construction; one unpushed commit anywhere would freeze the whole pool.
$fx = & $NewFixture -SlotCount 2 -Label 'unpushed'
try {
    foreach ($s in $fx.Slots) { Set-SlotMarker $s; Set-SlotIdle $s }
    & git -C $fx.Slots[0] switch -q -c branch-a 2>&1 | Out-Null
    'a' | Out-File -FilePath (Join-Path $fx.Slots[0] 'a.txt') -Encoding utf8
    & git -C $fx.Slots[0] add -A 2>&1 | Out-Null
    & git -C $fx.Slots[0] commit -q -m 'unpushed on A' 2>&1 | Out-Null
    & git -C $fx.Slots[1] switch -q -c branch-b 2>&1 | Out-Null
    $r = Invoke-Status $fx.Main
    Assert-Eq (Get-Slot $r.Data 'slot02').free $true 'an unpushed commit on branch-a does NOT unfree the slot on branch-b'
    Assert-True ((Get-Slot $r.Data 'slot01').unpushedCount -ge 1) 'the slot that owns the unpushed commit reports it'
    Assert-Eq (Get-Slot $r.Data 'slot01').free $false 'the owning slot is not free'
}
finally { Remove-Item -Recurse -Force $fx.Root -ErrorAction SilentlyContinue }

# --- case 5: occupancy, three states, fail-closed ---------------------------
$fx = & $NewFixture -SlotCount 1 -Label 'occupancy'
try {
    Set-SlotMarker $fx.Slots[0]; Set-SlotIdle $fx.Slots[0]

    $env:MBPOOL_STUB_MODE = 'live'
    $r = Invoke-Status $fx.Main
    Assert-Eq (Get-Slot $r.Data 'slot01').session.state 'live' 'a record WITH a pid means the slot is occupied'
    Assert-Eq (Get-Slot $r.Data 'slot01').free $false 'an occupied slot is not free'

    $env:MBPOOL_STUB_MODE = 'nopid'
    $r = Invoke-Status $fx.Main
    Assert-Eq (Get-Slot $r.Data 'slot01').session.state 'none' 'a record WITHOUT a pid is ignored'
    Assert-Eq (Get-Slot $r.Data 'slot01').free $true 'a slot with only pid-less records is free'

    $env:MBPOOL_STUB_MODE = 'garbage'
    $r = Invoke-Status $fx.Main
    Assert-Eq (Get-Slot $r.Data 'slot01').session.state 'unknown' 'unparseable output means UNKNOWN, never "free"'
    Assert-Eq (Get-Slot $r.Data 'slot01').free $false 'occupancy unknown is fail-closed: the slot is not free'

    $env:MBPOOL_STUB_MODE = 'empty'
    $r = Invoke-Status $fx.Main
    Assert-Eq (Get-Slot $r.Data 'slot01').session.state 'none' 'an empty record list means no session'
}
finally {
    $env:MBPOOL_STUB_MODE = 'empty'
    Remove-Item -Recurse -Force $fx.Root -ErrorAction SilentlyContinue
}

# --- case 6: the ledger is paired to the slug FROM THE PIN ------------------
# A slot carrying two sdd directories, the foreign one sorting first.
$fx = & $NewFixture -SlotCount 1 -Label 'ledger'
try {
    Set-SlotMarker $fx.Slots[0]
    Set-SlotPin $fx.Slots[0] 'zulu_current_work'
    New-SlotLedger $fx.Slots[0] 'plan_alpha_leftover' 'Task 9 of the WRONG plan.'
    New-SlotLedger $fx.Slots[0] 'plan_zulu_current_work' 'Task 2 of the right plan.'
    $r = Invoke-Status $fx.Main
    $s = Get-Slot $r.Data 'slot01'
    Assert-Match $s.progress.path 'plan_zulu_current_work' 'progress comes from the slug the PIN names'
    Assert-NotMatch $s.progress.path 'plan_alpha_leftover' 'the alphabetically first, foreign ledger is not reported'
    Assert-Match $s.progress.lastLine 'right plan' 'the reported line comes from the right ledger'
}
finally { Remove-Item -Recurse -Force $fx.Root -ErrorAction SilentlyContinue }

# --- case 7: a FOREIGN playbook candidate leaves the slot free --------------
# It is only defined against the CURRENT slug; an IDLE slot has none, so every
# candidate in it is foreign, and a foreign candidate is "merely present".
$fx = & $NewFixture -SlotCount 1 -Label 'candidate'
try {
    Set-SlotMarker $fx.Slots[0]; Set-SlotIdle $fx.Slots[0]
    $cand = Join-Path (Join-Path $fx.Slots[0] '.superpowers') 'playbook-candidates'
    New-Item -ItemType Directory -Force -Path $cand | Out-Null
    Set-Content -LiteralPath (Join-Path $cand 'someone_elses_slug.md') -Value '# Playbook candidates' -Encoding utf8
    $r = Invoke-Status $fx.Main
    Assert-Eq (Get-Slot $r.Data 'slot01').free $true 'a foreign playbook candidate does NOT unfree an IDLE slot'
}
finally { Remove-Item -Recurse -Force $fx.Root -ErrorAction SilentlyContinue }

# --- case 8: an ACTIVE pin is not free, and a branch NAME never decides IDLE -
$fx = & $NewFixture -SlotCount 1 -Label 'pin'
try {
    Set-SlotMarker $fx.Slots[0]
    # The slot stands on a branch named after its own directory AND carries an
    # ACTIVE pin — measured shape; the branch name must not win.
    & git -C $fx.Slots[0] switch -q -c slot01 2>&1 | Out-Null
    Set-SlotPin $fx.Slots[0] 'ums_3485_vyhodnoceni'
    $r = Invoke-Status $fx.Main
    $s = Get-Slot $r.Data 'slot01'
    Assert-Eq $s.free $false 'an eponymous branch does NOT make a pinned slot idle'
    Assert-Match ($s.reasons -join ' ') 'ACTIVE pin' 'the reason names the pin, not the branch'
    Assert-Eq $s.pin.slug 'ums_3485_vyhodnoceni' 'the pin slug is reported'
}
finally { Remove-Item -Recurse -Force $fx.Root -ErrorAction SilentlyContinue }

# --- case 9: locked and prunable worktrees are excluded with a named reason --
$fx = & $NewFixture -SlotCount 2 -Label 'locked'
try {
    foreach ($s in $fx.Slots) { Set-SlotMarker $s; Set-SlotIdle $s }
    & git -C $fx.Main worktree lock --reason 'held by the operator' $fx.Slots[1] 2>&1 | Out-Null
    $r = Invoke-Status $fx.Main
    Assert-Eq @($r.Data.slots).Count 1 'a locked worktree is not a candidate'
    Assert-Match (($r.Data.excluded | ForEach-Object { $_.reason }) -join ' ') 'locked' 'the exclusion names locked'
}
finally {
    & git -C $fx.Main worktree unlock $fx.Slots[1] 2>&1 | Out-Null
    Remove-Item -Recurse -Force $fx.Root -ErrorAction SilentlyContinue
}

Complete-Tests
```

- [ ] **Step 3: Spusť sadu proti neexistujícímu skriptu a potvrď selhání**

```bash
pwsh -NoProfile -File ums/.claude/skills/mb-epic-run/tests/pool-status.tests.ps1
```

Očekávané: sada spadne (skript neexistuje). To je výchozí červená; teprve implementace ji smí zezelenat.

- [ ] **Step 4: Implementuj `pool-status.ps1`**

```powershell
#Requires -Version 7
<#
.SYNOPSIS
Derives the state of the pool slots of this repository. Read-only; the only
write is the optional -Json file.

.DESCRIPTION
Membership of the pool is DERIVED, never configured: candidates come from one
read of `git worktree list --porcelain` (linked, non-bare, not the primary
worktree, not the one this script was pointed at), and a candidate becomes a
slot only when it carries the marker file .superpowers/pool-slot.

Freedom is derived from PER-WORKTREE signals only. In a linked worktree just
HEAD and the index are per-worktree; refs/stash and refs/heads are SHARED, so
`git stash list` and `git log --branches --not --remotes` answer the same from
every slot and would freeze the whole pool over one stash or one unpushed
commit anywhere. See the contract, "A pool slot's freedom is derived from
per-worktree signals only".

Occupancy is read from the harness (`claude agents --json --cwd <slot>`), not
from git: a slot whose session has just started, before it reaches its pin
write, looks free to git for about a minute. The signal is fail-closed —
unreadable means UNKNOWN, and UNKNOWN is not free.

.PARAMETER RepoPath
Repository root. Defaults to the toplevel of the current directory.

.PARAMETER Epic
Optional epic key. When given, a slot holding a ticket branch of this epic is
reported as such and is not free for a spawn of that epic.

.PARAMETER Json
Optional path to also write the full state as JSON. The path is validated
BEFORE any work, never at write time: in a fresh worktree a missing
.superpowers/ is the normal state, and failing at the end would print a
healthy-looking report and then exit 1 with no file.

.PARAMETER ClaudeCommand
Harness executable used for the occupancy probe. Empty (the default) resolves
`claude` through Get-Command; tests point it at a stub. Never hardcode a path.

.OUTPUTS
English summary on stdout. Exit: 0 = OK, 1 = input/script failure,
3 = the repository has no pool (no marked worktree).
#>
[CmdletBinding()]
param(
    [string] $RepoPath = '',
    [string] $Epic = '',
    [string] $Json = '',
    [string] $ClaudeCommand = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }

# Never name a function `Git`: PowerShell command discovery prefers a function
# over an application, case-insensitively, so `& git ...` inside it would
# recurse until the stack overflows.
function Invoke-RepoGit([string] $Dir, [string[]] $GitArgs) {
    $out = & git -C $Dir @GitArgs 2>&1
    return @{ Out = @($out); Code = $LASTEXITCODE }
}

function ConvertTo-SlashPath([string] $Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    return ([IO.Path]::GetFullPath($Path)).Replace('\', '/').TrimEnd('/')
}

if ([string]::IsNullOrWhiteSpace($RepoPath)) {
    $top = & git rev-parse --show-toplevel 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($top)) {
        Write-Error 'Git repository not found. Memory Bank requires git.'
        exit 1
    }
    $RepoPath = ([string] $top).Trim()
}
if (-not (Test-Path -LiteralPath $RepoPath -PathType Container)) {
    Write-Error "Repository path does not exist: $RepoPath"; exit 1
}
# -Json is checked BEFORE any work, for the reason in the parameter help.
if ($Json) {
    $jsonDir = Split-Path -Parent ([IO.Path]::GetFullPath($Json))
    if (-not (Test-Path -LiteralPath $jsonDir -PathType Container)) {
        Write-Error "-Json target directory does not exist: $jsonDir"; exit 1
    }
}

$repoAbs = ConvertTo-SlashPath $RepoPath

# --- worktree enumeration ----------------------------------------------------
# The porcelain record carries more than a path and a branch, and the
# derivation has to survive all of it: `bare` is skipped, `locked` and
# `prunable` are NOT candidates and are reported with a named reason —
# a prunable worktree's directory is gone, so `git -C <path> status` could not
# even be run there.
$wtRes = Invoke-RepoGit $RepoPath @('worktree', 'list', '--porcelain')
if ($wtRes.Code -ne 0) { Write-Error "git worktree list failed: $($wtRes.Out -join "`n")"; exit 1 }

$records = @()
$cur = $null
foreach ($line in $wtRes.Out) {
    $text = [string] $line
    if ($text -match '^worktree (?<p>.+)$') {
        if ($null -ne $cur) { $records += $cur }
        $cur = @{ Path = $Matches['p']; Head = ''; Branch = ''; Detached = $false; Bare = $false; Locked = ''; Prunable = '' }
        continue
    }
    if ($null -eq $cur) { continue }
    if ($text -match '^HEAD (?<h>\S+)$')        { $cur.Head = $Matches['h']; continue }
    if ($text -match '^branch refs/heads/(?<b>.+)$') { $cur.Branch = $Matches['b']; continue }
    if ($text -eq 'detached')                   { $cur.Detached = $true; continue }
    if ($text -eq 'bare')                       { $cur.Bare = $true; continue }
    if ($text -match '^locked ?(?<r>.*)$')      { $cur.Locked = if ($Matches['r']) { $Matches['r'] } else { 'no reason given' }; continue }
    if ($text -match '^prunable ?(?<r>.*)$')    { $cur.Prunable = if ($Matches['r']) { $Matches['r'] } else { 'no reason given' }; continue }
}
if ($null -ne $cur) { $records += $cur }

# The FIRST porcelain record is always the main worktree; it is not a slot, and
# neither is the worktree this script was pointed at (the orchestrator's own).
$candidates = @()
$excluded = @()
for ($i = 0; $i -lt $records.Count; $i++) {
    $r = $records[$i]
    $abs = ConvertTo-SlashPath $r.Path
    if ($i -eq 0)   { $excluded += @{ path = $abs; reason = 'primary worktree' }; continue }
    if ($r.Bare)    { $excluded += @{ path = $abs; reason = 'bare worktree' }; continue }
    if ($abs -ceq $repoAbs) { $excluded += @{ path = $abs; reason = "the orchestrator's own worktree" }; continue }
    if ($r.Prunable) { $excluded += @{ path = $abs; reason = "prunable: $($r.Prunable)" }; continue }
    if ($r.Locked)   { $excluded += @{ path = $abs; reason = "locked: $($r.Locked)" }; continue }
    if (-not (Test-Path -LiteralPath (Join-Path (Join-Path $r.Path '.superpowers') 'pool-slot') -PathType Leaf)) {
        $excluded += @{ path = $abs; reason = 'no pool-slot marker' }; continue
    }
    $r.Abs = $abs
    $candidates += $r
}

# --- occupancy ---------------------------------------------------------------
$claude = $ClaudeCommand
if ([string]::IsNullOrWhiteSpace($claude)) {
    $cmd = Get-Command claude -ErrorAction SilentlyContinue
    if ($cmd) { $claude = $cmd.Source }
}
$occupancySource = if ($claude) { 'claude' } else { 'unavailable' }

function Get-SlotSession([string] $Claude, [string] $SlotPath) {
    # Returns @{ state = 'live'|'none'|'unknown'; pids = @() }. Fail-closed:
    # anything unreadable is 'unknown', which the caller must not treat as free.
    if (-not $Claude) { return @{ state = 'unknown'; pids = @() } }
    $raw = ''
    try { $raw = (& $Claude agents --json --cwd $SlotPath 2>&1 | Out-String) }
    catch { return @{ state = 'unknown'; pids = @() } }
    if ($LASTEXITCODE -ne 0) { return @{ state = 'unknown'; pids = @() } }
    if ([string]::IsNullOrWhiteSpace($raw)) { return @{ state = 'none'; pids = @() } }
    $parsed = $null
    try { $parsed = $raw | ConvertFrom-Json } catch { return @{ state = 'unknown'; pids = @() } }
    # A successful ConvertFrom-Json does NOT mean an object with properties:
    # root null, a scalar and an array all parse without error.
    if ($null -eq $parsed) { return @{ state = 'none'; pids = @() } }
    $items = @($parsed)
    if ($items.Count -eq 0) { return @{ state = 'none'; pids = @() } }
    $pids = @()
    foreach ($it in $items) {
        if ($it -isnot [System.Management.Automation.PSCustomObject]) { return @{ state = 'unknown'; pids = @() } }
        $names = @(@($it.PSObject.Properties) | ForEach-Object { $_.Name })
        if ($names -notcontains 'pid') { continue }
        if ($null -eq $it.pid -or [string]::IsNullOrWhiteSpace([string] $it.pid)) { continue }
        $pids += [int] $it.pid
    }
    if ($pids.Count -gt 0) { return @{ state = 'live'; pids = $pids } }
    return @{ state = 'none'; pids = @() }
}

# --- per-slot derivation -----------------------------------------------------
function Get-SlotPin([string] $SlotPath) {
    $ctx = Join-Path (Join-Path $SlotPath 'memory-bank') 'context.md'
    if (-not (Test-Path -LiteralPath $ctx -PathType Leaf)) { return $null }
    $text = ''
    try { $text = Get-Content -LiteralPath $ctx -Raw -Encoding utf8 } catch { return $null }
    if ($null -eq $text) { return $null }
    # ACTIVE is a state NAME, never a token in the file: the mechanical test is
    # whether the Active Work block carries a pin. `- **Proposal:**` is the
    # mandated legacy alias of `- **Work item:**`.
    $slug = [regex]::Match($text, '(?m)^\s*-\s+\*\*(?:Work item|Proposal):\*\*\s*(?<v>\S+)\s*$')
    $target = [regex]::Match($text, '(?m)^\s*-\s+\*\*Target MB Pin:\*\*\s*(?<v>\S+)\s*$')
    if (-not ($slug.Success -and $target.Success)) { return $null }
    $jira = [regex]::Match($text, '(?m)^\s*-\s+\*\*Jira:\*\*\s*(?<v>\S+)')
    return [pscustomobject] @{
        targetMb = $target.Groups['v'].Value
        slug     = $slug.Groups['v'].Value
        jira     = if ($jira.Success) { $jira.Groups['v'].Value } else { '' }
    }
}

function Get-SlotProgress([string] $SlotPath, [string] $Slug) {
    # Paired to the slug the PIN names, never to "the first directory found
    # under sdd/": a slot can carry the leftover ledger of earlier work, and a
    # leftover slug can sort first.
    if ([string]::IsNullOrWhiteSpace($Slug)) { return $null }
    $rel = ".superpowers/sdd/plan_$Slug/progress.md"
    $full = Join-Path $SlotPath ($rel -replace '/', [IO.Path]::DirectorySeparatorChar)
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
        return [pscustomobject] @{ path = $rel; exists = $false; lines = 0; lastLine = '' }
    }
    $lines = @(Get-Content -LiteralPath $full -Encoding utf8)
    $last = @($lines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Last 1)
    return [pscustomobject] @{
        path     = $rel
        exists   = $true
        lines    = $lines.Count
        lastLine = if ($last.Count -gt 0) { ([string] $last[0]).Trim() } else { '' }
    }
}

$slots = @()
foreach ($c in $candidates) {
    $reasons = @()

    $st = Invoke-RepoGit $c.Path @('status', '--porcelain')
    $dirty = if ($st.Code -eq 0) { @($st.Out | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count } else { -1 }
    if ($dirty -lt 0) { $reasons += 'status unreadable' } elseif ($dirty -gt 0) { $reasons += "dirty tree ($dirty entries)" }

    # Unpushed commits OF THIS SLOT. With an upstream the question is exact;
    # without one, `HEAD --not --remotes` is still per-worktree because HEAD is.
    $ups = Invoke-RepoGit $c.Path @('rev-parse', '--abbrev-ref', '@{upstream}')
    if ($ups.Code -eq 0) {
        $unpRes = Invoke-RepoGit $c.Path @('log', '--oneline', '@{upstream}..HEAD')
        $unpSource = 'upstream'
    } else {
        $unpRes = Invoke-RepoGit $c.Path @('log', '--oneline', 'HEAD', '--not', '--remotes')
        $unpSource = 'head-not-remotes'
    }
    $unpushed = if ($unpRes.Code -eq 0) { @($unpRes.Out | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count } else { -1 }
    if ($unpushed -lt 0) { $reasons += 'unpushed count unreadable' } elseif ($unpushed -gt 0) { $reasons += "unpushed commits ($unpushed)" }

    $pin = Get-SlotPin $c.Path
    if ($null -ne $pin) { $reasons += "ACTIVE pin: $($pin.slug)" }

    $session = Get-SlotSession $claude $c.Path
    if ($session.state -eq 'live') { $reasons += "live session (pid $($session.pids -join ', '))" }
    if ($session.state -eq 'unknown') { $reasons += 'occupancy unknown (fail-closed)' }

    if ($Epic -and $c.Branch -and ($c.Branch -match [regex]::Escape($Epic))) {
        $reasons += "holds a ticket branch of $Epic"
    }

    $slots += [pscustomobject] @{
        name           = Split-Path -Leaf $c.Abs
        path           = $c.Abs
        branch         = if ($c.Branch) { $c.Branch } else { $null }
        detached       = $c.Detached
        head           = $c.Head
        dirtyCount     = $dirty
        unpushedCount  = $unpushed
        unpushedSource = $unpSource
        pin            = $pin
        progress       = if ($null -ne $pin) { Get-SlotProgress $c.Path $pin.slug } else { $null }
        session        = [pscustomobject] @{ state = $session.state; pids = @($session.pids) }
        free           = ($reasons.Count -eq 0)
        reasons        = @($reasons)
    }
}

# Repo-wide, reported once, never attached to a slot.
$stashRes = Invoke-RepoGit $RepoPath @('stash', 'list')
$stash = if ($stashRes.Code -eq 0) { @($stashRes.Out | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { [string] $_ }) } else { @() }

$state = [pscustomobject] @{
    repoRoot        = $repoAbs
    generatedAt     = [datetimeoffset]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
    occupancySource = $occupancySource
    stashCount      = $stash.Count
    slots           = @($slots)
    excluded        = @($excluded | ForEach-Object { [pscustomobject] $_ })
    stash           = $stash
}

if ($Json) { $state | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Json -Encoding utf8 }

Write-Output "Pool status for $repoAbs"
Write-Output "Occupancy source: $occupancySource"
if ($slots.Count -eq 0) {
    Write-Output 'This repository has no pool: no linked worktree carries the .superpowers/pool-slot marker.'
    foreach ($e in $excluded) { Write-Output ("  excluded {0} — {1}" -f $e.path, $e.reason) }
    exit 3
}
foreach ($s in $slots) {
    $where = if ($s.detached) { 'detached' } else { $s.branch }
    $pinText = if ($null -eq $s.pin) { 'IDLE' } else { $s.pin.slug }
    Write-Output ("  {0}  {1}  pin={2}  dirty={3}  unpushed={4}  session={5}  free={6}" -f `
        $s.name, $where, $pinText, $s.dirtyCount, $s.unpushedCount, $s.session.state, $s.free)
    foreach ($r in $s.reasons) { Write-Output "      - $r" }
}
foreach ($e in $excluded) { Write-Output ("  excluded {0} — {1}" -f $e.path, $e.reason) }
if ($stash.Count -gt 0) {
    Write-Output "Repository-wide stash entries: $($stash.Count) (cannot be attributed to a slot)"
}
exit 0
```

- [ ] **Step 5: Spusť sadu a potvrď zeleň**

```bash
pwsh -NoProfile -File ums/.claude/skills/mb-epic-run/tests/pool-status.tests.ps1
```

Očekávané: `<N> passed`, exit 0. Když případ 9 selže na `git worktree lock` (starší git), přečti skutečnou hlášku a fixturu oprav; asercii neškrtej.

- [ ] **Step 6: Negativita obou regresních důkazů**

Toto je jádro úlohy — bez něj případy 3 a 4 nic nedokazují.

```bash
cp ums/.claude/skills/mb-epic-run/scripts/pool-status.ps1 /tmp/ps-backup.ps1
sha256sum ums/.claude/skills/mb-epic-run/scripts/pool-status.ps1 > /tmp/ps-hash.txt
```

Mutace: v bloku per-slot derivace nahraď per-worktree signály **kontraktovou trojicí** — přidej `$stash.Count -gt 0` a `git log --branches --not --remotes` jako důvody nevolnosti slotu. Spusť sadu.

Očekávané: zčervená `a stash created in slot01 does NOT make slot02 unfree` a `an unpushed commit on branch-a does NOT unfree the slot on branch-b`. Případy, které zůstanou zeleně, zapiš jako **regresní zámky**; vše za případným bodem přerušení jako **NEPROVEDENO** (bod vyčti z transkriptu, ne odhadem).

Druhá mutace: v `Get-SlotProgress` nahraď párování na slug prvním nalezeným adresářem (`Get-ChildItem … | Select-Object -First 1`). Očekávané: zčervená případ 6.

Obnova po každé mutaci:

```bash
cp /tmp/ps-backup.ps1 ums/.claude/skills/mb-epic-run/scripts/pool-status.ps1
sha256sum -c /tmp/ps-hash.txt && cmp /tmp/ps-backup.ps1 ums/.claude/skills/mb-epic-run/scripts/pool-status.ps1 && echo RESTORED
```

Skript je v tomto commitu nový a netrackovaný — `git diff` je vůči němu slepý oběma směry, takže hash a `cmp` jsou jediný důkaz obnovy.

- [ ] **Step 7: Ověř cestu „bez poolu" proti TOMUTO forku, ne jen proti fixtuře**

Fixtura dokazuje, že kód dělá, co jsi do fixtury napsal; skutečné repo dokazuje, že cesta funguje. Tento fork má nula linked worktrees, takže je to přesně případ 1:

```bash
pwsh -NoProfile -File ums/.claude/skills/mb-epic-run/scripts/pool-status.ps1; echo "EXIT=$?"
```

Očekávané: `EXIT=3` a věta o tom, že repozitář nemá pool. Běh je read-only, takže je bezpečný.

- [ ] **Step 8: Commit a publikace**

```bash
git add ums/.claude/skills/mb-epic-run/scripts/pool-status.ps1 ums/.claude/skills/mb-epic-run/tests/
```

```text
UMS-3488: pool-status.ps1 — derivace stavu slotu z per-worktree signálů
 - členství v poolu derivované z git worktree list plus markeru .superpowers/pool-slot; bare, locked, prunable a primary worktree vyloučeny s pojmenovaným důvodem
 - volnost jen z per-worktree signálů; stash se hlásí jednou za repozitář a nikdy se nepřipisuje slotu, nepushnuté commity se počítají proti vlastnímu upstreamu
 - obsazenost z claude agents --json --cwd, filtrovaná na přítomný pid; nečitelný výstup je unknown a unknown není volný
 - ledger se páruje na slug z pinu, o IDLE rozhoduje výhradně pin, ne jméno větve
 - fixtura se skutečnými linked worktrees a sdíleným .git; dva regresní důkazy ověřené negativitou proti kontraktové trojici signálů
```

Pak publikuj větev.

---

### Task 4: `pool-launch.ps1` — spuštění a jeho mechanické ověření

**Files:**
- Create: `ums/.claude/skills/mb-epic-run/scripts/pool-launch.ps1`
- Create: `ums/.claude/skills/mb-epic-run/tests/pool-launch.tests.ps1`
- Create: `ums/.claude/skills/mb-epic-run/tests/stubs/argv-probe.ps1`
- Modify: `ums/.claude/skills/mb-epic-run/tests/_assert.ps1` (helper `Invoke-WithFakeSessionEnv`)

**Interfaces:**
- Consumes: `Invoke-PoolScript` z `_assert.ps1` (Task 3).
- Produces:
  - Skript `pool-launch.ps1` s parametry `-SlotPath <string>` (povinný), `-Prompt <string>` (povinný), `-Ticket <string>` (povinný), `-Adapter terminal|direct` (povinný), `-ClaudeCommand <string>`, `-TerminalCommand <string>`.
  - Na stdout právě jedno **stavové slovo** na vlastním řádku: `launched` / `unavailable` / `failed`, doplněné o řádek s důvodem.
  - Exit kódy: `0` = `launched` · `2` = `unavailable` (adaptér není k dispozici) · `1` = `failed` nebo vstupní chyba.
  - Konstantu `$StripVars` s **devíti** jmény; `CLAUDECODE` a `CLAUDE_CODE_USE_POWERSHELL_TOOL` v ní vědomě nejsou.

- [ ] **Step 1: Napiš sondu argv a helper pro falešné zděděné prostředí**

`tests/stubs/argv-probe.ps1` — skript, který si vypíše vlastní `$args` a vlastní prostředí do souboru. Je to jediný způsob, jak zjistit, co se ke spouštěnému programu opravdu dostane; z tvaru příkazové řádky se to odvodit nedá.

```powershell
#Requires -Version 7
# Probe: writes its own argv and environment to $env:MBPOOL_PROBE_OUT as JSON.
# Never infer from the shape of a command line which tokens reach a program —
# run something that prints its own argv and read it.
param([Parameter(ValueFromRemainingArguments = $true)] $Rest)
$payload = [pscustomobject] @{
    argv = @($Rest | ForEach-Object { [string] $_ })
    env  = @{}
}
foreach ($n in @('CLAUDE_CODE_CHILD_SESSION','CLAUDE_CODE_SESSION_ID','CLAUDE_CODE_BRIDGE_SESSION_ID',
                 'CLAUDE_CODE_MESSAGING_SOCKET','CLAUDE_CODE_MESSAGING_TOKEN','CLAUDE_CODE_SSE_PORT',
                 'CLAUDE_PID','CLAUDE_CODE_ENTRYPOINT','NO_COLOR',
                 'CLAUDECODE','CLAUDE_CODE_USE_POWERSHELL_TOOL')) {
    $payload.env[$n] = [Environment]::GetEnvironmentVariable($n)
}
$payload.cwd = (Get-Location).Path
$payload | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $env:MBPOOL_PROBE_OUT -Encoding utf8
exit 0
```

Do `_assert.ps1` přidej:

```powershell
# Sets the nine variables a child would inherit from an orchestrator session,
# runs $Body, and restores. Parameter names differ from every other wrapper in
# this file ON PURPOSE: `& $X` binds dynamically to the $X of the FUNCTION it
# runs in, so a shared parameter name anywhere in a wrapper chain recurses
# until the stack overflows.
function Invoke-WithFakeSessionEnv([scriptblock] $EnvBody) {
    $names = @('CLAUDE_CODE_CHILD_SESSION','CLAUDE_CODE_SESSION_ID','CLAUDE_CODE_BRIDGE_SESSION_ID',
               'CLAUDE_CODE_MESSAGING_SOCKET','CLAUDE_CODE_MESSAGING_TOKEN','CLAUDE_CODE_SSE_PORT',
               'CLAUDE_PID','CLAUDE_CODE_ENTRYPOINT','NO_COLOR',
               'CLAUDECODE','CLAUDE_CODE_USE_POWERSHELL_TOOL')
    $saved = @{}
    foreach ($n in $names) { $saved[$n] = [Environment]::GetEnvironmentVariable($n) }
    try {
        foreach ($n in $names) { Set-Item -Path "Env:$n" -Value 'inherited' }
        & $EnvBody
    }
    finally {
        foreach ($n in $names) {
            if ($null -eq $saved[$n]) { Remove-Item -Path "Env:$n" -ErrorAction SilentlyContinue }
            else { Set-Item -Path "Env:$n" -Value $saved[$n] }
        }
    }
}
```

- [ ] **Step 2: Napiš padající sadu `pool-launch.tests.ps1`**

Pokrývá verifikační body 6 a 7 návrhu.

```powershell
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '_assert.ps1')
$ErrorActionPreference = 'Stop'
$Probe = Join-Path $PSScriptRoot 'stubs\argv-probe.ps1'
$NewFixture = Join-Path $PSScriptRoot 'new-pool-fixture.ps1'

# The exact prompt shape the design mandates: one quoted argument, Czech
# diacritics, an em dash, and NO semicolon (wt.exe treats it as its own
# command separator).
$RealPrompt = 'Převezmi tiket UMS-3488 — zbytek si najdi v ledgeru epiku, cesta memory-bank/epics/ums_3400/ledger.md'

function Invoke-Launch([string] $Slot, [string] $Adapter, [string] $Prompt, [string] $Claude, [string] $Terminal = '') {
    $out = Join-Path ([IO.Path]::GetTempPath()) ('mbprobe-' + [guid]::NewGuid().ToString('N') + '.json')
    $env:MBPOOL_PROBE_OUT = $out
    $a = @('-SlotPath', $Slot, '-Prompt', $Prompt, '-Ticket', 'UMS-3488', '-Adapter', $Adapter, '-ClaudeCommand', $Claude)
    if ($Terminal) { $a += @('-TerminalCommand', $Terminal) }
    $r = Invoke-PoolScript 'pool-launch.ps1' $a
    Start-Sleep -Milliseconds 400   # the direct adapter starts a process
    $probe = $null
    if (Test-Path -LiteralPath $out) { $probe = Get-Content -LiteralPath $out -Raw | ConvertFrom-Json }
    Remove-Item -LiteralPath $out -Force -ErrorAction SilentlyContinue
    return @{ Out = $r.Out; Code = $r.Code; Probe = $probe }
}

$fx = & $NewFixture -SlotCount 1 -Label 'launch'
try {
    $slot = $fx.Slots[0]

    # --- case 1: the DIRECT adapter delivers the whole prompt as ONE argument
    Invoke-WithFakeSessionEnv {
        $script:r1 = Invoke-Launch $slot 'direct' $RealPrompt $Probe
    }
    Assert-Eq $script:r1.Code 0 'direct adapter reports launched (exit 0)'
    Assert-Match $script:r1.Out '(?m)^launched$' 'direct adapter prints the status word launched'
    Assert-True ($null -ne $script:r1.Probe) 'the direct adapter actually started the probe'
    $argv = @($script:r1.Probe.argv)
    Assert-True ($argv -contains $RealPrompt) 'the whole prompt arrives as ONE argument, diacritics and em dash intact'
    Assert-True ($argv -contains '--name' -and $argv -contains 'UMS-3488') 'the session is named after the ticket'

    # --- case 2: the nine inherited variables are gone, the two kept remain
    foreach ($n in @('CLAUDE_CODE_CHILD_SESSION','CLAUDE_CODE_SESSION_ID','CLAUDE_CODE_BRIDGE_SESSION_ID',
                     'CLAUDE_CODE_MESSAGING_SOCKET','CLAUDE_CODE_MESSAGING_TOKEN','CLAUDE_CODE_SSE_PORT',
                     'CLAUDE_PID','CLAUDE_CODE_ENTRYPOINT','NO_COLOR')) {
        Assert-Eq $script:r1.Probe.env.$n $null "$n is stripped before the spawn"
    }
    Assert-Eq $script:r1.Probe.env.CLAUDECODE 'inherited' 'CLAUDECODE is deliberately KEPT (baton writer precondition, UserProfile marker carrier)'
    Assert-Eq $script:r1.Probe.env.CLAUDE_CODE_USE_POWERSHELL_TOOL 'inherited' 'CLAUDE_CODE_USE_POWERSHELL_TOOL is a user setting, not session state — kept'

    # --- case 3: the child starts in the SLOT, not in the orchestrator's cwd
    Assert-Match ($script:r1.Probe.cwd -replace '\\', '/') ([regex]::Escape(($slot -replace '\\', '/'))) 'the child runs with the slot as its working directory'

    # --- case 4: the TERMINAL adapter, same delivery through wt.exe's argv
    Invoke-WithFakeSessionEnv {
        $script:r2 = Invoke-Launch $slot 'terminal' $RealPrompt $Probe $Probe
    }
    Assert-Eq $script:r2.Code 0 'terminal adapter reports launched (exit 0)'
    Assert-True ($null -ne $script:r2.Probe) 'the terminal adapter actually invoked its terminal command'
    Assert-True (@($script:r2.Probe.argv) -contains $RealPrompt) 'the terminal adapter also delivers the prompt as ONE argument'

    # --- case 5: a prompt containing a semicolon is REFUSED before any spawn
    Invoke-WithFakeSessionEnv {
        $script:r3 = Invoke-Launch $slot 'terminal' 'do this; and that' $Probe $Probe
    }
    Assert-Eq $script:r3.Code 1 'a semicolon in the prompt is a hard input error'
    Assert-Match $script:r3.Out 'semicolon' 'the refusal names the semicolon'
    Assert-True ($null -eq $script:r3.Probe) 'nothing was spawned'

    # --- case 6: a missing terminal command is `unavailable`, never a fallback
    Invoke-WithFakeSessionEnv {
        $script:r4 = Invoke-Launch $slot 'terminal' $RealPrompt $Probe (Join-Path $PSScriptRoot 'stubs\does-not-exist.exe')
    }
    Assert-Eq $script:r4.Code 2 'a missing terminal command exits 2'
    Assert-Match $script:r4.Out '(?m)^unavailable$' 'the status word is unavailable'
    Assert-NotMatch $script:r4.Out 'launched' 'the script NEVER falls back to another adapter'
    Assert-True ($null -eq $script:r4.Probe) 'no hidden fallback spawn happened'

    # --- case 7: a slot path that does not exist is an input error
    $r5 = Invoke-Launch (Join-Path $fx.Root 'nope') 'direct' $RealPrompt $Probe
    Assert-Eq $r5.Code 1 'a non-existent slot path is an input error'
}
finally {
    Remove-Item -Recurse -Force $fx.Root -ErrorAction SilentlyContinue
    Remove-Item -Path 'Env:MBPOOL_PROBE_OUT' -ErrorAction SilentlyContinue
}

Complete-Tests
```

- [ ] **Step 3: Spusť sadu a potvrď selhání**

```bash
pwsh -NoProfile -File ums/.claude/skills/mb-epic-run/tests/pool-launch.tests.ps1
```

Očekávané: sada spadne (skript neexistuje).

- [ ] **Step 4: Implementuj `pool-launch.ps1`**

```powershell
#Requires -Version 7
<#
.SYNOPSIS
Launches one Claude Code session in a pool slot, with the inherited session
environment stripped and the prompt delivered on argv.

.DESCRIPTION
Three measured failures on 2026-09-02 all LOOKED like success, and each had a
mechanical cause this script exists to remove.

1. A child inherits the orchestrator's own session variables and comes up as a
   CHILD session with transcript saving off, wearing the parent's identity and
   messaging pipe. Nine variables are therefore removed from this process
   before the spawn — and the removal must happen in the SAME invocation as the
   spawn, because every PowerShell tool call is a fresh shell inheriting from
   the parent again.
2. An argument list passed unquoted falls apart into single words and the
   session receives one word as its whole brief. The prompt is therefore passed
   as ONE argument, verbatim.
3. `Get-Process claude` returns a pid in all three failure modes, so process
   existence proves nothing. Proof is the harness's own session registry, and
   the caller obtains it by looking for the `--name <TICKET>` this script
   passes.

CLAUDECODE is deliberately NOT stripped, for two independent reasons: it is
part of the baton writer's precondition, so removing it would make every
spawned session refuse to write its own baton (losing the third execution
choice and the fifth stop class, silently); and on a -Scope UserProfile
deployment it is the ONLY carrier of the publication guarantee, because that
scope does not deploy settings.json and the pre-push hook then has nothing but
its CLAUDECODE/AI_AGENT fallback. CLAUDE_CODE_USE_POWERSHELL_TOOL stays too —
that is a user setting, not session state.

The variable list lives HERE and not in ums-repo.json: it is a property of the
harness, not of the repository (contract, "Repository Configuration").

.PARAMETER Adapter
`terminal` (wt.exe) or `direct` (Start-Process). Exactly one command each, no
hidden fallback chain: this script never decides which adapter to use and
never falls back to another one.

.OUTPUTS
One status word on its own line — launched | unavailable | failed — plus a
reason line. Exit: 0 = launched, 2 = unavailable, 1 = failed or input error.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string] $SlotPath,
    [Parameter(Mandatory = $true)] [string] $Prompt,
    [Parameter(Mandatory = $true)] [string] $Ticket,
    [Parameter(Mandatory = $true)] [ValidateSet('terminal', 'direct')] [string] $Adapter,
    [string] $ClaudeCommand = '',
    [string] $TerminalCommand = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }

$StripVars = @(
    'CLAUDE_CODE_CHILD_SESSION',      # child session: turns transcript saving off
    'CLAUDE_CODE_SESSION_ID',         # child pretends to be the same session
    'CLAUDE_CODE_BRIDGE_SESSION_ID',  # same, for the bridge
    'CLAUDE_CODE_MESSAGING_SOCKET',   # child would talk over the parent's pipe
    'CLAUDE_CODE_MESSAGING_TOKEN',    # same
    'CLAUDE_CODE_SSE_PORT',           # same
    'CLAUDE_PID',                     # parent identity
    'CLAUDE_CODE_ENTRYPOINT',         # parent's entry point marker
    'NO_COLOR'                        # session comes up monochrome under VS Code
)

function Write-Status([string] $Word, [string] $Reason, [int] $Code) {
    Write-Output $Word
    Write-Output $Reason
    exit $Code
}

if (-not (Test-Path -LiteralPath $SlotPath -PathType Container)) {
    Write-Status 'failed' "Slot path does not exist: $SlotPath" 1
}
if ([string]::IsNullOrWhiteSpace($Prompt)) {
    Write-Status 'failed' 'The prompt is empty.' 1
}
# Measured: wt.exe reads a semicolon as its own command separator, so a prompt
# carrying one is split into commands rather than delivered. Refused for BOTH
# adapters so the prompt text is adapter-independent.
if ($Prompt.Contains(';')) {
    Write-Status 'failed' 'The prompt contains a semicolon; wt.exe reads it as a command separator. Rewrite the prompt without one.' 1
}
if ($Prompt.Length -gt 600) {
    Write-Status 'failed' "The prompt is $($Prompt.Length) characters. A prompt says what to do, which ticket, and where to read the rest — the rest is pulled from the ledger." 1
}

$claude = $ClaudeCommand
if ([string]::IsNullOrWhiteSpace($claude)) {
    $cmd = Get-Command claude -ErrorAction SilentlyContinue
    if (-not $cmd) { Write-Status 'unavailable' 'claude was not found in PATH (never hardcode its path).' 2 }
    $claude = $cmd.Source
}
elseif (-not (Test-Path -LiteralPath $claude -PathType Leaf)) {
    Write-Status 'unavailable' "The given claude command does not exist: $claude" 2
}

# Removal happens in THIS process, immediately before the spawn, so the child
# cannot inherit what the orchestrator handed us.
foreach ($n in $StripVars) { Remove-Item -Path "Env:$n" -ErrorAction SilentlyContinue }

$claudeArgs = @('--name', $Ticket, $Prompt)

if ($Adapter -eq 'direct') {
    try {
        Start-Process -FilePath $claude -ArgumentList $claudeArgs -WorkingDirectory $SlotPath | Out-Null
    }
    catch {
        Write-Status 'failed' "Start-Process failed: $($_.Exception.Message)" 1
    }
    Write-Status 'launched' "direct adapter: $claude in $SlotPath, session named $Ticket" 0
}

# terminal adapter
$terminal = $TerminalCommand
if ([string]::IsNullOrWhiteSpace($terminal)) {
    $cmd = Get-Command wt.exe -ErrorAction SilentlyContinue
    if (-not $cmd) { Write-Status 'unavailable' 'wt.exe was not found in PATH. This script never falls back to another adapter.' 2 }
    $terminal = $cmd.Source
}
elseif (-not (Test-Path -LiteralPath $terminal -PathType Leaf)) {
    Write-Status 'unavailable' "The given terminal command does not exist: $terminal. This script never falls back to another adapter." 2
}

try {
    & $terminal -d $SlotPath $claude @claudeArgs
    if ($LASTEXITCODE -ne 0) { Write-Status 'failed' "The terminal command exited with $LASTEXITCODE." 1 }
}
catch {
    Write-Status 'failed' "The terminal command failed: $($_.Exception.Message)" 1
}
Write-Status 'launched' "terminal adapter: $terminal -d $SlotPath, session named $Ticket" 0
```

- [ ] **Step 5: Spusť sadu a potvrď zeleň**

```bash
pwsh -NoProfile -File ums/.claude/skills/mb-epic-run/tests/pool-launch.tests.ps1
```

Očekávané: `<N> passed`, exit 0. Pokud případ 4 (terminal) vrátí prázdnou sondu, je to skutečný nález o předávání argv přes `& $terminal`, ne šum — přečti výstup sondy a oprav skript, ne test.

- [ ] **Step 6: Negativita vyčištění prostředí**

Odstraň z `$StripVars` proměnnou `CLAUDE_CODE_CHILD_SESSION` a spusť sadu. Očekávané: zčervená právě asercie `CLAUDE_CODE_CHILD_SESSION is stripped before the spawn`. Pak přidej do `$StripVars` navíc `CLAUDECODE` a spusť znovu: očekávaně zčervená asercie o jeho ponechání — bez ní by nikdo nepoznal, že se seznam rozšířil o proměnnou, kterou rozšířit nesmí. Po obou mutacích obnov soubor ze zálohy a doluž hashem, stejně jako v Tasku 3.

- [ ] **Step 7: Commit a publikace**

```bash
git add ums/.claude/skills/mb-epic-run/scripts/pool-launch.ps1 ums/.claude/skills/mb-epic-run/tests/
```

```text
UMS-3488: pool-launch.ps1 — vyčištěné prostředí, argv prompt, dva prokázané adaptéry
 - před spuštěním se z prostředí odebírá devět proměnných zděděného sezení; CLAUDECODE a CLAUDE_CODE_USE_POWERSHELL_TOOL se vědomě nechávají
 - prompt jde jako jeden argument; středník je tvrdá vstupní chyba, protože wt.exe ho bere jako oddělovač příkazů
 - adaptéry terminal a direct, každý právě jeden příkaz, žádný skrytý fallback řetěz; chybějící wt.exe je stav unavailable
 - --name <TIKET> pro pozdější strojové ověření v session registru harnessu
 - sonda vypisující vlastní argv a prostředí dokazuje doručení přes oba adaptéry, včetně diakritiky a pomlčky
```

Pak publikuj větev.

---

### Task 5: `pool-provision.ps1` — vynucený nástroj operátora

**Files:**
- Create: `ums/.claude/skills/mb-epic-run/scripts/pool-provision.ps1`
- Create: `ums/.claude/skills/mb-epic-run/tests/pool-provision.tests.ps1`

**Interfaces:**
- Consumes: `Invoke-PoolScript`, `new-pool-fixture.ps1` (Task 3).
- Produces:
  - Skript `pool-provision.ps1` s parametry `-Path <string>` (povinný), `-Base <string>`, `-RepoPath <string>`, `-Operator [switch]`, `-NoFetch [switch]`.
  - Exit kódy: `0` OK · `1` vstupní/skriptové selhání · `4` **odmítnuto guardem** (běží pod značkou agentní relace bez `-Operator`).
  - Postcondice úspěšného běhu: existuje linked worktree na `-Path`, v něm marker `.superpowers/pool-slot`, a `git rev-parse --git-path hooks/pre-push` **z vnitřku slotu** ukazuje na značkovaný hook v2.

- [ ] **Step 1: Napiš padající sadu `pool-provision.tests.ps1`**

Pokrývá verifikační bod 11 návrhu.

```powershell
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '_assert.ps1')
$ErrorActionPreference = 'Stop'
$NewFixture = Join-Path $PSScriptRoot 'new-pool-fixture.ps1'

function Invoke-Provision([string] $Repo, [string] $Path, [string[]] $Extra = @()) {
    $a = @('-RepoPath', $Repo, '-Path', $Path, '-Base', 'origin/develop', '-NoFetch') + $Extra
    return Invoke-PoolScript 'pool-provision.ps1' $a
}

# --- case 1: the guard refuses under an agent-session marker ----------------
$fx = & $NewFixture -SlotCount 0 -Label 'guard'
try {
    $new = Join-Path $fx.Root 'slotX'
    Invoke-WithFakeSessionEnv {
        $script:g = Invoke-Provision $fx.Main $new
    }
    Assert-Eq $script:g.Code 4 'provisioning under an agent-session marker exits 4'
    Assert-Match $script:g.Out 'operator' 'the refusal names the operator switch'
    Assert-True (-not (Test-Path -LiteralPath $new)) 'nothing was created'
}
finally { Remove-Item -Recurse -Force $fx.Root -ErrorAction SilentlyContinue }

# --- case 2: with -Operator it proceeds, and it creates the MARKER ----------
$fx = & $NewFixture -SlotCount 0 -Label 'operator'
try {
    $new = Join-Path $fx.Root 'slotX'
    Invoke-WithFakeSessionEnv {
        $script:o = Invoke-Provision $fx.Main $new @('-Operator')
    }
    Assert-Eq $script:o.Code 0 'with -Operator the run succeeds even under the marker'
    Assert-True (Test-Path -LiteralPath (Join-Path $new '.git')) 'a linked worktree was created'
    Assert-True (Test-Path -LiteralPath (Join-Path (Join-Path $new '.superpowers') 'pool-slot')) 'the pool-slot marker was created'
    # Detached on purpose: a fresh slot must not hold a branch.
    $head = & git -C $new rev-parse --abbrev-ref HEAD 2>&1
    Assert-Eq ([string] $head).Trim() 'HEAD' 'a fresh slot is detached'
    Assert-Match $script:o.Out 'GB|MB|bytes' 'the run reports the size of the new slot'
}
finally { Remove-Item -Recurse -Force $fx.Root -ErrorAction SilentlyContinue }

# --- case 3: outside an agent session no switch is needed -------------------
$fx = & $NewFixture -SlotCount 0 -Label 'human'
try {
    $new = Join-Path $fx.Root 'slotX'
    $r = Invoke-Provision $fx.Main $new
    Assert-Eq $r.Code 0 'outside an agent session the guard does not fire'
    Assert-True (Test-Path -LiteralPath (Join-Path (Join-Path $new '.superpowers') 'pool-slot')) 'the marker is created on the human path too'
}
finally { Remove-Item -Recurse -Force $fx.Root -ErrorAction SilentlyContinue }

# --- case 4: an existing current hook is NOT reinstalled --------------------
$fx = & $NewFixture -SlotCount 0 -Label 'hook'
try {
    $hook = Join-Path (Join-Path (Join-Path $fx.Main '.git') 'hooks') 'pre-push'
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $hook) | Out-Null
    $marker = 'MARKER-SENTINEL-DO-NOT-OVERWRITE'
    Set-Content -LiteralPath $hook -Value "#!/bin/sh`n# UMS pre-push guard (Publication Contract) v2`n# $marker`nexit 0`n" -Encoding utf8 -NoNewline
    $new = Join-Path $fx.Root 'slotX'
    $r = Invoke-Provision $fx.Main $new
    Assert-Eq $r.Code 0 'provisioning succeeds with a current hook already in place'
    Assert-Match (Get-Content -LiteralPath $hook -Raw) $marker 'a current marked v2 hook is left untouched'
    Assert-Match $r.Out 'v2' 'the run reports that the shared hook is current'
}
finally { Remove-Item -Recurse -Force $fx.Root -ErrorAction SilentlyContinue }

# --- case 5: an existing target path is refused, never overwritten ----------
$fx = & $NewFixture -SlotCount 0 -Label 'exists'
try {
    $new = Join-Path $fx.Root 'slotX'
    New-Item -ItemType Directory -Force -Path $new | Out-Null
    Set-Content -LiteralPath (Join-Path $new 'keepme.txt') -Value 'operator content' -Encoding utf8
    $r = Invoke-Provision $fx.Main $new
    Assert-Eq $r.Code 1 'a non-empty existing target path is an input error'
    Assert-Match (Get-Content -LiteralPath (Join-Path $new 'keepme.txt') -Raw) 'operator content' 'existing content is untouched'
}
finally { Remove-Item -Recurse -Force $fx.Root -ErrorAction SilentlyContinue }

Complete-Tests
```

Builder fixtury musí umět `-SlotCount 0`; ověř, že cyklus `for` s nulou nevytvoří nic a vrátí prázdné pole (`$slots = @()` už na začátku je).

- [ ] **Step 2: Spusť sadu a potvrď selhání**

```bash
pwsh -NoProfile -File ums/.claude/skills/mb-epic-run/tests/pool-provision.tests.ps1
```

- [ ] **Step 3: Implementuj `pool-provision.ps1`**

```powershell
#Requires -Version 7
<#
.SYNOPSIS
Provisions a new pool slot: a linked worktree, its pool-slot marker, and a
check that the shared pre-push guard covers it.

.DESCRIPTION
This is an OPERATOR tool, and the guard that makes that true lives in the
script rather than only in prose: the run refuses when an agent-session marker
is in the environment, unless the operator says so explicitly with -Operator.
The guard is here because it travels with the layer even to harnesses where
permissions.deny does not exist (permissions.deny carries the same rule for
Claude Code, in settings.json).

The hook check runs FROM INSIDE the new slot, because that is where the
question is: `git rev-parse --git-path hooks/pre-push` resolves per worktree
and honours core.hooksPath. A shared .git means one installation covers every
slot, so this installs only when the hook is MISSING or older than v2 —
reinstalling a current hook would be a write nobody asked for.

.OUTPUTS
English progress lines. Exit: 0 = OK, 1 = input/script failure,
4 = refused by the agent-session guard.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string] $Path,
    [string] $Base = '',
    [string] $RepoPath = '',
    [switch] $Operator,
    [switch] $NoFetch
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }

function Invoke-RepoGit([string] $Dir, [string[]] $GitArgs) {
    $out = & git -C $Dir @GitArgs 2>&1
    return @{ Out = @($out); Code = $LASTEXITCODE }
}

# Same three variables the pre-push hook's own entry gate reads, in the same
# order, so "an agent session" means the same thing in both places.
$agentMarker = ($env:MB_AGENT_SESSION -eq '1') -or
               (-not [string]::IsNullOrEmpty($env:AI_AGENT)) -or
               ($env:CLAUDECODE -eq '1') -or
               (-not [string]::IsNullOrEmpty($env:CLAUDECODE))
if ($agentMarker -and -not $Operator) {
    Write-Output 'Refused: an agent-session marker is present in the environment.'
    Write-Output 'Provisioning a pool slot is an OPERATOR action (contract, Worktree Policy).'
    Write-Output 'If you are the operator and you mean it, re-run with -Operator.'
    exit 4
}

if ([string]::IsNullOrWhiteSpace($RepoPath)) {
    $top = & git rev-parse --show-toplevel 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($top)) {
        Write-Error 'Git repository not found. Memory Bank requires git.'; exit 1
    }
    $RepoPath = ([string] $top).Trim()
}
if (Test-Path -LiteralPath $Path) {
    $existing = @(Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue)
    if ($existing.Count -gt 0) {
        Write-Error "Target path exists and is not empty: $Path"; exit 1
    }
}

if ([string]::IsNullOrWhiteSpace($Base)) {
    # baseRef comes from the repository configuration, and it already carries
    # its remote prefix — never prefix it a second time.
    $loader = Join-Path $PSScriptRoot '..\..\shared\scripts\Get-UmsRepoConfig.ps1'
    if (Test-Path -LiteralPath $loader -PathType Leaf) {
        . $loader
        $cfg = Get-UmsRepoConfig -RepoRoot $RepoPath
        $Base = $cfg.baseRef
    }
    if ([string]::IsNullOrWhiteSpace($Base)) { $Base = 'origin/develop' }
}

if (-not $NoFetch) {
    Write-Output "Fetching $RepoPath ..."
    $f = Invoke-RepoGit $RepoPath @('fetch', 'origin')
    if ($f.Code -ne 0) { Write-Error "git fetch origin failed: $($f.Out -join "`n")"; exit 1 }
}

Write-Output "Creating a detached linked worktree at $Path from $Base ..."
$add = Invoke-RepoGit $RepoPath @('worktree', 'add', '--detach', $Path, $Base)
if ($add.Code -ne 0) { Write-Error "git worktree add failed: $($add.Out -join "`n")"; exit 1 }

$markerDir = Join-Path $Path '.superpowers'
New-Item -ItemType Directory -Force -Path $markerDir | Out-Null
$markerText = @(
    '# UMS pool slot marker.',
    '# Membership of the pool is derived, not configured: this file is what makes',
    '# this worktree a slot. Without it a worktree held for release maintenance —',
    '# clean tree, IDLE pin, no unpushed commits — would satisfy every freedom',
    '# condition and a spawn would switch it to a ticket branch.'
) -join "`n"
Set-Content -LiteralPath (Join-Path $markerDir 'pool-slot') -Value $markerText -Encoding utf8
Write-Output 'Marker .superpowers/pool-slot created.'

# --- shared hook check, asked FROM INSIDE the new slot -----------------------
$hookRes = Invoke-RepoGit $Path @('rev-parse', '--git-path', 'hooks/pre-push')
if ($hookRes.Code -ne 0) {
    Write-Output 'WARNING: could not resolve the pre-push hook path from inside the slot.'
}
else {
    $hookRaw = ([string] ($hookRes.Out | Select-Object -First 1)).Trim()
    # The path SHAPE differs by where you ask from: absolute from a slot,
    # relative from the primary worktree. Normalize before doing anything with it.
    $hookPath = if ([IO.Path]::IsPathRooted($hookRaw)) { $hookRaw } else { Join-Path $Path $hookRaw }
    $current = $false
    if (Test-Path -LiteralPath $hookPath -PathType Leaf) {
        $head5 = @(Get-Content -LiteralPath $hookPath -TotalCount 5)
        # -cmatch, case-sensitive: a broken hook whose error message merely
        # quotes its own path would otherwise pass as verified in any
        # repository living under a directory whose name contains "ums".
        $current = [bool](@($head5 | Where-Object { $_ -cmatch 'UMS pre-push guard \(Publication Contract\) v2' }).Count)
    }
    if ($current) {
        Write-Output "Shared pre-push guard is current (v2) at $hookPath — not reinstalling."
    }
    else {
        Write-Output "Shared pre-push guard is missing or older than v2 at $hookPath — installing."
        $installer = Join-Path $PSScriptRoot '..\..\..\hooks\install-git-hooks.ps1'
        if (-not (Test-Path -LiteralPath $installer -PathType Leaf)) {
            Write-Output "WARNING: installer not found at $installer; install the hook by hand."
        }
        else {
            & pwsh -NoProfile -File $installer -RepoRoot $Path
            if ($LASTEXITCODE -ne 0) {
                Write-Output "WARNING: install-git-hooks.ps1 exited $LASTEXITCODE — the publication guarantee is NOT confirmed."
            }
        }
    }
}

# --- size report -------------------------------------------------------------
$bytes = 0
$files = 0
Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue |
    ForEach-Object { $bytes += $_.Length; $files++ }
$gb = [math]::Round($bytes / 1GB, 2)
Write-Output "Slot provisioned: $files files, $gb GB (bytes: $bytes)."
Write-Output 'Next: run the mb-epic-run skill (status) to see the slot in the pool.'
exit 0
```

- [ ] **Step 4: Spusť sadu a potvrď zeleň**

```bash
pwsh -NoProfile -File ums/.claude/skills/mb-epic-run/tests/pool-provision.tests.ps1
```

Očekávané: `<N> passed`, exit 0.

- [ ] **Step 5: Negativita guardu**

Odstraň celou podmínku `if ($agentMarker -and -not $Operator)` a spusť sadu. Očekávané: zčervenají obě asercie případu 1 (`exits 4`, `nothing was created`). Případy 2, 3, 4, 5 zůstanou zeleně — **regresní zámky**, ne důkaz guardu. Pak vrať podmínku, ale ze seznamu proměnných vypusť `MB_AGENT_SESSION` a znovu změř: pokud sada zůstane celá zelená, chybí případ, který nastavuje **jen** `MB_AGENT_SESSION` — přidej ho. Obnovu doluž hashem.

- [ ] **Step 6: Commit a publikace**

```bash
git add ums/.claude/skills/mb-epic-run/scripts/pool-provision.ps1 ums/.claude/skills/mb-epic-run/tests/
```

```text
UMS-3488: pool-provision.ps1 — provisionace slotu jako vynucený nástroj operátora
 - guard ve skriptu odmítá běh pod značkou agentní relace bez přepínače -Operator, takže pravidlo putuje s vrstvou i tam, kde permissions.deny neexistuje
 - zakládá detached linked worktree z báze, marker .superpowers/pool-slot a hlásí velikost slotu
 - kontrola sdíleného pre-push hooku se ptá z vnitřku slotu a normalizuje tvar cesty; aktuální značkovaný v2 hook se nepřeinstalovává
 - neprázdný cílový adresář je vstupní chyba, nikdy se nepřepisuje
```

Pak publikuj větev.

---

### Task 6: Skill `mb-epic-run`

**Files:**
- Create: `ums/.claude/skills/mb-epic-run/SKILL.md`
- Modify: `ums/.claude/skills/shared/SKILLS_MANIFEST.md`

**Interfaces:**
- Consumes: JSON kontrakt `pool-status.ps1` (Task 3), stavová slova a exit kódy `pool-launch.ps1` (Task 4), `pool-provision.ps1` (Task 5, jen jako odkaz pro operátora — skill ho nikdy nevolá), existující `epic-graph.ps1` a `ledger-status.ps1` **beze změny rozhraní**.
- Produces: skill se čtyřmi operacemi `status`, `ready <EPIK>`, `spawn <TIKET>`, `attach <TIKET>`, na který se v Tasku 7 odkazuje `mb-epic-elaboration`.

- [ ] **Step 1: Napiš `SKILL.md`**

Frontmatter kopíruje tvar ostatních `mb-*` skillů (`name`, `description`, `license`, `metadata`) a přidává `allowed-tools`, jak žádá návrh. **Žádný jiný skill této vrstvy `allowed-tools` dnes nemá** — je to vědomá odchylka od zavedeného tvaru, ne omyl; důvod je, že tenhle skill jako jediný spouští procesy mimo repozitář.

`description` piš **jazykem otázky, kterou položí uživatel**, ne jménem interní sekce — triggering řídí výhradně `description`. Druhá oponentura namítá, že je to čtvrté české `description` v téže sémantické čtvrti; proto v něm musí zaznít slovo, které ostatní tři nemají: **spuštění/rozjetí sezení do slotu**.

```markdown
---
name: mb-epic-run
description: Use when a ticket is to be STARTED as its own session in a pool slot, or when you need to see which slot holds what — "rozjeď tiket UMS-1234", "co je volné", "pusť sezení na tiket", "stav poolu", "kde běží ten tiket", "co je připravené rozjet". Companion of mb-epic-elaboration; the pool is a set of linked worktrees the operator provisioned and marked.
license: MIT
metadata:
  author: UMS Project
  version: "1.0"
allowed-tools: Bash(git status:*), Bash(git worktree list:*), Bash(git rev-parse:*), Bash(git log:*), Bash(git branch:*), Bash(git for-each-ref:*), Bash(git fetch:*), Bash(git stash list:*), Bash(claude agents:*), Read, Grep, Glob, PowerShell(pwsh:*)
---

> Follow [UMS_MEMORY_BANK_CONTRACT](../shared/UMS_MEMORY_BANK_CONTRACT.md) —
> especially "Worktree Policy" (the pool-slot exception), "Workspace
> Discipline" (a pool slot's freedom is derived from per-worktree signals
> only), "Publication Contract" and "Cross-Branch Visibility".

# Command: mb-epic-run

**Action:** Show the state of the pool, put both readiness oracles side by
side, start a session on a ticket in a free slot, and point the operator at
the slot that holds a ticket.

**Execution:** Read-only towards every slot. The ONLY write this skill ever
makes is one intent line in the epic's ledger, on the ELABORATION branch, in
this repository — never inside a slot.

## Iron rules

These are not style. Each one closes a measured failure.

1. **Never `cd` into a slot.** Ask git about it with `-C <slot>`.
2. **Never run a writing git command in a slot.** No `switch`, no `commit`, no
   `stash`, no `clean`, no `checkout`.
3. **Never write, move or delete ANYTHING inside a slot** — not a briefing,
   not a baton, not a note. The intent travels on argv and in the ledger; the
   session in the slot pulls the rest itself.
4. **Never spawn without the collision check.** A collision check that FAILED
   is not "no collision" — a run that did not complete is a STOP.
5. **A STOP leaves the slot exactly as it was found.** With rule 3 that is
   trivially true, and it must stay trivially true.
6. **Never decide the adapter silently and never fall back to another one.**
   `pool-launch.ps1` returns `unavailable`; report it and stop.
7. **Occupancy `unknown` is not free.** Without the harness signal, spawn only
   on the operator's explicit instruction, never on your own judgement.
8. **Never provision a slot.** `pool-provision.ps1` is the operator's; it
   refuses to run under an agent-session marker anyway.

## Operations

All four report in Czech. The scripts speak English (they are developer
tooling, contract "Language Contract"); the rendering into Czech is this
skill's job.

### `status`

1. Run the state script, always with `-Json`, and keep the file for the rest
   of the session:

       pwsh <this skill>/scripts/pool-status.ps1 -Json .superpowers/pool-status.json [-Epic <EPIC>]

2. Exit `3` means **this repository has no pool**: no linked worktree carries
   the `.superpowers/pool-slot` marker. Report it in Czech, name
   `pool-provision.ps1` as the operator's remedy, and STOP — this is a
   fail-closed refusal, not a degraded mode.
3. Render the Czech table from the JSON, one row per slot:

| Slot | Větev / detached | Pin | Postup v plánu | Špinavé | Nepushnuté | Sezení | Volný |

   `Sezení` renders `session.state` as `běží (pid …)` / `žádné` / `neznámé`.
   `Volný` renders `free`, and under a non-free row list its `reasons`.
4. Print `excluded` as a separate short list (why a worktree is not a slot),
   and the repository-wide `stash` count as ONE line that is explicitly NOT a
   property of any slot.
5. When an epic is in play, add the epic view: for every ticket in its ledger,
   whether some slot holds it.

### `ready <EPIK>`

Runs the two existing oracles **as they are** and prints both outputs next to
the pool table. **No verdict, no classification.** The decision stays with the
operator, who has been making it by hand and correctly; this skill only puts
both tables in one place so they do not have to be collected.

       pwsh <mb-epic-graph>/scripts/epic-graph.ps1 -Epic <EPIK> -Check
       pwsh <mb-epic-elaboration>/scripts/ledger-status.ps1 -LedgerFile memory-bank/epics/<epic_snake>/ledger.md

Then the pool table from `status`. Classification of readiness is a separate,
queued work item — do not invent one here.

### `spawn <TIKET>`

In this order, and the order is the point.

1. **Eligibility, every item a STOP with a named reason when unmet:**
   - the pool exists (at least one marked worktree — `pool-status.ps1` exit 3
     is the refusal),
   - the ticket appears in the epic's ledger,
   - a free slot exists per the derivation (`free == true`),
   - the ticket's branch is not checked out in any worktree
     (`git worktree list --porcelain`, compare branch names case-sensitively),
   - `mb-doc-index` with the DECLARED INTENT reports no active-work collision:

         pwsh <mb-doc-index>/scripts/doc-index.ps1 -Jira <TIKET> -Json .superpowers/doc-index.json

     Exit `2` is a collision and a STOP. **A run that failed (exit 1, or no
     JSON written) is also a STOP** — a check that did not complete is not
     "no collision".
2. **Choose the slot.** Among free slots prefer a detached one, then one whose
   branch name equals its own directory name (the parked shape), then the
   rest. Announce which and why.
3. **Write the intent line** into the epic's ledger section `## Rozjetí`
   (Task 7's convention), commit it with `mb-git-commit` and publish the
   ELABORATION branch. Nothing is written into the slot.
4. **Launch:**

       pwsh <this skill>/scripts/pool-launch.ps1 -SlotPath <slot> -Ticket <TIKET> -Adapter <terminal|direct> -Prompt "<one short line>"

   The prompt is SHORT and one line: what to do, which ticket, and where to
   read the rest. No semicolon (the script refuses one). Shape:

   `Převezmi tiket <TIKET>. Zbytek si najdi v ledgeru epiku <EPIK>, cesta memory-bank/epics/<epic_snake>/ledger.md, sekce Rozjetí.`

   Report the status word in Czech: `launched` → „spuštěno", `unavailable` →
   „adaptér není k dispozici", `failed` → „spuštění selhalo".
5. **Mechanical verification, not a process table.** `Get-Process claude`
   returned a pid in all three measured failures, so process existence proves
   nothing. Re-run `pool-status.ps1` and require a record for that slot with
   `session.state == live`. Either report „sezení potvrzeno" or „**žádné nové
   sezení se neobjevilo — ověř na obrazovce**". Never report „spuštěno" as
   „běží".
6. **Operator questions, as a backstop and not as the only check:** is there
   no `⚠ Transcript saving is off` in the status line, and is the WHOLE prompt
   in the first input? Into Jira the ticket goes as running only after the
   first commit on its branch.

### `attach <TIKET>`

Find the slot holding the ticket and **print** the operator's next action: the
slot path, the command that gets them there, and the session state from
`pool-status.ps1`. Prints; runs nothing on the operator's behalf.

## Quick reference

| Need | Use |
|---|---|
| State of the pool | `pool-status.ps1 -Json <path>` (exit 3 = no pool) |
| Both readiness oracles in one place | `ready <EPIK>` |
| Start a ticket in a slot | `spawn <TIKET>` |
| Where does a ticket run | `attach <TIKET>` |
| Provision a NEW slot | `pool-provision.ps1` — **operator only**, refuses under an agent-session marker |
| Cross-clone collision | `mb-doc-index` with `-Jira` (declared intent); exit 2 = STOP |
| Model for sub-dispatches | contract, "Dispatch Model Policy" |

## Rationalizations (all mean: STOP)

| Excuse | Reality |
|---|---|
| "The collision check errored, so there is no collision" | A check that did not complete is a STOP. Exit 1 is not exit 0. |
| "Occupancy is unknown, but the tree is clean, so it is free" | Unknown is fail-closed. A session that started a minute ago has not reached its pin write yet. |
| "wt.exe is missing, I will use direct instead" | The adapter is the caller's choice. `unavailable` is a report, never a fallback. |
| "I will just tidy that leftover in the slot" | Rule 3. The decision belongs to the user, in the slot where the leftovers lie. |
| "This worktree looks free even without the marker" | A worktree held for release maintenance satisfies every freedom condition. The marker is what prevents that spawn. |
| "The process exists, so the session is running" | All three measured failures had a pid. The registry record with `--name <TICKET>` is the proof. |
```

- [ ] **Step 2: Ověř, že `description` nekoliduje se sousedy**

Triggering řídí výhradně `description`. Vypiš všechna čtyři česká `description` v téže sémantické čtvrti vedle sebe a přečti je jako uživatel:

```bash
grep -h '^description:' ums/.claude/skills/mb-epic-elaboration/SKILL.md ums/.claude/skills/mb-epic-graph/SKILL.md ums/.claude/skills/mb-doc-index/SKILL.md ums/.claude/skills/mb-epic-run/SKILL.md
```

Kontrolní otázka: na kterou z nich se trefí věta „rozjeď mi tiket UMS-1234 do slotu"? Musí to být `mb-epic-run` a jen ono. Když se překrývá s `mb-doc-index` (`kdo na čem pracuje`), zostři formulaci — neškrtej sousedovu.

- [ ] **Step 3: Zapiš skill do `SKILLS_MANIFEST.md`**

Do tabulky `## Aktivní mb-* skilly`, za řádek `mb-doc-index`, vlož:

```markdown
| mb-epic-run | [mb-epic-run/SKILL.md](../mb-epic-run/SKILL.md) | Mechanika poolu: stav slotů (derivovaný, per-worktree), obě orákula připravenosti na jednom místě, spuštění sezení na tiket do volného slotu se strojovým ověřením, a dohledání slotu, který tiket drží |
```

- [ ] **Step 4: Ověř odkazy a spustitelnost cest ze SKILL.md**

Odkazy v Markdownu se rozpouštějí proti adresáři **obsahujícího souboru**, kdežto shellový argument proti pracovnímu adresáři agenta (kořen repozitáře). Zkontroluj obojí zvlášť:

```bash
ls ums/.claude/skills/mb-epic-run/scripts/pool-status.ps1 ums/.claude/skills/mb-epic-run/scripts/pool-launch.ps1 ums/.claude/skills/mb-epic-run/scripts/pool-provision.ps1
ls ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md
```

Placeholder `<this skill>` v PowerShellových příkazech ponech — kontrakt sám ten tvar používá (`pwsh <mb-doc-index>/scripts/doc-index.ps1`) — ale **nepovyšuj ho na definici v kontraktu**; je to lokální konvence skillu.

- [ ] **Step 5: Commit a publikace**

```bash
git add ums/.claude/skills/mb-epic-run/SKILL.md ums/.claude/skills/shared/SKILLS_MANIFEST.md
```

```text
UMS-3488: skill mb-epic-run — čtyři operace nad poolem
 - status renderuje českou tabulku z JSON výstupu pool-status.ps1; exit 3 je fail-closed odmítnutí repozitáře bez poolu
 - ready jen položí vedle sebe epic-graph -Check a ledger-status, žádný verdikt a žádná klasifikace
 - spawn: způsobilost, volba slotu, řádek záměru do ledgeru na elaborační větvi, launch, strojové ověření v session registru, teprve pak operátorské otázky
 - attach tiskne operátorovi cestu ke slotu a stav sezení, nespouští za něj nic
 - železná pravidla: do slotu se nikdy nezapisuje, nedoběhlá kolizní kontrola je STOP, unknown obsazenost není volno, adaptér nikdy nepadá na jiný
 - zápis do SKILLS_MANIFEST.md
```

Pak publikuj větev.

---

### Task 7: Integrace do `mb-epic-elaboration` a řádek záměru v ledgeru

**Files:**
- Modify: `ums/.claude/skills/mb-epic-elaboration/SKILL.md` (fáze 7 a quick-reference)
- Modify: `ums/.claude/skills/mb-epic-elaboration/protocol.md` (§3.3)
- Modify: `ums/.claude/skills/mb-epic-elaboration/ledger-template.md`
- Modify: `ums/.claude/skills/mb-epic-elaboration/scripts/ledger-status.ps1`
- Create: `ums/.claude/skills/mb-epic-elaboration/tests/fixtures/ledger_rozjeti.md`
- Modify: `ums/.claude/skills/mb-epic-elaboration/tests/ledger-status.tests.ps1`

**Interfaces:**
- Consumes: skill `mb-epic-run` z Tasku 6 (jmenuje ho v nabídce).
- Produces: sekci `## Rozjetí` v ledgeru se **šesti** sloupci v tomto pořadí — `Tiket | Datum | Slot | Verdikt | Draft (větev + cesta) | Pasti`. Pořadí je závazné: `Get-SectionTable` indexuje sloupce **pozičně**.

- [ ] **Step 1: Napiš fixturu, která řádek záměru NESE**

„Stávající sada zůstane zelená" se za důkaz nepočítá — je zelená před i po změně a žádný řádek záměru nikdy neuvidí. Vytvoř `tests/fixtures/ledger_rozjeti.md` jako minimální, ale úplný ledger **včetně nové sekce**:

```markdown
# Evidence ledger: UMS-3400 — testovací epic pro sekci Rozjetí

- **Epic:** UMS-3400 (https://datasyscz.atlassian.net/browse/UMS-3400)
- **Režim:** Jira
- **Zdroj položek:** Doc/test.md
- **Založeno:** 2026-09-01
- **Poslední aktualizace:** 2026-09-03 (okno W01)

## Položky

| ID | Popis | Vlastník | Stav | Pozn. |
|----|-------|----------|------|-------|
| E-1 | první položka | UMS-3488 | uzavřená | |
| E-2 | druhá položka | UMS-3496 | otevřená | |

## Členové (proposaly)

| Člen | Stav | Pozn. |
|-------|------|-------|
| UMS-3488 | hotov | |
| UMS-3496 | nezahájen | |

## Okna

| Okno | Agenda (položky + otázky) | Stav | Datum | Výstup |
|------|---------------------------|------|-------|--------|
| W01 | mechanika poolu; položky: E-1, E-2 | uzavřeno | 2026-09-02 | |

## Dirty-set

| Položka/Tiket | Zašpiněno oknem | Důvod | Vyčištěno oknem |
|---------------|-----------------|-------|-----------------|

## Rozjetí

| Tiket | Datum | Slot | Verdikt | Draft (větev + cesta) | Pasti |
|-------|-------|------|---------|-----------------------|-------|
| UMS-3488 | 2026-09-03 | ums05 | rozjeto | UMS-3400-okno-w01 @ memory-bank/proposals/next/design_ums_3488_pool.md | wt.exe není v PATH na stanici B |
| UMS-3496 | 2026-09-03 | — | odloženo | UMS-3400-okno-w01 @ memory-bank/proposals/next/design_ums_3496_brana.md | čeká na UMS-3488 |
```

Poznámka k tvaru: **zvolená báze se do řádku nepíše jako vlastní sloupec.** Návrh ji mezi obsahem řádku jmenuje, ale báze pracovní položky má v tomto modelu jediný domov — řádek `Báze:` v `context.md` toho work itemu, který ji zapíše až vstupní brána sezení ve slotu. Šestý sloupec by byl druhý domov téhož faktu a rozešel by se s ním hned prvním sezením, které si zvolí jinou bázi. Když je báze netriviální, patří do sloupce `Pasti` jako věta, ne jako strukturovaná hodnota. **Zapiš to jako `Ruling:` do ledgeru plánu** — je to odchylka od návrhu, rozhodnutá podle pravidla „jeden fakt, jeden domov".

- [ ] **Step 2: Napiš padající asercie nad novou fixturou**

Do `tests/ledger-status.tests.ps1` přidej **před** `Complete-Tests`:

```powershell
# --- section Rozjetí ---------------------------------------------------------
# The parser ends a table at the first line without a pipe and indexes columns
# POSITIONALLY, so a new section is only proven by a fixture that carries one.
$spawns = Join-Path $PSScriptRoot 'fixtures\ledger_rozjeti.md'
$rs = Invoke-Ledger $spawns
Assert-Eq $rs.Code 0 'a ledger carrying the Rozjetí section parses clean (exit 0)'
Assert-Match $rs.Out '## Rozjet' 'the Rozjetí section is reported'
Assert-Match $rs.Out 'UMS-3488' 'the spawned ticket is listed'
Assert-Match $rs.Out 'ums05' 'the slot is listed'
Assert-Match $rs.Out 'rozjeto' 'the verdict is listed'
Assert-Match $rs.Out 'wt.exe' 'the traps column survives to the report'
# Positional indexing proof: the verdict must come from column 4, not from
# whatever text happens to match elsewhere in the row.
Assert-Match $rs.Out 'UMS-3496.*odlo' 'the second row keeps its own verdict'
# The sections BEFORE it must be unaffected — a new trailing section must not
# swallow the dirty-set or the windows.
Assert-Match $rs.Out '## Položky \(2 celkem\)' 'items still parse'
Assert-Match $rs.Out 'W01' 'windows still parse'
Assert-NotMatch $rs.Out 'Nekonzistence' 'no false inconsistency from the new section'
```

- [ ] **Step 3: Spusť sadu a potvrď selhání**

```bash
pwsh -NoProfile -File ums/.claude/skills/mb-epic-elaboration/tests/ledger-status.tests.ps1
```

Očekávané: `<N>/<M> FAILED`, mezi selhanými `the Rozjetí section is reported`. Asercie o položkách a oknech projdou už teď — regresní zámky.

- [ ] **Step 4: Rozšiř `ledger-status.ps1` o sekci Rozjetí**

Za řádek, kde se čte `$dirty`, přidej čtení nové sekce a její filtr:

```powershell
$spawns  = Get-SectionTable $lines 'Rozjetí'
```

a k existujícím filtrům:

```powershell
$spawns  = @($spawns  | Where-Object { $_.Count -ge 4 -and $_[0] -and $_[0] -notmatch '^<' })
```

Do křížových kontrol přidej jednu, která má co říct — spawn řádek pro člena, který v ledgeru není:

```powershell
# --- spawn rows -----------------------------------------------------------
foreach ($s in $spawns) {
    if (-not $ticketStates.ContainsKey($s[0])) {
        $issuesFound += "Řádek rozjetí pro «$($s[0])» nemá odpovídajícího člena v tabulce $memberHeading."
    }
}
```

A do reportu, za blok Dirty-set:

```powershell
Write-Output "## Rozjetí ($($spawns.Count))"
if ($spawns.Count -eq 0) { Write-Output '- žádné' }
foreach ($s in $spawns) {
    $trap = if ($s.Count -ge 6 -and $s[5]) { " — pasti: $($s[5])" } else { '' }
    Write-Output ("- {0} ({1}): {2}, slot {3}{4}" -f $s[0], $s[1], $s[3], $s[2], $trap)
}
Write-Output ''
```

Umísti blok **před** `## Doporučení dalšího okna`, aby doporučení zůstalo poslední.

- [ ] **Step 5: Doplň konvenci do `ledger-template.md`**

Na konec šablony, za sekci `## Dirty-set`, přidej:

```markdown
## Rozjetí

Jeden řádek na jedno rozjetí tiketu do slotu poolu (skill `mb-epic-run`,
operace `spawn`). Řádek je **tažený** artefakt: sezení ve slotu si podle něj
dohledá zbytek v commitnutých dokumentech — orchestrátor do pracovního stromu
slotu nezapisuje nic. Sloupce **neměnit ani nepřehazovat**, parsuje je
`scripts/ledger-status.ps1` pozičně.

Sloupec `Draft` nese větev i cestu, protože draft může ležet na cizí větvi.
Zvolená báze tu vlastní sloupec **nemá** — jejím jediným domovem je řádek
`Báze:` v `context.md` té pracovní položky; netriviální bázi zmiň větou ve
sloupci `Pasti`.

| Tiket | Datum | Slot | Verdikt | Draft (větev + cesta) | Pasti |
|-------|-------|------|---------|-----------------------|-------|
| <UMS-0000> | <YYYY-MM-DD> | <jméno slotu nebo —> | <rozjeto \| odloženo \| selhalo> | <větev> @ <cesta k draftu> | <krátce, co může překvapit> |
```

- [ ] **Step 6: Spusť sadu a potvrď zeleň**

```bash
pwsh -NoProfile -File ums/.claude/skills/mb-epic-elaboration/tests/ledger-status.tests.ps1
```

Očekávané: `<N> passed`, exit 0. **Spusť ji i proti oběma původním fixturám** (sada to dělá sama) — nová sekce nesmí rozbít legacy ledger bez ní.

- [ ] **Step 7: Negativita parseru**

Odstraň řádek `$spawns = Get-SectionTable $lines 'Rozjetí'` a nahraď ho `$spawns = @()`. Spusť sadu. Očekávané: zčervenají asercie o obsahu sekce; asercie o položkách a oknech zůstanou zeleně (**zámky**). Pak vrať a místo toho **prohoď dva sloupce v šabloně fixtury** (Slot a Verdikt): očekávaně zčervená `the verdict is listed` nebo `the slot is listed` — to je důkaz, že indexace je opravdu poziční a že fixtura ji testuje. Obnov fixturu.

- [ ] **Step 8: Napoj nabídku do `mb-epic-elaboration`**

Jsou to soubory vrstvy, edituje se přímo — žádný overlay.

V `SKILL.md`, v tabulce životního cyklu okna, na konec buňky fáze **7 (Close)**, za část o odkazech na proposaly, přidej:

```markdown
; then OFFER the pool: `mb-epic-run ready` puts both readiness oracles beside the pool table, and for the tickets the operator picks, `mb-epic-run spawn <TIKET>` starts a session in a free slot — an OFFER, one question, the operator decides per ticket, and nothing is spawned without that decision
```

Do quick-reference tabulky přidej řádek:

```markdown
| Rozjetí tiketu do slotu poolu, stav slotů | `mb-epic-run` skill (`ready` / `spawn` / `status` / `attach`); zápis rozjetí je řádek v sekci `## Rozjetí` ledgeru |
```

V `protocol.md` najdi §3.3 (uzávěrka okna) a za krok publikace přidej odstavec ve stejném stylu jako okolní text:

```markdown
After the window's single commit is published, OFFER the pool. `mb-epic-run
ready <EPIC>` prints both existing oracles beside the pool table; it produces
no verdict of its own. For each ticket the operator selects, `mb-epic-run
spawn <TICKET>` runs its own eligibility gate, writes ONE intent line into the
ledger's `## Rozjetí` section on THIS branch, and launches a session in a free
slot. This is an offer and a per-ticket decision, never a batch action, and it
happens AFTER publication because the spawned session pulls the window's
documents from `origin`.
```

- [ ] **Step 9: Ověř číslování a křížové odkazy po vložení**

Vložení kroku posouvá interní odkazy na pořadová čísla, a žádný grep na termín je nenajde. Projdi obojí:

```bash
grep -nEi 'steps? [0-9]|fáze [0-9]|§3\.[0-9]|\bstep\b' ums/.claude/skills/mb-epic-elaboration/SKILL.md ums/.claude/skills/mb-epic-elaboration/protocol.md
grep -nEi '\bšest\b|\bsedm\b|\bseven\b|\bsix\b' ums/.claude/skills/mb-epic-elaboration/SKILL.md ums/.claude/skills/mb-epic-elaboration/protocol.md
```

Nic jsi nečísloval nově, takže očekávané je „beze změny" — ale ověř to čtením, ne předpokladem, a odkazuj na sousední krok **jménem fáze**, ne číslem.

- [ ] **Step 10: Commit a publikace**

```bash
git add ums/.claude/skills/mb-epic-elaboration/
```

```text
UMS-3488: ledger dostal sekci Rozjetí a elaborace nabízí mb-epic-run
 - ledger-template.md: šest pozičně parsovaných sloupců Tiket/Datum/Slot/Verdikt/Draft/Pasti; báze vlastní sloupec nemá, jejím domovem zůstává řádek Báze v context.md
 - ledger-status.ps1 sekci čte, reportuje a hlásí řádek rozjetí bez odpovídajícího člena
 - fixtura ledger_rozjeti.md nese řádek záměru, takže sada novou sekci opravdu vidí; poziční indexace ověřena prohozením sloupců
 - mb-epic-elaboration fáze 7 a protocol §3.3 nabízejí mb-epic-run ready a spawn po publikaci okna, per tiket a jen na rozhodnutí operátora
```

Pak publikuj větev.

---

### Task 8: Past s upstreamem do overlaye `brainstorming`

Oprava u zdroje. `git switch -c X <báze>` nastaví tracking na **chráněnou** bázi a ten příkaz předepisuje overlay pro **každé** sezení, ne jen pro spawnuté — opis do zadání každého spawnu by chránil jen spawnutá sezení a opakoval by to navždy. Kontraktová polovina je hotová z Tasku 1, kroku 9; tady jde jen o overlay.

**Files:**
- Modify: `ums/.claude/skills/shared/overlays/brainstorming.overlay.md`

**Interfaces:**
- Consumes: kontraktový text z Tasku 1, kroku 9 (`git branch --unset-upstream` + první publikace `-u`).
- Produces: nic programového. Fragment se do vendorovaných skillů promítne až revendorem v Tasku 10.

- [ ] **Step 1: Ověř fragment proti KONTRAKTU, ne proti tomuto plánu**

Plán i návrh pravidlo jen parafrázují. Otevři `ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md`, sekci `## Publication Contract`, a přečti odstavec o první publikaci, jak ho Task 1 zapsal. Fragment smí říct „per <jméno sekce>" plus co je čistě lokální; věta parafrázující důvod je budoucí rozchod.

- [ ] **Step 2: Doplň odpojení upstreamu ke kroku vytvoření větve**

V `ums/.claude/skills/shared/overlays/brainstorming.overlay.md` najdi krok 5 (`**Create the ticket branch**`, kolem řádku 116) a za příkaz `git switch -c` doplň:

```markdown
     `git switch -c <TICKET>-<kebab-slug> <chosen base>` after a
     `git fetch origin`, always with the explicit start point, **immediately
     followed by `git branch --unset-upstream`** — `switch -c` left the
     upstream pointing at the (typically protected) base, and until it is
     rewritten every bare push aims there. Both halves of that rule live in
     the contract's Publication Contract, first-publication rule; this is the
     step that performs the first half.
```

- [ ] **Step 3: Sjednoť druhou formulaci ve stejném souboru**

Fragment popisuje vytvoření větve na **dvou** místech (krok 5 a odstavec „The rule that governed that creation" ve fázi Write design doc). Po úpravě jednoho vyhledej druhý a srovnej je **vedle sebe**, ne jen každý proti kontraktu:

```bash
grep -n 'switch -c\|unset-upstream\|push -u' ums/.claude/skills/shared/overlays/brainstorming.overlay.md
```

Do odstavce kolem řádku 164 doplň tutéž větu o odpojení. Odstavec o první publikaci (kolem řádku 182) už `-u` jmenuje — potvrď to a doplň jen odkaz na to, že odpojení proběhlo při vytvoření, aby si čtenář obě poloviny spojil.

- [ ] **Step 4: Projdi ostatní konzumenty téže operace**

Když je stejná chyba rozbitá ve víc než jednom konzumentovi sdíleného kontraktu, oprava patří do kontraktu (to je hotové) a **každý** konzument musí odkazovat, ne parafrázovat. Vypiš je:

```bash
grep -rn 'switch -c' ums/.claude/skills/ | grep -v UMS_MEMORY_BANK_CONTRACT
```

Očekávaní konzumenti: `brainstorming.overlay.md` (opraveno) a `mb-architect-review/SKILL.md` (kolem řádků 131 a 142) plus `mb-park/SKILL.md` (řádky 89 a 268). U každého rozhodni jmenovitě: vytváří-li větev, doplň odkaz na pravidlo jménem sekce; jen-li ho zmiňuje jako pojem, nech být. Rozhodnutí zapiš, ať se příští kolo neptá znovu.

- [ ] **Step 5: Ověř grepem, i case-insensitive**

```bash
grep -n 'unset-upstream' ums/.claude/skills/shared/overlays/brainstorming.overlay.md
grep -ni 'first-publication rule' ums/.claude/skills/shared/overlays/brainstorming.overlay.md
```

Nulový zásah doslovného grepu nehlas jako anchor-miss dřív, než jsi zkusil `grep -ni` — casing v briefu proti casingu ve fragmentu je změřená příčina falešného poplachu.

- [ ] **Step 6: Commit a publikace**

```bash
git add ums/.claude/skills/shared/overlays/brainstorming.overlay.md ums/.claude/skills/mb-architect-review/SKILL.md ums/.claude/skills/mb-park/SKILL.md
```

(Poslední dvě cesty stáhni ze stagingu, pokud je krok 4 rozhodl nechat beze změny.)

```text
UMS-3488: overlay brainstorming odpojuje upstream hned po vytvoření tiketové větve
 - po git switch -c následuje git branch --unset-upstream, protože switch -c nechal tracking na chráněné bázi a bare push by mířil tam
 - obě místa fragmentu popisující vytvoření větve srovnána vedle sebe, ne jen každé proti kontraktu
 - ostatní konzumenti téže operace prověřeni a odkazují na pravidlo jménem sekce, neparafrázují důvod
```

Pak publikuj větev.

---

### Task 9: Dokumentace

**Files:**
- Create: `ums/.claude/skills/mb-epic-run/README.md` (anglicky — vývojářský popis skriptů)
- Create: `ums/docs/pool-rozjeti-tiketu.md` (česky — průvodce operátora)
- Modify: `ums/README.md` (strom adresářů, matice harnessů)

**Interfaces:**
- Consumes: hotová rozhraní všech tří skriptů (Tasky 3–5) a skillu (Task 6).
- Produces: nic programového.

- [ ] **Step 1: Napiš `mb-epic-run/README.md`**

Anglicky, protože popisuje vývojářské nástroje. Obsah: účel skillu jednou větou; tabulka tří skriptů s parametry, exit kódy a testovacími seamy (`-ClaudeCommand`, `-TerminalCommand`); závazný tvar JSON z `pool-status.ps1` (zkopíruj ho z Interfaces Tasku 3 doslova, je to kontrakt mezi skriptem a skillem); a jak spustit sady:

```bash
pwsh -NoProfile -File ums/.claude/skills/mb-epic-run/tests/pool-status.tests.ps1
pwsh -NoProfile -File ums/.claude/skills/mb-epic-run/tests/pool-launch.tests.ps1
pwsh -NoProfile -File ums/.claude/skills/mb-epic-run/tests/pool-provision.tests.ps1
```

Přidej jeden odstavec „What is deliberately NOT here": žádná evidence slotů, žádný démon, žádný nový druh batonu, žádné zápisy do slotu, žádné zápisy do Jiry, adaptéry `vscode`/`deeplink`/`bg` nepostavené.

- [ ] **Step 2: Napiš český průvodce `ums/docs/pool-rozjeti-tiketu.md`**

Pro operátora, česky. Struktura:

1. **Co pool je** — sada linked worktrees, které si operátor založil a označil; jedno sezení na slot.
2. **Jak označit existující sloty** — jednořádkový příkaz na každý:

```powershell
foreach ($s in @('D:\_datasys\ums01','D:\_datasys\ums02','D:\_datasys\ums03','D:\_datasys\ums04')) {
  New-Item -ItemType Directory -Force -Path (Join-Path $s '.superpowers') | Out-Null
  Set-Content -LiteralPath (Join-Path $s '.superpowers\pool-slot') -Value '# UMS pool slot marker.' -Encoding utf8
}
```

3. **Jak založit nový slot** — `pool-provision.ps1 -Path <cesta> -Operator`, a proč se ptá.
4. **Jak rozjet tiket** — `mb-epic-run spawn <TIKET>`, volba adaptéru, a **co po spuštění ověřit na obrazovce**: není tam `⚠ Transcript saving is off` a v prvním vstupu je celý prompt.
5. **Pohodlí stanice** — `wt.exe` musí být v PATH pro adaptér `terminal`; bez něj skript hlásí `unavailable` a nepadá na jiný adaptér.
6. **Co dělat, když se sezení neobjeví** — skill hlásí „žádné nové sezení se neobjevilo"; podívej se na obrazovku, proces sám o sobě není důkaz.
7. **Kolik slot stojí** — naměřeno: slot 7,7 GB / 80 022 souborů, sdílený `.git` 4,4 GB, hlavní klon 27,2 GB / 140 365 souborů; čerstvý slot asi 8 GB.

Odkazy piš **relativně k adresáři obsahujícího souboru** (`../.claude/skills/mb-epic-run/SKILL.md`) a **bez `#fragment` kotev** — sekci pojmenuj slovy.

- [ ] **Step 3: Doplň `ums/README.md`**

V sekci `## Layout` doplň do stromu `mb-epic-run/` se třemi skripty a testy. V sekci `## Harness compatibility` doplň řádek: `mb-epic-run` a kontrakt jsou čistý Markdown a přenesou se; `claude agents --json` je vázané na Claude Code, takže na jiných harnessech **obsazenost slotu není k dispozici** a degraduje **fail-closed** — skill ohlásí, že obsazenost neumí zjistit, a spawn nechá na výslovném pokynu operátora. Guard v `pool-provision.ps1` putuje se skriptem, `permissions.deny` ne.

- [ ] **Step 4: Ověř odkazy**

Odkazy v MB dokumentech i v dokumentaci vrstvy se rozpouštějí proti adresáři obsahujícího souboru a nesmějí nést `#fragment` kotvy. Zkontroluj mechanicky, že každý cíl existuje:

```bash
grep -oE '\]\([^)#]+\)' ums/docs/pool-rozjeti-tiketu.md ums/.claude/skills/mb-epic-run/README.md | sed 's/.*](//; s/)$//' | sort -u
grep -n '](.*#' ums/docs/pool-rozjeti-tiketu.md ums/.claude/skills/mb-epic-run/README.md
```

Druhý grep musí být prázdný (žádné kotvy). Každou cestu z prvního ověř `ls` **z adresáře obsahujícího souboru**, ne z kořene repa.

- [ ] **Step 5: Commit a publikace**

```bash
git add ums/.claude/skills/mb-epic-run/README.md ums/docs/pool-rozjeti-tiketu.md ums/README.md
```

```text
UMS-3488: dokumentace poolu — anglický README skillu a český průvodce operátora
 - README skillu popisuje tři skripty, jejich parametry, exit kódy, testovací seamy a závazný tvar JSON mezi pool-status.ps1 a skillem
 - český průvodce: označení existujících slotů jedním příkazem, založení nového, rozjetí tiketu, co ověřit na obrazovce a naměřená cena slotu na disku
 - ums/README.md doplněn o strom mb-epic-run a o fail-closed degradaci obsazenosti mimo Claude Code
```

Pak publikuj větev.

---

### Task 10: `permissions.deny`, nasazení, revendor a operátorské ověření

Poslední úloha. Nese tři věci, které se nedají udělat dřív: mechanické zakázání worktreí a provisionace, promítnutí změněného overlay fragmentu do vendorovaných skillů, a sweepy, které mají smysl teprve nad hotovým celkem.

**Files:**
- Modify: `ums/.claude/settings.json`
- Modify: nasazená kopie `.claude/` a `.agents/skills/` (netrackované)
- Modify: `ums/.claude/skills/shared/VENDORED_FROM.md` (jen pokud revendor změní zapsaný stav)

**Interfaces:**
- Consumes: všechno z Tasků 1–9.
- Produces: nasazenou, ověřenou vrstvu; žádné nové programové rozhraní.

- [ ] **Step 1: Zakaž provisionaci i mechanicky**

V `ums/.claude/settings.json`, do `permissions.deny`, přidej dva záznamy k existujícím čtyřem:

```json
    "deny": [
      "EnterWorktree",
      "ExitWorktree",
      "Bash(rm -rf:*)",
      "Bash(git reset --hard:*)",
      "Bash(git worktree:*)",
      "PowerShell(pool-provision.ps1:*)"
    ]
```

`Bash(git worktree list:*)` do `allow` **nepřidávej** — deny vyhrává nad allow, takže by to nefungovalo, a `pool-status.ps1` volá git zevnitř `pwsh`, ne přes Bash tool, takže na deny nenaráží. Ověř, že soubor zůstal platný JSON:

```bash
node -e "JSON.parse(require('fs').readFileSync('ums/.claude/settings.json','utf8')); console.log('OK')"
```

- [ ] **Step 2: Obnov nasazenou kopii ZDROJE, teprve pak revendoruj**

Pořadí je závazné: revendor čte overlay fragmenty z **nasazené** kopie (`.claude/skills/shared/overlays/`), takže běh bez předchozí obnovy tiše aplikuje starou verzi a verify pass přesto projde zeleně.

```bash
cp -r ums/.claude/. .claude/
cp -r ums/.claude/skills/. .agents/skills/
diff -rq ums/.claude/skills .claude/skills | grep -v 'Only in .claude/skills' || echo "zdroj a nasazeni se shoduji"
```

`cp -r zdroj cíl/` do existujícího stejnojmenného adresáře **slučuje, nevnořuje** — ověřeno měřením; cizí soubory v cíli přežijí. Před spolehnutím na to ověř `git diff --name-status`, jestli tato větev nenese v `ums/` řádky `D`/`R`; s mazáním nebo přejmenováním by merge-copy nechala v nasazení osiřelý soubor:

```bash
git diff --name-status origin/ums-memory-bank..HEAD -- ums/ | grep -E '^(D|R)' || echo "zadne D/R, merge-copy staci"
```

- [ ] **Step 3: Revendoruj — plný jednoprůchodový běh s pinovaným tagem**

Změnily se **dva** overlay fragmenty (`subagent-driven-development` v Tasku 2, `brainstorming` v Tasku 8), takže vendorované kopie se musí vygenerovat znovu. `-OverlaysOnly` **nepoužívej** — funguje jen na čerstvě vendorované pristine soubory hned po `-NoOverlays`, a nasazené kopie už předchozí overlay bloky nesou.

Revendor běží **v monorepu**, ne v tomto repu, a spouští se **z PowerShellu**, ne z Git Bash (v Git Bashi zdědí msys `tar`, který windowsovou cestu čte jako vzdálený host):

```powershell
pwsh -NoProfile -Command "& 'D:\_datasys\ums\.claude\scripts\revendor-superpowers.ps1' -Tag v6.3.0"
```

Běh je hotový, teprve když skončí `Verification passed.`. **Miss kotvy `ANCHOR-BEFORE` je detektor driftu upstreamu, ne chyba k obejití** — kotvu nikdy neuvolňuj; oprav fragment, synchronizuj zpět do forku a spusť znovu.

Výsledek ověř **cíleným grepem na charakteristický text nové verze**, a když doslovný grep vrátí nulu, zopakuj `grep -ni`, než z toho uděláš STOP:

```bash
grep -n 'required `Instruction:` line' .claude/skills/subagent-driven-development/SKILL.md
grep -n 'unset-upstream' .claude/skills/brainstorming/SKILL.md
```

- [ ] **Step 4: Dorovnej vendorované skilly i v `.agents/skills`**

Revendor cílí jen na `.claude/skills` a sync vendorované skilly nesynchronizuje nikdy, takže Codex kopie tiše zaostane — platí pro tento fork i pro monorepo.

```bash
for d in brainstorming dispatching-parallel-agents executing-plans finishing-a-development-branch receiving-code-review requesting-code-review subagent-driven-development systematic-debugging test-driven-development using-git-worktrees using-superpowers verification-before-completion writing-plans writing-skills; do
  cp -r ".claude/skills/$d/." ".agents/skills/$d/"
done
for d in brainstorming dispatching-parallel-agents executing-plans finishing-a-development-branch receiving-code-review requesting-code-review subagent-driven-development systematic-debugging test-driven-development using-git-worktrees using-superpowers verification-before-completion writing-plans writing-skills; do
  diff -rq ".claude/skills/$d" ".agents/skills/$d" || echo "ROZDIL: $d"
done
```

Očekávané: druhá smyčka bez jediného řádku `ROZDIL`.

- [ ] **Step 5: Sweepy ze sekce 9 návrhu, rozdělené podle vlastníka**

Pět sweepů, každý jiný slovník. **Soubory vrstvy opravuje tento commit; dokumenty Memory Bank jdou harvestu jmenovitým seznamem; `proposals/completed/` se nikdy needituje.**

1. **Bump verze** (vlastní sweep, oddělený od slovníkových):

```bash
grep -rn '2\.12' ums/ memory-bank/ CLAUDE.md
```

   V `ums/` musí být prázdný (Task 1 to zařídil). Zbytek předej harvestu.

2. **Počítací a jedinečnostní fráze** — lámou se přidáním nové instance, ne změnou té popisované, takže je grep na jméno konceptu nenajde:

```bash
grep -rnEi 'jediná|jediný|přesně|nikdy|vždy|žádná výjimka|only|never|always|exactly|single|the one|both|either|no exception' ums/ | grep -Ei 'worktree|slot|pool|provision|baton|instruction|upstream'
```

3. **Věty stojící na měření disku:**

```bash
grep -rnE '16 ?%|25 ?GB|4[.,]1 ?GB|27[.,]2 ?GB|7[.,]7 ?GB|4[.,]4 ?GB' ums/ memory-bank/ CLAUDE.md
```

4. **Inventáře podle DRUHU artefaktu, ne podle jména** — ptej se „kdo počítá nebo vyjmenovává věci tohoto druhu?" a grepuj na jména **sourozeneckých** artefaktů, nikdy na jméno nového:

```bash
grep -rn 'mb-doc-index\|mb-epic-graph\|mb-link-audit' ums/README.md ums/.claude/skills/shared/SKILLS_MANIFEST.md memory-bank/tech.md
grep -rn 'sad\b\|asercí\|počet sad\|settings.json' memory-bank/tech.md
```

   Vlastníkem `memory-bank/tech.md` je harvest — jen vypiš, neopravuj.

5. **Věty o batonu jako o obecném nosiči záměru:**

```bash
grep -rn 'baton' ums/.claude/hooks/session-intent.ps1 ums/.claude/hooks/tests/session-intent.tests.ps1 memory-bank/architecture.md | grep -i 'intent\|záměr\|carrier\|nosič'
```

Výstupem kroku je **jmenovitý předávací seznam pro harvest**, zapsaný do ledgeru plánu: cesta, řádek, a co je na ní po této práci nepravdivé.

- [ ] **Step 6: Spusť CELOU sadu vrstvy po dávkách a získej nová čísla**

Počty asercí nikdy nedopočítávej aritmetikou.

```bash
find ums -name "*.tests.ps1" | wc -l
find ums -name "*.tests.ps1" | sort
```

Pak po dávkách 1–4 souborů, s explicitním timeoutem na dávku:

```bash
for t in ums/.claude/skills/mb-epic-run/tests/pool-status.tests.ps1 ums/.claude/skills/mb-epic-run/tests/pool-launch.tests.ps1 ums/.claude/skills/mb-epic-run/tests/pool-provision.tests.ps1; do echo "== $t"; timeout 300 pwsh -NoProfile -File "$t" || echo "FAILED: $t"; done
```

Součet nech spočítat strojově, nikdy v hlavě:

```bash
… | grep -Eo '^[0-9]+ passed' | awk '{s+=$1} END {print s}'
```

Nové číslo rekonciliuj proti předchozímu (1072 asercí ve 20 sadách, `memory-bank/tech.md`) přes **delty, které jsi sám zavedl** — tedy součty z Tasků 2, 3, 4, 5 a 7. Rozdíl mezi součtem a deltami je nález, ne zaokrouhlení. Čísla předej harvestu spolu se seznamem z kroku 5.

- [ ] **Step 7: Ověř, že nasazení je aktuální OBSAHEM, ne jen existencí**

Kontrola `Contract-Version` plus přítomnost všech `mb-*` adresářů odhalí jen **chybějící** nasazení, ne zastaralé:

```bash
grep -n 'Contract-Version' .claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md
ls .claude/skills | grep '^mb-' | wc -l
ls ums/.claude/skills | grep '^mb-' | wc -l
diff -rq ums/.claude .claude | grep -v 'Only in .claude'
```

Očekávané: `2.13`; obě čísla `mb-*` adresářů stejná a obě o jedna vyšší než před touto prací; `diff -rq` bez rozdílů v souborech, které v obou stromech existují. Čtyři vendorované skilly s overlay bloky se v `ums/` **nenacházejí** — ty srovnávej proti monorepo kopii, ne proti `ums/`.

- [ ] **Step 8: Ověř publikační záruku a precondici zapisovatele — v TOMTO sezení**

Verifikační body 9 a 10 návrhu se pro spawnuté sezení měří až operátorem (krok 9), ale to, že se instalace hooku nerozbila, ověř tady. Syntetický pipe piš **do skriptu a spusť ho jako soubor**, ne jako literál v parametru nástroje — text citující tvar push příkazu nebo únikovou proměnnou blokuje bezpečnostní hlídka nástroje:

```bash
bash .superpowers/verify-hook.sh
```

Skript (zapiš ho nástrojem na zápis souboru) provede obě poloviny self-checku s nastaveným markerem: čtveřici pro chráněnou větev, která musí skončit **nenulově**, a zrcadlovou čtveřici pro tiketovou větev, která musí skončit **nulou a tiše**. Bez druhé poloviny projde jako ověřený i hook, který se vůbec nedá spustit.

- [ ] **Step 9: OPERÁTORSKÉ KROKY — předej je uživateli, nedělej je za něj**

Čtyři body návrhu, které agent provést nemůže. Předlož je jako seznam a čekej.

1. **Označit existující sloty** — jeden příkaz z českého průvodce (Task 9, krok 2). Bez markeru se slot v tabulce vůbec neobjeví, a to je záměr.
2. **Provisionovat NOVÝ slot pro end-to-end** — naměřeno, že **žádný ze čtyř dnešních slotů volný není** (špinavé záznamy: ums01 34, ums02 222, ums03 221, ums04 0; ums04 nese ACTIVE pin; ve třech ze čtyř běželo sezení). Není to volitelný krok:

```powershell
pwsh -NoProfile -File D:\_datasys\ums\.claude\skills\mb-epic-run\scripts\pool-provision.ps1 -Path D:\_datasys\ums05 -Operator
```

3. **End-to-end spawn (verifikační bod 17)** — z orchestrátoru `mb-epic-run spawn <TIKET>` s adaptérem `terminal`; pozorovat, že nové sezení dostalo **celý** prompt, projde vstupní bránu, založí tiketovou větev a aktivuje draft. Pak `mb-epic-run status` musí ukázat slot obsazený a po zápisu pinu ACTIVE se slugem. **Zopakovat s adaptérem `direct`.** Ověření na obrazovce: **není** tam `⚠ Transcript saving is off` a v prvním vstupu je celý prompt. V tom spawnutém sezení navíc zkontrolovat, že `MB_AGENT_SESSION` je nastavený (bod 9) a že `CLAUDECODE` je neprázdný a hook registrovaný, tedy že sezení **smí** napsat vlastní baton (bod 10) — obojí se musí **změřit v tom sezení**, ne dovodit.
4. **A1 ve VS Code extension (verifikační bod 18) — NEBLOKUJÍCÍ.** Čerstvé sezení extension s platným batonem: rozjede první tah samo? Pak totéž v CLI mimo extension jako kontrolní běh, bez kterého nelze selhání přiřadit frontendu. **Oba výsledky zapsat do návrhu před harvestem.** Na poolu to nestojí, takže negativní výsledek položku nezastaví. Pokud Task 2, krok 1 rozhodl, že se A1 nestaví, tento bod odpadá celý — řekni to výslovně.

- [ ] **Step 10: Commit a publikace**

```bash
git add ums/.claude/settings.json ums/.claude/skills/shared/VENDORED_FROM.md
```

(Druhou cestu stáhni ze stagingu, pokud ji revendor nezměnil. Nasazené `.claude/` a `.agents/skills/` jsou **ignorované** — ověř to kódem `!!`, ne jen absencí řádku: `git status --short --ignored=matching -- .claude .agents`.)

```text
UMS-3488: permissions.deny, nasazení vrstvy a revendor overlay fragmentů
 - deny doplněn o git worktree a pool-provision.ps1, takže provisionace je zakázaná i mechanicky, nejen prózou ve skriptu
 - nasazená kopie obnovena ze zdroje před revendorem (revendor čte fragmenty z nasazení), plný jednoprůchodový revendor s pinem v6.3.0, vendorované skilly dorovnány i v .agents/skills
 - sweepy podle slovníku i podle druhu artefaktu; nálezy v dokumentech Memory Bank předány harvestu jmenovitým seznamem, archiv completed nedotčen
 - celá sada vrstvy spuštěná po dávkách, nová čísla asercí naměřená a rekonciliovaná deltami
```

Pak publikuj větev.

---

## Self-Review

Kontrola plánu proti specifikaci, provedená po jeho dopsání.

**1. Pokrytí specifikace.** Každá položka „Pořadí úloh" návrhu má svou úlohu (1→Task 1, 2→Task 2, 3→Task 3, 4→Task 4, 5→Task 5, 6→Task 6, 7→Task 7, 8→Task 8, 9→Task 9, 10→Task 10). Devatenáct verifikačních bodů návrhu má tyto domovy: 1→Task 2 (kroky 2–10); 2→Task 3 (případy 3 a 4 plus negativita v kroku 6); 3→Task 3 (případ 5); 4→Task 3 (případy 1 a 2); 5→Task 3 (případy 6 a 7); 6→Task 4 (případ 2 a negativita v kroku 6); 7→Task 4 (případy 1 a 4, sonda argv); 8→Task 6 (krok `spawn` 5) — **jen instrukčně**, viz mezera níž; 9 a 10→Task 10 (krok 8 pro tento klon, krok 9 bod 3 pro spawnuté sezení); 11→Task 5 (případy 1–4 a negativita v kroku 5); 12→Task 7 (fixtura `ledger_rozjeti.md`); 13, 14, 16→Task 6 (železná pravidla a tabulka racionalizací) — **instrukčně**; 15→Task 3 (případ 1 plus běh proti tomuto forku v kroku 7); 17 a 18→Task 10, krok 9; 19→Task 10, krok 5.

**Jmenovitá mezera, se kterou plán počítá:** body 8, 13, 14 a 16 popisují chování **skillu**, a skill je instrukční Markdown — testovací sada pro něj v této vrstvě neexistuje a plán ji nezavádí. Mechanická polovina těchto bodů žije ve skriptech a testovaná je (`session.state == live` v Tasku 3, exit 3 „bez poolu", exit 2 `unavailable`); polovina, která je úsudkem agenta, je vynucená textem skillu a operátorským krokem 17. Nezastírej to v reportu.

**2. Sken placeholderů.** V plánu není „TBD", „doplň podle potřeby", „ošetři chyby" ani „podobně jako Task N" — kód se opakuje i tam, kde se úlohy podobají, protože implementátor čte úlohy jednotlivě a mimo pořadí. Kde plán rozhoduje něco, co návrh nechal otevřené, je to označené jako rozhodnutí s důvodem: umístění skriptů (File Structure), fail-closed chování prázdného seznamu skillů (Task 2, krok 8), chybějící sloupec s bází v sekci Rozjetí (Task 7, krok 1), a rozdělení kontraktové a overlay poloviny pasti s upstreamem mezi Task 1 a Task 8 (Task 1, úvod).

**3. Konzistence typů a jmen.** Parametry napříč úlohami: `-RepoPath`, `-Json`, `-ClaudeCommand` mají všude stejný význam; `pool-launch.ps1` má navíc `-TerminalCommand`, `pool-provision.ps1` `-Path`/`-Base`/`-Operator`/`-NoFetch`. Exit kódy se nepřekrývají v jednom skriptu a napříč skripty znamenají různé věci **záměrně** (`2` = kolize u `doc-index.ps1`, `2` = `unavailable` u `pool-launch.ps1`, `3` = bez poolu u `pool-status.ps1`, `4` = odmítnuto guardem u `pool-provision.ps1`); skill je proto překládá jménem operace, ne číslem. Jména polí JSON (`free`, `reasons`, `session.state`, `pin.slug`, `progress.path`) jsou v Tasku 3 definovaná a v Tasku 6 se čtou přesně tak. Aserční funkce (`Assert-True`, `Assert-Match`, `Assert-NotMatch`, `Assert-Eq`, `Complete-Tests`) a helpery (`Invoke-PoolScript`, `Set-SlotMarker`, `Set-SlotPin`, `Set-SlotIdle`, `New-SlotLedger`, `Invoke-WithFakeSessionEnv`) jsou definované v Tasku 3 respektive 4 a jinde se jen volají. **Parametr `Invoke-WithFakeSessionEnv` se jmenuje `$EnvBody`, ne `$Body`** — kolize jmen napříč řetězcem wrapperů je změřená příčina přetečení zásobníku.

**4. Poznámka k pořadí.** Task 8 mění overlay fragment, jehož promítnutí do vendorovaných skillů dělá až Task 10 (revendor). Do té doby je fragment zdrojem pravdy, ale nasazený `brainstorming/SKILL.md` starou verzi ještě nese — to je normální stav mezi úlohami, ne nález. Task 2 naproti tomu mění **hook**, který toto sezení skutečně používá, a proto nasazení obnovuje hned (Task 2, krok 12).


