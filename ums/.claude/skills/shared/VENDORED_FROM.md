# Vendored Superpowers skills

- Upstream: https://github.com/obra/superpowers.git (mirror: C:\Users\matejka\source\repos\superpowers)
- Tag: v6.4.2
- Commit: 8ca22dba9a94f28898bbce59f2537ff4d87c747d
- Vendored on top of repo state: 2026-09-29 (by .claude/scripts/revendor-superpowers.ps1)
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
- Excluded:
  diagnosing-superpowers
- Overlays: applied from `shared/overlays/*.overlay.md`; applied blocks are marked
  `<!-- UMS-OVERLAY BEGIN/END -->` inside the vendored files.

## Re-vendor procedure

The tag and the skill set are read from THIS file; the script has no built-in list.

1. Bump the pin in the fork (run from the fork root):
   `pwsh ums/.claude/scripts/revendor-superpowers.ps1 -UmsRoot ums -PinOnly -Tag <new-tag>` rewrites
   this pin from the tag (Tag, Commit, Skills, Excluded) -> commit. An upstream skill this pin does
   not know stops the run: decide it with `-Include <name>` (vendor it) or `-Exclude <name>` (record
   it under Excluded). A skill listed under Excluded stays out until it is passed with `-Include`.
2. Vendor into each deployment target (the sync does this): `pwsh <script> -NoOverlays
   -SkillsRoot <target> -PinSource <fork pin>` vendors exactly the pinned skills, removes skills that
   are in the TARGET's own previous pin but no longer in the new one, deletes present target
   directories of Excluded skills, and writes the target pin. A tag change on a git-tracked target is
   two runs: this one -> commit (vanilla sync), then step 3 -> commit (UMS overlay).
3. `pwsh <script> -OverlaysOnly -SkillsRoot <target>` -> commit (UMS overlay)
4. An `ANCHOR-BEFORE` miss means upstream moved the anchored text - fix the fragment in
   `shared/overlays/` and re-run step 3. Never edit vendored files by hand outside overlay blocks.

Removal of skills that left the pin compares the target's previous pin with -PinSource, so it needs
them to be different files. A run whose -PinSource is the target's own pin (in place) removes
nothing that merely left the pin; it only deletes directories of Excluded skills.

This file pins the VENDORED UPSTREAM version only. The UMS contract has its own,
separate version: `Contract-Version` at the top of `UMS_MEMORY_BANK_CONTRACT.md`,
with the per-version history in shared/CHANGELOG.md.
