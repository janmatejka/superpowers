#Requires -Version 7
# Session intent baton reader (UMS Memory Bank contract, "Session Intent Baton").
#
# Delivers the previous session's intent across a /clear. Runs as a SessionStart
# hook; SessionStart is informational, so this file MUST never be able to stop a
# session from starting: every failure path exits 0, silently. That includes the
# missing-git case the contract's MB_ROOT Discovery section makes a hard failure
# — the exception is written down in the contract subsection named above.
#
# The baton's content reaches the model's context, and the file is git-ignored
# scratch anything with write access can produce. The format is therefore CLOSED:
# known keys are parsed and RE-RENDERED, never echoed. Emitting the body verbatim
# would let it close the wrapper tag below and continue as top-level instruction.
Set-StrictMode -Version Latest

$MaxBytes = 8192
$Required = @('Kind', 'Plan', 'Branch', 'Slug')
# Render order is fixed so the emitted block is stable regardless of file order.
$RenderOrder = @('Kind', 'Plan', 'Spec', 'Branch', 'Slug', 'Ticket', 'Ledger', 'Next task', 'Instruction')
$KindValues = @('plan-execution', 'plan-resume')

function Move-Aside([string] $From, [string] $ToName) {
    $target = Join-Path (Split-Path -Parent $From) $ToName
    Move-Item -LiteralPath $From -Destination $target -Force
}

