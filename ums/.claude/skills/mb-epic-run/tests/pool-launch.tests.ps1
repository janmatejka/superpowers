Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '_assert.ps1')
$ErrorActionPreference = 'Stop'
# Ruling A: point the seam at a .cmd shim, not at argv-probe.ps1 directly.
# Start-Process ShellExecutes a bare .ps1 on Windows instead of running it, so
# the DIRECT adapter's probe may never write its output. The terminal
# adapter's stand-in below is invoked via PowerShell's native `&` operator,
# which runs a .ps1 fine on its own — the shim is strictly required only for
# the direct adapter. Using it for both is still right: it keeps the two
# cases symmetric and the shim was verified (before this suite was trusted)
# to round-trip a real multi-word prompt as ONE argument through both
# invocation shapes, so there is no cost to sharing it.
$Probe = Join-Path $PSScriptRoot 'stubs\argv-probe.cmd'
# The raw, un-shimmed probe — used ONLY for Gate 3 (fix round 1): a target
# Start-Process genuinely cannot launch. Handing this .ps1 straight to the
# direct adapter's Start-Process -FilePath (bypassing the shim on purpose)
# is exactly Ruling A's ShellExecute failure, which -PassThru now turns into
# a checkable "nothing started" fact instead of a silent no-op.
$UnshimmedProbe = Join-Path $PSScriptRoot 'stubs\argv-probe.ps1'
$NewFixture = Join-Path $PSScriptRoot 'new-pool-fixture.ps1'

# The exact prompt shape the design mandates: one quoted argument, Czech
# diacritics, an em dash, and NO semicolon (wt.exe treats it as its own
# command separator).
$RealPrompt = 'Převezmi tiket UMS-3488 — zbytek si najdi v ledgeru epiku, cesta memory-bank/epics/ums_3400/ledger.md'

# Cases that must NEVER produce a probe file (a hard input error, or an
# unavailable adapter, refused before any spawn) get a SHORT deadline: they
# would otherwise each burn the full default timeout waiting for a file that
# provably cannot appear, adding real time to a suite whose actual work is
# under a second.
$NoSpawnWaitMs = 400

function Wait-ForProbe([string] $Path, [int] $TimeoutMs = 5000) {
    # The direct adapter starts a DETACHED process; a fixed sleep is the
    # classic source of intermittent failures (too short on a slow machine,
    # too long on every run). Poll for the probe's output file AND require it
    # to parse as JSON before trusting it — Set-Content can create the file
    # before the write of its content completes, so mere existence does not
    # guarantee complete, parseable content. Returns the parsed object, or
    # $null if nothing parseable appeared before the deadline.
    $deadline = (Get-Date).AddMilliseconds($TimeoutMs)
    while ((Get-Date) -lt $deadline) {
        if (Test-Path -LiteralPath $Path) {
            $raw = $null
            try { $raw = Get-Content -LiteralPath $Path -Raw } catch { }
            if (-not [string]::IsNullOrWhiteSpace($raw)) {
                try { return ($raw | ConvertFrom-Json) } catch { }
            }
        }
        Start-Sleep -Milliseconds 100
    }
    return $null
}

