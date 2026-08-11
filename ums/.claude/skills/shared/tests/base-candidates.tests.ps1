#Requires -Version 7
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_assert.ps1')
. (Join-Path $PSScriptRoot '..\scripts\Get-UmsBaseCandidates.ps1')

function Invoke-Git([string] $Root, [string[]] $GitArgs) {
    & git -C $Root @GitArgs 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "git $($GitArgs -join ' ') selhalo v $Root" }
}

$tmp = Join-Path ([IO.Path]::GetTempPath()) ("ums-base-" + [Guid]::NewGuid().ToString('N'))
$bare = Join-Path $tmp 'origin.git'
$work = Join-Path $tmp 'work'
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
& git init --bare --initial-branch=develop $bare | Out-Null
& git init --initial-branch=develop $work | Out-Null
Invoke-Git $work @('remote', 'add', 'origin', $bare)
New-Item -ItemType Directory -Force -Path (Join-Path $work 'memory-bank') | Out-Null
Set-Content -LiteralPath (Join-Path $work 'memory-bank/ums-repo.json') -Encoding UTF8 -Value @'
{ "baseRef": "origin/develop", "protectedBranches": ["develop", "main", "Branches/*"] }
'@
Invoke-Git $work @('add', '-A')
Invoke-Git $work @('-c', 'user.email=t@t', '-c', 'user.name=t', 'commit', '-m', 'init')
foreach ($b in @('main', 'Branches/5.36', 'Branches/5.37', 'feature/UMS-1-neco')) {
    Invoke-Git $work @('branch', $b)
}
Invoke-Git $work @('push', '--no-verify', 'origin', '--all')
# refs/remotes/origin/HEAD is normally created by `git clone`, not by plain
# `push` from a hand-built fixture - without this, the assertion below that
# the symref never becomes a candidate would be vacuous (it would pass even
# if Get-UmsBaseCandidates did not filter it at all).
Invoke-Git $work @('fetch', 'origin')
Invoke-Git $work @('remote', 'set-head', 'origin', '-a')

Write-Host "== kandidati jsou jen chranene vetve existujici na origin"
$c = Get-UmsBaseCandidates $work 'develop'
$refs = @($c | ForEach-Object { $_.Ref })
Assert-True ($refs -contains 'origin/develop') 'develop je kandidat'
Assert-True ($refs -contains 'origin/Branches/5.37') 'Branches/5.37 je kandidat'
Assert-True ($refs -contains 'origin/main') 'main je kandidat'
Assert-True (-not ($refs -contains 'origin/feature/UMS-1-neco')) 'pracovni vetev neni kandidat'
Assert-True (-not ($refs -contains 'origin')) 'symref origin/HEAD se nestal kandidatem'

# Select-Object rather than [n] everywhere below: under the mutation this suite's
# own negativity check prescribes (lstrip=3 swapped for refname:short) no name
# matches protectedBranches any more, so the candidate list is EMPTY - and
# indexing it would abort the whole run with IndexOutOfRangeException instead of
# reporting FAILED assertions, skipping every assertion after the first index.
Write-Host "== vychozi baze je prvni a je oznacena"
Assert-Eq (@($c) | Select-Object -First 1 -ExpandProperty Ref) 'origin/develop' 'vychozi baze je prvni v poradi'
# `-eq $true` is not decoration: Assert-True's parameter is typed [bool], and an
# EMPTY pipeline binds as "" - a binding error that aborts the run exactly like
# the index it replaced. The comparison turns "nothing" into a plain $false.
Assert-True ((@($c) | Select-Object -First 1 -ExpandProperty IsDefault) -eq $true) 'vychozi baze nese IsDefault'

Write-Host "== aktualni vetev je oznacena a razena hned za vychozi"
$c = Get-UmsBaseCandidates $work 'Branches/5.37'
$cur = @($c | Where-Object { $_.IsCurrent })
Assert-Eq (@($cur).Count) 1 'prave jedna vetev je oznacena jako aktualni'
Assert-Eq (@($cur) | Select-Object -First 1 -ExpandProperty Ref) 'origin/Branches/5.37' 'aktualni vetev je Branches/5.37'
Assert-Eq (@($c) | Select-Object -Skip 1 -First 1 -ExpandProperty Ref) 'origin/Branches/5.37' 'aktualni vetev nasleduje hned za vychozi bazi'

Write-Host "== Branch je Ref bez remote prefixu, vcetne lomitka ve jmene"
$b = @($c | Where-Object { $_.Ref -eq 'origin/Branches/5.37' }) | Select-Object -First 1 -ExpandProperty Branch
Assert-Eq $b 'Branches/5.37' 'strip odebira jen remote a jedno lomitko'

Write-Host "== aktualni vetev mimo chranene se kandidatem nestava"
$c = Get-UmsBaseCandidates $work 'feature/UMS-1-neco'
Assert-True (-not (@($c | ForEach-Object { $_.Ref }) -contains 'origin/feature/UMS-1-neco')) `
    'nechranena aktualni vetev neni nabidnuta jako baze'

Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
Complete-Tests
