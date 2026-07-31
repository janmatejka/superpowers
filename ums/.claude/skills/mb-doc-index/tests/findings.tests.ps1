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
Complete-Tests
