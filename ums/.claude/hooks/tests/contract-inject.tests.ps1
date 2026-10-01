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

# 15. the ledger is found by the workspace's plan-path marker, not by the
# directory name (design: upstream sdd-workspace disambiguates a basename
# collision as plan_<slug>-<parent>/, so plan_<slug>/ may belong to another plan).
function New-Workspace([string] $Repo, [string] $Name, $PlanPath, [string] $TaskText) {
    # $PlanPath is deliberately untyped: a [string] parameter turns $null ("no marker") into ''.
    $w = Join-Path $Repo ".superpowers\sdd\$Name"
    New-Item -ItemType Directory -Force -Path $w | Out-Null
    if ($null -ne $PlanPath) { [IO.File]::WriteAllText((Join-Path $w 'plan-path'), $PlanPath + "`n", (New-Object Text.UTF8Encoding($false))) }
    $blk = "# Ledger`n<!-- UMS-NOW BEGIN -->`nState: waiting-for-subagent`nWaiting on: implementer`nSince: 2026-09-17T09:00:00Z`nDue: 2026-09-17T09:30:00Z`nTask: $TaskText`nLook at: nowhere`n<!-- UMS-NOW END -->`n"
    [IO.File]::WriteAllText((Join-Path $w 'progress.md'), $blk, (New-Object Text.UTF8Encoding($false)))
    return $w
}
$ctxX = "# Context`n`n## Active Work`n`n- **Target MB Pin:** memory-bank/`n- **Work item:** x`n"
$dm = New-Deployment $core

# 15a. two workspaces: the plain-slug one is owned by an abandoned plan, the
# suffixed one by the active plan → the active plan's block wins.
$rm = New-Repo $ctxX
New-Workspace $rm 'plan_x' 'memory-bank/proposals/abandoned/plan_x.md' '1 - stale' | Out-Null
New-Workspace $rm 'plan_x-active' 'memory-bank/proposals/active/plan_x.md' '7 - live' | Out-Null
$ac = ((Invoke-Hook $dm $rm 'SessionStart').Out | ConvertFrom-Json).hookSpecificOutput.additionalContext
Assert-Match $ac '<now-block>[\s\S]*Task: 7 - live[\s\S]*</now-block>' 'marker: the workspace owned by the active plan supplies the block'
Assert-True (-not ($ac -match 'stale')) 'marker: the abandoned plan''s workspace is not read'

# 15b. only the plain-slug workspace, WITHOUT a marker (pre-marker legacy) → used.
$rl = New-Repo $ctxX
New-Workspace $rl 'plan_x' $null '3 - legacy' | Out-Null
$ac = ((Invoke-Hook $dm $rl 'SessionStart').Out | ConvertFrom-Json).hookSpecificOutput.additionalContext
Assert-Match $ac '<now-block>[\s\S]*Task: 3 - legacy[\s\S]*</now-block>' 'legacy: a plan_<slug>/ workspace without plan-path is used'

# 15c. the plain-slug workspace HAS a marker naming another plan and nothing
# else matches → no block (the directory name alone never decides).
$ro = New-Repo $ctxX
New-Workspace $ro 'plan_x' 'memory-bank/proposals/abandoned/plan_x.md' '1 - stale' | Out-Null
$ac = ((Invoke-Hook $dm $ro 'SessionStart').Out | ConvertFrom-Json).hookSpecificOutput.additionalContext
Assert-Match $ac '<contract-core>' 'foreign marker: core is still emitted'
Assert-True (-not ($ac -match '<now-block>')) 'foreign marker: no fallback to the plain-slug directory'
Assert-True (-not ($ac -match 'stale')) 'foreign marker: foreign ledger content is not emitted'

