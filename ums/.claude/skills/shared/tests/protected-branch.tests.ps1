#Requires -Version 7
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_assert.ps1')
. (Join-Path $PSScriptRoot '..\scripts\Test-UmsProtectedBranch.ps1')

Write-Host "== presna shoda"
$r = Test-UmsProtectedBranch 'develop' @('develop', 'main')
Assert-True $r.Matched 'develop odpovida vzoru develop'
Assert-True $r.Evaluated 'presna shoda je vyhodnotitelna'

Write-Host "== glob nad radou verzi"
$r = Test-UmsProtectedBranch 'Branches/5.37' @('Branches/*')
Assert-True $r.Matched 'Branches/5.37 odpovida vzoru Branches/*'

Write-Host "== neshoda"
$r = Test-UmsProtectedBranch 'Branches/5.37' @('release/*', 'develop')
Assert-True (-not $r.Matched) 'Branches/5.37 neodpovida vzorum release/* ani develop'
Assert-True $r.Evaluated 'neshoda platnych vzoru je vyhodnotitelna'

Write-Host "== vadny vzor: neshoda, ale NEvyhodnoceno"
$r = Test-UmsProtectedBranch 'Branches/5.37' @('Maint/[0-9')
Assert-True (-not $r.Matched) 'vadny vzor nesmi tvrdit shodu'
Assert-True (-not $r.Evaluated) 'vadny vzor hlasi nevyhodnoceno'
Assert-Eq (@($r.BadPatterns).Count) 1 'vadny vzor je vyjmenovan'
Assert-Eq (@($r.BadPatterns)[0]) 'Maint/[0-9' 'BadPatterns nese presne ten vzor'

Write-Host "== shoda vyhrava nad vadnym vzorem"
$r = Test-UmsProtectedBranch 'Branches/5.37' @('Branches/*', 'Maint/[0-9')
Assert-True $r.Matched 'nalezena shoda je dukaz ochrany bez ohledu na dalsi vzory'

Write-Host "== prazdny a nesmyslny vstup"
$r = Test-UmsProtectedBranch 'develop' @()
Assert-True (-not $r.Matched) 'prazdny seznam vzoru nechrani nic'
Assert-True $r.Evaluated 'prazdny seznam je vyhodnotitelny'
$r = Test-UmsProtectedBranch '' @('develop')
Assert-True (-not $r.Matched) 'prazdne jmeno vetve neodpovida nicemu'
$r = Test-UmsProtectedBranch 'develop' @('', '   ', 'develop')
Assert-True $r.Matched 'prazdne vzory se preskoci, platny vzor rozhodne'
Assert-True $r.Evaluated 'preskoceny prazdny vzor neni vadny vzor'

Complete-Tests
