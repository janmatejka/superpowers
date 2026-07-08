# UMS Memory Bank integration layer

This directory carries the **UMS Memory Bank v2** integration layer for the
UMS monorepo (`d:\_datasys\ums`, Bitbucket `datasyscz/ums`). It lives only on
the `ums-memory-bank` branch of this fork; `main` stays a clean mirror of
upstream `obra/superpowers`.

**Model:** vendored superpowers skills (v6.1.1) drive the workflow
(`brainstorming → writing-plans → subagent-driven-development →
finishing-a-development-branch`); the Memory Bank is the document/knowledge
layer injected into it. The normative rules are in
[`.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md`](.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md)
(contract v2).

## Layout

```
ums/
├── README.md                 ← this file
├── CLAUDE.md.sample          ← monorepo root CLAUDE.md (user-preference lever)
├── sync-with-monorepo.ps1    ← mirrors the UMS-owned file set fork ⇄ monorepo
└── .claude/
    ├── settings.json         ← Claude Code glue (hooks, permission denies, skillOverrides)
    ├── hooks/deny-superpowers-docs.mjs   ← PreToolUse write-guard (Claude Code)
    ├── scripts/revendor-superpowers.ps1  ← vendors skills/ of THIS repo into the monorepo
    └── skills/
        ├── shared/           ← contract v2, manifest, VENDORED_FROM.md, overlays/*.overlay.md
        ├── mb-harvest/ …     ← active mb-* utility skills
        └── mb-plan/ …        ← deprecated v1 stubs (transitional)
```

The 14 vendored superpowers skill copies are **not** stored here — they are
produced in the monorepo by `revendor-superpowers.ps1` from this repo's
`skills/` tree, then patched with the `shared/overlays/*.overlay.md` fragments
(marked `<!-- UMS-OVERLAY BEGIN/END -->`).

## Upstream merge strategy (the whole point of this branch)

Everything UMS-specific is **additive** under `ums/` — no file outside this
directory is modified on this branch. Upstream therefore always merges clean:

```bash
git fetch vanila --tags
git merge vanila/main          # never conflicts (upstream has no ums/)
```

After merging a new upstream release, redeploy to the monorepo:

```powershell
# in the monorepo (d:\_datasys\ums), two-commit pattern:
pwsh .claude/scripts/revendor-superpowers.ps1 -Tag v6.2.0 -NoOverlays   # commit: vanilla sync
pwsh .claude/scripts/revendor-superpowers.ps1 -OverlaysOnly             # commit: UMS overlay
```

An `ANCHOR-BEFORE` miss during overlay application is the upstream-drift
detector — it enumerates exactly the fragments needing attention. Fix the
fragment in `shared/overlays/`, sync it back here, re-run.

**Rules that keep merges trivial:**

1. Never modify files outside `ums/` on this branch. Improvements meant for
   upstream go to `main`/PRs against `obra/superpowers` instead.
2. Never hand-edit vendored files in the monorepo outside `UMS-OVERLAY`
   blocks; change the fragment and re-apply.
3. The monorepo is the live master copy of this layer; after changing it
   there, run `pwsh ums/sync-with-monorepo.ps1` here and commit.

## Harness compatibility

The superpowers architecture keeps skill content identical across harnesses —
only the bootstrap and tool mapping differ (`docs/porting-to-a-new-harness.md`).
The UMS layer follows the same split:

**Portable (any harness that loads skills):** the contract, the mb-* skills,
the overlay fragments, and the proposal-pair document conventions are plain
markdown — they work wherever superpowers skills load (Claude Code, Codex
native discovery, Cursor, Copilot CLI, Kimi, OpenCode, pi). The mb-* skills
use only git + filesystem + markdown; `mb-jira-update` needs an Atlassian MCP
connection configured per harness.

**Claude Code-specific glue (`.claude/settings.json` + `hooks/`):**

| Mechanism | Claude Code | Other harnesses |
|---|---|---|
| Contract/context injection at session start | SessionStart + PostCompact hooks (`additionalContext`) | Cursor: `hooks-cursor.json` `sessionStart` (schema differs); Codex: no session-start injection — put the "load the contract" rule into the instructions file (`AGENTS.md`); Kimi: manifest `sessionStart`; OpenCode/pi: in-process injection |
| Write-guard for `docs/superpowers/**`, `docs/plans/**` | PreToolUse hook with `permissionDecision: deny` (`deny-superpowers-docs.mjs`) | No shown equivalent — degrade to the contract's Document Placement rule + CLAUDE.md/AGENTS.md preference text (upstream skills honor declared location preferences) |
| Worktree ban | `permissions.deny: EnterWorktree/ExitWorktree` + `skillOverrides: using-git-worktrees: off` | No shown equivalent — degrade to the ban text in the instructions file; `using-git-worktrees` itself honors a declared preference ("work in place") |
| Model routing for subagents | `## Model Routing` in `memory-bank/context.md` consumed per contract | Portable in principle (contract text); effective only where the harness exposes a model parameter on subagent dispatch |

Deploying to a non-Claude harness in the monorepo therefore means: mirror the
`CLAUDE.md.sample` preference block into that harness's instructions file
(`AGENTS.md`, etc.) and accept that the write-guard and worktree denies are
advisory (contract text) rather than mechanical there.

## Deployment to the monorepo from scratch

1. Vendor the skills: `pwsh .claude/scripts/revendor-superpowers.ps1 -Tag <tag> -NoOverlays`
   (script and overlays must already be in the monorepo — step 2 first on a
   brand-new deployment).
2. Copy this layer: `pwsh ums/sync-with-monorepo.ps1 -Direction ToMonorepo`
   (and place `CLAUDE.md.sample` content into the monorepo root `CLAUDE.md`).
3. Apply overlays: `pwsh .claude/scripts/revendor-superpowers.ps1 -OverlaysOnly`.
4. Verify: the script's verification pass must end with `Verification passed.`
