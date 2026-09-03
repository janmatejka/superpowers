#Requires -Version 7
# Probe: writes its own argv and environment to $env:MBPOOL_PROBE_OUT as JSON.
# Never infer from the shape of a command line which tokens reach a program —
# run something that prints its own argv and read it.
param([Parameter(ValueFromRemainingArguments = $true)] $Rest)
# `cwd` is set HERE, in the initial object literal, not via a later
# `$payload.cwd = ...` assignment. Measured: a [pscustomobject] built from a
# hashtable literal does not support adding a NEW property by plain dot
# assignment after construction — `$o = [pscustomobject]@{a=1}; $o.b = 2`
# throws SetValueInvocationException ("The property 'b' cannot be found on
# this object") and silently leaves `b` absent from the object, which
# ConvertTo-Json then omits without any error of its own. `$payload.env[$n]`
# below is unaffected because `env` is a hashtable value being indexed, not a
# new property being added to the outer pscustomobject.
$payload = [pscustomobject] @{
    argv = @($Rest | ForEach-Object { [string] $_ })
    env  = @{}
    cwd  = (Get-Location).Path
}
foreach ($n in @('CLAUDE_CODE_CHILD_SESSION','CLAUDE_CODE_SESSION_ID','CLAUDE_CODE_BRIDGE_SESSION_ID',
                 'CLAUDE_CODE_MESSAGING_SOCKET','CLAUDE_CODE_MESSAGING_TOKEN','CLAUDE_CODE_SSE_PORT',
                 'CLAUDE_PID','CLAUDE_CODE_ENTRYPOINT','NO_COLOR',
                 'CLAUDECODE','CLAUDE_CODE_USE_POWERSHELL_TOOL')) {
    $payload.env[$n] = [Environment]::GetEnvironmentVariable($n)
}
$payload | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $env:MBPOOL_PROBE_OUT -Encoding utf8
exit 0
