Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '_assert.ps1')
$ErrorActionPreference = 'Stop'

# The hook only enforces inside an agent session (Task 4) - this suite's own
# assertions about REJECTED pushes need the marker set at suite scope, not
# borrowed from whatever ambient CLAUDECODE/AI_AGENT the runner happens to
# export. Run by a human from a plain terminal or by CI this would otherwise
# be absent and every "push is rejected" assertion below would go red for an
# environmental reason, not a hook regression. The two marker-gate helpers
# further down save/clear/restore around themselves, so they are unaffected.
$env:MB_AGENT_SESSION = '1'

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
function Invoke-InstallerScript([string] $Script, [string] $RepoDir, [string] $Src) {
    $out = & pwsh -NoProfile -File $Script -RepoRoot $RepoDir -SourceDir $Src 2>&1 | Out-String
    # Flat = whitespace-collapsed copy; phrase assertions run against it so a
    # console line wrap in the captured output cannot break them.
    return @{ Out = $out; Flat = ($out -replace '\s+', ' '); Code = $LASTEXITCODE }
}

function Invoke-Installer([string] $RepoDir, [string] $Src) {
    if (-not $Src) { $Src = (Join-Path $PSScriptRoot '..') }
    return Invoke-InstallerScript $installScript $RepoDir $Src
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
    (Join-Path $fakeMono '.claude\skills\shared\scripts'),
    (Join-Path $fakeMono '.claude\skills\mb-fake'),
    (Join-Path $fakeMono '.claude\hooks')
) | Out-Null
Set-Content -LiteralPath (Join-Path $fakeMono '.claude\settings.json') -Value '{}'
Set-Content -LiteralPath (Join-Path $fakeMono '.claude\scripts\revendor-superpowers.ps1') -Value '# stub'
Set-Content -LiteralPath (Join-Path $fakeMono '.claude\skills\shared\x.md') -Value 'shared stub'
# The REAL loader, not a stub, and not optional scenery: `skills\shared` is
# MIRRORED by the sync (destination replaced outright), so a fake monorepo
# without it leaves the fork copy without one either - and the installer treats
# a missing loader as a hard error, which the sync then downgrades to a warning
# with no hook installed at all. A real monorepo carrying this layer has it.
Copy-Item -Force (Join-Path $realUms.Path '.claude\skills\shared\scripts\Get-UmsRepoConfig.ps1') `
    (Join-Path $fakeMono '.claude\skills\shared\scripts\Get-UmsRepoConfig.ps1')
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

# ---------------------------------------------------------------------------
# 15. THE HUMAN PATH, end to end. The layer tells the user to publish
# `develop` themselves, but a git hook cannot tell a human from an agent, so
# without an explicit escape the hook rejects the very command the layer just
# handed over — and mb-jira-update then refuses to move the ticket to "Test"
# because the merge commit is not on origin. MB_HUMAN_PUSH=1 is that escape:
# a REAL push to a protected branch must succeed with it and still fail
# without it, and the rejection must name it so the user learns the way out at
# the moment they hit the wall. Its SCOPE — it lifts the whole guard, deletion
# and force push included — and the transitional acceptance of the old name
# are proven on their own fixture at the end of this suite.
# ---------------------------------------------------------------------------
Invoke-GitOk $work @('checkout', 'develop') | Out-Null
$developBeforeEscape = Get-Sha $origin 'refs/heads/develop'
$r = Invoke-GitTry $work @('push', 'origin', 'develop')
Assert-True ($r.Code -ne 0) 'bez proměnné je push na develop stále zamítnut'
Assert-Match $r.Out 'MB_HUMAN_PUSH=1' 'zamítnutí samo pojmenuje únikovou cestu pro člověka'
Assert-Match $r.Out 'agent ji nikdy nenastavuje' 'zamítnutí říká, že výjimka patří člověku, ne agentovi'
Assert-Eq (Get-Sha $origin 'refs/heads/develop') $developBeforeEscape 'remote develop se po zamítnutí nepohnul'

# Set narrowly and always restored: a leaked escape would silently disarm the
# guarantee for every later assertion in this suite.
function Invoke-WithEscape([scriptblock] $Body) {
    $prev = $env:MB_HUMAN_PUSH
    $env:MB_HUMAN_PUSH = '1'
    try { & $Body }
    finally {
        if ($null -eq $prev) { Remove-Item Env:MB_HUMAN_PUSH -ErrorAction SilentlyContinue }
        else { $env:MB_HUMAN_PUSH = $prev }
    }
}

$r = Invoke-WithEscape { Invoke-GitTry $work @('push', 'origin', 'develop') }
Assert-Eq $r.Code 0 's MB_HUMAN_PUSH=1 skutečný push na develop projde'
# ASCII-only pattern on purpose: git's stderr reaches this suite through the
# console code page, which mangles diacritics (the other Czech assertions
# above match ASCII substrings for the same reason).
Assert-Match $r.Out 'UMS: MB_HUMAN_PUSH=1' 'povolený push je ohlášen, ne tichý'
Assert-Eq (Get-Sha $origin 'refs/heads/develop') (Get-Sha $work 'develop') 'remote develop po povoleném pushi odpovídá lokálnímu'

# And it is gone again afterwards — the guarantee is back in place.
Add-Content -Path (Join-Path $work 'f.txt') -Value 'after escape'
Invoke-GitOk $work @('commit', '-am', 'develop change after escape') | Out-Null
$developAfterEscape = Get-Sha $origin 'refs/heads/develop'
$r = Invoke-GitTry $work @('push', 'origin', 'develop')
Assert-True ($r.Code -ne 0) 'po odstranění proměnné je push na develop opět zamítnut'
Assert-Eq (Get-Sha $origin 'refs/heads/develop') $developAfterEscape 'remote develop se po opětovném zamítnutí nepohnul'

# ---------------------------------------------------------------------------
# 16. The protected-branch list is CONFIGURATION, not hook body. pre-push is
# POSIX sh with no JSON parser, so install-git-hooks.ps1 materializes the
# repository's `protectedBranches` into <git-common-dir>/ums-protected-branches
# (one glob per line, `#` starts a comment) and the hook reads that file. The
# generator is a later task, so the file is written BY HAND here.
#
# The governing rule these four cases pin down: a missing, empty or
# comment-only file falls back to the BUILT-IN list, because degradation must
# always lead to MORE protection, never less.
# ---------------------------------------------------------------------------

# The hook resolves the file through `git rev-parse --git-common-dir` — for a
# linked worktree that is the MAIN repo's .git, not the worktree's own, so a
# fixture must not simply assume "<repo>\.git".
function Resolve-GitCommonDir([string] $RepoDir) {
    $p = (& git -C $RepoDir rev-parse --git-common-dir).Trim()
    if (-not [IO.Path]::IsPathRooted($p)) { $p = Join-Path $RepoDir $p }
    return (Resolve-Path $p).Path
}

# LF endings on purpose — the shape the generator writes, so these cases pin the
# NORMAL path. The hook does strip CRs as well as comments and blanks
# (`tr -d '[:blank:]\r'`, whose own comment explains why the CR deletion is
# load-bearing), so a CRLF list is tolerated rather than fatal; 16g and 16h below
# are the cases that assert exactly that, 16h under an emulated non-msys `sh`.
# Do not read this helper as evidence that CRLF would break the hook — it would
# not, and the hook forbids that regression on purpose.
function Write-ProtectedList([string] $Path, [string[]] $Lines) {
    [IO.File]::WriteAllText($Path, (($Lines -join "`n") + "`n"))
}

$protectedFile = Join-Path (Resolve-GitCommonDir $work) 'ums-protected-branches'
Invoke-GitOk $work @('checkout', '-b', 'Branches/5.37', 'refs/heads/feature/x') | Out-Null
'maint' | Out-File -FilePath (Join-Path $work 'h.txt') -Encoding utf8
Invoke-GitOk $work @('add', 'h.txt') | Out-Null
Invoke-GitOk $work @('commit', '-m', 'maint base') | Out-Null

# 16a. Without the generated list, `Branches/5.37` PASSES: the built-in
# fallback does not contain `Branches/*`. This is what makes the fallback a
# fallback rather than a second hardcoded list — if this case ever went red,
# the "configuration" would be decoration.
$r = Invoke-GitTry $work @('push', 'origin', 'HEAD:refs/heads/Branches/5.37')
Assert-Eq $r.Code 0 'bez generovaného seznamu push do Branches/5.37 projde (vestavěný fallback Branches/* nezná)'

# 16b. With `Branches/*` configured, the very same branch is rejected — the
# real reason this task exists (this fork's maintenance branches Branches/5.33
# -5.37 were unprotected, `release/*` never matched them).
#
# An untracked `branches/` DIRECTORY in the working tree is part of the case,
# not scenery: the hook splits the pattern list with an unquoted expansion, and
# an unquoted expansion is also PATHNAME-expanded, so without `set -f` the
# lowercased pattern `branches/*` gets replaced by the files in that directory
# and the protection silently disappears. Removing this directory would keep
# the case green while quietly retiring that half of the proof.
New-Item -ItemType Directory -Force -Path (Join-Path $work 'branches') | Out-Null
Set-Content -LiteralPath (Join-Path $work 'branches\notes.txt') -Value 'glob bait'
Write-ProtectedList $protectedFile @(
    '# generated from memory-bank/ums-repo.json by install-git-hooks.ps1',
    '',
    'develop',
    'Branches/*   # trailing comment, and the case folding of the pattern'
)
Add-Content -Path (Join-Path $work 'h.txt') -Value 'maint change'
Invoke-GitOk $work @('commit', '-am', 'maint change') | Out-Null
$maintBefore = Get-Sha $origin 'refs/heads/Branches/5.37'
$r = Invoke-GitTry $work @('push', 'origin', 'HEAD:refs/heads/Branches/5.37')
Assert-True (($r.Code -ne 0) -and ($r.Out -match 'UMS') -and ((Get-Sha $origin 'refs/heads/Branches/5.37') -eq $maintBefore)) 'Branches/5.37 je zamítnuta, když ji generovaný seznam obsahuje (UMS hláška, remote se nepohnul)'

# 16c. Fallback must not TAKE protection away: with the file gone again,
# `develop` is still rejected.
Remove-Item -LiteralPath $protectedFile -Force
Invoke-GitOk $work @('checkout', 'develop') | Out-Null
$developBeforeFallback = Get-Sha $origin 'refs/heads/develop'
$r = Invoke-GitTry $work @('push', 'origin', 'develop')
Assert-True (($r.Code -ne 0) -and ((Get-Sha $origin 'refs/heads/develop') -eq $developBeforeFallback)) 'develop je zamítnutý i bez generovaného seznamu (degradace vede k více ochrany, ne k méně)'

