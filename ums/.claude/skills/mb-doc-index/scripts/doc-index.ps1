#Requires -Version 7
<#
.SYNOPSIS
Read-only index of Memory Bank documents across origin branches (pull model).

.DESCRIPTION
Builds the candidate set for Target-MB discovery, the cross-clone collision
check and the epic graph: one history traversal over remote refs above the base
ref, filtered by path and age. Writes nothing but the optional -Json file.

Three sources are merged into one picture: foreign origin branches (the log
traversal below), the local working tree (pseudo-branch "local") and the base
ref content (pseudo-branch "base", read via git ls-tree). Entries from all
three go into -Json; the printed table shows only phases next/active —
completed entries are indexed but not printed (a later consumer needs them to
tell a queued draft from one already completed on another branch).

.PARAMETER RepoPath
Repository root. Defaults to the toplevel of the current directory.

.PARAMETER BaseRef
Ref the traversal excludes (commits already visible there don't need a pull
model). Defaults to origin/develop.

.PARAMETER SinceDays
Only commits within this many days (by committer date) are considered.

.PARAMETER BranchGlob
When set, restricts the ORIGIN branches considered to those matching this
-like pattern (e.g. 'origin/feature/ums-1-*'). Does not affect the local/base
pseudo-branches.

.PARAMETER Jira
DECLARED INTENT: the ticket the caller is about to start work on. Foreign
active work on that ticket is then a KOLIZE AKTIVNÍ PRÁCE (CHYBA, exit 2) even
when nothing is active locally yet — which is exactly the situation during
Target-MB discovery, where the design document does not exist so far.

.PARAMETER Slug
DECLARED INTENT, same as -Jira but matched on the work-item slug. Either or
both may be supplied; a foreign active entry matching EITHER is a collision.

.PARAMETER Json
Optional path to also write the full index as JSON.

.PARAMETER NoFetch
Skip 'git fetch --prune origin' (offline fixtures, or when the caller already
fetched).

.OUTPUTS
Czech table + findings. Exit: 0 = OK, 1 = input/script failure, 2 = collisions.
#>
[CmdletBinding()]
param(
    [string] $RepoPath = '',
    [string] $BaseRef = 'origin/develop',
    [int]    $SinceDays = 120,
    [string] $BranchGlob = '',
    [string] $Jira = '',
    [string] $Slug = '',
    [string] $Json = '',
    [switch] $NoFetch
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
$script:ExitCode = 0

# --- repo resolution (contract: one discovery step) -------------------------
# NB: $LASTEXITCODE must only be inspected right after a native call in the
# SAME branch — under Set-StrictMode, reading it before any native command has
# run in this session throws ("cannot be retrieved because it has not been
# set"), which is exactly what happens here when -RepoPath is supplied
# explicitly (the -RepoPath given branch never runs "& git rev-parse").
if (-not $RepoPath) {
    $RepoPath = (& git rev-parse --show-toplevel)
    if ($LASTEXITCODE -ne 0 -or -not $RepoPath) {
        Write-Error 'Git repository not found. Memory Bank requires git.'; exit 1
    }
} elseif (-not (Test-Path -LiteralPath $RepoPath)) {
    Write-Error "Repository path not found: $RepoPath"; exit 1
}
# NB: the wrapper is intentionally NOT named "Git" — PowerShell's command
# resolution is case-insensitive and prefers a Function over an Application,
# so "& git ..." inside the wrapper would resolve back to the wrapper itself
# and recurse until the call stack overflows. Confirmed by running it.
function Invoke-RepoGit([string[]] $GitArgs) { & git -C $RepoPath @GitArgs 2>$null }

# --- git-call failure semantics ---------------------------------------------
# TRAVERSAL/DATA calls below (fetch, log, branch -r --contains, show, ls-tree,
# rev-parse for the base snapshot) read data the rest of the script depends
# on: a non-zero exit there is a genuine git-level FAILURE (corrupt pack, I/O
# error, resource limits against a large real repo) and must exit 1 — never
# be swallowed into "clean run, nothing found". Use Stop-OnGitFailure right
# after each such call.
# This is DELIBERATELY different from the "cat-file -e" PROBE further below
# (existence check before reading a branch tip): its non-zero exit is a
# legitimate ANSWER ("this path is not on that branch's tip"), not a
# failure — it must keep meaning exactly that and must NEVER be routed
# through Stop-OnGitFailure.
function Stop-OnGitFailure([string] $What) {
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Selhání příkazu git ($What), exit kód ${LASTEXITCODE}: index nelze spolehlivě sestavit."
        exit 1
    }
}

