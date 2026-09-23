#Requires -Version 7
# Dot-source this file. Memory Bank tree, playbook chain and lowest common ancestor
# (contract/playbook-contract.md, "Playbook chain"). Read-only except the -Out scratch file.
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'Read-UmsPlaybook.ps1')

function ConvertTo-UmsMbDir([string] $Mb) {
    $d = ($Mb -replace '\\', '/').TrimEnd('/')
    if ($d -notmatch '(^|/)memory-bank$') { throw "Not a memory-bank directory: $Mb" }
    $d
}

function Get-UmsMbTree([string] $RepoRoot) {
    $files = @(git -C $RepoRoot ls-files)
    if ($LASTEXITCODE -ne 0) { throw "git ls-files failed in $RepoRoot" }
    $byDir = @{}
    foreach ($f in $files) {
        $m = [regex]::Match($f, '^(?:(.+)/)?memory-bank/([^/]+\.md)$')
        if (-not $m.Success) { continue }
        if (([regex]::Matches($f, '(^|/)memory-bank/')).Count -ne 1) { continue }
        $owner = $m.Groups[1].Value
        $dir = if ($owner) { "$owner/memory-bank" } else { 'memory-bank' }
        if (-not $byDir.ContainsKey($dir)) { $byDir[$dir] = [pscustomobject]@{ Dir = $dir; Owner = $owner; Playbook = $null; Tasks = $null } }
        if ($m.Groups[2].Value -eq 'playbook.md') { $byDir[$dir].Playbook = $f }
        if ($m.Groups[2].Value -eq 'tasks.md') { $byDir[$dir].Tasks = $f }
    }
    @($byDir.Values | ForEach-Object {
        [pscustomobject]@{ Dir = $_.Dir; Owner = $_.Owner; Playbook = $(if ($_.Playbook) { $_.Playbook } else { $_.Tasks }) }
    } | Sort-Object Owner)
}

function Test-UmsOwnerIsAncestor([string] $Ancestor, [string] $Owner) {
    if ($Ancestor -eq $Owner) { return $false }
    ($Ancestor -eq '') -or $Owner.StartsWith("$Ancestor/")
}

function Get-UmsPlaybookChain([string] $RepoRoot, [string] $Mb, [switch] $Out) {
    $dir = ConvertTo-UmsMbDir $Mb
    $tree = Get-UmsMbTree $RepoRoot
    $target = $tree | Where-Object Dir -eq $dir
    $owner = if ($dir -eq 'memory-bank') { '' } else { $dir -replace '/memory-bank$', '' }
    $segments = [Collections.Generic.List[object]]::new()
    $ancestors = @($tree | Where-Object { $_.Playbook -and (Test-UmsOwnerIsAncestor $_.Owner $owner) } | Sort-Object { ($_.Owner -split '/').Count * [int]($_.Owner -ne '') })
    foreach ($a in $ancestors) {
        $pb = Read-UmsPlaybook (Join-Path $RepoRoot $a.Playbook)
        if ($pb.Shape -eq 'new') {
            if ($pb.Parts.ContainsKey('podstrom')) {
                $p = $pb.Parts['podstrom']
                $segments.Add([pscustomobject]@{ Mb = $a.Dir; Playbook = $a.Playbook; Part = 'podstrom'; StartLine = $p.Start; EndLine = $p.End; Lines = $p.End - $p.Start + 1 })
            }
        } elseif ($a.Owner -eq '') {
            $segments.Add([pscustomobject]@{ Mb = $a.Dir; Playbook = $a.Playbook; Part = 'celý soubor'; StartLine = 1; EndLine = $pb.LineCount; Lines = $pb.LineCount })
        }
    }
    if ($target -and $target.Playbook) {
        $pb = Read-UmsPlaybook (Join-Path $RepoRoot $target.Playbook)
        $segments.Add([pscustomobject]@{ Mb = $target.Dir; Playbook = $target.Playbook; Part = 'celý soubor'; StartLine = 1; EndLine = $pb.LineCount; Lines = $pb.LineCount })
    }
    $total = [int](($segments | Measure-Object Lines -Sum).Sum)
    $outPath = $null
    if ($Out) {
        $slug = if ($owner) { $owner -replace '/', '_' } else { 'root' }
        $outDir = Join-Path $RepoRoot '.superpowers/playbook-chain'
        New-Item -ItemType Directory -Force $outDir | Out-Null
        $outPath = Join-Path $outDir "$slug.md"
        $sb = [Text.StringBuilder]::new()
        foreach ($s in $segments) {
            $pb = Read-UmsPlaybook (Join-Path $RepoRoot $s.Playbook)
            [void]$sb.Append("<!-- úsek: $($s.Playbook) ($($s.Part), řádky $($s.StartLine)–$($s.EndLine)) -->`n")
            [void]$sb.Append((@($pb.Lines[($s.StartLine - 1)..($s.EndLine - 1)]) -join "`n")).Append("`n`n")
        }
        [IO.File]::WriteAllText($outPath, $sb.ToString(), [Text.UTF8Encoding]::new($false))
    }
    [pscustomobject]@{ Mb = $dir; Segments = $segments.ToArray(); TotalLines = $total; OutPath = $outPath }
}

function Get-UmsMbLowestCommonAncestor([object[]] $Tree, [string[]] $Mbs) {
    $owners = @($Mbs | ForEach-Object { $d = ConvertTo-UmsMbDir $_; if ($d -eq 'memory-bank') { '' } else { $d -replace '/memory-bank$', '' } })
    $common = @($owners[0] -split '/' | Where-Object { $_ })
    if ($owners.Count -gt 1) {
        foreach ($o in $owners[1..($owners.Count - 1)]) {
            $segs = @($o -split '/' | Where-Object { $_ })
            $k = 0
            while ($k -lt $common.Count -and $k -lt $segs.Count -and $common[$k] -eq $segs[$k]) { $k++ }
            $common = @(if ($k) { $common[0..($k - 1)] } else { @() })
        }
    }
    for ($len = $common.Count; $len -ge 0; $len--) {
        $o = if ($len) { ($common[0..($len - 1)]) -join '/' } else { '' }
        $hit = $Tree | Where-Object Owner -eq $o
        if ($hit) { return $hit.Dir }
    }
    'memory-bank'
}
