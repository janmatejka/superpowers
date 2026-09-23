#Requires -Version 7
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_assert.ps1')
# Hygiene of every test suite of the layer (contract/playbook-contract.md, "Retired rules and conversion to code").
#
# Detection runs on the PowerShell AST, not on regex over raw text (Ruling
# R9, fix round 1 of Task A6). Regex had two holes: a semicolon-joined
# dot-source line ". (Join-Path $PSScriptRoot '_assert.ps1'); . (Join-Path
# $PSScriptRoot 'subject.ps1')" matched as ONE line whose captured text
# contains "_assert.ps1", so the whole line was excluded and the subject
# dot-source became invisible to rule (b) (false negative). And the
# definition regex '(?m)^\s*function\s+(Assert-\w+)' matched literal text
# inside a here-string in a sibling file, so a fake "function Assert-Fake"
# living only inside a string counted as a real definition (false
# positive for rule (a)). Both are closed below by asking the AST what is
# actually a dot-source command / a real function definition, not what a
# line of text looks like.

function Get-UmsFileAst {
    param([string] $Path, [ref] $ParseErrors)
    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref] $tokens, [ref] $errors)
    if ($errors -and $errors.Count -gt 0) {
        $ParseErrors.Value = @($errors)
        return $null
    }
    $ParseErrors.Value = @()
    return $ast
}

function Get-UmsAssertDefinitions {
    param([System.Management.Automation.Language.Ast] $Ast)
    if ($null -eq $Ast) { return @() }
    $funcs = $Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    return @($funcs | Where-Object { $_.Name -match '^Assert-' } | ForEach-Object { $_.Name })
}

function Get-UmsAssertCalls {
    param([System.Management.Automation.Language.Ast] $Ast)
    if ($null -eq $Ast) { return @() }
    $cmds = $Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)
    return @($cmds | ForEach-Object { $_.GetCommandName() } | Where-Object { $_ -and $_ -match '^Assert-' })
}

function Get-UmsDotSourceTargets {
    param([System.Management.Automation.Language.Ast] $Ast)
    if ($null -eq $Ast) { return @() }
    $cmds = $Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.InvocationOperator -eq [System.Management.Automation.Language.TokenKind]::Dot }, $true)
    $targets = @($cmds | Where-Object { $_.CommandElements.Count -gt 0 } | ForEach-Object { $_.CommandElements[0].Extent.Text })
    return @($targets | Where-Object { $_ -notmatch '_assert\.ps1' })
}

function Test-UmsSetsErrorActionStop {
    param([System.Management.Automation.Language.Ast] $Ast)
    if ($null -eq $Ast) { return $false }
    $assigns = $Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true)
    foreach ($a in $assigns) {
        if ($a.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
            $a.Left.VariablePath.UserPath -eq 'ErrorActionPreference' -and
            $a.Right -is [System.Management.Automation.Language.CommandExpressionAst] -and
            $a.Right.Expression -is [System.Management.Automation.Language.StringConstantExpressionAst] -and
            $a.Right.Expression.Value -eq 'Stop') {
            return $true
        }
    }
    return $false
}

