#Requires -Version 7
<#
.SYNOPSIS
Launches one Claude Code session in a pool slot, with the inherited session
environment stripped and the prompt delivered on argv.

.DESCRIPTION
Three measured failures on 2026-09-02 all LOOKED like success, and each had a
mechanical cause this script exists to remove.

1. A child inherits the orchestrator's own session variables and comes up as a
   CHILD session with transcript saving off, wearing the parent's identity and
   messaging pipe. Nine variables are therefore removed from this process
   before the spawn — and the removal must happen in the SAME invocation as the
   spawn, because every PowerShell tool call is a fresh shell inheriting from
   the parent again.
2. An argument list passed unquoted falls apart into single words and the
   session receives one word as its whole brief. The prompt is therefore passed
   as ONE argument, verbatim.
3. `Get-Process claude` returns a pid in all three failure modes, so process
   existence proves nothing. Proof is the harness's own session registry, and
   the caller obtains it by looking for the `--name <TICKET>` this script
   passes.

CLAUDECODE is deliberately NOT stripped, for two independent reasons: it is
part of the baton writer's precondition, so removing it would make every
spawned session refuse to write its own baton (losing the third execution
choice and the fifth stop class, silently); and on a -Scope UserProfile
deployment it is the ONLY carrier of the publication guarantee, because that
scope does not deploy settings.json and the pre-push hook then has nothing but
its CLAUDECODE/AI_AGENT fallback. CLAUDE_CODE_USE_POWERSHELL_TOOL stays too —
that is a user setting, not session state.

The variable list lives HERE and not in ums-repo.json: it is a property of the
harness, not of the repository (contract, "Repository Configuration").

.PARAMETER Adapter
`terminal` (wt.exe) or `direct` (Start-Process). Exactly one command each, no
hidden fallback chain: this script never decides which adapter to use and
never falls back to another one.

.OUTPUTS
One status word on its own line — launched | unavailable | failed — plus a
reason line. Exit: 0 = launched, 2 = unavailable, 1 = failed or input error.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string] $SlotPath,
    [Parameter(Mandatory = $true)] [string] $Prompt,
    [Parameter(Mandatory = $true)] [string] $Ticket,
    [Parameter(Mandatory = $true)] [ValidateSet('terminal', 'direct')] [string] $Adapter,
    [string] $ClaudeCommand = '',
    [string] $TerminalCommand = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }

$StripVars = @(
    'CLAUDE_CODE_CHILD_SESSION',      # child session: turns transcript saving off
    'CLAUDE_CODE_SESSION_ID',         # child pretends to be the same session
    'CLAUDE_CODE_BRIDGE_SESSION_ID',  # same, for the bridge
    'CLAUDE_CODE_MESSAGING_SOCKET',   # child would talk over the parent's pipe
    'CLAUDE_CODE_MESSAGING_TOKEN',    # same
    'CLAUDE_CODE_SSE_PORT',           # same
    'CLAUDE_PID',                     # parent identity
    'CLAUDE_CODE_ENTRYPOINT',         # parent's entry point marker
    'NO_COLOR'                        # session comes up monochrome under VS Code
)

function Write-Status([string] $Word, [string] $Reason, [int] $Code) {
    Write-Output $Word
    Write-Output $Reason
    exit $Code
}

