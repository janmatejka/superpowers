<#
.SYNOPSIS
    The epic manager's OUTBOX: a git-ignored list of messages between the
    manager and ticket sessions that still await a reply.

.DESCRIPTION
    Every message between an epic's manager and a ticket session requires a
    reply, except the named `Oznámení:` class (contract/message-protocol.md,
    "Replies are required"). This file is the manager's ARTIFACT of that
    obligation: it makes an unanswered or late message visible to
    `mb-epic-run status` without anybody reading a transcript. It records;
    it decides nothing and detects nothing by itself — the reply rule has no
    mechanical trigger, the outbox only makes it visible.

    File: <RepoRoot>/.superpowers/epic/<KEY>/outbox.md (git-ignored scratch).
    Format — CLOSED, one line each under a fixed title line:

        # Outbox — epic <KEY>

        - <sentUtc> | to: <TICKET|manager> | due: <ISO-8601 UTC> | state: open|resent|closed | <subject>

    `to:` names WHO OWES THE REPLY: a ticket key for a message the manager
    sent to that ticket session, or `manager` for a message the manager
    received and still owes an answer to. `state`: open -> resent (the ONE
    repeat after Due, with a new Due; only for an entry addressed to a ticket -
    an answer the manager owes is answered, not repeated) -> closed (answered,
    or handed to the human); closed is final. Times are ISO-8601 UTC. Lateness is COMPUTED by
    the reader against its own clock and is never written into the file.

    Reader safety follows contract/now-block.md, "The `NOW` Block" (the
    baton's safety rules, applied unchanged): the format is closed, the reader
    parses and RE-RENDERS every value (never echoes a line as it lies), bounds
    the size of what it reads and of what it renders, and rejects a value by
    CHARACTER CLASS — an angle bracket, a control character (\p{Cc}) or a
    format character (\p{Cf}). A rejected or foreign line is dropped and
    COUNTED (-Rejected), never rendered. A damaged title, an absent, empty or
    over-size file, or a key outside the epic-key shape yields an EMPTY result
    without an exception: the outbox is a view, and a view that throws would
    take `status` down with it.

    Dot-source this file, then call the functions. Layer scripts are
    developer tooling and speak English (contract "Language Contract"); the
    Czech rendering is the calling skill's job.
#>
#Requires -Version 7
Set-StrictMode -Version Latest

# Bound on what is READ. An outbox line is ~150 bytes; a file this large is not
# an outbox that anyone kept honestly.
$UmsOutboxMaxBytes = 262144
# Bound on what is RENDERED out of a subject.
$UmsOutboxSubjectMax = 200
$UmsOutboxStates = @('open', 'resent', 'closed')
$UmsOutboxIsoPattern = '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z$'
$UmsOutboxKeyPattern = '^[A-Z][A-Z0-9]*-\d+$'

function Get-UmsOutboxPath([string] $RepoRoot, [string] $EpicKey) {
    return (Join-Path (Join-Path (Join-Path (Join-Path $RepoRoot '.superpowers') 'epic') $EpicKey) 'outbox.md')
}

# The key becomes a PATH COMPONENT, so its shape is checked before any path is
# built: `..` and separators cannot match, and neither can a lower-case name.
function Test-UmsOutboxKey([string] $Key) {
    if ([string]::IsNullOrEmpty($Key) -or $Key.Length -gt 40) { return $false }
    return ($Key -cmatch $UmsOutboxKeyPattern)
}

function Test-UmsOutboxTo([string] $To) {
    if ($To -ceq 'manager') { return $true }
    return (Test-UmsOutboxKey $To)
}

# One place where "what may leave this file" is decided. Cc AND Cf: U+202E
# RIGHT-TO-LEFT OVERRIDE and U+200B carry no glyph, survive Trim() and the
# length bound, and reorder a rendered table (contract/now-block.md).
function Test-UmsOutboxText([string] $Text) {
    if ($null -eq $Text) { return $false }
    if ($Text -match '[<>]') { return $false }
    if ($Text -match '\p{Cc}') { return $false }
    if ($Text -match '\p{Cf}') { return $false }
    return $true
}

# A cut may not split a surrogate pair.
function Limit-UmsOutboxText([string] $Text) {
    if ($Text.Length -le $UmsOutboxSubjectMax) { return $Text }
    $cut = $UmsOutboxSubjectMax
    if ([char]::IsHighSurrogate($Text[$cut - 1])) { $cut -= 1 }
    return $Text.Substring(0, $cut)
}

# [datetime] in, UTC [datetime] out. An Unspecified kind is READ AS UTC: the
# functions promise UTC, and ToUniversalTime() on an Unspecified value would
# silently apply the machine's zone.
function ConvertTo-UmsOutboxUtc([datetime] $Value) {
    if ($Value.Kind -eq [DateTimeKind]::Unspecified) { return [datetime]::SpecifyKind($Value, [DateTimeKind]::Utc) }
    return $Value.ToUniversalTime()
}

function Format-UmsOutboxInstant([datetime] $Utc) {
    return $Utc.ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture)
}

