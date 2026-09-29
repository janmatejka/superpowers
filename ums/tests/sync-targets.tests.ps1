Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '_assert.ps1')
$ErrorActionPreference = 'Stop'

# Get-UmsSyncTargets je jediný zdroj pravdy o tom, kam který harness čte
# skilly, instrukce a kde má konfigurační adresář. Test běží čistě nad řetězci
# cest: nic nezapisuje, na disk nesahá (živé monorepo ani profil se netýká).
. (Join-Path $PSScriptRoot '..\sync-with-monorepo.ps1') -DotSourceOnly

$allAgents = @('claude', 'codex', 'gemini', 'qwen', 'opencode', 'pi', 'hermes',
    'cursor', 'copilot', 'devin', 'droid', 'kimi', 'muse', 'antigravity', 'grok')
$validMarkers = @('settings-env', 'codex-toml', 'dotenv', 'opencode-plugin', 'pi-prefix', 'hermes-passthrough', 'none')

function Get-One([string] $Agent, [string] $Scope, [string] $Root = 'C:\r') {
    $rows = @(Get-UmsSyncTargets -Agent $Agent -Scope $Scope -Root $Root)
    Assert-Eq $rows.Count 1 "$Agent/${Scope}: presně jeden řádek"
    return $rows[0]
}

# --- hodnoty z tabulky návrhu 3.6 -------------------------------------------

$t = Get-One 'claude' 'Monorepo'
Assert-Eq $t.Agent 'claude' 'claude/Monorepo: Agent'
Assert-Eq $t.SkillsDir 'C:\r\.claude\skills' 'claude/Monorepo: SkillsDir'
Assert-Eq $t.ConfigDir 'C:\r\.claude' 'claude/Monorepo: ConfigDir'
Assert-Eq $t.Instructions 'C:\r\CLAUDE.md' 'claude/Monorepo: Instructions'
Assert-Eq $t.Marker 'settings-env' 'claude/Monorepo: Marker'

$t = Get-One 'claude' 'UserProfile'
Assert-Eq $t.Instructions 'C:\r\.claude\CLAUDE.md' 'claude/UserProfile: Instructions'

$t = Get-One 'claude' 'Fork'
Assert-Eq $t.SkillsDir 'C:\r\.claude\skills' 'claude/Fork: SkillsDir'
Assert-Eq $t.ConfigDir 'C:\r\.claude' 'claude/Fork: ConfigDir'
Assert-True ($null -eq $t.Instructions) 'claude/Fork: Instructions je $null (CLAUDE.md forku je ruční)'

$t = Get-One 'codex' 'Monorepo'
Assert-Eq $t.SkillsDir 'C:\r\.agents\skills' 'codex/Monorepo: SkillsDir'
Assert-Eq $t.ConfigDir 'C:\r\.codex' 'codex/Monorepo: ConfigDir'
Assert-Eq $t.Instructions 'C:\r\AGENTS.md' 'codex/Monorepo: Instructions'
Assert-Eq $t.Marker 'codex-toml' 'codex/Monorepo: Marker'
$t = Get-One 'codex' 'UserProfile'
Assert-Eq $t.Instructions 'C:\r\.codex\AGENTS.md' 'codex/UserProfile: Instructions'

$t = Get-One 'gemini' 'Monorepo'
Assert-Eq $t.SkillsDir 'C:\r\.agents\skills' 'gemini/Monorepo: SkillsDir je .agents\skills'
Assert-Eq $t.Instructions 'C:\r\GEMINI.md' 'gemini/Monorepo: Instructions'
Assert-Eq $t.Marker 'dotenv' 'gemini/Monorepo: Marker'
$t = Get-One 'gemini' 'UserProfile'
Assert-Eq $t.Instructions 'C:\r\.gemini\GEMINI.md' 'gemini/UserProfile: Instructions'

