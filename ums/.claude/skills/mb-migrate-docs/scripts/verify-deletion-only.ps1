#Requires -Version 7
<#
.SYNOPSIS
Verifies that an agent only deleted and reordered lines of a Memory Bank
document — that it authored nothing.

.DESCRIPTION
The original is the STAGED blob (git show :<file>), written there by
migrate-mb-docs.ps1 -Apply; the candidate is the working-tree file the agent
edited. Every non-empty candidate line must occur verbatim among the original's
non-empty lines, the candidate must not be longer than the original, must not
be empty and must keep its H1 heading. On violation restore with
'git checkout -- <file>'.

.PARAMETER RepoPath
Repository root.

.PARAMETER File
Repo-relative path of the document to check.

.OUTPUTS
Czech verdict. Exit: 0 = passed, 1 = input/script failure, 2 = violation.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $RepoPath,
    [Parameter(Mandatory)] [string] $File
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }

$originalText = (& git -C $RepoPath show ":$File") -join "`n"
if ($LASTEXITCODE -ne 0) {
    Write-Error "Soubor '$File' není ve stagingu — verifikátor nemá s čím porovnávat."; exit 1
}
$original = @($originalText -split "`r?`n")
# NB: Get-Content returns a bare scalar string, not a one-element array, when
# the file has exactly one line — under Set-StrictMode -Version Latest a
# scalar string has no .Count property, so "$candidate.Count" below throws
# PropertyNotFoundException for a single-line candidate (confirmed by
# reproduction). Wrapping in @() forces an array in every case, including the
# empty-file case where Get-Content returns $null.
$candidate = @(Get-Content -LiteralPath (Join-Path $RepoPath $File))

$origSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($line in $original) { [void] $origSet.Add($line.TrimEnd()) }

$violations = @()
foreach ($line in $candidate) {
    $t = $line.TrimEnd()
    if ($t -eq '') { continue }
    if (-not $origSet.Contains($t)) { $violations += $t }
}

# --- structural checks beyond the per-line set membership --------------------
# The set check alone lets a duplicated original line through (it is still a
# member of the set) even though the candidate now carries more text than the
# original ever had — catch that here, by count, not by content.
$origNonEmptyCount = @($original | Where-Object { $_.TrimEnd() -ne '' }).Count
$candNonEmptyCount = @($candidate | Where-Object { $_.TrimEnd() -ne '' }).Count

if ($candidate.Count -gt $original.Count) {
    $violations += 'Výstup má víc řádků než vstup'
}

if ($candNonEmptyCount -eq 0) {
    $violations += 'Výstupní soubor je prázdný'
}

$origHasH1 = [bool]($original | Where-Object { $_ -match '^#\s' })
$candHasH1 = [bool]($candidate | Where-Object { $_ -match '^#\s' })
if ($origHasH1 -and -not $candHasH1) {
    $violations += 'Nadpis H1 z originálu chybí ve výstupu'
}

# --- verdict -------------------------------------------------------------------
if (@($violations).Count -gt 0) {
    Write-Output '❌ Verifikace mazacího režimu SELHALA'
    Write-Output ''
    Write-Output "Soubor: $File"
    Write-Output ''
    Write-Output 'Nálezy:'
    $shown = @($violations | Select-Object -First 10)
    foreach ($v in $shown) { Write-Output "- $v" }
    if (@($violations).Count -gt 10) {
        Write-Output "- ... a dalších $(@($violations).Count - 10) porušení"
    }
    Write-Output ''
    Write-Output "Obnov mechanickou verzi: git checkout -- $File"
    exit 2
}

$removed = $origNonEmptyCount - $candNonEmptyCount
Write-Output '✅ Verifikace mazacího režimu prošla'
Write-Output ''
Write-Output "Soubor: $File"
Write-Output "Ubráno neprázdných řádků: $removed z $origNonEmptyCount"

if ($origNonEmptyCount -gt 0) {
    $ratio = $removed / $origNonEmptyCount
    if ($ratio -gt 0.5) {
        Write-Output ''
        Write-Output "VAROVÁNÍ: úbytek řádků přesáhl 50 % ($([Math]::Round($ratio * 100, 1)) %) — zkontrolujte ručně, zda nešlo o ztrátu obsahu."
    }
}

exit 0
