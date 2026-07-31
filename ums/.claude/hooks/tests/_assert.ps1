# Dependency-free assertion helper for guard-git-push tests.
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
# Pipes a JSON payload into the hook; returns its stdout (empty = allowed).
function Invoke-Hook([string] $PayloadJson) {
    $hook = Join-Path $PSScriptRoot '..\guard-git-push.mjs'
    try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
    return ($PayloadJson | & node $hook | Out-String).Trim()
}
