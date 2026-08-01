<#
.SYNOPSIS
    Installs this layer's git hooks (currently: pre-push, the Publication
    Contract enforcement boundary) into a repository's .git/hooks/.

.DESCRIPTION
    Git hooks live in untracked .git/hooks/, so the guarantee described in
    UMS_MEMORY_BANK_CONTRACT.md ("Publication Contract") exists only once
    this script has been run against a given clone — vendoring the source
    file under ums/.claude/hooks/ is not enough by itself.

    Safe to re-run: re-installs over its own previously-installed copy
    (identified by the "UMS pre-push guard" marker comment at the top of the
    hook). Never overwrites a pre-existing pre-push hook that is NOT ours —
    it reports the conflict and leaves the file untouched, since silently
    replacing someone's own hook would be worse than not installing at all.

    This script is deliberately generic (parameterized by -RepoRoot and
    -SourceDir) so it works unmodified against any clone that carries this
    layer — the UMS monorepo, this fork, or any other project that adopts
    UMS Memory Bank — not just the sync pipeline's own targets.

.PARAMETER RepoRoot
    Working-tree root of the repository to install into (NOT .git/hooks
    itself). Defaults to the current directory.

.PARAMETER SourceDir
    Directory containing the hook source files. Defaults to this script's
    own directory (ums/.claude/hooks).

.EXAMPLE
    pwsh ums/.claude/hooks/install-git-hooks.ps1 -RepoRoot C:\path\to\repo

.EXAMPLE
    # Verify it actually works after installing:
    git -C C:\path\to\repo push origin develop
    # -> should print the UMS rejection message and refuse (non-zero exit).
    # `git push --no-verify` bypasses this hook by design; that is expected.
#>
#Requires -Version 7
[CmdletBinding()]
param(
    [string]$RepoRoot = (Get-Location).Path,
    [string]$SourceDir = $PSScriptRoot
)
$ErrorActionPreference = 'Stop'

$HOOK_NAMES = @('pre-push')
$OURS_MARKER = 'UMS pre-push guard (Publication Contract)'

$gitDir = Join-Path $RepoRoot '.git'
if (-not (Test-Path $gitDir)) {
    throw "Not a git repository (no .git found under RepoRoot): $RepoRoot"
}
# .git can itself be a file (worktrees, submodules) pointing elsewhere via
# "gitdir: <path>" - resolve it so hooks land in the real hooks directory.
if (Test-Path -PathType Leaf $gitDir) {
    $pointer = (Get-Content -LiteralPath $gitDir -Raw) -replace '^gitdir:\s*', ''
    $gitDir = $pointer.Trim()
    if (-not [IO.Path]::IsPathRooted($gitDir)) { $gitDir = Join-Path $RepoRoot $gitDir }
}
$hooksDir = Join-Path $gitDir 'hooks'
New-Item -ItemType Directory -Force -Path $hooksDir | Out-Null

# Resolve Git Bash's own bash.exe (NOT whatever "bash" happens to be first on
# PATH - on a machine with WSL installed, that is frequently the WSL launcher
# stub, which does not run this repo's scripts against the intended
# filesystem). Best-effort only: used solely to set the executable bit,
# which Git for Windows' own hook runner does not require (it dispatches on
# the shebang line), so a failure here is not fatal.
function Find-GitBash {
    $gitCmd = Get-Command git -ErrorAction SilentlyContinue
    if (-not $gitCmd) { return $null }
    # git.exe's directory relative to the Git for Windows install root varies
    # (cmd\, mingw64\bin\, bin\ all observed depending on how PATH was
    # assembled) - climb ancestors until bash.exe turns up.
    $dir = Split-Path $gitCmd.Source
    for ($i = 0; $i -lt 4 -and $dir; $i++) {
        foreach ($candidate in @('bin\bash.exe', 'usr\bin\bash.exe')) {
            $p = Join-Path $dir $candidate
            if (Test-Path $p) { return $p }
        }
        $parent = Split-Path $dir
        if (-not $parent -or $parent -eq $dir) { break }
        $dir = $parent
    }
    return $null
}
$gitBash = Find-GitBash
$installedAny = $false

foreach ($name in $HOOK_NAMES) {
    $src = Join-Path $SourceDir $name
    if (-not (Test-Path $src)) { throw "Hook source not found: $src" }
    $dst = Join-Path $hooksDir $name

    if (Test-Path $dst) {
        $existing = Get-Content -LiteralPath $dst -Raw
        if ($existing -notmatch [regex]::Escape($OURS_MARKER)) {
            Write-Host "SKIP: $dst already exists and is not the UMS hook - leaving it alone." -ForegroundColor Yellow
            Write-Host "      Merge the UMS pre-push logic into it by hand if you want both enforced." -ForegroundColor Yellow
            continue
        }
    }

    Copy-Item -Force -LiteralPath $src -Destination $dst

    if ($gitBash) {
        # Path with forward slashes so the MSYS bash accepts it unambiguously.
        $unixish = $dst -replace '\\', '/'
        try { & $gitBash -c 'chmod +x "$1"' _ $unixish 2>$null | Out-Null } catch { }
    }

    Write-Host "installed $name -> $dst" -ForegroundColor Cyan
    $installedAny = $true
}

if ($installedAny) {
    Write-Host ''
    Write-Host "Verify: git -C `"$RepoRoot`" push origin develop" -ForegroundColor DarkGray
    Write-Host '  -> should print the UMS rejection message and fail (non-zero exit).' -ForegroundColor DarkGray
    Write-Host '     `--no-verify` bypasses this hook by design - that is expected, not a bug.' -ForegroundColor DarkGray
}