if (-not $NoFetch) {
    Invoke-RepoGit @('fetch', '--prune', 'origin') | Out-Null
    Stop-OnGitFailure 'fetch --prune origin'
}
Invoke-RepoGit @('rev-parse', '--verify', '--quiet', $BaseRef) | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Error "Base ref not found: $BaseRef"; exit 1 }

# --- own identity: which remote ref is "me", never a foreign-collision source
# The actor's own already-pushed branch must never collide with their own
# local work (contract: collisions are about OTHER actors, never yourself).
# Prefers the current branch's configured upstream; falls back to a
# same-named origin branch when no upstream is configured; returns '' when
# neither exists — nothing to exclude in that case (e.g. detached HEAD, a
# brand-new local branch never pushed).
function Get-OwnRemoteRef() {
    # PROBE, not a traversal/data call: a non-zero exit here means "no
    # upstream configured" / "no such ref" / "detached HEAD" — a legitimate
    # ANSWER, not a git failure. Never route through Stop-OnGitFailure.
    $upstream = Invoke-RepoGit @('rev-parse', '--abbrev-ref', '--symbolic-full-name', '@{u}')
    if ($LASTEXITCODE -eq 0 -and $upstream) { return (@($upstream)[0]).Trim() }

    $branch = Invoke-RepoGit @('rev-parse', '--abbrev-ref', 'HEAD')
    if ($LASTEXITCODE -ne 0 -or -not $branch) { return '' }
    $branch = (@($branch)[0]).Trim()
    if (-not $branch -or $branch -eq 'HEAD') { return '' }   # detached HEAD

    $candidate = "origin/$branch"
    Invoke-RepoGit @('rev-parse', '--verify', '--quiet', $candidate) | Out-Null
    if ($LASTEXITCODE -eq 0) { return $candidate }
    return ''
}
$script:OwnRemoteRef = Get-OwnRemoteRef

function Test-FixturePath([string] $Path) { return ($Path -match '/tests/fixtures/') }

function Get-Slug([string] $Path) {
    # Contract pairing rule: strip exactly ONE prefix; '-design' only after 'proposal_'.
    $stem = [IO.Path]::GetFileNameWithoutExtension($Path)
    if ($stem -match '^proposal_(.+)$') { return ($Matches[1] -replace '-design$', '') }
    if ($stem -match '^(design_|plan_)(.+)$') { return $Matches[2] }
    return $stem
}

function Get-Phase([string] $Path) { return (Split-Path (Split-Path $Path -Parent) -Leaf) }

# NB: the per-document header value is held in $docJira, NOT $jira — PowerShell
# variable names are case-insensitive, so a local `$jira = …` would silently
# overwrite the -Jira PARAMETER and the declared-intent collision check would
# never fire. Confirmed by running it (the -Slug path worked, -Jira did not).
function Get-JiraHeader([string[]] $Lines) {
    foreach ($ln in $Lines) {
        if ($ln -match '^-\s*\*\*Jira:\*\*\s*(.+?)\s*$') { return $Matches[1] }
    }
    return ''
}

# --- findings: collision/queue-state candidates for the user, never silent
# fixes (contract: fail-closed). Severity CHYBA raises the exit code to 2 —
# the fail-closed STOP for pinning new work; VAROVÁNÍ/INFO stay exit 0.
$script:Findings = @()
function Add-Finding([string] $Code, [string] $Severity, [string] $Message) {
    $script:Findings += [pscustomobject]@{ code = $Code; severity = $Severity; message = $Message }
    if ($Severity -eq 'CHYBA') { $script:ExitCode = 2 }
}

