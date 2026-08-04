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

    PROOF. After installing, the hook is run against synthetic stdin lines: a
    fabricated push to refs/heads/develop that MUST be rejected with the UMS
    message, and a fabricated push creating a ticket branch that MUST be
    accepted — plus, whenever the configuration names a protected pattern the
    hook's built-in fallback does not cover, a third run on that pattern (which
    must be rejected) with its own control on an unprotected name (which must
    not be). That pair is what distinguishes "the generated list was consulted"
    from "the built-in fallback happened to agree".

    No run touches the repository or the remote (no git command runs, every sha
    is fabricated), unlike verifying with a real `git push origin develop`,
    which either publishes real commits when the hook turns out to be inert —
    exactly how a worktree bypass was confirmed for real — or prints a
    misleading "Everything up-to-date" when there is nothing to push. The
    ACCEPT cases are what make the proof honest: a hook that cannot execute at
    all (bad shebang, missing exec bit, wrong location) fails every run, so it
    can never be mistaken for one that "rejected" the push — and a rejection
    shape that rejects EVERYTHING (which a fabricated remote sha produces, via
    the unresolvable fast-forward check) can never be mistaken for a consulted
    configuration.

    EXIT CODES — a caller (sync-with-monorepo.ps1) must be able to tell an
    installed guarantee from an absent one:
      0  installed and proven live
      1  installed, but the proof FAILED — treat the guarantee as absent
      2  NOT installed: a foreign pre-push was already there and was left
         untouched — the guarantee is absent here
      3  installed, but no shell was available to run the proof
      4  installed and proven live, but the protected-branch list is NOT in
         place — either it could not be WRITTEN, or the configuration LOADER
         (Get-UmsRepoConfig.ps1) was not found next to the hooks directory —
         so only the hook's built-in patterns are enforced and any configured
         pattern beyond them is not

    CONFIGURATION. The protected-branch patterns are configuration (contract:
    "Repository Configuration"), not hook body: pre-push is POSIX sh and
    cannot read JSON, so this script materializes memory-bank/ums-repo.json's
    `protectedBranches` into <git-common-dir>/ums-protected-branches, one glob
    per line. That means a CHANGE TO THE CONFIGURATION TAKES EFFECT ONLY AFTER
    THIS SCRIPT RUNS AGAIN. The common dir is deliberate: one install covers
    every working tree of the repository (unless core.hooksPath moves the hook
    itself, see above).

    Anything that goes wrong on the CONFIGURATION path degrades to the hook's
    built-in list — never to an uninstalled hook. A missing loader or an
    unwritable list still installs pre-push and still exits 4, because the
    hook's own fallback IS the built-in list: landing at built-in protection
    is right, landing at NO protection would invert the very principle the
    hook states about its fallback (contract: "Repository Configuration").

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

$PROTECTED_LIST_NAME = 'ums-protected-branches'

# Patterns pre-push falls back to when the generated list is missing, empty or
# comment-only. Kept here only to pick the third proof run's sample pattern -
# the hook owns the authoritative copy.
$BUILTIN_PROTECTED = @('develop', 'main', 'master', 'release/*')

# Branch name for the third run's own control - see Test-HookIsLive. Must be a
# name no sane configuration protects; if a repository's patterns do cover it,
# the control is skipped rather than reported as a failure.
$EXTRA_CONTROL_NAME = 'ums-install-verify-unprotected'

$EXIT_OK = 0
$EXIT_PROOF_FAILED = 1
$EXIT_NOT_INSTALLED = 2
$EXIT_UNPROVEN = 3
$EXIT_LIST_FAILED = 4

$script:ListFailed = $false
$script:ListFailedReason = $null

