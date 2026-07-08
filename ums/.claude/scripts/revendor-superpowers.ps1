<#
.SYNOPSIS
    Re-vendors the Superpowers skill pack from the upstream mirror repo into
    .claude/skills/ and re-applies the UMS overlay blocks.

.DESCRIPTION
    Two-commit workflow (see UMS_MEMORY_BANK_CONTRACT.md, Versioning & Vendoring):
      1. pwsh revendor-superpowers.ps1 -Tag v6.1.1 -NoOverlays   -> commit "vanilla sync"
      2. pwsh revendor-superpowers.ps1 -OverlaysOnly             -> commit "UMS overlay"
    Or run without switches to do both in one pass (single-commit workflow).

    Overlay fragments live in .claude/skills/shared/overlays/*.overlay.md.
    Fragment format (first lines are directives, rest is the block to insert):
      <!-- TARGET: <skill>/<file> -->
      <!-- ANCHOR: EOF -->                          (append at end of file)
      or
      <!-- ANCHOR-BEFORE: <exact line text> -->     (insert before that line)
    An anchor that no longer matches upstream text is a HARD ERROR - that is the
    upstream-drift detector: it enumerates exactly the blocks needing attention.

.NOTES
    Verification always runs last and fails the script on any problem:
    dangling relative links, stale v5 files, missing v6 files, unbalanced
    overlay markers, CRLF in bash scripts, and a functional Git Bash test of
    the SDD scripts.
#>
#Requires -Version 7
[CmdletBinding()]
param(
    [string]$SpRepo = 'C:\Users\matejka\source\repos\superpowers',
    [string]$Tag,
    [string]$UmsRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path,
    [switch]$NoOverlays,
    [switch]$OverlaysOnly,
    [switch]$VerifyOnly
)

$ErrorActionPreference = 'Stop'

$Skills = @(
    'brainstorming', 'dispatching-parallel-agents', 'executing-plans',
    'finishing-a-development-branch', 'receiving-code-review', 'requesting-code-review',
    'subagent-driven-development', 'systematic-debugging', 'test-driven-development',
    'using-git-worktrees', 'using-superpowers', 'verification-before-completion',
    'writing-plans', 'writing-skills'
)

$SkillsRoot  = Join-Path $UmsRoot '.claude\skills'
$SharedDir   = Join-Path $SkillsRoot 'shared'
$OverlaysDir = Join-Path $SharedDir 'overlays'
$PinFile     = Join-Path $SharedDir 'VENDORED_FROM.md'

function Step([string]$msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Fail([string]$msg) { Write-Host "FAIL: $msg" -ForegroundColor Red; exit 1 }

# ---------------------------------------------------------------- vendor ----
function Invoke-Vendor {
    if (-not $Tag) { Fail 'Vendoring requires -Tag (e.g. -Tag v6.1.1).' }

    Step "Fetching tags in $SpRepo"
    git -C $SpRepo fetch vanila --tags 2>$null
    $commit = git -C $SpRepo rev-parse "$Tag^{commit}"
    if ($LASTEXITCODE -ne 0) { Fail "Tag $Tag not found in $SpRepo." }

    Step "Exporting skills/ from $Tag ($commit)"
    $staging = Join-Path ([IO.Path]::GetTempPath()) "sp-vendor-$Tag"
    if (Test-Path $staging) { Remove-Item -Recurse -Force $staging }
    New-Item -ItemType Directory -Force $staging | Out-Null
    $tarPath = Join-Path $staging 'skills.tar'
    git -C $SpRepo archive --format=tar -o $tarPath $Tag 'skills/'
    if ($LASTEXITCODE -ne 0) { Fail 'git archive failed.' }
    tar -xf $tarPath -C $staging
    if ($LASTEXITCODE -ne 0) { Fail 'tar extraction failed.' }

    Step 'Replacing skill directories wholesale'
    foreach ($s in $Skills) {
        $src = Join-Path $staging "skills\$s"
        if (-not (Test-Path $src)) { Fail "Skill '$s' missing in upstream $Tag - update the skill list in this script." }
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
    $today = git -C $UmsRoot log -1 --format=%cd --date=format:%Y-%m-%d 2>$null
    if (-not $today) { $today = 'unknown' }
    $skillLines = ($Skills | ForEach-Object { "  $_" }) -join [Environment]::NewLine
    Set-Content -Path $PinFile -NoNewline -Value (@"
# Vendored Superpowers skills

- Upstream: https://github.com/obra/superpowers.git (mirror: C:\Users\matejka\source\repos\superpowers)
- Tag: $Tag
- Commit: $commit
- Vendored on top of repo state: $today (by .claude/scripts/revendor-superpowers.ps1)
- Skills:
$skillLines
- Overlays: applied from ``shared/overlays/*.overlay.md``; applied blocks are marked
  ``<!-- UMS-OVERLAY BEGIN/END -->`` inside the vendored files.

## Re-vendor procedure

1. ``pwsh .claude/scripts/revendor-superpowers.ps1 -Tag <new-tag> -NoOverlays`` -> commit (vanilla sync)
2. ``pwsh .claude/scripts/revendor-superpowers.ps1 -OverlaysOnly`` -> commit (UMS overlay)
3. An ``ANCHOR-BEFORE`` miss means upstream moved the anchored text - fix the fragment in
   ``shared/overlays/`` and re-run step 2. Never edit vendored files by hand outside overlay blocks.
"@ + [Environment]::NewLine)
}

# --------------------------------------------------------------- overlays ---
function Invoke-Overlays {
    Step "Applying overlay fragments from $OverlaysDir"
    $fragments = @(Get-ChildItem -Path $OverlaysDir -Filter '*.overlay.md' -ErrorAction SilentlyContinue)
    if ($fragments.Count -eq 0) { Write-Host '    (no fragments found - nothing to apply)'; return }

    foreach ($frag in $fragments) {
        $lines = Get-Content -Path $frag.FullName
        if ($lines[0] -notmatch '^<!-- TARGET: (.+?) -->$') { Fail "$($frag.Name): first line must be '<!-- TARGET: <skill>/<file> -->'." }
        $targetRel = $Matches[1].Trim()
        $target = Join-Path $SkillsRoot ($targetRel -replace '/', '\')
        if (-not (Test-Path $target)) { Fail "$($frag.Name): target '$targetRel' does not exist." }

        $anchorLine = $lines[1]
        $body = ($lines[2..($lines.Count - 1)] -join "`n").TrimStart("`r", "`n")
        if ($body -notmatch 'UMS-OVERLAY BEGIN' -or $body -notmatch 'UMS-OVERLAY END') {
            Fail "$($frag.Name): body must contain '<!-- UMS-OVERLAY BEGIN ... -->' and '<!-- UMS-OVERLAY END -->' markers."
        }

        $content = (Get-Content -Path $target -Raw) -replace "`r`n", "`n"
        if ($content -match 'UMS-OVERLAY BEGIN') {
            Fail "$($frag.Name): '$targetRel' already contains an overlay block. Re-vendor first (vendored files must be pristine before overlay application)."
        }

        if ($anchorLine -match '^<!-- ANCHOR: EOF -->$') {
            $newContent = $content.TrimEnd("`n") + "`n`n" + $body + "`n"
        }
        elseif ($anchorLine -match '^<!-- ANCHOR-BEFORE: (.+?) -->$') {
            $anchor = $Matches[1]
            $contentLines = $content -split "`n"
            $hits = @(0..($contentLines.Count - 1) | Where-Object { $contentLines[$_].TrimEnd() -eq $anchor })
            if ($hits.Count -ne 1) { Fail "$($frag.Name): anchor '$anchor' matched $($hits.Count) lines in target (need exactly 1). Upstream drift - update the fragment." }
            $i = $hits[0]
            $before = if ($i -gt 0) { $contentLines[0..($i - 1)] } else { @() }
            $after  = $contentLines[$i..($contentLines.Count - 1)]
            $newContent = (($before + ($body -split "`n") + '' + $after) -join "`n")
        }
        else { Fail "$($frag.Name): second line must be '<!-- ANCHOR: EOF -->' or '<!-- ANCHOR-BEFORE: <line> -->'." }

        Set-Content -Path $target -NoNewline -Value $newContent
        Write-Host "    applied $($frag.Name)"
    }
}

# ----------------------------------------------------------------- verify ---
function Invoke-Verify {
    $problems = [System.Collections.Generic.List[string]]::new()

    Step 'Verify: stale v5 files absent, required v6 files present'
    foreach ($f in @('subagent-driven-development\spec-reviewer-prompt.md',
                     'subagent-driven-development\code-quality-reviewer-prompt.md')) {
        if (Test-Path (Join-Path $SkillsRoot $f)) { $problems.Add("stale v5 file present: $f") }
    }
    foreach ($f in @('subagent-driven-development\task-reviewer-prompt.md',
                     'subagent-driven-development\implementer-prompt.md',
                     'subagent-driven-development\scripts\task-brief',
                     'subagent-driven-development\scripts\review-package',
                     'subagent-driven-development\scripts\sdd-workspace',
                     'requesting-code-review\code-reviewer.md',
                     'brainstorming\spec-document-reviewer-prompt.md',
                     'writing-plans\plan-document-reviewer-prompt.md')) {
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
    if ($appliedBegin -ne $appliedEnd) { $problems.Add("unbalanced overlay markers: $appliedBegin BEGIN vs $appliedEnd END") }
    if (-not $NoOverlays -and -not $VerifyOnly -and $appliedBegin -ne $fragments.Count) {
        $problems.Add("overlay count mismatch: $($fragments.Count) fragments but $appliedBegin applied blocks")
    }

    Step 'Verify: no dangling relative links in vendored/shared markdown'
    $linkScanDirs = @($Skills | ForEach-Object { Join-Path $SkillsRoot $_ }) + $SharedDir
    Get-ChildItem -Path $linkScanDirs -Recurse -Filter '*.md' | ForEach-Object {
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

    Step 'Verify: no CRLF in bash scripts'
    Get-ChildItem -Path $SkillsRoot -Recurse -File |
        Where-Object { $_.Directory.Name -eq 'scripts' -or $_.Extension -eq '.sh' } |
        ForEach-Object {
            if ((Get-Content -Path $_.FullName -Raw) -match "`r") {
                $problems.Add("CRLF found in script: $($_.FullName.Substring($SkillsRoot.Length + 1))")
            }
        }

    Step 'Verify: SDD scripts run under Git Bash'
    $sddWs = '.claude/skills/subagent-driven-development/scripts/sdd-workspace'
    Push-Location $UmsRoot
    try {
        $out = bash $sddWs 2>&1
        if ($LASTEXITCODE -ne 0 -or -not $out) { $problems.Add("sdd-workspace failed (exit $LASTEXITCODE): $out") }
        elseif (-not (Test-Path (Join-Path $UmsRoot '.superpowers\sdd'))) { $problems.Add('sdd-workspace did not create .superpowers/sdd') }
    } finally { Pop-Location }

    if ($problems.Count -gt 0) {
        $problems | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
        Fail "$($problems.Count) verification problem(s)."
    }
    Step 'Verification passed.'
}

# ------------------------------------------------------------------- main ---
if ($VerifyOnly)        { Invoke-Verify }
elseif ($OverlaysOnly)  { Invoke-Overlays; Invoke-Verify }
elseif ($NoOverlays)    { Invoke-Vendor;   Invoke-Verify }
else                    { Invoke-Vendor;   Invoke-Overlays; Invoke-Verify }
