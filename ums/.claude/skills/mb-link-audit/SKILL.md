---
name: mb-link-audit
description: Use when Memory Bank links need verifying or repairing — broken relative paths, anchors (#fragment) that the link conventions forbid, link text that no longer matches its target, absolute paths (kontrola odkazů, rozbité odkazy, kotvy v odkazech, konsolidace odkazů v MB).
license: MIT
metadata:
  author: UMS Project
  version: "1.0"
---

> Follow [UMS_MEMORY_BANK_CONTRACT](../shared/UMS_MEMORY_BANK_CONTRACT.md) —
> especially "Link Conventions" and "Scope Lock".

# Command: mb-link-audit

**Action:** Verify every markdown link in the repository's Memory Banks against
the contract's Link Conventions, and optionally consolidate the mechanically
determinable defects.
**Execution:** Read-only by default. `-Apply` writes; it never touches anything
outside `memory-bank/` trees.

**⛔ GIT PROHIBITION:** no `git commit`/`push` from this skill. Offer
`mb-git-commit` at the end.

**Model selection:** script-driven, not model work. When a residual finding
needs a prose decision, that is ordinary work for the session — not a dispatch.

---

## Workflow

### 1. Audit

```powershell
pwsh <this skill>/scripts/link-audit.ps1 `
  [-RepoPath <repo>] [-Path <subtree>] [-Json <path>]
```

Exit codes: `0` clean · `1` input/script failure · `2` findings exist. Show the
user the printed Czech table verbatim.

### 2. Consolidate

```powershell
pwsh <this skill>/scripts/link-audit.ps1 -RepoPath <repo> -Apply [-IncludeProposals]
```

`-Apply` rescans after each pass and repeats until the scan comes back clean
(max 5 passes), because a fix can uncover a second-order finding — a link whose
fragment hid an equally broken path, or a stale label that only becomes visible
once the path underneath it resolves.

**`proposals/` is excluded from `-Apply` by default.** `proposals/completed/` is
an immutable archive under the contract; pass `-IncludeProposals` only when the
user has asked for the archive to be repaired too, and say so in the report.

### 3. Report and hand over the residue

Print the final table. Every remaining finding is a **prose decision, not a link
fix** — the script marked it `[ODKAZ K OVĚŘENÍ: <dead path>]` in place. Route
those to `mb-sync` or handle them in the session; do not invent a target.

Then offer `mb-git-commit`.

---

## What the classes mean

| Třída | Fix |
|---|---|
| `anchor-inpage` | `[X](#slug)` → `sekce „Nadpis“` |
| `anchor-crossfile` | `[X](f.md#slug)` → `[f.md](f.md), sekce „Nadpis“` |
| `anchor-lines` | `[X](f.cs#L10-L20)` → `[f.cs](f.cs), řádky 10–20` |
| `anchor-unresolved` | fragment matches no heading — link kept, fragment marked |
| `retarget` | broken path with a determinable successor |
| `stale-label` | link text is a bare `*.md` name differing from the target |
| `absolute-path` | drive-qualified/root-anchored path made relative |
| `ambiguous` / `unresolved` | no determinable target — delinked and marked |

## Notes

- **Why anchors go.** Heading slugs are renderer-specific: Bitbucket Cloud,
  GitHub and IDE preview each generate a different one, so an anchor that
  resolves in one viewer silently dead-ends in the others. The section title is
  stable everywhere. The script's GitHub-style slug map exists ONLY to resolve
  an existing anchor back to its heading text so it can be removed — never to
  author one.
- **The intent gate is the load-bearing safety rule.** When a broken path
  pointed INSIDE the document's own project and nothing is there, the file was
  dropped from that project; retargeting the sentence at a same-named file in a
  DIFFERENT project would silently change what it claims. Those are marked, not
  rewritten — even when exactly one same-named file exists repo-wide. Intent is
  read from the Memory Bank root, not the document's own directory: a doc under
  `proposals/<state>/` sits two levels deeper, so a doc-relative reading would
  mis-classify nearly every sibling reference as intra-project.
- **Wrong depth is the dominant defect in `proposals/`.** Links there were
  typically written relative to the MB root while the document lives two levels
  below it. R1 re-resolves the same relative path against the MB root, the
  project root and the repo root, and accepts the result only when those bases
  agree on ONE existing path. The rewrite is then emitted relative to the
  document — the roots are a hypothesis about the author's base, never an
  output form.
- **Do not verify links by fetching Bitbucket URLs.** Its SPA answers `HTTP 200`
  with an identically sized shell for paths that do not exist, so a status-code
  check proves nothing (confirmed by probing a deliberately bogus path). Verify
  on disk — which is what this script does — or navigate and inspect the
  rendered page.
- **Encoding is preserved.** The file is split so each line keeps its own
  terminator and a UTF-8 BOM is written back when it was there, so a one-word
  change cannot turn into a whole-file CRLF/BOM diff.
- Fenced code blocks are skipped on both sides — a link inside ``` is an
  example, and a `#` line inside one is not a heading.
- Scope: `**/memory-bank/**/*.md`, excluding `.git`, `DistOut`, `node_modules`,
  `bin`, `obj`, `packages`. Use `-Path` to narrow it.
