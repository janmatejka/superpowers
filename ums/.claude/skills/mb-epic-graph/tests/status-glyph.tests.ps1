# Status-glyph tests (Jira mode): rozhodovací matice z
# memory-bank/proposals/completed/design_epic_graph_test_jako_hotovo.md.
# Běhy záměrně BEZ -Check (oracle by do výstupu vložil vlastní ✅).
. (Join-Path $PSScriptRoot '_assert.ps1')
$status = Join-Path $PSScriptRoot 'fixtures\jira\status.json'
$props  = Join-Path $PSScriptRoot 'fixtures\status_proposals'
$stav   = Join-Path $PSScriptRoot 'fixtures\status_stav'

Write-Host 'Jira mode: fixture runs (malformed status object must not crash)'
$bare = Invoke-Graph @('-Source','Jira','-InputFile',$status,'-EpicKey','DEMO-0')
Assert-Eq $bare.Code 0 'run without -ProposalPath exits 0'
$full = Invoke-Graph @('-Source','Jira','-InputFile',$status,'-EpicKey','DEMO-0','-ProposalPath',$props)
Assert-Eq $full.Code 0 'run with -ProposalPath exits 0'
Assert-Match $bare.Out '\[DEMO-10\]' 'ticket with empty status object still lands in the table'

Write-Host 'Jira mode without -ProposalPath: unblocked To Do is ❔ (proposal state unknown)'
Assert-Match $bare.Out '❔ \S+ \[DEMO-6\]'  'DEMO-6 (blocker Done, no proposal info) -> ❔'
Assert-Match $bare.Out '❔ \S+ \[DEMO-17\]' 'DEMO-17 (blocker Cancelled) -> ❔'
Assert-Match $bare.Out '❔ \S+ \[DEMO-10\]' 'DEMO-10 (empty status, unblocked) -> ❔'
Assert-NotMatch $bare.Out '▶️ \S+ \[DEMO-6\]' 'no ▶️ without proposal information'

Write-Host 'Jira mode with -ProposalPath: no proposal -> 💡, live draft blocked -> ⏳'
Assert-Match $full.Out '💡 \S+ \[DEMO-6\]'  'DEMO-6 (unblocked, no proposal) -> 💡'
Assert-Match $full.Out '💡 \S+ \[DEMO-17\]' 'DEMO-17 (blocker Cancelled, no proposal) -> 💡'
Assert-Match $full.Out '💡 \S+ \[DEMO-10\]' 'DEMO-10 (empty status, no proposal) -> 💡'
Assert-Match $full.Out '⏳ \S+ \[DEMO-4\]'  'DEMO-4 (draft in next/, blocked by In Progress) -> ⏳'
Assert-NotMatch $full.Out '🆕' '🆕 is retired from the whole family'

Write-Host 'Jira mode: Test/Review/Documentation are done for planning'
Assert-Match $bare.Out '🧪 \S+ \[DEMO-1\]'  'DEMO-1 (Test) -> 🧪'
Assert-Match $bare.Out '🧪 \S+ \[DEMO-7\]'  'DEMO-7 (status name in lower case) -> 🧪'
Assert-Match $bare.Out '🧪 \S+ \[DEMO-8\]'  'DEMO-8 (Test) -> 🧪 without proposal info'
Assert-Match $full.Out '🧪 \S+ \[DEMO-8\]'  'DEMO-8 (Test + active/ proposal) -> 🧪, not 🔨'
Assert-Match $bare.Out '🧪 \S+ \[DEMO-11\]' 'DEMO-11 (Review) -> 🧪'
Assert-Match $bare.Out '🧪 \S+ \[DEMO-12\]' 'DEMO-12 (Documentation) -> 🧪'
Assert-Match $bare.Out '🔨 \S+ \[DEMO-3\]'  'DEMO-3 (In Progress) stays 🔨 — no category-wide generalization'

