#Requires -Version 7
# Dot-source this file, then call Read-UmsPlaybook -Path <playbook.md>.
# Parses a Memory Bank playbook (contract/playbook-contract.md, "Playbook shape")
# into items. Read-only; never writes.
Set-StrictMode -Version Latest

$script:UmsPlaybookPartTitles = [ordered]@{ podstrom = 'Pro celý podstrom'; projekt = 'Jen pro tento projekt' }
$script:UmsFenceRx = '^\s{0,3}(```|~~~)'
$script:UmsRuleRx = '^(?:- |\d+\. )\*\*(.+?)(?:\*\*|$)'
$script:UmsPostupRx = '^\*\*([^*].*?)\*\*\s*$'

function Get-UmsPlaybookRatchet([string[]] $Lines) {
    if ($Lines.Count -lt 2) { return $null }
    $m = [regex]::Match($Lines[1], '^<!-- playbook-budget: (\d+); baseline: (\d+) \((\d{4}-\d{2}-\d{2})(?:, (.+?))?\) -->$')
    if (-not $m.Success) { return $null }
    [pscustomobject]@{
        Budget   = [int]$m.Groups[1].Value
        Baseline = [int]$m.Groups[2].Value
        Date     = $m.Groups[3].Value
        Reason   = $(if ($m.Groups[4].Success) { $m.Groups[4].Value } else { $null })
    }
}