# --- Self-test: prove the two holes Ruling R9 named are closed, on
# synthetic fixtures built at run time under the system temp dir. Run this
# BEFORE trusting the real-layer scan below. ---
$selfTestDir = Join-Path ([IO.Path]::GetTempPath()) ("ums-hygiene-selftest-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $selfTestDir | Out-Null
try {
    # Finding 1: a semicolon-joined dot-source line must still surface the
    # non-_assert subject, and a suite without Stop must be seen as missing it.
    $semicolonSuite = Join-Path $selfTestDir 'semicolon.tests.ps1'
    [IO.File]::WriteAllText($semicolonSuite, @'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '_assert.ps1'); . (Join-Path $PSScriptRoot 'subject.ps1')
Assert-True $true 'ok'
'@)
    $perr1 = $null
    $semicolonAst = Get-UmsFileAst $semicolonSuite ([ref] $perr1)
    Assert-True ($perr1.Count -eq 0) 'self-test: semicolon fixture parses without AST errors'
    $dotSources = @(Get-UmsDotSourceTargets $semicolonAst)
    Assert-True ($dotSources.Count -eq 1 -and $dotSources[0] -match 'subject\.ps1') "self-test (finding 1 closed): a semicolon-joined dot-source line still yields the non-_assert subject $(if ($dotSources.Count -ne 1) { '(got: ' + ($dotSources -join '; ') + ')' })"
    Assert-True (-not (Test-UmsSetsErrorActionStop $semicolonAst)) 'self-test: a fixture without Stop is correctly seen as missing it'

    # Finding 2: text shaped like "function Assert-Fake { }" but living only
    # inside a here-string must not count as a real definition, and a suite
    # calling that name must be seen as calling an UNDEFINED assert.
    $heredocDir = Join-Path $selfTestDir 'heredoc-case'
    New-Item -ItemType Directory -Force -Path $heredocDir | Out-Null
    [IO.File]::WriteAllText((Join-Path $heredocDir '_assert.ps1'), '# fixture stub, not dot-sourced by the AST helpers directly')
    [IO.File]::WriteAllText((Join-Path $heredocDir 'helper.ps1'), @'
$s = @"
function Assert-Fake { }
"@
'@)
    $heredocSuite = Join-Path $heredocDir 'mysuite.tests.ps1'
    [IO.File]::WriteAllText($heredocSuite, @'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '_assert.ps1')
Assert-Fake $true 'ok'
'@)
    $perr2 = $null
    $heredocSuiteAst = Get-UmsFileAst $heredocSuite ([ref] $perr2)
    Assert-True ($perr2.Count -eq 0) 'self-test: heredoc-case suite parses without AST errors'
    $perr3 = $null
    $helperAst = Get-UmsFileAst (Join-Path $heredocDir 'helper.ps1') ([ref] $perr3)
    Assert-True ($perr3.Count -eq 0) 'self-test: heredoc-case helper parses without AST errors'
    $defs = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($d in @(Get-UmsAssertDefinitions $heredocSuiteAst) + @(Get-UmsAssertDefinitions $helperAst)) { [void]$defs.Add($d) }
    Assert-True (-not $defs.Contains('Assert-Fake')) 'self-test (finding 2 closed): function-shaped text inside a here-string is not counted as a real Assert-* definition'
    $calls = @(Get-UmsAssertCalls $heredocSuiteAst)
    $undef = @($calls | Where-Object { -not $defs.Contains($_) })
    Assert-True ($undef.Count -eq 1 -and $undef[0] -eq 'Assert-Fake') "self-test: the suite calling Assert-Fake is correctly seen as calling an undefined assert $(if ($undef.Count -ne 1) { '(got: ' + ($undef -join ', ') + ')' })"
}
finally {
    Remove-Item -Recurse -Force $selfTestDir -ErrorAction SilentlyContinue
}

# --- Real layer scan ---
$layer = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path   # ums/.claude
$suites = @(Get-ChildItem -Recurse -File -Path $layer -Filter '*.tests.ps1')
Assert-True ($suites.Count -ge 30) "found $($suites.Count) suites"
foreach ($s in $suites) {
    $rel = $s.FullName.Substring($layer.Length + 1)
    $perr = $null
    $suiteAst = Get-UmsFileAst $s.FullName ([ref] $perr)
    if ($perr.Count -gt 0) {
        Assert-True $false "$rel parses without AST errors (parse errors: $(($perr | ForEach-Object { $_.Message }) -join '; '))"
        continue
    }
    # (a) every Assert-* called is defined in the suite or in a .ps1 of its directory
    $defs = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($f in @($s) + @(Get-ChildItem -File -Path $s.DirectoryName -Filter '*.ps1')) {
        if ($f.FullName -eq $s.FullName) {
            $fAst = $suiteAst
        } else {
            $ferr = $null
            $fAst = Get-UmsFileAst $f.FullName ([ref] $ferr)
            if ($ferr.Count -gt 0) {
                $frel = $f.FullName.Substring($layer.Length + 1)
                Assert-True $false "$frel parses without AST errors (parse errors: $(($ferr | ForEach-Object { $_.Message }) -join '; '))"
                continue
            }
        }
        foreach ($d in @(Get-UmsAssertDefinitions $fAst)) { [void]$defs.Add($d) }
    }
    $called = @(Get-UmsAssertCalls $suiteAst | Sort-Object -Unique)
    $undef = @($called | Where-Object { -not $defs.Contains($_) })
    Assert-True ($undef.Count -eq 0) "$rel calls only defined asserts $(if ($undef.Count) { '(missing: ' + ($undef -join ', ') + ')' })"
    # (b) a suite that dot-sources its subject sets ErrorActionPreference Stop
    $dotSources = @(Get-UmsDotSourceTargets $suiteAst)
    if ($dotSources.Count) {
        Assert-True (Test-UmsSetsErrorActionStop $suiteAst) "$rel dot-sources its subject and sets ErrorActionPreference Stop"
    }
}
Complete-Tests
