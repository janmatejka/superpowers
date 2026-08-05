Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '_assert.ps1')
. (Join-Path $PSScriptRoot 'new-fixture-repo.ps1')

# ---------------------------------------------------------------------------
# -SinceDays means "the BRANCH's tip is this recent", not "commits are this
# recent". The suite is written against that meaning: the old commit-date
# filter dropped a live branch whose design document was committed long ago,
# which is why its default had to be inflated to 120 days.
# ---------------------------------------------------------------------------

$fx = New-FixtureRepo
$json = Join-Path $fx.Work 'index.json'
$r = Invoke-Index @('-RepoPath', $fx.Work, '-BaseRef', 'origin/develop', '-NoFetch', '-Json', $json)

Assert-Eq $r.Code 0 'čistý běh bez kolizí končí kódem 0'
Assert-Match $r.Out 'ums_1_alfa' 'tabulka obsahuje aktivní slug z cizí větve'
Assert-Match $r.Out 'origin/feature/ums-1-alfa' 'tabulka uvádí větev, která slug drží'
Assert-NotMatch $r.Out 'design_fixture' 'cesty pod tests/fixtures/ se vylučují'
Assert-NotMatch $r.Out 'design_hotovo' 'dokončené dokumenty z báze nejsou v tabulce'

$idx = Get-Content -LiteralPath $json -Raw | ConvertFrom-Json
$alfa = @($idx.entries | Where-Object { $_.slug -eq 'ums_1_alfa' })[0]
Assert-Eq $alfa.phase 'active' 'fáze se určuje z cesty'
Assert-Eq $alfa.jira 'UMS-1' 'tiket se čte z hlavičky dokumentu'
Assert-True ($alfa.commit.Length -ge 7) 'záznam nese commit SHA'
Assert-Eq $idx.base 'origin/develop' 'JSON nese použitou bázi'

$hotovoCount = @($idx.entries | Where-Object { $_.slug -eq 'hotovo' -and $_.phase -eq 'completed' }).Count
Assert-True ($hotovoCount -gt 0) 'dokončené dokumenty JSOU v entries, jen se netisknou v tabulce'

# --- case 1: branch whose TIP is older than the window is not in the table ---
Assert-NotMatch $r.Out 'ums_5_stare' 'větev, jejíž tip je starší než -SinceDays, v tabulce není'
$stare = Invoke-Index @('-RepoPath', $fx.Work, '-BaseRef', 'origin/develop', '-NoFetch', '-SinceDays', '1000')
Assert-Match $stare.Out 'ums_5_stare' 'vyšší -SinceDays větev se starým tipem zahrne'

# --- case 2: fresh tip, ancient design commit = the fixed false negative -----
# Under the old commit-date filter this branch vanished from the index even
# though it is the most alive thing in the fixture.
Assert-Match $r.Out 'ums_10_obnovena' 'větev s čerstvým tipem je v tabulce, i když její návrh vznikl dávno'
$obnAll = @($idx.entries | Where-Object { $_.slug -eq 'ums_10_obnovena' })
Assert-True (@($obnAll).Count -gt 0) 'záznam větve s čerstvým tipem a starým návrhem je v indexu'
if (@($obnAll).Count -gt 0) {
    $obn = $obnAll[0]
    $obnDate = [datetimeoffset]::Parse([string]$obn.date)
    Assert-True ($obnDate -lt [datetimeoffset]::UtcNow.AddDays(-300)) `
        'nalezený commit návrhu je opravdu starší než okno (traverzace přeživších větví není datově omezená)'
    Assert-True ([int64]$obn.activity -gt [DateTimeOffset]::UtcNow.AddDays(-30).ToUnixTimeSeconds()) `
        'záznam nese aktivitu (datum tipu větve), ne datum svého commitu'
}

# --- refs now round-trip through PowerShell (for-each-ref -> log --stdin) ----
# A branch name with diacritics must survive that round trip; if the decode is
# not UTF-8, git answers "fatal: bad revision" and the run aborts with exit 1.
Assert-Match $r.Out 'ums_12_diakritika' 'větev se jménem s diakritikou se indexuje (UTF-8 round trip refů)'
Assert-Eq (@($idx.entries | Where-Object { $_.branch -eq 'origin/feature/ums-12-diakritika-ěšč' }).Count) 1 `
    'jméno větve s diakritikou se přenese do indexu nepoškozené'

# --- case 3: refs/remotes/origin/HEAD is a symref to the base ----------------
# It must be skipped, otherwise the base is indexed a second time under the
# branch name origin/HEAD.
Assert-Eq (@($idx.entries | Where-Object { $_.branch -eq 'origin/HEAD' }).Count) 0 `
    'symref origin/HEAD se neindexuje jako samostatná větev'
