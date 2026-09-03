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
    Assert-Match $script:o.Out 'GB|MB|bytes' 'the run reports the size of the new slot'
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
    Assert-Match $script:r4.Out 'v2' 'the run reports that the shared hook is current'
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

Complete-Tests