# --- one traversal: commits above the base that touched MB proposal paths ---
$since = (Get-Date).AddDays(-$SinceDays).ToString('yyyy-MM-dd')
$log = Invoke-RepoGit @(
    'log', '--remotes=origin', '--not', $BaseRef, "--since=$since",
    '--name-only', '--format=%x01%H%x09%cI%x09%an', '--',
    ':(glob)**/memory-bank/proposals/next/*.md',
    ':(glob)**/memory-bank/proposals/active/*.md',
    ':(glob)**/memory-bank/proposals/completed/*.md'
)
Stop-OnGitFailure 'log --remotes=origin --not <BaseRef>'

# Records are separated by \x01; the header line is SHA \t ISO date \t author,
# every following non-empty line is a path touched by that commit.
$commits = @()
$cur = $null
foreach ($ln in ($log -split "`n")) {
    $ln = $ln.TrimEnd("`r")
    if ($ln.StartsWith([char]1)) {
        $parts = $ln.Substring(1) -split "`t"
        $cur = [pscustomobject]@{ Sha = $parts[0]; Date = $parts[1]; Author = $parts[2]; Paths = @() }
        $commits += $cur
        continue
    }
    if (-not $ln -or -not $cur) { continue }
    if ($ln -match '/tests/fixtures/') { continue }      # never index own test data
    $cur.Paths += ($ln -replace '\\', '/')
}

# --- which branches carry it, and does it still exist on their tip? --------
# $commits is newest-first (git log default order). For each commit we resolve
# the remote branches that contain it, then for each (branch, path) pair we
# keep only the FIRST (= newest) hit — this also naturally handles the case
# where the same path was committed independently on two divergent branches
# (each commit is only "--contains"-reachable from its own branch, so both
# surface as separate entries instead of one clobbering the other).
$entries = @()
$seen = @{}   # "branch|path" -> $true once resolved (hit or miss)

foreach ($commit in $commits) {
    if (@($commit.Paths).Count -eq 0) { continue }
    $branchLines = Invoke-RepoGit @('branch', '-r', '--contains', $commit.Sha)
    Stop-OnGitFailure "branch -r --contains $($commit.Sha)"
    $branches = @($branchLines | ForEach-Object {
        $b = $_.Trim()
        if ($b -match '\s->\s') { return }   # skip "origin/HEAD -> origin/develop"
        $b
    } | Where-Object { $_ })
    if ($BranchGlob) { $branches = @($branches | Where-Object { $_ -like $BranchGlob }) }
    if (@($branches).Count -eq 0) { continue }

    foreach ($branch in $branches) {
        foreach ($path in $commit.Paths) {
            $key = "$branch|$path"
            if ($seen.ContainsKey($key)) { continue }
            $seen[$key] = $true

            # PROBE, not a traversal/data call: non-zero here is the ANSWER
            # "this path is not present at that branch's tip" (deleted/moved
            # since), not a git failure — do NOT route through
            # Stop-OnGitFailure, it would turn a legitimate miss into an abort.
            Invoke-RepoGit @('cat-file', '-e', "${branch}:${path}") | Out-Null
            if ($LASTEXITCODE -ne 0) { continue }   # deleted/moved since — nothing to index

            $content = Invoke-RepoGit @('show', "${branch}:${path}")
            Stop-OnGitFailure "show ${branch}:${path}"
            $docJira = Get-JiraHeader $content

            $entries += [pscustomobject]@{
                slug   = Get-Slug $path
                jira   = $docJira
                phase  = Get-Phase $path
                path   = $path
                branch = $branch
                commit = $commit.Sha
                date   = $commit.Date
                author = $commit.Author
            }
        }
    }
}

