<#
.SYNOPSIS
    Re-vendors the Superpowers skill pack from the upstream mirror repo into
    .claude/skills/ and re-applies the UMS overlay blocks.

.DESCRIPTION
    The tag and the skill set come from the PIN FILE (shared/VENDORED_FROM.md),
    not from this script. Workflow (see UMS_MEMORY_BANK_CONTRACT.md, Versioning
    & Vendoring):
      0. pwsh revendor-superpowers.ps1 -PinOnly -Tag v6.4.2      -> rewrites the pin
         (Tag, Commit, Skills, Excluded) from `git ls-tree` of the tag. A new upstream
         skill without a decision stops the run: pass -Include <name> or -Exclude <name>.
      1. pwsh revendor-superpowers.ps1 -NoOverlays               -> commit "vanilla sync"
      2. pwsh revendor-superpowers.ps1 -OverlaysOnly             -> commit "UMS overlay"
    Or run without -NoOverlays/-OverlaysOnly to do vendor + overlays in one pass.

    -SkillsRoot     target skills directory (default <UmsRoot>\.claude\skills). Overlay
                    fragments are read from <SkillsRoot>\shared\overlays; the vendor phase
                    writes the target pin to <SkillsRoot>\shared\VENDORED_FROM.md.
    -PinSource      the pin that is READ (default <SkillsRoot>\shared\VENDORED_FROM.md);
                    -PinOnly writes to it. A sync vendors into a target SkillsRoot with
                    -PinSource pointing at the pin it just produced.
    -Tag            optional; without it the tag is taken from the pin.
    -Include/-Exclude  decide upstream skills the pin does not know yet (with -PinOnly).
    -DotSourceOnly  define the functions and return (used by the test suite).

    Overlay fragments live in <SkillsRoot>\shared\overlays\*.overlay.md.
    Fragment format (first lines are directives, rest is the block to insert):
      <!-- TARGET: <skill>/<file> -->
      <!-- ANCHOR: EOF -->                          (append at end of file)
      or
      <!-- ANCHOR-BEFORE: <exact line text> -->     (insert before that line)
    An anchor that no longer matches upstream text is a HARD ERROR - that is the
    upstream-drift detector: it enumerates exactly the blocks needing attention.
    Several fragments may share one TARGET (a header pointer block plus the body
    block): they apply in ordinal file-name order, the pristine check runs once
    per target, and verification requires the first block of every overlayed
    SKILL.md within the first 12000 characters.

.NOTES
    Verification always runs last and fails the script on any problem:
    dangling relative links, stale v5 files, missing v6 files (of the pinned
    skills), unbalanced overlay markers, CRLF in bash scripts, and a functional
    Git Bash test of the SDD scripts.
#>
#Requires -Version 7
[CmdletBinding()]
param(
    [string]$SpRepo = 'C:\Users\matejka\source\repos\superpowers',
    [string]$Tag,
    [string]$UmsRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path,
    [string]$SkillsRoot = (Join-Path $UmsRoot '.claude\skills'),
    [string]$PinSource = (Join-Path $SkillsRoot 'shared\VENDORED_FROM.md'),
    [switch]$PinOnly,
    [string[]]$Include = @(),
    [string[]]$Exclude = @(),
    [switch]$NoOverlays,
    [switch]$OverlaysOnly,
    [switch]$VerifyOnly,
    [switch]$DotSourceOnly
)

$ErrorActionPreference = 'Stop'

$SharedDir   = Join-Path $SkillsRoot 'shared'
$OverlaysDir = Join-Path $SharedDir 'overlays'
# The TARGET pin: written by the vendor phase, read by overlays/verify. It is
# the same file as -PinSource unless a sync points -PinSource elsewhere.
$PinFile     = Join-Path $SharedDir 'VENDORED_FROM.md'

