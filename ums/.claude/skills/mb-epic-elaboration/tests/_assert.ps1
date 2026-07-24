# Dependency-free assertion helper for epic-elaboration tests.
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
# Runs ledger-status.ps1 out-of-process; returns @{ Out=<stdout string>; Code=<exit code> }.
function Invoke-Ledger([string] $LedgerFile) {
    $script = Join-Path $PSScriptRoot '..\scripts\ledger-status.ps1'
    # Decode the child pwsh's UTF-8 stdout as UTF-8 (a CP852/non-UTF-8 console
    # would otherwise mojibake diacritics in captured output).
    try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
    $out = & pwsh -NoProfile -File $script -LedgerFile $LedgerFile 2>&1 | Out-String
    return @{ Out = $out; Code = $LASTEXITCODE }
}
