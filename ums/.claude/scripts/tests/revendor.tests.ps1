#Requires -Version 7
# Tests for revendor-superpowers.ps1: the pin (tag + skill set + excluded skills),
# -PinOnly, -SkillsRoot / -PinSource and the vendor phase driven by the pin.
# Offline: the "upstream" is a local throwaway git repo with two tags.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_assert.ps1')
. (Join-Path $PSScriptRoot 'new-revendor-fixture.ps1')

$revendorScript = (Resolve-Path (Join-Path $PSScriptRoot '..\revendor-superpowers.ps1')).Path
. $revendorScript -DotSourceOnly

# Runs the script as a process (the way a sync or a human calls it).
function Invoke-Revendor([string[]] $RevArgs) {
    $text = & pwsh -NoProfile -File $revendorScript @RevArgs 2>&1 | Out-String
    return @{ Exit = $LASTEXITCODE; Out = $text }
}

$fx = New-RevendorFixture
try {
    $pinFile = Join-Path $fx.SkillsRoot 'shared\VENDORED_FROM.md'
    $common = @('-SpRepo', $fx.SpRepo, '-UmsRoot', $fx.UmsRoot, '-SkillsRoot', $fx.SkillsRoot)

    Write-Host '== Read-UmsVendorPin'
    Assert-True ($null -eq (Read-UmsVendorPin (Join-Path $fx.Root 'no-such-pin.md'))) 'missing pin file = $null'
    $pin = Read-UmsVendorPin $pinFile
    Assert-Eq $pin.Tag 't1' 'pin: tag'
    Assert-Eq $pin.Commit $fx.T1Commit 'pin: commit'
    Assert-Eq ($pin.Skills -join ',') 'alpha,beta,subagent-driven-development' 'pin: skills (Overlays lines are not skills)'
    Assert-Eq (@($pin.Excluded).Count) 0 'pin bez sekce Excluded = prazdne pole'

    Write-Host '== Write-UmsVendorPin / Read-UmsVendorPin round trip'
    $rt = Join-Path $fx.Root 'roundtrip\VENDORED_FROM.md'
    Write-UmsVendorPin $rt 'v9' 'abc123' @('alpha', 'zeta') @('gamma', 'omega') '2026-02-03'
    $rtPin = Read-UmsVendorPin $rt
    Assert-Eq $rtPin.Tag 'v9' 'round trip: tag'
    Assert-Eq $rtPin.Commit 'abc123' 'round trip: commit'
    Assert-Eq ($rtPin.Skills -join ',') 'alpha,zeta' 'round trip: skills'
    Assert-Eq ($rtPin.Excluded -join ',') 'gamma,omega' 'round trip: excluded'
    $rtText = Get-Content -LiteralPath $rt -Raw
    Assert-Match $rtText '(?m)^- Excluded:\r?$' 'written pin has the Excluded section'
    Assert-Match $rtText '(?m)^- Vendored on top of repo state: 2026-02-03 ' 'written pin carries the repo-state date'
    Assert-Match $rtText '-PinOnly' 'written pin documents -PinOnly'
    Assert-Match $rtText '(?m)^This file pins the VENDORED UPSTREAM version only\.' 'written pin keeps the closing paragraph (upstream version only)'
    Assert-Match $rtText '`Contract-Version` at the top of `UMS_MEMORY_BANK_CONTRACT\.md`' 'written pin keeps the Contract-Version sentence'
    Assert-Match $rtText '(?m)^with the per-version history in shared/CHANGELOG\.md\.$' 'written pin names shared/CHANGELOG.md as plain text'
    Assert-True (-not $rtText.Contains('](CHANGELOG.md)')) 'written pin has no CHANGELOG link (would dangle in a foreign SkillsRoot)'
    Assert-Match $rtText 'TARGET.s own previous pin' 'written procedure ties removal to the target pin'
    Assert-True (-not $rtText.Contains("`r")) 'written pin uses LF'
    Write-UmsVendorPin $rt 'v9' 'abc123' @('alpha') @() '2026-02-03'
    $emptyEx = Read-UmsVendorPin $rt
    Assert-Eq (@($emptyEx.Excluded).Count) 0 'round trip: empty Excluded stays empty'
    Assert-Eq ($emptyEx.Skills -join ',') 'alpha' 'round trip: skills before an empty Excluded section'

    Write-Host '== Resolve-UmsPinSkills'
    $r = Resolve-UmsPinSkills @('alpha', 'gamma', 'subagent-driven-development') $pin @() @()
    Assert-Eq ($r.Unknown -join ',') 'gamma' 'novy upstream skill je Unknown'
    Assert-Eq ($r.Skills -join ',') 'alpha,subagent-driven-development' 'Unknown skill is not vendored; removed beta drops out'
    $r = Resolve-UmsPinSkills @('alpha', 'gamma', 'subagent-driven-development') $pin @() @('gamma')
    Assert-Eq (@($r.Unknown).Count) 0 '-Exclude rozhodne neznamy skill'
    Assert-Eq ($r.Excluded -join ',') 'gamma' 'vylouceny skill jde do Excluded'
    Assert-Eq ($r.Skills -join ',') 'alpha,subagent-driven-development' '-Exclude keeps the skill out of Skills'
    $r = Resolve-UmsPinSkills @('alpha', 'gamma', 'subagent-driven-development') $pin @('gamma') @()
    Assert-Eq (@($r.Unknown).Count) 0 '-Include rozhodne neznamy skill'
    Assert-Eq ($r.Skills -join ',') 'alpha,gamma,subagent-driven-development' '-Include vendors the new skill'
    Assert-Eq (@($r.Excluded).Count) 0 '-Include: nothing excluded'
    $pinWithEx = [pscustomobject]@{ Tag = 't2'; Commit = 'x'; Skills = [string[]]@('alpha'); Excluded = [string[]]@('gamma') }
    $r = Resolve-UmsPinSkills @('alpha', 'gamma') $pinWithEx @() @()
    Assert-Eq (@($r.Unknown).Count) 0 'previously excluded skill is not Unknown again'
    Assert-Eq ($r.Excluded -join ',') 'gamma' 'previously excluded skill stays Excluded'
    Assert-Eq ($r.Skills -join ',') 'alpha' 'previously excluded skill stays out of Skills'
    $r = Resolve-UmsPinSkills @('alpha', 'gamma') $pinWithEx @('gamma') @()
    Assert-Eq ($r.Skills -join ',') 'alpha,gamma' '-Include re-admits a previously excluded skill'
    Assert-Eq (@($r.Excluded).Count) 0 '-Include removes the skill from Excluded'
    $r = Resolve-UmsPinSkills @('alpha', 'gamma') $null @() @()
    Assert-Eq ($r.Unknown -join ',') 'alpha,gamma' 'no previous pin: every upstream skill is Unknown'

    Write-Host '== Get-UmsRemovedSkills'
    Assert-Eq ((Get-UmsRemovedSkills $pin @('alpha', 'subagent-driven-development')) -join ',') 'beta' 'zruseny skill se smaze'
    Assert-Eq (@(Get-UmsRemovedSkills $null @('alpha')).Count) 0 'null pin = nothing removed'
    Assert-Eq (@(Get-UmsRemovedSkills $pin @('alpha', 'beta', 'subagent-driven-development')).Count) 0 'unchanged set = nothing removed'

    Write-Host '== -PinOnly without a decision fails and names the skill'
    $before = Get-Content -LiteralPath $pinFile -Raw
    $res = Invoke-Revendor ($common + @('-PinOnly', '-Tag', 't2'))
    Assert-True ($res.Exit -ne 0) '-PinOnly -Tag t2 without a decision exits non-zero'
    Assert-Match $res.Out 'gamma' 'output names the undecided skill'
    Assert-Match $res.Out '-Include' 'output points to -Include'
    Assert-Match $res.Out '-Exclude' 'output points to -Exclude'
    Assert-True ((Get-Content -LiteralPath $pinFile -Raw) -ceq $before) 'the pin is untouched after the failed -PinOnly'

    Write-Host '== -PinOnly -Exclude gamma writes the pin'
    $res = Invoke-Revendor ($common + @('-PinOnly', '-Tag', 't2', '-Exclude', 'gamma'))
    Assert-Eq $res.Exit 0 '-PinOnly -Tag t2 -Exclude gamma succeeds'
    $pin2 = Read-UmsVendorPin $pinFile
    Assert-Eq $pin2.Tag 't2' 'written pin: Tag t2'
    Assert-Eq ($pin2.Skills -join ',') 'alpha,subagent-driven-development' 'written pin: Skills without beta'
    Assert-Eq ($pin2.Excluded -join ',') 'gamma' 'written pin: Excluded gamma'
    Assert-True ($pin2.Commit -ne $fx.T1Commit -and $pin2.Commit -match '^[0-9a-f]{40}$') 'written pin: commit of t2'
    Assert-Match (Get-Content -LiteralPath $pinFile -Raw) '(?m)^- Vendored on top of repo state: 20\d\d-\d\d-\d\d ' 'written pin: repo-state date from the git of the pin directory'

    Write-Host '== -PinOnly is idempotent and remembers Excluded'
    $res = Invoke-Revendor ($common + @('-PinOnly', '-Tag', 't2'))
    Assert-Eq $res.Exit 0 'repeat -PinOnly without flags succeeds (gamma is already decided)'
    $pin3 = Read-UmsVendorPin $pinFile
    Assert-Eq ($pin3.Excluded -join ',') 'gamma' 'Excluded survives a repeat run'

    Write-Host '== vendor phase reads tag and skills from the pin (-SkillsRoot outside UmsRoot, no -Tag)'
    $target = Join-Path $fx.Root 'deploy-target'
    $targetShared = Join-Path $target 'shared'
    New-Item -ItemType Directory -Force $targetShared | Out-Null
    # The target starts as a t1 deployment: pin (beta pinned) plus a beta directory.
    Write-UmsVendorPin (Join-Path $targetShared 'VENDORED_FROM.md') 't1' $fx.T1Commit @('alpha', 'beta', 'subagent-driven-development') @() '2026-01-01'
    Write-FxFile (Join-Path $target 'beta\SKILL.md') "# stale beta`n"
    # gamma is Excluded by the new pin, yet the target still holds a copy of it.
    Write-FxFile (Join-Path $target 'gamma\SKILL.md') "# stale gamma`n"
    $res = Invoke-Revendor @('-SpRepo', $fx.SpRepo, '-UmsRoot', $fx.UmsRoot, '-SkillsRoot', $target, '-PinSource', $pinFile, '-NoOverlays')
    Assert-Eq $res.Exit 0 'vendor into a foreign SkillsRoot succeeds'
    Assert-True (Test-Path (Join-Path $target 'alpha\SKILL.md')) 'alpha vendored'
    Assert-True (Test-Path (Join-Path $target 'subagent-driven-development\scripts\sdd-workspace')) 'subagent-driven-development vendored'
    Assert-True (-not (Test-Path (Join-Path $target 'beta'))) 'beta (left the pin) is removed from the target'
    Assert-True (-not (Test-Path (Join-Path $target 'gamma'))) 'gamma (excluded by the pin) is deleted from the target'
    Assert-Match $res.Out "Removing skill 'beta'" 'console output reports the removal of beta'
    Assert-Match $res.Out "Removing skill 'gamma' \(excluded by the pin\)" 'console output reports the removal of excluded gamma'
    $targetPin = Read-UmsVendorPin (Join-Path $targetShared 'VENDORED_FROM.md')
    Assert-Eq $targetPin.Tag 't2' 'target pin: Tag t2'
    Assert-Eq $targetPin.Commit $pin2.Commit 'target pin: commit of t2'
    Assert-Eq ($targetPin.Skills -join ',') 'alpha,subagent-driven-development' 'target pin: Skills'
    Assert-Eq ($targetPin.Excluded -join ',') 'gamma' 'target pin: Excluded'
    Assert-Match (Get-Content -LiteralPath (Join-Path $targetShared 'VENDORED_FROM.md') -Raw) '(?m)^- Vendored on top of repo state: unknown ' 'target outside git: date is unknown'
    $alphaRaw = [IO.File]::ReadAllText((Join-Path $target 'alpha\SKILL.md'))
    Assert-True (-not $alphaRaw.Contains("`r")) 'CRLF in a vendored file is normalized to LF'
    $wsRaw = [IO.File]::ReadAllText((Join-Path $target 'subagent-driven-development\scripts\sdd-workspace'))
    Assert-True (-not $wsRaw.Contains("`r")) 'bash script stays LF'
    Assert-True (-not (Test-Path (Join-Path $fx.SkillsRoot 'alpha'))) 'the fixture UmsRoot skills were not touched by a foreign-target run'

    Write-Host '== vendor phase in place (default SkillsRoot, -PinSource = the target pin)'
    # In place the previous pin already IS the new pin, so nothing "leaves the pin":
    # a hand-made beta directory stays. Excluded skills are still deleted.
    Write-FxFile (Join-Path $fx.SkillsRoot 'beta\SKILL.md') "# hand-made beta`n"
    Write-FxFile (Join-Path $fx.SkillsRoot 'gamma\SKILL.md') "# hand-made gamma`n"
    $res = Invoke-Revendor ($common + @('-NoOverlays'))
    Assert-Eq $res.Exit 0 'vendor with the default -PinSource (pin in SkillsRoot) succeeds'
    Assert-True (Test-Path (Join-Path $fx.SkillsRoot 'alpha\SKILL.md')) 'in place: alpha vendored'
    Assert-True (-not (Test-Path (Join-Path $fx.SkillsRoot 'gamma'))) 'in place: excluded gamma directory is deleted'
    Assert-True (Test-Path (Join-Path $fx.SkillsRoot 'beta\SKILL.md')) 'in place: removal by previous pin is not possible (documented), beta stays'
    Assert-Match (Get-Content -LiteralPath $pinFile -Raw) '(?m)^- Vendored on top of repo state: 20\d\d-\d\d-\d\d ' 'default target inside git: date from git'
    Remove-Item -Recurse -Force -LiteralPath (Join-Path $fx.SkillsRoot 'beta')

    Write-Host '== -VerifyOnly and -OverlaysOnly still work on the pinned set'
    $res = Invoke-Revendor ($common + @('-VerifyOnly'))
    Assert-Eq $res.Exit 0 '-VerifyOnly passes on the vendored target'
    $res = Invoke-Revendor ($common + @('-OverlaysOnly'))
    Assert-Eq $res.Exit 0 '-OverlaysOnly with no fragments passes'

    Write-Host '== a pinned skill missing in the tag is a failure'
    $badPin = Join-Path $fx.Root 'bad\VENDORED_FROM.md'
    Write-UmsVendorPin $badPin 't2' $pin2.Commit @('alpha', 'delta') @() '2026-01-01'
    $badTarget = Join-Path $fx.Root 'bad-target'
    $res = Invoke-Revendor @('-SpRepo', $fx.SpRepo, '-UmsRoot', $fx.UmsRoot, '-SkillsRoot', $badTarget, '-PinSource', $badPin, '-NoOverlays')
    Assert-True ($res.Exit -ne 0) 'pinned skill absent from the tag exits non-zero'
    Assert-Match $res.Out 'delta' 'output names the missing skill'

    Write-Host '== flag misuse'
    $res = Invoke-Revendor ($common + @('-Include', 'gamma', '-NoOverlays'))
    Assert-True ($res.Exit -ne 0) '-Include without -PinOnly is refused'
    $res = Invoke-Revendor ($common + @('-PinOnly', '-Tag', 'no-such-tag'))
    Assert-True ($res.Exit -ne 0) '-PinOnly with an unknown tag exits non-zero'
    $res = Invoke-Revendor ($common + @('-PinOnly'))
    Assert-True ($res.Exit -ne 0) '-PinOnly without -Tag is refused'
}
finally {
    Remove-RevendorFixture $fx
}

Complete-Tests
