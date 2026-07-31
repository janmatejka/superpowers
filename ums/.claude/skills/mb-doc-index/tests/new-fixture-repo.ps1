# Builds an offline fixture: a bare "origin" plus a clone with several branches
# carrying Memory Bank documents. Returns @{ Work=<path>; Origin=<path> }.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-Git([string] $RepoDir, [string[]] $GitArgs) {
    $out = & git -C $RepoDir -c user.name=Test -c user.email=test@example.com @GitArgs 2>&1
    if ($LASTEXITCODE -ne 0) { throw "git $($GitArgs -join ' ') failed: $out" }
    return $out
}

function Add-Doc([string] $RepoDir, [string] $RelPath, [string] $Jira) {
    $full = Join-Path $RepoDir $RelPath
    New-Item -ItemType Directory -Force -Path (Split-Path $full) | Out-Null
    Set-Content -LiteralPath $full -Encoding UTF8 -Value @(
        "# Návrh: $([IO.Path]::GetFileNameWithoutExtension($RelPath))"
        ""
        "- **Jira:** $Jira"
        "- **Target MB:** memory-bank/"
    )
    Invoke-Git $RepoDir @('add', $RelPath) | Out-Null
}

function New-FixtureRepo {
    $root = Join-Path ([IO.Path]::GetTempPath()) ("mbidx-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $origin = Join-Path $root 'origin.git'
    $work = Join-Path $root 'work'
    New-Item -ItemType Directory -Force -Path $origin, $work | Out-Null
    & git init --bare -b develop $origin | Out-Null
    & git init -b develop $work | Out-Null
    Invoke-Git $work @('remote', 'add', 'origin', $origin) | Out-Null

    # base: one completed document, plus one already-queued document that
    # never changes after this commit. This is the repro for a false
    # "DRAFT NA VÍCE VĚTVÍCH": since every branch below descends from this
    # same commit, the file shows up unmodified in BOTH the 'base' pseudo-branch
    # (BaseRef content) AND the 'local' pseudo-branch (working tree of
    # whichever branch is checked out) — that must count as ONE actor, not two.
    Add-Doc $work 'memory-bank/proposals/completed/design_hotovo.md' 'UMS-0'
    Add-Doc $work 'memory-bank/proposals/next/design_ums_6_fronta.md' 'UMS-6'
    Invoke-Git $work @('commit', '-m', 'base') | Out-Null
    Invoke-Git $work @('push', '-u', 'origin', 'develop') | Out-Null

    # active work item on a foreign branch
    Invoke-Git $work @('checkout', '-b', 'feature/ums-1-alfa', 'develop') | Out-Null
    Add-Doc $work 'memory-bank/proposals/active/design_ums_1_alfa.md' 'UMS-1'
    Invoke-Git $work @('commit', '-m', 'alfa') | Out-Null
    Invoke-Git $work @('push', 'origin', 'feature/ums-1-alfa') | Out-Null

    # the same queued draft on two branches
    foreach ($b in @('feature/ums-2-beta', 'feature/ums-2-beta-dup')) {
        Invoke-Git $work @('checkout', '-b', $b, 'develop') | Out-Null
        Add-Doc $work 'memory-bank/proposals/next/design_ums_2_beta.md' 'UMS-2'
        Invoke-Git $work @('commit', '-m', "beta on $b") | Out-Null
        Invoke-Git $work @('push', 'origin', $b) | Out-Null
    }

    # queued on one branch, completed on another
    Invoke-Git $work @('checkout', '-b', 'feature/ums-3-gama', 'develop') | Out-Null
    Add-Doc $work 'memory-bank/proposals/next/design_ums_3_gama.md' 'UMS-3'
    Invoke-Git $work @('commit', '-m', 'gama next') | Out-Null
    Invoke-Git $work @('push', 'origin', 'feature/ums-3-gama') | Out-Null
    Invoke-Git $work @('checkout', '-b', 'feature/ums-3-gama-done', 'develop') | Out-Null
    Add-Doc $work 'memory-bank/proposals/completed/design_ums_3_gama.md' 'UMS-3'
    Invoke-Git $work @('commit', '-m', 'gama done') | Out-Null
    Invoke-Git $work @('push', 'origin', 'feature/ums-3-gama-done') | Out-Null

    # test fixture path -> must be excluded from the index
    Invoke-Git $work @('checkout', '-b', 'feature/ums-4-fixture', 'develop') | Out-Null
    Add-Doc $work 'ums/.claude/skills/x/tests/fixtures/memory-bank/proposals/active/design_fixture.md' 'UMS-4'
    Invoke-Git $work @('commit', '-m', 'fixture doc') | Out-Null
    Invoke-Git $work @('push', 'origin', 'feature/ums-4-fixture') | Out-Null

    # stale branch (2 years old) -> excluded by default -SinceDays
    Invoke-Git $work @('checkout', '-b', 'feature/ums-5-stare', 'develop') | Out-Null
    Add-Doc $work 'memory-bank/proposals/next/design_ums_5_stare.md' 'UMS-5'
    $old = (Get-Date).AddYears(-2).ToString('yyyy-MM-ddTHH:mm:ss')
    $env:GIT_AUTHOR_DATE = $old; $env:GIT_COMMITTER_DATE = $old
    Invoke-Git $work @('commit', '-m', 'stare') | Out-Null
    Remove-Item Env:GIT_AUTHOR_DATE, Env:GIT_COMMITTER_DATE
    Invoke-Git $work @('push', 'origin', 'feature/ums-5-stare') | Out-Null

    Invoke-Git $work @('checkout', 'develop') | Out-Null
    return @{ Work = $work; Origin = $origin }
}
