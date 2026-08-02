#Requires -Version 7
<#
.SYNOPSIS
Audits and consolidates every markdown link inside the monorepo's Memory Banks.

.DESCRIPTION
Walks all *.md files under any directory named 'memory-bank', extracts inline
markdown links outside fenced code blocks, and classifies each one. Without
-Apply nothing is written: the run is a pure audit that reports findings and
exits 2 when any exist, so it can be used as a gate.

Classes:

  anchor-inpage      '[X](#slug)'            -> 'sekce „X“'
  anchor-crossfile   '[X](f.md#slug)'        -> '[f.md](f.md), sekce „Nadpis“'
  anchor-lines       '[X](f.cs#L10-L20)'     -> '[f.cs](f.cs), řádky 10–20'
  anchor-unresolved  fragment matches no heading -> link kept, fragment marked
  retarget           broken path with a determinable successor
  stale-label        text is a bare *.md name that differs from the target
  absolute-path      drive-qualified or root-anchored path -> made relative
  ambiguous          broken path, several equally good successors -> marked
  unresolved         broken path, no determinable successor -> marked

Anchors are rewritten because heading slugs are renderer-specific (see the
contract, "Link Conventions"). Broken paths are repaired through a cascade that
prefers exact evidence over name guessing:

  R1 WRONG DEPTH — re-resolve the same relative path against the Memory Bank
     root, the project root and the repository root. This is the dominant defect
     in proposals/<state>/, which sits two levels below the MB root. Exact, not
     a guess; accepted only when those bases agree on a single existing path.
  R2 SUCCESSOR BY NAME — look the basename up in the tracked-file index and
     score candidates by shared trailing path segments. GATED BY INTENT: if the
     original path pointed INSIDE the document's own project and nothing is
     there, the file was dropped from that project, and pointing the sentence at
     a same-named file in a DIFFERENT project would silently change what it
     claims. Those are marked, never rewritten. Intent is read from the MB root,
     because a doc-relative reading of an MB-relative link lands inside the
     project almost every time.
  R3 otherwise — drop the dead link syntax, keep the text, and append the marker
     WITH the dead path inside it, so the next pass has something to work from.

Applying can reveal second-order findings (a link whose fragment hid an equally
broken path), so -Apply loops until the scan comes back clean.

proposals/completed/ is an immutable archive under the contract, so proposals
are reported but NOT modified unless -IncludeProposals is given.

.PARAMETER RepoPath
Repository root. Defaults to the git root of the current directory.

.PARAMETER Path
Optional subtree to restrict the scan to (repo-relative).

.PARAMETER Json
Optional ledger output path.

.PARAMETER Apply
Write the fixes. Omit for a read-only audit.

.PARAMETER IncludeProposals
Also fix links inside proposals/. Off by default (archive).

.PARAMETER Marker
Inline marker used for links that could not be resolved.

.OUTPUTS
Czech table and findings. Exit: 0 = clean (or applied), 1 = input/script
failure, 2 = findings remain.
#>
[CmdletBinding()]
param(
    [string] $RepoPath,
    [string] $Path,
    [string] $Json,
    [switch] $Apply,
    [switch] $IncludeProposals,
    [string] $Marker = 'ODKAZ K OVĚŘENÍ'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }

# --- MB_ROOT discovery: exactly one step, per the contract ----------------------
if (-not $RepoPath) {
    $RepoPath = & git rev-parse --show-toplevel 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $RepoPath) {
        Write-Error 'Git repository not found. Memory Bank requires git.'; exit 1
    }
}
if (-not (Test-Path -LiteralPath $RepoPath)) { Write-Error "RepoPath '$RepoPath' neexistuje."; exit 1 }
$repoFull = (Resolve-Path -LiteralPath $RepoPath).Path