# --- pseudo-branch 'local': working tree, phases next/active only ----------
# Candidate paths come from git in ONE call instead of a recursive directory
# walk. This script sits on the hot path of Target-MB discovery, mb-state and
# every elaboration bootstrap, and the target monorepo is extremely large: a
# full `Get-ChildItem -Recurse` over it (excluding only .git) is slow enough
# that agents would quietly stop running the index, and every guarantee built
# on top of it would evaporate with it.
# `--cached` = tracked files, `--others --exclude-standard` = untracked ones
# that are not gitignored, so an uncommitted design document is still indexed
# exactly as the directory walk indexed it. The ONE deliberate difference: a
# gitignored MB document is no longer indexed — nobody could pull it across
# branches anyway, which is what this index is for.
$localPaths = Invoke-RepoGit @(
    'ls-files', '--cached', '--others', '--exclude-standard', '--',
    ':(glob)**/memory-bank/proposals/next/*.md',
    ':(glob)**/memory-bank/proposals/active/*.md'
)
Stop-OnGitFailure 'ls-files (local working tree)'

$seenLocal = @{}
foreach ($rel in $localPaths) {
    $rel = ($rel -replace '\\', '/').Trim()
    if (-not $rel) { continue }
    if ($seenLocal.ContainsKey($rel)) { continue }   # --cached and --others cannot overlap, but be explicit
    $seenLocal[$rel] = $true
    if (Test-FixturePath $rel) { continue }

    # 'local' means the WORKING TREE: a tracked file deleted on disk is not
    # local work in flight, so it must not enter the index as one.
    $full = Join-Path $RepoPath $rel
    if (-not (Test-Path -LiteralPath $full)) { continue }

    $lines = Get-Content -LiteralPath $full -ErrorAction SilentlyContinue
    $docJira = Get-JiraHeader $lines

    $hist = Invoke-RepoGit @('log', '-1', '--format=%H%x09%cI%x09%an', 'HEAD', '--', $rel)
    Stop-OnGitFailure "log -1 HEAD -- $rel"
    if ($hist) {
        $p = ($hist | Select-Object -First 1) -split "`t"
        $sha = $p[0]; $date = $p[1]; $author = $p[2]
    } else {
        $sha = ''; $date = (Get-Date).ToString('yyyy-MM-ddTHH:mm:sszzz'); $author = ''
    }

    $entries += [pscustomobject]@{
        slug   = Get-Slug $rel
        jira   = $docJira
        phase  = Get-Phase $rel
        path   = $rel
        branch = 'local'
        commit = $sha
        date   = $date
        author = $author
    }
}

# --- pseudo-branch 'base': BaseRef content, all three phases ---------------
# Cheap: base content is normally visible anyway, so one snapshot per file
# (BaseRef's own tip commit) is enough — no per-file history walk needed.
$baseSha = (Invoke-RepoGit @('rev-parse', $BaseRef) | Select-Object -First 1)
Stop-OnGitFailure "rev-parse $BaseRef"
$baseMeta = (Invoke-RepoGit @('show', '-s', '--format=%cI%x09%an', $BaseRef) | Select-Object -First 1)
Stop-OnGitFailure "show -s $BaseRef"
$baseParts = @($baseMeta -split "`t")
$baseDate = if ($baseParts.Count -ge 1) { $baseParts[0] } else { '' }
$baseAuthor = if ($baseParts.Count -ge 2) { $baseParts[1] } else { '' }

$baseTree = Invoke-RepoGit @('ls-tree', '-r', '--name-only', $BaseRef)
Stop-OnGitFailure "ls-tree -r $BaseRef"
foreach ($path in $baseTree) {
    $path = ($path -replace '\\', '/')
    if ($path -notmatch '(^|/)memory-bank/proposals/(next|active|completed)/[^/]+\.md$') { continue }
    if (Test-FixturePath $path) { continue }

    $content = Invoke-RepoGit @('show', "${BaseRef}:${path}")
    Stop-OnGitFailure "show ${BaseRef}:${path}"
    $docJira = Get-JiraHeader $content

    $entries += [pscustomobject]@{
        slug   = Get-Slug $path
        jira   = $docJira
        phase  = Get-Phase $path
        path   = $path
        branch = 'base'
        commit = $baseSha
        date   = $baseDate
        author = $baseAuthor
    }
}

