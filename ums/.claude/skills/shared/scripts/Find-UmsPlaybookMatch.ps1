#Requires -Version 7
# Dot-source this file. Language-neutral match of a candidate against the playbook chain:
# only identifiers in backticks are compared (contract/playbook-contract.md, "Harvest gate").
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'Get-UmsPlaybookChain.ps1')

function Get-UmsBacktickTokens([string] $Text) {
    @([regex]::Matches($Text, '`([^`]+)`') | ForEach-Object { ($_.Groups[1].Value.Trim() -replace '\s+', ' ').ToLowerInvariant() } | Where-Object { $_ } | Sort-Object -Unique)
}

function Find-UmsPlaybookMatch([string] $Text, [string] $RepoRoot, [string] $Mb, [int] $Top = 3) {
    $want = @(Get-UmsBacktickTokens $Text)
    if (-not $want.Count) { return @() }
    $chain = Get-UmsPlaybookChain $RepoRoot $Mb
    $hits = [Collections.Generic.List[object]]::new()
    foreach ($s in $chain.Segments) {
        $pb = Read-UmsPlaybook (Join-Path $RepoRoot $s.Playbook)
        foreach ($it in $pb.Items) {
            if ($it.StartLine -lt $s.StartLine -or $it.EndLine -gt $s.EndLine) { continue }
            $itemText = (@($pb.Lines[($it.StartLine - 1)..($it.EndLine - 1)]) -join ' ')
            $shared = @(Get-UmsBacktickTokens $itemText | Where-Object { $want -contains $_ })
            if ($shared.Count) {
                $hits.Add([pscustomobject]@{ Mb = $s.Mb; Playbook = $s.Playbook; ItemId = $it.Id; Title = $it.Title; Score = $shared.Count; Shared = $shared })
            }
        }
    }
    @($hits | Sort-Object -Property @{ Expression = 'Score'; Descending = $true }, @{ Expression = 'ItemId'; Descending = $false } | Select-Object -First $Top)
}
