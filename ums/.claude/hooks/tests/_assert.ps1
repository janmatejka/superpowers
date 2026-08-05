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

# Additive, NOT a replacement for Invoke-Hook: the whole existing suite is
# built on "empty stdout = allowed" via Invoke-Hook, and that must keep
# working unchanged. But stdout-only is blind to the one failure mode the
# fail-open assertions care about most — a thrown, uncaught exception also
# produces empty/no stdout (no JSON gets written) and would read as
# "allowed" exactly like a clean pass. This variant additionally returns the
# exit code and stderr text, so a case whose whole point is "must not throw"
# can actually check that, instead of asserting a stdout shape that a crash
# would satisfy by accident. Use this ONLY for new non-throw assertions.
function Invoke-HookFull([string] $PayloadJson) {
    $hook = Join-Path $PSScriptRoot '..\guard-git-push.mjs'
    try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
    $errFile = Join-Path ([IO.Path]::GetTempPath()) ("mbhookerr-" + [guid]::NewGuid().ToString('N') + '.txt')
    try {
        $stdout = ($PayloadJson | & node $hook 2> $errFile | Out-String).Trim()
        $code = $LASTEXITCODE
        $stderr = ''
        if (Test-Path -LiteralPath $errFile) {
            $stderr = (Get-Content -LiteralPath $errFile -Raw -ErrorAction SilentlyContinue)
            if (-not $stderr) { $stderr = '' }
        }
        return @{ Out = $stdout; Code = $code; Err = $stderr }
    }
    finally {
        Remove-Item -LiteralPath $errFile -Force -ErrorAction SilentlyContinue
    }
}
