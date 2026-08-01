<#
.SYNOPSIS
    Installs this layer's git hooks (currently: pre-push, the Publication
    Contract enforcement boundary) into a repository, and self-verifies that
    the installed copy is actually the one git will run.

.DESCRIPTION
    Git hooks live in untracked .git/hooks/, so the guarantee described in
    UMS_MEMORY_BANK_CONTRACT.md ("Publication Contract") exists only once
    this script has been run against a given clone — vendoring the source
    file under ums/.claude/hooks/ is not enough by itself.

    The destination is resolved with `git -C <RepoRoot> rev-parse --git-path
    hooks/<name>` — the one resolution that is correct for a plain repo, a
    LINKED WORKTREE (whose hooks are NOT under its own
    .git/worktrees/<name>/hooks/ — that would be the wrong, inert location;
    hooks live in $GIT_COMMON_DIR, which only --git-path resolves correctly),
    and a repository with `core.hooksPath` set (local or global — common with
    husky/pre-commit), which makes git ignore .git/hooks/ entirely. Hand-
    resolving the `.git` file/directory (an earlier version of this script
    did that) gets the worktree case wrong silently: it reports success while
    the hook it wrote is never consulted.

    After installing, this script pipes a synthetic, harmless line into the
    installed hook (a fabricated push to `refs/heads/develop`) and confirms
    it rejects with the expected message — this never touches the real repo
    or remote, unlike verifying with an actual `git push origin develop`
    (which either publishes real commits if the hook is inert, exactly how
    the worktree bypass was first confirmed, or prints a misleading
    "Everything up-to-date" if there is nothing new to push). If Git Bash is
    not available to run that check, the command is printed instead so a
    human can run it.

    Safe to re-run: re-installs over its own previously-installed copy,
    identified by a marker comment on one of the file's first few lines
    (matched only near the top, not anywhere in the file, so a foreign hook
    that merely mentions similar wording deeper in its body is never treated
    as ours). Never overwrites a pre-existing hook that is NOT ours — it
    reports the conflict and leaves the file untouched.

    This script is deliberately generic (parameterized by -RepoRoot and
    -SourceDir) so it works unmodified against any clone that carries this
    layer — the UMS monorepo, this fork, or any other project that adopts
    UMS Memory Bank — not just the sync pipeline's own targets.

.PARAMETER RepoRoot
    Working-tree root of the repository (or linked worktree) to install
    into. Defaults to the current directory.

.PARAMETER SourceDir
    Directory containing the hook source files. Defaults to this script's
    own directory (ums/.claude/hooks).

.EXAMPLE
    pwsh ums/.claude/hooks/install-git-hooks.ps1 -RepoRoot C:\path\to\repo

.EXAMPLE
    # Non-destructive manual verification (does not push or move any ref) -
    # same check this script runs automatically when Git Bash is available:
    printf 'refs/heads/develop 0123456789abcdef0123456789abcdef01234567 refs/heads/develop 0123456789abcdef0123456789abcdef01234567\n' | "<resolved hook path>" origin verify
    # -> should print the UMS rejection message and exit non-zero.
    # `git push --no-verify` and `git -c core.hooksPath=<other>` both bypass
    # this hook by design; that is expected, not a bug.
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
$MARKER_LINES_CHECKED = 5

if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw 'git not found on PATH.' }

& git -C $RepoRoot rev-parse --is-inside-work-tree *> $null
if ($LASTEXITCODE -ne 0) {
    throw "Not a git working tree (git rev-parse --is-inside-work-tree failed): $RepoRoot"
}

# The one resolution that is correct for a plain repo, a linked worktree
# (common dir, not the per-worktree private dir), and a core.hooksPath
# override (local or global, relative or absolute).
function Resolve-HookDestination([string] $Root, [string] $Name) {
    $out = & git -C $Root rev-parse --git-path "hooks/$Name" 2>&1
    if ($LASTEXITCODE -ne 0) { throw "git rev-parse --git-path failed for '$Root': $out" }
    $rel = (($out | Select-Object -First 1).ToString()).Trim()
    if ([IO.Path]::IsPathRooted($rel)) { return $rel }
    return (Join-Path $Root $rel)
}

function Get-CustomHooksPath([string] $Root) {
    $out = & git -C $Root config --get core.hooksPath 2>$null
    if ($LASTEXITCODE -eq 0 -and $out) { return $out.Trim() }
    return $null
}

