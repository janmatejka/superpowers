# Builds a throwaway Superpowers mirror (two tags) and a throwaway UMS root
# (with a pin for tag t1) for the revendor tests. Everything lives in OS temp.
#
#   t1: skills alpha, beta, subagent-driven-development
#   t2: beta is gone, gamma is new
#
# Dot-source this file, then call New-RevendorFixture; remove the returned
# Root with Remove-RevendorFixture when done.

function Invoke-FxGit([string] $Dir, [string[]] $GitArgs) {
    $out = & git -C $Dir -c user.name=fixture -c user.email=fixture@example.invalid `
        -c commit.gpgsign=false -c core.autocrlf=false @GitArgs 2>&1
    if ($LASTEXITCODE -ne 0) { throw "git $($GitArgs -join ' ') failed in ${Dir}: $out" }
    return $out
}

# Writes exact bytes: UTF-8 without BOM, line endings exactly as given.
function Write-FxFile([string] $Path, [string] $Text) {
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
    [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false))
}

function New-RevendorFixture {
    $root = Join-Path ([IO.Path]::GetTempPath()) ("revendor-fx-" + [Guid]::NewGuid().ToString('N'))
    $sp = Join-Path $root 'sp-mirror'
    $ums = Join-Path $root 'ums-root'
    New-Item -ItemType Directory -Force $sp, $ums | Out-Null

    # ---- Superpowers mirror, tag t1
    Invoke-FxGit $sp @('init', '-q', '-b', 'main') | Out-Null
    # alpha is committed with CRLF on purpose: the vendor phase must normalize it to LF.
    Write-FxFile (Join-Path $sp 'skills/alpha/SKILL.md') "# Alpha`r`nline two`r`n"
    Write-FxFile (Join-Path $sp 'skills/beta/SKILL.md') "# beta`n"
    $sdd = 'skills/subagent-driven-development'
    Write-FxFile (Join-Path $sp "$sdd/SKILL.md") "# subagent-driven-development`n"
    Write-FxFile (Join-Path $sp "$sdd/task-reviewer-prompt.md") "# task reviewer`n"
    Write-FxFile (Join-Path $sp "$sdd/implementer-prompt.md") "# implementer`n"
    Write-FxFile (Join-Path $sp "$sdd/scripts/task-brief") "#!/usr/bin/env bash`nexit 0`n"
    Write-FxFile (Join-Path $sp "$sdd/scripts/review-package") "#!/usr/bin/env bash`nexit 0`n"
    # Functional stand-in for the real plan-scoped workspace script: creates
    # <repo>/.superpowers/sdd/<plan-basename>/ and prints its path.
    Write-FxFile (Join-Path $sp "$sdd/scripts/sdd-workspace") (
        "#!/usr/bin/env bash`nset -euo pipefail`n" +
        "slug=`$(basename `"`$1`" .md)`n" +
        "root=`$(git rev-parse --show-toplevel)`n" +
        "dir=`"`$root/.superpowers/sdd/`$slug`"`n" +
        "mkdir -p `"`$dir`"`n" +
        "cd `"`$dir`" && pwd`n")
    Invoke-FxGit $sp @('add', '-A') | Out-Null
    Invoke-FxGit $sp @('commit', '-q', '-m', 'v1') | Out-Null
    Invoke-FxGit $sp @('tag', 't1') | Out-Null
    $t1Commit = (Invoke-FxGit $sp @('rev-parse', 't1^{commit}')) | Select-Object -First 1

    # ---- tag t2: beta removed, gamma added
    Invoke-FxGit $sp @('rm', '-q', '-r', 'skills/beta') | Out-Null
    Write-FxFile (Join-Path $sp 'skills/gamma/SKILL.md') "# gamma`n"
    Invoke-FxGit $sp @('add', '-A') | Out-Null
    Invoke-FxGit $sp @('commit', '-q', '-m', 'v2') | Out-Null
    Invoke-FxGit $sp @('tag', 't2') | Out-Null

    # ---- UMS root: git repo, empty overlays dir, pin for t1 (no Excluded section)
    Invoke-FxGit $ums @('init', '-q', '-b', 'main') | Out-Null
    $skillsRoot = Join-Path $ums '.claude/skills'
    New-Item -ItemType Directory -Force (Join-Path $skillsRoot 'shared/overlays') | Out-Null
    Write-FxFile (Join-Path $skillsRoot 'shared/VENDORED_FROM.md') (
        "# Vendored Superpowers skills`n`n" +
        "- Upstream: https://github.com/obra/superpowers.git`n" +
        "- Tag: t1`n" +
        "- Commit: $t1Commit`n" +
        "- Vendored on top of repo state: 2026-01-01 (by .claude/scripts/revendor-superpowers.ps1)`n" +
        "- Skills:`n  alpha`n  beta`n  subagent-driven-development`n" +
        "- Overlays: applied from ``shared/overlays/*.overlay.md``; applied blocks are marked`n" +
        "  ``<!-- UMS-OVERLAY BEGIN/END -->`` inside the vendored files.`n")
    Write-FxFile (Join-Path $ums 'README.md') "fixture`n"
    Invoke-FxGit $ums @('add', 'README.md') | Out-Null
    Invoke-FxGit $ums @('commit', '-q', '-m', 'init') | Out-Null

    return @{
        Root       = $root
        SpRepo     = $sp
        UmsRoot    = $ums
        SkillsRoot = $skillsRoot
        T1Commit   = $t1Commit
    }
}

# Writes the two fragments that overlay one target (alpha/SKILL.md) into an
# overlays directory: a body block appended at EOF and a header pointer block
# before the H1. By file name the body fragment sorts first (alpha.overlay.md <
# alpha.pointer.overlay.md), so the pointer's ASSERT on a body line only holds
# when the fragments of one target are applied in that order.
function Add-RevendorFixtureOverlays([string] $OverlaysDir) {
    Write-FxFile (Join-Path $OverlaysDir 'alpha.overlay.md') (
        "<!-- TARGET: alpha/SKILL.md -->`n" +
        "<!-- ANCHOR: EOF -->`n" +
        "<!-- ASSERT: line two -->`n" +
        "<!-- UMS-OVERLAY BEGIN (fixture body) -->`n" +
        "Alpha body block.`n" +
        "Target-relative link: [pin](../shared/VENDORED_FROM.md)`n" +
        "<!-- UMS-OVERLAY END -->`n")
    Write-FxFile (Join-Path $OverlaysDir 'alpha.pointer.overlay.md') (
        "<!-- TARGET: alpha/SKILL.md -->`n" +
        "<!-- ANCHOR-BEFORE: # Alpha -->`n" +
        "<!-- ASSERT: Alpha body block. -->`n" +
        "<!-- UMS-OVERLAY BEGIN (fixture pointer) -->`n" +
        "UMS pointer: the overlay body is at the end of this file.`n" +
        "<!-- UMS-OVERLAY END -->`n")
}

function Remove-RevendorFixture($Fixture) {
    if ($Fixture -and (Test-Path -LiteralPath $Fixture.Root)) {
        Remove-Item -Recurse -Force -LiteralPath $Fixture.Root -ErrorAction SilentlyContinue
    }
}
