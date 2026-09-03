#Requires -Version 7
# Test seam for `claude agents --json --cwd <path>`.
#
# MBPOOL_STUB_MODE selects a single mode applied to every --cwd (the default,
# back-compat path used by most cases):
#   live     -> one record WITH a pid                (slot occupied)
#   nopid    -> one record WITHOUT a pid              (finished background session; ignored)
#   empty    -> empty array                           (slot free)
#   garbage  -> unparseable output                    (occupancy unknown, fail-closed)
#   silent   -> exit 0, no output at all               (occupancy unknown, fail-closed — Gate 2.1)
#   jsonnull -> the bare JSON literal `null`           (occupancy unknown, fail-closed — Gate 2.2)
#   wrapped  -> a top-level JSON OBJECT, not an array  (occupancy unknown, fail-closed — Gate 2.3)
#
# MBPOOL_STUB_CWD_MODES overrides the above PER --cwd, keyed by the leaf
# directory name, semicolon-separated "name=mode" pairs, e.g.
# "slot01=live;slot02=empty" — this is what proves the production script
# actually threads --cwd through to a per-slot answer rather than reading the
# same env var for every slot (Gate 4). Falls back to MBPOOL_STUB_MODE for any
# --cwd not named in the map.
param([Parameter(ValueFromRemainingArguments = $true)] $Rest)

function Get-StubMode([object[]] $RestArgs) {
    $restArr = @($RestArgs)
    $cwdIndex = [array]::IndexOf($restArr, '--cwd')
    $cwd = if ($cwdIndex -ge 0 -and ($cwdIndex + 1) -lt $restArr.Count) { [string] $restArr[$cwdIndex + 1] } else { '' }
    $leaf = if ($cwd) { Split-Path -Leaf $cwd } else { '' }
    if ($env:MBPOOL_STUB_CWD_MODES) {
        foreach ($pair in ($env:MBPOOL_STUB_CWD_MODES -split ';')) {
            if (-not $pair) { continue }
            $kv = $pair -split '=', 2
            if ($kv.Count -eq 2 -and $kv[0] -ceq $leaf) { return $kv[1] }
        }
    }
    return $env:MBPOOL_STUB_MODE
}

$mode = Get-StubMode $Rest
switch ($mode) {
    'live'     { Write-Output '[{"name":"UMS-0000","pid":29404,"state":"idle"}]'; exit 0 }
    'nopid'    { Write-Output '[{"name":"UMS-0000","state":"exited"}]';           exit 0 }
    'garbage'  { Write-Output 'not json at all';                                  exit 0 }
    'silent'   { exit 0 }
    'jsonnull' { Write-Output 'null';                                             exit 0 }
    'wrapped'  { Write-Output '{"agents":[{"name":"UMS-0000","pid":1}]}';         exit 0 }
    default    { Write-Output '[]';                                               exit 0 }
}
