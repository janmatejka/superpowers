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

# A genuine git-level failure in the traversal must surface as exit 1, not a
# silent "clean, nothing found" empty table. Reproduced offline/deterministically
# by pointing an origin remote-tracking ref at a well-formed but nonexistent
# SHA-1: "git rev-parse --verify --quiet <BaseRef>" (a different, valid ref)
# still succeeds, but "git log --remotes=origin --not <BaseRef> ..." must walk
# ALL refs under refs/remotes/, including the broken one, and fails with
# "fatal: bad object" — confirmed manually before writing this assertion.
$fx2 = New-FixtureRepo
$brokenRef = Join-Path $fx2.Work '.git\refs\remotes\origin\broken'
New-Item -ItemType Directory -Force -Path (Split-Path $brokenRef) | Out-Null
Set-Content -LiteralPath $brokenRef -Encoding ascii -Value '0123456789abcdef0123456789abcdef01234567'
$broken = Invoke-Index @('-RepoPath', $fx2.Work, '-BaseRef', 'origin/develop', '-NoFetch')
Assert-Eq $broken.Code 1 'poškozená vzdálená větev shodí traverzaci na exit 1, ne na tichou prázdnou tabulku'
Assert-NotMatch $broken.Out 'Index dokumentů' 'při selhání traverzace se tabulka vůbec netiskne'

Remove-Item -Recurse -Force (Split-Path $fx2.Work)
Complete-Tests
