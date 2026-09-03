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
# Every non-terminating error becomes terminating, so it is routed into the one
# silent catch at the bottom instead of printing a PowerShell error record to
# stderr and then carrying on with a half-assigned variable. That is what the
# "exits 0 silently" claim above actually requires, and at the default
# 'Continue' it was false: a locked file made Get-Content write to stderr, leave
# its target $null, and let the script run on and throw somewhere less obvious.
$ErrorActionPreference = 'Stop'
# ...but NOT for native commands. This script probes `git` by $LASTEXITCODE and
# decides what a non-zero exit means itself (no repository is a plain exit 0; a
# failed HEAD lookup is invalidation). Pinned explicitly rather than left to the
# host default so that contract holds on any PowerShell version.
$PSNativeCommandUseErrorActionPreference = $false

$MaxBytes = 8192
# Instruction becomes an automatically executed first move (see the payload at
# the bottom), so its value is bounded twice: it must NAME a skill that exists
# in this deployment, and it must be short. 200 characters is roughly three
# times the canonical instruction and leaves no room for a payload.
$MaxInstruction = 200
$Required = @('Kind', 'Plan', 'Branch', 'Slug', 'Instruction')
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

    # Size ceiling, part one: bound the READ. `Get-Content -Raw` loads the whole
    # file, so checking only afterwards meant a multi-megabyte scratch file was
    # pulled into memory in full just to be thrown away — the ceiling read as a
    # bound while being none, and session start paid for it.
    if ((Get-Item -LiteralPath $batonPath).Length -gt $MaxBytes) {
        Move-Aside $batonPath 'session-intent.stale.md'
        exit 0
    }

    $raw = Get-Content -LiteralPath $batonPath -Raw -Encoding utf8
    if ($null -eq $raw -or [string]::IsNullOrWhiteSpace($raw)) { exit 0 }

    # Part two, kept as-is: on-disk length counts a BOM and any CRLF the decode
    # collapses, so it is the wrong number to judge CONTENT by. This is the
    # correct check; the one above is only there to make it cheap.
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
    # `Select-Object -Skip 1`, never $lines[1..($lines.Count - 1)]: for a
    # single-line file that slice is $lines[1..0], and 1..0 is a DESCENDING
    # range in PowerShell, so it reads index 1 — out of bounds, which under
    # Set-StrictMode throws. An identity-line-only file with no trailing newline
    # therefore fell into the silent catch and was neither emitted NOR
    # invalidated: it stayed as session-intent.md and was re-evaluated
    # identically on every single session start.
    foreach ($line in $lines | Select-Object -Skip 1) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $m = [regex]::Match($line, '^(?<k>[A-Za-z][A-Za-z ]*):[ ]?(?<v>.*)$')
        if (-not $m.Success) { $bad = $true; break }
        $key = $m.Groups['k'].Value
        if ($RenderOrder -notcontains $key) { $bad = $true; break }
        if ($fields.Contains($key)) { $bad = $true; break }
        $value = $m.Groups['v'].Value.Trim()
        # Values are re-rendered VERBATIM (only key NAMES are drawn from the
        # canonical $RenderOrder), so a value is the one place attacker-chosen
        # text reaches the emitted block — and this is a structural-character
        # check rather than a search for one tag, deliberately.
        #
        # The wrapper is a TEXTUAL convention a model reads, not XML a parser
        # validates, so a merely visually-identical closing tag followed by
        # instruction text restores the whole hole. A literal
        # '(?i)</?session-intent' check therefore did not close it: it demands
        # the exact ASCII '<' and the exact spelling, and both
        # '</session‑intent>' written with U+2011 NON-BREAKING HYPHEN and
        # '< /session-intent>' were measured sailing through and being emitted
        # inside the wrapper. Enumerating spellings of one tag is a losing game;
        # rejecting the class is cheap and final, and '[<>]' strictly subsumes
        # the check it replaces.
        #
        # \p{Cc} is the same argument for control characters: a bare CR inside a
        # value survives the "`r?`n" split and .Trim() and then renders as extra
        # apparent key lines inside the block.
        #
        # No legitimate pointer value — a plan or ledger path, a branch, a slug,
        # a ticket key, a task number, a skill name — has any reason to carry an
        # angle bracket or a control character, so the whole class can go.
        # Staleness is the disposition already used for an unknown key or a
        # malformed line; a structurally hostile value gets the same one.
        if ($value -match '[<>]' -or $value -match '\p{Cc}') { $bad = $true; break }
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

    # Instruction validation. The legal words are the skill directory names of
    # THIS deployment, taken from the skills directory beside this hook's own
    # directory ($PSScriptRoot is <deployment>/hooks, skills are its sibling).
    # An empty or unreadable list matches nothing and the baton goes stale —
    # deliberately fail-closed: the documented fallback for a lost baton is the
    # operator typing the intent, so the cost of being wrong this way is zero,
    # while the cost the other way is up to $MaxBytes of arbitrary text handed
    # over as the session's first user message.
    $instruction = $fields['Instruction']
    if ($instruction.Length -gt $MaxInstruction) {
        Move-Aside $batonPath 'session-intent.stale.md'
        exit 0
    }
    $skillNames = @()
    try {
        $skillsDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'skills'
        if (Test-Path -LiteralPath $skillsDir -PathType Container) {
            $skillNames = @(Get-ChildItem -LiteralPath $skillsDir -Directory -ErrorAction Stop |
                ForEach-Object { $_.Name })
        }
    }
    catch { $skillNames = @() }
    # -cmatch, never -match: skill names are lower-case path names and the
    # comparison must not accept a differently-cased near-miss, the same reason
    # the branch and slug guards below are case-sensitive.
    $namesASkill = $false
    foreach ($n in $skillNames) {
        if ($instruction -cmatch [regex]::Escape($n)) { $namesASkill = $true; break }
    }
    if (-not $namesASkill) {
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
        # Belt and braces for the no-opinion promise above. A read that fails
        # leaves the assignment unmade, and an empty file reads as $null too, so
        # $ctxText can be $null here on paths where the catch never fires —
        # which is exactly what happened at the default 'Continue', where
        # Get-Content on a locked file raised a NON-terminating error the catch
        # could not see. [regex]::Match($null, ...) then threw into the outer
        # silent catch, so a perfectly valid handoff was lost AND the baton was
        # left as session-intent.md — the one disposition a rejected baton may
        # never have. Normalised here so no opinion does not rest on
        # $ErrorActionPreference alone.
        if ($null -eq $ctxText) { $ctxText = '' }
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
        if ($span.Ticks -lt 0) {
            # A stamp in the future is not an age. The trigger is mundane — a
            # writer stamping LOCAL time and appending 'Z', or plain clock skew
            # — and unclamped it was doubly wrong: measured with
            # '3000-01-01T00:00:00Z' it rendered age="-8532039h -24m", and
            # because a negative TotalHours is never greater than 12 it also
            # DROPPED the confirmation trailer. The only staleness signal the
            # model gets became nonsense precisely when the stamp is untrusted.
            # Unknown-and-aged is the fail-safe reading, and it is already the
            # outcome for a stamp that will not parse at all.
            $ageText = 'unknown'
            $aged = $true
        }
        else {
            $ageText = '{0}h {1}m' -f [int] $span.TotalHours, $span.Minutes
            $aged = $span.TotalHours -gt 12
        }
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

    # Fixed English text, never derived from the baton: this string becomes the
    # session's first USER message, so nothing attacker-chosen may reach it.
    # Ordering is load-bearing — the bootstrap checks are a PRECONDITION of
    # acting on a baton, never the other way round (contract, "Session Intent
    # Baton", Precedence).
    #
    # Field verified against the Claude Code hooks reference:
    # https://code.claude.com/docs/en/hooks#sessionstart-decision-control
    # "`initialUserMessage` | String used as the first user message of the session."
    $firstMove = @(
        'A session intent baton from the previous session in this workspace has been delivered above.',
        'Run the bootstrap checks of the session-start context FIRST — the publication-guarantee self-check is a precondition, and a baton never overrides a fail-closed gate.',
        'Only then act on the baton''s Instruction line.'
    ) -join ' '

    $payload = [pscustomobject] @{
        hookSpecificOutput = [pscustomobject] @{
            hookEventName      = 'SessionStart'
            additionalContext  = $body
            initialUserMessage = $firstMove
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
