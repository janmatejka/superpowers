Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '_assert.ps1')

# guard-git-push.mjs is NOT the enforcement boundary (fix round 2 demoted it
# after two rounds of adversarial review — see the real guarantee's own
# fixture-driven suite in pre-push.tests.ps1). This file only pins its
# reduced, best-effort, FAIL-OPEN responsibility: a friendly early warning
# for the common accident (a plainly-typed push that resolves to a protected
# branch), plus the one context-free `--no-verify` substring check, plus the
# fetch protected-destination check. Everything else must ALLOW.

function Test-Cmd([string] $Command, [string] $Cwd = '') {
    $payload = @{ tool_name = 'Bash'; tool_input = @{ command = $Command } }
    if ($Cwd) { $payload.cwd = $Cwd }
    return Invoke-Hook ($payload | ConvertTo-Json -Depth 5 -Compress)
}

# ---------------------------------------------------------------------------
# allowed: ordinary, unprotected pushes/fetches and unrelated commands
# ---------------------------------------------------------------------------
Assert-Eq (Test-Cmd 'git push origin feature/ums-1-alfa') '' 'push tiketové větve projde'
Assert-Eq (Test-Cmd 'git push -u origin feature/ums-1-alfa') '' 'push s -u projde'
Assert-Eq (Test-Cmd 'git push -q origin feature/ums-1-alfa') '' 'push s -q projde'
Assert-Eq (Test-Cmd 'git -C /repo push origin feature/ums-1-alfa') '' 'push s -C projde'
Assert-Eq (Test-Cmd 'git status') '' 'jiný git příkaz se neřeší'
Assert-Eq (Test-Cmd 'echo "git push origin develop"') '' 'zmínka v echu se neřeší'
Assert-Eq (Test-Cmd 'git fetch origin') '' 'fetch bez refspecu projde'

# ---------------------------------------------------------------------------
# denied: the one thing this layer still catches — a push that can be
# confidently parsed as simple AND whose target is a protected branch
# ---------------------------------------------------------------------------
foreach ($c in @(
    'git push origin develop',
    'git push origin main',
    'git push origin release/2026.1',
    'git push origin HEAD:refs/heads/develop',
    'cd /repo && git push origin develop',
    'git -C /repo push origin master',
    'FOO=bar git push origin develop',
    'git -c protocol.version=2 push origin develop'
)) { Assert-Match (Test-Cmd $c) 'permissionDecision.*deny' "zamítnuto (jednoduchý push na chráněnou větev): $c" }

# multi-invocation scan still finds a push on the second "line" of a command
Assert-Match (Test-Cmd "git status`ngit push origin develop") 'permissionDecision.*deny' 'zamítnuto: push za jiným git příkazem ve stejném řádku/víceřádku'

# ---------------------------------------------------------------------------
# allowed now (regression pinned in the NEW direction): an unrecognized flag
# means "not simple" and this layer is no longer the boundary — it defers to
# the pre-push hook instead of guessing. Real force/delete/mirror pushes are
# proven rejected end-to-end in pre-push.tests.ps1, not here.
# ---------------------------------------------------------------------------
foreach ($c in @(
    'git push --force origin feature/ums-1-alfa',
    'git push -f origin feature/ums-1-alfa',
    'git push --force-with-lease origin feature/ums-1-alfa',
    'git push origin +feature/ums-1-alfa',
    'git push origin :feature/ums-1-alfa',
    'git push --delete origin feature/ums-1-alfa',
    'git push --all origin',
    'git push --mirror origin',
    'git push -fu origin feature/ums-1-alfa',
    'git push -uf origin feature/ums-1-alfa',
    'git push -dq origin feature/ums-1-alfa',
    'git push --force-with-lease=refs/heads/x:deadbeef origin x',
    'git push --force origin develop'
)) { Assert-Eq (Test-Cmd $c) '' "povoleno (neznámý přepínač, o rozhodnutí se stará pre-push hook): $c" }

# ---------------------------------------------------------------------------
# allowed now (former over-denial from round 1, fixed by failing open on
# anything not cleanly parseable): quoted branch names, redirections,
# trailing comments, and a commit message that happens to mention "push"
# ---------------------------------------------------------------------------
foreach ($c in @(
    'git push origin "feature/ums-1-alfa"',
    'git push origin feature/ums-1-alfa 2>&1',
    'git push origin feature/ums-1-alfa # nasazení',
    'git commit -m "vysvetli git push origin develop"'
)) { Assert-Eq (Test-Cmd $c) '' "povoleno (dřívější nadměrné zamítnutí opraveno): $c" }