# The repository-configuration loader lives next to the hooks directory
# (ums/.claude/skills/shared/scripts). Primary path relative to -SourceDir so
# a run against a copied/vendored layer reads THAT copy's loader; fallback
# relative to this script's own location for the case where -SourceDir points
# somewhere else (the tests do exactly that).
#
# A missing loader is LOUD but NOT fatal. Throwing here (an earlier version
# did) skips the install altogether, and sync-with-monorepo.ps1 downgrades a
# non-zero exit to a warning - so an incomplete layer copy ended up with NO
# pre-push at all and an unprotected `develop`, which is strictly less
# protection than the hook's own built-in fallback would have given. The
# contract's degradation principle decides: install the hook, land at built-in
# protection, and say so with exit 4.
$loader = Join-Path $SourceDir '..\skills\shared\scripts\Get-UmsRepoConfig.ps1'
if (-not (Test-Path -LiteralPath $loader)) {
    $loader = Join-Path $PSScriptRoot '..\skills\shared\scripts\Get-UmsRepoConfig.ps1'
}
$loaderFound = Test-Path -LiteralPath $loader
if ($loaderFound) {
    . $loader
}
else {
    Write-Host "WARNING: Get-UmsRepoConfig.ps1 not found next to the hooks directory - this copy of the layer is incomplete:" -ForegroundColor Red
    Write-Host "           $loader" -ForegroundColor Red
    Write-Host '         The protected-branch list cannot be generated, so pre-push falls back to its built-in' -ForegroundColor Red
    Write-Host '         list (develop, main, master, release/*). The hook IS still installed below: degrading to' -ForegroundColor Red
    Write-Host '         built-in protection is correct, degrading to NO hook would not be. Any configured' -ForegroundColor Red
    Write-Host '         pattern beyond the built-in list is NOT enforced here (exit 4).' -ForegroundColor Red
    $script:ListFailed = $true
    $script:ListFailedReason = 'the configuration loader Get-UmsRepoConfig.ps1 was not found'
}

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