# The regex runs FIRST: TryParse alone accepts far more than this closed format.
function ConvertFrom-UmsOutboxInstant([string] $Text) {
    if ($Text -notmatch $UmsOutboxIsoPattern) { return $null }
    $parsed = [datetime]::MinValue
    if (-not [datetime]::TryParse($Text, [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal,
            [ref] $parsed)) {
        return $null
    }
    return $parsed
}

function Get-UmsOutboxTitle([string] $EpicKey) {
    return "# Outbox $([char]0x2014) epic $EpicKey"
}

function Format-UmsOutboxLine([string] $Sent, [string] $To, [string] $Due, [string] $State, [string] $Subject) {
    return "- $Sent | to: $To | due: $Due | state: $State | $Subject"
}

# Returns @{ Lines = <string[] after the title>; Ok = $bool }. Ok is false for
# every unreadable shape (absent, over-size, unreadable, empty, damaged or
# foreign title) — the callers turn that into an empty view or, for a writer,
# a refusal to append under a title that is not its own.
function Read-UmsOutboxFile([string] $Path, [string] $EpicKey) {
    $none = @{ Lines = @(); Ok = $false }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $none }
    $text = ''
    try {
        if ((Get-Item -LiteralPath $Path).Length -gt $UmsOutboxMaxBytes) { return $none }
        $text = [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8)
    } catch { return $none }
    if ([string]::IsNullOrEmpty($text)) { return $none }
    $lines = @($text -split '\r?\n')
    if ($lines[0] -cne (Get-UmsOutboxTitle $EpicKey)) { return $none }
    return @{ Lines = @($lines | Select-Object -Skip 1); Ok = $true }
}

# Parses ONE body line into a re-rendered record. $null means REJECT: a
# blank line is the caller's to skip and never reaches this function.
function ConvertFrom-UmsOutboxLine([string] $Line) {
    if (-not (Test-UmsOutboxText $Line)) { return $null }
    $m = [regex]::Match($Line, '^- (?<sent>\S+) \| to: (?<to>\S+) \| due: (?<due>\S+) \| state: (?<state>\S+) \| (?<subj>\S.*)$')
    if (-not $m.Success) { return $null }
    $sent = ConvertFrom-UmsOutboxInstant $m.Groups['sent'].Value
    $due = ConvertFrom-UmsOutboxInstant $m.Groups['due'].Value
    if ($null -eq $sent -or $null -eq $due) { return $null }
    $to = $m.Groups['to'].Value
    if (-not (Test-UmsOutboxTo $to)) { return $null }
    # The state is a CLOSED enum compared case-sensitively and re-rendered from
    # the enum's own array, never echoed from the file.
    $state = $null
    foreach ($s in $UmsOutboxStates) { if ($s -ceq $m.Groups['state'].Value) { $state = $s } }
    if ($null -eq $state) { return $null }
    $subject = Limit-UmsOutboxText ($m.Groups['subj'].Value.Trim())
    return @{ Sent = (Format-UmsOutboxInstant $sent); To = $to; Due = (Format-UmsOutboxInstant $due); State = $state; Subject = $subject; DueUtc = $due }
}

