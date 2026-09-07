Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '_assert.ps1')
$ErrorActionPreference = 'Stop'

# `allowed-tools` RESTRICTS: a tool the field does not name cannot be used at
# all. The `integrate` operation pushes by refspec and writes the epic ledger,
# so these two entries are load-bearing for it. Both were already in the field
# when the operation was written - these are regression locks, not proof of a
# fix.
$fm = Get-Content -Raw (Join-Path $PSScriptRoot '..' 'SKILL.md')

Assert-Match $fm 'allowed-tools:.*git push' 'allowed-tools kryje git push — integrate pushuje refspecem'
Assert-Match $fm 'allowed-tools:.*Edit' 'allowed-tools kryje Edit — integrate zapisuje do ledgeru'

Complete-Tests
