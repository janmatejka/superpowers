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

.PARAMETER NowUtc
The instant this run reads as "now", as ISO-8601 UTC. Empty (the default) is
the real clock. The `late` flag of a slot's NOW block is COMPUTED against this
value (contract, "The `NOW` Block": lateness is never written into the block),
so without an injectable clock no test of that flag could assert anything —
one that derived its expectation from [datetime]::UtcNow the same way the
script does would assert nothing at all. Validated BEFORE any work, like -Json.

.OUTPUTS
English summary on stdout. Exit: 0 = OK, 1 = input/script failure,
3 = the repository has no pool (no marked worktree).
#>
[CmdletBinding()]
param(
    [string] $RepoPath = '',
    [string] $Epic = '',
    [string] $Json = '',
    [string] $ClaudeCommand = '',
    [string] $NowUtc = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }

# --- NOW block constants (contract, "The `NOW` Block") -----------------------
# The markers are HTML comments and not a heading, so nothing that merely LOOKS
# like a heading can move the region boundary.
$NowBegin  = '<!-- UMS-NOW BEGIN -->'
$NowEnd    = '<!-- UMS-NOW END -->'
# Six items, all required, in this order. The set is CLOSED: an unknown key is
# malformed, so this array is also the whitelist.
$NowKeys   = @('State', 'Waiting on', 'Since', 'Due', 'Task', 'Look at')
$NowStates = @('stalled', 'waiting-for-subagent', 'waiting-for-human', 'waiting-for-manager')
# Bound on what is RENDERED out of the ledger — a block value and any other
# excerpt alike.
$LedgerMaxRender = 200
# Bound on what is READ. The ledger is a git-ignored scratch file in a foreign
# working tree that implementer subagents write into routinely; a status
# command must not pull an unbounded one into memory.
$LedgerMaxBytes = 1048576
# Bound on the slug lifted out of a foreign `context.md` before it becomes a
# FILENAME COMPONENT (see Test-SlotSlug).
$SlugMaxLength = 100
$IsoUtcPattern = '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z$'

