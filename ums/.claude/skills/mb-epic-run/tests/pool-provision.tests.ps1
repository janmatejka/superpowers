Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '_assert.ps1')
$ErrorActionPreference = 'Stop'
$NewFixture = Join-Path $PSScriptRoot 'new-pool-fixture.ps1'

function Invoke-Provision([string] $Repo, [string] $Path, [string[]] $Extra = @()) {
    $a = @('-RepoPath', $Repo, '-Path', $Path, '-Base', 'origin/develop', '-NoFetch') + $Extra
    return Invoke-PoolScript 'pool-provision.ps1' $a
}

# --- case 1: the guard refuses under an agent-session marker ----------------
# NOT wrapped in Invoke-WithoutSessionEnv on purpose: this suite itself runs
# from inside an agent session (MB_AGENT_SESSION=1, AI_AGENT, CLAUDECODE=1 are
# already ambient and inherited by the child pwsh under test), which is
# exactly the condition this case exists to exercise. Invoke-WithFakeSessionEnv
# additionally sets the eleven CLAUDE_CODE_* variables a real child inherits,
# so the case also covers that fuller shape.
$fx = & $NewFixture -SlotCount 0 -Label 'guard'
try {
    $new = Join-Path $fx.Root 'slotX'
    Invoke-WithFakeSessionEnv {
        $script:g = Invoke-Provision $fx.Main $new
    }
    Assert-Eq $script:g.Code 4 'provisioning under an agent-session marker exits 4'
    Assert-Match $script:g.Out 'operator' 'the refusal names the operator switch'
    Assert-True (-not (Test-Path -LiteralPath $new)) 'nothing was created'
}
finally { Remove-Item -Recurse -Force $fx.Root -ErrorAction SilentlyContinue }

# --- case 2: with -Operator it proceeds, and it creates the MARKER ----------
$fx = & $NewFixture -SlotCount 0 -Label 'operator'
try {
    $new = Join-Path $fx.Root 'slotX'
    Invoke-WithFakeSessionEnv {
        $script:o = Invoke-Provision $fx.Main $new @('-Operator')
    }
    Assert-Eq $script:o.Code 0 'with -Operator the run succeeds even under the marker'
    Assert-True (Test-Path -LiteralPath (Join-Path $new '.git')) 'a linked worktree was created'
    Assert-True (Test-Path -LiteralPath (Join-Path (Join-Path $new '.superpowers') 'pool-slot')) 'the pool-slot marker was created'
    # Detached on purpose: a fresh slot must not hold a branch.
    $head = & git -C $new rev-parse --abbrev-ref HEAD 2>&1
    Assert-Eq ([string] $head).Trim() 'HEAD' 'a fresh slot is detached'
    Assert-Match $script:o.Out 'Slot provisioned: \d+ files, [\d.]+ GB \(bytes: \d+\)\.' 'the run reports the size of the new slot'
}
finally { Remove-Item -Recurse -Force $fx.Root -ErrorAction SilentlyContinue }

# --- case 3: outside an agent session no switch is needed -------------------
# Ruling A: wrapped in Invoke-WithoutSessionEnv. This suite runs FROM an agent
# session, so the ambient MB_AGENT_SESSION=1/AI_AGENT/CLAUDECODE=1 would
# otherwise be inherited by the child pwsh under test and the guard would fire
# (exit 4) here, failing this case for an environmental reason that looks like
# a code defect rather than exercising the "no marker present" path at all.
$fx = & $NewFixture -SlotCount 0 -Label 'human'
try {
    $new = Join-Path $fx.Root 'slotX'
    Invoke-WithoutSessionEnv {
        $script:r = Invoke-Provision $fx.Main $new
    }
    Assert-Eq $script:r.Code 0 'outside an agent session the guard does not fire'
    Assert-True (Test-Path -LiteralPath (Join-Path (Join-Path $new '.superpowers') 'pool-slot')) 'the marker is created on the human path too'
}
finally { Remove-Item -Recurse -Force $fx.Root -ErrorAction SilentlyContinue }

