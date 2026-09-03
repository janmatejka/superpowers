Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '_assert.ps1')
$ErrorActionPreference = 'Stop'
$NewFixture = Join-Path $PSScriptRoot 'new-pool-fixture.ps1'
$Stub = Join-Path $PSScriptRoot 'stubs\claude-stub.ps1'

function Invoke-Status([string] $Repo, [string[]] $Extra = @()) {
    $json = Join-Path ([IO.Path]::GetTempPath()) ('mbpool-' + [guid]::NewGuid().ToString('N') + '.json')
    $a = @('-RepoPath', $Repo, '-Json', $json, '-ClaudeCommand', $Stub) + $Extra
    $r = Invoke-PoolScript 'pool-status.ps1' $a
    $data = $null
    if (Test-Path -LiteralPath $json) { $data = Get-Content -LiteralPath $json -Raw | ConvertFrom-Json }
    Remove-Item -LiteralPath $json -Force -ErrorAction SilentlyContinue
    return @{ Out = $r.Out; Code = $r.Code; Data = $data }
}
function Get-Slot($Data, [string] $Name) {
    return @($Data.slots | Where-Object { $_.name -eq $Name }) | Select-Object -First 1
}

# Clean slate: MBPOOL_STUB_CWD_MODES is a per-cwd override (Gate 4) that no
# case before it existed, but leaving it set from one run to the next would
# make a later case's plain MBPOOL_STUB_MODE silently ignored.
$env:MBPOOL_STUB_CWD_MODES = $null

# --- case 1: no marked worktree => the repository has no pool (exit 3) -------
# This is the state of the superpowers fork itself (zero linked worktrees), so
# the path has to be proven, not assumed.
$env:MBPOOL_STUB_MODE = 'empty'
$fx = & $NewFixture -SlotCount 2 -Label 'nopool'
try {
    $r = Invoke-Status $fx.Main
    Assert-Eq $r.Code 3 'repository without a marked worktree exits 3'
    Assert-Match $r.Out 'no pool' 'exit 3 says the repository has no pool'
    Assert-Eq @($r.Data.slots).Count 0 'no slots reported'
    Assert-True (@($r.Data.excluded | Where-Object { $_.reason -match 'marker' }).Count -ge 2) 'unmarked worktrees are excluded with a named reason'
    # Ruling A: excluded entries also carry `branch` — null for the detached
    # fixture slots, and the porcelain branch name for the primary worktree.
    $primaryEntry = @($r.Data.excluded | Where-Object { $_.reason -eq 'primary worktree' }) | Select-Object -First 1
    Assert-Eq $primaryEntry.branch 'develop' 'the primary worktree exclusion reports its branch (Ruling A)'
    Assert-True (@($r.Data.excluded | Where-Object { $_.reason -match 'marker' -and $null -eq $_.branch }).Count -ge 2) 'excluded detached worktrees report branch = null (Ruling A)'
}
finally { Remove-Item -Recurse -Force $fx.Root -ErrorAction SilentlyContinue }

# --- case 2: marker decides membership --------------------------------------
$env:MBPOOL_STUB_MODE = 'empty'
$fx = & $NewFixture -SlotCount 2 -Label 'marker'
try {
    Set-SlotMarker $fx.Slots[0]
    Set-SlotIdle $fx.Slots[0]
    $r = Invoke-Status $fx.Main
    Assert-Eq $r.Code 0 'a marked worktree makes a pool'
    Assert-Eq @($r.Data.slots).Count 1 'only the marked worktree is a slot'
    Assert-Eq (Get-Slot $r.Data 'slot01').free $true 'clean marked IDLE slot is free'
    Assert-NotMatch (($r.Data.slots | ForEach-Object { $_.name }) -join ',') 'slot02' 'the unmarked worktree is not a slot'
}
finally { Remove-Item -Recurse -Force $fx.Root -ErrorAction SilentlyContinue }

