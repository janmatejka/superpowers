# Jira (ticket text, links, permalinks)

Part of contract 3.x — the core is ../UMS_MEMORY_BANK_CONTRACT.md; cite as (contract/jira.md, "Permalink").

## Ticket description template

A ticket description is a FRAME; the detail lives in `design_<slug>.md` (proposals/next/ before activation). The Czech artifact, written verbatim:

    **Cíl**

    <do pěti vět: co se mění a proč>

    **Rozsah**

    Dovnitř:
    - <odrážky>

    Ven:
    - <odrážky>

    **Závislosti**

    <jen věty odkazující na linky; linky jsou pravda, próza je proč>

    **Návrh (design):** [design_<slug>.md](<commit-pinned permalink>)
    — or the sentence „vznikne v brainstormingu na tiketové větvi; odkaz doplní řešitel po commitu" while no commit exists.

    **Ověření**

    <do tří řádků>

## Description budget

2 500 characters. `Test-UmsJiraDescription.ps1 -RequireSections` runs before every description write; a finding is a STOP with the findings shown to the user. Doklad: doklad/jira.md, "Ticket sizes in UMS-3517".

## Link rules

- Link text never contains backticks; bold never wraps a code span; no angle brackets outside links. Jira's markdown normalisation drops the link or splits the bold otherwise. Doklad: doklad/jira.md, "Measured normalisation".
- Every link to a git object is commit-pinned and reachable on origin (contract, "Publication Contract").

## Read-back verification

After every write of a description or comment, read it back (`responseContentFormat: markdown`) and verify each link and each bold survived; text authored in a file is compared by diff (mb-jira-update §7b-1). A mismatch is reported, never patched blind.

## Permalink

The URL shape has ONE home: `Get-UmsPermalink.ps1` (template `permalinkTemplate` from ums-repo.json with `{sha}` and `{path}`, else derived from the origin host: bitbucket.org → `src/{sha}/{path}`, github.com → `blob/{sha}/{path}`; an unknown host is a STOP asking the user). No skill spells a host.

## Description mirrors carry a fetch stamp

A local mirror of a ticket description (`.superpowers/jira-desc/<TICKET>.md`) carries `Fetched: <ISO-8601 UTC>` on its first line; a mirror older than the ticket's `updated` field is re-fetched before use. Doklad: doklad/jira.md, "Stale mirror after compaction".
