# Vendored Superpowers skills

- Upstream: https://github.com/obra/superpowers.git (mirror: C:\Users\matejka\source\repos\superpowers)
- Tag: v6.2.0
- Commit: 3dcbd5c4b48e02263fbf4a3c01e3fe4f81d584d9
- Vendored on top of repo state: 2026-07-24 (by .claude/scripts/revendor-superpowers.ps1)
- Skills:
  brainstorming
  dispatching-parallel-agents
  executing-plans
  finishing-a-development-branch
  receiving-code-review
  requesting-code-review
  subagent-driven-development
  systematic-debugging
  test-driven-development
  using-git-worktrees
  using-superpowers
  verification-before-completion
  writing-plans
  writing-skills
- Overlays: applied from `shared/overlays/*.overlay.md`; applied blocks are marked
  `<!-- UMS-OVERLAY BEGIN/END -->` inside the vendored files.

## Re-vendor procedure

1. `pwsh .claude/scripts/revendor-superpowers.ps1 -Tag <new-tag> -NoOverlays` -> commit (vanilla sync)
2. `pwsh .claude/scripts/revendor-superpowers.ps1 -OverlaysOnly` -> commit (UMS overlay)
3. An `ANCHOR-BEFORE` miss means upstream moved the anchored text - fix the fragment in
   `shared/overlays/` and re-run step 2. Never edit vendored files by hand outside overlay blocks.
