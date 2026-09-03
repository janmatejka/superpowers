#Requires -Version 7
<#
.SYNOPSIS
Derives the state of the pool slots of this repository. Read-only; the only
write is the optional -Json file.

.DESCRIPTION
Membership of the pool is DERIVED, never configured: candidates come from one
read of `git worktree list --porcelain` (linked, non-bare, not the primary
worktree, not the one this script was pointed at), and a candidate becomes a
slot only when it carries the marker file .superpowers/pool-slot.

Freedom is derived from PER-WORKTREE signals only. In a linked worktree just
HEAD and the index are per-worktree; refs/stash and refs/heads are SHARED, so
`git stash list` and `git log --branches --not --remotes` answer the same from
every slot and would freeze the whole pool over one stash or one unpushed
commit anywhere. See the contract, "A pool slot's freedom is derived from
per-worktree signals only".

Occupancy is read from the harness (`claude agents --json --cwd <slot>`), not
from git: a slot whose session has just started, before it reaches its pin
write, looks free to git for about a minute. The signal is fail-closed —
unreadable means UNKNOWN, and UNKNOWN is not free.

Every `excluded` entry also carries `branch`: the porcelain branch name, or
null when the worktree is detached, bare or prunable. This lets a consumer
(Task 6's spawn eligibility gate) answer "is this ticket branch checked out
anywhere" from the union of slots[].branch and excluded[].branch without
running `git worktree list` itself — that command is separately denied to the
Bash tool.

.PARAMETER RepoPath
Repository root. Defaults to the toplevel of the current directory.

.PARAMETER Epic
Optional epic key. When given, a slot holding a ticket branch of this epic is
reported as such and is not free for a spawn of that epic. Compared
case-sensitively (-cmatch): an epic key differing only in case must not match.

.PARAMETER Json
Optional path to also write the full state as JSON. The path is validated
BEFORE any work, never at write time: in a fresh worktree a missing
.superpowers/ is the normal state, and failing at the end would print a
healthy-looking report and then exit 1 with no file.

.PARAMETER ClaudeCommand
Harness executable used for the occupancy probe. Empty (the default) resolves
`claude` through Get-Command; tests point it at a stub. Never hardcode a path.

.OUTPUTS
English summary on stdout. Exit: 0 = OK, 1 = input/script failure,
3 = the repository has no pool (no marked worktree).
#>
[CmdletBinding()]
param(
    [string] $RepoPath = '',
    [string] $Epic = '',
    [string] $Json = '',
    [string] $ClaudeCommand = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }

# Never name a function `Git`: PowerShell command discovery prefers a function
# over an application, case-insensitively, so `& git ...` inside it would
# recurse until the stack overflows.
function Invoke-RepoGit([string] $Dir, [string[]] $GitArgs) {
    $out = & git -C $Dir @GitArgs 2>&1
    return @{ Out = @($out); Code = $LASTEXITCODE }
}

function ConvertTo-SlashPath([string] $Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    return ([IO.Path]::GetFullPath($Path)).Replace('\', '/').TrimEnd('/')
}

# Windows paths are case-INSENSITIVE and [IO.Path]::GetFullPath does not
# canonicalise case, so two spellings of the same path (the porcelain record's
# vs. the caller's -RepoPath) can differ only in case and still name the same
# worktree. Normalise BOTH sides to lower-case before comparing so the
# "orchestrator's own worktree" exclusion cannot be missed by a casing
# mismatch — keep -ceq (not -ieq) on the normalised copies, per the Global
# Constraint that git-derived operands compare case-sensitively; this
# compares two ALREADY-lower-cased strings, it does not relax the operator.
function ConvertTo-ComparablePath([string] $Path) {
    return (ConvertTo-SlashPath $Path).ToLowerInvariant()
}

if ([string]::IsNullOrWhiteSpace($RepoPath)) {
    $top = & git rev-parse --show-toplevel 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($top)) {
        Write-Error 'Git repository not found. Memory Bank requires git.'
        exit 1
    }
    $RepoPath = ([string] $top).Trim()
}
if (-not (Test-Path -LiteralPath $RepoPath -PathType Container)) {
    Write-Error "Repository path does not exist: $RepoPath"; exit 1
}
# -Json is checked BEFORE any work, for the reason in the parameter help.
if ($Json) {
    $jsonDir = Split-Path -Parent ([IO.Path]::GetFullPath($Json))
    if (-not (Test-Path -LiteralPath $jsonDir -PathType Container)) {
        Write-Error "-Json target directory does not exist: $jsonDir"; exit 1
    }
}

$repoAbs = ConvertTo-SlashPath $RepoPath

# --- worktree enumeration ----------------------------------------------------
# The porcelain record carries more than a path and a branch, and the
# derivation has to survive all of it: `bare` is skipped, `locked` and
# `prunable` are NOT candidates and are reported with a named reason —
# a prunable worktree's directory is gone, so `git -C <path> status` could not
# even be run there.
$wtRes = Invoke-RepoGit $RepoPath @('worktree', 'list', '--porcelain')
if ($wtRes.Code -ne 0) { Write-Error "git worktree list failed: $($wtRes.Out -join "`n")"; exit 1 }

$records = @()
$cur = $null
foreach ($line in $wtRes.Out) {
    $text = [string] $line
    if ($text -match '^worktree (?<p>.+)$') {
        if ($null -ne $cur) { $records += $cur }
        $cur = @{ Path = $Matches['p']; Head = ''; Branch = ''; Detached = $false; Bare = $false; Locked = ''; Prunable = '' }
        continue
    }
    if ($null -eq $cur) { continue }
    if ($text -match '^HEAD (?<h>\S+)$')        { $cur.Head = $Matches['h']; continue }
    if ($text -match '^branch refs/heads/(?<b>.+)$') { $cur.Branch = $Matches['b']; continue }
    if ($text -eq 'detached')                   { $cur.Detached = $true; continue }
    if ($text -eq 'bare')                       { $cur.Bare = $true; continue }
    if ($text -match '^locked ?(?<r>.*)$')      { $cur.Locked = if ($Matches['r']) { $Matches['r'] } else { 'no reason given' }; continue }
    if ($text -match '^prunable ?(?<r>.*)$')    { $cur.Prunable = if ($Matches['r']) { $Matches['r'] } else { 'no reason given' }; continue }
}
if ($null -ne $cur) { $records += $cur }

# Ruling A: the branch reported on an excluded entry, or $null when the
# worktree is detached, bare or prunable — a prunable worktree's directory may
# already be gone, and its branch line (if any) is stale.
function Get-ExcludedBranch($Record) {
    if ($Record.Detached -or $Record.Bare -or $Record.Prunable) { return $null }
    if ($Record.Branch) { return $Record.Branch }
    return $null
}

# The FIRST porcelain record is always the main worktree; it is not a slot, and
# neither is the worktree this script was pointed at (the orchestrator's own).
$candidates = @()
$excluded = @()
for ($i = 0; $i -lt $records.Count; $i++) {
    $r = $records[$i]
    $abs = ConvertTo-SlashPath $r.Path
    $branch = Get-ExcludedBranch $r
    if ($i -eq 0)   { $excluded += @{ path = $abs; reason = 'primary worktree'; branch = $branch }; continue }
    if ($r.Bare)    { $excluded += @{ path = $abs; reason = 'bare worktree'; branch = $branch }; continue }
    if ((ConvertTo-ComparablePath $r.Path) -ceq (ConvertTo-ComparablePath $RepoPath)) { $excluded += @{ path = $abs; reason = "the orchestrator's own worktree"; branch = $branch }; continue }
    if ($r.Prunable) { $excluded += @{ path = $abs; reason = "prunable: $($r.Prunable)"; branch = $branch }; continue }
    if ($r.Locked)   { $excluded += @{ path = $abs; reason = "locked: $($r.Locked)"; branch = $branch }; continue }
    if (-not (Test-Path -LiteralPath (Join-Path (Join-Path $r.Path '.superpowers') 'pool-slot') -PathType Leaf)) {
        $excluded += @{ path = $abs; reason = 'no pool-slot marker'; branch = $branch }; continue
    }
    $r.Abs = $abs
    $candidates += $r
}

# --- occupancy ---------------------------------------------------------------
$claude = $ClaudeCommand
if ([string]::IsNullOrWhiteSpace($claude)) {
    $cmd = Get-Command claude -ErrorAction SilentlyContinue
    if ($cmd) { $claude = $cmd.Source }
}
$occupancySource = if ($claude) { 'claude' } else { 'unavailable' }

function Get-SlotSession([string] $Claude, [string] $SlotPath) {
    # Returns @{ state = 'live'|'none'|'unknown'; pids = @() }. Fail-closed:
    # anything unreadable OR any output that does not match the documented
    # shape ("a JSON array of records") is 'unknown', which the caller must
    # not treat as free. Three shapes used to read as 'none' (fail-OPEN) and
    # were fixed here (Gate item 2 of fix round 1):
    #   1. exit 0 with empty/whitespace output — measured, the real harness
    #      answers a session-less slot with `[]` (three bytes), never nothing;
    #      silence is an anomaly in the contract, not evidence of zero sessions.
    #   2. the bare JSON literal `null` — was fail-open while `not json at all`
    #      was already fail-closed, an arbitrary asymmetry.
    #   3. a top-level JSON OBJECT rather than an array (e.g. `{"agents":[...]}`)
    #      — the most dangerous: it has no `pid` property, the per-item loop
    #      below just skips it, and every slot would read 'none'/free on a
    #      harness-side output-shape change instead of failing loudly. The
    #      design states the shape of `claude agents --json` is not stable and
    #      the signal is therefore fail-closed.
    if (-not $Claude) { return @{ state = 'unknown'; pids = @() } }
    $raw = ''
    try { $raw = (& $Claude agents --json --cwd $SlotPath 2>&1 | Out-String) }
    catch { return @{ state = 'unknown'; pids = @() } }
    if ($LASTEXITCODE -ne 0) { return @{ state = 'unknown'; pids = @() } }
    if ([string]::IsNullOrWhiteSpace($raw)) { return @{ state = 'unknown'; pids = @() } }
    $trimmed = $raw.Trim()
    # Check the RAW TEXT prefix, not the parsed value: ConvertFrom-Json
    # collapses BOTH the literal `null` and the empty array `[]` to PowerShell
    # $null (the well-known zero/one-pipeline-object capture quirk), so a
    # post-parse `$null` check cannot tell "not an array" apart from "an array
    # with nothing in it" — and a bare top-level object parses to a lone
    # PSCustomObject exactly like a genuine single-element array does. Only
    # the untouched source text can distinguish "not an array at all" from
    # "an array with 0 or 1 elements", which is why this check runs BEFORE
    # ConvertFrom-Json is ever called.
    if (-not $trimmed.StartsWith('[')) { return @{ state = 'unknown'; pids = @() } }
    $parsed = $null
    try { $parsed = $trimmed | ConvertFrom-Json } catch { return @{ state = 'unknown'; pids = @() } }
    # A successful ConvertFrom-Json does NOT mean an object with properties:
    # the empty array `[]` parses to $null here (see above) — genuinely "no
    # sessions", now that the text prefix already proved it WAS an array.
    if ($null -eq $parsed) { return @{ state = 'none'; pids = @() } }
    $items = @($parsed)
    if ($items.Count -eq 0) { return @{ state = 'none'; pids = @() } }
    $pids = @()
    foreach ($it in $items) {
        if ($it -isnot [System.Management.Automation.PSCustomObject]) { return @{ state = 'unknown'; pids = @() } }
        $names = @(@($it.PSObject.Properties) | ForEach-Object { $_.Name })
        if ($names -notcontains 'pid') { continue }
        if ($null -eq $it.pid -or [string]::IsNullOrWhiteSpace([string] $it.pid)) { continue }
        # Rider: guard the numeric cast. A record with "pid": "n/a" must mark
        # THIS slot unknown, not throw uncaught under
        # $ErrorActionPreference = 'Stop' and abort the whole report.
        $parsedPid = 0
        if (-not [int]::TryParse([string] $it.pid, [ref] $parsedPid)) { return @{ state = 'unknown'; pids = @() } }
        $pids += $parsedPid
    }
    if ($pids.Count -gt 0) { return @{ state = 'live'; pids = $pids } }
    return @{ state = 'none'; pids = @() }
}

# --- per-slot derivation -----------------------------------------------------
function Get-SlotPin([string] $SlotPath) {
    # Returns @{ Pin = <pscustomobject>|$null; Unreadable = $true|$false }.
    #
    # Three facts collapse to Pin=$null, and ALL THREE are legitimately IDLE
    # per the contract ("ACTIVE and IDLE are state NAMES, not tokens in the
    # file ... a block with no pin is the IDLE state"): the file is absent,
    # the file reads as empty/whitespace, or the file is READABLE but its
    # Active Work block carries no full pin pair (a PARTIAL pin — slug without
    # target, or vice versa — is not a pin).
    #
    # A FOURTH fact is different and must NOT collapse into the same $null:
    # the file EXISTS and CANNOT BE READ (the `catch` below). That is not "a
    # block with no pin" — it is an unreadable per-worktree signal, exactly
    # like `status unreadable` and `unpushed count unreadable` elsewhere in
    # this script, and occupancy `unknown`. Reporting it as IDLE would be
    # fail-OPEN; Unreadable=$true lets the caller add a fail-closed reason
    # without inventing a fake pin.
    $ctx = Join-Path (Join-Path $SlotPath 'memory-bank') 'context.md'
    if (-not (Test-Path -LiteralPath $ctx -PathType Leaf)) { return @{ Pin = $null; Unreadable = $false } }
    $text = ''
    try { $text = Get-Content -LiteralPath $ctx -Raw -Encoding utf8 }
    catch { return @{ Pin = $null; Unreadable = $true } }
    if ($null -eq $text) { return @{ Pin = $null; Unreadable = $false } }
    # ACTIVE is a state NAME, never a token in the file: the mechanical test is
    # whether the Active Work block carries a pin. `- **Proposal:**` is the
    # mandated legacy alias of `- **Work item:**`.
    $slug = [regex]::Match($text, '(?m)^\s*-\s+\*\*(?:Work item|Proposal):\*\*\s*(?<v>\S+)\s*$')
    $target = [regex]::Match($text, '(?m)^\s*-\s+\*\*Target MB Pin:\*\*\s*(?<v>\S+)\s*$')
    if (-not ($slug.Success -and $target.Success)) { return @{ Pin = $null; Unreadable = $false } }
    $jira = [regex]::Match($text, '(?m)^\s*-\s+\*\*Jira:\*\*\s*(?<v>\S+)')
    $pin = [pscustomobject] @{
        targetMb = $target.Groups['v'].Value
        slug     = $slug.Groups['v'].Value
        jira     = if ($jira.Success) { $jira.Groups['v'].Value } else { '' }
    }
    return @{ Pin = $pin; Unreadable = $false }
}

function Get-SlotProgress([string] $SlotPath, [string] $Slug) {
    # Paired to the slug the PIN names, never to "the first directory found
    # under sdd/": a slot can carry the leftover ledger of earlier work, and a
    # leftover slug can sort first.
    if ([string]::IsNullOrWhiteSpace($Slug)) { return $null }
    $rel = ".superpowers/sdd/plan_$Slug/progress.md"
    $full = Join-Path $SlotPath ($rel -replace '/', [IO.Path]::DirectorySeparatorChar)
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
        return [pscustomobject] @{ path = $rel; exists = $false; lines = 0; lastLine = '' }
    }
    $lines = @(Get-Content -LiteralPath $full -Encoding utf8)
    $last = @($lines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Last 1)
    return [pscustomobject] @{
        path     = $rel
        exists   = $true
        lines    = $lines.Count
        lastLine = if ($last.Count -gt 0) { ([string] $last[0]).Trim() } else { '' }
    }
}

$slots = @()
foreach ($c in $candidates) {
    $reasons = @()

    $st = Invoke-RepoGit $c.Path @('status', '--porcelain')
    $dirty = if ($st.Code -eq 0) { @($st.Out | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count } else { -1 }
    if ($dirty -lt 0) { $reasons += 'status unreadable' } elseif ($dirty -gt 0) { $reasons += "dirty tree ($dirty entries)" }

    # Unpushed commits OF THIS SLOT. With an upstream the question is exact;
    # without one, `HEAD --not --remotes` is still per-worktree because HEAD is.
    $ups = Invoke-RepoGit $c.Path @('rev-parse', '--abbrev-ref', '@{upstream}')
    if ($ups.Code -eq 0) {
        $unpRes = Invoke-RepoGit $c.Path @('log', '--oneline', '@{upstream}..HEAD')
        $unpSource = 'upstream'
    } else {
        $unpRes = Invoke-RepoGit $c.Path @('log', '--oneline', 'HEAD', '--not', '--remotes')
        $unpSource = 'head-not-remotes'
    }
    $unpushed = if ($unpRes.Code -eq 0) { @($unpRes.Out | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count } else { -1 }
    if ($unpushed -lt 0) { $reasons += 'unpushed count unreadable' } elseif ($unpushed -gt 0) { $reasons += "unpushed commits ($unpushed)" }

    $pinResult = Get-SlotPin $c.Path
    $pin = $pinResult.Pin
    if ($pinResult.Unreadable) { $reasons += 'pin unreadable (fail-closed)' }
    if ($null -ne $pin) { $reasons += "ACTIVE pin: $($pin.slug)" }

    $session = Get-SlotSession $claude $c.Path
    if ($session.state -eq 'live') { $reasons += "live session (pid $($session.pids -join ', '))" }
    if ($session.state -eq 'unknown') { $reasons += 'occupancy unknown (fail-closed)' }

    # Ruling B: case-sensitive (-cmatch). Global Constraint requires
    # case-sensitive comparison on git-derived operands, and Task 6 compares
    # branch names case-sensitively — an epic key differing only in case must
    # not match.
    if ($Epic -and $c.Branch -and ($c.Branch -cmatch [regex]::Escape($Epic))) {
        $reasons += "holds a ticket branch of $Epic"
    }

    $slots += [pscustomobject] @{
        name           = Split-Path -Leaf $c.Abs
        path           = $c.Abs
        branch         = if ($c.Branch) { $c.Branch } else { $null }
        detached       = $c.Detached
        head           = $c.Head
        dirtyCount     = $dirty
        unpushedCount  = $unpushed
        unpushedSource = $unpSource
        pin            = $pin
        progress       = if ($null -ne $pin) { Get-SlotProgress $c.Path $pin.slug } else { $null }
        session        = [pscustomobject] @{ state = $session.state; pids = @($session.pids) }
        free           = ($reasons.Count -eq 0)
        reasons        = @($reasons)
    }
}

# Repo-wide, reported once, never attached to a slot.
# The @() MUST wrap the WHOLE if/else, not the inner branch: an if-expression
# streams its branch's output through the pipeline before assignment sees it,
# so an inner `@(<empty>)` unrolls to zero objects and the outer `$stash =`
# collapses to $null, not an empty array, under Set-StrictMode -Version Latest.
$stashRes = Invoke-RepoGit $RepoPath @('stash', 'list')
$stash = @(if ($stashRes.Code -eq 0) { $stashRes.Out | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { [string] $_ } } else { @() })

$state = [pscustomobject] @{
    repoRoot        = $repoAbs
    generatedAt     = [datetimeoffset]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
    occupancySource = $occupancySource
    stashCount      = $stash.Count
    slots           = @($slots)
    excluded        = @($excluded | ForEach-Object { [pscustomobject] $_ })
    stash           = $stash
}

if ($Json) { $state | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Json -Encoding utf8 }

Write-Output "Pool status for $repoAbs"
Write-Output "Occupancy source: $occupancySource"
if ($slots.Count -eq 0) {
    Write-Output 'This repository has no pool: no linked worktree carries the .superpowers/pool-slot marker.'
    foreach ($e in $excluded) { Write-Output ("  excluded {0} — {1}" -f $e.path, $e.reason) }
    exit 3
}
foreach ($s in $slots) {
    $where = if ($s.detached) { 'detached' } else { $s.branch }
    $pinText = if ($null -eq $s.pin) { 'IDLE' } else { $s.pin.slug }
    Write-Output ("  {0}  {1}  pin={2}  dirty={3}  unpushed={4}  session={5}  free={6}" -f `
        $s.name, $where, $pinText, $s.dirtyCount, $s.unpushedCount, $s.session.state, $s.free)
    foreach ($r in $s.reasons) { Write-Output "      - $r" }
}
foreach ($e in $excluded) { Write-Output ("  excluded {0} — {1}" -f $e.path, $e.reason) }
if ($stash.Count -gt 0) {
    Write-Output "Repository-wide stash entries: $($stash.Count) (cannot be attributed to a slot)"
}
exit 0
