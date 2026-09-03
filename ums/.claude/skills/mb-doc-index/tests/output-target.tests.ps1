# -Json output target: the run must not do its whole job and THEN fail to write.
#
# Measured defect (UMS-3495): in a fresh worktree `.superpowers/` does not exist
# yet, and `-Json <missing dir>/index.json` printed the complete, normal-looking
# report on stdout and only then died on Set-Content — exit 1, no JSON file, and
# a caller reading stdout saw a healthy run. For a fail-closed collision check
# that is the difference between "no collision" and "the check never completed".
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '_assert.ps1')
. (Join-Path $PSScriptRoot 'new-fixture-repo.ps1')

$fx = New-FixtureRepo

# --- 1) NEGATIVE: the -Json parent directory does not exist ------------------
$missingDir = Join-Path $fx.Work 'nonexistent-scratch'
$badJson = Join-Path $missingDir 'index.json'
Assert-True (-not (Test-Path -LiteralPath $missingDir)) 'předpoklad: cílový adresář opravdu neexistuje'

$bad = Invoke-Index @('-RepoPath', $fx.Work, '-BaseRef', 'origin/develop', '-NoFetch', '-Json', $badJson)

Assert-True ($bad.Code -ne 0) 'chybějící cílový adresář -Json končí nenulově'
Assert-Match $bad.Out 'nonexistent-scratch' 'hláška jmenuje adresář, který chybí'
# The guard has to fire BEFORE the work, not after it: a report that is printed
# in full and then dies is exactly what made the defect invisible, and on the
# target monorepo the wasted work is minutes, not milliseconds.
Assert-NotMatch $bad.Out 'Index dokumentů' 'zastaví se dřív, než vypíše report — ne až po něm'
Assert-True (-not (Test-Path -LiteralPath $badJson)) 'žádný JSON soubor nevznikne'

# --- 2) POSITIVE CONTROL: existing directory still works --------------------
# Without this the suite would go green on a script that refuses every -Json.
$goodDir = Join-Path $fx.Work 'scratch'
New-Item -ItemType Directory -Path $goodDir -Force | Out-Null
$goodJson = Join-Path $goodDir 'index.json'

$good = Invoke-Index @('-RepoPath', $fx.Work, '-BaseRef', 'origin/develop', '-NoFetch', '-Json', $goodJson)

Assert-Eq $good.Code 0 'existující cílový adresář -Json běh nezastaví'
Assert-Match $good.Out 'Index dokumentů' 'report se na úspěšné cestě vypíše'
Assert-True (Test-Path -LiteralPath $goodJson) 'JSON soubor vznikne'
$idx = Get-Content -LiteralPath $goodJson -Raw | ConvertFrom-Json
Assert-True ($idx -is [System.Management.Automation.PSCustomObject]) 'JSON je objekt, ne skalár ani null'
Assert-True (@(@($idx.PSObject.Properties) | ForEach-Object { $_.Name }) -contains 'entries') 'JSON nese klíč entries'

# --- 3) POSITIVE CONTROL: no -Json at all is untouched ----------------------
$none = Invoke-Index @('-RepoPath', $fx.Work, '-BaseRef', 'origin/develop', '-NoFetch')
Assert-Eq $none.Code 0 'běh bez -Json se guardem nedotkne'
Assert-Match $none.Out 'Index dokumentů' 'běh bez -Json report vypíše'

Complete-Tests
