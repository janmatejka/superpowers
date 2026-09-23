#Requires -Version 7
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_assert.ps1')
. (Join-Path $PSScriptRoot 'new-playbook-fixture.ps1')
. (Join-Path $PSScriptRoot '..\scripts\Find-UmsPlaybookMatch.ps1')

$repo = New-PlaybookFixtureRepo
Write-PlaybookFixtureFile $repo 'A/memory-bank/playbook.md' @'
# Playbook — A

## Pro celý podstrom

### Když obnovuješ soubor

- **Po obnově ověř `git ls-files` dřív než `git diff`.** Proč: x. Důkaz: a.
- **Pro `git diff` použij `--find-renames`.** Proč: y. Důkaz: b.

## Jen pro tento projekt

### Když ladíš A

- **Tohle potomci nevidí `git diff`.** Proč: z. Důkaz: c.
'@
git -C $repo add -A; git -C $repo commit -q -m match

Write-Host "== best match first"
$r = @(Find-UmsPlaybookMatch 'Before trusting an empty `git diff`, check `git ls-files`.' $repo 'A/B/memory-bank')
Assert-Eq $r[0].Title 'Po obnově ověř `git ls-files` dřív než `git diff`.' 'two shared tokens rank first'
Assert-Eq $r[0].Score 2 'score counts shared tokens'
Assert-Eq $r[0].Mb 'A/memory-bank' 'match reports its MB'
Assert-True (-not (@($r | ForEach-Object Title) -match 'potomci nevidí')) 'own-project part of an ancestor is not searched'

Write-Host "== case and whitespace"
$r = @(Find-UmsPlaybookMatch 'use ` GIT DIFF ` here' $repo 'A/B/memory-bank')
Assert-True ($r.Count -ge 1) 'tokens are normalized'

Write-Host "== no tokens, top limit"
Assert-Eq @(Find-UmsPlaybookMatch 'no identifiers at all' $repo 'A/B/memory-bank').Count 0 'no tokens, no matches'
Assert-Eq @(Find-UmsPlaybookMatch '`git diff`' $repo 'A/B/memory-bank' -Top 1).Count 1 'Top limits results'

Remove-Item -Recurse -Force $repo
Complete-Tests