Assert-Eq (@($idx.entries | Where-Object { $_.slug -eq 'hotovo' }).Count) 1 `
    'obsah báze se přes symref origin/HEAD nezduplikuje'

# --- case 4: -BranchGlob is applied BEFORE the activity filter ---------------
$glob = Invoke-Index @('-RepoPath', $fx.Work, '-BaseRef', 'origin/develop', '-NoFetch',
    '-BranchGlob', 'origin/feature/ums-1-*', '-Json', ($json + '.glob'))
Assert-Match $glob.Out 'ums_1_alfa' '-BranchGlob propustí odpovídající větev'
Assert-NotMatch $glob.Out 'ums_2_beta' '-BranchGlob odfiltruje ostatní větve'
Assert-NotMatch $glob.Out 'ums_10_obnovena' 'čerstvá větev mimo -BranchGlob se nezapočítá'
$idxGlob = Get-Content -LiteralPath ($json + '.glob') -Raw | ConvertFrom-Json
$outside = @($idxGlob.entries | Where-Object {
    $_.branch -notin @('local', 'base') -and $_.branch -notlike 'origin/feature/ums-1-*' })
Assert-Eq (@($outside).Count) 0 'do indexu nevstoupí žádná vzdálená větev mimo -BranchGlob'

# --- case 5: a DORMANT branch reached through a commit it SHARES with a live ---
# branch must not enter the index. `feature/ums-13-ziva` is cut from
# `feature/ums-13-uspany-zdroj`'s design commit, so `branch -r --contains` on
# that one sha reports both — the dormant tip (400 days) and the live one
# (1 day). Stage 1's active set is the authority, and stage 2 intersects against
# it precisely so the dormant branch cannot ride in on the shared commit.
#
# Without that intersection the dormant entry is also created with NO activity
# stamp, and the display filter lets a missing stamp through unconditionally
# (`-not $_.activity`, which exists for the local/base pseudo-branches), so it
# prints no matter what -SinceDays says. Every other case in this suite stays
# green with that line deleted; this is the one that goes red.
Assert-Eq (@($idx.entries | Where-Object { $_.branch -eq 'origin/feature/ums-13-uspany-zdroj' }).Count) 0 `
    'uspaná větev se nedostane do indexu přes commit, který dělí se živou větví'
Assert-NotMatch $r.Out 'ums-13-uspany-zdroj' 'uspaná větev se netiskne ani do tabulky'
# Positive control, so the case cannot pass by indexing nothing at all: the LIVE
# child IS indexed, and it carries the shared design document.
Assert-Eq (@($idx.entries | Where-Object {
    $_.branch -eq 'origin/feature/ums-13-ziva' -and $_.slug -eq 'ums_13_zdedeny' }).Count) 1 `
    'živá větev s týmž (společným) commitem návrhu v indexu JE'
# The second half of the same guarantee: every remote entry has an activity
# stamp, because only branches from stage 1's map can produce one.
Assert-Eq (@($idx.entries | Where-Object { $_.branch -like 'origin/*' -and -not $_.activity }).Count) 0 `
    'každý záznam vzdálené větve nese stopu aktivity (jinak by ho okno -SinceDays nemohlo filtrovat)'

# ---------------------------------------------------------------------------
# The 'local' pseudo-branch is enumerated from git (one `ls-files` call with a
# pathspec) rather than by a recursive directory walk, because this script is
# on the hot path of discovery/mb-state/elaboration in a very large monorepo.
# What must stay identical: an UNTRACKED but present document is still local
# work in flight. What deliberately changed: a gitignored document is no
# longer indexed (nobody can pull it across branches anyway).
# ---------------------------------------------------------------------------
$untracked = Join-Path $fx.Work 'memory-bank/proposals/active/design_nezapsany.md'
New-Item -ItemType Directory -Force -Path (Split-Path $untracked) | Out-Null
Set-Content -LiteralPath $untracked -Encoding UTF8 -Value @('# Návrh: nezapsany', '', '- **Jira:** UMS-8')

$ignored = Join-Path $fx.Work 'memory-bank/proposals/active/design_ignorovany.md'
Set-Content -LiteralPath $ignored -Encoding UTF8 -Value @('# Návrh: ignorovany', '', '- **Jira:** UMS-88')
Set-Content -LiteralPath (Join-Path $fx.Work '.gitignore') -Encoding UTF8 -Value 'design_ignorovany.md'

# tracked in HEAD but deleted from the working tree — 'local' means working
# tree, so it must not be reported as local work in flight
Remove-Item -LiteralPath (Join-Path $fx.Work 'memory-bank/proposals/next/design_ums_6_fronta.md')

