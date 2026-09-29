#Requires -Version 7
# Contract core injector (contract, "Session Eligibility"); design UMS-3551, §3.
# SessionStart and UserPromptSubmit(after a compaction marker) inject the core
# as additionalContext; PostCompact cannot carry additionalContext (Claude Code
# hooks reference), so it writes a marker and a systemMessage instead.
# Informational hook: every failure path exits 0.
param([string] $Event = '')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$MaxPayloadBytes = 49152
$corePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'skills\shared\UMS_MEMORY_BANK_CONTRACT.md'
$FallbackText = "Read $corePath (contract core) and memory-bank/context.md before relying on any Memory Bank-aware behaviour."
$Instruction = 'Invoke the Skill tool with skill: using-superpowers first, then read your active skill''s references named in its banner. Then run the Session Eligibility check (contract, "Session Eligibility"). If a skill body was re-injected after compaction it may be truncated at 5,000 tokens — before continuing, read that skill''s UMS-OVERLAY block from its SKILL.md.'

function Emit-Context([string] $EventName, [string] $Text) {
    $p = [pscustomobject] @{ hookSpecificOutput = [pscustomobject] @{ hookEventName = $EventName; additionalContext = $Text } }
    Write-Output ($p | ConvertTo-Json -Depth 5 -Compress)
}
function Test-Hostile([string] $v) { return ($v -match '[<>]' -or $v -match '\p{Cc}' -or $v -match '\p{Cf}') }

