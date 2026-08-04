#Requires -Version 7
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_assert.ps1')
. (Join-Path $PSScriptRoot '..\scripts\Get-UmsRepoConfig.ps1')

$tmp = Join-Path ([IO.Path]::GetTempPath()) ("ums-cfg-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path (Join-Path $tmp 'memory-bank') | Out-Null

Write-Host "== chybejici soubor -> defaulty"
$c = Get-UmsRepoConfig $tmp
Assert-Eq $c.Source 'default' 'chybejici soubor hlasi Source=default'
Assert-Eq $c.BaseRef 'origin/develop' 'default baseRef'
Assert-True (@($c.ProtectedBranches).Count -eq 4) 'default protectedBranches ma 4 vzory'
Assert-True (@($c.SharedRoots).Count -eq 0) 'default sharedRoots je prazdny'

Write-Host "== plny soubor"
@'
{
  "baseRef": "origin/ums-memory-bank",
  "protectedBranches": ["develop", "Branches/*"],
  "ticketPattern": "^UMS-[0-9]+",
  "projectMarkers": ["*.csproj"],
  "sharedRoots": ["Common/"]
}
'@ | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $tmp 'memory-bank\ums-repo.json')
$c = Get-UmsRepoConfig $tmp
Assert-Eq $c.Source 'file' 'existujici soubor hlasi Source=file'
Assert-Eq $c.BaseRef 'origin/ums-memory-bank' 'baseRef ze souboru'
Assert-Eq (@($c.ProtectedBranches)[1]) 'Branches/*' 'protectedBranches ze souboru'
Assert-Eq (@($c.SharedRoots).Count) 1 'sharedRoots ma jeden prvek a je pole'

Write-Host "== jednoprvkove pole zustava polem"
'{ "protectedBranches": ["develop"] }' | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $tmp 'memory-bank\ums-repo.json')
$c = Get-UmsRepoConfig $tmp
Assert-Eq (@($c.ProtectedBranches).Count) 1 'jednoprvkove pole ma Count 1'

Write-Host "== chybejici klic bere svuj default, ne cely default"
'{ "baseRef": "origin/trunk" }' | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $tmp 'memory-bank\ums-repo.json')
$c = Get-UmsRepoConfig $tmp
Assert-Eq $c.BaseRef 'origin/trunk' 'baseRef ze souboru'
Assert-True (@($c.ProtectedBranches).Count -eq 4) 'chybejici protectedBranches padne na default'

Write-Host "== rozbity JSON -> defaulty, ne vyjimka"
'{ not json' | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $tmp 'memory-bank\ums-repo.json')
$c = Get-UmsRepoConfig $tmp
Assert-Eq $c.Source 'default' 'rozbity JSON degraduje na defaulty'
Assert-Eq $c.BaseRef 'origin/develop' 'rozbity JSON nezpusobi vyjimku'

Remove-Item -Recurse -Force $tmp
Complete-Tests