# 15d. legacy proposal_<slug>.md marker also matches; the marker compares
# case-sensitively and after trim only.
$rp = New-Repo $ctxX
New-Workspace $rp 'plan_x-old' 'memory-bank/proposals/active/proposal_x.md' '5 - proposal era' | Out-Null
$ac = ((Invoke-Hook $dm $rp 'SessionStart').Out | ConvertFrom-Json).hookSpecificOutput.additionalContext
Assert-Match $ac 'Task: 5 - proposal era' 'marker: legacy proposal_<slug>.md path matches'
$rc = New-Repo $ctxX
New-Workspace $rc 'plan_x-c' 'memory-bank/proposals/active/PLAN_X.md' '9 - wrong case' | Out-Null
$ac = ((Invoke-Hook $dm $rc 'SessionStart').Out | ConvertFrom-Json).hookSpecificOutput.additionalContext
Assert-True (-not ($ac -match 'wrong case')) 'marker: comparison is case-sensitive'

# 15e. an oversized marker is never a match and never echoed.
$rb = New-Repo $ctxX
# The padding is trailing whitespace only, so the value EQUALS the plan path after
# trim: the size bound alone is what rejects it. A short padding (same shape,
# inside the bound) is the paired positive case.
New-Workspace $rb 'plan_x-big' ('memory-bank/proposals/active/plan_x.md' + (' ' * 5000)) '2 - oversize' | Out-Null
$ac = ((Invoke-Hook $dm $rb 'SessionStart').Out | ConvertFrom-Json).hookSpecificOutput.additionalContext
Assert-True (-not ($ac -match 'oversize')) 'marker: an oversized plan-path is not a match'
Assert-True (-not ($ac -match 'plan-path')) 'marker: plan-path content is never emitted'
$rb2 = New-Repo $ctxX
New-Workspace $rb2 'plan_x-pad' ('memory-bank/proposals/active/plan_x.md' + (' ' * 100)) '2 - padded' | Out-Null
$ac = ((Invoke-Hook $dm $rb2 'SessionStart').Out | ConvertFrom-Json).hookSpecificOutput.additionalContext
Assert-Match $ac 'Task: 2 - padded' 'marker: trailing whitespace inside the bound is trimmed and matches'

# 15f. on Windows Git Bash upstream sdd-workspace writes the marker as an
# ABSOLUTE msys path (/c/...), because its root and its plan path come from
# different tools. That exact spelling of THIS repo's plan matches as well.
$rw = New-Repo $ctxX
$rootFwd = (& git -C $rw rev-parse --show-toplevel).Trim()
$msysRoot = if ($rootFwd -match '^(?<d>[A-Za-z]):/(?<r>.*)$') { '/' + $Matches['d'].ToLowerInvariant() + '/' + $Matches['r'] } else { $rootFwd }
New-Workspace $rw 'plan_x-msys' ($msysRoot + '/memory-bank/proposals/active/plan_x.md') '4 - msys absolute' | Out-Null
$ac = ((Invoke-Hook $dm $rw 'SessionStart').Out | ConvertFrom-Json).hookSpecificOutput.additionalContext
Assert-Match $ac 'Task: 4 - msys absolute' 'marker: this repo''s absolute path spelling matches'
$rz = New-Repo $ctxX
New-Workspace $rz 'plan_x-elsewhere' '/c/somewhere/else/memory-bank/proposals/active/plan_x.md' '6 - other repo' | Out-Null
$ac = ((Invoke-Hook $dm $rz 'SessionStart').Out | ConvertFrom-Json).hookSpecificOutput.additionalContext
Assert-True (-not ($ac -match 'other repo')) 'marker: an absolute path of another location does not match'

# 15g. two workspaces both claiming the active plan are ambiguous → no block.
$ra = New-Repo $ctxX
New-Workspace $ra 'plan_x-a' 'memory-bank/proposals/active/plan_x.md' '1 - first' | Out-Null
New-Workspace $ra 'plan_x-b' 'memory-bank/proposals/active/plan_x.md' '2 - second' | Out-Null
$ac = ((Invoke-Hook $dm $ra 'SessionStart').Out | ConvertFrom-Json).hookSpecificOutput.additionalContext
Assert-True (-not ($ac -match '<now-block>')) 'marker: two claimants of one plan → no block'

