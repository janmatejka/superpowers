#Requires -Version 7
<#
.SYNOPSIS
Verifies that an agent only deleted and reordered lines of a Memory Bank
document — that it authored nothing.

.DESCRIPTION
The original is the STAGED blob (git show :<file>), written there by
migrate-mb-docs.ps1 -Apply; the candidate is the working-tree file the agent
edited. Formalised as MULTISET containment: every non-empty candidate line
must occur in the original no more times than it occurred there (reordering
is unconstrained; an original line consumed once cannot be reused to justify
a second, duplicated occurrence in the candidate). The candidate must not be
empty and must keep its H1 heading — both checked fence-aware, so a line
starting with "#" inside a fenced code block never counts as a heading on
either side. On violation restore with 'git checkout -- <file>'.

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
# scalar string has no .Count property, so "$candidate.Count" would throw
# PropertyNotFoundException for a single-line candidate (confirmed by
# reproduction). Wrapping in @() forces an array in every case, including the
# empty-file case where Get-Content returns $null.
#
# The working-tree file itself may be GONE entirely — an agent deleting the
# whole document is the maximal case of "authored nothing survives", not a
# script failure. Test-Path first and fall back to an empty candidate instead
# of letting Get-Content throw (it would, under $ErrorActionPreference =
# 'Stop', with an English stack trace and exit 1 — the wrong verdict for what
# is really the most extreme violation this tool exists to catch).
$candidatePath = Join-Path $RepoPath $File
if (Test-Path -LiteralPath $candidatePath) {
    $candidate = @(Get-Content -LiteralPath $candidatePath)
} else {
    $candidate = @()
}

# --- BOM normalisation ---------------------------------------------------------
# 'git show' returns the STAGED BLOB'S RAW BYTES: if migrate-mb-docs.ps1 (or
# whatever wrote the staged version) left a UTF-8 BOM (U+FEFF) at the start of
# the file, that character survives into $original's first line. Get-Content
# on the working-tree candidate, by contrast, detects and STRIPS a BOM
# automatically. Left unstripped, this breaks comparison in BOTH directions:
# a byte-identical candidate is rejected (the BOM-prefixed original first line
# is not in the candidate's line set — a real, present line gets misreported
# as invented) AND, separately, the H1 guard silently disarms itself (a
# BOM-prefixed "# Heading" does not match '^#\s', so a genuinely deleted H1
# goes unnoticed). Strip U+FEFF from the start of the first line on BOTH
# sides before anything else touches them — defensively on the candidate too,
# in case some future caller feeds it a file Get-Content did not normalise.
function Remove-LeadingBom([string[]] $Lines) {
    $copy = $Lines.Clone()
    if ($copy.Count -gt 0 -and $copy[0].Length -gt 0 -and $copy[0][0] -eq [char]0xFEFF) {
        $copy[0] = $copy[0].Substring(1)
    }
    return $copy
}
# NB: "return $copy" is not enough on its own — PowerShell unwraps a
# ONE-ELEMENT collection written to the pipeline back down to its bare
# scalar element (confirmed by reproduction: a single-line $candidate came
# back out of this function as a plain [string], not a one-element
# [object[]], silently losing the array-ness $candidate = @(Get-Content ...)
# had just established). Wrapping the CALL SITE in @() — the same defensive
# idiom already used for Get-Content above — re-forces an array regardless
# of what the function handed back, so a later ".Count"/index/iteration
# access never regresses into the PropertyNotFoundException this exact
# pattern already caused once in this script (see the Get-Content NB above).
$original = @(Remove-LeadingBom $original)
$candidate = @(Remove-LeadingBom $candidate)

# --- fence-aware H1 detection --------------------------------------------------
# Mirrors migrate-mb-docs.ps1's own fence tracking (Get-ProductBody): a line
# that merely LOOKS like a heading because it sits inside a ```-fenced code
# block (e.g. a shell comment "# do the thing") must never count as the
# document's H1 — on EITHER side. Without this, deleting the real H1 while a
# fenced pseudo-heading survives silently passes verification.
function Test-HasRealH1([string[]] $Lines) {
    $inFence = $false
    foreach ($line in $Lines) {
        if ($line -match '^\s*```') { $inFence = -not $inFence; continue }
        if (-not $inFence -and $line -match '^#\s') { return $true }
    }
    return $false
}

# --- multiset containment: the correct formalisation of "delete/reorder only"
# NB (plan-author override, fix round 1): the brief's original core checked
# per-line SET membership plus "$candidate.Count -le $original.Count" and
# claimed the count guard "catches the duplication that the set check alone
# lets through". That claim is false and has been removed rather than kept:
# a candidate that deletes five original lines and then repeats one SURVIVING
# line five times keeps the total line count at or below the original and
# every individual line is still a member of the original's set, so the old
# check passed it with exit 0 even though real content was invented via
# duplication. A Dictionary[string,int] budget (each original non-empty line
# spendable exactly as many times as it appeared) is the correct proof of
# containment: reordering is free, but no line may be consumed more times
# than the original actually offered it. Empty lines carry no content and are
# exempt entirely — neither budgeted here nor charged against the candidate
# below — so blank-line churn (adding or removing blank lines only) can never
# by itself be a violation.
$origDict = [System.Collections.Generic.Dictionary[string, int]]::new([StringComparer]::Ordinal)
foreach ($line in $original) {
    $t = $line.TrimEnd()
    if ($t -eq '') { continue }
    if ($origDict.ContainsKey($t)) { $origDict[$t]++ } else { $origDict[$t] = 1 }
}

$violations = @()
foreach ($line in $candidate) {
    $t = $line.TrimEnd()
    if ($t -eq '') { continue }
    if ($origDict.ContainsKey($t) -and $origDict[$t] -gt 0) {
        $origDict[$t]--
    } else {
        $violations += $t
    }
}

# --- structural checks beyond multiset containment ---------------------------
# Under containment (no violations above), every candidate non-empty line was
# paid for out of the original's own budget, so candNonEmpty <= origNonEmpty
# is now a STRUCTURAL guarantee, not merely observed — a negative "removed"
# count below is impossible when the verdict is a pass. There is
# deliberately no separate "candidate longer than original" guard anymore:
# multiset containment already subsumes it, and the old count-only guard used
# to fire on blank-line churn alone (see the NB above) — a false rejection of
# a change that authored nothing.
$origNonEmptyCount = @($original | Where-Object { $_.TrimEnd() -ne '' }).Count
$candNonEmptyCount = @($candidate | Where-Object { $_.TrimEnd() -ne '' }).Count

if ($candNonEmptyCount -eq 0) {
    $violations += 'Výstupní soubor je prázdný'
}

$origHasH1 = Test-HasRealH1 $original
$candHasH1 = Test-HasRealH1 $candidate
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
