#Requires -Version 7
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_assert.ps1')
. (Join-Path $PSScriptRoot '..\scripts\Test-UmsIntegrationBase.ps1')

# Config shape is the one Get-UmsRepoConfig returns; only the two fields the
# function reads are set, so a case cannot pass on an unrelated field.
function New-Cfg([string[]] $Protected, [string] $Epic) {
    return @{ ProtectedBranches = $Protected; EpicBranchPattern = $Epic }
}

Write-Host "== chranena vetev je protected"
$r = Test-UmsIntegrationBase 'develop' (New-Cfg @('develop', 'main') 'epic/*')
Assert-True ($r.Allowed -eq $true) 'develop (chranena) je povolena baze'
Assert-Eq $r.Kind 'protected' 'develop ma Kind=protected'
Assert-Eq (@($r.BadPatterns).Count) 0 'bez vadneho vzoru je BadPatterns prazdne'

Write-Host "== linie epiku bez ochrany je epic-line"
$r = Test-UmsIntegrationBase 'epic/UMS-1' (New-Cfg @('develop') 'epic/*')
Assert-True ($r.Allowed -eq $true) 'epic/UMS-1 nechranena je povolena baze'
Assert-Eq $r.Kind 'epic-line' 'epic/UMS-1 ma Kind=epic-line'

Write-Host "== chranena vetev vyhrava nad linii epiku"
$r = Test-UmsIntegrationBase 'epic/UMS-1' (New-Cfg @('develop', 'epic/*') 'epic/*')
Assert-True ($r.Allowed -eq $true) 'epic/UMS-1 chranena je povolena'
Assert-Eq $r.Kind 'protected' 'chranena vetev odpovidajici i vzoru epiku ma Kind=protected'

Write-Host "== prazdny vzor epiku = zadna linie epiku"
$r = Test-UmsIntegrationBase 'epic/UMS-1' (New-Cfg @('develop') '')
Assert-True ($r.Allowed -eq $false) 'epic/UMS-1 s prazdnym vzorem neni baze'
Assert-Eq $r.Kind 'none' 'prazdny vzor -> Kind=none'

Write-Host "== jina nechranena vetev neni baze"
$r = Test-UmsIntegrationBase 'feature/x' (New-Cfg @('develop') 'epic/*')
Assert-True ($r.Allowed -eq $false) 'feature/x neni baze'
Assert-Eq $r.Kind 'none' 'feature/x ma Kind=none'

Write-Host "== vzor epic/* vyzaduje lomitko"
$r = Test-UmsIntegrationBase 'epic' (New-Cfg @('develop') 'epic/*')
Assert-Eq $r.Kind 'none' 'holy epic bez lomitka vzoru epic/* neodpovida'

Write-Host "== vadny vzor epiku: neshoda a BadPatterns, zadna vyjimka"
$r = Test-UmsIntegrationBase 'epic/UMS-1' (New-Cfg @('develop') 'epic/[')
Assert-True ($r.Allowed -eq $false) 'vadny vzor epic/[ nic nepusti'
Assert-Eq $r.Kind 'none' 'vadny vzor -> Kind=none'
Assert-True (@($r.BadPatterns) -contains 'epic/[') 'vadny vzor je vypsan v BadPatterns'

Write-Host "== vadny chraneny vzor: neshoda, ale linie epiku dal funguje"
$r = Test-UmsIntegrationBase 'epic/UMS-1' (New-Cfg @('Maint/[0-9') 'epic/*')
Assert-Eq $r.Kind 'epic-line' 'vadny chraneny vzor nezablokuje shodu se vzorem epiku'
Assert-True (@($r.BadPatterns) -contains 'Maint/[0-9') 'vadny chraneny vzor je v BadPatterns'

Write-Host "== prazdne jmeno vetve neni baze"
$r = Test-UmsIntegrationBase '' (New-Cfg @('develop') '*')
Assert-True ($r.Allowed -eq $false) 'prazdne jmeno neni baze ani pri vzoru *'
Assert-Eq $r.Kind 'none' 'prazdne jmeno -> Kind=none'

Complete-Tests