# Returns a [datetimeoffset], or $null when the text is not ISO-8601 UTC. The
# regex runs FIRST because TryParse alone accepts a great deal that this closed
# format does not (a bare date, a local-time spelling, a culture-shaped date).
function ConvertTo-UtcInstant([string] $Text) {
    if ($Text -notmatch $IsoUtcPattern) { return $null }
    $parsed = [datetimeoffset]::MinValue
    if (-not [datetimeoffset]::TryParse(
            $Text,
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal,
            [ref] $parsed)) {
        return $null
    }
    return $parsed
}

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
# One clock for the whole run: the report's own timestamp and every `late`
# derivation read the same instant, so a slot cannot be judged against a
# different moment than the one the report claims to describe.
$clockUtc = [datetimeoffset]::UtcNow
if ($NowUtc) {
    $clockUtc = ConvertTo-UtcInstant $NowUtc
    if ($null -eq $clockUtc) {
        Write-Error "-NowUtc is not an ISO-8601 UTC timestamp (yyyy-MM-ddTHH:mm:ssZ): $NowUtc"; exit 1
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

# --- the ledger is UNTRUSTED input ------------------------------------------
# Contract, "The `NOW` Block": the READER-SAFETY rules of the Session Intent
# Baton apply here unchanged, and they bind everything this reader emits OUT OF
# THIS FILE — not only the marker region. The rules are stated there, once, and
# are not re-derived here; what follows is only their mechanics.

# The class check, shared by the block's values and by every other excerpt, so
# there is exactly one place where "what may leave this file" is decided.
function Test-LedgerText([string] $Text) {
    if ($null -eq $Text) { return $false }
    if ($Text -match '[<>]') { return $false }
    # Cc AND Cf. The contract states the class once ("Session Intent Baton":
    # an angle bracket, a control character or a FORMAT character); the reason
    # the format category belongs in it is that U+202E RIGHT-TO-LEFT OVERRIDE,
    # U+200B and the U+2066..U+2069 isolates carry no glyph, survive .Trim()
    # and the length bound, and reorder the manager's rendered table -- the
    # Trojan-source shape -- inside the very budget this bound grants.
    if ($Text -match '\p{Cc}') { return $false }
    if ($Text -match '\p{Cf}') { return $false }
    return $true
}

# The bound, applied in exactly one place so both callers cut the same way.
# `Substring(0, $LedgerMaxRender)` on its own can cut BETWEEN the halves of a
# surrogate pair and emit a lone surrogate into UTF-8 JSON; when the last kept
# char is a high surrogate its partner is the first dropped one, so the cut
# moves back by one char.
function Limit-LedgerText([string] $Text) {
    if ($Text.Length -le $LedgerMaxRender) { return $Text }
    $cut = $LedgerMaxRender
    if ([char]::IsHighSurrogate($Text[$cut - 1])) { $cut -= 1 }
    return $Text.Substring(0, $cut)
}

# A block value: rejected text yields $null (which makes the block malformed,
# and malformed reads as absent); over-long text is bounded, not rejected.
function ConvertTo-NowValue([string] $Text) {
    $t = ([string] $Text).Trim()
    if (-not (Test-LedgerText $t)) { return $null }
    return (Limit-LedgerText $t)
}

# Any OTHER excerpt lifted out of the same file (today: the last non-empty
# line). Same class, same bound; rejected text renders as nothing, because
# there is no "malformed" state for a bare excerpt to fall into.
function ConvertTo-LedgerExcerpt([string] $Text) {
    $t = ([string] $Text).Trim()
    if (-not (Test-LedgerText $t)) { return '' }
    return (Limit-LedgerText $t)
}

function Get-NowBlock([string[]] $Lines, [datetimeoffset] $Now) {
    # Returns the parsed block, or $null. ABSENT and MALFORMED are deliberately
    # the same answer (contract: "A malformed block is treated exactly as an
    # ABSENT one"), and absence sends the reader to go and look at the slot.
    $begins = @()
    $ends = @()
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $t = ([string] $Lines[$i]).Trim()
        if ($t -ceq $NowBegin) { $begins += $i; continue }
        if ($t -ceq $NowEnd) { $ends += $i }
    }
    if ($begins.Count -eq 0) { return $null }
    # MORE THAN ONE begin marker is malformed either way, and the two shapes
    # collapse here rather than being told apart: a second begin INSIDE the
    # region is a nested marker, and one after the region is either a second
    # complete pair (the signature of a writer that appended instead of
    # rewriting) or a begin with no end. A duplicated END after the region is
    # the one shape that is defined and NOT malformed — it lies outside the
    # region, so nothing below ever looks at it.
    if ($begins.Count -gt 1) { return $null }
    $b = [int] $begins[0]
    $after = @($ends | Where-Object { $_ -gt $b })
    if ($after.Count -eq 0) { return $null }
    $e = [int] $after[0]

    $fields = [ordered] @{}
    for ($i = $b + 1; $i -lt $e; $i++) {
        $line = [string] $Lines[$i]
        # A blank line inside the region is SKIPPED, not malformed (contract,
        # "The `NOW` Block"), the same as the Session Intent Baton's reader:
        # the region is bounded by its markers, not by its content.
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        # The key is everything before the FIRST colon; the value is the rest of
        # the line, trimmed, and no reader splits it further — which is what
        # keeps the em dash of `Task:` the writer's problem and never the
        # parser's.
        $m = [regex]::Match($line, '^(?<k>[A-Za-z][A-Za-z ]*):(?<v>.*)$')
        if (-not $m.Success) { return $null }
        $key = $m.Groups['k'].Value
        if ($NowKeys -cnotcontains $key) { return $null }
        if ($fields.Contains($key)) { return $null }
        $value = ConvertTo-NowValue $m.Groups['v'].Value
        if ($null -eq $value -or $value -eq '') { return $null }
        $fields[$key] = $value
    }
    foreach ($key in $NowKeys) { if (-not $fields.Contains($key)) { return $null } }

    # The state class is a CLOSED enum and the comparison is case-sensitive:
    # any other value makes the block malformed.
    $stateIndex = -1
    for ($i = 0; $i -lt $NowStates.Count; $i++) { if ($NowStates[$i] -ceq $fields['State']) { $stateIndex = $i } }
    if ($stateIndex -lt 0) { return $null }

    # Ruling: a `Since:`/`Due:` that is not ISO-8601 UTC is malformed. The
    # contract fixes the spelling of both and forbids an empty, `-` or
    # `unknown` Due precisely so that lateness always computes; a value that
    # cannot be a timestamp is the same class of defect as a State outside the
    # enum, and this reader is fail-closed everywhere else.
    if ($null -eq (ConvertTo-UtcInstant $fields['Since'])) { return $null }
    $due = ConvertTo-UtcInstant $fields['Due']
    if ($null -eq $due) { return $null }

    return [pscustomobject] @{
        # Re-rendered from the enum's own array, never echoed from the file.
        state = $NowStates[$stateIndex]
        # InvariantCulture, and not decoration: `:` in a CUSTOM format string
        # is the culture's TIME SEPARATOR, so under a culture that spells it
        # otherwise this would emit a value the reader re-parses as late/not
        # late, and `$IsoUtcPattern` would no longer match its own output.
        dueAt = $due.ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture)
        # COMPUTED here and nowhere else. Nothing in the file can set it: an
        # extra `Late:` line is an unknown key and makes the block malformed.
        late  = [bool] ($Now -gt $due)
        items = [pscustomobject] @{
            state     = $NowStates[$stateIndex]
            waitingOn = $fields['Waiting on']
            since     = $fields['Since']
            due       = $fields['Due']
            task      = $fields['Task']
            lookAt    = $fields['Look at']
        }
    }
}

