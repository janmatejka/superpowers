<#
.SYNOPSIS
    Deploys the UMS Memory Bank layer from this fork (directory ums/, the
    MASTER copy) into a target - the UMS monorepo (default), the user's
    profile or the fork's own root - including the vendored superpowers
    skills, with protection against overwriting changes made in the target.

.DESCRIPTION
    The fork is the master copy of the layer. The default -Direction ToMonorepo
    deploys fork -> target for every scope. -Direction FromMonorepo is the
    deliberate pull of changes made in the monorepo back into the fork; it
    exists only for -Agent claude -Scope Monorepo and never pulls the vendored
    skills (see below).

    What one ToMonorepo run writes, per target (Get-UmsSyncTargets is the one
    table of the 15 harnesses superpowers supports - claude, codex, gemini,
    qwen, opencode, pi, hermes, cursor, copilot, devin, droid, kimi, muse,
    antigravity, grok - with their skills dir, config dir, instructions file
    and marker mechanism per scope):
      * UMS items: skills/shared (the target's shared/VENDORED_FROM.md is kept -
        the revendor owns it) and every skills/mb-* into the skills directory;
        for claude in Monorepo/Fork also settings.json, hooks/* and
        scripts/revendor-superpowers.ps1; for every other harness (and claude
        in UserProfile) the glue dirs of ums/.claude (hooks/, scripts/) are
        merged file by file into its config dir, never deleting anything
        there; settings.json only ever goes to claude;
      * the vendored superpowers skills: the fork's revendor runs against the
        target skills directory with the FORK's pin (tag, skill set) and the
        overlay fragments just mirrored into the target;
      * the instructions block: ums/CLAUDE.md.sample between the
        UMS-MEMORY-BANK markers of the harness's instructions file; for
        claude's CLAUDE.md a legacy file without markers is migrated in place
        (its UMS-owned sections are replaced, project sections stay);
        UserProfile prepends a scoping line;
      * the agent-session marker (MB_AGENT_SESSION) through the harness's
        documented mechanism; harnesses without one get the named warning
        "the pre-push guarantee does not bind '<agent>'" (Pi is covered by its
        own AI_AGENT variable and gets a note instead);
      * the pre-push git hook (Monorepo: the monorepo, Fork: the fork;
        UserProfile has no single repository - install it per clone);
      * the deployment manifest (below).
    Targets shared by several harnesses (a skills dir, an instructions file,
    a glue file) are written once per run.

    Drift protection. After every successful run (FromMonorepo too) a manifest
    records the TARGET's post-deploy SHA-256 (LF-normalised) of everything the
    run owns there, keyed per agent and scope, in the target's git dir (per
    worktree; outside git in the target root). Before writing, each target is
    compared three ways - target, manifest, fork:
      * a file changed in the target since the last deployment whose change the
        fork does not have -> STOP (exit 3) listing the files; resolve with
        -Direction FromMonorepo (claude + Monorepo) or overwrite with -Force;
      * no manifest (first run) or an unreadable one -> STOP on every
        difference between target and fork;
      * vendored skills are judged target vs manifest only (their fork-side
        content exists only after a revendor), so a hand edit in the target is
        caught; on a first run they are not judged;
      * the instructions block is compared by its content;
      * an mb-* directory present only in the target -> warning.

    Vendoring plan per skills directory: same tag or an untracked target -> one
    pass (UMS items, then revendor with overlays). A tag change on a target
    tracked by git -> ONLY the vanilla phase (revendor without overlays, nothing
    else) and exit 4: commit it as "vanilla sync" in the target and run again,
    the second run mirrors the layer and applies the overlays ("overlay").

    Scopes: Monorepo (-MonorepoRoot, default D:\_datasys\ums or the environment
    variable UMS_SYNC_MONOREPO_ROOT), UserProfile (-UserProfileRoot, default
    $HOME) and Fork (the git toplevel of -ForkUmsDir; claude gets .claude/,
    other harnesses their skills dir only; no instructions file and no marker
    are written there, every deployed dir git does not ignore is added to
    .git/info/exclude so the tree stays clean, pre-push is installed).

    -WhatIf prints what the run would write and the drift, writes nothing
    (no file, no manifest, no exclude line, no hook) and exits 0.
    -Force deploys over drift. In an interactive console a run without -Force
    that finds drift lists it and asks ONCE whether to overwrite it (y = the
    same as -Force, anything else = STOP, exit 3), so nothing has to be typed
    again.

    Exit codes: 0 done; 1 error (nothing or part written - read the output),
    including a non-interactive -Force without a target parameter; 3 drift
    STOP (nothing written); 4 vanilla phase done - not an error (commit
    "vanilla sync" in the target, run again; if you revert the target instead,
    delete the manifest the output names); 5 deployed, but a per-agent step
    failed (marker writer error, pre-push not confirmed) - the summary names it.

    Target parameters are -Agent, -Scope, -MonorepoRoot, -UserProfileRoot,
    -Direction and -ForkUmsDir. With none of them given, an interactive console
    prompts for each parameter with its default offered (Enter accepts the
    default) - also when only -Force or -WhatIf is given. In a non-interactive
    process (redirected stdin, pwsh -NonInteractive) the defaults apply
    silently (claude, Monorepo, ToMonorepo), except that -Force without a
    target parameter is refused with exit 1.
#>
#Requires -Version 7
[CmdletBinding()]
param(
    # The fork is the master copy: ToMonorepo deploys fork -> target (every
    # scope); FromMonorepo pulls the monorepo's changes back (claude+Monorepo only).
    [ValidateSet('FromMonorepo', 'ToMonorepo')]
    [string]$Direction = 'ToMonorepo',
    # One or more of the 15 harnesses (claude, codex, gemini, qwen, opencode, pi,
    # hermes, cursor, copilot, devin, droid, kimi, muse, antigravity, grok). Every
    # value is split on commas ('-Agent claude,codex' arrives as ONE string) and
    # validated against the target table, not by ValidateSet, for that reason.
    [string[]]$Agent = @('claude'),
    [ValidateSet('Monorepo', 'UserProfile', 'Fork')]
    [string]$Scope = 'Monorepo',
    # Default: the environment variable UMS_SYNC_MONOREPO_ROOT when set (another
    # clone, or a test fixture), else D:\_datasys\ums.
    [string]$MonorepoRoot = $(if ($env:UMS_SYNC_MONOREPO_ROOT) { $env:UMS_SYNC_MONOREPO_ROOT } else { 'D:\_datasys\ums' }),
    [string]$ForkUmsDir = $PSScriptRoot,
    # Test/advanced override of the user-profile root used by -Scope UserProfile.
    [string]$UserProfileRoot = $HOME,
    # Deploy over a target that has drifted from the last deployment (the drift
    # is listed, then overwritten).
    [switch] $Force,
    # Print what the run would write and the drift; write nothing, exit 0. The
    # script's own switch (no SupportsShouldProcess).
    [switch] $WhatIf,
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
#   Guarantee    - whether the pre-push guard can recognise an agent session
#                  there: 'marker' (a marker mechanism exists), or for Marker
#                  'none' either 'ai-agent-fallback' (the harness sets AI_AGENT
#                  itself - Pi) or 'none' (not covered: the sync warns)
# Output is unrolled: wrap the call in @() to get an array for one agent.
# Scope Fork uses the Monorepo layout (Root = the fork's git toplevel).
function Get-UmsSyncTargets(
    [string[]] $Agent,
    [Parameter(Mandatory)] [ValidateSet('Monorepo', 'UserProfile', 'Fork')] [string] $Scope,
    [Parameter(Mandatory)] [string] $Root
) {
    function Row($Skills, $Config, $Instr, $Marker, $Guarantee) {
        if (-not $Guarantee) { $Guarantee = if ($Marker -ne 'none') { 'marker' } else { 'none' } }
        @{ Skills = $Skills; Config = $Config; Instr = $Instr; Marker = $Marker; Guarantee = $Guarantee }
    }
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
            Monorepo    = Row '.agents\skills' '.pi' 'AGENTS.md' 'none' 'ai-agent-fallback'
            UserProfile = Row '.agents\skills' '.pi\agent' '.pi\agent\AGENTS.md' 'none' 'ai-agent-fallback'
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
            Guarantee    = $r.Guarantee
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

# ------------------------------------------- deployment plan (design 3.2-3.4)
# What one run would write into one target, as data - nothing here writes.

# Names listed in a section ('Skills' or 'Excluded') of a pin file; nothing
# for a missing file. Unrolled output, wrap in @().
function Get-UmsPinNames([string] $PinFile, [string] $Section = 'Skills') {
    if (-not $PinFile -or -not (Test-Path -LiteralPath $PinFile -PathType Leaf)) { return }
    $in = $false
    foreach ($line in ((Get-Content -LiteralPath $PinFile -Raw) -split '\r?\n')) {
        if ($line -match '^- (\w+):\s*$') { $in = ($Matches[1] -ceq $Section); continue }
        if ($in -and $line -match '^\s+([A-Za-z0-9][A-Za-z0-9._-]*)\s*$') { $Matches[1]; continue }
        $in = $false
    }
}

# SHA-256 of a text as the manifest records the instructions block: LF line
# endings, trailing newlines dropped, UTF-8.
function Get-UmsTextHash([string] $Text) {
    $norm = $Text.Replace("`r`n", "`n").TrimEnd("`n")
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($norm))).ToLowerInvariant()
}

# Get-UmsTreeHashes of one file or directory, keyed '<Key>' (a file) or
# '<Key>\<path inside>' (a directory). Empty for a missing path.
function Get-UmsItemHashes([string] $Path, [string] $Key) {
    $out = @{}
    if (Test-Path -LiteralPath $Path -PathType Container) {
        $h = Get-UmsTreeHashes $Path @('.')
        foreach ($k in $h.Keys) { $out["$Key\$k"] = $h[$k] }
    }
    elseif (Test-Path -LiteralPath $Path -PathType Leaf) {
        $h = Get-UmsTreeHashes (Split-Path -Parent $Path) @(Split-Path -Leaf $Path)
        foreach ($v in $h.Values) { $out[$Key] = $v }
    }
    return $out
}

# $true when Key is one of Items or lies below one of them.
function Test-UmsKeyUnder([string] $Key, [string[]] $Items) {
    foreach ($i in @($Items)) {
        if ($Key -ieq $i -or $Key.StartsWith("$i\", [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

# Git toplevel of the repository holding Path (the nearest existing ancestor
# is asked when Path does not exist yet), or $null outside git.
function Get-UmsGitTop([string] $Path) {
    $p = $Path
    while ($p -and -not (Test-Path -LiteralPath $p -PathType Container)) { $p = Split-Path -Parent $p }
    if (-not $p) { return $null }
    $out = & git -C $p rev-parse --show-toplevel 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $out) { return $null }
    return [IO.Path]::GetFullPath(([string]@($out)[0]).Trim())
}

# The preference block one harness gets from ums/CLAUDE.md.sample: skill links
# repointed to its skills dir, the scoping line for UserProfile, the note on
# Claude-only enforcement for every other harness. For claude in the monorepo
# this is the sample verbatim.
function Get-UmsInstructionContent([string] $Sample, $Target, [string] $Scope, [string] $Root, [string] $MonorepoRoot) {
    $content = $Sample -replace "`r`n", "`n"
    if ($Target.SkillsDir) {
        $skillsFwd = ([IO.Path]::GetRelativePath($Root, $Target.SkillsDir)) -replace '\\', '/'
        $content = $content -replace [regex]::Escape('.claude/skills/'), "$skillsFwd/"
    }
    if ($Scope -eq 'UserProfile') {
        $preamble = "> **Rozsah platnosti:** následující pravidla platí POUZE při práci v UMS`n" +
                    "> monorepu (``$MonorepoRoot``). V jiných projektech je ignoruj.`n`n"
        $content = $preamble + $content
    }
    if ($Target.Agent -ne 'claude') {
        $content += @"

> Pozn. pro tento nástroj: mechanická vynucení (PreToolUse write-guard,
> permission deny EnterWorktree/ExitWorktree, skillOverrides) existují jen
> v Claude Code — zde platí výše uvedená pravidla jako závazný text.
"@
    }
    return ($content -replace "`r`n", "`n")
}

# One target's deployment plan. Fields:
#   Agent, Root (target root), SkillsDir, ConfigDir, Guarantee, Marker
#   Items        UMS items, each @{ Kind; Src; Dst; Key }: Kind 'Mirror'
#                (replace the destination file/dir), 'MirrorShared' (Mirror
#                keeping the target's shared\VENDORED_FROM.md), 'File' (copy one
#                glue file, nothing next to it is deleted); Key = Dst relative
#                to Root
#   Vendored     target-relative items the revendor owns: every skill of the
#                fork pin (Skills and Excluded) and of the target pin, plus
#                the target pin itself
#   Instructions instructions file or $null; BlockKey '<rel>#ums-block';
#                Content (the block); Owned (headings of a legacy claude file)
#   SharedWith   the agent that writes the same instructions file in this run
#                (set by the caller; the block is written once)
function Get-UmsDeployPlan($Target, [string] $Scope, [string] $ForkClaude, [string] $Root, [string] $Sample, [string] $MonorepoRoot) {
    $items = [System.Collections.Generic.List[object]]::new()
    $addItem = {
        param([string] $Kind, [string] $Src, [string] $Dst)
        $items.Add([pscustomobject]@{ Kind = $Kind; Src = $Src; Dst = $Dst; Key = [IO.Path]::GetRelativePath($Root, $Dst).Replace('/', '\') })
    }
    $forkSkills = Join-Path $ForkClaude 'skills'
    $vendored = [System.Collections.Generic.List[string]]::new()
    if ($Target.SkillsDir) {
        & $addItem 'MirrorShared' (Join-Path $forkSkills 'shared') (Join-Path $Target.SkillsDir 'shared')
        foreach ($d in @(Get-ChildItem -LiteralPath $forkSkills -Directory -Filter 'mb-*' | Sort-Object Name)) {
            & $addItem 'Mirror' $d.FullName (Join-Path $Target.SkillsDir $d.Name)
        }
        $skillsRel = [IO.Path]::GetRelativePath($Root, $Target.SkillsDir).Replace('/', '\')
        $forkPin = Join-Path $forkSkills 'shared\VENDORED_FROM.md'
        $targetPin = Join-Path $Target.SkillsDir 'shared\VENDORED_FROM.md'
        $names = @(@(Get-UmsPinNames $forkPin 'Skills') + @(Get-UmsPinNames $forkPin 'Excluded') + @(Get-UmsPinNames $targetPin 'Skills') |
            Where-Object { $_ } | Select-Object -Unique)
        foreach ($n in $names) { $vendored.Add("$skillsRel\$n") }
        $vendored.Add("$skillsRel\shared\VENDORED_FROM.md")
    }
    if ($Target.Agent -ceq 'claude' -and $Scope -ne 'UserProfile') {
        # claude in Monorepo/Fork: the layer's own .claude files, mirrored.
        foreach ($rel in @('settings.json', 'scripts\revendor-superpowers.ps1')) {
            & $addItem 'Mirror' (Join-Path $ForkClaude $rel) (Join-Path $Target.ConfigDir $rel)
        }
        $srcHooks = Join-Path $ForkClaude 'hooks'
        if (Test-Path -LiteralPath $srcHooks) {
            foreach ($h in @(Get-ChildItem -LiteralPath $srcHooks -File | Sort-Object Name)) {
                & $addItem 'Mirror' $h.FullName (Join-Path $Target.ConfigDir "hooks\$($h.Name)")
            }
        }
    }
    elseif ($Scope -ne 'Fork' -and $Target.ConfigDir) {
        # Every other harness (and claude in the profile): glue merged file by
        # file into its config dir; settings.json is Claude Code's registration
        # file and is never deployed there.
        foreach ($dir in @(Get-ChildItem -LiteralPath $ForkClaude -Directory | Where-Object { $_.Name -ne 'skills' } | Sort-Object Name)) {
            foreach ($f in @(Get-ChildItem -LiteralPath $dir.FullName -Recurse -File -Force | Sort-Object FullName)) {
                $rel = [IO.Path]::GetRelativePath($ForkClaude, $f.FullName)
                & $addItem 'File' $f.FullName (Join-Path $Target.ConfigDir $rel)
            }
        }
    }
    $content = $null; $blockKey = $null; $owned = @()
    if ($Target.Instructions) {
        $content = Get-UmsInstructionContent $Sample $Target $Scope $Root $MonorepoRoot
        $blockKey = [IO.Path]::GetRelativePath($Root, $Target.Instructions).Replace('/', '\') + '#ums-block'
        # Legacy (marker-less) migration only for claude's CLAUDE.md (design 3.4).
        if ($Target.Agent -ceq 'claude') { $owned = $UmsOwnedHeadings }
    }
    return [pscustomobject]@{
        Agent        = $Target.Agent
        Root         = $Root
        SkillsDir    = $Target.SkillsDir
        ConfigDir    = $Target.ConfigDir
        Marker       = $Target.Marker
        Guarantee    = $Target.Guarantee
        Items        = $items.ToArray()
        Vendored     = [string[]]$vendored.ToArray()
        Instructions = $Target.Instructions
        BlockKey     = $blockKey
        Content      = $content
        Owned        = [string[]]@($owned)
        SharedWith   = $null
    }
}

# Hashes of a plan's UMS items and instructions block (not the vendored
# skills): -Side Fork = what the run would write, -Side Target = what the
# target holds now. The target's shared\VENDORED_FROM.md is left out of the
# MirrorShared item on both sides - it is a vendored key.
function Get-UmsPlanHashes($Plan, [ValidateSet('Fork', 'Target')] [string] $Side) {
    $out = @{}
    foreach ($it in $Plan.Items) {
        $path = if ($Side -eq 'Fork') { $it.Src } else { $it.Dst }
        $h = Get-UmsItemHashes $path $it.Key
        if ($it.Kind -eq 'MirrorShared') { $h.Remove("$($it.Key)\VENDORED_FROM.md") }
        foreach ($k in $h.Keys) { $out[$k] = $h[$k] }
    }
    if ($Plan.Instructions) {
        $text = if ($Side -eq 'Fork') { $Plan.Content } else { Get-MarkedBlockContent $Plan.Instructions $Plan.Owned }
        if ($null -ne $text) { $out[$Plan.BlockKey] = Get-UmsTextHash $text }
    }
    return $out
}

# Everything the manifest records for a plan, read from the TARGET: UMS items,
# the instructions block and the vendored skills.
function Get-UmsPlanTargetState($Plan) {
    $state = Get-UmsPlanHashes $Plan 'Target'
    $vend = Get-UmsTreeHashes $Plan.Root @($Plan.Vendored)
    foreach ($k in $vend.Keys) { $state[$k] = $vend[$k] }
    return $state
}

# Drift of one plan against the manifest's Files map ($null = no manifest).
# UMS items and the block are judged target / manifest / fork. The vendored
# skills have no fork-side content before a revendor, so for them the fork side
# IS the manifest: a vendored file drifts when it differs from what the last
# deployment left (a hand edit, a deleted or an added file). Without a manifest
# they are not judged. Returns Test-UmsDeployDrift's result.
function Get-UmsPlanDrift($Plan, [hashtable] $ManifestFiles) {
    $fork = Get-UmsPlanHashes $Plan 'Fork'
    $target = Get-UmsPlanHashes $Plan 'Target'
    $vend = Get-UmsTreeHashes $Plan.Root @($Plan.Vendored)
    foreach ($k in $vend.Keys) {
        $target[$k] = $vend[$k]
        if ($null -eq $ManifestFiles) { $fork[$k] = $vend[$k] }
        elseif ($ManifestFiles.ContainsKey($k)) { $fork[$k] = $ManifestFiles[$k] }
    }
    if ($null -ne $ManifestFiles) {
        foreach ($k in @($ManifestFiles.Keys)) {
            if (-not $vend.ContainsKey($k) -and (Test-UmsKeyUnder $k $Plan.Vendored)) { $fork[$k] = $ManifestFiles[$k] }
        }
    }
    return (Test-UmsDeployDrift $target $ManifestFiles $fork)
}

# ------------------------------------------- target choice and the drift answer
# Only these parameters choose the target of a run; -Force, -WhatIf and
# -DotSourceOnly never do. With none of them bound an interactive run shows the
# target menu (even with -Force or -WhatIf alone), and a non-interactive -Force
# is refused instead of running against the default target.
function Test-UmsNeedsTargetMenu([string[]] $BoundKeys) {
    $targetParameters = @('Agent', 'Scope', 'MonorepoRoot', 'UserProfileRoot', 'Direction', 'ForkUmsDir')
    foreach ($k in @($BoundKeys)) { if ($targetParameters -contains $k) { return $false } }
    return $true
}

# What a run does about drift: 'proceed' (no drift, or -Force), 'preview'
# (-WhatIf lists it and writes nothing), 'ask' (interactive: one question for the
# whole run) or 'stop' (non-interactive without -Force: exit 3).
function Get-UmsDriftAction([bool] $HasDrift, [bool] $Force, [bool] $Preview, [bool] $Interactive) {
    if (-not $HasDrift -or $Force) { return 'proceed' }
    if ($Preview) { return 'preview' }
    if ($Interactive) { return 'ask' }
    return 'stop'
}

# The answer to the drift question: only an explicit yes overwrites.
function ConvertFrom-UmsDriftAnswer([string] $Answer) {
    if ("$Answer".Trim() -in @('y', 'yes')) { return 'proceed' }
    return 'stop'
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
$Preview = [bool]$WhatIf
$needsTargetMenu = Test-UmsNeedsTargetMenu @($PSBoundParameters.Keys)

# A non-interactive -Force must name its target: the defaults point at a live
# monorepo, and overwriting it by accident is exactly what -Force must not do.
if ($Force -and $needsTargetMenu -and $isNonInteractive) {
    Write-Host '-Force needs an explicit target in a non-interactive run: pass -Scope with -MonorepoRoot or -UserProfileRoot (or -Agent) - nothing was written.' -ForegroundColor Red
    exit 1
}

# The menu appears in an interactive session whenever no target parameter was
# given - -Force or -WhatIf alone do not skip it. A non-interactive process
# without parameters runs the defaults silently (claude, Monorepo, ToMonorepo),
# so automation keeps working.
if ($needsTargetMenu -and -not $isNonInteractive) {
    Write-Host 'No parameters given - interactive setup (Enter = default):' -ForegroundColor Cyan

    # Agent names only: a scratch root, so a missing default drive (D:) cannot throw here.
    $agentNames = @(Get-UmsSyncTargets -Scope Monorepo -Root ([IO.Path]::GetTempPath()) | ForEach-Object { $_.Agent })
    do {
        $agentAnswer = Read-WithDefault "Target AI agent(s), comma-separated ($($agentNames -join ', '))" 'claude'
        $picked = @(ConvertTo-UmsAgentList @($agentAnswer))
        $unknown = @($picked | Where-Object { $agentNames -cnotcontains $_ })
        $valid = ($picked.Count -gt 0) -and ($unknown.Count -eq 0)
        if (-not $valid) { Write-Host '  Enter one or more of the listed agent names.' -ForegroundColor Yellow }
    } until ($valid)
    $Agent = $picked

    do {
        $scopeAnswer = Read-WithDefault "Scope: 1 = Monorepo ($MonorepoRoot), 2 = UserProfile ($UserProfileRoot), 3 = Fork (this fork's own root)" '1'
        $valid = $scopeAnswer -in @('1', '2', '3', 'Monorepo', 'UserProfile', 'Fork')
        if (-not $valid) { Write-Host '  Enter 1, 2, 3, Monorepo, UserProfile or Fork.' -ForegroundColor Yellow }
    } until ($valid)
    $Scope = if ($scopeAnswer -in @('2', 'UserProfile')) { 'UserProfile' } elseif ($scopeAnswer -in @('3', 'Fork')) { 'Fork' } else { 'Monorepo' }

    if ((@($Agent) -join ',') -ceq 'claude' -and $Scope -eq 'Monorepo') {
        do {
            $dirAnswer = Read-WithDefault 'Direction: 1 = ToMonorepo (fork -> monorepo, the fork is master), 2 = FromMonorepo (pull monorepo changes -> fork)' '1'
            $valid = $dirAnswer -in @('1', '2', 'ToMonorepo', 'FromMonorepo')
            if (-not $valid) { Write-Host '  Enter 1, 2, ToMonorepo or FromMonorepo.' -ForegroundColor Yellow }
        } until ($valid)
        $Direction = if ($dirAnswer -in @('2', 'FromMonorepo')) { 'FromMonorepo' } else { 'ToMonorepo' }
    }
    else {
        Write-Host '  This combination deploys fork -> target only (ToMonorepo).' -ForegroundColor DarkGray
    }

    if ($Scope -eq 'Monorepo') {
        $attempts = 0
        do {
            $MonorepoRoot = Read-WithDefault 'Monorepo root' $MonorepoRoot
            $valid = Test-Path -LiteralPath $MonorepoRoot -PathType Container
            if (-not $valid) {
                Write-Host "  '$MonorepoRoot' is not an existing directory." -ForegroundColor Yellow
                if ((++$attempts) -ge 3) { throw 'Monorepo root not valid after 3 attempts.' }
            }
        } until ($valid)
    }
    elseif ($Scope -eq 'UserProfile') {
        $UserProfileRoot = Read-WithDefault 'User profile root' $UserProfileRoot
    }

    $ForkUmsDir = Read-WithDefault 'Fork ums/ directory' $ForkUmsDir
    $previewAnswer = Read-WithDefault 'Preview only, write nothing (-WhatIf)? y/n' 'n'
    $Preview = $previewAnswer -match '^(y|yes)$'
}

# ------------------------------------------------------------ shared helpers
function Copy-Mirrored([string]$Src, [string]$Dst) {
    # Replaces the destination item entirely - use ONLY for items this layer
    # owns outright (skill dirs, the layer's own files).
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

# Mirrors skills\shared into a target directory like Copy-Mirrored, but keeps
# the TARGET's own shared\VENDORED_FROM.md (an absent one stays absent, the
# source's is never copied): the revendor owns that file and reads it as the
# previous pin before rewriting it, so a mirror that replaced it would leave the
# revendor unable to delete a skill that left the pin (ruling R3). Used for
# every scope, and by FromMonorepo so the FORK's pin stays the fork's.
function Copy-MirroredShared([string] $Src, [string] $Dst) {
    $pin = Join-Path $Dst 'VENDORED_FROM.md'
    $keep = if (Test-Path -LiteralPath $pin -PathType Leaf) { [IO.File]::ReadAllBytes($pin) } else { $null }
    Copy-Mirrored $Src $Dst
    if ($null -ne $keep) { [IO.File]::WriteAllBytes($pin, $keep) }
    elseif (Test-Path -LiteralPath $pin) { Remove-Item -Force -LiteralPath $pin }
}

# Writes one plan item (see Get-UmsDeployPlan).
function Copy-UmsItem($Item) {
    switch ($Item.Kind) {
        'MirrorShared' { Copy-MirroredShared $Item.Src $Item.Dst }
        'Mirror'       { Copy-Mirrored $Item.Src $Item.Dst }
        'File' {
            New-Item -ItemType Directory -Force (Split-Path -Parent $Item.Dst) | Out-Null
            Copy-Item -Force -LiteralPath $Item.Src -Destination $Item.Dst
        }
        default { throw "Copy-UmsItem: unknown item kind '$($Item.Kind)'." }
    }
}

$forkClaude = Join-Path $ForkUmsDir '.claude'
$forkSkills = Join-Path $forkClaude 'skills'
$forkPin = Join-Path $forkSkills 'shared\VENDORED_FROM.md'
$samplePath = Join-Path $ForkUmsDir 'CLAUDE.md.sample'

# Install/refresh this layer's git hooks (currently: pre-push, the
# Publication Contract enforcement boundary - see
# .claude/hooks/install-git-hooks.ps1) into a target repository. Git hooks
# are per-repository, not per-agent: called once per run, for Monorepo (the
# monorepo) and Fork (the fork); UserProfile has no single associated
# repository - install manually per clone with install-git-hooks.ps1 -RepoRoot.
# Called AFTER the deployment (never before): FromMonorepo rewrites the hook
# source under the fork's .claude in the same run. Returns $true only when the
# installer confirmed the guarantee; a failure never aborts the rest of the run
# (the caller reports it as a partial result).
function Install-PublicationHooks([string] $RepoRoot) {
    $installScript = Join-Path $forkClaude 'hooks\install-git-hooks.ps1'
    if (-not (Test-Path $installScript)) {
        Write-Host "warning: install-git-hooks.ps1 not found - the pre-push guarantee is NOT installed into $RepoRoot." -ForegroundColor Yellow
        return $false
    }
    try {
        $global:LASTEXITCODE = 0
        & $installScript -RepoRoot $RepoRoot -SourceDir (Join-Path $forkClaude 'hooks') | ForEach-Object { Write-Host "$_" }
        $code = $LASTEXITCODE
        # The installer exits non-zero whenever the guarantee is NOT in place
        # (foreign hook left alone, or the installed copy failed its own proof).
        if ($code -ne 0) {
            Write-Host "warning: install-git-hooks.ps1 exited with $code - the pre-push guarantee is NOT confirmed for $RepoRoot (see its output just above)." -ForegroundColor Yellow
            return $false
        }
        return $true
    }
    catch {
        Write-Host "warning: could not install git hooks into $RepoRoot ($($_.Exception.Message)) - continuing sync without them." -ForegroundColor Yellow
        return $false
    }
}

function Write-WhatIf([string] $Text) { Write-Host "WHATIF would $Text" -ForegroundColor DarkCyan }

$failures = [System.Collections.Generic.List[string]]::new()

# Ends the run: exit 5 when a per-agent step failed (partial state), else 0.
function Complete-Run([string] $What) {
    if ($Preview) {
        Write-Host "WhatIf: nothing was written ($What)." -ForegroundColor Cyan
        exit 0
    }
    if ($failures.Count -gt 0) {
        Write-Host "PARTIAL: deployed ($What), but $($failures.Count) step(s) failed:" -ForegroundColor Red
        foreach ($f in $failures) { Write-Host "  - $f" -ForegroundColor Red }
        exit 5
    }
    Write-Host "Done ($What)." -ForegroundColor Cyan
    exit 0
}

# ------------------------------------------------------------------------ run
foreach ($p in @($forkPin, $samplePath)) {
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { throw "'$p' not found - is '$ForkUmsDir' the fork's ums/ directory?" }
}
$AgentList = @(ConvertTo-UmsAgentList $Agent)
if ($AgentList.Count -eq 0) { $AgentList = @('claude') }

$forkRoot = $null
if ($Scope -eq 'Fork') {
    $top = & git -C $ForkUmsDir rev-parse --show-toplevel 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $top) { throw "-Scope Fork: '$ForkUmsDir' is not inside a git working tree." }
    $forkRoot = [IO.Path]::GetFullPath(([string]@($top)[0]).Trim())
}
$targetRoot = if ($Scope -eq 'Fork') { $forkRoot } elseif ($Scope -eq 'UserProfile') { $UserProfileRoot } else { $MonorepoRoot }
if (-not $targetRoot -or -not (Test-Path -LiteralPath $targetRoot -PathType Container)) {
    $hint = if ($Scope -eq 'Monorepo') { ' - pass -MonorepoRoot (or set UMS_SYNC_MONOREPO_ROOT)' } elseif ($Scope -eq 'UserProfile') { ' - pass -UserProfileRoot' } else { '' }
    throw "Target root '$targetRoot' (scope $Scope) does not exist$hint."
}
$targetRoot = [IO.Path]::GetFullPath($targetRoot)

# Validates every agent name before anything is read or written.
$targets = @(Get-UmsSyncTargets -Agent $AgentList -Scope $Scope -Root $targetRoot)

if ($Direction -eq 'FromMonorepo' -and -not ($Scope -eq 'Monorepo' -and $AgentList.Count -eq 1 -and $AgentList[0] -ceq 'claude')) {
    throw "-Direction FromMonorepo pulls the monorepo's changes back into the fork and exists only for -Agent claude -Scope Monorepo (got -Agent $($AgentList -join ',') -Scope $Scope); nothing was written."
}

$forkSha = ''
$shaOut = & git -C $ForkUmsDir rev-parse HEAD 2>$null
if ($LASTEXITCODE -eq 0 -and $shaOut) { $forkSha = ([string]@($shaOut)[0]).Trim() }
$forkTag = Get-UmsPinTag $forkPin

$previewNote = if ($Preview) { '  [WhatIf: nothing is written]' } else { '' }
Write-Host "Plan: Direction=$Direction  Scope=$Scope  Agent=$($AgentList -join ',')  Target=$targetRoot  Fork=$ForkUmsDir  Tag=$forkTag$previewNote" -ForegroundColor Cyan

function Get-TargetRel([string] $Path) { return [IO.Path]::GetRelativePath($targetRoot, $Path) }

# The manifest of one plan: its path, whether a file exists there, and its
# Files map ($null when there is none or it is unreadable).
function Get-PlanManifest($Plan) {
    $path = Get-UmsManifestPath $targetRoot "$($Plan.Agent)-$Scope"
    $exists = Test-Path -LiteralPath $path -PathType Leaf
    $m = if ($exists) { Read-UmsManifest $path 3>$null } else { $null }
    $files = if ($null -ne $m) { $m.Files } else { $null }
    return [pscustomobject]@{ Path = $path; Exists = $exists; Files = $files }
}

# -------------------------------------------- FromMonorepo (claude + Monorepo)
# The deliberate pull of changes made in the monorepo back into the fork: the
# UMS items (settings.json, scripts\revendor-superpowers.ps1, skills\shared -
# the FORK's pin is kept -, skills\mb-*, hooks\*) and the UMS block of
# CLAUDE.md into CLAUDE.md.sample. Vendored skills are never pulled. No drift
# check: this IS the way to take the target's changes (the fork's own diff is
# reviewable in git). The manifest then records the monorepo as deployed, so
# the next ToMonorepo sees no drift for what was pulled; vendored entries are
# carried over from the previous manifest (not blessed - a hand edit in a
# vendored skill still stops the next ToMonorepo).
function Invoke-UmsFromMonorepo {
    $monoClaude = Join-Path $targetRoot '.claude'
    if (-not (Test-Path -LiteralPath $monoClaude -PathType Container)) { throw "Monorepo .claude not found at $monoClaude" }
    $monoSkills = Join-Path $monoClaude 'skills'
    $pulls = [System.Collections.Generic.List[object]]::new()
    $addPull = { param($Kind, $Rel) $pulls.Add([pscustomobject]@{ Kind = $Kind; Src = (Join-Path $monoClaude $Rel); Dst = (Join-Path $forkClaude $Rel); Rel = $Rel }) }
    foreach ($rel in @('settings.json', 'scripts\revendor-superpowers.ps1')) {
        if (Test-Path -LiteralPath (Join-Path $monoClaude $rel) -PathType Leaf) { & $addPull 'Mirror' $rel }
        else { Write-Host "note: $rel is not in the monorepo - left as it is in the fork." -ForegroundColor DarkGray }
    }
    if (Test-Path -LiteralPath (Join-Path $monoSkills 'shared') -PathType Container) { & $addPull 'MirrorShared' 'skills\shared' }
    if (Test-Path -LiteralPath $monoSkills -PathType Container) {
        foreach ($d in @(Get-ChildItem -LiteralPath $monoSkills -Directory -Filter 'mb-*' | Sort-Object Name)) { & $addPull 'Mirror' "skills\$($d.Name)" }
    }
    $monoHooks = Join-Path $monoClaude 'hooks'
    if (Test-Path -LiteralPath $monoHooks -PathType Container) {
        foreach ($h in @(Get-ChildItem -LiteralPath $monoHooks -File | Sort-Object Name)) { & $addPull 'Mirror' "hooks\$($h.Name)" }
    }

    $monoMd = Join-Path $targetRoot 'CLAUDE.md'
    $block = if (Test-Path -LiteralPath $monoMd -PathType Leaf) { Get-MarkedBlockContent $monoMd $UmsOwnedHeadings } else { $null }

    foreach ($p in $pulls) {
        if ($Preview) { Write-WhatIf "pull $($p.Rel) -> ums\.claude\$($p.Rel)" }
        else { Copy-UmsItem $p; Write-Host "pulled $($p.Rel)" }
    }
    if ($null -eq $block) {
        Write-Host "warning: $monoMd has no UMS block (no markers, no UMS-owned sections) - CLAUDE.md.sample left as it is." -ForegroundColor Yellow
    }
    else {
        $newSample = $block.TrimEnd("`n") + "`n"
        $oldSample = [IO.File]::ReadAllText($samplePath).Replace("`r`n", "`n")
        if ($oldSample -ceq $newSample) { Write-Host 'CLAUDE.md.sample already equals the UMS block of CLAUDE.md.' -ForegroundColor DarkGray }
        elseif ($Preview) { Write-WhatIf 'write the UMS block of CLAUDE.md -> ums\CLAUDE.md.sample' }
        else {
            [IO.File]::WriteAllText($samplePath, $newSample, [Text.UTF8Encoding]::new($false))
            Write-Host 'pulled the UMS block of CLAUDE.md -> CLAUDE.md.sample'
        }
    }

    if ($Preview) { Write-WhatIf "install the pre-push hook into $targetRoot" }
    elseif (-not (Install-PublicationHooks $targetRoot)) { $failures.Add("pre-push hook not confirmed for $targetRoot") }

    # The manifest reflects the ToMonorepo plan against the refreshed fork.
    $plan = Get-UmsDeployPlan $targets[0] $Scope $forkClaude $targetRoot ([IO.File]::ReadAllText($samplePath)) $MonorepoRoot
    $man = Get-PlanManifest $plan
    if ($Preview) { Write-WhatIf "write the manifest $($man.Path)" }
    else {
        $files = Get-UmsPlanHashes $plan 'Target'
        if ($null -ne $man.Files) {
            foreach ($k in $man.Files.Keys) { if (Test-UmsKeyUnder $k $plan.Vendored) { $files[$k] = $man.Files[$k] } }
        }
        else {
            $vend = Get-UmsTreeHashes $targetRoot @($plan.Vendored)
            foreach ($k in $vend.Keys) { $files[$k] = $vend[$k] }
        }
        Write-UmsManifest $man.Path $files $forkSha
        Write-Host "manifest written: $($man.Path)" -ForegroundColor DarkGray
    }
    Complete-Run "claude, Monorepo, FromMonorepo: $targetRoot -> $ForkUmsDir"
}

if ($Direction -eq 'FromMonorepo') { Invoke-UmsFromMonorepo }

# ----------------------------------------------------------- ToMonorepo plans
# Instructions files read by several harnesses are written once, with the
# block of the first agent that claims them in this run.
$claimed = @{}
$plans = @(foreach ($t in $targets) {
        $plan = Get-UmsDeployPlan $t $Scope $forkClaude $targetRoot ([IO.File]::ReadAllText($samplePath)) $MonorepoRoot
        if ($plan.Instructions) {
            $k = $plan.Instructions.ToLowerInvariant()
            if ($claimed.ContainsKey($k)) { $plan.SharedWith = $claimed[$k].Agent; $plan.Content = $claimed[$k].Content }
            else { $claimed[$k] = $plan }
        }
        $plan
    })

# ---- 1. drift (design 3.2): nothing is written before this check passes
$manifests = @{}
$drifted = [System.Collections.Generic.List[object]]::new()
foreach ($plan in $plans) {
    $man = Get-PlanManifest $plan
    $manifests[$plan.Agent] = $man
    $d = Get-UmsPlanDrift $plan $man.Files
    if (@($d.Drifted).Count -gt 0) { $drifted.Add([pscustomobject]@{ Plan = $plan; Manifest = $man; Files = [string[]]@($d.Drifted) }) }
}
foreach ($x in $drifted) {
    $why = if ($x.Manifest.Exists -and $null -eq $x.Manifest.Files) {
        "the manifest '$($x.Manifest.Path)' exists but is corrupt (unreadable) - treated as missing, every difference from the fork counts"
    }
    elseif ($null -eq $x.Manifest.Files) { 'no deployment manifest yet (first run) - every difference from the fork counts' }
    else { 'changed in the target since the last deployment, and the fork does not have the change' }
    Write-Host "DRIFT in '$($x.Plan.Agent)' ($Scope, $targetRoot): $($x.Files.Count) file(s) - ${why}:" -ForegroundColor Yellow
    foreach ($f in $x.Files) { Write-Host "    $f" -ForegroundColor Yellow }
}
if ($drifted.Count -gt 0) {
    $driftAction = Get-UmsDriftAction -HasDrift $true -Force ([bool]$Force) -Preview $Preview -Interactive (-not $isNonInteractive)
    if ($driftAction -eq 'ask') {
        if (@($drifted | Where-Object { $null -eq $_.Manifest.Files }).Count -gt 0) {
            Write-Host 'Note: without a manifest the direction of these differences is unknown - -Direction FromMonorepo would overwrite newer fork content with the target''s.' -ForegroundColor Yellow
        }
        $driftAction = ConvertFrom-UmsDriftAnswer (Read-Host 'Overwrite the drifted files listed above (same as -Force)? [y/N]')
        # A yes is -Force for the rest of the run (the vanilla branch and the overwrite note read it).
        if ($driftAction -eq 'proceed') { $Force = $true }
    }
    if ($driftAction -eq 'proceed') {
        # Says nothing yet: whether the drift is overwritten depends on the vanilla decision below.
    }
    elseif ($driftAction -eq 'preview') {
        Write-Host 'WhatIf: without -Force this run would STOP here (exit 3); below is what a run with -Force would write.' -ForegroundColor Yellow
    }
    else {
        Write-Host 'STOP: the target has drifted - nothing was written.' -ForegroundColor Red
        if ($Scope -eq 'Monorepo' -and @($drifted | Where-Object { $_.Plan.Agent -ceq 'claude' }).Count -gt 0) {
            Write-Host '  take the monorepo changes into the fork first:  -Direction FromMonorepo' -ForegroundColor Red
        }
        else {
            Write-Host "  carry the target's changes into the fork (ums/.claude, ums/CLAUDE.md.sample) by hand," -ForegroundColor Red
        }
        Write-Host '  or overwrite them deliberately:                  -Force' -ForegroundColor Red
        exit 3
    }
}

# ---- 2. Fork: .git/info/exclude lines BEFORE the first file lands
$forkRelDirs = [System.Collections.Generic.List[string]]::new()
if ($Scope -eq 'Fork') {
    foreach ($plan in $plans) {
        if (-not $plan.SkillsDir) { continue }
        $rel = if ($plan.Agent -ceq 'claude') { '.claude' } else { Get-TargetRel $plan.SkillsDir }
        if (-not ($forkRelDirs | Where-Object { $_ -ieq $rel })) { $forkRelDirs.Add($rel) }
    }
    $needed = @(Get-UmsForkExcludes $forkRoot $forkRelDirs.ToArray())
    if ($Preview) { foreach ($l in $needed) { Write-WhatIf "add to .git/info/exclude: $l" } }
    else { foreach ($l in @(Add-UmsGitExclude $forkRoot $needed)) { Write-Host "added to .git/info/exclude: $l" } }
}

# ---- 3. vendoring plan per skills directory (design 3.3)
$vendorUnits = [ordered]@{}
foreach ($plan in $plans) {
    $pinArg = if ($plan.SkillsDir) { Join-Path $plan.SkillsDir 'shared\VENDORED_FROM.md' } else { '' }
    $tracked = $false
    if ($pinArg) {
        # Tracked is judged on the real target pin, relative to the target's git toplevel.
        $top = Get-UmsGitTop $plan.SkillsDir
        if ($top) { $tracked = Test-UmsTracked $top ([IO.Path]::GetRelativePath($top, $pinArg)) }
    }
    $mode = Get-UmsVendorPlan $forkPin $pinArg $tracked
    if ($mode -eq 'none') {
        Write-Host "note: '$($plan.Agent)' has no skills directory at scope $Scope - no vendored skills." -ForegroundColor DarkGray
        continue
    }
    $k = $plan.SkillsDir.ToLowerInvariant()
    if (-not $vendorUnits.Contains($k)) { $vendorUnits[$k] = [pscustomobject]@{ Dir = $plan.SkillsDir; Mode = $mode } }
}

$vanilla = @($vendorUnits.Values | Where-Object { $_.Mode -eq 'vanilla-only' })
if ($vanilla.Count -gt 0) {
    # A tag change on a git-tracked target: the upstream diff on its own, NOTHING
    # else in this run (no UMS items, instructions, marker or hooks), so that the
    # commit carries only the upstream change.
    foreach ($u in $vanilla) {
        $rel = Get-TargetRel $u.Dir
        $oldTag = Get-UmsPinTag (Join-Path $u.Dir 'shared\VENDORED_FROM.md')
        if ($Preview) { Write-WhatIf "run ONLY the vanilla phase in $rel (tag $oldTag -> $forkTag on a git-tracked target): revendor without overlays, nothing else" }
        else {
            Write-Host "vanilla phase: $rel (tag $oldTag -> $forkTag, git-tracked) - revendor without overlays"
            Invoke-UmsVendoredDeploy $ForkUmsDir $u.Dir 'vanilla-only'
        }
    }
    foreach ($u in @($vendorUnits.Values | Where-Object { $_.Mode -ne 'vanilla-only' })) {
        Write-Host "note: $(Get-TargetRel $u.Dir) is left for the next run (the vanilla phase writes nothing else)." -ForegroundColor DarkGray
    }
    if ($Force -and $drifted.Count -gt 0) {
        Write-Host '-Force: the drifted files listed above are not overwritten in this run (the vanilla phase writes nothing else); the next run stops on them again and needs -Force again.' -ForegroundColor Yellow
    }
    if ($Preview) {
        Write-Host 'WhatIf: the run would end after the vanilla phase with exit 4; nothing was written.' -ForegroundColor Cyan
        exit 0
    }
    # Record what the vanilla phase wrote, so the next run does not take it for drift.
    foreach ($plan in $plans) {
        if (-not $plan.SkillsDir -or @($vanilla | Where-Object { $_.Dir -ieq $plan.SkillsDir }).Count -eq 0) { continue }
        $man = $manifests[$plan.Agent]
        $files = @{}
        if ($null -ne $man.Files) {
            foreach ($k in $man.Files.Keys) { if (-not (Test-UmsKeyUnder $k $plan.Vendored)) { $files[$k] = $man.Files[$k] } }
        }
        $vend = Get-UmsTreeHashes $targetRoot @($plan.Vendored)
        foreach ($k in $vend.Keys) { $files[$k] = $vend[$k] }
        Write-UmsManifest $man.Path $files $forkSha
    }
    Write-Host ''
    Write-Host "VANILLA PHASE DONE: the vendored skills were re-vendored at $forkTag WITHOUT overlays; the UMS layer, instructions, marker and git hooks were NOT touched." -ForegroundColor Yellow
    Write-Host 'NEXT: commit this in the target as "vanilla sync", then run this script again - it mirrors the UMS layer and applies the overlays (commit "overlay").' -ForegroundColor Yellow
    Write-Host 'The vanilla phase finished successfully - exit 4 is not an error, it asks for that commit and a second run.' -ForegroundColor Yellow
    foreach ($plan in $plans) {
        if (-not $plan.SkillsDir -or @($vanilla | Where-Object { $_.Dir -ieq $plan.SkillsDir }).Count -eq 0) { continue }
        Write-Host "If you revert the target instead of committing it, delete the manifest $($manifests[$plan.Agent].Path) first - otherwise the next run reports the reverted skills as drift." -ForegroundColor Yellow
    }
    exit 4
}

# ---- 4. full deployment: UMS items, vendored skills, instructions, marker, hooks
if ($Force -and $drifted.Count -gt 0) {
    Write-Host '-Force: the drifted files listed above are overwritten.' -ForegroundColor Yellow
}
foreach ($u in $vendorUnits.Values) {
    foreach ($name in @(Get-UmsTargetOnlySkills $u.Dir $forkSkills)) {
        Write-Host "warning: '$(Get-TargetRel $u.Dir)\$name' exists only in the target - it is not part of the layer and stays untouched." -ForegroundColor Yellow
    }
}

$written = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($plan in $plans) {
    $glue = 0
    foreach ($it in $plan.Items) {
        if (-not $written.Add($it.Dst)) { continue }
        if ($it.Kind -eq 'File') {
            if (-not $Preview) { Copy-UmsItem $it }
            $glue++
            continue
        }
        $what = if ($it.Kind -eq 'MirrorShared') { "$($it.Key) (target pin kept)" } else { $it.Key }
        if ($Preview) { Write-WhatIf "mirror $what" }
        else { Copy-UmsItem $it; Write-Host "deployed $what" }
    }
    if ($glue -gt 0) {
        $cfgRel = Get-TargetRel $plan.ConfigDir
        if ($Preview) { Write-WhatIf "merge $glue glue file(s) (hooks/, scripts/) into $cfgRel" }
        else { Write-Host "deployed $glue glue file(s) (hooks/, scripts/) -> $cfgRel (merged)" }
    }
}

foreach ($u in $vendorUnits.Values) {
    $rel = Get-TargetRel $u.Dir
    if ($Preview) { Write-WhatIf "vendor ($($u.Mode)) the superpowers skills at $forkTag into $rel" }
    else {
        Write-Host "vendoring ($($u.Mode)) -> $rel"
        Invoke-UmsVendoredDeploy $ForkUmsDir $u.Dir $u.Mode
    }
}

foreach ($plan in $plans) {
    if (-not $plan.Instructions) {
        if ($Scope -ne 'Fork') {
            Write-Host "WARNING: agent '$($plan.Agent)' has no known instructions file at scope $Scope - the preference block was NOT deployed; add it to the harness's instructions by hand." -ForegroundColor Yellow
        }
        continue
    }
    $rel = Get-TargetRel $plan.Instructions
    if ($plan.SharedWith) {
        Write-Host "note: '$($plan.Agent)' reads $rel too - written once, with the block of '$($plan.SharedWith)'." -ForegroundColor DarkGray
        continue
    }
    if ($Preview) { Write-WhatIf "write the UMS block into $rel" }
    else {
        Set-MarkedBlock $plan.Instructions $plan.Content $plan.Owned
        Write-Host "deployed preference block -> $rel"
    }
}

# Agent-session marker. Who is covered is DATA (Get-UmsSyncTargets .Guarantee),
# not exception text. A marker writer error other than NotSupportedException is
# reported for that agent and the run continues (exit 5 at the end).
foreach ($plan in $plans) {
    $a = $plan.Agent
    if ($a -cne 'claude' -and $Scope -ne 'Fork') {
        Write-Host "note: settings.json not deployed for '$a' (Claude Code registration format) - wire hooks manually there." -ForegroundColor DarkGray
    }
    if ($plan.Guarantee -eq 'none') {
        Write-Host "WARNING: the pre-push guarantee does not bind '$a' (no documented environment-injection mechanism) - the guard recognises an agent session there only if MB_AGENT_SESSION or AI_AGENT is set by other means." -ForegroundColor Yellow
        continue
    }
    if ($plan.Guarantee -eq 'ai-agent-fallback') {
        Write-Host "note: no marker to write for '$a' - covered by the AI_AGENT fallback of the pre-push guard (the harness sets AI_AGENT itself)." -ForegroundColor DarkGray
        continue
    }
    if ($Scope -eq 'Fork') { continue }
    if ($plan.Marker -eq 'settings-env') {
        if ($Scope -eq 'UserProfile') {
            Write-Host "note: settings.json not deployed - merge hook registration into $(Get-TargetRel $plan.ConfigDir)\settings.json manually if wanted (the guard's CLAUDECODE fallback covers Claude Code)." -ForegroundColor DarkGray
        }
        continue
    }
    if ($Preview) { Write-WhatIf "write the agent-session marker ($($plan.Marker)) for '$a' into $(Get-TargetRel $plan.ConfigDir)"; continue }
    try {
        Set-AgentMarker $plan.ConfigDir $a $Scope
        Write-Host "note: agent-session marker ($AGENT_MARKER_NAME) written for '$a' ($($plan.Marker)) - without it the pre-push guard disables itself there." -ForegroundColor DarkGray
    }
    catch [System.NotSupportedException] {
        Write-Host "WARNING: no agent-session marker mechanism for '$a' at scope $Scope ($($_.Exception.Message)) - a named, open gap." -ForegroundColor Yellow
    }
    catch {
        $failures.Add("agent-session marker for '$a' NOT written: $($_.Exception.Message)")
        Write-Host "ERROR: agent-session marker for '$a' NOT written: $($_.Exception.Message)" -ForegroundColor Red
    }
}
if ($Scope -eq 'Fork') {
    $others = @($plans | Where-Object { $_.Agent -cne 'claude' } | ForEach-Object { $_.Agent })
    if ($others.Count -gt 0) {
        Write-Host "note: Fork scope deploys only skills for $($others -join ', ') - no glue, no agent-session marker, no instructions file (the pre-push guard needs MB_AGENT_SESSION or AI_AGENT set by other means there)." -ForegroundColor DarkGray
    }
}

if ($Scope -eq 'UserProfile') {
    Write-Host 'note: git hook enforcement (pre-push, the Publication Contract boundary) is per-repository and is NOT installed by a UserProfile-scope deploy - run install-git-hooks.ps1 -RepoRoot <repo> manually for each repository you use.' -ForegroundColor Yellow
}
elseif ($Preview) { Write-WhatIf "install the pre-push hook into $targetRoot" }
elseif (-not (Install-PublicationHooks $targetRoot)) { $failures.Add("pre-push hook not confirmed for $targetRoot") }

# ---- 5. manifest: the TARGET's post-deploy hashes (ruling R3)
foreach ($plan in $plans) {
    $man = $manifests[$plan.Agent]
    if ($Preview) { Write-WhatIf "write the manifest $($man.Path)"; continue }
    Write-UmsManifest $man.Path (Get-UmsPlanTargetState $plan) $forkSha
    Write-Host "manifest written: $($man.Path)" -ForegroundColor DarkGray
}

if ($Scope -eq 'Fork' -and -not $Preview) {
    $dirty = @(& git -C $forkRoot status --porcelain -- @($forkRelDirs.ToArray()) 2>$null | Where-Object { $_ })
    if ($dirty.Count -gt 0) {
        Write-Host "warning: the deployed directories show up in 'git status' of the fork ($($dirty.Count) entries, e.g. $($dirty[0])) - something in them is tracked or not ignored." -ForegroundColor Yellow
    }
}

Complete-Run "$Direction, $Scope deploy: $($AgentList -join ', ') -> $targetRoot"
