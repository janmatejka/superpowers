#Requires -Version 7
# Test seam for `claude agents --json --cwd <path>`. MBPOOL_STUB_MODE selects:
#   live    -> one record WITH a pid           (slot occupied)
#   nopid   -> one record WITHOUT a pid        (finished background session; ignored)
#   empty   -> empty array                     (slot free)
#   garbage -> unparseable output              (occupancy unknown, fail-closed)
param([Parameter(ValueFromRemainingArguments = $true)] $Rest)
switch ($env:MBPOOL_STUB_MODE) {
    'live'    { Write-Output '[{"name":"UMS-0000","pid":29404,"state":"idle"}]'; exit 0 }
    'nopid'   { Write-Output '[{"name":"UMS-0000","state":"exited"}]';           exit 0 }
    'garbage' { Write-Output 'not json at all';                                  exit 0 }
    default   { Write-Output '[]';                                               exit 0 }
}
