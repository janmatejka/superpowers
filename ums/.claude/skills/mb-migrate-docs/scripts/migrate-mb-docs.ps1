#Requires -Version 7
<#
.SYNOPSIS
Mechanical migration of Memory Bank documents to the current document set.

.DESCRIPTION
Merges product.md into brief.md, renames tasks.md to playbook.md and rewrites
relative links. Moves text only — never authors a sentence. Idempotent: an MB
already in the current shape is skipped. Stages its changes (git add/mv/rm) but
never commits.

.PARAMETER RepoPath
Repository root. Defaults to the toplevel of the current directory.

.PARAMETER Path
Optional repo-relative subtree to limit the scan to.

.PARAMETER Apply
Perform the changes. Without it the script only reports the plan.

.PARAMETER Json
Optional path to also write the result as JSON.

.OUTPUTS
Czech table + findings. Exit: 0 = OK, 1 = input/script failure, 2 = blocking
conflict.
#>
[CmdletBinding()]
param(
    [string] $RepoPath = '',
    [string] $Path = '',
    [switch] $Apply,
    [string] $Json = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
$script:ExitCode = 0

# --- repo resolution ---------------------------------------------------------
# NB: $LASTEXITCODE must only be inspected right after a native call in the
# SAME branch — under Set-StrictMode, reading it before any native command has
# run in this session throws ("cannot be retrieved because it has not been
# set"). The -RepoPath given branch below never runs "& git rev-parse", so it
# must never touch $LASTEXITCODE either; every other native call in this
# script goes through Invoke-RepoGit, which captures $LASTEXITCODE inside the
# same function call that ran it, so nothing downstream ever reads a stale or
# unset value. Same trap and same fix as doc-index.ps1.
if (-not $RepoPath) {
    $RepoPath = (& git rev-parse --show-toplevel)
    if ($LASTEXITCODE -ne 0 -or -not $RepoPath) {
        Write-Error 'Git repozitář nenalezen. Memory Bank vyžaduje git.'; exit 1
    }
} elseif (-not (Test-Path -LiteralPath $RepoPath)) {
    Write-Error "Cesta k repozitáři neexistuje: $RepoPath"; exit 1
}

# Wrapper always captures $LASTEXITCODE immediately inside this function, right
# after the native call that produced it — callers get it back on the returned
# object instead of touching the global $LASTEXITCODE themselves.
function Invoke-RepoGit([string[]] $GitArgs) {
    $out = & git -C $RepoPath @GitArgs 2>&1
    return [pscustomobject]@{ Out = $out; Code = $LASTEXITCODE }
}

function Get-RelPath([string] $AbsPath) {
    $rel = [IO.Path]::GetRelativePath($RepoPath, $AbsPath)
    return ($rel -replace '\\', '/')
}

function Invoke-RepoGitMutation([string[]] $GitArgs, [string] $What) {
    $r = Invoke-RepoGit $GitArgs
    if ($r.Code -ne 0) {
        Write-Error "Selhání příkazu git ($What), exit kód $($r.Code): $($r.Out -join ' ')"
        exit 1
    }
}

# --- fail-closed: -Apply over a dirty working tree is refused ---------------
# Staging is the snapshot the verifier (Task 3) diffs against, and a plain
# "git checkout --" is how a caller restores if the migration needs to be
# undone. Neither guarantee holds if the tree already carried uncommitted
# changes before this script touched anything, so this check runs BEFORE any
# enumeration or mutation, in both branches (script failure, not a finding).
if ($Apply) {
    $statusResult = Invoke-RepoGit @('status', '--porcelain')
    if ($statusResult.Code -ne 0) {
        Write-Error "Selhání příkazu git (status --porcelain), exit kód $($statusResult.Code): stav pracovního stromu nelze zjistit."
        exit 1
    }
    if (@($statusResult.Out | Where-Object { $_ -and $_.Trim() -ne '' }).Count -gt 0) {
        Write-Error 'Pracovní strom není čistý (git status --porcelain vrátil změny). -Apply nad špinavým pracovním stromem se neprovádí: staging slouží jako snímek pro verifikátor a "git checkout --" jako obnova, ani jedno nefunguje spolehlivě přes cizí necommitnuté změny. Vyčistěte pracovní strom (commit/stash) a zkuste to znovu.'
        exit 1
    }
}

# --- findings: collision/attention candidates, never silent fixes -----------
# Severity CHYBA raises the exit code to 2 — the fail-closed STOP for a
# blocking conflict; VAROVÁNÍ/INFO stay exit 0 (or whatever a CHYBA elsewhere
# already set it to).
$script:Findings = @()
function Add-Finding([string] $Code, [string] $Severity, [string] $Message) {
    $script:Findings += [pscustomobject]@{ code = $Code; severity = $Severity; message = $Message }
    if ($Severity -eq 'CHYBA') { $script:ExitCode = 2 }
}

# --- text-moving primitives: the two functions that carry correctness -------

function Get-ProductBody([string[]] $Lines) {
    # Drop leading blanks and the leading H1, then demote every heading one
    # level. Lines inside fenced blocks are never touched.
    # Returns @{ Lines = <string[]>; UnterminatedFence = <bool> } — an odd
    # number of fence markers leaves $inFence true at the end of the file,
    # meaning everything after the last fence was silently treated as "inside
    # a fence" (or vice versa) and never demoted. The caller surfaces that as
    # a finding instead of guessing/repairing it.
    $i = 0
    while ($i -lt $Lines.Count -and $Lines[$i].Trim() -eq '') { $i++ }
    if ($i -lt $Lines.Count -and $Lines[$i] -match '^#\s') { $i++ }
    while ($i -lt $Lines.Count -and $Lines[$i].Trim() -eq '') { $i++ }

    $out = [System.Collections.Generic.List[string]]::new()
    $inFence = $false
    for (; $i -lt $Lines.Count; $i++) {
        $line = $Lines[$i]
        if ($line -match '^\s*```') { $inFence = -not $inFence; $out.Add($line); continue }
        if (-not $inFence -and $line -match '^(#{1,5})(\s.*)$') {
            $out.Add('#' + $Matches[1] + $Matches[2])
        } else {
            $out.Add($line)
        }
    }
    return @{ Lines = $out.ToArray(); UnterminatedFence = $inFence }
}

function Update-Links([string] $MdFile, [hashtable] $Map) {
    # $Map: 'product.md' -> 'brief.md', 'tasks.md' -> 'playbook.md'
    # Returns $true when the file was rewritten.
    $dir = Split-Path -Parent $MdFile
    $text = Get-Content -LiteralPath $MdFile -Raw
    if ($null -eq $text) { return $false }
    $original = $text
    foreach ($old in $Map.Keys) {
        $new = $Map[$old]
        # Group 1 = prefix before the filename, Group 2 = an OPTIONAL "#anchor"
        # fragment. Section anchors (e.g. "product.md#pro-koho") are ordinary
        # in these documents — without capturing the fragment separately, the
        # whole link failed to match at all (the old pattern required ")"
        # immediately after the filename) and survived untouched, pointing at
        # a file the merge/rename step just deleted.
        $pattern = '\]\(([^)#]*?)' + [regex]::Escape($old) + '((?:#[^)]*)?)\)'
        $text = [regex]::Replace($text, $pattern, {
            param($m)
            $prefix = $m.Groups[1].Value
            $fragment = $m.Groups[2].Value
            $oldTarget = Join-Path $dir ($prefix + $old)
            $newTarget = Join-Path $dir ($prefix + $new)
            # Rewrite ONLY when the old target is gone and the new one exists.
            # That is what keeps links into a not-yet-migrated MB untouched.
            # The existence check is against the FILENAME only — the fragment
            # is never part of a path and must never enter Test-Path.
            if ((-not (Test-Path -LiteralPath $oldTarget)) -and (Test-Path -LiteralPath $newTarget)) {
                return '](' + $prefix + $new + $fragment + ')'
            }
            return $m.Value
        })
    }
    if ($text -eq $original) { return $false }
    [IO.File]::WriteAllText($MdFile, $text, [Text.UTF8Encoding]::new($false))
    return $true
}

# Computes the merged brief.md content WITHOUT writing anything: brief
# content, two blank lines, the "Produktový pohled" heading, one blank line,
# then the demoted product body. Split from the write step so the same
# computation can run in plan mode too (needed for -Json to describe the plan
# and for the "unterminated fence" finding to surface before -Apply, not just
# after).
# Returns @{ Text = <string>; UnterminatedFence = <bool> }.
function Get-MergedBriefContent([string] $BriefFile, [string] $ProductFile) {
    $briefLines = @(Get-Content -LiteralPath $BriefFile)
    $productLines = @(Get-Content -LiteralPath $ProductFile)
    $productResult = Get-ProductBody $productLines

    $merged = [System.Collections.Generic.List[string]]::new()
    foreach ($ln in $briefLines) { $merged.Add($ln) }
    $merged.Add('')
    $merged.Add('')
    $merged.Add('## Produktový pohled')
    $merged.Add('')
    foreach ($ln in $productResult.Lines) { $merged.Add($ln) }

    $text = ($merged -join "`n") + "`n"
    return @{ Text = $text; UnterminatedFence = $productResult.UnterminatedFence }
}

# Writes UTF-8 without BOM — the same rule Update-Links follows above.
function Write-MergedBrief([string] $BriefFile, [string] $Text) {
    [IO.File]::WriteAllText($BriefFile, $Text, [Text.UTF8Encoding]::new($false))
}

# --- MB enumeration -----------------------------------------------------------
# One call covers tracked AND untracked-but-not-ignored files, exactly like
# doc-index.ps1's own "local" pass — a Memory Bank someone is mid-way through
# creating, not yet committed, must still be found. Non-zero exit here is a
# genuine git-level failure, not "nothing found": exit 1 immediately.
$lsResult = Invoke-RepoGit @('ls-files', '--cached', '--others', '--exclude-standard')
if ($lsResult.Code -ne 0) {
    Write-Error "Selhání příkazu git (ls-files), exit kód $($lsResult.Code): soubory repozitáře nelze vypsat."
    exit 1
}

$allPaths = @($lsResult.Out | ForEach-Object { ($_ -replace '\\', '/').Trim() } | Where-Object { $_ })

# NB: both patterns below are anchored with (^|/) — NOT a bare '/memory-bank/'
# or '/tests/fixtures/'. Without the alternation, a root-level path such as
# this very repo's own "memory-bank/product.md" (no leading slash before the
# segment) fails to match at all, silently dropping the whole MB from the
# scan. Confirmed against this repository itself: the un-anchored pattern
# made the script report "no Memory Bank roots" and exit 0 even though
# memory-bank/product.md and memory-bank/tasks.md are tracked at the repo
# root.
function Test-FixturePath([string] $RelPath) { return ($RelPath -match '(^|/)tests/fixtures/') }

$normPath = ''
if ($Path) { $normPath = ($Path.Trim('/', '\') -replace '\\', '/') }

$mbPaths = @($allPaths | Where-Object {
    $_ -match '(^|/)memory-bank/' -and
    -not (Test-FixturePath $_) -and
    (-not $normPath -or $_ -eq $normPath -or $_.StartsWith("$normPath/"))
})

function Get-MbRoot([string] $RelPath) {
    if ($RelPath -match '^((?:.*/)?)memory-bank/') { return ($Matches[1] + 'memory-bank') }
    return $null
}

$mbRoots = @($mbPaths | ForEach-Object { Get-MbRoot $_ } | Where-Object { $_ } | Select-Object -Unique | Sort-Object)

# --- per-MB plan and (when -Apply) mutation ----------------------------------
# NB: 'merged'/'renamed'/'notes' and the emitted findings are computed the
# SAME way in both modes — only the actual git/file mutation is gated by
# $Apply. That is what makes plan mode (the user's consent surface, and what
# -Json without -Apply describes) tell the truth about what WOULD happen,
# instead of reporting an empty/all-false plan and only becoming honest after
# the tree has already been changed.
$linkMap = @{ 'product.md' = 'brief.md'; 'tasks.md' = 'playbook.md' }
$mbsResult = @()
$skippedRoots = [System.Collections.Generic.HashSet[string]]::new()

foreach ($root in $mbRoots) {
    $absRoot = Join-Path $RepoPath $root
    $briefPath = Join-Path $absRoot 'brief.md'
    $productPath = Join-Path $absRoot 'product.md'
    $tasksPath = Join-Path $absRoot 'tasks.md'
    $playbookPath = Join-Path $absRoot 'playbook.md'

    $hasBrief = Test-Path -LiteralPath $briefPath
    $hasProduct = Test-Path -LiteralPath $productPath
    $hasTasks = Test-Path -LiteralPath $tasksPath
    $hasPlaybook = Test-Path -LiteralPath $playbookPath

    $notes = [System.Collections.Generic.List[string]]::new()
    $mergeResult = $null

    if ($hasTasks -and $hasPlaybook) {
        # Blocking conflict: this MB has both the legacy and the current name.
        # The whole MB is skipped — nothing about it is touched this run, and
        # its files are excluded below from the cross-MB link-rewrite pass too
        # (recorded in $skippedRoots), not just from its own merge/rename.
        Add-Finding 'KONFLIKT PLAYBOOKU' 'CHYBA' "${root}: existují tasks.md i playbook.md současně, MB byla přeskočena."
        $action = 'přeskočeno (konflikt)'
        $notes.Add('existují tasks.md i playbook.md; nutná ruční kontrola.')
        $merged = $false
        $renamed = $false
        [void] $skippedRoots.Add($root)
    } else {
        $needsProduct = $hasProduct
        $needsTasks = ($hasTasks -and -not $hasPlaybook)
        $merged = ($needsProduct -and $hasBrief)
        $renamed = $needsTasks

        $parts = [System.Collections.Generic.List[string]]::new()
        if ($needsProduct) {
            if ($hasBrief) {
                $mergeResult = Get-MergedBriefContent $briefPath $productPath
                if ($mergeResult.UnterminatedFence) {
                    Add-Finding 'NEUZAVŘENÝ BLOK' 'VAROVÁNÍ' ("${root}: product.md obsahuje neuzavřený ohraničený blok (počet značek s trojicí zpětných apostrofů je lichý); posun nadpisů za tímto místem je nespolehlivý, zkontrolujte ručně.")
                }
                $parts.Add('sloučit product.md')
                $notes.Add('product.md se slučuje do brief.md.')
            } else {
                # No brief.md to merge into: a plain rename, not a merge — the
                # file's own H1 still says "Product", a human needs to look at
                # it. This finding is emitted in BOTH modes (like KONFLIKT
                # PLAYBOOKU already was) because the plan is what a caller
                # reads before deciding to run -Apply at all.
                $parts.Add('přejmenovat product.md')
                $notes.Add('product.md se přejmenovává na brief.md (chybí originální brief.md, nadpis zůstane beze změny).')
                $warnMsg = "${root}" + ': product.md je bez brief.md - nadpis souboru (H1) zůstane "Product" i po přejmenování na brief.md; zkontrolujte ručně.'
                Add-Finding 'PRODUCT BEZ BRIEFU' 'VAROVÁNÍ' $warnMsg
            }
        }
        if ($needsTasks) {
            $parts.Add('přejmenovat tasks.md')
            $notes.Add('tasks.md se přejmenovává na playbook.md.')
        }
        $action = if ($parts.Count -gt 0) { $parts -join ' + ' } else { 'beze změny (hotovo)' }

        if ($Apply) {
            if ($needsProduct) {
                if ($hasBrief) {
                    Write-MergedBrief $briefPath $mergeResult.Text
                    Invoke-RepoGitMutation @('add', '--', (Get-RelPath $briefPath)) "add $root/brief.md"
                    Invoke-RepoGitMutation @('rm', '--', (Get-RelPath $productPath)) "rm $root/product.md"
                } else {
                    Invoke-RepoGitMutation @('mv', (Get-RelPath $productPath), (Get-RelPath $briefPath)) "mv $root/product.md -> brief.md"
                }
            }
            if ($needsTasks) {
                Invoke-RepoGitMutation @('mv', (Get-RelPath $tasksPath), (Get-RelPath $playbookPath)) "mv $root/tasks.md -> playbook.md"
            }
        }
    }

    # NB: 'action' is carried on this object only for the table below — the
    # JSON schema is pinned to exactly { path, merged, renamed, notes }, so the
    # JSON writer further down selects those four properties explicitly.
    $mbsResult += [pscustomobject]@{
        path    = $root
        merged  = $merged
        renamed = $renamed
        notes   = ($notes -join ' ')
        action  = $action
    }
}

# --- link rewrite: runs once, after ALL moves, over every *.md under every ---
# found memory-bank root — links can point across MBs, not just within one.
# Only performed when actually mutating; plan mode leaves the tree untouched.
# Roots in $skippedRoots (blocking conflict) are excluded ENTIRELY from this
# pass, not merely left alone by Update-Links' own existence guard: that
# guard asks "is the old target gone and the new one there", which is only a
# proxy for "did this MB migrate". A skipped MB can still fool the proxy —
# e.g. a document inside it links to a "product.md" that never existed there
# in the first place, while its own brief.md already does, satisfying the
# guard's condition by accident even though nothing about that MB was ever
# touched. Excluding the whole root up front removes that failure mode
# instead of relying on the guard to catch every such case.
if ($Apply) {
    $mdFiles = @()
    foreach ($root in $mbRoots) {
        if ($skippedRoots.Contains($root)) { continue }
        $absRoot = Join-Path $RepoPath $root
        if (Test-Path -LiteralPath $absRoot) {
            $mdFiles += @(Get-ChildItem -LiteralPath $absRoot -Recurse -Filter '*.md' -File | Select-Object -ExpandProperty FullName)
        }
    }
    foreach ($mdFile in ($mdFiles | Select-Object -Unique)) {
        if (Update-Links $mdFile $linkMap) {
            Invoke-RepoGitMutation @('add', '--', (Get-RelPath $mdFile)) "add $(Get-RelPath $mdFile)"
        }
    }
}

# --- output -------------------------------------------------------------------
Write-Output '🔀 Migrace dokumentů Memory Bank'
Write-Output ''
Write-Output '| MB | Akce | Poznámka |'
Write-Output '|---|---|---|'
foreach ($mb in $mbsResult) {
    Write-Output "| $($mb.path) | $($mb.action) | $($mb.notes) |"
}
if (@($mbsResult).Count -eq 0) { Write-Output '' ; Write-Output '_(v repozitáři nejsou žádné Memory Bank kořeny)_' }

Write-Output ''
Write-Output 'Nálezy:'
if (@($script:Findings).Count -eq 0) {
    Write-Output '_(žádné nálezy)_'
} else {
    foreach ($f in $script:Findings) {
        Write-Output "- [$($f.severity)] $($f.code): $($f.message)"
    }
}

if ($Json) {
    $mbsJson = @($mbsResult | Select-Object path, merged, renamed, notes)
    $out = [pscustomobject]@{
        generated = (Get-Date).ToString('yyyy-MM-ddTHH:mm:sszzz')
        repo      = $RepoPath
        mbs       = $mbsJson
        findings  = $script:Findings
    }
    $out | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $Json -Encoding UTF8
}

exit $script:ExitCode
