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

# .env bez koncového konce řádku: značka nesmí slepit poslední řádek.
$dir = New-TempDir 'dotenv-no-eol'
[IO.File]::WriteAllText((Join-Path $dir '.env'), 'FOO=bar')
Set-AgentMarker $dir 'gemini'
$content = Get-Content -LiteralPath (Join-Path $dir '.env') -Raw
Assert-Match $content '(?m)^FOO=bar\r?$' 'gemini (.env bez EOL): cizí poslední řádek zůstal celý'
Assert-Match $content '(?m)^MB_AGENT_SESSION=1\r?$' 'gemini (.env bez EOL): značka je na vlastním řádku'
Remove-Item -Recurse -Force $dir

# --- qwen: .qwen/.env (stejný dotenv mechanismus jako gemini) -------------

$dir = New-TempDir 'qwen-none'
Set-AgentMarker $dir 'qwen'
$envFile = Join-Path $dir '.env'
Assert-True (Test-Path -LiteralPath $envFile) 'qwen (bez souboru): .env vznikl'
$content = Get-Content -LiteralPath $envFile -Raw
Assert-Match $content '(?m)^MB_AGENT_SESSION=1\r?$' 'qwen (bez souboru): .env dostal značku'
$size1 = (Get-Item -LiteralPath $envFile).Length
Set-AgentMarker $dir 'qwen'
Assert-Eq (Get-Item -LiteralPath $envFile).Length $size1 'qwen: druhý běh .env nezvětší'
Assert-Eq ([regex]::Matches((Get-Content -LiteralPath $envFile -Raw), 'MB_AGENT_SESSION').Count) 1 'qwen: značka jen jednou'
Remove-Item -Recurse -Force $dir

$dir = New-TempDir 'qwen-existing'
Set-Content -LiteralPath (Join-Path $dir '.env') -Value 'OPENAI_API_KEY=x' -Encoding utf8
Set-AgentMarker $dir 'qwen'
$content = Get-Content -LiteralPath (Join-Path $dir '.env') -Raw
Assert-Match $content 'OPENAI_API_KEY=x' 'qwen (existující .env): cizí řádek přežil'
Assert-Match $content 'MB_AGENT_SESSION=1' 'qwen (existující .env): značka přibyla'
Remove-Item -Recurse -Force $dir

# --- opencode: plugin s hookem shell.env ----------------------------------

$dir = New-TempDir 'opencode'
Set-AgentMarker $dir 'opencode'
$plugin = Join-Path $dir 'plugins\ums-agent-session.js'
Assert-True (Test-Path -LiteralPath $plugin) 'opencode: plugins\ums-agent-session.js vznikl'
$content = Get-Content -LiteralPath $plugin -Raw
Assert-Match $content 'shell\.env' 'opencode: plugin registruje hook shell.env'
Assert-Match $content 'output\.env\.MB_AGENT_SESSION\s*=\s*"1"' 'opencode: hook nastavuje MB_AGENT_SESSION = "1"'
Assert-Match $content 'export const \w+ = async' 'opencode: plugin exportuje pojmenovanou async funkci'
$hash1 = (Get-FileHash -LiteralPath $plugin).Hash
Set-AgentMarker $dir 'opencode'
Assert-Eq (Get-FileHash -LiteralPath $plugin).Hash $hash1 'opencode: druhý běh soubor nezmění'
Assert-Eq @(Get-ChildItem -Recurse -File $dir).Count 1 'opencode: vznikl jediný soubor'
# Cizí plugin vedle nesmí být dotčen.
Set-Content -LiteralPath (Join-Path $dir 'plugins\jiny.js') -Value 'export const X = async () => ({})' -Encoding utf8
Set-AgentMarker $dir 'opencode'
Assert-True (Test-Path -LiteralPath (Join-Path $dir 'plugins\jiny.js')) 'opencode: cizí plugin přežil'
# Ručně poškozený vlastní soubor se při dalším nasazení obnoví.
Set-Content -LiteralPath $plugin -Value '// poškozeno' -Encoding utf8
Set-AgentMarker $dir 'opencode'
Assert-Match (Get-Content -LiteralPath $plugin -Raw) 'shell\.env' 'opencode: poškozený vlastní plugin se obnoví'
Remove-Item -Recurse -Force $dir

# --- pi: kryje AI_AGENT fallback hooku, nic se nezapisuje -----------------