$json2 = Join-Path ([IO.Path]::GetTempPath()) ("mbidx-local-" + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.json')
$loc = Invoke-Index @('-RepoPath', $fx.Work, '-BaseRef', 'origin/develop', '-NoFetch', '-Json', $json2)
Assert-Eq $loc.Code 0 'lokální sken přes git končí kódem 0'
$idx2 = Get-Content -LiteralPath $json2 -Raw | ConvertFrom-Json
$localOf = { param($slug) @($idx2.entries | Where-Object { $_.branch -eq 'local' -and $_.slug -eq $slug }).Count }
Assert-True ((& $localOf 'nezapsany') -gt 0) 'necommitnutý (untracked) dokument je i nadále v indexu jako lokální práce'
Assert-Eq (& $localOf 'ignorovany') 0 'gitignorovaný dokument se neindexuje (vědomá změna oproti adresářovému walku)'
Assert-Eq (& $localOf 'ums_6_fronta') 0 'trackovaný, ale z working tree smazaný dokument není lokální práce'
Remove-Item -LiteralPath $json2

Remove-Item -Recurse -Force (Split-Path $fx.Work)

# ---------------------------------------------------------------------------
# case 5 + 6: the base ref comes from memory-bank/ums-repo.json (contract:
# "Repository Configuration"). An explicit -BaseRef always wins; the empty
# default means "take it from the config", whose own fallback is origin/develop.
# The loader reads the FILE, so the fixture's working-tree copy is what counts.
# ---------------------------------------------------------------------------
$fx3 = New-FixtureRepo
$cfgPath = Join-Path $fx3.Work 'memory-bank/ums-repo.json'
Invoke-Git $fx3.Work @('push', 'origin', 'develop:baseline') | Out-Null
Invoke-Git $fx3.Work @('fetch', 'origin') | Out-Null
Set-Content -LiteralPath $cfgPath -Encoding UTF8 -Value '{ "baseRef": "origin/baseline" }'

$json3 = Join-Path ([IO.Path]::GetTempPath()) ("mbidx-cfg-" + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.json')
$cfgRun = Invoke-Index @('-RepoPath', $fx3.Work, '-NoFetch', '-Json', $json3)
Assert-Eq $cfgRun.Code 0 'běh bez -BaseRef s bází z konfigurace končí kódem 0'
$idx3 = Get-Content -LiteralPath $json3 -Raw | ConvertFrom-Json
Assert-Eq $idx3.base 'origin/baseline' 'bez -BaseRef se báze vezme z memory-bank/ums-repo.json'
Assert-Match $cfgRun.Out 'ums_1_alfa' 'báze z konfigurace opravdu funguje jako báze traverzace'

$explicit = Invoke-Index @('-RepoPath', $fx3.Work, '-NoFetch', '-BaseRef', 'origin/develop', '-Json', $json3)
Assert-Eq $explicit.Code 0 'explicitní -BaseRef proti konfiguraci končí kódem 0'
$idx3b = Get-Content -LiteralPath $json3 -Raw | ConvertFrom-Json
Assert-Eq $idx3b.base 'origin/develop' 'explicitní -BaseRef má přednost před konfigurací'

Remove-Item -LiteralPath $cfgPath
$noCfg = Invoke-Index @('-RepoPath', $fx3.Work, '-NoFetch', '-Json', $json3)
Assert-Eq $noCfg.Code 0 'chybějící konfigurace degraduje na vestavěný default, nepadá'
$idx3c = Get-Content -LiteralPath $json3 -Raw | ConvertFrom-Json
Assert-Eq $idx3c.base 'origin/develop' 'bez konfigurace zůstává báze origin/develop'
Remove-Item -LiteralPath $json3

# case 6: a base ref from the config that does not exist is a hard stop
Set-Content -LiteralPath $cfgPath -Encoding UTF8 -Value '{ "baseRef": "origin/neexistuje" }'
$badBase = Invoke-Index @('-RepoPath', $fx3.Work, '-NoFetch')
Assert-Eq $badBase.Code 1 'neexistující báze z konfigurace končí kódem 1'
Assert-Match $badBase.Out 'Base ref not found: origin/neexistuje' 'hláška uvádí bázi, kterou skript opravdu použil'

Remove-Item -Recurse -Force (Split-Path $fx3.Work)

# A genuine git-level failure in the traversal must surface as exit 1, not a
# silent "clean, nothing found" empty table. Reproduced offline/deterministically
# by pointing an origin remote-tracking ref at a well-formed but nonexistent
# SHA-1: "git rev-parse --verify --quiet <BaseRef>" (a different, valid ref)
# still succeeds, but the ref enumeration must read EVERY ref under
# refs/remotes/origin/, including the broken one, and fails there
# ("fatal: missing object …" from for-each-ref) — confirmed manually before
# writing this assertion.
$fx2 = New-FixtureRepo
$brokenRef = Join-Path $fx2.Work '.git\refs\remotes\origin\broken'
New-Item -ItemType Directory -Force -Path (Split-Path $brokenRef) | Out-Null
Set-Content -LiteralPath $brokenRef -Encoding ascii -Value '0123456789abcdef0123456789abcdef01234567'
$broken = Invoke-Index @('-RepoPath', $fx2.Work, '-BaseRef', 'origin/develop', '-NoFetch')
Assert-Eq $broken.Code 1 'poškozená vzdálená větev shodí enumeraci na exit 1, ne na tichou prázdnou tabulku'
Assert-NotMatch $broken.Out 'Index dokumentů' 'při selhání enumerace se tabulka vůbec netiskne'

Remove-Item -Recurse -Force (Split-Path $fx2.Work)
Complete-Tests