# Materializes protectedBranches as one glob per line for the pre-push hook,
# which is POSIX sh and cannot parse JSON. Written into the COMMON dir so a
# single install covers every working tree of the repository.
function Write-ProtectedList([string] $Root, [string[]] $Patterns) {
    $common = & git -C $Root rev-parse --git-common-dir 2>&1
    if ($LASTEXITCODE -ne 0) { throw "git rev-parse --git-common-dir failed for '$Root': $common" }
    $common = (($common | Select-Object -First 1).ToString()).Trim()
    if (-not [IO.Path]::IsPathRooted($common)) { $common = Join-Path $Root $common }
    $dst = Join-Path $common $PROTECTED_LIST_NAME
    $header = '# Generated by install-git-hooks.ps1 from memory-bank/ums-repo.json - do not edit.'
    $body = (@($header) + @($Patterns)) -join "`n"
    [IO.File]::WriteAllText($dst, $body + "`n", (New-Object Text.UTF8Encoding($false)))
    return $dst
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
# its exit code and combined output. Paths with forward slashes so an MSYS
# bash accepts them unambiguously.
#
# Run FROM $RepoRoot, the way git itself invokes a hook. Not cosmetic: the hook
# resolves its protected-branch list through `git rev-parse --git-common-dir`,
# which answers for the CURRENT DIRECTORY - so a proof run started from
# wherever the operator happened to be would read ANOTHER repository's list
# and could report "verified" about a file that has nothing to do with
# $RepoRoot. `cd` failing short-circuits the pipeline, so a bad root fails the
# proof loudly instead of quietly proving nothing.
function Invoke-HookLine([string] $Shell, [string] $HookPath, [string] $Line) {
    $unixHook = $HookPath -replace '\\', '/'
    $unixRoot = (Resolve-Path -LiteralPath $RepoRoot).Path -replace '\\', '/'
    $script = 'cd "$3" && printf "%s\n" "$1" | "$2" origin ums-install-verify'
    $out = & $Shell -c $script _ $Line $unixHook $unixRoot 2>&1 | Out-String
    return @{ Out = $out; Code = $LASTEXITCODE }
}

# Two runs, not one - and a third whenever the configuration names a pattern
# the hook's built-in fallback does not cover, that being the only run able to
# tell "consulted the generated list" from "fell back and happened to agree".
#
# A single "rejected something" check is not proof: a hook
# that cannot execute also exits non-zero, and its error text QUOTES THE HOOK
# PATH - which is how a case-insensitive `-match 'UMS'` on that output used
# to report a broken hook as verified for every repository living under a
# directory named "ums" (this layer's own deployment target included). Hence:
# case-sensitive match on the hook's own message marker, AND an accept case
# the broken hook cannot pass.
function Test-HookIsLive([string] $Shell, [string] $HookPath, [string[]] $Patterns) {
    $reject = Invoke-HookLine $Shell $HookPath "refs/heads/develop $SHA_FAKE refs/heads/develop $SHA_FAKE"
    $accept = Invoke-HookLine $Shell $HookPath "refs/heads/feature/ums-install-verify $SHA_FAKE refs/heads/feature/ums-install-verify $SHA_ZERO"

    # Third run: proves the hook actually READS the generated list, not just
    # that its built-in fallback works. Uses the first configured pattern that
    # the built-in list does not already cover; with no such pattern there is
    # nothing this run could distinguish, so it is skipped and reported.
    #
    # A pattern carrying glob metacharacters other than `*` has no mechanical
    # sample branch name (`[Bb]ranches/*` is not matched by `[Bb]ranches/x`
    # with the brackets left in, and guessing would report a FALSE proof
    # failure), so such a pattern is passed over rather than sampled.
    $candidates = @($Patterns | Where-Object { $BUILTIN_PROTECTED -notcontains $_ })
    $extra = @($candidates | Where-Object { $_ -notmatch '[?\[\]\\]' }) | Select-Object -First 1
    $sample = $null
    $skipReason = $null
    if ($script:ListFailed) {
        # Nothing to prove: the list this run exists to detect is not there,
        # and a legitimately failing run would be reported as a broken hook.
        $extra = $null
        $skipReason = 'the protected-branch list is not in place, so there is no generated list to consult'
    }
    elseif (-not $extra) {
        if (@($candidates).Count -gt 0) {
            $skipReason = "every configured pattern beyond the built-in list ($($candidates -join ', ')) carries a glob metacharacter other than '*', so no sample branch name can be derived from it"
        }
        else {
            $skipReason = 'no configured pattern beyond the built-in list'
        }
    }

    $extraResult = $null
    $extraControl = $null
    if ($extra) {
        $sample = ($extra -replace '\*', 'x')
        # ZERO remote sha, exactly as the accept run uses. With a FABRICATED
        # remote sha the hook reaches `git merge-base --is-ancestor`, which
        # cannot resolve it and rejects EVERY branch name with a `UMS: `
        # message - so the run passed for a name nothing protects and this
        # "proof" was decorative. A zero remote sha means branch creation,
        # which skips the fast-forward check, leaving the shared-branch rule
        # as the only thing that can reject: measured, an unprotected name
        # then exits 0 while a configured pattern exits non-zero.
        $extraRemote = $SHA_ZERO
        $extraResult = Invoke-HookLine $Shell $HookPath "refs/heads/$sample $SHA_FAKE refs/heads/$sample $extraRemote"

        # CONTROL for the run above, sharing its sha pair on purpose: a name the
        # configuration does not cover must come back CLEAN. This is what stops
        # the decorative version from being reintroduced silently - flip
        # $extraRemote back to a fabricated sha and this control fails, so the
        # installer reports a failed proof instead of a false "verified".
        # Skipped (not failed) in the pathological case where a repository's own
        # patterns match the control name.
        if (@($Patterns | Where-Object { $EXTRA_CONTROL_NAME -like $_ }).Count -eq 0) {
            $extraControl = Invoke-HookLine $Shell $HookPath "refs/heads/$EXTRA_CONTROL_NAME $SHA_FAKE refs/heads/$EXTRA_CONTROL_NAME $extraRemote"
        }
    }

    $saidUms = ($reject.Out -cmatch '(?m)^\s*UMS: ') -and ($reject.Out -cmatch 'Publication Contract')
    $ok = ($reject.Code -ne 0) -and $saidUms -and ($accept.Code -eq 0)
    if ($null -ne $extraResult) {
        # The SHARED-BRANCH message specifically, not any rejection: a
        # rejection for some other reason must not pass as "the list was
        # consulted". `HEAD:<sample>` appears only in the shared-branch
        # advice, and it is ASCII, unlike the Czech prose around it (git's
        # stderr reaches a console code page that mangles diacritics).
        $saidShared = ($extraResult.Out -cmatch '(?m)^\s*UMS: ') -and
                      ($extraResult.Out -cmatch [regex]::Escape("HEAD:$sample"))
        $ok = $ok -and ($extraResult.Code -ne 0) -and $saidShared
        if ($null -ne $extraControl) { $ok = $ok -and ($extraControl.Code -eq 0) }
    }
    return @{
        Ok           = $ok
        Reject       = $reject
        Accept       = $accept
        Extra        = $extraResult
        ExtraControl = $extraControl
        ExtraPattern = $extra
        ExtraSample  = $sample
        SkipReason   = $skipReason
    }
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

# The hook is POSIX sh with no JSON parser, so the configured patterns only
# reach it through this generated file - which also means a configuration
# change does nothing until this script runs again.
#
# Without the loader there is no configuration to read: the whole path is
# skipped rather than fed a fabricated config object, and $protectedPatterns
# stays empty so the third proof run has nothing to claim either.
$protectedPatterns = @()
if ($loaderFound) {
    $repoCfg = Get-UmsRepoConfig $RepoRoot
    $protectedPatterns = @($repoCfg.ProtectedBranches)
    try {
        $listPath = Write-ProtectedList $RepoRoot $protectedPatterns
        Write-Host "protected-branch list ($($repoCfg.Source)) -> $listPath" -ForegroundColor Cyan
        Write-Host "  patterns: $($protectedPatterns -join ', ')" -ForegroundColor DarkGray
    }
    catch {
        Write-Host "WARNING: could not write the protected-branch list: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host '         pre-push falls back to its built-in list (develop, main, master, release/*),' -ForegroundColor Red
        Write-Host '         so any additional protected pattern from the configuration is NOT enforced here.' -ForegroundColor Red
        $script:ListFailed = $true
        $script:ListFailedReason = 'the list could not be written'
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
    $proof = Test-HookIsLive $shell $hook.Path $protectedPatterns
    if ($proof.Ok) {
        Write-Host "verified: pre-push rejects a synthetic push to 'develop' (exit $($proof.Reject.Code)) and accepts a synthetic ticket-branch push (exit 0)." -ForegroundColor Green
        if ($null -ne $proof.Extra) {
            Write-Host "verified: the generated protected-branch list is consulted (pattern '$($proof.ExtraPattern)') - it is NOT in the hook's built-in list, and a synthetic branch-creating push to '$($proof.ExtraSample)' was rejected as a shared branch (exit $($proof.Extra.Code))." -ForegroundColor Green
            if ($null -ne $proof.ExtraControl) {
                Write-Host "          control for that run: the same synthetic shape with an unprotected name ('$EXTRA_CONTROL_NAME') came back clean (exit 0), so the run above discriminates instead of rejecting everything." -ForegroundColor Green
            }
        }
        else {
            # NOT a proof and must not read like one: no run here can tell the
            # generated list from the built-in fallback.
            Write-Host "note: $($proof.SkipReason), so the generated list could not be proven live (the two runs above pass either way)." -ForegroundColor Yellow
        }
        Write-Host "summary: $($hook.Name) -> $($hook.Path)  [installed + verified live]" -ForegroundColor Green
    }
    else {
        Write-Host 'WARNING: the installed pre-push hook did NOT behave like the UMS guard!' -ForegroundColor Red
        Write-Host "  protected-branch run: exit $($proof.Reject.Code) (expected non-zero with a 'UMS:' message)" -ForegroundColor Red
        Write-Host "    output: $($proof.Reject.Out.Trim())" -ForegroundColor Red
        Write-Host "  ticket-branch run:    exit $($proof.Accept.Code) (expected 0, silent)" -ForegroundColor Red
        Write-Host "    output: $($proof.Accept.Out.Trim())" -ForegroundColor Red
        if ($null -ne $proof.Extra) {
            Write-Host "  generated-list run:   exit $($proof.Extra.Code) (expected non-zero with the shared-branch message for '$($proof.ExtraSample)', from the configured pattern '$($proof.ExtraPattern)')" -ForegroundColor Red
            Write-Host "    output: $($proof.Extra.Out.Trim())" -ForegroundColor Red
        }
        if ($null -ne $proof.ExtraControl) {
            Write-Host "  its control run:      exit $($proof.ExtraControl.Code) (expected 0, silent - an unprotected name under the same synthetic shape; non-zero here means the shape rejects EVERYTHING and the run above proves nothing)" -ForegroundColor Red
            Write-Host "    output: $(([string]$proof.ExtraControl.Out).Trim())" -ForegroundColor Red
        }
        Write-Host '  The guarantee is NOT in place here (hook cannot execute, wrong location, another' -ForegroundColor Red
        Write-Host '  core.hooksPath override taking precedence, ...) - investigate before relying on it.' -ForegroundColor Red
        Write-Host "summary: $($hook.Name) -> $($hook.Path)  [installed, PROOF FAILED - treat the guarantee as absent]" -ForegroundColor Red
        $exitCode = $EXIT_PROOF_FAILED
    }
}

# Only when nothing worse happened: a configuration-path failure must never
# mask an absent hook (2), a failed proof (1) or an unproven one (3).
if ($script:ListFailed -and $exitCode -eq $EXIT_OK) {
    Write-Host "summary: the protected-branch list is NOT in place ($script:ListFailedReason) - only the hook's built-in patterns (develop, main, master, release/*) are enforced here, any configured pattern beyond them is not." -ForegroundColor Red
    $exitCode = $EXIT_LIST_FAILED
}

Write-Host '`git push --no-verify` and `git -c core.hooksPath=<other>` both bypass this hook by design.' -ForegroundColor DarkGray
exit $exitCode
