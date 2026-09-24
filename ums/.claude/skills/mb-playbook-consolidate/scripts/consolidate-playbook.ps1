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
    # -Apply never raises a ratchet (contract/playbook-contract.md, "Budget, threshold and ratchet").
    # $body carries no comment; $oldPb is the file as it was before the batch ($null for a new file).
    function Set-ApplyRatchet([string[]] $body, $oldPb) {
        if ($body.Count -le $script:UmsPlaybookLimits.File) { return $body }
        $newSize = $body.Count + 1
        $old = if ($oldPb) { $oldPb.Ratchet } else { $null }
        if ($old) {
            # Lower to the achieved size; equal or grown keeps the comment as it was.
            $line = if ($newSize -lt $old.Baseline) { Get-RatchetLine $newSize $null } else { $oldPb.Lines[1] }
        } else {
            $oldSize = if ($oldPb) { $oldPb.LineCount } else { 0 }
            if ($body.Count -gt $oldSize) { return $body }
            $line = Get-RatchetLine $newSize $null
        }
        @($body[0], $line) + @($body[1..($body.Count - 1)])
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
            $parseId = { param([string] $id) $k = $id.LastIndexOf('#'); @($id.Substring(0, $k), [int]$id.Substring($k + 1)) }
            # Validate every decision before loading (and so before writing) anything.
            # Czech message, names the decision (id, or index + verdict for novy).
            $knownVerdicts = @('ponechat', 'prepsat', 'presunout', 'novy', 'sloucit', 'vyradit', 'prevest-na-test', 'do-tech')
            $decisionLabel = { param($d, [int] $i) if ($d.PSObject.Properties['id']) { $d.id } else { "#$($i + 1) ($($d.verdict))" } }
            $legacyPeek = @{}
            $isFileLegacy = {
                param([string] $rel)
                if (-not $legacyPeek.ContainsKey($rel)) {
                    $full = Join-Path $RepoRoot $rel
                    $legacyPeek[$rel] = (Test-Path $full) -and ((Read-UmsPlaybook $full).Shape -eq 'legacy')
                }
                $legacyPeek[$rel]
            }
            $convertedRels = @{}
            foreach ($d in $decisions) {
                if ($d.PSObject.Properties['id'] -and $d.verdict -in @('presunout', 'ponechat')) {
                    $convertedRels[(& $parseId $d.id)[0]] = $true
                }
            }
            for ($vi = 0; $vi -lt $decisions.Count; $vi++) {
                $d = $decisions[$vi]
                $label = & $decisionLabel $d $vi
                if ($d.verdict -notin $knownVerdicts) { throw "Rozhodnutí ${label}: neznámý verdikt '$($d.verdict)'." }
                if ($d.verdict -ne 'novy' -and -not $d.PSObject.Properties['id']) { throw "Rozhodnutí ${label}: verdikt $($d.verdict) potřebuje id." }
                if ($d.verdict -in @('presunout', 'novy')) {
                    if (-not $d.PSObject.Properties['target'] -or -not $d.target) { throw "Rozhodnutí ${label}: verdikt $($d.verdict) potřebuje target." }
                    if ($d.part -notin @('podstrom', 'projekt')) { throw "Rozhodnutí ${label}: part musí být `„podstrom`" nebo `„projekt`", ne '$($d.part)'." }
                    if (-not $d.section -or $d.section -notmatch '^Když ') { throw "Rozhodnutí ${label}: section musí začínat `„Když `" (je '$($d.section)')." }
                }
                if ($d.verdict -in @('novy', 'prepsat', 'sloucit')) {
                    if (-not $d.PSObject.Properties['text'] -or -not "$($d.text)".Trim()) { throw "Rozhodnutí ${label}: verdikt $($d.verdict) potřebuje neprázdný text." }
                }
                if ($d.verdict -eq 'sloucit' -and (-not $d.PSObject.Properties['into'] -or -not $d.into)) { throw "Rozhodnutí ${label}: verdikt sloucit potřebuje into." }
                if ($d.verdict -eq 'vyradit' -and (-not $d.PSObject.Properties['reason'] -or -not "$($d.reason)".Trim())) { throw "Rozhodnutí ${label}: verdikt vyradit potřebuje neprázdný reason." }
                if ($d.verdict -eq 'prevest-na-test' -and (-not $d.PSObject.Properties['test'] -or -not $d.test)) { throw "Rozhodnutí ${label}: verdikt prevest-na-test potřebuje test." }
                if ($d.verdict -eq 'do-tech' -and (-not $d.PSObject.Properties['target'] -or -not $d.target)) { throw "Rozhodnutí ${label}: verdikt do-tech potřebuje target." }
                if ($d.verdict -in @('prepsat', 'sloucit') -and $d.PSObject.Properties['id']) {
                    $rel = (& $parseId $d.id)[0]
                    if ($convertedRels.ContainsKey($rel) -and (& $isFileLegacy $rel)) {
                        throw "Rozhodnutí ${label}: soubor $rel se v této dávce převádí (obsahuje presunout/ponechat) — přepis musí cestovat jako presunout s text, ne $($d.verdict)."
                    }
                }
            }
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
                    $model[$rel] = @{ Pb = $null; Preamble = @("# Playbook — $name"); Parts = $parts; Legacy = $false; ItemRef = @{}; Patch = $false; Appended = $null }
                    return
                }
                $pb = Read-UmsPlaybook $full
                $pre = @($pb.Lines[0..([Math]::Max(0, $pb.PreambleEnd - 1))] | Select-Object -First ([Math]::Max(1, $pb.PreambleEnd)))
                $pre = @($pre | Where-Object { -not ($_ -match '^<!-- playbook-budget:') })
                $ref = @{}
                if ($pb.Shape -eq 'new') {
                    $bad = @($pb.Items | Where-Object { $_.Kind -eq 'prose' -or -not $_.Part -or -not $_.Section } | ForEach-Object { "$rel#$($_.Id)" })
                    if ($bad.Count) { throw "Soubor $rel není v platném tvaru: položky mimo část nebo sekci ($($bad -join ', ')). Nejdřív oprav tvar (Test-UmsPlaybookShape)." }
                    foreach ($it in $pb.Items) {
                        if (-not $parts[$it.Part].Contains($it.Section)) { $parts[$it.Part][$it.Section] = [Collections.Generic.List[object]]::new() }
                        $entry = [pscustomobject]@{ Id = $it.Id; Lines = (Get-ItemLines $pb $it) }
                        $parts[$it.Part][$it.Section].Add($entry)
                        $ref[$it.Id] = $entry
                    }
                }
                $model[$rel] = @{ Pb = $pb; Preamble = $pre; Parts = $parts; Legacy = ($pb.Shape -eq 'legacy'); ItemRef = $ref; Patch = $false; Appended = $null }
            }
            foreach ($d in $decisions) {
                if ($d.PSObject.Properties['id']) { & $load (& $parseId $d.id)[0] }
                if ($d.PSObject.Properties['target'] -and $d.verdict -ne 'do-tech') { & $load $d.target }
                if ($d.PSObject.Properties['into']) { & $load (& $parseId $d.into)[0] }
            }
            # Legacy: a CONVERSION when the batch has presunout or ponechat for one of the
            # file's items (then every item needs a decision); otherwise a PATCH in place
            # that leaves every untouched line byte-for-byte (contract/playbook-contract.md, "Legacy mode").
            foreach ($rel in @($model.Keys)) {
                $m = $model[$rel]
                if (-not $m.Legacy) { continue }
                $decided = @($decisions | Where-Object { $_.PSObject.Properties['id'] -and ((& $parseId $_.id)[0] -eq $rel) })
                if (-not @($decided | Where-Object { $_.verdict -in @('presunout', 'ponechat') }).Count) {
                    $m.Patch = $true
                    $m.Appended = [Collections.Generic.List[object]]::new()
                    if ($m.Pb) { foreach ($it in $m.Pb.Items) { $m.ItemRef[$it.Id] = [pscustomobject]@{ Id = $it.Id; Lines = (Get-ItemLines $m.Pb $it); Removed = $false } } }
                    continue
                }
                if (@($decided | Where-Object verdict -eq 'ponechat').Count) { throw "Legacy soubor ${rel}: verdikt ponechat nelze použít, položka potřebuje část a sekci (presunout)." }
                $ids = @($decided | ForEach-Object { (& $parseId $_.id)[1] })
                $missing = @($m.Pb.Items | Where-Object { $ids -notcontains $_.Id } | ForEach-Object { "$rel#$($_.Id)" })
                if ($missing.Count) { throw "Legacy soubor $rel se převádí celý; položky bez rozhodnutí: $($missing -join ', ')" }
            }
            $retired = @{}
            $addRetired = {
                param([string] $rel, [string] $title, [string[]] $lines, [string] $why)
                $r = (Get-MbOf $rel) + '/playbook-retired.md'
                if (-not $retired.ContainsKey($r)) { $retired[$r] = [Collections.Generic.List[string]]::new() }
                $t = $title
                if ($t.Trim() -eq '' -or $t -match $script:UmsFenceRx) {
                    # Title is a fence delimiter (or blank) — a prose item whose first line is
                    # not real text. Walk the item's own lines to the first real text line
                    # instead, skipping fence lines and empty lines.
                    $real = @($lines | Where-Object { $_.Trim() -ne '' -and $_ -notmatch $script:UmsFenceRx } | Select-Object -First 1)
                    if ($real.Count) { $t = ($real[0] -replace '^\s*-\s*', '') -replace '\*\*', '' }
                }
                $words = (@($t.Trim() -split '\s+') | Select-Object -First 8) -join ' '
                $retired[$r].Add("- $words — $why ($Today)")
            }
            $insert = {
                param([string] $rel, [string] $part, [string] $section, [string[]] $lines)
                if ($model[$rel].Patch) { $model[$rel].Appended.Add($lines); return }
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
                    'vyradit' { $remove.Add(@($src, $it.Id)); & $addRetired $src $it.Title $srcLines $d.reason }
                    'prevest-na-test' { $remove.Add(@($src, $it.Id)); & $addRetired $src $it.Title $srcLines "hlídá test $($d.test)" }
                    'do-tech' { $remove.Add(@($src, $it.Id)); if (-not $techAppend.ContainsKey($d.target)) { $techAppend[$d.target] = [Collections.Generic.List[string]]::new() }; foreach ($l in $text) { $techAppend[$d.target].Add($l) } }
                    default { throw "Neznámý verdikt $($d.verdict)" }
                }
            }
            foreach ($r in $remove) {
                $m = $model[$r[0]]
                if ($m.Patch) { $m.ItemRef[$r[1]].Removed = $true; continue }
                if ($m.Legacy) { continue }
                foreach ($part in $m.Parts.Values) { foreach ($sec in $part.Values) { $x = @($sec | Where-Object Id -eq $r[1]); foreach ($e in $x) { [void]$sec.Remove($e) } } }
            }
            $written = [Collections.Generic.List[string]]::new()
            foreach ($rel in $model.Keys) {
                $m = $model[$rel]
                if ($m.Patch) {
                    $out = [Collections.Generic.List[string]]::new()
                    $byStart = @{}
                    foreach ($it in $m.Pb.Items) { $byStart[$it.StartLine] = $it }
                    for ($i = 1; $i -le $m.Pb.LineCount; $i++) {
                        if ($byStart.ContainsKey($i)) {
                            $e = $m.ItemRef[$byStart[$i].Id]
                            if (-not $e.Removed) { foreach ($l in $e.Lines) { $out.Add($l) } }
                            $i = $byStart[$i].EndLine
                            continue
                        }
                        $out.Add($m.Pb.Lines[$i - 1])
                    }
                    if ($m.Appended.Count) {
                        while ($out.Count -and $out[$out.Count - 1] -eq '') { $out.RemoveAt($out.Count - 1) }
                        foreach ($block in $m.Appended) { $out.Add(''); foreach ($l in $block) { $out.Add($l) } }
                    }
                    Write-Lf $rel $out.ToArray()
                    $written.Add($rel)
                    continue
                }
                $out = [Collections.Generic.List[string]]::new()
                foreach ($l in $m.Preamble) { $out.Add($l) }
                while ($out.Count -and $out[$out.Count - 1] -eq '') { $out.RemoveAt($out.Count - 1) }
                foreach ($key in $script:UmsPlaybookPartTitles.Keys) {
                    $secs = @($m.Parts[$key].Keys | Where-Object { $m.Parts[$key][$_].Count })
                    if (-not $secs.Count) { continue }
                    $out.Add(''); $out.Add("## $($script:UmsPlaybookPartTitles[$key])")
                    foreach ($s in $secs) {
                        $out.Add(''); $out.Add("### $s"); $out.Add('')
                        # Items of a section follow each other without an empty line (the item
                        # shape of contract/playbook-contract.md, "Playbook shape"); an empty line
                        # per item would grow every rewritten file by one line per item.
                        foreach ($e in $m.Parts[$key][$s]) { foreach ($l in $e.Lines) { $out.Add($l) } }
                    }
                }
                while ($out.Count -and $out[$out.Count - 1] -eq '') { $out.RemoveAt($out.Count - 1) }
                Write-Lf $rel (Set-ApplyRatchet $out.ToArray() $m.Pb)
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
                    # Append directly after the section's last non-empty line — no empty line
                    # splitting the list — but keep one empty line after a bare heading and one
                    # empty line before the next "## ".
                    $body = [Collections.Generic.List[string]]::new(); $body.AddRange([string[]]$lines[0..($end - 1)])
                    while ($body.Count -and $body[$body.Count - 1] -eq '') { $body.RemoveAt($body.Count - 1) }
                    if ($body.Count -and $body[$body.Count - 1] -match '^## ') { $body.Add('') }
                    foreach ($l in $techAppend[$t]) { $body.Add($l) }
                    $lines = @($body.ToArray()) + $(if ($end -lt $lines.Count) { @('') + @($lines[$end..($lines.Count - 1)]) } else { @() })
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