$t = Get-One 'qwen' 'UserProfile'
Assert-Eq $t.SkillsDir 'C:\r\.qwen\skills' 'qwen/UserProfile: SkillsDir'
Assert-Eq $t.ConfigDir 'C:\r\.qwen' 'qwen/UserProfile: ConfigDir'
Assert-Eq $t.Instructions 'C:\r\.qwen\QWEN.md' 'qwen/UserProfile: Instructions'
Assert-Eq $t.Marker 'dotenv' 'qwen/UserProfile: Marker'
$t = Get-One 'qwen' 'Monorepo'
Assert-Eq $t.SkillsDir 'C:\r\.qwen\skills' 'qwen/Monorepo: SkillsDir'
Assert-Eq $t.Instructions 'C:\r\QWEN.md' 'qwen/Monorepo: Instructions'

$t = Get-One 'opencode' 'Monorepo'
Assert-Eq $t.SkillsDir 'C:\r\.agents\skills' 'opencode/Monorepo: SkillsDir'
Assert-Eq $t.ConfigDir 'C:\r\.opencode' 'opencode/Monorepo: ConfigDir'
Assert-Eq $t.Instructions 'C:\r\AGENTS.md' 'opencode/Monorepo: Instructions'
Assert-Eq $t.Marker 'opencode-plugin' 'opencode/Monorepo: Marker'
$t = Get-One 'opencode' 'UserProfile'
Assert-Eq $t.SkillsDir 'C:\r\.agents\skills' 'opencode/UserProfile: SkillsDir'
Assert-Eq $t.ConfigDir 'C:\r\.config\opencode' 'opencode/UserProfile: ConfigDir'
Assert-Eq $t.Instructions 'C:\r\.config\opencode\AGENTS.md' 'opencode/UserProfile: Instructions'

$t = Get-One 'pi' 'Monorepo'
Assert-Eq $t.SkillsDir 'C:\r\.agents\skills' 'pi/Monorepo: SkillsDir'
Assert-Eq $t.ConfigDir 'C:\r\.pi' 'pi/Monorepo: ConfigDir'
Assert-Eq $t.Marker 'none' 'pi/Monorepo: Marker none (kryje AI_AGENT fallback)'
$t = Get-One 'pi' 'UserProfile'
Assert-Eq $t.ConfigDir 'C:\r\.pi\agent' 'pi/UserProfile: ConfigDir'
Assert-Eq $t.Instructions 'C:\r\.pi\agent\AGENTS.md' 'pi/UserProfile: Instructions'

$t = Get-One 'hermes' 'Monorepo'
Assert-Eq $t.SkillsDir 'C:\r\.agents\skills' 'hermes/Monorepo: SkillsDir'
Assert-Eq $t.Instructions 'C:\r\.hermes.md' 'hermes/Monorepo: Instructions'
Assert-True ($null -eq $t.ConfigDir) 'hermes/Monorepo: bez projektového configu -> ConfigDir $null'
Assert-Eq $t.Marker 'none' 'hermes/Monorepo: Marker none (mechanismus jen v profilu)'
$t = Get-One 'hermes' 'UserProfile'
Assert-Eq $t.SkillsDir 'C:\r\.hermes\skills' 'hermes/UserProfile: SkillsDir'
Assert-Eq $t.ConfigDir 'C:\r\.hermes' 'hermes/UserProfile: ConfigDir'
Assert-True ($null -eq $t.Instructions) 'hermes/UserProfile: bez instrukčního souboru'
Assert-Eq $t.Marker 'hermes-passthrough' 'hermes/UserProfile: Marker'

$t = Get-One 'grok' 'Monorepo'
Assert-Eq $t.SkillsDir 'C:\r\.grok\skills' 'grok/Monorepo: SkillsDir'
Assert-Eq $t.Instructions 'C:\r\AGENTS.md' 'grok/Monorepo: Instructions'
$t = Get-One 'grok' 'UserProfile'
Assert-Eq $t.SkillsDir 'C:\r\.grok\skills' 'grok/UserProfile: SkillsDir'
Assert-True ($null -eq $t.Instructions) 'grok/UserProfile: bez instrukčního souboru'

