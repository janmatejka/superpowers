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

# Runs the real installer capturing BOTH its output and its exit code. The
# exit code is part of its contract with sync-with-monorepo.ps1: "installed
# and proven live" must never be indistinguishable from "guarantee absent".
function Invoke-Installer([string] $RepoDir, [string] $Src) {
    if (-not $Src) { $Src = (Join-Path $PSScriptRoot '..') }
    $out = & pwsh -NoProfile -File $installScript -RepoRoot $RepoDir -SourceDir $Src 2>&1 | Out-String
    # Flat = whitespace-collapsed copy; phrase assertions run against it so a
    # console line wrap in the captured output cannot break them.
    return @{ Out = $out; Flat = ($out -replace '\s+', ' '); Code = $LASTEXITCODE }
}

$res = Invoke-Installer $work $null
Assert-True (Test-Path (Join-Path $work '.git\hooks\pre-push')) 'pre-push hook byl nainstalován do work/.git/hooks'
Assert-Eq $res.Code 0 'instalátor končí kódem 0, když je hook nainstalován a ověřen'
Assert-Match $res.Flat 'installed \+ verified live' 'instalátor v souhrnu potvrzuje živý hook'

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

# 6. case-insensitive protected-branch matching (must agree with guard-git-push.mjs)
$r = Invoke-GitTry $work @('push', 'origin', 'HEAD:DEVELOP')
Assert-True ($r.Code -ne 0) 'push na DEVELOP (velkými) selže stejně jako na develop'

# 7. tags are out of scope - a tag literally named "develop" passes through.
# Deleted again immediately after (and the branch worktree below is created
# from an explicit refs/heads/develop) so the tag/branch name collision does
# not make "develop" an ambiguous revision for the rest of this suite.
Invoke-GitOk $work @('tag', 'develop') | Out-Null
$r = Invoke-GitTry $work @('push', 'origin', 'refs/tags/develop')
Assert-Eq $r.Code 0 'push tagu pojmenovaného develop projde (tagy jsou mimo rozsah pravidla)'
$r = Invoke-GitTry $work @('push', 'origin', '--delete', 'refs/tags/develop')
Assert-Eq $r.Code 0 'smazání tagu develop projde (tagy jsou mimo rozsah pravidla o mazání větví)'
Invoke-GitOk $work @('tag', '-d', 'develop') | Out-Null

# ---------------------------------------------------------------------------
# 8. FALSE-SUCCESS REGRESSION 1: linked worktree. Hooks are NOT under a
# worktree's own .git/worktrees/<name>/hooks/ - they live in the common dir,
# which only `git rev-parse --git-path` (used by the installer) resolves
# correctly. Proves both that the resolved path matches the main repo's own
# hooks dir, AND that a real push from the worktree is actually rejected.
# ---------------------------------------------------------------------------
$wt = Join-Path $root 'work-wt'
Invoke-GitOk $work @('worktree', 'add', '-b', 'wt-branch', $wt, 'refs/heads/develop') | Out-Null
$res = Invoke-Installer $wt $null
Assert-Eq $res.Code 0 'worktree: instalace do worktree končí kódem 0'

function Resolve-GitPath([string] $RepoDir, [string] $RelPath) {
    $p = (& git -C $RepoDir rev-parse --git-path $RelPath).Trim()
    if (-not [IO.Path]::IsPathRooted($p)) { $p = Join-Path $RepoDir $p }
    return $p
}
$wtHookPath = Resolve-GitPath $wt 'hooks/pre-push'
$mainHookPath = Resolve-GitPath $work 'hooks/pre-push'
Assert-True (Test-Path $wtHookPath) 'worktree: git-path pro pre-push existuje'
Assert-Eq (Resolve-Path $wtHookPath).Path (Resolve-Path $mainHookPath).Path 'worktree: pre-push se resolvuje do STEJNÉHO souboru jako v hlavním repu (společný .git, ne .git/worktrees/<name>/hooks)'
$wtHead = Get-Content -LiteralPath $wtHookPath -TotalCount 5
Assert-Match ($wtHead -join "`n") 'UMS pre-push guard' 'worktree: nainstalovaný hook nese UMS marker'

$developBeforeWt = Get-Sha $origin 'refs/heads/develop'
Add-Content -Path (Join-Path $wt 'f.txt') -Value 'from worktree'
Invoke-GitOk $wt @('commit', '-am', 'wt change') | Out-Null
$r = Invoke-GitTry $wt @('push', 'origin', 'HEAD:develop')
Assert-True ($r.Code -ne 0) 'worktree: push na develop selže (hook resolvován přes git-path, ne uhodnutý z .git souboru)'
Assert-Eq (Get-Sha $origin 'refs/heads/develop') $developBeforeWt 'worktree: remote develop zůstává nezměněný'