# Marker matched only on the file's first few lines, not anywhere in the
# file - a foreign hook whose body happens to mention similar wording deeper
# down must NOT be mistaken for ours.
function Test-IsOurHook([string] $Path) {
    if (-not (Test-Path $Path)) { return $false }
    $head = Get-Content -LiteralPath $Path -TotalCount $MARKER_LINES_CHECKED -ErrorAction SilentlyContinue
    if (-not $head) { return $false }
    return (($head -join "`n") -match [regex]::Escape($OURS_MARKER))
}

# Resolve Git Bash's own bash.exe (NOT whatever "bash" happens to be first on
# PATH - on a machine with WSL installed, that is frequently the WSL launcher
# stub, which silently drops positional args and does not run this repo's
# scripts against the intended filesystem). Used both to set the executable
# bit (best-effort only - Git for Windows' own hook runner dispatches on the
# shebang line regardless) and to self-verify the installed hook fires.
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

$customHooksPath = Get-CustomHooksPath $RepoRoot
if ($customHooksPath) {
    Write-Host "note: core.hooksPath is set to '$customHooksPath' - installing there, since that is where git actually looks (it ignores .git/hooks/ while this is set)." -ForegroundColor DarkGray
}

$installedAny = $false
foreach ($name in $HOOK_NAMES) {
    $src = Join-Path $SourceDir $name
    if (-not (Test-Path $src)) { throw "Hook source not found: $src" }
    $dst = Resolve-HookDestination $RepoRoot $name
    New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null

    if ((Test-Path $dst) -and -not (Test-IsOurHook $dst)) {
        Write-Host "SKIP: $dst already exists and is not the UMS hook - leaving it alone." -ForegroundColor Yellow
        Write-Host '      Merge the UMS pre-push logic into it by hand if you want both enforced.' -ForegroundColor Yellow
        continue
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
    $hookPath = Resolve-HookDestination $RepoRoot 'pre-push'
    Write-Host ''
    if ($gitBash) {
        # Self-verify: pipe a synthetic, harmless line straight into the
        # installed hook - a fabricated push to refs/heads/develop, both
        # shas fake. This never touches the real repo/remote (unlike
        # verifying with an actual `git push origin develop`, which either
        # publishes real commits if the hook is inert - exactly how the
        # worktree bypass was confirmed for real - or prints a misleading
        # "Everything up-to-date" if there is nothing new to push).
        $sha = '0123456789abcdef0123456789abcdef01234567'
        $unixHook = $hookPath -replace '\\', '/'
        $bashScript = 'printf "refs/heads/develop %s refs/heads/develop %s\n" "$1" "$1" | "$2" origin verify'
        $verifyOut = & $gitBash -c $bashScript _ $sha $unixHook 2>&1 | Out-String
        $verifyCode = $LASTEXITCODE
        if ($verifyCode -ne 0 -and $verifyOut -match 'UMS') {
            Write-Host "verified: pre-push correctly rejects a synthetic push to 'develop' (exit $verifyCode)." -ForegroundColor Green
        }
        else {
            Write-Host 'WARNING: the installed pre-push hook did NOT reject the synthetic protected-branch push!' -ForegroundColor Red
            Write-Host "  exit code: $verifyCode" -ForegroundColor Red
            Write-Host "  output: $($verifyOut.Trim())" -ForegroundColor Red
            Write-Host '  The guarantee may be inert here (wrong location, another core.hooksPath override taking' -ForegroundColor Red
            Write-Host '  precedence, a non-executable copy, ...) - investigate before relying on it.' -ForegroundColor Red
        }
    }
    else {
        Write-Host 'Git Bash was not found to self-verify. Verify manually (non-destructive):' -ForegroundColor DarkGray
        Write-Host "  printf 'refs/heads/develop 0123456789abcdef0123456789abcdef01234567 refs/heads/develop 0123456789abcdef0123456789abcdef01234567`n' | ""$hookPath"" origin verify" -ForegroundColor DarkGray
        Write-Host '  -> should print the UMS rejection message and exit non-zero.' -ForegroundColor DarkGray
    }
    Write-Host '`git push --no-verify` and `git -c core.hooksPath=<other>` both bypass this hook by design.' -ForegroundColor DarkGray
}