# --- heading slugs -------------------------------------------------------------
# GitHub-style, because that is the convention the existing anchors in this
# repository were written against. Only ever used to RESOLVE an existing anchor
# to its heading text so the anchor can be removed — never to author one.
# NB: each whitespace character becomes its own dash; collapsing runs would
# mis-resolve every heading containing a stripped symbol ("v1 → v2").
function Get-SlugMap([string[]] $Lines) {
    $map = @{}; $counts = @{}; $inFence = $false
    foreach ($line in $Lines) {
        if ($line -match '^\s*```') { $inFence = -not $inFence; continue }
        if ($inFence) { continue }
        if ($line -notmatch '^(#{1,6})\s+(.*)$') { continue }
        $t = $Matches[2]
        $t = [regex]::Replace($t, '\[([^\]]*)\]\([^)]*\)', '$1')
        $t = ($t -replace '[*_`~]', '').Trim().TrimEnd('#').Trim()
        $slug = $t.ToLowerInvariant()
        $slug = [regex]::Replace($slug, '[^\p{L}\p{N}\s_-]', '')
        $slug = $slug -replace '\s', '-'
        if ($counts.ContainsKey($slug)) { $counts[$slug]++; $slug = "$slug-$($counts[$slug])" } else { $counts[$slug] = 0 }
        if (-not $map.ContainsKey($slug)) { $map[$slug] = $t }
    }
    return $map
}

function Get-SharedSuffix([string] $Broken, [string] $Candidate) {
    $b = @($Broken.Trim('/').Split('/') | Where-Object { $_ -ne '' -and $_ -ne '.' -and $_ -ne '..' })
    $c = @($Candidate.Trim('/').Split('/'))
    $n = 0
    while ($n -lt $b.Count -and $n -lt $c.Count -and $b[$b.Count-1-$n] -eq $c[$c.Count-1-$n]) { $n++ }
    return $n
}

# --- tracked-file index --------------------------------------------------------
# git ls-files, not a directory walk: the target monorepo is very large.
$tracked = & git -C $repoFull ls-files
$byBase = @{}; $dirSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($t in $tracked) {
    $b = $t.Substring($t.LastIndexOf('/') + 1)
    if (-not $byBase.ContainsKey($b)) { $byBase[$b] = [System.Collections.Generic.List[string]]::new() }
    $byBase[$b].Add($t)
    $parts = $t.Split('/'); $acc = ''
    for ($i = 0; $i -lt $parts.Count - 1; $i++) {
        $acc = if ($acc -eq '') { $parts[$i] } else { "$acc/$($parts[$i])" }
        [void]$dirSet.Add($acc)
    }
}
$dirByName = @{}
foreach ($d in $dirSet) {
    $n = $d.Substring($d.LastIndexOf('/') + 1)
    if (-not $dirByName.ContainsKey($n)) { $dirByName[$n] = [System.Collections.Generic.List[string]]::new() }
    $dirByName[$n].Add($d)
}

$excludeRx = '[\\/](\.git|DistOut|node_modules|bin|obj|packages)[\\/]'
$scanRoot = if ($Path) { Join-Path $repoFull $Path } else { $repoFull }
if (-not (Test-Path -LiteralPath $scanRoot)) { Write-Error "Path '$Path' neexistuje."; exit 1 }

$linkRx = [regex]'(?<!\!)\[(?<text>[^\]]*)\]\((?<target>[^)\s]*)(?:\s+"[^"]*")?\)'

