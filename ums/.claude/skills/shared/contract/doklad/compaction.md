# Doklad — Compaction and overlaid skills
Part of contract 3.x — evidence read on demand, never the home of a rule.

## The 5,000-token re-injection cap

**What Claude Code documents.** The page "Explore the context window",
section "What survives compaction"
(https://code.claude.com/docs/en/context-window, read 2026-09-29), lists in its
table of mechanisms:

> Invoked skill bodies | Re-injected, capped at 5,000 tokens per skill and
> 25,000 tokens total; oldest dropped first

and, directly below the table:

> Skill bodies are re-injected after compaction, but large skills are truncated
> to fit the per-skill cap, and the oldest invoked skills are dropped once the
> total budget is exceeded. Truncation keeps the start of the file, so put the
> most important instructions near the top of `SKILL.md`.

The same page's timeline says it once more: "After `/compact`, Claude Code
re-injects the body of each skill you invoked, capped at 5,000 tokens per
skill."

**Where the overlays stand.** Every overlay block is anchored at or near the
END of its skill. Sizes are ESTIMATES — characters divided by 3.5, taken during
the design of the v6.4.2 upgrade — not tokenizer counts:

| Skill | Whole file | Overlay block starts at | Consequence |
|---|---|---|---|
| `subagent-driven-development` | ~12.3k tokens | ~9.2k | the whole block lies past the cap |
| `finishing-a-development-branch` | ~10k | ~0.8k | ~9.2k of overlay, most of it past the cap |
| `brainstorming` | ~9.7k | ~4.4k | almost all of the block past the cap |
| `writing-plans` | ~2.9k | ~1.9k | fits |
| `executing-plans` (v6.4.2) | ~5.8k for the upstream text alone | — | a block at its end lies wholly past the cap |

The `executing-plans` figure was re-measured against
`git show v6.4.2:skills/executing-plans/SKILL.md` (20,248 characters → ~5.8k).

**The direction of truncation.** The design of this change recorded the
direction as undocumented; the page quoted above documents it — "Truncation
keeps the start of the file". Under the documented behaviour the block at the
end is exactly what a compaction drops, while a pointer placed right after the
frontmatter is exactly what it keeps.

**Why a pointer plus the block covers both directions anyway.** The layer does
not rely on the documented direction alone: it is one sentence of product
documentation, not a contract, and a change to "keep the end" would silently
invert the failure. With a short pointer at the start and the block at the
end, a kept start carries the pointer — which sends the model to read the block
from the file — and a kept end carries the block itself. Either way the binding
text is reachable after one read.

**What neither covers.** A skill DROPPED from the re-injection — the oldest ones
once the 25,000-token total is exceeded — carries neither the pointer nor the
block. That case is left to the post-compaction instruction the
`contract-inject` hook adds to the model's context, and to the operator
re-invoking the skill; a fresh session started through the Session Intent Baton
is not affected, because it invokes the skill anew and reads the whole
`SKILL.md`.
