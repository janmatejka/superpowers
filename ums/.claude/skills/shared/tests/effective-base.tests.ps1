#Requires -Version 7
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_assert.ps1')
. (Join-Path $PSScriptRoot '..\scripts\Get-UmsEffectiveBase.ps1')

$tmp = Join-Path ([IO.Path]::GetTempPath()) ("ums-eff-" + [Guid]::NewGuid().ToString('N'))
$mb = Join-Path $tmp 'memory-bank'
New-Item -ItemType Directory -Force -Path $mb | Out-Null
Set-Content -LiteralPath (Join-Path $mb 'ums-repo.json') -Encoding UTF8 -Value '{ "baseRef": "origin/ums-memory-bank" }'

Write-Host "== bez context.md padne na konfiguraci"
$e = Get-UmsEffectiveBase $tmp
Assert-Eq $e.Ref 'origin/ums-memory-bank' 'bez context.md plati baseRef'
Assert-Eq $e.Source 'config' 'zdroj je konfigurace'

Write-Host "== context.md bez radku Baze padne na konfiguraci"
Set-Content -LiteralPath (Join-Path $mb 'context.md') -Encoding UTF8 -Value @'
# Context

## Active Work

- **Jira:** (bez tiketu)
- **Target MB Pin:** memory-bank/
- **Work item:** neco
- **Started:** 2026-08-11
'@
$e = Get-UmsEffectiveBase $tmp
Assert-Eq $e.Ref 'origin/ums-memory-bank' 'chybejici radek Baze znamena vychozi bazi'
Assert-Eq $e.Source 'config' 'zdroj je konfigurace i s existujicim context.md'
Assert-True ($null -eq $e.Malformed) 'zadny radek Baze neni nesrozumitelny radek'

Write-Host "== radek Baze ma prednost pred baseRef"
Set-Content -LiteralPath (Join-Path $mb 'context.md') -Encoding UTF8 -Value @'
# Context

## Active Work

- **Jira:** (bez tiketu)
- **Target MB Pin:** memory-bank/
- **Work item:** neco
- **Báze:** origin/Branches/5.37
- **Started:** 2026-08-11
'@
$e = Get-UmsEffectiveBase $tmp
Assert-Eq $e.Ref 'origin/Branches/5.37' 'radek Baze prebiji baseRef'
Assert-Eq $e.Source 'context' 'zdroj je context.md'
Assert-True ($null -eq $e.Malformed) 'citelny radek Baze neni hlasen jako nesrozumitelny'

Write-Host "== derivace push destinace strhava jen JEDNO lomitko"
Assert-Eq $e.Branch 'Branches/5.37' 'Branch je Ref bez remote, lomitko ve jmene zustava'

# Three shapes the loose match catches but the strict value regex does not.
# Without the Malformed field all three would land silently on the config base
# with Source=config - indistinguishable from "there is no line at all".
$badLines = @(
    @{ Line = '- **Báze:** origin/Branches/5.37  <!-- pozn -->'; Case = 'komentar za hodnotou' },
    @{ Line = '- **Báze:**'; Case = 'prazdna hodnota' },
    @{ Line = '- **Baze:** origin/Branches/5.37'; Case = 'chybejici diakritika' }
)
foreach ($bad in $badLines) {
    Write-Host "== nesrozumitelny radek Baze: $($bad.Case)"
    Set-Content -LiteralPath (Join-Path $mb 'context.md') -Encoding UTF8 -Value @"
# Context

## Active Work

- **Jira:** (bez tiketu)
- **Target MB Pin:** memory-bank/
- **Work item:** neco
$($bad.Line)
- **Started:** 2026-08-11
"@
    $e = Get-UmsEffectiveBase $tmp
    Assert-Eq $e.Ref 'origin/ums-memory-bank' "$($bad.Case): fallback na konfiguracni bazi zustava"
    Assert-Eq $e.Source 'config' "$($bad.Case): zdroj je konfigurace"
    Assert-Eq $e.Malformed $bad.Line "$($bad.Case): Malformed jmenuje presne ten radek"
}

Write-Host "== IDLE stav se zachovanym radkem Baze (integrace bezi po resetu)"
Set-Content -LiteralPath (Join-Path $mb 'context.md') -Encoding UTF8 -Value @'
# Context

## Active Work

(No active work - IDLE phase)

- **Jira:** (bez tiketu)
- **Báze:** origin/Branches/5.37
'@
$e = Get-UmsEffectiveBase $tmp
Assert-Eq $e.Ref 'origin/Branches/5.37' 'zachovany radek plati i v IDLE stavu'
Assert-Eq $e.Source 'context' 'IDLE nemeni zdroj'

Write-Host "== bez konfigurace i bez context.md plati vestaveny default"
$bare = Join-Path ([IO.Path]::GetTempPath()) ("ums-eff2-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path (Join-Path $bare 'memory-bank') | Out-Null
$e = Get-UmsEffectiveBase $bare
Assert-Eq $e.Ref 'origin/develop' 'vestaveny default baseRef'
Assert-Eq $e.Branch 'develop' 'derivace nad vestavenym defaultem'

Remove-Item -Recurse -Force $tmp, $bare -ErrorAction SilentlyContinue
Complete-Tests
