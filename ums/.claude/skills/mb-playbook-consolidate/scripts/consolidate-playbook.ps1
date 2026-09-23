#Requires -Version 7
<#
Mechanical half of playbook consolidation and of the harvest gate
(contract/playbook-contract.md, "Consolidation"). Judgement is the analyst's,
approval is the human's; this script only executes approved decisions.
Output: JSON on stdout. Errors: Czech message, exit 1.
#>
[CmdletBinding(DefaultParameterSetName = 'Parse')]
param(
    [Parameter(ParameterSetName = 'Parse', Mandatory)] [switch] $Parse,
    [Parameter(ParameterSetName = 'Apply', Mandatory)] [string] $Apply,
    [Parameter(ParameterSetName = 'Baseline', Mandatory)] [switch] $Baseline,
    [Parameter(ParameterSetName = 'Resume', Mandatory)] [string] $Resume,
    [Parameter(ParameterSetName = 'Stats', Mandatory)] [switch] $Stats,
    [string] $Path,
    [string] $Tree,
    [string] $Reason,
    [string] $RepoRoot,
    [string] $Today = (Get-Date -Format 'yyyy-MM-dd')
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$shared = Join-Path $PSScriptRoot '..\..\shared\scripts'
. (Join-Path $shared 'Test-UmsPlaybookShape.ps1')
try {
    if (-not $RepoRoot) { $RepoRoot = (git rev-parse --show-toplevel) }
    $utf8 = [Text.UTF8Encoding]::new($false)

    function Get-RelPlaybooks {
        if ($Path) { return @($Path -replace '\\', '/') }
        $under = if ($Tree -in @('', '.')) { '' } else { ($Tree -replace '\\', '/').TrimEnd('/') }
        @(Get-UmsMbTree $RepoRoot | Where-Object { $_.Playbook -and (($under -eq '') -or $_.Owner -eq $under -or $_.Owner.StartsWith("$under/")) } | ForEach-Object Playbook)
    }
    function Get-MbOf([string] $rel) { ($rel -replace '/[^/]+$', '') }
    function Write-Lf([string] $rel, [string[]] $lines) {
        $p = Join-Path $RepoRoot $rel
        New-Item -ItemType Directory -Force (Split-Path $p) | Out-Null
        [IO.File]::WriteAllText($p, (($lines -join "`n") + "`n"), $utf8)
    }
    function Get-ItemLines($pb, $it) { @($pb.Lines[($it.StartLine - 1)..($it.EndLine - 1)]) }
    function Split-Text([string] $t) { @(($t -replace "`r`n", "`n").TrimEnd("`n") -split "`n") }
    function Get-RatchetLine([int] $n, [string] $reason) {
        $r = if ($reason) { ", $reason" } else { '' }
        "<!-- playbook-budget: $($script:UmsPlaybookLimits.File); baseline: $n ($Today$r) -->"
    }
    function Set-Ratchet([string[]] $lines, [string] $reason) {
        $body = [Collections.Generic.List[string]]::new()
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($i -eq 1 -and (Get-UmsPlaybookRatchet $lines)) { continue }
            $body.Add($lines[$i])
        }
        if ($body.Count -le $script:UmsPlaybookLimits.File) { return $body.ToArray() }
        $withComment = $body.Count + 1
        @($body[0], (Get-RatchetLine $withComment $reason)) + @($body.GetRange(1, $body.Count - 1))
    }

    switch ($PSCmdlet.ParameterSetName) {
        'Parse' {
            $files = foreach ($rel in Get-RelPlaybooks) {
                $pb = Read-UmsPlaybook (Join-Path $RepoRoot $rel)
                [ordered]@{
                    playbook = $rel; mb = (Get-MbOf $rel); shape = $pb.Shape; lines = $pb.LineCount; ratchet = $pb.Ratchet
                    items    = @($pb.Items | ForEach-Object { [ordered]@{ id = "$rel#$($_.Id)"; kind = $_.Kind; part = $_.Part; section = $_.Section; title = $_.Title; startLine = $_.StartLine; endLine = $_.EndLine; lineCount = $_.LineCount; proc = $_.Proc; dukaz = $_.Dukaz } })
                }
            }
            @{ files = @($files) } | ConvertTo-Json -Depth 6
        }
        'Baseline' {
            $rel = $Path -replace '\\', '/'
            $pb = Read-UmsPlaybook (Join-Path $RepoRoot $rel)
            $lines = @($pb.Lines)
            $out = Set-Ratchet $lines $Reason
            Write-Lf $rel $out
            @{ written = @($rel) } | ConvertTo-Json
        }
        'Resume' {
            $vals = @(git -C $RepoRoot log --format='%(trailers:key=Playbook-Consolidation,valueonly)')
            $done = @($vals | Where-Object { $_ -like "$Resume/*" } | ForEach-Object { ($_ -split '/', 2)[1].Trim() } | Sort-Object -Unique)
            @{ run = $Resume; done = $done } | ConvertTo-Json
        }
        'Stats' {
            $mbs = foreach ($rel in Get-RelPlaybooks) {
                $pb = Read-UmsPlaybook (Join-Path $RepoRoot $rel)
                $chain = Get-UmsPlaybookChain $RepoRoot (Get-MbOf $rel)
                $secs = @($pb.Items | Group-Object { "$($_.Part)|$($_.Section)" } | ForEach-Object {
                        $parts = $_.Name -split '\|', 2
                        [ordered]@{ part = $parts[0]; section = $parts[1]; items = $_.Count; lines = [int](($_.Group | Measure-Object LineCount -Sum).Sum) }
                    })
                [ordered]@{ mb = (Get-MbOf $rel); playbook = $rel; lines = $pb.LineCount; overThreshold = ($pb.LineCount -gt $script:UmsPlaybookLimits.File); chainLines = $chain.TotalLines; sections = $secs }
            }
            @{ mbs = @($mbs) } | ConvertTo-Json -Depth 6
        }
        'Apply' {
            $doc = Get-Content -Raw $Apply | ConvertFrom-Json
            $decisions = @($doc.decisions)
            # Load every involved file once.
            $model = @{}   # rel -> @{ Pb; Preamble; Parts = ordered part -> ordered section -> List[string[]] ; Legacy }
            $load = {
                param([string] $rel)
                if ($model.ContainsKey($rel)) { return }
                $full = Join-Path $RepoRoot $rel
                $parts = [ordered]@{ podstrom = [ordered]@{}; projekt = [ordered]@{} }
                if (-not (Test-Path $full)) {
                    $owner = (Get-MbOf $rel) -replace '/?memory-bank$', ''
                    $name = if ($owner) { $owner } else { 'kořen' }
                    $model[$rel] = @{ Pb = $null; Preamble = @("# Playbook — $name"); Parts = $parts; Legacy = $false; ItemRef = @{} }
                    return
                }
                $pb = Read-UmsPlaybook $full
                $pre = @($pb.Lines[0..([Math]::Max(0, $pb.PreambleEnd - 1))] | Select-Object -First ([Math]::Max(1, $pb.PreambleEnd)))
                $pre = @($pre | Where-Object { -not ($_ -match '^<!-- playbook-budget:') })
                $ref = @{}
                if ($pb.Shape -eq 'new') {
                    foreach ($it in $pb.Items) {
                        if (-not $parts[$it.Part].Contains($it.Section)) { $parts[$it.Part][$it.Section] = [Collections.Generic.List[object]]::new() }
                        $entry = [pscustomobject]@{ Id = $it.Id; Lines = (Get-ItemLines $pb $it) }
                        $parts[$it.Part][$it.Section].Add($entry)
                        $ref[$it.Id] = $entry
                    }
                }
                $model[$rel] = @{ Pb = $pb; Preamble = $pre; Parts = $parts; Legacy = ($pb.Shape -eq 'legacy'); ItemRef = $ref }
            }
            $parseId = { param([string] $id) $k = $id.LastIndexOf('#'); @($id.Substring(0, $k), [int]$id.Substring($k + 1)) }
            foreach ($d in $decisions) {
                if ($d.PSObject.Properties['id']) { & $load (& $parseId $d.id)[0] }
                if ($d.PSObject.Properties['target'] -and $d.verdict -ne 'do-tech') { & $load $d.target }
                if ($d.PSObject.Properties['into']) { & $load (& $parseId $d.into)[0] }
            }
            # Legacy completeness.
            foreach ($rel in @($model.Keys)) {
                $m = $model[$rel]
                if (-not $m.Legacy) { continue }
                $decided = @($decisions | Where-Object { $_.PSObject.Properties['id'] -and ((& $parseId $_.id)[0] -eq $rel) })
                if (@($decided | Where-Object verdict -eq 'ponechat').Count) { throw "Legacy soubor ${rel}: verdikt ponechat nelze použít, položka potřebuje část a sekci (presunout)." }
                $ids = @($decided | ForEach-Object { (& $parseId $_.id)[1] })
                $missing = @($m.Pb.Items | Where-Object { $ids -notcontains $_.Id } | ForEach-Object { "$rel#$($_.Id)" })
                if ($missing.Count) { throw "Legacy soubor $rel se převádí celý; položky bez rozhodnutí: $($missing -join ', ')" }
            }
            $retired = @{}
            $addRetired = {
                param([string] $rel, [string] $title, [string] $why)
                $r = (Get-MbOf $rel) + '/playbook-retired.md'
                if (-not $retired.ContainsKey($r)) { $retired[$r] = [Collections.Generic.List[string]]::new() }
                $words = (@($title -split '\s+') | Select-Object -First 8) -join ' '
                $retired[$r].Add("- $words — $why ($Today)")
            }
            $insert = {
                param([string] $rel, [string] $part, [string] $section, [string[]] $lines)
                $p = $model[$rel].Parts[$part]
                if (-not $p.Contains($section)) { $p[$section] = [Collections.Generic.List[object]]::new() }
                $p[$section].Add([pscustomobject]@{ Id = -1; Lines = $lines })
            }
            $remove = [Collections.Generic.List[object]]::new()
            $techAppend = @{}
            foreach ($d in $decisions) {
                $src = $null; $it = $null; $srcLines = $null
                if ($d.PSObject.Properties['id']) {
                    $pair = & $parseId $d.id
                    $src = $pair[0]
                    $it = @($model[$src].Pb.Items | Where-Object Id -eq $pair[1])
                    if (-not $it.Count) { throw "Neznámá položka $($d.id)" }
                    $it = $it[0]
                    $srcLines = Get-ItemLines $model[$src].Pb $it
                }
                $text = if ($d.PSObject.Properties['text']) { Split-Text $d.text } else { $srcLines }
                switch ($d.verdict) {
                    'ponechat' { }
                    'prepsat' { $model[$src].ItemRef[$it.Id].Lines = $text }
                    'presunout' { $remove.Add(@($src, $it.Id)); & $insert $d.target $d.part $d.section $text }
                    'novy' { & $insert $d.target $d.part $d.section $text }
                    'sloucit' { $ip = & $parseId $d.into; $model[$ip[0]].ItemRef[$ip[1]].Lines = $text; $remove.Add(@($src, $it.Id)) }
                    'vyradit' { $remove.Add(@($src, $it.Id)); & $addRetired $src $it.Title $d.reason }
                    'prevest-na-test' { $remove.Add(@($src, $it.Id)); & $addRetired $src $it.Title "hlídá test $($d.test)" }
                    'do-tech' { $remove.Add(@($src, $it.Id)); if (-not $techAppend.ContainsKey($d.target)) { $techAppend[$d.target] = [Collections.Generic.List[string]]::new() }; foreach ($l in $text) { $techAppend[$d.target].Add($l) } }
                    default { throw "Neznámý verdikt $($d.verdict)" }
                }
            }
            foreach ($r in $remove) {
                $m = $model[$r[0]]
                if ($m.Legacy) { continue }
                foreach ($part in $m.Parts.Values) { foreach ($sec in $part.Values) { $x = @($sec | Where-Object Id -eq $r[1]); foreach ($e in $x) { [void]$sec.Remove($e) } } }
            }
            $written = [Collections.Generic.List[string]]::new()
            foreach ($rel in $model.Keys) {
                $m = $model[$rel]
                $out = [Collections.Generic.List[string]]::new()
                foreach ($l in $m.Preamble) { $out.Add($l) }
                while ($out.Count -and $out[$out.Count - 1] -eq '') { $out.RemoveAt($out.Count - 1) }
                foreach ($key in $script:UmsPlaybookPartTitles.Keys) {
                    $secs = @($m.Parts[$key].Keys | Where-Object { $m.Parts[$key][$_].Count })
                    if (-not $secs.Count) { continue }
                    $out.Add(''); $out.Add("## $($script:UmsPlaybookPartTitles[$key])")
                    foreach ($s in $secs) {
                        $out.Add(''); $out.Add("### $s"); $out.Add('')
                        $first = $true
                        foreach ($e in $m.Parts[$key][$s]) {
                            if (-not $first) { $out.Add('') }
                            foreach ($l in $e.Lines) { $out.Add($l) }
                            $first = $false
                        }
                    }
                }
                while ($out.Count -and $out[$out.Count - 1] -eq '') { $out.RemoveAt($out.Count - 1) }
                Write-Lf $rel (Set-Ratchet $out.ToArray() $null)
                $written.Add($rel)
            }
            foreach ($r in $retired.Keys) {
                $full = Join-Path $RepoRoot $r
                $existing = if (Test-Path $full) { @((Get-Content -Raw $full).TrimEnd("`n") -split "`n") } else { @('# Vyřazená pravidla', '') }
                Write-Lf $r (@($existing) + @($retired[$r]))
                $written.Add($r)
            }
            foreach ($t in $techAppend.Keys) {
                $full = Join-Path $RepoRoot $t
                $lines = if (Test-Path $full) { @((Get-Content -Raw $full).TrimEnd("`n") -split "`n") } else { @('# Tech') }
                $idx = [Array]::IndexOf($lines, '## Pasti prostředí')
                if ($idx -lt 0) { $lines = @($lines) + @('', '## Pasti prostředí', '') + @($techAppend[$t]) }
                else {
                    $end = $idx + 1
                    while ($end -lt $lines.Count -and $lines[$end] -notmatch '^## ') { $end++ }
                    $lines = @($lines[0..($end - 1)]) + @($techAppend[$t]) + $(if ($end -lt $lines.Count) { @('') + @($lines[$end..($lines.Count - 1)]) } else { @() })
                }
                Write-Lf $t $lines
                $written.Add($t)
            }
            @{ written = $written.ToArray(); retired = [int](($retired.Values | ForEach-Object Count | Measure-Object -Sum).Sum) } | ConvertTo-Json
        }
    }
}
catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