function Step([string]$msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Fail([string]$msg) { Write-Host "FAIL: $msg" -ForegroundColor Red; exit 1 }

# -------------------------------------------------------------------- pin ----
function Sort-UmsOrdinal([string[]] $Names) {
    $arr = [string[]]@($Names | Where-Object { $_ })
    [Array]::Sort($arr, [StringComparer]::Ordinal)
    return $arr
}

# Reads the pin file. Returns $null when the file is missing; missing Skills /
# Excluded sections are empty arrays.
function Read-UmsVendorPin([string] $PinFile) {
    if (-not (Test-Path -LiteralPath $PinFile)) { return $null }
    $tag = ''; $commit = ''
    $skills = [System.Collections.Generic.List[string]]::new()
    $excluded = [System.Collections.Generic.List[string]]::new()
    $section = ''
    foreach ($line in ((Get-Content -LiteralPath $PinFile -Raw) -split '\r?\n')) {
        if ($line -match '^- Tag:\s*(\S+)\s*$')    { $tag = $Matches[1]; $section = ''; continue }
        if ($line -match '^- Commit:\s*(\S+)\s*$') { $commit = $Matches[1]; $section = ''; continue }
        if ($line -match '^- Skills:\s*$')         { $section = 'skills'; continue }
        if ($line -match '^- Excluded:\s*$')       { $section = 'excluded'; continue }
        if ($line -match '^\s+([A-Za-z0-9][A-Za-z0-9._-]*)\s*$') {
            if ($section -eq 'skills')   { $skills.Add($Matches[1]) }
            if ($section -eq 'excluded') { $excluded.Add($Matches[1]) }
            continue
        }
        $section = ''
    }
    return [pscustomobject]@{
        Tag      = $tag
        Commit   = $commit
        Skills   = [string[]]$skills.ToArray()
        Excluded = [string[]]$excluded.ToArray()
    }
}

function Write-UmsVendorPin([string] $PinFile, [string] $Tag, [string] $Commit,
                            [string[]] $Skills, [string[]] $Excluded, [string] $RepoStateDate) {
    $skillLines    = (@($Skills)   | ForEach-Object { "  $_" }) -join "`n"
    $excludedLines = (@($Excluded) | ForEach-Object { "  $_" }) -join "`n"
    $lines = @(
        '# Vendored Superpowers skills',
        '',
        '- Upstream: https://github.com/obra/superpowers.git (mirror: C:\Users\matejka\source\repos\superpowers)',
        "- Tag: $Tag",
        "- Commit: $Commit",
        "- Vendored on top of repo state: $RepoStateDate (by .claude/scripts/revendor-superpowers.ps1)",
        '- Skills:'
    )
    if ($skillLines) { $lines += $skillLines }
    $lines += '- Excluded:'
    if ($excludedLines) { $lines += $excludedLines }
    $lines += @(
        '- Overlays: applied from `shared/overlays/*.overlay.md`; applied blocks are marked',
        '  `<!-- UMS-OVERLAY BEGIN/END -->` inside the vendored files.',
        '',
        '## Re-vendor procedure',
        '',
        'The tag and the skill set are read from THIS file; the script has no built-in list.',
        '',
        '1. Bump the pin in the fork (run from the fork root):',
        '   `pwsh ums/.claude/scripts/revendor-superpowers.ps1 -UmsRoot ums -PinOnly -Tag <new-tag>` rewrites',
        '   this pin from the tag (Tag, Commit, Skills, Excluded) -> commit. An upstream skill this pin does',
        '   not know stops the run: decide it with `-Include <name>` (vendor it) or `-Exclude <name>` (record',
        '   it under Excluded). A skill listed under Excluded stays out until it is passed with `-Include`.',
        '2. Vendor into each deployment target (the sync does this): `pwsh <script> -NoOverlays',
        '   -SkillsRoot <target> -PinSource <fork pin>` vendors exactly the pinned skills, removes skills that',
        '   are in the TARGET''s own previous pin but no longer in the new one, deletes present target',
        '   directories of Excluded skills, and writes the target pin. A tag change on a git-tracked target is',
        '   two runs: this one -> commit (vanilla sync), then step 3 -> commit (UMS overlay).',
        '3. `pwsh <script> -OverlaysOnly -SkillsRoot <target>` -> commit (UMS overlay)',
        '4. An `ANCHOR-BEFORE` miss means upstream moved the anchored text - fix the fragment in',
        '   `shared/overlays/` and re-run step 3. Never edit vendored files by hand outside overlay blocks.',
        '',
        'Removal of skills that left the pin compares the target''s previous pin with -PinSource, so it needs',
        'them to be different files. A run whose -PinSource is the target''s own pin (in place) removes',
        'nothing that merely left the pin; it only deletes directories of Excluded skills.',
        '',
        'This file pins the VENDORED UPSTREAM version only. The UMS contract has its own,',
        'separate version: `Contract-Version` at the top of `UMS_MEMORY_BANK_CONTRACT.md`,',
        'with the per-version history in shared/CHANGELOG.md.',
        ''
    )
    $dir = Split-Path -Parent $PinFile
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
    [IO.File]::WriteAllText($PinFile, ($lines -join "`n"), [Text.UTF8Encoding]::new($false))
}

# Decides which upstream skills are vendored. Unknown = upstream skills the
# previous pin and the caller have no opinion about.
function Resolve-UmsPinSkills([string[]] $UpstreamSkills, $PreviousPin, [string[]] $Include, [string[]] $Exclude) {
    $upstream = @($UpstreamSkills | Where-Object { $_ })
    $inc      = @($Include        | Where-Object { $_ })
    $exc      = @($Exclude        | Where-Object { $_ })
    $prevSkills = @(); $prevExcluded = @()
    if ($null -ne $PreviousPin) {
        $prevSkills   = @($PreviousPin.Skills)
        $prevExcluded = @($PreviousPin.Excluded)
    }
    $excluded = @(($prevExcluded + $exc) | Where-Object { $_ -and ($inc -cnotcontains $_) })
    $skills   = @($upstream | Where-Object { ($excluded -cnotcontains $_) -and (($prevSkills -ccontains $_) -or ($inc -ccontains $_)) })
    $unknown  = @($upstream | Where-Object {
        ($prevSkills -cnotcontains $_) -and ($prevExcluded -cnotcontains $_) -and
        ($inc -cnotcontains $_) -and ($exc -cnotcontains $_) })
    return @{
        Skills   = [string[]]@(Sort-UmsOrdinal @($skills | Select-Object -Unique))
        Excluded = [string[]]@(Sort-UmsOrdinal @($excluded | Select-Object -Unique))
        Unknown  = [string[]]@(Sort-UmsOrdinal @($unknown | Select-Object -Unique))
    }
}

# Skills the target pin carries that the new set no longer has.
function Get-UmsRemovedSkills($TargetPin, [string[]] $NewSkills) {
    if ($null -eq $TargetPin) { return [string[]]@() }
    $new = @($NewSkills)
    return [string[]]@(@($TargetPin.Skills) | Where-Object { $new -cnotcontains $_ })
}

function Get-UmsRepoStateDate([string] $Dir) {
    if (-not (Test-Path -LiteralPath $Dir)) { return 'unknown' }
    $d = git -C $Dir log -1 --format=%cd --date=format:%Y-%m-%d 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $d) { return 'unknown' }
    return $d
}

