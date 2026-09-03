# Dependency-free assertion helper for mb-epic-run tests.
Set-StrictMode -Version Latest
$script:Failures = 0
$script:Total = 0
function Assert-True([bool] $cond, [string] $msg) {
    $script:Total++
    if ($cond) { Write-Host "  ok  : $msg" } else { Write-Host "  FAIL: $msg"; $script:Failures++ }
}
function Assert-Match([string] $text, [string] $pattern, [string] $msg) {
    Assert-True ([bool]([regex]::IsMatch($text, $pattern))) "$msg  [/$pattern/]"
}
function Assert-NotMatch([string] $text, [string] $pattern, [string] $msg) {
    Assert-True (-not [regex]::IsMatch($text, $pattern)) "$msg  [must NOT match /$pattern/]"
}
function Assert-Eq($actual, $expected, [string] $msg) {
    Assert-True ($actual -eq $expected) "$msg  (got '$actual', want '$expected')"
}
function Complete-Tests {
    Write-Host ""
    if ($script:Failures -gt 0) { Write-Host "$script:Failures/$script:Total FAILED"; exit 1 }
    Write-Host "$script:Total passed"; exit 0
}

# Runs a pool script out-of-process; returns @{ Out=<stdout>; Code=<exit code> }.
function Invoke-PoolScript([string] $Name, [string[]] $ScriptArgs) {
    $script = Join-Path $PSScriptRoot "..\scripts\$Name"
    try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
    $out = & pwsh -NoProfile -File $script @ScriptArgs 2>&1 | Out-String
    return @{ Out = $out; Code = $LASTEXITCODE }
}

# --- fixture helpers shared by every suite in this tests/ directory --------

# -NoNewline everywhere below: Set-Content otherwise appends the HOST'S own
# newline (CRLF on Windows) after the -Value string even though the string
# already ends in a literal `n — the fixture's own base commit of
# memory-bank/context.md (new-pool-fixture.ps1) is git-normalized to LF on
# `git add` (eol=lf), so a REWRITE with the platform terminator attached would
# not byte-match the committed blob and every "clean IDLE slot" case would be
# spuriously dirty even though the content is logically identical.
function Set-SlotMarker([string] $Slot) {
    $dir = Join-Path $Slot '.superpowers'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    Set-Content -LiteralPath (Join-Path $dir 'pool-slot') -Value '' -NoNewline -Encoding utf8
}
function Set-SlotPin([string] $Slot, [string] $Slug, [string] $Jira = 'UMS-0000') {
    $mb = Join-Path $Slot 'memory-bank'
    New-Item -ItemType Directory -Force -Path $mb | Out-Null
    $text = "# Context`n`n## Active Work`n`n- **Jira:** $Jira`n- **Target MB Pin:** memory-bank/`n- **Work item:** $Slug`n"
    Set-Content -LiteralPath (Join-Path $mb 'context.md') -Value $text -NoNewline -Encoding utf8
}
function Set-SlotIdle([string] $Slot) {
    $mb = Join-Path $Slot 'memory-bank'
    New-Item -ItemType Directory -Force -Path $mb | Out-Null
    Set-Content -LiteralPath (Join-Path $mb 'context.md') `
        -Value "# Context`n`n## Active Work`n`n(No active work - IDLE phase)`n" -NoNewline -Encoding utf8
}
function New-SlotLedger([string] $Slot, [string] $PlanBase, [string] $LastLine) {
    $dir = Join-Path (Join-Path (Join-Path $Slot '.superpowers') 'sdd') $PlanBase
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    Set-Content -LiteralPath (Join-Path $dir 'progress.md') -Value "# progress`n`n$LastLine`n" -NoNewline -Encoding utf8
}