function Add-UmsOutboxEntry {
    param(
        [Parameter(Mandatory = $true)] [string] $RepoRoot,
        [Parameter(Mandatory = $true)] [string] $EpicKey,
        [Parameter(Mandatory = $true)] [string] $To,
        [Parameter(Mandatory = $true)] [datetime] $SentUtc,
        [Parameter(Mandatory = $true)] [datetime] $DueUtc,
        [Parameter(Mandatory = $true)] [string] $Subject
    )
    # A writer refuses what the reader would reject, so the outbox never holds
    # a line its own reader drops.
    if (-not (Test-UmsOutboxKey $EpicKey)) { throw "Outbox: epic key outside the key shape: $EpicKey" }
    if (-not (Test-UmsOutboxTo $To)) { throw "Outbox: recipient must be a ticket key or 'manager': $To" }
    $subj = ([string] $Subject).Trim()
    if ($subj -eq '' -or -not (Test-UmsOutboxText $subj)) { throw 'Outbox: subject is empty or carries an angle bracket, control or format character' }
    if ($subj.Length -gt $UmsOutboxSubjectMax) { throw "Outbox: subject is over $UmsOutboxSubjectMax characters" }
    $sent = ConvertTo-UmsOutboxUtc $SentUtc
    $due = ConvertTo-UmsOutboxUtc $DueUtc
    if ($due -le $sent) { throw 'Outbox: due must be after the sent time' }

    $path = Get-UmsOutboxPath $RepoRoot $EpicKey
    $line = Format-UmsOutboxLine (Format-UmsOutboxInstant $sent) $To (Format-UmsOutboxInstant $due) 'open' $subj
    $utf8 = [Text.UTF8Encoding]::new($false)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path) | Out-Null
        [IO.File]::WriteAllText($path, ((Get-UmsOutboxTitle $EpicKey) + "`n" + $line + "`n"), $utf8)
        return
    }
    # Never append under a title that is not ours.
    $file = Read-UmsOutboxFile $path $EpicKey
    if (-not $file.Ok) { throw "Outbox: $path is not a readable outbox of $EpicKey (title damaged, empty or over the size ceiling); not appending" }
    # The same message entered twice would make `Set-UmsOutboxState` ambiguous
    # and show one owed reply as two. Sent time and recipient identify a message.
    $sentText = Format-UmsOutboxInstant $sent
    foreach ($l in $file.Lines) {
        $known = ConvertFrom-UmsOutboxLine $l
        if ($null -ne $known -and $known.Sent -ceq $sentText -and $known.To -ceq $To) {
            throw "Outbox: an entry sent at $sentText to $To is already recorded"
        }
    }
    $existing = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)
    $lead = if ($existing.EndsWith("`n")) { '' } else { "`n" }
    [IO.File]::AppendAllText($path, ($lead + $line + "`n"), $utf8)
}