# --- case 4: an existing current hook is NOT reinstalled --------------------
# Ruling A: wrapped in Invoke-WithoutSessionEnv, same reason as case 3.
$fx = & $NewFixture -SlotCount 0 -Label 'hook'
try {
    $hook = Join-Path (Join-Path (Join-Path $fx.Main '.git') 'hooks') 'pre-push'
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $hook) | Out-Null
    $marker = 'MARKER-SENTINEL-DO-NOT-OVERWRITE'
    Set-Content -LiteralPath $hook -Value "#!/bin/sh`n# UMS pre-push guard (Publication Contract) v2`n# $marker`nexit 0`n" -Encoding utf8 -NoNewline
    $new = Join-Path $fx.Root 'slotX'
    Invoke-WithoutSessionEnv {
        $script:r4 = Invoke-Provision $fx.Main $new
    }
    Assert-Eq $script:r4.Code 0 'provisioning succeeds with a current hook already in place'
    Assert-Match (Get-Content -LiteralPath $hook -Raw) $marker 'a current marked v2 hook is left untouched'
    # Fix round 1, Gate 1: 'v2' alone appears on BOTH branches ("current (v2)
    # ... not reinstalling" AND "missing or older than v2 ... installing"), so
    # it passed identically whether the hook was correctly left alone or
    # wrongly reinstalled. Match the phrase unique to the "left alone" branch,
    # and independently assert the "installing" branch's own text is absent.
    Assert-Match $script:r4.Out 'current \(v2\)' 'the run reports that the shared hook is current'
    Assert-NotMatch $script:r4.Out '— installing' 'the run does NOT take the reinstall branch'
}
finally { Remove-Item -Recurse -Force $fx.Root -ErrorAction SilentlyContinue }

# --- case 5: an existing target path is refused, never overwritten ----------
# Ruling A: wrapped in Invoke-WithoutSessionEnv, same reason as case 3.
$fx = & $NewFixture -SlotCount 0 -Label 'exists'
try {
    $new = Join-Path $fx.Root 'slotX'
    New-Item -ItemType Directory -Force -Path $new | Out-Null
    Set-Content -LiteralPath (Join-Path $new 'keepme.txt') -Value 'operator content' -Encoding utf8
    Invoke-WithoutSessionEnv {
        $script:r5 = Invoke-Provision $fx.Main $new
    }
    Assert-Eq $script:r5.Code 1 'a non-empty existing target path is an input error'
    Assert-Match (Get-Content -LiteralPath (Join-Path $new 'keepme.txt') -Raw) 'operator content' 'existing content is untouched'
}
finally { Remove-Item -Recurse -Force $fx.Root -ErrorAction SilentlyContinue }

# --- case 6: MB_AGENT_SESSION alone is sufficient to fire the guard ---------
# Added during step-5 negativity part 2 (plan Global Constraints / brief step
# 5): dropping MB_AGENT_SESSION from the guard's OR-list left the whole suite
# green (see report) — cases 1-2 still fire the guard through the ambient
# AI_AGENT/CLAUDECODE this suite itself runs under, and cases 3-5 remove ALL
# three markers via Invoke-WithoutSessionEnv, so none of them isolates this
# ONE variable's own contribution to $agentMarker. This case closes that gap:
# clear all three markers, then set back only MB_AGENT_SESSION.
$fx = & $NewFixture -SlotCount 0 -Label 'solo-marker'
try {
    $new = Join-Path $fx.Root 'slotX'
    Invoke-WithoutSessionEnv {
        $env:MB_AGENT_SESSION = '1'
        try {
            $script:r6 = Invoke-Provision $fx.Main $new
        }
        finally {
            Remove-Item -Path Env:MB_AGENT_SESSION -ErrorAction SilentlyContinue
        }
    }
    Assert-Eq $script:r6.Code 4 'MB_AGENT_SESSION=1 alone, with AI_AGENT and CLAUDECODE genuinely absent, still fires the guard'
    Assert-True (-not (Test-Path -LiteralPath $new)) 'nothing was created (solo MB_AGENT_SESSION case)'
}
finally { Remove-Item -Recurse -Force $fx.Root -ErrorAction SilentlyContinue }

