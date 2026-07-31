Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '_assert.ps1')
. (Join-Path $PSScriptRoot 'new-fixture-repo.ps1')

$fx = New-FixtureRepo
$json = Join-Path $fx.Work 'index.json'
$r = Invoke-Index @('-RepoPath', $fx.Work, '-BaseRef', 'origin/develop', '-NoFetch', '-Json', $json)

Assert-Eq $r.Code 0 'čistý běh bez kolizí končí kódem 0'
Assert-Match $r.Out 'ums_1_alfa' 'tabulka obsahuje aktivní slug z cizí větve'
Assert-Match $r.Out 'origin/feature/ums-1-alfa' 'tabulka uvádí větev, která slug drží'
Assert-NotMatch $r.Out 'design_fixture' 'cesty pod tests/fixtures/ se vylučují'
Assert-NotMatch $r.Out 'ums_5_stare' 'commit starší než -SinceDays se nezapočítá'
Assert-NotMatch $r.Out 'design_hotovo' 'dokončené dokumenty z báze nejsou v tabulce'

$idx = Get-Content -LiteralPath $json -Raw | ConvertFrom-Json
$alfa = @($idx.entries | Where-Object { $_.slug -eq 'ums_1_alfa' })[0]
Assert-Eq $alfa.phase 'active' 'fáze se určuje z cesty'
Assert-Eq $alfa.jira 'UMS-1' 'tiket se čte z hlavičky dokumentu'
Assert-True ($alfa.commit.Length -ge 7) 'záznam nese commit SHA'
Assert-Eq $idx.base 'origin/develop' 'JSON nese použitou bázi'

$stare = Invoke-Index @('-RepoPath', $fx.Work, '-BaseRef', 'origin/develop', '-NoFetch', '-SinceDays', '1000')
Assert-Match $stare.Out 'ums_5_stare' 'vyšší -SinceDays starou větev zahrne'

$glob = Invoke-Index @('-RepoPath', $fx.Work, '-BaseRef', 'origin/develop', '-NoFetch', '-BranchGlob', 'origin/feature/ums-1-*')
Assert-Match $glob.Out 'ums_1_alfa' '-BranchGlob propustí odpovídající větev'
Assert-NotMatch $glob.Out 'ums_2_beta' '-BranchGlob odfiltruje ostatní větve'

Remove-Item -Recurse -Force (Split-Path $fx.Work)
Complete-Tests
