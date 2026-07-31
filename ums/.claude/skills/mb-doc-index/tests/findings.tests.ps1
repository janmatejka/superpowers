Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '_assert.ps1')
. (Join-Path $PSScriptRoot 'new-fixture-repo.ps1')

$fx = New-FixtureRepo

# 1) foreign active work on ANOTHER ticket = information only, exit 0
$r = Invoke-Index @('-RepoPath', $fx.Work, '-BaseRef', 'origin/develop', '-NoFetch')
Assert-Eq $r.Code 0 'cizí aktivní práce jiného tiketu běh nezastaví'
Assert-Match $r.Out 'CIZÍ AKTIVNÍ PRÁCE' 'cizí aktivní práce se vypíše jako informace'
Assert-Match $r.Out 'DRAFT NA VÍCE VĚTVÍCH.*ums_2_beta' 'duplicitní draft je varování'
Assert-Match $r.Out 'FRONTA I DOKONČENO.*ums_3_gama' 'obživlá fronta je varování'

# 1b) NEGATIVE: a next/ document already sitting unmodified in the base
# commit shows up as BOTH 'base' and 'local' (every branch descends from it)
# but that is ONE actor, not a duplicate draft — must never fire a warning.
Assert-Match $r.Out 'ums_6_fronta' 'fronta shodná se základnou (base+local) se v tabulce zobrazí'
Assert-NotMatch $r.Out 'DRAFT NA VÍCE VĚTVÍCH.*ums_6_fronta' 'shoda base+local není falešný duplicitní draft'

# 2) the SAME slug active locally and on a foreign branch = collision, exit 2
$local = Join-Path $fx.Work 'memory-bank/proposals/active/design_ums_1_alfa.md'
New-Item -ItemType Directory -Force -Path (Split-Path $local) | Out-Null
Set-Content -LiteralPath $local -Encoding UTF8 -Value @('# Návrh: alfa', '', '- **Jira:** UMS-1')
$c = Invoke-Index @('-RepoPath', $fx.Work, '-BaseRef', 'origin/develop', '-NoFetch')
Assert-Eq $c.Code 2 'stejný slug aktivní lokálně i na cizí větvi = exit 2'
Assert-Match $c.Out 'KOLIZE AKTIVNÍ PRÁCE' 'kolize se hlásí jako CHYBA'
Assert-Match $c.Out 'origin/feature/ums-1-alfa' 'hlášení kolize nese větev'
Assert-Match $c.Out '\d{4}-\d{2}-\d{2}' 'hlášení kolize nese datum posledního commitu'

# 3) the same TICKET under a different slug is a collision too
Remove-Item -LiteralPath $local
$other = Join-Path $fx.Work 'memory-bank/proposals/active/design_ums_1_jinak.md'
Set-Content -LiteralPath $other -Encoding UTF8 -Value @('# Návrh: jinak', '', '- **Jira:** UMS-1')
$t = Invoke-Index @('-RepoPath', $fx.Work, '-BaseRef', 'origin/develop', '-NoFetch')
Assert-Eq $t.Code 2 'tentýž tiket pod jiným slugem je také kolize'

Remove-Item -Recurse -Force (Split-Path $fx.Work)

# 4) NEGATIVE: the actor's own already-pushed branch must never self-collide.
# Ordinary git hygiene — push your own active work to your own origin
# feature branch — must not be indistinguishable from a genuine two-actor
# collision, and must not even be reported as someone else's parallel work.
$fx2 = New-FixtureRepo
Invoke-Git $fx2.Work @('checkout', '-b', 'feature/own-work', 'develop') | Out-Null
Add-Doc $fx2.Work 'memory-bank/proposals/active/design_ums_9_vlastni.md' 'UMS-9'
Invoke-Git $fx2.Work @('commit', '-m', 'own active work') | Out-Null
Invoke-Git $fx2.Work @('push', '-u', 'origin', 'feature/own-work') | Out-Null
$own = Invoke-Index @('-RepoPath', $fx2.Work, '-BaseRef', 'origin/develop', '-NoFetch')
Assert-Eq $own.Code 0 'vlastní už pushnutá větev se sama se sebou nesrazí'
Assert-NotMatch $own.Out 'KOLIZE AKTIVNÍ PRÁCE' 'vlastní práce se nehlásí jako kolize se sebou samou'
Assert-NotMatch $own.Out 'CIZÍ AKTIVNÍ PRÁCE.*ums_9_vlastni' 'vlastní práce se nehlásí ani jako cizí'

Remove-Item -Recurse -Force (Split-Path $fx2.Work)
Complete-Tests
