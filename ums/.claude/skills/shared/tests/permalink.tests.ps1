#Requires -Version 7
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '_assert.ps1')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\scripts\Get-UmsPermalink.ps1')
function New-RepoWithOrigin([string] $Url) {
    $r = Join-Path ([IO.Path]::GetTempPath()) ("mbperma-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $r | Out-Null; git -C $r init -q; git -C $r remote add origin $Url; return $r
}
$sha = '50d222f0ee412a2450f084e40cd1eb3724ed2c38'
$gh = New-RepoWithOrigin 'https://github.com/janmatejka/superpowers'
$p = Get-UmsPermalink -RepoRoot $gh -Sha $sha -Path 'memory-bank/proposals/active/design_x.md'
Assert-Eq $p.Url "https://github.com/janmatejka/superpowers/blob/$sha/memory-bank/proposals/active/design_x.md" 'GitHub https remote → blob permalink'
Assert-Eq $p.Source 'derived' 'zdroj je odvození'
$bb = New-RepoWithOrigin 'git@bitbucket.org:datasyscz/ums.git'
$p = Get-UmsPermalink -RepoRoot $bb -Sha $sha -Path 'Doc/a.md'
Assert-Eq $p.Url "https://bitbucket.org/datasyscz/ums/src/$sha/Doc/a.md" 'Bitbucket ssh remote → src permalink'
$p = Get-UmsPermalink -RepoRoot $bb -Sha $sha -Path 'Doc/a.md' -Template 'https://git.example/{sha}/{path}'
Assert-Eq $p.Url "https://git.example/$sha/Doc/a.md" 'šablona má přednost'
Assert-Eq $p.Source 'template' 'zdroj je šablona'
$other = New-RepoWithOrigin 'https://gitea.internal/x/y.git'
$p = Get-UmsPermalink -RepoRoot $other -Sha $sha -Path 'a.md'
Assert-Eq $p.Url $null 'neznámý host nevrací URL'
Assert-Match $p.Reason 'unknown host' 'důvod jmenuje neznámý host'
$p = Get-UmsPermalink -RepoRoot $gh -Sha 'abc' -Path 'a.md'
Assert-Eq $p.Url $null 'krátké SHA je odmítnuté'
$p = Get-UmsPermalink -RepoRoot $gh -Sha $sha -Path '../secret.md'
Assert-Eq $p.Url $null 'cesta s .. je odmítnutá'
Remove-Item -Recurse -Force $gh, $bb, $other
Complete-Tests