try {
    if (-not $Event) {
        $stdin = ''
        try { if (-not [Console]::IsInputRedirected) { $stdin = '' } else { $stdin = [Console]::In.ReadToEnd() } } catch { $stdin = '' }
        if ($stdin) { try { $Event = [string] (($stdin | ConvertFrom-Json).hook_event_name) } catch { $Event = '' } }
    }
    if ($Event -notin @('SessionStart', 'PostCompact', 'UserPromptSubmit')) { exit 0 }

    $root = & git rev-parse --show-toplevel 2>$null
    $hasRoot = ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($root))
    if ($hasRoot) { $root = ([string] $root).Trim() }
    $marker = if ($hasRoot) { Join-Path (Join-Path $root '.superpowers') 'contract-reload.flag' } else { '' }

    if ($Event -eq 'PostCompact') {
        if ($hasRoot) {
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $marker) | Out-Null
            [IO.File]::WriteAllText($marker, [datetimeoffset]::UtcNow.ToString('o'), (New-Object Text.UTF8Encoding($false)))
        }
        Write-Output (([pscustomobject] @{ systemMessage = 'Context was compacted. The contract core is re-injected with your next prompt; until then act on the summary and re-invoke the skill you are executing.' }) | ConvertTo-Json -Compress)
        exit 0
    }
    if ($Event -eq 'UserPromptSubmit') {
        if (-not $hasRoot -or -not (Test-Path -LiteralPath $marker -PathType Leaf)) { exit 0 }
        Remove-Item -LiteralPath $marker -Force
    }

    if (-not (Test-Path -LiteralPath $corePath -PathType Leaf)) { Emit-Context $Event $FallbackText; exit 0 }
    $coreText = Get-Content -LiteralPath $corePath -Raw -Encoding utf8
    if ($null -eq $coreText -or [Text.Encoding]::UTF8.GetByteCount($coreText) -gt $MaxPayloadBytes) { Emit-Context $Event $FallbackText; exit 0 }

    $parts = @()
    if ($hasRoot) {
        $sourceCorePath = Join-Path $root 'ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md'
        if (Test-Path -LiteralPath $sourceCorePath -PathType Leaf) {
            $deployedHash = (Get-FileHash -LiteralPath $corePath -Algorithm SHA256).Hash
            $sourceHash = (Get-FileHash -LiteralPath $sourceCorePath -Algorithm SHA256).Hash
            if ($deployedHash -ne $sourceHash) {
                $warning = 'WARNING: deployed contract core differs from source ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md — refresh the deployment (playbook, "Když nasazuješ nebo revendoruješ").'
                $parts = @($warning, '')
            }
        }
    }
    $parts += @('<contract-core>', $coreText.TrimEnd(), '</contract-core>', '')
    $ctxLines = @('(context.md missing)')
    if ($hasRoot) {
        $ctxPath = Join-Path (Join-Path $root 'memory-bank') 'context.md'
        if (Test-Path -LiteralPath $ctxPath -PathType Leaf) {
            $raw = Get-Content -LiteralPath $ctxPath -Encoding utf8
            $ctxLines = @(@($raw) | Where-Object { $_ -match '^\s*-\s+\*\*[A-Za-z][A-Za-z ]+:\*\*\s+.*$' -or $_.Trim() -eq '(No active work - IDLE phase)' } | Where-Object { -not (Test-Hostile $_) })
            if ($ctxLines.Count -eq 0) { $ctxLines = @('(context.md carries no pin)') }
        }
    }
    $parts += @('<memory-bank-context>') + $ctxLines + @('</memory-bank-context>', '')

    if ($hasRoot) {
        $slugLine = @($ctxLines | Where-Object { $_ -match '\*\*(Work item|Proposal):\*\*\s+(?<s>\S+)' })
        $slug = $null
        if ($slugLine.Count -gt 0 -and $slugLine[0] -match '\*\*(Work item|Proposal):\*\*\s+(?<s>\S+)') { $slug = $Matches['s'] }
        # Slug reaches a filesystem path below (Join-Path into .superpowers/sdd/),
        # and it is attacker-reachable text from context.md — a value like
        # "x/../../../../outside" is a valid \S+ match but a path traversal once
        # joined. Whitelisting the charset (no `/`, `\`, or `..`-enabling
        # separators) before it goes anywhere near Join-Path is the fix; a slug
        # that fails simply yields no NOW block, same as any other unreadable
        # ledger.
        if ($null -ne $slug -and $slug -match '^[A-Za-z0-9_.-]+$') {
            # The ledger's home is decided by the workspace's plan-path marker, not
            # by the directory name: upstream sdd-workspace writes the owning plan's
            # path into .superpowers/sdd/<dir>/plan-path and, when plan_<slug>/ is
            # owned by another plan, creates plan_<slug>-<parent>/ instead. The pin
            # is attacker-reachable text like the slug, so it passes a character
            # whitelist (no `..` segment) before it is built into a comparison
            # string; the marker file is untrusted too — size-bounded, trimmed,
            # compared as a string, never executed or emitted.
            $pin = $null
            $pinLine = @($ctxLines | Where-Object { $_ -match '\*\*Target MB Pin:\*\*\s+(?<p>\S+)' })
            if ($pinLine.Count -gt 0 -and $pinLine[0] -match '\*\*Target MB Pin:\*\*\s+(?<p>\S+)') { $pin = $Matches['p'] }
            if ($null -ne $pin -and $pin -match '^[A-Za-z0-9_./-]+$' -and $pin -notmatch '(^|/)\.\.(/|$)') {
                if (-not $pin.EndsWith('/')) { $pin += '/' }
            } else { $pin = $null }
            $wsDir = $null
            $sddDir = Join-Path $root '.superpowers/sdd'
            if ($null -ne $pin -and (Test-Path -LiteralPath $sddDir -PathType Container)) {
                $rootFwd = $root.Replace('\', '/').TrimEnd('/')
                $rootMsys = if ($rootFwd -match '^(?<d>[A-Za-z]):/(?<r>.*)$') { '/' + $Matches['d'].ToLowerInvariant() + '/' + $Matches['r'] } else { $rootFwd }
                # Accepted spellings of the active pair's plan path (plan_ first, legacy
                # proposal_ second). Upstream writes the repo-relative form; under Git
                # Bash on Windows it writes this repo's absolute msys form instead.
                $wanted = @()
                foreach ($f in @("plan_$slug.md", "proposal_$slug.md")) {
                    $rel = $pin + 'proposals/active/' + $f
                    $wanted += @($rel, "$rootFwd/$rel", "$rootMsys/$rel")
                }
                $claims = @()
                foreach ($d in @(Get-ChildItem -LiteralPath $sddDir -Directory -ErrorAction SilentlyContinue | Where-Object { -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) } | Sort-Object Name | Select-Object -First 200)) {
                    $mf = Join-Path $d.FullName 'plan-path'
                    if (-not (Test-Path -LiteralPath $mf -PathType Leaf)) { continue }
                    if ((Get-Item -LiteralPath $mf).Length -gt 1024) { continue }
                    $mv = ([IO.File]::ReadAllText($mf)).Trim()
                    if ($wanted -ccontains $mv) { $claims += $d.FullName }
                }
                # Exactly one claimant; two workspaces naming the same plan are ambiguous
                # and yield no block.
                if ($claims.Count -eq 1) { $wsDir = $claims[0] }
                elseif ($claims.Count -eq 0) {
                    # A workspace from before the marker scheme has no plan-path file;
                    # only then is the plain-slug directory the ledger's home.
                    $legacy = Join-Path $sddDir ("plan_" + $slug)
                    if ((Test-Path -LiteralPath $legacy -PathType Container) -and -not (Test-Path -LiteralPath (Join-Path $legacy 'plan-path'))) { $wsDir = $legacy }
                }
            }
            elseif ($null -eq $pin) {
                $legacy = Join-Path $sddDir ("plan_" + $slug)
                if ((Test-Path -LiteralPath $legacy -PathType Container) -and -not (Test-Path -LiteralPath (Join-Path $legacy 'plan-path'))) { $wsDir = $legacy }
            }
            $ledger = if ($null -ne $wsDir) { Join-Path $wsDir 'progress.md' } else { '' }
            if ($ledger -and (Test-Path -LiteralPath $ledger -PathType Leaf)) {
                $l = @(Get-Content -LiteralPath $ledger -Encoding utf8)
                $b = [array]::IndexOf($l, '<!-- UMS-NOW BEGIN -->'); $e = [array]::IndexOf($l, '<!-- UMS-NOW END -->')
                if ($b -ge 0 -and $e -gt $b) {
                    $kv = @($l[($b + 1)..($e - 1)] | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
                    $ok = ($kv.Count -eq 6)
                    $rendered = @()
                    foreach ($line in $kv) {
                        $m = [regex]::Match($line, '^(?<k>State|Waiting on|Since|Due|Task|Look at):\s*(?<v>.*)$')
                        if (-not $m.Success -or (Test-Hostile $m.Groups['v'].Value)) { $ok = $false; break }
                        $rendered += "$($m.Groups['k'].Value): $($m.Groups['v'].Value.Trim())"
                    }
                    if ($ok) { $parts += @('<now-block>') + $rendered + @('</now-block>', '') } else { $parts += @('now-block: rejected (character class)', '') }
                }
            }
        }
    }
    $parts += $Instruction
    $payload = $parts -join "`n"
    if ([Text.Encoding]::UTF8.GetByteCount($payload) -gt $MaxPayloadBytes) { Emit-Context $Event $FallbackText; exit 0 }
    Emit-Context $Event $payload
}
catch { }
exit 0