# 16d. A file with nothing but comments and blank lines must behave like a
# MISSING file, not like "nothing is protected" — the shape a half-written or
# emptied generated file takes. Both halves asserted together: develop stays
# protected AND Branches/5.37 goes back to passing, which is exactly the
# built-in list and not "everything allowed".
Write-ProtectedList $protectedFile @('# nothing configured here', '', '   ', '# not even here')
$rDevelop = Invoke-GitTry $work @('push', 'origin', 'develop')
Invoke-GitOk $work @('checkout', 'Branches/5.37') | Out-Null
$rMaint = Invoke-GitTry $work @('push', 'origin', 'HEAD:refs/heads/Branches/5.37')
Assert-True (($rDevelop.Code -ne 0) -and ($rMaint.Code -eq 0)) 'seznam jen s komentáři a prázdnými řádky se chová jako chybějící soubor (develop chráněný, Branches/5.37 ne), ne jako „nic není chráněné"'

# 16e. The advice in the shared-branch rejection must be a command that works
# where the user actually is: in a ticket clone WITHOUT a local `develop`,
# `git push origin develop` fails on an unknown local ref, so the refspec form
# is the only one that runs. (Reuses the rejection captured just above.)
Assert-Match $rDevelop.Out 'HEAD:develop' 'zamítnutí sdílené větve radí refspecový tvar HEAD:<větev> (funguje i v klonu bez lokální báze)'

# 16f. Non-fast-forward has two very different causes — a rewritten history
# and a base that simply moved on — and the message must name the second, or
# the reader treats a routine "fetch + merge" as a forbidden force push.
#
# Captured through a SHELL-LEVEL redirect and read back as UTF-8: git's stderr
# otherwise reaches this suite through the console code page, which mangles
# diacritics (hence the ASCII-only assertions elsewhere). The word under test
# is Czech, so this one case needs the real bytes.
$nonFfErrFile = Join-Path $root 'nonff.err'
& $gitBash -c 'cd "$1" && git push --force origin feature/x 2>"$2"' _ $work ($nonFfErrFile -replace '\\', '/') 2>&1 | Out-Null
$nonFfErr = Get-Content -LiteralPath $nonFfErrFile -Raw -Encoding utf8
Assert-Match $nonFfErr 'báze' 'zamítnutí non-fast-forward pojmenuje pohnutou bázi (odlišení od vynuceného přepisu historie)'

# CRLF twin of Write-ProtectedList. A generator running on Windows can easily
# produce this shape (Set-Content / Out-File default to CRLF), so the hook must
# tolerate it rather than depend on the generator getting it right: the failure
# mode is silent and total — every pattern becomes `develop\r`, the list is
# NON-empty so the fallback never fires, nothing matches, and the repository is
# unprotected while hook and configuration both look correct.
function Write-ProtectedListCrlf([string] $Path, [string[]] $Lines) {
    [IO.File]::WriteAllText($Path, (($Lines -join "`r`n") + "`r`n"))
}

# 16g. CRLF list, real push, protected branch still rejected.
#
# HONEST SCOPE: this case cannot go red on Git for Windows. Measured, both
# stages of the loader pipeline drop a trailing CR on their own here — GfW
# `sed` and `grep` read in TEXT mode — so the CR never reaches the pattern.
# The exposure is a CRLF list read by a NON-msys `sh` (Linux, macOS, WSL bash
# against a shared checkout), where neither tool converts. This case is the
# cross-platform guard; 16h below is the one that can actually fail here.
Write-ProtectedListCrlf $protectedFile @('develop', 'Branches/*')
$developBeforeCrlf = Get-Sha $origin 'refs/heads/develop'
$r = Invoke-GitTry $work @('push', 'origin', 'develop')
Assert-True (($r.Code -ne 0) -and ((Get-Sha $origin 'refs/heads/develop') -eq $developBeforeCrlf)) 'seznam s CRLF řádkováním chrání dál (CR se ze vzorů odstraní), remote se nepohnul'

