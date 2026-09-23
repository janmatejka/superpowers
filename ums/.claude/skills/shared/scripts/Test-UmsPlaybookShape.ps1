#Requires -Version 7
# Dot-source this file, then call Test-UmsPlaybookShape -Playbook <path>.
# Checks shape, thresholds and ratchet (contract/playbook-contract.md, "Budget, threshold and ratchet").
# Findings are Czech; only three classes are hard, and only for the new shape.
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'Read-UmsPlaybook.ps1')
. (Join-Path $PSScriptRoot 'Get-UmsPlaybookChain.ps1')

$script:UmsPlaybookLimits = @{ File = 600; Chain = 900; Section = 40; RuleLines = 4; RuleWidth = 80; PostupLines = 16 }

function Get-UmsSentenceCount([string] $Text) {
    $t = $Text -replace '\b(např|tj|tzn|resp|apod|atd|č|str|viz|mj|popř)\.', '$1'
    ([regex]::Matches($t, '[.!?](?=\s|$)')).Count
}

# Line shape of the sibling playbook-retired.md, for both shapes; warnings only
# (contract/playbook-contract.md, "Retired rules and conversion to code").
function Get-UmsRetiredListWarnings([string] $Playbook) {
    $p = Join-Path (Split-Path -Parent $Playbook) 'playbook-retired.md'
    if (-not (Test-Path -LiteralPath $p)) { return @() }
    $n = 0
    foreach ($raw in ([IO.File]::ReadAllText($p) -split "`n")) {
        $n++
        $l = $raw.TrimEnd("`r")
        if ($l -eq '' -or $l -match '^# ' -or $l -match '^- .+ — .+ \(\d{4}-\d{2}-\d{2}\)$') { continue }
        "[vyřazené] playbook-retired.md, řádek ${n}: není ve tvaru - <text> — <důvod> (<RRRR-MM-DD>): $l"
    }
}