# --- findings -----------------------------------------------------------------
# KOLIZE AKTIVNÍ PRÁCE (CHYBA) vs. CIZÍ AKTIVNÍ PRÁCE (INFO) are two sides of
# the same comparison: 'active' work of MINE against foreign-branch 'active'
# work. "Mine" has two possible sources and BOTH must be honoured:
#   (a) a document already in my working tree (the local×foreign pass), and
#   (b) DECLARED INTENT via -Jira/-Slug (the pass after it).
# (b) exists because the check that matters most runs when (a) is still empty:
# Target-MB discovery happens during brainstorming item 1, BEFORE the design
# document is written, so a purely local×foreign comparison has nothing to
# compare and a colleague's active work on the very same ticket degrades into
# "normal parallel work" (INFO, exit 0) and both actors proceed. With the
# ticket declared — step 7 of the contract's discovery asks for it — the same
# situation is the fail-closed STOP it was always meant to be.
# A foreign entry that matches by slug OR by non-empty jira is the SAME work
# item in flight on two branches (a real collision); every other foreign
# 'active' entry is just parallel work on something else and is reported for
# awareness only, never fails the run. The actor's OWN remote ref
# ($script:OwnRemoteRef — their own branch's upstream, already-pushed copy of
# their own work) is excluded from "foreign" entirely: nothing about my own
# work, pushed or not, may ever be reported as a collision OR as someone
# else's parallel work — declared intent included.
$localActive = @($entries | Where-Object { $_.branch -eq 'local' -and $_.phase -eq 'active' })
$foreignActive = @($entries | Where-Object {
    $_.phase -eq 'active' -and $_.branch -ne 'local' -and $_.branch -ne 'base' -and
    $_.branch -ne $script:OwnRemoteRef
})

$collided = @{}   # "branch|path" -> $true once reported as a collision
foreach ($le in $localActive) {
    foreach ($fe in $foreignActive) {
        $sameSlug = ($le.slug -eq $fe.slug)
        $sameJira = ([bool]$le.jira -and [bool]$fe.jira -and $le.jira -eq $fe.jira)
        if (-not ($sameSlug -or $sameJira)) { continue }

        $key = "$($fe.branch)|$($fe.path)"
        $collided[$key] = $true
        $dateOnly = if ($fe.date) { $fe.date.Substring(0, [Math]::Min(10, $fe.date.Length)) } else { '' }
        # Minor fix: when the match was on slug only and the local entry has
        # no jira, don't render an empty "()" — omit the parenthetical instead.
        $jiraPart = if ($le.jira) { " ($($le.jira))" } else { '' }
        Add-Finding 'KOLIZE AKTIVNÍ PRÁCE' 'CHYBA' `
            "$($le.slug)$jiraPart je aktivní i na $($fe.branch) ($dateOnly, $($fe.author))"
    }
}

# Declared intent (-Jira / -Slug): the SAME comparison against work that does
# not exist locally yet. Runs after the local×foreign pass and skips whatever
# that pass already reported, so a run with both a local document and a
# declared ticket reports each foreign branch once.
$declared = if ($Jira -and $Slug) { "$Slug ($Jira)" } elseif ($Jira) { $Jira } elseif ($Slug) { $Slug } else { '' }
if ($declared) {
    foreach ($fe in $foreignActive) {
        $sameJira = ([bool]$Jira -and [bool]$fe.jira -and $fe.jira -eq $Jira)
        $sameSlug = ([bool]$Slug -and $fe.slug -eq $Slug)
        if (-not ($sameSlug -or $sameJira)) { continue }

        $key = "$($fe.branch)|$($fe.path)"
        if ($collided.ContainsKey($key)) { continue }
        $collided[$key] = $true
        $dateOnly = if ($fe.date) { $fe.date.Substring(0, [Math]::Min(10, $fe.date.Length)) } else { '' }
        Add-Finding 'KOLIZE AKTIVNÍ PRÁCE' 'CHYBA' `
            "zamýšlená práce $declared už běží jako $($fe.slug) na $($fe.branch) ($dateOnly, $($fe.author))"
    }
}