function Set-UmsOutboxState {
    param(
        [Parameter(Mandatory = $true)] [string] $RepoRoot,
        [Parameter(Mandatory = $true)] [string] $EpicKey,
        [Parameter(Mandatory = $true)] [datetime] $SentUtc,
        [Parameter(Mandatory = $true)] [ValidateSet('resent', 'closed')] [string] $State,
        # Disambiguates two entries sent in the same second to different parties.
        [string] $To = '',
        # The repeat needs a new Due, or it would stay late forever. Ignored for closed.
        [Nullable[datetime]] $NewDueUtc = $null
    )
    if (-not (Test-UmsOutboxKey $EpicKey)) { throw "Outbox: epic key outside the key shape: $EpicKey" }
    $path = Get-UmsOutboxPath $RepoRoot $EpicKey
    $file = Read-UmsOutboxFile $path $EpicKey
    if (-not $file.Ok) { throw "Outbox: $path is not a readable outbox of $EpicKey" }

    $sentText = Format-UmsOutboxInstant (ConvertTo-UmsOutboxUtc $SentUtc)
    $lines = @($file.Lines)
    $hits = @()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $rec = ConvertFrom-UmsOutboxLine $lines[$i]
        if ($null -eq $rec) { continue }
        if ($rec.Sent -cne $sentText) { continue }
        if ($To -ne '' -and $rec.To -cne $To) { continue }
        $hits += $i
    }
    if ($hits.Count -eq 0) { throw "Outbox: no entry sent at $sentText" }
    if ($hits.Count -gt 1) { throw "Outbox: $($hits.Count) entries sent at $sentText; pass -To to pick one" }

    $idx = [int] $hits[0]
    $rec = ConvertFrom-UmsOutboxLine $lines[$idx]
    if ($rec.State -ceq 'closed') { throw "Outbox: entry sent at $sentText is closed and closed is final" }
    if ($State -ceq 'resent') {
        # ONE repeat after Due, then the human (contract/message-protocol.md,
        # "Replies are required"). Only a message the manager SENT can be sent
        # again; an entry addressed to `manager` is an answer the manager owes,
        # and that is answered, not repeated.
        if ($rec.To -ceq 'manager') { throw "Outbox: entry sent at $sentText is addressed to manager; the manager owes that answer and there is nothing to repeat" }
        if ($rec.State -ceq 'resent') { throw "Outbox: entry sent at $sentText was already resent once; the next step is the human" }
        if ($null -ne $NewDueUtc) {
            $newDue = ConvertTo-UmsOutboxUtc ([datetime] $NewDueUtc)
            if ($newDue -le (ConvertFrom-UmsOutboxInstant $rec.Sent)) { throw 'Outbox: new due must be after the sent time' }
            $rec.Due = Format-UmsOutboxInstant $newDue
        }
    }
    $lines[$idx] = Format-UmsOutboxLine $rec.Sent $rec.To $rec.Due $State $rec.Subject
    $body = ((Get-UmsOutboxTitle $EpicKey) + "`n" + (($lines | Where-Object { $_ -ne '' }) -join "`n") + "`n")
    [IO.File]::WriteAllText($path, $body, [Text.UTF8Encoding]::new($false))
}

function Get-UmsOutbox {
    param(
        [Parameter(Mandatory = $true)] [string] $RepoRoot,
        [Parameter(Mandatory = $true)] [string] $EpicKey,
        [Parameter(Mandatory = $true)] [datetime] $NowUtc,
        # Receives the number of dropped lines (rejected by class or foreign to the closed format).
        # Pass ([ref] $n). The default is a throwaway reference: a [ref]
        # parameter cannot default to $null, and an [object] one would receive
        # the DEREFERENCED value instead of the reference.
        [ref] $Rejected = ([ref] $null)
    )
    if ($null -ne $Rejected) { $Rejected.Value = 0 }
    if (-not (Test-UmsOutboxKey $EpicKey)) { return }
    $file = Read-UmsOutboxFile (Get-UmsOutboxPath $RepoRoot $EpicKey) $EpicKey
    if (-not $file.Ok) { return }
    $now = ConvertTo-UmsOutboxUtc $NowUtc
    # NOT named $rejected: PowerShell variables are case-insensitive, so that
    # would overwrite the [ref] parameter above.
    $dropped = 0
    foreach ($line in $file.Lines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $rec = ConvertFrom-UmsOutboxLine $line
        if ($null -eq $rec) { $dropped++; continue }
        [pscustomobject] @{
            To      = $rec.To
            Sent    = $rec.Sent
            Due     = $rec.Due
            State   = $rec.State
            Subject = $rec.Subject
            # COMPUTED here and nowhere else; nothing in the file can set it.
            Late    = [bool](($rec.State -cne 'closed') -and ($now -gt $rec.DueUtc))
        }
    }
    if ($null -ne $Rejected) { $Rejected.Value = $dropped }
}
