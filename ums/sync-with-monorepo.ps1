<#
.SYNOPSIS
    Syncs the UMS Memory Bank integration layer between this fork branch
    (ums-memory-bank, directory ums/) and a deployment target: the UMS
    monorepo (default) or the current user's profile. Claude Code in the
    monorepo is two-way; every other combination is a one-way deploy.

.DESCRIPTION
    Agent 'claude' + Scope 'Monorepo' (default) — two-way sync of the
    UMS-owned file set (everything in the monorepo's .claude/ EXCEPT the 14
    vendored superpowers skill directories):

      FromMonorepo (default):  <monorepo>/.claude/*  ->  <fork>/ums/.claude/*
                               <monorepo>/CLAUDE.md  ->  <fork>/ums/CLAUDE.md.sample
      ToMonorepo:              the reverse

    The monorepo is the LIVE deployment and the normal master copy; run the
    default direction after changing the layer in the monorepo.

    Every other combination — other agents (the 15 harnesses superpowers supports) and/or
    Scope 'UserProfile' — is a one-way DEPLOY from this fork's ums/ layer
    (the Direction parameter is ignored):
      * the skills content (shared/ contract + mb-* utilities) into the
        agent's skills directory, where the agent supports one,
      * glue artifacts (hooks/, scripts/, and any future non-settings items
        of ums/.claude) into the agent's config directory — merged file-by-
        file, never wiping existing content; settings.json is deliberately
        NOT deployed (it is Claude Code's registration file and would clobber
        e.g. an existing .gemini/settings.json — hook registration is manual
        per harness),
      * the CLAUDE.md.sample preference block into the agent's instructions
        file, wrapped in UMS-MEMORY-BANK BEGIN/END markers (re-runs replace
        the marked block in place). UserProfile deploys prepend a scoping
        line so the rules apply only when working in the UMS monorepo.
    Per-agent target paths (per scope) live in the table inside
    Get-UmsSyncTargets — adjust there if a harness expects a different layout.

    Vendored superpowers skills are never synced by this script - they are
    produced in the monorepo by .claude/scripts/revendor-superpowers.ps1
    from this repo's skills/ tree.

    Scope 'Fork' deploys the layer into the fork's OWN root (git toplevel of
    -ForkUmsDir) without dirtying its working tree, replacing the manual refresh
    of the deployed copy. -Agent takes a list (claude,codex); targets shared by
    several harnesses (.agents/skills) are written once:
      * claude: .claude/ - settings.json, hooks/, scripts/revendor-superpowers.ps1,
        skills/shared, skills/mb-*, plus the vendored superpowers skills;
      * every other harness: shared/, mb-* and the vendored skills in its skills
        directory only (no glue, no marker, no instructions file);
      * instruction files are never written (the fork's CLAUDE.md is manual,
        AGENTS.md is an upstream file);
      * every deployed directory git does not ignore is added, idempotently, to
        .git/info/exclude (.gitignore stays untouched);
      * the pre-push hook is installed into the fork.
    A target's shared/VENDORED_FROM.md is never overwritten by the mirror of
    shared/: the revendor owns it and needs the previous pin to drop skills that
    left the pin.

    Run WITHOUT parameters in an interactive console to be prompted for each
    parameter with its default offered (Enter accepts the default). In a
    non-interactive context (redirected stdin, pwsh -NonInteractive) the
    defaults are used silently, so automation keeps working.
#>
#Requires -Version 7
[CmdletBinding()]
param(
    [ValidateSet('FromMonorepo', 'ToMonorepo')]
    [string]$Direction = 'FromMonorepo',
    # One or more of the 15 harnesses (claude, codex, gemini, qwen, opencode, pi,
    # hermes, cursor, copilot, devin, droid, kimi, muse, antigravity, grok). Every
    # value is split on commas ('-Agent claude,codex' arrives as ONE string) and
    # validated against the target table, not by ValidateSet, for that reason.
    [string[]]$Agent = @('claude'),
    [ValidateSet('Monorepo', 'UserProfile', 'Fork')]
    [string]$Scope = 'Monorepo',
    [string]$MonorepoRoot = 'D:\_datasys\ums',
    [string]$ForkUmsDir = $PSScriptRoot,
    # Test/advanced override of the user-profile root used by -Scope UserProfile.
    [string]$UserProfileRoot = $HOME,
    # Deploy over a target that has drifted from the last deployment. Accepted
    # here; the drift check it overrides is wired in a later step.
    [switch] $Force,
    # Dot-source this script to reuse its function definitions in tests,
    # without running the interactive/sync body below.
    [switch] $DotSourceOnly
)

$AGENT_MARKER_NAME = 'MB_AGENT_SESSION'

# The agent-session marker must reach EVERY harness, or the pre-push hook
# disables itself there and the agent runs unsupervised. settings.json is
# Claude Code's registration format and is deliberately not deployed to the
# other targets, so the marker is written into each harness's own,
# documented environment-injection mechanism instead:
#   codex    - config.toml [shell_environment_policy] "set" inline table.
#              Confirmed at https://learn.chatgpt.com/docs/config-file/config-advanced
#              ("set" injects custom env vars into spawned subprocesses,
#              including git). A bare top-level [env] table - what an
#              earlier round of this function wrote - is NOT read by Codex.
#   gemini   - .env file in the agent's own config dir (~/.gemini/.env or
#              ./.gemini/.env). Confirmed at
#              https://google-gemini.github.io/gemini-cli/docs/get-started/configuration.html
#              and https://geminicli.com/docs/reference/configuration/ :
#              settings.json has NO env-injection key at all (an earlier
#              round wrote "env" into settings.json, which Gemini CLI never
#              reads); .env loading is the only documented mechanism.
#   qwen     - .env file in the agent's own config dir (.qwen/.env). Confirmed
#              at https://raw.githubusercontent.com/QwenLM/qwen-code/main/docs/users/configuration/auth.md
#              (Qwen Code docs, 2026-09-29): ".qwen/.env" is searched first
#              (then ".env", "~/.qwen/.env", "~/.env"), the first file found
#              is auto-loaded, and "Only variables not already present in
#              process.env are loaded". Caveat: only the FIRST .env found is
#              read, variables are not merged across files.
#   opencode - plugin exporting a "shell.env" hook. Confirmed at
#              https://opencode.ai/docs/plugins/ : the hook will "Inject
#              environment variables into all shell execution (AI tools and
#              user terminals)" via `output.env.X = ...`; plugin files live in
#              ".opencode/plugins/" (project) or "~/.config/opencode/plugins/"
#              (global). We own <ConfigDir>/plugins/ums-agent-session.js.
#   pi       - NOTHING to write. Confirmed at
#              https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/environment-variables.md :
#              "AI_AGENT=pi is a generic marker that lets tooling identify Pi
#              as the agent that launched the process" - set by the CLI and
#              RPC entry points and inherited by child processes (NOT set when
#              Pi is embedded through the SDK). The pre-push hook's
#              is_agent_session() accepts any non-empty AI_AGENT, so Pi is
#              covered by the AI_AGENT fallback. Pi's own alternative,
#              settings "shellCommandPrefix" ("Prefix prepended to every shell
#              command", docs/settings.md), is therefore not needed.
#   hermes   - profile scope only: ~/.hermes/config.yaml
#              terminal.env_passthrough plus ~/.hermes/.env. Confirmed at
#              https://hermes-agent.nousresearch.com/docs/user-guide/security :
#              "Both execute_code and terminal strip sensitive environment
#              variables from child processes", "For env vars not declared by
#              any skill, add them to terminal.env_passthrough in config.yaml",
#              and ".env" values are NOT passed to subprocesses on their own -
#              only declared passthrough variables are (config.yaml example:
#              terminal: / env_passthrough: [list]). Hermes has no
#              project-level config (https://hermes-agent.nousresearch.com/docs/user-guide/configuration),
#              hence Monorepo/Fork -> NotSupportedException.
#   all others (cursor, copilot, devin, droid, kimi, muse, antigravity, grok,
#              and claude, whose marker is the settings.json "env" block plus
#              the hook's CLAUDECODE fallback) - no documented env-injection
#              mechanism this function may write: NotSupportedException
#              naming the harness. kilocode was removed (upstream superpowers
#              does not support it).
# Each write is idempotent - a repeated deploy must not grow the file or
# duplicate a key.
function Set-AgentMarker([string] $ConfigDir, [string] $Agent, [string] $Scope = 'Monorepo') {
    switch ($Agent) {
        'codex'    { Set-CodexEnvMarker $ConfigDir; return }
        'gemini'   { Set-DotEnvMarker (Join-Path $ConfigDir '.env'); return }
        'qwen'     { Set-DotEnvMarker (Join-Path $ConfigDir '.env'); return }
        'opencode' { Set-OpenCodePluginMarker $ConfigDir; return }
        'pi'       { throw [System.NotSupportedException]::new("Set-AgentMarker: nothing to write for 'pi' - covered by AI_AGENT fallback (Pi's CLI sets AI_AGENT=pi and the pre-push hook accepts any non-empty AI_AGENT; not set when Pi is embedded via the SDK).") }
        'hermes'   {
            if ($Scope -ne 'UserProfile') {
                throw [System.NotSupportedException]::new("Set-AgentMarker: 'hermes' has no project-level configuration - terminal.env_passthrough exists only in the profile (~/.hermes); marker NOT written for scope '$Scope'.")
            }
            Set-HermesPassthroughMarker $ConfigDir
            return
        }
        default    { throw [System.NotSupportedException]::new("Set-AgentMarker: no documented environment-injection mechanism for '$Agent' - marker NOT written, the pre-push guard self-disables there (see harness matrix).") }
    }
}

# Writes the OpenCode plugin that injects the marker into every shell
# execution. The file is owned by this layer (ums- prefix), so a differing
# copy is simply rewritten; other plugins in the directory are never touched.
function Set-OpenCodePluginMarker([string] $ConfigDir) {
    $dir = Join-Path $ConfigDir 'plugins'
    $file = Join-Path $dir 'ums-agent-session.js'
    $body = @(
        '// Generated by ums/sync-with-monorepo.ps1 - do not edit; re-run the sync instead.'
        '// Marks every OpenCode shell execution as an agent session so that the'
        '// pre-push guard is active (see UMS_MEMORY_BANK_CONTRACT.md).'
        'export const UmsAgentSession = async () => {'
        '  return {'
        '    "shell.env": async (input, output) => {'
        "      output.env.$AGENT_MARKER_NAME = `"1`""
        '    },'
        '  }'
        '}'
    ) -join "`n"
    $body += "`n"
    if ((Test-Path -LiteralPath $file) -and ([IO.File]::ReadAllText($file) -ceq $body)) { return }
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    [IO.File]::WriteAllText($file, $body, [Text.UTF8Encoding]::new($false))
}

# Adds MB_AGENT_SESSION to terminal.env_passthrough in <ConfigDir>/config.yaml
# and MB_AGENT_SESSION=1 to <ConfigDir>/.env. The YAML edit is line-based and
# touches only the terminal block; shapes it cannot edit safely (e.g. a flow
# map `terminal: { ... }`) throw InvalidOperationException and leave the file
# untouched.
function Set-HermesPassthroughMarker([string] $ConfigDir) {
    New-Item -ItemType Directory -Force -Path $ConfigDir | Out-Null
    $file = Join-Path $ConfigDir 'config.yaml'
    $raw = if (Test-Path -LiteralPath $file) { [IO.File]::ReadAllText($file) } else { '' }
    if ($raw -notmatch "(?m)^[^#\r\n]*$AGENT_MARKER_NAME") {
        $nl = if ($raw.Contains("`r`n")) { "`r`n" } else { "`n" }
        $lines = [System.Collections.Generic.List[string]]::new()
        if ($raw) {
            foreach ($l in ($raw -split '\r?\n')) { $lines.Add($l) }
            if ($raw.EndsWith("`n")) { $lines.RemoveAt($lines.Count - 1) }
        }

        $termIdx = -1
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^terminal:(.*)$') {
                if (($Matches[1] -replace '(^|\s)#.*$', '').Trim()) {
                    throw [System.InvalidOperationException]::new("Set-HermesPassthroughMarker: 'terminal:' in $file has an inline value - edit terminal.env_passthrough manually (add $AGENT_MARKER_NAME).")
                }
                $termIdx = $i; break
            }
        }

        if ($termIdx -lt 0) {
            $lines.Add('terminal:'); $lines.Add('  env_passthrough:'); $lines.Add("    - $AGENT_MARKER_NAME")
        }
        else {
            $endIdx = $lines.Count
            for ($i = $termIdx + 1; $i -lt $lines.Count; $i++) {
                if ($lines[$i] -match '^\S' -and $lines[$i] -notmatch '^#') { $endIdx = $i; break }
            }
            $childIndent = '  '
            for ($i = $termIdx + 1; $i -lt $endIdx; $i++) {
                if ($lines[$i].Trim() -and $lines[$i] -notmatch '^\s*#') { $null = $lines[$i] -match '^(\s*)'; $childIndent = $Matches[1]; break }
            }
            $keyIdx = -1
            for ($i = $termIdx + 1; $i -lt $endIdx; $i++) {
                if ($lines[$i] -match '^(\s+)env_passthrough:(.*)$') { $keyIdx = $i; break }
            }
            if ($keyIdx -lt 0) {
                $lines.Insert($termIdx + 1, "$childIndent  - $AGENT_MARKER_NAME")
                $lines.Insert($termIdx + 1, "${childIndent}env_passthrough:")
            }
            else {
                $null = $lines[$keyIdx] -match '^(\s+)env_passthrough:(.*)$'
                $keyIndent = $Matches[1]; $rest = $Matches[2]
                $comment = if ($rest -match '(\s+#.*)$') { $Matches[1] } else { '' }
                $value = ($rest -replace '(^|\s)#.*$', '').Trim()
                $itemIndent = "$keyIndent  "
                if ($value -in @('', 'null', '~')) {
                    $next = if ($keyIdx + 1 -lt $endIdx) { $lines[$keyIdx + 1] } else { '' }
                    if ($next -match '^(\s*)-\s') { $itemIndent = $Matches[1] }
                    $lines[$keyIdx] = "${keyIndent}env_passthrough:$comment"
                    $lines.Insert($keyIdx + 1, "$itemIndent- $AGENT_MARKER_NAME")
                }
                elseif ($value -match '^\[(.*)\]$') {
                    if ($Matches[1].Trim()) {
                        $lines[$keyIdx] = "${keyIndent}env_passthrough: [$($Matches[1].TrimEnd()), $AGENT_MARKER_NAME]$comment"
                    }
                    else {
                        $lines[$keyIdx] = "${keyIndent}env_passthrough:$comment"
                        $lines.Insert($keyIdx + 1, "$itemIndent- $AGENT_MARKER_NAME")
                    }
                }
                else {
                    throw [System.InvalidOperationException]::new("Set-HermesPassthroughMarker: unrecognised terminal.env_passthrough value '$value' in $file - add $AGENT_MARKER_NAME manually.")
                }
            }
        }
        [IO.File]::WriteAllText($file, (($lines -join $nl) + $nl), [Text.UTF8Encoding]::new($false))
    }
    Set-DotEnvMarker (Join-Path $ConfigDir '.env')
}

# Merges `set = { $AGENT_MARKER_NAME = "1" }` into config.toml's
# [shell_environment_policy] table, preserving any other keys already in
# that table and any other sections in the file. Handles all four shapes:
# no file, file without the section, section without a `set` line, and
# section with an existing `set = { ... }` that has unrelated keys.
function Set-CodexEnvMarker([string] $ConfigDir) {
    $file = Join-Path $ConfigDir 'config.toml'
    New-Item -ItemType Directory -Force -Path $ConfigDir | Out-Null
    $text = if (Test-Path -LiteralPath $file) { (Get-Content -LiteralPath $file -Raw) -replace "`r`n", "`n" } else { '' }
    if ($text -match [regex]::Escape($AGENT_MARKER_NAME)) { return }

    $lines = @(if ($text) { $text -split "`n" } else { @() })
    $sectionIdx = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*\[shell_environment_policy\]\s*$') { $sectionIdx = $i; break }
    }
    if ($sectionIdx -lt 0) {
        # No [shell_environment_policy] section anywhere - append a fresh one.
        $newLines = $lines + @('', '[shell_environment_policy]', "set = { $AGENT_MARKER_NAME = `"1`" }")
        Set-Content -LiteralPath $file -Value ($newLines -join "`n") -Encoding utf8
        return
    }

    $endIdx = $lines.Count
    for ($i = $sectionIdx + 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*\[') { $endIdx = $i; break }
    }
    $setIdx = -1
    for ($i = $sectionIdx + 1; $i -lt $endIdx; $i++) {
        if ($lines[$i] -match '^\s*set\s*=\s*\{(.*)\}\s*$') { $setIdx = $i; break }
    }
    if ($setIdx -lt 0) {
        # Section exists but has no `set` line yet - add one right after the header.
        $before = $lines[0..$sectionIdx]
        $after = if ($sectionIdx + 1 -le $lines.Count - 1) { $lines[($sectionIdx + 1)..($lines.Count - 1)] } else { @() }
        $newLines = $before + @("set = { $AGENT_MARKER_NAME = `"1`" }") + $after
        Set-Content -LiteralPath $file -Value ($newLines -join "`n") -Encoding utf8
        return
    }

    # `set` table exists - merge the marker key in, preserving existing pairs.
    $inner = $Matches[1].Trim()
    $pairs = @()
    if ($inner) { $pairs = @($inner -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
    $pairs += "$AGENT_MARKER_NAME = `"1`""
    $lines[$setIdx] = "set = { " + ($pairs -join ', ') + " }"
    Set-Content -LiteralPath $file -Value ($lines -join "`n") -Encoding utf8
}

# Appends "$AGENT_MARKER_NAME=1" to a .env file, creating it (and its parent
# directory) if missing, and preserving any pre-existing lines.
function Set-DotEnvMarker([string] $File) {
    New-Item -ItemType Directory -Force -Path (Split-Path $File) | Out-Null
    $lead = ''
    if (Test-Path -LiteralPath $File) {
        $existing = Get-Content -LiteralPath $File -Raw
        if ($existing -match $AGENT_MARKER_NAME) { return }
        # A last line without a line ending must not swallow the marker.
        if ($existing -and -not $existing.EndsWith("`n")) { $lead = [Environment]::NewLine }
    }
    Add-Content -LiteralPath $File -Value "$lead$AGENT_MARKER_NAME=1" -Encoding utf8
}

# The single source of truth for where each harness reads skills and
# instructions, where its config directory is, and which marker mechanism
# Set-AgentMarker has for it (design 3.6). Returns one object per requested
# agent, in the requested order (all 15 when -Agent is omitted), with
# absolute paths under -Root and $null where the harness has none:
#   SkillsDir    - where the harness discovers skills
#   ConfigDir    - config directory receiving glue artifacts (hooks/, scripts/)
#   Instructions - instructions file receiving the preference block; always
#                  $null for -Scope Fork (the fork's CLAUDE.md is manual and
#                  AGENTS.md is an upstream file)
#   Marker       - settings-env | codex-toml | dotenv | opencode-plugin |
#                  pi-prefix | hermes-passthrough | none
# Output is unrolled: wrap the call in @() to get an array for one agent.
# Scope Fork uses the Monorepo layout (Root = the fork's git toplevel).
function Get-UmsSyncTargets(
    [string[]] $Agent,
    [Parameter(Mandatory)] [ValidateSet('Monorepo', 'UserProfile', 'Fork')] [string] $Scope,
    [Parameter(Mandatory)] [string] $Root
) {
    function Row($Skills, $Config, $Instr, $Marker) { @{ Skills = $Skills; Config = $Config; Instr = $Instr; Marker = $Marker } }
    # Harnesses without a documented marker mechanism or config dir.
    $generic = @{
        Monorepo    = Row '.agents\skills' $null 'AGENTS.md' 'none'
        UserProfile = Row '.agents\skills' $null $null 'none'
    }
    $table = [ordered]@{
        claude = @{
            Monorepo    = Row '.claude\skills' '.claude' 'CLAUDE.md' 'settings-env'
            UserProfile = Row '.claude\skills' '.claude' '.claude\CLAUDE.md' 'settings-env'
        }
        codex = @{
            Monorepo    = Row '.agents\skills' '.codex' 'AGENTS.md' 'codex-toml'
            UserProfile = Row '.agents\skills' '.codex' '.codex\AGENTS.md' 'codex-toml'
        }
        gemini = @{
            Monorepo    = Row '.agents\skills' '.gemini' 'GEMINI.md' 'dotenv'
            UserProfile = Row '.agents\skills' '.gemini' '.gemini\GEMINI.md' 'dotenv'
        }
        qwen = @{
            Monorepo    = Row '.qwen\skills' '.qwen' 'QWEN.md' 'dotenv'
            UserProfile = Row '.qwen\skills' '.qwen' '.qwen\QWEN.md' 'dotenv'
        }
        opencode = @{
            Monorepo    = Row '.agents\skills' '.opencode' 'AGENTS.md' 'opencode-plugin'
            UserProfile = Row '.agents\skills' '.config\opencode' '.config\opencode\AGENTS.md' 'opencode-plugin'
        }
        # Pi: AI_AGENT=pi is set by its CLI, the pre-push fallback covers it.
        pi = @{
            Monorepo    = Row '.agents\skills' '.pi' 'AGENTS.md' 'none'
            UserProfile = Row '.agents\skills' '.pi\agent' '.pi\agent\AGENTS.md' 'none'
        }
        # Hermes: no project-level config; the marker exists only in the profile.
        hermes = @{
            Monorepo    = Row '.agents\skills' $null '.hermes.md' 'none'
            UserProfile = Row '.hermes\skills' '.hermes' $null 'hermes-passthrough'
        }
        cursor = $generic
        copilot = @{
            Monorepo    = Row '.agents\skills' $null '.github\copilot-instructions.md' 'none'
            UserProfile = $generic.UserProfile
        }
        devin = $generic
        droid = $generic
        kimi = $generic
        muse = $generic
        antigravity = @{
            Monorepo    = $generic.Monorepo
            UserProfile = Row '.gemini\antigravity-cli\skills' $null $null 'none'
        }
        grok = @{
            Monorepo    = Row '.grok\skills' $null 'AGENTS.md' 'none'
            UserProfile = Row '.grok\skills' $null $null 'none'
        }
    }
    $names = if ($Agent) { $Agent } else { @($table.Keys) }
    foreach ($name in $names) {
        if (-not $table.Contains($name)) {
            $extra = if ($name -ceq 'kilocode') { ' (kilocode was removed - upstream superpowers does not support it)' } else { '' }
            throw "Get-UmsSyncTargets: unknown agent '$name'$extra. Known agents: $(@($table.Keys) -join ', ')."
        }
    }
    $layout = if ($Scope -eq 'UserProfile') { 'UserProfile' } else { 'Monorepo' }
    foreach ($name in $names) {
        $r = $table[$name][$layout]
        $abs = { param($rel) if ($rel) { Join-Path $Root $rel } else { $null } }
        [pscustomobject]@{
            Agent        = $name
            SkillsDir    = & $abs $r.Skills
            ConfigDir    = & $abs $r.Config
            Instructions = if ($Scope -eq 'Fork') { $null } else { & $abs $r.Instr }
            Marker       = $r.Marker
        }
    }
}

# ------------------------------------------------- drift protection (design 3.2)
# Pure building blocks: none of them decides WHEN it runs. The main body
# records the TARGET's post-deploy hashes in the manifest and compares three
# states (target / manifest / fork) before it writes anything.

# Maps every file below the given items to the SHA-256 of its content with
# CRLF normalised to LF (so a CRLF checkout equals an LF one). Keys are paths
# relative to -Root with '\' separators; an item may be a file or a directory
# (walked recursively, hidden files included); a missing item is skipped.
function Get-UmsTreeHashes([string] $Root, [string[]] $RelItems) {
    $hashes = @{}
    foreach ($item in $RelItems) {
        $full = Join-Path $Root $item
        $files = if (Test-Path -LiteralPath $full -PathType Container) {
            @(Get-ChildItem -LiteralPath $full -Recurse -File -Force)
        }
        elseif (Test-Path -LiteralPath $full -PathType Leaf) {
            @(Get-Item -LiteralPath $full -Force)
        }
        else { @() }
        foreach ($f in $files) {
            $rel = [IO.Path]::GetRelativePath($Root, $f.FullName).Replace('/', '\')
            # Latin-1 maps bytes 1:1 to chars, so the replace never corrupts
            # non-text content.
            $text = [Text.Encoding]::Latin1.GetString([IO.File]::ReadAllBytes($f.FullName)).Replace("`r`n", "`n")
            $bytes = [Text.Encoding]::Latin1.GetBytes($text)
            $hashes[$rel] = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
        }
    }
    return $hashes
}

# Where the deployment manifest of a target lives. It is per git WORKTREE
# (--absolute-git-dir, not the shared common dir): pool slots on other branches
# carry different tracked content, a shared manifest would report false drift
# for each of them. Outside git the manifest sits in the target root itself.
# -Key identifies the deployment, '<Agent>-<Scope>'.
function Get-UmsManifestPath([string] $TargetRoot, [string] $Key) {
    $name = "ums-sync-manifest-$Key.json"
    $gitDir = $null
    try {
        $out = & git -C $TargetRoot rev-parse --absolute-git-dir 2>$null
        if ($LASTEXITCODE -eq 0 -and $out) { $gitDir = [IO.Path]::GetFullPath(([string]@($out)[0]).Trim()) }
    }
    catch { $gitDir = $null }
    if ($gitDir) { return (Join-Path $gitDir $name) }
    return (Join-Path $TargetRoot ".$name")
}

# Returns @{ Files = [hashtable]; ForkSha; Written } or $null when the file is
# missing or unusable (unreadable JSON, wrong shape). A broken manifest counts
# as no manifest - the safe direction, drift checks then stop on every
# difference. Written is always the ISO-8601 UTC string.
function Read-UmsManifest([string] $Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    try { $json = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable }
    catch { Write-Warning "Read-UmsManifest: '$Path' is not valid JSON - treated as no manifest."; return $null }
    if ($json -isnot [hashtable] -or $json['Files'] -isnot [hashtable]) {
        Write-Warning "Read-UmsManifest: '$Path' has an unexpected shape - treated as no manifest."
        return $null
    }
    $files = @{}
    foreach ($k in $json['Files'].Keys) { $files[[string]$k] = [string]$json['Files'][$k] }
    $written = $json['Written']
    # ConvertFrom-Json turns an ISO-8601 string into a [datetime]; turn it back.
    if ($written -is [datetime]) { $written = $written.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [cultureinfo]::InvariantCulture) }
    return @{ Files = $files; ForkSha = [string]$json['ForkSha']; Written = [string]$written }
}

# Writes the manifest deterministically (ordinally sorted keys, LF, UTF-8
# without BOM) so a diff of it stays readable. -Files is path -> hash as
# returned by Get-UmsTreeHashes; the caller decides whose hashes those are.
function Write-UmsManifest([string] $Path, [hashtable] $Files, [string] $ForkSha) {
    $keys = [string[]]@($Files.Keys)
    [Array]::Sort($keys, [StringComparer]::Ordinal)
    $sorted = [ordered]@{}
    foreach ($k in $keys) { $sorted[$k] = [string]$Files[$k] }
    $doc = [ordered]@{
        Files   = $sorted
        ForkSha = $ForkSha
        Written = [DateTime]::UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [cultureinfo]::InvariantCulture)
    }
    $text = ($doc | ConvertTo-Json -Depth 5) -replace "`r`n", "`n"
    $dir = Split-Path -Parent $Path
    if ($dir) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    [IO.File]::WriteAllText($Path, $text + "`n", [Text.UTF8Encoding]::new($false))
}

# Three-state drift comparison. -Target, -Manifest and -Fork are path -> hash
# maps; -Manifest is the manifest's Files map, or $null when there is none.
#   no manifest   - Drifted = files present in the target whose hash differs
#                   from the fork's (a file the fork lacks differs too);
#   with manifest - Drifted = files where target differs from manifest AND
#                   target differs from fork: changed in the target since the
#                   last deployment and not yet in the fork. A file in the
#                   manifest but missing in the target was deleted there and
#                   counts as drift unless the fork dropped it as well.
# Returns @{ Drifted = [string[]] (sorted); NoManifest = [bool] }.
function Test-UmsDeployDrift([hashtable] $Target, [hashtable] $Manifest, [hashtable] $Fork) {
    $noManifest = ($null -eq $Manifest)
    $paths = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($k in $Target.Keys) { [void]$paths.Add([string]$k) }
    if (-not $noManifest) { foreach ($k in $Manifest.Keys) { [void]$paths.Add([string]$k) } }
    $drifted = [System.Collections.Generic.List[string]]::new()
    foreach ($p in $paths) {
        $t = if ($Target.ContainsKey($p)) { [string]$Target[$p] } else { $null }
        $f = if ($Fork.ContainsKey($p)) { [string]$Fork[$p] } else { $null }
        if ($noManifest) {
            if ($null -ne $t -and $t -cne $f) { $drifted.Add($p) }
        }
        else {
            $m = if ($Manifest.ContainsKey($p)) { [string]$Manifest[$p] } else { $null }
            if ($t -cne $m -and $t -cne $f) { $drifted.Add($p) }
        }
    }
    $sortedDrift = [string[]]$drifted.ToArray()
    [Array]::Sort($sortedDrift, [StringComparer]::Ordinal)
    return @{ Drifted = $sortedDrift; NoManifest = $noManifest }
}

# Names of mb-* skill directories that exist in the target but not in the fork
# (someone's own skill would be wiped by the mirror, or a fork-side rename
# left an orphan) - the caller only warns about them. Sorted; output is
# unrolled, wrap the call in @().
function Get-UmsTargetOnlySkills([string] $TargetSkills, [string] $ForkSkills) {
    if (-not (Test-Path -LiteralPath $TargetSkills -PathType Container)) { return }
    $inFork = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    if (Test-Path -LiteralPath $ForkSkills -PathType Container) {
        foreach ($d in Get-ChildItem -LiteralPath $ForkSkills -Directory -Filter 'mb-*') { [void]$inFork.Add($d.Name) }
    }
    $names = @(Get-ChildItem -LiteralPath $TargetSkills -Directory -Filter 'mb-*' |
        Where-Object { -not $inFork.Contains($_.Name) } | ForEach-Object { $_.Name })
    [string[]]$names | Sort-Object -CaseSensitive
}

# ------------------------------------------------- vendored skills (design 3.3)
# The sync never copies the vendored superpowers skills: it calls the fork's
# revendor per target. Building blocks only - the main body decides when.

# Tag of a pin file (the "- Tag: <tag>" line), or '' when the file is missing
# or carries none.
function Get-UmsPinTag([string] $PinFile) {
    if (-not $PinFile -or -not (Test-Path -LiteralPath $PinFile -PathType Leaf)) { return '' }
    foreach ($line in ((Get-Content -LiteralPath $PinFile -Raw) -split '\r?\n')) {
        if ($line -match '^- Tag:\s*(\S+)\s*$') { return $Matches[1] }
    }
    return ''
}

# $true when git tracks anything at RelPath below Root (a file, or a directory
# with tracked files in it); $false for an untracked or missing path and for a
# Root outside git.
function Test-UmsTracked([string] $Root, [string] $RelPath) {
    $rel = $RelPath.Replace('\', '/')
    $out = & git -C $Root ls-files -- $rel 2>$null
    if ($LASTEXITCODE -ne 0) { return $false }
    return (@($out | Where-Object { $_ }).Count -gt 0)
}

# How to vendor into one target. ForkPin and TargetPin are PIN FILE paths (the
# shared\VENDORED_FROM.md of the fork and of the target).
#   'none'         - the target has no skills directory. Signalled by an EMPTY
#                    TargetPin (the caller passes '' when Get-UmsSyncTargets
#                    gives it no SkillsDir; a [string] parameter turns $null
#                    into '' anyway). A target that HAS a skills directory but
#                    no pin yet (first deployment) is not 'none'.
#   'vanilla-only' - the fork pin's tag differs from the target pin's tag AND
#                    the target is tracked by git: vendor the new tag without
#                    overlays and nothing else, so the commit carries only the
#                    upstream diff; the overlay run follows after that commit.
#   'full'         - everything else: one pass, vendor plus overlays.
# The tags are compared case-sensitively. A missing target pin file has no tag,
# so it never forces 'vanilla-only'. A missing fork pin is an error.
function Get-UmsVendorPlan([string] $ForkPin, [string] $TargetPin, [bool] $Tracked) {
    if (-not $TargetPin) { return 'none' }
    $forkTag = Get-UmsPinTag $ForkPin
    if (-not $forkTag) { throw "Get-UmsVendorPlan: fork pin '$ForkPin' is missing or has no '- Tag:' line." }
    $targetTag = Get-UmsPinTag $TargetPin
    if ($Tracked -and $targetTag -and ($forkTag -cne $targetTag)) { return 'vanilla-only' }
    return 'full'
}

# Runs the fork's revendor as a PowerShell process over one target skills
# directory: -SpRepo <fork root> -SkillsRoot <target> -PinSource <fork pin>
# (plus -NoOverlays for 'vanilla-only'). The revendor reads tag and skill set
# from the fork pin, overlays from the TARGET's shared\overlays, and owns the
# target's shared\VENDORED_FROM.md: it reads it as the previous pin before
# rewriting it, so a mirror of shared\ done before this call MUST leave that
# file alone (else no skill dropped upstream is ever removed). Mode 'none'
# does nothing. A non-zero exit throws with the tail of the revendor's output.
function Invoke-UmsVendoredDeploy(
    [string] $ForkUmsDir,
    [string] $SkillsRoot,
    [Parameter(Mandatory)] [ValidateSet('full', 'vanilla-only', 'none')] [string] $Mode
) {
    if ($Mode -eq 'none') { return }
    $revendor = Join-Path $ForkUmsDir '.claude\scripts\revendor-superpowers.ps1'
    $forkPin = Join-Path $ForkUmsDir '.claude\skills\shared\VENDORED_FROM.md'
    foreach ($p in @($revendor, $forkPin)) {
        if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { throw "Invoke-UmsVendoredDeploy: '$p' not found." }
    }
    $forkRoot = $null
    $top = & git -C $ForkUmsDir rev-parse --show-toplevel 2>$null
    if ($LASTEXITCODE -eq 0 -and $top) { $forkRoot = [IO.Path]::GetFullPath(([string]@($top)[0]).Trim()) }
    if (-not $forkRoot) { $forkRoot = [IO.Path]::GetFullPath((Split-Path -Parent $ForkUmsDir)) }

    $revArgs = @('-NoProfile', '-File', $revendor, '-SpRepo', $forkRoot, '-SkillsRoot', $SkillsRoot, '-PinSource', $forkPin)
    if ($Mode -eq 'vanilla-only') { $revArgs += '-NoOverlays' }
    $pwshExe = (Get-Process -Id $PID).Path
    $lines = @(& $pwshExe @revArgs 2>&1 | ForEach-Object { "$_" })
    $code = $LASTEXITCODE
    if ($code -ne 0) {
        $tail = ($lines | Select-Object -Last 20) -join [Environment]::NewLine
        throw "Invoke-UmsVendoredDeploy: revendor-superpowers.ps1 ($Mode) exited with $code for '$SkillsRoot'. Output tail:$([Environment]::NewLine)$tail"
    }
    foreach ($l in $lines) { Write-Host "    [revendor] $l" }
}

# ------------------------------------------------ -Scope Fork (design 3.5)
# -Agent takes a list, and every value is split on commas and trimmed, because
# `pwsh -File ... -Agent claude,codex` delivers ONE string 'claude,codex'. The
# names are lower-cased and de-duplicated (first occurrence wins), so a harness
# named twice - or two harnesses sharing one skills directory - is not deployed
# twice. Unknown names are not judged here: Get-UmsSyncTargets throws for them.
# Output is unrolled, wrap the call in @().
function ConvertTo-UmsAgentList([string[]] $Agent) {
    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($value in @($Agent)) {
        if ($null -eq $value) { continue }
        foreach ($part in $value.Split(',')) {
            $name = $part.Trim().ToLowerInvariant()
            if ($name -and $seen.Add($name)) { $name }
        }
    }
}

# Appends to the repository's info/exclude ONLY the lines it does not already
# carry (whole-line, case-sensitive comparison) and returns the lines it added
# (unrolled, wrap in @()). The file is resolved with
# `git rev-parse --git-path info/exclude`, which is right for a plain clone and
# for a linked worktree (the exclude file lives in the common dir). An existing
# file's line-ending style is kept, and a last line without a line ending never
# swallows the first added line.
function Add-UmsGitExclude([string] $RepoRoot, [string[]] $Patterns) {
    $out = & git -C $RepoRoot rev-parse --git-path info/exclude 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Add-UmsGitExclude: git rev-parse --git-path info/exclude failed in '$RepoRoot': $out" }
    $file = ([string]@($out)[0]).Trim()
    if (-not [IO.Path]::IsPathRooted($file)) { $file = Join-Path $RepoRoot $file }
    $file = [IO.Path]::GetFullPath($file)

    $existing = if (Test-Path -LiteralPath $file -PathType Leaf) { [IO.File]::ReadAllText($file) } else { '' }
    $have = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($l in ($existing -split '\r?\n')) { [void]$have.Add($l.TrimEnd()) }
    $add = [System.Collections.Generic.List[string]]::new()
    foreach ($p in @($Patterns)) {
        if ($p -and $have.Add($p)) { $add.Add($p) }
    }
    if ($add.Count -eq 0) { return }

    $nl = if ($existing.Contains("`r`n")) { "`r`n" } else { "`n" }
    $text = $existing
    if ($text -and -not $text.EndsWith("`n")) { $text += $nl }
    $text += (($add -join $nl) + $nl)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $file) | Out-Null
    [IO.File]::WriteAllText($file, $text, [Text.UTF8Encoding]::new($false))
    return $add.ToArray()
}

# The exclude lines ('/<reldir>/') for the directories among -RelDirs that git
# does NOT already ignore, so that deploying into them leaves
# `git status --porcelain` empty. A directory is judged by a probe path INSIDE
# it (git only matches a directory-only pattern such as `.claude/` for a path it
# knows is a directory, and the directory may not exist yet). Unrolled output,
# wrap in @().
function Get-UmsForkExcludes([string] $RepoRoot, [string[]] $RelDirs) {
    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($dir in @($RelDirs)) {
        $rel = ([string]$dir).Replace('\', '/').Trim('/')
        if (-not $rel -or -not $seen.Add($rel)) { continue }
        & git -C $RepoRoot check-ignore -q -- "$rel/.ums-probe" 2>$null
        if ($LASTEXITCODE -eq 1) { "/$rel/" }
        elseif ($LASTEXITCODE -gt 1) { throw "Get-UmsForkExcludes: git check-ignore failed (exit $LASTEXITCODE) in '$RepoRoot' for '$rel'." }
    }
}

# ------------------------------------------------ marked block in instructions
# Sections of an instructions file that belong to the UMS block (design 3.4).
# A legacy file (one that predates the markers) carries them unmarked; the
# marker-less migration in Set-MarkedBlock finds them by these exact headings.
$UmsOwnedHeadings = @('## Memory Bank contract', '## Superpowers × Memory Bank (uživatelské preference)', '## Zákaz git worktree')

$UMS_BLOCK_BEGIN = '<!-- UMS-MEMORY-BANK BEGIN (generated by ums/sync-with-monorepo.ps1 - edit ums/CLAUDE.md.sample instead) -->'
$UMS_BLOCK_END   = '<!-- UMS-MEMORY-BANK END -->'

# Split LF-normalised text into lines; the flag says whether it ended with a
# newline (so it can be restored byte-for-byte).
function Split-InstructionLines([string] $Text) {
    $endsNl = $Text.EndsWith("`n")
    $lines = @($Text.Split("`n"))
    if ($endsNl) { $lines = @($lines[0..($lines.Count - 2)]) }
    return [pscustomobject]@{ Lines = $lines; EndsWithNewline = $endsNl }
}

# The sections whose '## ' heading is exactly one of $OwnedHeadings (trailing
# whitespace ignored, case-sensitive). A section runs from its heading line up
# to, not including, the next line starting with '## ' or the end of the file.
# Returns [start, end) line ranges in file order. Assign the result, do not
# enumerate the call directly (return , $array).
function Find-OwnedSections([string[]] $Lines, [string[]] $OwnedHeadings) {
    $found = [System.Collections.Generic.List[object]]::new()
    $i = 0
    while ($i -lt $Lines.Count) {
        if ($Lines[$i].StartsWith('## ', [StringComparison]::Ordinal)) {
            $j = $i + 1
            while ($j -lt $Lines.Count -and -not $Lines[$j].StartsWith('## ', [StringComparison]::Ordinal)) { $j++ }
            if ($OwnedHeadings -ccontains $Lines[$i].TrimEnd()) {
                $found.Add([pscustomobject]@{ Start = $i; End = $j })
            }
            $i = $j
        }
        else { $i++ }
    }
    return , $found.ToArray()
}

# File text with LF endings plus the ending style it came with.
function Read-InstructionFile([string] $File) {
    $raw = [string](Get-Content -Path $File -Raw)
    return [pscustomobject]@{ Text = ($raw -replace "`r`n", "`n"); Crlf = $raw.Contains("`r`n") }
}

# Insert or replace the UMS-MEMORY-BANK marked block in an instructions file.
#  * File has markers: the block is replaced in place.
#  * No markers, $OwnedHeadings match sections (legacy shape): those sections
#    are removed and the block takes the place of the first of them; the rest
#    of the file (title, project sections) is left byte-identical.
#  * No markers, nothing owned: the block is appended (also for a new file).
# The file's line-ending style (LF or CRLF) is preserved.
function Set-MarkedBlock([string] $File, [string] $Content, [string[]] $OwnedHeadings = @()) {
    if ($null -eq $OwnedHeadings) { $OwnedHeadings = @() }
    $begin = $UMS_BLOCK_BEGIN
    $end   = $UMS_BLOCK_END
    $block = "$begin`n$($Content.TrimEnd("`n"))`n$end"
    $crlf = $false
    if (Test-Path $File) {
        $info = Read-InstructionFile $File
        $raw = $info.Text
        $crlf = $info.Crlf
        $iBegin = $raw.IndexOf($begin)
        $iEnd   = $raw.IndexOf($end)
        $sections = Find-OwnedSections (Split-InstructionLines $raw).Lines $OwnedHeadings
        if ($iBegin -ge 0 -and $iEnd -gt $iBegin) {
            $new = $raw.Substring(0, $iBegin) + $block + $raw.Substring($iEnd + $end.Length)
        }
        elseif ($iBegin -ge 0 -or $iEnd -ge 0) {
            throw "Corrupted UMS-MEMORY-BANK markers in $File - fix the file manually."
        }
        elseif ($sections.Count -gt 0) {
            $split = Split-InstructionLines $raw
            $lines = $split.Lines
            $endsNl = $split.EndsWithNewline
            $out = [System.Collections.Generic.List[string]]::new()
            $cursor = 0
            for ($k = 0; $k -lt $sections.Count; $k++) {
                $s = $sections[$k]
                for ($x = $cursor; $x -lt $s.Start; $x++) { $out.Add($lines[$x]) }
                if ($k -eq 0) {
                    $out.AddRange([string[]]$block.Split("`n"))
                    # The block inherits the blank lines that closed the section it replaces.
                    $t = $s.End
                    while ($t -gt ($s.Start + 1) -and [string]::IsNullOrWhiteSpace($lines[$t - 1])) { $t-- }
                    for ($x = $t; $x -lt $s.End; $x++) { $out.Add($lines[$x]) }
                }
                $cursor = $s.End
            }
            for ($x = $cursor; $x -lt $lines.Count; $x++) { $out.Add($lines[$x]) }
            if ($sections.Count -gt 1 -and $sections[$sections.Count - 1].End -eq $lines.Count) {
                # A removed section closed the file: do not leave its neighbour's blank lines dangling.
                while ($out.Count -gt 0 -and [string]::IsNullOrWhiteSpace($out[$out.Count - 1])) { $out.RemoveAt($out.Count - 1) }
                $endsNl = $true
            }
            $new = ($out -join "`n") + $(if ($endsNl) { "`n" } else { '' })
        }
        else {
            $new = $raw.TrimEnd("`n") + "`n`n" + $block + "`n"
        }
    }
    else {
        $new = $block + "`n"
    }
    if ($crlf) { $new = $new -replace "`n", "`r`n" }
    New-Item -ItemType Directory -Force (Split-Path $File) | Out-Null
    Set-Content -Path $File -NoNewline -Value $new
}

# The content of the UMS block of an instructions file, LF-normalised and
# without the marker lines: the text between the markers, or - for a legacy
# file without markers - the sections named by $OwnedHeadings joined in file
# order. $null when the file, the markers and the owned sections are all absent.
function Get-MarkedBlockContent([string] $File, [string[]] $OwnedHeadings = @()) {
    if ($null -eq $OwnedHeadings) { $OwnedHeadings = @() }
    if (-not (Test-Path $File)) { return $null }
    $begin = $UMS_BLOCK_BEGIN
    $end   = $UMS_BLOCK_END
    $raw = (Read-InstructionFile $File).Text
    $iBegin = $raw.IndexOf($begin)
    $iEnd   = $raw.IndexOf($end)
    if ($iBegin -ge 0 -and $iEnd -gt $iBegin) {
        $inner = $raw.Substring($iBegin + $begin.Length, $iEnd - $iBegin - $begin.Length)
        if ($inner.StartsWith("`n")) { $inner = $inner.Substring(1) }
        return $inner.TrimEnd("`n")
    }
    if ($iBegin -ge 0 -or $iEnd -ge 0) {
        throw "Corrupted UMS-MEMORY-BANK markers in $File - fix the file manually."
    }
    if ($OwnedHeadings.Count -eq 0) { return $null }
    $lines = (Split-InstructionLines $raw).Lines
    $sections = Find-OwnedSections $lines $OwnedHeadings
    if ($sections.Count -eq 0) { return $null }
    $out = [System.Collections.Generic.List[string]]::new()
    foreach ($s in $sections) {
        for ($x = $s.Start; $x -lt $s.End; $x++) { $out.Add($lines[$x]) }
    }
    while ($out.Count -gt 0 -and [string]::IsNullOrWhiteSpace($out[$out.Count - 1])) { $out.RemoveAt($out.Count - 1) }
    return ($out -join "`n")
}

# Tests need only the function definitions, not the full sync run.
if ($DotSourceOnly) { return }

$ErrorActionPreference = 'Stop'

# ------------------------------------------------- interactive parameter setup
function Read-WithDefault([string]$Prompt, [string]$Default) {
    $answer = Read-Host "$Prompt [$Default]"
    if ([string]::IsNullOrWhiteSpace($answer)) { $Default } else { $answer.Trim() }
}

$isNonInteractive = [Console]::IsInputRedirected -or
    ([Environment]::GetCommandLineArgs() -contains '-NonInteractive')

if ($PSBoundParameters.Count -eq 0 -and -not $isNonInteractive) {
    Write-Host 'No parameters given - interactive setup (Enter = default):' -ForegroundColor Cyan

    $agentNames = @(Get-UmsSyncTargets -Scope Monorepo -Root $MonorepoRoot | ForEach-Object { $_.Agent })
    do {
        $agentAnswer = Read-WithDefault "Target AI agent ($($agentNames -join ', '))" 'claude'
        $valid = $agentAnswer -in $agentNames
        if (-not $valid) { Write-Host '  Enter one of the listed agent names.' -ForegroundColor Yellow }
    } until ($valid)
    $Agent = @($agentAnswer)

    do {
        $scopeAnswer = Read-WithDefault "Scope: 1 = Monorepo ($MonorepoRoot), 2 = UserProfile ($UserProfileRoot)" '1'
        $valid = $scopeAnswer -in @('1', '2', 'Monorepo', 'UserProfile')
        if (-not $valid) { Write-Host '  Enter 1, 2, Monorepo, or UserProfile.' -ForegroundColor Yellow }
    } until ($valid)
    $Scope = if ($scopeAnswer -in @('2', 'UserProfile')) { 'UserProfile' } else { 'Monorepo' }

    if ($agentAnswer -eq 'claude' -and $Scope -eq 'Monorepo') {
        do {
            $dirAnswer = Read-WithDefault 'Direction: 1 = FromMonorepo (monorepo -> fork), 2 = ToMonorepo (fork -> monorepo)' '1'
            $valid = $dirAnswer -in @('1', '2', 'FromMonorepo', 'ToMonorepo')
            if (-not $valid) { Write-Host '  Enter 1, 2, FromMonorepo, or ToMonorepo.' -ForegroundColor Yellow }
        } until ($valid)
        $Direction = if ($dirAnswer -in @('2', 'ToMonorepo')) { 'ToMonorepo' } else { 'FromMonorepo' }
    }
    else {
        Write-Host "  This combination is deploy-only (fork -> target); Direction is ignored." -ForegroundColor DarkGray
    }

    if ($Scope -eq 'Monorepo') {
        $attempts = 0
        do {
            $MonorepoRoot = Read-WithDefault 'Monorepo root' $MonorepoRoot
            $valid = Test-Path (Join-Path $MonorepoRoot '.claude')
            if (-not $valid) {
                Write-Host "  No .claude/ found under '$MonorepoRoot'." -ForegroundColor Yellow
                if ((++$attempts) -ge 3) { throw "Monorepo root not valid after 3 attempts." }
            }
        } until ($valid)
    }

    $ForkUmsDir = Read-WithDefault 'Fork ums/ directory' $ForkUmsDir

    Write-Host "Agent=$Agent  Scope=$Scope  Direction=$Direction  MonorepoRoot=$MonorepoRoot  ForkUmsDir=$ForkUmsDir" -ForegroundColor Cyan
}

# ------------------------------------------------------------ shared helpers
function Copy-Mirrored([string]$Src, [string]$Dst) {
    # Replaces the destination item entirely - use ONLY for directories this
    # layer owns outright (skill dirs).
    if (-not (Test-Path $Src)) { throw "Source item missing: $Src" }
    if (Test-Path -PathType Container $Src) {
        if (Test-Path $Dst) { Remove-Item -Recurse -Force $Dst }
        New-Item -ItemType Directory -Force (Split-Path $Dst) | Out-Null
        Copy-Item -Recurse $Src $Dst
    }
    else {
        New-Item -ItemType Directory -Force (Split-Path $Dst) | Out-Null
        Copy-Item -Force $Src $Dst
    }
}

function Copy-Merged([string]$Src, [string]$Dst) {
    # Merges into the destination: overwrites same-named files, never deletes
    # anything else - safe for shared config dirs (e.g. ~/.claude/hooks with
    # the user's own hooks).
    Get-ChildItem -Path $Src -Recurse -File | ForEach-Object {
        $rel = $_.FullName.Substring($Src.Length).TrimStart('\', '/')
        $dstFile = Join-Path $Dst $rel
        New-Item -ItemType Directory -Force (Split-Path $dstFile) | Out-Null
        Copy-Item -Force $_.FullName $dstFile
    }
}

$forkClaude = Join-Path $ForkUmsDir '.claude'
$baseRoot = if ($Scope -eq 'UserProfile') { $UserProfileRoot } else { $MonorepoRoot }
$AgentList = @(ConvertTo-UmsAgentList $Agent)
if ($AgentList.Count -eq 0) { $AgentList = @('claude') }

# Install/refresh this layer's git hooks (currently: pre-push, the
# Publication Contract enforcement boundary - see
# .claude/hooks/install-git-hooks.ps1) into a target repository. Git hooks
# are per-repository, not per-agent, so this only applies for Scope
# Monorepo (the same repo regardless of which -Agent's glue is being
# synced); UserProfile scope has no single associated repository, so hook
# installation does not apply there - install manually per clone with
# install-git-hooks.ps1 -RepoRoot. Called AFTER each branch's own target
# checks/deployment below (never before), and never lets a hook-install
# failure abort the rest of the sync - an unrelated problem with the
# repository (not a git repo yet, permissions, ...) must not silently skip
# every other deployed item the way an unguarded throw here once did.
function Install-PublicationHooks([string] $RepoRoot) {
    $installScript = Join-Path $forkClaude 'hooks\install-git-hooks.ps1'
    if (-not (Test-Path $installScript)) {
        Write-Host "note: install-git-hooks.ps1 not found - pre-push guarantee not installed into $RepoRoot." -ForegroundColor Yellow
        return
    }
    try {
        & $installScript -RepoRoot $RepoRoot -SourceDir (Join-Path $forkClaude 'hooks')
        # The installer exits non-zero whenever the guarantee is NOT in place
        # (foreign hook left alone, or the installed copy failed its own
        # proof). A sync run that ends in a wall of "synced ..." lines must
        # not let that scroll past unremarked.
        if ($LASTEXITCODE -ne 0) {
            Write-Host "warning: install-git-hooks.ps1 exited with $LASTEXITCODE - the pre-push guarantee is NOT confirmed for $RepoRoot (see its output just above)." -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "warning: could not install git hooks into $RepoRoot ($($_.Exception.Message)) - continuing sync without them." -ForegroundColor Yellow
    }
}

# The one-agent deploy of the Monorepo and UserProfile scopes. Called once per
# requested agent (-Agent takes a list); every agent gets its own target row.
function Invoke-UmsAgentSync([string] $AgentName) {
    $target = @(Get-UmsSyncTargets -Agent $AgentName -Scope $Scope -Root $baseRoot)[0]

    # --------------------------------------------- claude + monorepo: two-way sync
    if ($AgentName -eq 'claude' -and $Scope -eq 'Monorepo') {
        $monoClaude = Join-Path $MonorepoRoot '.claude'
        if (-not (Test-Path $monoClaude)) { throw "Monorepo .claude not found at $monoClaude" }

        # UMS-owned items relative to the .claude/ root. skills/mb-* AND hooks/* are
        # discovered dynamically on the source side so new mb-* skills or hooks are
        # picked up without editing this script (settings.json registers hooks by
        # path, so an un-mirrored hook would be a dangling reference).
        $staticItems = @(
            'settings.json',
            'scripts\revendor-superpowers.ps1',
            'skills\shared'
        )

        if ($Direction -eq 'FromMonorepo') { $srcClaude = $monoClaude; $dstClaude = $forkClaude }
        else                               { $srcClaude = $forkClaude; $dstClaude = $monoClaude }

        $mbSkills = Get-ChildItem -Path (Join-Path $srcClaude 'skills') -Directory -Filter 'mb-*' |
            ForEach-Object { "skills\$($_.Name)" }

        $srcHooks = Join-Path $srcClaude 'hooks'
        $hooks = if (Test-Path $srcHooks) {
            Get-ChildItem -Path $srcHooks -File | ForEach-Object { "hooks\$($_.Name)" }
        } else { @() }

        foreach ($rel in $staticItems + $mbSkills + $hooks) {
            Copy-Mirrored (Join-Path $srcClaude $rel) (Join-Path $dstClaude $rel)
            Write-Host "synced $rel"
        }

        # Root CLAUDE.md <-> ums/CLAUDE.md.sample
        $monoClaudeMd = Join-Path $MonorepoRoot 'CLAUDE.md'
        $forkSample   = Join-Path $ForkUmsDir 'CLAUDE.md.sample'
        if ($Direction -eq 'FromMonorepo') { Copy-Item -Force $monoClaudeMd $forkSample; Write-Host 'synced CLAUDE.md -> CLAUDE.md.sample' }
        else                               { Copy-Item -Force $forkSample $monoClaudeMd; Write-Host 'synced CLAUDE.md.sample -> CLAUDE.md' }

        # Git hook install runs AFTER the sync above, never before: with the
        # default -Direction FromMonorepo the hook source under $forkClaude is
        # rewritten by this very run, and installing first would deploy the
        # fork's pre-sync copy instead of the one this run just made
        # authoritative.
        Install-PublicationHooks $MonorepoRoot

        Write-Host "Done (claude, Monorepo, $Direction)." -ForegroundColor Cyan
    }
    # ------------------------------------- everything else: one-way deploy
    else {
        # 1. Portable skills content -> agent's skills directory (when it has one).
        $skillsRel = if ($target.SkillsDir) { [IO.Path]::GetRelativePath($baseRoot, $target.SkillsDir) } else { $null }
        if ($target.SkillsDir) {
            $dstSkills = $target.SkillsDir
            $items = @('shared') + (Get-ChildItem -Path (Join-Path $forkClaude 'skills') -Directory -Filter 'mb-*' |
                ForEach-Object { $_.Name })
            foreach ($name in $items) {
                Copy-Mirrored (Join-Path $forkClaude "skills\$name") (Join-Path $dstSkills $name)
                Write-Host "deployed skills\$name -> $skillsRel\$name"
            }
        }
        else {
            Write-Host "Agent '$AgentName' has no skills directory - deploying glue + instructions block only." -ForegroundColor DarkGray
        }

        # 2. Glue artifacts (hooks/, scripts/, any future non-settings items of
        #    ums/.claude) -> agent's config dir. Merged, never wiping existing
        #    content. settings.json is intentionally skipped: it is Claude Code's
        #    registration file and would clobber the agent's own settings (e.g.
        #    .gemini/settings.json); register hooks manually per harness.
        $dstConfig = $target.ConfigDir
        if ($dstConfig) {
            $configRel = [IO.Path]::GetRelativePath($baseRoot, $dstConfig)
            Get-ChildItem -Path $forkClaude -Directory |
                Where-Object { $_.Name -ne 'skills' } |
                ForEach-Object {
                    Copy-Merged $_.FullName (Join-Path $dstConfig $_.Name)
                    Write-Host "deployed $($_.Name)\ -> $configRel\$($_.Name)\ (merged)"
                }
        }
        else {
            Write-Host "Agent '$AgentName' has no config directory at scope $Scope - glue (hooks/, scripts/) not deployed." -ForegroundColor DarkGray
        }
        if (-not ($AgentName -eq 'claude')) {
            Write-Host "note: settings.json not deployed (Claude Code registration format) - wire hooks manually for '$AgentName'." -ForegroundColor DarkGray
            try {
                Set-AgentMarker $dstConfig $AgentName $Scope
                Write-Host "note: agent-session marker ($AGENT_MARKER_NAME) written into '$AgentName' config - without it the pre-push guard disables itself there." -ForegroundColor DarkGray
            }
            catch [System.NotSupportedException] {
                if ($_.Exception.Message -match 'covered by AI_AGENT fallback') {
                    Write-Host "note: no marker written for '$AgentName' - covered by the AI_AGENT fallback of the pre-push guard." -ForegroundColor DarkGray
                }
                else {
                    Write-Host "WARNING: no known agent-session marker mechanism for '$AgentName' at scope $Scope - the pre-push guard self-disables there until this harness gets one. This is a named, open gap, not a silent failure." -ForegroundColor Yellow
                }
            }
        }
        elseif ($Scope -eq 'UserProfile') {
            Write-Host "note: settings.json not deployed - merge hook registration into $configRel\settings.json manually if wanted." -ForegroundColor DarkGray
        }

        # 3. Preference block from CLAUDE.md.sample -> agent's instructions file.
        $content = (Get-Content -Path (Join-Path $ForkUmsDir 'CLAUDE.md.sample') -Raw) -replace "`r`n", "`n"
        if ($target.SkillsDir) {
            # Repoint skill-pack references to the agent's own skills location.
            $skillsFwd = $skillsRel -replace '\\', '/'
            $content = $content -replace [regex]::Escape('.claude/skills/'), "$skillsFwd/"
        }
        if ($Scope -eq 'UserProfile') {
            $preamble = "> **Rozsah platnosti:** následující pravidla platí POUZE při práci v UMS`n" +
                        "> monorepu (``$MonorepoRoot``). V jiných projektech je ignoruj.`n`n"
            $content = $preamble + $content
        }
        if ($AgentName -ne 'claude') {
            $content += @"

> Pozn. pro tento nástroj: mechanická vynucení (PreToolUse write-guard,
> permission deny EnterWorktree/ExitWorktree, skillOverrides) existují jen
> v Claude Code — zde platí výše uvedená pravidla jako závazný text.
"@
        }
        if ($target.Instructions) {
            Set-MarkedBlock $target.Instructions $content
            Write-Host "deployed preference block -> $([IO.Path]::GetRelativePath($baseRoot, $target.Instructions))"
        }
        else {
            Write-Host "WARNING: agent '$AgentName' has no known instructions file at scope $Scope - the preference block was NOT deployed; add it to the harness's instructions by hand." -ForegroundColor Yellow
        }

        # 4. Git hook install (Monorepo only - see Install-PublicationHooks above).
        if ($Scope -eq 'Monorepo') {
            Install-PublicationHooks $MonorepoRoot
        }
        else {
            Write-Host 'note: git hook enforcement (pre-push, the Publication Contract boundary) is per-repository and is NOT installed by a UserProfile-scope deploy - run install-git-hooks.ps1 -RepoRoot <repo> manually for each repository you use.' -ForegroundColor Yellow
        }

        $scopeNote = if ($Scope -eq 'UserProfile') { "user profile $baseRoot" } else { 'monorepo (this file set may be gitignored there - local per-developer deploy)' }
        Write-Host "Done ($AgentName, $Scope deploy -> $scopeNote)." -ForegroundColor Cyan
    }
}

# Mirrors skills\shared into a target directory like Copy-Mirrored, but keeps
# the TARGET's own shared\VENDORED_FROM.md (an absent one stays absent, the
# fork's is never copied): the revendor owns that file and reads it as the
# previous pin before rewriting it, so a mirror that replaced it would leave the
# revendor unable to delete a skill that left the pin.
function Copy-MirroredShared([string] $Src, [string] $Dst) {
    $pin = Join-Path $Dst 'VENDORED_FROM.md'
    $keep = if (Test-Path -LiteralPath $pin -PathType Leaf) { [IO.File]::ReadAllBytes($pin) } else { $null }
    Copy-Mirrored $Src $Dst
    if ($null -ne $keep) { [IO.File]::WriteAllBytes($pin, $keep) }
    elseif (Test-Path -LiteralPath $pin) { Remove-Item -Force -LiteralPath $pin }
}

# -Scope Fork (design 3.5): deploy the layer into the fork's own root without
# dirtying its working tree. Order matters: names are validated and the
# .git/info/exclude lines written BEFORE the first file lands, so a run that
# dies half-way still leaves a clean `git status`.
#   claude       .claude/ - settings.json, hooks/*, scripts/revendor-superpowers.ps1,
#                skills/shared, skills/mb-*, then the vendored skills
#   every other  shared/, mb-* and the vendored skills in its skills dir; no glue,
#                no agent-session marker (a config dir would show up untracked)
#   never        instruction files (CLAUDE.md is manual, AGENTS.md is upstream)
# A skills directory shared by several harnesses is deployed once. Drift
# protection (manifest, -Force) is not part of this step.
function Invoke-UmsForkDeploy([string[]] $AgentNames) {
    $top = & git -C $ForkUmsDir rev-parse --show-toplevel 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $top) { throw "-Scope Fork: '$ForkUmsDir' is not inside a git working tree." }
    $forkRoot = [IO.Path]::GetFullPath(([string]@($top)[0]).Trim())
    $targets = @(Get-UmsSyncTargets -Agent $AgentNames -Scope Fork -Root $forkRoot)
    foreach ($p in @((Join-Path $forkClaude 'skills\shared\VENDORED_FROM.md'), (Join-Path $forkClaude 'skills\shared'))) {
        if (-not (Test-Path -LiteralPath $p)) { throw "-Scope Fork: '$p' not found - is '$ForkUmsDir' the fork's ums/ directory?" }
    }
    $forkPin = Join-Path $forkClaude 'skills\shared\VENDORED_FROM.md'

    $claudeTarget = $targets | Where-Object { $_.Agent -ceq 'claude' } | Select-Object -First 1
    $skillsDirs = [System.Collections.Generic.List[string]]::new()
    $relDirs = [System.Collections.Generic.List[string]]::new()
    foreach ($t in $targets) {
        if (-not $t.SkillsDir) {
            Write-Host "note: agent '$($t.Agent)' has no skills directory - nothing to deploy for it in Fork scope." -ForegroundColor DarkGray
            continue
        }
        if (-not ($skillsDirs | Where-Object { $_ -ieq $t.SkillsDir })) { $skillsDirs.Add($t.SkillsDir) }
        $rel = if ($t.Agent -ceq 'claude') { '.claude' } else { [IO.Path]::GetRelativePath($forkRoot, $t.SkillsDir) }
        if (-not ($relDirs | Where-Object { $_ -ieq $rel })) { $relDirs.Add($rel) }
    }

    $newExcludes = @(Add-UmsGitExclude $forkRoot @(Get-UmsForkExcludes $forkRoot $relDirs.ToArray()))
    foreach ($l in $newExcludes) { Write-Host "added to .git/info/exclude: $l" }

    $vanillaPending = $false
    foreach ($sd in $skillsDirs) {
        $skillsRel = [IO.Path]::GetRelativePath($forkRoot, $sd)
        $tracked = Test-UmsTracked $forkRoot "$skillsRel/shared/VENDORED_FROM.md"
        $mode = Get-UmsVendorPlan $forkPin (Join-Path $sd 'shared\VENDORED_FROM.md') $tracked
        if ($mode -eq 'vanilla-only') {
            # A tracked target changing tag: upstream diff first, on its own (design 3.3).
            Invoke-UmsVendoredDeploy $ForkUmsDir $sd 'vanilla-only'
            Write-Host "NEXT: commit the vanilla sync in '$skillsRel', then run this script again to mirror the UMS layer and apply the overlays." -ForegroundColor Yellow
            $vanillaPending = $true
            continue
        }

        foreach ($name in @(Get-UmsTargetOnlySkills $sd (Join-Path $forkClaude 'skills'))) {
            Write-Host "warning: '$skillsRel\$name' exists only in the target - it is not part of the layer and stays untouched." -ForegroundColor Yellow
        }
        Copy-MirroredShared (Join-Path $forkClaude 'skills\shared') (Join-Path $sd 'shared')
        Write-Host "deployed skills\shared -> $skillsRel\shared (pin kept)"
        foreach ($d in Get-ChildItem -LiteralPath (Join-Path $forkClaude 'skills') -Directory -Filter 'mb-*') {
            Copy-Mirrored $d.FullName (Join-Path $sd $d.Name)
            Write-Host "deployed skills\$($d.Name) -> $skillsRel\$($d.Name)"
        }

        if ($claudeTarget -and $sd -ieq $claudeTarget.SkillsDir) {
            $dstClaude = $claudeTarget.ConfigDir
            $srcHooks = Join-Path $forkClaude 'hooks'
            $hooks = if (Test-Path -LiteralPath $srcHooks) {
                @(Get-ChildItem -LiteralPath $srcHooks -File | ForEach-Object { "hooks\$($_.Name)" })
            } else { @() }
            foreach ($rel in @('settings.json', 'scripts\revendor-superpowers.ps1') + $hooks) {
                Copy-Mirrored (Join-Path $forkClaude $rel) (Join-Path $dstClaude $rel)
                Write-Host "deployed $rel -> .claude\$rel"
            }
        }

        Invoke-UmsVendoredDeploy $ForkUmsDir $sd 'full'
    }

    $others = @($targets | Where-Object { $_.Agent -cne 'claude' } | ForEach-Object { $_.Agent })
    if ($others.Count -gt 0) {
        Write-Host "note: Fork scope deploys only skills for $($others -join ', ') - no glue, no agent-session marker, no instructions file (the pre-push guard needs MB_AGENT_SESSION or AI_AGENT set by other means there)." -ForegroundColor DarkGray
    }

    if ($vanillaPending) {
        Write-Host 'Fork deploy stopped after the vanilla phase (see NEXT above); git hooks not touched.' -ForegroundColor Yellow
        return
    }
    Install-PublicationHooks $forkRoot

    $dirty = @(& git -C $forkRoot status --porcelain -- @($relDirs.ToArray()) 2>$null | Where-Object { $_ })
    if ($dirty.Count -gt 0) {
        Write-Host "warning: the deployed directories show up in 'git status' of the fork ($($dirty.Count) entries, e.g. $($dirty[0])) - something in them is tracked or not ignored." -ForegroundColor Yellow
    }
    Write-Host "Done (Fork deploy: $($AgentNames -join ', ') -> $forkRoot)." -ForegroundColor Cyan
}

# ------------------------------------------------------------------------ run
if ($Scope -eq 'Fork') {
    Invoke-UmsForkDeploy $AgentList
}
else {
    # Validate every name before the first file is written.
    $null = @(Get-UmsSyncTargets -Agent $AgentList -Scope $Scope -Root $baseRoot)
    foreach ($name in $AgentList) { Invoke-UmsAgentSync $name }
}
