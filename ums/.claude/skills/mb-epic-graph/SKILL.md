---
name: mb-epic-graph
description: Use when you need a Jira epic's dependency view (the wave table for the epic description, or a Mermaid flowchart on request) or a consistency check between ticket prose, proposals and Jira links — e.g. "vygeneruj graf závislostí", verifying blokováno/blokuje/souvisí/vyčleněno claims, closing an elaboration window, or auditing an epic for missing/asymmetric links.
license: MIT
metadata:
  author: UMS Project
  version: "1.3"
---

# Command: mb-epic-graph

**Action:** Generate the epic dependency graph FROM Jira links (or, in
JIRA-less mode, from proposal header fields) — never from prose or by hand —
and run the prose↔links consistency oracle.
**Execution:** Read-only towards Jira/proposals and git. The only writes are
the report files you explicitly choose.

Works for ANY epic (parameterized by epic key). Companion of
`mb-epic-elaboration` (used at window open for context and at window close as
the exit gate), also usable standalone.

## Režimy

- **Jira** (default): uzly = tikety, hrany = Jira linky; workflow níže platí beze změny.
- **Proposals** (JIRA-less): uzly = proposal dokumenty (slug), hrany = hlavičková
  pole `Blokováno:`/`Blokuje:`/`Souvisí:`/`Vyčleněno z:`/`Vyčleněno do:` s markdown
  odkazy na sourozenecké proposaly. Zdroj režimu: `context.md` (`Jira: (bez tiketu)`
  nebo chybějící Atlassian MCP → Proposals), případně vynuceno `-Source Proposals`.

V režimu Proposals se **krok 1 (fetch snapshot) vynechává** — místo něj se skriptu
předá `-ProposalPath` na složku/soubory členů epiku.

## Workflow

### 1. Fetch a snapshot (Jira read tools only)

Use the session's Atlassian/Jira MCP READ tools. One JQL search covering the
epic and its children, with links and markdown descriptions:

- JQL: `key = <EPIC> OR parent = <EPIC>`
- fields: `["summary","status","issuetype","issuelinks","description","parent"]`
- responseContentFormat: `"markdown"` (the script also parses ADF, but
  markdown is cheaper)

Save the tool's JSON result AS-IS to a snapshot file in your session
scratchpad (large results are auto-saved to a `tool-results` file — pass that
path directly; small results: write the JSON to a file yourself). Accepted
shapes: `{issues:{nodes:[…]}}`, REST `{issues:[…]}`, bare issue array, single
issue. Multiple files merge — fetch external blockers reported by the check
(e.g. `key in (UMS-2884, …)`) into a second file when you want them fully
labeled.

Do NOT transform, filter, or summarize the JSON — the script normalizes it.

### 2. Generate + check

```powershell
# Jira (výchozí):
pwsh <this skill>/scripts/epic-graph.ps1 `
  -InputFile <snapshot.json>[, <externals.json>] `
  -EpicKey <EPIC> -Check `
  [-ProposalPath <component>/memory-bank/proposals/next[, …]] `
  [-ProjectKeys UMS[, …]] `
  [-Mermaid] [-IndentedList] [-NoStatus] `
  [-JiraBaseUrl https://datasyscz.atlassian.net] `
  [-OutFile <MB_ROOT>/memory-bank/epics/<epic_snake>/graph.md]

# JIRA-less (nad proposaly):
pwsh <this skill>/scripts/epic-graph.ps1 `
  -Source Proposals `
  -ProposalPath <MB>/proposals/next[, <další cesty>] `
  -EpicKey <epic_slug> -Check `
  [-Mermaid] [-IndentedList] [-NoStatus] `
  [-OutFile <MB_ROOT>/memory-bank/epics/<epic_snake>/graph.md]
```

- Default output = the **wave table** (`## Tabulka vln`) + (with `-Check`) the
  consistency oracle. The wave table is what goes into the epic description
  (JIRA-less: do přehledového dokumentu epiku).
- `-Mermaid`: also emit the Mermaid flowchart (off by default — generate it
  only when explicitly asked). It is the only view that shows
  `souvisí`/`vyčleněno` edges.
- `-IndentedList`: also emit the legacy indented list (off by default;
  superseded by the wave table).
- `-JiraBaseUrl`: base for the clickable ticket links in the wave table
  (default `https://datasyscz.atlassian.net`; a per-issue `webUrl` in the
  snapshot wins). Jira mode only — in Proposals mode keys are not linked.
