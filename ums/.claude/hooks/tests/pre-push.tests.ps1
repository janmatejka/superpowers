Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '_assert.ps1')
$ErrorActionPreference = 'Stop'

# End-to-end proof of the real Publication Contract enforcement boundary:
# the git `pre-push` hook. Everything here is a REAL git push against a
# local bare "origin" — no network. Own fixture (per-directory convention),
# modeled on ums/.claude/skills/mb-doc-index/tests/new-fixture-repo.ps1 but
# simpler (this suite only needs one protected + one ticket branch).

function Invoke-GitOk([string] $RepoDir, [string[]] $GitArgs) {
    $out = & git -C $RepoDir -c user.name=Test -c user.email=test@example.com @GitArgs 2>&1
    if ($LASTEXITCODE -ne 0) { throw "git $($GitArgs -join ' ') failed: $out" }
    return $out
}

# Runs a push attempt without throwing - returns @{ Out=<combined output>; Code=<exit code> }.
function Invoke-GitTry([string] $RepoDir, [string[]] $GitArgs) {
    $out = & git -C $RepoDir @GitArgs 2>&1 | Out-String
    return @{ Out = $out; Code = $LASTEXITCODE }
}

# Same, but without an implicit `-C` - needed for the `--git-dir` bypass test
# so it is not combined with a redundant/conflicting `-C`.
function Invoke-GitTryRaw([string[]] $GitArgs) {
    $out = & git @GitArgs 2>&1 | Out-String
    return @{ Out = $out; Code = $LASTEXITCODE }
}

function Get-Sha([string] $RepoDir, [string] $Ref) {
    $out = & git -C $RepoDir rev-parse $Ref 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }
    return $out.Trim()
}

# Resolve Git for Windows' own bash.exe - NOT whatever "bash" is first on
# PATH, which on a machine with WSL installed is frequently the WSL launcher
# stub (confirmed during development: it silently drops positional args
# passed after `-c script`, so `cd "$1"` never receives the fixture path and
# the push runs from the wrong directory instead of failing outright).
function Find-GitBash {
    $gitCmd = Get-Command git -ErrorAction Stop
    # git.exe's own directory relative to the Git for Windows install root
    # varies (cmd\, mingw64\bin\, bin\ have all been observed depending on
    # how the process's PATH was assembled) - climb ancestors until bash.exe
    # turns up rather than assuming a fixed depth.
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
    throw "Could not locate Git Bash near $($gitCmd.Source) - needed for the 'bash -c' bypass test."
}
$gitBash = Find-GitBash