# 15h. a pin outside the character whitelist never selects a workspace.
$rh = New-Repo "# Context`n`n## Active Work`n`n- **Target MB Pin:** ../evil/`n- **Work item:** x`n"
New-Workspace $rh 'plan_x-evil' '../evil/proposals/active/plan_x.md' '8 - evil pin' | Out-Null
$ac = ((Invoke-Hook $dm $rh 'SessionStart').Out | ConvertFrom-Json).hookSpecificOutput.additionalContext
Assert-True (-not ($ac -match 'evil pin')) 'hostile pin: no workspace is selected by it'

# 16. the post-compaction instruction tells the model about truncated skill bodies.
$ac = ((Invoke-Hook $dm $rm 'SessionStart').Out | ConvertFrom-Json).hookSpecificOutput.additionalContext
Assert-Match $ac 'may be truncated at 5,000 tokens' 'instruction: warns that a re-injected skill body may be truncated'
Assert-Match $ac 'read that skill''s UMS-OVERLAY block from its SKILL\.md\.\s*$' 'instruction: the truncation sentence closes the payload'
$fb = ((Invoke-Hook (New-Deployment $null) $rm 'SessionStart').Out | ConvertFrom-Json).hookSpecificOutput.additionalContext
Assert-Match $fb 'Read .*\(contract core\)' 'instruction: fallback payload is unchanged'
$res = Invoke-Hook $dm $rm 'PostCompact'
Assert-Match (($res.Out | ConvertFrom-Json).systemMessage) '^Context was compacted\. The contract core is re-injected with your next prompt' 'PostCompact systemMessage is unchanged'
Assert-True (-not ((($res.Out | ConvertFrom-Json).PSObject.Properties.Name) -contains 'hookSpecificOutput')) 'PostCompact still carries no additionalContext'

Remove-Item -Recurse -Force $dm, $rm, $rl, $ro, $rp, $rc, $rb, $rb2, $rw, $rz, $ra, $rh

# 17. harness-shaped run: windowless child, stdin event, stdout read as raw bytes.
# The real core carries characters outside the OEM code page (→ … „ “); written
# through a cp852 console they became 0x1A/0x07 control bytes and bare quotes,
# and Claude Code rejected the whole payload ("JSON Parse error: Unterminated
# string"), so the session started without the core. The output must be strict
# JSON whatever the console code page is — 7-bit ASCII with \u escapes — and
# must still carry the non-ASCII text intact.
$nonAscii = -join ([char[]] @(0x2192, 0x20, 0x2026, 0x20, 0x201E, 0x63, 0x201C, 0x20, 0x2014, 0x20, 0x11B, 0x161, 0x10D, 0x159, 0x17E))
$dn = New-Deployment ($core + "- Chain: brainstorming $nonAscii writing-plans`n")
$rn = New-Repo $ctxActive
foreach ($evt in @('SessionStart', 'PostCompact', 'UserPromptSubmit')) {
    $raw = Invoke-PwshHookRaw (Join-Path $dn 'hooks\contract-inject.ps1') $rn ('{"hook_event_name":"' + $evt + '","source":"startup"}')
    Assert-Eq $raw.Code 0 "raw ${evt}: exits 0"
    Assert-True ($raw.Bytes.Length -gt 0) "raw ${evt}: emits a payload"
    $bad = @($raw.Bytes | Where-Object { $_ -gt 0x7e -or ($_ -lt 0x20 -and $_ -notin 0x0d, 0x0a) }).Count
    Assert-Eq $bad 0 "raw ${evt}: stdout is 7-bit ASCII without control bytes"
    $strict = Test-StrictHookJson $raw.Bytes
    Assert-True $strict.Ok "raw ${evt}: stdout parses as strict JSON  $($strict.Error)"
    if ($evt -ne 'PostCompact' -and $strict.Ok) {
        Assert-True ($strict.Json.hookSpecificOutput.additionalContext.Contains($nonAscii)) "raw ${evt}: non-ASCII core text survives the round trip"
    }
}
Remove-Item -Recurse -Force $dn, $rn