# ---------------------------------------------------------------------------
# `--no-verify` next to `push`: the one context-free substring check, since
# that flag would skip the real guarantee (the pre-push hook)
# ---------------------------------------------------------------------------
Assert-Match (Test-Cmd 'git push --no-verify origin feature/ums-1-alfa') 'permissionDecision.*deny' 'zamítnuto: --no-verify u pushe'
Assert-Match (Test-Cmd 'git push origin feature/ums-1-alfa --no-verify') 'permissionDecision.*deny' 'zamítnuto: --no-verify u pushe (na konci)'
Assert-Eq (Test-Cmd 'git commit --no-verify -m msg') '' '--no-verify bez zmínky o push neřeší (commit, ne push)'
Assert-Eq (Test-Cmd 'npm run push -- --no-verify') '' '--no-verify bez zmínky o gitu neřeší (žádný git v příkazu)'

# ---------------------------------------------------------------------------
# denied: fetch that would overwrite a protected local ref (unchanged from
# round 1 — best effort, same footing, not fail-closed for the rest of fetch)
# ---------------------------------------------------------------------------
Assert-Match (Test-Cmd 'git fetch https://example.com/evil.git feature:refs/heads/develop') 'permissionDecision.*deny' 'zamítnuto: fetch přepisující lokální develop'

# a WILDCARD destination names no branch, so the protected-name test alone
# never matched it — yet it overwrites every local branch, develop included
Assert-Match (Test-Cmd 'git fetch https://example.com/evil.git +refs/heads/*:refs/heads/*') 'permissionDecision.*deny' 'zamítnuto: fetch se žolíkem do lokálních větví'
Assert-Match (Test-Cmd 'git fetch origin refs/heads/*:*') 'permissionDecision.*deny' 'zamítnuto: žolík bez prefixu refs/ je taky lokální větev'
# ... while the everyday refspec into remote-tracking refs must keep passing
Assert-Eq (Test-Cmd 'git fetch origin +refs/heads/*:refs/remotes/origin/*') '' 'běžný refspec do remote-tracking refů projde'

