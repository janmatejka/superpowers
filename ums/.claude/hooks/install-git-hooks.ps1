<#
.SYNOPSIS
    Installs this layer's git hooks (currently: pre-push, the Publication
    Contract enforcement boundary) into a repository, and proves that the
    installed copy is the one git will actually run.

.DESCRIPTION
    Git hooks live in untracked .git/hooks/, so the guarantee described in
    UMS_MEMORY_BANK_CONTRACT.md ("Publication Contract") exists only once
    this script has been run against a given clone — vendoring the source
    file under ums/.claude/hooks/ is not enough by itself.

    DESTINATION. Resolved with `git -C <RepoRoot> rev-parse --git-path
    hooks/<name>` — the one resolution that is correct for a plain repo, a
    LINKED WORKTREE (whose hooks are NOT under its own
    .git/worktrees/<name>/hooks/ — that would be the wrong, inert location;
    hooks live in $GIT_COMMON_DIR, which only --git-path resolves correctly),
    and a repository with `core.hooksPath` set (local or global — common with
    husky/pre-commit), which makes git ignore .git/hooks/ entirely. Hand-
    resolving the `.git` file/directory (an earlier version of this script
    did that) gets the worktree case wrong silently: it reports success while
    the hook it wrote is never consulted.

    Two `core.hooksPath` shapes change what a single run actually covers, so
    both are reported in the output instead of being discovered later the
    hard way:
      * a RELATIVE value (e.g. `customhooks`) is resolved per working tree,
        so a run against the main clone leaves every LINKED WORKTREE inert —
        each worktree needs its own run of this script;
      * a value coming from GLOBAL (or system) config applies to every
        repository that user works in, so what looks like a per-repository
        install is in fact a per-user one.
    Without core.hooksPath, .git/hooks/ is shared through the common dir, so
    one run does cover every worktree of that repository.

    PROOF. After installing, the hook is run twice against synthetic stdin
    lines: a fabricated push to refs/heads/develop that MUST be rejected with
    the UMS message, and a fabricated push creating a ticket branch that MUST
    be accepted. Neither touches the repository or the remote (no git command
    runs, both shas are fabricated), unlike verifying with a real
    `git push origin develop`, which either publishes real commits when the
    hook turns out to be inert — exactly how a worktree bypass was confirmed
    for real — or prints a misleading "Everything up-to-date" when there is
    nothing to push. The accept case is what makes the proof honest: a hook
    that cannot execute at all (bad shebang, missing exec bit, wrong
    location) fails BOTH runs, so it can never be mistaken for one that
    "rejected" the push.

    EXIT CODES — a caller (sync-with-monorepo.ps1) must be able to tell an
    installed guarantee from an absent one:
      0  installed and proven live
      1  installed, but the proof FAILED — treat the guarantee as absent
      2  NOT installed: a foreign pre-push was already there and was left
         untouched — the guarantee is absent here
      3  installed, but no shell was available to run the proof

    Safe to re-run: re-installs over its own previously-installed copy,
    identified by a marker comment on one of the file's first few lines
    (matched only near the top, not anywhere in the file, so a foreign hook
    that merely mentions similar wording deeper in its body is never treated
    as ours). Never overwrites a pre-existing hook that is NOT ours — it
    reports the conflict, leaves the file untouched and exits 2.

    CROSS-PLATFORM. The shell used for `chmod +x` and for the proof is, on
    Windows, Git for Windows' own bash.exe located from git.exe — NOT
    whatever `bash` PATH resolves to, which on a machine with WSL installed
    is frequently the WSL launcher stub. Elsewhere it is `bash` from PATH, or
    the usual POSIX locations.

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
    # Non-destructive manual verification (does not push or move any ref) —
    # the same two runs this script performs automatically. Reject case:
    printf 'refs/heads/develop 0123456789abcdef0123456789abcdef01234567 refs/heads/develop 0123456789abcdef0123456789abcdef01234567\n' | "<resolved hook path>" origin verify
    # -> must print the UMS rejection message and exit non-zero.
    # Accept case (proves the hook actually RUNS, not just that something failed):
    printf 'refs/heads/feature/x 0123456789abcdef0123456789abcdef01234567 refs/heads/feature/x 0000000000000000000000000000000000000000\n' | "<resolved hook path>" origin verify
    # -> must print nothing and exit 0.
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

# Fabricated shas for the proof runs. They are never resolved: the hook's
# protected-name rule fires before any sha is used, and the accept case sets
# the remote sha to all-zeros (branch creation), which skips the merge-base
# call as well.
$SHA_FAKE = '0123456789abcdef0123456789abcdef01234567'
$SHA_ZERO = '0000000000000000000000000000000000000000'

$EXIT_OK = 0
$EXIT_PROOF_FAILED = 1
$EXIT_NOT_INSTALLED = 2
$EXIT_UNPROVEN = 3

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

