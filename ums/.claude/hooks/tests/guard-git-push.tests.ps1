Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '_assert.ps1')

function Test-Cmd([string] $Command, [string] $Cwd = '') {
    $payload = @{ tool_name = 'Bash'; tool_input = @{ command = $Command } }
    if ($Cwd) { $payload.cwd = $Cwd }
    return Invoke-Hook ($payload | ConvertTo-Json -Depth 5 -Compress)
}

# ---------------------------------------------------------------------------
# allowed: simple, confidently-parsed pushes/fetches and unrelated commands
# ---------------------------------------------------------------------------
Assert-Eq (Test-Cmd 'git push origin feature/ums-1-alfa') '' 'push tiketové větve projde'
Assert-Eq (Test-Cmd 'git push -u origin feature/ums-1-alfa') '' 'push s -u projde'
Assert-Eq (Test-Cmd 'git push -q origin feature/ums-1-alfa') '' 'push s -q projde'
Assert-Eq (Test-Cmd 'git push -v origin feature/ums-1-alfa') '' 'push s -v projde'
Assert-Eq (Test-Cmd 'git push --set-upstream origin feature/ums-1-alfa') '' 'push s --set-upstream projde'
Assert-Eq (Test-Cmd 'git -C /repo push origin feature/ums-1-alfa') '' 'push s -C projde'
Assert-Eq (Test-Cmd 'git -c protocol.version=2 push origin feature/ums-1-alfa') '' 'push s -c protocol.version=2 na tiketovou větev projde'
Assert-Eq (Test-Cmd 'git status') '' 'jiný git příkaz se neřeší'
Assert-Eq (Test-Cmd 'echo "git push origin develop"') '' 'zmínka v echu se neřeší'
Assert-Eq (Test-Cmd 'git fetch origin') '' 'fetch bez refspecu projde'

# ---------------------------------------------------------------------------
# denied: shared branches (explicit refspec)
# ---------------------------------------------------------------------------
foreach ($c in @(
    'git push origin develop',
    'git push origin main',
    'git push origin release/2026.1',
    'git push origin HEAD:refs/heads/develop',
    'cd /repo && git push origin develop',
    'git -C /repo push origin master'
)) { Assert-Match (Test-Cmd $c) 'permissionDecision.*deny' "zamítnuto: $c" }

# ---------------------------------------------------------------------------
# denied: any flag outside the small allow-list (force, delete, all, mirror,
# clustered short flags, and parameterized long forms all fall out of this
# single rule — no per-flag enumeration to keep in sync)
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
    'git push --force-with-lease=refs/heads/x:deadbeef origin x'
)) { Assert-Match (Test-Cmd $c) 'permissionDecision.*deny' "zamítnuto: $c" }

# ---------------------------------------------------------------------------
# denied: detection bypasses (review round 1) — every shape below must still
# resolve to a `git push origin develop` and be denied, even though the old
# preceding-context regex missed all of them
# ---------------------------------------------------------------------------
Assert-Match (Test-Cmd ' git push origin develop') 'permissionDecision.*deny' 'zamítnuto: leading space'
Assert-Match (Test-Cmd "git status`ngit push origin develop") 'permissionDecision.*deny' 'zamítnuto: push na druhém řádku víceřádkového příkazu'
Assert-Match (Test-Cmd '(git push origin develop)') 'permissionDecision.*deny' 'zamítnuto: (git push …) subshell'
Assert-Match (Test-Cmd '`git push origin develop`') 'permissionDecision.*deny' 'zamítnuto: `git push …` v obrácených uvozovkách'
Assert-Match (Test-Cmd '$(git push origin develop)') 'permissionDecision.*deny' 'zamítnuto: $(git push …) substituce příkazu'
Assert-Match (Test-Cmd 'FOO=bar git push origin develop') 'permissionDecision.*deny' 'zamítnuto: FOO=bar prefix před git'
Assert-Match (Test-Cmd 'git -c protocol.version=2 push origin develop') 'permissionDecision.*deny' 'zamítnuto: git -c protocol.version=2 push … develop'

# ---------------------------------------------------------------------------
# denied: fetch that would overwrite a protected local ref
# ---------------------------------------------------------------------------
Assert-Match (Test-Cmd 'git fetch https://example.com/evil.git feature:refs/heads/develop') 'permissionDecision.*deny' 'zamítnuto: fetch přepisující lokální develop'

# ---------------------------------------------------------------------------
# bare push resolves the current branch from cwd
# ---------------------------------------------------------------------------
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("mbhook-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
& git init -b develop $tmp | Out-Null
Assert-Match (Test-Cmd 'git push' $tmp) 'permissionDecision.*deny' 'bare push na develop je zamítnut'
& git -C $tmp checkout -q -b feature/ums-9-x
Assert-Eq (Test-Cmd 'git push' $tmp) '' 'bare push na tiketové větvi projde'
Remove-Item -Recurse -Force $tmp

# ---------------------------------------------------------------------------
# fail-closed: current branch cannot be resolved (detached HEAD) -> deny.
# Note: a *fresh* `git init` with zero commits was NOT used here — verified
# empirically on this git version that `git branch --show-current` already
# reports the pending (unborn) branch name before any commit exists, so it
# does not exercise the "unresolvable" path. Detached HEAD reliably does
# (`git branch --show-current` returns an empty string).
# ---------------------------------------------------------------------------
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
Assert-Match (Test-Cmd 'git push' $tmp2) 'permissionDecision.*deny' 'bare push v odpojeném HEAD je zamítnut (nelze zjistit větev)'
Remove-Item -Recurse -Force $tmp2

# ---------------------------------------------------------------------------
# unparseable input must not block
# ---------------------------------------------------------------------------
Assert-Eq (Invoke-Hook 'not json') '' 'nerozparsovatelný vstup neblokuje'

Complete-Tests