function Read-UmsPlaybook([string] $Path) {
    $raw = [IO.File]::ReadAllText($Path)
    $list = [Collections.Generic.List[string]]::new()
    foreach ($l in ($raw -split "`n")) { $list.Add($l.TrimEnd("`r")) }
    if ($list.Count -gt 0 -and $list[$list.Count - 1] -eq '') { $list.RemoveAt($list.Count - 1) }
    $lines = $list.ToArray()
    $n = $lines.Count

    # Pass 1: fences and headings (0-based line numbers internally).
    $inFence = $false
    $fenced = [bool[]]::new($n)
    $headings = [Collections.Generic.List[object]]::new()
    for ($i = 0; $i -lt $n; $i++) {
        if ($lines[$i] -match $script:UmsFenceRx) { $fenced[$i] = $true; $inFence = -not $inFence; continue }
        if ($inFence) { $fenced[$i] = $true; continue }
        $m = [regex]::Match($lines[$i], '^(#{1,6})\s+(.+?)\s*$')
        if ($m.Success) { $headings.Add([pscustomobject]@{ Line = $i; Level = $m.Groups[1].Value.Length; Title = $m.Groups[2].Value }) }
    }
    $isHeading = [bool[]]::new($n)
    foreach ($h in $headings) { $isHeading[$h.Line] = $true }

    $partTitles = @($script:UmsPlaybookPartTitles.Values)
    $h2 = @($headings | Where-Object Level -eq 2)
    $isNew = ($h2.Count -gt 0) -and (@($h2 | Where-Object { $partTitles -notcontains $_.Title }).Count -eq 0)
    $firstH2 = if ($h2.Count) { $h2[0].Line } else { $n }

    $parts = @{}
    $sections = [Collections.Generic.List[object]]::new()
    if ($isNew) {
        for ($k = 0; $k -lt $h2.Count; $k++) {
            $key = @($script:UmsPlaybookPartTitles.Keys | Where-Object { $script:UmsPlaybookPartTitles[$_] -eq $h2[$k].Title })[0]
            $end = if ($k + 1 -lt $h2.Count) { $h2[$k + 1].Line } else { $n }
            $parts[$key] = [pscustomobject]@{ Start = $h2[$k].Line + 1; End = $end }
        }
    }

    # Context of a 0-based line: part key and section title.
    $contextOf = {
        param([int] $line, [int] $ownHeading)
        $part = $null; $section = $null
        foreach ($h in $headings) {
            if ($h.Line -ge $line -or $h.Line -eq $ownHeading) { if ($h.Line -ge $line) { break } else { continue } }
            if ($h.Level -eq 2) {
                $section = $null
                $part = if ($isNew) { @($script:UmsPlaybookPartTitles.Keys | Where-Object { $script:UmsPlaybookPartTitles[$_] -eq $h.Title })[0] } else { $null }
                if (-not $isNew) { $section = $h.Title }
            } elseif ($h.Level -ge 3) { $section = $h.Title }
        }
        , @($part, $section)
    }

    $consumed = [bool[]]::new($n)
    $spans = [Collections.Generic.List[object]]::new()   # Kind, Start, End (0-based), Title, OwnHeading

    if (-not $isNew) {
        # Heading items: a heading (level >= 2) whose body has no rule starts and is not empty.
        for ($k = 0; $k -lt $headings.Count; $k++) {
            $h = $headings[$k]
            if ($h.Level -lt 2) { continue }
            $bodyEnd = if ($k + 1 -lt $headings.Count) { $headings[$k + 1].Line - 1 } else { $n - 1 }
            $hasRule = $false; $last = -1
            for ($i = $h.Line + 1; $i -le $bodyEnd; $i++) {
                if (-not $fenced[$i] -and $lines[$i] -match $script:UmsRuleRx) { $hasRule = $true }
                if ($lines[$i].Trim() -ne '') { $last = $i }
            }
            if ($hasRule -or $last -lt 0) { continue }
            for ($i = $h.Line; $i -le $last; $i++) { $consumed[$i] = $true }
            $spans.Add([pscustomobject]@{ Kind = 'heading'; Start = $h.Line; End = $last; Title = $h.Title; OwnHeading = $h.Line })
        }
    }

    # Rules, procedures and prose after the preamble.
    #
    # Ruling R1: in the NEW shape only, a blank line OUTSIDE a fence closes any
    # open item (rule, procedure, prose) — not just prose. The next task's
    # shape check relies on prose following a rule after a blank line being
    # reported as a separate "text outside item", not absorbed into the rule.
    # In the legacy shape blank lines keep the brief's original behaviour:
    # they never close a rule/procedure, only prose. A blank line INSIDE a
    # fence never closes anything in either shape — it is just more content
    # of the open item (e.g. a blank line inside a fenced code block that is
    # part of a postup).
    $cur = $null
    $close = { if ($null -ne $cur) { $spans.Add($cur) }; $null }
    for ($i = $firstH2; $i -lt $n; $i++) {
        if ($consumed[$i] -or $isHeading[$i]) { $cur = & $close; continue }
        $line = $lines[$i]
        if (-not $fenced[$i] -and $line -match $script:UmsRuleRx) {
            $cur = & $close
            $cur = [pscustomobject]@{ Kind = 'pravidlo'; Start = $i; End = $i; Title = $Matches[1].Trim(); OwnHeading = -1 }
            continue
        }
        if ($isNew -and -not $fenced[$i] -and $line -match $script:UmsPostupRx) {
            $cur = & $close
            $cur = [pscustomobject]@{ Kind = 'postup'; Start = $i; End = $i; Title = $Matches[1].Trim(); OwnHeading = -1 }
            continue
        }
        if ($line.Trim() -eq '') {
            if ($fenced[$i]) {
                if ($null -ne $cur) { $cur.End = $i }
                continue
            }
            if ($isNew) {
                if ($null -ne $cur) { $cur = & $close }
            } elseif ($null -ne $cur -and $cur.Kind -eq 'prose') {
                $cur = & $close
            }
            continue
        }
        if ($null -ne $cur) { $cur.End = $i; continue }
        $cur = [pscustomobject]@{ Kind = 'prose'; Start = $i; End = $i; Title = $line.Trim(); OwnHeading = -1 }
    }
    $cur = & $close

    $items = [Collections.Generic.List[object]]::new()
    $id = 0
    foreach ($s in ($spans | Sort-Object Start)) {
        $id++
        $ctx = & $contextOf $s.Start $s.OwnHeading
        $ls = @($lines[$s.Start..$s.End])
        $joined = (($ls | ForEach-Object { $_.Trim() }) -join ' ')
        $pm = [regex]::Match($joined, 'Proč:\s*(.+?)(?=\s*Důkaz:|$)')
        $dm = [regex]::Match($joined, 'Důkaz:\s*(.+?)\s*$')
        $title = $s.Title
        if ($title.Length -gt 80) { $title = $title.Substring(0, 80) }
        $items.Add([pscustomobject]@{
            Id = $id; Kind = $s.Kind; Part = $ctx[0]; Section = $ctx[1]; Title = $title
            StartLine = $s.Start + 1; EndLine = $s.End + 1; LineCount = $s.End - $s.Start + 1
            Proc = $(if ($pm.Success) { $pm.Groups[1].Value } else { $null })
            Dukaz = $(if ($dm.Success) { $dm.Groups[1].Value } else { $null })
        })
    }
    foreach ($h in $headings) {
        if ($isNew -and $h.Level -eq 3) {
            $ctx = & $contextOf $h.Line -1
            $sections.Add([pscustomobject]@{ Part = $ctx[0]; Title = $h.Title; Line = $h.Line + 1 })
        }
    }

    [pscustomobject]@{
        Path = $Path; Shape = $(if ($isNew) { 'new' } else { 'legacy' }); LineCount = $n; Lines = $lines
        Ratchet = (Get-UmsPlaybookRatchet $lines); PreambleEnd = $firstH2
        Parts = $parts; Sections = $sections.ToArray(); Items = $items.ToArray()
    }
}