Write-Host 'Jira mode: successors of Test/Review are unblocked'
Assert-Match $bare.Out '❔ \S+ \[DEMO-2\]'  'DEMO-2 (blocker in Test) -> ❔ without proposal info'
Assert-Match $full.Out '▶️ \S+ \[DEMO-2\]'  'DEMO-2 (blocker in Test, draft in next/) -> ▶️'
Assert-Match $bare.Out '❔ \S+ \[DEMO-15\]' 'DEMO-15 (blocker in Review) -> ❔'
Assert-Match $full.Out '💡 \S+ \[DEMO-15\]' 'DEMO-15 (blocker in Review, no proposal) -> 💡'
Assert-Match $bare.Out '⛔ \S+ \[DEMO-4\]'  'DEMO-4 (blocker In Progress) stays blocked'

Write-Host 'Proposals mode: free-text **Stav:** must not be matched by name'
$sp = Invoke-Graph @('-Source','Proposals','-ProposalPath',$stav,'-EpicKey','stav')
Assert-Eq $sp.Code 0 'proposals mode exits 0'
Assert-NotMatch $sp.Out '🧪 \S+ \*\*alfa\*\*' 'proposal with **Stav:** Test does not get 🧪'
Assert-Match $sp.Out '▶️ \S+ \*\*alfa\*\*' 'alfa (live next/, unblocked) -> ▶️'
Assert-Match $sp.Out '⏳ \S+ \*\*beta\*\*' 'beta (live next/, blocked by alfa) -> ⏳'

Write-Host 'Jira mode: Design Review has its own glyph and keeps blocking'
Assert-Match $bare.Out '👀 \S+ \[DEMO-13\]' 'DEMO-13 (Design Review) -> 👀'
Assert-Match $full.Out '👀 \S+ \[DEMO-13\]' 'DEMO-13 (Design Review + active/ proposal) -> 👀, not 🔨'
Assert-Match $bare.Out '⛔ \S+ \[DEMO-14\]' 'DEMO-14 (blocker in Design Review) stays ⛔ without proposal info'
Assert-Match $full.Out '⛔ \S+ \[DEMO-14\]' 'DEMO-14 (blocker in Design Review, no proposal) stays ⛔'

Write-Host 'Proposals mode: free-text **Stav:** Design Review must not be matched'
Assert-NotMatch $sp.Out '👀 \S+ \*\*gama\*\*' 'proposal with **Stav:** Design Review does not get 👀'
Assert-Match $sp.Out '▶️ \S+ \*\*gama\*\*' 'gama (live next/, unblocked) -> ▶️'

Write-Host 'Jira mode: done category and external blockers'
Assert-Match $bare.Out '✅ \S+ \[DEMO-5\]'  'DEMO-5 (Done) -> ✅'
Assert-Match $bare.Out '✅ \S+ \[DEMO-16\]' 'DEMO-16 (Cancelled, category done) -> ✅'
Assert-Match $bare.Out '⛔ \S+ \[DEMO-9\]'  'DEMO-9 (blocker outside the snapshot) stays ⛔'
Assert-NotMatch $bare.Out '(?:✅|🧪|👀|🔨|▶️|⏳|💡|⛔|❔) \S+ \[DEMO-99\]' 'external node DEMO-99 carries no status glyph'

Write-Host 'Jira mode: -NoStatus suppresses the whole family'
$ns = Invoke-Graph @('-Source','Jira','-InputFile',$status,'-EpicKey','DEMO-0','-ProposalPath',$props,'-NoStatus')
Assert-Eq $ns.Code 0 '-NoStatus exits 0'
Assert-Match $ns.Out '\[DEMO-1\]' 'tickets are still listed with -NoStatus'
Assert-NotMatch $ns.Out '🧪' '-NoStatus suppresses 🧪'
Assert-NotMatch $ns.Out '👀' '-NoStatus suppresses 👀'
Assert-NotMatch $ns.Out '❔' '-NoStatus suppresses ❔'
Assert-NotMatch $ns.Out '💡' '-NoStatus suppresses 💡'