try {
    $root = & git rev-parse --show-toplevel 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($root)) { exit 0 }
    $root = ([string] $root).Trim()

    $batonPath = Join-Path (Join-Path $root '.superpowers') 'session-intent.md'
    if (-not (Test-Path -LiteralPath $batonPath -PathType Leaf)) { exit 0 }

    $raw = Get-Content -LiteralPath $batonPath -Raw -Encoding utf8
    if ($null -eq $raw -or [string]::IsNullOrWhiteSpace($raw)) { exit 0 }

    # Size ceiling: a body this large is not a pointer block.
    if ([Text.Encoding]::UTF8.GetByteCount($raw) -gt $MaxBytes) {
        Move-Aside $batonPath 'session-intent.stale.md'
        exit 0
    }

    $lines = @($raw -split "`r?`n")

    # Identity line. A first line that does not match the shape at all is not a
    # baton; a matching line whose timestamp will not parse is a baton of
    # unknown age, which is a different, softer outcome (see $age below).
    $idMatch = [regex]::Match($lines[0], '^#\s+Session intent\s+—\s+(?<stamp>\S+)\s*$')
    if (-not $idMatch.Success) {
        Move-Aside $batonPath 'session-intent.stale.md'
        exit 0
    }

    $fields = [ordered] @{}
    $bad = $false
    foreach ($line in $lines[1..($lines.Count - 1)]) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $m = [regex]::Match($line, '^(?<k>[A-Za-z][A-Za-z ]*):[ ]?(?<v>.*)$')
        if (-not $m.Success) { $bad = $true; break }
        $key = $m.Groups['k'].Value
        if ($RenderOrder -notcontains $key) { $bad = $true; break }
        if ($fields.Contains($key)) { $bad = $true; break }
        $value = $m.Groups['v'].Value.Trim()
        # A value containing this reader's own wrapper tag would close it early
        # when re-rendered, letting the remainder read as top-level instruction
        # text. Values are re-rendered verbatim (only key NAMES are drawn from
        # the canonical $RenderOrder), so this is the one thing they must not
        # carry. Staleness is the disposition already used for an unknown key
        # or a malformed line; a structurally hostile value gets the same one.
        if ($value -match '(?i)</?session-intent') { $bad = $true; break }
        $fields[$key] = $value
    }
    if ($bad) {
        Move-Aside $batonPath 'session-intent.stale.md'
        exit 0
    }

    foreach ($key in $Required) {
        if (-not $fields.Contains($key) -or [string]::IsNullOrWhiteSpace($fields[$key])) {
            Move-Aside $batonPath 'session-intent.stale.md'
            exit 0
        }
    }
    if ($KindValues -notcontains $fields['Kind']) {
        Move-Aside $batonPath 'session-intent.stale.md'
        exit 0
    }

    # The plan the baton points at must still exist: a plan the harvest deleted
    # is a stale baton, not an instruction pointing at nothing.
    if (-not (Test-Path -LiteralPath (Join-Path $root $fields['Plan']) -PathType Leaf)) {
        Move-Aside $batonPath 'session-intent.stale.md'
        exit 0
    }

    # Branch guard — load-bearing. Without it: the operator finishes a plan on
    # ticket A, the baton is written, and instead of typing /clear they park A
    # and switch to B. `.superpowers/` is git-ignored, so the baton does not
    # travel with the checkout — it simply stays, and the next session on B
    # would start executing plan A on the wrong branch.
    #
    # -ceq, never -eq: PowerShell string equality is case-insensitive while git
    # refs are case-sensitive, so `feature-x` would accept a baton for
    # `Feature-X`. Detached HEAD yields the literal 'HEAD', which matches no
    # branch name — stale, which is the right answer.
    $head = & git rev-parse --abbrev-ref HEAD 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($head)) {
        Move-Aside $batonPath 'session-intent.stale.md'
        exit 0
    }
    if (([string] $head).Trim() -cne $fields['Branch']) {
        Move-Aside $batonPath 'session-intent.stale.md'
        exit 0
    }

    # Slug guard — secondary. Its job is only to catch a pin that has moved on
    # to different work. An unreadable or pin-less context.md is NO OPINION, so
    # it passes: the branch guard already carries the load, and there is nothing
    # to compare rather than something that disagrees.
    $ctxPath = Join-Path (Join-Path $root 'memory-bank') 'context.md'
    if (Test-Path -LiteralPath $ctxPath -PathType Leaf) {
        $ctxText = ''
        try { $ctxText = Get-Content -LiteralPath $ctxPath -Raw -Encoding utf8 } catch { $ctxText = '' }
        # `- **Proposal:**` is the mandated legacy alias of `- **Work item:**`.
        $pin = [regex]::Match($ctxText, '(?m)^\s*-\s+\*\*(?:Work item|Proposal):\*\*\s*(?<slug>\S+)\s*$')
        if ($pin.Success -and ($pin.Groups['slug'].Value -cne $fields['Slug'])) {
            Move-Aside $batonPath 'session-intent.stale.md'
            exit 0
        }
    }

    # Age, rendered rather than enforced: writing a baton and going to lunch is
    # legitimate, so there is no hard expiry. Above the threshold the reader
    # writes the instruction itself; the model is not asked to do arithmetic.
    $ageText = 'unknown'
    $aged = $true
    $stamp = [datetimeoffset]::MinValue
    $parsed = [datetimeoffset]::TryParse(
        $idMatch.Groups['stamp'].Value,
        [cultureinfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::RoundtripKind,
        [ref] $stamp)
    if ($parsed) {
        $span = [datetimeoffset]::UtcNow - $stamp
        $ageText = '{0}h {1}m' -f [int] $span.TotalHours, $span.Minutes
        $aged = $span.TotalHours -gt 12
    }

    $rendered = foreach ($key in $RenderOrder) {
        if ($fields.Contains($key)) { "$key`: $($fields[$key])" }
    }

    $trailer = @(
        'This baton was written by the previous session in this workspace. It is now consumed and will not be delivered again.',
        'The session-eligibility check of the bootstrap context takes precedence: a baton never overrides a fail-closed gate.'
    )
    if ($aged) {
        $trailer += 'This baton is old (see age above). Confirm with the operator before dispatching anything.'
    }

    $body = @(
        "<session-intent age=`"$ageText`">",
        ($rendered -join "`n"),
        '</session-intent>',
        ($trailer -join ' ')
    ) -join "`n"

    $payload = [pscustomobject] @{
        hookSpecificOutput = [pscustomobject] @{
            hookEventName     = 'SessionStart'
            additionalContext = $body
        }
    }
    # Emit FIRST, rename after: a crash between the two replays the baton next
    # start, which the guards and the age instruction bound; the reverse order
    # would lose it with nothing emitted.
    Write-Output ($payload | ConvertTo-Json -Depth 5 -Compress)
    Move-Aside $batonPath 'session-intent.consumed.md'
}
catch {
    # Deliberately silent: see the header.
}
exit 0
