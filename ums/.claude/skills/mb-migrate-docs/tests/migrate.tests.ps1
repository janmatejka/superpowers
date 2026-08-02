#Requires -Version 7
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_assert.ps1')
. (Join-Path $PSScriptRoot 'new-fixture-repo.ps1')

$fx = New-FixtureRepo
$work = $fx.Work

Write-Host "== Plan mode (default) =="
$r = Invoke-Script 'migrate-mb-docs.ps1' @('-RepoPath', $work)
Assert-Eq $r.Code 2 'Plan hlásí konflikt v C -> exit 2'
Assert-Match $r.Out 'A[/\\]memory-bank' 'Plan jmenuje MB A'
Assert-Match $r.Out 'KONFLIKT PLAYBOOKU' 'Plan hlásí konflikt playbooku'
Assert-True (Test-Path (Join-Path $work 'A/memory-bank/product.md')) 'Plan nic nemaže'

Write-Host "== Apply =="
$json = Join-Path ([IO.Path]::GetTempPath()) ("mbmig-" + [guid]::NewGuid().ToString('N').Substring(0,8) + '.json')
$r = Invoke-Script 'migrate-mb-docs.ps1' @('-RepoPath', $work, '-Apply', '-Json', $json)
Assert-Eq $r.Code 2 'Apply doběhne, ale konflikt v C drží exit 2'

$briefA = Get-Content -LiteralPath (Join-Path $work 'A/memory-bank/brief.md') -Raw
Assert-Match $briefA '## Produktový pohled' 'A: vložen nadpis produktového pohledu'
Assert-Match $briefA '### Pro koho' 'A: nadpisy produktu posunuty o úroveň'
Assert-Match $briefA '#### Detail' 'A: vnořený nadpis posunut také'
Assert-NotMatch $briefA '(?m)^## Product - A$' 'A: H1 produktu zahozen, ne posunut'
Assert-Match $briefA '(?m)^# tohle není nadpis$' 'A: řádek uvnitř fence se neposouvá'
Assert-True (-not (Test-Path (Join-Path $work 'A/memory-bank/product.md'))) 'A: product.md odstraněn'
Assert-True (Test-Path (Join-Path $work 'A/memory-bank/playbook.md')) 'A: tasks.md přejmenován na playbook.md'
Assert-True (-not (Test-Path (Join-Path $work 'A/memory-bank/tasks.md'))) 'A: tasks.md už neexistuje'

$archA = Get-Content -LiteralPath (Join-Path $work 'A/memory-bank/architecture.md') -Raw
Assert-Match $archA '\[product\]\(brief\.md\)' 'A: odkaz na product.md přepsán na brief.md'
Assert-Match $archA '\[tasks\]\(playbook\.md\)' 'A: odkaz na tasks.md přepsán na playbook.md'

Assert-True (Test-Path (Join-Path $work 'C/memory-bank/tasks.md')) 'C: konfliktní tasks.md zůstal'
Assert-True (Test-Path (Join-Path $work 'D/memory-bank/brief.md')) 'D: product.md přejmenován na brief.md'
Assert-True (-not (Test-Path (Join-Path $work 'D/memory-bank/product.md'))) 'D: product.md už neexistuje'
Assert-Match $r.Out 'PRODUCT BEZ BRIEFU' 'D: hlášeno varování o chybějícím briefu'
Assert-True (Test-Path (Join-Path $work 'E/tests/fixtures/memory-bank/product.md')) 'E: fixture cesta přeskočena'

$idx = Get-Content -LiteralPath $json -Raw | ConvertFrom-Json
$mbA = $idx.mbs | Where-Object { $_.path -match 'A[/\\]memory-bank' }
Assert-Eq $mbA.merged $true 'JSON: A má merged=true'
Assert-Eq $mbA.renamed $true 'JSON: A má renamed=true'
$mbB = $idx.mbs | Where-Object { $_.path -match 'B[/\\]memory-bank' }
Assert-Eq $mbB.merged $false 'JSON: B nic neslučovalo'

Write-Host "== Staging =="
$staged = (& git -C $work diff --cached --name-only) -join "`n"
Assert-Match $staged 'A/memory-bank/brief.md' 'Sloučený brief.md je ve stagingu'
Assert-Match $staged 'A/memory-bank/product.md' 'Odstranění product.md je ve stagingu'

Write-Host "== Idempotence =="
Invoke-Git $work @('commit', '-m', 'migrace') | Out-Null
$r2 = Invoke-Script 'migrate-mb-docs.ps1' @('-RepoPath', $work)
Assert-Match $r2.Out 'A[/\\]memory-bank.*(hotovo|beze změny)' 'Druhý běh hlásí A jako hotovou'
Assert-NotMatch $r2.Out '(?m)^\s*\|\s*A[/\\]memory-bank\s*\|\s*sloučit' 'Druhý běh už neplánuje sloučení'

Write-Host "== Špinavý strom =="
Set-Content -LiteralPath (Join-Path $work 'B/memory-bank/brief.md') -Encoding UTF8 -Value @('# Brief - B', 'změna')
$r3 = Invoke-Script 'migrate-mb-docs.ps1' @('-RepoPath', $work, '-Apply')
Assert-Eq $r3.Code 1 'Apply nad špinavým stromem končí chybou'
Assert-Match $r3.Out 'pracovní strom' 'Zpráva jmenuje pracovní strom'

Complete-Tests