Write-Host 'Wave columns depend on Blocks topology only, not on status'
Assert-Match $bare.Out '(?m)^\| 🧪 \S+ \[DEMO-1\]'    'DEMO-1 sits in wave 0'
Assert-Match $bare.Out '(?m)^\|\s+\| ❔ \S+ \[DEMO-2\]' 'DEMO-2 sits in wave 1'
Assert-Match $full.Out '(?m)^\| 🧪 \S+ \[DEMO-1\]'    'DEMO-1 sits in wave 0 (with -ProposalPath)'
Assert-Match $full.Out '(?m)^\|\s+\| ▶️ \S+ \[DEMO-2\]' 'DEMO-2 sits in wave 1 (with -ProposalPath)'

Write-Host 'Legend documents the whole family'
Assert-Match $full.Out '🧪 v testu/review/dokumentaci' 'jira legend documents 🧪'
Assert-Match $full.Out '👀 v design review' 'jira legend documents 👀'
Assert-Match $full.Out '💡 k rozpracování' 'jira legend documents 💡'
Assert-Match $full.Out '❔ odblokováno, stav návrhu neznámý' 'jira legend documents ❔'
Assert-Match $full.Out 'hotové pro plánování' 'jira legend defines what unblocks a successor'
Assert-Match $sp.Out '💡 opuštěný návrh' 'proposals legend documents the abandoned stage'
Assert-NotMatch $sp.Out '🧪 v testu' 'proposals legend does not advertise 🧪 as a ticket state'

Write-Host 'Jira mode: an active/ work item outranks a stale To Do status'
Assert-Match $full.Out '🔨 \S+ \[DEMO-18\]' 'DEMO-18 (To Do + proposal in active/) -> 🔨'
Assert-Match $bare.Out '❔ \S+ \[DEMO-18\]' 'DEMO-18 without -ProposalPath -> ❔ (active/ is invisible there)'

Write-Host 'Degraded run flags itself so a pasted report cannot be misread'
Assert-Match $bare.Out 'stav návrhů není znám' 'run without -ProposalPath announces the degradation'
Assert-NotMatch $full.Out 'stav návrhů není znám' 'run with -ProposalPath carries no degradation note'

# --- -IndexFile: a draft living only on a foreign branch counts as "návrh hotov"
$idx = Join-Path $PSScriptRoot 'fixtures/doc-index/index.json'
$snap = Join-Path $PSScriptRoot 'fixtures/jira/status.json'
$r = Invoke-Graph @('-InputFile', $snap, '-EpicKey', 'DEMO-0', '-Check', '-IndexFile', $idx)
Assert-Match $r.Out '▶️|⏳' 'glyf zohlední návrh existující jen na cizí větvi'
Assert-Match $r.Out 'DRAFT NA CIZÍ VĚTVI' 'graf hlásí draft na cizí větvi jako informaci'
Assert-Match $r.Out 'DRAFT NA VÍCE VĚTVÍCH' 'graf hlásí tentýž draft na dvou větvích (převzato z findings indexu)'
Assert-True ($r.Code -ne 1) 'nové findings nejsou skriptová chyba'

$without = Invoke-Graph @('-InputFile', $snap, '-EpicKey', 'DEMO-0', '-Check')
Assert-NotMatch $without.Out 'DRAFT NA CIZÍ VĚTVI' 'bez -IndexFile se nové findings netiskne'
Assert-Match $without.Out '💡|❔' 'bez -IndexFile zůstává tiket bez známého návrhu'

