# Vendored Superpowers skills

- Upstream: https://github.com/obra/superpowers.git (mirror: C:\Users\matejka\source\repos\superpowers)
- Tag: v6.1.1
- Commit: d884ae04edebef577e82ff7c4e143debd0bbec99
- Vendored on top of repo state: 2026-07-06 (by .claude/scripts/revendor-superpowers.ps1)
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