$dir = New-TempDir 'pi'
$err = $null
try { Set-AgentMarker $dir 'pi' } catch [System.NotSupportedException] { $err = $_.Exception.Message }
Assert-True ($null -ne $err) 'pi: Set-AgentMarker hlásí NotSupportedException'
Assert-Match ([string]$err) 'AI_AGENT' 'pi: hláška říká, že marker kryje AI_AGENT fallback'
Assert-Eq @(Get-ChildItem -Recurse -File $dir -ErrorAction SilentlyContinue).Count 0 'pi: nevznikl žádný soubor'
Remove-Item -Recurse -Force $dir

# --- hermes: jen profil - terminal.env_passthrough v config.yaml + .env ---

$dir = New-TempDir 'hermes-mono'
$err = $null
try { Set-AgentMarker $dir 'hermes' 'Monorepo' } catch [System.NotSupportedException] { $err = $_.Exception.Message }
Assert-True ($null -ne $err) 'hermes/Monorepo: NotSupportedException (mechanismus existuje jen v profilu)'
Assert-Match ([string]$err) 'hermes' 'hermes/Monorepo: hláška nese jméno harnessu'
Assert-Eq @(Get-ChildItem -Recurse -File $dir -ErrorAction SilentlyContinue).Count 0 'hermes/Monorepo: nevznikl žádný soubor'
Remove-Item -Recurse -Force $dir

function Get-HermesYamlPassthrough([string] $Dir) {
    Get-Content -LiteralPath (Join-Path $Dir 'config.yaml') -Raw
}

# bez souboru
$dir = New-TempDir 'hermes-none'
Set-AgentMarker $dir 'hermes' 'UserProfile'
$yaml = Get-HermesYamlPassthrough $dir
Assert-Match $yaml '(?m)^terminal:\r?$' 'hermes (bez souboru): config.yaml má klíč terminal'
Assert-Match $yaml '(?m)^  env_passthrough:\r?$' 'hermes (bez souboru): env_passthrough pod terminal'
Assert-Match $yaml '(?m)^    - MB_AGENT_SESSION\r?$' 'hermes (bez souboru): značka je položka seznamu'
Assert-Match (Get-Content -LiteralPath (Join-Path $dir '.env') -Raw) '(?m)^MB_AGENT_SESSION=1\r?$' 'hermes (bez souboru): .env má MB_AGENT_SESSION=1'
$s1 = (Get-Item -LiteralPath (Join-Path $dir 'config.yaml')).Length
$s2 = (Get-Item -LiteralPath (Join-Path $dir '.env')).Length
Set-AgentMarker $dir 'hermes' 'UserProfile'
Assert-Eq (Get-Item -LiteralPath (Join-Path $dir 'config.yaml')).Length $s1 'hermes: druhý běh config.yaml nezvětší'
Assert-Eq (Get-Item -LiteralPath (Join-Path $dir '.env')).Length $s2 'hermes: druhý běh .env nezvětší'
Remove-Item -Recurse -Force $dir

# terminal existuje bez env_passthrough
$dir = New-TempDir 'hermes-terminal'
Set-Content -LiteralPath (Join-Path $dir 'config.yaml') -Value "model: x`nterminal:`n  backend: local`nother: 1" -Encoding utf8
Set-AgentMarker $dir 'hermes' 'UserProfile'
$yaml = Get-HermesYamlPassthrough $dir
Assert-Match $yaml '(?m)^  backend: local\r?$' 'hermes (terminal bez passthrough): cizí klíč terminalu přežil'
Assert-Match $yaml '(?m)^other: 1\r?$' 'hermes (terminal bez passthrough): klíč za blokem přežil'
Assert-Match $yaml '(?s)terminal:.*env_passthrough:\s*\r?\n\s+- MB_AGENT_SESSION.*other: 1' 'hermes (terminal bez passthrough): seznam je uvnitř bloku terminal'
Remove-Item -Recurse -Force $dir

# env_passthrough: []
$dir = New-TempDir 'hermes-empty-list'
Set-Content -LiteralPath (Join-Path $dir 'config.yaml') -Value "terminal:`n  env_passthrough: []  # names" -Encoding utf8
Set-AgentMarker $dir 'hermes' 'UserProfile'
$yaml = Get-HermesYamlPassthrough $dir
Assert-True (-not ($yaml -match '\[\]')) 'hermes (prázdný seznam): prázdné [] zmizelo'
Assert-Match $yaml '(?m)^    - MB_AGENT_SESSION\r?$' 'hermes (prázdný seznam): značka je položka blokového seznamu'
Remove-Item -Recurse -Force $dir

