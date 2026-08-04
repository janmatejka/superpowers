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
Assert-Eq $c.TicketPattern '^UMS-[0-9]+' 'ticketPattern ze souboru'
Assert-Eq (@($c.ProjectMarkers)[0]) '*.csproj' 'projectMarkers ze souboru'
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

Write-Host "== Source hlasi KDE loader hledal, ne kolik pouzil"
'{ "baseRef": null, "protectedBranches": null, "ticketPattern": null, "projectMarkers": null, "sharedRoots": null }' |
    Set-Content -Encoding UTF8 -LiteralPath (Join-Path $tmp 'memory-bank\ums-repo.json')
$c = Get-UmsRepoConfig $tmp
Assert-Eq $c.Source 'file' 'soubor se samymi null hodnotami je porad nalezeny soubor'
Assert-Eq $c.BaseRef 'origin/develop' 'null baseRef padne na default'
Assert-True (@($c.ProtectedBranches).Count -eq 4) 'null protectedBranches padne na default'

Write-Host "== prazdny objekt {} je platny konfig, ktery nic neprebiji"
'{}' | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $tmp 'memory-bank\ums-repo.json')
$c = Get-UmsRepoConfig $tmp
Assert-Eq $c.Source 'file' 'prazdny objekt hlasi Source=file'
Assert-Eq $c.BaseRef 'origin/develop' 'prazdny objekt necha baseRef na defaultu'
Assert-True (@($c.ProtectedBranches).Count -eq 4) 'prazdny objekt necha protectedBranches na defaultu'

Write-Host "== JSON null (bez objektu) je malformed jako konfig"
'null' | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $tmp 'memory-bank\ums-repo.json')
$c = Get-UmsRepoConfig $tmp
Assert-Eq $c.Source 'default' 'holy null degraduje na defaulty'
Assert-True (@($c.ProtectedBranches).Count -eq 4) 'holy null ma 4 vestavene vzory'

Write-Host "== holy skalar je malformed jako konfig"
'42' | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $tmp 'memory-bank\ums-repo.json')
$c = Get-UmsRepoConfig $tmp
Assert-Eq $c.Source 'default' 'holy skalar degraduje na defaulty'
Assert-True (@($c.ProtectedBranches).Count -eq 4) 'holy skalar ma 4 vestavene vzory'

Write-Host "== holy JSON array je malformed jako konfig"
'[1,2,3]' | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $tmp 'memory-bank\ums-repo.json')
$c = Get-UmsRepoConfig $tmp
Assert-Eq $c.Source 'default' 'holy array degraduje na defaulty'
Assert-True (@($c.ProtectedBranches).Count -eq 4) 'holy array ma 4 vestavene vzory'

Remove-Item -Recurse -Force $tmp
Complete-Tests