function Invoke-Scan {
    $findings = [System.Collections.Generic.List[object]]::new()
    $script:linkTotal = 0; $script:linkExternal = 0
    $slugCache = @{}

    $files = Get-ChildItem -LiteralPath $scanRoot -Recurse -Filter '*.md' -File -EA SilentlyContinue |
        Where-Object { $_.FullName -match '[\\/]memory-bank[\\/]' -and $_.FullName -notmatch $excludeRx }

    foreach ($file in $files) {
        $raw = [IO.File]::ReadAllText($file.FullName)
        # Split keeping each line's own terminator so a rewrite cannot silently
        # normalise CRLF/LF (a whole-file diff for a one-word change).
        $segs = [regex]::Split($raw, '(?<=\n)')
        $dir = $file.DirectoryName
        $rel = [IO.Path]::GetRelativePath($repoFull, $file.FullName).Replace('\', '/')
        $inFence = $false

        for ($i = 0; $i -lt $segs.Count; $i++) {
            $line = $segs[$i].TrimEnd("`r", "`n")
            if ($line -match '^\s*```') { $inFence = -not $inFence; continue }
            if ($inFence) { continue }

            foreach ($m in $linkRx.Matches($line)) {
                $script:linkTotal++
                $text = $m.Groups['text'].Value
                $rawT = $m.Groups['target'].Value.Trim().Trim('<', '>')
                if ($rawT -eq '') { continue }
                if ($rawT -match '^(https?|mailto|ftp|tel):') { $script:linkExternal++; continue }

                $anchor = ''; $lpath = $rawT
                $h = $rawT.IndexOf('#')
                if ($h -ge 0) { $anchor = $rawT.Substring($h + 1); $lpath = $rawT.Substring(0, $h) }

                $rec = [ordered]@{
                    file = $rel; line = $i + 1; area = $(if ($rel -match '/proposals/') { 'proposals' } else { 'stav' })
                    old = "[$text]($rawT)"; new = ''; class = ''; note = ''
                }

                # --- absolute / root-anchored -------------------------------------
                if ($lpath -match '^([A-Za-z]:[\\/]|[\\/])') {
                    $abs = $lpath -replace '/', [IO.Path]::DirectorySeparatorChar
                    if (Test-Path -LiteralPath $abs) {
                        $r = [IO.Path]::GetRelativePath($dir, (Resolve-Path -LiteralPath $abs).Path).Replace('\', '/')
                        if ($lpath.EndsWith('/') -and -not $r.EndsWith('/')) { $r += '/' }
                        $rec.class = 'absolute-path'; $rec.note = 'absolutní cesta → relativní'
                        $rec.new = "[$text]($r)"
                    } else {
                        $rec.class = 'unresolved'; $rec.note = 'absolutní cesta, cíl neexistuje'
                        $rec.new = '`{0}` [{1}: {2}]' -f $text, $Marker, $lpath
                    }
                    $findings.Add([pscustomobject]$rec); continue
                }

                # --- anchors ------------------------------------------------------
                if ($anchor -ne '') {
                    if ($lpath -ne '' -and $anchor -match '^L(?<a>\d+)(?:-L?(?<b>\d+))?$') {
                        # Capture before any further -match: $Matches is global.
                        $la = $Matches['a']; $lb = if ($Matches.ContainsKey('b')) { $Matches['b'] } else { $null }
                        $lbl = if ($text -match '#L\d') { [IO.Path]::GetFileName($lpath) } else { $text }
                        $where = if ($lb) { "řádky $la–$lb" } else { "řádek $la" }
                        $rec.class = 'anchor-lines'
                        $rec.new = '[{0}]({1}), {2}' -f $lbl, $lpath, $where
                        $findings.Add([pscustomobject]$rec); continue
                    }
                    $tf = if ($lpath -eq '') { $file.FullName }
                          else { [IO.Path]::GetFullPath((Join-Path $dir ([Uri]::UnescapeDataString($lpath)))) }
                    $heading = $null
                    if ($tf -like '*.md' -and (Test-Path -LiteralPath $tf -PathType Leaf)) {
                        if (-not $slugCache.ContainsKey($tf)) { $slugCache[$tf] = Get-SlugMap @(Get-Content -LiteralPath $tf) }
                        $sm = $slugCache[$tf]; $k = $anchor.ToLowerInvariant()
                        if ($sm.ContainsKey($k)) { $heading = $sm[$k] }
                    }
                    if ($null -eq $heading) {
                        $rec.class = 'anchor-unresolved'; $rec.note = "kotva '#$anchor' neodpovídá žádnému nadpisu"
                        $rec.new = if ($lpath -eq '') { '{0} [{1}: #{2}]' -f $text, $Marker, $anchor }
                                   else { '[{0}]({1}) [{2}: #{3}]' -f $text, $lpath, $Marker, $anchor }
                    } elseif ($lpath -eq '') {
                        $rec.class = 'anchor-inpage'
                        $rec.new = 'sekce „{0}“' -f $heading
                    } else {
                        $rec.class = 'anchor-crossfile'
                        # Drop label text that only described the anchor — the
                        # section is named in words right after the link now.
                        $label = if ($text.Trim() -eq $heading.Trim() -or $text -match 'kotevní sekce|§|#') {
                                     [IO.Path]::GetFileName($lpath) } else { $text }
                        $rec.new = '[{0}]({1}), sekce „{2}“' -f $label, $lpath, $heading
                    }
                    $findings.Add([pscustomobject]$rec); continue
                }

                # --- plain path ---------------------------------------------------
                $decoded = [Uri]::UnescapeDataString($lpath)
                $resolved = [IO.Path]::GetFullPath((Join-Path $dir $decoded))

                if (Test-Path -LiteralPath $resolved) {
                    $tb = [IO.Path]::GetFileName($decoded)
                    if ($text -match '^[\w.\-]+\.md$' -and $tb -ne '' -and $text -ne $tb) {
                        $rec.class = 'stale-label'; $rec.note = "text '$text' vs. cíl '$tb'"
                        $rec.new = "[$tb]($rawT)"
                        $findings.Add([pscustomobject]$rec)
                    }
                    continue
                }

                $isDir = $decoded.EndsWith('/')
                $mbDir = $dir
                while ($null -ne $mbDir -and [IO.Path]::GetFileName($mbDir) -ne 'memory-bank') { $mbDir = [IO.Path]::GetDirectoryName($mbDir) }
                $projDir = if ($mbDir) { [IO.Path]::GetDirectoryName($mbDir) } else { $null }

                # R1 — wrong depth
                $hits = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
                foreach ($b in @($mbDir, $projDir, $repoFull)) {
                    if (-not $b) { continue }
                    $try = [IO.Path]::GetFullPath((Join-Path $b $decoded))
                    if ($try.StartsWith($repoFull, [StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $try)) { [void]$hits.Add($try) }
                }

                $chosen = $null; $rule = ''
                if ($hits.Count -eq 1) {
                    $chosen = @($hits)[0]; $rule = 'špatná hloubka (../) opravena'
                } else {
                    # R2 — successor by name, gated by intent (see .DESCRIPTION)
                    $intentBase = if ($mbDir) { $mbDir } else { $dir }
                    $intentPath = [IO.Path]::GetFullPath((Join-Path $intentBase $decoded))
                    $intra = $projDir -and $intentPath.StartsWith($projDir + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
                    $b2 = $decoded.TrimEnd('/'); $b2 = $b2.Substring($b2.LastIndexOf('/') + 1)
                    $pool = if ($isDir) { $dirByName } else { $byBase }
                    $cands = @()
                    if (-not $intra -and $b2 -ne '' -and $pool.ContainsKey($b2)) { $cands = @($pool[$b2]) }
                    if ($cands.Count -gt 0) {
                        $scored = $cands | ForEach-Object { [pscustomobject]@{ p = $_; s = (Get-SharedSuffix $decoded $_) } }
                        $best = ($scored | Measure-Object -Property s -Maximum).Maximum
                        $top = @($scored | Where-Object { $_.s -eq $best })
                        if ($top.Count -eq 1 -and $best -ge 2) {
                            $chosen = Join-Path $repoFull ($top[0].p -replace '/', [IO.Path]::DirectorySeparatorChar)
                            $rule = "jednoznačný nástupce (shoda $best segmentů cesty)"
                        }
                    }
                }

                if ($chosen) {
                    $nr = [IO.Path]::GetRelativePath($dir, $chosen).Replace('\', '/')
                    if ($isDir -and -not $nr.EndsWith('/')) { $nr += '/' }
                    $rec.class = 'retarget'
                    $rec.note = "$rule : $decoded -> " + ([IO.Path]::GetRelativePath($repoFull, $chosen).Replace('\', '/'))
                    $rec.new = "[$text]($nr)"
                } else {
                    $rec.class = if ($hits.Count -gt 1) { 'ambiguous' } else { 'unresolved' }
                    $rec.note = if ($hits.Count -gt 1) { 'více možných cílů' } else { "cíl '$decoded' nelze určit" }
                    $rec.new = '`{0}` [{1}: {2}]' -f $text, $Marker, $decoded
                }
                $findings.Add([pscustomobject]$rec)
            }
        }
    }
    return , @($findings)
}

function Invoke-Apply([object[]] $Findings) {
    $applied = 0; $failed = 0
    foreach ($grp in ($Findings | Group-Object file)) {
        $abs = Join-Path $repoFull ($grp.Name -replace '/', [IO.Path]::DirectorySeparatorChar)
        $bytes = [IO.File]::ReadAllBytes($abs)
        $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
        $raw = [IO.File]::ReadAllText($abs)
        $segs = [regex]::Split($raw, '(?<=\n)')
        foreach ($e in ($grp.Group | Sort-Object line -Descending)) {
            $idx = $e.line - 1
            if ($idx -lt 0 -or $idx -ge $segs.Count -or -not $segs[$idx].Contains($e.old)) { $failed++; continue }
            $pos = $segs[$idx].IndexOf($e.old)
            $segs[$idx] = $segs[$idx].Remove($pos, $e.old.Length).Insert($pos, $e.new)
            $applied++
        }
        # Rejoin verbatim: each segment still carries its original terminator,
        # so BOM and CRLF/LF survive untouched.
        [IO.File]::WriteAllText($abs, ($segs -join ''), (New-Object Text.UTF8Encoding($hasBom)))
    }
    return @{ applied = $applied; failed = $failed }
}

$findings = Invoke-Scan
$totalApplied = 0

if ($Apply) {
    $pass = 0
    while ($true) {
        $pass++
        $act = @($findings | Where-Object { $IncludeProposals -or $_.area -ne 'proposals' })
        if ($act.Count -eq 0 -or $pass -gt 5) { break }
        $r = Invoke-Apply $act
        $totalApplied += $r.applied
        if ($r.failed -gt 0) { Write-Output "⚠️  pass $($pass): $($r.failed) úprav se nepodařilo umístit" }
        # Fixes can uncover second-order findings — rescan until clean.
        $findings = Invoke-Scan
    }
}

Write-Output "Odkazů celkem: $script:linkTotal (z toho externích: $script:linkExternal)"
if ($Apply) { Write-Output "Aplikováno úprav: $totalApplied" }
Write-Output ''

if ($Json) {
    @{ repo = $repoFull; marker = $Marker; applied = $totalApplied; findings = @($findings) } |
        ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $Json -Encoding utf8
    Write-Output "Ledger: $Json"
    Write-Output ''
}

if ($findings.Count -eq 0) { Write-Output '✅ Žádné nálezy — odkazy v Memory Bank jsou konzistentní.'; exit 0 }

Write-Output '| Třída | proposals | stavové | celkem |'
Write-Output '|---|---|---|---|'
foreach ($g in ($findings | Group-Object class | Sort-Object Count -Descending)) {
    $p = @($g.Group | Where-Object { $_.area -eq 'proposals' }).Count
    $s = @($g.Group | Where-Object { $_.area -eq 'stav' }).Count
    Write-Output "| $($g.Name) | $p | $s | $($g.Count) |"
}
Write-Output ''
Write-Output "Nálezů celkem: $($findings.Count)"
if (-not $Apply) { Write-Output 'Spusť znovu s -Apply pro konsolidaci (proposals/ jen s -IncludeProposals).' }
exit 2
