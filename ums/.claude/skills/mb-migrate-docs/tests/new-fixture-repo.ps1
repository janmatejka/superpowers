# Builds an offline fixture repo with Memory Banks in the legacy and the
# current shape, plus the conflict and link-rewrite cases.
# Returns @{ Work=<path>; Origin=<path> }.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-Git([string] $RepoDir, [string[]] $GitArgs) {
    $out = & git -C $RepoDir -c user.name=Test -c user.email=test@example.com @GitArgs 2>&1
    if ($LASTEXITCODE -ne 0) { throw "git $($GitArgs -join ' ') failed: $out" }
    return $out
}

function Add-File([string] $RepoDir, [string] $RelPath, [string[]] $Lines) {
    $full = Join-Path $RepoDir $RelPath
    New-Item -ItemType Directory -Force -Path (Split-Path $full) | Out-Null
    Set-Content -LiteralPath $full -Encoding UTF8 -Value $Lines
    Invoke-Git $RepoDir @('add', '--', $RelPath) | Out-Null
}

function New-FixtureRepo {
    $root = Join-Path ([IO.Path]::GetTempPath()) ("mbmig-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $origin = Join-Path $root 'origin.git'
    $work = Join-Path $root 'work'
    New-Item -ItemType Directory -Force -Path $origin, $work | Out-Null
    & git init --bare -b develop $origin | Out-Null
    & git init -b develop $work | Out-Null
    Invoke-Git $work @('remote', 'add', 'origin', $origin) | Out-Null

    # A: legacy shape, the full case — brief + product + tasks, with a link
    #    from architecture.md into both files that must be rewritten.
    Add-File $work 'A/memory-bank/brief.md' @(
        '# Brief - A', '', '## Cíl projektu', 'Komponenta A dělá věci.',
        'Sdílená věta o třech variantách DLL.')
    Add-File $work 'A/memory-bank/product.md' @(
        '# Product - A', '', '## Pro koho', 'Pro vývojáře.',
        'Sdílená věta o třech variantách DLL.', '',
        '### Detail', 'Podrobnost.', '', '```bash', '# tohle není nadpis', 'echo ahoj', '```')
    Add-File $work 'A/memory-bank/tasks.md' @(
        '# Tasks - A', '', '## Postup: build', 'Spusť msbuild.')
    Add-File $work 'A/memory-bank/architecture.md' @(
        '# Architektura - A', '', 'Viz [product](product.md) a [tasks](tasks.md).')

    # B: already migrated — nothing to do, proves idempotence.
    Add-File $work 'B/memory-bank/brief.md' @('# Brief - B', '', 'Hotovo.')
    Add-File $work 'B/memory-bank/architecture.md' @('# Architektura - B')
    Add-File $work 'B/memory-bank/tech.md' @('# Tech - B')
    Add-File $work 'B/memory-bank/playbook.md' @('# Playbook - B')

    # C: conflict — both tasks.md and playbook.md exist.
    Add-File $work 'C/memory-bank/brief.md' @('# Brief - C')
    Add-File $work 'C/memory-bank/tasks.md' @('# Tasks - C')
    Add-File $work 'C/memory-bank/playbook.md' @('# Playbook - C')

    # D: product.md without brief.md — rename path.
    Add-File $work 'D/memory-bank/product.md' @('# Product - D', '', 'Jen produkt.')

    # E: fixture path — must be skipped entirely.
    Add-File $work 'E/tests/fixtures/memory-bank/product.md' @('# Product - fixture')
    Add-File $work 'E/tests/fixtures/memory-bank/brief.md' @('# Brief - fixture')

    Invoke-Git $work @('commit', '-m', 'fixture') | Out-Null
    Invoke-Git $work @('push', '-u', 'origin', 'develop') | Out-Null
    return @{ Work = $work; Origin = $origin }
}