Write-Host '-IndexFile findings are scoped to THIS epic (mb-doc-index is project-wide)'
# fixtures/jira/clean.json (epic CLEAN-0, single child CLEAN-1) has zero
# prose/link findings of its own on -Check, so it isolates the -IndexFile
# contribution from status.json's pre-existing, unrelated CHYBA above.
$clean = Join-Path $PSScriptRoot 'fixtures/jira/clean.json'
$rCleanBase = Invoke-Graph @('-InputFile', $clean, '-EpicKey', 'CLEAN-0', '-Check')
Assert-Eq $rCleanBase.Code 0 'baseline: clean snapshot has no findings of its own'
# $idx (above) is entirely about DEMO-6, a ticket that does not belong to
# CLEAN-0 — regression coverage for the cross-epic leak the review caught
# (running -EpicKey CLEAN-0 with this same $idx used to still print DEMO-6).
$rCleanForeignIdx = Invoke-Graph @('-InputFile', $clean, '-EpicKey', 'CLEAN-0', '-Check', '-IndexFile', $idx)
Assert-NotMatch $rCleanForeignIdx.Out 'DRAFT NA CIZÍ VĚTVI' 'index entry belonging to another epic (DEMO-6) produces no finding here'
Assert-NotMatch $rCleanForeignIdx.Out 'DRAFT NA VÍCE VĚTVÍCH' 'index findings-array entry for another epic (demo_6) produces no finding here'
Assert-Eq $rCleanForeignIdx.Code 0 'foreign-epic index entries do not affect the exit code either'

$crossEpicIdx = Join-Path $PSScriptRoot 'fixtures/doc-index/cross-epic.json'
$rCross = Invoke-Graph @('-InputFile', $clean, '-EpicKey', 'CLEAN-0', '-Check', '-IndexFile', $crossEpicIdx)
Assert-Match $rCross.Out 'DRAFT NA CIZÍ VĚTVI' 'in-scope ticket (CLEAN-1) still gets its own foreign-branch finding'
Assert-Match $rCross.Out 'clean_1 je ve frontě' 'findings-array DRAFT NA VÍCE VĚTVÍCH for an in-scope ticket (CLEAN-1) renders'
Assert-NotMatch $rCross.Out 'demo_6 je ve frontě' 'findings-array DRAFT NA VÍCE VĚTVÍCH for a foreign ticket (DEMO-6) does not render'
Assert-Eq $rCross.Code 0 '-IndexFile findings alone (INFO/VAROVÁNÍ, hardcoded severity) never raise exit code to 2'

Write-Host '-IndexFile passes through mb-doc-index''s own actor model — no naive base+local recomputation'
# regression lock for the ruling: mb-doc-index excludes 'base' (shared
# baseline) and collapses 'local' with the actor's own remote ref, because an
# ordinary unclaimed backlog item already in the base ref shows up as both
# 'base' and 'local' in every clone. This index has exactly that base+local
# pair and an EMPTY findings array (mb-doc-index correctly did not consider
# it a duplicate) — a naive distinct-branch recount here must not invent one.
$baseLocalIdx = Join-Path $PSScriptRoot 'fixtures/doc-index/baselocal.json'
$rBaseLocal = Invoke-Graph @('-InputFile', $clean, '-EpicKey', 'CLEAN-0', '-Check', '-IndexFile', $baseLocalIdx)
Assert-NotMatch $rBaseLocal.Out 'DRAFT NA VÍCE VĚTVÍCH' 'base+local pair with empty index findings produces NO duplicate warning'
Assert-NotMatch $rBaseLocal.Out 'DRAFT NA CIZÍ VĚTVI' 'base/local are not foreign branches either'
Assert-Eq $rBaseLocal.Code 0 'base+local pair exits 0'

Write-Host '-IndexFile: a malformed entry (missing phase/branch) is a controlled failure, not a crash'
$malformedIdx = Join-Path $PSScriptRoot 'fixtures/doc-index/malformed.json'
$rMalformed = Invoke-Graph @('-InputFile', $clean, '-EpicKey', 'CLEAN-0', '-IndexFile', $malformedIdx)
Assert-Eq $rMalformed.Code 1 'malformed doc-index entry (missing slug/phase/branch) exits 1'
Assert-Match $rMalformed.Out 'Malformed doc-index entry' 'malformed entry produces the script''s own controlled error message'

Complete-Tests