# ---------------------------------------------------------------------------
# 9. FALSE-SUCCESS REGRESSION 2: core.hooksPath override. When set, git
# ignores .git/hooks/ entirely - the installer must detect it and install
# into the configured directory instead (own small fixture, to avoid
# perturbing the primary fixture above with a repo-wide config change).
# ---------------------------------------------------------------------------
$root2 = Join-Path ([IO.Path]::GetTempPath()) ("mbprepush2-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$origin2 = Join-Path $root2 'origin.git'
$work2 = Join-Path $root2 'work'
New-Item -ItemType Directory -Force -Path $origin2, $work2 | Out-Null
& git init --bare -q -b develop $origin2 | Out-Null
& git init -q -b develop $work2 | Out-Null
Invoke-GitOk $work2 @('remote', 'add', 'origin', $origin2) | Out-Null
'base' | Out-File -FilePath (Join-Path $work2 'f.txt') -Encoding utf8
Invoke-GitOk $work2 @('add', '-A') | Out-Null
Invoke-GitOk $work2 @('commit', '-m', 'base') | Out-Null
Invoke-GitOk $work2 @('push', '-u', 'origin', 'develop') | Out-Null
Invoke-GitOk $work2 @('config', 'core.hooksPath', 'customhooks') | Out-Null

$res = Invoke-Installer $work2 $null
$customHookPath = Resolve-GitPath $work2 'hooks/pre-push'
Assert-True (Test-Path $customHookPath) 'core.hooksPath: hook je nainstalován tam, kam git skutečně sahá'
Assert-Match $customHookPath 'customhooks' 'core.hooksPath: instalace míří do nakonfigurovaného adresáře, ne do .git/hooks'
Assert-Eq $res.Code 0 'core.hooksPath: instalace proběhne a ověří se (kód 0)'
# RELATIVE core.hooksPath is resolved per working tree, so a run against the
# main clone leaves every linked worktree inert - the installer must say so
# instead of letting a green "verified" imply repository-wide coverage.
Assert-Match $res.Flat 'relative core.hooksPath' 'core.hooksPath: instalátor hlásí, že relativní hodnota se resolvuje per worktree'
Assert-Match $res.Flat 'needs its own run' 'core.hooksPath: instalátor říká, že každý worktree potřebuje vlastní instalaci'

$developBefore2 = Get-Sha $origin2 'refs/heads/develop'
Add-Content -Path (Join-Path $work2 'f.txt') -Value 'change'
Invoke-GitOk $work2 @('commit', '-am', 'devchange') | Out-Null
$r = Invoke-GitTry $work2 @('push', 'origin', 'develop')
Assert-True ($r.Code -ne 0) 'core.hooksPath: push na develop stále selže (hook nainstalován na správném místě)'
Assert-Eq (Get-Sha $origin2 'refs/heads/develop') $developBefore2 'core.hooksPath: remote develop zůstává nezměněný'

# 9b. The limitation the warning above names, proven end-to-end: a linked
# worktree resolves a RELATIVE core.hooksPath against its own root, so the
# main clone's install genuinely does not cover it (a real push to develop
# goes through) - and a run against the worktree itself genuinely does.
$wt2 = Join-Path $root2 'work-wt'
Invoke-GitOk $work2 @('worktree', 'add', '-b', 'wt2-branch', $wt2, 'refs/heads/develop') | Out-Null
Assert-True (-not (Test-Path (Join-Path $wt2 'customhooks\pre-push'))) 'relativní core.hooksPath: worktree nedostal hook z instalace do hlavního klonu'
Add-Content -Path (Join-Path $wt2 'f.txt') -Value 'from unguarded worktree'
Invoke-GitOk $wt2 @('commit', '-am', 'wt2 change') | Out-Null
$r = Invoke-GitTry $wt2 @('push', 'origin', 'HEAD:develop')
Assert-Eq $r.Code 0 'relativní core.hooksPath: push z worktree PROJDE, dokud tam instalace neproběhla (proto to varování)'

$res = Invoke-Installer $wt2 $null
Assert-True (Test-Path (Join-Path $wt2 'customhooks\pre-push')) 'relativní core.hooksPath: instalace do worktree míří do jeho vlastního customhooks/'
$developBefore2b = Get-Sha $origin2 'refs/heads/develop'
Add-Content -Path (Join-Path $wt2 'f.txt') -Value 'again'
Invoke-GitOk $wt2 @('commit', '-am', 'wt2 change 2') | Out-Null
$r = Invoke-GitTry $wt2 @('push', 'origin', 'HEAD:develop')
Assert-True ($r.Code -ne 0) 'relativní core.hooksPath: po vlastní instalaci je push z worktree na develop zamítnut'
Assert-Eq (Get-Sha $origin2 'refs/heads/develop') $developBefore2b 'relativní core.hooksPath: remote develop se po zamítnutí nepohnul'

Remove-Item -Recurse -Force $root2

# ---------------------------------------------------------------------------
# 10. foreign-hook marker matched only near the top of the file, not
# anywhere in it - a foreign hook whose body happens to mention similar
# wording well past the first few lines must NOT be mistaken for ours.
# ---------------------------------------------------------------------------
$root3 = Join-Path ([IO.Path]::GetTempPath()) ("mbprepush3-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $root3 | Out-Null
& git init -q $root3 | Out-Null
$foreignHook = @(
    '#!/bin/sh'
    'echo "line 2 - somebody elses hook"'
    'echo "line 3"'
    'echo "line 4"'
    'echo "line 5"'
    '# only way down here: UMS pre-push guard (Publication Contract) is mentioned in passing'
    'exit 0'
) -join "`n"
New-Item -ItemType Directory -Force -Path (Join-Path $root3 '.git\hooks') | Out-Null
Set-Content -LiteralPath (Join-Path $root3 '.git\hooks\pre-push') -Value $foreignHook -NoNewline
$res = Invoke-Installer $root3 $null
$afterInstall = Get-Content -LiteralPath (Join-Path $root3 '.git\hooks\pre-push') -Raw
Assert-Match $afterInstall 'somebody elses hook' 'cizí hook zmiňující marker teprve hluboko v souboru NENÍ přepsán'
# A SKIP that prints no summary and exits 0 is indistinguishable from a
# successful install for any script calling this - the whole failure mode of
# this layer is "reported success, inert guarantee".
Assert-Eq $res.Code 2 'cizí hook: instalátor končí kódem 2 (záruka NENÍ na místě), ne nulou'
Assert-Match $res.Flat 'NOT INSTALLED' 'cizí hook: souhrn výslovně říká, že hook nebyl nainstalován'
Assert-Match $res.Flat 'guarantee is ABSENT' 'cizí hook: souhrn pojmenuje chybějící záruku'

Remove-Item -Recurse -Force $root3

# ---------------------------------------------------------------------------
# 11. FALSE-SUCCESS REGRESSION 3: a hook that CANNOT EXECUTE must never be
# reported as verified. The self-check used to be `exit != 0 -and $out -match
# 'UMS'`; PowerShell's -match is case-insensitive and bash quotes the hook
# path in its own error text, so a broken hook passed as verified for every
# repository living under a directory whose name contains "ums" - including
# this layer's own deployment target d:\_datasys\ums. Both spellings of the
# fixture path are exercised: the outcome must not depend on the path at all.
# ---------------------------------------------------------------------------
$brokenSrc = Join-Path ([IO.Path]::GetTempPath()) ("mbbrokensrc-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $brokenSrc | Out-Null
# Carries our marker (so it counts as "ours" on re-install) but points at an
# interpreter that does not exist - exactly the shape of an installed-but-
# inert hook. `exit 1` in the body so that even a shell that fell back to
# running it as a plain script would still fail the accept case.
$brokenHook = @(
    '#!/nonexistent/interpreter'
    '# UMS pre-push guard (Publication Contract)'
    'exit 1'
) -join "`n"
Set-Content -LiteralPath (Join-Path $brokenSrc 'pre-push') -Value $brokenHook -NoNewline

foreach ($seed in @('ums-badshebang', 'neutral-badshebang')) {
    $rBroken = Join-Path ([IO.Path]::GetTempPath()) ("$seed-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Force -Path $rBroken | Out-Null
    & git init -q -b develop $rBroken | Out-Null
    $res = Invoke-Installer $rBroken $brokenSrc
    Assert-True ($res.Code -ne 0) "$seed : nespustitelný hook -> instalátor končí nenulovým kódem"
    Assert-Match $res.Flat 'PROOF FAILED' "$seed : nespustitelný hook je v souhrnu označen jako selhání důkazu"
    Assert-NotMatch $res.Flat 'verified live' "$seed : nespustitelný hook NENÍ hlášen jako ověřený"
    Remove-Item -Recurse -Force $rBroken
}
Remove-Item -Recurse -Force $brokenSrc

# Control for the same finding: the REAL hook under a path containing "ums"
# must still verify green - the fix must reject broken hooks, not everything.
$rGood = Join-Path ([IO.Path]::GetTempPath()) ("ums-goodhook-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $rGood | Out-Null
& git init -q -b develop $rGood | Out-Null
$res = Invoke-Installer $rGood $null
Assert-Eq $res.Code 0 'kontrola: skutečný hook pod cestou obsahující "ums" končí kódem 0'
Assert-Match $res.Flat 'installed \+ verified live' 'kontrola: skutečný hook pod cestou obsahující "ums" je ověřen'
Remove-Item -Recurse -Force $rGood

# ---------------------------------------------------------------------------
# 12. A GLOBAL core.hooksPath silently turns a per-repository install into a
# per-user one - the installer must say so. GIT_CONFIG_GLOBAL points git at a
# throwaway global config, so the developer's real ~/.gitconfig is untouched.
# ---------------------------------------------------------------------------
$root6 = Join-Path ([IO.Path]::GetTempPath()) ("mbprepush6-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$globalHooks = Join-Path $root6 'globalhooks'
New-Item -ItemType Directory -Force -Path $root6, $globalHooks | Out-Null
& git init -q -b develop $root6 | Out-Null
$fakeGlobalCfg = Join-Path $root6 'fake-gitconfig'
Set-Content -LiteralPath $fakeGlobalCfg -Value "[core]`n`thooksPath = $($globalHooks -replace '\\', '/')`n"
$prevGlobalCfg = $env:GIT_CONFIG_GLOBAL
$env:GIT_CONFIG_GLOBAL = $fakeGlobalCfg
try {
    $res = Invoke-Installer $root6 $null
}
finally {
    if ($null -eq $prevGlobalCfg) { Remove-Item Env:GIT_CONFIG_GLOBAL -ErrorAction SilentlyContinue }
    else { $env:GIT_CONFIG_GLOBAL = $prevGlobalCfg }
}
Assert-True (Test-Path (Join-Path $globalHooks 'pre-push')) 'globální core.hooksPath: hook je nainstalován do nakonfigurovaného adresáře'
Assert-Match $res.Flat 'global config' 'globální core.hooksPath: instalátor pojmenuje, že hodnota není z tohoto repozitáře'
Assert-Match $res.Flat 'EVERY repository' 'globální core.hooksPath: instalátor říká, že instalace platí pro všechny repozitáře uživatele'
Remove-Item -Recurse -Force $root6

# ---------------------------------------------------------------------------
# 13. The refs/heads/ scope gate and the protected-name check are two halves
# of one rule: the gate used to be case-sensitive while the name below it was
# case-folded, so `refs/HEADS/develop` skipped the guard entirely. Driven as a
# synthetic stdin line (a real push of that spelling is refused by the
# receiving repo before the hook's behaviour becomes observable).
# ---------------------------------------------------------------------------
$hookInWork = (Resolve-GitPath $work 'hooks/pre-push') -replace '\\', '/'
$fakeSha = '0123456789abcdef0123456789abcdef01234567'
$out = & $gitBash -c 'printf "refs/heads/develop %s refs/HEADS/develop %s\n" "$1" "$1" | "$2" origin verify' _ $fakeSha $hookInWork 2>&1 | Out-String
Assert-True ($LASTEXITCODE -ne 0) 'refs/HEADS/develop (jiná velikost v prefixu) je zamítnuto stejně jako refs/heads/develop'
Assert-Match $out 'UMS' 'refs/HEADS/develop: zamítnutí nese UMS vysvětlení'
Assert-Match $out "'develop'" 'refs/HEADS/develop: hláška pojmenuje větev develop (prefix je odstraněn bez ohledu na velikost písmen)'
# ... and a tag still passes through untouched, whatever its case.
$out = & $gitBash -c 'printf "refs/tags/v1 %s refs/TAGS/develop %s\n" "$1" "$1" | "$2" origin verify' _ $fakeSha $hookInWork 2>&1 | Out-String
Assert-Eq $LASTEXITCODE 0 'refs/TAGS/develop zůstává mimo rozsah (tagy se nehlídají)'

# ---------------------------------------------------------------------------
# 14. sync-with-monorepo.ps1 must install the hook AFTER the sync, not before.
# With the default -Direction FromMonorepo the fork's hooks/ is rewritten by
# the very run doing the installing, so installing first deploys the fork's
# pre-sync copy instead of the one the run just made authoritative. Proven
# with two distinguishable variants of the real hook (both functional, both
# keeping the marker on line 2) in a throwaway monorepo + fork pair.
# ---------------------------------------------------------------------------
$syncScript = Join-Path $PSScriptRoot '..\..\..\sync-with-monorepo.ps1'
$realUms = Resolve-Path (Join-Path $PSScriptRoot '..\..\..')
$root7 = Join-Path ([IO.Path]::GetTempPath()) ("mbsync-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$fakeMono = Join-Path $root7 'monorepo'
$forkCopy = Join-Path $root7 'fork-ums'
New-Item -ItemType Directory -Force -Path $fakeMono | Out-Null
Copy-Item -Recurse -Force -LiteralPath $realUms.Path -Destination $forkCopy

# minimal but complete monorepo shape for the claude+Monorepo branch
New-Item -ItemType Directory -Force -Path @(
    (Join-Path $fakeMono '.claude\scripts'),
    (Join-Path $fakeMono '.claude\skills\shared'),
    (Join-Path $fakeMono '.claude\skills\mb-fake'),
    (Join-Path $fakeMono '.claude\hooks')
) | Out-Null
Set-Content -LiteralPath (Join-Path $fakeMono '.claude\settings.json') -Value '{}'
Set-Content -LiteralPath (Join-Path $fakeMono '.claude\scripts\revendor-superpowers.ps1') -Value '# stub'
Set-Content -LiteralPath (Join-Path $fakeMono '.claude\skills\shared\x.md') -Value 'shared stub'
Set-Content -LiteralPath (Join-Path $fakeMono '.claude\skills\mb-fake\y.md') -Value 'skill stub'
Set-Content -LiteralPath (Join-Path $fakeMono 'CLAUDE.md') -Value "# stub`n"
Copy-Item -Force (Join-Path $realUms.Path '.claude\hooks\install-git-hooks.ps1') (Join-Path $fakeMono '.claude\hooks\install-git-hooks.ps1')
& git init -q -b develop $fakeMono | Out-Null

# two variants of the REAL hook, tagged on line 3 (marker stays on line 2)
$realHookLines = @(Get-Content -LiteralPath (Join-Path $realUms.Path '.claude\hooks\pre-push'))
function Write-TaggedHook([string] $Path, [string] $Tag) {
    $lines = @($realHookLines[0], $realHookLines[1], "# $Tag") + $realHookLines[2..($realHookLines.Count - 1)]
    [IO.File]::WriteAllText($Path, (($lines -join "`n") + "`n"))
}
Write-TaggedHook (Join-Path $fakeMono '.claude\hooks\pre-push') 'MONOREPO-VERSION'
Write-TaggedHook (Join-Path $forkCopy '.claude\hooks\pre-push') 'FORK-PRESYNC-VERSION'

$syncOut = & pwsh -NoProfile -File $syncScript -Agent claude -Scope Monorepo -Direction FromMonorepo `
    -MonorepoRoot $fakeMono -ForkUmsDir $forkCopy 2>&1 | Out-String
$syncCode = $LASTEXITCODE
$installedInMono = Get-Content -LiteralPath (Join-Path $fakeMono '.git\hooks\pre-push') -Raw
Assert-Eq $syncCode 0 'sync: běh claude+Monorepo skončí bez chyby'
Assert-Match $installedInMono 'MONOREPO-VERSION' 'sync: nainstalovaný hook pochází z verze PO synchronizaci (instalace běží až po sync)'
Assert-NotMatch $installedInMono 'FORK-PRESYNC-VERSION' 'sync: nainstalovaný hook NENÍ předsynchronizační kopie z forku'
Assert-Match ($syncOut -replace '\s+', ' ') 'installed \+ verified live' 'sync: instalátor v rámci syncu potvrdí živý hook'

# ... and when the guarantee is NOT in place, the sync must say so instead of
# ending in a wall of "synced ..." lines.
$brokenLines = @('#!/nonexistent/interpreter', $realHookLines[1], 'exit 1')
[IO.File]::WriteAllText((Join-Path $fakeMono '.claude\hooks\pre-push'), (($brokenLines -join "`n") + "`n"))
$syncOut2 = & pwsh -NoProfile -File $syncScript -Agent claude -Scope Monorepo -Direction FromMonorepo `
    -MonorepoRoot $fakeMono -ForkUmsDir $forkCopy 2>&1 | Out-String
Assert-Match ($syncOut2 -replace '\s+', ' ') 'guarantee is NOT confirmed' 'sync: nenulový kód instalátoru je v syncu vidět jako varování'

Remove-Item -Recurse -Force $root7
Remove-Item -Recurse -Force $root

Complete-Tests