- `-Source`: `Jira` (výchozí) nebo `Proposals`; volí, odkud se berou uzly a
  hrany. `Jira` vyžaduje `-InputFile`; `Proposals` vyžaduje `-ProposalPath`.
- `-ProposalPath`: v Jira režimu doplňuje prose-check o lokální
  preliminary proposaly (atribuce přes jejich `**Jira:**` hlavičku nebo
  slug) a sytí stavový glyph tabulky vln: tiket s živým proposalem
  (`next/` nebo `active/`) se čte jako „návrh hotov"; bez `-ProposalPath`
  glyph degraduje na ✅/🔨/▶️/⛔. V Proposals režimu je to **primární zdroj
  uzlů** — skript enumeruje členy epiku jako `proposal_*.md` pod touto
  cestou (indexní soubor typu `_prehled.md` uzlem není); dvojice
  `proposal_x.md` + `proposal_x-design.md` se sloučí do jednoho uzlu (slug).
- `-NoStatus`: suppress the per-ticket status glyph (see below); by default the
  wave table leads each ticket with one merged status symbol.
- `-ProjectKeys`: extra project prefixes for mention detection (defaults to
  prefixes seen in the snapshot; finding IDs like `WF-6` are ignored by
  design).
- Exit codes: `0` OK · `1` input/script failure · `2` consistency errors
  (CHYBA findings) — treat `2` as a failed gate. Které findings jsou CHYBA
  závisí na režimu: v **Jira** režimu chybějící linky, **asymetrické linky**
  a cykly. V **Proposals** režimu bránu shodí jen `CHYBĚJÍCÍ CÍL`,
  `PROSE BEZ ODKAZU` a `CYKLUS`; `ASYMETRICKÝ ODKAZ`, `ODKAZ BEZ PROSE` a
  `TYP ODKAZU NESOUHLASÍ` jsou jen `VAROVÁNÍ` a `-Check` nezhazují —
  symetrie deklarací tedy pro průchod v Proposals režimu není nutná.

### 3. Use the outputs

- **Wave table** (Czech, default): paste it into the epic description's graph
  section (JIRA-less: do přehledového dokumentu), replacing the previous
  GENERATED section wholesale. Columns are
  dependency waves (longest `Blocks` chain from a root; wave 0 = unblocked), so
  every child sits to the RIGHT of its blocker; `←NNNN` marks the direct
  blocker. Rows are ordered by dependency — each ticket lands on the first free
  row right after its last-placed blocker (roots first, biggest stream first).
  Each ticket is prefixed by two inline markers, in this order: first a
  **status glyph**, then the **stream emoji**. The status glyph merges Jira
  status category, blocker readiness and proposal existence into ONE symbol —
  ✅ done · 🔨 in progress · ▶️ ready to implement (proposal + unblocked) ·
  ⏳ proposal ready but still blocked · 🆕 ready to elaborate (unblocked, no
  proposal) · ⛔ blocked — where "unblocked" = every `Blocks` blocker is done
  (an external/unknown-status blocker counts as blocking; external tickets get
  no glyph). In Proposals mode the glyph comes from the proposal stage
  (`completed/` = ✅, `active/` = 🔨, `next/` = ▶️/⏳ by readiness). It uses a
  symbolic family deliberately distinct from the
  square/circle stream palette; suppress it with `-NoStatus`.
  A stream emoji is inline before each ticket (no separate column): the emoji
  marks the primordial ancestor (foundational root) the ticket descends from,
  assigned dynamically from a palette per root that has descendants — a ticket
  depending on several foundational roots carries several emoji; standalone
  tickets get ⬜. The legend under the table is generated from the actual roots.
  Full ticket titles (incl. the `[component]`) are shown verbatim, not
  truncated; ticket keys are clickable Jira links (Jira mode). Only `Blocks`
  drives the columns and the streams — for `souvisí`/`vyčleněno` add
  `-Mermaid`. Never
  hand-edit, reorder, or "curate" it — a wrong edge means a wrong LINK: propose
  the link fix to the user, sync Jira, refetch, regenerate.
- **Mermaid flowchart** (`-Mermaid`, on request): the full graph with all edge
  types; use it when a reviewer wants the visual topology, not for the epic
  description (it does not render everywhere).