# --------------------------------------------------------------- fixture --
$root = Join-Path ([IO.Path]::GetTempPath()) ("mbprepush-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$origin = Join-Path $root 'origin.git'
$work = Join-Path $root 'work'
New-Item -ItemType Directory -Force -Path $origin, $work | Out-Null
& git init --bare -q -b develop $origin | Out-Null
& git init -q -b develop $work | Out-Null
Invoke-GitOk $work @('remote', 'add', 'origin', $origin) | Out-Null

'base' | Out-File -FilePath (Join-Path $work 'f.txt') -Encoding utf8
Invoke-GitOk $work @('add', '-A') | Out-Null
Invoke-GitOk $work @('commit', '-m', 'base') | Out-Null
Invoke-GitOk $work @('push', '-u', 'origin', 'develop') | Out-Null

Invoke-GitOk $work @('checkout', '-b', 'feature/x') | Out-Null
'feature' | Out-File -FilePath (Join-Path $work 'g.txt') -Encoding utf8
Invoke-GitOk $work @('add', '-A') | Out-Null
Invoke-GitOk $work @('commit', '-m', 'feature') | Out-Null
Invoke-GitOk $work @('push', '-u', 'origin', 'feature/x') | Out-Null

# install the hook under test via the real installer, into the WORK clone
# (pre-push runs client-side, in the repo doing the pushing).
$installScript = Join-Path $PSScriptRoot '..\install-git-hooks.ps1'
& pwsh -NoProfile -File $installScript -RepoRoot $work -SourceDir (Join-Path $PSScriptRoot '..') | Out-Null
Assert-True (Test-Path (Join-Path $work '.git\hooks\pre-push')) 'pre-push hook byl nainstalován do work/.git/hooks'

# ------------------------------------------------------------------ tests
# 1. push to develop -> rejected, remote unmoved, Czech message shown
Invoke-GitOk $work @('checkout', 'develop') | Out-Null
$developBefore = Get-Sha $origin 'refs/heads/develop'
Add-Content -Path (Join-Path $work 'f.txt') -Value 'change'
Invoke-GitOk $work @('commit', '-am', 'develop change') | Out-Null
$r = Invoke-GitTry $work @('push', 'origin', 'develop')
Assert-True ($r.Code -ne 0) 'push na develop selže (pre-push hook)'
Assert-Match $r.Out 'UMS' 'chybová hláška obsahuje UMS vysvětlení'
Assert-Eq (Get-Sha $origin 'refs/heads/develop') $developBefore 'remote develop zůstává nezměněný po zamítnutém pushi'

# 2. push to the ticket branch -> succeeds
Invoke-GitOk $work @('checkout', 'feature/x') | Out-Null
Add-Content -Path (Join-Path $work 'g.txt') -Value 'change'
Invoke-GitOk $work @('commit', '-am', 'feature change') | Out-Null
$r = Invoke-GitTry $work @('push', 'origin', 'feature/x')
Assert-Eq $r.Code 0 'push na tiketovou větev projde (pre-push hook)'
Assert-Eq (Get-Sha $origin 'refs/heads/feature/x') (Get-Sha $work 'feature/x') 'remote feature/x odpovídá lokální po úspěšném pushi'

# 3. deletion -> rejected, remote branch still present
$beforeDelete = Get-Sha $origin 'refs/heads/feature/x'
$r = Invoke-GitTry $work @('push', 'origin', '--delete', 'feature/x')
Assert-True ($r.Code -ne 0) 'mazání větve přes push selže (pre-push hook)'
Assert-Eq (Get-Sha $origin 'refs/heads/feature/x') $beforeDelete 'vzdálená feature/x nebyla smazána'

# 4. forced non-fast-forward -> rejected
Invoke-GitOk $work @('reset', '--hard', 'HEAD~1') | Out-Null
Add-Content -Path (Join-Path $work 'g.txt') -Value 'diverge'
Invoke-GitOk $work @('commit', '-am', 'diverging change') | Out-Null
$beforeForce = Get-Sha $origin 'refs/heads/feature/x'
$r = Invoke-GitTry $work @('push', '--force', 'origin', 'feature/x')
Assert-True ($r.Code -ne 0) 'vynucený (force) non-fast-forward push selže (pre-push hook)'
Assert-Eq (Get-Sha $origin 'refs/heads/feature/x') $beforeForce 'vzdálená feature/x se po zamítnutém force pushi nezměnila'

# 5. bypasses that defeated the PreToolUse hook - all rejected here instead
Invoke-GitOk $work @('checkout', 'develop') | Out-Null
$r = Invoke-GitTry $work @('push', 'origin', 'HEAD')
Assert-True ($r.Code -ne 0) 'git push origin HEAD na develop selže (git resolvuje HEAD před voláním hooku)'

$r = Invoke-GitTryRaw @('--git-dir', (Join-Path $work '.git'), '--work-tree', $work, 'push', 'origin', 'develop')
Assert-True ($r.Code -ne 0) 'git --git-dir push na develop selže (hook je vázán na .git/hooks, ne na tvar příkazu)'

$out = & $gitBash -c 'cd "$1" && git push origin develop' _ $work 2>&1 | Out-String
Assert-True ($LASTEXITCODE -ne 0) 'push spuštěný přes bash -c selže (pre-push hook)'
Assert-Match $out 'UMS' 'bash -c push hláška obsahuje UMS vysvětlení'

Remove-Item -Recurse -Force $root

Complete-Tests
