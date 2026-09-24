#Requires -Version 7
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '_assert.ps1')
$ErrorActionPreference = 'Stop'
$hookSrc = Join-Path $PSScriptRoot '..\contract-inject.ps1'

function New-Deployment($CoreText) {
    $d = Join-Path ([IO.Path]::GetTempPath()) ("mbinject-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path (Join-Path $d 'hooks'), (Join-Path $d 'skills\shared') | Out-Null
    Copy-Item $hookSrc (Join-Path $d 'hooks\contract-inject.ps1')
    if ($null -ne $CoreText) { [IO.File]::WriteAllText((Join-Path $d 'skills\shared\UMS_MEMORY_BANK_CONTRACT.md'), $CoreText, (New-Object Text.UTF8Encoding($false))) }
    return $d
}
function New-Repo($ContextText) {
    $r = Join-Path ([IO.Path]::GetTempPath()) ("mbrepo-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path (Join-Path $r 'memory-bank'), (Join-Path $r '.superpowers') | Out-Null
    git -C $r init -q
    if ($null -ne $ContextText) { [IO.File]::WriteAllText((Join-Path $r 'memory-bank\context.md'), $ContextText, (New-Object Text.UTF8Encoding($false))) }
    return $r
}
function Invoke-Hook([string] $Deployment, [string] $Repo, [string] $Event) {
    Push-Location $Repo
    try { $out = & pwsh -NoProfile -File (Join-Path $Deployment 'hooks\contract-inject.ps1') -Event $Event 2>&1 | Out-String; $code = $LASTEXITCODE }
    finally { Pop-Location }
    return @{ Out = $out; Code = $code }
}
# Production never passes -Event: Claude Code pipes {"hook_event_name":"..."}
# on stdin. No other case in this file drives that route, so it is otherwise
# untested — this helper is the one case that does.
function Invoke-HookStdin([string] $Deployment, [string] $Repo, [string] $EventJson) {
    Push-Location $Repo
    try { $out = $EventJson | & pwsh -NoProfile -File (Join-Path $Deployment 'hooks\contract-inject.ps1') 2>&1 | Out-String; $code = $LASTEXITCODE }
    finally { Pop-Location }
    return @{ Out = $out; Code = $code }
}

$core = "# UMS Memory Bank Contract`n`n- **Contract-Version:** 3.0`n`n## Language Contract`n- AI-facing text is English.`n"
$ctxActive = "# Context`n`n## Active Work`n`n- **Jira:** UMS-1 (https://x/UMS-1)`n- **Target MB Pin:** memory-bank/`n- **Work item:** demo_slug`n- **Started:** 2026-09-17`n"

# 1. SessionStart carries core + context
$d = New-Deployment $core; $r = New-Repo $ctxActive
$res = Invoke-Hook $d $r 'SessionStart'
Assert-Eq $res.Code 0 'SessionStart exits 0'
$json = $res.Out | ConvertFrom-Json
Assert-Eq $json.hookSpecificOutput.hookEventName 'SessionStart' 'event name is SessionStart'
Assert-Match $json.hookSpecificOutput.additionalContext '<contract-core>[\s\S]*Contract-Version:\*\* 3\.0[\s\S]*</contract-core>' 'core is embedded whole'
Assert-Match $json.hookSpecificOutput.additionalContext '<memory-bank-context>[\s\S]*Work item:\*\* demo_slug' 'context pin is re-rendered'
Assert-True (-not ($json.hookSpecificOutput.additionalContext -match '<now-block>')) 'no ledger → no NOW block'

# 2. NOW block from the pinned slug's ledger
$led = Join-Path $r '.superpowers\sdd\plan_demo_slug'; New-Item -ItemType Directory -Path $led | Out-Null
$now = "# Ledger`n<!-- UMS-NOW BEGIN -->`nState: waiting-for-subagent`nWaiting on: implementer of task 2`nSince: 2026-09-17T09:00:00Z`nDue: 2026-09-17T09:30:00Z`nTask: 2 — Demo`nLook at: .superpowers/sdd/plan_demo_slug/task-2-brief.md`n<!-- UMS-NOW END -->`n"
[IO.File]::WriteAllText((Join-Path $led 'progress.md'), $now, (New-Object Text.UTF8Encoding($false)))
$json = (Invoke-Hook $d $r 'SessionStart').Out | ConvertFrom-Json
Assert-Match $json.hookSpecificOutput.additionalContext '<now-block>[\s\S]*State: waiting-for-subagent[\s\S]*</now-block>' 'NOW block is re-rendered'

# 3. hostile NOW value is rejected by character class
$hostile = $now -replace 'implementer of task 2', ("implementer" + [char]0x202E + " of task 2")
[IO.File]::WriteAllText((Join-Path $led 'progress.md'), $hostile, (New-Object Text.UTF8Encoding($false)))
$json = (Invoke-Hook $d $r 'SessionStart').Out | ConvertFrom-Json
Assert-True (-not ($json.hookSpecificOutput.additionalContext -match '<now-block>')) 'RTL override → block dropped'
Assert-Match $json.hookSpecificOutput.additionalContext 'now-block: rejected \(character class\)' 'rejection is announced'

# 4. PostCompact writes the marker and a systemMessage
$res = Invoke-Hook $d $r 'PostCompact'
Assert-Eq $res.Code 0 'PostCompact exits 0'
$json = $res.Out | ConvertFrom-Json
Assert-Match $json.systemMessage 'Context was compacted' 'PostCompact emits systemMessage'
Assert-True (Test-Path (Join-Path $r '.superpowers\contract-reload.flag')) 'PostCompact writes the reload marker'

# 5. UserPromptSubmit with marker injects and consumes it
$res = Invoke-Hook $d $r 'UserPromptSubmit'
$json = $res.Out | ConvertFrom-Json
Assert-Eq $json.hookSpecificOutput.hookEventName 'UserPromptSubmit' 'UserPromptSubmit injects when marker present'
Assert-Match $json.hookSpecificOutput.additionalContext '<contract-core>' 'core injected after compaction'
Assert-True (-not (Test-Path (Join-Path $r '.superpowers\contract-reload.flag'))) 'marker consumed'

# 6. UserPromptSubmit without marker is silent
$res = Invoke-Hook $d $r 'UserPromptSubmit'
Assert-Eq $res.Code 0 'silent exit 0'
Assert-True ([string]::IsNullOrWhiteSpace($res.Out)) 'no output without marker'

# 7. missing core → fallback instruction, exit 0
$d2 = New-Deployment $null
$res = Invoke-Hook $d2 $r 'SessionStart'
Assert-Eq $res.Code 0 'missing core still exits 0'
$json = $res.Out | ConvertFrom-Json
Assert-Match $json.hookSpecificOutput.additionalContext 'Read .*UMS_MEMORY_BANK_CONTRACT\.md \(contract core\)' 'fallback instruction emitted'

# 8. missing context.md → core still emitted
$r2 = New-Repo $null
$json = (Invoke-Hook $d $r2 'SessionStart').Out | ConvertFrom-Json
Assert-Match $json.hookSpecificOutput.additionalContext '<contract-core>' 'core without context.md'
Assert-Match $json.hookSpecificOutput.additionalContext '<memory-bank-context>\s*\(context\.md missing\)' 'missing context is named'

# 9. oversize core → fallback
$big = "# UMS Memory Bank Contract`n- **Contract-Version:** 3.0`n" + ('x' * 60000)
$d3 = New-Deployment $big
$json = (Invoke-Hook $d3 $r 'SessionStart').Out | ConvertFrom-Json
Assert-Match $json.hookSpecificOutput.additionalContext 'Read .*\(contract core\)' 'payload over 48 kB falls back to the read instruction'
Assert-True (-not ($json.hookSpecificOutput.additionalContext -match 'xxxxxxxxxx')) 'oversize content is not emitted'

# 10. outside a git repo → exit 0, and the hook still measurably does its job.
# $res.Code 0 alone is vacuous: this hook exits 0 on every path by design, so
# that assertion is green even if the hook silently did nothing (or crashed
# into the empty catch — see case 6's note below). Outside a repo there is no
# root to read memory-bank/context.md from, but the deployment's own core file
# ($d has real content) is still readable and still emitted in full — assert
# that positively, alongside the exit code.
$nogit = Join-Path ([IO.Path]::GetTempPath()) ("mbnogit-" + [guid]::NewGuid().ToString('N').Substring(0, 8)); New-Item -ItemType Directory -Path $nogit | Out-Null
$res = Invoke-Hook $d $nogit 'SessionStart'
Assert-Eq $res.Code 0 'no git → exit 0'
Assert-Match $res.Out '<contract-core>' 'no git → core is still emitted (not a silent no-op or a crash)'

# 11. path traversal in the pinned slug must not reach the filesystem.
# context.md's Work item value is attacker-reachable text (contract-inject.ps1
# only re-renders known keys from it, never echoes it verbatim) and it used to
# flow straight into Join-Path: a slug of "x/../../../../outside" resolved to a
# ledger several directories above the repo. Plant a real progress.md there,
# at the exact path the unguarded code would have read, and confirm the hook
# refuses to open it — no <now-block>, and (paired positive assertion, so this
# cannot pass merely because the hook produced nothing or crashed) the core and
# context pin are still emitted normally.
$rTrav = New-Repo "# Context`n`n## Active Work`n`n- **Work item:** x/../../../../outside`n"
$outsideDir = Join-Path (Split-Path -Parent $rTrav) 'outside'
New-Item -ItemType Directory -Force -Path $outsideDir | Out-Null
$leak = "# Ledger`n<!-- UMS-NOW BEGIN -->`nState: LEAKED-FROM-OUTSIDE`nWaiting on: nobody`nSince: 2026-09-17T09:00:00Z`nDue: 2026-09-17T09:30:00Z`nTask: 0 — n/a`nLook at: nowhere`n<!-- UMS-NOW END -->`n"
[IO.File]::WriteAllText((Join-Path $outsideDir 'progress.md'), $leak, (New-Object Text.UTF8Encoding($false)))
$json = (Invoke-Hook $d $rTrav 'SessionStart').Out | ConvertFrom-Json
Assert-Match $json.hookSpecificOutput.additionalContext '<contract-core>' 'traversal slug: core is still emitted'
Assert-Match $json.hookSpecificOutput.additionalContext 'Work item:\*\* x/\.\./\.\./\.\./\.\./outside' 'traversal slug: context pin is still re-rendered'
Assert-True (-not ($json.hookSpecificOutput.additionalContext -match '<now-block>')) 'traversal slug → no NOW block'
Assert-True (-not ($json.hookSpecificOutput.additionalContext -match 'LEAKED-FROM-OUTSIDE')) 'traversal slug → outside ledger content never reaches the payload'
Remove-Item -Recurse -Force $outsideDir

# 12. production invocation shape: stdin JSON, no -Event at all.
$json = (Invoke-HookStdin $d $r '{"hook_event_name":"SessionStart"}').Out | ConvertFrom-Json
Assert-Eq $json.hookSpecificOutput.hookEventName 'SessionStart' 'stdin route: event name recovered from JSON'
Assert-Match $json.hookSpecificOutput.additionalContext '<contract-core>' 'stdin route: payload is produced, not just a non-crash'

Remove-Item -Recurse -Force $d, $d2, $d3, $r, $r2, $rTrav, $nogit

# 13. registration shape check: SessionStart, PostCompact and UserPromptSubmit
# all name this hook (Step 6 of the task brief — a shape check, not a new suite).
$settingsPath = Join-Path $PSScriptRoot '..\..\settings.json'
$settings = Get-Content -LiteralPath $settingsPath -Raw -Encoding utf8 | ConvertFrom-Json
Assert-Match $settings.hooks.SessionStart[0].hooks[0].command 'contract-inject\.ps1' 'SessionStart[0] names contract-inject.ps1'
Assert-Match $settings.hooks.PostCompact[0].hooks[0].command 'contract-inject\.ps1' 'PostCompact[0] names contract-inject.ps1'
Assert-Match $settings.hooks.UserPromptSubmit[0].hooks[0].command 'contract-inject\.ps1' 'UserPromptSubmit[0] names contract-inject.ps1'

# 14. deployment drift inside the fork: the repo carries a source core
# (ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md) that differs from the
# deployment's own core → the warning is the FIRST line of the payload. Then,
# with an IDENTICAL source core, the warning must NOT fire — but a warning
# that never fires would also pass a lazily-written "no warning" assertion
# (e.g. one that only checks the hook didn't crash), so pair it with a
# positive assertion on the same payload: the core itself is still emitted in
# full, proving the hash comparison ran and simply found no drift, not that
# the whole feature silently no-oped.
$d4 = New-Deployment $core
$rDrift = New-Repo $ctxActive
$sourceDir = Join-Path $rDrift 'ums\.claude\skills\shared'
New-Item -ItemType Directory -Force -Path $sourceDir | Out-Null
$differentCore = $core + "`n- extra source-only line`n"
[IO.File]::WriteAllText((Join-Path $sourceDir 'UMS_MEMORY_BANK_CONTRACT.md'), $differentCore, (New-Object Text.UTF8Encoding($false)))
$json = (Invoke-Hook $d4 $rDrift 'SessionStart').Out | ConvertFrom-Json
Assert-Match $json.hookSpecificOutput.additionalContext '^WARNING: deployed contract core differs from source ums/\.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT\.md — refresh the deployment \(playbook, "Když nasazuješ nebo revendoruješ"\)\.' 'drift → warning is the first line of the payload'

[IO.File]::WriteAllText((Join-Path $sourceDir 'UMS_MEMORY_BANK_CONTRACT.md'), $core, (New-Object Text.UTF8Encoding($false)))
$json = (Invoke-Hook $d4 $rDrift 'SessionStart').Out | ConvertFrom-Json
Assert-True (-not ($json.hookSpecificOutput.additionalContext -match 'WARNING: deployed')) 'identical source → no drift warning'
Assert-Match $json.hookSpecificOutput.additionalContext '<contract-core>[\s\S]*Contract-Version:\*\* 3\.0[\s\S]*</contract-core>' 'identical source → core is still emitted in full (hash check ran, found no drift)'
Remove-Item -Recurse -Force $d4, $rDrift

Complete-Tests