# --- case 3: REGRESSION PROOF — a stash in one worktree must not unfree another
# refs/stash is SHARED across a pool, so `git stash list` answers identically
# from every slot. With the contract's original three-signal derivation this
# case goes red; that is the negativity this assertion exists for.
$env:MBPOOL_STUB_MODE = 'empty'
$fx = & $NewFixture -SlotCount 2 -Label 'stash'
try {
    foreach ($s in $fx.Slots) { Set-SlotMarker $s; Set-SlotIdle $s }
    'dirty' | Out-File -FilePath (Join-Path $fx.Slots[0] 'f.txt') -Encoding utf8
    & git -C $fx.Slots[0] stash push -u -m 'fixture stash' 2>&1 | Out-Null
    $r = Invoke-Status $fx.Main
    Assert-Eq (Get-Slot $r.Data 'slot02').free $true 'a stash created in slot01 does NOT make slot02 unfree'
    Assert-True (@($r.Data.stash).Count -ge 1) 'the stash is still reported, once per repository'
    Assert-NotMatch (((Get-Slot $r.Data 'slot02').reasons -join ' ')) 'stash' 'stash is not a reason attached to a slot'
}
finally { Remove-Item -Recurse -Force $fx.Root -ErrorAction SilentlyContinue }

# --- case 4: REGRESSION PROOF — an unpushed commit on branch A must not
# unfree a slot standing on branch B. `--branches` is repo-wide by
# construction; one unpushed commit anywhere would freeze the whole pool.
$env:MBPOOL_STUB_MODE = 'empty'
$fx = & $NewFixture -SlotCount 2 -Label 'unpushed'
try {
    foreach ($s in $fx.Slots) { Set-SlotMarker $s; Set-SlotIdle $s }
    & git -C $fx.Slots[0] switch -q -c branch-a 2>&1 | Out-Null
    'a' | Out-File -FilePath (Join-Path $fx.Slots[0] 'a.txt') -Encoding utf8
    & git -C $fx.Slots[0] add -A 2>&1 | Out-Null
    & git -C $fx.Slots[0] commit -q -m 'unpushed on A' 2>&1 | Out-Null
    & git -C $fx.Slots[1] switch -q -c branch-b 2>&1 | Out-Null
    $r = Invoke-Status $fx.Main
    Assert-Eq (Get-Slot $r.Data 'slot02').free $true 'an unpushed commit on branch-a does NOT unfree the slot on branch-b'
    Assert-True ((Get-Slot $r.Data 'slot01').unpushedCount -ge 1) 'the slot that owns the unpushed commit reports it'
    Assert-Eq (Get-Slot $r.Data 'slot01').free $false 'the owning slot is not free'
}
finally { Remove-Item -Recurse -Force $fx.Root -ErrorAction SilentlyContinue }

# --- case 5: occupancy, three states, fail-closed ---------------------------
$fx = & $NewFixture -SlotCount 1 -Label 'occupancy'
try {
    Set-SlotMarker $fx.Slots[0]; Set-SlotIdle $fx.Slots[0]

    $env:MBPOOL_STUB_MODE = 'live'
    $r = Invoke-Status $fx.Main
    Assert-Eq (Get-Slot $r.Data 'slot01').session.state 'live' 'a record WITH a pid means the slot is occupied'
    Assert-Eq (Get-Slot $r.Data 'slot01').free $false 'an occupied slot is not free'

    $env:MBPOOL_STUB_MODE = 'nopid'
    $r = Invoke-Status $fx.Main
    Assert-Eq (Get-Slot $r.Data 'slot01').session.state 'none' 'a record WITHOUT a pid is ignored'
    Assert-Eq (Get-Slot $r.Data 'slot01').free $true 'a slot with only pid-less records is free'

    $env:MBPOOL_STUB_MODE = 'garbage'
    $r = Invoke-Status $fx.Main
    Assert-Eq (Get-Slot $r.Data 'slot01').session.state 'unknown' 'unparseable output means UNKNOWN, never "free"'
    Assert-Eq (Get-Slot $r.Data 'slot01').free $false 'occupancy unknown is fail-closed: the slot is not free'

    $env:MBPOOL_STUB_MODE = 'empty'
    $r = Invoke-Status $fx.Main
    Assert-Eq (Get-Slot $r.Data 'slot01').session.state 'none' 'an empty record list means no session'
}
finally {
    $env:MBPOOL_STUB_MODE = 'empty'
    Remove-Item -Recurse -Force $fx.Root -ErrorAction SilentlyContinue
}

