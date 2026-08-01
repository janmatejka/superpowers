Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '_assert.ps1')
. (Join-Path $PSScriptRoot 'new-fixture-repo.ps1')

$fx = New-FixtureRepo

# 1) foreign active work with NOTHING declared and nothing active locally =
# information only, exit 0. NB: on its own this says nothing about tickets —
# with an empty local set the run cannot tell "another ticket" from "the same
# ticket", which is exactly the dead spot test 1c pins. The two cases are
# separated by declaring the intent (1a / 1c below).
$r = Invoke-Index @('-RepoPath', $fx.Work, '-BaseRef', 'origin/develop', '-NoFetch')
Assert-Eq $r.Code 0 'bez deklarovaného záměru a bez lokální práce běh nezastaví'
Assert-Match $r.Out 'CIZÍ AKTIVNÍ PRÁCE' 'cizí aktivní práce se vypíše jako informace'
Assert-Match $r.Out 'DRAFT NA VÍCE VĚTVÍCH.*ums_2_beta' 'duplicitní draft je varování'
Assert-Match $r.Out 'FRONTA I DOKONČENO.*ums_3_gama' 'obživlá fronta je varování'

# 1b) NEGATIVE: a next/ document already sitting unmodified in the base
# commit shows up as BOTH 'base' and 'local' (every branch descends from it)
# but that is ONE actor, not a duplicate draft — must never fire a warning.
Assert-Match $r.Out 'ums_6_fronta' 'fronta shodná se základnou (base+local) se v tabulce zobrazí'
Assert-NotMatch $r.Out 'DRAFT NA VÍCE VĚTVÍCH.*ums_6_fronta' 'shoda base+local není falešný duplicitní draft'

# ---------------------------------------------------------------------------
# DECLARED INTENT (-Jira / -Slug). The cross-clone collision check runs during
# Target-MB discovery, i.e. BEFORE the design document exists — the local set
# is empty then, so a local×foreign comparison alone cannot fire and the
# colleague's work on the same ticket looks like ordinary parallel work. The
# caller therefore declares what it is about to start.
# ---------------------------------------------------------------------------

# 1a) declared intent on ANOTHER ticket: foreign active work stays INFO, exit 0
$other = Invoke-Index @('-RepoPath', $fx.Work, '-BaseRef', 'origin/develop', '-NoFetch', '-Jira', 'UMS-7')
Assert-Eq $other.Code 0 'cizí aktivní práce JINÉHO tiketu běh nezastaví ani při deklarovaném záměru'
Assert-Match $other.Out 'CIZÍ AKTIVNÍ PRÁCE.*ums_1_alfa' 'cizí práce jiného tiketu zůstává jen informací'
Assert-NotMatch $other.Out 'KOLIZE AKTIVNÍ PRÁCE' 'jiný tiket nevyvolá kolizi'

# 1b) the same for a declared slug that nobody else works on
$otherSlug = Invoke-Index @('-RepoPath', $fx.Work, '-BaseRef', 'origin/develop', '-NoFetch', '-Slug', 'ums_7_neco')
Assert-Eq $otherSlug.Code 0 'deklarovaný slug, na kterém nikdo nepracuje, běh nezastaví'
Assert-NotMatch $otherSlug.Out 'KOLIZE AKTIVNÍ PRÁCE' 'neznámý slug nevyvolá kolizi'

# 1c) declared intent on THE SAME ticket with an EMPTY local set = collision.
# This is the discovery-time dead spot: without -Jira the identical situation
# above exits 0.
$dupTicket = Invoke-Index @('-RepoPath', $fx.Work, '-BaseRef', 'origin/develop', '-NoFetch', '-Jira', 'UMS-1')
Assert-Eq $dupTicket.Code 2 'deklarovaný tiket aktivní na cizí větvi = exit 2 i bez lokálního dokumentu'
Assert-Match $dupTicket.Out 'KOLIZE AKTIVNÍ PRÁCE' 'kolize deklarovaného tiketu se hlásí jako CHYBA'
Assert-Match $dupTicket.Out 'origin/feature/ums-1-alfa' 'hlášení nese větev cizího aktéra'
Assert-Match $dupTicket.Out '\d{4}-\d{2}-\d{2}' 'hlášení nese datum posledního commitu'
Assert-NotMatch $dupTicket.Out 'CIZÍ AKTIVNÍ PRÁCE.*ums_1_alfa' 'tentýž záznam se nehlásí zároveň jako kolize i jako cizí práce'

