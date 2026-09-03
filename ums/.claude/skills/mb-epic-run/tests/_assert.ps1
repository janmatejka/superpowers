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

# Invoke-WithFakeSessionEnv and Invoke-WithoutSessionEnv are exact mirrors —
# one SETS the nine variables a spawned child would inherit from an
# orchestrator session, the other REMOVES the agent-session marker variables —
# and both restore afterward. Their scriptblock parameter names ($EnvBody,
# $NoEnvBody) differ from each other and from every OTHER wrapper function's
# scriptblock parameter in this file ON PURPOSE: `& $X` inside a scriptblock
# binds dynamically to the $X of the FUNCTION currently executing, not to the
# `$X` in lexical scope at the point the scriptblock was written — so if two
# functions in a wrapper chain share a parameter name, the inner `& $X` re-enters
# the outer function's own body instead of running the caller's block, and
# recurses until the stack overflows. This bit a chain of two same-named
# wrappers in this codebase (Task 3's playbook candidates); do not reintroduce
# it here by "tidying" these two names to match.

# Sets the nine variables a child would inherit from an orchestrator session,
# runs $EnvBody, and restores.
function Invoke-WithFakeSessionEnv([scriptblock] $EnvBody) {
    $names = @('CLAUDE_CODE_CHILD_SESSION','CLAUDE_CODE_SESSION_ID','CLAUDE_CODE_BRIDGE_SESSION_ID',
               'CLAUDE_CODE_MESSAGING_SOCKET','CLAUDE_CODE_MESSAGING_TOKEN','CLAUDE_CODE_SSE_PORT',
               'CLAUDE_PID','CLAUDE_CODE_ENTRYPOINT','NO_COLOR',
               'CLAUDECODE','CLAUDE_CODE_USE_POWERSHELL_TOOL')
    $saved = @{}
    foreach ($n in $names) { $saved[$n] = [Environment]::GetEnvironmentVariable($n) }
    try {
        foreach ($n in $names) { Set-Item -Path "Env:$n" -Value 'inherited' }
        & $EnvBody
    }
    finally {
        foreach ($n in $names) {
            if ($null -eq $saved[$n]) { Remove-Item -Path "Env:$n" -ErrorAction SilentlyContinue }
            else { Set-Item -Path "Env:$n" -Value $saved[$n] }
        }
    }
}

# Mirror of Invoke-WithFakeSessionEnv: REMOVES the agent-session marker
# variables (MB_AGENT_SESSION, AI_AGENT, CLAUDECODE) instead of setting them,
# runs $NoEnvBody, and restores. This suite does not call it — it exists for
# pool-provision.ps1's operator guard (Task 5), whose cases need an
# environment where these markers are genuinely ABSENT even though the suite
# itself runs from inside an agent session where all three are already set
# and would otherwise be inherited by the child pwsh under test.
function Invoke-WithoutSessionEnv([scriptblock] $NoEnvBody) {
    $names = @('MB_AGENT_SESSION', 'AI_AGENT', 'CLAUDECODE')
    $saved = @{}
    foreach ($n in $names) { $saved[$n] = [Environment]::GetEnvironmentVariable($n) }
    try {
        foreach ($n in $names) { Remove-Item -Path "Env:$n" -ErrorAction SilentlyContinue }
        & $NoEnvBody
    }
    finally {
        foreach ($n in $names) {
            if ($null -eq $saved[$n]) { Remove-Item -Path "Env:$n" -ErrorAction SilentlyContinue }
            else { Set-Item -Path "Env:$n" -Value $saved[$n] }
        }
    }
}