if (-not (Test-Path -LiteralPath $SlotPath -PathType Container)) {
    Write-Status 'failed' "Slot path does not exist: $SlotPath" 1
}
if ([string]::IsNullOrWhiteSpace($Prompt)) {
    Write-Status 'failed' 'The prompt is empty.' 1
}
# Measured: wt.exe reads a semicolon as its own command separator, so a prompt
# carrying one is split into commands rather than delivered. Refused for BOTH
# adapters so the prompt text is adapter-independent.
if ($Prompt.Contains(';')) {
    Write-Status 'failed' 'The prompt contains a semicolon; wt.exe reads it as a command separator. Rewrite the prompt without one.' 1
}
# Measured (fix round 1): a double quote is NOT a safe character to carry
# through either adapter's delivery. On the direct adapter, wrapping the
# prompt in a literal quote pair for Start-Process (below) means an embedded
# quote either gets silently DELETED (`read the "ledger" file` arrives as
# `read the ledger file`, content corrupted with no error) or SPLITS the
# prompt into more than one argv element (`brief a" b` arrives as two
# elements, `brief a` and `b` — failure mode 2, restored). The same corruption
# was also measured on the terminal adapter's `&` delivery, so this is refused
# for BOTH adapters, before either is chosen, exactly like the semicolon.
# Escaping instead of refusing was considered and rejected: the prompt is one
# short line saying what to do, which ticket, and where to read the rest, so
# it never legitimately needs a literal quote.
if ($Prompt.Contains('"')) {
    Write-Status 'failed' 'The prompt contains a double quote, which is silently dropped or splits the prompt on delivery. Rewrite the prompt without one.' 1
}
# Measured (fix round 1): a trailing backslash escapes the quote that wraps
# the prompt for the direct adapter's Start-Process call — the backslash is
# consumed, a stray literal quote is appended to the prompt text, the REAL
# closing quote is consumed too, and anything after the prompt on the
# command line would be swallowed into it. Refused for both adapters, before
# either is chosen, for the same reason as the semicolon and the double quote.
if ($Prompt.EndsWith('\')) {
    Write-Status 'failed' 'The prompt ends with a backslash, which escapes the quote wrapping it on the direct adapter. Rewrite the prompt without a trailing backslash.' 1
}
if ($Prompt.Length -gt 600) {
    Write-Status 'failed' "The prompt is $($Prompt.Length) characters. A prompt says what to do, which ticket, and where to read the rest — the rest is pulled from the ledger." 1
}

$claude = $ClaudeCommand
if ([string]::IsNullOrWhiteSpace($claude)) {
    $cmd = Get-Command claude -ErrorAction SilentlyContinue
    if (-not $cmd) { Write-Status 'unavailable' 'claude was not found in PATH (never hardcode its path).' 2 }
    $claude = $cmd.Source
}
elseif (-not (Test-Path -LiteralPath $claude -PathType Leaf)) {
    Write-Status 'unavailable' "The given claude command does not exist: $claude" 2
}

# Removal happens in THIS process, immediately before the spawn, so the child
# cannot inherit what the orchestrator handed us.
foreach ($n in $StripVars) { Remove-Item -Path "Env:$n" -ErrorAction SilentlyContinue }

# The prompt travels on argv, never on the command line as a bare, unquoted
# token — that is failure mode 2. `& $terminal ... @claudeArgs` (below) is
# PowerShell's own native-command invocation: measured, it quotes an array
# element containing whitespace automatically before handing the child a
# command line, so $claudeArgs here carries the prompt UNQUOTED and still
# arrives at the child as one token — no fix needed on that path.
# `Start-Process -ArgumentList` (the direct adapter, below) does NOT do this —
# measured, on a real executable target, not just a script: it joins array
# elements into a command line WITHOUT quoting any of them, so an unquoted
# multi-word prompt falls apart into one word per space (2026-09-02 attempt 3,
# exactly this failure). Attempt 4's proven fix is to wrap the prompt in a
# literal double-quote pair before it ever reaches Start-Process.
# $directArgs below does only that, and only for Start-Process's call, kept
# separate from the shared $claudeArgs used by the terminal adapter — NOT
# because adding the same quotes there would break anything (measured: it
# would not; the terminal child's own parser consumes the redundant quotes
# and the prompt still arrives as one intact element), but because the
# terminal path does not NEED them, and the smallest correct change adds a
# quote only where one is actually required.
$claudeArgs = @('--name', $Ticket, $Prompt)

if ($Adapter -eq 'direct') {
    $proc = $null
    try {
        $directArgs = @('--name', $Ticket, ('"' + $Prompt + '"'))
        $proc = Start-Process -FilePath $claude -ArgumentList $directArgs -WorkingDirectory $SlotPath -PassThru
    }
    catch {
        Write-Status 'failed' "Start-Process failed: $($_.Exception.Message)" 1
    }
    # Measured (fix round 1): Start-Process against a bare .ps1, or against a
    # non-executable file, can neither throw NOR start anything — control
    # would fall through and report launched with nothing actually running.
    # -PassThru turns that into a checkable fact: it either throws (caught
    # above) or returns a real process object. $proc -eq $null here means
    # neither happened, so no false "launched" is ever reported. Task 6's
    # session-registry check remains an independent SECOND proof, not the
    # only one.
    if ($null -eq $proc) {
        Write-Status 'failed' "Start-Process did not start a process for $claude (no exception, no process returned). Verify -ClaudeCommand points at a real executable." 1
    }
    Write-Status 'launched' "direct adapter: $claude in $SlotPath, session named $Ticket" 0
}
else {
    # terminal adapter. Structured as the `else` half of the SAME if, not as
    # fall-through code after the direct branch's Write-Status calls: this
    # makes "never falls back to another adapter" a fact about the script's
    # SHAPE, not merely a consequence of Write-Status always calling `exit`.
    $terminal = $TerminalCommand
    if ([string]::IsNullOrWhiteSpace($terminal)) {
        $cmd = Get-Command wt.exe -ErrorAction SilentlyContinue
        if (-not $cmd) { Write-Status 'unavailable' 'wt.exe was not found in PATH. This script never falls back to another adapter.' 2 }
        $terminal = $cmd.Source
    }
    elseif (-not (Test-Path -LiteralPath $terminal -PathType Leaf)) {
        Write-Status 'unavailable' "The given terminal command does not exist: $terminal. This script never falls back to another adapter." 2
    }

    try {
        # Piped to Out-Null so a chatty terminal command's own stdout cannot
        # land ahead of this script's status word on ITS stdout — the
        # contract is exactly one status word plus one reason line, and a
        # real wt.exe is normally silent, so this is a latent risk made
        # unconditionally safe rather than an observed failure.
        & $terminal -d $SlotPath $claude @claudeArgs | Out-Null
        if ($LASTEXITCODE -ne 0) { Write-Status 'failed' "The terminal command exited with $LASTEXITCODE." 1 }
    }
    catch {
        Write-Status 'failed' "The terminal command failed: $($_.Exception.Message)" 1
    }
    Write-Status 'launched' "terminal adapter: $terminal -d $SlotPath, session named $Ticket" 0
}