# --- case 6: the ledger is paired to the slug FROM THE PIN ------------------
# A slot carrying two sdd directories, the foreign one sorting first.
$env:MBPOOL_STUB_MODE = 'empty'
$fx = & $NewFixture -SlotCount 1 -Label 'ledger'
try {
    Set-SlotMarker $fx.Slots[0]
    Set-SlotPin $fx.Slots[0] 'zulu_current_work'
    New-SlotLedger $fx.Slots[0] 'plan_alpha_leftover' 'Task 9 of the WRONG plan.'
    New-SlotLedger $fx.Slots[0] 'plan_zulu_current_work' 'Task 2 of the right plan.'
    $r = Invoke-Status $fx.Main
    $s = Get-Slot $r.Data 'slot01'
    Assert-Match $s.progress.path 'plan_zulu_current_work' 'progress comes from the slug the PIN names'
    Assert-NotMatch $s.progress.path 'plan_alpha_leftover' 'the alphabetically first, foreign ledger is not reported'
    Assert-Match $s.progress.lastLine 'right plan' 'the reported line comes from the right ledger'
}
finally { Remove-Item -Recurse -Force $fx.Root -ErrorAction SilentlyContinue }

# --- case 7: a FOREIGN playbook candidate leaves the slot free --------------
# It is only defined against the CURRENT slug; an IDLE slot has none, so every
# candidate in it is foreign, and a foreign candidate is "merely present".
$env:MBPOOL_STUB_MODE = 'empty'
$fx = & $NewFixture -SlotCount 1 -Label 'candidate'
try {
    Set-SlotMarker $fx.Slots[0]; Set-SlotIdle $fx.Slots[0]
    $cand = Join-Path (Join-Path $fx.Slots[0] '.superpowers') 'playbook-candidates'
    New-Item -ItemType Directory -Force -Path $cand | Out-Null
    Set-Content -LiteralPath (Join-Path $cand 'someone_elses_slug.md') -Value '# Playbook candidates' -Encoding utf8
    $r = Invoke-Status $fx.Main
    Assert-Eq (Get-Slot $r.Data 'slot01').free $true 'a foreign playbook candidate does NOT unfree an IDLE slot'
}
finally { Remove-Item -Recurse -Force $fx.Root -ErrorAction SilentlyContinue }

# --- case 8: an ACTIVE pin is not free, and a branch NAME never decides IDLE -
$env:MBPOOL_STUB_MODE = 'empty'
$fx = & $NewFixture -SlotCount 1 -Label 'pin'
try {
    Set-SlotMarker $fx.Slots[0]
    # The slot stands on a branch named after its own directory AND carries an
    # ACTIVE pin — measured shape; the branch name must not win.
    & git -C $fx.Slots[0] switch -q -c slot01 2>&1 | Out-Null
    Set-SlotPin $fx.Slots[0] 'ums_3485_vyhodnoceni'
    $r = Invoke-Status $fx.Main
    $s = Get-Slot $r.Data 'slot01'
    Assert-Eq $s.free $false 'an eponymous branch does NOT make a pinned slot idle'
    Assert-Match ($s.reasons -join ' ') 'ACTIVE pin' 'the reason names the pin, not the branch'
    Assert-Eq $s.pin.slug 'ums_3485_vyhodnoceni' 'the pin slug is reported'
    Assert-Eq $s.branch 'slot01' 'the slot reports its own branch name'
}
finally { Remove-Item -Recurse -Force $fx.Root -ErrorAction SilentlyContinue }

# --- case 9: locked and prunable worktrees are excluded with a named reason --
$env:MBPOOL_STUB_MODE = 'empty'
$fx = & $NewFixture -SlotCount 2 -Label 'locked'
try {
    foreach ($s in $fx.Slots) { Set-SlotMarker $s; Set-SlotIdle $s }
    # Ruling A rider: move the to-be-locked slot onto a real branch first, so
    # this case also proves "locked" alone does NOT null the branch field —
    # only detached/bare/prunable do.
    & git -C $fx.Slots[1] switch -q -c slot02-branch 2>&1 | Out-Null
    & git -C $fx.Main worktree lock --reason 'held by the operator' $fx.Slots[1] 2>&1 | Out-Null
    $r = Invoke-Status $fx.Main
    Assert-Eq @($r.Data.slots).Count 1 'a locked worktree is not a candidate'
    Assert-Match (($r.Data.excluded | ForEach-Object { $_.reason }) -join ' ') 'locked' 'the exclusion names locked'
    $lockedEntry = @($r.Data.excluded | Where-Object { $_.reason -match 'locked' }) | Select-Object -First 1
    Assert-Eq $lockedEntry.branch 'slot02-branch' 'a locked but non-detached worktree still reports its branch (Ruling A)'
}
finally {
    & git -C $fx.Main worktree unlock $fx.Slots[1] 2>&1 | Out-Null
    Remove-Item -Recurse -Force $fx.Root -ErrorAction SilentlyContinue
}

