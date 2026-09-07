# Builds an offline fixture for the handoff gate: a bare "origin", a working
# clone, and one branch per gate outcome. Returns a hashtable with the paths,
# the base ref and one SHA per outcome.
#
# The fixture is built so that EACH of the gate's three checks has at least one
# SHA that only THAT check can redden. Alibi-free by construction:
#
#   MergedSha     descends from the base commit, IDLE context.md, pushed
#                 -> everything green until Move-GateBase moves the base
#   ActiveSha     descends from the MOVED base, pushed, ACTIVE context.md
#   UnpushedSha   descends from the MOVED base, IDLE context.md, NOT pushed
#   NoContextSha  descends from the MOVED base, pushed, context.md DELETED
#
# The three negative branches are cut from the commit that Move-GateBase later
# makes the base, so moving the base does NOT also break their ancestry — that
# would give the ancestor check an alibi for all three findings.
#
# Move-GateBase pushes the base from a SECOND clone, so the first clone's
# refs/remotes/origin/<base> stays stale until something fetches. That is what
# makes the gate's `git fetch origin` load-bearing rather than decorative.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:GateBaseBranch = 'ums-memory-bank'

function Invoke-GateGit([string] $RepoDir, [string[]] $GitArgs) {
    # core.autocrlf=false: `git show <sha>:<path>` must return the bytes that
    # were committed, whatever the machine's global autocrlf says (on Windows
    # the fork's own checkout runs with autocrlf=true).
    $out = & git -C $RepoDir -c user.name=Test -c user.email=test@example.com `
        -c core.autocrlf=false -c commit.gpgsign=false @GitArgs 2>&1
    if ($LASTEXITCODE -ne 0) { throw "git $($GitArgs -join ' ') failed: $out" }
    return $out
}

function Set-GateContext([string] $RepoDir, [string] $State, [string] $Slug) {
    $path = Join-Path $RepoDir 'memory-bank/context.md'
    New-Item -ItemType Directory -Force -Path (Split-Path $path) | Out-Null
    if ($State -eq 'idle') {
        # Contract, "`context.md` Schema & Writers": the IDLE file carries the
        # IDLE marker, keeps `Báze:` and has NO `Jira:` line.
        $body = @(
            '# Context'
            ''
            '## Active Work'
            ''
            '(No active work - IDLE phase)'
            ''
            "- **Báze:** origin/$script:GateBaseBranch"
        )
    }
    else {
        $body = @(
            '# Context'
            ''
            '## Active Work'
            ''
            '- **Jira:** UMS-9999 (https://jira.datasys.cz/browse/UMS-9999)'
            '- **Target MB Pin:** memory-bank/'
            "- **Work item:** $Slug"
            '- **Started:** 2026-09-07'
        )
    }
    Set-Content -LiteralPath $path -Encoding UTF8 -Value $body
    Invoke-GateGit $RepoDir @('add', 'memory-bank/context.md') | Out-Null
}

function New-GateFixture {
    $root = Join-Path ([IO.Path]::GetTempPath()) ("ums-gate-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $origin = Join-Path $root 'origin.git'
    $clone = Join-Path $root 'clone'
    $pusher = Join-Path $root 'pusher'
    New-Item -ItemType Directory -Force -Path $origin, $clone | Out-Null
    & git init --bare -b $script:GateBaseBranch $origin | Out-Null
    & git init -b $script:GateBaseBranch $clone | Out-Null
    Invoke-GateGit $clone @('remote', 'add', 'origin', $origin) | Out-Null
    Invoke-GateGit $clone @('config', 'core.autocrlf', 'false') | Out-Null
    Invoke-GateGit $clone @('config', 'user.name', 'Test') | Out-Null
    Invoke-GateGit $clone @('config', 'user.email', 'test@example.com') | Out-Null

    # base: IDLE context.md plus the repository configuration the gate reads
    # (contract, "Repository Configuration": baseRef).
    New-Item -ItemType Directory -Force -Path (Join-Path $clone 'memory-bank') | Out-Null
    Set-Content -LiteralPath (Join-Path $clone 'memory-bank/ums-repo.json') -Encoding UTF8 `
        -Value "{ `"baseRef`": `"origin/$script:GateBaseBranch`" }"
    Set-GateContext $clone 'idle' ''
    Invoke-GateGit $clone @('add', 'memory-bank/ums-repo.json') | Out-Null
    Invoke-GateGit $clone @('commit', '-m', 'base') | Out-Null
    Invoke-GateGit $clone @('push', '-u', 'origin', $script:GateBaseBranch) | Out-Null

    # The ticket branch as the gate should see it: descendant of the base,
    # IDLE context.md (post-harvest), published.
    Invoke-GateGit $clone @('checkout', '-b', 'UMS-1-hotovo', $script:GateBaseBranch) | Out-Null
    Set-Content -LiteralPath (Join-Path $clone 'hotovo.txt') -Encoding UTF8 -Value 'práce'
    Invoke-GateGit $clone @('add', 'hotovo.txt') | Out-Null
    Invoke-GateGit $clone @('commit', '-m', 'hotová práce') | Out-Null
    Invoke-GateGit $clone @('push', 'origin', 'UMS-1-hotovo') | Out-Null
    $mergedSha = (Invoke-GateGit $clone @('rev-parse', 'HEAD')).Trim()

    # The commit Move-GateBase later makes the base. Published under its own
    # branch name so the three negative branches below are publishable without
    # touching the base itself.
    Invoke-GateGit $clone @('checkout', '-b', 'base-next', $script:GateBaseBranch) | Out-Null
    Set-Content -LiteralPath (Join-Path $clone 'cizi.txt') -Encoding UTF8 -Value 'cizí práce na bázi'
    Invoke-GateGit $clone @('add', 'cizi.txt') | Out-Null
    Invoke-GateGit $clone @('commit', '-m', 'cizí commit na bázi') | Out-Null
    Invoke-GateGit $clone @('push', 'origin', 'base-next') | Out-Null

    # ACTIVE pin: only the context check may redden this one.
    Invoke-GateGit $clone @('checkout', '-b', 'UMS-2-aktivni', 'base-next') | Out-Null
    Set-GateContext $clone 'active' 'rozdelana_prace'
    Invoke-GateGit $clone @('commit', '-m', 'rozdělaná práce s ACTIVE pinem') | Out-Null
    Invoke-GateGit $clone @('push', 'origin', 'UMS-2-aktivni') | Out-Null
    $activeSha = (Invoke-GateGit $clone @('rev-parse', 'HEAD')).Trim()

    # context.md missing at that SHA: `git show` exits 128 there.
    Invoke-GateGit $clone @('checkout', '-b', 'UMS-3-bez-contextu', 'base-next') | Out-Null
    Invoke-GateGit $clone @('rm', '--quiet', 'memory-bank/context.md') | Out-Null
    Invoke-GateGit $clone @('commit', '-m', 'bez context.md') | Out-Null
    Invoke-GateGit $clone @('push', 'origin', 'UMS-3-bez-contextu') | Out-Null
    $noContextSha = (Invoke-GateGit $clone @('rev-parse', 'HEAD')).Trim()

    # Never pushed: only the publication check may redden this one.
    Invoke-GateGit $clone @('checkout', '-b', 'UMS-4-nepublikovano', 'base-next') | Out-Null
    Set-Content -LiteralPath (Join-Path $clone 'lokalni.txt') -Encoding UTF8 -Value 'jen lokálně'
    Invoke-GateGit $clone @('add', 'lokalni.txt') | Out-Null
    Invoke-GateGit $clone @('commit', '-m', 'nepublikovaný commit') | Out-Null
    $unpushedSha = (Invoke-GateGit $clone @('rev-parse', 'HEAD')).Trim()

    # Back to the base, so the working tree the gate reads its configuration
    # from is the base's.
    Invoke-GateGit $clone @('checkout', $script:GateBaseBranch) | Out-Null

    # Second clone: exists only so Move-GateBase can advance the base WITHOUT
    # updating the first clone's remote-tracking refs.
    & git clone --quiet $origin $pusher | Out-Null
    Invoke-GateGit $pusher @('config', 'core.autocrlf', 'false') | Out-Null
    Invoke-GateGit $pusher @('config', 'user.name', 'Test') | Out-Null
    Invoke-GateGit $pusher @('config', 'user.email', 'test@example.com') | Out-Null

    return @{
        Root         = $root
        Clone        = $clone
        Origin       = $origin
        Pusher       = $pusher
        BaseBranch   = $script:GateBaseBranch
        BaseRef      = "origin/$script:GateBaseBranch"
        MergedSha    = $mergedSha
        ActiveSha    = $activeSha
        UnpushedSha  = $unpushedSha
        NoContextSha = $noContextSha
    }
}

# Advances the base by one commit, from the second clone. Fast-forward: the new
# base commit is a descendant of the old one. The first clone learns about it
# only by fetching.
function Move-GateBase($Fixture) {
    Invoke-GateGit $Fixture.Pusher @('fetch', 'origin', '--quiet') | Out-Null
    Invoke-GateGit $Fixture.Pusher @(
        'push', 'origin', "refs/remotes/origin/base-next:refs/heads/$($Fixture.BaseBranch)") | Out-Null
}

function Remove-GateFixture($Fixture) {
    if ($Fixture -and $Fixture.Root -and (Test-Path -LiteralPath $Fixture.Root)) {
        Remove-Item -LiteralPath $Fixture.Root -Recurse -Force -ErrorAction SilentlyContinue
    }
}
