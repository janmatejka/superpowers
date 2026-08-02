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
# Captured BEFORE -Apply so the link-safety regressions below can prove
# byte-identical content afterwards, not just "still contains the substring".
$crossLinkFile = Join-Path $work 'A/memory-bank/cross-link.md'
$cLinksFile = Join-Path $work 'C/memory-bank/links.md'
$beforeCrossLinkHash = (Get-FileHash -LiteralPath $crossLinkFile -Algorithm SHA256).Hash
$beforeCLinksHash = (Get-FileHash -LiteralPath $cLinksFile -Algorithm SHA256).Hash

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
Assert-Match $archA '\[detail produktu\]\(brief\.md#pro-koho\)' 'A: odkaz se sekčním fragmentem (#pro-koho) je také přepsán'
Assert-NotMatch $archA '\(product\.md#pro-koho\)' 'A: kotvený odkaz na product.md už nikde nezůstal'

Assert-True (Test-Path (Join-Path $work 'C/memory-bank/tasks.md')) 'C: konfliktní tasks.md zůstal'
Assert-True (Test-Path (Join-Path $work 'D/memory-bank/brief.md')) 'D: product.md přejmenován na brief.md'
Assert-True (-not (Test-Path (Join-Path $work 'D/memory-bank/product.md'))) 'D: product.md už neexistuje'
Assert-Match $r.Out 'PRODUCT BEZ BRIEFU' 'D: hlášeno varování o chybějícím briefu'
Assert-True (Test-Path (Join-Path $work 'E/tests/fixtures/memory-bank/product.md')) 'E: fixture cesta přeskočena'

Write-Host "== Bezpečnost odkazů (nezmigrovaná/přeskočená MB) =="
# A links INTO C (the skipped conflict MB) — C's tasks.md still exists there,
# so the generic old/new existence guard already keeps this one untouched;
# asserted here as a locked-in regression, not just "still contains it".
$afterCrossLinkHash = (Get-FileHash -LiteralPath $crossLinkFile -Algorithm SHA256).Hash
Assert-Eq $afterCrossLinkHash $beforeCrossLinkHash 'A: odkaz do přeskočené MB C zůstal byte-identický'

# C's OWN document links to its own tasks.md (exists) AND to a "product.md"
# that never existed in C (C already has its own brief.md). Without excluding
# the whole skipped root from the link-rewrite pass, the generic guard alone
# would satisfy "old target gone (it never existed) AND new target exists"
# and wrongly rewrite product.md -> brief.md even though C never migrated.
$afterCLinksHash = (Get-FileHash -LiteralPath $cLinksFile -Algorithm SHA256).Hash
Assert-Eq $afterCLinksHash $beforeCLinksHash 'C: vlastní odkazy (tasks.md i neexistující product.md) zůstaly byte-identické, celá MB je přeskočena'

$idx = Get-Content -LiteralPath $json -Raw | ConvertFrom-Json
$mbA = $idx.mbs | Where-Object { $_.path -match 'A[/\\]memory-bank' }
Assert-Eq $mbA.merged $true 'JSON: A má merged=true'
Assert-Eq $mbA.renamed $true 'JSON: A má renamed=true'
$mbB = $idx.mbs | Where-Object { $_.path -match 'B[/\\]memory-bank' }
Assert-Eq $mbB.merged $false 'JSON: B nic neslučovalo'

Write-Host "== Staging =="
# --name-status (not --name-only): a bare path match would also pass if
# product.md were staged as MODIFIED instead of DELETED — the status letter
# is what actually proves each of the four distinct change kinds landed in
# the index the way Task 3's verifier needs to read them.
$statusOut = (& git -C $work diff --cached --find-renames --name-status) -join "`n"
Assert-Match $statusOut '(?m)^M\s+A[/\\]memory-bank[/\\]brief\.md$' 'Sloučený brief.md je ve stagingu jako M (modifikace)'
Assert-Match $statusOut '(?m)^D\s+A[/\\]memory-bank[/\\]product\.md$' 'product.md je ve stagingu jako D (smazání)'
Assert-Match $statusOut '(?m)^R\d*\s+A[/\\]memory-bank[/\\]tasks\.md\s+A[/\\]memory-bank[/\\]playbook\.md$' 'tasks.md -> playbook.md je ve stagingu jako R (rename)'
Assert-Match $statusOut '(?m)^M\s+A[/\\]memory-bank[/\\]architecture\.md$' 'Přepsaný architecture.md je ve stagingu jako M (modifikace)'

Write-Host "== Idempotence =="
Invoke-Git $work @('commit', '-m', 'migrace') | Out-Null
$statusAfterCommit = ((& git -C $work status --porcelain) -join "`n").Trim()
Assert-Eq $statusAfterCommit '' 'Po commitu migrace nezůstal žádný nestageovaný/necommitnutý zbytek'

$r2 = Invoke-Script 'migrate-mb-docs.ps1' @('-RepoPath', $work)
Assert-Match $r2.Out 'A[/\\]memory-bank.*(hotovo|beze změny)' 'Druhý běh hlásí A jako hotovou'
Assert-NotMatch $r2.Out '(?m)^\s*\|\s*A[/\\]memory-bank\s*\|\s*sloučit' 'Druhý běh už neplánuje sloučení'

# Idempotence must hold for -Apply itself, not just for the plan: running
# -Apply again over an already-migrated tree must be a true no-op.
$r2b = Invoke-Script 'migrate-mb-docs.ps1' @('-RepoPath', $work, '-Apply')
$statusAfterReapply = ((& git -C $work status --porcelain) -join "`n").Trim()
Assert-Eq $statusAfterReapply '' 'Druhý -Apply běh nad již migrovaným repozitářem nic nemění (prázdný git status)'

Write-Host "== Špinavý strom =="
Set-Content -LiteralPath (Join-Path $work 'B/memory-bank/brief.md') -Encoding UTF8 -Value @('# Brief - B', 'změna')
$r3 = Invoke-Script 'migrate-mb-docs.ps1' @('-RepoPath', $work, '-Apply')
Assert-Eq $r3.Code 1 'Apply nad špinavým stromem končí chybou'
Assert-Match $r3.Out 'pracovní strom' 'Zpráva jmenuje pracovní strom'

Complete-Tests