# --- case 7 (Gate 2, fix round 1): the hook check is asked FROM THE SLOT ----
# The fixture never sets core.hooksPath, so with a plain shared .git the slot
# and the main worktree resolve to the IDENTICAL physical hook file — that
# alone cannot distinguish "asked from the slot" from "asked from the repo".
# A RELATIVE core.hooksPath resolves PER WORKING TREE, so it is the only axis
# that can tell the two apart: git itself returns the SAME relative string
# ("customhooks/pre-push") from both worktrees (measured), and the divergence
# is entirely in how pool-provision.ps1 joins that relative string onto a
# root — $Path (the slot, correct) vs $RepoPath (the primary worktree,
# wrong). This asserts only the REPORTED path, not that installation
# succeeds — the path is the discriminating axis; whether
# install-git-hooks.ps1 itself succeeds here is exercised elsewhere (and by
# gate 3's case 8, for the "does not" side).
$fx = & $NewFixture -SlotCount 0 -Label 'hookspath'
try {
    & git -C $fx.Main config core.hooksPath customhooks
    $new = Join-Path $fx.Root 'slotX'
    Invoke-WithoutSessionEnv {
        $script:r7 = Invoke-Provision $fx.Main $new
    }
    Assert-True (@(0, 5) -contains $script:r7.Code) 'the run reaches a definite outcome (confirmed or unconfirmed guarantee), not an input/guard failure'
    $m7 = [regex]::Match($script:r7.Out, 'guard is (?:current \(v2\)|missing or older than v2) at (?<p>\S+) —')
    Assert-True $m7.Success 'the run reports a resolved hook path'
    $reportedPath = ($m7.Groups['p'].Value).Replace('\', '/').ToLowerInvariant()
    $slotNorm = (([IO.Path]::GetFullPath($new)).Replace('\', '/')).ToLowerInvariant()
    $mainNorm = (([IO.Path]::GetFullPath($fx.Main)).Replace('\', '/')).ToLowerInvariant()
    Assert-True ($reportedPath.StartsWith($slotNorm)) 'the reported hook path is under the SLOT (per-worktree relative core.hooksPath resolved against -Path)'
    Assert-True (-not ($reportedPath.StartsWith($mainNorm))) 'the reported hook path is NOT under the primary worktree'
}
finally { Remove-Item -Recurse -Force $fx.Root -ErrorAction SilentlyContinue }

# --- case 8 (Gate 3, fix round 1): unconfirmed guarantee reports exit 5 -----
# Forces the "install-git-hooks.ps1 exited non-zero" sub-path: pre-placing a
# foreign, non-UMS hook AND its own already-chained sibling
# (pre-push.ums-chained) makes install-git-hooks.ps1's Move-ForeignHook refuse
# to overwrite the existing chained file (its EXIT_NOT_INSTALLED path), so it
# leaves the foreign hook alone and exits non-zero. pool-provision.ps1 must
# report exit 5 — NOT 0 (that would claim success it never established) and
# NOT 1 (the worktree really was created; 1 means input/script failure) — and
# must NOT unwind the worktree or the marker it already wrote.
$fx = & $NewFixture -SlotCount 0 -Label 'unconfirmed'
try {
    $hooksDir = Join-Path (Join-Path $fx.Main '.git') 'hooks'
    New-Item -ItemType Directory -Force -Path $hooksDir | Out-Null
    Set-Content -LiteralPath (Join-Path $hooksDir 'pre-push') -Value "#!/bin/sh`n# a foreign, unrelated hook`nexit 0`n" -Encoding utf8 -NoNewline
    Set-Content -LiteralPath (Join-Path $hooksDir 'pre-push.ums-chained') -Value "#!/bin/sh`n# pretend a chained hook is already here`nexit 0`n" -Encoding utf8 -NoNewline
    $new = Join-Path $fx.Root 'slotX'
    Invoke-WithoutSessionEnv {
        $script:r8 = Invoke-Provision $fx.Main $new
    }
    Assert-Eq $script:r8.Code 5 'a run that cannot confirm the publication guarantee reports exit 5, not 0'
    Assert-True (Test-Path -LiteralPath (Join-Path $new '.git')) 'the worktree is NOT unwound even when the guarantee is unconfirmed'
    Assert-True (Test-Path -LiteralPath (Join-Path (Join-Path $new '.superpowers') 'pool-slot')) 'the marker is NOT unwound either'
    Assert-Match $script:r8.Out 'NOT confirmed' 'the run names the unconfirmed guarantee'
}
finally { Remove-Item -Recurse -Force $fx.Root -ErrorAction SilentlyContinue }

Complete-Tests
