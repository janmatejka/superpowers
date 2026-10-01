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

# Runs a PowerShell hook the way Claude Code does on Windows: a windowless child
# (CREATE_NO_WINDOW gives it a fresh console with the OEM code page, e.g. 852,
# not the parent's), stdin piped, stdout redirected and read as RAW BYTES. The
# `& pwsh ... | Out-String` capture used elsewhere decodes with the same console
# code page the child encoded with, so it round-trips and hides a code-page
# corruption that the harness's UTF-8 JSON parser does see.
function Invoke-PwshHookRaw([string] $Script, [string] $WorkDir, [string] $StdinText = '', [string[]] $ExtraArgs = @()) {
    $psi = [Diagnostics.ProcessStartInfo]::new('pwsh')
    foreach ($a in @('-NoProfile', '-File', $Script) + $ExtraArgs) { $psi.ArgumentList.Add($a) }
    $psi.WorkingDirectory = $WorkDir
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.Environment['CLAUDE_PROJECT_DIR'] = $WorkDir
    $p = [Diagnostics.Process]::Start($psi)
    $ms = [IO.MemoryStream]::new()
    $copy = $p.StandardOutput.BaseStream.CopyToAsync($ms)
    $errTask = $p.StandardError.ReadToEndAsync()
    $inBytes = [Text.UTF8Encoding]::new($false).GetBytes($StdinText)
    $p.StandardInput.BaseStream.Write($inBytes, 0, $inBytes.Length)
    $p.StandardInput.Close()
    $p.WaitForExit()
    $copy.Wait()
    return @{ Bytes = $ms.ToArray(); Code = $p.ExitCode; Err = $errTask.Result }
}

# Validates hook stdout bytes the way the harness consumes them: strict UTF-8,
# then a strict JSON parser (System.Text.Json rejects raw control characters in
# strings, as JavaScriptCore does: "JSON Parse error: Unterminated string").
# Returns @{ Ok; Error; Json } — Json is the ConvertFrom-Json object when Ok.
function Test-StrictHookJson([byte[]] $Bytes) {
    try {
        $text = [Text.UTF8Encoding]::new($false, $true).GetString($Bytes)
        $doc = [Text.Json.JsonDocument]::Parse($text)
        $doc.Dispose()
        return @{ Ok = $true; Error = ''; Json = ($text | ConvertFrom-Json) }
    }
    catch {
        $offset = -1
        for ($i = 0; $i -lt $Bytes.Length; $i++) { if (($Bytes[$i] -lt 0x20 -and $Bytes[$i] -notin 0x0d, 0x0a) -or $Bytes[$i] -gt 0x7e) { $offset = $i; break } }
        return @{ Ok = $false; Error = "$($_.Exception.Message) (first suspicious byte at offset $offset)"; Json = $null }
    }
}