# 1d) the same via -Slug (the work item may be declared before the ticket is known)
$dupSlug = Invoke-Index @('-RepoPath', $fx.Work, '-BaseRef', 'origin/develop', '-NoFetch', '-Slug', 'ums_1_alfa')
Assert-Eq $dupSlug.Code 2 'deklarovaný slug aktivní na cizí větvi = exit 2 i bez lokálního dokumentu'
Assert-Match $dupSlug.Out 'KOLIZE AKTIVNÍ PRÁCE' 'kolize deklarovaného slugu se hlásí jako CHYBA'

# 2) the SAME slug active locally and on a foreign branch = collision, exit 2
$local = Join-Path $fx.Work 'memory-bank/proposals/active/design_ums_1_alfa.md'
New-Item -ItemType Directory -Force -Path (Split-Path $local) | Out-Null
Set-Content -LiteralPath $local -Encoding UTF8 -Value @('# Návrh: alfa', '', '- **Jira:** UMS-1')
$c = Invoke-Index @('-RepoPath', $fx.Work, '-BaseRef', 'origin/develop', '-NoFetch')
Assert-Eq $c.Code 2 'stejný slug aktivní lokálně i na cizí větvi = exit 2'
Assert-Match $c.Out 'KOLIZE AKTIVNÍ PRÁCE' 'kolize se hlásí jako CHYBA'
Assert-Match $c.Out 'origin/feature/ums-1-alfa' 'hlášení kolize nese větev'
Assert-Match $c.Out '\d{4}-\d{2}-\d{2}' 'hlášení kolize nese datum posledního commitu'

# 3) the same TICKET under a different slug is a collision too
Remove-Item -LiteralPath $local
$other = Join-Path $fx.Work 'memory-bank/proposals/active/design_ums_1_jinak.md'
Set-Content -LiteralPath $other -Encoding UTF8 -Value @('# Návrh: jinak', '', '- **Jira:** UMS-1')
$t = Invoke-Index @('-RepoPath', $fx.Work, '-BaseRef', 'origin/develop', '-NoFetch')
Assert-Eq $t.Code 2 'tentýž tiket pod jiným slugem je také kolize'

Remove-Item -Recurse -Force (Split-Path $fx.Work)

# 4) NEGATIVE: the actor's own already-pushed branch must never self-collide.
# Ordinary git hygiene — push your own active work to your own origin
# feature branch — must not be indistinguishable from a genuine two-actor
# collision, and must not even be reported as someone else's parallel work.
$fx2 = New-FixtureRepo
Invoke-Git $fx2.Work @('checkout', '-b', 'feature/own-work', 'develop') | Out-Null
Add-Doc $fx2.Work 'memory-bank/proposals/active/design_ums_9_vlastni.md' 'UMS-9'
Invoke-Git $fx2.Work @('commit', '-m', 'own active work') | Out-Null
Invoke-Git $fx2.Work @('push', '-u', 'origin', 'feature/own-work') | Out-Null
$own = Invoke-Index @('-RepoPath', $fx2.Work, '-BaseRef', 'origin/develop', '-NoFetch')
Assert-Eq $own.Code 0 'vlastní už pushnutá větev se sama se sebou nesrazí'
Assert-NotMatch $own.Out 'KOLIZE AKTIVNÍ PRÁCE' 'vlastní práce se nehlásí jako kolize se sebou samou'
Assert-NotMatch $own.Out 'CIZÍ AKTIVNÍ PRÁCE.*ums_9_vlastni' 'vlastní práce se nehlásí ani jako cizí'

# 4b) NEGATIVE for declared intent: declaring the ticket I am already working
# on must not collide with my own pushed branch either — the own-remote-ref
# exclusion has to hold for BOTH collision sources, not just local×foreign.
$ownDecl = Invoke-Index @('-RepoPath', $fx2.Work, '-BaseRef', 'origin/develop', '-NoFetch', '-Jira', 'UMS-9', '-Slug', 'ums_9_vlastni')
Assert-Eq $ownDecl.Code 0 'deklarovaný záměr na VLASTNÍM už pushnutém tiketu nekoliduje sám se sebou'
Assert-NotMatch $ownDecl.Out 'KOLIZE AKTIVNÍ PRÁCE' 'vlastní pushnutá větev není kolize ani při deklarovaném záměru'

Remove-Item -Recurse -Force (Split-Path $fx2.Work)
Complete-Tests
