#Requires -Version 7
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_assert.ps1')
. (Join-Path $PSScriptRoot '..\scripts\epic-line.ps1')

# Everything here runs against a LOCAL BARE ORIGIN in OS temp. New-UmsEpicLine
# pushes, so the fixture's origin is the only remote it may ever see - never
# this repository's real one.
function Invoke-Git([string] $Root, [string[]] $GitArgs) {
    $out = & git -C $Root @GitArgs 2>&1
    if ($LASTEXITCODE -ne 0) { throw "git $($GitArgs -join ' ') failed in ${Root}: $out" }
    return @($out)
}

$tmp = Join-Path ([IO.Path]::GetTempPath()) ("ums-epicline-" + [Guid]::NewGuid().ToString('N'))
$bare = Join-Path $tmp 'origin.git'
$work = Join-Path $tmp 'work'
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
& git init --bare --initial-branch=develop $bare | Out-Null
& git init --initial-branch=develop $work | Out-Null
Invoke-Git $work @('remote', 'add', 'origin', $bare) | Out-Null
Set-Content -LiteralPath (Join-Path $work 'a.txt') -Value 'one' -NoNewline
Invoke-Git $work @('add', 'a.txt') | Out-Null
Invoke-Git $work @('-c', 'user.email=t@t', '-c', 'user.name=t', 'commit', '-m', 'init') | Out-Null
Invoke-Git $work @('push', '--no-verify', 'origin', 'develop') | Out-Null
Invoke-Git $work @('fetch', 'origin') | Out-Null
$developSha = (@(Invoke-Git $work @('rev-parse', 'origin/develop')))[0].Trim()

Write-Host "== prvni volani zaklada linii epiku z dodavkove linie"
$r = New-UmsEpicLine $work 'UMS-1' 'origin/develop'
Assert-Eq $r.Branch 'epic/UMS-1' 'Branch je epic/<klic>'
Assert-True ($r.Created -eq $true) 'prvni volani: Created'
Assert-True ($r.Existed -eq $false) 'prvni volani: nebylo Existed'
Assert-Eq $r.Sha $developSha 'Sha je SHA dodavkove linie'
$ls = @(Invoke-Git $work @('ls-remote', 'origin', 'refs/heads/epic/UMS-1'))
Assert-Eq (@($ls).Count) 1 'ls-remote vraci prave jednu vetev epic/UMS-1'
Assert-Eq ((@($ls)[0] -split '\s+')[0]) $developSha 'vetev epic/UMS-1 na originu ukazuje na SHA develop'

Write-Host "== druhe volani vetev nemeni"
$r2 = New-UmsEpicLine $work 'UMS-1' 'origin/develop'
Assert-True ($r2.Existed -eq $true) 'druhe volani: Existed'
Assert-True ($r2.Created -eq $false) 'druhe volani: nic nezalozilo'
Assert-Eq $r2.Sha $developSha 'druhe volani: Sha je SHA linie na originu'

Write-Host "== existujici linie se nepretaci ani kdyz se dodavkova linie posunula"
Set-Content -LiteralPath (Join-Path $work 'a.txt') -Value 'two' -NoNewline
Invoke-Git $work @('-c', 'user.email=t@t', '-c', 'user.name=t', 'commit', '-am', 'second') | Out-Null
Invoke-Git $work @('push', '--no-verify', 'origin', 'develop') | Out-Null
$newDevelop = (@(Invoke-Git $work @('rev-parse', 'HEAD')))[0].Trim()
Assert-True ($newDevelop -ne $developSha) 'fixtura: develop se posunul'
$r3 = New-UmsEpicLine $work 'UMS-1' 'origin/develop'
Assert-True ($r3.Existed -eq $true) 'posunuta dodavkova linie: linie porad Existed'
Assert-Eq $r3.Sha $developSha 'posunuta dodavkova linie: Sha linie epiku je puvodni'
$ls = @(Invoke-Git $work @('ls-remote', 'origin', 'refs/heads/epic/UMS-1'))
Assert-Eq ((@($ls)[0] -split '\s+')[0]) $developSha 'origin: epic/UMS-1 se nepohnula'

Write-Host "== dalsi epik se zaklada z aktualniho tipu dodavkove linie; DeliveryRef muze byt SHA"
$r4 = New-UmsEpicLine $work 'UMS-2' $newDevelop
Assert-True ($r4.Created -eq $true) 'epic/UMS-2 zalozena z holeho SHA'
Assert-Eq $r4.Sha $newDevelop 'epic/UMS-2 ukazuje na zadane SHA'

Write-Host "== chybny vstup a chyba pushe = vyjimka"
$threw = $false
try { New-UmsEpicLine $work 'UMS-3' 'origin/neexistuje' | Out-Null } catch { $threw = $true }
Assert-True $threw 'neexistujici dodavkova linie: vyjimka'
Assert-Eq (@(Invoke-Git $work @('ls-remote', 'origin', 'refs/heads/epic/UMS-3')).Count) 0 'neexistujici dodavkova linie nezalozila nic'

$threw = $false
try { New-UmsEpicLine $work 'bad key;x' 'origin/develop' | Out-Null } catch { $threw = $true }
Assert-True $threw 'klic epiku mimo tvar: vyjimka'
Assert-Eq (@(Invoke-Git $work @('ls-remote', 'origin', 'refs/heads/epic/bad*')).Count) 0 'klic mimo tvar nezalozil nic'

# A push that is refused: a pre-receive hook on the bare origin rejects the
# new ref. The failure must surface as an exception, not as a silent Created.
$hookDir = Join-Path $bare 'hooks'
New-Item -ItemType Directory -Force -Path $hookDir | Out-Null
$hook = Join-Path $hookDir 'pre-receive'
[IO.File]::WriteAllText($hook, "#!/bin/sh`nexit 1`n")
$canHook = $true
try { & chmod +x $hook 2>$null } catch { $canHook = $false }
$threw = $false
try { New-UmsEpicLine $work 'UMS-4' 'origin/develop' | Out-Null } catch { $threw = $true }
if ($canHook -and (@(Invoke-Git $work @('ls-remote', 'origin', 'refs/heads/epic/UMS-4')).Count) -eq 0) {
    Assert-True $threw 'odmitnuty push: vyjimka'
} else {
    Write-Host '  skip: pre-receive hook na tomto stroji nespusti (bez chmod), odmitnuty push se neoveruje'
}
Remove-Item -LiteralPath $hook -Force

Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
Complete-Tests
