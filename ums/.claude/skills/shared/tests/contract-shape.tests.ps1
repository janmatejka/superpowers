#Requires -Version 7
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '_assert.ps1')
$ErrorActionPreference = 'Stop'
$shared = Resolve-Path (Join-Path $PSScriptRoot '..')
$layer = Resolve-Path (Join-Path $shared '..\..')          # ums/.claude
$core = Join-Path $shared 'UMS_MEMORY_BANK_CONTRACT.md'
$refDir = Join-Path $shared 'contract'
$coreLines = @(Get-Content -LiteralPath $core -Encoding utf8)

Assert-True ($coreLines.Count -le 600) "jádro má nejvýš 600 řádků (má $($coreLines.Count))"
Assert-Match ($coreLines -join "`n") '(?m)^- \*\*Contract-Version:\*\* \d+\.\d+' 'jádro nese Contract-Version'
Assert-True (-not (($coreLines -join "`n") -match '(?m)^- (Supersedes|v\d+\.\d+ superseded)')) 'verzní preambule v jádře není'
foreach ($h in @('## Escalation & Autonomy', '## Fail-Closed Behavior', '## Publication Contract', '## Language Contract', '## Message Protocol', '## Session Eligibility', '## Work Item Granularity', '## Phase Map')) {
    Assert-True (($coreLines -match ('^' + [regex]::Escape($h) + '\s*$')).Count -eq 1) "jádro má právě jednu sekci $h"
}
foreach ($k in @('Publication into the delivery line', 'irreversible or destructive', 'security-sensitive', 'not a protected branch', 'epicBranchPattern', 'playbook.md')) {
    Assert-True ((($coreLines -join "`n") -match [regex]::Escape($k))) "řádek dna «$k» je v jádře"
}
Assert-True (-not (($coreLines -join "`n") -match 'Measured|measured 2026|Earlier versions|superseded v|once claimed')) 'jádro nenese značky dokladu'

# --- heading index across core + references -----------------------------------
function Get-Headings([string] $Path) {
    @(Get-Content -LiteralPath $Path -Encoding utf8) | Where-Object { $_ -match '^#{2,4}\s+' } |
        ForEach-Object { ($_ -replace '^#{2,4}\s+', '').Trim() -replace '`', '' }
}
$index = @{ 'core' = @(Get-Headings $core) }
$refs = @(Get-ChildItem -LiteralPath $refDir -File -Filter '*.md')
foreach ($r in $refs) { $index[$r.Name] = @(Get-Headings $r.FullName) }
Assert-True ($refs.Count -ge 17) "existuje aspoň 17 referencí (je $($refs.Count))"

# --- citations ----------------------------------------------------------------
$scan = @(Get-ChildItem -LiteralPath $layer -Recurse -File -Include *.md, *.ps1, *.mjs, pre-push |
    Where-Object { $_.FullName -notmatch '[\\/]doklad[\\/]' -and $_.Name -ne 'CHANGELOG.md' -and $_.FullName -notmatch '[\\/]tests[\\/]' })
$bad = @(); $legacy = @(); $count = 0
foreach ($f in $scan) {
    $text = Get-Content -LiteralPath $f.FullName -Raw -Encoding utf8
    if ($null -eq $text) { continue }
    foreach ($m in [regex]::Matches($text, '\(contract, "(?<s>[^"]+)"\)')) {
        $count++
        $s = $m.Groups['s'].Value -replace '`', ''
        if ($index['core'] -notcontains $s) { $bad += "$($f.Name): (contract, `"$s`")" }
    }
    foreach ($m in [regex]::Matches($text, '\(contract/(?<f>[a-z0-9-]+\.md), "(?<s>[^"]+)"\)')) {
        $count++
        $fn = $m.Groups['f'].Value; $s = $m.Groups['s'].Value -replace '`', ''
        if (-not $index.ContainsKey($fn)) { $bad += "$($f.Name): reference $fn neexistuje"; continue }
        if ($index[$fn] -notcontains $s) { $bad += "$($f.Name): (contract/$fn, `"$s`")" }
    }
    # U+201E is spelled with `u{201E} on purpose: PowerShell 7 treats a literal „
    # as a smart-quote string delimiter, so the brief's literal spelling does not parse.
    foreach ($m in [regex]::Matches($text, "contract's\s+[`"`u{201E}]|UMS_MEMORY_BANK_CONTRACT\.md`?,\s*[`"`u{201E}]|\(contract,\s+section\s")) {
        $legacy += "$($f.Name): $($m.Value)"
    }
}
Assert-True ($count -gt 50) "nalezeno dost citací ke kontrole ($count)"
Assert-Eq @($bad).Count 0 ("každá citace má cíl: " + ($bad -join '; '))
Assert-Eq @($legacy).Count 0 ("žádný legacy tvar citace: " + ($legacy -join '; '))

# --- every reference has a consumer -------------------------------------------
$noConsumer = @()
foreach ($r in $refs) {
    $hits = @($scan | Where-Object { (Get-Content -LiteralPath $_.FullName -Raw -Encoding utf8) -match [regex]::Escape("contract/$($r.Name)") })
    if ($hits.Count -eq 0) { $noConsumer += $r.Name }
}
Assert-Eq @($noConsumer).Count 0 ("každá reference má konzumenta: " + ($noConsumer -join ', '))
Complete-Tests