function Resolve-UmsTagCommit([string] $Tag) {
    Step "Fetching tags in $SpRepo"
    git -C $SpRepo fetch vanila --tags 2>$null | Out-Null
    $commit = git -C $SpRepo rev-parse "$Tag^{commit}" 2>$null
    if ($LASTEXITCODE -ne 0) { Fail "Tag $Tag not found in $SpRepo." }
    return $commit
}

# ---------------------------------------------------------------- pin-only ---
function Invoke-PinOnly {
    if (-not $Tag) { Fail '-PinOnly requires -Tag (e.g. -Tag v6.4.2).' }
    $commit = Resolve-UmsTagCommit $Tag

    Step "Listing upstream skills of $Tag"
    $tree = @(git -C $SpRepo ls-tree "${Tag}:skills")
    if ($LASTEXITCODE -ne 0) { Fail "Cannot list skills/ of $Tag in $SpRepo." }
    # "<mode> <type> <sha>\t<name>" - directories only.
    $upstream = @($tree | Where-Object { $_ -match '^\d+ tree [0-9a-f]+\t(.+)$' } | ForEach-Object { $Matches[1] })

    $previous = Read-UmsVendorPin $PinSource
    $r = Resolve-UmsPinSkills $upstream $previous $Include $Exclude
    if (@($r.Unknown).Count -gt 0) {
        Fail ("Upstream $Tag has skill(s) the pin has no decision for: $(@($r.Unknown) -join ', '). " +
              "Re-run with -Include <name> to vendor a skill or -Exclude <name> to leave it out.")
    }

    Step "Writing $PinSource"
    $dir = Split-Path -Parent $PinSource
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
    Write-UmsVendorPin $PinSource $Tag $commit $r.Skills $r.Excluded (Get-UmsRepoStateDate $dir)
    Write-Host "    Tag $Tag ($commit): $(@($r.Skills).Count) skill(s), $(@($r.Excluded).Count) excluded"
}