function Invoke-Launch([string] $Slot, [string] $Adapter, [string] $Prompt, [string] $Claude, [string] $Terminal = '', [int] $WaitMs = 5000) {
    $out = Join-Path ([IO.Path]::GetTempPath()) ('mbprobe-' + [guid]::NewGuid().ToString('N') + '.json')
    $env:MBPOOL_PROBE_OUT = $out
    $a = @('-SlotPath', $Slot, '-Prompt', $Prompt, '-Ticket', 'UMS-3488', '-Adapter', $Adapter, '-ClaudeCommand', $Claude)
    if ($Terminal) { $a += @('-TerminalCommand', $Terminal) }
    $r = Invoke-PoolScript 'pool-launch.ps1' $a
    $probe = Wait-ForProbe $out $WaitMs
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
    # Gate 4 (fix round 1): -d $SlotPath is the terminal adapter's ONLY
    # guarantee that the session starts in the right slot, and the literal
    # `-d` token vanishes from `argv` before the probe can record it (its
    # `[Parameter(...)]` makes it an "advanced" script, and `-d` binds to the
    # common parameter `-Debug` instead). `cmdLine` is the raw OS-level argv,
    # untouched by that binder — assert BOTH that `-d` is present there AND
    # that the token immediately after it is the correct slot path, so a
    # session landing in the orchestrator's own directory would be caught.
    $cmdLine = @($script:r2.Probe.cmdLine)
    $dIndex = [array]::IndexOf($cmdLine, '-d')
    Assert-True ($dIndex -ge 0) 'the terminal adapter''s raw command line carries the -d flag (Gate 4)'
    if ($dIndex -ge 0 -and ($dIndex + 1) -lt $cmdLine.Count) {
        Assert-Eq (([string] $cmdLine[$dIndex + 1]) -replace '\\', '/') ($slot -replace '\\', '/') '-d is immediately followed by the correct slot path (Gate 4)'
    } else {
        Assert-True $false '-d has a following token naming the slot path (Gate 4)'
    }

    # --- case 5: a prompt containing a semicolon is REFUSED before any spawn
    Invoke-WithFakeSessionEnv {
        $script:r3 = Invoke-Launch $slot 'terminal' 'do this; and that' $Probe $Probe $NoSpawnWaitMs
    }
    Assert-Eq $script:r3.Code 1 'a semicolon in the prompt is a hard input error'
    Assert-Match $script:r3.Out 'semicolon' 'the refusal names the semicolon'
    Assert-True ($null -eq $script:r3.Probe) 'nothing was spawned'

    # --- case 5b (Gate 1, fix round 1): a double quote is REFUSED before any spawn
    Invoke-WithFakeSessionEnv {
        $script:r3b = Invoke-Launch $slot 'direct' 'read the "ledger" file now' $Probe '' $NoSpawnWaitMs
    }
    Assert-Eq $script:r3b.Code 1 'a double quote in the prompt is a hard input error (Gate 1)'
    Assert-Match $script:r3b.Out 'double quote' 'the refusal names the double quote'
    Assert-True ($null -eq $script:r3b.Probe) 'nothing was spawned for a quote-bearing prompt'

    # --- case 5c (Gate 1, fix round 1): a trailing backslash is REFUSED before any spawn
    Invoke-WithFakeSessionEnv {
        $script:r3c = Invoke-Launch $slot 'direct' 'memory-bank\epics\ums_3400\' $Probe '' $NoSpawnWaitMs
    }
    Assert-Eq $script:r3c.Code 1 'a trailing backslash in the prompt is a hard input error (Gate 1)'
    Assert-Match $script:r3c.Out 'backslash' 'the refusal names the backslash'
    Assert-True ($null -eq $script:r3c.Probe) 'nothing was spawned for a trailing-backslash prompt'

    # --- case 5d (rider): the 600-character prompt ceiling is enforced
    Invoke-WithFakeSessionEnv {
        $script:r3d = Invoke-Launch $slot 'direct' ('x' * 601) $Probe '' $NoSpawnWaitMs
    }
    Assert-Eq $script:r3d.Code 1 'a prompt over the 600-character ceiling is a hard input error'
    Assert-True ($null -eq $script:r3d.Probe) 'nothing was spawned for an over-length prompt'

    # --- case 6: a missing terminal command is `unavailable`, never a fallback
    Invoke-WithFakeSessionEnv {
        $script:r4 = Invoke-Launch $slot 'terminal' $RealPrompt $Probe (Join-Path $PSScriptRoot 'stubs\does-not-exist.exe') $NoSpawnWaitMs
    }
    Assert-Eq $script:r4.Code 2 'a missing terminal command exits 2'
    # \r? : same Out-String CRLF-join artifact as case 1, see the comment there.
    Assert-Match $script:r4.Out '(?m)^unavailable\r?$' 'the status word is unavailable'
    Assert-NotMatch $script:r4.Out 'launched' 'the script NEVER falls back to another adapter'
    Assert-True ($null -eq $script:r4.Probe) 'no hidden fallback spawn happened'

    # --- case 6b (Gate 3, fix round 1): Start-Process cannot actually launch
    # the given target (Ruling A's ShellExecute-of-a-.ps1 failure, deliberately
    # NOT routed through the shim here) must report failed, never launched.
    Invoke-WithFakeSessionEnv {
        $script:r4b = Invoke-Launch $slot 'direct' $RealPrompt $UnshimmedProbe '' $NoSpawnWaitMs
    }
    Assert-Eq $script:r4b.Code 1 'a target Start-Process cannot actually launch reports failed, not launched (Gate 3)'
    Assert-NotMatch $script:r4b.Out '(?m)^launched\r?$' 'no false launched report when nothing actually started'
    Assert-True ($null -eq $script:r4b.Probe) 'nothing was actually started (Gate 3)'

    # --- case 7: a slot path that does not exist is an input error
    $r5 = Invoke-Launch (Join-Path $fx.Root 'nope') 'direct' $RealPrompt $Probe '' $NoSpawnWaitMs
    Assert-Eq $r5.Code 1 'a non-existent slot path is an input error'
}
finally {
    Remove-Item -Recurse -Force $fx.Root -ErrorAction SilentlyContinue
    Remove-Item -Path 'Env:MBPOOL_PROBE_OUT' -ErrorAction SilentlyContinue
}

Complete-Tests
