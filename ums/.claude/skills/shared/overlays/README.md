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

Between the anchor line and the body, a fragment may carry any number of
assertion directives:

```
<!-- ASSERT: <exact line text> -->
```

Each must match exactly one line of the target file (same `TrimEnd()`
comparison as `ANCHOR-BEFORE`). A miss is a hard error — this is how an
`ANCHOR: EOF` fragment still detects upstream drift: assert the upstream
sentences the overlay's semantics stand on, and the next upstream change to
them fails the re-vendor loudly instead of applying cleanly.

## Several fragments for one target

A target file may be overlayed by more than one fragment — typically a small
header pointer block plus the body block. Fragments with the same `TARGET` are
grouped and applied in alphabetical (ordinal) order of their file names, each
against the file as the previous fragment left it, so its `ANCHOR-BEFORE` and
`ASSERT` lines are matched against that intermediate text. Name them so the
order is the one you want: `alpha.overlay.md` sorts before
`alpha.pointer.overlay.md`, so the body is appended first and the pointer is
inserted second. A pointer fragment can therefore `ASSERT` a line of the body
that must already be there.

The "target already carries an overlay block" (pristine file) check runs once
per target, before its first fragment, and fails with one message for the
target — never once per fragment.

## Header pointer block

Claude Code re-injects only the first ~5,000 tokens of a skill after
compaction. A body block appended at the end of a long `SKILL.md` falls behind
that cut, so every overlayed skill carries a short pointer block near the top
— `ANCHOR-BEFORE` the skill's H1 heading, in a fragment named
`<skill>.pointer.overlay.md`. The verification step of the re-vendor script
requires the first `UMS-OVERLAY BEGIN` of every overlayed `SKILL.md` to start
within the first 12,000 characters (`Test-UmsOverlayPointerPosition`) and
fails otherwise. The count of applied blocks must equal the count of
fragments.
