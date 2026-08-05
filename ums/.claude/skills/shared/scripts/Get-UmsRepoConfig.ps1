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

    Source reports WHERE the loader looked, not how much it used: 'file'
    means a config file was found and parsed as an object (an object with
    no usable keys, including {}, still counts — it overrides nothing, but
    it IS a config); 'default' means there was no file, it could not be
    parsed as JSON, or it parsed to something that is not an object (an
    array, a bare scalar, or JSON null) — well-formed JSON that is
    malformed AS CONFIGURATION.

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

    # A value that parses as valid JSON but is not an object — {}, null, a
    # bare scalar, a bare array — is malformed AS CONFIGURATION even though
    # ConvertFrom-Json accepted it without error. Guard on the type BEFORE
    # touching .PSObject.Properties: under Set-StrictMode, dereferencing
    # .Properties.Name on $null or on some non-object shapes is itself an
    # error, so the type check must come first, not inside a try/catch that
    # already succeeded.
    if ($json -isnot [System.Management.Automation.PSCustomObject]) {
        Write-Warning "ums-repo.json nelze přečíst ($path): obsah není konfigurační objekt. Používám vestavěné defaulty."
        return $cfg
    }

    $cfg.Source = 'file'
    # Materialize properties into a plain array first, then pull .Name from
    # that array — not from the live PSMemberInfoCollection — so an empty
    # object ({}) never triggers member-enumeration-on-empty-collection
    # errors under Set-StrictMode. {} is a valid config that overrides
    # nothing: Source stays 'file', every field keeps its default, no
    # warning — the user wrote an empty config and got exactly what it says.
    $propNames = @(@($json.PSObject.Properties) | ForEach-Object { $_.Name })

    # Each key falls back INDIVIDUALLY: a file naming only baseRef must not
    # wipe the built-in protected list.
    if ($propNames -contains 'baseRef' -and $json.baseRef) {
        $cfg.BaseRef = [string]$json.baseRef
    }
    if ($propNames -contains 'ticketPattern' -and $json.ticketPattern) {
        $cfg.TicketPattern = [string]$json.ticketPattern
    }
    foreach ($pair in @(
            @{ Key = 'protectedBranches'; Field = 'ProtectedBranches' },
            @{ Key = 'projectMarkers'; Field = 'ProjectMarkers' },
            @{ Key = 'sharedRoots'; Field = 'SharedRoots' })) {
        if ($propNames -contains $pair.Key) {
            # @() also NORMALIZES A BARE STRING into a single-element list:
            # `"protectedBranches": "Branches/*"` becomes @('Branches/*'), the
            # same answer guard-git-push.mjs now gives for the same shape. The
            # two enforcement layers must not disagree (the pre-push hook says
            # so in its own comment), and for a while they did — the JS side
            # required Array.isArray, fell back to the built-in four and
            # ALLOWED a push the generated list here rejected.
            # @() so a single-element JSON array still exposes .Count. Kept
            # to entries that ARE strings (post-ConvertFrom-Json, a JSON
            # string is [string]; a number/bool/object/array is not) with
            # something left after trimming — not `Where-Object { $_ }`
            # followed by an unconditional `[string]$_` coercion. That older
            # shape passed [1,2,3] through as the patterns "1","2","3"
            # instead of falling back: same class of bug as
            # guard-git-push.mjs's mirror-image gap, reached via PowerShell's
            # willingness to stringify anything rather than JS's
            # typeof-narrowing. If nothing usable remains, the key falls back
            # to its default exactly as if it were absent.
            $values = @($json.($pair.Key)) | Where-Object { $_ -is [string] -and $_.Trim() -ne '' } |
                ForEach-Object { [string]$_ }
            if (@($values).Count -gt 0) { $cfg[$pair.Field] = @($values) }
        }
    }
    return $cfg
}
