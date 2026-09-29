# Builds a throwaway fork + monorepo pair for the sync tests. Everything lives
# in OS temp; nothing outside it is touched (no live monorepo, no user profile).
#
#   Fork    git repo shaped like the real fork: upstream-style root files
#           (.gitignore ignoring .claude/, CLAUDE.md, AGENTS.md, a tracked
#           .agents/plugins/marketplace.json), skills/ with tags t1 and t2 (the
#           SAME history as the revendor fixture: t1 = alpha, beta, sdd;
#           t2 = beta gone, gamma new) and the layer under ums/.
#   ForkUms <Fork>\ums: .gitignore (!.claude/), CLAUDE.md.sample,
#           sync-with-monorepo.ps1 and revendor-superpowers.ps1 copied from the
#           working tree, and .claude/ with settings.json, shared/ (pin at t2,
#           contract stub, overlays/ = the two revendor-fixture fragments for
#           alpha), mb-demo, and hooks/ (only an install-git-hooks.ps1 stub -
#           the sync copies hooks as they are, it needs nothing else here).
#   Mono    git repo with a LOCAL bare origin (MonoBare, cloned from Mono, so
#           no push is needed): CLAUDE.md, .claude/settings.json and a TRACKED
#           .claude/skills/ deployed at t1 - shared/ (pin t1, the same
#           overlays), alpha, beta and subagent-driven-development.
#
# Dot-source this file, call New-SyncFixture, remove the result with
# Remove-SyncFixture. The returned hashtable also carries Root (the temp
# directory holding everything), T1Commit and T2Commit.

. (Join-Path $PSScriptRoot '..\.claude\scripts\tests\new-revendor-fixture.ps1')

function New-SyncFixturePin([string] $Tag, [string] $Commit, [string[]] $Skills) {
    return ("# Vendored Superpowers skills`n`n" +
        "- Upstream: https://github.com/obra/superpowers.git`n" +
        "- Tag: $Tag`n" +
        "- Commit: $Commit`n" +
        "- Vendored on top of repo state: 2026-01-01 (by .claude/scripts/revendor-superpowers.ps1)`n" +
        "- Skills:`n" + (($Skills | ForEach-Object { "  $_" }) -join "`n") + "`n" +
        "- Excluded:`n" +
        "- Overlays: applied from ``shared/overlays/*.overlay.md``; applied blocks are marked`n" +
        "  ``<!-- UMS-OVERLAY BEGIN/END -->`` inside the vendored files.`n")
}