# blokový seznam s cizí položkou
$dir = New-TempDir 'hermes-block-list'
Set-Content -LiteralPath (Join-Path $dir 'config.yaml') -Value "terminal:`n  env_passthrough:`n    - MY_KEY`nnext: 1" -Encoding utf8
Set-AgentMarker $dir 'hermes' 'UserProfile'
$yaml = Get-HermesYamlPassthrough $dir
Assert-Match $yaml '(?m)^    - MY_KEY\r?$' 'hermes (blokový seznam): cizí položka přežila'
Assert-Match $yaml '(?m)^    - MB_AGENT_SESSION\r?$' 'hermes (blokový seznam): značka přibyla'
Assert-Match $yaml '(?m)^next: 1\r?$' 'hermes (blokový seznam): klíč za blokem přežil'
Set-AgentMarker $dir 'hermes' 'UserProfile'
Assert-Eq ([regex]::Matches((Get-HermesYamlPassthrough $dir), 'MB_AGENT_SESSION').Count) 1 'hermes (blokový seznam): opakovaný běh značku neduplikuje'
Remove-Item -Recurse -Force $dir

# inline seznam s položkami
$dir = New-TempDir 'hermes-inline-list'
Set-Content -LiteralPath (Join-Path $dir 'config.yaml') -Value "terminal:`n  env_passthrough: [MY_KEY, OTHER]" -Encoding utf8
Set-AgentMarker $dir 'hermes' 'UserProfile'
$yaml = Get-HermesYamlPassthrough $dir
Assert-Match $yaml 'env_passthrough: \[MY_KEY, OTHER, MB_AGENT_SESSION\]' 'hermes (inline seznam): značka doplněna, cizí položky zachovány'
Remove-Item -Recurse -Force $dir

# jiná struktura, kterou neumíme bezpečně upravit: nepoškodit, jasně selhat
$dir = New-TempDir 'hermes-flow-map'
Set-Content -LiteralPath (Join-Path $dir 'config.yaml') -Value "terminal: { backend: local }" -Encoding utf8
$threwOther = $false
try { Set-AgentMarker $dir 'hermes' 'UserProfile' } catch [System.NotSupportedException] { } catch { $threwOther = $true }
Assert-True $threwOther 'hermes (terminal jako flow mapa): jasná výjimka místo tiché úpravy'
Assert-Eq (Get-Content -LiteralPath (Join-Path $dir 'config.yaml') -Raw).Trim() 'terminal: { backend: local }' 'hermes (terminal jako flow mapa): config.yaml nedotčen'
Remove-Item -Recurse -Force $dir

# CRLF soubor zůstane CRLF
$dir = New-TempDir 'hermes-crlf'
[IO.File]::WriteAllText((Join-Path $dir 'config.yaml'), "terminal:`r`n  backend: local`r`n")
Set-AgentMarker $dir 'hermes' 'UserProfile'
$raw = [IO.File]::ReadAllText((Join-Path $dir 'config.yaml'))
Assert-True (-not ($raw -match "(?<!`r)`n")) 'hermes (CRLF): žádný holý LF, konce řádků zachovány'
Assert-Match $raw '- MB_AGENT_SESSION' 'hermes (CRLF): značka přibyla'
Remove-Item -Recurse -Force $dir

# --- harnessy bez mechanismu: cursor (nedoloženo) --------------------------

$dir = New-TempDir 'cursor'
$threw = $false
try {
    Set-AgentMarker $dir 'cursor'
}
catch [System.NotSupportedException] {
    $threw = $true
    Assert-Match $_.Exception.Message 'cursor' 'cursor: hláška nese jméno harnessu'
}
Assert-True $threw 'cursor: Set-AgentMarker hlásí NotSupportedException (žádný zdokumentovaný mechanismus, ne tichý úspěch)'
$anyFile = @(Get-ChildItem -Recurse -File $dir -ErrorAction SilentlyContinue)
Assert-Eq $anyFile.Count 0 'cursor: nevznikl žádný soubor, který by jen předstíral konfiguraci'
Remove-Item -Recurse -Force $dir

Complete-Tests
