# Status-glyph tests (Jira mode): rozhodovací matice z
# ums/docs/design_epic_graph_test_jako_hotovo.md.
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

Complete-Tests
