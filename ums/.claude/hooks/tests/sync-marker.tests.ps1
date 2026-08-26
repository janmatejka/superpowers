Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '_assert.ps1')
$ErrorActionPreference = 'Stop'

# Bez znacky se hook v danem harnessu sam vypne, takze by tam agent bezel
# uplne bez dozoru - ne jen bez predbezneho varovani. settings.json se na
# ne-Claude cile zamerne nenasazuje, proto vlastni injektaz do dokumentovaneho
# env-injection mechanismu kazdeho harnesse (viz komentare u Set-AgentMarker
# v sync-with-monorepo.ps1 s citacemi dokumentace).
. (Join-Path $PSScriptRoot '..\..\..\sync-with-monorepo.ps1') -DotSourceOnly

function New-TempDir([string] $Label) {
    $dir = Join-Path ([IO.Path]::GetTempPath()) ("mbmarker-$Label-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    return $dir
}

# --- codex: config.toml [shell_environment_policy] "set" inline table -----

# Zadny soubor -> vznikne nova sekce se `set` tabulkou.
$dir = New-TempDir 'codex-none'
Set-AgentMarker $dir 'codex'
$content = Get-Content -LiteralPath (Join-Path $dir 'config.toml') -Raw
Assert-Match $content '\[shell_environment_policy\]' 'codex (bez souboru): sekce shell_environment_policy vznikla'
Assert-Match $content 'MB_AGENT_SESSION\s*=\s*"1"' 'codex (bez souboru): znacka je v set tabulce'
Set-AgentMarker $dir 'codex'
$again = Get-Content -LiteralPath (Join-Path $dir 'config.toml') -Raw
Assert-Eq ([regex]::Matches($again, 'MB_AGENT_SESSION').Count) 1 'codex (bez souboru): opakovany beh znacku neduplikuje'
Remove-Item -Recurse -Force $dir

# Soubor existuje, ma jine sekce, ale zadnou shell_environment_policy.
$dir = New-TempDir 'codex-other-section'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
Set-Content -LiteralPath (Join-Path $dir 'config.toml') -Value "model = `"gpt-5`"`n`n[mcp_servers.foo]`ncommand = `"foo`"" -Encoding utf8
Set-AgentMarker $dir 'codex'
$content = Get-Content -LiteralPath (Join-Path $dir 'config.toml') -Raw
Assert-Match $content 'model = "gpt-5"' 'codex (jina sekce): puvodni obsah prezil'
Assert-Match $content '\[mcp_servers\.foo\]' 'codex (jina sekce): puvodni sekce prezila'
Assert-Match $content 'MB_AGENT_SESSION\s*=\s*"1"' 'codex (jina sekce): znacka pribyla'
Remove-Item -Recurse -Force $dir

# Sekce existuje, ale bez `set` radku.
$dir = New-TempDir 'codex-section-no-set'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
Set-Content -LiteralPath (Join-Path $dir 'config.toml') -Value "[shell_environment_policy]`ninherit = `"core`"" -Encoding utf8
Set-AgentMarker $dir 'codex'
$content = Get-Content -LiteralPath (Join-Path $dir 'config.toml') -Raw
Assert-Match $content 'inherit = "core"' 'codex (sekce bez set): puvodni klic prezil'
Assert-Match $content 'set = \{ MB_AGENT_SESSION = "1" \}' 'codex (sekce bez set): set radek vznikl se znackou'
Remove-Item -Recurse -Force $dir

# Sekce i `set` tabulka existuji s cizim klicem, ktery musi prezit.
$dir = New-TempDir 'codex-existing-set'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
Set-Content -LiteralPath (Join-Path $dir 'config.toml') -Value "[shell_environment_policy]`ninherit = `"core`"`nset = { MY_FLAG = `"1`" }" -Encoding utf8
Set-AgentMarker $dir 'codex'
$content = Get-Content -LiteralPath (Join-Path $dir 'config.toml') -Raw
Assert-Match $content 'MY_FLAG = "1"' 'codex (existujici set): cizi klic v set tabulce prezil'
Assert-Match $content 'MB_AGENT_SESSION = "1"' 'codex (existujici set): znacka pribyla do te same tabulky'
Assert-Eq ([regex]::Matches($content, '(?m)^set\s*=').Count) 1 'codex (existujici set): porad jen jedna set tabulka, ne druha'
Set-AgentMarker $dir 'codex'
$again = Get-Content -LiteralPath (Join-Path $dir 'config.toml') -Raw
Assert-Eq ([regex]::Matches($again, 'MB_AGENT_SESSION').Count) 1 'codex (existujici set): opakovany beh znacku neduplikuje'
Remove-Item -Recurse -Force $dir

# --- gemini: .env soubor v konfiguracnim adresari harnesse -----------------

$dir = New-TempDir 'gemini-none'
Set-AgentMarker $dir 'gemini'
$content = Get-Content -LiteralPath (Join-Path $dir '.env') -Raw
Assert-Match $content '(?m)^MB_AGENT_SESSION=1\r?$' 'gemini (bez souboru): .env dostal znacku'
Set-AgentMarker $dir 'gemini'
$again = Get-Content -LiteralPath (Join-Path $dir '.env') -Raw
Assert-Eq ([regex]::Matches($again, 'MB_AGENT_SESSION').Count) 1 'gemini (bez souboru): opakovany beh znacku neduplikuje'
Remove-Item -Recurse -Force $dir

$dir = New-TempDir 'gemini-existing'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
Set-Content -LiteralPath (Join-Path $dir '.env') -Value 'FOO=bar' -Encoding utf8
Set-AgentMarker $dir 'gemini'
$content = Get-Content -LiteralPath (Join-Path $dir '.env') -Raw
Assert-Match $content 'FOO=bar' 'gemini (existujici .env): cizi radek prezil'
Assert-Match $content 'MB_AGENT_SESSION=1' 'gemini (existujici .env): znacka pribyla'
Remove-Item -Recurse -Force $dir

# --- kilocode: zadny zdokumentovany mechanismus - otevrena mezera ----------

$dir = New-TempDir 'kilocode'
$threw = $false
try {
    Set-AgentMarker $dir 'kilocode'
}
catch [System.NotSupportedException] {
    $threw = $true
}
Assert-True $threw 'kilocode: Set-AgentMarker hlasi NotSupportedException (zadny zdokumentovany mechanismus, ne tichy uspech)'
$anyFile = @(Get-ChildItem -Recurse -File $dir -ErrorAction SilentlyContinue)
Assert-Eq $anyFile.Count 0 'kilocode: nevznikl zadny soubor, ktery by jen predstiral konfiguraci'
Remove-Item -Recurse -Force $dir

Complete-Tests