$t = Get-One 'copilot' 'Monorepo'
Assert-Eq $t.Instructions 'C:\r\.github\copilot-instructions.md' 'copilot/Monorepo: Instructions'
$t = Get-One 'antigravity' 'UserProfile'
Assert-Eq $t.SkillsDir 'C:\r\.gemini\antigravity-cli\skills' 'antigravity/UserProfile: SkillsDir'
$t = Get-One 'antigravity' 'Monorepo'
Assert-Eq $t.SkillsDir 'C:\r\.agents\skills' 'antigravity/Monorepo: SkillsDir'

$t = Get-One 'cursor' 'Monorepo'
Assert-Eq $t.Marker 'none' 'cursor: Marker none (nedoloženo)'
Assert-Eq $t.SkillsDir 'C:\r\.agents\skills' 'cursor/Monorepo: SkillsDir'

# --- všech 15 harnessů, všechny scope --------------------------------------

foreach ($sc in 'Monorepo', 'UserProfile', 'Fork') {
    $rows = @(Get-UmsSyncTargets -Agent $allAgents -Scope $sc -Root 'C:\r')
    Assert-Eq $rows.Count 15 "$sc`: 15 harnessů"
    Assert-Eq (($rows | ForEach-Object { $_.Agent }) -join ',') ($allAgents -join ',') "$sc`: pořadí a jména podle vstupu"
    foreach ($r in $rows) {
        Assert-True ($r.Marker -in $validMarkers) "$sc/$($r.Agent): Marker '$($r.Marker)' je z povolené množiny"
        foreach ($p in 'SkillsDir', 'ConfigDir', 'Instructions') {
            $v = $r.$p
            Assert-True (($null -eq $v) -or [IO.Path]::IsPathRooted($v)) "$sc/$($r.Agent): $p je absolutní nebo `$null"
        }
        Assert-True ($null -ne $r.SkillsDir) "$sc/$($r.Agent): každý harness má adresář skillů"
        if ($sc -eq 'Fork') {
            Assert-True ($null -eq $r.Instructions) "Fork/$($r.Agent): Instructions je vždy `$null"
        }
    }
}
$noArg = @(Get-UmsSyncTargets -Scope Monorepo -Root 'C:\r')
Assert-Eq $noArg.Count 15 'bez -Agent: vrátí všech 15'

# Sdílené cíle: jeden adresář skillů pro víc harnessů se pozná porovnáním cest.
$shared = @(Get-UmsSyncTargets -Agent 'codex', 'gemini', 'pi' -Scope Monorepo -Root 'C:\r' | ForEach-Object { $_.SkillsDir } | Select-Object -Unique)
Assert-Eq $shared.Count 1 'codex, gemini, pi sdílejí jediný SkillsDir'

# --- chyby -----------------------------------------------------------------

function Get-ThrownMessage([scriptblock] $Body) {
    try { & $Body | Out-Null; return $null } catch { return $_.Exception.Message }
}
$msg = Get-ThrownMessage { Get-UmsSyncTargets -Agent 'kilocode' -Scope Monorepo -Root 'C:\r' }
Assert-True ($null -ne $msg) 'kilocode: výjimka (harness zrušen)'
Assert-Match ([string]$msg) 'kilocode' 'kilocode: hláška nese jméno agenta'
$msg = Get-ThrownMessage { Get-UmsSyncTargets -Agent 'claude', 'nesmysl' -Scope Monorepo -Root 'C:\r' }
Assert-Match ([string]$msg) 'nesmysl' 'neznámý agent uprostřed seznamu: hláška nese jeho jméno'
$msg = Get-ThrownMessage { Get-UmsSyncTargets -Agent 'claude' -Scope 'Nowhere' -Root 'C:\r' }
Assert-True ($null -ne $msg) 'neznámý scope: výjimka'

# --- skript už nenese starou tabulku ---------------------------------------
$script = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\sync-with-monorepo.ps1') -Raw
Assert-True (-not ($script -match '\$AgentTargets\s*=')) 'skript už nedefinuje $AgentTargets'
Assert-True (-not ($script -match "(?m)^\s*kilocode\s*=")) 'skript už nemá řádek tabulky kilocode'

Complete-Tests
