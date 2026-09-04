. (Join-Path $PSScriptRoot '_assert.ps1')
$ledger = Join-Path $PSScriptRoot 'fixtures\ledger_proposals.md'

$r = Invoke-Ledger $ledger
Assert-Match $r.Out 'konferencni_bezplatne_obdobi' 'slug member listed'
Assert-Match $r.Out '2 celkem' 'two items parsed'
Assert-Match $r.Out 'monetizace_play' 'second member listed'
# monetizace_play owns only E-2 (otevřená) so it is not a false-hotov; konferencni owns E-1 (uzavřená) and is hotov -> clean.
Assert-Eq $r.Code 0 'proposal ledger parses clean (exit 0)'
Assert-NotMatch $r.Out 'Nekonzistence' 'no cross-check errors'
Assert-Match $r.Out '## Členové \(2\)' 'members parsed under Členové heading'

# Legacy Jira ledger (## Tikety only) must keep its heading byte-for-byte.
$legacy = Join-Path $PSScriptRoot 'fixtures\ledger_legacy_tikety.md'
$rl = Invoke-Ledger $legacy
Assert-Eq $rl.Code 0 'legacy ledger parses clean (exit 0)'
Assert-Match $rl.Out '## Tikety \(' 'legacy heading preserved'
Assert-NotMatch $rl.Out '## Členové' 'no new heading for legacy ledger'

# --- section Rozjetí ---------------------------------------------------------
# The parser ends a table at the first line without a pipe and indexes columns
# POSITIONALLY, so a new section is only proven by a fixture that carries one.
$spawns = Join-Path $PSScriptRoot 'fixtures\ledger_rozjeti.md'
$rs = Invoke-Ledger $spawns
Assert-Eq $rs.Code 0 'a ledger carrying the Rozjetí section parses clean (exit 0)'
Assert-Match $rs.Out '## Rozjet' 'the Rozjetí section is reported'
Assert-Match $rs.Out 'UMS-3488' 'the spawned ticket is listed'
Assert-Match $rs.Out 'ums05' 'the slot is listed'
Assert-Match $rs.Out 'rozjeto' 'the verdict is listed'
Assert-Match $rs.Out 'wt.exe' 'the traps column survives to the report'
# Positional indexing proof: the verdict must come from column 4, not from
# whatever text happens to match elsewhere in the row.
Assert-Match $rs.Out 'UMS-3496.*odlo' 'the second row keeps its own verdict'
# Ordered proof over the RENDERED sentence (Ruling B): a mere presence check on
# 'ums05' and 'rozjeto' cannot distinguish positional indexing from column-name
# matching, because the report prints both cells regardless of which column
# they came from. The render is
# "- {0} ({1}): {2}, slot {3}{4}" -f $s[0], $s[1], $s[3], $s[2], $trap
# so this pattern is only true while column 3 (index) is the verdict and
# column 2 is the slot.
Assert-Match $rs.Out 'UMS-3488.*rozjeto, slot ums05' 'the verdict/slot order in the rendered line is positional, not name-matched'
# The sections BEFORE it must be unaffected — a new trailing section must not
# swallow the dirty-set or the windows. (Regression locks: these pass before
# this task's change too, on any pre-existing fixture with the same shape.)
Assert-Match $rs.Out '## Položky \(2 celkem\)' 'items still parse'
Assert-Match $rs.Out 'W01' 'windows still parse'
Assert-NotMatch $rs.Out 'Nekonzistence' 'no false inconsistency from the new section'

# --- cross-check: spawn row for a ticket that is NOT a member ----------------
# ledger_rozjeti.md alone never proves the new cross-check branch: both of its
# spawn rows name members already in the Členové table. A dedicated fixture
# with an orphaned spawn row is required to see $issuesFound fire.
$orphan = Join-Path $PSScriptRoot 'fixtures\ledger_rozjeti_orphan.md'
$ro = Invoke-Ledger $orphan
Assert-Eq $ro.Code 2 'a spawn row for a non-member ticket is a reported inconsistency (exit 2)'
Assert-Match $ro.Out 'Nekonzistence' 'the orphaned spawn row is flagged'
Assert-Match $ro.Out 'UMS-2222.*nemá odpovídajícího člena' 'the orphan message names the ticket and the reason'
Complete-Tests
