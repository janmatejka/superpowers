#Requires -Version 7
<#
.SYNOPSIS
    Line-multiset preservation check for the contract split (design UMS-3551,
    "Postup přesunu"). Dot-source, then call Compare-UmsLineMultiset or
    Test-UmsContractMove.
#>
Set-StrictMode -Version Latest

function Compare-UmsLineMultiset([string[]] $Original, [string[]] $Candidate) {
    $budget = [System.Collections.Generic.Dictionary[string, int]]::new([StringComparer]::Ordinal)
    foreach ($line in @($Original)) {
        $t = ([string] $line).TrimEnd()
        if ($t -eq '') { continue }
        if ($budget.ContainsKey($t)) { $budget[$t]++ } else { $budget[$t] = 1 }
    }
    $extra = @()
    foreach ($line in @($Candidate)) {
        $t = ([string] $line).TrimEnd()
        if ($t -eq '') { continue }
        if ($budget.ContainsKey($t) -and $budget[$t] -gt 0) { $budget[$t]-- } else { $extra += $t }
    }
    $missing = @()
    foreach ($k in $budget.Keys) { for ($i = 0; $i -lt $budget[$k]; $i++) { $missing += $k } }
    return @{ Missing = @($missing); Extra = @($extra) }
}

function Test-UmsContractMove {
    param(
        [Parameter(Mandatory)] [string] $RepoRoot,
        [Parameter(Mandatory)] [string] $SnapshotRef,
        [Parameter(Mandatory)] [string[]] $TargetGlobs,
        [string] $AllowExtraPattern = '^(# |Part of contract|Doklad: )'
    )
    $snap = & git -C $RepoRoot show $SnapshotRef 2>$null
    if ($LASTEXITCODE -ne 0) { throw "Snapshot '$SnapshotRef' nelze přečíst." }
    $original = @($snap)
    $candidate = @()
    foreach ($g in $TargetGlobs) {
        foreach ($f in @(Get-ChildItem -Path (Join-Path $RepoRoot $g) -File -ErrorAction SilentlyContinue)) {
            $candidate += @(Get-Content -LiteralPath $f.FullName -Encoding utf8)
        }
    }
    $cmp = Compare-UmsLineMultiset $original $candidate
    $unexpected = @($cmp.Extra | Where-Object { $_ -notmatch $AllowExtraPattern })
    return @{
        Ok              = (@($cmp.Missing).Count -eq 0 -and $unexpected.Count -eq 0)
        Missing         = @($cmp.Missing)
        Extra           = @($cmp.Extra)
        UnexpectedExtra = $unexpected
    }
}
