Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '_assert.ps1')
$ErrorActionPreference = 'Stop'

# Bez značky se hook v daném harnessu sám vypne, takže by tam agent běžel
# úplně bez dozoru - ne jen bez předběžného varování. settings.json se na
# ne-Claude cíle záměrně nenasazuje, proto vlastní injektáž do dokumentovaného
# env-injection mechanismu každého harnesse (viz komentáře u Set-AgentMarker
# v sync-with-monorepo.ps1 s citacemi dokumentace).
. (Join-Path $PSScriptRoot '..\..\..\sync-with-monorepo.ps1') -DotSourceOnly

function New-TempDir([string] $Label) {
    $dir = Join-Path ([IO.Path]::GetTempPath()) ("mbmarker-$Label-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    return $dir
}

# --- codex: config.toml [shell_environment_policy] "set" inline table -----

# Žádný soubor -> vznikne nová sekce se `set` tabulkou.
$dir = New-TempDir 'codex-none'
Set-AgentMarker $dir 'codex'
$content = Get-Content -LiteralPath (Join-Path $dir 'config.toml') -Raw
Assert-Match $content '\[shell_environment_policy\]' 'codex (bez souboru): sekce shell_environment_policy vznikla'
Assert-Match $content 'MB_AGENT_SESSION\s*=\s*"1"' 'codex (bez souboru): značka je v set tabulce'
Set-AgentMarker $dir 'codex'
$again = Get-Content -LiteralPath (Join-Path $dir 'config.toml') -Raw
Assert-Eq ([regex]::Matches($again, 'MB_AGENT_SESSION').Count) 1 'codex (bez souboru): opakovaný běh značku neduplikuje'
Remove-Item -Recurse -Force $dir

# Soubor existuje, má jiné sekce, ale žádnou shell_environment_policy.
$dir = New-TempDir 'codex-other-section'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
Set-Content -LiteralPath (Join-Path $dir 'config.toml') -Value "model = `"gpt-5`"`n`n[mcp_servers.foo]`ncommand = `"foo`"" -Encoding utf8
Set-AgentMarker $dir 'codex'
$content = Get-Content -LiteralPath (Join-Path $dir 'config.toml') -Raw
Assert-Match $content 'model = "gpt-5"' 'codex (jiná sekce): původní obsah přežil'
Assert-Match $content '\[mcp_servers\.foo\]' 'codex (jiná sekce): původní sekce přežila'
Assert-Match $content 'MB_AGENT_SESSION\s*=\s*"1"' 'codex (jiná sekce): značka přibyla'
Remove-Item -Recurse -Force $dir

# Sekce existuje, ale bez `set` řádku.
$dir = New-TempDir 'codex-section-no-set'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
Set-Content -LiteralPath (Join-Path $dir 'config.toml') -Value "[shell_environment_policy]`ninherit = `"core`"" -Encoding utf8
Set-AgentMarker $dir 'codex'
$content = Get-Content -LiteralPath (Join-Path $dir 'config.toml') -Raw
Assert-Match $content 'inherit = "core"' 'codex (sekce bez set): původní klíč přežil'
Assert-Match $content 'set = \{ MB_AGENT_SESSION = "1" \}' 'codex (sekce bez set): set řádek vznikl se značkou'
Remove-Item -Recurse -Force $dir

# Sekce i `set` tabulka existují s cizím klíčem, který musí přežít.
$dir = New-TempDir 'codex-existing-set'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
Set-Content -LiteralPath (Join-Path $dir 'config.toml') -Value "[shell_environment_policy]`ninherit = `"core`"`nset = { MY_FLAG = `"1`" }" -Encoding utf8
Set-AgentMarker $dir 'codex'
$content = Get-Content -LiteralPath (Join-Path $dir 'config.toml') -Raw
Assert-Match $content 'MY_FLAG = "1"' 'codex (existující set): cizí klíč v set tabulce přežil'
Assert-Match $content 'MB_AGENT_SESSION = "1"' 'codex (existující set): značka přibyla do téže tabulky'
Assert-Eq ([regex]::Matches($content, '(?m)^set\s*=').Count) 1 'codex (existující set): pořád jen jedna set tabulka, ne druhá'
Set-AgentMarker $dir 'codex'
$again = Get-Content -LiteralPath (Join-Path $dir 'config.toml') -Raw
Assert-Eq ([regex]::Matches($again, 'MB_AGENT_SESSION').Count) 1 'codex (existující set): opakovaný běh značku neduplikuje'
Remove-Item -Recurse -Force $dir

# --- gemini: .env soubor v konfiguračním adresáři harnesse -----------------

$dir = New-TempDir 'gemini-none'
Set-AgentMarker $dir 'gemini'
$content = Get-Content -LiteralPath (Join-Path $dir '.env') -Raw
Assert-Match $content '(?m)^MB_AGENT_SESSION=1\r?$' 'gemini (bez souboru): .env dostal značku'
Set-AgentMarker $dir 'gemini'
$again = Get-Content -LiteralPath (Join-Path $dir '.env') -Raw
Assert-Eq ([regex]::Matches($again, 'MB_AGENT_SESSION').Count) 1 'gemini (bez souboru): opakovaný běh značku neduplikuje'
Remove-Item -Recurse -Force $dir

$dir = New-TempDir 'gemini-existing'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
Set-Content -LiteralPath (Join-Path $dir '.env') -Value 'FOO=bar' -Encoding utf8
Set-AgentMarker $dir 'gemini'
$content = Get-Content -LiteralPath (Join-Path $dir '.env') -Raw
Assert-Match $content 'FOO=bar' 'gemini (existující .env): cizí řádek přežil'
Assert-Match $content 'MB_AGENT_SESSION=1' 'gemini (existující .env): značka přibyla'
Remove-Item -Recurse -Force $dir

# --- kilocode: žádný zdokumentovaný mechanismus - otevřená mezera ----------

$dir = New-TempDir 'kilocode'
$threw = $false
try {
    Set-AgentMarker $dir 'kilocode'
}
catch [System.NotSupportedException] {
    $threw = $true
}
Assert-True $threw 'kilocode: Set-AgentMarker hlásí NotSupportedException (žádný zdokumentovaný mechanismus, ne tichý úspěch)'
$anyFile = @(Get-ChildItem -Recurse -File $dir -ErrorAction SilentlyContinue)
Assert-Eq $anyFile.Count 0 'kilocode: nevznikl žádný soubor, který by jen předstíral konfiguraci'
Remove-Item -Recurse -Force $dir

Complete-Tests