# The slug is a FILENAME COMPONENT taken from a foreign worktree's
# `context.md`, which is the same untrusted file the banner above governs --
# so it is checked for SHAPE before it is used to build a path, not only for
# what it emits. `Get-SlotPin` lifts it with `(?<v>\S+)`, and `\S+` admits
# `../../..`; `Join-Path` would then resolve outside the slot and this reader
# would emit the last line of any `progress.md` the process can reach.
# The shape is the layer's own slug convention (contract, "Active Work Item
# (Design + Plan Pair)": lowercase snake case, ASCII only, no diacritics),
# with a length ceiling so the path stays bounded too.
function Test-SlotSlug([string] $Slug) {
    if ([string]::IsNullOrWhiteSpace($Slug)) { return $false }
    if ($Slug.Length -gt $SlugMaxLength) { return $false }
    return ($Slug -cmatch '^[a-z0-9]+(_[a-z0-9]+)*$')
}

function Get-SlotProgress([string] $SlotPath, [string] $Slug, [datetimeoffset] $Now) {
    # Paired to the slug the PIN names, never to "the first directory found
    # under sdd/": a slot can carry the leftover ledger of earlier work, and a
    # leftover slug can sort first.
    #
    # `notRead` names WHY a `lines = -1` slot was not read, so the caller's
    # `reasons` entry can say it in this script's established wording without
    # the caller re-deriving the cause. Empty on every path that did read.
    if (-not (Test-SlotSlug $Slug)) {
        return [pscustomobject] @{
            path = ''; exists = $false; lines = -1; lastLine = ''; now = $null
            notRead = 'pin slug outside the slug shape, fail-closed'
        }
    }
    $rel = ".superpowers/sdd/plan_$Slug/progress.md"
    $full = Join-Path $SlotPath ($rel -replace '/', [IO.Path]::DirectorySeparatorChar)
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
        return [pscustomobject] @{ path = $rel; exists = $false; lines = 0; lastLine = ''; now = $null; notRead = '' }
    }
    # Bound the READ before anything is read. `lines = -1` is this script's own
    # convention for an unreadable per-worktree signal (see `dirty` and
    # `unpushed`), so an over-size ledger reports as unread rather than as an
    # empty one.
    #
    # Both calls are in `try/catch` for the same reason `Get-SlotPin`'s read
    # is: under `$ErrorActionPreference = 'Stop'` a foreign slot that rotates,
    # deletes or momentarily holds its ledger -- the routine case this script's
    # own header describes -- would throw a TERMINATING error and take the
    # whole pool report down with exit 1 and no output, for every slot.
    # Measured: `Get-Item` on a path that passed `Test-Path` and then vanished
    # throws ItemNotFoundException, and `Get-Content` on a file held with
    # FileShare.None throws IOException. An unreadable ledger is a per-worktree
    # signal like any other here, so it degrades into `reasons`.
    $lines = @()
    try {
        if ((Get-Item -LiteralPath $full).Length -gt $LedgerMaxBytes) {
            return [pscustomobject] @{
                path = $rel; exists = $true; lines = -1; lastLine = ''; now = $null
                notRead = 'over the size ceiling'
            }
        }
        $lines = @(Get-Content -LiteralPath $full -Encoding utf8)
    } catch {
        return [pscustomobject] @{
            path = $rel; exists = $true; lines = -1; lastLine = ''; now = $null
            notRead = 'unreadable in this worktree'
        }
    }
    $last = @($lines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Last 1)
    return [pscustomobject] @{
        path     = $rel
        exists   = $true
        lines    = $lines.Count
        lastLine = if ($last.Count -gt 0) { ConvertTo-LedgerExcerpt ([string] $last[0]) } else { '' }
        now      = (Get-NowBlock $lines $Now)
        notRead  = ''
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

    # Every unreadable per-worktree signal in this script is named in `reasons`
    # (`status unreadable`, `unpushed count unreadable`, `pin unreadable
    # (fail-closed)`, `occupancy unknown (fail-closed)`), and a `-1` sentinel
    # without one would be invisible to a renderer — an over-size, an
    # unreadable and a slug-refused ledger would each read as an ordinary
    # slot. `notRead` supplies the cause; the wording of the three causes is
    # this function's, not the caller's. This reason can never be the FIRST one and
    # therefore cannot change any slot's freedom: the ledger is read only when
    # a pin exists, and a pin has already added `ACTIVE pin: <slug>` above.
    $progress = if ($null -ne $pin) { Get-SlotProgress $c.Path $pin.slug $clockUtc } else { $null }
    if ($null -ne $progress -and $progress.lines -eq -1) {
        $reasons += "progress ledger not read ($($progress.notRead))"
    }

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
        progress       = $progress
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
    generatedAt     = $clockUtc.ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture)
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
