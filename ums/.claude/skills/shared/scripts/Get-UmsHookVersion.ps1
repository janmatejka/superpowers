#Requires -Version 7
Set-StrictMode -Version Latest

# The version suffix of the pre-push hook header. The identity marker itself
# is version-less on purpose (install-git-hooks.ps1 recognises its OWN hook by
# it, whatever version), so the version lives only in the suffix and only
# consumers read it.
#
# Consumers compare by ORDERING, never by equality: an exact-match test cannot
# tell a NEWER hook from an older one, so a stale layer copy would reinstall
# over a newer hook and DOWNGRADE it. The hook lives in the shared common dir,
# so one stale worktree would downgrade it for the whole repository.
$script:UmsHookMarker = 'UMS pre-push guard \(Publication Contract\)'
$script:UmsHookMarkerLines = 5

# Returns [int] version, 0 for our hook without a suffix (pre-v2), or $null
# when the file is missing or is not our hook at all.
function Get-UmsHookVersion([string] $Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    $head = @(Get-Content -LiteralPath $Path -TotalCount $script:UmsHookMarkerLines -ErrorAction SilentlyContinue)
    if (-not $head) { return $null }
    # Case-sensitive by default in .NET: an identity check against the exact
    # marker the installer stamps, so a differently-cased paraphrase is never
    # mistaken for it.
    $m = [regex]::Match(($head -join "`n"), $script:UmsHookMarker + '(?:\s+v(\d+))?')
    if (-not $m.Success) { return $null }
    if (-not $m.Groups[1].Success) { return 0 }
    return [int] $m.Groups[1].Value
}

# $SourceHookPath is the layer's OWN hook source. Reading the current version
# from it rather than from a literal is what makes every future bump free for
# consumers: nobody has to be edited again.
#
# FAIL-OPEN ON AN UNREADABLE SOURCE, DELIBERATELY - and said out loud because
# this layer is fail-closed nearly everywhere else. When the layer's own
# pre-push is missing or carries no marker there is no version to compare
# against, and the only alternatives are to install from a source we just
# failed to identify, or to loop reinstalling forever. Refusing to act is the
# conservative choice here: the installed hook is left exactly as it is, and
# the incomplete layer copy is the problem to fix. Callers that print a verdict
# must not word it as "current" without qualification - there was no comparison.
function Test-UmsHookNeedsInstall([string] $InstalledPath, [string] $SourceHookPath) {
    $installed = Get-UmsHookVersion $InstalledPath
    if ($null -eq $installed) { return $true }
    $source = Get-UmsHookVersion $SourceHookPath
    if ($null -eq $source) { return $false }
    return ($installed -lt $source)
}
