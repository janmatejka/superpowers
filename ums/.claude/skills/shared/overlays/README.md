# UMS overlay fragments

Each `*.overlay.md` file here is one overlay block that
`.claude/scripts/revendor-superpowers.ps1` inserts into a vendored Superpowers
skill file. Vendored files must never be edited by hand outside the applied
`<!-- UMS-OVERLAY BEGIN/END -->` blocks — edit the fragment here and re-apply
with `-OverlaysOnly` instead.

## Fragment format

```
<!-- TARGET: <skill-dir>/<file> -->
<!-- ANCHOR: EOF -->                        (append at end of the target file)
   — or —
<!-- ANCHOR-BEFORE: <exact line text> -->   (insert before that exact line)

<!-- UMS-OVERLAY BEGIN (ums-memory-bank v2) -->
...block content...
<!-- UMS-OVERLAY END -->
```

An `ANCHOR-BEFORE` line must match exactly one line of the target file.
A miss is a hard error — that is the upstream-drift detector: after a
re-vendor to a new tag, every failing anchor points at an overlay block that
needs human attention.