# ---------------------------------------------------------------- vendor ----
function Invoke-Vendor {
    $pin = Read-UmsVendorPin $PinSource
    if ($null -eq $pin) { Fail "Pin file not found: $PinSource (create it with -PinOnly -Tag <tag>)." }
    $useTag = if ($Tag) { $Tag } else { $pin.Tag }
    if (-not $useTag) { Fail "Pin $PinSource has no Tag and no -Tag was given." }
    $skills = @($pin.Skills)
    if ($skills.Count -eq 0) { Fail "Pin $PinSource lists no Skills." }

    $commit = Resolve-UmsTagCommit $useTag

    Step "Exporting skills/ from $useTag ($commit)"
    $staging = Join-Path ([IO.Path]::GetTempPath()) "sp-vendor-$useTag"
    if (Test-Path $staging) { Remove-Item -Recurse -Force $staging }
    New-Item -ItemType Directory -Force $staging | Out-Null
    $tarPath = Join-Path $staging 'skills.tar'
    git -C $SpRepo archive --format=tar -o $tarPath $useTag 'skills/'
    if ($LASTEXITCODE -ne 0) { Fail 'git archive failed.' }
    # Extract with a relative name from inside the staging dir: an msys tar (Git Bash
    # PATH) reads 'C:' in an absolute path as a remote host.
    Push-Location $staging
    try { tar -xf 'skills.tar' } finally { Pop-Location }
    if ($LASTEXITCODE -ne 0) { Fail 'tar extraction failed.' }

    New-Item -ItemType Directory -Force $SkillsRoot | Out-Null

    # The target pin as it stands BEFORE this phase rewrites it: skills that left
    # the pin are removed from the target. (Needs -PinSource != the target pin; when
    # both are the same file the previous pin already IS the new pin.)
    $previous = Read-UmsVendorPin $PinFile
    $removed = @(Get-UmsRemovedSkills $previous $skills)
    foreach ($r in $removed) {
        $gone = Join-Path $SkillsRoot $r
        if (Test-Path -LiteralPath $gone) {
            Step "Removing skill '$r' (no longer pinned)"
            Remove-Item -Recurse -Force -LiteralPath $gone
        }
    }

    # Excluded skills are never vendored: delete any copy the target still holds.
    foreach ($x in @($pin.Excluded)) {
        $excludedDir = Join-Path $SkillsRoot $x
        if (Test-Path -LiteralPath $excludedDir) {
            Step "Removing skill '$x' (excluded by the pin)"
            Remove-Item -Recurse -Force -LiteralPath $excludedDir
        }
    }

    Step 'Replacing skill directories wholesale'
    foreach ($s in $skills) {
        $src = Join-Path $staging "skills\$s"
        if (-not (Test-Path $src)) { Fail "Skill '$s' from the pin is missing in upstream $useTag - fix the pin (-PinOnly -Tag $useTag)." }
        $dst = Join-Path $SkillsRoot $s
        if (Test-Path $dst) { Remove-Item -Recurse -Force $dst }
        Copy-Item -Recurse $src $dst
        # git archive applies autocrlf smudge to files not covered by upstream
        # .gitattributes (e.g. extension-less bash scripts) - normalize to LF.
        Get-ChildItem -Path $dst -Recurse -File | ForEach-Object {
            $raw = Get-Content -Path $_.FullName -Raw
            if ($raw -match "`r") { Set-Content -Path $_.FullName -NoNewline -Value ($raw -replace "`r`n", "`n") }
        }
    }
    Remove-Item -Recurse -Force $staging

    Step "Writing $PinFile"
    Write-UmsVendorPin $PinFile $useTag $commit $skills @($pin.Excluded) (Get-UmsRepoStateDate $SkillsRoot)
}

