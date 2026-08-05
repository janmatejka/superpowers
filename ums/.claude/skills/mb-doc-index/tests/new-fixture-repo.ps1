# Builds an offline fixture: a bare "origin" plus a clone with several branches
# carrying Memory Bank documents. Returns @{ Work=<path>; Origin=<path> }.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-Git([string] $RepoDir, [string[]] $GitArgs) {
    $out = & git -C $RepoDir -c user.name=Test -c user.email=test@example.com @GitArgs 2>&1
    if ($LASTEXITCODE -ne 0) { throw "git $($GitArgs -join ' ') failed: $out" }
    return $out
}

# Every commit gets an EXPLICIT author AND committer date, given as an AGE in
# days relative to fixture creation. -SinceDays filters on the branch TIP's age,
# so ages must be deterministic: a fixture that let the clock supply dates would
# pass today and fail in a month (and the "old commit on a live branch" case
# would silently stop being old at all).
function Invoke-GitCommit([string] $RepoDir, [string] $Message, [int] $AgeDays) {
    $when = [DateTimeOffset]::UtcNow.AddDays(-$AgeDays).ToString('yyyy-MM-ddTHH:mm:sszzz')
    $env:GIT_AUTHOR_DATE = $when
    $env:GIT_COMMITTER_DATE = $when
    try { Invoke-Git $RepoDir @('commit', '-m', $Message) | Out-Null }
    finally { Remove-Item Env:GIT_AUTHOR_DATE, Env:GIT_COMMITTER_DATE -ErrorAction SilentlyContinue }
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
    # The base commit is deliberately OLD: the base ref is excluded from the
    # traversal by ^BaseRef anyway, so its own age must not matter.
    Add-Doc $work 'memory-bank/proposals/completed/design_hotovo.md' 'UMS-0'
    Add-Doc $work 'memory-bank/proposals/next/design_ums_6_fronta.md' 'UMS-6'
    # Repository configuration (contract: "Repository Configuration"). Set to
    # the loader's own built-in fallback, so tests that pass -BaseRef
    # explicitly are unaffected; the config-precedence tests overwrite this
    # file in the working tree (the loader reads the file, not the commit).
    Set-Content -LiteralPath (Join-Path $work 'memory-bank/ums-repo.json') -Encoding UTF8 `
        -Value '{ "baseRef": "origin/develop" }'
    Invoke-Git $work @('add', 'memory-bank/ums-repo.json') | Out-Null
    Invoke-GitCommit $work 'base' 500
    Invoke-Git $work @('push', '-u', 'origin', 'develop') | Out-Null

    # active work item on a foreign branch
    Invoke-Git $work @('checkout', '-b', 'feature/ums-1-alfa', 'develop') | Out-Null
    Add-Doc $work 'memory-bank/proposals/active/design_ums_1_alfa.md' 'UMS-1'
    Invoke-GitCommit $work 'alfa' 3
    Invoke-Git $work @('push', 'origin', 'feature/ums-1-alfa') | Out-Null

    # the same queued draft on two branches
    foreach ($b in @('feature/ums-2-beta', 'feature/ums-2-beta-dup')) {
        Invoke-Git $work @('checkout', '-b', $b, 'develop') | Out-Null
        Add-Doc $work 'memory-bank/proposals/next/design_ums_2_beta.md' 'UMS-2'
        Invoke-GitCommit $work "beta on $b" 5
        Invoke-Git $work @('push', 'origin', $b) | Out-Null
    }

    # queued on one branch, completed on another
    Invoke-Git $work @('checkout', '-b', 'feature/ums-3-gama', 'develop') | Out-Null
    Add-Doc $work 'memory-bank/proposals/next/design_ums_3_gama.md' 'UMS-3'
    Invoke-GitCommit $work 'gama next' 6
    Invoke-Git $work @('push', 'origin', 'feature/ums-3-gama') | Out-Null
    Invoke-Git $work @('checkout', '-b', 'feature/ums-3-gama-done', 'develop') | Out-Null
    Add-Doc $work 'memory-bank/proposals/completed/design_ums_3_gama.md' 'UMS-3'
    Invoke-GitCommit $work 'gama done' 7
    Invoke-Git $work @('push', 'origin', 'feature/ums-3-gama-done') | Out-Null

    # test fixture path -> must be excluded from the index
    Invoke-Git $work @('checkout', '-b', 'feature/ums-4-fixture', 'develop') | Out-Null
    Add-Doc $work 'ums/.claude/skills/x/tests/fixtures/memory-bank/proposals/active/design_fixture.md' 'UMS-4'
    Invoke-GitCommit $work 'fixture doc' 4
    Invoke-Git $work @('push', 'origin', 'feature/ums-4-fixture') | Out-Null

    # abandoned branch: its TIP is 2 years old -> outside the default window
    Invoke-Git $work @('checkout', '-b', 'feature/ums-5-stare', 'develop') | Out-Null
    Add-Doc $work 'memory-bank/proposals/next/design_ums_5_stare.md' 'UMS-5'
    Invoke-GitCommit $work 'stare' 730
    Invoke-Git $work @('push', 'origin', 'feature/ums-5-stare') | Out-Null

    # LIVE branch whose design document was committed LONG AGO: the tip is 2
    # days old, the commit that added the document is 400 days old. Filtering by
    # COMMIT date drops it (the false negative that forced the default window up
    # to 120 days); filtering by TIP age keeps it and finds the whole history.
    Invoke-Git $work @('checkout', '-b', 'feature/ums-10-obnovena', 'develop') | Out-Null
    Add-Doc $work 'memory-bank/proposals/active/design_ums_10_obnovena.md' 'UMS-10'
    Invoke-GitCommit $work 'obnovena design (dávno)' 400
    Set-Content -LiteralPath (Join-Path $work 'obnovena.txt') -Encoding UTF8 -Value 'stale-doc, fresh branch'
    Invoke-Git $work @('add', 'obnovena.txt') | Out-Null
    Invoke-GitCommit $work 'obnovena tip (čerstvý)' 2
    Invoke-Git $work @('push', 'origin', 'feature/ums-10-obnovena') | Out-Null

    # DORMANT branch carrying ACTIVE work on UMS-11: outside the display window,
    # but declared intent (-Jira UMS-11) must still find it and stop pinning.
    Invoke-Git $work @('checkout', '-b', 'feature/ums-11-uspana', 'develop') | Out-Null
    Add-Doc $work 'memory-bank/proposals/active/design_ums_11_uspana.md' 'UMS-11'
    Invoke-GitCommit $work 'uspana' 200
    Invoke-Git $work @('push', 'origin', 'feature/ums-11-uspana') | Out-Null

    # Branch name with DIACRITICS. Ref names round-trip through PowerShell now
    # (for-each-ref -> git log --stdin), and the target monorepo really has
    # branches like origin/UMS-1646-mobilní-klient-pro-alarminfo: if the
    # round trip is not UTF-8 on both sides, git answers "fatal: bad revision"
    # and the whole index aborts.
    Invoke-Git $work @('checkout', '-b', 'feature/ums-12-diakritika-ěšč', 'develop') | Out-Null
    Add-Doc $work 'memory-bank/proposals/active/design_ums_12_diakritika.md' 'UMS-12'
    Invoke-GitCommit $work 'diakritika' 1
    Invoke-Git $work @('push', 'origin', 'feature/ums-12-diakritika-ěšč') | Out-Null

    # A real clone has refs/remotes/origin/HEAD (a symref to the base branch);
    # `git init` + `remote add` does not, so create it explicitly — the index
    # must skip it instead of indexing the base twice.
    Invoke-Git $work @('remote', 'set-head', 'origin', 'develop') | Out-Null

    Invoke-Git $work @('checkout', 'develop') | Out-Null
    return @{ Work = $work; Origin = $origin }
}