# --- case 10: epic branch matching is case-sensitive (Ruling B, -cmatch) ----
# Every case-sensitive comparator needs its own dedicated case whose two
# values differ ONLY by letter case — a generic "these are different values"
# case proves nothing about case sensitivity specifically.
$env:MBPOOL_STUB_MODE = 'empty'
$fx = & $NewFixture -SlotCount 1 -Label 'epic-case'
try {
    Set-SlotMarker $fx.Slots[0]; Set-SlotIdle $fx.Slots[0]
    & git -C $fx.Slots[0] switch -q -c UMS-3488-epic-ticket 2>&1 | Out-Null

    $r = Invoke-Status $fx.Main @('-Epic', 'ums-3488')
    $s = Get-Slot $r.Data 'slot01'
    Assert-Eq $s.free $true 'an epic key differing only in case does NOT match the branch (Ruling B, -cmatch)'
    Assert-NotMatch (($s.reasons -join ' ')) 'ticket branch' 'no ticket-branch reason when only case differs'

    $r2 = Invoke-Status $fx.Main @('-Epic', 'UMS-3488')
    $s2 = Get-Slot $r2.Data 'slot01'
    Assert-Eq $s2.free $false 'the exact-case epic key DOES match the branch'
    Assert-Match (($s2.reasons -join ' ')) 'UMS-3488' 'the reason names the matched epic'
}
finally { Remove-Item -Recurse -Force $fx.Root -ErrorAction SilentlyContinue }

# --- case 11: a pin file that EXISTS but cannot be READ is fail-closed, not
# IDLE (Gate item 1, fix round 1) --------------------------------------------
$env:MBPOOL_STUB_MODE = 'empty'
$fx = & $NewFixture -SlotCount 1 -Label 'pin-unreadable'
$handle = $null
try {
    Set-SlotMarker $fx.Slots[0]; Set-SlotIdle $fx.Slots[0]
    $ctxPath = Join-Path $fx.Slots[0] 'memory-bank\context.md'
    # icacls is blocked in this sandbox (measured, Task 2); deny sharing from
    # this process instead, for the duration of the child script's run.
    $handle = [System.IO.File]::Open($ctxPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None)
    $r = Invoke-Status $fx.Main
    $s = Get-Slot $r.Data 'slot01'
    Assert-Eq $s.free $false 'a context.md that exists but cannot be read is NOT free (fail-closed, Gate 1)'
    Assert-Match (($s.reasons -join ' ')) 'pin unreadable' 'the reason names the unreadable pin, not IDLE'
}
finally {
    if ($handle) { $handle.Dispose() }
    Remove-Item -Recurse -Force $fx.Root -ErrorAction SilentlyContinue
}

# --- case 12: silent exit-0 output is UNKNOWN, not "no session" (Gate 2.1) --
$env:MBPOOL_STUB_MODE = 'silent'
$fx = & $NewFixture -SlotCount 1 -Label 'occ-silent'
try {
    Set-SlotMarker $fx.Slots[0]; Set-SlotIdle $fx.Slots[0]
    $r = Invoke-Status $fx.Main
    $s = Get-Slot $r.Data 'slot01'
    Assert-Eq $s.session.state 'unknown' 'exit 0 with no output at all is UNKNOWN, never "none" (Gate 2.1)'
    Assert-Eq $s.free $false 'occupancy unknown is fail-closed here too'
}
finally { Remove-Item -Recurse -Force $fx.Root -ErrorAction SilentlyContinue }

