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