# git expands a leading ~ itself, so ~/hooks is NOT working-tree relative.
function Test-HooksPathIsAbsolute([string] $Value) {
    if ($Value.StartsWith('~')) { return $true }
    return [IO.Path]::IsPathRooted($Value)
}

# Effective core.hooksPath plus the config scope it comes from - the scope
# decides whether this install is per-repository or in fact per-user.
function Get-HooksPathConfig([string] $Root) {
    # --show-scope prints "<scope>\t<value>" (git >= 2.26); fall back to a
    # plain --get on anything older, where the scope stays unknown but the
    # value - and therefore the destination - is still correct.
    $raw = & git -C $Root config --show-scope --get core.hooksPath 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $raw) {
        $plain = & git -C $Root config --get core.hooksPath 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $plain) { return $null }
        $value = (($plain | Select-Object -First 1).ToString()).Trim()
        return @{ Value = $value; Scope = 'unknown'; IsAbsolute = (Test-HooksPathIsAbsolute $value) }
    }
    $line = (($raw | Select-Object -First 1).ToString()).Trim()
    $parts = $line -split "`t", 2
    if ($parts.Count -eq 2) { $scope = $parts[0].Trim(); $value = $parts[1].Trim() }
    else { $scope = 'unknown'; $value = $line }
    return @{ Value = $value; Scope = $scope; IsAbsolute = (Test-HooksPathIsAbsolute $value) }
}

function Get-WorktreeCount([string] $Root) {
    $out = & git -C $Root worktree list --porcelain 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $out) { return 1 }
    return @($out | Where-Object { $_ -like 'worktree *' }).Count
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

# Locate a POSIX shell for `chmod +x` and for the proof runs.
#   Windows: Git for Windows' own bash.exe, found by climbing ancestors of
#     git.exe (its directory relative to the install root varies - cmd\,
#     bin\, mingw64\bin\ have all been observed). Deliberately NOT `bash`
#     from PATH: with WSL installed that is usually the WSL launcher stub,
#     which silently drops positional args and runs against another
#     filesystem entirely.
#   Everything else: `bash` from PATH (no launcher-stub problem there), then
#     the usual absolute locations.
function Find-Shell {
    if ($IsWindows) {
        $gitCmd = Get-Command git -ErrorAction SilentlyContinue
        if (-not $gitCmd) { return $null }
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
    $onPath = Get-Command bash -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }
    foreach ($p in @('/bin/bash', '/usr/bin/bash', '/usr/local/bin/bash', '/bin/sh')) {
        if (Test-Path $p) { return $p }
    }
    return $null
}

# Feeds one synthetic pre-push stdin line to the installed hook and returns
# its exit code and combined output. Path with forward slashes so an MSYS
# bash accepts it unambiguously.
function Invoke-HookLine([string] $Shell, [string] $HookPath, [string] $Line) {
    $unixHook = $HookPath -replace '\\', '/'
    $script = 'printf "%s\n" "$1" | "$2" origin ums-install-verify'
    $out = & $Shell -c $script _ $Line $unixHook 2>&1 | Out-String
    return @{ Out = $out; Code = $LASTEXITCODE }
}

# Two runs, not one. A single "rejected something" check is not proof: a hook
# that cannot execute also exits non-zero, and its error text QUOTES THE HOOK
# PATH - which is how a case-insensitive `-match 'UMS'` on that output used
# to report a broken hook as verified for every repository living under a
# directory named "ums" (this layer's own deployment target included). Hence:
# case-sensitive match on the hook's own message marker, AND an accept case
# the broken hook cannot pass.
function Test-HookIsLive([string] $Shell, [string] $HookPath) {
    $reject = Invoke-HookLine $Shell $HookPath "refs/heads/develop $SHA_FAKE refs/heads/develop $SHA_FAKE"
    $accept = Invoke-HookLine $Shell $HookPath "refs/heads/feature/ums-install-verify $SHA_FAKE refs/heads/feature/ums-install-verify $SHA_ZERO"
    $saidUms = ($reject.Out -cmatch '(?m)^\s*UMS: ') -and ($reject.Out -cmatch 'Publication Contract')
    $ok = ($reject.Code -ne 0) -and $saidUms -and ($accept.Code -eq 0)
    return @{ Ok = $ok; Reject = $reject; Accept = $accept }
}

$shell = Find-Shell

$hooksPathCfg = Get-HooksPathConfig $RepoRoot
if ($hooksPathCfg) {
    Write-Host "note: core.hooksPath is set to '$($hooksPathCfg.Value)' ($($hooksPathCfg.Scope) config) - installing there, since that is where git actually looks (it ignores .git/hooks/ while this is set)." -ForegroundColor DarkGray
    if (-not $hooksPathCfg.IsAbsolute) {
        $wtCount = Get-WorktreeCount $RepoRoot
        Write-Host "WARNING: that is a relative core.hooksPath - git resolves it per working tree, so this run covers ONLY $RepoRoot." -ForegroundColor Yellow
        Write-Host "         Every other linked worktree of this repository needs its own run of this script (this repository currently has $wtCount working tree(s))." -ForegroundColor Yellow
    }
    if ($hooksPathCfg.Scope -in @('global', 'system')) {
        Write-Host "WARNING: core.hooksPath comes from $($hooksPathCfg.Scope) config, not from this repository - installing there affects EVERY repository you use with that config, not just this one." -ForegroundColor Yellow
    }
}

