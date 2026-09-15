#Requires -Version 7
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '_assert.ps1')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\scripts\Get-UmsHookVersion.ps1')

function New-HookFile([string] $Label, [string] $FirstLines) {
    $p = Join-Path ([IO.Path]::GetTempPath()) ("mbhookver-$Label-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    [IO.File]::WriteAllText($p, $FirstLines, (New-Object System.Text.UTF8Encoding($false)))
    return $p
}

$v3 = New-HookFile 'v3' "#!/bin/sh`n# UMS pre-push guard (Publication Contract) v3`n#`n"
$v2 = New-HookFile 'v2' "#!/bin/sh`n# UMS pre-push guard (Publication Contract) v2`n#`n"
$v0 = New-HookFile 'v0' "#!/bin/sh`n# UMS pre-push guard (Publication Contract)`n#`n"
$foreign = New-HookFile 'foreign' "#!/bin/sh`nexit 0`n"
$deep = New-HookFile 'deep' "#!/bin/sh`n#`n#`n#`n#`n# UMS pre-push guard (Publication Contract) v3`n"

Assert-Eq (Get-UmsHookVersion $v3) 3 'verze v3 se přečte jako 3'
Assert-Eq (Get-UmsHookVersion $v2) 2 'verze v2 se přečte jako 2'
Assert-Eq (Get-UmsHookVersion $v0) 0 'náš hook bez přípony je verze 0'
Assert-Eq (Get-UmsHookVersion $foreign) $null 'cizí hook nevrací verzi'
Assert-Eq (Get-UmsHookVersion (Join-Path $PSScriptRoot 'neexistuje')) $null 'chybějící soubor nevrací verzi'
Assert-Eq (Get-UmsHookVersion $deep) $null 'značka pod pátým řádkem se nepočítá'

Assert-True (Test-UmsHookNeedsInstall $v2 $v3) 'nainstalovaná v2 proti zdrojové v3 chce instalaci'
Assert-True (-not (Test-UmsHookNeedsInstall $v3 $v3)) 'shodná verze instalaci nechce'
Assert-True (-not (Test-UmsHookNeedsInstall $v3 $v2)) 'NOVĚJŠÍ nainstalovaná verze se NEDEGRADUJE'
Assert-True (Test-UmsHookNeedsInstall $v0 $v2) 'hook bez přípony chce instalaci'
Assert-True (Test-UmsHookNeedsInstall $foreign $v3) 'cizí hook chce instalaci'

Remove-Item -Force $v3, $v2, $v0, $foreign, $deep
Complete-Tests
