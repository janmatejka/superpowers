#Requires -Version 7
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '_assert.ps1')
$ErrorActionPreference = 'Stop'
$shared = Resolve-Path (Join-Path $PSScriptRoot '..')
$layer = Resolve-Path (Join-Path $shared '..\..')          # ums/.claude
$core = Join-Path $shared 'UMS_MEMORY_BANK_CONTRACT.md'
$refDir = Join-Path $shared 'contract'
$coreLines = @(Get-Content -LiteralPath $core -Encoding utf8)

# Rozpočet jádra = 800 řádků, odvozeno MĚŘENÍM, ne odhadem.
# Návrh (sekce 2.2) odhadoval ~470 řádků, jenže ten odhad byl nad PRÓZOU. Soubor
# je markdown: naměřeno 258 ze 790 řádků (32,7 %) nejsou próza vůbec — 34 nadpisů
# (každý je cíl citace), 135 markdownem vynucených prázdných řádků, 46 řádků
# tabulek, 30 řádků fenced bloků a 13 ukazatelů `Doklad:`. Tuhle část nelze
# stlačit, aniž by se rozbily cíle citací. Próza sama je 532 řádků po dvou
# kolech komprese (Task 4), nezávislé revizi, která větu po větě potvrdila, že
# nezmizelo žádné pravidlo, kvalifikátor, STOP ani artefakt, a třetím kole
# v Task 19 (první publikace s `-u`, dvojí zápis pushe, dvě přijaté obchůzky
# a odmítnutí řetězení cizího hooku se přesunuly do `contract/integration.md`,
# sekce „Publication mechanics" — jádro je jmenuje a odkazuje).
# Smysl asercie je zabránit tomu, aby jádro znovu narostlo do 3066řádkového
# dokumentu, ze kterého vzniklo — ne trvale svítit červeně. Naměřeno 790,
# zaokrouhleno nahoru na 800.
#
# CO DĚLAT, AŽ TAHLE ASERCE ZČERVENÁ (deset řádků rezervy je západka, ne prostor
# k růstu — proto tenhle odstavec): číslo NEZVYŠUJ reflexivně. Nejdřív znovu změř
# podíl neprózy výše uvedeným rozpadem a podívej se na PŘIBYLÉ řádky. Je-li mezi
# nimi výklad, zdůvodnění, zopakované pravidlo nebo příklad, patří do
# `contract/<téma>.md` (mechanismus) nebo `contract/doklad/<téma>.md` (měření
# a zdůvodnění) — komprimuj prózu, strop nech být. Strop zvyš jedině tehdy, když
# přibylé řádky jsou samy pravidla nebo artefakty (nadpis jako cíl citace,
# tabulka, fenced blok, ukazatel `Doklad:`), a nové číslo odvoď stejným měřením
# a zapiš ho sem i s tím, co přibylo. Nadpisy nikdy nekomprimuj — jsou cíle
# citací a hlídá je aserce o sekcích níž.
Assert-True ($coreLines.Count -le 800) "jádro má nejvýš 800 řádků (má $($coreLines.Count))"
Assert-Match ($coreLines -join "`n") '(?m)^- \*\*Contract-Version:\*\* \d+\.\d+' 'jádro nese Contract-Version'
Assert-True (-not (($coreLines -join "`n") -match '(?m)^- (Supersedes|v\d+\.\d+ superseded)')) 'verzní preambule v jádře není'
foreach ($h in @('## Escalation & Autonomy', '## Fail-Closed Behavior', '## Publication Contract', '## Language Contract', '## Message Protocol', '## Session Eligibility', '## Work Item Granularity', '## Phase Map')) {
    Assert-True (($coreLines -match ('^' + [regex]::Escape($h) + '\s*$')).Count -eq 1) "jádro má právě jednu sekci $h"
}
# Podlaha eskalace: aserce MUSÍ číst datové řádky TABULKY, ne celý soubor.
# Celosouborový substring match nedokáže smazání řádku podlahy vidět — token
# `playbook.md` stojí v jádře na sedmi dalších místech, takže smazaná řádka
# `| Writing into playbook.md | … |` nechala asercii zelenou. Ostatní klíče jsou
# bezpečné jen náhodou (každý je v souboru právě jednou). Proto: najdi tabulku,
# vezmi jen její datové řádky, a asertuj OBOJÍ — že každý klíč je právě v jedné
# řádce, a že řádek je přesně šest. Počet chytá řádku PŘIDANOU bez aserčního
# klíče, na kterou je per-klíčová půlka slepá.
$floorRows = @()
$floorHeader = -1
for ($i = 0; $i -lt $coreLines.Count; $i++) {
    if ($coreLines[$i] -match '^\|\s*Kind\s*\|\s*Example\s*\|\s*$') { $floorHeader = $i; break }
}
Assert-True ($floorHeader -ge 0) 'tabulka podlahy eskalace je v jádře nalezena'
if ($floorHeader -ge 0) {
    for ($j = $floorHeader + 2; $j -lt $coreLines.Count; $j++) {
        if ($coreLines[$j] -notmatch '^\s*\|') { break }
        $floorRows += $coreLines[$j]
    }
}
Assert-Eq @($floorRows).Count 6 'tabulka podlahy eskalace má právě 6 datových řádků'
foreach ($k in @('Publication into the delivery line', 'irreversible or destructive', 'security-sensitive', 'not a protected branch', 'epicBranchPattern', 'playbook.md')) {
    Assert-Eq @($floorRows | Where-Object { $_ -match [regex]::Escape($k) }).Count 1 "řádek dna «$k» je právě v jedné řádce tabulky podlahy"
}
Assert-True (-not (($coreLines -join "`n") -match 'Measured|measured 2026|Earlier versions|superseded v|once claimed')) 'jádro nenese značky dokladu'

# --- heading index across core + references -----------------------------------
function Get-Headings([string] $Path) {
    @(Get-Content -LiteralPath $Path -Encoding utf8) | Where-Object { $_ -match '^#{1,4}\s+' } |
        ForEach-Object { ($_ -replace '^#{1,4}\s+', '').Trim() -replace '`', '' }
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
# Reference se cituje sama ve své hlavičce (`cite as (contract/<jméno>.md, …)`),
# a `$scan` obsahuje i soubory referencí — takže bez vyloučení VLASTNÍHO souboru
# je aserce splněná bezpodmínečně a nemůže nikdy zčervenat. Jednou tak zeleně
# proseděla reference s nulovým skutečným konzumentem.
$noConsumer = @()
foreach ($r in $refs) {
    $hits = @($scan | Where-Object {
        $_.FullName -ne $r.FullName -and
        (Get-Content -LiteralPath $_.FullName -Raw -Encoding utf8) -match [regex]::Escape("contract/$($r.Name)")
    })
    if ($hits.Count -eq 0) { $noConsumer += $r.Name }
}
Assert-Eq @($noConsumer).Count 0 ("každá reference má konzumenta: " + ($noConsumer -join ', '))
Complete-Tests