# 18. delivery in parts. Claude Code caps each hook's additionalContext at 10,000
# characters (longer → file path + 2,000-character preview, measured with a real
# session: the 46,729-character payload arrived cut at "## MB_ROOT Discovery").
# Each -Part k emits one slice under the cap; the slices joined are the payload.
$partCount = [int] [regex]::Match((Get-Content -LiteralPath $hookSrc -Raw), '(?m)^\$PartCount\s*=\s*(?<n>\d+)').Groups['n'].Value
Assert-True ($partCount -ge 2) "hook declares PartCount ($partCount)"
function Invoke-HookPart([string] $Deployment, [string] $Repo, [string] $Event, [int] $Part) {
    Push-Location $Repo
    try { $out = & pwsh -NoProfile -File (Join-Path $Deployment 'hooks\contract-inject.ps1') -Event $Event -Part $Part 2>&1 | Out-String; $code = $LASTEXITCODE }
    finally { Pop-Location }
    return @{ Out = $out; Code = $code }
}
# Runs every part; returns @{ Whole; Slices; Lengths; Headers; Silent } where Silent counts empty parts.
function Get-PartRun([string] $Deployment, [string] $Repo, [string] $Event = 'SessionStart') {
    $wholeOut = (Invoke-HookPart $Deployment $Repo $Event 0).Out
    $whole = if ([string]::IsNullOrWhiteSpace($wholeOut)) { $null } else { ($wholeOut | ConvertFrom-Json).hookSpecificOutput.additionalContext }
    $slices = @(); $lengths = @(); $headers = @(); $silent = 0
    foreach ($k in 1..$partCount) {
        $res = Invoke-HookPart $Deployment $Repo $Event $k
        if ([string]::IsNullOrWhiteSpace($res.Out)) { $silent++; continue }
        $ac = ($res.Out | ConvertFrom-Json).hookSpecificOutput.additionalContext
        $lengths += $ac.Length
        $nl = $ac.IndexOf("`n")
        $headers += $ac.Substring(0, $nl)
        $slices += $ac.Substring($nl + 1)
    }
    return @{ Whole = $whole; Slices = $slices; Lengths = $lengths; Headers = $headers; Silent = $silent }
}

# 18a. the real contract core: needs several parts, each under the cap, and the
# joined slices are exactly the whole payload (nothing dropped, nothing doubled).
$realCore = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\..\skills\shared\UMS_MEMORY_BANK_CONTRACT.md') -Raw -Encoding utf8
$dr = New-Deployment $realCore; $rr = New-Repo $ctxActive
$run = Get-PartRun $dr $rr
Assert-Match $run.Whole '<contract-core>' 'parts/real core: -Part 0 still emits the whole payload'
Assert-True ($run.Slices.Count -ge 2) "parts/real core: split into $($run.Slices.Count) parts"
Assert-True (@($run.Lengths | Where-Object { $_ -gt 10000 }).Count -eq 0) "parts/real core: every part is under the 10,000-character cap ($($run.Lengths -join ', '))"
Assert-True (($run.Slices -join "`n") -ceq $run.Whole) 'parts/real core: the slices joined are exactly the whole payload'
Assert-Eq $run.Silent ($partCount - $run.Slices.Count) 'parts/real core: parts beyond the last slice are silent'
$n = $run.Slices.Count
$hdrOk = $true; for ($i = 0; $i -lt $n; $i++) { if ($run.Headers[$i] -notmatch "^\[UMS session context, part $($i + 1) of $n\b") { $hdrOk = $false } }
Assert-True $hdrOk 'parts/real core: each part names its position (part k of N)'
Assert-Match $run.Slices[$n - 1] 'read that skill''s UMS-OVERLAY block from its SKILL\.md\.\s*$' 'parts/real core: the instruction closes the last part'

