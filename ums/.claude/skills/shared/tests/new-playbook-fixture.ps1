#Requires -Version 7
# Test helper: builds a throwaway git repo with a Memory Bank tree.
Set-StrictMode -Version Latest

function New-PlaybookRules([int] $Count, [string] $Prefix) {
    (1..$Count | ForEach-Object { "- **$Prefix pravidlo $_.**`n  Proč: důvod $Prefix $_.`n  Důkaz: abc$_." }) -join "`n"
}

function Write-PlaybookFixtureFile([string] $Root, [string] $Rel, [string] $Content) {
    $p = Join-Path $Root $Rel
    New-Item -ItemType Directory -Force (Split-Path $p) | Out-Null
    [IO.File]::WriteAllText($p, ($Content -replace "`r`n", "`n"), [Text.UTF8Encoding]::new($false))
}

function New-PlaybookFixtureRepo {
    $root = Join-Path ([IO.Path]::GetTempPath()) ("pbtree-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory $root | Out-Null
    git -C $root init -q -b main
    git -C $root config user.email t@example.invalid
    git -C $root config user.name test
    git -C $root config core.autocrlf false
    $sub = { param($title, $rules) "## Pro celý podstrom`n`n### Když $title`n`n$rules`n" }
    $own = { param($title, $rules) "## Jen pro tento projekt`n`n### Když $title`n`n$rules`n" }
    Write-PlaybookFixtureFile $root 'memory-bank/playbook.md' ("# Playbook — kořen`n`n" + (& $sub 'píšeš git' '- **ROOT-SUB pravidlo.** Proč: r. Důkaz: a1.'))
    Write-PlaybookFixtureFile $root 'memory-bank/brief.md' "# Brief`n"
    Write-PlaybookFixtureFile $root 'A/memory-bank/playbook.md' ("# Playbook — A`n`n" + (& $sub 'stavíš A' '- **A-SUB pravidlo.** Proč: a. Důkaz: a2.') + "`n" + (& $own 'ladíš A' '- **A-OWN pravidlo.** Proč: a. Důkaz: a3.'))
    Write-PlaybookFixtureFile $root 'A/B/memory-bank/playbook.md' ("# Playbook — B`n`n" + (& $own 'testuješ B' '- **B-OWN pravidlo.** Proč: b. Důkaz: a4.'))
    Write-PlaybookFixtureFile $root 'A/C/memory-bank/brief.md' "# Brief C`n"
    Write-PlaybookFixtureFile $root 'A/C/D/memory-bank/playbook.md' ("# Playbook — D`n`n" + (& $own 'testuješ D' '- **D-OWN pravidlo.** Proč: d. Důkaz: a5.'))
    Write-PlaybookFixtureFile $root 'L/memory-bank/playbook.md' "# Úkoly — L`n`n## Build`n`nL-LEGACY text.`n"
    Write-PlaybookFixtureFile $root 'L/M/memory-bank/playbook.md' ("# Playbook — M`n`n" + (& $own 'testuješ M' '- **M-OWN pravidlo.** Proč: m. Důkaz: a6.'))
    Write-PlaybookFixtureFile $root 'S1/memory-bank/playbook.md' ("# Playbook — S1`n`n" + (& $own 'píšeš SQL' '- **S1 pravidlo `sqlcmd`.** Proč: s. Důkaz: a7.'))
    Write-PlaybookFixtureFile $root 'S2/memory-bank/playbook.md' ("# Playbook — S2`n`n" + (& $own 'píšeš SQL' '- **S2 pravidlo `sqlcmd`.** Proč: s. Důkaz: a8.'))
    Write-PlaybookFixtureFile $root 'A/B/memory-bank/X/memory-bank/playbook.md' "# Vnořená`n"
    Write-PlaybookFixtureFile $root '.gitignore' "/DistOut/`n"
    Write-PlaybookFixtureFile $root 'DistOut/W/memory-bank/playbook.md' "# Kopie buildu`n"
    git -C $root add -A
    git -C $root commit -q -m fixture
    $root
}