foreach ($fe in $foreignActive) {
    $key = "$($fe.branch)|$($fe.path)"
    if ($collided.ContainsKey($key)) { continue }   # already reported as a collision above
    $jiraCell = if ($fe.jira) { $fe.jira } else { '(žádný tiket)' }
    Add-Finding 'CIZÍ AKTIVNÍ PRÁCE' 'INFO' "$($fe.slug) ($jiraCell) je aktivní na $($fe.branch)"
}

# DRAFT NA VÍCE VĚTVÍCH (VAROVÁNÍ) – the same queued (phase 'next') slug shows
# up with 2+ distinct ACTORS behind it: either a genuine duplicate draft or a
# rebase/fork the author forgot to clean up. 'base' is the shared baseline,
# never an actor — any file that already exists unmodified in BaseRef's own
# proposals/next/ always also shows up in the working tree of every branch
# descended from it, so it must never count as a peer/duplicate source.
# 'local' and the actor's own remote ref are the SAME actor (one person, one
# piece of work, possibly also pushed) and collapse into a single key.
$nextBySlug = @($entries | Where-Object { $_.phase -eq 'next' -and $_.branch -ne 'base' } | Group-Object slug)
foreach ($g in $nextBySlug) {
    $actors = @($g.Group | ForEach-Object {
        if ($_.branch -eq 'local' -or $_.branch -eq $script:OwnRemoteRef) { 'ME' } else { $_.branch }
    } | Select-Object -Unique)
    if (@($actors).Count -lt 2) { continue }
    $branches = @($g.Group | Select-Object -ExpandProperty branch -Unique)
    Add-Finding 'DRAFT NA VÍCE VĚTVÍCH' 'VAROVÁNÍ' `
        "$($g.Name) je ve frontě (next) na více větvích: $($branches -join ', ')"
}

# FRONTA I DOKONČENO (VAROVÁNÍ) – the same slug is queued (next) somewhere and
# already completed elsewhere: a resurrected/duplicated queue entry for work
# that already shipped. This is the reason 'completed' entries are indexed at
# all even though the table never prints them.
$bySlug = @($entries | Group-Object slug)
foreach ($g in $bySlug) {
    $phases = @($g.Group | Select-Object -ExpandProperty phase -Unique)
    if (-not (($phases -contains 'next') -and ($phases -contains 'completed'))) { continue }
    Add-Finding 'FRONTA I DOKONČENO' 'VAROVÁNÍ' `
        "$($g.Name) je zároveň ve frontě (next) i dokončený (completed)"
}

# --- output -------------------------------------------------------------------
$printable = @($entries | Where-Object { $_.phase -in @('next', 'active') } |
    Sort-Object slug, branch)

Write-Output "📇 Index dokumentů (báze $BaseRef, posledních $SinceDays dní)"
if ($declared) { Write-Output "Kontrola kolize pro zamýšlenou práci: $declared" }
Write-Output ''
Write-Output '| Slug | Tiket | Fáze | Větev | Poslední commit | Autor |'
Write-Output '|---|---|---|---|---|---|'
foreach ($e in $printable) {
    $shortSha = if ($e.commit) { $e.commit.Substring(0, [Math]::Min(7, $e.commit.Length)) } else { '(lokální)' }
    $jiraCell = if ($e.jira) { $e.jira } else { '(žádný tiket)' }
    Write-Output "| $($e.slug) | $jiraCell | $($e.phase) | $($e.branch) | $shortSha | $($e.author) |"
}
if (@($printable).Count -eq 0) { Write-Output '' ; Write-Output '_(žádné položky ve fázích next/active v okně -SinceDays)_' }

Write-Output ''
Write-Output 'Nálezy:'
if (@($script:Findings).Count -eq 0) {
    Write-Output '_(žádné nálezy)_'
} else {
    foreach ($f in $script:Findings) {
        Write-Output "$($f.severity)  $($f.code)  $($f.message)"
    }
}

if ($Json) {
    $out = [pscustomobject]@{
        base      = $BaseRef
        generated = (Get-Date).ToString('yyyy-MM-ddTHH:mm:sszzz')
        entries   = $entries
        findings  = $script:Findings
    }
    $out | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $Json -Encoding UTF8
}

exit $script:ExitCode