# 18b. capacity: a core at the byte cap with long lines still fits the parts.
$line = ('w' * 199)
$fill = [Text.StringBuilder]::new("# UMS Memory Bank Contract`n- **Contract-Version:** 3.0`n")
while ([Text.Encoding]::UTF8.GetByteCount($fill.ToString()) -lt (49152 - 1024 - 200)) { [void] $fill.Append($line + "`n") }
$dc = New-Deployment $fill.ToString()
$run = Get-PartRun $dc $rr
Assert-True (($run.Slices -join "`n") -ceq $run.Whole) "parts/capacity: a core at the byte cap is delivered whole in $($run.Slices.Count) of $partCount parts"
Assert-True (@($run.Lengths | Where-Object { $_ -gt 10000 }).Count -eq 0) 'parts/capacity: every part is under the cap'

# 18c. a single line longer than a part has no clean cut → part 1 falls back, the rest are silent.
$dl = New-Deployment ($core + ('z' * 9500) + "`n")
$p1 = (Invoke-HookPart $dl $rr 'SessionStart' 1).Out | ConvertFrom-Json
Assert-Match $p1.hookSpecificOutput.additionalContext '^Read .*\(contract core\)' 'parts/uncuttable line: part 1 emits the read instruction'
Assert-True ([string]::IsNullOrWhiteSpace((Invoke-HookPart $dl $rr 'SessionStart' 2).Out)) 'parts/uncuttable line: part 2 is silent'

# 18d. after compaction every part re-injects once, consuming only its own marker.
Invoke-Hook $dr $rr 'PostCompact' | Out-Null
foreach ($k in 0..$partCount) { if (-not (Test-Path -LiteralPath (Join-Path $rr ('.superpowers\' + $(if ($k -eq 0) { 'contract-reload.flag' } else { "contract-reload.part$k.flag" }))))) { Assert-True $false "PostCompact writes marker for part $k" } }
$a = Invoke-HookPart $dr $rr 'UserPromptSubmit' 1
Assert-Match (($a.Out | ConvertFrom-Json).hookSpecificOutput.additionalContext) '^\[UMS session context, part 1 of' 'parts/compaction: part 1 re-injects with the first prompt'
Assert-True ([string]::IsNullOrWhiteSpace((Invoke-HookPart $dr $rr 'UserPromptSubmit' 1).Out)) 'parts/compaction: part 1 is silent on the next prompt'
$b = Invoke-HookPart $dr $rr 'UserPromptSubmit' 2
Assert-Match (($b.Out | ConvertFrom-Json).hookSpecificOutput.additionalContext) '^\[UMS session context, part 2 of' 'parts/compaction: part 1 did not consume part 2''s marker'
$run = Get-PartRun $dr $rr 'UserPromptSubmit'
Assert-Eq $run.Slices.Count ($n - 2) 'parts/compaction: the parts not yet consumed still re-inject'
$run = Get-PartRun $dr $rr 'UserPromptSubmit'
Assert-Eq $run.Slices.Count 0 'parts/compaction: nothing is re-injected twice'

# 18e. registration: SessionStart and UserPromptSubmit name every part exactly
# once, in order; PostCompact runs the hook once, without -Part.
foreach ($evt in @('SessionStart', 'UserPromptSubmit')) {
    $cmds = @($settings.hooks.$evt[0].hooks | ForEach-Object { $_.command })
    $want = @(1..$partCount | ForEach-Object { "-Part $_" })
    $got = @($cmds | ForEach-Object { if ($_ -match 'contract-inject\.ps1"?\s+(?<p>-Part \d+)\s*$') { $Matches['p'] } else { "?? $_" } })
    Assert-Eq ($got -join ',') ($want -join ',') "registration: $evt runs contract-inject once per part"
}
Assert-True (@($settings.hooks.PostCompact[0].hooks).Count -eq 1 -and $settings.hooks.PostCompact[0].hooks[0].command -notmatch '-Part') 'registration: PostCompact runs contract-inject once, without -Part'
Remove-Item -Recurse -Force $dr, $rr, $dc, $dl

Complete-Tests
