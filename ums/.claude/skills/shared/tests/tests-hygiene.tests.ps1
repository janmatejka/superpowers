#Requires -Version 7
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_assert.ps1')
# Hygiene of every test suite of the layer (contract/playbook-contract.md, "Retired rules and conversion to code").
$layer = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path   # ums/.claude
$suites = @(Get-ChildItem -Recurse -File -Path $layer -Filter '*.tests.ps1')
Assert-True ($suites.Count -ge 30) "found $($suites.Count) suites"
foreach ($s in $suites) {
    $text = [IO.File]::ReadAllText($s.FullName)
    $rel = $s.FullName.Substring($layer.Length + 1)
    # (a) every Assert-* called is defined in the suite or in a .ps1 of its directory
    $defs = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($f in @($s) + @(Get-ChildItem -File -Path $s.DirectoryName -Filter '*.ps1')) {
        foreach ($m in [regex]::Matches([IO.File]::ReadAllText($f.FullName), '(?m)^\s*function\s+(Assert-\w+)')) { [void]$defs.Add($m.Groups[1].Value) }
    }
    $called = @([regex]::Matches($text, '(?<![\w-])(Assert-\w+)') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
    $undef = @($called | Where-Object { -not $defs.Contains($_) })
    Assert-True ($undef.Count -eq 0) "$rel calls only defined asserts $(if ($undef.Count) { '(missing: ' + ($undef -join ', ') + ')' })"
    # (b) a suite that dot-sources its subject sets ErrorActionPreference Stop
    $dotSources = @([regex]::Matches($text, '(?m)^\s*\.\s+(.+)$') | ForEach-Object { $_.Groups[1].Value } | Where-Object { $_ -notmatch "_assert\.ps1" })
    if ($dotSources.Count) {
        Assert-Match $text "(?m)^\s*\`$ErrorActionPreference\s*=\s*'Stop'" "$rel dot-sources its subject and sets ErrorActionPreference Stop"
    }
}
Complete-Tests
