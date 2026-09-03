Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '_assert.ps1')
$ErrorActionPreference = 'Stop'
# Ruling A: point the seam at a .cmd shim, not at argv-probe.ps1 directly.
# Start-Process ShellExecutes a bare .ps1 on Windows instead of running it, so
# the probe may never write its output for EITHER adapter under test — the
# direct adapter calls Start-Process itself, and the terminal adapter's stand-in
# below is invoked the same way case 1 needs to prove works. The shim forwards
# through pwsh and was verified (before this suite was trusted) to round-trip a
# real multi-word prompt as ONE argument through both invocation shapes.
$Probe = Join-Path $PSScriptRoot 'stubs\argv-probe.cmd'
$NewFixture = Join-Path $PSScriptRoot 'new-pool-fixture.ps1'

# The exact prompt shape the design mandates: one quoted argument, Czech
# diacritics, an em dash, and NO semicolon (wt.exe treats it as its own
# command separator).
$RealPrompt = 'Převezmi tiket UMS-3488 — zbytek si najdi v ledgeru epiku, cesta memory-bank/epics/ums_3400/ledger.md'

function Wait-ForProbe([string] $Path, [int] $TimeoutMs = 5000) {
    # The direct adapter starts a DETACHED process; a fixed sleep is the
    # classic source of intermittent failures (too short on a slow machine,
    # too long on every run). Poll for the probe's output file instead.
    $deadline = (Get-Date).AddMilliseconds($TimeoutMs)
    while (-not (Test-Path -LiteralPath $Path) -and (Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 100
    }
    return (Test-Path -LiteralPath $Path)
}

function Invoke-Launch([string] $Slot, [string] $Adapter, [string] $Prompt, [string] $Claude, [string] $Terminal = '') {
    $out = Join-Path ([IO.Path]::GetTempPath()) ('mbprobe-' + [guid]::NewGuid().ToString('N') + '.json')
    $env:MBPOOL_PROBE_OUT = $out
    $a = @('-SlotPath', $Slot, '-Prompt', $Prompt, '-Ticket', 'UMS-3488', '-Adapter', $Adapter, '-ClaudeCommand', $Claude)
    if ($Terminal) { $a += @('-TerminalCommand', $Terminal) }
    $r = Invoke-PoolScript 'pool-launch.ps1' $a
    Wait-ForProbe $out | Out-Null
    $probe = $null
    if (Test-Path -LiteralPath $out) { $probe = Get-Content -LiteralPath $out -Raw | ConvertFrom-Json }
    Remove-Item -LiteralPath $out -Force -ErrorAction SilentlyContinue
    return @{ Out = $r.Out; Code = $r.Code; Probe = $probe }
}

$fx = & $NewFixture -SlotCount 1 -Label 'launch'
try {
    $slot = $fx.Slots[0]

    # --- case 1: the DIRECT adapter delivers the whole prompt as ONE argument
    Invoke-WithFakeSessionEnv {
        $script:r1 = Invoke-Launch $slot 'direct' $RealPrompt $Probe
    }
    Assert-Eq $script:r1.Code 0 'direct adapter reports launched (exit 0)'
    # \r? : Invoke-PoolScript captures a native process's stdout line-by-line
    # (each line already stripped of its own terminator) and Out-String then
    # rejoins them with [Environment]::NewLine, which is CRLF on Windows —
    # measured: .NET's multiline $ matches only immediately before a bare \n,
    # not before \r\n, so an unqualified '(?m)^launched$' never matches here
    # even though the script really did print "launched" alone on its line.
    # This is an artifact of the TEST capture, not of the script's real stdout.
    Assert-Match $script:r1.Out '(?m)^launched\r?$' 'direct adapter prints the status word launched'
    Assert-True ($null -ne $script:r1.Probe) 'the direct adapter actually started the probe'
    $argv = @($script:r1.Probe.argv)
    Assert-True ($argv -contains $RealPrompt) 'the whole prompt arrives as ONE argument, diacritics and em dash intact'
    Assert-True ($argv -contains '--name' -and $argv -contains 'UMS-3488') 'the session is named after the ticket'

    # --- case 2: the nine inherited variables are gone, the two kept remain
    foreach ($n in @('CLAUDE_CODE_CHILD_SESSION','CLAUDE_CODE_SESSION_ID','CLAUDE_CODE_BRIDGE_SESSION_ID',
                     'CLAUDE_CODE_MESSAGING_SOCKET','CLAUDE_CODE_MESSAGING_TOKEN','CLAUDE_CODE_SSE_PORT',
                     'CLAUDE_PID','CLAUDE_CODE_ENTRYPOINT','NO_COLOR')) {
        Assert-Eq $script:r1.Probe.env.$n $null "$n is stripped before the spawn"
    }
    Assert-Eq $script:r1.Probe.env.CLAUDECODE 'inherited' 'CLAUDECODE is deliberately KEPT (baton writer precondition, UserProfile marker carrier)'
    Assert-Eq $script:r1.Probe.env.CLAUDE_CODE_USE_POWERSHELL_TOOL 'inherited' 'CLAUDE_CODE_USE_POWERSHELL_TOOL is a user setting, not session state — kept'

    # --- case 3: the child starts in the SLOT, not in the orchestrator's cwd
    Assert-Match ($script:r1.Probe.cwd -replace '\\', '/') ([regex]::Escape(($slot -replace '\\', '/'))) 'the child runs with the slot as its working directory'

    # --- case 4: the TERMINAL adapter, same delivery through wt.exe's argv
    Invoke-WithFakeSessionEnv {
        $script:r2 = Invoke-Launch $slot 'terminal' $RealPrompt $Probe $Probe
    }
    Assert-Eq $script:r2.Code 0 'terminal adapter reports launched (exit 0)'
    Assert-True ($null -ne $script:r2.Probe) 'the terminal adapter actually invoked its terminal command'
    Assert-True (@($script:r2.Probe.argv) -contains $RealPrompt) 'the terminal adapter also delivers the prompt as ONE argument'

    # --- case 5: a prompt containing a semicolon is REFUSED before any spawn
    Invoke-WithFakeSessionEnv {
        $script:r3 = Invoke-Launch $slot 'terminal' 'do this; and that' $Probe $Probe
    }
    Assert-Eq $script:r3.Code 1 'a semicolon in the prompt is a hard input error'
    Assert-Match $script:r3.Out 'semicolon' 'the refusal names the semicolon'
    Assert-True ($null -eq $script:r3.Probe) 'nothing was spawned'

    # --- case 6: a missing terminal command is `unavailable`, never a fallback
    Invoke-WithFakeSessionEnv {
        $script:r4 = Invoke-Launch $slot 'terminal' $RealPrompt $Probe (Join-Path $PSScriptRoot 'stubs\does-not-exist.exe')
    }
    Assert-Eq $script:r4.Code 2 'a missing terminal command exits 2'
    # \r? : same Out-String CRLF-join artifact as case 1, see the comment there.
    Assert-Match $script:r4.Out '(?m)^unavailable\r?$' 'the status word is unavailable'
    Assert-NotMatch $script:r4.Out 'launched' 'the script NEVER falls back to another adapter'
    Assert-True ($null -eq $script:r4.Probe) 'no hidden fallback spawn happened'

    # --- case 7: a slot path that does not exist is an input error
    $r5 = Invoke-Launch (Join-Path $fx.Root 'nope') 'direct' $RealPrompt $Probe
    Assert-Eq $r5.Code 1 'a non-existent slot path is an input error'
}
finally {
    Remove-Item -Recurse -Force $fx.Root -ErrorAction SilentlyContinue
    Remove-Item -Path 'Env:MBPOOL_PROBE_OUT' -ErrorAction SilentlyContinue
}

Complete-Tests
