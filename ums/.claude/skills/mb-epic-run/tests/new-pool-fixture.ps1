#Requires -Version 7
<#
.SYNOPSIS
Builds a throwaway repository with a bare "origin", a main clone and N REAL
linked worktrees sharing one .git — the only shape in which the per-worktree
question this suite exists to answer can be asked at all.

.OUTPUTS
Hashtable: Root, Origin, Main, Slots (ordered array of worktree paths).
#>
[CmdletBinding()]
param(
    [int] $SlotCount = 3,
    [string] $Label = 'pool'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-FixtureGit([string] $Dir, [string[]] $GitArgs) {
    $out = & git -C $Dir @GitArgs 2>&1
    if ($LASTEXITCODE -ne 0) { throw "git $($GitArgs -join ' ') in $Dir failed: $out" }
    return $out
}

$root = Join-Path ([IO.Path]::GetTempPath()) ("mbpool-$Label-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$origin = Join-Path $root 'origin.git'
$main = Join-Path $root 'main'
New-Item -ItemType Directory -Force -Path $root | Out-Null

& git init -q --bare -b develop $origin | Out-Null
& git clone -q $origin $main | Out-Null
Invoke-FixtureGit $main @('config', 'user.email', 'test@example.invalid') | Out-Null
Invoke-FixtureGit $main @('config', 'user.name', 'Test') | Out-Null
'base' | Out-File -FilePath (Join-Path $main 'f.txt') -Encoding utf8
# `.superpowers/` is git-ignored in real repos (contract: "A free workspace" —
# `git status --porcelain` is silent about it), and memory-bank/context.md is
# a REAL tracked file. Both go into the base commit so a slot that Set-SlotIdle
# merely re-writes with byte-identical content stays truly clean — otherwise
# EVERY fixture slot would show a spurious "dirty tree" from its own marker
# and pin files, which no real pool slot would.
'.superpowers/' | Out-File -FilePath (Join-Path $main '.gitignore') -Encoding utf8
# Force LF on checkout REGARDLESS of the host's core.autocrlf. Measured: with
# autocrlf=true (a common Windows default), git checks memory-bank/context.md
# out with CRLF while Set-SlotIdle/Set-SlotPin (Set-Content, literal `n) write
# LF-only — git then reports the untouched, re-written-identically file as
# modified, and every "clean IDLE slot" fixture case would be spuriously dirty.
'* text=auto eol=lf' | Out-File -FilePath (Join-Path $main '.gitattributes') -Encoding utf8
$mb = Join-Path $main 'memory-bank'
New-Item -ItemType Directory -Force -Path $mb | Out-Null
Set-Content -LiteralPath (Join-Path $mb 'context.md') `
    -Value "# Context`n`n## Active Work`n`n(No active work - IDLE phase)`n" -NoNewline -Encoding utf8
Invoke-FixtureGit $main @('add', '-A') | Out-Null
Invoke-FixtureGit $main @('commit', '-m', 'base') | Out-Null
Invoke-FixtureGit $main @('push', '-u', 'origin', 'develop') | Out-Null

$slots = @()
for ($i = 1; $i -le $SlotCount; $i++) {
    $name = 'slot{0:d2}' -f $i
    $path = Join-Path $root $name
    Invoke-FixtureGit $main @('worktree', 'add', '--detach', $path, 'origin/develop') | Out-Null
    $slots += $path
}

return @{ Root = $root; Origin = $origin; Main = $main; Slots = $slots }