# 16h. The same property under an emulated NON-msys /bin/sh, so it is covered
# on the platform this suite actually runs on. The two tools the loader pipes
# through get shimmed to their binary modes (`sed --binary`, `grep -U`), which
# is what Linux/macOS/WSL do natively. Black-box: the REAL hook file runs,
# unmodified, at its real installed path.
#
# The shim names the tools the loader uses TODAY. If the loader ever changes
# tools the shim goes inert — it cannot then report a false protection claim,
# only a stale test, and the control below is what keeps a BROKEN shim from
# passing as a working one.
$zeroSha = '0000000000000000000000000000000000000000'
$posixShim = Join-Path $root 'posix-shim'
New-Item -ItemType Directory -Force -Path $posixShim | Out-Null
$emulator = Join-Path $root 'posix-sh-emulation.sh'
[IO.File]::WriteAllText($emulator, (@'
# $1 shim dir, $2 hook path, $3 repo, $4 local sha, $5 remote sha, $6 ref
real_sed=$(command -v sed)
real_grep=$(command -v grep)
printf '#!/bin/sh\nexec "%s" --binary "$@"\n' "$real_sed" > "$1/sed"
printf '#!/bin/sh\nexec "%s" -U "$@"\n' "$real_grep" > "$1/grep"
chmod +x "$1/sed" "$1/grep"
cd "$3" || exit 99
# PATH entries must be POSIX paths: a Windows path keeps its drive-letter
# colon, which PATH itself uses as the separator, so `C:/x/shim` silently
# becomes the two useless entries `C` and `/x/shim` and the shim is never
# reached (measured - the case then passes without testing anything).
shimdir=$(cygpath -u "$1")
PATH="$shimdir:$PATH"
export PATH
# Fail LOUDLY rather than inertly if the shim is not the sed being used.
if [ "$(command -v sed)" != "$shimdir/sed" ] || [ "$(command -v grep)" != "$shimdir/grep" ]; then
    echo "EXIT=98"
    exit 0
fi
printf '%s %s %s %s\n' "$6" "$4" "$6" "$5" | "$2" origin verify >/dev/null 2>&1
echo "EXIT=$?"
'@ -replace "`r`n", "`n"))

function Invoke-HookUnderPosixSh([string] $Ref) {
    $out = & $gitBash ($emulator -replace '\\', '/') ($posixShim -replace '\\', '/') `
        $hookInWork ($work -replace '\\', '/') $fakeSha $zeroSha $Ref 2>&1 | Out-String
    if ($out -match 'EXIT=(\d+)') { return [int]$Matches[1] }
    return -1
}

# The pattern under test must NOT be the last line of the list. Measured: msys
# bash strips a trailing CRLF — not just the LF — when it closes a `$(...)`
# substitution, so the LAST pattern comes out clean even under the shims and a
# single-line CRLF list would pass without the fix and prove nothing. A real
# POSIX shell strips nothing, so on Linux/macOS EVERY pattern keeps its CR;
# `Branches/*` first, `feature/x` after it, reproduces the part that is
# observable here.
#
# CONTROL first, on the LF twin of the very same list: `develop` must pass.
# That proves the emulated sh really reads the configured file — a shim that
# broke the pipeline would leave the patterns empty, fall back to the built-in
# list, reject `develop`, and this case would go red instead of quietly
# "passing" without testing anything.
Write-ProtectedList $protectedFile @('Branches/*', 'feature/x')
$posixControlExit = Invoke-HookUnderPosixSh 'refs/heads/develop'
# TARGET: same list, CRLF this time — the pattern must still match.
Write-ProtectedListCrlf $protectedFile @('Branches/*', 'feature/x')
$posixCrlfExit = Invoke-HookUnderPosixSh 'refs/heads/Branches/5.37'
Assert-True (($posixControlExit -eq 0) -and ($posixCrlfExit -ne 0)) "pod ne-msys sh (sed --binary, grep -U) CRLF seznam chrání dál (kontrola: LF seznam se čte, develop projde = $posixControlExit; CRLF: Branches/5.37 zamítnuta = $posixCrlfExit)"

# 16i. STDIN-THEFT REGRESSION. git feeds the hook one line per ref, and the
# configuration is loaded BEFORE the loop for exactly this reason: a `while
# read` (or anything else consuming stdin) inside the loop swallows the
# remaining refs and the hook stops checking — with exit code 0. Every other
# case in this suite pushes a single ref, so moving the load inside the loop
# would leave the whole suite green. Two ref lines, the innocuous one FIRST:
# if only the first line is ever processed, the assertion fails.
Remove-Item -LiteralPath $protectedFile -Force
$multiRefScript = 'cd "$1" && printf "refs/heads/feature/x %s %s %s\nrefs/heads/develop %s %s %s\n" ' +
    '"$2" "refs/heads/feature/x" "$3" "$2" "refs/heads/develop" "$3" | "$4" origin verify'
$out = & $gitBash -c $multiRefScript _ ($work -replace '\\', '/') $fakeSha $zeroSha $hookInWork 2>&1 | Out-String
$multiRefCode = $LASTEXITCODE
Assert-True (($multiRefCode -ne 0) -and ($out -match "'develop'")) 'druhý ref na stdin je stále kontrolován (konfigurace se čte před smyčkou, nic ve smyčce nekrade stdin)'

# 16j. REPLACE, not union. The configured list IS the list; the built-in one is
# a fallback for "no usable file", not a floor that is always added. Pinned
# with a built-in name the configuration omits: with only `Branches/*`
# configured, `main` is pushable.
Write-ProtectedList $protectedFile @('Branches/*')
$r = Invoke-GitTry $work @('push', 'origin', 'HEAD:refs/heads/main')
Assert-Eq $r.Code 0 'konfigurovaný seznam vestavěný NAHRAZUJE (main není chráněný, když ho seznam neobsahuje), nesjednocuje se s ním'

# ---------------------------------------------------------------------------
# 17. THE GENERATOR, the other half of case 16. Case 16 writes the list BY
# HAND; here nothing is written by hand — install-git-hooks.ps1 must
# materialize memory-bank/ums-repo.json's `protectedBranches` into
# <git-common-dir>/ums-protected-branches itself, because pre-push is POSIX sh
# with no JSON parser. Without this step the configuration reaches the hook
# nowhere and the hook only ever sees its built-in fallback.
#
# Own fixture: the primary one above has no configuration file and a list that
# later cases keep rewriting, so a generated file there could not be told from
# a hand-written one.
#
# `develop` is configured alongside the extra pattern on purpose. The
# installer's own proof runs the hook, which resolves the list relative to the
# working directory, so the fixture's list is what the reject run reads — a
# configuration that dropped `develop` would fail that run and the exit code
# asserted below would be about the wrong thing.
#
# The extra pattern is `Maint/*`, deliberately NOT `Branches/*`: this fork's own
# memory-bank/ums-repo.json contains `Branches/*`, so if the installer's proof
# ever read the WRONG repository's list again (it resolves the list from the
# current directory, and the suite runs from this fork's root), a stale
# `Branches/*` would give the right answer for the wrong reason and the
# regression would pass unnoticed. `Maint/*` cannot appear in this fork's list.
# ---------------------------------------------------------------------------

# work clone + bare origin with `develop` published - the minimum needed to
# prove a REAL push is refused. Cases 17 and 18 need three independent ones.
function New-PushFixture([string] $Label) {
    $r = Join-Path ([IO.Path]::GetTempPath()) ("$Label-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $o = Join-Path $r 'origin.git'
    $w = Join-Path $r 'work'
    New-Item -ItemType Directory -Force -Path $o, $w | Out-Null
    & git init --bare -q -b develop $o | Out-Null
    & git init -q -b develop $w | Out-Null
    Invoke-GitOk $w @('remote', 'add', 'origin', $o) | Out-Null
    'base' | Out-File -FilePath (Join-Path $w 'f.txt') -Encoding utf8
    Invoke-GitOk $w @('add', '-A') | Out-Null
    Invoke-GitOk $w @('commit', '-m', 'base') | Out-Null
    Invoke-GitOk $w @('push', '-u', 'origin', 'develop') | Out-Null
    return @{ Root = $r; Origin = $o; Work = $w }
}

function Write-RepoConfig([string] $RepoDir, [string] $Json) {
    New-Item -ItemType Directory -Force -Path (Join-Path $RepoDir 'memory-bank') | Out-Null
    Set-Content -LiteralPath (Join-Path $RepoDir 'memory-bank\ums-repo.json') -Value $Json
}

$fx8 = New-PushFixture 'mbgen'
$work8 = $fx8.Work
Write-RepoConfig $work8 @'
{
  "protectedBranches": ["develop", "Maint/*"]
}
'@

$res = Invoke-Installer $work8 $null
$listFile8 = Join-Path (Resolve-GitCommonDir $work8) 'ums-protected-branches'
Assert-True (Test-Path -LiteralPath $listFile8) 'generátor: instalátor vytvořil <git-common-dir>/ums-protected-branches'
$generated = if (Test-Path -LiteralPath $listFile8) { [IO.File]::ReadAllText($listFile8) } else { '' }
Assert-Match $generated '(?m)^Maint/\*\s*$' 'generátor: seznam obsahuje vzor Maint/* z konfigurace'
Assert-True (-not $generated.Contains("`r")) 'generátor: seznam je zapsaný s LF, bez CR (ne-msys sh nic nekonvertuje)'
Assert-Eq $res.Code 0 'generátor: instalátor končí kódem 0 (seznam zapsán, hook ověřen)'
# The third proof run must actually have happened AND must have read THIS
# fixture's list: `Maint/*` exists nowhere else, so a proof run reading another
# repository's list cannot produce this line.
Assert-Match $res.Flat "generated protected-branch list is consulted \(pattern 'Maint/\*'\)" 'generátor: self-test dokazuje, že hook čte seznam TOHOTO repozitáře (vzor Maint/* nikde jinde není)'

# ... and the branch the built-in list cannot cover is rejected by a REAL push,
# with no file written by this suite. This is the assertion that stands on its
# own: no synthetic stdin, no cwd of the installer's choosing.
Invoke-GitOk $work8 @('checkout', '-q', '-b', 'Maint/5.37') | Out-Null
'maint' | Out-File -FilePath (Join-Path $work8 'h.txt') -Encoding utf8
Invoke-GitOk $work8 @('add', '-A') | Out-Null
Invoke-GitOk $work8 @('commit', '-m', 'maint') | Out-Null
$r = Invoke-GitTry $work8 @('push', 'origin', 'HEAD:refs/heads/Maint/5.37')
Assert-True (($r.Code -ne 0) -and ($r.Out -match 'UMS') -and ($null -eq (Get-Sha $fx8.Origin 'refs/heads/Maint/5.37'))) 'generátor: push do Maint/5.37 je po instalaci zamítnutý (vzor se dostal ke hooku bez ručního zápisu)'

# The installer's third proof run stands on ONE property of the hook, so that
# property is pinned here instead of being left to a comment: a BRANCH-CREATING
# push (zero remote sha) is judged by the protected-branch rule ALONE. With a
# fabricated remote sha the hook reaches `git merge-base --is-ancestor`, which
# cannot resolve it and rejects EVERY branch name with a `UMS: ` message — which
# is exactly what made an earlier version of that run decorative: it "proved"
# the list was consulted for names nothing protected. Both spellings are
# measured, so the discriminator cannot quietly stop discriminating.
$hook8 = (Resolve-GitPath $work8 'hooks/pre-push') -replace '\\', '/'
function Invoke-SyntheticPush([string] $Ref, [string] $RemoteSha) {
    $out = & $gitBash -c 'cd "$1" && printf "%s %s %s %s\n" "$2" "$3" "$2" "$4" | "$5" origin verify' _ `
        ($work8 -replace '\\', '/') $Ref $fakeSha $RemoteSha $hook8 2>&1 | Out-String
    return @{ Out = $out; Code = $LASTEXITCODE }
}
$unprotZero = Invoke-SyntheticPush 'refs/heads/zzz-not-protected' $zeroSha
$maintZero = Invoke-SyntheticPush 'refs/heads/Maint/x' $zeroSha
$unprotFake = Invoke-SyntheticPush 'refs/heads/zzz-not-protected' $fakeSha
Assert-True (($unprotZero.Code -eq 0) -and ($maintZero.Code -ne 0) -and ($maintZero.Out -match 'HEAD:Maint/x')) "tvar 3. důkazního běhu ROZLIŠUJE: se nulovou remote sha projde nechráněné jméno (exit $($unprotZero.Code)) a konfigurovaný vzor je zamítnut jako sdílená větev (exit $($maintZero.Code))"
Assert-True ($unprotFake.Code -ne 0) "kontrola téhož: s vymyšlenou remote sha hook zamítne i nechráněné jméno (exit $($unprotFake.Code), non-fast-forward) — proto ten tvar důkaz použít NESMÍ"

Remove-Item -Recurse -Force $fx8.Root

# ---------------------------------------------------------------------------
# 18. EXIT CODE 4 - the configuration path failed, but protection must land at
# the BUILT-IN level, never at "no hook". Both triggers are covered, because
# both used to degrade the wrong way: an unwritable list, and a missing
# configuration loader (which THREW before any hook was installed - and
# sync-with-monorepo.ps1 downgrades a non-zero exit to a warning, so an
# incomplete layer copy left `develop` completely unprotected, strictly less
# than the hook's own fallback would have given).
# ---------------------------------------------------------------------------

# 18a. Unwritable list: a DIRECTORY occupies the target path, so WriteAllText
# fails while everything else about the run is fine.
$fx9 = New-PushFixture 'mbexit4w'
New-Item -ItemType Directory -Force -Path (Join-Path (Resolve-GitCommonDir $fx9.Work) 'ums-protected-branches') | Out-Null
Write-RepoConfig $fx9.Work @'
{
  "protectedBranches": ["develop", "Maint/*"]
}
'@
$res = Invoke-Installer $fx9.Work $null
Assert-Eq $res.Code 4 'exit 4 (zápis): nezapsatelný seznam končí kódem 4, ne nulou ani 1'
Assert-Match $res.Flat 'could not write the protected-branch list' 'exit 4 (zápis): instalátor hlásí selhání zápisu nahlas'
Assert-Match $res.Flat 'could not be refreshed \(the list could not be written\)' 'exit 4 (zápis): souhrn pojmenuje příčinu'
Assert-Match $res.Flat 'no usable list on disk, so pre-push falls back to its built-in patterns' 'exit 4 (zápis): bez použitelného seznamu na disku je tvrzení o vestavěných vzorech pravdivé'
Assert-True (Test-Path -LiteralPath (Resolve-GitPath $fx9.Work 'hooks/pre-push')) 'exit 4 (zápis): hook je i tak nainstalovaný'
Add-Content -Path (Join-Path $fx9.Work 'f.txt') -Value 'change'
Invoke-GitOk $fx9.Work @('commit', '-am', 'develop change') | Out-Null
$developBefore9 = Get-Sha $fx9.Origin 'refs/heads/develop'
$r = Invoke-GitTry $fx9.Work @('push', 'origin', 'develop')
Assert-True (($r.Code -ne 0) -and ((Get-Sha $fx9.Origin 'refs/heads/develop') -eq $developBefore9)) 'exit 4 (zápis): develop je chráněný vestavěným seznamem (degradace vede k méně ochrany, ne k žádné)'
Remove-Item -Recurse -Force $fx9.Root

# 18b. Missing loader. The installer is run from a COPY of the hooks directory
# with no sibling skills\shared\scripts, so BOTH resolution paths (-SourceDir
# and $PSScriptRoot) miss - which is exactly the shape a partially-deployed
# layer takes.
$fx10 = New-PushFixture 'mbexit4l'
$hooksCopy = Join-Path $fx10.Root 'hooks-copy'
New-Item -ItemType Directory -Force -Path $hooksCopy | Out-Null
Copy-Item -Force (Join-Path $PSScriptRoot '..\install-git-hooks.ps1') $hooksCopy
Copy-Item -Force (Join-Path $PSScriptRoot '..\pre-push') $hooksCopy
Write-RepoConfig $fx10.Work @'
{
  "protectedBranches": ["develop", "Maint/*"]
}
'@
$res = Invoke-InstallerScript (Join-Path $hooksCopy 'install-git-hooks.ps1') $fx10.Work $hooksCopy
Assert-Eq $res.Code 4 'exit 4 (loader): chybějící Get-UmsRepoConfig.ps1 končí kódem 4, ne výjimkou'
Assert-Match $res.Flat 'Get-UmsRepoConfig.ps1 not found' 'exit 4 (loader): instalátor pojmenuje chybějící loader nahlas'
Assert-Match $res.Flat 'degrading to NO hook would not be' 'exit 4 (loader): instalátor říká, proč hook přesto instaluje'
Assert-Match $res.Flat 'could not be refreshed \(the configuration loader' 'exit 4 (loader): souhrn pojmenuje příčinu'
Assert-True (-not (Test-Path -LiteralPath (Join-Path (Resolve-GitCommonDir $fx10.Work) 'ums-protected-branches'))) 'exit 4 (loader): žádný seznam se nevygeneroval (konfigurace se nefabrikuje)'
# THE POINT of the whole case: the hook is installed and really guards.
Assert-True (Test-Path -LiteralPath (Resolve-GitPath $fx10.Work 'hooks/pre-push')) 'exit 4 (loader): hook JE nainstalovaný'
Add-Content -Path (Join-Path $fx10.Work 'f.txt') -Value 'change'
Invoke-GitOk $fx10.Work @('commit', '-am', 'develop change') | Out-Null
$developBefore10 = Get-Sha $fx10.Origin 'refs/heads/develop'
$r = Invoke-GitTry $fx10.Work @('push', 'origin', 'develop')
Assert-True (($r.Code -ne 0) -and ((Get-Sha $fx10.Origin 'refs/heads/develop') -eq $developBefore10)) 'exit 4 (loader): reálný push na develop je zamítnutý (vestavěný seznam platí, hook není mrtvý)'
# Honest scope of exit 4: the CONFIGURED extra pattern is NOT enforced. Asserted
# so nobody reads "exit 4" as "everything still protected".
Invoke-GitOk $fx10.Work @('checkout', '-q', '-b', 'Maint/5.37') | Out-Null
'maint' | Out-File -FilePath (Join-Path $fx10.Work 'h.txt') -Encoding utf8
Invoke-GitOk $fx10.Work @('add', '-A') | Out-Null
Invoke-GitOk $fx10.Work @('commit', '-m', 'maint') | Out-Null
$r = Invoke-GitTry $fx10.Work @('push', 'origin', 'HEAD:refs/heads/Maint/5.37')
Assert-Eq $r.Code 0 'exit 4 (loader): konfigurovaný vzor Maint/* vynucený NENÍ - přesně to nenulový kód říká'
Remove-Item -Recurse -Force $fx10.Root

# ---------------------------------------------------------------------------
# 19. STALE LIST on a degraded run. The exit-4 summary NAMES the protection in
# force, so it must not assert the built-in set when a list from an earlier run
# is still on disk: that list is non-empty, so the hook's built-in fallback
# never fires. Measured before the fix: a repo installed with `develop` +
# `Maint/*`, re-run without a loader, reported develop/main/master/release/* as
# enforced while a push to `main` went straight through.
#
# The fix must NOT be "delete the stale list" - with a configuration richer than
# the built-in set that would REMOVE protection. It must be to read the file
# back (no loader needed for a text file) and report what is genuinely in force.
# ---------------------------------------------------------------------------
$fx11 = New-PushFixture 'mbstale'
Write-RepoConfig $fx11.Work @'
{
  "protectedBranches": ["develop", "Maint/*"]
}
'@
$res = Invoke-Installer $fx11.Work $null
Assert-Eq $res.Code 0 'zastaralý seznam: první instalace (s loaderem) proběhne normálně'

# Second run from a hooks copy with no loader: the list stays as the first run
# left it, and the summary must say so instead of claiming the built-in set.
$hooksCopy11 = Join-Path $fx11.Root 'hooks-copy'
New-Item -ItemType Directory -Force -Path $hooksCopy11 | Out-Null
Copy-Item -Force (Join-Path $PSScriptRoot '..\install-git-hooks.ps1') $hooksCopy11
Copy-Item -Force (Join-Path $PSScriptRoot '..\pre-push') $hooksCopy11
$res = Invoke-InstallerScript (Join-Path $hooksCopy11 'install-git-hooks.ps1') $fx11.Work $hooksCopy11
Assert-Eq $res.Code 4 'zastaralý seznam: běh bez loaderu končí kódem 4'
Assert-Match $res.Flat 'patterns in force: develop, Maint/\*' 'zastaralý seznam: souhrn vypíše vzory, které SKUTEČNĚ platí (přečtené z disku)'
Assert-Match $res.Flat 'may be STALE' 'zastaralý seznam: souhrn říká, že seznam nebyl obnoven a může být zastaralý'
# The false claim that motivated this case must be gone: `main` is NOT in force
# here, so the summary must not say it is.
Assert-NotMatch $res.Flat 'built-in patterns \(develop, main, master, release/\*\)' 'zastaralý seznam: výstup vestavěné vzory vůbec nejmenuje (main mezi platnými není, tvrdit to by byla lež)'
# ... and the reality the claim would have misrepresented, by real push: `main`
# passes (the stale list does not contain it), `Maint/5.37` is still rejected.
Invoke-GitOk $fx11.Work @('checkout', '-q', '-b', 'Maint/5.37') | Out-Null
'maint' | Out-File -FilePath (Join-Path $fx11.Work 'h.txt') -Encoding utf8
Invoke-GitOk $fx11.Work @('add', '-A') | Out-Null
Invoke-GitOk $fx11.Work @('commit', '-m', 'maint') | Out-Null
$rMain = Invoke-GitTry $fx11.Work @('push', 'origin', 'HEAD:refs/heads/main')
$rMaint = Invoke-GitTry $fx11.Work @('push', 'origin', 'HEAD:refs/heads/Maint/5.37')
Assert-True (($rMain.Code -eq 0) -and ($rMaint.Code -ne 0)) "zastaralý seznam: realita odpovídá hlášení - main projde (main=$($rMain.Code)), Maint/5.37 je zamítnuta (maint=$($rMaint.Code))"
Remove-Item -Recurse -Force $fx11.Root

# ---------------------------------------------------------------------------
# 20. The proof's own ACCEPT names are configuration-sensitive, and a repository
# is free to protect the patterns they fall under.
# ---------------------------------------------------------------------------

# 20a. A configuration matching the third run's CONTROL name silently removed
# the only guard against that run going decorative again. The install must still
# succeed (the consultation claim is carried by the shared-branch message), but
# the lost control must be REPORTED, not invisible.
$fx12 = New-PushFixture 'mbctlskip'
Write-RepoConfig $fx12.Work @'
{
  "protectedBranches": ["develop", "ums-*"]
}
'@
$res = Invoke-Installer $fx12.Work $null
Assert-Eq $res.Code 0 'kontrola 3. běhu: konfigurace pokrývající jméno kontroly instalaci neshodí'
Assert-Match $res.Flat "generated protected-branch list is consulted \(pattern 'ums-\*'\)" 'kontrola 3. běhu: samotný důkaz konzultace platí dál'
Assert-Match $res.Flat "covers the control name 'ums-install-verify-unprotected' too" 'kontrola 3. běhu: přeskočení kontroly je nahlas ohlášené, ne neviditelné'
Assert-NotMatch $res.Flat 'control for that run: the same synthetic shape' 'kontrola 3. běhu: nehlásí se kontrola, která neproběhla'
Remove-Item -Recurse -Force $fx12.Root

# 20b. `feature/*` is an ordinary thing to protect, and it covers the DEFAULT
# accept name. Before the pre-check the hook rejected it correctly, the proof
# read that as a broken hook and the installer exited 1 — refusing to install a
# working guard. A substitute accept name must be used instead.
$fx13 = New-PushFixture 'mbacceptcfg'
Write-RepoConfig $fx13.Work @'
{
  "protectedBranches": ["develop", "feature/*"]
}
'@
$res = Invoke-Installer $fx13.Work $null
Assert-Eq $res.Code 0 'accept vzor: konfigurace chránící feature/* instalaci neshodí (dřív exit 1)'
Assert-Match $res.Flat 'installed \+ verified live' 'accept vzor: hook je ověřený jako živý'
Assert-NotMatch $res.Flat "accepts a synthetic ticket-branch push to 'feature/" 'accept vzor: nepoužije se jméno, které konfigurace chrání'
Assert-Match $res.Flat "accepts a synthetic ticket-branch push to '(ums-install-verify-accept|zzz-install-verify-accept)'" 'accept vzor: použije se náhradní jméno, které konfigurace nechrání'
Remove-Item -Recurse -Force $fx13.Root

# 20c. A configuration protecting `*` covers every candidate, so the accept half
# cannot run at all - it must be skipped and reported, not turned into a failure.
$fx14 = New-PushFixture 'mbacceptall'
Write-RepoConfig $fx14.Work @'
{
  "protectedBranches": ["*"]
}
'@
$res = Invoke-Installer $fx14.Work $null
Assert-Eq $res.Code 0 'accept vzor: konfigurace chránící * instalaci neshodí'
Assert-Match $res.Flat 'ACCEPT half of the proof was skipped' 'accept vzor: přeskočení accept poloviny důkazu je ohlášené'
Remove-Item -Recurse -Force $fx14.Root

# ---------------------------------------------------------------------------
# 21. Three ways the self-test's own guards used to turn an ENFORCING hook into
# "the guarantee is absent". All three are about the same rule from the other
# side: the installer must not report absent protection it did not measure.
# ---------------------------------------------------------------------------

# 21a. An unterminated character class is a legal POSIX `case` glob but not a
# legal PowerShell wildcard, and `-like` THROWS on it. Unhandled, that throw
# skipped the summary entirely and exited 1 - "proof FAILED, treat the guarantee
# as absent" - for a hook that was installed and enforcing.
$fx15 = New-PushFixture 'mbbadglob'
Write-RepoConfig $fx15.Work @'
{
  "protectedBranches": ["develop", "Maint/[0-9"]
}
'@
$res = Invoke-Installer $fx15.Work $null
Assert-Match $res.Flat 'summary: pre-push' 'nevalidní glob: běh dojde až k vypsanému souhrnu (dřív spadl bez souhrnu)'
Assert-NotMatch $res.Flat 'wildcard character pattern is not valid' 'nevalidní glob: instalátor nespadne na PowerShell výjimce z -like'
Assert-Eq $res.Code 0 'nevalidní glob: hook je nainstalovaný a ověřený, ne hlášený jako chybějící záruka'
# Honest consequence of the conservative direction: a pattern that cannot be
# parsed counts as covering every candidate name, so the accept half is skipped
# - reported, never silent, and never a failed install.
Assert-Match $res.Flat 'ACCEPT half of the proof was skipped' 'nevalidní glob: přeskočení accept poloviny je ohlášené'
# ... and the REASON must name the unparseable pattern, not claim coverage the
# configuration does not give. POSIX `case` reads `Maint/[0-9` as a literal, so
# the configuration covers no accept-case name at all; "the configuration covers
# them" was a false reason for a true skip.
Assert-Match $res.Flat "the configured pattern 'Maint/\[0-9' is not a parseable wildcard" 'nevalidní glob: důvod přeskočení jmenuje neparsovatelný vzor'
Assert-NotMatch $res.Flat 'is covered by a configured protected pattern' 'nevalidní glob: důvod netvrdí, že vzory to jméno pokrývají (nepokrývají)'
$developBefore15 = Get-Sha $fx15.Origin 'refs/heads/develop'
Add-Content -Path (Join-Path $fx15.Work 'f.txt') -Value 'change'
Invoke-GitOk $fx15.Work @('commit', '-am', 'develop change') | Out-Null
$r = Invoke-GitTry $fx15.Work @('push', 'origin', 'develop')
Assert-True (($r.Code -ne 0) -and ((Get-Sha $fx15.Origin 'refs/heads/develop') -eq $developBefore15)) 'nevalidní glob: hook skutečně hlídá (develop zamítnut), takže exit 0 nelže'
Remove-Item -Recurse -Force $fx15.Root

# 21b. Degraded run whose STALE list protects the accept name. The self-test was
# fed the (empty) configuration instead of the list in force, so the hook's
# correct rejection of `feature/ums-install-verify` read as a broken hook: exit 1
# plus "guarantee as absent" - and because that is not exit 4, the report naming
# the patterns actually in force was suppressed, so the run named NO protection.
$fx16 = New-PushFixture 'mbstaleaccept'
Write-RepoConfig $fx16.Work @'
{
  "protectedBranches": ["develop", "feature/*"]
}
'@
$res = Invoke-Installer $fx16.Work $null
Assert-Eq $res.Code 0 'zastaralý accept: první instalace (s loaderem) proběhne normálně'
$hooksCopy16 = Join-Path $fx16.Root 'hooks-copy'
New-Item -ItemType Directory -Force -Path $hooksCopy16 | Out-Null
Copy-Item -Force (Join-Path $PSScriptRoot '..\install-git-hooks.ps1') $hooksCopy16
Copy-Item -Force (Join-Path $PSScriptRoot '..\pre-push') $hooksCopy16
$res = Invoke-InstallerScript (Join-Path $hooksCopy16 'install-git-hooks.ps1') $fx16.Work $hooksCopy16
Assert-NotMatch $res.Flat 'PROOF FAILED' 'zastaralý accept: hook chránící feature/* NENÍ hlášen jako selhaný důkaz'
Assert-Eq $res.Code 4 'zastaralý accept: běh končí kódem 4 (seznam nešel obnovit), ne kódem 1'
Assert-Match $res.Flat 'patterns in force: develop, feature/\*' 'zastaralý accept: běh pojmenuje vzory, které skutečně platí (dřív nepojmenoval žádné)'
Remove-Item -Recurse -Force $fx16.Root

# 21c. The write-failure warning named the built-in patterns while the summary
# five lines below reported a different, real list - and a reader stops at the red
# WARNING. Read-only list file: the write fails, but the file stays READABLE, so
# a usable list is genuinely in force (the directory trick in 18a removes it).
$fx17 = New-PushFixture 'mbrolist'
Write-RepoConfig $fx17.Work @'
{
  "protectedBranches": ["develop", "Maint/*"]
}
'@
$res = Invoke-Installer $fx17.Work $null
Assert-Eq $res.Code 0 'read-only seznam: první instalace proběhne normálně'
$listFile17 = Join-Path (Resolve-GitCommonDir $fx17.Work) 'ums-protected-branches'
Set-ItemProperty -LiteralPath $listFile17 -Name IsReadOnly -Value $true
$res = Invoke-Installer $fx17.Work $null
Assert-Eq $res.Code 4 'read-only seznam: nezapsatelný seznam končí kódem 4'
Assert-Match $res.Flat 'patterns in force: develop, Maint/\*' 'read-only seznam: souhrn pojmenuje skutečně platné vzory'
# THE finding: nothing in the run may name main/master/release as protected while
# the list in force does not contain them.
Assert-NotMatch $res.Flat 'main, master, release/\*' 'read-only seznam: ani varování, ani souhrn nejmenují vestavěné vzory, když platí jiný seznam'
Set-ItemProperty -LiteralPath $listFile17 -Name IsReadOnly -Value $false
Remove-Item -Recurse -Force $fx17.Root

# 21d. The shape where an unparseable pattern silently removed the THIRD run's
# control. With `["Branches/*", "Maint/[0-9"]` the third run itself fires (its
# sample comes from `Branches/*`; bracketed patterns are excluded from sampling),
# but the control name could not be tested against `Maint/[0-9` - `-like` throws -
# so it was conservatively treated as covered and the control was skipped. The
# skip was reported with the reason "the configuration covers the control name",
# which is FALSE: POSIX `case` reads that pattern as a literal. The run then
# printed "the generated protected-branch list is consulted" and
# "[installed + verified live]" with exit 0, having lost the only guard against a
# decorative third run behind a wrong explanation.
$fx18 = New-PushFixture 'mbbadglobctl'
Write-RepoConfig $fx18.Work @'
{
  "protectedBranches": ["Branches/*", "Maint/[0-9"]
}
'@
$res = Invoke-Installer $fx18.Work $null
Assert-Eq $res.Code 0 'kontrola 3. běhu: neparsovatelný vzor vedle použitelného instalaci neshodí'
Assert-Match $res.Flat "generated protected-branch list is consulted \(pattern 'Branches/\*'\)" 'kontrola 3. běhu: třetí běh proběhl (vzorek se bere z Branches/*)'
Assert-Match $res.Flat "the configured pattern 'Maint/\[0-9' is not a parseable wildcard" 'kontrola 3. běhu: důvod přeskočení kontroly jmenuje neparsovatelný vzor'
Assert-NotMatch $res.Flat 'the configuration covers the control name' 'kontrola 3. běhu: důvod už netvrdí, že konfigurace kontrolní jméno pokrývá'
Assert-Match $res.Flat 'the only run that would notice if the run above stopped discriminating' 'kontrola 3. běhu: hlásí se i důsledek — chybí jediná pojistka proti dekorativnímu třetímu běhu'
Remove-Item -Recurse -Force $fx18.Root

# ---------------------------------------------------------------------------
# 22. Řetězení cizího hooku. Kanárek zapisuje počet přijatých řádků stdinu do
# souboru: kdyby ho hook zavolal bez přehrání stdinu, napíše 0 a LFS by tiše
# přestalo posílat objekty - selhání, které vypadá jako funkční stav.
# ---------------------------------------------------------------------------
$chainDir = Join-Path $work '.git/hooks'
$canaryOut = (Join-Path $root 'canary.txt') -replace '\\', '/'
$chainPath = Join-Path $chainDir 'pre-push.ums-chained'
Set-Content -LiteralPath $chainPath -Encoding ascii -Value @"
#!/bin/sh
wc -l < /dev/stdin > "$canaryOut"
echo "args=$*" >> "$canaryOut"
exit 0
"@
& $gitBash -c 'chmod +x "$1"' _ ($chainPath -replace '\\', '/') | Out-Null

# feature/x's local pointer was left diverged from origin by the rejected
# force-push case above (case 4) - resync to origin's tip first, so this
# case tests chaining, not an unrelated non-fast-forward from an earlier case.
Invoke-GitOk $work @('fetch', 'origin', 'feature/x') | Out-Null
Invoke-GitOk $work @('checkout', '-B', 'feature/x', 'origin/feature/x') | Out-Null
Add-Content -Path (Join-Path $work 'g.txt') -Value 'chain test'
Invoke-GitOk $work @('commit', '-am', 'chain test') | Out-Null
$r = Invoke-GitTry $work @('push', 'origin', 'feature/x')
Assert-Eq $r.Code 0 'řetězení: povolený push projde'
Assert-True (Test-Path $canaryOut) 'řetězení: cizí hook byl skutečně zavolán'
$canary = @(Get-Content -LiteralPath $canaryOut)
Assert-Eq $canary[0].Trim() '1' 'řetězení: cizí hook dostal přehraný stdin (1 ref)'
Assert-Match $canary[1] 'args=origin' 'řetězení: cizí hook dostal i argumenty gitu'

# ---------------------------------------------------------------------------
# 23. FAIL-CLOSED REGRESSION. The stdin buffer (`cat > "$stdin_buf"`) has no
# error handling of its own further up in the hook; without a guard, an
# unwritable/unresolvable TMPDIR would make `cat` fail, the main loop would
# then read from a MISSING file, process zero refs, leave `reject` at 0 and
# fall straight through to an ALLOWED push - this is the layer's enforcement
# boundary, so a plumbing failure here must reject, not silently pass every
# policy check. Simulated by pointing TMPDIR at a directory that does not
# exist (and is never created by anything in this test): `cat` cannot open
# a file inside a non-existent parent directory, which is a portable way to
# force the failure without relying on filesystem permission bits (those do
# not behave uniformly under msys/Windows).
# ---------------------------------------------------------------------------
$badTmpDir = Join-Path $root 'no-such-tmp'
Invoke-GitOk $work @('checkout', 'develop') | Out-Null
$developBeforeBadTmp = Get-Sha $origin 'refs/heads/develop'
Add-Content -Path (Join-Path $work 'f.txt') -Value 'bad tmpdir test'
Invoke-GitOk $work @('commit', '-am', 'bad tmpdir test') | Out-Null
$prevTmpDir = $env:TMPDIR
$env:TMPDIR = $badTmpDir
try {
    $r = Invoke-GitTry $work @('push', 'origin', 'develop')
}
finally {
    if ($null -eq $prevTmpDir) { Remove-Item Env:TMPDIR -ErrorAction SilentlyContinue }
    else { $env:TMPDIR = $prevTmpDir }
}
Assert-True ($r.Code -ne 0) 'fail-closed: push selže, i když stdin buffer nejde vytvořit (nezapsatelné TMPDIR)'
Assert-Match $r.Out 'UMS' 'fail-closed: zamítnutí nese UMS vysvětlení, ne jen holou chybu shellu'
Assert-Eq (Get-Sha $origin 'refs/heads/develop') $developBeforeBadTmp 'fail-closed: remote develop se nepohnulo (žádná kontrola neproběhla, ale push je přesto zamítnutý)'
Assert-True (-not (Test-Path $badTmpDir)) 'fail-closed: adresář pro buffer se sám nevytvořil (skutečně nezapsatelný scénář)'

Remove-Item -Recurse -Force $root

# ---------------------------------------------------------------------------
# 24. Cizí hook (typicky Git LFS) se neodmítá, ale odsouvá a řetězí. Do sdíleného
# adresáře hooků se ale řetězit NESMÍ - přejmenování by tiše přesměrovalo
# každý repozitář, který tu cestu používá.
# ---------------------------------------------------------------------------
$rChain = Join-Path ([IO.Path]::GetTempPath()) ("mbchain-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
& git init -q -b develop $rChain | Out-Null
$foreign = Join-Path $rChain '.git/hooks/pre-push'
New-Item -ItemType Directory -Force -Path (Split-Path $foreign) | Out-Null
Set-Content -LiteralPath $foreign -Encoding ascii -Value "#!/bin/sh`nexit 0`n"
$res = Invoke-Installer $rChain $null
Assert-Eq $res.Code 0 'cizí hook: instalace uspěje řetězením, ne exitem 2'
Assert-True (Test-Path (Join-Path $rChain '.git/hooks/pre-push.ums-chained')) 'cizí hook: odsunut na .ums-chained'
Assert-Match $res.Flat 'chained' 'cizí hook: instalátor řetězení pojmenuje'
$ours = Get-Content -LiteralPath $foreign -TotalCount 5
Assert-Match ($ours -join "`n") 'UMS pre-push guard' 'cizí hook: na jeho místě je náš hook'

# Opakovaný běh nesmí přepsat už odsunutý cizí hook vlastním hookem.
$chainedBefore = Get-Content -LiteralPath (Join-Path $rChain '.git/hooks/pre-push.ums-chained') -Raw
$res = Invoke-Installer $rChain $null
$chainedAfter = Get-Content -LiteralPath (Join-Path $rChain '.git/hooks/pre-push.ums-chained') -Raw
Assert-Eq $chainedAfter $chainedBefore 'cizí hook: opakovaná instalace řetězený soubor nemění'
Assert-NotMatch $chainedAfter 'UMS pre-push guard' 'cizí hook: náš hook se nikdy nezřetězí sám se sebou'

# Minor 6 (review, kolo 1): reálný scénář - `git lfs install --local` spuštěné
# znovu obnoví cizí pre-push vedle už existujícího .ums-chained z dřívějšího
# běhu instalátoru. Odmítací větev ":614-618" (chained soubor už existuje) na
# to dosud nesahal - tenhle případ ho poprvé cvičí.
Remove-Item -LiteralPath (Join-Path $rChain '.git/hooks/pre-push') -Force
Set-Content -LiteralPath $foreign -Encoding ascii -Value "#!/bin/sh`nexit 0`n"
$res = Invoke-Installer $rChain $null
Assert-Eq $res.Code 2 'cizí hook obnovený vedle existujícího .ums-chained: instalace odmítnuta, exit 2'
Assert-Match $res.Flat 'already present' 'cizí hook obnovený vedle existujícího .ums-chained: instalátor pojmenuje důvod (chained soubor už existuje)'
$chainedStillAfter = Get-Content -LiteralPath (Join-Path $rChain '.git/hooks/pre-push.ums-chained') -Raw
Assert-Eq $chainedStillAfter $chainedBefore 'cizí hook obnovený vedle existujícího .ums-chained: existující .ums-chained zůstal nedotčený'
$foreignStill = Get-Content -LiteralPath $foreign -Raw
Assert-NotMatch $foreignStill 'UMS pre-push guard' 'cizí hook obnovený vedle existujícího .ums-chained: nově obnovený cizí hook zůstal na místě, nepřepsán'

Remove-Item -Recurse -Force $rChain

# ---------------------------------------------------------------------------
# Important 1 (review, kolo 1): Ruling R16b tvrdí, že instalátor musí odsunutý
# cizí hook učinit spustitelným. Fixtura je vlastní kanárek (jako blok 22),
# ale ZÁMĚRNĚ BEZ chmod +x před instalací - jestli po instalaci a skutečném
# pushi kanárek nezapíše soubor, `chmod` v Move-ForeignHook je rozbitý nebo se
# vůbec nezavolal, a run_chained (`[ -x "$chained" ] || return 0`) by cizí
# hook tiše přeskočil. Tohle testuje INSTALÁTOR, ne vlastní setup testu.
# ---------------------------------------------------------------------------
$rxOrigin = Join-Path ([IO.Path]::GetTempPath()) ("mbexecbito-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$rxWork = Join-Path ([IO.Path]::GetTempPath()) ("mbexecbitw-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $rxOrigin, $rxWork | Out-Null
& git init --bare -q -b develop $rxOrigin | Out-Null
& git init -q -b develop $rxWork | Out-Null
Invoke-GitOk $rxWork @('remote', 'add', 'origin', $rxOrigin) | Out-Null
'base' | Out-File -FilePath (Join-Path $rxWork 'f.txt') -Encoding utf8
Invoke-GitOk $rxWork @('add', '-A') | Out-Null
Invoke-GitOk $rxWork @('commit', '-m', 'base') | Out-Null
Invoke-GitOk $rxWork @('push', '-u', 'origin', 'develop') | Out-Null
Invoke-GitOk $rxWork @('checkout', '-b', 'feature/execbit') | Out-Null
'feature' | Out-File -FilePath (Join-Path $rxWork 'g.txt') -Encoding utf8
Invoke-GitOk $rxWork @('add', '-A') | Out-Null
Invoke-GitOk $rxWork @('commit', '-m', 'feature') | Out-Null
Invoke-GitOk $rxWork @('push', '-u', 'origin', 'feature/execbit') | Out-Null

$rxForeign = Join-Path $rxWork '.git/hooks/pre-push'
New-Item -ItemType Directory -Force -Path (Split-Path $rxForeign) | Out-Null
$rxCanaryOut = (Join-Path $rxWork 'canary-execbit.txt') -replace '\\', '/'
Set-Content -LiteralPath $rxForeign -Encoding ascii -Value @"
#!/bin/sh
wc -l < /dev/stdin > "$rxCanaryOut"
exit 0
"@
# Žádný chmod +x tady - to je celý bod: kanárek začíná NEspustitelný, a jestli
# přesto zapíše výstup (ať už během vlastního self-testu instalátoru, nebo
# při skutečném pushi níže), spustitelnost mu dal instalátor.
$res = Invoke-Installer $rxWork $null
Assert-Eq $res.Code 0 'exec bit: instalace nezpustitelného cizího hooku uspěje řetězením'

Add-Content -Path (Join-Path $rxWork 'g.txt') -Value 'exec bit test'
Invoke-GitOk $rxWork @('commit', '-am', 'exec bit test') | Out-Null
$rExecPush = Invoke-GitTry $rxWork @('push', 'origin', 'feature/execbit')
Assert-Eq $rExecPush.Code 0 'exec bit: push na tiketovou větev projde (řetězený kanárek nic nezamítá)'
Assert-True (Test-Path $rxCanaryOut) 'exec bit: kanárek byl skutečně zavolán - instalátor odsunutý cizí hook učinil spustitelným'

Remove-Item -Recurse -Force $rxOrigin
Remove-Item -Recurse -Force $rxWork

# Sdílený core.hooksPath: řetězení se odmítne, exit 2 zůstává.
$rShared = Join-Path ([IO.Path]::GetTempPath()) ("mbshared-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$sharedHooks = Join-Path $rShared 'shared-hooks'
New-Item -ItemType Directory -Force -Path $rShared, $sharedHooks | Out-Null
& git init -q -b develop $rShared | Out-Null
Set-Content -LiteralPath (Join-Path $sharedHooks 'pre-push') -Encoding ascii -Value "#!/bin/sh`nexit 0`n"
& git -C $rShared config core.hooksPath ($sharedHooks -replace '\\', '/') | Out-Null
$res = Invoke-Installer $rShared $null
Assert-Eq $res.Code 2 'sdílený core.hooksPath: řetězení odmítnuto, exit 2'
Assert-Match $res.Flat 'shared' 'sdílený core.hooksPath: instalátor pojmenuje důvod odmítnutí'
Assert-True (-not (Test-Path (Join-Path $sharedHooks 'pre-push.ums-chained'))) 'sdílený core.hooksPath: cizí hook zůstal nedotčený'
Remove-Item -Recurse -Force $rShared

# Ruční slepenec z dřívějšího ad-hoc obcházení exitu 2: náš kód je v těle
# cizího hooku hlouběji, než kam sahá kontrola identity. Rozplétat se nesmí.
#
# Ruling R2 (controller): marker musí ležet AŽ POD pátým řádkem, jinak by ho
# Test-IsOurHook (MARKER_LINES_CHECKED=5) sám rozpoznal jako "náš hook" a
# Move-ForeignHook by se nikdy nezavolal - proto tu jsou navíc dva odstavce
# před markerem, aby padl na řádek 6.
$rMerged = Join-Path ([IO.Path]::GetTempPath()) ("mbmerged-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
& git init -q -b develop $rMerged | Out-Null
$mergedHook = Join-Path $rMerged '.git/hooks/pre-push'
New-Item -ItemType Directory -Force -Path (Split-Path $mergedHook) | Out-Null
Set-Content -LiteralPath $mergedHook -Encoding ascii -Value @"
#!/bin/sh
git lfs pre-push "`$@"
# ručně vlepeno kdysi dávno:
# (poznámka navíc, aby marker padl mimo prvních pět řádků)
# (ještě jedna poznámka)
# UMS pre-push guard (Publication Contract)
exit 0
"@
$res = Invoke-Installer $rMerged $null
Assert-Eq $res.Code 2 'ruční slepenec: instalace se nepokouší rozplétat, exit 2'
Assert-Match $res.Flat 'hand-merged' 'ruční slepenec: instalátor pojmenuje, o co jde'
Assert-True (-not (Test-Path (Join-Path $rMerged '.git/hooks/pre-push.ums-chained'))) 'ruční slepenec: nic se neodsunulo'
Remove-Item -Recurse -Force $rMerged

# ---------------------------------------------------------------------------
# Brána na značku. Sada běží běžně UVNITŘ agentního sezení, takže značku zdědí
# z prostředí - no-marker případy by pak tiše testovaly opak. Odstraníme ji
# stejně, jako se výš izoluje GIT_CONFIG_GLOBAL, a nepřítomnost ověříme.
# ---------------------------------------------------------------------------
function Invoke-WithoutMarker([scriptblock] $Body) {
    $saved = @{}
    foreach ($n in @('MB_AGENT_SESSION', 'AI_AGENT', 'CLAUDECODE')) {
        $saved[$n] = [Environment]::GetEnvironmentVariable($n)
        Remove-Item "Env:$n" -ErrorAction SilentlyContinue
    }
    try { & $Body }
    finally {
        foreach ($n in $saved.Keys) {
            if ($null -ne $saved[$n]) { Set-Item "Env:$n" $saved[$n] }
        }
    }
}

# Deleguje na Invoke-WithoutMarker, ale s parametrem POJMENOVANÝM JINAK
# (`$MarkerBody`, ne `$Body`): scriptblock invokovaný přes `&` běží v novém
# scope, jehož rodič je scope VOLAJÍCÍ funkce (dynamické rozlišení jména), ne
# lexikální scope místa, kde byl scriptblock zapsán - kdyby obě funkce měly
# parametr `$Body`, `& $Body` uvnitř vnořeného bloku by se dynamicky svázal
# s `$Body` funkce Invoke-WithoutMarker (tím vnořeným blokem samotným)
# a rekurzí do sebe přetekl zásobník (ověřeno empiricky - Stack overflow).
# S různými jmény dynamické hledání `$MarkerBody` nenajde kolizi ve
# volané funkci a doputuje až do tohoto volajícího frame.
function Invoke-WithMarker([scriptblock] $MarkerBody) {
    Invoke-WithoutMarker { $env:MB_AGENT_SESSION = '1'; try { & $MarkerBody } finally { Remove-Item Env:MB_AGENT_SESSION -ErrorAction SilentlyContinue } }
}

Invoke-WithoutMarker {
    Assert-Eq $env:MB_AGENT_SESSION $null 'izolace: MB_AGENT_SESSION je pro no-marker případy skutečně pryč'
    Assert-Eq $env:AI_AGENT $null 'izolace: AI_AGENT je pro no-marker případy skutečně pryč'
    Assert-Eq $env:CLAUDECODE $null 'izolace: CLAUDECODE je pro no-marker případy skutečně pryč'
}

# Vlastní fixtura (primární $root/$work/$origin byly výše uklizeny) - bare
# origin + work klon s nainstalovaným hookem, stejný tvar jako fixtura na
# začátku sady.
$rootMarker = Join-Path ([IO.Path]::GetTempPath()) ("mbprepushmark-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$originMarker = Join-Path $rootMarker 'origin.git'
$workMarker = Join-Path $rootMarker 'work'
New-Item -ItemType Directory -Force -Path $originMarker, $workMarker | Out-Null
& git init --bare -q -b develop $originMarker | Out-Null
& git init -q -b develop $workMarker | Out-Null
Invoke-GitOk $workMarker @('remote', 'add', 'origin', $originMarker) | Out-Null
'base' | Out-File -FilePath (Join-Path $workMarker 'f.txt') -Encoding utf8
Invoke-GitOk $workMarker @('add', '-A') | Out-Null
Invoke-GitOk $workMarker @('commit', '-m', 'base') | Out-Null
Invoke-GitOk $workMarker @('push', '-u', 'origin', 'develop') | Out-Null
Invoke-Installer $workMarker $null | Out-Null

Add-Content -Path (Join-Path $workMarker 'f.txt') -Value 'marker pair'
Invoke-GitOk $workMarker @('commit', '-am', 'marker pair') | Out-Null
$developBeforePair = Get-Sha $originMarker 'refs/heads/develop'

# TÁŽ řádka refu dvakrát, liší se jen značka.
$withMarker = Invoke-WithMarker { Invoke-GitTry $workMarker @('push', 'origin', 'develop') }
Assert-True ($withMarker.Code -ne 0) 'značka je: push na chráněnou větev zamítnut'
Assert-Eq (Get-Sha $originMarker 'refs/heads/develop') $developBeforePair 'značka je: remote se nepohnul'

$withoutMarker = Invoke-WithoutMarker { Invoke-GitTry $workMarker @('push', 'origin', 'develop') }
Assert-Eq $withoutMarker.Code 0 'značka chybí: hook nevynucuje nic, push člověka projde'
Assert-Eq (Get-Sha $originMarker 'refs/heads/develop') (Get-Sha $workMarker 'develop') 'značka chybí: remote se posunul'

# ---------------------------------------------------------------------------
# Oba Claude Code fallbacky (AI_AGENT neprázdný, CLAUDECODE=1) - dosud
# pokrytá jen samotná MB_AGENT_SESSION větev. Nový commit + push pro každý
# fallback, aby remote SHA před testem odpovídalo skutečnosti.
# ---------------------------------------------------------------------------
function Invoke-WithAiAgent([scriptblock] $FallbackBody) {
    Invoke-WithoutMarker { $env:AI_AGENT = 'anything-non-empty'; try { & $FallbackBody } finally { Remove-Item Env:AI_AGENT -ErrorAction SilentlyContinue } }
}
function Invoke-WithClaudecode([scriptblock] $FallbackBody) {
    Invoke-WithoutMarker { $env:CLAUDECODE = '1'; try { & $FallbackBody } finally { Remove-Item Env:CLAUDECODE -ErrorAction SilentlyContinue } }
}

Add-Content -Path (Join-Path $workMarker 'f.txt') -Value 'ai_agent fallback'
Invoke-GitOk $workMarker @('commit', '-am', 'ai_agent fallback') | Out-Null
$developBeforeAiAgent = Get-Sha $originMarker 'refs/heads/develop'
$rAiAgent = Invoke-WithAiAgent { Invoke-GitTry $workMarker @('push', 'origin', 'develop') }
Assert-True ($rAiAgent.Code -ne 0) 'fallback AI_AGENT: push na chráněnou větev zamítnut'
Assert-Eq (Get-Sha $originMarker 'refs/heads/develop') $developBeforeAiAgent 'fallback AI_AGENT: remote se nepohnul'

Add-Content -Path (Join-Path $workMarker 'f.txt') -Value 'claudecode fallback'
Invoke-GitOk $workMarker @('commit', '-am', 'claudecode fallback') | Out-Null
$developBeforeClaudecode = Get-Sha $originMarker 'refs/heads/develop'
$rClaudecode = Invoke-WithClaudecode { Invoke-GitTry $workMarker @('push', 'origin', 'develop') }
Assert-True ($rClaudecode.Code -ne 0) 'fallback CLAUDECODE=1: push na chráněnou větev zamítnut'
Assert-Eq (Get-Sha $originMarker 'refs/heads/develop') $developBeforeClaudecode 'fallback CLAUDECODE=1: remote se nepohnul'

Remove-Item -Recurse -Force $rootMarker

# ---------------------------------------------------------------------------
# Ruční instalace člověkem z terminálu - prostředí značku nemá. Instalátor si
# ji pro důkazní běhy nastavuje sám, jinak by o funkčním hooku hlásil, že
# záruka není potvrzená.
# ---------------------------------------------------------------------------
$rProof = Join-Path ([IO.Path]::GetTempPath()) ("mbproof-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
& git init -q -b develop $rProof | Out-Null
$res = Invoke-WithoutMarker { Invoke-Installer $rProof $null }
Assert-Eq $res.Code 0 'self-test: instalace z prostředí bez značky končí kódem 0'
Assert-Match $res.Flat 'installed \+ verified live' 'self-test: hook je ověřený i bez značky v prostředí instalátoru'
Remove-Item -Recurse -Force $rProof

# ---------------------------------------------------------------------------
# Pravidlo obsahu: na chráněné větvi projde fast-forward na commity, které už
# JSOU na cílovém remote. Dosažitelnost se omezuje na remote, do kterého se
# pushuje - tenhle fork má druhý remote (vanila), takže commit dosažitelný jen
# tam by jinak prošel jako publikovaný.
#
# Vlastní fixtura (New-PushFixture, case 17+): primární $work/$origin/$root
# mají v tuhle chvíli `develop` posunuté vlastními commity z dřívějších
# případů (case 1, 15) a `feature/x` z nich větvenou dřív, než k nim
# přibyly - jejich historie se rozešla a FF na "už publikované" by tam
# neplatilo z důvodu zamotané fixtury, ne z důvodu testované logiky.
# ---------------------------------------------------------------------------
$fxContent = New-PushFixture 'mbcontent'
$workContent = $fxContent.Work
$originContent = $fxContent.Origin
Invoke-Installer $workContent $null | Out-Null

Invoke-GitOk $workContent @('checkout', '-b', 'feature/x') | Out-Null
Add-Content -Path (Join-Path $workContent 'g.txt') -Value 'to be integrated'
Invoke-GitOk $workContent @('add', '-A') | Out-Null
Invoke-GitOk $workContent @('commit', '-m', 'integrace') | Out-Null
Invoke-GitOk $workContent @('push', '-u', 'origin', 'feature/x') | Out-Null

# a) FF na commit, který na originu už je -> projde
$r = Invoke-GitTry $workContent @('push', 'origin', 'HEAD:develop')
Assert-Eq $r.Code 0 'obsah: FF push commitu už publikovaného na originu projde'
# ASCII, konkrétní ke KTERÉ hlášce - 'fast-forward' samotné matchuje i zamítnutí
# vynuceného non-fast-forward pushe ("není fast-forward … zakázáno"), teprve
# spolu s 'povolen' (které se v zamítací hlášce nevyskytuje) je pár jednoznačný.
Assert-Match $r.Out 'fast-forward.*povolen' 'obsah: povolená integrace je ohlášená hláškou POVOLENÍ, ne obecným UMS textem'
Assert-Eq (Get-Sha $originContent 'refs/heads/develop') (Get-Sha $workContent 'feature/x') 'obsah: develop se posunul na integrovaný commit'

# b) FF na commit, který na originu NENÍ -> zamítnuto
Add-Content -Path (Join-Path $workContent 'g.txt') -Value 'nepublikovano'
Invoke-GitOk $workContent @('commit', '-am', 'nepublikovany commit') | Out-Null
$developBeforeUnpub = Get-Sha $originContent 'refs/heads/develop'
$r = Invoke-GitTry $workContent @('push', 'origin', 'HEAD:develop')
Assert-True ($r.Code -ne 0) 'obsah: FF push nepublikovaného commitu zamítnut'
Assert-Eq (Get-Sha $originContent 'refs/heads/develop') $developBeforeUnpub 'obsah: develop se po zamítnutí nepohnul'

# c) commit dosažitelný jen na JINÉM remote se nepočítá
$otherContent = Join-Path $fxContent.Root 'other.git'
& git init --bare -q -b develop $otherContent | Out-Null
Invoke-GitOk $workContent @('remote', 'add', 'vanila', $otherContent) | Out-Null
Invoke-GitOk $workContent @('push', 'vanila', 'HEAD:refs/heads/parkoviste') | Out-Null
$r = Invoke-GitTry $workContent @('push', 'origin', 'HEAD:develop')
Assert-True ($r.Code -ne 0) 'obsah: dosažitelnost na jiném remote se nepočítá'

# d) nulová remote sha (nová chráněná větev, na originu ještě vůbec neexistuje)
# -> is_integration_push ji zamítne rovnou svým vlastním guardem, i když je
# local_sha jinak dosažitelný z refs/remotes/origin/ (feature/x je publikovaná).
# `main` je v built-in seznamu chráněných vzorů, takže se řídí stejnou větví.
Invoke-GitOk $workContent @('checkout', '-b', 'main', 'feature/x') | Out-Null
$r = Invoke-GitTry $workContent @('push', 'origin', 'HEAD:refs/heads/main')
Assert-True ($r.Code -ne 0) 'obsah: nulová remote sha (nová chráněná větev) je zamítnuta i přes jinak dosažitelný commit'
Assert-Eq (Get-Sha $originContent 'refs/heads/main') $null 'obsah: main se na originu nevytvořila'

# e) nulová local sha (mazání chráněné větve) -> stejný guard, jiná strana.
$developBeforeDelete = Get-Sha $originContent 'refs/heads/develop'
$r = Invoke-GitTry $workContent @('push', 'origin', '--delete', 'develop')
Assert-True ($r.Code -ne 0) 'obsah: nulová local sha (mazání chráněné větve) je zamítnuta'
Assert-Eq (Get-Sha $originContent 'refs/heads/develop') $developBeforeDelete 'obsah: develop po pokusu o smazání zůstává na originu'

Remove-Item -Recurse -Force $fxContent.Root

# ---------------------------------------------------------------------------
# 26. THE HUMAN ESCAPE LIFTS THE WHOLE GUARD - the shared-branch rule, the
# deletion ban and the force-push ban alike. The mechanical containment
# against an agent abusing it is the PreToolUse guard (which denies any
# command carrying the variable), not a narrower scope here: once the hook
# only fires inside an agent session, a human rebasing their OWN ticket branch
# in-session carries the marker too, and a narrow escape would leave them
# nothing but turning hooks off entirely.
#
# Own fixture: the primary $work/$origin were cleaned up many cases above, and
# a force push needs a history that actually diverged from the published one.
# ---------------------------------------------------------------------------

# The parameter is NOT called $Body on purpose - see Invoke-WithMarker's own
# comment above. A scriptblock invoked with `&` resolves names against the
# CALLER's scope chain, so a $Body here would bind to Invoke-WithoutMarker's
# own $Body and recurse into itself (measured: 51 levels deep before a guard
# tripped, i.e. unbounded).
function Invoke-WithHumanPush([string] $VarName, [scriptblock] $PushBody) {
    Invoke-WithMarker {
        Set-Item "Env:$VarName" '1'
        try { & $PushBody } finally { Remove-Item "Env:$VarName" -ErrorAction SilentlyContinue }
    }
}

$fxHuman = New-PushFixture 'mbhuman'
$workHuman = $fxHuman.Work
$originHuman = $fxHuman.Origin
Invoke-Installer $workHuman $null | Out-Null

# ticket branch published, then rewritten locally -> pushing it is a genuine
# non-fast-forward, which the hook forbids without the escape
Invoke-GitOk $workHuman @('checkout', '-b', 'feature/x') | Out-Null
'feature' | Out-File -FilePath (Join-Path $workHuman 'g.txt') -Encoding utf8
Invoke-GitOk $workHuman @('add', '-A') | Out-Null
Invoke-GitOk $workHuman @('commit', '-m', 'feature') | Out-Null
Invoke-GitOk $workHuman @('push', '-u', 'origin', 'feature/x') | Out-Null
$featurePublished = Get-Sha $originHuman 'refs/heads/feature/x'
Invoke-GitOk $workHuman @('reset', '--hard', 'HEAD~1') | Out-Null
'prepsana historie' | Out-File -FilePath (Join-Path $workHuman 'g.txt') -Encoding utf8
Invoke-GitOk $workHuman @('add', '-A') | Out-Null
Invoke-GitOk $workHuman @('commit', '-m', 'prepsana historie') | Out-Null

# Controls FIRST: without the escape the very same push must be rejected,
# otherwise the assertions below would prove nothing about the escape - only
# that a force push happens to be legal here.
$r = Invoke-GitTry $workHuman @('push', '--force', 'origin', 'HEAD:feature/x')
Assert-True ($r.Code -ne 0) 'kontrola: bez výjimky je force push vlastní větve zamítnutý'
Assert-Eq (Get-Sha $originHuman 'refs/heads/feature/x') $featurePublished 'kontrola: vzdálená feature/x se po zamítnutí nezměnila'

# ... and a value other than 1 is not the escape either (`= "1"`, not `-n`)
$r = Invoke-WithMarker {
    $env:MB_HUMAN_PUSH = '0'
    try { Invoke-GitTry $workHuman @('push', '--force', 'origin', 'HEAD:feature/x') }
    finally { Remove-Item Env:MB_HUMAN_PUSH -ErrorAction SilentlyContinue }
}
Assert-True ($r.Code -ne 0) 'kontrola: MB_HUMAN_PUSH=0 výjimkou není, force push zůstává zamítnutý'
Assert-Eq (Get-Sha $originHuman 'refs/heads/feature/x') $featurePublished 'kontrola: vzdálená feature/x se ani po MB_HUMAN_PUSH=0 nezměnila'

$r = Invoke-WithHumanPush 'MB_HUMAN_PUSH' { Invoke-GitTry $workHuman @('push', '--force', 'origin', 'HEAD:feature/x') }
Assert-Eq $r.Code 0 'výjimka: force push vlastní větve s MB_HUMAN_PUSH projde'
# ASCII-only pattern: git's stderr reaches this suite through the console code
# page, which mangles diacritics.
Assert-Match $r.Out 'MB_HUMAN_PUSH' 'výjimka: povolení je ohlášené na stderr'
Assert-Eq (Get-Sha $originHuman 'refs/heads/feature/x') (Get-Sha $workHuman 'feature/x') 'výjimka: vzdálená feature/x se posunula na přepsanou historii'

# deletion, the second rule the escape used to leave standing
$r = Invoke-WithHumanPush 'MB_HUMAN_PUSH' { Invoke-GitTry $workHuman @('push', 'origin', '--delete', 'feature/x') }
Assert-Eq $r.Code 0 'výjimka: mazání větve s MB_HUMAN_PUSH projde'
Assert-Eq (Get-Sha $originHuman 'refs/heads/feature/x') $null 'výjimka: vzdálená feature/x je skutečně smazaná'

# the OLD name stays accepted for the transition, announcing itself as
# deprecated and naming the new one
Invoke-GitOk $workHuman @('checkout', 'develop') | Out-Null
Add-Content -Path (Join-Path $workHuman 'f.txt') -Value 'nepublikovana zmena'
Invoke-GitOk $workHuman @('commit', '-am', 'nepublikovana zmena') | Out-Null
$developBeforeOldName = Get-Sha $originHuman 'refs/heads/develop'
$r = Invoke-GitTry $workHuman @('push', 'origin', 'HEAD:develop')
Assert-True ($r.Code -ne 0) 'kontrola: bez výjimky je push nepublikovaného commitu do develop zamítnutý'
Assert-Eq (Get-Sha $originHuman 'refs/heads/develop') $developBeforeOldName 'kontrola: develop se po zamítnutí nepohnul'

$r = Invoke-WithHumanPush 'UMS_ALLOW_SHARED_PUSH' { Invoke-GitTry $workHuman @('push', 'origin', 'HEAD:develop') }
Assert-Eq $r.Code 0 'výjimka: staré jméno je přechodně stále přijímané'
Assert-Match $r.Out 'MB_HUMAN_PUSH' 'výjimka: staré jméno hlásí, že je zastaralé, a jmenuje nové'
Assert-Match $r.Out 'UMS_ALLOW_SHARED_PUSH' 'výjimka: hláška o zastaralosti pojmenuje i staré jméno'
Assert-Eq (Get-Sha $originHuman 'refs/heads/develop') (Get-Sha $workHuman 'develop') 'výjimka: develop se se starým jménem posunul'

Remove-Item -Recurse -Force $fxHuman.Root

# ---------------------------------------------------------------------------
# 27. The escape path still CHAINS (fix round 1, Minor 8). Lifting the guard
# must not turn a foreign hook off: the escape exits through run_chained for
# the same reason the marker gate does, and a future refactor to a bare
# `exit 0` would otherwise be caught by nothing. Same canary shape as the
# exec-bit case above — the chained hook writes a file, and its absence is the
# whole finding.
# ---------------------------------------------------------------------------
$fxChainEsc = New-PushFixture 'mbhumanchain'
$workChainEsc = $fxChainEsc.Work
$originChainEsc = $fxChainEsc.Origin
$foreignChainEsc = Join-Path $workChainEsc '.git/hooks/pre-push'
New-Item -ItemType Directory -Force -Path (Split-Path $foreignChainEsc) | Out-Null
$canaryChainEsc = (Join-Path $workChainEsc 'canary-escape.txt') -replace '\\', '/'
Set-Content -LiteralPath $foreignChainEsc -Encoding ascii -Value @"
#!/bin/sh
wc -l < /dev/stdin > "$canaryChainEsc"
exit 0
"@
Invoke-Installer $workChainEsc $null | Out-Null
Assert-True (Test-Path (Join-Path $workChainEsc '.git/hooks/pre-push.ums-chained')) 'řetězení s výjimkou: cizí hook je odsunutý a zřetězený'

# a push the guard would REJECT without the escape, so the escape is what
# carries this run all the way to the chained hook
Add-Content -Path (Join-Path $workChainEsc 'f.txt') -Value 'nepublikovana zmena'
Invoke-GitOk $workChainEsc @('commit', '-am', 'nepublikovana zmena') | Out-Null
Remove-Item -LiteralPath $canaryChainEsc -Force -ErrorAction SilentlyContinue
$r = Invoke-GitTry $workChainEsc @('push', 'origin', 'HEAD:develop')
Assert-True ($r.Code -ne 0) 'řetězení s výjimkou: kontrola - bez výjimky je push zamítnutý'
Assert-True (-not (Test-Path $canaryChainEsc)) 'řetězení s výjimkou: kontrola - zamítnutý push řetězený hook vůbec nespouští'

$r = Invoke-WithHumanPush 'MB_HUMAN_PUSH' { Invoke-GitTry $workChainEsc @('push', 'origin', 'HEAD:develop') }
Assert-Eq $r.Code 0 'řetězení s výjimkou: s MB_HUMAN_PUSH push projde'
Assert-True (Test-Path $canaryChainEsc) 'řetězení s výjimkou: výjimka NEVYPÍNÁ cizí hook - kanárek se spustil'
Assert-Eq (Get-Sha $originChainEsc 'refs/heads/develop') (Get-Sha $workChainEsc 'develop') 'řetězení s výjimkou: develop se posunul'

Remove-Item -Recurse -Force $fxChainEsc.Root

Complete-Tests