# --------------------------------------------------------------- overlays ---
# Claude Code re-injects only the first ~5,000 tokens of a skill after compaction, so
# the first overlay block of a skill must start within $MaxChars characters (a header
# pointer block). A file without any block passes.
function Test-UmsOverlayPointerPosition([string] $SkillFile, [int] $MaxChars = 12000) {
    $raw = Get-Content -LiteralPath $SkillFile -Raw
    if ([string]::IsNullOrEmpty($raw)) { return $true }
    $first = $raw.IndexOf('UMS-OVERLAY BEGIN', [StringComparison]::Ordinal)
    if ($first -lt 0) { return $true }
    return ($first -lt $MaxChars)
}

function Invoke-Overlays {
    Step "Applying overlay fragments from $OverlaysDir"
    $fragments = @(Get-ChildItem -Path $OverlaysDir -Filter '*.overlay.md' -ErrorAction SilentlyContinue)
    if ($fragments.Count -eq 0) { Write-Host '    (no fragments found - nothing to apply)'; return }

    # Parse every fragment first, so a malformed one fails before anything is written.
    $parsed = foreach ($frag in $fragments) {
        $lines = Get-Content -Path $frag.FullName
        if ($lines[0] -notmatch '^<!-- TARGET: (.+?) -->$') { Fail "$($frag.Name): first line must be '<!-- TARGET: <skill>/<file> -->'." }
        $targetRel = $Matches[1].Trim()
        $target = Join-Path $SkillsRoot ($targetRel -replace '/', '\')
        if (-not (Test-Path $target)) { Fail "$($frag.Name): target '$targetRel' does not exist." }

        $anchorLine = $lines[1]
        $bodyStart = 2
        $asserts = @()
        while ($bodyStart -lt $lines.Count -and $lines[$bodyStart] -match '^<!-- ASSERT: (.+?) -->$') {
            $asserts += $Matches[1]
            $bodyStart++
        }
        $body = ($lines[$bodyStart..($lines.Count - 1)] -join "`n").TrimStart("`r", "`n")
        if ($body -notmatch 'UMS-OVERLAY BEGIN' -or $body -notmatch 'UMS-OVERLAY END') {
            Fail "$($frag.Name): body must contain '<!-- UMS-OVERLAY BEGIN ... -->' and '<!-- UMS-OVERLAY END -->' markers."
        }
        [pscustomobject]@{
            Name = $frag.Name; TargetRel = $targetRel; Target = $target
            AnchorLine = $anchorLine; Asserts = $asserts; Body = $body
        }
    }

    # One pass per target: fragments of the same target apply in ordinal file-name order
    # (alpha.overlay.md before alpha.pointer.overlay.md), each against the file as the
    # previous fragment left it. The target is written once, after its last fragment.
    $groups = @($parsed | Group-Object -Property TargetRel)
    foreach ($groupName in (Sort-UmsOrdinal @($groups.Name))) {
        $group = $groups | Where-Object { $_.Name -ceq $groupName }
        $ordered = @(foreach ($n in (Sort-UmsOrdinal @($group.Group.Name))) { $group.Group | Where-Object { $_.Name -ceq $n } })
        $targetRel = $groupName
        $target = $ordered[0].Target
        $content = (Get-Content -Path $target -Raw) -replace "`r`n", "`n"

        # Pristine check: once per target, before its first fragment.
        if ($content -match 'UMS-OVERLAY BEGIN') {
            Fail "${targetRel}: already contains an overlay block. Re-vendor first (vendored files must be pristine before overlay application)."
        }

        foreach ($f in $ordered) {
            $targetLines = $content -split "`n"
            foreach ($a in $f.Asserts) {
                $hits = @($targetLines | Where-Object { $_.TrimEnd() -eq $a }).Count
                if ($hits -ne 1) { Fail "$($f.Name): ASSERT '$a' matched $hits lines in target (need exactly 1). Upstream drift - update the fragment." }
            }

            if ($f.AnchorLine -match '^<!-- ANCHOR: EOF -->$') {
                $content = $content.TrimEnd("`n") + "`n`n" + $f.Body + "`n"
            }
            elseif ($f.AnchorLine -match '^<!-- ANCHOR-BEFORE: (.+?) -->$') {
                $anchor = $Matches[1]
                $hits = @(0..($targetLines.Count - 1) | Where-Object { $targetLines[$_].TrimEnd() -eq $anchor })
                if ($hits.Count -ne 1) { Fail "$($f.Name): anchor '$anchor' matched $($hits.Count) lines in target (need exactly 1). Upstream drift - update the fragment." }
                $i = $hits[0]
                $before = if ($i -gt 0) { $targetLines[0..($i - 1)] } else { @() }
                $after  = $targetLines[$i..($targetLines.Count - 1)]
                $content = (($before + ($f.Body -split "`n") + '' + $after) -join "`n")
            }
            else { Fail "$($f.Name): second line must be '<!-- ANCHOR: EOF -->' or '<!-- ANCHOR-BEFORE: <line> -->'." }
            Write-Host "    applied $($f.Name)"
        }
        Set-Content -Path $target -NoNewline -Value $content
    }
}

# ----------------------------------------------------------------- verify ---
function Invoke-Verify {
    $problems = [System.Collections.Generic.List[string]]::new()

    $pin = Read-UmsVendorPin $PinFile
    if ($null -eq $pin) { Fail "Verification needs the pin file: $PinFile" }
    $pinned = @($pin.Skills)

    Step 'Verify: stale v5 files absent, required v6 files present'
    foreach ($f in @('subagent-driven-development\spec-reviewer-prompt.md',
                     'subagent-driven-development\code-quality-reviewer-prompt.md')) {
        if (Test-Path (Join-Path $SkillsRoot $f)) { $problems.Add("stale v5 file present: $f") }
    }
    # Required files are checked only for skills the pin actually vendors.
    foreach ($f in @('subagent-driven-development\task-reviewer-prompt.md',
                     'subagent-driven-development\implementer-prompt.md',
                     'subagent-driven-development\scripts\task-brief',
                     'subagent-driven-development\scripts\review-package',
                     'subagent-driven-development\scripts\sdd-workspace',
                     'requesting-code-review\code-reviewer.md',
                     'brainstorming\spec-document-reviewer-prompt.md',
                     'executing-plans\scripts\task-start',
                     'executing-plans\scripts\task-done')) {
        if ($pinned -cnotcontains ($f -split '\\')[0]) { continue }
        if (-not (Test-Path (Join-Path $SkillsRoot $f))) { $problems.Add("required v6 file missing: $f") }
    }

    Step 'Verify: overlay markers balanced and fragments applied'
    $fragments = @(Get-ChildItem -Path $OverlaysDir -Filter '*.overlay.md' -ErrorAction SilentlyContinue)
    $appliedBegin = 0; $appliedEnd = 0
    Get-ChildItem -Path $SkillsRoot -Recurse -Filter '*.md' |
        Where-Object { $_.FullName -notlike "*\shared\*" } |
        ForEach-Object {
            $raw = Get-Content -Path $_.FullName -Raw
            $appliedBegin += ([regex]::Matches($raw, 'UMS-OVERLAY BEGIN')).Count
            $appliedEnd   += ([regex]::Matches($raw, 'UMS-OVERLAY END')).Count
        }
    # The counts are plain substring counts, so a fragment BODY that quotes a marker literally
    # ('UMS-OVERLAY BEGIN' / 'UMS-OVERLAY END') is counted as a marker too - name that cause.
    $markerHint = "an overlay fragment body must not contain the literal marker strings 'UMS-OVERLAY BEGIN' / 'UMS-OVERLAY END' (they are counted as markers)"
    if ($appliedBegin -ne $appliedEnd) { $problems.Add("unbalanced overlay markers: $appliedBegin BEGIN vs $appliedEnd END - $markerHint") }
    if (-not $NoOverlays -and -not $VerifyOnly -and $appliedBegin -ne $fragments.Count) {
        $problems.Add("overlay count mismatch: $($fragments.Count) fragments but $appliedBegin applied blocks - $markerHint")
    }

    Step 'Verify: overlay pointer block within the re-injection window'
    # Every overlayed skill must open its first overlay block near the top of SKILL.md.
    Get-ChildItem -Path $SkillsRoot -Recurse -File -Filter 'SKILL.md' |
        Where-Object { $_.FullName -notlike "*\shared\*" } |
        ForEach-Object {
            $raw = Get-Content -Path $_.FullName -Raw
            if ($raw -and $raw.Contains('UMS-OVERLAY BEGIN') -and -not (Test-UmsOverlayPointerPosition $_.FullName)) {
                $problems.Add("overlay block of $($_.FullName.Substring($SkillsRoot.Length + 1)) starts after the first 12000 characters - add a header pointer fragment (<skill>.pointer.overlay.md)")
            }
        }

    Step 'Verify: no dangling relative links in vendored/shared markdown'
    $linkScanDirs = @()
    foreach ($s in $pinned) {
        $d = Join-Path $SkillsRoot $s
        if (Test-Path -LiteralPath $d) { $linkScanDirs += $d } else { $problems.Add("pinned skill missing on disk: $s") }
    }
    if (Test-Path -LiteralPath $SharedDir) { $linkScanDirs += $SharedDir }
    if ($linkScanDirs.Count -gt 0) {
        # Overlay fragments are skipped: their links are written relative to the TARGET
        # skill and are checked where they land, in the overlayed SKILL.md.
        $overlaysPrefix = [IO.Path]::GetFullPath($OverlaysDir).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
        Get-ChildItem -Path $linkScanDirs -Recurse -Filter '*.md' |
            Where-Object { -not ($_.Name.EndsWith('.overlay.md', [StringComparison]::OrdinalIgnoreCase) -and
                                 $_.FullName.StartsWith($overlaysPrefix, [StringComparison]::OrdinalIgnoreCase)) } |
            ForEach-Object {
            $file = $_
            $raw = Get-Content -Path $file.FullName -Raw
            # Skip links inside fenced code blocks and inline code - those are examples.
            $raw = [regex]::Replace($raw, '(?s)```.*?```', '')
            $raw = [regex]::Replace($raw, '`[^`\r\n]*`', '')
            foreach ($m in [regex]::Matches($raw, '\]\(([^)\s]+?)(?:#[^)]*)?\)')) {
                $link = $m.Groups[1].Value
                if ($link -match '^[a-z][a-z0-9+.-]*:' -or $link.StartsWith('/') -or $link.StartsWith('#')) { continue }
                $resolved = Join-Path $file.DirectoryName ($link -replace '/', '\')
                if (-not (Test-Path $resolved)) {
                    $problems.Add("dangling link in $($file.FullName.Substring($SkillsRoot.Length + 1)): $link")
                }
            }
        }
    }

    Step 'Verify: no CRLF in bash scripts'
    # Only bash scripts must be LF - Git Bash chokes on a CRLF shebang. That is
    # extension-less shebang files in a scripts/ dir, plus any .sh. PowerShell
    # (.ps1/.psm1) is CRLF-safe and is normalized to LF on commit by
    # .gitattributes, so a CRLF working-tree copy is not a defect - skip it to
    # avoid false positives on UMS utility scripts (e.g. mb-epic-* scripts).
    Get-ChildItem -Path $SkillsRoot -Recurse -File |
        Where-Object { ($_.Extension -eq '.sh') -or ($_.Directory.Name -eq 'scripts' -and $_.Extension -eq '') } |
        ForEach-Object {
            if ((Get-Content -Path $_.FullName -Raw) -match "`r") {
                $problems.Add("CRLF found in script: $($_.FullName.Substring($SkillsRoot.Length + 1))")
            }
        }

    Step 'Verify: SDD scripts run under Git Bash'
    # Since v6.2.0, sdd-workspace is plan-scoped: it requires a PLAN_FILE argument and
    # creates .superpowers/sdd/<plan-basename>/. Feed it a throwaway plan file.
    $sddPath = Join-Path $SkillsRoot 'subagent-driven-development\scripts\sdd-workspace'
    if ($pinned -ccontains 'subagent-driven-development' -and (Test-Path -LiteralPath $sddPath)) {
        # The script keeps its workspace in the git working tree of the TARGET, so the test
        # runs from that repository's root; a target outside git has nothing to test in.
        $gitTop = $null
        if (Test-Path -LiteralPath $SkillsRoot) {
            $gitTop = git -C $SkillsRoot rev-parse --show-toplevel 2>$null
            if ($LASTEXITCODE -ne 0 -or -not $gitTop) { $gitTop = $null }
        }
        if ($null -eq $gitTop) {
            Write-Host 'SKIP: sdd-workspace functional test (target is not inside a git repository)'
        }
        else {
            $gitTop = ([IO.Path]::GetFullPath(($gitTop | Select-Object -First 1))).TrimEnd('\', '/')
            # Relative to the repository root (the cwd below): a `bash` that is WSL's cannot
            # open C:/... absolute paths, but resolves relative ones. git reports the path of
            # SkillsRoot inside the repository, which avoids comparing two spellings of a path.
            $prefix = (git -C $SkillsRoot rev-parse --show-prefix 2>$null | Select-Object -First 1)
            $sddWs = ($prefix + 'subagent-driven-development/scripts/sdd-workspace')
            Push-Location $gitTop
            $planFile = '.superpowers-revendor-verify.md'
            $workspace = Join-Path $gitTop '.superpowers\sdd\.superpowers-revendor-verify'
            try {
                Set-Content -Path (Join-Path $gitTop $planFile) -Value '# revendor verify plan' -NoNewline
                $out = bash $sddWs $planFile 2>&1
                if ($LASTEXITCODE -ne 0 -or -not $out) { $problems.Add("sdd-workspace failed (exit $LASTEXITCODE): $out") }
                elseif (-not (Test-Path $workspace)) { $problems.Add('sdd-workspace did not create the plan workspace') }
            } finally {
                Remove-Item -Path (Join-Path $gitTop $planFile) -Force -ErrorAction SilentlyContinue
                Remove-Item -Path $workspace -Recurse -Force -ErrorAction SilentlyContinue
                Pop-Location
            }
        }
    }

    if ($problems.Count -gt 0) {
        $problems | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
        Fail "$($problems.Count) verification problem(s)."
    }
    Step 'Verification passed.'
}

# ------------------------------------------------------------------- main ---
if ($DotSourceOnly) { return }

if ((@($Include).Count -gt 0 -or @($Exclude).Count -gt 0) -and -not $PinOnly) {
    Fail '-Include/-Exclude decide upstream skills and only apply together with -PinOnly.'
}
if ($PinOnly -and ($NoOverlays -or $OverlaysOnly -or $VerifyOnly)) {
    Fail '-PinOnly cannot be combined with -NoOverlays, -OverlaysOnly or -VerifyOnly.'
}

if ($PinOnly)           { Invoke-PinOnly }
elseif ($VerifyOnly)    { Invoke-Verify }
elseif ($OverlaysOnly)  { Invoke-Overlays; Invoke-Verify }
elseif ($NoOverlays)    { Invoke-Vendor;   Invoke-Verify }
else                    { Invoke-Vendor;   Invoke-Overlays; Invoke-Verify }