$installed = @()
$skipped = @()
foreach ($name in $HOOK_NAMES) {
    $src = Join-Path $SourceDir $name
    if (-not (Test-Path $src)) { throw "Hook source not found: $src" }
    $dst = Resolve-HookDestination $RepoRoot $name
    New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null

    if ((Test-Path $dst) -and -not (Test-IsOurHook $dst)) {
        Write-Host "SKIP: $dst already exists and is not the UMS hook - leaving it alone." -ForegroundColor Yellow
        Write-Host '      Merge the UMS pre-push logic into it by hand if you want both enforced.' -ForegroundColor Yellow
        $skipped += @{ Name = $name; Path = $dst }
        continue
    }

    Copy-Item -Force -LiteralPath $src -Destination $dst

    if ($shell) {
        $unixish = $dst -replace '\\', '/'
        try { & $shell -c 'chmod +x "$1"' _ $unixish 2>$null | Out-Null } catch { }
    }

    Write-Host "installed $name -> $dst" -ForegroundColor Cyan
    $installed += @{ Name = $name; Path = $dst }
}

# ------------------------------------------------------------------ summary
$exitCode = $EXIT_OK
Write-Host ''

foreach ($hook in $skipped) {
    Write-Host "summary: $($hook.Name) -> $($hook.Path)  [NOT INSTALLED - foreign hook left in place, the Publication Contract guarantee is ABSENT here]" -ForegroundColor Yellow
    $exitCode = $EXIT_NOT_INSTALLED
}

foreach ($hook in $installed) {
    if ($hook.Name -ne 'pre-push') {
        Write-Host "summary: $($hook.Name) -> $($hook.Path)  [installed]" -ForegroundColor Cyan
        continue
    }
    if (-not $shell) {
        Write-Host 'No shell (bash) was found to run the proof. Verify manually - non-destructive, nothing is pushed:' -ForegroundColor DarkGray
        Write-Host "  printf 'refs/heads/develop $SHA_FAKE refs/heads/develop $SHA_FAKE\n' | ""$($hook.Path)"" origin verify" -ForegroundColor DarkGray
        Write-Host '  -> must print the UMS rejection message and exit non-zero.' -ForegroundColor DarkGray
        Write-Host "  printf 'refs/heads/feature/x $SHA_FAKE refs/heads/feature/x $SHA_ZERO\n' | ""$($hook.Path)"" origin verify" -ForegroundColor DarkGray
        Write-Host '  -> must print nothing and exit 0 (this half proves the hook RUNS at all).' -ForegroundColor DarkGray
        Write-Host "summary: $($hook.Name) -> $($hook.Path)  [installed, UNPROVEN - no shell available to run the proof]" -ForegroundColor Yellow
        $exitCode = $EXIT_UNPROVEN
        continue
    }
    $proof = Test-HookIsLive $shell $hook.Path
    if ($proof.Ok) {
        Write-Host "verified: pre-push rejects a synthetic push to 'develop' (exit $($proof.Reject.Code)) and accepts a synthetic ticket-branch push (exit 0)." -ForegroundColor Green
        Write-Host "summary: $($hook.Name) -> $($hook.Path)  [installed + verified live]" -ForegroundColor Green
    }
    else {
        Write-Host 'WARNING: the installed pre-push hook did NOT behave like the UMS guard!' -ForegroundColor Red
        Write-Host "  protected-branch run: exit $($proof.Reject.Code) (expected non-zero with a 'UMS:' message)" -ForegroundColor Red
        Write-Host "    output: $($proof.Reject.Out.Trim())" -ForegroundColor Red
        Write-Host "  ticket-branch run:    exit $($proof.Accept.Code) (expected 0, silent)" -ForegroundColor Red
        Write-Host "    output: $($proof.Accept.Out.Trim())" -ForegroundColor Red
        Write-Host '  The guarantee is NOT in place here (hook cannot execute, wrong location, another' -ForegroundColor Red
        Write-Host '  core.hooksPath override taking precedence, ...) - investigate before relying on it.' -ForegroundColor Red
        Write-Host "summary: $($hook.Name) -> $($hook.Path)  [installed, PROOF FAILED - treat the guarantee as absent]" -ForegroundColor Red
        $exitCode = $EXIT_PROOF_FAILED
    }
}

Write-Host '`git push --no-verify` and `git -c core.hooksPath=<other>` both bypass this hook by design.' -ForegroundColor DarkGray
exit $exitCode
