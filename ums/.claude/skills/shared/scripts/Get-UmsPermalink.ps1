#Requires -Version 7
Set-StrictMode -Version Latest
function Get-UmsPermalink {
    param([Parameter(Mandatory)] [string] $RepoRoot, [Parameter(Mandatory)] [string] $Sha, [Parameter(Mandatory)] [string] $Path, [string] $Template = '')
    $out = @{ Url = $null; Source = ''; Host = ''; Reason = '' }
    if ($Sha -notmatch '^[0-9a-f]{40}$') { $out.Reason = 'sha must be 40 lowercase hex characters'; return $out }
    $p = $Path -replace '\\', '/'
    if ($p -match '(^|/)\.\.(/|$)' -or $p.StartsWith('/')) { $out.Reason = 'path must be repo-relative without ..'; return $out }
    if (-not [string]::IsNullOrWhiteSpace($Template)) {
        $out.Url = $Template.Replace('{sha}', $Sha).Replace('{path}', $p); $out.Source = 'template'; return $out
    }
    $remote = & git -C $RepoRoot remote get-url origin 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($remote)) { $out.Reason = 'origin remote not found'; return $out }
    $remote = ([string] $remote).Trim()
    $m = [regex]::Match($remote, '^(?:https?://(?:[^@/]+@)?|git@|ssh://git@)(?<host>[^/:]+)[:/](?<owner>[^/]+)/(?<repo>[^/]+?)(?:\.git)?/?$')
    if (-not $m.Success) { $out.Reason = "cannot parse origin url: $remote"; return $out }
    # NOT $host: $Host is a PowerShell automatic variable (the host
    # application object). Assigning to it inside a function throws
    # "Proměnnou Host nelze přepsat..." under Set-StrictMode -Version
    # Latest — measured, not theoretical. Use a plain local name instead.
    $originHost = $m.Groups['host'].Value.ToLowerInvariant(); $owner = $m.Groups['owner'].Value; $repo = $m.Groups['repo'].Value
    $out.Host = $originHost; $out.Source = 'derived'
    switch ($originHost) {
        'github.com'    { $out.Url = "https://github.com/$owner/$repo/blob/$Sha/$p" }
        'bitbucket.org' { $out.Url = "https://bitbucket.org/$owner/$repo/src/$Sha/$p" }
        default         { $out.Reason = "unknown host '$originHost' — set permalinkTemplate in ums-repo.json"; }
    }
    return $out
}