# ---------------------------------------------------------------------------
# protected branches come from memory-bank/ums-repo.json's `protectedBranches`
# (task 3), the SAME source of truth as the pre-push hook — the contract
# explicitly warns that the two enforcement layers disagreeing is a defect.
# ---------------------------------------------------------------------------
function New-ConfigFixture([string] $Json) {
    $r = Join-Path ([IO.Path]::GetTempPath()) ("mbhookcfg-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Force -Path (Join-Path $r 'memory-bank') | Out-Null
    Set-Content -LiteralPath (Join-Path $r 'memory-bank\ums-repo.json') -Value $Json
    return $r
}

# 1. Configured pattern the built-in list does NOT know: `Branches/*` denies
# a push to `Branches/5.37` only once it comes from configuration.
$cfg1 = New-ConfigFixture @'
{
  "protectedBranches": ["Branches/*"]
}
'@
Assert-Match (Test-Cmd 'git push origin Branches/5.37' $cfg1) 'permissionDecision.*deny' 'zamítnuto: konfigurace obsahuje Branches/*, push na Branches/5.37 je zamítnutý'
# glob -> regex must stay case-insensitive: a pattern written as `Branches/*`
# has to match the lower-cased spelling too.
Assert-Match (Test-Cmd 'git push origin branches/5.37' $cfg1) 'permissionDecision.*deny' 'zamítnuto: shoda vzoru je case-insensitive (branches/5.37 vs. konfigurovaný Branches/*)'
Remove-Item -Recurse -Force $cfg1

# 2. THE LOAD-BEARING NEGATIVE: without any configuration, the SAME push must
# be ALLOWED, because the built-in fallback list does not know `Branches/*`.
# If this passed as denied, it would prove the guard denies everything rather
# than actually reading the configured list.
$noCfg = Join-Path ([IO.Path]::GetTempPath()) ("mbhooknocfg-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $noCfg | Out-Null
Assert-Eq (Test-Cmd 'git push origin Branches/5.37' $noCfg) '' 'povoleno: bez konfigurace zná guard jen vestavěný seznam, Branches/* v něm není'

# 3. Without configuration, a BUILT-IN name is still protected — the fallback
# itself must still work, not just "fall back to nothing".
Assert-Match (Test-Cmd 'git push origin develop' $noCfg) 'permissionDecision.*deny' 'zamítnuto i bez konfigurace: develop je součástí vestavěného seznamu'

# 4. Broken configuration (malformed JSON) must behave exactly like a missing
# one: MORE protection than "no fallback", never less.
$cfgBroken = New-ConfigFixture '{ this is not valid json'
Assert-Eq (Test-Cmd 'git push origin Branches/5.37' $cfgBroken) '' 'povoleno: rozbitá konfigurace padá na vestavěný seznam (Branches/* v něm chybí)'
Assert-Match (Test-Cmd 'git push origin develop' $cfgBroken) 'permissionDecision.*deny' 'zamítnuto: rozbitá konfigurace stále chrání vestavěný seznam'
Remove-Item -Recurse -Force $cfgBroken

# 4b. Valid JSON that is NOT AN OBJECT (array / number / null) — same fallback
# trap that hit task 3's PowerShell loader (a Critical there), in JS shape:
# `parsed.protectedBranches` on a non-object must not throw, it must miss.
foreach ($json in @('[1,2,3]', '42', 'null')) {
    $cfgNonObj = New-ConfigFixture $json
    Assert-Eq (Test-Cmd 'git push origin Branches/5.37' $cfgNonObj) '' "povoleno: konfigurace '$json' (validní JSON, ne objekt) padá na vestavěný seznam bez vyhození výjimky"
    Assert-Match (Test-Cmd 'git push origin develop' $cfgNonObj) 'permissionDecision.*deny' "zamítnuto: konfigurace '$json' stále chrání vestavěný seznam"
    Remove-Item -Recurse -Force $cfgNonObj
}

# 5. The rejection message must advise the REFSPEC form (task 4 changed the
# pre-push hint the same way) — a bare `git push origin <branch>` fails on a
# ticket clone that never had a local copy of the shared branch.
Assert-Match (Test-Cmd 'git push origin develop') 'HEAD:' 'zamítnutí radí refspecový tvar (obsahuje HEAD:)'

# ---------------------------------------------------------------------------
# UMS_ALLOW_SHARED_PUSH=1 — the human escape the pre-push hook honours. This
# early-warning layer must not stand in front of the command the layer itself
# hands the user, otherwise the escape is unusable in-session.
# ---------------------------------------------------------------------------
Assert-Eq (Test-Cmd 'UMS_ALLOW_SHARED_PUSH=1 git push origin develop') '' 'push sdílené větve s lidskou výjimkou projde'
Assert-Eq (Test-Cmd 'UMS_ALLOW_SHARED_PUSH=1 git push origin main') '' 'výjimka platí pro každou sdílenou větev'
# the escape lifts ONE rule; it is not a licence to disable every hook
Assert-Match (Test-Cmd 'UMS_ALLOW_SHARED_PUSH=1 git push --no-verify origin develop') 'permissionDecision.*deny' 'výjimka neomlouvá --no-verify'
# a different value is not the escape
Assert-Match (Test-Cmd 'UMS_ALLOW_SHARED_PUSH=0 git push origin develop') 'permissionDecision.*deny' 'jiná hodnota než 1 výjimkou není'
# the rejection itself must teach the way out
Assert-Match (Test-Cmd 'git push origin develop') 'UMS_ALLOW_SHARED_PUSH=1' 'zamítnutí pojmenuje únikovou cestu pro člověka'

# ---------------------------------------------------------------------------
# bare push resolves the current branch from cwd when it can
# ---------------------------------------------------------------------------
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("mbhook-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
& git init -b develop $tmp | Out-Null
Assert-Match (Test-Cmd 'git push' $tmp) 'permissionDecision.*deny' 'bare push na develop je zamítnut'
& git -C $tmp checkout -q -b feature/ums-9-x
Assert-Eq (Test-Cmd 'git push' $tmp) '' 'bare push na tiketové větvi projde'
Remove-Item -Recurse -Force $tmp

# unresolvable current branch (detached HEAD): round 1 denied this
# fail-closed; round 2 deliberately ALLOWS it — this layer no longer
# guesses when uncertain, it defers to the pre-push hook.
$tmp2 = Join-Path ([IO.Path]::GetTempPath()) ("mbhook-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $tmp2 | Out-Null
& git init -q -b wip $tmp2 | Out-Null
& git -C $tmp2 config user.email 'test@example.com'
& git -C $tmp2 config user.name 'Test'
'x' | Out-File -FilePath (Join-Path $tmp2 'f.txt') -Encoding utf8
& git -C $tmp2 add -A
& git -C $tmp2 commit -q -m init
$sha = (& git -C $tmp2 rev-parse HEAD).Trim()
& git -C $tmp2 checkout -q $sha
Assert-Eq (Test-Cmd 'git push' $tmp2) '' 'bare push v odpojeném HEAD teď projde (nejistota = allow, ne deny)'
Remove-Item -Recurse -Force $tmp2

# ---------------------------------------------------------------------------
# unparseable input must not block
# ---------------------------------------------------------------------------
Assert-Eq (Invoke-Hook 'not json') '' 'nerozparsovatelný vstup neblokuje'

Complete-Tests
