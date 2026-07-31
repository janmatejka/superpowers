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
# TRAVERSAL/DATA calls below (log, branch -r --contains, show, ls-tree,
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

function Test-FixturePath([string] $Path) { return ($Path -match '/tests/fixtures/') }

function Get-Slug([string] $Path) {
    # Contract pairing rule: strip exactly ONE prefix; '-design' only after 'proposal_'.
    $stem = [IO.Path]::GetFileNameWithoutExtension($Path)
    if ($stem -match '^proposal_(.+)$') { return ($Matches[1] -replace '-design$', '') }
    if ($stem -match '^(design_|plan_)(.+)$') { return $Matches[2] }
    return $stem
}

function Get-Phase([string] $Path) { return (Split-Path (Split-Path $Path -Parent) -Leaf) }

function Get-JiraHeader([string[]] $Lines) {
    foreach ($ln in $Lines) {
        if ($ln -match '^-\s*\*\*Jira:\*\*\s*(.+?)\s*$') { return $Matches[1] }
    }
    return ''
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
            $jira = Get-JiraHeader $content

            $entries += [pscustomobject]@{
                slug   = Get-Slug $path
                jira   = $jira
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
$mbRoots = @(Get-ChildItem -LiteralPath $RepoPath -Recurse -Directory -Filter 'memory-bank' -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' })

foreach ($mbRoot in $mbRoots) {
    foreach ($phase in @('next', 'active')) {
        $dir = Join-Path $mbRoot.FullName "proposals\$phase"
        if (-not (Test-Path -LiteralPath $dir)) { continue }
        $files = @(Get-ChildItem -LiteralPath $dir -Filter '*.md' -File -ErrorAction SilentlyContinue)
        foreach ($f in $files) {
            $rel = ($f.FullName.Substring($RepoPath.Length).TrimStart('\', '/')) -replace '\\', '/'
            if (Test-FixturePath $rel) { continue }

            $lines = Get-Content -LiteralPath $f.FullName -ErrorAction SilentlyContinue
            $jira = Get-JiraHeader $lines

            $hist = Invoke-RepoGit @('log', '-1', '--format=%H%x09%cI%x09%an', 'HEAD', '--', $rel)
            if ($hist) {
                $p = ($hist | Select-Object -First 1) -split "`t"
                $sha = $p[0]; $date = $p[1]; $author = $p[2]
            } else {
                $sha = ''; $date = (Get-Date).ToString('yyyy-MM-ddTHH:mm:sszzz'); $author = ''
            }

            $entries += [pscustomobject]@{
                slug   = Get-Slug $rel
                jira   = $jira
                phase  = Get-Phase $rel
                path   = $rel
                branch = 'local'
                commit = $sha
                date   = $date
                author = $author
            }
        }
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
    $jira = Get-JiraHeader $content

    $entries += [pscustomobject]@{
        slug   = Get-Slug $path
        jira   = $jira
        phase  = Get-Phase $path
        path   = $path
        branch = 'base'
        commit = $baseSha
        date   = $baseDate
        author = $baseAuthor
    }
}

# --- output -------------------------------------------------------------------
$printable = @($entries | Where-Object { $_.phase -in @('next', 'active') } |
    Sort-Object slug, branch)

Write-Output "📇 Index dokumentů (báze $BaseRef, posledních $SinceDays dní)"
Write-Output ''
Write-Output '| Slug | Tiket | Fáze | Větev | Poslední commit | Autor |'
Write-Output '|---|---|---|---|---|---|'
foreach ($e in $printable) {
    $shortSha = if ($e.commit) { $e.commit.Substring(0, [Math]::Min(7, $e.commit.Length)) } else { '(lokální)' }
    $jiraCell = if ($e.jira) { $e.jira } else { '(žádný tiket)' }
    Write-Output "| $($e.slug) | $jiraCell | $($e.phase) | $($e.branch) | $shortSha | $($e.author) |"
}
if (@($printable).Count -eq 0) { Write-Output '' ; Write-Output '_(žádné položky ve fázích next/active v okně -SinceDays)_' }

# Findings (duplicate slugs, collisions, ...) land here in Task 3. Kept as an
# empty array now so the JSON shape is already stable for later consumers.
$findings = @()

if ($Json) {
    $out = [pscustomobject]@{
        base      = $BaseRef
        generated = (Get-Date).ToString('yyyy-MM-ddTHH:mm:sszzz')
        entries   = $entries
        findings  = $findings
    }
    $out | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $Json -Encoding UTF8
}

exit $script:ExitCode