- **Consistency findings** (Czech): each is a decision candidate for the
  user, not something to silently "fix" in prose:
  - `PROSE BEZ LINKU` (Proposals: `PROSE BEZ ODKAZU`) — prose asserts a
    dependency, no matching link → add the link or correct the prose
    (human decides which is right).
  - `TYP LINKU NESOUHLASÍ` (Proposals: `TYP ODKAZU NESOUHLASÍ`) — prose
    direction/type differs from the link.
  - `LINK BEZ PROSE` (Proposals: `ODKAZ BEZ PROSE`) — link exists but no
    prose anywhere explains WHY.
  - `ASYMETRICKÝ LINK` (Proposals: `ASYMETRICKÝ ODKAZ`) — one endpoint lists
    the link, the other does not (corrupt data or partial snapshot). V
    režimu Proposals jde jen o `VAROVÁNÍ` — jednostranná deklarace stačí,
    hrana v grafu existuje, jakmile ji deklaruje alespoň jedna strana.
  - `CYKLUS` — Blocks cycle; always an error.
  - `EXTERNÍ TIKET` (Proposals: `EXTERNÍ CÍL`) — dependency outside the
    snapshot/`-ProposalPath` (info; v Jira režimu lze cíl volitelně
    dofetchnout do druhého input souboru).
  - `CHYBĚJÍCÍ CÍL` (jen Proposals) — hlavička odkazuje na proposal soubor,
    který v `-ProposalPath` neexistuje (chyba).
  - `TIKET BEZ ODKAZU NA PROPOSAL` (jen Jira) — a proposal is attributed to the
    ticket (via its `**Jira:**` header) but the ticket description does not
    reference the proposal file → add/refresh the `**Návrh (proposal):**`
    commit-pinned link (VAROVÁNÍ; needs `-ProposalPath`). VAROVÁNÍ, not CHYBA,
    on purpose: a commit-pinned link cannot exist before the window's commit,
    so a hard gate would deadlock the close — the workflow refreshes links
    post-commit.
  - `ODKAZ NA NEEXISTUJÍCÍ PROPOSAL` (jen Jira) — the description links a
    `proposal_*.md` not among the known proposals (renamed/moved/deleted) →
    refresh it (VAROVÁNÍ; needs `-ProposalPath` covering the relevant stages,
    else it may misfire on proposals that live in a stage you did not pass).
- The prose scan is a precision-tuned heuristic (line-bounded keyword
  windows; quoted meta-mentions like `(dříve „blokuje")` are skipped) — read
  each finding before acting on it.

## Edge semantics (canonical, Mermaid mapping)

The wave table uses **only `Blocks`** (columns = waves). The Mermaid flowchart
(`-Mermaid`) shows every edge type:

| Jira link | Graph edge | Meaning |
|-----------|-----------|---------|
| `Blocks` (A blocks B) | `A --> B` | A must be done first; A "odemyká" B |
| `Issue split` (A split to B) | `A -. vyčleněno .-> B` | B was split out of A |
| `Relates` | `A -.- B` (undirected) | souvisí |
| other types | labeled directed edge | as named |

V režimu Proposals nahrazuje levý sloupec hlavičkové pole proposalu
(`this` = proposal s hlavičkou, `target` = odkazovaný sourozenec):
`Blokuje: target` → `this --> target`, `Blokováno: target` →
`target --> this`, `Vyčleněno z: W` → `W -. vyčleněno .-> this`
(this byl vyčleněn z W), `Vyčleněno do: V` → `this -. vyčleněno .-> V`
(V byl vyčleněn z this), `Souvisí: target` → nesměrovaná hrana
`this -.- target`. Hrana v grafu vzniká, i když ji deklaruje jen jedna
strana páru (viz `ASYMETRICKÝ ODKAZ` výše).

## Common mistakes

- Drawing the graph from the epic description or ticket prose — prose is the
  WHY, links are the WHAT; the old hand-drawn graph in an epic description is
  exactly what this tool replaces.
- Analyzing the snapshot ad hoc in context instead of running the script —
  slow, expensive, and each run invents a new output shape; the committed
  `graph.md` must stay diffable between windows.
- Calling Jira write tools from this workflow — link fixes are proposed to
  the user and executed by the elaboration closure step, never by this skill.
- Feeding the script a hand-edited snapshot to make the check pass.
- V režimu Proposals ruční přepisování hlavičkových polí
  (`Blokováno:`/`Blokuje:`/`Souvisí:`/`Vyčleněno z:`/`Vyčleněno do:`) bez
  spuštění kontroly — findings jsou rozhodovací kandidáti pro člověka, ne
  něco, co se má potichu "opravit" jen v prose.
- Zaměňovat `-Source Jira` a `-Source Proposals` požadavky na vstup —
  Jira režim bez `-InputFile` a Proposals režim bez `-ProposalPath`
  neproběhnou.
