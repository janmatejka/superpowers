<#
.SYNOPSIS
    Reads the per-repository UMS configuration (contract: "Repository
    Configuration") and fills in per-key defaults for everything absent.

.DESCRIPTION
    Location is <RepoRoot>/memory-bank/ums-repo.json — deliberately NOT
    .claude/, which upstream .gitignore ignores wholesale, so a config file
    there would be untracked and therefore not shared.

    Never throws on a missing or malformed file: degradation is toward the
    SAFER side (built-in protected list = more protection, not less; empty
    projectMarkers/sharedRoots = the drift heuristic offers verification more
    often, not less). A malformed file writes one warning to the warning
    stream and falls back to defaults.

    Dot-source this file, then call Get-UmsRepoConfig.
#>
Set-StrictMode -Version Latest

function Get-UmsRepoConfig([string] $RepoRoot) {
    $cfg = @{
        BaseRef           = 'origin/develop'
        ProtectedBranches = @('develop', 'main', 'master', 'release/*')
        TicketPattern     = '^[A-Z][A-Z0-9]+-[0-9]+'
        ProjectMarkers    = @()
        SharedRoots       = @()
        Source            = 'default'
    }

    if (-not $RepoRoot) { return $cfg }
    $path = Join-Path $RepoRoot 'memory-bank/ums-repo.json'
    if (-not (Test-Path -LiteralPath $path)) { return $cfg }

    try {
        $raw = Get-Content -LiteralPath $path -Raw -ErrorAction Stop
        $json = $raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Write-Warning "ums-repo.json nelze přečíst ($path): $($_.Exception.Message). Používám vestavěné defaulty."
        return $cfg
    }

    $cfg.Source = 'file'
    # Each key falls back INDIVIDUALLY: a file naming only baseRef must not
    # wipe the built-in protected list.
    if ($json.PSObject.Properties.Name -contains 'baseRef' -and $json.baseRef) {
        $cfg.BaseRef = [string]$json.baseRef
    }
    if ($json.PSObject.Properties.Name -contains 'ticketPattern' -and $json.ticketPattern) {
        $cfg.TicketPattern = [string]$json.ticketPattern
    }
    foreach ($pair in @(
            @{ Key = 'protectedBranches'; Field = 'ProtectedBranches' },
            @{ Key = 'projectMarkers'; Field = 'ProjectMarkers' },
            @{ Key = 'sharedRoots'; Field = 'SharedRoots' })) {
        if ($json.PSObject.Properties.Name -contains $pair.Key) {
            # @() so a single-element JSON array still exposes .Count.
            $values = @($json.($pair.Key)) | Where-Object { $_ } | ForEach-Object { [string]$_ }
            if (@($values).Count -gt 0) { $cfg[$pair.Field] = @($values) }
        }
    }
    return $cfg
}