function Test-UmsPlaybookShape([string] $Playbook) {
    $pb = Read-UmsPlaybook $Playbook
    $L = $script:UmsPlaybookLimits
    $hard = [Collections.Generic.List[string]]::new()
    $warn = [Collections.Generic.List[string]]::new()
    $over = $pb.LineCount -gt $L.File
    foreach ($w in @(Get-UmsRetiredListWarnings $Playbook)) { $warn.Add($w) }

    if ($pb.Shape -eq 'legacy') {
        $warn.Add('[legacy] soubor je ve starém tvaru (bez částí „Pro celý podstrom" / „Jen pro tento projekt") — převede ho kolo 1 konsolidace')
        if ($over) { $warn.Add("[práh-soubor] $($pb.LineCount) řádků > $($L.File)") }
        return [pscustomobject]@{ Playbook = $Playbook; Shape = $pb.Shape; Lines = $pb.LineCount; Hard = $hard.ToArray(); Warn = $warn.ToArray() }
    }

    foreach ($it in $pb.Items) {
        $at = "(řádek $($it.StartLine))"
        if ($it.Kind -eq 'prose') { $hard.Add("[tvar] text mimo položku $at"); continue }
        if (-not $it.Part) { $hard.Add("[tvar] položka mimo část: $($it.Title) $at") }
        if (-not $it.Section) { $hard.Add("[tvar] položka mimo sekci: $($it.Title) $at") }
        if ($it.Kind -eq 'pravidlo') {
            if ($it.LineCount -gt $L.RuleLines) { $hard.Add("[tvar] pravidlo má $($it.LineCount) řádků > $($L.RuleLines) $at") }
            for ($i = $it.StartLine; $i -le $it.EndLine; $i++) {
                if ($pb.Lines[$i - 1].Length -gt $L.RuleWidth) { $hard.Add("[tvar] řádek delší než $($L.RuleWidth) znaků (řádek $i)") }
            }
            if (-not $it.Proc) { $hard.Add("[tvar] chybí Proč: $($it.Title) $at") }
            elseif ((Get-UmsSentenceCount $it.Proc) -gt 1) { $warn.Add("[proč] Proč: má víc než jednu větu $at") }
            if (-not $it.Dukaz) { $hard.Add("[tvar] chybí Důkaz: $($it.Title) $at") }
        }
        if ($it.Kind -eq 'postup' -and $it.LineCount -gt $L.PostupLines) { $hard.Add("[tvar] postup má $($it.LineCount) řádků > $($L.PostupLines) $at") }
    }
    foreach ($s in $pb.Sections) {
        if ($s.Title -notmatch '^Když ') {
            # Message with proper curly quotes and ellipsis
            $msg = "[tvar] sekce není ve tvaru " + [char]0x201E + "Když …" + [char]0x201D + ": $($s.Title) (řádek $($s.Line))"
            $hard.Add($msg)
        }
    }
    $groups = $pb.Items | Where-Object { $_.Section } | Group-Object { "$($_.Part)|$($_.Section)" }
    foreach ($g in $groups) {
        if ($g.Count -gt $L.Section) {
            # Section name with proper curly quotes
            $sectionName = ($g.Name -split '\|', 2)[1]
            $msg = "[práh-sekce] sekce " + [char]0x201E + $sectionName + [char]0x201D + " má $($g.Count) položek > $($L.Section)"
            $warn.Add($msg)
        }
    }
    if ($over) {
        $warn.Add("[práh-soubor] $($pb.LineCount) řádků > $($L.File) — kandidát na eskalační report")
        if ($null -eq $pb.Ratchet) { $hard.Add('[ráčna-chybí] soubor nad prahem nemá ráčnový komentář na druhém řádku') }
        elseif ($pb.LineCount -gt $pb.Ratchet.Baseline) { $hard.Add("[ráčna-růst] $($pb.LineCount) řádků > baseline $($pb.Ratchet.Baseline) bez zaznamenaného rozhodnutí") }
    } elseif ($null -ne $pb.Ratchet) {
        $warn.Add('[ráčna-zbytečná] soubor je pod prahem — ráčnový komentář lze odstranit')
    }
    [pscustomobject]@{ Playbook = $Playbook; Shape = $pb.Shape; Lines = $pb.LineCount; Hard = $hard.ToArray(); Warn = $warn.ToArray() }
}

function Test-UmsPlaybookTree([string] $RepoRoot, [string] $Under = '') {
    $L = $script:UmsPlaybookLimits
    $tree = Get-UmsMbTree $RepoRoot
    $scope = @($tree | Where-Object { $_.Playbook -and (($Under -eq '') -or ($_.Owner -eq $Under) -or $_.Owner.StartsWith("$Under/")) })
    foreach ($mb in $scope) {
        $file = Test-UmsPlaybookShape (Join-Path $RepoRoot $mb.Playbook)
        $hard = [Collections.Generic.List[string]]::new(); foreach ($h in $file.Hard) { $hard.Add($h) }
        $warn = [Collections.Generic.List[string]]::new(); foreach ($w in $file.Warn) { $warn.Add($w) }
        $chain = Get-UmsPlaybookChain $RepoRoot $mb.Dir
        if ($chain.TotalLines -gt $L.Chain) {
            $conforming = $true
            foreach ($s in $chain.Segments) {
                $pb = Read-UmsPlaybook (Join-Path $RepoRoot $s.Playbook)
                if ($pb.Shape -ne 'new' -or $pb.Ratchet -or $pb.LineCount -gt $L.File) { $conforming = $false }
            }
            $hint = if ($conforming) { ' — úseky jsou v novém tvaru a v prahu: konsoliduj (přesun k potomkovi, přeřazení do projektu, sloučení), jinak eskalační report' } else { '' }
            $warn.Add("[práh-řetězec] řetězec $($mb.Dir) má $($chain.TotalLines) řádků > $($L.Chain)$hint")
        }
        [pscustomobject]@{ Mb = $mb.Dir; Playbook = $mb.Playbook; Hard = $hard.ToArray(); Warn = $warn.ToArray(); ChainLines = $chain.TotalLines }
    }
}