function New-SyncFixture {
    $ums = Split-Path -Parent $PSScriptRoot   # the working tree's ums/

    # Skills history (t1, t2) from the revendor fixture; its own UMS root is not needed.
    $rv = New-RevendorFixture
    Remove-Item -Recurse -Force -LiteralPath $rv.UmsRoot
    $root = $rv.Root
    $fork = $rv.SpRepo
    $t1 = $rv.T1Commit
    $t2 = (Invoke-FxGit $fork @('rev-parse', 't2^{commit}')) | Select-Object -First 1

    # ---- Fork: upstream-style root files + the layer under ums/
    Write-FxFile (Join-Path $fork '.gitignore') ".claude/`n"
    Write-FxFile (Join-Path $fork 'CLAUDE.md') "# fork CLAUDE.md (manual)`n"
    Write-FxFile (Join-Path $fork 'AGENTS.md') "# fork AGENTS.md (upstream)`n"
    Write-FxFile (Join-Path $fork '.agents/plugins/marketplace.json') "{}`n"

    $forkUms = Join-Path $fork 'ums'
    Write-FxFile (Join-Path $forkUms '.gitignore') "!.claude/`n"
    Write-FxFile (Join-Path $forkUms 'CLAUDE.md.sample') "## Memory Bank contract`n`nFixture sample block.`n"
    Copy-Item -LiteralPath (Join-Path $ums 'sync-with-monorepo.ps1') -Destination (Join-Path $forkUms 'sync-with-monorepo.ps1')
    $forkClaude = Join-Path $forkUms '.claude'
    New-Item -ItemType Directory -Force (Join-Path $forkClaude 'scripts') | Out-Null
    Copy-Item -LiteralPath (Join-Path $ums '.claude\scripts\revendor-superpowers.ps1') `
        -Destination (Join-Path $forkClaude 'scripts\revendor-superpowers.ps1')
    Write-FxFile (Join-Path $forkClaude 'settings.json') "{}`n"
    $forkShared = Join-Path $forkClaude 'skills/shared'
    Write-FxFile (Join-Path $forkShared 'VENDORED_FROM.md') (New-SyncFixturePin 't2' $t2 @('alpha', 'gamma', 'subagent-driven-development'))
    Write-FxFile (Join-Path $forkShared 'UMS_MEMORY_BANK_CONTRACT.md') "# contract stub`n`nContract-Version: fixture`n"
    Add-RevendorFixtureOverlays (Join-Path $forkShared 'overlays')
    Write-FxFile (Join-Path $forkClaude 'skills/mb-demo/SKILL.md') "---`nname: mb-demo`n---`n# mb-demo`n"
    Write-FxFile (Join-Path $forkClaude 'hooks/install-git-hooks.ps1') "param([string] `$RepoRoot, [string] `$SourceDir)`nexit 0`n"

    Invoke-FxGit $fork @('add', '.gitignore', 'CLAUDE.md', 'AGENTS.md', '.agents', 'ums') | Out-Null
    Invoke-FxGit $fork @('commit', '-q', '-m', 'ums layer') | Out-Null

    # ---- Monorepo: tracked deployment at t1, local bare origin
    $mono = Join-Path $root 'mono'
    $monoBare = Join-Path $root 'mono-origin.git'
    New-Item -ItemType Directory -Force $mono | Out-Null
    Invoke-FxGit $mono @('init', '-q', '-b', 'main') | Out-Null
    Write-FxFile (Join-Path $mono 'CLAUDE.md') "# monorepo CLAUDE.md`n"
    Write-FxFile (Join-Path $mono '.claude/settings.json') "{}`n"
    $monoSkills = Join-Path $mono '.claude/skills'
    $monoShared = Join-Path $monoSkills 'shared'
    Write-FxFile (Join-Path $monoShared 'VENDORED_FROM.md') (New-SyncFixturePin 't1' $t1 @('alpha', 'beta', 'subagent-driven-development'))
    Add-RevendorFixtureOverlays (Join-Path $monoShared 'overlays')
    foreach ($s in 'alpha', 'beta', 'subagent-driven-development') {
        Write-FxFile (Join-Path $monoSkills "$s/SKILL.md") "# $s (deployed at t1)`n"
    }
    Invoke-FxGit $mono @('add', '-A') | Out-Null
    Invoke-FxGit $mono @('commit', '-q', '-m', 'monorepo at t1') | Out-Null
    Invoke-FxGit $root @('clone', '-q', '--bare', $mono, $monoBare) | Out-Null
    Invoke-FxGit $mono @('remote', 'add', 'origin', $monoBare) | Out-Null
    Invoke-FxGit $mono @('fetch', '-q', 'origin') | Out-Null
    Invoke-FxGit $mono @('branch', '-q', '--set-upstream-to=origin/main', 'main') | Out-Null

    return @{
        Root     = $root
        Fork     = $fork
        ForkUms  = $forkUms
        Mono     = $mono
        MonoBare = $monoBare
        T1Commit = $t1
        T2Commit = $t2
    }
}

function Remove-SyncFixture($Fixture) {
    if ($Fixture -and (Test-Path -LiteralPath $Fixture.Root)) {
        Remove-Item -Recurse -Force -LiteralPath $Fixture.Root -ErrorAction SilentlyContinue
    }
}
