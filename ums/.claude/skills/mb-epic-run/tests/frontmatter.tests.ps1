Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '_assert.ps1')
$ErrorActionPreference = 'Stop'

# `allowed-tools` RESTRICTS: a tool the field does not name cannot be used at
# all. `spawn` and `integrate` write the epic ledger and publish the
# elaboration branch (integrate no longer pushes the epic line itself - the
# ticket does after the manager's go), so these two entries are load-bearing
# for them. Both were already in the field when the operations were written -
# these are regression locks, not proof of a fix.
$fm = Get-Content -Raw (Join-Path $PSScriptRoot '..' 'SKILL.md')

Assert-Match $fm 'allowed-tools:.*git push' 'allowed-tools kryje git push — spawn a integrate publikují elaborační větev'
Assert-Match $fm 'allowed-tools:.*Edit' 'allowed-tools kryje Edit — integrate zapisuje do ledgeru'

Complete-Tests