# --- case 13: the bare JSON literal `null` is UNKNOWN, not "no session"
# (Gate 2.2) -------------------------------------------------------------------
$env:MBPOOL_STUB_MODE = 'jsonnull'
$fx = & $NewFixture -SlotCount 1 -Label 'occ-jsonnull'
try {
    Set-SlotMarker $fx.Slots[0]; Set-SlotIdle $fx.Slots[0]
    $r = Invoke-Status $fx.Main
    $s = Get-Slot $r.Data 'slot01'
    Assert-Eq $s.session.state 'unknown' 'the literal null is UNKNOWN, not "none" — same fail-closed rule as unparseable output (Gate 2.2)'
    Assert-Eq $s.free $false 'occupancy unknown is fail-closed here too'
}
finally { Remove-Item -Recurse -Force $fx.Root -ErrorAction SilentlyContinue }

# --- case 14: a top-level JSON OBJECT (not an array) is UNKNOWN (Gate 2.3) --
# The most dangerous of the three holes: silently reading "none" here would
# disable the pool's only load-bearing occupancy gate on a harness-side
# output-shape change instead of failing loudly.
$env:MBPOOL_STUB_MODE = 'wrapped'
$fx = & $NewFixture -SlotCount 1 -Label 'occ-wrapped'
try {
    Set-SlotMarker $fx.Slots[0]; Set-SlotIdle $fx.Slots[0]
    $r = Invoke-Status $fx.Main
    $s = Get-Slot $r.Data 'slot01'
    Assert-Eq $s.session.state 'unknown' 'a top-level JSON object instead of an array is UNKNOWN, not "none" (Gate 2.3)'
    Assert-Eq $s.free $false 'occupancy unknown is fail-closed here too'
}
finally { Remove-Item -Recurse -Force $fx.Root -ErrorAction SilentlyContinue }

# --- case 15: the -Json guard fires BEFORE any work — ordering, not just the
# exit code (Gate item 3) ------------------------------------------------------
$env:MBPOOL_STUB_MODE = 'empty'
$fx = & $NewFixture -SlotCount 1 -Label 'json-guard'
try {
    Set-SlotMarker $fx.Slots[0]; Set-SlotIdle $fx.Slots[0]
    $badJsonDir = Join-Path ([IO.Path]::GetTempPath()) ('mbpool-nonexistent-' + [guid]::NewGuid().ToString('N'))
    $badJson = Join-Path $badJsonDir 'out.json'
    $r = Invoke-PoolScript 'pool-status.ps1' @('-RepoPath', $fx.Main, '-Json', $badJson, '-ClaudeCommand', $Stub)
    Assert-Eq $r.Code 1 'a missing -Json target directory exits 1'
    Assert-NotMatch $r.Out 'Pool status for' 'the guard fires BEFORE the report is printed — a refactor that kept exit 1 but moved the check next to the write would still leave this line printed'
}
finally { Remove-Item -Recurse -Force $fx.Root -ErrorAction SilentlyContinue }

# --- case 16: occupancy is threaded per --cwd, not answered identically for
# every slot (Gate item 4) ------------------------------------------------------
$env:MBPOOL_STUB_MODE = 'empty'
$fx = & $NewFixture -SlotCount 2 -Label 'per-cwd'
try {
    foreach ($s in $fx.Slots) { Set-SlotMarker $s; Set-SlotIdle $s }
    $env:MBPOOL_STUB_CWD_MODES = 'slot01=live;slot02=empty'
    $r = Invoke-Status $fx.Main
    $s1 = Get-Slot $r.Data 'slot01'
    $s2 = Get-Slot $r.Data 'slot02'
    Assert-Eq $s1.session.state 'live' 'slot01 reads live from its OWN --cwd'
    Assert-Eq $s1.free $false 'slot01 is occupied'
    Assert-Eq $s2.session.state 'none' 'slot02, in the SAME run, reads none from its OWN --cwd — a constant-path or dropped --cwd regression would make this live too'
    Assert-Eq $s2.free $true 'slot02 is free'
}
finally {
    $env:MBPOOL_STUB_CWD_MODES = $null
    Remove-Item -Recurse -Force $fx.Root -ErrorAction SilentlyContinue
}

Complete-Tests
